-- CurrencySchema.lua — currency 模块 Schema
-- 所有货币类型

local CurrencySchema = {}

local function normalizeCountMap(map)
    local fixed = {}
    if type(map) == "table" then
        for k, v in pairs(map) do
            fixed[tostring(k)] = math.max(0, math.floor(tonumber(v) or 0))
        end
    end
    return fixed
end

local function normalizePoolStats(stats)
    if type(stats) ~= "table" then stats = {} end
    stats.total = math.max(0, math.floor(tonumber(stats.total) or 0))
    stats.single = math.max(0, math.floor(tonumber(stats.single) or 0))
    stats.ten = math.max(0, math.floor(tonumber(stats.ten) or 0))
    stats.ticket = math.max(0, math.floor(tonumber(stats.ticket) or 0))
    stats.diamond = math.max(0, math.floor(tonumber(stats.diamond) or 0))
    stats.byQuality = normalizeCountMap(stats.byQuality)
    stats.byType = normalizeCountMap(stats.byType)
    stats.byHero = normalizeCountMap(stats.byHero)
    return stats
end

local function normalizeGachaDrawStats(data)
    if type(data.gachaDrawStats) ~= "table" then data.gachaDrawStats = {} end
    data.gachaDrawStats.standard = normalizePoolStats(data.gachaDrawStats.standard)
    data.gachaDrawStats.stellar = normalizePoolStats(data.gachaDrawStats.stellar)
end

CurrencySchema.Fields = {
    currency = {
        pdmKey     = "ModCurrency",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_currency" },
        getDefault = function()
            return {
                gold = 0,
                gems = 0,
                essence = 0,
                enhanceStone = 0,     -- 洗练石（原强化星石）
                degradeStone = 0,     -- （已隐藏，占位保留）
                destroyStone = 0,     -- 点金石（原损毁保护石）
                weaponScroll = 0,     -- 武器卷轴
                offhandScroll = 0,    -- 副手卷轴
                armorScroll = 0,      -- 护甲卷轴
                accessoryScroll = 0,  -- 饰品卷轴
                recruitTicket = 0,
                stellarRecruitTicket = 0,
                goldenKey = 0,
                sweepTicket = 0,
                arenaTicket = 0,
                arenaCoin = 0,
                tavernCoin = 0,
                privilegePoint = 0,
                arcaneDust = 0,       -- 奥术粉尘
                corruptStone = 0,     -- 腐化石
                sacredStone = 0,      -- 神圣石
                speedCardExpireAt = 0,  -- 加速卡到期时间戳（购买即生效，持续24小时）
                privilegeCardOwned = 0, -- 特权卡是否拥有（1=已激活，永久生效）
                privilegeCardDailyGrantDayId = 0, -- 上次发放「每日100特权点」的 UTC+8 日编号
                gachaPitySR  = 0,
                gachaPitySSR = 0,
                gachaStandardPulls = 0,
                gachaDrawStats = {},
                urPitySR  = 0,
                urPitySSR = 0,
                urPityUR  = 0,
                -- 指定招募（保底计数持久化）
                targetRecruitHeroId = nil,  -- 当前指定的SSR英雄ID
                targetRecruitRemain = 0,    -- 剩余保底次数
                stellarTargetUpHeroId = nil, -- 星辉指定UP角色ID（UR命中时50%概率转为该角色）
            }
        end,
        onLoad = function(data)
            if data.arcaneDust == nil then data.arcaneDust = 0 end
            data.arcaneDust = math.max(0, math.floor(tonumber(data.arcaneDust) or 0))
            if data.privilegePoint == nil then data.privilegePoint = 0 end
            data.privilegePoint = math.max(0, math.floor(tonumber(data.privilegePoint) or 0))
            if data.corruptStone == nil then data.corruptStone = 0 end
            data.corruptStone = math.max(0, math.floor(tonumber(data.corruptStone) or 0))
            if data.sacredStone == nil then data.sacredStone = 0 end
            data.sacredStone = math.max(0, math.floor(tonumber(data.sacredStone) or 0))
            if data.stellarRecruitTicket == nil then data.stellarRecruitTicket = 0 end
            if data.goldenKey == nil then data.goldenKey = 0 end
            data.goldenKey = math.max(0, math.floor(tonumber(data.goldenKey) or 0))
            if data.gachaStandardPulls == nil then data.gachaStandardPulls = 0 end
            normalizeGachaDrawStats(data)
            if data.urPitySR == nil then data.urPitySR = 0 end
            if data.urPitySSR == nil then data.urPitySSR = 0 end
            if data.urPityUR == nil then data.urPityUR = 0 end
            if data.stellarTargetUpHeroId ~= nil then data.stellarTargetUpHeroId = tonumber(data.stellarTargetUpHeroId) end
            if data.speedCardExpireAt == nil then data.speedCardExpireAt = 0 end
            data.speedCardExpireAt = math.floor(tonumber(data.speedCardExpireAt) or 0)
            if data.privilegeCardOwned == nil then data.privilegeCardOwned = 0 end
            data.privilegeCardOwned = tonumber(data.privilegeCardOwned) or 0
            if data.privilegeCardDailyGrantDayId == nil then data.privilegeCardDailyGrantDayId = 0 end
            data.privilegeCardDailyGrantDayId = math.floor(tonumber(data.privilegeCardDailyGrantDayId) or 0)
        end,
        desc = "货币系统",
    },
}

return CurrencySchema
