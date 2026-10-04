-- T08：真实转职回执 → ChurchResults → CharacterProgress → Boot。
-- 真实角色面板、转职规则、三队驱动、精准失效与战斗统计；
-- 仅绘制、导航、启动外围服务使用替身，不写存档、不改经济规则。
local checks, failures = 0, 0
local function check(value, label)
    checks = checks + 1
    if not value then failures = failures + 1 end
    print("[team_progress_refresh] " .. (value and "PASS " or "FAIL ") .. label)
end

function Start()
    local nativeRequire = require
    local restores = {}
    local function replace(owner, key, value)
        local old = owner[key]
        restores[#restores + 1] = function() owner[key] = old end
        owner[key] = value
    end
    local function sourceModule(path, resolver)
        local file = assert(cache:GetFile(path), "missing source " .. path)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local env = setmetatable({ require = resolver }, { __index = _G })
        return assert(load(table.concat(lines, "\n"), "@" .. path, "t", env))()
    end
    local function same(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do if not same(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    local ok, err = pcall(function()
        local CP = nativeRequire("ui.character.panel.CharacterPanel")
        local Stats = nativeRequire("systems.BattleStats")
        local Page = nativeRequire("ui.battle.tri.BattleTriPage")
        local Driver = nativeRequire("ui.battle.tri.BattleTriDriver")
        local Scene = nativeRequire("ui.battle.scene.BattleScene")
        local HC = nativeRequire("config.HeroConfig")
        local AVC = nativeRequire("config.AdvancementConfig")
        local AD = nativeRequire("systems.AttributeDef")
        local Protocol = nativeRequire("shared.Protocol")
        local Dispatcher = nativeRequire("runtime.ClientDispatcher")
        -- 执行真实 init 注册 heroes 订阅；只跳过图像加载和详情像素初始化。
        local Draw = nativeRequire("ui.character.panel.CharacterPanelDraw2")
        local Detail = nativeRequire("ui.character.detail.CharacterDetail")
        replace(Draw, "initImages", function() end)
        replace(Detail, "init", function() end)
        local subscribe = Dispatcher.subscribe
        replace(Dispatcher, "subscribe", function(name, callback)
            subscribe(name, callback)
            restores[#restores + 1] = function() Dispatcher.unsubscribe(name, callback) end
        end)
        CP.init(nil)
        local PDM = nativeRequire("rules.character.PlayerDataManager")
        local Bridge = nativeRequire("runtime.LocalActionBridge")
        local TaskService = nativeRequire("rules.task.TaskService")
        local handlers = nativeRequire("rules.advancement.AdvancementHandler")
        local modules = Dispatcher.getAll()
        local heroes = { roster = {}, deployed = { 1, 0, 0, 0 }, teams = {
            { slots = { 1, 0, 0, 0 } }, { slots = { 2, 0, 0, 0 } }, { slots = { 3, 0, 0, 0 } },
        } }
        for _, id in ipairs({ 1, 2, 3, 25 }) do
            heroes.roster[id] = { level = 30, exp = 0, shards = 0 }
        end
        local battle = { currentStageId = 101, maxStageId = 2001,
            teamCurrentStageIds = { 101, 102, 103 }, battleMode = "idle",
            clearedStages = { ["905"] = true, ["1905"] = true } }
        replace(modules, "heroes", heroes)
        replace(modules, "battle", battle)
        replace(modules, "currency", { gold = 100000000 })
        replace(modules, "equipment", { inventory = {}, equipped = {} })
        replace(modules, "lootbox", { seeds = {} })
        replace(modules, "player", { name = "T08", level = 30 })
        replace(PDM, "GetModule", function(_, key) return modules[key] end)
        local pushes, teamCommits = 0, 0
        replace(PDM, "MarkDirty", function(_, key)
            pushes = pushes + 1
            Dispatcher.set(key, modules[key])
        end)
        replace(TaskService, "RefreshAchievements", function() end)
        replace(Scene, "pumpBattleCards", function() end)
        CP.setHeroesData(heroes)
        Scene.setBattleData(battle)
        Scene.adoptStageProgress(101)
        Page.setTeamStageIds({ 101, 102, 103 })
        Page.setBattleReady(true)
        local drivers = {}
        local makeDriver = Driver.new
        replace(Driver, "new", function(team, options)
            local drv = makeDriver(team, options)
            drivers[team] = drv
            return drv
        end)
        Page.open()
        check(drivers[1] and drivers[2] and drivers[3], "real Page created all three real drivers")
        local noop = function() end
        local function stub(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local setTeams = Bridge.setTeams
        local sceneReloads, sceneSets, sceneRefreshes, formationEvents = 0, 0, 0, 0
        local oldSetAllies, oldRefresh = Scene.setAllies, Scene.refreshAllyStats
        replace(Scene, "reloadStage", function() sceneReloads = sceneReloads + 1 end)
        replace(Scene, "setAllies", function(list)
            sceneSets = sceneSets + 1
            oldSetAllies(list)
        end)
        replace(Scene, "refreshAllyStats", function()
            sceneRefreshes = sceneRefreshes + 1
            oldRefresh()
        end)
        local setFormation = CP.setOnTeamChanged
        replace(CP, "setOnTeamChanged", function(callback)
            setFormation(function(...)
                formationEvents = formationEvents + 1
                return callback(...)
            end)
        end)
        local bootMocks = {
            ["ui.character.panel.CharacterPanel"] = CP,
            ["systems.BattleStats"] = Stats,
            ["ui.battle.tri.BattleTriPage"] = Page,
            ["ui.battle.scene.BattleScene"] = Scene,
            ["runtime.ClientDispatcher"] = Dispatcher,
            ["config.StageConfig"] = nativeRequire("config.StageConfig"),
            ["core.PlayerStore"] = stub(),
            ["runtime.LocalActionBridge"] = stub({ setTeams = function(layout)
                teamCommits = teamCommits + 1
                return setTeams(layout)
            end }),
        }
        local function bootRequire(name)
            if not bootMocks[name] then bootMocks[name] = stub() end
            return bootMocks[name]
        end
        local Boot = sourceModule("boot/StandaloneBoot.lua", bootRequire)
        Boot.run({ vg = nil, localSendAction = noop })
        local presentation = {
            ["ui.church.ChurchClassChange"] = { showFloat = noop },
            ["ui.character.detail.CharacterDetail"] = nativeRequire("ui.character.detail.CharacterDetail"),
            ["ui.hud.BottomNav"] = stub(),
        }
        local ChurchResults = sourceModule("ui/church/ChurchResults.lua", function(name)
            return presentation[name] or nativeRequire(name)
        end)
        local powerClears = 0
        local receipts = ChurchResults.bind({ state = { open = false }, ANIM = {}, CHAR_SLOT = {},
            getProtocol = function() return Protocol end, ArtifactPanel = stub(),
            ArtifactDrawPanel = stub(), CharacterPanel = CP, SpineCardEffect = stub(),
            clearPowerCache = function() powerClears = powerClears + 1 end,
        })
        local invalidations = {}
        local invalidate = Page.invalidateTeams
        replace(Page, "invalidateTeams", function(teams)
            local copied = {}
            if teams then for t, selected in pairs(teams) do copied[t] = selected end end
            invalidations[#invalidations + 1] = teams and copied or false
            return invalidate(teams)
        end)
        local starts = { 0, 0, 0 }
        for team, drv in ipairs(drivers) do
            local start = drv.start
            drv.start = function(self, stage)
                starts[team] = starts[team] + 1
                return start(self, stage)
            end
            -- 保留签名检查和真实 start，不推进战斗时间。
            drv.tick = noop
        end
        local function firstBranch(heroId)
            local class = HC.get(heroId).classId
            for id = 101, 112 do
                local cfg = AVC.get(id)
                if cfg and cfg.baseClass == class then return id end
            end
            error("no valid branch for hero " .. heroId)
        end
        local function seedStats()
            for team = 0, 3 do
                Stats.mount(team)
                Stats.reset()
                Stats.resetAccum()
                local unit = { heroId = 100 + team, name = "stat" .. team }
                Stats.recordDamage(unit, 1000 + team, "physical", true)
                Stats.recordDotDamage(unit, 100 + team)
                Stats.recordHeal(unit, 50 + team, true)
                Stats.recordTaken(unit, 20 + team)
            end
            Stats.mount(3)
        end
        local function statsSnapshot()
            local mounted = Stats.mountedTeam()
            local result = {}
            for team = 0, 3 do
                Stats.mount(team)
                result[team] = cjson.decode(cjson.encode({ wave = Stats.getSorted("totalDamage"),
                    accum = Stats.getSorted("totalDamage", true),
                    duration = Stats.getDuration(true), hasData = Stats.hasData(true) }))
            end
            Stats.mount(mounted)
            return result
        end
        local function driverSnapshot(drv)
            return { signature = drv.teamSignature, stage = drv.stageId, allies = drv.allies,
                attrs = drv.allies[1].attrs, hp = drv.allies[1].hp,
                combos = drv.combatState.comboQueue, projectiles = drv.psState.projectiles,
                effects = drv.semState.effects, threat = drv.tmState.threatTable,
                immunity = drv.rchState.unitStates, kills = drv.kills, active = drv.active }
        end
        local function unchanged(drv, old)
            return drv.stageId == old.stage and drv.allies == old.allies
                and drv.allies[1].attrs == old.attrs and drv.allies[1].hp == old.hp
                and drv.combatState.comboQueue == old.combos and old.combos[1].timer == 0.7
                and drv.psState.projectiles == old.projectiles
                and drv.semState.effects == old.effects and drv.tmState.threatTable == old.threat
                and drv.rchState.unitStates == old.immunity and drv.kills == old.kills
                and drv.active == old.active
        end
        local function runReceipt(heroId, target, reset, closed)
            local label = (closed and "closed " or "open ") .. (reset and "reset " or "advance ")
                .. "hero=" .. heroId .. " team=" .. tostring(target)
            if closed then Page.close() else Page.open() end
            for _, drv in ipairs(drivers) do
                drv.combatState.comboQueue = { { timer = 0.7 } }
                drv.psState.projectiles = { { onHit = noop } }
                drv.kills = 7
                drv.allies[1].hp = math.max(1, drv.allies[1].hp - 1)
                drv.teamSignature = CP.getTeamSignature(drv.teamIdx)
                drv._sigTick = 0
                drv.marchTimer = 0
            end
            seedStats()
            local oldStats, oldDrivers = statsSnapshot(), {}
            for team, drv in ipairs(drivers) do oldDrivers[team] = driverSnapshot(drv) end
            local oldFormation, oldCommits = formationEvents, teamCommits
            local oldReload, oldSets, oldRefresh = sceneReloads, sceneSets, sceneRefreshes
            local oldInvalid, oldClear = #invalidations, powerClears
            local defaultUnit = Scene.getAllies()[1]
            local defaultHp, defaultAttrs = defaultUnit and defaultUnit.hp, defaultUnit and defaultUnit.attrs
            local action = reset and Protocol.ACTION_TYPES.RESET_CLASS or Protocol.ACTION_TYPES.ADVANCE_CLASS
            local result = handlers[action](1, { heroId = heroId, branchId = firstBranch(heroId), advLevel = 1 })
            result.action = action
            check(result.success, label .. " real handler/service success")
            receipts.onActionResult(result)
            check(reset and not CP.getOwnedHero(heroId).advBranch
                or not reset and CP.getOwnedHero(heroId).advBranch.first == result.branchId,
                label .. " receipt synchronized owned progression")
            check(powerClears == oldClear + 1, label .. " real ChurchResults refreshed UI power")
            check(formationEvents == oldFormation and teamCommits == oldCommits,
                label .. " no fabricated formation callback or setTeams transaction")
            check(sceneReloads == oldReload and sceneSets == oldSets, label .. " no default Scene reload/setAllies")
            check(sceneRefreshes == oldRefresh + ((closed and target == 1) and 1 or 0),
                label .. " only closed-page team1 refreshes default Scene")
            if closed and target == 1 then
                check(defaultUnit and defaultUnit.heroId == heroId and defaultUnit.hp == defaultHp
                    and defaultUnit.attrs == defaultAttrs and defaultUnit._pendingSnapshot,
                    label .. " default live hp/attrs preserved with pending snapshot")
                check(defaultUnit and ((reset and not defaultUnit.advBranch and #defaultUnit.advTalentIds == 0)
                    or (not reset and defaultUnit.advBranch and defaultUnit.advBranch.first == result.branchId
                        and #defaultUnit.advTalentIds > 0)), label .. " default live progression clears on reset")
            end
            local changed = invalidations[oldInvalid + 1]
            check(target and #invalidations == oldInvalid + 1 and changed and changed[target]
                or not target and #invalidations == oldInvalid,
                label .. " invalidated only real deployment (none when undeployed)")
            for team, drv in ipairs(drivers) do
                check((team == target and drv.teamSignature == nil)
                    or (team ~= target and drv.teamSignature == oldDrivers[team].signature),
                    label .. " signature gate team " .. team)
                if team ~= target then check(unchanged(drv, oldDrivers[team]), label .. " unrelated live state " .. team) end
            end
            local afterStats = statsSnapshot()
            for team = 0, 3 do
                check(same(afterStats[team], oldStats[team]), label .. " wave/cumulative stats retained " .. team)
            end
            -- 走真实驱动的十五帧签名检查和战斗单位重建。
            local oldStarts = { starts[1], starts[2], starts[3] }
            for _, drv in ipairs(drivers) do for _ = 1, 15 do drv:update(0) end end
            for team, drv in ipairs(drivers) do
                check(starts[team] == oldStarts[team] + (team == target and 1 or 0),
                    label .. " real rebuild restricted to team " .. team)
                if team ~= target then check(unchanged(drv, oldDrivers[team]), label .. " unrelated state after rebuild " .. team) end
                Stats.mount(team)
                check(same(cjson.decode(cjson.encode(Stats.getSorted("totalDamage", true))),
                    oldStats[team].accum), label .. " cumulative stats survive real start " .. team)
                if team == target then
                    local unit = drv.allies[1]
                    check(unit.heroId == heroId and (reset and not unit.advBranch
                        or not reset and unit.advBranch and unit.advBranch.first == result.branchId),
                        label .. " rebuilt real battle unit progression")
                    local own = CP.getOwnedHero(heroId)
                    local expected = HC.createHero(heroId, own.level, own.advBranch, own.awakening, own.extraTalent)
                    check(unit.attrs:get(AD.MAX_HP) == expected.attrs:get(AD.MAX_HP),
                        label .. " real attribute pipeline matches progression")
                end
            end
            Stats.mount(3)
        end
        for _, closed in ipairs({ false, true }) do
            if closed then Scene.setAllies(CP.getDeployedTeam(1)) end
            for index, heroId in ipairs({ 1, 2, 3, 25 }) do
                local target = index <= 3 and index or nil
                CP.setActiveTeam(index % 3 + 1) -- 查看其他队不应改变真实所属队路由
                runReceipt(heroId, target, false, closed)
                runReceipt(heroId, target, true, closed)
            end
        end
        -- 失败/未知英雄回执不得修改任何队伍。
        local oldInvalid, oldFormation = #invalidations, formationEvents
        receipts.onActionResult({ action = Protocol.ACTION_TYPES.ADVANCE_CLASS, success = false, heroId = 1 })
        receipts.onActionResult({ action = Protocol.ACTION_TYPES.RESET_CLASS, success = false, heroId = 2 })
        CP.setHeroAdvBranch(999, 101, 1)
        CP.resetHeroAdvBranch(999)
        check(#invalidations == oldInvalid and formationEvents == oldFormation, "failed and unknown-hero receipts do not refresh teams")
        -- 真实原地推送：闭页队一属性变化保留轻刷新，旁队/未上阵不借用默认 Scene。
        for _, id in ipairs({ 1, 2, 3, 25 }) do
            heroes.roster[id].awakening = { _awk3Migrated = true }
            heroes.roster[id].extraTalent = nativeRequire("systems.ExtraTalentSystem").normalize(nil)
        end
        CP.setHeroesData(heroes)
        for _, open in ipairs({ false, true }) do
            if open then Page.open() else Page.close() end
            for _, field in ipairs({ "level", "awakening", "extraTalent" }) do
                for index, id in ipairs({ 1, 2, 3, 25 }) do
                    seedStats()
                    local beforeStats = statsSnapshot()
                    local beforeRefresh, beforeInvalid = sceneRefreshes, #invalidations
                    local hero = heroes.roster[id]
                    if field == "level" then hero.level = hero.level + 1
                    elseif field == "awakening" then hero.awakening[open and 2 or 1] = true
                    else hero.extraTalent.stacks = hero.extraTalent.stacks + 1 end
                    Dispatcher.set("heroes", heroes)
                    check(sceneRefreshes == beforeRefresh + ((not open and index == 1) and 1 or 0),
                        "real in-place " .. field .. " push hero=" .. id .. " open=" .. tostring(open) .. " default refresh scope")
                    check(#invalidations == beforeInvalid, "nonclass attribute push keeps formation signatures")
                    local afterStats = statsSnapshot()
                    for team = 0, 3 do
                        check(same(beforeStats[team], afterStats[team]), "attribute push retains stats team " .. team)
                    end
                end
            end
        end
        Page.close()
        -- 保留真实跨队编队的原子交换回调。
        seedStats()
        local oldThird = statsSnapshot()[3]
        local oldFormationCount, oldTeamCommits = formationEvents, teamCommits
        CP.setActiveTeam(2)
        local Draw = nativeRequire("ui.character.panel.CharacterPanelDraw2")
        local Detail = nativeRequire("ui.character.detail.CharacterDetail")
        replace(Detail, "isOpen", function() return false end)
        local hitAvatar = Draw.hitTestAvatarSlot
        replace(Draw, "hitTestAvatarSlot", function(x, y)
            if x == 101 and y == 101 then return 1, 1 end
            if x == 202 and y == 202 then return 2, 1 end
            return hitAvatar(x, y)
        end)
        check(CP.handleDragBegin(101, 101) and CP.handleDragMove(202, 202)
            and CP.handleInput(202, 202), "real avatar drag reaches atomic swap input")
        CP.handleDragEnd(202, 202)
        check(formationEvents == oldFormationCount + 1 and teamCommits == oldTeamCommits + 1,
            "real cross-team swap still emits one formation callback/atomic commit")
        check(heroes.teams[1].slots[1] == 2 and heroes.teams[2].slots[1] == 1,
            "real cross-team swap retains both heroes")
        for team = 1, 2 do
            Stats.mount(team)
            check(not Stats.hasData(true), "real formation swap resets only changed cumulative team " .. team)
        end
        check(same(statsSnapshot()[3], oldThird), "real formation swap preserves unrelated cumulative team3")
        check(pushes > 0, "real rules produced heroes/currency module pushes")
        Page.close()
    end)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then failures = failures + 1; log:Write(LOG_ERROR, "[team_progress_refresh] " .. tostring(err)) end
    print(string.format("[team_progress_refresh] %s checks=%d failures=%d", failures == 0 and "ALL PASS" or "FAILED", checks, failures))
    if failures > 0 then log:Write(LOG_ERROR, "[team_progress_refresh] regression failed") end
    engine:Exit()
end
