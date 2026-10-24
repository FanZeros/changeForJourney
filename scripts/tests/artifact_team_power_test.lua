-- 神器详情分数独立计入队伍；沿用 growth 的真实 Panel + 只读源码隔离脚手架。
-- 不启动 main；File/FS 封闭，Store/Dispatcher/Draw/导航/战斗通知仅为外围替身。
local checks, failures, cases = 0, 0, 0
local function check(ok, message)
    checks = checks + 1
    if not ok then failures = failures + 1; print("[ArtifactTeamPower][FAIL] " .. message) end
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
    local storage = 0
    local function denyIO() storage = storage + 1; error("artifact team power test forbids player IO") end
    rawset(_G, "File", denyIO)
    rawset(_G, "fileSystem", setmetatable({}, { __index = function() return denyIO end }))
    local HC = nativeRequire("config.HeroConfig")
    local EP = nativeRequire("systems.EquipmentPower")
    local AD = nativeRequire("systems.AttributeDef")
    local Defs = nativeRequire("shared.artifact.ArtifactDefs")
    local Schema = nativeRequire("shared.artifact.ArtifactSchema")
    local Bridge = nativeRequire("systems.ArtifactBridge")
    local Events = nativeRequire("config.GameEvents")
    local Draw = nativeRequire("ui.character.panel.CharacterPanelDraw2")
    local savedCreate, savedLit = HC.createHero, HC._getSavedLitNodes()
    local creates, batchCalls, reuseCalls = 0, 0, 0
    local savedBatch, savedBuild = EP.createWornBatch, EP.buildWornContext
    HC.createHero = function(...)
        creates = creates + 1
        return savedCreate(...)
    end
    EP.createWornBatch = function(...)
        batchCalls = batchCalls + 1
        return savedBatch(...)
    end
    EP.buildWornContext = function(id, options, batch)
        if options.reuseTeamContext and batch then reuseCalls = reuseCalls + 1 end
        return savedBuild(id, options, batch)
    end
    local f = { data = {}, revisions = { heroes = 1, equipment = 1, artifacts = 1, talents = 1 },
        modules = {}, listeners = {}, storeListeners = {}, events = {}, gamePower = 0, dirty = 0,
        battleRefreshes = 0, context = {}, detailContext = {} }
    local noop = function() end
    -- 独立 oracle 不调用 Bridge helper，不拿总分缓存作为自身期望。
    local function artifactOracle(teamIdx)
        local slots = f.panel.getTeamSlotsData(teamIdx)
        local counted, total = {}, 0
        local data = f.data.artifacts or {}
        for slot = 1, Schema.SLOT_COUNT do
            for subSlot = 1, Schema.SUB_SLOT_COUNT do
                local id = Schema.getEquippedId(data, slot, subSlot, teamIdx)
                local instance
                for _, item in ipairs(data.bag or {}) do
                    if tostring(item.id) == tostring(id) then instance = item; break end
                end
                local def = instance and Defs.get(instance.artifactId)
                if def and not counted[tostring(id)] then
                    local target = slot
                    if def.effectType == "left_phys_atk_bonus" then target = slot - 1 end
                    if def.effectType == "right_mag_atk_bonus" then target = slot + 1 end
                    local owner = slots[target]
                    if target >= 1 and target <= 4 and owner and owner.state == "occupied"
                        and f.panel.getOwnedHero(owner.heroId) then
                        total = total + Defs.getPower(instance)
                        counted[tostring(id)] = true
                    end
                end
            end
        end
        return total
    end
    local function verify(label, payload)
        for t = 1, 3 do
            local slots, powers = f.panel.getTeamSlotsData(t)
            local total = artifactOracle(t)
            for slot = 1, 4 do
                local owner = slots[slot]
                local expected = owner and owner.state == "occupied" and f.panel.getRosterPower(owner.heroId) or 0
                check((powers[slot] or 0) == (expected or 0), label .. " role slot " .. t .. "/" .. slot)
                total = total + (expected or 0)
            end
            check(f.panel.getTotalPower(t) == total, label .. " exact team sum " .. t)
            check(f.powerGet("artifactPowerCaches")[t] == artifactOracle(t), label .. " separate artifact cache " .. t)
            if payload then check(payload.powers[t] == total, label .. " event snapshot " .. t) end
        end
        check(f.gamePower == f.panel.getTotalPower(1), label .. " GameState stays team1")
    end
    local store = { Get = function(key) return f.data[key] end,
        GetRevision = function(key) return f.revisions[key] or 0 end,
        Subscribe = function(key, fn) f.storeListeners[key] = fn end }
    local mocks = {
        ["core.PlayerStore"] = store,
        ["runtime.ClientDispatcher"] = { get = store.Get,
            subscribe = function(key, fn) f.listeners[key] = fn end },
        ["core.GameState"] = { getLevel = function() return 100 end,
            setPower = function(value) f.gamePower = value end },
        ["core.EventBus"] = { emit = function(event, payload)
            if event == Events.TEAM_POWER_CHANGED then
                verify("synchronous publish", payload)
                f.events[#f.events + 1] = copy(payload)
            end
        end },
        ["ui.character.panel.CharacterPanelDraw2"] = setmetatable({
            setContext = function(ctx) f.context = ctx end, initImages = noop,
            getSharedImages = function() return {} end, resetPresentation = noop,
            clearSortInteraction = noop, clearTeamInteraction = noop }, { __index = Draw }),
        ["ui.character.detail.CharacterDetail"] = { init = noop,
            setContext = function(ctx) f.detailContext = ctx end,
            markPowerDirty = function() f.dirty = f.dirty + 1 end,
            hasAwakeningUpgrade = function() return false end,
            hasAnyUpgradeForHero = function() return false end },
        ["ui.hud.BottomNav"] = { setBadge = noop, refreshTownBadge = noop },
        ["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end },
        ["ui.battle.scene.BattleScene"] = { refreshAllyStats = function()
            f.battleRefreshes = f.battleRefreshes + 1
            verify("battle pending callback")
        end },
        ["ui.battle.tri.BattleTriPage"] = { invalidateTeams = noop, refreshHeroProgressTeams = noop },
        ["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return false end },
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
                    return power
                end
            end
            f.modules[name] = module
            return module
        end
        return nativeRequire(name)
    end
    local ok, err = pcall(function()
        require = resolver
        f.panel = resolver("ui.character.panel.CharacterPanel")
        f.panel.init({})
        local input = { heroes = { roster = {}, deployed = { 1, 3, 4, 5 }, teams = {
            { slots = { 1, 3, 4, 5 } }, { slots = { 9, 20, 12, 23 } }, { slots = { 15, 10, 18, 24 } } } },
            equipment = { inventory = {}, equipped = {} }, talents = { litNodes = {} },
            battle = { clearedStages = { [905] = true, [1905] = true }, maxStageId = 2305 },
            artifacts = { bag = {}, equippedByTeam = {} } }
        local ownedCount = 0
        for _, id in ipairs(HC.getAllIds()) do
            if id ~= 25 then
                input.heroes.roster[tostring(id)] = { level = 70, exp = 0, maxExp = 100,
                    awakening = {}, extraTalent = {}, advBranch = {} }
                ownedCount = ownedCount + 1
            end
        end
        f.data = copy(input)
        f.panel.setHeroesData(f.data.heroes)
        local function roleScores()
            local result = {}
            for _, entry in ipairs(f.context.getHeroRoster()) do
                if entry.owned then result[entry.heroId] = {
                    power = f.panel.getRosterPower(entry.heroId),
                    estimate = f.detailContext.calcHeroEstimate(entry.heroId),
                } end
            end
            return result
        end
        local bare = roleScores()
        local function notify(cause)
            f.revisions.artifacts = f.revisions.artifacts + 1
            local before, dirty = #f.events, f.dirty
            if cause then
                Schema.withEquipNotification(f.data.artifacts, function()
                    f.storeListeners.artifacts(f.data.artifacts)
                end)
            else f.storeListeners.artifacts(f.data.artifacts) end
            check(#f.events == before + 1 and f.dirty == dirty + 1, "one immediate complete publication")
            check(f.events[#f.events].cause == cause, "private notification cause consumed once")
            check(Schema.takeEquipNotificationCause(f.data.artifacts) == nil, "private cause cannot leak after notify")
            verify("after notify")
        end
        -- 每种神器含惩罚/固定bonus/反击都不得污染角色分数及估值。
        for id = 1, 16 do
            cases = cases + 1
            local artifact = { id = "a", artifactId = id, quality = 6, value = Defs.ratioToValue(id, 6, 10000) }
            f.data.artifacts = { bag = { artifact }, equippedByTeam = { { {}, { "a" } } } }
            local before = copy(f.data)
            notify("artifact_equip")
            check(same(roleScores(), bare), "all role powers/estimates exclude artifact " .. id)
            check(f.powerGet("artifactPowerCaches")[1] == Defs.getPower(artifact), "detail pricing type " .. id)
            check(same(before, f.data), "refresh is read-only type " .. id)
        end
        -- 双格取 schema 已装引用；明确低等级不额外关掉现有装配。
        cases = cases + 1
        f.data.artifacts = { bag = {
            { id = "a", artifactId = 5, quality = 1, value = 35 },
            { id = "b", artifactId = 9, quality = 6, value = 600 },
            { id = "left", artifactId = 7, quality = 2, value = 18 },
            { id = "right", artifactId = 8, quality = 3, value = 26 },
            { id = "unknown", artifactId = 9999, power = 999999 },
        }, equippedByTeam = { { { "a", "b" } }, {}, {} } }
        notify("artifact_equip")
        local a, b = f.data.artifacts.bag[1], f.data.artifacts.bag[2]
        check(f.powerGet("artifactPowerCaches")[1] == Defs.getPower(a) + Defs.getPower(b), "two installed subslots add detail values")
        local lowSlots = { { state = "occupied", heroId = 1 } }
        check(Bridge.getTeamPower(f.data.artifacts, lowSlots, { [1] = { level = 1 } }, 1)
            == Defs.getPower(a) + Defs.getPower(b), "helper introduces no level unlock gate")
        -- helper 不回读Store、不水合、不改变原Schema；数字/文本旧键并存。
        local mixed = { bag = copy(f.data.artifacts.bag), et = {
            [1] = { [1] = { [1] = "a" } }, ["1"] = { ["1"] = { ["2"] = "b" } } } }
        local mixedBefore = copy(mixed)
        check(Bridge.getTeamPower(mixed, lowSlots, { ["1"] = { level = 1 } }, 1)
            == Defs.getPower(a) + Defs.getPower(b), "mixed schema keys preserve complementary cells")
        check(same(mixed, mixedBefore), "helper never normalizes installed schema")
        local beforePure, beforeOwn = copy(lowSlots), copy(f.data)
        local readGuard = 0
        local function denyLive() readGuard = readGuard + 1; error("pure helper read live modules") end
        local pureBridge = sourceModule("systems.ArtifactBridge", function(name)
            if name == "core.PlayerStore" or name == "runtime.ClientDispatcher" then
                return { Get = denyLive, get = denyLive }
            end
            return nativeRequire(name)
        end)
        check(pureBridge.getTeamPower(mixed, lowSlots, { [1] = { level = 1 } }, 1)
            == Defs.getPower(a) + Defs.getPower(b) and readGuard == 0,
            "explicit helper never reads Store or Dispatcher")
        check(same(lowSlots, beforePure) and same(f.data, beforeOwn), "pure helper preserves roster and module snapshots")
        -- 本队重复实例只算一次，未知/悬空引用均不能以显式power伪造战力。
        cases = cases + 1
        f.data.artifacts.equippedByTeam[1] = { { "a", "a" }, { "unknown", "missing" }, { "a" } }
        notify(nil)
        check(f.powerGet("artifactPowerCaches")[1] == Defs.getPower(a), "duplicate unknown dangling skip")
        check(same(roleScores(), bare), "dirty references cannot change roles")
        -- 空槽/锁槽/未拥有不能承接自身神器；左右使用真实邻位目标而非owner。
        local own = { [1] = { level = 1 } }
        local one = { { state = "occupied", heroId = 1 }, { state = "empty" },
            { state = "occupied", heroId = 9999 }, { state = "locked", heroId = 1 } }
        local edge = { bag = copy(f.data.artifacts.bag), equippedByTeam = { {
            {}, { "a", "left" }, { "b" }, { "a" } } } }
        check(Bridge.getTeamPower(edge, one, own, 1) == Defs.getPower(edge.bag[3]),
            "empty owner left effect counts only its real owned neighbor")
        edge.equippedByTeam[1] = { { "left", "right" } }
        check(Bridge.getTeamPower(edge, one, own, 1) == 0, "edge/no-neighbor left/right have no effective target")
        one[2] = { state = "occupied", heroId = 1 }
        check(Bridge.getTeamPower(edge, one, own, 1) == Defs.getPower(edge.bag[4]),
            "right counts real target regardless of damage category")
        check(Bridge.getTeamPower(nil, one, own, 1) == 0 and Bridge.getTeamPower(edge, nil, own, 1) == 0
            and Bridge.getTeamPower(edge, one, nil, 1) == 0, "missing explicit inputs are zero without live fallback")
        -- 真实 schema 跨队转移：同步源队减、目标队加，活动队不改变顶栏口径。
        cases = cases + 1
        f.data.artifacts.equippedByTeam = { { { "a", "b" } }, {}, {} }
        notify("artifact_equip")
        local beforeTeam1, beforeTeam3 = f.panel.getTotalPower(1), f.panel.getTotalPower(3)
        check(f.panel.setActiveTeam(2), "switch edit view to team2")
        Schema.setEquippedId(f.data.artifacts, 1, 1, "a", 3)
        notify("artifact_equip")
        check(f.panel.getTotalPower(1) == beforeTeam1 - Defs.getPower(a)
            and f.panel.getTotalPower(3) == beforeTeam3 + Defs.getPower(a), "transfer updates both teams in same notification")
        check(f.panel.getTotalPower() == f.panel.getTotalPower(2) and f.gamePower == f.panel.getTotalPower(1),
            "default follows editor but GameState remains team1")
        check(same(roleScores(), bare), "cross-team artifact transfer leaves roles unchanged")
        local pureRole = HC.createHero(15, 70)
        local runtime = Bridge.applyToUnit(pureRole.attrs, 1, f.data.artifacts, 3)
        check(pureRole.attrs.artifactPowerBonus == a.value * 0.5
            and #runtime == 1 and runtime[1].effectType == "counter_attack",
            "battle bridge still applies original fixed effect and counter runtime")
        local counterTeamPower = f.powerGet("artifactPowerCaches")[3]
        a.power = Defs.getPower(a) + 17
        notify(nil)
        check(f.powerGet("artifactPowerCaches")[3] == counterTeamPower + 17 and same(roleScores(), bare),
            "in-place detail power mutation is consumed immediately without role contamination")
        notify(nil)
        check(f.events[#f.events].cause == nil, "ordinary notification cannot borrow prior private cause")
        -- 清空队1及丢失artifacts后必须即时清分，不留上轮装配分项。
        f.data.heroes.deployed = { 0, 0, 0, 0 }
        f.panel.setHeroesData(f.data.heroes)
        check(f.powerGet("artifactPowerCaches")[1] == 0 and f.panel.getTotalPower(1) == 0 and f.gamePower == 0,
            "no deployed team clears role/artifact/GameState together")
        f.data.artifacts = nil
        f.storeListeners.artifacts(nil)
        check(same(f.powerGet("artifactPowerCaches"), { 0, 0, 0 }), "missing module clears all artifact caches")
        -- 同刷新共享队上下文，但下一刷新必须重新创建并读取全部角色。
        cases = cases + 1
        f.data = copy(input)
        f.panel.setHeroesData(f.data.heroes)
        creates, batchCalls, reuseCalls = 0, 0, 0
        f.panel.refreshPower()
        check(creates == ownedCount and batchCalls == 1 and reuseCalls == ownedCount,
            "full refresh retains one worn batch and one create per hero")
        f.panel.refreshPower()
        check(creates == ownedCount * 2 and batchCalls == 2 and reuseCalls == ownedCount * 2,
            "second refresh rebuilds its own team contexts without cross-refresh reuse")
        f.data.artifacts = { bag = { a }, equippedByTeam = { { { "a" } }, { { "a" } } } }
        notify(nil)
        check(f.panel.setActiveTeam(3), "switch editor before reset")
        f.panel.resetSessionData()
        check(same(f.powerGet("artifactPowerCaches"), { 0, 0, 0 }) and f.gamePower == 0
            and f.panel.getTotalPower(1) == 0 and f.panel.getTotalPower(2) == 0 and f.panel.getTotalPower(3) == 0,
            "session reset clears every artifact cache before publication")
        f.panel.setHeroesData(f.data.heroes)
        verify("rehydrate")
        check(f.events[#f.events].ready == true, "rehydrate immediately publishes ready complete totals")
        check(storage == 0 and f.battleRefreshes > 0, "no File/FS and actual battle refresh callback retained")
    end)
    HC.createHero, EP.createWornBatch, EP.buildWornContext = savedCreate, savedBatch, savedBuild
    HC.setDefaultLitNodes(savedLit)
    require = nativeRequire
    rawset(_G, "File", savedFile)
    rawset(_G, "fileSystem", savedFS)
    if not ok then check(false, "exception " .. tostring(err)) end
    print(string.format("[artifact_team_power_test] %s cases=%d assertions=%d failures=%d",
        failures == 0 and "ALL PASS" or "FAIL", cases, checks, failures))
    engine:Exit()
end
