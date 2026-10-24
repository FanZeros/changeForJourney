-- 成长刷新热路径：沿用 character_roster_sort_test 的真实Panel隔离脚手架。
-- full oracle 每次强制全名册评分；另用完整库存buildContext核对所有正式缓存。
-- 不启动main、不读写玩家档；外围Draw/导航/保存为边界替身，正式属性/光环/神器不替换。
local checks, failures, cases = 0, 0, 0
local function check(ok, message)
    checks = checks + 1
    if not ok then failures = failures + 1; print("[GrowthPower][FAIL] " .. message) end
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
local function sourceModule(name, resolver)
    local path = name:gsub("%.", "/") .. ".lua"
    local file = assert(cache:GetFile(path), path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return assert(load(table.concat(lines, "\n"), "@" .. path, "t",
        setmetatable({ require = resolver }, { __index = _G })))()
end

function Start()
    local nativeRequire, savedFile, savedFS = require, File, fileSystem
    local HC = nativeRequire("config.HeroConfig")
    local EP = nativeRequire("systems.EquipmentPower")
    local EC = nativeRequire("config.EquipmentConfig")
    local ESC = nativeRequire("config.EquipmentSetConfig")
    local AD = nativeRequire("systems.AttributeDef")
    local Events = nativeRequire("config.GameEvents")
    local ArtifactDefs = nativeRequire("shared.artifact.ArtifactDefs")
    local ArtifactSchema = nativeRequire("shared.artifact.ArtifactSchema")
    local Draw = nativeRequire("ui.character.panel.CharacterPanelDraw2")
    local savedBuild, fullBuild, savedLit = EP.buildWornContext, EP.buildContext, HC._getSavedLitNodes()
    local savedInvalidate = EP.invalidate
    local Eq = nativeRequire("systems.EquipmentSystem")
    local ESR = nativeRequire("systems.EquipmentSetRuntime")
    local savedCreate, savedApply, savedAura = HC.createHero, Eq.applyToUnit, ESR.applyTeamAura
    local active = { order = {}, creates = 0, equips = 0, auras = 0 }
    HC.createHero = function(...)
        active.creates = active.creates + 1
        return savedCreate(...)
    end
    Eq.applyToUnit = function(...)
        active.equips = active.equips + 1
        return savedApply(...)
    end
    ESR.applyTeamAura = function(...)
        active.auras = active.auras + 1
        return savedAura(...)
    end
    EP.invalidate = function(...)
        active.order[#active.order + 1] = "invalidate"
        return savedInvalidate(...)
    end
    local storage = 0
    local function denyIO() storage = storage + 1; error("growth power test forbids player IO") end
    rawset(_G, "File", denyIO)
    rawset(_G, "fileSystem", setmetatable({}, { __index = function() return denyIO end }))
    EP.buildWornContext = function(...)
        active.calls = active.calls + 1
        local id = select(1, ...)
        active.scored[id] = (active.scored[id] or 0) + 1
        if active.noTeamReuse then
            local id, options, batch = ...
            local isolated = {}
            for key, value in pairs(options or {}) do isolated[key] = value end
            isolated.reuseTeamContext = false
            return savedBuild(id, isolated, batch)
        end
        return savedBuild(...)
    end
    -- 队伍新口径独立 oracle：不调用被测 Bridge helper，也不复用分项缓存。
    local function artifactTeamPower(f, teamIdx, slots)
        local total, counted = 0, {}
        local data = f.data.artifacts or {}
        for slot = 1, ArtifactSchema.SLOT_COUNT do
            for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
                local id = ArtifactSchema.getEquippedId(data, slot, subSlot, teamIdx)
                local artifact
                for _, item in ipairs(data.bag or {}) do
                    if tostring(item.id) == tostring(id) then artifact = item; break end
                end
                local def = artifact and ArtifactDefs.get(artifact.artifactId)
                if def and not counted[tostring(id)] then
                    local target = slot
                    if def.effectType == "left_phys_atk_bonus" then target = slot - 1 end
                    if def.effectType == "right_mag_atk_bonus" then target = slot + 1 end
                    local owner = slots[target]
                    if target >= 1 and target <= ArtifactSchema.SLOT_COUNT
                        and owner and owner.state == "occupied" and f.panel.getOwnedHero(owner.heroId) then
                        counted[tostring(id)] = true
                        total = total + ArtifactDefs.getPower(artifact)
                    end
                end
            end
        end
        return total
    end
    local function fixture(forceFull)
        local f = { data = {}, revisions = { heroes = 1, equipment = 1, artifacts = 1, talents = 1 },
            calls = 0, scored = {}, events = {}, progress = {}, invalidations = {}, dirty = 0, order = {},
            creates = 0, equips = 0, auras = 0, noTeamReuse = forceFull,
            context = {}, modules = {}, listeners = {}, storeListeners = {}, gamePower = 0 }
        local noop = function() end
        local detail = { init = noop, setContext = noop, markPowerDirty = function()
            f.dirty = f.dirty + 1; f.order[#f.order + 1] = "dirty"
        end,
            hasAwakeningUpgrade = function() return false end, hasAnyUpgradeForHero = function() return false end }
        local store = { Get = function(key) return f.data[key] end,
            GetRevision = function(key) return f.revisions[key] or 0 end,
            Subscribe = function(key, fn) f.storeListeners[key] = fn end }
        f.store = store
        local draw = setmetatable({ setContext = function(ctx) f.context = ctx end,
            initImages = noop, getSharedImages = function() return {} end, resetPresentation = noop,
            clearSortInteraction = noop, clearTeamInteraction = noop }, { __index = Draw })
        local mocks = {
            ["runtime.ClientDispatcher"] = { get = store.Get,
                subscribe = function(key, fn) f.listeners[key] = fn end },
            ["core.PlayerStore"] = store,
            ["core.GameState"] = { getLevel = function() return 100 end, setPower = function(value)
                f.order[#f.order + 1] = "gamePower"
                if value ~= f.gamePower then
                    f.gamePower = value
                    f.events[#f.events + 1] = { event = Events.PLAYER_POWER_CHANGED, power = value }
                end
            end },
            ["core.EventBus"] = { emit = function(event, payload)
                f.order[#f.order + 1] = "event"
                local order = f.order
                check(order[#order - 3] == "invalidate" and order[#order - 2] == "gamePower"
                    and order[#order - 1] == "dirty" and order[#order] == "event",
                    "所有正式刷新保持invalidate/GameState/dirty/TEAM_POWER_CHANGED顺序")
                -- 同步订阅者直接读整套缓存，不能先发事件再补另两队。
                local powers = {}
                for t = 1, 3 do powers[t] = f.panel.getTotalPower(t) end
                local mapped = true
                for i, entry in ipairs(f.context.getHeroRoster()) do
                    if f.context.getRosterPowerCache()[i] ~= (entry.owned and f.panel.getRosterPower(entry.heroId) or 0) then
                        mapped = false
                    end
                end
                check(same(powers, payload.powers) and mapped, "同步事件缓存/三队/heroId映射完整")
                f.events[#f.events + 1] = { event = event, payload = copy(payload) }
            end },
            ["ui.character.panel.CharacterPanelDraw2"] = draw,
            ["ui.character.detail.CharacterDetail"] = detail,
            ["ui.hud.BottomNav"] = { setBadge = noop, refreshTownBadge = noop },
            ["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end },
            ["ui.battle.scene.BattleScene"] = { refreshAllyStats = noop },
            ["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return false end },
            ["ui.battle.tri.BattleTriPage"] = {
                refreshHeroProgressTeams = function(teams, classes)
                    f.progress[#f.progress + 1] = { teams = copy(teams), classes = copy(classes) }
                end,
                invalidateTeams = function(teams) f.invalidations[#f.invalidations + 1] = copy(teams) end },
        }
        local isolated = { CharacterPanel = true, CharacterPower = true, CharacterHeroSync = true,
            CharacterRosterSort = true, CharacterProgress = true }
        local function resolver(name)
            if mocks[name] then return mocks[name] end
            if f.modules[name] then return f.modules[name] end
            local leaf = name:match("^ui%.character%.panel%.(.+)$")
            if leaf and isolated[leaf] then
                local module = sourceModule(name, resolver)
                if leaf == "CharacterPower" then
                    local bind = module.bind
                    module.bind = function(deps)
                        local power = bind(deps)
                        f.power, f.powerGet = power, deps.get
                        if forceFull then
                            local refresh = power.refreshPowerCache
                            power.refreshPowerCache = function(cause) return refresh(cause) end
                        end
                        return power
                    end
                end
                f.modules[name] = module
                return module
            end
            return nativeRequire(name)
        end
        f.load = resolver
        f.panel = resolver("ui.character.panel.CharacterPanel")
        active, require = f, resolver
        f.panel.init({})
        return f
    end
    local ok, err = pcall(function()
        local optimized, oracle = fixture(false), fixture(true)
        local input = { heroes = { roster = {}, deployed = { 1, 3, 0, 0 }, teams = {
            { slots = { 1, 3, 0, 0 } }, { slots = { 9, 20, 12, 0 } }, { slots = { 15, 10, 0, 0 } } } },
            equipment = { inventory = {}, equipped = {} }, talents = { litNodes = { 113, 124 } },
            battle = { clearedStages = { [905] = true, [1905] = true }, maxStageId = 2305 },
            artifacts = { bag = { { id = "a", artifactId = 5, value = 20 },
                { id = "b", artifactId = 8, value = 80 }, { id = "c", artifactId = 5, value = 140 } },
                equippedByTeam = { { { "a" } }, { {}, { "b" } }, { { "c" } } } } }
        local ownedCount = 0
        for _, id in ipairs(HC.getAllIds()) do
            if id ~= 25 then
                input.heroes.roster[tostring(id)] = { level = 70, exp = 0, maxExp = 100,
                    awakening = { [1] = true, [2] = true, [3] = true, [7] = true, _awk3Migrated = true },
                    extraTalent = { stacks = 10, issuedCards = 2 }, advBranch = {} }
                ownedCount = ownedCount + 1
            end
        end
        -- 真实司仪六件+魂火成长：星门队友实际消费变化后的法伤/穿透，非假评分函数。
        for index, slot in ipairs(EC.SLOTS) do
            local found
            for id, template in pairs(EC.ITEMS) do
                if template.slot == slot and ESC.getSetIdForTemplate(template) == "last_rite" then found = id; break end
            end
            assert(found, "missing last_rite " .. slot)
            input.equipment.inventory[tostring(index)] = { templateId = found, level = 70, quality = 6,
                baseStats = {}, affixes = {} }
            input.equipment.equipped["9"] = input.equipment.equipped["9"] or {}
            input.equipment.equipped["9"][slot] = index
        end
        input.equipment.inventory["20"] = { templateId = "C1", level = 70, quality = 3,
            baseStats = { { AD.ENERGY_SHIELD, 100 }, { AD.MAG_DMG_BONUS, 20 }, { AD.MAG_PEN, 10 } }, affixes = {} }
        input.equipment.equipped["12"] = { accessory = 20 }
        local function on(f, action)
            active, require = f, f.load
            return action(f.panel, f)
        end
        for _, f in ipairs({ optimized, oracle }) do
            on(f, function(panel)
                f.data = copy(input)
                panel.setHeroesData(f.data.heroes)
            end)
        end
        local function observation(f)
            return on(f, function(panel)
                local result = { roster = {}, slots = {}, totals = {}, events = copy(f.events),
                    progress = copy(f.progress), invalidations = copy(f.invalidations), dirty = f.dirty,
                    lastTeams = panel.getLastHeroesRefreshTeams(), gamePower = f.gamePower, order = copy(f.order) }
                for i, entry in ipairs(f.context.getHeroRoster()) do
                    result.roster[i] = { id = entry.heroId, owned = entry.owned,
                        power = f.context.getRosterPowerCache()[i], mapped = panel.getRosterPower(entry.heroId) }
                end
                for t = 1, 3 do
                    local slots, powers = panel.getTeamSlotsData(t)
                    result.slots[t] = { slots = copy(slots), powers = copy(powers) }
                    result.totals[t] = panel.getTotalPower(t)
                end
                return result
            end)
        end
        local function assertFullValues(f, label)
            on(f, function(panel)
                local expected = {}
                for _, entry in ipairs(f.context.getHeroRoster()) do
                    if entry.owned then
                        local context = assert(fullBuild(entry.heroId, { heroData = panel.getOwnedHero(entry.heroId),
                            heroes = f.data.heroes, equipment = f.data.equipment,
                            artifacts = f.data.artifacts, talents = f.data.talents }))
                        expected[entry.heroId] = math.floor(context.currentPower + 0.5)
                        check(panel.getRosterPower(entry.heroId) == expected[entry.heroId], label .. " roster " .. entry.heroId)
                    else check(panel.getRosterPower(entry.heroId) == nil, label .. " unowned " .. entry.heroId) end
                end
                for t = 1, 3 do
                    local slots, powers = panel.getTeamSlotsData(t)
                    local total = artifactTeamPower(f, t, slots)
                    for i = 1, 4 do
                        local id = slots[i].state == "occupied" and slots[i].heroId
                        local value = expected[id] or 0
                        check((powers[i] or 0) == value, label .. " slot " .. t .. "/" .. i)
                        total = total + value
                    end
                    check(panel.getTotalPower(t) == total, label .. " total " .. t)
                end
            end)
        end
        local function runCase(label, action, expectedCalls, expectedIds, deferred)
            cases = cases + 1
            for _, f in ipairs({ optimized, oracle }) do
                f.calls, f.scored = 0, {}
                f.creates, f.equips, f.auras = 0, 0, 0
                local started = os.clock()
                on(f, action)
                f.lastCPU = os.clock() - started
                f.work = { creates = f.creates, equips = f.equips, auras = f.auras }
            end
            check(optimized.calls == expectedCalls,
                label .. " calls expected=" .. expectedCalls .. " actual=" .. optimized.calls)
            if expectedIds then
                local ids = {}
                for _, id in ipairs(expectedIds) do ids[id] = 1 end
                check(same(optimized.scored, ids), label .. "精确依赖集合且每英雄仅一次评分")
            end
            check(same(observation(optimized), observation(oracle)), label .. "全名册/三队slot/总分/事件/战斗基线与全量oracle等价")
            if not deferred then assertFullValues(optimized, label) end
            print(string.format("[GrowthPower] case=%s calls=%d fullCalls=%d cpu=%.6f fullCPU=%.6f creates=%d/%d equips=%d/%d auras=%d/%d",
                label, optimized.calls, oracle.calls, optimized.lastCPU, oracle.lastCPU,
                optimized.work.creates, oracle.work.creates, optimized.work.equips, oracle.work.equips,
                optimized.work.auras, oracle.work.auras))
        end
        local function patch(id, values, defer)
            return function(panel) panel.patchExtraTalent(id, values, defer) end
        end
        local options = { heroes = input.heroes, equipment = input.equipment, artifacts = input.artifacts, talents = input.talents }
        local aura = assert(fullBuild(12, options))
        check(aura.hero.attrs.modifiers.set6_last_rite ~= nil and aura.hero.attrs:get(AD.ENERGY_SHIELD) > 100,
            "真实六件光环fixture作用于队2成员")
        local isolatedOptions = copy(options)
        isolatedOptions.heroes.teams[2].slots = { 20, 12, 0, 0 }
        check(aura.hero.attrs:get(AD.ES_BONUS) > fullBuild(12, isolatedOptions).hero.attrs:get(AD.ES_BONUS),
            "移走司仪真实光环消失，不是空fixture")
        local noArtifactOptions = copy(options)
        noArtifactOptions.artifacts = { bag = {}, equippedByTeam = {} }
        check(fullBuild(15, options).currentPower == fullBuild(15, noArtifactOptions).currentPower,
            "队3神器完全排除角色评分，不借当前活动队1")
        local combatOptions = copy(options)
        combatOptions.includeArtifactEffects = true
        check(fullBuild(15, combatOptions).hero.attrs.artifactPowerBonus > 0
            and artifactTeamPower(optimized, 3, optimized.panel.getTeamSlotsData(3)) > 0,
            "队3神器fixture真实战斗效果及独立详情分项仍非零")
        runCase("bench", patch(2, { stacks = 500 }), 1, { 2 })
        runCase("team2", patch(12, { stacks = 1000 }), 3, { 9, 20, 12 })
        local resonanceOptions = copy(options)
        resonanceOptions.heroes.teams[2].slots = { 9, 0, 12, 0 }
        check(aura.currentPower > fullBuild(12, resonanceOptions).currentPower,
            "hero12真实星门供给源计价非空，移走Melissa共鸣消失")
        local starBefore = optimized.panel.getRosterPower(12)
        runCase("resonance", patch(12, { stacks = 100000 }), 3, { 9, 20, 12 })
        check(optimized.panel.getRosterPower(12) > starBefore, "成长正式属性与本队星门共鸣同时保留")
        runCase("team3", patch(10, { shareCount = 500, stacks = 500 }), 2, { 15, 10 })
        local cardsBefore = optimized.panel.getRosterPower(15)
        runCase("issuedCards only", patch(15, { stacks = 10, issuedCards = 1000 }), 2, { 15, 10 })
        check(optimized.panel.getRosterPower(15) > cardsBefore, "issuedCards非stacks字段确实进入正式战力，不盲跳")
        runCase("same extra table mutated", function(panel, f)
            local extra = panel.getOwnedHero(12).extraTalent
            check(f.data.heroes.roster["12"].extraTalent == extra, "patch后owned/Dispatcher共享同extra表夹具成立")
            extra.stacks = extra.stacks + 1
            panel.patchExtraTalent(12, extra)
        end, 3, { 9, 20, 12 })
        runCase("active team switched before team2 growth", function(panel)
            check(panel.setActiveTeam(3) and panel.getActiveTeamIdx() == 3, "先切编辑队3成功")
            panel.patchExtraTalent(12, { stacks = 100002 })
            check(panel.getActiveTeamIdx() == 3, "队2成长不改变编辑队3")
        end, 3, { 9, 20, 12 })
        runCase("power sort warm baseline", function(panel)
            check(panel.setRosterSort("power", false), "切power排序成功")
            panel.refreshPower()
        end, ownedCount)
        runCase("power sort first patch", patch(12, { stacks = 100003 }), 3, { 9, 20, 12 })
        runCase("power sort consecutive patch", patch(12, { stacks = 100004 }), 3, { 9, 20, 12 })
        runCase("batch deferred", function(panel)
            panel.patchExtraTalent(1, { stacks = 500 }, true)
            panel.patchExtraTalent(12, { stacks = 200000 }, true)
            panel.patchExtraTalent(12, { stacks = 300000 }, true)
            panel.patchExtraTalent(15, { issuedCards = 2000 }, true)
        end, 0, {}, true)
        -- 上一case尚未发布，完整库存值应在finish后核对。
        runCase("batch finish", function(panel) panel.finishExtraTalentBatch() end, 7, { 1, 3, 9, 20, 12, 15, 10 })
        runCase("empty batch unknown", function(panel) panel.finishExtraTalentBatch() end, ownedCount)
        runCase("batch interrupted deferred", function(panel)
            panel.patchExtraTalent(1, { stacks = 501 }, true)
            panel.patchExtraTalent(12, { stacks = 300010 }, true)
        end, 0, {}, true)
        runCase("batch interrupted full refresh", function(panel) panel.refreshPower() end, ownedCount)
        runCase("batch interrupted finish", function(panel) panel.finishExtraTalentBatch() end, ownedCount)
        runCase("batch consumed next patch", patch(2, { burnKills = 500 }), 1, { 2 })
        runCase("global refresh", function(panel) panel.refreshPower() end, ownedCount)
        runCase("unannounced growth", function(panel, f)
            panel.getOwnedHero(2).extraTalent.stacks = 900
            f.data.heroes.roster["2"].extraTalent.stacks = 900
            panel.patchExtraTalent(12, { stacks = 300001 })
        end, ownedCount)
        runCase("formation source changed", function(panel, f)
            f.data.heroes.teams[2].slots, f.data.heroes.teams[3].slots = { 15, 9, 0, 0 }, { 20, 10, 12, 0 }
            panel.patchExtraTalent(12, { stacks = 300002 })
        end, ownedCount)
        runCase("formation applied", function(panel, f) panel.setHeroesData(f.data.heroes) end, ownedCount)
        runCase("new team3 closure", patch(12, { stacks = 300003 }), 3, { 20, 10, 12 })
        runCase("equipment revision", function(panel, f)
            f.revisions.equipment = f.revisions.equipment + 1
            f.data.equipment.inventory["20"].baseStats[2][2] = 55
            panel.patchExtraTalent(12, { stacks = 300004 })
        end, ownedCount)
        runCase("equipment notification", function(_, f) f.storeListeners.equipment() end, ownedCount)
        runCase("artifact notification", function(_, f) f.storeListeners.artifacts() end, ownedCount)
        runCase("talents notification", function(_, f) f.listeners.talents() end, ownedCount)
        runCase("cold cache", function(panel, f)
            f.context.getRosterPowerCache()[1] = nil
            panel.patchExtraTalent(12, { stacks = 300005 })
        end, ownedCount)
        runCase("no revision host", function(panel, f)
            f.store.GetRevision = nil
            panel.patchExtraTalent(12, { stacks = 300006 })
            f.store.GetRevision = function(key) return f.revisions[key] or 0 end
        end, ownedCount)
        runCase("level resonance global", function(panel, f)
            f.data.heroes.roster["2"].level = 100
            panel.setHeroesData(f.data.heroes)
        end, ownedCount)
        runCase("rememberState ack", function(panel, f) panel.setHeroesData(f.data.heroes) end, 0, {})
        runCase("shield dependency fixture", function(panel, f)
            f.data.heroes.teams[2].slots = { 9, 20, 12, 0 }
            f.data.heroes.teams[3].slots = { 15, 23, 0, 0 }
            f.data.heroes.roster["23"].extraTalent = { shieldStacks = 0 }
            for _, id in ipairs({ 15, 23 }) do
                local seq = tostring(100 + id)
                f.data.equipment.inventory[seq] = { templateId = "C1", level = 70, quality = 3,
                    baseStats = { { AD.ENERGY_SHIELD, -1000000 } }, affixes = {} }
                f.data.equipment.equipped[tostring(id)] = { accessory = seq }
            end
            panel.setHeroesData(f.data.heroes)
        end, ownedCount)
        local teammateBefore = optimized.panel.getRosterPower(15)
        runCase("real teammate dependency", patch(23, { shieldStacks = 2000000 }), 2, { 15, 23 })
        check(optimized.panel.getRosterPower(15) > teammateBefore,
            "真布护盾成长解锁同队治疗124：未直接patch的hero15正式战力真实变化")
        runCase("extra ack deduplicated", function(panel, f) panel.setHeroesData(f.data.heroes) end, 0, {})
        runCase("exp replacement then extra remains local", function(panel, f)
            f.data.heroes = copy(f.data.heroes)
            f.data.heroes.roster["2"].exp = f.data.heroes.roster["2"].exp + 1
            f.revisions.heroes = f.revisions.heroes + 1
            panel.setHeroesData(f.data.heroes)
            panel.patchExtraTalent(23, { shieldStacks = 2000001 })
        end, 2, { 15, 23 })

        -- 装备差分仍走真实Panel订阅；oracle剥除尝试差分参数，始终正式全量评分。
        -- 装备revision用+7，模拟PlayerStore跨字段共享序列，不错误要求相邻整数。
        local SuccessContext = nativeRequire("shared.SuccessNotificationContext")
        local function equipmentNotify(f, cause)
            local before, dirty = #f.events, f.dirty
            f.revisions.equipment = f.revisions.equipment + 7
            SuccessContext.withNotification(f.data.equipment, "equipment", cause, function()
                f.storeListeners.equipment(f.data.equipment)
            end)
            local event = f.events[#f.events]
            check(event.event == Events.TEAM_POWER_CHANGED and event.payload.cause == cause
                and #f.events >= before + 1 and f.dirty == dirty + 1, "装备通知同步发布且原cause一次消费")
            local order = f.order
            check(order[#order - 3] == "invalidate" and order[#order - 2] == "gamePower"
                and order[#order - 1] == "dirty" and order[#order] == "event", "装备通知原失效/同步/dirty/event顺序")
            check(SuccessContext.takeCause(f.data.equipment, "equipment") == nil, "cause没有泄漏到后续通知")
        end
        local function equipCase(label, change, calls, ids)
            runCase("equipment " .. label, function(panel, f)
                if change then change(panel, f) end
                equipmentNotify(f, label)
            end, calls, ids)
        end
        runCase("equipment oracle baseline", function(panel, f)
            f.data = copy(input)
            f.revisions.heroes = f.revisions.heroes + 1
            panel.setHeroesData(f.data.heroes)
        end, ownedCount)
        equipCase("unworn added", function(_, f)
            f.data.equipment.inventory["900"] = { templateId = "C1", level = 70, quality = 3,
                baseStats = { { AD.ENERGY_SHIELD, 120 } }, affixes = {} }
        end, 0, {})
        equipCase("bench equip", function(_, f)
            f.data.equipment.equipped["2"] = { accessory = 900 }
        end, 1, { 2 })
        equipCase("same seq nested refine", function(_, f)
            f.data.equipment.inventory["900"].baseStats[1][2] = 400
        end, 1, { 2 })
        equipCase("same seq ascend", function(_, f)
            f.data.equipment.inventory["900"].ascendLevel = 2
            f.data.equipment.inventory["900"].affixes[1] = { key = AD.MAG_PEN, value = 30, ascBonus = 4 }
        end, 1, { 2 })
        equipCase("bench to team2", function(_, f)
            f.data.equipment.equipped["2"].accessory = nil
            f.data.equipment.equipped["20"] = { accessory = 900 }
        end, 4, { 2, 9, 20, 12 })
        equipCase("cross team stolen seq", function(_, f)
            f.data.equipment.equipped["20"].accessory = nil
            f.data.equipment.equipped["15"] = { accessory = 900 }
        end, 5, { 9, 20, 12, 15, 10 })
        equipCase("cross team reverse", function(_, f)
            f.data.equipment.equipped["15"].accessory = nil
            f.data.equipment.equipped["12"].accessory = 900
        end, 5, { 9, 20, 12, 15, 10 })
        equipCase("same seq stargate input", function(_, f)
            f.data.equipment.inventory["900"].baseStats[2] = { AD.MAG_DMG_BONUS, 500 }
        end, 3, { 9, 20, 12 })
        equipCase("delete worn item", function(_, f) f.data.equipment.inventory["900"] = nil end,
            3, { 9, 20, 12 })
        equipCase("missing worn unchanged", nil, 0, {})
        equipCase("numeric fallback appears", function(_, f)
            f.data.equipment.inventory[900] = { templateId = "C1", level = 70, quality = 3,
                baseStats = { { AD.MAG_DMG_BONUS, 200 } }, affixes = {} }
        end, 3, { 9, 20, 12 })
        equipCase("string key priority", function(_, f)
            f.data.equipment.inventory["900"] = { templateId = "C1", level = 70, quality = 3,
                baseStats = { { AD.MAG_DMG_BONUS, 600 } }, affixes = {} }
        end, 3, { 9, 20, 12 })
        equipCase("shadowed numeric change", function(_, f)
            f.data.equipment.inventory[900].baseStats[1][2] = 20000
        end, 0, {})
        equipCase("remove string reveals numeric", function(_, f) f.data.equipment.inventory["900"] = nil end,
            3, { 9, 20, 12 })
        equipCase("duplicate seq slots", function(_, f) f.data.equipment.equipped["12"].offhand = 900 end,
            3, { 9, 20, 12 })
        local twohandTemplate, onehandTemplate = "", ""
        for id, template in pairs(EC.ITEMS) do
            if template.slot == "weapon" and template.grip == "twohand" then twohandTemplate = id end
            if template.slot == "weapon" and template.grip == "onehand" then onehandTemplate = id end
        end
        assert(twohandTemplate ~= "" and onehandTemplate ~= "", "missing real weapon grip templates")
        local function checkGripAndOffhand(f, grip, contributes)
            local options = { heroData = f.panel.getOwnedHero(12), heroes = f.data.heroes,
                equipment = f.data.equipment, artifacts = f.data.artifacts, talents = f.data.talents }
            local withOffhand = assert(fullBuild(12, options))
            check(withOffhand.equipmentData.inventory["901"].grip == grip, "真实模板水合后握持=" .. grip)
            options.equipment = copy(f.data.equipment)
            options.equipment.equipped["12"].offhand = nil
            local withoutOffhand = assert(fullBuild(12, options))
            check((withOffhand.currentPower > withoutOffhand.currentPower) == contributes,
                "真实副手贡献符合握持规则=" .. grip)
        end
        equipCase("twohand hides offhand", function(_, f)
            f.data.equipment.inventory["901"] = { templateId = twohandTemplate, level = 70, quality = 3,
                baseStats = { { AD.PHYS_ATK, 200 } }, affixes = {} }
            f.data.equipment.equipped["12"].weapon = 901
            -- 上一case同seq同时占饰品/副手；只留副手，避免去重掩盖真实握持分支。
            f.data.equipment.equipped["12"].accessory = nil
            checkGripAndOffhand(f, "twohand", false)
        end, 3, { 9, 20, 12 })
        equipCase("onehand restores offhand", function(_, f)
            f.data.equipment.inventory["901"].templateId = onehandTemplate
            checkGripAndOffhand(f, "onehand", true)
        end, 3, { 9, 20, 12 })
        equipCase("remove equipped hero mapping", function(_, f) f.data.equipment.equipped["12"] = nil end,
            3, { 9, 20, 12 })
        equipCase("unworn metadata only", function(_, f)
            f.data.equipment.inventory["901"].locked = true
            f.data.equipment.autoDecompose = { quality = 1 }
        end, 0, {})
        runCase("equipment no unworn inventory scan", function(_, f)
            local inventory = f.data.equipment.inventory
            setmetatable(inventory, { __pairs = function() error("equipment notification scanned full inventory") end })
            local notified, message = pcall(equipmentNotify, f, "no inventory scan")
            setmetatable(inventory, nil)
            check(notified, "装备通知只读已穿引用，不扫描库存 " .. tostring(message))
        end, 0, {})
        equipCase("source replacement fallback", function(_, f) f.data.equipment = copy(f.data.equipment) end, ownedCount)
        equipCase("source replacement next notification", nil, 0, {})
        equipCase("unannounced owned combat fallback", function(panel)
            panel.getOwnedHero(2).extraTalent.stacks = 991
        end, ownedCount)
        equipCase("unannounced source combat fallback", function(_, f)
            f.data.heroes.roster["2"].level = 90
        end, ownedCount)
        equipCase("heroes source fallback", function(_, f) f.data.heroes = copy(f.data.heroes) end, ownedCount)
        equipCase("heroes revision fallback", function(_, f) f.revisions.heroes = f.revisions.heroes + 1 end, ownedCount)
        equipCase("artifact revision fallback", function(_, f)
            f.revisions.artifacts = f.revisions.artifacts + 1
            f.data.artifacts.bag[1].value = 25
        end, ownedCount)
        equipCase("talents revision fallback", function(_, f)
            f.revisions.talents = f.revisions.talents + 1
            f.data.talents.litNodes[#f.data.talents.litNodes + 1] = 125
        end, ownedCount)
        equipCase("formal formation fallback", function(_, f)
            f.data.heroes.teams[2].slots = { 9, 12, 20, 0 }
        end, ownedCount)
        equipCase("deployed fallback", function(_, f) f.data.heroes.deployed = { 3, 1, 0, 0 } end, ownedCount)
        equipCase("cold roster cache fallback", function(_, f) f.context.getRosterPowerCache()[1] = nil end, ownedCount)
        equipCase("corrupt team cache fallback", function(_, f) f.context.getTeamPowerCaches()[2][1] = -1 end, ownedCount)
        runCase("equipment revision not advanced fallback", function(_, f)
            f.storeListeners.equipment(f.data.equipment)
        end, ownedCount)
        runCase("equipment unknown payload fallback", function(_, f)
            f.revisions.equipment = f.revisions.equipment + 1
            f.storeListeners.equipment({})
        end, ownedCount)
        runCase("equipment unknown revision fallback", function(_, f)
            local getRevision = f.store.GetRevision
            f.store.GetRevision = nil
            f.storeListeners.equipment(f.data.equipment)
            f.store.GetRevision = getRevision
        end, ownedCount)
        equipCase("after unknown revision fallback", nil, ownedCount)
        runCase("equipment deferred growth fallback", function(panel, f)
            panel.patchExtraTalent(12, { stacks = 400000 }, true)
            equipmentNotify(f, "growth interleaved")
        end, ownedCount)
        runCase("equipment consumed batch finish fallback", function(panel) panel.finishExtraTalentBatch() end, ownedCount)
        runCase("equipment restore shield fixture", function(panel, f)
            f.data.heroes.teams[2].slots = { 9, 20, 12, 0 }
            f.data.heroes.teams[3].slots = { 15, 23, 0, 0 }
            f.data.heroes.roster["23"].extraTalent = { shieldStacks = 0 }
            f.data.talents.litNodes = { 113, 124 }
            for _, id in ipairs({ 15, 23 }) do
                local seq = tostring(100 + id)
                f.data.equipment.inventory[seq] = { templateId = "C1", level = 70, quality = 3,
                    baseStats = { { AD.ENERGY_SHIELD, -1000000 } }, affixes = {} }
                f.data.equipment.equipped[tostring(id)] = { accessory = seq }
            end
            panel.setHeroesData(f.data.heroes)
        end, ownedCount)
        local shieldTeammateBefore = optimized.panel.getRosterPower(15)
        equipCase("124 real teammate shield", function(_, f)
            f.data.equipment.inventory["123"].baseStats[1][2] = 1000000
        end, 2, { 15, 23 })
        check(optimized.panel.getRosterPower(15) > shieldTeammateBefore,
            "装备护盾解锁真实124：未换装hero15的正式评分也随队友变化")
        equipCase("last rite six piece removed", function(_, f)
            f.data.equipment.equipped["9"][EC.SLOTS[1]] = nil
        end, 3, { 9, 20, 12 })
        runCase("equipment full caller stays full", function(panel) panel.refreshPower() end, ownedCount)
        -- 本轮团队复用的正式Panel矩阵：三队满员、乱序名册与本队光环/神器。
        runCase("three full teams fixture", function(panel, f)
            f.data = copy(input)
            f.data.heroes.deployed = { 1, 3, 4, 5 }
            f.data.heroes.teams = { { slots = { 1, 3, 4, 5 } },
                { slots = { 9, 20, 12, 23 } }, { slots = { 15, 10, 18, 24 } } }
            panel.setHeroesData(f.data.heroes)
        end, ownedCount)
        runCase("four member growth", patch(12, { stacks = 300001 }), 4, { 9, 20, 12, 23 })
        check(optimized.work.creates == 4 and optimized.work.auras == 1,
            "四人队一次refresh只创建4英雄/应用1次整队光环，不再16次创建")
        runCase("three full teams global", function(panel) panel.refreshPower() end, ownedCount)
        check(optimized.work.creates == ownedCount and oracle.work.creates == ownedCount + 36,
            "三队满员全刷新24 vs 60真实HC.createHero，未编队仍独立创建")
        check(optimized.work.equips < oracle.work.equips and optimized.work.auras < oracle.work.auras,
            "真实装备应用/团队光环调用同时下降，不只是少算外层函数")
        -- 同夹具/同强制全量入口CPU，观察不进入计时区；不以耗时阈值作易抖动断言。
        for _, f in ipairs({ optimized, oracle }) do
            f.benchmarkCreates, f.benchmarkCPU = 0, 0
            on(f, function(panel)
                local before = copy(f.data)
                local start = os.clock()
                f.creates, f.equips, f.auras = 0, 0, 0
                for _ = 1, 8 do panel.refreshPower() end
                f.benchmarkCPU, f.benchmarkCreates = os.clock() - start, f.creates
                check(same(before, f.data), "连续正式refresh不写回玩家模块/养成/神器")
            end)
        end
        check(same(observation(optimized), observation(oracle)), "连续全刷新同步事件/dirty/三队数值完全一致")
        check(optimized.benchmarkCreates == ownedCount * 8 and oracle.benchmarkCreates == (ownedCount + 36) * 8,
            "八次刷新均重新创建本轮种子，不跨通知缓存")
        print(string.format("[GrowthPowerBenchmark] fullRefreshes=8 candidateCPU=%.6f baselineCPU=%.6f creates=%d/%d",
            optimized.benchmarkCPU, oracle.benchmarkCPU, optimized.benchmarkCreates, oracle.benchmarkCreates))

        -- 同完整buildContext逐目标对照：源队表并不等于Panel显示队表，不能从active/deployed猜。
        local function contextCase(label, change)
            cases = cases + 1
            local data = copy(input)
            data.heroes.teams[2].slots = { 9, 20, 12, 23 }
            if change then change(data) end
            local options = { heroes = data.heroes, equipment = data.equipment,
                artifacts = data.artifacts, talents = data.talents, reuseTeamContext = true }
            local before = copy(data)
            local batch = EP.createWornBatch(options)
            for _, id in ipairs({ 12, 9, 20, 23, 1, 3, 15, 10, 2, 18, 24 }) do
                options.heroData = copy(data.heroes.roster[tostring(id)] or data.heroes.roster[id])
                local ctx = assert(savedBuild(id, options, batch))
                local full = assert(fullBuild(id, options))
                check(ctx.currentPower == full.currentPower, label .. " raw power " .. id)
                check(same(ctx.hero.attrs, full.hero.attrs), label .. " all attrs " .. id)
                local members, fullMembers = {}, {}
                for _, unit in ipairs(ctx.teamUnits) do
                    members[#members + 1] = { id = unit.heroId, slot = unit.partySlot, team = unit.teamIdx,
                        attrs = unit.attrs, awakening = unit.awakening, effects = unit.artifactEffects }
                end
                for _, unit in ipairs(full.teamUnits) do
                    fullMembers[#fullMembers + 1] = { id = unit.heroId, slot = unit.partySlot, team = unit.teamIdx,
                        attrs = unit.attrs, awakening = unit.awakening, effects = unit.artifactEffects }
                end
                check(same(members, fullMembers), label .. " exact team order/slot/artifact/aura " .. id)
            end
            check(same(before, data), label .. " no live writes")
        end
        contextCase("four full source")
        contextCase("cross team duplicate ids", function(data)
            data.heroes.teams[1].slots = { 12, 12, 0, 0 }
            data.heroes.teams[3].slots = { 20, 9, 10, 15 }
        end)
        contextCase("source table string slots", function(data)
            data.heroes.teams = { ["1"] = { slots = { ["2"] = "1", ["4"] = { heroId = "3" } } },
                ["2"] = { slots = { ["1"] = "9", ["2"] = "20", ["4"] = "12" } } }
        end)
        contextCase("nondeployed formal source", function(data)
            data.heroes.deployed = { 9, 20, 12, 23 }
            data.heroes.teams[2].slots = { 0, 0, 0, 0 }
        end)
        contextCase("legacy deployed no teams", function(data)
            data.heroes.teams = nil
            data.heroes.deployed = { 9, 20, 12, 23 }
        end)
        contextCase("nil empty awakening and growth", function(data)
            for _, id in ipairs({ 9, 20, 12, 23 }) do
                data.heroes.roster[tostring(id)].awakening = nil
                data.heroes.roster[tostring(id)].extraTalent = nil
            end
        end)
        contextCase("growth gate closed", function(data)
            for _, id in ipairs({ 9, 20, 12, 23 }) do data.heroes.roster[tostring(id)].awakening = {} end
        end)
        -- 正式bind入口的错槽/错队仍按旧口径禁用整批神器，不能与matches=true混用。
        on(optimized, function(panel, f)
            local batches, withoutArtifacts = {}, {}
            for _, args in ipairs({ { 12, 3, 2 }, { 12, 2, 2 }, { 12, 3, 1 },
                { 15, 1, 3 }, { 15, 1, 2 }, { 2, 1, 1 }, { 12, "3", "2" } }) do
                local id, slot, team = table.unpack(args)
                local deployedSlot, deployedTeam = panel.getHeroDeployPosition(id)
                local matches = tonumber(slot) == deployedSlot and tonumber(team) == deployedTeam
                local expected = assert(fullBuild(id, { heroData = panel.getOwnedHero(id),
                    heroes = f.data.heroes, equipment = f.data.equipment,
                    artifacts = matches and f.data.artifacts or withoutArtifacts, talents = f.data.talents }))
                local batched = f.power.calcHeroPower(id, slot, team, batches)
                check(batched == math.floor(expected.currentPower + 0.5)
                    and batched == f.power.calcHeroPower(id, slot, team),
                    "正式错槽/错队matches隔离 " .. table.concat(args, "/"))
            end
            check(batches[true] ~= nil and batches[false] ~= nil, "真实神器/错槽无神器批次独立")
        end)
        -- 复用窗口内Panel与正式source成长不一致，完整重建仍保留仅目标覆盖。
        on(optimized, function(panel, f)
            local own = panel.getOwnedHero(12)
            local before = own.extraTalent
            own.extraTalent = copy(before)
            own.extraTalent.stacks = 900001
            local batches = {}
            for _, id in ipairs({ 12, 9, 12, 20, 23 }) do
                local slot, team = panel.getHeroDeployPosition(id)
                local full = assert(fullBuild(id, { heroData = panel.getOwnedHero(id), heroes = f.data.heroes,
                    equipment = f.data.equipment, artifacts = f.data.artifacts, talents = f.data.talents }))
                check(f.power.calcHeroPower(id, slot, team, batches) == math.floor(full.currentPower + 0.5),
                    "Panel独立养成覆盖不污染队友source " .. id)
            end
            own.extraTalent = before
        end)
        -- 目标覆盖和队友source确有差异时必须fallback，不以凑4次为由合并。
        local function overrideCase(label, field, value)
            cases = cases + 1
            local data = copy(input)
            data.heroes.teams[2].slots = { 9, 20, 12, 23 }
            local options = { heroes = data.heroes, equipment = data.equipment,
                artifacts = data.artifacts, talents = data.talents, reuseTeamContext = true }
            local batch = EP.createWornBatch(options)
            for _, id in ipairs({ 12, 9, 12, 20 }) do
                options.heroData = copy(data.heroes.roster[tostring(id)])
                if id == 12 then options.heroData[field] = copy(value) end
                local ctx = assert(savedBuild(id, options, batch))
                local full = assert(fullBuild(id, options))
                check(ctx.currentPower == full.currentPower and same(ctx.hero.attrs, full.hero.attrs),
                    label .. " target override remains private " .. id)
                check(same(ctx.heroesData, full.heroesData), label .. " exact source data " .. id)
            end
        end
        overrideCase("different target level", "level", 101)
        overrideCase("different target awakening", "awakening", {})
        overrideCase("different target extra", "extraTalent", { stacks = 99000 })
        overrideCase("unknown nonconsumed growth field", "extraTalent", { stacks = 10, issuedCards = 2, oldUnusedField = 200 })
        overrideCase("normalized zero defaults", "extraTalent", { stacks = 10, issuedCards = 2, shieldStacks = 0 })
        -- issuedCards是唯一normalize之外的直接评分读取：不能把2.25与2归成等价。
        for _, cards in ipairs({ 2.25, -1, "2.25", "nan" }) do
            cases = cases + 1
            local data = copy(input)
            data.heroes.teams[3].slots = { 15, 10, 18, 24 }
            data.heroes.roster["15"].extraTalent.issuedCards = cards
            local options = { heroes = data.heroes, equipment = data.equipment,
                artifacts = data.artifacts, talents = data.talents, reuseTeamContext = true }
            local batch = EP.createWornBatch(options)
            options.heroData = copy(data.heroes.roster["15"])
            options.heroData.extraTalent.issuedCards = 2
            savedBuild(15, options, batch)
            options.heroData = copy(data.heroes.roster["10"])
            local ctx = assert(savedBuild(10, options, batch))
            local full = assert(fullBuild(10, options))
            check(ctx.currentPower == full.currentPower and same(ctx.teamUnits[1].attrs, full.teamUnits[1].attrs),
                "raw issuedCards preserves teammate source " .. tostring(cards))
            check(ctx.heroesData.roster["15"].extraTalent.issuedCards == cards,
                "raw issuedCards source remains unchanged " .. tostring(cards))
        end
        runCase("reset session", function(panel) panel.resetSessionData() end, 0, {})
        runCase("cold rehydrate", function(panel, f) panel.setHeroesData(f.data.heroes) end, ownedCount)
        check(storage == 0, "全测试无玩家File/FS访问")
    end)
    HC.createHero, Eq.applyToUnit, ESR.applyTeamAura = savedCreate, savedApply, savedAura
    EP.buildWornContext, EP.invalidate, require = savedBuild, savedInvalidate, nativeRequire
    rawset(_G, "File", savedFile)
    rawset(_G, "fileSystem", savedFS)
    HC.setDefaultLitNodes(savedLit)
    if not ok then check(false, "exception " .. tostring(err)) end
    print(string.format("[character_growth_power_perf_test] %s cases=%d assertions=%d failures=%d",
        failures == 0 and "ALL PASS" or "FAIL", cases, checks, failures))
    engine:Exit()
end
