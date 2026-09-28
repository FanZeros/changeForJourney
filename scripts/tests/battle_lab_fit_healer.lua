-- ============================================================================
-- battle_lab_fit_healer.lua — 治疗系数拟合采样器（独立 Runtime 进程）
-- 跑法: ./.cli/UrhoXRuntime tests/battle_lab_fit_healer.lua -tapcode_dir=<项目根> -tool_mode -graphicsheadless
-- 输出: 项目根 battle_lab_fit_healer_samples.json（gitignore），
--       交给 scripts/_proc/fit_power_estimate.py --mode healing 回归。
--
-- 与伤害采样的两点本质差异（探测结论，见 docs/memory-index.md）：
--   1. 治疗量 = min(供给, 需求)。heal/taken 比值接近 1 时治疗被需求截断
--      （饱和），对 HPS 回归无信息量——L28 实测出现「高治疗装反而 heal 更低」
--      的反转即是证据。采样只取 heal/taken < 0.65 的非饱和带，脚本内自检。
--   2. 牧师神圣攻击走 calcHealAttack，单人局无法击杀敌人：要么超时（303 关
--      稳定带）要么阵亡（304/305 关）。两种败局都可回归，target 统一用
--      HPS = avgHealing / avgSeconds，饱和检测交给回归脚本。
--
-- 采样带：
--   带1（303 关超时稳定带，L8）：武器 W67 木质权杖{1,16} 等级扫描制造 heal 组
--     连续变异；饰品 C2(str)/C8(int)/C20(vit+spi)/裸 制造 off/generic 变异。
--   带2（304 关阵亡带，L18）：W68 铁质权杖{17,32} + C27 珊瑚耳环{18,9999}
--     （healAmount+healBonus）拉大 heal 组变异。
--   带3（305 关阵亡带，L18）：同带2 配置换关卡，验证跨关稳定性。
-- ============================================================================

local Lab = require("tests.BattleLab")

local OUTPUT_FILE = "battle_lab_fit_healer_samples.json"
local RUNS = 10
local SEED = 926
local TIME_LIMIT = 120
local HEALER_ID = 9        -- 卡皮巴拉（牧师，ATK_HOLY）
local SATURATION_WARN = 0.65

local CASES = {}

local function addCase(label, stageId, heroLevel, slots)
    CASES[#CASES + 1] = { label = label, stageId = stageId,
        heroLevel = heroLevel, slots = slots }
end

-- 带1：303 关超时稳定带（L8）
addCase("healer303 W67@1 +C2",  303, 8, { weapon = { templateId = "W67", level = 1 },  accessory = { templateId = "C2", level = 8 } })
addCase("healer303 W67@4 +C2",  303, 8, { weapon = { templateId = "W67", level = 4 },  accessory = { templateId = "C2", level = 8 } })
addCase("healer303 W67@8 +C2",  303, 8, { weapon = { templateId = "W67", level = 8 },  accessory = { templateId = "C2", level = 8 } })
addCase("healer303 W67@12 +C2", 303, 8, { weapon = { templateId = "W67", level = 12 }, accessory = { templateId = "C2", level = 8 } })
addCase("healer303 W67@16 +C2", 303, 8, { weapon = { templateId = "W67", level = 16 }, accessory = { templateId = "C2", level = 8 } })
addCase("healer303 W67@8 +C8",  303, 8, { weapon = { templateId = "W67", level = 8 },  accessory = { templateId = "C8", level = 8 } })
addCase("healer303 W67@8 +C20", 303, 8, { weapon = { templateId = "W67", level = 8 },  accessory = { templateId = "C20", level = 8 } })
addCase("healer303 W67@8 bare", 303, 8, { weapon = { templateId = "W67", level = 8 } })
-- 带2：304 关阵亡带（L18，heal 组变异更大）
addCase("healer304 W68@17 +C27", 304, 18, { weapon = { templateId = "W68", level = 17 }, accessory = { templateId = "C27", level = 18 } })
addCase("healer304 W68@20 +C27", 304, 18, { weapon = { templateId = "W68", level = 20 }, accessory = { templateId = "C27", level = 18 } })
addCase("healer304 W68@24 +C27", 304, 18, { weapon = { templateId = "W68", level = 24 }, accessory = { templateId = "C27", level = 18 } })
addCase("healer304 W68@28 +C27", 304, 18, { weapon = { templateId = "W68", level = 28 }, accessory = { templateId = "C27", level = 18 } })
addCase("healer304 W68@32 +C27", 304, 18, { weapon = { templateId = "W68", level = 32 }, accessory = { templateId = "C27", level = 18 } })
addCase("healer304 W68@24 +C2",  304, 18, { weapon = { templateId = "W68", level = 24 }, accessory = { templateId = "C2", level = 8 } })
addCase("healer304 W68@24 +C8",  304, 18, { weapon = { templateId = "W68", level = 24 }, accessory = { templateId = "C8", level = 8 } })
addCase("healer304 W68@24 +C14", 304, 18, { weapon = { templateId = "W68", level = 24 }, accessory = { templateId = "C14", level = 8 } })
-- 带3：305 关阵亡带（L18，跨关复验）
addCase("healer305 W68@17 +C27", 305, 18, { weapon = { templateId = "W68", level = 17 }, accessory = { templateId = "C27", level = 18 } })
addCase("healer305 W68@24 +C27", 305, 18, { weapon = { templateId = "W68", level = 24 }, accessory = { templateId = "C27", level = 18 } })
addCase("healer305 W68@32 +C27", 305, 18, { weapon = { templateId = "W68", level = 32 }, accessory = { templateId = "C27", level = 18 } })
addCase("healer305 W68@24 +C2",  305, 18, { weapon = { templateId = "W68", level = 24 }, accessory = { templateId = "C2", level = 8 } })
addCase("healer305 W68@24 +C8",  305, 18, { weapon = { templateId = "W68", level = 24 }, accessory = { templateId = "C8", level = 8 } })
addCase("healer305 W68@24 bare",  305, 18, { weapon = { templateId = "W68", level = 24 } })

function Start()
    local samples = {}
    for index, case in ipairs(CASES) do
        local report, errMessage = Lab.runSingle({
            stageId = case.stageId, mode = "firstClear", runs = RUNS, seed = SEED,
            timeLimit = TIME_LIMIT,
            heroes = { { id = HEALER_ID, level = case.heroLevel } },
            loadouts = { A = { [tostring(HEALER_ID)] = case.slots }, B = {} },
        })
        assert(report, (errMessage or "unknown") .. " @" .. case.label)
        local hp = report.heroPowers[1]
        local taken = report.avgTaken
        local heal = report.avgHealing
        local ratio = taken > 0 and heal / taken or 0
        samples[#samples + 1] = {
            label = case.label, heroId = HEALER_ID, heroLevel = case.heroLevel,
            stageId = case.stageId, runs = RUNS, seed = SEED,
            category = hp.category, power = hp.power, estimate = hp.estimate,
            groups = hp.groups,
            measured = {
                avgDamage = report.avgDamage, avgHealing = heal,
                avgTaken = taken, avgSeconds = report.avgSeconds,
                winRate = report.winRate, errors = report.errors,
                healTakenRatio = ratio,
            },
        }
        print(string.format("[FitHeal] %d/%d %s hps=%.1f heal/taken=%.2f sec=%.1f win=%.0f%%%s",
            index, #CASES, case.label,
            report.avgSeconds > 0 and heal / report.avgSeconds or 0,
            ratio, report.avgSeconds, report.winRate,
            ratio >= SATURATION_WARN and "  [饱和警告]" or ""))
        assert(report.errors == 0, "样本含错误局: " .. case.label)
        assert(heal > 0, "治疗量为 0，样本无效: " .. case.label)
    end
    local file = File(OUTPUT_FILE, FILE_WRITE)
    assert(file:IsOpen(), "无法写入 " .. OUTPUT_FILE)
    file:WriteLine(cjson.encode(samples))
    file:Close()
    print("[FitHeal] 已保存 " .. OUTPUT_FILE .. "（" .. #samples .. " 组样本）")
    engine:Exit()
end
