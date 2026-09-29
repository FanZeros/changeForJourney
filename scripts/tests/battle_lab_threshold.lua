-- ============================================================================
-- battle_lab_threshold.lua — 关卡推荐战力采样器（独立 Runtime 进程）
-- 跑法: ./.cli/UrhoXRuntime tests/battle_lab_threshold.lua -tapcode_dir=<项目根> -tool_mode -graphicsheadless
-- 输出: 项目根 battle_lab_threshold_samples.json（gitignore），
--       交 scripts/_proc/fit_stage_recommend.py 拟合推荐战力曲线。
--
-- 口径（与 docs/memory-index.md 约定一致）：
--   * 基准队伍 = 剧情开荒三人组：大狗嚼(1)/黄桃龙(2)/叮咚鸡(3)，无装备
--     无遗物/神器/觉醒/星图，全员同等级 L（模拟裸练级推进的玩家）。
--   * 首通模式（含地图词缀与狂暴）= 玩家推图的实际体验；12 局固定种子。
--   * 阈值 = winRate 跨过 50% 的英雄等级 L*（胜率随 L 单调，二分定位），
--     记录 L* 处的官方 teamPower 与分项预估 teamEstimate 双口径。
--   * [触底细化 0929] 首探即胜时下探必须实测到 L1（原实现 lo 默认 1 从未实测，
--     早期章节记录的是"裸队恰好拥有的战力"而非"打赢所需战力"——下限伪值）。
--     三人组 L1 仍 ≥50% 胜率时（测量下限触底），减员细化：依次实测 2人L1/1人L1，
--     阈值取最小可胜配置的 teamPower（threshold.floor=true, teamSize 记录人数）。
--   * 关卡采样 = Normal + Hard 难度各 23 个章节的首关（monsterLevel 1..46
--     全覆盖，v2.63 扩展 Hard）。章节内 1-5 关的差异（怪物数量 firstCount
--     递增）由生成器的章内插值梯度吸收。
--
-- 二分策略：初始猜测 L0 = max(1, ml)，若胜率<50% 则按 +4 步长上探
-- （上限 MAX_HERO_LEVEL=345），找到 [lo,hi] 括住 50% 后二分
-- 到区间宽度 ≤1，取 hi（保守推荐：保证 ≥50% 胜率的一侧）。
-- ============================================================================

local Lab = require("tests.BattleLab")
local SC = require("config.StageConfig")

local OUTPUT_FILE = "battle_lab_threshold_samples.json"
-- [断点续跑 0929] 采样进程可能被外部环境终止；每章完成即落盘 checkpoint，
-- 重启时跳过已有样本，避免 50min 全量重跑因中断丢失全部进度
local function writeCheckpoint(samples)
    local f = File(OUTPUT_FILE, FILE_WRITE)
    if f:IsOpen() then
        f:WriteLine(cjson.encode(samples))
        f:Close()
    end
end
--- 读取断点：返回 (已完成 stageId 集合, 已有样本数组)
--- 样本数组作为本次 samples 初值，确保续跑落盘时不丢失已完成章节
local function loadCheckpoint()
    local f = File(OUTPUT_FILE, FILE_READ)
    if not f:IsOpen() then return {}, {} end
    local content = f:ReadString()
    f:Close()
    local ok, data = pcall(cjson.decode, content)
    if not ok or type(data) ~= "table" then return {}, {} end
    local done, existing = {}, {}
    for _, s in ipairs(data) do
        if s.stageId then
            done[tostring(s.stageId)] = true
            existing[#existing + 1] = s
        end
    end
    return done, existing
end
local RUNS = 12
local SEED = 926
local TIME_LIMIT = 120
local MAX_HERO_LEVEL = 345
local BASE_TEAM = { 1, 2, 3 }   -- 开荒三人组

-- Normal 23 章首关（ml 1..23）+ Hard 23 章首关（ml 24..46，v2.63）
local STAGES = {
    101, 201, 301, 401, 501, 601, 701, 801, 901, 1001,
    1101, 1201, 1301, 1401, 1501, 1601, 1701, 1801, 1901, 2001,
    2101, 2201, 2301,
    2401, 2501, 2601, 2701, 2801, 2901, 3001, 3101, 3201, 3301,
    3401, 3501, 3601, 3701, 3801, 3901, 4001, 4101, 4201, 4301,
    4401, 4501, 4601,
}

--- 在指定关卡以全员等级 level 跑一局批量测试，返回报告摘要
--- teamIds: 可选自定义队伍（缺省开荒三人组）；用于触底减员细化
local function measure(stageId, level, teamIds)
    local heroes = {}
    for _, id in ipairs(teamIds or BASE_TEAM) do
        heroes[#heroes + 1] = { id = id, level = level }
    end
    local report, errMessage = Lab.runSingle({
        stageId = stageId, mode = "firstClear", runs = RUNS, seed = SEED,
        timeLimit = TIME_LIMIT, heroes = heroes,
    })
    assert(report, (errMessage or "unknown") .. " @stage" .. stageId .. " L" .. level)
    assert(report.errors == 0, "样本含错误局 @stage" .. stageId .. " L" .. level)
    return {
        level = level, teamPower = report.teamPower,
        teamEstimate = report.teamEstimate or 0,
        winRate = report.winRate, wins = report.wins, runs = report.completedRuns,
        avgSeconds = report.avgSeconds, timeouts = report.timeouts,
        heroPowers = report.heroPowers,
    }
end

function Start()
    local doneStages, samples = loadCheckpoint()
    local nDone = 0
    for _ in pairs(doneStages) do nDone = nDone + 1 end
    if nDone > 0 then
        print(string.format("[Threshold] 断点续跑：已有 %d 章样本，将跳过", nDone))
    end
    for stageIndex, stageId in ipairs(STAGES) do
        if doneStages[tostring(stageId)] then
            goto continue_stage
        end
        local stage = SC.getStage(stageId)
        assert(stage, "未知关卡 " .. stageId)
        local ml = stage.monsterLevel

        -- 1) 初始猜测（自然节奏：英雄等级=怪物等级）+ 上探找到胜率 ≥50% 的 hi
        local guess = math.max(1, ml)
        local loSample, hiSample = nil, nil
        local level = guess
        local probes = {}
        while level <= MAX_HERO_LEVEL do
            local sample = measure(stageId, level)
            probes[#probes + 1] = sample
            print(string.format("[Threshold] %d/%d stage=%d ml=%d L=%d power=%d win=%.0f%%",
                stageIndex, #STAGES, stageId, ml, level, sample.teamPower, sample.winRate))
            if sample.winRate >= 50 then
                hiSample = sample
                break
            end
            loSample = sample
            level = level + 4
        end
        if not hiSample then
            print(string.format("[Threshold][WARN] stage=%d 到 L%d 仍无 50%% 胜率，跳过",
                stageId, MAX_HERO_LEVEL))
            samples[#samples + 1] = { stageId = stageId, monsterLevel = ml,
                stageInChapter = 1, threshold = nil, probes = probes,
                note = "L345 内无 50% 胜率点" }
        else
            -- 1.5) [触底细化 0929] 首探即胜（loSample 缺失）时，先实测 L1：
            --      原实现 lo 默认 1 但从未实测，L1 实际能赢的章节被记成 L=guess 的
            --      队伍战力（下限伪值，如 201 记 L2=336 而 L1=318 已 100% 胜）。
            if not loSample and hiSample.level > 1 then
                local l1 = measure(stageId, 1)
                probes[#probes + 1] = l1
                print(string.format("[Threshold] %d/%d stage=%d ml=%d L=1 power=%d win=%.0f%% (floor probe)",
                    stageIndex, #STAGES, stageId, ml, l1.teamPower, l1.winRate))
                if l1.winRate >= 50 then
                    hiSample = l1
                else
                    loSample = l1
                end
            end
            -- 2) 二分收窄 [lo, hi]（lo 胜率<50，hi 胜率≥50）
            local lo = loSample and loSample.level or 1
            local hi = hiSample.level
            while hi - lo > 1 do
                local mid = math.floor((lo + hi) / 2)
                local sample = measure(stageId, mid)
                probes[#probes + 1] = sample
                print(string.format("[Threshold] %d/%d stage=%d bisect L=%d power=%d win=%.0f%%",
                    stageIndex, #STAGES, stageId, mid, sample.teamPower, sample.winRate))
                if sample.winRate >= 50 then
                    hi, hiSample = mid, sample
                else
                    lo, loSample = mid, sample
                end
            end
            -- 2.5) [触底细化 0929] 三人组 L1 即 ≥50% 胜率 = 测量下限触底，
            --      减员实测 2人L1/1人L1，阈值取最小可胜配置（人数/战力记入 threshold）
            local threshold = {
                level = hi, teamPower = hiSample.teamPower,
                teamEstimate = hiSample.teamEstimate,
                winRate = hiSample.winRate, avgSeconds = hiSample.avgSeconds,
                loLevel = lo, loPower = loSample and loSample.teamPower or 0,
                loWinRate = loSample and loSample.winRate or 0,
                teamSize = #BASE_TEAM, floor = false,
            }
            if hi == 1 then
                threshold.floor = true
                local REDUCED_TEAMS = { { 1, 2 }, { 1 } }
                for _, team in ipairs(REDUCED_TEAMS) do
                    local sample = measure(stageId, 1, team)
                    probes[#probes + 1] = sample
                    print(string.format("[Threshold] %d/%d stage=%d ml=%d L=1 size=%d power=%d win=%.0f%% (reduce probe)",
                        stageIndex, #STAGES, stageId, ml, #team, sample.teamPower, sample.winRate))
                    if sample.winRate >= 50 and sample.teamPower < threshold.teamPower then
                        threshold.level = 1
                        threshold.teamPower = sample.teamPower
                        threshold.teamEstimate = sample.teamEstimate
                        threshold.winRate = sample.winRate
                        threshold.avgSeconds = sample.avgSeconds
                        threshold.teamSize = #team
                    end
                end
            end
            samples[#samples + 1] = {
                stageId = stageId, monsterLevel = ml, stageInChapter = 1,
                threshold = threshold,
                probes = probes,
            }
            print(string.format("[Threshold] ✔ stage=%d ml=%d 阈值 L=%d size=%d 官方战力=%d 预估=%d floor=%s (lo L=%d win=%.0f%%)",
                stageId, ml, threshold.level, threshold.teamSize, threshold.teamPower,
                threshold.teamEstimate, tostring(threshold.floor), lo,
                loSample and loSample.winRate or 0))
        end
        writeCheckpoint(samples)  -- [断点续跑 0929] 每章落盘
        ::continue_stage::
    end

    local file = File(OUTPUT_FILE, FILE_WRITE)
    assert(file:IsOpen(), "无法写入 " .. OUTPUT_FILE)
    file:WriteLine(cjson.encode(samples))
    file:Close()
    print("[Threshold] 已保存 " .. OUTPUT_FILE .. "（" .. #samples .. " 个关卡）")
    engine:Exit()
end
