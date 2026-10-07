-- HeroSync 重复计算回归：真实 Panel/Sync/Power/EquipmentPower/OfflineService 源码隔离加载。
-- 只读声明的 Lua 源；不加载 main/真实 PlayerStore/PDM/存档，不构建。
-- -hero-sync-baseline 记录旧重复次数；最终数据断言相同，刷新前缓存的新增时序约束仅新版检查。
local TAG = "[startup_hero_sync_test]"
local assertions, failures = 0, 0
local baseline = false
for _, argument in ipairs(GetArguments()) do
    if argument == "-hero-sync-baseline" then baseline = true end
end
local function check(value, label)
    assertions = assertions + 1
    if not value then failures = failures + 1 end
    print(TAG .. (value and " PASS " or " FAIL ") .. label)
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function noop() end

local function fixture()
    local counts = { rebuild = 0, refresh = 0, calc = 0, context = 0, invalidations = 0, nav = 0,
        fullContext = 0, wornContext = 0, wornBatch = 0, hydrate = 0 }
    local trace, notifications, legacy, invalidated, progress, observations = {}, {}, {}, {}, {}, {}
    -- 重复/纯exp通知不发布新快照；保留实际事件的最后值作完整缓存对照。
    local latestSnapshot = {}
    local modules, stored, subscriptions = {}, {}, {}
    local loaded, loading = {}, {}
    local clock = 1700000000
    ---@type table
    local panel
    ---@type table
    local powerApi
    ---@type table
    local drawContext
    local inputContext = {}
    ---@type table
    local detailContext
    local offlineOpen = false
    ---@type table|nil
    local offlinePreview = nil
    local preparing, primingOffline = false, false
    local gamePower = 0
    local function record(kind) trace[#trace + 1] = kind end
    local function resetCounts()
        for key in pairs(counts) do counts[key] = 0 end
        trace, notifications, legacy, invalidated, progress, observations = {}, {}, {}, {}, {}, {}
    end
    local mocks = {}
    local function snapshot(kind)
        local powers = {}
        for team = 1, 3 do powers[team] = panel.getTotalPower(team) end
        observations[#observations + 1] = {
            kind = kind, powers = powers, ready = panel.isHeroesDataApplied(),
            roster = copy(drawContext.getHeroRoster()), rosterPower = copy(drawContext.getRosterPowerCache()),
            slots = copy(panel.getTeamSlotIds()),
        }
    end
    mocks["runtime.ClientDispatcher"] = {
        get = function(key) return modules[key] end,
        subscribe = function(key, callback)
            subscriptions[key] = subscriptions[key] or {}
            subscriptions[key][#subscriptions[key] + 1] = callback
        end,
    }
    mocks["core.PlayerStore"] = {
        Get = function(key) return stored[key] end,
        Subscribe = function() end,
    }
    mocks["core.GameState"] = {
        getLevel = function() return 100 end,
        setPower = function(value)
            if value ~= gamePower then
                gamePower = value
                legacy[#legacy + 1] = value
                record("legacy")
                snapshot("legacy")
            end
        end,
    }
    mocks["ui.character.detail.CharacterDetail"] = {
        init = noop, markPowerDirty = noop,
        setContext = function(value) detailContext = value end,
        hasAnyUpgradeForHero = function() return false end,
        hasAwakeningUpgrade = function() return false end,
    }
    mocks["ui.hud.BottomNav"] = {
        setBadge = noop,
        refreshTownBadge = function() counts.nav = counts.nav + 1; record("nav") end,
    }
    mocks["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end }
    mocks["ui.character.panel.CharacterPanelDraw2"] = {
        MAX_SLOTS = 4, MAX_PER_ROW = 5, CARD_W = 198, CARD_H = 351,
        CARD_SPACING = 205, CARD_CY = 300, ROW1_CY = 600, ROW_SPACING = 200,
        NAME_BG_DY = 100, NAME_BG_H = 40, SCROLL_TOP = 450, SCROLL_BOTTOM = 2200,
        SCROLL_LEFT = 0, SCROLL_RIGHT = 1080, DESIGN_W = 1080, ROSTER_BOTTOM_DY = 130,
        getSlotCX = function(index) return index * 205 end,
        setContext = function(value) drawContext = value end,
        initImages = noop, getSharedImages = function() return {} end,
    }
    mocks["ui.character.panel.CharacterInput"] = {
        bind = function(deps) inputContext = deps; return { handleInput = noop } end,
    }
    mocks["systems.GameSFX"] = { play = noop }
    mocks["systems.TutorialManager"] = { notifyHeroDeployed = noop }
    mocks["ui.character.panel.CharacterProgress"] = { bind = function() return {} end }
    mocks["ui.church.talent.TalentStarMap"] = {
        -- 外围UI只提供明确的静态节点文字，真实解析/估值仍执行TalentEffect/CombatPower。
        getNode = function(id)
            return id == 0 and { effect = "力量+2", st = "small" } or nil
        end,
    }
    mocks["ui.battle.tri.BattleTriPage"] = {
        invalidateTeams = function(selected)
            invalidated[#invalidated + 1] = copy(selected)
            record("invalidate")
            snapshot("invalidate")
        end,
        refreshHeroProgressTeams = function(selected, classes)
            progress[#progress + 1] = { teams = copy(selected), classes = copy(classes) }
            record("progress")
            snapshot("progress")
        end,
    }
    mocks["ui.hud.popup.OfflineRewardPanel"] = {
        isOpen = function() return offlineOpen end,
        refreshHeroPreview = function(value)
            offlinePreview = value
            record("offline-panel")
            snapshot("offline-panel")
        end,
    }
    mocks["rules.character.PlayerDataManager"] = {
        GetModule = function(uid, key)
            assert(uid == 1, "isolated PDM uid")
            return modules[key]
        end,
        MarkDirty = function(uid, key)
            assert(primingOffline and uid == 1 and key == "session", "只读预览不得发奖或保存")
        end,
    }
    mocks["rules.currency.CurrencyService"] = {}
    mocks["rules.hero.HeroService"] = {}
    mocks["systems.OfflineCalc"] = {
        MIN_SECONDS = 1,
        calcTeamOfflineRewards = function()
            return { seconds = 60, gold = 0, diamond = 0, adventureExp = 0, adventurerExp = 600,
                kills = 0, equipSeeds = {}, scrollDrops = {}, teamRewards = {
                    { teamIdx = 1, heroCount = 2, adventurerExp = 200 },
                    { teamIdx = 2, heroCount = 2, adventurerExp = 400 },
                    { teamIdx = 3, heroCount = 1, adventurerExp = 600 },
                } }
        end,
    }
    local realNames = {
        ["ui.character.panel.CharacterPanel"] = true,
        ["ui.character.panel.CharacterHeroSync"] = true,
        ["ui.character.panel.CharacterDeploy"] = true,
        ["ui.character.panel.CharacterPower"] = true,
        ["ui.character.panel.CharacterRosterSort"] = true,
        ["rules.offline.OfflineService"] = true,
        ["core.EventBus"] = true, ["core.BattleLayout"] = true,
        ["core.NumberUtil"] = true,
        ["systems.AttributeDef"] = true, ["systems.UnitAttributes"] = true,
        ["systems.EquipmentSystem"] = true, ["systems.EquipmentSetSystem"] = true,
        ["systems.EquipmentSetRuntime"] = true, ["systems.EquipmentPower"] = true,
        ["systems.CombatPower"] = true, ["systems.CombatFormula"] = true,
        ["systems.TalentEffect"] = true, ["systems.AwakeningGrowth"] = true,
        ["systems.CombatPowerEstimate"] = true, ["systems.ArtifactBridge"] = true,
        ["systems.ArtifactRuntime"] = true, ["systems.ExtraTalentSystem"] = true,
        ["systems.StatusEffectManager"] = true, ["systems.LootBoxSystem"] = true,
        ["systems.BattleDiag"] = true, ["systems.ThreatManager"] = true,
        ["systems.ClassGateRuntime"] = true, ["systems.MapAffixSystem"] = true,
    }
    local allowedPaths = {}
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.File = function() error("禁止访问真实玩家档") end
    env.os = setmetatable({ time = function() return clock end }, { __index = os })
    env.require = function(name)
        if mocks[name] then return mocks[name] end
        if loaded[name] then return loaded[name] end
        assert(realNames[name] or name:match("^config%.") or name:match("^shared%."),
            "未声明依赖/真实存档入口: " .. name)
        assert(not loading[name], "unexpected cycle: " .. name)
        loading[name] = true
        local path = name:gsub("%.", "/") .. ".lua"
        allowedPaths[path] = true
        local file = assert(cache:GetFile(path), "missing source " .. path)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local value = assert(load(table.concat(lines, "\n"), "@hero-sync-isolated/" .. path, "t", env))()
        loading[name] = nil
        loaded[name] = value
        if name == "ui.character.panel.CharacterHeroSync" then
            local bind = value.bind
            value.bind = function(deps)
                local rebuild, refresh = deps.rebuildRoster, deps.refreshPowerCache
                deps.rebuildRoster = function()
                    counts.rebuild = counts.rebuild + 1
                    record("rebuild")
                    return rebuild()
                end
                deps.refreshPowerCache = function()
                    counts.refresh = counts.refresh + 1
                    record("refresh")
                    return refresh()
                end
                return bind(deps)
            end
        elseif name == "ui.character.panel.CharacterPower" then
            local bind = value.bind
            value.bind = function(deps)
                local api = bind(deps)
                local calc, refresh = api.calcHeroPower, api.refreshPowerCache
                api.calcHeroPower = function(...)
                    counts.calc = counts.calc + 1
                    return calc(...)
                end
                api.refreshPowerCache = function()
                    if not preparing then record("power-refresh") end
                    return refresh()
                end
                powerApi = api
                return api
            end
        elseif name == "systems.EquipmentSystem" then
            local hydrate = value.hydrate
            value.hydrate = function(...)
                counts.hydrate = counts.hydrate + 1
                return hydrate(...)
            end
        elseif name == "systems.EquipmentPower" then
            local context, invalidate = value.buildContext, value.invalidate
            value.buildContext = function(...)
                counts.context = counts.context + 1
                counts.fullContext = counts.fullContext + 1
                return context(...)
            end
            if value.buildWornContext then
                local worn, batch = value.buildWornContext, value.createWornBatch
                value.buildWornContext = function(...)
                    counts.context = counts.context + 1
                    counts.wornContext = counts.wornContext + 1
                    return worn(...)
                end
                value.createWornBatch = function(...)
                    counts.wornBatch = counts.wornBatch + 1
                    return batch(...)
                end
            end
            value.invalidate = function()
                counts.invalidations = counts.invalidations + 1
                return invalidate()
            end
        elseif name == "rules.offline.OfflineService" then
            local calc = value.CalcOnEnter
            value.CalcOnEnter = function(uid)
                primingOffline = true
                local ok, result = pcall(calc, uid)
                primingOffline = false
                assert(ok, result)
                return result
            end
            local rebuild = value.RebuildHeroPreview
            value.RebuildHeroPreview = function(uid)
                record("offline-service")
                snapshot("offline-service")
                return rebuild(uid)
            end
        end
        return value
    end
    -- 被测模块只能通过上方声明的源码加载器读文件，不暴露真实 File 或缓存读档口。
    env.cache = { GetFile = function(_, path)
        assert(allowedPaths[path], "禁止未声明资源/存档读取: " .. tostring(path))
        return cache:GetFile(path)
    end }
    panel = env.require("ui.character.panel.CharacterPanel")
    local bus, events = env.require("core.EventBus"), env.require("config.GameEvents")
    bus.on(events.TEAM_POWER_CHANGED, function(value)
        latestSnapshot = copy(value)
        notifications[#notifications + 1] = copy(value)
        record("team-event")
        snapshot("team-event")
    end)
    preparing = true
    panel.init(nil)
    preparing = false
    resetCounts()
    local function apply(data, viaSubscription, fallback)
        modules.heroes = fallback and nil or data
        if fallback then modules.heroes = nil end
        stored.heroes = fallback and data or nil
        if viaSubscription then
            for _, callback in ipairs(subscriptions.heroes or {}) do callback() end
        else
            return panel.setHeroesData(data)
        end
    end
    return {
        panel = panel, load = env.require, counts = counts, reset = resetCounts, apply = apply,
        openOffline = function(value) offlineOpen = value end,
        deploy = function(heroId, slot)
            panel.handleInput(0, 0) -- 仅bind，外围输入不触发；部署执行真实CharacterDeploy。
            return inputContext.deployHeroToSlot(heroId, slot)
        end,
        modules = modules, stored = stored,
        data = function()
            return { trace = trace, events = notifications, legacy = legacy, invalidated = invalidated,
                progress = progress, observations = observations, preview = offlinePreview,
                roster = drawContext.getHeroRoster(), rosterPower = drawContext.getRosterPowerCache(),
                detail = detailContext, power = powerApi, gamePower = gamePower, snapshot = latestSnapshot }
        end,
    }
end

local function heroes()
    local roster = {}
    for _, id in ipairs({ 1, 2, 3, 4, 5, 8 }) do
        roster[tostring(id)] = { level = 60 + id, exp = id, shards = id * 2,
            awakening = {}, extraTalent = {} }
    end
    roster["4"].advBranch = { first = 101 }
    roster["25"] = { shards = 9 }
    return { roster = roster, deployed = { 1, 0, 2, 0 }, teams = {
        { slots = { 1, 0, 2, 0 } }, { slots = { 0, 3, 0, 4 } }, { slots = { 5, 0, 0, 0 } },
    } }
end

local function rosterCheck(f, label)
    local data, cp = f.data(), f.panel
    local ids, byId = {}, {}
    for index, entry in ipairs(data.roster) do
        ids[#ids + 1] = entry.heroId
        byId[entry.heroId] = entry
        if entry.owned then
            check(data.rosterPower[index] == data.detail.calcHeroPower(entry.heroId),
                label .. " 名册战力同正式口径 hero=" .. entry.heroId)
        else
            check(data.rosterPower[index] == 0, label .. " 未拥有名册战力为0 hero=" .. entry.heroId)
        end
    end
    check(#ids == #f.load("config.HeroConfig").getAllIds(), label .. " 名册覆盖全部英雄")
    check(byId[8].owned and not byId[25].owned and byId[25].shards == 9,
        label .. " 未部署拥有与仅碎片英雄保留")
    check(cp.getOwnedHero(1).level == 61 and cp.getOwnedHero(1).exp == 1,
        label .. " 字符串名册键水合等级/经验")
    local lastDeployed, firstReserve = 0, #ids + 1
    for index, id in ipairs(ids) do
        if cp.isHeroDeployed(id) then lastDeployed = index
        elseif cp.isOwned(id) then firstReserve = math.min(firstReserve, index) end
    end
    check(lastDeployed < firstReserve, label .. " 三队出战均排未出战英雄之前")
end

local function finalCheck(f, label, unchanged)
    local data, cp = f.data(), f.panel
    check(cp.isHeroesDataApplied(), label .. " ready=true")
    local snapshot = unchanged and not baseline and data.snapshot or data.events[#data.events]
    check(snapshot and snapshot.ready == true, label .. " 最终战力快照ready=true")
    for team = 1, 3 do
        local slots, powers = cp.getTeamSlotsData(team)
        local total = 0
        for slot = 1, 4 do
            local entry = slots[slot]
            local expected = entry.state == "occupied"
                and data.detail.calcHeroPower(entry.heroId, slot, team) or 0
            check((powers[slot] or 0) == expected, label .. " 正式队/槽缓存 " .. team .. ":" .. slot)
            total = total + expected
        end
        check(cp.getTotalPower(team) == total and snapshot and snapshot.powers[team] == total,
            label .. " 队" .. team .. "总战力与完整快照同源")
    end
    check(data.gamePower == cp.getTotalPower(1), label .. " 顶栏只取队1")
    for _, observation in ipairs(data.observations) do
        check(observation.ready, label .. " 即时回调ready " .. observation.kind)
        if not baseline then
            for team = 1, 3 do
                check(observation.powers[team] == cp.getTotalPower(team),
                    label .. " 即时回调最终缓存 " .. observation.kind .. " T" .. team)
            end
        end
    end
end

local function countsCheck(f, label, deployed, viaSubscription, unchanged)
    local count, data = copy(f.counts), f.data()
    local skipped = unchanged and not baseline
    local refreshCount = skipped and 0 or 1
    print(string.format("%s COUNTS mode=%s case=%s rebuild=%d refresh=%d calc=%d context=%d invalidate=%d events=%d",
        TAG, baseline and "baseline" or "optimized", label, count.rebuild, count.refresh,
        count.calc, count.context, count.invalidations, #data.events))
    local ownedCount = 0
    for _, entry in ipairs(data.roster) do if entry.owned then ownedCount = ownedCount + 1 end end
    check(count.rebuild == (baseline and 2 or refreshCount), label .. " 精确rebuild次数")
    check(count.refresh == refreshCount, label .. " Sync精确refresh次数")
    check(count.invalidations == ((baseline and viaSubscription) and 2 or refreshCount), label .. " 实际Power刷新/失效次数")
    check(#data.events == ((baseline and viaSubscription) and 2 or refreshCount), label .. " 完整快照仅必要时最终发布一次")
    -- 名册重建只做视图排序，正式Power同轮一次按heroId/真实神器队槽评分，不重复调用公开calc。
    check(count.calc == (baseline and (deployed + ownedCount * 2) or 0), label .. " 直接calc精确次数")
    check(count.context == (baseline and (deployed + ownedCount * (viaSubscription and 4 or 3))
        or ownedCount * refreshCount), label .. " 真实EquipmentPower上下文精确次数")
    local business = {}
    for _, kind in ipairs(data.trace) do
        if kind == "invalidate" or kind == "offline-service" or kind == "offline-panel"
            or kind == "nav" or kind == "progress" then business[#business + 1] = kind end
    end
    if not baseline and not skipped then
        ---@type number|nil
        local eventIndex = nil
        ---@type number|nil
        local firstReader = nil
        for index, kind in ipairs(data.trace) do
            if kind == "team-event" then eventIndex = index end
            if not firstReader and (kind == "invalidate" or kind == "offline-service") then firstReader = index end
        end
        check(not firstReader or (eventIndex and eventIndex < firstReader), label .. " 最终刷新先于即时读取回调")
    end
    return business
end

-- 真正的正式战力对照：保留通用完整库存作oracle，不用新函数自己验证自己。
local function wornContextChecks()
    local f = fixture()
    local EP, Eq = f.load("systems.EquipmentPower"), f.load("systems.EquipmentSystem")
    local EC, ESC = f.load("config.EquipmentConfig"), f.load("config.EquipmentSetConfig")
    local AD = f.load("systems.AttributeDef")
    check(type(EP.buildWornContext) == "function" and type(EP.createWornBatch) == "function",
        "穿戴专用入口存在，通用入口独立")
    if not EP.buildWornContext then return end
    local ids = { 1, 2, 3, 4, 8, 9, 12, 14, 15, 18, 19, 20 }
    local roster, teams = {}, {}
    for index, id in ipairs(ids) do
        roster[index % 2 == 0 and tostring(id) or id] = {
            level = 100 + index, exp = index, awakening = { [1] = true, [2] = true, [3] = true },
            extraTalent = { issuedCards = 12, totalKills = 40 },
        }
        local team = math.floor((index - 1) / 4) + 1
        teams[team] = teams[team] or { slots = {} }
        teams[team].slots[(index - 1) % 4 + 1] = index % 2 == 0 and tostring(id) or id
    end
    local templateIds = {}
    for id in pairs(EC.ITEMS) do templateIds[#templateIds + 1] = id end
    table.sort(templateIds)
    local equipment = { inventory = {}, equipped = {}, nextSeq = 1001, unrelated = { preserve = true } }
    for index = 1, 1000 do
        equipment.inventory[index % 2 == 0 and index or tostring(index)] = {
            templateId = templateIds[(index - 1) % #templateIds + 1], level = 85,
            quality = 6, ascendLevel = index % 21, affixMult = 1.2,
            affixes = { { affixId = 1, quality = 3, value = 7, ascBonus = 0.5 } },
        }
    end
    local function templateFor(slot, setId)
        for _, id in ipairs(templateIds) do
            local template = EC.ITEMS[id]
            if template.slot == slot and (not setId or ESC.getSetIdForTemplate(template) == setId) then return id end
        end
        error("missing real template " .. slot .. "/" .. tostring(setId))
    end
    for index, id in ipairs(ids) do
        local slots = {}
        equipment.equipped[index % 2 == 0 and tostring(id) or id] = slots
        local setId = id == 19 and "last_rite" or id == 20 and "starless" or id == 3 and "nitros" or nil
        for slotIndex, slot in ipairs(EC.SLOTS) do
            local seq = (index - 1) * 6 + slotIndex
            equipment.inventory[seq % 2 == 0 and seq or tostring(seq)].templateId = templateFor(slot, setId)
            slots[slot] = seq % 2 == 0 and seq or tostring(seq)
        end
    end
    equipment.inventory[1000].templateId = "C1" -- 未穿戴但合法的候选，不能只测拒绝路径。
    local artifacts = { bag = {
        { id = "1", artifactId = 7, quality = 3, valueRatio = 1234 },
        { id = "2", artifactId = 8, quality = 4, valueRatio = 2345 },
        { id = "3", artifactId = 14, quality = 4, valueRatio = 3456 },
    }, equippedByTeam = { [1] = { [2] = { "1" } }, [2] = { [3] = { "2" } }, [3] = { [4] = { "3" } } } }
    f.load("shared.artifact.ArtifactSchema").normalizeModule(artifacts)
    local options = { heroes = { roster = roster, teams = teams, deployed = { 1, 2, 3, 4 } },
        equipment = equipment, artifacts = artifacts, talents = { litNodes = { 0, 113, 115, 124, 125, 126, 128 } } }
    local before = copy(options)
    local inventoryWalks = 0
    setmetatable(equipment.inventory, { __pairs = function(value)
        inventoryWalks = inventoryWalks + 1
        return next, value, nil
    end })
    local function contextSame(light, full, label)
        check(light and full and light.currentPower == full.currentPower, label .. " 未取整战力严格相同")
        if not light or not full then return end
        check(light.hero.partySlot == full.hero.partySlot and light.hero.teamIdx == full.hero.teamIdx,
            label .. " 神器真实队/槽一致")
        check(#light.teamUnits == #full.teamUnits, label .. " 本队去重/顺序一致")
        for index, unit in ipairs(full.teamUnits) do
            local actual = light.teamUnits[index]
            check(actual and actual.heroId == unit.heroId and same(actual.attrs.final, unit.attrs.final)
                and same(actual.attrs.modifiers, unit.attrs.modifiers) and same(actual.attrs._setRows, unit.attrs._setRows)
                and same(actual.artifactEffects, unit.artifactEffects), label .. " 完整属性/套装/神器 " .. index)
        end
    end
    inventoryWalks = 0
    f.reset()
    local lightStarted = os.clock()
    local batch = EP.createWornBatch(options)
    for _, id in ipairs(ids) do EP.buildWornContext(id, options, batch) end
    local lightSeconds = os.clock() - lightStarted
    local lightCounts, lightWalks = copy(f.counts), inventoryWalks
    check(lightCounts.hydrate == 72 and lightWalks == 0,
        "1000库存12拥有三队批次仅hydrate72已穿项，遍历全inventory=0")
    check(Eq.getInventoryCount(batch.equipmentData) == 72, "轻快照无928未穿候选")
    inventoryWalks = 0
    f.reset()
    local fullStarted = os.clock()
    for _, id in ipairs(ids) do EP.buildContext(id, options) end
    local fullSeconds = os.clock() - fullStarted
    local fullCounts, fullWalks = copy(f.counts), inventoryWalks
    check(fullCounts.hydrate == 12000 and fullWalks == 12,
        "旧通用ctx对照确实hydrate12000项/完整库存12次")
    print(string.format("%s WORN_COUNTS fullHydrate=%d wornHydrate=%d fullWalks=%d wornWalks=%d",
        TAG, fullCounts.hydrate, lightCounts.hydrate, fullWalks, lightWalks))
    print(string.format("%s WORN_CPU fullMs=%.3f wornMs=%.3f (isolated os.clock CPU, not device FPS)",
        TAG, fullSeconds * 1000, lightSeconds * 1000))
    for _, id in ipairs(ids) do
        contextSame(EP.buildWornContext(id, options, batch), EP.buildContext(id, options), "1000库存 hero=" .. id)
    end
    check(EP.buildWornContext(19, options).hero.attrs._setSix == "last_rite",
        "真实司仪六件光环有效非空")
    check(EP.buildWornContext(20, options).hero.attrs._setFour == "starless"
        and EP.buildWornContext(3, options).hero.attrs._setFour == "nitros", "真实无光/硝烟开战属性有效")
    check(same(options, before), "轻/完整上下文均不写英雄/装备/神器/天赋源数据")
    -- 候选必须仍在完整库存中，且完整evaluate/score契约不因当前穿戴优化缩小。
    local full = EP.buildContext(1, options)
    local candidate = equipment.inventory[1000]
    check(Eq.getInventoryCount(full.equipmentData) == 1000 and full.equipmentData.inventory[1000] ~= candidate
        and candidate.type == nil, "通用ctx完整1000项且hydrate只写副本")
    local result = EP.evaluate(full, 1000, full.equipmentData.inventory[1000].slot)
    check(result and result.valid and result.equipment.equipped[1].accessory == 1000,
        "未穿戴合法候选仍可evaluate并真实试穿，完整inventory不缩减")
    check(EP.evaluateLoadout(full, { weapon = 1000 }).valid == false,
        "完整试穿职业/部位门禁不放宽")
    f.modules.heroes, f.modules.equipment, f.modules.artifacts, f.modules.talents =
        options.heroes, equipment, artifacts, options.talents
    f.stored.heroes, f.stored.equipment, f.stored.artifacts, f.stored.talents =
        options.heroes, equipment, artifacts, options.talents
    local cached = EP.getContext(1)
    check(cached and Eq.getInventoryCount(cached.equipmentData) == 1000,
        "score/getContext仍用完整库存，不接轻context")
    check(type(EP.score(candidate, 1)) == "number", "正式候选score仍返回数值")
    -- 同批覆盖只影响本人，不能改变其他英雄后续构造时的队友。
    local override = copy(options)
    override.heroData = { level = 150, awakening = { [1] = true }, extraTalent = { issuedCards = 5 } }
    contextSame(EP.buildWornContext(1, override, batch), EP.buildContext(1, override), "heroData独立覆盖")
    contextSame(EP.buildWornContext(2, options, batch), EP.buildContext(2, options), "覆盖不泄漏队友")
    check(same(batch.heroesData, before.heroes), "批次英雄快照没有被heroData覆盖污染")
    -- 脏档：数字/string并存、前导0、非数字seq、重复槽、缺项和旧双手副手。
    local dirty = copy(options)
    local inv, equipped = dirty.equipment.inventory, dirty.equipment.equipped
    inv[1] = { templateId = "W1", level = 3, quality = 1 }
    inv["1"] = { templateId = "W7", level = "45", quality = 4, enhanceLevel = "19" }
    inv["0001"] = { templateId = "C1", level = 42, quality = 5 }
    inv.bad = { templateId = "H1", level = 999999, quality = 3, ascendLevel = 120 }
    inv[0] = { templateId = "S1", level = 0, quality = 1, ascendLevel = -4 }
    inv.unknown = { templateId = "missing_template", type = "custom", slot = "armor", baseStats = { { AD.ARMOR, 7 } } }
    inv[true] = { templateId = "C1", level = 12, quality = 2 }
    inv[false] = false
    equipped[1] = { weapon = 1, offhand = "1", accessory = "0001", helmet = "bad", shoes = 0, armor = "missing" }
    equipped["1"] = { weapon = 1000 }
    equipped[2] = { armor = "unknown", accessory = true }
    equipped["2"] = { weapon = 1000 }
    dirty.heroes.teams = { [1] = { slots = { [1] = { heroId = "1" }, ["2"] = "2", [3] = 1, [4] = 9999 } },
        ["1"] = { slots = { 20 } }, ["2"] = { slots = { ["1"] = 19, ["2"] = "20" } },
        [3] = { slots = { 8, 14 } } }
    dirty.heroes.roster[1].advBranch = { first = 103, second = 207 }
    dirty.heroes.roster[8].advBranch = { first = 109, second = 220 }
    equipped[8] = { weapon = "1", offhand = 2, accessory = "0001" }
    equipped[14] = { weapon = "1", offhand = "1" }
    local dirtyBefore = copy(dirty)
    local dirtyBatch = EP.createWornBatch(dirty)
    for _, id in ipairs({ 1, 2, 19, 20, 8, 14, 25 }) do
        contextSame(EP.buildWornContext(id, dirty, dirtyBatch), EP.buildContext(id, dirty), "脏key/双持 hero=" .. id)
    end
    check(same(dirty, dirtyBefore), "脏key/双持/夹紧水合不修改源数据")
    check(EP.buildWornContext(1, dirty).equipmentData.inventory["1"].templateId == "W7"
        and EP.buildWornContext(1, dirty).equipmentData.equipped[1].offhand == "1",
        "字符串inventory优先且原无效副手槽不删（不伪五算六）")
    check(EP.buildWornContext(9999, options) == nil and EP.buildWornContext("bad", options) == nil,
        "未知hero/非法ID同原通用入口返回nil")
    local twohand = copy(options)
    local twohandTemplate
    for _, templateId in ipairs(templateIds) do
        local template = EC.ITEMS[templateId]
        if template.slot == "weapon" and template.grip == "twohand"
            and ESC.getSetIdForTemplate(template) == "swordgate" then twohandTemplate = templateId; break end
    end
    assert(twohandTemplate, "real swordgate twohand template")
    local twohandSlots = {}
    twohand.equipment.equipped[1] = twohandSlots
    for index, slot in ipairs({ "weapon", "armor", "helmet", "shoes", "accessory" }) do
        twohand.equipment.inventory[tostring(1100 + index)] = {
            templateId = slot == "weapon" and twohandTemplate or templateFor(slot, "swordgate"),
            level = 90, quality = 4,
        }
        twohandSlots[slot] = tostring(1100 + index)
    end
    local validTwohand = EP.buildWornContext(1, twohand)
    contextSame(validTwohand, EP.buildContext(1, twohand), "真实双手5件算6")
    check(validTwohand.hero.attrs._setSix == "swordgate", "双手空副手五算六未丢失")
    twohandSlots.offhand = "missing_piece"
    local dirtyTwohand = EP.buildWornContext(1, twohand)
    contextSame(dirtyTwohand, EP.buildContext(1, twohand), "脏双手无效非空副手")
    check(dirtyTwohand.hero.attrs._setSix == nil, "脏非空副手不伪造5算6")
    -- 原地更改与替换源，必须新批读取最新值；旧批只代表本次同步评估窗口。
    equipment.inventory[1000].level = 86
    equipment.equipped[1].accessory = 1000
    local nextBatch = EP.createWornBatch(options)
    contextSame(EP.buildWornContext(1, options, nextBatch), EP.buildContext(1, options), "新通知原位穿戴/等级更新")
    check(nextBatch ~= batch and nextBatch.equipmentData.inventory[1000] ~= nil,
        "新批拾取原位修改的未曾穿戴候选，不跨通知负缓存")
    local empty = { heroes = options.heroes }
    contextSame(EP.buildWornContext(1, empty), EP.buildContext(1, empty), "空装备/神器/天赋")
    f.stored.heroes, f.stored.equipment, f.stored.artifacts, f.stored.talents =
        options.heroes, equipment, artifacts, options.talents
    contextSame(EP.buildWornContext(1), EP.buildContext(1), "无options读取Store快照")
    -- 真Panel刷新：12拥有，先正常水合，再测单次刷新，不把oracle成本计入优化计数。
    f.modules.battle = { maxStageId = 2001, clearedStages = { ["905"] = true, ["1905"] = true } }
    f.apply(options.heroes)
    f.reset()
    inventoryWalks = 0
    f.data().power.refreshPowerCache()
    local refreshCounts, refreshWalks = copy(f.counts), inventoryWalks
    check(refreshCounts.fullContext == 0 and refreshCounts.wornContext == 12 and refreshCounts.wornBatch == 1,
        "真实Power单刷新12轻context/1batch/0fullcontext")
    check(refreshCounts.hydrate <= 73 and refreshWalks == 0,
        "真实Power刷新全inventory遍历0，水合至多73当前穿戴项")
    print(string.format("%s WORN_REFRESH contexts=%d batches=%d hydrate=%d walks=%d",
        TAG, refreshCounts.wornContext, refreshCounts.wornBatch, refreshCounts.hydrate, refreshWalks))
    for _, id in ipairs(ids) do
        local own = f.panel.getOwnedHero(id)
        local expected = EP.buildContext(id, { heroData = own, heroes = options.heroes, equipment = equipment,
            artifacts = artifacts, talents = options.talents }).currentPower
        check(f.data().detail.calcHeroPower(id) == math.floor(expected + 0.5), "真实Panel同完整ctx hero=" .. id)
    end
    for team = 1, 3 do
        f.panel.setActiveTeam(team)
        for _, id in ipairs(ids) do
            local slot, actualTeam = EP.findPosition(options.heroes, id)
            local correct = f.data().detail.calcHeroPower(id, slot, actualTeam)
            local wrongTeam = actualTeam % 3 + 1
            local wrong = EP.buildContext(id, { heroData = f.panel.getOwnedHero(id), heroes = options.heroes,
                equipment = equipment, artifacts = {}, talents = options.talents }).currentPower
            check(correct == f.data().detail.calcHeroPower(id), "活动队不改变真实神器队 hero=" .. id .. " active=" .. team)
            check(f.data().detail.calcHeroPower(id, slot, wrongTeam) == math.floor(wrong + 0.5),
                "错队不借神器且同完整ctx hero=" .. id .. " active=" .. team)
        end
    end
    check(same(options.heroes, before.heroes) and same(artifacts, before.artifacts),
        "完整Panel同步/多活动队/错误队未写英雄或神器源")
end

function Start()
    local oldRequire, oldFile = require, File
    local ok, err = pcall(function()
        local f, input = fixture(), heroes()
        local cp = f.panel
        f.modules.battle = { currentStageId = 101, maxStageId = 2001,
            teamStageIds = { 101, 102, 103 }, clearedStages = { ["905"] = true, ["1905"] = true } }
        f.modules.session = { lastOnlineTime = 1699999940, firstLoginTime = 1699999900 }
        f.modules.player = { level = 100 }
        f.modules.heroes = copy(input)
        local schema = f.load("shared.artifact.ArtifactSchema")
        local artifacts = { bag = {
            { id = "1", artifactId = 11, quality = 1, valueRatio = 0 },
            { id = "2", artifactId = 9, quality = 3, valueRatio = 0 },
            { id = "3", artifactId = 5, quality = 2, valueRatio = 0 },
        }, equippedByTeam = {
            [1] = { [3] = { "1" } }, [2] = { [4] = { "2" } }, [3] = { [1] = { "3" } },
        } }
        schema.normalizeModule(artifacts)
        f.modules.artifacts = artifacts
        f.modules.equipment = { inventory = {}, equipped = {} }
        f.modules.talents = { litNodes = {} }
        local pending = f.load("rules.offline.OfflineService").CalcOnEnter(1)
        check(pending ~= nil, "真实离线Service建立隔离pending")
        check(not cp.isHeroesDataApplied(), "首份英雄通知前保持ready=false")
        f.openOffline(true)
        f.reset()
        local changed = f.apply(input)
        local business = countsCheck(f, "direct", 5, false)
        check(same(changed, { true, true, true }), "首次只失效真正变化的三队")
        check(same(business, { "invalidate", "offline-service", "offline-panel", "nav" }),
            "首次业务回调相对顺序保持")
        finalCheck(f, "direct")
        rosterCheck(f, "direct")
        local data = f.data()
        local previews = {}
        for _, entry in ipairs(data.preview or {}) do previews[entry.heroId] = entry end
        check(#data.preview == 5 and previews[1].expGain == 100 and previews[2].expGain == 100
            and previews[3].expGain == 200 and previews[4].expGain == 200 and previews[5].expGain == 600,
            "真实离线预览按三队自己的经验池与人数分配")
        check(not previews[8] and not previews[25] and previews[4].teamIdx == 2,
            "离线预览排除未出战/仅碎片并保留真实队")
        check(same(input, heroes()), "源英雄数据未被写回/发奖/改编队")
        local expectedRoster = copy(data.roster)
        for team = 1, 3 do
            cp.setActiveTeam(team)
            check(same(f.data().roster, expectedRoster), "切活动队不重排三队名册 T" .. team)
        end
        local current = f.data()
        check(current.detail.calcHeroPower(4, 4, 2) ~= current.detail.calcHeroPower(4, 4, 1),
            "不同队神器非零且错误队不能借用")
        check(current.detail.calcHeroPower(4) == current.detail.calcHeroPower(4, 4, 2),
            "缺省名册战力取真实队2槽4神器")

        f.reset()
        local duplicate = f.apply(copy(input))
        countsCheck(f, "direct-identical", 5, false, true)
        check(baseline or (same(duplicate, {}) and #f.data().trace == 0),
            "逐值相同的新table直接通知不重复业务回调")
        finalCheck(f, "direct-identical", true)

        f.reset()
        f.apply(input, true)
        countsCheck(f, "subscription-identical", 5, true, true)
        check(#f.data().invalidated == 0 and #f.data().progress == 0,
            "相同数据订阅不失效布局或养成")
        finalCheck(f, "subscription-identical-active3", true)

        local stableRoster, stablePower = f.data().roster, f.data().rosterPower
        local stableSlots, stableSlotPower = cp.getTeamSlotsData(2)
        local stableSlot = stableSlots[4]
        local expInput = copy(input)
        expInput.roster["4"].exp = expInput.roster["4"].exp + 1
        f.reset()
        f.apply(expInput, true)
        local expBusiness = countsCheck(f, "subscription-exp-only", 5, true, true)
        local updatedSlots, updatedSlotPower = cp.getTeamSlotsData(2)
        local rosterExp
        for _, entry in ipairs(f.data().roster) do if entry.heroId == 4 then rosterExp = entry.exp end end
        check(cp.getOwnedHero(4).exp == expInput.roster["4"].exp
            and updatedSlots[4].exp == expInput.roster["4"].exp and rosterExp == expInput.roster["4"].exp,
            "纯exp通知更新拥有/槽位/名册经验")
        check(baseline or (f.data().roster == stableRoster and f.data().rosterPower == stablePower
            and updatedSlots == stableSlots and updatedSlots[4] == stableSlot and updatedSlotPower == stableSlotPower),
            "纯exp通知保留名册/槽数组/槽对象/战力cache引用")
        check(baseline or (same(expBusiness, { "offline-service", "offline-panel" })
            and #f.data().invalidated == 0 and #f.data().progress == 0),
            "纯exp只更新实际离线预览，不重开战斗或养成")
        finalCheck(f, "subscription-exp-only", true)
        input = expInput

        input.roster["4"].level = 90
        f.reset()
        f.apply(input, true)
        local growthBusiness = countsCheck(f, "subscription-growth", 5, true)
        check(#f.data().invalidated == 0 and same(f.data().progress[1].teams, { 2 }),
            "等级成长只刷新队2下波，不重置编队")
        check(same(f.data().progress[1].classes, {}), "等级成长不触发职业重建")
        check(growthBusiness[#growthBusiness] == "progress", "养成刷新仍最后执行业务回调")
        finalCheck(f, "subscription-growth")

        check(cp.getOwnedHero(4).advBranch == input.roster["4"].advBranch,
            "原地分支夹具确实与拥有数据共享同一表")
        input.roster["4"].advBranch.first = 102
        f.reset()
        f.apply(input, true)
        countsCheck(f, "subscription-branch-in-place", 5, true)
        check(#f.data().invalidated == 0 and same(f.data().progress[1].teams, { 2 })
            and f.data().progress[1].classes[2] == true,
            "原地分支修改仍刷新队2职业，不被共享引用吞掉")
        finalCheck(f, "subscription-branch-in-place")

        input.teams[2].slots, input.teams[3].slots = { 0, 5, 0, 4 }, { 3, 0, 0, 0 }
        f.reset()
        f.apply(input, true)
        countsCheck(f, "subscription-layout", 5, true)
        check(same(f.data().invalidated, { { [2] = true, [3] = true } }),
            "跨队换位只失效队2/3，一队不变")
        check(#f.data().progress == 0, "编队变动不另当成长刷新")
        finalCheck(f, "subscription-layout")

        input.teams[2].slots, input.teams[3].slots = { 1, 5, 0, 4 }, { 3, 9999, 0, 0 }
        f.reset()
        f.apply(input, true)
        countsCheck(f, "subscription-dedup", 5, true, true)
        check(same(cp.getTeamSlotLayout(2), { 0, 5, 0, 4 })
            and same(cp.getTeamSlotLayout(3), { 3, 0, 0, 0 }), "重复/未拥有脏槽按原规则清空")
        check(#f.data().invalidated == 0, "去重后有效布局未变不重置")
        finalCheck(f, "subscription-dedup", true)

        input.teams[2].slots = { 0, 0, 0, 0 }
        f.reset()
        f.apply(input, true)
        countsCheck(f, "subscription-empty-team", 3, true)
        check(cp.getTotalPower(2) == 0 and same(f.data().invalidated, { { [2] = true } }),
            "清空队2只失效队2并清缓存")
        finalCheck(f, "subscription-empty-team")

        f.reset()
        f.apply(input, true, true)
        countsCheck(f, "subscription-store-fallback", 3, true, true)
        finalCheck(f, "subscription-store-fallback", true)

        f.reset()
        f.apply(nil)
        check(f.counts.context == 0 and #f.data().events == 0 and #f.data().invalidated == 0,
            "直接nil无同步/刷新/事件")
        f.reset()
        f.apply(nil, true)
        check(f.counts.rebuild == 0 and f.counts.invalidations == 1 and #f.data().events == 1,
            "订阅无data仍完整refresh一次，不重建名册")
        finalCheck(f, "subscription-no-data")

        f.reset()
        cp.resetSessionData()
        check(not cp.isHeroesDataApplied() and cp.getTotalPower(1) == 0 and cp.getTotalPower(2) == 0
            and cp.getTotalPower(3) == 0, "reset保持ready=false并清三队缓存")
        check(f.data().events[1].ready == false, "reset仍发未就绪快照，不误发就绪")
        f.reset()
        f.apply(heroes(), true)
        countsCheck(f, "subscription-after-reset", 5, true)
        finalCheck(f, "subscription-after-reset")
        if not baseline then
            -- 一条真实同步部署链：成功回执、重复回执、失败回滚与无宿主兜底。
            f.openOffline(false)
            local authoritative = heroes()
            cp.setOnTeamChanged(function()
                authoritative.deployed = cp.getTeamSlotLayout(1)
                for team = 1, 3 do authoritative.teams[team].slots = cp.getTeamSlotLayout(team) end
                f.apply(authoritative, true)
                return true
            end, true)
            f.reset()
            check(f.deploy(8, 4), "真实部署发起同步单机回执")
            countsCheck(f, "deploy-sync-success", 6, true)
            check(cp.getTeamSlotLayout(1)[4] == 8 and same(f.data().invalidated, { { [1] = true } }),
                "同步回执只算一次且冻结布局仍失效真正变化的队1")
            finalCheck(f, "deploy-sync-success")
            f.reset()
            f.apply(authoritative, true)
            countsCheck(f, "deploy-sync-repeat", 6, true, true)
            finalCheck(f, "deploy-sync-repeat", true)
            local beforeRollback = copy(f.data().snapshot)
            cp.setOnTeamChanged(function() f.apply(authoritative, true); return true end, true)
            f.reset()
            check(f.deploy(3, 2), "真实跨队部署发起失败回滚回执")
            countsCheck(f, "deploy-sync-rollback", 6, true, true)
            check(same(f.data().snapshot, beforeRollback) and cp.getTeamSlotLayout(1)[2] == 0
                and cp.getTeamSlotLayout(2)[2] == 3 and #f.data().invalidated == 0
                and #f.data().progress == 0, "失败回滚不清战力缓存、不改变最终编队或重开战斗")
            finalCheck(f, "deploy-sync-rollback", true)
            cp.setOnTeamChanged(nil)
            f.reset()
            check(f.deploy(3, 2), "无回调宿主仍可真实部署")
            check(f.counts.invalidations == 1 and f.counts.context == 6 and #f.data().events == 1,
                "无回调宿主仅一次完整刷新，不丢本地兜底")
            print(string.format("%s DEPLOY_COUNTS fallback refresh=%d context=%d events=%d",
                TAG, f.counts.invalidations, f.counts.context, #f.data().events))
            finalCheck(f, "deploy-no-callback")
        end
        check(require == oldRequire and File == oldFile, "全局require/File保持，完全隔离真实档")
        if not baseline then wornContextChecks() end
    end)
    if not ok then check(false, "harness error: " .. tostring(err)) end
    print(string.format("%s %s assertions=%d failures=%d mode=%s", TAG,
        failures == 0 and "ALL PASS" or "FAIL", assertions, failures, baseline and "baseline" or "optimized"))
    if failures > 0 then log:Write(LOG_ERROR, TAG .. " failures=" .. failures) end
    engine:Exit()
end
