-- ============================================================================
-- EquipmentDetail - 装备详情面板
-- 从 EquipmentBag 的格子点击打开
-- 展示双面板对比（当前已穿戴 vs 新装备），支持穿戴/更换
-- 像素精确布局，所有坐标基于设计分辨率 1080×2400
-- ============================================================================

local EquipmentConfig  = require("config.EquipmentConfig")
local EquipmentSystem  = require("systems.EquipmentSystem")
local EquipmentPower   = require("systems.EquipmentPower")
local EquipmentSetConfig = require("config.EquipmentSetConfig")
local EquipmentSetSystem = require("systems.EquipmentSetSystem")
local AffixConfig      = require("config.AffixConfig")
local AD               = require("systems.AttributeDef")
local GameConfig       = require("config.GameConfig")
local PlayerStore      = require("core.PlayerStore")
local HC               = require("config.HeroConfig")
local ImageCache       = require("ui.widget.ImageCache")
local EquipmentSetIcon = require("ui.widget.EquipmentSetIcon")
local BF               = require("systems.ButtonFeedback")
local DarkIcon         = require("core.DarkIcon")  -- [暗黑化 P1-B5] 矢量九宫格
local ExpTable         = require("config.ExpTable")
local GameState        = require("core.GameState")
local TutorialManager  = require("systems.TutorialManager")
local I18n             = require("core.I18n")
local EquipmentDetailDraw = require("ui.character.equip.EquipmentDetailDraw")

local BlacksmithConfig = require("config.BlacksmithConfig")
local KeywordText      = require("ui.widget.KeywordText")

local EquipmentDetail = {}

-- 套装词条关键词富文本（2件/4件/6件 三行各一实例；仅主面板交互，
-- 绘制与输入同在 compact 0.92 变换坐标系，热区天然对齐，无需 setTransform）
local setKw = {
    KeywordText.new(), KeywordText.new(), KeywordText.new(),
}
local affixKw = KeywordText.new()
local keywordDismissGesture = false -- 按下时说明已打开：即使微抖动/重绘关泡，松手仍只消费说明。

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 状态 ========================

local detState = {
    open      = false,
    closing   = false,
    equipSeq  = nil,    -- 点击的背包装备 seq (string)
    slot      = nil,    -- 槽位 "weapon"|"offhand"|"armor"|"accessory"
    heroId    = nil,    -- 当前角色 ID
    openTime  = 0,
    closeTime = 0,
    compactCorner = false, -- 小窗以装备格子的上角定位：右栏向左、左栏向右展开
    owner = nil,           -- backpack | character | bag | smith，只在打开它的那一侧画
    descScrollY = 0,
    descScrollMax = 0,
    descDragging = false,
    descDragLastY = 0,
    -- 关闭动画快照（close() 时冻结，防止 server 推送导致面板内容跳变）
    snapshot  = nil,    -- { newEquip, isEquipped, curEquip, hasCurrent, btnKey, powerDiff }
}

-- ======================== 动画常量 ========================

local ANIM_OPEN_DUR  = 0.25
local ANIM_CLOSE_DUR = 0.20
local SLIDE_DIST     = 800   -- 从下方滑入的距离

-- 前向声明（close() 中需要在定义之前引用）
local isClickedEquipEquipped
local getComparisonEquip

local function easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 品质边框/文本颜色 ========================
-- [B-方案] 统一引用 DarkIcon.QUALITY_TRIM 古卷色表
local QUALITY_COLOR = DarkIcon.QUALITY_TRIM

-- 词缀品质名 → 图片key映射
local AFFIX_BADGE_KEY = { "D", "C", "B", "A", "S" }

-- ======================== 图片资源 ========================

local imgPowerIcon   = -1
local imgArrowUp     = -1
local imgArrowDown   = -1
local imgBtnGreen    = -1
local imgBtnRed      = -1   -- UI_AN_HONG.png（立即分解按钮）
local imgLock        = -1   -- UI_ICON_SUO.png（装备锁定图标）
local imgAffixBadge  = {}   -- { D=handle, C=handle, ... }
-- 装备图标缓存已迁移至 ImageCache 共享模块（LRU 淘汰，防止 VRAM 累积）

-- ======================== Lazy-load Client ========================

---@type table|nil
local _cachedClient = nil

local function getClient()
    if not _cachedClient then
        _cachedClient = require("runtime.GameAction")
    end
    return _cachedClient
end

---@type table|nil
local _cachedProtocol = nil

local function getProtocol()
    if not _cachedProtocol then
        _cachedProtocol = require("shared.Protocol")
    end
    return _cachedProtocol
end

-- ======================== 工具函数 ========================

--- 居中绘制图片
local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 or alpha <= 0.01 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    ---@cast paint NVGpaint
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 点击测试（中心坐标+尺寸）
local function hitTest(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

--- 描边文字（16方向采样）
local drawTextStroke = require("core.DrawUtil").drawTextStroke

-- ======================== 战斗力计算 ========================

-- 角色分与自动配装共用实际换装评估；未选角色保留通用展示价值。
local function calcEquipPower(equip, heroId, slot)
    return EquipmentPower.score(equip, heroId, slot)
end

local function replacementGain(equip)
    if not equip or not detState.heroId then return 0 end
    local context = EquipmentPower.getContext(detState.heroId)
    local result = EquipmentPower.evaluate(context, detState.equipSeq, detState.slot or equip.slot)
    return result and result.valid and result.gain or 0
end

-- ======================== 属性格式化 ========================

--- 格式化属性值为显示文本
---@param key string 属性 key
---@param value number
---@return string
local function formatStatValue(key, value)
    local meta = AD.META[key]
    if not meta then return string.format("%.1f", value) end

    if meta.dataType == AD.TYPE_PCT then
        return string.format("%.1f%%", value)
    elseif meta.dataType == AD.TYPE_INT then
        return tostring(math.floor(value))
    else
        return string.format("%.1f", value)
    end
end

--- 获取属性中文名
---@param key string
---@return string
local function getStatName(key)
    local meta = AD.META[key]
    return I18n.lookup(meta and meta.name or key)
end

-- ======================== 新装备面板参考坐标（绝对值） ========================
-- 所有 X,Y 为中心坐标（用于 hitTest、drawImageCentered）
-- 文本坐标用 NVG_ALIGN_LEFT/RIGHT + NVG_ALIGN_MIDDLE

-- 面板背景
local REF_BG_CX  = 805
local REF_BG_CY  = 1120
local REF_BG_W   = 860
local REF_BG_H   = 1380
-- 小窗按实际内容收紧。旧 1380 高把按钮压出框，并在词条下方留下大片空白。
local COMPACT_BG_W = 600
local COMPACT_BTN_H = 64
local COMPACT_BTN_GAP = 14
local COMPACT_BTN_W = 300   -- [UI 0930] 按钮收窄（原 COMPACT_BG_W - 56 过宽）

-- 装备名称（左对齐）
local REF_NAME_X = 470    -- 左对齐基准
local REF_NAME_Y = 625
local REF_NAME_FONT = 40

-- 装备类型
local REF_TYPE_X = 470
local REF_TYPE_Y = 706
local REF_TYPE_FONT = 30

-- 品质文本
local REF_QUALITY_X = 470
local REF_QUALITY_Y = 861
local REF_QUALITY_FONT = 30

-- 装备图标
local REF_ICON_CX = 903
local REF_ICON_CY = 809
local REF_ICON_SIZE = 290

-- 战斗力图标
local REF_POWER_ICON_CX = 596
local REF_POWER_ICON_CY = 917

-- 战斗力数值
local REF_POWER_VAL_X = 622
local REF_POWER_VAL_Y = 917
local REF_POWER_VAL_FONT = 42

-- 提升/下降箭头
local REF_ARROW_SIZE = 48
local REF_ARROW_GAP  = 12  -- 战斗力文本右边12像素

-- 等级背景框
local REF_LV_BG_CX  = 961
local REF_LV_BG_CY  = 917
local REF_LV_BG_W   = 142
local REF_LV_BG_H   = 42
local REF_LV_BG_RAD  = 21
local REF_LV_FONT   = 30

-- 基础属性栏
local REF_STAT_BG_CX  = 805
local REF_STAT_BG_Y0  = 1007   -- 第一行中心Y
local REF_STAT_BG_W   = 740
local REF_STAT_BG_H   = 60
local REF_STAT_BG_RAD = 14
local REF_STAT_GAP    = 12     -- 多条属性间距
local REF_STAT_TEXT_X  = 470   -- 左对齐
local REF_STAT_VAL_X   = 1148  -- 右对齐
local REF_STAT_FONT   = 34

-- 随机属性标题
local REF_AFFIX_TITLE_X = 470
local REF_AFFIX_TITLE_Y = 1206
local REF_AFFIX_TITLE_FONT = 30

-- 随机属性行：独立名称/数值配色，左侧保留词条稀有度徽章。
local REF_AFFIX_TEXT_X  = 636   -- 左对齐（缩进，留出徽章空间）
local REF_AFFIX_GAP_TOP = 15    -- 与"随机属性"标题下方间距
local REF_AFFIX_GAP     = 15    -- 多条随机属性间距（含背景）
local REF_AFFIX_ROW_H   = 60    -- 行高与基础属性一致

-- 品质标识徽章
local REF_BADGE_CX   = 611
local REF_BADGE_Y0   = 1264   -- 第一条徽章中心Y
local REF_BADGE_W    = 36
local REF_BADGE_H    = 44

-- 穿戴按钮
local REF_BTN_CX  = 807
local REF_BTN_CY  = 1461
local REF_BTN_W   = 410
local REF_BTN_H   = 100
local REF_BTN_FONT = 40

-- 立即分解按钮（背景底边下方 18px；无穿戴按钮时放在框内）
local REF_DEC_BTN_GAP  = 18
local REF_DEC_BTN_W    = 300
local REF_DEC_BTN_H    = 100
local REF_DEC_BTN_FONT = 40

-- 当前装备面板（顶部与新装备面板对齐）
local CUR_BG_CX = 274
local CUR_BG_W  = 530
local CUR_BG_H  = 850
-- 新面板顶部 = REF_BG_CY - REF_BG_H*0.5 = 564.5
-- 当前面板CY = 564.5 + CUR_BG_H*0.5 = 989.5 → 取整
local CUR_BG_CY = math.floor(REF_BG_CY - REF_BG_H * 0.5 + CUR_BG_H * 0.5)

-- 单面板居中
local SINGLE_BG_CX = 540

-- 小窗以装备格子的上角定位，比较卡向外侧排列。
local COMPACT_SCALE = 0.92
local COMPACT_MARGIN = 16

local COMPACT_PAD_TOP = 28
local COMPACT_NAME_Y = 34
local COMPACT_TYPE_Y = 78
local COMPACT_QUALITY_Y = 122
local COMPACT_ICON_CY = 168
local COMPACT_ICON_SIZE = 132
local COMPACT_STAT_Y0 = 248
local COMPACT_CONTENT_BOTTOM_PAD = 24
local COMPACT_AFFIX_TITLE_FONT = 26
local COMPACT_AFFIX_GAP = 8

--- 小窗随机标题、首行与内容底部共用计算，绘制/套装/按钮/命中范围不能各算一份。
---@param equip table|nil
---@return number titleY, number firstAffixY, number contentBottom
local function compactAffixLayout(equip)
    -- 稀有度下方 Lv 行（中心 +40，字号 28）的完整底部，无主属性时也不能被词条覆盖。
    local bottom = COMPACT_QUALITY_Y + 58
    local statCount = equip and equip.baseStats and #equip.baseStats or 0
    if statCount > 0 then
        bottom = COMPACT_STAT_Y0 + (statCount - 1) * (REF_STAT_BG_H + REF_STAT_GAP)
            + REF_STAT_BG_H * 0.5
    end
    local titleY = bottom + 16 + COMPACT_AFFIX_TITLE_FONT * 0.5
    local firstAffixY = titleY + COMPACT_AFFIX_TITLE_FONT * 0.5 + 12 + REF_AFFIX_ROW_H * 0.5
    local affixCount = equip and equip.affixes and #equip.affixes or 0
    if affixCount > 0 then
        bottom = firstAffixY + (affixCount - 1) * (REF_AFFIX_ROW_H + COMPACT_AFFIX_GAP)
            + REF_AFFIX_ROW_H * 0.5
    end
    return titleY, firstAffixY, bottom + COMPACT_CONTENT_BOTTOM_PAD
end

--- 小窗内容底部：与随机属性实际绘制位置同源，不再遗漏随机标题高度。
---@param equip table|nil
---@return number
local function compactContentBottom(equip)
    return select(3, compactAffixLayout(equip))
end

local SET_TITLE_H = 42
local SET_ROW_H = 36
local SET_GAP = 10

local function compactSetRowHeight(line)
    local chars = utf8.len(I18n.lookup(line.desc or "")) or 0
    local lines = math.max(1, math.ceil(chars / 16))
    return 8 + lines * 32
end

local function compactSetLines(equip)
    local tpl = EquipmentConfig.ITEMS[equip and equip.templateId]
        or EquipmentConfig.ITEMS[equip and tostring(equip.templateId)]
    local setId = EquipmentSetConfig.getSetIdForTemplate(tpl)
    local def = setId and EquipmentSetConfig.get(setId) or nil
    if not def then return nil, {} end
    local count = 0
    local twoActive, fourActive, sixActive = false, false, false
    local eqData = PlayerStore.Get("equipment")
    if eqData and detState.heroId then
        local counts = EquipmentSetSystem.countSets(
            eqData, detState.heroId,
            EquipmentSystem.getFromInventory,
            function(data, hid) return EquipmentSystem.getHeroSlots(data, hid) end)
        count = counts[setId] or 0
        local rows = EquipmentSetSystem.summarize(counts)
        for i = 1, #rows do
            local row = rows[i]
            if row.setId == setId then
                twoActive, fourActive, sixActive = row.twoActive, row.fourActive, row.sixActive
                break
            end
        end
    end
    local lines = {
        { text = I18n.format("%s  %d/6", I18n.lookup(def.name), count), active = true },
        { tier = 2, desc = def.desc2 or "", active = twoActive },
        { tier = 4, desc = def.desc4 or "", active = fourActive },
        { tier = 6, desc = def.desc6 or "", active = sixActive },
    }
    return def, lines
end

local function compactSetBlockHeight(equip)
    local _, lines = compactSetLines(equip)
    if #lines == 0 then return 0 end
    local height = SET_GAP + SET_TITLE_H + 8
    for i = 2, #lines do
        height = height + compactSetRowHeight(lines[i])
    end
    return height
end

local function compactViewHeight(equip, withButtons)
    local contentBottom = compactContentBottom(equip)
    local setH = compactSetBlockHeight(equip)
    if not withButtons or detState.slot == nil then
        return math.max(360, contentBottom + setH + 18)
    end
    return math.max(430, contentBottom + setH + COMPACT_BTN_GAP + COMPACT_BTN_H + 18)
end

local function compactCompareEquip()
    if not detState.open or detState.slot == nil then return nil end
    if isClickedEquipEquipped() then return nil end
    return getComparisonEquip()
end

local function compactVisSize()
    local h = compactViewHeight(detState.layoutEquip, true)
    local compare = compactCompareEquip()
    if compare then h = math.max(h, compactViewHeight(compare, false)) end
    return COMPACT_BG_W * COMPACT_SCALE, h * COMPACT_SCALE
end

--- 小窗穿戴/卸下按钮：贴在最后一条内容下方，完整留在框内。
---@return number wearCY, number cx, number w, number h
local function compactButtonRow()
    local panelH = compactViewHeight(detState.layoutEquip, true)
    local h = COMPACT_BTN_H
    return panelH - 18 - h * 0.5, REF_BG_CX, COMPACT_BTN_W, h
end

local function compactOffset()
    local refLeft = REF_BG_CX - COMPACT_BG_W * 0.5
    local visW, visH = compactVisSize()
    local ax = detState.anchorX or 540
    local ay = detState.anchorY or 1144
    local toLeft = detState.owner == "character"
    local targetLeft = toLeft and (ax - 12 - visW) or (ax + 12)
    local targetTop = math.max(COMPACT_MARGIN, math.min(ay,
        DESIGN_H - COMPACT_MARGIN - visH))
    return targetLeft - refLeft * COMPACT_SCALE, targetTop
end

local DESC_TOP = 980
local DESC_BTN_LIMIT_PAD = 150

local function pinnedBtnCY()
    return REF_BG_CY + REF_BG_H * 0.5 - DESC_BTN_LIMIT_PAD
end

--- 说明区超出底板时，按钮钉在框内，多出来的部分靠 descScrollY 下滚
local function layoutButtons(equip)
    local btnCY = REF_BTN_CY
    if equip and equip.affixes and #equip.affixes > 0 then
        local baseStatCount = equip.baseStats and #equip.baseStats or 0
        local affixTitleY = REF_AFFIX_TITLE_Y
        if baseStatCount ~= 0 then
            local baseStatEndY = REF_STAT_BG_Y0 + (baseStatCount - 1) * (REF_STAT_BG_H + REF_STAT_GAP) + REF_STAT_BG_H * 0.5
            if affixTitleY < baseStatEndY + 30 then
                affixTitleY = baseStatEndY + 30
            end
        end
        local lastAffixY = affixTitleY + REF_AFFIX_TITLE_FONT * 0.5 + REF_AFFIX_GAP_TOP + REF_AFFIX_ROW_H * 0.5
            + (#equip.affixes - 1) * (REF_AFFIX_ROW_H + REF_AFFIX_GAP)
        local natural = lastAffixY + REF_AFFIX_ROW_H * 0.5 + 40
        if btnCY < natural then btnCY = natural end
    end
    local limit = pinnedBtnCY()
    local scrollMax = math.max(0, btnCY - limit)
    if btnCY > limit then btnCY = limit end
    return btnCY, scrollMax
end

local function clampDescScroll()
    if detState.descScrollY < 0 then detState.descScrollY = 0 end
    if detState.descScrollY > detState.descScrollMax then
        detState.descScrollY = detState.descScrollMax
    end
end

-- ======================== 面板绘制（绝对坐标 + X偏移） ========================

--- 获取装备图标（委托 ImageCache 共享缓存）
---@param templateId string 模板 ID（如 "W1"）
---@return number nvgImage handle (-1 if failed)
local function getEquipIcon(templateId)
    return ImageCache.getEquipIcon(templateId)
end

-- 绘制分区：共用活状态和 KeywordText；图片 getter 保证 init 之后的句柄可见。
local panelDraw = EquipmentDetailDraw.create({
    detState = detState, setKw = setKw, affixKw = affixKw,
    qualityColor = QUALITY_COLOR, affixBadgeKey = AFFIX_BADGE_KEY,
    ---@return EquipmentDetailDrawImages
    getImages = function()
        return {
            powerIcon = imgPowerIcon, arrowUp = imgArrowUp, arrowDown = imgArrowDown,
            btnGreen = imgBtnGreen, btnRed = imgBtnRed,
            lock = imgLock, affixBadge = imgAffixBadge,
        }
    end,
    drawImageCentered = drawImageCentered,
    drawTextStroke = drawTextStroke,
    calcEquipPower = calcEquipPower,
    getEquipIcon = getEquipIcon,
    getStatName = getStatName,
    formatStatValue = formatStatValue,
    layoutButtons = layoutButtons,
    clampDescScroll = clampDescScroll,
    compactViewHeight = compactViewHeight,
    compactAffixLayout = compactAffixLayout,
    compactSetLines = compactSetLines,
    compactSetRowHeight = compactSetRowHeight,
    compactContentBottom = compactContentBottom,
    compactButtonRow = compactButtonRow,
    layout = {
        COMPACT_BG_W = COMPACT_BG_W,
        COMPACT_AFFIX_TITLE_FONT = COMPACT_AFFIX_TITLE_FONT,
        COMPACT_AFFIX_GAP = COMPACT_AFFIX_GAP,
        COMPACT_ICON_CY = COMPACT_ICON_CY,
        COMPACT_ICON_SIZE = COMPACT_ICON_SIZE,
        COMPACT_NAME_Y = COMPACT_NAME_Y,
        COMPACT_PAD_TOP = COMPACT_PAD_TOP,
        COMPACT_QUALITY_Y = COMPACT_QUALITY_Y,
        COMPACT_STAT_Y0 = COMPACT_STAT_Y0,
        COMPACT_TYPE_Y = COMPACT_TYPE_Y,
        DESC_TOP = DESC_TOP,
        REF_AFFIX_GAP = REF_AFFIX_GAP,
        REF_AFFIX_GAP_TOP = REF_AFFIX_GAP_TOP,
        REF_AFFIX_ROW_H = REF_AFFIX_ROW_H,
        REF_AFFIX_TEXT_X = REF_AFFIX_TEXT_X,
        REF_AFFIX_TITLE_FONT = REF_AFFIX_TITLE_FONT,
        REF_AFFIX_TITLE_X = REF_AFFIX_TITLE_X,
        REF_AFFIX_TITLE_Y = REF_AFFIX_TITLE_Y,
        REF_ARROW_GAP = REF_ARROW_GAP,
        REF_ARROW_SIZE = REF_ARROW_SIZE,
        REF_BADGE_CX = REF_BADGE_CX,
        REF_BADGE_H = REF_BADGE_H,
        REF_BADGE_W = REF_BADGE_W,
        REF_BG_CX = REF_BG_CX,
        REF_BTN_CX = REF_BTN_CX,
        REF_BTN_FONT = REF_BTN_FONT,
        REF_BTN_H = REF_BTN_H,
        REF_BTN_W = REF_BTN_W,
        REF_DEC_BTN_FONT = REF_DEC_BTN_FONT,
        REF_DEC_BTN_GAP = REF_DEC_BTN_GAP,
        REF_DEC_BTN_H = REF_DEC_BTN_H,
        REF_DEC_BTN_W = REF_DEC_BTN_W,
        REF_ICON_CX = REF_ICON_CX,
        REF_ICON_CY = REF_ICON_CY,
        REF_ICON_SIZE = REF_ICON_SIZE,
        REF_NAME_FONT = REF_NAME_FONT,
        REF_NAME_X = REF_NAME_X,
        REF_NAME_Y = REF_NAME_Y,
        REF_QUALITY_FONT = REF_QUALITY_FONT,
        REF_QUALITY_X = REF_QUALITY_X,
        REF_QUALITY_Y = REF_QUALITY_Y,
        REF_STAT_BG_H = REF_STAT_BG_H,
        REF_STAT_BG_Y0 = REF_STAT_BG_Y0,
        REF_STAT_FONT = REF_STAT_FONT,
        REF_STAT_GAP = REF_STAT_GAP,
        REF_STAT_TEXT_X = REF_STAT_TEXT_X,
        REF_STAT_VAL_X = REF_STAT_VAL_X,
        REF_TYPE_FONT = REF_TYPE_FONT,
        REF_TYPE_X = REF_TYPE_X,
        REF_TYPE_Y = REF_TYPE_Y,
        SET_GAP = SET_GAP,
        SET_TITLE_H = SET_TITLE_H,
    },
})
local drawEquipPanel = panelDraw.drawEquipPanel
local drawCompactPanel = panelDraw.drawCompactPanel

-- ======================== Public API ========================

--- 初始化（加载图片资源）
---@param vg any NanoVG 上下文
function EquipmentDetail.init(vg)
    imgPowerIcon = nvgCreateImage(vg, "image/通用图标/ICON_ZDL.png", 0)
    imgArrowUp   = nvgCreateImage(vg, "image/通用图标/ICON_UP.png", 0)
    imgArrowDown = nvgCreateImage(vg, "image/通用图标/ICON_down.png", 0)
    imgBtnGreen  = nvgCreateImage(vg, "image/按钮/UI_AN_LV.png", 0)
    imgBtnRed    = nvgCreateImage(vg, "image/按钮/UI_AN_HONG.png", 0)
    imgLock      = nvgCreateImage(vg, "image/通用图标/UI_ICON_SUO.png", 0)
    ImageCache.init(vg)

    for _, key in ipairs(AFFIX_BADGE_KEY) do
        imgAffixBadge[key] = nvgCreateImage(vg, "image/通用图标/ICON_CZBZ_" .. key .. ".png", 0)
    end

    print("[EquipmentDetail] init OK")
end

--- 打开装备详情
---@param seq string|number 装备序列号
---@param slot string 槽位
---@param heroId number 角色ID
function EquipmentDetail.open(seq, slot, heroId, compactCorner, owner, anchorX, anchorY)
    keywordDismissGesture = false
    detState.open      = true
    detState.closing   = false
    detState.equipSeq  = tostring(seq)
    detState.slot      = slot
    detState.heroId    = heroId
    detState.openTime  = time.elapsedTime
    detState.compactCorner = compactCorner == true
    detState.owner = owner or (compactCorner and "character" or "bag")
    detState.anchorX = tonumber(anchorX)
    detState.anchorY = tonumber(anchorY)
    detState.pinned = false
    detState.equippedView = false
    detState.descScrollY = 0
    detState.descScrollMax = 0
    detState.descDragging = false
    detState.lockHotspot = nil
    detState.layoutEquip = nil
    affixKw:clear()
    for i = 1, 3 do setKw[i]:clear() end   -- 清上次装备的关键词状态
    print("[EquipmentDetail] open seq=" .. tostring(seq) .. " slot=" .. tostring(slot)
        .. " heroId=" .. tostring(heroId) .. " compact=" .. tostring(detState.compactCorner)
        .. " anchor=" .. tostring(detState.anchorX) .. "," .. tostring(detState.anchorY))
end

--- 已装备槽位的悬停说明；不是试穿候选，不改变配装比较的目标槽。
function EquipmentDetail.openEquipped(seq, slot, heroId, anchorX, anchorY)
    EquipmentDetail.open(seq, slot, heroId, true, "character", anchorX, anchorY)
    detState.equippedView = true
end

function EquipmentDetail.setAnchor(anchorX, anchorY)
    detState.anchorX = tonumber(anchorX)
    detState.anchorY = tonumber(anchorY)
end

function EquipmentDetail.pin()
    if detState.equippedView then return end -- 当前装备悬停不占用仓库候选的钉住状态。
    detState.pinned = true
end

function EquipmentDetail.isPinned()
    return detState.open and detState.pinned == true
end

--- 关闭（冻结当前面板内容用于关闭动画）
function EquipmentDetail.dismissHover(owner)
    if not detState.open or not detState.compactCorner then return end
    if detState.pinned or (owner and detState.owner ~= owner) then return end
    EquipmentDetail.close()
end

function EquipmentDetail.close()
    keywordDismissGesture = false
    affixKw:clear()
    for i = 1, 3 do setKw[i]:clear() end
    if detState.compactCorner then
        detState.open = false
        detState.closing = false
        detState.compactCorner = false
        detState.snapshot = nil
        detState.pinned = false
        detState.equippedView = false
        detState.layoutEquip = nil
        detState.lockHotspot = nil
        for i = 1, 3 do setKw[i]:clear() end
        return
    end
    if detState.closing then return end
    -- 快照当前渲染数据，动画期间不再读实时数据
    local equipData = PlayerStore.Get("equipment")
    local newEquip = equipData and equipData.inventory and equipData.inventory[detState.equipSeq]
    local isEquipped = isClickedEquipEquipped()
    local curEquip = getComparisonEquip()
    local hasCurrent = (not isEquipped) and (curEquip ~= nil)
    local btnKey = isEquipped and "unequip" or (hasCurrent and "replace" or "wear")
    local powerDiff = replacementGain(newEquip)
    detState.snapshot = {
        newEquip   = newEquip,
        isEquipped = isEquipped,
        curEquip   = curEquip,
        hasCurrent = hasCurrent,
        btnKey     = btnKey,
        powerDiff  = powerDiff,
    }
    detState.closing   = true
    detState.closeTime = time.elapsedTime
    print("[EquipmentDetail] close")
end

--- 是否打开
---@return boolean
function EquipmentDetail.isOpen()
    return detState.open
end

function EquipmentDetail.isCompactCorner()
    return detState.open and detState.compactCorner == true
end

--- 判断当前点击的装备是否已穿戴
---@return boolean isEquipped, string|nil equippedSlot 已装备的实际槽位
isClickedEquipEquipped = function()
    local equipData = PlayerStore.Get("equipment")
    if not equipData or not equipData.equipped then return false, nil end
    local heroEquipped = EquipmentSystem.getHeroSlots(equipData, detState.heroId)
    if not heroEquipped then return false, nil end

    local seqStr = detState.equipSeq
    local slot = detState.slot

    -- 直接检查该槽位
    if heroEquipped[slot] and tostring(heroEquipped[slot]) == seqStr then
        return true, slot
    end

    -- 副手槽位：检查主手是否为该双手武器
    if slot == "offhand" and heroEquipped["weapon"] then
        local wSeqStr = tostring(heroEquipped["weapon"])
        if wSeqStr == seqStr then
            return true, "weapon"
        end
    end

    return false, nil
end

--- 等级穿戴门槛：角色等级低于装备等级时不可穿戴
---@return boolean ok true=可穿戴
---@return number|nil requiredLevel 装备需求等级（仅等级不足时）
local function checkDetailLevelGate()
    if not detState.heroId or not detState.equipSeq then return true, nil end
    local equipData = PlayerStore.Get("equipment")
    local equip = equipData and equipData.inventory and equipData.inventory[detState.equipSeq]
    if not equip then return true, nil end
    if not equip.type or not equip.slot then
        EquipmentSystem.hydrate(equip)
    end
    local heroesData = PlayerStore.Get("heroes")
    local heroLevel = EquipmentSystem.getHeroLevel(heroesData, detState.heroId)
    local ok, requiredLevel = EquipmentSystem.checkLevelGate(heroLevel, equip)
    return ok, requiredLevel
end

--- 穿戴前统一拦截：等级不足时提示并拒绝
---@return boolean blocked true=已拦截（调用方应中止穿戴）
local function blockIfLevelLocked()
    local ok, requiredLevel = checkDetailLevelGate()
    if ok then return false end
    local Toast = require("core.UiToast")
    Toast.show(I18n.t("level_not_enough_equip", tostring(requiredLevel or 1)))
    require("systems.GameSFX").playUIClick(1)
    BF.trigger("equip_deny")
    print("[EquipmentDetail] 等级不足拒绝穿戴 seq=" .. tostring(detState.equipSeq)
        .. " 需Lv." .. tostring(requiredLevel))
    return true
end

--- 获取用于对比的"当前装备"（处理副手对比双手武器场景）
---@return table|nil curEquip, number|nil curSeq
getComparisonEquip = function()
    local equipData = PlayerStore.Get("equipment")
    if not equipData or not equipData.equipped then return nil, nil end
    local heroEquipped = EquipmentSystem.getHeroSlots(equipData, detState.heroId)
    if not heroEquipped then return nil, nil end

    local slot = detState.slot

    -- 直接获取该槽位的装备
    local curSeq = heroEquipped[slot]
    if curSeq and tostring(curSeq) ~= detState.equipSeq then
        local curEquip = equipData.inventory and equipData.inventory[tostring(curSeq)]
        if curEquip then return curEquip, curSeq end
    end

    -- 副手槽位：如果副手没有装备，检查主手是否为双手武器（副手被占用）
    if slot == "offhand" and not curSeq then
        local weaponSeq = heroEquipped["weapon"]
        if weaponSeq then
            local weaponEquip = equipData.inventory and equipData.inventory[tostring(weaponSeq)]
            if weaponEquip and weaponEquip.grip == "twohand" then
                return weaponEquip, weaponSeq
            end
        end
    end

    return nil, nil
end

--- 处理点击
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function EquipmentDetail.handleInput(dx, dy)
    if not detState.open then return false end
    if detState.closing then return true end
    if keywordDismissGesture then
        keywordDismissGesture = false
        affixKw:closePopup()
        for i = 1, 3 do setKw[i]:closePopup() end
        return true
    end
    if detState.compactCorner then
        local ox, oy = compactOffset()
        dx = (dx - ox) / COMPACT_SCALE
        dy = (dy - oy) / COMPACT_SCALE
    end

    local equipData = PlayerStore.Get("equipment")
    if not equipData then return true end

    local newEquip = equipData.inventory and equipData.inventory[detState.equipSeq]
    if not newEquip then
        EquipmentDetail.close()
        return true
    end

    -- 判断是否为已穿戴装备
    local isEquipped, equippedSlot = isClickedEquipEquipped()

    -- 判断是否有对比装备
    local curEquip = getComparisonEquip()
    local hasCurrent = (not isEquipped) and (curEquip ~= nil)

    -- 气泡优先关闭，不能把这次点击变成穿戴/分解或关闭装备详情。
    if affixKw:isOpen() then affixKw:closePopup(); return true end
    if detState.compactCorner then
        for i = 1, 3 do
            if setKw[i]:isOpen() then
                setKw[i]:closePopup()
                return true
            end
        end
    end
    -- 大面板文字在滚动变换内；输入补回 scrollY，clip 防止隐藏词条吃按钮点击。
    local keywordY = detState.compactCorner and dy or dy + detState.descScrollY
    if affixKw:handleInput(dx, keywordY) then return true end
    if detState.compactCorner then
        for i = 1, 3 do
            if setKw[i]:handleInput(dx, dy) then return true end
        end
    end

    -- 按钮位置与绘制一致：超出时钉在框底
    local btnCY = layoutButtons(newEquip)
    detState.descScrollMax = select(2, layoutButtons(newEquip))
    clampDescScroll()
    local offsetX = detState.compactCorner and 0 or (SINGLE_BG_CX - REF_BG_CX)
    local btnCX = REF_BTN_CX + offsetX

    -- 大面板分解按钮：无穿戴按钮时放在框内，其余情况紧贴底板下方。
    local backpackOnly = (detState.slot == nil)
    local decBtnCY = backpackOnly and btnCY
        or (REF_BG_CY + REF_BG_H * 0.5 + REF_DEC_BTN_GAP + REF_DEC_BTN_H * 0.5)

    if detState.compactCorner and detState.lockHotspot
       and hitTest(dx, dy, detState.lockHotspot.cx, detState.lockHotspot.cy,
                   detState.lockHotspot.w, detState.lockHotspot.h) then
        BF.trigger("ed_equip")
        local Client = getClient()
        local Protocol = getProtocol()
        if Client and Client.sendAction and Protocol then
            Client.sendAction(Protocol.ACTION_TYPES.TOGGLE_EQUIP_LOCK, {
                seq = tonumber(detState.equipSeq),
            })
        end
        newEquip.locked = (not newEquip.locked) or nil
        print("[EquipmentDetail] 切换装备锁定 seq=" .. tostring(detState.equipSeq)
            .. " locked=" .. tostring(newEquip.locked == true))
        return true
    end

    if detState.compactCorner then
        local showWear = not backpackOnly
        local wearCY, cx, bw, bh = compactButtonRow()
        if showWear and hitTest(dx, dy, cx, wearCY, bw, bh) then
            BF.trigger("ed_equip")
            local Client = getClient()
            local Protocol = getProtocol()
            if Client and Client.sendAction and Protocol then
                if isEquipped then
                    Client.sendAction(Protocol.ACTION_TYPES.UNEQUIP_ITEM, {
                        heroId = detState.heroId,
                        slot = equippedSlot or detState.slot,
                    })
                elseif blockIfLevelLocked() then
                    -- 等级穿戴门槛：等级不足，已提示，中止穿戴且不关闭面板
                    return true
                else
                    Client.sendAction(Protocol.ACTION_TYPES.EQUIP_ITEM, {
                        seq = tonumber(detState.equipSeq),
                        heroId = detState.heroId,
                        slot = detState.slot,
                    })
                    require("systems.GameSFX").play("install")
                end
            end
            print("[EquipmentDetail] 小窗穿戴 seq=" .. tostring(detState.equipSeq))
            EquipmentDetail.close()
            return true
        end
    end

    -- 点击立即分解按钮（保留未穿戴、未锁定及铁匠铺解锁条件）
    local showDecompose = (not detState.compactCorner) and (not newEquip.locked) and (not isEquipped)
        and TutorialManager.isBuildingUnlocked("smith")
    if showDecompose then
        if hitTest(dx, dy, btnCX, decBtnCY, REF_DEC_BTN_W, REF_DEC_BTN_H) then
            BF.trigger("ed_decompose")
            local Client = getClient()
            local Protocol = getProtocol()
            if Client and Client.sendAction and Protocol then
                Client.sendAction(Protocol.ACTION_TYPES.DECOMPOSE_EQUIP, {
                    seqs = { tonumber(detState.equipSeq) },
                })
                detState.pendingDecompose = true   -- 标记由本面板发起，供 onActionResult 弹出奖励
                print("[EquipmentDetail] 立即分解 seq=" .. tostring(detState.equipSeq))
            end
            EquipmentDetail.close()
            return true
        end
    end

    -- 点击穿戴/卸下按钮（背包模式不显示此按钮，跳过）
    if (not detState.compactCorner) and not backpackOnly and hitTest(dx, dy, btnCX, btnCY, REF_BTN_W, REF_BTN_H) then
        BF.trigger("ed_equip")
        local Client = getClient()
        local Protocol = getProtocol()
        if Client and Client.sendAction and Protocol then
            if isEquipped then
                -- 卸下装备
                Client.sendAction(Protocol.ACTION_TYPES.UNEQUIP_ITEM, {
                    heroId = detState.heroId,
                    slot   = equippedSlot or detState.slot,
                })
                print("[EquipmentDetail] 发送卸下请求 slot=" .. tostring(equippedSlot or detState.slot))
            elseif blockIfLevelLocked() then
                -- 等级穿戴门槛：等级不足，已提示，中止穿戴且不关闭面板
                return true
            else
                -- 穿戴/更换装备
                Client.sendAction(Protocol.ACTION_TYPES.EQUIP_ITEM, {
                    seq    = tonumber(detState.equipSeq),
                    heroId = detState.heroId,
                    slot   = detState.slot,
                })
                print("[EquipmentDetail] 发送穿戴请求 seq=" .. detState.equipSeq)
                require("systems.GameSFX").play("install")
            end
        end
        -- 多人模式乐观更新：数字 heroId 写入 equipped（单机已由 Standalone.tryLocalAction 落地）
        local okPS, PS = pcall(require, "core.PlayerStore")
        if okPS then
            local eq = PS.Get("equipment")
            if eq then
                local hid = tonumber(detState.heroId)
                if hid then
                    local slots = EquipmentSystem.ensureHeroSlots(eq, hid)
                    if isEquipped then
                        local sl = equippedSlot or detState.slot
                        slots[sl] = nil
                    else
                        slots[detState.slot] = tonumber(detState.equipSeq)
                    end
                end
            end
        end
        local okCP, CP = pcall(require, "ui.character.panel.CharacterPanel")
        if okCP and CP.refreshBadge then CP.refreshBadge() end
        EquipmentDetail.close()
        return true
    end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - detState.openTime < 0.05 then return true end

    -- 点击锁定图标 → 切换锁定状态
    if (not detState.compactCorner) and detState.lockHotspot
       and hitTest(dx, dy, detState.lockHotspot.cx, detState.lockHotspot.cy,
                   detState.lockHotspot.w, detState.lockHotspot.h) then
        BF.trigger("ed_equip")
        local Client = getClient()
        local Protocol = getProtocol()
        if Client and Client.sendAction and Protocol then
            Client.sendAction(Protocol.ACTION_TYPES.TOGGLE_EQUIP_LOCK, {
                seq = tonumber(detState.equipSeq),
            })
        end
        -- 乐观更新本地缓存，立即刷新锁图标
        newEquip.locked = (not newEquip.locked) or nil
        print("[EquipmentDetail] 切换装备锁定 seq=" .. tostring(detState.equipSeq)
            .. " locked=" .. tostring(newEquip.locked == true))
        return true
    end

    -- 点击面板外部 → 关闭
    local inPanel = false
    if detState.compactCorner then
        local panelH = compactViewHeight(newEquip, true)
        local panelCenter = REF_BG_CX
        local panelW = COMPACT_BG_W
        if hasCurrent then
            local side = (detState.owner == "character") and -1 or 1
            panelH = math.max(panelH, compactViewHeight(curEquip, false))
            panelW = COMPACT_BG_W * 2 + 16
            panelCenter = panelCenter + side * (COMPACT_BG_W + 16) * 0.5
        end
        if hitTest(dx, dy, panelCenter, panelH * 0.5, panelW, panelH) then
            inPanel = true
        end
    elseif hasCurrent then
        if hitTest(dx, dy, SINGLE_BG_CX, REF_BG_CY, REF_BG_W, REF_BG_H) then
            inPanel = true
        end
    else
        if hitTest(dx, dy, SINGLE_BG_CX, REF_BG_CY, REF_BG_W, REF_BG_H) then
            inPanel = true
        end
    end

    -- 仅保留实际显示的按钮热区，compact 按钮均已包含在底板内。
    if (not detState.compactCorner) and not backpackOnly
       and hitTest(dx, dy, btnCX, btnCY, REF_BTN_W + 40, REF_BTN_H + 40) then
        inPanel = true
    end
    if showDecompose and hitTest(dx, dy, btnCX, decBtnCY, REF_DEC_BTN_W, REF_DEC_BTN_H) then
        inPanel = true
    end

    if not inPanel then
        EquipmentDetail.close()
        return true
    end

    return true
end

--- 绘制
---@param vg any NanoVG 上下文
function EquipmentDetail.draw(vg)
    if not detState.open then return end

    -- 动画计算
    local progress, slideOY

    if detState.closing then
        local elapsed = time.elapsedTime - detState.closeTime
        local rawT = math.min(1.0, elapsed / ANIM_CLOSE_DUR)
        progress = 1 - easeInCubic(rawT)
        if rawT >= 1.0 then
            detState.open     = false
            detState.closing  = false
            detState.snapshot = nil
            return
        end
    else
        local elapsed = time.elapsedTime - detState.openTime
        local rawT = math.min(1.0, elapsed / ANIM_OPEN_DUR)
        progress = easeOutCubic(rawT)
    end

    slideOY = SLIDE_DIST * (1 - progress)

    -- 获取渲染数据：关闭动画期间使用快照，避免 server 推送导致面板内容跳变
    local newEquip, isEquipped, curEquip, hasCurrent, powerDiff, btnText

    if detState.closing and detState.snapshot then
        local s = detState.snapshot
        newEquip   = s.newEquip
        isEquipped = s.isEquipped
        curEquip   = s.curEquip
        hasCurrent = s.hasCurrent
        powerDiff  = s.powerDiff
        -- 新快照按当前语言取 key；旧快照从冻结状态推导，未知 btnText 仍原样兜底。
        local btnKey = s.btnKey
        if not btnKey and s.isEquipped ~= nil then
            btnKey = s.isEquipped and "unequip" or (s.hasCurrent and "replace" or "wear")
        end
        btnText = btnKey and I18n.t(btnKey) or I18n.lookup(s.btnText or "")
    else
        local equipData = PlayerStore.Get("equipment")
        if not equipData or not equipData.inventory then return end
        newEquip = equipData.inventory[detState.equipSeq]
        if not newEquip then return end
        isEquipped = isClickedEquipEquipped()
        curEquip = getComparisonEquip()
        hasCurrent = (not isEquipped) and (curEquip ~= nil)
        btnText = isEquipped and I18n.t("unequip") or (hasCurrent and I18n.t("replace") or I18n.t("wear"))
        powerDiff = replacementGain(newEquip)
    end

    if not newEquip then return end

    local compact = detState.compactCorner == true
    -- 说明栏不铺全屏黑影

    -- 小窗贴点击格子的外侧，右栏向左、左栏向右展开。
    if compact then detState.layoutEquip = newEquip end
    nvgSave(vg)
    if compact then
        local ox, oy = compactOffset()
        nvgTranslate(vg, ox, oy)
        nvgScale(vg, COMPACT_SCALE, COMPACT_SCALE)
    else
        nvgTranslate(vg, 0, slideOY)
    end

    local backpackOnly = (detState.slot == nil)  -- 背包模式不显示穿戴按钮

    if compact then
        affixKw:setPopupTransform(function(x, y) return x, y end)
        local compare = hasCurrent and curEquip or nil
        if compare then
            local side = (detState.owner == "character") and -1 or 1
            nvgSave(vg)
            nvgTranslate(vg, side * (COMPACT_BG_W + 16), 0)
            drawCompactPanel(vg, compare, "当前", false)
            nvgRestore(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 214, 102, 255))
            nvgText(vg, REF_BG_CX + side * (COMPACT_BG_W + 16), 16, "当前装备", nil)
        end
        drawCompactPanel(vg, newEquip, btnText)
        -- 关键词解释气泡在内容之后、滚动裁剪之外绘制。
        affixKw:drawPopup(vg)
        for i = 1, 3 do setKw[i]:drawPopup(vg) end
        nvgRestore(vg)
        return
    end

    -- 只画被点开的这一件，不再左右各铺一份完整说明
    local singleOffsetX = SINGLE_BG_CX - REF_BG_CX
    local showDecompose = (not isEquipped) and (not newEquip.locked)
    drawEquipPanel(vg, newEquip, singleOffsetX,
        SINGLE_BG_CX, REF_BG_CY, REF_BG_W, REF_BG_H,
        (hasCurrent and powerDiff or nil), true, btnText, backpackOnly, true, showDecompose)
    affixKw:setPopupTransform(function(x, y) return x, y - detState.descScrollY end)
    affixKw:drawPopup(vg)

    nvgRestore(vg)
end

--- 遗匣预览：直接展示尚未领取的原装备，不访问背包或提供穿戴/分解操作。
function EquipmentDetail.drawReadOnly(vg, equip, x, y)
    if not equip then return end
    nvgSave(vg)
    nvgTranslate(vg, x - (REF_BG_CX - COMPACT_BG_W * 0.5) * COMPACT_SCALE, y)
    nvgScale(vg, COMPACT_SCALE, COMPACT_SCALE)
    drawCompactPanel(vg, equip, "", false, { generic = true })
    nvgRestore(vg)
end

function EquipmentDetail.readOnlySize(equip)
    return COMPACT_BG_W * COMPACT_SCALE, compactViewHeight(equip, false) * COMPACT_SCALE
end

--- 鼠标是否落在详情面板（含按钮条）。未给坐标时视为命中，兼容旧调用。
---@param dx number|nil
---@param dy number|nil
---@return boolean
function EquipmentDetail.containsPoint(dx, dy)
    if not detState.open or dx == nil or dy == nil then return false end
    local lx, ly = dx, dy
    if detState.compactCorner then
        local ox, oy = compactOffset()
        lx = (dx - ox) / COMPACT_SCALE
        ly = (dy - oy) / COMPACT_SCALE
    end
    if detState.compactCorner then
        local panelH = compactViewHeight(detState.layoutEquip, true)
        local spanW = COMPACT_BG_W
        local spanCenter = REF_BG_CX * 1.0
        if compactCompareEquip() then
            local side = (detState.owner == "character") and -1 or 1
            spanW = COMPACT_BG_W * 2 + 16
            spanCenter = spanCenter + side * (COMPACT_BG_W + 16) * 0.5
            panelH = math.max(panelH, compactViewHeight(compactCompareEquip(), false))
        end
        if hitTest(lx, ly, spanCenter, panelH * 0.5, spanW, panelH) then
            return true
        end
    else
        if hitTest(lx, ly, SINGLE_BG_CX, REF_BG_CY, REF_BG_W, REF_BG_H) then return true end
    end
    if detState.compactCorner then return false end

    local btnCX = REF_BTN_CX + SINGLE_BG_CX - REF_BG_CX
    local eqData = PlayerStore.Get("equipment")
    local equip = eqData and eqData.inventory and eqData.inventory[detState.equipSeq]
    if not equip then return false end
    local btnCY = layoutButtons(equip)
    if detState.slot ~= nil and hitTest(lx, ly, btnCX, btnCY, REF_BTN_W + 40, REF_BTN_H + 40) then
        return true
    end
    if not equip.locked and not isClickedEquipEquipped() and TutorialManager.isBuildingUnlocked("smith") then
        local decBtnCY = detState.slot == nil and btnCY
            or (REF_BG_CY + REF_BG_H * 0.5 + REF_DEC_BTN_GAP + REF_DEC_BTN_H * 0.5)
        return hitTest(lx, ly, btnCX, decBtnCY, REF_DEC_BTN_W, REF_DEC_BTN_H)
    end
    return false
end

---@param wheel number
---@param dx number|nil 设计坐标；给出且不在面板上时不消费
---@param dy number|nil
---@return boolean
function EquipmentDetail.handleScroll(wheel, dx, dy)
    if not detState.open or detState.closing then return false end
    if dx ~= nil and not EquipmentDetail.containsPoint(dx, dy) then return false end
    affixKw:closePopup()
    detState.descScrollY = detState.descScrollY - (wheel or 0) * 90
    clampDescScroll()
    return true
end

function EquipmentDetail.handleDragBegin(dx, dy)
    if not detState.open or detState.closing then return false end
    keywordDismissGesture = affixKw:isOpen()
    if detState.compactCorner then
        for i = 1, 3 do keywordDismissGesture = keywordDismissGesture or setKw[i]:isOpen() end
    end
    local _, ly = dx, dy
    if detState.compactCorner then
        local ox, oy = compactOffset()
        ly = (dy - oy) / COMPACT_SCALE
    end
    -- 每次指针按下都会到 Begin；点击说明/按钮须保留气泡到松手消费。
    detState.descDragging = true
    detState.descDragLastY = ly
    return true
end

function EquipmentDetail.handleDragMove(dx, dy)
    if not detState.open or not detState.descDragging then return false end
    local ly = dy
    if detState.compactCorner then
        local ox, oy = compactOffset()
        ly = (dy - oy) / COMPACT_SCALE
    end
    if math.abs(detState.descDragLastY - ly) > 0.01 then
        affixKw:closePopup()
        for i = 1, 3 do setKw[i]:closePopup() end
    end
    detState.descScrollY = detState.descScrollY + (detState.descDragLastY - ly)
    detState.descDragLastY = ly
    clampDescScroll()
    return true
end

function EquipmentDetail.handleDragEnd()
    detState.descDragging = false
    return detState.open == true
end

function EquipmentDetail.getOwner()
    return detState.owner
end

--- 只读选择快照：悬停与钉住共用同一真源，不暴露装备或可变面板状态。
---@return table|nil
function EquipmentDetail.getSelection()
    if not detState.open or detState.closing then return nil end
    return {
        seq = detState.equipSeq, slot = detState.slot, heroId = detState.heroId,
        owner = detState.owner, pinned = detState.pinned == true,
        equipped = detState.equippedView == true,
    }
end

function EquipmentDetail.drawIf(vg, owner)
    if detState.compactCorner then return end
    if owner and detState.owner and detState.owner ~= owner then return end
    EquipmentDetail.draw(vg)
end

--- 处理 action 结果：当「立即分解」由本面板发起时，弹出分解奖励
--- （铁匠铺未打开时 BlacksmithPage.onActionResult 会提前 return，需要本模块兜底展示奖励）
---@param data table
function EquipmentDetail.onActionResult(data)
    if not detState.pendingDecompose then return end
    local Protocol = getProtocol()
    -- 仅处理分解结果（成功/失败都清除标记，避免后续误弹）
    if Protocol and data.action ~= Protocol.ACTION_TYPES.DECOMPOSE_EQUIP then return end
    detState.pendingDecompose = false
    if data.decomposed then
        local rewards = {}
        if (data.essenceReward or 0) > 0 then
            rewards[#rewards + 1] = { type = "essence", amount = data.essenceReward }
        end
        if (data.goldReward or 0) > 0 then
            rewards[#rewards + 1] = { type = "gold", amount = data.goldReward }
        end
        BlacksmithConfig.appendScrollRewardItems(rewards, data.scrollRewards)
        if #rewards > 0 then
            require("ui.hud.popup.RewardPopup").show("分解奖励", rewards)
        end
    end
end

--- 暴露战斗力计算供 EquipmentBag 角标判断使用
EquipmentDetail.calcEquipPower = calcEquipPower

return EquipmentDetail
