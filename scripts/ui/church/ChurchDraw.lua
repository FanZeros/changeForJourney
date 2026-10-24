-- ============================================================================
-- ChurchDraw - 神器 / 宝箱页面及公共浮层绘制
-- ============================================================================

local SpineCardEffect = require("ui.fx.SpineCardEffect")
local ArtifactPanel = require("ui.church.ChurchArtifactPanel")
local ArtifactDrawPanel = require("ui.church.ChurchArtifactDrawPanel")
local I18n = require("core.I18n")

local M = {}

function M.bind(deps)
    local ANIM = deps.ANIM
    local CHURCH = deps.CHURCH
    local DESIGN_H = deps.DESIGN_H
    local DESIGN_W = deps.DESIGN_W
    local TAB = deps.TAB
    local TAB_ITEMS = deps.TAB_ITEMS
    local TAB_KEYS = deps.TAB_KEYS
    local TAB_MAP = deps.TAB_MAP
    local TownPageChrome = deps.TownPageChrome
    local drawImageCentered = deps.drawImageCentered
    local drawTextStroke = deps.drawTextStroke
    local easeInCubic = deps.easeInCubic
    local easeInOutCubic = deps.easeInOutCubic
    local easeOutCubic = deps.easeOutCubic
    local img = deps.img
    local state = deps.state

    local function drawPageImpl(vg)
        if not state.open then return end

        -- 打开/关闭回调在动画完成时只派发一次。
        local rawT, progress, lowerProgress
        if state.closing then
            local elapsed = time.elapsedTime - state.closeTime
            rawT = math.min(1.0, elapsed / ANIM.CLOSE_DUR)
            progress = 1 - easeInCubic(rawT)
            lowerProgress = progress
            if rawT >= 1.0 then
                state.open = false
                state.closing = false
                local cb = deps.getOnCloseCallback and deps.getOnCloseCallback()
                if deps.setOnCloseCallback then deps.setOnCloseCallback(nil) end
                if cb then cb() end
                return
            end
        else
            local elapsed = time.elapsedTime - state.openTime
            rawT = math.min(1.0, elapsed / ANIM.OPEN_DUR)
            progress = easeOutCubic(rawT)
            lowerProgress = easeOutCubic(rawT)
            local openCb = deps.getOnOpenCallback and deps.getOnOpenCallback()
            if rawT >= 1.0 and openCb then
                if deps.setOnOpenCallback then deps.setOnOpenCallback(nil) end
                openCb()
            end
        end

        -- 整页平移由 ChurchPage.draw 与中缝条同步；保留非中缝模式兼容。
        local seamMode = H_SEAM_BACK == true
        local upperDist = state.closing and ANIM.UPPER_SLIDE_OUT or ANIM.UPPER_SLIDE_IN
        local upperOX = seamMode and 0 or (-upperDist * (1 - progress))
        local lowerOX = seamMode and 0 or (-ANIM.LOWER_SLIDE_DIST * (1 - lowerProgress))
        local overlayAlpha = seamMode and 0 or math.floor(180 * progress)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
        nvgFill(vg)

        local tabIdx = TAB_MAP[state.tab] or 1
        local fromIdx = TAB_MAP[state.tabFrom] or 1
        local tabElapsed = time.elapsedTime - state.tabSwitchTime
        local tabT = math.min(1.0, tabElapsed / TAB.ANIM_DUR)
        local tabEased = easeInOutCubic(tabT)
        -- 新页从左滑入、旧页向右滑出；两页背景覆盖区间首尾相接。
        local newOX_tab = -DESIGN_W * (1 - tabEased)
        local oldOX_tab = DESIGN_W * tabEased
        local isAnimating = (tabT < 1.0 and tabIdx ~= fromIdx)

        -- === Tab 全屏背景 ===
        nvgSave(vg)
        nvgTranslate(vg, lowerOX, 0)
        if isAnimating then
            local oVisL = math.max(0, oldOX_tab)
            local oVisR = math.min(DESIGN_W, oldOX_tab + DESIGN_W)
            if oVisR > oVisL then
                nvgSave(vg)
                nvgScissor(vg, oVisL, 0, oVisR - oVisL, DESIGN_H)
                nvgTranslate(vg, oldOX_tab, 0)
                if state.tabFrom == "shenqi" then ArtifactPanel.drawBg(vg)
                elseif state.tabFrom == "baoxiang" then ArtifactDrawPanel.drawBg(vg) end
                nvgRestore(vg)
            end
            local nVisL = math.max(0, newOX_tab)
            local nVisR = math.min(DESIGN_W, newOX_tab + DESIGN_W)
            if nVisR > nVisL then
                nvgSave(vg)
                nvgScissor(vg, nVisL, 0, nVisR - nVisL, DESIGN_H)
                nvgTranslate(vg, newOX_tab, 0)
                if state.tab == "shenqi" then ArtifactPanel.drawBg(vg)
                elseif state.tab == "baoxiang" then ArtifactDrawPanel.drawBg(vg) end
                nvgRestore(vg)
            end
        else
            if state.tab == "shenqi" then ArtifactPanel.drawBg(vg)
            elseif state.tab == "baoxiang" then ArtifactDrawPanel.drawBg(vg) end
        end
        nvgRestore(vg)

        -- === Tab 内容 ===
        nvgSave(vg)
        nvgTranslate(vg, lowerOX, 0)
        local function drawTabContent(tabKey)
            if tabKey == "shenqi" then ArtifactPanel.drawContent(vg)
            elseif tabKey == "baoxiang" then ArtifactDrawPanel.drawContent(vg) end
        end
        if isAnimating then
            local oVisL = math.max(0, oldOX_tab)
            local oVisR = math.min(DESIGN_W, oldOX_tab + DESIGN_W)
            if oVisR > oVisL then
                nvgSave(vg)
                nvgScissor(vg, oVisL, 0, oVisR - oVisL, DESIGN_H)
                nvgTranslate(vg, oldOX_tab, 0)
                drawTabContent(state.tabFrom)
                nvgRestore(vg)
            end
            local nVisL = math.max(0, newOX_tab)
            local nVisR = math.min(DESIGN_W, newOX_tab + DESIGN_W)
            if nVisR > nVisL then
                nvgSave(vg)
                nvgScissor(vg, nVisL, 0, nVisR - nVisL, DESIGN_H)
                nvgTranslate(vg, newOX_tab, 0)
                drawTabContent(state.tab)
                nvgRestore(vg)
            end
        else
            nvgSave(vg)
            nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
            drawTabContent(state.tab)
            nvgRestore(vg)
        end

        TownPageChrome.drawBack(vg)
        TownPageChrome.drawTabBar(vg, img.tabBg, {
            items = TAB_ITEMS,
            tabIdx = tabIdx, fromIdx = fromIdx, eased = tabEased,
            sliderW = TAB.SLIDER_W, sliderH = TAB.SLIDER_H,
            bgCX = TAB.BG_CX, bgCY = TAB.BG_CY, bgW = TAB.BG_W, bgH = TAB.BG_H,
            font = TAB.FONT_SIZE,
            active = { r = TAB.ACTIVE_R, g = TAB.ACTIVE_G, b = TAB.ACTIVE_B },
            inactive = { r = TAB.INACTIVE_R, g = TAB.INACTIVE_G, b = TAB.INACTIVE_B },
            activePred = function(i, _) return state.tab == TAB_KEYS[i] end,
            drawBadge = function(vg, i, item, textX, textY)
                local showTabBadge = TAB_KEYS[i] == "shenqi" and ArtifactPanel.canUpgradeAnyArtifact()
                if showTabBadge and img.iconUp >= 0 then
                    local upSize = 30
                    local textHalfW = nvgTextBounds(vg, 0, 0, item.name) * 0.5
                    drawImageCentered(vg, img.iconUp, textX + textHalfW + 10, textY - 18, upSize, upSize, 1.0)
                end
            end,
        })
        nvgRestore(vg)

        -- 名称牌盖住内容，神器详情再盖住名称牌和底栏。
        nvgSave(vg)
        nvgTranslate(vg, upperOX, 0)
        TownPageChrome.drawNamePlate(vg, img.nameBg, I18n.t("church"), {
            textCX = CHURCH.NAME_TEXT_CX, textCY = CHURCH.NAME_TEXT_CY, font = CHURCH.NAME_FONT_SIZE,
        })
        nvgRestore(vg)
        if state.tab == "shenqi" and not isAnimating then
            nvgSave(vg)
            nvgTranslate(vg, lowerOX, 0)
            ArtifactPanel.drawOverlay(vg)
            nvgRestore(vg)
        end
        ArtifactDrawPanel.drawKeyConfirmDialog(vg)
        SpineCardEffect.draw(vg, "church")

        if state.floatText then
            local FLOAT_DURATION, FLOAT_DIST = 1.5, 100
            local elapsed = time.elapsedTime - state.floatTextTime
            if elapsed >= FLOAT_DURATION then
                state.floatText = nil
            else
                local t = elapsed / FLOAT_DURATION
                drawTextStroke(vg, state.floatTextX, state.floatTextY - FLOAT_DIST * t,
                    state.floatText, 40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 80, 80, 6, { alpha = 1.0 - t })
            end
        end
        -- 专属抽卡是教堂页内模态，使用同一设计变换并覆盖旧提示与页签。
        if ArtifactDrawPanel.isAnimationPlaying() then ArtifactDrawPanel.drawAnimation(vg) end
    end

    return { drawPageImpl = drawPageImpl }
end

return M
