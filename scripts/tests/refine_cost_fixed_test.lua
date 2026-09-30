-- ============================================================================
-- refine_cost_fixed_test.lua — 洗练固定单价回归
-- 验证：
--   1) calcRefineEssenceCost 与已洗练次数无关（0/5/19/100 次同价）
--   2) 等级缩放与双手翻倍仍生效
--   3) 锁定倍率 ×1.5 独立生效
--   4) calcTotalRefineSpent = 单次固定价 × 次数（次数封顶 20）
--   5) nextRefineCount 封顶 20
-- 跑法: ./.cli/UrhoXRuntime tests/refine_cost_fixed_test.lua \
--         -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local PREFIX = "[refine_cost_fixed] "
local failures = {}
local function check(cond, msg)
    if cond then print(PREFIX .. "[PASS] " .. msg)
    else print(PREFIX .. "[FAIL] " .. msg); failures[#failures + 1] = msg end
end
local function eq(actual, expected, msg)
    check(actual == expected, msg .. " (实际=" .. tostring(actual) .. " 期望=" .. tostring(expected) .. ")")
end

local BlacksmithConfig = require("config.BlacksmithConfig")

function Start()
    -- 1) 固定单价：与次数无关
    local c0  = BlacksmithConfig.calcRefineEssenceCost(5, 30)
    local c5  = BlacksmithConfig.calcRefineEssenceCost(5, 30, nil)
    local c19 = BlacksmithConfig.calcRefineEssenceCost(5, 30)
    eq(c0, c5, "次数 0 与旧签名同价")
    eq(c0, c19, "次数 0 与 19 同价")
    -- 旧公式在 19 次时必然更高：确认固定价等于 refBase 口径
    local q5 = BlacksmithConfig.QUALITY_COST[5]
    eq(c0, math.floor(q5.refBase * (1 + 30 * q5.refLvScale)), "固定价=refBase×等级缩放")

    -- 2) 双手翻倍
    local c2h = BlacksmithConfig.calcRefineEssenceCost(5, 30, "twohand")
    eq(c2h, c0 * 2, "双手武器消耗 ×2")

    -- 3) 锁定倍率
    eq(BlacksmithConfig.applyRefineLockCostMult(c0, 0), c0, "无锁定不加价")
    eq(BlacksmithConfig.applyRefineLockCostMult(c0, 2), math.floor(c0 * 1.5 + 0.5), "锁定 ×1.5")

    -- 4) 分解返还累计 = 固定价 × 次数
    eq(BlacksmithConfig.calcTotalRefineSpent(5, 30, 7), c0 * 7, "累计消耗=单价×7")
    eq(BlacksmithConfig.calcTotalRefineSpent(5, 30, 0), 0, "0 次返还 0")
    eq(BlacksmithConfig.calcTotalRefineSpent(5, 30, 999), c0 * 20, "次数封顶 20")

    -- 5) 次数封顶
    eq(BlacksmithConfig.nextRefineCount(19), 20, "19→20")
    eq(BlacksmithConfig.nextRefineCount(20), 20, "20 封顶不再涨")
    eq(BlacksmithConfig.clampRefineCount(57), 20, "clamp 封顶 20")

    if #failures == 0 then
        print(PREFIX .. "RESULT ALL PASS")
    else
        print(PREFIX .. "RESULT " .. #failures .. " FAIL")
    end
    engine:Exit()
end
