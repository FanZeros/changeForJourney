-- ============================================================================
-- LootBoxPage - 城镇遗匣左栏页。模式 A：1080×2400，沿用 TownPageChrome。
-- summary 与 seeds 一一对应：不排序、不合并、不生成装备；动作只转发原索引。
-- ============================================================================
local DrawUtil = require("core.DrawUtil")
local TownPageChrome = require("ui.TownPageChrome")
local DarkIcon = require("core.DarkIcon")
local EquipmentConfig = require("config.EquipmentConfig")
local ImageCache = require("ui.ImageCache")
local BF = require("systems.ButtonFeedback")

local LootBoxPage = {}
local W, H = 1080, 2400
local LIST = { x = 48, y = 490, w = 984, h = 1450, rowH = 224, gap = 18 }
local BACK = { cx = 958, cy = 2308, w = 144, h = 120 }
local ACTION_CX, ACTION_W, ACTION_H = 873, 202, 112
local BTN_W, BTN_H, BTN_Y = 420, 108, 2070
local CONFIRM = { cx = 540, cy = 1200, w = 860, h = 460, btnY = 1340 }
local OPEN_DUR, CLOSE_DUR = TownPageChrome.OPEN_DUR, TownPageChrome.CLOSE_DUR
local text = DrawUtil.drawTextStroke

local state = {
    open = false, closing = false, openTime = 0, closeTime = 0,
    summary = {}, count = 0, scrollY = 0, maxScrollY = 0,
    dragging = false, dragStartY = 0, dragStartScroll = 0, dragMoved = false,
    decompose = false, confirm = false,
    lastClickX = 540, lastClickY = BTN_Y,
    toast = "", toastTime = 0,
}
local imgName, imgBox = -1, -1
local inited = false
---@type fun(index: number)|nil
local onClaimOne = nil
---@type fun()|nil
local onClaimAll = nil
---@type fun(index: number)|nil
local onDecomposeOne = nil
---@type fun()|nil
local onDecomposeAll = nil
---@type fun()|nil
local onClose = nil
---@type fun()|nil
local onOpen = nil

local function clampScroll()
    state.scrollY = math.max(0, math.min(state.maxScrollY, state.scrollY))
end

local function insideList(x, y)
    return x >= LIST.x and x <= LIST.x + LIST.w
        and y >= LIST.y and y <= LIST.y + LIST.h
end

local function rowY(index)
    return LIST.y + LIST.rowH * 0.5 + (index - 1) * (LIST.rowH + LIST.gap) - state.scrollY
end

local function ready()
    return state.open and not state.closing and time.elapsedTime - state.openTime >= OPEN_DUR
end

local function finishClose()
    state.open, state.closing, state.dragging = false, false, false
    state.confirm, state.dragMoved, state.toast = false, false, ""
    if onClose then onClose() end
end

function LootBoxPage.init(vg)
    if inited then return end
    inited = true
    ImageCache.init(vg)
    imgName = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0) or -1
    imgBox = nvgCreateImage(vg, "image/通用图标/ICON_BX.png", 0) or -1
end

function LootBoxPage.setOnClaimOne(cb) onClaimOne = cb end
function LootBoxPage.setOnClaimAll(cb) onClaimAll = cb end
function LootBoxPage.setOnDecomposeOne(cb) onDecomposeOne = cb end
function LootBoxPage.setOnDecomposeAll(cb) onDecomposeAll = cb end
function LootBoxPage.setOnClose(cb) onClose = cb end
function LootBoxPage.setOnCloseCallback(cb) onClose = cb end
function LootBoxPage.setOnOpenCallback(cb) onOpen = cb end
-- 兼容旧接线；自动分解设置入口已撤下，本页只提供手动分解。
function LootBoxPage.setOnAutoDecompose(_cb) end

---@param summary table[]|nil
function LootBoxPage.refresh(summary)
    state.summary = summary or {}
    state.count = 0
    for _, entry in ipairs(state.summary) do
        state.count = state.count + (entry.equip and 1 or (entry.count or 1))
    end
    local height = #state.summary * (LIST.rowH + LIST.gap) - LIST.gap
    state.maxScrollY = math.max(0, height - LIST.h)
    clampScroll()
    -- 异步刷新取消当前拖拽并抑制该次释放点击，避免索引移动后误领另一条。
    if state.dragging or state.confirm then state.dragMoved = true end
    state.dragging = false
    -- 二次确认只对用户看见的这一批有效，异步掉落/刷新后必须重新确认。
    state.confirm = false
end

---@param summary table[]|nil
function LootBoxPage.open(summary)
    if summary then LootBoxPage.refresh(summary) end
    if state.open and not state.closing then return end
    state.open, state.closing = true, false
    state.openTime, state.closeTime = time.elapsedTime, 0
    state.scrollY, state.dragging, state.dragMoved = 0, false, false
    state.decompose, state.confirm, state.toast = false, false, ""
    require("systems.GameSFX").playUIMove(1)
    print("[LootBoxPage] open entries=" .. #state.summary)
end

function LootBoxPage.show(summary) LootBoxPage.open(summary or {}) end
function LootBoxPage.close()
    if not state.open or state.closing then return end
    state.closing, state.closeTime = true, time.elapsedTime
    state.dragging, state.confirm = false, false
    print("[LootBoxPage] close")
end
function LootBoxPage.forceClose()
    if state.open then
        print("[LootBoxPage] forceClose")
        finishClose()
    end
end
-- hide 保留旧的立即隐藏语义，用于主流程切页/重置。
function LootBoxPage.hide() LootBoxPage.forceClose() end
function LootBoxPage.isOpen() return state.open end
function LootBoxPage.isVisible() return state.open end
function LootBoxPage.getSeamAnim()
    return state.openTime, state.closeTime, OPEN_DUR, CLOSE_DUR
end

-- 旧调用方可继续 update；draw 也驱动生命周期，避免主循环未接 update 时卡在关闭中。
function LootBoxPage.update(_dt)
    if not state.open then return end
    if state.closing and time.elapsedTime - state.closeTime >= CLOSE_DUR then
        finishClose()
    elseif not state.closing and time.elapsedTime - state.openTime >= OPEN_DUR and onOpen then
        local callback = onOpen
        onOpen = nil
        callback()
    end
end

function LootBoxPage.showToast(message)
    if not state.open or state.closing then return end
    state.toast, state.toastTime = message, time.elapsedTime
end
function LootBoxPage.getLastClickPos() return state.lastClickX, state.lastClickY end

local function drawButton(vg, id, cx, cy, w, h, label, accent, enabled)
    local feedback = enabled and BF.begin(vg, id, cx, cy, w, h) or false
    nvgSave(vg)
    if not enabled then nvgGlobalAlpha(vg, 0.4) end
    DarkIcon.drawNine(vg, "btn", cx - w * 0.5, cy - h * 0.5, w, h, { accent = accent })
    text(vg, cx, cy, label, 38, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 3)
    nvgRestore(vg)
    BF.finish(vg, feedback)
end

-- 局部绘制函数，禁止向全局泄漏旧 drawComboItem。
---@param entry table
local function drawEntry(vg, entry, index, cy)
    local equip = entry.equip
    local quality = (equip and equip.quality) or entry.quality or 1
    local level = (equip and equip.level) or entry.level or 1
    local count = equip and 1 or (entry.count or 1)
    local q = EquipmentConfig.QUALITY[quality] or EquipmentConfig.QUALITY[1]
    local color = q.color or "ffffff"
    local r = tonumber(color:sub(1, 2), 16) or 255
    local g = tonumber(color:sub(3, 4), 16) or 255
    local b = tonumber(color:sub(5, 6), 16) or 255
    DarkIcon.drawNine(vg, "plain", 72, cy - LIST.rowH * 0.5, 930, LIST.rowH)
    DarkIcon.drawQualityBg(vg, quality, 181, cy, 174, 174, 1.0)
    local name = q.name .. "装备"
    if equip then
        local template = EquipmentConfig.ITEMS[equip.templateId]
        name = equip.name or (template and template.name) or tostring(equip.templateId or "装备")
        local icon = ImageCache.getEquipIcon(equip.templateId)
        if icon >= 0 then
            DarkIcon.drawIconDark(vg, icon, 181, cy, 160, 160, 1.0)
        end
    else
        text(vg, 181, cy - 8, "?", 70, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
    end
    text(vg, 181, cy + 69, "Lv." .. tostring(level), 32,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)

    nvgSave(vg)
    nvgIntersectScissor(vg, 294, cy - 100, 458, 200)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    local nameWidth = nvgTextBounds(vg, 0, 0, name)
    local font = math.min(42, 42 * 448 / math.max(1, nameWidth))
    text(vg, 294, cy - 56, name, font, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, r, g, b, 3)
    text(vg, 294, cy + 1, q.name .. "  ×" .. tostring(count), 34,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 224, 217, 201, 2)
    text(vg, 294, cy + 59, equip and "背包溢出 · 原装备暂存" or "挂机掉落 · 领取时生成", 28,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 181, 166, 143, 2)
    nvgRestore(vg)
    drawButton(vg, (state.decompose and "lbp_decompose_" or "lbp_claim_") .. index,
        ACTION_CX, cy, ACTION_W, ACTION_H, state.decompose and "分解" or "领取",
        state.decompose and "red" or "green", true)
end

local function drawConfirmation(vg)
    DarkIcon.drawNine(vg, "panel", CONFIRM.cx - CONFIRM.w * 0.5,
        CONFIRM.cy - CONFIRM.h * 0.5, CONFIRM.w, CONFIRM.h, { titleH = 104 })
    text(vg, 540, 1035, "确认全部分解", 48, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 4)
    text(vg, 540, 1150, "将分解遗匣中的全部装备", 36, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 2)
    text(vg, 540, 1210, "共 " .. state.count .. " 件，分解后无法撤回", 34,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 226, 149, 135, 2)
    drawButton(vg, "lbp_cancel", 330, CONFIRM.btnY, 330, 96, "取消", "gold", true)
    drawButton(vg, "lbp_confirm", 750, CONFIRM.btnY, 330, 96, "确认分解", "red", true)
end

function LootBoxPage.draw(vg)
    LootBoxPage.update(0)
    if not state.open then return end
    local progress = TownPageChrome.slideProgress(state, OPEN_DUR, CLOSE_DUR)
    local ox = DrawUtil.seamSlideX(-1, state.openTime, state.closeTime, OPEN_DUR, CLOSE_DUR, W)
    nvgSave(vg)
    -- 只在宿主左栏内绘制，不能重置宿主裁剪或覆盖中/右栏。
    nvgIntersectScissor(vg, 0, 0, W, H)
    nvgTranslate(vg, ox, 0)
    nvgGlobalAlpha(vg, progress)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(18, 16, 22, 255))
    nvgFill(vg)
    TownPageChrome.drawNamePlate(vg, imgName, "遗匣")
    text(vg, 540, 285, "旅途所得，暂存于此", 48, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 3)
    text(vg, 540, 354, "挂机掉落与背包溢出装备均可在此领取", 32,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 181, 173, 157, 2)
    text(vg, 540, 427, "待领取 " .. state.count .. " 件" .. (state.decompose and "  ·  分解模式" or ""), 36,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 231, 210, 161, 2)

    nvgSave(vg)
    nvgIntersectScissor(vg, LIST.x, LIST.y, LIST.w, LIST.h)
    if #state.summary == 0 then
        DrawUtil.drawImageCentered(vg, imgBox, 540, 1000, 260, 260, 0.7)
        text(vg, 540, 1210, "遗匣为空", 48, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 3)
        text(vg, 540, 1285, "继续远征，新的战利品会存放在这里", 32,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 161, 152, 136, 2)
    else
        local first = math.max(1, math.floor(state.scrollY / (LIST.rowH + LIST.gap)) + 1)
        local last = math.min(#state.summary, math.ceil((state.scrollY + LIST.h) / (LIST.rowH + LIST.gap)))
        for index = first, last do drawEntry(vg, state.summary[index], index, rowY(index)) end
    end
    nvgRestore(vg)
    if state.maxScrollY > 0 then
        local thumbH = math.max(60, LIST.h * LIST.h / (LIST.h + state.maxScrollY))
        local y = LIST.y + (LIST.h - thumbH) * state.scrollY / state.maxScrollY
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 1020, y, 6, thumbH, 3)
        nvgFillColor(vg, nvgRGBA(161, 137, 94, 200))
        nvgFill(vg)
    end
    local hasItems = state.count > 0
    drawButton(vg, "lbp_mode", 300, BTN_Y, BTN_W, BTN_H,
        state.decompose and "取消分解" or "切换分解模式", "red", hasItems or state.decompose)
    drawButton(vg, "lbp_claim_all", 780, BTN_Y, BTN_W, BTN_H, "全部领取", "gold", hasItems)
    drawButton(vg, "lbp_decompose_all", 540, 2220, BTN_W, BTN_H, "全部分解", "red", hasItems)
    TownPageChrome.drawBack(vg, BACK)
    if state.confirm then drawConfirmation(vg) end
    -- toast 必须最后绘制，且只属于本页，不再藏到弹窗底下或泄漏到其他页面。
    local elapsed = time.elapsedTime - state.toastTime
    if state.toast ~= "" and elapsed < 1.8 then
        text(vg, 540, 1580 - 70 * elapsed / 1.8, state.toast, 34,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 169, 141, 4,
            { alpha = math.min(1, (1.8 - elapsed) / 0.5) })
    end
    nvgRestore(vg)
end

local function action(name, callback, index)
    print("[LootBoxPage] action=" .. name .. (index and (" index=" .. index) or ""))
    if callback then callback(index) end
end

function LootBoxPage.handleInput(dx, dy)
    if not state.open then return false end
    if not ready() then return true end
    if state.dragMoved then state.dragMoved = false return true end
    state.lastClickX, state.lastClickY = dx, dy
    if state.confirm then
        if DrawUtil.hitTest(dx, dy, 330, CONFIRM.btnY, 330, 96) then
            BF.trigger("lbp_cancel")
            state.confirm = false
        elseif DrawUtil.hitTest(dx, dy, 750, CONFIRM.btnY, 330, 96) then
            BF.trigger("lbp_confirm")
            state.confirm = false
            action("decomposeAll", onDecomposeAll)
        end
        return true
    end
    if TownPageChrome.hitBack(dx, dy, BACK) then LootBoxPage.close() return true end
    if DrawUtil.hitTest(dx, dy, 300, BTN_Y, BTN_W, BTN_H) then
        if state.count > 0 or state.decompose then
            BF.trigger("lbp_mode")
            state.decompose = not state.decompose
        end
        return true
    end
    if DrawUtil.hitTest(dx, dy, 780, BTN_Y, BTN_W, BTN_H) then
        if state.count > 0 then BF.trigger("lbp_claim_all") action("claimAll", onClaimAll) end
        return true
    end
    if DrawUtil.hitTest(dx, dy, 540, 2220, BTN_W, BTN_H) then
        if state.count > 0 then BF.trigger("lbp_decompose_all") state.confirm = true end
        return true
    end
    if insideList(dx, dy) then
        local index = math.floor((dy - LIST.y + state.scrollY) / (LIST.rowH + LIST.gap)) + 1
        if state.summary[index] and DrawUtil.hitTest(dx, dy, ACTION_CX, rowY(index), ACTION_W, ACTION_H) then
            local name = state.decompose and "decompose" or "claim"
            BF.trigger("lbp_" .. name .. "_" .. index)
            if state.decompose then
                action(name, onDecomposeOne, index)
            else
                action(name, onClaimOne, index)
            end
        end
    end
    -- 空白与空态仍属于左栏页，不以“点面板外”关闭。
    return true
end

function LootBoxPage.handleDragBegin(dx, dy)
    state.dragMoved = false
    if not ready() or state.confirm or not insideList(dx, dy) then return false end
    state.dragging = true
    state.dragStartY, state.dragStartScroll = dy, state.scrollY
    return true
end
function LootBoxPage.handleDragMove(_dx, dy)
    if not state.dragging then return false end
    local delta = state.dragStartY - dy
    if math.abs(delta) >= 15 then state.dragMoved = true end
    state.scrollY = state.dragStartScroll + delta
    clampScroll()
    return true
end
function LootBoxPage.handleDragEnd(_dx, _dy)
    local wasDragging = state.dragging
    state.dragging = false
    return wasDragging
end
function LootBoxPage.handleScroll(wheel)
    if not state.open then return false end
    if not ready() or state.confirm then return true end
    if state.dragging then state.dragMoved = true end
    state.dragging = false
    state.scrollY = state.scrollY - wheel * 100
    clampScroll()
    return true
end

return LootBoxPage
