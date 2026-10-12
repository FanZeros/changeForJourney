-- ============================================================================
-- BlacksmithDraw - BlacksmithPage.drawPageImpl（重写）
-- 中栏锻炉页：背景 + 名牌 + 装备工作台槽 + 强化/洗练双页签
-- 整页滑入由 BlacksmithPage.draw 外层 seamSlideX(+1) 处理，本层不再分段滑动
-- ============================================================================

local M = {}

function M.bind(deps)
    local ANIM_DURATION = deps.ANIM_DURATION
    local BlacksmithEnhance = deps.BlacksmithEnhance
    local BlacksmithPage = deps.BlacksmithPage
    local CLOSE_ANIM_DURATION = deps.CLOSE_ANIM_DURATION
    local DESIGN_W, DESIGN_H = deps.DESIGN_W, deps.DESIGN_H
    local DrawUtil = deps.DrawUtil
    local I18n = deps.I18n
    local LOWER_BG_CY = deps.LOWER_BG_CY
    local LOWER_BG_H = deps.LOWER_BG_H
    local NAME_FONT_SIZE = deps.NAME_FONT_SIZE
    local NAME_TEXT_CX, NAME_TEXT_CY = deps.NAME_TEXT_CX, deps.NAME_TEXT_CY
    local SLIDER_W, SLIDER_H = deps.SLIDER_W, deps.SLIDER_H
    local SpineResultEffect = deps.SpineResultEffect
    local TAB_ACTIVE_R, TAB_ACTIVE_G, TAB_ACTIVE_B = deps.TAB_ACTIVE_R, deps.TAB_ACTIVE_G, deps.TAB_ACTIVE_B
    local TAB_ANIM_DURATION = deps.TAB_ANIM_DURATION
    local TAB_BG_CX, TAB_BG_CY, TAB_BG_W, TAB_BG_H = deps.TAB_BG_CX, deps.TAB_BG_CY, deps.TAB_BG_W, deps.TAB_BG_H
    local TAB_FONT_SIZE = deps.TAB_FONT_SIZE
    local TAB_INACTIVE_R, TAB_INACTIVE_G, TAB_INACTIVE_B = deps.TAB_INACTIVE_R, deps.TAB_INACTIVE_G, deps.TAB_INACTIVE_B
    local TAB_ITEMS = deps.TAB_ITEMS
    local TAB_MAP = deps.TAB_MAP
    local TAB_TEXT_Y = deps.TAB_TEXT_Y
    local TownPageChrome = deps.TownPageChrome
    local drawTabContent = deps.drawTabContent
    local drawWorkbenchSlot = deps.drawWorkbenchSlot
    local easeInCubic = deps.easeInCubic
    local easeInOutCubic = deps.easeInOutCubic
    local easeOutCubic = deps.easeOutCubic
    local imgBg = deps.imgBg
    local imgIconUp = deps.imgIconUp
    local imgNameBg = deps.imgNameBg
    local imgTabBg = deps.imgTabBg
    local WORKBENCH_CX, WORKBENCH_CY = deps.WORKBENCH_CX, deps.WORKBENCH_CY
    local closeAutoWarehouse = deps.closeAutoWarehouse
    local state = deps.state

    local tabKeys = { "qianghua", "xilian" }

    local function drawPageImpl(vg)
        if not state.open then return end

        -- === 开合动画进度 ===
        if state.closing then
            local elapsed = time.elapsedTime - state.closeTime
            local rawT = math.min(1.0, elapsed / CLOSE_ANIM_DURATION)
            if rawT >= 1.0 then
                state.open = false
                state.closing = false
                if closeAutoWarehouse then closeAutoWarehouse() end
                local cb = deps.getOnCloseCallback and deps.getOnCloseCallback()
                if deps.setOnCloseCallback then deps.setOnCloseCallback(nil) end
                if cb then cb() end
                return
            end
        else
            local elapsed = time.elapsedTime - state.openTime
            local rawT = math.min(1.0, elapsed / ANIM_DURATION)
            local openCb = deps.getOnOpenCallback and deps.getOnOpenCallback()
            if rawT >= 1.0 and openCb then
                if deps.setOnOpenCallback then deps.setOnOpenCallback(nil) end
                openCb()
            end
        end

        -- === 不透明底（锻炉在中栏，盖住城镇）===
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0x14, 0x12, 0x10, 255))
        nvgFill(vg)

        -- === 整页单一背景（UI_SMITH_BG_FULL 按设计分辨率对齐拉伸：比例差仅1.6%，
        --    保证背景暗板框与 UI 元素坐标精确对齐）+ 名牌 + 工作台槽 ===
        nvgSave(vg)
        nvgIntersectScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        DrawUtil.drawImageCentered(vg, imgBg, DESIGN_W * 0.5, DESIGN_H * 0.5, DESIGN_W, DESIGN_H, 1.0)
        nvgResetScissor(vg)
        nvgRestore(vg)

        TownPageChrome.drawNamePlate(vg, imgNameBg, I18n.t("blacksmith"),
            { textCX = NAME_TEXT_CX, textCY = NAME_TEXT_CY, font = NAME_FONT_SIZE,
              bgCX = deps.NAME_BG_CX, bgCY = deps.NAME_BG_CY })

        -- 装备工作台槽（强化/洗练共用）
        drawWorkbenchSlot(vg)

        -- 强化结果特效（叠在工作台槽上）
        if SpineResultEffect.isPlaying() then
            SpineResultEffect.draw(vg, WORKBENCH_CX, WORKBENCH_CY, BlacksmithPage.WORKBENCH.size)
        end

        -- === 下半部分：tab 内容 + tab 栏（背景由整页单一暗黑底提供）===
        local clipTop = LOWER_BG_CY - LOWER_BG_H * 0.5
        local clipBottom = TAB_BG_CY - TAB_BG_H * 0.5
        nvgSave(vg)
        -- 与宿主视口取交集，开合平移时不能把裁剪范围替换到左栏背包。
        nvgIntersectScissor(vg, 0, clipTop, DESIGN_W, clipBottom - clipTop)
        drawTabContent(vg, state.tab)
        nvgResetScissor(vg)
        nvgRestore(vg)

        local tabIdx = TAB_MAP[state.tab] or 1
        local fromIdx = TAB_MAP[state.tabFrom] or 1
        local tabElapsed = time.elapsedTime - state.tabSwitchTime
        local tabT = math.min(1.0, tabElapsed / TAB_ANIM_DURATION)
        local tabEased = easeInOutCubic(tabT)

        TownPageChrome.drawTabBar(vg, imgTabBg, {
            items = TAB_ITEMS,
            tabIdx = tabIdx, fromIdx = fromIdx, eased = tabEased,
            sliderW = SLIDER_W, sliderH = SLIDER_H,
            bgCX = TAB_BG_CX, bgCY = TAB_BG_CY, bgW = TAB_BG_W, bgH = TAB_BG_H,
            font = TAB_FONT_SIZE, textY = TAB_TEXT_Y,
            active = { r = TAB_ACTIVE_R, g = TAB_ACTIVE_G, b = TAB_ACTIVE_B },
            inactive = { r = TAB_INACTIVE_R, g = TAB_INACTIVE_G, b = TAB_INACTIVE_B },
            activePred = function(i, _) return state.tab == tabKeys[i] end,
            drawBadge = function(vg2, i, item, textX, textY)
                if i == 1 and imgIconUp and imgIconUp >= 0 and BlacksmithPage.canEnhanceSelected() then
                    nvgFontFace(vg2, "sans"); nvgFontSize(vg2, TAB_FONT_SIZE)
                    local upSize = 30
                    local textHalfW = nvgTextBounds(vg2, 0, 0, item.name) * 0.5
                    DrawUtil.drawImageCentered(vg2, imgIconUp, textX + textHalfW + 10, textY - 18, upSize, upSize, 1.0)
                end
            end,
        })

        -- 一键强化确认弹窗（强化 tab，最顶层）
        if state.tab == "qianghua" then
            BlacksmithEnhance.drawConfirmDialog(vg)
        end
    end

    --- 左栏仅铺不透明底防止城镇穿透；仓库自己的背景与标题随其滑入绘制。
    --- 不复用锻炉背景，避免双页出现两个锻炉。
    ---@param vg any
    local function drawUnderlay(vg)
        if not state.open then return end
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0x14, 0x12, 0x10, 255))
        nvgFill(vg)
    end

    return { drawPageImpl = drawPageImpl, drawUnderlay = drawUnderlay }
end

return M
