-- ============================================================================
-- CurrencyService - 货币操作公共服务
-- 职责: 提供奖励发放等通用货币操作（被多个 Service 复用）
-- 层级: server/currency  |  禁止网络 IO
-- ============================================================================

local PDM = require("server.character.PlayerDataManager")
local ResourceDefs = require("config.ResourceDefs")

local CurrencyService = {}

--- 奖励类型 → currency 模块字段名映射
CurrencyService.REWARD_TO_CURRENCY = {
    diamond          = "gems",
    gold             = "gold",
    arena_coin       = "arenaCoin",
    adventure_ticket = "recruitTicket",
    stellar_ticket   = "stellarRecruitTicket",
    privilege_point  = "privilegePoint",
    arcane_dust      = "arcaneDust",     -- 奥术粉尘
    essence          = "essence",
    enhance_star     = "enhanceStone",   -- 洗练石（原强化星石）
    refine_stone     = "enhanceStone",   -- 洗练石（新 reward key 别名）
    sweep_ticket     = "sweepTicket",
    golden_key       = "goldenKey",
    corrupt_stone    = "corruptStone",
    sacred_stone     = "sacredStone",
    arena_ticket     = "arenaTicket",
    tavern_coin      = "tavernCoin",
    degrade_protect  = "degradeStone",   -- （已隐藏，保留兼容）
    break_protect    = "destroyStone",   -- 点金石（原损毁保护石）
    gold_stone       = "destroyStone",   -- 点金石（新 reward key 别名）
    weapon_scroll    = "weaponScroll",   -- 武器卷轴
    offhand_scroll   = "offhandScroll",  -- 副手卷轴
    armor_scroll     = "armorScroll",    -- 护甲卷轴
    accessory_scroll = "accessoryScroll",-- 饰品卷轴
    random_scroll    = "weaponScroll",   -- 随机卷轴（发放时由业务层随机选一种）
    privilege_card   = "privilegeCardOwned", -- 特权卡（激活型，非累加）
}

--- 激活型奖励（设为 amount 而非 += amount）
CurrencyService.ACTIVATION_KEYS = {
    privilegeCardOwned = true,
}

--- 发放单个奖励到 currency 模块
---@param uid number
---@param reward table { type=string, amount=number, heroId=number|nil }
---@return boolean success
function CurrencyService.GrantReward(uid, reward)
    -- 兼容旧 GM 邮件：type="101" 等碎片编号
    if reward.type ~= "shard" then
        local legacyHeroId = ResourceDefs.SHARD_ID_TO_HERO[tostring(reward.type)]
        if legacyHeroId then
            reward = { type = "shard", heroId = legacyHeroId, amount = reward.amount }
        end
    end

    if reward.type == "shard" then
        local heroId = tonumber(reward.heroId)
        local amount = tonumber(reward.amount)
        if not heroId or not amount or amount <= 0 then
            print("[CurrencyService] invalid shard reward: heroId=" .. tostring(reward.heroId)
                .. " amount=" .. tostring(reward.amount))
            return false
        end
        local heroes = PDM.GetModule(uid, "heroes")
        if not heroes then return false end
        if not heroes.roster then heroes.roster = {} end
        if not heroes.roster[heroId] then
            heroes.roster[heroId] = { shards = 0, _shardMigrated = true }
        end
        heroes.roster[heroId].shards = (heroes.roster[heroId].shards or 0) + amount
        PDM.MarkDirty(uid, "heroes")
        print("[CurrencyService] GrantReward shard uid=" .. tostring(uid)
            .. " heroId=" .. heroId .. " +" .. amount)
        return true
    end

    local currencyKey = CurrencyService.REWARD_TO_CURRENCY[reward.type]
    if not currencyKey then
        print("[CurrencyService] unknown reward type: " .. tostring(reward.type))
        return false
    end
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false end
    if CurrencyService.ACTIVATION_KEYS[currencyKey] then
        -- 激活型：直接设为 amount（1=激活）
        currency[currencyKey] = reward.amount
    else
        -- 累加型：常规 += amount
        currency[currencyKey] = (currency[currencyKey] or 0) + reward.amount
    end
    PDM.MarkDirty(uid, "currency")
    return true
end

--- 批量发放奖励
---@param uid number
---@param rewards table[] { type, amount }[]
---@return number grantedCount
function CurrencyService.GrantRewards(uid, rewards)
    local count = 0
    for _, reward in ipairs(rewards) do
        if CurrencyService.GrantReward(uid, reward) then
            count = count + 1
        end
    end
    return count
end

--- 检查余额是否足够
---@param uid number
---@param currencyField string  currency 表中的字段名（如 "gems", "gold"）
---@param amount number
---@return boolean enough
---@return number balance 当前余额
function CurrencyService.CheckBalance(uid, currencyField, amount)
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, 0 end
    local balance = currency[currencyField] or 0
    return balance >= amount, balance
end

--- 扣除货币
---@param uid number
---@param currencyField string
---@param amount number
---@return boolean success
---@return number newBalance
function CurrencyService.Deduct(uid, currencyField, amount)
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, 0 end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, currency[currencyField] or 0 end
    local balance = math.max(0, math.floor(tonumber(currency[currencyField]) or 0))
    if balance < amount then return false, balance end
    currency[currencyField] = balance - amount
    PDM.MarkDirty(uid, "currency")
    return true, currency[currencyField]
end

--- 增加货币
---@param uid number
---@param currencyField string
---@param amount number
---@return number newBalance
function CurrencyService.Add(uid, currencyField, amount)
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return 0 end
    currency[currencyField] = (currency[currencyField] or 0) + amount
    PDM.MarkDirty(uid, "currency")
    return currency[currencyField]
end

return CurrencyService
