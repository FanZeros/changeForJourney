-- ============================================================================
-- ArtifactDetailPanel - 神器详情浮层：背包神器可操作，已装神器仅展示位置。
-- 坐标系: 设计分辨率 1080x2400；悬停/钉住浮层复用同一套详情与操作
-- ============================================================================

local DrawUtil          = require("core.DrawUtil")
local DarkIcon          = require("core.DarkIcon")  -- [暗黑化 P1] 矢量面板/按钮
local drawTextStroke    = DrawUtil.drawTextStroke
local hitTest           = DrawUtil.hitTest
local BF                = require("systems.ButtonFeedback")
local ArtifactDefs      = require("shared.artifact.ArtifactDefs")
local ImageCache        = require("ui.widget.ImageCache")
local ArtifactAssetUtil   = require("config.ArtifactAssetUtil")

local ArtifactDetailPanel = {}
local effectKeywords = require("ui.widget.KeywordText").new({
    textColor = { 0xb7, 0xa5, 0x94 }, popupMaxW = 500,
})

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

local DESIGN_W, DESIGN_H = 1080, 2400
local FLOAT_MARGIN, FLOAT_GAP = 16, 12

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
    -- 深色矢量底上的暖灰正文，提高对比度；效果文本与比例格式仍沿用原真源。
    R = 0xb7, G = 0xa5, B = 0x94,
    HIGHLIGHT_R = 0xf6, HIGHLIGHT_G = 0x85, HIGHLIGHT_B = 0x00,
    RATIO_R = 0x99, RATIO_G = 0x92, RATIO_B = 0x8a,
}

local ARTIFACT_ICON = {
    CX = 629, CY = 943,
    W = 220, H = 220,
}

-- 详情页仅为背包神器保留安装入口；已装神器只显示位置，不提供取下/洗练快捷操作。
local BTN_EQUIP = {
    CX = 408, CY = 1496,
    W = 210, H = 100,
    NP_T = 15, NP_R = 60, NP_B = 15, NP_L = 60,
    FONT = 38,
    TEXT_R = 0xd8, TEXT_G = 0xc9, TEXT_B = 0xa3, TEXT_A = 230,
}

local BTN_REFINE = {
    CX = 672, CY = 1496,
    W = 250, H = 100,
    NP_T = 15, NP_R = 60, NP_B = 15, NP_L = 60,
    FONT = 34,
    TEXT_R = 0xd8, TEXT_G = 0xc9, TEXT_B = 0xa3, TEXT_A = 230,
}

local REFINE_COST = {
    X = 672, Y = 1564,
    FONT = 24,
    R = 0x72, G = 0x58, B = 0x50,
}

-- ======================== 图片资源 ========================

local imgPowerIcon = -1

-- ======================== 状态 ========================

---@class ArtifactDetailAnchor
---@field x number 格子左上角，1080x2400 设计坐标
---@field y number
---@field w number
---@field h number

---@class ArtifactDetailOptions
---@field hover? boolean true=悬停，false=钉住；省略 opts 保留居中弹窗
---@field anchor? ArtifactDetailAnchor

---@class ArtifactDetailState
---@field artifact table|nil
---@field slot number|nil
---@field subSlot number|nil
---@field teamIdx number|nil
---@type ArtifactDetailState
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
    teamIdx   = nil,   -- [三队行式布局] 装配所在队伍（卸下时回传）
    floating  = false, -- 带 anchor 或 hover 的非模态浮层
    hover     = false,
    pinned    = false,
    panelCX   = BG.CX,
    panelCY   = BG.CY,
}
---@type function|nil
local onEquipCallback_ = nil
---@type function|nil
local onRefineCallback_ = nil
---@type function|nil
local onCloseCallback_ = nil
---@type function|nil
local equipActionStateGetter_ = nil

local function getEquipActionState()
    local fallback = { label = state.location == "slot" and "取下" or "安装", enabled = true }
    if not equipActionStateGetter_ or not state.artifact then return fallback end
    return equipActionStateGetter_(state.artifact, state.location, state.slot, state.subSlot, state.teamIdx) or fallback
end

--- 已装神器详情仅显示只读位置提示；背包候选保留安装入口。
local function getEquipActionHint()
    local action = getEquipActionState()
    if action.hint then return action.hint end
    if state.location == "slot" then
        return "队伍" .. tostring(state.teamIdx or 1) .. " · 号位" .. tostring(state.slot or 1)
            .. " · 第" .. tostring(state.subSlot or 1) .. "格"
    end
    return nil
end

-- ======================== 辅助 ========================

--- 优先贴在格子右侧，右侧不足改左侧；两侧都不足时取较宽侧再夹紧。
--- 只平移原 530x894 面板，不缩小字号或删减效果/比例。
---@param anchor ArtifactDetailAnchor|nil
---@return number cx, number cy
local function anchorCenter(anchor)
    if not anchor then return BG.CX, BG.CY end
    local x, y = tonumber(anchor.x) or 0, tonumber(anchor.y) or 0
    local w, h = math.max(0, tonumber(anchor.w) or 0), math.max(0, tonumber(anchor.h) or 0)
    local right = x + w + FLOAT_GAP
    local left = x - FLOAT_GAP - BG.W
    local targetX = right
    if right + BG.W > DESIGN_W - FLOAT_MARGIN then
        if left >= FLOAT_MARGIN or x > DESIGN_W - x - w then
            targetX = left
        end
    end
    targetX = math.max(FLOAT_MARGIN, math.min(targetX, DESIGN_W - FLOAT_MARGIN - BG.W))
    local targetY = math.max(FLOAT_MARGIN, math.min(y + h * 0.5 - BG.H * 0.5,
        DESIGN_H - FLOAT_MARGIN - BG.H))
    return targetX + BG.W * 0.5, targetY + BG.H * 0.5
end

--- 渲染和命中共享变换；浮层立即显示，避免移动到详情时热区随开合缩放漂移。
---@return number progress, number scale, number cx, number cy
local function renderTransform()
    local progress = 1.0
    if not state.floating then
        local now = time.elapsedTime
        if state.opening then
            local t = math.max(0, math.min((now - state.openTime) / ANIM_OPEN_DUR, 1.0))
            progress = easeOutCubic(t)
        elseif state.closing then
            local t = math.max(0, math.min((now - state.closeTime) / ANIM_CLOSE_DUR, 1.0))
            progress = 1.0 - easeInCubic(t)
        end
    end
    return progress, 0.8 + 0.2 * progress, state.panelCX, state.panelCY
end

---@param dx number
---@param dy number
---@return number lx, number ly
local function toPanelPoint(dx, dy)
    local _, scale, cx, cy = renderTransform()
    return BG.CX + (dx - cx) / scale, BG.CY + (dy - cy) / scale
end

--- 同物品同来源刷新不重启动画；同模板不同实例不能被误认为同一个神器。
local function sameSelection(artifact, location, slot, subSlot, teamIdx)
    local selected = state.artifact
    if not selected then return false end
    local sameArtifact = selected == artifact
    if selected.id ~= nil and artifact.id ~= nil then
        sameArtifact = tostring(selected.id) == tostring(artifact.id)
    end
    return sameArtifact and state.location == location and state.slot == slot
        and state.subSlot == subSlot and state.teamIdx == teamIdx
end

local function clearSelection(reason)
    effectKeywords:clear()
    if not state.visible then return end
    local artifactId = state.artifact and state.artifact.id
    state.visible = false
    state.opening = false
    state.closing = false
    state.openTime = 0
    state.closeTime = 0
    state.artifact = nil
    state.location = "bag"
    state.slot = nil
    state.subSlot = nil
    state.teamIdx = nil
    state.floating = false
    state.hover = false
    state.pinned = false
    state.panelCX = BG.CX
    state.panelCY = BG.CY
    print("[ArtifactDetailPanel] close id=" .. tostring(artifactId) .. " reason=" .. reason)
    if onCloseCallback_ then onCloseCallback_() end
end

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
    local styles = {}
    for _, highlight in ipairs(highlightText or {}) do
        local value, ratio = highlight:match("^(.-)(（[%d%.]+%%）)$")
        styles[#styles + 1] = { text = value or highlight,
            color = { DESC_TEXT.HIGHLIGHT_R, DESC_TEXT.HIGHLIGHT_G, DESC_TEXT.HIGHLIGHT_B } }
        if ratio then
            styles[#styles + 1] = { text = ratio,
                color = { DESC_TEXT.RATIO_R, DESC_TEXT.RATIO_G, DESC_TEXT.RATIO_B } }
        end
    end
    effectKeywords.textColor = { r, g, b }
    effectKeywords:draw(vg, tostring(text or ""), x, y, maxW, fontSize, lineH, nil, true, { styles = styles })
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
            clearSelection("animation")
        end
    end
end

-- ======================== Public API ========================

function ArtifactDetailPanel.init(vg)
    ImageCache.init(vg)
    imgPowerIcon = nvgCreateImage(vg, "image/通用图标/ICON_ZDL.png", 0)
    print("[ArtifactDetailPanel] init OK")
end

-- 三队行式布局：teamIdx 为装配所在队伍，"slot" 时必传（卸下用），"bag" 时可省
---@param artifact table 神器实例
---@param location? string "bag" 或 "slot"
---@param slot? number 已装配槽位
---@param subSlot? number 已装配子格
---@param teamIdx? number 装配所在队伍
---@param opts? ArtifactDetailOptions 悬停/锚定浮层；旧五参保持居中模态
function ArtifactDetailPanel.show(artifact, location, slot, subSlot, teamIdx, opts)
    if not artifact then return end
    local selectedLocation = location or "bag"
    local hover = opts ~= nil and opts.hover == true
    local floating = opts ~= nil and (hover or opts.anchor ~= nil)
    local same = state.visible and not state.closing and state.floating == floating
        and sameSelection(artifact, selectedLocation, slot, subSlot, teamIdx)
    if same then
        state.artifact = artifact
        -- 已钉住的窗口不被同格子的逐次 hover 解钉或挪动。
        if not (state.pinned and hover) then
            state.panelCX, state.panelCY = anchorCenter(opts and opts.anchor)
        end
        if not hover then ArtifactDetailPanel.pin() end
        return
    end

    effectKeywords:clear()
    state.artifact = artifact
    state.location = selectedLocation
    state.slot = slot
    state.subSlot = subSlot
    state.teamIdx = teamIdx
    state.floating = floating
    state.hover = hover
    state.pinned = not hover
    state.panelCX, state.panelCY = anchorCenter(opts and opts.anchor)
    state.visible = true
    state.opening = not floating
    state.closing = false
    state.openTime = time.elapsedTime
    state.closeTime = 0
    print("[ArtifactDetailPanel] show id=" .. tostring(artifact.id)
        .. " location=" .. state.location .. " slot=" .. tostring(slot)
        .. " subSlot=" .. tostring(subSlot) .. " teamIdx=" .. tostring(teamIdx)
        .. " hover=" .. tostring(hover) .. " floating=" .. tostring(floating)
        .. " center=" .. tostring(state.panelCX) .. "," .. tostring(state.panelCY))
end

function ArtifactDetailPanel.hide()
    effectKeywords:clear()
    if not state.visible or state.closing then return end
    if state.floating then
        ArtifactDetailPanel.closeImmediate()
        return
    end
    state.closing = true
    state.opening = false
    state.closeTime = time.elapsedTime
    print("[ArtifactDetailPanel] hide begin")
end

--- 强制清理浮层/弹窗，不等关闭动画；回调至多执行一次。
function ArtifactDetailPanel.closeImmediate()
    clearSelection("immediate")
end

--- 仅移除未钉住的悬停窗，不影响点击打开的详情。
function ArtifactDetailPanel.dismissHover()
    if state.visible and state.hover and not state.pinned then
        clearSelection("hover-leave")
    end
end

function ArtifactDetailPanel.pin()
    if not state.visible or state.closing or state.pinned then return end
    state.pinned = true
    state.hover = false
    print("[ArtifactDetailPanel] pin id=" .. tostring(state.artifact and state.artifact.id))
end

---@return boolean
function ArtifactDetailPanel.isPinned()
    internalUpdate()
    return state.visible and not state.closing and state.pinned == true
end

function ArtifactDetailPanel.isVisible()
    internalUpdate()
    return state.visible
end

--- 新选择表供宿主比较同物品；artifact 为原实例的只读引用，不复制/改写业务数据。
---@return table|nil
function ArtifactDetailPanel.getSelection()
    internalUpdate()
    if not state.visible or state.closing or not state.artifact then return nil end
    return {
        artifact = state.artifact,
        artifactId = state.artifact.id ~= nil and tostring(state.artifact.id) or nil,
        location = state.location, slot = state.slot, subSlot = state.subSlot, teamIdx = state.teamIdx,
        pinned = state.pinned, hover = state.hover,
    }
end

function ArtifactDetailPanel.refreshArtifact(artifact)
    if state.visible and artifact then
        effectKeywords:clear()
        state.artifact = artifact
    end
end

function ArtifactDetailPanel.setOnEquip(fn)
    onEquipCallback_ = fn
end

function ArtifactDetailPanel.setEquipActionStateGetter(fn)
    equipActionStateGetter_ = fn
end

function ArtifactDetailPanel.setOnRefine(fn)
    onRefineCallback_ = fn
end

function ArtifactDetailPanel.setOnClose(fn)
    onCloseCallback_ = fn
end

function ArtifactDetailPanel.update(_dt)
    internalUpdate()
end

function ArtifactDetailPanel.draw(vg)
    internalUpdate()
    if not state.visible or not state.artifact then return end

    local artifact = state.artifact
    local progress, scale, cx, cy = renderTransform()

    -- 锚定悬停/钉住均为非模态；只有旧五参居中弹窗保留遮罩。
    if not state.floating then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * progress)))
        nvgFill(vg)
    end

    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -BG.CX, -BG.CY)
    nvgGlobalAlpha(vg, progress)

    local q = math.max(1, math.min(tonumber(artifact.quality) or 1, 6))
    DarkIcon.drawNine(vg, "panel",
        BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5,
        BG.W, BG.H,
        { titleH = BG.IT, accent = DarkIcon.QUALITY_TRIM[q] })

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

    local powerStr = require("core.NumberUtil").format(getArtifactPower(artifact))
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

    effectKeywords:beginFrame()
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
    local equipAction = getEquipActionState()
    local equipHint = getEquipActionHint()
    if equipHint then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(210, 190, 150, 230))
        nvgText(vg, BG.CX, 1430, equipHint, nil)
    end

    if state.location ~= "slot" then
        local _bfEq = BF.begin(vg, "artifact_detail_equip", BTN_EQUIP.CX, BTN_EQUIP.CY, BTN_EQUIP.W, BTN_EQUIP.H)
        nvgSave(vg)
        if not equipAction.enabled then nvgGlobalAlpha(vg, 0.45) end
        DarkIcon.drawNine(vg, "btn",
            BTN_EQUIP.CX - BTN_EQUIP.W * 0.5,
            BTN_EQUIP.CY - BTN_EQUIP.H * 0.5,
            BTN_EQUIP.W, BTN_EQUIP.H,
            { accent = "green", radius = BTN_EQUIP.H * 0.3 })
        nvgRestore(vg)
        BF.finish(vg, _bfEq)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_EQUIP.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_EQUIP.TEXT_R, BTN_EQUIP.TEXT_G, BTN_EQUIP.TEXT_B, BTN_EQUIP.TEXT_A))
        nvgText(vg, BTN_EQUIP.CX, BTN_EQUIP.CY, equipAction.label, nil)
    end

    if state.location == "bag" then
        local canRefine = canRefineArtifact(artifact)
        local _bfRefine = BF.begin(vg, "artifact_detail_refine_value", BTN_REFINE.CX, BTN_REFINE.CY, BTN_REFINE.W, BTN_REFINE.H)
        nvgSave(vg)
        if not canRefine then nvgGlobalAlpha(vg, 0.45) end
        DarkIcon.drawNine(vg, "btn",
            BTN_REFINE.CX - BTN_REFINE.W * 0.5,
            BTN_REFINE.CY - BTN_REFINE.H * 0.5,
            BTN_REFINE.W, BTN_REFINE.H,
            { accent = "green", radius = BTN_REFINE.H * 0.3 })
        nvgRestore(vg)
        BF.finish(vg, _bfRefine)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_REFINE.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if canRefine then
            nvgFillColor(vg, nvgRGBA(BTN_REFINE.TEXT_R, BTN_REFINE.TEXT_G, BTN_REFINE.TEXT_B, BTN_REFINE.TEXT_A))
        else
            nvgFillColor(vg, nvgRGBA(0x8b, 0x95, 0xa5, 255))
        end
        nvgText(vg, BTN_REFINE.CX, BTN_REFINE.CY, canRefine and "洗练数值" or "已满值", nil)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, REFINE_COST.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if canRefine then
            nvgFillColor(vg, nvgRGBA(REFINE_COST.R, REFINE_COST.G, REFINE_COST.B, 220))
            nvgText(vg, REFINE_COST.X, REFINE_COST.Y, "消耗1点特权点", nil)
        else
            nvgFillColor(vg, nvgRGBA(0x8b, 0x95, 0xa5, 255))
            nvgText(vg, REFINE_COST.X, REFINE_COST.Y, "数值已达到上限", nil)
        end
    end

    nvgRestore(vg)
    effectKeywords:setPopupTransform(function(x, y)
        return cx + (x - BG.CX) * scale, cy + (y - BG.CY) * scale
    end)
    effectKeywords:drawPopup(vg)
end

---@param tx number 1080x2400 设计坐标
---@param ty number
---@return boolean consumed
function ArtifactDetailPanel.handleTap(tx, ty)
    internalUpdate()
    if not state.visible or not state.artifact then return false end
    local lx, ly = toPanelPoint(tx, ty)
    local inside = hitTest(lx, ly, BG.CX, BG.CY, BG.W, BG.H)

    -- 开合动画只拦可见本体，不吞无关格子的点击/拖拽。
    if state.closing or state.opening then return inside end
    if effectKeywords:handleInput(lx, ly) then
        ArtifactDetailPanel.pin()
        return true
    end
    if not inside then
        if state.floating then
            ArtifactDetailPanel.closeImmediate()
            return false -- 非模态浮层让宿主继续处理外部格子
        end
        ArtifactDetailPanel.hide()
        return true -- 兼容旧居中弹窗：点击遮罩关闭且不穿透
    end

    -- 点击本体（包括背包操作按钮）钉住；之后移出详情不自动关闭。
    ArtifactDetailPanel.pin()
    local artifact = state.artifact
    if state.location ~= "slot"
        and hitTest(lx, ly, BTN_EQUIP.CX, BTN_EQUIP.CY, BTN_EQUIP.W, BTN_EQUIP.H) then
        if not getEquipActionState().enabled then return true end
        BF.trigger("artifact_detail_equip")
        print("[ArtifactDetailPanel] equip id=" .. tostring(artifact.id) .. " location=" .. state.location)
        if onEquipCallback_ then
            onEquipCallback_(artifact, state.location, state.slot, state.subSlot, state.teamIdx)
        end
        return true
    end

    if state.location == "bag"
        and hitTest(lx, ly, BTN_REFINE.CX, BTN_REFINE.CY, BTN_REFINE.W, BTN_REFINE.H) then
        if not canRefineArtifact(artifact) then return true end
        BF.trigger("artifact_detail_refine_value")
        print("[ArtifactDetailPanel] refine id=" .. tostring(artifact.id))
        if onRefineCallback_ then
            onRefineCallback_(artifact, state.location, state.slot, state.subSlot)
        end
        return true
    end

    return true
end

---@param dx number|nil 1080x2400 设计坐标
---@param dy number|nil
---@return boolean
function ArtifactDetailPanel.containsPoint(dx, dy)
    internalUpdate()
    if not state.visible or not state.artifact or dx == nil or dy == nil then return false end
    local lx, ly = toPanelPoint(dx, dy)
    return hitTest(lx, ly, BG.CX, BG.CY, BG.W, BG.H)
end

return ArtifactDetailPanel
