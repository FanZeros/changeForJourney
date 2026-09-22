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
    local getTeamPowerCaches = deps.getTeamPowerCaches
    local getSlotPowerCache = deps.getSlotPowerCache
    local calcHeroPower = deps.calcHeroPower
    local rebuildRoster = deps.rebuildRoster
    local refreshPowerCache = deps.refreshPowerCache
    local refreshNavBadge = deps.refreshNavBadge
    local getOnTeamChanged = deps.getOnTeamChanged

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
            local teamPowerCaches = getTeamPowerCaches()
            for i = 1, #otherSlots do
                if otherSlots[i].state == "occupied" and otherSlots[i].heroId == heroId then
                    otherSlots[i] = { state = "empty" }
                    if teamPowerCaches[otherTeam] then teamPowerCaches[otherTeam][i] = 0 end
                    print(string.format("[CharacterPanel] 英雄%d 从队伍%d 移出，编入当前队伍%d", heroId, otherTeam, activeTeamIdx))
                    -- 先同步原队（单机: 队1 需刷新战斗画面；联机: 先提交原队再提交当前队，避免服务端唯一性校验拒绝）
                    local cb = getOnTeamChanged()
                    if cb then cb(otherTeam) end
                    break
                end
            end
        end

        -- 如果该英雄已在其他槽位，先移除
        local slotPowerCache = getSlotPowerCache()
        for i = 1, MAX_SLOTS do
            if teamSlots[i].state == "occupied" and teamSlots[i].heroId == heroId then
                teamSlots[i] = { state = "empty" }
                slotPowerCache[i] = 0
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
        slotPowerCache[slotIdx] = calcHeroPower(heroId, slotIdx)

        local heroCfg = HC.get(heroId)
        print("[CharacterPanel] 部署 " .. (heroCfg and heroCfg.name or "?") .. " 到槽位 " .. slotIdx)

        -- 重建列表（排序会变化）
        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()

        -- 通知阵容变更
        local cb = getOnTeamChanged()
        if cb then cb(activeTeamIdx) end

        require("systems.GameSFX").play("ui_loosen")

        -- 新手引导：若拖拽的是引导高亮的新英雄，触发 drag_to_slot_3 推进
        do
            local _TM = require("systems.TutorialManager")
            if _TM.isActive() and _TM.getNewHeroId() == heroId and slotIdx == 3 then
                _TM.notifyEvent("drag_to_slot_3")
            end
        end

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
