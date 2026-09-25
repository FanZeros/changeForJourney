-- ============================================================================
-- DungeonIdleConfig - 副本挂机/离线收益配置
-- 黄金矿洞 → 金币 | 上古遗迹 → 奥术粉尘 | 通天塔 → 钻石
--
-- 平衡原则（相对每日 2 次扫荡）：
--   · 挂机是补充收入，不应压过扫荡
--   · 满条收益 ≈ 1 次同层扫荡奖励
--   · 效率 = 扫荡奖励 / EFFICIENCY_DIVISOR（满条分钟数）
-- ============================================================================

local DungeonConfig = require("config.DungeonConfig")
local TowerConfig   = require("config.TowerConfig")

local DungeonIdleConfig = {}

--- 进度条满格点（24 小时）。超过后仍继续累积，收益减半，不封顶。
DungeonIdleConfig.FULL_RATE_SEC = 86400

--- 超过满格点的收益比例
DungeonIdleConfig.TAIL_RATIO = 0.5

--- 兼容旧字段：进度条满格与「挂机已满」文案仍读这个
DungeonIdleConfig.MAX_ACCUM_SEC = DungeonIdleConfig.FULL_RATE_SEC

--- 满格对应分钟数（= FULL_RATE_SEC / 60）
DungeonIdleConfig.MAX_ACCUM_MIN = DungeonIdleConfig.FULL_RATE_SEC / 60

--- 每分钟效率除数：24 小时满额 ≈ 1 次扫荡，与改前 12 小时口径的每分钟效率保持一致
--- 改前除数是 720（12h），满条收益 ≈ 1 次扫荡。现在满格改成 24h，除数仍用 720，
--- 否则每分钟收益会被砍半。
DungeonIdleConfig.EFFICIENCY_DIVISOR = 720

--- 副本挂机收益倍率
DungeonIdleConfig.REWARD_MULT = 2

--- 最少累积 60 秒才可领取
DungeonIdleConfig.MIN_CLAIM_SEC = 60

--- 副本 → 奖励资源 type（与 ResourceDefs / CurrencyService 对齐）
DungeonIdleConfig.REWARD_TYPE = {
    gold_mine    = "gold",
    ancient_ruin = "arcane_dust",
    babel_tower  = "diamond",
}

--- 副本 ID 列表
DungeonIdleConfig.DUNGEON_IDS = { "gold_mine", "ancient_ruin", "babel_tower" }

--- 获取指定层扫荡奖励（作为挂机效率基准）
---@param dungeonId string
---@param floor number 已通关层（挂机层，非当前挑战层）
---@return number
function DungeonIdleConfig.getSweepReward(dungeonId, floor)
    floor = math.floor(tonumber(floor) or 0)
    if floor <= 0 then return 0 end

    if dungeonId == "gold_mine" then
        local data = DungeonConfig.getGoldMineFloor(floor)
        return data and (data.sweepGold or 0) or 0
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
    local div = DungeonIdleConfig.EFFICIENCY_DIVISOR
    if div <= 0 then div = 480 end
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

--- 收益用的有效秒数：满格前原样，超出部分按 TAIL_RATIO，无硬顶
---@param accumSec number
---@return number
function DungeonIdleConfig.effectiveSeconds(accumSec)
    local raw = math.max(0, math.floor(tonumber(accumSec) or 0))
    local full = DungeonIdleConfig.FULL_RATE_SEC
    if raw <= full then return raw end
    return full + math.floor((raw - full) * DungeonIdleConfig.TAIL_RATIO)
end

--- 根据累积秒数计算可领取数量
--- 返回的 minutes 是实际累积分钟（领取时按它扣存档），amount 按有效时长算。
---@param dungeonId string
---@param floor number
---@param accumSec number
---@return number amount
---@return number minutes
function DungeonIdleConfig.calcReward(dungeonId, floor, accumSec)
    local raw = math.floor(tonumber(accumSec) or 0)
    if raw < DungeonIdleConfig.MIN_CLAIM_SEC then
        return 0, 0
    end
    local perMin = DungeonIdleConfig.getIdlePerMin(dungeonId, floor)
    if perMin <= 0 then return 0, 0 end
    local effective = DungeonIdleConfig.effectiveSeconds(raw)
    local payMinutes = math.floor(effective / 60)
    local rawMinutes = math.floor(raw / 60)
    return payMinutes * perMin * DungeonIdleConfig.REWARD_MULT, rawMinutes
end

--- 从副本进度子结构推算挂机层（= 可扫荡层 = floor - 1）
---@param sub table
---@return number idleFloor 0 表示尚无挂机收益
function DungeonIdleConfig.getIdleFloorFromSub(sub)
    if not sub then return 0 end
    return math.max(0, math.floor(tonumber(sub.floor) or 1) - 1)
end

return DungeonIdleConfig
