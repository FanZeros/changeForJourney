-- ============================================================================
-- DungeonIdleService - 副本挂机/离线收益
-- 在线每帧累加 idleAccumSec，登录时补算离线时长，玩家手动领取
-- ============================================================================

local PDM               = require("server.character.PlayerDataManager")
local DungeonConfig     = require("config.DungeonConfig")
local DungeonIdleConfig = require("config.DungeonIdleConfig")
local CurrencyService   = require("server.currency.CurrencyService")

local DungeonIdleService = {}

local syncedThisSession = {}
local onlineAccumFrac = {}

local DUNGEON_IDS = DungeonIdleConfig.DUNGEON_IDS

--- 会话键：同一 uid 在不同区服有独立离线同步/在线累加状态
---@param uid number
---@return string
local function getSessionKey(uid)
    local sid = PDM.GetServerId(uid) or 0
    return tostring(uid) .. ":" .. tostring(sid)
end

-- ======================== 工具 ========================

local function isDungeonUnlocked(uid, dungeonId)
    local req = DungeonConfig.UNLOCK_CONDITIONS[dungeonId] or 0
    if req <= 0 then return true end
    local battle = PDM.GetModule(uid, "battle")
    local maxStageId = battle and tonumber(battle.maxStageId) or 0
    return maxStageId >= req
end

local function getSub(dungeon, dungeonId)
    if not dungeon[dungeonId] then
        dungeon[dungeonId] = {
            floor = 1, cleared = {}, dailyUsed = 0, dailyDay = 0,
            idleAccumSec = 0,
        }
    end
    local sub = dungeon[dungeonId]
    sub.idleAccumSec = math.floor(tonumber(sub.idleAccumSec) or 0)
    return sub
end

local function capAccumSec(sec)
    sec = math.floor(sec)
    if sec > DungeonIdleConfig.MAX_ACCUM_SEC then
        return DungeonIdleConfig.MAX_ACCUM_SEC
    end
    if sec < 0 then return 0 end
    return sec
end

local function addAccumSec(sub, addSec)
    if addSec <= 0 then return end
    sub.idleAccumSec = capAccumSec(sub.idleAccumSec + addSec)
end

-- ======================== 生命周期 ========================

--- 登录后一次性补算离线挂机时长（各副本独立累积）
---@param uid number
function DungeonIdleService.SyncOfflineOnEnter(uid)
    local sessionKey = getSessionKey(uid)
    if syncedThisSession[sessionKey] then return end
    syncedThisSession[sessionKey] = true

    local dungeon = PDM.GetModule(uid, "dungeon")
    local session = PDM.GetModule(uid, "session")
    if not dungeon or not session then return end

    local lastOnline = tonumber(session.lastOnlineTime) or 0
    local now = os.time()
    if lastOnline <= 0 then return end

    local offlineSec = now - lastOnline
    if offlineSec < 60 then return end

    local dirty = false
    for _, dungeonId in ipairs(DUNGEON_IDS) do
        if isDungeonUnlocked(uid, dungeonId) then
            local sub = getSub(dungeon, dungeonId)
            local idleFloor = DungeonIdleConfig.getIdleFloorFromSub(sub)
            if idleFloor > 0 and DungeonIdleConfig.getIdlePerMin(dungeonId, idleFloor) > 0 then
                local before = sub.idleAccumSec
                addAccumSec(sub, offlineSec)
                if sub.idleAccumSec ~= before then
                    dirty = true
                    print(string.format(
                        "[DungeonIdle] offline sync uid=%s %s +%ds accum=%ds",
                        tostring(uid), dungeonId, offlineSec, sub.idleAccumSec))
                end
            end
        end
    end

    if dirty then
        PDM.MarkDirty(uid, "dungeon")
    end
end

--- 在线每帧累加（对已解锁且有挂机层的副本）
---@param uid number
---@param dt number
function DungeonIdleService.HandleIdleAccum(uid, dt)
    if dt <= 0 then return end

    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then return end

    local dirty = false
    local sessionKey = getSessionKey(uid)
    local fracByDungeon = onlineAccumFrac[sessionKey]
    if not fracByDungeon then
        fracByDungeon = {}
        onlineAccumFrac[sessionKey] = fracByDungeon
    end

    for _, dungeonId in ipairs(DUNGEON_IDS) do
        if isDungeonUnlocked(uid, dungeonId) then
            local sub = getSub(dungeon, dungeonId)
            local idleFloor = DungeonIdleConfig.getIdleFloorFromSub(sub)
            if idleFloor > 0 and DungeonIdleConfig.getIdlePerMin(dungeonId, idleFloor) > 0 then
                if sub.idleAccumSec < DungeonIdleConfig.MAX_ACCUM_SEC then
                    local before = sub.idleAccumSec
                    local frac = (fracByDungeon[dungeonId] or 0) + dt
                    local whole = math.floor(frac)
                    fracByDungeon[dungeonId] = frac - whole
                    if whole > 0 then
                        addAccumSec(sub, whole)
                        if sub.idleAccumSec ~= before then
                            dirty = true
                        end
                    end
                else
                    fracByDungeon[dungeonId] = 0
                end
            else
                fracByDungeon[dungeonId] = 0
            end
        else
            fracByDungeon[dungeonId] = 0
        end
    end

    if dirty then
        PDM.MarkDirty(uid, "dungeon")
    end
end

--- 预览可领取奖励（不修改数据）
---@param uid number
---@param dungeonId string
---@return table|nil preview { amount, rewardType, idleFloor, accumSec, minutes, perMin }
function DungeonIdleService.Preview(uid, dungeonId)
    if not isDungeonUnlocked(uid, dungeonId) then
        return nil
    end

    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then return nil end

    local sub = getSub(dungeon, dungeonId)
    local idleFloor = DungeonIdleConfig.getIdleFloorFromSub(sub)
    local accumSec = sub.idleAccumSec or 0
    local amount, minutes = DungeonIdleConfig.calcReward(dungeonId, idleFloor, accumSec)
    local rewardType = DungeonIdleConfig.REWARD_TYPE[dungeonId] or "gold"

    return {
        amount     = amount,
        rewardType = rewardType,
        idleFloor  = idleFloor,
        accumSec   = accumSec,
        minutes    = minutes,
        perMin     = DungeonIdleConfig.getIdlePerMin(dungeonId, idleFloor),
        maxAccumSec = DungeonIdleConfig.MAX_ACCUM_SEC,
    }
end

--- 领取副本挂机奖励
---@param uid number
---@param dungeonId string
---@return boolean ok
---@return string|nil err
---@return table|nil result
function DungeonIdleService.Claim(uid, dungeonId)
    if not dungeonId or dungeonId == "" then
        return false, "缺少dungeonId参数", nil
    end
    if not isDungeonUnlocked(uid, dungeonId) then
        return false, "副本未解锁", nil
    end

    local preview = DungeonIdleService.Preview(uid, dungeonId)
    if not preview then
        return false, "数据未加载", nil
    end
    if preview.idleFloor <= 0 then
        return false, "尚未通关任何层，暂无挂机收益", nil
    end
    if (preview.amount or 0) <= 0 then
        return false, "暂无可领取的挂机奖励", nil
    end

    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then return false, "数据未加载", nil end

    local sub = getSub(dungeon, dungeonId)
    local claimMinutes = preview.minutes or 0
    local claimSec = claimMinutes * 60

    local okGrant = CurrencyService.GrantReward(uid, {
        type   = preview.rewardType,
        amount = preview.amount,
    })
    if not okGrant then
        return false, "奖励发放失败", nil
    end

    sub.idleAccumSec = math.max(0, (sub.idleAccumSec or 0) - claimSec)
    PDM.MarkDirty(uid, "dungeon")
    PDM.FlushImmediate(uid)

    local serverId = PDM.GetServerId(uid) or 0
    print(string.format(
        "[DungeonIdle] claim uid=%s sid=%s %s floor=%d amount=%d sec=%d remain=%d",
        tostring(uid), tostring(serverId), dungeonId, preview.idleFloor, preview.amount, claimSec, sub.idleAccumSec))

    return true, nil, {
        dungeonId  = dungeonId,
        serverId   = serverId,
        amount     = preview.amount,
        rewardType = preview.rewardType,
        idleFloor  = preview.idleFloor,
        minutes    = claimMinutes,
        accumSec   = sub.idleAccumSec,
    }
end

--- 断线/切服清理当前区服的会话标记
---@param uid number
function DungeonIdleService.Cleanup(uid)
    local sessionKey = getSessionKey(uid)
    syncedThisSession[sessionKey] = nil
    onlineAccumFrac[sessionKey] = nil
end

return DungeonIdleService
