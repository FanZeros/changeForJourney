-- ============================================================================
-- TowerHandler - 通天塔网络路由层
-- 职责: 接收客户端 Action → 调用 TowerService → 返回结果
-- ============================================================================

local TowerService = require("rules.tower.TowerService")
local Protocol     = require("shared.Protocol")

local handlers = {}

-- ── 挑战（进入通天塔） ──
handlers[Protocol.ACTION_TYPES.TOWER_CHALLENGE] = function(uid, params)
    local ok, err, result = TowerService.Challenge(uid)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success      = true,
        floor        = result.floor,
        wave         = result.wave,
        monsterLevel = result.monsterLevel,
        monsters     = result.monsters,
        rageTime     = result.rageTime,
        superRageTime = result.superRageTime,
        runId        = result.runId,
        buffs        = result.buffs,
        battleBg     = result.battleBg,
    }
end

-- ── 单波胜利 ──
handlers[Protocol.ACTION_TYPES.TOWER_WAVE_WIN] = function(uid, params)
    local floor = params and params.floor
    local wave  = params and params.wave
    if not floor or not wave then
        return { success = false, reason = "缺少参数" }
    end

    local ok, err, result = TowerService.WaveWin(uid, floor, wave)
    if not ok then
        return { success = false, reason = err, floor = floor, wave = wave }
    end
    return {
        success      = true,
        runId        = result.runId,
        selectionId  = result.selectionId,
        floor        = floor,
        wave         = wave,
        floorCleared = result.floorCleared,
        nextWave     = result.nextWave,
        monsters     = result.monsters,
        monsterLevel = result.monsterLevel,
        buffChoices  = result.buffChoices,
    }
end

-- ── 整层通关结算 ──
handlers[Protocol.ACTION_TYPES.TOWER_FLOOR_WIN] = function(uid, params)
    local floor = params and params.floor
    if not floor then
        return { success = false, reason = "缺少参数" }
    end

    local ok, err, result = TowerService.FloorWin(uid, floor)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success       = true,
        floor         = result.floor,
        firstClear    = result.firstClear,
        diamondReward = result.diamondReward,
        rewards       = result.rewards,
        nextFloor     = result.nextFloor,
    }
end

-- ── 选择强化 ──
handlers[Protocol.ACTION_TYPES.TOWER_PICK_BUFF] = function(uid, params)
    params = type(params) == "table" and params or {}
    local buffId = params.buffId
    local function failed(reason, retryOnly)
        print("[TowerHandler] PickBuff failed run=" .. tostring(params.runId)
            .. " selection=" .. tostring(params.selectionId) .. " request=" .. tostring(params.requestId)
            .. " reason=" .. tostring(reason))
        return { success = false, reason = reason, buffId = buffId,
            runId = params.runId, selectionId = params.selectionId,
            floor = params.floor, wave = params.wave, requestId = params.requestId,
            retryOnly = retryOnly }
    end
    if not buffId then return failed("缺少参数") end

    -- 桥层抛错兜底不携带身份，必须在这里捕获，避免 Scene 永久等待无从匹配的回执。
    local called, ok, err, result = pcall(TowerService.PickBuff, uid, buffId, params)
    if not called then
        print("[TowerHandler] ERROR PickBuff: " .. tostring(ok))
        -- 异常可能发生在 append/MarkDirty 后；同 selection 同卡重试，不能假定未提交。
        return failed("强化处理异常，请重试", true)
    end
    if not ok then return failed(err) end
    return result
end

-- ── 扫荡 ──
handlers[Protocol.ACTION_TYPES.TOWER_SWEEP] = function(uid, params)
    local ok, err, result = TowerService.Sweep(uid)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success       = true,
        sweepFloor    = result.sweepFloor,
        diamondReward = result.diamondReward,
        dailyUsed     = result.dailyUsed,
        dailyMax      = result.dailyMax,
    }
end

return { actionHandlers = handlers }
