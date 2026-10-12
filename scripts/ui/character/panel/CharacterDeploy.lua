-- ============================================================================
-- CharacterDeploy - 出战部署 / 空槽查找（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local HC = deps.HC
    local MAX_SLOTS = deps.MAX_SLOTS
    local TEAM_COUNT = deps.TEAM_COUNT
    local getTeams = deps.getTeams
    local getTeamSlots = deps.getTeamSlots
    local getActiveTeamIdx = deps.getActiveTeamIdx
    local getOwnedSet = deps.getOwnedSet
    local rebuildRoster = deps.rebuildRoster
    local refreshPowerCache = deps.refreshPowerCache
    local refreshNavBadge = deps.refreshNavBadge
    local getOnTeamChanged = deps.getOnTeamChanged
    local commitTeamChange = deps.commitTeamChange or function(teamIdx, otherTeamIdx)
        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
        local cb = getOnTeamChanged()
        if cb then cb(teamIdx, otherTeamIdx) end
    end

    local function findHeroTeamIdx(heroId)
        local teams = getTeams()
        for t = 1, TEAM_COUNT do
            local slots = teams[t] and teams[t].slots
            if slots then
                for i = 1, #slots do
                    local slot = slots[i]
                    if slot.state == "occupied" and slot.heroId == heroId then
                        return t
                    end
                end
            end
        end
        return nil
    end

    local function deployHeroToSlot(heroId, slotIdx)
        local teamSlots = getTeamSlots()
        local slot = teamSlots[slotIdx]
        if not slot then return false end
        if slot.state == "locked" then return false end

        local ownedSet = getOwnedSet()
        local ownData = ownedSet[heroId]
        if not ownData then
            print("[CharacterPanel] 英雄 " .. heroId .. " 未拥有，无法出战")
            return false
        end

        local activeTeamIdx = getActiveTeamIdx()
        -- [三队并行] 跨队唯一性: 已在其他队 → 先从原队移出（同一英雄全局只能在一队）
        local otherTeam = findHeroTeamIdx(heroId)
        if otherTeam and otherTeam ~= activeTeamIdx then
            local teams = getTeams()
            local otherSlots = teams[otherTeam].slots
            for i = 1, #otherSlots do
                if otherSlots[i].state == "occupied" and otherSlots[i].heroId == heroId then
                    if slot.state == "occupied" and slot.heroId and slot.heroId ~= heroId then
                        otherSlots[i] = slot
                        print(string.format("[CharacterPanel] 英雄%d 与队伍%d槽%d 交换", heroId, otherTeam, i))
                    else
                        otherSlots[i] = { state = "empty" }
                        print(string.format("[CharacterPanel] 英雄%d 从队伍%d 移到当前队伍%d", heroId, otherTeam, activeTeamIdx))
                    end
                    break
                end
            end
        end

        -- 如果该英雄已在其他槽位，先移除
        for i = 1, MAX_SLOTS do
            if teamSlots[i].state == "occupied" and teamSlots[i].heroId == heroId then
                teamSlots[i] = { state = "empty" }
                break
            end
        end

        -- 如果目标槽位已有角色，先取消（回到列表）
        if slot.state == "occupied" and slot.heroId then
            print("[CharacterPanel] 槽位 " .. slotIdx .. " 原角色 " .. slot.heroId .. " 被替换")
        end

        -- 部署
        teamSlots[slotIdx] = {
            state  = "occupied",
            heroId = heroId,
            level  = ownData.level,
            exp    = ownData.exp,
            maxExp = ownData.maxExp,
        }

        local heroCfg = HC.get(heroId)
        print("[CharacterPanel] 部署 " .. (heroCfg and heroCfg.name or "?") .. " 到槽位 " .. slotIdx)

        -- 同步回执刷新最终编队；没有同步宿主时只做一次本地刷新。
        commitTeamChange(activeTeamIdx, otherTeam ~= activeTeamIdx and otherTeam or nil)

        require("systems.GameSFX").play("ui_loosen")

        -- 真实编队回调可能回滚；中央校验会重新读取提交后的队一槽位4。
        require("systems.TutorialManager").notifyHeroDeployed(heroId, activeTeamIdx, slotIdx)

        return true
    end

    local function findFirstEmptySlot()
        local teamSlots = getTeamSlots()
        for i = 1, MAX_SLOTS do
            if teamSlots[i].state == "empty" then
                return i
            end
        end
        return nil
    end

    return {
        findHeroTeamIdx = findHeroTeamIdx,
        deployHeroToSlot = deployHeroToSlot,
        findFirstEmptySlot = findFirstEmptySlot,
    }
end

return M
