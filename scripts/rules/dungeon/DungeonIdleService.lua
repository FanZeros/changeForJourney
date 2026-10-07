-- ============================================================================
-- DungeonIdleService - 副本挂机/离线收益
-- 在线每帧累加 idleAccumSec，登录时补算离线时长，玩家手动领取
-- ============================================================================

local PDM               = require("rules.character.PlayerDataManager")
local DungeonConfig     = require("config.DungeonConfig")
local DungeonIdleConfig = require("config.DungeonIdleConfig")
local DungeonService    = require("rules.dungeon.DungeonService")

local DungeonIdleService = {}

local syncedThisSession = {}
local onlineAccumFrac = {}

local DUNGEON_IDS = DungeonIdleConfig.DUNGEON_IDS

--- 会话键：单机按 uid
---@param uid number
---@return string
local function getSessionKey(uid)
    return tostring(uid)
end

-- ======================== 工具 ========================

local function isDungeonUnlocked(uid, dungeonId)
    if not DungeonIdleConfig.REWARD_TYPE[dungeonId] then return false end
    -- 隐藏旧遗迹仅结清已经累积的粉尘，不用新装备解锁条件阻挡旧存量。
    if dungeonId == "ancient_ruin" then return true end
    local req = DungeonConfig.UNLOCK_CONDITIONS[dungeonId] or 0
    if req <= 0 then return true end
    local battle = PDM.GetModule(uid, "battle")
    local maxStageId = battle and tonumber(battle.maxStageId) or 0
    return maxStageId >= req
end

local function getSub(dungeon, dungeonId)
    if type(dungeon[dungeonId]) ~= "table" then
        dungeon[dungeonId] = {
            floor = 1, cleared = {}, dailyUsed = 0, dailyDay = 0,
            idleAccumSec = 0,
        }
    end
    local sub = dungeon[dungeonId]
    sub.idleAccumSec = math.max(0, math.floor(tonumber(sub.idleAccumSec) or 0))
    if dungeonId == "equipment_vault" then
        sub.idleConsumedSec = math.max(0, math.floor(tonumber(sub.idleConsumedSec) or 0))
        if sub.idleAccumSec == 0 then sub.idleConsumedSec = 0 end
    end
    return sub
end

local function capAccumSec(sec)
    sec = math.floor(sec)
    if sec < 0 then return 0 end
    -- [7日硬顶] 累积时长封顶，超出部分不再产生收益
    local cap = DungeonIdleConfig.HARD_CAP_SEC
    if cap and sec > cap then return cap end
    return sec
end

local function addAccumSec(sub, addSec, dungeonId)
    if addSec <= 0 then return end
    if dungeonId == "equipment_vault" then
        local cursor = math.min(DungeonIdleConfig.HARD_CAP_SEC, sub.idleConsumedSec or 0)
        sub.idleAccumSec = math.max(0, capAccumSec(cursor + sub.idleAccumSec + addSec) - cursor)
    else
        sub.idleAccumSec = capAccumSec(sub.idleAccumSec + addSec)
    end
end

-- ======================== 生命周期 ========================

--- 登录后一次性补算离线挂机时长（各副本独立累积）
---@param uid number
function DungeonIdleService.SyncOfflineOnEnter(uid)
    local sessionKey = getSessionKey(uid)
    if syncedThisSession[sessionKey] then return end

    local dungeon = PDM.GetModule(uid, "dungeon")
    local session = PDM.GetModule(uid, "session")
    if not dungeon or not session then return end
    syncedThisSession[sessionKey] = true

    local lastOnline = tonumber(session.lastOnlineTime) or 0
    local now = os.time()
    if lastOnline <= 0 then return end

    local offlineSec = now - lastOnline
    if offlineSec < 60 then return end

    local dirty = false
    for _, dungeonId in ipairs(DUNGEON_IDS) do
        if isDungeonUnlocked(uid, dungeonId) then
            local sub = getSub(dungeon, dungeonId)
            local idleFloor = DungeonIdleConfig.getIdleFloorFromSub(sub, dungeonId)
            if idleFloor > 0 and DungeonIdleConfig.getIdlePerMin(dungeonId, idleFloor) > 0 then
                local before = sub.idleAccumSec
                addAccumSec(sub, offlineSec, dungeonId)
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
            local idleFloor = DungeonIdleConfig.getIdleFloorFromSub(sub, dungeonId)
            if idleFloor > 0 and DungeonIdleConfig.getIdlePerMin(dungeonId, idleFloor) > 0 then
                do
                    local before = sub.idleAccumSec
                    local frac = (fracByDungeon[dungeonId] or 0) + dt
                    local whole = math.floor(frac)
                    fracByDungeon[dungeonId] = frac - whole
                    if whole > 0 then
                        addAccumSec(sub, whole, dungeonId)
                        if sub.idleAccumSec ~= before then
                            dirty = true
                        end
                    end
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

    -- 只读预览：旧档数值在局部副本归一化，失败领奖不能先补写游标/子表。
    local source = type(dungeon[dungeonId]) == "table" and dungeon[dungeonId] or {}
    local sub = {}
    for key, value in pairs(source) do sub[key] = value end
    sub.idleAccumSec = math.max(0, math.floor(tonumber(sub.idleAccumSec) or 0))
    sub.idleConsumedSec = math.max(0, math.floor(tonumber(sub.idleConsumedSec) or 0))
    local idleFloor = DungeonIdleConfig.getIdleFloorFromSub(sub, dungeonId)
    local accumSec = sub.idleAccumSec or 0
    local amount, minutes = DungeonIdleConfig.calcReward(dungeonId, idleFloor, accumSec, sub.idleConsumedSec)
    local rewardType = DungeonIdleConfig.REWARD_TYPE[dungeonId]

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
    if not DungeonIdleConfig.REWARD_TYPE[dungeonId] then
        return false, "未知副本", nil
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

    local claimMinutes = preview.minutes or 0
    local claimSec = claimMinutes * 60

    local ok, commitErr, receipt = DungeonService.CommitRewardTransaction(uid, function()
        local sub = getSub(dungeon, dungeonId)
        local equipmentResult = {} ---@type table
        -- 当前层配置：既供装备当量折算，也供结算经验取怪物等级（旧代码误传 uid 当 floor）。
        local floorData = DungeonConfig.getFloor(dungeonId, preview.idleFloor)
        if preview.rewardType == "equip" then
            -- 生成、容量检查、实际交付与扣时在一个保存事务内。
            local okGrant, grantErr, result = DungeonService.GrantEquipment(
                uid, dungeonId, preview.idleFloor, preview.amount)
            if not okGrant then return false, grantErr or "装备奖励发放失败" end
            equipmentResult = result or {}
            -- 与扫荡同口径补卷轴/扫荡券：一次扫荡当量 = 本次发奖件数 / sweepEquip。
            local sweepPerUnit = floorData and floorData.sweepEquip or 0
            local sweepCount = sweepPerUnit > 0
                and math.max(1, math.floor((preview.amount + sweepPerUnit - 1) / sweepPerUnit)) or 0
            if sweepCount > 0 then
                equipmentResult.scrollDrops = DungeonService.GrantEquipScrolls(uid, preview.idleFloor, sweepCount)
            end
        elseif not DungeonService.GrantIdleCurrency(uid, preview.rewardType, preview.amount) then
            return false, "奖励发放失败"
        end

        -- 挂机结算经验：与同进度主线同级，按实际结算分钟数发放。
        local playerExp, heroExp = 0, 0
        if floorData and claimMinutes > 0 then
            playerExp, heroExp = DungeonService.GrantIdleExp(uid, 1, floorData.monsterLevel, claimMinutes)
        end

        sub.idleAccumSec = math.max(0, (sub.idleAccumSec or 0) - claimSec)
        if preview.rewardType == "equip" then
            -- 保留不足一件的原始余时与尾段位置；本轮清空后允许下一轮重新开始。
            sub.idleConsumedSec = sub.idleAccumSec > 0 and ((sub.idleConsumedSec or 0) + claimSec) or 0
        end
        DungeonService.MarkRewardDirty(uid, "dungeon")
        return true, nil, {
            dungeonId  = dungeonId,
            amount     = preview.amount,
            rewardType = preview.rewardType,
            idleFloor  = preview.idleFloor,
            minutes    = claimMinutes,
            accumSec   = sub.idleAccumSec,
            equips     = equipmentResult.equips,
            inventoryCount = equipmentResult.inventoryCount,
            lootboxCount = equipmentResult.lootboxCount,
            scrollDrops = equipmentResult.scrollDrops,
            playerExp  = playerExp,
            heroExpTotal = heroExp,
            idleConsumedSec = sub.idleConsumedSec,
        }
    end)
    if not ok then return false, commitErr end
    print(string.format(
        "[DungeonIdle] claim uid=%s %s floor=%d amount=%d sec=%d remain=%d",
        tostring(uid), dungeonId, preview.idleFloor, preview.amount, claimSec, receipt.accumSec))
    return true, nil, receipt
end

--- 断线/切服清理当前区服的会话标记
---@param uid number
function DungeonIdleService.Cleanup(uid)
    local sessionKey = getSessionKey(uid)
    syncedThisSession[sessionKey] = nil
    onlineAccumFrac[sessionKey] = nil
end

return DungeonIdleService
