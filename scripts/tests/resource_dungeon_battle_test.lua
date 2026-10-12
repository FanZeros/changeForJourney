-- 三资源真实DungeonBattle/Scene/公共出怪与战斗模块回归，持久化/渲染出口隔离。
local TAG = "[resource_dungeon_battle_test]"
local assertions = 0
local function eq(a, b, label)
    assertions = assertions + 1
    assert(a == b, label .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end
local function copyTree(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copyTree(child) end
    return result
end
local function sameTree(actual, expected, label)
    eq(type(actual), type(expected), label .. "类型")
    if type(expected) ~= "table" then eq(actual, expected, label) return end
    for key, value in pairs(expected) do sameTree(actual[key], value, label .. "/" .. tostring(key)) end
    for key in pairs(actual) do check(expected[key] ~= nil, label .. "未追加字段 " .. tostring(key)) end
end

function Start()
    local nativeRequire, nativeFile, nativeSystem = require, File, fileSystem
    local ok, err = pcall(function()
        local function noop() end
        local env = setmetatable({}, { __index = _G })
        -- 真实模块遗漏保存替身时也只写内存，不触碰cwd或玩家文件。
        local disk = {}
        env.File = function(path, mode)
            return { IsOpen = function() return true end,
                WriteString = function(_, value) disk[path] = value; return true end,
                ReadString = function() return disk[path] end, Close = noop, Dispose = noop }
        end
        env.fileSystem = {
            FileExists = function(_, path) return disk[path] ~= nil end,
            Delete = function(_, path) disk[path] = nil; return true end,
            Rename = function(_, from, to)
                if disk[from] == nil then return false end
                disk[to], disk[from] = disk[from], nil; return true
            end,
        }
        rawset(_G, "File", env.File)
        rawset(_G, "fileSystem", env.fileSystem)
        local modules = { player = { level = 100 }, battle = { maxStageId = 2501 } }
        local actions, results = {}, {}
        local cancels = 0
        local mockPanel = { init = noop, update = noop, draw = noop, isOpen = function() return false end,
            show = function(opts) results[#results + 1] = opts end }
        local mocks = {
            ["core.PlayerStore"] = { Get = function(key) return modules[key] end },
            ["runtime.ClientDispatcher"] = { get = function(key) return modules[key] end },
            ["core.GameState"] = { getLevel = function() return 100 end },
            ["ui.character.panel.CharacterPanel"] = { getOwnedHero = function() return nil end },
            ["ui.battle.scene.BattleScene"] = { restoreContext = noop },
            ["ui.battle.popup.BattleResultPanel"] = mockPanel,
            ["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return false end },
            ["ui.fx.SpineCardEffect"] = { playRevive = noop },
            ["systems.ButtonFeedback"] = { trigger = noop },
            ["systems.GameSFX"] = setmetatable({}, { __index = function() return noop end }),
            ["runtime.GameAction"] = { sendAction = function(action, params)
                actions[#actions + 1] = { action = action, params = params }
            end },
            ["rules.dungeon.DungeonService"] = { Cleanup = function(uid)
                eq(uid, 1, "单机取消仅uid1") cancels = cancels + 1
            end },
        }
        local loaded = {}
        local function compile(name)
            if mocks[name] then return mocks[name] end
            if loaded[name] then return loaded[name] end
            assert(not name:match("^rules%.") and not name:match("^boot%."), "不允许加载存档/规则: " .. name)
            local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少脚本 " .. name)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            local value = assert(load(table.concat(lines, "\n"), "@" .. name, "t", env))()
            loaded[name] = value
            return value
        end
        env.require = compile
        rawset(_G, "require", compile) -- 复用StageBerserk独立实例在_G环境中require同一配置。
        local DC = compile("config.DungeonConfig")
        local SC = compile("config.StageConfig")
        local HC = compile("config.HeroConfig")
        local AD = compile("systems.AttributeDef")
        local DB = compile("ui.dungeon.DungeonBattle")
        local Scene = compile("ui.dungeon.DungeonBattleScene")
        local BC = compile("ui.battle.combat.BattleCombat")
        local PS = compile("ui.battle.combat.ProjectileSystem")
        local SEM = compile("systems.StatusEffectManager")
        local TAL = compile("systems.TalentManager")
        local ETS = compile("systems.ExtraTalentSystem")
        local Layout = compile("core.BattleLayout")
        local DamagePanel = compile("ui.battle.popup.DamageStatsPanel")
        local Threat = compile("systems.ThreatManager")
        local FX = compile("ui.battle.combat.BattleEffects")
        local Stats = compile("systems.BattleStats")
        local MAS = compile("systems.MapAffixSystem")
        local BAS = compile("systems.BossAffixSystem")
        local Spawn = compile("ui.battle.stage.BattleEnemySpawn")
        local Scope = compile("ui.dungeon.DungeonBattleScope")
        local Runtime = compile("ui.dungeon.DungeonCombatRuntime")
        local Rewards = compile("ui.dungeon.DungeonRewards")
        local Protocol = compile("shared.Protocol")
        local function upvalue(fn, wanted)
            for i = 1, 100 do
                local name, value = debug.getupvalue(fn, i)
                if not name then break end
                if name == wanted then return value end
            end
            error("缺少状态 " .. wanted)
        end
        local state = upvalue(upvalue(Scene.update, "implementation"), "state")
        local function snapshot()
            return table.pack(BC.mountedState(), PS.mountedState(), Threat.mountedState(), TAL.mountedState(),
                FX.mountedState(), SEM.mountedState(), Stats.mountedTeam())
        end
        local mainScope = snapshot()
        local sourceBerserk = compile("ui.battle.stage.StageBerserk")
        local RCH = compile("systems.RelicConditionHandler")
        local mainDummy = { heroId = 999, hp = 100, atkInterval = 1, atkCoeff = 1 }
        TAL.initUnit(mainDummy)
        local mainUnitStates = TAL.mountedUnitStates()
        local mainUnit = mainUnitStates[mainDummy]
        mainUnit.atkCount, mainUnit.advTimer = 73, 8.25
        mainUnit.selfReviveUsed, mainUnit.phoenixUsed = true, true
        mainUnit.reviveUsed[mainDummy] = true
        mainUnit.reviveHealBoostTargets[mainDummy] = 6.75
        mainUnit.shadowTimer, mainUnit.flyingSwordTimer = 4.5, 2.125
        local mainUnitBefore = copyTree(mainUnit)
        local mainExtra = ETS.mountedState()
        mainExtra.orbitAngle, mainExtra.persistAcc = 3.75, 1.49
        mainExtra.iceStatues[1] = { hp = 1, cx = 147, cy = 804, sourceId = 12 }
        mainExtra.dirty[999] = ETS.normalize({ stacks = 47, tickets = { ["2"] = true } })
        local extraFields = { "iceStatues", "dirty", "pendingPrecise", "pendingConquer", "pendingBeams",
            "pendingShadows", "pendingGatling", "pendingNitroDash" }
        local mainExtraTables = {}
        for i, field in ipairs(extraFields) do
            if field:match("^pending") then mainExtra[field][999] = 30 + i end
            mainExtraTables[field] = mainExtra[field]
        end
        local mainExtraBefore = copyTree(mainExtra)
        local refs = TAL.mountedState()
        refs.deathHookDepth = 1
        refs.pendingDeaths[1] = { unit = mainDummy, allies = {}, enemies = {} }
        refs.pendingDeathSet[mainDummy] = true
        local mainPending, mainPendingSet = refs.pendingDeaths, refs.pendingDeathSet
        Layout.setMode("strip")
        RCH.initBattle({ mainDummy })
        RCH.addImmunityCharges(mainDummy, 5)
        local mainRchUpdate = RCH.update
        sourceBerserk.enter({}, { mainDummy })
        sourceBerserk.update(12, {}, { mainDummy })
        local mainStatsBefore = Stats.getTotal("totalDamage", false)
        local function unchanged()
            local current = snapshot()
            for i = 1, mainScope.n do eq(current[i], mainScope[i], "宿主挂载还原" .. i) end
            eq(sourceBerserk.getElapsed(), 12, "暂停主线狂暴计时未覆盖")
            eq(RCH.update, mainRchUpdate, "RCH导出函数恢复")
            eq(Stats.getTotal("totalDamage", false), mainStatsBefore, "副本不清主线统计")
            eq(TAL.mountedUnitStates(), mainUnitStates, "主线单位状态原表还原")
            eq(mainUnitStates[mainDummy], mainUnit, "主线单位天赋原实例保留")
            sameTree(mainUnit, mainUnitBefore, "主线攻击/复活/计时天赋不变")
            eq(TAL.mountedState().pendingDeaths, mainPending, "主线待死亡队列原表保留")
            eq(TAL.mountedState().pendingDeathSet, mainPendingSet, "主线待死亡去重表保留")
            eq(#mainPending, 1, "主线待死亡队列不被消费")
            eq(mainPending[1].unit, mainDummy, "主线待死亡对象不变")
            eq(mainPendingSet[mainDummy], true, "主线待死亡标记不变")
            eq(refs.deathHookDepth, 1, "主线死亡钩子深度不变")
            eq(ETS.mountedState(), mainExtra, "ETS主线原作用域还原")
            for _, field in ipairs(extraFields) do
                eq(mainExtra[field], mainExtraTables[field], "ETS原容器保留 " .. field)
            end
            sameTree(mainExtra, mainExtraBefore, "ETS冰雕/待持久化/待处理不变")
            eq(Layout.MODE, "strip", "副本返回还原主线strip")
            for _, action in ipairs(actions) do
                check(not (action.action == Protocol.ACTION_TYPES.SYNC_EXTRA_TALENT
                    and action.params.heroId == 999), "副本不能flush主线dirty哨兵")
            end
        end
        local function inScene(label)
            eq(Layout.MODE, "strip", label .. "作用域strip")
            check(TAL.mountedUnitStates() ~= mainUnitStates, label .. "独立单位天赋表")
            check(ETS.mountedState() ~= mainExtra, label .. "独立ETS状态")
            local _, enemyY = Layout.cardPos("enemy", 1, 4)
            local _, allyY = Layout.cardPos("ally", 1, 4)
            eq(enemyY, Layout.STRIP_CY, label .. "敌方左右对阵坐标")
            eq(allyY, Layout.STRIP_CY, label .. "友方左右对阵坐标")
        end
        local function data(id, floor, team, token)
            return { dungeonId = id, floor = floor, teamIdx = team, challengeId = token,
                stageEntry = DC.getCombatEntry(id, floor), resourceCombat = true,
                classBonus = "spoil", classBonusValue = 9 }
        end
        local function ally()
            local unit = assert(HC.createHero(2, 100, nil, {}, {}))
            unit.atkInterval = 100000
            return unit
        end
        local function kill(unit)
            unit.hp = 0
            unit.attrs.final[AD.HP] = 0
        end
        local function receipt(challenge)
            return { action = Protocol.ACTION_TYPES.DUNGEON_WIN, success = true,
                dungeonId = challenge.dungeonId, floor = challenge.floor, teamIdx = challenge.teamIdx,
                challengeId = challenge.challengeId, nextFloor = challenge.floor + 1, diamond = 987 }
        end

        -- 观测真实Scene公共入口所调用的核心生命周期，不用外套Scope掩盖漏挂载。
        local lifecycleCalls = { init = 0, reset = 0, update = 0, draw = 0 }
        local realInitUnit, realReset, realUpdate = TAL.initUnit, BC.reset, TAL.update
        TAL.initUnit = function(...)
            inScene("Scene.initUnit")
            lifecycleCalls.init = lifecycleCalls.init + 1
            return realInitUnit(...)
        end
        BC.reset = function(...)
            inScene("Scene.reset")
            lifecycleCalls.reset = lifecycleCalls.reset + 1
            return realReset(...)
        end
        TAL.update = function(...)
            inScene("Scene.update")
            lifecycleCalls.update = lifecycleCalls.update + 1
            return realUpdate(...)
        end
        local Draw = compile("ui.battle.scene.BattleDraw")
        Draw.drawCardGroup = function(_, units, cy)
            inScene("Scene.draw")
            lifecycleCalls.draw = lifecycleCalls.draw + 1
            eq(cy, Layout.STRIP_CY, "Scene.draw左右对阵坐标")
        end
        compile("core.DarkIcon").drawDarkScene = noop
        mocks["systems.ButtonFeedback"].begin, mocks["systems.ButtonFeedback"].finish = noop, noop
        mocks["ui.hud.popup.SettingsPanel"].isDamageNumbersEnabled = function() return false end
        for _, name in ipairs({ "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor", "nvgText",
            "nvgSave", "nvgRestore", "nvgBeginPath", "nvgRoundedRect", "nvgFill", "nvgRect",
            "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke" }) do env[name] = noop end

        -- 最外层保存主线；嵌套reset替换表后，外层与下一帧都须继续使用新副本表。
        local scopedUnit = { heroId = 998, hp = 100 }
        local replacedStates = {}
        Scope.run(2, function()
            inScene("外层")
            local oldStates = TAL.mountedUnitStates()
            local extraState = ETS.mountedState()
            local nested = table.pack(Scope.run(3, function()
                inScene("内层")
                eq(Stats.mountedTeam(), 102, "嵌套沿用外层统计桶")
                TAL.reset()
                replacedStates = TAL.mountedUnitStates()
                check(replacedStates ~= oldStates, "真实TAL.reset替换副本单位表")
                TAL.initUnit(scopedUnit)
                replacedStates[scopedUnit].atkCount = 19
                return "nested", nil, 7
            end))
            eq(nested.n, 3, "Scope保留多返回值含nil")
            eq(nested[1], "nested", "Scope返回首值")
            eq(nested[3], 7, "Scope返回尾值")
            eq(TAL.mountedUnitStates(), replacedStates, "内层reset后外层保留新表")
            eq(ETS.mountedState(), extraState, "嵌套ETS沿用副本原状态")
            eq(Layout.MODE, "strip", "内层返回不提前恢复宿主")
        end)
        unchanged()
        Scope.run(2, function()
            eq(TAL.mountedUnitStates(), replacedStates, "下一次挂载保留reset后的表")
            eq(replacedStates[scopedUnit].atkCount, 19, "下一帧副本计数保留")
            local okInner, innerErr = pcall(Scope.run, 3, function()
                inScene("内层异常")
                error("expected-nested-scope-error", 0)
            end)
            eq(okInner, false, "嵌套异常透传")
            check(tostring(innerErr):find("expected-nested-scope-error", 1, true), "内层原异常保留")
            inScene("捕获内层异常后外层")
        end)
        unchanged()
        local okOuter, outerErr = pcall(Scope.run, 2, function()
            TAL.reset()
            TAL.initUnit(scopedUnit)
            TAL.mountedUnitStates()[scopedUnit].atkCount = 29
            error("expected-outer-scope-error", 0)
        end)
        eq(okOuter, false, "外层异常透传")
        check(tostring(outerErr):find("expected-outer-scope-error", 1, true), "外层原异常保留")
        unchanged()
        Scope.run(2, function()
            inScene("异常后重入")
            eq(TAL.mountedUnitStates()[scopedUnit].atkCount, 29, "异常也记录最新reset表")
        end)
        unchanged()
        Layout.setMode("classic")
        Scope.run(1, function() eq(Layout.MODE, "strip", "classic宿主进入副本仍使用strip") end)
        eq(Layout.MODE, "classic", "按原宿主MODE恢复而非写死strip")
        Layout.setMode("strip")

        local clockSteps = {}
        local realProjectileUpdate, realComboUpdate, realSemUpdate = PS.update, BC.updateComboQueue, SEM.update
        PS.update = function(dt)
            clockSteps.projectile = dt
            return realProjectileUpdate(dt)
        end
        BC.updateComboQueue = function(dt)
            clockSteps.combo = dt
            return realComboUpdate(dt)
        end
        SEM.update = function(dt, ...)
            clockSteps.status = dt
            return realSemUpdate(dt, ...)
        end
        -- 直接调用真实init，图片创建仅记录路径，不能再加载已删除的倍速图标。
        local imagePaths = {}
        env.nvgCreateImage = function(_, path) imagePaths[#imagePaths + 1] = path; return -1 end
        Scene.init(nil)
        for _, path in ipairs(imagePaths) do
            check(not path:find("UI_ICON_kong", 1, true), "副本初始化不加载旧倍速图标")
        end
        for _, id in ipairs(DC.RESOURCE_IDS) do
            local challenge = data(id, 1, 3, id .. "-1")
            local sourceSnapshot = cjson.encode(SC.getStage(challenge.stageEntry.id))
            local expected = Spawn.generateEnemyList(challenge.stageEntry, true)
            modules.battle = { maxStageId = 34505, clearedStages = { ["999"] = true, ["1999"] = true } }
            local legacyBattle = cjson.encode(modules.battle)
            Scene.open({ data = challenge, allies = { ally() } })
            state.battleSpeed = 3 -- 旧状态残留不允许再参与真实战斗。
            eq(Scene.cycleBattleSpeed(), false, "资源副本旧切速API为空操作")
            local combatAlly = state.allies[1]
            combatAlly.atkInterval, combatAlly.atkProgress = 1, 0
            Scene.update(.25)
            eq(DB.getElapsed(), .25, id .. "真实场景限时只累计真实dt")
            eq(Runtime.getBerserk().getElapsed(), .25, id .. "资源狂暴时钟只累计真实dt")
            eq(combatAlly.atkProgress, .25, id .. "攻击进度只推进四分之一秒")
            eq(clockSteps.projectile, .25, "投射物使用原dt")
            eq(clockSteps.combo, .25, "连击使用原dt")
            eq(clockSteps.status, .25, "DOT/HOT状态使用原dt")
            combatAlly.atkInterval = 100000
            local cycle = Scene.cycleBattleSpeed
            Scene.cycleBattleSpeed = function() error("旧按钮不得再进入切速分支") end
            for _, size in ipairs({ {1920,1080}, {1280,800} }) do
                local fit = math.min(size[1] / 1920, size[2] / 1080)
                local ox, oy = (size[1] - 1920 * fit) * .5, (size[2] - 1080 * fit) * .5
                Scene.handleInput(ox + 1500 * fit, oy + 110 * fit, size[1], size[2])
                eq(state.confirmOpen, false, "旧按钮位置不误触撤退确认")
            end
            Scene.cycleBattleSpeed = cycle
            eq(cjson.encode(modules.battle), legacyBattle, "副本真实时钟/旧点击不修改账户进度")
            Scene.draw(nil) -- 真实draw入口调用，卡组仅观测坐标/作用域，不冒充像素验收。
            unchanged()
            eq(#state.enemies, 4, id .. "同屏4")
            eq(#state.enemies + #state.enemyQueue, #expected, id .. "更多敌人与主线出怪数同源")
            check(#expected > 4, "超出4名必须进入队列")
            eq(DB.getConfig().stageEntry, challenge.stageEntry, "消费回执stageEntry引用")
            eq(DB.getClassBonus(), "", "资源模式无旧职业加成")
            eq(DB.getDamageMultiplier({ classId = "spoil" }), 1, "旧classBonus不能污染资源伤害")
            local bossCount = 0
            for _, list in ipairs({ state.enemies, state.enemyQueue }) do
                for _, unit in ipairs(list) do
                    if unit.isBoss then bossCount = bossCount + 1 end
                    eq(unit.goldReward, 0, "敌人金币不另发")
                    eq(unit.expReward, 0, "敌人经验不另发")
                end
            end
            eq(bossCount, challenge.stageEntry.bossId > 0 and 1 or 0, "Boss主线标记一致")
            local first = state.enemies[1]
            local survivor = state.enemies[2]
            local queueBefore = #state.enemyQueue
            kill(first)
            Scene.update(0.41)
            check(state.enemies[1] == survivor, "单名死亡退场，其他存活者保留")
            eq(#state.enemies, 4, "无需全灭即补位")
            eq(#state.enemyQueue, queueBefore - 1, "补位只消费队列一个")
            unchanged()
            Scene.forceClose()
            eq(Scene.isOpen(), false, "退出场景关闭")
            eq(DB.isActive(), false, "退出清副本模式")
            eq(#state.enemyQueue, 0, "退出清后备队列")
            eq(cjson.encode(SC.getStage(challenge.stageEntry.id)), sourceSnapshot, "不修改主线配置或奖励")
            unchanged()
        end

        -- 高难层使用地图/Boss公共链；静态加成也覆盖尚未入场Boss。
        local bossFloor
        for floor = 1, DC.MAX_FLOOR.black_diamond do
            local entry = DC.getCombatEntry("black_diamond", floor)
            if entry.bossId > 0 and SC.getDifficulty(entry.id) ~= SC.DIFFICULTY_NORMAL then bossFloor = floor break end
        end
        check(bossFloor ~= nil, "存在困难Boss资源层")
        local challenge = data("black_diamond", bossFloor, 2, "boss-current")
        Scene.open({ data = challenge, allies = { ally() } })
        local expectedAffixes = compile("config.MapAffixConfig").getAffixesForChapter(challenge.stageEntry.chapter) or {}
        Scope.run(2, function()
            eq(#(MAS.getActiveAffixes() or {}), #expectedAffixes, "地图词缀按源章节配置而非难度猜测")
            check(BAS.hasAffixes(), "困难Boss词缀加载")
        end)
        local berserk = Runtime.getBerserk()
        check(berserk.isActive(), "资源使用独立主线狂暴实例")
        Scope.run(2, function() DB.update(120, state.enemies, state.allies) end)
        eq(DB.getRagePhase(), 1, "主线120秒狂暴不是旧30秒")
        for _, list in ipairs({ state.enemies, state.enemyQueue }) do
            for _, unit in ipairs(list) do kill(unit) end
        end
        for _ = 1, 30 do Scene.update(0.41) end
        eq(state.battleState, "win", "完整队列杀完再胜利")
        eq(actions[#actions].action, Protocol.ACTION_TYPES.DUNGEON_WIN, "资源只发送WIN链")
        eq(actions[#actions].params.teamIdx, 2, "WIN显式队号")
        eq(actions[#actions].params.challengeId, challenge.challengeId, "WIN携带挑战ID")
        local actionCount = #actions
        DB.onVictory()
        eq(#actions, actionCount, "胜利重复调用不重复请求")
        local correct = receipt(challenge)
        for _, key in ipairs({ "dungeonId", "floor", "teamIdx", "challengeId", "action" }) do
            local wrong = receipt(challenge)
            wrong[key] = key == "floor" and (challenge.floor + 1) or "mismatch"
            eq(Scene.onActionResult(wrong), false, "错" .. key .. "回执拒绝")
        end
        eq(DB.isResultReady(), false, "错误回执不能放开奖励等待")
        eq(Scene.onActionResult(correct), true, "正确回执消费一次")
        eq(Scene.onActionResult(correct), false, "重复回执拒绝")
        Scene.update(2)
        eq(results[#results].rewards[1].type, "diamond", "黑钻入口货币仍diamond")
        eq(results[#results].rewards[1].amount, 987, "只展示服务端金额")
        local before = cancels
        Scene.close()
        eq(cancels, before, "胜利回执完成不错误清service")
        eq(Scene.onActionResult(correct), false, "场景关闭后迟到回执拒绝")
        unchanged()
        local bad = data("gold_mine", 1, 2, "missing-entry")
        bad.stageEntry = nil
        eq(pcall(Scene.open, { data = bad, allies = { ally() } }), false, "缺stageEntry不能回退旧出怪")
        eq(Scene.isOpen(), false, "开场失败不留半开场景")
        unchanged()

        -- 真实撤退按钮链清pending，遗留投射物/队列不得继续攻击。
        challenge = data("equipment_vault", 1, 3, "retreat")
        Scene.open({ data = challenge, allies = { ally() } })
        before = cancels
        Scene.handleInput(1750, 110)
        local confirmFit = math.min(1920 / 1120, 1080 / 800)
        Scene.handleInput(960 + (340 - 540) * confirmFit, 540 + (1310 - 1100) * confirmFit)
        eq(state.battleState, "lose", "确认撤退判负")
        eq(cancels, before + 1, "撤退清单机资源pending")
        eq(Scene.onActionResult(receipt(challenge)), false, "撤退后WIN拒绝")
        Scene.update(2)
        eq(#results[#results].rewards, 0, "撤退无奖励")
        Scene.close()

        -- 满包回执完整保留原装备及destination，不生成、不再发奖。
        local equip = { uid = 777, templateId = "W1", quality = 4, level = 50 }
        local rewardData = { success = true, equips = {
            { type = "equip", equip = equip, templateId = equip.templateId, quality = 4, level = 50, destination = "lootbox" },
        }, lootboxCount = 1 }
        local rewards = Rewards.build(rewardData)
        eq(#rewards, 1, "equip回执一项展示")
        eq(rewards[1].equip, equip, "保留后端装备实例")
        eq(rewards[1].destination, "lootbox", "满包去向保留")
        check(Rewards.overflowText(rewardData):find("遗匣", 1, true), "满包明确提示遗匣")
        eq(#Rewards.build({ success = false, gold = 999, equips = rewardData.equips }), 0, "失败回执无奖励")
        eq(#Rewards.build({ success = true, rewardType = "equip", amount = 6, equips = rewardData.equips }), 1,
            "挂机equip不重复追加货币项")

        -- 当前结算异常失败可展示关闭；过期失败仍不能解除当前等待。
        challenge = data("gold_mine", 1, 2, "error-current")
        Scene.open({ data = challenge, allies = { ally() } })
        for _, list in ipairs({ state.enemies, state.enemyQueue }) do
            for _, unit in ipairs(list) do kill(unit) end
        end
        for _ = 1, 30 do Scene.update(0.41) end
        local failed = receipt(challenge)
        failed.success, failed.reason = false, "本地处理失败"
        failed.challengeId = "old-error-token"
        eq(Scene.onActionResult(failed), false, "过期失败回执拒绝")
        eq(DB.isResultReady(), false, "过期失败不解除等待")
        failed.challengeId = challenge.challengeId
        eq(Scene.onActionResult(failed), true, "当前异常失败回执接受")
        Scene.update(2)
        eq(results[#results].isWin, false, "结算异常不显示胜利")
        eq(#results[#results].rewards, 0, "结算异常不显示奖励")
        results[#results].onClose()
        eq(Scene.isOpen(), false, "异常结算可正常关闭")
        unchanged()

        -- 独立ETS dirty只保存最新拥有状态；双向旧快照不得复活已消费库存或回退成长。
        local cpMock = mocks["ui.character.panel.CharacterPanel"]
        local oldOwned = cpMock.getOwnedHero
        local newestMain = ETS.normalize({ stacks = 20, preciseStored = 1, blockBank = 2,
            conquerCarry = 3, beamCharges = 0, iceStatues = 1, tickets = { latest = true } })
        local ownedHeroes = { [3] = { extraTalent = newestMain } }
        cpMock.getOwnedHero = function(id) return ownedHeroes[id] end
        cpMock.patchExtraTalent = function(id, extra)
            if ownedHeroes[id] then ownedHeroes[id].extraTalent = extra end
        end
        local oldDirty = mainExtra.dirty
        mainExtra.dirty = { [3] = ETS.normalize({ stacks = 10, preciseStored = 5,
            blockBank = 7, conquerCarry = 6, beamCharges = 5, iceStatues = 3, tickets = { stale = true } }) }
        ETS.flush()
        sameTree(ownedHeroes[3].extraTalent, newestMain, "整表保存最新成长和可消耗字段")
        eq(ownedHeroes[3].extraTalent.stacks, 20, "主线旧dirty不回退副本成长")
        eq(ownedHeroes[3].extraTalent.preciseStored, 1, "主线旧dirty不复活已消费精准")
        eq(actions[#actions].params.extraTalent.stacks, 20, "发送最新拥有成长")
        eq(actions[#actions].params.extraTalent.preciseStored, 1, "发送最新消费库存")
        Scope.run(1, function()
            ETS.mountedState().dirty[3] = ETS.normalize({ stacks = 20, preciseStored = 4 })
        end)
        local newestDungeon = ETS.normalize({ stacks = 30, preciseStored = 0, blockBank = 0,
            conquerCarry = 0, beamCharges = 1, iceStatues = 0, tickets = { final = true } })
        ownedHeroes[3].extraTalent = newestDungeon
        Scope.run(1, ETS.flush)
        sameTree(ownedHeroes[3].extraTalent, newestDungeon, "反向保存不合并过期位图和库存")
        eq(ownedHeroes[3].extraTalent.stacks, 30, "副本旧dirty不回退主线成长")
        eq(ownedHeroes[3].extraTalent.preciseStored, 0, "副本旧dirty不max可消耗库存")
        cpMock.getOwnedHero = function() return nil end
        Scope.run(1, function()
            ETS.mountedState().dirty[3] = ETS.normalize({ stacks = 33, preciseStored = 2 })
            ETS.flush()
        end)
        eq(actions[#actions].params.extraTalent.stacks, 33, "无owned回退原dirty状态")
        eq(actions[#actions].params.extraTalent.preciseStored, 2, "无owned不丢原库存")
        cpMock.getOwnedHero, cpMock.patchExtraTalent = oldOwned, nil
        mainExtra.dirty = oldDirty
        unchanged()

        -- 成长边界使用真实副本Scope，胜败/撤退提交，清档丢弃；不能消费宿主dirty哨兵。
        local growthFlushes, growthDiscards = {}, {}
        local originalFlush, originalDiscard = ETS.flush, ETS.discard
        ETS.flush = function()
            growthFlushes[#growthFlushes + 1] = ETS.mountedState()
            return originalFlush()
        end
        ETS.discard = function()
            growthDiscards[#growthDiscards + 1] = ETS.mountedState()
            return originalDiscard()
        end
        local function dungeonGrowthScope()
            return Scope.run(2, function() return ETS.mountedState() end)
        end
        Scene.open({ data = data("gold_mine", 1, 2, "growth-victory"), allies = { ally() } })
        local growthScope = dungeonGrowthScope()
        local growthCount = #growthFlushes
        Scope.run(2, DB.onVictory)
        eq(#growthFlushes, growthCount + 1, "副本胜利消费一次成长")
        eq(growthFlushes[#growthFlushes], growthScope, "胜利只消费副本ETS域")
        Scope.run(2, DB.onVictory)
        eq(#growthFlushes, growthCount + 1, "重复胜利不重复消费")
        Scene.close()
        eq(growthFlushes[#growthFlushes], growthScope, "关闭兜底在副本域消费")
        unchanged()
        Scene.open({ data = data("gold_mine", 1, 2, "growth-defeat"), allies = { ally() } })
        growthCount = #growthFlushes
        Scope.run(2, DB.onDefeat)
        eq(#growthFlushes, growthCount + 1, "副本战败提交实际成长")
        eq(growthFlushes[#growthFlushes], growthScope, "战败只消费副本ETS域")
        Scene.close()
        Scene.open({ data = data("gold_mine", 1, 2, "growth-reset"), allies = { ally() } })
        growthCount = #growthFlushes
        Scene.forceClose(true)
        eq(#growthFlushes, growthCount, "清档强关不能flush旧成长")
        eq(growthDiscards[#growthDiscards], growthScope, "清档丢弃副本独立域")
        growthCount = #growthDiscards
        Scene.forceClose(true)
        eq(#growthDiscards, growthCount + 1, "未打开副本时清档仍丢弃遗留域")
        Scene.open({ data = data("gold_mine", 1, 2, "growth-debug"), allies = { ally() } })
        local debugOwned = { extraTalent = ETS.normalize({ stacks = 10 }) }
        cpMock.getOwnedHero = function(id) return id == 3 and debugOwned or oldOwned(id) end
        cpMock.patchExtraTalent = function(id, extra)
            if id == 3 then debugOwned.extraTalent = extra end
        end
        Scope.run(2, function() ETS.mountedState().pendingGrowth[3] = { stacks = 2 } end)
        growthCount = #growthFlushes
        eq(ETS.mountedState(), mainExtra, "宿主调用debug前仍挂载主线哨兵")
        eq(DB.debugInstantWin(), true, "真实宿主debug瞬胜调用成功")
        eq(#growthFlushes, growthCount + 1, "debug只消费一次副本成长")
        eq(growthFlushes[#growthFlushes], growthScope, "debug瞬胜先挂载副本ETS域")
        eq(debugOwned.extraTalent.stacks, 12, "debug实际提交副本pending成长增量")
        eq(next(growthScope.pendingGrowth), nil, "debug清空已消费副本pending")
        eq(ETS.mountedState(), mainExtra, "debug返回还原主线ETS挂载")
        unchanged() -- 阴性：主线dirty原表/数据保留且没有SYNC哨兵动作。
        eq(DB.debugInstantWin(), true, "重复debug瞬胜沿用结算状态")
        eq(#growthFlushes, growthCount + 1, "重复debug不再次消费")
        Scene.close()
        cpMock.getOwnedHero, cpMock.patchExtraTalent = oldOwned, nil
        ETS.flush, ETS.discard = originalFlush, originalDiscard
        unchanged()

        -- 木桩统计入口绑定独立101桶，真实面板重置不清主线0/三队数据。
        Stats.mount(0)
        Stats.recordDamage({ heroId = 999, name = "主线哨兵" }, 4321, "physical", false)
        local mainAccum = Stats.getTotal("totalDamage", true)
        Scene.open({ data = { dungeonId = "training_dummy", trainingDummy = true,
            monsterLevel = 1, dummyMaxHp = 1000000000000 }, allies = { ally() } })
        Scope.run(1, function()
            Stats.recordDamage(state.allies[1], 765, "physical", false)
            check(Stats.getTotal("totalDamage", true) >= 765, "木桩伤害写独立桶")
        end)
        Scene.handleInput(170, 110)
        eq(DamagePanel.isOpen(), true, "木桩打开真实统计面板")
        eq(upvalue(DamagePanel.open, "state").teamIdx, 101, "木桩面板绑定101而非主线0")
        local damageFit = math.min(1920 / 1120, 1080 / 1300)
        Scene.handleInput(960, 540 + ((1640 - 1195) * 0.8) * damageFit)
        Scope.run(1, function() eq(Stats.getTotal("totalDamage", true), 0, "只重置木桩累计桶") end)
        Stats.mount(0)
        eq(Stats.getTotal("totalDamage", true), mainAccum, "木桩重置保留主线累计")
        Scene.close()
        eq(DamagePanel.isOpen(), false, "退出木桩关闭旧统计面板")
        Stats.reset()
        Stats.resetAccum()
        unchanged()
        check(lifecycleCalls.init > 0 and lifecycleCalls.update > 0, "真实Scene生命周期隔离已观测")

        -- 从正式Standalone抽取真实宿主分流，详情等待与返回首帧不能驱动默认战场。
        local hostFile = assert(cache:GetFile("boot/Standalone.lua"))
        local hostLines = {}
        while not hostFile:IsEof() do hostLines[#hostLines + 1] = hostFile:ReadLine() end
        hostFile:Dispose()
        local hostSource = table.concat(hostLines, "\n")
        local hostUpdate = assert(hostSource:match(
            "(if postStartFlowDone_ and not awaitingOfflineClaim then.-)\n    require%(\"ui%.dev%.CERuntime\"%)%.tick%(%)"))
        local hostReopen = assert(hostSource:match(
            "\n    require%(\"ui%.dev%.CERuntime\"%)%.tick%(%)\n\n    (local tabIndex = BottomNav.getSelectedIndex%(%).-)\n    %-%- 临时验证钩子"))
        local host = { tab = 5, tri = false, updates = 0, opens = 0 }
        local hostEnv = setmetatable({
            postStartFlowDone_ = true, awaitingOfflineClaim = false,
            BottomNav = { getSelectedIndex = function() return host.tab end },
            TowerBattleScene = { isActive = function() return false end },
            DungeonBattleScene = Scene,
            BattleScene = { update = function() error("默认战场不应在副本返回窗口启动", 0) end },
            BattleTriPage = {
                isOpen = function() return host.tri end,
                update = function() host.updates = host.updates + 1 end,
                open = function() host.tri = true; host.opens = host.opens + 1 end,
            },
        }, { __index = _G })
        local hostTick = assert(load("return function(dt)\n" .. hostUpdate .. "\n" .. hostReopen
            .. "\nend", "@正式宿主副本分流", "t", hostEnv))()
        for _ = 1, 40 do hostTick(0.1) end
        eq(host.updates, 0, "详情停留4秒不推进暂停三队")
        unchanged()
        Scene.open({ data = data("gold_mine", 1, 2, "host-scope"), allies = { ally() } })
        hostTick(0.05)
        eq(Scene.isOpen(), true, "宿主独占分流更新副本")
        Scene.close()
        for _ = 1, 40 do hostTick(0.1) end
        unchanged()
        host.tab = 3
        hostTick(0.1)
        eq(host.opens, 1, "返回首帧只重开原三队")
        eq(host.updates, 0, "返回首帧不跑默认场景")
        hostTick(0.1)
        eq(host.updates, 1, "下一帧正常继续三队驱动")
        unchanged()

        -- 独立通天塔旧波次链保持TOWER_WAVE_WIN，不使用资源ID/主线stageEntry。
        Scene.open({ data = { dungeonId = "babel_tower", floor = 2, wave = 4,
            monsterLevel = 1, monsters = { 1 }, classBonus = "spoil" }, allies = { ally() } })
        Scope.run(1, DB.onVictory)
        eq(actions[#actions].action, Protocol.ACTION_TYPES.TOWER_WAVE_WIN, "独立塔胜利链保留")
        eq(actions[#actions].params.wave, 4, "独立塔波次保留")
        Scene.forceClose()
        unchanged()
        print(TAG .. " ALL PASS: " .. assertions .. " assertions")
    end)
    rawset(_G, "require", nativeRequire)
    rawset(_G, "File", nativeFile)
    rawset(_G, "fileSystem", nativeSystem)
    if not ok then log:Write(LOG_ERROR, TAG .. " FAIL after " .. assertions .. ": " .. tostring(err)) end
    engine:Exit()
end
