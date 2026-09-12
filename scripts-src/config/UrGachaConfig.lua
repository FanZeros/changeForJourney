-- ============================================================================
-- UrGachaConfig.lua - 星辉招募（UR 限定卡池）配置
-- 规则文档：docs/配置文件/建筑-酒馆招募.txt
-- ============================================================================

local HC = require("config.HeroConfig")

local UrGachaConfig = {}

UrGachaConfig.POOL_ID   = "stellar"
UrGachaConfig.POOL_NAME = "星辉招募"

-- ======================== 开放条件 ========================

UrGachaConfig.Unlock = {
    --- 通关进度达到地狱首关（7001）即开放星辉招募
    HELL_FIRST_STAGE = 7001,
}

-- ======================== 消耗 ========================

UrGachaConfig.Cost = {
    SINGLE_TICKET  = 1,
    TEN_TICKET     = 10,
    SINGLE_DIAMOND = 900,
    TEN_DIAMOND    = 9000,
}

--- 市场商店星辉券商品 id（8 折 720 钻，每日限购；与酒馆钻石快速补券独立）
UrGachaConfig.Market = {
    STELLAR_DIAMOND_ITEM_ID = 18,
}

-- ======================== 品质与概率 ========================

UrGachaConfig.QUALITY_R   = 1
UrGachaConfig.QUALITY_SR  = 2
UrGachaConfig.QUALITY_SSR = 3
UrGachaConfig.QUALITY_UR  = 4

UrGachaConfig.Probability = {
    [UrGachaConfig.QUALITY_R]   = 52.0,
    [UrGachaConfig.QUALITY_SR]  = 41.0,
    [UrGachaConfig.QUALITY_SSR] = 5.0,
    [UrGachaConfig.QUALITY_UR]  = 1.0,
}

-- ======================== 保底（独立计数，见 currency.urPity*） ========================

UrGachaConfig.Pity = {
    SR_THRESHOLD  = 10,
    SSR_THRESHOLD = 60,
    UR_THRESHOLD  = 120,
}

-- ======================== 满觉醒分解（整卡→酒馆币） ========================

UrGachaConfig.StardustValue = {
    [UrGachaConfig.QUALITY_R]   = 50,
    [UrGachaConfig.QUALITY_SR]  = 250,
    [UrGachaConfig.QUALITY_SSR] = 1000,
    [UrGachaConfig.QUALITY_UR]  = 4500,
}

--- 满觉醒碎片分解（酒馆币/片）
UrGachaConfig.ShardStardustValue = {
    [16] = 450,
    [20] = 450,
}

-- ======================== 卡池（仅整卡，无碎片条目） ========================

UrGachaConfig.Pool = {
    { quality = 1, type = "hero", heroId = 1,  weight = 100, stardustValue = 50 },
    { quality = 1, type = "hero", heroId = 2,  weight = 100, stardustValue = 50 },
    { quality = 1, type = "hero", heroId = 3,  weight = 100, stardustValue = 50 },
    { quality = 2, type = "hero", heroId = 4,  weight = 100, stardustValue = 250 },
    { quality = 2, type = "hero", heroId = 5,  weight = 100, stardustValue = 250 },
    { quality = 2, type = "hero", heroId = 6,  weight = 100, stardustValue = 250 },
    { quality = 2, type = "hero", heroId = 7,  weight = 100, stardustValue = 250 },
    { quality = 2, type = "hero", heroId = 8,  weight = 100, stardustValue = 250 },
    { quality = 2, type = "hero", heroId = 9,  weight = 100, stardustValue = 250 },
    { quality = 3, type = "hero", heroId = 10, weight = 100, stardustValue = 1000 },
    { quality = 3, type = "hero", heroId = 11, weight = 100, stardustValue = 1000 },
    { quality = 3, type = "hero", heroId = 12, weight = 100, stardustValue = 1000 },
    { quality = 3, type = "hero", heroId = 13, weight = 100, stardustValue = 1000 },
    { quality = 3, type = "hero", heroId = 14, weight = 100, stardustValue = 1000 },
    { quality = 3, type = "hero", heroId = 15, weight = 100, stardustValue = 1000 },
    { quality = 3, type = "hero", heroId = 21, weight = 100, stardustValue = 1000 },
    { quality = 3, type = "hero", heroId = 22, weight = 100, stardustValue = 1000 },
    { quality = 3, type = "hero", heroId = 23, weight = 100, stardustValue = 1000 },
    { quality = 4, type = "hero", heroId = 16, weight = 100, stardustValue = 4500 },
    { quality = 4, type = "hero", heroId = 20, weight = 100, stardustValue = 4500 },
}

UrGachaConfig._poolByQuality = {}

local function _buildPoolIndex()
    UrGachaConfig._poolByQuality = {}
    for _, item in ipairs(UrGachaConfig.Pool) do
        local q = item.quality
        if not UrGachaConfig._poolByQuality[q] then
            UrGachaConfig._poolByQuality[q] = { items = {}, totalWeight = 0 }
        end
        local group = UrGachaConfig._poolByQuality[q]
        group.items[#group.items + 1] = item
        group.totalWeight = group.totalWeight + item.weight
    end
end

_buildPoolIndex()

function UrGachaConfig.getPoolGroup(quality)
    return UrGachaConfig._poolByQuality[quality]
end

--- 满觉醒单枚碎片分解为酒馆币（非整卡 stardustValue；整卡=10片时约为整卡值/10）
---@param heroId number
---@return number
function UrGachaConfig.getShardStardustValue(heroId)
    heroId = tonumber(heroId)
    if not heroId then return 0 end

    if UrGachaConfig.ShardStardustValue[heroId] then
        return UrGachaConfig.ShardStardustValue[heroId]
    end

    local GachaConfig = require("config.GachaConfig")
    for _, entry in ipairs(GachaConfig.Pool) do
        if entry.heroId == heroId and entry.type == "shard" then
            return entry.stardustValue or 0
        end
    end

    -- 无碎片条目时：整卡满觉醒分解值 / 重复转化片数（默认 10 片）
    local dupeShards = HC.SHARD_DUPE_CONVERT or 10
    for _, entry in ipairs(UrGachaConfig.Pool) do
        if entry.heroId == heroId and entry.type == "hero" then
            local full = entry.stardustValue or 0
            if full > 0 then
                return math.floor(full / dupeShards + 0.5)
            end
        end
    end
    for _, entry in ipairs(GachaConfig.Pool) do
        if entry.heroId == heroId and entry.type == "hero" then
            local full = entry.stardustValue or 0
            if full > 0 then
                return math.floor(full / dupeShards + 0.5)
            end
        end
    end
    return 0
end

-- ======================== 指定UP角色 ========================

UrGachaConfig.TargetUp = {
    UR_TARGET_RATE = 50,  -- 抽到 UR 时，50% 概率转为玩家指定的 UP 角色
}

-- ======================== UI 资产 ========================

UrGachaConfig.UI = {
    bgPath          = "image/UI_KCBJ_2.png",
    poolTabPath     = "image/UI_KCFL_2.png",
    ticketIconPath  = "image/UI_icon_ZMQ2_X.png",
    portraitPattern = "image/KCLH_%d.png",
    portraitCx      = 540,
    portraitCy      = 1145,
    poolTabCx       = 249,
    poolTabCy       = 558,
    poolTextX       = 80,
    poolTextY       = 591,
}

-- ======================== 当期 UP ========================

UrGachaConfig.UP = {
    heroId  = 20,
    name    = "梅丽莎",
    endTime = nil,
}

function UrGachaConfig.getUpHeroId()
    return UrGachaConfig.UP.heroId or 20
end

function UrGachaConfig.getUpHeroName()
    if UrGachaConfig.UP.name and UrGachaConfig.UP.name ~= "" then
        return UrGachaConfig.UP.name
    end
    local cfg = HC.get(UrGachaConfig.getUpHeroId())
    return cfg and cfg.name or "未知"
end

function UrGachaConfig.getUpPortraitPath(heroId)
    heroId = heroId or UrGachaConfig.getUpHeroId()
    return string.format(UrGachaConfig.UI.portraitPattern, heroId)
end

function UrGachaConfig.setUpHero(heroId, opts)
    UrGachaConfig.UP.heroId = heroId
    if opts then
        if opts.name ~= nil then UrGachaConfig.UP.name = opts.name end
        if opts.endTime ~= nil then UrGachaConfig.UP.endTime = opts.endTime end
    end
end

function UrGachaConfig.getTimeDisplayText()
    return "永久"
end

--- 星辉池是否已解锁（进入地狱难度后开放）
---@param currency table|nil  保留兼容，未使用
---@param roster table|nil    保留兼容，未使用
---@param battle table|nil    需含 maxStageId
---@return boolean
---@return string|nil reason
function UrGachaConfig.checkPoolUnlocked(currency, roster, battle)
    battle = battle or {}
    local maxStageId = tonumber(battle.maxStageId) or 0
    if maxStageId >= UrGachaConfig.Unlock.HELL_FIRST_STAGE then
        return true
    end
    return false, "进入地狱难度后开放"
end

function UrGachaConfig.isPoolEnabled()
    return UrGachaConfig._enabled ~= false
end

function UrGachaConfig.setPoolEnabled(enabled)
    UrGachaConfig._enabled = enabled
end

return UrGachaConfig
