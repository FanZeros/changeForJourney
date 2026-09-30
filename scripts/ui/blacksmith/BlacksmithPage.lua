-- ============================================================================
-- BlacksmithPage - 铁匠铺（狱火锻炉）界面
-- [锻炉双页 0929] 重构：
--   1. 分解 tab 已迁移到仓库（BackpackPanel"分解"tab，复用 BlacksmithDecompose）
--   2. 打开锻炉时自动在左栏打开仓库，锻炉本体移到中栏（双页面并排）
--   3. 强化/洗练共用一个"装备工作台槽"：从左侧仓库拖装备进来即选中，
--      原编队卡片 + 6 装备槽 + EquipmentBag 选择页全部移除
--   4. 页面从右缘滑入/滑出（dirSign=+1），取消竖栏（中缝返回条）在锻炉右侧
-- 子模块：BlacksmithEnhance / BlacksmithRefine
-- ============================================================================

local GameConfig       = require("config.GameConfig")
local GameState        = require("core.GameState")
local DarkIcon         = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质底框矢量绘制
local EquipmentDetail  = require("ui.character.equip.EquipmentDetail")
local ImageCache       = require("ui.widget.ImageCache")  -- 共享装备图标缓存（含组首图 fallback）
local EquipmentConfig  = require("config.EquipmentConfig")
local AffixConfig      = require("config.AffixConfig")
local AD               = require("systems.AttributeDef")
local ClientDispatcher = require("runtime.ClientDispatcher")
local PlayerStore      = require("core.PlayerStore")
local EquipmentSystem  = require("systems.EquipmentSystem")
local SpineResultEffect = require("ui.fx.SpineResultEffect")
local DrawUtil         = require("core.DrawUtil")
local TownPageChrome   = require("ui.town.TownPageChrome")
local ExpTable         = require("config.ExpTable")
local HeroAssetUtil    = require("config.HeroAssetUtil")
local HeroConfig       = require("config.HeroConfig")
local HeroFrame        = require("ui.widget.HeroFrame")
local I18n             = require("core.I18n")

-- 子模块（[锻炉双页 0929] BlacksmithDecompose 已迁至仓库分解 tab，不再由本页驱动）
local BlacksmithEnhance   = require("ui.blacksmith.BlacksmithEnhance")
local BlacksmithRefine    = require("ui.blacksmith.BlacksmithRefine")
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

-- 4. [锻炉双页 0929] 装备工作台槽（上半部分唯一槽位，强化/洗练共用）
-- 从左侧仓库拖装备到此槽即选中；已选中时点击可查看装备详情
local WORKBENCH_CX, WORKBENCH_CY = 540, 431
local WORKBENCH_SIZE    = 220
local WORKBENCH_RADIUS  = 24
local EQUIP_LV_FONT_SIZE = 38
local EQUIP_SLOT_ORDER   = { "weapon", "offhand", "armor", "helmet", "shoes", "accessory" }
local MAX_PARTY          = 5   -- BlacksmithEnhanceCache 仍按编队扫描可强化角标

-- 工作台槽几何（导出给 EquipCrossDrag 命中检测/高亮）
BlacksmithPage.WORKBENCH = {
    cx = WORKBENCH_CX, cy = WORKBENCH_CY, size = WORKBENCH_SIZE,
}

-- 7. 下方背景板
local LOWER_BG_CX, LOWER_BG_W, LOWER_BG_H = 540, 1080, 1670
local LOWER_BG_CY = DESIGN_H - LOWER_BG_H * 0.5  -- 2400 - 835 = 1565

-- 9. 页面选项滑块背景
local TAB_BG_CX, TAB_BG_CY = 540, 2308
local TAB_BG_W, TAB_BG_H   = 810, 143

-- 10. 两个滑块按钮位置（[锻炉双页 0929] 分解 tab 已迁移到仓库）
local TAB_ITEMS = {
    { name = "强化", cx = 340, cy = 2308 },
    { name = "洗练", cx = 740, cy = 2308 },
}

-- 11. 滑块按钮（九宫格）
local SLIDER_W, SLIDER_H = 410, 143

-- Tab 文本样式
local TAB_TEXT_Y          = 2302
local TAB_FONT_SIZE       = 40
local TAB_ACTIVE_R, TAB_ACTIVE_G, TAB_ACTIVE_B = 0xD8, 0xC9, 0xA3
local TAB_INACTIVE_R, TAB_INACTIVE_G, TAB_INACTIVE_B = 255, 255, 255

-- 动画
local TAB_ANIM_DURATION   = 0.35  -- Tab 切换动画时长
local ANIM_DURATION       = 0.45  -- 打开动画时长（seam 滑入）
local CLOSE_ANIM_DURATION = 0.38  -- 关闭动画时长（seam 滑出）
-- [双页方向 0930] 依次出现错峰：仓库(左栏)先滑入，锻炉(中栏)延迟此刻长再从左滑入。
-- seamSlideX 对 openTime 在未来时返回边缘位（t<=0 → dirSign*dist），天然支持延迟启动。
local OPEN_STAGGER        = 0.12

-- ======================== 状态 ========================

local onCloseCallback_ = nil  -- 关闭动画完成后的回调
local onOpenCallback_  = nil  -- 打开动画完成后的回调
--- [锻炉双页 0929] 打开锻炉时是否自动打开了左栏仓库（关闭时联动关闭）
local autoOpenedWarehouse_ = false

local state = {
    open       = false,
    closing    = false,
    openTime   = 0,
    closeTime  = 0,
    -- [锻炉双页 0929] 当前选中 Tab: "qianghua" | "xilian"（分解已迁至仓库）
    tab        = "qianghua",
    tabFrom    = "qianghua",
    tabSwitchTime = 0,
    -- [锻炉双页 0929] 工作台装备（由仓库拖入或预选）
    selectedPartySlot = 1,           -- 保留字段：BlacksmithEnhance 请求参数兼容（服务端优先 seq）
    selectedEquipSlot = "weapon",    -- 当前装备的部位 key（决定强化卷轴类型）
    selectedEquip = nil,
    selectedSeq   = nil,
    -- 洗练缓存：服务端返回的新词缀（用于"替换"按钮）
    pendingRefineAffixes = nil,
    pendingRefineSeq     = nil,
}

-- Tab 对应的标签项索引
local TAB_MAP = {
    qianghua = 1,
    xilian   = 2,
}

-- 装备品质消耗配置（用于洗练）
local QUALITY_COST = require("config.BlacksmithConfig").QUALITY_COST

local imgHeroIcons = {}    -- [heroId] = nvgImage handle, 角色头像角标（与背包一致）

-- ======================== 装备图标缓存 ========================

--- 装备图标：委托共享 ImageCache（含组首图 fallback——318 个模板 ID 共用 53 张组首图，
--- 非组首 ID 直接 nvgCreateImage 会失败返回 <=0 导致格子空白）
local function getEquipIconCached(templateId)
    return ImageCache.getEquipIcon(templateId)
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
local imgTabBg    = -1   -- UI_AN_1.png

local imgArrow    = -1   -- UI_TJP_JIANTOU.png（提升箭头）
local imgEnhBtn   = -1   -- UI_AN_LV.png（强化按钮背景）
local imgGoldIcon = -1   -- UI_icon_JB_X.png（金币图标）
local imgGoldQBg  = -1   -- UI_icon_ZBBJ_2.png（金币品质背景框, quality=2）
local imgEssenceIcon = -1 -- UI_icon_JC.png（精粹图标）
local imgXlBefore  = -1   -- UI_TJP_XL_2.png（洗练前/后共用单框背景）
local imgReplaceBtn = -1  -- UI_AN_HUANG.png（替换按钮背景）
local imgCheckmark = -1   -- UI_icon_GOU.png（选中打钩）
local imgLock      = -1   -- 锁定图标
local imgIconUp    = -1   -- ICON_UP.png（可强化角标）
-- 一键强化确认弹窗专用图片
local imgEnhDlgMinus = -1  -- UI_AN_JIAN.png（减按钮）
local imgEnhDlgPlus  = -1  -- UI_AN_JIA.png（加按钮）

local imgQualityBg = {}   -- UI_icon_ZBBJ_1~6（品质背景框，按品质索引）
local imgGrade = {}      -- 词缀等级图标 imgGrade["D"/"C"/"B"/"A"/"S"]

-- ======================== 缓动函数（TownPageChrome） ========================
local easeOutCubic   = TownPageChrome.easeOutCubic
local easeInCubic    = TownPageChrome.easeInCubic
local easeInOutCubic = TownPageChrome.easeInOutCubic

-- ======================== 工具函数 ========================

local drawImageCentered = DrawUtil.drawImageCentered
local drawTextStroke = DrawUtil.drawTextStroke
local drawNineSlice = DrawUtil.drawNineSlice
local hitTest = DrawUtil.hitTest

-- ======================== 工作台装备选择 ========================

--- 应用工作台装备（同步强化/洗练子模块）
---@param equip table|nil
local function applySelectedEquip(equip)
    if not equip then
        state.selectedEquip = nil
        state.selectedSeq = nil
        BlacksmithEnhance.updateEnhanceData(nil)
        BlacksmithRefine.updateRefineData(nil)
        return
    end
    EquipmentSystem.hydrate(equip)
    equip.seq = tonumber(equip.seq)
    state.selectedEquip = equip
    state.selectedSeq = equip.seq
    state.selectedEquipSlot = equip.slot or "weapon"
    BlacksmithEnhance.updateEnhanceData(equip)
    BlacksmithRefine.updateRefineData(equip)
end

--- 按 seq 从背包/已穿戴中查找装备并放入工作台（EquipCrossDrag 拖放入口）
---@param seq number|string
---@return boolean ok
function BlacksmithPage.setEquipBySeq(seq)
    local seqNum = tonumber(seq)
    if not seqNum then return false end
    local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    local equip = eqData and eqData.inventory and eqData.inventory[tostring(seqNum)]
    if not equip then
        print("[BlacksmithPage] setEquipBySeq: 装备不存在 seq=" .. tostring(seqNum))
        return false
    end
    equip.seq = seqNum
    applySelectedEquip(equip)
    print("[BlacksmithPage] 工作台放入装备 seq=" .. tostring(seqNum)
        .. " name=" .. tostring(equip.name) .. " slot=" .. tostring(state.selectedEquipSlot))
    return true
end

--- 直接设置工作台装备（EquipmentDetail"前往强化/洗练"预选入口）
---@param equip table|nil
function BlacksmithPage.setSelectedEquip(equip)
    applySelectedEquip(equip)
end

--- 工作台槽命中检测（设计坐标）
---@param dx number
---@param dy number
---@return boolean
function BlacksmithPage.hitWorkbench(dx, dy)
    return hitTest(dx, dy, WORKBENCH_CX, WORKBENCH_CY, WORKBENCH_SIZE, WORKBENCH_SIZE)
end

--- 默认工作台装备：优先编队英雄已穿戴的装备，其次背包第一件（保证教程"点击强化"可推进）
local function autoSelectDefaultEquip()
    local teamSlots = require("ui.character.panel.CharacterPanel").getTeamSlotsData()
    local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    if teamSlots and eqData and eqData.equipped then
        for partySlot = 1, MAX_PARTY do
            local slot = teamSlots[partySlot]
            if slot and slot.state == "occupied" and slot.heroId then
                local heroEquipped = EquipmentSystem.getHeroSlots(eqData, slot.heroId)
                if heroEquipped then
                    for _, slotKey in ipairs(EQUIP_SLOT_ORDER) do
                        local seq = heroEquipped[slotKey]
                        if seq and eqData.inventory and eqData.inventory[tostring(seq)] then
                            local equip = eqData.inventory[tostring(seq)]
                            equip.seq = tonumber(seq)
                            applySelectedEquip(equip)
                            print("[BlacksmithPage] 自动选中已穿戴装备 seq=" .. tostring(seq))
                            return
                        end
                    end
                end
            end
        end
    end
    -- 兜底：背包中第一件装备（按 seq 升序）
    if eqData and eqData.inventory then
        local bestSeq, bestEquip
        for seqStr, equip in pairs(eqData.inventory) do
            local seq = tonumber(seqStr)
            if seq and (not bestSeq or seq < bestSeq) then
                bestSeq, bestEquip = seq, equip
            end
        end
        if bestEquip then
            bestEquip.seq = bestSeq
            applySelectedEquip(bestEquip)
            print("[BlacksmithPage] 自动选中背包装备 seq=" .. tostring(bestSeq))
            return
        end
    end
    applySelectedEquip(nil)
    print("[BlacksmithPage] 无可用装备，工作台为空")
end

-- ======================== 可强化检查（供角标绘制使用） ========================

local _enhanceCache = {
    dirty = true,
    partyCanEnhance = {},
    slotCanEnhance  = {},
}

local _enhCache
local function bindEnhanceCache()
    _enhCache = BlacksmithEnhanceCache.bind({
        ClientDispatcher = ClientDispatcher,
        PlayerStore = PlayerStore,
        GameState = GameState,
        CharacterPanel = require("ui.character.panel.CharacterPanel"),
        ExpTable = ExpTable,
        BlacksmithEnhance = BlacksmithEnhance,
        EQUIP_SLOT_ORDER = EQUIP_SLOT_ORDER,
        MAX_PARTY = MAX_PARTY,
        cache = _enhanceCache,
    })
end

--- 标记可强化缓存为脏（数据变化时调用）
function BlacksmithPage.markEnhanceDirty()
    _enhanceCache.dirty = true
end

--- 检查是否有任意出战槽位的装备满足强化条件（城镇建筑角标/BottomNav 用）
---@return boolean
function BlacksmithPage.canEnhanceAny()
    if not _enhCache then bindEnhanceCache() end
    return _enhCache.canEnhanceAny()
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

-- ======================== 工作台槽绘制 ========================

--- 绘制装备工作台槽（上半部分，强化/洗练共用）
local function drawWorkbenchSlot(vg)
    local equip = state.selectedEquip
    local slotCX, slotCY, slotSize = WORKBENCH_CX, WORKBENCH_CY, WORKBENCH_SIZE

    if equip then
        -- 品质底框 + 装备图标 [暗黑化 P2-A]
        local qIdx = math.max(1, math.min(6, equip.quality or 1))
        DarkIcon.drawQualityBg(vg, qIdx, slotCX, slotCY, slotSize, slotSize, 1.0)
        local eqIcon = getEquipIconCached(equip.templateId)
        if eqIcon and eqIcon > 0 then
            DarkIcon.drawIconDark(vg, eqIcon, slotCX, slotCY, slotSize - 20, slotSize - 20, 1.0)
        end

        -- 升阶等级角标 "+N"（左上）
        local enhLv = EquipmentSystem.getAscendLevel(equip) or 0
        if enhLv > 0 then
            local lvX = slotCX - slotSize * 0.5 + 6
            local lvY = slotCY - slotSize * 0.5 + 26
            drawTextStroke(vg, lvX, lvY, "+" .. enhLv,
                EQUIP_LV_FONT_SIZE, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                0x67, 0xff, 0x75, 5)
        end

        -- 装备等级角标 "Lv.X"（右下）
        local eqLv = equip.level or 1
        if eqLv >= 1 then
            local lvlText = "Lv." .. eqLv
            local lvlX = slotCX + slotSize * 0.5 - 10
            local lvlY = slotCY + slotSize * 0.5 - 8
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
        drawTextStroke(vg, slotCX, slotCY + slotSize * 0.5 + 34, name,
            36, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)

        -- 归属行（装备名下方）：已装备英雄 或 背包未装备提示
        local ownerHeroId = getEquipOwnerHeroId(equip)
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
            slotSize + 6, slotSize + 6, WORKBENCH_RADIUS)
        nvgStrokeColor(vg, nvgRGBA(0xff, 0xd7, 0x00, 200))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    else
        -- 空状态：黑色半透明圆角矩形 + 加号 + 拖拽提示
        nvgBeginPath(vg)
        nvgRoundedRect(vg, slotCX - slotSize * 0.5, slotCY - slotSize * 0.5,
            slotSize, slotSize, WORKBENCH_RADIUS)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 214, 102, 120))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)

        drawImageCentered(vg, imgPlus, slotCX, slotCY - 10, 72, 72, 0.5)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 150))
        nvgText(vg, slotCX, slotCY + 62, "拖入装备", nil)

        nvgFontFace(vg, "sans")
        drawTextStroke(vg, slotCX, slotCY + slotSize * 0.5 + 34, "从左侧仓库拖拽装备到工作台",
            30, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            0xb6, 0xb0, 0x9d, 3)
    end
end

--- 绘制下半部分 Tab 面板内容（按 tab 类型）
local function drawTabContent(vg, tabName)
    -- 强化/洗练：未选中装备时显示提示文本
    if not state.selectedEquip then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 40)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x99, 0x99, 0x99, 180))
        nvgText(vg, 540, 1200, "请先从左侧仓库拖入装备", nil)
        return
    end
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
    imgTabBg    = nvgCreateImage(vg, "image/按钮/UI_AN_1.png", 0)
    imgArrow    = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_JIANTOU.png", 0)
    imgEnhBtn   = nvgCreateImage(vg, "image/按钮/UI_AN_LV.png", 0)
    imgGoldIcon = nvgCreateImage(vg, "image/货币道具/UI_icon_JB_X.png", 0)
    imgGoldQBg  = nvgCreateImage(vg, "image/品质框/UI_icon_ZBBJ_2.png", 0)
    imgEssenceIcon = nvgCreateImage(vg, "image/货币道具/UI_icon_JC.png", 0)
    imgXlBefore  = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_XL_2.png", 0)
    imgReplaceBtn = nvgCreateImage(vg, "image/按钮/UI_AN_HUANG.png", 0)
    imgCheckmark = nvgCreateImage(vg, "image/货币道具/UI_icon_GOU.png", 0)
    imgLock       = nvgCreateImage(vg, "image/通用图标/UI_ICON_SUO.png", 0)
    imgIconUp     = nvgCreateImage(vg, "image/通用图标/ICON_UP.png", 0)
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

    ImageCache.init(vg)  -- 幂等：背包面板启动时也 init 同一 vg
    HeroAssetUtil.preloadIcons(vg, imgHeroIcons)

    -- 构建共享上下文并注入子模块
    local ctx = {
        state            = state,
        QUALITY_COST     = QUALITY_COST,
        imgArrow         = imgArrow,
        imgEnhBtn        = imgEnhBtn,
        imgGoldIcon      = imgGoldIcon,
        imgGoldQBg       = imgGoldQBg,
        imgEssenceIcon   = imgEssenceIcon,
        imgXlBefore      = imgXlBefore,
        imgReplaceBtn    = imgReplaceBtn,
        imgPlus          = imgPlus,
        imgLock          = imgLock,
        imgBtnYellow     = imgReplaceBtn,
        imgBtnMinus      = imgEnhDlgMinus,
        imgBtnPlus       = imgEnhDlgPlus,
        imgCheckmark     = imgCheckmark,
        imgGrade         = imgGrade,
        imgQualityBg     = imgQualityBg,
        getEquipIconCached = getEquipIconCached,
        formatCompact      = formatCompact,
        formatAffixValue   = formatAffixValue,
        drawNineSlice      = drawNineSlice,
        getClient          = getClient,
        getProtocol        = getProtocol,
    }

    BlacksmithEnhance.setContext(ctx)
    BlacksmithRefine.setContext(ctx)

    BlacksmithEnhance.init(vg)
    BlacksmithRefine.init(vg)

    -- 装备或货币变化时刷新可强化角标缓存
    PlayerStore.Subscribe("equipment", function()
        _enhanceCache.dirty = true
    end)
    PlayerStore.Subscribe("currency", function()
        _enhanceCache.dirty = true
    end)

    print("[BlacksmithPage] init OK")
end

--- [锻炉双页 0929] 关闭其他左栏二级页（锻炉+仓库占据左/中栏前的清场）
local function closeOtherLeftPages()
    local pages = {
        require("ui.loot.LootBoxPage"),
        require("ui.story.task.TaskPage"),
        require("ui.church.talent.TalentPage"),
        require("ui.church.ChurchPage"),
        require("ui.tavern.TavernPage"),
        require("ui.market.MarketPage"),
    }
    for _, mod in ipairs(pages) do
        if mod and mod.isOpen and mod.isOpen() then
            if mod.forceClose then mod.forceClose() else mod.close() end
            print("[BlacksmithPage] 双页清场: 关闭左栏二级页")
        end
    end
    -- 古树宽布局必须立即复位，否则宿主输入映射仍按宽页处理
    local TalentPage = require("ui.church.talent.TalentPage")
    if TalentPage.resetHorizonLayout then TalentPage.resetHorizonLayout() end
end

--- 打开铁匠铺（[锻炉双页 0929] 自动联动打开左栏仓库）
---@param preSelectEquip table|nil 预选装备（从装备详情跳转时传入）
---@param initialTab string|nil 初始 tab："qianghua"|"xilian"，默认 "qianghua"
function BlacksmithPage.open(preSelectEquip, initialTab)
    if not blacksmithInited_ and blacksmithVg_ then
        BlacksmithPage.init(blacksmithVg_)
    end
    if not blacksmithInited_ then
        print("[BlacksmithPage] open before init, skip")
        return
    end
    closeOtherLeftPages()
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    _enhanceCache.dirty = true
    require("systems.GameSFX").playUIMove(1)
    local tab = (initialTab == "xilian") and "xilian" or "qianghua"
    state.tab = tab
    state.tabFrom = tab
    state.tabSwitchTime = 0

    -- 工作台装备：预选优先，否则自动挑一件（教程"点击强化"依赖非空工作台）
    if preSelectEquip then
        applySelectedEquip(preSelectEquip)
        print("[BlacksmithPage] 打开铁匠铺 tab=" .. tab
            .. "（预选装备: " .. (preSelectEquip.name or "?") .. "）")
    else
        autoSelectDefaultEquip()
        print("[BlacksmithPage] 打开铁匠铺 tab=" .. tab)
    end
    BlacksmithEnhance.onOpen()

    -- [锻炉双页 0929] 左栏自动打开仓库（装备 tab，供拖拽）
    local BackpackPanel = require("ui.backpack.BackpackPanel")
    if not BackpackPanel.isOpen() then
        BackpackPanel.open("left")
        autoOpenedWarehouse_ = true
        print("[BlacksmithPage] 双页联动：自动打开左栏仓库")
    else
        autoOpenedWarehouse_ = false
    end
end

--- [锻炉双页 0929] 联动关闭自动打开的仓库
local function closeAutoWarehouse()
    if not autoOpenedWarehouse_ then return end
    autoOpenedWarehouse_ = false
    local BackpackPanel = require("ui.backpack.BackpackPanel")
    if BackpackPanel.isOpen() then
        BackpackPanel.close()
        print("[BlacksmithPage] 双页联动：关闭左栏仓库")
    end
end

--- 关闭铁匠铺（启动关闭动画；动画完成后联动关闭仓库）
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
    closeAutoWarehouse()
end

--- 装备数据更新（服务端推送）
function BlacksmithPage.onEquipmentDataUpdate(equipmentData)
    if not state.open then return end
    -- 工作台装备按 seq 刷新（可能已被分解/替换）
    if state.selectedSeq then
        local eqData = equipmentData or ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
        local refreshed = eqData and eqData.inventory and eqData.inventory[tostring(state.selectedSeq)]
        if refreshed then
            refreshed.seq = state.selectedSeq
            if state.tab == "xilian" and BlacksmithRefine.hasPreview() then
                state.selectedEquip = refreshed
                BlacksmithRefine.refreshCostOnly()
            else
                applySelectedEquip(refreshed)
            end
        else
            print("[BlacksmithPage] 工作台装备 seq=" .. tostring(state.selectedSeq) .. " 已不存在，清空")
            applySelectedEquip(nil)
        end
    end
    _enhanceCache.dirty = true
end

--- 服务端 action 结果（强化/洗练）
---@param data table
function BlacksmithPage.onActionResult(data)
    if not state.open then return end
    _enhanceCache.dirty = true

    -- 失败响应（无特定字段）→ 按当前 Tab 转发释放门控
    if not data.enhanceOutcome and not data.refinePreview and not data.refineReplaced then
        if state.tab == "qianghua" then
            BlacksmithEnhance.onActionResult(data)
        elseif state.tab == "xilian" then
            BlacksmithRefine.onActionResult(data)
        end
        return
    end
    if data.enhanceOutcome then
        BlacksmithEnhance.onActionResult(data)
    end
    if data.refinePreview or data.refineReplaced then
        BlacksmithRefine.onActionResult(data)
    end
end

-- ======================== 输入 ========================

local _input
local function bindInput()
    _input = require("ui.blacksmith.BlacksmithInput").bind({
        BlacksmithEnhance = BlacksmithEnhance,
        BlacksmithRefine = BlacksmithRefine,
        TAB_ITEMS = TAB_ITEMS,
        state = state,
        forceClose = BlacksmithPage.forceClose,
        closePage = BlacksmithPage.close,
        SLIDER_W = SLIDER_W,
        SLIDER_H = SLIDER_H,
        hitTest = hitTest,
        WORKBENCH_CX = WORKBENCH_CX,
        WORKBENCH_CY = WORKBENCH_CY,
        WORKBENCH_SIZE = WORKBENCH_SIZE,
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

-- ======================== 绘制 ========================

local _pageDraw
local function bindPageDraw()
    _pageDraw = require("ui.blacksmith.BlacksmithDraw").bind({
        ANIM_DURATION = ANIM_DURATION,
        BG_CX = BG_CX, BG_CY = BG_CY, BG_W = BG_W, BG_H = BG_H,
        BlacksmithEnhance = BlacksmithEnhance,
        BlacksmithPage = BlacksmithPage,
        CLOSE_ANIM_DURATION = CLOSE_ANIM_DURATION,
        DESIGN_W = DESIGN_W, DESIGN_H = DESIGN_H,
        DarkIcon = DarkIcon,
        DrawUtil = DrawUtil,
        I18n = I18n,
        LOWER_BG_CX = LOWER_BG_CX, LOWER_BG_CY = LOWER_BG_CY,
        LOWER_BG_W = LOWER_BG_W, LOWER_BG_H = LOWER_BG_H,
        NAME_FONT_SIZE = NAME_FONT_SIZE,
        NAME_TEXT_CX = NAME_TEXT_CX, NAME_TEXT_CY = NAME_TEXT_CY,
        SLIDER_W = SLIDER_W, SLIDER_H = SLIDER_H,
        SpineResultEffect = SpineResultEffect,
        TAB_ACTIVE_R = TAB_ACTIVE_R, TAB_ACTIVE_G = TAB_ACTIVE_G, TAB_ACTIVE_B = TAB_ACTIVE_B,
        TAB_ANIM_DURATION = TAB_ANIM_DURATION,
        TAB_BG_CX = TAB_BG_CX, TAB_BG_CY = TAB_BG_CY, TAB_BG_W = TAB_BG_W, TAB_BG_H = TAB_BG_H,
        TAB_FONT_SIZE = TAB_FONT_SIZE,
        TAB_INACTIVE_R = TAB_INACTIVE_R, TAB_INACTIVE_G = TAB_INACTIVE_G, TAB_INACTIVE_B = TAB_INACTIVE_B,
        TAB_ITEMS = TAB_ITEMS,
        TAB_MAP = TAB_MAP,
        TAB_TEXT_Y = TAB_TEXT_Y,
        TownPageChrome = TownPageChrome,
        drawImageCentered = drawImageCentered,
        drawTextStroke = drawTextStroke,
        drawTabContent = drawTabContent,
        drawWorkbenchSlot = drawWorkbenchSlot,
        easeInCubic = easeInCubic,
        easeInOutCubic = easeInOutCubic,
        easeOutCubic = easeOutCubic,
        getEquipIconCached = getEquipIconCached,
        imgBg = imgBg,
        imgIconUp = imgIconUp,
        imgLowerBg = imgLowerBg,
        imgNameBg = imgNameBg,
        imgTabBg = imgTabBg,
        WORKBENCH_CX = WORKBENCH_CX, WORKBENCH_CY = WORKBENCH_CY,
        getOnCloseCallback = function() return onCloseCallback_ end,
        setOnCloseCallback = function(v) onCloseCallback_ = v end,
        getOnOpenCallback = function() return onOpenCallback_ end,
        setOnOpenCallback = function(v) onOpenCallback_ = v end,
        closeAutoWarehouse = closeAutoWarehouse,
        state = state,
    })
end

--- [水平滑入] 整页从左缘滑入/滑出（与锻炉右侧中缝返回条同步）；0=完全展开
--- [双页方向 0930] openTime 附加错峰延迟：仓库(左栏)先滑入，锻炉随后从左滑入，
--- 双页整体呈"从左到右依次出现"；关闭仍按 closeTime 立即滑出(向左)。
function BlacksmithPage.getSeamAnim()
    return state.openTime + OPEN_STAGGER, state.closeTime, ANIM_DURATION, CLOSE_ANIM_DURATION
end

function BlacksmithPage.draw(vg)
    local ot, ct, od, cd = BlacksmithPage.getSeamAnim()
    -- [双页方向 0930] dirSign=-1：双页都属左栏组，锻炉也从左缘滑入/滑出（返回方向反转）
    local ox = DrawUtil.seamSlideX(-1, ot, ct, od, cd, 1080)
    if ox ~= 0 then
        nvgSave(vg)
        nvgTranslate(vg, ox, 0)
    end
    bindPageDraw()
    _pageDraw.drawPageImpl(vg)
    if ox ~= 0 then
        nvgRestore(vg)
    end
end

--- 设置分解标签红点（[锻炉双页 0929] 分解已迁至仓库，保留接口兼容旧调用，改为无操作）
---@param show boolean
function BlacksmithPage.setDecomposeRedDot(show)
    -- no-op：红点改由 TownScene 仓库建筑呈现
end

return BlacksmithPage
