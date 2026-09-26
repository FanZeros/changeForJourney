-- ============================================================================
-- battle_stage_switch_test.lua — 战斗切关回归
-- 覆盖三处修复：
--   1) 失败回退 / 轮回 / 寻怪 后 battleActive 不被过期值覆盖（否则战斗卡死）
--   2) 切关时还原己方出场顺序（否则选关后角色位置变化）
--   3) 行2/3 全灭有墙钟兜底复活（否则永久卡住）
-- 跑法: ./.cli/UrhoXRuntime tests/battle_stage_switch_test.lua -tool_mode -graphicssurfaceless
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

-- ── 1) BattleAllyReset.restoreOrder：按 _slotOrder 原位还原 ──
local function testRestoreOrder()
    local BattleAllyReset = require("ui.battle.scene.BattleAllyReset")

    local function mk(slot, name)
        return { _slotOrder = slot, name = name }
    end
    -- 模拟「阵亡紧凑」后的顺序：2 号阵亡被移到队尾
    local allies = { mk(1, "a"), mk(3, "c"), mk(4, "d"), mk(2, "b") }
    local ref = allies
    BattleAllyReset.restoreOrder(allies)
    check(allies == ref, "restoreOrder 原位排序（数组引用不变）")
    local order = {}
    for i, u in ipairs(allies) do order[i] = u.name end
    check(table.concat(order, "") == "abcd", "restoreOrder 还原槽位顺序 → abcd，实得 " .. table.concat(order, ""))

    -- 无 _slotOrder 时不改动顺序
    local noSlot = { { name = "x" }, { name = "y" } }
    BattleAllyReset.restoreOrder(noSlot)
    check(noSlot[1].name == "x" and noSlot[2].name == "y", "restoreOrder 无槽位信息时保持原序")

    -- 单个元素 / nil 不报错
    BattleAllyReset.restoreOrder({ { _slotOrder = 1 } })
    BattleAllyReset.restoreOrder(nil)
    check(true, "restoreOrder 边界输入不报错")
end

-- ── 2) 失败回退分支不再把过期的 battleActive=false 写回 ──
local function testDefeatRollbackKeepsBattleActive()
    local Phases = require("ui.battle.scene.BattleScenePhases")

    local loaded = 0
    local ally = { name = "a", hp = 0 }
    local ctx
    ctx = {
        -- 进入 process 时是「已全灭」状态
        battleActive = false,
        defeatTimer = 10,        -- 已超过 DEFEAT_DELAY
        reincarnationTimer = nil,
        searchingTimer = nil,
        terminalDefeatPending = false,
        defeatByTimeout = false,
        isFirstClear = true,
        currentStageId = 101,
        maxStageId_ = 101,
        clearedStages = {},
        stageName = "1-1",
        pendingReincarnation = nil,
        bgTransAnim = nil,
        regenAccum = 0,
        enemies = {},
        enemyQueue = {},
        allies = { ally },
        DEFEAT_DELAY = 1.5,
        REINCARNATION_DELAY = 2.0,
        SEARCH_ENEMY_DURATION = 1.0,
        BG_ZOOM_BACK_TARGET = 1,
        BG_ZOOM_FWD_TARGET = 2,
        isPaused = false,
        updateCardAnims = function() end,
        updateFloatingTexts = function() end,
        updateHitFlashes = function() end,
        updateComboQueue = function() end,
        getStageConfig = function()
            return {
                isTerminalTemple = function() return false end,
                getPrevStageId = function() return 101 end,
                getTerminalPrevStageId = function() return 101 end,
            }
        end,
        -- loadStage 把 battleActive 置 true（真实 BattleStageLoad 的行为）
        loadStage = function() loaded = loaded + 1 ctx.battleActive = true end,
        resetAllyUnit = function(u) u.hp = 100 end,
        startBattleTalents = function() end,
        onStageChangedCallback = nil,
        onReincarnateCallback = nil,
        recalcIdleIncome = function() end,
        generateIdleEnemyList = function() return {}, 1 end,
        assignEnemiesToField = function(e) return e, 1 end,
        BattleScene = { nextStage = function() end, refreshAllyStats = function() end },
    }

    local consumed = Phases.process(ctx, 1 / 60)
    check(consumed == true, "失败回退帧被 process 消费")
    check(loaded == 1, "失败回退调用了 loadStage")
    check(ctx.defeatTimer == nil, "失败回退清空 defeatTimer")
    -- 核心断言：loadStage 设的 true 不能被过期局部值覆盖
    check(ctx.battleActive == true,
        "失败回退后 battleActive 保持 true（不被过期 false 覆盖），实得 " .. tostring(ctx.battleActive))
    check(ally.hp == 100, "失败回退重置了己方单位")
end

-- ── 3) BattleTriDriver 全灭墙钟兜底 ──
local function testTriDriverWipeFallback()
    local Driver = require("ui.battle.tri.BattleTriDriver")
    local drv = Driver.new(2)

    -- 两个都没有 attrs 的单位：单单位复活计时无法推进（旧逻辑会永久卡死）
    -- maxHp 必填：BattleCombat.updateHpBuffers 会读它（真实单位一定有）
    drv.allies = { { name = "a", hp = 0, maxHp = 50 }, { name = "b", hp = 0, maxHp = 60 } }
    drv.enemies = { { name = "e", hp = 10, maxHp = 10 } }
    drv.active = true
    drv.mount()
    drv.bindContext()

    local revivedAt = nil
    for frame = 1, 400 do
        drv:tick(1 / 60)
        local alive = 0
        for _, u in ipairs(drv.allies) do
            if u.hp > 0 then alive = alive + 1 end
        end
        if alive == #drv.allies then revivedAt = frame / 60 break end
    end
    check(revivedAt ~= nil, "行2/3 全灭后能自动复活（不再永久卡死）")
    if revivedAt then
        check(revivedAt <= 6.0, string.format("全灭兜底在 6 秒内触发，实得 %.2fs", revivedAt))
    end
    for _, u in ipairs(drv.allies) do
        check(u.hp > 0, "单位 " .. tostring(u.name) .. " 已复活，hp=" .. tostring(u.hp))
    end
end

function Start()
    print("[battle_stage_switch_test] start")
    local ok, err = pcall(function()
        testRestoreOrder()
        testDefeatRollbackKeepsBattleActive()
        testTriDriverWipeFallback()
    end)
    if not ok then
        print("[FAIL] 测试抛异常: " .. tostring(err))
        failures[#failures + 1] = "exception"
    end
    if #failures == 0 then
        print("[battle_stage_switch_test] ALL PASS")
    else
        print("[battle_stage_switch_test] FAILURES=" .. #failures)
        for _, m in ipairs(failures) do print("  - " .. m) end
    end
end
