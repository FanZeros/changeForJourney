-- ============================================================================
-- battle_lab_fit.lua — 分项计价系数拟合采样器（独立 Runtime 进程）
-- 跑法: ./.cli/UrhoXRuntime tests/battle_lab_fit.lua -tapcode_dir=<项目根> -tool_mode -graphicsheadless
-- 输出: 项目根 battle_lab_fit_samples.json（单行 JSON 数组，被 .gitignore 忽略），
--       交给 scripts/_proc/fit_power_estimate.py 做最小二乘回归。
--
-- 采样设计：
--   * 全部样本取「战败关」（大狗嚼 Lv8/303 一侧全败的难度带），伤害/治疗不饱和，
--     才有回归价值；饱和样本（全胜时伤害=怪物总血量）对拟合无信息量。
--   * 每个英雄用武器等级（levelRange {1,16} 内 Lv1/8/16，属性按 5%/级缩放）
--     制造本系属性的连续变化，用异系饰品（C8 int / C2 str / C20 vit+spi）
--     制造异系与通用组的变化。
--   * 每组 runs=10（拟合看场均值，不需要 40 局的胜率精度）。
-- ============================================================================

local Lab = require("tests.BattleLab")

local OUTPUT_FILE = "battle_lab_fit_samples.json"
local STAGE = 303          -- 哑雾沼泽3-3：Lv8 单英雄全败难度带
local RUNS = 10
local SEED = 926
local TIME_LIMIT = 120

-- 英雄 × 配装矩阵（模板等级全部在 levelRange 内）
-- W1 单手剑{1,16} W13 单手斧{1,16} W25 法杖{1,16} W31 魔杖{1,16}
-- W37 弓箭{1,16} W43 单手弩{1,16} W67 权杖{1,16}
-- C2 力量戒{8,9999} C8 智力戒{8,9999} C20 黄玉挂坠{8,9999}(vit+spi)
local CASES = {}

local function addCase(label, heroId, heroLevel, slots)
    CASES[#CASES + 1] = { label = label, heroId = heroId, heroLevel = heroLevel, slots = slots }
end

-- 战士（大狗嚼 id=1，physical）：本系=phys
addCase("warrior W1@1 +C2",   1, 8, { weapon = { templateId = "W1", level = 1 },  accessory = { templateId = "C2", level = 8 } })
addCase("warrior W1@8 +C2",   1, 8, { weapon = { templateId = "W1", level = 8 },  accessory = { templateId = "C2", level = 8 } })
addCase("warrior W1@16 +C2",  1, 8, { weapon = { templateId = "W1", level = 16 }, accessory = { templateId = "C2", level = 8 } })
addCase("warrior W13@8 +C2",  1, 8, { weapon = { templateId = "W13", level = 8 }, accessory = { templateId = "C2", level = 8 } })
addCase("warrior W1@8 +C8",   1, 8, { weapon = { templateId = "W1", level = 8 },  accessory = { templateId = "C8", level = 8 } })
addCase("warrior W1@8 +C20",  1, 8, { weapon = { templateId = "W1", level = 8 },  accessory = { templateId = "C20", level = 8 } })
addCase("warrior W1@8 bare",  1, 8, { weapon = { templateId = "W1", level = 8 } })
-- 法师（黄桃龙 id=2，magical）：本系=mag
addCase("mage W25@1 +C8",     2, 8, { weapon = { templateId = "W25", level = 1 },  accessory = { templateId = "C8", level = 8 } })
addCase("mage W25@8 +C8",     2, 8, { weapon = { templateId = "W25", level = 8 },  accessory = { templateId = "C8", level = 8 } })
addCase("mage W25@16 +C8",    2, 8, { weapon = { templateId = "W25", level = 16 }, accessory = { templateId = "C8", level = 8 } })
addCase("mage W31@8 +C8",     2, 8, { weapon = { templateId = "W31", level = 8 },  accessory = { templateId = "C8", level = 8 } })
addCase("mage W25@8 +C2",     2, 8, { weapon = { templateId = "W25", level = 8 },  accessory = { templateId = "C2", level = 8 } })
addCase("mage W25@8 +C20",    2, 8, { weapon = { templateId = "W25", level = 8 },  accessory = { templateId = "C20", level = 8 } })
addCase("mage W25@8 bare",    2, 8, { weapon = { templateId = "W25", level = 8 } })
-- 游侠（叮咚鸡 id=3，physical pierce）：本系=phys
addCase("ranger W37@1 +C2",   3, 8, { weapon = { templateId = "W37", level = 1 },  accessory = { templateId = "C2", level = 8 } })
addCase("ranger W37@8 +C2",   3, 8, { weapon = { templateId = "W37", level = 8 },  accessory = { templateId = "C2", level = 8 } })
addCase("ranger W37@16 +C2",  3, 8, { weapon = { templateId = "W37", level = 16 }, accessory = { templateId = "C2", level = 8 } })
addCase("ranger W43@8 +C2",   3, 8, { weapon = { templateId = "W43", level = 8 },  accessory = { templateId = "C2", level = 8 } })
addCase("ranger W37@8 +C8",   3, 8, { weapon = { templateId = "W37", level = 8 },  accessory = { templateId = "C8", level = 8 } })
addCase("ranger W37@8 +C20",  3, 8, { weapon = { templateId = "W37", level = 8 },  accessory = { templateId = "C20", level = 8 } })
addCase("ranger W37@8 bare",  3, 8, { weapon = { templateId = "W37", level = 8 } })
-- 牧师（卡皮巴拉 id=9，healing）：本系=heal
addCase("healer W67@1 +C2",   9, 8, { weapon = { templateId = "W67", level = 1 },  accessory = { templateId = "C2", level = 8 } })
addCase("healer W67@8 +C2",   9, 8, { weapon = { templateId = "W67", level = 8 },  accessory = { templateId = "C2", level = 8 } })
addCase("healer W67@16 +C2",  9, 8, { weapon = { templateId = "W67", level = 16 }, accessory = { templateId = "C2", level = 8 } })
addCase("healer W67@8 +C8",   9, 8, { weapon = { templateId = "W67", level = 8 },  accessory = { templateId = "C8", level = 8 } })
addCase("healer W67@8 +C20",  9, 8, { weapon = { templateId = "W67", level = 8 },  accessory = { templateId = "C20", level = 8 } })
addCase("healer W67@8 bare",  9, 8, { weapon = { templateId = "W67", level = 8 } })
-- 高等级带（Lv14，同关更深败局）：加大属性跨度
addCase("warrior W1@14 +C2 L14", 1, 14, { weapon = { templateId = "W1", level = 14 }, accessory = { templateId = "C2", level = 8 } })
addCase("mage W25@14 +C8 L14",   2, 14, { weapon = { templateId = "W25", level = 14 }, accessory = { templateId = "C8", level = 8 } })
addCase("ranger W37@14 +C2 L14", 3, 14, { weapon = { templateId = "W37", level = 14 }, accessory = { templateId = "C2", level = 8 } })
addCase("healer W67@14 +C2 L14", 9, 14, { weapon = { templateId = "W67", level = 14 }, accessory = { templateId = "C2", level = 8 } })

function Start()
    local samples = {}
    for index, case in ipairs(CASES) do
        -- 单方案入口：拟合只用一套配装，不走 Lab.run 的 A/B 双跑路径
        local report, errMessage = Lab.runSingle({
            stageId = STAGE, mode = "firstClear", runs = RUNS, seed = SEED,
            timeLimit = TIME_LIMIT,
            heroes = { { id = case.heroId, level = case.heroLevel } },
            loadouts = { A = { [tostring(case.heroId)] = case.slots }, B = {} },
        })
        assert(report, (errMessage or "unknown") .. " @" .. case.label)
        local hp = report.heroPowers[1]
        samples[#samples + 1] = {
            label = case.label, heroId = case.heroId, heroLevel = case.heroLevel,
            stageId = STAGE, runs = RUNS, seed = SEED,
            category = hp.category, power = hp.power, estimate = hp.estimate,
            groups = hp.groups,
            measured = {
                avgDamage = report.avgDamage, avgHealing = report.avgHealing,
                avgTaken = report.avgTaken, avgSeconds = report.avgSeconds,
                winRate = report.winRate, errors = report.errors,
            },
        }
        print(string.format("[Fit] %d/%d %s cat=%s dmg=%.1f heal=%.1f taken=%.1f sec=%.1f win=%.0f%%",
            index, #CASES, case.label, hp.category, report.avgDamage, report.avgHealing,
            report.avgTaken, report.avgSeconds, report.winRate))
        assert(report.errors == 0, "样本含错误局: " .. case.label)
        -- 战败关校验：饱和（全胜）样本对伤害回归无信息量，直接报警
        if report.winRate >= 100 then
            print("[Fit][WARN] 样本全胜，伤害饱和: " .. case.label)
        end
    end
    local file = File(OUTPUT_FILE, FILE_WRITE)
    assert(file:IsOpen(), "无法写入 " .. OUTPUT_FILE)
    file:WriteLine(cjson.encode(samples))
    file:Close()
    print("[Fit] 已保存 " .. OUTPUT_FILE .. "（" .. #samples .. " 组样本）")
    engine:Exit()
end
