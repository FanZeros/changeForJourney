-- ============================================================================
-- DungeonHandler - 副本网络入口（薄路由层）
-- 职责: 接收 DUNGEON_* 请求 → 调 DungeonService → 返回结果
-- 层级: server/dungeon  |  禁止业务逻辑
-- ============================================================================

local Protocol           = require("shared.Protocol")
local DungeonService     = require("server.dungeon.DungeonService")
local DungeonIdleService = require("server.dungeon.DungeonIdleService")

local DungeonHandler = {}

local handlers = {}

-- ── 扫荡 ──
handlers[Protocol.ACTION_TYPES.DUNGEON_SWEEP] = function(uid, params)
    local dungeonId = params and params.dungeonId or "gold_mine"

    local ok, err, result = DungeonService.Sweep(uid, dungeonId)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success    = true,
        dungeonId  = result.dungeonId,
        sweepFloor = result.sweepFloor,
        gold       = result.gold,       -- gold_mine
        dust       = result.dust,       -- ancient_ruin
        relics     = result.relics,     -- ancient_ruin
        dailyUsed  = result.dailyUsed,
        dailyMax   = result.dailyMax,
    }
end

-- ── 挑战（进入战斗） ──
handlers[Protocol.ACTION_TYPES.DUNGEON_CHALLENGE] = function(uid, params)
    local dungeonId = params and params.dungeonId or "gold_mine"
    local floor     = params and params.floor

    if not floor then
        return { success = false, reason = "缺少floor参数" }
    end

    local ok, err, result = DungeonService.Challenge(uid, dungeonId, floor)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success          = true,
        dungeonId        = result.dungeonId,
        floor            = result.floor,
        monsterLevel     = result.monsterLevel,
        monsters         = result.monsters,
        firstGold        = result.firstGold,        -- gold_mine
        firstDust        = result.firstDust,        -- ancient_ruin
        firstRelicCount  = result.firstRelicCount,  -- ancient_ruin
        qualityWeights   = result.qualityWeights,   -- ancient_ruin
        classBonus       = result.classBonus,
        classBonusValue  = result.classBonusValue,
        rageTime         = result.rageTime,
        rageAtkBonus     = result.rageAtkBonus,
        superRageTime    = result.superRageTime,
        superRageAtkBonus = result.superRageAtkBonus,
    }
end

-- ── 胜利结算 ──
handlers[Protocol.ACTION_TYPES.DUNGEON_WIN] = function(uid, params)
    local dungeonId = params and params.dungeonId or "gold_mine"
    local floor     = params and params.floor

    if not floor then
        return { success = false, reason = "缺少floor参数" }
    end

    local ok, err, result = DungeonService.Win(uid, dungeonId, floor)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success    = true,
        dungeonId  = result.dungeonId,
        floor      = result.floor,
        firstClear = result.firstClear,
        gold       = result.gold,       -- gold_mine
        dust       = result.dust,       -- ancient_ruin
        relics     = result.relics,     -- ancient_ruin
        nextFloor  = result.nextFloor,
    }
end

-- ── 副本挂机/离线收益领取 ──
handlers[Protocol.ACTION_TYPES.DUNGEON_IDLE_CLAIM] = function(uid, params)
    local dungeonId = params and params.dungeonId
    if not dungeonId then
        return { success = false, reason = "缺少dungeonId参数" }
    end

    local ok, err, result = DungeonIdleService.Claim(uid, dungeonId)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success    = true,
        dungeonId  = result.dungeonId,
        serverId   = result.serverId,
        amount     = result.amount,
        rewardType = result.rewardType,
        idleFloor  = result.idleFloor,
        minutes    = result.minutes,
        accumSec   = result.accumSec,
    }
end

--- 断线/切服清理（由 Server.lua 的 __cleanup 机制调用）
handlers["__cleanup"] = function(uid)
    DungeonIdleService.Cleanup(uid)
end

DungeonHandler.actionHandlers = handlers

return DungeonHandler
