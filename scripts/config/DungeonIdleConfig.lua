-- ============================================================================
-- DungeonIdleConfig - 副本挂机/离线收益配置
-- 金币副本 → 金币 | 装备副本 → 装备 | 黑钻副本 → 钻石
-- 通天塔只在首通发黑钻，不提供挂机黑钻（神器通过实际挑战获得）。
-- 隐藏上古遗迹仅保留旧粉尘存量领取。
--
-- 金币/旧粉尘的每分钟效率保持不变；黑钻保留小数，避免整数阈值跳涨。
-- 2× 倍率与尾段口径不变。装备完整 24h 发 2 次 sweepEquip，最终件数向下取整。
-- ============================================================================

local DungeonConfig = require("config.DungeonConfig")
local TowerConfig   = require("config.TowerConfig")

local DungeonIdleConfig = {}

--- 进度条满格点（24 小时）。超过后仍继续累积，收益减半，直到 HARD_CAP_SEC 硬顶。
DungeonIdleConfig.FULL_RATE_SEC = 86400

--- 超过满格点的收益比例
DungeonIdleConfig.TAIL_RATIO = 0.5

--- 硬顶（7 日）：离线补算与累积最多到此时长，超出部分不再产生收益
DungeonIdleConfig.HARD_CAP_SEC = 86400 * 7

--- 兼容旧字段：进度条满格与「挂机已满」文案仍读这个
DungeonIdleConfig.MAX_ACCUM_SEC = DungeonIdleConfig.FULL_RATE_SEC

--- 满格对应分钟数（= FULL_RATE_SEC / 60）
DungeonIdleConfig.MAX_ACCUM_MIN = DungeonIdleConfig.FULL_RATE_SEC / 60

--- 货币基准的每分钟效率除数（沿用旧 12h 的 720，不改变旧收入）。
DungeonIdleConfig.EFFICIENCY_DIVISOR = 720

--- 装备完整 24h 的扫荡次数当量；不再应用旧货币 REWARD_MULT。
DungeonIdleConfig.EQUIP_FULL_SWEEPS = 2

--- 副本挂机收益倍率
DungeonIdleConfig.REWARD_MULT = 2

--- 最少累积 60 秒才可领取
DungeonIdleConfig.MIN_CLAIM_SEC = 60

--- 副本 → 奖励 type；equip 必须交给 DungeonService，不是货币。
DungeonIdleConfig.REWARD_TYPE = {
    gold_mine      = "gold",
    equipment_vault = "equip",
    black_diamond  = "diamond",
    ancient_ruin   = "arcane_dust",
    babel_tower    = "diamond",
}

--- 活跃挂机副本。旧遗迹只领取既存积累；塔不再新增被动收益。
DungeonIdleConfig.DUNGEON_IDS = { "gold_mine", "equipment_vault", "black_diamond" }

--- 获取指定层扫荡奖励（作为挂机效率基准）
---@param dungeonId string
---@param floor number 已通关层（挂机层，非当前挑战层）
---@return number
function DungeonIdleConfig.getSweepReward(dungeonId, floor)
    floor = math.floor(tonumber(floor) or 0)
    if floor <= 0 then return 0 end

    if DungeonConfig.isResourceDungeon(dungeonId) then
        local data = DungeonConfig.getFloor(dungeonId, floor)
        if not data then return 0 end
        if dungeonId == "gold_mine" then return data.sweepGold or 0 end
        if dungeonId == "equipment_vault" then return data.sweepEquip or 0 end
        if dungeonId == "black_diamond" then return data.sweepDiamond or 0 end
    elseif dungeonId == "ancient_ruin" then
        local data = DungeonConfig.getAncientRuinFloor(floor)
        return data and (data.sweepDust or 0) or 0
    elseif dungeonId == "babel_tower" then
        local data = TowerConfig.getFloor(floor)
        return data and (data.sweepDiamond or 0) or 0
    end
    return 0
end

--- 每分钟挂机收益
---@param dungeonId string
---@param floor number
---@return number perMin
function DungeonIdleConfig.getIdlePerMin(dungeonId, floor)
    local sweep = DungeonIdleConfig.getSweepReward(dungeonId, floor)
    if sweep <= 0 then return 0 end
    if dungeonId == "equipment_vault" then
        return sweep * DungeonIdleConfig.EQUIP_FULL_SWEEPS / DungeonIdleConfig.MAX_ACCUM_MIN
    end
    local div = DungeonIdleConfig.EFFICIENCY_DIVISOR
    if div <= 0 then div = 480 end
    -- 黑钻保留小数效率，避免跨整数阈值时整段收益翻倍；领取时才取整。
    if dungeonId == "black_diamond" or dungeonId == "babel_tower" then
        return math.max(1, sweep / div)
    end
    return math.max(1, math.floor(sweep / div))
end

--- 累积进度 0~1（用于 UI 展示）
---@param accumSec number
---@return number ratio
function DungeonIdleConfig.getFillRatio(accumSec)
    accumSec = math.floor(tonumber(accumSec) or 0)
    if accumSec <= 0 then return 0 end
    return math.min(1, accumSec / DungeonIdleConfig.MAX_ACCUM_SEC)
end

--- 收益用的有效秒数：先按 HARD_CAP_SEC（7 日）截断，满格前原样，超出部分按 TAIL_RATIO
---@param accumSec number
---@return number
function DungeonIdleConfig.effectiveSeconds(accumSec)
    local raw = math.max(0, math.floor(tonumber(accumSec) or 0))
    local cap = DungeonIdleConfig.HARD_CAP_SEC
    if raw > cap then raw = cap end
    local full = DungeonIdleConfig.FULL_RATE_SEC
    if raw <= full then return raw end
    return full + math.floor((raw - full) * DungeonIdleConfig.TAIL_RATIO)
end

--- 根据累积秒数计算可领取数量。
--- 货币消费全部原始分钟；装备只消费足以发整件的最小原分钟，保留不足一件余量。
--- 装备 consumedSec 保留本轮 FULL/TAIL 的位置，不把残余尾段重新计为全速。
---@param dungeonId string
---@param floor number
---@param accumSec number
---@param consumedSec number|nil 仅装备；旧档 nil=0
---@return number amount
---@return number minutes
function DungeonIdleConfig.calcReward(dungeonId, floor, accumSec, consumedSec)
    local raw = math.floor(tonumber(accumSec) or 0)
    if raw < DungeonIdleConfig.MIN_CLAIM_SEC then
        return 0, 0
    end
    local perMin = DungeonIdleConfig.getIdlePerMin(dungeonId, floor)
    if perMin <= 0 then return 0, 0 end
    if dungeonId == "equipment_vault" then
        local cursor = math.min(DungeonIdleConfig.HARD_CAP_SEC, math.max(0, math.floor(tonumber(consumedSec) or 0)))
        local maxMinutes = math.floor(math.min(raw, DungeonIdleConfig.HARD_CAP_SEC - cursor) / 60)
        local baseline = DungeonIdleConfig.effectiveSeconds(cursor)
        local fullReward = DungeonIdleConfig.getSweepReward(dungeonId, floor) * DungeonIdleConfig.EQUIP_FULL_SWEEPS
        local function amountAt(minutes)
            local effective = DungeonIdleConfig.effectiveSeconds(cursor + minutes * 60) - baseline
            -- 先乘整数扫荡当量再除秒数，避免 perMin 浮点乘回整数的边界误差。
            return math.floor(effective * fullReward / DungeonIdleConfig.FULL_RATE_SEC)
        end
        local amount = amountAt(maxMinutes)
        if amount <= 0 then return 0, 0 end
        local low, high = 1, maxMinutes
        while low < high do
            local mid = math.floor((low + high) / 2)
            if amountAt(mid) >= amount then high = mid else low = mid + 1 end
        end
        return amount, low
    end
    local effective = DungeonIdleConfig.effectiveSeconds(raw)
    local payMinutes = math.floor(effective / 60)
    local rawMinutes = math.floor(raw / 60)
    return math.floor(payMinutes * perMin * DungeonIdleConfig.REWARD_MULT), rawMinutes
end

--- 三资源取真实最高 cleared（包含已通末层）；旧遗迹/独立塔保留 floor-1 口径。
---@param sub table|nil
---@param dungeonId string|nil 不传时兼容旧调用，并识别账本中的末层
---@return number idleFloor 0 表示尚无挂机收益
function DungeonIdleConfig.getIdleFloorFromSub(sub, dungeonId)
    if not sub then return 0 end
    if dungeonId then
        if DungeonConfig.isResourceDungeon(dungeonId) then
            return DungeonConfig.getHighestClearedFloor(sub, dungeonId)
        end
        if not DungeonIdleConfig.REWARD_TYPE[dungeonId] then return 0 end
    end
    local legacyFloor = math.max(0, math.floor(tonumber(sub.floor) or 1) - 1)
    if dungeonId then return legacyFloor end
    local highest = legacyFloor
    for key, cleared in pairs(sub.cleared or {}) do
        local floor = math.tointeger(tonumber(key) or 0)
        if cleared == true and floor and floor > highest then highest = floor end
    end
    return highest
end

return DungeonIdleConfig
