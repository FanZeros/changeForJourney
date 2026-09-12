-- ============================================================================
-- GachaConfig.lua - 抽卡系统配置
-- 数据来源: docs/配置文件/建筑-酒馆招募.txt
-- ============================================================================

local HC = require("config.HeroConfig")

local GachaConfig = {}

-- ======================== 消耗配置 ========================

GachaConfig.Cost = {
    SINGLE_TICKET  = 1,      -- 单抽消耗冒险招募券
    TEN_TICKET     = 10,     -- 十连消耗冒险招募券
    SINGLE_DIAMOND = 180,    -- 单抽钻石替代价格
    TEN_DIAMOND    = 1800,   -- 十连钻石替代价格
}

-- ======================== 品质概率 ========================

-- 品质等级定义（与 HeroConfig / RecruitAnim 的 quality 值对应）
GachaConfig.QUALITY_N   = 0
GachaConfig.QUALITY_R   = 1
GachaConfig.QUALITY_SR  = 2
GachaConfig.QUALITY_SSR = 3

-- 基础概率（百分比）
GachaConfig.Probability = {
    [GachaConfig.QUALITY_N]   = 71.0,
    [GachaConfig.QUALITY_R]   = 18.0,
    [GachaConfig.QUALITY_SR]  = 10.0,
    [GachaConfig.QUALITY_SSR] = 1.0,
}

-- ======================== 保底配置 ========================

GachaConfig.Pity = {
    -- SR 保底：连续未出 SR 或更高品质时，第 N 次必出 SR
    SR_THRESHOLD  = 10,
    -- SSR 硬保底：连续未出 SSR 时，第 N 次必出 SSR
    SSR_THRESHOLD = 80,
    -- SSR 软保底：从第 SSR_SOFT_PITY_START 抽起，每多一抽 SSR 概率提升 SSR_SOFT_PITY_RATE%
    SSR_SOFT_PITY_START = 60,   -- 第 61 抽开始提升概率
    SSR_SOFT_PITY_RATE  = 6.0,  -- 每抽 +6%
}

-- ======================== 卡池物品定义 ========================
-- type: "hero" | "shard" | "resource"
-- heroId: 英雄 ID（hero / shard 类型）
-- resType: 资源类型 key（仅 resource 类型）
-- amount: 碎片/资源数量（shard / resource 类型）
-- quality: 品质等级 (0=N, 1=R, 2=SR, 3=SSR)
-- weight: 权重（同品质内的相对权重）
-- stardustValue: 满觉醒后分解为酒馆币的数量

GachaConfig.Pool = {
    -- N 品质（3 项碎片：R 英雄碎片）
    { quality = 0, type = "shard", heroId = 1,  amount = 1, weight = 100, stardustValue = 5 },  -- 卡琳碎片
    { quality = 0, type = "shard", heroId = 2,  amount = 1, weight = 100, stardustValue = 5 },  -- 麦琪碎片
    { quality = 0, type = "shard", heroId = 3,  amount = 1, weight = 100, stardustValue = 5 },  -- 琳达碎片

    -- R 品质（3 角色 + 6 碎片 = 9 项）
    { quality = 1, type = "hero",  heroId = 1,  weight = 100, stardustValue = 50 },  -- 卡琳
    { quality = 1, type = "hero",  heroId = 2,  weight = 100, stardustValue = 50 },  -- 麦琪
    { quality = 1, type = "hero",  heroId = 3,  weight = 100, stardustValue = 50 },  -- 琳达
    { quality = 1, type = "shard", heroId = 4,  amount = 1, weight = 100, stardustValue = 25 },  -- 塞西莉亚碎片
    { quality = 1, type = "shard", heroId = 5,  amount = 1, weight = 100, stardustValue = 25 },  -- 维多利亚碎片
    { quality = 1, type = "shard", heroId = 6,  amount = 1, weight = 100, stardustValue = 25 },  -- 露娜碎片
    { quality = 1, type = "shard", heroId = 7,  amount = 1, weight = 100, stardustValue = 25 },  -- 星织碎片
    { quality = 1, type = "shard", heroId = 8,  amount = 1, weight = 100, stardustValue = 25 },  -- 绫音碎片
    { quality = 1, type = "shard", heroId = 9,  amount = 1, weight = 100, stardustValue = 25 },  -- 芙罗拉碎片

    -- SR 品质（6 角色 + 6 碎片 = 12 项）
    { quality = 2, type = "hero",  heroId = 4,  weight = 100, stardustValue = 250 },  -- 塞西莉亚
    { quality = 2, type = "hero",  heroId = 5,  weight = 100, stardustValue = 250 },  -- 维多利亚
    { quality = 2, type = "hero",  heroId = 6,  weight = 100, stardustValue = 250 },  -- 露娜
    { quality = 2, type = "hero",  heroId = 7,  weight = 100, stardustValue = 250 },  -- 星织
    { quality = 2, type = "hero",  heroId = 8,  weight = 100, stardustValue = 250 },  -- 绫音
    { quality = 2, type = "hero",  heroId = 9,  weight = 100, stardustValue = 250 },  -- 芙罗拉
    { quality = 2, type = "shard", heroId = 10, amount = 1, weight = 100, stardustValue = 100 },  -- 丽贝卡碎片
    { quality = 2, type = "shard", heroId = 11, amount = 1, weight = 100, stardustValue = 100 },  -- 素华碎片
    { quality = 2, type = "shard", heroId = 12, amount = 1, weight = 100, stardustValue = 100 },  -- 艾丝翠德碎片
    { quality = 2, type = "shard", heroId = 13, amount = 1, weight = 100, stardustValue = 100 },  -- 罗莎琳碎片
    { quality = 2, type = "shard", heroId = 14, amount = 1, weight = 100, stardustValue = 100 },  -- 幽夜碎片
    { quality = 2, type = "shard", heroId = 15, amount = 1, weight = 100, stardustValue = 100 },  -- 伊丽莎白碎片
    { quality = 2, type = "shard", heroId = 21, amount = 1, weight = 100, stardustValue = 100 },  -- 亚历克斯碎片
    { quality = 2, type = "shard", heroId = 22, amount = 1, weight = 100, stardustValue = 100 },  -- 赛拉碎片
    { quality = 2, type = "shard", heroId = 23, amount = 1, weight = 100, stardustValue = 100 },  -- 艾尔温碎片

    -- SSR 品质（9 角色）
    { quality = 3, type = "hero", heroId = 10, weight = 100, stardustValue = 1000 }, -- 丽贝卡
    { quality = 3, type = "hero", heroId = 11, weight = 100, stardustValue = 1000 }, -- 素华
    { quality = 3, type = "hero", heroId = 12, weight = 100, stardustValue = 1000 }, -- 艾丝翠德
    { quality = 3, type = "hero", heroId = 13, weight = 100, stardustValue = 1000 }, -- 罗莎琳
    { quality = 3, type = "hero", heroId = 14, weight = 100, stardustValue = 1000 }, -- 幽夜
    { quality = 3, type = "hero", heroId = 15, weight = 100, stardustValue = 1000 }, -- 伊丽莎白
    { quality = 3, type = "hero", heroId = 21, weight = 100, stardustValue = 1000 }, -- 亚历克斯
    { quality = 3, type = "hero", heroId = 22, weight = 100, stardustValue = 1000 }, -- 赛拉
    { quality = 3, type = "hero", heroId = 23, weight = 100, stardustValue = 1000 }, -- 艾尔温
}

-- ======================== 预计算：按品质分组 + 总权重 ========================

GachaConfig._poolByQuality = {}  -- quality → { items, totalWeight }

local function _buildPoolIndex()
    GachaConfig._poolByQuality = {}
    for _, item in ipairs(GachaConfig.Pool) do
        local q = item.quality
        if not GachaConfig._poolByQuality[q] then
            GachaConfig._poolByQuality[q] = { items = {}, totalWeight = 0 }
        end
        local group = GachaConfig._poolByQuality[q]
        group.items[#group.items + 1] = item
        group.totalWeight = group.totalWeight + item.weight
    end
end

_buildPoolIndex()

--- 获取指定品质的物品列表和总权重
---@param quality number
---@return table|nil  { items, totalWeight }
function GachaConfig.getPoolGroup(quality)
    return GachaConfig._poolByQuality[quality]
end

return GachaConfig
