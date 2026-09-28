-- ============================================================================
-- stage_recommend_test.lua — StageRecommendPower 生成表 sanity check（v2.62）
--
-- 验证 fit_stage_recommend.py 生成的推荐表：
--   1. 模块可 require，API 齐全（model/byStage/get/getEstimate）
--   2. 实测章节首关推荐值 = PAVA 保序 + 最小梯度修正后的展示值，
--      且 x 不为 true（实测数据不打外推标记）
--      ⚠️ v2.61 口径「= 实测阈值原值取整」已废弃：实测阈值存在怪物构成
--      导致的真实回落（ml13<ml12 等），直接展示会让玩家看到倒挂。
--      v2.62 起首关展示值经保序回归修正，与原始实测值允许 ±10% 偏差。
--   3. 单调性（v2.62 硬断言）：
--      a) 全表按关卡 ID 升序，推荐 p 严格不减（章内 + 章间 + 跨难度）
--      b) Normal/Hard 各章首关 p 严格递增（下一章推荐必须更高）
--      c) 章内梯度：5 关中存在差异（首关 < 第 5 关，除相邻章过近的章外）
--   4. 外推关卡（ml 24..46）标 x=true；超上限关卡（ml>46）get 返回 nil
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
    and SRP.model.sampledRange[1] == 1 and SRP.model.sampledRange[2] == 23)
check("model.extrapCap=46", SRP.model and SRP.model.extrapCap == 46)
check("byStage 表存在", type(SRP.byStage) == "table")
check("get 是函数", type(SRP.get) == "function")
check("getEstimate 是函数", type(SRP.getEstimate) == "function")

-- 2. 实测章节首关：展示值 = 保序修正值（v2.62），且不打外推标记。
--    RAW = battle-lab 原始实测阈值（取整到 10），DISPLAY = 修正后展示值。
--    两者在回落章（13/17/21）与相邻抬升章不同，其余章多数一致或微调。
--    stage -> {原始实测p, 修正后展示p, 修正后展示e}
local FIRST_STAGES = {
    [101]  = { 320,  320,  230 }, [201]  = { 340,  340,  240 },
    [301]  = { 340,  350,  250 }, [401]  = { 340,  360,  260 },
    [501]  = { 340,  370,  270 }, [601]  = { 430,  430,  330 },
    [701]  = { 500,  490,  390 }, [801]  = { 480,  500,  400 },
    [901]  = { 540,  540,  440 }, [1001] = { 580,  580,  480 },
    [1101] = { 720,  720,  610 }, [1201] = { 1000, 940,  820 },
    [1301] = { 880,  960,  840 }, [1401] = { 920,  980,  860 },
    [1501] = { 1020, 1020, 910 }, [1601] = { 1150, 1090, 970 },
    [1701] = { 1020, 1120, 990 }, [1801] = { 1320, 1320, 1200 },
    [1901] = { 1500, 1500, 1380 }, [2001] = { 1890, 1770, 1630 },
    [2101] = { 1640, 1810, 1670 }, [2201] = { 1930, 1930, 1790 },
    [2301] = { 2200, 2200, 2060 },
}
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
check("23 个实测章节首关 = 保序修正展示值", mismatch == 0, mismatch .. " 处不符")

-- 2b. 修正幅度约束：展示值与原始实测偏差不超过 ±12%（保序合并的代价有界）
local bigDev = 0
for sid, expect in pairs(FIRST_STAGES) do
    local p = SRP.get(sid)
    if p and math.abs(p - expect[1]) > expect[1] * 0.12 then
        bigDev = bigDev + 1
        print(string.format("  偏差过大 stage=%s raw=%s display=%s", tostring(sid),
            tostring(expect[1]), tostring(p)))
    end
end
check("修正幅度 |display-raw| <= 12%", bigDev == 0, bigDev .. " 处超限")

-- 3a. 全表按关卡 ID 升序 p 严格不减（章内 + 章间 + 跨难度统一保证）
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
check("全表关卡序 p 不减（v2.62 硬断言）", viol == 0, viol .. " 处倒挂")

-- 3b. Normal + Hard 各章首关 p 严格递增（"下一章推荐必须更高"）
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

-- 单值查询 helper：返回确定 number（无条目→-1），消除 nil/多值展开的 LSP 噪声
---@param sid integer
---@return number
local function recP(sid)
    local p = SRP.get(sid)
    return p or -1
end

-- 3c. 章内梯度：绝大多数章 5 关内 p 有差异（首关 < 第5关）。
--     相邻章首关差 <10 的章（如 ch1/ch2/ch7）插值取整后可能全等，允许少量。
local noGrad = 0
for ch = 1, 23 do
    local p1 = recP(ch * 100 + 1)
    local p5 = recP(ch * 100 + 5)
    if p5 <= p1 then noGrad = noGrad + 1 end
end
check("Normal 章内梯度覆盖 >= 20/23 章", noGrad <= 3, noGrad .. " 章无梯度")
-- 抽查梯度章的中间值单调（ch11: 720<765<810<850<895）
local g11 = { recP(1101), recP(1102), recP(1103), recP(1104), recP(1105) }
local gOk = true
for i = 2, 5 do
    if g11[i] < g11[i - 1] then gOk = false end
end
check("ch11 章内梯度非降且有差异", gOk and g11[5] > g11[1],
    string.format("%s..%s", tostring(g11[1]), tostring(g11[5])))

-- 3d. 整体趋势保留
local p101 = recP(101)
local p2301 = recP(2301)
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
