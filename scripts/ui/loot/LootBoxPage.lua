-- ============================================================================
-- LootBoxPage - 城镇遗匣左栏页。模式 A：1080×2400，沿用 TownPageChrome。
-- sourceSummary 保留 seeds 原顺序；summary 仅作筛选显示，动作转发 sourceIndex。
-- ============================================================================
local DrawUtil = require("core.DrawUtil")
local TownPageChrome = require("ui.town.TownPageChrome")
local DarkIcon = require("core.DarkIcon")
local EquipmentConfig = require("config.EquipmentConfig")
local ImageCache = require("ui.widget.ImageCache")
local QualityMark = require("ui.widget.QualityMark")
local BF = require("systems.ButtonFeedback")
local I18n = require("core.I18n")

local LootBoxPage = {}
local W, H = 1080, 2400
local LIST = { x = 48, y = 430, w = 984, h = 1510, rowH = 224, gap = 18 }
-- 七档品质贴在一起。名称牌占左上，说明改到右上。
local FILTER = { x = 24, cy = 286, w = 96, h = 64, gap = 4 }
local BACK = { cx = 958, cy = 2308, w = 144, h = 120 }
local ACTION_CX, ACTION_W, ACTION_H = 873, 202, 112
local BTN_W, BTN_H, BTN_Y = 420, 108, 2070
local CONFIRM = { cx = 540, cy = 1200, w = 860, h = 460, btnY = 1340 }
local OPEN_DUR, CLOSE_DUR = TownPageChrome.OPEN_DUR, TownPageChrome.CLOSE_DUR
local text = DrawUtil.drawTextStroke

local state = {
    open = false, closing = false, openTime = 0, closeTime = 0,
    sourceSummary = {}, summary = {}, qualityFilter = 0,
    count = 0, pendingCount = 0, scrollY = 0, maxScrollY = 0,
    dragging = false, dragStartY = 0, dragStartScroll = 0, dragMoved = false,
    decompose = false, confirm = false,
    lastClickX = 540, lastClickY = BTN_Y,
    toast = "", toastTime = 0,
}
local imgName, imgBox = -1, -1
local inited = false
---@type fun(index: number)|nil
local onClaimOne = nil
---@type fun(qualityFilter: number)|nil
local onClaimAll = nil
---@type fun(index: number)|nil
local onDecomposeOne = nil
---@type fun(qualityFilter: number)|nil
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
    QualityMark.init(vg)
    imgName = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0) or -1
    imgBox = nvgCreateImage(vg, "image/通用图标/ICON_CZ_YX.png", 0) or -1
end

function LootBoxPage.setOnClaimOne(cb) onClaimOne = cb end
function LootBoxPage.setOnClaimAll(cb) onClaimAll = cb end
function LootBoxPage.setOnDecomposeOne(cb) onDecomposeOne = cb end
function LootBoxPage.setOnDecomposeAll(cb) onDecomposeAll = cb end
function LootBoxPage.setOnClose(cb) onClose = cb end
function LootBoxPage.setOnCloseCallback(cb) onClose = cb end
function LootBoxPage.setOnOpenCallback(cb) onOpen = cb end
-- 兼容旧接线；自动回收设置入口已撤下，本页只提供手动回收。
function LootBoxPage.setOnAutoDecompose(_cb) end

local function filterName()
    return state.qualityFilter == 0 and "全部品质" or EquipmentConfig.QUALITY[state.qualityFilter].name
end

local function rebuildSummary()
    state.summary = {}
    state.count, state.pendingCount = 0, 0
    for sourceIndex, entry in ipairs(state.sourceSummary) do
        local equip = entry.equip
        -- 旧种子仅在“全部”中展示待整理，不能冒充已确定品质的装备。
        if state.qualityFilter == 0 or (equip and equip.quality == state.qualityFilter) then
            local display = {}
            for key, value in pairs(entry) do display[key] = value end
            display.sourceIndex = entry.sourceIndex or sourceIndex
            state.summary[#state.summary + 1] = display
            if equip then
                state.count = state.count + 1
            else
                state.pendingCount = state.pendingCount + (entry.count or 1)
            end
        end
    end
    local height = #state.summary * (LIST.rowH + LIST.gap) - LIST.gap
    state.maxScrollY = math.max(0, height - LIST.h)
    clampScroll()
end

local function setFilter(quality)
    if state.qualityFilter == quality then return end
    state.qualityFilter, state.scrollY = quality, 0
    if state.dragging then state.dragMoved = true end
    state.dragging, state.confirm = false, false
    rebuildSummary()
end

---@param summary table[]|nil
function LootBoxPage.refresh(summary)
    -- 不改写来源数组，也不在此页生成或迁移装备；刷新继续沿用当前筛选。
    state.sourceSummary = summary or {}
    rebuildSummary()
    -- 异步刷新取消当前拖拽并抑制该次释放点击，避免索引移动后误领另一条。
    if state.dragging or state.confirm then state.dragMoved = true end
    state.dragging = false
    -- 二次确认只对用户看见的这一批有效，异步掉落/刷新后必须重新确认。
    state.confirm = false
end

---@param summary table[]|nil
function LootBoxPage.open(summary)
    state.qualityFilter, state.scrollY = 0, 0
    LootBoxPage.refresh(summary or state.sourceSummary)
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
    local caption = I18n.lookup(label)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 38)
    local captionWidth = nvgTextBounds(vg, 0, 0, caption)
    local fontSize = math.min(38, 38 * (w - 20) / math.max(1, captionWidth))
    text(vg, cx, cy, caption, fontSize, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 3)
    nvgRestore(vg)
    BF.finish(vg, feedback)
end

local function filterCenter(quality)
    return FILTER.x + FILTER.w * 0.5 + quality * (FILTER.w + FILTER.gap), FILTER.cy
end

local function drawFilters(vg)
    for quality = 0, 6 do
        local cx, cy = filterCenter(quality)
        local selected = state.qualityFilter == quality
        if quality == 0 then
            drawButton(vg, "lbp_filter_0", cx, cy, FILTER.w, FILTER.h,
                "全部", selected and "green" or "gold", true)
        else
            local feedback = BF.begin(vg, "lbp_filter_" .. quality, cx, cy, FILTER.w, FILTER.h)
            DarkIcon.drawNine(vg, "btn", cx - FILTER.w * 0.5, cy - FILTER.h * 0.5,
                FILTER.w, FILTER.h, { accent = selected and "green" or "gold" })
            if not QualityMark.draw(vg, quality, cx, cy, 52, 1) then
                local label = EquipmentConfig.QUALITY[quality].name
                text(vg, cx, cy, label, 24, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 2)
            end
            BF.finish(vg, feedback)
        end
    end
end

-- 局部绘制函数，只展示已生成装备；没有装备的残留数据保留待整理占位。
---@param entry table
local function drawEntry(vg, entry, index, cy)
    local equip = entry.equip
    local quality = equip and equip.quality
    local q = quality and EquipmentConfig.QUALITY[quality]
    local color = (q and q.color) or "b5a68f"
    local r = tonumber(color:sub(1, 2), 16) or 255
    local g = tonumber(color:sub(3, 4), 16) or 255
    local b = tonumber(color:sub(5, 6), 16) or 255
    DarkIcon.drawNine(vg, "plain", 72, cy - LIST.rowH * 0.5, 930, LIST.rowH)
    local name = "待整理"
    if equip then
        if q then DarkIcon.drawQualityBg(vg, quality, 181, cy, 174, 174, 1.0) end
        local template = EquipmentConfig.ITEMS[equip.templateId]
        name = equip.name or (template and template.name) or tostring(equip.templateId or "装备")
        local icon = ImageCache.getEquipIcon(equip.templateId)
        if icon >= 0 then
            DarkIcon.drawIconDark(vg, icon, 181, cy, 160, 160, 1.0)
        end
        if equip.level then
            text(vg, 181, cy + 69, "Lv." .. tostring(equip.level), 32,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
        end
    else
        text(vg, 181, cy, "待整理", 32, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 181, 166, 143, 3)
    end

    nvgSave(vg)
    nvgIntersectScissor(vg, 294, cy - 100, 458, 200)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    local nameWidth = nvgTextBounds(vg, 0, 0, name)
    local font = math.min(42, 42 * 448 / math.max(1, nameWidth))
    text(vg, 294, cy - 56, name, font, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, r, g, b, 3)
    if equip and quality and QualityMark.draw(vg, quality, 322, cy + 1, 48, 1) then
        -- 品质行改用背包/铁匠共用的小图，不再重复写品质名。
    else
        text(vg, 294, cy + 1, equip and ((q and q.name) or "品质待整理") or "装备内容待整理", 34,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 224, 217, 201, 2)
    end
    -- 旧的完整装备没有 source 字段，沿用背包溢出的展示语义。
    local sourceText = entry.source == "idle" and "挂机掉落 · 装备已暂存" or "背包溢出 · 原装备暂存"
    text(vg, 294, cy + 59, equip and sourceText or "暂不可领取或回收", 28,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 181, 166, 143, 2)
    nvgRestore(vg)
    local label = equip and (state.decompose and "回收" or "领取") or "待整理"
    drawButton(vg, (state.decompose and "lbp_decompose_" or "lbp_claim_") .. index,
        ACTION_CX, cy, ACTION_W, ACTION_H, label,
        state.decompose and "red" or "green", equip ~= nil)
end

local function drawConfirmation(vg)
    DarkIcon.drawNine(vg, "panel", CONFIRM.cx - CONFIRM.w * 0.5,
        CONFIRM.cy - CONFIRM.h * 0.5, CONFIRM.w, CONFIRM.h, { titleH = 104 })
    text(vg, 540, 1035, "确认一键回收", 48, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 4)
    text(vg, 540, 1150, string.format(I18n.lookup("回收范围：%s装备"), I18n.lookup(filterName())), 36,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 2)
    text(vg, 540, 1210, string.format(I18n.lookup("共 %d 件，回收后无法撤回"), state.count), 34,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 226, 149, 135, 2)
    drawButton(vg, "lbp_cancel", 330, CONFIRM.btnY, 330, 96, "取消", "gold", true)
    drawButton(vg, "lbp_confirm", 750, CONFIRM.btnY, 330, 96, "确认回收", "red", true)
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
    text(vg, 1044, 130, "旅途所得，暂存于此", 32,
        NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, 216, 201, 163, 3)
    drawFilters(vg)
    local statusText = string.format(I18n.lookup("%s · 待领取 %d 件"), I18n.lookup(filterName()), state.count)
    if state.pendingCount > 0 then
        statusText = statusText .. string.format(I18n.lookup(" · 待整理 %d 件"), state.pendingCount)
    end
    if state.decompose then statusText = statusText .. I18n.lookup(" · 回收模式") end
    text(vg, 540, 360, statusText, 28,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 231, 210, 161, 2)

    nvgSave(vg)
    nvgIntersectScissor(vg, LIST.x, LIST.y, LIST.w, LIST.h)
    if #state.summary == 0 then
        DrawUtil.drawImageCentered(vg, imgBox, 540, 1000, 260, 260, 0.7)
        local emptyTitle = state.qualityFilter == 0 and "遗匣为空" or "暂无该稀有度装备"
        local emptyHint = state.qualityFilter == 0 and "继续远征，新的战利品会存放在这里" or "切换其他品质或查看全部装备"
        text(vg, 540, 1210, emptyTitle, 48, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 3)
        text(vg, 540, 1285, emptyHint, 32,
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
        state.decompose and "取消回收" or "切换回收", "red", hasItems or state.decompose)
    drawButton(vg, "lbp_claim_all", 780, BTN_Y, BTN_W, BTN_H,
        state.qualityFilter == 0 and "一键领取" or "领取筛选", "gold", hasItems)
    drawButton(vg, "lbp_decompose_all", 540, 2220, BTN_W, BTN_H,
        state.qualityFilter == 0 and "一键回收" or "回收筛选", "red", hasItems)
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

-- 单件参数是原 seeds 索引；批量参数是品质筛选（0 全部，1..6 精确匹配）。
-- 批量接收方只处理已有 equip 的条目，待整理残留不参与领取或回收。
local function action(name, callback, value)
    print("[LootBoxPage] action=" .. name .. " value=" .. tostring(value))
    if callback then callback(value) end
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
            action("decomposeAll", onDecomposeAll, state.qualityFilter)
        end
        return true
    end
    if TownPageChrome.hitBack(dx, dy, BACK) then LootBoxPage.close() return true end
    for quality = 0, 6 do
        local cx, cy = filterCenter(quality)
        if DrawUtil.hitTest(dx, dy, cx, cy, FILTER.w, FILTER.h) then
            BF.trigger("lbp_filter_" .. quality)
            setFilter(quality)
            return true
        end
    end
    if DrawUtil.hitTest(dx, dy, 300, BTN_Y, BTN_W, BTN_H) then
        if state.count > 0 or state.decompose then
            BF.trigger("lbp_mode")
            state.decompose = not state.decompose
        end
        return true
    end
    if DrawUtil.hitTest(dx, dy, 780, BTN_Y, BTN_W, BTN_H) then
        if state.count > 0 then
            BF.trigger("lbp_claim_all")
            action("claimAll", onClaimAll, state.qualityFilter)
        end
        return true
    end
    if DrawUtil.hitTest(dx, dy, 540, 2220, BTN_W, BTN_H) then
        if state.count > 0 then BF.trigger("lbp_decompose_all") state.confirm = true end
        return true
    end
    if insideList(dx, dy) then
        local index = math.floor((dy - LIST.y + state.scrollY) / (LIST.rowH + LIST.gap)) + 1
        local entry = state.summary[index] --[[@as table?]]
        if entry and entry.equip and DrawUtil.hitTest(dx, dy, ACTION_CX, rowY(index), ACTION_W, ACTION_H) then
            local name = state.decompose and "decompose" or "claim"
            BF.trigger("lbp_" .. name .. "_" .. index)
            if state.decompose then
                action(name, onDecomposeOne, entry.sourceIndex)
            else
                action(name, onClaimOne, entry.sourceIndex)
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
