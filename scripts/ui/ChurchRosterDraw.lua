-- ============================================================================
-- ChurchRosterDraw - ChurchPage.drawRosterList 抽出（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local ROSTER = deps.ROSTER
    local DarkIcon = deps.DarkIcon
    local DrawUtil = deps.DrawUtil
    local CharacterPanel = deps.CharacterPanel
    local HC = deps.HC
    local AD = deps.AD
    local POWER_SKIP = deps.POWER_SKIP
    local ClassChange = deps.ClassChange
    local drawImageCentered = deps.drawImageCentered
    local drawTextStroke = deps.drawTextStroke
    local getHeroCardImage = deps.getHeroCardImage
    local getOwnedHeroList = deps.getOwnedHeroList
    local img = deps.img
    local rosterPowerCache = deps.rosterPowerCache
    local hasAdvanceForHero = deps.hasAdvanceForHero
    local DESIGN_W = deps.DESIGN_W
    local state = deps.state

    local function drawRosterList(vg)
        local ownedList = getOwnedHeroList()
        local rosterCount = #ownedList

        -- 1) 列表背景图（与角色面板相同的 UI_JSJM_0.png）
        drawImageCentered(vg, img.listBg, ROSTER.LIST_BG_CX, ROSTER.LIST_BG_CY, ROSTER.LIST_BG_W, ROSTER.LIST_BG_H, 1.0)

        -- 2) "选择远征队员"提示（原战斗力位置，标题上方）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        local listTopY = ROSTER.LIST_BG_CY - ROSTER.LIST_BG_H * 0.5
        nvgText(vg, ROSTER.MY_HEROES_CX, listTopY + 24, "选择", nil)

        -- 3) "远征团"标题（白色描边）
        drawTextStroke(vg, ROSTER.MY_HEROES_CX, ROSTER.MY_HEROES_CY, "远征团",
            42, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)

        if rosterCount == 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 32)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
            nvgText(vg, 540, ROSTER.ROW1_CY, "暂无远征队员", nil)
            return
        end

        -- 3) 角色卡片行（可滚动，裁剪到可视范围；用 Intersect 保留外层动画裁剪）
        nvgSave(vg)
        nvgIntersectScissor(vg, 0, ROSTER.SCROLL_TOP, DESIGN_W, ROSTER.SCROLL_BOTTOM - ROSTER.SCROLL_TOP)

        local scrollY = state.rosterScrollY
        for idx = 1, rosterCount do
            local entry = ownedList[idx]
            local heroCfg = HC.get(entry.heroId)
            if not heroCfg then goto continueRoster end

            -- 确定行列
            local row = math.ceil(idx / ROSTER.MAX_PER_ROW)
            local col = idx - (row - 1) * ROSTER.MAX_PER_ROW    -- 1~5

            -- 当前行有多少张卡（最后一行可能不满）
            local rowStart = (row - 1) * ROSTER.MAX_PER_ROW + 1
            local rowEnd   = math.min(row * ROSTER.MAX_PER_ROW, rosterCount)
            local rowCount = rowEnd - rowStart + 1

            -- 行的 Y 中心（应用滚动偏移）
            local rowCY = ROSTER.ROW1_CY + (row - 1) * ROSTER.ROW_SPACING - scrollY

            -- 快速跳过完全不可见的行
            local cardTop    = rowCY - ROSTER.CARD_H * 0.5 + ROSTER.TAG_OFFSET_Y
            local cardBottom = rowCY + ROSTER.NAME_BG_DY + ROSTER.NAME_BG_H2 * 0.5
            if cardBottom < ROSTER.SCROLL_TOP or cardTop > ROSTER.SCROLL_BOTTOM then
                goto continueRoster
            end

            -- 水平居中分布（按实际卡片数居中）
            local totalW = rowCount * ROSTER.CARD_W + (rowCount - 1) * ROSTER.CARD_SPACING
            local startCX = (DESIGN_W - totalW) * 0.5 + ROSTER.CARD_W * 0.5
            local cx = startCX + (col - 1) * (ROSTER.CARD_W + ROSTER.CARD_SPACING)
            local cy = rowCY

            -- a) 角色卡片
            local cardImg = getHeroCardImage(vg, entry.heroId)
            DrawUtil.drawImageCover(vg, cardImg, cx, cy, ROSTER.CARD_W, ROSTER.CARD_H, 1.0)

            -- b) 职业图标（左上角，60x60）
            local iconIdx = ClassChange.CLASS_NUM[heroCfg.classId]
            if iconIdx and img.classIcons[iconIdx] then
                drawImageCentered(vg, img.classIcons[iconIdx], cx, cy + ROSTER.TAG_OFFSET_Y, 60, 60, 1.0)
            end

            -- c) 战斗力图标+数值（居中于卡片）
            if not rosterPowerCache[entry.heroId] then
                local pw = 0
                local statLevel = entry.level or 1
                local heroUnit = HC.createHero(entry.heroId, statLevel, entry.advBranch, entry.awakening, entry.extraTalent)
                if heroUnit and heroUnit.attrs then
                    local a = heroUnit.attrs
                    CharacterPanel.applyEquippedItems(a, entry.heroId)
                    for key, meta in pairs(AD.META) do
                        if not POWER_SKIP[key] and meta.valueModel and meta.valueModel > 0 then
                            local val = a:get(key)
                            if meta.dataType == AD.TYPE_PCT then
                                pw = pw + val * (meta.valueModel / 100)
                            else
                                pw = pw + val * meta.valueModel
                            end
                        end
                    end
                end
                rosterPowerCache[entry.heroId] = math.floor(pw + 0.5)
            end
            local rPower = rosterPowerCache[entry.heroId] or 0
            local rPowerStr = tostring(rPower)
            local POWER_GAP = 4
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 30)
            local rptW = nvgTextBounds(vg, 0, 0, rPowerStr)
            local rpcW = ROSTER.POWER_ICON_SIZE + POWER_GAP + rptW
            local rpcX = cx - rpcW * 0.5
            DarkIcon.draw(vg, "power", rpcX + ROSTER.POWER_ICON_SIZE * 0.5, cy + ROSTER.POWER_DY, ROSTER.POWER_ICON_SIZE, 1.0)
            drawTextStroke(vg, rpcX + ROSTER.POWER_ICON_SIZE + POWER_GAP,
                cy + ROSTER.POWER_DY, rPowerStr,
                30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                247, 254, 119, 4)

            -- d) 经验条
            local expBarCX = cx + ROSTER.EXP_BAR_DX
            local expBarCY = cy + ROSTER.EXP_BAR_DY
            drawImageCentered(vg, img.expBarBg, expBarCX, expBarCY, ROSTER.EXP_BAR_BG_W, ROSTER.EXP_BAR_BG_H, 1.0)
            local expProgress = (entry.maxExp > 0) and (entry.exp / entry.maxExp) or 0
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
                nvgRestore(vg)
            end

            -- e) 等级徽章（与角色面板一致：显示有效等级，含共鸣）
            local badgeLevel = entry.level or 1
            local badgeCX = cx + ROSTER.LVL_BADGE_DX
            local badgeCY = cy + ROSTER.LVL_BADGE_DY
            drawImageCentered(vg, img.lvlBadge, badgeCX, badgeCY, ROSTER.LVL_BADGE_SIZE, ROSTER.LVL_BADGE_SIZE, 1.0)
            drawTextStroke(vg, badgeCX, badgeCY, tostring(badgeLevel),
                28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)

            -- f) 角色名背景（纯黑矩形，10%不透明度，圆角24）
            local nameBgCY = cy + ROSTER.NAME_BG_DY
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - ROSTER.NAME_BG_W2 * 0.5, nameBgCY - ROSTER.NAME_BG_H2 * 0.5,
                ROSTER.NAME_BG_W2, ROSTER.NAME_BG_H2, ROSTER.NAME_BG_RADIUS)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
            nvgFill(vg)

            -- g) 角色名文字（白色，黑描边4）
            drawTextStroke(vg, cx, nameBgCY, heroCfg.name,
                28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)

            -- h) 出战中标识（[三队并行] 显示所属队伍：队1/队2/队3）
            local deployTeams = CharacterPanel.getHeroDeployTeams and CharacterPanel.getHeroDeployTeams(entry.heroId) or nil
            if deployTeams and #deployTeams > 0 then
                local labels = {}
                for i, t in ipairs(deployTeams) do labels[i] = "队" .. t end
                drawImageCentered(vg, img.deployed, cx + ROSTER.DEPLOYED_DX, cy + ROSTER.DEPLOYED_DY, ROSTER.DEPLOYED_W, ROSTER.DEPLOYED_H, 1.0)
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, #deployTeams > 1 and 22 or 28)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, cx + ROSTER.DEPLOYED_DX, cy + ROSTER.DEPLOYED_TXT_DY, table.concat(labels, "·"), nil)
            end

            -- i) 可转职角标（右上角 ICON_UP 40x40）
            if hasAdvanceForHero(entry.heroId) and img.iconUp >= 0 then
                local upSize = 40
                local upX = cx + ROSTER.CARD_W * 0.5 - upSize * 0.5 - 2
                local upY = cy - ROSTER.CARD_H * 0.5 + upSize * 0.5 + 2
                drawImageCentered(vg, img.iconUp, upX, upY, upSize, upSize, 1.0)
            end

            ::continueRoster::
        end

        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    return { drawRosterList = drawRosterList }
end

return M
