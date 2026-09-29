-- ============================================================================
-- BlacksmithInput - BlacksmithPage 点击/拖拽/滚轮
-- [锻炉双页 0929] 重写：
--   - 分解 tab 已迁至仓库；EquipmentBag 选择页已移除
--   - 编队卡片/6装备槽点击移除；上半部分只有一个工作台槽
--   - 点击工作台槽：已选装备 → 查看装备详情；空槽 → toast 提示从仓库拖入
-- ============================================================================

local M = {}

function M.bind(deps)
    local BlacksmithEnhance = deps.BlacksmithEnhance
    local BlacksmithRefine = deps.BlacksmithRefine
    local TAB_ITEMS = deps.TAB_ITEMS
    local state = deps.state
    local forceClose = deps.forceClose
    local closePage = deps.closePage
    local SLIDER_W = deps.SLIDER_W
    local SLIDER_H = deps.SLIDER_H
    local hitTest = deps.hitTest
    local WORKBENCH_CX = deps.WORKBENCH_CX
    local WORKBENCH_CY = deps.WORKBENCH_CY
    local WORKBENCH_SIZE = deps.WORKBENCH_SIZE

    local TownPageChrome = require("ui.town.TownPageChrome")
    local EquipmentDetail = require("ui.character.equip.EquipmentDetail")

    --- 拖拽开始
    local function handleDragBegin(dx, dy)
        if not state.open or state.closing then return true end
        -- 一键强化确认弹窗滑块
        if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
            BlacksmithEnhance.handleDialogDragBegin(dx, dy)
            return true
        end
        return true  -- 铁匠铺打开时消费所有拖拽
    end

    --- 拖拽移动
    ---@param dx number 设计空间 X
    ---@param dy number 设计空间 Y
    ---@return boolean 是否消费事件
    local function handleDragMove(dx, dy)
        if not state.open or state.closing then return true end
        if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
            BlacksmithEnhance.handleDialogDragMove(dx, dy)
            return true
        end
        return true
    end

    --- 拖拽结束
    ---@param dx number 设计空间 X
    ---@param dy number 设计空间 Y
    ---@return boolean 是否消费事件
    local function handleDragEnd(dx, dy)
        if not state.open then return false end
        if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
            BlacksmithEnhance.handleDialogDragEnd()
            return true
        end
        return true
    end

    --- 鼠标滚轮滚动
    ---@param wheel number 滚轮值
    ---@param dx number|nil
    ---@param dy number|nil
    local function handleScroll(wheel, dx, dy)
        if not state.open or state.closing then return end
        -- 工作台/强化/洗练面板无滚动列表；滚轮事件直接消费
    end

    --- 处理输入
    ---@param dx number 设计空间 X
    ---@param dy number 设计空间 Y
    ---@return boolean 是否消费事件
    local function handleInput(dx, dy)
        if not state.open then return false end
        if state.closing then
            -- 安全保护：关闭动画超时强制关闭
            local closingElapsed = time.elapsedTime - state.closeTime
            if closingElapsed > 1.0 then
                print("[BlacksmithPage] handleInput: 关闭动画超时(" .. string.format("%.2f", closingElapsed) .. "s)，强制关闭")
                forceClose()
                return false
            end
            return true
        end

        -- 装备详情面板交互（点击工作台槽打开，优先级最高）
        if EquipmentDetail.isOpen() then
            return EquipmentDetail.handleInput(dx, dy)
        end

        -- 一键强化确认弹窗（强化 tab，优先级最高）
        if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
            return BlacksmithEnhance.handleDialogInput(dx, dy)
        end

        -- [锻炉双页 0929] 页内返回键已移除：锻炉右侧中缝返回条（seamBackList）统一接管关闭

        -- [锻炉双页 0929] 工作台槽点击
        if hitTest(dx, dy, WORKBENCH_CX, WORKBENCH_CY, WORKBENCH_SIZE, WORKBENCH_SIZE) then
            if state.selectedEquip and state.selectedSeq then
                -- 已选装备：打开装备详情（compactCorner 小窗，owner="smith"）
                EquipmentDetail.open(state.selectedSeq, nil, nil, true, "smith",
                    WORKBENCH_CX - WORKBENCH_SIZE * 0.5, WORKBENCH_CY)
                if EquipmentDetail.pin then EquipmentDetail.pin() end
                print("[BlacksmithPage] 工作台点击：查看装备详情 seq=" .. tostring(state.selectedSeq))
            else
                require("core.UiToast").show("从左侧仓库拖拽装备到工作台")
                print("[BlacksmithPage] 工作台为空，提示拖入装备")
            end
            return true
        end

        -- Tab 切换检测
        do
            local i = TownPageChrome.hitTab(dx, dy, TAB_ITEMS, SLIDER_W, SLIDER_H)
            if i then
                local tabKeys = { "qianghua", "xilian" }
                local newTab = tabKeys[i]
                if state.tab ~= newTab then
                    state.tabFrom = state.tab
                    state.tabSwitchTime = time.elapsedTime
                    state.tab = newTab
                    require("systems.GameSFX").playUIMove(2)
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
