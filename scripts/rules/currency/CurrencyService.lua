-- ============================================================================
-- CurrencyService - 货币操作公共服务
-- 职责: 提供奖励发放等通用货币操作（被多个 Service 复用）
-- 层级: server/currency  |  禁止网络 IO
-- ============================================================================

local PDM = require("rules.character.PlayerDataManager")
local ResourceDefs = require("config.ResourceDefs")
local HeroShardService = require("rules.hero.HeroShardService")

local CurrencyService = {}

--- 奖励类型 → currency 模块字段名映射
CurrencyService.REWARD_TO_CURRENCY = {
    diamond          = "gems",
    gold             = "gold",
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
    tavern_coin      = "tavernCoin",
    degrade_protect  = "degradeStone",   -- （已隐藏，保留兼容）
    break_protect    = "destroyStone",   -- 点金石（原损毁保护石）
    gold_stone       = "destroyStone",   -- 点金石（新 reward key 别名）
    weapon_scroll    = "weaponScroll",   -- 武器卷轴
    offhand_scroll   = "offhandScroll",  -- 副手卷轴
    armor_scroll     = "armorScroll",    -- 护甲卷轴
    accessory_scroll = "accessoryScroll",-- 饰品卷轴
    helmet_scroll    = "helmetScroll",   -- 头盔卷轴
    shoes_scroll     = "shoesScroll",    -- 鞋子卷轴
    random_scroll    = "weaponScroll",   -- 随机卷轴（发放时由业务层随机选一种）
    privilege_card   = "privilegeCardOwned", -- 特权卡（激活型，非累加）
}

--- 激活型奖励（设为 amount 而非 += amount）
CurrencyService.ACTIVATION_KEYS = {
    privilegeCardOwned = true,
}

-- 访问与发布只转发当前 PDM 方法；不缓存模块或方法，也不复制业务持有的表。
local function getCurrency(uid)
    return PDM.GetModule(uid, "currency")
end

local function publishCurrency(uid)
    PDM.MarkDirty(uid, "currency")
end

-- 规范化仅兼容旧碎片编号，不把普通货币奖励改成扣款的整数规则。
local function normalizeReward(reward)
    if reward.type ~= "shard" then
        local legacyHeroId = ResourceDefs.SHARD_ID_TO_HERO[tostring(reward.type)]
        if legacyHeroId then
            reward = { type = "shard", heroId = legacyHeroId, amount = reward.amount }
        end
    end

    return reward
end

-- 碎片由统一服务先规划，再原位写 heroes/currency，保留封顶、溢出转币及实际回执。
local function grantShard(uid, reward)
    local ok, err, receipt = HeroShardService.Grant(uid, reward.heroId, reward.amount)
    if not ok then
        print("[CurrencyService] invalid shard reward: " .. tostring(err))
        return false, nil, err
    end
    return true, receipt
end

-- 货币奖励按当前公开映射及激活表分流，查询顺序保持在访问 PDM 前后原位置。
local function grantCurrency(uid, reward)
    local currencyKey = CurrencyService.REWARD_TO_CURRENCY[reward.type]
    if not currencyKey then
        print("[CurrencyService] unknown reward type: " .. tostring(reward.type))
        return false
    end
    local currency = getCurrency(uid)
    if not currency then return false end
    if CurrencyService.ACTIVATION_KEYS[currencyKey] then
        -- 激活型：直接设为 amount（1=激活）
        currency[currencyKey] = reward.amount
    else
        -- 累加型：常规 += amount
        currency[currencyKey] = (currency[currencyKey] or 0) + reward.amount
    end
    publishCurrency(uid)
    return true
end

-- 扣款判断不写表。非正数返回原余额，正数才规范化余额；二者不能合并。
local function prepareDeduction(currency, currencyField, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, currency[currencyField] or 0 end
    local balance = math.max(0, math.floor(tonumber(currency[currencyField]) or 0))
    if balance < amount then return false, balance end
    return true, balance, amount
end

--- 发放单个奖励到 currency 模块
---@param uid number
---@param reward table { type=string, amount=number, heroId=number|nil }
---@return boolean success
---@return table|nil receipt 实际碎片/酒馆币回执
function CurrencyService.GrantReward(uid, reward)
    reward = normalizeReward(reward)
    if reward.type == "shard" then
        return grantShard(uid, reward)
    end
    return grantCurrency(uid, reward)
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
    local currency = getCurrency(uid)
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
    local currency = getCurrency(uid)
    if not currency then return false, 0 end
    local allowed, balance, amount = prepareDeduction(currency, currencyField, amount)
    if not allowed then return false, balance end
    currency[currencyField] = balance - amount
    publishCurrency(uid)
    -- 发布可同步重入；返回通知后的同一张表，不能返回预计算余额或重新取模块。
    return true, currency[currencyField]
end

--- 增加货币
---@param uid number
---@param currencyField string
---@param amount number
---@return number newBalance
function CurrencyService.Add(uid, currencyField, amount)
    local currency = getCurrency(uid)
    if not currency then return 0 end
    currency[currencyField] = (currency[currencyField] or 0) + amount
    publishCurrency(uid)
    return currency[currencyField]
end

return CurrencyService
