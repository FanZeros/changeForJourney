-- ============================================================================
-- TowerHandler - 通天塔网络路由层
-- 职责: 接收客户端 Action → 调用 TowerService → 返回结果
-- ============================================================================

local TowerService = require("server.tower.TowerService")
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
        return { success = false, reason = err }
    end
    return {
        success      = true,
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
    local buffId = params and params.buffId
    if not buffId then
        return { success = false, reason = "缺少参数" }
    end

    local ok, err, result = TowerService.PickBuff(uid, buffId)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success    = true,
        buffId     = result.buffId,
        buffName   = result.buffName,
        totalBuffs = result.totalBuffs,
    }
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
