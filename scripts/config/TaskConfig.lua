-- ============================================================================
-- TaskConfig - 任务系统配置（日任务/周任务/成就）
-- 双端共享：服务端用于校验 & 发放奖励，客户端用于 UI 显示
-- 数据来源: docs/运营配置/运营-任务.txt
-- ============================================================================

local TaskConfig = {}

-- ======================== 任务状态枚举 ========================

TaskConfig.STATUS = {
    LOCKED    = "locked",     -- 未满足条件
    CLAIMABLE = "claimable",  -- 可领取
    CLAIMED   = "claimed",    -- 已领取
}

-- ======================== 奖励 type → currency 字段映射 ========================
-- 复用 SignInConfig 的映射规则

TaskConfig.REWARD_TO_CURRENCY = {
    diamond           = "gems",
    gold              = "gold",
    adventure_ticket  = "recruitTicket",
    stellar_ticket    = "stellarRecruitTicket",
    golden_key        = "goldenKey",
    corrupt_stone     = "corruptStone",
    sacred_stone      = "sacredStone",
    privilege_point   = "privilegePoint",
}

-- ======================== 时间工具（复用 SignInConfig 规则） ========================

--- 获取当天编号（UTC+8，自 epoch 以来的天数）
function TaskConfig.getDayNumber()
    return math.floor((os.time() + 28800) / 86400)
end

--- 获取当前周编号（UTC+8，周一起始）
function TaskConfig.getWeekNumber()
    return math.floor((os.time() + 28800 + 3 * 86400) / (7 * 86400))
end

-- ======================== 通关任务（名字 / 描述 / 指定关卡） ========================

TaskConfig.DAILY = {}
TaskConfig.WEEKLY = {}
TaskConfig.ACHIEVEMENT = {}

local StageConfig = require("config.StageConfig")

local function gem(amount)
    return { type = "diamond", amount = amount, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 }
end

local function addClear(stageId, difficulty, amount)
    local entry = StageConfig.getStage(stageId)
    if not entry then return end
    local label = StageConfig.formatProgressDisplay(stageId)
    local place = StageConfig.getChapterName(entry.chapter or 0)
    if not place or place == "" then place = label end
    TaskConfig.ACHIEVEMENT[#TaskConfig.ACHIEVEMENT + 1] = {
        id = "a_clear_" .. tostring(stageId),
        name = place,
        desc = "通关" .. label,
        condKey = "clear_" .. tostring(stageId),
        stageId = stageId,
        difficulty = difficulty,
        target = 1,
        reward = gem(amount),
    }
end

local function addBosses(range, difficulty, baseAmount)
    local index = 0
    for chapter = range.first, range.last do
        index = index + 1
        addClear(chapter * 100 + 5, difficulty, baseAmount + index * 40)
    end
end

for stage = 1, 4 do
    addClear(100 + stage, "normal", 60 + stage * 20)
end
addBosses(StageConfig.NORMAL_CHAPTERS, "normal", 120)
addBosses(StageConfig.HARD_CHAPTERS, "hard", 400)
addBosses(StageConfig.NIGHTMARE_CHAPTERS, "nightmare", 800)

-- ======================== 按 ID 快速查找 ========================

TaskConfig._byId = {}

local function buildIndex()
    for _, list in ipairs({ TaskConfig.DAILY, TaskConfig.WEEKLY, TaskConfig.ACHIEVEMENT }) do
        for _, task in ipairs(list) do
            TaskConfig._byId[task.id] = task
        end
    end
end
buildIndex()

--- 按 ID 查找任务定义
---@param taskId string
---@return table|nil
function TaskConfig.findById(taskId)
    return TaskConfig._byId[taskId]
end

--- 获取任务类别（"daily"/"weekly"/"achievement"）
---@param taskId string
---@return string|nil
function TaskConfig.getCategory(taskId)
    if taskId:sub(1, 2) == "d_" then return "daily" end
    if taskId:sub(1, 2) == "w_" then return "weekly" end
    if taskId:sub(1, 2) == "a_" then return "achievement" end
    return nil
end

return TaskConfig
