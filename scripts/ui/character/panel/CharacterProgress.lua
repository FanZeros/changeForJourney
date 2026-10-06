-- ============================================================================
-- CharacterProgress - 经验升级 / 槽位等级 / 转职分支（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local ExpTable = deps.ExpTable
    local get = deps.get
    local applyResonanceSync = deps.applyResonanceSync
    local syncTeamSlotsFromOwned = deps.syncTeamSlotsFromOwned
    local rebuildRoster = deps.rebuildRoster
    local refreshPowerCache = deps.refreshPowerCache
    local refreshNavBadge = deps.refreshNavBadge
    local getHeroDeployPosition = deps.getHeroDeployPosition
    local persistHeroExp = deps.persistHeroExp

    -- 养成回执不是编队交易；只通知真实所属队，未上阵不借用当前编辑队。
    local function refreshHeroProgress(heroId)
        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
        local _, teamIdx = getHeroDeployPosition(heroId)
        local callback = get("onHeroProgressChangedCallback")
        if teamIdx and callback then callback(heroId, teamIdx) end
    end

    local function isFinite(value)
        return type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge
    end

    local function addHeroExp(heroId, amount)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        if not ownData or not isFinite(amount) or amount <= 0 then return false end
        -- 拒绝损坏来源和溢出；不得让 NaN/inf 进入共鸣排序或持久化。
        for _, hero in pairs(ownedSet) do
            if not isFinite(hero.level) or hero.level < 1 or hero.level % 1 ~= 0
                or not isFinite(hero.exp or 0) or (hero.exp or 0) < 0
                or (hero.maxExp ~= nil and not isFinite(hero.maxExp)) then return false end
        end
        local newExp = (ownData.exp or 0) + amount
        if not isFinite(newExp) then return false end

        -- 共鸣也可能提升旁队/未上阵英雄；只提交本次真正变化的经验字段，
        -- 不能把面板中过期的整份英雄覆盖到持久化 roster。
        local before = {}
        if persistHeroExp then
            for id, hero in pairs(ownedSet) do
                before[id] = { level = hero.level, exp = hero.exp, maxExp = hero.maxExp }
            end
        end
        ownData.exp = newExp

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
        if persistHeroExp then
            local changed = {}
            for id, hero in pairs(ownedSet) do
                local prior = before[id]
                if prior then
                    local patch = {}
                    for _, field in ipairs({ "level", "exp", "maxExp" }) do
                        if prior[field] ~= hero[field] then patch[field] = hero[field] end
                    end
                    if next(patch) then changed[id] = patch end
                end
            end
            persistHeroExp(changed)
        end
        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
        return true
    end

    local function syncSlotLevel(heroId, newLevel)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        if not ownData then return false end
        -- 编辑队只是视图；等级回执同步真实所属队的槽位快照。
        local partySlot, teamIdx = getHeroDeployPosition(heroId)
        local teams = get("teams") or {}
        local team = teamIdx and teams[teamIdx]
        local slot = team and team.slots[partySlot]
        if slot then
            slot.level  = newLevel
            slot.exp    = ownData.exp
            slot.maxExp = ownData.maxExp
        end
        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
        return true
    end

    local function setHeroAdvBranch(heroId, branchId, advLevel)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        if not ownData then return false end
        if advLevel ~= 1 and advLevel ~= 2 then return false end
        if not ownData.advBranch then
            ownData.advBranch = {}
        end
        if advLevel == 1 then
            ownData.advBranch.first = branchId
        elseif advLevel == 2 then
            ownData.advBranch.second = branchId
        end
        refreshHeroProgress(heroId)
        return true
    end

    local function resetHeroAdvBranch(heroId)
        local ownedSet = get("ownedSet")
        local ownData = ownedSet[heroId]
        if not ownData then return false end
        ownData.advBranch = nil
        refreshHeroProgress(heroId)
        return true
    end

    return {
        addHeroExp = addHeroExp,
        syncSlotLevel = syncSlotLevel,
        setHeroAdvBranch = setHeroAdvBranch,
        resetHeroAdvBranch = resetHeroAdvBranch,
    }
end

return M
