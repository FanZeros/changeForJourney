-- ============================================================================
-- CharacterPanelDraw - 角色界面绘制子模块
-- 从 CharacterPanel.lua 提取的布局常量、图片资源和 draw 函数
-- ============================================================================

local HC = require("config.HeroConfig")
local HeroAssetUtil = require("config.HeroAssetUtil")
local DrawUtil = require("core.DrawUtil")
local ExpTable = require("config.ExpTable")
local TutorialManager = require("systems.TutorialManager")

local drawImageCentered  = DrawUtil.drawImageCentered
local drawTextStroke     = DrawUtil.drawTextStroke

local M = {}

-- ======================== 设计分辨率 ========================

local GameConfig = require("config.GameConfig")
local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 面板背景
local PANEL_BG_CX   = 540
local PANEL_BG_CY   = 402
local PANEL_BG_W    = 1240
local PANEL_BG_H    = 1290

-- 卡片尺寸（与战斗场景一致）
local CARD_W        = 198
local CARD_H        = 438
local CARD_SPACING  = 7
local CARD_CY       = 544      -- 编队位置 Y 轴中心

-- 锁图标
local LOCK_ICON_W   = 64
local LOCK_ICON_H   = 64

-- 加号图标
local PLUS_ICON_W   = 64
local PLUS_ICON_H   = 64

-- 职业标签（与战斗界面一致：偏移 -215）
local TAG_SIZE        = 60
local TAG_OFFSET_Y    = -215   -- 相对卡片中心的 Y 偏移（同 BattleScene）

-- 战斗力图标+数值 Y 位置
local POWER_Y       = 680
local POWER_ICON_SIZE = 36

-- 等级徽章（以最中心卡牌为基准的相对偏移）
local LVL_BADGE_SIZE  = 56
local LVL_BADGE_DX    = 477 - 540    -- -63
local LVL_BADGE_DY    = 725 - CARD_CY -- 181

-- 经验条
local EXP_BAR_DX      = 552 - 540    -- 12（相对卡牌中心）
local EXP_BAR_DY      = 727 - CARD_CY -- 183
local EXP_BAR_BG_W    = 148
local EXP_BAR_BG_H    = 28
local EXP_BAR_PADDING = 4
local EXP_FILL_LEFT_INSET = 15  -- 填充起始右移，避开等级徽章遮挡

-- 职业图标映射（与 BattleScene 一致）
local CLASS_ICON_MAP = {
    knight   = 1,
    warrior  = 2,
    mage     = 3,
    ranger   = 4,
    assassin = 5,
    priest   = 6,
}

-- ======================== 下半部分：角色列表布局 ========================

-- 角色列表背景
local LIST_BG_CX     = 540
local LIST_BG_W      = 1080
local LIST_BG_H      = 1579
local LIST_BG_CY     = DESIGN_H - LIST_BG_H * 0.5   -- 底部对齐: 2400 - 789.5 = 1610.5

-- 队伍总战斗力
local TOTAL_POWER_CX = 540
local TOTAL_POWER_CY = 860
local TOTAL_POWER_ICON_SIZE = 36
local TOTAL_POWER_GAP = 4

-- "我的冒险家"标题
local MY_HEROES_CX   = 540
local MY_HEROES_CY   = 996

-- 角色卡片行
local ROW1_CY        = 1291    -- 第一排 Y 中心
local MAX_PER_ROW    = 5

-- 行间距
local ROW2_CY        = 1834    -- 第二排 Y 中心
local ROW_SPACING    = ROW2_CY - ROW1_CY  -- 543

-- 角色名背景（相对卡片行 Y 中心的偏移）
local NAME_BG_DY     = 1544 - ROW1_CY   -- 253
local NAME_BG_W      = 193
local NAME_BG_H      = 48
local NAME_BG_RADIUS = 24

-- 出战中标识（基于最中间卡牌 cx=540, cy=ROW1_CY=1291 的绝对坐标推算偏移）
local DEPLOYED_W     = 134
local DEPLOYED_H     = 56
local DEPLOYED_DX    = -CARD_W * 0.5 + 134 * 0.5  -- -32, 左对齐卡片
local DEPLOYED_DY    = 1145 - ROW1_CY  -- -146
local DEPLOYED_TXT_DY = 1142 - ROW1_CY -- -149

-- ======================== 滚动区域 ========================

local SCROLL_TOP     = 1050   -- 标题下方
local SCROLL_BOTTOM  = 2200   -- 底部导航栏顶边
local SCROLL_LEFT    = 0
local SCROLL_RIGHT   = DESIGN_W

-- ======================== 导出共享常量（供 CharacterPanel hit testing 使用） ========================

M.MAX_SLOTS    = 5
M.CARD_W       = CARD_W
M.CARD_H       = CARD_H
M.CARD_SPACING = CARD_SPACING
M.CARD_CY      = CARD_CY
M.MAX_PER_ROW  = MAX_PER_ROW
M.ROW1_CY      = ROW1_CY
M.ROW_SPACING  = ROW_SPACING
M.NAME_BG_DY   = NAME_BG_DY
M.NAME_BG_H    = NAME_BG_H
M.SCROLL_TOP   = SCROLL_TOP
M.SCROLL_BOTTOM = SCROLL_BOTTOM
M.SCROLL_LEFT  = SCROLL_LEFT
M.SCROLL_RIGHT = SCROLL_RIGHT
M.DESIGN_W     = DESIGN_W

-- ======================== 图片资源 ========================

local img = {
    panelBg    = -1,   -- UI_JSJM_bj.png
    listBg     = -1,   -- UI_JSJM_0.png
    deployed   = -1,   -- UI_JSJM_CZZ.png（出战中标识）
    lock       = -1,   -- UI_ICON_SUO.png
    plus       = -1,   -- UI_ICON_JIA.png
    power      = -1,   -- ICON_ZDL.png
    lvlBadge   = -1,   -- UI_JSJM_DJ.png
    expBarBg   = -1,   -- UI_JSMB_JYT1.png
    expBarFill = -1,   -- UI_JSMB_JYT2.png
    iconUp     = -1,   -- ICON_UP.png 装备可提升角标
    shardSp    = -1,   -- ICON_SP.png 碎片图标
    heroCards  = {},    -- [heroId] = nvg image handle
    classIcons = {},    -- [1~6]  = nvg image handle
}

-- ======================== setContext 注入（来自 CharacterPanel） ========================

local getTeamSlots        -- function() return teamSlots end
local getHeroRoster       -- function() return heroRoster end
local getSlotPowerCache   -- function() return slotPowerCache end
local getRosterPowerCache -- function() return rosterPowerCache end
local getDragState        -- function() return dragState end
local getSelectSlotState  -- function() return selectSlotState end
local isHeroDeployed      -- function(heroId) return bool end
local getUpgradeBadgeCache -- function() return upgradeBadgeCache end

--- 注入来自 CharacterPanel 的共享状态
function M.setContext(ctx)
    getTeamSlots         = ctx.getTeamSlots
    getHeroRoster        = ctx.getHeroRoster
    getSlotPowerCache    = ctx.getSlotPowerCache
    getRosterPowerCache  = ctx.getRosterPowerCache
    getDragState         = ctx.getDragState
    getSelectSlotState   = ctx.getSelectSlotState
    isHeroDeployed       = ctx.isHeroDeployed
    getUpgradeBadgeCache = ctx.getUpgradeBadgeCache
end

-- ======================== 图片初始化 ========================

function M.initImages(vg)
    img.panelBg    = nvgCreateImage(vg, "image/UI_JSJM_bj.png", 0)
    img.listBg     = nvgCreateImage(vg, "image/UI_JSJM_0.png", 0)
    img.deployed   = nvgCreateImage(vg, "image/UI_JSJM_CZZ.png", 0)
    img.lock       = nvgCreateImage(vg, "image/UI_ICON_SUO.png", 0)
    img.plus       = nvgCreateImage(vg, "image/UI_ICON_JIA.png", 0)
    img.power      = nvgCreateImage(vg, "image/ICON_ZDL.png", 0)
    img.lvlBadge   = nvgCreateImage(vg, "image/UI_JSJM_DJ.png", 0)
    img.expBarBg   = nvgCreateImage(vg, "image/UI_JSMB_JYT1.png", 0)
    img.expBarFill = nvgCreateImage(vg, "image/UI_JSMB_JYT2.png", 0)
    img.iconUp     = nvgCreateImage(vg, "image/ICON_UP.png", 0)
    img.shardSp    = nvgCreateImage(vg, "image/ICON_SP.png", 0)

    -- 英雄卡片背景
    HeroAssetUtil.preloadCards(vg, img.heroCards)

    -- 职业图标 (1~6)
    for i = 1, 6 do
        img.classIcons[i] = nvgCreateImage(vg, "image/ICON_ZY_" .. i .. ".png", 0)
    end
end

--- 返回共享图片句柄（供 CharacterDetail.setContext 使用）
function M.getSharedImages()
    return {
        imgHeroCards   = img.heroCards,
        imgClassIcons  = img.classIcons,
        imgPower       = img.power,
        imgLvlBadge    = img.lvlBadge,
        imgExpBarBg    = img.expBarBg,
        imgExpBarFill  = img.expBarFill,
    }
end

-- ======================== 布局计算（导出给 CharacterPanel hit testing） ========================

--- 计算5个编队槽位的 X 中心坐标（始终按5个位置布局）
function M.getSlotCX(index)
    local count = M.MAX_SLOTS
    local totalW = count * CARD_W + (count - 1) * CARD_SPACING
    local startCX = (DESIGN_W - totalW) * 0.5 + CARD_W * 0.5
    return startCX + (index - 1) * (CARD_W + CARD_SPACING)
end

--- 根据设计空间坐标找到对应的编队槽位索引
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return number|nil 槽位索引
function M.hitTestTeamSlot(dx, dy)
    for i = 1, M.MAX_SLOTS do
        local cx = M.getSlotCX(i)
        local cy = CARD_CY
        if dx >= cx - CARD_W * 0.5 and dx <= cx + CARD_W * 0.5
           and dy >= cy - CARD_H * 0.5 and dy <= cy + CARD_H * 0.5 then
            return i
        end
    end
    return nil
end

-- ======================== 绘制主函数 ========================

--- 绘制角色面板（编队槽位 + 角色列表）
--- CharacterDetail.draw() 由 CharacterPanel 在调用本函数之后单独调用
---@param vg any NanoVG 上下文
---@param scrollY number 当前滚动偏移
function M.draw(vg, scrollY)
    local teamSlots       = getTeamSlots()
    local heroRoster      = getHeroRoster()
    local slotPowerCache  = getSlotPowerCache()
    local rosterPowerCache = getRosterPowerCache()
    local dragState       = getDragState()
    local selectSlotState = getSelectSlotState()

    -- 1) 面板背景（裁剪到设计宽度内，防止两侧超出）
    nvgSave(vg)
    nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
    drawImageCentered(vg, img.panelBg, PANEL_BG_CX, PANEL_BG_CY, PANEL_BG_W, PANEL_BG_H, 1.0)
    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 2) 绘制 5 个编队槽位
    -- 拖拽中：计算鼠标悬停的目标槽位（用于高亮提示）
    local dragHoverSlot = nil
    if dragState.active and dragState.heroId then
        dragHoverSlot = M.hitTestTeamSlot(dragState.cx, dragState.cy)
    end

    for i = 1, M.MAX_SLOTS do
        local slot = teamSlots[i]
        local cx = M.getSlotCX(i)
        local cy = CARD_CY

        -- 拖拽中：源槽位显示为半透明虚位
        if dragState.active and dragState.fromSlot == i then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - CARD_W * 0.5, cy - CARD_H * 0.5, CARD_W, CARD_H, 8)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
            nvgFill(vg)
            -- 虚线边框提示
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - CARD_W * 0.5, cy - CARD_H * 0.5, CARD_W, CARD_H, 8)
            nvgStrokeColor(vg, nvgRGBA(255, 220, 80, 120))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
            -- 跳过正常绘制
            goto continueSlot
        end

        -- 拖拽悬停：目标槽位高亮边框
        if dragHoverSlot == i and dragState.active then
            local isValidTarget = (slot.state == "empty" or slot.state == "occupied")
            if isValidTarget then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - CARD_W * 0.5 - 3, cy - CARD_H * 0.5 - 3,
                    CARD_W + 6, CARD_H + 6, 10)
                nvgStrokeColor(vg, nvgRGBA(100, 255, 100, 200))
                nvgStrokeWidth(vg, 4)
                nvgStroke(vg)
            end
        end

        if slot.state == "locked" then
            -- ====== 未解锁状态 ======
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - CARD_W * 0.5, cy - CARD_H * 0.5, CARD_W, CARD_H, 8)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
            nvgFill(vg)
            drawImageCentered(vg, img.lock, cx, cy - 16, LOCK_ICON_W, LOCK_ICON_H, 1.0)
            -- 解锁条件文字
            local unlockLv = ExpTable.getSlotUnlockLevel(i)
            if unlockLv then
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 22)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
                nvgText(vg, cx, cy + LOCK_ICON_H * 0.5 - 2, "冒险等级" .. unlockLv .. "解锁", nil)
            end

        elseif slot.state == "empty" then
            -- ====== 已解锁空位 ======
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - CARD_W * 0.5, cy - CARD_H * 0.5, CARD_W, CARD_H, 8)
            if selectSlotState.active and selectSlotState.slotIndex == i then
                nvgFillColor(vg, nvgRGBA(0, 60, 0, 160))
            else
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
            end
            nvgFill(vg)

            -- 选中状态下显示"选择角色"提示文字
            if selectSlotState.active and selectSlotState.slotIndex == i then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - CARD_W * 0.5, cy - CARD_H * 0.5, CARD_W, CARD_H, 8)
                nvgStrokeColor(vg, nvgRGBA(100, 255, 100, 200))
                nvgStrokeWidth(vg, 4)
                nvgStroke(vg)
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 26)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 255))
                nvgText(vg, cx, cy + 60, "选择角色", nil)
            end

            drawImageCentered(vg, img.plus, cx, cy, PLUS_ICON_W, PLUS_ICON_H, 1.0)

        elseif slot.state == "occupied" then
            -- ====== 已有角色状态 ======
            local heroId = slot.heroId
            local heroCfg = HC.get(heroId)
            if not heroCfg then goto continue end

            -- a) 角色卡片背景
            local cardImg = img.heroCards[heroId] or img.heroCards[1]
            drawImageCentered(vg, cardImg, cx, cy, CARD_W, CARD_H, 1.0)

            -- b) 职业标志图标（偏移与战斗界面一致）
            local iconIdx = CLASS_ICON_MAP[heroCfg.classId]
            if iconIdx and img.classIcons[iconIdx] then
                drawImageCentered(vg, img.classIcons[iconIdx], cx, cy + TAG_OFFSET_Y, TAG_SIZE, TAG_SIZE, 1.0)
            end

            -- c) 战斗力图标 + 数值 (Y=680)，整体水平居中于卡片
            local power = slotPowerCache[i] or 0
            local powerStr = tostring(power)
            local POWER_GAP = 4
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 30)
            local textW = nvgTextBounds(vg, 0, 0, powerStr)
            local comboW = POWER_ICON_SIZE + POWER_GAP + textW
            local comboStartX = cx - comboW * 0.5
            local iconCX = comboStartX + POWER_ICON_SIZE * 0.5
            drawImageCentered(vg, img.power, iconCX, POWER_Y, POWER_ICON_SIZE, POWER_ICON_SIZE, 1.0)
            local textX = comboStartX + POWER_ICON_SIZE + POWER_GAP
            drawTextStroke(vg, textX, POWER_Y, powerStr,
                30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                247, 254, 119, 4)

            -- d) 经验进度条（先绘制，在等级徽章下方）
            local expBarCX = cx + EXP_BAR_DX
            local expBarCY = cy + EXP_BAR_DY
            drawImageCentered(vg, img.expBarBg, expBarCX, expBarCY, EXP_BAR_BG_W, EXP_BAR_BG_H, 1.0)
            local expProgress = (slot.maxExp > 0) and (slot.exp / slot.maxExp) or 0
            expProgress = math.max(0, math.min(1, expProgress))
            local fillW = EXP_BAR_BG_W - EXP_BAR_PADDING * 2 - EXP_FILL_LEFT_INSET
            local fillH = EXP_BAR_BG_H - EXP_BAR_PADDING * 2
            local fillX = expBarCX - EXP_BAR_BG_W * 0.5 + EXP_BAR_PADDING + EXP_FILL_LEFT_INSET
            local fillY = expBarCY - EXP_BAR_BG_H * 0.5 + EXP_BAR_PADDING
            local clipW = fillW * expProgress
            if clipW > 0 and img.expBarFill >= 0 then
                nvgSave(vg)
                nvgScissor(vg, fillX, fillY, clipW, fillH)
                local paint = nvgImagePattern(vg, fillX, fillY, fillW, fillH, 0, img.expBarFill, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, fillX, fillY, fillW, fillH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
                nvgResetScissor(vg)
                nvgRestore(vg)
            end

            -- e) 等级徽章（绘制在经验条上方层级）
            local badgeCX = cx + LVL_BADGE_DX
            local badgeCY = cy + LVL_BADGE_DY
            drawImageCentered(vg, img.lvlBadge, badgeCX, badgeCY, LVL_BADGE_SIZE, LVL_BADGE_SIZE, 1.0)
            drawTextStroke(vg, badgeCX, badgeCY,
                tostring(slot.level or 1),
                28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)

            -- f) 角色名背景 + 文字
            local nameBgCY = cy + NAME_BG_DY
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - NAME_BG_W * 0.5, nameBgCY - NAME_BG_H * 0.5,
                NAME_BG_W, NAME_BG_H, NAME_BG_RADIUS)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
            nvgFill(vg)
            drawTextStroke(vg, cx, nameBgCY, heroCfg.name,
                28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)

            -- g) 可提升角标（右上角）：从缓存查找（数据变更时已刷新）
            if img.iconUp >= 0 and getUpgradeBadgeCache()[heroId] then
                local upSize = 40
                local upX = cx + CARD_W * 0.5 - upSize * 0.5 - 2
                local upY = cy - CARD_H * 0.5 + upSize * 0.5 + 2
                drawImageCentered(vg, img.iconUp, upX, upY, upSize, upSize, 1.0)
            end

            ::continue::
        end

        -- 新手引导热点：槽位3（引导组9目标槽位）
        if i == 3 then
            if TutorialManager.isActive() then
                TutorialManager.registerHotspot("character_slot_3", cx, CARD_CY, CARD_W, CARD_H)
            end
        end

        ::continueSlot::
    end

    -- ================================================================
    -- 下半部分：角色列表
    -- ================================================================

    -- 3) 角色列表背景
    drawImageCentered(vg, img.listBg, LIST_BG_CX, LIST_BG_CY, LIST_BG_W, LIST_BG_H, 1.0)

    -- 4) 队伍总战斗力（图标+数值，水平居中）
    local totalPower = 0
    for i = 1, M.MAX_SLOTS do
        totalPower = totalPower + (slotPowerCache[i] or 0)
    end
    local totalPowerStr = tostring(totalPower)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    local tpTextW = nvgTextBounds(vg, 0, 0, totalPowerStr)
    local tpComboW = TOTAL_POWER_ICON_SIZE + TOTAL_POWER_GAP + tpTextW
    local tpStartX = TOTAL_POWER_CX - tpComboW * 0.5
    drawImageCentered(vg, img.power, tpStartX + TOTAL_POWER_ICON_SIZE * 0.5, TOTAL_POWER_CY,
        TOTAL_POWER_ICON_SIZE, TOTAL_POWER_ICON_SIZE, 1.0)
    drawTextStroke(vg, tpStartX + TOTAL_POWER_ICON_SIZE + TOTAL_POWER_GAP, TOTAL_POWER_CY,
        totalPowerStr, 30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        247, 254, 119, 4)

    -- 5) "我的冒险家"标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x7b, 0x53, 0x39, 255))
    nvgText(vg, MY_HEROES_CX, MY_HEROES_CY, "我的冒险家", nil)

    -- 6) 角色卡片行（可滚动区域，裁剪到可视范围）
    nvgSave(vg)
    nvgScissor(vg, SCROLL_LEFT, SCROLL_TOP, SCROLL_RIGHT - SCROLL_LEFT, SCROLL_BOTTOM - SCROLL_TOP)

    local rosterCount = #heroRoster
    for idx = 1, rosterCount do
        local entry = heroRoster[idx]
        local heroCfg = HC.get(entry.heroId)
        if not heroCfg then goto continueRoster end

        -- 确定行列
        local row = math.ceil(idx / MAX_PER_ROW)
        local col = idx - (row - 1) * MAX_PER_ROW    -- 1~5

        -- 当前行有多少张卡（最后一行可能不满）
        local rowStart = (row - 1) * MAX_PER_ROW + 1
        local rowEnd   = math.min(row * MAX_PER_ROW, rosterCount)
        local rowCount = rowEnd - rowStart + 1

        -- 行的 Y 中心（应用滚动偏移）
        local rowCY = ROW1_CY + (row - 1) * ROW_SPACING - scrollY

        -- 快速跳过完全不可见的行（卡片+名字的上下边界）
        local cardTop    = rowCY - CARD_H * 0.5 + TAG_OFFSET_Y
        local cardBottom = rowCY + NAME_BG_DY + NAME_BG_H * 0.5
        if cardBottom < SCROLL_TOP or cardTop > SCROLL_BOTTOM then
            goto continueRoster
        end

        -- 顶部渐变透明：卡片主体滚入裁剪上边界时逐渐变透明
        -- 使用 rowCY（卡片视觉中心）判定，当中心接近 SCROLL_TOP 时开始淡出
        local FADE_H = 150
        local fadeAlpha = 1.0
        if rowCY < SCROLL_TOP + FADE_H then
            fadeAlpha = math.max(0, (rowCY - SCROLL_TOP) / FADE_H)
        end
        nvgGlobalAlpha(vg, fadeAlpha)

        -- 水平居中分布（与编队槽位同算法，按实际卡片数居中）
        local totalW = rowCount * CARD_W + (rowCount - 1) * CARD_SPACING
        local startCX = (DESIGN_W - totalW) * 0.5 + CARD_W * 0.5
        local cx = startCX + (col - 1) * (CARD_W + CARD_SPACING)
        local cy = rowCY

        -- a) 角色卡片背景
        local cardImg = img.heroCards[entry.heroId] or img.heroCards[1]
        local isOwned = entry.owned
        drawImageCentered(vg, cardImg, cx, cy, CARD_W, CARD_H, 1.0)

        -- a2) 未拥有角色遮罩：纯黑 50% 透明度
        if not isOwned then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - CARD_W * 0.5, cy - CARD_H * 0.5, CARD_W, CARD_H, 20)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
            nvgFill(vg)
        end

        -- b) 职业标志图标
        local iconIdx = CLASS_ICON_MAP[heroCfg.classId]
        if iconIdx and img.classIcons[iconIdx] then
            drawImageCentered(vg, img.classIcons[iconIdx], cx, cy + TAG_OFFSET_Y, TAG_SIZE, TAG_SIZE, isOwned and 1.0 or 0.3)
        end

        -- c-shard) 未拥有角色：碎片进度条（复用经验条素材，ICON_SP 替代等级徽章）
        if not isOwned then
            local shards = entry.shards or 0
            if shards > 0 then
                local canSynth = shards >= HC.SHARD_SYNTHESIZE_COST
                local shardMax = HC.SHARD_SYNTHESIZE_COST  -- 10

                -- 碎片进度条（与经验条同位置/同尺寸）
                local sBarCX = cx + EXP_BAR_DX
                local sBarCY = cy + EXP_BAR_DY
                drawImageCentered(vg, img.expBarBg, sBarCX, sBarCY, EXP_BAR_BG_W, EXP_BAR_BG_H, 1.0)

                local sProgress = math.min(1, shards / shardMax)
                local sFillW = EXP_BAR_BG_W - EXP_BAR_PADDING * 2 - EXP_FILL_LEFT_INSET
                local sFillH = EXP_BAR_BG_H - EXP_BAR_PADDING * 2
                local sFillX = sBarCX - EXP_BAR_BG_W * 0.5 + EXP_BAR_PADDING + EXP_FILL_LEFT_INSET
                local sFillY = sBarCY - EXP_BAR_BG_H * 0.5 + EXP_BAR_PADDING
                local sClipW = sFillW * sProgress
                if sClipW > 0 and img.expBarFill >= 0 then
                    nvgSave(vg)
                    nvgIntersectScissor(vg, sFillX, sFillY, sClipW, sFillH)
                    local sPaint = nvgImagePattern(vg, sFillX, sFillY, sFillW, sFillH, 0, img.expBarFill, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, sFillX, sFillY, sFillW, sFillH)
                    nvgFillPaint(vg, sPaint)
                    nvgFill(vg)
                    nvgRestore(vg)
                end

                -- ICON_SP 碎片图标（替代等级徽章，同位置 50×50）
                local spCX = cx + LVL_BADGE_DX
                local spCY = cy + LVL_BADGE_DY
                drawImageCentered(vg, img.shardSp, spCX, spCY, 50, 50, 1.0)

                -- 碎片进度文字（显示在进度条上方）
                local shardLabel = shards .. "/" .. shardMax
                drawTextStroke(vg, sBarCX + 10, sBarCY, shardLabel,
                    20, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 3)

                -- 可合成文本（进度条上方）
                if canSynth then
                    local synthY = sBarCY - EXP_BAR_BG_H * 0.5 - 36
                    drawTextStroke(vg, cx, synthY, "可合成",
                        28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                        0x44, 0xff, 0x5e, 3)
                end
            end
        end

        -- c/d/e 仅已拥有角色显示战斗力、经验条、等级
        if isOwned then
            -- c) 战斗力图标+数值
            local power = rosterPowerCache[idx] or 0
            local powerStr = tostring(power)
            local POWER_GAP = 4
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 30)
            local ptW = nvgTextBounds(vg, 0, 0, powerStr)
            local pcW = POWER_ICON_SIZE + POWER_GAP + ptW
            local pcX = cx - pcW * 0.5
            drawImageCentered(vg, img.power, pcX + POWER_ICON_SIZE * 0.5,
                cy + (POWER_Y - CARD_CY), POWER_ICON_SIZE, POWER_ICON_SIZE, 1.0)
            drawTextStroke(vg, pcX + POWER_ICON_SIZE + POWER_GAP,
                cy + (POWER_Y - CARD_CY), powerStr,
                30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                247, 254, 119, 4)

            -- d) 经验条
            local expBarCX = cx + EXP_BAR_DX
            local expBarCY = cy + EXP_BAR_DY
            drawImageCentered(vg, img.expBarBg, expBarCX, expBarCY, EXP_BAR_BG_W, EXP_BAR_BG_H, 1.0)
            local expProgress = (entry.maxExp > 0) and (entry.exp / entry.maxExp) or 0
            expProgress = math.max(0, math.min(1, expProgress))
            local fillW = EXP_BAR_BG_W - EXP_BAR_PADDING * 2 - EXP_FILL_LEFT_INSET
            local fillH = EXP_BAR_BG_H - EXP_BAR_PADDING * 2
            local fillX = expBarCX - EXP_BAR_BG_W * 0.5 + EXP_BAR_PADDING + EXP_FILL_LEFT_INSET
            local fillY = expBarCY - EXP_BAR_BG_H * 0.5 + EXP_BAR_PADDING
            local clipW = fillW * expProgress
            if clipW > 0 and img.expBarFill >= 0 then
                nvgSave(vg)
                nvgIntersectScissor(vg, fillX, fillY, clipW, fillH)
                local paint = nvgImagePattern(vg, fillX, fillY, fillW, fillH, 0, img.expBarFill, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, fillX, fillY, fillW, fillH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
                nvgRestore(vg)
            end

            -- e) 等级徽章
            local badgeCX = cx + LVL_BADGE_DX
            local badgeCY = cy + LVL_BADGE_DY
            drawImageCentered(vg, img.lvlBadge, badgeCX, badgeCY, LVL_BADGE_SIZE, LVL_BADGE_SIZE, 1.0)
            drawTextStroke(vg, badgeCX, badgeCY,
                tostring(entry.level or 1),
                28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)
        end

        -- f) 角色名背景
        local nameBgCY = cy + NAME_BG_DY
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - NAME_BG_W * 0.5, nameBgCY - NAME_BG_H * 0.5,
            NAME_BG_W, NAME_BG_H, NAME_BG_RADIUS)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
        nvgFill(vg)

        -- g) 角色名文字
        drawTextStroke(vg, cx, nameBgCY, heroCfg.name,
            28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)

        -- h) 出战中标识
        if isHeroDeployed(entry.heroId) then
            drawImageCentered(vg, img.deployed, cx + DEPLOYED_DX, cy + DEPLOYED_DY, DEPLOYED_W, DEPLOYED_H, 1.0)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 28)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, cx + DEPLOYED_DX, cy + DEPLOYED_TXT_DY, "出战中", nil)
        end

        -- i) 可提升角标（右上角，所有已拥有角色）：从缓存查找
        if isOwned and img.iconUp >= 0 and getUpgradeBadgeCache()[entry.heroId] then
            local upSize = 40
            local upX = cx + CARD_W * 0.5 - upSize * 0.5 - 2
            local upY = cy - CARD_H * 0.5 + upSize * 0.5 + 2
            drawImageCentered(vg, img.iconUp, upX, upY, upSize, upSize, 1.0)
        end

        -- 新手引导热点：第一个 roster 卡片槽 / 新获得英雄卡片
        if TutorialManager.isActive() then
            if idx == 1 then
                TutorialManager.registerHotspot("character_slot_1", cx, cy, CARD_W, CARD_H)
            end
            local _newId = TutorialManager.getNewHeroId()
            if _newId and entry.heroId == _newId then
                TutorialManager.registerHotspot("character_new_hero", cx, cy, CARD_W, CARD_H)
            end
        end

        nvgGlobalAlpha(vg, 1.0)
        ::continueRoster::
    end

    nvgResetScissor(vg)
    nvgRestore(vg)



    -- 7) 拖拽中的浮动卡片（绘制在最上层）
    if dragState.active and dragState.heroId then
        local cardImg = img.heroCards[dragState.heroId] or img.heroCards[1]
        -- 半透明浮动卡片
        drawImageCentered(vg, cardImg, dragState.cx, dragState.cy, CARD_W * 1.05, CARD_H * 1.05, 0.8)
        -- 高亮边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dragState.cx - CARD_W * 0.525, dragState.cy - CARD_H * 0.525,
            CARD_W * 1.05, CARD_H * 1.05, 10)
        nvgStrokeColor(vg, nvgRGBA(255, 220, 80, 200))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end
end

return M
