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
    arena_coin        = "arenaCoin",
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

-- ======================== 日任务定义（10 条） ========================

TaskConfig.DAILY = {
    {
        id = "d_login",
        name = "登录游戏",
        condKey = "login",          -- 进度追踪 key
        target = 1,
        reward = { type = "diamond", amount = 282, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "d_recruit_1",
        name = "进行1次招募",
        condKey = "recruit",
        target = 1,
        reward = { type = "adventure_ticket", amount = 1, icon = "image/UI_icon_ZMQ_1.png", quality = 5 },
    },
    {
        id = "d_stellar_recruit_3",
        name = "进行3次星辉招募",
        condKey = "stellar_recruit",
        target = 3,
        reward = { type = "stellar_ticket", amount = 1, icon = "image/UI_icon_ZMQ_2.png", quality = 6 },
    },
    {
        id = "d_artifact_draw_3",
        name = "进行3次神器抽取",
        condKey = "artifact_draw",
        target = 3,
        reward = { type = "golden_key", amount = 1, icon = "image/UI_icon_HJYS.png", quality = 6 },
    },
    {
        id = "d_ad_1",
        name = "观看1次广告",
        condKey = "watch_ad",
        target = 1,
        reward = { type = "privilege_point", amount = 1, icon = "image/UI_icon_TQD.png", quality = 4 },
    },
    {
        id = "d_decompose_20",
        name = "分解20件装备",
        condKey = "decompose",
        target = 20,
        reward = { type = "diamond", amount = 282, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "d_enhance_3",
        name = "强化3次装备",
        condKey = "enhance",
        target = 3,
        reward = { type = "diamond", amount = 282, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "d_refine_10",
        name = "洗练10次装备",
        condKey = "refine",
        target = 10,
        reward = { type = "diamond", amount = 282, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "d_online_20",
        name = "在线20分钟",
        condKey = "online_min",
        target = 20,
        reward = { type = "diamond", amount = 282, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "d_online_40",
        name = "在线40分钟",
        condKey = "online_min",
        target = 40,
        reward = { type = "diamond", amount = 432, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "d_online_60",
        name = "在线60分钟",
        condKey = "online_min",
        target = 60,
        reward = { type = "diamond", amount = 582, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "d_arena_3",
        name = "参加3次竞技场",
        condKey = "arena",
        target = 3,
        reward = { type = "arena_coin", amount = 100, icon = "image/UI_icon_JJB.png", quality = 3 },
    },
}

-- ======================== 周任务定义（8 条） ========================

TaskConfig.WEEKLY = {
    {
        id = "w_login_3",
        name = "累计登录3日",
        condKey = "login_days",
        target = 3,
        reward = { type = "diamond", amount = 880, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "w_login_7",
        name = "累计登录7日",
        condKey = "login_days",
        target = 7,
        reward = { type = "diamond", amount = 2000, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "w_recruit_10",
        name = "进行10次招募",
        condKey = "recruit",
        target = 10,
        reward = { type = "adventure_ticket", amount = 5, icon = "image/UI_icon_ZMQ_1.png", quality = 5 },
    },
    {
        id = "w_recruit_20",
        name = "进行20次招募",
        condKey = "recruit",
        target = 20,
        reward = { type = "adventure_ticket", amount = 10, icon = "image/UI_icon_ZMQ_1.png", quality = 5 },
    },
    {
        id = "w_stellar_recruit_10",
        name = "进行10次星辉招募",
        condKey = "stellar_recruit",
        target = 10,
        reward = { type = "stellar_ticket", amount = 5, icon = "image/UI_icon_ZMQ_2.png", quality = 6 },
    },
    {
        id = "w_artifact_draw_10",
        name = "进行10次神器抽取",
        condKey = "artifact_draw",
        target = 10,
        reward = { type = "golden_key", amount = 5, icon = "image/UI_icon_HJYS.png", quality = 6 },
    },
    {
        id = "w_decompose_100",
        name = "分解100件装备",
        condKey = "decompose",
        target = 100,
        reward = { type = "diamond", amount = 880, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "w_decompose_300",
        name = "分解300件装备",
        condKey = "decompose",
        target = 300,
        reward = { type = "diamond", amount = 1320, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "w_enhance_20",
        name = "强化20次装备",
        condKey = "enhance",
        target = 20,
        reward = { type = "diamond", amount = 1320, icon = "image/UI_icon_SJ.png", quality = 5 },
    },
    {
        id = "w_arena_15",
        name = "参加15次竞技场",
        condKey = "arena",
        target = 15,
        reward = { type = "arena_coin", amount = 888, icon = "image/UI_icon_JJB.png", quality = 3 },
    },
}

-- ======================== 成就定义（56 条） ========================

TaskConfig.ACHIEVEMENT = {
    -- -------- 转职成就 (1-10) --------
    { id = "a_adv1_1", name = "1名角色进行1转",   condKey = "adv1_count", target = 1, reward = { type = "diamond", amount = 100,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_adv1_2", name = "2名角色进行1转",   condKey = "adv1_count", target = 2, reward = { type = "diamond", amount = 150,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_adv1_3", name = "3名角色进行1转",   condKey = "adv1_count", target = 3, reward = { type = "diamond", amount = 200,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_adv1_4", name = "4名角色进行1转",   condKey = "adv1_count", target = 4, reward = { type = "diamond", amount = 300,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_adv1_5", name = "5名角色进行1转",   condKey = "adv1_count", target = 5, reward = { type = "diamond", amount = 400,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_adv2_1", name = "1名角色进行2转",   condKey = "adv2_count", target = 1, reward = { type = "diamond", amount = 200,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_adv2_2", name = "2名角色进行2转",   condKey = "adv2_count", target = 2, reward = { type = "diamond", amount = 400,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_adv2_3", name = "3名角色进行2转",   condKey = "adv2_count", target = 3, reward = { type = "diamond", amount = 600,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_adv2_4", name = "4名角色进行4转",   condKey = "adv2_count", target = 4, reward = { type = "diamond", amount = 888,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_adv2_5", name = "5名角色进行5转",   condKey = "adv2_count", target = 5, reward = { type = "diamond", amount = 1288, icon = "image/UI_icon_SJ.png", quality = 5 } },

    -- -------- 冒险等级成就 (11-18) --------
    { id = "a_plv_5",  name = "冒险等级达到5",    condKey = "player_level", target = 5,  reward = { type = "diamond", amount = 50,   icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_plv_10", name = "冒险等级达到10",   condKey = "player_level", target = 10, reward = { type = "diamond", amount = 100,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_plv_15", name = "冒险等级达到15",   condKey = "player_level", target = 15, reward = { type = "diamond", amount = 150,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_plv_20", name = "冒险等级达到20",   condKey = "player_level", target = 20, reward = { type = "diamond", amount = 200,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_plv_30", name = "冒险等级达到30",   condKey = "player_level", target = 30, reward = { type = "diamond", amount = 400,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_plv_40", name = "冒险等级达到40",   condKey = "player_level", target = 40, reward = { type = "diamond", amount = 600,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_plv_50", name = "冒险等级达到50",   condKey = "player_level", target = 50, reward = { type = "diamond", amount = 888,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_plv_60", name = "冒险等级达到60",   condKey = "player_level", target = 60, reward = { type = "diamond", amount = 1288, icon = "image/UI_icon_SJ.png", quality = 5 } },

    -- -------- 拥有 SR 角色 (19-23) --------
    { id = "a_sr_1",  name = "拥有1个SR角色",   condKey = "sr_count",  target = 1, reward = { type = "diamond", amount = 100, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_sr_2",  name = "拥有2个SR角色",   condKey = "sr_count",  target = 2, reward = { type = "diamond", amount = 150, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_sr_3",  name = "拥有3个SR角色",   condKey = "sr_count",  target = 3, reward = { type = "diamond", amount = 200, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_sr_4",  name = "拥有4个SR角色",   condKey = "sr_count",  target = 4, reward = { type = "diamond", amount = 300, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_sr_5",  name = "拥有5个SR角色",   condKey = "sr_count",  target = 5, reward = { type = "diamond", amount = 500, icon = "image/UI_icon_SJ.png", quality = 5 } },

    -- -------- 拥有 SSR 角色 (24-28) --------
    { id = "a_ssr_1", name = "拥有1个SSR角色",  condKey = "ssr_count", target = 1, reward = { type = "diamond", amount = 200,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_ssr_2", name = "拥有2个SSR角色",  condKey = "ssr_count", target = 2, reward = { type = "diamond", amount = 400,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_ssr_3", name = "拥有3个SSR角色",  condKey = "ssr_count", target = 3, reward = { type = "diamond", amount = 600,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_ssr_4", name = "拥有4个SSR角色",  condKey = "ssr_count", target = 4, reward = { type = "diamond", amount = 888,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_ssr_5", name = "拥有5个SSR角色",  condKey = "ssr_count", target = 5, reward = { type = "diamond", amount = 1288, icon = "image/UI_icon_SJ.png", quality = 5 } },

    -- -------- R 级角色觉醒 (29-35) --------
    { id = "a_awk_r_1", name = "任意R级角色觉醒至1阶",  condKey = "awk_r_max", target = 1, reward = { type = "diamond", amount = 50,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_r_2", name = "任意R级角色觉醒至2阶",  condKey = "awk_r_max", target = 2, reward = { type = "diamond", amount = 80,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_r_3", name = "任意R级角色觉醒至3阶",  condKey = "awk_r_max", target = 3, reward = { type = "diamond", amount = 100, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_r_4", name = "任意R级角色觉醒至4阶",  condKey = "awk_r_max", target = 4, reward = { type = "diamond", amount = 150, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_r_5", name = "任意R级角色觉醒至5阶",  condKey = "awk_r_max", target = 5, reward = { type = "diamond", amount = 200, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_r_6", name = "任意R级角色觉醒至6阶",  condKey = "awk_r_max", target = 6, reward = { type = "diamond", amount = 288, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_r_7", name = "任意R级角色觉醒至7阶",  condKey = "awk_r_max", target = 7, reward = { type = "diamond", amount = 400, icon = "image/UI_icon_SJ.png", quality = 5 } },

    -- -------- SR 级角色觉醒 (36-42) --------
    { id = "a_awk_sr_1", name = "任意SR级角色觉醒至1阶",  condKey = "awk_sr_max", target = 1, reward = { type = "diamond", amount = 100, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_sr_2", name = "任意SR级角色觉醒至2阶",  condKey = "awk_sr_max", target = 2, reward = { type = "diamond", amount = 150, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_sr_3", name = "任意SR级角色觉醒至3阶",  condKey = "awk_sr_max", target = 3, reward = { type = "diamond", amount = 200, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_sr_4", name = "任意SR级角色觉醒至4阶",  condKey = "awk_sr_max", target = 4, reward = { type = "diamond", amount = 300, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_sr_5", name = "任意SR级角色觉醒至5阶",  condKey = "awk_sr_max", target = 5, reward = { type = "diamond", amount = 500, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_sr_6", name = "任意SR级角色觉醒至6阶",  condKey = "awk_sr_max", target = 6, reward = { type = "diamond", amount = 688, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_sr_7", name = "任意SR级角色觉醒至7阶",  condKey = "awk_sr_max", target = 7, reward = { type = "diamond", amount = 888, icon = "image/UI_icon_SJ.png", quality = 5 } },

    -- -------- SSR 级角色觉醒 (43-49) --------
    { id = "a_awk_ssr_1", name = "任意SSR级角色觉醒至1阶", condKey = "awk_ssr_max", target = 1, reward = { type = "diamond", amount = 200,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_ssr_2", name = "任意SSR级角色觉醒至2阶", condKey = "awk_ssr_max", target = 2, reward = { type = "diamond", amount = 300,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_ssr_3", name = "任意SSR级角色觉醒至3阶", condKey = "awk_ssr_max", target = 3, reward = { type = "diamond", amount = 500,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_ssr_4", name = "任意SSR级角色觉醒至4阶", condKey = "awk_ssr_max", target = 4, reward = { type = "diamond", amount = 688,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_ssr_5", name = "任意SSR级角色觉醒至5阶", condKey = "awk_ssr_max", target = 5, reward = { type = "diamond", amount = 888,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_ssr_6", name = "任意SSR级角色觉醒至6阶", condKey = "awk_ssr_max", target = 6, reward = { type = "diamond", amount = 1288, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_awk_ssr_7", name = "任意SSR级角色觉醒至7阶", condKey = "awk_ssr_max", target = 7, reward = { type = "diamond", amount = 1888, icon = "image/UI_icon_SJ.png", quality = 5 } },

    -- -------- 竞技场段位 (50-56) --------
    { id = "a_arena_1", name = "竞技场段位达到青铜级", condKey = "arena_tier", target = 2, reward = { type = "diamond", amount = 50,   icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_arena_2", name = "竞技场段位达到白银级", condKey = "arena_tier", target = 3, reward = { type = "diamond", amount = 100,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_arena_3", name = "竞技场段位达到黄金级", condKey = "arena_tier", target = 4, reward = { type = "diamond", amount = 200,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_arena_4", name = "竞技场段位达到铂金级", condKey = "arena_tier", target = 5, reward = { type = "diamond", amount = 400,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_arena_5", name = "竞技场段位达到钻石级", condKey = "arena_tier", target = 6, reward = { type = "diamond", amount = 688,  icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_arena_6", name = "竞技场段位达到大师级", condKey = "arena_tier", target = 7, reward = { type = "diamond", amount = 1288, icon = "image/UI_icon_SJ.png", quality = 5 } },
    { id = "a_arena_7", name = "竞技场段位达到传说级", condKey = "arena_tier", target = 8, reward = { type = "diamond", amount = 1888, icon = "image/UI_icon_SJ.png", quality = 5 } },
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
