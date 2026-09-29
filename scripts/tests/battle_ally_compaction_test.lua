-- ============================================================================
-- battle_ally_compaction_test.lua — 己方阵亡紧凑（死亡补位）回归
-- 覆盖 2026-09-28 改动：
--   1) BattleTriDriver：救不回的阵亡者退场后移到队尾（_fallen），存活者前移补位
--   2) 拦截复活（神器/天赋瞬时复活）的单位原地留下，不进入紧凑
--   3) 退场途中被拉起（hp>0）取消紧凑（训练木桩/防御分支）
-- 跑法: ./.cli/UrhoXRuntime scripts/tests/battle_ally_compaction_test.lua \
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

--- 构造能安全通过 tick 的最小己方单位（无 attrs：不会被神器/天赋拦截复活）
local function mkAlly(name, hp)
    return { name = name, heroId = nil, hp = hp, maxHp = 100, atkProgress = 0 }
end

local function mkEnemy(name, hp)
    return { name = name, monsterId = 1, hp = hp, maxHp = hp, atkProgress = 0,
             expReward = 0, goldReward = 0 }
end

--- 驱动若干帧（1/60 每帧）
local function tickFrames(drv, n)
    for _ = 1, n do
        drv:tick(1 / 60)
    end
end

-- ── 1) 阵亡者退场后移队尾，存活者顺序前移 ──
local function testCompactionMovesDeadToTail()
    local Driver = require("ui.battle.tri.BattleTriDriver")
    local drv = Driver.new(2)
    drv.stageId = 101
    local a, b, c = mkAlly("a", 100), mkAlly("b", 0), mkAlly("c", 100)
    drv.allies = { a, b, c }
    drv.enemies = { mkEnemy("e", 50) }
    drv.enemyQueue = {}
    drv.active = true
    drv.mount()
    drv.bindContext()

    -- b 已是 hp=0：第一帧触发死亡处理（无拦截复活 → _fallenPending + dying 动画）
    tickFrames(drv, 1)
    check(b._fallenPending == true, "救不回的阵亡者进入退场等待（_fallenPending）")

    -- 死亡动画约 0.4s；再补 0.3s 确保 gone → 紧凑完成
    tickFrames(drv, 45)
    check(b._fallen == true, "退场完成后标记 _fallen")
    check(b._fallenPending == nil, "紧凑后清除 _fallenPending")
    local order = {}
    for _, u in ipairs(drv.allies) do order[#order + 1] = u.name end
    check(table.concat(order, "") == "acb",
        "存活者前移、阵亡者移队尾 → acb，实得 " .. table.concat(order, ""))
    check(drv.allies[1] == a and drv.allies[2] == c and drv.allies[3] == b,
        "紧凑后单位对象引用保持（a/c 前移，b 在队尾）")
end

-- ── 2) 拦截复活（hp 被拉回 >0）的单位原地留下 ──
local function testInterceptReviveStaysInPlace()
    local Driver = require("ui.battle.tri.BattleTriDriver")
    local drv = Driver.new(3)
    drv.stageId = 101
    local a, b = mkAlly("a", 100), mkAlly("b", 0)
    drv.allies = { a, b }
    drv.enemies = { mkEnemy("e", 50) }
    drv.enemyQueue = {}
    drv.active = true
    drv.mount()
    drv.bindContext()

    -- 模拟瞬时拦截复活：死亡处理同帧把 hp 拉回（神器/天赋路径在 tick 内先执行，
    -- 这里用钩子替换 ART/TAL 不现实，改为直接验证「hp>0 者不会进入紧凑」的守卫）
    b.hp = 60  -- 视为拦截复活成功
    tickFrames(drv, 40)
    check(b._fallenPending == nil and b._fallen == nil,
        "拦截复活的单位不进入紧凑（无 _fallen/_fallenPending）")
    local order = {}
    for _, u in ipairs(drv.allies) do order[#order + 1] = u.name end
    check(table.concat(order, "") == "ab",
        "拦截复活的单位保持原位 → ab，实得 " .. table.concat(order, ""))
end

-- ── 3) 退场途中被拉起：取消紧凑，不移队尾 ──
local function testRescueCancelsCompaction()
    local Driver = require("ui.battle.tri.BattleTriDriver")
    local drv = Driver.new(2)
    drv.stageId = 101
    local a, b = mkAlly("a", 100), mkAlly("b", 0)
    drv.allies = { a, b }
    drv.enemies = { mkEnemy("e", 50) }
    drv.enemyQueue = {}
    drv.active = true
    drv.mount()
    drv.bindContext()

    tickFrames(drv, 1)          -- b 进入退场等待
    check(b._fallenPending == true, "退场等待已建立（前置）")
    b.hp = 80                    -- 退场途中被拉起（防御分支/训练木桩）
    tickFrames(drv, 2)
    check(b._fallenPending == nil, "被拉起后取消退场等待")
    check(b._fallen == nil, "被拉起后不标记 _fallen")
    local order = {}
    for _, u in ipairs(drv.allies) do order[#order + 1] = u.name end
    check(table.concat(order, "") == "ab",
        "被拉起的单位保持原位 → ab，实得 " .. table.concat(order, ""))
end

-- ── 4) 动画状态卡住（永远停在 dying）→ 时间兜底强制紧凑 ──
local function testStuckAnimFallbackCompacts()
    local Driver = require("ui.battle.tri.BattleTriDriver")
    local BattleCombat = require("ui.battle.combat.BattleCombat")
    local Reset = require("ui.battle.scene.BattleAllyReset")
    local drv = Driver.new(2)
    drv.stageId = 101
    local a, b, c = mkAlly("a", 100), mkAlly("b", 0), mkAlly("c", 100)
    drv.allies = { a, b, c }
    drv.enemies = { mkEnemy("e", 50) }
    drv.enemyQueue = {}
    drv.active = true
    drv.mount()
    drv.bindContext()

    -- 手工构造"退场登记后动画被卡住"：dying 永不到 gone（不 tick 动画更新）
    b.hp = 0
    b._fallenPending = true
    b._fallenAt = 100.0
    BattleCombat.setCardAnim(b, { state = "dying", timer = 0, lungeDir = 1 })

    -- now 远超兜底宽限（退场时长+0.3）→ 强制紧凑
    Reset.compactFallen(drv.allies, 100.0 + 5.0)
    check(b._fallen == true, "卡住动画被兜底强制紧凑（_fallen）")
    local order = {}
    for _, u in ipairs(drv.allies) do order[#order + 1] = u.name end
    check(table.concat(order, "") == "acb",
        "兜底紧凑后存活者前移 → acb，实得 " .. table.concat(order, ""))
    check(BattleCombat.getAnimState(c) == "advance",
        "兜底紧凑给前移者播 advance 动画")
end

testCompactionMovesDeadToTail()
testInterceptReviveStaysInPlace()
testRescueCancelsCompaction()
testStuckAnimFallbackCompacts()

if #failures > 0 then
    print(string.format("[battle_ally_compaction_test] FAILURES=%d", #failures))
    for _, f in ipairs(failures) do print("  - " .. f) end
else
    print("[battle_ally_compaction_test] ALL PASS")
end
