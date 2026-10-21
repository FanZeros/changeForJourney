-- ============================================================================
-- SweepHandler - 扫荡本地入口（薄路由层）
-- 职责: 接收本地 SWEEP 请求 → 调 SweepService → 返回结果
-- 层级: rules/sweep  |  单机，不连服务器
-- ============================================================================

local Protocol     = require("shared.Protocol")
local SweepService = require("rules.sweep.SweepService")

local SweepHandler = {}

local handlers = {}

local function sweep(uid, args, control)
    if not control then
        return SweepService.Sweep(uid, args.count, args.teamIdx, args.stageId)
    end
    local candidate, err = SweepService.PrepareSweep(uid, args, control)
    if not candidate then return false, err end
    if control.checkpoint then control.checkpoint("commit", 0, 0) end
    -- Prepare 的 checkpoint 可让出；最后校验/提交内绝不让出 live 事务。
    return SweepService.CommitSweep(uid, candidate, control)
end

handlers[Protocol.ACTION_TYPES.SWEEP] = function(uid, params, control)
    params = params or {}
    local count = params.count
    if count == nil then count = params.times end
    local teamIdx = params.teamIdx
    local ok, err, result = sweep(uid, { count = count, teamIdx = teamIdx, stageId = params.stageId }, control)
    if not ok then
        return { success = false, reason = err, teamIdx = teamIdx, stageId = params.stageId }
    end
    result.success = true
    return result
end

--- 仅资源旧协议异步兼容；古遗迹等原 DungeonHandler 同步路径不变。
function SweepHandler.isResourceSweep(params)
    return require("config.DungeonConfig").isResourceDungeon(params.dungeonId or "gold_mine")
end

function SweepHandler.resourceSweep(uid, params, control)
    local DC = require("config.DungeonConfig")
    local PDM = require("rules.character.PlayerDataManager")
    local id = params.dungeonId or "gold_mine"
    local dungeon, battle = PDM.GetModule(uid, "dungeon"), PDM.GetModule(uid, "battle")
    if not dungeon or not battle then return { success = false, reason = "数据未加载" } end
    local floor = params.floor
    if floor == nil then
        local rules = require("shared.sweep.SweepRewards")
        for candidate = DC.getHighestClearedFloor(dungeon[id], id), 1, -1 do
            if rules.isCleared(DC.getStageId(id, candidate), battle, dungeon) then
                floor = candidate
                break
            end
        end
    end
    local stageId = DC.getStageId(id, floor)
    if not stageId then return { success = false, reason = "暂无可扫荡层" } end
    local count = params.count
    if count == nil then count = params.times end
    local ok, err, result = sweep(uid, { count = count, teamIdx = params.teamIdx, stageId = stageId }, control)
    if not ok then return { success = false, reason = err, teamIdx = params.teamIdx, stageId = stageId } end
    result.success, result.dungeonId, result.sweepFloor = true, id, floor
    return result
end

SweepHandler.actionHandlers = handlers

return SweepHandler
