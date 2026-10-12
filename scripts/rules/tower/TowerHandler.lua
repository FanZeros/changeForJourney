-- ============================================================================
-- TowerHandler - 通天塔动作路由
-- 波/层请求与回执保留本次局身份；不能用迟到回执推进新挑战。
-- ============================================================================

local TowerService = require("rules.tower.TowerService")
local Protocol = require("shared.Protocol")

local handlers = {}

local function failed(params, reason, retryOnly)
    params = type(params) == "table" and params or {}
    return { success = false, reason = reason, floor = params.floor, wave = params.wave,
        runId = params.runId, requestId = params.requestId,
        selectionId = params.selectionId, buffId = params.buffId, retryOnly = retryOnly }
end

local function receipt(params, result)
    result.success = true
    result.requestId = params and params.requestId
    return result
end

handlers[Protocol.ACTION_TYPES.TOWER_CHALLENGE] = function(uid, params)
    local ok, err, result = TowerService.Challenge(uid, params and params.floor)
    if not ok then return failed(params, err) end
    return receipt(params, result)
end

handlers[Protocol.ACTION_TYPES.TOWER_WAVE_WIN] = function(uid, params)
    if not params or not params.floor or not params.wave then return failed(params, "缺少参数") end
    local called, ok, err, result = pcall(TowerService.WaveWin, uid, params.floor, params.wave, params)
    if not called then
        print("[TowerHandler] ERROR WaveWin: " .. tostring(ok))
        return failed(params, "楼层战斗确认异常，请重试", true)
    end
    if not ok then return failed(params, err) end
    return receipt(params, result)
end

handlers[Protocol.ACTION_TYPES.TOWER_FLOOR_WIN] = function(uid, params)
    if not params or not params.floor then return failed(params, "缺少参数") end
    local called, ok, err, result = pcall(TowerService.FloorWin, uid, params.floor, params)
    if not called then
        print("[TowerHandler] ERROR FloorWin: " .. tostring(ok))
        return failed(params, "通天塔结算异常，请重试", true)
    end
    if not ok then return failed(params, err, true) end
    return receipt(params, result)
end

handlers[Protocol.ACTION_TYPES.TOWER_PICK_BUFF] = function(uid, params)
    params = type(params) == "table" and params or {}
    if not params.buffId then return failed(params, "缺少参数") end
    local called, ok, err, result = pcall(TowerService.PickBuff, uid, params.buffId, params)
    if not called then
        print("[TowerHandler] ERROR PickBuff: " .. tostring(ok))
        return failed(params, "强化处理异常，请重试", true)
    end
    if not ok then return failed(params, err) end
    return result
end

handlers[Protocol.ACTION_TYPES.TOWER_SWEEP] = function(uid, params)
    local called, ok, err, result = pcall(TowerService.Sweep, uid)
    if not called then
        print("[TowerHandler] ERROR Sweep: " .. tostring(ok))
        return failed(params, "通天塔扫荡异常，请重试", true)
    end
    if not ok then return failed(params, err) end
    return receipt(params, result)
end

return { actionHandlers = handlers }
