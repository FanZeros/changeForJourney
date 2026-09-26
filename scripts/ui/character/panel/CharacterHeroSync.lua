-- ============================================================================
-- CharacterHeroSync - setHeroesData / resetSessionData（玩法不变）
-- ============================================================================

local ExtraTalentSystem = require("systems.ExtraTalentSystem")

local M = {}

function M.bind(deps)
    local ExpTable = deps.ExpTable
    local GameState = deps.GameState
    local MAX_SLOTS = deps.MAX_SLOTS
    local TEAM_COUNT = deps.TEAM_COUNT
    local get = deps.get
    local set = deps.set
    local buildDefaultSlots = deps.buildDefaultSlots
    local calcHeroPower = deps.calcHeroPower
    local rebuildRoster = deps.rebuildRoster
    local refreshPowerCache = deps.refreshPowerCache
    local refreshNavBadge = deps.refreshNavBadge

    local function setHeroesData(data)
        if not data then return end

        do
            local deployedStr = "nil"
            if data.deployed and type(data.deployed) == "table" then
                local ids = {}
                for i, v in ipairs(data.deployed) do ids[i] = tostring(v) end
                deployedStr = "[" .. table.concat(ids, ",") .. "]"
            end
            local rosterCount = 0
            if data.roster then
                for _ in pairs(data.roster) do rosterCount = rosterCount + 1 end
            end
            print(string.format("[DIAG-HERO] setHeroesData ENTER deployed=%s rosterFieldCount=%d",
                deployedStr, rosterCount))
        end

        local ownedSet = {}
        local shardMap = {}
        if data.roster then
            for heroId, heroData in pairs(data.roster) do
                local numId = tonumber(heroId) or heroId
                shardMap[numId] = heroData.shards or 0
                if heroData.level then
                    local level = heroData.level
                    local exp   = heroData.exp or 0
                    local maxExp = heroData.maxExp
                    if not maxExp or maxExp == 0 then
                        maxExp = ExpTable.getHeroExpForLevel(level) or 5
                    end
                    ownedSet[numId] = {
                        level  = level,
                        exp    = exp,
                        maxExp = maxExp,
                        advBranch = heroData.advBranch,
                        awakening = heroData.awakening,
                        dupeCount = heroData.dupeCount or 0,
                        shards = heroData.shards or 0,
                        extraTalent = ExtraTalentSystem.normalize(heroData.extraTalent),
                    }
                end
            end
        end
        set("ownedSet", ownedSet)
        set("shardMap", shardMap)

        do
            local ownedKeys = {}
            for k, v in pairs(ownedSet) do
                ownedKeys[#ownedKeys + 1] = tostring(k) .. "(lv" .. tostring(v.level) .. ")"
            end
            print(string.format("[DIAG-HERO] setHeroesData AFTER_ROSTER ownedSet={%s}",
                table.concat(ownedKeys, ",")))
        end

        local teams = get("teams")
        local function buildSlotsFromIds(ids)
            local unlocked = ExpTable.getUnlockedSlotCountForTeam(GameState.getLevel())
            local cnt = ids and #ids or 0
            if cnt > unlocked then
                unlocked = cnt
            end
            local slots = {}
            for i = 1, MAX_SLOTS do
                slots[i] = { state = (i <= unlocked) and "empty" or "locked" }
            end
            for idx, heroId in ipairs(ids or {}) do
                local numId = tonumber(heroId) or heroId
                if idx <= MAX_SLOTS then
                    local ownData = ownedSet[numId]
                    if ownData then
                        slots[idx] = {
                            state  = "occupied",
                            heroId = numId,
                            level  = ownData.level,
                            exp    = ownData.exp,
                            maxExp = ownData.maxExp,
                        }
                    else
                        print(string.format("[DIAG-HERO] WARNING: slots[%d]=%s NOT in ownedSet! Slot stays empty.",
                            idx, tostring(numId)))
                    end
                end
            end
            return slots
        end

        if data.deployed then
            teams[1].slots = buildSlotsFromIds(data.deployed)
        end
        if data.teams and type(data.teams) == "table" then
            for t = 2, TEAM_COUNT do
                local tdata = data.teams[t]
                if type(tdata) == "table" and type(tdata.slots) == "table" then
                    teams[t].slots = buildSlotsFromIds(tdata.slots)
                end
            end
        end

        do
            local seenHero = {}
            for t = 1, TEAM_COUNT do
                local slots = teams[t] and teams[t].slots
                if slots then
                    for i = 1, #slots do
                        local s = slots[i]
                        if s.state == "occupied" and s.heroId then
                            if seenHero[s.heroId] then
                                print(string.format("[CharacterPanel] 去重: 英雄%d 重复编队，移出队伍%d", s.heroId, t))
                                slots[i] = { state = "empty" }
                            else
                                seenHero[s.heroId] = true
                            end
                        end
                    end
                end
            end
        end

        local teamPowerCaches = get("teamPowerCaches")
        local activeTeamIdx = get("activeTeamIdx")
        for t = 1, TEAM_COUNT do
            ---@type table
            local cache = teamPowerCaches[t]
            for k in pairs(cache) do cache[k] = nil end
            local slots = teams[t].slots
            for i = 1, #slots do
                if slots[i].state == "occupied" and slots[i].heroId then
                    cache[i] = calcHeroPower(slots[i].heroId, i)
                end
            end
        end
        set("teamSlots", teams[activeTeamIdx].slots)
        set("slotPowerCache", teamPowerCaches[activeTeamIdx])

        do
            local teamsInfo = {}
            for t = 1, TEAM_COUNT do
                local ids = {}
                local slots = teams[t].slots
                for i = 1, #slots do
                    ids[i] = tostring(slots[i].heroId or (slots[i].state == "locked" and "L" or "-"))
                end
                teamsInfo[t] = "T" .. t .. "[" .. table.concat(ids, ",") .. "]"
            end
            print(string.format("[DIAG-HERO] setHeroesData AFTER_TEAMS active=%d %s",
                activeTeamIdx, table.concat(teamsInfo, " ")))
        end

        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
    end

    local function resetSessionData()
        local teams = get("teams")
        local teamPowerCaches = get("teamPowerCaches")
        for t = 1, TEAM_COUNT do
            teams[t].slots = buildDefaultSlots(t)
            teamPowerCaches[t] = {}
        end
        set("activeTeamIdx", 1)
        set("teamSlots", teams[1].slots)
        set("slotPowerCache", teamPowerCaches[1])
        set("runtimeOnlyPowerCache", 0)
        set("ownedSet", {})
        set("shardMap", {})
        set("heroRoster", {})
        set("rosterPowerCache", {})
        set("upgradeBadgeCache", {})
        set("scrollY", 0)
        set("scrollVelocity", 0)
        set("isDragging", false)
        local dragState = get("dragState")
        dragState.active = false
        dragState.heroId = nil
        dragState.rosterIdx = nil
        dragState.fromSlot = nil
        dragState.fromTeam = nil
        local selectSlotState = get("selectSlotState")
        selectSlotState.active = false
        selectSlotState.slotIndex = nil
        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
        print("[CharacterPanel] session data reset")
    end

    return {
        setHeroesData = setHeroesData,
        resetSessionData = resetSessionData,
    }
end

return M
