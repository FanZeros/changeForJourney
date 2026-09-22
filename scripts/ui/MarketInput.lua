-- ============================================================================
-- MarketInput - MarketPage 点击/拖拽/滚轮（玩法不变）
-- ============================================================================

local GameState = require("core.GameState")
local TownPageChrome = require("ui.TownPageChrome")
local Protocol = require("shared.Protocol")

local M = {}

function M.bind(deps)
    local BF = deps.BF
    local CARD_STEP_X = deps.CARD_STEP_X
    local CARD_STEP_Y = deps.CARD_STEP_Y
    local COL = deps.COL
    local DLG = deps.DLG
    local GRID_LEFT = deps.GRID_LEFT
    local GameState = deps.GameState
    local KEY_CF = deps.KEY_CF
    local MarketPage = deps.MarketPage
    local Protocol = deps.Protocol
    local SCROLL_BOT = deps.SCROLL_BOT
    local SCROLL_TOP = deps.SCROLL_TOP
    local SHOP_ITEMS = deps.SHOP_ITEMS
    local SL = deps.SL
    local TAB = deps.TAB
    local TownPageChrome = deps.TownPageChrome
    local checkKeyAndDraw = deps.checkKeyAndDraw
    local closeKeyConfirm = deps.closeKeyConfirm
    local getActualPrice = deps.getActualPrice
    local getPurchased = deps.getPurchased
    local hitTest = deps.hitTest
    local isArtifactChestUnlocked = deps.isArtifactChestUnlocked
    local isSoldOut = deps.isSoldOut
    local sendAction_ = deps.sendAction_
    local sendArtifactDraw = deps.sendArtifactDraw
    local state = deps.state

local function handleInput(dx, dy)
    if not state.open or state.closing then return false end

    -- 黄金钥匙快速购买确认框
    if state.keyConfirmVisible then
        if state.keyConfirmClosing then return true end
        if time.elapsedTime - state.keyConfirmAnimTime < 0.05 then return true end

        if hitTest(dx, dy, KEY_CF.BUY_CX, KEY_CF.BUY_CY, KEY_CF.BUY_W, KEY_CF.BUY_H) then
            BF.trigger("market_key_confirm")
            if GameState.getGems() < state.keyConfirmDiamondCost then
                state.floatText = "钻石不足"
                state.floatTextX = KEY_CF.BUY_CX
                state.floatTextY = KEY_CF.BUY_CY - 80
                state.floatTextTime = time.elapsedTime
                return true
            end
            local drawCount = state.keyConfirmCount
            closeKeyConfirm()
            sendArtifactDraw(drawCount)
            state.floatText = "正在开启宝箱"
            state.floatTextX = drawCount == 10 and COL.BTN_TEN_X or COL.BTN_ONE_X
            state.floatTextY = COL.BTN_Y - 120
            state.floatTextTime = time.elapsedTime
            return true
        end
        if not hitTest(dx, dy, KEY_CF.CX, KEY_CF.CY, KEY_CF.W, KEY_CF.H) then
            closeKeyConfirm()
        end
        return true
    end

    -- 弹窗优先
    if state.dialogOpen then
        if state.popupClosing then return true end

        -- 减按钮
        if hitTest(dx, dy, DLG.MINUS_CX, DLG.MINUS_CY, DLG.MINUS_W, DLG.MINUS_H) then
            BF.trigger("market_dlg_minus")
            if state.buyQuantity > 1 then
                state.buyQuantity = state.buyQuantity - 1
            end
            return true
        end

        -- 加按钮
        if hitTest(dx, dy, DLG.PLUS_CX, DLG.PLUS_CY, DLG.PLUS_W, DLG.PLUS_H) then
            BF.trigger("market_dlg_plus")
            if state.buyQuantity < state.buyMaxQuantity then
                state.buyQuantity = state.buyQuantity + 1
            end
            return true
        end

        -- 滑条点击（整个滑条区域 + 滑块溢出范围）
        local sliderHitH = math.max(DLG.SLIDER_H, DLG.KNOB_SIZE) + 20
        if hitTest(dx, dy, DLG.SLIDER_CX, DLG.SLIDER_CY, DLG.SLIDER_W + DLG.KNOB_SIZE, sliderHitH) then
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty = math.floor(frac * (state.buyMaxQuantity - 1) + 0.5) + 1
            state.buyQuantity = math.max(1, math.min(state.buyMaxQuantity, qty))
            state.sliderDragging = true
            return true
        end

        -- 购买按钮
        if hitTest(dx, dy, DLG.BUY_CX, DLG.BUY_CY, DLG.BUY_W, DLG.BUY_H) then
            BF.trigger("market_dlg_buy")
            local idx = state.dialogItemIdx
            local item = SHOP_ITEMS[idx]
            if item and sendAction_ then
                local actualCost = getActualPrice(item) * state.buyQuantity
                local currName = "金币"
                local balance = 0
                if item.currency == "diamond" then
                    currName = "钻石"
                    balance = GameState.getGems()
                else
                    balance = GameState.getGold()
                end

                if balance < actualCost then
                    print("[MarketPage] " .. currName .. "不足: 需要" .. actualCost .. " 当前" .. balance)
                    state.floatText = currName .. "不足"
                    state.floatTextX = DLG.BUY_CX
                    state.floatTextY = DLG.BUY_CY
                    state.floatTextTime = time.elapsedTime
                    return true
                else
                    print("[MarketPage] 发送购买请求 itemId=" .. item.id .. " qty=" .. state.buyQuantity .. " (" .. item.name .. ")")
                    sendAction_(Protocol.ACTION_TYPES.MARKET_BUY, { itemId = item.id, quantity = state.buyQuantity })
                end
            end
            state.popupClosing = true
            state.popupCloseTime = time.elapsedTime
            return true
        end

        -- 同帧保护
        if time.elapsedTime - state.popupAnimTime < 0.05 then return true end

        -- 点击弹窗外部关闭
        if not hitTest(dx, dy, DLG.BG_CX, DLG.BG_CY, DLG.BG_W, DLG.BG_H) then
            state.popupClosing = true
            state.popupCloseTime = time.elapsedTime
        end
        return true
    end

    -- 返回按钮（三行模式由中缝层接管）
    if TownPageChrome.hitBack(dx, dy) then
        BF.trigger("market_back")
        MarketPage.close(); return true
    end

    -- Tab 切换
    do
        local i = TownPageChrome.hitTab(dx, dy, TAB.ITEMS, TAB.SLIDER_W, TAB.SLIDER_H)
        if i then
            local newTab = TAB.KEYS[i]
            if state.tab ~= newTab then
                state.tabFrom = state.tab
                state.tabSwitchTime = time.elapsedTime
                state.tab = newTab
                require("systems.GameSFX").playUIMove(2)
                state.scrollY = 0
                print("[MarketPage] 切换到 " .. TAB.ITEMS[i].name)
            end
            return true
        end
    end

    -- 典藏 Tab：神器宝箱抽取按钮
    if state.tab == "collection" then
        if not isArtifactChestUnlocked() then
            return true
        end
        local drawCount, btnId, btnCX = nil, nil, nil
        if hitTest(dx, dy, COL.BTN_ONE_X, COL.BTN_Y, COL.BTN_W, COL.BTN_H) then
            drawCount, btnId, btnCX = 1, "collection_draw_1", COL.BTN_ONE_X
        elseif hitTest(dx, dy, COL.BTN_TEN_X, COL.BTN_Y, COL.BTN_W, COL.BTN_H) then
            drawCount, btnId, btnCX = 10, "collection_draw_10", COL.BTN_TEN_X
        end
        if drawCount then
            BF.trigger(btnId)
            checkKeyAndDraw(drawCount)
            return true
        end
    end

    -- 道具 Tab：商品购买按钮
    if state.tab == "items" then
        for idx, item in ipairs(SHOP_ITEMS) do
            local col = ((idx - 1) % SL.CARD_COLS)
            local row = math.floor((idx - 1) / SL.CARD_COLS)
            local cx = GRID_LEFT + col * CARD_STEP_X
            local cy = SL.GRID_TOP_CY + row * CARD_STEP_Y - state.scrollY

            local btnCY = cy + SL.BTN_OY
            if hitTest(dx, dy, cx, btnCY, SL.BTN_W, SL.BTN_H) then
                if isSoldOut(item) then
                    print("[MarketPage] 商品已售罄 " .. item.name)
                    return true
                end
                BF.trigger("market_buy_" .. idx)
                state.dialogOpen = true
                state.dialogItemIdx = idx
                state.popupAnimTime = time.elapsedTime
                state.popupClosing = false
                state.sliderDragging = false
                -- 计算最大可购买数量
                state.buyQuantity = 1
                if item.limitCount == -1 then
                    state.buyMaxQuantity = 99
                else
                    local bought = getPurchased(item.id)
                    state.buyMaxQuantity = math.max(1, item.limitCount - bought)
                end
                print("[MarketPage] 打开购买确认: " .. item.name .. " maxQty=" .. state.buyMaxQuantity)
                return true
            end
        end
    end

    return true  -- 消费事件防穿透
end

local function handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    if state.dialogOpen then
        if state.popupClosing then return true end
        -- 滑条拖拽开始
        local sliderHitH = math.max(DLG.SLIDER_H, DLG.KNOB_SIZE) + 20
        if hitTest(dx, dy, DLG.SLIDER_CX, DLG.SLIDER_CY, DLG.SLIDER_W + DLG.KNOB_SIZE, sliderHitH) then
            state.sliderDragging = true
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty = math.floor(frac * (state.buyMaxQuantity - 1) + 0.5) + 1
            state.buyQuantity = math.max(1, math.min(state.buyMaxQuantity, qty))
        end
        return true
    end
    if state.tab == "items" and dy >= SCROLL_TOP and dy <= SCROLL_BOT then
        state.dragging = true
        state.lastDragY = dy
        return true
    end
    return true
end

local function handleDragMove(dx, dy)
    if not state.open or state.closing then return false end
    if state.dialogOpen then
        if state.sliderDragging and not state.popupClosing then
            local sliderL = DLG.SLIDER_CX - DLG.SLIDER_W * 0.5
            local frac = math.max(0, math.min(1, (dx - sliderL) / DLG.SLIDER_W))
            local qty = math.floor(frac * (state.buyMaxQuantity - 1) + 0.5) + 1
            state.buyQuantity = math.max(1, math.min(state.buyMaxQuantity, qty))
        end
        return true
    end
    if state.dragging then
        state.scrollY = state.scrollY + (state.lastDragY - dy)
        state.lastDragY = dy
        return true
    end
    return true
end

local function handleDragEnd(dx, dy)
    if not state.open or state.closing then return false end
    state.sliderDragging = false
    state.dragging = false
    return true
end

local function handleScroll(wheel)
    if not state.open or state.closing then return false end
    if state.dialogOpen or state.popupClosing or state.keyConfirmVisible then return true end
    if state.tab == "items" then
        state.scrollY = state.scrollY - wheel * 60
    end
    return true
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
