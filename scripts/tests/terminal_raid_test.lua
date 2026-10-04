-- ============================================================================
-- terminal_raid_test.lua — 终焉神殿九实例 / 三个同编号生命池回归
-- 使用真实 TerminalRaid / BattleTriDriver / BattleTriPage；只 patch 测试边界，
-- 每个用例即使抛异常也逆序 restore。普通关行为不在本文件中替换。
-- 跑法: .cli/UrhoXRuntime tests/terminal_raid_test.lua \
--        -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 必须看到 SUMMARY / ALL PASS；engine:Exit() 的退出码不能代替断言结果。
-- ============================================================================

local failures, assertions = 0, 0
local restores = {}

local function check(cond, msg)
    assertions = assertions + 1
    print((cond and "[PASS] " or "[FAIL] ") .. msg)
    if not cond then failures = failures + 1 end
end

local function defer(fn) restores[#restores + 1] = fn end

local function patch(object, key, value)
    local original = object[key]
    defer(function() object[key] = original end)
    object[key] = value
    return original
end

local function restoreTo(index)
    for i = #restores, index + 1, -1 do
        local fn = table.remove(restores)
        local ok, err = pcall(fn)
        if not ok then check(false, "restore 异常: " .. tostring(err)) end
    end
end

local function case(name, fn)
    local index = #restores
    local ok, err = pcall(fn)
    if not ok then check(false, name .. "异常: " .. tostring(err)) end
    restoreTo(index)
end

local TerminalRaid = require("ui.battle.tri.TerminalRaid")
local Driver = require("ui.battle.tri.BattleTriDriver")
local SC = require("config.StageConfig")
local MC = require("config.MonsterConfig")
local HC = require("config.HeroConfig")
local AD = require("systems.AttributeDef")
local BC = require("ui.battle.combat.BattleCombat")
local PS = require("ui.battle.combat.ProjectileSystem")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local BattleStats = require("systems.BattleStats")
local BattleEffects = require("ui.battle.combat.BattleEffects")
local TM = require("systems.ThreatManager")
local TERMINAL = SC.TERMINAL_NORMAL

local function mkAlly(name, hp)
    return { name = name, hp = hp, maxHp = hp, atkProgress = 0 }
end

-- 手工装配测试战线，但敌人、状态和 tick 均为生产实现；真实 start 另有覆盖。
local function mkRaidDriver(teamIdx, allies)
    local drv = Driver.new(teamIdx)
    local entry = assert(SC.getStage(TERMINAL))
    drv.stageId = TERMINAL
    drv.allies = allies
    drv.enemies = {}
    for _, bossId in ipairs(entry.monsters) do
        local boss = assert(MC.createMonster(bossId, entry.monsterLevel))
        boss.isBoss, boss.atkProgress = true, 0
        drv.enemies[#drv.enemies + 1] = boss
    end
    drv.enemyQueue = {}
    drv.active = true
    drv:activate()
    return drv
end

local function mkRaidDrivers(emptyRow)
    local drivers = {}
    for row = 1, 3 do
        drivers[row] = mkRaidDriver(row,
            row == emptyRow and {} or { mkAlly("team" .. row, 100) })
    end
    return drivers
end

local function bindRaid(drivers)
    local raid = TerminalRaid.new(TERMINAL, drivers)
    for row = 1, 3 do drivers[row].terminalRaid = raid end
    defer(function()
        raid:release()
        for row = 1, 3 do drivers[row].terminalRaid = nil end
    end)
    return raid
end

local function tickFrames(drv, count, dt)
    for _ = 1, count do drv:update(dt or 1 / 60) end
end

local function clearShield(boss)
    boss.attrs.energyShield, boss.attrs.tempEnergyShield = 0, 0
end

local function killPool(raid, row, index)
    local boss = raid.lines[row][index]
    clearShield(boss)
    return boss.attrs:takeDamage(raid.pools[index].maxHp * 100)
end

local function testRaidPoolBasics()
    local drivers = mkRaidDrivers()
    local maxByIndex, expected = {}, 0
    for index = 1, 3 do
        maxByIndex[index] = drivers[1].enemies[index].maxHp
        expected = expected + maxByIndex[index]
    end
    local raid = bindRaid(drivers)
    check(#raid.enemies == 9 and #raid.pools == 3, "九个 Boss 实例绑定三个编号池")
    check(raid.hp == expected and raid.maxHp == expected, "raid HP/MAX_HP 是三个单 Boss 池合计")
    local seen = {}
    for index = 1, 3 do
        local pool = raid.pools[index]
        check(pool.maxHp == maxByIndex[index] and pool.maxHp > 0,
            "池" .. index .. "上限等于单 Boss 本身，不乘三")
        check(#pool.enemies == 3, "池" .. index .. "只含同编号三路实例")
        for row = 1, 3 do
            local boss = drivers[row].enemies[index]
            check(raid.lines[row][index] == boss and pool.enemies[row] == boss,
                string.format("lines[%d][%d] 与编号池归属正确", row, index))
            check(not seen[boss] and boss.maxHp == pool.maxHp, "Boss 实例不复用且显示单池上限")
            seen[boss] = true
        end
        pool.hp = math.floor(pool.maxHp * (index + 1) / 5)
    end
    raid:sync()
    local total = 0
    for index = 1, 3 do
        local pool = raid.pools[index]
        total = total + pool.hp
        for row = 1, 3 do
            local boss = raid.lines[row][index]
            check(boss.hp == pool.hp and boss.attrs.final[AD.HP] == pool.hp
                and boss.attrs.final[AD.MAX_HP] == pool.maxHp,
                string.format("sync 只将池%d生命写入队%d同编号 Boss", index, row))
        end
    end
    check(raid.hp == total, "sync 重新汇总三个不同池的 HP")

    for _, pool in ipairs(raid.pools) do pool.hp = pool.maxHp end
    raid:sync()
    local boss = raid.lines[2][2]
    clearShield(boss)
    local before, others = raid.pools[2].hp, { raid.pools[1].hp, raid.pools[3].hp }
    local actual = boss.attrs:takeDamage(100)
    check(actual == 100 and raid.pools[2].hp == before - actual, "队2编号2伤害按实际扣血减池2")
    for row = 1, 3 do
        check(raid.lines[row][2].hp == raid.pools[2].hp, "同编号跨队扣血同步，队" .. row)
    end
    check(raid.pools[1].hp == others[1] and raid.pools[3].hp == others[2], "扣血不影响异编号池")
    local hpBeforeHeal = raid.pools[2].hp
    local healed = raid.lines[3][2].attrs:heal(50)
    check(healed == 50 and raid.pools[2].hp == hpBeforeHeal + healed, "另一战线同编号治疗回池")
    for row = 1, 3 do check(raid.lines[row][2].hp == raid.pools[2].hp, "同编号治疗同步，队" .. row) end
    check(raid.pools[1].hp == others[1] and raid.pools[3].hp == others[2], "治疗不影响异编号池")
    boss.attrs:heal(raid.pools[2].maxHp * 2)
    check(raid.pools[2].hp == raid.pools[2].maxHp, "治疗不超过单池上限")

    killPool(raid, 1, 2)
    for row = 1, 3 do
        check(raid.lines[row][2].hp == 0 and not raid.lines[row][2].attrs:isAlive(), "同编号死亡同步，队" .. row)
        check(raid.lines[row][1].hp > 0 and raid.lines[row][3].hp > 0, "死亡不波及异编号，队" .. row)
    end
    check(boss.attrs:takeDamage(100) == 0 and boss.attrs:heal(100) == 0, "空池拒绝继续扣血/普通治疗复活")
    local originals = raid.originalDamage
    raid:release()
    for _, enemy in ipairs(raid.enemies) do
        check(enemy.attrs.takeDamage == originals[enemy].takeDamage
            and enemy.attrs.heal == originals[enemy].heal, "release 还原每个实例的受伤和治疗")
    end
end

local function testLaneIsolation()
    local drivers = mkRaidDrivers()
    local raid = bindRaid(drivers)
    local a, b, c = raid.lines[1][1], raid.lines[2][1], raid.lines[3][1]
    a.attrs.energyShield, a.attrs.tempEnergyShield = 500, 300
    a.attrs.final[AD.ES_DMG_REDUCE] = 0
    b.attrs.energyShield, b.attrs.tempEnergyShield = 200, 100
    c.attrs.energyShield, c.attrs.tempEnergyShield = 400, 150
    local before = raid.pools[1].hp
    check(a.attrs:takeDamage(100) == 0 and raid.pools[1].hp == before, "本线护盾吸收不扣共享生命")
    check(a.attrs.tempEnergyShield == 200 and a.attrs.energyShield == 500
        and b.attrs.energyShield == 200 and b.attrs.tempEnergyShield == 100
        and c.attrs.energyShield == 400 and c.attrs.tempEnergyShield == 150, "护盾只在命中战线消耗")
    local actual = a.attrs:takeDamage(1000)
    check(actual == 300 and raid.pools[1].hp == before - 300, "穿盾只按剩余生命伤害扣池")
    check(b.attrs.energyShield == 200 and c.attrs.energyShield == 400, "生命同步不复制或消耗其他战线护盾")

    drivers[1]:activate()
    a.attrs.final[AD.ABNORMAL_RES] = 0
    SEM.apply(a, SEM.FROZEN, 10, drivers[1].allies[1], {})
    check(SEM.has(a, SEM.FROZEN) and not SEM.has(raid.lines[1][2], SEM.FROZEN), "状态只施加当前战线指定目标")
    drivers[2]:activate()
    check(not SEM.has(b, SEM.FROZEN) and not SEM.has(a, SEM.FROZEN), "战线2的状态容器无战线1冰冻")
    drivers[3]:activate()
    check(not SEM.has(c, SEM.FROZEN), "战线3同编号 Boss 不被共享冰冻")

    -- 保留真实进度推进，只记录攻击派发，避免无属性哨兵被高等级 Boss 实伤秒杀。
    local attacks, dispatches = {}, {}
    patch(BC, "performAttack", function(attacker, targets, isAlly)
        attacks[attacker] = (attacks[attacker] or 0) + 1
        local state = BC.mountedState()
        local row = 0
        for team = 1, 3 do if state == drivers[team].combatState then row = team end end
        dispatches[#dispatches + 1] = { row = row, attacker = attacker, targets = targets, isAlly = isAlly }
    end)
    local attacker = raid.lines[1][2]
    attacker.attrs.final[AD.ATK_INTERVAL], attacker.attrs.final[AD.ATK_SPEED] = 1, 0
    attacker.atkProgress, a.atkProgress, b.atkProgress, c.atkProgress = 0.99, 0.4, 0.6, 0.7
    drivers[1]:update(0.02)
    check(attacks[attacker] == 1 and attacker.atkProgress < 0.1, "战线1攻击按自己的进度触发一次")
    check(a.atkProgress == 0.4 and not attacks[a], "本线冰冻只阻止该 Boss 攻击")
    check(b.atkProgress == 0.6 and c.atkProgress == 0.7 and not attacks[b] and not attacks[c], "未更新战线攻击进度/派发不联动")

    -- 同一协同帧依次挂载三队：同编号1各自在本线派发一次，绝不能只剩一条攻击记录。
    attacks, dispatches = {}, {}
    for row = 1, 3 do
        drivers[row]:activate()
        SEM.remove(raid.lines[row][1], SEM.FROZEN)
        drivers[row].allies[1].atkProgress = 0
        for index = 1, 3 do
            local boss = raid.lines[row][index]
            boss.attrs.final[AD.ATK_INTERVAL], boss.attrs.final[AD.ATK_SPEED] = 1, 0
            boss.atkProgress = index == 1 and 0.99 or 0
        end
    end
    for row = 1, 3 do drivers[row]:update(0.02) end
    check(#dispatches == 3, "同一协同帧三队同编号独立派发，完整记录恰好三行")
    for row = 1, 3 do
        local entry = dispatches[row]
        local boss = raid.lines[row][1]
        check(entry and entry.row == row and entry.attacker == boss
            and entry.targets == drivers[row].allies and entry.isAlly == false,
            "同编号攻击记录含正确挂载战线/实例/本队目标，队" .. row)
        check(attacks[boss] == 1 and boss.atkProgress > 0 and boss.atkProgress < 0.1,
            "同编号 Boss 自身进度结算一次，队" .. row)
        check(not attacks[raid.lines[row][2]] and not attacks[raid.lines[row][3]],
            "其他编号尚未满进度不连带派发，队" .. row)
    end
end

local function testDriverRaidVictory()
    -- 每个编号都作为首个空池测试，不能只验证编号1。
    for first = 1, 3 do
        local drivers = mkRaidDrivers()
        local raid = bindRaid(drivers)
        killPool(raid, 3, first)
        drivers[1]:update(0)
        check(not raid.finished and raid.hp > 0, "仅池" .. first .. "为空不能胜利")
        for index = 1, 3 do
            if index ~= first then
                killPool(raid, 2, index)
                drivers[1]:update(0)
                local hasRemaining = false
                for _, pool in ipairs(raid.pools) do if pool.hp > 0 then hasRemaining = true end end
                if hasRemaining then check(not raid.finished, "仍有一个非空池不能胜利") end
            end
        end
        check(raid.hp == 0 and raid.finished and raid.won == true, "全部三池空后任一战线 tick 判胜")
        raid:finish(false)
        check(raid.won == true, "finish 幂等，胜局不被失败改写")
    end
end

local function testFallenVisualAndCancellation()
    local drivers = mkRaidDrivers()
    local raid = bindRaid(drivers)
    local drv, dead = drivers[2], drivers[2].allies[1]
    local arrivals, otherArrivals = 0, 0
    drv:activate()
    BC.updateHpBuffers(drv.allies, 0)
    PS.spawn(12, 0, 0, 100, 0, function()
        arrivals = arrivals + 1
        dead.hp = dead.maxHp -- 若未取消，这个未落地回调会错误拉起失守者。
        raid.lines[2][1].attrs:takeDamage(100)
    end)
    drv.combatState.comboQueue[1] = { attacker = dead, targetRef = drv.enemies[1], isAlly = true,
        targetIsAlly = false, timer = 0, delay = 10, comboHitIndex = 1 }
    check(#drv.psState.projectiles == 1 and #drv.combatState.comboQueue == 1, "失守前存在真实未落地投射物与排队连击")
    local liveBoss = drv.enemies[1]
    BC.setCardAnim(liveBoss, { state = "lunge", timer = 0, lungeDir = -1 })
    liveBoss.atkProgress = 0.95
    liveBoss.attrs.energyShield, liveBoss.attrs.tempEnergyShield = 0, 0
    liveBoss.attrs.esRegenCooldown = 0
    liveBoss.attrs.final[AD.ABNORMAL_RES] = 0
    SEM.apply(liveBoss, SEM.FROZEN, 10, dead, {})
    local statusBefore = assert(SEM.get(liveBoss, SEM.FROZEN)).remaining
    drivers[1]:activate()
    PS.spawn(12, 0, 0, 100, 0, function() otherArrivals = otherArrivals + 1 end)
    local otherQueue = drivers[1].psState.projectiles
    dead.hp = 0
    drv:update(0.01)
    check(raid.defeated[2] and not raid.finished and drv.stageId == TERMINAL, "单队失守不收尾、不退关")
    check(BC.getAnimState(dead) == "dying" and dead._fallenPending == true, "失守当帧真实 dying 已登记，非冻结早返")
    check(BC.getHpBuffer(dead) > 0 and BC.getHpBuffer(dead) < 1, "失守当帧生命拖尾缓冲仍推进")
    check(liveBoss.atkProgress == 0 and BC.getAnimState(liveBoss) == nil, "失守清活敌卡攻击动画并归零进度")
    check(#drv.psState.projectiles == 0 and #drv.combatState.comboQueue == 0, "失守立即取消本线投射物和连击")
    check(drivers[1].psState.projectiles == otherQueue and #otherQueue == 1, "取消不清其他战线投射物")
    local hpBefore = raid.hp
    tickFrames(drv, 60)
    check(BC.getAnimState(dead) == "gone" and dead._fallen == true and not dead._fallenPending,
        "失守后视觉 tick 正常播完 dying→gone 并 compact 为 _fallen")
    check(BC.getHpBuffer(dead) == 0, "失守后生命拖尾正常收敛到零")
    check(liveBoss.atkProgress == 0 and liveBoss.attrs.energyShield == 0
        and assert(SEM.get(liveBoss, SEM.FROZEN)).remaining == statusBefore, "停摆不推进攻击/护盾恢复/状态业务")
    PS.update(20)
    BC.updateComboQueue(20)
    check(arrivals == 0 and dead.hp == 0 and raid.hp == hpBefore, "后续更新也不会执行已取消回调或复活/扣池")
    drivers[1]:activate()
    PS.update(20)
    check(otherArrivals == 1, "未失守战线原投射物仍可正常落地一次")
end

local function testAllTeamsDefeatedAndReviveChance()
    local drivers = mkRaidDrivers()
    local raid = bindRaid(drivers)
    for row = 1, 3 do drivers[row].allies[1].hp = 0 end
    drivers[1]:update(0)
    check(raid.defeated[1] and not raid.finished and not raid.defeated[2], "不能凭后更新战线瞬时 HP=0提前判全灭")
    drivers[2]:update(0)
    check(raid.defeated[2] and not raid.finished and not raid.defeated[3], "等最后战线显式失守前不失败")
    drivers[3]:update(0)
    check(raid.defeated[3] and raid.finished and raid.won == false, "三条战线显式 defeated 后才失败")
    for row = 1, 3 do
        tickFrames(drivers[row], 40)
        check(drivers[row].allies[1]._fallen == true, "全员失败仍能播完并 compact，队" .. row)
    end

    local laterDrivers = mkRaidDrivers()
    local reviver = assert(HC.createHero(3, 1, nil, nil, false))
    reviver.litNodeSet = { [125] = true } -- 真实不死鸟之翼：首次死亡恢复到1HP。
    laterDrivers[3].allies = { reviver }
    laterDrivers[3]:activate()
    TAL.initUnit(reviver)
    local laterRaid = bindRaid(laterDrivers)
    for row = 1, 3 do
        local ally = laterDrivers[row].allies[1]
        ally.hp = 0
        if ally.attrs then ally.attrs.final[AD.HP] = 0 end
    end
    local reviveCalls = 0
    local oldAllyDeath = TAL.onAllyDeath
    patch(TAL, "onAllyDeath", function(unit, allies, syncHp)
        if unit == reviver then
            reviveCalls = reviveCalls + 1
            check(not laterRaid.finished, "最后战线瞬时复活钩调用前协同尚未失败")
        end
        return oldAllyDeath(unit, allies, syncHp)
    end)
    for row = 1, 3 do laterDrivers[row]:update(0) end
    check(reviveCalls == 1 and reviver.hp == 1 and not laterRaid.defeated[3] and not laterRaid.finished,
        "后更新队执行真实 TAL 不死鸟瞬时复活后继续协同战")
    reviver.hp, reviver.attrs.final[AD.HP] = 0, 0
    laterDrivers[3]:update(0)
    check(laterRaid.finished and laterRaid.won == false, "复活机会消耗后再死才最终失败")
end

local function testTerminalStartAndSignature()
    local CP = require("ui.character.panel.CharacterPanel")
    local teams = { { mkAlly("one", 100) }, {}, { mkAlly("three", 100) } }
    local signature = "initial"
    patch(CP, "getDeployedTeam", function(row) return teams[row] end)
    patch(CP, "getTeamSignature", function(row) return signature .. row end)
    local drivers = {}
    for row = 1, 3 do
        drivers[row] = Driver.new(row)
        drivers[row]:start(TERMINAL)
        drivers[row].introTimer = 0
        check(drivers[row].stageId == TERMINAL and #drivers[row].enemies == 3, "真实 start 每队全部三 Boss，队" .. row)
        check(#drivers[row].enemyQueue == 0, "终焉无后备队列，队" .. row)
        for index = 1, 3 do
            check(drivers[row].enemies[index].isBoss == true
                and drivers[row].enemies[index].monsterId == SC.getStage(TERMINAL).monsters[index],
                string.format("真实 start 队%d编号%d按配置顺序生成", row, index))
        end
    end
    local raid = bindRaid(drivers)
    check(raid.defeated[2] and #raid.lines[2] == 3 and #raid.enemies == 9, "空队仍生成三 Boss 并完整绑定同编号生命池")
    local originals, starts = {}, 0
    for row = 1, 3 do
        originals[row] = {}
        for index = 1, 3 do originals[row][index] = drivers[row].enemies[index] end
        local oldStart = drivers[row].start
        patch(drivers[row], "start", function(self, id) starts = starts + 1; return oldStart(self, id) end)
        drivers[row]._sigTick = 14
    end
    signature = "changed"
    -- dt=0：穿过多轮签名轮询，不推进高等级敌人的实伤战斗。
    for _ = 1, 45 do for row = 1, 3 do drivers[row]:update(0) end end
    check(starts == 0 and not raid.finished, "协同期间编队 signature 变更不得单路重开")
    for row = 1, 3 do
        for index = 1, 3 do
            check(drivers[row].enemies[index] == originals[row][index]
                and raid.lines[row][index] == originals[row][index], "signature 变化保留 Boss 实例与共享绑定")
        end
    end
end

local function testAllEmptyTeamsRaid()
    local CP = require("ui.character.panel.CharacterPanel")
    patch(CP, "getDeployedTeam", function() return {} end)
    patch(CP, "getTeamSignature", function(row) return "terminal-empty-" .. row end)
    local drivers = {}
    for row = 1, 3 do
        drivers[row] = Driver.new(row)
        drivers[row]:start(TERMINAL)
    end
    local raid = bindRaid(drivers)
    check(raid.finished == true and raid.won == false and raid.hp > 0,
        "三队均空构建协同立即判失败，不能因无队伍判胜")
    check(#raid.enemies == 9 and #raid.pools == 3, "三队均空仍生成九实例和三个生命池")
    local seen, count, bound = {}, 0, true
    for row = 1, 3 do
        check(#drivers[row].allies == 0 and raid.defeated[row] == true
            and drivers[row].terminalRaid == raid and #raid.lines[row] == 3,
            "空队显式失守且三 Boss 绑定仍保留，队" .. row)
        for index = 1, 3 do
            local boss = drivers[row].enemies[index]
            if seen[boss] then bound = false else seen[boss] = true; count = count + 1 end
            if raid.lines[row][index] ~= boss or raid.pools[index].enemies[row] ~= boss
                or not raid.originalDamage[boss] then bound = false end
        end
    end
    check(count == 9 and bound, "三队均空九实例互不复用且全部接入对应编号生命池")
end

-- UrhoX 的 require 有引擎侧缓存，不靠 package.loaded 清缓存隔离私有状态。
-- 从已有生产资源只读编译独立模块；模块代码与真实依赖不替换。
local function compileModule(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"))
    local ok, text = pcall(function()
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        return table.concat(lines, "\n")
    end)
    file:Dispose()
    assert(ok, text)
    return assert(load(text, "@" .. name, "t", _G))()
end

local function openTestPage()
    local CP = require("ui.character.panel.CharacterPanel")
    local BS = require("ui.battle.scene.BattleScene")
    local drivers, teams = {}, {}
    for row = 1, 3 do teams[row] = { assert(HC.createHero(row, 1)) } end
    local stage = TERMINAL
    local observations = { victories = 0, retreats = 0, rewards = {} }
    patch(CP, "getDeployedTeam", function(row) return teams[row] end)
    patch(CP, "getTeamSignature", function(row) return "terminal-test-" .. row end)
    patch(require("config.ExpTable"), "getUnlockedTeamCount", function() return 3 end)
    patch(BS, "getStageId", function() return stage end)
    patch(BS, "pumpBattleCards", function() end)
    patch(BS, "adoptStageProgress", function(id) stage = id; observations.retreats = observations.retreats + 1 end)
    patch(BS, "gotoStage", function(id) stage = id; return true end)
    patch(BS, "completeTriTerminal", function()
        observations.victories = observations.victories + 1
        stage = SC.getReincarnationTarget(SC.getDifficulty(TERMINAL))
        return true
    end)
    patch(require("ui.story.gate.LetterIntro"), "isOpen", function() return false end)
    patch(require("ui.story.gate.IntroCutscene"), "isActive", function() return false end)
    patch(require("ui.story.ScenarioDialogue"), "isActive", function() return false end)
    patch(require("ui.battle.popup.TerminalConfirmDialog"), "update", function() end)
    patch(require("ui.hud.BottomNav"), "setAllLocked", function() end)
    patch(require("systems.GameBGM"), "setScene", function() end)
    local oldNew = Driver.new
    patch(Driver, "new", function(row, opts)
        local drv = oldNew(row, opts)
        drivers[row] = drv
        return drv
    end)
    local Page = compileModule("ui.battle.tri.BattleTriPage")
    defer(function()
        Page.close()
        for _, drv in ipairs(drivers) do
            if drv.terminalRaid then drv.terminalRaid:release(); drv.terminalRaid = nil end
        end
    end)
    Page.setOnKill(function(data) observations.rewards[#observations.rewards + 1] = data end)
    Page.open()
    for row = 1, 3 do drivers[row].introTimer = 0 end
    return Page, drivers, assert(drivers[1].terminalRaid), observations
end

local function testPageFailureHold()
    local Page, drivers, raid, observed = openTestPage()
    check(TerminalRaid.FAILURE_HOLD_SEC >= 1, "失败展示门槛至少1秒")
    for row = 1, 3 do
        for _, ally in ipairs(drivers[row].allies) do ally.hp, ally.attrs.final[AD.HP] = 0, 0 end
    end
    Page.update(0)
    check(raid.finished and raid.won == false and observed.retreats == 0, "真实 Page 全灭当帧不退关")
    local half = TerminalRaid.FAILURE_HOLD_SEC * 0.5
    Page.update(half)
    Page.update(half - 0.01)
    check(observed.retreats == 0 and observed.victories == 0 and #observed.rewards == 0,
        "失败不足 FAILURE_HOLD_SEC 不退关、不发胜利奖励")
    for row = 1, 3 do
        check(drivers[row].terminalRaid == raid and drivers[row].stageId == TERMINAL
            and drivers[row].allies[1]._fallen == true, "延迟期间保留绑定且完成阵亡退场，队" .. row)
    end
    Page.update(0.02)
    local previous = SC.getTerminalPrevStageId(TERMINAL)
    check(observed.retreats == 1 and #observed.rewards == 0, "达到失败展示门槛只退关一次、无奖励")
    for row = 1, 3 do
        check(drivers[row].terminalRaid == nil and drivers[row].stageId == previous, "失败展示结束后解绑并退回前关，队" .. row)
    end
end

local function testPageTimeoutAndLargeDt()
    for _, isTimeout in ipairs({ true, false }) do
        case(isTimeout and "真实 Page 配置时限超时" or "真实 Page 大dt首次全灭", function()
            local Page, drivers, raid, observed = openTestPage()
            local timeLimit = require("config.GameConfig").Battle.TIME_LIMIT_SEC
            local hold = TerminalRaid.FAILURE_HOLD_SEC
            local firstDt = isTimeout and timeLimit or hold + 1
            check(timeLimit > 0 and hold >= 1 and firstDt > hold,
                "使用实际配置时限，首次失败帧dt大于失败展示门槛")
            for row = 1, 3 do
                for _, ally in ipairs(drivers[row].allies) do
                    if isTimeout then
                        -- 只压低夹具攻击频率，保留真实 Page/Driver 更新与超时判定。
                        ally.attrs.final[AD.ATK_INTERVAL], ally.attrs.final[AD.ATK_SPEED] = firstDt * 100, 0
                    else
                        ally.hp, ally.attrs.final[AD.HP] = 0, 0
                    end
                end
                for _, boss in ipairs(drivers[row].enemies) do
                    boss.attrs.final[AD.ATK_INTERVAL], boss.attrs.final[AD.ATK_SPEED] = firstDt * 100, 0
                    boss.atkProgress = 0.5
                end
            end
            check(not raid.finished and observed.retreats == 0, "大dt更新前协同尚未失败或退关")
            Page.update(firstDt)
            check(raid.finished == true and raid.won == false and raid.finishObserved == true
                and raid.finishElapsed == 0 and observed.retreats == 0,
                "首次观察失败不累计当前大dt，不能同帧直接退关")
            if isTimeout then
                local living = true
                for row = 1, 3 do
                    if raid.defeated[row] or drivers[row].allies[1].hp <= 0 then living = false end
                end
                check(raid.elapsed == timeLimit and raid.hp > 0 and living,
                    "真实 Page 到实际 TIME_LIMIT_SEC 判超时，三队仍存活且池未空")
            else
                check(raid.defeated[1] and raid.defeated[2] and raid.defeated[3] and raid.hp > 0,
                    "真实 Page 大dt全灭路径显式确认三队失守，非空池也只判失败")
            end
            -- 超时是在本帧各线更新后才判负，下一次真实 Driver tick 执行停摆清理。
            Page.update(0)
            for row = 1, 3 do
                local stopped = true
                for _, boss in ipairs(drivers[row].enemies) do
                    if boss.atkProgress ~= 0 then stopped = false end
                end
                check(drivers[row].terminalRaid == raid and drivers[row].stageId == TERMINAL
                    and drivers[row]._terminalStopped == true and stopped,
                    "失败留存仍绑定终焉，真实停摆使全部敌人atkProgress=0，队" .. row)
            end
            check(observed.retreats == 0 and observed.victories == 0 and #observed.rewards == 0
                and raid.finishElapsed == 0, "零dt停摆观察不退关、不发奖、不偷算展示时长")
            Page.update(hold - 0.01)
            check(observed.retreats == 0 and raid.finishElapsed < hold,
                "首次大dt之后仍需另等完整失败展示门槛，不足一秒不退关")
            for row = 1, 3 do
                local stopped = true
                for _, boss in ipairs(drivers[row].enemies) do
                    if boss.atkProgress ~= 0 then stopped = false end
                end
                check(drivers[row].terminalRaid == raid and drivers[row].stageId == TERMINAL and stopped,
                    "失败等待期间不重开且全部敌人攻击进度保持零，队" .. row)
            end
            Page.update(0.02)
            check(observed.retreats == 1 and observed.victories == 0 and #observed.rewards == 0
                and raid.finishElapsed >= hold, "另等至少一秒后才退关一次，无胜利或奖励")
            local previous = SC.getTerminalPrevStageId(TERMINAL)
            for row = 1, 3 do
                check(drivers[row].terminalRaid == nil and drivers[row].stageId == previous,
                    "失败展示结束统一解绑并退回前关，队" .. row)
            end
        end)
    end
end

local function testPageImmediateVictoryAndRewards()
    local Page, drivers, raid, observed = openTestPage()
    local expected = {}
    for row = 1, 3 do
        for index = 1, 3 do
            local boss = raid.lines[row][index]
            boss.expReward, boss.goldReward = row * 100 + index, row * 1000 + index
        end
        expected[row] = { expReward = raid.lines[row][row].expReward, goldReward = raid.lines[row][row].goldReward }
    end
    for index = 1, 3 do killPool(raid, 3, index) end
    Page.update(0)
    check(observed.victories == 1 and observed.retreats == 0, "真实 Page 全池空胜利当帧即时收尾，不等失败门槛")
    check(#observed.rewards == 3, "九实例只发三个 Boss 奖励，不按九卡重复")
    for row = 1, 3 do
        local reward = observed.rewards[row]
        check(reward and reward.teamIdx == row and reward.stageId == TERMINAL
            and reward.expReward == expected[row].expReward and reward.goldReward == expected[row].goldReward,
            "仅 lines[row][row] 的实际奖励入账，队" .. row)
        check(reward and #reward.heroIds == 1 and reward.heroIds[1] == drivers[row].allies[1].heroId,
            "奖励经验名单只取对应队存活英雄，队" .. row)
        check(drivers[row].terminalRaid == nil, "胜利当帧解除共享绑定，队" .. row)
    end
    Page.update(0)
    check(observed.victories == 1 and #observed.rewards == 3, "胜利后再次 Page.update 不重复完成或奖励")
end

-- 保留原有 completeTriTerminal 基线：真实轮回推进、存档镜像、首通去重。
-- 隔离 BattleScene 私有进度和持久化边界，不写玩家真实存档。
local function testCompleteTriTerminal()
    local BattleScene = compileModule("ui.battle.scene.BattleScene")
    local Dispatcher = require("runtime.ClientDispatcher")
    local battle = { clearedStages = {} }
    local oldGet = Dispatcher.get
    patch(Dispatcher, "get", function(key) if key == "battle" then return battle end; return oldGet(key) end)
    patch(require("boot.StandaloneSave"), "Flush", function() end)
    patch(require("ui.hud.BottomNav"), "setAllLocked", function() end)
    patch(require("systems.GameBGM"), "setScene", function() end)
    local targetId = SC.getReincarnationTarget(SC.getDifficulty(TERMINAL))
    check(targetId ~= nil, "轮回目标关存在")
    local fcCalls = {}
    BattleScene.setOnFirstClear(function(id) fcCalls[#fcCalls + 1] = id end)
    defer(function() BattleScene.setOnFirstClear(nil) end)
    local lastStage = SC.getTerminalPrevStageId(TERMINAL)
    BattleScene.adoptStageProgress(lastStage)
    BattleScene.getClearedStages()[lastStage] = true
    BattleScene.adoptStageProgress(TERMINAL)
    check(BattleScene.getStageId() == TERMINAL, "主线已停在终焉关")
    check(BattleScene.completeTriTerminal(TERMINAL) == true, "completeTriTerminal 成功")
    check(BattleScene.getStageId() == targetId and BattleScene.getMaxStageId() >= targetId, "胜利推进轮回目标并覆盖 maxStage")
    check(BattleScene.getClearedStages()[TERMINAL] == true and battle.clearedStages[tostring(TERMINAL)] == true,
        "终焉已通关同时写内存进度和隔离存档镜像")
    check(#fcCalls == 1 and fcCalls[1] == TERMINAL, "首通回调恰好一次")
    BattleScene.adoptStageProgress(TERMINAL)
    check(BattleScene.completeTriTerminal(TERMINAL) == true and BattleScene.getStageId() == targetId, "重复通关仍可轮回")
    check(#fcCalls == 1, "重复通关不重复首通奖励")
end

function Start()
    local ok, err = pcall(function()
        case("三池构建/扣血/治疗/死亡/release", testRaidPoolBasics)
        case("护盾/状态/攻击战线隔离", testLaneIsolation)
        case("所有池空才胜利", testDriverRaidVictory)
        case("失守视觉与回调取消", testFallenVisualAndCancellation)
        case("全灭显式确认与后更新队复活机会", testAllTeamsDefeatedAndReviveChance)
        case("真实终焉 start/空队/signature", testTerminalStartAndSignature)
        case("三队均空立即判负但完整绑定", testAllEmptyTeamsRaid)
        case("真实 Page 失败延迟", testPageFailureHold)
        case("真实 Page 超时/大dt首次失败边界", testPageTimeoutAndLargeDt)
        case("真实 Page 即时胜利和奖励口径", testPageImmediateVictoryAndRewards)
        case("真实主线轮回/首通去重", testCompleteTriTerminal)
    end)
    if not ok then check(false, "测试初始化/收尾异常: " .. tostring(err)) end
    restoreTo(0)
    BattleStats.mount(0)
    BC.mount(nil)
    PS.mount(nil)
    TM.mount(nil)
    TAL.mount(nil)
    BattleEffects.mount(nil)
    SEM.mount(nil)
    print(string.format("[terminal_raid_test] SUMMARY assertions=%d failures=%d", assertions, failures))
    if failures == 0 then print("[terminal_raid_test] ALL PASS") end
    if failures > 0 then log:Write(LOG_ERROR, "[terminal_raid_test] failures=" .. failures) end
    engine:Exit()
end
