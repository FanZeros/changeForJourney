-- ============================================================================
-- ArtifactHandler.lua — 神器系统网络入口（薄 Handler）
-- ============================================================================

local Protocol        = require("shared.Protocol")
local ArtifactService = require("server.artifact.ArtifactService")

local ArtifactHandler = {}
local handlers = {}

handlers[Protocol.ACTION_TYPES.ARTIFACT_DRAW] = function(uid, params)
    local ok, err, result = ArtifactService.Draw(uid, params and params.count, params and params.payType)
    if not ok then
        return { success = false, reason = err, action = Protocol.ACTION_TYPES.ARTIFACT_DRAW }
    end
    result.success = true
    result.action = Protocol.ACTION_TYPES.ARTIFACT_DRAW
    return result
end

handlers[Protocol.ACTION_TYPES.ARTIFACT_EQUIP] = function(uid, params)
    local ok, err, result = ArtifactService.Equip(uid, params and params.artifactId, params and params.slot, params and params.subSlot)
    if not ok then
        return { success = false, reason = err, action = Protocol.ACTION_TYPES.ARTIFACT_EQUIP }
    end
    result.success = true
    result.action = Protocol.ACTION_TYPES.ARTIFACT_EQUIP
    return result
end

handlers[Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP] = function(uid, params)
    local ok, err, result = ArtifactService.Unequip(uid, params and params.slot, params and params.subSlot)
    if not ok then
        return { success = false, reason = err, action = Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP }
    end
    result.success = true
    result.action = Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP
    return result
end

handlers[Protocol.ACTION_TYPES.ARTIFACT_MERGE] = function(uid, params)
    local ok, err, result
    if params and params.artifactIdGroups then
        ok, err, result = ArtifactService.MergeBatch(uid, params.artifactIdGroups)
    else
        ok, err, result = ArtifactService.Merge(uid, params and params.artifactIds)
    end
    if not ok then
        return { success = false, reason = err, action = Protocol.ACTION_TYPES.ARTIFACT_MERGE }
    end
    result.success = true
    result.action = Protocol.ACTION_TYPES.ARTIFACT_MERGE
    return result
end

handlers[Protocol.ACTION_TYPES.ARTIFACT_REROLL] = function(uid, params)
    local ok, err, result = ArtifactService.Reroll(uid, params and params.artifactIds)
    if not ok then
        return { success = false, reason = err, action = Protocol.ACTION_TYPES.ARTIFACT_REROLL }
    end
    result.success = true
    result.action = Protocol.ACTION_TYPES.ARTIFACT_REROLL
    return result
end

handlers[Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE] = function(uid, params)
    local ok, err, result = ArtifactService.RefineValue(uid, params and params.artifactId)
    if not ok then
        return { success = false, reason = err, action = Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE }
    end
    result.success = true
    result.action = Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE
    return result
end

ArtifactHandler.actionHandlers = handlers

return ArtifactHandler
