-- ============================================================================
-- SetFilterDialog - 套装筛选弹窗（仓库装备 tab / 遗匣页共用）
-- 12 套装 + 「无套装」共 13 行，多选勾选；勾选实时写回调用方持有的集合表
-- （[setId]=true，"none"=无套装；空集合=不筛选）。模态：打开时消费全部点击。
-- 坐标系：1080×2400 左栏页（与 LootBoxPage / BackpackPanel 一致）。
-- ============================================================================
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local EquipmentSetConfig = require("config.EquipmentSetConfig")
local BF = require("systems.ButtonFeedback")
local I18n = require("core.I18n")
local EquipmentSetIcon = require("ui.widget.EquipmentSetIcon")
local KeywordText = require("ui.widget.KeywordText")

local SetFilterDialog = {}
local text = DrawUtil.drawTextStroke

-- 「无套装」在集合表中的特殊键（装备模板无套装归属时用）
SetFilterDialog.NONE_KEY = "none"

local PANEL = { cx = 540, cy = 1200, w = 940, h = 1560, titleH = 110 }
local ROW = { top = 566, h = 88, x = 70, w = 940 }
local DOT = { cx = 140, r = 18 }
local NAME_X = 186
local CHECK = { cx = 938, size = 54 }
local COUNT_X = CHECK.cx - CHECK.size * 0.5 - 32
local BTN = { cy = 1836, w = 300, h = 96, clearCX = 330, doneCX = 750 }
-- 图标热区与整行筛选热区分离；说明卡始终限制在左栏设计区域内。
local ICON = { cx = DOT.cx + 24, size = 58, hit = 72 }
local TIP = { w = 680, pad = 24, gap = 14, margin = 24, maxH = 2352 }

local imgCheck = -1
local inited = false

local open_ = false
---@type table<string, boolean>|nil
local sel_ = nil
---@type (fun()|nil)
local onChange_ = nil
---@type (fun()|nil)
local onDone_ = nil
---@type (fun(): table<string, integer>)|nil
local getCounts_ = nil
---@type string|nil
local hoverKey_ = nil
---@type string|nil
local pinnedKey_ = nil
---@type { key: string, x: number, y: number, w: number, h: number }|nil
local tipBounds_ = nil
-- 复用装备描述的完整句子本地化、UTF-8 折行与金色关键词，不创建第二套 UI 管线。
local tipText_ = KeywordText.new()

local function clearExplanation()
    hoverKey_, pinnedKey_, tipBounds_ = nil, nil, nil
    tipText_:clear()
end

local function ensureInit(vg)
    if inited or not vg then return end
    inited = true
    imgCheck = nvgCreateImage(vg, "image/货币道具/UI_icon_GOU.png", 0) or -1
end

--- 行数据（固定顺序）：12 套装 + 无套装
---@return { key: string, name: string, color: number[]|nil }[]
local function buildRows()
    local rows = {}
    local order = EquipmentSetConfig.orderedSetIds()
    for i = 1, #order do
        local def = EquipmentSetConfig.get(order[i])
        if def then
            rows[#rows + 1] = { key = order[i], name = def.name, color = def.color }
        end
    end
    rows[#rows + 1] = { key = SetFilterDialog.NONE_KEY, name = "无套装", color = nil }
    return rows
end

local function rowCount()
    return #EquipmentSetConfig.orderedSetIds() + 1
end

--- 打开弹窗。sel 为调用方持有的集合表引用，勾选直接改写该表。
---@param sel table<string, boolean> 勾选集合：键=套装id 或 "none"（无套装）；空集合=全部
---@param opts? { onChange?: fun(), onDone?: fun(), getCounts?: fun(): table<string, integer> }
function SetFilterDialog.open(sel, opts)
    clearExplanation()
    sel_ = sel
    onChange_ = opts and opts.onChange or nil
    onDone_ = opts and opts.onDone or nil
    getCounts_ = opts and opts.getCounts or nil
    open_ = true
    require("systems.GameSFX").playUIMove(1)
    print("[SetFilterDialog] open")
end

function SetFilterDialog.close()
    clearExplanation()
    if not open_ then return end
    open_ = false
    sel_, onChange_, onDone_, getCounts_ = nil, nil, nil, nil
    print("[SetFilterDialog] close")
end

function SetFilterDialog.isOpen() return open_ end

--- 当前选中数量（供入口按钮角标文本）
---@param sel table<string, boolean>|nil
---@return integer
function SetFilterDialog.countSelected(sel)
    local source = sel or sel_
    if not source then return 0 end
    local n = 0
    for _, checked in pairs(source) do
        if checked then n = n + 1 end
    end
    return n
end

local function rowCY(index)
    return ROW.top + (index - 1) * ROW.h + ROW.h * 0.5
end

local function iconRow(dx, dy)
    for index, row in ipairs(buildRows()) do
        if DrawUtil.hitTest(dx, dy, ICON.cx, rowCY(index), ICON.hit, ICON.hit) then
            return row
        end
    end
    return nil
end

local function insideTip(dx, dy)
    local bounds = tipBounds_
    if not bounds or bounds.key ~= (hoverKey_ or pinnedKey_) then return false end
    return DrawUtil.hitTest(dx, dy, bounds.x + bounds.w * 0.5,
        bounds.y + bounds.h * 0.5, bounds.w, bounds.h)
end

--- 当前说明的只读快照；原始完整描述直接来自套装表，永不反写业务数据。
---@return { key: string, name: string, pinned: boolean, color: number[], effects: { pieces: integer, desc: string }[], note: string|nil }|nil
function SetFilterDialog.getExplanation()
    local key = hoverKey_ or pinnedKey_
    if not open_ or not key then return nil end
    local def = EquipmentSetConfig.get(key)
    if key ~= SetFilterDialog.NONE_KEY and not def then return nil end
    local effects = {}
    if def then
        for _, pieces in ipairs({ 2, 4, 6 }) do
            effects[#effects + 1] = { pieces = pieces, desc = def["desc" .. pieces] or "暂无效果说明" }
        end
    end
    return {
        key = key, name = def and def.name or "无套装", pinned = key == pinnedKey_,
        color = def and { def.color[1], def.color[2], def.color[3] } or { 181, 166, 143 },
        effects = effects,
        note = not def and "无套装装备不计入任何套装的件数，不提供2/4/6件套装效果。" or nil,
    }
end

--- 调用方在自身 hover 逻辑之前转交；移出左栏传 (-1,-1)，只清悬停不清点击钉住。
--- 打开时恒返回 true，避免穿透到仓库/遗匣列表的装备说明。
---@param dx number 左栏设计坐标
---@param dy number 左栏设计坐标
---@return boolean
function SetFilterDialog.handleHover(dx, dy)
    if not open_ then return false end
    local row = iconRow(dx, dy)
    if row then
        if hoverKey_ ~= row.key then tipBounds_ = nil end
        hoverKey_ = row.key
    elseif not insideTip(dx, dy) then
        if hoverKey_ then tipBounds_ = nil end
        hoverKey_ = nil
    end
    return true
end

-- 描述/标题/提示统一用 KeywordText 完整折行；极长文案缩放整卡而不裁掉末尾。
local function explanationLayout(vg, explanation)
    local width = TIP.w - TIP.pad * 2
    local blocks = {}
    local function add(content, font, lineH, color, gap)
        local height = tipText_:measureHeight(vg, content, width, font, lineH)
        blocks[#blocks + 1] = { text = content, font = font, lineH = lineH,
            height = height, color = color, gap = gap }
    end
    add(explanation.name, 36, 46, explanation.color, 10)
    if explanation.note then
        add(explanation.note, 30, 40, { 232, 220, 200 }, 10)
    else
        for _, effect in ipairs(explanation.effects) do
            add(I18n.format("%d件", effect.pieces), 28, 36, explanation.color, 4)
            add(effect.desc, 30, 40, { 232, 220, 200 }, 14)
        end
    end
    add(explanation.pinned and "已钉住 · 再点图标取消" or "点击图标钉住说明", 24, 32,
        { 181, 166, 143 }, 0)
    local height = TIP.pad * 2
    for _, block in ipairs(blocks) do height = height + block.height + block.gap end
    return blocks, height
end

local function drawExplanation(vg)
    local explanation = SetFilterDialog.getExplanation()
    if not explanation then tipBounds_ = nil return end
    local anchorY = PANEL.cy
    for index, row in ipairs(buildRows()) do
        if row.key == explanation.key then anchorY = rowCY(index) break end
    end
    local blocks, contentH = explanationLayout(vg, explanation)
    local scale = math.min(1, (TIP.maxH - 4) / contentH)
    if scale < 1 then
        -- 字体栅格测量会受缩放影响；在最终缩放下重测，不能沿用缩放前的行数裁掉尾行。
        for _ = 1, 4 do
            nvgSave(vg)
            nvgScale(vg, scale, scale)
            blocks, contentH = explanationLayout(vg, explanation)
            nvgRestore(vg)
            if contentH * scale <= TIP.maxH then break end
            scale = scale * (TIP.maxH - 4) / (contentH * scale)
        end
    end
    local width, height = TIP.w * scale, contentH * scale
    local left = math.max(TIP.margin, math.min(ICON.cx + ICON.hit * 0.5 + TIP.gap,
        1080 - TIP.margin - width))
    -- 优先放在来源行上方，顶端空间不足翻到下方，避免遮住同一行名称/勾选框。
    local above = anchorY - ROW.h * 0.5 - TIP.gap - height
    local desiredTop = above >= TIP.margin and above or anchorY + ROW.h * 0.5 + TIP.gap
    local top = math.max(TIP.margin, math.min(desiredTop, 2400 - TIP.margin - height))
    tipBounds_ = { key = explanation.key, x = left, y = top, w = width, h = height }
    nvgSave(vg)
    nvgTranslate(vg, left, top)
    nvgScale(vg, scale, scale)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 0, 0, TIP.w, contentH, 16)
    nvgFillColor(vg, nvgRGBA(31, 23, 17, 250))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(explanation.color[1], explanation.color[2], explanation.color[3], 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    local y = TIP.pad
    tipText_:beginFrame()
    for _, block in ipairs(blocks) do
        tipText_.textColor = block.color
        -- 说明卡整体消费点击；这里只复用关键词配色，不嵌套会越界的第二层弹窗。
        tipText_:draw(vg, block.text, TIP.pad, y, TIP.w - TIP.pad * 2,
            block.font, block.lineH, nil, true, { interactive = false })
        y = y + block.height + block.gap
    end
    nvgRestore(vg)
end

local function toggle(key)
    if not sel_ then return end
    if sel_[key] then
        sel_[key] = nil
    else
        sel_[key] = true
    end
    print("[SetFilterDialog] toggle " .. key .. " -> " .. tostring(sel_[key] == true))
    if onChange_ then onChange_() end
end

local function clearAll()
    if not sel_ then return end
    for key in pairs(sel_) do sel_[key] = nil end
    print("[SetFilterDialog] clear all")
    if onChange_ then onChange_() end
end

local function drawButton(vg, id, cx, cy, w, h, label, accent)
    local feedback = BF.begin(vg, id, cx, cy, w, h)
    DarkIcon.drawNine(vg, "btn", cx - w * 0.5, cy - h * 0.5, w, h, { accent = accent })
    local caption = I18n.lookup(label)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 38)
    local captionWidth = nvgTextBounds(vg, 0, 0, caption)
    local fontSize = math.min(38, 38 * (w - 20) / math.max(1, captionWidth))
    text(vg, cx, cy, caption, fontSize, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 3)
    BF.finish(vg, feedback)
end

function SetFilterDialog.draw(vg)
    if not open_ then return end
    ensureInit(vg)
    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    DarkIcon.drawNine(vg, "panel", PANEL.cx - PANEL.w * 0.5, PANEL.cy - PANEL.h * 0.5,
        PANEL.w, PANEL.h, { titleH = PANEL.titleH })
    text(vg, 540, PANEL.cy - PANEL.h * 0.5 + PANEL.titleH * 0.5, "套装筛选", 48,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 4)

    local rows = buildRows()
    -- 每帧只统计一次，掉落/分解/领取后不必重开弹窗即可看到最新数量。
    local counts = getCounts_ and getCounts_() or nil
    for index, row in ipairs(rows) do
        local cy = rowCY(index)
        local checked = sel_ and sel_[row.key] == true
        local feedback = BF.begin(vg, "sfd_row_" .. row.key, PANEL.cx, cy, ROW.w - 60, ROW.h - 12)
        -- 行底（选中微亮）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ROW.x + 24, cy - ROW.h * 0.5 + 6, ROW.w - 48, ROW.h - 12, 12)
        nvgFillColor(vg, nvgRGBA(255, 244, 214, checked and 26 or 12))
        nvgFill(vg)
        -- 图标悬停/钉住只强调徽记，不借用整行的筛选按压反馈。
        if row.key == hoverKey_ or row.key == pinnedKey_ then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ICON.cx - ICON.hit * 0.5, cy - ICON.hit * 0.5,
                ICON.hit, ICON.hit, 12)
            nvgFillColor(vg, nvgRGBA(255, 215, 110, 38))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 215, 110, 220))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
        -- 套装徽记取代色点；无套装或加载失败保持灰圈/配色兜底。
        if not row.color or not EquipmentSetIcon.draw(vg, row.key, ICON.cx, cy, ICON.size, 1) then
            nvgBeginPath(vg)
            nvgCircle(vg, DOT.cx + 24, cy, DOT.r)
            local color = row.color or { 90, 84, 74 }
            nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 255))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(160, 150, 130, 200))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
        -- 名称与数量分列，译名过长时裁在名称区，不能遮住数量/勾选框。
        nvgSave(vg)
        if counts then nvgIntersectScissor(vg, NAME_X + 34, cy - 30, 470, 60) end
        text(vg, NAME_X + 34, cy, row.name, 36, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            row.color and row.color[1] or 181, row.color and row.color[2] or 166,
            row.color and row.color[3] or 143, 3)
        nvgRestore(vg)
        if counts then
            local count = counts[row.key] or 0
            local countText = tostring(count)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 34)
            local countWidth = nvgTextBounds(vg, 0, 0, countText)
            local fontSize = math.min(34, 34 * 164 / math.max(1, countWidth))
            text(vg, COUNT_X, cy, countText, fontSize, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                count > 0 and 244 or 140, count > 0 and 237 or 132, count > 0 and 224 or 116, 2)
        end
        -- 勾选框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, CHECK.cx - CHECK.size * 0.5, cy - CHECK.size * 0.5,
            CHECK.size, CHECK.size, 8)
        nvgFillColor(vg, nvgRGBA(16, 13, 10, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(190, 155, 104, 200))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        if checked and imgCheck >= 0 then
            DrawUtil.drawImageCentered(vg, imgCheck, CHECK.cx, cy, 40, 40, 1)
        end
        BF.finish(vg, feedback)
    end

    drawButton(vg, "sfd_clear", BTN.clearCX, BTN.cy, BTN.w, BTN.h, "清空", "gold")
    drawButton(vg, "sfd_done", BTN.doneCX, BTN.cy, BTN.w, BTN.h, "完成", "green")
    -- 说明卡最后绘制，不能被后续筛选行/底部按钮盖住。
    drawExplanation(vg)
end

--- 模态输入：打开时恒返回 true（消费全部点击）。
---@return boolean
function SetFilterDialog.handleInput(dx, dy)
    if not open_ then return false end
    -- 徽记点击只开/钉住说明，绝不写勾选集合或触发 onChange。
    local icon = iconRow(dx, dy)
    if icon then
        local same = pinnedKey_ == icon.key
        clearExplanation()
        if not same then pinnedKey_ = icon.key end
        print("[SetFilterDialog] explanation " .. icon.key .. " pinned=" .. tostring(not same))
        return true
    end
    -- 浮卡遮住的底层行/按钮不能收到点击；点击卡外则关闭说明并按原筛选契约处理。
    if insideTip(dx, dy) then return true end
    clearExplanation()
    if DrawUtil.hitTest(dx, dy, BTN.clearCX, BTN.cy, BTN.w, BTN.h) then
        BF.trigger("sfd_clear")
        clearAll()
        return true
    end
    if DrawUtil.hitTest(dx, dy, BTN.doneCX, BTN.cy, BTN.w, BTN.h) then
        BF.trigger("sfd_done")
        local cb = onDone_
        SetFilterDialog.close()
        if cb then cb() end
        return true
    end
    -- 行点击（整行热区）
    local n = rowCount()
    for index = 1, n do
        local cy = rowCY(index)
        if DrawUtil.hitTest(dx, dy, PANEL.cx, cy, ROW.w - 40, ROW.h - 8) then
            local rows = buildRows()
            local row = rows[index]
            if row then
                BF.trigger("sfd_row_" .. row.key)
                toggle(row.key)
            end
            return true
        end
    end
    -- 面板外点击 = 完成关闭（勾选已实时生效）
    if not DrawUtil.hitTest(dx, dy, PANEL.cx, PANEL.cy, PANEL.w, PANEL.h) then
        local cb = onDone_
        SetFilterDialog.close()
        if cb then cb() end
    end
    return true
end

return SetFilterDialog
