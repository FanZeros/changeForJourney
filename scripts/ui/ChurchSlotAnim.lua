-- ============================================================================
-- ChurchSlotAnim - 教堂槽位展开/选择/滑动动画（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local ANIM = deps.ANIM
    local CHAR_SLOT = deps.CHAR_SLOT
    local HC = deps.HC
    local state = deps.state
    local resetRosterScrollState = deps.resetRosterScrollState
    local easeOutCubic = deps.easeOutCubic

    --- 展开槽位（点击空槽位后）
    local function expandSlot()
        if state.slotExpanded then return end
        state.slotAnimDir = 1
        state.slotAnimTime = time.elapsedTime
        state.slotExpanded = true
        state.rosterScrollY = 0
        resetRosterScrollState()
        -- 列表随槽位上移一起显示（不需要单独滑入）
        state.rosterSlideProgress = 1.0
        state.rosterSlideDir = 0
        print("[ChurchPage] 展开角色列表")
    end

    --- 收起槽位
    local function collapseSlot()
        if not state.slotExpanded then return end
        state.slotAnimDir = -1
        state.slotAnimTime = time.elapsedTime
        state.slotExpanded = false
        print("[ChurchPage] 收起角色列表")
    end

    --- 选择英雄放入槽位（带飞行动画 + 列表滑出）
    local function selectHero(heroId, fromCX, fromCY)
        state.selectedHeroId = heroId
        state.slotAnimDir = 0
        -- slotLiftProgress 保持 1.0，不动

        -- 启动卡片飞行动画
        state.selectAnim = true
        state.selectAnimTime = time.elapsedTime
        state.selectAnimFromX = fromCX or CHAR_SLOT.CX
        state.selectAnimFromY = fromCY or CHAR_SLOT.CY

        -- 启动列表向下滑出动画（不立即隐藏）
        state.rosterSlideDir = -1
        state.rosterSlideTime = time.elapsedTime
        state.rosterSlideProgress = 1.0

        local heroCfg = HC.get(heroId)
        print("[ChurchPage] 选择冒险家: " .. (heroCfg and heroCfg.name or ("ID:" .. heroId)))
    end

    --- 更新槽位动画进度
    local function updateSlotAnim()
        if state.slotAnimDir == 0 then return end

        local elapsed = time.elapsedTime - state.slotAnimTime
        local t = math.min(1.0, elapsed / ANIM.SLOT_DUR)
        local eased = easeOutCubic(t)

        if state.slotAnimDir == 1 then
            state.slotLiftProgress = eased
        else
            state.slotLiftProgress = 1.0 - eased
        end

        if t >= 1.0 then
            state.slotAnimDir = 0
            if not state.slotExpanded then
                state.slotLiftProgress = 0
            else
                state.slotLiftProgress = 1.0
            end
        end
    end

    --- 更新卡片飞行动画
    local function updateSelectAnim()
        if not state.selectAnim then return end
        local elapsed = time.elapsedTime - state.selectAnimTime
        local t = math.min(1.0, elapsed / ANIM.SELECT_DUR)
        if t >= 1.0 then
            state.selectAnim = false
            state.slotExpanded = false
        end
    end

    --- 更新角色列表滑入/滑出动画
    local function updateRosterSlide()
        if state.rosterSlideDir == 0 then return end
        local elapsed = time.elapsedTime - state.rosterSlideTime
        local t = math.min(1.0, elapsed / ANIM.ROSTER_SLIDE_DUR)
        local eased = easeOutCubic(t)
        if state.rosterSlideDir == 1 then
            state.rosterSlideProgress = eased
        else
            state.rosterSlideProgress = 1.0 - eased
        end
        if t >= 1.0 then
            state.rosterSlideDir = 0
            if state.rosterSlideProgress < 0.01 then
                state.rosterSlideProgress = 0
                state.slotExpanded = false
            else
                state.rosterSlideProgress = 1.0
            end
        end
    end

    return {
        expandSlot = expandSlot,
        collapseSlot = collapseSlot,
        selectHero = selectHero,
        updateSlotAnim = updateSlotAnim,
        updateSelectAnim = updateSelectAnim,
        updateRosterSlide = updateRosterSlide,
    }
end

return M
