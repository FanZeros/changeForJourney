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
    local commitTeamChange = deps.commitTeamChange or function(teamIdx, otherTeamIdx)
        rebuildRoster()
        refreshPowerCache()
        refreshNavBadge()
        local cb = getOnTeamChanged()
        if cb then cb(teamIdx, otherTeamIdx) end
    end
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
    -- 一个Down只可消费一次。End先于Input时保留released，下一Update/Begin销毁。
    local press = {}
    local blockers = {
        { "ui.hud.popup.OfflineRewardPanel", "isOpen" }, { "ui.hud.popup.LevelUpPopup", "isOpen" },
        { "ui.hud.popup.UpdateNoticePopup", "isOpen" }, { "ui.hud.popup.PlayerInfoPanel", "isOpen" },
        { "ui.story.gate.DarkTitleScreenGate", "isOpen" }, { "ui.story.gate.StartScreen", "isOpen" },
        { "ui.story.gate.LetterIntro", "isOpen" }, { "ui.story.gate.IntroCutscene", "isActive" },
        { "ui.story.ScenarioDialogue", "isActive" }, { "ui.battle.popup.TerminalConfirmDialog", "isOpen" },
        { "ui.dungeon.DungeonBattleScene", "isOpen" }, { "ui.tower.TowerBattleScene", "isActive" },
        { "ui.dev.CEPanel", "isOpen" },
    }
    local blockerModules = {}
    local blockersLoaded = false
    local function loadBlockers()
        if blockersLoaded then return end
        -- 引擎require自有缓存，package.loaded不是其权威表。只在首个手势缓存模块引用，
        -- 后续Down/Move/End/Update只读API，绝不每帧require或创建UI/英雄。
        for i, blocker in ipairs(blockers) do blockerModules[i] = require(blocker[1]) end
        blockerModules.reward = require("ui.hud.popup.RewardPopup")
        blockersLoaded = true
    end
    local function presentationBlocked()
        if deps.isRosterInputBlocked and deps.isRosterInputBlocked() then return true end
        for i, blocker in ipairs(blockers) do
            local module = blockerModules[i]
            if module and module[blocker[2]] and module[blocker[2]]() then return true end
        end
        local reward = blockerModules.reward
        if reward and reward.isOpen and reward.isOpen() then
            local panel = reward.currentPanel and reward.currentPanel()
            local row = reward.currentRowTag and reward.currentRowTag()
            if not row and (panel == nil or panel == "right" or panel == "center") then return true end
        end
        return false
    end
    local function geometry()
        if deps.getRosterGeometry then return deps.getRosterGeometry() end
        if graphics then return graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR() end
        return 0, 0, 1
    end
    local function clearVisual()
        if Draw.clearSortInteraction then Draw.clearSortInteraction() end
        if Draw.clearTeamInteraction then Draw.clearTeamInteraction() end
    end
    local function cancelRosterInteraction()
        if press.kind then press.canceled = true end
        local drag = getDragState()
        drag.active, drag.moved = false, false
        drag.heroId, drag.rosterIdx, drag.fromSlot, drag.fromTeam = nil, nil, nil, nil
        setIsDragging(false)
        setScrollVelocity(0)
        clearVisual()
    end
    local function finishPress()
        press.consumed = true
        clearVisual()
    end
    local function hitSort(dx, dy)
        return Draw.hitTestRosterSort and Draw.hitTestRosterSort(dx, dy) or nil
    end
    local function hitHeader(dx, dy)
        return Draw.hitTestTeamHeader and Draw.hitTestTeamHeader(dx, dy) or nil
    end
    local function remember(kind, dx, dy, target, heroId)
        loadBlockers()
        local w, h, dpr = geometry()
        local mode, ascending
        if CharacterPanel.getRosterSort then mode, ascending = CharacterPanel.getRosterSort() end
        press = { kind = kind, x = dx, y = dy, target = target, heroId = heroId,
            width = w, height = h, dpr = dpr, mode = mode, ascending = ascending,
            revision = deps.getRosterSortRevision and deps.getRosterSortRevision() or 0 }
    end
    local function observeRosterIdentity()
        if not press.kind or press.canceled or press.consumed then return end
        if press.kind == "avatar" then
            local team = getTeams()[press.team]
            local slot = team and team.slots[press.target]
            if not slot or slot.heroId ~= press.heroId or slot.state ~= press.state then cancelRosterInteraction() end
        elseif press.kind == "roster" then
            local entry = getHeroRoster()[press.target]
            if not entry or entry.heroId ~= press.heroId or entry.owned ~= press.owned then cancelRosterInteraction() end
        end
    end
    local function validatePresentation()
        if not press.kind or press.canceled then return end
        observeRosterIdentity()
        local w, h, dpr = geometry()
        if w ~= press.width or h ~= press.height or dpr ~= press.dpr or presentationBlocked() then
            cancelRosterInteraction()
        end
    end
    local function pressMatches(dx, dy)
        validatePresentation()
        if press.canceled or press.consumed then return false end
        if press.kind == "sort" then
            local mode, ascending
            if CharacterPanel.getRosterSort then mode, ascending = CharacterPanel.getRosterSort() end
            return hitSort(dx, dy) == press.target and mode == press.mode and ascending == press.ascending
                and (not deps.getRosterSortRevision or deps.getRosterSortRevision() == press.revision)
        elseif press.kind == "header" then
            return hitHeader(dx, dy) == press.target
        elseif press.kind == "roster" then
            local index = hitTestRosterCard(dx, dy)
            local entry = index and getHeroRoster()[index]
            return entry and entry.heroId == press.heroId
        elseif press.kind == "avatar" then
            local team, slot = Draw.hitTestAvatarSlot(dx, dy)
            local data = team and getTeams()[team].slots[slot]
            return team == press.team and slot == press.target
                and data and data.heroId == press.heroId and data.state == press.state
        end
        return false
    end

    local function handleInput(dx, dy)
        validatePresentation()
        if CharacterDetail.isOpen() then
            cancelRosterInteraction()
            return CharacterDetail.handleInput(dx, dy)
        end

        local dragState = getDragState()
        local teamSlots = getTeamSlots()
        local slotPowerCache = getSlotPowerCache()
        local activeTeamIdx = getActiveTeamIdx()

        if press.kind and (press.canceled or press.consumed) then
            finishPress()
            dragState.active, dragState.heroId = false, nil
            dragState.rosterIdx, dragState.fromSlot, dragState.fromTeam = nil, nil, nil
            setIsDragging(false)
            return true
        end

        if dragState.active then
            finishPress()
            -- 头像行内移动时，仍按槽位命中处理交换/部署。
            local draggedHeroId = dragState.heroId
            local dropTeam, dropSlot = Draw.hitTestAvatarSlot(dx, dy)
            if dropTeam then
                local srcTeam = dragState.fromTeam or activeTeamIdx
                local srcIdx = dragState.fromSlot
                local teams = getTeams()
                local srcSlots = teams[srcTeam] and teams[srcTeam].slots
                local dstSlots = teams[dropTeam] and teams[dropTeam].slots
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
                            print(string.format("[CharacterPanel] 移动 队%d槽%d → 队%d槽%d",
                                srcTeam, srcIdx, dropTeam, dropSlot))
                        else
                            srcSlots[srcIdx], dstSlots[dropSlot] = dstSlots[dropSlot], srcSlots[srcIdx]
                            print(string.format("[CharacterPanel] 交换 队%d槽%d ↔ 队%d槽%d",
                                srcTeam, srcIdx, dropTeam, dropSlot))
                        end
                        -- 跨队一次提交两队，最终同步数据只刷新一轮。
                        commitTeamChange(srcTeam, dropTeam ~= srcTeam and dropTeam or nil)
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

        local sortTarget = hitSort(dx, dy)
        if press.kind == "sort" or sortTarget then
            local valid = press.kind == "sort" and press.released and pressMatches(dx, dy)
            local target = press.target
            finishPress()
            if valid then
                local mode, ascending = CharacterPanel.getRosterSort()
                if target == "direction" then
                    if mode ~= "default" and mode ~= "team" then CharacterPanel.setRosterSort(mode, not ascending) end
                else
                    CharacterPanel.setRosterSort(target)
                end
            end
            return true
        end

        -- 主界面的旧tab没有绘制，不能以其历史矩形抢占头像。
        local header = hitHeader(dx, dy)
        if press.kind == "header" or header then
            local valid = not press.kind or (press.kind == "header" and pressMatches(dx, dy))
            finishPress()
            if valid and header then CharacterPanel.setActiveTeam(header) end
            return true
        end
        if press.kind then
            if not pressMatches(dx, dy) or press.moved then finishPress(); return true end
            finishPress()
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
                require("systems.TutorialManager").notifyCharacterDetailOpened("avatar", slot.heroId)
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
        press = {}
        clearVisual()
        if CharacterDetail.isOpen() then
            return CharacterDetail.handleDragBegin(dx, dy)
        end

        local dragState = getDragState()
        if not dragState.active then
            dragState.heroId, dragState.rosterIdx, dragState.fromSlot, dragState.fromTeam = nil, nil, nil, nil
            dragState.moved = false
            setIsDragging(false)
        end
        if not dragState.active then
            local target, header = hitSort(dx, dy), hitHeader(dx, dy)
            if target then
                remember("sort", dx, dy, target)
                if Draw.setSortInteraction then Draw.setSortInteraction(dx, dy, true) end
                return true
            elseif header then
                remember("header", dx, dy, header)
                if Draw.setTeamInteraction then Draw.setTeamInteraction(dx, dy, true) end
                return true
            end
        end
        local avatarTeam, slotIdx = Draw.hitTestAvatarSlot(dx, dy)
        if avatarTeam then
            local slot = getTeams()[avatarTeam].slots[slotIdx]
            remember("avatar", dx, dy, slotIdx, slot.heroId)
            press.team, press.state = avatarTeam, slot.state
            if Draw.setTeamInteraction then Draw.setTeamInteraction(dx, dy, true) end
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
            end
            return true
        end

        if isInScrollArea(dx, dy) then
            local rosterIdx = hitTestRosterCard(dx, dy)
            if rosterIdx then
                local heroRoster = getHeroRoster()
                local entry = heroRoster[rosterIdx]
                if entry then
                    remember("roster", dx, dy, rosterIdx, entry.heroId)
                    press.owned = entry.owned
                end
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
        validatePresentation()
        if CharacterDetail.isOpen() then
            cancelRosterInteraction()
            return CharacterDetail.handleDragMove(dx, dy)
        end

        if press.kind and (math.abs(dx - press.x) > DRAG_THRESHOLD or math.abs(dy - press.y) > DRAG_THRESHOLD) then
            press.moved = true
            if press.kind == "sort" or press.kind == "header" then cancelRosterInteraction() end
        end
        if press.kind == "sort" or press.kind == "header" then
            if not pressMatches(dx, dy) then cancelRosterInteraction() end
            if not press.canceled then
                if press.kind == "sort" and Draw.setSortInteraction then Draw.setSortInteraction(dx, dy, true) end
                if press.kind == "header" and Draw.setTeamInteraction then Draw.setTeamInteraction(dx, dy, true) end
            end
            return true
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
        validatePresentation()
        if press.kind then press.released = true end
        if dx < 0 or dy < 0 then cancelRosterInteraction() end
        clearVisual()
        if CharacterDetail.isOpen() then
            cancelRosterInteraction()
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
        cancelRosterInteraction()
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

        local dragState = getDragState()
        dragState.active = false
        dragState.heroId = nil
        dragState.rosterIdx = nil
        dragState.fromSlot = nil
        dragState.fromTeam = nil

        commitTeamChange(avatarTeam)
        require("systems.GameSFX").play("ui_loosen")
        print(string.format("[CharacterPanel] 右键卸下 英雄%d 队伍%d 槽位%d", heroId, avatarTeam, slotIdx))
        return true
    end

    return {
        isRosterInteractionBusy = function()
            return press.kind ~= nil and not press.canceled
        end,
        observeRosterIdentity = observeRosterIdentity,
        cancelRosterInteraction = cancelRosterInteraction,
        updateRosterInteraction = function()
            validatePresentation()
            if CharacterDetail.isOpen() then cancelRosterInteraction() end
            if press.released then press = {} end
        end,
        handleInput = handleInput,
        handleDragBegin = handleDragBegin,
        handleDragMove = handleDragMove,
        handleDragEnd = handleDragEnd,
        handleScroll = handleScroll,
        handleRightClick = handleRightClick,
    }
end

return M
