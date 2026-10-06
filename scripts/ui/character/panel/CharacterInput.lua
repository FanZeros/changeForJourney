-- ============================================================================
-- CharacterInput - 角色面板点击/拖拽/滚轮（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local CharacterDetail = deps.CharacterDetail
    local Draw = deps.Draw
    local CharacterPanel = deps.CharacterPanel
    local hitTestRosterCard = deps.hitTestRosterCard
    local getTeamSlots = deps.getTeamSlots
    local getSlotPowerCache = deps.getSlotPowerCache
    local getDragState = deps.getDragState
    local getSelectSlotState = deps.getSelectSlotState
    local selectSlotState = getSelectSlotState()
    local getTeams = deps.getTeams
    local getTeamPowerCaches = deps.getTeamPowerCaches
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

        local dragState = getDragState()
        local teamSlots = getTeamSlots()
        local slotPowerCache = getSlotPowerCache()
        local activeTeamIdx = getActiveTeamIdx()
        local onTeamChangedCallback = getOnTeamChanged()

        if dragState.active then
            -- 头像行内移动时，仍按槽位命中处理交换/部署。
            local draggedHeroId = dragState.heroId
            local dropTeam, dropSlot = Draw.hitTestAvatarSlot(dx, dy)
            if dropTeam then
                local srcTeam = dragState.fromTeam or activeTeamIdx
                local srcIdx = dragState.fromSlot
                local teams = getTeams()
                local powerCaches = getTeamPowerCaches()
                local srcSlots = teams[srcTeam] and teams[srcTeam].slots
                local dstSlots = teams[dropTeam] and teams[dropTeam].slots
                local srcCache = powerCaches[srcTeam]
                local dstCache = powerCaches[dropTeam]
                local dstSlot = dstSlots and dstSlots[dropSlot]
                if not dstSlot or dstSlot.state == "locked" then
                    print("[CharacterPanel] 目标槽位 " .. dropSlot .. " 未解锁，无法交换")
                elseif srcIdx and srcSlots then
                    -- 槽位之间拖拽：同队或跨队都直接交换/移动，不切队
                    if not (srcTeam == dropTeam and dropSlot == srcIdx) then
                        local srcSlot = srcSlots[srcIdx]
                        if dstSlot.state == "empty" then
                            dstSlots[dropSlot] = srcSlot
                            srcSlots[srcIdx] = { state = "empty" }
                            if dstCache then dstCache[dropSlot] = (srcCache and srcCache[srcIdx]) or 0 end
                            if srcCache then srcCache[srcIdx] = 0 end
                            print(string.format("[CharacterPanel] 移动 队%d槽%d → 队%d槽%d",
                                srcTeam, srcIdx, dropTeam, dropSlot))
                        else
                            srcSlots[srcIdx], dstSlots[dropSlot] = dstSlots[dropSlot], srcSlots[srcIdx]
                            if srcCache and dstCache then
                                srcCache[srcIdx], dstCache[dropSlot] = dstCache[dropSlot], srcCache[srcIdx]
                            end
                            print(string.format("[CharacterPanel] 交换 队%d槽%d ↔ 队%d槽%d",
                                srcTeam, srcIdx, dropTeam, dropSlot))
                        end
                        rebuildRoster()
                        refreshPowerCache()
                        refreshNavBadge()
                        if onTeamChangedCallback then
                            -- 跨队交换必须一次性提交两队，逐队同步会在第一轮刷新时覆盖第二队槽位。
                            onTeamChangedCallback(srcTeam, dropTeam ~= srcTeam and dropTeam or nil)
                        end
                        require("systems.TutorialManager").notifyHeroDeployed(draggedHeroId, dropTeam, dropSlot)
                    end
                else
                    -- 从名册拖上来：编入目标队（跨队唯一性由部署函数处理）
                    if dropTeam ~= getActiveTeamIdx() and not CharacterPanel.setActiveTeam(dropTeam) then
                        print("[CharacterPanel] 目标队伍未解锁，取消拖拽")
                    else
                        deployHeroToSlot(draggedHeroId, dropSlot)
                    end
                end
            elseif dragState.fromSlot then
                -- 松手在非槽位处只取消本次拖拽；切换队伍不能顺带卸下英雄。
                print("[CharacterPanel] 取消头像拖拽 hero=" .. tostring(draggedHeroId))
            end
            dragState.active = false
            dragState.heroId = nil
            dragState.rosterIdx = nil
            dragState.fromSlot = nil
            dragState.fromTeam = nil
            return true
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
            if slot and slot.state == "occupied" and slot.heroId then
                require("systems.GameSFX").play("ui_pick")
                CharacterDetail.open(slot.heroId)
            elseif slot and slot.state == "empty" then
                selectSlotState.active = true
                selectSlotState.slotIndex = avatarSlot
            end
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

        local rosterIdx = hitTestRosterCard(dx, dy)
        if rosterIdx then
            local entry = heroRoster[rosterIdx]
            if dragState.moved or dragState.active then
                return true
            end
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
                end
                -- 碎片不够时仍可查看属性，配装和转职在详情里禁用。
                require("systems.GameSFX").play("ui_pick")
                CharacterDetail.open(entry.heroId)
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
        local avatarTeam, slotIdx = Draw.hitTestAvatarSlot(dx, dy)
        if avatarTeam then
            local slot = getTeams()[avatarTeam].slots[slotIdx]
            if slot.state == "occupied" and slot.heroId then
                dragState.startX = dx
                dragState.startY = dy
                dragState.cx = dx
                dragState.cy = dy
                dragState.heroId = slot.heroId
                dragState.fromSlot = slotIdx
                dragState.fromTeam = avatarTeam
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
                    dragState.fromTeam = nil
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
                -- 任意方向超过阈值都算拖拽上阵，避免松手被当成点击打开详情
                if distX > DRAG_THRESHOLD or distY > DRAG_THRESHOLD then
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
            dragState.fromTeam = nil
            CharacterDetail.handleDragEnd(dx, dy)
            return true
        end

        local dragState = getDragState()
        if dragState.heroId and not dragState.active then
            dragState.heroId = nil
            dragState.rosterIdx = nil
            dragState.fromSlot = nil
            dragState.fromTeam = nil
        elseif dragState.moved or dragState.active then
            dragState.moved = true
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

        -- 编队槽右键卸下，回到下方名册。空槽和锁定槽不处理。
        local avatarTeam, slotIdx = Draw.hitTestAvatarSlot(dx, dy)
        if not avatarTeam then return false end
        local teams = getTeams()
        local slots = teams[avatarTeam] and teams[avatarTeam].slots
        local slot = slots and slots[slotIdx]
        if not slot or slot.state ~= "occupied" or not slot.heroId then return false end

        local heroId = slot.heroId
        slots[slotIdx] = { state = "empty" }
        local caches = getTeamPowerCaches()
        if caches[avatarTeam] then caches[avatarTeam][slotIdx] = 0 end

        local dragState = getDragState()
        dragState.active = false
        dragState.heroId = nil
        dragState.rosterIdx = nil
        dragState.fromSlot = nil
        dragState.fromTeam = nil

        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
        local cb = getOnTeamChanged()
        if cb then cb(avatarTeam) end
        require("systems.GameSFX").play("ui_loosen")
        print(string.format("[CharacterPanel] 右键卸下 英雄%d 队伍%d 槽位%d", heroId, avatarTeam, slotIdx))
        return true
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
