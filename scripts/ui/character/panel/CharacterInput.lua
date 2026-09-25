-- ============================================================================
-- CharacterInput - 角色面板点击/拖拽/滚轮（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local CharacterDetail = deps.CharacterDetail
    local Draw = deps.Draw
    local CharacterPanel = deps.CharacterPanel
    local hitTestTeamSlot = deps.hitTestTeamSlot
    local hitTestRosterCard = deps.hitTestRosterCard
    local getTeamSlots = deps.getTeamSlots
    local getSlotPowerCache = deps.getSlotPowerCache
    local getDragState = deps.getDragState
    local getSelectSlotState = deps.getSelectSlotState
    local selectSlotState = getSelectSlotState()
    local getTeams = deps.getTeams
    local getHeroRoster = deps.getHeroRoster
    local getShardMap = deps.getShardMap
    local getActiveTeamIdx = deps.getActiveTeamIdx
    local getOnTeamChanged = deps.getOnTeamChanged
    local deployHeroToSlot = deps.deployHeroToSlot
    local rebuildRoster = deps.rebuildRoster
    local refreshPowerCache = deps.refreshPowerCache
    local refreshNavBadge = deps.refreshNavBadge
    local isHeroDeployed = deps.isHeroDeployed
    local isInScrollArea = deps.isInScrollArea
    local clampScroll = deps.clampScroll
    local getScroll = deps.getScroll
    local setScroll = deps.setScroll
    local getIsDragging = deps.getIsDragging
    local setIsDragging = deps.setIsDragging
    local getDragLastY = deps.getDragLastY
    local setDragLastY = deps.setDragLastY
    local getDragDeltaY = deps.getDragDeltaY
    local setDragDeltaY = deps.setDragDeltaY
    local setScrollVelocity = deps.setScrollVelocity
    local SCROLL_WHEEL_STEP = deps.SCROLL_WHEEL_STEP
    local HC = deps.HC

    local DRAG_THRESHOLD = 30

    local function handleInput(dx, dy)
        if CharacterDetail.isOpen() then
            return CharacterDetail.handleInput(dx, dy)
        end

        local tabIdx = Draw.hitTestTeamTabs(dx, dy)
        if tabIdx then
            CharacterPanel.setActiveTeam(tabIdx)
            return true
        end

        -- 头像编队：点哪一队的头像就切到哪一队，空位进入选人
        local avatarTeam, avatarSlot = Draw.hitTestAvatarSlot(dx, dy)
        if avatarTeam then
            if avatarTeam ~= getActiveTeamIdx() then
                CharacterPanel.setActiveTeam(avatarTeam)
            end
            local teams = getTeams()
            local slot = teams[avatarTeam] and teams[avatarTeam].slots[avatarSlot]
            if slot and slot.state == "empty" then
                selectSlotState.open = true
                selectSlotState.slotIdx = avatarSlot
            end
            return true
        end

        local dragState = getDragState()
        local teamSlots = getTeamSlots()
        local slotPowerCache = getSlotPowerCache()
        local activeTeamIdx = getActiveTeamIdx()
        local onTeamChangedCallback = getOnTeamChanged()

        if dragState.active then
            local slotIdx = hitTestTeamSlot(dx, dy)
            if slotIdx and dragState.fromSlot then
                local srcIdx = dragState.fromSlot
                if slotIdx ~= srcIdx then
                    local srcSlot = teamSlots[srcIdx]
                    local dstSlot = teamSlots[slotIdx]
                    if dstSlot.state == "locked" then
                        print("[CharacterPanel] 目标槽位 " .. slotIdx .. " 未解锁，无法交换")
                    elseif dstSlot.state == "empty" then
                        teamSlots[slotIdx] = srcSlot
                        teamSlots[srcIdx] = { state = "empty" }
                        slotPowerCache[slotIdx] = slotPowerCache[srcIdx] or 0
                        slotPowerCache[srcIdx] = 0
                        print("[CharacterPanel] 移动槽位 " .. srcIdx .. " → " .. slotIdx)
                        rebuildRoster()
                        refreshNavBadge()
                        if onTeamChangedCallback then onTeamChangedCallback(activeTeamIdx) end
                    else
                        teamSlots[srcIdx], teamSlots[slotIdx] = teamSlots[slotIdx], teamSlots[srcIdx]
                        slotPowerCache[srcIdx], slotPowerCache[slotIdx] = slotPowerCache[slotIdx], slotPowerCache[srcIdx]
                        print("[CharacterPanel] 交换槽位 " .. srcIdx .. " ↔ " .. slotIdx)
                        rebuildRoster()
                        refreshNavBadge()
                        if onTeamChangedCallback then onTeamChangedCallback(activeTeamIdx) end
                    end
                end
            elseif slotIdx and not dragState.fromSlot then
                local slot = teamSlots[slotIdx]
                if slot.state == "empty" or slot.state == "occupied" then
                    deployHeroToSlot(dragState.heroId, slotIdx)
                end
            elseif not slotIdx and dragState.fromSlot then
                local srcIdx = dragState.fromSlot
                local srcSlot = teamSlots[srcIdx]
                if srcSlot.state == "occupied" then
                    print("[CharacterPanel] 解除出战 槽位 " .. srcIdx .. " 英雄 " .. (srcSlot.heroId or "?"))
                    teamSlots[srcIdx] = { state = "empty" }
                    slotPowerCache[srcIdx] = 0
                    rebuildRoster()
                    refreshPowerCache()
                    refreshNavBadge()
                    if onTeamChangedCallback then onTeamChangedCallback(activeTeamIdx) end
                end
            end
            dragState.active = false
            dragState.heroId = nil
            dragState.rosterIdx = nil
            dragState.fromSlot = nil
            return true
        end

        local selectSlotState = getSelectSlotState()
        local heroRoster = getHeroRoster()
        if selectSlotState.active then
            local rosterIdx = hitTestRosterCard(dx, dy)
            if rosterIdx then
                local entry = heroRoster[rosterIdx]
                if entry and entry.owned and not isHeroDeployed(entry.heroId) then
                    deployHeroToSlot(entry.heroId, selectSlotState.slotIndex)
                    selectSlotState.active = false
                    selectSlotState.slotIndex = nil
                    return true
                elseif entry and entry.owned and isHeroDeployed(entry.heroId) then
                    print("[CharacterPanel] 该角色已在出战中")
                    return true
                elseif entry and not entry.owned then
                    print("[CharacterPanel] 该角色未拥有")
                    return true
                end
            end
            selectSlotState.active = false
            selectSlotState.slotIndex = nil
        end

        local slotIdx = hitTestTeamSlot(dx, dy)
        if slotIdx then
            local slot = teamSlots[slotIdx]
            if slot.state == "locked" then
                print("[CharacterPanel] 槽位 " .. slotIdx .. " 未解锁")
            elseif slot.state == "empty" then
                selectSlotState.active = true
                selectSlotState.slotIndex = slotIdx
                print("[CharacterPanel] 槽位 " .. slotIdx .. " 已选中，请点击下方角色出战")
            elseif slot.state == "occupied" then
                print("[CharacterPanel] 查看已出战角色详情: heroId=" .. tostring(slot.heroId))
                require("systems.GameSFX").play("ui_pick")
                CharacterDetail.open(slot.heroId)
            end
            return true
        end

        local rosterIdx = hitTestRosterCard(dx, dy)
        if rosterIdx then
            local entry = heroRoster[rosterIdx]
            if entry and entry.owned then
                local _TM = require("systems.TutorialManager")
                if _TM.isActive() and _TM.getCurrentHighlight() == "character_new_hero" then
                    print("[CharacterPanel] 引导中：禁止点击打开详情，请拖拽将角色上阵")
                    return true
                end
                require("systems.GameSFX").play("ui_pick")
                CharacterDetail.open(entry.heroId)
                return true
            elseif entry and not entry.owned then
                local shardMap = getShardMap()
                local shards = shardMap[entry.heroId] or 0
                if shards >= HC.SHARD_SYNTHESIZE_COST then
                    CharacterPanel.requestSynthesizeHero(entry.heroId)
                    return true
                else
                    local heroCfg = HC.get(entry.heroId)
                    print("[CharacterPanel] " .. (heroCfg and heroCfg.name or "?")
                        .. " 碎片不足，需要 " .. HC.SHARD_SYNTHESIZE_COST
                        .. " 个，当前 " .. shards .. " 个")
                end
                return true
            end
        end

        return false
    end

    local function handleDragBegin(dx, dy)
        if CharacterDetail.isOpen() then
            return CharacterDetail.handleDragBegin(dx, dy)
        end

        local dragState = getDragState()
        local teamSlots = getTeamSlots()
        local slotIdx = hitTestTeamSlot(dx, dy)
        if slotIdx then
            local slot = teamSlots[slotIdx]
            if slot.state == "occupied" and slot.heroId then
                dragState.startX = dx
                dragState.startY = dy
                dragState.cx = dx
                dragState.cy = dy
                dragState.heroId = slot.heroId
                dragState.fromSlot = slotIdx
                dragState.rosterIdx = nil
                dragState.active = false
                dragState.moved = false
                return true
            end
        end

        if isInScrollArea(dx, dy) then
            local rosterIdx = hitTestRosterCard(dx, dy)
            if rosterIdx then
                local heroRoster = getHeroRoster()
                local entry = heroRoster[rosterIdx]
                if entry and entry.owned then
                    dragState.startX = dx
                    dragState.startY = dy
                    dragState.cx = dx
                    dragState.cy = dy
                    dragState.heroId = entry.heroId
                    dragState.rosterIdx = rosterIdx
                    dragState.fromSlot = nil
                    dragState.active = false
                    dragState.moved = false
                end
            end
        end

        if isInScrollArea(dx, dy) then
            setIsDragging(true)
            setDragLastY(dy)
            setDragDeltaY(0)
            setScrollVelocity(0)
            return true
        end
        return false
    end

    local function handleDragMove(dx, dy)
        if CharacterDetail.isOpen() then
            return CharacterDetail.handleDragMove(dx, dy)
        end

        local dragState = getDragState()
        if dragState.heroId and not dragState.active then
            local distX = math.abs(dx - dragState.startX)
            local distY = math.abs(dy - dragState.startY)

            if dragState.fromSlot then
                if distX > DRAG_THRESHOLD or distY > DRAG_THRESHOLD then
                    dragState.active = true
                    dragState.moved = true
                    require("systems.GameSFX").play("ui_pick")
                end
            else
                if distY > DRAG_THRESHOLD and (dragState.startY - dy) > DRAG_THRESHOLD then
                    dragState.active = true
                    dragState.moved = true
                    require("systems.GameSFX").play("ui_pick")
                    setIsDragging(false)
                    setScrollVelocity(0)
                end
            end
        end

        if dragState.active then
            dragState.cx = dx
            dragState.cy = dy
            return true
        end

        if getIsDragging() then
            local dragDeltaY = getDragLastY() - dy
            setDragDeltaY(dragDeltaY)
            setScroll(getScroll() + dragDeltaY)
            clampScroll()
            setDragLastY(dy)
            return true
        end

        return false
    end

    local function handleDragEnd(dx, dy)
        if CharacterDetail.isOpen() then
            setIsDragging(false)
            local dragState = getDragState()
            dragState.active = false
            dragState.heroId = nil
            dragState.rosterIdx = nil
            dragState.fromSlot = nil
            CharacterDetail.handleDragEnd(dx, dy)
            return true
        end

        local dragState = getDragState()
        if dragState.heroId and not dragState.active then
            dragState.heroId = nil
            dragState.rosterIdx = nil
            dragState.fromSlot = nil
        end

        if getIsDragging() then
            setIsDragging(false)
            setScrollVelocity(-getDragDeltaY())
        end

        return true
    end

    local function handleScroll(wheel, dx, dy)
        if CharacterDetail.isOpen() then
            CharacterDetail.handleScroll(wheel, dx, dy)
            return
        end
        setScroll(getScroll() - wheel * SCROLL_WHEEL_STEP)
        clampScroll()
        setScrollVelocity(0)
    end

    local function handleRightClick(dx, dy)
        if CharacterDetail.isOpen() then
            return CharacterDetail.handleRightClick(dx, dy)
        end
        return false
    end

    return {
        handleInput = handleInput,
        handleDragBegin = handleDragBegin,
        handleDragMove = handleDragMove,
        handleDragEnd = handleDragEnd,
        handleScroll = handleScroll,
        handleRightClick = handleRightClick,
    }
end

return M
