-- ============================================================================
-- UrGachaService.lua - 星辉招募（UR 卡池）抽卡逻辑
-- ============================================================================

local PDM            = require("server.character.PlayerDataManager")
local UrGachaConfig  = require("config.UrGachaConfig")
local HeroConfig     = require("config.HeroConfig")
local ExpTable       = require("config.ExpTable")
local TaskService    = require("server.task.TaskService")
local HeroService    = require("server.hero.HeroService")

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

local function findItemInQuality(quality, heroId)
    local group = UrGachaConfig.getPoolGroup(quality)
    if not group or #group.items == 0 then return nil end
    heroId = tonumber(heroId)
    if not heroId then return nil end
    for _, item in ipairs(group.items) do
        if item.type == "hero" and item.heroId == heroId then
            return item
        end
    end
    return nil
end

local function rollItemInQuality(quality, currency)
    if quality == UrGachaConfig.QUALITY_UR and currency and currency.stellarTargetUpHeroId then
        local targetItem = findItemInQuality(quality, currency.stellarTargetUpHeroId)
        local targetRate = UrGachaConfig.TargetUp and UrGachaConfig.TargetUp.UR_TARGET_RATE or 50
        if targetItem and math.random() * 100 <= targetRate then
            print("[UrGachaService] 指定UP命中 heroId=" .. tostring(currency.stellarTargetUpHeroId))
            return targetItem
        end
    end

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

local function grantHeroResult(uid, heroes, currency, poolItem, index, results)
    local heroId = poolItem.heroId
    local heroEntry = heroes.roster[heroId]
    local isNew = not heroEntry or not heroEntry.level
    if isNew then
        local existingShards = heroEntry and heroEntry.shards or 0
        local cfg = HeroConfig.get(heroId)
        local startLv = HeroService.GetNewHeroStartLevel(uid)
        heroes.roster[heroId] = {
            level = startLv, exp = 0,
            maxExp = ExpTable.getHeroExpForLevel(startLv) or 0,
            classId = cfg and cfg.classId or 1,
            dupeCount = 0,
            shards = existingShards,
            _shardMigrated = true,
        }
        results[#results + 1] = {
            type = "hero", heroId = heroId, quality = poolItem.quality,
            isNew = true, index = index,
        }
        return
    end

    local hero = heroes.roster[heroId]
    local awakeCount = 0
    if hero.awakening then
        for _ in pairs(hero.awakening) do awakeCount = awakeCount + 1 end
    end

    if awakeCount >= 7 then
        local heroCfg = HeroConfig.get(heroId)
        if heroCfg and tonumber(heroCfg.quality) == HeroConfig.QUALITY_UR then
            -- UR满觉醒后仍保留为碎片，不自动分解为酒馆币
            local shardGain = HeroConfig.SHARD_DUPE_CONVERT
            hero.shards = (hero.shards or 0) + shardGain
            results[#results + 1] = {
                type = "dupe_to_shard", heroId = heroId, quality = poolItem.quality,
                shardGain = shardGain, index = index,
            }
        else
            local tavernCoins = poolItem.stardustValue or 0
            currency.tavernCoin = (currency.tavernCoin or 0) + tavernCoins
            results[#results + 1] = {
                type = "decompose", heroId = heroId, quality = poolItem.quality,
                tavernCoin = tavernCoins, index = index,
            }
        end
    else
        local shardGain = HeroConfig.SHARD_DUPE_CONVERT
        hero.shards = (hero.shards or 0) + shardGain
        results[#results + 1] = {
            type = "dupe_to_shard", heroId = heroId, quality = poolItem.quality,
            shardGain = shardGain, index = index,
        }
    end
end

--- 星辉招募抽卡
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
        return false, unlockReason or "星辉招募尚未开放"
    end

    count = tonumber(count) or 1
    if count < 1 then count = 1 end
    if count > 10 then count = 10 end

    payType = payType or "diamond"
    local ticketCost = (count == 10) and UrGachaConfig.Cost.TEN_TICKET or UrGachaConfig.Cost.SINGLE_TICKET
    local ticketsToUse = 0
    local diamondNeeded = 0

    if payType == "ticket" then
        if (currency.stellarRecruitTicket or 0) < ticketCost then
            return false, "星辉招募券不足（需要 " .. ticketCost .. "）"
        end
        ticketsToUse = ticketCost
    else
        payType = "diamond"
        local available = currency.stellarRecruitTicket or 0
        ticketsToUse = math.min(available, ticketCost)
        local shortfall = ticketCost - ticketsToUse
        diamondNeeded = shortfall * UrGachaConfig.Cost.SINGLE_DIAMOND
        if (currency.gems or 0) < diamondNeeded then
            return false, "钻石不足（需要 " .. diamondNeeded .. "）"
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
        local poolItem = rollItemInQuality(quality, currency)
        if poolItem and poolItem.type == "hero" then
            grantHeroResult(uid, heroes, currency, poolItem, i, results)
        else
            results[#results + 1] = {
                type = "hero", heroId = UrGachaConfig.getUpHeroId(),
                quality = UrGachaConfig.QUALITY_UR, isNew = false, index = i,
            }
            print("[UrGachaService] WARNING: 无池条目 quality=" .. tostring(quality))
        end
    end

    recordDrawStats(currency, UrGachaConfig.POOL_ID, count, ticketsToUse, ticketCost - ticketsToUse, results)

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

--- 设置星辉指定UP角色
---@param uid number
---@param heroId number
---@return boolean ok, string? err
function UrGachaService.SetTargetUp(uid, heroId)
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId then return false, "缺少角色ID" end

    local hero = HeroConfig.HEROES[heroId]
    if not hero then return false, "角色不存在" end
    if hero.quality ~= (HeroConfig.QUALITY_UR or 4) then
        return false, "只能指定UR角色"
    end
    if not findItemInQuality(UrGachaConfig.QUALITY_UR, heroId) then
        return false, "该UR角色不在星辉卡池中"
    end

    currency.stellarTargetUpHeroId = heroId
    PDM.MarkDirty(uid, "currency")

    print("[UrGachaService] SetTargetUp uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId))
    return true
end

return UrGachaService
