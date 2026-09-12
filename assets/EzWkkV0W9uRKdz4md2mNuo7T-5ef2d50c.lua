-- ============================================================================
-- BlacksmithHandler - 铁匠铺事件路由
-- 职责: 网络事件入口、参数提取、调 Service、返回结果
-- 层级: server/blacksmith
-- ============================================================================

local Protocol         = require("shared.Protocol")
local BlacksmithService = require("server.blacksmith.BlacksmithService")

local BlacksmithHandler = {}
local handlers = {}

--- 槽位强化
handlers[Protocol.ACTION_TYPES.ENHANCE_EQUIP] = function(uid, params)
    local partySlot = params and tonumber(params.partySlot)
    local equipSlot = params and params.equipSlot
    if not partySlot or not equipSlot then
        return { success = false, reason = "缺少 partySlot 或 equipSlot" }
    end
    local ok, err, result = BlacksmithService.EnhanceSlot(uid, partySlot, equipSlot)
    if not ok then return { success = false, reason = err } end
    result.success = true
    return result
end

--- 一键强化到目标等级
handlers[Protocol.ACTION_TYPES.ENHANCE_EQUIP_MAX] = function(uid, params)
    local partySlot  = params and tonumber(params.partySlot)
    local equipSlot  = params and params.equipSlot
    local targetLevel = params and tonumber(params.targetLevel)
    if not partySlot or not equipSlot or not targetLevel then
        return { success = false, reason = "缺少 partySlot、equipSlot 或 targetLevel" }
    end
    local ok, err, result = BlacksmithService.EnhanceSlotToLevel(uid, partySlot, equipSlot, targetLevel)
    if not ok then return { success = false, reason = err } end
    result.success = true
    return result
end

--- 洗练装备
handlers[Protocol.ACTION_TYPES.REFINE_EQUIP] = function(uid, params)
    local seq = params and tonumber(params.seq)
    if not seq then
        return { success = false, reason = "缺少 seq" }
    end
    local extraResource = params and params.extraResource or nil
    local lockedIndices = params and params.lockedIndices or nil
    local ok, err, result = BlacksmithService.RefineEquip(uid, seq, extraResource, lockedIndices)
    if not ok then return { success = false, reason = err } end
    result.success = true
    return result
end

--- 替换词缀（确认洗练结果）
handlers[Protocol.ACTION_TYPES.REFINE_REPLACE] = function(uid, params)
    local seq = params and tonumber(params.seq)
    if not seq then
        return { success = false, reason = "缺少 seq" }
    end
    local ok, err, result = BlacksmithService.RefineReplace(uid, seq)
    if not ok then return { success = false, reason = err } end
    result.success = true
    return result
end

--- 分解装备
handlers[Protocol.ACTION_TYPES.DECOMPOSE_EQUIP] = function(uid, params)
    local seqs = params and params.seqs
    if not seqs or #seqs == 0 then
        return { success = false, reason = "未选择装备" }
    end
    local ok, err, result = BlacksmithService.DecomposeEquip(uid, seqs)
    if not ok then return { success = false, reason = err } end
    result.success = true
    return result
end

--- 断线清理
handlers.__cleanup = function(uid)
    BlacksmithService.Cleanup(uid)
end

BlacksmithHandler.actionHandlers = handlers
return BlacksmithHandler
