-- DungeonCompat.lua — 副本/通天塔存档兼容（层数回退等）
local DungeonConfig = require("config.DungeonConfig")

local DungeonCompat = {}

--- 201-206 / 通天塔 2× 加强后，旧进度层数回退（保留 cleared 首通记录）
---@param floor number
---@return number
function DungeonCompat.rollbackFloorForBuffV1(floor)
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    if floor <= 5 then
        return math.max(1, floor - 1)
    elseif floor <= 15 then
        return math.max(1, floor - 2)
    end
    local drop = math.max(5, math.ceil(floor * 0.12))
    drop = math.min(drop, 8)
    return math.max(1, floor - drop)
end

--- 修正 cleared 表 key（cjson 可能把数字 key 变成字符串）
---@param cleared table|nil
---@return table
local function normalizeCleared(cleared)
    if not cleared then return {} end
    local fixed = {}
    for k, v in pairs(cleared) do
        local numK = tonumber(k)
        if numK and v then
            fixed[numK] = true
        end
    end
    return fixed
end

--- 若当前层已首通但未推进，自动 +1（修复旧版卡顿）
---@param sub table
---@param maxFloor number
local function advanceIfStuck(sub, maxFloor)
    while (sub.cleared[sub.floor] or sub.cleared[tostring(sub.floor)])
        and sub.floor < maxFloor do
        sub.floor = sub.floor + 1
    end
end

--- 一次性：副本怪 201-206 加强 + 通天塔 2× 难度 → 回退当前可挑战层
---@param data table mod_dungeon
---@return boolean migrated
function DungeonCompat.migrateMonsterBuffV1(data)
    data.compat = data.compat or {}
    if data.compat.monsterBuffV1 then
        return false
    end

    local function apply(sub, label)
        if not sub then return end
        local old = math.floor(tonumber(sub.floor) or 1)
        local newF = DungeonCompat.rollbackFloorForBuffV1(old)
        if newF ~= old then
            print(string.format("[DungeonCompat] %s floor rollback: %d -> %d", label, old, newF))
            sub.floor = newF
        end
    end

    apply(data.gold_mine, "gold_mine")
    apply(data.ancient_ruin, "ancient_ruin")
    apply(data.babel_tower, "babel_tower")

    data.compat.monsterBuffV1 = true
    data._justMigratedMonsterBuffV1 = true
    return true
end

--- 加载/接收：结构补全 + cleared 修正 + 卡层修复；层数回退迁移仅由服务端 PDM 显式开启
---@param data table mod_dungeon
---@param opts table|nil { runMigration?: boolean }
function DungeonCompat.onLoad(data, opts)
    if not data.gold_mine then
        data.gold_mine = { floor = 1, cleared = {}, dailyUsed = 0, dailyDay = 0, idleAccumSec = 0 }
    end
    local gm = data.gold_mine
    gm.floor         = math.max(1, math.floor(tonumber(gm.floor) or 1))
    gm.dailyUsed     = math.floor(tonumber(gm.dailyUsed) or 0)
    gm.dailyDay      = math.floor(tonumber(gm.dailyDay) or 0)
    gm.idleAccumSec  = math.max(0, math.floor(tonumber(gm.idleAccumSec) or 0))
    gm.cleared       = normalizeCleared(gm.cleared)

    if not data.ancient_ruin then
        data.ancient_ruin = { floor = 1, cleared = {}, dailyUsed = 0, dailyDay = 0, idleAccumSec = 0 }
    end
    local ar = data.ancient_ruin
    ar.floor         = math.max(1, math.floor(tonumber(ar.floor) or 1))
    ar.dailyUsed     = math.floor(tonumber(ar.dailyUsed) or 0)
    ar.dailyDay      = math.floor(tonumber(ar.dailyDay) or 0)
    ar.idleAccumSec  = math.max(0, math.floor(tonumber(ar.idleAccumSec) or 0))
    ar.cleared       = normalizeCleared(ar.cleared)

    if not data.babel_tower then
        data.babel_tower = { floor = 1, cleared = {}, dailyUsed = 0, dailyDay = 0, buffs = {}, idleAccumSec = 0 }
    end
    local bt = data.babel_tower
    bt.floor         = math.max(1, math.floor(tonumber(bt.floor) or 1))
    bt.dailyUsed     = math.floor(tonumber(bt.dailyUsed) or 0)
    bt.dailyDay      = math.floor(tonumber(bt.dailyDay) or 0)
    bt.idleAccumSec  = math.max(0, math.floor(tonumber(bt.idleAccumSec) or 0))
    bt.cleared       = normalizeCleared(bt.cleared)
    if not bt.buffs then bt.buffs = {} end

    local today = math.floor((os.time() + 28800) / 86400)
    if (gm.dailyDay or 0) ~= today then
        gm.dailyUsed = 0
        gm.dailyDay  = today
    end
    if (ar.dailyDay or 0) ~= today then
        ar.dailyUsed = 0
        ar.dailyDay  = today
    end
    if (bt.dailyDay or 0) ~= today then
        bt.dailyUsed = 0
        bt.dailyDay  = today
    end

    advanceIfStuck(gm, DungeonConfig.MAX_FLOOR.gold_mine or 83)
    advanceIfStuck(ar, DungeonConfig.MAX_FLOOR.ancient_ruin or 77)

    if opts and opts.runMigration then
        DungeonCompat.migrateMonsterBuffV1(data)
    end
end

return DungeonCompat
