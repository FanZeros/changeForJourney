-- ============================================================================
-- BlacksmithDraw - BlacksmithPage.drawPageImpl 抽出（玩法不变）
-- ============================================================================

local DarkIcon = require("core.DarkIcon")
local DrawUtil = require("core.DrawUtil")
local GameState = require("core.GameState")
local TownPageChrome = require("ui.TownPageChrome")
local CharacterPanel = require("ui.CharacterPanel")
local ClientDispatcher = require("network.ClientDispatcher")
local PlayerStore = require("client.data.PlayerStore")
local EquipmentBag = require("ui.EquipmentBag")
local EquipmentDetail = require("ui.EquipmentDetail")
local SpineResultEffect = require("ui.SpineResultEffect")

local M = {}

function M.bind(deps)
    local ANIM_DURATION = deps.ANIM_DURATION
    local BG_CX = deps.BG_CX
    local BG_CY = deps.BG_CY
    local BG_H = deps.BG_H
    local BG_W = deps.BG_W
    local BlacksmithDecompose = deps.BlacksmithDecompose
    local BlacksmithEnhance = deps.BlacksmithEnhance
    local BlacksmithPage = deps.BlacksmithPage
    local CLOSE_ANIM_DURATION = deps.CLOSE_ANIM_DURATION
    local DESIGN_H = deps.DESIGN_H
    local DESIGN_W = deps.DESIGN_W
    local DarkIcon = deps.DarkIcon
    local DrawUtil = deps.DrawUtil
    local EQUIP_SLOT_ORDER = deps.EQUIP_SLOT_ORDER
    local EquipmentBag = deps.EquipmentBag
    local EquipmentDetail = deps.EquipmentDetail
    local LOWER_BG_CX = deps.LOWER_BG_CX
    local LOWER_BG_CY = deps.LOWER_BG_CY
    local LOWER_BG_H = deps.LOWER_BG_H
    local LOWER_BG_W = deps.LOWER_BG_W
    local LOWER_SLIDE_DIST = deps.LOWER_SLIDE_DIST
    local NAME_FONT_SIZE = deps.NAME_FONT_SIZE
    local NAME_TEXT_CX = deps.NAME_TEXT_CX
    local NAME_TEXT_CY = deps.NAME_TEXT_CY
    local SLIDER_H = deps.SLIDER_H
    local SLIDER_W = deps.SLIDER_W
    local SpineResultEffect = deps.SpineResultEffect
    local TAB_ACTIVE_B = deps.TAB_ACTIVE_B
    local TAB_ACTIVE_G = deps.TAB_ACTIVE_G
    local TAB_ACTIVE_R = deps.TAB_ACTIVE_R
    local TAB_ANIM_DURATION = deps.TAB_ANIM_DURATION
    local TAB_BG_CX = deps.TAB_BG_CX
    local TAB_BG_CY = deps.TAB_BG_CY
    local TAB_BG_H = deps.TAB_BG_H
    local TAB_BG_W = deps.TAB_BG_W
    local TAB_FONT_SIZE = deps.TAB_FONT_SIZE
    local TAB_INACTIVE_B = deps.TAB_INACTIVE_B
    local TAB_INACTIVE_G = deps.TAB_INACTIVE_G
    local TAB_INACTIVE_R = deps.TAB_INACTIVE_R
    local TAB_ITEMS = deps.TAB_ITEMS
    local TAB_MAP = deps.TAB_MAP
    local TAB_TEXT_Y = deps.TAB_TEXT_Y
    local TownPageChrome = deps.TownPageChrome
    local UPPER_SLIDE_DIST = deps.UPPER_SLIDE_DIST
    local decomposeRedDot = deps.decomposeRedDot
    local drawEquipSlots = deps.drawEquipSlots
    local drawImageCentered = deps.drawImageCentered
    local drawTabContent = deps.drawTabContent
    local drawUpperSlotContent = deps.drawUpperSlotContent
    local easeInCubic = deps.easeInCubic
    local easeInOutCubic = deps.easeInOutCubic
    local easeOutCubic = deps.easeOutCubic
    local getEquipSlotCX = deps.getEquipSlotCX
    local getEquipSlotCY = deps.getEquipSlotCY
    local imgBg = deps.imgBg
    local imgIconUp = deps.imgIconUp
    local imgLowerBg = deps.imgLowerBg
    local imgNameBg = deps.imgNameBg
    local imgTabBg = deps.imgTabBg
    local state = deps.state

    local function drawPageImpl(vg)
    if not state.open then return end

    -- === 弹出/关闭动画 ===
    local rawT, progress, lowerProgress

    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        rawT = math.min(1.0, elapsed / CLOSE_ANIM_DURATION)
        progress      = 1 - easeInCubic(rawT)
        lowerProgress = progress
        if rawT >= 1.0 then
            print("[BlacksmithPage] draw: 关闭动画完成，state.open → false")
            state.open = false
            state.closing = false
            local cb = deps.getOnCloseCallback and deps.getOnCloseCallback()
            if deps.setOnCloseCallback then deps.setOnCloseCallback(nil) end
            if cb then cb() end
            return
        end
    else
        local elapsed = time.elapsedTime - state.openTime
        rawT = math.min(1.0, elapsed / ANIM_DURATION)
        progress      = easeOutCubic(rawT)
        lowerProgress = easeOutCubic(rawT)
        local openCb = deps.getOnOpenCallback and deps.getOnOpenCallback()
        if rawT >= 1.0 and openCb then
            if deps.setOnOpenCallback then deps.setOnOpenCallback(nil) end
            openCb()
        end
    end

    local upperOX = -UPPER_SLIDE_DIST * (1 - progress)  -- [横向] 从左侧滑入/滑出
    local lowerOX = -LOWER_SLIDE_DIST * (1 - lowerProgress)  -- [横向] 与整页同向:从左侧滑入/滑出
    local overlayAlpha = math.floor(180 * progress)

    -- === 全屏遮罩 ===
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)

    -- ================== 上半部分（从上方滑入） ==================
    nvgSave(vg)
    nvgTranslate(vg, upperOX, 0)

    -- 1. 铁匠铺背景图（裁剪到设计宽度）
    nvgSave(vg)
    nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
    drawImageCentered(vg, imgBg, BG_CX, BG_CY, BG_W, BG_H, 1.0)
    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 2-3. 铁匠铺名称牌
    TownPageChrome.drawNamePlate(vg, imgNameBg, "铁匠铺", { textCX = NAME_TEXT_CX, textCY = NAME_TEXT_CY, font = NAME_FONT_SIZE })

    -- 4-6. 上半部分槽位区域 + 下半部分面板内容（带 Tab 切换滑动动画）
    local tabIdx = TAB_MAP[state.tab] or 3
    local fromIdx = TAB_MAP[state.tabFrom] or 3
    local tabElapsed = time.elapsedTime - state.tabSwitchTime
    local tabT = math.min(1.0, tabElapsed / TAB_ANIM_DURATION)
    local tabEased = easeInOutCubic(tabT)

    -- 滑动方向：新 tab 在旧 tab 左侧 -> 内容从左滑入（direction = -1）
    local direction = 0
    if tabIdx ~= fromIdx then
        direction = (tabIdx < fromIdx) and -1 or 1
    end
    -- 新面板偏移：从 direction*DESIGN_W 滑到 0
    local newOX = DESIGN_W * direction * (1 - tabEased)
    -- 旧面板偏移：从 0 滑到 -direction*DESIGN_W
    local oldOX = -DESIGN_W * direction * tabEased
    local isAnimating = (tabT < 1.0 and tabIdx ~= fromIdx)

    -- 上半部分：三种 tab 内容各不相同，任意两种之间切换都需要滑动
    local upperNeedSlide = isAnimating and (state.tab ~= state.tabFrom)

    if upperNeedSlide then
        -- 涉及分解切换：新旧槽位都带水平滑动 + 屏幕范围剪裁
        nvgSave(vg)
        nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgSave(vg)
        nvgTranslate(vg, oldOX, 0)
        drawUpperSlotContent(vg, state.tabFrom)
        nvgRestore(vg)
        nvgSave(vg)
        nvgTranslate(vg, newOX, 0)
        drawUpperSlotContent(vg, state.tab)
        nvgRestore(vg)
        nvgResetScissor(vg)
        nvgRestore(vg)
    else
        -- 强化<->洗练：上半部分不动，直接绘制当前 tab
        drawUpperSlotContent(vg, state.tab)
    end

    nvgRestore(vg)  -- 结束上半部分偏移

    -- ================== 下半部分（从下方滑入） ==================
    nvgSave(vg)
    nvgTranslate(vg, lowerOX, 0)

    -- 7. 下方背景板
    drawImageCentered(vg, imgLowerBg, LOWER_BG_CX, LOWER_BG_CY, LOWER_BG_W, LOWER_BG_H, 1.0)

    -- 7.5 装备槽位（仅强化 tab，带滑动动画，绘制在 lower BG 之上避免被覆盖）
    do
        local curIsQH = (state.tab == "qianghua")
        local oldIsQH = (state.tabFrom == "qianghua")
        if isAnimating and (curIsQH or oldIsQH) then
            -- 动画中：旧/新面板分别绘制装备槽位并带滑动
            nvgSave(vg)
            nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
            if oldIsQH then
                nvgSave(vg)
                nvgTranslate(vg, oldOX, 0)
                drawEquipSlots(vg)
                nvgRestore(vg)
            end
            if curIsQH then
                nvgSave(vg)
                nvgTranslate(vg, newOX, 0)
                drawEquipSlots(vg)
                -- Spine 强化结果特效
                if SpineResultEffect.isPlaying() then
                    local eqIdx = 1
                    for i, k in ipairs(EQUIP_SLOT_ORDER) do
                        if k == state.selectedEquipSlot then eqIdx = i; break end
                    end
                    SpineResultEffect.draw(vg, getEquipSlotCX(eqIdx), getEquipSlotCY(eqIdx))
                end
                nvgRestore(vg)
            end
            nvgResetScissor(vg)
            nvgRestore(vg)
        elseif curIsQH then
            -- 非动画：直接绘制
            drawEquipSlots(vg)
            if SpineResultEffect.isPlaying() then
                local eqIdx = 1
                for i, k in ipairs(EQUIP_SLOT_ORDER) do
                    if k == state.selectedEquipSlot then eqIdx = i; break end
                end
                SpineResultEffect.draw(vg, getEquipSlotCX(eqIdx), getEquipSlotCY(eqIdx))
            end
        end
    end

    -- 下方内容剪裁区域（背景板范围内，Tab 栏以上）
    local clipTop = LOWER_BG_CY - LOWER_BG_H * 0.5
    local clipBottom = TAB_BG_CY - TAB_BG_H * 0.5
    local clipH = clipBottom - clipTop

    -- === 绘制旧面板内容（滑出，仅动画中绘制） ===
    if isAnimating then
        nvgSave(vg)
        nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)
        nvgTranslate(vg, oldOX, 0)
        drawTabContent(vg, state.tabFrom)
        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    -- === 绘制新面板内容（当前 tab） ===
    nvgSave(vg)
    nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)
    if isAnimating then nvgTranslate(vg, newOX, 0) end
    drawTabContent(vg, state.tab)
    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 8. 返回按钮（三行模式由中缝层绘制）
    TownPageChrome.drawBack(vg)

    -- 9-11. 底栏 Tab
    local tabKeys = { "qianghua", "xilian", "fenjie" }
    TownPageChrome.drawTabBar(vg, imgTabBg, {
        items = TAB_ITEMS,
        tabIdx = tabIdx, fromIdx = fromIdx, eased = tabEased,
        sliderW = SLIDER_W, sliderH = SLIDER_H,
        bgCX = TAB_BG_CX, bgCY = TAB_BG_CY, bgW = TAB_BG_W, bgH = TAB_BG_H,
        font = TAB_FONT_SIZE, textY = TAB_TEXT_Y,
        active = { r = TAB_ACTIVE_R, g = TAB_ACTIVE_G, b = TAB_ACTIVE_B },
        inactive = { r = TAB_INACTIVE_R, g = TAB_INACTIVE_G, b = TAB_INACTIVE_B },
        activePred = function(i, _) return state.tab == tabKeys[i] end,
        drawBadge = function(vg, i, item, textX, textY)
            if i == 3 and decomposeRedDot then
                nvgFontFace(vg, "sans"); nvgFontSize(vg, TAB_FONT_SIZE)
                local upSize = 30
                local textHalfW = nvgTextBounds(vg, 0, 0, item.name) * 0.5
                DarkIcon.draw(vg, "reddot", textX + textHalfW + 10, textY - 18, upSize, 1.0)
            elseif i == 1 and imgIconUp >= 0 and BlacksmithPage.canEnhanceAny() then
                nvgFontFace(vg, "sans"); nvgFontSize(vg, TAB_FONT_SIZE)
                local upSize = 30
                local textHalfW = nvgTextBounds(vg, 0, 0, item.name) * 0.5
                DrawUtil.drawImageCentered(vg, imgIconUp, textX + textHalfW + 10, textY - 18, upSize, upSize, 1.0)
            end
        end,
    })

    nvgRestore(vg)  -- 结束下半部分偏移

    -- 自动分解弹窗（最顶层，不受滑动偏移影响）
    if state.tab == "fenjie" then
        BlacksmithDecompose.drawAutoDecomposePopup(vg)
    end

    -- 装备详情面板（最顶层，长按触发）
    if state.tab == "fenjie" then
        EquipmentDetail.draw(vg)
    end

    -- 一键强化确认弹窗（强化 tab，最顶层）
    if state.tab == "qianghua" then
        BlacksmithEnhance.drawConfirmDialog(vg)
    end

    -- 装备背包覆盖层（最顶层）
    EquipmentBag.draw(vg)
    end
    return { drawPageImpl = drawPageImpl }
end

return M
