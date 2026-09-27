-- 独立战斗实验入口：./.cli/UrhoXRuntime tests/battle_lab.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 工作区根目录放置单行 JSON battle_lab_config.json；输出 battle_lab_report.json。
-- 仅在独立 Runtime 进程运行：不加载主入口、不读存档、不发奖。
local Lab = require("tests.BattleLab")
local CONFIG_FILE = "battle_lab_config.json"
local OUTPUT_FILE = "battle_lab_report.json"

local function readConfig()
    local file = File(CONFIG_FILE, FILE_READ)
    if not file:IsOpen() then
        local default = {
            stageId = 101, mode = "firstClear", runs = 20, seed = 926,
            timeLimit = 300,
            heroes = { { id = 1, level = 1 }, { id = 3, level = 1 }, { id = 2, level = 1 } },
        }
        print("[BattleLab] 未找到 " .. CONFIG_FILE .. "，使用默认第1关配置")
        return default
    end
    local text = file:ReadLine()
    file:Close()
    return cjson.decode(text)
end

local function writeReport(report)
    local text = cjson.encode(report)
    local file = File(OUTPUT_FILE, FILE_WRITE)
    assert(file:IsOpen(), "无法写入报告 " .. OUTPUT_FILE)
    file:WriteLine(text)
    file:Close()
    print("[BattleLab] 已保存 " .. OUTPUT_FILE)
    print("[BattleLab][REPORT] " .. text)
end

function Start()
    local ok, err = xpcall(function()
        local config = readConfig()
        local report, message = Lab.run(config, function(done, total, battle)
            if done == 1 or done == total or done % 10 == 0 then
                print(string.format("[BattleLab] %d/%d seed=%d %s %.1fs %d/%d",
                    done, total, battle.seed, battle.outcome, battle.seconds, battle.kills, battle.monsters))
            end
        end)
        assert(report, message)
        print(string.format("[BattleLab] %s #%d: %d/%d 胜(%.1f%%) 负%d 超时%d 平均%.1fs",
            report.stageName, report.stageId, report.wins, report.completedRuns,
            report.winRate, report.losses, report.timeouts, report.avgSeconds))
        for _, stat in ipairs(report.heroStats) do
            print(string.format("[BattleLab] %s: 场均输出 %.0f 治疗 %.0f 承伤 %.0f 暴击 %.1f%%",
                stat.name, stat.avgDamage, stat.avgHealing, stat.avgTaken, stat.critRate))
        end
        writeReport(report)
    end, debug.traceback)
    if not ok then
        print("[BattleLab] ERROR: " .. tostring(err))
        error(err)
    end
    engine:Exit()
end
