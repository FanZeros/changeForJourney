-- ============================================================================
-- ChurchDraw - ChurchPage.drawPageImpl 抽出（玩法不变）
-- ============================================================================

local AD = require("systems.AttributeDef")
local CharacterPanel = require("ui.character.panel.CharacterPanel")
local SpineCardEffect = require("ui.fx.SpineCardEffect")
-- 转职已迁到右侧栏角色详情，教堂不再绘制转职页
local ArtifactPanel = require("ui.church.ChurchArtifactPanel")
local I18n = require("core.I18n")

local M = {}

function M.bind(deps)
    local ANIM = deps.ANIM
    local CHURCH = deps.CHURCH
    local CHAR_SLOT = deps.CHAR_SLOT
    local DESIGN_H = deps.DESIGN_H
    local DESIGN_W = deps.DESIGN_W
    local DarkIcon = deps.DarkIcon
    local DrawUtil = deps.DrawUtil
    local GameState = deps.GameState
    local HC = deps.HC
    local NumberUtil = deps.NumberUtil
    local POWER_SKIP = deps.POWER_SKIP
    local ROSTER = deps.ROSTER
    local TAB = deps.TAB
    local TAB_ITEMS = deps.TAB_ITEMS
    local TAB_KEYS = deps.TAB_KEYS
    local TAB_MAP = deps.TAB_MAP
    local TownPageChrome = deps.TownPageChrome
    local clampRosterScroll = deps.clampRosterScroll
    local drawImageCentered = deps.drawImageCentered
    local drawRosterList = deps.drawRosterList
    local drawTextStroke = deps.drawTextStroke
    local easeInCubic = deps.easeInCubic
    local easeInOutCubic = deps.easeInOutCubic
    local easeOutCubic = deps.easeOutCubic
    local getHeroCardImage = deps.getHeroCardImage
    local getRosterScrollMax = deps.getRosterScrollMax
    local img = deps.img
    local powerCache = deps.powerCache
    local hasAnyAdvance = deps.hasAnyAdvance
    local hasAnyUnusedTalent = deps.hasAnyUnusedTalent
    local state = deps.state
    local updateRosterSlide = deps.updateRosterSlide
    local updateSelectAnim = deps.updateSelectAnim
    local updateSlotAnim = deps.updateSlotAnim

    local function drawPageImpl(vg)
        if not state.open then return end

        -- 更新槽位动画
        updateSlotAnim()
        updateSelectAnim()
        updateRosterSlide()

        -- 更新角色列表滚动惯性
        if state.rosterScrollVelocity ~= 0 and not state.rosterDragging then
            state.rosterScrollY = state.rosterScrollY - state.rosterScrollVelocity
            state.rosterScrollVelocity = state.rosterScrollVelocity * 0.92
            clampRosterScroll()
            if math.abs(state.rosterScrollVelocity) < 0.5 or state.rosterScrollY <= 0 or state.rosterScrollY >= getRosterScrollMax() then
                state.rosterScrollVelocity = 0
            end
        end

        -- === 弹出/关闭动画 ===
        local rawT, progress, lowerProgress

        if state.closing then
            local elapsed = time.elapsedTime - state.closeTime
            rawT = math.min(1.0, elapsed / ANIM.CLOSE_DUR)
            progress      = 1 - easeInCubic(rawT)
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
            progress      = easeOutCubic(rawT)
            lowerProgress = easeOutCubic(rawT)
            local openCb = deps.getOnOpenCallback and deps.getOnOpenCallback()
            if rawT >= 1.0 and openCb then
                if deps.setOnOpenCallback then deps.setOnOpenCallback(nil) end
                openCb()
            end
        end

        -- 整页已由 ChurchPage.draw 的 seamSlideX 与中缝条同步；内部分段滑/淡入会打架。
        local seamMode = H_SEAM_BACK == true
        local upperDist = state.closing and ANIM.UPPER_SLIDE_OUT or ANIM.UPPER_SLIDE_IN
        local upperOX = seamMode and 0 or (-upperDist * (1 - progress))
        local lowerOX = seamMode and 0 or (-ANIM.LOWER_SLIDE_DIST * (1 - lowerProgress))
        local overlayAlpha = seamMode and 0 or math.floor(180 * progress)

        -- === 全屏遮罩 ===
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
        nvgFill(vg)

        -- === Tab 滑动动画（提前计算，供背景和内容共用） ===
        local tabIdx = TAB_MAP[state.tab] or 1
        local fromIdx = TAB_MAP[state.tabFrom] or 1
        local tabElapsed = time.elapsedTime - state.tabSwitchTime
        local tabT = math.min(1.0, tabElapsed / TAB.ANIM_DUR)
        local tabEased = easeInOutCubic(tabT)

        local direction = 0
        if tabIdx ~= fromIdx then
            direction = (tabIdx < fromIdx) and -1 or 1
        end
        -- 垂直滑动: 转职(idx=1)在上，天赋(idx=2)在下
        -- tianfu→zhuanzhi: direction=-1, 旧页下滑(+Y), 新页从上进入(-Y→0)
        -- zhuanzhi→tianfu: direction=1, 旧页上滑(-Y), 新页从下进入(+Y→0)
        local newOY_tab = DESIGN_H * direction * (1 - tabEased)
        local oldOY_tab = -DESIGN_H * direction * tabEased
        local isAnimating = (tabT < 1.0 and tabIdx ~= fromIdx)

        -- 延迟清除：Tab 切换动画结束后清除旧 Tab 的英雄选中态
        if not isAnimating and state._deferClearHero then
            state.selectedHeroId = nil
            state._deferClearHero = false
            state.slotLiftProgress = 0
        end

        -- === 槽位上移偏移 ===
        local slotLiftOY = -ANIM.SLOT_LIFT * state.slotLiftProgress

        -- 计算教堂上半部分（属于转职视图）在 tab 动画期间的垂直偏移
        local upperTabOY = 0
        if isAnimating then
            if state.tabFrom == "zhuanzhi" then
                upperTabOY = oldOY_tab  -- 转职是旧 tab，跟着滑出
            elseif state.tab == "zhuanzhi" then
                upperTabOY = newOY_tab  -- 转职是新 tab，跟着滑入
            end
        end

        -- ================== 上半部分（从上方滑入） ==================
        nvgSave(vg)
        nvgTranslate(vg, upperOX, upperTabOY)

        local isArtifactTab = (state.tab == "shenqi")

        -- 1. 教堂背景图（神器 Tab 隐藏，避免遮挡 UI_JTSQ_BJ）
        local hideChurchBg = isArtifactTab
            and not (isAnimating and state.tabFrom == "shenqi")
        if not hideChurchBg then
            nvgSave(vg)
            nvgTranslate(vg, 0, slotLiftOY)
            nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
            drawImageCentered(vg, img.bg, CHURCH.BG_CX, CHURCH.BG_CY, CHURCH.BG_W, CHURCH.BG_H, 1.0)
            nvgResetScissor(vg)
            nvgRestore(vg)
        end

        if not isArtifactTab then
            -- 2-3. 建筑名称牌（不跟随上移）
            TownPageChrome.drawNamePlate(vg, img.nameBg, I18n.t("church"), {
                textCX = CHURCH.NAME_TEXT_CX, textCY = CHURCH.NAME_TEXT_CY, font = CHURCH.NAME_FONT_SIZE,
            })

        -- 3.5 资源显示：金币 & 宝石（与主界面 TopBar 相同位置和样式）
        do
            local resY = 100
            -- 金币背景
            local goldBgX = 732 - 170 * 0.5
            nvgBeginPath(vg)
            nvgRoundedRect(vg, goldBgX, resY - 47 * 0.5, 170, 47, 18)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
            nvgFill(vg)
            -- 金币图标
            drawImageCentered(vg, img.resGold, 653, resY, 73, 73, 1.0)
            -- 金币数值
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 33)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, goldBgX + 44, resY, NumberUtil.format(GameState.getGold()), nil)

            -- 宝石背景
            local gemBgX = 965 - 170 * 0.5
            nvgBeginPath(vg)
            nvgRoundedRect(vg, gemBgX, resY - 47 * 0.5, 170, 47, 18)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
            nvgFill(vg)
            -- 宝石图标
            drawImageCentered(vg, img.resDiamond, 884, resY, 76, 76, 1.0)
            -- 宝石数值
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 33)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, gemBgX + 44, resY, NumberUtil.format(GameState.getGems()), nil)
        end

        -- 4. 角色选择框（跟随上移）
        nvgSave(vg)
        nvgTranslate(vg, 0, slotLiftOY)

        if state.selectedHeroId then
            -- 已选角色 → 显示角色卡牌 + 详细信息（与角色面板一致）
            local heroCfg = HC.get(state.selectedHeroId)
            local ownData = CharacterPanel.getOwnedHero(state.selectedHeroId)
            local cx, cy = CHAR_SLOT.CX, CHAR_SLOT.CY

            -- a) 角色卡牌（飞行动画期间隐藏槽位上的卡片，由飞行动画绘制）
            if not state.selectAnim then
            local cardImg = getHeroCardImage(vg, state.selectedHeroId)
            DrawUtil.drawImageCover(vg, cardImg, cx, cy, CHAR_SLOT.W, CHAR_SLOT.H, 1.0)
            end

            if heroCfg then
                -- b) 职业图标（左上角，60x60）
                local iconIdx = heroCfg.classId
                if iconIdx and img.classIcons[iconIdx] then
                    drawImageCentered(vg, img.classIcons[iconIdx], cx, cy + ROSTER.TAG_OFFSET_Y, 60, 60, 1.0)
                end

                -- c) 战斗力图标+数值（居中于卡片，与角色面板一致）
                local realLevel = ownData and ownData.level or 1
                local statLevel = realLevel
                -- 使用缓存，仅当角色变更时重新计算
                if powerCache.heroId ~= state.selectedHeroId then
                    powerCache.heroId = state.selectedHeroId
                    powerCache.value = 0
                    local selAdvBranch = ownData and ownData.advBranch or nil
                    local selAwakening = ownData and ownData.awakening or nil
                    local heroUnit = HC.createHero(state.selectedHeroId, statLevel, selAdvBranch, selAwakening, ownData and ownData.extraTalent)
                    if heroUnit and heroUnit.attrs then
                        local a = heroUnit.attrs
                        CharacterPanel.applyEquippedItems(a, state.selectedHeroId)
                        local total = 0
                        for key, meta in pairs(AD.META) do
                            if not POWER_SKIP[key] and meta.valueModel and meta.valueModel > 0 then
                                local val = a:get(key)
                                if meta.dataType == AD.TYPE_PCT then
                                    total = total + val * (meta.valueModel / 100)
                                else
                                    total = total + val * meta.valueModel
                                end
                            end
                        end
                        powerCache.value = math.floor(total + 0.5)
                    end
                end
                local power = powerCache.value
                local powerStr = tostring(power)
                local POWER_GAP = 4
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 30)
                local ptW = nvgTextBounds(vg, 0, 0, powerStr)
                local pcW = ROSTER.POWER_ICON_SIZE + POWER_GAP + ptW
                local pcX = cx - pcW * 0.5
                DarkIcon.draw(vg, "power", pcX + ROSTER.POWER_ICON_SIZE * 0.5, cy + ROSTER.POWER_DY, ROSTER.POWER_ICON_SIZE, 1.0)
                drawTextStroke(vg, pcX + ROSTER.POWER_ICON_SIZE + POWER_GAP,
                    cy + ROSTER.POWER_DY, powerStr,
                    30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                    247, 254, 119, 4)

                -- d) 经验条
                local exp = ownData and ownData.exp or 0
                local maxExp = ownData and ownData.maxExp or 5
                local expBarCX = cx + ROSTER.EXP_BAR_DX
                local expBarCY = cy + ROSTER.EXP_BAR_DY
                drawImageCentered(vg, img.expBarBg, expBarCX, expBarCY, ROSTER.EXP_BAR_BG_W, ROSTER.EXP_BAR_BG_H, 1.0)
                local expProgress = (maxExp > 0) and (exp / maxExp) or 0
                expProgress = math.max(0, math.min(1, expProgress))
                local fillW = ROSTER.EXP_BAR_BG_W - ROSTER.EXP_BAR_PADDING * 2 - ROSTER.EXP_FILL_LEFT_INSET
                local fillH = ROSTER.EXP_BAR_BG_H - ROSTER.EXP_BAR_PADDING * 2
                local fillX = expBarCX - ROSTER.EXP_BAR_BG_W * 0.5 + ROSTER.EXP_BAR_PADDING + ROSTER.EXP_FILL_LEFT_INSET
                local fillY = expBarCY - ROSTER.EXP_BAR_BG_H * 0.5 + ROSTER.EXP_BAR_PADDING
                local clipW = fillW * expProgress
                if clipW > 0 and img.expBarFill >= 0 then
                    nvgSave(vg)
                    nvgIntersectScissor(vg, fillX, fillY, clipW, fillH)
                    local paint = nvgImagePattern(vg, fillX, fillY, fillW, fillH, 0, img.expBarFill, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, fillX, fillY, fillW, fillH)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                    nvgResetScissor(vg)
                    nvgRestore(vg)
                end

                -- e) 等级徽章
                local badgeCX = cx + ROSTER.LVL_BADGE_DX
                local badgeCY = cy + ROSTER.LVL_BADGE_DY
                drawImageCentered(vg, img.lvlBadge, badgeCX, badgeCY, ROSTER.LVL_BADGE_SIZE, ROSTER.LVL_BADGE_SIZE, 1.0)
                drawTextStroke(vg, badgeCX, badgeCY, tostring(statLevel),
                    28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 4)

                -- f) 角色名背景 + 文字
                local nameBgCY = cy + ROSTER.NAME_BG_DY
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - ROSTER.NAME_BG_W2 * 0.5, nameBgCY - ROSTER.NAME_BG_H2 * 0.5,
                    ROSTER.NAME_BG_W2, ROSTER.NAME_BG_H2, ROSTER.NAME_BG_RADIUS)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
                nvgFill(vg)
                drawTextStroke(vg, cx, nameBgCY, heroCfg.name,
                    28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 4)
            end
        else
            -- 空槽位
            nvgBeginPath(vg)
            nvgRoundedRect(vg,
                CHAR_SLOT.CX - CHAR_SLOT.W * 0.5,
                CHAR_SLOT.CY - CHAR_SLOT.H * 0.5,
                CHAR_SLOT.W, CHAR_SLOT.H,
                CHAR_SLOT.R)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
            nvgFill(vg)
            -- 加号图标居中
            drawImageCentered(vg, img.plus, CHAR_SLOT.CX, CHAR_SLOT.CY, CHAR_SLOT.PLUS_W, CHAR_SLOT.PLUS_H, 1.0)
            -- 空槽位右上角可转职角标
            if hasAnyAdvance() and img.iconUp >= 0 then
                local upSize = 40
                local upX = CHAR_SLOT.CX + CHAR_SLOT.W * 0.5 - upSize * 0.5 - 2
                local upY = CHAR_SLOT.CY - CHAR_SLOT.H * 0.5 + upSize * 0.5 + 2
                drawImageCentered(vg, img.iconUp, upX, upY, upSize, upSize, 1.0)
            end
        end

        nvgRestore(vg)  -- 结束槽位上移偏移
        end

        nvgRestore(vg)  -- 结束上半部分偏移

        -- === Tab 全屏背景（上半部分之后绘制，覆盖教堂室内背景） ===
        nvgSave(vg)
        nvgTranslate(vg, lowerOX, 0)
        if isAnimating then
            -- 旧 tab 背景（垂直滑出）：先裁剪到屏幕可见区域，再纵向平移
            local oVisTop = math.max(0, oldOY_tab)
            local oVisBot = math.min(DESIGN_H, oldOY_tab + DESIGN_H)
            if oVisBot > oVisTop then
                nvgSave(vg)
                nvgScissor(vg, 0, oVisTop, DESIGN_W, oVisBot - oVisTop)
                nvgTranslate(vg, 0, oldOY_tab)
                if state.tabFrom == "shenqi" then ArtifactPanel.drawBg(vg) end
                nvgRestore(vg)
            end
            -- 新 tab 背景（垂直滑入）
            local nVisTop = math.max(0, newOY_tab)
            local nVisBot = math.min(DESIGN_H, newOY_tab + DESIGN_H)
            if nVisBot > nVisTop then
                nvgSave(vg)
                nvgScissor(vg, 0, nVisTop, DESIGN_W, nVisBot - nVisTop)
                nvgTranslate(vg, 0, newOY_tab)
                if state.tab == "shenqi" then ArtifactPanel.drawBg(vg) end
                nvgRestore(vg)
            end
        else
            if state.tab == "shenqi" then ArtifactPanel.drawBg(vg) end
        end
        nvgRestore(vg)

        -- （教堂名称移至 Tab 内容之后绘制，确保在星图上方）

        -- ================== 下半部分（从下方滑入） ==================
        nvgSave(vg)
        nvgTranslate(vg, lowerOX, 0)

        -- Tab 内容剪裁区域（延伸到屏幕底部，让星图显示在底部按钮后方）
        local clipTop = 0
        local clipBottom = DESIGN_H
        local clipH = clipBottom - clipTop

        -- （Tab 动画变量和背景已在上半部分之前绘制）

        -- drawTabContent 内联委托
        local function drawTabContent(tabKey)
            if tabKey == "shenqi" then ArtifactPanel.drawContent(vg) end
        end

        -- 绘制旧面板内容（垂直滑出，仅动画中）
        if isAnimating then
            local oVisTop = math.max(clipTop, clipTop + oldOY_tab)
            local oVisBot = math.min(clipTop + clipH, clipTop + oldOY_tab + clipH)
            if oVisBot > oVisTop then
                nvgSave(vg)
                nvgScissor(vg, 0, oVisTop, DESIGN_W, oVisBot - oVisTop)
                nvgTranslate(vg, 0, oldOY_tab)
                drawTabContent(state.tabFrom)
                nvgRestore(vg)
            end
        end

        -- 绘制新面板内容（垂直滑入）
        if isAnimating then
            local nVisTop = math.max(clipTop, clipTop + newOY_tab)
            local nVisBot = math.min(clipTop + clipH, clipTop + newOY_tab + clipH)
            if nVisBot > nVisTop then
                nvgSave(vg)
                nvgScissor(vg, 0, nVisTop, DESIGN_W, nVisBot - nVisTop)
                nvgTranslate(vg, 0, newOY_tab)
                drawTabContent(state.tab)
                nvgRestore(vg)
            end
        else
            nvgSave(vg)
            nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)
            drawTabContent(state.tab)
            nvgRestore(vg)
        end

        -- 6. 返回按钮（三行模式由中缝层绘制）
        TownPageChrome.drawBack(vg)

        -- 7-8. 底栏 Tab
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
                local showTabBadge = false
                if i == 1 then
                    showTabBadge = ArtifactPanel.canUpgradeAnyArtifact()
                end
                if showTabBadge and img.iconUp >= 0 then
                    local upSize = 30
                    local textHalfW = nvgTextBounds(vg, 0, 0, item.name) * 0.5
                    drawImageCentered(vg, img.iconUp, textX + textHalfW + 10, textY - 18, upSize, upSize, 1.0)
                end
            end,
        })

        -- 天赋已独立到古树，教堂不再注册 talent_toggle

        nvgRestore(vg)  -- 结束下半部分偏移

        -- === 教堂名称（在 Tab 内容之上重绘，跟随 upperOX，确保不被星图覆盖） ===
        nvgSave(vg)
        nvgTranslate(vg, upperOX, 0)
        TownPageChrome.drawNamePlate(vg, img.nameBg, I18n.t("church"), {
            textCX = CHURCH.NAME_TEXT_CX, textCY = CHURCH.NAME_TEXT_CY, font = CHURCH.NAME_FONT_SIZE,
        })
        nvgRestore(vg)

        -- ================== 角色列表浮层（独立绘制，不被下半部分遮盖） ==================
        -- 仅在展开状态（slotExpanded）时绘制；选中远征队员后 slotExpanded=false 但 slotLiftProgress 保持1.0
        if false and (state.slotExpanded or state.rosterSlideProgress > 0.01) and state.slotLiftProgress > 0.01 then
            local rosterAlpha = state.slotLiftProgress * state.rosterSlideProgress
            nvgSave(vg)
            nvgGlobalAlpha(vg, rosterAlpha)

            -- 列表滑入/滑出偏移（从下方滑入/向下滑出）
            local slideOY = ANIM.ROSTER_SLIDE_DIST * (1.0 - state.rosterSlideProgress)
            nvgTranslate(vg, 0, slideOY)

            -- 直接绘制列表（无黑色遮罩，列表背景图自带底色）
            -- 列表背景底部不截断，直接显示到设计分辨率底部
            drawRosterList(vg)

            nvgGlobalAlpha(vg, 1.0)
            nvgRestore(vg)
        end

        -- ================== 卡片飞行动画 ==================
        if state.selectAnim and state.selectedHeroId then
            local elapsed = time.elapsedTime - state.selectAnimTime
            local t = math.min(1.0, elapsed / ANIM.SELECT_DUR)
            local eased = easeOutCubic(t)

            -- 目标位置 = 槽位已上移后的位置
            local targetCX = CHAR_SLOT.CX
            local targetCY = CHAR_SLOT.CY - ANIM.SLOT_LIFT

            -- 从列表卡片位置飞向槽位
            local curX = state.selectAnimFromX + (targetCX - state.selectAnimFromX) * eased
            local curY = state.selectAnimFromY + (targetCY - state.selectAnimFromY) * eased

            -- 缩放：卡片从列表尺寸到槽位尺寸（两者相同则无缩放）
            local cardImg = getHeroCardImage(vg, state.selectedHeroId)
            nvgSave(vg)
            nvgGlobalAlpha(vg, 1.0)
            DrawUtil.drawImageCover(vg, cardImg, curX, curY, ROSTER.CARD_W, ROSTER.CARD_H, 1.0)
            nvgRestore(vg)
        end

        -- 天赋详情/总览已移至 TalentPage

        -- 转职确认/重置弹窗已随转职页迁到右侧栏角色详情

        -- ================== Spine 卡牌特效 ==================
        SpineCardEffect.draw(vg, "church")

        -- ================== 飘字提示（最最顶层） ==================
        if state.floatText then
            local FLOAT_DURATION = 1.5   -- 飘字持续时间（秒）
            local FLOAT_DIST     = 100   -- 向上飘动距离
            local elapsed = time.elapsedTime - state.floatTextTime
            if elapsed >= FLOAT_DURATION then
                state.floatText = nil  -- 飘字结束
            else
                local t = elapsed / FLOAT_DURATION
                local alpha = 1.0 - t   -- 0~1 范围（drawTextStroke opts.alpha 使用 0~1）
                local offsetY = -FLOAT_DIST * t
                drawTextStroke(vg, state.floatTextX, state.floatTextY + offsetY,
                    state.floatText,
                    40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 80, 80, 6,
                    { alpha = alpha })
            end
        end
    end


    return { drawPageImpl = drawPageImpl }
end

return M
