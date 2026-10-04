-- ============================================================================
-- terminal_raid_test.lua — 终焉神殿三队协同战（共享生命池）回归
-- 覆盖 2026-09-30 改动：
--   1) TerminalRaid：池=三 Boss HP 之和；任一路受伤三路同步；治疗回池；
--      release 还原原始 takeDamage/heal
--   2) BattleTriDriver 协同分支：单队失守不退关只停摆；池打空判胜；
--      失守队 tick 直接返回；终焉 start 每队只出 1 个 Boss
--   3) BattleScene.completeTriTerminal：胜利→轮回目标关+存档写入；
--      首通回调只在未通关过时触发一次（奖励去重）
-- 跑法: ./.cli/UrhoXRuntime scripts/tests/terminal_raid_test.lua \
--        -tapcode_dir=/workspace -tool_mode -graphicssurfaceless
-- ============================================================================

local failures = {}

local function check(cond, msg)
    if cond then
        print("[PASS] " .. msg)
    else
        print("[FAIL] " .. msg)
        failures[#failures + 1] = msg
    end
end

local TerminalRaid = require("ui.battle.tri.TerminalRaid")
local Driver       = require("ui.battle.tri.BattleTriDriver")
local SC           = require("config.StageConfig")
local MC           = require("config.MonsterConfig")
local AD           = require("systems.AttributeDef")

local TERMINAL = SC.TERMINAL_NORMAL   -- 999（普通难度终焉）

--- 构造能安全通过 tick 的最小己方单位
local function mkAlly(name, hp)
    return { name = name, heroId = nil, hp = hp, maxHp = hp, atkProgress = 0 }
end

--- 构造一支停在终焉关、带真实 Boss 的驱动（不经过 start，避免编队依赖）
local function mkRaidDriver(teamIdx, allies)
    local drv = Driver.new(teamIdx)
    drv.stageId = TERMINAL
    local bossId = SC.getStage(TERMINAL).monsters[teamIdx]
    local boss = MC.createMonster(bossId, SC.getStage(TERMINAL).monsterLevel)
    check(boss ~= nil, string.format("队%d 终焉 Boss %s 可创建", teamIdx, tostring(bossId)))
    boss.isBoss = true
    drv.allies = allies
    drv.enemies = { boss }
    drv.enemyQueue = {}
    drv.active = true
    drv:activate()
    return drv
end

local function mkRaidDrivers()
    local drivers = {
        mkRaidDriver(1, { mkAlly("a1", 100), mkAlly("a2", 100) }),
        mkRaidDriver(2, { mkAlly("b1", 100) }),
        mkRaidDriver(3, { mkAlly("c1", 100) }),
    }
    return drivers
end

local function tickFrames(drv, n)
    for _ = 1, n do
        drv:tick(1 / 60)
    end
end

-- ── 1) TerminalRaid 基础：池构建 / 同步 / 治疗 / release ──
local function testRaidPoolBasics()
    local drivers = mkRaidDrivers()
    local expected = 0
    for row = 1, 3 do expected = expected + drivers[row].enemies[1].hp end
    local raid = TerminalRaid.new(TERMINAL, drivers)
    check(raid.maxHp == expected and expected > 0,
        string.format("共享池=三 Boss HP 之和（%d）", expected))
    check(raid.hp == raid.maxHp, "初始满池")
    check(#raid.enemies == 3, "三路 Boss 全部入池")
    for row = 1, 3 do
        check(raid.lines[row] == drivers[row].enemies[1],
            string.format("队%d 战线归属记录正确（供击杀奖励结算）", row))
    end

    -- 同步：三路显示 HP 与池一致
    raid.hp = raid.maxHp * 0.5
    raid:sync()
    for row = 1, 3 do
        local boss = drivers[row].enemies[1]
        check(boss.hp == raid.hp and boss.attrs.final[AD.HP] == raid.hp,
            string.format("sync 后队%d Boss 显示 HP 与池一致", row))
    end

    -- 包装 takeDamage：直接调 Boss 受伤 → 池同步扣减
    -- （终焉 Boss 自带能量护盾会全额吸收小额伤害，先清空护盾再断言）
    raid.hp = raid.maxHp
    raid:sync()
    local boss1 = drivers[1].enemies[1]
    boss1.attrs.energyShield = 0
    boss1.attrs.tempEnergyShield = 0
    local before = raid.hp
    local actual = boss1.attrs:takeDamage(100)
    check(actual > 0, "包装 takeDamage 返回实际扣血（护盾清空后）")
    check(raid.hp == math.max(0, before - actual),
        string.format("队1 受伤池同步扣减（%d → %d）", before, raid.hp))
    check(drivers[2].enemies[1].hp == raid.hp and drivers[3].enemies[1].hp == raid.hp,
        "其余两路 Boss 显示 HP 跟随池")

    -- 包装 heal：Boss 治疗 → 池回升且不超上限
    local healed = boss1.attrs:heal(50)
    check(healed > 0 and raid.hp > 0, "包装 heal 回池")
    raid.hp = 10
    raid:sync()
    boss1.attrs:heal(raid.maxHp * 2)
    check(raid.hp == raid.maxHp, "治疗不超过池上限")

    -- 池空后拒绝继续扣血/回血
    raid.hp = 0
    raid:sync()
    check(boss1.attrs:takeDamage(100) == 0, "池空后 takeDamage 返回 0")
    check(boss1.attrs:heal(100) == 0, "池空后 heal 返回 0")

    -- release 还原原始函数
    local origTake = raid.originalDamage[boss1].takeDamage
    raid:release()
    check(boss1.attrs.takeDamage == origTake, "release 还原 takeDamage 原型")
    check(drivers[2].enemies[1].attrs.takeDamage ~= nil, "release 不损坏其他路 Boss")
end

-- ── 2) 驱动协同分支：单队失守 / 池空判胜 / 失守队停摆 ──
local function testDriverRaidBranches()
    local drivers = mkRaidDrivers()
    local raid = TerminalRaid.new(TERMINAL, drivers)
    for row = 1, 3 do drivers[row].terminalRaid = raid end

    -- 2a) 队2 全灭 → 只停摆，不结束协同、不退关
    local stageBefore = drivers[2].stageId
    drivers[2].allies[1].hp = 0
    tickFrames(drivers[2], 90)   -- 走完退场动画 + 紧凑 + 全灭判定
    check(raid.defeated[2] == true, "队2 全灭标记失守（onTeamDefeated）")
    check(raid.finished ~= true, "单队失守不结束协同战")
    check(drivers[2].stageId == stageBefore, "失守队不退关（区别于普通关回退）")
    check(drivers[1].stageId == TERMINAL and drivers[3].stageId == TERMINAL,
        "其他队继续留在终焉关")

    -- 失守队 tick 直接返回（不再战斗）
    local atkBefore = drivers[2].enemies[1].atkProgress or 0
    tickFrames(drivers[2], 30)
    check((drivers[2].enemies[1].atkProgress or 0) == atkBefore,
        "失守队 tick 停摆（攻击进度不再推进）")

    -- 2b) 存活队仍可正常输出（简装单位无攻击属性，直接以第三路受伤验证池联动）
    for row = 1, 3 do
        drivers[row].enemies[1].attrs.energyShield = 0
        drivers[row].enemies[1].attrs.tempEnergyShield = 0
    end
    raid.hp = raid.maxHp
    raid:sync()
    tickFrames(drivers[1], 60)   -- 存活队 tick 正常运行不报错
    local beforeAlive = raid.hp
    drivers[3].enemies[1].attrs:takeDamage(1000)
    check(raid.hp < beforeAlive, "存活战线受伤继续压低共享池")
    check(drivers[1].enemies[1].hp == raid.hp, "队1 Boss 显示 HP 跟随池（跨路同步）")

    -- 2c) 池打空 → 任一队 tick 触发胜利
    raid.hp = 0
    raid:sync()
    tickFrames(drivers[3], 2)
    check(raid.finished == true and raid.won == true, "池打空即全队胜利（任一路触发）")

    -- 2d) finish 幂等
    raid:finish(false)
    check(raid.won == true, "finish 幂等（胜局不被改写）")

    raid:release()
end

-- ── 3) 全员失守 → 失败 ──
local function testAllTeamsDefeated()
    local drivers = mkRaidDrivers()
    local raid = TerminalRaid.new(TERMINAL, drivers)
    for row = 1, 3 do drivers[row].terminalRaid = raid end
    for row = 1, 3 do
        for _, u in ipairs(drivers[row].allies) do u.hp = 0 end
    end
    tickFrames(drivers[1], 90)
    tickFrames(drivers[2], 90)
    tickFrames(drivers[3], 90)
    check(raid.finished == true and raid.won == false, "三队全部失守 → 协同战失败")
    raid:release()
end

-- ── 4) 终焉 start：每队只出 1 个 Boss（不走挂机敌表） ──
local function testTerminalStartSingleBoss()
    local drv = Driver.new(2)
    -- 无编队环境：注入 allyFactory 不可用（非 battleLab），依赖真实编队为空时的守卫。
    -- start 内部 isTerminal 分支用 entry.monsters[teamIdx] 建 Boss；allies 允许为空。
    drv:start(TERMINAL)
    check(drv.stageId == TERMINAL, "start 停在终焉关")
    check(#drv.enemies == 1, "终焉每队只出 1 个 Boss，实得 " .. #drv.enemies)
    check(drv.enemies[1] and drv.enemies[1].isBoss == true, "Boss 带 isBoss 标志")
    check(drv.enemies[1].monsterId == SC.getStage(TERMINAL).monsters[2],
        "队2 出怪物表第 2 位 Boss")
    check(#drv.enemyQueue == 0, "终焉无补位队列")
end

-- ── 5) BattleScene.completeTriTerminal：轮回推进 + 奖励去重 ──
local function testCompleteTriTerminal()
    local BattleScene = require("ui.battle.scene.BattleScene")
    local targetId = SC.getReincarnationTarget(SC.getDifficulty(TERMINAL))
    check(targetId ~= nil, "轮回目标关存在")

    -- 首通回调计数
    local fcCalls = {}
    local oldSetOnFirstClear = BattleScene.setOnFirstClear
    BattleScene.setOnFirstClear(function(id) fcCalls[#fcCalls + 1] = id end)

    -- 前置：末关已通关 + maxStage 达标，adopt 到终焉
    local lastStage = SC.getTerminalPrevStageId(TERMINAL)
    BattleScene.adoptStageProgress(lastStage)
    BattleScene.getClearedStages()[lastStage] = true
    BattleScene.adoptStageProgress(TERMINAL)
    check(BattleScene.getStageId() == TERMINAL, "主线已停在终焉关")

    local ok = BattleScene.completeTriTerminal(TERMINAL)
    check(ok == true, "completeTriTerminal 成功")
    check(BattleScene.getStageId() == targetId,
        string.format("胜利后主线推进到轮回目标 %s，实得 %s",
            tostring(targetId), tostring(BattleScene.getStageId())))
    check(BattleScene.getClearedStages()[TERMINAL] == true, "终焉关标记已通关")
    check(BattleScene.getMaxStageId() >= targetId, "maxStageId 覆盖轮回目标")
    check(#fcCalls == 1 and fcCalls[1] == TERMINAL,
        "首通回调恰好触发一次（fcExp 等奖励入账）")

    -- 重打已通关的终焉：不再重复发首通奖励
    BattleScene.adoptStageProgress(TERMINAL)
    local ok2 = BattleScene.completeTriTerminal(TERMINAL)
    check(ok2 == true, "重打通关过的终焉仍可胜利轮回")
    check(#fcCalls == 1, "重复通关不再触发首通回调（奖励去重），实得 " .. #fcCalls)
    check(BattleScene.getStageId() == targetId, "重复通关同样推进轮回目标")

    BattleScene.setOnFirstClear = oldSetOnFirstClear
end

-- ── 6) 真实Page终焉结算：Flush早于重建战线时也应保存全队退出目标 ──
local function testPageTerminalSnapshots()
    local nativeRequire = require
    local restores = {}
    local function replace(owner, key, value)
        local previous = owner[key]
        restores[#restores + 1] = function() owner[key] = previous end
        owner[key] = value
    end
    local ok, err = pcall(function()
        local Scene = nativeRequire("ui.battle.scene.BattleScene")
        local Dispatcher = nativeRequire("runtime.ClientDispatcher")
        local Scope = nativeRequire("ui.battle.scene.BattleMountScope")
        local Schema = nativeRequire("shared.battle.BattleSchema")
        local last = SC.getTerminalPrevStageId(TERMINAL)
        local target = SC.getReincarnationTarget(SC.getDifficulty(TERMINAL))
        local modules = { battle = { currentStageId = last, maxStageId = last,
            teamCurrentStageIds = { last, last, last }, clearedStages = { [tostring(last)] = true }, battleMode = "idle" } }
        replace(Dispatcher, "get", function(key) return modules[key] end)
        replace(Dispatcher, "notifySubscribers", function() end)
        replace(Scene, "pumpBattleCards", function() end)
        local raid = nil ---@type table|nil
        local created = {}
        local makeRaid, makeDriver = TerminalRaid.new, Driver.new
        replace(TerminalRaid, "new", function(id, drivers)
            raid = makeRaid(id, drivers)
            return raid
        end)
        replace(Driver, "new", function(team)
            local drv = makeDriver(team)
            -- 创建/开战/结算使用真实Driver，唯独不随机模拟伤害时钟。
            drv.update = function() end
            created[team] = drv
            return drv
        end)
        local mocks = {
            ["ui.battle.scene.BattleScene"] = Scene,
            ["ui.battle.tri.BattleTriDriver"] = Driver,
            ["ui.battle.tri.TerminalRaid"] = TerminalRaid,
            ["ui.battle.scene.BattleMountScope"] = Scope,
            ["shared.battle.BattleSchema"] = Schema,
            ["runtime.ClientDispatcher"] = Dispatcher,
            ["ui.character.panel.CharacterPanel"] = { getTeamSignature = function(t) return "terminal" .. t end,
                getDeployedTeam = function(t) return { mkAlly("page" .. t, 100) } end },
            ["ui.hud.BottomNav"] = { setAllLocked = function() end },
            ["systems.GameBGM"] = { setScene = function() end },
            ["ui.story.gate.LetterIntro"] = { isOpen = function() return false end },
            ["ui.story.gate.IntroCutscene"] = { isActive = function() return false end },
            ["ui.story.ScenarioDialogue"] = { isActive = function() return false end },
            ["ui.battle.popup.TerminalConfirmDialog"] = { update = function() end },
        }
        replace(_G, "require", function(name) return mocks[name] or nativeRequire(name) end)
        local function compile(name)
            local f = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"))
            local lines = {}
            while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
            f:Dispose()
            return assert(load(table.concat(lines, "\n"), "@" .. name, "t", _G))()
        end
        local Save = compile("boot.StandaloneSave")
        local snapshots, snapshotWindows = {}, {}
        Save.Flush = function()
            snapshotWindows[#snapshotWindows + 1] = created[2] and created[3]
                and created[2].stageId == TERMINAL and created[3].stageId == TERMINAL
                and created[2].pendingStageId == target and created[3].pendingStageId == target
            snapshots[#snapshots + 1] = Save.CaptureBattleProgress(modules.battle)
            return true
        end
        mocks["boot.StandaloneSave"] = Save
        local Page = compile("ui.battle.tri.BattleTriPage")
        mocks["ui.battle.tri.BattleTriPage"] = Page
        Save.SetBattlePage(Page)
        Scene.adoptStageProgress(last)
        Scene.getClearedStages()[last] = true
        Page.setTeamStageIds({ last, last, last })
        Page.open()
        check(created[1] and created[2] and created[3], "真实Scope执行Page.open创建三条终焉参战线")
        Scene.adoptStageProgress(TERMINAL)
        Page.close()
        Page.open()
        assert(raid, "Page必须创建真实TerminalRaid")
        check(created[2].stageId == TERMINAL and created[3].stageId == TERMINAL,
            "Page接管终焉后三条真实驱动均停挑战关")
        raid.hp = 0
        raid:sync()
        Page.update(0)
        check(#snapshots > 0, "真实Page胜利结算调用Flush出口")
        local snapshot = snapshots[#snapshots]
        check(snapshotWindows[#snapshots] and snapshot and snapshot.currentStageId == target
            and snapshot.teamCurrentStageIds[1] == target
            and snapshot.teamCurrentStageIds[2] == target and snapshot.teamCurrentStageIds[3] == target,
            "终焉Flush在旧驱动尚未start时采集全队pending轮回目标")
        check(snapshot and snapshot.clearedStages[tostring(TERMINAL)] == true and snapshot.maxStageId == target,
            "终焉快照共享首通和max与退出目标一致")
        check(created[2].stageId == target and created[3].stageId == target,
            "即时快照后队二三真实start落实轮回目标")
        Page.close()
    end)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then error(err, 0) end
end

function Start()
    local ok, err = pcall(function()
        testRaidPoolBasics()
        testDriverRaidBranches()
        testAllTeamsDefeated()
        testTerminalStartSingleBoss()
        testCompleteTriTerminal()
        testPageTerminalSnapshots()
    end)
    if not ok then
        check(false, "测试抛异常: " .. tostring(err))
    end
    if #failures > 0 then
        print(string.format("[terminal_raid_test] FAILURES=%d", #failures))
        for _, f in ipairs(failures) do print("  - " .. f) end
    else
        print("[terminal_raid_test] ALL PASS")
    end
    engine:Exit()
end
