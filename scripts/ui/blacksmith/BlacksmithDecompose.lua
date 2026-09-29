-- ============================================================================
-- BlacksmithDecompose.lua
-- 铁匠铺 - 分解子模块：背包格子、品质筛选、自动分解弹窗
-- 从 BlacksmithPage.lua 拆分而来
-- ============================================================================

---@diagnostic disable: undefined-global

local GameConfig       = require("config.GameConfig")
local DrawUtil         = require("core.DrawUtil")
local DarkIcon         = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质底框矢量绘制
local EquipmentConfig  = require("config.EquipmentConfig")
local EquipmentSystem  = require("systems.EquipmentSystem")
local BlacksmithConfig = require("config.BlacksmithConfig")
local ResourceDefs     = require("config.ResourceDefs")
local PlayerStore      = require("core.PlayerStore")
local RewardPopup      = require("ui.hud.popup.RewardPopup")
local EquipmentDetail  = require("ui.character.equip.EquipmentDetail")
local QualityMark      = require("ui.widget.QualityMark")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local hitTest           = DrawUtil.hitTest
local BF                = require("systems.ButtonFeedback")

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

local M = {}

-- ======================== 分解界面常量 ========================

local FJ = {
    -- 1. 奖励图标槽位（上半部分 Y431，替代装备槽）
    REWARD_CX = 540, REWARD_CY = 431, REWARD_SIZE = 160, REWARD_RADIUS = 24,
    -- 2. "分解装备" 文本
    TITLE_X = 157, TITLE_Y = 905, TITLE_FONT_SIZE = 40,
    TITLE_R = 0x45, TITLE_G = 0x45, TITLE_B = 0x45,
    -- 3-4. 品质筛选图标
    PZSX_FIRST_CX = 558, PZSX_CY = 900, PZSX_SIZE = 80, PZSX_GAP = 23,
    -- 5. 背包格子
    GRID_COLS = 5, GRID_CELL = 160, GRID_GAP = 35, GRID_RADIUS = 24,
    GRID_BOTTOM_Y = 2025,
    -- 选中遮罩
    SEL_MASK_ALPHA = 128,
    SEL_CHECK_SIZE = 80,
    -- 6. 自动分解按钮
    AUTO_BTN_CX = 310, AUTO_BTN_CY = 2129, AUTO_BTN_W = 410, AUTO_BTN_H = 100,
    AUTO_TEXT_FONT_SIZE = 40,
    AUTO_TEXT_R = 0x6d, AUTO_TEXT_G = 0x4c, AUTO_TEXT_B = 0x1d,
    -- 8. 分解按钮
    DEC_BTN_CX = 773, DEC_BTN_CY = 2129, DEC_BTN_W = 410, DEC_BTN_H = 100,
    DEC_TEXT_FONT_SIZE = 40,
    DEC_TEXT_R = 255, DEC_TEXT_G = 214, DEC_TEXT_B = 102,
}
-- 自动分解弹窗常量
FJ.POP_MASK_ALPHA = 128
FJ.POP_BG_CX = 540; FJ.POP_BG_CY = 1111; FJ.POP_BG_W = 950; FJ.POP_BG_H = 720
FJ.POP_TITLE_CX = 540; FJ.POP_TITLE_CY = 830; FJ.POP_TITLE_FONT = 60; FJ.POP_TITLE_STROKE = 4
FJ.POP_DESC_CX = 540; FJ.POP_DESC_CY = 925; FJ.POP_DESC_FONT = 38; FJ.POP_DESC_MAX_W = 820
FJ.POP_DESC_R = 0xb6; FJ.POP_DESC_G = 0xb0; FJ.POP_DESC_B = 0x9d
-- 品质方框选择行（6 个品质图标方框，与分解页品质筛选同款小图）
FJ.POP_QBOX_COUNT = 6
FJ.POP_QBOX_SIZE = 100; FJ.POP_QBOX_GAP = 24; FJ.POP_QBOX_CY = 1060; FJ.POP_QBOX_R = 16
FJ.POP_QBOX_ICON_SIZE = 76
FJ.POP_QBOX_TOTAL_W = FJ.POP_QBOX_COUNT * FJ.POP_QBOX_SIZE + (FJ.POP_QBOX_COUNT - 1) * FJ.POP_QBOX_GAP  -- 720
FJ.POP_QBOX_FIRST_CX = 540 - FJ.POP_QBOX_TOTAL_W * 0.5 + FJ.POP_QBOX_SIZE * 0.5  -- 230
FJ.POP_QBOX_SEL_STROKE = 5
-- 等级筛选行：减/加按钮 + 滑条（与市场购买弹窗同款交互）
FJ.POP_LEVEL_CY = 1185
FJ.POP_MINUS_CX = 240; FJ.POP_MINUS_CY = FJ.POP_LEVEL_CY; FJ.POP_MINUS_W = 84; FJ.POP_MINUS_H = 84
FJ.POP_PLUS_CX = 840; FJ.POP_PLUS_CY = FJ.POP_LEVEL_CY; FJ.POP_PLUS_W = 84; FJ.POP_PLUS_H = 84
FJ.POP_SLIDER_CX = 540; FJ.POP_SLIDER_CY = FJ.POP_LEVEL_CY; FJ.POP_SLIDER_W = 400; FJ.POP_SLIDER_H = 24; FJ.POP_SLIDER_R = 12
FJ.POP_KNOB_SIZE = 36
FJ.POP_KNOB_STROKE_R = 0x44; FJ.POP_KNOB_STROKE_G = 0x2d; FJ.POP_KNOB_STROKE_B = 0x19; FJ.POP_KNOB_STROKE_W = 6
FJ.POP_LEVEL_STEP = 1
FJ.POP_LEVEL_MAX = 60
-- 设置完成按钮
FJ.POP_CONFIRM_CX = 540; FJ.POP_CONFIRM_CY = 1330; FJ.POP_CONFIRM_W = 410; FJ.POP_CONFIRM_H = 100
FJ.POP_CONFIRM_TEXT_FONT = 40
FJ.POP_CONFIRM_TEXT_R = 0x6d; FJ.POP_CONFIRM_TEXT_G = 0x4c; FJ.POP_CONFIRM_TEXT_B = 0x1d

-- 7. 奖励图标行（精粹+返还卷轴同排，奖励槽下方，每行最多 5 个，超出换行）
FJ.SCROLL_ROW1_CY = 570
FJ.SCROLL_ROW_STEP = 116
FJ.SCROLL_ICON_SIZE = 96
FJ.SCROLL_GAP = 24
FJ.SCROLL_MAX_PER_ROW = 5
FJ.SCROLL_MAX_ROWS = 2
FJ.SCROLL_BADGE_FONT = 32
FJ.SCROLL_BADGE_FONT_MIN = 18
FJ.SCROLL_BADGE_STROKE = 3

-- 格子布局计算
FJ.GRID_TOTAL_W = FJ.GRID_COLS * FJ.GRID_CELL + (FJ.GRID_COLS - 1) * FJ.GRID_GAP  -- 940
FJ.GRID_LEFT = (DESIGN_W - FJ.GRID_TOTAL_W) * 0.5  -- 70
FJ.GRID_FIRST_CX = FJ.GRID_LEFT + FJ.GRID_CELL * 0.5  -- 150
FJ.GRID_ROW_STEP = FJ.GRID_CELL + FJ.GRID_GAP  -- 195
FJ.GRID_COL_STEP = FJ.GRID_CELL + FJ.GRID_GAP  -- 195
FJ.GRID_FIRST_CY = FJ.PZSX_CY + FJ.PZSX_SIZE * 0.5 + 40 + FJ.GRID_CELL * 0.5  -- 1060

-- 品质名称和颜色映射
local QUALITY_CONFIG = {
    { name = "普通", r = 0x99, g = 0x99, b = 0x99 },
    { name = "优质", r = 0xa2, g = 0xff, b = 0x94 },
    { name = "稀有", r = 0x72, g = 0xf2, b = 0xf5 },
    { name = "史诗", r = 0xef, g = 0x79, b = 0xff },
    { name = "传说", r = 0xff, g = 0xed, b = 0x00 },
    { name = "至臻", r = 0xff, g = 0x00, b = 0x00 },
}

-- ======================== 分解界面状态 ========================

--- 请求门控（防重复提交）
local pendingDecompose = false      -- 分解请求是否正在等待服务端响应
local pendingDecomposeTime = 0      -- 发送时间戳（用于超时保护）
local DECOMPOSE_TIMEOUT = 10        -- 超时自动释放锁（秒）

local fjState = {
    scrollY = 0,
    selectedItems = {},
    touchStartY = nil,
    touchStartScroll = 0,
    -- 自动分解弹窗状态
    autoPopupOpen = false,
    autoQuality = 0,
    autoLevel = 0,
    levelSliderDragging = false,  -- 等级滑条是否正在拖拽
    -- 分解结果展示
    lastRewardEssence = nil,
    lastRewardGold = nil,
    -- 长按检测状态
    longPressStartTime = 0,     -- 按下时间戳
    longPressStartX = 0,        -- 按下时设计空间坐标
    longPressStartY = 0,
    longPressCellIdx = 0,       -- 按下时命中的格子索引（0=未命中）
    longPressFired = false,     -- 本次按下是否已触发长按
    longPressActive = false,    -- 当前是否正在检测长按
}

-- 长按常量
local LONG_PRESS_THRESHOLD = 0.4   -- 秒
local LONG_PRESS_MOVE_LIMIT = 20   -- 像素（超出此范围取消长按）

-- 背包数据
local backpackItems = {}

-- ======================== ctx 引用（由 setContext 注入） ========================

local imgGoldQBg      -- 金币品质背景框
local imgEssenceIcon   -- 精粹图标
local imgEnhBtn        -- 绿色按钮
local imgReplaceBtn    -- 黄色按钮
local imgCheckmark     -- 选中打钩
local imgQualityBg     -- 品质背景框 table
local getEquipIconCached  -- 装备图标缓存函数
local QUALITY_COST     -- 品质消耗配置
local ENHANCE_TABLE    -- 强化等级配置
local SLOT_BG_ALPHA    -- 装备槽透明度
local EQUIP_NAME_CX    -- 装备名称 X
local EQUIP_NAME_CY    -- 装备名称 Y
local EQUIP_NAME_FONT_SIZE  -- 装备名称字号
local EQUIP_NAME_STROKE     -- 装备名称描边
local getClient        -- 延迟加载 Client
local getProtocol      -- 延迟加载 Protocol

-- 分解界面专属图片
-- 品质筛选小图由 QualityMark 统一加载。
local imgPopupBg = -1     -- 弹窗背景
local imgBtnMinus = -1    -- 减按钮 UI_AN_JIAN
local imgBtnPlus = -1     -- 加按钮 UI_AN_JIA
local imgLock = -1        -- 锁定角标 UI_ICON_SUO

-- 返还卷轴图标懒加载缓存（type -> nvg 图片句柄）
---@type table<string, number>
local scrollIconCache = {}

---@param vg any
---@param resType string
---@return number
local function getScrollIcon(vg, resType)
    local cached = scrollIconCache[resType]
    if cached then return cached end
    local def = ResourceDefs.DEFS[resType]
    ---@type integer
    local img = -1
    if def then
        img = nvgCreateImage(vg, def.iconPath, 0) or -1
    end
    scrollIconCache[resType] = img
    return img
end

--- 角标字号自适应：数字过长时缩小，保证不溢出图标宽度
---@param vg any
---@param text string
---@return number
local function fitScrollBadgeFont(vg, text)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, FJ.SCROLL_BADGE_FONT)
    local w = nvgTextBounds(vg, 0, 0, text)
    local maxW = FJ.SCROLL_ICON_SIZE - 12
    if w <= maxW then return FJ.SCROLL_BADGE_FONT end
    return math.max(FJ.SCROLL_BADGE_FONT_MIN, FJ.SCROLL_BADGE_FONT * maxW / w)
end

--- 绘制奖励图标行（精粹+返还卷轴）：整体居中，每行最多 5 个，超出换行
---@param vg any
---@param entries table[] { type: string, amount: number }
local function drawScrollRefundIcons(vg, entries)
    local perRow = FJ.SCROLL_MAX_PER_ROW
    local step = FJ.SCROLL_ICON_SIZE + FJ.SCROLL_GAP
    local maxCount = perRow * FJ.SCROLL_MAX_ROWS
    local count = math.min(#entries, maxCount)
    for i = 1, count do
        local entry = entries[i]
        local row = math.ceil(i / perRow)
        local col = ((i - 1) % perRow) + 1
        local rowStart = (row - 1) * perRow + 1
        local rowEnd = math.min(#entries, row * perRow)
        local rowItemCount = rowEnd - rowStart + 1
        local rowW = rowItemCount * FJ.SCROLL_ICON_SIZE + (rowItemCount - 1) * FJ.SCROLL_GAP
        local cx = FJ.REWARD_CX - rowW * 0.5 + FJ.SCROLL_ICON_SIZE * 0.5 + (col - 1) * step
        local cy = FJ.SCROLL_ROW1_CY + (row - 1) * FJ.SCROLL_ROW_STEP

        local def = ResourceDefs.DEFS[entry.type]
        local q = def and def.quality or 1
        DarkIcon.drawQualityBg(vg, q, cx, cy, FJ.SCROLL_ICON_SIZE, FJ.SCROLL_ICON_SIZE, 1.0)
        local img = getScrollIcon(vg, entry.type)
        if img >= 0 then
            local inner = FJ.SCROLL_ICON_SIZE - 12
            drawImageCentered(vg, img, cx, cy, inner, inner, 1.0)
        end

        -- 数量角标（右下角，描边）
        local amtText = "×" .. tostring(entry.amount)
        local amtX = cx + FJ.SCROLL_ICON_SIZE * 0.5 - 6
        local amtY = cy + FJ.SCROLL_ICON_SIZE * 0.5 - 4
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fitScrollBadgeFont(vg, amtText))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        local sStep = math.pi * 2 / 16
        for si = 0, 15 do
            local sa = si * sStep
            nvgText(vg, amtX + math.cos(sa) * FJ.SCROLL_BADGE_STROKE,
                amtY + math.sin(sa) * FJ.SCROLL_BADGE_STROKE, amtText, nil)
        end
        nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
        nvgText(vg, amtX, amtY, amtText, nil)
    end
end

--- 注入共享上下文
---@param ctx table 由 BlacksmithPage 构造的共享上下文
function M.setContext(ctx)
    imgGoldQBg         = ctx.imgGoldQBg
    imgEssenceIcon     = ctx.imgEssenceIcon
    imgEnhBtn          = ctx.imgEnhBtn
    imgReplaceBtn      = ctx.imgReplaceBtn
    imgCheckmark       = ctx.imgCheckmark
    imgQualityBg       = ctx.imgQualityBg
    getEquipIconCached = ctx.getEquipIconCached
    QUALITY_COST       = ctx.QUALITY_COST
    ENHANCE_TABLE      = ctx.ENHANCE_TABLE
    SLOT_BG_ALPHA      = ctx.SLOT_BG_ALPHA
    EQUIP_NAME_CX      = ctx.EQUIP_NAME_CX
    EQUIP_NAME_CY      = ctx.EQUIP_NAME_CY
    EQUIP_NAME_FONT_SIZE = ctx.EQUIP_NAME_FONT_SIZE
    EQUIP_NAME_STROKE  = ctx.EQUIP_NAME_STROKE
    getClient          = ctx.getClient
    getProtocol        = ctx.getProtocol
end

--- 初始化分解界面专属图片
function M.init(vg)
    QualityMark.init(vg)
    -- 整图拉伸绘制（950x647），使用 POP 副本，调整原图不影响九宫格用法
    imgPopupBg = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TY_EJQRK_POP.png", 0)
    imgBtnMinus = nvgCreateImage(vg, "image/按钮/UI_AN_JIAN.png", 0)
    imgBtnPlus = nvgCreateImage(vg, "image/按钮/UI_AN_JIA.png", 0)
    imgLock = nvgCreateImage(vg, "image/通用图标/UI_ICON_SUO.png", 0)
    EquipmentDetail.init(vg)
end

-- ======================== 背包数据管理 ========================

--- 刷新背包数据：从 ClientDispatcher 获取最新装备数据，筛选出未穿戴的装备
function M.refreshBackpackItems()
    -- 记录刷新前选中的装备 seq（用于刷新后重映射）
    local oldSelectedSeqs = {}
    for idx in pairs(fjState.selectedItems) do
        local item = backpackItems[idx]
        if item and item.seq then
            oldSelectedSeqs[item.seq] = true
        end
    end

    local equipData = PlayerStore.Get("equipment")
    backpackItems = {}
    if not equipData or not equipData.inventory then
        fjState.selectedItems = {}
        return
    end

    -- 收集所有已穿戴的 seq
    local equippedSeqs = {}
    if equipData.equipped then
        for _, slots in pairs(equipData.equipped) do
            for _, eqSeq in pairs(slots) do
                equippedSeqs[eqSeq] = true
            end
        end
    end

    -- 筛选未穿戴的装备（seq 从 key 恢复，dehydrate 不保存 seq 字段）
    for seqStr, equip in pairs(equipData.inventory) do
        local seq = tonumber(seqStr)
        if seq and not equippedSeqs[seq] then
            equip.seq = seq
            backpackItems[#backpackItems + 1] = equip
        end
    end

    -- 按 seq 排序（新获得的在后面）
    table.sort(backpackItems, function(a, b)
        return (a.seq or 0) < (b.seq or 0)
    end)

    -- 基于 seq 重映射选中状态（锁定的装备不保留勾选）
    fjState.selectedItems = {}
    for idx, item in ipairs(backpackItems) do
        if oldSelectedSeqs[item.seq] and not item.locked then
            fjState.selectedItems[idx] = true
        end
    end
end

-- ======================== 打开/关闭/重置 ========================

--- 打开时重置分解状态
function M.onOpen()
    fjState.scrollY = 0
    fjState.selectedItems = {}
    fjState.lastRewardEssence = nil
    fjState.lastRewardGold = nil
    fjState.autoPopupOpen = false
    fjState.levelSliderDragging = false
    pendingDecompose = false   -- 重置门控
    -- 从服务端已保存的设置初始化自动分解参数
    local equipData = PlayerStore.Get("equipment")
    if equipData and equipData.settings then
        fjState.autoQuality = equipData.settings.autoQuality or 0
        fjState.autoLevel   = equipData.settings.autoLevel   or 0
    else
        fjState.autoQuality = 0
        fjState.autoLevel   = 0
    end
    M.refreshBackpackItems()
end

--- 切换到分解 tab 时重置
function M.onTabSwitch()
    fjState.scrollY = 0
    fjState.selectedItems = {}
    pendingDecompose = false   -- 重置门控
    M.refreshBackpackItems()
end

--- 装备数据更新时刷新背包
function M.onEquipmentDataUpdate()
    M.refreshBackpackItems()
end

--- 自动分解弹窗是否打开
---@return boolean
function M.isPopupOpen()
    return fjState.autoPopupOpen
end

--- 直接打开自动分解弹窗（供外部调用，如从战利品面板跳转）
function M.openAutoPopup()
    -- 同步最新的服务端设置
    local equipData = PlayerStore.Get("equipment")
    if equipData and equipData.settings then
        fjState.autoQuality = equipData.settings.autoQuality or 0
        fjState.autoLevel   = equipData.settings.autoLevel   or 0
    end
    fjState.autoPopupOpen = true
    fjState.levelSliderDragging = false
    print("[BlacksmithDecompose] openAutoPopup")
end

-- ======================== 绘制 ========================

--- 绘制上半部分奖励槽位内容
function M.drawUpperSlot(vg)
    -- 分解奖励图标槽位
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        FJ.REWARD_CX - FJ.REWARD_SIZE * 0.5, FJ.REWARD_CY - FJ.REWARD_SIZE * 0.5,
        FJ.REWARD_SIZE, FJ.REWARD_SIZE, FJ.REWARD_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
    nvgFill(vg)
    DarkIcon.drawQualityBg(vg, 2, FJ.REWARD_CX, FJ.REWARD_CY, FJ.REWARD_SIZE, FJ.REWARD_SIZE, 1.0)  -- [暗黑化 P2-A] 原 UI_icon_ZBBJ_2
    drawImageCentered(vg, imgEssenceIcon, FJ.REWARD_CX, FJ.REWARD_CY, FJ.REWARD_SIZE, FJ.REWARD_SIZE, 1.0)

    -- 计算选中装备的预估精粹奖励，以及升阶卷轴 70% 返还
    local previewEssence = 0
    local selCount = 0
    local previewScrolls = {}
    for idx in pairs(fjState.selectedItems) do
        local item = backpackItems[idx]
        if item then
            selCount = selCount + 1
            local q = item.quality or 1
            local lv = item.level or 1
            local qCost = QUALITY_COST[q] or QUALITY_COST[1]
            previewEssence = previewEssence + math.floor(qCost.decBase * (1 + lv * qCost.decScale))
            local slot = item.slot
            if not slot and item.templateId then
                local tpl = EquipmentConfig.ITEMS[item.templateId]
                    or EquipmentConfig.ITEMS[tostring(item.templateId)]
                slot = tpl and tpl.slot
            end
            local field = slot and BlacksmithConfig.SLOT_SCROLL_MAP[slot]
            local refund = BlacksmithConfig.calcAscendScrollRefund(EquipmentSystem.getAscendLevel(item))
            if field and refund > 0 then
                previewScrolls[field] = (previewScrolls[field] or 0) + refund
            end
        end
    end

    -- 奖励图标行：精粹与返还卷轴同排（整体居中，超过 5 个换行）
    local essenceAmount = 0
    if selCount > 0 then
        essenceAmount = previewEssence
    elseif fjState.lastRewardEssence then
        essenceAmount = fjState.lastRewardEssence
    end
    local scrollEntries = BlacksmithConfig.collectScrollRefundEntries(previewScrolls)
    if #scrollEntries == 0 and selCount == 0 and fjState.lastScrollEntries then
        scrollEntries = fjState.lastScrollEntries
    end
    ---@type table[]
    local entries = {}
    if essenceAmount > 0 then
        entries[#entries + 1] = { type = "essence", amount = essenceAmount }
    end
    for _, e in ipairs(scrollEntries) do
        entries[#entries + 1] = e
    end
    if #entries > 0 then
        drawScrollRefundIcons(vg, entries)
    else
        drawTextStroke(vg, FJ.REWARD_CX, FJ.REWARD_CY + FJ.REWARD_SIZE * 0.5 + 30, "分解奖励",
            36, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)
    end
end

--- 绘制分解面板（下半部分）
function M.drawPanel(vg)
    -- 长按检测：每帧检查是否超过阈值
    if fjState.longPressActive and not fjState.longPressFired then
        local elapsed = time.elapsedTime - fjState.longPressStartTime
        if elapsed >= LONG_PRESS_THRESHOLD then
            fjState.longPressFired = true
            fjState.longPressActive = false
            local cellIdx = fjState.longPressCellIdx
            if cellIdx > 0 and cellIdx <= #backpackItems then
                local item = backpackItems[cellIdx]
                if item and item.seq then
                    EquipmentDetail.open(item.seq, nil, nil, true, "smith")
                    print("[BlacksmithDecompose] 长按打开装备详情 idx=" .. cellIdx .. " seq=" .. item.seq)
                end
            end
        end
    end

    -- 1. "分解装备" 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, FJ.TITLE_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(FJ.TITLE_R, FJ.TITLE_G, FJ.TITLE_B, 255))
    nvgText(vg, FJ.TITLE_X, FJ.TITLE_Y, "分解装备", nil)

    -- 2. 品质筛选图标
    for i = 1, 5 do
        local cx = FJ.PZSX_FIRST_CX + (i - 1) * (FJ.PZSX_SIZE + FJ.PZSX_GAP)
        local didScale = BF.begin(vg, "bsd_filter_" .. i, cx, FJ.PZSX_CY, FJ.PZSX_SIZE, FJ.PZSX_SIZE)
        QualityMark.draw(vg, i, cx, FJ.PZSX_CY, FJ.PZSX_SIZE, 1.0)
        BF.finish(vg, didScale)
    end

    -- 3. 背包装备格子（可滚动区域）
    local totalSlots = EquipmentSystem.MAX_INVENTORY
    local itemCount = #backpackItems
    local totalRows = math.ceil(totalSlots / FJ.GRID_COLS)
    local visibleH = FJ.GRID_BOTTOM_Y - (FJ.GRID_FIRST_CY - FJ.GRID_CELL * 0.5)
    local contentH = totalRows * FJ.GRID_ROW_STEP - FJ.GRID_GAP
    local maxScroll = math.max(0, contentH - visibleH)
    fjState.scrollY = math.max(0, math.min(fjState.scrollY, maxScroll))

    nvgSave(vg)
    nvgIntersectScissor(vg, 0, FJ.GRID_FIRST_CY - FJ.GRID_CELL * 0.5,
        DESIGN_W, visibleH)

    for idx = 1, totalSlots do
        local row = math.ceil(idx / FJ.GRID_COLS)
        local col = ((idx - 1) % FJ.GRID_COLS) + 1
        local cx = FJ.GRID_FIRST_CX + (col - 1) * FJ.GRID_COL_STEP
        local cy = FJ.GRID_FIRST_CY + (row - 1) * FJ.GRID_ROW_STEP - fjState.scrollY

        local topY = FJ.GRID_FIRST_CY - FJ.GRID_CELL * 0.5
        if cy + FJ.GRID_CELL * 0.5 < topY or cy - FJ.GRID_CELL * 0.5 > FJ.GRID_BOTTOM_Y then
            goto continue_slot
        end

        if idx <= itemCount then
            local item = backpackItems[idx]
            local didScaleCell = BF.begin(vg, "bsd_cell_" .. idx, cx, cy, FJ.GRID_CELL, FJ.GRID_CELL)
            DarkIcon.drawQualityBg(vg, item.quality or 1, cx, cy, FJ.GRID_CELL, FJ.GRID_CELL, 1.0)  -- [暗黑化 P2-A]
            local eqIcon = getEquipIconCached(item.templateId)
            if eqIcon and eqIcon > 0 then
                DarkIcon.drawIconDark(vg, eqIcon, cx, cy, FJ.GRID_CELL - 16, FJ.GRID_CELL - 16, 1.0)  -- [暗黑化 P2-B]
            end

            -- 强化角标
            local enhLv = item.enhanceLevel or 0
            if enhLv > 0 then
                local enhText = "+" .. enhLv
                local enhX = cx + FJ.GRID_CELL * 0.5 - 8
                local enhY = cy - FJ.GRID_CELL * 0.5 + 8
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 36)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                local sStep = math.pi * 2 / 16
                for si = 0, 15 do
                    local sa = si * sStep
                    nvgText(vg, enhX + math.cos(sa) * 3, enhY + math.sin(sa) * 3, enhText, nil)
                end
                nvgFillColor(vg, nvgRGBA(0x00, 0xff, 0x60, 255))
                nvgText(vg, enhX, enhY, enhText, nil)
            end

            -- 等级角标
            local itemLv = item.level or 1
            if itemLv >= 1 then
                local lvlText = "Lv." .. itemLv
                local lvlX = cx + FJ.GRID_CELL * 0.5 - 8
                local lvlY = cy + FJ.GRID_CELL * 0.5 - 6
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 40)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                local sStep = math.pi * 2 / 16
                for si = 0, 15 do
                    local sa = si * sStep
                    nvgText(vg, lvlX + math.cos(sa) * 4, lvlY + math.sin(sa) * 4, lvlText, nil)
                end
                nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                nvgText(vg, lvlX, lvlY, lvlText, nil)
            end

            -- 锁定角标（左上角）
            if item.locked and imgLock >= 0 then
                local lockSize = 56
                local lockCX = cx - FJ.GRID_CELL * 0.5 + lockSize * 0.5 + 4
                local lockCY = cy - FJ.GRID_CELL * 0.5 + lockSize * 0.5 + 4
                drawImageCentered(vg, imgLock, lockCX, lockCY, lockSize, lockSize, 1.0)
            end

            -- 选中状态
            if fjState.selectedItems[idx] then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - FJ.GRID_CELL * 0.5, cy - FJ.GRID_CELL * 0.5,
                    FJ.GRID_CELL, FJ.GRID_CELL, FJ.GRID_RADIUS)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, FJ.SEL_MASK_ALPHA))
                nvgFill(vg)
                drawImageCentered(vg, imgCheckmark, cx, cy, FJ.SEL_CHECK_SIZE, FJ.SEL_CHECK_SIZE, 1.0)
            end
            BF.finish(vg, didScaleCell)
        else
            -- 空格子
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - FJ.GRID_CELL * 0.5, cy - FJ.GRID_CELL * 0.5,
                FJ.GRID_CELL, FJ.GRID_CELL, FJ.GRID_RADIUS)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 25))
            nvgFill(vg)
        end

        ::continue_slot::
    end

    nvgRestore(vg)

    -- 4. 自动分解按钮 UI_AN_HUANG
    local didScaleAuto = BF.begin(vg, "bsd_auto", FJ.AUTO_BTN_CX, FJ.AUTO_BTN_CY, FJ.AUTO_BTN_W, FJ.AUTO_BTN_H)
    drawImageCentered(vg, imgReplaceBtn, FJ.AUTO_BTN_CX, FJ.AUTO_BTN_CY, FJ.AUTO_BTN_W, FJ.AUTO_BTN_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, FJ.AUTO_TEXT_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(FJ.AUTO_TEXT_R, FJ.AUTO_TEXT_G, FJ.AUTO_TEXT_B, 255))
    nvgText(vg, FJ.AUTO_BTN_CX, FJ.AUTO_BTN_CY, "自动分解", nil)
    BF.finish(vg, didScaleAuto)

    -- 5. 分解按钮 UI_AN_LV
    local didScaleDec = BF.begin(vg, "bsd_decompose", FJ.DEC_BTN_CX, FJ.DEC_BTN_CY, FJ.DEC_BTN_W, FJ.DEC_BTN_H)
    drawImageCentered(vg, imgEnhBtn, FJ.DEC_BTN_CX, FJ.DEC_BTN_CY, FJ.DEC_BTN_W, FJ.DEC_BTN_H, 1.0)
    nvgFillColor(vg, nvgRGBA(FJ.DEC_TEXT_R, FJ.DEC_TEXT_G, FJ.DEC_TEXT_B, 255))
    nvgText(vg, FJ.DEC_BTN_CX, FJ.DEC_BTN_CY, "分解", nil)
    BF.finish(vg, didScaleDec)
end

--- 第 i 个品质方框的中心 X
---@param i integer 1-6
---@return number
local function qboxCX(i)
    return FJ.POP_QBOX_FIRST_CX + (i - 1) * (FJ.POP_QBOX_SIZE + FJ.POP_QBOX_GAP)
end

--- 等级滑条比例（0=无，1=满级上限）
---@return number
local function levelSliderFrac()
    return math.max(0, math.min(1, fjState.autoLevel / FJ.POP_LEVEL_MAX))
end

--- 由滑条 X 坐标换算等级（吸附到 STEP 档位）
---@param dx number
---@return integer
local function levelFromSliderX(dx)
    local sliderL = FJ.POP_SLIDER_CX - FJ.POP_SLIDER_W * 0.5
    local frac = math.max(0, math.min(1, (dx - sliderL) / FJ.POP_SLIDER_W))
    local steps = FJ.POP_LEVEL_MAX / FJ.POP_LEVEL_STEP
    return math.floor(frac * steps + 0.5) * FJ.POP_LEVEL_STEP
end

--- 滑条命中区域高度（含滑块溢出）
---@return number
local function sliderHitH()
    return math.max(FJ.POP_SLIDER_H, FJ.POP_KNOB_SIZE) + 20
end

--- 按当前选中条件生成描述分段（品质名用品质色，其余灰白）
---@return {text:string, r:integer, g:integer, b:integer}[]
local function buildConditionSegments()
    local gr, gg, gb = FJ.POP_DESC_R, FJ.POP_DESC_G, FJ.POP_DESC_B
    local segs = {}
    local function addGray(text)
        segs[#segs + 1] = { text = text, r = gr, g = gg, b = gb }
    end
    if fjState.autoQuality > 0 then
        local qCfg = QUALITY_CONFIG[fjState.autoQuality]
        if qCfg then
            segs[#segs + 1] = { text = qCfg.name, r = qCfg.r, g = qCfg.g, b = qCfg.b }
        end
        addGray("级及以下")
    end
    if fjState.autoQuality > 0 and fjState.autoLevel > 0 then
        addGray("且")
    end
    if fjState.autoLevel > 0 then
        addGray(tostring(fjState.autoLevel) .. "级及以下")
    end
    if #segs == 0 then
        addGray("未设置条件，掉落装备不会自动分解")
        return segs
    end
    addGray("的装备会在掉落时自动分解")
    return segs
end

--- 绘制自动分解弹窗
function M.drawAutoDecomposePopup(vg)
    if not fjState.autoPopupOpen then return end

    -- 1. 黑色 50% 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, FJ.POP_MASK_ALPHA))
    nvgFill(vg)

    -- 2. 弹窗背景
    drawImageCentered(vg, imgPopupBg, FJ.POP_BG_CX, FJ.POP_BG_CY, FJ.POP_BG_W, FJ.POP_BG_H, 1.0)

    -- 3. 标题
    drawTextStroke(vg, FJ.POP_TITLE_CX, FJ.POP_TITLE_CY, "设置自动分解",
        FJ.POP_TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, FJ.POP_TITLE_STROKE)

    -- 4. 描述文本（分段绘制：品质名品质色，其余灰白；超宽自动缩字号）
    local segs = buildConditionSegments()
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, FJ.POP_DESC_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local function measureSegs()
        local total = 0
        for _, s in ipairs(segs) do
            s.w = nvgTextBounds(vg, 0, 0, s.text)
            total = total + s.w
        end
        return total
    end
    local totalW = measureSegs()
    if totalW > FJ.POP_DESC_MAX_W then
        nvgFontSize(vg, math.max(26, math.floor(FJ.POP_DESC_FONT * FJ.POP_DESC_MAX_W / totalW)))
        totalW = measureSegs()
    end
    local segX = FJ.POP_DESC_CX - totalW * 0.5
    for _, s in ipairs(segs) do
        nvgFillColor(vg, nvgRGBA(s.r, s.g, s.b, 255))
        nvgText(vg, segX, FJ.POP_DESC_CY, s.text, nil)
        segX = segX + s.w
    end

    -- 5. 品质方框选择（6 个品质图标方框，选中高亮描边）
    for i = 1, FJ.POP_QBOX_COUNT do
        local cx = qboxCX(i)
        local selected = (fjState.autoQuality == i)
        local didScaleQ = BF.begin(vg, "bsd_qbox_" .. i, cx, FJ.POP_QBOX_CY, FJ.POP_QBOX_SIZE, FJ.POP_QBOX_SIZE)

        -- 方框底板
        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            cx - FJ.POP_QBOX_SIZE * 0.5, FJ.POP_QBOX_CY - FJ.POP_QBOX_SIZE * 0.5,
            FJ.POP_QBOX_SIZE, FJ.POP_QBOX_SIZE, FJ.POP_QBOX_R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, selected and 60 or 25))
        nvgFill(vg)

        -- 品质小图
        QualityMark.draw(vg, i, cx, FJ.POP_QBOX_CY - 8, FJ.POP_QBOX_ICON_SIZE, selected and 1.0 or 0.55)

        -- 品质名（小字，置于方框内底部）
        local qCfg = QUALITY_CONFIG[i]
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 24)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(qCfg.r, qCfg.g, qCfg.b, selected and 255 or 160))
        nvgText(vg, cx, FJ.POP_QBOX_CY + 34, qCfg.name, nil)

        -- 选中描边
        if selected then
            nvgBeginPath(vg)
            nvgRoundedRect(vg,
                cx - FJ.POP_QBOX_SIZE * 0.5, FJ.POP_QBOX_CY - FJ.POP_QBOX_SIZE * 0.5,
                FJ.POP_QBOX_SIZE, FJ.POP_QBOX_SIZE, FJ.POP_QBOX_R)
            nvgStrokeColor(vg, nvgRGBA(qCfg.r, qCfg.g, qCfg.b, 255))
            nvgStrokeWidth(vg, FJ.POP_QBOX_SEL_STROKE)
            nvgStroke(vg)
        end
        BF.finish(vg, didScaleQ)
    end

    -- 6. 减按钮（0 档时半透明）
    local didScaleMinus = BF.begin(vg, "bsd_minus", FJ.POP_MINUS_CX, FJ.POP_MINUS_CY, FJ.POP_MINUS_W, FJ.POP_MINUS_H)
    drawImageCentered(vg, imgBtnMinus, FJ.POP_MINUS_CX, FJ.POP_MINUS_CY,
        FJ.POP_MINUS_W, FJ.POP_MINUS_H, fjState.autoLevel <= 0 and 0.4 or 1.0)
    BF.finish(vg, didScaleMinus)

    -- 7. 加按钮（满档时半透明）
    local didScalePlus = BF.begin(vg, "bsd_plus", FJ.POP_PLUS_CX, FJ.POP_PLUS_CY, FJ.POP_PLUS_W, FJ.POP_PLUS_H)
    drawImageCentered(vg, imgBtnPlus, FJ.POP_PLUS_CX, FJ.POP_PLUS_CY,
        FJ.POP_PLUS_W, FJ.POP_PLUS_H, fjState.autoLevel >= FJ.POP_LEVEL_MAX and 0.4 or 1.0)
    BF.finish(vg, didScalePlus)

    -- 8. 滑条背景
    local sliderL = FJ.POP_SLIDER_CX - FJ.POP_SLIDER_W * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderL, FJ.POP_SLIDER_CY - FJ.POP_SLIDER_H * 0.5,
        FJ.POP_SLIDER_W, FJ.POP_SLIDER_H, FJ.POP_SLIDER_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 51))
    nvgFill(vg)

    -- 已填充部分
    local frac = levelSliderFrac()
    local fillW = FJ.POP_SLIDER_W * frac
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sliderL, FJ.POP_SLIDER_CY - FJ.POP_SLIDER_H * 0.5,
            fillW, FJ.POP_SLIDER_H, FJ.POP_SLIDER_R)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 80))
        nvgFill(vg)
    end

    -- 9. 滑块（圆形，纯白+描边）
    local knobX = sliderL + FJ.POP_SLIDER_W * frac
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, FJ.POP_SLIDER_CY, FJ.POP_KNOB_SIZE * 0.5)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(FJ.POP_KNOB_STROKE_R, FJ.POP_KNOB_STROKE_G, FJ.POP_KNOB_STROKE_B, 255))
    nvgStrokeWidth(vg, FJ.POP_KNOB_STROKE_W)
    nvgStroke(vg)

    -- 10. 设置完成按钮
    local didScaleConfirm = BF.begin(vg, "bsd_confirm", FJ.POP_CONFIRM_CX, FJ.POP_CONFIRM_CY, FJ.POP_CONFIRM_W, FJ.POP_CONFIRM_H)
    drawImageCentered(vg, imgReplaceBtn, FJ.POP_CONFIRM_CX, FJ.POP_CONFIRM_CY,
        FJ.POP_CONFIRM_W, FJ.POP_CONFIRM_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, FJ.POP_CONFIRM_TEXT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(FJ.POP_CONFIRM_TEXT_R, FJ.POP_CONFIRM_TEXT_G, FJ.POP_CONFIRM_TEXT_B, 255))
    nvgText(vg, FJ.POP_CONFIRM_CX, FJ.POP_CONFIRM_CY, "设置完成", nil)
    BF.finish(vg, didScaleConfirm)
end

-- ======================== 输入处理 ========================

--- 处理自动分解弹窗输入（优先级最高）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function M.handlePopupInput(dx, dy)
    -- 装备详情面板优先拦截
    if EquipmentDetail.isOpen() then
        return EquipmentDetail.handleInput(dx, dy)
    end
    if not fjState.autoPopupOpen then return false end

    -- 品质方框选择（1-6，再次点击已选中的方框则取消为"无"）
    for i = 1, FJ.POP_QBOX_COUNT do
        local cx = qboxCX(i)
        if hitTest(dx, dy, cx, FJ.POP_QBOX_CY, FJ.POP_QBOX_SIZE, FJ.POP_QBOX_SIZE) then
            BF.trigger("bsd_qbox_" .. i)
            if fjState.autoQuality == i then
                fjState.autoQuality = 0
                print("[BlacksmithDecompose] 品质筛选取消: 无")
            else
                fjState.autoQuality = i
                print("[BlacksmithDecompose] 品质筛选选择: " .. QUALITY_CONFIG[i].name .. "级及以下")
            end
            return true
        end
    end
    -- 等级减按钮
    if hitTest(dx, dy, FJ.POP_MINUS_CX, FJ.POP_MINUS_CY, FJ.POP_MINUS_W, FJ.POP_MINUS_H) then
        BF.trigger("bsd_minus")
        fjState.autoLevel = math.max(0, fjState.autoLevel - FJ.POP_LEVEL_STEP)
        print("[BlacksmithDecompose] 等级筛选降低: " .. (fjState.autoLevel == 0 and "无" or fjState.autoLevel))
        return true
    end
    -- 等级加按钮
    if hitTest(dx, dy, FJ.POP_PLUS_CX, FJ.POP_PLUS_CY, FJ.POP_PLUS_W, FJ.POP_PLUS_H) then
        BF.trigger("bsd_plus")
        fjState.autoLevel = math.min(FJ.POP_LEVEL_MAX, fjState.autoLevel + FJ.POP_LEVEL_STEP)
        print("[BlacksmithDecompose] 等级筛选提高: " .. fjState.autoLevel)
        return true
    end
    -- 滑条点击（整个滑条区域 + 滑块溢出范围），并进入拖拽
    if hitTest(dx, dy, FJ.POP_SLIDER_CX, FJ.POP_SLIDER_CY, FJ.POP_SLIDER_W + FJ.POP_KNOB_SIZE, sliderHitH()) then
        fjState.levelSliderDragging = true
        fjState.autoLevel = levelFromSliderX(dx)
        print("[BlacksmithDecompose] 滑条点击等级: " .. (fjState.autoLevel == 0 and "无" or fjState.autoLevel))
        return true
    end
    -- 设置完成按钮
    if hitTest(dx, dy, FJ.POP_CONFIRM_CX, FJ.POP_CONFIRM_CY, FJ.POP_CONFIRM_W, FJ.POP_CONFIRM_H) then
        BF.trigger("bsd_confirm")
        fjState.autoPopupOpen = false
        -- 发送自动分解设置到服务端保存
        getClient().sendAction(getProtocol().ACTION_TYPES.SET_AUTO_DECOMPOSE, {
            autoQuality = fjState.autoQuality,
            autoLevel   = fjState.autoLevel,
        })
        local qLabel = fjState.autoQuality == 0 and "无" or QUALITY_CONFIG[fjState.autoQuality].name
        local lLabel = fjState.autoLevel == 0 and "无" or tostring(fjState.autoLevel)
        print("[BlacksmithDecompose] 自动分解设置保存 - 品质:" .. qLabel .. " 等级:" .. lLabel)
        return true
    end
    -- 点击弹窗背景外区域：关闭弹窗并保存设置
    if not hitTest(dx, dy, FJ.POP_BG_CX, FJ.POP_BG_CY, FJ.POP_BG_W, FJ.POP_BG_H) then
        fjState.autoPopupOpen = false
        getClient().sendAction(getProtocol().ACTION_TYPES.SET_AUTO_DECOMPOSE, {
            autoQuality = fjState.autoQuality,
            autoLevel   = fjState.autoLevel,
        })
        print("[BlacksmithDecompose] 点击空白关闭自动分解面板")
        return true
    end
    -- 弹窗内部空白区域消费事件（防止穿透）
    return true
end

--- 处理分解面板输入（品质筛选、分解按钮、自动分解按钮、格子点击）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function M.handleInput(dx, dy)
    -- 装备详情打开时拦截所有输入
    if EquipmentDetail.isOpen() then return true end

    -- 超时保护：若门控锁超过 DECOMPOSE_TIMEOUT 秒仍未释放，强制解锁
    if pendingDecompose and (time.elapsedTime - pendingDecomposeTime) >= DECOMPOSE_TIMEOUT then
        print("[BlacksmithDecompose] 分解请求超时，强制释放门控")
        pendingDecompose = false
    end

    -- 品质筛选图标点击
    for i = 1, 5 do
        local cx = FJ.PZSX_FIRST_CX + (i - 1) * (FJ.PZSX_SIZE + FJ.PZSX_GAP)
        if hitTest(dx, dy, cx, FJ.PZSX_CY, FJ.PZSX_SIZE, FJ.PZSX_SIZE) then
            BF.trigger("bsd_filter_" .. i)
            fjState.selectedItems = {}
            for idx, item in ipairs(backpackItems) do
                -- 锁定的装备不参与一键选择
                if (item.quality or 1) <= i and not item.locked then
                    fjState.selectedItems[idx] = true
                end
            end
            print("[BlacksmithDecompose] 品质筛选点击: <=" .. QUALITY_CONFIG[i].name)
            return true
        end
    end

    -- 分解按钮
    if hitTest(dx, dy, FJ.DEC_BTN_CX, FJ.DEC_BTN_CY, FJ.DEC_BTN_W, FJ.DEC_BTN_H) then
        BF.trigger("bsd_decompose")
        -- 门控：等待上次请求完成
        if pendingDecompose then
            print("[BlacksmithDecompose] 分解请求等待中，忽略重复点击")
            return true
        end
        local selectedSeqs = {}
        for idx, selected in pairs(fjState.selectedItems) do
            if selected and backpackItems[idx] then
                selectedSeqs[#selectedSeqs + 1] = backpackItems[idx].seq
            end
        end
        if #selectedSeqs > 0 then
            pendingDecompose = true
            pendingDecomposeTime = time.elapsedTime
            getClient().sendAction(getProtocol().ACTION_TYPES.DECOMPOSE_EQUIP, { seqs = selectedSeqs })
            print("[BlacksmithDecompose] 发送分解请求，数量: " .. #selectedSeqs)
        else
            print("[BlacksmithDecompose] 未选择任何装备")
        end
        return true
    end

    -- 自动分解按钮
    if hitTest(dx, dy, FJ.AUTO_BTN_CX, FJ.AUTO_BTN_CY, FJ.AUTO_BTN_W, FJ.AUTO_BTN_H) then
        BF.trigger("bsd_auto")
        fjState.autoPopupOpen = true
        print("[BlacksmithDecompose] 打开自动分解弹窗")
        return true
    end

    -- 背包格子点击（长按已触发时跳过选择切换）
    if not fjState.longPressFired then
        local itemCount = #backpackItems
        for idx = 1, itemCount do
            local row = math.ceil(idx / FJ.GRID_COLS)
            local col = ((idx - 1) % FJ.GRID_COLS) + 1
            local cx = FJ.GRID_FIRST_CX + (col - 1) * FJ.GRID_COL_STEP
            local cy = FJ.GRID_FIRST_CY + (row - 1) * FJ.GRID_ROW_STEP - fjState.scrollY
            if hitTest(dx, dy, cx, cy, FJ.GRID_CELL, FJ.GRID_CELL) then
                local topY = FJ.GRID_FIRST_CY - FJ.GRID_CELL * 0.5
                local botY = FJ.GRID_BOTTOM_Y
                if cy >= topY and cy <= botY then
                    local item = backpackItems[idx]
                    if item and item.locked then
                        -- 锁定的装备不可选择分解
                        BF.trigger("bsd_cell_" .. idx)
                        print("[BlacksmithDecompose] 背包格子已锁定，无法选择: " .. idx)
                    else
                        BF.trigger("bsd_cell_" .. idx)
                        fjState.selectedItems[idx] = not fjState.selectedItems[idx] or nil
                        print("[BlacksmithDecompose] 背包格子点击: " .. idx)
                    end
                end
                return true
            end
        end
    end

    return false
end

-- ======================== 拖拽与滚动 ========================

--- 拖拽开始
function M.handleDragBegin(dx, dy)
    if EquipmentDetail.isOpen() then return EquipmentDetail.handleDragBegin(dx, dy) end
    -- 自动分解弹窗打开时：滑条拖拽优先，且不滚动背包
    if fjState.autoPopupOpen then
        if hitTest(dx, dy, FJ.POP_SLIDER_CX, FJ.POP_SLIDER_CY, FJ.POP_SLIDER_W + FJ.POP_KNOB_SIZE, sliderHitH()) then
            fjState.levelSliderDragging = true
            fjState.autoLevel = levelFromSliderX(dx)
        end
        return
    end
    fjState.touchStartY = dy
    fjState.touchStartScroll = fjState.scrollY

    -- 长按检测：记录按下位置和时间，识别命中的格子
    fjState.longPressStartTime = time.elapsedTime
    fjState.longPressStartX = dx
    fjState.longPressStartY = dy
    fjState.longPressFired = false
    fjState.longPressActive = false
    fjState.longPressCellIdx = 0

    local itemCount = #backpackItems
    for idx = 1, itemCount do
        local row = math.ceil(idx / FJ.GRID_COLS)
        local col = ((idx - 1) % FJ.GRID_COLS) + 1
        local cx = FJ.GRID_FIRST_CX + (col - 1) * FJ.GRID_COL_STEP
        local cy = FJ.GRID_FIRST_CY + (row - 1) * FJ.GRID_ROW_STEP - fjState.scrollY
        if hitTest(dx, dy, cx, cy, FJ.GRID_CELL, FJ.GRID_CELL) then
            local topY = FJ.GRID_FIRST_CY - FJ.GRID_CELL * 0.5
            local botY = FJ.GRID_BOTTOM_Y
            if cy >= topY and cy <= botY then
                fjState.longPressCellIdx = idx
                fjState.longPressActive = true
            end
            break
        end
    end
end

--- 拖拽移动
function M.handleDragMove(dx, dy)
    if EquipmentDetail.isOpen() then return EquipmentDetail.handleDragMove(dx, dy) end
    -- 滑条拖拽中：跟随 X 更新等级
    if fjState.levelSliderDragging then
        fjState.autoLevel = levelFromSliderX(dx)
        return
    end
    if fjState.autoPopupOpen then return end
    -- 长按检测：移动超限则取消
    if fjState.longPressActive then
        local moveDist = math.abs(dx - fjState.longPressStartX) + math.abs(dy - fjState.longPressStartY)
        if moveDist > LONG_PRESS_MOVE_LIMIT then
            fjState.longPressActive = false
            fjState.longPressCellIdx = 0
        end
    end
    if fjState.touchStartY then
        local delta = fjState.touchStartY - dy
        local totalSlots = EquipmentSystem.MAX_INVENTORY
        local totalRows = math.ceil(totalSlots / FJ.GRID_COLS)
        local visibleH = FJ.GRID_BOTTOM_Y - (FJ.GRID_FIRST_CY - FJ.GRID_CELL * 0.5)
        local contentH = totalRows * FJ.GRID_ROW_STEP - FJ.GRID_GAP
        local maxScroll = math.max(0, contentH - visibleH)
        fjState.scrollY = math.max(0, math.min(fjState.touchStartScroll + delta, maxScroll))
    end
end

--- 拖拽结束
function M.handleDragEnd(dx, dy)
    if EquipmentDetail.isOpen() then return EquipmentDetail.handleDragEnd(dx, dy) end
    if fjState.levelSliderDragging then
        fjState.levelSliderDragging = false
        print("[BlacksmithDecompose] 滑条拖拽结束，等级: " .. (fjState.autoLevel == 0 and "无" or fjState.autoLevel))
    end
    if fjState.autoPopupOpen then return end
    fjState.touchStartY = nil
    -- 重置长按状态
    fjState.longPressActive = false
    fjState.longPressCellIdx = 0
end

--- 鼠标滚轮。详情只在鼠标落在弹窗上时接管。
---@param wheel number
---@param dx number|nil
---@param dy number|nil
function M.handleScroll(wheel, dx, dy)
    if fjState.autoPopupOpen then return end
    if EquipmentDetail.isOpen() then
        if dx == nil or EquipmentDetail.containsPoint(dx, dy) then
            EquipmentDetail.handleScroll(wheel, dx, dy)
            return
        end
    end
    local scrollStep = FJ.GRID_ROW_STEP
    local totalSlots = EquipmentSystem.MAX_INVENTORY
    local totalRows = math.ceil(totalSlots / FJ.GRID_COLS)
    local visibleH = FJ.GRID_BOTTOM_Y - (FJ.GRID_FIRST_CY - FJ.GRID_CELL * 0.5)
    local contentH = totalRows * FJ.GRID_ROW_STEP - FJ.GRID_GAP
    local maxScroll = math.max(0, contentH - visibleH)
    fjState.scrollY = math.max(0, math.min(fjState.scrollY - wheel * scrollStep, maxScroll))
end

-- ======================== 结果处理 ========================

--- 处理分解结果（成功和失败都会调用，用于释放门控）
---@param data table action result 数据
function M.onActionResult(data)
    -- 无论成功/失败，都释放门控锁
    if pendingDecompose then
        pendingDecompose = false
        print("[BlacksmithDecompose] 门控释放" .. (data.decomposed and "（成功）" or "（失败/无关）"))
    end
    if not data.decomposed then return end
    local essenceReward = data.essenceReward or 0
    local goldReward = data.goldReward or 0
    fjState.lastRewardEssence = essenceReward
    fjState.lastRewardGold = goldReward
    fjState.selectedItems = {}
    M.refreshBackpackItems()
    -- 弹出奖励提示框
    local rewards = {}
    if essenceReward > 0 then
        rewards[#rewards + 1] = { type = "essence", amount = essenceReward }
    end
    if goldReward > 0 then
        rewards[#rewards + 1] = { type = "gold", amount = goldReward }
    end
    BlacksmithConfig.appendScrollRewardItems(rewards, data.scrollRewards)
    local entries = BlacksmithConfig.collectScrollRefundEntries(data.scrollRewards)
    fjState.lastScrollEntries = #entries > 0 and entries or nil
    if #rewards > 0 then
        RewardPopup.show("分解奖励", rewards)
    end
    print("[BlacksmithDecompose] 分解完成，获得精粹: " .. tostring(essenceReward)
        .. " (含洗练返还: " .. tostring(data.refineReturn or 0) .. ")"
        .. " 金币: " .. tostring(goldReward)
        .. " 卷轴: " .. tostring(data.scrollReward or 0)
        .. "，分解数量: " .. tostring(data.decomposeCount))
end

return M
