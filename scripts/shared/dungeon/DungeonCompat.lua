-- DungeonCompat.lua — 副本/通天塔存档兼容（新结构补全与旧难度迁移）
local DungeonConfig = require("config.DungeonConfig")
local TowerConfig = require("config.TowerConfig")

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
    if type(cleared) ~= "table" then return {} end
    local fixed = {}
    for k, v in pairs(cleared) do
        local numK = math.tointeger(tonumber(k) or 0)
        -- 只接受整数层号；false 不能成为已通关记录，也不将小数层截断成别的层。
        if numK and numK >= 1 and v then
            fixed[numK] = true
        end
    end
    return fixed
end

--- 若当前层已首通但未推进，自动 +1（修复旧版卡顿）
---@param sub table
---@param maxFloor number
local function advanceIfStuck(sub, maxFloor)
    -- 旧难度回退要求无奖重打，不能被下一次加载的卡层修复立即抵消。
    local replayUntil = math.floor(tonumber(sub.monsterBuffReplayUntil) or 0)
    if sub.floor < replayUntil then return end
    sub.monsterBuffReplayUntil = nil
    while (sub.cleared[sub.floor] or sub.cleared[tostring(sub.floor)])
        and sub.floor < maxFloor do
        sub.floor = sub.floor + 1
    end
end

--- 一次性：副本怪 201-206 加强 + 通天塔 2× 难度 → 回退当前可挑战层
---@param data table mod_dungeon
---@return boolean migrated
function DungeonCompat.migrateMonsterBuffV1(data)
    if type(data.compat) ~= "table" then data.compat = {} end
    if data.compat.monsterBuffV1 then
        return false
    end

    local function apply(sub, label)
        if type(sub) ~= "table" then return end
        local old = math.max(1, math.floor(tonumber(sub.floor) or 1))
        local newF = DungeonCompat.rollbackFloorForBuffV1(old)
        if newF ~= old then
            print(string.format("[DungeonCompat] %s floor rollback: %d -> %d", label, old, newF))
            sub.floor = newF
            if label ~= "babel_tower" then sub.monsterBuffReplayUntil = old end
        end
    end

    -- 此迁移只覆盖当年的旧副本；新装备/黑钻的独立进度绝不能回退。
    apply(data.gold_mine, "gold_mine")
    apply(data.ancient_ruin, "ancient_ruin")
    apply(data.babel_tower, "babel_tower")

    data.compat.monsterBuffV1 = true
    data._justMigratedMonsterBuffV1 = true
    return true
end

--- 首次读档：无账本旧资源档以有效 floor-1 证明连续已通历史，先落到 cleared。
--- Registry 比 Schema 更早调用本入口，必须先于规范化以免非空坏账本被清空后误补。
---@param data table mod_dungeon
local function migrateResourceClearedV1(data)
    if type(data.compat) ~= "table" then data.compat = {} end
    if data.compat.resourceClearedV1 then return end
    for _, id in ipairs(DungeonConfig.RESOURCE_IDS) do
        local sub = data[id]
        if type(sub) == "table" then
            local cleared = sub.cleared
            local noLedger = cleared == nil or (type(cleared) == "table" and next(cleared) == nil)
            local floor = math.tointeger(tonumber(sub.floor) or 0)
            local maxFloor = DungeonConfig.LEGACY_MAX_FLOOR[id]
            -- floor=1 不授予首层；小数/非法/越界值不能经后续规范化变成迁移凭据。
            if noLedger and floor and floor > 1 and floor <= maxFloor + 1 then
                local history = {}
                for clearedFloor = 1, floor - 1 do history[clearedFloor] = true end
                sub.cleared = history
                print(string.format("[DungeonCompat] %s legacy cleared migrated: 1..%d", id, floor - 1))
            end
        end
    end
    -- 新档与非空账本也标记此次判定，重复加载不重推断、不补齐新章节跳过的层。
    data.compat.resourceClearedV1 = true
end

--- 单波爬塔保持原层号；在可能的旧难度回退之前冻结已经领取的首通历史。
--- 无账本旧资源档只信旧上界，新内容不可由越界 floor 凭空解锁。
local function migrateProgressionV2(data)
    if type(data.compat) ~= "table" then data.compat = {} end
    if not data.compat.resourceProgressionV2 then
        for _, id in ipairs(DungeonConfig.RESOURCE_IDS) do
            local sub = data[id]
            if type(sub) == "table" then
                local oldMax = DungeonConfig.LEGACY_MAX_FLOOR[id]
                local floor = tonumber(sub.floor) or 1
                if floor > oldMax + 1 and (type(sub.cleared) ~= "table" or next(sub.cleared) == nil) then
                    sub.floor = 1
                end
            end
        end
        data.compat.resourceProgressionV2 = true
    end
    if data.compat.towerSingleWaveV2 then return end
    local bt = data.babel_tower
    if type(bt) == "table" then
        local floor = math.tointeger(tonumber(bt.floor) or 0)
        bt.cleared = type(bt.cleared) == "table" and bt.cleared or {}
        if floor and floor > 1 and floor <= TowerConfig.MAX_FLOOR + 1 then
            for history = 1, floor - 1 do bt.cleared[history] = true end
        end
    end
    data.compat.towerSingleWaveV2 = true
end

--- 加载/接收：幂等补全结构、修正 key 和日计数；无账本旧资源档先迁移已通历史。
--- 旧难度迁移仍只由服务端或显式 runMigration 开启，不扩展到新 ID。
---@param data table mod_dungeon
---@param opts table|nil { runMigration?: boolean }
function DungeonCompat.onLoad(data, opts)
    migrateResourceClearedV1(data)
    migrateProgressionV2(data)
    local today = math.floor((os.time() + 28800) / 86400)
    for _, id in ipairs({ "gold_mine", "ancient_ruin", "equipment_vault", "black_diamond", "babel_tower" }) do
        if type(data[id]) ~= "table" then
            data[id] = {}
        end
        local sub = data[id]
        sub.floor        = math.max(1, math.floor(tonumber(sub.floor) or 1))
        sub.dailyUsed    = math.max(0, math.floor(tonumber(sub.dailyUsed) or 0))
        sub.dailyDay     = math.max(0, math.floor(tonumber(sub.dailyDay) or 0))
        sub.idleAccumSec = math.max(0, math.floor(tonumber(sub.idleAccumSec) or 0))
        sub.cleared      = normalizeCleared(sub.cleared)
        if id == "equipment_vault" then
            sub.idleConsumedSec = math.max(0, math.floor(tonumber(sub.idleConsumedSec) or 0))
            if sub.idleAccumSec == 0 then sub.idleConsumedSec = 0 end
        end
        if sub.dailyDay ~= today then
            sub.dailyUsed = 0
            sub.dailyDay  = today
        end
        if id == "babel_tower" then
            if type(sub.buffs) ~= "table" then sub.buffs = {} end
        elseif id == "ancient_ruin" or DungeonConfig.isResourceDungeon(id) then
            advanceIfStuck(sub, DungeonConfig.MAX_FLOOR[id])
        end
    end

    if opts and opts.runMigration then
        DungeonCompat.migrateMonsterBuffV1(data)
    end
end

return DungeonCompat
