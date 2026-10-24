-- ============================================================================
-- AwakeningService - 觉醒业务逻辑
-- 职责: 觉醒节点激活校验与修改（纯业务，禁止网络 IO）
-- 层级: server/awakening  |  通过 PDM 读写数据
-- ============================================================================

local PDM              = require("rules.character.PlayerDataManager")
local TaskService      = require("rules.task.TaskService")
local AwakeningConfig  = require("config.AwakeningConfig")
local HeroShardPolicy = require("shared.heroes.HeroShardPolicy")
local HeroShardService = require("rules.hero.HeroShardService")

local AwakeningService = {}

--- 激活觉醒节点
--- 觉醒节点必须按顺序激活: 1→2→3
---@param uid number
---@param heroId number
---@param nodeIndex number 1-3
---@return boolean ok
---@return string|nil errReason
---@return table|nil result { heroId, nodeIndex }
function AwakeningService.Activate(uid, heroId, nodeIndex)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then
        return false, "数据未加载"
    end

    if not heroId or not nodeIndex then
        return false, "参数缺失"
    end

    heroId = tonumber(heroId)
    nodeIndex = tonumber(nodeIndex)
    if not HeroShardPolicy.isSafeInteger(nodeIndex) or nodeIndex > AwakeningConfig.NODE_COUNT then
        return false, "无效的觉醒节点: " .. tostring(nodeIndex)
    end

    if heroes.roster[heroId] ~= nil and heroes.roster[tostring(heroId)] ~= nil then
        return false, "英雄库存键重复"
    end
    local hero = heroes.roster[heroId] or heroes.roster[tostring(heroId)]
    if not HeroShardPolicy.isOwned(hero) then
        return false, "未拥有该英雄"
    end

    -- 初始化觉醒数据（旧 7 阶压成 3 阶）
    local awakening = AwakeningConfig.migrateAwakening(hero.awakening, hero._awk3Migrated == true)

    -- 检查是否已激活
    if awakening[nodeIndex] then
        return false, "该觉醒节点已激活"
    end

    -- 顺序校验: 前置节点必须全部激活
    for i = 1, nodeIndex - 1 do
        if not awakening[i] then
            return false, "需要先激活第" .. i .. "阶觉醒"
        end
    end

    -- 碎片消耗检查
    local shardCost = AwakeningConfig.getShardCost(nodeIndex)
    local currentShards = hero.shards or 0
    if not HeroShardPolicy.isSafeInteger(currentShards, true) then return false, "碎片库存异常" end
    if currentShards < shardCost then
        return false, "碎片不足（需要 " .. shardCost .. " 个碎片，当前 " .. currentShards .. " 个）"
    end

    -- 新阶段扣片后重算剩余容量，旧超额按原比例归并；币异常不扣觉醒费用。
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, "数据未加载" end
    local staged = HeroShardService.CopyHeroes(heroes)
    local pending = staged.roster[heroId] or staged.roster[tostring(heroId)]
    pending.shards = currentShards - shardCost
    pending.awakening = awakening
    pending.awakening[nodeIndex] = true
    pending.awakening._awk3Migrated = true
    pending._awk3Migrated = true
    staged.roster[heroId], staged.roster[tostring(heroId)] = pending, nil
    local plan, planErr = HeroShardService.PlanFor(staged, currency, heroId, 0, { allowZero = true })
    if not plan then return false, planErr end
    plan.beforeShards = currentShards
    local applied, applyErr = HeroShardService.ApplyTo(heroes, currency, plan)
    if not applied then return false, applyErr end
    HeroShardService.MarkDirty(uid, plan)

    -- 任务进度：刷新觉醒成就（awk_r/sr/ssr_max）
    TaskService.RefreshAchievements(uid)

    print("[AwakeningService] Activate uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " node=" .. tostring(nodeIndex))

    return true, nil, { heroId = heroId, nodeIndex = nodeIndex,
        tavernCoin = plan.tavernCoin, overflowShards = plan.overflowShards }
end

return AwakeningService
