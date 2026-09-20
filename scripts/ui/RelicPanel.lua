-- ============================================================================
-- RelicPanel - 封兽祭阵（暗黑矢量九宫格）
-- 五兽座位 + 阵眼，不再使用 8×10 拼图网格
-- 布局基于 1080×2400 设计分辨率
-- ============================================================================

local DrawUtil          = require("core.DrawUtil")
local DarkIcon          = require("core.DarkIcon")
local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local hitTest           = DrawUtil.hitTest
local BF                = require("systems.ButtonFeedback")

local RelicBagPanel     = require("ui.RelicBagPanel")
local RelicDetailPanel  = require("ui.RelicDetailPanel")
local RelicReforgePanel = require("ui.RelicReforgePanel")
local RelicSystem       = require("systems.RelicSystem")
local RelicAltar        = require("systems.RelicAltar")
local RelicDefs         = require("data.RelicDefs")
local PlayerStore       = require("client.data.PlayerStore")

local RelicPanel = {}

local TITLE = {
    CX = 540, CY = 182, FONT = 72,
    STROKE_R = 10, STROKE_G = 8, STROKE_B = 6, STROKE_SIZE = 8,
    INFO_BTN_CX = 980, INFO_BTN_CY = 182, INFO_BTN_W = 80, INFO_BTN_H = 80,
    INFO_ICON_W = 54, INFO_ICON_H = 54,
}

local OVERVIEW = {
    bgCX = 540, bgCY = 1080, bgW = 920, bgH = 1500,
    bgNsT = 180, bgNsR = 40, bgNsB = 50, bgNsL = 40,
    titleCY = 420, titleFont = 48, titleStroke = 5,
    listTop = 500, listH = 1180, listPadX = 80, listW = 760,
    lineH = 46, headerH = 56,
    textFont = 32, headerFont = 36,
    textR = 0xD8, textG = 0xC9, textB = 0xA3,
    headerR = 0xC9, headerG = 0x97, headerB = 0x3B,
    POPUP_DUR = 0.22, POPUP_SCALE_FROM = 0.85,
}

local SEAT_SIZE = 210
local CORE_SIZE = 180

local SEATS = {
    ying = { cx = 540, cy = 540, size = SEAT_SIZE },
    she  = { cx = 230, cy = 820, size = SEAT_SIZE },
    lang = { cx = 850, cy = 820, size = SEAT_SIZE },
    core = { cx = 540, cy = 1040, size = CORE_SIZE },
    lu   = { cx = 280, cy = 1360, size = SEAT_SIZE },
    gui  = { cx = 800, cy = 1360, size = SEAT_SIZE },
}

local BTN_BAG = {
    CX = 874, CY = 2100, W = 340, H = 100,
    NP_T = 10, NP_R = 40, NP_B = 10, NP_L = 40,
    TEXT_CX = 873, TEXT_CY = 2100, FONT = 40,
    TEXT_R = 0xD8, TEXT_G = 0xC9, TEXT_B = 0xA3, TEXT_A = 255,
}

local BTN_CANCEL = {
    CX = 874, CY = 2100, W = 340, H = 100,
    NP_T = 10, NP_R = 40, NP_B = 10, NP_L = 40,
    FONT = 40,
}

local QUALITY_COLORS = DarkIcon.QUALITY_TRIM

local img = {
    bg = -1, infoIcon = -1,
}
local imgRelicGrid = {}

local state = {
    inited = false,
    placementMode = false,
    placingRelic = nil,
    overviewOpen = false,
    overviewClosing = false,
    overviewAnimT = 0,
    overviewScrollY = 0,
    overviewDragging = false,
    overviewLastDragY = 0,
    overviewLines = nil,
    toast = nil,
}

local function easeOutCubic(t)
    local inv = 1 - t
    return 1 - inv * inv * inv
end

local function easeInCubic(t)
    return t * t * t
end

local function getMaxStageId()
    local battleData = PlayerStore.Get("battle")
    return battleData and tonumber(battleData.maxStageId) or 0
end

local function getAltar()
    return RelicAltar.evaluate(RelicSystem.getGrid())
end

local function showToast(text)
    state.toast = { text = text, start = time.elapsedTime, dur = 1.6 }
end

local function rebuildOverviewLines()
    state.overviewLines = RelicSystem.buildEquippedOverview(RelicSystem.getGrid())
end

local function getOverviewContentHeight()
    local h = 0
    for _, line in ipairs(state.overviewLines or {}) do
        if line.kind == "header" then
            h = h + OVERVIEW.headerH + 8
        elseif line.kind == "stat" then
            h = h + OVERVIEW.lineH + 6
        else
            h = h + OVERVIEW.lineH + 8
        end
    end
    return h
end

local function clampOverviewScroll()
    local maxScroll = math.max(0, getOverviewContentHeight() - OVERVIEW.listH)
    state.overviewScrollY = math.max(0, math.min(state.overviewScrollY, maxScroll))
end

local function openOverview()
    rebuildOverviewLines()
    state.overviewOpen = true
    state.overviewClosing = false
    state.overviewAnimT = time.elapsedTime
    state.overviewScrollY = 0
    state.overviewDragging = false
end

local function closeOverview()
    if not state.overviewOpen or state.overviewClosing then return end
    state.overviewClosing = true
    state.overviewAnimT = time.elapsedTime
end

function RelicPanel.init(vg)
    img.bg       = nvgCreateImage(vg, "image/界面底板/遗物神器/UI_MXZGH_YW_BJ.png", 0)
    img.infoIcon = nvgCreateImage(vg, "image/货币道具/UI_icon_TS.png", 0)

    local iconKeys = { "GUI", "SHE", "LU", "LANG", "YING" }
    for i, key in ipairs(iconKeys) do
        imgRelicGrid[i] = nvgCreateImage(vg, "image/ICON_YW_" .. key .. ".png", 0)
    end

    RelicBagPanel.init(vg)
    RelicDetailPanel.init(vg)
    RelicReforgePanel.init(vg)

    RelicBagPanel.setOnSelectCallback(function(relic)
        if relic then
            RelicDetailPanel.show(relic, "bag")
        end
    end)

    RelicDetailPanel.setOnClose(function()
        RelicBagPanel.clearSelection()
    end)

    RelicDetailPanel.setOnReforge(function(relic)
        RelicDetailPanel.hide()
        RelicReforgePanel.show(relic)
    end)

    RelicDetailPanel.setOnEquip(function(relic, location, replaceTarget)
        if location == "replace" and replaceTarget then
            RelicDetailPanel.hide()
            RelicBagPanel.close()
            RelicSystem.requestReplace(relic.id, replaceTarget.id, function(success, reason)
                if not success then showToast(reason or "替换失败") end
            end)
        elseif location == "bag" then
            RelicDetailPanel.hide()
            RelicBagPanel.close()
            RelicPanel.enterPlacementMode(relic)
        elseif location == "grid" then
            RelicDetailPanel.hide()
            RelicSystem.requestRemoveFromGrid(relic.id, function(success, reason)
                if not success then showToast(reason or "取下失败") end
            end)
        end
    end)

    state.inited = true
    print("[RelicPanel] init altar OK")
end

function RelicPanel.enterPlacementMode(relic)
    if not relic then return end
    state.placementMode = true
    state.placingRelic = relic
    print("[RelicPanel] enterPlacementMode relic=" .. tostring(relic.id)
        .. " type=" .. tostring(relic.type))
end

function RelicPanel.exitPlacementMode()
    state.placementMode = false
    state.placingRelic = nil
end

local function drawSeat(vg, slotId, relic, unlocked, highlight)
    local seat = SEATS[slotId]
    local def = RelicAltar.SLOTS[slotId]
    if not seat or not def then return end
    local half = seat.size * 0.5
    local x, y = seat.cx - half, seat.cy - half

    local accent = "gold"
    if relic then
        accent = QUALITY_COLORS[relic.quality] or QUALITY_COLORS[1]
    elseif highlight == "valid" then
        accent = "green"
    elseif highlight == "mismatch" then
        accent = "gold"
    elseif slotId == "core" then
        accent = "gold"
    end
    DarkIcon.drawNine(vg, "slot", x, y, seat.size, seat.size, {
        accent = accent,
        radius = 18,
        alpha = unlocked and 1 or 0.45,
    })
    if relic then
        DarkIcon.drawQualityFrame(vg, relic.quality or 1, seat.cx, seat.cy, seat.size, seat.size, 1.0)
    end

    if relic then
        local icon = imgRelicGrid[relic.type]
        if icon and icon >= 0 then
            drawImageCentered(vg, icon, seat.cx, seat.cy - 8, seat.size * 0.72, seat.size * 0.72, 1.0)
        end
        local native = RelicAltar.isNative(relic, slotId)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 24)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        if native then
            nvgFillColor(vg, nvgRGBA(95, 158, 62, 255))
            nvgText(vg, seat.cx, seat.cy + half - 8, "本座", nil)
        elseif slotId == "core" then
            nvgFillColor(vg, nvgRGBA(201, 151, 59, 255))
            nvgText(vg, seat.cx, seat.cy + half - 8, "阵眼", nil)
        else
            nvgFillColor(vg, nvgRGBA(255, 122, 40, 255))
            nvgText(vg, seat.cx, seat.cy + half - 8, "错座 50%", nil)
        end
    else
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(216, 201, 163, unlocked and 220 or 90))
        nvgText(vg, seat.cx, seat.cy - 8, def.name, nil)
        if not unlocked then
            nvgFontSize(vg, 20)
            nvgFillColor(vg, nvgRGBA(150, 138, 110, 220))
            nvgText(vg, seat.cx, seat.cy + 28, RelicAltar.unlockHint(slotId), nil)
        elseif highlight then
            nvgFontSize(vg, 22)
            nvgFillColor(vg, nvgRGBA(201, 151, 59, 240))
            nvgText(vg, seat.cx, seat.cy + 28, highlight == "valid" and "点此上阵" or "可错座", nil)
        end
    end
end

local function drawLinks(vg, altar)
    nvgStrokeWidth(vg, 4)
    for _, pair in ipairs(altar.opposites or {}) do
        local a, b = SEATS[pair[1]], SEATS[pair[2]]
        if a and b then
            nvgBeginPath(vg)
            nvgMoveTo(vg, a.cx, a.cy)
            nvgLineTo(vg, b.cx, b.cy)
            nvgStrokeColor(vg, nvgRGBA(201, 151, 59, 150))
            nvgStroke(vg)
        end
    end
    for _, edge in ipairs(altar.neighbors or {}) do
        local a, b = SEATS[edge[1]], SEATS[edge[2]]
        if a and b then
            nvgBeginPath(vg)
            nvgMoveTo(vg, a.cx, a.cy)
            nvgLineTo(vg, b.cx, b.cy)
            nvgStrokeColor(vg, nvgRGBA(166, 30, 30, 120))
            nvgStroke(vg)
        end
    end
end

function RelicPanel.draw(vg)
    if not state.inited then return end

    drawImageCentered(vg, img.bg, 540, 1200, 1080, 2400, 1.0)

    drawTextStroke(vg, TITLE.CX, TITLE.CY, "封兽祭阵",
        TITLE.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TITLE.STROKE_SIZE,
        { strokeColor = { TITLE.STROKE_R, TITLE.STROKE_G, TITLE.STROKE_B } })

    local _bfInfo = BF.begin(vg, "relic_overview_info", TITLE.INFO_BTN_CX, TITLE.INFO_BTN_CY,
        TITLE.INFO_BTN_W, TITLE.INFO_BTN_H)
    if img.infoIcon >= 0 then
        drawImageCentered(vg, img.infoIcon, TITLE.INFO_BTN_CX, TITLE.INFO_BTN_CY,
            TITLE.INFO_ICON_W, TITLE.INFO_ICON_H, 1.0)
    end
    BF.finish(vg, _bfInfo)

    local altar = getAltar()
    local status = RelicAltar.describe(altar)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(216, 201, 163, 230))
    nvgText(vg, 540, 270, status[1] or "", nil)

    drawLinks(vg, altar)

    local maxStage = getMaxStageId()
    local placing = state.placementMode and state.placingRelic
    for _, slotId in ipairs(RelicAltar.SLOT_ORDER) do
        local unlocked = RelicAltar.isSlotUnlocked(slotId, maxStage)
        local relic = altar.slotMap[slotId]
        local highlight = nil
        if placing and unlocked and not relic then
            highlight = RelicAltar.isNative(placing, slotId) and "valid" or "mismatch"
            if slotId == RelicAltar.SLOT_CORE then highlight = "mismatch" end
        end
        drawSeat(vg, slotId, relic, unlocked, highlight)
    end

    if placing then
        local typeDef = RelicDefs.TYPES[placing.type]
        local nativeSlot = RelicAltar.TYPE_TO_SLOT[placing.type]
        local nativeName = nativeSlot and RelicAltar.SLOTS[nativeSlot].name or "本座"
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(216, 201, 163, 230))
        nvgText(vg, 540, 1680, "点亮的祭位上阵「" .. (typeDef and typeDef.name or "遗物")
            .. "」  本座：" .. nativeName, nil)
        nvgFontSize(vg, 26)
        nvgFillColor(vg, nvgRGBA(255, 122, 40, 220))
        nvgText(vg, 540, 1724, "错座仅 50% 词缀，且不计入成阵", nil)
    end

    if state.placementMode then
        local _bfCancel = BF.begin(vg, "relic_cancel_place", BTN_CANCEL.CX, BTN_CANCEL.CY, BTN_CANCEL.W, BTN_CANCEL.H)
        DarkIcon.drawNine(vg, "btn",
            BTN_CANCEL.CX - BTN_CANCEL.W * 0.5, BTN_CANCEL.CY - BTN_CANCEL.H * 0.5,
            BTN_CANCEL.W, BTN_CANCEL.H, { accent = "gold" })
        BF.finish(vg, _bfCancel)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_CANCEL.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
        nvgText(vg, BTN_CANCEL.CX, BTN_CANCEL.CY, "取消上阵", nil)
    else
        local _bfBag = BF.begin(vg, "relic_bag", BTN_BAG.CX, BTN_BAG.CY, BTN_BAG.W, BTN_BAG.H)
        DarkIcon.drawNine(vg, "btn",
            BTN_BAG.CX - BTN_BAG.W * 0.5, BTN_BAG.CY - BTN_BAG.H * 0.5,
            BTN_BAG.W, BTN_BAG.H, { accent = "green" })
        BF.finish(vg, _bfBag)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_BAG.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_BAG.TEXT_R, BTN_BAG.TEXT_G, BTN_BAG.TEXT_B, BTN_BAG.TEXT_A))
        nvgText(vg, BTN_BAG.TEXT_CX, BTN_BAG.TEXT_CY, "遗物背包", nil)

        local TM = require("systems.TutorialManager")
        if TM.isActive() then
            TM.registerHotspot("relic_bag_btn", BTN_BAG.CX, BTN_BAG.CY, BTN_BAG.W, BTN_BAG.H)
        end
    end

    if state.toast then
        local t = (time.elapsedTime - state.toast.start) / state.toast.dur
        if t >= 1 then
            state.toast = nil
        else
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 34)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 220, 160, math.floor(255 * (1 - t))))
            nvgText(vg, 540, 1860, state.toast.text, nil)
        end
    end
end

function RelicPanel.playReplaceAnim(newRelic, replaceTarget)
    if not newRelic or not replaceTarget then return end
    RelicSystem.requestReplace(newRelic.id, replaceTarget.id, function(success, reason)
        if not success then showToast(reason or "替换失败") end
    end)
end

function RelicPanel.isReplaceAnimActive()
    return false
end

function RelicPanel.handleTap(tx, ty)
    if state.overviewOpen then
        return RelicPanel.handleOverviewTap(tx, ty)
    end
    if RelicReforgePanel.isVisible() then
        return RelicReforgePanel.handleTap(tx, ty)
    end
    if RelicDetailPanel.isVisible() then
        return RelicDetailPanel.handleTap(tx, ty)
    end

    if state.placementMode then
        if hitTest(tx, ty, BTN_CANCEL.CX, BTN_CANCEL.CY, BTN_CANCEL.W, BTN_CANCEL.H) then
            BF.trigger("relic_cancel_place")
            RelicPanel.exitPlacementMode()
            return true
        end
        local maxStage = getMaxStageId()
        local altar = getAltar()
        for _, slotId in ipairs(RelicAltar.SLOT_ORDER) do
            local seat = SEATS[slotId]
            if hitTest(tx, ty, seat.cx, seat.cy, seat.size, seat.size) then
                if not RelicAltar.isSlotUnlocked(slotId, maxStage) then
                    showToast(RelicAltar.unlockHint(slotId))
                    return true
                end
                if altar.slotMap[slotId] then
                    showToast("该祭位已有遗物")
                    return true
                end
                local relic = state.placingRelic
                RelicPanel.exitPlacementMode()
                RelicSystem.requestPlace(relic.id, slotId, function(success, reason)
                    if not success then showToast(reason or "上阵失败") end
                end)
                return true
            end
        end
        return true
    end

    if hitTest(tx, ty, TITLE.INFO_BTN_CX, TITLE.INFO_BTN_CY, TITLE.INFO_BTN_W, TITLE.INFO_BTN_H) then
        BF.trigger("relic_overview_info")
        openOverview()
        return true
    end

    local altar = getAltar()
    for _, slotId in ipairs(RelicAltar.SLOT_ORDER) do
        local seat = SEATS[slotId]
        if hitTest(tx, ty, seat.cx, seat.cy, seat.size, seat.size) then
            local relic = altar.slotMap[slotId]
            if relic then
                RelicDetailPanel.show(relic, "grid")
                return true
            end
        end
    end

    if hitTest(tx, ty, BTN_BAG.CX, BTN_BAG.CY, BTN_BAG.W, BTN_BAG.H) then
        BF.trigger("relic_bag")
        RelicBagPanel.open()
        return true
    end

    return false
end

function RelicPanel.handleDragBegin() return false end
function RelicPanel.handleDragMove() return false end
function RelicPanel.handleDragEnd() return false end
function RelicPanel.handleAdjustDragBegin() return false end
function RelicPanel.handleAdjustDragMove() return false end
function RelicPanel.handleAdjustDragEnd() return false end
function RelicPanel.pickUpGridRelic() end
function RelicPanel.commitAdjustments() end
function RelicPanel.checkPendingCommit() end

function RelicPanel.isOverviewOpen()
    return state.overviewOpen
end

function RelicPanel.drawOverviewPanel(vg)
    if not state.overviewOpen then return end

    local elapsed = time.elapsedTime - state.overviewAnimT
    local rawT = math.min(1.0, elapsed / OVERVIEW.POPUP_DUR)
    local progress
    if state.overviewClosing then
        progress = 1.0 - easeInCubic(rawT)
        if rawT >= 1.0 then
            state.overviewOpen = false
            state.overviewClosing = false
            state.overviewLines = nil
            return
        end
    else
        progress = easeOutCubic(rawT)
    end

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * progress + 0.5)))
    nvgFill(vg)

    local scale = OVERVIEW.POPUP_SCALE_FROM + (1.0 - OVERVIEW.POPUP_SCALE_FROM) * progress
    nvgSave(vg)
    nvgTranslate(vg, OVERVIEW.bgCX, OVERVIEW.bgCY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -OVERVIEW.bgCX, -OVERVIEW.bgCY)
    nvgGlobalAlpha(vg, progress)

    DarkIcon.drawNine(vg, "panel",
        OVERVIEW.bgCX - OVERVIEW.bgW * 0.5, OVERVIEW.bgCY - OVERVIEW.bgH * 0.5,
        OVERVIEW.bgW, OVERVIEW.bgH, { titleH = OVERVIEW.bgNsT })

    drawTextStroke(vg, OVERVIEW.bgCX, OVERVIEW.titleCY, "祭阵效果总览",
        OVERVIEW.titleFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        216, 201, 163, OVERVIEW.titleStroke,
        { strokeColor = { 10, 8, 6 } })

    clampOverviewScroll()
    local listLeft = OVERVIEW.bgCX - OVERVIEW.listW * 0.5
    local contentW = OVERVIEW.listW - OVERVIEW.listPadX * 2
    local contentLeft = listLeft + OVERVIEW.listPadX
    local contentRight = contentLeft + contentW
    nvgSave(vg)
    nvgIntersectScissor(vg, listLeft, OVERVIEW.listTop, OVERVIEW.listW, OVERVIEW.listH)
    nvgTranslate(vg, 0, -state.overviewScrollY)

    local y = OVERVIEW.listTop
    for _, line in ipairs(state.overviewLines or {}) do
        if line.kind == "header" then
            y = y + 8
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, OVERVIEW.headerFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(OVERVIEW.headerR, OVERVIEW.headerG, OVERVIEW.headerB, 255))
            nvgText(vg, contentLeft, y + OVERVIEW.headerH * 0.5, line.text, nil)
            y = y + OVERVIEW.headerH
        elseif line.kind == "stat" then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, contentLeft, y, contentW, OVERVIEW.lineH, 8)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 20))
            nvgFill(vg)
            local midY = y + OVERVIEW.lineH * 0.5
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, OVERVIEW.textFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(OVERVIEW.textR, OVERVIEW.textG, OVERVIEW.textB, 255))
            nvgText(vg, contentLeft + 16, midY, line.label, nil)
            drawTextStroke(vg, contentRight - 16, midY, line.value,
                OVERVIEW.textFont, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)
            y = y + OVERVIEW.lineH + 6
        else
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, OVERVIEW.textFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(OVERVIEW.textR, OVERVIEW.textG, OVERVIEW.textB, line.muted and 160 or 255))
            nvgTextBox(vg, contentLeft, y, contentW, line.text, nil)
            y = y + OVERVIEW.lineH + 8
        end
    end
    nvgRestore(vg)
    nvgRestore(vg)
end

function RelicPanel.handleOverviewTap(tx, ty)
    if not state.overviewOpen then return false end
    if state.overviewClosing then return true end
    if time.elapsedTime - state.overviewAnimT < 0.05 then return true end
    if not hitTest(tx, ty, OVERVIEW.bgCX, OVERVIEW.bgCY, OVERVIEW.bgW, OVERVIEW.bgH) then
        closeOverview()
    end
    return true
end

function RelicPanel.handleOverviewDragBegin(dx, dy)
    if not state.overviewOpen or state.overviewClosing then return false end
    if hitTest(dx, dy, OVERVIEW.bgCX, OVERVIEW.bgCY, OVERVIEW.bgW, OVERVIEW.bgH) then
        state.overviewDragging = true
        state.overviewLastDragY = dy
        return true
    end
    return true
end

function RelicPanel.handleOverviewDragMove(dx, dy)
    if not state.overviewOpen or not state.overviewDragging then return false end
    state.overviewScrollY = state.overviewScrollY + (state.overviewLastDragY - dy)
    state.overviewLastDragY = dy
    clampOverviewScroll()
    return true
end

function RelicPanel.handleOverviewDragEnd()
    state.overviewDragging = false
    return true
end

function RelicPanel.handleOverviewScroll(wheel)
    if not state.overviewOpen or state.overviewClosing then return false end
    state.overviewScrollY = state.overviewScrollY - wheel * 80
    clampOverviewScroll()
    return true
end

function RelicPanel.isDetailOpen()
    return RelicDetailPanel.isVisible()
end
function RelicPanel.updateDetail(dt)
    RelicDetailPanel.update(dt)
end
function RelicPanel.drawDetailPanel(vg)
    RelicDetailPanel.draw(vg)
end
function RelicPanel.handleDetailTap(tx, ty)
    return RelicDetailPanel.handleTap(tx, ty)
end

function RelicPanel.isReforgeOpen()
    return RelicReforgePanel.isVisible()
end
function RelicPanel.isReforgePoolOpen()
    return RelicReforgePanel.isPoolOpen()
end
function RelicPanel.updateReforge(dt)
    RelicReforgePanel.update(dt)
end
function RelicPanel.drawReforgePanel(vg)
    RelicReforgePanel.draw(vg)
end
function RelicPanel.handleReforgeTap(tx, ty)
    return RelicReforgePanel.handleTap(tx, ty)
end
function RelicPanel.handleReforgePoolTap(tx, ty)
    return RelicReforgePanel.handlePoolTap(tx, ty)
end
function RelicPanel.handleReforgePoolDragBegin(dx, dy)
    return RelicReforgePanel.handlePoolDragBegin(dx, dy)
end
function RelicPanel.handleReforgePoolDragMove(dx, dy)
    return RelicReforgePanel.handlePoolDragMove(dx, dy)
end
function RelicPanel.handleReforgePoolDragEnd(dx, dy)
    return RelicReforgePanel.handlePoolDragEnd(dx, dy)
end
function RelicPanel.handleReforgePoolScroll(wheel)
    return RelicReforgePanel.handlePoolScroll(wheel)
end

function RelicPanel.isBagOpen()
    return RelicBagPanel.isOpen()
end
function RelicPanel.drawBagPanel(vg)
    RelicBagPanel.draw(vg)
end
function RelicPanel.handleBagTap(tx, ty)
    if RelicReforgePanel.isVisible() then
        return RelicReforgePanel.handleTap(tx, ty)
    end
    if RelicDetailPanel.isVisible() then
        return RelicDetailPanel.handleTap(tx, ty)
    end
    return RelicBagPanel.handleTap(tx, ty)
end
function RelicPanel.handleBagDragBegin(dx, dy)
    return RelicBagPanel.handleDragBegin(dx, dy)
end
function RelicPanel.handleBagDragMove(dx, dy)
    return RelicBagPanel.handleDragMove(dx, dy)
end
function RelicPanel.handleBagDragEnd(dx, dy)
    return RelicBagPanel.handleDragEnd(dx, dy)
end
function RelicPanel.handleBagScroll(wheel)
    return RelicBagPanel.handleScroll(wheel)
end

function RelicPanel.isPlacementMode()
    return state.placementMode
end
function RelicPanel.isAdjustMode()
    return false
end

return RelicPanel
