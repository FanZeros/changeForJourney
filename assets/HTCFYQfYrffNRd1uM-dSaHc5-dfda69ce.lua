-- ============================================================================
-- CharacterDetailDraw - 角色详情界面绘制子模块
-- 从 CharacterDetail.lua 提取的布局常量、图片资源和 draw 函数
-- ============================================================================

local HC               = require("config.HeroConfig")
local CC               = require("config.ClassConfig")
local GameConfig        = require("config.GameConfig")
local GameState         = require("core.GameState")
local ExpTable          = require("config.ExpTable")
local EquipmentBag      = require("ui.EquipmentBag")
local PlayerStore       = require("client.data.PlayerStore")
local EquipmentConfig   = require("config.EquipmentConfig")
local DetailAttrs       = require("ui.CharacterDetailAttrs")
local DrawUtil          = require("core.DrawUtil")
local AwakeningPanel    = require("ui.AwakeningPanel")
local ClientDispatcher  = require("network.ClientDispatcher")
local EquipmentSystem   = require("systems.EquipmentSystem")
local BF                 = require("systems.ButtonFeedback")

local drawTextStroke = DrawUtil.drawTextStroke

local M = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 详情界面布局常量 ========================

-- 背景图
local DT_BG_CX, DT_BG_CY  = 540, 477
local DT_BG_W,  DT_BG_H   = 1240, 1290

-- 角色卡片中心
local DT_CARD_CX, DT_CARD_CY = 540, 497

-- 资源栏（金币/钻石）
local DT_GOLD_ICON_CX  = 137
local DT_GEM_ICON_CX   = 367
local DT_RES_Y          = 100
local DT_RES_BG_W       = 170
local DT_RES_BG_H       = 47
local DT_RES_BG_R       = 18
local DT_GOLD_ICON_SIZE = 73
local DT_GEM_ICON_SIZE  = 76
local DT_GOLD_BG_CX     = 137 + 79
local DT_GEM_BG_CX      = 367 + 81

-- 装备槽位
local DT_SLOT_SIZE = 160
M.DT_SLOT_SIZE = DT_SLOT_SIZE  -- handleInput 需要
local DT_SLOTS = {
    { name = "主武器",   cx = 259, cy = 592, img = "weapon",    slot = "weapon" },
    { name = "副武器",   cx = 810, cy = 592, img = "offhand",   slot = "offhand" },
    { name = "护甲",     cx = 259, cy = 382, img = "armor",     slot = "armor" },
    { name = "饰品",     cx = 810, cy = 382, img = "accessory", slot = "accessory" },
}
M.DT_SLOTS = DT_SLOTS  -- handleInput 需要

-- ======================== 中间部分布局常量 ========================

local MID_BG_W, MID_BG_H = 1080, 1579
local MID_BG_CX = 540
local MID_BG_CY = DESIGN_H - MID_BG_H * 0.5

local MID_TITLE_CX, MID_TITLE_CY = 540, 860
local MID_NAME_CX, MID_NAME_CY = 540, 995

local MID_EXP_CX, MID_EXP_CY = 536, 1083
local MID_EXP_W, MID_EXP_H   = 910, 54
local MID_EXP_PADDING         = 5

local MID_QUALITY_BOX_CX, MID_QUALITY_BOX_CY = 310, 1175
local MID_QUALITY_BOX_W, MID_QUALITY_BOX_H   = 440, 60
local MID_QUALITY_LABEL_X  = 121
local MID_QUALITY_LABEL_Y  = 1175
local MID_QUALITY_ICON_RIGHT_X = 509

local MID_CLASS_BOX_CX, MID_CLASS_BOX_CY = 770, 1175
local MID_CLASS_BOX_W, MID_CLASS_BOX_H   = 440, 60
local MID_CLASS_LABEL_X  = 580
local MID_CLASS_LABEL_Y  = 1175
local MID_CLASS_COMBO_RIGHT_X = 967
local MID_CLASS_ICON_SIZE     = 64

local MID_DIV1_CX, MID_DIV1_CY = 540, 1238
local MID_DIV1_W, MID_DIV1_H   = 1010, 37

-- ======================== 属性区域布局常量 ========================

local ATTR_BOX_W, ATTR_BOX_H = 440, 60
local ATTR_BOX_RADIUS        = 20

local ATTR_COL1_CX = 310
local ATTR_COL2_CX = 770
local ATTR_ROW_GAP = 9
local ATTR_FIRST_ROW_Y = 1294

local ATTR_DECO_X    = 137
local ATTR_DECO_SIZE = 20
local ATTR_DECO_DX   = ATTR_COL2_CX - ATTR_COL1_CX  -- 460

local ATTR_NAME_LEFT_X = 167
local ATTR_VAL_RIGHT_X = 510

local ATTR_FONT_SIZE     = 35
local ATTR_FONT_SIZE_MIN = 22
local ATTR_NAME_VAL_GAP  = 15

local ATTR_VISIBLE_ROWS = 4
local ATTR_SCROLL_FRICTION = 0.90
local ATTR_SCROLL_MIN_VEL  = 0.3
local ATTR_SCROLL_WHEEL_STEP = 60
local ATTR_CLIP_TOP    = ATTR_FIRST_ROW_Y - ATTR_BOX_H * 0.5
local ATTR_CLIP_HEIGHT = ATTR_VISIBLE_ROWS * ATTR_BOX_H + (ATTR_VISIBLE_ROWS - 1) * ATTR_ROW_GAP

-- 导出给 handleInput 使用
M.ATTR_BOX_W        = ATTR_BOX_W
M.ATTR_BOX_H        = ATTR_BOX_H
M.ATTR_COL1_CX      = ATTR_COL1_CX
M.ATTR_COL2_CX      = ATTR_COL2_CX
M.ATTR_ROW_GAP      = ATTR_ROW_GAP
M.ATTR_FIRST_ROW_Y  = ATTR_FIRST_ROW_Y
M.ATTR_CLIP_TOP     = ATTR_CLIP_TOP
M.ATTR_CLIP_HEIGHT  = ATTR_CLIP_HEIGHT
M.ATTR_SCROLL_WHEEL_STEP = ATTR_SCROLL_WHEEL_STEP

local MID_DIV2_CX, MID_DIV2_CY = 540, 1565
local MID_DIV2_W, MID_DIV2_H   = 1010, 37

-- ======================== 六围区域布局常量 ========================

local STAT_BOX_W, STAT_BOX_H = 437, 95
local STAT_BOX_RADIUS        = 20
local STAT_COL1_CX           = 308.5
local STAT_ROW1_CY           = 1641
local STAT_COL_GAP           = 26
local STAT_ROW_GAP_STAT      = 16
local STAT_COL2_CX           = STAT_COL1_CX + STAT_BOX_W + STAT_COL_GAP
local STAT_ROW_STEP          = STAT_BOX_H + STAT_ROW_GAP_STAT

local STAT_ICON_BG_DX   = 132 - 301
local STAT_ICON_BG_DY   = 0
local STAT_ICON_BG_SIZE = 69
local STAT_ICON_BG_R    = 14

local STAT_ICON_DX   = 132 - 301
local STAT_ICON_DY   = 1
local STAT_ICON_SIZE = 60

local STAT_NAME_DX = 190 - 301
local STAT_NAME_DY = 1623 - 1641

local STAT_VAL_DY = 1663 - 1641

local STAT_LAYOUT = DetailAttrs.STAT_LAYOUT

-- 导出给 handleInput 使用
M.STAT_BOX_W    = STAT_BOX_W
M.STAT_BOX_H    = STAT_BOX_H
M.STAT_COL1_CX  = STAT_COL1_CX
M.STAT_COL2_CX  = STAT_COL2_CX
M.STAT_ROW1_CY  = STAT_ROW1_CY
M.STAT_ROW_STEP = STAT_ROW_STEP
M.STAT_LAYOUT   = STAT_LAYOUT

-- ======================== 天赋技能区域布局常量 ========================

local TALENT_BG_CX, TALENT_BG_CY = 540, 2057
local TALENT_BG_W, TALENT_BG_H   = 903, 250
local TALENT_BG_RADIUS            = 20

local TALENT_NAME_X, TALENT_NAME_Y = 121.5, 1976
local TALENT_TEXT_LEFT   = TALENT_BG_CX - TALENT_BG_W * 0.5 + 33
local TALENT_TEXT_TOP    = TALENT_BG_CY - TALENT_BG_H * 0.5 + 81
local TALENT_TEXT_RIGHT  = TALENT_BG_CX + TALENT_BG_W * 0.5 - 33
local TALENT_TEXT_WIDTH  = TALENT_TEXT_RIGHT - TALENT_TEXT_LEFT

-- ======================== 一键卸下/一键装备按钮布局常量 ========================

local BTN_UNEQUIP_CX, BTN_UNEQUIP_CY = 211, 763
local BTN_EQUIP_CX,   BTN_EQUIP_CY   = 869, 763
local BTN_BATCH_W,     BTN_BATCH_H    = 304, 100

-- 九宫格参数（左右60，上下15）打包为 table，节省 local 变量槽位
local NP = { hongT=15, hongR=60, hongB=15, hongL=60, lvT=15, lvR=60, lvB=15, lvL=60 }

-- 导出给 handleInput 使用
M.BTN_UNEQUIP_CX = BTN_UNEQUIP_CX
M.BTN_UNEQUIP_CY = BTN_UNEQUIP_CY
M.BTN_EQUIP_CX   = BTN_EQUIP_CX
M.BTN_EQUIP_CY   = BTN_EQUIP_CY
M.BTN_BATCH_W    = BTN_BATCH_W
M.BTN_BATCH_H    = BTN_BATCH_H

-- ======================== 底部按钮布局常量 ========================

local BTN_BACK_CX, BTN_BACK_CY = 122, 2308
local BTN_BACK_W, BTN_BACK_H   = 184, 143

local BTN_TAB_BG_CX, BTN_TAB_BG_CY = 639, 2308
local BTN_TAB_BG_W, BTN_TAB_BG_H   = 810, 143

-- 3-Tab 布局（参考铁匠铺 SLIDER_W=277）
local BTN_TAB_SLIDER_W, BTN_TAB_SLIDER_H = 277, 143
local BTN_TAB_ATTR_CX, BTN_TAB_ATTR_CY     = 372, 2308
local BTN_TAB_EQUIP_CX, BTN_TAB_EQUIP_CY   = 638, 2308
local BTN_TAB_AWAKEN_CX, BTN_TAB_AWAKEN_CY = 905, 2308

local TEXT_ATTR_CX, TEXT_ATTR_CY     = 372, 2302
local TEXT_EQUIP_CX, TEXT_EQUIP_CY   = 638, 2302
local TEXT_AWAKEN_CX, TEXT_AWAKEN_CY = 905, 2302

-- 导出给 handleInput 使用
M.BTN_BACK_CX  = BTN_BACK_CX
M.BTN_BACK_CY  = BTN_BACK_CY
M.BTN_BACK_W   = BTN_BACK_W
M.BTN_BACK_H   = BTN_BACK_H
M.BTN_TAB_SLIDER_W = BTN_TAB_SLIDER_W
M.BTN_TAB_SLIDER_H = BTN_TAB_SLIDER_H
M.BTN_TAB_ATTR_CX  = BTN_TAB_ATTR_CX
M.BTN_TAB_ATTR_CY  = BTN_TAB_ATTR_CY
M.BTN_TAB_EQUIP_CX = BTN_TAB_EQUIP_CX
M.BTN_TAB_EQUIP_CY = BTN_TAB_EQUIP_CY
M.BTN_TAB_AWAKEN_CX = BTN_TAB_AWAKEN_CX
M.BTN_TAB_AWAKEN_CY = BTN_TAB_AWAKEN_CY

-- 左右切换箭头按钮布局（直接挂 M，避免局部变量超限）
M.ARROW_BG_W      = 158
M.ARROW_BG_H      = 226
M.ARROW_ICON_W    = 54
M.ARROW_ICON_H    = 82
M.ARROW_CY        = 491
-- 背景中心：左右边缘对齐屏幕边缘
M.ARROW_BG_LEFT_CX  = 158 * 0.5              -- 79: 背景左边缘对齐屏幕左侧
M.ARROW_BG_RIGHT_CX = DESIGN_W - 158 * 0.5   -- 1001: 背景右边缘对齐屏幕右侧
-- 图标中心（保持原位不变）
M.ARROW_LEFT_CX   = 158 * 0.5 - 30           -- 49: 左箭头图标中心
M.ARROW_RIGHT_CX  = DESIGN_W - 158 * 0.5 + 30 -- 1031: 右箭头图标中心
M.ARROW_ICON_INSET = 20                      -- 箭头图标向内偏移量（px）
-- 水平切换动画（参考建筑界面分页滑动风格）
M.SWITCH_ANIM_DURATION = 0.35               -- 切换动画时长（与建筑界面一致）
M.SWITCH_SLIDE_DIST    = 180                 -- 水平滑动距离（适中，不会太僵硬）

-- 卡片渲染常量（打包为 table，节省 local 变量槽位）
local CARD = {
    W=198, H=438, CY=544,
    TAG_SIZE=60, TAG_OFFSET_Y=-215,
    POWER_Y=680, POWER_ICON_SIZE=36,
    LVL_BADGE_SIZE=56, LVL_BADGE_DX=477-540, LVL_BADGE_DY=725-544,
    EXP_BAR_DX=552-540, EXP_BAR_DY=727-544,
    EXP_BAR_BG_W=148, EXP_BAR_BG_H=28, EXP_BAR_PADDING=4,
    NAME_BG_DY=253, NAME_BG_W=193, NAME_BG_H=48, NAME_BG_RADIUS=24,
}

-- 职业图标映射
local CLASS_ICON_MAP = {
    knight   = 1,
    warrior  = 2,
    mage     = 3,
    ranger   = 4,
    assassin = 5,
    priest   = 6,
}

-- ======================== 动画常量 ========================

local ANIM_DURATION       = 0.45
local CLOSE_ANIM_DURATION = 0.38
local UPPER_SLIDE_DIST = 1200
local LOWER_SLIDE_DIST = 1600
local TAB_ANIM_DURATION = 0.2

--- ease-out cubic 缓动
local function easeOutCubic(t)
    t = t - 1
    return t * t * t + 1
end

--- ease-out back 缓动（带回弹）
local function easeOutBack(t)
    local s = 1.70158
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end

--- ease-in cubic 缓动（加速离开）
local function easeInCubic(t)
    return t * t * t
end

--- ease-in-out cubic 缓动（平滑加减速，参考建筑界面分页切换）
local function easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t
    else local f = 2 * t - 2; return 0.5 * f * f * f + 1 end
end

-- ======================== 工具函数 ========================

--- 居中绘制图片
local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 or alpha <= 0.01 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

-- ======================== 图片句柄 ========================

local img = {
    detailBg      = -1,
    slotWeapon    = -1,
    slotOffhand   = -1,
    slotArmor     = -1,
    slotAccessory = -1,
    detailGold    = -1,
    detailDiamond = -1,
    midBg         = -1,
    midExpBg      = -1,
    midExpFill    = -1,
    midDiv1       = -1,
    attrDeco      = -1,
    midDiv2       = -1,
    btnBack       = -1,
    tabBg         = -1,
    tabSlider     = -1,
    btnHong       = -1,
    btnLv         = -1,
    arrowBg       = -1,   -- 切换箭头背景 UI_YWJM_HS
    arrowIcon     = -1,   -- 切换箭头图标 UI_YWJM_XYG2（默认向右）
}

local imgQualityBadges = {}
local imgStatIcons     = {}

-- 来自 CharacterPanel 的共享图片（通过 setContext 注入）
local imgHeroCards   = {}
local imgClassIcons  = {}
local imgPower       = -1
local imgLvlBadge    = -1
local imgExpBarBg    = -1
local imgExpBarFill  = -1

-- ======================== 注入依赖 ========================

-- 通过 setContext 注入的引用
---@type table
local detailState       = nil   -- 详情状态表（引用，draw 可直接修改）
local getOwnedData      = nil   -- function(heroId) → ownData or nil
local calcHeroPowerFn   = nil   -- function(heroId) → number
local CharacterDetailRef = nil  -- CharacterDetail 模块引用（访问 _hasUpgradeForSlot 等）
local collectAttributes = nil   -- DetailAttrs.collectAttributes
local clampAttrScroll   = nil   -- 限制属性滚动

-- ======================== 性能缓存（避免每帧重计算） ========================
-- calcHeroPower 缓存：仅当 heroId/level 变化或数据脏时重算
local _powerCache = { heroId = nil, level = nil, value = 0, dirty = true }
-- _hasUpgradeForSlot 缓存：仅当 heroId 变化或装备数据脏时重算
local _upgradeCache = { heroId = nil, results = {}, dirty = true }  -- results[slotName] = bool

--- 标记战斗力缓存为脏（外部数据变化时调用）
function M.markPowerDirty()
    _powerCache.dirty = true
    _upgradeCache.dirty = true
end

--- 获取缓存的战斗力（仅在 heroId/level 变化或脏标记时重算）
local function getCachedPower(heroId, level)
    if _powerCache.heroId == heroId and _powerCache.level == level and not _powerCache.dirty then
        return _powerCache.value
    end
    local power = calcHeroPowerFn and calcHeroPowerFn(heroId) or 0
    _powerCache.heroId = heroId
    _powerCache.level = level
    _powerCache.value = power
    _powerCache.dirty = false
    return power
end

--- 获取缓存的可提升判断（仅在 heroId 变化或脏标记时重算）
local function getCachedUpgrade(heroId, slotName, equipData)
    if _upgradeCache.heroId == heroId and not _upgradeCache.dirty then
        return _upgradeCache.results[slotName]
    end
    -- 脏了或 heroId 变了，全部重算4个槽位（一次性算完）
    _upgradeCache.heroId = heroId
    _upgradeCache.results = {}
    local SLOTS = { "weapon", "offhand", "armor", "accessory" }
    for _, s in ipairs(SLOTS) do
        _upgradeCache.results[s] = CharacterDetailRef._hasUpgradeForSlot(heroId, s, equipData)
    end
    _upgradeCache.dirty = false
    return _upgradeCache.results[slotName]
end

--- 注入依赖
---@param ctx table
function M.setContext(ctx)
    detailState       = ctx.detailState
    getOwnedData      = ctx.getOwnedData
    calcHeroPowerFn     = ctx.calcHeroPower
    CharacterDetailRef = ctx.CharacterDetail
    collectAttributes = ctx.collectAttributes
    clampAttrScroll   = ctx.clampAttrScroll
    -- 共享图片
    imgHeroCards   = ctx.imgHeroCards   or {}
    imgClassIcons  = ctx.imgClassIcons  or {}
    imgPower       = ctx.imgPower       or -1
    imgLvlBadge    = ctx.imgLvlBadge    or -1
    imgExpBarBg    = ctx.imgExpBarBg     or -1
    imgExpBarFill  = ctx.imgExpBarFill   or -1
end

--- 初始化图片（在 CharacterDetail.init 中调用）
function M.initImages(vg)
    img.detailBg      = nvgCreateImage(vg, "image/UI_JSXQ_bj.png", 0)
    img.slotWeapon    = nvgCreateImage(vg, "image/UI_JSXQ_KGZ_WQ.png", 0)
    img.slotOffhand   = nvgCreateImage(vg, "image/UI_JSXQ_KGZ_FS.png", 0)
    img.slotArmor     = nvgCreateImage(vg, "image/UI_JSXQ_KGZ_HJ.png", 0)
    img.slotAccessory = nvgCreateImage(vg, "image/UI_JSXQ_KGZ_SS.png", 0)
    img.detailGold    = nvgCreateImage(vg, "image/UI_icon_JB_X.png", 0)
    img.detailDiamond = nvgCreateImage(vg, "image/UI_icon_SJ_X.png", 0)

    img.midBg      = nvgCreateImage(vg, "image/UI_JSJM_0.png", 0)
    img.midExpBg   = nvgCreateImage(vg, "image/UI_JSXQ_JYT1.png", 0)
    img.midExpFill = nvgCreateImage(vg, "image/UI_JSXQ_JYT2.png", 0)
    img.midDiv1    = nvgCreateImage(vg, "image/UI_JSXQ_FGXj.png", 0)

    imgQualityBadges["R"]   = nvgCreateImage(vg, "image/UI_PZBZ_R.png", 0)
    imgQualityBadges["SR"]  = nvgCreateImage(vg, "image/UI_PZBZ_SR.png", 0)
    imgQualityBadges["SSR"] = nvgCreateImage(vg, "image/UI_PZBZ_SSR.png", 0)
    imgQualityBadges["UR"]  = nvgCreateImage(vg, "image/UI_PZBZ_UR.png", 0)

    img.attrDeco = nvgCreateImage(vg, "image/ICON_XX.png", 0)
    img.midDiv2  = nvgCreateImage(vg, "image/UI_JSXQ_FGXj.png", 0)

    for _, st in ipairs(STAT_LAYOUT) do
        imgStatIcons[st.icon] = nvgCreateImage(vg, "image/" .. st.icon .. ".png", 0)
    end

    img.btnHong   = nvgCreateImage(vg, "image/UI_AN_HONG.png", 0)
    img.btnLv     = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    img.btnBack   = nvgCreateImage(vg, "image/UI_AN_FH.png", 0)
    img.tabBg     = nvgCreateImage(vg, "image/UI_AN_1.png", 0)
    img.tabSlider = nvgCreateImage(vg, "image/UI_AN_2.png", 0)

    img.arrowBg   = nvgCreateImage(vg, "image/UI_YWJM_HS.png", 0)
    img.arrowIcon = nvgCreateImage(vg, "image/UI_YWJM_XYG2.png", 0)
    img.slotSelected = nvgCreateImage(vg, "image/UI_TJPXZTBBJ.png", 0)
end

--- 返回 imgIconUp（由 CharacterDetail 管理，此处仅提供给外部使用的便捷接口）
function M.getImgIconUp()
    return CharacterDetailRef and CharacterDetailRef._imgIconUp or -1
end

-- ======================== 绘制主函数 ========================

--- 绘制角色详情二级界面
function M.draw(vg)
    if not detailState.open then return end

    local heroId = detailState.heroId
    local heroCfg = HC.get(heroId)
    if not heroCfg then return end

    -- 从 ownedSet 取等级信息
    local ownData = getOwnedData and getOwnedData(heroId) or nil
    local heroLevel = ownData and ownData.level or 1
    local exp     = ownData and ownData.exp    or 0
    local maxExp  = ownData and ownData.maxExp or ExpTable.getHeroExpForLevel(heroLevel) or 5

    -- === 弹出/关闭动画计算 ===
    local rawT, progress, lowerProgress

    if detailState.closing then
        local elapsed = time.elapsedTime - detailState.closeTime
        rawT = math.min(1.0, elapsed / CLOSE_ANIM_DURATION)
        progress      = 1 - easeInCubic(rawT)
        lowerProgress = progress
        if rawT >= 1.0 then
            detailState.open = false
            detailState.closing = false
            detailState.heroId = nil
            return
        end
    elseif detailState.switchDir then
        -- 箭头切换：水平滑入 + 透明度淡入（参考建筑界面分页滑动）
        local elapsed = time.elapsedTime - detailState.openTime
        rawT = math.min(1.0, elapsed / M.SWITCH_ANIM_DURATION)
        progress      = easeInOutCubic(rawT)  -- 平滑加减速，不会太僵硬
        lowerProgress = 1.0  -- 下半部分不做垂直滑入
        if rawT >= 1.0 then
            detailState.switchDir = nil  -- 动画结束，清除标记
            -- 修正抖动：确保下一帧进入 else 分支时 elapsed/ANIM_DURATION >= 1.0
            detailState.openTime = time.elapsedTime - ANIM_DURATION
        end
    else
        local elapsed = time.elapsedTime - detailState.openTime
        rawT = math.min(1.0, elapsed / ANIM_DURATION)
        progress      = easeOutCubic(rawT)
        lowerProgress = easeOutCubic(rawT)
    end

    -- 水平偏移 + 透明度淡入（仅箭头切换时生效）
    local switchOX = 0
    local switchAlpha = 1.0
    if detailState.switchDir then
        -- switchDir: -1=向左切(新角色从右侧滑入), 1=向右切(新角色从左侧滑入)
        switchOX = detailState.switchDir * M.SWITCH_SLIDE_DIST * (1 - progress)
        -- 透明度：从 0.2 淡入到 1.0（前半段快速淡入，避免闪烁感）
        switchAlpha = 0.2 + 0.8 * math.min(1.0, progress * 1.8)
    end

    local upperOY = -UPPER_SLIDE_DIST * (1 - progress)
    local lowerOY =  LOWER_SLIDE_DIST * (1 - lowerProgress)
    local overlayAlpha = math.floor(180 * progress)

    -- 箭头切换时不做垂直滑入
    if detailState.switchDir then
        upperOY = 0
        lowerOY = 0
    end

    -- === 属性区域惯性滚动更新 ===
    if not detailState.attrDragging and math.abs(detailState.attrScrollVel) > ATTR_SCROLL_MIN_VEL then
        detailState.attrScrollY = detailState.attrScrollY + detailState.attrScrollVel
        detailState.attrScrollVel = detailState.attrScrollVel * ATTR_SCROLL_FRICTION
        clampAttrScroll()
    elseif not detailState.attrDragging then
        detailState.attrScrollVel = 0
    end

    -- === 全屏半透明黑色遮罩（渐入） ===
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)

    -- ================== 上半部分（从上方滑入） ==================
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)

    -- === 1) 背景图 ===
    nvgSave(vg)
    nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
    drawImageCentered(vg, img.detailBg, DT_BG_CX, DT_BG_CY, DT_BG_W, DT_BG_H, 1.0)
    nvgResetScissor(vg)
    nvgRestore(vg)

    -- === 2) 金币资源栏 ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg, DT_GOLD_BG_CX - DT_RES_BG_W * 0.5, DT_RES_Y - DT_RES_BG_H * 0.5,
        DT_RES_BG_W, DT_RES_BG_H, DT_RES_BG_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
    nvgFill(vg)
    drawImageCentered(vg, img.detailGold, DT_GOLD_ICON_CX, DT_RES_Y,
        DT_GOLD_ICON_SIZE, DT_GOLD_ICON_SIZE, 1.0)
    local goldTextX = DT_GOLD_BG_CX - DT_RES_BG_W * 0.5 + 44
    drawTextStroke(vg, goldTextX, DT_RES_Y, require("core.NumberUtil").format(GameState.getGold()),
        33, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)

    -- === 3) 钻石资源栏 ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg, DT_GEM_BG_CX - DT_RES_BG_W * 0.5, DT_RES_Y - DT_RES_BG_H * 0.5,
        DT_RES_BG_W, DT_RES_BG_H, DT_RES_BG_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
    nvgFill(vg)
    drawImageCentered(vg, img.detailDiamond, DT_GEM_ICON_CX, DT_RES_Y,
        DT_GEM_ICON_SIZE, DT_GEM_ICON_SIZE, 1.0)
    local gemTextX = DT_GEM_BG_CX - DT_RES_BG_W * 0.5 + 44
    drawTextStroke(vg, gemTextX, DT_RES_Y, require("core.NumberUtil").format(GameState.getGems()),
        33, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)

    -- === 动态内容开始（箭头切换时水平滑入+淡入） ===
    nvgSave(vg)
    nvgTranslate(vg, switchOX, 0)
    nvgGlobalAlpha(vg, switchAlpha)

    -- === 4) 角色卡片 ===
    local cx, cy = DT_CARD_CX, DT_CARD_CY
    local cardImg = imgHeroCards[heroId] or imgHeroCards[1]
    drawImageCentered(vg, cardImg, cx, cy, CARD.W, CARD.H, 1.0)

    -- 职业标志图标
    local iconIdx = CLASS_ICON_MAP[heroCfg.classId]
    if iconIdx and imgClassIcons[iconIdx] then
        drawImageCentered(vg, imgClassIcons[iconIdx], cx, cy + CARD.TAG_OFFSET_Y, CARD.TAG_SIZE, CARD.TAG_SIZE, 1.0)
    end

    -- 战斗力图标+数值（使用缓存，避免每帧重算）
    local power = getCachedPower(heroId, heroLevel)
    local powerStr = tostring(power)
    local POWER_GAP = 4
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    local ptW = nvgTextBounds(vg, 0, 0, powerStr)
    local pcW = CARD.POWER_ICON_SIZE + POWER_GAP + ptW
    local pcX = cx - pcW * 0.5
    drawImageCentered(vg, imgPower, pcX + CARD.POWER_ICON_SIZE * 0.5,
        cy + (CARD.POWER_Y - CARD.CY), CARD.POWER_ICON_SIZE, CARD.POWER_ICON_SIZE, 1.0)
    drawTextStroke(vg, pcX + CARD.POWER_ICON_SIZE + POWER_GAP,
        cy + (CARD.POWER_Y - CARD.CY), powerStr,
        30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        247, 254, 119, 4)

    -- 经验条 / 等级徽章 / 角色名
    do
        local expBarCX = cx + CARD.EXP_BAR_DX
        local expBarCY = cy + CARD.EXP_BAR_DY
        drawImageCentered(vg, imgExpBarBg, expBarCX, expBarCY, CARD.EXP_BAR_BG_W, CARD.EXP_BAR_BG_H, 1.0)
        local expProgress = (maxExp > 0) and (exp / maxExp) or 0
        expProgress = math.max(0, math.min(1, expProgress))
        local fillW = CARD.EXP_BAR_BG_W - CARD.EXP_BAR_PADDING * 2
        local fillH = CARD.EXP_BAR_BG_H - CARD.EXP_BAR_PADDING * 2
        local fillX = expBarCX - CARD.EXP_BAR_BG_W * 0.5 + CARD.EXP_BAR_PADDING
        local fillY = expBarCY - CARD.EXP_BAR_BG_H * 0.5 + CARD.EXP_BAR_PADDING
        local clipW = fillW * expProgress
        if clipW > 0 and imgExpBarFill >= 0 then
            nvgSave(vg)
            nvgScissor(vg, fillX, fillY, clipW, fillH)
            local paint = nvgImagePattern(vg, fillX, fillY, fillW, fillH, 0, imgExpBarFill, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, fillX, fillY, fillW, fillH)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
            nvgResetScissor(vg)
            nvgRestore(vg)
        end

        -- 等级徽章
        local badgeCX = cx + CARD.LVL_BADGE_DX
        local badgeCY = cy + CARD.LVL_BADGE_DY
        drawImageCentered(vg, imgLvlBadge, badgeCX, badgeCY, CARD.LVL_BADGE_SIZE, CARD.LVL_BADGE_SIZE, 1.0)
        drawTextStroke(vg, badgeCX, badgeCY, tostring(heroLevel),
            28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)

        -- 角色名背景 + 文字
        local nameBgCY = cy + CARD.NAME_BG_DY
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - CARD.NAME_BG_W * 0.5, nameBgCY - CARD.NAME_BG_H * 0.5,
            CARD.NAME_BG_W, CARD.NAME_BG_H, CARD.NAME_BG_RADIUS)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
        nvgFill(vg)
        drawTextStroke(vg, cx, nameBgCY, heroCfg.name,
            28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)
    end

    -- === 5) 装备槽位 ===
    local equipData = PlayerStore.Get("equipment")
    local heroEquipped = nil
    local heroInventory = nil
    if equipData then
        heroEquipped = equipData.equipped and equipData.equipped[heroId]
        heroInventory = equipData.inventory
    end

    -- 槽位强化等级（slotEnhance）
    local slotEnhanceData = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
    local heroesData = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
    local partySlot = EquipmentSystem.findPartySlot(heroesData and heroesData.deployed, heroId)
    local slotEnhLevels = nil
    if slotEnhanceData and slotEnhanceData.levels and partySlot then
        slotEnhLevels = slotEnhanceData.levels[tostring(partySlot)] or slotEnhanceData.levels[partySlot]
    end

    for _, slot in ipairs(DT_SLOTS) do
        -- 配装tab下：选中槽位绘制选中底图
        if detailState.tab == "equip" and slot.slot == detailState.equipSlot and img.slotSelected >= 0 then
            drawImageCentered(vg, img.slotSelected, slot.cx, slot.cy, 234, 234, 1.0)
        end

        local slotImg
        if slot.img == "weapon" then
            slotImg = img.slotWeapon
        elseif slot.img == "offhand" then
            slotImg = img.slotOffhand
        elseif slot.img == "armor" then
            slotImg = img.slotArmor
        else
            slotImg = img.slotAccessory
        end
        drawImageCentered(vg, slotImg, slot.cx, slot.cy, DT_SLOT_SIZE, DT_SLOT_SIZE, 1.0)

        local equippedEquip = nil
        local isTwohandOccupied = false
        if heroEquipped and heroInventory then
            local seq = heroEquipped[slot.slot]
            if seq then
                equippedEquip = heroInventory[tostring(seq)]
            end
            if not equippedEquip and slot.slot == "offhand" then
                local weaponSeq = heroEquipped["weapon"]
                if weaponSeq then
                    local weaponEquip = heroInventory[tostring(weaponSeq)]
                    if weaponEquip and weaponEquip.grip == "twohand" then
                        equippedEquip = weaponEquip
                        isTwohandOccupied = true
                    end
                end
            end
        end

        if equippedEquip then
            local scx, scy = slot.cx, slot.cy
            local eq = equippedEquip.quality or 1

            local qBgImg = CharacterDetailRef._getQualityBg(eq)
            if qBgImg >= 0 then
                drawImageCentered(vg, qBgImg, scx, scy, DT_SLOT_SIZE, DT_SLOT_SIZE, 1.0)
            end

            local equipIconImg = CharacterDetailRef._getEquipIcon(equippedEquip.templateId)
            local iconPad = 12
            local iconSize = DT_SLOT_SIZE - iconPad * 2
            if equipIconImg >= 0 then
                drawImageCentered(vg, equipIconImg, scx, scy, iconSize, iconSize, 1.0)
            else
                local qualityDef = EquipmentConfig.QUALITY[eq]
                local qc = qualityDef and qualityDef.color or { 180, 180, 180 }
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 22)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 255))
                nvgText(vg, scx, scy, equippedEquip.name, nil)
            end

            do
                local lvlText = "Lv." .. tostring(equippedEquip.level)
                local lvlX = scx + DT_SLOT_SIZE * 0.5 - 8
                local lvlY = scy + DT_SLOT_SIZE * 0.5 - 8
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

            local slotEnhLv = slotEnhLevels and slotEnhLevels[slot.slot] or 0
            if slotEnhLv > 0 then
                local enhText = "+" .. slotEnhLv
                local enhX = scx + DT_SLOT_SIZE * 0.5 - 8
                local enhY = scy - DT_SLOT_SIZE * 0.5 + 8
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

            if isTwohandOccupied then
                nvgBeginPath(vg)
                nvgRoundedRect(vg,
                    scx - DT_SLOT_SIZE * 0.5,
                    scy - DT_SLOT_SIZE * 0.5,
                    DT_SLOT_SIZE, DT_SLOT_SIZE, 24)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
                nvgFill(vg)
            end
        end

        -- ICON_UP 可提升角标（使用缓存，避免每帧遍历全背包）
        local imgIconUp = CharacterDetailRef._imgIconUp
        if not isTwohandOccupied and imgIconUp >= 0
            and getCachedUpgrade(heroId, slot.slot, equipData) then
            local upSize = 40
            local upX = slot.cx - DT_SLOT_SIZE * 0.5 + upSize * 0.5 + 2
            local upY = slot.cy - DT_SLOT_SIZE * 0.5 + upSize * 0.5 + 2
            drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
        end

        -- 新手引导热点：主武器槽
        if slot.slot == "weapon" then
            local _TM = require("systems.TutorialManager")
            if _TM.isActive() then _TM.registerHotspot("equip_slot_weapon", slot.cx, slot.cy, DT_SLOT_SIZE, DT_SLOT_SIZE) end
        end
    end

    -- === 6) 一键卸下 / 一键装备 按钮 ===
    do
        local bx, by = BTN_UNEQUIP_CX - BTN_BATCH_W * 0.5, BTN_UNEQUIP_CY - BTN_BATCH_H * 0.5
        DrawUtil.drawNineSlice(vg, img.btnHong, bx, by, BTN_BATCH_W, BTN_BATCH_H,
            NP.hongT, NP.hongR, NP.hongB, NP.hongL)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))
        local _ds1 = BF.begin(vg, "unequip_all", BTN_UNEQUIP_CX, BTN_UNEQUIP_CY, BTN_BATCH_W, BTN_BATCH_H)
        nvgText(vg, BTN_UNEQUIP_CX, BTN_UNEQUIP_CY, "一键卸下", nil)
        BF.finish(vg, _ds1)
    end
    do
        local bx, by = BTN_EQUIP_CX - BTN_BATCH_W * 0.5, BTN_EQUIP_CY - BTN_BATCH_H * 0.5
        DrawUtil.drawNineSlice(vg, img.btnLv, bx, by, BTN_BATCH_W, BTN_BATCH_H,
            NP.lvT, NP.lvR, NP.lvB, NP.lvL)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))
        local _ds = BF.begin(vg, "equip_all", BTN_EQUIP_CX, BTN_EQUIP_CY, BTN_BATCH_W, BTN_BATCH_H)
        nvgText(vg, BTN_EQUIP_CX, BTN_EQUIP_CY, "一键装备", nil)
        BF.finish(vg, _ds)
        local _TM = require("systems.TutorialManager")
        if _TM.isActive() then _TM.registerHotspot("equip_btn_auto", BTN_EQUIP_CX, BTN_EQUIP_CY, BTN_BATCH_W, BTN_BATCH_H) end
    end

    nvgRestore(vg)  -- 结束动态内容偏移（switchOX/switchAlpha）

    -- === 左右切换箭头按钮（静态，不参与切换动画） ===
    if img.arrowBg >= 0 then
        -- 左箭头背景（翻转绘制，对齐屏幕左边缘）
        nvgSave(vg)
        nvgTranslate(vg, M.ARROW_BG_LEFT_CX, M.ARROW_CY)
        nvgScale(vg, -1, 1)  -- 水平翻转
        drawImageCentered(vg, img.arrowBg, 0, 0, M.ARROW_BG_W, M.ARROW_BG_H, 1.0)
        nvgRestore(vg)
        -- 左箭头图标（翻转+对称位置：距左边缘69px）
        if img.arrowIcon >= 0 then
            nvgSave(vg)
            nvgTranslate(vg, M.ARROW_LEFT_CX + M.ARROW_ICON_INSET, M.ARROW_CY)
            nvgScale(vg, -1, 1)  -- 水平翻转使箭头指向左
            drawImageCentered(vg, img.arrowIcon, 0, 0, M.ARROW_ICON_W, M.ARROW_ICON_H, 1.0)
            nvgRestore(vg)
        end

        -- 右箭头背景（对齐屏幕右边缘）
        drawImageCentered(vg, img.arrowBg, M.ARROW_BG_RIGHT_CX, M.ARROW_CY, M.ARROW_BG_W, M.ARROW_BG_H, 1.0)
        -- 右箭头图标（距右边缘69px）
        if img.arrowIcon >= 0 then
            drawImageCentered(vg, img.arrowIcon, M.ARROW_RIGHT_CX - M.ARROW_ICON_INSET, M.ARROW_CY, M.ARROW_ICON_W, M.ARROW_ICON_H, 1.0)
        end
    end

    nvgRestore(vg)  -- 结束上半部分偏移

    -- ================== 下半部分（从下方滑入） ==================
    nvgSave(vg)
    nvgTranslate(vg, 0, lowerOY)

    -- === 6) 角色详情属性背景图（静态，不参与切换动画） ===
    drawImageCentered(vg, img.midBg, MID_BG_CX, MID_BG_CY, MID_BG_W, MID_BG_H, 1.0)

    -- === 7) "角色详情" 标题文本（静态） ===
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local titleSW = 4
    nvgFillColor(vg, nvgRGBA(0x23, 0x23, 0x23, 255))
    local stepAngle = math.pi * 2 / 16
    for i = 0, 15 do
        local a = i * stepAngle
        nvgText(vg, MID_TITLE_CX + math.cos(a) * titleSW, MID_TITLE_CY + math.sin(a) * titleSW, "角色详情", nil)
    end
    nvgFillColor(vg, nvgRGBA(0xf7, 0xfe, 0x77, 255))
    nvgText(vg, MID_TITLE_CX, MID_TITLE_CY, "角色详情", nil)

    -- === 动态内容开始（箭头切换时水平滑入+淡入） ===
    nvgSave(vg)
    nvgTranslate(vg, switchOX, 0)
    nvgGlobalAlpha(vg, switchAlpha)

    -- === 8~17) 名称/经验/品质/职业/分割线：配装tab下隐藏 ===
    if detailState.tab ~= "equip" then

    -- === 8) 角色名称 ===
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x7b, 0x53, 0x39, 255))
    nvgText(vg, MID_NAME_CX, MID_NAME_CY, heroCfg.name, nil)

    -- === 9) 大经验条 ===
    drawImageCentered(vg, img.midExpBg, MID_EXP_CX, MID_EXP_CY, MID_EXP_W, MID_EXP_H, 1.0)
    local midExpProgress = (maxExp > 0) and (exp / maxExp) or 0
    midExpProgress = math.max(0, math.min(1, midExpProgress))
    local meFillW = MID_EXP_W - MID_EXP_PADDING * 2
    local meFillH = MID_EXP_H - MID_EXP_PADDING * 2
    local meFillX = MID_EXP_CX - MID_EXP_W * 0.5 + MID_EXP_PADDING
    local meFillY = MID_EXP_CY - MID_EXP_H * 0.5 + MID_EXP_PADDING
    local meClipW = meFillW * midExpProgress
    if meClipW > 0 and img.midExpFill >= 0 then
        nvgSave(vg)
        nvgScissor(vg, meFillX, meFillY, meClipW, meFillH)
        local paint = nvgImagePattern(vg, meFillX, meFillY, meFillW, meFillH, 0, img.midExpFill, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, meFillX, meFillY, meFillW, meFillH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    -- === 10) 等级文本 ===
    local lvlText = "等级" .. tostring(heroLevel)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local lvlSW = 5
    nvgFillColor(vg, nvgRGBA(0x31, 0x24, 0x24, 255))
    for i = 0, 15 do
        local a = i * stepAngle
        nvgText(vg, MID_EXP_CX + math.cos(a) * lvlSW, MID_EXP_CY + math.sin(a) * lvlSW, lvlText, nil)
    end
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, MID_EXP_CX, MID_EXP_CY, lvlText, nil)

    -- === 11) 品质内容背景框 ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        MID_QUALITY_BOX_CX - MID_QUALITY_BOX_W * 0.5,
        MID_QUALITY_BOX_CY - MID_QUALITY_BOX_H * 0.5,
        MID_QUALITY_BOX_W, MID_QUALITY_BOX_H, 20)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)

    -- === 12) "品质"文本 ===
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 35)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
    nvgText(vg, MID_QUALITY_LABEL_X, MID_QUALITY_LABEL_Y, "品质", nil)

    -- === 13) 品质文字图标 ===
    local qualityName = HC.QUALITY_INFO[heroCfg.quality]
        and HC.QUALITY_INFO[heroCfg.quality].name or "R"
    local qBadge = imgQualityBadges[qualityName]
    if qBadge and qBadge >= 0 then
        local qImgW, qImgH = nvgImageSize(vg, qBadge)
        local qDrawCX = MID_QUALITY_ICON_RIGHT_X - qImgW * 0.5
        drawImageCentered(vg, qBadge, qDrawCX, MID_QUALITY_LABEL_Y, qImgW, qImgH, 1.0)
    end

    -- === 14) 职业内容背景框 ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        MID_CLASS_BOX_CX - MID_CLASS_BOX_W * 0.5,
        MID_CLASS_BOX_CY - MID_CLASS_BOX_H * 0.5,
        MID_CLASS_BOX_W, MID_CLASS_BOX_H, 20)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)

    -- === 15) "职业"文本 ===
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 35)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
    nvgText(vg, MID_CLASS_LABEL_X, MID_CLASS_LABEL_Y, "职业", nil)

    -- === 16) 职业图标 + 文字组合 ===
    local classCfg = CC.get(heroCfg.classId)
    local className = classCfg and classCfg.name or "未知"
    local classIconIdx = CLASS_ICON_MAP[heroCfg.classId]
    local classIcon = classIconIdx and imgClassIcons[classIconIdx] or -1

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 34)
    local classTextW = nvgTextBounds(vg, 0, 0, className)
    local classGap = 6
    local comboW = MID_CLASS_ICON_SIZE + classGap + classTextW
    local comboRightX = MID_CLASS_COMBO_RIGHT_X
    local comboLeftX  = comboRightX - comboW
    local classIconCX = comboLeftX + MID_CLASS_ICON_SIZE * 0.5
    local classTextX  = comboLeftX + MID_CLASS_ICON_SIZE + classGap

    if classIcon >= 0 then
        drawImageCentered(vg, classIcon, classIconCX, MID_CLASS_LABEL_Y,
            MID_CLASS_ICON_SIZE, MID_CLASS_ICON_SIZE, 1.0)
    end
    drawTextStroke(vg, classTextX, MID_CLASS_LABEL_Y, className,
        34, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4)

    -- === 17) 分割线1 ===
    drawImageCentered(vg, img.midDiv1, MID_DIV1_CX, MID_DIV1_CY, MID_DIV1_W, MID_DIV1_H, 1.0)

    end -- if tab ~= "equip"（隐藏 8~17: 名称/经验/品质/职业/分割线）

    -- ================================================================
    -- ===          Tab 分支：属性页 / 觉醒页                        ===
    -- ================================================================

    if detailState.tab == "awaken" then
        -- 觉醒面板绘制
        AwakeningPanel.draw(vg, heroId)

    elseif detailState.tab == "equip" then
        -- 配装面板绘制（由 CharacterDetailEquip 子模块负责）
        if M._drawEquipPanel then
            M._drawEquipPanel(vg, heroId, detailState)
        end

    else -- detailState.tab == "attr"

    -- ================================================================
    -- ===                  属性区域（2列×N行）                      ===
    -- ================================================================

    local attrData = collectAttributes(heroId, heroCfg, heroLevel)
    local leftAttrs  = attrData.left
    local rightAttrs = attrData.right
    local totalRows  = math.max(#leftAttrs, #rightAttrs)

    detailState.cachedLeft  = leftAttrs
    detailState.cachedRight = rightAttrs

    local attrClipY = ATTR_FIRST_ROW_Y - ATTR_BOX_H * 0.5
    local attrClipH = ATTR_VISIBLE_ROWS * ATTR_BOX_H + (ATTR_VISIBLE_ROWS - 1) * ATTR_ROW_GAP

    local rowStep = ATTR_BOX_H + ATTR_ROW_GAP
    local totalContentH = totalRows * ATTR_BOX_H + (totalRows - 1) * ATTR_ROW_GAP
    detailState.attrScrollMax = math.max(0, totalContentH - attrClipH)

    nvgSave(vg)
    nvgScissor(vg, 0, attrClipY, DESIGN_W, attrClipH)

    for row = 1, totalRows do
        local rowY = ATTR_FIRST_ROW_Y + (row - 1) * rowStep - detailState.attrScrollY

        if rowY >= attrClipY - ATTR_BOX_H and rowY <= attrClipY + attrClipH + ATTR_BOX_H then

            -- === 左列属性 ===
            if row <= #leftAttrs then
                local attr = leftAttrs[row]
                local colCX = ATTR_COL1_CX

                nvgBeginPath(vg)
                nvgRoundedRect(vg,
                    colCX - ATTR_BOX_W * 0.5, rowY - ATTR_BOX_H * 0.5,
                    ATTR_BOX_W, ATTR_BOX_H, ATTR_BOX_RADIUS)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
                nvgFill(vg)

                drawImageCentered(vg, img.attrDeco, ATTR_DECO_X, rowY,
                    ATTR_DECO_SIZE, ATTR_DECO_SIZE, 1.0)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, ATTR_FONT_SIZE)
                local nameW = nvgTextBounds(vg, 0, 0, attr.name)
                local valW  = nvgTextBounds(vg, 0, 0, attr.value)
                local maxNameW = ATTR_VAL_RIGHT_X - ATTR_NAME_LEFT_X - valW - ATTR_NAME_VAL_GAP
                local nameFontSize = ATTR_FONT_SIZE
                if maxNameW > 0 and nameW > maxNameW then
                    nameFontSize = math.max(ATTR_FONT_SIZE_MIN,
                        math.floor(ATTR_FONT_SIZE * maxNameW / nameW))
                    nvgFontSize(vg, nameFontSize)
                end
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
                nvgText(vg, ATTR_NAME_LEFT_X, rowY, attr.name, nil)

                drawTextStroke(vg, ATTR_VAL_RIGHT_X, rowY, attr.value,
                    ATTR_FONT_SIZE, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 4)
            end

            -- === 右列属性 ===
            if row <= #rightAttrs then
                local attr = rightAttrs[row]
                local colCX = ATTR_COL2_CX

                nvgBeginPath(vg)
                nvgRoundedRect(vg,
                    colCX - ATTR_BOX_W * 0.5, rowY - ATTR_BOX_H * 0.5,
                    ATTR_BOX_W, ATTR_BOX_H, ATTR_BOX_RADIUS)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
                nvgFill(vg)

                drawImageCentered(vg, img.attrDeco, ATTR_DECO_X + ATTR_DECO_DX, rowY,
                    ATTR_DECO_SIZE, ATTR_DECO_SIZE, 1.0)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, ATTR_FONT_SIZE)
                local rNameW = nvgTextBounds(vg, 0, 0, attr.name)
                local rValW  = nvgTextBounds(vg, 0, 0, attr.value)
                local rMaxNameW = (ATTR_VAL_RIGHT_X + ATTR_DECO_DX)
                    - (ATTR_NAME_LEFT_X + ATTR_DECO_DX) - rValW - ATTR_NAME_VAL_GAP
                local rNameFS = ATTR_FONT_SIZE
                if rMaxNameW > 0 and rNameW > rMaxNameW then
                    rNameFS = math.max(ATTR_FONT_SIZE_MIN,
                        math.floor(ATTR_FONT_SIZE * rMaxNameW / rNameW))
                    nvgFontSize(vg, rNameFS)
                end
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
                nvgText(vg, ATTR_NAME_LEFT_X + ATTR_DECO_DX, rowY, attr.name, nil)

                drawTextStroke(vg, ATTR_VAL_RIGHT_X + ATTR_DECO_DX, rowY, attr.value,
                    ATTR_FONT_SIZE, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 4)
            end
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- === 18) 分割线2 ===
    drawImageCentered(vg, img.midDiv2, MID_DIV2_CX, MID_DIV2_CY, MID_DIV2_W, MID_DIV2_H, 1.0)

    -- ================================================================
    -- ===                  六围区域（2列×3行）                      ===
    -- ================================================================

    local statValues = attrData.stats

    for _, st in ipairs(STAT_LAYOUT) do
        local boxCX = (st.col == 1) and STAT_COL1_CX or STAT_COL2_CX
        local boxCY = STAT_ROW1_CY + (st.row - 1) * STAT_ROW_STEP

        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            boxCX - STAT_BOX_W * 0.5, boxCY - STAT_BOX_H * 0.5,
            STAT_BOX_W, STAT_BOX_H, STAT_BOX_RADIUS)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
        nvgFill(vg)

        local ibCX = boxCX + STAT_ICON_BG_DX
        local ibCY = boxCY + STAT_ICON_BG_DY
        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            ibCX - STAT_ICON_BG_SIZE * 0.5, ibCY - STAT_ICON_BG_SIZE * 0.5,
            STAT_ICON_BG_SIZE, STAT_ICON_BG_SIZE, STAT_ICON_BG_R)
        nvgFillColor(vg, nvgRGBA(0xa9, 0xa0, 0x8f, 255))
        nvgFill(vg)

        local iconImg = imgStatIcons[st.icon] or -1
        if iconImg >= 0 then
            local icCX = boxCX + STAT_ICON_DX
            local icCY = boxCY + STAT_ICON_DY
            drawImageCentered(vg, iconImg, icCX, icCY, STAT_ICON_SIZE, STAT_ICON_SIZE, 1.0)
        end

        local nmX = boxCX + STAT_NAME_DX
        local nmY = boxCY + STAT_NAME_DY
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 35)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
        nvgText(vg, nmX, nmY, st.name, nil)

        local valY = boxCY + STAT_VAL_DY
        local valStr = tostring(statValues[st.key] or 0)
        drawTextStroke(vg, nmX, valY, valStr,
            35, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)
    end

    -- ================================================================
    -- ===                    天赋技能区域                            ===
    -- ================================================================

    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        TALENT_BG_CX - TALENT_BG_W * 0.5, TALENT_BG_CY - TALENT_BG_H * 0.5,
        TALENT_BG_W, TALENT_BG_H, TALENT_BG_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)

    local talentName = heroCfg.talentName or ""
    drawTextStroke(vg, TALENT_NAME_X, TALENT_NAME_Y, talentName .. "：",
        40, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        0x66, 0xf8, 0x62, 5)

    local talentDesc = heroCfg.talentDesc or ""
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
    nvgTextBox(vg, TALENT_TEXT_LEFT, TALENT_TEXT_TOP, TALENT_TEXT_WIDTH, talentDesc, nil)

    end -- if detailState.tab == "awaken" / "attr"

    nvgRestore(vg)  -- 结束动态内容偏移（switchOX/switchAlpha）

    -- ================================================================
    -- ===              底部按钮区域（静态，不参与切换动画）          ===
    -- ================================================================

    drawImageCentered(vg, img.btnBack, BTN_BACK_CX, BTN_BACK_CY, BTN_BACK_W, BTN_BACK_H, 1.0)

    drawImageCentered(vg, img.tabBg, BTN_TAB_BG_CX, BTN_TAB_BG_CY, BTN_TAB_BG_W, BTN_TAB_BG_H, 1.0)

    local TAB_CX_MAP = { attr = BTN_TAB_ATTR_CX, equip = BTN_TAB_EQUIP_CX, awaken = BTN_TAB_AWAKEN_CX }
    local targetCX = TAB_CX_MAP[detailState.tab] or BTN_TAB_ATTR_CX
    local fromCX   = TAB_CX_MAP[detailState.tabFrom] or BTN_TAB_ATTR_CX
    local tabElapsed = time.elapsedTime - detailState.tabSwitchTime
    local tabT = math.min(1.0, tabElapsed / TAB_ANIM_DURATION)
    local tabEased = easeOutCubic(tabT)
    local sliderCX = fromCX + (targetCX - fromCX) * tabEased
    local sliderCY = BTN_TAB_BG_CY
    DrawUtil.drawNineSlice(vg, img.tabSlider,
        sliderCX - BTN_TAB_SLIDER_W * 0.5, sliderCY - BTN_TAB_SLIDER_H * 0.5,
        BTN_TAB_SLIDER_W, BTN_TAB_SLIDER_H,
        10, 70, 10, 70)

    -- Tab 文字绘制（3个Tab）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 40)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local activeColor   = nvgRGBA(0x81, 0x57, 0x3c, 255)
    local inactiveColor = nvgRGBA(255, 255, 255, 255)
    local curTab = detailState.tab

    nvgFillColor(vg, curTab == "attr" and activeColor or inactiveColor)
    nvgText(vg, TEXT_ATTR_CX, TEXT_ATTR_CY, "属性", nil)

    nvgFillColor(vg, curTab == "equip" and activeColor or inactiveColor)
    nvgText(vg, TEXT_EQUIP_CX, TEXT_EQUIP_CY, "配装", nil)

    nvgFillColor(vg, curTab == "awaken" and activeColor or inactiveColor)
    nvgText(vg, TEXT_AWAKEN_CX, TEXT_AWAKEN_CY, "觉醒", nil)

    -- 觉醒Tab角标：当前英雄有可用觉醒点时，在文字右上角显示 ICON_UP（选中也显示）
    if CharacterDetailRef and CharacterDetailRef.hasAwakeningUpgrade then
        if CharacterDetailRef.hasAwakeningUpgrade(heroId) then
            local imgIconUp = CharacterDetailRef._imgIconUp
            if imgIconUp and imgIconUp >= 0 then
                local upSize = 30
                local upX = TEXT_AWAKEN_CX + 50
                local upY = TEXT_AWAKEN_CY - 18
                drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
            end
        end
    end

    -- ================================================================
    -- ===               属性说明气泡（最上层绘制）                  ===
    -- ================================================================
    if detailState.attrTip and detailState.tab == "attr" then
        local tip = detailState.attrTip

        local TIP_PAD_X   = 24
        local TIP_PAD_TOP = 16
        local TIP_PAD_BOT = 18
        local TIP_RADIUS  = 16
        local TIP_ARROW_W = 20
        local TIP_ARROW_H = 12
        local TIP_GAP     = 6
        local TIP_FONT    = 28
        local TIP_NAME_FONT = 30
        local TIP_MAX_W   = 420
        local TIP_LINE_H  = 36

        nvgFontFace(vg, "sans")

        nvgFontSize(vg, TIP_NAME_FONT)
        ---@diagnostic disable-next-line: missing-parameter
        local nameW = nvgTextBounds(vg, 0, 0, tip.name)

        nvgFontSize(vg, TIP_FONT)
        local descWrapW = TIP_MAX_W - TIP_PAD_X * 2
        local descRows = {}
        local descText = tip.desc
        local curLine = ""
        for _, codepoint in utf8.codes(descText) do
            local ch = utf8.char(codepoint)
            local testLine = curLine .. ch
            local tw = nvgTextBounds(vg, 0, 0, testLine)
            if tw > descWrapW and curLine ~= "" then
                descRows[#descRows + 1] = curLine
                curLine = ch
            else
                curLine = testLine
            end
        end
        if curLine ~= "" then
            descRows[#descRows + 1] = curLine
        end

        local descH = #descRows * TIP_LINE_H
        local contentW = math.max(nameW + TIP_PAD_X * 2, TIP_MAX_W)
        contentW = math.min(contentW, TIP_MAX_W)
        local tipW = contentW
        local tipH = TIP_PAD_TOP + TIP_NAME_FONT + 8 + descH + TIP_PAD_BOT

        local arrowTipY = tip.boxTopY - TIP_GAP
        local tipBottomY = arrowTipY - TIP_ARROW_H
        local tipTopY = tipBottomY - tipH
        local tipCX = tip.boxCX

        local tipLeft = tipCX - tipW * 0.5
        local tipRight = tipCX + tipW * 0.5
        if tipLeft < 16 then
            tipLeft = 16
            tipRight = tipLeft + tipW
        end
        if tipRight > DESIGN_W - 16 then
            tipRight = DESIGN_W - 16
            tipLeft = tipRight - tipW
        end
        local arrowCX = math.max(tipLeft + TIP_ARROW_W + TIP_RADIUS,
                         math.min(tip.boxCX, tipRight - TIP_ARROW_W - TIP_RADIUS))

        nvgBeginPath(vg)
        nvgRoundedRect(vg, tipLeft, tipTopY, tipW, tipH, TIP_RADIUS)
        nvgFillColor(vg, nvgRGBA(0x2a, 0x1f, 0x18, 230))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgMoveTo(vg, arrowCX - TIP_ARROW_W, tipBottomY)
        nvgLineTo(vg, arrowCX, arrowTipY)
        nvgLineTo(vg, arrowCX + TIP_ARROW_W, tipBottomY)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(0x2a, 0x1f, 0x18, 230))
        nvgFill(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TIP_NAME_FONT)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(0xff, 0xd7, 0x6e, 255))
        nvgText(vg, tipLeft + TIP_PAD_X, tipTopY + TIP_PAD_TOP, tip.name, nil)

        nvgFontSize(vg, TIP_FONT)
        nvgFillColor(vg, nvgRGBA(0xe8, 0xe0, 0xd4, 255))
        local textY = tipTopY + TIP_PAD_TOP + TIP_NAME_FONT + 8
        for i, line in ipairs(descRows) do
            nvgText(vg, tipLeft + TIP_PAD_X, textY + (i - 1) * TIP_LINE_H, line, nil)
        end
    end

    nvgRestore(vg)  -- 结束下半部分偏移

    -- === 装备背包覆盖层 ===
    EquipmentBag.draw(vg)

    -- === 装备详情弹窗（配装面板点击时显示）===
    if not EquipmentBag.isOpen() then
        local EquipmentDetail = require("ui.EquipmentDetail")
        if EquipmentDetail.isOpen() then
            EquipmentDetail.draw(vg)
        end
    end
end

return M
