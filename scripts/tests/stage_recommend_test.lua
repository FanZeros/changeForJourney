-- ============================================================================
-- stage_recommend_test.lua — StageRecommendPower 生成表 sanity check（v2.65）
-- v2.65: 采样器触底细化修复后重跑 46 章（早期章节阈值从下限伪值 318/336
--        修正为真实门槛 216/216/323），FIRST_STAGES 表同步更新。
--
-- 验证 fit_stage_recommend.py 生成的推荐表：
--   1. 模块可 require，API 齐全（model/byStage/get/getEstimate）
--   2. 实测章节首关（Normal+Hard 46 章，ml 1..46）推荐值 = PAVA 保序 +
--      最小梯度修正后的展示值，且 x 不为 true（实测数据不打外推标记）
--      ⚠️ 展示值与原始实测阈值允许偏差（Hard 段采样噪声大：ml37 实测 3774
--      反常低于 ml34-36，保序压平后偏差最高 ~37%）——单调性是玩家可见的
--      硬需求，优先于逐点还原实测值；偏差上限 40% 锁死防保序失控。
--   3. 单调性（硬断言）：
--      a) 全表按关卡 ID 升序，推荐 p 不减（章内 + 章间 + 跨难度 + 实测→外推衔接）
--      b) Normal/Hard/Nightmare 各章首关 p 严格递增
--      c) 章内梯度：92 章（46 实测 + 46 外推）全部首关 < 第 5 关
--   4. 外推关卡（ml 47..92）标 x=true；超上限（ml>92）get 返回 nil
--   5. 预估口径 e < 官方口径 p（与 CombatPowerEstimate 系统性偏低一致）
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
    and SRP.model.sampledRange[1] == 1 and SRP.model.sampledRange[2] == 46)
check("model.extrapCap=92", SRP.model and SRP.model.extrapCap == 92)
check("byStage 表存在", type(SRP.byStage) == "table")
check("get 是函数", type(SRP.get) == "function")
check("getEstimate 是函数", type(SRP.getEstimate) == "function")

-- 2. 实测章节首关（46 个）：展示值 = 保序修正值，不打外推标记。
--    stage -> {原始实测p(RAW), 修正后展示p(DISPLAY), 修正后展示e}
local FIRST_STAGES = {
    [101] = { 216, 220, 160 },
    [201] = { 216, 230, 170 },
    [301] = { 323, 330, 230 },
    [401] = { 344, 350, 250 },
    [501] = { 344, 360, 260 },
    [601] = { 425, 430, 330 },
    [701] = { 506, 510, 410 },
    [801] = { 506, 530, 420 },
    [901] = { 528, 550, 430 },
    [1001] = { 574, 580, 470 },
    [1101] = { 690, 690, 590 },
    [1201] = { 1021, 960, 840 },
    [1301] = { 916, 980, 860 },
    [1401] = { 916, 1000, 880 },
    [1501] = { 1052, 1060, 940 },
    [1601] = { 1142, 1090, 970 },
    [1701] = { 1021, 1120, 990 },
    [1801] = { 1328, 1330, 1210 },
    [1901] = { 1572, 1580, 1450 },
    [2001] = { 1881, 1820, 1690 },
    [2101] = { 1758, 1860, 1730 },
    [2201] = { 1962, 1970, 1840 },
    [2301] = { 2367, 2370, 2230 },
    [2401] = { 2773, 2780, 2630 },
    [2501] = { 3289, 3040, 2900 },
    [2601] = { 3479, 3110, 2960 },
    [2701] = { 2827, 3180, 3020 },
    [2801] = { 2555, 3250, 3090 },
    [2901] = { 3352, 3360, 3210 },
    [3001] = { 4021, 4030, 3870 },
    [3101] = { 4094, 4120, 3950 },
    [3201] = { 3948, 4210, 4030 },
    [3301] = { 4239, 4300, 4120 },
    [3401] = { 5119, 5050, 4890 },
    [3501] = { 6004, 5160, 4990 },
    [3601] = { 5339, 5270, 5090 },
    [3701] = { 3948, 5380, 5200 },
    [3801] = { 5782, 5490, 5310 },
    [3901] = { 4094, 5600, 5420 },
    [4001] = { 6598, 6340, 6170 },
    [4101] = { 6078, 6470, 6300 },
    [4201] = { 6747, 6750, 6570 },
    [4301] = { 8096, 7350, 7170 },
    [4401] = { 6672, 7500, 7320 },
    [4501] = { 7268, 7650, 7470 },
    [4601] = { 9307, 9310, 9110 },
}
local nFirst = 0
for _ in pairs(FIRST_STAGES) do nFirst = nFirst + 1 end
check("FIRST_STAGES 覆盖 46 章首关", nFirst == 46, "got " .. nFirst)

local mismatch = 0
for sid, expect in pairs(FIRST_STAGES) do
    local p, extr = SRP.get(sid)
    local e = SRP.getEstimate(sid)
    if p ~= expect[2] or e ~= expect[3] or extr ~= false then
        mismatch = mismatch + 1
        print(string.format("  mismatch stage=%s p=%s(want %s) e=%s(want %s) x=%s(want false)",
            tostring(sid), tostring(p), tostring(expect[2]),
            tostring(e), tostring(expect[3]), tostring(extr)))
    end
end
check("46 个实测章节首关 = 保序修正展示值", mismatch == 0, mismatch .. " 处不符")

-- 2b. 修正幅度约束：|display-raw| ≤ 40%（Hard 段采样噪声大，保序压平后
--     ml37/39 偏差 ~37%；上限 40% 防保序/梯度逻辑失控产出离谱值）
local bigDev = 0
for sid, expect in pairs(FIRST_STAGES) do
    local p = SRP.get(sid)
    if p and math.abs(p - expect[1]) > expect[1] * 0.40 then
        bigDev = bigDev + 1
        print(string.format("  偏差过大 stage=%s raw=%s display=%s", tostring(sid),
            tostring(expect[1]), tostring(p)))
    end
end
check("修正幅度 |display-raw| <= 40%", bigDev == 0, bigDev .. " 处超限")

-- 单值查询 helper：返回确定 number（无条目→-1），消除 nil/多值展开的 LSP 噪声
---@param sid integer
---@return number
local function recP(sid)
    local p = SRP.get(sid)
    return p or -1
end

-- 3a. 全表按关卡 ID 升序 p 不减（章内 + 章间 + 跨难度 + 实测→外推衔接统一保证）
local ids = {}
for sid in pairs(SRP.byStage) do ids[#ids + 1] = sid end
table.sort(ids)
local viol = 0
for i = 2, #ids do
    local prevP = SRP.byStage[ids[i - 1]].p
    local curP = SRP.byStage[ids[i]].p
    if curP < prevP then
        viol = viol + 1
        if viol <= 5 then
            print(string.format("  倒挂 %s(p=%s) -> %s(p=%s)",
                tostring(ids[i - 1]), tostring(prevP), tostring(ids[i]), tostring(curP)))
        end
    end
end
check("全表关卡序 p 不减（含实测→外推衔接）", viol == 0, viol .. " 处倒挂")

-- 3b. Normal + Hard + Nightmare 各章首关 p 严格递增（"下一章推荐必须更高"）
local function firstsStrict(baseId, chapters)
    local prev = nil
    for ch = 0, chapters - 1 do
        local sid = baseId + ch * 100 + 1
        local p = SRP.get(sid)
        if p == nil then return false, sid end
        if prev and p <= prev then return false, sid end
        prev = p
    end
    return true
end
local okN, badN = firstsStrict(100, 23)
check("Normal 23 章首关严格递增", okN, "at stage " .. tostring(badN))
local okH, badH = firstsStrict(2400, 23)
check("Hard 23 章首关严格递增", okH, "at stage " .. tostring(badH))
local okM, badM = firstsStrict(4700, 23)
check("Nightmare(外推) 23 章首关严格递增", okM, "at stage " .. tostring(badM))

-- 3c. 章内梯度：92 章全部有梯度（首关 < 第5关）
local noGrad = 0
for ch = 1, 92 do
    local p1 = recP(ch * 100 + 1)
    local p5 = recP(ch * 100 + 5)
    if p1 > 0 and p5 <= p1 then noGrad = noGrad + 1 end
end
check("92 章章内梯度全覆盖", noGrad == 0, noGrad .. " 章无梯度")
-- 抽查梯度章的中间值单调（ch11: 690..905）
local g11 = { recP(1101), recP(1102), recP(1103), recP(1104), recP(1105) }
local gOk = true
for i = 2, 5 do
    if g11[i] < g11[i - 1] then gOk = false end
end
check("ch11 章内梯度非降且有差异", gOk and g11[5] > g11[1],
    string.format("%s..%s", tostring(g11[1]), tostring(g11[5])))

-- 3d. 整体趋势保留
local p101 = recP(101)
local p4601 = recP(4601)
check("整体趋势: p(4601) >= 20 * p(101)", p4601 >= p101 * 20,
    string.format("p101=%s p4601=%s", tostring(p101), tostring(p4601)))

-- 4. 外推标记：ml=47 (stage 4701) x=true；ml=92 上限内有值；ml=93+ 无条目
local p4701, x4701 = SRP.get(4701)
check("4701(ml47) 有推荐且 x=true", p4701 ~= nil and x4701 == true,
    string.format("p=%s x=%s", tostring(p4701), tostring(x4701)))
local p9205, x9205 = SRP.get(9205)
check("9205(ml92=上限) 有推荐且 x=true", p9205 ~= nil and x9205 == true,
    string.format("p=%s x=%s", tostring(p9205), tostring(x9205)))
-- 实测→外推衔接点单调：4605(ml46 实测末章 boss 关) < 4701(ml47 外推首关)
check("衔接单调: p(4605) < p(4701)", recP(4605) < recP(4701),
    string.format("4605=%s 4701=%s", tostring(recP(4605)), tostring(recP(4701))))
-- ml=93 超限：9301 应无条目
local p9301 = SRP.get(9301)
check("9301(ml93>上限) 返回 nil", p9301 == nil, "p=" .. tostring(p9301))
check("getEstimate(9301) 返回 nil", SRP.getEstimate(9301) == nil)
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
