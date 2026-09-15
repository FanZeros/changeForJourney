-- ============================================================================
-- GachaService - 抽卡/招募业务逻辑
-- 职责: 扭蛋抽卡、保底计算、产出英雄/资源
-- 层级: server/gacha  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local GachaConfig     = require("config.GachaConfig")
local UrGachaConfig   = require("config.UrGachaConfig")
local UrGachaService  = require("server.gacha.UrGachaService")
local HeroConfig      = require("config.HeroConfig")
local ExpTable        = require("config.ExpTable")
local TaskService     = require("server.task.TaskService")
local HeroService     = require("server.hero.HeroService")

local GachaService = {}

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

-- ======================== 抽卡核心 ========================

--- 扭蛋抽卡（支持招募券或钻石支付）
---@param uid number
---@param count number|nil 抽取次数(1-10)
---@param payType string|nil "ticket"|"diamond"
---@param poolId string|nil "standard"|"stellar"
---@return boolean ok, string? err, table? result
function GachaService.GachaPull(uid, count, payType, poolId)
    poolId = poolId or "standard"
    if poolId == UrGachaConfig.POOL_ID or poolId == "stellar" then
        return UrGachaService.Pull(uid, count, payType)
    end

    local heroes   = PDM.GetModule(uid, "heroes")
    local currency = PDM.GetModule(uid, "currency")
    local session  = PDM.GetModule(uid, "session")
    if not heroes or not currency or not session then
        return false, "数据未加载"
    end

    count = tonumber(count) or 1
    if count < 1 then count = 1 end
    if count > 10 then count = 10 end

    -- 判断支付方式（diamond 模式下优先消耗已有招募券，不足部分用钻石补）
    payType = payType or "diamond"
    local ticketCost = (count == 10) and GachaConfig.Cost.TEN_TICKET or GachaConfig.Cost.SINGLE_TICKET

    local ticketsToUse  = 0
    local diamondNeeded = 0

    if payType == "ticket" then
        if (currency.recruitTicket or 0) < ticketCost then
            return false, "招募券不足（需要 " .. ticketCost .. "）"
        end
        ticketsToUse = ticketCost
    else
        payType = "diamond"
        local available  = currency.recruitTicket or 0
        ticketsToUse     = math.min(available, ticketCost)
        local shortfall  = ticketCost - ticketsToUse
        diamondNeeded    = shortfall * GachaConfig.Cost.SINGLE_DIAMOND
        if (currency.gems or 0) < diamondNeeded then
            return false, "钻石不足（需要 " .. diamondNeeded .. "）"
        end
    end

    -- === 快照（回滚用） ===
    local oldTickets      = currency.recruitTicket or 0
    local oldGems         = currency.gems
    local oldPitySR       = currency.gachaPitySR or 0
    local oldPitySSR      = currency.gachaPitySSR or 0
    local addedHeroIds    = {}

    -- === 扣费（混合支付：先扣券再扣钻石） ===
    if ticketsToUse > 0 then
        currency.recruitTicket = (currency.recruitTicket or 0) - ticketsToUse
    end
    if diamondNeeded > 0 then
        currency.gems = currency.gems - diamondNeeded
    end

    -- 保底配置
    local SR_THRESHOLD      = GachaConfig.Pity and GachaConfig.Pity.SR_THRESHOLD or 10
    local SSR_THRESHOLD     = GachaConfig.Pity and GachaConfig.Pity.SSR_THRESHOLD or 80
    local SSR_SOFT_START    = GachaConfig.Pity and GachaConfig.Pity.SSR_SOFT_PITY_START or 60
    local SSR_SOFT_RATE     = GachaConfig.Pity and GachaConfig.Pity.SSR_SOFT_PITY_RATE or 6.0
    local QUALITY_N   = GachaConfig.QUALITY_N   or 0
    local QUALITY_R   = GachaConfig.QUALITY_R   or 1
    local QUALITY_SR  = GachaConfig.QUALITY_SR  or 2
    local QUALITY_SSR = GachaConfig.QUALITY_SSR or 3

    -- ===== 新手首次十连保底 =====
    -- 新玩家第一次进行十连抽时，第 1 抽强制产出一名 SR 英雄（heroId 4~9）
    local SR_HERO_IDS = {4, 5, 6, 7, 8, 9}  -- 全部 SR 英雄 ID
    local isFirstTenPull   = (count == 10) and session and not session.firstGachaTenDone
    local forcedSRHeroId   = nil
    local forcedSRPoolItem = nil
    if isFirstTenPull then
        forcedSRHeroId = SR_HERO_IDS[math.random(#SR_HERO_IDS)]
        -- 预查 Pool，找到对应的 SR 英雄词条
        for _, item in ipairs(GachaConfig.Pool) do
            if item.type == "hero" and item.heroId == forcedSRHeroId and item.quality == QUALITY_SR then
                forcedSRPoolItem = item
                break
            end
        end
        -- 兜底：若指定英雄不在 Pool 中（配置变更），从 SR Pool 中随机取一个英雄词条
        if not forcedSRPoolItem then
            local srGroup = GachaConfig.getPoolGroup(QUALITY_SR)
            if srGroup and srGroup.items then
                for _, item in ipairs(srGroup.items) do
                    if item.type == "hero" then
                        forcedSRPoolItem = item
                        forcedSRHeroId   = item.heroId
                        break
                    end
                end
            end
        end
        print("[GachaService] 新手首次十连保底触发: uid=" .. tostring(uid)
            .. " 强制SR英雄 heroId=" .. tostring(forcedSRHeroId))
    end

    --- 按保底 + 概率决定品质（使用扁平字段 gachaPitySR / gachaPitySSR）
    --- 软保底：第 SSR_SOFT_START 抽后，每多一抽 SSR 概率 +SSR_SOFT_RATE%
    local function rollQuality()
        currency.gachaPitySSR = (currency.gachaPitySSR or 0) + 1
        currency.gachaPitySR  = (currency.gachaPitySR  or 0) + 1

        -- SSR 硬保底
        if currency.gachaPitySSR >= SSR_THRESHOLD then
            currency.gachaPitySSR = 0
            currency.gachaPitySR  = 0
            return QUALITY_SSR
        end

        -- SR 保底
        if currency.gachaPitySR >= SR_THRESHOLD then
            currency.gachaPitySR = 0
            return QUALITY_SR
        end

        -- 计算动态 SSR 概率（软保底）
        local baseSSR = GachaConfig.Probability[QUALITY_SSR] or 1.0
        local sinceSSR = currency.gachaPitySSR  -- 已在上方 +1
        local bonusSSR = math.max(0, sinceSSR - SSR_SOFT_START) * SSR_SOFT_RATE
        local effectiveSSR = math.min(baseSSR + bonusSSR, 100)

        -- 重建概率表：SSR 提升的部分从 N 中扣除
        local probSSR = effectiveSSR
        local probSR  = GachaConfig.Probability[QUALITY_SR] or 10.0
        local probR   = GachaConfig.Probability[QUALITY_R] or 18.0
        local probN   = math.max(0, 100 - probSSR - probSR - probR)

        local roll = math.random() * 100
        local cumulative = 0
        local probs = {
            { q = QUALITY_SSR, p = probSSR },
            { q = QUALITY_SR,  p = probSR },
            { q = QUALITY_R,   p = probR },
            { q = QUALITY_N,   p = probN },
        }
        for _, entry in ipairs(probs) do
            cumulative = cumulative + entry.p
            if roll <= cumulative then
                if entry.q >= QUALITY_SSR then
                    currency.gachaPitySSR = 0
                    currency.gachaPitySR  = 0
                elseif entry.q >= QUALITY_SR then
                    currency.gachaPitySR = 0
                end
                return entry.q
            end
        end
        return QUALITY_N
    end

    local results = {}
    for i = 1, count do
        local quality
        local poolItem

        if isFirstTenPull and i == 1 then
            -- ===== 新手首次十连：第 1 抽强制 SR 英雄 =====
            -- 手动推进保底计数（与 rollQuality 语义保持一致）
            currency.gachaPitySSR = (currency.gachaPitySSR or 0) + 1
            currency.gachaPitySR  = (currency.gachaPitySR  or 0) + 1
            currency.gachaPitySR  = 0   -- SR 到手，重置 SR 保底计数
            quality  = QUALITY_SR
            poolItem = forcedSRPoolItem
        else
            -- ===== 正常抽取：概率 + 保底 =====
            quality = rollQuality()

            -- 从对应品质的统一卡池中按权重抽取
            local group = GachaConfig.getPoolGroup(quality)
            if group and #group.items > 0 then
                -- 指定招募：命中 SSR 时检查是否强制产出目标英雄
                local targetHeroId = currency.targetRecruitHeroId
                local targetRemain = currency.targetRecruitRemain or 0
                if quality == QUALITY_SSR and targetHeroId and targetRemain > 0 then
                    -- 递减保底计数
                    currency.targetRecruitRemain = targetRemain - 1
                    if currency.targetRecruitRemain <= 0 then
                        -- 保底触发：强制产出指定英雄
                        for _, item in ipairs(group.items) do
                            if item.type == "hero" and item.heroId == targetHeroId then
                                poolItem = item
                                break
                            end
                        end
                        -- 兜底：若目标英雄不在卡池中（配置变更），正常随机SSR
                        if not poolItem then
                            local roll = math.random() * group.totalWeight
                            local acc = 0
                            for _, item in ipairs(group.items) do
                                acc = acc + item.weight
                                if roll <= acc then poolItem = item; break end
                            end
                            if not poolItem then poolItem = group.items[#group.items] end
                            print("[GachaService] 指定招募目标不在池中,随机SSR uid=" .. tostring(uid))
                        end
                        -- 产出后重置指定招募
                        currency.targetRecruitHeroId = nil
                        currency.targetRecruitRemain = 0
                        print("[GachaService] 指定招募保底触发! uid=" .. tostring(uid) .. " heroId=" .. tostring(targetHeroId))
                    else
                        -- 未到保底，正常随机（但若随机到目标英雄也算完成）
                        local roll = math.random() * group.totalWeight
                        local acc = 0
                        for _, item in ipairs(group.items) do
                            acc = acc + item.weight
                            if roll <= acc then
                                poolItem = item
                                break
                            end
                        end
                        if not poolItem then poolItem = group.items[#group.items] end
                        -- 如果恰好随机到了目标英雄，提前完成指定招募
                        if poolItem and poolItem.type == "hero" and poolItem.heroId == targetHeroId then
                            currency.targetRecruitHeroId = nil
                            currency.targetRecruitRemain = 0
                            print("[GachaService] 指定招募提前命中! uid=" .. tostring(uid) .. " heroId=" .. tostring(targetHeroId))
                        end
                    end
                else
                    -- 无指定招募或非SSR：正常随机
                    local roll = math.random() * group.totalWeight
                    local acc = 0
                    for _, item in ipairs(group.items) do
                        acc = acc + item.weight
                        if roll <= acc then
                            poolItem = item
                            break
                        end
                    end
                    if not poolItem then poolItem = group.items[#group.items] end
                end
            end
        end

        if not poolItem then
            -- 兜底：不应该发生，给 1 碎片（heroId=1）
            results[#results + 1] = {
                type = "shard", heroId = 1, amount = 1,
                quality = quality, index = i,
            }
        elseif poolItem.type == "hero" then
            local heroId = poolItem.heroId
            -- 用 level 字段区分"真正拥有"和"只有碎片存根"
            -- 碎片存根格式：{ shards=N, _shardMigrated=true }，无 level 字段
            local heroEntry = heroes.roster[heroId]
            local isNew = not heroEntry or not heroEntry.level
            if isNew then
                -- 新英雄：解锁（保留已有碎片数量，若存根已存在）
                -- 起始等级 = 冒险等级（确保新招募的英雄不低于冒险等级）
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
                addedHeroIds[#addedHeroIds + 1] = heroId
                results[#results + 1] = {
                    type = "hero", heroId = heroId, quality = poolItem.quality,
                    isNew = true, index = i,
                }
            else
                -- 重复英雄 → 检查是否满觉醒
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
                            shardGain = shardGain, index = i,
                        }
                    else
                        -- 满觉醒：分解为酒馆币（stardustValue）
                        local tavernCoins = poolItem.stardustValue or 0
                        currency.tavernCoin = (currency.tavernCoin or 0) + tavernCoins
                        results[#results + 1] = {
                            type = "decompose", heroId = heroId, quality = poolItem.quality,
                            tavernCoin = tavernCoins, index = i,
                        }
                    end
                else
                    -- 未满觉醒：转化为 10 碎片
                    local shardGain = HeroConfig.SHARD_DUPE_CONVERT
                    hero.shards = (hero.shards or 0) + shardGain
                    results[#results + 1] = {
                        type = "dupe_to_shard", heroId = heroId, quality = poolItem.quality,
                        shardGain = shardGain, index = i,
                    }
                end
            end
        elseif poolItem.type == "shard" then
            -- 碎片产出：确保 roster 条目存在
            local heroId = poolItem.heroId
            local amount = poolItem.amount or 1
            if not heroes.roster[heroId] then
                -- 未拥有的英雄也可以积攒碎片（仅 shards 字段）
                heroes.roster[heroId] = {
                    shards = 0,
                    _shardMigrated = true,
                }
            end
            heroes.roster[heroId].shards = (heroes.roster[heroId].shards or 0) + amount
            results[#results + 1] = {
                type = "shard", heroId = heroId, amount = amount,
                quality = poolItem.quality, index = i,
            }
        end
    end

    -- === 持久化 ===
    PDM.MarkDirty(uid, "currency")
    PDM.MarkDirty(uid, "heroes")
    -- 新手首次十连保底：标记已使用
    if isFirstTenPull and session then
        session.firstGachaTenDone = true
        PDM.MarkDirty(uid, "session")
        print("[GachaService] 新手首次十连保底已消耗: uid=" .. tostring(uid))
    end

    local actualCost = diamondNeeded
    print("[GachaService] PULL uid=" .. tostring(uid)
        .. " count=" .. count .. " payType=" .. payType
        .. " tickets=" .. ticketsToUse .. " diamonds=" .. diamondNeeded
        .. " results=" .. #results)

    -- 任务进度
    TaskService.UpdateProgress(uid, "recruit", count)
    TaskService.RefreshAchievements(uid)

    currency.gachaStandardPulls = (currency.gachaStandardPulls or 0) + count
    recordDrawStats(currency, "standard", count, ticketsToUse, ticketCost - ticketsToUse, results)
    PDM.MarkDirty(uid, "currency")
    PDM.FlushImmediate(uid)

    return true, nil, {
        gachaResults = results,
        totalCost    = actualCost,
        payType      = payType,
        poolId       = "standard",
        pity = { poolId = "standard", sinceSR = currency.gachaPitySR or 0, sinceSSR = currency.gachaPitySSR or 0 },
    }
end

-- ======================== 指定招募 ========================

local TARGET_RECRUIT_PITY = 3  -- 保底次数：3次SSR内必出

--- 设置指定招募目标英雄
--- 更换目标时继承已消耗的保底进度（remain 不重置），仅首次激活时设为满值
---@param uid number
---@param heroId number
---@return boolean ok, string? err
function GachaService.SetTargetRecruit(uid, heroId)
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, "数据未加载" end

    -- 校验英雄ID是否为有效的SSR英雄
    local hero = HeroConfig.HEROES[heroId]
    if not hero then return false, "英雄不存在" end
    if hero.quality ~= (HeroConfig.QUALITY_SSR or 3) then
        return false, "只能指定SSR品质英雄"
    end

    -- 设置指定招募（更换目标时继承剩余计数）
    local prevRemain = currency.targetRecruitRemain or 0
    local prevTarget = currency.targetRecruitHeroId
    currency.targetRecruitHeroId = heroId

    if not prevTarget or prevRemain <= 0 then
        -- 首次激活 或 上一轮保底已触发（remain=0）：初始化为满值
        currency.targetRecruitRemain = TARGET_RECRUIT_PITY
    end
    -- 否则（正在进行中切换目标）：保留当前 remain 不变，继承已消耗的进度

    PDM.MarkDirty(uid, "currency")

    print("[GachaService] SetTargetRecruit uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " remain=" .. tostring(currency.targetRecruitRemain)
        .. " (prev=" .. tostring(prevTarget) .. " prevRemain=" .. tostring(prevRemain) .. ")")
    return true
end

-- ======================== 星辉指定UP角色 ========================

--- 设置星辉指定UP角色
---@param uid number
---@param heroId number
---@return boolean ok, string? err
function GachaService.SetStellarTargetUp(uid, heroId)
    return UrGachaService.SetTargetUp(uid, heroId)
end

return GachaService
