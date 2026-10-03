-- ============================================================================
-- scenario82_firstclear_test.lua — 首通情景接线修复回归（2026-10-01）
-- 背景：0922 删除 Client/Server 联网壳（4e184304）时，首通触发情景的接线
--   （原 ClientBoot.setOnFirstClear 里 lastClearedStageId_ + NEXT_STAGE）没搬进单机版，
--   导致所有"首通触发"情景（含情景82 大狗嚼碎片引导）在单机永不入队/播放。
--   且 13df6a95 起客户端播放前预写 claimedScenarios，单机 PDM 与客户端共享同一
--   张表 → 播完领奖被"已领取"拦截。
-- 修复：
--   1) StandaloneBoot.setOnFirstClear 直接调 StoryPlayer.onStage(id,"clear") 补接线
--   2) StoryPlayer.backfillCleared() 旧档补播（已首通未领的情景重新入队）
--   3) ClaimScenarioReward 增 preClaimed 参数 + scenarioRewardsGranted 独立防刷账本
-- 验证：
--   1) backfillCleared 把已首通 205 的情景 82 补入队，take 能取到
--   2) preClaimed=true 领奖：在 claimed 已预标记下仍成功发 10 碎片
--   3) 无 preClaimed 且已 claimed → 拒绝（证明预标记必须配 preClaimed）
--   4) 重复领取被 scenarioRewardsGranted 账本拒绝（preClaimed 也无法刷第二次）
--   5) 关卡未通关时领取失败不记账 → 补通关后可重试成功
-- 跑法: /workspace/.cli/UrhoXRuntime tests/scenario82_firstclear_test.lua \
--         -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local PREFIX = "[scenario82] "
local failures = {}
local function check(cond, msg)
    if cond then print(PREFIX .. "[PASS] " .. msg)
    else print(PREFIX .. "[FAIL] " .. msg); failures[#failures + 1] = msg end
end
local function eq(actual, expected, msg)
    check(actual == expected, msg .. " (实际=" .. tostring(actual) .. " 期望=" .. tostring(expected) .. ")")
end

-- ======================== 加载真实模块 + 覆盖数据源 ========================
-- 沿用 corrupt_convert_test 模式：require 真实服务，覆盖 PDM/ClientDispatcher 的
-- 数据方法指向测试 modules 表（引擎 require 返回单例，覆盖对所有引用者生效）。

local PDM = require("rules.character.PlayerDataManager")
local ClientDispatcher = require("runtime.ClientDispatcher")
local StoryPlayer = require("systems.StoryPlayer")
local okBS, BS = pcall(require, "rules.battle.BattleService")
if not okBS then
    print(PREFIX .. "RESULT FAIL — cannot require BattleService: " .. tostring(BS))
    engine:Exit()
    return
end

---@type table<string, table>
local modules = {}
PDM.GetModule = function(_, name) return modules[name] end
PDM.MarkDirty = function() end
PDM.FlushImmediate = function() end
ClientDispatcher.get = function(name) return modules[name] end

local UID = 1

--- 重置数据源。clearedStages/claimed/granted/shards 由各用例指定
---@param opts table { cleared205?:boolean, claimed82?:boolean, shards?:integer }
local function resetModules(opts)
    opts = opts or {}
    modules.session = {
        introCompleted = true,
        initialHeroId = 1,
        claimedScenarios = opts.claimed82 and { ["82"] = true } or {},
        scenarioRewardsGranted = {},
    }
    modules.battle = {
        clearedStages = (opts.cleared205 ~= false) and { ["205"] = true } or {},
        maxStageId = 205,
        currentStageId = 205,
    }
    modules.heroes = { roster = { [1] = { level = 1, shards = opts.shards or 0 } } }
    modules.currency = {}
end

local function shardsOf(heroId)
    local h = modules.heroes.roster[heroId]
    return h and h.shards or 0
end
local function grantedOf(id)
    return modules.session.scenarioRewardsGranted[tostring(id)] == true
end

-- ======================== 用例 ========================

function Start()
    print(PREFIX .. "start")

    local config = require("config.ScenarioDialogueConfig")
    local awakening = require("config.AwakeningConfig")
    eq(config.SCENARIO_82.rewards[1].amount, 10, "剧情展示配置为10碎片")
    eq(awakening.getShardCost(1), 10, "首次觉醒仍消耗10碎片")

    -- 用例1：旧档补播——已首通 205，情景 82 未领 → backfillCleared 补入队，take 能取到
    resetModules({ cleared205 = true })
    local added = StoryPlayer.backfillCleared()
    check(added >= 1, "用例1: backfillCleared 补入队 (added=" .. tostring(added) .. ")")
    local found82 = false
    local guard = 0
    while guard < 50 do
        guard = guard + 1
        local pending = StoryPlayer.take()
        if not pending then break end
        if pending.scenarioId == 82 then found82 = true end
    end
    check(found82, "用例1: 补播队列含情景82（首通205大狗嚼引导）")

    -- 用例2：preClaimed=true 领奖——claimed[82] 已预标记（模拟客户端播放前预写），
    --   关卡已通 → 仍应成功发 10 碎片（旧代码此处会被"已领取"拒绝）
    resetModules({ cleared205 = true, claimed82 = true, shards = 0 })
    local ok2, err2, res2 = BS.ClaimScenarioReward(UID, 82, true)
    check(ok2, "用例2: preClaimed=true 领奖成功: " .. tostring(err2))
    eq(res2 and res2.rewardType, "shard", "用例2: 奖励类型 shard")
    eq(res2 and res2.reward and res2.reward.amount, 10, "用例2: 奖励回包数量10")
    eq(shardsOf(1), 10, "用例2: 大狗嚼碎片 +10")
    check(grantedOf(82), "用例2: scenarioRewardsGranted 记账")

    -- 用例3：无 preClaimed 且已 claimed → 拒绝（证明预标记场景必须带 preClaimed）
    resetModules({ cleared205 = true, claimed82 = true, shards = 0 })
    local ok3, err3 = BS.ClaimScenarioReward(UID, 82, nil)
    check(not ok3, "用例3: 无 preClaimed 且已 claimed 被拒: " .. tostring(err3))
    eq(shardsOf(1), 0, "用例3: 未发碎片")

    -- 用例4：重复领取被账本拒绝（接用例2 已发放状态，再带 preClaimed 也刷不动）
    resetModules({ cleared205 = true, claimed82 = true, shards = 0 })
    BS.ClaimScenarioReward(UID, 82, true)   -- 第一次发放（shards→10, granted[82]=true）
    local ok4, err4 = BS.ClaimScenarioReward(UID, 82, true)
    check(not ok4, "用例4: 重复领取（即便 preClaimed）被账本拒绝: " .. tostring(err4))
    eq(shardsOf(1), 10, "用例4: 碎片仍为10（未重复发放）")

    -- 用例5：关卡未通关 → 领取失败且不记账；补通关后可重试成功
    resetModules({ cleared205 = false, shards = 0 })
    local ok5a, err5a = BS.ClaimScenarioReward(UID, 82, true)
    check(not ok5a, "用例5a: 未通关205 领取失败: " .. tostring(err5a))
    check(not grantedOf(82), "用例5a: 失败未记账（granted 空，可重试）")
    modules.battle.clearedStages["205"] = true   -- 补通关
    local ok5b, err5b = BS.ClaimScenarioReward(UID, 82, true)
    check(ok5b, "用例5b: 补通关后重试成功: " .. tostring(err5b))
    eq(shardsOf(1), 10, "用例5b: 重试发放 10 碎片")
    check(grantedOf(82), "用例5b: 成功后记账")

    if #failures == 0 then
        print(PREFIX .. "RESULT ALL PASS")
    else
        print(PREFIX .. "RESULT " .. #failures .. " FAIL")
    end
    engine:Exit()
end
