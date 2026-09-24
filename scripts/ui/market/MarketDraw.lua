-- ============================================================================
-- MarketDraw - MarketPage.drawPageImpl 抽出（玩法不变）
-- ============================================================================

local DarkIcon = require("core.DarkIcon")
local GameState = require("core.GameState")
local TownPageChrome = require("ui.town.TownPageChrome")
local I18n = require("core.I18n")

local M = {}

function M.bind(deps)
    local ANIM_DUR = deps.ANIM_DUR
    local BF = deps.BF
    local CLOSE_DUR = deps.CLOSE_DUR
    local DESIGN_H = deps.DESIGN_H
    local DESIGN_W = deps.DESIGN_W
    local DarkIcon = deps.DarkIcon
    local GameState = deps.GameState
    local LOWER_DIST = deps.LOWER_DIST
    local P1 = deps.P1
    local TAB = deps.TAB
    local TAB_DRAW = deps.TAB_DRAW
    local TownPageChrome = deps.TownPageChrome
    local UPPER_DIST = deps.UPPER_DIST
    local drawImageCentered = deps.drawImageCentered
    local drawKeyConfirmDialog = deps.drawKeyConfirmDialog
    local drawPurchaseDialog = deps.drawPurchaseDialog
    local drawTextStroke = deps.drawTextStroke
    local easeInCubic = deps.easeInCubic
    local easeInOutCubic = deps.easeInOutCubic
    local easeOutCubic = deps.easeOutCubic
    local formatNumber = deps.formatNumber
    local img = deps.img
    local state = deps.state

    local function drawPageImpl(vg)
    if not state.open then return end

    local rawT, progress, lowerProgress

    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        rawT = math.min(1.0, elapsed / CLOSE_DUR)
        progress = 1 - easeInCubic(rawT)
        lowerProgress = progress
        if rawT >= 1.0 then
            state.open = false; state.closing = false; return
        end
    else
        local elapsed = time.elapsedTime - state.openTime
        rawT = math.min(1.0, elapsed / ANIM_DUR)
        progress = easeOutCubic(rawT)
        lowerProgress = progress
    end

    local seamMode = H_SEAM_BACK == true
    local upperOX = seamMode and 0 or (-UPPER_DIST * (1 - progress))
    local lowerOX = seamMode and 0 or (-LOWER_DIST * (1 - lowerProgress))
    local overlayAlpha = seamMode and 0 or math.floor(180 * progress)

    -- Tab 切换进度
    local tabT = 1.0
    if state.tabSwitchTime > 0 then
        tabT = math.min(1.0, (time.elapsedTime - state.tabSwitchTime) / TAB.ANIM_DUR)
    end
    local tabEased = easeInOutCubic(tabT)
    local tabIdx = TAB.MAP[state.tab] or 3
    local fromIdx = TAB.MAP[state.tabFrom] or tabIdx
    local isAnimating = (tabT < 1.0 and tabIdx ~= fromIdx)

    -- 全屏遮罩
    nvgBeginPath(vg); nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha)); nvgFill(vg)

    -- ========== 上半部分（从上方滑入） ==========
    nvgSave(vg)
    nvgTranslate(vg, upperOX, 0)

    -- 资源栏数据（切换动画时两侧都可能绘制，提前计算一次）
    local resGroups = {
        { bgCX = P1.R1_BG_CX, bgCY = P1.R1_BG_CY, iCX = P1.R1_ICON_CX, iCY = P1.R1_ICON_CY,
          iW = P1.R1_ICON_W, iH = P1.R1_ICON_H, tX = P1.R1_TX, tY = P1.R1_TY,
          icon = img.gold, val = formatNumber(GameState.getGold()) },
        { bgCX = P1.R2_BG_CX, bgCY = P1.R2_BG_CY, iCX = P1.R2_ICON_CX, iCY = P1.R2_ICON_CY,
          iW = P1.R2_ICON_W, iH = P1.R2_ICON_H, tX = P1.R2_TX, tY = P1.R2_TY,
          icon = img.gem, val = formatNumber(GameState.getGems()) },
    }

    -- 绘制指定 tab 的上半部分可变内容（背景图 + 资源栏/刷新时间）
    local function drawUpperVariant(tabKey)
        -- 背景图
        -- 使用 nvgIntersectScissor 而非 nvgScissor，以保留外层动画裁剪区域，防止内容溢出屏幕
        nvgSave(vg); nvgIntersectScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        drawImageCentered(vg, img.bg, P1.BG_CX, P1.BG_CY, P1.BG_W, P1.BG_H, 1.0)
        nvgRestore(vg)
        -- 资源栏
        for _, r in ipairs(resGroups) do
            nvgBeginPath(vg)
            nvgRoundedRect(vg, r.bgCX - P1.RES_BG_W * 0.5, r.bgCY - P1.RES_BG_H * 0.5,
                P1.RES_BG_W, P1.RES_BG_H, P1.RES_BG_R)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, P1.RES_BG_A)); nvgFill(vg)
            drawImageCentered(vg, r.icon, r.iCX, r.iCY, r.iW, r.iH, 1.0)
            drawTextStroke(vg, r.tX, r.tY, r.val,
                P1.RES_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, P1.RES_SW,
                { strokeColor = { P1.RES_SR, P1.RES_SG, P1.RES_SB } })
        end
    end

    -- tab 切换时上半部分也参与水平平移（与下方内容区同方向、同进度条
    if isAnimating then
        local dir = (tabIdx > fromIdx) and 1 or -1
        local newOX = DESIGN_W * dir * (1 - tabEased)
        local oldOX = -DESIGN_W * dir * tabEased
        nvgSave(vg); nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgSave(vg); nvgTranslate(vg, oldOX, 0); drawUpperVariant(state.tabFrom); nvgRestore(vg)
        nvgSave(vg); nvgTranslate(vg, newOX, 0); drawUpperVariant(state.tab);     nvgRestore(vg)
        nvgResetScissor(vg); nvgRestore(vg)
    else
        drawUpperVariant(state.tab)
    end

    -- 名称牌（固定，不参与水平滑动）
    TownPageChrome.drawNamePlate(vg, img.nameBg, I18n.t("market"), {
        textCX = P1.NAME_TEXT_CX, textCY = P1.NAME_TEXT_CY, font = P1.NAME_FONT,
    })

    nvgRestore(vg)  -- 上半部分 end

    -- ========== 下半部分（从下方滑入） ==========
    nvgSave(vg)
    nvgTranslate(vg, lowerOX, 0)

    -- 下方背景框（封装为函数以支持水平滑动动画）
    local function drawLowerBg(tabKey)
        DarkIcon.drawNine(vg, "plain", P1.LOWER_CX - P1.LOWER_W * 0.5, P1.LOWER_CY - P1.LOWER_H * 0.5, P1.LOWER_W, P1.LOWER_H)
    end

    if isAnimating then
        local dir = (tabIdx > fromIdx) and 1 or -1
        local newOX = DESIGN_W * dir * (1 - tabEased)
        local oldOX = -DESIGN_W * dir * tabEased
        nvgSave(vg); nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgSave(vg); nvgTranslate(vg, oldOX, 0); drawLowerBg(state.tabFrom); nvgRestore(vg)
        nvgSave(vg); nvgTranslate(vg, newOX, 0); drawLowerBg(state.tab);     nvgRestore(vg)
        nvgResetScissor(vg); nvgRestore(vg)
    else
        drawLowerBg(state.tab)
    end

    -- ========== Tab 内容 ==========
    local contentClipTop = 430
    local contentClipBot = math.min(DESIGN_H, 2300)  -- [横向] 下半无 Y 偏移,裁剪固定
    -- isAnimating 已在函数顶部计算，此处直接复用

    if isAnimating then
        local dir = (tabIdx > fromIdx) and 1 or -1
        local newOX = DESIGN_W * dir * (1 - tabEased)
        local oldOX = -DESIGN_W * dir * tabEased

        nvgSave(vg); nvgScissor(vg, 0, contentClipTop, DESIGN_W, contentClipBot - contentClipTop)

        nvgSave(vg); nvgTranslate(vg, oldOX, 0)
        local oldFn = TAB_DRAW[state.tabFrom]
        if oldFn then oldFn(vg) end
        nvgRestore(vg)

        nvgSave(vg); nvgTranslate(vg, newOX, 0)
        local newFn = TAB_DRAW[state.tab]
        if newFn then newFn(vg) end
        nvgRestore(vg)

        nvgResetScissor(vg); nvgRestore(vg)
    else
        nvgSave(vg); nvgScissor(vg, 0, contentClipTop, DESIGN_W, contentClipBot - contentClipTop)
        local fn = TAB_DRAW[state.tab]
        if fn then fn(vg) end
        nvgResetScissor(vg); nvgRestore(vg)
    end

    -- ========== 返回按钮 & Tab 栏==========
    ---@diagnostic disable-next-line: undefined-global
    if not H_SEAM_BACK then
        local _sb = BF.begin(vg, "market_back", TAB.BACK_CX, TAB.BACK_CY, TAB.BACK_W, TAB.BACK_H)
        TownPageChrome.drawBack(vg)
        BF.finish(vg, _sb)
    end
    TownPageChrome.drawTabBar(vg, img.tabBg, {
        items = TAB.ITEMS,
        tabIdx = tabIdx, fromIdx = fromIdx, eased = tabEased,
        sliderW = TAB.SLIDER_W, sliderH = TAB.SLIDER_H,
        bgCX = TAB.BG_CX, bgCY = TAB.BG_CY, bgW = TAB.BG_W, bgH = TAB.BG_H,
        font = TAB.FONT, textY = TAB.TEXT_Y,
        active = { r = TAB.ACT_R, g = TAB.ACT_G, b = TAB.ACT_B },
        inactive = { r = TAB.INA_R, g = TAB.INA_G, b = TAB.INA_B },
        activePred = function(i, _) return state.tab == TAB.KEYS[i] end,
    })

    -- 弹窗（在裁剪区域外绘制，遮罩覆盖全屏）
    drawPurchaseDialog(vg)
    drawKeyConfirmDialog(vg)

    nvgRestore(vg)  -- 下半部分 end

    -- 浮动提示（在所有变换之外渲染，确保坐标正确）
    if state.floatText then
        local FLOAT_DURATION = 1.5
        local FLOAT_DIST     = 100
        local elapsed = time.elapsedTime - state.floatTextTime
        if elapsed >= FLOAT_DURATION then
            state.floatText = nil
        else
            local t       = elapsed / FLOAT_DURATION
            local offsetY = -FLOAT_DIST * t
            drawTextStroke(vg, state.floatTextX, state.floatTextY + offsetY,
                state.floatText,
                40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 80, 80, 6,
                { alpha = 1.0 - t })
        end
    end
    end
    return { drawPageImpl = drawPageImpl }
end

return M
