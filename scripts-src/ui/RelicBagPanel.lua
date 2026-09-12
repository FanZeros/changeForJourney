-- ============================================================================
-- RelicBagPanel - 遗物背包面板（底部弹出式）
-- 从屏幕底部向上弹出，只占屏幕下方约 1/3 高度
-- UI 排版参照 BackpackPanel（网格+空位占位+装饰条+九宫格面板）
-- 坐标系: 设计分辨率 1080x2400
-- ============================================================================

local GameConfig   = require("config.GameConfig")
local DrawUtil     = require("core.DrawUtil")
local ImageCache   = require("ui.ImageCache")
local BF           = require("systems.ButtonFeedback")
local RelicSystem  = require("systems.RelicSystem")
local RelicDefs    = require("data.RelicDefs")
local RelicDetailPanel = require("ui.RelicDetailPanel")
local EventBus     = require("core.EventBus")


local RelicBagPanel = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 面板尺寸 ========================

-- 面板高度：屏幕 1/3 ≈ 880px
local PANEL_H = 880
-- 面板顶部 Y = 屏幕高度 - 面板高度
local PANEL_TOP = DESIGN_H - PANEL_H  -- 1520

-- ======================== 动画常量 ========================

local ANIM_OPEN_DUR  = 0.35
local ANIM_CLOSE_DUR = 0.28

local function easeOutCubic(t)
    local u = 1 - t; return 1 - u * u * u
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 布局常量（参照 BackpackPanel） ========================

-- 九宫格背景面板 UI_TJP_1.png
local LOWER_PANEL = {
    IT = 200, IR = 10, IB = 200, IL = 10,
}

-- 标题装饰条 UI_JJC_BTBJ.png
local DECO = {
    W = 660, H = 60,
}

-- 标题文字
local GRID_TITLE = {
    FONT_SIZE = 40,
    R = 0x45, G = 0x45, B = 0x45,
    TEXT = "遗物背包",
}

-- 筛选标签栏
local FILTER = {
    FONT = 30,
    GAP = 6,
    ITEM_W = 110,
    ITEM_H = 48,
    ITEM_R = 24,
    -- 激活态
    ACT_BG_R = 0xff, ACT_BG_G = 0xc1, ACT_BG_B = 0x40, ACT_BG_A = 255,
    ACT_TEXT_R = 0x1a, ACT_TEXT_G = 0x14, ACT_TEXT_B = 0x0e,
    -- 非激活态
    INA_BG_R = 0x00, INA_BG_G = 0x00, INA_BG_B = 0x00, INA_BG_A = 25,
    INA_TEXT_R = 0x45, INA_TEXT_G = 0x45, INA_TEXT_B = 0x45,
}

local FILTER_ITEMS = {
    { name = "全部",  type = 0 },
    { name = "岩龟",  type = 1 },
    { name = "毒蛇",  type = 2 },
    { name = "白鹿",  type = 3 },
    { name = "灰狼",  type = 4 },
    { name = "猎鹰",  type = 5 },
}

-- 网格（与 BackpackPanel 一致：160px 格子，5列）
local GRID = {
    CELL_SIZE = 160,
    CELL_RADIUS = 24,
    GAP = 30,
    COLS = 5,
    MARGIN_LEFT = 80,  -- (1080 - 5*160 - 4*30) / 2 = 80
}

-- 品质边框颜色
local QUALITY_BORDER = {
    [1] = { 0xb5, 0xb5, 0xb5 },  -- 普通 - 灰色
    [2] = { 0xa2, 0xff, 0x94 },  -- 优质 - 绿色
    [3] = { 0x72, 0xf2, 0xf5 },  -- 稀有 - 蓝色
    [4] = { 0xef, 0x79, 0xff },  -- 史诗 - 紫色
    [5] = { 0xff, 0xed, 0x00 },  -- 传说 - 金色
    [6] = { 0xff, 0x00, 0x00 },  -- 至臻 - 红色
}

-- 格子空位颜色：纯黑 10%（与 BackpackPanel 一致）
local CELL_BG_R, CELL_BG_G, CELL_BG_B, CELL_BG_A = 0x00, 0x00, 0x00, 25

-- 遗物类型小图标映射（使用 ICON_YWX 小图标）
local TYPE_ICONS = {
    [1] = "image/ICON_YWX_GUI.png",   -- 岩龟
    [2] = "image/ICON_YWX_SHE.png",   -- 毒蛇
    [3] = "image/ICON_YWX_LU.png",    -- 白鹿
    [4] = "image/ICON_YWX_LANG.png",  -- 灰狼
    [5] = "image/ICON_YWX_YING.png",  -- 猎鹰
}

-- 合成按钮布局（面板底部居中）
local MERGE_BTN = {
    W = 340, H = 90,
    CX = 540,
    CY = DESIGN_H - 60,  -- 距屏幕底部 60px
    FONT = 36,
    NINE_IT = 30, NINE_IR = 30, NINE_IB = 30, NINE_IL = 30,
}

-- 滚动参数
local SCROLL_FRICTION   = 0.90
local SCROLL_MIN_VEL    = 0.5
local SCROLL_WHEEL_STEP = 60

-- ======================== 预计算布局（面板内相对坐标） ========================
-- 所有 Y 坐标以面板顶部 PANEL_TOP 为基准
-- 去掉返回按钮后整体下移 40px，让内容更居中

-- 装饰条 + 标题文字 Y（面板内顶部区域）
local DECO_CY  = PANEL_TOP + 100
local TITLE_Y  = DECO_CY

-- 筛选标签 Y（装饰条下方）
local FILTER_Y  = DECO_CY + 50

-- 网格区域起始 Y（筛选栏下方）
local GRID_FIRST_ROW_TOP = FILTER_Y + FILTER.ITEM_H + 20
-- 网格裁剪底部（为底部合成按钮留空间）
local GRID_CLIP_BOTTOM = DESIGN_H - 140
local GRID_CLIP_H = GRID_CLIP_BOTTOM - GRID_FIRST_ROW_TOP

-- 预计算列中心 X（与 BackpackPanel 一致）
local CELL_COL_CX = {}
for c = 1, GRID.COLS do
    CELL_COL_CX[c] = GRID.MARGIN_LEFT + (c - 1) * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5
end

-- 背包容量（占位格子总数，不够的画空位）
local BAG_MAX_DISPLAY = 20  -- 固定显示 20 格（4行×5列）

-- ======================== 图片句柄 ========================

local imgPanel   = -1  -- UI_TJP_1.png（九宫格背景）
local imgDeco    = -1  -- UI_JJC_BTBJ.png（标题装饰条）
local imgMergeBtn = -1 -- UI_AN_LV.png（绿色按钮九宫格）
local imgIconUp  = -1  -- ICON_UP.png（可提升角标）
local imgLock    = -1  -- UI_ICON_SUO.png（锁定角标）

-- 类型图标缓存
local imgTypeIcons = {}  -- [type] = nvgImage handle

-- NanoVG 上下文
local vg_ = nil

-- ======================== 面板状态 ========================

local state = {
    open         = false,
    closing      = false,
    openTime     = 0,
    closeTime    = 0,
    filterType   = 0,       -- 当前筛选类型（0=全部）
    scrollY      = 0,
    scrollMax    = 0,
    dragging     = false,
    lastDragY    = 0,
    scrollVel    = 0,
    selectedId   = nil,     -- 当前选中遗物ID
}

-- 选中回调（外部注册）
local onSelectCallback_ = nil

-- ======================== 数据获取（接入 RelicSystem） ========================

--- 获取背包遗物列表（已筛选 + 排序）
---@param filterType number 0=全部, 1~5=对应类型
---@return table[] 遗物实例列表
local function getFilteredRelics(filterType)
    local relics
    if filterType == 0 then
        relics = RelicSystem.getBag()
    else
        relics = RelicSystem.filterBagByType(filterType)
    end
    return RelicSystem.sortByQuality(relics)
end

-- ======================== 辅助函数 ========================

local function clampScroll()
    state.scrollY = math.max(0, math.min(state.scrollMax, state.scrollY))
end

local function calcScrollMax(totalSlots)
    local rows = math.ceil(totalSlots / GRID.COLS)
    local contentH = rows * GRID.CELL_SIZE + math.max(0, rows - 1) * GRID.GAP
    local maxScroll = math.max(0, contentH - GRID_CLIP_H)
    return maxScroll
end

-- ======================== 初始化 ========================

function RelicBagPanel.init(vg)
    vg_ = vg
    imgPanel    = nvgCreateImage(vg, "image/UI_TJP_1.png", 0)
    imgDeco     = nvgCreateImage(vg, "image/UI_JJC_BTBJ.png", 0)
    imgMergeBtn = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    imgIconUp   = nvgCreateImage(vg, "image/ICON_UP.png", 0)
    imgLock     = nvgCreateImage(vg, "image/UI_ICON_SUO.png", 0)

    for t, path in pairs(TYPE_ICONS) do
        imgTypeIcons[t] = nvgCreateImage(vg, path, 0)
    end

    ImageCache.init(vg)
    print("[RelicBagPanel] init OK")
end

-- ======================== Public API ========================

function RelicBagPanel.open()
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    state.scrollY = 0
    state.scrollMax = 0
    state.dragging = false
    state.scrollVel = 0
    state.selectedId = nil
    print("[RelicBagPanel] open")
end

function RelicBagPanel.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    state.dragging = false
    print("[RelicBagPanel] close")
end

function RelicBagPanel.isOpen()
    return state.open
end

--- 注册选中回调: fn(relic|nil)
---@param fn fun(relic: table|nil)
function RelicBagPanel.setOnSelectCallback(fn)
    onSelectCallback_ = fn
end

--- 获取当前选中的遗物实例（nil 表示无选中）
---@return table|nil
function RelicBagPanel.getSelectedRelic()
    if not state.selectedId then return nil end
    return RelicSystem.findById(state.selectedId)
end

--- 获取当前选中遗物 ID（nil 表示无选中）
---@return number|nil
function RelicBagPanel.getSelectedId()
    return state.selectedId
end

--- 清除选中状态
function RelicBagPanel.clearSelection()
    state.selectedId = nil
    if onSelectCallback_ then onSelectCallback_(nil) end
end

--- 返回打开/关闭动画进度 (0=完全关闭, 1=完全打开)
function RelicBagPanel.getAnimProgress()
    if not state.open then return 0 end
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / ANIM_CLOSE_DUR)
        return 1 - easeInCubic(rawT)
    else
        local elapsed = time.elapsedTime - state.openTime
        local rawT = math.min(1.0, elapsed / ANIM_OPEN_DUR)
        return easeOutCubic(rawT)
    end
end

-- ======================== 更新（内部驱动） ========================

local lastFrameTime_ = 0

local function internalUpdate()
    if not state.open then return end

    local now = time.elapsedTime
    local dt = now - lastFrameTime_
    lastFrameTime_ = now
    if dt <= 0 or dt > 0.1 then dt = 0.016 end

    -- 关闭动画结束
    if state.closing then
        local elapsed = now - state.closeTime
        if elapsed >= ANIM_CLOSE_DUR then
            state.open = false
            state.closing = false
        end
        return
    end
    -- 惯性滚动
    if not state.dragging and math.abs(state.scrollVel) > SCROLL_MIN_VEL then
        state.scrollY = state.scrollY + state.scrollVel
        state.scrollVel = state.scrollVel * SCROLL_FRICTION
        clampScroll()
    else
        state.scrollVel = 0
    end
end

--- 外部可选调用（向后兼容）
function RelicBagPanel.update(dt)
    internalUpdate()
end

-- ======================== 绘制 ========================

function RelicBagPanel.draw(vg)
    if not state.open then return end

    -- 内部驱动更新
    internalUpdate()
    if not state.open then return end

    -- 动画进度
    local progress
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / ANIM_CLOSE_DUR)
        progress = 1 - easeInCubic(rawT)
    else
        local elapsed = time.elapsedTime - state.openTime
        local rawT = math.min(1.0, elapsed / ANIM_OPEN_DUR)
        progress = easeOutCubic(rawT)
    end

    -- 面板从底部向上滑入
    local slideOY = PANEL_H * (1 - progress)

    -- 半透明遮罩（轻量，保持上方可见）
    local overlayAlpha = math.floor(100 * progress)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)

    -- === 面板整体（从底部滑入） ===
    nvgSave(vg)
    nvgTranslate(vg, 0, slideOY)

    -- 九宫格背景面板
    DrawUtil.drawNineSlice(vg, imgPanel,
        0, PANEL_TOP - 40, DESIGN_W, PANEL_H + 80,
        LOWER_PANEL.IT, LOWER_PANEL.IR, LOWER_PANEL.IB, LOWER_PANEL.IL)

    -- 标题装饰条
    if imgDeco >= 0 then
        DrawUtil.drawImageCentered(vg, imgDeco, 540, DECO_CY, DECO.W, DECO.H, 1.0)
    end

    -- 标题文字（居中在装饰条上）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, GRID_TITLE.FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(GRID_TITLE.R, GRID_TITLE.G, GRID_TITLE.B, 255))
    nvgText(vg, 540, TITLE_Y, GRID_TITLE.TEXT, nil)

    -- 筛选标签栏
    local filterTotalW = #FILTER_ITEMS * FILTER.ITEM_W + (#FILTER_ITEMS - 1) * FILTER.GAP
    local filterStartX = (DESIGN_W - filterTotalW) * 0.5

    for i, item in ipairs(FILTER_ITEMS) do
        local fx = filterStartX + (i - 1) * (FILTER.ITEM_W + FILTER.GAP)
        local fy = FILTER_Y
        local isActive = (state.filterType == item.type)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, fx, fy, FILTER.ITEM_W, FILTER.ITEM_H, FILTER.ITEM_R)
        if isActive then
            nvgFillColor(vg, nvgRGBA(FILTER.ACT_BG_R, FILTER.ACT_BG_G, FILTER.ACT_BG_B, FILTER.ACT_BG_A))
        else
            nvgFillColor(vg, nvgRGBA(FILTER.INA_BG_R, FILTER.INA_BG_G, FILTER.INA_BG_B, FILTER.INA_BG_A))
        end
        nvgFill(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, FILTER.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(FILTER.ACT_TEXT_R, FILTER.ACT_TEXT_G, FILTER.ACT_TEXT_B, 255))
        else
            nvgFillColor(vg, nvgRGBA(FILTER.INA_TEXT_R, FILTER.INA_TEXT_G, FILTER.INA_TEXT_B, 180))
        end
        nvgText(vg, fx + FILTER.ITEM_W * 0.5, fy + FILTER.ITEM_H * 0.5, item.name, nil)
    end

    -- 获取过滤后的遗物列表（通过 RelicSystem）
    local relics = getFilteredRelics(state.filterType)

    -- 显示格子总数（至少 BAG_MAX_DISPLAY，用空位补齐）
    local totalSlots = math.max(BAG_MAX_DISPLAY, #relics)
    state.scrollMax = calcScrollMax(totalSlots)
    clampScroll()

    -- 网格绘制（裁剪区域）
    nvgSave(vg)
    nvgScissor(vg, 0, GRID_FIRST_ROW_TOP, DESIGN_W, GRID_CLIP_H)
    nvgTranslate(vg, 0, -state.scrollY)

    for idx = 1, totalSlots do
        local col = ((idx - 1) % GRID.COLS) + 1
        local row = math.floor((idx - 1) / GRID.COLS)
        local cx = CELL_COL_CX[col]
        local cy = GRID_FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5

        -- 可见性剔除
        local screenY = cy - state.scrollY
        if screenY < GRID_FIRST_ROW_TOP - GRID.CELL_SIZE then
            goto continue_cell
        end
        if screenY > GRID_CLIP_BOTTOM + GRID.CELL_SIZE then
            break
        end

        local relic = relics[idx]

        if relic then
            -- 有遗物的格子：品质背景 + 图标 + 品质文字 + 词缀指示
            local qualBg = ImageCache.getQualityBg(relic.quality)
            if qualBg and qualBg >= 0 then
                DrawUtil.drawImageCentered(vg, qualBg, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE, 1.0)
            else
                -- fallback: 品质色圆角矩形
                local qc = QUALITY_BORDER[relic.quality] or QUALITY_BORDER[1]
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5,
                    GRID.CELL_SIZE, GRID.CELL_SIZE, GRID.CELL_RADIUS)
                nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 40))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 200))
                nvgStrokeWidth(vg, 3)
                nvgStroke(vg)
            end

            -- 遗物类型图标
            local iconImg = imgTypeIcons[relic.type]
            if iconImg and iconImg >= 0 then
                DrawUtil.drawImageCentered(vg, iconImg, cx, cy, GRID.CELL_SIZE - 20, GRID.CELL_SIZE - 20, 1.0)
            end

            -- "可合成" 角标（左下角，品质 < 6 且同类同品质 >= 3 件时显示）
            if relic.quality < 6 then
                local bag = RelicSystem.getBag()
                local sameCount = 0
                for _, r in ipairs(bag) do
                    if r.type == relic.type and r.quality == relic.quality then
                        sameCount = sameCount + 1
                    end
                end
                if sameCount >= 3 then
                    local mTxtX = cx - GRID.CELL_SIZE * 0.5 + 8
                    local mTxtY = cy + GRID.CELL_SIZE * 0.5 - 6
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, 22)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
                    -- 黑色描边 12 方向
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local msStep = math.pi * 2 / 12
                    for si = 0, 11 do
                        local sa = si * msStep
                        nvgText(vg, mTxtX + math.cos(sa) * 2, mTxtY + math.sin(sa) * 2, "可合成", nil)
                    end
                    nvgFillColor(vg, nvgRGBA(0x4c, 0xfa, 0x4c, 255))
                    nvgText(vg, mTxtX, mTxtY, "可合成", nil)
                end
            end



            -- 锁定标记（左上角，与装备背包一致）
            if RelicSystem.isLocked(relic) and imgLock >= 0 then
                local lockSize = 36
                local lockX = cx - GRID.CELL_SIZE * 0.5 + lockSize * 0.5 + 4
                local lockY = cy - GRID.CELL_SIZE * 0.5 + lockSize * 0.5 + 4
                DrawUtil.drawImageCentered(vg, imgLock, lockX, lockY, lockSize, lockSize, 1.0)
            end

            -- 被遮蔽覆盖（同词缀已装备且品质>=本遗物，黑色半透明遮罩）
            if RelicSystem.isBlockedByEquipped(relic) then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5,
                    GRID.CELL_SIZE, GRID.CELL_SIZE, GRID.CELL_RADIUS)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
                nvgFill(vg)
            end

            -- "可提升"角标（右上角，有同词缀可替换的高品质遗物时显示）
            if imgIconUp >= 0 and RelicSystem.findReplaceTarget(relic) then
                local upSize = 40
                local upX = cx + GRID.CELL_SIZE * 0.5 - upSize * 0.5 - 2
                local upY = cy - GRID.CELL_SIZE * 0.5 + upSize * 0.5 + 2
                DrawUtil.drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
            end

            -- 选中高亮（金色发光边框 + 外发光）
            if state.selectedId == relic.id then
                local half = GRID.CELL_SIZE * 0.5
                -- 外发光（模糊光晕）
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - half - 4, cy - half - 4,
                    GRID.CELL_SIZE + 8, GRID.CELL_SIZE + 8, GRID.CELL_RADIUS + 4)
                nvgStrokeWidth(vg, 8)
                nvgStrokeColor(vg, nvgRGBA(0xff, 0xd7, 0x00, 100))
                nvgStroke(vg)
                -- 内边框（明亮金色）
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - half, cy - half,
                    GRID.CELL_SIZE, GRID.CELL_SIZE, GRID.CELL_RADIUS)
                nvgStrokeWidth(vg, 4)
                nvgStrokeColor(vg, nvgRGBA(0xff, 0xd7, 0x00, 240))
                nvgStroke(vg)
            end
        else
            -- 空格子：纯黑 10% 圆角矩形（与 BackpackPanel 一致）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5,
                GRID.CELL_SIZE, GRID.CELL_SIZE, GRID.CELL_RADIUS)
            nvgFillColor(vg, nvgRGBA(CELL_BG_R, CELL_BG_G, CELL_BG_B, CELL_BG_A))
            nvgFill(vg)
        end

        ::continue_cell::
    end

    nvgRestore(vg)

    -- 空列表提示（筛选后无结果时）
    if #relics == 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x45, 0x45, 0x45, 180))
        nvgText(vg, 540, GRID_FIRST_ROW_TOP + GRID_CLIP_H * 0.5, "暂无遗物", nil)
    end

    -- ========== 合成按钮（底部居中）==========
    local candidates = RelicSystem.findMergeCandidates()
    local mergeCount = #candidates
    if mergeCount > 0 then
        local btnX = MERGE_BTN.CX - MERGE_BTN.W * 0.5
        local btnY = MERGE_BTN.CY - MERGE_BTN.H * 0.5
        local _bfMerge = BF.begin(vg, "relicBagMerge", MERGE_BTN.CX, MERGE_BTN.CY, MERGE_BTN.W, MERGE_BTN.H)
        DrawUtil.drawNineSlice(vg, imgMergeBtn,
            btnX, btnY, MERGE_BTN.W, MERGE_BTN.H,
            MERGE_BTN.NINE_IT, MERGE_BTN.NINE_IR, MERGE_BTN.NINE_IB, MERGE_BTN.NINE_IL)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, MERGE_BTN.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
        nvgText(vg, MERGE_BTN.CX, MERGE_BTN.CY, "一键合成(" .. mergeCount .. ")", nil)
        BF.finish(vg, _bfMerge)
    end

    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

--- 获取面板实际 Y 偏移（考虑动画）
local function getPanelOffset()
    local progress = RelicBagPanel.getAnimProgress()
    return PANEL_H * (1 - progress)
end

---@param dx number 设计坐标 X
---@param dy number 设计坐标 Y
---@return boolean consumed
function RelicBagPanel.handleTap(dx, dy)
    if not state.open or state.closing then return false end

    local progress = RelicBagPanel.getAnimProgress()
    if progress < 0.9 then return true end

    local offsetY = getPanelOffset()
    local localY = dy - offsetY

    -- 点击面板区域外（上方空白）→ 关闭面板
    if localY < PANEL_TOP then
        RelicBagPanel.close()
        return true
    end

    -- 筛选标签点击
    local filterTotalW = #FILTER_ITEMS * FILTER.ITEM_W + (#FILTER_ITEMS - 1) * FILTER.GAP
    local filterStartX = (DESIGN_W - filterTotalW) * 0.5

    for i, item in ipairs(FILTER_ITEMS) do
        local fx = filterStartX + (i - 1) * (FILTER.ITEM_W + FILTER.GAP)
        local fcx = fx + FILTER.ITEM_W * 0.5
        local fcy = FILTER_Y + FILTER.ITEM_H * 0.5
        if DrawUtil.hitTest(dx, localY, fcx, fcy, FILTER.ITEM_W, FILTER.ITEM_H) then
            state.filterType = item.type
            state.scrollY = 0
            state.scrollVel = 0
            return true
        end
    end

    -- 合成按钮点击
    local candidates = RelicSystem.findMergeCandidates()
    if #candidates > 0 then
        if DrawUtil.hitTest(dx, localY, MERGE_BTN.CX, MERGE_BTN.CY, MERGE_BTN.W, MERGE_BTN.H) then
            ---@diagnostic disable-next-line: param-type-mismatch
            BF.trigger("relicBagMerge")
            -- 通知 Client 进入批量收集模式，等全部结果到齐后统一展示奖励面板
            EventBus.emit("RELIC_BATCH_MERGE_START", { count = #candidates })
            -- 逐组发送合成请求（每组恰好3个，canMerge要求#relicIds==3）
            for _, c in ipairs(candidates) do
                RelicSystem.requestMerge(c.ids, nil)
            end
            return true
        end
    end

    -- 网格区域点击 → 定位遗物格子
    if localY >= GRID_FIRST_ROW_TOP and localY <= GRID_CLIP_BOTTOM then
        local relics = getFilteredRelics(state.filterType)
        local tapContentY = localY + state.scrollY  -- 考虑滚动偏移
        for idx, relic in ipairs(relics) do
            local col = ((idx - 1) % GRID.COLS) + 1
            local row = math.floor((idx - 1) / GRID.COLS)
            local cx = CELL_COL_CX[col]
            local cy = GRID_FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5

            if DrawUtil.hitTest(dx, tapContentY, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE) then
                -- 点击遗物图标 → 弹出详情面板
                RelicDetailPanel.show(relic, "bag")
                return true
            end
        end
        -- 点击到空格子区域，取消选中
        state.selectedId = nil
        if onSelectCallback_ then onSelectCallback_(nil) end
        return true
    end

    return true
end

--- 处理拖拽开始
function RelicBagPanel.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    local offsetY = getPanelOffset()
    local localY = dy - offsetY

    if localY < PANEL_TOP then return true end

    if localY >= GRID_FIRST_ROW_TOP and localY <= GRID_CLIP_BOTTOM then
        state.dragging = true
        state.lastDragY = dy
        state.scrollVel = 0
        return true
    end
    return true
end

--- 处理拖拽移动
function RelicBagPanel.handleDragMove(dx, dy)
    if not state.open or state.closing then return false end
    if state.dragging then
        local delta = state.lastDragY - dy
        state.scrollY = state.scrollY + delta
        state.scrollVel = delta
        state.lastDragY = dy
        clampScroll()
        return true
    end
    return true
end

--- 处理拖拽结束
function RelicBagPanel.handleDragEnd(dx, dy)
    if not state.open or state.closing then return false end
    state.dragging = false
    return true
end

--- 处理滚轮
function RelicBagPanel.handleScroll(wheel)
    if not state.open or state.closing then return false end
    state.scrollY = state.scrollY - wheel * SCROLL_WHEEL_STEP
    clampScroll()
    return true
end

return RelicBagPanel
