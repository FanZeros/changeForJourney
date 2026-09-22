-- ============================================================================
-- ChurchBadge - 教堂入口角标查询（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local HC = deps.HC
    local ClassChange = deps.ClassChange
    local CharacterPanel = deps.CharacterPanel
    local GameState = deps.GameState
    local AVC = deps.AVC
    local ArtifactPanel = deps.ArtifactPanel
    local getDispatcher = deps.getDispatcher

    local function hasAdvanceForHero(heroId)
        local heroCfg = HC.get(heroId)
        if not heroCfg then return false end
        local classId = heroCfg.classId
        -- 该职业需要有转职分支
        if not ClassChange.FIRST_ADV_BRANCHES[classId] then return false end
        -- 需要已拥有
        local ownData = CharacterPanel.getOwnedHero(heroId)
        if not ownData then return false end
        local heroLevel = ownData.level or 1
        local advBranch = ownData.advBranch
        local gold = GameState.getGold()
        -- 一转可用：等级达标 且 尚未一转 且 金币足够
        local cost1 = AVC.COST[1]
        if heroLevel >= ClassChange.ADV2.firstLevel and (not advBranch or not advBranch.first)
           and cost1 and gold >= cost1.gold then
            return true
        end
        -- 二转可用：等级达标 且 已一转 且 尚未二转 且 金币足够
        local cost2 = AVC.COST[2]
        if heroLevel >= ClassChange.ADV2.secondLevel and advBranch and advBranch.first and not advBranch.second
           and cost2 and gold >= cost2.gold then
            return true
        end
        return false
    end

    local function hasAnyAdvance()
        local allIds = HC.getAllIds()
        for _, id in ipairs(allIds) do
            if CharacterPanel.isOwned(id) and CharacterPanel.isHeroDeployed(id) and hasAdvanceForHero(id) then
                return true
            end
        end
        return false
    end

    local function hasAnyUnusedTalent()
        local talentsData = getDispatcher().get("talents")
        local playerData  = getDispatcher().get("player")
        local litCount   = (talentsData and talentsData.litNodes) and #talentsData.litNodes or 1
        local usedPoints = litCount - 1
        local maxPoints  = (playerData and playerData.level) or 1
        local remaining  = maxPoints - usedPoints
        return remaining > 0
    end

    local function hasAnyChurchBadge()
        return hasAnyUnusedTalent() or hasAnyAdvance() or ArtifactPanel.canUpgradeAnyArtifact()
    end

    local function getChurchBadgeInfo()
        if hasAnyUnusedTalent() or ArtifactPanel.canUpgradeAnyArtifact() then
            return true, nil        -- 绿色箭头
        elseif hasAnyAdvance() then
            return true, "redDot"   -- 红点
        else
            return false, nil
        end
    end

    return {
        hasAdvanceForHero = hasAdvanceForHero,
        hasAnyAdvance = hasAnyAdvance,
        hasAnyUnusedTalent = hasAnyUnusedTalent,
        hasAnyChurchBadge = hasAnyChurchBadge,
        getChurchBadgeInfo = getChurchBadgeInfo,
    }
end

return M
