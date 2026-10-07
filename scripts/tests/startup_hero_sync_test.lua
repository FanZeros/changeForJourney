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
    local counts = { rebuild = 0, refresh = 0, calc = 0, context = 0, invalidations = 0, nav = 0 }
    local trace, notifications, legacy, invalidated, progress, observations = {}, {}, {}, {}, {}, {}
    local modules, stored, subscriptions = {}, {}, {}
    local loaded, loading = {}, {}
    local clock = 1700000000
    ---@type table
    local panel
    ---@type table
    local powerApi
    ---@type table
    local drawContext
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
    mocks["ui.character.panel.CharacterDeploy"] = { bind = function() return {} end }
    mocks["ui.character.panel.CharacterInput"] = { bind = function() return {} end }
    mocks["ui.character.panel.CharacterProgress"] = { bind = function() return {} end }
    mocks["ui.church.talent.TalentStarMap"] = {}
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
        elseif name == "systems.EquipmentPower" then
            local context, invalidate = value.buildContext, value.invalidate
            value.buildContext = function(...)
                counts.context = counts.context + 1
                return context(...)
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
        modules = modules, stored = stored,
        data = function()
            return { trace = trace, events = notifications, legacy = legacy, invalidated = invalidated,
                progress = progress, observations = observations, preview = offlinePreview,
                roster = drawContext.getHeroRoster(), rosterPower = drawContext.getRosterPowerCache(),
                detail = detailContext, power = powerApi, gamePower = gamePower }
        end,
    }
end

local function heroes()
    local roster = {}
    for _, id in ipairs({ 1, 2, 3, 4, 5, 8 }) do
        roster[tostring(id)] = { level = 60 + id, exp = id, shards = id * 2,
            awakening = {}, extraTalent = {} }
    end
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

local function finalCheck(f, label)
    local data, cp = f.data(), f.panel
    check(cp.isHeroesDataApplied(), label .. " ready=true")
    local snapshot = data.events[#data.events]
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

local function countsCheck(f, label, deployed, viaSubscription)
    local count, data = copy(f.counts), f.data()
    print(string.format("%s COUNTS mode=%s case=%s rebuild=%d refresh=%d calc=%d context=%d invalidate=%d events=%d",
        TAG, baseline and "baseline" or "optimized", label, count.rebuild, count.refresh,
        count.calc, count.context, count.invalidations, #data.events))
    local ownedCount = 0
    for _, entry in ipairs(data.roster) do if entry.owned then ownedCount = ownedCount + 1 end end
    check(count.rebuild == (baseline and 2 or 1), label .. " 精确rebuild次数")
    check(count.refresh == 1, label .. " Sync精确refresh次数")
    check(count.invalidations == ((baseline and viaSubscription) and 2 or 1), label .. " 实际Power刷新/失效次数")
    check(#data.events == ((baseline and viaSubscription) and 2 or 1), label .. " 完整快照仅最终发布一次")
    -- 名册重建只做视图排序，正式Power同轮一次按heroId/真实神器队槽评分，不重复调用公开calc。
    check(count.calc == (baseline and (deployed + ownedCount * 2) or 0), label .. " 直接calc精确次数")
    check(count.context == (baseline and (deployed + ownedCount * (viaSubscription and 4 or 3))
        or ownedCount), label .. " 真实EquipmentPower上下文精确次数")
    local business = {}
    for _, kind in ipairs(data.trace) do
        if kind == "invalidate" or kind == "offline-service" or kind == "offline-panel"
            or kind == "nav" or kind == "progress" then business[#business + 1] = kind end
    end
    if not baseline then
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
        f.apply(input, true)
        countsCheck(f, "subscription-identical", 5, true)
        check(#f.data().invalidated == 0 and #f.data().progress == 0,
            "相同数据订阅不失效布局或养成")
        finalCheck(f, "subscription-identical-active3")

        input.roster["4"].level = 90
        f.reset()
        f.apply(input, true)
        local growthBusiness = countsCheck(f, "subscription-growth", 5, true)
        check(#f.data().invalidated == 0 and same(f.data().progress[1].teams, { 2 }),
            "等级成长只刷新队2下波，不重置编队")
        check(same(f.data().progress[1].classes, {}), "等级成长不触发职业重建")
        check(growthBusiness[#growthBusiness] == "progress", "养成刷新仍最后执行业务回调")
        finalCheck(f, "subscription-growth")

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
        countsCheck(f, "subscription-dedup", 5, true)
        check(same(cp.getTeamSlotLayout(2), { 0, 5, 0, 4 })
            and same(cp.getTeamSlotLayout(3), { 3, 0, 0, 0 }), "重复/未拥有脏槽按原规则清空")
        check(#f.data().invalidated == 0, "去重后有效布局未变不重置")
        finalCheck(f, "subscription-dedup")

        input.teams[2].slots = { 0, 0, 0, 0 }
        f.reset()
        f.apply(input, true)
        countsCheck(f, "subscription-empty-team", 3, true)
        check(cp.getTotalPower(2) == 0 and same(f.data().invalidated, { { [2] = true } }),
            "清空队2只失效队2并清缓存")
        finalCheck(f, "subscription-empty-team")

        f.reset()
        f.apply(input, true, true)
        countsCheck(f, "subscription-store-fallback", 3, true)
        finalCheck(f, "subscription-store-fallback")

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
        check(require == oldRequire and File == oldFile, "全局require/File保持，完全隔离真实档")
    end)
    if not ok then check(false, "harness error: " .. tostring(err)) end
    print(string.format("%s %s assertions=%d failures=%d mode=%s", TAG,
        failures == 0 and "ALL PASS" or "FAIL", assertions, failures, baseline and "baseline" or "optimized"))
    if failures > 0 then log:Write(LOG_ERROR, TAG .. " failures=" .. failures) end
    engine:Exit()
end
