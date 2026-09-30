-- ============================================================================
-- BlacksmithPage - 铁匠铺界面
-- 从城镇页面点击铁匠铺进入的二级界面
-- 职责：铁匠铺常规 UI（背景、装备槽、分解/洗练/强化切换）
-- 子模块：BlacksmithEnhance / BlacksmithRefine / BlacksmithDecompose
-- ============================================================================

local GameConfig       = require("config.GameConfig")
local GameState        = require("core.GameState")
local DarkIcon         = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质底框矢量绘制
local EquipmentBag     = require("ui.character.equip.EquipmentBag")
local EquipmentDetail  = require("ui.character.equip.EquipmentDetail")
local EquipmentConfig  = require("config.EquipmentConfig")
local AffixConfig      = require("config.AffixConfig")
local AD               = require("systems.AttributeDef")
local ClientDispatcher = require("runtime.ClientDispatcher")
local PlayerStore      = require("core.PlayerStore")
local EquipmentSystem  = require("systems.EquipmentSystem")
local RewardPopup      = require("ui.hud.popup.RewardPopup")
local SpineResultEffect = require("ui.fx.SpineResultEffect")
local DrawUtil         = require("core.DrawUtil")
local DarkIcon       = require("core.DarkIcon")  -- [暗黑化 P0] 矢量图标库
local TownPageChrome   = require("ui.town.TownPageChrome")
local ExpTable         = require("config.ExpTable")
local HeroAssetUtil    = require("config.HeroAssetUtil")
local HeroConfig       = require("config.HeroConfig")
local HeroFrame        = require("ui.widget.HeroFrame")

-- 子模块
local BlacksmithEnhance   = require("ui.blacksmith.BlacksmithEnhance")
local BlacksmithRefine    = require("ui.blacksmith.BlacksmithRefine")
local BlacksmithDecompose = require("ui.blacksmith.BlacksmithDecompose")
local BlacksmithEnhanceCache = require("ui.blacksmith.BlacksmithEnhanceCache")

-- 延迟加载网络模块（避免循环依赖）
local Client_
local Protocol_
local function getClient()
    if not Client_ then Client_ = require("runtime.GameAction") end
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

-- 4. 强化/洗练共用的装备选择槽（上半部分居中单槽，点击打开装备背包）
local SELECT_SLOT_CX, SELECT_SLOT_CY = 540, 431
local SELECT_SLOT_SIZE               = 160

local EQUIP_LV_FONT_SIZE = 38
local EQUIP_SLOT_ORDER   = { "weapon", "offhand", "armor", "helmet", "shoes", "accessory" }

-- 7. 下方背景板
local LOWER_BG_CX, LOWER_BG_W, LOWER_BG_H = 540, 1080, 1670
-- Y 最下方与屏幕最下方对齐 -> cy = DESIGN_H - H/2
local LOWER_BG_CY = DESIGN_H - LOWER_BG_H * 0.5  -- 2400 - 835 = 1565

-- 8. 返回按钮（与角色详情界面完全一致）
local BTN_BACK_CX, BTN_BACK_CY = 958, 1150
local BTN_BACK_W, BTN_BACK_H   = 184, 143

-- 9. 页面选项滑块背景（与角色界面完全一致）
local TAB_BG_CX, TAB_BG_CY = 540, 2308
local TAB_BG_W, TAB_BG_H   = 810, 143

-- 10. 三个滑块按钮位置（Y 与 tab 背景一致 = 2308，参考 CharacterDetail）
local TAB_ITEMS = {
    { name = "强化", cx = 274, cy = 2308 },
    { name = "洗练", cx = 540, cy = 2308 },
    { name = "分解", cx = 806, cy = 2308 },
}

-- 11. 滑块按钮（九宫格）
local SLIDER_W, SLIDER_H = 277, 143
local SLIDER_DEFAULT_CX   = 806   -- 默认在强化位置
local SLIDER_DEFAULT_CY   = 2308
-- 九宫格 inset: 上10 下10 左70 右70
local SLIDER_INSET_TOP    = 10
local SLIDER_INSET_BOTTOM = 10
local SLIDER_INSET_LEFT   = 70
local SLIDER_INSET_RIGHT  = 70

-- Tab 文本样式
local TAB_TEXT_Y          = 2302
local TAB_FONT_SIZE       = 40
local TAB_ACTIVE_R, TAB_ACTIVE_G, TAB_ACTIVE_B = 0xD8, 0xC9, 0xA3  -- [fix] 深色滑块上深棕不可读 → 骨白
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
    -- 装备槽选择（强化/洗练共用，单槽）
    selectedEquipSlot = "weapon",    -- 当前选中的装备槽位 key
    -- 已选装备（由 selectedEquipSlot 从玩家身上推导）
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
local imgHeroIcons = {}    -- [heroId] = nvgImage handle, 角色头像角标（与背包一致）

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
local BlacksmithDraw = require("ui.blacksmith.BlacksmithDraw")
local BlacksmithInput = require("ui.blacksmith.BlacksmithInput")
local BlacksmithResults = require("ui.blacksmith.BlacksmithResults")

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

local imgArrow    = -1   -- UI_TJP_JIANTOU.png（提升箭头）
local imgEnhBtn   = -1   -- UI_AN_LV.png（强化按钮背景）
local imgGoldIcon = -1   -- UI_icon_JB_X.png（金币图标）
local imgGoldQBg  = -1   -- UI_icon_ZBBJ_2.png（金币品质背景框, quality=2）
local imgEssenceIcon = -1 -- UI_icon_JC.png（精粹图标）
local imgXlBefore  = -1   -- UI_TJP_XL_2.png（洗练前背景框）
local imgXlAfter   = -1   -- UI_TJP_XL_1.png（洗练后背景框）
local imgReplaceBtn = -1  -- UI_AN_HUANG.png（替换按钮背景）
local imgCheckmark = -1   -- UI_icon_GOU.png（选中打钩）
local imgLvlBadge  = -1   -- UI_JSJM_DJ.png（等级徽章）
-- [图标统一 0928] 移除 imgRedDot 死声明：红点统一走 DarkIcon.draw(vg,"reddot",...)
local imgIconUp    = -1   -- ICON_UP.png（可强化角标）
-- 一键强化确认弹窗专用图片
local imgEnhDlgMinus = -1  -- UI_AN_JIAN.png（减按钮）
local imgEnhDlgPlus  = -1  -- UI_AN_JIA.png（加按钮）

-- ======================== 外部驱动标志 ========================
local decomposeRedDot = false  -- 分解标签红点（背包满时）
local imgQualityBg = {}   -- UI_icon_ZBBJ_1~5（品质背景框，按品质索引）

-- 词缀等级图标 D/C/B/A/S
local imgGrade = {}      -- imgGrade["D"], imgGrade["C"], ...

-- ======================== 缓动函数（TownPageChrome） ========================
local easeOutCubic   = TownPageChrome.easeOutCubic
local easeInCubic    = TownPageChrome.easeInCubic
local easeInOutCubic = TownPageChrome.easeInOutCubic

-- ======================== 工具函数 ========================

--- 居中绘制图片
local drawImageCentered = DrawUtil.drawImageCentered

--- 描边文字
local drawTextStroke = DrawUtil.drawTextStroke

--- 九宫格绘制
local drawNineSlice = DrawUtil.drawNineSlice

--- hitTest（中心坐标 + 尺寸）
local hitTest = DrawUtil.hitTest

-- ======================== 选中装备推导 ========================

--- 根据 selectedEquipSlot 从出战英雄身上推导 selectedEquip（双手武器镜像到 offhand）
local function deriveSelectedEquip()
    local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    if not eqData or not eqData.equipped or not eqData.inventory then
        state.selectedEquip = nil
        BlacksmithEnhance.updateEnhanceData(nil)
        BlacksmithRefine.updateRefineData(nil)
        return
    end
    local heroes = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
    local deployed = heroes and heroes.deployed or {}
    for i = 1, #deployed do
        local heroId = deployed[i]
        local heroEquipped = EquipmentSystem.getHeroSlots(eqData, heroId)
        if heroEquipped then
            local seq = heroEquipped[state.selectedEquipSlot]
            -- 双手武器镜像：offhand 无装备时检查 weapon 是否双手
            if not seq and state.selectedEquipSlot == "offhand" then
                local weaponSeq = heroEquipped["weapon"]
                local weaponEquip = weaponSeq and eqData.inventory[tostring(weaponSeq)]
                if weaponEquip and weaponEquip.grip == "twohand" then
                    seq = weaponSeq
                end
            end
            local equip = seq and eqData.inventory[tostring(seq)]
            if equip then
                state.selectedEquip = equip
                equip.seq = tonumber(seq)
                state.selectedSeq = equip.seq
                BlacksmithEnhance.updateEnhanceData(equip)
                BlacksmithRefine.updateRefineData(equip)
                return
            end
        end
    end
    -- 无英雄在该槽位装备
    state.selectedEquip = nil
    BlacksmithEnhance.updateEnhanceData(nil)
    BlacksmithRefine.updateRefineData(nil)
end

--- 查询装备当前被哪个英雄穿戴（遍历出战+后备阵容）
---@param equip table|nil
---@return number|nil heroId
local function getEquipOwnerHeroId(equip)
    if not equip or not equip.seq then return nil end
    local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    if not eqData or not eqData.equipped then return nil end
    local seqStr = tostring(equip.seq)
    for heroKey, slots in pairs(eqData.equipped) do
        if slots then
            for _, slotKey in ipairs(EQUIP_SLOT_ORDER) do
                if tostring(slots[slotKey]) == seqStr then
                    return tonumber(heroKey) or heroKey
                end
            end
        end
    end
    return nil
end

-- ======================== 可强化检查（供角标绘制使用） ========================

-- -------- 性能缓存：避免 draw 每帧重复计算 canEnhance --------
local _enhanceCache = {
    dirty = true,
    --- canEnhance(equip) = bool  单件装备是否可强化
    canEnhance = nil,
}

local _enhCache
local function bindEnhanceCache()
    _enhCache = BlacksmithEnhanceCache.bind({
        ClientDispatcher = ClientDispatcher,
        PlayerStore = PlayerStore,
        GameState = GameState,
        ExpTable = ExpTable,
        BlacksmithEnhance = BlacksmithEnhance,
        cache = _enhanceCache,
    })
end

--- 标记可强化缓存为脏（数据变化时调用）
function BlacksmithPage.markEnhanceDirty()
    _enhanceCache.dirty = true
end

local function refreshEnhanceCache()
    if not _enhCache then bindEnhanceCache() end
    return _enhCache.refreshEnhanceCache()
end

--- 选中装备当前是否可强化（选择槽角标用）
local function getCachedSelectedCanEnhance()
    refreshEnhanceCache()
    if not _enhanceCache.canEnhance then return false end
    return _enhanceCache.canEnhance(state.selectedEquip) or false
end

-- ======================== 上半部分绘制 ========================

--- 绘制上半部分选中装备槽（强化/洗练共用，点击打开装备背包选择）
---@param vg any
---@param tabName string "qianghua" | "xilian"（空状态提示文案不同）
local function drawSelectedEquipSlot(vg, tabName)
    local equip = state.selectedEquip
    local slotCX, slotCY = SELECT_SLOT_CX, SELECT_SLOT_CY
    local slotSize = SELECT_SLOT_SIZE

    local ownerHeroId = getEquipOwnerHeroId(equip)

    if equip then
        -- 品质底框 + 装备图标（160x160）[暗黑化 P2-A]
        local qIdx = math.max(1, math.min(6, equip.quality or 1))
        DarkIcon.drawQualityBg(vg, qIdx, slotCX, slotCY, slotSize, slotSize, 1.0)
        local eqIcon = getEquipIconCached(equip.templateId)
        if eqIcon and eqIcon > 0 then
            DarkIcon.drawIconDark(vg, eqIcon, slotCX, slotCY, slotSize - 16, slotSize - 16, 1.0)  -- [暗黑化 P2-B]
        end

        local enhLv = equip and EquipmentSystem.getAscendLevel(equip) or 0
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

        -- 归属行（装备名下方）：已装备英雄 或 背包未装备提示
        local ownerLine, oR, oG, oB
        if ownerHeroId then
            local heroInfo = HeroConfig.get(ownerHeroId)
            ownerLine = "已装备: " .. (heroInfo and heroInfo.name or ("英雄" .. tostring(ownerHeroId)))
            oR, oG, oB = 0xD8, 0xC9, 0xA3
        else
            ownerLine = "未装备(背包)"
            oR, oG, oB = 0x99, 0x99, 0x99
        end
        nvgFontFace(vg, "sans")
        drawTextStroke(vg, slotCX, slotCY + slotSize * 0.5 + 74, ownerLine,
            26, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            oR, oG, oB, 3)

        -- 归属英雄头像角标（左下角，与背包"他人已装备"白描边变体一致）
        if ownerHeroId then
            local ownerIcon = imgHeroIcons[ownerHeroId]
            if ownerIcon and ownerIcon >= 0 then
                local badgeSize = 66
                HeroFrame.draw(vg, {
                    cx = slotCX - slotSize * 0.5 + badgeSize * 0.5 + 1,
                    cy = slotCY + slotSize * 0.5 - badgeSize * 0.5 - 1,
                    size = badgeSize, radius = 6,
                    heroId = ownerHeroId,
                    iconHandle = ownerIcon,
                    state = "owned",
                    borderOverride = { 255, 255, 255, 200, 2 },
                })
            end
        end

        -- 选中高亮边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, slotCX - slotSize * 0.5 - 3, slotCY - slotSize * 0.5 - 3,
            slotSize + 6, slotSize + 6, 24)
        nvgStrokeColor(vg, nvgRGBA(0xff, 0xd7, 0x00, 200))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)

        -- 可强化角标（强化 tab，右上角）
        if tabName == "qianghua" and imgIconUp >= 0 and getCachedSelectedCanEnhance() then
            local upSize = 40
            DrawUtil.drawImageCentered(vg, imgIconUp,
                slotCX + slotSize * 0.5 - upSize * 0.3,
                slotCY - slotSize * 0.5 + upSize * 0.3,
                upSize, upSize, 1.0)
        end
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
        nvgText(vg, slotCX, slotCY + slotSize * 0.5 + 30,
            tabName == "qianghua" and "选择装备进行升阶" or "选择装备进行洗练", nil)
    end
end

--- 绘制上半部分内容（分解 / 洗练 / 强化）
local function drawUpperSlotContent(vg, tabName)
    if tabName == "fenjie" then
        BlacksmithDecompose.drawUpperSlot(vg)
        return
    end

    -- 强化/洗练：共用"选装备"单槽，点击打开装备背包
    drawSelectedEquipSlot(vg, tabName)
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

local blacksmithInited_ = false
local blacksmithVg_ = nil

--- 初始化（加载图片资源）
function BlacksmithPage.init(vg)
    if blacksmithInited_ then return end
    blacksmithInited_ = true
    blacksmithVg_ = vg
    -- 共享图片
    imgBg       = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_CH_1.png", 0)
    imgNameBg   = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0)
    imgPlus     = nvgCreateImage(vg, "image/通用图标/UI_ICON_TJP_JIA.png", 0)
    imgLowerBg  = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_1.png", 0)
    imgBtnBack  = nvgCreateImage(vg, "image/按钮/UI_AN_FH.png", 0)
    imgTabBg    = nvgCreateImage(vg, "image/按钮/UI_AN_1.png", 0)
    -- [暗黑化 P1-B5] 原 image/按钮/UI_AN_2.png 贴图加载已移除（矢量绘制替代）
    imgArrow    = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_JIANTOU.png", 0)
    imgEnhBtn   = nvgCreateImage(vg, "image/按钮/UI_AN_LV.png", 0)
    imgGoldIcon = nvgCreateImage(vg, "image/货币道具/UI_icon_JB_X.png", 0)
    imgGoldQBg  = nvgCreateImage(vg, "image/品质框/UI_icon_ZBBJ_2.png", 0)
    imgEssenceIcon = nvgCreateImage(vg, "image/货币道具/UI_icon_JC.png", 0)
    imgXlBefore  = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_XL_2.png", 0)
    imgXlAfter   = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_XL_1.png", 0)
    imgReplaceBtn = nvgCreateImage(vg, "image/按钮/UI_AN_HUANG.png", 0)
    imgCheckmark = nvgCreateImage(vg, "image/货币道具/UI_icon_GOU.png", 0)
    imgLvlBadge  = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSJM_DJ.png", 0)
    imgIconUp    = nvgCreateImage(vg, "image/通用图标/ICON_UP.png", 0)
    -- 一键强化确认弹窗图片
    imgEnhDlgMinus = nvgCreateImage(vg, "image/按钮/UI_AN_JIAN.png", 0)
    imgEnhDlgPlus  = nvgCreateImage(vg, "image/按钮/UI_AN_JIA.png", 0)
    for i = 1, 6 do
        imgQualityBg[i] = nvgCreateImage(vg, "image/品质框/UI_icon_ZBBJ_" .. i .. ".png", 0)
    end

    -- 加载词缀等级图标
    local grades = { "D", "C", "B", "A", "S" }
    for _, g in ipairs(grades) do
        imgGrade[g] = nvgCreateImage(vg, "image/通用图标/ICON_CZBZ_" .. g .. ".png", 0)
    end

    -- 词缀锁定图标（洗练子模块经 ctx 使用）
    local imgLock   = nvgCreateImage(vg, "image/通用图标/UI_ICON_SUO.png", 0)
    -- 角色头像角标（选择槽归属显示，与背包一致）
    HeroAssetUtil.preloadIcons(vg, imgHeroIcons)

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
        imgDialogBg      = -1,  -- 弹窗背景已改 DarkIcon.drawNine 矢量绘制，无贴图
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

    -- 升阶跟装备走，装备或货币变化时刷新可升阶角标
    PlayerStore.Subscribe("equipment", function()
        _enhanceCache.dirty = true
    end)
    PlayerStore.Subscribe("currency", function()
        _enhanceCache.dirty = true
    end)

    print("[BlacksmithPage] init OK")
end

--- 打开铁匠铺
---@param preSelectEquip table|nil 预选装备（从装备详情跳转时传入）
---@param initialTab string|nil 初始 tab："qianghua"|"xilian"|"fenjie"，默认 "qianghua"
function BlacksmithPage.open(preSelectEquip, initialTab)
    if not blacksmithInited_ and blacksmithVg_ then
        BlacksmithPage.init(blacksmithVg_)
    end
    if not blacksmithInited_ then
        print("[BlacksmithPage] open before init, skip")
        return
    end
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
    -- 初始化装备槽选择
    state.selectedEquipSlot = "weapon"
    -- 预选装备：自动放入对应 tab 槽位
    if preSelectEquip then
        state.selectedEquip = preSelectEquip
        state.selectedSeq = preSelectEquip.seq
        if preSelectEquip.slot then state.selectedEquipSlot = preSelectEquip.slot end
        BlacksmithEnhance.updateEnhanceData(preSelectEquip)
        BlacksmithRefine.updateRefineData(preSelectEquip)
        print("[BlacksmithPage] 打开铁匠铺 tab=" .. tab .. "（预选装备: " .. (preSelectEquip.name or "?") .. "）")
    else
        -- 自动选择第一个有已装备装备的槽位，避免默认选中空槽导致引导卡死。
        local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
        local heroes = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
        local deployed = heroes and heroes.deployed or {}
        local found = false
        if eqData and eqData.equipped and eqData.inventory then
            for i = 1, #deployed do
                local heroEquipped = EquipmentSystem.getHeroSlots(eqData, deployed[i])
                if heroEquipped then
                    for _, slotKey in ipairs(EQUIP_SLOT_ORDER) do
                        local seq = heroEquipped[slotKey]
                        if seq and eqData.inventory[tostring(seq)] then
                            state.selectedEquipSlot = slotKey
                            found = true
                            break
                        end
                    end
                end
                if found then break end
            end
        end
        if found then
            print("[BlacksmithPage] 打开铁匠铺，自动选中装备槽=" .. state.selectedEquipSlot)
        else
            print("[BlacksmithPage] 打开铁匠铺，未找到已装备装备，保持默认槽位")
        end
        deriveSelectedEquip()
        print("[BlacksmithPage] 打开铁匠铺")
    end
end

--- 关闭铁匠铺（启动关闭动画）
function BlacksmithPage.close()
    if state.closing then return end
    require("systems.StoryPlayer").onPlace("smith", "leave")
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

local _results
local function bindResults()
    _results = BlacksmithResults.bind({
        state = state,
        BlacksmithDecompose = BlacksmithDecompose,
        BlacksmithEnhance = BlacksmithEnhance,
        BlacksmithRefine = BlacksmithRefine,
        ClientDispatcher = ClientDispatcher,
        PlayerStore = PlayerStore,
        deriveSelectedEquip = deriveSelectedEquip,
        enhanceCache = _enhanceCache,
    })
end

function BlacksmithPage.onEquipmentDataUpdate(equipmentData)
    if not _results then bindResults() end
    return _results.onEquipmentDataUpdate(equipmentData)
end

function BlacksmithPage.onActionResult(data)
    if not _results then bindResults() end
    return _results.onActionResult(data)
end

--- 点击/拖拽/滚轮
local _input
local function bindInput()
    _input = BlacksmithInput.bind({
        EquipmentBag = EquipmentBag,
        BlacksmithEnhance = BlacksmithEnhance,
        BlacksmithDecompose = BlacksmithDecompose,
        BlacksmithRefine = BlacksmithRefine,
        TownPageChrome = TownPageChrome,
        TAB_ITEMS = TAB_ITEMS,
        state = state,
        forceClose = BlacksmithPage.forceClose,
        closePage = BlacksmithPage.close,
        BlacksmithPage = BlacksmithPage,
        EquipmentDetail = EquipmentDetail,
        SLIDER_W = SLIDER_W,
        SLIDER_H = SLIDER_H,
        hitTest = hitTest,
        SELECT_SLOT_CX = SELECT_SLOT_CX,
        SELECT_SLOT_CY = SELECT_SLOT_CY,
        SELECT_SLOT_SIZE = SELECT_SLOT_SIZE,
        deriveSelectedEquip = deriveSelectedEquip,
    })
end

function BlacksmithPage.handleDragBegin(dx, dy)
    if not _input then bindInput() end
    return _input.handleDragBegin(dx, dy)
end

function BlacksmithPage.handleDragMove(dx, dy)
    if not _input then bindInput() end
    return _input.handleDragMove(dx, dy)
end

function BlacksmithPage.handleDragEnd(dx, dy)
    if not _input then bindInput() end
    return _input.handleDragEnd(dx, dy)
end

function BlacksmithPage.handleScroll(wheel, dx, dy)
    if not _input then bindInput() end
    return _input.handleScroll(wheel, dx, dy)
end

function BlacksmithPage.handleInput(dx, dy)
    if not _input then bindInput() end
    return _input.handleInput(dx, dy)
end

--- 绘制铁匠铺界面
local _pageDraw
local function bindPageDraw()
    _pageDraw = BlacksmithDraw.bind({
        ANIM_DURATION = ANIM_DURATION,
        BG_CX = BG_CX,
        BG_CY = BG_CY,
        BG_H = BG_H,
        BG_W = BG_W,
        BlacksmithDecompose = BlacksmithDecompose,
        BlacksmithEnhance = BlacksmithEnhance,
        BlacksmithPage = BlacksmithPage,
        CLOSE_ANIM_DURATION = CLOSE_ANIM_DURATION,
        DESIGN_H = DESIGN_H,
        DESIGN_W = DESIGN_W,
        DarkIcon = DarkIcon,
        DrawUtil = DrawUtil,
        EQUIP_SLOT_ORDER = EQUIP_SLOT_ORDER,
        EquipmentBag = EquipmentBag,
        EquipmentDetail = EquipmentDetail,
        LOWER_BG_CX = LOWER_BG_CX,
        LOWER_BG_CY = LOWER_BG_CY,
        LOWER_BG_H = LOWER_BG_H,
        LOWER_BG_W = LOWER_BG_W,
        LOWER_SLIDE_DIST = LOWER_SLIDE_DIST,
        NAME_FONT_SIZE = NAME_FONT_SIZE,
        NAME_TEXT_CX = NAME_TEXT_CX,
        NAME_TEXT_CY = NAME_TEXT_CY,
        SLIDER_H = SLIDER_H,
        SLIDER_W = SLIDER_W,
        SpineResultEffect = SpineResultEffect,
        TAB_ACTIVE_B = TAB_ACTIVE_B,
        TAB_ACTIVE_G = TAB_ACTIVE_G,
        TAB_ACTIVE_R = TAB_ACTIVE_R,
        TAB_ANIM_DURATION = TAB_ANIM_DURATION,
        TAB_BG_CX = TAB_BG_CX,
        TAB_BG_CY = TAB_BG_CY,
        TAB_BG_H = TAB_BG_H,
        TAB_BG_W = TAB_BG_W,
        TAB_FONT_SIZE = TAB_FONT_SIZE,
        TAB_INACTIVE_B = TAB_INACTIVE_B,
        TAB_INACTIVE_G = TAB_INACTIVE_G,
        TAB_INACTIVE_R = TAB_INACTIVE_R,
        TAB_ITEMS = TAB_ITEMS,
        TAB_MAP = TAB_MAP,
        TAB_TEXT_Y = TAB_TEXT_Y,
        TownPageChrome = TownPageChrome,
        UPPER_SLIDE_DIST = UPPER_SLIDE_DIST,
        decomposeRedDot = decomposeRedDot,
        drawImageCentered = drawImageCentered,
        drawTabContent = drawTabContent,
        drawUpperSlotContent = drawUpperSlotContent,
        easeInCubic = easeInCubic,
        easeInOutCubic = easeInOutCubic,
        easeOutCubic = easeOutCubic,
        SELECT_SLOT_CX = SELECT_SLOT_CX,
        SELECT_SLOT_CY = SELECT_SLOT_CY,
        imgBg = imgBg,
        imgIconUp = imgIconUp,
        imgLowerBg = imgLowerBg,
        imgNameBg = imgNameBg,
        imgTabBg = imgTabBg,
        getOnCloseCallback = function() return onCloseCallback_ end,
        setOnCloseCallback = function(v) onCloseCallback_ = v end,
        getOnOpenCallback = function() return onOpenCallback_ end,
        setOnOpenCallback = function(v) onOpenCallback_ = v end,
        state = state
    })
end

local function drawPageImpl(vg)
    bindPageDraw()
    return _pageDraw.drawPageImpl(vg)
end

--- 设置分解标签红点（背包满时由外部驱动）
---@param show boolean
function BlacksmithPage.setDecomposeRedDot(show)
    decomposeRedDot = show
end

--- 检查是否有任意装备（含背包）满足强化条件
--- 只要有一件当前金币+卷轴足够升一级就返回 true（城镇 Tab 角标用）
---@return boolean
function BlacksmithPage.canEnhanceAny()
    if not _enhCache then bindEnhanceCache() end
    return _enhCache.canEnhanceAny()
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

--- [水平滑入] 整页从屏幕边缘滑入/滑出(与中缝返回条同步);0=完全展开
function BlacksmithPage.getSeamAnim()
    return state.openTime, state.closeTime, ANIM_DURATION, CLOSE_ANIM_DURATION
end

function BlacksmithPage.draw(vg)
    local ot, ct, od, cd = BlacksmithPage.getSeamAnim()
    local ox = DrawUtil.seamSlideX(-1, ot, ct, od, cd, 1080)
    if ox ~= 0 then
        nvgSave(vg)
        nvgTranslate(vg, ox, 0)
    end
    drawPageImpl(vg)
    if ox ~= 0 then
        nvgRestore(vg)
    end
end

return BlacksmithPage
