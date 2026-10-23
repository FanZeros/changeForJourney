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
    local Draw = nativeRequire("ui.character.panel.CharacterPanelDraw2")
    local savedBuild, fullBuild, savedLit = EP.buildWornContext, EP.buildContext, HC._getSavedLitNodes()
    local active = {}
    local storage = 0
    local function denyIO() storage = storage + 1; error("growth power test forbids player IO") end
    rawset(_G, "File", denyIO)
    rawset(_G, "fileSystem", setmetatable({}, { __index = function() return denyIO end }))
    EP.buildWornContext = function(...)
        active.calls = active.calls + 1
        local id = select(1, ...)
        active.scored[id] = (active.scored[id] or 0) + 1
        return savedBuild(...)
    end
    local function fixture(forceFull)
        local f = { data = {}, revisions = { equipment = 1, artifacts = 1, talents = 1 },
            calls = 0, scored = {}, events = {}, progress = {}, invalidations = {}, dirty = 0,
            context = {}, modules = {}, listeners = {}, storeListeners = {}, gamePower = 0 }
        local noop = function() end
        local detail = { init = noop, setContext = noop, markPowerDirty = function() f.dirty = f.dirty + 1 end,
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
                if value ~= f.gamePower then
                    f.gamePower = value
                    f.events[#f.events + 1] = { event = Events.PLAYER_POWER_CHANGED, power = value }
                end
            end },
            ["core.EventBus"] = { emit = function(event, payload)
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
                if leaf == "CharacterPower" and forceFull then
                    local bind = module.bind
                    module.bind = function(deps)
                        local power = bind(deps)
                        local refresh = power.refreshPowerCache
                        power.refreshPowerCache = function(cause) return refresh(cause) end
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
                    lastTeams = panel.getLastHeroesRefreshTeams(), gamePower = f.gamePower }
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
                    local total = 0
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
                on(f, action)
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
            print(string.format("[GrowthPower] case=%s calls=%d fullCalls=%d", label, optimized.calls, oracle.calls))
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
        check(fullBuild(15, options).currentPower > fullBuild(15, noArtifactOptions).currentPower,
            "队3神器fixture真实非零，不借当前活动队1")
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
        runCase("reset session", function(panel) panel.resetSessionData() end, 0, {})
        runCase("cold rehydrate", function(panel, f) panel.setHeroesData(f.data.heroes) end, ownedCount)
        check(storage == 0, "全测试无玩家File/FS访问")
    end)
    EP.buildWornContext, require = savedBuild, nativeRequire
    rawset(_G, "File", savedFile)
    rawset(_G, "fileSystem", savedFS)
    HC.setDefaultLitNodes(savedLit)
    if not ok then check(false, "exception " .. tostring(err)) end
    print(string.format("[character_growth_power_perf_test] %s cases=%d assertions=%d failures=%d",
        failures == 0 and "ALL PASS" or "FAIL", cases, checks, failures))
    engine:Exit()
end
