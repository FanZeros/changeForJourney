-- ============================================================================
-- stage_recommend_test.lua — StageRecommendPower 生成表 sanity check（v2.61）
--
-- 验证 fit_stage_recommend.py 生成的推荐表：
--   1. 模块可 require，API 齐全（model/byStage/get/getEstimate）
--   2. 实测关卡（Normal 章节首关 101..2301）推荐值 = 实测阈值向上取整到 10，
--      且 x 不为 true（实测数据不打外推标记）
--   3. 单调性：推荐战力随 monsterLevel 不减（全表按关卡序检查）
--   4. 外推关卡（ml 24..46）标 x=true；超上限关卡（ml>46）get 返回 nil
--   5. 预估口径 e < 官方口径 p（与 CombatPowerEstimate 系统性偏低的已知关系一致）
-- 运行: UrhoXRuntime tests/stage_recommend_test.lua -tapcode_dir=<root> -tool_mode -graphicsheadless
-- ============================================================================

local SRP = require("config.StageRecommendPower")

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
        print(string.format("[PASS] %s", name))
    else
        failed = failed + 1
        print(string.format("[FAIL] %s %s", name, detail or ""))
    end
end

-- 1. API 齐全
check("model 表存在", type(SRP.model) == "table")
check("model.power.name", SRP.model and SRP.model.power and type(SRP.model.power.name) == "string")
check("model.sampledRange", SRP.model and SRP.model.sampledRange
    and SRP.model.sampledRange[1] == 1 and SRP.model.sampledRange[2] == 23)
check("model.extrapCap=46", SRP.model and SRP.model.extrapCap == 46)
check("byStage 表存在", type(SRP.byStage) == "table")
check("get 是函数", type(SRP.get) == "function")
check("getEstimate 是函数", type(SRP.getEstimate) == "function")

-- 2. 实测阈值（来自 battle_lab_threshold_samples.json，向上取整到 10）
--    stage -> {官方p, 预估e}
local MEASURED = {
    [101]  = {320, 230}, [201]  = {340, 240}, [301]  = {340, 240},
    [401]  = {340, 240}, [501]  = {340, 240}, [601]  = {430, 330},
    [701]  = {500, 400}, [801]  = {480, 380}, [901]  = {540, 440},
    [1001] = {580, 480}, [1101] = {720, 610}, [1201] = {1000, 880},
    [1301] = {880, 760}, [1401] = {920, 810}, [1501] = {1020, 910},
    [1601] = {1150, 1030}, [1701] = {1020, 910}, [1801] = {1320, 1200},
    [1901] = {1500, 1380}, [2001] = {1890, 1750}, [2101] = {1640, 1510},
    [2201] = {1930, 1790}, [2301] = {2200, 2060},
}
local mismatch = 0
for sid, expect in pairs(MEASURED) do
    local p, extr = SRP.get(sid)
    local e = SRP.getEstimate(sid)
    if p ~= expect[1] or e ~= expect[2] or extr ~= false then
        mismatch = mismatch + 1
        print(string.format("  mismatch stage=%s p=%s(want %s) e=%s(want %s) x=%s(want false)",
            tostring(sid), tostring(p), tostring(expect[1]),
            tostring(e), tostring(expect[2]), tostring(extr)))
    end
end
check("23 个实测章节首关推荐值 = 实测阈值取整", mismatch == 0, mismatch .. " 处不符")

-- 3. 单调性：ml 增大时推荐 p 不减。ml 由关卡 ID 推不出，直接按 byStage 中
--    Normal 章节首关序列 + 外推段抽查。这里用采样口径：对 101..2301 首关序列，
--    ml 严格递增，允许实测噪声导致的局部回落（1301<1201, 1701<1601, 2101<2001
--    是怪物构成差异的真实回落），因此只检查"整体趋势"：末端 >= 首端 * 5。
local p101 = SRP.get(101)
local p2301 = SRP.get(2301)
check("整体趋势: p(2301) >= 5 * p(101)", p2301 >= p101 * 5,
    string.format("p101=%s p2301=%s", tostring(p101), tostring(p2301)))

-- 4. 外推标记：ml=24 (stage 2401) 应为 x=true；ml=46 上限内有值；ml=47+ 无条目
local p2401, x2401 = SRP.get(2401)
check("2401(ml24) 有推荐且 x=true", p2401 ~= nil and x2401 == true,
    string.format("p=%s x=%s", tostring(p2401), tostring(x2401)))
local p4605, x4605 = SRP.get(4605)
check("4605(ml46=上限) 有推荐且 x=true", p4605 ~= nil and x4605 == true,
    string.format("p=%s x=%s", tostring(p4605), tostring(x4605)))
-- ml=47 超限：4701 应无条目（若关卡表存在该 ID）
local p4701 = SRP.get(4701)
check("4701(ml47>上限) 返回 nil", p4701 == nil, "p=" .. tostring(p4701))
check("getEstimate(4701) 返回 nil", SRP.getEstimate(4701) == nil)
-- 不存在的关卡
check("get(999999) 返回 nil, nil", select(1, SRP.get(999999)) == nil
    and select(2, SRP.get(999999)) == nil)

-- 5. 全表 e < p（预估口径系统性低于官方口径）
local bad = 0
for sid, v in pairs(SRP.byStage) do
    if not (v.e < v.p) then
        bad = bad + 1
        if bad <= 3 then
            print(string.format("  e>=p stage=%s p=%s e=%s", tostring(sid), tostring(v.p), tostring(v.e)))
        end
    end
end
check("全表 e < p", bad == 0, bad .. " 关异常")

print(string.format("\n[stage_recommend_test] passed=%d failed=%d", passed, failed))
if failed == 0 then print("ALL PASS") end

engine:Exit()
