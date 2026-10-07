-- ============================================================================
-- CharacterRosterSort - 名册纯排序与战力索引重映射（不创建英雄、不改编队）
-- ============================================================================

local M = {}
local MODES = { default = true, team = true, power = true, level = true, rarity = true }

function M.bind(deps)
    local mode, ascending = "default", false
    local powersById = {}
    local pending = false
    local revision = 0

    local function idKey(id) return tonumber(id) or id end
    local function number(value)
        if type(value) ~= "number" or value ~= value then return 0 end
        return value
    end

    local function positions()
        local result = {}
        local teams = deps.getTeams()
        for teamIdx = 1, deps.TEAM_COUNT do
            local team = teams[teamIdx]
            local slots = team and team.slots or {}
            for slotIdx = 1, deps.MAX_SLOTS do
                local slot = slots[slotIdx]
                if slot and slot.state == "occupied" and slot.heroId then
                    local key = idKey(slot.heroId)
                    if not result[key] then result[key] = { team = teamIdx, slot = slotIdx } end
                end
            end
        end
        return result
    end

    local function compare(roster)
        -- 全部原始键在排序前取一次；比较器只读，不触发属性/神器/评分管线。
        local deployed, keys = positions(), {}
        for _, entry in ipairs(roster) do
            local id = idKey(entry.heroId)
            local cfg = deps.HC.get(entry.heroId)
            keys[entry] = { id = id, quality = number(cfg and cfg.quality),
                level = number(entry.level), power = number(powersById[id]),
                shards = number(entry.shards), position = deployed[id] }
        end
        return function(a, b)
            if a == b then return false end
            if a.owned ~= b.owned then return a.owned == true end
            local ak, bk = keys[a], keys[b]
            if a.owned then
                if mode == "default" or mode == "team" then
                    local ap, bp = ak.position, bk.position
                    if (ap ~= nil) ~= (bp ~= nil) then return ap ~= nil end
                    if mode == "team" and ap and bp then
                        if ap.team ~= bp.team then return ap.team < bp.team end
                        if ap.slot ~= bp.slot then return ap.slot < bp.slot end
                    end
                    if ak.quality ~= bk.quality then return ak.quality > bk.quality end
                    if ak.level ~= bk.level then return ak.level > bk.level end
                else
                    local key = mode == "rarity" and "quality" or mode
                    local av, bv = ak[key], bk[key]
                    if av ~= bv then
                        if ascending then return av < bv end
                        return av > bv
                    end
                end
            else
                -- 未拥有沿原稀有度/ID稳定序，不以碎片、虚构等级/零战力排序。
                if ak.quality ~= bk.quality then return ak.quality > bk.quality end
            end
            return ak.id < bk.id
        end
    end

    local function remap()
        local roster, cache = deps.getHeroRoster(), deps.getPowerCache()
        for i, entry in ipairs(roster) do
            cache[i] = entry.owned and (powersById[idKey(entry.heroId)] or 0) or 0
        end
        for i = #cache, #roster + 1, -1 do cache[i] = nil end
    end

    local function sortNow()
        local roster = deps.getHeroRoster()
        local oldOrder = {}
        for i, entry in ipairs(roster) do oldOrder[i] = entry.heroId end
        local less = compare(roster)
        local needsSort = false
        for i = 2, #roster do
            if less(roster[i], roster[i - 1]) then needsSort = true; break end
        end
        if needsSort then table.sort(roster, less) end
        remap()
        pending = false
        for i, entry in ipairs(roster) do
            if oldOrder[i] ~= entry.heroId then revision = revision + 1; break end
        end
    end

    local function requestSort()
        pending = true
        if not deps.isInteractionBusy() then sortNow() end
    end

    local function rebuild()
        local roster, ownedSet, shards = deps.getHeroRoster(), deps.getOwnedSet(), deps.getShardMap()
        local previous, entries = {}, {}
        for _, entry in ipairs(roster) do previous[#previous + 1] = entry.heroId end
        for _, id in ipairs(deps.HC.getAllIds()) do
            local own = ownedSet[id]
            entries[id] = { heroId = id, owned = own ~= nil,
                level = own and own.level or 1, exp = own and own.exp or 0,
                maxExp = own and own.maxExp or (deps.ExpTable.getHeroExpForLevel(1) or 5),
                shards = shards[id] or 0 }
        end
        for i = #roster, 1, -1 do roster[i] = nil end
        -- 水合期间也保住按下时的索引：已有ID顺序不动，新ID追加，删除不复活。
        for _, id in ipairs(previous) do
            if entries[id] then roster[#roster + 1] = entries[id]; entries[id] = nil end
        end
        for _, id in ipairs(deps.HC.getAllIds()) do
            if entries[id] then roster[#roster + 1] = entries[id] end
        end
        remap()
        requestSort()
    end

    local function powerRefreshed()
        local roster, cache = deps.getHeroRoster(), deps.getPowerCache()
        local mapped = {}
        for i, entry in ipairs(roster) do
            if entry.owned then mapped[idKey(entry.heroId)] = cache[i] or 0 end
        end
        powersById = mapped
        if mode == "power" then requestSort() end
    end

    local function setSort(requestedMode, requestedAscending)
        if type(requestedMode) ~= "string" or not MODES[requestedMode]
            or (requestedAscending ~= nil and type(requestedAscending) ~= "boolean") then return false end
        local direction = requestedAscending
        if requestedMode == "default" then direction = false
        elseif requestedMode == "team" then direction = true
        elseif direction == nil then direction = false end
        deps.cancelInteraction()
        mode, ascending = requestedMode, direction
        sortNow()
        return true
    end

    return {
        rebuild = rebuild,
        powerRefreshed = powerRefreshed,
        setSort = setSort,
        getSort = function() return mode, ascending end,
        getRevision = function() return revision end,
        getPower = function(id) return powersById[idKey(id)] end,
        flush = function()
            if pending and not deps.isInteractionBusy() then sortNow(); return true end
            return false
        end,
        reset = function()
            mode, ascending, powersById, pending = "default", false, {}, false
            revision = revision + 1
            deps.cancelInteraction()
        end,
    }
end

return M
