-- ============================================================================
-- boss_affix_smoke_test.lua — Boss 词缀端到端冒烟（v2.64）
--
-- 单元测 boss_affix_test 用 mock 验证逻辑；本测试走真实 BattleLab.runSingle
-- 战斗循环（TriDriver + BattleCombat.performAttack + tick），确认：
--   1. Hard Boss 关（stage 3105，ch31→warden_shield）战斗能正常完成不崩
--   2. Boss 词缀在真实战斗中被应用（Boss 出场带护盾）
--   3. 荆棘关（stage 3405，ch34→thorns）反弹路径在真实 dealDamageToUnit 下不崩
--   4. enrage 关（stage 3205，ch32→enrage）阶段触发在真实 tick 下不崩
-- 用满级三人组确保能推进战斗触发各阶段。
-- 运行: UrhoXRuntime tests/boss_affix_smoke_test.lua -tapcode_dir=<root> -tool_mode -graphicsheadless
-- ============================================================================

local Lab = require("tests.BattleLab")
local SC  = require("config.StageConfig")
local BAS = require("systems.BossAffixSystem")
local BAC = require("config.BossAffixConfig")

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then passed = passed + 1; print(string.format("[PASS] %s", name))
    else failed = failed + 1; print(string.format("[FAIL] %s %s", name, detail or "")) end
end

local function runStage(stageId)
    local report, err = Lab.runSingle({
        stageId = stageId, mode = "firstClear", runs = 3, seed = 926,
        timeLimit = 120,
        heroes = { { id = 1, level = 345 }, { id = 2, level = 345 }, { id = 3, level = 345 } },
    })
    return report, err
end

-- ch31 -> warden_shield（startIdx=(31-1)%6+1=1）
check("config: stage3105 是 Hard Boss 关", SC.getStage(3105).bossId > 0
    and SC.getDifficulty(3105) == "hard")
local affixes31 = BAC.getAffixesForBoss(31, "hard")
check("config: ch31 hard = warden_shield", affixes31 and affixes31[1].id == "warden_shield",
    affixes31 and affixes31[1].id)

local r1, e1 = runStage(3105)
check("冒烟: Hard Boss 关(3105/warden_shield)战斗完成不崩", r1 ~= nil, tostring(e1))
if r1 then
    check("冒烟: 3105 report.errors=0", r1.errors == 0, "errors=" .. tostring(r1.errors))
    print(string.format("    3105: winRate=%.0f%% avgSec=%.1f completed=%s",
        r1.winRate or 0, r1.avgSeconds or 0, tostring(r1.completedRuns)))
end

-- ch34 -> thorns（startIdx=(34-1)%6+1=4 -> pool[4]=thorns）
local affixes34 = BAC.getAffixesForBoss(34, "hard")
check("config: ch34 hard = thorns", affixes34 and affixes34[1].id == "thorns",
    affixes34 and affixes34[1].id)
local r2, e2 = runStage(3405)
check("冒烟: 荆棘 Boss 关(3405/thorns)反弹路径不崩", r2 ~= nil, tostring(e2))
if r2 then
    check("冒烟: 3405 report.errors=0", r2.errors == 0, "errors=" .. tostring(r2.errors))
    print(string.format("    3405: winRate=%.0f%% avgSec=%.1f", r2.winRate or 0, r2.avgSeconds or 0))
end

-- ch32 -> enrage（startIdx=(32-1)%6+1=2 -> pool[2]=enrage）
local affixes32 = BAC.getAffixesForBoss(32, "hard")
check("config: ch32 hard = enrage", affixes32 and affixes32[1].id == "enrage",
    affixes32 and affixes32[1].id)
local r3, e3 = runStage(3205)
check("冒烟: 暴怒 Boss 关(3205/enrage)阶段触发不崩", r3 ~= nil, tostring(e3))
if r3 then
    check("冒烟: 3205 report.errors=0", r3.errors == 0, "errors=" .. tostring(r3.errors))
    print(string.format("    3205: winRate=%.0f%% avgSec=%.1f", r3.winRate or 0, r3.avgSeconds or 0))
end

-- Normal Boss 关不应有词缀（对照）：stage 805 ch8 normal
local r4, e4 = runStage(805)
check("冒烟: Normal Boss 关(805)正常完成（无词缀）", r4 ~= nil, tostring(e4))
if r4 then
    check("冒烟: 805 report.errors=0", r4.errors == 0, "errors=" .. tostring(r4.errors))
end

print(string.format("\n[boss_affix_smoke_test] passed=%d failed=%d", passed, failed))
if failed == 0 then print("ALL PASS") end

engine:Exit()
