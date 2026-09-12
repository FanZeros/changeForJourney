-- ============================================================================
-- ArtifactDetailPanel - 神器详情弹窗
-- 复用遗物详情弹窗的布局和交互风格，展示神器信息与装备/取下操作
-- 坐标系: 设计分辨率 1080x2400
-- ============================================================================

local DrawUtil          = require("core.DrawUtil")
local drawTextStroke    = DrawUtil.drawTextStroke
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest
local BF                = require("systems.ButtonFeedback")
local ArtifactDefs      = require("shared.artifact.ArtifactDefs")
local ImageCache        = require("ui.ImageCache")
local ArtifactAssetUtil   = require("config.ArtifactAssetUtil")

local ArtifactDetailPanel = {}

-- ======================== 动画常量 ========================

local ANIM_OPEN_DUR  = 0.25
local ANIM_CLOSE_DUR = 0.18

local function easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 布局常量 ========================

local BG = {
    CX = 540, CY = 1146,
    W  = 530, H  = 894,
    IT = 400, IR = 93, IB = 93, IL = 93,
}

local NAME = {
    X = 316, Y = 759,
    FONT = 40,
    STROKE = 4,
}

local TYPE_LABEL = {
    X = 316, Y = 840,
    FONT = 30,
}

local QUALITY = {
    X = 316, Y = 995,
    FONT = 30,
    STROKE = 4,
    STROKE_R = 0x28, STROKE_G = 0x28, STROKE_B = 0x28,
}

local POWER = {
    ICON_X = 316, ICON_Y = 1051,
    ICON_W = 40, ICON_H = 40,
    TEXT_X = 360, TEXT_Y = 1051,
    FONT = 30,
    TEXT_R = 0xf7, TEXT_G = 0xfe, TEXT_B = 0x77,
    STROKE = 4,
    STROKE_R = 0x23, STROKE_G = 0x23, STROKE_B = 0x23,
}

local EFFECT_LABEL = {
    Y = 1129,
    FONT = 34,
    R = 0x91, G = 0x8f, B = 0x88,
}

local DESC_BG = {
    CX = 540, CY = 1283,
    W = 460, H = 250,
    R = 14,
    FILL_R = 0, FILL_G = 0, FILL_B = 0, FILL_A = 13,
}

local DESC_TEXT = {
    PADDING = 30,
    FONT = 28,
    LINE_H = 36,
    R = 0x72, G = 0x58, B = 0x50,
    HIGHLIGHT_R = 0xf6, HIGHLIGHT_G = 0x85, HIGHLIGHT_B = 0x00,
    RATIO_R = 0x99, RATIO_G = 0x92, RATIO_B = 0x8a,
}

local ARTIFACT_ICON = {
    CX = 629, CY = 943,
    W = 220, H = 220,
}

local BTN_EQUIP = {
    CX = 408, CY = 1496,
    W = 210, H = 100,
    NP_T = 15, NP_R = 60, NP_B = 15, NP_L = 60,
    FONT = 38,
    TEXT_R = 0, TEXT_G = 0, TEXT_B = 0, TEXT_A = 191,
}

local BTN_REFINE = {
    CX = 672, CY = 1496,
    W = 250, H = 100,
    NP_T = 15, NP_R = 60, NP_B = 15, NP_L = 60,
    FONT = 34,
    TEXT_R = 0, TEXT_G = 0, TEXT_B = 0, TEXT_A = 191,
}

local REFINE_COST = {
    X = 672, Y = 1564,
    FONT = 24,
    R = 0x72, G = 0x58, B = 0x50,
}

-- ======================== 图片资源 ========================

local imgBg        = {}
local imgBtnLv     = -1
local imgPowerIcon = -1

-- ======================== 状态 ========================

local state = {
    visible   = false,
    opening   = false,
    closing   = false,
    openTime  = 0,
    closeTime = 0,
    artifact  = nil,
    location  = "bag",
    slot      = nil,
    subSlot   = nil,
}

local onEquipCallback_ = nil
local onRefineCallback_ = nil
local onCloseCallback_ = nil

-- ======================== 辅助 ========================

local function getArtifactPower(artifact)
    if not artifact then return 0 end
    return ArtifactDefs.getPower(artifact)
end

local function drawArtifactIcon(vg, artifact, cx, cy, size)
    ArtifactAssetUtil.drawIcon(vg, artifact, cx, cy, size, {
        iconPadding = math.max(16, math.floor(size * 0.1)),
        hideQualityBg = true,
    })
end

local function getArtifactDef(artifact)
    if not artifact then return nil end
    local ids = {
        artifact.artifactId,
        artifact.defId,
        artifact.type,
        artifact.templateId,
        artifact.id,
    }
    for _, id in ipairs(ids) do
        local def = ArtifactDefs.get(id)
        if def then return def end
    end
    if artifact.name then
        for _, def in pairs(ArtifactDefs.ARTIFACTS or {}) do
            if def.name == artifact.name then return def end
        end
    end
    return nil
end

local function getEffectText(artifact)
    if not artifact then return "" end
    local explicit = artifact.effectText or artifact.desc or artifact.description
    if explicit and explicit ~= "" then
        return tostring(explicit)
    end
    return ArtifactDefs.getEffectText(artifact)
end

local function formatRefineRatio(ratio)
    ratio = math.max(0, math.min(10000, math.floor(tonumber(ratio) or 0)))
    return string.format("%.1f%%", ratio / 100)
end

local function getMainValueRatio(artifact)
    if not artifact then return nil end
    local ratio = artifact.valueRatio
    if ratio == nil and artifact.value ~= nil then
        ratio = ArtifactDefs.valueToRatio(artifact.artifactId or artifact.id, tonumber(artifact.quality) or 1, artifact.value)
    end
    if ratio == nil then return nil end
    return math.max(0, math.min(10000, math.floor(tonumber(ratio) or 0)))
end

local function getThreatClearRatio(artifact)
    if not artifact then return nil end
    local ratio = artifact.threatClearRatio
    if ratio == nil then
        local threatClearValue = ArtifactDefs.getThreatClearValue and ArtifactDefs.getThreatClearValue(artifact) or nil
        if threatClearValue ~= nil and ArtifactDefs.threatClearValueToRatio then
            ratio = ArtifactDefs.threatClearValueToRatio(artifact.artifactId or artifact.id, tonumber(artifact.quality) or 1, threatClearValue)
        end
    end
    if ratio == nil then return nil end
    return math.max(0, math.min(10000, math.floor(tonumber(ratio) or 0)))
end

local function canRefineArtifact(artifact)
    local mainRatio = getMainValueRatio(artifact)
    local threatClearRatio = getThreatClearRatio(artifact)
    if mainRatio and mainRatio < 10000 then return true end
    if threatClearRatio and threatClearRatio < 10000 then return true end
    return false
end

local function appendRatioAfterFirst(text, valueText, ratioText)
    if not text or text == "" or not valueText or valueText == "" or not ratioText then return text end
    local s, e = tostring(text):find(tostring(valueText), 1, true)
    if not s then return text end
    return text:sub(1, e) .. "（" .. ratioText .. "）" .. text:sub(e + 1)
end

local function getEffectTextWithRatios(artifact)
    local text = getEffectText(artifact)
    if not artifact or text == "" then return text end
    local valueText = ArtifactDefs.formatValue(artifact.value)
    local mainRatio = getMainValueRatio(artifact)
    if mainRatio ~= nil then
        text = appendRatioAfterFirst(text, valueText, formatRefineRatio(mainRatio))
    end
    local threatClearValue = ArtifactDefs.getThreatClearValue and ArtifactDefs.getThreatClearValue(artifact) or nil
    local threatClearRatio = getThreatClearRatio(artifact)
    if threatClearValue ~= nil and threatClearRatio ~= nil then
        text = appendRatioAfterFirst(text, ArtifactDefs.formatValue(threatClearValue), formatRefineRatio(threatClearRatio))
    end
    return text
end

local function drawWrappedText(vg, x, y, maxW, text, fontSize, lineH, r, g, b, highlightText)
    text = tostring(text or "")
    if text == "" then return end
    local highlights = {}
    if type(highlightText) == "table" then
        for _, h in ipairs(highlightText) do
            if h and h ~= "" then highlights[#highlights + 1] = tostring(h) end
        end
    elseif highlightText and highlightText ~= "" then
        highlights[1] = tostring(highlightText)
    end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))

    local chars = {}
    local i = 1
    local len = #text
    while i <= len do
        local b0 = string.byte(text, i)
        local charLen = 1
        if b0 >= 0xF0 then
            charLen = 4
        elseif b0 >= 0xE0 then
            charLen = 3
        elseif b0 >= 0xC0 then
            charLen = 2
        end
        chars[#chars + 1] = string.sub(text, i, i + charLen - 1)
        i = i + charLen
    end

    local lineY = y
    local lineStart = 1
    while lineStart <= #chars do
        if chars[lineStart] == "\n" then
            lineY = lineY + lineH
            lineStart = lineStart + 1
        else
            local lineEnd = lineStart
            for ci = lineStart, #chars do
                if chars[ci] == "\n" then
                    lineEnd = ci - 1
                    break
                end
                local sub = table.concat(chars, "", lineStart, ci)
                local tw = nvgTextBounds(vg, 0, 0, sub)
                if tw > maxW and ci > lineStart then
                    lineEnd = ci - 1
                    break
                end
                lineEnd = ci
            end
            if lineEnd >= lineStart then
                local lineStr = table.concat(chars, "", lineStart, lineEnd)
                if #highlights > 0 then
                    local hs, he = nil, nil
                    for _, h in ipairs(highlights) do
                        local s, e = lineStr:find(h, 1, true)
                        if s and (not hs or s < hs) then
                            hs, he = s, e
                        end
                    end
                    if hs then
                        local before = lineStr:sub(1, hs - 1)
                        local mid = lineStr:sub(hs, he)
                        local after = lineStr:sub(he + 1)
                        local ratioPrefix, ratioMid, ratioSuffix = mid:match("^(.-)(（[%d%.]+%%）)(.*)$")
                        local curX = x
                        nvgFillColor(vg, nvgRGBA(r, g, b, 255))
                        if before ~= "" then
                            nvgText(vg, curX, lineY, before, nil)
                            curX = curX + nvgTextBounds(vg, 0, 0, before)
                        end
                        nvgFillColor(vg, nvgRGBA(DESC_TEXT.HIGHLIGHT_R, DESC_TEXT.HIGHLIGHT_G, DESC_TEXT.HIGHLIGHT_B, 255))
                        if ratioMid then
                            if ratioPrefix ~= "" then
                                nvgText(vg, curX, lineY, ratioPrefix, nil)
                                curX = curX + nvgTextBounds(vg, 0, 0, ratioPrefix)
                            end
                            nvgFillColor(vg, nvgRGBA(DESC_TEXT.RATIO_R, DESC_TEXT.RATIO_G, DESC_TEXT.RATIO_B, 255))
                            nvgText(vg, curX, lineY, ratioMid, nil)
                            curX = curX + nvgTextBounds(vg, 0, 0, ratioMid)
                            if ratioSuffix ~= "" then
                                nvgFillColor(vg, nvgRGBA(DESC_TEXT.HIGHLIGHT_R, DESC_TEXT.HIGHLIGHT_G, DESC_TEXT.HIGHLIGHT_B, 255))
                                nvgText(vg, curX, lineY, ratioSuffix, nil)
                                curX = curX + nvgTextBounds(vg, 0, 0, ratioSuffix)
                            end
                        else
                            nvgText(vg, curX, lineY, mid, nil)
                            curX = curX + nvgTextBounds(vg, 0, 0, mid)
                        end
                        nvgFillColor(vg, nvgRGBA(r, g, b, 255))
                        if after ~= "" then
                            nvgText(vg, curX, lineY, after, nil)
                        end
                    else
                        nvgFillColor(vg, nvgRGBA(r, g, b, 255))
                        nvgText(vg, x, lineY, lineStr, nil)
                    end
                else
                    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
                    nvgText(vg, x, lineY, lineStr, nil)
                end
            end
            lineY = lineY + lineH
            lineStart = lineEnd + 1
        end
    end
end

local function internalUpdate()
    if not state.visible then return end
    local now = time.elapsedTime

    if state.opening then
        local elapsed = now - state.openTime
        if elapsed >= ANIM_OPEN_DUR then
            state.opening = false
        end
    elseif state.closing then
        local elapsed = now - state.closeTime
        if elapsed >= ANIM_CLOSE_DUR then
            state.closing = false
            state.visible = false
            state.artifact = nil
            state.location = "bag"
            state.slot = nil
            state.subSlot = nil
            if onCloseCallback_ then onCloseCallback_() end
        end
    end
end

-- ======================== Public API ========================

function ArtifactDetailPanel.init(vg)
    ImageCache.init(vg)
    for i = 1, 6 do
        imgBg[i] = nvgCreateImage(vg, "image/UI_ZBTS_" .. i .. ".png", 0)
    end
    imgBtnLv = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    imgPowerIcon = nvgCreateImage(vg, "image/ICON_ZDL.png", 0)
    print("[ArtifactDetailPanel] init OK")
end

---@param artifact table 神器实例
---@param location string|nil "bag" 或 "slot"
---@param slot number|nil 已装配槽位
---@param subSlot number|nil 已装配子格
function ArtifactDetailPanel.show(artifact, location, slot, subSlot)
    if not artifact then return end
    state.artifact = artifact
    state.location = location or "bag"
    state.slot = slot
    state.subSlot = subSlot
    state.visible = true
    state.opening = true
    state.closing = false
    state.openTime = time.elapsedTime
end

function ArtifactDetailPanel.hide()
    if not state.visible then return end
    state.closing = true
    state.opening = false
    state.closeTime = time.elapsedTime
end

function ArtifactDetailPanel.isVisible()
    return state.visible
end

function ArtifactDetailPanel.refreshArtifact(artifact)
    if state.visible and artifact then
        state.artifact = artifact
    end
end

function ArtifactDetailPanel.setOnEquip(fn)
    onEquipCallback_ = fn
end

function ArtifactDetailPanel.setOnRefine(fn)
    onRefineCallback_ = fn
end

function ArtifactDetailPanel.setOnClose(fn)
    onCloseCallback_ = fn
end

function ArtifactDetailPanel.update(_dt)
end

function ArtifactDetailPanel.draw(vg)
    if not state.visible or not state.artifact then return end

    internalUpdate()
    if not state.visible or not state.artifact then return end

    local artifact = state.artifact
    local now = time.elapsedTime
    local progress = 1.0
    if state.opening then
        local t = math.min((now - state.openTime) / ANIM_OPEN_DUR, 1.0)
        progress = easeOutCubic(t)
    elseif state.closing then
        local t = math.min((now - state.closeTime) / ANIM_CLOSE_DUR, 1.0)
        progress = 1.0 - easeInCubic(t)
    end

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * progress)))
    nvgFill(vg)

    local scale = 0.8 + 0.2 * progress
    nvgSave(vg)
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -BG.CX, -BG.CY)
    nvgGlobalAlpha(vg, progress)

    local q = math.max(1, math.min(tonumber(artifact.quality) or 1, 6))
    local bgImg = imgBg[q] or imgBg[1]
    drawNineSlice(vg, bgImg,
        BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5,
        BG.W, BG.H,
        BG.IT, BG.IR, BG.IB, BG.IL)

    drawArtifactIcon(vg, artifact, ARTIFACT_ICON.CX, ARTIFACT_ICON.CY, ARTIFACT_ICON.W)

    local artifactName = ArtifactDefs.getName(artifact)
    drawTextStroke(vg, NAME.X, NAME.Y, artifactName,
        NAME.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, NAME.STROKE)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TYPE_LABEL.FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, TYPE_LABEL.X, TYPE_LABEL.Y, "神器", nil)

    local qualityName = ArtifactDefs.getQualityName(q)
    local qc = ArtifactDefs.getQualityColor(q)
    drawTextStroke(vg, QUALITY.X, QUALITY.Y, qualityName,
        QUALITY.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        qc[1], qc[2], qc[3], QUALITY.STROKE,
        { strokeColor = { QUALITY.STROKE_R, QUALITY.STROKE_G, QUALITY.STROKE_B } })

    local powerStr = tostring(getArtifactPower(artifact))
    if imgPowerIcon >= 0 then
        DrawUtil.drawImageCentered(vg, imgPowerIcon,
            POWER.ICON_X + POWER.ICON_W * 0.5,
            POWER.ICON_Y,
            POWER.ICON_W, POWER.ICON_H, 1.0)
    end
    drawTextStroke(vg, POWER.TEXT_X, POWER.TEXT_Y, powerStr,
        POWER.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        POWER.TEXT_R, POWER.TEXT_G, POWER.TEXT_B, POWER.STROKE,
        { strokeColor = { POWER.STROKE_R, POWER.STROKE_G, POWER.STROKE_B } })

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, EFFECT_LABEL.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(EFFECT_LABEL.R, EFFECT_LABEL.G, EFFECT_LABEL.B, 255))
    nvgText(vg, BG.CX, EFFECT_LABEL.Y, "神器效果", nil)

    DrawUtil.drawRoundedRectCentered(vg,
        DESC_BG.CX, DESC_BG.CY,
        DESC_BG.W, DESC_BG.H,
        DESC_BG.R,
        DESC_BG.FILL_R, DESC_BG.FILL_G, DESC_BG.FILL_B, DESC_BG.FILL_A)

    local effectText = getEffectTextWithRatios(artifact)
    if effectText and effectText ~= "" then
        local textX = DESC_BG.CX - DESC_BG.W * 0.5 + DESC_TEXT.PADDING
        local textY = DESC_BG.CY - DESC_BG.H * 0.5 + DESC_TEXT.PADDING
        local maxW = DESC_BG.W - DESC_TEXT.PADDING * 2
        local valueText = ArtifactDefs.formatValue(artifact.value)
        local mainRatio = getMainValueRatio(artifact)
        if mainRatio ~= nil then
            valueText = valueText .. "（" .. formatRefineRatio(mainRatio) .. "）"
        end
        local highlights = { valueText }
        local threatClearValue = ArtifactDefs.getThreatClearValue and ArtifactDefs.getThreatClearValue(artifact) or nil
        if threatClearValue ~= nil then
            local threatText = ArtifactDefs.formatValue(threatClearValue)
            local threatRatio = getThreatClearRatio(artifact)
            if threatRatio ~= nil then
                threatText = threatText .. "（" .. formatRefineRatio(threatRatio) .. "）"
            end
            highlights[#highlights + 1] = threatText
        end
        drawWrappedText(vg, textX, textY, maxW, effectText,
            DESC_TEXT.FONT, DESC_TEXT.LINE_H,
            DESC_TEXT.R, DESC_TEXT.G, DESC_TEXT.B,
            highlights)
    else
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, DESC_TEXT.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(DESC_TEXT.R, DESC_TEXT.G, DESC_TEXT.B, 180))
        nvgText(vg, DESC_BG.CX, DESC_BG.CY, "暂无神器效果", nil)
    end

    local buttonLabel = state.location == "slot" and "取下" or "安装"
    local _bfEq = BF.begin(vg, "artifact_detail_equip", BTN_EQUIP.CX, BTN_EQUIP.CY, BTN_EQUIP.W, BTN_EQUIP.H)
    drawNineSlice(vg, imgBtnLv,
        BTN_EQUIP.CX - BTN_EQUIP.W * 0.5,
        BTN_EQUIP.CY - BTN_EQUIP.H * 0.5,
        BTN_EQUIP.W, BTN_EQUIP.H,
        BTN_EQUIP.NP_T, BTN_EQUIP.NP_R, BTN_EQUIP.NP_B, BTN_EQUIP.NP_L)
    BF.finish(vg, _bfEq)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_EQUIP.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(BTN_EQUIP.TEXT_R, BTN_EQUIP.TEXT_G, BTN_EQUIP.TEXT_B, BTN_EQUIP.TEXT_A))
    nvgText(vg, BTN_EQUIP.CX, BTN_EQUIP.CY, buttonLabel, nil)

    local canRefine = canRefineArtifact(artifact)
    local _bfRefine = BF.begin(vg, "artifact_detail_refine_value", BTN_REFINE.CX, BTN_REFINE.CY, BTN_REFINE.W, BTN_REFINE.H)
    nvgSave(vg)
    if not canRefine then nvgGlobalAlpha(vg, 0.45) end
    drawNineSlice(vg, imgBtnLv,
        BTN_REFINE.CX - BTN_REFINE.W * 0.5,
        BTN_REFINE.CY - BTN_REFINE.H * 0.5,
        BTN_REFINE.W, BTN_REFINE.H,
        BTN_REFINE.NP_T, BTN_REFINE.NP_R, BTN_REFINE.NP_B, BTN_REFINE.NP_L)
    nvgRestore(vg)
    BF.finish(vg, _bfRefine)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_REFINE.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if canRefine then
        nvgFillColor(vg, nvgRGBA(BTN_REFINE.TEXT_R, BTN_REFINE.TEXT_G, BTN_REFINE.TEXT_B, BTN_REFINE.TEXT_A))
    else
        nvgFillColor(vg, nvgRGBA(120, 120, 120, 210))
    end
    nvgText(vg, BTN_REFINE.CX, BTN_REFINE.CY, canRefine and "洗练数值" or "已满值", nil)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, REFINE_COST.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if canRefine then
        nvgFillColor(vg, nvgRGBA(REFINE_COST.R, REFINE_COST.G, REFINE_COST.B, 220))
        nvgText(vg, REFINE_COST.X, REFINE_COST.Y, "消耗1点特权点", nil)
    else
        nvgFillColor(vg, nvgRGBA(120, 120, 120, 210))
        nvgText(vg, REFINE_COST.X, REFINE_COST.Y, "数值已达到上限", nil)
    end

    nvgRestore(vg)
end

---@return boolean consumed
function ArtifactDetailPanel.handleTap(tx, ty)
    if not state.visible then return false end
    if state.opening or state.closing then return true end

    local artifact = state.artifact
    if not artifact then return true end

    if hitTest(tx, ty, BTN_EQUIP.CX, BTN_EQUIP.CY, BTN_EQUIP.W, BTN_EQUIP.H) then
        BF.trigger("artifact_detail_equip")
        if onEquipCallback_ then
            onEquipCallback_(artifact, state.location, state.slot, state.subSlot)
        end
        return true
    end

    if hitTest(tx, ty, BTN_REFINE.CX, BTN_REFINE.CY, BTN_REFINE.W, BTN_REFINE.H) then
        if not canRefineArtifact(artifact) then
            return true
        end
        BF.trigger("artifact_detail_refine_value")
        if onRefineCallback_ then
            onRefineCallback_(artifact, state.location, state.slot, state.subSlot)
        end
        return true
    end

    if not hitTest(tx, ty, BG.CX, BG.CY, BG.W, BG.H) then
        ArtifactDetailPanel.hide()
        return true
    end

    return true
end

return ArtifactDetailPanel
