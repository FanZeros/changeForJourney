-- ============================================================================
-- RelicHandler - 遗物管理网络入口（薄路由层）
-- 职责: 接收请求 �?提取参数 �?�?RelicService �?返回结果
-- 层级: server/relic  |  禁止业务逻辑
-- ============================================================================

local Protocol     = require("shared.Protocol")
local RelicService = require("server.relic.RelicService")
local GMHandler    = require("server.gm.GMHandler")
local GMLogger     = require("server.gm.GMLogger")

local RelicHandler = {}

local handlers = {}

--- GM 给遗物（指定类型/品质）— 必须走 UID 白名单
handlers[Protocol.ACTION_TYPES.GM_GIVE_RELIC] = GMLogger.WrapGMAction(
    Protocol.ACTION_TYPES.GM_GIVE_RELIC,
    function(uid, params)
        if not GMHandler.RequireAuth(uid) then
            return { success = false, reason = "权限不足" }
        end
        local ok, err, result = RelicService.GmGiveRelic(
            uid,
            params and params.relicType,
            params and params.quality
        )
        if not ok then
            return { success = false, reason = err }
        end
        return { success = true, relic = result.relic }
    end
)

--- 遗物洗练（消耗奥术粉尘，生成候选词缀）
handlers[Protocol.ACTION_TYPES.RELIC_REFORGE] = function(uid, params)
    local ok, err, result = RelicService.Reforge(uid, params and params.relicId)
    if not ok then
        return { success = false, reason = err, action = Protocol.ACTION_TYPES.RELIC_REFORGE }
    end
    return { success = true, action = Protocol.ACTION_TYPES.RELIC_REFORGE, newAffixId = result.newAffixId }
end

--- 确认替换洗练候选词缀
handlers[Protocol.ACTION_TYPES.RELIC_REFORGE_CONFIRM] = function(uid, params)
    local ok, err, result = RelicService.ConfirmReforge(uid, params and params.relicId, params and params.newAffixId)
    if not ok then
        return { success = false, reason = err, action = Protocol.ACTION_TYPES.RELIC_REFORGE_CONFIRM }
    end
    return {
        success = true,
        action = Protocol.ACTION_TYPES.RELIC_REFORGE_CONFIRM,
        relicId = result.relicId,
        newAffixId = result.newAffixId,
    }
end

--- 遗物镶嵌到石板网�?
handlers[Protocol.ACTION_TYPES.RELIC_PLACE] = function(uid, params)
    local ok, err, result = RelicService.PlaceOnGrid(
        uid,
        params and params.relicId,
        params and params.row,
        params and params.col,
        params and params.rotation
    )
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true, relicId = result.relicId, row = result.row, col = result.col, rotation = result.rotation }
end

--- 从石板网格取下遗�?
handlers[Protocol.ACTION_TYPES.RELIC_REMOVE] = function(uid, params)
    local ok, err, result = RelicService.RemoveFromGrid(uid, params and params.relicId)
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true, relicId = result.relicId }
end

--- 调整模式批量移动（原子化 REMOVE+PLACE，避免频率限制拆分问题）
handlers[Protocol.ACTION_TYPES.RELIC_BATCH_ADJUST] = function(uid, params)
    local ok, err, result = RelicService.BatchAdjust(uid, params and params.moves)
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true, moved = result.moved }
end

--- 遗物合成�?个同类型同品质→1个高品质�?
handlers[Protocol.ACTION_TYPES.RELIC_MERGE] = function(uid, params)
    local ok, err, result = RelicService.Merge(uid, params and params.relicIds)
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true, relic = result.relic }
end


--- ԭ�ӻ��滻��������ȡ�¾����� + �������е�������ŵ���λ�ã������ύ������ REMOVE+PLACE �������͵ľ�̬��
handlers[Protocol.ACTION_TYPES.RELIC_REPLACE] = function(uid, params)
    local ok, err, result = RelicService.ReplaceOnGrid(
        uid,
        params and params.oldRelicId,
        params and params.newRelicId,
        params and params.row,
        params and params.col,
        params and params.rotation
    )
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true }
end

--- 切换遗物锁定状态
handlers[Protocol.ACTION_TYPES.RELIC_LOCK] = function(uid, params)
    local ok, err, result = RelicService.ToggleLock(uid, params and params.relicId)
    if not ok then
        return { success = false, reason = err, action = Protocol.ACTION_TYPES.RELIC_LOCK }
    end
    return {
        success  = true,
        action   = Protocol.ACTION_TYPES.RELIC_LOCK,
        relicId  = result.relicId,
        locked   = result.locked,
    }
end

RelicHandler.actionHandlers = handlers

return RelicHandler
