-- ============================================================================
-- LootBoxPage - 城镇遗匣左栏页。模式 A：1080×2400，沿用 TownPageChrome。
-- sourceSummary 保留 seeds 原顺序；summary 仅作筛选/战力降序显示，动作转发 sourceIndex。
-- ============================================================================
local DrawUtil = require("core.DrawUtil")
local TownPageChrome = require("ui.town.TownPageChrome")
local DarkIcon = require("core.DarkIcon")
local EquipmentConfig = require("config.EquipmentConfig")
local EquipmentSetConfig = require("config.EquipmentSetConfig")
local ImageCache = require("ui.widget.ImageCache")
local EquipmentSetIcon = require("ui.widget.EquipmentSetIcon")
local QualityMark = require("ui.widget.QualityMark")
local SetFilterDialog = require("ui.widget.SetFilterDialog")
local BF = require("systems.ButtonFeedback")
local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
local NumberUtil = require("core.NumberUtil")
local I18n = require("core.I18n")
local BackpackFilters = require("ui.backpack.BackpackFilters")
local EquipmentQuery = require("systems.EquipmentQuery")
local EquipmentSystem = require("systems.EquipmentSystem")

local LootBoxPage = {}
local W, H = 1080, 2400
local LIST = { x = 48, y = 660, w = 984, h = 1460, rowH = 224, gap = 18 }
-- 工具条与列表同一坐标源：部位/类型行中心434，排序行中心524，列表底2120。
local GRID = { FIRST_ROW_TOP = LIST.y, CLIP_BOTTOM = LIST.y + LIST.h }
-- 稀有度勾选条：右上角一排 6 档（与背包分解页同款同位置逻辑），名称牌占左上。
local FILTER = { firstCX = 565, cy = 286, size = 70, gap = 12 }
-- 套装筛选入口按钮：与稀有度勾选条同行，左侧空位。
local SET_BTN = { cx = 190, cy = 286, w = 280, h = 70 }
local BACK = { cx = 958, cy = 2308, w = 144, h = 120 }
local ACTION_CX, ACTION_W, ACTION_H = 873, 202, 112
local BTN_W, BTN_H, BTN_Y = 420, 108, 2210
local BTN_CLAIM_CX, BTN_DECOMPOSE_CX = 320, 760
local CONFIRM = { cx = 540, cy = 1200, w = 860, h = 460, btnY = 1340 }
local OPEN_DUR, CLOSE_DUR = TownPageChrome.OPEN_DUR, TownPageChrome.CLOSE_DUR
local text = DrawUtil.drawTextStroke

local state = {
    open = false, closing = false, openTime = 0, closeTime = 0,
    sourceSummary = {}, summary = {},
    ---@type string|nil
    slotFilter = nil,
    ---@type string|nil
    typeFilter = nil,
    ---@type string|nil
    sortKey = nil,
    sortAscending = false, -- 仅排序方向，绝不影响批量动作的过滤范围
    ---@type table<number, boolean>
    qualitySet = {}, -- [quality]=true 勾选的稀有度档；空集合=全部（不筛选）
    ---@type table<string, boolean>
    setFilter = {}, -- [setId]=true / ["none"]=true 勾选的套装；空集合=全部（不筛选）
    count = 0, pendingCount = 0, scrollY = 0, maxScrollY = 0,
    dragging = false, dragStartY = 0, dragStartScroll = 0, dragMoved = false,
    decompose = false, confirm = false,
    lastClickX = 540, lastClickY = BTN_Y,
    messages = {}, messageUntil = 0,
    hoverIndex = nil, hoverSince = 0, detailIndex = nil, detailPinned = false,
}
local imgName, imgBox, imgCheck, imgPower = -1, -1, -1, -1
local inited = false
-- bind 返回独立菜单；先声明供关闭生命周期使用，后接重建回调。
---@type table
local filterBar = {}
local menuPressed = false
---@type fun(index: number)|nil
local onClaimOne = nil
---@type fun(qualitySet: table<number, boolean>, setFilter: table<string, boolean>, detailFilter: table)|nil
local onClaimAll = nil
---@type fun(index: number)|nil
local onDecomposeOne = nil
---@type fun(qualitySet: table<number, boolean>, setFilter: table<string, boolean>, detailFilter: table)|nil
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

local function previewBounds(index, equip)
    local width, height = EquipmentDetail.readOnlySize(equip)
    local x = 16
    local y = math.max(390, math.min(2150 - height, rowY(index) - height * 0.5))
    return x, y, width, height
end

local function ready()
    return state.open and not state.closing and time.elapsedTime - state.openTime >= OPEN_DUR
end

local function clearDetail()
    state.detailIndex, state.detailPinned = nil, false
    state.hoverIndex, state.hoverSince = nil, 0
end

local function finishClose()
    clearDetail()
    SetFilterDialog.close()
    filterBar.close()
    menuPressed = false
    state.open, state.closing, state.dragging = false, false, false
    state.confirm, state.dragMoved, state.messages = false, false, {}
    if onClose then onClose() end
end

function LootBoxPage.init(vg)
    if inited then return end
    inited = true
    ImageCache.init(vg)
    QualityMark.init(vg)
    EquipmentDetail.init(vg)
    imgName = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0) or -1
    imgBox = nvgCreateImage(vg, "image/通用图标/ICON_CZ_YX.png", 0) or -1
    imgCheck = nvgCreateImage(vg, "image/货币道具/UI_icon_GOU.png", 0) or -1
    imgPower = nvgCreateImage(vg, "image/通用图标/ICON_ZDL.png", 0) or -1
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

--- 当前勾选的稀有度集合（复制一份传出，避免外部改写页面状态）。
---@return table<number, boolean>
local function currentSet()
    local set = {}
    for quality, checked in pairs(state.qualitySet) do
        if checked then set[quality] = true end
    end
    return set
end

--- 当前勾选的套装集合（复制一份传出）。
---@return table<string, boolean>
local function currentSetFilter()
    local set = {}
    for setId, checked in pairs(state.setFilter) do
        if checked then set[setId] = true end
    end
    return set
end

--- 批量操作追加只读快照；不传页面状态表，旧前两参保持品质/套装契约。
local function currentDetailFilter()
    return { slotFilter = state.slotFilter, typeFilter = state.typeFilter }
end

local function hasFilter()
    return EquipmentQuery.isFiltered(state.qualitySet, state.setFilter, state)
end

--- 套装行数量只统计确定装备，忽略套装勾选但遵循品质/部位/类型 AND 规则。
---@return table<string, integer>
local function getSetCounts()
    local counts = { none = 0 }
    for _, setId in ipairs(EquipmentSetConfig.orderedSetIds()) do counts[setId] = 0 end
    for _, entry in ipairs(state.sourceSummary) do
        local equip = entry.equip
        if EquipmentQuery.matches(equip, state.qualitySet, nil, state) then
            local setId = EquipmentQuery.getSetId(equip)
            counts[setId] = (counts[setId] or 0) + 1
        end
    end
    return counts
end

--- 套装筛选范围描述（已翻译）：未勾选=全部套装；单套=套装名；多套=「共 N 种套装」。
local function setFilterName()
    local picked = {}
    for setId, checked in pairs(state.setFilter) do
        if checked then picked[#picked + 1] = setId end
    end
    if #picked == 0 then return nil end
    if #picked == 1 then
        if picked[1] == SetFilterDialog.NONE_KEY then return I18n.lookup("无套装") end
        local def = EquipmentSetConfig.get(picked[1])
        return def and I18n.lookup(def.name) or picked[1]
    end
    return string.format(I18n.lookup("共 %d 种套装"), #picked)
end

--- 品质+套装组合筛选范围描述（状态行用）。
local function filterName()
    local picked = {}
    for quality = 1, QualityMark.count() do
        if state.qualitySet[quality] then picked[#picked + 1] = quality end
    end
    local qualityText
    if #picked == 0 then qualityText = I18n.lookup("全部品质")
    elseif #picked == 1 then qualityText = I18n.lookup(EquipmentConfig.QUALITY[picked[1]].name)
    else qualityText = string.format(I18n.lookup("共 %d 种品质"), #picked) end
    local parts = { qualityText }
    local setText = setFilterName()
    if setText then parts[#parts + 1] = setText end
    if state.slotFilter then parts[#parts + 1] = I18n.lookup(EquipmentConfig.SLOT_NAME[state.slotFilter]) end
    if state.typeFilter then parts[#parts + 1] = I18n.lookup(state.typeFilter) end
    return table.concat(parts, " · ")
end

local function rebuildSummary()
    state.summary = {}
    state.count, state.pendingCount = 0, 0
    local sortKey = state.sortKey
    local field = ({ power = "power", quality = "quality", level = "level", ascend = "enhanceLevel" })[sortKey]
    local attributeSort = sortKey ~= nil and sortKey ~= "default" and field == nil
    for sourceIndex, entry in ipairs(state.sourceSummary) do
        local equip = entry.equip
        -- 待整理只在所有过滤维度不限时展示，排序方向不构成过滤条件。
        local matches = equip and EquipmentQuery.matches(equip, state.qualitySet, state.setFilter, state)
            or not equip and not hasFilter()
        if matches then
            local display = {}
            for key, value in pairs(entry) do display[key] = value end
            display.sourceIndex = entry.sourceIndex or sourceIndex
            display.displayOrder = sourceIndex
            if equip then
                -- 显示/评分/详情共用深拷贝水合结果，源装备及腐化快照保持不变。
                display.equip = EquipmentQuery.hydrateCopy(equip)
                display.quality, display.level = display.equip.quality, display.equip.level
                display.enhanceLevel = EquipmentSystem.getAscendLevel(display.equip)
                display.power = EquipmentDetail.calcEquipPower(display.equip, nil)
                if attributeSort then
                    display.sortValue, display.hasSortAttribute = EquipmentQuery.attributeValue(display.equip, sortKey)
                end
                state.count = state.count + 1
            else
                display.power = 0
                state.pendingCount = state.pendingCount + (entry.count or 1)
            end
            state.summary[#state.summary + 1] = display
        end
    end
    -- 默认保留遗匣数值战力降序；显式排序按有效值，缺属性无论方向始终置后。
    local function defaultOrder(a, b)
        if a.power ~= b.power then return a.power > b.power end
        return a.displayOrder < b.displayOrder
    end
    table.sort(state.summary, function(a, b)
        if (a.equip ~= nil) ~= (b.equip ~= nil) then return a.equip ~= nil end
        if not a.equip then return a.displayOrder < b.displayOrder end
        if attributeSort then
            if a.hasSortAttribute ~= b.hasSortAttribute then return a.hasSortAttribute end
            if a.sortValue ~= b.sortValue then
                if state.sortAscending then return a.sortValue < b.sortValue end
                return a.sortValue > b.sortValue
            end
        elseif field and a[field] ~= b[field] then
            if state.sortAscending then return a[field] < b[field] end
            return a[field] > b[field]
        elseif (not sortKey or sortKey == "default") and state.sortAscending and a.power ~= b.power then
            return a.power < b.power
        end
        return defaultOrder(a, b)
    end)
    local height = #state.summary * (LIST.rowH + LIST.gap) - LIST.gap
    state.maxScrollY = math.max(0, height - LIST.h)
    clampScroll()
    clearDetail()
end

--- 过滤/排序变化统一清理滚动手势、旧确认与旧详情。
local function filtersChanged()
    state.scrollY = 0
    if state.dragging then state.dragMoved = true end
    state.dragging, state.confirm = false, false
    rebuildSummary()
end

-- 只绑定通用工具条，不引入仓库英雄/双持上下文；状态与菜单均属于本页。
filterBar = BackpackFilters.bind({
    filters = state, GRID = GRID,
    getSlot = function() return state.slotFilter end,
    setSlot = function(slot) state.slotFilter = slot end,
    clearQualitySets = function() state.qualitySet, state.setFilter = {}, {} end,
    onChange = filtersChanged,
})

--- 勾选/取消某一稀有度档（多选）；空集合即“全部”。
local function toggleQuality(quality)
    state.qualitySet[quality] = not state.qualitySet[quality] or nil
    filtersChanged()
end

---@param summary table[]|nil
function LootBoxPage.refresh(summary)
    -- 不改写来源数组，也不在此页生成或迁移装备；刷新继续沿用当前筛选。
    state.sourceSummary = summary or {}
    rebuildSummary()
    -- 异步刷新取消当前拖拽并抑制该次释放点击，避免索引移动后误领另一条。
    if state.dragging or state.confirm or menuPressed then state.dragMoved = true end
    -- close 会清菜单 moved，释放保护先保存在页面；刷新不改过滤和排序。
    filterBar.close()
    menuPressed = false
    state.dragging = false
    -- 二次确认只对用户看见的这一批有效，异步掉落/刷新后必须重新确认。
    state.confirm = false
end

---@param summary table[]|nil
function LootBoxPage.open(summary)
    state.qualitySet, state.setFilter, state.scrollY = {}, {}, 0
    state.slotFilter, state.typeFilter, state.sortKey, state.sortAscending = nil, nil, nil, false
    state.dragging, state.dragMoved, state.confirm = false, false, false
    filterBar.close()
    menuPressed = false
    SetFilterDialog.close()
    LootBoxPage.refresh(summary or state.sourceSummary)
    if state.open and not state.closing then return end
    state.open, state.closing = true, false
    state.openTime, state.closeTime = time.elapsedTime, 0
    state.scrollY, state.dragging, state.dragMoved = 0, false, false
    state.decompose, state.confirm, state.messages = false, false, {}
    require("systems.GameSFX").playUIMove(1)
    print("[LootBoxPage] open entries=" .. #state.summary)
end

function LootBoxPage.show(summary) LootBoxPage.open(summary or {}) end
function LootBoxPage.close()
    if not state.open or state.closing then return end
    state.closing, state.closeTime = true, time.elapsedTime
    state.dragging, state.confirm = false, false
    filterBar.close()
    menuPressed = false
    SetFilterDialog.close()
    clearDetail()
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
function LootBoxPage.isDetailOpen() return state.detailIndex ~= nil end
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
    if not state.open or state.closing or not message or message == "" then return end
    local messages = state.messages
    messages[#messages + 1] = message
    if #messages == 1 then state.messageUntil = time.elapsedTime + 1.8 end
    print("[LootBoxPage] message=" .. message)
end
function LootBoxPage.getLastClickPos() return state.lastClickX, state.lastClickY end

local function drawMessages(vg)
    local messages = state.messages
    if #messages == 0 then return end
    if time.elapsedTime >= state.messageUntil then
        table.remove(messages, 1)
        if #messages == 0 then return end
        state.messageUntil = time.elapsedTime + 1.8
    end
    local current = messages[1]
    local remaining = state.messageUntil - time.elapsedTime
    local alpha = math.min(1, remaining / 0.35)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 32)
    local boxY = 910
    local boxW = math.min(910, math.max(370, nvgTextBounds(vg, 0, 0, I18n.lookup(current)) + 68))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 540 - boxW * 0.5, boxY, boxW, 104, 18)
    nvgFillColor(vg, nvgRGBA(22, 19, 22, math.floor(220 * alpha)))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(190, 155, 104, math.floor(185 * alpha)))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    text(vg, 540, boxY + 52, current, 32, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        244, 237, 224, 3, { alpha = alpha })
    if #messages > 1 then
        text(vg, 540, boxY + 90, "+" .. tostring(#messages - 1), 22,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 2, { alpha = alpha })
    end
end

local function drawButton(vg, id, cx, cy, w, h, label, accent, enabled)
    local feedback = enabled and BF.begin(vg, id, cx, cy, w, h) or false
    nvgSave(vg)
    if not enabled then nvgGlobalAlpha(vg, 0.4) end
    DarkIcon.drawNine(vg, "btn", cx - w * 0.5, cy - h * 0.5, w, h, { accent = accent })
    nvgRestore(vg)
    local caption = I18n.lookup(label)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 38)
    local captionWidth = nvgTextBounds(vg, 0, 0, caption)
    local fontSize = math.min(38, 38 * (w - 20) / math.max(1, captionWidth))
    -- 按钮文字：可用=亮骨白，禁用=灰蓝色
    local tr, tg, tb = 244, 237, 224
    if not enabled then tr, tg, tb = 0x8b, 0x95, 0xa5 end
    text(vg, cx, cy, caption, fontSize, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, tr, tg, tb, 3)
    BF.finish(vg, feedback)
end

local function filterCenter(quality)
    return FILTER.firstCX + (quality - 1) * (FILTER.size + FILTER.gap), FILTER.cy
end

--- 套装筛选入口：与稀有度勾选条同行左侧；显示当前选中数（0=「套装」，N=「套装·N」）。
local function drawSetFilterButton(vg)
    local selected = SetFilterDialog.countSelected(state.setFilter)
    local feedback = BF.begin(vg, "lbp_set_filter", SET_BTN.cx, SET_BTN.cy, SET_BTN.w, SET_BTN.h)
    DarkIcon.drawNine(vg, "btn", SET_BTN.cx - SET_BTN.w * 0.5, SET_BTN.cy - SET_BTN.h * 0.5,
        SET_BTN.w, SET_BTN.h, { accent = selected > 0 and "green" or "gold" })
    local label = selected > 0 and I18n.format("套装 · %d", selected) or I18n.lookup("套装")
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 34)
    text(vg, SET_BTN.cx, SET_BTN.cy, label, 34, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        244, 237, 224, 3)
    BF.finish(vg, feedback)
end

--- 稀有度勾选条：与背包分解页同款——右上角一排品质框（品质小图即框体），
--- 1-6 档可多选；勾选=框内居中对勾；全不勾即全部，无“全部”按钮。
local function drawFilters(vg)
    drawSetFilterButton(vg)
    for quality = 1, QualityMark.count() do
        local cx, cy = filterCenter(quality)
        local checked = state.qualitySet[quality] == true
        local feedback = BF.begin(vg, "lbp_filter_" .. quality, cx, cy, FILTER.size, FILTER.size)
        if not QualityMark.draw(vg, quality, cx, cy, FILTER.size, 1) then
            local label = EquipmentConfig.QUALITY[quality].name
            text(vg, cx, cy, label, 24, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 2)
        end
        if checked and imgCheck >= 0 then
            DrawUtil.drawImageCentered(vg, imgCheck, cx, cy, 40, 40, 1)
        end
        BF.finish(vg, feedback)
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
            local lvl = EquipmentSetIcon.levelLayout(equip, 181, cy, 174)
            local lvlText = "Lv." .. tostring(equip.level)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 32)
            local badge = EquipmentSetIcon.badgeLayout(181, cy, 174)
            local availableW = lvl.x - (badge.x + badge.size) - 8
            local textW = nvgTextBounds(vg, 0, 0, lvlText)
            local font = textW > availableW and 32 * availableW / textW or 32
            text(vg, lvl.x, cy + 69, lvlText, font,
                NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
        end
        EquipmentSetIcon.drawBadge(vg, equip, 181, cy, 174, 1.0)
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
    -- 第三行：确定装备显示战力（与装备详情同口径）；待整理条目保留不可操作提示。
    if equip then
        local powerStr = NumberUtil.format(entry.power)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        DrawUtil.drawImageCentered(vg, imgPower, 294 + 15, cy + 59, 30, 30, 1)
        text(vg, 294 + 30 + 8, cy + 59, powerStr, 30,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 255, 214, 102, 2)
    else
        text(vg, 294, cy + 59, "暂不可领取或回收", 28,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 181, 166, 143, 2)
    end
    nvgRestore(vg)
    drawButton(vg, "lbp_claim_" .. index,
        ACTION_CX, cy, ACTION_W, ACTION_H, equip and "领取" or "待整理",
        "green", equip ~= nil)
end

local function drawConfirmation(vg)
    DarkIcon.drawNine(vg, "panel", CONFIRM.cx - CONFIRM.w * 0.5,
        CONFIRM.cy - CONFIRM.h * 0.5, CONFIRM.w, CONFIRM.h, { titleH = 104 })
    text(vg, 540, 1035, "确认一键回收", 48, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 4)
    local range = string.format(I18n.lookup("回收范围：%s装备"), filterName())
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 36)
    local rangeWidth = nvgTextBounds(vg, 0, 0, range)
    local font = math.min(36, 36 * (CONFIRM.w - 80) / math.max(1, rangeWidth))
    text(vg, 540, 1150, range, font,
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
    filterBar.draw(vg)
    local statusText = string.format(I18n.lookup("%s · 待领取 %d 件"), filterName(), state.count)
    if state.pendingCount > 0 then
        statusText = statusText .. string.format(I18n.lookup(" · 待整理 %d 件"), state.pendingCount)
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 28)
    local statusWidth = nvgTextBounds(vg, 0, 0, statusText)
    local statusFont = math.min(28, 28 * 960 / math.max(1, statusWidth))
    text(vg, 540, 360, statusText, statusFont,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 231, 210, 161, 2)

    nvgSave(vg)
    nvgIntersectScissor(vg, LIST.x, LIST.y, LIST.w, LIST.h)
    if #state.summary == 0 then
        DrawUtil.drawImageCentered(vg, imgBox, 540, 1000, 260, 260, 0.7)
        local filtered = hasFilter()
        local emptyTitle = filtered and "暂无符合筛选的装备" or "遗匣为空"
        local emptyHint = filtered and "调整上方筛选或重置查看全部" or "继续远征，新的战利品会存放在这里"
        text(vg, 540, 1210, I18n.lookup(emptyTitle), 48, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 216, 201, 163, 3)
        text(vg, 540, 1285, I18n.lookup(emptyHint), 32,
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
    local filtered = hasFilter()
    drawButton(vg, "lbp_claim_all", BTN_CLAIM_CX, BTN_Y, BTN_W, BTN_H,
        filtered and "领取勾选" or "一键领取", "gold", hasItems)
    drawButton(vg, "lbp_decompose_all", BTN_DECOMPOSE_CX, BTN_Y, BTN_W, BTN_H,
        filtered and "回收勾选" or "一键回收", "red", hasItems)
    TownPageChrome.drawBack(vg, BACK)
    if not state.confirm and state.detailIndex then
        local entry = state.summary[state.detailIndex]
        if entry and entry.equip then
            local x, y = previewBounds(state.detailIndex, entry.equip)
            EquipmentDetail.drawReadOnly(vg, entry.equip, x, y)
        end
    end
    filterBar.drawOverlay(vg)
    if state.confirm then drawConfirmation(vg) end
    -- 套装筛选弹窗（最顶层模态）
    SetFilterDialog.draw(vg)
    drawMessages(vg)
    nvgRestore(vg)
end

-- 单件参数是原 seeds 索引；批量参数兼容品质/套装，第三参是部位/类型新快照。
-- 批量接收方只处理已有 equip 的条目，待整理残留不参与领取或回收。
local function action(name, callback, value, value2, value3)
    print("[LootBoxPage] action=" .. name .. " value=" .. tostring(value))
    if callback then callback(value, value2, value3) end
end

local function entryAt(dx, dy)
    if not insideList(dx, dy) then return nil end
    local index = math.floor((dy - LIST.y + state.scrollY) / (LIST.rowH + LIST.gap)) + 1
    local entry = state.summary[index] --[[@as table?]]
    if not entry then return nil end
    local cy = rowY(index)
    if dy > cy + LIST.rowH * 0.5 or dy < cy - LIST.rowH * 0.5 then return nil end
    entry.index = index
    return entry
end

function LootBoxPage.handleHover(dx, dy)
    if state.open and SetFilterDialog.handleHover and SetFilterDialog.handleHover(dx, dy) then
        clearDetail()
        return true
    end
    if not ready() or state.confirm or state.dragging or SetFilterDialog.isOpen() or filterBar.isOpen() then
        clearDetail() return
    end
    if state.detailIndex then
        local selected = state.summary[state.detailIndex]
        if selected and selected.equip then
            local x, y, w, h = previewBounds(state.detailIndex, selected.equip)
            if dx >= x and dx <= x + w and dy >= y and dy <= y + h then return end
        end
    end
    local entry = entryAt(dx, dy)
    if not entry or not entry.equip or dx >= ACTION_CX - ACTION_W * 0.5 then
        state.hoverIndex, state.hoverSince = nil, 0
        if not state.detailPinned then state.detailIndex = nil end
        return
    end
    if state.hoverIndex ~= entry.index then
        state.hoverIndex, state.hoverSince = entry.index, time.elapsedTime
        if not state.detailPinned then state.detailIndex = nil end
        return
    end
    if not state.detailPinned and time.elapsedTime - state.hoverSince >= 0.5 then
        state.detailIndex = entry.index
    end
end

function LootBoxPage.handleRightClick(dx, dy)
    if not state.open or not ready() then return false end
    if state.confirm or SetFilterDialog.isOpen() or filterBar.isOpen() then
        clearDetail()
        return true
    end
    if state.dragging or state.dragMoved then return true end
    local entry = entryAt(dx, dy)
    if not entry or not entry.equip then return true end
    clearDetail()
    print("[LootBoxPage] right-click recycle index=" .. tostring(entry.sourceIndex))
    action("decompose", onDecomposeOne, entry.sourceIndex)
    return true
end

function LootBoxPage.handleInput(dx, dy)
    if not state.open then return false end
    if not ready() then return true end
    -- 套装筛选弹窗模态优先（打开时消费全部点击）
    if SetFilterDialog.isOpen() then return SetFilterDialog.handleInput(dx, dy) end
    if state.dragMoved then state.dragMoved = false return true end
    state.lastClickX, state.lastClickY = dx, dy
    if state.confirm then
        if DrawUtil.hitTest(dx, dy, 330, CONFIRM.btnY, 330, 96) then
            BF.trigger("lbp_cancel")
            state.confirm = false
        elseif DrawUtil.hitTest(dx, dy, 750, CONFIRM.btnY, 330, 96) then
            BF.trigger("lbp_confirm")
            state.confirm = false
            action("decomposeAll", onDecomposeAll, currentSet(), currentSetFilter(), currentDetailFilter())
        end
        return true
    end
    menuPressed = false
    if filterBar.handleInput(dx, dy) then
        clearDetail()
        return true
    end
    if state.detailIndex then
        local selected = state.summary[state.detailIndex]
        if selected and selected.equip then
            local x, y, w, h = previewBounds(state.detailIndex, selected.equip)
            if dx >= x and dx <= x + w and dy >= y and dy <= y + h then
                clearDetail()
                return true
            end
        end
    end
    if TownPageChrome.hitBack(dx, dy, BACK) then LootBoxPage.close() return true end
    -- 套装筛选入口按钮（弹窗内勾选实时生效）
    if DrawUtil.hitTest(dx, dy, SET_BTN.cx, SET_BTN.cy, SET_BTN.w, SET_BTN.h) then
        BF.trigger("lbp_set_filter")
        clearDetail()
        SetFilterDialog.open(state.setFilter, {
            getCounts = getSetCounts,
            onChange = filtersChanged,
        })
        return true
    end
    for quality = 1, QualityMark.count() do
        local cx, cy = filterCenter(quality)
        if DrawUtil.hitTest(dx, dy, cx, cy, FILTER.size, FILTER.size) then
            BF.trigger("lbp_filter_" .. quality)
            toggleQuality(quality)
            print("[LootBoxPage] 稀有度勾选切换: " .. quality
                .. " checked=" .. tostring(state.qualitySet[quality] == true))
            return true
        end
    end
    if DrawUtil.hitTest(dx, dy, BTN_CLAIM_CX, BTN_Y, BTN_W, BTN_H) then
        clearDetail()
        if state.count > 0 then
            BF.trigger("lbp_claim_all")
            action("claimAll", onClaimAll, currentSet(), currentSetFilter(), currentDetailFilter())
        end
        return true
    end
    if DrawUtil.hitTest(dx, dy, BTN_DECOMPOSE_CX, BTN_Y, BTN_W, BTN_H) then
        clearDetail()
        if state.count > 0 then BF.trigger("lbp_decompose_all") state.confirm = true end
        return true
    end
    local entry = entryAt(dx, dy)
    if entry and entry.equip then
        if DrawUtil.hitTest(dx, dy, ACTION_CX, rowY(entry.index), ACTION_W, ACTION_H) then
            BF.trigger("lbp_claim_" .. entry.index)
            clearDetail()
            action("claim", onClaimOne, entry.sourceIndex)
        elseif state.detailIndex == entry.index and state.detailPinned then
            clearDetail()
        else
            state.detailIndex, state.detailPinned = entry.index, true
            state.hoverIndex, state.hoverSince = entry.index, time.elapsedTime
            print("[LootBoxPage] detail index=" .. tostring(entry.sourceIndex))
        end
    else
        clearDetail()
    end
    -- 空白与空态仍属于左栏页，不以“点面板外”关闭。
    return true
end

function LootBoxPage.handleDragBegin(dx, dy)
    state.dragMoved = false
    if not ready() then return false end
    if state.confirm or SetFilterDialog.isOpen() then return true end
    if filterBar.isOpen() then
        menuPressed = true
        state.dragging = false
        clearDetail()
        return filterBar.handleDragBegin(dx, dy)
    end
    if not insideList(dx, dy) then return false end
    state.dragging = true
    state.dragStartY, state.dragStartScroll = dy, state.scrollY
    return true
end
function LootBoxPage.handleDragMove(dx, dy)
    if state.confirm or SetFilterDialog.isOpen() then return true end
    if filterBar.isOpen() then return filterBar.handleDragMove(dx, dy) end
    if not state.dragging then return false end
    local delta = state.dragStartY - dy
    if math.abs(delta) >= 15 then
        state.dragMoved = true
        clearDetail()
    end
    state.scrollY = state.dragStartScroll + delta
    clampScroll()
    return true
end
function LootBoxPage.handleDragEnd(dx, dy)
    if state.confirm or SetFilterDialog.isOpen() then return true end
    if filterBar.isOpen() then return filterBar.handleDragEnd(dx, dy) end
    local wasDragging = state.dragging or menuPressed
    state.dragging = false
    return wasDragging
end
function LootBoxPage.handleScroll(wheel)
    if not state.open then return false end
    if not ready() or state.confirm then return true end
    if SetFilterDialog.isOpen() then return true end  -- 弹窗打开时消费但不滚动列表
    if filterBar.isOpen() then return filterBar.handleScroll(wheel) end
    if state.dragging then state.dragMoved = true end
    state.dragging = false
    clearDetail()
    state.scrollY = state.scrollY - wheel * 100
    clampScroll()
    return true
end

return LootBoxPage
