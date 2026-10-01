-- ============================================================================
-- battle_lab_fit_expand.lua — 分项计价系数「跨难度带」扩展采样器
-- 跑法: ./.cli/UrhoXRuntime tests/battle_lab_fit_expand.lua -tapcode_dir=<项目根> -tool_mode -graphicsheadless
-- 输出: 项目根 battle_lab_fit_expand_samples.json（gitignore），
--       交 scripts/_proc/fit_power_estimate.py --band <标签> 分带回归。
--
-- 目的：验证 v2.57 单带（L8/303）拟合出的 OFF_FACTOR=0.10 在其他难度带是否稳定。
-- 采样矩阵 = 3 职业（战士1/法师2/游侠3）× 2 难度带 × 多装备变异：
--   带 L8  ：303 关（哑雾沼泽3-3，v2.57 已验证的非饱和败局带，~49s）
--   带 L16 ：1501 关（焦土平原，怪物 Lv15，实测 7~11s 非饱和败局）
--   带 L24 ：2301 关（Normal 尾段，怪物 Lv23）——实测 3~4s 速死、DPS 样本弱，
--            仅少量纳入作稳健性对照，预期 R² 低，由回归脚本按带分桶报告。
-- 每带内变异：武器等级扫描（本系攻击组连续变异）+ 本系/异系饰品对照
--   （C2 力量 str / C8 智力 int / C20 vit+spi），制造 phys/mag/generic 组方差。
-- 全部走 Lab.runSingle（单方案），runs=8（分带后每桶样本足够回归即可）。
-- ============================================================================

local Lab = require("tests.BattleLab")

local OUTPUT_FILE = "battle_lab_fit_expand_samples.json"
local RUNS = 8
local SEED = 926
local TIME_LIMIT = 120

-- 职业 → 本系武器（onehand，levelRange 覆盖各带）
--   战士 W1 单手剑{1,16} W2 生铁重剑双手{17,32}（双手不配副手，简化）→ 用 W13 单手斧{1,16}/W14{17,32}
--   法师 W25 法杖双手{1,16} / W31 魔杖单手{1,16} / W32 魔杖{17,32}
--   游侠 W37 弓箭双手{1,16} / W43 单手弩{1,16} / W44{17,32}
-- 为保证 levelRange 合法且单手（不触发双手互斥），统一选单手武器层级。
-- 饰品：C2{8,9999}str / C8{8,9999}int / C20{8,9999}vit+spi（黄玉挂坠）
local CASES = {}

local function addCase(band, label, stageId, heroId, heroLevel, slots)
    CASES[#CASES + 1] = { band = band, label = label, stageId = stageId,
        heroId = heroId, heroLevel = heroLevel, slots = slots }
end

-- 单手武器层级表（各职业 tier1={1,16} / tier2={17,32}）
-- 战士单手剑 W1..W6 → W1(t1) W2(t2)；法师魔杖 W31..W36 → W31(t1) W32(t2)；
-- 游侠单手弩 W43..W48 → W43(t1) W44(t2)。饰品 C2{8,9999}str C8{8,9999}int C20{18,9999}vit+spi
local function weaponFor(heroId, level)
    -- 按英雄等级选 tier，使 weapon level 落在 levelRange 内
    if heroId == 1 then return level <= 16 and "W1" or "W2" end
    if heroId == 2 then return level <= 16 and "W31" or "W32" end
    return level <= 16 and "W43" or "W44"  -- 游侠 id=3
end

-- 每个 (职业, 带) 生成：武器等级扫描 3 档 + 饰品对照 3 档 + 裸装基线
local function addBand(band, stageId, heroId, heroLevel)
    local w = weaponFor(heroId, heroLevel)
    -- 武器等级扫描：用同 tier 内不同 level 制造本系攻击组变异
    local lo, hi = (heroLevel <= 16) and 1 or 17, (heroLevel <= 16) and 16 or 32
    for _, lv in ipairs({ lo, math.floor((lo + hi) / 2), hi }) do
        addCase(band, string.format("%s h%d W%s@%d +C2", band, heroId, w, lv),
            stageId, heroId, heroLevel,
            { weapon = { templateId = w, level = lv }, accessory = { templateId = "C2", level = 8 } })
    end
    -- 饰品对照：本系 vs 异系 vs 通用（武器固定 mid level）
    local mid = math.floor((lo + hi) / 2)
    for _, acc in ipairs({ "C2", "C8", "C20" }) do
        addCase(band, string.format("%s h%d W%s@%d +%s", band, heroId, w, mid, acc),
            stageId, heroId, heroLevel,
            { weapon = { templateId = w, level = mid }, accessory = { templateId = acc, level = 8 } })
    end
    -- 裸装（无饰品）基线
    addCase(band, string.format("%s h%d W%s@%d bare", band, heroId, w, mid),
        stageId, heroId, heroLevel, { weapon = { templateId = w, level = mid } })
end

-- 带 L8：303 关
addBand("L8", 303, 1, 8)
addBand("L8", 303, 2, 8)
addBand("L8", 303, 3, 8)
-- 带 L16：1501 关
addBand("L16", 1501, 1, 16)
addBand("L16", 1501, 2, 16)
addBand("L16", 1501, 3, 16)
-- 带 L24：2301 关（速死带，稳健性对照）
addBand("L24", 2301, 1, 24)
addBand("L24", 2301, 2, 24)
addBand("L24", 2301, 3, 24)

function Start()
    local samples = {}
    for index, case in ipairs(CASES) do
        local report, errMessage = Lab.runSingle({
            stageId = case.stageId, mode = "firstClear", runs = RUNS, seed = SEED,
            timeLimit = TIME_LIMIT,
            heroes = { { id = case.heroId, level = case.heroLevel } },
            loadouts = { A = { [tostring(case.heroId)] = case.slots }, B = {} },
        })
        assert(report, (errMessage or "unknown") .. " @" .. case.label)
        local hp = report.heroPowers[1]
        local sec = report.avgSeconds
        samples[#samples + 1] = {
            band = case.band, label = case.label, heroId = case.heroId,
            heroLevel = case.heroLevel, stageId = case.stageId,
            runs = RUNS, seed = SEED,
            category = hp.category, power = hp.power, estimate = hp.estimate,
            groups = hp.groups,
            measured = {
                avgDamage = report.avgDamage, avgHealing = report.avgHealing,
                avgTaken = report.avgTaken, avgSeconds = sec,
                winRate = report.winRate, errors = report.errors,
                dps = sec > 0 and report.avgDamage / sec or 0,
            },
        }
        print(string.format("[FitExpand] %d/%d %s cat=%s dps=%.1f sec=%.1f win=%.0f%%%s",
            index, #CASES, case.label, hp.category,
            sec > 0 and report.avgDamage / sec or 0, sec, report.winRate,
            report.winRate >= 100 and "  [饱和]" or (sec < 5 and "  [速死弱样本]" or "")))
        assert(report.errors == 0, "样本含错误局: " .. case.label)
    end
    local file = File(OUTPUT_FILE, FILE_WRITE)
    assert(file:IsOpen(), "无法写入 " .. OUTPUT_FILE)
    file:WriteLine(cjson.encode(samples))
    file:Close()
    print("[FitExpand] 已保存 " .. OUTPUT_FILE .. "（" .. #samples .. " 组样本）")
    engine:Exit()
end
