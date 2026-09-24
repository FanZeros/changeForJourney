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

-- ======================== 日任务：签到 / 关卡 / 在线 ========================

TaskConfig.DAILY = {
    { id = "d_login", name = "登录游戏", condKey = "login", target = 1,
      reward = { type = "diamond", amount = 100, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "d_signin", name = "完成今日签到", condKey = "signin", target = 1,
      reward = { type = "diamond", amount = 150, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "d_stage_1", name = "推进1关", condKey = "stage_clear", target = 1,
      reward = { type = "diamond", amount = 120, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "d_stage_3", name = "推进3关", condKey = "stage_clear", target = 3,
      reward = { type = "diamond", amount = 240, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "d_stage_5", name = "推进5关", condKey = "stage_clear", target = 5,
      reward = { type = "diamond", amount = 400, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "d_online_20", name = "在线20分钟", condKey = "online_min", target = 20,
      reward = { type = "diamond", amount = 150, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "d_online_40", name = "在线40分钟", condKey = "online_min", target = 40,
      reward = { type = "diamond", amount = 250, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "d_online_60", name = "在线60分钟", condKey = "online_min", target = 60,
      reward = { type = "diamond", amount = 400, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
}

-- ======================== 周任务：签到 / 关卡 / 在线 ========================

TaskConfig.WEEKLY = {
    { id = "w_login_3", name = "累计登录3日", condKey = "login_days", target = 3,
      reward = { type = "diamond", amount = 300, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "w_login_7", name = "累计登录7日", condKey = "login_days", target = 7,
      reward = { type = "diamond", amount = 800, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "w_signin_5", name = "本周签到5次", condKey = "signin", target = 5,
      reward = { type = "diamond", amount = 500, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "w_stage_10", name = "本周推进10关", condKey = "stage_clear", target = 10,
      reward = { type = "diamond", amount = 600, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "w_stage_30", name = "本周推进30关", condKey = "stage_clear", target = 30,
      reward = { type = "diamond", amount = 1200, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "w_online_180", name = "本周在线3小时", condKey = "online_min", target = 180,
      reward = { type = "diamond", amount = 800, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
}

-- ======================== 成就：关卡推进 ========================

TaskConfig.ACHIEVEMENT = {
    { id = "a_stage_10", name = "累计推进10关", condKey = "stage_count", target = 10,
      reward = { type = "diamond", amount = 200, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "a_stage_30", name = "累计推进30关", condKey = "stage_count", target = 30,
      reward = { type = "diamond", amount = 400, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "a_stage_60", name = "累计推进60关", condKey = "stage_count", target = 60,
      reward = { type = "diamond", amount = 800, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "a_stage_100", name = "累计推进100关", condKey = "stage_count", target = 100,
      reward = { type = "diamond", amount = 1500, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "a_reach_505", name = "到达普通5-5", condKey = "max_stage", target = 505,
      reward = { type = "diamond", amount = 300, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "a_reach_1005", name = "到达普通10-5", condKey = "max_stage", target = 1005,
      reward = { type = "diamond", amount = 600, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
    { id = "a_reach_2305", name = "到达普通终焉前", condKey = "max_stage", target = 2305,
      reward = { type = "diamond", amount = 2000, icon = "image/货币道具/UI_icon_SJ.png", quality = 5 } },
}

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
