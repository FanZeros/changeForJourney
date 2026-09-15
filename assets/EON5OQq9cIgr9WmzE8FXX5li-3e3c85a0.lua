-- ============================================================================
-- ServerSelectPanel  —  选择服务器弹窗
-- 从开始界面点击区服状态进入，全屏遮罩 + 九宫格弹窗
-- ============================================================================

local GameConfig        = require("config.GameConfig")
local DrawUtil          = require("core.DrawUtil")
local DarkIcon          = require("core.DarkIcon")  -- [暗黑化 P1-B5] 矢量九宫格
local ServerListConfig  = require("shared.ServerListConfig")

local M = {}

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ── 状态 ──
local isOpen_   = false
local vg_       = nil

-- ── 图片句柄 ──
local imgBg_     = -1   -- UI_TY_EJQRK 弹窗背景
local imgTabA_   = -1   -- UI_TYAN_A 未选中分类
local imgTabB_   = -1   -- UI_TYAN_B 选中分类
local imgItem_   = -1   -- UI_GG_1 服务器条目背景

-- ── 布局常量（设计坐标） ──
-- 弹窗背景九宫格
local BG_CX, BG_CY = 540, 1170
local BG_W, BG_H   = 950, 1287
local BG_9_TOP, BG_9_LEFT, BG_9_RIGHT, BG_9_BOTTOM = 180, 40, 40, 50

-- 标题
local TITLE_CX, TITLE_CY = 540, 595
local TITLE_FONT = 60
local TITLE_STROKE_W = 6
local TITLE_STROKE_R, TITLE_STROKE_G, TITLE_STROKE_B = 0x59, 0x32, 0x19

-- 左侧分类区域
local CAT_BG_CX, CAT_BG_CY = 282, 1223
local CAT_BG_W, CAT_BG_H   = 330, 1042
local CAT_BG_TOP   = CAT_BG_CY - CAT_BG_H * 0.5  -- 702
local CAT_BG_BOT   = CAT_BG_CY + CAT_BG_H * 0.5  -- 1744

-- 分类按钮
local TAB_CX       = 277
local TAB_FIRST_CY = 798
local TAB_W, TAB_H = 280, 122
local TAB_GAP      = 18   -- 分类间距
local TAB_FONT     = 48
local TAB_MAX_Y    = 1728  -- 分类最大可见底部

-- 右侧服务器列表
local ITEM_CX       = 730
local ITEM_FIRST_CY = 797
local ITEM_W, ITEM_H = 480, 200
local ITEM_GAP       = 20   -- 条目间距
local ITEM_MAX_Y     = 1728 -- 列表最大可见底部

-- 服务器条目内部布局
local ITEM_NAME_X   = 530   -- 左对齐
local ITEM_NAME_DY  = -52   -- 相对条目中心 Y 偏移 (745 - 797)
local ITEM_NAME_FONT = 48

local ITEM_STATUS_X  = 941  -- 右对齐
local ITEM_STATUS_DY = -52
local ITEM_STATUS_FONT = 38

local ITEM_LINE_X   = 734   -- 分割线左端
local ITEM_LINE_DY  = -9    -- (788 - 797)
local ITEM_LINE_W   = 413
local ITEM_LINE_H   = 4

local ITEM_PROG_X   = 530   -- 左对齐
local ITEM_PROG_DY  = 38    -- (835 - 797)
local ITEM_PROG_FONT = 38

-- ── 数据 ──
-- 服务器列表（外部设置）
local servers_ = {}
-- 已游玩的服务器 ID 列表
local playedServerIds_ = {}
-- 上次登录的服务器 ID
local lastServerId_ = -1

-- 分类列表（动态生成）
local categories_ = {}   -- { { name, serverIds = {} }, ... }
local selectedCat_ = 1   -- 当前选中分类索引

-- 滚动
local catScrollY_  = 0   -- 分类列表滚动偏移
local itemScrollY_ = 0   -- 服务器列表滚动偏移
local draggingCat_  = false
local draggingItem_ = false
local dragStartY_   = 0
local dragStartScroll_ = 0
local dragMoved_    = false   -- 本次拖拽是否产生了实际位移
local openTime_     = -1     -- open() 被调用时的引擎时间，防止同帧关闭

-- 回调
local onSelectCallback_ = nil  -- 选中服务器后的回调 function(serverId)
local onClosedTransferCallback_ = nil  -- 已结束挑战者区转出回调 function(serverId)
local closedTransferPending_ = false

-- ============================================================================
-- 内部工具
-- ============================================================================

local function hitTest(px, py, cx, cy, w, h)
    return DrawUtil.hitTest(px, py, cx, cy, w, h)
end

--- 判断服务器是否应该对玩家可见（已开放 或 已游玩；挑战者服始终可见以展示活动状态）
local function isServerVisible(serverId)
    if ServerListConfig.isChallengerServer(serverId) then
        return true
    end
    -- 已游玩的服务器始终可见
    for _, pid in ipairs(playedServerIds_) do
        if pid == serverId then return true end
    end
    -- 未游玩：检查是否已开放
    return ServerListConfig.isValid(serverId)
end

local function isChallengerSelectable(srv)
    if not srv or not ServerListConfig.isChallengerServer(srv.id) then return true end
    if srv.stageConfigReady == false then return false end
    if srv.closed or srv.status == "closed" or srv.status == "not_open" then return false end
    return true
end

local function formatChallengerCloseTime(closeTime)
    closeTime = tonumber(closeTime) or 0
    if closeTime <= 0 then return nil end
    local t = os.date("*t", closeTime)
    if not t then return nil end
    return string.format("截止时间 %d月%d日 %02d:%02d", t.month, t.day, t.hour, t.min)
end

local function getChallengerStateText(srv)
    if not srv or not ServerListConfig.isChallengerServer(srv.id) then return nil end
    if srv.stageConfigReady == false then return "配置维护中" end
    if srv.closed or srv.status == "closed" then return "活动已结束" end
    if srv.status == "not_open" then return "活动未开放" end
    return formatChallengerCloseTime(srv.closeTime) or "截止时间"
end

local function getChallengerStatusLabel(srv)
    if not srv or not ServerListConfig.isChallengerServer(srv.id) then return nil end
    if srv.stageConfigReady == false then return "维护"
    elseif srv.closed or srv.status == "closed" then return "结束"
    elseif srv.status == "not_open" then return "未开"
    end
    return "挑战"
end

local function isClosedChallengerServer(srv)
    return srv and ServerListConfig.isChallengerServer(srv.id)
        and (srv.closed or srv.status == "closed")
end

local function canTransferClosedChallengerCard(srv)
    return isClosedChallengerServer(srv)
        and srv.id == lastServerId_
        and not closedTransferPending_
end

local function getClosedTransferButtonRect(cy)
    return ITEM_CX + 112, cy + 57, 190, 54
end

local function drawClosedTransferButton(vg, srv, cy)
    if not isClosedChallengerServer(srv) then return end

    local bx, by, bw, bh = getClosedTransferButtonRect(cy)
    local enabled = canTransferClosedChallengerCard(srv)
    local fillAlpha = enabled and 235 or 105
    local borderAlpha = enabled and 255 or 130
    local text = closedTransferPending_ and "转出中..." or "转出特权卡"

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx - bw * 0.5, by - bh * 0.5, bw, bh, 16)
    local bg = nvgLinearGradient(vg,
        bx - bw * 0.5, by - bh * 0.5,
        bx + bw * 0.5, by + bh * 0.5,
        nvgRGBA(0x35, 0x6c, 0xff, fillAlpha),
        nvgRGBA(0x86, 0x3c, 0xe8, fillAlpha))
    nvgFillPaint(vg, bg)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx - bw * 0.5, by - bh * 0.5, bw, bh, 16)
    nvgStrokeWidth(vg, 4)
    nvgStrokeColor(vg, nvgRGBA(0x8e, 0xe9, 0xff, borderAlpha))
    nvgStroke(vg)
    DrawUtil.drawTextStroke(vg, bx, by, text, 30,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 3,
        { strokeColor = { 0x18, 0x25, 0x68 } })
end

local function buildCategories()
    categories_ = {}

    -- 1. "已游玩"分类（始终第一个）
    local played = { name = "已游玩", serverIds = {} }
    for _, sid in ipairs(playedServerIds_) do
        table.insert(played.serverIds, sid)
    end
    table.insert(categories_, played)

    -- 2. 挑战者服分类
    local challenger = { name = "挑战者", serverIds = {} }
    for _, s in ipairs(servers_) do
        if ServerListConfig.isChallengerServer(s.id) then
            table.insert(challenger.serverIds, s.id)
        end
    end
    if #challenger.serverIds > 0 then
        table.insert(categories_, challenger)
    end

    -- 3. 按系列（旅程 / 启航）分别分组，同系列内每 10 个服一组，新组在前
    local openServers = ServerListConfig.getOpenFormalServers()
    if #openServers == 0 then return end

    local groupSize = 10

    for _, seriesKey in ipairs(ServerListConfig.SERIES_ORDER) do
        local seriesCfg = ServerListConfig.SERIES[seriesKey]
        if not seriesCfg then goto continue_series end

        local seriesServers = {}
        for _, s in ipairs(openServers) do
            if ServerListConfig.getSeries(s.id) == seriesKey then
                seriesServers[#seriesServers + 1] = s
            end
        end
        if #seriesServers == 0 then goto continue_series end

        local groupCount = math.ceil(#seriesServers / groupSize)
        for g = groupCount, 1, -1 do
            local startIdx = (g - 1) * groupSize + 1
            local endIdx   = math.min(g * groupSize, #seriesServers)

            local firstId = seriesServers[startIdx].id
            local lastId  = seriesServers[endIdx].id
            local displayFirst = firstId - seriesCfg.displayBase
            local displayLast  = lastId - seriesCfg.displayBase

            local catName
            if displayFirst == displayLast then
                catName = seriesCfg.label .. displayFirst
            else
                catName = seriesCfg.label .. displayFirst .. "-" .. displayLast
            end

            local cat = { name = catName, serverIds = {} }
            for i = startIdx, endIdx do
                table.insert(cat.serverIds, seriesServers[i].id)
            end
            table.insert(categories_, cat)
        end

        ::continue_series::
    end
end

--- 获取当前分类下要显示的服务器列表
local function getVisibleServers()
    local cat = categories_[selectedCat_]
    if not cat then return {} end

    local result = {}
    for _, sid in ipairs(cat.serverIds) do
        if isServerVisible(sid) then
            for _, s in ipairs(servers_) do
                if s.id == sid then
                    table.insert(result, s)
                    break
                end
            end
        end
    end
    return result
end

--- 限制滚动范围
local function clampScroll(scroll, contentH, viewH)
    local maxScroll = math.max(0, contentH - viewH)
    return math.max(0, math.min(scroll, maxScroll))
end

-- ============================================================================
-- Public API
-- ============================================================================

--- 初始化（传入 NanoVG 上下文）
function M.init(nvgCtx)
    vg_ = nvgCtx
    imgBg_   = nvgCreateImage(vg_, "image/UI_TY_EJQRK.png", 0)
    imgTabA_ = nvgCreateImage(vg_, "image/UI_TYAN_A.png", 0)
    imgTabB_ = nvgCreateImage(vg_, "image/UI_TYAN_B.png", 0)
    imgItem_ = nvgCreateImage(vg_, "image/UI_GG_1.png", 0)
end

--- 设置服务器数据
---@param servers table  {{ id=1, name="测试1服", level=1, stage="普通3-4", isNew=false }, ...}
---@param playedIds table  已游玩的服务器 ID 列表 {1, 3, 5}
---@param lastId number    上次登录的服务器 ID
function M.setData(servers, playedIds, lastId)
    servers_          = servers or {}
    playedServerIds_  = playedIds or {}
    lastServerId_     = lastId or -1
    buildCategories()
    selectedCat_ = 1
    catScrollY_  = 0
    itemScrollY_ = 0
    closedTransferPending_ = false
end

--- 设置选中回调
function M.setOnSelect(fn)
    onSelectCallback_ = fn
end

function M.setOnClosedTransfer(fn)
    onClosedTransferCallback_ = fn
end

function M.setClosedTransferPending(pending)
    closedTransferPending_ = pending == true
end

--- 打开面板
function M.open()
    isOpen_ = true
    catScrollY_  = 0
    itemScrollY_ = 0
    selectedCat_ = 1
    openTime_    = time.elapsedTime  -- 记录打开时间，防止同帧 Mouse+Touch 双击导致立即关闭
end

--- 关闭面板
function M.close()
    isOpen_ = false
    closedTransferPending_ = false
end

function M.isOpen()
    return isOpen_
end

--- 处理点击（设计坐标）
function M.handleClick(dx, dy)
    if not isOpen_ then return false end

    -- 刚完成拖拽滑动 → 不触发点击
    if dragMoved_ then
        dragMoved_ = false
        return true
    end

    -- 同帧保护：open() 和本次 click 在同一帧内，跳过关闭逻辑
    if time.elapsedTime - openTime_ < 0.05 then
        return true
    end

    -- 点击弹窗外部 → 关闭
    if not hitTest(dx, dy, BG_CX, BG_CY, BG_W, BG_H) then
        M.close()
        return true
    end

    -- 左侧分类点击
    for i, cat in ipairs(categories_) do
        local cy = TAB_FIRST_CY + (i - 1) * (TAB_H + TAB_GAP) - catScrollY_
        if cy - TAB_H * 0.5 >= CAT_BG_TOP and cy + TAB_H * 0.5 <= CAT_BG_BOT then
            if hitTest(dx, dy, TAB_CX, cy, TAB_W, TAB_H) then
                if selectedCat_ ~= i then
                    selectedCat_ = i
                    itemScrollY_ = 0
                end
                return true
            end
        end
    end

    -- 右侧服务器条目点击
    local visibleServers = getVisibleServers()
    for idx, srv in ipairs(visibleServers) do
        local cy = ITEM_FIRST_CY + (idx - 1) * (ITEM_H + ITEM_GAP) - itemScrollY_
        if cy - ITEM_H * 0.5 >= (CAT_BG_TOP - 10) and cy + ITEM_H * 0.5 <= ITEM_MAX_Y + ITEM_H * 0.5 then
            if hitTest(dx, dy, ITEM_CX, cy, ITEM_W, ITEM_H) then
                if canTransferClosedChallengerCard(srv) then
                    local bx, by, bw, bh = getClosedTransferButtonRect(cy)
                    if hitTest(dx, dy, bx, by, bw, bh) then
                        closedTransferPending_ = true
                        if onClosedTransferCallback_ then
                            onClosedTransferCallback_(srv.id)
                        end
                        return true
                    end
                end
                if isChallengerSelectable(srv) and onSelectCallback_ then
                    onSelectCallback_(srv.id)
                end
                return true
            end
        end
    end

    return true  -- 消费点击（弹窗内部）
end

--- 处理滚动（设计坐标）
function M.handleScroll(dx, dy, delta)
    if not isOpen_ then return false end

    -- 左侧分类区域滚动
    if hitTest(dx, dy, CAT_BG_CX, CAT_BG_CY, CAT_BG_W, CAT_BG_H) then
        local contentH = #categories_ * (TAB_H + TAB_GAP) - TAB_GAP
        local viewH = CAT_BG_H
        catScrollY_ = catScrollY_ - delta * 40
        catScrollY_ = clampScroll(catScrollY_, contentH, viewH)
        return true
    end

    -- 右侧服务器列表区域滚动
    local listAreaCX = ITEM_CX
    local listAreaCY = (CAT_BG_TOP + ITEM_MAX_Y) * 0.5
    local listAreaW  = ITEM_W + 40
    local listAreaH  = ITEM_MAX_Y - CAT_BG_TOP
    if hitTest(dx, dy, listAreaCX, listAreaCY, listAreaW, listAreaH) then
        local visibleServers = getVisibleServers()
        local contentH = #visibleServers * (ITEM_H + ITEM_GAP) - ITEM_GAP
        local viewH = ITEM_MAX_Y - ITEM_FIRST_CY + ITEM_H * 0.5
        itemScrollY_ = itemScrollY_ - delta * 40
        itemScrollY_ = clampScroll(itemScrollY_, contentH, viewH)
        return true
    end

    return true
end

--- 拖拽开始（触摸/鼠标按下）
function M.handleDragBegin(dx, dy)
    if not isOpen_ then return false end
    draggingCat_  = false
    draggingItem_ = false
    dragMoved_    = false

    -- 判断落点在左侧分类区域还是右侧列表区域
    if hitTest(dx, dy, CAT_BG_CX, CAT_BG_CY, CAT_BG_W, CAT_BG_H) then
        draggingCat_    = true
        dragStartY_     = dy
        dragStartScroll_ = catScrollY_
        return true
    end

    local listAreaCX = ITEM_CX
    local listAreaCY = (CAT_BG_TOP + ITEM_MAX_Y) * 0.5
    local listAreaW  = ITEM_W + 40
    local listAreaH  = ITEM_MAX_Y - CAT_BG_TOP
    if hitTest(dx, dy, listAreaCX, listAreaCY, listAreaW, listAreaH) then
        draggingItem_   = true
        dragStartY_     = dy
        dragStartScroll_ = itemScrollY_
        return true
    end

    return false
end

--- 拖拽移动
local DRAG_THRESHOLD = 8  -- 超过此像素才视为真正拖拽
function M.handleDragMove(dx, dy)
    if not isOpen_ then return false end

    if draggingCat_ then
        if not dragMoved_ and math.abs(dy - dragStartY_) > DRAG_THRESHOLD then
            dragMoved_ = true
        end
        local delta = dragStartY_ - dy
        local contentH = #categories_ * (TAB_H + TAB_GAP) - TAB_GAP
        local viewH = CAT_BG_H
        catScrollY_ = clampScroll(dragStartScroll_ + delta, contentH, viewH)
        return true
    end

    if draggingItem_ then
        if not dragMoved_ and math.abs(dy - dragStartY_) > DRAG_THRESHOLD then
            dragMoved_ = true
        end
        local delta = dragStartY_ - dy
        local visibleServers = getVisibleServers()
        local contentH = #visibleServers * (ITEM_H + ITEM_GAP) - ITEM_GAP
        local viewH = ITEM_MAX_Y - ITEM_FIRST_CY + ITEM_H * 0.5
        itemScrollY_ = clampScroll(dragStartScroll_ + delta, contentH, viewH)
        return true
    end

    return false
end

--- 拖拽结束
function M.handleDragEnd(dx, dy)
    if not isOpen_ then return false end
    local wasDragging = draggingCat_ or draggingItem_
    draggingCat_  = false
    draggingItem_ = false
    return wasDragging
end

--- 绘制
function M.draw(vg)
    if not isOpen_ then return end

    -- 1. 全屏黑色 50% 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
    nvgFill(vg)

    -- 2. 弹窗背景 [暗黑化 P1-B5] 矢量面板
    DarkIcon.drawNine(vg, "panel",
        BG_CX - BG_W * 0.5, BG_CY - BG_H * 0.5, BG_W, BG_H,
        { titleH = BG_9_TOP })

    -- 3. 标题 "选择服务器"
    DrawUtil.drawTextStroke(vg, TITLE_CX, TITLE_CY, "选择服务器",
        TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255,
        TITLE_STROKE_W,
        { strokeColor = { TITLE_STROKE_R, TITLE_STROKE_G, TITLE_STROKE_B } })

    -- 4. 左侧分类背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        CAT_BG_CX - CAT_BG_W * 0.5, CAT_BG_CY - CAT_BG_H * 0.5,
        CAT_BG_W, CAT_BG_H, 8)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgFill(vg)

    -- 5. 分类按钮列表（裁剪区域）
    nvgSave(vg)
    nvgScissor(vg,
        CAT_BG_CX - CAT_BG_W * 0.5, CAT_BG_TOP,
        CAT_BG_W, CAT_BG_H)

    for i, cat in ipairs(categories_) do
        local cy = TAB_FIRST_CY + (i - 1) * (TAB_H + TAB_GAP) - catScrollY_
        -- 可见性检查
        if cy + TAB_H * 0.5 >= CAT_BG_TOP and cy - TAB_H * 0.5 <= CAT_BG_BOT then
            local isSelected = (i == selectedCat_)
            local isChallengerCat = (cat.name == "挑战者")
            local tabImg = isSelected and imgTabB_ or imgTabA_
            if isChallengerCat then
                local pulse = 0.5 + 0.5 * math.sin(time.elapsedTime * 2.4)
                local glowAlpha = math.floor(100 + 58 * pulse)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, TAB_CX - TAB_W * 0.5 - 10, cy - TAB_H * 0.5 - 10, TAB_W + 20, TAB_H + 20, 24)
                local glow = nvgBoxGradient(vg,
                    TAB_CX - TAB_W * 0.5 - 3, cy - TAB_H * 0.5 - 3, TAB_W + 6, TAB_H + 6,
                    18, 20,
                    nvgRGBA(0x54, 0xe9, 0xff, glowAlpha),
                    nvgRGBA(0x9c, 0x4d, 0xff, 0))
                nvgFillPaint(vg, glow)
                nvgFill(vg)
            end
            if tabImg >= 0 then
                DrawUtil.drawImageCentered(vg, tabImg, TAB_CX, cy, TAB_W, TAB_H, 1.0)
            end
            if isChallengerCat then
                local fillAlpha = isSelected and 210 or 185
                nvgBeginPath(vg)
                nvgRoundedRect(vg, TAB_CX - TAB_W * 0.5 + 7, cy - TAB_H * 0.5 + 7, TAB_W - 14, TAB_H - 14, 20)
                local bg = nvgLinearGradient(vg,
                    TAB_CX - TAB_W * 0.5, cy - TAB_H * 0.5,
                    TAB_CX + TAB_W * 0.5, cy + TAB_H * 0.5,
                    nvgRGBA(0x12, 0x4d, 0xff, fillAlpha),
                    nvgRGBA(0xbd, 0x2d, 0xff, math.floor(fillAlpha * 0.92)))
                nvgFillPaint(vg, bg)
                nvgFill(vg)

                nvgBeginPath(vg)
                nvgRoundedRect(vg, TAB_CX - TAB_W * 0.5 + 4, cy - TAB_H * 0.5 + 4, TAB_W - 8, TAB_H - 8, 22)
                nvgStrokeWidth(vg, isSelected and 6 or 5)
                nvgStrokeColor(vg, nvgRGBA(0x70, 0xf6, 0xff, isSelected and 255 or 230))
                nvgStroke(vg)
            end

            -- 分类文字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, TAB_FONT)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if isChallengerCat then
                DrawUtil.drawTextStroke(vg, TAB_CX, cy, cat.name, TAB_FONT,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 255, 255,
                    5,
                    { strokeColor = { 0x15, 0x16, 0x63 } })
            else
                if isSelected then
                    nvgFillColor(vg, nvgRGBA(0x8d, 0x5f, 0x41, 255))
                else
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                end
                nvgText(vg, TAB_CX, cy, cat.name, nil)
            end
        end
    end

    nvgRestore(vg)

    -- 6. 右侧服务器列表（裁剪区域）
    local listClipTop = ITEM_FIRST_CY - ITEM_H * 0.5   -- 697，不截断第一个条目背景
    local listClipH   = ITEM_MAX_Y - listClipTop        -- 底部裁剪到 Y1728

    nvgSave(vg)
    nvgScissor(vg,
        ITEM_CX - ITEM_W * 0.5 - 10, listClipTop,
        ITEM_W + 20, listClipH)

    local visibleServers = getVisibleServers()
    for idx, srv in ipairs(visibleServers) do
        local cy = ITEM_FIRST_CY + (idx - 1) * (ITEM_H + ITEM_GAP) - itemScrollY_
        -- 可见性检查
        if cy + ITEM_H * 0.5 >= listClipTop and cy - ITEM_H * 0.5 <= listClipTop + listClipH then
            -- 6a. 条目背景 [暗黑化 P1-B5] 矢量纯底板
            local selectable = isChallengerSelectable(srv)
            local itemAlpha = selectable and 1.0 or 0.55
            DarkIcon.drawNine(vg, "plain",
                ITEM_CX - ITEM_W * 0.5, cy - ITEM_H * 0.5, ITEM_W, ITEM_H,
                { alpha = itemAlpha })

            -- 6b. 服务器名称（左对齐）
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, ITEM_NAME_FONT)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0x5f, 0x37, 0x37, math.floor(255 * itemAlpha)))
            nvgText(vg, ITEM_NAME_X, cy + ITEM_NAME_DY, srv.name, nil)

            -- 6c. 状态标签（右对齐，斜体，描边）
            local statusText = nil
            local statusR, statusG, statusB = 255, 255, 255
            local challengerLabel = getChallengerStatusLabel(srv)
            if challengerLabel then
                statusText = challengerLabel
                if srv.stageConfigReady == false or srv.closed or srv.status == "closed" then
                    statusR, statusG, statusB = 180, 180, 180
                elseif srv.status == "not_open" then
                    statusR, statusG, statusB = 0xff, 0xd0, 0x66
                else
                    statusR, statusG, statusB = 0xff, 0x66, 0x44
                end
            elseif srv.id == lastServerId_ then
                statusText = "上次登录"
                statusR, statusG, statusB = 0xff, 0xf4, 0x44
            elseif srv.isNew then
                statusText = "新"
                statusR, statusG, statusB = 0x44, 0xff, 0x63
            end
            if statusText then
                DrawUtil.drawTextStroke(vg,
                    ITEM_STATUS_X, cy + ITEM_STATUS_DY,
                    statusText, ITEM_STATUS_FONT,
                    NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                    statusR, statusG, statusB,
                    5,
                    { italic = true })
            end

            -- 6d. 分割线（ITEM_LINE_X 是中心 X，居中绘制）
            nvgBeginPath(vg)
            nvgRoundedRect(vg,
                ITEM_LINE_X - ITEM_LINE_W * 0.5, cy + ITEM_LINE_DY - ITEM_LINE_H * 0.5,
                ITEM_LINE_W, ITEM_LINE_H, 2)
            nvgFillColor(vg, nvgRGBA(0x8d, 0x5f, 0x41, math.floor(102 * itemAlpha)))  -- 40%
            nvgFill(vg)

            -- 6e. 进度信息（左对齐）—— 未游玩则显示"暂无游玩"
            local played = false
            for _, pid in ipairs(playedServerIds_) do
                if pid == srv.id then played = true; break end
            end

            local progText
            local challengerStateText = getChallengerStateText(srv)
            if challengerStateText then
                progText = challengerStateText
                if srv.stage and srv.stage ~= "" then
                    progText = progText .. " · " .. srv.stage
                end
            elseif played then
                progText = ""
                if srv.level then
                    progText = srv.level .. "级"
                end
                if srv.stage and srv.stage ~= "" then
                    if progText ~= "" then progText = progText .. " " end
                    progText = progText .. srv.stage
                end
                if progText == "" then progText = "暂无游玩" end
            else
                progText = "暂无游玩"
            end

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, ITEM_PROG_FONT)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0xc6, 0xa9, 0x97, math.floor(255 * itemAlpha)))
            nvgText(vg, ITEM_PROG_X, cy + ITEM_PROG_DY, progText, nil)

            drawClosedTransferButton(vg, srv, cy)
        end
    end

    nvgRestore(vg)
end

return M
