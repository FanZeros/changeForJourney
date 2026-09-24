-- ============================================================================
-- BlacksmithHandler - 铁匠铺事件路由
-- 职责: 网络事件入口、参数提取、调 Service、返回结果
-- 层级: server/blacksmith
-- ============================================================================

local Protocol         = require("shared.Protocol")
local BlacksmithService = require("rules.blacksmith.BlacksmithService")

local BlacksmithHandler = {}
local handlers = {}

--- 装备升阶。优先 seq；旧的 partySlot 参数只用来找到身上那一件。
local function resolveAscendSeq(uid, params)
    local seq = params and tonumber(params.seq)
    if seq then return seq end
    local partySlot = params and tonumber(params.partySlot)
    local equipSlot = params and params.equipSlot
    if not partySlot or not equipSlot then return nil end
    local heroes = require("rules.character.PlayerDataManager").GetModule(uid, "heroes")
    local equipData = require("rules.character.PlayerDataManager").GetModule(uid, "equipment")
    if not heroes or not equipData then return nil end
    local heroId = heroes.deployed and heroes.deployed[partySlot]
    if not heroId then return nil end
    local slots = equipData.equipped and (equipData.equipped[heroId] or equipData.equipped[tostring(heroId)])
    local found = slots and slots[equipSlot]
    return tonumber(found)
end

handlers[Protocol.ACTION_TYPES.ENHANCE_EQUIP] = function(uid, params)
    local seq = resolveAscendSeq(uid, params)
    if not seq then
        return { success = false, reason = "请选择要升阶的装备" }
    end
    local ok, err, result = BlacksmithService.AscendEquip(uid, seq)
    if not ok then return { success = false, reason = err } end
    result.success = true
    return result
end

handlers[Protocol.ACTION_TYPES.ENHANCE_EQUIP_MAX] = function(uid, params)
    local seq = resolveAscendSeq(uid, params)
    local targetLevel = params and tonumber(params.targetLevel)
    if not seq or not targetLevel then
        return { success = false, reason = "请选择装备和目标升阶" }
    end
    local ok, err, result = BlacksmithService.AscendEquipToLevel(uid, seq, targetLevel)
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
