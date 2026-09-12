-- ============================================================================
-- AnnouncementPanel - 公告弹窗面板
-- 全屏遮罩 + 九宫格弹窗 + 可滚动公告列表
-- ============================================================================

local GameConfig = require("config.GameConfig")
local DrawUtil   = require("core.DrawUtil")
local DarkIcon   = require("core.DarkIcon")  -- [暗黑化 P1-B2] 矢量九宫格面板

local Panel = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 遮罩
local MASK_A = 128  -- 50% 不透明度

-- 弹窗背景（九宫格 UI_TY_EJQRK）
local BG = {
    CX = 540, CY = 1175, W = 950, H = 1447,
    IT = 180, IL = 40, IR = 40, IB = 50,
}

-- 标题 "公告"
local TTL = {
    X = 540, Y = 520, FONT = 60, SW = 6,
    SR = 0x59, SG = 0x32, SB = 0x19,
}

-- 内容背景框
local CONTENT = {
    CX = 540, CY = 1228, W = 850, H = 1200, R = 16,
    BG_A = 13,  -- 5% of 255 ≈ 13
}

-- 公告条目（基于第一条绝对坐标 → 相对偏移量）
-- 第一条条目中心 Y = 757（用户指定）
local FIRST_CY = 757

local ENTRY = {
    CX = 540, W = 810, H = 220, GAP = 13,
    -- 图标 UI_ICON_GG.png: X243 Y752 → 偏移 (243, 752-757=-5)
    ICON_CX = 243, ICON_CY_OFF = -5, ICON_W = 104, ICON_H = 104,
    -- 标题: X左对齐338 Y718 → 偏移 (338, 718-757=-39)
    TITLE_X = 338, TITLE_Y_OFF = -39, TITLE_FONT = 48,
    TITLE_R = 0x5f, TITLE_G = 0x37, TITLE_B = 0x37,
    -- 分割线: X605 Y757 530*4 圆角2 颜色8d5f41 不透明度40% → 偏移 (605, 0)
    DIV_CX = 605, DIV_Y_OFF = 0, DIV_W = 530, DIV_H = 4, DIV_ROUND = 2,
    DIV_R = 0x8d, DIV_G = 0x5f, DIV_B = 0x41, DIV_A = 102,  -- 40% of 255
    -- 日期: X338 (同标题左对齐) Y792 → 偏移 (338, +35)
    DATE_X = 338, DATE_Y_OFF = 35, DATE_FONT = 38,
    DATE_R = 0xc6, DATE_G = 0xa9, DATE_B = 0x97,
}
ENTRY.STEP = ENTRY.H + ENTRY.GAP  -- 233

-- 内容区域顶
local CONTENT_TOP = CONTENT.CY - CONTENT.H * 0.5  -- 628

-- 裁剪区域
local CLIP = {
    TOP = CONTENT_TOP + 10,  -- 638
    BOT = 1800,              -- 用户指定截断位置
}
CLIP.H = CLIP.BOT - CLIP.TOP

-- ======================== 详情视图布局 ========================

local DETAIL = {
    -- 5. 公告标题: X540 Y677 字号48 [暗黑化: 深棕→骨白，适配暗底]
    TITLE_X = 540, TITLE_Y = 677, TITLE_FONT = 48,
    TITLE_R = 0xd8, TITLE_G = 0xc9, TITLE_B = 0xa3,
    -- 6. 正文段落区域: X540 Y1221 746×958 字号36 [暗黑化: 深棕→浅棕]
    PARA_CX = 540, PARA_CY = 1221, PARA_W = 746, PARA_H = 958,
    PARA_FONT = 36, PARA_LINE_H = 52,  -- 行高 ≈ 字号×1.44
    PARA_R = 0xc9, PARA_G = 0xb9, PARA_B = 0x8f,
    -- 7. 日期: X右对齐934 Y1783 字号38 颜色c6a997
    DATE_X = 934, DATE_Y = 1783, DATE_FONT = 38,
    DATE_R = 0xc6, DATE_G = 0xa9, DATE_B = 0x97,
}
DETAIL.PARA_LEFT = DETAIL.PARA_CX - DETAIL.PARA_W * 0.5  -- 167
DETAIL.PARA_TOP  = DETAIL.PARA_CY - DETAIL.PARA_H * 0.5  -- 742

-- ======================== 弹窗动画 ========================

local POPUP_OPEN_DUR   = 0.25
local POPUP_CLOSE_DUR  = 0.20
local POPUP_SCALE_FROM = 0.8
local POPUP_SCALE_TO   = 1.0

local function easeOutCubic(t) local f = t - 1; return f * f * f + 1 end
local function easeInCubic(t) return t * t * t end

-- ======================== 图片句柄 ========================

-- [暗黑化 P1-B2] 弹窗底板改由 DarkIcon.drawNine("panel") 矢量绘制，不再加载 UI_TY_EJQRK.png
local imgIcon    = -1  -- UI_ICON_GG.png  (公告图标)
local imgEntryBg = -1  -- UI_GG_1.png     (条目背景)

-- ======================== 公告数据 ========================

local ANNOUNCEMENTS = {}  -- 由 setAnnouncementData 注入
local readSet = {}        -- 已读公告 id 集合 { [id] = true }，持久化到本地

local READ_FILE = "announcement_read.json"

local function saveReadSet()
    local file = File(READ_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(readSet))
        file:Close()
    end
end

local function loadReadSet()
    if not fileSystem:FileExists(READ_FILE) then return end
    local file = File(READ_FILE, FILE_READ)
    if not file:IsOpen() then return end
    local raw = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, raw)
    if ok and type(data) == "table" then
        readSet = data
        print("[AnnouncementPanel] loadReadSet: " .. tostring(#raw) .. " bytes")
    end
end

--- 外部注入公告数据（服务端推送）
function Panel.setAnnouncementData(list)
    ANNOUNCEMENTS = list or {}
    -- 不重置 readSet：已读状态由本地文件持久化，重推数据不应清空
    print("[AnnouncementPanel] setAnnouncementData: " .. #ANNOUNCEMENTS .. " 条")
end

--- 是否有未读公告
function Panel.hasUnread()
    if #ANNOUNCEMENTS == 0 then return false end
    for _, ann in ipairs(ANNOUNCEMENTS) do
        if ann.id and not readSet[ann.id] then return true end
    end
    return false
end

-- ======================== 状态 ========================

local state = {
    open = false,
    -- 列表滚动
    scrollY = 0,
    dragging = false,
    lastDragY = 0,
    -- 详情模式
    detailIndex = nil,        -- nil=列表模式, 数字=详情模式
    detailScrollY = 0,
    detailDragging = false,
    detailLastDragY = 0,
    detailTextH = 0,          -- 正文实际高度（用于滚动上限）
    -- 弹窗动画
    popupAnimTime  = 0,
    popupClosing   = false,
    popupCloseTime = 0,
}

-- ======================== 弹窗动画辅助 ========================

local function getPopupAnim()
    if state.popupClosing then
        local t = math.min(1.0, (time.elapsedTime - state.popupCloseTime) / POPUP_CLOSE_DUR)
        local e = easeInCubic(t)
        local scale = POPUP_SCALE_TO + (POPUP_SCALE_FROM - POPUP_SCALE_TO) * e
        return scale, 1.0 - e, (t >= 1.0)
    else
        local t = math.min(1.0, (time.elapsedTime - state.popupAnimTime) / POPUP_OPEN_DUR)
        local e = easeOutCubic(t)
        local scale = POPUP_SCALE_FROM + (POPUP_SCALE_TO - POPUP_SCALE_FROM) * e
        return scale, e, false
    end
end

-- ======================== Public API ========================

function Panel.init(vg)
    imgIcon    = nvgCreateImage(vg, "image/UI_ICON_GG.png", 0)
    imgEntryBg = nvgCreateImage(vg, "image/UI_GG_1.png", 0)
    loadReadSet()  -- 从本地文件恢复已读状态
    print("[AnnouncementPanel] init OK")
end

function Panel.open()
    state.open = true
    require("systems.GameSFX").playUIMove(1)
    state.scrollY = 0
    state.dragging = false
    state.detailIndex = nil
    state.detailScrollY = 0
    state.detailDragging = false
    state.popupAnimTime = time.elapsedTime
    state.popupClosing = false
    print("[AnnouncementPanel] open")
end

function Panel.close()
    if state.popupClosing then return end
    state.popupClosing = true
    state.popupCloseTime = time.elapsedTime
    state.dragging = false
    print("[AnnouncementPanel] close (anim)")
end

function Panel.isOpen()
    return state.open
end

function Panel.update(dt)
    if not state.open then return end
    if state.popupClosing then
        local _, _, done = getPopupAnim()
        if done then
            state.popupClosing = false
            state.open = false
        end
    end
end

-- ======================== 正文高度估算 ========================

--- 估算中文文本在指定宽度内自动换行后的总高度
local function estimateTextHeight(text, fontSize, wrapWidth, lineH)
    local cjkCount = 0
    local asciiCount = 0
    local lineBreaks = 0
    local i = 1
    local len = #text
    while i <= len do
        local b = string.byte(text, i)
        if b == 0x0A then -- '\n'
            lineBreaks = lineBreaks + 1
            i = i + 1
        elseif b >= 0xF0 then i = i + 4; cjkCount = cjkCount + 1
        elseif b >= 0xE0 then i = i + 3; cjkCount = cjkCount + 1
        elseif b >= 0xC0 then i = i + 2; cjkCount = cjkCount + 1
        else i = i + 1; asciiCount = asciiCount + 1 end
    end
    -- CJK 字符宽度 ≈ fontSize，ASCII ≈ fontSize*0.5
    -- 按实际宽度累加估算总行数
    local totalWidth = cjkCount * fontSize + asciiCount * (fontSize * 0.5)
    local wrapLines = math.ceil(totalWidth / wrapWidth)
    -- 底部额外增加 2 行 padding，确保滚到底时最后几行不会被截断
    local BOTTOM_PADDING_LINES = 2
    return math.ceil((wrapLines + lineBreaks + BOTTOM_PADDING_LINES) * lineH)
end

-- ======================== 详情视图绘制 ========================

local function drawDetail(vg, ann)
    -- 5. 公告标题 X540 Y677 字号48 颜色5f3737 居中
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DETAIL.TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(DETAIL.TITLE_R, DETAIL.TITLE_G, DETAIL.TITLE_B, 255))
    nvgText(vg, DETAIL.TITLE_X, DETAIL.TITLE_Y, ann.title or "", nil)

    -- 6. 正文段落区域（可滚动）
    local paraText = ann.content or ""
    state.detailTextH = estimateTextHeight(paraText, DETAIL.PARA_FONT,
        DETAIL.PARA_W, DETAIL.PARA_LINE_H)
    local maxScroll = math.max(0, state.detailTextH - DETAIL.PARA_H)
    state.detailScrollY = math.max(0, math.min(state.detailScrollY, maxScroll))

    nvgSave(vg)
    nvgScissor(vg, DETAIL.PARA_LEFT, DETAIL.PARA_TOP, DETAIL.PARA_W, DETAIL.PARA_H)
    nvgTranslate(vg, 0, -state.detailScrollY)

    nvgFontFace(vg, "sans"); nvgFontSize(vg, DETAIL.PARA_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(DETAIL.PARA_R, DETAIL.PARA_G, DETAIL.PARA_B, 255))
    nvgTextLineHeight(vg, DETAIL.PARA_LINE_H / DETAIL.PARA_FONT)
    nvgTextBox(vg, DETAIL.PARA_LEFT, DETAIL.PARA_TOP, DETAIL.PARA_W, paraText, nil)

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 7. 日期 X右对齐934 Y1783 字号38 颜色c6a997
    nvgFontFace(vg, "sans"); nvgFontSize(vg, DETAIL.DATE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(DETAIL.DATE_R, DETAIL.DATE_G, DETAIL.DATE_B, 255))
    nvgText(vg, DETAIL.DATE_X, DETAIL.DATE_Y, ann.date or "", nil)
end

-- ======================== 主绘制 ========================

function Panel.draw(vg)
    if not state.open then return end

    local pScale, pAlpha, _ = getPopupAnim()

    -- 1. 全屏遮罩
    nvgBeginPath(vg); nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(MASK_A * pAlpha)))
    nvgFill(vg)

    -- 弹窗 scale+fade 变换
    nvgSave(vg)
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -BG.CX, -BG.CY)
    nvgGlobalAlpha(vg, pAlpha)

    -- 2. 矢量九宫格弹窗背景 [暗黑化 P1-B2: 暗铁标题带(titleH=原切片IT) + 金饰线 + 深底主体]
    DarkIcon.drawNine(vg, "panel",
        BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5,
        BG.W, BG.H, { titleH = BG.IT })

    -- 3. 标题 "公告"（描边文字）
    DrawUtil.drawTextStroke(vg, TTL.X, TTL.Y, "公告",
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TTL.SW,
        { strokeColor = { TTL.SR, TTL.SG, TTL.SB } })

    -- 4. 内容背景框（圆角矩形，黑色 5%）
    DrawUtil.drawRoundedRectCentered(vg, CONTENT.CX, CONTENT.CY,
        CONTENT.W, CONTENT.H, CONTENT.R,
        0, 0, 0, CONTENT.BG_A)

    -- 分支：详情模式 / 列表模式
    if state.detailIndex then
        local ann = ANNOUNCEMENTS[state.detailIndex]
        if ann then drawDetail(vg, ann) end
        nvgRestore(vg)  -- 恢复弹窗 scale+fade 变换
        return
    end

    -- 5. 公告条目列表（可滚动）
    local count = #ANNOUNCEMENTS
    if count == 0 then
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 180))
        nvgText(vg, 540, 1100, "暂无公告", nil)
        nvgRestore(vg)
        return
    end

    local totalH = count * ENTRY.STEP - ENTRY.GAP
    local maxScroll = math.max(0, totalH - CLIP.H)
    state.scrollY = math.max(0, math.min(state.scrollY, maxScroll))

    nvgSave(vg)
    nvgScissor(vg, CONTENT.CX - CONTENT.W * 0.5, CLIP.TOP, CONTENT.W, CLIP.H)
    nvgTranslate(vg, 0, -state.scrollY)

    for i, ann in ipairs(ANNOUNCEMENTS) do
        local cy = FIRST_CY + (i - 1) * ENTRY.STEP
        local screenCY = cy - state.scrollY

        -- 可见性检测（跳过不可见条目）
        if screenCY >= CLIP.TOP - ENTRY.H and screenCY <= CLIP.BOT + ENTRY.H then
            -- 5-1) 条目背景 UI_GG_1.png (X540, 810×220)
            DrawUtil.drawImageCentered(vg, imgEntryBg, ENTRY.CX, cy,
                ENTRY.W, ENTRY.H, 1.0)

            -- 5-2) 公告图标 UI_ICON_GG.png (X243, 104×104)
            DrawUtil.drawImageCentered(vg, imgIcon,
                ENTRY.ICON_CX, cy + ENTRY.ICON_CY_OFF,
                ENTRY.ICON_W, ENTRY.ICON_H, 1.0)

            -- 5-3/4) 公告标题 X左对齐338 字号48 颜色5f3737
            nvgFontFace(vg, "sans"); nvgFontSize(vg, ENTRY.TITLE_FONT)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(ENTRY.TITLE_R, ENTRY.TITLE_G, ENTRY.TITLE_B, 255))
            nvgText(vg, ENTRY.TITLE_X, cy + ENTRY.TITLE_Y_OFF, ann.title or "", nil)

            -- 5-5) 分割线 X605 530×4 圆角2 颜色8d5f41
            nvgBeginPath(vg)
            nvgRoundedRect(vg,
                ENTRY.DIV_CX - ENTRY.DIV_W * 0.5,
                cy + ENTRY.DIV_Y_OFF - ENTRY.DIV_H * 0.5,
                ENTRY.DIV_W, ENTRY.DIV_H, ENTRY.DIV_ROUND)
            nvgFillColor(vg, nvgRGBA(ENTRY.DIV_R, ENTRY.DIV_G, ENTRY.DIV_B, ENTRY.DIV_A))
            nvgFill(vg)

            -- 5-6) 公告日期 X338 Y792 字号38 颜色c6a997
            nvgFontFace(vg, "sans"); nvgFontSize(vg, ENTRY.DATE_FONT)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(ENTRY.DATE_R, ENTRY.DATE_G, ENTRY.DATE_B, 255))
            nvgText(vg, ENTRY.DATE_X, cy + ENTRY.DATE_Y_OFF, ann.date or "", nil)

            -- 5-7) 已读遮罩（黑色 50% 不透明度，圆角与条目背景一致）
            if ann.id and readSet[ann.id] then
                nvgBeginPath(vg)
                nvgRoundedRect(vg,
                    ENTRY.CX - ENTRY.W * 0.5, cy - ENTRY.H * 0.5,
                    ENTRY.W, ENTRY.H, 16)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
                nvgFill(vg)
            end
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)  -- 恢复滚动裁剪

    nvgRestore(vg)  -- 恢复弹窗 scale+fade 变换
end

-- ======================== 输入处理 ========================

function Panel.handleInput(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.popupAnimTime < 0.05 then return true end

    -- 点击弹窗外部 → 关闭整个面板
    local bgL = BG.CX - BG.W * 0.5
    local bgT = BG.CY - BG.H * 0.5
    if dx < bgL or dx > bgL + BG.W or dy < bgT or dy > bgT + BG.H then
        Panel.close()
        return true
    end

    -- ---- 详情模式：点击弹窗内任意位置 → 返回列表 ----
    if state.detailIndex then
        state.detailIndex = nil
        state.detailScrollY = 0
        state.detailDragging = false
        return true
    end

    -- ---- 列表模式：检测点击条目 → 进入详情 ----
    local count = #ANNOUNCEMENTS
    if count > 0 then
        local entryL = ENTRY.CX - ENTRY.W * 0.5
        local entryR = ENTRY.CX + ENTRY.W * 0.5
        if dx >= entryL and dx <= entryR then
            for i = 1, count do
                local cy = FIRST_CY + (i - 1) * ENTRY.STEP - state.scrollY
                local top = cy - ENTRY.H * 0.5
                local bot = cy + ENTRY.H * 0.5
                -- 只检测在可见裁剪区域内的条目
                if dy >= math.max(top, CLIP.TOP) and dy <= math.min(bot, CLIP.BOT) then
                    state.detailIndex = i
                    state.detailScrollY = 0
                    state.detailDragging = false
                    local ann = ANNOUNCEMENTS[i]
                    if ann and ann.id and not readSet[ann.id] then
                        readSet[ann.id] = true
                        saveReadSet()  -- 持久化到本地文件
                    end
                    return true
                end
            end
        end
    end

    return true  -- 消费事件防穿透
end

function Panel.handleDragBegin(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end

    if state.detailIndex then
        -- 详情模式：在正文段落区域内拖拽
        if dx >= DETAIL.PARA_LEFT and dx <= DETAIL.PARA_LEFT + DETAIL.PARA_W
           and dy >= DETAIL.PARA_TOP and dy <= DETAIL.PARA_TOP + DETAIL.PARA_H then
            state.detailDragging = true
            state.detailLastDragY = dy
        end
    else
        -- 列表模式：在裁剪区域内才可拖拽
        if dy >= CLIP.TOP and dy <= CLIP.BOT
           and dx >= ENTRY.CX - ENTRY.W * 0.5 and dx <= ENTRY.CX + ENTRY.W * 0.5 then
            state.dragging = true
            state.lastDragY = dy
        end
    end
    return true
end

function Panel.handleDragMove(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end

    if state.detailIndex then
        if state.detailDragging then
            state.detailScrollY = state.detailScrollY + (state.detailLastDragY - dy)
            state.detailLastDragY = dy
        end
    else
        if state.dragging then
            state.scrollY = state.scrollY + (state.lastDragY - dy)
            state.lastDragY = dy
        end
    end
    return true
end

function Panel.handleDragEnd(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end

    if state.detailIndex then
        state.detailDragging = false
    else
        state.dragging = false
    end
    return true
end

function Panel.handleScroll(wheel)
    if not state.open then return false end
    if state.popupClosing then return true end

    if state.detailIndex then
        state.detailScrollY = state.detailScrollY - wheel * 60
    else
        state.scrollY = state.scrollY - wheel * 60
    end
    return true
end

return Panel
