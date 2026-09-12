-- ============================================================================
-- EquipmentHandler - 装备管理网络入口（薄路由层）
-- 职责: 接收请求 → 提取参数 → 调 EquipmentService → 返回结果
-- 层级: server/equipment  |  禁止业务逻辑
-- ============================================================================

local Protocol         = require("shared.Protocol")
local EquipmentService = require("server.equipment.EquipmentService")
local GMHandler        = require("server.gm.GMHandler")
local GMLogger         = require("server.gm.GMLogger")

local EquipmentHandler = {}

local handlers = {}

--- GM 给装备（指定模板）— 必须走 UID 白名单
handlers[Protocol.ACTION_TYPES.GM_GIVE_EQUIP] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_GIVE_EQUIP,
    function(uid, params)
        if not GMHandler.RequireAuth(uid) then
            return { success = false, reason = "权限不足" }
        end
        local ok, err, result = EquipmentService.GmGiveEquip(
            uid,
            params and params.templateId,
            params and params.level,
            params and params.quality
        )
        if not ok then
            return { success = false, reason = err }
        end
        return { success = true, seq = result.seq, equip = result.equip }
    end
)

--- GM 随机给装备 — 必须走 UID 白名单
handlers[Protocol.ACTION_TYPES.GM_GIVE_RANDOM] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_GIVE_RANDOM,
    function(uid, params)
        if not GMHandler.RequireAuth(uid) then
            return { success = false, reason = "权限不足" }
        end
        local ok, err, result = EquipmentService.GmGiveRandom(
            uid,
            params and params.level,
            params and params.quality,
            params and params.count
        )
        if not ok then
            return { success = false, reason = err }
        end
        return {
            success = true,
            count   = result.count,
            items   = result.items,
            bagFull = result.bagFull,
        }
    end
)

--- 穿戴/更换装备
handlers[Protocol.ACTION_TYPES.EQUIP_ITEM] = function(uid, params)
    local ok, err, result = EquipmentService.EquipItem(
        uid,
        params and params.seq,
        params and params.heroId,
        params and params.slot
    )
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success         = true,
        seq             = result.seq,
        heroId          = result.heroId,
        slot            = result.slot,
        oldSeq          = result.oldSeq,
        unequippedSlots = result.unequippedSlots,
    }
end

--- 卸下装备
handlers[Protocol.ACTION_TYPES.UNEQUIP_ITEM] = function(uid, params)
    local ok, err, result = EquipmentService.UnequipItem(
        uid,
        params and params.heroId,
        params and params.slot
    )
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success    = true,
        heroId     = result.heroId,
        slot       = result.slot,
        removedSeq = result.removedSeq,
    }
end

--- 一键卸下全部装备
handlers[Protocol.ACTION_TYPES.UNEQUIP_ALL] = function(uid, params)
    local ok, err, result = EquipmentService.UnequipAll(
        uid,
        params and params.heroId
    )
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success       = true,
        heroId        = result.heroId,
        removedSlots  = result.removedSlots,
    }
end

--- 一键装备最佳装备
handlers[Protocol.ACTION_TYPES.EQUIP_ALL_BEST] = function(uid, params)
    local ok, err, result = EquipmentService.EquipAllBest(
        uid,
        params and params.heroId
    )
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success  = true,
        heroId   = result.heroId,
        changes  = result.changes,
    }
end

--- 切换装备锁定状态
handlers[Protocol.ACTION_TYPES.TOGGLE_EQUIP_LOCK] = function(uid, params)
    local ok, err, result = EquipmentService.ToggleEquipLock(uid, params and params.seq)
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true, seq = result.seq, locked = result.locked }
end

--- 设置自动分解条件
handlers[Protocol.ACTION_TYPES.SET_AUTO_DECOMPOSE] = function(uid, params)
    local autoQuality = params and tonumber(params.autoQuality)
    local autoLevel   = params and tonumber(params.autoLevel)
    if autoQuality == nil or autoLevel == nil then
        return { success = false, reason = "缺少 autoQuality 或 autoLevel 参数" }
    end
    local ok, err = EquipmentService.SetAutoDecompose(uid, autoQuality, autoLevel)
    if not ok then return { success = false, reason = err } end
    return { success = true, autoQuality = autoQuality, autoLevel = autoLevel }
end

EquipmentHandler.actionHandlers = handlers

return EquipmentHandler
