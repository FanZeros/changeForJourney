-- ============================================================================
-- Protocol - 网络通信协议常量（双端共享）
-- 职责: 定义所有远程事件名称、消息格式常�?
-- 运行�? shared（服务端 + 客户端都加载�?
-- ============================================================================

local Protocol = {}

-- ======================== 远程事件名称 ========================

-- 客户�?�?服务端：请求�?
Protocol.REQ_CLIENT_READY     = "C_Ready"        -- 客户端场景已准备�?
Protocol.REQ_LOAD_SAVE        = "C_LoadSave"      -- 请求加载存档
Protocol.REQ_ACTION           = "C_Action"        -- 通用业务请求
Protocol.REQ_NEW_GAME         = "C_NewGame"       -- 重连后选择新游�?
Protocol.REQ_RETURN_SERVER_SELECT = "C_ReturnServerSelect" -- 返回选服（不清档，特权卡转区等）
Protocol.REQ_HEARTBEAT        = "C_Heartbeat"     -- 客户端心跳（�?5s�?

-- 服务�?�?客户端：响应/推送类
Protocol.RES_SERVER_LIST      = "S_ServerList"     -- 区服列表 + 玩家已创角服列表
Protocol.RES_INIT_DATA        = "S_InitData"      -- 初始化数据（连接后首次发送）
Protocol.RES_SAVE_RESULT      = "S_SaveResult"    -- 存档加载结果
Protocol.RES_ACTION_RESULT    = "S_ActionResult"   -- 业务请求响应
Protocol.RES_STATE_UPDATE     = "S_StateUpdate"    -- 模块数据推送（增量/全量�?
Protocol.RES_STATE_BATCH      = "S_StateBatch"     -- 批量数据推送（拆分传输用）
Protocol.RES_KICKED           = "S_Kicked"         -- 被踢出（顶号等）
Protocol.RES_RECONNECT_DATA   = "S_ReconnectData"  -- 重连数据
Protocol.RES_OFFLINE_REWARD   = "S_OfflineReward"   -- 离线收益推�?

-- ======================== 消息格式常量 ========================

-- 单条消息安全阈值（字节�?
Protocol.MSG_SAFE_SIZE = 50000    -- 50KB�?0KB 硬限�?- 10KB 余量�?

-- 存档结果状�?
Protocol.SAVE_STATUS_SUCCESS = "success"
Protocol.SAVE_STATUS_FAILED  = "failed"
Protocol.SAVE_STATUS_TIMEOUT = "timeout"

-- 业务请求类型（REQ_ACTION 的子类型�?
Protocol.ACTION_TYPES = {
    -- 战斗
    NEXT_STAGE     = "next_stage",      -- 进入下一�?
    RESET_STAGE    = "reset_stage",     -- 重置关卡

    -- 英雄
    DEPLOY_HERO    = "deploy_hero",     -- 上阵英雄
    UNDEPLOY_HERO  = "undeploy_hero",   -- 下阵英雄
    SET_DEPLOYED   = "set_deployed",    -- 设置完整出战阵容
    LEVEL_UP_HERO  = "level_up_hero",   -- 英雄升级

    -- 经济
    DRAW_CARD      = "draw_card",       -- 抽卡（旧版简易抽卡）
    GACHA_PULL     = "gacha_pull",      -- 酒馆招募（完整抽卡系统）
    TARGET_RECRUIT = "target_recruit", -- 指定招募（设置保底目标英雄）
    STELLAR_TARGET_UP = "stellar_target_up", -- 星辉指定UP角色（UR命中时50%概率转为该角色）

    -- 战斗奖励
    CLAIM_BATTLE_REWARDS = "claim_battle_rewards",  -- 批量领取击杀奖励

    -- 装备（GM / 测试�?
    GM_GIVE_EQUIP  = "gm_give_equip",   -- GM 给装备（指定模板/等级/品质�?
    GM_GIVE_RANDOM = "gm_give_random",  -- GM 随机给装�?
    GM_GIVE_RELIC  = "gm_give_relic",   -- GM 给遗物（指定类型/品质�?

    -- 遗物操作
    RELIC_REFORGE  = "relic_reforge",   -- 遗物洗练（消耗奥术粉尘，生成候选词缀）
    RELIC_REFORGE_CONFIRM = "relic_reforge_confirm", -- 确认替换洗练候选词缀
    RELIC_PLACE    = "relic_place",     -- 遗物镶嵌到石板网�?
    RELIC_REMOVE   = "relic_remove",    -- 从石板网格取下遗�?
    RELIC_BATCH_ADJUST = "relic_batch_adjust", -- 调整模式批量移动（原子化 REMOVE+PLACE�?
    RELIC_MERGE    = "relic_merge",      -- 遗物合成（3个同类型同品质→1个高品质）
    RELIC_REPLACE  = "relic_replace",
    RELIC_LOCK     = "relic_lock",       -- 切换遗物锁定（锁定后无法参与合成）

    -- 神器操作
    ARTIFACT_DRAW    = "artifact_draw",    -- 神器宝箱抽取（params: { count = 1|10 }）
    ARTIFACT_EQUIP   = "artifact_equip",   -- 装配神器到出战槽位（params: { artifactId, slot, subSlot? }）
    ARTIFACT_UNEQUIP = "artifact_unequip", -- 卸下指定出战槽位神器（params: { slot, subSlot? }）
    ARTIFACT_MERGE   = "artifact_merge",   -- 神器合成（3个同神器同品质→1个高品质）
    ARTIFACT_REROLL  = "artifact_reroll",  -- 神器置换（2个同品质神器→1个同品质不同类型神器）
    ARTIFACT_REFINE_VALUE = "artifact_refine_value", -- 神器洗练数值（消耗特权点，重新roll当前词缀数值）

    -- 装备操作
    EQUIP_ITEM     = "equip_item",      -- 穿戴/更换装备
    UNEQUIP_ITEM   = "unequip_item",    -- 卸下装备
    UNEQUIP_ALL    = "unequip_all",     -- 一键卸下全部装�?
    EQUIP_ALL_BEST = "equip_all_best",  -- 一键装备最佳装�?
    TOGGLE_EQUIP_LOCK = "toggle_equip_lock", -- 切换装备锁定（锁定后无法被分解）

    -- 装备设置
    SET_AUTO_DECOMPOSE = "set_auto_decompose", -- 设置自动分解条件（autoQuality/autoLevel�?

    -- 铁匠铺操�?
    ENHANCE_EQUIP     = "enhance_equip",      -- 强化装备（消耗金币，升一级）
    ENHANCE_EQUIP_MAX = "enhance_equip_max",  -- 一键强化到目标等级（消耗金�?卷轴，批量升级）
    REFINE_EQUIP    = "refine_equip",    -- 洗练装备（消耗精粹，重随词缀�?
    REFINE_REPLACE  = "refine_replace",  -- 替换词缀（用洗练后的结果覆盖�?
    DECOMPOSE_EQUIP = "decompose_equip", -- 分解装备（获得精粹）

    -- 资源管理（GM / 测试�?
    GM_GIVE_RESOURCE = "gm_give_resource", -- GM 给资源（指定 key + amount�?

    -- 转职
    ADVANCE_CLASS  = "advance_class",   -- 英雄转职（一�?二转�?
    RESET_CLASS    = "reset_class",     -- 重置转职（清�?advBranch�?

    -- 存档管理（GM / 测试�?
    GM_RESET_SAVE  = "gm_reset_save",   -- GM 清除存档（重置为默认值）
    GM_LEVEL_UP    = "gm_level_up",     -- GM 英雄升级（免费，不扣金币）
    GM_AWAKENING   = "gm_awakening",    -- GM 提升觉醒等级（免费，不扣碎片）
    GM_GIVE_HERO   = "gm_give_hero",    -- GM 获得冒险家（写入服务端 roster）
    GM_PLAYER_LEVEL_UP = "gm_player_level_up", -- GM 冒险等级提升（直接升一级）
    GM_JUMP_STAGE      = "gm_jump_stage",      -- GM 跳转关卡（同步 maxStageId / clearedStages）

    -- 天赋
    ACTIVATE_TALENT      = "activate_talent",      -- 激活天赋节点（消�?天赋点）
    RESET_TALENTS        = "reset_talents",        -- 重置全部天赋（恢复天赋点�?
    RESET_SINGLE_TALENT  = "reset_single_talent",  -- 重置单个末尾天赋节点（恢�?天赋点）

    -- 觉醒
    ACTIVATE_AWAKENING = "activate_awakening", -- 激活觉醒节�?

    -- 碎片
    SYNTHESIZE_HERO = "synthesize_hero",       -- 碎片合成英雄�?0碎片解锁未拥有英雄）
    CONVERT_SHARD_TO_COIN = "convert_shard_to_coin", -- 满觉醒碎片转酒馆�?
    CONVERT_UR_SHARD = "convert_ur_shard",     -- UR碎片1:1转化为其他英雄碎片
    RESTORE_UR_SHARD_CONVERT = "restore_ur_shard_convert", -- 消耗特权点恢复UR碎片转化次数

    -- 战利�?
    CLAIM_LOOT     = "claim_loot",       -- 领取战利品（从种子生成装备入背包�?
    CLAIM_LOOT_ALL = "claim_loot_all",   -- 一键领取全部战利品
    DECOMPOSE_LOOT_ALL = "decompose_loot_all", -- 一键分解全部战利品
    DECOMPOSE_LOOT     = "decompose_loot",     -- 分解指定组战利品

    -- 竞技�?
    ARENA_ENTER         = "arena_enter",          -- 进入竞技场（惰性结�?分组+自动同步防守阵容+返回排名�?
    ARENA_GET_OPPONENT  = "arena_get_opponent",    -- 获取对手防守阵容
    ARENA_BATTLE_RESULT = "arena_battle_result",   -- 提交战斗结果（结算积分）
    ARENA_GET_LOG       = "arena_get_log",         -- 获取防守记录（延迟结算）
    ARENA_SHOP_BUY      = "arena_shop_buy",        -- 竞技场商店购�?
    TAVERN_SHOP_BUY     = "tavern_shop_buy",       -- 酒馆商店购买
    ARENA_CLAIM_TIER    = "arena_claim_tier",      -- 领取段位首通奖�?

    -- 离线收益
    CLAIM_OFFLINE_REWARDS = "claim_offline_rewards", -- 领取离线收益

    -- 兑换�?
    REDEEM_CODE = "redeem_code",  -- 兑换码兑�?

    -- 邮件
    CLAIM_MAIL     = "claim_mail",       -- 领取单封邮件奖励（params: { mailId = string }�?
    CLAIM_ALL_MAIL = "claim_all_mail",   -- 一键领取所有未读邮�?
    DELETE_READ    = "delete_read",      -- 删除已读邮件

    -- 头像
    SET_AVATAR       = "set_avatar",        -- 设置头像
    SET_AVATAR_FRAME = "set_avatar_frame",  -- 设置头像框

    -- 初始角色选择
    SELECT_INITIAL_HERO = "select_initial_hero",  -- 新玩家选择初始英雄

    -- 开场剧�?
    MARK_INTRO_COMPLETED = "mark_intro_completed",  -- 标记开场剧情已完成

    -- 轮回
    CLEAR_REINCARNATION = "clear_reincarnation",  -- 清除轮回标志（入场动画播放完毕后调用�?

    -- 签到
    WEEKLY_SIGN      = "weekly_sign",       -- 每周签到（当日）
    DAILY_SIGN       = "daily_sign",        -- 每日签到（当日）
    RETRO_SIGN       = "retro_sign",        -- 补签（消耗钻石）
    GET_SIGNIN_STATE = "get_signin_state",  -- 查询签到状态（触发周期重置检查）

    -- 区服
    SELECT_SERVER                     = "select_server",                     -- 选择区服（params: { serverId = number }）
    TRANSFER_PRIVILEGE_CARD           = "transfer_privilege_card",           -- 特权卡转区（当前区服内发起）
    TRANSFER_CLOSED_CHALLENGER_CARD   = "transfer_closed_challenger_card",   -- 挑战者活动结束后从选服界面转出特权卡

    -- 任务
    CLAIM_TASK = "claim_task",  -- 领取任务奖励（params: { taskId = string }�?

    -- 情景奖励
    CLAIM_SCENARIO_REWARD = "claim_scenario_reward", -- 领取情景对话奖励（params: { scenarioId = number }�?

    -- 广告补偿
    AD_PENDING = "ad_pending",    -- 广告即将展示（SDK 调用前发送，服务端写 adPending 标记）params: { scene = string }
    AD_CONFIRM = "ad_confirm",    -- 广告成功完成（SDK 回调成功后发送，服务端结算奖励并清除标记）params: { scene = string }

    -- 市场商店
    MARKET_BUY              = "market_buy",              -- 市场购买商品（params: { itemId = number }�?
    CLAIM_PRIVILEGE_REWARD  = "claim_privilege_reward",  -- 领取特权观看奖励（params: { threshold = number }�?
    WATCH_PRIVILEGE_AD      = "watch_privilege_ad",      -- 观看特权广告完成（客户端广告成功后发送，服务端扣除存储、增�?watchCount 和特权点�?

    -- 冒险者公�?
    GUILD_ENTER = "guild_enter",  -- 进入公会（返回关卡排行榜数据�?

    -- 扫荡
    SWEEP = "sweep",  -- 消耗扫荡券，立即获�?0分钟挂机收益

    -- 副本
    DUNGEON_CHALLENGE  = "dungeon_challenge",   -- 发起副本挑战（params: { dungeonId, floor }）
    DUNGEON_SWEEP      = "dungeon_sweep",       -- 副本扫荡（params: { dungeonId }）
    DUNGEON_WIN        = "dungeon_win",         -- 副本战斗胜利（params: { dungeonId, floor }）
    DUNGEON_IDLE_CLAIM = "dungeon_idle_claim",  -- 领取副本挂机/离线收益（params: { dungeonId }）

    -- 通天塔
    TOWER_CHALLENGE   = "tower_challenge",    -- 发起通天塔挑战
    TOWER_WAVE_WIN    = "tower_wave_win",     -- 通天塔单波胜利
    TOWER_FLOOR_WIN   = "tower_floor_win",    -- 通天塔整层通关
    TOWER_SWEEP       = "tower_sweep",        -- 通天塔扫荡
    TOWER_PICK_BUFF   = "tower_pick_buff",    -- 通天塔选择强化

    -- ======================== GM 后台控制�?========================
    -- 第一批：零风险高价�?
    GM_KICK_PLAYER     = "gm_kick_player",      -- 踢出玩家（强制断开连接�?
    GM_SEND_MAIL       = "gm_send_mail",        -- 发送单人邮件（含资源附件）
    GM_SERVER_STATUS   = "gm_server_status",    -- 查询服务器状态（在线人数、运行时间）
    GM_RESET_MODULE    = "gm_reset_module",     -- 重置指定模块数据

    -- 第二批：中等难度
    GM_BAN_PLAYER      = "gm_ban_player",       -- 封禁玩家
    GM_UNBAN_PLAYER    = "gm_unban_player",     -- 解封玩家
    GM_MAINTENANCE     = "gm_maintenance",      -- 维护模式开�?
    GM_QUERY_PLAYER    = "gm_query_player",     -- 查询在线玩家信息
    GM_ANNOUNCEMENT    = "gm_announcement",     -- 公告管理（增删改�?

    -- 第三批：新子系统
    GM_BROADCAST_MAIL  = "gm_broadcast_mail",   -- 全服广播邮件

    -- GM 工具
    GM_QUERY_LOG       = "gm_query_log",        -- 查询 GM 操作日志
    GM_REPAIR_SAVE     = "gm_repair_save",      -- 修复玩家丢档（迁移恢复）
}

return Protocol
