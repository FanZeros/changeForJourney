-- ============================================================================
-- BlacksmithRefine.lua
-- 铁匠铺 - 洗练子模块：洗练前/后对比、替换确认、洗练/替换按钮、洗练动画
-- 从 BlacksmithPage.lua 拆分而来
-- ============================================================================

---@diagnostic disable: undefined-global

local DrawUtil         = require("core.DrawUtil")
local DarkIcon         = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质底框矢量绘制
local GameState        = require("core.GameState")
local PlayerStore      = require("core.PlayerStore")
local AffixConfig      = require("config.AffixConfig")
local EquipmentConfig  = require("config.EquipmentConfig")
local BlacksmithConfig = require("config.BlacksmithConfig")
local EquipmentSystem  = require("systems.EquipmentSystem")
local AD               = require("systems.AttributeDef")

local drawImageCentered = DrawUtil.drawImageCentered
local hitTest           = DrawUtil.hitTest
local BF                = require("systems.ButtonFeedback")

local M = {}

local MAX_CORRUPT_COUNT = 3
-- 构筑模型 2026-09-30：腐化后仍可洗练，精粹 ×2（与服务端 CORRUPTED_ESSENCE_MULT 一致）
local CORRUPTED_ESSENCE_MULT = 2

---@param equip table|nil
---@return number
local function getCorruptCount(equip)
    if not equip then return 0 end
    return math.max(0, math.floor(tonumber(equip.corruptCount) or 0))
end

local CORRUPT_TAG_R, CORRUPT_TAG_G, CORRUPT_TAG_B = 0xef, 0x79, 0xff
local CORRUPT_COMPARE_R, CORRUPT_COMPARE_G, CORRUPT_COMPARE_B = 0xef, 0x79, 0xff

---@param equip table|nil
---@return table meta { scaleByIndex, originalAffixCount, baseMult }
local function parseCorruptRevertMeta(equip)
    local meta = {
        scaleByIndex = {},
        originalAffixCount = 0,
        baseMult = nil,
    }
    local rev = equip and equip.corruptRevert
    if not rev then return meta end
    meta.originalAffixCount = rev.affixCount or 0
    meta.baseMult = rev.baseMult
    for _, patch in ipairs(rev.patches or {}) do
        if patch[1] == "s" and patch[2] then
            meta.scaleByIndex[patch[2]] = patch[3]
        end
    end
    return meta
end

local function showRefineToast(msg)
    -- 抽卡页开着时进其消息队列，否则走全局 UiToast（LootBoxPage.showToast 在页面关闭时静默丢弃）
    local ok, LootBoxPage = pcall(require, "ui.loot.LootBoxPage")
    if ok and LootBoxPage.isOpen and LootBoxPage.isOpen() and LootBoxPage.showToast then
        LootBoxPage.showToast(msg)
        return
    end
    local ok2, UiToast = pcall(require, "core.UiToast")
    if ok2 and UiToast.show then
        UiToast.show(msg)
    else
        print("[BlacksmithRefine] " .. tostring(msg))
    end
end

--- WaitForChange cancel 引用（防泄漏 + 防叠加）
local cancelCurrencyWatch_ = nil

--- 按装备 seq 记录锁定的词缀 index（session 内有效）
local affixLocksBySeq = {}

---@param seq number
---@return table lockedSet index -> true
local function getAffixLockSet(seq)
    return affixLocksBySeq[seq] or {}
end

---@param seq number
---@return number
local function getLockedCountForSeq(seq)
    local set = getAffixLockSet(seq)
    local n = 0
    for _ in pairs(set) do
        n = n + 1
    end
    return n
end

---@param seq number
---@return number[]
local function getLockedIndicesArray(seq)
    local set = getAffixLockSet(seq)
    local arr = {}
    for idx in pairs(set) do
        arr[#arr + 1] = idx
    end
    table.sort(arr)
    return arr
end

-- ======================== 前置声明（供闭包捕获） ========================
-- 以下变量在文件后方赋值，但必须在此声明以使 recalcRefineEssenceCost 等闭包能正确捕获
local state            ---@type table 共享状态 (selectedEquip, pendingRefineAffixes 等)
local selectedExtraRes ---@type table|nil 当前选中的额外资源
local refineData       ---@type table 洗练面板数据

--- 根据当前锁定状态重算精粹消耗
local function recalcRefineEssenceCost()
    if not state or not state.selectedEquip then return end
    local equip = state.selectedEquip
    local baseCost = BlacksmithConfig.calcRefineEssenceCost(
        equip.quality or 1,
        equip.level or 1,
        equip.grip)
    local lockedCount = 0
    if not (selectedExtraRes and (selectedExtraRes.key == "destroyStone" or selectedExtraRes.key == "corruptStone" or selectedExtraRes.key == "sacredStone")) then
        lockedCount = getLockedCountForSeq(equip.seq)
    end
    if selectedExtraRes and selectedExtraRes.key == "sacredStone" then
        refineData.costEssence = 0
        return
    end
    -- 腐化诅咒：洗练精粹 ×2（与服务端一致；腐化石/点金石路径不加价）
    local extraKey = selectedExtraRes and selectedExtraRes.key or nil
    if getCorruptCount(equip) > 0 and extraKey ~= "destroyStone" and extraKey ~= "corruptStone" then
        baseCost = baseCost * CORRUPTED_ESSENCE_MULT
    end
    refineData.costEssence = BlacksmithConfig.applyRefineLockCostMult(baseCost, lockedCount)
end

---@param seq number
---@param index number 1-based
local function toggleAffixLock(seq, index)
    if not affixLocksBySeq[seq] then
        affixLocksBySeq[seq] = {}
    end
    local set = affixLocksBySeq[seq]
    if set[index] then
        set[index] = nil
        if not next(set) then
            affixLocksBySeq[seq] = nil
        end
    else
        set[index] = true
    end
    recalcRefineEssenceCost()
end

--- 洗练成功后同步本地次数与下次消耗（与服务端 nextRefineCount 一致）
local function bumpRefineCountAndCost(state)
    refineData.refineCount = BlacksmithConfig.nextRefineCount(refineData.refineCount)
    if state.selectedEquip then
        state.selectedEquip.refineCount = refineData.refineCount
        recalcRefineEssenceCost()
    end
end

-- ======================== 洗练界面常量 ========================

-- ---- 洗练界面 - 上半部分（横屏左右排布：洗练前左 / 洗练后右） ----
local XL = {
    -- 1. "洗练装备" 标题
    TITLE_CX = 540, TITLE_CY = 886, TITLE_FONT_SIZE = 40,
    -- 腐化次数提示（标题下方）
    CORRUPT_TEXT_CX = 540, CORRUPT_TEXT_Y = 940, CORRUPT_TEXT_FONT = 32,
    CORRUPT_TAG_FONT = 22,
    -- 2. 单一背景框：洗练前/后内容共用一个框，左右并排（无「洗练前/后」标题字）
    FRAME_CX = 540, FRAME_CY = 1240, FRAME_W = 970, FRAME_H = 560,
    -- 左右两半内容的面板相对左缘 / 半幅中心（空状态提示与结果展示用）
    -- 左半可用 110..516、右半可用 610..1009（箭头 516..564 居中分隔）
    LEFT_PANEL_LEFT = 55, RIGHT_PANEL_LEFT = 555,
    LEFT_HALF_CX = 313, RIGHT_HALF_CX = 786,
    -- 3. 两半之间的箭头（向右，亮色染色绘制）
    ARROW_CX = 540, ARROW_CY = 1240, ARROW_W = 48, ARROW_H = 48,
    -- 5. 属性行（半幅内相对坐标：相对各半左缘）
    ATTR_ICON_CX = 34, ATTR_ICON_SIZE = 40,
    ATTR_NAME_X = 60, ATTR_FONT_SIZE = 28, ATTR_NAME_FONT_SMALL = 24,
    ATTR_NAME_MAX_W = 210,
    ATTR_NAME_R = 0xd8, ATTR_NAME_G = 0xc9, ATTR_NAME_B = 0xa3,  -- 亮米金（暗底可读）
    ATTR_VALUE_X = 330,
    LOCK_ICON_CX = 366, LOCK_ICON_SIZE = 38,
    ATTR_VAL_R = 0xe8, ATTR_VAL_G = 0xe4, ATTR_VAL_B = 0xda,      -- 亮白数值（暗底可读）
    -- 腐化对比行（第二行 旧→新）
    COMPARE_FONT = 24,
    COMPARE_LINE_DY = 18,
    -- 6. 行间距
    ATTR_ROW_GAP = 28,
}
-- 计算行步进
XL.ATTR_ROW_STEP = XL.ATTR_ICON_SIZE + XL.ATTR_ROW_GAP  -- 68

--- 属性行首行 Y：N 行整体垂直居中于单框中心
---@param rowCount number
---@return number
local function refineRowFirstY(rowCount)
    local n = math.max(1, math.floor(tonumber(rowCount) or 1))
    return XL.FRAME_CY - (n - 1) * XL.ATTR_ROW_STEP * 0.5
end

-- ---- 洗练界面 - 下半部分 ----
-- 1. "洗练需求"
XL.REQ_TITLE_X = 134; XL.REQ_TITLE_Y = 1737; XL.REQ_TITLE_FONT_SIZE = 40
XL.REQ_TITLE_R = 0xbc; XL.REQ_TITLE_G = 0xb8; XL.REQ_TITLE_B = 0xaa
-- 2. "当前装备累计洗练XX次"
XL.REQ_COUNT_X = 1024; XL.REQ_COUNT_Y = 1737
-- 3. 洗练需求背景框
XL.REQ_BG_CX = 540; XL.REQ_BG_CY = 1905; XL.REQ_BG_W = 970; XL.REQ_BG_H = 260; XL.REQ_BG_RADIUS = 48
-- 4. 资源需求图标（精粹 - 居中）
XL.RES_ICON_CX = 540; XL.RES_ICON_CY = 1889; XL.RES_ICON_SIZE = 160
-- 4b. 额外资源槽位（右侧 - 洗练石/点金石）
XL.EXTRA_ICON_CX = 719; XL.EXTRA_ICON_CY = 1889; XL.EXTRA_ICON_SIZE = 160
XL.EXTRA_BG_RADIUS = 24; XL.EXTRA_PLUS_SIZE = 92
-- 5. 资源消耗数值背景框
XL.RES_COUNT_BG_CX = 540; XL.RES_COUNT_BG_CY = 1977; XL.RES_COUNT_BG_W = 158; XL.RES_COUNT_BG_H = 47; XL.RES_COUNT_BG_RADIUS = 16
-- 5b. 额外资源消耗数值背景框
XL.EXTRA_COUNT_BG_CX = 719; XL.EXTRA_COUNT_BG_CY = 1977
-- 6. 资源对比颜色
XL.ENOUGH_R = 0x45; XL.ENOUGH_G = 0xff; XL.ENOUGH_B = 0x7e
XL.SHORT_R = 0xff; XL.SHORT_G = 0x45; XL.SHORT_B = 0x45
-- 7. 替换按钮
XL.REPLACE_BTN_CX = 310; XL.REPLACE_BTN_CY = 2129; XL.REPLACE_BTN_W = 410; XL.REPLACE_BTN_H = 100
-- 8. 洗练按钮
XL.REFINE_BTN_CX = 773; XL.REFINE_BTN_CY = 2129; XL.REFINE_BTN_W = 410; XL.REFINE_BTN_H = 100
-- 9. 替换按钮文本
XL.REPLACE_TEXT_FONT_SIZE = 40; XL.REPLACE_TEXT_R = 0x6d; XL.REPLACE_TEXT_G = 0x4c; XL.REPLACE_TEXT_B = 0x1d
-- 10. 洗练按钮文本
XL.REFINE_TEXT_FONT_SIZE = 40; XL.REFINE_TEXT_R = 255; XL.REFINE_TEXT_G = 214; XL.REFINE_TEXT_B = 102

-- ======================== 洗练界面数据 ========================

refineData = {
    -- 洗练前随机词缀
    before = {
        { name = "暴击率", value = "5%",  grade = "C" },
        { name = "生命值", value = "120", grade = "D" },
    },
    corruptBaseHint = nil,
    -- 洗练后随机词缀
    after = {
        { name = "暴击率", value = "8%",  grade = "B" },
        { name = "生命值", value = "200", grade = "C" },
    },
    -- 累计洗练次数
    refineCount = 3,
    -- 资源需求（精粹）
    costEssence  = 300,
    ownedEssence = 100,
}

-- ======================== 额外资源选择状态 ========================

--- 额外资源定义
local EXTRA_RES_OPTIONS = {
    { key = "enhanceStone", name = "洗练石", iconPath = "image/货币道具/UI_icon_QH_1.png", quality = 3, cost = 1 },
    { key = "destroyStone", name = "点金石", iconPath = "image/货币道具/UI_icon_QH_3.png", quality = 5, cost = nil },  -- cost 动态：当前品质即为消耗数
    { key = "corruptStone", name = "腐化石", iconPath = "image/货币道具/UI_icon_FHS.png", quality = 3, cost = 1 },
    { key = "sacredStone", name = "神圣石", iconPath = "image/货币道具/UI_icon_SSS.png", quality = 6, cost = 1 },
}

--- 当前选中的额外资源 (nil = 未选择)
selectedExtraRes = nil  -- EXTRA_RES_OPTIONS[n] or nil

--- 额外资源选择弹窗是否打开
local extraResPopupOpen = false

-- ======================== 洗练动画状态 ========================

local refineAnim = {
    type      = nil,    -- "refine" | "replace" | nil
    startTime = 0,
    duration  = 0.4,
    oldAfter  = nil,    -- table[] 旧的洗练后数据（用于滑出动画）
    replaceSnapshot = nil,  -- table[] 替换时的洗练后快照
}

local REFINE_ANIM_DURATION  = 0.4
local REPLACE_ANIM_DURATION = 0.35

--- 点金石是提品，不叫升阶，也不叫洗练
local function isRaiseRarity()
    return selectedExtraRes and selectedExtraRes.key == "destroyStone"
end
local autoReplaceScheduled = false

--- 点金石品质提升展示状态
local qualityUpgradeInfo = nil  -- { fromQ = number, toQ = number, startTime = number } or nil
local QUALITY_UPGRADE_DISPLAY_DURATION = 2.0  -- 品质提升展示持续时间（秒）

--- 腐化/净化结果展示状态
local corruptResultInfo = nil  -- { title = string, effectName = string, hint = string, startTime = number } or nil
local CORRUPT_RESULT_DISPLAY_DURATION = 4.0

-- ======================== ctx 引用（由 setContext 注入） ========================

local imgLock          -- 词缀锁定图标
local imgEnhBtn        -- 洗练按钮背景（绿色）
local imgReplaceBtn    -- 替换按钮背景（黄色）
local imgEssenceIcon   -- 精粹图标
local imgGoldQBg       -- 精粹品质背景框
local imgXlBefore      -- 洗练前/后共用单框背景图
local imgGrade         -- 词缀等级图标 table
local imgPlus          -- 加号图标
local imgQualityBg     -- 品质背景框 table {[1]~[5]}
local imgExtraRes = {} -- 额外资源图标 { [key] = nvgImageHandle }
local formatAffixValue -- 词缀值格式化函数
local QUALITY_COST     -- 品质消耗配置
-- state 已在文件顶部前置声明，此处仅注释说明
local getClient        -- 延迟加载 Client
local getProtocol      -- 延迟加载 Protocol

--- 注入共享上下文
---@param ctx table 由 BlacksmithPage 构造的共享上下文
function M.setContext(ctx)
    imgLock            = ctx.imgLock
    imgEnhBtn          = ctx.imgEnhBtn
    imgReplaceBtn      = ctx.imgReplaceBtn
    imgEssenceIcon     = ctx.imgEssenceIcon
    imgGoldQBg         = ctx.imgGoldQBg
    imgXlBefore        = ctx.imgXlBefore
    imgGrade           = ctx.imgGrade
    imgPlus            = ctx.imgPlus
    imgQualityBg       = ctx.imgQualityBg
    formatAffixValue   = ctx.formatAffixValue
    QUALITY_COST       = ctx.QUALITY_COST
    state              = ctx.state
    getClient          = ctx.getClient
    getProtocol        = ctx.getProtocol
end

--- 仅重算精粹消耗（不重置预览/动画/额外资源状态）
--- 用于 equipment 数据推送后刷新 selectedEquip 引用时调用
function M.refreshCostOnly()
    recalcRefineEssenceCost()
end

--- 初始化额外资源图标
---@param vg any NanoVG context
function M.init(vg)
    for _, opt in ipairs(EXTRA_RES_OPTIONS) do
        imgExtraRes[opt.key] = nvgCreateImage(vg, opt.iconPath, 0)
    end
    print("[BlacksmithRefine] init OK, loaded " .. #EXTRA_RES_OPTIONS .. " extra res icons")
end

-- ======================== 缓动函数 ========================

local function easeOutCubic(t)
    t = t - 1
    return t * t * t + 1
end

local function getAffixTemplate(affix)
    if not affix then return nil end
    local affixId = tonumber(affix.affixId) or affix.affixId
    if affixId and AffixConfig.BY_ID[affixId] then
        return AffixConfig.BY_ID[affixId]
    end
    if affix.key and AffixConfig.BY_KEY[affix.key] then
        return AffixConfig.BY_KEY[affix.key]
    end
    return nil
end

---@param row table
---@param index number
---@param affix table
---@param equip table|nil
---@param corruptMeta table|nil
local function annotateAffixCorruptRow(row, index, affix, equip, corruptMeta)
    -- 魔化词条只显示紫色名称/数值（品级标不变），不附加标签与百分比对比
    if AffixConfig.isCorruptAffix(affix) then
        return row
    end
    if corruptMeta then
        local beforeVal = corruptMeta.scaleByIndex[index]
        if beforeVal ~= nil then
            local beforeEff = beforeVal
            if equip and not AffixConfig.isCorruptAffix(affix) then
                beforeEff = beforeVal * EquipmentSystem.getAffixMult(equip)
            end
            local beforeFmt = formatAffixValue(affix.key, beforeEff, affix.affixId)
            local afterFmt = row.value
            local av = tonumber(affix.value) or 0
            if av > beforeVal * 1.01 then
                row.corruptTag = "腐化强化"
            elseif av < beforeVal * 0.99 then
                row.corruptTag = "腐化削弱"
            else
                row.corruptTag = "腐化变化"
            end
            row.compareText = beforeFmt .. " → " .. afterFmt
        elseif index > (corruptMeta.originalAffixCount or 0) then
            local isCorruptAffix = false
            for _, tpl in ipairs(AffixConfig.CORRUPT_AFFIXES or {}) do
                if tpl.id == affix.affixId or tpl.key == affix.key then
                    isCorruptAffix = true
                    break
                end
            end
            row.corruptTag = isCorruptAffix and "魔化词条" or "腐化新增"
        end
    end
    return row
end

---@param affix table
---@param equip table|nil
---@param index number|nil
---@param corruptMeta table|nil
---@return table
local function affixToDisplayRow(affix, equip, index, corruptMeta)
    if equip then
        EquipmentSystem.ensureAffixValue(affix, equip)
    end
    local isCorrupt = AffixConfig.isCorruptAffix(affix)
    local qDef = AffixConfig.QUALITY[affix.quality]
    local effVal = equip and EquipmentSystem.effectiveAffixValue(equip, affix) or affix.value
    local row = {
        name = affix.name or affix.key or "?",
        value = formatAffixValue(affix.key, effVal, affix.affixId),
        grade = qDef and qDef.name or "D",
        isCorrupt = isCorrupt,
    }
    if isCorrupt then
        row.nameColor = { CORRUPT_TAG_R, CORRUPT_TAG_G, CORRUPT_TAG_B }
        row.valueColor = { CORRUPT_TAG_R, CORRUPT_TAG_G, CORRUPT_TAG_B }
    end
    if index and corruptMeta then
        annotateAffixCorruptRow(row, index, affix, equip, corruptMeta)
    end
    return row
end

---@param affixes table[]
---@param equip table|nil
---@param corruptMeta table|nil
---@return table[]
local function buildAffixDisplayRows(affixes, equip, corruptMeta)
    local rows = {}
    for i, affix in ipairs(affixes or {}) do
        rows[#rows + 1] = affixToDisplayRow(affix, equip, i, corruptMeta)
    end
    return rows
end

---@param detail table|nil
---@param beforeAffixes table[]
---@param afterAffixes table[]
---@param equip table|nil
---@return table[]
local function buildCorruptAfterRows(detail, beforeAffixes, afterAffixes, equip)
    local changeByIndex = {}
    for _, ch in ipairs(detail and detail.affixChanges or {}) do
        changeByIndex[ch.index] = ch
    end
    local rows = {}
    for i, affix in ipairs(afterAffixes or {}) do
        local row = affixToDisplayRow(affix, equip, i, nil)
        local ch = changeByIndex[i]
        if ch then
            if ch.kind == "added" then
                row.corruptTag = "魔化词条"
            elseif ch.kind == "scale" then
                local beforeEff = ch.beforeValue
                if equip and not AffixConfig.isCorruptAffix(affix) then
                    beforeEff = ch.beforeValue * EquipmentSystem.getAffixMult(equip)
                end
                local beforeFmt = formatAffixValue(ch.key, beforeEff, ch.affixId)
                if ch.afterValue > ch.beforeValue then
                    row.corruptTag = "腐化强化"
                else
                    row.corruptTag = "腐化削弱"
                end
                row.compareText = beforeFmt .. " → " .. row.value
            end
        end
        rows[#rows + 1] = row
    end
    return rows
end

-- ======================== 数据更新 ========================

--- 是否已有洗练预览（等待替换）
function M.hasPreview()
    return refineData.hasPreview == true
end

--- 从装备词缀重建洗练前/后展示数据（不重置动画）
---@param equip table
local function applyRefineDisplayFromEquip(equip)
    EquipmentSystem.hydrate(equip)

    local corruptMeta = getCorruptCount(equip) > 0 and parseCorruptRevertMeta(equip) or nil
    refineData.before = buildAffixDisplayRows(equip.affixes, equip, corruptMeta)

    local after = {}
    for i = 1, #refineData.before do
        after[i] = { name = refineData.before[i].name, value = "?", grade = "?" }
    end

    refineData.after = after
    refineData.hasPreview = false
    refineData.refineCount = BlacksmithConfig.clampRefineCount(equip.refineCount)
    recalcRefineEssenceCost()
    refineData.ownedEssence = GameState.getEssence()
end

--- 根据选中装备更新洗练面板数据
function M.updateRefineData(equip)
    if not equip then
        refineData.before       = {}
        refineData.after        = {}
        refineData.hasPreview   = false
        refineData.refineCount  = 0
        refineData.costEssence  = 0
        refineData.ownedEssence = GameState.getEssence()
        refineAnim.type = nil
        refineAnim.oldAfter = nil
        refineAnim.replaceSnapshot = nil
        autoReplaceScheduled = false
        qualityUpgradeInfo = nil
        corruptResultInfo = nil
        -- 重置额外资源选择
        selectedExtraRes = nil
        extraResPopupOpen = false
        return
    end

    applyRefineDisplayFromEquip(equip)
    -- 重置洗练动画
    refineAnim.type = nil
    refineAnim.oldAfter = nil
    refineAnim.replaceSnapshot = nil
    -- 重置额外资源选择
    selectedExtraRes = nil
    extraResPopupOpen = false
end

-- ======================== 绘制函数 ========================

--- 绘制洗练属性行列表（洗练前/洗练后通用，左右排布后的半幅面板）
---@param vg any NanoVG context
---@param attrs table 属性列表 { {name, value, grade}, ... }
---@param firstY number 第一行 Y 中心
---@param panelLeft number 面板左缘 X（行内元素按面板相对坐标定位）
---@param offsetX number|nil X偏移量（动画用，默认0）
---@param alpha number|nil 透明度 0-255（动画用，默认255）
---@param lockOpts table|nil { showLocks=true, lockedSet=table }
local function drawRefineAttrRows(vg, attrs, firstY, panelLeft, offsetX, alpha, lockOpts)
    offsetX = offsetX or 0
    alpha = alpha or 255
    local a = math.floor(math.max(0, math.min(255, alpha)))
    if a <= 0 then return end

    for i, attr in ipairs(attrs) do
        local rowY = firstY + (i - 1) * XL.ATTR_ROW_STEP

        -- 品质图标 / 魔化紫色圆标
        if attr.isCorrupt then
            local r = XL.ATTR_ICON_SIZE * 0.22
            nvgBeginPath(vg)
            nvgCircle(vg, panelLeft + XL.ATTR_ICON_CX + offsetX, rowY, r)
            nvgFillColor(vg, nvgRGBA(0x9B, 0x4D, 0xFF, a))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, panelLeft + XL.ATTR_ICON_CX + offsetX, rowY, r)
            nvgStrokeWidth(vg, 2)
            nvgStrokeColor(vg, nvgRGBA(0xE0, 0xB0, 0xFF, math.floor(a * 0.85)))
            nvgStroke(vg)
        else
            local gradeIcon = imgGrade[attr.grade] or -1
            if gradeIcon >= 0 then
                drawImageCentered(vg, gradeIcon, panelLeft + XL.ATTR_ICON_CX + offsetX, rowY, XL.ATTR_ICON_SIZE, XL.ATTR_ICON_SIZE, a / 255)
            end
        end

        -- 属性名（左对齐，超长缩字号）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, XL.ATTR_FONT_SIZE)
        local nameW = nvgTextBounds(vg, 0, 0, attr.name)
        if nameW > XL.ATTR_NAME_MAX_W then
            nvgFontSize(vg, XL.ATTR_NAME_FONT_SMALL)
            nameW = nvgTextBounds(vg, 0, 0, attr.name)
        end
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local nameRGB = attr.nameColor or { XL.ATTR_NAME_R, XL.ATTR_NAME_G, XL.ATTR_NAME_B }
        nvgFillColor(vg, nvgRGBA(nameRGB[1], nameRGB[2], nameRGB[3], a))
        nvgText(vg, panelLeft + XL.ATTR_NAME_X + offsetX, rowY, attr.name, nil)

        -- 腐化标签（词缀名右侧）
        if attr.corruptTag and attr.corruptTag ~= "" then
            nvgFontSize(vg, XL.CORRUPT_TAG_FONT)
            nvgFillColor(vg, nvgRGBA(CORRUPT_TAG_R, CORRUPT_TAG_G, CORRUPT_TAG_B, a))
            nvgText(vg, panelLeft + XL.ATTR_NAME_X + offsetX + nameW + 6, rowY, "[" .. attr.corruptTag .. "]", nil)
        end

        -- 数值（右对齐）：腐化对比时数值行下移一行展示「旧 → 新」
        local valueText = tostring(attr.value or "")
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        local valRGB = attr.valueColor or { XL.ATTR_VAL_R, XL.ATTR_VAL_G, XL.ATTR_VAL_B }
        nvgFillColor(vg, nvgRGBA(valRGB[1], valRGB[2], valRGB[3], a))
        nvgText(vg, panelLeft + XL.ATTR_VALUE_X + offsetX, rowY, valueText, nil)

        if attr.compareText then
            nvgFontSize(vg, XL.COMPARE_FONT)
            nvgFillColor(vg, nvgRGBA(CORRUPT_COMPARE_R, CORRUPT_COMPARE_G, CORRUPT_COMPARE_B, a))
            nvgText(vg, panelLeft + XL.ATTR_VALUE_X + offsetX, rowY + XL.COMPARE_LINE_DY, attr.compareText, nil)
        end

        -- 词缀锁定图标（仅洗练前区域）
        if lockOpts and lockOpts.showLocks and imgLock and imgLock >= 0 then
            local locked = lockOpts.lockedSet and lockOpts.lockedSet[i]
            local lockAlpha = (locked and 1.0 or 0.35) * (a / 255)
            drawImageCentered(vg, imgLock, panelLeft + XL.LOCK_ICON_CX + offsetX, rowY,
                XL.LOCK_ICON_SIZE, XL.LOCK_ICON_SIZE, lockAlpha)
        end
    end
end

--- 洗练前词缀行是否显示锁定按钮（点金石提品/腐化石魔化/神圣石净化不涉及锁词缀）
---@return boolean
local function shouldShowAffixLocks()
    if selectedExtraRes and (selectedExtraRes.key == "destroyStone" or selectedExtraRes.key == "corruptStone" or selectedExtraRes.key == "sacredStone") then
        return false
    end
    return true
end

--- 当前选中装备的锁定绘制参数
---@return table|nil
local function getBeforeLockDrawOpts()
    if not shouldShowAffixLocks() or not state.selectedEquip then
        return nil
    end
    return {
        showLocks = true,
        lockedSet = getAffixLockSet(state.selectedEquip.seq),
    }
end

--- 绘制洗练界面上半部分
function M.drawPanel(vg)
    local data = refineData

    -- 计算动画进度
    local animT = 0       -- 0..1 动画进度
    local animType = refineAnim.type
    if animType then
        local elapsed = time.elapsedTime - refineAnim.startTime
        animT = math.min(1.0, elapsed / refineAnim.duration)
        if animT >= 1.0 then
            -- 动画结束，清理状态
            refineAnim.type = nil
            refineAnim.oldAfter = nil
            refineAnim.replaceSnapshot = nil
            animType = nil
            animT = 0

            -- 点金石自动替换：洗练动画结束后立即触发替换动画
            if autoReplaceScheduled then
                autoReplaceScheduled = false
                refineAnim.replaceSnapshot = refineData.after
                refineAnim.type = "replace"
                refineAnim.startTime = time.elapsedTime
                refineAnim.duration = REPLACE_ANIM_DURATION
                animType = "replace"
                animT = 0
                -- 更新状态：已替换完成
                state.pendingRefineAffixes = nil
                state.pendingRefineSeq = nil
                refineData.hasPreview = false
                if state.selectedEquip then
                    applyRefineDisplayFromEquip(state.selectedEquip)
                end
            end
        end
    end

    -- 替换动画的 X 偏移量（单框内：右半洗练后内容左移到左半位置）
    local replaceXOffset = 0   -- 洗练后内容的 X 偏移
    local replaceAlpha = 255   -- 洗练前内容淡出透明度
    local beforeXDelta = XL.RIGHT_PANEL_LEFT - XL.LEFT_PANEL_LEFT  -- 500
    if animType == "replace" then
        local eased = easeOutCubic(animT)
        replaceXOffset = -beforeXDelta * eased   -- 从 0 移到 -500（左移）
        replaceAlpha = math.floor(255 * (1 - eased))  -- 洗练前淡出
    end
    local frameLeft = XL.FRAME_CX - XL.FRAME_W * 0.5

    -- 1. 标题：点金石路径叫提品，避免和装备升阶、普通洗练混在一起
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, XL.TITLE_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(XL.ATTR_VAL_R, XL.ATTR_VAL_G, XL.ATTR_VAL_B, 255))
    nvgText(vg, XL.TITLE_CX, XL.TITLE_CY, isRaiseRarity() and "提品" or "洗练装备", nil)

    -- 腐化次数（已腐化装备显示）
    local corruptCount = getCorruptCount(state and state.selectedEquip)
    if corruptCount > 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, XL.CORRUPT_TEXT_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xef, 0x79, 0xff, 255))
        local corruptText = string.format("腐化状态：诅咒 %d/%d 层", corruptCount, MAX_CORRUPT_COUNT)
        if corruptCount >= MAX_CORRUPT_COUNT then
            corruptText = corruptText .. "（需神圣石洗除）"
        end
        nvgText(vg, XL.CORRUPT_TEXT_CX, XL.CORRUPT_TEXT_Y, corruptText, nil)
    end

    -- 2. 单一背景框（洗练前/后内容共用，无「洗练前/后」标题字）
    drawImageCentered(vg, imgXlBefore, XL.FRAME_CX, XL.FRAME_CY, XL.FRAME_W, XL.FRAME_H, 1.0)

    -- 3. 洗练前属性行（框内左半）
    local beforeLeft = frameLeft + XL.LEFT_PANEL_LEFT
    local beforeLockOpts = getBeforeLockDrawOpts()
    if #data.before > 0 then
        local firstY = refineRowFirstY(#data.before)
        if animType == "replace" then
            drawRefineAttrRows(vg, data.before, firstY, beforeLeft, 0, replaceAlpha, beforeLockOpts)
        else
            drawRefineAttrRows(vg, data.before, firstY, beforeLeft, 0, 255, beforeLockOpts)
        end
    else
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x91, 0x8f, 0x88, 180))
        nvgText(vg, XL.LEFT_HALF_CX, XL.FRAME_CY, "当前装备无可洗练词缀", nil)
    end

    -- 11. 洗练后属性行
    -- 检查品质提升展示是否超时
    if qualityUpgradeInfo then
        local elapsed = time.elapsedTime - qualityUpgradeInfo.startTime
        if elapsed > QUALITY_UPGRADE_DISPLAY_DURATION then
            qualityUpgradeInfo = nil
        end
    end
    if corruptResultInfo then
        local elapsed = time.elapsedTime - corruptResultInfo.startTime
        if elapsed > CORRUPT_RESULT_DISPLAY_DURATION then
            corruptResultInfo = nil
            if state.selectedEquip then
                applyRefineDisplayFromEquip(state.selectedEquip)
            end
        end
    end

    if qualityUpgradeInfo then
        -- 点金石品质提升展示：显示品质变化而非词缀
        local qi = qualityUpgradeInfo
        local elapsed = time.elapsedTime - qi.startTime
        local fadeIn = math.min(1.0, elapsed / 0.3)  -- 0.3秒淡入

        local fromQDef = EquipmentConfig.QUALITY[qi.fromQ]
        local toQDef = EquipmentConfig.QUALITY[qi.toQ]
        local fromName = fromQDef and fromQDef.name or "未知"
        local toName = toQDef and toQDef.name or "未知"
        local fromColor = fromQDef and fromQDef.color or "ffffff"
        local toColor = toQDef and toQDef.color or "ffffff"

        -- 解析颜色 hex → RGB
        local function hexToRGB(hex)
            local r = tonumber(hex:sub(1, 2), 16) or 255
            local g = tonumber(hex:sub(3, 4), 16) or 255
            local b = tonumber(hex:sub(5, 6), 16) or 255
            return r, g, b
        end
        local fR, fG, fB = hexToRGB(fromColor)
        local tR, tG, tB = hexToRGB(toColor)

        local alpha = math.floor(255 * fadeIn)
        local centerY = XL.FRAME_CY

        -- "提品" 标题（点金石提品，不叫升阶）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xbc, 0xb8, 0xaa, alpha))
        nvgText(vg, XL.RIGHT_HALF_CX, centerY - 40, "提品", nil)

        -- "旧品质 → 新品质" 展示
        nvgFontSize(vg, 42)
        local arrowStr = " → "
        local fromW = nvgTextBounds(vg, 0, 0, fromName)
        local arrowW = nvgTextBounds(vg, 0, 0, arrowStr)
        local toW = nvgTextBounds(vg, 0, 0, toName)
        local totalW = fromW + arrowW + toW
        local startX = XL.RIGHT_HALF_CX - totalW * 0.5

        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        -- 旧品质名
        nvgFillColor(vg, nvgRGBA(fR, fG, fB, alpha))
        nvgText(vg, startX, centerY + 10, fromName, nil)
        -- 箭头
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        nvgText(vg, startX + fromW, centerY + 10, arrowStr, nil)
        -- 新品质名（高亮）
        nvgFillColor(vg, nvgRGBA(tR, tG, tB, alpha))
        nvgText(vg, startX + fromW + arrowW, centerY + 10, toName, nil)

        -- "词缀已更新" 提示
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x91, 0x8f, 0x88, math.floor(alpha * 0.7)))
        nvgText(vg, XL.RIGHT_HALF_CX, centerY + 60, "词缀已自动生成", nil)
    elseif corruptResultInfo then
        -- 腐化石结果展示：词缀前后对比 + 效果说明（单框右半）
        local ci = corruptResultInfo
        local elapsed = time.elapsedTime - ci.startTime
        local fadeIn = math.min(1.0, elapsed / 0.3)
        local alpha = math.floor(255 * fadeIn)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xbc, 0xb8, 0xaa, alpha))
        nvgText(vg, XL.RIGHT_HALF_CX, 1030, "腐化结果", nil)

        nvgFontSize(vg, 28)
        nvgFillColor(vg, nvgRGBA(CORRUPT_TAG_R, CORRUPT_TAG_G, CORRUPT_TAG_B, alpha))
        nvgText(vg, XL.RIGHT_HALF_CX, 1066, ci.effectName or "魔化完成", nil)

        local afterRows = ci.afterRows
        if afterRows and #afterRows > 0 then
            local afterLeft = frameLeft + XL.RIGHT_PANEL_LEFT
            local firstY = refineRowFirstY(#afterRows) + 36
            drawRefineAttrRows(vg, afterRows, firstY, afterLeft, 0, alpha)
        else
            nvgFontSize(vg, 28)
            nvgFillColor(vg, nvgRGBA(0x91, 0x8f, 0x88, math.floor(alpha * 0.75)))
            nvgText(vg, XL.RIGHT_HALF_CX, XL.FRAME_CY, ci.hint or "效果已直接应用到装备", nil)
        end
    elseif #data.before == 0 then
        -- 无词缀装备
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x91, 0x8f, 0x88, 180))
        nvgText(vg, XL.RIGHT_HALF_CX, XL.FRAME_CY, "当前装备无可洗练词缀", nil)
    elseif animType == "replace" then
        -- 替换动画：右半洗练后内容左移到左半（使用快照数据）
        local snapshot = refineAnim.replaceSnapshot or data.after
        local afterLeft = frameLeft + XL.RIGHT_PANEL_LEFT
        local afterFirstY = refineRowFirstY(#snapshot)
        drawRefineAttrRows(vg, snapshot, afterFirstY, afterLeft + replaceXOffset)
    elseif animType == "refine" then
        -- 洗练刷新动画：旧词条右滑出，新词条左滑入（单框右半内）
        local eased = easeOutCubic(animT)
        local slideRange = 240  -- 滑动距离（右半幅内）
        local afterLeft = frameLeft + XL.RIGHT_PANEL_LEFT
        local afterFirstY = refineRowFirstY(math.max(#data.after, 1))
        -- 旧词条右滑出（淡出）
        local oldData = refineAnim.oldAfter
        if oldData and #oldData > 0 then
            local oldOffX = slideRange * eased          -- 0 → 240
            local oldAlpha = 255 * (1 - eased)          -- 255 → 0
            drawRefineAttrRows(vg, oldData, refineRowFirstY(#oldData), afterLeft, oldOffX, oldAlpha)
        end
        -- 新词条左滑入（淡入）
        local newOffX = -slideRange * (1 - eased)       -- -240 → 0
        local newAlpha = 255 * eased                    -- 0 → 255
        drawRefineAttrRows(vg, data.after, afterFirstY, afterLeft, newOffX, newAlpha)
    elseif not data.hasPreview then
        -- 未洗练状态：显示提示文本
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x91, 0x8f, 0x88, 180))
        nvgText(vg, XL.RIGHT_HALF_CX, XL.FRAME_CY,
            isRaiseRarity() and "请点击提品，提升装备品质" or "请点击洗练按钮来刷出新词条", nil)
    else
        -- 正常显示洗练后属性行（单框右半）
        local afterLeft = frameLeft + XL.RIGHT_PANEL_LEFT
        drawRefineAttrRows(vg, data.after, refineRowFirstY(#data.after), afterLeft)
    end

    -- 5. 亮色箭头最后绘制：滑行动画的词条行从其下方穿过，箭头保持可见
    -- 程序化亮金双 chevron（原深色位图在暗底上不可见）
    DrawUtil.drawDoubleChevron(vg, XL.ARROW_CX, XL.ARROW_CY, XL.ARROW_W, XL.ARROW_H, 0xff, 0xd6, 0x66)
end

--- 绘制资源数量 "owned/cost" 居中于指定 cx
--- 数字缩写：超过4位数转为 k 格式（如 12345 → "12.3k"）
local function formatShortNum(n)
    if n >= 10000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(n)
end

---@param vg any
---@param cx number 居中 X
---@param ownedVal number 拥有数量
---@param costVal number 需求数量
local function drawResCount(vg, cx, ownedVal, costVal)
    -- 数值背景框（纯黑 80%）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - XL.RES_COUNT_BG_W * 0.5, XL.RES_COUNT_BG_CY - XL.RES_COUNT_BG_H * 0.5,
        XL.RES_COUNT_BG_W, XL.RES_COUNT_BG_H, XL.RES_COUNT_BG_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
    nvgFill(vg)

    local ownedStr = formatShortNum(ownedVal)
    local costStr  = formatShortNum(costVal)
    local enough = ownedVal >= costVal
    local oR, oG, oB
    if enough then
        oR, oG, oB = XL.ENOUGH_R, XL.ENOUGH_G, XL.ENOUGH_B
    else
        oR, oG, oB = 0x8b, 0x95, 0xa5  -- 不足=灰蓝色（全局统一）
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local ownedW = nvgTextBounds(vg, 0, 0, ownedStr)
    local sepCostStr = "/" .. costStr
    local sepCostW = nvgTextBounds(vg, 0, 0, sepCostStr)
    local totalW = ownedW + sepCostW
    local sx = cx - totalW * 0.5
    nvgFillColor(vg, nvgRGBA(oR, oG, oB, 255))
    nvgText(vg, sx, XL.RES_COUNT_BG_CY, ownedStr, nil)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, sx + ownedW, XL.RES_COUNT_BG_CY, sepCostStr, nil)
end

--- 绘制额外资源选择弹窗（浮在额外资源槽位上方）
---@param vg any
local function drawExtraResPopup(vg)
    if not extraResPopupOpen then return end

    local popupW = 320
    local itemH = 80
    local popupH = #EXTRA_RES_OPTIONS * itemH + 16  -- 上下各 8 padding
    local popupCX = XL.EXTRA_ICON_CX
    local popupBottom = XL.EXTRA_ICON_CY - XL.EXTRA_ICON_SIZE * 0.5 - 8  -- 弹窗底部在槽位上方 8px
    local popupTop = popupBottom - popupH
    local popupLeft = popupCX - popupW * 0.5

    -- 弹窗背景（深色半透明）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popupLeft, popupTop, popupW, popupH, 16)
    nvgFillColor(vg, nvgRGBA(30, 25, 20, 230))
    nvgFill(vg)
    -- 边框
    nvgStrokeColor(vg, nvgRGBA(120, 100, 80, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 绘制每个选项
    for i, opt in ipairs(EXTRA_RES_OPTIONS) do
        local itemY = popupTop + 8 + (i - 1) * itemH + itemH * 0.5
        local iconX = popupLeft + 50
        local textX = popupLeft + 90

        -- 高亮当前选中
        if selectedExtraRes and selectedExtraRes.key == opt.key then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, popupLeft + 6, itemY - itemH * 0.5 + 4, popupW - 12, itemH - 8, 10)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 25))
            nvgFill(vg)
        end

        -- 品质背景 + 图标（小尺寸）[暗黑化 P2-A]
        DarkIcon.drawQualityBg(vg, opt.quality, iconX, itemY, 56, 56, 1.0)
        local icon = imgExtraRes[opt.key]
        if icon and icon >= 0 then
            drawImageCentered(vg, icon, iconX, itemY, 56, 56, 1.0)
        end

        -- 名称
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 230, 210, 255))
        if opt.key == "destroyStone" then
            nvgText(vg, textX, itemY - 12, opt.name, nil)
            nvgFontSize(vg, 22)
            nvgFillColor(vg, nvgRGBA(255, 214, 102, 255))
            nvgText(vg, textX, itemY + 16, "提品", nil)
        else
            nvgText(vg, textX, itemY, opt.name, nil)
        end

        -- 拥有数量（右侧）
        local ownedCount = 0
        if opt.key == "enhanceStone" then
            ownedCount = GameState.getEnhanceStone()
        elseif opt.key == "destroyStone" then
            ownedCount = GameState.getDestroyStone()
        elseif opt.key == "corruptStone" then
            ownedCount = GameState.getCorruptStone()
        elseif opt.key == "sacredStone" then
            ownedCount = GameState.getSacredStone()
        end
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 170, 150, 200))
        nvgText(vg, popupLeft + popupW - 16, itemY, "x" .. ownedCount, nil)
    end
end

--- 绘制洗练界面下半部分（需求、资源、替换/洗练按钮）
function M.drawPanelBottom(vg)
    local data = refineData

    -- 1. "洗练需求" 文本（居中对齐）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, XL.REQ_TITLE_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(XL.REQ_TITLE_R, XL.REQ_TITLE_G, XL.REQ_TITLE_B, 255))
    nvgText(vg, XL.REQ_TITLE_X, XL.REQ_TITLE_Y, isRaiseRarity() and "提品需求" or "洗练需求", nil)

    -- 2. "当前装备累计洗练XX次"（右对齐；费用固定，次数仅统计）
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    local countText = tostring(data.refineCount) .. "次"
    nvgText(vg, XL.REQ_COUNT_X, XL.REQ_COUNT_Y, "当前装备累计洗练" .. countText, nil)

    -- 3. 洗练需求背景框（暗底上压暗 25% 形成区域感）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, XL.REQ_BG_CX - XL.REQ_BG_W * 0.5, XL.REQ_BG_CY - XL.REQ_BG_H * 0.5,
        XL.REQ_BG_W, XL.REQ_BG_H, XL.REQ_BG_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 64))
    nvgFill(vg)

    -- 4. 精粹资源图标（左侧）
    DarkIcon.drawQualityBg(vg, 2, XL.RES_ICON_CX, XL.RES_ICON_CY, XL.RES_ICON_SIZE, XL.RES_ICON_SIZE, 1.0)  -- [暗黑化 P2-A] 原 UI_icon_ZBBJ_2
    drawImageCentered(vg, imgEssenceIcon, XL.RES_ICON_CX, XL.RES_ICON_CY, XL.RES_ICON_SIZE, XL.RES_ICON_SIZE, 1.0)

    -- 5. 精粹资源数量（实时读取，与额外资源保持一致）
    -- 防御性重算：如果 costEssence 为 0 但有装备选中，强制重算
    if data.costEssence == 0 and state and state.selectedEquip then
        recalcRefineEssenceCost()
    end
    drawResCount(vg, XL.RES_COUNT_BG_CX, GameState.getEssence(), data.costEssence)

    -- 4b. 额外资源槽位（右侧）
    if selectedExtraRes then
        -- 已选择：显示品质背景 + 资源图标 [暗黑化 P2-A]
        DarkIcon.drawQualityBg(vg, selectedExtraRes.quality, XL.EXTRA_ICON_CX, XL.EXTRA_ICON_CY, XL.EXTRA_ICON_SIZE, XL.EXTRA_ICON_SIZE, 1.0)
        local icon = imgExtraRes[selectedExtraRes.key]
        if icon and icon >= 0 then
            drawImageCentered(vg, icon, XL.EXTRA_ICON_CX, XL.EXTRA_ICON_CY, XL.EXTRA_ICON_SIZE, XL.EXTRA_ICON_SIZE, 1.0)
        end
        -- 额外资源数量
        local extraOwned = 0
        if selectedExtraRes.key == "enhanceStone" then
            extraOwned = GameState.getEnhanceStone()
        elseif selectedExtraRes.key == "destroyStone" then
            extraOwned = GameState.getDestroyStone()
        elseif selectedExtraRes.key == "corruptStone" then
            extraOwned = GameState.getCorruptStone()
        elseif selectedExtraRes.key == "sacredStone" then
            extraOwned = GameState.getSacredStone()
        end
        -- 点金石消耗=当前品质，洗练石=固定1
        local extraCost = selectedExtraRes.cost or (state.selectedEquip and state.selectedEquip.quality or 1)
        drawResCount(vg, XL.EXTRA_COUNT_BG_CX, extraOwned, extraCost)
    else
        -- 未选择：显示黑色半透明背景 + 加号图标
        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            XL.EXTRA_ICON_CX - XL.EXTRA_ICON_SIZE * 0.5,
            XL.EXTRA_ICON_CY - XL.EXTRA_ICON_SIZE * 0.5,
            XL.EXTRA_ICON_SIZE, XL.EXTRA_ICON_SIZE, XL.EXTRA_BG_RADIUS)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 102))  -- 40% opacity
        nvgFill(vg)
        -- 加号图标
        if imgPlus and imgPlus >= 0 then
            drawImageCentered(vg, imgPlus, XL.EXTRA_ICON_CX, XL.EXTRA_ICON_CY, XL.EXTRA_PLUS_SIZE, XL.EXTRA_PLUS_SIZE, 0.6)
        end
    end

    -- 7. 替换按钮背景 UI_AN_HUANG
    local didReplace = BF.begin(vg, "bsr_replace", XL.REPLACE_BTN_CX, XL.REPLACE_BTN_CY, XL.REPLACE_BTN_W, XL.REPLACE_BTN_H)
    drawImageCentered(vg, imgReplaceBtn, XL.REPLACE_BTN_CX, XL.REPLACE_BTN_CY, XL.REPLACE_BTN_W, XL.REPLACE_BTN_H, 1.0)

    -- "替换" 文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, XL.REPLACE_TEXT_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(XL.REPLACE_TEXT_R, XL.REPLACE_TEXT_G, XL.REPLACE_TEXT_B, 255))
    nvgText(vg, XL.REPLACE_BTN_CX, XL.REPLACE_BTN_CY, "替换", nil)
    BF.finish(vg, didReplace)

    -- 8. 洗练按钮背景 UI_AN_LV
    local didRefine = BF.begin(vg, "bsr_refine", XL.REFINE_BTN_CX, XL.REFINE_BTN_CY, XL.REFINE_BTN_W, XL.REFINE_BTN_H)
    drawImageCentered(vg, imgEnhBtn, XL.REFINE_BTN_CX, XL.REFINE_BTN_CY, XL.REFINE_BTN_W, XL.REFINE_BTN_H, 1.0)

    -- "洗练" 文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, XL.REFINE_TEXT_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(XL.REFINE_TEXT_R, XL.REFINE_TEXT_G, XL.REFINE_TEXT_B, 255))
    nvgText(vg, XL.REFINE_BTN_CX, XL.REFINE_BTN_CY, isRaiseRarity() and "提品" or "洗练", nil)
    BF.finish(vg, didRefine)

    -- 额外资源选择弹窗（绘制在按钮之上）
    drawExtraResPopup(vg)
end

-- ======================== 输入处理 ========================

--- 处理洗练界面输入
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function M.handleInput(dx, dy)
    -- ===== 1. 额外资源弹窗交互（最上层，优先消费） =====
    if extraResPopupOpen then
        local popupW = 320
        local itemH = 80
        local popupH = #EXTRA_RES_OPTIONS * itemH + 16
        local popupCX = XL.EXTRA_ICON_CX
        local popupBottom = XL.EXTRA_ICON_CY - XL.EXTRA_ICON_SIZE * 0.5 - 8
        local popupTop = popupBottom - popupH
        local popupLeft = popupCX - popupW * 0.5

        -- 检查是否点击了弹窗内的选项
        if dx >= popupLeft and dx <= popupLeft + popupW and dy >= popupTop and dy <= popupBottom then
            local relY = dy - popupTop - 8  -- 减去上 padding
            local idx = math.floor(relY / itemH) + 1
            if idx >= 1 and idx <= #EXTRA_RES_OPTIONS then
                local opt = EXTRA_RES_OPTIONS[idx]
                if selectedExtraRes and selectedExtraRes.key == opt.key then
                    -- 再次点击已选中的 → 取消选择
                    selectedExtraRes = nil
                    print("[BlacksmithRefine] 取消额外资源: " .. opt.name)
                else
                    selectedExtraRes = opt
                    print("[BlacksmithRefine] 选择额外资源: " .. opt.name)
                end
                recalcRefineEssenceCost()
            end
            extraResPopupOpen = false
            return true
        end

        -- 点击弹窗外 → 关闭弹窗，消费事件
        extraResPopupOpen = false
        return true
    end

    -- ===== 2. 洗练前词缀锁定（点金石路径不显示锁；左侧面板内坐标） =====
    if shouldShowAffixLocks() and state.selectedEquip and #refineData.before > 0 then
        local seq = state.selectedEquip.seq
        local lockX = XL.FRAME_CX - XL.FRAME_W * 0.5 + XL.LEFT_PANEL_LEFT + XL.LOCK_ICON_CX
        local firstY = refineRowFirstY(#refineData.before)
        for i = 1, #refineData.before do
            local rowY = firstY + (i - 1) * XL.ATTR_ROW_STEP
            if hitTest(dx, dy, lockX, rowY, XL.LOCK_ICON_SIZE, XL.LOCK_ICON_SIZE) then
                toggleAffixLock(seq, i)
                print("[BlacksmithRefine] 词缀锁定切换 seq=" .. tostring(seq) .. " index=" .. i
                    .. " locked=" .. tostring(getAffixLockSet(seq)[i] == true))
                return true
            end
        end
    end

    -- ===== 3. 额外资源槽位点击（打开弹窗） =====
    if hitTest(dx, dy, XL.EXTRA_ICON_CX, XL.EXTRA_ICON_CY, XL.EXTRA_ICON_SIZE, XL.EXTRA_ICON_SIZE) then
        extraResPopupOpen = true
        print("[BlacksmithRefine] 打开额外资源选择弹窗")
        return true
    end

    -- ===== 4. 洗练按钮 =====
    if hitTest(dx, dy, XL.REFINE_BTN_CX, XL.REFINE_BTN_CY, XL.REFINE_BTN_W, XL.REFINE_BTN_H) then
        BF.trigger("bsr_refine")
        if state.selectedEquip then
            local seq = state.selectedEquip.seq
            local extraKey = selectedExtraRes and selectedExtraRes.key or nil
            local affixCount = #(state.selectedEquip.affixes or {})
            local lockedCount = getLockedCountForSeq(seq)
            if extraKey ~= "destroyStone" and extraKey ~= "corruptStone" and extraKey ~= "sacredStone" and affixCount > 0 and lockedCount >= affixCount then
                showRefineToast("至少保留1条词缀未锁定")
            elseif GameState.getEssence() < refineData.costEssence then
                showRefineToast("精粹不足，无法洗练")
            else
                local lockedIndices = getLockedIndicesArray(seq)
                print("[BlacksmithRefine] 洗练按钮点击 seq=" .. tostring(seq)
                    .. " extraRes=" .. tostring(extraKey)
                    .. " locked=" .. #lockedIndices)
                getClient().sendAction(getProtocol().ACTION_TYPES.REFINE_EQUIP, {
                    seq = seq,
                    extraResource = extraKey,
                    lockedIndices = (#lockedIndices > 0) and lockedIndices or nil,
                })
            end
        end
        return true
    end

    -- ===== 5. 替换按钮（确认使用洗练结果覆盖当前词缀） =====
    if hitTest(dx, dy, XL.REPLACE_BTN_CX, XL.REPLACE_BTN_CY, XL.REPLACE_BTN_W, XL.REPLACE_BTN_H) then
        BF.trigger("bsr_replace")
        if state.pendingRefineAffixes and state.pendingRefineSeq then
            local seq = state.pendingRefineSeq
            print("[BlacksmithRefine] 替换按钮点击 seq=" .. tostring(seq))
            getClient().sendAction(getProtocol().ACTION_TYPES.REFINE_REPLACE, {
                seq = seq,
            })
        else
            print("[BlacksmithRefine] 无待替换的洗练结果，请先洗练")
        end
        return true
    end
    return false
end

-- ======================== 动作结果处理 ========================

--- 处理洗练/替换动作结果
---@param data table 服务端返回数据
---@return boolean 是否已处理
function M.onActionResult(data)
    if data.success == false and data.reason then
        showRefineToast(data.reason)
        return true
    end

    -- 洗练结果预览（缓存新词缀，等待"替换"确认）
    if data.refinePreview then
        -- 点金石后期出口：品质不变，随机一条普通词缀品级 +1
        if data.autoReplaced and data.affixGradeUp and not data.upgradedQuality then
            if state.selectedEquip then
                state.selectedEquip.affixes = data.refinePreview
                if data.newQuality then
                    state.selectedEquip.quality = data.newQuality
                end
                EquipmentSystem.hydrate(state.selectedEquip)
            end
            refineData.before = buildAffixDisplayRows(data.refinePreview, state.selectedEquip, nil)
            refineData.after = {}
            refineData.hasPreview = false
            state.pendingRefineAffixes = nil
            state.pendingRefineSeq = nil
            qualityUpgradeInfo = nil

            local gu = data.affixGradeUp
            local beforeName = (gu.before and gu.before.name) or "?"
            local beforeGrade = (AffixConfig.QUALITY[(gu.before and gu.before.quality) or 1] or {}).name or "D"
            local afterGrade = (AffixConfig.QUALITY[gu.afterQ or 1] or {}).name or "S"
            corruptResultInfo = {
                title = "提品",
                effectName = string.format("词缀「%s」品级 %s → %s", beforeName, beforeGrade, afterGrade),
                hint = "装备品质已达进度上限，点金石转为提升词缀品级",
                startTime = time.elapsedTime,
            }

            if cancelCurrencyWatch_ then cancelCurrencyWatch_() end
            cancelCurrencyWatch_ = PlayerStore.WaitForChange("currency", {
                timeout = 2.0,
                onChange = function()
                    cancelCurrencyWatch_ = nil
                    refineData.ownedEssence = GameState.getEssence()
                end,
            })

            bumpRefineCountAndCost(state)
            print("[BlacksmithRefine] 点金石词缀提品: " .. beforeName .. " " .. beforeGrade .. "→" .. afterGrade)
            return true
        end

        -- 点金石路径：词缀不变，只提升品质，展示品质提升效果
        if data.autoReplaced and data.upgradedQuality then
            local oldQ = state.selectedEquip and (state.selectedEquip.quality or 1) or 1
            local newQ = data.upgradedQuality

            -- 更新选中装备的品质和词缀（服务端已补充生成新词缀）
            if state.selectedEquip then
                state.selectedEquip.quality = newQ
                state.selectedEquip.affixes = data.refinePreview
            end

            -- 刷新洗练前显示（反映新词缀）
            local before = {}
            for _, affix in ipairs(data.refinePreview or {}) do
                if state.selectedEquip then
                    EquipmentSystem.ensureAffixValue(affix, state.selectedEquip)
                end
                local qDef2 = AffixConfig.QUALITY[affix.quality]
                local gradeName = qDef2 and qDef2.name or "D"
                local effVal = state.selectedEquip
                    and EquipmentSystem.effectiveAffixValue(state.selectedEquip, affix) or affix.value
                before[#before + 1] = {
                    name = affix.name or affix.key or "?",
                    value = formatAffixValue(affix.key, effVal, affix.affixId),
                    grade = gradeName,
                }
            end
            refineData.before = before

            -- 不显示词缀预览，不设 pending 状态
            state.pendingRefineAffixes = nil
            state.pendingRefineSeq = nil
            refineData.hasPreview = false

            -- 设置品质提升展示信息
            qualityUpgradeInfo = {
                fromQ = oldQ,
                toQ = newQ,
                startTime = time.elapsedTime,
            }
            corruptResultInfo = nil

            -- 洗练扣了精粹，等 REPLICATED 到达后再刷新拥有量
            if cancelCurrencyWatch_ then cancelCurrencyWatch_() end
            cancelCurrencyWatch_ = PlayerStore.WaitForChange("currency", {
                timeout = 2.0,
                onChange = function()
                    cancelCurrencyWatch_ = nil
                    refineData.ownedEssence = GameState.getEssence()
                end,
            })

            -- 累计洗练次数+1 并重算下次消耗
            bumpRefineCountAndCost(state)

            print("[BlacksmithRefine] 点金石品质提升 " .. oldQ .. " → " .. newQ .. "，词缀保持不变")
            return true
        end

        -- 神圣石路径：服务端已洗除一层诅咒（逐层回退；剩余层数由 data.corruptCount 给出）
        if data.autoReplaced and data.cleansed then
            local remaining = data.corruptCount or 0
            if state.selectedEquip then
                state.selectedEquip.affixes = data.refinePreview
                state.selectedEquip.corruptCount = remaining > 0 and remaining or nil
                state.selectedEquip.corruptBaseMult = data.corruptBaseMult
                state.selectedEquip.corruptRevert = data.corruptRevert
                state.selectedEquip.corruptOriginalAffixes = nil
                state.selectedEquip.corruptOriginalBaseMult = nil
                if data.newQuality then
                    state.selectedEquip.quality = data.newQuality
                end
                state.selectedEquip.baseStats = nil
                EquipmentSystem.hydrate(state.selectedEquip)
            end

            local before = {}
            for _, affix in ipairs(data.refinePreview or {}) do
                if state.selectedEquip then
                    EquipmentSystem.ensureAffixValue(affix, state.selectedEquip)
                end
                local qDef2 = AffixConfig.QUALITY[affix.quality]
                local gradeName = qDef2 and qDef2.name or "D"
                local effVal = state.selectedEquip
                    and EquipmentSystem.effectiveAffixValue(state.selectedEquip, affix) or affix.value
                before[#before + 1] = {
                    name = affix.name or affix.key or "?",
                    value = formatAffixValue(affix.key, effVal, affix.affixId),
                    grade = gradeName,
                }
            end
            refineData.before = before
            refineData.after = {}
            refineData.hasPreview = false

            state.pendingRefineAffixes = nil
            state.pendingRefineSeq = nil
            qualityUpgradeInfo = nil
            corruptResultInfo = {
                title = "洗除诅咒",
                effectName = remaining > 0
                    and ("已洗除 1 层诅咒，剩余 " .. remaining .. " 层")
                    or "腐化诅咒已全部洗除",
                hint = remaining > 0
                    and "魔化词条保留，可继续洗除剩余层数"
                    or "魔化词条保留，装备已无诅咒减益",
                startTime = time.elapsedTime,
            }

            if cancelCurrencyWatch_ then cancelCurrencyWatch_() end
            cancelCurrencyWatch_ = PlayerStore.WaitForChange("currency", {
                timeout = 2.0,
                onChange = function()
                    cancelCurrencyWatch_ = nil
                    refineData.ownedEssence = GameState.getEssence()
                end,
            })

            recalcRefineEssenceCost()
            print("[BlacksmithRefine] 神圣石净化完成")
            return true
        end

        -- 腐化石路径：服务端已直接应用魔化结果，不进入待替换流程
        if data.autoReplaced and data.corrupted then
            if state.selectedEquip then
                state.selectedEquip.affixes = data.refinePreview
                state.selectedEquip.corruptCount = data.corruptCount or state.selectedEquip.corruptCount
                state.selectedEquip.corruptBaseMult = data.corruptBaseMult or state.selectedEquip.corruptBaseMult
                if data.corruptRevert then
                    state.selectedEquip.corruptRevert = data.corruptRevert
                end
                if data.newQuality then
                    state.selectedEquip.quality = data.newQuality
                end
                if data.corruptBaseMult then
                    state.selectedEquip.baseStats = nil
                    EquipmentSystem.hydrate(state.selectedEquip)
                end
            end

            local detail = data.corruptEffectDetail
            local beforeAffixes = data.corruptBeforeAffixes or data.refinePreview or {}
            local afterAffixes = data.refinePreview or {}

            refineData.before = buildAffixDisplayRows(beforeAffixes, state.selectedEquip, nil)
            refineData.after = buildCorruptAfterRows(detail, beforeAffixes, afterAffixes, state.selectedEquip)
            refineData.hasPreview = false

            state.pendingRefineAffixes = nil
            state.pendingRefineSeq = nil
            qualityUpgradeInfo = nil

            corruptResultInfo = {
                title = "腐化结果",
                effectName = "魔化转换",
                afterRows = refineData.after,
                startTime = time.elapsedTime,
            }

            if cancelCurrencyWatch_ then cancelCurrencyWatch_() end
            cancelCurrencyWatch_ = PlayerStore.WaitForChange("currency", {
                timeout = 2.0,
                onChange = function()
                    cancelCurrencyWatch_ = nil
                    refineData.ownedEssence = GameState.getEssence()
                end,
            })

            bumpRefineCountAndCost(state)

            print("[BlacksmithRefine] 腐化石魔化完成: " .. tostring(corruptResultInfo.effectName))
            return true
        end

        -- 普通洗练/洗练石路径：展示新词缀预览，等待替换确认
        state.pendingRefineAffixes = data.refinePreview
        state.pendingRefineSeq = data.refineSeq
        -- 快照旧的 after 数据（用于滑出动画）
        refineAnim.oldAfter = refineData.after
        -- 更新洗练面板的"洗练后"预览
        local after = {}
        for _, affix in ipairs(data.refinePreview) do
            EquipmentSystem.ensureAffixValue(affix, state.selectedEquip or {})
            local qDef = AffixConfig.QUALITY[affix.quality]
            local gradeName = qDef and qDef.name or "D"
            local effVal = state.selectedEquip
                and EquipmentSystem.effectiveAffixValue(state.selectedEquip, affix) or affix.value
            after[#after + 1] = {
                name = affix.name or affix.key or "?",
                value = formatAffixValue(affix.key, effVal, affix.affixId),
                grade = gradeName,
            }
        end
        refineData.after = after
        refineData.hasPreview = true
        -- 清除直接生效展示（如果有）
        qualityUpgradeInfo = nil
        corruptResultInfo = nil
        -- 洗练扣了精粹，等 REPLICATED 到达后再刷新拥有量
        if cancelCurrencyWatch_ then cancelCurrencyWatch_() end
        cancelCurrencyWatch_ = PlayerStore.WaitForChange("currency", {
            timeout = 2.0,
            onChange = function()
                cancelCurrencyWatch_ = nil
                refineData.ownedEssence = GameState.getEssence()
            end,
        })
        -- 累计洗练次数+1 并重算下次消耗（与服务端 REFINE_EQUIP 同步）
        bumpRefineCountAndCost(state)
        -- 启动洗练刷新动画
        refineAnim.type = "refine"
        refineAnim.startTime = time.elapsedTime
        refineAnim.duration = REFINE_ANIM_DURATION

        print("[BlacksmithRefine] 洗练预览已更新，等待替换确认")
        return true
    end

    -- 替换成功后清除缓存，启动替换动画，更新洗练次数
    if data.refineReplaced then
        -- 快照当前洗练后数据用于上移动画
        refineAnim.replaceSnapshot = refineData.after
        refineAnim.type = "replace"
        refineAnim.startTime = time.elapsedTime
        refineAnim.duration = REPLACE_ANIM_DURATION

        local previewAffixes = state.pendingRefineAffixes
        state.pendingRefineAffixes = nil
        state.pendingRefineSeq = nil

        if previewAffixes and state.selectedEquip then
            state.selectedEquip.affixes = previewAffixes
        end
        if state.selectedEquip then
            applyRefineDisplayFromEquip(state.selectedEquip)
        end

        -- 洗练次数已在 refinePreview 回调中递增，替换时无需再改
        print("[BlacksmithRefine] 词缀替换成功，累计洗练" .. tostring(refineData.refineCount) .. "次")
        return true
    end

    return false
end

return M
