-- T08：真实转职回执 → ChurchResults → CharacterProgress → Boot。
-- 完整保留 source team_progress_refresh_test 的断言，适配主线模块/API/字段。
-- 真实面板、转职规则、三队驱动、精准失效与统计；仅外围展示/持久化替身。
local checks, failures, harnessErrors = 0, 0, 0
local function check(value, label)
    checks = checks + 1
    if not value then failures = failures + 1 end
    print("[team_parity_growth] " .. (value and "PASS " or "FAIL ") .. label)
end

function Start()
    local nativeRequire = require
    local restores = {}
    local function replace(owner, key, value)
        local old = owner[key]
        restores[#restores + 1] = function() owner[key] = old end
        owner[key] = value
    end
    local function sourceModule(path, resolver, globals)
        local file = assert(cache:GetFile(path), "missing source " .. path)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local env = setmetatable(globals or {}, { __index = _G })
        env.require = resolver
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
        -- 所有持久化必须走下方独立 MemorySave；意外真实 File 访问立即失败。
        replace(_G, "File", function() error("成长集成测试禁止读写真档") end)
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
        -- 三行 start 的保存/故事副作用不写入开发者存档，不删除其实际战斗逻辑。
        replace(nativeRequire("boot.StandaloneSave"), "Flush", function() end)
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
            teamStageIds = { ["1"] = 101, ["2"] = 102, ["3"] = 103 }, battleMode = "idle",
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
            ["systems.LootBoxSystem"] = nativeRequire("systems.LootBoxSystem"),
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
        local function runReceipt(heroId, target, reset, closed, receiptOnly)
            local label = (closed and "closed " or "open ") .. (reset and "reset " or "advance ")
                .. "hero=" .. heroId .. " team=" .. tostring(target)
                .. (receiptOnly and " receipt-before-push" or "")
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
            ---@type table
            local result
            if receiptOnly then
                -- 模拟合法成功回执先到，heroes 推送稍后到；不调用会先推送的真实 handler。
                result = { success = true, heroId = heroId, branchId = not reset and firstBranch(heroId) or nil,
                    advLevel = not reset and 1 or nil }
            else
                result = handlers[action](1, { heroId = heroId, branchId = firstBranch(heroId), advLevel = 1 })
            end
            result.action = action
            check(result.success, label .. (receiptOnly and " successful direct receipt" or " real handler/service success"))
            receipts.onActionResult(result)
            if receiptOnly then
                local afterInvalid, afterRefresh = #invalidations, sceneRefreshes
                -- 面板第一转与镜像可能别名共享；冻结门禁必须识别第一次写入并去重迟到推送。
                local branch = CP.getOwnedHero(heroId).advBranch
                heroes.roster[heroId].advBranch = branch and { first = branch.first, second = branch.second } or nil
                Dispatcher.set("heroes", heroes)
                check(#invalidations == afterInvalid and sceneRefreshes == afterRefresh,
                    label .. " delayed identical push does not refresh twice")
            end
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
        -- 独立回执无先行 heroes 推送时，三个 wrapper 的成功返回才驱动冻结刷新。
        for _, closed in ipairs({ false, true }) do
            for index, heroId in ipairs({ 1, 2, 3, 25 }) do
                local target = index <= 3 and index or nil
                CP.setActiveTeam(index % 3 + 1)
                runReceipt(heroId, target, false, closed, true)
                runReceipt(heroId, target, true, closed, true)
            end
        end
        -- 失败/未知英雄回执不得修改任何队伍。
        local oldInvalid, oldFormation = #invalidations, formationEvents
        receipts.onActionResult({ action = Protocol.ACTION_TYPES.ADVANCE_CLASS, success = false, heroId = 1 })
        receipts.onActionResult({ action = Protocol.ACTION_TYPES.RESET_CLASS, success = false, heroId = 2 })
        CP.setHeroAdvBranch(999, 101, 1)
        CP.resetHeroAdvBranch(999)
        check(#invalidations == oldInvalid and formationEvents == oldFormation, "failed and unknown-hero receipts do not refresh teams")
        -- 轻刷新必须真实构建本队 pending；不能只保留签名但什么都没更新。
        local scopeModules = {
            nativeRequire("ui.battle.combat.BattleCombat"), nativeRequire("ui.battle.combat.ProjectileSystem"),
            nativeRequire("ui.battle.combat.BattleEffects"), nativeRequire("systems.ThreatManager"),
            nativeRequire("systems.TalentManager"), nativeRequire("systems.ExtraTalentSystem"),
            nativeRequire("systems.StatusEffectManager"), nativeRequire("systems.RelicConditionHandler"),
        }
        local Talents = nativeRequire("systems.TalentManager")
        local function mountedSnapshot()
            local result = { statsTeam = Stats.mountedTeam(), talentUnits = Talents.mountedUnitStates() }
            for i, module in ipairs(scopeModules) do result[i] = module.mountedState() end
            return result
        end
        local function sameMounted(before)
            if Stats.mountedTeam() ~= before.statsTeam or Talents.mountedUnitStates() ~= before.talentUnits then return false end
            for i, module in ipairs(scopeModules) do if module.mountedState() ~= before[i] then return false end end
            return true
        end
        local function prepareGrowthState()
            local result = {}
            for team, drv in ipairs(drivers) do
                drv.combatState.comboQueue = { { timer = 0.7 } }
                drv.psState.projectiles = { { onHit = noop } }
                drv.kills, drv.marchTimer, drv._sigTick = 7, 0, 0
                drv.teamSignature = CP.getTeamSignature(team)
                local units = {}
                for i, unit in ipairs(drv.allies) do
                    unit.atkProgress, unit.reviveTimer = 0.4, 0.3
                    units[i] = { unit = unit, attrs = unit.attrs, hp = unit.hp, base = unit._baseSnapshot,
                        pending = unit._pendingSnapshot, atkProgress = unit.atkProgress, reviveTimer = unit.reviveTimer,
                        fallen = unit._fallen, fallenPending = unit._fallenPending,
                        partySlot = unit.partySlot, artifactTeam = unit.artifactTeamIdx, slotOrder = unit._slotOrder }
                end
                result[team] = { driver = driverSnapshot(drv), units = units,
                    context = drv.combatState.ctx, startCount = starts[team] }
            end
            drivers[3].mount()
            return result, mountedSnapshot()
        end
        local function verifyGrowthState(before, changedTeam, label)
            for team, drv in ipairs(drivers) do
                local prior = before[team]
                check(unchanged(drv, prior.driver) and drv.teamSignature == prior.driver.signature
                    and drv.combatState.ctx == prior.context and starts[team] == prior.startCount,
                    label .. " keeps real driver state/context/signature team " .. team)
                for i, old in ipairs(prior.units) do
                    local unit = drv.allies[i]
                    check(unit == old.unit and unit.attrs == old.attrs and unit.hp == old.hp
                        and unit._baseSnapshot == old.base and unit.reviveTimer == old.reviveTimer
                        and unit.atkProgress == old.atkProgress and unit._fallen == old.fallen
                        and unit._fallenPending == old.fallenPending and unit.partySlot == old.partySlot
                        and unit.artifactTeamIdx == old.artifactTeam and unit._slotOrder == old.slotOrder,
                        label .. " keeps hp/death/live/base/real slot team " .. team)
                    if team == changedTeam then
                        local own = CP.getOwnedHero(unit.heroId)
                        local expected = HC.createHero(unit.heroId, CP.getEffectiveLevel(unit.heroId),
                            own.advBranch, own.awakening, own.extraTalent)
                        local armor = CP.applyEquippedItems(expected.attrs, unit.heroId, unit.partySlot)
                        if armor then expected.armorType = armor end
                        local artifacts = nativeRequire("systems.ArtifactBridge").applyToUnit(expected.attrs,
                            unit.partySlot, nil, unit.artifactTeamIdx) or {}
                        check(unit._pendingSnapshot and unit._pendingSnapshot ~= old.pending
                            and same(unit._pendingSnapshot.final, expected.attrs.final)
                            and unit._pendingArmorType == expected.armorType
                            and unit._pendingLevel == CP.getEffectiveLevel(unit.heroId)
                            and same(unit._pendingArtifactEffects, artifacts),
                            label .. " real Lifecycle pending matches owned/equipment/own-team artifact pipeline " .. team)
                    else
                        check(unit._pendingSnapshot == old.pending, label .. " unrelated pending untouched team " .. team)
                    end
                end
            end
        end
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
                    local target = index <= 3 and index or nil
                    -- 觉醒推送时令真实驱动单位阵亡；其他属性验证受伤存活者也不回血。
                    if target then
                        local unit = drivers[target].allies[1]
                        unit.hp = field == "awakening" and 0 or math.max(1, unit.maxHp - 2)
                        unit.attrs.final[AD.HP] = unit.hp
                        unit._fallen = unit.hp == 0 and true or nil
                    end
                    local beforeDrivers, beforeMounted = prepareGrowthState()
                    local beforeStats = statsSnapshot()
                    local beforeRefresh, beforeInvalid = sceneRefreshes, #invalidations
                    local hero = heroes.roster[id]
                    if field == "level" then hero.level = hero.level + 1
                    elseif field == "awakening" then hero.awakening[open and 2 or 1] = true
                    else hero.extraTalent.stacks = hero.extraTalent.stacks + 1 end
                    Dispatcher.set("heroes", heroes)
                    check(sameMounted(beforeMounted), "attribute push restores every caller mount including TAL units/ETS/stats")
                    verifyGrowthState(beforeDrivers, target, "原地" .. field .. "推送 hero=" .. id)
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
        -- 追加技独立本地 patch 同样走真实 pending，重复值/迟到镜像不重复刷新。
        do
            Page.open()
            seedStats()
            local beforeDrivers, beforeMounted = prepareGrowthState()
            local beforeRefresh, beforeInvalid = sceneRefreshes, #invalidations
            local beforeStats = statsSnapshot()
            local oldExtra = CP.getOwnedHero(2).extraTalent
            CP.patchExtraTalent(2, { stacks = oldExtra.stacks + 1 })
            verifyGrowthState(beforeDrivers, 2, "独立追加技回执")
            check(sceneRefreshes == beforeRefresh and #invalidations == beforeInvalid
                and sameMounted(beforeMounted) and same(beforeStats, statsSnapshot()),
                "extra-talent patch retains default Scene/signatures/stats/caller mounts")
            local pending = drivers[2].allies[1]._pendingSnapshot
            CP.patchExtraTalent(2, CP.getOwnedHero(2).extraTalent)
            Dispatcher.set("heroes", heroes)
            check(drivers[2].allies[1]._pendingSnapshot == pending and #invalidations == beforeInvalid,
                "identical extra-talent patch and delayed push keep the original pending snapshot")
        end
        Page.close()
        -- 普通刷新抛错仍恢复调用者挂载，不能吞错或借异常重开/清统计。
        do
            drivers[3].mount()
            local beforeMounted, beforeStats = mountedSnapshot(), statsSnapshot()
            local beforeInvalid = #invalidations
            local create = HC.createHero
            HC.createHero = function() error("成长刷新异常夹具") end
            local refreshed, refreshError = pcall(Page.refreshHeroProgressTeams, { 2 })
            HC.createHero = create
            check(not refreshed and tostring(refreshError):find("成长刷新异常夹具", 1, true)
                and sameMounted(beforeMounted) and same(beforeStats, statsSnapshot())
                and #invalidations == beforeInvalid,
                "ordinary pending refresh propagates error and restores all caller mounts/stats without invalidation")
            check(Page.refreshHeroProgressTeams({ 0, 4, 1.5, "bad" }) == false
                and sameMounted(beforeMounted) and #invalidations == beforeInvalid,
                "invalid growth teams neither borrow mounts nor refresh formation")
        end
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

        -- 扩展：冻结门禁/消息桥双订阅、槽位空洞、无效输入与默认 Scene 生命周期。
        heroes.deployed = { 1, 0, 0, 0 }
        heroes.teams[1].slots = heroes.deployed
        heroes.teams[2].slots = { 0, 2, 0, 0 }
        heroes.teams[3].slots = { 0, 0, 3, 0 }
        local changedLayouts = CP.setHeroesData(heroes)
        check(changedLayouts and changedLayouts[1] and changedLayouts[2] and changedLayouts[3],
            "mainline HeroSync returns actual changed layout map")
        check(next(CP.setHeroesData(heroes)) == nil, "unchanged HeroSync returns empty changed map")
        for _, drv in ipairs(drivers) do for _ = 1, 15 do drv:update(0) end end
        check(drivers[2].allies[1].partySlot == 2 and drivers[3].allies[1].partySlot == 3,
            "real layout rebuild retains holes before ordinary pending refresh")
        Scene.setAllies(CP.getDeployedTeam(1))
        local messageMocks = {
            ["ui.character.panel.CharacterPanel"] = CP,
            ["ui.battle.scene.BattleScene"] = Scene,
            ["ui.battle.tri.BattleTriPage"] = Page,
            ["ui.hud.TopBar"] = stub(),
            ["runtime.ClientDispatcher"] = Dispatcher,
        }
        local Message = sourceModule("runtime/ClientMessageHandler.lua", function(name)
            return messageMocks[name] or stub()
        end)
        Message.setup({ sendAction = noop, ui = {} })
        local messageGateErrors = 0
        replace(Dispatcher, "setOnAnyUpdate", Dispatcher.setOnAnyUpdate)
        Dispatcher.setOnAnyUpdate(function(mods)
            if mods.heroes then
                local routed, routeError = pcall(Message.onHeroesDataUpdate, mods.heroes, "heroes")
                if not routed then messageGateErrors = messageGateErrors + 1; print(tostring(routeError)) end
            end
        end)
        Message.setLastDeployedSnapshot(Message.deployedToString(heroes.deployed))
        for _, open in ipairs({ false, true }) do
            if open then Page.open() else Page.close() end
            for _, id in ipairs({ 1, 2, 3, 25 }) do
                local beforeRefresh = sceneRefreshes
                heroes.roster[id].level = heroes.roster[id].level + 1
                Dispatcher.set("heroes", heroes)
                check(sceneRefreshes == beforeRefresh + ((not open and id == 1) and 1 or 0),
                    "subscriber + real Message gate scope hero=" .. id .. " open=" .. tostring(open))
                local valueDiff = CP.getLastHeroesRefreshTeams()
                check((id == 25 and next(valueDiff) == nil) or (id ~= 25 and valueDiff[id] == true),
                    "frozen changed-team map matches actual hero deployment " .. id)
                valueDiff[1] = nil
                check(id ~= 1 or CP.getLastHeroesRefreshTeams()[1] == true,
                    "changed-team getter cannot mutate internal frozen gate")
                local afterRefresh = sceneRefreshes
                CP.refreshDefaultSceneForHeroes()
                check(sceneRefreshes == afterRefresh, "same push refresh cannot run twice")
            end
        end
        Page.close()
        for _, field in ipairs({ "exp", "shards", "dupeCount" }) do
            local beforeRefresh, beforeInvalid = sceneRefreshes, #invalidations
            heroes.roster[1][field] = (heroes.roster[1][field] or 0) + 1
            Dispatcher.set("heroes", heroes)
            check(sceneRefreshes == beforeRefresh and #invalidations == beforeInvalid,
                "non-effective " .. field .. " push does not refresh or invalidate")
        end
        local beforeRefresh = sceneRefreshes
        heroes.roster[1].awakening[1] = nil
        Dispatcher.set("heroes", heroes)
        check(sceneRefreshes == beforeRefresh + 1, "in-place awakening deletion detected")
        local beforeInvalid = #invalidations
        local invalidBefore = CP.getOwnedHero(1).advBranch
        CP.setHeroAdvBranch(1, firstBranch(1), 0)
        check(#invalidations == beforeInvalid and CP.getOwnedHero(1).advBranch == invalidBefore,
            "invalid advancement level does not create branch or invalidate")
        check(messageGateErrors == 0, "real Message heroes route produced no swallowed harness error")
        Dispatcher.setOnAnyUpdate(nil)

        -- 本地升级也只刷新有效属性；原始经验未升级不刷新，旁队不重开默认 Scene。
        for _, open in ipairs({ false, true }) do
            if open then Page.open() else Page.close() end
            for _, id in ipairs({ 1, 2, 3, 25 }) do
                local beforeRefresh, beforeInvalid = sceneRefreshes, #invalidations
                local beforeDrivers, beforeMounted = prepareGrowthState()
                local own = CP.getOwnedHero(id)
                local oldLevel = own.level
                CP.addHeroExp(id, nativeRequire("config.ExpTable").getHeroExpForLevel(oldLevel))
                check(sameMounted(beforeMounted), "local experience restores all caller mounts")
                verifyGrowthState(beforeDrivers, id ~= 25 and id or nil, "本地升级 hero=" .. id)
                check(CP.getOwnedHero(id).level > oldLevel, "real local exp increases hero level " .. id)
                check(sceneRefreshes == beforeRefresh + ((not open and id == 1) and 1 or 0),
                    "local level-up default scope hero=" .. id .. " open=" .. tostring(open))
                check(#invalidations == beforeInvalid, "local level-up does not restart formation")
            end
        end
        Page.close()
        local beforeNoLevelRefresh = sceneRefreshes
        CP.addHeroExp(1, 1)
        check(sceneRefreshes == beforeNoLevelRefresh, "exp below level threshold does not refresh")
        CP.setActiveTeam(1)
        local syncedLevel = CP.getOwnedHero(2).level + 1
        CP.getOwnedHero(2).level = syncedLevel
        local beforeSlotRefresh, beforeSlotInvalid = sceneRefreshes, #invalidations
        local beforeSlotDrivers, beforeSlotMounted = prepareGrowthState()
        check(CP.syncSlotLevel(2, syncedLevel) == true, "syncSlotLevel returns successful receipt to refresh wrapper")
        verifyGrowthState(beforeSlotDrivers, 2, "旁队槽位等级回执")
        check(sameMounted(beforeSlotMounted), "slot-level receipt restores all caller mounts")
        CP.setActiveTeam(2)
        local actualSlots = CP.getTeamSlotsData()
        check(actualSlots[2].heroId == 2 and actualSlots[2].level == syncedLevel,
            "syncSlotLevel updates true team/slot while editing another team")
        check(sceneRefreshes == beforeSlotRefresh and #invalidations == beforeSlotInvalid,
            "team2 slot level callback never refreshes default Scene or resets formation")

        local wipeStage = 0
        replace(bootRequire("systems.StoryPlayer"), "onWipe", function(stageId) wipeStage = stageId end)
        drivers[2].onAllDead(2, 102)
        check(wipeStage == 102, "Boot routes tri failure stage rather than team number to Story")

        -- 无 GPU 生命周期验证：死亡者仍收到 pending，nil class/branch/node 重置必须写回。
        local Lifecycle = nativeRequire("ui.battle.scene.BattleAllyLifecycle")
        local Reset = nativeRequire("ui.battle.scene.BattleAllyReset")
        local artifact = nativeRequire("systems.ArtifactBridge")
        local fallen = HC.createHero(3, CP.getEffectiveLevel(3))
        fallen.hp = 0
        fallen.attrs.final[AD.HP] = 0
        fallen.partySlot, fallen.artifactTeamIdx, fallen._slotOrder = 3, 3, 1
        fallen.classId, fallen.classBranchId = "staleClass", 999
        fallen.advBranch, fallen.awakeningNodes, fallen.advTalentIds = { first = 999 }, { [99] = true }, { 999 }
        fallen.artifactEffects = { { kind = "stale" } }
        fallen.reviveTimer, fallen.atkProgress = 0.3, 0.7
        Reset.createSnapshot(fallen)
        local oldAttrs, oldBase, setterCalls, incomeCalls, levelFx = fallen.attrs, fallen._baseSnapshot, 0, 0, 0
        local equipmentSlot, artifactSlot, artifactTeam
        local newUnit
        local createHero = HC.createHero
        replace(HC, "createHero", function(id, level, branch, awaken, extra)
            newUnit = createHero(id, level, branch, awaken, extra)
            newUnit.classId, newUnit.classBranchId = nil, nil
            newUnit.advBranch, newUnit.awakeningNodes, newUnit.advTalentIds = nil, nil, nil
            return newUnit
        end)
        replace(CP, "applyEquippedItems", function(_, _, slot) equipmentSlot = slot; return 2 end)
        replace(artifact, "applyToUnit", function(_, slot, _, team) artifactSlot, artifactTeam = slot, team; return {} end)
        replace(nativeRequire("ui.fx.SpineCardEffect"), "playLevelUp", function() levelFx = levelFx + 1 end)
        local life = Lifecycle.bind({
            getAllies = function() return { fallen } end,
            getEnemies = function() return {} end,
            getEnemyQueue = function() return {} end,
            recalcIdleIncome = function() incomeCalls = incomeCalls + 1 end,
            get = function() return nil end,
            set = function() setterCalls = setterCalls + 1 end,
            ALLY_CARD_CY = 1760,
        })
        life.refreshAllyStats()
        check(fallen.hp == 0 and fallen.attrs == oldAttrs and fallen._baseSnapshot == oldBase,
            "dead hero receives pending without hp/live attrs/base mutation")
        check(fallen._pendingSnapshot == newUnit.attrs and fallen._pendingArmorType == 2,
            "dead hero pending snapshot includes rebuilt real attrs and armor")
        check(fallen.classId == nil and fallen.classBranchId == nil and fallen.advBranch == nil
            and fallen.awakeningNodes == nil and fallen.advTalentIds == nil,
            "nil class/branch/awakening/talent reset clears every stale field")
        check(equipmentSlot == 3 and artifactSlot == 3 and artifactTeam == 3,
            "dead compacted hero refresh uses real team/slot not display order")
        check(fallen.reviveTimer == 0.3 and fallen.atkProgress == 0.7 and setterCalls == 0 and levelFx == 0,
            "refresh preserves death timer/progress/context and never plays dead level FX")
        check(incomeCalls == 1 and #fallen._pendingArtifactEffects == 0,
            "pending artifact removal and income recalc retained")
        local beforeStatLevel = CP.getOwnedHero(3).level
        CP.getOwnedHero(3).level = beforeStatLevel - 1
        life.refreshAllyStats()
        check(fallen._pendingLevel == beforeStatLevel - 1 and fallen.hp == 0,
            "level decrease replaces prior pending level without reviving")
        Reset.restoreFromSnapshot(fallen)
        check(fallen.level == beforeStatLevel - 1 and fallen.artifactEffects == nil,
            "next-wave commit applies lowered pending level and removes stale artifact effects")
        local entryResets, wipeResets = 0, 0
        replace(nativeRequire("ui.battle.stage.StageEntryEvents"), "reset", function() entryResets = entryResets + 1 end)
        replace(nativeRequire("systems.StoryPlayer"), "resetWipe", function() wipeResets = wipeResets + 1 end)
        life.resetToDefault()
        check(entryResets == 1 and wipeResets == 1, "Scene reset clears stage-entry and wipe-session dedupe")

        -- 清档必须丢弃Boot暂存掉落，不借正常失败出口发放旧奖励。
        local killDrop, failBattle, popupShows, delivered, scrollBalance = noop, noop, 0, 0, 0
        local rewardScene = stub({
            setOnEnemyDrop = function(callback) killDrop = callback end,
            setOnAllDead = function(callback) failBattle = callback end,
            getCurrentStageId = function() return 101 end,
        })
        local resetMocks = {
            ["ui.character.panel.CharacterPanel"] = stub(),
            ["ui.battle.scene.BattleScene"] = rewardScene,
            ["runtime.ClientDispatcher"] = Dispatcher,
            ["config.StageConfig"] = stub({ getStage = function() return { monsterLevel = 1 } end }),
            ["systems.DropSystem"] = stub({ rollKillDrop = function() return 1 end,
                rollScrollDrop = function() return "weaponScroll" end }),
            ["systems.EquipmentSystem"] = stub({ generateRandom = function() return { level = 1, quality = 1 } end }),
            ["systems.LootBoxSystem"] = stub({ getTotalCount = function() return 0 end,
                deliverEquipment = function() delivered = delivered + 1; return "bag" end }),
            ["core.GameState"] = stub({ getWeaponScroll = function() return scrollBalance end,
                setWeaponScroll = function(value) scrollBalance = value end }),
            ["ui.hud.popup.RewardPopup"] = stub({ show = function() popupShows = popupShows + 1 end }),
        }
        local ResetBoot = sourceModule("boot/StandaloneBoot.lua", function(name)
            resetMocks[name] = resetMocks[name] or stub()
            return resetMocks[name]
        end)
        ResetBoot.run({ localSendAction = noop })
        killDrop({ stageId = 101, isFirstClear = true })
        ResetBoot.resetPendingBattleRewards()
        failBattle()
        check(popupShows == 0 and delivered == 0 and scrollBalance == 0,
            "formal reset discards old pending seeds/scrolls without granting rewards")
        killDrop({ stageId = 101, isFirstClear = true })
        failBattle()
        check(popupShows == 1 and delivered == 1 and scrollBalance == 1,
            "normal defeat still grants kept drop through existing reward exit")

        -- 在线真实 Boot 回调 → CP 升级/共鸣 → 共享 roster → 真实推送 → Save。
        -- 独立 PDM/Save 实例隔离上下文；File/Rename 仅在 Save 的环境中使用内存。
        Page.close()
        replace(HC, "createHero", createHero) -- 结束 nil 字段生命周期夹具，在线链使用真实英雄构造。
        local ET = nativeRequire("config.ExpTable")
        local GS = nativeRequire("core.GameState")
        local savedState = GS.exportSave()
        restores[#restores + 1] = function() GS.importSave(savedState) end
        replace(_G, "IsNetworkMode", function() return false end)
        local fixturePDM = sourceModule("rules/character/PlayerDataManager.lua", nativeRequire)
        fixturePDM.Setup({ serverDispatcher = { pushModule = function(_, name, data)
            Dispatcher.set(name, data)
        end } })
        fixturePDM.AttachLocalModules(1, modules)
        local onlineHeroes = { roster = {}, deployed = { 1, 0, 0, 0 }, teams = {
            { slots = { 1, 0, 0, 0 } }, { slots = { 0, 5, 0, 0 } }, { slots = { 0, 0, 25, 0 } },
        }, urShardConvertDayId = 123, urShardConvertCount = 2 }
        for _, id in ipairs({ 1, 2, 3, 4, 5, 6, 25 }) do
            onlineHeroes.roster[id] = { level = id <= 4 and 2 or 1, exp = 0, shards = 7,
                dupeCount = 3, _shardMigrated = true, _awk3Migrated = true,
                awakening = { _awk3Migrated = true }, advBranch = { first = firstBranch(id) },
                extraTalent = { stacks = 4 }, customSaveField = { tag = "hero" .. id, retained = true } }
        end
        replace(modules, "heroes", onlineHeroes)
        replace(modules, "battle", { currentStageId = 101, maxStageId = 2001,
            teamStageIds = { ["1"] = 101, ["2"] = 102, ["3"] = 103 },
            clearedStages = { ["905"] = true, ["1905"] = true }, battleMode = "idle" })
        replace(modules, "player", { name = "online-save", level = 1, exp = 0 })
        replace(modules, "session", { lastOnlineTime = 0, firstLoginTime = 0 })
        GS.syncPlayerData({ name = "online-save", level = 1, exp = 0 }, { silent = true })
        Dispatcher.set("heroes", onlineHeroes)
        -- 面板未收到另一个业务已经提交的经验；此次不变英雄不能被整表反写。
        onlineHeroes.roster[4].exp = 9
        local function copy(value)
            if type(value) ~= "table" then return value end
            local out = {}
            for key, item in pairs(value) do out[key] = copy(item) end
            return out
        end
        local otherFields = copy(onlineHeroes)
        local onlineKill, triKill = noop, noop
        local onlineMocks = {
            ["ui.character.panel.CharacterPanel"] = CP,
            ["runtime.ClientDispatcher"] = Dispatcher,
            ["core.GameState"] = GS,
            ["config.ExpTable"] = ET,
            ["config.StageConfig"] = nativeRequire("config.StageConfig"),
            ["systems.LootBoxSystem"] = nativeRequire("systems.LootBoxSystem"),
            ["ui.battle.scene.BattleScene"] = stub({
                setOnEnemyKill = function(callback) onlineKill = callback end,
                getStageId = function() return 101 end,
                getMaxStageId = function() return 2001 end,
                getClearedStages = function() return modules.battle.clearedStages end,
            }),
            ["ui.battle.tri.BattleTriPage"] = stub({ isOpen = function() return false end,
                setOnKill = function(callback) triKill = callback end }),
        }
        local OnlineBoot = sourceModule("boot/StandaloneBoot.lua", function(name)
            onlineMocks[name] = onlineMocks[name] or stub()
            return onlineMocks[name]
        end)
        OnlineBoot.run({ localSendAction = noop })
        check(onlineKill == triKill, "Scene and all tri teams share the real Boot experience callback")
        local memory = {}
        local function allowed(path)
            assert(path == "standalone_save.json" or path == "standalone_save.pending.json",
                "online-save fixture rejects unexpected path " .. tostring(path))
        end
        local MemorySave = sourceModule("boot/StandaloneSave.lua", function(name)
            if name == "ui.battle.scene.BattleScene" then return onlineMocks[name] end
            if name == "rules.offline.OfflineService" then
                return { HasPendingRewards = function() return false end, MarkOnline = noop }
            end
            return nativeRequire(name)
        end, {
            File = function(path)
                allowed(path)
                return { IsOpen = function() return true end,
                    WriteString = function(_, text) memory[path] = text; return true end,
                    ReadString = function() return memory[path] end, Close = noop }
            end,
            fileSystem = {
                FileExists = function(_, path) allowed(path); return memory[path] ~= nil end,
                Delete = function(_, path) allowed(path); memory[path] = nil; return true end,
                Rename = function(_, from, to)
                    allowed(from); allowed(to)
                    memory[to], memory[from] = memory[from], nil
                    return true
                end,
            },
        })
        local heroPushes = 0
        local countPush = function() heroPushes = heroPushes + 1 end
        Dispatcher.subscribe("heroes", countPush)
        local function preserved(data, label)
            check(data.urShardConvertDayId == 123 and data.urShardConvertCount == 2,
                label .. " preserves module counters")
            for id, prior in pairs(otherFields.roster) do
                local hero = data.roster[id]
                for _, field in ipairs({ "shards", "dupeCount", "_shardMigrated", "_awk3Migrated",
                    "awakening", "advBranch", "extraTalent", "customSaveField" }) do
                    check(hero and same(hero[field], prior[field]), label .. " preserves " .. field .. " hero=" .. id)
                end
            end
        end
        local formationBefore, commitsBefore, invalidBefore = formationEvents, teamCommits, #invalidations
        local setsBefore, reloadBefore, refreshBefore = sceneSets, sceneReloads, sceneRefreshes
        seedStats()
        local statsBeforeOnline = statsSnapshot()
        onlineKill({ expReward = 1, goldReward = 0, heroIds = { 1 }, allyCount = 1 })
        check(CP.getOwnedHero(1).level == 2 and CP.getOwnedHero(1).exp == 1
            and onlineHeroes.roster[1].exp == 1, "below-threshold Boot experience persists without level-up")
        triKill({ expReward = ET.getHeroExpForLevel(1), goldReward = 0, heroIds = { 5 }, allyCount = 1 })
        check(CP.getOwnedHero(5).level == 2 and onlineHeroes.roster[5].level == 2,
            "team2 real Boot level-up updates persistent roster")
        check(CP.getOwnedHero(25).level == 2 and onlineHeroes.roster[25].level == 2
            and onlineHeroes.roster[25].exp == 0,
            "same grant persists resonance floor on the other team")
        check(CP.getOwnedHero(6).level == 2 and onlineHeroes.roster[6].level == 2
            and onlineHeroes.roster[6].exp == 0 and onlineHeroes.roster[6].maxExp == ET.getHeroExpForLevel(2)
            and not CP.getHeroDeployPosition(6),
            "same grant persists resonance on an undeployed hero")
        check(CP.getOwnedHero(1).exp == 1 and onlineHeroes.roster[1].exp == 1,
            "resonance does not overwrite unchanged hero experience")
        check(CP.getOwnedHero(4).exp == 0 and onlineHeroes.roster[4].exp == 9,
            "changed-only write preserves a newer persistent field absent from the panel")
        check(GS.getLevel() == 1 and GS.getExp() == 1 + ET.getHeroExpForLevel(1),
            "real Boot gives shared account base experience once without hidden level-up")
        check(fixturePDM.GetModule(1, "heroes") == Dispatcher.get("heroes")
            and fixturePDM.GetModule(1, "heroes").roster == onlineHeroes.roster,
            "real PDM and Dispatcher share one persistent roster")
        check(heroPushes == 0 and formationEvents == formationBefore and teamCommits == commitsBefore
            and #invalidations == invalidBefore and sceneSets == setsBefore and sceneReloads == reloadBefore
            and sceneRefreshes == refreshBefore and same(statsBeforeOnline, statsSnapshot()),
            "experience persistence fabricates no push/formation/reload or all-team invalidation and retains stats")
        preserved(onlineHeroes, "online grant")
        check(MemorySave.Flush(), "real Save Flush captures online experience using memory File")
        local diskData = cjson.decode(memory["standalone_save.json"])
        check(diskData.modules.heroes.roster.h1.exp == 1 and diskData.modules.heroes.roster.h5.level == 2
            and diskData.modules.heroes.roster.h25.level == 2 and diskData.modules.heroes.roster.h6.level == 2
            and diskData.modules.heroes.roster.h4.exp == 9,
            "immediate disk snapshot contains grant, resonance and untouched newer field before a hero push")
        fixturePDM.MarkDirty(1, "heroes")
        check(heroPushes == 1 and CP.getOwnedHero(1).exp == 1 and CP.getOwnedHero(5).level == 2
            and CP.getOwnedHero(25).level == 2 and CP.getOwnedHero(6).level == 2 and CP.getOwnedHero(4).exp == 9,
            "real PDM hero push cannot roll back local experience")
        preserved(Dispatcher.get("heroes"), "hero push")
        check(MemorySave.RestoreData(), "real RestoreData reloads the in-memory committed snapshot")
        local restoredHeroes = Dispatcher.get("heroes")
        check(fixturePDM.GetModule(1, "heroes") == restoredHeroes and CP.getOwnedHero(1).exp == 1
            and CP.getOwnedHero(5).level == 2 and CP.getOwnedHero(25).level == 2
            and CP.getOwnedHero(6).level == 2 and CP.getOwnedHero(4).exp == 9,
            "Flush/Restore retains growth across CP/Dispatcher/PDM")
        preserved(restoredHeroes, "restore")
        check(same(restoredHeroes.teams, otherFields.teams) and same(restoredHeroes.deployed, otherFields.deployed)
            and formationEvents == formationBefore and teamCommits == commitsBefore and #invalidations == invalidBefore,
            "grant, push and restore retain real formations without a synthetic transaction")
        for _, id in ipairs({ 1, 2, 3, 4, 5, 6, 25 }) do
            local hero, own = restoredHeroes.roster[id], CP.getOwnedHero(id)
            check(hero.level == own.level and (hero.exp or 0) == own.exp,
                "CP and unique persistent roster experience agree after restore hero=" .. id)
            if id ~= 5 and id ~= 6 and id ~= 25 then
                check(hero.level == otherFields.roster[id].level,
                    "unchanged hero level never copied from a different owner " .. id)
            else
                check(hero.maxExp == ET.getHeroExpForLevel(2), "resonance maxExp survives restore hero=" .. id)
            end
        end
        local validBefore = copy(restoredHeroes)
        for _, amount in ipairs({ 0, -1, math.huge, -math.huge, 0 / 0, "20" }) do CP.addHeroExp(1, amount) end
        CP.addHeroExp(1, nil)
        CP.addHeroExp(999, 20)
        check(same(Dispatcher.get("heroes"), validBefore), "invalid experience or unknown hero cannot mutate persistent roster")
        -- 一次真实 Boot 奖励连续升级，之后的推送/存档仍应保留余额。
        GS.syncPlayerData({ level = 30, exp = 0 }, { silent = true })
        triKill({ expReward = ET.getHeroExpForLevel(2) + ET.getHeroExpForLevel(3) + 7,
            goldReward = 0, heroIds = { 5 }, allyCount = 1 })
        check(CP.getOwnedHero(5).level == 4 and restoredHeroes.roster[5].level == 4
            and restoredHeroes.roster[5].exp == 7 and restoredHeroes.roster[5].maxExp == ET.getHeroExpForLevel(4),
            "one real Boot reward persists consecutive level-ups and residual experience")
        fixturePDM.MarkDirty(1, "heroes")
        check(CP.getOwnedHero(5).level == 4 and CP.getOwnedHero(5).exp == 7,
            "subsequent hero push retains multi-level reward")
        check(MemorySave.Flush() and MemorySave.RestoreData(), "multi-level reward Flush/Restore succeeds in memory")
        restoredHeroes = Dispatcher.get("heroes")
        check(CP.getOwnedHero(5).level == 4 and restoredHeroes.roster[5].level == 4
            and restoredHeroes.roster[5].exp == 7, "multi-level reward persists through Restore")
        preserved(restoredHeroes, "multi-level restore")
        local persistedBefore = copy(restoredHeroes)
        replace(_G, "IsNetworkMode", function() return true end)
        CP.addHeroExp(1, 1)
        check(same(Dispatcher.get("heroes"), persistedBefore), "network client cannot persist local hero experience")
        replace(_G, "IsNetworkMode", function() return false end)
        Dispatcher.set("heroes", restoredHeroes)
    end)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then
        harnessErrors = harnessErrors + 1
        log:Write(LOG_ERROR, "[team_parity_growth] " .. tostring(err))
    end
    print(string.format("[team_parity_growth] %s checks=%d failures=%d harnessErrors=%d",
        failures == 0 and harnessErrors == 0 and "ALL PASS" or "FAILED", checks, failures, harnessErrors))
    if failures > 0 or harnessErrors > 0 then log:Write(LOG_ERROR, "[team_parity_growth] regression failed") end
    engine:Exit()
end
