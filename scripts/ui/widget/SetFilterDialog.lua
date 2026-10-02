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

local SetFilterDialog = {}
local text = DrawUtil.drawTextStroke

-- 「无套装」在集合表中的特殊键（装备模板无套装归属时用）
SetFilterDialog.NONE_KEY = "none"

local PANEL = { cx = 540, cy = 1200, w = 940, h = 1560, titleH = 110 }
local ROW = { top = 566, h = 88, x = 70, w = 940 }
local DOT = { cx = 140, r = 18 }
local NAME_X = 186
local CHECK = { cx = 938, size = 54 }
local BTN = { cy = 1836, w = 300, h = 96, clearCX = 330, doneCX = 750 }

local imgCheck = -1
local inited = false

local open_ = false
---@type table<string, boolean>|nil
local sel_ = nil
---@type (fun()|nil)
local onChange_ = nil
---@type (fun()|nil)
local onDone_ = nil

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
---@param opts? { onChange?: fun(), onDone?: fun() }
function SetFilterDialog.open(sel, opts)
    sel_ = sel
    onChange_ = opts and opts.onChange or nil
    onDone_ = opts and opts.onDone or nil
    open_ = true
    require("systems.GameSFX").playUIMove(1)
    print("[SetFilterDialog] open")
end

function SetFilterDialog.close()
    if not open_ then return end
    open_ = false
    sel_, onChange_, onDone_ = nil, nil, nil
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
    for index, row in ipairs(rows) do
        local cy = rowCY(index)
        local checked = sel_ and sel_[row.key] == true
        local feedback = BF.begin(vg, "sfd_row_" .. row.key, PANEL.cx, cy, ROW.w - 60, ROW.h - 12)
        -- 行底（选中微亮）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ROW.x + 24, cy - ROW.h * 0.5 + 6, ROW.w - 48, ROW.h - 12, 12)
        nvgFillColor(vg, nvgRGBA(255, 244, 214, checked and 26 or 12))
        nvgFill(vg)
        -- 套装徽记取代色点；无套装或加载失败保持灰圈/配色兜底。
        if not row.color or not EquipmentSetIcon.draw(vg, row.key, DOT.cx + 24, cy, 58, 1) then
            nvgBeginPath(vg)
            nvgCircle(vg, DOT.cx + 24, cy, DOT.r)
            local color = row.color or { 90, 84, 74 }
            nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 255))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(160, 150, 130, 200))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
        -- 名称
        text(vg, NAME_X + 34, cy, row.name, 36, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            row.color and row.color[1] or 181, row.color and row.color[2] or 166,
            row.color and row.color[3] or 143, 3)
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
end

--- 模态输入：打开时恒返回 true（消费全部点击）。
---@return boolean
function SetFilterDialog.handleInput(dx, dy)
    if not open_ then return false end
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
