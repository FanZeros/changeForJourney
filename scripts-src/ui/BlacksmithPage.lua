-- ============================================================================
-- BlacksmithPage - 铁匠铺界面
-- 从城镇页面点击铁匠铺进入的二级界面
-- 职责：铁匠铺常规 UI（背景、装备槽、分解/洗练/强化切换）
-- 子模块：BlacksmithEnhance / BlacksmithRefine / BlacksmithDecompose
-- ============================================================================

local GameConfig       = require("config.GameConfig")
local GameState        = require("core.GameState")
local EquipmentBag     = require("ui.EquipmentBag")
local EquipmentDetail  = require("ui.EquipmentDetail")
local EquipmentConfig  = require("config.EquipmentConfig")
local AffixConfig      = require("config.AffixConfig")
local AD               = require("systems.AttributeDef")
local ClientDispatcher = require("network.ClientDispatcher")
local PlayerStore      = require("client.data.PlayerStore")
local EquipmentSystem  = require("systems.EquipmentSystem")
local RewardPopup      = require("ui.RewardPopup")
local SpineResultEffect = require("ui.SpineResultEffect")
local DrawUtil         = require("core.DrawUtil")
local HeroAssetUtil    = require("config.HeroAssetUtil")
local CharacterPanel   = require("ui.CharacterPanel")
local HeroConfig       = require("config.HeroConfig")
local ExpTable         = require("config.ExpTable")

-- 子模块
local BlacksmithEnhance   = require("ui.BlacksmithEnhance")
local BlacksmithRefine    = require("ui.BlacksmithRefine")
local BlacksmithDecompose = require("ui.BlacksmithDecompose")

-- 延迟加载网络模块（避免循环依赖）
local Client_
local Protocol_
local function getClient()
    if not Client_ then Client_ = require("network.Client") end
    return Client_
end
local function getProtocol()
    if not Protocol_ then Protocol_ = require("shared.Protocol") end
    return Protocol_
end

local BlacksmithPage = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 1. 铁匠铺背景图
local BG_CX, BG_CY = 540, 453
local BG_W, BG_H   = 1278, 1050

-- 2. 铁匠铺名称背景（中心点坐标）
local NAME_BG_CX, NAME_BG_CY = 147, 136
local NAME_BG_W, NAME_BG_H   = 294, 123

-- 3. 文本"铁匠铺"（中心点坐标）
local NAME_TEXT_CX, NAME_TEXT_CY = 173, 130
local NAME_FONT_SIZE              = 50

-- 4. 编队卡片区域（从 CharacterPanel 搬来，Y 轴改为 449）
local CARD_W        = 198
local CARD_H        = 438
local CARD_SPACING  = 7
local CARD_CY       = 449   -- 卡片 Y 中心（计划书指定）
local MAX_PARTY     = 5     -- 编队最多 5 个槽位

-- 卡片内部偏移（参考 CharacterPanelDraw）
local CARD_TAG_OFFSET_Y  = -215
local CARD_TAG_SIZE      = 60
local CARD_NAME_BG_DY    = 253
local CARD_NAME_BG_W     = 193
local CARD_NAME_BG_H     = 48
local CARD_NAME_BG_RADIUS = 24
local CARD_LVL_BADGE_DX  = -63
local CARD_LVL_BADGE_DY  = 181
local CARD_LVL_BADGE_SIZE = 56
local CARD_EXP_BAR_DX    = 12
local CARD_EXP_BAR_DY    = 183
local CARD_EXP_BAR_BG_W  = 148
local CARD_EXP_BAR_BG_H  = 28
local CARD_EXP_BAR_PAD   = 4
local CARD_EXP_FILL_LEFT  = CARD_EXP_BAR_PAD  -- 与 PAD 保持一致，四边均为 4px
local CARD_POWER_Y        = 585   -- CARD_CY(449) + 偏移(136)，与 CharacterPanelDraw 中 POWER_Y(680)-CARD_CY(544)=136 一致
local CARD_POWER_ICON_SIZE = 36
local CARD_LOCK_ICON_SIZE  = 64
local CARD_PLUS_ICON_SIZE  = 64

-- 5. 装备槽位区域（4 个装备槽，在卡片下方）
local EQUIP_SLOT_FIRST_X = 227  -- 第一个槽位中心 X
local EQUIP_SLOT_Y       = 967  -- 槽位中心 Y
local EQUIP_SLOT_SIZE    = 160  -- 槽位尺寸
local EQUIP_SLOT_SPACING = 49   -- 槽位间距
local EQUIP_SLOT_RADIUS  = 24
local EQUIP_LV_X_OFFSET  = 3   -- 强化等级文本相对槽位中心的 X 偏移（230-227=3）
local EQUIP_LV_Y_OFFSET  = -78 -- 强化等级文本相对槽位中心的 Y 偏移（889-967=-78）
local EQUIP_LV_FONT_SIZE = 38
local EQUIP_SLOT_ORDER   = { "weapon", "offhand", "armor", "accessory" }

-- 7. 下方背景板
local LOWER_BG_CX, LOWER_BG_W, LOWER_BG_H = 540, 1080, 1670
-- Y 最下方与屏幕最下方对齐 -> cy = DESIGN_H - H/2
local LOWER_BG_CY = DESIGN_H - LOWER_BG_H * 0.5  -- 2400 - 835 = 1565

-- 8. 返回按钮（与角色详情界面完全一致）
local BTN_BACK_CX, BTN_BACK_CY = 122, 2308
local BTN_BACK_W, BTN_BACK_H   = 184, 143

-- 9. 页面选项滑块背景（与角色界面完全一致）
local TAB_BG_CX, TAB_BG_CY = 639, 2308
local TAB_BG_W, TAB_BG_H   = 810, 143

-- 10. 三个滑块按钮位置（Y 与 tab 背景一致 = 2308，参考 CharacterDetail）
local TAB_ITEMS = {
    { name = "强化", cx = 372, cy = 2308 },
    { name = "洗练", cx = 638, cy = 2308 },
    { name = "分解", cx = 905, cy = 2308 },
}

-- 11. 滑块按钮（九宫格）
local SLIDER_W, SLIDER_H = 277, 143
local SLIDER_DEFAULT_CX   = 905   -- 默认在强化位置
local SLIDER_DEFAULT_CY   = 2308
-- 九宫格 inset: 上10 下10 左70 右70
local SLIDER_INSET_TOP    = 10
local SLIDER_INSET_BOTTOM = 10
local SLIDER_INSET_LEFT   = 70
local SLIDER_INSET_RIGHT  = 70

-- Tab 文本样式
local TAB_TEXT_Y          = 2302
local TAB_FONT_SIZE       = 40
local TAB_ACTIVE_R, TAB_ACTIVE_G, TAB_ACTIVE_B = 0x81, 0x57, 0x3c
local TAB_INACTIVE_R, TAB_INACTIVE_G, TAB_INACTIVE_B = 255, 255, 255

-- 动画
local TAB_ANIM_DURATION   = 0.35  -- Tab 切换动画时长
local ANIM_DURATION       = 0.45  -- 打开动画时长
local CLOSE_ANIM_DURATION = 0.38  -- 关闭动画时长
local UPPER_SLIDE_DIST    = 1200  -- 上半部分滑入距离
local LOWER_SLIDE_DIST    = 1600  -- 下半部分滑入距离

-- ======================== 状态 ========================

local onCloseCallback_ = nil  -- 关闭动画完成后的回调（用于触发离场情景）
local onOpenCallback_  = nil  -- 打开动画完成后的回调（用于触发入场情景）

local state = {
    open       = false,
    closing    = false,
    openTime   = 0,
    closeTime  = 0,
    -- 当前选中 Tab: "fenjie" | "xilian" | "qianghua"
    tab        = "qianghua",
    tabFrom    = "qianghua",
    tabSwitchTime = 0,
    -- 编队/装备槽选择
    selectedPartySlot = 1,           -- 当前选中的编队槽位索引 (1~5)
    selectedEquipSlot = "weapon",    -- 当前选中的装备槽位 key
    -- 已选装备（由 partySlot + equipSlot 自动推导）
    selectedEquip = nil,
    -- 洗练缓存：服务端返回的新词缀（用于"替换"按钮）
    pendingRefineAffixes = nil,   -- table[] | nil
    pendingRefineSeq     = nil,   -- number | nil (对应装备 seq)
}

-- Tab 对应的标签项索引
local TAB_MAP = {
    qianghua = 1,
    xilian   = 2,
    fenjie   = 3,
}

-- ======================== 强化等级配置（来自 建筑-铁匠铺.txt）========================

local ENHANCE_TABLE = {
    --  lv  costMult  successRate  degradeRate  destroyRate  attrBoost
    {  1,  1.0,  1.00, 0.00, 0.00, 0.20 },
    {  2,  1.5,  0.95, 0.00, 0.00, 0.40 },
    {  3,  2.0,  0.90, 0.00, 0.00, 0.60 },
    {  4,  2.5,  0.85, 0.00, 0.00, 0.80 },
    {  5,  3.0,  0.80, 0.00, 0.00, 1.00 },
    {  6,  3.5,  0.75, 0.00, 0.00, 1.20 },
    {  7,  4.0,  0.70, 0.05, 0.00, 1.40 },
    {  8,  4.5,  0.65, 0.10, 0.00, 1.60 },
    {  9,  5.0,  0.60, 0.15, 0.00, 1.80 },
    { 10,  5.5,  0.55, 0.20, 0.00, 2.00 },
    { 11,  6.0,  0.50, 0.25, 0.05, 2.20 },
    { 12,  6.5,  0.45, 0.30, 0.10, 2.40 },
    { 13,  7.5,  0.40, 0.35, 0.15, 2.60 },
    { 14,  8.5,  0.35, 0.40, 0.20, 2.80 },
    { 15,  9.5,  0.30, 0.45, 0.25, 3.00 },
    { 16, 10.5,  0.25, 0.50, 0.25, 3.20 },
}

-- 装备品质消耗配置（用于洗练/分解）
-- decBase/decScale: 分解精粹奖励基础与等级缩放
-- refBase/refInc/refLvScale: 洗练精粹消耗基础、递增、等级缩放
local QUALITY_COST = require("config.BlacksmithConfig").QUALITY_COST

-- ======================== 装备图标缓存 ========================

local equipIconCache = {}  -- [templateId] = nvgImage handle
local equipIconVg = nil    -- 缓存 vg 上下文

local function getEquipIconCached(templateId)
    if not templateId then return -1 end
    local cached = equipIconCache[templateId]
    if cached then return cached end
    if not equipIconVg then return -1 end
    local path = EquipmentConfig.getIconPath(templateId)
    local img = nvgCreateImage(equipIconVg, path, 0)
    equipIconCache[templateId] = img
    return img
end

-- ======================== 词缀值格式化 ========================

--- 大数值缩写（超过4位数用 K/M 等单位）
local function formatCompact(n)
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 10000 then
        return string.format("%.1fK", n / 1000)
    else
        return tostring(n)
    end
end

local EquipmentSystem = require("systems.EquipmentSystem")

local function formatAffixValue(key, value, affixId)
    local numeric = EquipmentSystem.normalizeAffixNumericValue(value)
    if numeric == nil then
        if affixId then
            local tpl = AffixConfig.BY_ID[tonumber(affixId) or affixId]
            if tpl and tpl.key then
                key = key or tpl.key
            end
        end
        return "?"
    end

    local meta = key and AD.META[key]
    local tpl = (not meta and affixId) and AffixConfig.BY_ID[tonumber(affixId) or affixId]
    local dataType = meta and meta.dataType
    if not dataType and tpl then
        if tpl.dataType == "pct" then
            dataType = AD.TYPE_PCT
        elseif tpl.dataType == "int" then
            dataType = AD.TYPE_INT
        end
    end

    if dataType == AD.TYPE_PCT then
        return string.format("%.1f%%", numeric)
    elseif dataType == AD.TYPE_INT then
        return string.format("%.0f", numeric)
    else
        return string.format("%.1f", numeric)
    end
end

-- ======================== 图片句柄（共享） ========================

local imgBg       = -1   -- UI_TJP_CH_1.png
local imgNameBg   = -1   -- UI_TJP_MC.png
local imgPlus     = -1   -- UI_ICON_TJP_JIA.png
local imgLowerBg  = -1   -- UI_TJP_1.png
local imgBtnBack  = -1   -- UI_AN_FH.png
local imgTabBg    = -1   -- UI_AN_1.png
local imgSlider   = -1   -- UI_AN_2.png
local imgArrow    = -1   -- UI_TJP_JIANTOU.png（提升箭头）
local imgEnhBtn   = -1   -- UI_AN_LV.png（强化按钮背景）
local imgGoldIcon = -1   -- UI_icon_JB.png（金币图标）
local imgGoldQBg  = -1   -- UI_icon_ZBBJ_2.png（金币品质背景框, quality=2）
local imgEssenceIcon = -1 -- UI_icon_JC.png（精粹图标）
local imgXlBefore  = -1   -- UI_TJP_XL_2.png（洗练前背景框）
local imgXlAfter   = -1   -- UI_TJP_XL_1.png（洗练后背景框）
local imgReplaceBtn = -1  -- UI_AN_HUANG.png（替换按钮背景）
local imgCheckmark = -1   -- UI_icon_GOU.png（选中打钩）
local imgLvlBadge  = -1   -- UI_JSJM_DJ.png（等级徽章）
local imgRedDot    = -1   -- ICON_HD.png（红点图标）
local imgIconUp    = -1   -- ICON_UP.png（可强化角标）
-- 一键强化确认弹窗专用图片
local imgEnhDlgBg    = -1  -- UI_TY_EJQRK.png（弹窗背景）
local imgEnhDlgMinus = -1  -- UI_AN_JIAN.png（减按钮）
local imgEnhDlgPlus  = -1  -- UI_AN_JIA.png（加按钮）

-- ======================== 编队卡片图片 ========================
local imgHeroCards  = {}  -- [1..15] 英雄卡牌图
local imgClassIcons = {}  -- [1..6] 职业图标
local imgDeployed   = -1  -- 编队已部署标记
local imgLock       = -1  -- 锁定图标
local imgPlusCard   = -1  -- 加号图标（空卡位）
local imgPower      = -1  -- 战力图标
local imgLvlBadgeCard = -1 -- 等级徽章
local imgExpBarBg   = -1  -- 经验条背景
local imgExpBarFill = -1  -- 经验条填充

-- 装备槽位背景图
local imgSlotBg       = {}  -- { weapon=.., offhand=.., armor=.., accessory=.. }
local imgSlotSelected = -1  -- UI_TJPXZTBBJ.png（装备槽选中底图）

-- CLASS_ICON_MAP（与 CharacterPanelDraw 一致）
local CLASS_ICON_MAP = { knight=1, warrior=2, mage=3, ranger=4, assassin=5, priest=6 }

-- ======================== 外部驱动标志 ========================
local decomposeRedDot = false  -- 分解标签红点（背包满时）
local imgQualityBg = {}   -- UI_icon_ZBBJ_1~5（品质背景框，按品质索引）

-- 词缀等级图标 D/C/B/A/S
local imgGrade = {}      -- imgGrade["D"], imgGrade["C"], ...

-- ======================== 缓动函数 ========================

local function easeOutCubic(t)
    t = t - 1
    return t * t * t + 1
end

local function easeInCubic(t)
    return t * t * t
end

local function easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local f = 2 * t - 2
        return 0.5 * f * f * f + 1
    end
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

--- 描边文字
local drawTextStroke = DrawUtil.drawTextStroke

--- 九宫格绘制
local function drawNineSlice(vg, img, dx, dy, dw, dh, iTop, iRight, iBottom, iLeft)
    if img < 0 then return end

    local srcW, srcH = nvgImageSize(vg, img)
    if srcW <= 0 or srcH <= 0 then return end

    local sL, sR, sT, sB = iLeft, iRight, iTop, iBottom
    local sMW = srcW - sL - sR
    local sMH = srcH - sT - sB

    local dL = math.min(iLeft, dw * 0.5)
    local dR = math.min(iRight, dw * 0.5)
    local dT = math.min(iTop, dh * 0.5)
    local dB = math.min(iBottom, dh * 0.5)

    if sMW <= 0 or sMH <= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, img, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, dx, dy, dw, dh)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        return
    end

    local ix0 = math.floor(dx + 0.5)
    local iy0 = math.floor(dy + 0.5)
    local ix1 = math.floor(dx + dL + 0.5)
    local iy1 = math.floor(dy + dT + 0.5)
    local ix2 = math.floor(dx + dw - dR + 0.5)
    local iy2 = math.floor(dy + dh - dB + 0.5)
    local ix3 = math.floor(dx + dw + 0.5)
    local iy3 = math.floor(dy + dh + 0.5)

    local OV = 1
    local patches = {
        { ix1 - OV, iy1 - OV, ix2 - ix1 + OV * 2, iy2 - iy1 + OV * 2, sL, sT, sMW, sMH },
        { ix1 - OV, iy0,      ix2 - ix1 + OV * 2, iy1 - iy0 + OV,     sL,       0,        sMW, sT  },
        { ix1 - OV, iy2 - OV, ix2 - ix1 + OV * 2, iy3 - iy2 + OV,     sL,       sT + sMH, sMW, sB  },
        { ix0,      iy1 - OV, ix1 - ix0 + OV,     iy2 - iy1 + OV * 2, 0,        sT,       sL,  sMH },
        { ix2 - OV, iy1 - OV, ix3 - ix2 + OV,     iy2 - iy1 + OV * 2, sL + sMW, sT,       sR,  sMH },
        { ix0,      iy0,      ix1 - ix0 + OV, iy1 - iy0 + OV, 0,        0,        sL, sT  },
        { ix2 - OV, iy0,      ix3 - ix2 + OV, iy1 - iy0 + OV, sL + sMW, 0,        sR, sT  },
        { ix0,      iy2 - OV, ix1 - ix0 + OV, iy3 - iy2 + OV, 0,        sT + sMH, sL, sB  },
        { ix2 - OV, iy2 - OV, ix3 - ix2 + OV, iy3 - iy2 + OV, sL + sMW, sT + sMH, sR, sB  },
    }

    nvgShapeAntiAlias(vg, 0)
    for _, p in ipairs(patches) do
        local px, py, pw, ph = p[1], p[2], p[3], p[4]
        local sx, sy, sw, sh = p[5], p[6], p[7], p[8]
        if pw > 0 and ph > 0 and sw > 0 and sh > 0 then
            local scaleX = pw / sw
            local scaleY = ph / sh
            local paint = nvgImagePattern(vg,
                px - sx * scaleX,
                py - sy * scaleY,
                srcW * scaleX,
                srcH * scaleY,
                0, img, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, px, py, pw, ph)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    end
    nvgShapeAntiAlias(vg, 1)
end

--- hitTest（中心坐标 + 尺寸）
local function hitTest(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

-- ======================== 编队卡片辅助函数 ========================

--- 计算第 index 个卡片的中心 X 坐标（1-based）
local function getCardSlotCX(index)
    local count = MAX_PARTY
    local totalW = count * CARD_W + (count - 1) * CARD_SPACING
    local startCX = (DESIGN_W - totalW) * 0.5 + CARD_W * 0.5
    return startCX + (index - 1) * (CARD_W + CARD_SPACING)
end

--- 计算第 index 个装备槽的中心 X 坐标（1-based, index=1..4）
local function getEquipSlotCX(index)
    return EQUIP_SLOT_FIRST_X + (index - 1) * (EQUIP_SLOT_SIZE + EQUIP_SLOT_SPACING)
end

--- 根据当前 selectedPartySlot + selectedEquipSlot 自动推导 selectedEquip
local function deriveSelectedEquip()
    local teamSlots = CharacterPanel.getTeamSlotsData()
    if not teamSlots then
        state.selectedEquip = nil
        return
    end
    local slot = teamSlots[state.selectedPartySlot]
    if not slot or slot.state ~= "occupied" or not slot.heroId then
        state.selectedEquip = nil
        BlacksmithEnhance.updateEnhanceData(nil)
        BlacksmithRefine.updateRefineData(nil)
        return
    end
    local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    if not eqData or not eqData.equipped then
        state.selectedEquip = nil
        return
    end
    local heroEquipped = eqData.equipped[tostring(slot.heroId)] or eqData.equipped[slot.heroId]
    if not heroEquipped then
        state.selectedEquip = nil
        BlacksmithEnhance.updateEnhanceData(nil)
        BlacksmithRefine.updateRefineData(nil)
        return
    end
    local seq = heroEquipped[state.selectedEquipSlot]
    if seq and eqData.inventory then
        local equip = eqData.inventory[tostring(seq)]
        if equip then
            state.selectedEquip = equip
            BlacksmithEnhance.updateEnhanceData(equip)
            BlacksmithRefine.updateRefineData(equip)
            return
        end
    end
    -- 双手武器镜像：offhand 无装备时检查 weapon 是否双手
    if state.selectedEquipSlot == "offhand" and eqData.inventory then
        local weaponSeq = heroEquipped["weapon"]
        if weaponSeq then
            local weaponEquip = eqData.inventory[tostring(weaponSeq)]
            if weaponEquip and weaponEquip.grip == "twohand" then
                state.selectedEquip = weaponEquip
                BlacksmithEnhance.updateEnhanceData(weaponEquip)
                BlacksmithRefine.updateRefineData(weaponEquip)
                return
            end
        end
    end
    -- 该槽位无装备
    state.selectedEquip = nil
    BlacksmithEnhance.updateEnhanceData(nil)
    BlacksmithRefine.updateRefineData(nil)
end

-- ======================== 可强化检查（供角标绘制使用） ========================

-- -------- 性能缓存：避免 draw 每帧重复计算 canEnhance --------
local _enhanceCache = {
    dirty = true,
    --- partyCanEnhance[i] = bool  出战位 i 是否有任意槽可强化
    partyCanEnhance = {},
    --- slotCanEnhance[partySlot][equipSlot] = bool
    slotCanEnhance  = {},
}

--- 标记可强化缓存为脏（数据变化时调用）
function BlacksmithPage.markEnhanceDirty()
    _enhanceCache.dirty = true
end

--- 检查指定出战位的指定装备槽位是否满足强化条件
---@param partySlot number 出战位索引 (1~5)
---@param equipSlot string 装备槽位 key ("weapon"|"offhand"|"armor"|"accessory")
---@param slotEnhanceData table|nil 预取的 slotEnhance 数据（可选，避免重复读取）
---@param gold number|nil 预取的金币数量（可选）
---@return boolean
local function canEnhanceSlot(partySlot, equipSlot, slotEnhanceData, gold)
    local BlacksmithConfig = require("config.BlacksmithConfig")
    ---@diagnostic disable-next-line: assign-type-mismatch
    slotEnhanceData = slotEnhanceData or ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
    if not slotEnhanceData or not slotEnhanceData.levels then return false end
    gold = gold or GameState.getGold()

    local partyLevels = slotEnhanceData.levels[tostring(partySlot)]
        or slotEnhanceData.levels[partySlot]
    -- partyLevels 为 nil 表示该出战位从未强化过，所有槽位等级视为 0
    local curLevel = (partyLevels and partyLevels[equipSlot]) or 0
    -- 动态上限 = min(硬上限, 玩家等级限制)
    local maxLv = math.min(BlacksmithConfig.MAX_ENHANCE_LEVEL,
        ExpTable.getEnhanceLevelCap(GameState.getLevel()))
    if curLevel >= maxLv then return false end

    local nextLevel = curLevel + 1
    local cost = BlacksmithConfig.getEnhanceCost(nextLevel)
    if not cost then return false end

    local scrollField = BlacksmithConfig.SLOT_SCROLL_MAP[equipSlot]
    local scrollGetter = scrollField and BlacksmithEnhance.getScrollGetter(scrollField)
    local ownedScroll = 0
    if scrollGetter and GameState[scrollGetter] then
    ---@diagnostic disable-next-line: assign-type-mismatch
        ownedScroll = GameState[scrollGetter]()
    end
    return gold >= cost.gold and ownedScroll >= cost.scroll
end

--- 检查指定出战位是否有任意装备槽位满足强化条件
---@param partySlot number 出战位索引 (1~5)
---@param slotEnhanceData table|nil 预取的 slotEnhance 数据（可选）
---@param gold number|nil 预取的金币数量（可选）
---@return boolean
local function canEnhancePartySlot(partySlot, slotEnhanceData, gold)
    -- 只有已上阵角色的出战位才能强化，空槽位/未解锁槽位不算
    local teamSlots = CharacterPanel.getTeamSlotsData()
    local slot = teamSlots and teamSlots[partySlot]
    if not slot or slot.state ~= "occupied" then return false end

    for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
        if canEnhanceSlot(partySlot, equipSlot, slotEnhanceData, gold) then
            return true
        end
    end
    return false
end

--- 刷新可强化缓存（仅在 dirty 时调用，一次性算完所有槽位）
local function refreshEnhanceCache()
    if not _enhanceCache.dirty then return end
    _enhanceCache.dirty = false

    -- 预取共享数据，避免 canEnhanceSlot 内部重复读取
    local slotEnhanceData = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
    local gold = GameState.getGold()

    for i = 1, MAX_PARTY do
        _enhanceCache.slotCanEnhance[i] = _enhanceCache.slotCanEnhance[i] or {}
        local anyCanEnhance = false
        -- 只有已上阵角色的出战位才能强化
        local teamSlots = CharacterPanel.getTeamSlotsData()
        local slot = teamSlots and teamSlots[i]
        if slot and slot.state == "occupied" then
            for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
                local can = canEnhanceSlot(i, equipSlot, slotEnhanceData, gold)
                _enhanceCache.slotCanEnhance[i][equipSlot] = can
                if can then anyCanEnhance = true end
            end
        else
            for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
                _enhanceCache.slotCanEnhance[i][equipSlot] = false
            end
        end
        _enhanceCache.partyCanEnhance[i] = anyCanEnhance
    end
end

--- 从缓存获取：出战位是否有任意槽可强化（draw 路径用）
local function getCachedPartyCanEnhance(partySlot)
    refreshEnhanceCache()
    return _enhanceCache.partyCanEnhance[partySlot] or false
end

--- 从缓存获取：指定槽位是否可强化（draw 路径用）
local function getCachedSlotCanEnhance(partySlot, equipSlot)
    refreshEnhanceCache()
    local ps = _enhanceCache.slotCanEnhance[partySlot]
    return ps and ps[equipSlot] or false
end

-- ======================== 上半部分绘制 ========================

--- 绘制洗练上半部分（单个装备槽位）
local function drawRefineUpperSlot(vg)
    local equip = state.selectedEquip
    local slotCX, slotCY = 540, 431
    local slotSize = 160

    if equip then
        -- 品质底框 + 装备图标（160x160）
        local qIdx = math.max(1, math.min(6, equip.quality or 1))
        drawImageCentered(vg, imgQualityBg[qIdx], slotCX, slotCY, slotSize, slotSize, 1.0)
        local eqIcon = getEquipIconCached(equip.templateId)
        if eqIcon and eqIcon > 0 then
            drawImageCentered(vg, eqIcon, slotCX, slotCY, slotSize - 16, slotSize - 16, 1.0)
        end

        -- 槽位强化等级（来自 slotEnhance）
        local slotEnhanceData = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
        local enhLv = 0
        if slotEnhanceData and slotEnhanceData.levels then
            local partyLevels = slotEnhanceData.levels[tostring(state.selectedPartySlot)]
                or slotEnhanceData.levels[state.selectedPartySlot]
            if partyLevels then
                enhLv = partyLevels[state.selectedEquipSlot] or 0
            end
        end
        if enhLv > 0 then
            local lvX = slotCX - slotSize * 0.5 + 3
            local lvY = slotCY - slotSize * 0.5 + 22
            drawTextStroke(vg, lvX, lvY, "+" .. enhLv,
                EQUIP_LV_FONT_SIZE, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                0x67, 0xff, 0x75, 5)
        end

        -- 装备等级角标 "Lv.X"（右下角，16方向描边）
        local eqLv = equip.level or 1
        if eqLv >= 1 then
            local lvlText = "Lv." .. eqLv
            local lvlX = slotCX + slotSize * 0.5 - 8
            local lvlY = slotCY + slotSize * 0.5 - 6
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

        -- 装备名称（槽位下方）
        local name = equip.name or ""
        nvgFontFace(vg, "sans")
        drawTextStroke(vg, slotCX, slotCY + slotSize * 0.5 + 30, name,
            36, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)

        -- 选中高亮边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, slotCX - slotSize * 0.5 - 3, slotCY - slotSize * 0.5 - 3,
            slotSize + 6, slotSize + 6, 24)
        nvgStrokeColor(vg, nvgRGBA(0xff, 0xd7, 0x00, 200))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    else
        -- 空状态：纯黑色 80% 不透明度圆角矩形
        nvgBeginPath(vg)
        nvgRoundedRect(vg, slotCX - slotSize * 0.5, slotCY - slotSize * 0.5,
            slotSize, slotSize, 24)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
        nvgFill(vg)

        -- 加号图标
        drawImageCentered(vg, imgPlus, slotCX, slotCY, 64, 64, 0.5)

        -- 提示文本
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 128))
        nvgText(vg, slotCX, slotCY + slotSize * 0.5 + 30, "选择装备进行洗练", nil)
    end
end

--- 绘制上半部分内容（分解 / 洗练 / 强化）
local function drawUpperSlotContent(vg, tabName)
    if tabName == "fenjie" then
        BlacksmithDecompose.drawUpperSlot(vg)
        return
    end

    if tabName == "xilian" then
        drawRefineUpperSlot(vg)
        return
    end

    -- ===== 强化：5 张编队卡片 =====
    local teamSlots, slotPowerCache = CharacterPanel.getTeamSlotsData()
    local playerLevel = GameState.getLevel and GameState.getLevel() or 1

    -- —— 绘制 5 张编队卡片 ——
    for i = 1, MAX_PARTY do
        local cx = getCardSlotCX(i)
        local cy = CARD_CY
        local slotData = teamSlots and teamSlots[i]
        local slotState = slotData and slotData.state or "locked"
        local isSelected = (i == state.selectedPartySlot)

        -- 选中高亮底框
        if isSelected then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - CARD_W * 0.5 - 4, cy - CARD_H * 0.5 - 4,
                CARD_W + 8, CARD_H + 8, 16)
            nvgStrokeColor(vg, nvgRGBA(0xff, 0xd7, 0x00, 200))
            nvgStrokeWidth(vg, 4)
            nvgStroke(vg)
        end

        if slotState == "locked" then
            -- 锁定状态：黑色半透明 + 锁图标 + 解锁提示
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - CARD_W * 0.5, cy - CARD_H * 0.5, CARD_W, CARD_H, 12)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
            nvgFill(vg)
            drawImageCentered(vg, imgLock, cx, cy - 16, CARD_LOCK_ICON_SIZE, CARD_LOCK_ICON_SIZE, 1.0)
            local unlockLv = ExpTable.getSlotUnlockLevel(i)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
            nvgText(vg, cx, cy + 40, "冒险等级" .. unlockLv .. "解锁", nil)

        elseif slotState == "empty" then
            -- 空槽位：黑色半透明 + 加号
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - CARD_W * 0.5, cy - CARD_H * 0.5, CARD_W, CARD_H, 12)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
            nvgFill(vg)
            drawImageCentered(vg, imgPlusCard, cx, cy, CARD_PLUS_ICON_SIZE, CARD_PLUS_ICON_SIZE, 1.0)

        elseif slotState == "occupied" then
            -- 已部署：英雄卡牌背景
            local heroId = slotData.heroId
            local heroInfo = HeroConfig.get(heroId)
            local cardIdx = heroId or 1
            if imgHeroCards[cardIdx] and imgHeroCards[cardIdx] >= 0 then
                drawImageCentered(vg, imgHeroCards[cardIdx], cx, cy, CARD_W, CARD_H, 1.0)
            end

            -- 职业图标（卡片顶部）
            if heroInfo and heroInfo.classId then
                local clsIdx = CLASS_ICON_MAP[heroInfo.classId]
                if clsIdx and imgClassIcons[clsIdx] and imgClassIcons[clsIdx] >= 0 then
                    drawImageCentered(vg, imgClassIcons[clsIdx],
                        cx, cy + CARD_TAG_OFFSET_Y, CARD_TAG_SIZE, CARD_TAG_SIZE, 1.0)
                end
            end

            -- 战力图标 + 数值（与 CharacterPanelDraw 一致）
            local power = slotPowerCache and slotPowerCache[i] or 0
            if power > 0 then
                local powerStr = tostring(math.floor(power))
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 30)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                local pwTextW = nvgTextBounds(vg, 0, 0, powerStr)
                local pwTotalW = CARD_POWER_ICON_SIZE + 4 + pwTextW
                local pwStartX = cx - pwTotalW * 0.5
                drawImageCentered(vg, imgPower,
                    pwStartX + CARD_POWER_ICON_SIZE * 0.5, CARD_POWER_Y,
                    CARD_POWER_ICON_SIZE, CARD_POWER_ICON_SIZE, 1.0)
                local textX = pwStartX + CARD_POWER_ICON_SIZE + 4
                drawTextStroke(vg, textX, CARD_POWER_Y, powerStr,
                    30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                    247, 254, 119, 4)
            end

            -- 经验条背景 + 填充
            local expBarCX = cx + CARD_EXP_BAR_DX
            local expBarCY = cy + CARD_EXP_BAR_DY
            drawImageCentered(vg, imgExpBarBg, expBarCX, expBarCY, CARD_EXP_BAR_BG_W, CARD_EXP_BAR_BG_H, 1.0)
            local exp = slotData.exp or 0
            local maxExp = slotData.maxExp or 1
            local expRatio = math.min(1.0, exp / math.max(1, maxExp))
            if expRatio > 0 then
                local fillMaxW = CARD_EXP_BAR_BG_W - CARD_EXP_BAR_PAD * 2
                local fillW = math.max(1, fillMaxW * expRatio)
                local fillH = CARD_EXP_BAR_BG_H - CARD_EXP_BAR_PAD * 2
                local fillX = expBarCX - CARD_EXP_BAR_BG_W * 0.5 + CARD_EXP_FILL_LEFT
                local fillY = expBarCY - fillH * 0.5
                nvgSave(vg)
                nvgScissor(vg, fillX, fillY, fillW, fillH)
                drawImageCentered(vg, imgExpBarFill, expBarCX, expBarCY, CARD_EXP_BAR_BG_W, CARD_EXP_BAR_BG_H, 1.0)
                nvgResetScissor(vg)
                nvgRestore(vg)
            end

            -- 等级徽章 + 等级数字（与 CharacterPanelDraw 一致）
            local lvlBadgeCX = cx + CARD_LVL_BADGE_DX
            local lvlBadgeCY = cy + CARD_LVL_BADGE_DY
            drawImageCentered(vg, imgLvlBadgeCard, lvlBadgeCX, lvlBadgeCY,
                CARD_LVL_BADGE_SIZE, CARD_LVL_BADGE_SIZE, 1.0)
            nvgFontFace(vg, "sans")
            drawTextStroke(vg, lvlBadgeCX, lvlBadgeCY, tostring(slotData.level or 1),
                28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)

            -- 名字背景 + 名字文本（与 CharacterPanelDraw 一致）
            local nameBgCY = cy + CARD_NAME_BG_DY
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - CARD_NAME_BG_W * 0.5, nameBgCY - CARD_NAME_BG_H * 0.5,
                CARD_NAME_BG_W, CARD_NAME_BG_H, CARD_NAME_BG_RADIUS)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
            nvgFill(vg)

            -- 选中时显示"强化中"，未选中显示角色名
            if isSelected then
                nvgFontFace(vg, "sans")
                drawTextStroke(vg, cx, nameBgCY, "强化中",
                    38, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    0x67, 0xff, 0x75, 4,
                    { strokeColor = { 0x23, 0x23, 0x23 } })
            else
                local heroName = heroInfo and heroInfo.name or ("英雄" .. heroId)
                nvgFontFace(vg, "sans")
                drawTextStroke(vg, cx, nameBgCY, heroName,
                    28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 4)
            end

            -- 可强化角标（右上角，该出战位有任意装备槽可强化时显示）
            if imgIconUp >= 0 and getCachedPartyCanEnhance(i) then
                local upSize = 40
                local upX = cx + CARD_W * 0.5 - upSize * 0.3
                local upY = cy - CARD_H * 0.5 + upSize * 0.3
                DrawUtil.drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
            end
        end
    end

end

--- 绘制 4 个装备槽位（强化 tab 专用，放在下半部分避免被 lower BG 覆盖）
local _equipSlotDbgTimer = 0
local function drawEquipSlots(vg)
    local teamSlots = CharacterPanel.getTeamSlotsData()
    local selectedSlot = teamSlots and teamSlots[state.selectedPartySlot]
    local heroId = selectedSlot and selectedSlot.heroId
    local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    local heroEquipped = nil
    if heroId and eqData and eqData.equipped then
        -- 尝试字符串和数字两种 key
        heroEquipped = eqData.equipped[tostring(heroId)] or eqData.equipped[heroId]
    end

    -- 诊断日志（每 3 秒打印一次）
    local now = time.elapsedTime or 0
    if now - _equipSlotDbgTimer > 3 then
        _equipSlotDbgTimer = now
        print("[drawEquipSlots] heroId=" .. tostring(heroId)
            .. " eqData=" .. tostring(eqData ~= nil)
            .. " equipped=" .. tostring(eqData and eqData.equipped ~= nil)
            .. " heroEquipped=" .. tostring(heroEquipped ~= nil))
        if eqData and eqData.equipped then
            local keys = {}
            for k, _ in pairs(eqData.equipped) do keys[#keys+1] = tostring(k) .. "(" .. type(k) .. ")" end
            print("[drawEquipSlots] equipped keys: " .. table.concat(keys, ", "))
        end
        if heroEquipped then
            local slots = {}
            for k, v in pairs(heroEquipped) do slots[#slots+1] = k .. "=" .. tostring(v) end
            print("[drawEquipSlots] heroEquipped: " .. table.concat(slots, ", "))
        end
    end

    for i, slotKey in ipairs(EQUIP_SLOT_ORDER) do
        local cx = getEquipSlotCX(i)
        local cy = EQUIP_SLOT_Y
        local isSelected = (slotKey == state.selectedEquipSlot)

        -- 选中底图（在槽位背景图后方）
        if isSelected and imgSlotSelected >= 0 then
            drawImageCentered(vg, imgSlotSelected, cx, cy, 234, 234, 1.0)
        end

        -- 槽位背景图
        local bgImg = imgSlotBg[slotKey]
        if bgImg and bgImg >= 0 then
            drawImageCentered(vg, bgImg, cx, cy, EQUIP_SLOT_SIZE, EQUIP_SLOT_SIZE, 1.0)
        end

        -- 如果该英雄该槽位有装备，绘制品质底框 + 装备图标
        local seq = heroEquipped and heroEquipped[slotKey]
        local equip = nil
        if seq and eqData and eqData.inventory then
            equip = eqData.inventory[tostring(seq)]
        end
        -- 双手武器镜像：offhand 无装备时检查 weapon 是否双手
        local isTwohandOccupied = false
        if not equip and slotKey == "offhand" and heroEquipped and eqData and eqData.inventory then
            local weaponSeq = heroEquipped["weapon"]
            if weaponSeq then
                local weaponEquip = eqData.inventory[tostring(weaponSeq)]
                if weaponEquip and weaponEquip.grip == "twohand" then
                    equip = weaponEquip
                    isTwohandOccupied = true
                end
            end
        end
        if equip then
            local qIdx = math.max(1, math.min(6, equip.quality or 1))
            drawImageCentered(vg, imgQualityBg[qIdx], cx, cy, EQUIP_SLOT_SIZE, EQUIP_SLOT_SIZE, 1.0)
            local eqIcon = getEquipIconCached(equip.templateId)
            if eqIcon and eqIcon > 0 then
                drawImageCentered(vg, eqIcon, cx, cy, EQUIP_SLOT_SIZE - 16, EQUIP_SLOT_SIZE - 16, 1.0)
            end
            -- 装备等级角标 "Lv.X"（右下角，16方向描边）
            local eqLv = equip.level or 1
            if eqLv >= 1 then
                local lvlText = "Lv." .. eqLv
                local lvlX = cx + EQUIP_SLOT_SIZE * 0.5 - 8
                local lvlY = cy + EQUIP_SLOT_SIZE * 0.5 - 6
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

            -- 双手武器占用副手槽位时绘制半透明黑色遮罩
            if isTwohandOccupied then
                nvgBeginPath(vg)
                nvgRoundedRect(vg,
                    cx - EQUIP_SLOT_SIZE * 0.5,
                    cy - EQUIP_SLOT_SIZE * 0.5,
                    EQUIP_SLOT_SIZE, EQUIP_SLOT_SIZE, 24)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
                nvgFill(vg)
            end
        end

        -- 槽位强化等级文本（来自 slotEnhance，与装备无关）
        do
            local slotEnhanceData = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
            local enhLv = 0
            if slotEnhanceData and slotEnhanceData.levels then
                local partyLevels = slotEnhanceData.levels[tostring(state.selectedPartySlot)]
                    or slotEnhanceData.levels[state.selectedPartySlot]
                if partyLevels then
                    enhLv = partyLevels[slotKey] or 0
                end
            end
            if enhLv > 0 then
                local lvX = cx
                local lvY = cy + EQUIP_LV_Y_OFFSET
                drawTextStroke(vg, lvX, lvY, "+" .. enhLv,
                    EQUIP_LV_FONT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    0x67, 0xff, 0x75, 5, { italic = true })
            end
        end

        -- 可强化角标（右上角，该装备槽位满足强化条件时显示）
        if imgIconUp >= 0 and getCachedSlotCanEnhance(state.selectedPartySlot, slotKey) then
            local upSize = 36
            local upX = cx + EQUIP_SLOT_SIZE * 0.5 - upSize * 0.25
            local upY = cy - EQUIP_SLOT_SIZE * 0.5 + upSize * 0.25
            DrawUtil.drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
        end
    end
end

--- 绘制下半部分 Tab 面板内容（按 tab 类型）
local function drawTabContent(vg, tabName)
    if tabName == "fenjie" then
        BlacksmithDecompose.drawPanel(vg)
        return
    end
    -- 强化/洗练：未选中装备时显示提示文本，不显示模拟数值
    if not state.selectedEquip then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 40)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x99, 0x99, 0x99, 180))
        nvgText(vg, 540, 1200, "请先选择装备", nil)
        return
    end
    -- 每次绘制前刷新拥有资源（实时反映余额变化）
    if tabName == "qianghua" then
        BlacksmithEnhance.drawPanel(vg)
        BlacksmithEnhance.drawPanelBottom(vg)
    elseif tabName == "xilian" then
        BlacksmithRefine.drawPanel(vg)
        BlacksmithRefine.drawPanelBottom(vg)
    end
end

-- ======================== Public API ========================

--- 初始化（加载图片资源）
function BlacksmithPage.init(vg)
    -- 共享图片
    imgBg       = nvgCreateImage(vg, "image/UI_TJP_CH_1.png", 0)
    imgNameBg   = nvgCreateImage(vg, "image/UI_TJP_MC.png", 0)
    imgPlus     = nvgCreateImage(vg, "image/UI_ICON_TJP_JIA.png", 0)
    imgLowerBg  = nvgCreateImage(vg, "image/UI_TJP_1.png", 0)
    imgBtnBack  = nvgCreateImage(vg, "image/UI_AN_FH.png", 0)
    imgTabBg    = nvgCreateImage(vg, "image/UI_AN_1.png", 0)
    imgSlider   = nvgCreateImage(vg, "image/UI_AN_2.png", 0)
    imgArrow    = nvgCreateImage(vg, "image/UI_TJP_JIANTOU.png", 0)
    imgEnhBtn   = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    imgGoldIcon = nvgCreateImage(vg, "image/UI_icon_JB.png", 0)
    imgGoldQBg  = nvgCreateImage(vg, "image/UI_icon_ZBBJ_2.png", 0)
    imgEssenceIcon = nvgCreateImage(vg, "image/UI_icon_JC.png", 0)
    imgXlBefore  = nvgCreateImage(vg, "image/UI_TJP_XL_2.png", 0)
    imgXlAfter   = nvgCreateImage(vg, "image/UI_TJP_XL_1.png", 0)
    imgReplaceBtn = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    imgCheckmark = nvgCreateImage(vg, "image/UI_icon_GOU.png", 0)
    imgLvlBadge  = nvgCreateImage(vg, "image/UI_JSJM_DJ.png", 0)
    imgRedDot    = nvgCreateImage(vg, "image/ICON_HD.png", 0)
    imgIconUp    = nvgCreateImage(vg, "image/ICON_UP.png", 0)
    -- 一键强化确认弹窗图片
    imgEnhDlgBg    = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    imgEnhDlgMinus = nvgCreateImage(vg, "image/UI_AN_JIAN.png", 0)
    imgEnhDlgPlus  = nvgCreateImage(vg, "image/UI_AN_JIA.png", 0)
    for i = 1, 6 do
        imgQualityBg[i] = nvgCreateImage(vg, "image/UI_icon_ZBBJ_" .. i .. ".png", 0)
    end

    -- 加载词缀等级图标
    local grades = { "D", "C", "B", "A", "S" }
    for _, g in ipairs(grades) do
        imgGrade[g] = nvgCreateImage(vg, "image/ICON_CZBZ_" .. g .. ".png", 0)
    end

    -- 编队卡片图片
    HeroAssetUtil.preloadCards(vg, imgHeroCards)
    for i = 1, 6 do
        imgClassIcons[i] = nvgCreateImage(vg, "image/ICON_ZY_" .. i .. ".png", 0)
    end
    imgDeployed     = nvgCreateImage(vg, "image/UI_JSJM_CZZ.png", 0)
    imgLock         = nvgCreateImage(vg, "image/UI_ICON_SUO.png", 0)
    imgPlusCard     = nvgCreateImage(vg, "image/UI_ICON_JIA.png", 0)
    imgPower        = nvgCreateImage(vg, "image/ICON_ZDL.png", 0)
    imgLvlBadgeCard = nvgCreateImage(vg, "image/UI_JSJM_DJ.png", 0)
    imgExpBarBg     = nvgCreateImage(vg, "image/UI_JSMB_JYT1.png", 0)
    imgExpBarFill   = nvgCreateImage(vg, "image/UI_JSMB_JYT2.png", 0)

    -- 装备槽位背景图
    imgSlotBg.weapon    = nvgCreateImage(vg, "image/UI_TJP_ZBL_WQ.png", 0)
    imgSlotBg.offhand   = nvgCreateImage(vg, "image/UI_TJP_ZBL_FS.png", 0)
    imgSlotBg.armor     = nvgCreateImage(vg, "image/UI_TJP_ZBL_HJ.png", 0)
    imgSlotBg.accessory = nvgCreateImage(vg, "image/UI_TJP_ZBL_SP.png", 0)
    imgSlotSelected     = nvgCreateImage(vg, "image/UI_TJPXZTBBJ.png", 0)

    -- 装备背包初始化
    EquipmentBag.init(vg)
    equipIconVg = vg

    -- 构建共享上下文并注入子模块
    local ctx = {
        -- 共享状态
        state            = state,
        ENHANCE_TABLE    = ENHANCE_TABLE,
        QUALITY_COST     = QUALITY_COST,
        -- 共享图片句柄
        imgArrow         = imgArrow,
        imgEnhBtn        = imgEnhBtn,
        imgGoldIcon      = imgGoldIcon,
        imgGoldQBg       = imgGoldQBg,
        imgEssenceIcon   = imgEssenceIcon,
        imgXlBefore      = imgXlBefore,
        imgXlAfter       = imgXlAfter,
        imgReplaceBtn    = imgReplaceBtn,
        imgPlus          = imgPlus,
        -- 一键强化确认弹窗图片
        imgDialogBg      = imgEnhDlgBg,
        imgBtnYellow     = imgReplaceBtn,   -- 复用黄色按钮背景
        imgBtnMinus      = imgEnhDlgMinus,
        imgBtnPlus       = imgEnhDlgPlus,
        imgCheckmark     = imgCheckmark,
        imgGrade         = imgGrade,
        imgQualityBg     = imgQualityBg,
        imgLock          = imgLock,
        -- 共享工具函数
        getEquipIconCached = getEquipIconCached,
        formatCompact      = formatCompact,
        formatAffixValue   = formatAffixValue,
        drawNineSlice      = drawNineSlice,
        -- 网络
        getClient          = getClient,
        getProtocol        = getProtocol,
    }

    BlacksmithEnhance.setContext(ctx)
    BlacksmithRefine.setContext(ctx)
    BlacksmithDecompose.setContext(ctx)

    -- 子模块专属图片初始化
    BlacksmithEnhance.init(vg)
    BlacksmithRefine.init(vg)
    BlacksmithDecompose.init(vg)

    -- 订阅外部数据变化，标脏可强化缓存（页面打开期间金币/强化等级由其他系统变动时）
    PlayerStore.Subscribe("slotEnhance", function()
        _enhanceCache.dirty = true
    end)
    ClientDispatcher.subscribe("slotEnhance", function()
        _enhanceCache.dirty = true
    end)
    PlayerStore.Subscribe("equipment", function()
        _enhanceCache.dirty = true
    end)

    print("[BlacksmithPage] init OK")
end

--- 打开铁匠铺
---@param preSelectEquip table|nil 预选装备（从装备详情跳转时传入）
---@param initialTab string|nil 初始 tab："qianghua"|"xilian"|"fenjie"，默认 "qianghua"
function BlacksmithPage.open(preSelectEquip, initialTab)
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    _enhanceCache.dirty = true  -- 打开时重新计算角标
    require("systems.GameSFX").playUIMove(1)
    local tab = initialTab or "qianghua"
    state.tab = tab
    state.tabFrom = tab
    state.tabSwitchTime = 0
    state.selectedEquip = nil
    -- 刷新分解页面背包数据
    BlacksmithDecompose.refreshBackpackItems()
    BlacksmithDecompose.onOpen()
    -- 重置强化子模块门控状态
    BlacksmithEnhance.onOpen()
    -- 初始化编队/装备槽选择
    state.selectedPartySlot = 1
    state.selectedEquipSlot = "weapon"
    -- 预选装备：自动放入对应 tab 槽位
    if preSelectEquip then
        state.selectedEquip = preSelectEquip
        BlacksmithEnhance.updateEnhanceData(preSelectEquip)
        BlacksmithRefine.updateRefineData(preSelectEquip)
        print("[BlacksmithPage] 打开铁匠铺 tab=" .. tab .. "（预选装备: " .. (preSelectEquip.name or "?") .. "）")
    else
        -- 自动选择第一个有装备的英雄槽+装备槽，避免默认选中空槽导致引导卡死。
        -- 若英雄1的 weapon 槽为空，则依次尝试其他装备槽；若英雄1全空则切到下一个英雄。
        local teamSlots = CharacterPanel.getTeamSlotsData()
        local eqData    = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
        if teamSlots and eqData and eqData.equipped then
            local found = false
            for partySlot = 1, 5 do
                local slot = teamSlots[partySlot]
                if slot and slot.state == "occupied" and slot.heroId then
                    local heroEquipped = eqData.equipped[tostring(slot.heroId)]
                                     or eqData.equipped[slot.heroId]
                    if heroEquipped then
                        for _, slotKey in ipairs(EQUIP_SLOT_ORDER) do
                            local seq = heroEquipped[slotKey]
                            if seq and eqData.inventory and eqData.inventory[tostring(seq)] then
                                state.selectedPartySlot = partySlot
                                state.selectedEquipSlot = slotKey
                                found = true
                                break
                            end
                        end
                    end
                end
                if found then break end
            end
            if found then
                print("[BlacksmithPage] 打开铁匠铺，自动选中槽位 partySlot="
                    .. state.selectedPartySlot .. " equipSlot=" .. state.selectedEquipSlot)
            else
                print("[BlacksmithPage] 打开铁匠铺，未找到已装备装备，保持默认槽位")
            end
        end
        deriveSelectedEquip()
        print("[BlacksmithPage] 打开铁匠铺")
    end
end

--- 关闭铁匠铺（启动关闭动画）
function BlacksmithPage.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    print("[BlacksmithPage] 关闭铁匠铺（动画）")
end

--- 注册关闭动画完成后的回调（触发一次后自动清除）
function BlacksmithPage.setOnCloseCallback(fn)
    onCloseCallback_ = fn
end

--- 注册打开动画完成后的回调（触发一次后自动清除）
function BlacksmithPage.setOnOpenCallback(fn)
    onOpenCallback_ = fn
end

--- 是否打开
---@return boolean
function BlacksmithPage.isOpen()
    return state.open
end

--- 强制关闭（跳过动画，用于安全恢复）
function BlacksmithPage.forceClose()
    if not state.open then return end
    print("[BlacksmithPage] forceClose: 跳过动画强制关闭 (closing=" .. tostring(state.closing) .. ")")
    state.open = false
    state.closing = false
end

--- 从战利品面板打开铁匠铺并直接进入自动分解设置弹窗
function BlacksmithPage.openToAutoDecompose()
    -- 若已打开则直接切换到分解 tab 并弹出弹窗；否则先 open 再切
    if not state.open then
        BlacksmithPage.open()
    end
    state.tab     = "fenjie"
    state.tabFrom = "fenjie"
    state.tabSwitchTime = 0
    -- 触发弹窗（autoPopupOpen 在 onOpen 中已重置为 false，需手动开启）
    BlacksmithDecompose.openAutoPopup()
    print("[BlacksmithPage] openToAutoDecompose")
end

--- 当装备数据从服务端推送更新时，刷新 selectedEquip
---@param equipmentData table 完整的装备模块数据
function BlacksmithPage.onEquipmentDataUpdate(equipmentData)
    if not state.open then return end

    -- 刷新分解页面背包数据
    BlacksmithDecompose.refreshBackpackItems()

    -- 洗练 tab 下：按 seq 从最新 inventory 中刷新独立选中的装备，不走 deriveSelectedEquip
    if state.tab == "xilian" and state.selectedEquip then
        local seq = state.selectedEquip.seq
        if seq then
            local eqData = equipmentData or ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
            if eqData and eqData.inventory then
                local refreshed = eqData.inventory[tostring(seq)]
                if refreshed then
                    state.selectedEquip = refreshed
                    if BlacksmithRefine.hasPreview() then
                        -- 有洗练预览时仅重算消耗，避免覆盖预览/动画状态
                        BlacksmithRefine.refreshCostOnly()
                    else
                        BlacksmithRefine.updateRefineData(refreshed)
                    end
                    print("[BlacksmithPage] 洗练tab: 按seq=" .. tostring(seq) .. "刷新装备数据+消耗")
                else
                    -- 装备可能已被分解/删除
                    state.selectedEquip = nil
                    BlacksmithRefine.updateRefineData(nil)
                    print("[BlacksmithPage] 洗练tab: seq=" .. tostring(seq) .. "装备已不存在，重置")
                end
            end
        end
        return
    end

    -- 强化/分解 tab：重新推导当前选中装备（服务端推送后英雄装备可能变化）
    deriveSelectedEquip()
    print("[BlacksmithPage] 装备数据已刷新（deriveSelectedEquip）")
end

--- 当服务端返回 action result 时处理强化/洗练特有数据
---@param data table action result 数据
function BlacksmithPage.onActionResult(data)
    if not state.open then return end

    -- 任何操作结果都可能影响金币/卷轴/强化等级 → 标脏角标缓存
    _enhanceCache.dirty = true

    -- 失败响应（无特定字段）→ 按当前 Tab 转发到对应子模块以释放门控
    if not data.enhanceOutcome and not data.refinePreview and not data.decomposed and not data.refineReplaced then
        if state.tab == "qianghua" then
            BlacksmithEnhance.onActionResult(data)
        elseif state.tab == "xilian" then
            BlacksmithRefine.onActionResult(data)
        elseif state.tab == "fenjie" then
            BlacksmithDecompose.onActionResult(data)
        end
        return
    end

    -- 强化结果 → 委托给 Enhance 子模块
    if data.enhanceOutcome then
        BlacksmithEnhance.onActionResult(data)
    end

    -- 洗练结果预览 → 委托给 Refine 子模块
    if data.refinePreview then
        BlacksmithRefine.onActionResult(data)
    end

    -- 分解结果处理 → 委托给 Decompose 子模块
    if data.decomposed then
        BlacksmithDecompose.onActionResult(data)
    end

    -- 替换成功 → 委托给 Refine 子模块
    if data.refineReplaced then
        BlacksmithRefine.onActionResult(data)
    end
end

--- 拖拽开始（由 Standalone/Client 委托转发）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function BlacksmithPage.handleDragBegin(dx, dy)
    if not state.open or state.closing then return true end
    if EquipmentBag.isOpen() then return EquipmentBag.handleDragBegin(dx, dy) end
    -- 一键强化确认弹窗滑块
    if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
        BlacksmithEnhance.handleDialogDragBegin(dx, dy)
        return true
    end
    -- 分解 tab：记录触摸起点用于滚动
    if state.tab == "fenjie" then
        BlacksmithDecompose.handleDragBegin(dx, dy)
    end
    return true  -- 铁匠铺打开时消费所有拖拽
end

--- 拖拽移动
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function BlacksmithPage.handleDragMove(dx, dy)
    if not state.open or state.closing then return true end
    if EquipmentBag.isOpen() then return EquipmentBag.handleDragMove(dx, dy) end
    -- 一键强化确认弹窗滑块
    if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
        BlacksmithEnhance.handleDialogDragMove(dx, dy)
        return true
    end
    -- 分解 tab：滑动滚动背包列表
    if state.tab == "fenjie" then
        BlacksmithDecompose.handleDragMove(dx, dy)
    end
    return true
end

--- 拖拽结束
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function BlacksmithPage.handleDragEnd(dx, dy)
    if not state.open then return false end
    if EquipmentBag.isOpen() then return EquipmentBag.handleDragEnd(dx, dy) end
    -- 一键强化确认弹窗滑块释放
    if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
        BlacksmithEnhance.handleDialogDragEnd()
        return true
    end
    -- 分解 tab：清除触摸状态
    if state.tab == "fenjie" then
        BlacksmithDecompose.handleDragEnd(dx, dy)
    end
    return true
end

--- 鼠标滚轮滚动
---@param wheel number 滚轮值
function BlacksmithPage.handleScroll(wheel)
    if not state.open or state.closing then return end
    if EquipmentBag.isOpen() then EquipmentBag.handleScroll(wheel); return end
    -- 分解 tab：滚轮滚动背包列表
    if state.tab == "fenjie" then
        BlacksmithDecompose.handleScroll(wheel)
    end
end

--- 处理输入
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function BlacksmithPage.handleInput(dx, dy)
    if not state.open then return false end
    if state.closing then
        -- 安全保护：如果关闭动画超过 1 秒仍未完成，强制关闭
        local closingElapsed = time.elapsedTime - state.closeTime
        if closingElapsed > 1.0 then
            print("[BlacksmithPage] handleInput: 关闭动画超时(" .. string.format("%.2f", closingElapsed) .. "s)，强制关闭")
            BlacksmithPage.forceClose()
            return false
        end
        return true
    end

    -- 装备背包优先处理
    if EquipmentBag.isOpen() then
        return EquipmentBag.handleInput(dx, dy)
    end

    -- 装备详情面板交互（长按触发，优先级最高）
    if state.tab == "fenjie" and EquipmentDetail.isOpen() then
        return EquipmentDetail.handleInput(dx, dy)
    end

    -- 自动分解弹窗交互（优先级最高）
    if state.tab == "fenjie" and BlacksmithDecompose.isPopupOpen() then
        return BlacksmithDecompose.handlePopupInput(dx, dy)
    end

    -- 一键强化确认弹窗（强化 tab，优先级最高）
    if state.tab == "qianghua" and BlacksmithEnhance.isDialogOpen() then
        return BlacksmithEnhance.handleDialogInput(dx, dy)
    end

    -- 返回按钮
    if hitTest(dx, dy, BTN_BACK_CX, BTN_BACK_CY, BTN_BACK_W, BTN_BACK_H) then
        BlacksmithPage.close()
        return true
    end

    -- 编队卡片 + 装备槽点击（仅强化 tab）
    if state.tab == "qianghua" then
        -- 5 张编队卡片点击
        for i = 1, MAX_PARTY do
            local cx = getCardSlotCX(i)
            if hitTest(dx, dy, cx, CARD_CY, CARD_W, CARD_H) then
                if i ~= state.selectedPartySlot then
                    state.selectedPartySlot = i
                    deriveSelectedEquip()
                    print("[BlacksmithPage] 选中编队槽位: " .. i)
                end
                return true
            end
        end
        -- 4 个装备槽点击
        for i, slotKey in ipairs(EQUIP_SLOT_ORDER) do
            local cx = getEquipSlotCX(i)
            if hitTest(dx, dy, cx, EQUIP_SLOT_Y, EQUIP_SLOT_SIZE, EQUIP_SLOT_SIZE) then
                if slotKey ~= state.selectedEquipSlot then
                    state.selectedEquipSlot = slotKey
                    deriveSelectedEquip()
                    print("[BlacksmithPage] 选中装备槽: " .. slotKey)
                end
                return true
            end
        end
    end

    -- 洗练 tab：单个装备槽点击（打开装备背包选择）
    if state.tab == "xilian" then
        local slotCX, slotCY, slotSize = 540, 431, 160
        if hitTest(dx, dy, slotCX, slotCY, slotSize, slotSize) then
            -- 洗练独立板块：slot=nil 显示全部装备（已装备+未装备），heroId=nil 不限英雄
            EquipmentBag.open(nil, "全部装备", nil, function(seq, equip)
                if equip then
                    state.selectedEquip = equip
                    BlacksmithRefine.updateRefineData(equip)
                    print("[BlacksmithPage] 洗练选择装备: seq=" .. tostring(seq) .. " name=" .. (equip.name or "?"))
                end
            end)
            return true
        end
    end

    -- Tab 切换检测
    for i, item in ipairs(TAB_ITEMS) do
        -- 每个 tab 使用 SLIDER_W x SLIDER_H 的点击区域
        if hitTest(dx, dy, item.cx, item.cy, SLIDER_W, SLIDER_H) then
            local tabKeys = { "qianghua", "xilian", "fenjie" }
            local newTab = tabKeys[i]
            if state.tab ~= newTab then
                state.tabFrom = state.tab
                state.tabSwitchTime = time.elapsedTime
                state.tab = newTab
                require("systems.GameSFX").playUIMove(2)
                -- 切换到强化 tab 时恢复装备选择（洗练 tab 会清空 selectedEquip）
                if newTab == "qianghua" then
                    deriveSelectedEquip()
                end
                -- 切换到洗练 tab 时重置装备选择（洗练槽位独立选择，不继承强化面板）
                if newTab == "xilian" then
                    state.selectedEquip = nil
                    BlacksmithRefine.updateRefineData(nil)
                end
                -- 切换到分解 tab 时重置分解状态
                if newTab == "fenjie" then
                    BlacksmithDecompose.onTabSwitch()
                    BlacksmithDecompose.refreshBackpackItems()
                end
                print("[BlacksmithPage] 切换到: " .. item.name)
            end
            return true
        end
    end

    -- Tab 内部输入：委托给对应子模块
    if state.tab == "qianghua" and state.selectedEquip then
        return BlacksmithEnhance.handleInput(dx, dy)
    elseif state.tab == "xilian" and state.selectedEquip then
        return BlacksmithRefine.handleInput(dx, dy)
    elseif state.tab == "fenjie" then
        return BlacksmithDecompose.handleInput(dx, dy)
    end

    -- 面板内其他区域，消费事件不关闭
    return true
end

--- 绘制铁匠铺界面
function BlacksmithPage.draw(vg)
    if not state.open then return end

    -- === 弹出/关闭动画 ===
    local rawT, progress, lowerProgress

    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        rawT = math.min(1.0, elapsed / CLOSE_ANIM_DURATION)
        progress      = 1 - easeInCubic(rawT)
        lowerProgress = progress
        if rawT >= 1.0 then
            print("[BlacksmithPage] draw: 关闭动画完成，state.open → false")
            state.open = false
            state.closing = false
            local cb = onCloseCallback_
            onCloseCallback_ = nil
            if cb then cb() end
            return
        end
    else
        local elapsed = time.elapsedTime - state.openTime
        rawT = math.min(1.0, elapsed / ANIM_DURATION)
        progress      = easeOutCubic(rawT)
        lowerProgress = easeOutCubic(rawT)
        if rawT >= 1.0 and onOpenCallback_ then
            local cb = onOpenCallback_
            onOpenCallback_ = nil
            cb()
        end
    end

    local upperOY = -UPPER_SLIDE_DIST * (1 - progress)
    local lowerOY =  LOWER_SLIDE_DIST * (1 - lowerProgress)
    local overlayAlpha = math.floor(180 * progress)

    -- === 全屏遮罩 ===
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)

    -- ================== 上半部分（从上方滑入） ==================
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)

    -- 1. 铁匠铺背景图（裁剪到设计宽度）
    nvgSave(vg)
    nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
    drawImageCentered(vg, imgBg, BG_CX, BG_CY, BG_W, BG_H, 1.0)
    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 2. 铁匠铺名称背景（中心点绘制）
    drawImageCentered(vg, imgNameBg, NAME_BG_CX, NAME_BG_CY, NAME_BG_W, NAME_BG_H, 1.0)

    -- 3. 文本"铁匠铺"（中心点坐标，无描边）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, NAME_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, NAME_TEXT_CX, NAME_TEXT_CY, "铁匠铺", nil)

    -- 4-6. 上半部分槽位区域 + 下半部分面板内容（带 Tab 切换滑动动画）
    local tabIdx = TAB_MAP[state.tab] or 3
    local fromIdx = TAB_MAP[state.tabFrom] or 3
    local tabElapsed = time.elapsedTime - state.tabSwitchTime
    local tabT = math.min(1.0, tabElapsed / TAB_ANIM_DURATION)
    local tabEased = easeInOutCubic(tabT)

    -- 滑动方向：新 tab 在旧 tab 左侧 -> 内容从左滑入（direction = -1）
    local direction = 0
    if tabIdx ~= fromIdx then
        direction = (tabIdx < fromIdx) and -1 or 1
    end
    -- 新面板偏移：从 direction*DESIGN_W 滑到 0
    local newOX = DESIGN_W * direction * (1 - tabEased)
    -- 旧面板偏移：从 0 滑到 -direction*DESIGN_W
    local oldOX = -DESIGN_W * direction * tabEased
    local isAnimating = (tabT < 1.0 and tabIdx ~= fromIdx)

    -- 上半部分：三种 tab 内容各不相同，任意两种之间切换都需要滑动
    local upperNeedSlide = isAnimating and (state.tab ~= state.tabFrom)

    if upperNeedSlide then
        -- 涉及分解切换：新旧槽位都带水平滑动 + 屏幕范围剪裁
        nvgSave(vg)
        nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgSave(vg)
        nvgTranslate(vg, oldOX, 0)
        drawUpperSlotContent(vg, state.tabFrom)
        nvgRestore(vg)
        nvgSave(vg)
        nvgTranslate(vg, newOX, 0)
        drawUpperSlotContent(vg, state.tab)
        nvgRestore(vg)
        nvgResetScissor(vg)
        nvgRestore(vg)
    else
        -- 强化<->洗练：上半部分不动，直接绘制当前 tab
        drawUpperSlotContent(vg, state.tab)
    end

    nvgRestore(vg)  -- 结束上半部分偏移

    -- ================== 下半部分（从下方滑入） ==================
    nvgSave(vg)
    nvgTranslate(vg, 0, lowerOY)

    -- 7. 下方背景板
    drawImageCentered(vg, imgLowerBg, LOWER_BG_CX, LOWER_BG_CY, LOWER_BG_W, LOWER_BG_H, 1.0)

    -- 7.5 装备槽位（仅强化 tab，带滑动动画，绘制在 lower BG 之上避免被覆盖）
    do
        local curIsQH = (state.tab == "qianghua")
        local oldIsQH = (state.tabFrom == "qianghua")
        if isAnimating and (curIsQH or oldIsQH) then
            -- 动画中：旧/新面板分别绘制装备槽位并带滑动
            nvgSave(vg)
            nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
            if oldIsQH then
                nvgSave(vg)
                nvgTranslate(vg, oldOX, 0)
                drawEquipSlots(vg)
                nvgRestore(vg)
            end
            if curIsQH then
                nvgSave(vg)
                nvgTranslate(vg, newOX, 0)
                drawEquipSlots(vg)
                -- Spine 强化结果特效
                if SpineResultEffect.isPlaying() then
                    local eqIdx = 1
                    for i, k in ipairs(EQUIP_SLOT_ORDER) do
                        if k == state.selectedEquipSlot then eqIdx = i; break end
                    end
                    SpineResultEffect.draw(vg, getEquipSlotCX(eqIdx), EQUIP_SLOT_Y)
                end
                nvgRestore(vg)
            end
            nvgResetScissor(vg)
            nvgRestore(vg)
        elseif curIsQH then
            -- 非动画：直接绘制
            drawEquipSlots(vg)
            if SpineResultEffect.isPlaying() then
                local eqIdx = 1
                for i, k in ipairs(EQUIP_SLOT_ORDER) do
                    if k == state.selectedEquipSlot then eqIdx = i; break end
                end
                SpineResultEffect.draw(vg, getEquipSlotCX(eqIdx), EQUIP_SLOT_Y)
            end
        end
    end

    -- 下方内容剪裁区域（背景板范围内，Tab 栏以上）
    local clipTop = LOWER_BG_CY - LOWER_BG_H * 0.5
    local clipBottom = TAB_BG_CY - TAB_BG_H * 0.5
    local clipH = clipBottom - clipTop

    -- === 绘制旧面板内容（滑出，仅动画中绘制） ===
    if isAnimating then
        nvgSave(vg)
        nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)
        nvgTranslate(vg, oldOX, 0)
        drawTabContent(vg, state.tabFrom)
        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    -- === 绘制新面板内容（当前 tab） ===
    nvgSave(vg)
    nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)
    if isAnimating then nvgTranslate(vg, newOX, 0) end
    drawTabContent(vg, state.tab)
    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 8. 返回按钮
    drawImageCentered(vg, imgBtnBack, BTN_BACK_CX, BTN_BACK_CY, BTN_BACK_W, BTN_BACK_H, 1.0)

    -- 9. 页面选项滑块背景
    drawImageCentered(vg, imgTabBg, TAB_BG_CX, TAB_BG_CY, TAB_BG_W, TAB_BG_H, 1.0)

    -- 10-11. 滑块按钮（带平移动画，与角色详情完全一致）
    local targetItem = TAB_ITEMS[tabIdx]
    local fromItem = TAB_ITEMS[fromIdx]

    local sliderCX = fromItem.cx + (targetItem.cx - fromItem.cx) * tabEased
    local sliderCY = fromItem.cy + (targetItem.cy - fromItem.cy) * tabEased

    -- 使用九宫格绘制滑块
    drawNineSlice(vg, imgSlider,
        sliderCX - SLIDER_W * 0.5, sliderCY - SLIDER_H * 0.5,
        SLIDER_W, SLIDER_H,
        SLIDER_INSET_TOP, SLIDER_INSET_RIGHT, SLIDER_INSET_BOTTOM, SLIDER_INSET_LEFT)

    -- Tab 文本
    for i, item in ipairs(TAB_ITEMS) do
        local tabKeys = { "qianghua", "xilian", "fenjie" }
        local isActive = (state.tab == tabKeys[i])

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TAB_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(TAB_ACTIVE_R, TAB_ACTIVE_G, TAB_ACTIVE_B, 255))
        else
            nvgFillColor(vg, nvgRGBA(TAB_INACTIVE_R, TAB_INACTIVE_G, TAB_INACTIVE_B, 255))
        end
        nvgText(vg, item.cx, TAB_TEXT_Y, item.name, nil)
    end

    -- 分解标签红点（背包满时，选中也保留）
    if imgRedDot >= 0 and decomposeRedDot then
        local fenjieTab = TAB_ITEMS[3]  -- "分解"
        nvgFontFace(vg, "sans"); nvgFontSize(vg, TAB_FONT_SIZE)
        local upSize = 30
        local textHalfW = nvgTextBounds(vg, 0, 0, fenjieTab.name) * 0.5
        local upX = fenjieTab.cx + textHalfW + 10
        local upY = TAB_TEXT_Y - 18
        DrawUtil.drawImageCentered(vg, imgRedDot, upX, upY, upSize, upSize, 1.0)
    end

    -- 强化标签可强化角标（有任意槽位满足强化条件时显示）
    if imgIconUp >= 0 and BlacksmithPage.canEnhanceAny() then
        local qhTab = TAB_ITEMS[1]  -- "强化"
        nvgFontFace(vg, "sans"); nvgFontSize(vg, TAB_FONT_SIZE)
        local upSize = 30
        local textHalfW = nvgTextBounds(vg, 0, 0, qhTab.name) * 0.5
        local upX = qhTab.cx + textHalfW + 10
        local upY = TAB_TEXT_Y - 18
        DrawUtil.drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
    end

    nvgRestore(vg)  -- 结束下半部分偏移

    -- 自动分解弹窗（最顶层，不受滑动偏移影响）
    if state.tab == "fenjie" then
        BlacksmithDecompose.drawAutoDecomposePopup(vg)
    end

    -- 装备详情面板（最顶层，长按触发）
    if state.tab == "fenjie" then
        EquipmentDetail.draw(vg)
    end

    -- 一键强化确认弹窗（强化 tab，最顶层）
    if state.tab == "qianghua" then
        BlacksmithEnhance.drawConfirmDialog(vg)
    end

    -- 装备背包覆盖层（最顶层）
    EquipmentBag.draw(vg)
end

--- 设置分解标签红点（背包满时由外部驱动）
---@param show boolean
function BlacksmithPage.setDecomposeRedDot(show)
    decomposeRedDot = show
end

--- 检查是否有任意出战槽位的装备槽位满足强化条件
--- 遍历 5 个出战位 × 4 个装备槽，只要有一个当前金币+卷轴足够升级就返回 true
---@return boolean
function BlacksmithPage.canEnhanceAny()
    local BlacksmithConfig = require("config.BlacksmithConfig")
    local slotEnhanceData = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
    if not slotEnhanceData or not slotEnhanceData.levels then return false end

    local gold = GameState.getGold()
    local teamSlots = CharacterPanel.getTeamSlotsData()

    for partySlot = 1, MAX_PARTY do
        -- 跳过空槽位和未解锁槽位：只有已上阵角色的装备槽才算可强化
        local slot = teamSlots and teamSlots[partySlot]
        if not slot or slot.state ~= "occupied" then goto continueParty end

        local partyLevels = slotEnhanceData.levels[tostring(partySlot)]
            or slotEnhanceData.levels[partySlot]
        for _, equipSlot in ipairs(EQUIP_SLOT_ORDER) do
            local curLevel = (partyLevels and partyLevels[equipSlot]) or 0
            if curLevel < BlacksmithConfig.MAX_ENHANCE_LEVEL then
                local nextLevel = curLevel + 1
                local cost = BlacksmithConfig.getEnhanceCost(nextLevel)
                if cost then
                    local scrollField = BlacksmithConfig.SLOT_SCROLL_MAP[equipSlot]
                    local scrollGetter = scrollField and BlacksmithEnhance.getScrollGetter(scrollField)
                    local ownedScroll = 0
                    if scrollGetter and GameState[scrollGetter] then
                    ---@diagnostic disable-next-line: assign-type-mismatch
                        ownedScroll = GameState[scrollGetter]()
                    end
                    if gold >= cost.gold and ownedScroll >= cost.scroll then
                        return true
                    end
                end
            end
        end
        ::continueParty::
    end
    return false
end

-- ============================================================================
-- Standalone 自动分解弹窗代理（供战利品面板等外部直接调用，无需打开铁匠铺）
-- ============================================================================

--- 直接打开自动分解设置弹窗（不切换 tab，不打开铁匠铺页面）
function BlacksmithPage.openAutoDecomposePopupStandalone()
    BlacksmithDecompose.openAutoPopup()
end

--- 检查自动分解弹窗是否处于 standalone 模式（BlacksmithPage 未打开时）
---@return boolean
function BlacksmithPage.isAutoDecomposePopupStandaloneOpen()
    return BlacksmithDecompose.isPopupOpen() and not BlacksmithPage.isOpen()
end

--- 在顶层绘制自动分解弹窗（当 BlacksmithPage 未打开时使用）
---@param vg any
function BlacksmithPage.drawAutoDecomposePopupStandalone(vg)
    if BlacksmithPage.isOpen() then return end  -- 已由 draw() 内部处理
    BlacksmithDecompose.drawAutoDecomposePopup(vg)
end

--- 处理 standalone 模式下的弹窗输入
---@param dx number
---@param dy number
---@return boolean
function BlacksmithPage.handleAutoDecomposePopupStandaloneInput(dx, dy)
    if BlacksmithPage.isOpen() then return false end  -- 已由 handleInput() 内部处理
    return BlacksmithDecompose.handlePopupInput(dx, dy)
end

return BlacksmithPage
