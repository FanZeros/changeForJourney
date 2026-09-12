-- ============================================================================
-- AwakeningService - 觉醒业务逻辑
-- 职责: 觉醒节点激活校验与修改（纯业务，禁止网络 IO）
-- 层级: server/awakening  |  通过 PDM 读写数据
-- ============================================================================

local PDM              = require("server.character.PlayerDataManager")
local TaskService      = require("server.task.TaskService")
local AwakeningConfig  = require("config.AwakeningConfig")

local AwakeningService = {}

--- 激活觉醒节点
--- 觉醒节点必须按顺序激活: 1→2→3→4→5→6→7
---@param uid number
---@param heroId number
---@param nodeIndex number 1-7
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

    if nodeIndex < 1 or nodeIndex > 7 then
        return false, "无效的觉醒节点: " .. tostring(nodeIndex)
    end

    local hero = heroes.roster[heroId]
    if not hero then
        return false, "未拥有该英雄"
    end

    -- 初始化觉醒数据
    if not hero.awakening then
        hero.awakening = {}
    end

    -- 检查是否已激活
    if hero.awakening[nodeIndex] then
        return false, "该觉醒节点已激活"
    end

    -- 顺序校验: 前置节点必须全部激活
    for i = 1, nodeIndex - 1 do
        if not hero.awakening[i] then
            return false, "需要先激活第" .. i .. "阶觉醒"
        end
    end

    -- 碎片消耗检查
    local shardCost = AwakeningConfig.getShardCost(nodeIndex)
    local currentShards = hero.shards or 0
    if currentShards < shardCost then
        return false, "碎片不足（需要 " .. shardCost .. " 个碎片，当前 " .. currentShards .. " 个）"
    end

    -- === 原子修改 ===
    hero.shards = currentShards - shardCost
    hero.awakening[nodeIndex] = true

    -- === 持久化（MarkDirty 是同步内存操作，不会抛异常） ===
    PDM.MarkDirty(uid, "heroes")

    -- 任务进度：刷新觉醒成就（awk_r/sr/ssr_max）
    TaskService.RefreshAchievements(uid)

    print("[AwakeningService] Activate uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " node=" .. tostring(nodeIndex))

    return true, nil, { heroId = heroId, nodeIndex = nodeIndex }
end

return AwakeningService
