-- ============================================================================
-- RelicPanel - 冒险遗物界面
-- 嵌入冒险者协会第二个 Tab（原"未开放"占位）
-- 布局基于 1080×2400 设计分辨率
--
-- 功能:
--   1. 8×10 网格显示已安装的遗物（品质色块 + 75%缩放图标）
--   2. 安装模式: 遗物石板浮空出现 → 玩家拖拽到网格上安装
--   3. 旋转按钮旋转遗物石板形状
--   4. 点击已安装遗物 → 弹出详情面板（含"取下"按钮）
-- ============================================================================

local DrawUtil          = require("core.DrawUtil")
local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest
local BF                = require("systems.ButtonFeedback")

local RelicBagPanel     = require("ui.RelicBagPanel")
local RelicDetailPanel  = require("ui.RelicDetailPanel")
local RelicReforgePanel = require("ui.RelicReforgePanel")
local RelicSystem       = require("systems.RelicSystem")
local RelicGrid         = require("systems.RelicGrid")
local RelicDefs         = require("data.RelicDefs")
local PlayerStore       = require("client.data.PlayerStore")

local RelicPanel = {}

-- ======================== 布局常量 ========================

-- 标题
local TITLE = {
    CX = 540, CY = 182, FONT = 80,
    STROKE_R = 0xa3, STROKE_G = 0x86, STROKE_B = 0x62, STROKE_SIZE = 8,
    INFO_BTN_CX = 980, INFO_BTN_CY = 182, INFO_BTN_W = 80, INFO_BTN_H = 80,
    INFO_ICON_W = 54, INFO_ICON_H = 54,
}

-- 效果总览弹窗
local OVERVIEW = {
    bgCX = 540, bgCY = 1080, bgW = 920, bgH = 1500,
    bgNsT = 180, bgNsR = 40, bgNsB = 50, bgNsL = 40,
    titleCY = 420, titleFont = 48, titleStroke = 5,
    listTop = 500, listH = 1180, listPadX = 80, listW = 760,
    lineH = 46, headerH = 56,
    textFont = 32, headerFont = 36,
    textR = 0x72, textG = 0x58, textB = 0x50,
    headerR = 0x81, headerG = 0x57, headerB = 0x3c,
    POPUP_DUR = 0.22, POPUP_SCALE_FROM = 0.85,
}

-- 格子区域 — 8列×10行 网格, 无缝排布
local GRID_COLS = 8
local GRID_ROWS = 10
local GRID_W = 961
local GRID_H = 1206
local CELL_W = GRID_W / GRID_COLS    -- ~120.125
local CELL_H = GRID_H / GRID_ROWS    -- ~120.6
local GRID = {
    CX = 540, CY = 1158,
    W = GRID_W, H = GRID_H,
    COLS = GRID_COLS, ROWS = GRID_ROWS,
    -- 空格子样式
    FILL_R = 0, FILL_G = 0, FILL_B = 0, FILL_A = 51,          -- 纯黑 20%
    STROKE_R = 0, STROKE_G = 0, STROKE_B = 0, STROKE_A = 179,  -- 70%
    STROKE_W = 2,
}

-- 遗物图标绘制缩放比（75%）— 基于原图尺寸
local RELIC_ICON_SCALE = 0.75
-- 格子尺寸取平均值用于碰撞/预览判断
local CELL_SIZE = (CELL_W + CELL_H) * 0.5

-- 品质颜色映射（与 RelicBagPanel 一致）
local QUALITY_COLORS = {
    [1] = { 0xb5, 0xb5, 0xb5 },  -- 普通 - 灰色
    [2] = { 0xa2, 0xff, 0x94 },  -- 优质 - 绿色
    [3] = { 0x72, 0xf2, 0xf5 },  -- 稀有 - 蓝色
    [4] = { 0xef, 0x79, 0xff },  -- 史诗 - 紫色
    [5] = { 0xff, 0xed, 0x00 },  -- 传说 - 金色
    [6] = { 0xff, 0x00, 0x00 },  -- 至臻 - 红色
}

-- 高亮颜色
local HIGHLIGHT_VALID   = { 0x00, 0xff, 0x80, 80 }   -- 绿色半透明（可放置）
local HIGHLIGHT_INVALID = { 0xff, 0x40, 0x40, 80 }   -- 红色半透明（不可放置）
local HIGHLIGHT_PREVIEW = { 0x00, 0xff, 0x80, 160 }  -- 绿色较亮（预览确认）

-- 翻转按钮（旋转按钮上方，仅鹿/狼可用）
local BTN_FLIP = {
    CX = 122, CY = 1960, W = 130, H = 143,
    TEXT_CX = 122, TEXT_CY = 2019, FONT = 38,
    STROKE_R = 0, STROKE_G = 0, STROKE_B = 0, STROKE_SIZE = 4,
}

-- 旋转按钮
local BTN_ROTATE = {
    CX = 122, CY = 2121, W = 130, H = 143,
    TEXT_CX = 122, TEXT_CY = 2180, FONT = 38,
    STROKE_R = 0, STROKE_G = 0, STROKE_B = 0, STROKE_SIZE = 4,
}

-- 遗物背包按钮（九宫格）
local BTN_BAG = {
    CX = 874, CY = 2100, W = 340, H = 100,
    NP_T = 10, NP_R = 40, NP_B = 10, NP_L = 40,
    TEXT_CX = 873, TEXT_CY = 2100, FONT = 40,
    TEXT_R = 0, TEXT_G = 0, TEXT_B = 0, TEXT_A = 191,
}

-- 调整模式按钮（在背包按钮上方）
local BTN_ADJUST = {
    CX = 874, CY = 1980, W = 340, H = 100,
    NP_T = 10, NP_R = 40, NP_B = 10, NP_L = 40,
    TEXT_CX = 873, TEXT_CY = 1980, FONT = 40,
    TEXT_R = 0, TEXT_G = 0, TEXT_B = 0, TEXT_A = 191,
}

-- 取消安装按钮（安装模式下显示在背包按钮位置）
local BTN_CANCEL = {
    CX = 874, CY = 2100, W = 340, H = 100,
    NP_T = 10, NP_R = 40, NP_B = 10, NP_L = 40,
    FONT = 40,
    TEXT_R = 0xff, TEXT_G = 0x40, TEXT_B = 0x40, TEXT_A = 255,
}

-- 浮空遗物石板初始位置
local FLOAT_RELIC = {
    CX = 445, CY = 2091,
}

-- ======================== 图片资源 ========================

local img = {
    bg      = -1,  -- UI_MXZGH_YW_BJ.png
    rotBtn  = -1,  -- UI_MXZGH_YW_XZAN.png
    flipBtn = -1,  -- UI_MXZGH_YW_JXAN.png
    bagBtn  = -1,  -- UI_AN_LV.png
    cancelBtn = -1, -- UI_AN_HUANG.png
    infoIcon  = -1, -- UI_icon_TS.png 效果总览
    overviewBg = -1, -- UI_TY_EJQRK.png 弹窗背景
}

-- 遗物图标（grid 版本）
local imgRelicGrid = {}  -- [1..5] → nvgImage handle

-- ======================== 状态 ========================

local state = {
    inited = false,

    -- 安装模式
    placementMode   = false,   -- 是否处于安装模式
    placingRelic    = nil,     -- 当前要安装的遗物数据
    rotation        = 0,       -- 旋转+翻转 (0-3=旋转, 4-7=翻转+旋转)
    rotatedCells    = nil,     -- 旋转后的 cells 偏移列表

    -- 调整模式
    adjustMode      = false,   -- 是否处于调整模式
    adjustingRelic  = nil,     -- 当前正在调整的遗物原始数据（含 origRow, origCol, origRotation）
    -- 本地覆盖表：调整模式下的位置变更记录（退出时批量上传）
    -- key = relicId, value = { row, col, rotation } 或 nil（未变更的不记录）
    localOverrides  = {},
    -- 已提交但等待服务器确认的覆盖表（结构同 localOverrides）
    -- 防止服务器推送中间态（REMOVE 后 PLACE 前）时遗物消失
    pendingCommit   = nil,     -- nil 表示无待确认提交
    pendingCommitTime = 0,     -- 提交时间戳（用于超时清除）

    -- 拖拽状态
    dragging        = false,   -- 是否正在拖拽
    dragX           = 0,       -- 当前拖拽位置 X
    dragY           = 0,       -- 当前拖拽位置 Y
    floatX          = FLOAT_RELIC.CX,  -- 浮空石板当前 X
    floatY          = FLOAT_RELIC.CY,  -- 浮空石板当前 Y

    -- 预览
    previewRow      = nil,     -- 当前对齐到的网格行
    previewCol      = nil,     -- 当前对齐到的网格列
    previewValid    = false,   -- 预览位置是否有效
    previewCells    = nil,     -- 预览的所有格子 {row, col, valid}

    -- 效果总览弹窗
    overviewOpen      = false,
    overviewClosing   = false,
    overviewAnimT     = 0,
    overviewScrollY   = 0,
    overviewDragging  = false,
    overviewLastDragY = 0,
    overviewLines     = nil,

    -- 背包详情「替换」飞入动画（关闭背包后仍可见，避免玩家以为遗物消失）
    replaceAnim = nil,   -- { timer, duration, newRelic, oldRelicId, rotation, fromX, fromY, toX, toY, requestSent }
}

-- 详情面板遗物图标中心（与 RelicDetailPanel RELIC_ICON 一致）
local DETAIL_RELIC_ICON_CX = 629
local DETAIL_RELIC_ICON_CY = 943
local REPLACE_ANIM_DUR = 0.48

-- ======================== 工具函数 ========================

local function easeOutCubic(t)
    local inv = 1 - t
    return 1 - inv * inv * inv
end

local function easeInCubic(t)
    return t * t * t
end

local rebuildOverviewLines  -- forward declaration; body defined after getOverriddenGridRelics

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
    print("[RelicPanel] open equipped overview")
end

local function closeOverview()
    if not state.overviewOpen then return end
    if state.overviewClosing then return end
    state.overviewClosing = true
    state.overviewAnimT = time.elapsedTime
    print("[RelicPanel] close equipped overview")
end

--- 网格左上角坐标
local function gridOrigin()
    return GRID.CX - GRID.W * 0.5, GRID.CY - GRID.H * 0.5
end

--- 像素坐标 → 网格行列（1-based）
local function pixelToCell(px, py)
    local ox, oy = gridOrigin()
    local col = math.floor((px - ox) / CELL_W) + 1
    local row = math.floor((py - oy) / CELL_H) + 1
    if col >= 1 and col <= GRID_COLS and row >= 1 and row <= GRID_ROWS then
        return row, col
    end
    return nil, nil
end

--- 网格行列（1-based）→ 格子中心像素坐标
local function cellCenter(row, col)
    local ox, oy = gridOrigin()
    local cx = ox + (col - 1) * CELL_W + CELL_W * 0.5
    local cy = oy + (row - 1) * CELL_H + CELL_H * 0.5
    return cx, cy
end

--- 旋转 cells 偏移 90° 顺时针
--- {r, c} → {c, -r}
local function rotateCells90(cells)
    local result = {}
    for i, cell in ipairs(cells) do
        result[i] = { cell[2], -cell[1] }
    end
    return result
end

--- 根据旋转次数获取旋转后的 cells
--- 获取带 localOverrides / pendingCommit 应用后的 gridRelics 列表（用于命中检测/碰撞计算/绘制）
--- 优先级: localOverrides > pendingCommit > 服务器数据
local function getOverriddenGridRelics()
    local gridRelics = RelicSystem.getGrid()

    -- 合并覆盖源：localOverrides 优先，pendingCommit 兜底
    local merged = {}
    if state.pendingCommit then
        for id, ov in pairs(state.pendingCommit) do merged[id] = ov end
    end
    if state.localOverrides then
        for id, ov in pairs(state.localOverrides) do merged[id] = ov end
    end

    -- 无覆盖直接返回
    local hasAny = false
    for _ in pairs(merged) do hasAny = true; break end
    if not hasAny then return gridRelics end

    -- 将服务器 grid 中存在的遗物应用覆盖
    local seen = {}
    local result = {}
    for _, r in ipairs(gridRelics) do
        seen[r.id] = true
        local ov = merged[r.id]
        if ov then
            result[#result + 1] = {
                id = r.id, type = r.type, quality = r.quality,
                row = ov.row, col = ov.col, rotation = ov.rotation,
            }
        else
            result[#result + 1] = r
        end
    end

    -- "幽灵"遗物：在覆盖中但不在服务器 grid 中（已 REMOVE 尚未 PLACE 的中间态）
    for id, ov in pairs(merged) do
        if not seen[id] then
            -- 从 bag 中找到遗物元数据
            local relic = RelicSystem.findById(id)
            if relic then
                result[#result + 1] = {
                    id = relic.id, type = relic.type, quality = relic.quality,
                    row = ov.row, col = ov.col, rotation = ov.rotation,
                }
            end
        end
    end

    return result
end

-- rebuildOverviewLines body (forward-declared above)
function rebuildOverviewLines()
    state.overviewLines = RelicSystem.buildEquippedOverview(getOverriddenGridRelics())
end

local function getRotatedCells(relicType, rotation)
    local typeDef = RelicDefs.TYPES[relicType]
    if not typeDef then return {} end

    local cells = {}
    for i, c in ipairs(typeDef.cells) do
        cells[i] = { c[1], c[2] }
    end

    -- rotation 0~3 = 正常旋转; 4~7 = 水平翻转 + 旋转(0~3)
    local flipped = rotation >= 4
    if flipped then
        for i, cell in ipairs(cells) do
            cells[i] = { cell[1], -cell[2] }  -- 水平镜像：列取反
        end
    end

    for _ = 1, rotation % 4 do
        cells = rotateCells90(cells)
    end
    return cells
end

--- 获取玩家当前最高关卡进度
local function getMaxStageId()
    local battleData = PlayerStore.Get("battle")
    return battleData and tonumber(battleData.maxStageId) or 0
end

--- 判断指定行是否已解锁
local function isRowUnlocked(row)
    return RelicDefs.isRowUnlocked(row, getMaxStageId())
end

--- 判断旋转后的 cells 能否放置在 (row, col)
local function canPlaceRotated(rotatedCells, row, col, matrix)
    for _, offset in ipairs(rotatedCells) do
        local r = row + offset[1]
        local c = col + offset[2]
        if r < 1 or r > GRID_ROWS or c < 1 or c > GRID_COLS then
            return false
        end
        -- 行未解锁则不可放置
        if not isRowUnlocked(r) then
            return false
        end
        if matrix[r] and matrix[r][c] and matrix[r][c] ~= 0 then
            return false
        end
    end
    return true
end

--- 获取旋转后的详细预览
local function getRotatedPreview(rotatedCells, row, col, matrix)
    local allValid = true
    local result = {}
    for _, offset in ipairs(rotatedCells) do
        local r = row + offset[1]
        local c = col + offset[2]
        local valid = true
        if r < 1 or r > GRID_ROWS or c < 1 or c > GRID_COLS then
            valid = false
        elseif not isRowUnlocked(r) then
            valid = false
        elseif matrix[r] and matrix[r][c] and matrix[r][c] ~= 0 then
            valid = false
        end
        if not valid then allValid = false end
        result[#result + 1] = { row = r, col = c, valid = valid }
    end
    return allValid, result
end

-- ======================== 初始化 ========================

function RelicPanel.init(vg)
    img.bg        = nvgCreateImage(vg, "image/UI_MXZGH_YW_BJ.png", 0)
    img.rotBtn    = nvgCreateImage(vg, "image/UI_MXZGH_YW_XZAN.png", 0)
    img.flipBtn   = nvgCreateImage(vg, "image/UI_MXZGH_YW_JXAN.png", 0)
    img.bagBtn    = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    img.cancelBtn = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    img.infoIcon  = nvgCreateImage(vg, "image/UI_icon_TS.png", 0)
    img.overviewBg = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)

    -- 遗物 grid 图标 (ICON_YW_*)
    local iconKeys = { "GUI", "SHE", "LU", "LANG", "YING" }
    for i, key in ipairs(iconKeys) do
        imgRelicGrid[i] = nvgCreateImage(vg, "image/ICON_YW_" .. key .. ".png", 0)
    end

    RelicBagPanel.init(vg)
    RelicDetailPanel.init(vg)
    RelicReforgePanel.init(vg)

    -- 点击遗物图标时弹出详情面板（非安装模式）
    RelicBagPanel.setOnSelectCallback(function(relic)
        if relic then
            RelicDetailPanel.show(relic, "bag")
        end
    end)

    -- 详情面板关闭时清除选中
    RelicDetailPanel.setOnClose(function()
        RelicBagPanel.clearSelection()
    end)

    -- 详情面板点击"洗练"按钮 → 关闭详情 → 打开洗练面板
    RelicDetailPanel.setOnReforge(function(relic)
        RelicDetailPanel.hide()
        RelicReforgePanel.show(relic)
    end)

    -- 详情面板点击"装备"按钮 → 进入安装模式 / 替换 / 取下
    RelicDetailPanel.setOnEquip(function(relic, location, replaceTarget)
        if location == "replace" and replaceTarget then
            -- 快速替换：飞入动画 + 服务端请求（关闭背包后仍可见动画，避免误以为遗物消失）
            RelicDetailPanel.hide()
            RelicBagPanel.close()
            RelicPanel.playReplaceAnim(relic, replaceTarget)
        elseif location == "bag" then
            -- 从背包装备 → 进入安装模式
            RelicDetailPanel.hide()
            RelicBagPanel.close()
            RelicPanel.enterPlacementMode(relic)
        elseif location == "grid" then
            -- 从网格取下
            RelicDetailPanel.hide()
            RelicSystem.requestRemoveFromGrid(relic.id, function(success, reason)
                if not success then
                    print("[RelicPanel] removeFromGrid failed: " .. tostring(reason))
                end
            end)
        end
    end)

    state.inited = true
    print("[RelicPanel] init OK")
end

-- ======================== 安装模式 ========================

--- 进入安装模式
function RelicPanel.enterPlacementMode(relic)
    if not relic then return end
    state.placementMode = true
    state.placingRelic  = relic
    state.rotation      = 0
    state.rotatedCells  = getRotatedCells(relic.type, 0)

    -- 浮空位置初始化
    state.floatX = FLOAT_RELIC.CX
    state.floatY = FLOAT_RELIC.CY
    state.dragging = false
    state.previewRow = nil
    state.previewCol = nil
    state.previewValid = false
    state.previewCells = nil

    print("[RelicPanel] enterPlacementMode: relic=" .. tostring(relic.id) ..
          " type=" .. tostring(relic.type))
end

--- 退出安装模式
function RelicPanel.exitPlacementMode()
    state.placementMode = false
    state.placingRelic  = nil
    state.rotation      = 0
    state.rotatedCells  = nil
    state.dragging      = false
    state.previewRow    = nil
    state.previewCol    = nil
    state.previewValid  = false
    state.previewCells  = nil
    print("[RelicPanel] exitPlacementMode")
end

--- 更新放置预览（基于当前拖拽位置）— 前置声明
local updatePreview

--- 旋转石板
function RelicPanel.rotateRelic()
    if not state.placementMode or not state.placingRelic then return end
    -- 旋转在当前翻转组内循环: 0→1→2→3→0 或 4→5→6→7→4
    local flipBase = state.rotation >= 4 and 4 or 0
    local rot = state.rotation % 4
    state.rotation = flipBase + (rot + 1) % 4
    state.rotatedCells = getRotatedCells(state.placingRelic.type, state.rotation)
    -- 如果正在预览，更新预览
    if state.previewRow and state.previewCol then
        updatePreview()
    end
    print("[RelicPanel] rotateRelic: rotation=" .. state.rotation)
end

--- 翻转石板（水平镜像，仅鹿和狼可用）
function RelicPanel.flipRelic()
    if not state.placementMode or not state.placingRelic then return end
    local relicType = state.placingRelic.type
    if relicType ~= 3 and relicType ~= 4 then return end  -- 只有鹿和狼可翻转
    -- 翻转 = 在 0~3 和 4~7 之间切换（保持旋转角度不变）
    if state.rotation >= 4 then
        state.rotation = state.rotation - 4
    else
        state.rotation = state.rotation + 4
    end
    state.rotatedCells = getRotatedCells(state.placingRelic.type, state.rotation)
    -- 如果正在预览，更新预览
    if state.previewRow and state.previewCol then
        updatePreview()
    end
    print("[RelicPanel] flipRelic: rotation=" .. state.rotation)
end

--- 更新放置预览（基于当前拖拽位置）
updatePreview = function()
    if not state.dragging then
        state.previewRow = nil
        state.previewCol = nil
        state.previewValid = false
        state.previewCells = nil
        return
    end

    -- 浮空图片中心 = 包围盒中心，需要反算出锚点对应的像素位置
    -- 计算旋转后 cells 的包围盒中心偏移（相对于锚点 {0,0}）
    local minR, maxR, minC, maxC = 0, 0, 0, 0
    if state.rotatedCells then
        for _, offset in ipairs(state.rotatedCells) do
            if offset[1] < minR then minR = offset[1] end
            if offset[1] > maxR then maxR = offset[1] end
            if offset[2] < minC then minC = offset[2] end
            if offset[2] > maxC then maxC = offset[2] end
        end
    end
    -- 包围盒中心相对于锚点的偏移（单位：格子）
    local centerOffR = (minR + maxR) * 0.5
    local centerOffC = (minC + maxC) * 0.5
    -- 拖拽点是图片中心（=包围盒中心），反推锚点像素位置
    local anchorPX = state.dragX - centerOffC * CELL_W
    local anchorPY = state.dragY - centerOffR * CELL_H

    local row, col = pixelToCell(anchorPX, anchorPY)
    if not row or not col then
        state.previewRow = nil
        state.previewCol = nil
        state.previewValid = false
        state.previewCells = nil
        return
    end

    state.previewRow = row
    state.previewCol = col

    -- 检查是否可放置（排除正在调整的遗物，使用 localOverrides + pendingCommit 覆盖位置）
    local allRelics = getOverriddenGridRelics()
    local relicsForMatrix = {}
    local excludeId = state.adjustingRelic and state.adjustingRelic.id or nil
    for _, r in ipairs(allRelics) do
        if r.id ~= excludeId then
            relicsForMatrix[#relicsForMatrix + 1] = r
        end
    end
    local matrix = RelicGrid.buildMatrix(relicsForMatrix)
    local allValid, detailedCells = getRotatedPreview(state.rotatedCells, row, col, matrix)
    state.previewValid = allValid
    state.previewCells = detailedCells
end

--- 执行安装（发送请求到服务端）
local function doPlace(row, col)
    local relic = state.placingRelic
    if not relic then return end

    print("[RelicPanel] doPlace: relicId=" .. tostring(relic.id) ..
          " row=" .. row .. " col=" .. col .. " rotation=" .. state.rotation)

    if state.adjustingRelic then
        -- 调整模式：记录本地覆盖（不发送服务端请求，退出时统一上传）
        local movingId = relic.id
        state.localOverrides[movingId] = {
            row = row,
            col = col,
            rotation = state.rotation,
        }
        print("[RelicPanel] adjust local override: id=" .. tostring(movingId) ..
              " → row=" .. row .. " col=" .. col .. " rot=" .. state.rotation)
        -- 退出安装子模式但保持调整模式
        state.placementMode = false
        state.placingRelic  = nil
        state.rotation      = 0
        state.rotatedCells  = nil
        state.dragging      = false
        state.previewRow    = nil
        state.previewCol    = nil
        state.previewValid  = false
        state.previewCells  = nil
        state.adjustingRelic = nil
    else
        -- 正常安装模式
        RelicSystem.requestPlace(relic.id, row, col, state.rotation, function(success, reason)
            if not success then
                print("[RelicPanel] place failed: " .. tostring(reason))
            end
        end)
        -- 退出安装模式（PlayerStore 更新后网格会自动刷新）
        RelicPanel.exitPlacementMode()
    end
end

-- ======================== 遗物内发光效果 ========================
-- 参考觉醒面板连线外发光样式：多层描边递减透明度，模拟柔和内发光
-- 以遗物占地格子的整体外边框为路径，向内绘制

local GLOW_LAYERS     = 8       -- 层数（与觉醒面板一致）
local GLOW_MAX_INSET  = 14      -- 最大向内偏移（px）
local GLOW_ALPHA_BASE = 128     -- 基础不透明度（50% 整体 * 内层最亮 ≈ 128/255）

--- 构建遗物占地格子的外边界路径段列表
--- 返回 { {x1, y1, x2, y2, nx, ny}, ... }
--- nx,ny 为指向内部的单位法线方向
local function buildOuterEdges(rotatedCells, anchorRow, anchorCol, ox, oy)
    -- 构建格子 set 便于查邻
    local cellSet = {}
    for _, offset in ipairs(rotatedCells) do
        local r = anchorRow + offset[1]
        local c = anchorCol + offset[2]
        cellSet[r .. "," .. c] = true
    end

    local edges = {}
    for _, offset in ipairs(rotatedCells) do
        local r = anchorRow + offset[1]
        local c = anchorCol + offset[2]
        local x0 = ox + (c - 1) * CELL_W
        local y0 = oy + (r - 1) * CELL_H

        -- 上边：上方无格子 → 内侧向下(ny=+1)
        if not cellSet[(r-1) .. "," .. c] then
            edges[#edges + 1] = { x0, y0, x0 + CELL_W, y0, 0, 1 }
        end
        -- 下边：下方无格子 → 内侧向上(ny=-1)
        if not cellSet[(r+1) .. "," .. c] then
            edges[#edges + 1] = { x0, y0 + CELL_H, x0 + CELL_W, y0 + CELL_H, 0, -1 }
        end
        -- 左边：左方无格子 → 内侧向右(nx=+1)
        if not cellSet[r .. "," .. (c-1)] then
            edges[#edges + 1] = { x0, y0, x0, y0 + CELL_H, 1, 0 }
        end
        -- 右边：右方无格子 → 内侧向左(nx=-1)
        if not cellSet[r .. "," .. (c+1)] then
            edges[#edges + 1] = { x0 + CELL_W, y0, x0 + CELL_W, y0 + CELL_H, -1, 0 }
        end
    end
    return edges
end

--- 绘制单个遗物的内发光
local function drawSingleRelicGlow(vg, relic, ox, oy)
    local qColor = QUALITY_COLORS[relic.quality]
    if not qColor then return end

    local rot = relic.rotation or 0
    local rotatedCells = getRotatedCells(relic.type, rot)
    if #rotatedCells == 0 then return end

    local edges = buildOuterEdges(rotatedCells, relic.row, relic.col, ox, oy)
    if #edges == 0 then return end

    local glowR, glowG, glowB = qColor[1], qColor[2], qColor[3]
    local strokeW = GLOW_MAX_INSET / GLOW_LAYERS * 1.8  -- 每层线宽

    -- 多层内发光：从外（贴边最亮）向内（递减淡出）
    for layer = GLOW_LAYERS, 1, -1 do
        local t = layer / GLOW_LAYERS  -- 1.0=最外层(贴边), →0=最内层
        local inset = GLOW_MAX_INSET * (1.0 - t)  -- 0=贴边 → max=最内
        local alpha = GLOW_ALPHA_BASE * t  -- 外亮内淡

        nvgBeginPath(vg)
        for _, e in ipairs(edges) do
            local x1, y1, x2, y2 = e[1], e[2], e[3], e[4]
            local nx, ny = e[5], e[6]  -- 内侧法线方向（已由 buildOuterEdges 编码）
            nvgMoveTo(vg, x1 + nx * inset, y1 + ny * inset)
            nvgLineTo(vg, x2 + nx * inset, y2 + ny * inset)
        end

        nvgStrokeWidth(vg, strokeW)
        nvgStrokeColor(vg, nvgRGBA(glowR, glowG, glowB, math.floor(alpha + 0.5)))
        nvgStroke(vg)
    end
end

--- 绘制所有已安装遗物的内发光
local function drawRelicInnerGlow(vg)
    local gridRelics = getOverriddenGridRelics()
    if not gridRelics or #gridRelics == 0 then return end

    local ox, oy = gridOrigin()

    for _, relic in ipairs(gridRelics) do
        -- 跳过正在调整中拖拽的遗物
        local shouldSkip = false
        if state.adjustingRelic and relic.id == state.adjustingRelic.id then
            shouldSkip = true
        end
        if state.replaceAnim and tostring(relic.id) == tostring(state.replaceAnim.oldRelicId) then
            local t = math.min(1.0, (time.elapsedTime - state.replaceAnim.startTime) / state.replaceAnim.duration)
            if t >= 0.4 then
                shouldSkip = true
            end
        end

        if not shouldSkip and relic.row and relic.col and relic.type and relic.quality then
            drawSingleRelicGlow(vg, relic, ox, oy)
        end
    end
end

-- ======================== 图片原始尺寸 ========================
-- ICON_YW 图片本身就是格子形状素材，直接按 75% 缩放绘制即可
local ICON_ORIG_SIZE = {
    [1] = { w = 320, h = 320 },  -- 龟 2×2
    [2] = { w = 160, h = 640 },  -- 蛇 1×4
    [3] = { w = 480, h = 320 },  -- 鹿 L形
    [4] = { w = 480, h = 320 },  -- 狼 T形
    [5] = { w = 480, h = 320 },  -- 鹰 十字
}

--- 计算已安装遗物在网格上的绘制中心（与 drawPlacedRelics 一致）
---@param relic table { type, row, col, rotation? }
---@return number cx, number cy
local function getRelicDrawCenter(relic)
    if not relic or not relic.row or not relic.col or not relic.type then
        return DETAIL_RELIC_ICON_CX, DETAIL_RELIC_ICON_CY
    end
    local rot = relic.rotation or 0
    local rotatedCells = getRotatedCells(relic.type, rot)
    local minR, maxR, minC, maxC = 0, 0, 0, 0
    for _, offset in ipairs(rotatedCells) do
        local r, c = offset[1], offset[2]
        if r < minR then minR = r end
        if r > maxR then maxR = r end
        if c < minC then minC = c end
        if c > maxC then maxC = c end
    end
    local anchorCX, anchorCY = cellCenter(relic.row, relic.col)
    local cx = anchorCX + (minC + maxC) * 0.5 * CELL_W
    local cy = anchorCY + (minR + maxR) * 0.5 * CELL_H
    return cx, cy
end

--- 在指定位置绘制遗物网格图标
---@param vg NVGContextWrapper
---@param relic table { type, rotation? }
---@param cx number
---@param cy number
---@param alpha number|nil
local function drawRelicIconAt(vg, relic, cx, cy, alpha)
    if not relic or not relic.type then return end
    local relicImg = imgRelicGrid[relic.type]
    local origSize = ICON_ORIG_SIZE[relic.type]
    if not relicImg or relicImg < 0 or not origSize then return end

    local drawW = origSize.w * RELIC_ICON_SCALE
    local drawH = origSize.h * RELIC_ICON_SCALE
    local rot = relic.rotation or 0
    alpha = alpha or 1.0

    nvgSave(vg)
    if alpha < 0.999 then
        nvgGlobalAlpha(vg, alpha)
    end
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, (rot % 4) * math.pi * 0.5)
    if rot >= 4 then
        nvgScale(vg, -1, 1)
    end
    drawImageCentered(vg, relicImg, 0, 0, drawW, drawH, 1.0)
    nvgRestore(vg)
end

local function drawReplaceAnim(vg)
    local anim = state.replaceAnim
    if not anim then return end

    local t = math.min(1.0, (time.elapsedTime - anim.startTime) / anim.duration)
    if t >= 1.0 then
        state.replaceAnim = nil
        return
    end
    local flyT = easeOutCubic(math.max(0, (t - 0.08) / 0.92))
    local cx = anim.fromX + (anim.toX - anim.fromX) * flyT
    local cy = anim.fromY + (anim.toY - anim.fromY) * flyT
    local scale = 0.82 + 0.18 * flyT

    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -cx, -cy)
    drawRelicIconAt(vg, anim.newRelic, cx, cy, math.min(1.0, t * 1.4))
    nvgRestore(vg)

    if t < 0.92 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, math.floor(220 * (1 - t))))
        nvgText(vg, anim.toX, anim.toY - 90, "替换中…", nil)
    elseif t >= 0.92 and t < 1.0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(120, 255, 160, math.floor(240 * (1 - (t - 0.92) / 0.08))))
        nvgText(vg, anim.toX, anim.toY - 90, "已替换", nil)
    end
end

-- ======================== 绘制 ========================

function RelicPanel.draw(vg)
    if not state.inited then return end

    -- 每帧检查 pendingCommit 是否已被服务器确认
    RelicPanel.checkPendingCommit()

    -- 1. 背景
    drawImageCentered(vg, img.bg, 540, 1200, 1080, 2400, 1.0)

    -- 2. 标题 "冒险遗物"
    drawTextStroke(vg, TITLE.CX, TITLE.CY, "冒险遗物",
        TITLE.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TITLE.STROKE_SIZE,
        { strokeColor = { TITLE.STROKE_R, TITLE.STROKE_G, TITLE.STROKE_B } })

    -- 2.5 效果总览感叹号（右上角）
    local _bfInfo = BF.begin(vg, "relic_overview_info", TITLE.INFO_BTN_CX, TITLE.INFO_BTN_CY,
        TITLE.INFO_BTN_W, TITLE.INFO_BTN_H)
    if img.infoIcon >= 0 then
        drawImageCentered(vg, img.infoIcon, TITLE.INFO_BTN_CX, TITLE.INFO_BTN_CY,
            TITLE.INFO_ICON_W, TITLE.INFO_ICON_H, 1.0)
    else
        drawTextStroke(vg, TITLE.INFO_BTN_CX, TITLE.INFO_BTN_CY, "!",
            44, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4, { strokeColor = { 0, 0, 0 } })
    end
    BF.finish(vg, _bfInfo)

    -- 3. 绘制网格
    local ox, oy = gridOrigin()
    for row = 1, GRID_ROWS do
        for col = 1, GRID_COLS do
            local cx = ox + (col - 1) * CELL_W
            local cy = oy + (row - 1) * CELL_H

            -- 格子填充
            nvgBeginPath(vg)
            nvgRect(vg, cx, cy, CELL_W, CELL_H)
            nvgFillColor(vg, nvgRGBA(GRID.FILL_R, GRID.FILL_G, GRID.FILL_B, GRID.FILL_A))
            nvgFill(vg)

            -- 格子描边
            nvgStrokeColor(vg, nvgRGBA(GRID.STROKE_R, GRID.STROKE_G, GRID.STROKE_B, GRID.STROKE_A))
            nvgStrokeWidth(vg, GRID.STROKE_W)
            nvgStroke(vg)
        end
    end

    -- 3.5 未解锁行叠加 80% 纯黑遮罩
    for row = 1, GRID_ROWS do
        if not isRowUnlocked(row) then
            local cy = oy + (row - 1) * CELL_H
            -- 先绘制黑色遮罩
            nvgBeginPath(vg)
            nvgRect(vg, ox, cy, CELL_W * GRID_COLS, CELL_H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))  -- 50% 不透明黑色
            nvgFill(vg)

            -- 解锁条件提示（在遮罩之上绘制文字）
            local threshold = RelicDefs.ROW_UNLOCK[row]
            if threshold and threshold > 0 then
                local chapter = math.floor(threshold / 100)
                local stage = threshold % 100
                local unlockText
                if threshold >= 7000 then
                    unlockText = "通关地狱" .. (chapter - 69) .. "-" .. stage
                elseif threshold >= 4700 then
                    unlockText = "通关噩梦" .. (chapter - 46) .. "-" .. stage
                elseif threshold >= 2400 then
                    unlockText = "通关困难" .. (chapter - 23) .. "-" .. stage
                else
                    unlockText = "通关第" .. chapter .. "章第" .. stage .. "关"
                end
                unlockText = unlockText .. "解锁"
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 28)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
                nvgText(vg, ox + GRID_W * 0.5, cy + CELL_H * 0.5, unlockText, nil)
            end
        end
    end

    -- 4. 绘制已安装的遗物
    drawPlacedRelics(vg)

    -- 5. 绘制遗物品质内发光（在遗物石板上层）
    drawRelicInnerGlow(vg)

    -- 5.5 背包详情「替换」飞入动画（在网格遗物之上）
    drawReplaceAnim(vg)

    -- 6. 安装模式：绘制预览高亮 + 浮空石板
    if state.placementMode then
        drawPlacementPreview(vg)
        drawFloatingRelic(vg)
    end

    -- 7. 底部按钮
    drawBottomButtons(vg)
end

--- 播放背包详情「替换」飞入动画，并发送服务端请求
---@param newRelic table 背包中的新遗物
---@param replaceTarget table 网格上被替换的旧遗物
function RelicPanel.playReplaceAnim(newRelic, replaceTarget)
    if not newRelic or not replaceTarget then return end

    local toX, toY = getRelicDrawCenter(replaceTarget)
    state.replaceAnim = {
        startTime = time.elapsedTime,
        duration = REPLACE_ANIM_DUR,
        newRelic = {
            id = newRelic.id,
            type = newRelic.type,
            quality = newRelic.quality,
            rotation = replaceTarget.rotation or 0,
        },
        oldRelicId = replaceTarget.id,
        fromX = DETAIL_RELIC_ICON_CX,
        fromY = DETAIL_RELIC_ICON_CY,
        toX = toX,
        toY = toY,
        requestSent = false,
    }

    RelicSystem.requestReplace(newRelic.id, replaceTarget.id, function(success, reason)
        if not success then
            print("[RelicPanel] replace failed: " .. tostring(reason))
            state.replaceAnim = nil
        end
    end)
    state.replaceAnim.requestSent = true

    pcall(function()
        require("systems.GameSFX").play("install")
    end)

    print("[RelicPanel] playReplaceAnim new=" .. tostring(newRelic.id)
        .. " old=" .. tostring(replaceTarget.id))
end

--- 是否正在播放替换动画
function RelicPanel.isReplaceAnimActive()
    return state.replaceAnim ~= nil
end

-- ======================== 绘制已安装遗物 ========================

function drawPlacedRelics(vg)
    -- 使用统一的覆盖函数获取有效遗物列表（处理 localOverrides + pendingCommit + 幽灵遗物）
    local gridRelics = getOverriddenGridRelics()
    if not gridRelics or #gridRelics == 0 then return end

    -- 遍历每个已安装的遗物，在包围盒中心绘制 75% 缩放的原图（含旋转）
    for _, relic in ipairs(gridRelics) do
        -- 判断是否跳过绘制（正在拖拽中的遗物由 drawFloatingRelic 绘制）
        local shouldSkip = false
        if state.adjustingRelic and relic.id == state.adjustingRelic.id then
            shouldSkip = true
        end

        -- 替换动画：旧遗物淡出，新遗物由 drawReplaceAnim 飞入
        local drawAlpha = 1.0
        if state.replaceAnim and tostring(relic.id) == tostring(state.replaceAnim.oldRelicId) then
            local t = math.min(1.0, (time.elapsedTime - state.replaceAnim.startTime) / state.replaceAnim.duration)
            if t >= 0.55 then
                shouldSkip = true
            else
                drawAlpha = 1.0 - (t / 0.55)
            end
        end

        -- 位置已由 getOverriddenGridRelics 覆盖，直接使用
        local drawRow = relic.row
        local drawCol = relic.col
        local drawRotation = relic.rotation or 0

        if not shouldSkip and drawRow and drawCol and relic.type then
            local relicImg = imgRelicGrid[relic.type]
            local origSize = ICON_ORIG_SIZE[relic.type]
            if relicImg and relicImg >= 0 and origSize then
                local drawW = origSize.w * RELIC_ICON_SCALE
                local drawH = origSize.h * RELIC_ICON_SCALE
                local rot = drawRotation  -- 0-7: 0-3正常旋转, 4-7翻转+旋转

                -- 计算旋转后 cells 包围盒中心，作为图片绘制中心
                local rotatedCells = getRotatedCells(relic.type, rot)
                local minR, maxR, minC, maxC = 0, 0, 0, 0
                for _, offset in ipairs(rotatedCells) do
                    local r, c = offset[1], offset[2]
                    if r < minR then minR = r end
                    if r > maxR then maxR = r end
                    if c < minC then minC = c end
                    if c > maxC then maxC = c end
                end
                local anchorCX, anchorCY = cellCenter(drawRow, drawCol)
                local cx = anchorCX + (minC + maxC) * 0.5 * CELL_W
                local cy = anchorCY + (minR + maxR) * 0.5 * CELL_H

                if drawAlpha < 0.999 then
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, drawAlpha)
                end

                if rot == 0 then
                    drawImageCentered(vg, relicImg, cx, cy, drawW, drawH, 1.0)
                else
                    nvgSave(vg)
                    nvgTranslate(vg, cx, cy)
                    -- 变换顺序与 cells 逻辑一致：先旋转，再翻转
                    nvgRotate(vg, (rot % 4) * math.pi * 0.5)
                    if rot >= 4 then
                        nvgScale(vg, -1, 1)  -- 水平翻转
                    end
                    drawImageCentered(vg, relicImg, 0, 0, drawW, drawH, 1.0)
                    nvgRestore(vg)
                end

                if drawAlpha < 0.999 then
                    nvgRestore(vg)
                end
            end
        end
    end
end

-- ======================== 绘制放置预览（拖拽到网格上时） ========================

function drawPlacementPreview(vg)
    if not state.previewCells then return end

    local ox, oy = gridOrigin()
    for _, pc in ipairs(state.previewCells) do
        if pc.row >= 1 and pc.row <= GRID_ROWS and pc.col >= 1 and pc.col <= GRID_COLS then
            local cx = ox + (pc.col - 1) * CELL_W
            local cy = oy + (pc.row - 1) * CELL_H

            local color = pc.valid and HIGHLIGHT_PREVIEW or HIGHLIGHT_INVALID
            nvgBeginPath(vg)
            nvgRect(vg, cx + 1, cy + 1, CELL_W - 2, CELL_H - 2)
            nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4]))
            nvgFill(vg)
        end
    end
end

-- ======================== 绘制浮空遗物石板 ========================

function drawFloatingRelic(vg)
    if not state.placingRelic then return end

    local relic = state.placingRelic
    local relicImg = imgRelicGrid[relic.type]
    local origSize = ICON_ORIG_SIZE[relic.type]
    if not origSize then return end

    -- 计算石板中心位置
    local cx, cy
    if state.dragging then
        cx = state.dragX
        cy = state.dragY
    else
        cx = state.floatX
        cy = state.floatY
    end

    -- 直接用原图 75% 缩放绘制，保持原始比例
    local drawW = origSize.w * RELIC_ICON_SCALE
    local drawH = origSize.h * RELIC_ICON_SCALE

    -- 旋转绘制：根据 state.rotation 旋转图片
    -- rotation 0-3 = 正常旋转; 4-7 = 水平翻转 + 旋转(0-3)
    -- 变换顺序与 cells 逻辑一致：先旋转，再翻转
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, (state.rotation % 4) * math.pi * 0.5)  -- 每次旋转90°
    if state.rotation >= 4 then
        nvgScale(vg, -1, 1)  -- 水平翻转
    end
    if relicImg and relicImg >= 0 then
        drawImageCentered(vg, relicImg, 0, 0, drawW, drawH, 1.0)
    end
    nvgRestore(vg)

    -- 安装模式提示文本
    local typeDef = RelicDefs.TYPES[relic.type]
    local relicName = typeDef and typeDef.name or "遗物"
    local hintText = "拖动石板到网格中安装"
    if state.dragging and state.previewRow then
        if state.previewValid then
            hintText = "松手放置「" .. relicName .. "」"
        else
            hintText = "此处无法放置"
        end
    end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 200, 220))
    nvgText(vg, 540, 1840, hintText, nil)
end

-- ======================== 底部按钮 ========================

function drawBottomButtons(vg)
    -- 翻转按钮（仅安装鹿/狼遗物时显示）
    local showFlip = state.placementMode and state.placingRelic
        and (state.placingRelic.type == 3 or state.placingRelic.type == 4)
    if showFlip then
        local _bfFlip = BF.begin(vg, "relic_flip", BTN_FLIP.CX, BTN_FLIP.CY, BTN_FLIP.W, BTN_FLIP.H)
        drawImageCentered(vg, img.flipBtn, BTN_FLIP.CX, BTN_FLIP.CY, BTN_FLIP.W, BTN_FLIP.H, 1.0)
        BF.finish(vg, _bfFlip)

        drawTextStroke(vg, BTN_FLIP.TEXT_CX, BTN_FLIP.TEXT_CY, "翻转",
            BTN_FLIP.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, BTN_FLIP.STROKE_SIZE,
            { strokeColor = { BTN_FLIP.STROKE_R, BTN_FLIP.STROKE_G, BTN_FLIP.STROKE_B } })
    end

    -- 旋转按钮（始终显示，安装模式下可用）
    local _bfRot = BF.begin(vg, "relic_rotate", BTN_ROTATE.CX, BTN_ROTATE.CY, BTN_ROTATE.W, BTN_ROTATE.H)
    drawImageCentered(vg, img.rotBtn, BTN_ROTATE.CX, BTN_ROTATE.CY, BTN_ROTATE.W, BTN_ROTATE.H, 1.0)
    BF.finish(vg, _bfRot)

    drawTextStroke(vg, BTN_ROTATE.TEXT_CX, BTN_ROTATE.TEXT_CY, "旋转",
        BTN_ROTATE.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, BTN_ROTATE.STROKE_SIZE,
        { strokeColor = { BTN_ROTATE.STROKE_R, BTN_ROTATE.STROKE_G, BTN_ROTATE.STROKE_B } })

    if state.placementMode then
        -- 安装/调整子模式：显示"取消"按钮（替代背包按钮）
        local cancelLabel = state.adjustingRelic and "取消调整" or "取消安装"
        local _bfCancel = BF.begin(vg, "relic_cancel_place", BTN_CANCEL.CX, BTN_CANCEL.CY, BTN_CANCEL.W, BTN_CANCEL.H)
        drawNineSlice(vg, img.cancelBtn,
            BTN_CANCEL.CX - BTN_CANCEL.W * 0.5, BTN_CANCEL.CY - BTN_CANCEL.H * 0.5,
            BTN_CANCEL.W, BTN_CANCEL.H,
            BTN_CANCEL.NP_T, BTN_CANCEL.NP_R, BTN_CANCEL.NP_B, BTN_CANCEL.NP_L)
        BF.finish(vg, _bfCancel)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_CANCEL.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, BTN_CANCEL.CX, BTN_CANCEL.CY, cancelLabel, nil)
    elseif state.adjustMode then
        -- 调整模式（未拾取遗物时）：显示"退出调整"按钮
        local _bfExit = BF.begin(vg, "relic_exit_adjust", BTN_BAG.CX, BTN_BAG.CY, BTN_BAG.W, BTN_BAG.H)
        drawNineSlice(vg, img.cancelBtn,
            BTN_BAG.CX - BTN_BAG.W * 0.5, BTN_BAG.CY - BTN_BAG.H * 0.5,
            BTN_BAG.W, BTN_BAG.H,
            BTN_BAG.NP_T, BTN_BAG.NP_R, BTN_BAG.NP_B, BTN_BAG.NP_L)
        BF.finish(vg, _bfExit)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_BAG.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, BTN_BAG.TEXT_CX, BTN_BAG.TEXT_CY, "退出调整", nil)
    else
        -- 正常模式：调整模式按钮 + 背包按钮

        -- 调整模式按钮
        local _bfAdj = BF.begin(vg, "relic_adjust", BTN_ADJUST.CX, BTN_ADJUST.CY, BTN_ADJUST.W, BTN_ADJUST.H)
        drawNineSlice(vg, img.bagBtn,
            BTN_ADJUST.CX - BTN_ADJUST.W * 0.5, BTN_ADJUST.CY - BTN_ADJUST.H * 0.5,
            BTN_ADJUST.W, BTN_ADJUST.H,
            BTN_ADJUST.NP_T, BTN_ADJUST.NP_R, BTN_ADJUST.NP_B, BTN_ADJUST.NP_L)
        BF.finish(vg, _bfAdj)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_ADJUST.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_ADJUST.TEXT_R, BTN_ADJUST.TEXT_G, BTN_ADJUST.TEXT_B, BTN_ADJUST.TEXT_A))
        nvgText(vg, BTN_ADJUST.TEXT_CX, BTN_ADJUST.TEXT_CY, "调整模式", nil)

        -- 背包按钮
        local _bfBag = BF.begin(vg, "relic_bag", BTN_BAG.CX, BTN_BAG.CY, BTN_BAG.W, BTN_BAG.H)
        drawNineSlice(vg, img.bagBtn,
            BTN_BAG.CX - BTN_BAG.W * 0.5, BTN_BAG.CY - BTN_BAG.H * 0.5,
            BTN_BAG.W, BTN_BAG.H,
            BTN_BAG.NP_T, BTN_BAG.NP_R, BTN_BAG.NP_B, BTN_BAG.NP_L)
        BF.finish(vg, _bfBag)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_BAG.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_BAG.TEXT_R, BTN_BAG.TEXT_G, BTN_BAG.TEXT_B, BTN_BAG.TEXT_A))
        nvgText(vg, BTN_BAG.TEXT_CX, BTN_BAG.TEXT_CY, "遗物背包", nil)

        -- 新手引导热点：遗物背包按钮
        local _TM = require("systems.TutorialManager")
        if _TM.isActive() then
            _TM.registerHotspot("relic_bag_btn", BTN_BAG.CX, BTN_BAG.CY, BTN_BAG.W, BTN_BAG.H)
        end
    end
end

-- ======================== 点击处理 ========================

function RelicPanel.handleTap(tx, ty)
    -- 效果总览弹窗优先
    if state.overviewOpen then
        return RelicPanel.handleOverviewTap(tx, ty)
    end

    -- 洗练面板（含可洗练词缀弹窗）
    if RelicReforgePanel.isVisible() then
        return RelicReforgePanel.handleTap(tx, ty)
    end

    -- 详情面板优先处理（覆盖层）
    if RelicDetailPanel.isVisible() then
        return RelicDetailPanel.handleTap(tx, ty)
    end

    -- 安装模式（含调整子模式拾取后）
    if state.placementMode then
        -- 取消按钮
        if hitTest(tx, ty, BTN_CANCEL.CX, BTN_CANCEL.CY, BTN_CANCEL.W, BTN_CANCEL.H) then
            BF.trigger("relic_cancel_place")
            if state.adjustingRelic then
                -- 调整模式取消：遗物恢复原位（不发请求），回到调整模式
                state.placementMode = false
                state.placingRelic  = nil
                state.rotation      = 0
                state.rotatedCells  = nil
                state.dragging      = false
                state.previewRow    = nil
                state.previewCol    = nil
                state.previewValid  = false
                state.previewCells  = nil
                state.adjustingRelic = nil
                print("[RelicPanel] adjust cancel: relic stays at original position")
            else
                RelicPanel.exitPlacementMode()
            end
            return true
        end

        -- 翻转按钮（仅鹿/狼）
        if state.placingRelic and (state.placingRelic.type == 3 or state.placingRelic.type == 4) then
            if hitTest(tx, ty, BTN_FLIP.CX, BTN_FLIP.CY, BTN_FLIP.W, BTN_FLIP.H) then
                BF.trigger("relic_flip")
                RelicPanel.flipRelic()
                return true
            end
        end

        -- 旋转按钮
        if hitTest(tx, ty, BTN_ROTATE.CX, BTN_ROTATE.CY, BTN_ROTATE.W, BTN_ROTATE.H) then
            BF.trigger("relic_rotate")
            RelicPanel.rotateRelic()
            return true
        end

        return true  -- 安装模式吞掉其他点击
    end

    -- 调整模式（未拾取遗物时）：点击网格中的遗物 → 拾起进入安装子模式
    if state.adjustMode then
        -- 退出调整按钮
        if hitTest(tx, ty, BTN_BAG.CX, BTN_BAG.CY, BTN_BAG.W, BTN_BAG.H) then
            BF.trigger("relic_exit_adjust")
            RelicPanel.commitAdjustments()
            return true
        end

        -- 翻转/旋转按钮（调整模式下无浮空遗物时无效果，吞掉点击）
        if hitTest(tx, ty, BTN_FLIP.CX, BTN_FLIP.CY, BTN_FLIP.W, BTN_FLIP.H) then
            return true
        end
        if hitTest(tx, ty, BTN_ROTATE.CX, BTN_ROTATE.CY, BTN_ROTATE.W, BTN_ROTATE.H) then
            return true
        end

        -- 点击网格遗物 → 拾起（使用本地覆盖后的位置做命中检测）
        local row, col = pixelToCell(tx, ty)
        if row and col then
            local gridRelics = getOverriddenGridRelics()
            local relic = RelicGrid.getRelicAt(row, col, gridRelics)
            if relic then
                RelicPanel.pickUpGridRelic(relic)
                return true
            end
        end

        return true  -- 调整模式吞掉其他点击
    end

    -- 正常模式
    if hitTest(tx, ty, TITLE.INFO_BTN_CX, TITLE.INFO_BTN_CY, TITLE.INFO_BTN_W, TITLE.INFO_BTN_H) then
        BF.trigger("relic_overview_info")
        openOverview()
        return true
    end

    -- 检查网格点击（已安装遗物）
    local row, col = pixelToCell(tx, ty)
    if row and col then
        local gridRelics = RelicSystem.getGrid()
        local relic = RelicGrid.getRelicAt(row, col, gridRelics)
        if relic then
            -- 点击已安装的遗物 → 弹出详情面板（显示"取下"按钮）
            RelicDetailPanel.show(relic, "grid")
            print("[RelicPanel] tap grid relic: id=" .. tostring(relic.id))
            return true
        end
    end

    -- 翻转/旋转按钮（正常模式下无效果，但仍处理点击）
    if hitTest(tx, ty, BTN_FLIP.CX, BTN_FLIP.CY, BTN_FLIP.W, BTN_FLIP.H) then
        return true
    end
    if hitTest(tx, ty, BTN_ROTATE.CX, BTN_ROTATE.CY, BTN_ROTATE.W, BTN_ROTATE.H) then
        return true
    end

    -- 调整模式按钮
    if hitTest(tx, ty, BTN_ADJUST.CX, BTN_ADJUST.CY, BTN_ADJUST.W, BTN_ADJUST.H) then
        BF.trigger("relic_adjust")
        state.adjustMode = true
        print("[RelicPanel] enter adjustMode")
        return true
    end

    -- 遗物背包按钮
    if hitTest(tx, ty, BTN_BAG.CX, BTN_BAG.CY, BTN_BAG.W, BTN_BAG.H) then
        BF.trigger("relic_bag")
        RelicBagPanel.open()
        return true
    end

    return false
end

-- ======================== 拖拽处理 ========================

--- 判断坐标是否在浮空石板的拾取范围内
local function isOnFloatingRelic(tx, ty)
    if not state.placementMode then return false end
    if not state.placingRelic then return false end

    local origSize = ICON_ORIG_SIZE[state.placingRelic.type]
    if not origSize then return false end

    -- 基于图片 75% 缩放后的实际尺寸 + 旋转
    local drawW = origSize.w * RELIC_ICON_SCALE
    local drawH = origSize.h * RELIC_ICON_SCALE

    -- 旋转后宽高交换（90°/270° 时 w↔h）
    local rot = state.rotation % 4
    local halfW, halfH
    if rot == 1 or rot == 3 then
        halfW = drawH * 0.5
        halfH = drawW * 0.5
    else
        halfW = drawW * 0.5
        halfH = drawH * 0.5
    end

    -- 增加一点容差
    local margin = 30
    return tx >= state.floatX - halfW - margin and tx <= state.floatX + halfW + margin and
           ty >= state.floatY - halfH - margin and ty <= state.floatY + halfH + margin
end

--- 拖拽开始
function RelicPanel.handleDragBegin(tx, ty)
    if not state.placementMode then return false end
    if isOnFloatingRelic(tx, ty) then
        state.dragging = true
        state.dragX = tx
        state.dragY = ty
        print("[RelicPanel] drag begin at " .. math.floor(tx) .. "," .. math.floor(ty))
        return true
    end
    return false
end

--- 拖拽移动
function RelicPanel.handleDragMove(tx, ty)
    if not state.dragging then return false end
    state.dragX = tx
    state.dragY = ty
    updatePreview()
    return true
end

--- 拖拽结束
function RelicPanel.handleDragEnd(tx, ty)
    if not state.dragging then return false end
    state.dragging = false
    state.dragX = tx
    state.dragY = ty

    -- 检查是否在有效位置释放
    if state.previewRow and state.previewCol and state.previewValid then
        doPlace(state.previewRow, state.previewCol)
    else
        -- 回到初始浮空位置
        state.floatX = FLOAT_RELIC.CX
        state.floatY = FLOAT_RELIC.CY
        state.previewRow = nil
        state.previewCol = nil
        state.previewValid = false
        state.previewCells = nil
        print("[RelicPanel] drag end: returned to float position")
    end

    return true
end

-- ======================== 效果总览弹窗 ========================

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

    local alpha = math.floor(progress * 255 + 0.5)
    local scale = OVERVIEW.POPUP_SCALE_FROM + (1.0 - OVERVIEW.POPUP_SCALE_FROM) * progress

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * progress + 0.5)))
    nvgFill(vg)

    nvgSave(vg)
    nvgTranslate(vg, OVERVIEW.bgCX, OVERVIEW.bgCY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -OVERVIEW.bgCX, -OVERVIEW.bgCY)
    nvgGlobalAlpha(vg, alpha / 255)

    if img.overviewBg >= 0 then
        drawNineSlice(vg, img.overviewBg,
            OVERVIEW.bgCX - OVERVIEW.bgW * 0.5, OVERVIEW.bgCY - OVERVIEW.bgH * 0.5,
            OVERVIEW.bgW, OVERVIEW.bgH,
            OVERVIEW.bgNsT, OVERVIEW.bgNsR, OVERVIEW.bgNsB, OVERVIEW.bgNsL)
    end

    drawTextStroke(vg, OVERVIEW.bgCX, OVERVIEW.titleCY, "遗物效果总览",
        OVERVIEW.titleFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, OVERVIEW.titleStroke,
        { strokeColor = { 0x59, 0x32, 0x19 } })

    clampOverviewScroll()

    local listLeft = OVERVIEW.bgCX - OVERVIEW.listW * 0.5
    local listTop = OVERVIEW.listTop
    local contentW = OVERVIEW.listW - OVERVIEW.listPadX * 2
    local contentLeft = listLeft + OVERVIEW.listPadX
    local contentRight = contentLeft + contentW
    nvgSave(vg)
    nvgIntersectScissor(vg, listLeft, listTop, OVERVIEW.listW, OVERVIEW.listH)
    nvgTranslate(vg, 0, -state.overviewScrollY)

    local y = listTop
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
            local rowH = OVERVIEW.lineH
            nvgBeginPath(vg)
            nvgRoundedRect(vg, contentLeft, y, contentW, rowH, 8)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 20))
            nvgFill(vg)

            local midY = y + rowH * 0.5
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, OVERVIEW.textFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(OVERVIEW.textR, OVERVIEW.textG, OVERVIEW.textB, 255))
            nvgText(vg, contentLeft + 16, midY, line.label, nil)

            drawTextStroke(vg, contentRight - 16, midY, line.value,
                OVERVIEW.textFont, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)
            y = y + rowH + 6
        else
            local rowH = OVERVIEW.lineH + 8
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, OVERVIEW.textFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if line.muted then
                nvgFillColor(vg, nvgRGBA(OVERVIEW.textR, OVERVIEW.textG, OVERVIEW.textB, 160))
            else
                nvgFillColor(vg, nvgRGBA(OVERVIEW.textR, OVERVIEW.textG, OVERVIEW.textB, 255))
            end
            nvgTextBox(vg, contentLeft, y, contentW, line.text, nil)
            y = y + rowH
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
    if not state.overviewDragging then return false end
    state.overviewScrollY = state.overviewScrollY - (dy - state.overviewLastDragY)
    state.overviewLastDragY = dy
    clampOverviewScroll()
    return true
end

function RelicPanel.handleOverviewDragEnd(dx, dy)
    if state.overviewDragging then
        state.overviewDragging = false
        return true
    end
    return false
end

function RelicPanel.handleOverviewScroll(wheel)
    if not state.overviewOpen or state.overviewClosing then return false end
    state.overviewScrollY = state.overviewScrollY - wheel * 80
    clampOverviewScroll()
    return true
end

-- ======================== 详情面板 ========================

--- 详情面板是否打开
function RelicPanel.isDetailOpen()
    return RelicDetailPanel.isVisible()
end

--- 更新详情面板动画
function RelicPanel.updateDetail(dt)
    RelicDetailPanel.update(dt)
end

--- 绘制详情面板（应在背包面板之后调用，最顶层）
function RelicPanel.drawDetailPanel(vg)
    RelicDetailPanel.draw(vg)
end

--- 详情面板点击
function RelicPanel.handleDetailTap(tx, ty)
    return RelicDetailPanel.handleTap(tx, ty)
end

-- ======================== 洗练面板转发 ========================

--- 洗练面板是否打开
function RelicPanel.isReforgeOpen()
    return RelicReforgePanel.isVisible()
end

function RelicPanel.isReforgePoolOpen()
    return RelicReforgePanel.isPoolOpen()
end

--- 更新洗练面板动画
function RelicPanel.updateReforge(dt)
    RelicReforgePanel.update(dt)
end

--- 绘制洗练面板（应在详情面板之后调用，最顶层）
function RelicPanel.drawReforgePanel(vg)
    RelicReforgePanel.draw(vg)
end

--- 洗练面板点击
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

-- ======================== 背包面板转发 ========================

--- 背包面板是否打开
function RelicPanel.isBagOpen()
    return RelicBagPanel.isOpen()
end

--- 绘制背包面板（应在 RelicPanel.draw 之后调用）
function RelicPanel.drawBagPanel(vg)
    RelicBagPanel.draw(vg)
end

--- 背包面板点击
function RelicPanel.handleBagTap(tx, ty)
    -- 洗练面板打开时，最优先由洗练面板处理
    if RelicReforgePanel.isVisible() then
        return RelicReforgePanel.handleTap(tx, ty)
    end
    -- 详情面板打开时，优先由详情面板处理
    if RelicDetailPanel.isVisible() then
        return RelicDetailPanel.handleTap(tx, ty)
    end
    return RelicBagPanel.handleTap(tx, ty)
end

--- 背包面板拖拽开始
function RelicPanel.handleBagDragBegin(dx, dy)
    return RelicBagPanel.handleDragBegin(dx, dy)
end

--- 背包面板拖拽移动
function RelicPanel.handleBagDragMove(dx, dy)
    return RelicBagPanel.handleDragMove(dx, dy)
end

--- 背包面板拖拽结束
function RelicPanel.handleBagDragEnd(dx, dy)
    return RelicBagPanel.handleDragEnd(dx, dy)
end

--- 背包面板滚轮
function RelicPanel.handleBagScroll(wheel)
    return RelicBagPanel.handleScroll(wheel)
end

--- 是否处于安装模式
function RelicPanel.isPlacementMode()
    return state.placementMode
end

--- 是否处于调整模式（供 GuildPage 判断是否转发拖拽）
function RelicPanel.isAdjustMode()
    return state.adjustMode
end

-- ======================== 调整模式：拾起网格遗物 ========================

--- 拾起网格中的遗物进入安装子模式（不发 REMOVE 请求）
function RelicPanel.pickUpGridRelic(relic)
    if not relic then return end

    -- 使用本地覆盖位置（如果已经移动过）或服务端位置
    local currentRow = relic.row
    local currentCol = relic.col
    local currentRotation = relic.rotation or 0
    if state.localOverrides[relic.id] then
        local ov = state.localOverrides[relic.id]
        currentRow = ov.row
        currentCol = ov.col
        currentRotation = ov.rotation
    end

    print("[RelicPanel] pickUpGridRelic: id=" .. tostring(relic.id) ..
          " type=" .. tostring(relic.type) ..
          " currentRow=" .. tostring(currentRow) .. " currentCol=" .. tostring(currentCol) ..
          " currentRotation=" .. tostring(currentRotation))

    -- 记住当前位置（用于取消时恢复到此位置）
    state.adjustingRelic = {
        id = relic.id,
        type = relic.type,
        quality = relic.quality,
        origRow = currentRow,
        origCol = currentCol,
        origRotation = currentRotation,
    }

    -- 进入安装子模式（复用现有安装模式逻辑）
    state.placementMode = true
    state.placingRelic  = relic
    state.rotation      = currentRotation
    state.rotatedCells  = getRotatedCells(relic.type, state.rotation)

    -- 浮空位置初始化
    state.floatX = FLOAT_RELIC.CX
    state.floatY = FLOAT_RELIC.CY
    state.dragging = false
    state.previewRow = nil
    state.previewCol = nil
    state.previewValid = false
    state.previewCells = nil
end

-- ======================== 调整模式：拖拽拾取网格遗物 ========================

--- 调整模式下尝试从网格拖拽拾起遗物
function RelicPanel.handleAdjustDragBegin(tx, ty)
    if not state.adjustMode then return false end

    -- 已经拾起遗物（进入安装子模式），转发给常规拖拽处理
    if state.placementMode then
        return RelicPanel.handleDragBegin(tx, ty)
    end

    -- 未拾起：检查拖拽点是否在某个网格遗物上（使用本地覆盖后的位置）
    local row, col = pixelToCell(tx, ty)
    if not row or not col then return false end

    local gridRelics = getOverriddenGridRelics()
    local relic = RelicGrid.getRelicAt(row, col, gridRelics)
    if relic then
        -- 拾起遗物并立刻开始拖拽
        RelicPanel.pickUpGridRelic(relic)
        state.dragging = true
        state.dragX = tx
        state.dragY = ty
        print("[RelicPanel] adjust drag begin: picked relic " .. tostring(relic.id))
        return true
    end

    return false
end

--- 调整模式下拖拽移动
function RelicPanel.handleAdjustDragMove(tx, ty)
    if not state.adjustMode then return false end
    -- 已进入安装子模式且正在拖拽，复用常规逻辑
    if state.placementMode and state.dragging then
        return RelicPanel.handleDragMove(tx, ty)
    end
    return false
end

--- 调整模式下拖拽结束
function RelicPanel.handleAdjustDragEnd(tx, ty)
    if not state.adjustMode then return false end
    if state.placementMode and state.dragging then
        return RelicPanel.handleDragEnd(tx, ty)
    end
    return false
end

-- ======================== 调整模式：退出并批量上传 ========================

--- 退出调整模式，将所有本地位置变更批量发送到服务端
function RelicPanel.commitAdjustments()
    local overrides = state.localOverrides
    local count = 0
    for _ in pairs(overrides) do count = count + 1 end

    if count == 0 then
        -- 没有任何移动，直接退出
        state.adjustMode = false
        state.localOverrides = {}
        print("[RelicPanel] exit adjustMode (no changes)")
        return
    end

    -- 原子化批量移动：单次请求发送所有移动，避免频率限制导致部分操作丢失
    print("[RelicPanel] commitAdjustments: " .. count .. " relic(s) moved")
    local Client = require("network.Client")

    local moves = {}
    for relicId, ov in pairs(overrides) do
        moves[#moves + 1] = {
            relicId = relicId,
            row = ov.row,
            col = ov.col,
            rotation = ov.rotation or 0,
        }
    end
    Client.sendAction(RelicSystem.ACTIONS.RELIC_BATCH_ADJUST, { moves = moves })

    -- 退出调整模式，但将 overrides 转为 pendingCommit 保持视觉覆盖
    -- 直到服务器确认所有 PLACE 完成（或超时），才清除 pendingCommit
    state.adjustMode = false
    state.localOverrides = {}
    state.pendingCommit = overrides
    state.pendingCommitTime = os.clock()
    print("[RelicPanel] exit adjustMode → pendingCommit active (" .. count .. " relics)")
end

--- 每帧检查 pendingCommit 是否已被服务器确认（所有遗物在 grid 中出现在正确位置）
function RelicPanel.checkPendingCommit()
    if not state.pendingCommit then return end

    -- 超时保护：5 秒后强制清除（避免永久卡在 pending 态）
    local elapsed = os.clock() - state.pendingCommitTime
    if elapsed > 5.0 then
        print("[RelicPanel] pendingCommit TIMEOUT after " .. string.format("%.1f", elapsed) .. "s, force clear")
        state.pendingCommit = nil
        return
    end

    -- 检查服务器 grid 是否已包含所有待确认遗物的正确位置
    local serverGrid = RelicSystem.getGrid()
    local serverMap = {}
    for _, r in ipairs(serverGrid) do
        serverMap[r.id] = r
    end

    for relicId, ov in pairs(state.pendingCommit) do
        local sr = serverMap[relicId]
        if not sr then return end  -- 遗物不在 grid 中（PLACE 未完成）
        if sr.row ~= ov.row or sr.col ~= ov.col then return end  -- 位置不匹配
        -- rotation 检查（server 可能存 0 而 ov 可能是 nil/0）
        local sRot = sr.rotation or 0
        local oRot = ov.rotation or 0
        if sRot ~= oRot then return end
    end

    -- 所有遗物已确认在正确位置
    print("[RelicPanel] pendingCommit confirmed by server (" ..
          string.format("%.1f", elapsed) .. "s)")
    state.pendingCommit = nil
end

return RelicPanel
