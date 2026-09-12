-- ============================================================================
-- BlacksmithDecompose.lua
-- 铁匠铺 - 分解子模块：背包格子、品质筛选、自动分解弹窗
-- 从 BlacksmithPage.lua 拆分而来
-- ============================================================================

---@diagnostic disable: undefined-global

local GameConfig       = require("config.GameConfig")
local DrawUtil         = require("core.DrawUtil")
local EquipmentConfig  = require("config.EquipmentConfig")
local EquipmentSystem  = require("systems.EquipmentSystem")
local PlayerStore      = require("client.data.PlayerStore")
local RewardPopup      = require("ui.RewardPopup")
local EquipmentDetail  = require("ui.EquipmentDetail")

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
    DEC_TEXT_R = 0x25, DEC_TEXT_G = 0x55, DEC_TEXT_B = 0x3d,
}
-- 自动分解弹窗常量
FJ.POP_MASK_ALPHA = 128
FJ.POP_BG_CX = 540; FJ.POP_BG_CY = 1111; FJ.POP_BG_W = 950; FJ.POP_BG_H = 647
FJ.POP_TITLE_CX = 540; FJ.POP_TITLE_CY = 856; FJ.POP_TITLE_FONT = 60; FJ.POP_TITLE_STROKE = 4
FJ.POP_DESC_CX = 540; FJ.POP_DESC_CY = 967; FJ.POP_DESC_FONT = 40
FJ.POP_DESC_R = 0xb6; FJ.POP_DESC_G = 0xb0; FJ.POP_DESC_B = 0x9d
-- 品质筛选行
FJ.POP_FILTER_CX = 540; FJ.POP_FILTER_CY = 1052; FJ.POP_FILTER_W = 800; FJ.POP_FILTER_H = 80; FJ.POP_FILTER_R = 16
FJ.POP_ARROW_SIZE = 50
FJ.POP_ARROW_LEFT_CX = 181; FJ.POP_ARROW_LEFT_CY = 1049
FJ.POP_ARROW_RIGHT_CX = 903; FJ.POP_ARROW_RIGHT_CY = 1049
FJ.POP_QUALITY_TEXT_CX = 540; FJ.POP_QUALITY_TEXT_CY = 1050; FJ.POP_QUALITY_TEXT_FONT = 40; FJ.POP_QUALITY_STROKE = 6
-- 等级筛选行
FJ.POP_LEVEL_GAP = 28
FJ.POP_LEVEL_CY = FJ.POP_FILTER_CY + FJ.POP_FILTER_H + FJ.POP_LEVEL_GAP
FJ.POP_LEVEL_ARROW_LEFT_CY = FJ.POP_ARROW_LEFT_CY + FJ.POP_FILTER_H + FJ.POP_LEVEL_GAP
FJ.POP_LEVEL_ARROW_RIGHT_CY = FJ.POP_ARROW_RIGHT_CY + FJ.POP_FILTER_H + FJ.POP_LEVEL_GAP
FJ.POP_LEVEL_TEXT_CY = FJ.POP_QUALITY_TEXT_CY + FJ.POP_FILTER_H + FJ.POP_LEVEL_GAP
FJ.POP_LEVEL_STEP = 5
-- 设置完成按钮
FJ.POP_CONFIRM_CX = 540; FJ.POP_CONFIRM_CY = 1301; FJ.POP_CONFIRM_W = 410; FJ.POP_CONFIRM_H = 100
FJ.POP_CONFIRM_TEXT_FONT = 40
FJ.POP_CONFIRM_TEXT_R = 0x6d; FJ.POP_CONFIRM_TEXT_G = 0x4c; FJ.POP_CONFIRM_TEXT_B = 0x1d

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
local imgPzsx = {}        -- 品质筛选图标 1~5
local imgPopupBg = -1     -- 弹窗背景
local imgPopupArrow = -1  -- 箭头
local imgLock = -1        -- 锁定角标 UI_ICON_SUO

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
    for i = 1, 5 do
        imgPzsx[i] = nvgCreateImage(vg, "image/UI_ICON_PZSX_" .. i .. ".png", 0)
    end
    imgPopupBg = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    imgPopupArrow = nvgCreateImage(vg, "image/UI_TY_JT.png", 0)
    imgLock = nvgCreateImage(vg, "image/UI_ICON_SUO.png", 0)
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
    drawImageCentered(vg, imgGoldQBg, FJ.REWARD_CX, FJ.REWARD_CY, FJ.REWARD_SIZE, FJ.REWARD_SIZE, 1.0)
    drawImageCentered(vg, imgEssenceIcon, FJ.REWARD_CX, FJ.REWARD_CY, FJ.REWARD_SIZE, FJ.REWARD_SIZE, 1.0)

    -- 计算选中装备的预估精粹奖励
    local previewEssence = 0
    local selCount = 0
    for idx in pairs(fjState.selectedItems) do
        local item = backpackItems[idx]
        if item then
            selCount = selCount + 1
            local q = item.quality or 1
            local lv = item.level or 1
            local qCost = QUALITY_COST[q] or QUALITY_COST[1]
            previewEssence = previewEssence + math.floor(qCost.decBase * (1 + lv * qCost.decScale))
        end
    end

    -- 显示文本
    local rewardText
    if selCount > 0 then
        rewardText = "精粹 +" .. previewEssence
    elseif fjState.lastRewardEssence then
        rewardText = "精粹 +" .. fjState.lastRewardEssence
    else
        rewardText = "分解奖励"
    end
    drawTextStroke(vg, FJ.REWARD_CX, FJ.REWARD_CY + FJ.REWARD_SIZE * 0.5 + 30, rewardText,
        36, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4)
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
                    EquipmentDetail.open(item.seq, nil, nil)
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
        drawImageCentered(vg, imgPzsx[i], cx, FJ.PZSX_CY, FJ.PZSX_SIZE, FJ.PZSX_SIZE, 1.0)
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
            local qImg = imgQualityBg[item.quality] or imgQualityBg[1]
            drawImageCentered(vg, qImg, cx, cy, FJ.GRID_CELL, FJ.GRID_CELL, 1.0)
            local eqIcon = getEquipIconCached(item.templateId)
            if eqIcon and eqIcon > 0 then
                drawImageCentered(vg, eqIcon, cx, cy, FJ.GRID_CELL - 16, FJ.GRID_CELL - 16, 1.0)
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

    -- 4. 描述文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, FJ.POP_DESC_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(FJ.POP_DESC_R, FJ.POP_DESC_G, FJ.POP_DESC_B, 255))
    nvgText(vg, FJ.POP_DESC_CX, FJ.POP_DESC_CY, "符合需求的装备会在掉落时自动分解", nil)

    -- 5. 品质筛选背景框
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        FJ.POP_FILTER_CX - FJ.POP_FILTER_W * 0.5, FJ.POP_FILTER_CY - FJ.POP_FILTER_H * 0.5,
        FJ.POP_FILTER_W, FJ.POP_FILTER_H, FJ.POP_FILTER_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))
    nvgFill(vg)

    -- 6. 品质左箭头
    local didScaleQL = BF.begin(vg, "bsd_ql", FJ.POP_ARROW_LEFT_CX, FJ.POP_ARROW_LEFT_CY, FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE)
    nvgSave(vg)
    nvgTranslate(vg, FJ.POP_ARROW_LEFT_CX, FJ.POP_ARROW_LEFT_CY)
    nvgRotate(vg, math.rad(180))
    drawImageCentered(vg, imgPopupArrow, 0, 0, FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE, 1.0)
    nvgRestore(vg)
    BF.finish(vg, didScaleQL)

    -- 7. 品质右箭头
    local didScaleQR = BF.begin(vg, "bsd_qr", FJ.POP_ARROW_RIGHT_CX, FJ.POP_ARROW_RIGHT_CY, FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE)
    drawImageCentered(vg, imgPopupArrow, FJ.POP_ARROW_RIGHT_CX, FJ.POP_ARROW_RIGHT_CY,
        FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE, 1.0)
    BF.finish(vg, didScaleQR)

    -- 8. 品质文本
    if fjState.autoQuality == 0 then
        drawTextStroke(vg, FJ.POP_QUALITY_TEXT_CX, FJ.POP_QUALITY_TEXT_CY, "无",
            FJ.POP_QUALITY_TEXT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, FJ.POP_QUALITY_STROKE)
    else
        local qCfg = QUALITY_CONFIG[fjState.autoQuality]
        local qName = qCfg.name
        local qSuffix = fjState.autoQuality == 1 and "级" or "级及以下"
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, FJ.POP_QUALITY_TEXT_FONT)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local nameW = nvgTextBounds(vg, 0, 0, qName)
        local suffixW = nvgTextBounds(vg, 0, 0, qSuffix)
        local totalW = nameW + suffixW
        local startX = FJ.POP_QUALITY_TEXT_CX - totalW * 0.5
        drawTextStroke(vg, startX + nameW * 0.5, FJ.POP_QUALITY_TEXT_CY, qName,
            FJ.POP_QUALITY_TEXT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            qCfg.r, qCfg.g, qCfg.b, FJ.POP_QUALITY_STROKE)
        drawTextStroke(vg, startX + nameW + suffixW * 0.5, FJ.POP_QUALITY_TEXT_CY, qSuffix,
            FJ.POP_QUALITY_TEXT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, FJ.POP_QUALITY_STROKE)
    end

    -- 9. 等级筛选背景框
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        FJ.POP_FILTER_CX - FJ.POP_FILTER_W * 0.5, FJ.POP_LEVEL_CY - FJ.POP_FILTER_H * 0.5,
        FJ.POP_FILTER_W, FJ.POP_FILTER_H, FJ.POP_FILTER_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))
    nvgFill(vg)

    -- 等级左箭头
    local didScaleLL = BF.begin(vg, "bsd_ll", FJ.POP_ARROW_LEFT_CX, FJ.POP_LEVEL_ARROW_LEFT_CY, FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE)
    nvgSave(vg)
    nvgTranslate(vg, FJ.POP_ARROW_LEFT_CX, FJ.POP_LEVEL_ARROW_LEFT_CY)
    nvgRotate(vg, math.rad(180))
    drawImageCentered(vg, imgPopupArrow, 0, 0, FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE, 1.0)
    nvgRestore(vg)
    BF.finish(vg, didScaleLL)

    -- 等级右箭头
    local didScaleLR = BF.begin(vg, "bsd_lr", FJ.POP_ARROW_RIGHT_CX, FJ.POP_LEVEL_ARROW_RIGHT_CY, FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE)
    drawImageCentered(vg, imgPopupArrow, FJ.POP_ARROW_RIGHT_CX, FJ.POP_LEVEL_ARROW_RIGHT_CY,
        FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE, 1.0)
    BF.finish(vg, didScaleLR)

    -- 等级文本
    local levelText = fjState.autoLevel == 0 and "无" or (tostring(fjState.autoLevel) .. "级及以下")
    drawTextStroke(vg, FJ.POP_QUALITY_TEXT_CX, FJ.POP_LEVEL_TEXT_CY, levelText,
        FJ.POP_QUALITY_TEXT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, FJ.POP_QUALITY_STROKE)

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

    -- 品质左箭头
    if hitTest(dx, dy, FJ.POP_ARROW_LEFT_CX, FJ.POP_ARROW_LEFT_CY, FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE) then
        BF.trigger("bsd_ql")
        fjState.autoQuality = math.max(0, fjState.autoQuality - 1)
        local qLabel = fjState.autoQuality == 0 and "无" or QUALITY_CONFIG[fjState.autoQuality].name
        print("[BlacksmithDecompose] 品质筛选降低: " .. qLabel)
        return true
    end
    -- 品质右箭头
    if hitTest(dx, dy, FJ.POP_ARROW_RIGHT_CX, FJ.POP_ARROW_RIGHT_CY, FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE) then
        BF.trigger("bsd_qr")
        fjState.autoQuality = math.min(5, fjState.autoQuality + 1)
        print("[BlacksmithDecompose] 品质筛选提高: " .. QUALITY_CONFIG[fjState.autoQuality].name)
        return true
    end
    -- 等级左箭头
    if hitTest(dx, dy, FJ.POP_ARROW_LEFT_CX, FJ.POP_LEVEL_ARROW_LEFT_CY, FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE) then
        BF.trigger("bsd_ll")
        fjState.autoLevel = math.max(0, fjState.autoLevel - FJ.POP_LEVEL_STEP)
        print("[BlacksmithDecompose] 等级筛选降低: " .. (fjState.autoLevel == 0 and "无" or fjState.autoLevel))
        return true
    end
    -- 等级右箭头
    if hitTest(dx, dy, FJ.POP_ARROW_RIGHT_CX, FJ.POP_LEVEL_ARROW_RIGHT_CY, FJ.POP_ARROW_SIZE, FJ.POP_ARROW_SIZE) then
        BF.trigger("bsd_lr")
        fjState.autoLevel = math.min(60, fjState.autoLevel + FJ.POP_LEVEL_STEP)
        print("[BlacksmithDecompose] 等级筛选提高: " .. fjState.autoLevel)
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
    if EquipmentDetail.isOpen() then return end
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
    if EquipmentDetail.isOpen() then return end
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
    if EquipmentDetail.isOpen() then return end
    fjState.touchStartY = nil
    -- 重置长按状态
    fjState.longPressActive = false
    fjState.longPressCellIdx = 0
end

--- 鼠标滚轮
function M.handleScroll(wheel)
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
    if #rewards > 0 then
        RewardPopup.show("分解奖励", rewards)
    end
    print("[BlacksmithDecompose] 分解完成，获得精粹: " .. tostring(essenceReward)
        .. " (含洗练返还: " .. tostring(data.refineReturn or 0) .. ")"
        .. " 金币: " .. tostring(goldReward)
        .. "，分解数量: " .. tostring(data.decomposeCount))
end

return M
