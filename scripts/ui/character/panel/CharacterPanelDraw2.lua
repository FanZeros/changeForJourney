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
local HeroFrame = require("ui.widget.HeroFrame")
local Presentation = require("ui.character.panel.CharacterRosterPresentation")

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
local ROW1_CY        = 1122
local MAX_PER_ROW    = 5
local ROSTER_POWER_DY = ROSTER_ICON * 0.5 + 49
local ROSTER_BOTTOM_DY = ROSTER_ICON * 0.5 + 70

-- 名字与战力分两行，行间留下独立的阅读空间。
local ROW_SPACING    = ROSTER_ICON + 90

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

local SCROLL_TOP     = 1044   -- 缩小队三与名册的空档，五行名册首屏保留完整名字与战力。
local SCROLL_BOTTOM  = DESIGN_H - DESIGN_H * 0.06 -- 扣除内容下移量，战力行滚到底时仍在屏幕内。
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
M.ROSTER_ICON = ROSTER_ICON
M.ROSTER_BOTTOM_DY = ROSTER_BOTTOM_DY
M.CONTENT_SHIFT_X = 0 -- 取消旧右移，利用左侧留白并居中整个角色栏。
M.CONTENT_SHIFT_Y = DESIGN_H * 0.06
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
local getTeamTotalPower    -- function(teamIdx) return totalPower end
local getRosterSort = function() return "default", false end
local isHeroesDataApplied = function() return true end

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
    getTeamTotalPower    = ctx.getTeamTotalPower
    getRosterSort       = ctx.getRosterSort or function() return "default", false end
    isHeroesDataApplied = ctx.isHeroesDataApplied or function() return true end
    Presentation.reset()
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
local AV_PAD_Y = 30     -- 标题行与头像之间的空隙（留给站位名）
local AV_ROW_GAP = 28   -- 队与队之间的间距
local AV_POWER_H = 32   -- 单人战力独立放在头像下方，不盖等级与职业角标。
local AV_ROW_H = AV_LABEL_H + AV_PAD_Y + AV_SIZE + AV_POWER_H + AV_ROW_GAP
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

--- 站位名：1 号最靠右是前锋，4 号最靠左是后排
local SLOT_POS_NAME = { "前锋", "中锋", "中卫", "后卫" }

--- 队伍配色（右栏三队行/页签共用，便于分辨出战队伍）；未解锁灰
local TEAM_COLORS = {
    { 0x5a, 0xaa, 0xff },  -- 队1 蓝
    { 0x6e, 0xdc, 0x8c },  -- 队2 绿
    { 0xc0, 0x84, 0xfc },  -- 队3 紫
}
local TEAM_COLOR_GRAY = { 0x96, 0x8c, 0x7d }
local function teamColor(idx, locked)
    if locked then return TEAM_COLOR_GRAY end
    return TEAM_COLORS[idx] or TEAM_COLOR_GRAY
end

--- 第 teamIdx 队第 slotIdx 个头像的中心
--- 右侧为前锋（1 号），与战斗条带里我方从右向左排布一致
---@param teamIdx number
---@param slotIdx number
---@return number cx, number cy
local function avatarCenter(teamIdx, slotIdx)
    local x0 = avatarRowX()
    local visual = M.MAX_SLOTS - slotIdx
    local cx = x0 + visual * (AV_SIZE + AV_GAP) + AV_SIZE * 0.5
    -- 标题独占一行，头像在标题行下方另起一行
    local cy = AV_TOP + (teamIdx - 1) * AV_ROW_H + AV_LABEL_H + AV_PAD_Y + AV_SIZE * 0.5
    return cx, cy
end

M.AV_SIZE = AV_SIZE
M.avatarCenter = avatarCenter

local function drawHeroPower(vg, cx, cy, width, power, fontSize)
    local powerText = require("core.NumberUtil").format(power or 0)
    local iconSize, gap = fontSize, 4
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    local textW = nvgTextBounds(vg, 0, 0, powerText)
    local available = width - iconSize - gap - 8
    if textW > available then
        fontSize = math.max(14, math.floor(fontSize * available / textW))
        nvgFontSize(vg, fontSize)
        textW = nvgTextBounds(vg, 0, 0, powerText)
    end
    local startX = cx - (iconSize + gap + textW) * 0.5
    drawImageCentered(vg, img.power, startX + iconSize * 0.5, cy, iconSize, iconSize, 1)
    drawTextStroke(vg, startX + iconSize + gap, cy, powerText, fontSize,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 247, 254, 119, 2)
end

--- 绘制单个头像槽：已上阵显示头像，空位虚框
---@param vg any
---@param slotIdx number
---@param slot table|nil
---@param locked boolean
local function drawAvatarSlot(vg, teamIdx, slotIdx, slot, locked)
    local cx, cy = avatarCenter(teamIdx, slotIdx)
    local dragState = getDragState and getDragState()
    local draggingSource = dragState and dragState.active
        and dragState.fromTeam == teamIdx and dragState.fromSlot == slotIdx
    local occupied = slot and slot.state == "occupied" and slot.heroId
    local lvl = 1
    if occupied and not locked then
        local okLvl, CharacterPanel = pcall(require, "ui.character.panel.CharacterPanel")
        if okLvl and CharacterPanel.getEffectiveLevel then
            lvl = CharacterPanel.getEffectiveLevel(slot.heroId) or 1
        end
    end
    -- [统一角色框] HeroFrame：品质色描边 + 等级/职业角标 + 拖拽高亮 + 站位名
    HeroFrame.draw(vg, {
        cx = cx, cy = cy, size = AV_SIZE,
        heroId = occupied and slot.heroId or nil,
        iconHandle = occupied and heroIconHandle(vg, slot.heroId) or nil,
        state = locked and "locked" or (occupied and "owned" or "empty"),
        showLevel = (occupied and not draggingSource) and true or nil,
        level = lvl,
        showClass = (occupied and not draggingSource) and true or nil,
        dragSource = draggingSource and true or nil,
        posLabel = (not locked) and SLOT_POS_NAME[slotIdx] or nil,
    })
    local hovered, pressed, pulse = Presentation.getFeedback(teamIdx, slotIdx)
    if not locked and not draggingSource and (hovered or pressed or pulse > 0) then
        -- 框沿反馈不缩放头像，不移动普通点击区或教程热点。
        local tc = teamColor(teamIdx, false)
        local inset = pressed and 2 or -3
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - AV_SIZE * .5 + inset, cy - AV_SIZE * .5 + inset,
            AV_SIZE - inset * 2, AV_SIZE - inset * 2, 18)
        nvgStrokeColor(vg, nvgRGBA(tc[1], tc[2], tc[3], math.floor(100 + 130 * math.max(pulse, pressed and 1 or .4))))
        nvgStrokeWidth(vg, pressed and 4 or 2 + pulse * 2)
        nvgStroke(vg)
    end
    if occupied and not locked and not draggingSource then
        local caches = getTeamPowerCaches and getTeamPowerCaches() or {}
        local cache = caches[teamIdx]
        drawHeroPower(vg, cx, cy + AV_SIZE * 0.5 + AV_POWER_H * 0.5,
            AV_SIZE, cache and cache[slotIdx] or 0, 24)
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
        local frameH = AV_LABEL_H + AV_PAD_Y + AV_SIZE + AV_POWER_H + 20
        local tc = teamColor(t, locked)
        local slots = teams[t] and teams[t].slots
        local powerCaches = getTeamPowerCaches and getTeamPowerCaches() or {}
        local cache = powerCaches[t] or {}
        local teamPower, occupiedCount = 0, 0
        for s = 1, M.MAX_SLOTS do
            teamPower = teamPower + (cache[s] or 0)
            local slot = slots and slots[s]
            if slot and slot.state == "occupied" and slot.heroId then occupiedCount = occupiedCount + 1 end
        end
        if getTeamTotalPower then teamPower = getTeamTotalPower(t) end
        Presentation.observe(t, slots, teamPower, activeIdx, function(heroId)
            local owned = getHeroRoster and getHeroRoster() or {}
            for _, entry in ipairs(owned) do if entry.heroId == heroId then return entry.level or 1 end end
            return 1
        end, isHeroesDataApplied(), locked)
        local hovered, pressed, selectedPulse, powerPulse = Presentation.getFeedback(t)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, frameX, frameY, frameW, frameH, 16)
        nvgFillColor(vg, nvgRGBA(math.floor(tc[1] * 0.12), math.floor(tc[2] * 0.12),
            math.floor(tc[3] * 0.12), locked and 80 or 190))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(tc[1], tc[2], tc[3], locked and 75 or
            math.floor(math.min(255, (t == activeIdx and 205 or 110) + 45 * math.max(selectedPulse, powerPulse)))))
        nvgStrokeWidth(vg, t == activeIdx and 3 or 2)
        nvgStroke(vg)
        -- 左侧队色导轨/标题按压反馈，不增加独立动画实例或动头像位置。
        nvgBeginPath(vg)
        nvgRoundedRect(vg, frameX + 5, frameY + 10, 4, frameH - 20, 2)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], locked and 65 or (t == activeIdx and 235 or 120)))
        nvgFill(vg)
        if hovered or pressed then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, frameX + 15, frameY + 6, frameW - 30, 44, 8)
            nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], pressed and 48 or 22))
            nvgFill(vg)
        end
        Presentation.drawHeader(vg, t, frameX + 20, frameY + 6, tc, locked, occupiedCount, teamPower)
        if img.power and img.power > 0 then
            drawImageCentered(vg, img.power, frameX + 424, frameY + 28, 24, 24, locked and .35 or 1)
        end
        for s = 1, M.MAX_SLOTS do
            drawAvatarSlot(vg, t, s, slots and slots[s], locked)
        end
        if t == 1 and not locked and TutorialManager.getCurrentHighlight() == "character_slot_1" then
            local drag = getDragState and getDragState()
            for s = 1, M.MAX_SLOTS do
                local slot = slots and slots[s]
                local hidden = drag and drag.active and drag.fromTeam == t and drag.fromSlot == s
                if slot and slot.state == "occupied" and slot.heroId and not hidden then
                    local cx, cy = avatarCenter(t, s)
                    TutorialManager.registerCharacterDetailHotspot("character_slot_1", slot.heroId,
                        cx + M.CONTENT_SHIFT_X, cy + M.CONTENT_SHIFT_Y, AV_SIZE, AV_SIZE, "right")
                    break
                end
            end
        end
    end
    Presentation.finishObservation(activeIdx)
end

--- 头像槽命中：返回队伍与槽位，未解锁队伍不响应
---@param dx number
---@param dy number
---@return number|nil teamIdx, number|nil slotIdx
function M.hitTestAvatarSlot(dx, dy, detailOpen)
    -- 绘制与输入共用内容偏移，水平居中、保留顶部间距。
    dx = dx - M.CONTENT_SHIFT_X
    dy = dy - M.CONTENT_SHIFT_Y
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
        -- 队伍色圆点（与右栏三队行同色，便于分辨；锁定时让位给锁图标）
        if not isLocked then
            local tc = teamColor(i, false)
            nvgBeginPath(vg)
            nvgCircle(vg, x + 20, y + TAB_H * 0.5, 9)
            nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 255))
            nvgFill(vg)
        end

        -- 文案
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local label
        if isLocked then
            label = tostring(i)
            nvgFontSize(vg, 24)
            nvgFillColor(vg, nvgRGBA(0x8b, 0x95, 0xa5, 255))  -- 锁定=灰蓝色
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

M.resetPresentation = Presentation.reset

function M.hitTestRosterSort(dx, dy)
    return Presentation.hitTestSort(dx - M.CONTENT_SHIFT_X, dy - M.CONTENT_SHIFT_Y)
end

function M.setSortInteraction(dx, dy, pressed)
    Presentation.setSortInteraction(dx - M.CONTENT_SHIFT_X, dy - M.CONTENT_SHIFT_Y, pressed)
end

M.clearSortInteraction = Presentation.clearSortInteraction
M.clearTeamInteraction = Presentation.clearTeamInteraction

function M.hitTestTeamHeader(dx, dy)
    dx, dy = dx - M.CONTENT_SHIFT_X, dy - M.CONTENT_SHIFT_Y
    local unlocked = getUnlockedTeamCount and getUnlockedTeamCount() or 1
    for t = 1, math.min(M.TEAM_TAB_COUNT, unlocked) do
        local _, cy = avatarCenter(t, 1)
        local top = cy - AV_SIZE * .5 - AV_PAD_Y - AV_LABEL_H - 4
        if dx >= avatarRowX() and dx < avatarRowX() + 752 and dy >= top and dy < top + 44 then return t end
    end
    return nil
end

function M.setTeamInteraction(dx, dy, pressed)
    local team, slot = M.hitTestAvatarSlot(dx, dy, false)
    if not team then team = M.hitTestTeamHeader(dx, dy) end
    Presentation.setTeamInteraction(team, slot, pressed)
end

-- ======================== 绘制主函数 ========================

-- 原剔除条件为 cardBottom >= TOP 且 cardTop <= BOTTOM；两端各保留一行
-- 数值边界余量，最终仍使用原判断。总底框/最后行居中/拖拽浮层不依赖此范围。
---@param rosterCount integer
---@param scrollY number
---@return integer first
---@return integer last
function M.getVisibleRosterRange(rosterCount, scrollY)
    local firstRow = math.max(1, math.ceil((SCROLL_TOP - ROSTER_BOTTOM_DY + scrollY - ROW1_CY) / ROW_SPACING))
    local lastRow = math.floor((SCROLL_BOTTOM + ROSTER_ICON * 0.5 + scrollY - ROW1_CY) / ROW_SPACING) + 2
    return math.max(1, (firstRow - 1) * MAX_PER_ROW + 1), math.min(rosterCount, lastRow * MAX_PER_ROW)
end

--- 绘制角色面板；详情仍由宿主随后覆盖，浮动拖拽仍在裁剪外绘制。
---@param vg any
---@param scrollY number
---@param detailOpen boolean
function M.draw(vg, scrollY, detailOpen)
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
    -- 水平居中；下移量与输入、热点共用。
    local contentShiftX = M.CONTENT_SHIFT_X
    nvgSave(vg)
    nvgTranslate(vg, contentShiftX, M.CONTENT_SHIFT_Y)
    if detailOpen then
        M.clearSortInteraction()
        M.clearTeamInteraction()
    end
    M.drawTeamAvatars(vg)
    local sortMode, ascending = getRosterSort()
    Presentation.drawSort(vg, sortMode, ascending)

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
        -- 底框同时包住头像、名字与战力行。
        local frameBottom = lastCY + ROSTER_BOTTOM_DY + pad
        nvgBeginPath(vg)
        nvgRoundedRect(vg, frameX, frameY, gridW + pad * 2, frameBottom - frameY, 16)
        nvgFillColor(vg, nvgRGBA(8, 7, 6, 150))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(186, 154, 92, 180))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
    local firstVisible, lastVisible = M.getVisibleRosterRange(rosterCount, scrollY)
    for idx = firstVisible, lastVisible do
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
        local cardBottom = rowCY + ROSTER_BOTTOM_DY
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
        local isOwned = entry.owned
        local draggingThis = dragState and dragState.active and dragState.heroId == entry.heroId
        -- [统一角色框] 名册网格：品质描边 + 全套角标（等级/职业/队伍/碎片/可提升）+ 名字
        local deployTeams = getHeroDeployTeams and getHeroDeployTeams(entry.heroId) or nil
        local teamTags = {}
        local unlockedCnt = getUnlockedTeamCount and getUnlockedTeamCount() or 1
        if deployTeams then
            for _, t in ipairs(deployTeams) do
                if t <= unlockedCnt then
                    teamTags[#teamTags + 1] = { text = tostring(t), color = teamColor(t, false) }
                end
            end
        end
        HeroFrame.draw(vg, {
            cx = cx, cy = cy, size = ROSTER_ICON,
            heroId = entry.heroId,
            iconHandle = heroIconHandle(vg, entry.heroId),
            state = isOwned and "owned" or "unowned",
            showLevel = isOwned or nil,
            level = entry.level or 1,
            showClass = true,
            showShards = (not isOwned) or nil,
            shards = entry.shards or 0,
            showTeamTag = #teamTags > 0,
            teamTags = teamTags,
            showUpgrade = (isOwned and getUpgradeBadgeCache()[entry.heroId]) and true or nil,
            dragSource = draggingThis or nil,
            nameLabel = heroCfg.name,
        })
        if isOwned and not draggingThis then
            drawHeroPower(vg, cx, cy + ROSTER_POWER_DY, ROSTER_ICON, rosterPowerCache[idx] or 0, 24)
        end

        -- 新招募英雄仍按真实heroId注册名册；详情入口热点只由上方队伍头像提供。
        if TutorialManager.isActive() then
            local _newId = TutorialManager.getNewHeroId()
            if _newId and entry.heroId == _newId then
                TutorialManager.registerHotspot("character_new_hero", cx + contentShiftX,
                    cy + M.CONTENT_SHIFT_Y, ROSTER_ICON, ROSTER_ICON, "right")
            end
        end

        nvgGlobalAlpha(vg, 1.0)
        ::continueRoster::
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    nvgRestore(vg)  -- 结束内容下移/右移

    -- 7) 拖拽中的浮动卡片（绘制在最上层）
    if dragState.active and dragState.heroId then
        -- [统一角色框] 浮动拖拽卡：半透明头像 + 金高亮描边
        HeroFrame.draw(vg, {
            cx = dragState.cx, cy = dragState.cy, size = 148,
            heroId = dragState.heroId,
            iconHandle = heroIconHandle(vg, dragState.heroId),
            state = "owned",
            dragSource = true,
            alpha = 0.92,
        })
        local hoverTeam, hoverSlot = M.hitTestAvatarSlot(dragState.cx, dragState.cy, detailOpen)
        if hoverTeam and hoverSlot then
            local hx, hy = avatarCenter(hoverTeam, hoverSlot)
            hx = hx + M.CONTENT_SHIFT_X
            hy = hy + M.CONTENT_SHIFT_Y
            HeroFrame.draw(vg, {
                cx = hx, cy = hy, size = AV_SIZE,
                hoverTarget = true,
                frameOnly = true,
            })
        end
    end
end

return M
