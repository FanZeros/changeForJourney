-- ============================================================================
-- GachaSystem.lua - 抽卡核心逻辑
-- 负责概率计算、保底机制、消耗扣除、结果发放
-- ============================================================================

local GachaConfig    = require("config.GachaConfig")
local GameState      = require("core.GameState")
local EventBus       = require("core.EventBus")
local GameEvents     = require("config.GameEvents")
local CharacterPanel = require("ui.CharacterPanel")

local GachaSystem = {}

-- ======================== 保底计数器 ========================
-- sinceSR: 距离上次出 SR 或更高品质的抽数
-- sinceSSR: 距离上次出 SSR 的抽数

local pityState = {
    sinceSR  = 0,
    sinceSSR = 0,
}

-- ======================== 保底状态接口 ========================

--- 获取 SSR 保底剩余次数
---@return number
function GachaSystem.getSSRPityRemain()
    return GachaConfig.Pity.SSR_THRESHOLD - pityState.sinceSSR
end

--- 获取 SR 保底剩余次数
---@return number
function GachaSystem.getSRPityRemain()
    return GachaConfig.Pity.SR_THRESHOLD - pityState.sinceSR
end

--- 获取原始保底计数
---@return number sinceSR, number sinceSSR
function GachaSystem.getPityCounts()
    return pityState.sinceSR, pityState.sinceSSR
end

--- 获取下一抽的实际 SSR 概率（含软保底加成）
---@return number effectiveSSR 百分比值（如 7.0 表示 7%）
function GachaSystem.getEffectiveSSRRate()
    local nextSSR   = pityState.sinceSSR + 1
    local baseSSR   = GachaConfig.Probability[GachaConfig.QUALITY_SSR] or 1.0
    local softStart = GachaConfig.Pity.SSR_SOFT_PITY_START or 60
    local softRate  = GachaConfig.Pity.SSR_SOFT_PITY_RATE or 6.0
    local bonus     = math.max(0, nextSSR - softStart) * softRate
    return math.min(baseSSR + bonus, 100)
end

--- 设置保底计数（用于存档恢复）
---@param sinceSR number
---@param sinceSSR number
function GachaSystem.setPityCounts(sinceSR, sinceSSR)
    pityState.sinceSR  = sinceSR or 0
    pityState.sinceSSR = sinceSSR or 0
end

-- ======================== 消耗检查 ========================

--- 检查是否有足够资源进行抽卡
---@param count number 抽卡次数（1 或 10）
---@return boolean canPull
---@return string payType "ticket" | "diamond" | "none"
function GachaSystem.canPull(count)
    local ticketCost  = (count == 10) and GachaConfig.Cost.TEN_TICKET  or GachaConfig.Cost.SINGLE_TICKET
    local diamondCost = (count == 10) and GachaConfig.Cost.TEN_DIAMOND or GachaConfig.Cost.SINGLE_DIAMOND

    local tickets  = GameState.getRecruitTicket()
    local diamonds = GameState.getGems()

    if tickets >= ticketCost then
        return true, "ticket"
    elseif diamonds >= diamondCost then
        return true, "diamond"
    else
        return false, "none"
    end
end

--- 扣除抽卡消耗
---@param count number 1 或 10
---@param payType string "ticket" | "diamond"
local function deductCost(count, payType)
    if payType == "ticket" then
        local cost = (count == 10) and GachaConfig.Cost.TEN_TICKET or GachaConfig.Cost.SINGLE_TICKET
        GameState.setRecruitTicket(GameState.getRecruitTicket() - cost)
    elseif payType == "diamond" then
        local cost = (count == 10) and GachaConfig.Cost.TEN_DIAMOND or GachaConfig.Cost.SINGLE_DIAMOND
        GameState.setGems(GameState.getGems() - cost)
    end
end

-- ======================== 概率抽取核心 ========================

--- 在同品质物品池中按权重随机选取一个物品
---@param quality number
---@return table|nil  卡池物品定义
local function rollItemInQuality(quality)
    local group = GachaConfig.getPoolGroup(quality)
    if not group or #group.items == 0 then return nil end

    local roll = math.random() * group.totalWeight
    local cumulative = 0
    for _, item in ipairs(group.items) do
        cumulative = cumulative + item.weight
        if roll <= cumulative then
            return item
        end
    end
    -- 兜底：返回最后一个
    return group.items[#group.items]
end

--- 决定单次抽卡的品质（含硬保底 + 软保底逻辑）
--- 软保底：第 SSR_SOFT_PITY_START 抽后，每多一抽 SSR 概率 +SSR_SOFT_PITY_RATE%
---@return number quality
local function rollQuality()
    -- 注意：客户端 pityState 在 pullOnce() 中更新，这里用 +1 模拟"本次抽取"
    local nextSSR = pityState.sinceSSR + 1
    local nextSR  = pityState.sinceSR + 1

    -- 1. SSR 硬保底判断
    if nextSSR >= GachaConfig.Pity.SSR_THRESHOLD then
        return GachaConfig.QUALITY_SSR
    end

    -- 2. SR 保底判断
    if nextSR >= GachaConfig.Pity.SR_THRESHOLD then
        return GachaConfig.QUALITY_SR
    end

    -- 3. 计算动态 SSR 概率（软保底）
    local baseSSR    = GachaConfig.Probability[GachaConfig.QUALITY_SSR] or 1.0
    local softStart  = GachaConfig.Pity.SSR_SOFT_PITY_START or 60
    local softRate   = GachaConfig.Pity.SSR_SOFT_PITY_RATE or 6.0
    local bonusSSR   = math.max(0, nextSSR - softStart) * softRate
    local effectiveSSR = math.min(baseSSR + bonusSSR, 100)

    -- 重建概率表：SSR 提升的部分从 N 中扣除
    local probSSR = effectiveSSR
    local probSR  = GachaConfig.Probability[GachaConfig.QUALITY_SR] or 10.0
    local probR   = GachaConfig.Probability[GachaConfig.QUALITY_R] or 18.0
    local probN   = math.max(0, 100 - probSSR - probSR - probR)

    local roll = math.random() * 100
    local cumulative = 0
    local probs = {
        { q = GachaConfig.QUALITY_SSR, p = probSSR },
        { q = GachaConfig.QUALITY_SR,  p = probSR },
        { q = GachaConfig.QUALITY_R,   p = probR },
        { q = GachaConfig.QUALITY_N,   p = probN },
    }
    for _, entry in ipairs(probs) do
        cumulative = cumulative + entry.p
        if roll <= cumulative then
            return entry.q
        end
    end

    return GachaConfig.QUALITY_N
end

--- 执行单次抽卡（更新保底计数）
---@return table result { type, quality, heroId?, resType?, amount? }
local function pullOnce()
    local quality = rollQuality()
    local poolItem = rollItemInQuality(quality)

    -- 更新保底计数
    if quality >= GachaConfig.QUALITY_SSR then
        pityState.sinceSSR = 0
        pityState.sinceSR  = 0
    elseif quality >= GachaConfig.QUALITY_SR then
        pityState.sinceSSR = pityState.sinceSSR + 1
        pityState.sinceSR  = 0
    else
        pityState.sinceSSR = pityState.sinceSSR + 1
        pityState.sinceSR  = pityState.sinceSR + 1
    end

    if not poolItem then
        -- 兜底：不应该发生
        return { type = "resource", resType = "gold", amount = 200, quality = 0 }
    end

    -- 构造结果（与 RecruitAnim 需要的格式一致）
    if poolItem.type == "hero" then
        return {
            type    = "hero",
            heroId  = poolItem.heroId,
            quality = poolItem.quality,
        }
    else
        return {
            type    = "resource",
            resType = poolItem.resType,
            amount  = poolItem.amount,
            quality = poolItem.quality,
        }
    end
end

-- ======================== 发放奖励 ========================

--- 将抽卡结果的资源发放到 GameState
---@param results table[]
local function grantRewards(results)
    for _, r in ipairs(results) do
        if r.type == "resource" then
            local amount = r.amount or 1
            if r.resType == "gold" then
                GameState.setGold(GameState.getGold() + amount)
            elseif r.resType == "essence" then
                GameState.setEssence(GameState.getEssence() + amount)
            elseif r.resType == "enhance_star" then
                GameState.setEnhanceStone(GameState.getEnhanceStone() + amount)
            elseif r.resType == "degrade_protect" then
                GameState.setDegradeStone(GameState.getDegradeStone() + amount)
            elseif r.resType == "break_protect" then
                GameState.setDestroyStone(GameState.getDestroyStone() + amount)
            elseif r.resType == "sweep_ticket" then
                GameState.setSweepTicket(GameState.getSweepTicket() + amount)
            end
        end
        -- hero 类型：standalone 模式直接解锁英雄
        if r.type == "hero" and r.heroId then
            if CharacterPanel.addHero then
                CharacterPanel.addHero(r.heroId, 1)
                print("[GachaSystem] 解锁英雄: " .. tostring(r.heroId))
            end
        end
    end
end

-- ======================== 公开接口 ========================

--- 执行抽卡
---@param count number 1 或 10
---@param forcePayType? string 强制指定支付方式（"ticket"|"diamond"），跳过 canPull 检查
---@return table[]|nil results  抽卡结果列表（nil 表示资源不足）
---@return string|nil payType   支付方式
function GachaSystem.pull(count, forcePayType)
    local payType = forcePayType
    if not payType then
        local canDo
        canDo, payType = GachaSystem.canPull(count)
        if not canDo then
            print("[GachaSystem] 资源不足，无法抽卡")
            return nil, nil
        end
    end

    -- 扣除消耗
    deductCost(count, payType)

    -- 执行抽取
    local results = {}
    for i = 1, count do
        results[i] = pullOnce()
    end

    -- 发放奖励
    grantRewards(results)

    -- 日志
    local ssrCount, srCount = 0, 0
    for _, r in ipairs(results) do
        if r.quality == 3 then ssrCount = ssrCount + 1 end
        if r.quality == 2 then srCount = srCount + 1 end
    end
    print(string.format("[GachaSystem] 抽卡 %d 次 (%s) → SSR:%d SR:%d | 保底 SR剩余:%d SSR剩余:%d",
        count, payType, ssrCount, srCount,
        GachaSystem.getSRPityRemain(), GachaSystem.getSSRPityRemain()))

    return results, payType
end

return GachaSystem
