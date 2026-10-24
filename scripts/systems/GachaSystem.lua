-- 抽卡协调器：费用、品质采样、保底推进与奖励交付分别处理。
-- 配置在每次调用时读取，存档恢复仍只读写原有两个保底计数。
local Config = require("config.GachaConfig")
local State = require("core.GameState")
require("core.EventBus")
require("config.GameEvents")
local Heroes = require("ui.character.panel.CharacterPanel")

local Gacha = {}
local pity = { sinceSR = 0, sinceSSR = 0 }

-- 使用方法名而非缓存函数，兼容 GameState 在启动时安装的访问器。
local currencies = {
    gold = { "getGold", "setGold" },
    essence = { "getEssence", "setEssence" },
    enhance_star = { "getEnhanceStone", "setEnhanceStone" },
    degrade_protect = { "getDegradeStone", "setDegradeStone" },
    break_protect = { "getDestroyStone", "setDestroyStone" },
    sweep_ticket = { "getSweepTicket", "setSweepTicket" },
}

local function price(count, tender)
    -- 保留十连价格缺失时退回单抽价的既有选择规则。
    return (count == 10) and Config.Cost["TEN_" .. tender] or Config.Cost["SINGLE_" .. tender]
end

function Gacha.getSSRPityRemain()
    return Config.Pity.SSR_THRESHOLD - pity.sinceSSR
end

function Gacha.getSRPityRemain()
    return Config.Pity.SR_THRESHOLD - pity.sinceSR
end

function Gacha.getPityCounts()
    return pity.sinceSR, pity.sinceSSR
end

function Gacha.setPityCounts(sinceSR, sinceSSR)
    pity.sinceSR, pity.sinceSSR = sinceSR or 0, sinceSSR or 0
end

local function softSSR(nextCount)
    local base = Config.Probability[Config.QUALITY_SSR] or 1.0
    local start = Config.Pity.SSR_SOFT_PITY_START or 60
    local step = Config.Pity.SSR_SOFT_PITY_RATE or 6.0
    local extra = math.max(0, nextCount - start) * step
    return math.min(base + extra, 100)
end

function Gacha.getEffectiveSSRRate()
    return softSSR(pity.sinceSSR + 1)
end

function Gacha.canPull(count)
    local ticketCost, diamondCost = price(count, "TICKET"), price(count, "DIAMOND")
    local tickets, diamonds = State.getRecruitTicket(), State.getGems()
    if tickets >= ticketCost then return true, "ticket" end
    if diamonds >= diamondCost then return true, "diamond" end
    return false, "none"
end

local function charge(count, tender)
    if tender == "ticket" then
        local cost = price(count, "TICKET")
        State.setRecruitTicket(State.getRecruitTicket() - cost)
    elseif tender == "diamond" then
        local cost = price(count, "DIAMOND")
        State.setGems(State.getGems() - cost)
    end
end

-- 硬保底不消耗品质随机数；普通抽取使用按 SSR、SR、R、N 累加的区间。
-- 保留 <= 边界以及超额概率配置的原有优先级，不重新归一概率。
local function sampleQuality()
    local nextSSR, nextSR = pity.sinceSSR + 1, pity.sinceSR + 1
    if nextSSR >= Config.Pity.SSR_THRESHOLD then return Config.QUALITY_SSR end
    if nextSR >= Config.Pity.SR_THRESHOLD then return Config.QUALITY_SR end
    local ssr = softSSR(nextSSR)
    local sr = Config.Probability[Config.QUALITY_SR] or 10.0
    local rare = Config.Probability[Config.QUALITY_R] or 18.0
    local normal = math.max(0, 100 - ssr - sr - rare)
    local roll = math.random() * 100
    -- 在采样后按原顺序读取四个品质，兼容配置的动态访问器。
    local qSSR, qSR, qR, qN = Config.QUALITY_SSR, Config.QUALITY_SR, Config.QUALITY_R, Config.QUALITY_N
    local edge = 0 + ssr
    if roll <= edge then return qSSR end
    edge = edge + sr
    if roll <= edge then return qSR end
    edge = edge + rare
    if roll <= edge then return qR end
    edge = edge + normal
    if roll <= edge then return qN end
    return Config.QUALITY_N
end

local function sampleItem(quality)
    local pool = Config.getPoolGroup(quality)
    if not pool or #pool.items == 0 then return nil end
    local target, weight = math.random() * pool.totalWeight, 0
    for _, entry in ipairs(pool.items) do
        weight = weight + entry.weight
        if target <= weight then return entry end
    end
    return pool.items[#pool.items]
end

local function advancePity(quality)
    if quality >= Config.QUALITY_SSR then
        pity.sinceSSR, pity.sinceSR = 0, 0
    elseif quality >= Config.QUALITY_SR then
        pity.sinceSSR, pity.sinceSR = pity.sinceSSR + 1, 0
    else
        pity.sinceSSR, pity.sinceSR = pity.sinceSSR + 1, pity.sinceSR + 1
    end
end

local function draw()
    local quality = sampleQuality()
    local item = sampleItem(quality)
    -- 空池也推进保底；奖励使用池条目的 quality，而非采样的品质。
    advancePity(quality)
    if not item then
        return { type = "resource", resType = "gold", amount = 200, quality = 0 }
    end
    if item.type == "hero" then
        return { type = "hero", heroId = item.heroId, quality = item.quality }
    end
    return { type = "resource", resType = item.resType, amount = item.amount, quality = item.quality }
end

local function deliver(result)
    if result.type == "resource" then
        local accessor = currencies[result.resType]
        if accessor then
            local amount = result.amount or 1
            State[accessor[2]](State[accessor[1]]() + amount)
        end
    elseif result.type == "hero" and result.heroId and Heroes.addHero then
        result.isNew = Heroes.addHero(result.heroId, 1) == true
        print("[GachaSystem] 解锁英雄: " .. tostring(result.heroId) .. " isNew=" .. tostring(result.isNew))
    end
end

---@param count number
---@param forcePayType? string
---@return table[]|nil, string|nil
function Gacha.pull(count, forcePayType)
    local tender = forcePayType
    if not tender then
        local accepted
        accepted, tender = Gacha.canPull(count)
        if not accepted then
            print("[GachaSystem] 资源不足，无法抽卡")
            return nil, nil
        end
    end
    charge(count, tender)
    local results = {}
    for index = 1, count do results[index] = draw() end
    -- 整批抽取完成后才交付，避免交付通知影响后续抽取的状态。
    for _, result in ipairs(results) do deliver(result) end
    local ssr, sr = 0, 0
    for _, result in ipairs(results) do
        if result.quality == 3 then ssr = ssr + 1 end
        if result.quality == 2 then sr = sr + 1 end
    end
    print(string.format("[GachaSystem] 抽卡 %d 次 (%s) → SSR:%d SR:%d | 保底 SR剩余:%d SSR剩余:%d",
        count, tender, ssr, sr, Gacha.getSRPityRemain(), Gacha.getSSRPityRemain()))
    return results, tender
end

return Gacha
