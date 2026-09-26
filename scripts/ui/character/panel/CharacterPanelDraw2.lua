-- ============================================================================
-- CharacterPanelDraw - 角色界面绘制子模块
-- 从 CharacterPanel.lua 提取的布局常量、图片资源和 draw 函数
-- ============================================================================

local HC = require("config.HeroConfig")
local HeroAssetUtil = require("config.HeroAssetUtil")
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")   -- [三队并行] 页签复用按钮条背景
local ExpTable = require("config.ExpTable")
local TutorialManager = require("systems.TutorialManager")

local drawImageCentered  = DrawUtil.drawImageCentered
local drawImageCover     = DrawUtil.drawImageCover
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
local CARD_H        = 350    -- [卡高4/5] 原438
local CARD_SPACING  = 7
local CARD_CY       = 544      -- 编队位置 Y 轴中心

-- 锁图标
local LOCK_ICON_W   = 64
local LOCK_ICON_H   = 64

-- 加号图标
local PLUS_ICON_W   = 64
local PLUS_ICON_H   = 64

-- 职业标签（右下角，与等级徽章左右对应；未拥有卡同样放右下角）
local TAG_SIZE        = 60
local TAG_OFFSET_Y    = -172   -- 历史顶部偏移，保留给滚动裁剪计算
local TAG_DX          = 63     -- 与等级徽章(-63)左右镜像

-- 卡半高（卡底相对卡中心的偏移，下方元素随卡高联动，避免改 CARD_H 后错位）
local CARD_HALF_H = CARD_H * 0.5

-- 战斗力图标+数值 Y 位置（卡底上方 83，与原卡高438布局一致，随卡高联动）
local POWER_Y       = CARD_CY + CARD_HALF_H - 83
local POWER_ICON_SIZE = 36

-- 等级徽章（以最中心卡牌为基准的相对偏移，卡底上方 38）
local LVL_BADGE_SIZE  = 56
local LVL_BADGE_DX    = 477 - 540    -- -63
local LVL_BADGE_DY    = CARD_HALF_H - 38

-- 经验条（卡底上方 36，随卡高联动）
local EXP_BAR_DX      = 552 - 540    -- 12（相对卡牌中心）
local EXP_BAR_DY      = CARD_HALF_H - 36
local EXP_BAR_BG_W    = 148
local EXP_BAR_BG_H    = 28
local EXP_BAR_PADDING = 4
local EXP_FILL_LEFT_INSET = 15  -- 填充起始右移，避开等级徽章遮挡

-- 职业图标映射（与 BattleScene 一致）
local CLASS_ICON_MAP = {
    knight   = 1, seal  = 1,
    warrior  = 2, spoil = 2,
    mage     = 3, rift  = 3,
    ranger   = 4, echo  = 4,
    assassin = 5, mask  = 5,
    priest   = 6, debt  = 6,
}

-- ======================== 下半部分：角色列表布局 ========================

-- 角色列表背景
local LIST_BG_CX     = 540
local LIST_BG_W      = 1080
local LIST_BG_H      = 1579
local LIST_BG_CY     = DESIGN_H - LIST_BG_H * 0.5   -- 底部对齐: 2400 - 789.5 = 1610.5

-- 队伍总战斗力（与详情页「角色详情」同高 Y=860）
local TOTAL_POWER_CX = 540
local TOTAL_POWER_CY = 660
local TOTAL_POWER_ICON_SIZE = 36
local TOTAL_POWER_GAP = 4

-- "远征团"标题：与点进角色后的名字同位置（CharacterDetailDraw MID_NAME_CY=995）
local MY_HEROES_CX   = 540
local MY_HEROES_CY   = 680

-- 下方名册：图标网格，点图标才打开角色卡面
local ROSTER_ICON = 148
local ROSTER_GAP = 24
local ROW1_CY        = 1040
local MAX_PER_ROW    = 5

-- 行间距
local ROW_SPACING    = ROSTER_ICON + 64

-- 角色名背景（相对卡片行 Y 中心的偏移）
local NAME_BG_DY     = CARD_H * 0.5 + 34  -- [卡高4/5] 名牌中心=卡底下方34(原253)
local NAME_BG_W      = 193
local NAME_BG_H      = 48
local NAME_BG_RADIUS = 24

-- 出战中标识（基于最中间卡牌 cx=540, cy=ROW1_CY=1291 的绝对坐标推算偏移）
local DEPLOYED_W     = 134
local DEPLOYED_H     = 56
local DEPLOYED_DX    = -CARD_W * 0.5 + 134 * 0.5  -- -32, 左对齐卡片
local DEPLOYED_DY    = -CARD_H * 0.5 + 58  -- [卡高4/5] 原-146(顶下73)→顶下58
local DEPLOYED_TXT_DY = -120  -- [卡高4/5] 原-149

-- ======================== 滚动区域 ========================

local SCROLL_TOP     = 940   -- 三队头像边框下方
local SCROLL_BOTTOM  = 2400   -- 屏幕底边（与 ChurchPage 名册一致；避免底部大片留白）
local SCROLL_LEFT    = 0
local SCROLL_RIGHT   = DESIGN_W

-- ======================== 导出共享常量（供 CharacterPanel hit testing 使用） ========================

-- [三队并行] 每队最多 4 槽（左4角色 vs 右4敌人）
M.MAX_SLOTS    = 4
M.TEAM_TAB_COUNT = 3   -- 队伍页签数量（与 ExpTable.TEAM_COUNT 对应）
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
    panelBg    = -1,   -- UI_JSJM_BJ.png
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
local getHeroDeployTeams  -- [三队并行] function(heroId) return integer[] 出战队伍编号列表
local getUpgradeBadgeCache -- function() return upgradeBadgeCache end
local getActiveTeamIdx    -- [三队并行] function() return activeTeamIdx end
local getUnlockedTeamCount -- [三队并行] function() return unlockedCount end
local getTeamOccupiedCounts -- [三队并行] function() return counts[] end
local getTeams             -- function() return teams end
local getTeamPowerCaches   -- function() return teamPowerCaches end

--- 注入来自 CharacterPanel 的共享状态
function M.setContext(ctx)
    getTeamSlots         = ctx.getTeamSlots
    getHeroRoster        = ctx.getHeroRoster
    getSlotPowerCache    = ctx.getSlotPowerCache
    getRosterPowerCache  = ctx.getRosterPowerCache
    getDragState         = ctx.getDragState
    getSelectSlotState   = ctx.getSelectSlotState
    isHeroDeployed       = ctx.isHeroDeployed
    getHeroDeployTeams   = ctx.getHeroDeployTeams
    getUpgradeBadgeCache = ctx.getUpgradeBadgeCache
    getActiveTeamIdx     = ctx.getActiveTeamIdx
    getUnlockedTeamCount = ctx.getUnlockedTeamCount
    getTeamOccupiedCounts = ctx.getTeamOccupiedCounts
    getTeams             = ctx.getTeams
    getTeamPowerCaches   = ctx.getTeamPowerCaches
end

-- ======================== 图片初始化 ========================

function M.initImages(vg)
    img.vg = vg
    -- panelBg 2MB+，首次绘制再加载
    img.listBg     = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSJM_0.png", 0)
    img.deployed   = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSJM_CZZ.png", 0)
    img.lock       = nvgCreateImage(vg, "image/通用图标/UI_ICON_SUO.png", 0)
    img.plus       = nvgCreateImage(vg, "image/通用图标/UI_ICON_JIA.png", 0)
    img.power      = nvgCreateImage(vg, "image/通用图标/ICON_ZDL.png", 0)
    img.lvlBadge   = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSJM_DJ.png", 0)
    img.expBarBg   = nvgCreateImage(vg, "image/进度条/UI_JSMB_JYT1.png", 0)
    img.expBarFill = nvgCreateImage(vg, "image/进度条/UI_JSMB_JYT2.png", 0)
    img.iconUp     = nvgCreateImage(vg, "image/通用图标/ICON_UP.png", 0)
    img.shardSp    = nvgCreateImage(vg, "image/货币道具/ICON_SP.png", 0)

    -- 英雄卡片背景：按需加载，避免启动同步解码全部 KP_YX

    -- 职业图标 (1~6)
    for i = 1, 6 do
        img.classIcons[i] = nvgCreateImage(vg, "image/通用图标/ICON_ZY_" .. i .. ".png", 0)
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

--- 计算5个编队槽位的 X 中心坐标。
--- 显示与实战镜像：1 号在右（前排），序号越大越靠左。数据槽位不变。
function M.getSlotCX(index)
    local count = M.MAX_SLOTS
    local totalW = count * CARD_W + (count - 1) * CARD_SPACING
    local startCX = (DESIGN_W - totalW) * 0.5 + CARD_W * 0.5
    local visual = count - index + 1
    return startCX + (visual - 1) * (CARD_W + CARD_SPACING)
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

-- ======================== [三队并行] 队伍页签 ========================

local TAB_W, TAB_H, TAB_GAP = 132, 54, 12
local TAB_Y = 258   -- 页签顶边（槽位卡上边缘 325 之上，留 13px 间隙）

-- 右侧栏只显示图标：三队头像同时显示，点进去才打开角色卡面
local heroIconCache = {}  ---@type table<number, integer>
-- 头像放大到接近名册图标。标题独占一行，头像另起一行，避免和标题挤在一起被压扁
local AV_SIZE = 176
local AV_GAP = 16
local AV_LABEL_H = 56   -- 「小队N」标题行高
local AV_PAD_Y = 14     -- 标题行与头像之间的空隙
local AV_ROW_GAP = 28   -- 队与队之间的间距
local AV_ROW_H = AV_LABEL_H + AV_PAD_Y + AV_SIZE + AV_ROW_GAP
local AV_TOP = 28

--- 计算第 idx 个页签的左上角 X
---@param idx number
---@return number
local function teamTabX(idx)
    local totalW = M.TEAM_TAB_COUNT * TAB_W + (M.TEAM_TAB_COUNT - 1) * TAB_GAP
    return (DESIGN_W - totalW) * 0.5 + (idx - 1) * (TAB_W + TAB_GAP)
end

--- 角色头像句柄，按需加载并缓存。必须用当前帧 vg，失败不缓存，避免永久空白。
---@param vg any
---@param heroId number
---@return number
local function heroIconHandle(vg, heroId)
    local cached = heroIconCache[heroId]
    if cached and cached > 0 then return cached end
    local handle = HeroAssetUtil.ensureIcon(vg, heroIconCache, heroId)
    if not handle or handle <= 0 then
        heroIconCache[heroId] = nil
        return -1
    end
    return handle
end

--- 头像编队一行的左上角 X（4 个头像水平居中）
---@return number
local function avatarRowX()
    local rowW = M.MAX_SLOTS * AV_SIZE + (M.MAX_SLOTS - 1) * AV_GAP
    return (DESIGN_W - rowW) * 0.5
end

--- 第 teamIdx 队第 slotIdx 个头像的中心
---@param teamIdx number
---@param slotIdx number
---@return number cx, number cy
local function avatarCenter(teamIdx, slotIdx)
    local x0 = avatarRowX()
    local cx = x0 + (slotIdx - 1) * (AV_SIZE + AV_GAP) + AV_SIZE * 0.5
    -- 标题独占一行，头像在标题行下方另起一行
    local cy = AV_TOP + (teamIdx - 1) * AV_ROW_H + AV_LABEL_H + AV_PAD_Y + AV_SIZE * 0.5
    return cx, cy
end

--- 绘制单个头像槽：已上阵显示头像，空位虚框
---@param vg any
---@param slotIdx number
---@param slot table|nil
---@param locked boolean
local function drawAvatarSlot(vg, teamIdx, slotIdx, slot, locked)
    local cx, cy = avatarCenter(teamIdx, slotIdx)
    local x = cx - AV_SIZE * 0.5
    local y = cy - AV_SIZE * 0.5
    local dragState = getDragState and getDragState()
    local draggingSource = dragState and dragState.active
        and dragState.fromTeam == teamIdx and dragState.fromSlot == slotIdx
    local occupied = slot and slot.state == "occupied" and slot.heroId
    if occupied and not locked and not draggingSource then
        local icon = heroIconHandle(vg, slot.heroId)
        if icon and icon >= 0 then
            nvgSave(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x, y, AV_SIZE, AV_SIZE, 14)
            nvgFillColor(vg, nvgRGBA(20, 16, 12, 255))
            nvgFill(vg)
            nvgScissor(vg, x, y, AV_SIZE, AV_SIZE)
            drawImageCentered(vg, icon, cx, cy, AV_SIZE, AV_SIZE, 1.0)
            nvgRestore(vg)
        end
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, AV_SIZE, AV_SIZE, 14)
        nvgStrokeColor(vg, nvgRGBA(212, 175, 90, 230))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)

        -- 左下角等级徽章（与角色卡面同一套素材）
        local lvl = 1
        local okLvl, CharacterPanel = pcall(require, "ui.character.panel.CharacterPanel")
        if okLvl and CharacterPanel.getEffectiveLevel then
            lvl = CharacterPanel.getEffectiveLevel(slot.heroId) or 1
        end
        local badgeSize = 48
        local badgeCX = x + 30
        local badgeCY = y + AV_SIZE - 30
        if img.lvlBadge and img.lvlBadge >= 0 then
            drawImageCentered(vg, img.lvlBadge, badgeCX, badgeCY, badgeSize, badgeSize, 1.0)
        else
            nvgBeginPath(vg)
            nvgCircle(vg, badgeCX, badgeCY, badgeSize * 0.5)
            nvgFillColor(vg, nvgRGBA(18, 14, 10, 220))
            nvgFill(vg)
        end
        drawTextStroke(vg, badgeCX, badgeCY, tostring(lvl),
            24, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)

        -- 左上角队伍归属
        local tagCX, tagCY = x + 28, y + 26
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tagCX - 20, tagCY - 16, 40, 32, 7)
        nvgFillColor(vg, nvgRGBA(18, 14, 10, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 214, 102, 230))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 214, 102, 255))
        nvgText(vg, tagCX, tagCY, tostring(teamIdx), nil)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, AV_SIZE, AV_SIZE, 14)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, locked and 90 or 60))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(120, 100, 70, locked and 90 or 160))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, locked and 36 or 48)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 145, 120, locked and 140 or 200))
        if not draggingSource then
            if locked and img.lock and img.lock >= 0 then
                drawImageCentered(vg, img.lock, cx, cy, 52, 52, 0.85)
            else
                nvgText(vg, cx, cy, "+", nil)
            end
        end
    end
end

--- 三队头像同时显示。右侧栏不画角色整卡，点头像才进卡面。
---@param vg any
function M.drawTeamAvatars(vg)
    if not getTeams or not getUnlockedTeamCount then return end
    local teams = getTeams()
    local unlockedCnt = getUnlockedTeamCount() or 1
    local activeIdx = getActiveTeamIdx and getActiveTeamIdx() or 1
    for t = 1, M.TEAM_TAB_COUNT do
        local locked = t > unlockedCnt
        local _, rowCy = avatarCenter(t, 1)
        local rowX = avatarRowX()
        local rowW = M.MAX_SLOTS * AV_SIZE + (M.MAX_SLOTS - 1) * AV_GAP
        -- 底条包住标题行和头像行
        local frameX = rowX - 20
        local frameY = rowCy - AV_SIZE * 0.5 - AV_PAD_Y - AV_LABEL_H - 10
        local frameW = rowW + 40
        local frameH = AV_LABEL_H + AV_PAD_Y + AV_SIZE + 20
        nvgBeginPath(vg)
        nvgRoundedRect(vg, frameX, frameY, frameW, frameH, 16)
        if t == activeIdx then
            nvgFillColor(vg, nvgRGBA(48, 36, 18, 170))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(212, 175, 90, 230))
            nvgStrokeWidth(vg, 3)
        else
            nvgFillColor(vg, nvgRGBA(12, 10, 8, locked and 80 or 130))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(120, 100, 70, locked and 90 or 170))
            nvgStrokeWidth(vg, 2)
        end
        nvgStroke(vg)
        -- 「小队N」标题，左上角
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, t == activeIdx and nvgRGBA(255, 214, 102, 255)
            or (locked and nvgRGBA(150, 140, 125, 170) or nvgRGBA(244, 237, 224, 235)))
        nvgText(vg, frameX + 20, frameY + AV_LABEL_H * 0.5,
            locked and ("小队" .. t .. "  未解锁") or ("小队" .. t), nil)
        local powerCaches = getTeamPowerCaches and getTeamPowerCaches() or {}
        local teamPower = 0
        local cache = powerCaches[t]
        if cache then
            for i = 1, M.MAX_SLOTS do
                teamPower = teamPower + (cache[i] or 0)
            end
        end
        local powerStr = require("core.NumberUtil").format(teamPower)
        local labelCY = frameY + AV_LABEL_H * 0.5
        nvgFontSize(vg, 26)
        nvgFillColor(vg, locked and nvgRGBA(140, 130, 115, 160) or nvgRGBA(247, 254, 119, 255))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(vg, frameX + frameW - 16, labelCY, powerStr, nil)
        local powerTextW = nvgTextBounds(vg, 0, 0, powerStr)
        if img.power and img.power >= 0 then
            drawImageCentered(vg, img.power, frameX + frameW - 16 - powerTextW - 22, labelCY,
                30, 30, locked and 0.45 or 1)
        end
        local slots = teams[t] and teams[t].slots
        for s = 1, M.MAX_SLOTS do
            drawAvatarSlot(vg, t, s, slots and slots[s], locked)
        end
    end
end

--- 头像槽命中：返回队伍与槽位，未解锁队伍不响应
---@param dx number
---@param dy number
---@return number|nil teamIdx, number|nil slotIdx
function M.hitTestAvatarSlot(dx, dy)
    local unlockedCnt = getUnlockedTeamCount and getUnlockedTeamCount() or 1
    for t = 1, math.min(M.TEAM_TAB_COUNT, unlockedCnt) do
        for s = 1, M.MAX_SLOTS do
            local cx, cy = avatarCenter(t, s)
            if math.abs(dx - cx) <= AV_SIZE * 0.5 and math.abs(dy - cy) <= AV_SIZE * 0.5 then
                return t, s
            end
        end
    end
    return nil, nil
end

--- 绘制三队页签（队1/队2/队3，含解锁状态与上阵人数角标）
function M.drawTeamTabs(vg)
    if not getActiveTeamIdx or not getUnlockedTeamCount then return end
    local activeIdx    = getActiveTeamIdx() or 1
    local unlockedCnt  = getUnlockedTeamCount() or 1
    local counts       = getTeamOccupiedCounts and getTeamOccupiedCounts() or {}

    for i = 1, M.TEAM_TAB_COUNT do
        local x = teamTabX(i)
        local y = TAB_Y
        local isActive = (i == activeIdx)
        local isLocked = (i > unlockedCnt)

        -- 底板：复用暗黑按钮条背景（DarkIcon.drawNine "btn"，语义金描边）
        if isActive then
            DarkIcon.drawNine(vg, "btn", x, y, TAB_W, TAB_H, { accent = "gold" })
        elseif isLocked then
            DarkIcon.drawNine(vg, "btn", x, y, TAB_W, TAB_H, { alpha = 0.38 })
        else
            DarkIcon.drawNine(vg, "btn", x, y, TAB_W, TAB_H, { accent = "gold", alpha = 0.62 })
        end

        -- 文案
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local label
        if isLocked then
            label = tostring(i)
            nvgFontSize(vg, 24)
            nvgFillColor(vg, nvgRGBA(150, 150, 165, 255))
            if img.lock and img.lock >= 0 then
                drawImageCentered(vg, img.lock, x + 22, y + TAB_H * 0.5, 28, 28, 0.8)
            end
        else
            label = string.format("%d  %d/%d", i, counts[i] or 0, M.MAX_SLOTS)
            nvgFontSize(vg, 24)
            nvgFillColor(vg, isActive and nvgRGBA(255, 255, 255, 255) or nvgRGBA(205, 210, 225, 255))
        end
        nvgText(vg, x + TAB_W * 0.5, y + TAB_H * 0.5 + 1, label)
    end
end

--- 页签命中检测
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return number|nil 命中的队伍索引
function M.hitTestTeamTabs(dx, dy)
    for i = 1, M.TEAM_TAB_COUNT do
        local x = teamTabX(i)
        if dx >= x and dx <= x + TAB_W and dy >= TAB_Y and dy <= TAB_Y + TAB_H then
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
    --    [横屏三联] 共享大背景右半，与左侧城镇构成同一连续世界
    nvgSave(vg)
    nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
    ---@diagnostic disable-next-line: undefined-global
    if H_TRI_L0 then
        -- [三行并行] L0 整套大背景已铺英灵墙, 不再叠画
    else
        require("core.HorizonBg").draw(vg, 1, 1.0)
    end
    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 1.5) 三队头像同时显示。右侧栏不画整卡，点头像才进卡面。
    M.drawTeamAvatars(vg)

    -- 2) 整卡槽位已改为头像，保留块结构供下方列表复用局部变量
    if false then
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
                nvgText(vg, cx, cy + LOCK_ICON_H * 0.5 - 2, "远征等级" .. unlockLv .. "解锁", nil)
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
            local cardVg = img.vg or vg
            local cardImg = HeroAssetUtil.ensureCard(cardVg, img.heroCards, heroId)
            if (not cardImg or cardImg < 0) and heroId ~= 1 then
                cardImg = HeroAssetUtil.ensureCard(cardVg, img.heroCards, 1)
            end
            drawImageCover(vg, cardImg, cx, cy, CARD_W, CARD_H, 1.0)

            -- b) 职业标志图标（右下角，与等级徽章左右对应）
            local iconIdx = CLASS_ICON_MAP[heroCfg.classId]
            if iconIdx and img.classIcons[iconIdx] then
                drawImageCentered(vg, img.classIcons[iconIdx], cx + TAG_DX, cy + LVL_BADGE_DY, TAG_SIZE, TAG_SIZE, 1.0)
            end

            -- c) 战斗力图标 + 数值 (Y=680)，整体水平居中于卡片
            local power = slotPowerCache[i] or 0
            local powerStr = require("core.NumberUtil").format(power)
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

            -- e) 等级徽章
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
                TutorialManager.registerHotspot("character_slot_3", cx, CARD_CY, CARD_W, CARD_H, "right")
            end
        end

        ::continueSlot::
    end
    end

    -- ================================================================
    -- 下半部分：角色列表
    -- ================================================================

    -- 3) 角色框图片背景先去掉，背景稍后另定
    -- 4) 总战力已改到各队头像后方
    -- 5) 不显示“远征团”

    -- 6) 角色图标行（可滚动区域，裁剪到可视范围）
    nvgSave(vg)
    nvgScissor(vg, SCROLL_LEFT, SCROLL_TOP, SCROLL_RIGHT - SCROLL_LEFT, SCROLL_BOTTOM - SCROLL_TOP)

    local rosterCount = #heroRoster
    if rosterCount > 0 then
        local numRows = math.ceil(rosterCount / MAX_PER_ROW)
        local cols = math.min(rosterCount, MAX_PER_ROW)
        local gridW = cols * ROSTER_ICON + (cols - 1) * ROSTER_GAP
        local pad = 16
        local frameX = (DESIGN_W - gridW) * 0.5 - pad
        local firstTop = ROW1_CY - ROSTER_ICON * 0.5 - scrollY
        local lastCY = ROW1_CY + (numRows - 1) * ROW_SPACING - scrollY
        local frameY = firstTop - pad
        -- 名字在图标下方 22，再留一行字高，避免底框停在名字中间
        local frameBottom = lastCY + ROSTER_ICON * 0.5 + 48 + pad
        nvgBeginPath(vg)
        nvgRoundedRect(vg, frameX, frameY, gridW + pad * 2, frameBottom - frameY, 16)
        nvgFillColor(vg, nvgRGBA(8, 7, 6, 150))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(186, 154, 92, 180))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
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

        -- 快速跳过完全不可见的行（图标+名字）
        local cardTop    = rowCY - ROSTER_ICON * 0.5
        local cardBottom = rowCY + ROSTER_ICON * 0.5 + 36
        if cardBottom < SCROLL_TOP or cardTop > SCROLL_BOTTOM then
            goto continueRoster
        end

        local fadeAlpha = 1.0
        local distToExit = (rowCY + ROSTER_ICON * 0.5) - SCROLL_TOP
        if distToExit < ROSTER_ICON then
            fadeAlpha = math.max(0, distToExit / ROSTER_ICON)
        end
        nvgGlobalAlpha(vg, fadeAlpha)

        local totalW = rowCount * ROSTER_ICON + (rowCount - 1) * ROSTER_GAP
        local startCX = (DESIGN_W - totalW) * 0.5 + ROSTER_ICON * 0.5
        local cx = startCX + (col - 1) * (ROSTER_ICON + ROSTER_GAP)
        local cy = rowCY
        local ix = cx - ROSTER_ICON * 0.5
        local iy = cy - ROSTER_ICON * 0.5
        local isOwned = entry.owned
        local icon = heroIconHandle(vg, entry.heroId)
        if icon and icon >= 0 then
            nvgSave(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix, iy, ROSTER_ICON, ROSTER_ICON, 16)
            nvgFillColor(vg, nvgRGBA(20, 16, 12, 255))
            nvgFill(vg)
            nvgScissor(vg, ix, iy, ROSTER_ICON, ROSTER_ICON)
            drawImageCentered(vg, icon, cx, cy, ROSTER_ICON, ROSTER_ICON, isOwned and 1.0 or 0.45)
            nvgRestore(vg)
        else
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix, iy, ROSTER_ICON, ROSTER_ICON, 16)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 90))
            nvgFill(vg)
        end
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ix, iy, ROSTER_ICON, ROSTER_ICON, 16)
        nvgStrokeColor(vg, nvgRGBA(212, 175, 90, isOwned and 210 or 90))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

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

        local nameY = cy + ROSTER_ICON * 0.5 + 22
        drawTextStroke(vg, cx, nameY, heroCfg.name,
            20, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 3)
        if isOwned then
            drawTextStroke(vg, cx, iy + 18, "Lv" .. tostring(entry.level or 1),
                18, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 230, 160, 3)
        end

        -- h) 出战队伍角标：左下角深色底，显示队1/队2/队3
        local deployTeams = getHeroDeployTeams and getHeroDeployTeams(entry.heroId) or nil
        if deployTeams and #deployTeams > 0 then
            local labels = {}
            for i, t in ipairs(deployTeams) do labels[i] = "队" .. t end
            local badge = table.concat(labels, "·")
            local bx = ix + 6
            local by = iy + ROSTER_ICON - 28
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 16)
            local textW = nvgTextBounds(vg, 0, 0, badge)
            local bw = math.max(46, textW + 14)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, bw, 22, 6)
            nvgFillColor(vg, nvgRGBA(18, 14, 10, 215))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 214, 102, 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 214, 102, 255))
            nvgText(vg, bx + bw * 0.5, by + 11, badge, nil)
        end

        -- i) 可提升角标（右上角，所有已拥有角色）：从缓存查找
        if isOwned and img.iconUp >= 0 and getUpgradeBadgeCache()[entry.heroId] then
            local upSize = 32
            local upX = cx + ROSTER_ICON * 0.5 - 8
            local upY = cy - ROSTER_ICON * 0.5 + 8
            drawImageCentered(vg, img.iconUp, upX, upY, upSize, upSize, 1.0)
        end

        -- 新手引导热点：第一个 roster 卡片槽 / 新获得英雄卡片
        if TutorialManager.isActive() then
            if idx == 1 then
                TutorialManager.registerHotspot("character_slot_1", cx, cy, ROSTER_ICON, ROSTER_ICON, "right")
            end
            local _newId = TutorialManager.getNewHeroId()
            if _newId and entry.heroId == _newId then
                TutorialManager.registerHotspot("character_new_hero", cx, cy, ROSTER_ICON, ROSTER_ICON, "right")
            end
        end

        nvgGlobalAlpha(vg, 1.0)
        ::continueRoster::
    end

    nvgResetScissor(vg)
    nvgRestore(vg)



    -- 7) 拖拽中的浮动卡片（绘制在最上层）
    if dragState.active and dragState.heroId then
        local cardVg = img.vg or vg
        local icon = heroIconHandle(vg, dragState.heroId)
        if icon and icon >= 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, dragState.cx - 74, dragState.cy - 74, 148, 148, 16)
            nvgFillColor(vg, nvgRGBA(20, 16, 12, 180))
            nvgFill(vg)
            drawImageCentered(vg, icon, dragState.cx, dragState.cy, 148, 148, 0.92)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, dragState.cx - 74, dragState.cy - 74, 148, 148, 16)
            nvgStrokeColor(vg, nvgRGBA(255, 214, 102, 230))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end
        local hoverTeam, hoverSlot = M.hitTestAvatarSlot(dragState.cx, dragState.cy)
        if hoverTeam and hoverSlot then
            local hx, hy = avatarCenter(hoverTeam, hoverSlot)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, hx - AV_SIZE * 0.5 - 4, hy - AV_SIZE * 0.5 - 4, AV_SIZE + 8, AV_SIZE + 8, 16)
            nvgStrokeColor(vg, nvgRGBA(99, 255, 132, 230))
            nvgStrokeWidth(vg, 4)
            nvgStroke(vg)
        end
    end
end

return M
