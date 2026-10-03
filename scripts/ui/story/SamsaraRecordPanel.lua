-- ============================================================================
-- SamsaraRecordPanel - N02与征用三段的轻量剧情记录，无奖励与新选择
-- 基于 scaffold-2d 的生命周期分离；复用项目 raw NanoVG 管线，不创建上下文/帧。
-- draw / handleInput / drag 的 x,y,w,h 均为主渲染器的窗口逻辑坐标。
-- 1920×1080 CONTAIN 字号 + 全窗响应式布局；字体 sans 由主初始化创建。
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local SamsaraSlicePlayer = require("systems.SamsaraSlicePlayer")

local Panel = {}
local DESIGN_W, DESIGN_H = 1920.0, 1080.0
-- 已核实 DarkIcon 的 painter / drawNine 分支；不使用未定义的 book/close/lock 图标。
local RECORD_ICON, DOT_ICON = "nav_log", "reddot"
local BODY_FONT, BODY_LINE_HEIGHT = 38, 1.5
local BLOCK_GAP = 26

---@class SamsaraRecordViewEvidence
---@field id string
---@field title string
---@field text string
---@class SamsaraRecordView
---@field key string
---@field title string
---@field status string
---@field evidenceVisible boolean
---@field evidence SamsaraRecordViewEvidence|nil
---@field legacyContext string|nil
---@field evidences table[]
---@field unlockText string|nil

---@type NVGContextWrapper|nil
local context_ = nil
---@class SamsaraRecordPanelState
---@field open boolean
---@field scroll number
---@field maxScroll number
---@field frameW number
---@field frameH number
---@field pointerDown boolean
---@field scrollDrag boolean
---@field dragged boolean
---@field startX number
---@field startY number
---@field startScroll number
---@field requestFailed boolean
---@field contentSignature string
---@field selectedKey string
---@type SamsaraRecordPanelState
local state = {
    open = false,
    scroll = 0,
    maxScroll = 0,
    frameW = DESIGN_W,
    frameH = DESIGN_H,
    pointerDown = false,
    scrollDrag = false,
    dragged = false,
    startX = 0,
    startY = 0,
    startScroll = 0,
    requestFailed = false,
    contentSignature = "",
    selectedKey = "samsara.log_leaf",
}

-- 均以“扩展设计屏幕”定位，宽高比变化时不拉伸文字/图标。
local function layout(w, h)
    local fw = (type(w) == "number" and w > 0) and w or DESIGN_W --[[@as number]]
    local fh = (type(h) == "number" and h > 0) and h or DESIGN_H --[[@as number]]
    local scale = math.min(fw / DESIGN_W, fh / DESIGN_H) --[[@as number]]
    local sw, sh = fw / scale, fh / scale
    local pw = sw * 0.875
    local ph = sh * (13 / 15)
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    return {
        scale = scale, sw = sw, sh = sh,
        x = px, y = py, w = pw, h = ph,
        closeX = px + pw - 220, closeY = py + 36, closeW = 176, closeH = 84,
        contentX = px + 64, contentY = py + 352,
        contentW = pw - 148, contentH = ph - 506,
        tabsY = py + 150, tabsW = (pw - 148) / 4,
        actionX = px + pw - 360, actionY = py + ph - 120, actionW = 296, actionH = 84,
    }
end

local function inRect(x, y, rx, ry, rw, rh)
    return DrawUtil.hitTest(x, y, rx + rw * 0.5, ry + rh * 0.5, rw, rh)
end

local function clampScroll()
    state.scroll = math.max(0, math.min(state.maxScroll, state.scroll))
end

---@return SamsaraRecordView
local function getRecord()
    return SamsaraSlicePlayer.getRecord(state.selectedKey) --[[@as SamsaraRecordView]]
end

--- 只切换档案展示，不排首读或回看，不触碰完成记录。
function Panel.selectRecord(key)
    for _, record in ipairs(SamsaraSlicePlayer.getRecords()) do
        if record.key == key then
            state.selectedKey = key
            state.scroll, state.maxScroll = 0, 0
            state.contentSignature = ""
            state.requestFailed = false
            return true
        end
    end
    return false
end

---@param record SamsaraRecordView
local function statusText(record)
    if record.status == "pending" then return "待阅" end
    if record.status == "finished" then return "已读" end
    if record.status == "skipped" then return "已跳过" end
    if record.status == "locked" then return record.unlockText or "暂未开放" end
    return "暂未开放"
end

---@param record SamsaraRecordView
local function canRead(record)
    return (record.status == "pending" or record.status == "finished" or record.status == "skipped")
        and not SamsaraSlicePlayer.isSavePending()
end

---@param record SamsaraRecordView
local function actionText(record)
    if SamsaraSlicePlayer.isSavePending() then return "保存中" end
    if record.status == "pending" then return "待阅" end
    if record.status == "finished" or record.status == "skipped" then return "回看" end
    return "暂未开放"
end

---@param record SamsaraRecordView
local function contentBlocks(record)
    local blocks = {}
    local function add(text, font, muted)
        blocks[#blocks + 1] = { text = text, font = font or BODY_FONT, muted = muted == true }
    end

    if record.status == "unsupported" then
        add("这份剧情记录尚未开放。", BODY_FONT)
    elseif record.status == "locked" then
        add((record.unlockText or "暂未开放") .. "。", BODY_FONT)
        add("尚未处理剧情，原件正文暂不公开。", 32, true)
    elseif record.status == "pending" then
        add("有一段剧情待阅。点击下方“待阅”进入。", BODY_FONT)
        add("处理剧情后，这里会留下普通原件与来源。", 32, true)
    elseif record.status == "finished" or record.status == "skipped" then
        add(record.status == "skipped" and "此前已跳过剧情，可点击“回看”重新阅读。"
            or "此前已读剧情，可点击“回看”重新阅读。", 32, true)
    else
        add("这份剧情记录尚未开放。", BODY_FONT)
    end
    if record.status ~= "unsupported" then
        -- legacyContext只描述旧日志来源，不能据此冒充N02已读或封锁独立切片。
        if record.legacyContext == "legacy_claimed_unknown" then
            add("旧日志阅读状态未知；夹页可独立核对。", 32, true)
        elseif record.legacyContext == "unavailable" then
            add("旧日志来源暂不可用；当前记录可独立阅读。", 32, true)
        end
    end

    if record.key ~= "samsara.log_leaf" then
        -- 原件、核验与人员卷各服从数据层公开标记，未处理的后段不泄露正文。
        for _, item in ipairs(record.evidences or {}) do
            add(item.id .. " · " .. item.title, 40)
            local source = item.source == "player_record" and "普通2-4 · 货牌记录"
                or (item.source == "case_archive" and "铁匠保存的案件副本" or "征用签发底档")
            add("来源：" .. source, 32, true)
            add(item.text)
            if item.annotation then add("N12 · 来源核验", 38); add(item.annotation) end
            if item.continuation then add("N14 · 第二次续令", 38); add(item.continuation) end
            if item.people then add("N14 · 人员卷", 38); add(item.people) end
        end
        if #(record.evidences or {}) == 0 then add("原件正文暂不公开。", 32, true) end
        add("后续核验未开放。", 32, true)
        return blocks
    end
    -- N02原件保持既有公开规则，回看不会补读高难度批注。
    local evidence = record.evidence
    if (record.status == "finished" or record.status == "skipped")
        and record.evidenceVisible == true and evidence and evidence.id == "E01" then
        add("E01 · 普通原件", 40)
        if evidence.title and evidence.title ~= "" then add(evidence.title, 38) end
        add("来源：普通1-4 · N02剧情记录", 32, true)
        if evidence.text and evidence.text ~= "" then add(evidence.text, BODY_FONT) end
        add("下阶段批注未开放。", 32, true)
    elseif record.status == "finished" or record.status == "skipped" then
        add("原件正文暂不公开。", 32, true)
        add("下阶段批注未开放。", 32, true)
    end
    return blocks
end

--- 仅保留主上下文引用；不创建字体、图片、事件订阅或独立 NanoVG 帧。
---@param vg NVGContextWrapper
function Panel.init(vg)
    context_ = vg
end

function Panel.open()
    if state.open then return end
    state.open = true
    state.scroll, state.maxScroll = 0, 0
    state.pointerDown, state.scrollDrag, state.dragged = false, false, false
    state.requestFailed = false
    state.contentSignature = ""
end

function Panel.close()
    state.open = false
    state.pointerDown, state.scrollDrag, state.dragged = false, false, false
end

---@return boolean
function Panel.isOpen()
    return state.open
end

local function drawButton(vg, x, y, w, h, text, enabled)
    DarkIcon.drawNine(vg, "btn", x, y, w, h, { accent = "gold", alpha = enabled and 1 or 0.45 })
    DrawUtil.drawTextStroke(vg, x + w * 0.5, y + h * 0.5, text, 36,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        enabled and 244 or 150, enabled and 237 or 138, enabled and 224 or 110, 2)
end

--- 在主帧最终模态层调用；w/h 必须与输入传入的窗口逻辑尺寸一致。
---@param vg NVGContextWrapper
---@param w number
---@param h number
function Panel.draw(vg, w, h)
    if not state.open then return end
    local ctx = vg or context_
    if not ctx then return end
    state.frameW, state.frameH = w, h
    local l = layout(w, h)
    local record = getRecord()
    local blocks = contentBlocks(record)

    nvgSave(ctx)
    nvgIntersectScissor(ctx, 0, 0, w, h)
    nvgScale(ctx, l.scale, l.scale)
    DrawUtil.drawRoundedRectCentered(ctx, l.sw * 0.5, l.sh * 0.5, l.sw, l.sh, 0, 0, 0, 0, 190)
    DarkIcon.drawNine(ctx, "panel", l.x, l.y, l.w, l.h, { titleH = 144, radius = 24 })
    DarkIcon.draw(ctx, RECORD_ICON, l.x + 90, l.y + 72, 68, 1)
    DrawUtil.drawTextStroke(ctx, l.x + 146, l.y + 72, "剧情记录", 54,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 244, 237, 224, 3)
    drawButton(ctx, l.closeX, l.closeY, l.closeW, l.closeH, "关闭", true)

    local labels = { "日志夹页", "货牌核验", "灰印征用令", "人员卷" }
    for index, item in ipairs(SamsaraSlicePlayer.getRecords()) do
        local tabX = l.contentX + (index - 1) * l.tabsW
        drawButton(ctx, tabX, l.tabsY, l.tabsW - 12, 64, labels[index] or item.title,
            item.key == state.selectedKey)
        if item.status == "pending" then
            DarkIcon.draw(ctx, DOT_ICON, tabX + l.tabsW - 30, l.tabsY + 10, 18, 1)
        end
    end
    local title = record.status == "unsupported" and "剧情记录" or record.title
    DrawUtil.drawTextStroke(ctx, l.contentX, l.y + 266, title or "剧情记录", 40,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 238, 216, 161, 2)
    DrawUtil.drawTextStroke(ctx, l.contentX, l.y + 320, statusText(record), 32,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 216, 201, 163, 2)
    if record.status == "pending" then
        DarkIcon.draw(ctx, DOT_ICON, l.x + l.w - 84, l.y + 226, 28, 1)
    end

    -- 每块按真实换行高度排版；长正文滚动，E01短正文不强制滚动。
    local signatureParts = { tostring(l.contentW) }
    local totalH = 0
    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgTextLineHeight(ctx, BODY_LINE_HEIGHT)
    for _, block in ipairs(blocks) do
        nvgFontSize(ctx, block.font)
        local bounds = nvgTextBoxBounds(ctx, 0, 0, l.contentW - 12, block.text)
        local measuredH = bounds and (bounds[4] - math.min(0, bounds[2])) or block.font * BODY_LINE_HEIGHT
        block.height = math.max(block.font * BODY_LINE_HEIGHT, measuredH) + BLOCK_GAP
        totalH = totalH + block.height
        signatureParts[#signatureParts + 1] = block.text
    end
    local signature = table.concat(signatureParts, "\n")
    if signature ~= state.contentSignature then
        state.contentSignature = signature
        state.scroll = 0
        state.pointerDown, state.scrollDrag, state.dragged = false, false, false
    end
    state.maxScroll = math.max(0, totalH - l.contentH)
    clampScroll()

    nvgSave(ctx)
    nvgIntersectScissor(ctx, l.contentX, l.contentY, l.contentW, l.contentH)
    local y = l.contentY - state.scroll
    for _, block in ipairs(blocks) do
        nvgFontSize(ctx, block.font)
        nvgFillColor(ctx, block.muted and nvgRGBA(180, 166, 138, 255) or nvgRGBA(244, 237, 224, 255))
        nvgTextBox(ctx, l.contentX, y, l.contentW - 12, block.text, nil)
        y = y + block.height
    end
    nvgRestore(ctx)

    if state.maxScroll > 0 then
        local trackX = l.contentX + l.contentW + 18
        local thumbH = math.max(44, l.contentH * l.contentH / totalH) --[[@as number]]
        local thumbY = l.contentY + (l.contentH - thumbH) * state.scroll / state.maxScroll
        DrawUtil.drawRoundedRectCentered(ctx, trackX, l.contentY + l.contentH * 0.5,
            8, l.contentH, 4, 48, 42, 34, 255)
        DrawUtil.drawRoundedRectCentered(ctx, trackX, thumbY + thumbH * 0.5,
            8, thumbH, 4, 201, 151, 59, 255)
    end
    DrawUtil.drawTextStroke(ctx, l.contentX, l.actionY + 42,
        state.requestFailed and "暂时无法打开，请稍后重试。" or (state.maxScroll > 0 and "滑动或滚轮阅读正文" or "普通原件记录"),
        30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 180, 166, 138, 2)
    drawButton(ctx, l.actionX, l.actionY, l.actionW, l.actionH, actionText(record), canRead(record))
    nvgRestore(ctx)
end

--- 全窗模态吞点击；只有关闭/待阅/回看会触发操作，遮罩点击不穿透。
---@param x number
---@param y number
---@param w number
---@param h number
---@return boolean consumed
function Panel.handleInput(x, y, w, h)
    if not state.open then return false end
    state.frameW, state.frameH = w, h
    if state.dragged then
        state.dragged = false
        return true
    end
    local l = layout(w, h)
    local dx, dy = x / l.scale, y / l.scale
    if inRect(dx, dy, l.closeX, l.closeY, l.closeW, l.closeH) then
        Panel.close()
        return true
    end
    for index, record in ipairs(SamsaraSlicePlayer.getRecords()) do
        local tabX = l.contentX + (index - 1) * l.tabsW
        if inRect(dx, dy, tabX, l.tabsY, l.tabsW - 12, 64) then
            Panel.selectRecord(record.key)
            return true
        end
    end
    if inRect(dx, dy, l.actionX, l.actionY, l.actionW, l.actionH) then
        local record = getRecord()
        if canRead(record) then
            -- 仅排当前key；真正show由主仲裁在下一帧执行，不在输入回调内播剧情。
            if SamsaraSlicePlayer.requestRead(record.key) then
                Panel.close()
            else
                state.requestFailed = true
            end
        end
    end
    return true
end

---@param delta number 正值向上，负值向下（引擎滚轮方向）
---@return boolean consumed
function Panel.handleWheel(delta)
    if not state.open then return false end
    state.scroll = state.scroll - delta * 76
    clampScroll()
    return true
end

--- 手势坐标仍为窗口逻辑坐标，使用最近draw/handleInput的w/h逆映射。
---@param x number
---@param y number
---@return boolean consumed
function Panel.handleDragBegin(x, y)
    if not state.open then return false end
    local l = layout(state.frameW, state.frameH)
    state.pointerDown = true
    state.dragged = false
    state.startX, state.startY = x, y
    state.startScroll = state.scroll
    state.scrollDrag = inRect(x / l.scale, y / l.scale,
        l.contentX, l.contentY, l.contentW + 30, l.contentH)
    return true
end

---@param x number
---@param y number
---@return boolean consumed
function Panel.handleDragMove(x, y)
    if not state.open then return false end
    if state.pointerDown then
        local l = layout(state.frameW, state.frameH)
        local dx, dy = (x - state.startX) / l.scale, (y - state.startY) / l.scale
        if dx * dx + dy * dy > 12 * 12 then state.dragged = true end
        if state.scrollDrag and state.dragged then
            state.scroll = state.startScroll - dy
            clampScroll()
        end
    end
    return true
end

--- 返回是否真的拖动，而不是“是否吞事件”；主输入仲裁据此避免拖后误点按钮。
---@return boolean dragged
function Panel.handleDragEnd()
    local dragged = state.pointerDown and state.dragged
    state.pointerDown, state.scrollDrag, state.dragged = false, false, false
    return dragged
end

return Panel
