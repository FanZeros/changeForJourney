-- HeroShardService.lua — 统一碎片发放、整卡解锁与旧库存归并。
-- 所有跨模块值先规划/校验，后同时写 heroes/currency，最后才 MarkDirty。
local PDM = require("rules.character.PlayerDataManager")
local Policy = require("shared.heroes.HeroShardPolicy")
local HeroConfig = require("config.HeroConfig")
local ExpTable = require("config.ExpTable")

local Service = {}

local function modules(uid)
    local heroes = PDM.GetModule(uid, "heroes")
    local currency = PDM.GetModule(uid, "currency")
    if not heroes or not currency or type(heroes.roster) ~= "table" then
        return nil, nil, "数据未加载"
    end
    return heroes, currency
end

local function copyTable(source)
    local out = {}
    for key, value in pairs(source or {}) do out[key] = value end
    return out
end
Service.CopyTable = copyTable

--- 暂存多抽时复制每个条目；ApplyTo 的原地更新不可触及真实库存。
function Service.CopyHeroes(heroes)
    local staged = copyTable(heroes)
    staged.roster = {}
    for key, entry in pairs(heroes.roster) do
        staged.roster[key] = type(entry) == "table" and copyTable(entry) or entry
    end
    return staged
end

local function writeEntry(heroes, heroId, planned)
    local entry = heroes.roster[heroId] or heroes.roster[tostring(heroId)]
    if entry then
        for key, value in pairs(planned) do entry[key] = value end
    else
        entry = planned
    end
    heroes.roster[heroId] = entry
    heroes.roster[tostring(heroId)] = nil
end

function Service.CommitRoster(heroes, staged)
    for key, entry in pairs(staged.roster) do writeEntry(heroes, tonumber(key), entry) end
end

local function getEntry(heroes, heroId)
    return heroes.roster[heroId] or heroes.roster[tostring(heroId)]
end

local function attachBalance(currency, plan)
    local balance = currency.tavernCoin
    if balance == nil then balance = 0 end
    if not Policy.isSafeInteger(balance, true) then return nil, "酒馆币库存异常" end
    if plan.tavernCoin > Policy.MAX_SAFE_INTEGER - balance then
        return nil, "酒馆币超出安全范围"
    end
    plan.beforeCoin = balance
    plan.afterCoin = balance + plan.tavernCoin
    plan.changed = plan.beforeShards ~= plan.afterShards or plan.tavernCoin > 0 or plan.isNew == true
    return plan
end

--- 供扣费/扣源片前规划；不会创建存根或变更任何模块。
function Service.PlanFor(heroes, currency, heroId, amount, opts)
    heroId = tonumber(heroId)
    if not heroes or type(heroes.roster) ~= "table" or not currency then return nil, "数据未加载" end
    if heroId and heroes.roster[heroId] ~= nil and heroes.roster[tostring(heroId)] ~= nil then
        return nil, "英雄库存键重复"
    end
    local entry = heroId and getEntry(heroes, heroId) or nil
    local plan, err = Policy.planGrant(heroId, entry, amount, opts)
    if not plan then return nil, err end
    plan.entry = copyTable(entry)
    plan.entry.shards = plan.afterShards
    plan.entry._shardMigrated = true
    return attachBalance(currency, plan)
end

function Service.Plan(uid, heroId, amount, opts)
    local heroes, currency, err = modules(uid)
    if not heroes then return nil, err end
    return Service.PlanFor(heroes, currency, heroId, amount, opts)
end

--- 整卡先按新拥有状态计算容量，故存根100片获整卡后只留90片、10片转币。
function Service.PlanHeroFor(heroes, currency, heroId, opts)
    opts = opts or {}
    heroId = tonumber(heroId)
    if not Policy.isSafeInteger(heroId) or not HeroConfig.get(heroId) then return nil, "无效的英雄 ID" end
    if not heroes or type(heroes.roster) ~= "table" or not currency then return nil, "数据未加载" end
    if heroes.roster[heroId] ~= nil and heroes.roster[tostring(heroId)] ~= nil then
        return nil, "英雄库存键重复"
    end
    local existing = getEntry(heroes, heroId)
    if existing ~= nil and type(existing) ~= "table" then return nil, "英雄数据异常" end
    if Policy.isOwned(existing) then
        local plan, err = Service.PlanFor(heroes, currency, heroId, HeroConfig.SHARD_DUPE_CONVERT)
        if not plan then return nil, err end
        plan.isNew = false
        plan.type = plan.shardGain == 0 and "decompose" or "dupe_to_shard"
        return plan
    end
    local entry = copyTable(existing)
    local level = opts.startLevel or 1
    if not Policy.isSafeInteger(level) then return nil, "英雄初始等级异常" end
    entry.level, entry.exp = level, 0
    entry.maxExp = ExpTable.getHeroExpForLevel(level) or 0
    entry.classId = HeroConfig.get(heroId).classId or 1
    entry.dupeCount = 0
    entry.awakening = { _awk3Migrated = true }
    entry._awk3Migrated = true
    entry.extraTalent = require("systems.ExtraTalentSystem").normalize(entry.extraTalent)
    local plan, err = Policy.planGrant(heroId, entry, 0, { allowZero = true })
    if not plan then return nil, err end
    entry.shards, entry._shardMigrated = plan.afterShards, true
    plan.entry, plan.isNew, plan.type = entry, true, "hero"
    return attachBalance(currency, plan)
end

--- 仅同步写内存，不推送；用于多抽暂存表或调用者组合多模块操作。
function Service.ApplyTo(heroes, currency, plan)
    local existing = getEntry(heroes, plan.heroId)
    if (existing and existing.shards or 0) ~= plan.beforeShards
        or (currency.tavernCoin or 0) ~= plan.beforeCoin then
        return false, "碎片计划已失效"
    end
    writeEntry(heroes, plan.heroId, plan.entry)
    currency.tavernCoin = plan.afterCoin
    return true
end

function Service.MarkDirty(uid, receipt, opts)
    if opts and opts.silent then return end
    PDM.MarkDirty(uid, "heroes")
    if receipt.tavernCoin > 0 then PDM.MarkDirty(uid, "currency") end
end

function Service.Grant(uid, heroId, amount, opts)
    local heroes, currency, err = modules(uid)
    if not heroes then return false, err end
    local plan, planErr = Service.PlanFor(heroes, currency, heroId, amount, opts)
    if not plan then return false, planErr end
    local ok, applyErr = Service.ApplyTo(heroes, currency, plan)
    if not ok then return false, applyErr end
    Service.MarkDirty(uid, plan, opts)
    return true, nil, plan
end

function Service.GrantHero(uid, heroId, opts)
    local heroes, currency, err = modules(uid)
    if not heroes then return false, err end
    local plan, planErr = Service.PlanHeroFor(heroes, currency, heroId, opts)
    if not plan then return false, planErr end
    local ok, applyErr = Service.ApplyTo(heroes, currency, plan)
    if not ok then return false, applyErr end
    Service.MarkDirty(uid, plan, opts)
    return true, nil, plan
end

--- 整批先规划全部英雄和最终币余额，非法库存/溢出时整批零修改。
--- preview=true 只读；silent=true 应用但不 MarkDirty（由外层持久化事务统一处理）。
function Service.ReconcileAll(uid, opts)
    opts = opts or {}
    local heroes, currency, err = modules(uid)
    if not heroes then return false, err end
    local stagedCurrency = copyTable(currency)
    local plans, seen = {}, {}
    local result = { changed = false, overflowShards = 0, tavernCoin = 0, heroes = plans }
    if not Policy.isSafeInteger(currency.tavernCoin or 0, true) then return false, "酒馆币库存异常" end
    for key, entry in pairs(heroes.roster) do
        local heroId = tonumber(key)
        if not heroId or seen[heroId] then return false, "英雄库存键异常" end
        seen[heroId] = true
        local policyPlan, planErr = Policy.planGrant(heroId, entry, 0, { allowZero = true })
        if not policyPlan then return false, planErr end
        local plan, balanceErr = attachBalance(stagedCurrency, policyPlan)
        if not plan then return false, balanceErr end
        if plan.changed then
            plan.entry = copyTable(entry)
            plan.entry.shards = plan.afterShards
            plan.entry._shardMigrated = true
            plans[#plans + 1] = plan
            stagedCurrency.tavernCoin = plan.afterCoin
            result.changed = true
            result.overflowShards = result.overflowShards + plan.overflowShards
            result.tavernCoin = result.tavernCoin + plan.tavernCoin
        end
    end
    if opts.preview or not result.changed then return true, nil, result end
    -- 规划期间无 yield/回调；此处不会在半批更新后遇到验证失败。
    for _, plan in ipairs(plans) do
        writeEntry(heroes, plan.heroId, plan.entry)
    end
    currency.tavernCoin = stagedCurrency.tavernCoin
    Service.MarkDirty(uid, result, opts)
    return true, nil, result
end

return Service
