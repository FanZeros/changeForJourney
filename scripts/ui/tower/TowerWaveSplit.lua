-- ============================================================================
-- TowerWaveSplit - 通天塔一波怪物 ×2 后按品质均分到三行
-- ============================================================================

local MC          = require("config.MonsterConfig")
local TowerConfig = require("config.TowerConfig")
local BattleLayout = require("core.BattleLayout")

local TowerWaveSplit = {}

local TEAM_COUNT = 3

local function monsterQuality(monsterId)
    local tpl = MC.MONSTERS and MC.MONSTERS[monsterId]
    return (tpl and tpl.quality) or 1
end

local function expandIds(monsters)
    local ids = {}
    for _, entry in ipairs(monsters or {}) do
        local monsterId, count
        if type(entry) == "number" then
            monsterId, count = entry, 1
        else
            monsterId = entry.id or entry[1]
            count = entry.count or entry[2] or 1
        end
        monsterId = tonumber(monsterId)
        count = tonumber(count) or 1
        if monsterId then
            for _ = 1, count do
                ids[#ids + 1] = monsterId
            end
        end
    end
    return ids
end

--- 把服务端一波怪物列表翻倍后均分到三行
---@param monsters any
---@param monsterLevel number
---@return table[] lanes { { field = table[], queue = table[] }, ... } 长度 3
function TowerWaveSplit.splitToLanes(monsters, monsterLevel)
    local ids = expandIds(monsters)
    local doubled = {}
    for _ = 1, 2 do
        for i = 1, #ids do
            doubled[#doubled + 1] = ids[i]
        end
    end

    local statMult = TowerConfig.MONSTER_STAT_MULT or 1.0
    local units = {}
    for i = 1, #doubled do
        local unit = MC.createMonster(doubled[i], monsterLevel, { statMult = statMult })
        if unit then
            unit.quality = monsterQuality(doubled[i])
            units[#units + 1] = unit
        end
    end

    table.sort(units, function(a, b)
        local qa, qb = a.quality or 1, b.quality or 1
        if qa ~= qb then return qa > qb end
        return (a.maxHp or 0) > (b.maxHp or 0)
    end)

    local buckets = {}
    for t = 1, TEAM_COUNT do
        buckets[t] = {}
    end
    for i = 1, #units do
        local lane = ((i - 1) % TEAM_COUNT) + 1
        local bucket = buckets[lane]
        bucket[#bucket + 1] = units[i]
        units[i]._towerLane = lane
    end

    local fieldMax = BattleLayout.MAX_PER_SIDE or 4
    local lanes = {}
    for t = 1, TEAM_COUNT do
        local field, queue = {}, {}
        local list = buckets[t]
        for i = 1, #list do
            if #field < fieldMax then
                field[#field + 1] = list[i]
            else
                queue[#queue + 1] = list[i]
            end
        end
        lanes[t] = { field = field, queue = queue }
        print(string.format("[TowerWaveSplit] lane%d field=%d queue=%d", t, #field, #queue))
    end
    print(string.format("[TowerWaveSplit] total units=%d (ids=%d x2)", #units, #ids))
    return lanes
end

return TowerWaveSplit
