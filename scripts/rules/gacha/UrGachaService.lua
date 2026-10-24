-- ============================================================================
-- UrGachaService.lua - 星辰招募（UR 卡池）抽卡逻辑
-- ============================================================================

local PDM            = require("rules.character.PlayerDataManager")
local UrGachaConfig  = require("config.UrGachaConfig")
local TaskService    = require("rules.task.TaskService")
local HeroService    = require("rules.hero.HeroService")
local HeroShardService = require("rules.hero.HeroShardService")

local UrGachaService = {}

local function ensurePoolStats(currency, poolId)
    if type(currency.gachaDrawStats) ~= "table" then currency.gachaDrawStats = {} end
    if type(currency.gachaDrawStats[poolId]) ~= "table" then currency.gachaDrawStats[poolId] = {} end
    local stats = currency.gachaDrawStats[poolId]
    stats.total = tonumber(stats.total) or 0
    stats.single = tonumber(stats.single) or 0
    stats.ten = tonumber(stats.ten) or 0
    stats.ticket = tonumber(stats.ticket) or 0
    stats.diamond = tonumber(stats.diamond) or 0
    if type(stats.byQuality) ~= "table" then stats.byQuality = {} end
    if type(stats.byType) ~= "table" then stats.byType = {} end
    if type(stats.byHero) ~= "table" then stats.byHero = {} end
    return stats
end

local function addCount(map, key, amount)
    key = tostring(key or "unknown")
    map[key] = (tonumber(map[key]) or 0) + (amount or 1)
end

local function recordDrawStats(currency, poolId, count, ticketDraws, diamondDraws, results)
    local stats = ensurePoolStats(currency, poolId)
    stats.total = stats.total + count
    if count == 10 then
        stats.ten = stats.ten + 1
    elseif count == 1 then
        stats.single = stats.single + 1
    end
    stats.ticket = stats.ticket + (tonumber(ticketDraws) or 0)
    stats.diamond = stats.diamond + (tonumber(diamondDraws) or 0)

    for _, item in ipairs(results or {}) do
        addCount(stats.byQuality, item.quality or 0, 1)
        addCount(stats.byType, item.type or "unknown", 1)
        if item.heroId then addCount(stats.byHero, item.heroId, 1) end
    end
end

local function rollItemInQuality(quality)
    local group = UrGachaConfig.getPoolGroup(quality)
    if not group or #group.items == 0 then return nil end
    local roll = math.random() * group.totalWeight
    local acc = 0
    for _, item in ipairs(group.items) do
        acc = acc + item.weight
        if roll <= acc then return item end
    end
    return group.items[#group.items]
end

local function rollStellarQuality(currency)
    local Q = UrGachaConfig
    currency.urPityUR  = (currency.urPityUR  or 0) + 1
    currency.urPitySSR = (currency.urPitySSR or 0) + 1
    currency.urPitySR  = (currency.urPitySR  or 0) + 1

    if currency.urPityUR >= Q.Pity.UR_THRESHOLD then
        currency.urPityUR = 0
        currency.urPitySSR = 0
        currency.urPitySR = 0
        return Q.QUALITY_UR
    end
    if currency.urPitySSR >= Q.Pity.SSR_THRESHOLD then
        currency.urPitySSR = 0
        currency.urPitySR = 0
        return Q.QUALITY_SSR
    end
    if currency.urPitySR >= Q.Pity.SR_THRESHOLD then
        currency.urPitySR = 0
        return Q.QUALITY_SR
    end

    local roll = math.random() * 100
    local cum = 0
    local tiers = {
        { q = Q.QUALITY_UR,  p = Q.Probability[Q.QUALITY_UR]  or 0 },
        { q = Q.QUALITY_SSR, p = Q.Probability[Q.QUALITY_SSR] or 0 },
        { q = Q.QUALITY_SR,  p = Q.Probability[Q.QUALITY_SR]  or 0 },
        { q = Q.QUALITY_R,   p = Q.Probability[Q.QUALITY_R]   or 0 },
    }
    for _, t in ipairs(tiers) do
        cum = cum + t.p
        if roll <= cum then
            if t.q >= Q.QUALITY_UR then
                currency.urPityUR = 0
                currency.urPitySSR = 0
                currency.urPitySR = 0
            elseif t.q >= Q.QUALITY_SSR then
                currency.urPitySSR = 0
                currency.urPitySR = 0
            elseif t.q >= Q.QUALITY_SR then
                currency.urPitySR = 0
            end
            return t.q
        end
    end
    return Q.QUALITY_R
end

--- 星辰招募抽卡
---@param uid number
---@param count number|nil
---@param payType string|nil "ticket"|"diamond"
---@return boolean ok, string? err, table? result
function UrGachaService.Pull(uid, count, payType)
    local heroes   = PDM.GetModule(uid, "heroes")
    local currency = PDM.GetModule(uid, "currency")
    local battle   = PDM.GetModule(uid, "battle")
    if not heroes or not currency then
        return false, "数据未加载"
    end

    local unlocked, unlockReason = UrGachaConfig.checkPoolUnlocked(currency, heroes.roster, battle)
    if not unlocked then
        return false, unlockReason or "星辰招募尚未开放"
    end

    count = count == nil and 1 or tonumber(count)
    if count ~= 1 and count ~= 10 then return false, "招募次数只能为1或10" end
    local liveHeroes, liveCurrency = heroes, currency
    heroes = HeroShardService.CopyHeroes(liveHeroes)
    currency = HeroShardService.CopyTable(liveCurrency)

    payType = payType or "diamond"
    local ticketCost = (count == 10) and UrGachaConfig.Cost.TEN_TICKET or UrGachaConfig.Cost.SINGLE_TICKET
    local ticketsToUse = 0
    local diamondNeeded = 0

    if payType == "ticket" then
        if (currency.stellarRecruitTicket or 0) < ticketCost then
            return false, "星辰招募券不足（需要 " .. ticketCost .. "）"
        end
        ticketsToUse = ticketCost
    else
        payType = "diamond"
        local available = currency.stellarRecruitTicket or 0
        ticketsToUse = math.min(available, ticketCost)
        local shortfall = ticketCost - ticketsToUse
        diamondNeeded = shortfall * UrGachaConfig.Cost.SINGLE_DIAMOND
        if (currency.gems or 0) < diamondNeeded then
            return false, "黑晶不足（需要 " .. diamondNeeded .. "）"
        end
    end

    if ticketsToUse > 0 then
        currency.stellarRecruitTicket = (currency.stellarRecruitTicket or 0) - ticketsToUse
    end
    if diamondNeeded > 0 then
        currency.gems = currency.gems - diamondNeeded
    end

    local results = {}
    for i = 1, count do
        local quality = rollStellarQuality(currency)
        local poolItem = rollItemInQuality(quality)
        if not poolItem or poolItem.type ~= "hero" then
            return false, "星辰招募奖励配置异常"
        end
        local plan, planErr = HeroShardService.PlanHeroFor(heroes, currency, poolItem.heroId,
            { startLevel = HeroService.GetNewHeroStartLevel(uid) })
        if not plan then return false, planErr end
        local applied, applyErr = HeroShardService.ApplyTo(heroes, currency, plan)
        if not applied then return false, applyErr end
        results[#results + 1] = {
            type = plan.type, heroId = plan.heroId, quality = poolItem.quality,
            isNew = plan.isNew, index = i, shardGain = plan.shardGain, amount = plan.amount,
            tavernCoin = plan.tavernCoin, overflowShards = plan.overflowShards,
        }
    end

    recordDrawStats(currency, UrGachaConfig.POOL_ID, count, ticketsToUse, ticketCost - ticketsToUse, results)

    -- 奖励全部规划成功后统一提交，非法库存/币溢出不消耗券与保底。
    HeroShardService.CommitRoster(liveHeroes, heroes)
    for key, value in pairs(currency) do liveCurrency[key] = value end
    heroes, currency = liveHeroes, liveCurrency

    PDM.MarkDirty(uid, "currency")
    PDM.MarkDirty(uid, "heroes")
    -- 高价值操作：立即落盘，避免 mod_currency（保底）与 mod_heroes（碎片）跨 key 分裂存档
    PDM.FlushImmediate(uid)

    TaskService.UpdateProgress(uid, "recruit", count)
    TaskService.UpdateProgress(uid, "stellar_recruit", count)
    TaskService.RefreshAchievements(uid)

    print("[UrGachaService] PULL uid=" .. tostring(uid)
        .. " count=" .. count .. " payType=" .. payType
        .. " stellarTickets=" .. ticketsToUse .. " diamonds=" .. diamondNeeded)

    return true, nil, {
        gachaResults = results,
        totalCost    = diamondNeeded,
        payType      = payType,
        poolId       = UrGachaConfig.POOL_ID,
        pity = {
            poolId   = UrGachaConfig.POOL_ID,
            sinceSR  = currency.urPitySR or 0,
            sinceSSR = currency.urPitySSR or 0,
            sinceUR  = currency.urPityUR or 0,
        },
    }
end

--- 兼容旧接口：星辰招募已停用指定UP，统一按卡池权重抽取
---@param uid number
---@param heroId number
---@return boolean ok, string? err
function UrGachaService.SetTargetUp(uid, heroId)
    return false, "指定UR功能已停用，星辰招募按卡池权重随机抽取"
end

return UrGachaService
