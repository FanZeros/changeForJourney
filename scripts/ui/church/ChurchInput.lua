-- ============================================================================
-- ChurchInput - ChurchPage 点击/拖拽/滚轮（玩法不变）
-- ============================================================================

local TownPageChrome = require("ui.town.TownPageChrome")

local M = {}

function M.bind(deps)
    local ANIM = deps.ANIM
    local CHAR_SLOT = deps.CHAR_SLOT
    local ClassChange = deps.ClassChange  -- 转职已迁出，保留注入但不使用
    local TalentPanel = deps.TalentPanel
    local ArtifactPanel = deps.ArtifactPanel
    local TownPageChrome = deps.TownPageChrome
    local TAB_ITEMS = deps.TAB_ITEMS
    local TAB_KEYS = deps.TAB_KEYS
    local TAB = deps.TAB
    local CHURCH = deps.CHURCH
    local ROSTER = deps.ROSTER
    local DESIGN_W = deps.DESIGN_W
    local DESIGN_H = deps.DESIGN_H
    local clampRosterScroll = deps.clampRosterScroll
    local isRosterVisible = deps.isRosterVisible
    local isInRosterScrollArea = deps.isInRosterScrollArea
    local expandSlot = deps.expandSlot
    local collapseSlot = deps.collapseSlot
    local selectHero = deps.selectHero
    local getOwnedHeroList = deps.getOwnedHeroList
    local forceClose = deps.forceClose
    ---@type fun()
    local closeChurch = deps.closePage
    local resetRosterScrollState = deps.resetRosterScrollState
    local TalentStarMap = deps.TalentStarMap
    local state = deps.state
    local hitTest = deps.hitTest

    local function handleInput(dx, dy)
        if not state.open then return false end
        if state.closing then
            -- 安全保护：关闭动画超过 1 秒仍未完成，强制关闭
            local closingElapsed = time.elapsedTime - state.closeTime
            if closingElapsed > 1.0 then
                print("[ChurchPage] handleInput: 关闭动画超时(" .. string.format("%.2f", closingElapsed) .. "s)，强制关闭")
                forceClose()
                return false
            end
            return true
        end

        -- 转职确认/重置弹窗已随转职页迁到右侧栏角色详情

        -- 天赋详情/总览已独立到 TalentPage

        -- ========== 神器 Tab 交互 → 委托 ArtifactPanel ==========
        if state.tab == "shenqi" then
            local consumed = ArtifactPanel.handleTabInput(dx, dy)
            if consumed then return true end
        end

        -- 返回按钮（三行模式由中缝层接管）
        if TownPageChrome.hitBack(dx, dy) then
            closeChurch() -- close church page
            return true
        end

        -- 转职选人已迁出，教堂不再展开角色列表
        if false and state.slotExpanded and state.slotLiftProgress > 0.9 then
            local ownedList = getOwnedHeroList()
            local rosterCount = #ownedList
            local scrollOff = state.rosterScrollY
            for idx, entry in ipairs(ownedList) do
                -- 与 drawRosterList 完全一致的居中分布计算
                local row = math.ceil(idx / ROSTER.MAX_PER_ROW)
                local col = idx - (row - 1) * ROSTER.MAX_PER_ROW    -- 1~5

                local rowStart = (row - 1) * ROSTER.MAX_PER_ROW + 1
                local rowEnd   = math.min(row * ROSTER.MAX_PER_ROW, rosterCount)
                local rowCount = rowEnd - rowStart + 1

                local rowCY = ROSTER.ROW1_CY + (row - 1) * ROSTER.ROW_SPACING - scrollOff
                local totalW = rowCount * ROSTER.CARD_W + (rowCount - 1) * ROSTER.CARD_SPACING
                local startCX = (DESIGN_W - totalW) * 0.5 + ROSTER.CARD_W * 0.5
                local cx = startCX + (col - 1) * (ROSTER.CARD_W + ROSTER.CARD_SPACING)
                local cy = rowCY

                if hitTest(dx, dy, cx, cy, ROSTER.CARD_W, ROSTER.CARD_H) then
                    selectHero(entry.heroId, cx, cy)
                    return true
                end
            end
        end

        -- 角色选择框已随转职页迁出
        if false then
            local slotOY = -ANIM.SLOT_LIFT * state.slotLiftProgress
            local slotCY = CHAR_SLOT.CY + slotOY
            if hitTest(dx, dy, CHAR_SLOT.CX, slotCY, CHAR_SLOT.W, CHAR_SLOT.H) then
                if state.slotExpanded then
                    -- 已展开时点击槽位 → 收起
                    collapseSlot()
                elseif state.slotLiftProgress >= 1.0 then
                    -- 槽位已在上移位置（之前选过角色）→ 列表从下方滑入
                    state.slotExpanded = true
                    state.slotAnimDir = 0
                    state.rosterScrollY = 0
                    resetRosterScrollState()
                    state.rosterSlideDir = 1
                    state.rosterSlideTime = time.elapsedTime
                    state.rosterSlideProgress = 0
                    print("[ChurchPage] 重新展开角色列表（从下方滑入）")
                else
                    -- 未展开且未上移 → 展开角色列表（播放上移动画）
                    state.selectedHeroId = nil  -- 清除已选角色
                    expandSlot()
                end
                return true
            end
        end

        -- 转职角色列表面板已迁出
        if false and not state.selectAnim then
            local listTopY = ROSTER.LIST_BG_CY - ROSTER.LIST_BG_H * 0.5
            if state.slotExpanded and state.rosterSlideProgress > 0.5 then
                -- 列表展开时，点击列表背景上方区域 → 列表向下滑出
                if dy < listTopY then
                    if state.selectedHeroId then
                        -- 已选过角色：仅滑出列表，保持槽位上移
                        state.rosterSlideDir = -1
                        state.rosterSlideTime = time.elapsedTime
                        state.rosterSlideProgress = 1.0
                        print("[ChurchPage] 点击上方区域，滑出角色列表")
                    else
                        -- 未选过角色：完全收起（槽位下移回原位）
                        collapseSlot()
                        print("[ChurchPage] 点击上方区域，收起角色列表")
                    end
                    return true
                end
            elseif not state.slotExpanded and state.slotLiftProgress >= 1.0 and state.selectedHeroId then
                -- 已选角色、转职树显示时，点击上方空白区域 → 重新展开角色列表
                if dy < listTopY then
                    state.slotExpanded = true
                    state.slotAnimDir = 0
                    state.rosterScrollY = 0
                    resetRosterScrollState()
                    state.rosterSlideDir = 1
                    state.rosterSlideTime = time.elapsedTime
                    state.rosterSlideProgress = 0
                    print("[ChurchPage] 点击上方区域，重新展开角色列表")
                    return true
                end
            end
        end

        -- 转职分支点击已随转职页迁到右侧栏角色详情

        -- Tab 切换检测
        do
            local i = TownPageChrome.hitTab(dx, dy, TAB_ITEMS, TAB.SLIDER_W, TAB.SLIDER_H)
            if i then
                local newTab = TAB_KEYS[i]
                if state.tab ~= newTab then
                    state.tabFrom = state.tab
                    state.tabSwitchTime = time.elapsedTime
                    state.tab = newTab
                    require("systems.GameSFX").playUIMove(2)

                    if newTab ~= "shenqi" then
                        state._deferClearHero = true
                        -- 冻结槽位动画（不独立收起，整体跟 tab 一起滑走）
                        if state.slotExpanded then
                            state.slotExpanded = false
                        end
                        state.slotAnimDir = 0  -- 停止独立动画
                    else
                        state._deferClearHero = false
                    end

                    print("[ChurchPage] 切换到 " .. newTab)
                end
                return true
            end
        end

        return true  -- 教堂打开时消费所有点击
    end

    -- ======================== 拖拽三段式 ========================

    -- ======================== 拖拽三段式 → 委托 TalentPanel ========================

    --- 拖拽开始
    ---@return boolean consumed
    local function handleDragBegin(dx, dy)
        if not state.open or state.closing then return false end

        if isRosterVisible() and isInRosterScrollArea(dx, dy) then
            state.rosterDragging = true
            state.rosterLastDragY = dy
            state.rosterScrollVelocity = 0
            return true
        end

        if state.tab ~= "shenqi" then return false end
        return ArtifactPanel.handleDragBegin(dx, dy)
    end

    --- 拖拽移动
    ---@return boolean consumed
    local function handleDragMove(dx, dy)
        if not state.open or state.closing then return false end

        if state.rosterDragging then
            local delta = state.rosterLastDragY - dy
            state.rosterScrollY = state.rosterScrollY + delta
            state.rosterLastDragY = dy
            state.rosterScrollVelocity = -delta
            clampRosterScroll()
            return true
        end

        if state.tab ~= "shenqi" then return false end
        return ArtifactPanel.handleDragMove(dx, dy)
    end

    --- 拖拽结束
    local function handleDragEnd(dx, dy)
        if not state.open or state.closing then return end
        if state.rosterDragging then
            state.rosterDragging = false
            return
        end
        if state.tab == "shenqi" then
            ArtifactPanel.handleDragEnd(dx, dy)
        end
    end

    --- 鼠标滚轮滚动
    ---@param wheel number
    ---@param msx number|nil 鼠标设计坐标X (滚轮缩放锚点用, 可为nil)
    ---@param msy number|nil 鼠标设计坐标Y
    local function handleScroll(wheel, msx, msy)
        if not state.open or state.closing then return end
        if isRosterVisible() and (msx == nil or isInRosterScrollArea(msx, msy)) then
            state.rosterScrollY = state.rosterScrollY - wheel * 80
            state.rosterScrollVelocity = 0
            clampRosterScroll()
            return
        end
        if state.tab == "shenqi" then
            ArtifactPanel.handleScroll(wheel, msx, msy)
        end
    end


    return {
        handleInput = handleInput,
        handleDragBegin = handleDragBegin,
        handleDragMove = handleDragMove,
        handleDragEnd = handleDragEnd,
        handleScroll = handleScroll,
    }
end

return M
