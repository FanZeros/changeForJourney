-- ============================================================================
-- CharacterDetailDraw - 角色详情界面绘制子模块
-- 从 CharacterDetail.lua 提取的布局常量、图片资源和 draw 函数
-- ============================================================================

local HC               = require("config.HeroConfig")
local HeroAssetUtil    = require("config.HeroAssetUtil")
local CC               = require("config.ClassConfig")
local GameConfig        = require("config.GameConfig")
local ExpTable          = require("config.ExpTable")
local EquipmentBag      = require("ui.character.equip.EquipmentBag")
local PlayerStore       = require("core.PlayerStore")
local EquipmentConfig   = require("config.EquipmentConfig")
local DetailAttrs       = require("ui.character.detail.CharacterDetailAttrs")
local DrawUtil          = require("core.DrawUtil")
local HeroAssetUtil     = require("config.HeroAssetUtil")
local AwakeningPanel    = require("ui.character.hero.AwakeningPanel")
local ClientDispatcher  = require("runtime.ClientDispatcher")
local EquipmentSystem   = require("systems.EquipmentSystem")
local BF                 = require("systems.ButtonFeedback")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格
local ETS = require("systems.ExtraTalentSystem")
local I18n = require("core.I18n")

local drawTextStroke = DrawUtil.drawTextStroke

local M = {}

---@type fun(vg: any, heroId: number, detailState: table)|nil
M._drawEquipPanel = nil

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 详情界面布局常量 ========================

-- 背景图
local DT_BG_CX, DT_BG_CY  = 540, 477
local DT_BG_W,  DT_BG_H   = 1240, 1290

-- 角色卡片中心（上移 50px，给底部名字/按钮区留空间）
local DT_CARD_CX, DT_CARD_CY = 540, 447

-- 装备槽位
local DT_SLOT_SIZE = 160
M.DT_SLOT_SIZE = DT_SLOT_SIZE  -- handleInput 需要
-- 六边形围立绘（中心 540,447，垂直半径 262/水平 ±215，顶点朝上；立绘缩至 362 高避开上下槽）
local DT_SLOTS = {
    { name = "头盔",   cx = 540, cy = 185, img = "helmet",    slot = "helmet" },
    { name = "饰品",   cx = 755, cy = 316, img = "accessory", slot = "accessory" },
    { name = "副武器", cx = 755, cy = 578, img = "offhand",   slot = "offhand" },
    { name = "鞋子",   cx = 540, cy = 790, img = "shoes",     slot = "shoes" },
    { name = "主武器", cx = 325, cy = 578, img = "weapon",    slot = "weapon" },
    { name = "护甲",   cx = 325, cy = 316, img = "armor",     slot = "armor" },
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

local MID_CLASS_BOX_CX, MID_CLASS_BOX_CY = 540, 1175
local MID_CLASS_BOX_W, MID_CLASS_BOX_H   = 900, 60
M.MID_CLASS_BOX_CX = MID_CLASS_BOX_CX
M.MID_CLASS_BOX_CY = MID_CLASS_BOX_CY
M.MID_CLASS_BOX_W = MID_CLASS_BOX_W
M.MID_CLASS_BOX_H = MID_CLASS_BOX_H
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

-- 左列单列，右侧留给雷达图。可见 8 行，超出继续滚动。
local ATTR_VISIBLE_ROWS = 8
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

local MID_DIV2_CX, MID_DIV2_CY = 540, 1840
local MID_DIV2_W, MID_DIV2_H   = 1010, 37

-- ======================== 六围区域布局常量 ========================
-- 雷达图占位仍按旧的 2 列 × 3 行盒子算高度，避免把下面的天赋区顶开。

local STAT_BOX_W, STAT_BOX_H = 437, 95
local STAT_BOX_RADIUS        = 20
local STAT_COL1_CX           = 308.5
local STAT_ROW1_CY           = 1641
local STAT_COL_GAP           = 26
local STAT_ROW_GAP_STAT      = 16
local STAT_COL2_CX           = STAT_COL1_CX + STAT_BOX_W + STAT_COL_GAP
local STAT_ROW_STEP          = STAT_BOX_H + STAT_ROW_GAP_STAT

-- 雷达图放在右列，高度对齐分割线以上的属性区
local HEX_CX = 800
local HEX_CY = ATTR_FIRST_ROW_Y + (ATTR_VISIBLE_ROWS - 1) * (ATTR_BOX_H + ATTR_ROW_GAP) * 0.5
local HEX_R  = 175
local HEX_LABEL_R = 230
-- 顶点顺序：上起顺时针。力量在上，其余按战斗直觉绕圈。
local HEX_NAMES = { "力量", "敏捷", "体质", "魂火", "命数", "秘识" }
local HEX_KEYS = { ["力量"] = "str", ["敏捷"] = "agi", ["体质"] = "vit", ["魂火"] = "spi", ["命数"] = "luk", ["秘识"] = "int" }
-- 六维各自的颜色：力量赤、敏捷绿、体质褐、魂火紫、命数金、秘识青
local HEX_COLORS = {
    ["力量"] = { 0xE2, 0x4A, 0x3B },
    ["敏捷"] = { 0x3D, 0xDC, 0x6E },
    ["体质"] = { 0xC4, 0x8A, 0x3A },
    ["魂火"] = { 0xC0, 0x58, 0xE8 },
    ["命数"] = { 0xFF, 0xD2, 0x3A },
    ["秘识"] = { 0x3E, 0xC6, 0xE0 },
}

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
M.HEX_CX        = HEX_CX
M.HEX_CY        = HEX_CY
M.HEX_LABEL_R   = HEX_LABEL_R
M.HEX_NAMES     = HEX_NAMES

-- ======================== 天赋技能区域布局常量 ========================

local TALENT_BG_CX, TALENT_BG_CY = 540, 2045
local TALENT_BG_W, TALENT_BG_H   = 903, 210
local TALENT_BG_RADIUS            = 20

local TALENT_NAME_Y = 1918
local TALENT_TEXT_LEFT   = TALENT_BG_CX - TALENT_BG_W * 0.5 + 33
local TALENT_TEXT_TOP    = TALENT_NAME_Y + 36
local TALENT_TEXT_RIGHT  = TALENT_BG_CX + TALENT_BG_W * 0.5 - 33
local TALENT_TEXT_WIDTH  = TALENT_TEXT_RIGHT - TALENT_TEXT_LEFT

-- ======================== 一键卸下/一键装备按钮布局常量 ========================

local BTN_UNEQUIP_CX, BTN_UNEQUIP_CY = 211, 105
local BTN_EQUIP_CX,   BTN_EQUIP_CY   = 869, 105
local BTN_BATCH_W,     BTN_BATCH_H    = 304, 100
local EQUIP_LOWER_OFFSET = 160 -- 配装页底板下移，给装备词条预留空间

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

local BTN_BACK_CX, BTN_BACK_CY = 122, 1150
local BTN_BACK_W, BTN_BACK_H   = 184, 143

local BTN_TAB_BG_CX, BTN_TAB_BG_CY = 540, 2308
local BTN_TAB_BG_W, BTN_TAB_BG_H   = 810, 143

-- 4-Tab 布局：属性 / 配装 / 转职 / 觉醒
local BTN_TAB_SLIDER_W, BTN_TAB_SLIDER_H = 200, 143
local BTN_TAB_ATTR_CX, BTN_TAB_ATTR_CY     = 255, 2308
local BTN_TAB_EQUIP_CX, BTN_TAB_EQUIP_CY   = 445, 2308
local BTN_TAB_CLASS_CX, BTN_TAB_CLASS_CY   = 635, 2308
local BTN_TAB_AWAKEN_CX, BTN_TAB_AWAKEN_CY = 825, 2308

local TEXT_ATTR_CX, TEXT_ATTR_CY     = 255, 2302
local TEXT_EQUIP_CX, TEXT_EQUIP_CY   = 445, 2302
local TEXT_CLASS_CX, TEXT_CLASS_CY   = 635, 2302
local TEXT_AWAKEN_CX, TEXT_AWAKEN_CY = 825, 2302

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
M.BTN_TAB_CLASS_CX = BTN_TAB_CLASS_CX
M.BTN_TAB_CLASS_CY = BTN_TAB_CLASS_CY
M.BTN_TAB_AWAKEN_CX = BTN_TAB_AWAKEN_CX
M.BTN_TAB_AWAKEN_CY = BTN_TAB_AWAKEN_CY

-- 左右切换箭头按钮布局（直接挂 M，避免局部变量超限）
M.ARROW_BG_W      = 158
M.ARROW_BG_H      = 226
M.ARROW_ICON_W    = 54
M.ARROW_ICON_H    = 82
M.ARROW_CY        = 491
-- 图标中心（保持原位不变）
M.ARROW_LEFT_CX   = 158 * 0.5 - 30           -- 49: 左箭头图标中心
M.ARROW_RIGHT_CX  = DESIGN_W - 158 * 0.5 + 30 -- 1031: 右箭头图标中心
M.ARROW_ICON_INSET = 20                      -- 箭头图标向内偏移量（px）
-- 水平切换动画（参考建筑界面分页滑动风格）
M.SWITCH_ANIM_DURATION = 0.35               -- 切换动画时长（与建筑界面一致）
M.SWITCH_SLIDE_DIST    = 180                 -- 水平滑动距离（适中，不会太僵硬）

-- 卡片渲染常量（打包为 table，节省 local 变量槽位）
local CARD = {
    -- [复用角色展示/编队页卡片] 同尺寸 198x350 + 卡底锚定（战力上83/等级38/经验36），随卡高联动
    -- （卡 272..622：头盔槽底 265 / 鞋子槽顶 629，各留 7px；名牌不画——MID 名称行两页均显示）
    W=198, H=350, CY=544,
    SIDE_SCALE=0.92, SIDE_DX=250, CENTER_SCALE=1.18, YAW_SQUASH=0.86,
    TAG_SIZE=60, TAG_DX=63,  -- 职业标识右下角，与等级徽章(-63)左右对应
    POWER_BOTTOM_UP=83, POWER_ICON_SIZE=36,
    LVL_BADGE_SIZE=56, LVL_BADGE_DX=477-540, LVL_BOTTOM_UP=38,
}
M.ARROW_BG_LEFT_CX  = DT_CARD_CX - CARD.SIDE_DX
M.ARROW_BG_RIGHT_CX = DT_CARD_CX + CARD.SIDE_DX
M.SIDE_CARD_W = CARD.W * CARD.SIDE_SCALE * CARD.YAW_SQUASH
M.SIDE_CARD_H = CARD.H * CARD.SIDE_SCALE
M.SIDE_CARD_STEP = CARD.SIDE_DX
M.CARD_TOP_CY = CARD.CY
M.CARD_BOT_CY = CARD.CY
M.ARROW_CY = CARD.CY

-- 职业图标映射
local CLASS_ICON_MAP = {
    knight   = 1, seal  = 1,
    warrior  = 2, spoil = 2,
    mage     = 3, rift  = 3,
    ranger   = 4, echo  = 4,
    assassin = 5, mask  = 5,
    priest   = 6, debt  = 6,
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
    slotHelmet    = -1,
    slotShoes     = -1,
    slotAccessory = -1,
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
-- calcHeroPower 缓存：按英雄分别记录，滚动卡面每张都要显示自己的战力
local _powerCache = { dirty = true, values = {} }
-- _hasUpgradeForSlot 缓存：仅当 heroId 变化或装备数据脏时重算
local _upgradeCache = { heroId = nil, results = {}, dirty = true }  -- results[slotName] = bool

--- 标记战斗力缓存为脏（外部数据变化时调用）
function M.markPowerDirty()
    _powerCache.dirty = true
    _upgradeCache.dirty = true
end

--- 获取缓存的战斗力（数据变脏时整表重算，否则按英雄取缓存）
local function getCachedPower(heroId)
    if _powerCache.dirty then
        _powerCache.dirty = false
        _powerCache.values = {}
    end
    ---@type table<number, number>
    local values = _powerCache.values
    local cached = values[heroId]
    if cached then return cached end
    local power = calcHeroPowerFn and calcHeroPowerFn(heroId) or 0
    values[heroId] = power
    return power
end

--- 获取缓存的可提升判断（仅在 heroId 变化或脏标记时重算）
local function getCachedUpgrade(heroId, slotName, equipData)
    if _upgradeCache.heroId == heroId and not _upgradeCache.dirty then
        return _upgradeCache.results[slotName]
    end
    -- 脏了或 heroId 变了，全部重算 6 个槽位（一次性算完）
    _upgradeCache.heroId = heroId
    _upgradeCache.results = {}
    local SLOTS = { "weapon", "offhand", "armor", "helmet", "shoes", "accessory" }
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
end

--- 初始化图片（在 CharacterDetail.init 中调用）
function M.initImages(vg)
    img.detailBg      = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSXQ_BJ_dark.png", 0)
    -- 空槽底图与铁匠铺共用 TJP_ZBL，避免 JSXQ 新画头盔/鞋子风格不一致
    img.slotWeapon    = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_ZBL_WQ.png", 0)
    img.slotOffhand   = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_ZBL_FS.png", 0)
    img.slotArmor     = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_ZBL_HJ.png", 0)
    img.slotHelmet    = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_ZBL_TK.png", 0)
    img.slotShoes     = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_ZBL_XZ.png", 0)
    img.slotAccessory = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_ZBL_SP.png", 0)

    img.midBg      = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSJM_0.png", 0)
    img.midExpBg   = nvgCreateImage(vg, "image/进度条/UI_JSXQ_JYT1.png", 0)
    img.midExpFill = nvgCreateImage(vg, "image/进度条/UI_JSXQ_JYT2.png", 0)
    img.midDiv1    = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSXQ_FGXJ.png", 0)

    imgQualityBadges["R"]   = nvgCreateImage(vg, "image/品质框/UI_PZBZ_R.png", 0)
    imgQualityBadges["SR"]  = nvgCreateImage(vg, "image/品质框/UI_PZBZ_SR.png", 0)
    imgQualityBadges["SSR"] = nvgCreateImage(vg, "image/品质框/UI_PZBZ_SSR.png", 0)
    imgQualityBadges["UR"]  = nvgCreateImage(vg, "image/品质框/UI_PZBZ_UR.png", 0)

    img.attrDeco = nvgCreateImage(vg, "image/通用图标/ICON_XX.png", 0)
    img.midDiv2  = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSXQ_FGXJ.png", 0)

    for _, st in ipairs(STAT_LAYOUT) do
        imgStatIcons[st.icon] = nvgCreateImage(vg, "image/通用图标/" .. st.icon .. ".png", 0)
    end

    -- [暗黑化 P1-B5] 原 image/按钮/UI_AN_LV.png 贴图加载已移除（矢量绘制替代）
    img.btnLv     = nvgCreateImage(vg, "image/按钮/UI_AN_LV.png", 0)
    img.btnBack   = nvgCreateImage(vg, "image/按钮/UI_AN_FH.png", 0)
    -- [暗黑化 P1-B5] 原 image/按钮/UI_AN_2.png 贴图加载已移除（矢量绘制替代）
    img.tabSlider = nvgCreateImage(vg, "image/按钮/UI_AN_2.png", 0)

    img.arrowBg   = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_HS.png", 0)
    img.arrowIcon = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_XYG2.png", 0)
    img.slotSelected = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJPXZTBBJ.png", 0)
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
            detailState.switchFrom = nil
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

    -- 整页已由 CharacterDetail.draw 的 seamSlideX 水平滑动并与中缝返回条同步。
    -- 内部分段滑 + 遮罩淡入会和第二条轨迹打架，横屏中缝模式关掉。
    local seamMode = H_SEAM_BACK == true
    local upperOX = seamMode and 0 or (UPPER_SLIDE_DIST * (1 - progress))
    local lowerOX = seamMode and 0 or (LOWER_SLIDE_DIST * (1 - lowerProgress))
    local overlayAlpha = seamMode and 0 or math.floor(180 * progress)

    -- 箭头切换时不做垂直滑入
    if detailState.switchDir then
        upperOX = 0
        lowerOX = 0
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
    nvgTranslate(vg, upperOX, 0)

    -- 觉醒页由 AwakeningPanel 整页接管，以下 1~7 节/8~17 节全部被其背景遮挡，统一跳过绘制。
    -- 转职页复用属性页背景与角色横滑，只跳过属性区内容。
    local isAwakenTab = (detailState.tab == "awaken")
    local isClassTab = (detailState.tab == "class")
    local stepAngle = math.pi * 2 / 16  -- 16向描边步进角（7节标题/10节等级共用）

    --- 卡面底部信息：等级徽章、战力、职业标。画在卡的局部坐标里，随卡缩放和滑动。
    ---@param id number 英雄 id
    local function drawCardBadges(id)
        local cfg = HC.get(id)
        if not cfg then return end
        local level = heroLevel
        if id ~= heroId then
            local ok, CharacterPanel = pcall(require, "ui.character.panel.CharacterPanel")
            level = (ok and CharacterPanel.getEffectiveLevel and CharacterPanel.getEffectiveLevel(id)) or 1
        end
        local bottomY = CARD.H * 0.5 - CARD.LVL_BOTTOM_UP
        -- 等级徽章（左下）
        local badgeCX = CARD.LVL_BADGE_DX
        drawImageCentered(vg, imgLvlBadge, badgeCX, bottomY, CARD.LVL_BADGE_SIZE, CARD.LVL_BADGE_SIZE, 1.0)
        drawTextStroke(vg, badgeCX, bottomY, tostring(level),
            28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
        -- 战力（底部居中）
        local power = getCachedPower(id)
        local powerStr = tostring(power)
        local POWER_GAP = 4
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        local ptW = nvgTextBounds(vg, 0, 0, powerStr)
        local pcX = -(CARD.POWER_ICON_SIZE + POWER_GAP + ptW) * 0.5
        local powerY = CARD.H * 0.5 - CARD.POWER_BOTTOM_UP
        drawImageCentered(vg, imgPower, pcX + CARD.POWER_ICON_SIZE * 0.5, powerY,
            CARD.POWER_ICON_SIZE, CARD.POWER_ICON_SIZE, 1.0)
        drawTextStroke(vg, pcX + CARD.POWER_ICON_SIZE + POWER_GAP, powerY, powerStr,
            30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 247, 254, 119, 4)
        -- 职业标（右下）
        local iconIdx = CLASS_ICON_MAP[cfg.classId]
        if iconIdx and imgClassIcons[iconIdx] then
            drawImageCentered(vg, imgClassIcons[iconIdx], CARD.TAG_DX, bottomY,
                CARD.TAG_SIZE, CARD.TAG_SIZE, 1.0)
        end
    end

    -- === 1) 背景图（转职页另用觉醒页的整页背景）===
    if not isAwakenTab and not isClassTab then
        nvgSave(vg)
        nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        drawImageCentered(vg, img.detailBg, DT_BG_CX, DT_BG_CY, DT_BG_W, DT_BG_H, 1.0)
        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    -- === 2) [三队并行] 金币/钻石资源栏已移除——货币显示统一在左侧 TopBar ===

    -- === 动态内容开始（箭头切换时水平滑入+淡入） ===
    nvgSave(vg)
    nvgGlobalAlpha(vg, 1)

    if not isAwakenTab and not isClassTab then
    -- === 4) 角色卡片：X 轴排列，绕竖直 Y 轴转向，不做画面旋转 ===
    local function neighborId(dir)
        local roster = CharacterDetailRef and CharacterDetailRef._getHeroRoster and CharacterDetailRef._getHeroRoster()
        if not roster then return nil end
        local cur = nil
        for i, entry in ipairs(roster) do
            if entry.heroId == heroId then cur = i break end
        end
        if not cur then return nil end
        local idx = cur
        for _ = 1, #roster - 1 do
            idx = idx + dir
            if idx < 1 then idx = #roster end
            if idx > #roster then idx = 1 end
            if roster[idx].owned then return roster[idx].heroId end
        end
        return nil
    end
    local function drawCarouselCard(id, slot, alpha)
        if not id or alpha <= 0.01 then return end
        -- 编队页已改头像，不再预热卡图；详情页按需加载，避免卡片空白
        local imgCard = HeroAssetUtil.ensureCard(vg, imgHeroCards, id)
        if (not imgCard or imgCard < 0) and id ~= 1 then
            imgCard = HeroAssetUtil.ensureCard(vg, imgHeroCards, 1)
        end
        if not imgCard or imgCard < 0 then return end
        local slide = detailState.cardDragVisual or 0
        if detailState.switchDir then
            -- 松手时从拖动位置继续滑到中间，不再先跳回 0 再从屏外滑入。
            local from = (detailState.switchDir or 0) + (detailState.switchFrom or 0)
            slide = from * (1 - progress)
        end
        local pos = slot + slide
        local ax = math.min(1, math.abs(pos))
        local scale = CARD.CENTER_SCALE - (CARD.CENTER_SCALE - CARD.SIDE_SCALE) * ax
        local yaw = 1 - (1 - CARD.YAW_SQUASH) * ax
        nvgSave(vg)
        local cardY = CARD.CY - ((detailState.tab == "equip") and 70 or 0)
        nvgTranslate(vg, DT_CARD_CX + pos * CARD.SIDE_DX, cardY)
        nvgScale(vg, scale * yaw, scale)
        nvgGlobalAlpha(vg, alpha * (ax > 0.85 and 0.82 or 1))
        DrawUtil.drawImageCover(vg, imgCard, 0, 0, CARD.W, CARD.H, 1.0)
        drawCardBadges(id)
        nvgRestore(vg)
    end
    if detailState.tab == "attr" or detailState.tab == "class" then
        local leftId = neighborId(-1)
        local rightId = neighborId(1)
        -- 往一侧拖时，再外侧的那张也要在场，否则露出空白。
        local function secondNeighbor(firstId, dir)
            if not firstId then return nil end
            local saved = heroId
            heroId = firstId
            local id = neighborId(dir)
            heroId = saved
            return id
        end
        drawCarouselCard(secondNeighbor(leftId, -1), -2, 1)
        drawCarouselCard(leftId, -1, 1)
        drawCarouselCard(rightId, 1, 1)
        drawCarouselCard(secondNeighbor(rightId, 1), 2, 1)
    end
    drawCarouselCard(heroId, 0, 1)

    if detailState.tab == "equip" then
    -- === 5) 装备槽位 ===
    local equipData = PlayerStore.Get("equipment")
    local heroEquipped = nil
    local heroInventory = nil
    if equipData then
        heroEquipped = equipData.equipped and equipData.equipped[heroId]
        heroInventory = equipData.inventory
    end

    for _, slot in ipairs(DT_SLOTS) do
        -- 配装tab下：选中槽位绘制选中底图
        if slot.slot == detailState.equipSlot and img.slotSelected >= 0 then
            drawImageCentered(vg, img.slotSelected, slot.cx, slot.cy, 234, 234, 1.0)
        end

        local slotImg
        if slot.img == "weapon" then
            slotImg = img.slotWeapon
        elseif slot.img == "offhand" then
            slotImg = img.slotOffhand
        elseif slot.img == "armor" then
            slotImg = img.slotArmor
        elseif slot.img == "helmet" then
            slotImg = img.slotHelmet
        elseif slot.img == "shoes" then
            slotImg = img.slotShoes
        else
            slotImg = img.slotAccessory
        end
        if slotImg and slotImg >= 0 then
            drawImageCentered(vg, slotImg, slot.cx, slot.cy, DT_SLOT_SIZE, DT_SLOT_SIZE, 1.0)
        end

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

            DarkIcon.drawQualityBg(vg, eq, scx, scy, DT_SLOT_SIZE, DT_SLOT_SIZE, 1.0)  -- [暗黑化 P2-A]

            local equipIconImg = CharacterDetailRef._getEquipIcon(equippedEquip.templateId)
            local iconPad = 12
            local iconSize = DT_SLOT_SIZE - iconPad * 2
            if equipIconImg >= 0 then
                DarkIcon.drawIconDark(vg, equipIconImg, scx, scy, iconSize, iconSize, 1.0)  -- [暗黑化 P2-B]
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

            local slotEnhLv = equippedEquip and EquipmentSystem.getAscendLevel(equippedEquip) or 0
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
        else
            -- 空槽：槽位图本身偏浅，再压一层更深的暗影
            local inset = 16
            nvgBeginPath(vg)
            nvgRoundedRect(vg,
                slot.cx - DT_SLOT_SIZE * 0.5 + inset,
                slot.cy - DT_SLOT_SIZE * 0.5 + inset,
                DT_SLOT_SIZE - inset * 2,
                DT_SLOT_SIZE - inset * 2, 18)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 130))
            nvgFill(vg)
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
            if _TM.isActive() then _TM.registerHotspot("equip_slot_weapon", slot.cx, slot.cy, DT_SLOT_SIZE, DT_SLOT_SIZE, "right") end
        end
    end

    -- === 6) 一键卸下 / 一键装备 按钮 ===
    do
        local bx, by = BTN_UNEQUIP_CX - BTN_BATCH_W * 0.5, BTN_UNEQUIP_CY - BTN_BATCH_H * 0.5
        DarkIcon.drawNine(vg, "btn", bx, by, BTN_BATCH_W, BTN_BATCH_H, { accent = "red" })
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(244, 237, 224, 255))
        local _ds1 = BF.begin(vg, "unequip_all", BTN_UNEQUIP_CX, BTN_UNEQUIP_CY, BTN_BATCH_W, BTN_BATCH_H)
        nvgText(vg, BTN_UNEQUIP_CX, BTN_UNEQUIP_CY, I18n.t("unequip_all"), nil)
        BF.finish(vg, _ds1)
    end
    do
        local bx, by = BTN_EQUIP_CX - BTN_BATCH_W * 0.5, BTN_EQUIP_CY - BTN_BATCH_H * 0.5
        DarkIcon.drawNine(vg, "btn", bx, by, BTN_BATCH_W, BTN_BATCH_H, { accent = "green" })
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(244, 237, 224, 255))
        local _ds = BF.begin(vg, "equip_all", BTN_EQUIP_CX, BTN_EQUIP_CY, BTN_BATCH_W, BTN_BATCH_H)
        nvgText(vg, BTN_EQUIP_CX, BTN_EQUIP_CY, I18n.t("equip_all"), nil)
        BF.finish(vg, _ds)
        local _TM = require("systems.TutorialManager")
        if _TM.isActive() then _TM.registerHotspot("equip_btn_auto", BTN_EQUIP_CX, BTN_EQUIP_CY, BTN_BATCH_W, BTN_BATCH_H, "right") end
    end
    end  -- if detailState.tab == "equip"（装备槽与批量按钮）
    end  -- if not isAwakenTab and not isClassTab（4~6 节）

    nvgRestore(vg)  -- 结束动态内容偏移（switchOX/switchAlpha）

    nvgRestore(vg)  -- 结束上半部分偏移

    -- ================== 下半部分（从下方滑入） ==================
    nvgSave(vg)
    nvgTranslate(vg, lowerOX, 0)

    if not isAwakenTab and not isClassTab then
    -- === 6) 角色详情属性背景图（静态，不参与切换动画） ===
    -- 配装页底板及标题整体下移，给上半部装备词条留位置
    if detailState.tab == "equip" then
        nvgTranslate(vg, 0, EQUIP_LOWER_OFFSET)
    end
    -- 配装页分段画底板：保留顶部金属外框 + 下方皮革，跳过图内菱形金饰小横条
    if detailState.tab == "equip" and img.midBg and img.midBg >= 0 then
        local midTop = MID_BG_CY - MID_BG_H * 0.5
        local frameH = 100
        local barEnd = 125
        nvgSave(vg)
        nvgIntersectScissor(vg, 0, midTop, DESIGN_W, frameH)
        drawImageCentered(vg, img.midBg, MID_BG_CX, MID_BG_CY, MID_BG_W, MID_BG_H, 1.0)
        nvgRestore(vg)
        nvgSave(vg)
        nvgIntersectScissor(vg, 0, midTop + barEnd, DESIGN_W, MID_BG_H - barEnd)
        drawImageCentered(vg, img.midBg, MID_BG_CX, MID_BG_CY, MID_BG_W, MID_BG_H, 1.0)
        nvgRestore(vg)
    else
        drawImageCentered(vg, img.midBg, MID_BG_CX, MID_BG_CY, MID_BG_W, MID_BG_H, 1.0)
    end

    -- === 7) 标题：属性页「角色详情」，配装页显示当前部位名 ===
    local titleText = I18n.t("hero_detail")
    if detailState.tab == "equip" then
        local slotKey = "slot_" .. tostring(detailState.equipSlot or "weapon")
        local slotName = I18n.t(slotKey)
        titleText = (slotName ~= slotKey) and slotName or "主武器"
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local titleSW = 4
    nvgFillColor(vg, nvgRGBA(0x23, 0x23, 0x23, 255))
    for i = 0, 15 do
        local a = i * stepAngle
        nvgText(vg, MID_TITLE_CX + math.cos(a) * titleSW, MID_TITLE_CY + math.sin(a) * titleSW, titleText, nil)
    end
    nvgFillColor(vg, nvgRGBA(0xf7, 0xfe, 0x77, 255))
    nvgText(vg, MID_TITLE_CX, MID_TITLE_CY, titleText, nil)
    end  -- if not isAwakenTab and not isClassTab（6b~7 节）

    if detailState.tab == "equip" then
        nvgTranslate(vg, 0, -EQUIP_LOWER_OFFSET)
    end

    -- 转职页背景不参与角色切换淡入，换角色时保持不动
    if detailState.tab == "class" then
        local ClassChange = require("ui.church.ChurchClassChange")
        ClassChange.init(vg)
        ClassChange.drawBg(vg)
    end

    -- === 下方文本：原地交叉淡化。旧文本由 drawLowerText 末尾重绘模糊残影 ===
    local textBlur = detailState.switchDir and (1 - progress) or 0
    nvgSave(vg)
    nvgGlobalAlpha(vg, 1 - textBlur * 0.55)
    if not isAwakenTab and not isClassTab and detailState.tab ~= "equip" then
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xF4, 0xED, 0xE0, 255))
    nvgText(vg, MID_NAME_CX, MID_NAME_CY, heroCfg.name, nil)
    end

    -- === 9~17) 经验/品质/职业/分割线：属性页专属 ===
    if detailState.tab == "attr" then

    -- === 9) 大经验条 ===
    drawImageCentered(vg, img.midExpBg, MID_EXP_CX, MID_EXP_CY, MID_EXP_W, MID_EXP_H, 1.0)
    local midExpProgress = (maxExp > 0) and (exp / maxExp) or 0
    midExpProgress = math.max(0, math.min(1, midExpProgress))
    local meFillW = MID_EXP_W - MID_EXP_PADDING * 2
    local meFillH = MID_EXP_H - MID_EXP_PADDING * 2
    local meFillX = MID_EXP_CX - MID_EXP_W * 0.5 + MID_EXP_PADDING
    local meFillY = MID_EXP_CY - MID_EXP_H * 0.5 + MID_EXP_PADDING
    local meClipW = meFillW * midExpProgress
    if meClipW > 0 then
        nvgSave(vg)
        nvgScissor(vg, meFillX, meFillY, meClipW, meFillH)
        -- [配色] 经验条填充=金色竖向渐变（暗金主题；原青色贴图 tint 为乘法会偏绿，弃用）
        local grad = nvgLinearGradient(vg, meFillX, meFillY, meFillX, meFillY + meFillH,
            nvgRGBA(255, 226, 140, 255), nvgRGBA(196, 148, 44, 255))
        nvgBeginPath(vg)
        nvgRect(vg, meFillX, meFillY, meFillW, meFillH)
        nvgFillPaint(vg, grad)
        nvgFill(vg)
        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    -- === 10) 等级文本 + 当前经验/目标经验 ===
    local curExp = math.floor(exp or 0)
    local needExp = math.floor(maxExp or 0)
    local lvlText = "Lv." .. tostring(heroLevel) .. "  " .. tostring(curExp) .. "/" .. tostring(needExp)
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

    -- === 14) 职业内容背景框（品质行已去掉，职业条居中拉满） ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        MID_CLASS_BOX_CX - MID_CLASS_BOX_W * 0.5,
        MID_CLASS_BOX_CY - MID_CLASS_BOX_H * 0.5,
        MID_CLASS_BOX_W, MID_CLASS_BOX_H, 20)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)

    -- === 15) 职业图标 + 名称，整条居中 ===
    local classCfg = CC.get(heroCfg.classId)
    local className = classCfg and classCfg.name or "未知"
    local classIconIdx = CLASS_ICON_MAP[heroCfg.classId]
    local classIcon = classIconIdx and imgClassIcons[classIconIdx] or -1

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 34)
    local classTextW = nvgTextBounds(vg, 0, 0, className)
    local classGap = 8
    local iconW = classIcon >= 0 and MID_CLASS_ICON_SIZE or 0
    local comboW = iconW + (iconW > 0 and classGap or 0) + classTextW
    local comboLeftX = MID_CLASS_BOX_CX - comboW * 0.5
    local classIconCX = comboLeftX + iconW * 0.5
    local classTextX = comboLeftX + iconW + (iconW > 0 and classGap or 0) + classTextW * 0.5

    if classIcon >= 0 then
        drawImageCentered(vg, classIcon, classIconCX, MID_CLASS_LABEL_Y,
            MID_CLASS_ICON_SIZE, MID_CLASS_ICON_SIZE, 1.0)
    end
    drawTextStroke(vg, classTextX, MID_CLASS_LABEL_Y, className,
        34, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
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

    elseif detailState.tab == "class" then
        -- 转职页（从教堂迁入，整页接管）
        local ClassChange = require("ui.church.ChurchClassChange")
        ClassChange.init(vg)
        ClassChange.setHero(heroId)
        ClassChange.drawContent(vg)

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
    -- 左列防御、右列攻击都要显示，按行交错排进同一条滚动列表。
    local attrRows = {}
    local rowCount = math.max(#leftAttrs, #rightAttrs)
    for i = 1, rowCount do
        if leftAttrs[i] then attrRows[#attrRows + 1] = leftAttrs[i] end
        if rightAttrs[i] then attrRows[#attrRows + 1] = rightAttrs[i] end
    end
    local totalRows = #attrRows

    detailState.cachedLeft  = attrRows
    detailState.cachedRight = {}

    local attrClipY = ATTR_CLIP_TOP
    local attrClipH = ATTR_CLIP_HEIGHT

    local rowStep = ATTR_BOX_H + ATTR_ROW_GAP
    local contentBottom = ATTR_FIRST_ROW_Y + math.max(0, totalRows - 1) * rowStep + ATTR_BOX_H * 0.5
    local viewBottom = attrClipY + attrClipH
    detailState.attrScrollMax = math.max(0, contentBottom - viewBottom)

    nvgSave(vg)
    nvgScissor(vg, 0, attrClipY, 560, attrClipH)

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
                nvgFillColor(vg, nvgRGBA(0xE8, 0xDC, 0xC8, 255))
                nvgText(vg, ATTR_NAME_LEFT_X, rowY, attr.name, nil)

                drawTextStroke(vg, ATTR_VAL_RIGHT_X, rowY, attr.value,
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
    -- ===                  六围雷达图                                ===
    -- ================================================================

    local statValues = attrData.stats
    local statByKey = {}
    for _, st in ipairs(STAT_LAYOUT) do
        statByKey[st.key] = st
    end

    local function hexPoint(i, radius)
        local ang = -math.pi * 0.5 + (i - 1) * (math.pi / 3)
        return HEX_CX + math.cos(ang) * radius, HEX_CY + math.sin(ang) * radius
    end

    local function strokeDashed(x1, y1, x2, y2, dash, gap)
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        if len <= 0 then return end
        local ux, uy = dx / len, dy / len
        local pos = 0
        while pos < len do
            local seg = math.min(dash, len - pos)
            nvgBeginPath(vg)
            nvgMoveTo(vg, x1 + ux * pos, y1 + uy * pos)
            nvgLineTo(vg, x1 + ux * (pos + seg), y1 + uy * (pos + seg))
            nvgStroke(vg)
            pos = pos + dash + gap
        end
    end

    -- 满格跟当前六维走：取六项最大值再留 25% 空，主属性接近外圈，弱项明显内收。
    local hexPeak = 1
    for _, item in pairs(statByKey) do
        local val = statValues[item.key] or 0
        if val > hexPeak then hexPeak = val end
    end
    local hexMax = math.max(8, hexPeak / 0.82)

    nvgBeginPath(vg)
    nvgCircle(vg, HEX_CX, HEX_CY, HEX_LABEL_R + 28)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)

    -- 外圈实线，内两圈虚线
    for ring = 1, 3 do
        local rr = HEX_R * ring / 3
        nvgStrokeColor(vg, nvgRGBA(0xA9, 0xA0, 0x8F, ring == 3 and 170 or 110))
        nvgStrokeWidth(vg, ring == 3 and 2 or 1.5)
        local pts = {}
        for i = 1, 6 do
            pts[i] = { hexPoint(i, rr) }
        end
        for i = 1, 6 do
            local a = pts[i]
            local b = pts[i % 6 + 1]
            if ring == 3 then
                nvgBeginPath(vg)
                nvgMoveTo(vg, a[1], a[2])
                nvgLineTo(vg, b[1], b[2])
                nvgStroke(vg)
            else
                strokeDashed(a[1], a[2], b[1], b[2], 7, 5)
            end
        end
    end

    -- 六条轴线用虚线
    nvgStrokeColor(vg, nvgRGBA(0xA9, 0xA0, 0x8F, 120))
    nvgStrokeWidth(vg, 1.5)
    for i = 1, 6 do
        local x, y = hexPoint(i, HEX_R)
        strokeDashed(HEX_CX, HEX_CY, x, y, 6, 5)
    end

    nvgBeginPath(vg)
    for i, name in ipairs(HEX_NAMES) do
        local stFill = nil
        for _, item in pairs(statByKey) do
            if item.name == name then stFill = item break end
        end
        local val = stFill and statValues[stFill.key] or 0
        local ratio = val / hexMax
        if ratio < 0.08 then ratio = 0.08 end
        if ratio > 1 then ratio = 1 end
        local x, y = hexPoint(i, HEX_R * ratio)
        if i == 1 then nvgMoveTo(vg, x, y) else nvgLineTo(vg, x, y) end
    end
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(0xC4, 0x8A, 0x3A, 70))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(0xE8, 0xDC, 0xC8, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgCircle(vg, HEX_CX, HEX_CY, 5)
    nvgFillColor(vg, nvgRGBA(0xFF, 0xF4, 0xD6, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, HEX_CX, HEX_CY, 5)
    nvgStrokeColor(vg, nvgRGBA(0xC4, 0x8A, 0x3A, 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for i, name in ipairs(HEX_NAMES) do
        local st = nil
        for _, item in pairs(statByKey) do
            if item.name == name then st = item break end
        end
        local color = HEX_COLORS[name] or { 0xE8, 0xDC, 0xC8 }
        local lx, ly = hexPoint(i, HEX_LABEL_R)
        nvgFontSize(vg, 26)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 255))
        nvgText(vg, lx, ly - 24, st and st.name or "", nil)
        drawTextStroke(vg, lx, ly + 16, tostring(st and statValues[st.key] or 0),
            34, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            color[1], color[2], color[3], 3)
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
    drawTextStroke(vg, TALENT_TEXT_LEFT, TALENT_NAME_Y, talentName .. "：",
        40, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        0x66, 0xf8, 0x62, 5)

    local talentDesc = heroCfg.talentDesc or ""
    local extraLine = ETS.getDesc(heroId, ownData and ownData.extraTalent)
    if extraLine ~= "" then
        talentDesc = talentDesc .. "\n" .. extraLine
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, extraLine ~= "" and 28 or 34)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(0xE8, 0xDC, 0xC8, 255))
    nvgTextBox(vg, TALENT_TEXT_LEFT, TALENT_TEXT_TOP, TALENT_TEXT_WIDTH, talentDesc, nil)

    end -- if detailState.tab == "awaken" / "attr"

    nvgRestore(vg)
    if textBlur > 0.04 and detailState.prevHeroId and detailState.tab == "attr" then
        local savedId = detailState.heroId
        local savedCfg = heroCfg
        local savedLevel = heroLevel
        local savedExp = exp
        local savedMax = maxExp
        local savedOwn = ownData
        detailState.heroId = detailState.prevHeroId
        heroCfg = HC.get(detailState.prevHeroId) or heroCfg
        ownData = getOwnedData and getOwnedData(detailState.prevHeroId) or nil
        heroLevel = ownData and ownData.level or 1
        exp = ownData and ownData.exp or 0
        maxExp = ownData and ownData.maxExp or ExpTable.getHeroExpForLevel(heroLevel) or 5
        for pass = -2, 2 do
            nvgSave(vg)
            nvgTranslate(vg, pass * 3 * textBlur, 0)
            nvgGlobalAlpha(vg, textBlur * 0.16)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 42)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(244, 237, 224, 255))
            nvgText(vg, MID_NAME_CX, MID_NAME_CY, heroCfg.name or "", nil)
            nvgFontSize(vg, 28)
            nvgText(vg, MID_EXP_CX, MID_EXP_CY, "Lv." .. tostring(heroLevel), nil)
            nvgRestore(vg)
        end
        detailState.heroId = savedId
        heroCfg = savedCfg
        heroLevel = savedLevel
        exp = savedExp
        maxExp = savedMax
        ownData = savedOwn
    end

    -- ================================================================
    -- ===              底部按钮区域（静态，不参与切换动画）          ===
    -- ================================================================

    -- 三行模式返回键由中缝层绘制，页面内不再重复画
    ---@diagnostic disable-next-line: undefined-global
    if not H_SEAM_BACK then
        DrawUtil.drawBackChevron(vg, BTN_BACK_CX, BTN_BACK_CY, BTN_BACK_W, BTN_BACK_H, "right")
    end

    drawImageCentered(vg, img.tabBg, BTN_TAB_BG_CX, BTN_TAB_BG_CY, BTN_TAB_BG_W, BTN_TAB_BG_H, 1.0)

    local TAB_CX_MAP = { attr = BTN_TAB_ATTR_CX, equip = BTN_TAB_EQUIP_CX, class = BTN_TAB_CLASS_CX, awaken = BTN_TAB_AWAKEN_CX }
    local targetCX = TAB_CX_MAP[detailState.tab] or BTN_TAB_ATTR_CX
    local fromCX   = TAB_CX_MAP[detailState.tabFrom] or BTN_TAB_ATTR_CX
    local tabElapsed = time.elapsedTime - detailState.tabSwitchTime
    local tabT = math.min(1.0, tabElapsed / TAB_ANIM_DURATION)
    local tabEased = easeOutCubic(tabT)
    local sliderCX = fromCX + (targetCX - fromCX) * tabEased
    local sliderCY = BTN_TAB_BG_CY
    DarkIcon.drawNine(vg, "btn", sliderCX - BTN_TAB_SLIDER_W * 0.5, sliderCY - BTN_TAB_SLIDER_H * 0.5, BTN_TAB_SLIDER_W, BTN_TAB_SLIDER_H, { accent = "gold" })

    -- Tab 文字绘制（3个Tab）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 40)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- [fix] 选中态文字画在 DarkIcon btn 深色滑块上，深棕不可读 → 改骨白（DarkIcon 铭刻色）
    local activeColor   = nvgRGBA(0xD8, 0xC9, 0xA3, 255)
    local inactiveColor = nvgRGBA(255, 255, 255, 255)
    local curTab = detailState.tab

    nvgFillColor(vg, curTab == "attr" and activeColor or inactiveColor)
    nvgText(vg, TEXT_ATTR_CX, TEXT_ATTR_CY, I18n.t("tab_attr"), nil)

    nvgFillColor(vg, curTab == "equip" and activeColor or inactiveColor)
    nvgText(vg, TEXT_EQUIP_CX, TEXT_EQUIP_CY, I18n.t("tab_equip"), nil)

    nvgFillColor(vg, curTab == "class" and activeColor or inactiveColor)
    nvgText(vg, TEXT_CLASS_CX, TEXT_CLASS_CY, I18n.t("tab_class"), nil)

    -- 转职Tab角标：当前英雄可转职时显示红点
    do
        local okBadge, ChurchPage = pcall(require, "ui.church.ChurchPage")
        if okBadge and ChurchPage.hasAdvanceForHero and ChurchPage.hasAdvanceForHero(heroId) then
            nvgBeginPath(vg)
            nvgCircle(vg, TEXT_CLASS_CX + 42, TEXT_CLASS_CY - 20, 9)
            nvgFillColor(vg, nvgRGBA(0xE2, 0x3A, 0x2E, 255))
            nvgFill(vg)
        end
    end

    nvgFillColor(vg, curTab == "awaken" and activeColor or inactiveColor)
    nvgText(vg, TEXT_AWAKEN_CX, TEXT_AWAKEN_CY, I18n.t("tab_awaken"), nil)

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
        local TIP_MAX_W   = 546
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

    -- === 转职页角色横滑重绘在转职树之上，避免被职业图标盖住 ===
    if detailState.tab == "class" then
        local function neighborId(dir)
            local roster = CharacterDetailRef and CharacterDetailRef._getHeroRoster and CharacterDetailRef._getHeroRoster()
            if not roster then return nil end
            local cur = nil
            for i, entry in ipairs(roster) do
                if entry.heroId == heroId then cur = i break end
            end
            if not cur then return nil end
            local idx = cur
            for _ = 1, #roster - 1 do
                idx = idx + dir
                if idx < 1 then idx = #roster end
                if idx > #roster then idx = 1 end
                if roster[idx].owned then return roster[idx].heroId end
            end
            return nil
        end
        local function drawCarouselCard(id, slot, alpha)
            if not id or alpha <= 0.01 then return end
            local imgCard = HeroAssetUtil.ensureCard(vg, imgHeroCards, id)
            if (not imgCard or imgCard < 0) and id ~= 1 then
                imgCard = HeroAssetUtil.ensureCard(vg, imgHeroCards, 1)
            end
            if not imgCard or imgCard < 0 then return end
            local slide = detailState.cardDragVisual or 0
            if detailState.switchDir then
                local from = (detailState.switchDir or 0) + (detailState.switchFrom or 0)
                slide = from * (1 - progress)
            end
            local pos = slot + slide
            local ax = math.min(1, math.abs(pos))
            local scale = CARD.CENTER_SCALE - (CARD.CENTER_SCALE - CARD.SIDE_SCALE) * ax
            local yaw = 1 - (1 - CARD.YAW_SQUASH) * ax
            nvgSave(vg)
            nvgTranslate(vg, DT_CARD_CX + pos * CARD.SIDE_DX, CARD.CY)
            nvgScale(vg, scale * yaw, scale)
            nvgGlobalAlpha(vg, alpha * (ax > 0.85 and 0.82 or 1))
            DrawUtil.drawImageCover(vg, imgCard, 0, 0, CARD.W, CARD.H, 1.0)
            drawCardBadges(id)
            nvgRestore(vg)
        end
        local leftId = neighborId(-1)
        local rightId = neighborId(1)
        local function secondNeighbor(firstId, dir)
            if not firstId then return nil end
            local saved = heroId
            heroId = firstId
            local id = neighborId(dir)
            heroId = saved
            return id
        end
        drawCarouselCard(secondNeighbor(leftId, -1), -2, 1)
        drawCarouselCard(leftId, -1, 1)
        drawCarouselCard(rightId, 1, 1)
        drawCarouselCard(secondNeighbor(rightId, 1), 2, 1)
        drawCarouselCard(heroId, 0, 1)
    end

    -- === 转职确认/重置弹窗、飘字与转职 Spine 特效（转职页最上层）===
    if detailState.tab == "class" then
        local ClassChange = require("ui.church.ChurchClassChange")
        ClassChange.drawConfirmPopup(vg)
        ClassChange.drawResetConfirmPopup(vg)
        ClassChange.drawFloatText(vg)
        require("ui.fx.SpineCardEffect").draw(vg, "church")
    end

    -- === 装备背包覆盖层 ===
    EquipmentBag.draw(vg)

    -- === 套装详情浮层，盖住底部页签 ===
    if detailState.tab == "equip" and CharacterDetailRef and CharacterDetailRef._EquipPanel
        and CharacterDetailRef._EquipPanel.drawSetCodex then
        CharacterDetailRef._EquipPanel.drawSetCodex(vg)
    end

    -- === 装备详情弹窗（配装面板点击时显示）===
    if not EquipmentBag.isOpen() then
        local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
        if EquipmentDetail.isOpen() then
            EquipmentDetail.drawIf(vg, "character")
        end
    end

    -- 配装页角色名画在详情之上，随下方界面一同下移
    if not isAwakenTab and detailState.tab == "equip" and heroCfg and heroCfg.name then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xF4, 0xED, 0xE0, 255))
        nvgText(vg, MID_NAME_CX, MID_NAME_CY + EQUIP_LOWER_OFFSET, heroCfg.name, nil)
    end
end

return M
