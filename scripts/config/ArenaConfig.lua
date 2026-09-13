-- ============================================================================
-- ArenaConfig - 竞技场配置表（双端共享）
-- 职责: 段位表、积分规则、周排名奖励、竞技券配额、防守积分
-- 运行端: shared（服务端 + 客户端都加载）
-- ============================================================================

local ArenaConfig = {}

-- ======================== 常量 ========================

--- 公共 UID（用于存储全局分组数据）
ArenaConfig.PUBLIC_UID = "ARENA_PUBLIC"

--- 每组人数上限
ArenaConfig.GROUP_SIZE = 30

--- 周期分初始值（每周重置）
ArenaConfig.WEEK_SCORE_INIT = 1000

--- weekId 基准时间戳（一个历史上的周一 00:00 UTC+8）
--- 2024-01-01 00:00:00 Monday CST = 1704038400
ArenaConfig.WEEK_EPOCH = 1704038400

--- 一周秒数
ArenaConfig.WEEK_SECONDS = 604800

-- ======================== 段位表 ========================
-- 共 7 大段位 × 5 小段位 = 35 + 传说级 = 36 条
-- id: 唯一序号(1~36)
-- major: 大段位名称
-- minor: 小段位后缀（V/IV/III/II/I），传说级为 nil
-- icon: 段位图标索引（1~8, 8=传说）
-- scoreMin: 段位分下限
-- scoreMax: 段位分上限（传说级为 math.huge）
-- firstRewardDiamond: 首次抵达奖励钻石数

ArenaConfig.TIERS = {
    -- 黑铁级 (icon=1)
    { id =  1, major = "黑铁级", minor = "V",   icon = 1, scoreMin = 0,    scoreMax = 99,   firstRewardDiamond = 100  },
    { id =  2, major = "黑铁级", minor = "IV",  icon = 1, scoreMin = 100,  scoreMax = 199,  firstRewardDiamond = 100  },
    { id =  3, major = "黑铁级", minor = "III", icon = 1, scoreMin = 200,  scoreMax = 299,  firstRewardDiamond = 100  },
    { id =  4, major = "黑铁级", minor = "II",  icon = 1, scoreMin = 300,  scoreMax = 399,  firstRewardDiamond = 100  },
    { id =  5, major = "黑铁级", minor = "I",   icon = 1, scoreMin = 400,  scoreMax = 499,  firstRewardDiamond = 100  },
    -- 青铜级 (icon=2)
    { id =  6, major = "青铜级", minor = "V",   icon = 2, scoreMin = 500,  scoreMax = 599,  firstRewardDiamond = 300  },
    { id =  7, major = "青铜级", minor = "IV",  icon = 2, scoreMin = 600,  scoreMax = 699,  firstRewardDiamond = 150  },
    { id =  8, major = "青铜级", minor = "III", icon = 2, scoreMin = 700,  scoreMax = 799,  firstRewardDiamond = 150  },
    { id =  9, major = "青铜级", minor = "II",  icon = 2, scoreMin = 800,  scoreMax = 899,  firstRewardDiamond = 150  },
    { id = 10, major = "青铜级", minor = "I",   icon = 2, scoreMin = 900,  scoreMax = 999,  firstRewardDiamond = 150  },
    -- 白银级 (icon=3)
    { id = 11, major = "白银级", minor = "V",   icon = 3, scoreMin = 1000, scoreMax = 1099, firstRewardDiamond = 450  },
    { id = 12, major = "白银级", minor = "IV",  icon = 3, scoreMin = 1100, scoreMax = 1199, firstRewardDiamond = 200  },
    { id = 13, major = "白银级", minor = "III", icon = 3, scoreMin = 1200, scoreMax = 1299, firstRewardDiamond = 200  },
    { id = 14, major = "白银级", minor = "II",  icon = 3, scoreMin = 1300, scoreMax = 1399, firstRewardDiamond = 200  },
    { id = 15, major = "白银级", minor = "I",   icon = 3, scoreMin = 1400, scoreMax = 1499, firstRewardDiamond = 200  },
    -- 黄金级 (icon=4)
    { id = 16, major = "黄金级", minor = "V",   icon = 4, scoreMin = 1500, scoreMax = 1599, firstRewardDiamond = 600  },
    { id = 17, major = "黄金级", minor = "IV",  icon = 4, scoreMin = 1600, scoreMax = 1699, firstRewardDiamond = 250  },
    { id = 18, major = "黄金级", minor = "III", icon = 4, scoreMin = 1700, scoreMax = 1799, firstRewardDiamond = 250  },
    { id = 19, major = "黄金级", minor = "II",  icon = 4, scoreMin = 1800, scoreMax = 1899, firstRewardDiamond = 250  },
    { id = 20, major = "黄金级", minor = "I",   icon = 4, scoreMin = 1900, scoreMax = 1999, firstRewardDiamond = 250  },
    -- 铂金级 (icon=5)
    { id = 21, major = "铂金级", minor = "V",   icon = 5, scoreMin = 2000, scoreMax = 2149, firstRewardDiamond = 750  },
    { id = 22, major = "铂金级", minor = "IV",  icon = 5, scoreMin = 2150, scoreMax = 2299, firstRewardDiamond = 300  },
    { id = 23, major = "铂金级", minor = "III", icon = 5, scoreMin = 2300, scoreMax = 2449, firstRewardDiamond = 300  },
    { id = 24, major = "铂金级", minor = "II",  icon = 5, scoreMin = 2450, scoreMax = 2599, firstRewardDiamond = 300  },
    { id = 25, major = "铂金级", minor = "I",   icon = 5, scoreMin = 2600, scoreMax = 2749, firstRewardDiamond = 300  },
    -- 钻石级 (icon=6)
    { id = 26, major = "钻石级", minor = "V",   icon = 6, scoreMin = 2750, scoreMax = 2949, firstRewardDiamond = 900  },
    { id = 27, major = "钻石级", minor = "IV",  icon = 6, scoreMin = 2950, scoreMax = 3149, firstRewardDiamond = 400  },
    { id = 28, major = "钻石级", minor = "III", icon = 6, scoreMin = 3150, scoreMax = 3349, firstRewardDiamond = 400  },
    { id = 29, major = "钻石级", minor = "II",  icon = 6, scoreMin = 3350, scoreMax = 3549, firstRewardDiamond = 400  },
    { id = 30, major = "钻石级", minor = "I",   icon = 6, scoreMin = 3550, scoreMax = 3749, firstRewardDiamond = 400  },
    -- 大师级 (icon=7)
    { id = 31, major = "大师级", minor = "V",   icon = 7, scoreMin = 3750, scoreMax = 3999, firstRewardDiamond = 1200 },
    { id = 32, major = "大师级", minor = "IV",  icon = 7, scoreMin = 4000, scoreMax = 4249, firstRewardDiamond = 500  },
    { id = 33, major = "大师级", minor = "III", icon = 7, scoreMin = 4250, scoreMax = 4499, firstRewardDiamond = 500  },
    { id = 34, major = "大师级", minor = "II",  icon = 7, scoreMin = 4500, scoreMax = 4749, firstRewardDiamond = 500  },
    { id = 35, major = "大师级", minor = "I",   icon = 7, scoreMin = 4750, scoreMax = 4999, firstRewardDiamond = 500  },
    -- 传说级 (icon=8)
    { id = 36, major = "传说级", minor = nil,   icon = 8, scoreMin = 5000, scoreMax = math.huge, firstRewardDiamond = 1500 },
}

-- ======================== 进攻积分规则 ========================
-- 根据「对手排名 - 我方排名」的差值区间确定得失分
-- rankDiffMin/rankDiffMax: 排名差范围（正数 = 对手排名更高 = 以下克上）
-- winScore: 胜利获得周期分
-- loseScore: 失败扣除周期分（负数）
-- winCoin: 胜利获得竞技币
-- loseCoin: 失败获得竞技币

ArenaConfig.ATTACK_SCORING = {
    { rankDiffMin =  21, rankDiffMax = math.huge, winScore = 30, loseScore = -5,  winCoin = 50, loseCoin = 30 }, -- 对手高20名以上
    { rankDiffMin =  11, rankDiffMax = 20,        winScore = 25, loseScore = -8,  winCoin = 50, loseCoin = 30 }, -- 对手高11~20名
    { rankDiffMin =   1, rankDiffMax = 10,        winScore = 20, loseScore = -10, winCoin = 50, loseCoin = 30 }, -- 对手高1~10名
    { rankDiffMin =  -5, rankDiffMax = 0,         winScore = 15, loseScore = -12, winCoin = 50, loseCoin = 30 }, -- 相近(±5名)
    { rankDiffMin = -10, rankDiffMax = -6,        winScore = 12, loseScore = -15, winCoin = 50, loseCoin = 30 }, -- 对手低1~10名（从-6开始，因为±5已被上一档覆盖）
    { rankDiffMin = -20, rankDiffMax = -11,       winScore = 10, loseScore = -18, winCoin = 50, loseCoin = 30 }, -- 对手低11~20名
    { rankDiffMin = -math.huge, rankDiffMax = -21, winScore = 8, loseScore = -22, winCoin = 50, loseCoin = 30 }, -- 对手低20名以上
}

--- 根据排名差查找对应的进攻积分规则
---@param rankDiff number myRank - opponentRank（正数=我排名数字更大=我名次更低=以下克上；排名1=第一名）
---@return table rule { winScore, loseScore, winCoin, loseCoin }
function ArenaConfig.getAttackScoring(rankDiff)
    -- rankDiff = myRank - opponentRank
    -- 正数 = 我排名数字更大 = 我名次更低 = 以下克上（高收益低风险）
    -- 负数 = 我排名数字更小 = 我名次更高 = 以上打下（低收益高风险）
    for _, rule in ipairs(ArenaConfig.ATTACK_SCORING) do
        if rankDiff >= rule.rankDiffMin and rankDiff <= rule.rankDiffMax then
            return rule
        end
    end
    -- 兜底（不应触发）
    return ArenaConfig.ATTACK_SCORING[4]
end

-- ======================== 防守积分 ========================

ArenaConfig.DEFENSE_WIN_SCORE  = 8   -- 防守成功（击败进攻方）获得周期分
ArenaConfig.DEFENSE_LOSE_SCORE = -3  -- 防守失败（被击败）扣除周期分

--- 对战历史记录上限（每周清空）
ArenaConfig.BATTLE_HISTORY_MAX = 50

-- ======================== 周排名奖励 ========================
-- 30人制小组周结算奖励
-- rankMin/rankMax: 名次范围（1=第一名）
-- rankScoreChange: 段位分变动
-- diamond: 钻石奖励
-- arenaCoin: 竞技币奖励

ArenaConfig.WEEK_REWARDS = {
    { rankMin = 1,  rankMax = 1,  rankScoreChange = 250, diamond = 500, arenaCoin = 1000 },
    { rankMin = 2,  rankMax = 3,  rankScoreChange = 200, diamond = 400, arenaCoin = 800  },
    { rankMin = 4,  rankMax = 6,  rankScoreChange = 150, diamond = 300, arenaCoin = 600  },
    { rankMin = 7,  rankMax = 12, rankScoreChange = 100, diamond = 200, arenaCoin = 400  },
    { rankMin = 13, rankMax = 18, rankScoreChange = 50,  diamond = 150, arenaCoin = 300  },
    { rankMin = 19, rankMax = 24, rankScoreChange = 10,  diamond = 100, arenaCoin = 200  },
    { rankMin = 25, rankMax = 30, rankScoreChange = -10, diamond = 50,  arenaCoin = 100  },
}

--- 根据名次查找周排名奖励
---@param rank number 名次（1=第一名）
---@return table|nil reward { rankScoreChange, diamond, arenaCoin }
function ArenaConfig.getWeekReward(rank)
    for _, rw in ipairs(ArenaConfig.WEEK_REWARDS) do
        if rank >= rw.rankMin and rank <= rw.rankMax then
            return rw
        end
    end
    return nil
end

-- ======================== 竞技券配额 ========================

ArenaConfig.TICKET_DAILY_FREE = 3    -- 每日免费竞技券

-- ======================== serverCloud key 规划 ========================
-- 所有 key 都需要通过 getCloudKey() 获取，以自动附加区服前缀

local ServerListConfig = require("shared.ServerListConfig")

--- 基础 key 名映射（不含区服前缀）
local BASE_KEYS = {
    PLAYER_MODULE   = "mod_arena",              -- 玩家竞技场模块数据
    DEFENSE         = "arena_defense",           -- 防守阵容快照
    DEFENSE_LOG     = "arena_defense_log",       -- 待结算的防守记录 (list)
    META            = "arena_meta",              -- 分组元数据（公共UID）
    GROUP_PREFIX    = "arena_group_",            -- 小组成员列表前缀（公共UID）
    RANK_SCORE      = "arena_rank_score",        -- 段位分排行榜 (SetInt)
    TICKET_QUOTA    = "arena_ticket",            -- 竞技券每日配额 (quota)
}

--- 获取带区服前缀的 cloud key
--- 竞技场数据是区服隔离的，所有 key 都需要加前缀
---@param keyName string  BASE_KEYS 中的 key 名，如 "PLAYER_MODULE", "DEFENSE" 等
---@param serverId number 区服 ID
---@return string  带前缀的完整 key，如 "s1_arena_defense"
function ArenaConfig.getCloudKey(keyName, serverId)
    local base = BASE_KEYS[keyName]
    if not base then
        error("[ArenaConfig] unknown cloud key name: " .. tostring(keyName))
    end
    local prefix = ServerListConfig.getKeyPrefix(serverId)
    return prefix .. base
end

--- 向后兼容：CLOUD_KEYS 仍可直接访问基础 key（不带前缀）
--- 警告: 新代码应使用 getCloudKey(keyName, serverId)
ArenaConfig.CLOUD_KEYS = BASE_KEYS

-- ======================== 工具函数 ========================

--- 根据段位分查找当前段位
---@param rankScore number 段位分
---@return table tier 段位配置条目
function ArenaConfig.getTierByScore(rankScore)
    -- 从高到低查找（传说级优先匹配）
    for i = #ArenaConfig.TIERS, 1, -1 do
        if rankScore >= ArenaConfig.TIERS[i].scoreMin then
            return ArenaConfig.TIERS[i]
        end
    end
    return ArenaConfig.TIERS[1]
end

--- 获取段位显示名称（如 "黑铁级 V"、"传说级"）
---@param tier table 段位配置条目
---@return string
function ArenaConfig.getTierDisplayName(tier)
    if tier.minor then
        return tier.major .. " " .. tier.minor
    end
    return tier.major
end

--- 计算当前 weekId
---@param timestamp number|nil 时间戳（默认 os.time()）
---@return number weekId
function ArenaConfig.calcWeekId(timestamp)
    local t = timestamp or os.time()
    return math.floor((t - ArenaConfig.WEEK_EPOCH) / ArenaConfig.WEEK_SECONDS)
end

--- 获取段位总数
---@return number
function ArenaConfig.getTierCount()
    return #ArenaConfig.TIERS
end

-- ======================== AI 玩家 ========================

--- 判断 UID 是否为 AI 玩家（AI 使用负数 UID）
---@param uid number
---@return boolean
function ArenaConfig.isAIPlayer(uid)
    return type(uid) == "number" and uid < 0
end

--- AI 玩家名字池（用于预填小组时随机分配）
ArenaConfig.AI_NAMES = {
    "铁壁守卫",   "风暴骑士",   "暗影刺客",   "光明使者",   "幻影游侠",
    "星辰法师",   "碎骨战士",   "圣光祭司",   "烈焰行者",   "冰霜贤者",
    "雷鸣骑兵",   "月影猎手",   "破晓勇士",   "深渊守望",   "银翼弓手",
    "赤焰术士",   "苍穹剑士",   "翡翠治愈",   "暮光刺客",   "磐石骑士",
    "疾风斥候",   "紫电法师",   "钢铁卫士",   "圣域祈祷",   "血月狂战",
    "碧波海神",   "金刚力士",   "幽灵射手",   "凤凰术师",   "白银圣骑",
}

-- ======================== 竞技场商店商品 ========================

ArenaConfig.SHOP_ITEMS = {
    { id = 1, name = "随机强化卷轴", quality = 3, limitCycle = "weekly",   limitCount = 20, price = 50,   rewardType = "random_scroll",  rewardCount = 10 },
    { id = 2, name = "洗练石",       quality = 3, limitCycle = "weekly",   limitCount = 4,  price = 50,   rewardType = "enhanceStone",   rewardCount = 1 },
    { id = 3, name = "点金石",       quality = 5, limitCycle = "weekly",   limitCount = 3,  price = 150,  rewardType = "destroyStone",   rewardCount = 1 },
    { id = 4, name = "扫荡券",       quality = 4, limitCycle = "weekly",   limitCount = 2,  price = 100,  rewardType = "sweepTicket",    rewardCount = 1 },
    { id = 5, name = "冒险招募券",   quality = 5, limitCycle = "weekly",   limitCount = 5,  price = 150,  rewardType = "recruitTicket",  rewardCount = 1 },
    { id = 6, name = "急救复活甲-碎片", quality = 5, limitCycle = "weekly",  limitCount = 1,  price = 4000, rewardType = "shard",          rewardHeroId = 15, rewardCount = 10 },
}

--- 根据 id 查找商品配置
---@param itemId number
---@return table|nil
function ArenaConfig.getShopItem(itemId)
    for _, item in ipairs(ArenaConfig.SHOP_ITEMS) do
        if item.id == itemId then return item end
    end
    return nil
end

return ArenaConfig
