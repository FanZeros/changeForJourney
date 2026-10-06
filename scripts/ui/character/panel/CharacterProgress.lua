-- ============================================================================
-- CharacterProgress - 经验升级 / 槽位等级 / 转职分支（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local ExpTable = deps.ExpTable
    local MAX_SLOTS = deps.MAX_SLOTS
    local get = deps.get
    local applyResonanceSync = deps.applyResonanceSync
    local syncTeamSlotsFromOwned = deps.syncTeamSlotsFromOwned
    local rebuildRoster = deps.rebuildRoster
    local refreshPowerCache = deps.refreshPowerCache
    local refreshNavBadge = deps.refreshNavBadge

    local function addHeroExp(heroId, amount)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        if not ownData or amount <= 0 then return end

        ownData.exp = (ownData.exp or 0) + amount

        while true do
            local currentLevel = ownData.level or 1
            if ExpTable.isHeroMaxLevel(currentLevel) then
                ownData.exp = 0
                ownData.maxExp = 0
                break
            end
            local needed = ExpTable.getHeroExpForLevel(currentLevel)
            ownData.maxExp = needed or 5
            if not needed or ownData.exp < needed then
                break
            end
            ownData.exp = ownData.exp - needed
            ownData.level = currentLevel + 1
        end

        applyResonanceSync()
        syncTeamSlotsFromOwned()
        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
    end

    local function syncSlotLevel(heroId, newLevel)
        local ownedSet = get("ownedSet")
        local teamSlots = get("teamSlots")
        local ownData = ownedSet[heroId]
        if not ownData then return end
        for i = 1, MAX_SLOTS do
            local slot = teamSlots[i]
            if slot.state == "occupied" and slot.heroId == heroId then
                slot.level  = newLevel
                slot.exp    = ownData.exp
                slot.maxExp = ownData.maxExp
                break
            end
        end
        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
    end

    local function setHeroAdvBranch(heroId, branchId, advLevel)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        if not ownData then return end
        if not ownData.advBranch then
            ownData.advBranch = {}
        end
        if advLevel == 1 then
            ownData.advBranch.first = branchId
        elseif advLevel == 2 then
            ownData.advBranch.second = branchId
        end
        local onTeamChangedCallback = get("onTeamChangedCallback")
        if onTeamChangedCallback then onTeamChangedCallback(1) end
    end

    local function resetHeroAdvBranch(heroId)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        if not ownData then return end
        ownData.advBranch = nil
        local onTeamChangedCallback = get("onTeamChangedCallback")
        if onTeamChangedCallback then onTeamChangedCallback(1) end
    end

    return {
        addHeroExp = addHeroExp,
        syncSlotLevel = syncSlotLevel,
        setHeroAdvBranch = setHeroAdvBranch,
        resetHeroAdvBranch = resetHeroAdvBranch,
    }
end

return M
