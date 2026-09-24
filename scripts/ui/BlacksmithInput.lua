-- ============================================================================
-- BlacksmithInput - BlacksmithPage 点击/拖拽/滚轮（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local EquipmentBag = deps.EquipmentBag
    local BlacksmithEnhance = deps.BlacksmithEnhance
    local BlacksmithDecompose = deps.BlacksmithDecompose
    local BlacksmithRefine = deps.BlacksmithRefine
    local TownPageChrome = deps.TownPageChrome
    local TAB_ITEMS = deps.TAB_ITEMS
    local state = deps.state
    local forceClose = deps.forceClose
    local closePage = deps.closePage
    local BlacksmithPage = deps.BlacksmithPage
    local CharacterPanel = deps.CharacterPanel
    local EquipmentDetail = deps.EquipmentDetail
    local getEquipSlotCX = deps.getEquipSlotCX
    local getEquipSlotCY = deps.getEquipSlotCY
    local EQUIP_SLOT_ORDER = deps.EQUIP_SLOT_ORDER
    local SLIDER_W = deps.SLIDER_W
    local SLIDER_H = deps.SLIDER_H
    local hitTest = deps.hitTest
    local CARD_CY = deps.CARD_CY
    local CARD_W = deps.CARD_W
    local CARD_H = deps.CARD_H
    local EQUIP_SLOT_SIZE = deps.EQUIP_SLOT_SIZE
    local MAX_PARTY = deps.MAX_PARTY
    local getCardSlotCX = deps.getCardSlotCX
    local deriveSelectedEquip = deps.deriveSelectedEquip

    local function handleDragBegin(dx, dy)
        if not state.open or state.closing then return true end
        if EquipmentBag.isOpen() then return EquipmentBag.handleDragBegin(dx, dy) end
        -- 一键强化确认弹窗滑块
        if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
            BlacksmithEnhance.handleDialogDragBegin(dx, dy)
            return true
        end
        -- 分解 tab：记录触摸起点用于滚动
        if state.tab == "fenjie" then
            BlacksmithDecompose.handleDragBegin(dx, dy)
        end
        return true  -- 铁匠铺打开时消费所有拖拽
    end

    --- 拖拽移动
    ---@param dx number 设计空间 X
    ---@param dy number 设计空间 Y
    ---@return boolean 是否消费事件
    local function handleDragMove(dx, dy)
        if not state.open or state.closing then return true end
        if EquipmentBag.isOpen() then return EquipmentBag.handleDragMove(dx, dy) end
        -- 一键强化确认弹窗滑块
        if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
            BlacksmithEnhance.handleDialogDragMove(dx, dy)
            return true
        end
        -- 分解 tab：滑动滚动背包列表
        if state.tab == "fenjie" then
            BlacksmithDecompose.handleDragMove(dx, dy)
        end
        return true
    end

    --- 拖拽结束
    ---@param dx number 设计空间 X
    ---@param dy number 设计空间 Y
    ---@return boolean 是否消费事件
    local function handleDragEnd(dx, dy)
        if not state.open then return false end
        if EquipmentBag.isOpen() then return EquipmentBag.handleDragEnd(dx, dy) end
        -- 一键强化确认弹窗滑块释放
        if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
            BlacksmithEnhance.handleDialogDragEnd()
            return true
        end
        -- 分解 tab：清除触摸状态
        if state.tab == "fenjie" then
            BlacksmithDecompose.handleDragEnd(dx, dy)
        end
        return true
    end

    --- 鼠标滚轮滚动
    ---@param wheel number 滚轮值
    ---@param dx number|nil
    ---@param dy number|nil
    local function handleScroll(wheel, dx, dy)
        if not state.open or state.closing then return end
        if EquipmentBag.isOpen() then EquipmentBag.handleScroll(wheel, dx, dy); return end
        -- 分解 tab：滚轮滚动背包列表
        if state.tab == "fenjie" then
            BlacksmithDecompose.handleScroll(wheel, dx, dy)
        end
    end

    --- 处理输入
    ---@param dx number 设计空间 X
    ---@param dy number 设计空间 Y
    ---@return boolean 是否消费事件
    local function handleInput(dx, dy)
        if not state.open then return false end
        if state.closing then
            -- 安全保护：如果关闭动画超过 1 秒仍未完成，强制关闭
            local closingElapsed = time.elapsedTime - state.closeTime
            if closingElapsed > 1.0 then
                print("[BlacksmithPage] handleInput: 关闭动画超时(" .. string.format("%.2f", closingElapsed) .. "s)，强制关闭")
                forceClose()
                return false
            end
            return true
        end

        -- 装备背包优先处理
        if EquipmentBag.isOpen() then
            return EquipmentBag.handleInput(dx, dy)
        end

        -- 装备详情面板交互（长按触发，优先级最高）
        if state.tab == "fenjie" and EquipmentDetail.isOpen() then
            return EquipmentDetail.handleInput(dx, dy)
        end

        -- 自动分解弹窗交互（优先级最高）
        if state.tab == "fenjie" and BlacksmithDecompose.isPopupOpen() then
            return BlacksmithDecompose.handlePopupInput(dx, dy)
        end

        -- 一键强化确认弹窗（强化 tab，优先级最高）
        if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
            return BlacksmithEnhance.handleDialogInput(dx, dy)
        end

        -- 返回按钮（三行模式由中缝层接管）
        if TownPageChrome.hitBack(dx, dy) then
            closePage()
            return true
        end

        -- 编队卡片 + 装备槽点击（仅强化 tab）
        if state.tab == "qianghua" then
            -- 5 张编队卡片点击
            for i = 1, MAX_PARTY do
                local cx = getCardSlotCX(i)
                if hitTest(dx, dy, cx, CARD_CY, CARD_W, CARD_H) then
                    if i ~= state.selectedPartySlot then
                        state.selectedPartySlot = i
                        deriveSelectedEquip()
                        print("[BlacksmithPage] 选中编队槽位: " .. i)
                    end
                    return true
                end
            end
            -- 6 个装备槽点击
            for i, slotKey in ipairs(EQUIP_SLOT_ORDER) do
                local cx = getEquipSlotCX(i)
                local cy = getEquipSlotCY(i)
                if hitTest(dx, dy, cx, cy, EQUIP_SLOT_SIZE, EQUIP_SLOT_SIZE) then
                    if slotKey ~= state.selectedEquipSlot then
                        state.selectedEquipSlot = slotKey
                        deriveSelectedEquip()
                        print("[BlacksmithPage] 选中装备槽: " .. slotKey)
                    end
                    return true
                end
            end
        end

        -- 洗练 tab：单个装备槽点击（打开装备背包选择）
        if state.tab == "xilian" then
            local slotCX, slotCY, slotSize = 540, 431, 160
            if hitTest(dx, dy, slotCX, slotCY, slotSize, slotSize) then
                -- 洗练独立板块：slot=nil 显示全部装备（已装备+未装备），heroId=nil 不限英雄
                EquipmentBag.open(nil, "全部装备", nil, function(seq, equip)
                    if equip then
                        state.selectedEquip = equip
                        BlacksmithRefine.updateRefineData(equip)
                        print("[BlacksmithPage] 洗练选择装备: seq=" .. tostring(seq) .. " name=" .. (equip.name or "?"))
                    end
                end)
                return true
            end
        end

        -- Tab 切换检测
        do
            local i = TownPageChrome.hitTab(dx, dy, TAB_ITEMS, SLIDER_W, SLIDER_H)
            if i then
                local tabKeys = { "qianghua", "xilian", "fenjie" }
                local newTab = tabKeys[i]
                if state.tab ~= newTab then
                    state.tabFrom = state.tab
                    state.tabSwitchTime = time.elapsedTime
                    state.tab = newTab
                    require("systems.GameSFX").playUIMove(2)
                    -- 切换到强化 tab 时恢复装备选择（洗练 tab 会清空 selectedEquip）
                    if newTab == "qianghua" then
                        deriveSelectedEquip()
                    end
                    -- 切换到洗练 tab 时重置装备选择（洗练槽位独立选择，不继承强化面板）
                    if newTab == "xilian" then
                        state.selectedEquip = nil
                        BlacksmithRefine.updateRefineData(nil)
                    end
                    -- 切换到分解 tab 时重置分解状态
                    if newTab == "fenjie" then
                        BlacksmithDecompose.onTabSwitch()
                        BlacksmithDecompose.refreshBackpackItems()
                    end
                    print("[BlacksmithPage] 切换到: " .. TAB_ITEMS[i].name)
                end
                return true
            end
        end

        -- Tab 内部输入：委托给对应子模块
        if state.tab == "qianghua" and state.selectedEquip then
            return BlacksmithEnhance.handleInput(dx, dy)
        elseif state.tab == "xilian" and state.selectedEquip then
            return BlacksmithRefine.handleInput(dx, dy)
        elseif state.tab == "fenjie" then
            return BlacksmithDecompose.handleInput(dx, dy)
        end

        -- 面板内其他区域，消费事件不关闭
        return true
    end

    return {
        handleDragBegin = handleDragBegin,
        handleDragMove = handleDragMove,
        handleDragEnd = handleDragEnd,
        handleScroll = handleScroll,
        handleInput = handleInput,
    }
end

return M
