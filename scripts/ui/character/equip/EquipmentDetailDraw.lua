-- ============================================================================
-- EquipmentDetailDraw - 装备详情的两个绘制入口
-- 业务、布局计算与输入仍由 EquipmentDetail 持有。
-- detState / setKw 传共享引用；图片通过 getter 每次绘制读取，避免捕获 init 前的 -1。
-- ============================================================================

local EquipmentConfig = require("config.EquipmentConfig")
local EquipmentSystem = require("systems.EquipmentSystem")
local EquipmentSetConfig = require("config.EquipmentSetConfig")
local AffixConfig = require("config.AffixConfig")
local EquipmentSetIcon = require("ui.widget.EquipmentSetIcon")
local BF = require("systems.ButtonFeedback")
local DarkIcon = require("core.DarkIcon")
local TutorialManager = require("systems.TutorialManager")
local BlacksmithConfig = require("config.BlacksmithConfig")
local I18n = require("core.I18n")
local I18nEquipmentText = require("core.I18nEquipmentText")

---@class EquipmentDetailDrawImages
---@field powerIcon integer
---@field arrowUp integer
---@field arrowDown integer
---@field btnGreen integer
---@field btnYellow integer
---@field btnRed integer
---@field lock integer
---@field affixBadge table<string, integer>

---@class EquipmentDetailDrawContext
---@field detState table 共用活状态，绘制写回热区和滚动范围
---@field setKw KeywordTextInstance[] 原面板持有的关键词实例
---@field getImages fun(): EquipmentDetailDrawImages init 后的实时图片句柄
---@field layout table<string, number> 不可变布局常量，与输入计算同源
---@field qualityColor number[][]
---@field affixBadgeKey string[]
---@field drawImageCentered function
---@field drawTextStroke function
---@field calcEquipPower function
---@field getEquipIcon function
---@field getStatName function
---@field formatStatValue function
---@field layoutButtons function
---@field clampDescScroll function
---@field compactViewHeight function
---@field compactSetLines function
---@field compactSetRowHeight function
---@field compactContentBottom function
---@field compactButtonRow function

local EquipmentDetailDraw = {}

-- 标题行已经是完整译文的片段。描边也走raw出口，禁止全局draw hook重译局部词。
local function drawTitleRow(vg, x, y, text, font, stroke)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, font)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
    for index = 0, 7 do
        local angle = index * math.pi * 0.25
        I18n.displayText(vg, x + math.cos(angle) * stroke, y + math.sin(angle) * stroke, text, nil)
    end
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    I18n.displayText(vg, x, y, text, nil)
end

-- 标题、锁热区与战力共享同一宽度预算；折行只分割显示译文，不改装备原名。
-- 固定标题带最多两行，后续类型/属性/按钮的坐标和面板高度不变。
local function titleLayout(vg, text, width, preferredFont, minimumFont, lockSize, touchPad, stroke)
    local lockSpace = lockSize > 0 and (touchPad + stroke + 6 + lockSize + touchPad) or 0
    local textWidth = math.max(1, width - lockSpace - stroke * 2)
    local function measure(part, font)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, font)
        local advance = I18n.displayBounds(vg, 0, 0, part)
        return advance
    end
    local font = preferredFont
    while font > minimumFont and measure(text, font) > textWidth do font = font - 1 end
    local rows = { text }
    if measure(text, font) > textWidth then
        -- UTF-8/空格完整保留；优先在词间折行，单个长词也可以逐字折行。
        local function wrap(size)
            local result, row, wordEnd = {}, "", 0
            for _, codepoint in utf8.codes(text) do
                local char = utf8.char(codepoint)
                if row ~= "" and measure(row .. char, size) > textWidth then
                    if wordEnd > 0 then
                        result[#result + 1] = row:sub(1, wordEnd)
                        row = row:sub(wordEnd + 1)
                    else
                        result[#result + 1], row = row, ""
                    end
                    wordEnd = 0
                end
                row = row .. char
                if char == " " then wordEnd = #row end
            end
            if row ~= "" then result[#result + 1] = row end
            return result
        end
        rows = wrap(font)
        while #rows > 2 and font > 1 do
            font = font - 1
            rows = wrap(font)
        end
    end
    local widest = 0
    for _, row in ipairs(rows) do widest = math.max(widest, measure(row, font)) end
    return rows, font, widest
end

--- 只捕获共享引用、不可变布局与函数；不捕获尚未初始化的图片数值。
---@param ctx EquipmentDetailDrawContext
function EquipmentDetailDraw.create(ctx)
    local detState = ctx.detState
    local setKw = ctx.setKw
    local QUALITY_COLOR = ctx.qualityColor
    local AFFIX_BADGE_KEY = ctx.affixBadgeKey
    local drawImageCentered = ctx.drawImageCentered
    local drawTextStroke = ctx.drawTextStroke
    local calcEquipPower = ctx.calcEquipPower
    local getEquipIcon = ctx.getEquipIcon
    local getStatName = ctx.getStatName
    local formatStatValue = ctx.formatStatValue
    local layoutButtons = ctx.layoutButtons
    local clampDescScroll = ctx.clampDescScroll
    local compactViewHeight = ctx.compactViewHeight
    local compactSetLines = ctx.compactSetLines
    local compactSetRowHeight = ctx.compactSetRowHeight
    local compactContentBottom = ctx.compactContentBottom
    local compactButtonRow = ctx.compactButtonRow
    local COMPACT_BG_W = ctx.layout.COMPACT_BG_W
    local COMPACT_ICON_CY = ctx.layout.COMPACT_ICON_CY
    local COMPACT_ICON_SIZE = ctx.layout.COMPACT_ICON_SIZE
    local COMPACT_NAME_Y = ctx.layout.COMPACT_NAME_Y
    local COMPACT_PAD_TOP = ctx.layout.COMPACT_PAD_TOP
    local COMPACT_QUALITY_Y = ctx.layout.COMPACT_QUALITY_Y
    local COMPACT_STAT_Y0 = ctx.layout.COMPACT_STAT_Y0
    local COMPACT_TYPE_Y = ctx.layout.COMPACT_TYPE_Y
    local DESC_TOP = ctx.layout.DESC_TOP
    local REF_AFFIX_GAP = ctx.layout.REF_AFFIX_GAP
    local REF_AFFIX_GAP_TOP = ctx.layout.REF_AFFIX_GAP_TOP
    local REF_AFFIX_ROW_H = ctx.layout.REF_AFFIX_ROW_H
    local REF_AFFIX_TEXT_X = ctx.layout.REF_AFFIX_TEXT_X
    local REF_AFFIX_TITLE_FONT = ctx.layout.REF_AFFIX_TITLE_FONT
    local REF_AFFIX_TITLE_X = ctx.layout.REF_AFFIX_TITLE_X
    local REF_AFFIX_TITLE_Y = ctx.layout.REF_AFFIX_TITLE_Y
    local REF_ARROW_GAP = ctx.layout.REF_ARROW_GAP
    local REF_ARROW_SIZE = ctx.layout.REF_ARROW_SIZE
    local REF_BADGE_CX = ctx.layout.REF_BADGE_CX
    local REF_BADGE_H = ctx.layout.REF_BADGE_H
    local REF_BADGE_W = ctx.layout.REF_BADGE_W
    local REF_BG_CX = ctx.layout.REF_BG_CX
    local REF_BTN_CX = ctx.layout.REF_BTN_CX
    local REF_BTN_FONT = ctx.layout.REF_BTN_FONT
    local REF_BTN_H = ctx.layout.REF_BTN_H
    local REF_BTN_W = ctx.layout.REF_BTN_W
    local REF_DEC_BTN_GAP = ctx.layout.REF_DEC_BTN_GAP
    local REF_ENH_BTN_FONT = ctx.layout.REF_ENH_BTN_FONT
    local REF_ENH_BTN_GAP = ctx.layout.REF_ENH_BTN_GAP
    local REF_ENH_BTN_H = ctx.layout.REF_ENH_BTN_H
    local REF_ENH_BTN_W = ctx.layout.REF_ENH_BTN_W
    local REF_ICON_CX = ctx.layout.REF_ICON_CX
    local REF_ICON_CY = ctx.layout.REF_ICON_CY
    local REF_ICON_SIZE = ctx.layout.REF_ICON_SIZE
    local REF_NAME_FONT = ctx.layout.REF_NAME_FONT
    local REF_NAME_X = ctx.layout.REF_NAME_X
    local REF_NAME_Y = ctx.layout.REF_NAME_Y
    local REF_QUALITY_FONT = ctx.layout.REF_QUALITY_FONT
    local REF_QUALITY_X = ctx.layout.REF_QUALITY_X
    local REF_QUALITY_Y = ctx.layout.REF_QUALITY_Y
    local REF_STAT_BG_H = ctx.layout.REF_STAT_BG_H
    local REF_STAT_BG_Y0 = ctx.layout.REF_STAT_BG_Y0
    local REF_STAT_FONT = ctx.layout.REF_STAT_FONT
    local REF_STAT_GAP = ctx.layout.REF_STAT_GAP
    local REF_STAT_TEXT_X = ctx.layout.REF_STAT_TEXT_X
    local REF_STAT_VAL_X = ctx.layout.REF_STAT_VAL_X
    local REF_TYPE_FONT = ctx.layout.REF_TYPE_FONT
    local REF_TYPE_X = ctx.layout.REF_TYPE_X
    local REF_TYPE_Y = ctx.layout.REF_TYPE_Y
    local SET_GAP = ctx.layout.SET_GAP
    local SET_TITLE_H = ctx.layout.SET_TITLE_H

    --- 绘制单个装备面板（新装备或当前装备）
    ---@param vg any NanoVG 上下文
    ---@param equip table 装备实例
    ---@param offsetX number X轴偏移（相对于新装备面板参考坐标）
    ---@param bgCX number 背景中心X
    ---@param bgCY number 背景中心Y
    ---@param bgW number 背景宽
    ---@param bgH number 背景高
    ---@param powerDiff number|nil 战斗力差值（nil=不显示）
    ---@param showButton boolean 是否显示穿戴按钮
    ---@param btnText string 按钮文本
    ---@param showEnhanceOnly boolean|nil 仅显示前往洗练按钮（隐藏穿戴按钮）
    ---@param showLock boolean|nil 是否在名称右侧显示锁定图标（仅背包装备）
    ---@param showDecompose boolean|nil 是否在前往洗练按钮下方显示「立即分解」按钮（仅背包未穿戴装备）
    local function drawEquipPanel(vg, equip, offsetX, bgCX, bgCY, bgW, bgH, powerDiff, showButton, btnText, showEnhanceOnly, showLock, showDecompose)
        if not equip then return end
        local images = ctx.getImages()
        local imgPowerIcon, imgArrowUp, imgArrowDown = images.powerIcon, images.arrowUp, images.arrowDown
        local imgBtnGreen, imgBtnYellow, imgBtnRed = images.btnGreen, images.btnYellow, images.btnRed
        local imgLock, imgAffixBadge = images.lock, images.affixBadge

        local q = equip.quality or 1
        local qColor = QUALITY_COLOR[q] or QUALITY_COLOR[1]

        -- 1) 背景（坐标取整避免缝隙）[暗黑化 P1-B5] 矢量纯底板 + 品质语义描边
        local bgX = math.floor(bgCX - bgW * 0.5 + 0.5)
        local bgY = math.floor(bgCY - bgH * 0.5 + 0.5)
        DarkIcon.drawNine(vg, "plain",
            bgX, bgY, bgW, bgH,
            { accent = DarkIcon.QUALITY_TRIM[math.min(6, math.max(1, q))] })

        -- 战力组先实测，标题不能占用其图标/数值/箭头区域。
        local equipPower = calcEquipPower(equip, detState.heroId)
        local powerStr = require("core.NumberUtil").format(equipPower)
        local powerFont = REF_STAT_FONT
        local powerRight = bgX + bgW - 24
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, powerFont)
        local pwTextW = I18n.displayBounds(vg, 0, 0, powerStr)
        local powerIconSize = 44
        local arrowExtra = (powerDiff and powerDiff ~= 0) and (REF_ARROW_GAP + REF_ARROW_SIZE) or 0
        local powerValX = powerRight - arrowExtra - pwTextW
        local powerLeft = powerValX - 10 - powerIconSize
        local nameStr = I18n.lookup(equip.name or "???")
        local nameX = math.max(bgX + 24, REF_NAME_X + offsetX)
        local lockSize = showLock and imgLock >= 0 and 64 or 0
        local rows, nameFont, nameW = titleLayout(vg, nameStr, powerLeft - 20 - nameX,
            REF_NAME_FONT, 24, lockSize, 12, 4)
        local rowH = nameFont * 1.1
        local nameY = REF_NAME_Y - (#rows - 1) * rowH * 0.5
        for index, row in ipairs(rows) do
            -- 预折行译文直接绘制，不能对局部片段再次lookup。
            drawTitleRow(vg, nameX, nameY + (index - 1) * rowH, row, nameFont, 4)
        end

        if showLock then detState.lockHotspot = nil end
        if lockSize > 0 then
            local lockCX = nameX + nameW + 22 + lockSize * 0.5
            drawImageCentered(vg, imgLock, lockCX, REF_NAME_Y, lockSize, lockSize,
                equip.locked == true and 1.0 or 0.4)
            detState.lockHotspot = { cx = lockCX, cy = REF_NAME_Y,
                w = lockSize + 24, h = lockSize + 24 }
        end

        -- 3) 装备类型 - 左对齐 X578 Y706 字号30 纯白
        local typeName = equip.type or EquipmentConfig.SLOT_NAME[equip.slot] or ""
        local tpl = EquipmentConfig.ITEMS[equip.templateId]
            or EquipmentConfig.ITEMS[tostring(equip.templateId)]
        local setId = EquipmentSetConfig.getSetIdForTemplate(tpl)
        local setDef = setId and EquipmentSetConfig.get(setId) or nil
        if setDef then
            typeName = I18n.format("%s · %s", I18n.lookup(typeName), I18n.lookup(setDef.name))
        else
            typeName = I18n.lookup(typeName)
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, REF_TYPE_FONT)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, REF_TYPE_X + offsetX, REF_TYPE_Y, typeName, nil)

        -- 4) 品质文本 - 左对齐 X578 Y861 字号30 品质色 描边4
        local qualityDef = EquipmentConfig.QUALITY[q]
        local qualityName = I18n.lookup(qualityDef and qualityDef.name or "普通")
        drawTextStroke(vg, REF_QUALITY_X + offsetX, REF_QUALITY_Y, qualityName,
            REF_QUALITY_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            qColor[1], qColor[2], qColor[3], 4)

        -- 4.5) 等级 - 显示在稀有度下方 [UI 0930]
        drawTextStroke(vg, REF_QUALITY_X + offsetX, REF_QUALITY_Y + 48,
            "Lv." .. (equip.level or 1),
            REF_QUALITY_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)

        -- 5-7) 战斗力保留完整数值与比较箭头，位置使用上面的实测预算。
        drawImageCentered(vg, imgPowerIcon,
            powerValX - 10 - powerIconSize * 0.5, REF_NAME_Y,
            powerIconSize, powerIconSize, 1.0)
        drawTextStroke(vg, powerValX, REF_NAME_Y, powerStr,
            powerFont, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            0xf7, 0xfe, 0x77, 4)
        if powerDiff and powerDiff ~= 0 then
            local arrowCX = powerValX + pwTextW + REF_ARROW_GAP + REF_ARROW_SIZE * 0.5
            if powerDiff > 0 then
                drawImageCentered(vg, imgArrowUp, arrowCX, REF_NAME_Y,
                    REF_ARROW_SIZE, REF_ARROW_SIZE, 1.0)
            else
                drawImageCentered(vg, imgArrowDown, arrowCX, REF_NAME_Y,
                    REF_ARROW_SIZE, REF_ARROW_SIZE, 1.0)
            end
        end

        -- 8) 装备图标 - X903 Y809 290*290
        local iconCX = REF_ICON_CX + offsetX
        local iconCY = REF_ICON_CY
        local equipIconImg = getEquipIcon(equip.templateId)
        if equipIconImg >= 0 then
            DarkIcon.drawIconDark(vg, equipIconImg, iconCX, iconCY, REF_ICON_SIZE, REF_ICON_SIZE, 1.0)  -- [暗黑化 P2-B]
        else
            -- 无图标时回退为占位框+文字
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconCX - REF_ICON_SIZE * 0.5, iconCY - REF_ICON_SIZE * 0.5,
                REF_ICON_SIZE, REF_ICON_SIZE, 20)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 25))
            nvgFill(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 48)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(qColor[1], qColor[2], qColor[3], 180))
            local fallbackName = I18n.lookup(equip.name or "?")
            local thirdChar = utf8.offset(fallbackName, 3)
            local shortName = thirdChar and fallbackName:sub(1, thirdChar - 1) or fallbackName
            nvgText(vg, iconCX, iconCY, shortName, nil)
        end

        -- 8.5) 升阶角标（右上角，跟着这件装备）
        local slotLv = EquipmentSystem.getAscendLevel(equip)
        if slotLv > 0 then
            local enhText = "+" .. slotLv
            local enhX = iconCX + REF_ICON_SIZE * 0.5 - 12
            local enhY = iconCY - REF_ICON_SIZE * 0.5 - 4
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 48)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            -- 黑色描边 16方向
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            local sStep = math.pi * 2 / 16
            for si = 0, 15 do
                local sa = si * sStep
                nvgText(vg, enhX + math.cos(sa) * 4, enhY + math.sin(sa) * 4, enhText, nil)
            end
            -- 绿色填充
            nvgFillColor(vg, nvgRGBA(0x00, 0xff, 0x60, 255))
            nvgText(vg, enhX, enhY, enhText, nil)
        end

        EquipmentSetIcon.drawBadge(vg, equip, iconCX, iconCY, REF_ICON_SIZE, 1.0)

        -- 11-14) 基础属性 + 词缀：超出框内可视区时下滚
        local pinnedCY, scrollMax = layoutButtons(equip)
        detState.descScrollMax = scrollMax
        clampDescScroll()
        local descH = math.max(80, pinnedCY - 56 - DESC_TOP)
        nvgSave(vg)
        nvgIntersectScissor(vg, bgX, DESC_TOP, bgW, descH)
        nvgTranslate(vg, 0, -detState.descScrollY)

        if equip.baseStats and #equip.baseStats > 0 then
            local ascendBoost = EquipmentSystem.getAscendBoost(equip)
            for i, s in ipairs(equip.baseStats) do
                local statCY = REF_STAT_BG_Y0 + (i - 1) * (REF_STAT_BG_H + REF_STAT_GAP)

                -- 11) 属性行：不要底色阴影，只留文字
                local sName = getStatName(s[1])
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, REF_STAT_FONT)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
                nvgText(vg, REF_STAT_TEXT_X + offsetX, statCY, sName, nil)

                -- 属性值含装备升阶加成
                local rawVal = EquipmentSystem.effectiveBaseStatValue(equip, i, ascendBoost)
                local sVal = EquipmentSystem.formatBaseStatValue(s[1], rawVal)
                drawTextStroke(vg, REF_STAT_VAL_X + offsetX, statCY, sVal,
                    REF_STAT_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 4)
            end
        end

        -- 15-18) 随机属性（词缀）
        if equip.affixes and #equip.affixes > 0 then
            -- 15) "随机属性" 标题 - 左对齐 X578 Y1206 字号30 颜色918f88
            -- 标题Y根据基础属性数量动态偏移
            local baseStatCount = equip.baseStats and #equip.baseStats or 0
            local affixTitleY = REF_AFFIX_TITLE_Y
            -- 如果基础属性数量不同，调整Y位置（以2条为基准）
            if baseStatCount ~= 0 then
                local baseStatEndY = REF_STAT_BG_Y0 + (baseStatCount - 1) * (REF_STAT_BG_H + REF_STAT_GAP) + REF_STAT_BG_H * 0.5
                -- 标题在最后一条基础属性下方留一定间距
                local minGap = 30
                if affixTitleY < baseStatEndY + minGap then
                    affixTitleY = baseStatEndY + minGap
                end
            end

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, REF_AFFIX_TITLE_FONT)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0x91, 0x8f, 0x88, 255))
            nvgText(vg, REF_AFFIX_TITLE_X + offsetX, affixTitleY, "随机属性", nil)

            -- 词缀行起始Y：标题底部 + 15px + 行高一半
            local firstAffixY = affixTitleY + REF_AFFIX_TITLE_FONT * 0.5 + REF_AFFIX_GAP_TOP + REF_AFFIX_ROW_H * 0.5

            for i, affix in ipairs(equip.affixes) do
                local affixY = firstAffixY + (i - 1) * (REF_AFFIX_ROW_H + REF_AFFIX_GAP)
                local isCorrupt = AffixConfig.isCorruptAffix(affix)
                local aq = affix.quality or 1
                local badgeKey = AFFIX_BADGE_KEY[aq] or "D"
                local badgeImg = imgAffixBadge[badgeKey] or -1

                -- 词缀行不铺底色阴影
                if isCorrupt then
                    local r = math.min(REF_BADGE_W, REF_BADGE_H) * 0.28
                    nvgBeginPath(vg)
                    nvgCircle(vg, REF_BADGE_CX + offsetX, affixY, r)
                    nvgFillColor(vg, nvgRGBA(0x9B, 0x4D, 0xFF, 255))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgCircle(vg, REF_BADGE_CX + offsetX, affixY, r)
                    nvgStrokeWidth(vg, 2)
                    nvgStrokeColor(vg, nvgRGBA(0xE0, 0xB0, 0xFF, 220))
                    nvgStroke(vg)
                elseif badgeImg >= 0 then
                    drawImageCentered(vg, badgeImg,
                        REF_BADGE_CX + offsetX, affixY,
                        REF_BADGE_W, REF_BADGE_H, 1.0)
                end

                -- 16) 词缀名称 - 左对齐 X636 字号34 颜色725850（与基础属性相同）
                local affName = I18n.lookup(affix.name or "?")
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, REF_STAT_FONT)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(0xE8, 0xC8, 0x6A, 255))
                nvgText(vg, REF_AFFIX_TEXT_X + offsetX, affixY, affName, nil)

                -- 升阶副属性加成标记（金色小字"升阶"，ascBonus>0 时显示）
                local ascB = tonumber(affix.ascBonus) or 0
                if ascB > 0 and not isCorrupt then
                    local nameW = nvgTextBounds(vg, 0, 0, affName) or 0
                    nvgFontSize(vg, 22)
                    nvgFillColor(vg, nvgRGBA(0xC9, 0x97, 0x3B, 235))
                    nvgText(vg, REF_AFFIX_TEXT_X + offsetX + nameW + 8, affixY, "升阶", nil)
                end

                -- 词缀数值 - 右对齐 X1016 字号34 白色 描边4（与基础属性相同；生效值含栏位倍率）
                local affVal = "+" .. formatStatValue(affix.key, EquipmentSystem.effectiveAffixValue(equip, affix))
                drawTextStroke(vg, REF_STAT_VAL_X + offsetX, affixY, affVal,
                    REF_STAT_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 4)
            end
        end

        nvgRestore(vg)

        -- 19-20) 穿戴按钮钉在框内，说明超出部分用滚动看
        if showButton then
            local btnCY = pinnedCY
            if not showEnhanceOnly then
                -- 19) 按钮背景 UI_AN_LV.png - X807 Y1461 410*100
                local _bf1 = BF.begin(vg, "ed_equip", REF_BTN_CX + offsetX, btnCY, REF_BTN_W, REF_BTN_H)
                drawImageCentered(vg, imgBtnGreen,
                    REF_BTN_CX + offsetX, btnCY,
                    REF_BTN_W, REF_BTN_H, 1.0)

                -- 20) 穿戴按钮文字 - 正中央 字号40 金黄
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, REF_BTN_FONT)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 214, 102, 255))
                nvgText(vg, REF_BTN_CX + offsetX, btnCY, btnText, nil)
                BF.finish(vg, _bf1)
                local _TM = require("systems.TutorialManager")
                if _TM.isActive() then _TM.registerHotspot("equip_btn_equip", REF_BTN_CX + offsetX, btnCY, REF_BTN_W, REF_BTN_H, "right") end
            end

            -- 21-22) 前往洗练按钮（仅铁匠铺已解锁时显示）
            if TutorialManager.isBuildingUnlocked("smith") then
                local enhBtnCY
                if showEnhanceOnly then
                    -- 背包模式：前往洗练按钮顶替穿戴按钮的位置
                    enhBtnCY = btnCY
                else
                    enhBtnCY = bgCY + bgH * 0.5 + REF_ENH_BTN_GAP + REF_ENH_BTN_H * 0.5
                end
                local _bf2 = BF.begin(vg, "ed_enhance", REF_BTN_CX + offsetX, enhBtnCY, REF_ENH_BTN_W, REF_ENH_BTN_H)
                drawImageCentered(vg, imgBtnYellow,
                    REF_BTN_CX + offsetX, enhBtnCY,
                    REF_ENH_BTN_W, REF_ENH_BTN_H, 1.0)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, REF_ENH_BTN_FONT)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(244, 237, 224, 255))
                nvgText(vg, REF_BTN_CX + offsetX, enhBtnCY, "强化", nil)
                BF.finish(vg, _bf2)

                -- 23-24) 立即分解按钮（背包未穿戴装备，前往洗练下方）
                if showDecompose then
                    local decBtnCY = enhBtnCY + REF_ENH_BTN_H * 0.5 + REF_DEC_BTN_GAP + REF_ENH_BTN_H * 0.5
                    local _bf3 = BF.begin(vg, "ed_decompose", REF_BTN_CX + offsetX, decBtnCY, REF_ENH_BTN_W, REF_ENH_BTN_H)
                    drawImageCentered(vg, imgBtnRed,
                        REF_BTN_CX + offsetX, decBtnCY,
                        REF_ENH_BTN_W, REF_ENH_BTN_H, 1.0)
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, REF_ENH_BTN_FONT)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(244, 237, 224, 255))
                    nvgText(vg, REF_BTN_CX + offsetX, decBtnCY, "立即分解", nil)
                    BF.finish(vg, _bf3)
                    local slot = equip.slot
                    local field = slot and BlacksmithConfig.SLOT_SCROLL_MAP[slot]
                    local refund = field and BlacksmithConfig.calcAscendScrollRefund(
                        EquipmentSystem.getAscendLevel(equip)) or 0
                    if refund > 0 and field then
                        local hint = BlacksmithConfig.formatScrollRefund({ [field] = refund })
                        if hint then
                            hint = I18nEquipmentText.lookup(hint, I18n.get()) or hint
                            drawTextStroke(vg, REF_BTN_CX + offsetX,
                                decBtnCY + REF_ENH_BTN_H * 0.5 + 28, hint,
                                28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                                255, 214, 102, 3)
                        end
                    end
                end
            end
        end
    end

    --- 配装小窗：套装说明独立于属性和词条，按钮贴在套装区后方。
    ---@param vg any
    ---@param equip table
    ---@param btnText string
    ---@param showActions boolean|nil
    local function drawCompactPanel(vg, equip, btnText, showActions)
        local images = ctx.getImages()
        local imgPowerIcon, imgArrowUp, imgArrowDown = images.powerIcon, images.arrowUp, images.arrowDown
        local imgBtnGreen, imgBtnYellow, imgBtnRed = images.btnGreen, images.btnYellow, images.btnRed
        local imgLock, imgAffixBadge = images.lock, images.affixBadge
        local q = equip.quality or 1
        local qColor = QUALITY_COLOR[q] or QUALITY_COLOR[1]
        local panelW = COMPACT_BG_W
        local panelH = compactViewHeight(equip, showActions ~= false)
        local panelX = REF_BG_CX - panelW * 0.5
        local leftX = panelX + COMPACT_PAD_TOP
        local rightX = panelX + panelW - COMPACT_PAD_TOP
        DarkIcon.drawNine(vg, "plain", panelX, 0, panelW, panelH,
            { accent = DarkIcon.QUALITY_TRIM[math.min(6, math.max(1, q))] })
        if showActions ~= false then detState.lockHotspot = nil end

        -- 先给战力图标和完整数值留位，再测量标题（锁图标和热区计入同一预算）。
        local powerStr = require("core.NumberUtil").format(calcEquipPower(equip, detState.heroId))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 36)
        local powerW = I18n.displayBounds(vg, 0, 0, powerStr)
        local powerIconSize = 36
        local powerX = rightX - powerW
        local powerLeft = powerX - 12 - powerIconSize
        local nameStr = I18n.lookup(equip.name or "???")
        local lockSize = imgLock >= 0 and 36 or 0
        local rows, nameFont, nameW = titleLayout(vg, nameStr, powerLeft - 18 - leftX,
            44, 24, lockSize, 10, 3)
        local rowH = nameFont * 1.1
        local nameY = COMPACT_NAME_Y - (#rows - 1) * rowH * 0.5
        for index, row in ipairs(rows) do
            drawTitleRow(vg, leftX, nameY + (index - 1) * rowH, row, nameFont, 3)
        end
        if lockSize > 0 then
            local lockCX = leftX + nameW + 19 + lockSize * 0.5
            drawImageCentered(vg, imgLock, lockCX, COMPACT_NAME_Y, lockSize, lockSize,
                equip.locked and 1.0 or 0.4)
            if showActions ~= false then
                detState.lockHotspot = { cx = lockCX, cy = COMPACT_NAME_Y, w = lockSize + 20, h = lockSize + 20 }
            end
        end

        local typeName = I18n.lookup(equip.type or EquipmentConfig.SLOT_NAME[equip.slot] or "")
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 26)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, leftX, COMPACT_TYPE_Y, typeName, nil)

        local qualityDef = EquipmentConfig.QUALITY[q]
        drawTextStroke(vg, leftX, COMPACT_QUALITY_Y, I18n.lookup(qualityDef and qualityDef.name or "普通"), 28,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, qColor[1], qColor[2], qColor[3], 3)

        -- [UI 0930] 等级显示在稀有度下方
        drawTextStroke(vg, leftX, COMPACT_QUALITY_Y + 40, "Lv." .. tostring(equip.level or 1), 28,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)

        local iconCX = panelX + panelW - 96
        local icon = getEquipIcon(equip.templateId)
        if icon >= 0 then
            DarkIcon.drawIconDark(vg, icon, iconCX, COMPACT_ICON_CY, COMPACT_ICON_SIZE, COMPACT_ICON_SIZE, 1.0)
        end
        local ascend = EquipmentSystem.getAscendLevel(equip)
        if ascend > 0 then
            drawTextStroke(vg, iconCX + 48, COMPACT_ICON_CY - 52 - 28 / 3, "+" .. ascend, 28,
                NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, 0, 255, 96, 3)
        end

        EquipmentSetIcon.drawBadge(vg, equip, iconCX, COMPACT_ICON_CY, COMPACT_ICON_SIZE, 1.0)

        drawImageCentered(vg, imgPowerIcon, powerX - 12 - powerIconSize * 0.5, COMPACT_NAME_Y,
            powerIconSize, powerIconSize, 1.0)
        drawTextStroke(vg, powerX, COMPACT_NAME_Y, powerStr, 36,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 0xf7, 0xfe, 0x77, 3)

        local bottom = COMPACT_QUALITY_Y + 18
        if equip.baseStats and #equip.baseStats > 0 then
            local boost = EquipmentSystem.getAscendBoost(equip)
            for i, stat in ipairs(equip.baseStats) do
                local y = COMPACT_STAT_Y0 + (i - 1) * (REF_STAT_BG_H + REF_STAT_GAP)
                local raw = EquipmentSystem.effectiveBaseStatValue(equip, i, boost)
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 36)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
                nvgText(vg, leftX, y, getStatName(stat[1]), nil)
                drawTextStroke(vg, rightX, y, EquipmentSystem.formatBaseStatValue(stat[1], raw), 36,
                    NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
                bottom = y + REF_STAT_BG_H * 0.5
            end
        end
        if equip.affixes and #equip.affixes > 0 then
            local firstY = bottom + 16 + REF_AFFIX_ROW_H * 0.5
            for i, affix in ipairs(equip.affixes) do
                local y = firstY + (i - 1) * (REF_AFFIX_ROW_H + 8)
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 36)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(0xE8, 0xC8, 0x6A, 255))
                local cName = I18n.lookup(affix.name or "?")
                nvgText(vg, leftX, y, cName, nil)
                -- 升阶副属性加成标记（金色小字"升阶"，ascBonus>0 时显示）
                local cAscB = tonumber(affix.ascBonus) or 0
                if cAscB > 0 and not AffixConfig.isCorruptAffix(affix) then
                    local cNameW = nvgTextBounds(vg, 0, 0, cName) or 0
                    nvgFontSize(vg, 20)
                    nvgFillColor(vg, nvgRGBA(0xC9, 0x97, 0x3B, 235))
                    nvgText(vg, leftX + cNameW + 6, y, "升阶", nil)
                end
                drawTextStroke(vg, rightX, y, "+" .. formatStatValue(affix.key, EquipmentSystem.effectiveAffixValue(equip, affix)), 36,
                    NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
                bottom = y + REF_AFFIX_ROW_H * 0.5
            end
        end

        local setDef, setLines = compactSetLines(equip)
        if #setLines > 0 then
            local sectionTop = compactContentBottom(equip) + SET_GAP
            local col = setDef.color or { 232, 208, 122, 255 }
            local sectionH = SET_TITLE_H + 4
            for i = 2, #setLines do
                sectionH = sectionH + compactSetRowHeight(setLines[i])
            end
            nvgBeginPath(vg)
            nvgRoundedRect(vg, leftX - 10, sectionTop, panelW - 36, sectionH, 12)
            nvgFillColor(vg, nvgRGBA(12, 10, 8, 200))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(col[1], col[2], col[3], 110))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 30)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
            nvgText(vg, leftX + 8, sectionTop + 22, setLines[1].text, nil)
            local rowTop = sectionTop + SET_TITLE_H
            local mainPanel = (showActions ~= false)  -- 仅主面板关键词可点（对比/只读预览不交互）
            for i = 2, #setLines do
                local line = setLines[i]
                local tier = I18n.format("%d件  ", line.tier)
                local desc = line.desc
                nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], line.active and 255 or 185))
                nvgFontSize(vg, 26)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgText(vg, leftX + 8, rowTop + 2, tier or "", nil)
                if mainPanel then
                    local kw = setKw[i - 1]
                    if line.active then
                        kw.textColor = { 244, 237, 224, 255 }
                    else
                        kw.textColor = { 170, 158, 140, 210 }
                    end
                    kw:draw(vg, desc, leftX + 78, rowTop + 2, panelW - 130, 26, 32)
                else
                    nvgFillColor(vg, line.active and nvgRGBA(244, 237, 224, 255)
                        or nvgRGBA(170, 158, 140, 210))
                    nvgFontSize(vg, 26)
                    nvgTextBox(vg, leftX + 78, rowTop + 2, panelW - 130, I18n.lookup(desc), nil)
                end
                rowTop = rowTop + compactSetRowHeight(line)
            end
        end

        if showActions == false then return end
        local smithOn = TutorialManager.isBuildingUnlocked("smith")
        local showWear = detState.slot ~= nil
        local wearCY, refineCY, cx, bw, bh = compactButtonRow()
        if showWear then
            local feedback = BF.begin(vg, "ed_equip", cx, wearCY, bw, bh)
            drawImageCentered(vg, imgBtnGreen, cx, wearCY, bw, bh, 1.0)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 30)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 214, 102, 255))
            nvgText(vg, cx, wearCY, btnText, nil)
            BF.finish(vg, feedback)
        end
        if smithOn then
            local feedback = BF.begin(vg, "ed_enhance", cx, refineCY, bw, bh)
            drawImageCentered(vg, imgBtnYellow, cx, refineCY, bw, bh, 1.0)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 30)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 214, 102, 255))
            nvgText(vg, cx, refineCY, "强化", nil)
            BF.finish(vg, feedback)
        end
    end

    return { drawEquipPanel = drawEquipPanel, drawCompactPanel = drawCompactPanel }
end

return EquipmentDetailDraw
