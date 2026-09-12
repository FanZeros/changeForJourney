-- ============================================================================
-- BlacksmithEnhance.lua
-- 铁匠铺 - 槽位强化子模块：属性展示、消耗显示、强化触发
-- 新机制：100% 成功率，消耗金币+对应卷轴，仅提升第一条基础属性
-- ============================================================================

---@diagnostic disable: undefined-global

local DrawUtil          = require("core.DrawUtil")
local GameState         = require("core.GameState")
local AffixConfig       = require("config.AffixConfig")
local EquipmentConfig   = require("config.EquipmentConfig")
local BlacksmithConfig  = require("config.BlacksmithConfig")
local ExpTable          = require("config.ExpTable")
local AD                = require("systems.AttributeDef")
local SpineResultEffect = require("ui.SpineResultEffect")
local ClientDispatcher  = require("network.ClientDispatcher")
local PlayerStore       = require("client.data.PlayerStore")
local BF                = require("systems.ButtonFeedback")

local drawImageCentered = DrawUtil.drawImageCentered
local hitTest           = DrawUtil.hitTest

local M = {}

-- ======================== 门控状态（防止快速连点） ========================
local pendingEnhance = false       -- 是否有强化请求在等待服务端响应
local pendingEnhanceTime = 0       -- 请求发出时的 elapsedTime
local ENHANCE_TIMEOUT = 10         -- 超时保护（秒）
local ENHANCE_COOLDOWN = 0.5       -- 门控释放后的冷却期（秒）
local lastEnhanceReleaseTime = 0   -- 上次门控释放的时间戳

-- ======================== 强化界面 - 上半部分常量 ========================

-- 1. 标题
local ENH_TITLE_CX, ENH_TITLE_CY = 540, 1128
local ENH_TITLE_FONT_SIZE         = 40

-- 2. 当前强化等级
local ENH_CUR_LV_CX, ENH_CUR_LV_CY = 433, 1204
local ENH_LV_FONT_SIZE               = 70

-- 3. 提升箭头-大
local ENH_ARROW_CX, ENH_ARROW_CY = 540, 1204
local ENH_ARROW_W, ENH_ARROW_H   = 54, 54

-- 4. 下一强化等级
local ENH_NEXT_LV_CX, ENH_NEXT_LV_CY = 646, 1204

-- 5. 基础属性区域
local ATTR_NAME_X       = 286
local ATTR_NAME_Y       = 1305
local ATTR_FONT_SIZE    = 40
local ATTR_TEXT_COLOR_R, ATTR_TEXT_COLOR_G, ATTR_TEXT_COLOR_B = 0x45, 0x45, 0x45
local ATTR_NAME_COLOR_R, ATTR_NAME_COLOR_G, ATTR_NAME_COLOR_B = 0x72, 0x58, 0x50

-- 当前属性值背景框
local ATTR_CUR_BG_CX    = 473
local ATTR_BG_W          = 282
local ATTR_BG_H          = 58
local ATTR_BG_RADIUS     = 29

-- 提升箭头-小
local ATTR_ARROW_CX     = 670
local ATTR_ARROW_W      = 48
local ATTR_ARROW_H      = 48

-- 提升后属性值背景框
local ATTR_NEXT_BG_CX   = 856
local ATTR_NEXT_BG_W    = 282
local ATTR_NEXT_BG_H    = 58

-- 6. 多条属性行间距
local ATTR_ROW_SPACING   = 9

-- 7. 随机词缀：第一行 Y 轴中心
local AFFIX_FIRST_Y      = 1561

-- 8. 词缀等级 ICON 位置 X
local AFFIX_GRADE_CUR_CX  = 366
local AFFIX_GRADE_NEXT_CX = 754

-- 属性行高度
local ATTR_ROW_HEIGHT = ATTR_BG_H

-- ======================== 强化界面 - 下半部分常量 ========================

local EB = {
    -- "强化需求"
    REQ_TITLE_X = 134, REQ_TITLE_Y = 1737, REQ_TITLE_FONT_SIZE = 40,
    REQ_TITLE_R = 0xbc, REQ_TITLE_G = 0xb8, REQ_TITLE_B = 0xaa,
    -- 需求背景框
    REQ_BG_CX = 540, REQ_BG_CY = 1905, REQ_BG_W = 970, REQ_BG_H = 260, REQ_BG_RADIUS = 48,
    -- 资源需求图标
    RES_ICON_CX = 540, RES_ICON_CY = 1889, RES_ICON_SIZE = 160,
    -- 数值背景框
    RES_COUNT_BG_CY = 1977, RES_COUNT_BG_W = 158, RES_COUNT_BG_H = 47, RES_COUNT_BG_RADIUS = 16,
    -- 资源对比颜色
    ENOUGH_R = 0x45, ENOUGH_G = 0xff, ENOUGH_B = 0x7e,
    SHORT_R = 0xff, SHORT_G = 0x45, SHORT_B = 0x45,
    -- 强化按钮（左侧）
    ENH_BTN_CX = 307, ENH_BTN_CY = 2129, ENH_BTN_W = 410, ENH_BTN_H = 100,
    ENH_TEXT_FONT_SIZE = 40,
    ENH_TEXT_R = 0x25, ENH_TEXT_G = 0x55, ENH_TEXT_B = 0x3d,
    -- 一键强化按钮（右侧）
    ENH_MAX_BTN_CX = 770, ENH_MAX_BTN_CY = 2129, ENH_MAX_BTN_W = 410, ENH_MAX_BTN_H = 100,
}

-- 词缀等级图标尺寸
local AFFIX_GRADE_ICON_SIZE = 44

-- ======================== 强化界面数据 ========================

local enhanceData = {
    curLevel  = 0,
    nextLevel = 1,
    isMaxLevel = false,
    -- 基础属性列表（仅第一条有提升）
    baseAttrs = {},
    -- 随机词缀列表（仅显示，不随强化提升）
    affixes = {},
    -- 资源需求
    costGold     = 0,
    ownedGold    = 0,
    costScroll   = 0,
    ownedScroll  = 0,
    scrollField  = "weaponScroll",  -- 当前槽位对应的卷轴货币字段
}

-- ======================== ctx 引用（由 setContext 注入） ========================

local imgArrow         -- 提升箭头
local imgEnhBtn        -- 强化按钮背景 (UI_AN_LV.png)
local imgGoldIcon      -- 金币图标
local imgGoldQBg       -- 金币品质背景框
local imgGrade         -- 词缀等级图标 table
local formatCompact    -- 大数值缩写函数
local formatAffixValue -- 词缀值格式化函数
local state            -- 共享状态 (selectedEquipSlot, selectedPartySlot 等)
local getClient        -- 延迟加载 Client
local getProtocol      -- 延迟加载 Protocol

-- 弹窗专属图片（由 BlacksmithPage 注入）
local imgDialogBg      -- 二级确认弹窗背景 (UI_TY_EJQRK.png)
local imgBtnYellow     -- 黄色确认按钮 (UI_AN_HUANG.png)
local imgBtnMinus      -- 减按钮 (UI_AN_JIAN.png)
local imgBtnPlus       -- 加按钮 (UI_AN_JIA.png)
local imgScrollIconRef -- 当前卷轴图标引用（弹窗消耗展示用）
local drawNineSlice    -- 九宫格绘制函数（由 BlacksmithPage 注入）

-- 卷轴图标（模块专属）
local imgScrollIcon = {}  -- { weapon=handle, offhand=handle, armor=handle, accessory=handle }
local imgScrollQBg  = -1  -- 卷轴品质背景框（质量3）

--- 卷轴 getter 映射
local SCROLL_GETTER = {
    weaponScroll    = "getWeaponScroll",
    offhandScroll   = "getOffhandScroll",
    armorScroll     = "getArmorScroll",
    accessoryScroll = "getAccessoryScroll",
}

--- 注入共享上下文
---@param ctx table 由 BlacksmithPage 构造的共享上下文
function M.setContext(ctx)
    imgArrow           = ctx.imgArrow
    imgEnhBtn          = ctx.imgEnhBtn
    imgGoldIcon        = ctx.imgGoldIcon
    imgGoldQBg         = ctx.imgGoldQBg
    imgGrade           = ctx.imgGrade
    formatCompact      = ctx.formatCompact
    formatAffixValue   = ctx.formatAffixValue
    state              = ctx.state
    getClient          = ctx.getClient
    getProtocol        = ctx.getProtocol
    -- 弹窗图片
    imgDialogBg        = ctx.imgDialogBg
    imgBtnYellow       = ctx.imgBtnYellow
    imgBtnMinus        = ctx.imgBtnMinus
    imgBtnPlus         = ctx.imgBtnPlus
    -- 九宫格工具
    drawNineSlice      = ctx.drawNineSlice
end

--- 初始化强化界面专属图片
function M.init(vg)
    -- 加载 4 种卷轴图标
    imgScrollIcon.weapon    = nvgCreateImage(vg, "image/UI_icon_JZ_WQ.png", 0)
    imgScrollIcon.offhand   = nvgCreateImage(vg, "image/UI_icon_JZ_FS.png", 0)
    imgScrollIcon.armor     = nvgCreateImage(vg, "image/UI_icon_JZ_HJ.png", 0)
    imgScrollIcon.accessory = nvgCreateImage(vg, "image/UI_icon_JZ_SP.png", 0)
    -- 卷轴品质背景（quality=3，绿色品质）
    imgScrollQBg = nvgCreateImage(vg, "image/UI_icon_ZBBJ_3.png", 0)
end

-- ======================== 数据更新 ========================

--- 计算当前资源能强化到的最高等级
--- 从 curLevel+1 开始累加消耗，直到金币或卷轴不足为止
---@param curLevel number 当前强化等级
---@param ownedGold number 拥有金币
---@param ownedScroll number 拥有卷轴
---@return number reachLevel 能达到的最高等级（不超过 MAX_ENHANCE_LEVEL）
local function calcMaxAffordableLevel(curLevel, ownedGold, ownedScroll)
    local hardMax    = BlacksmithConfig.MAX_ENHANCE_LEVEL
    local enhanceCap = ExpTable.getEnhanceLevelCap(GameState.getLevel())
    local maxLv      = math.min(hardMax, enhanceCap)
    local reachLevel = curLevel
    local usedGold   = 0
    local usedScroll = 0
    for lv = curLevel + 1, maxLv do
        local cost = BlacksmithConfig.getEnhanceCost(lv)
        if not cost then break end
        if usedGold + cost.gold > ownedGold or usedScroll + cost.scroll > ownedScroll then
            break
        end
        usedGold   = usedGold   + cost.gold
        usedScroll = usedScroll + cost.scroll
        reachLevel = lv
    end
    return reachLevel
end

--- 获取当前选中槽位的 slotEnhance 等级
---@return number
local function getSlotEnhanceLevel()
    local slotEnhanceData = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
    if not slotEnhanceData or not slotEnhanceData.levels then return 0 end
    local partySlot = state.selectedPartySlot
    local equipSlot = state.selectedEquipSlot
    local partyLevels = slotEnhanceData.levels[tostring(partySlot)] or slotEnhanceData.levels[partySlot]
    if not partyLevels then return 0 end
    return partyLevels[equipSlot] or 0
end

--- 根据选中装备更新强化面板数据
function M.updateEnhanceData(equip)
    -- 确定当前槽位的卷轴类型
    local equipSlot = state.selectedEquipSlot or "weapon"
    local scrollField = BlacksmithConfig.SLOT_SCROLL_MAP[equipSlot] or "weaponScroll"
    enhanceData.scrollField = scrollField

    -- 获取槽位强化等级
    local enhLv     = getSlotEnhanceLevel()
    local hardMax   = BlacksmithConfig.MAX_ENHANCE_LEVEL
    local maxLv     = math.min(hardMax, ExpTable.getEnhanceLevelCap(GameState.getLevel()))
    local nextLv    = math.min(enhLv + 1, maxLv)
    local isMax     = enhLv >= maxLv

    enhanceData.curLevel  = enhLv
    enhanceData.nextLevel = nextLv
    enhanceData.isMaxLevel = isMax

    if not equip then
        enhanceData.baseAttrs   = {}
        enhanceData.affixes     = {}
        enhanceData.costGold    = 0
        enhanceData.ownedGold   = GameState.getGold()
        enhanceData.costScroll  = 0
        local getter = SCROLL_GETTER[scrollField]
    ---@diagnostic disable-next-line: assign-type-mismatch
        enhanceData.ownedScroll = getter and GameState[getter]() or 0
        return
    end

    -- 当前加成和下一级加成（双手武器：主副手各50%叠加，与 calcSlotBoost 保持一致）
    local curBoost, nextBoost
    if equip.grip == "twohand" then
        local sed = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
        local ps  = state.selectedPartySlot
        local pl  = sed and sed.levels and (sed.levels[tostring(ps)] or sed.levels[ps]) or {}
        local wLv = pl["weapon"]  or 0
        local oLv = pl["offhand"] or 0
        curBoost = BlacksmithConfig.getEnhanceBoost(wLv) * 0.5
                 + BlacksmithConfig.getEnhanceBoost(oLv) * 0.5
        -- 下一级：当前槽 +1，另一槽不变
        local nWLv = (equipSlot == "weapon")  and math.min(wLv + 1, maxLv) or wLv
        local nOLv = (equipSlot == "offhand") and math.min(oLv + 1, maxLv) or oLv
        nextBoost = BlacksmithConfig.getEnhanceBoost(nWLv) * 0.5
                  + BlacksmithConfig.getEnhanceBoost(nOLv) * 0.5
    else
        curBoost  = BlacksmithConfig.getEnhanceBoost(enhLv)
        nextBoost = isMax and curBoost or BlacksmithConfig.getEnhanceBoost(nextLv)
    end

    -- 基础属性：只有第一条受强化加成
    local baseAttrs = {}
    for idx, s in ipairs(equip.baseStats or {}) do
        local key = s[1]
        local rawVal = s[2]
        local meta = AD.META[key]
        local attrName = meta and meta.name or key

        local curVal, nextVal
        if idx == 1 then
            -- 第一条属性受槽位强化加成
            curVal  = rawVal * (1 + curBoost)
            nextVal = rawVal * (1 + nextBoost)
        else
            -- 其他属性不受强化影响
            curVal  = rawVal
            nextVal = rawVal
        end

        if meta and meta.dataType == AD.TYPE_PCT then
            baseAttrs[#baseAttrs + 1] = {
                name    = attrName,
                curVal  = string.format("%.1f%%", curVal),
                nextVal = string.format("%.1f%%", nextVal),
                boosted = (idx == 1),
            }
        else
            baseAttrs[#baseAttrs + 1] = {
                name    = attrName,
                curVal  = string.format("%.0f", curVal),
                nextVal = string.format("%.0f", nextVal),
                boosted = (idx == 1),
            }
        end
    end

    -- 词缀（不随强化变化，仅显示当前值）
    local affixes = {}
    for _, affix in ipairs(equip.affixes or {}) do
        local isCorrupt = AffixConfig.isCorruptAffix(affix)
        local qDef = AffixConfig.QUALITY[affix.quality]
        local gradeName = qDef and qDef.name or "D"
        affixes[#affixes + 1] = {
            name     = affix.name or affix.key,
            curVal   = formatAffixValue(affix.key, affix.value),
            nextVal  = formatAffixValue(affix.key, affix.value),
            curGrade = gradeName,
            nextGrade = gradeName,
            isCorrupt = isCorrupt,
        }
    end

    -- 强化消耗（金币 + 卷轴）
    local costEntry = BlacksmithConfig.getEnhanceCost(nextLv)
    local costGold   = costEntry and costEntry.gold   or 0
    local costScroll = costEntry and costEntry.scroll or 0

    -- 卷轴拥有量
    local getter = SCROLL_GETTER[scrollField]
    local ownedScroll = getter and GameState[getter]() or 0

    enhanceData.baseAttrs   = baseAttrs
    enhanceData.affixes     = affixes
    enhanceData.costGold    = isMax and 0 or costGold
    enhanceData.ownedGold   = GameState.getGold()
    enhanceData.costScroll  = isMax and 0 or costScroll
    ---@diagnostic disable-next-line: assign-type-mismatch
    enhanceData.ownedScroll = ownedScroll
end

-- ======================== 绘制函数 ========================

--- 绘制一行属性
---@param vg any NanoVG context
---@param rowY number 该行的 Y 中心坐标
---@param name string 属性名称
---@param curVal string 当前数值文本
---@param nextVal string 提升后数值文本
---@param curGradeIcon number|nil 当前词缀等级图标句柄
---@param nextGradeIcon number|nil 提升后词缀等级图标句柄
---@param showArrow boolean|nil 是否显示提升箭头和提升后数值（默认 true）
---@param isCorrupt boolean|nil 魔化词条：用紫色圆标替代 D~S 品质图
local function drawAttrRow(vg, rowY, name, curVal, nextVal, curGradeIcon, nextGradeIcon, showArrow, isCorrupt)
    if showArrow == nil then showArrow = true end

    -- 属性名称（右对齐）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, ATTR_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(ATTR_NAME_COLOR_R, ATTR_NAME_COLOR_G, ATTR_NAME_COLOR_B, 255))
    nvgText(vg, ATTR_NAME_X, rowY, name, nil)

    -- 当前属性值背景框
    local curBgX = ATTR_CUR_BG_CX - ATTR_BG_W * 0.5
    local curBgY = rowY - ATTR_BG_H * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, curBgX, curBgY, ATTR_BG_W, ATTR_BG_H, ATTR_BG_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))
    nvgFill(vg)

    -- 当前数值文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, ATTR_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(ATTR_TEXT_COLOR_R, ATTR_TEXT_COLOR_G, ATTR_TEXT_COLOR_B, 255))
    nvgText(vg, ATTR_CUR_BG_CX, rowY, curVal, nil)

    if showArrow then
        -- 提升箭头-小
        drawImageCentered(vg, imgArrow, ATTR_ARROW_CX, rowY, ATTR_ARROW_W, ATTR_ARROW_H, 1.0)

        -- 提升后属性值背景框
        local nextBgX = ATTR_NEXT_BG_CX - ATTR_NEXT_BG_W * 0.5
        local nextBgY = rowY - ATTR_NEXT_BG_H * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, nextBgX, nextBgY, ATTR_NEXT_BG_W, ATTR_NEXT_BG_H, ATTR_BG_RADIUS)
        nvgFillColor(vg, nvgRGBA(0x56, 0xcb, 0x90, 51))
        nvgFill(vg)

        -- 提升后数值文本
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, ATTR_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(ATTR_TEXT_COLOR_R, ATTR_TEXT_COLOR_G, ATTR_TEXT_COLOR_B, 255))
        nvgText(vg, ATTR_NEXT_BG_CX, rowY, nextVal, nil)
    end

    -- 词缀等级图标 / 魔化紫色圆标
    if isCorrupt then
        local r = AFFIX_GRADE_ICON_SIZE * 0.22
        nvgBeginPath(vg)
        nvgCircle(vg, AFFIX_GRADE_CUR_CX, rowY, r)
        nvgFillColor(vg, nvgRGBA(0x9B, 0x4D, 0xFF, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, AFFIX_GRADE_CUR_CX, rowY, r)
        nvgStrokeWidth(vg, 2)
        nvgStrokeColor(vg, nvgRGBA(0xE0, 0xB0, 0xFF, 220))
        nvgStroke(vg)
    elseif curGradeIcon and curGradeIcon >= 0 then
        drawImageCentered(vg, curGradeIcon, AFFIX_GRADE_CUR_CX, rowY, AFFIX_GRADE_ICON_SIZE, AFFIX_GRADE_ICON_SIZE, 1.0)
    end
    if showArrow and nextGradeIcon and nextGradeIcon >= 0 and not isCorrupt then
        drawImageCentered(vg, nextGradeIcon, AFFIX_GRADE_NEXT_CX, rowY, AFFIX_GRADE_ICON_SIZE, AFFIX_GRADE_ICON_SIZE, 1.0)
    end
end

--- 绘制强化界面上半部分（等级 + 属性预览）
function M.drawPanel(vg)
    local data = enhanceData

    -- 1. 动态标题："角色栏N>XX栏强化"
    local slotName = EquipmentConfig.SLOT_NAME[state.selectedEquipSlot] or "主手"
    local titleStr = "角色栏" .. (state.selectedPartySlot or 1) .. ">" .. slotName .. "栏强化"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, ENH_TITLE_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(ATTR_TEXT_COLOR_R, ATTR_TEXT_COLOR_G, ATTR_TEXT_COLOR_B, 255))
    nvgText(vg, ENH_TITLE_CX, ENH_TITLE_CY, titleStr, nil)

    if data.isMaxLevel then
        -- 已满级：只显示当前等级
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, ENH_LV_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xff, 0x33, 0x33, 255))
        nvgText(vg, ENH_TITLE_CX, ENH_CUR_LV_CY, "+" .. data.curLevel .. " MAX", nil)
    else
        -- 2. 当前强化等级
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, ENH_LV_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(ATTR_TEXT_COLOR_R, ATTR_TEXT_COLOR_G, ATTR_TEXT_COLOR_B, 255))
        nvgText(vg, ENH_CUR_LV_CX, ENH_CUR_LV_CY, "+" .. data.curLevel, nil)

        -- 3. 提升箭头-大
        drawImageCentered(vg, imgArrow, ENH_ARROW_CX, ENH_ARROW_CY, ENH_ARROW_W, ENH_ARROW_H, 1.0)

        -- 4. 下一强化等级
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, ENH_LV_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(ATTR_TEXT_COLOR_R, ATTR_TEXT_COLOR_G, ATTR_TEXT_COLOR_B, 255))
        nvgText(vg, ENH_NEXT_LV_CX, ENH_NEXT_LV_CY, "+" .. data.nextLevel, nil)
    end

    -- 5-6. 基础属性区域
    local rowY = ATTR_NAME_Y
    for _, attr in ipairs(data.baseAttrs) do
        -- 只有受强化加成的属性显示箭头和提升后数值
        local showArrow = attr.boosted and not data.isMaxLevel
        drawAttrRow(vg, rowY, attr.name, attr.curVal, attr.nextVal, nil, nil, showArrow)
        rowY = rowY + ATTR_ROW_HEIGHT + ATTR_ROW_SPACING
    end

    -- 7-8. 随机词缀区域（不随强化变化，不显示提升箭头）
    local affixY = AFFIX_FIRST_Y
    for _, affix in ipairs(data.affixes) do
        local curIcon = imgGrade[affix.curGrade] or -1
        drawAttrRow(vg, affixY, affix.name, affix.curVal, affix.nextVal, curIcon, nil, false, affix.isCorrupt)
        affixY = affixY + ATTR_ROW_HEIGHT + ATTR_ROW_SPACING
    end
end

--- 绘制资源数量（拥有/需要）
---@param vg any NanoVG context
---@param cx number 图标中心 X
---@param owned number 拥有数量
---@param cost number 需要数量
local function drawResourceCount(vg, cx, owned, cost)
    -- 数量背景框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - EB.RES_COUNT_BG_W * 0.5, EB.RES_COUNT_BG_CY - EB.RES_COUNT_BG_H * 0.5,
        EB.RES_COUNT_BG_W, EB.RES_COUNT_BG_H, EB.RES_COUNT_BG_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
    nvgFill(vg)

    local ownedStr = formatCompact(owned)
    local costStr  = formatCompact(cost)
    local enough = owned >= cost

    -- 自适应字号
    local maxTextW = EB.RES_COUNT_BG_W - 12
    local fontSize = 30
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local fullStr = ownedStr .. "/" .. costStr
    nvgFontSize(vg, fontSize)
    local tw = nvgTextBounds(vg, 0, 0, fullStr)
    while tw > maxTextW and fontSize > 16 do
        fontSize = fontSize - 2
        nvgFontSize(vg, fontSize)
        tw = nvgTextBounds(vg, 0, 0, fullStr)
    end

    local ownedW = nvgTextBounds(vg, 0, 0, ownedStr)
    local sx = cx - tw * 0.5
    nvgFillColor(vg, nvgRGBA(
        enough and EB.ENOUGH_R or EB.SHORT_R,
        enough and EB.ENOUGH_G or EB.SHORT_G,
        enough and EB.ENOUGH_B or EB.SHORT_B, 255))
    nvgText(vg, sx, EB.RES_COUNT_BG_CY, ownedStr, nil)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, sx + ownedW, EB.RES_COUNT_BG_CY, "/" .. costStr, nil)
end

--- 绘制强化界面下半部分（需求区域）
function M.drawPanelBottom(vg)
    local data = enhanceData

    if data.isMaxLevel then
        -- 满级提示
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x99, 0x99, 0x99, 180))
        nvgText(vg, 540, 1850, "已达到最高强化等级", nil)
        return
    end

    -- 1. "强化需求" 文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, EB.REQ_TITLE_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(EB.REQ_TITLE_R, EB.REQ_TITLE_G, EB.REQ_TITLE_B, 255))
    nvgText(vg, EB.REQ_TITLE_X, EB.REQ_TITLE_Y, "强化需求", nil)

    -- 9. 需求背景框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, EB.REQ_BG_CX - EB.REQ_BG_W * 0.5, EB.REQ_BG_CY - EB.REQ_BG_H * 0.5,
        EB.REQ_BG_W, EB.REQ_BG_H, EB.REQ_BG_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))
    nvgFill(vg)

    -- === 双图标居中排列：金币 + 卷轴 ===
    local ICON_SIZE = EB.RES_ICON_SIZE
    local ICON_GAP = 40
    local iconCY = EB.RES_ICON_CY
    local totalW = 2 * ICON_SIZE + ICON_GAP
    local goldCX   = EB.REQ_BG_CX - totalW * 0.5 + ICON_SIZE * 0.5
    local scrollCX = goldCX + ICON_SIZE + ICON_GAP

    -- 金币图标 + 数量
    drawImageCentered(vg, imgGoldQBg, goldCX, iconCY, ICON_SIZE, ICON_SIZE, 1.0)
    drawImageCentered(vg, imgGoldIcon, goldCX, iconCY, ICON_SIZE, ICON_SIZE, 1.0)
    drawResourceCount(vg, goldCX, data.ownedGold, data.costGold)

    -- 卷轴图标 + 数量
    local equipSlot = state.selectedEquipSlot or "weapon"
    local scrollImg = imgScrollIcon[equipSlot] or imgScrollIcon.weapon
    drawImageCentered(vg, imgScrollQBg, scrollCX, iconCY, ICON_SIZE, ICON_SIZE, 1.0)
    if scrollImg and scrollImg >= 0 then
        drawImageCentered(vg, scrollImg, scrollCX, iconCY, ICON_SIZE, ICON_SIZE, 1.0)
    end
    drawResourceCount(vg, scrollCX, data.ownedScroll, data.costScroll)

    -- 强化按钮（左侧）
    local didScale = BF.begin(vg, "bse_enhance", EB.ENH_BTN_CX, EB.ENH_BTN_CY, EB.ENH_BTN_W, EB.ENH_BTN_H)
    drawImageCentered(vg, imgEnhBtn, EB.ENH_BTN_CX, EB.ENH_BTN_CY, EB.ENH_BTN_W, EB.ENH_BTN_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, EB.ENH_TEXT_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(EB.ENH_TEXT_R, EB.ENH_TEXT_G, EB.ENH_TEXT_B, 255))
    nvgText(vg, EB.ENH_BTN_CX, EB.ENH_BTN_CY, "强化", nil)
    BF.finish(vg, didScale)
    local _TM = require("systems.TutorialManager")
    if _TM.isActive() then _TM.registerHotspot("smith_btn_enhance", EB.ENH_BTN_CX, EB.ENH_BTN_CY, EB.ENH_BTN_W, EB.ENH_BTN_H) end

    -- 一键强化按钮（右侧）
    local maxReachLevel = calcMaxAffordableLevel(data.curLevel, data.ownedGold, data.ownedScroll)
    local canMaxEnhance = maxReachLevel > data.curLevel
    local maxBtnAlpha = canMaxEnhance and 1.0 or 0.5
    local didScaleMax = BF.begin(vg, "bse_enhance_max", EB.ENH_MAX_BTN_CX, EB.ENH_MAX_BTN_CY, EB.ENH_MAX_BTN_W, EB.ENH_MAX_BTN_H)
    drawImageCentered(vg, imgEnhBtn, EB.ENH_MAX_BTN_CX, EB.ENH_MAX_BTN_CY, EB.ENH_MAX_BTN_W, EB.ENH_MAX_BTN_H, maxBtnAlpha)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, EB.ENH_TEXT_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(EB.ENH_TEXT_R, EB.ENH_TEXT_G, EB.ENH_TEXT_B, canMaxEnhance and 255 or 128))
    nvgText(vg, EB.ENH_MAX_BTN_CX, EB.ENH_MAX_BTN_CY, "一键强化", nil)
    BF.finish(vg, didScaleMax)
end

-- ======================== 一键强化确认弹窗 ========================

-- 弹窗布局常量（完全照搬 MarketPage DLG 风格）
local EMDLG = {
    -- 背景（九宫格）
    BG_CX = 540, BG_CY = 1211, BG_W = 950, BG_H = 847,
    BG_IT = 150, BG_IR = 60, BG_IB = 100, BG_IL = 60,
    -- 标题
    TITLE_CX = 540, TITLE_CY = 855, TITLE_FONT = 60, TITLE_SW = 6,
    TITLE_SR = 0x46, TITLE_SG = 0x2f, TITLE_SB = 0x20,
    -- 副标题
    SUB_CX = 540, SUB_CY = 967, SUB_FONT = 40,
    SUB_R = 0xb6, SUB_G = 0xb0, SUB_B = 0x9d,
    -- 内容框（参考 MarketPage CONTENT 区域）
    CONTENT_CX = 540, CONTENT_CY = 1121, CONTENT_W = 800, CONTENT_H = 218, CONTENT_R = 16,
    -- 内容框内的等级文本
    LVL_CX = 540, LVL_CY = 1122, LVL_FONT = 50, LVL_SW = 5,
    -- 数量文本行（参考 MarketPage QTY 行）
    QTY_CX = 540, QTY_CY = 1278, QTY_FONT = 40,
    -- 减按钮
    MINUS_CX = 282, MINUS_CY = 1342, MINUS_W = 84, MINUS_H = 84,
    -- 加按钮
    PLUS_CX  = 808, PLUS_CY  = 1342, PLUS_W  = 84, PLUS_H  = 84,
    -- 滑条
    SLIDER_CX = 540, SLIDER_CY = 1342, SLIDER_W = 400, SLIDER_H = 24, SLIDER_R = 12,
    KNOB_SIZE = 36,
    KNOB_STROKE_R = 0x44, KNOB_STROKE_G = 0x2d, KNOB_STROKE_B = 0x19, KNOB_STROKE_W = 6,
    -- 消耗展示
    COST_CX = 540, COST_CY = 1416, COST_ICON_SIZE = 70, COST_FONT = 40, COST_SW = 4,
    COST_GAP = 16,  -- 两组消耗之间的间距
    -- 确认按钮（九宫格黄色按钮）
    CONFIRM_CX = 540, CONFIRM_CY = 1503, CONFIRM_W = 410, CONFIRM_H = 100, CONFIRM_FONT = 40,
}

-- 弹窗动画常量
local EMDLG_OPEN_DUR   = 0.22
local EMDLG_CLOSE_DUR  = 0.18
local EMDLG_SCALE_FROM = 0.82

-- 弹窗状态
local dlg = {
    open        = false,
    closing     = false,
    openTime    = 0,
    closeTime   = 0,
    targetLevel = 1,   -- 玩家选择的目标强化等级
    maxLevel    = 1,   -- 资源上限等级（弹窗打开时计算）
    sliderDrag  = false,
}

--- 弹窗动画进度：返回 scale, alpha, done
local function getDlgAnim()
    if dlg.closing then
        local t = math.min(1.0, (time.elapsedTime - dlg.closeTime) / EMDLG_CLOSE_DUR)
        local ease = t * t
        local s = EMDLG_SCALE_FROM + (1.0 - EMDLG_SCALE_FROM) * (1.0 - ease)
        return s, 1.0 - ease, t >= 1.0
    else
        local t = math.min(1.0, (time.elapsedTime - dlg.openTime) / EMDLG_OPEN_DUR)
        local ease = 1 - (1 - t) * (1 - t)
        local s = EMDLG_SCALE_FROM + (1.0 - EMDLG_SCALE_FROM) * ease
        return s, ease, false
    end
end

--- 绘制一行消耗（图标 + "×N"文本），返回整行宽度
local function measureCostW(vg, label, iconSize, fontSize)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, fontSize)
    local tw = nvgTextBounds(vg, 0, 0, label)
    return iconSize + 6 + tw
end

--- 工具：带描边的文本（内联复用，避免循环依赖）
local function drawStroke(vg, cx, cy, text, font, align, r, g, b, sw)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, font); nvgTextAlign(vg, align)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    for ox = -sw, sw do for oy = -sw, sw do
        if ox ~= 0 or oy ~= 0 then nvgText(vg, cx + ox, cy + oy, text, nil) end
    end end
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
    nvgText(vg, cx, cy, text, nil)
end

--- 计算弹窗打开时的默认目标等级（资源上限）并刷新 dlg
local function refreshDlgTarget()
    local data       = enhanceData
    local hardMax    = BlacksmithConfig.MAX_ENHANCE_LEVEL
    local enhanceCap = ExpTable.getEnhanceLevelCap(GameState.getLevel())
    local capLv      = math.min(hardMax, enhanceCap)
    local maxReach   = calcMaxAffordableLevel(data.curLevel, data.ownedGold, data.ownedScroll)
    -- dlg.maxLevel = 资源可达上限，但不超过冒险等级上限
    dlg.maxLevel    = math.min(capLv, math.max(data.curLevel + 1, maxReach))
    dlg.targetLevel = maxReach > data.curLevel and maxReach or (data.curLevel + 1)
    -- 钳位到合法范围
    dlg.targetLevel = math.max(data.curLevel + 1, math.min(dlg.maxLevel, dlg.targetLevel))
end

--- 计算强化到目标等级的总消耗
---@return number totalGold, number totalScroll
local function calcCostToTarget(targetLevel)
    local curLevel = enhanceData.curLevel
    local totalGold, totalScroll = 0, 0
    for lv = curLevel + 1, targetLevel do
        local cost = BlacksmithConfig.getEnhanceCost(lv)
        if cost then
            totalGold   = totalGold   + (cost.gold   or 0)
            totalScroll = totalScroll + (cost.scroll or 0)
        end
    end
    return totalGold, totalScroll
end

--- 绘制一键强化确认弹窗（叠在最上层）
function M.drawConfirmDialog(vg)
    if not dlg.open then return end

    local pScale, pAlpha, done = getDlgAnim()
    if dlg.closing and done then
        dlg.open    = false
        dlg.closing = false
        return
    end

    local data = enhanceData

    -- 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * pAlpha)))
    nvgFill(vg)

    -- scale+fade
    nvgSave(vg)
    nvgTranslate(vg, EMDLG.BG_CX, EMDLG.BG_CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -EMDLG.BG_CX, -EMDLG.BG_CY)
    nvgGlobalAlpha(vg, pAlpha)

    -- 背景（九宫格，与 MarketPage 完全一致）
    if imgDialogBg and imgDialogBg >= 0 and drawNineSlice then
        drawNineSlice(vg, imgDialogBg,
            EMDLG.BG_CX - EMDLG.BG_W * 0.5, EMDLG.BG_CY - EMDLG.BG_H * 0.5,
            EMDLG.BG_W, EMDLG.BG_H,
            EMDLG.BG_IT, EMDLG.BG_IR, EMDLG.BG_IB, EMDLG.BG_IL)
    elseif imgDialogBg and imgDialogBg >= 0 then
        local bx = EMDLG.BG_CX - EMDLG.BG_W * 0.5
        local by = EMDLG.BG_CY - EMDLG.BG_H * 0.5
        local paint = nvgImagePattern(vg, bx, by, EMDLG.BG_W, EMDLG.BG_H, 0, imgDialogBg, 1.0)
        nvgBeginPath(vg); nvgRect(vg, bx, by, EMDLG.BG_W, EMDLG.BG_H)
        nvgFillPaint(vg, paint); nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, EMDLG.BG_CX - EMDLG.BG_W*0.5, EMDLG.BG_CY - EMDLG.BG_H*0.5,
            EMDLG.BG_W, EMDLG.BG_H, 32)
        nvgFillColor(vg, nvgRGBA(0x3a, 0x28, 0x1a, 245))
        nvgFill(vg)
    end

    -- 标题"一键强化"
    drawStroke(vg, EMDLG.TITLE_CX, EMDLG.TITLE_CY, "一键强化",
        EMDLG.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, EMDLG.TITLE_SW)

    -- 副标题"选择目标强化等级"
    nvgFontFace(vg, "sans"); nvgFontSize(vg, EMDLG.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(EMDLG.SUB_R, EMDLG.SUB_G, EMDLG.SUB_B, 255))
    nvgText(vg, EMDLG.SUB_CX, EMDLG.SUB_CY, "选择目标强化等级", nil)

    -- 内容框背景（与 MarketPage CONTENT 区域一致）
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        EMDLG.CONTENT_CX - EMDLG.CONTENT_W * 0.5, EMDLG.CONTENT_CY - EMDLG.CONTENT_H * 0.5,
        EMDLG.CONTENT_W, EMDLG.CONTENT_H, EMDLG.CONTENT_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)

    -- 内容框内：目标等级文本 "Lv.N"
    local lvText = "Lv." .. tostring(dlg.targetLevel)
    drawStroke(vg, EMDLG.LVL_CX, EMDLG.LVL_CY, lvText,
        EMDLG.LVL_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        0xff, 0xe0, 0x66, EMDLG.LVL_SW)

    -- 数量文本行（QTY 行）：显示"目标等级 +N"
    nvgFontFace(vg, "sans"); nvgFontSize(vg, EMDLG.QTY_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(EMDLG.SUB_R, EMDLG.SUB_G, EMDLG.SUB_B, 255))
    nvgText(vg, EMDLG.QTY_CX, EMDLG.QTY_CY, "+" .. data.curLevel .. " → +" .. dlg.targetLevel, nil)

    -- 减按钮
    local minusAlpha = dlg.targetLevel <= data.curLevel + 1 and 0.4 or 1.0
    local _sm = BF.begin(vg, "bse_dlg_minus", EMDLG.MINUS_CX, EMDLG.MINUS_CY, EMDLG.MINUS_W, EMDLG.MINUS_H)
    if imgBtnMinus and imgBtnMinus >= 0 then
        drawImageCentered(vg, imgBtnMinus, EMDLG.MINUS_CX, EMDLG.MINUS_CY, EMDLG.MINUS_W, EMDLG.MINUS_H, minusAlpha)
    end
    BF.finish(vg, _sm)

    -- 加按钮
    local plusAlpha = dlg.targetLevel >= dlg.maxLevel and 0.4 or 1.0
    local _sp = BF.begin(vg, "bse_dlg_plus", EMDLG.PLUS_CX, EMDLG.PLUS_CY, EMDLG.PLUS_W, EMDLG.PLUS_H)
    if imgBtnPlus and imgBtnPlus >= 0 then
        drawImageCentered(vg, imgBtnPlus, EMDLG.PLUS_CX, EMDLG.PLUS_CY, EMDLG.PLUS_W, EMDLG.PLUS_H, plusAlpha)
    end
    BF.finish(vg, _sp)

    -- 滑条
    local sliderL = EMDLG.SLIDER_CX - EMDLG.SLIDER_W * 0.5
    local range   = math.max(1, dlg.maxLevel - (data.curLevel + 1))
    local frac    = (dlg.targetLevel - (data.curLevel + 1)) / range
    frac = math.max(0, math.min(1, frac))

    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderL, EMDLG.SLIDER_CY - EMDLG.SLIDER_H * 0.5,
        EMDLG.SLIDER_W, EMDLG.SLIDER_H, EMDLG.SLIDER_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 51))
    nvgFill(vg)

    local fillW = EMDLG.SLIDER_W * frac
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sliderL, EMDLG.SLIDER_CY - EMDLG.SLIDER_H * 0.5,
            fillW, EMDLG.SLIDER_H, EMDLG.SLIDER_R)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 120))
        nvgFill(vg)
    end

    -- 滑块
    local knobX = sliderL + EMDLG.SLIDER_W * frac
    local knobR = EMDLG.KNOB_SIZE * 0.5
    nvgBeginPath(vg); nvgCircle(vg, knobX, EMDLG.SLIDER_CY, knobR)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255)); nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(EMDLG.KNOB_STROKE_R, EMDLG.KNOB_STROKE_G, EMDLG.KNOB_STROKE_B, 255))
    nvgStrokeWidth(vg, EMDLG.KNOB_STROKE_W); nvgStroke(vg)

    -- 消耗展示（金币 + 卷轴，两组居中排列）
    local totalGold, totalScroll = calcCostToTarget(dlg.targetLevel)
    local goldStr   = "×" .. tostring(totalGold)
    local scrollStr = "×" .. tostring(totalScroll)
    local iconSz    = EMDLG.COST_ICON_SIZE
    local font      = EMDLG.COST_FONT

    nvgFontFace(vg, "sans"); nvgFontSize(vg, font)
    local gwText = nvgTextBounds(vg, 0, 0, goldStr)
    local swText = nvgTextBounds(vg, 0, 0, scrollStr)
    local gW = iconSz + 6 + gwText
    local sW = iconSz + 6 + swText
    local totalW = gW + EMDLG.COST_GAP + sW
    local startX = EMDLG.COST_CX - totalW * 0.5
    local cy     = EMDLG.COST_CY

    -- 金币图标
    if imgGoldIcon and imgGoldIcon >= 0 then
        drawImageCentered(vg, imgGoldIcon, startX + iconSz * 0.5, cy, iconSz, iconSz, 1.0)
    end
    local goldEnough = totalGold <= enhanceData.ownedGold
    drawStroke(vg, startX + iconSz + 6, cy, goldStr, font,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        goldEnough and 0xff or 0xff,
        goldEnough and 0xff or 0x45,
        goldEnough and 0xff or 0x45,
        EMDLG.COST_SW)

    -- 卷轴图标
    local scrollX = startX + gW + EMDLG.COST_GAP
    local curScrollImg = imgScrollIcon[state.selectedEquipSlot or "weapon"] or imgScrollIcon.weapon
    if curScrollImg and curScrollImg >= 0 then
        drawImageCentered(vg, curScrollImg, scrollX + iconSz * 0.5, cy, iconSz, iconSz, 1.0)
    end
    local scrollEnough = totalScroll <= enhanceData.ownedScroll
    drawStroke(vg, scrollX + iconSz + 6, cy, scrollStr, font,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        scrollEnough and 0xff or 0xff,
        scrollEnough and 0xff or 0x45,
        scrollEnough and 0xff or 0x45,
        EMDLG.COST_SW)

    -- 确认按钮（九宫格黄色按钮，与 MarketPage BUY 按钮一致）
    local canConfirm = goldEnough and scrollEnough
    local _sc = BF.begin(vg, "bse_dlg_confirm", EMDLG.CONFIRM_CX, EMDLG.CONFIRM_CY, EMDLG.CONFIRM_W, EMDLG.CONFIRM_H)
    if imgBtnYellow and imgBtnYellow >= 0 and drawNineSlice then
        -- 九宫格黄色按钮（inset: 上20 右60 下20 左60，与 MarketPage 一致）
        nvgGlobalAlpha(vg, canConfirm and 1.0 or 0.5)
        drawNineSlice(vg, imgBtnYellow,
            EMDLG.CONFIRM_CX - EMDLG.CONFIRM_W * 0.5, EMDLG.CONFIRM_CY - EMDLG.CONFIRM_H * 0.5,
            EMDLG.CONFIRM_W, EMDLG.CONFIRM_H,
            20, 60, 20, 60)
        nvgGlobalAlpha(vg, 1.0)
    elseif imgBtnYellow and imgBtnYellow >= 0 then
        drawImageCentered(vg, imgBtnYellow, EMDLG.CONFIRM_CX, EMDLG.CONFIRM_CY,
            EMDLG.CONFIRM_W, EMDLG.CONFIRM_H, canConfirm and 1.0 or 0.5)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, EMDLG.CONFIRM_CX - EMDLG.CONFIRM_W * 0.5, EMDLG.CONFIRM_CY - EMDLG.CONFIRM_H * 0.5,
            EMDLG.CONFIRM_W, EMDLG.CONFIRM_H, 24)
        nvgFillColor(vg, nvgRGBA(0xe8, 0xb0, 0x20, canConfirm and 255 or 100))
        nvgFill(vg)
    end
    nvgFontFace(vg, "sans"); nvgFontSize(vg, EMDLG.CONFIRM_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x25, 0x55, 0x3d, canConfirm and 255 or 100))
    nvgText(vg, EMDLG.CONFIRM_CX, EMDLG.CONFIRM_CY, "强化", nil)
    BF.finish(vg, _sc)

    nvgRestore(vg)
end

--- 弹窗是否打开（供 BlacksmithPage 路由输入用）
function M.isDialogOpen()
    return dlg.open
end

--- 关闭弹窗（带动画）
local function closeDlg()
    if not dlg.open or dlg.closing then return end
    dlg.closing   = true
    dlg.closeTime = time.elapsedTime
end

-- 前向声明（定义在 M.handleInput 之前，供 M.handleDialogInput 调用）
local checkAndSetGate

--- 处理弹窗内的点击输入
---@return boolean consumed
function M.handleDialogInput(dx, dy)
    if not dlg.open then return false end
    if dlg.closing then return true end

    local data     = enhanceData
    local minLevel = data.curLevel + 1

    -- 减按钮
    if hitTest(dx, dy, EMDLG.MINUS_CX, EMDLG.MINUS_CY, EMDLG.MINUS_W, EMDLG.MINUS_H) then
        BF.trigger("bse_dlg_minus")
        dlg.targetLevel = math.max(minLevel, dlg.targetLevel - 1)
        return true
    end

    -- 加按钮
    if hitTest(dx, dy, EMDLG.PLUS_CX, EMDLG.PLUS_CY, EMDLG.PLUS_W, EMDLG.PLUS_H) then
        BF.trigger("bse_dlg_plus")
        dlg.targetLevel = math.min(dlg.maxLevel, dlg.targetLevel + 1)
        return true
    end

    -- 确认按钮
    if hitTest(dx, dy, EMDLG.CONFIRM_CX, EMDLG.CONFIRM_CY, EMDLG.CONFIRM_W, EMDLG.CONFIRM_H) then
        BF.trigger("bse_dlg_confirm")
        local totalGold, totalScroll = calcCostToTarget(dlg.targetLevel)
        if totalGold > data.ownedGold or totalScroll > data.ownedScroll then
            print("[BlacksmithEnhance] 资源不足，无法强化到 Lv." .. dlg.targetLevel)
            return true
        end
        if not checkAndSetGate() then return true end
        closeDlg()
        pendingEnhance     = true
        pendingEnhanceTime = time.elapsedTime or 0
        local partySlot    = state.selectedPartySlot
        local equipSlot    = state.selectedEquipSlot
        print("[BlacksmithEnhance] 一键强化确认 partySlot=" .. tostring(partySlot)
            .. " equipSlot=" .. tostring(equipSlot) .. " targetLevel=" .. dlg.targetLevel)
        getClient().sendAction(getProtocol().ACTION_TYPES.ENHANCE_EQUIP_MAX, {
            partySlot   = partySlot,
            equipSlot   = equipSlot,
            targetLevel = dlg.targetLevel,
        })
        return true
    end

    -- 点击弹窗外区域关闭
    local bx = EMDLG.BG_CX - EMDLG.BG_W * 0.5
    local by = EMDLG.BG_CY - EMDLG.BG_H * 0.5
    if not hitTest(dx, dy, EMDLG.BG_CX, EMDLG.BG_CY, EMDLG.BG_W, EMDLG.BG_H) then
        closeDlg()
    end
    return true
end

--- 处理弹窗滑块的拖拽开始
function M.handleDialogDragBegin(dx, dy)
    if not dlg.open or dlg.closing then return false end
    local hitH = math.max(EMDLG.SLIDER_H, EMDLG.KNOB_SIZE) + 20
    if hitTest(dx, dy, EMDLG.SLIDER_CX, EMDLG.SLIDER_CY, EMDLG.SLIDER_W + EMDLG.KNOB_SIZE, hitH) then
        dlg.sliderDrag = true
        local sliderL  = EMDLG.SLIDER_CX - EMDLG.SLIDER_W * 0.5
        local frac     = math.max(0, math.min(1, (dx - sliderL) / EMDLG.SLIDER_W))
        local minLevel = enhanceData.curLevel + 1
        local range    = math.max(1, dlg.maxLevel - minLevel)
        dlg.targetLevel = math.max(minLevel, math.min(dlg.maxLevel,
            minLevel + math.floor(frac * range + 0.5)))
    end
    return true
end

--- 处理弹窗滑块的拖拽移动
function M.handleDialogDragMove(dx, dy)
    if not dlg.open or dlg.closing then return false end
    if dlg.sliderDrag then
        local sliderL  = EMDLG.SLIDER_CX - EMDLG.SLIDER_W * 0.5
        local frac     = math.max(0, math.min(1, (dx - sliderL) / EMDLG.SLIDER_W))
        local minLevel = enhanceData.curLevel + 1
        local range    = math.max(1, dlg.maxLevel - minLevel)
        dlg.targetLevel = math.max(minLevel, math.min(dlg.maxLevel,
            minLevel + math.floor(frac * range + 0.5)))
    end
    return true
end

--- 处理弹窗滑块的拖拽结束
function M.handleDialogDragEnd()
    dlg.sliderDrag = false
end

-- ======================== 状态查询 ========================

--- 重置门控状态（打开铁匠铺/切换 Tab 时调用）
function M.onOpen()
    pendingEnhance = false
    dlg.open    = false
    dlg.closing = false
end

-- ======================== 输入处理 ========================

--- 门控检查（通用）- 返回 true 表示可以继续发送请求
checkAndSetGate = function()
    if pendingEnhance then
        local elapsed = (time.elapsedTime or 0) - pendingEnhanceTime
        if elapsed < ENHANCE_TIMEOUT then
            print("[BlacksmithEnhance] 门控中，等待服务端响应...")
            return false
        end
        pendingEnhance = false
        print("[BlacksmithEnhance] 门控超时，自动释放")
    end
    local sinceRelease = (time.elapsedTime or 0) - lastEnhanceReleaseTime
    if sinceRelease < ENHANCE_COOLDOWN then
        print("[BlacksmithEnhance] 冷却中...")
        return false
    end
    return true
end

--- 处理强化需求区域的点击
---@param dx number 设计坐标 X
---@param dy number 设计坐标 Y
---@return boolean consumed 是否消费了该事件
function M.handleInput(dx, dy)
    -- 强化按钮（升一级）
    if hitTest(dx, dy, EB.ENH_BTN_CX, EB.ENH_BTN_CY, EB.ENH_BTN_W, EB.ENH_BTN_H) then
        BF.trigger("bse_enhance")
        if not checkAndSetGate() then return true end
        local data = enhanceData
        if data.isMaxLevel then
            print("[BlacksmithEnhance] 已满级，无法强化")
            return true
        end
        if data.ownedGold < data.costGold then
            print("[BlacksmithEnhance] 金币不足")
            return true
        end
        if data.ownedScroll < data.costScroll then
            print("[BlacksmithEnhance] 卷轴不足")
            return true
        end
        pendingEnhance = true
        pendingEnhanceTime = time.elapsedTime or 0
        local partySlot = state.selectedPartySlot
        local equipSlot = state.selectedEquipSlot
        print("[BlacksmithEnhance] 强化请求 partySlot=" .. tostring(partySlot) .. " equipSlot=" .. tostring(equipSlot))
        getClient().sendAction(getProtocol().ACTION_TYPES.ENHANCE_EQUIP, {
            partySlot = partySlot,
            equipSlot = equipSlot,
        })
        return true
    end

    -- 一键强化按钮（打开二级确认弹窗）
    if hitTest(dx, dy, EB.ENH_MAX_BTN_CX, EB.ENH_MAX_BTN_CY, EB.ENH_MAX_BTN_W, EB.ENH_MAX_BTN_H) then
        BF.trigger("bse_enhance_max")
        local data = enhanceData
        if data.isMaxLevel then
            print("[BlacksmithEnhance] 已满级，无法强化")
            return true
        end
        local maxReach = calcMaxAffordableLevel(data.curLevel, data.ownedGold, data.ownedScroll)
        if maxReach <= data.curLevel then
            print("[BlacksmithEnhance] 资源不足，无法一键强化")
            return true
        end
        -- 打开确认弹窗（玩家可自行选择目标等级）
        refreshDlgTarget()
        dlg.open      = true
        dlg.closing   = false
        dlg.openTime  = time.elapsedTime
        print("[BlacksmithEnhance] 打开一键强化确认弹窗，默认目标=" .. dlg.targetLevel)
        return true
    end

    return false
end

-- ======================== 服务端结果处理 ========================

--- 处理强化 action result
---@param data table action result 数据
---@return boolean handled 是否处理了该事件
function M.onActionResult(data)
    -- 门控释放
    if pendingEnhance then
        pendingEnhance = false
        lastEnhanceReleaseTime = time.elapsedTime
        print("[BlacksmithEnhance] 门控释放")
    end

    if not data.enhanceOutcome then return false end

    local outcome = data.enhanceOutcome
    if outcome == "success" then
        print("[BlacksmithEnhance] 槽位强化成功！")
        -- 刷新强化面板数据（等级、消耗、拥有量）
        -- 此时 PlayerStore 已收到 currency/slotEnhance 的推送更新
        M.updateEnhanceData(state.selectedEquip)
        SpineResultEffect.play(true)
        -- 刷新城镇Tab角标（强化后金币/卷轴消耗，可强化状态可能变化）
        local okBN, BN = pcall(require, "ui.BottomNav")
        if okBN and BN and BN.refreshTownBadge then BN.refreshTownBadge() end
    else
        print("[BlacksmithEnhance] 强化失败: " .. tostring(outcome))
        SpineResultEffect.play(false)
    end

    return true
end

--- 获取卷轴货币字段对应的 GameState getter 方法名
---@param scrollField string 卷轴货币字段名（如 "weaponScroll"）
---@return string|nil getter 方法名（如 "getWeaponScroll"）
function M.getScrollGetter(scrollField)
    return SCROLL_GETTER[scrollField]
end

return M
