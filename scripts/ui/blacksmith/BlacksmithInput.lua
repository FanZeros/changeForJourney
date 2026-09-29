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
    local EquipmentDetail = deps.EquipmentDetail
    local SLIDER_W = deps.SLIDER_W
    local SLIDER_H = deps.SLIDER_H
    local hitTest = deps.hitTest
    local SELECT_SLOT_CX = deps.SELECT_SLOT_CX
    local SELECT_SLOT_CY = deps.SELECT_SLOT_CY
    local SELECT_SLOT_SIZE = deps.SELECT_SLOT_SIZE
    local deriveSelectedEquip = deps.deriveSelectedEquip

    --- 打开装备背包选择装备（强化/洗练共用；slot=nil 显示全部装备）
    local function openEquipBagPicker()
        EquipmentBag.open(nil, "全部装备", nil, function(seq, equip)
            if equip then
                state.selectedEquip = equip
                state.selectedSeq = equip.seq
                if equip.slot then state.selectedEquipSlot = equip.slot end
                BlacksmithEnhance.updateEnhanceData(equip)
                BlacksmithRefine.updateRefineData(equip)
                print("[BlacksmithPage] 选择装备: seq=" .. tostring(seq)
                    .. " slot=" .. tostring(equip.slot) .. " name=" .. (equip.name or "?"))
            end
        end)
    end

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

        -- 强化/洗练 tab：点击选择槽打开装备背包（与洗练一致的选装备交互）
        if state.tab == "qianghua" or state.tab == "xilian" then
            if hitTest(dx, dy, SELECT_SLOT_CX, SELECT_SLOT_CY, SELECT_SLOT_SIZE, SELECT_SLOT_SIZE) then
                openEquipBagPicker()
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
                    -- 强化/洗练共用 selectedEquip：切换到这两个 tab 时确保数据已刷新
                    if newTab == "qianghua" or newTab == "xilian" then
                        if state.selectedEquip then
                            BlacksmithEnhance.updateEnhanceData(state.selectedEquip)
                            BlacksmithRefine.updateRefineData(state.selectedEquip)
                        else
                            deriveSelectedEquip()
                        end
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
