-- ============================================================================
-- RelicReforgePanel - 遗物洗练面板
-- 通过遗物详情界面点击"洗练"后打开
-- 坐标系: 设计分辨率 1080x2400
-- ============================================================================

local DrawUtil          = require("core.DrawUtil")
local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest
local BF                = require("systems.ButtonFeedback")
local RelicSystem       = require("systems.RelicSystem")
local RelicAffix        = require("systems.RelicAffix")
local RelicDefs         = require("data.RelicDefs")
local ImageCache        = require("ui.ImageCache")
local PlayerStore       = require("client.data.PlayerStore")

local RelicReforgePanel = {}

-- ======================== 动画常量 ========================

local ANIM_OPEN_DUR  = 0.25
local ANIM_CLOSE_DUR = 0.18

local function easeOutCubic(t)
    local u = 1 - t; return 1 - u * u * u
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 布局常量 ========================

-- 背景框 UI_MXZGH_YW_0 X540 Y1043 1080*872
local BG = {
    CX = 540, CY = 1043,
    W  = 1080, H = 872,
}

-- 遗物图标（与背包样式相同）X540 Y564 160*160
local ICON = {
    CX = 540, CY = 564,
    SIZE = 160,
}

-- 标题"遗物洗练" X540 Y694 字号60 颜色纯白 描边颜色593219大小6
local TITLE = {
    CX = 540, CY = 694,
    FONT = 60,
    STROKE = 6,
    STROKE_R = 0x59, STROKE_G = 0x32, STROKE_B = 0x19,
}

-- 洗练前背景框 UI_TJP_XL_2 X540 Y928 970*260
local BEFORE_BG = {
    CX = 540, CY = 928,
    W  = 970, H = 260,
}

-- 文本"洗练前" X540 Y835 字号40 颜色454545
local BEFORE_LABEL = {
    CX = 540, CY = 835,
    FONT = 40,
    R = 0x45, G = 0x45, B = 0x45,
}

-- 洗练前词缀位置 X540 Y950 水平与垂直居中 字号40 颜色725850
local BEFORE_AFFIX = {
    CX = 540, CY = 950,
    FONT = 40,
    R = 0x72, G = 0x58, B = 0x50,
}

-- 箭头图标 UI_TJP_JIANTOU X540 Y1101 旋转向下 48*48
local ARROW = {
    CX = 540, CY = 1101,
    W = 48, H = 48,
}

-- 洗练后背景框 UI_TJP_XL_1 X540 Y1275 970*260
local AFTER_BG = {
    CX = 540, CY = 1275,
    W  = 970, H = 260,
}

-- 文本"洗练后" X540 Y1182 字号40 颜色454545
local AFTER_LABEL = {
    CX = 540, CY = 1182,
    FONT = 40,
    R = 0x45, G = 0x45, B = 0x45,
}

-- 洗练后词缀位置 X540 Y1291 水平与垂直居中 字号40 颜色725850
local AFTER_AFFIX = {
    CX = 540, CY = 1291,
    FONT = 40,
    R = 0x72, G = 0x58, B = 0x50,
}

-- "替换"按钮 UI_AN_HUANG X300 Y1543 410*100
local BTN_REPLACE = {
    CX = 300, CY = 1543,
    W = 410, H = 100,
    NP_T = 15, NP_R = 60, NP_B = 15, NP_L = 60,
    FONT = 38,
    TEXT_CX = 298, TEXT_CY = 1542,
    TEXT_R = 0, TEXT_G = 0, TEXT_B = 0, TEXT_A = 191,
}

-- "洗练"按钮 UI_AN_LV X780 Y1543 410*100
local BTN_REFORGE = {
    CX = 780, CY = 1543,
    W = 410, H = 100,
    NP_T = 15, NP_R = 60, NP_B = 15, NP_L = 60,
    FONT = 38,
    TEXT_CX = 778, TEXT_CY = 1542,
    TEXT_R = 0, TEXT_G = 0, TEXT_B = 0, TEXT_A = 191,
}

-- 可洗练词缀说明（感叹号，标题行右侧）
local INFO_BTN = {
    CX = 880, CY = 694,
    W = 64, H = 64,
    ICON_W = 48, ICON_H = 48,
}

-- 可洗练词缀弹窗
local POOL_POPUP = {
    bgCX = 540, bgCY = 1100, bgW = 880, bgH = 1100,
    bgNsT = 120, bgNsR = 40, bgNsB = 40, bgNsL = 40,
    titleCY = 630, titleFont = 44, titleStroke = 5,
    listTop = 690, listH = 920, listPadX = 60, listW = 760,
    lineH = 44, lineGap = 8, textFont = 32,
    textR = 0x72, textG = 0x58, textB = 0x50,
    POPUP_DUR = 0.22, POPUP_SCALE_FROM = 0.85,
}

-- 奥术粉尘图标+文本（动态居中于洗练按钮）
local COST_AREA = {
    CY = 1626,          -- 垂直中心（按钮下方）
    ICON_W = 70,        -- 图标宽高
    ICON_H = 70,
    GAP = 30,           -- 图标与文本间距
    FONT = 40,
    -- 颜色: 足够=绿色, 不足=红色, 斜杠后=白色
    ENOUGH_R = 0x45, ENOUGH_G = 0xff, ENOUGH_B = 0x7e,
    SHORT_R = 0xff, SHORT_G = 0x45, SHORT_B = 0x45,
    SLASH_R = 0xff, SLASH_G = 0xff, SLASH_B = 0xff,
}

-- ======================== 图片资源 ========================

local imgBg         = -1  -- UI_MXZGH_YW_0.png
local imgBeforeBg   = -1  -- UI_TJP_XL_2.png
local imgAfterBg    = -1  -- UI_TJP_XL_1.png
local imgArrow      = -1  -- UI_TJP_JIANTOU.png
local imgBtnHuang   = -1  -- UI_AN_HUANG.png
local imgBtnLv      = -1  -- UI_AN_LV.png
local imgDustIcon   = -1  -- UI_icon_ASFC_X.png
local imgInfoIcon   = -1  -- UI_icon_TS.png
local imgPoolBg     = -1  -- UI_TY_EJQRK.png
local imgRelicIcon  = {}  -- [1..5] 遗物图标 (ICON_YWX_*)

-- ======================== 状态 ========================

local state = {
    visible    = false,
    opening    = false,
    closing    = false,
    openTime   = 0,
    closeTime  = 0,
    relic      = nil,      -- 当前洗练的遗物
    relicId    = nil,      -- 遗物 ID（PlayerStore 更新后按 ID 刷新引用）
    newAffixId = nil,      -- 洗练后的新词缀ID（未确认替换前暂存）
    newAffixText = nil,    -- 洗练后的新词缀文本
    reforging  = false,    -- 是否正在等待洗练结果
    confirming = false,    -- 是否正在确认替换
    poolOpen      = false,
    poolClosing   = false,
    poolAnimT     = 0,
    poolScrollY   = 0,
    poolDragging  = false,
    poolLastDragY = 0,
    poolLines     = nil,   -- string[]
}

local storeSubscribed_ = false

local function rebuildPoolLines()
    local relic = state.relic
    if not relic then
        state.poolLines = {}
        return
    end
    state.poolLines = RelicAffix.getReforgeAffixTexts(
        relic.type, relic.quality, relic.level or 1, relic.affixId)
end

local function getPoolContentHeight()
    local count = state.poolLines and #state.poolLines or 0
    if count == 0 then
        return POOL_POPUP.lineH + POOL_POPUP.lineGap
    end
    return count * (POOL_POPUP.lineH + POOL_POPUP.lineGap) - POOL_POPUP.lineGap
end

local function clampPoolScroll()
    local maxScroll = math.max(0, getPoolContentHeight() - POOL_POPUP.listH)
    state.poolScrollY = math.max(0, math.min(state.poolScrollY, maxScroll))
end

local function openPoolPopup()
    rebuildPoolLines()
    state.poolOpen = true
    state.poolClosing = false
    state.poolAnimT = time.elapsedTime
    state.poolScrollY = 0
    state.poolDragging = false
end

local function closePoolPopup()
    if not state.poolOpen then return end
    if state.poolClosing then return end
    state.poolClosing = true
    state.poolAnimT = time.elapsedTime
end

local function drawPoolPopup(vg)
    if not state.poolOpen then return end

    local elapsed = time.elapsedTime - state.poolAnimT
    local rawT = math.min(1.0, elapsed / POOL_POPUP.POPUP_DUR)
    local progress
    if state.poolClosing then
        progress = 1.0 - easeInCubic(rawT)
        if rawT >= 1.0 then
            state.poolOpen = false
            state.poolClosing = false
            state.poolLines = nil
            return
        end
    else
        progress = easeOutCubic(rawT)
    end

    local alpha = math.floor(progress * 255 + 0.5)
    local scale = POOL_POPUP.POPUP_SCALE_FROM + (1.0 - POOL_POPUP.POPUP_SCALE_FROM) * progress

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * progress + 0.5)))
    nvgFill(vg)

    nvgSave(vg)
    nvgTranslate(vg, POOL_POPUP.bgCX, POOL_POPUP.bgCY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -POOL_POPUP.bgCX, -POOL_POPUP.bgCY)
    nvgGlobalAlpha(vg, alpha / 255)

    if imgPoolBg >= 0 then
        drawNineSlice(vg, imgPoolBg,
            POOL_POPUP.bgCX - POOL_POPUP.bgW * 0.5, POOL_POPUP.bgCY - POOL_POPUP.bgH * 0.5,
            POOL_POPUP.bgW, POOL_POPUP.bgH,
            POOL_POPUP.bgNsT, POOL_POPUP.bgNsR, POOL_POPUP.bgNsB, POOL_POPUP.bgNsL)
    end

    drawTextStroke(vg, POOL_POPUP.bgCX, POOL_POPUP.titleCY, "可洗练词缀",
        POOL_POPUP.titleFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, POOL_POPUP.titleStroke,
        { strokeColor = { 0x59, 0x32, 0x19 } })

    clampPoolScroll()

    local listLeft = POOL_POPUP.bgCX - POOL_POPUP.listW * 0.5
    local listTop = POOL_POPUP.listTop
    local contentW = POOL_POPUP.listW - POOL_POPUP.listPadX * 2
    local contentLeft = listLeft + POOL_POPUP.listPadX
    nvgSave(vg)
    nvgIntersectScissor(vg, listLeft, listTop, POOL_POPUP.listW, POOL_POPUP.listH)
    nvgTranslate(vg, 0, -state.poolScrollY)

    local y = listTop
    local lines = state.poolLines or {}
    if #lines == 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, POOL_POPUP.textFont)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(POOL_POPUP.textR, POOL_POPUP.textG, POOL_POPUP.textB, 160))
        nvgText(vg, POOL_POPUP.bgCX, y + POOL_POPUP.lineH * 0.5, "暂无可洗练词缀", nil)
    else
        for _, text in ipairs(lines) do
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, POOL_POPUP.textFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(POOL_POPUP.textR, POOL_POPUP.textG, POOL_POPUP.textB, 255))
            nvgText(vg, contentLeft, y + POOL_POPUP.lineH * 0.5, text, nil)
            y = y + POOL_POPUP.lineH + POOL_POPUP.lineGap
        end
    end

    nvgRestore(vg)
    nvgRestore(vg)
end

local function refreshRelicReference()
    if not state.visible or not state.relicId then return end
    local fresh = RelicSystem.findById(state.relicId)
    if fresh then
        state.relic = fresh
    end
end

-- ======================== 初始化 ========================

function RelicReforgePanel.init(vg)
    imgBg       = nvgCreateImage(vg, "image/UI_MXZGH_YW_0.png", 0)
    imgBeforeBg = nvgCreateImage(vg, "image/UI_TJP_XL_2.png", 0)
    imgAfterBg  = nvgCreateImage(vg, "image/UI_TJP_XL_1.png", 0)
    imgArrow    = nvgCreateImage(vg, "image/UI_TJP_JIANTOU.png", 0)
    imgBtnHuang = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    imgBtnLv    = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    imgDustIcon = nvgCreateImage(vg, "image/UI_icon_ASFC_X.png", 0)
    imgInfoIcon = nvgCreateImage(vg, "image/UI_icon_TS.png", 0)
    imgPoolBg   = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)

    -- 遗物图标 (ICON_YWX_*)
    local iconKeys = { "GUI", "SHE", "LU", "LANG", "YING" }
    for i, key in ipairs(iconKeys) do
        imgRelicIcon[i] = nvgCreateImage(vg, "image/ICON_YWX_" .. key .. ".png", 0)
    end

    if not storeSubscribed_ then
        storeSubscribed_ = true
        PlayerStore.Subscribe("mod_relics", function()
            refreshRelicReference()
        end)
    end

    print("[RelicReforgePanel] init OK")
end

-- ======================== 显示/隐藏 ========================

--- 打开洗练面板
---@param relic table 遗物数据
function RelicReforgePanel.show(relic)
    if not relic then return end
    state.relicId     = tostring(relic.id)
    state.relic       = relic
    refreshRelicReference()
    state.newAffixId  = nil
    state.newAffixText = nil
    state.reforging   = false
    state.confirming  = false
    state.poolOpen    = false
    state.poolClosing = false
    state.poolScrollY = 0
    state.poolDragging = false
    state.poolLines   = nil
    state.visible     = true
    state.opening     = true
    state.closing     = false
    state.openTime    = time.elapsedTime
end

--- 关闭洗练面板
function RelicReforgePanel.hide()
    if not state.visible then return end
    state.poolOpen = false
    state.poolClosing = false
    state.poolLines = nil
    state.closing   = true
    state.opening   = false
    state.closeTime = time.elapsedTime
end

--- 是否可见
function RelicReforgePanel.isVisible()
    return state.visible
end

function RelicReforgePanel.isPoolOpen()
    return state.poolOpen
end

--- 设置洗练结果（由外部在收到服务端响应后调用）
---@param newAffixId number|nil 新词缀ID
function RelicReforgePanel.setReforgeResult(newAffixId)
    state.reforging = false
    if newAffixId then
        state.newAffixId = newAffixId
        -- 获取新词缀文本
        local RelicAffix = require("systems.RelicAffix")
        state.newAffixText = RelicAffix.getAffixText(newAffixId, state.relic and state.relic.quality or 3)
    end
end

--- 确认替换完成（由外部在收到服务端响应后调用）
---@param success boolean
---@param reason string|nil
function RelicReforgePanel.setConfirmResult(success, reason)
    state.confirming = false
    if success then
        state.newAffixId = nil
        state.newAffixText = nil
        RelicReforgePanel.hide()
    else
        print("[RelicReforgePanel] 替换失败: " .. tostring(reason))
    end
end

-- ======================== 内部动画 ========================

local function internalUpdate()
    if not state.visible then return end
    local now = time.elapsedTime

    if state.opening then
        if (now - state.openTime) >= ANIM_OPEN_DUR then
            state.opening = false
        end
    elseif state.closing then
        if (now - state.closeTime) >= ANIM_CLOSE_DUR then
            state.closing = false
            state.visible = false
            state.relic   = nil
            state.relicId = nil
            state.newAffixId = nil
            state.newAffixText = nil
            state.reforging = false
            state.confirming = false
        end
    end
end

-- ======================== 绘制 ========================

function RelicReforgePanel.draw(vg)
    if not state.visible then return end
    if not state.relic then return end

    internalUpdate()
    if not state.visible then return end

    local relic = state.relic

    -- 动画进度
    local now = time.elapsedTime
    local progress = 1.0
    if state.opening then
        local t = math.min((now - state.openTime) / ANIM_OPEN_DUR, 1.0)
        progress = easeOutCubic(t)
    elseif state.closing then
        local t = math.min((now - state.closeTime) / ANIM_CLOSE_DUR, 1.0)
        progress = 1.0 - easeInCubic(t)
    end

    -- 全屏遮罩（纯黑 60%）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(153 * progress)))
    nvgFill(vg)

    -- 缩放动画
    local scale = 0.8 + 0.2 * progress
    nvgSave(vg)
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -BG.CX, -BG.CY)
    nvgGlobalAlpha(vg, progress)

    -- 1) 背景框 UI_MXZGH_YW_0
    if imgBg >= 0 then
        drawImageCentered(vg, imgBg, BG.CX, BG.CY, BG.W, BG.H, 1.0)
    end

    -- 2) 遗物图标 X540 Y564 160*160（品质背景 + 图标，与背包相同）
    local qualBg = ImageCache.getQualityBg(relic.quality)
    if qualBg and qualBg >= 0 then
        drawImageCentered(vg, qualBg, ICON.CX, ICON.CY, ICON.SIZE, ICON.SIZE, 1.0)
    end
    local relicImg = imgRelicIcon[relic.type] or imgRelicIcon[1]
    if relicImg and relicImg >= 0 then
        drawImageCentered(vg, relicImg, ICON.CX, ICON.CY, ICON.SIZE - 20, ICON.SIZE - 20, 1.0)
    end

    -- 3) 标题"遗物洗练" X540 Y694 字号60 纯白 描边593219大小6
    drawTextStroke(vg, TITLE.CX, TITLE.CY, "遗物洗练",
        TITLE.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TITLE.STROKE,
        { strokeColor = { TITLE.STROKE_R, TITLE.STROKE_G, TITLE.STROKE_B } })

    -- 3.5) 可洗练词缀说明（感叹号）
    local _bfInfo = BF.begin(vg, "relic_reforge_pool_info", INFO_BTN.CX, INFO_BTN.CY, INFO_BTN.W, INFO_BTN.H)
    if imgInfoIcon >= 0 then
        drawImageCentered(vg, imgInfoIcon, INFO_BTN.CX, INFO_BTN.CY, INFO_BTN.ICON_W, INFO_BTN.ICON_H, 1.0)
    else
        drawTextStroke(vg, INFO_BTN.CX, INFO_BTN.CY, "!",
            40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4, { strokeColor = { 0, 0, 0 } })
    end
    BF.finish(vg, _bfInfo)

    -- 4) 洗练前背景框 UI_TJP_XL_2 X540 Y928 970*260
    if imgBeforeBg >= 0 then
        drawImageCentered(vg, imgBeforeBg, BEFORE_BG.CX, BEFORE_BG.CY, BEFORE_BG.W, BEFORE_BG.H, 1.0)
    end

    -- 5) 文本"洗练前" X540 Y835 字号40 颜色454545
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BEFORE_LABEL.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(BEFORE_LABEL.R, BEFORE_LABEL.G, BEFORE_LABEL.B, 255))
    nvgText(vg, BEFORE_LABEL.CX, BEFORE_LABEL.CY, "洗练前", nil)

    -- 6) 洗练前词缀 X540 Y950 居中 字号40 颜色725850
    local beforeText = RelicSystem.getRelicAffixText(relic)
    if beforeText and beforeText ~= "" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BEFORE_AFFIX.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BEFORE_AFFIX.R, BEFORE_AFFIX.G, BEFORE_AFFIX.B, 255))
        nvgText(vg, BEFORE_AFFIX.CX, BEFORE_AFFIX.CY, beforeText, nil)
    end

    -- 7) 箭头图标 UI_TJP_JIANTOU X540 Y1101 旋转90°向下 48*48
    if imgArrow >= 0 then
        nvgSave(vg)
        nvgTranslate(vg, ARROW.CX, ARROW.CY)
        nvgRotate(vg, math.rad(90))  -- 向右旋转90°变为向下
        nvgTranslate(vg, -ARROW.CX, -ARROW.CY)
        drawImageCentered(vg, imgArrow, ARROW.CX, ARROW.CY, ARROW.W, ARROW.H, 1.0)
        nvgRestore(vg)
    end

    -- 8) 洗练后背景框 UI_TJP_XL_1 X540 Y1275 970*260
    if imgAfterBg >= 0 then
        drawImageCentered(vg, imgAfterBg, AFTER_BG.CX, AFTER_BG.CY, AFTER_BG.W, AFTER_BG.H, 1.0)
    end

    -- 9) 文本"洗练后" X540 Y1182 字号40 颜色454545
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, AFTER_LABEL.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(AFTER_LABEL.R, AFTER_LABEL.G, AFTER_LABEL.B, 255))
    nvgText(vg, AFTER_LABEL.CX, AFTER_LABEL.CY, "洗练后", nil)

    -- 10) 洗练后词缀 X540 Y1291 居中 字号40 颜色725850
    local afterText = (state.newAffixText --[[@as string?]]) or "点击洗练获取新词缀"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, AFTER_AFFIX.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if state.newAffixText then
        nvgFillColor(vg, nvgRGBA(AFTER_AFFIX.R, AFTER_AFFIX.G, AFTER_AFFIX.B, 255))
    else
        nvgFillColor(vg, nvgRGBA(0x91, 0x8f, 0x88, 180))  -- 提示文字用浅色
    end
    nvgText(vg, AFTER_AFFIX.CX, AFTER_AFFIX.CY, afterText, nil)

    -- 11) "替换"按钮 UI_AN_HUANG X300 Y1543 410*100
    local _bfReplace = BF.begin(vg, "relic_reforge_replace", BTN_REPLACE.CX, BTN_REPLACE.CY, BTN_REPLACE.W, BTN_REPLACE.H)
    drawNineSlice(vg, imgBtnHuang,
        BTN_REPLACE.CX - BTN_REPLACE.W * 0.5,
        BTN_REPLACE.CY - BTN_REPLACE.H * 0.5,
        BTN_REPLACE.W, BTN_REPLACE.H,
        BTN_REPLACE.NP_T, BTN_REPLACE.NP_R, BTN_REPLACE.NP_B, BTN_REPLACE.NP_L)
    BF.finish(vg, _bfReplace)

    -- 12) 文本"替换" X298 Y1542 纯黑不透明度75%
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_REPLACE.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(BTN_REPLACE.TEXT_R, BTN_REPLACE.TEXT_G, BTN_REPLACE.TEXT_B, BTN_REPLACE.TEXT_A))
    nvgText(vg, BTN_REPLACE.TEXT_CX, BTN_REPLACE.TEXT_CY, "替换", nil)

    -- 13) "洗练"按钮 UI_AN_LV X780 Y1543 410*100
    local _bfReforge = BF.begin(vg, "relic_reforge_do", BTN_REFORGE.CX, BTN_REFORGE.CY, BTN_REFORGE.W, BTN_REFORGE.H)
    drawNineSlice(vg, imgBtnLv,
        BTN_REFORGE.CX - BTN_REFORGE.W * 0.5,
        BTN_REFORGE.CY - BTN_REFORGE.H * 0.5,
        BTN_REFORGE.W, BTN_REFORGE.H,
        BTN_REFORGE.NP_T, BTN_REFORGE.NP_R, BTN_REFORGE.NP_B, BTN_REFORGE.NP_L)
    BF.finish(vg, _bfReforge)

    -- 14) 文本"洗练"/"继续洗练" X778 Y1542 纯黑不透明度75%
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_REFORGE.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(BTN_REFORGE.TEXT_R, BTN_REFORGE.TEXT_G, BTN_REFORGE.TEXT_B, BTN_REFORGE.TEXT_A))
    nvgText(vg, BTN_REFORGE.TEXT_CX, BTN_REFORGE.TEXT_CY, state.newAffixId and "继续洗练" or "洗练", nil)

    -- 15) 奥术粉尘图标 + 消耗文本（动态居中于洗练按钮）
    local qualityDef = RelicDefs.QUALITIES[relic.quality]
    local cost = qualityDef and qualityDef.reforgeCost or 0
    local owned = PlayerStore.GetField("currency", "arcaneDust") or 0
    local enough = owned >= cost

    local ownedStr = tostring(owned)
    local costStr  = tostring(cost)
    local fullText = ownedStr .. "/" .. costStr

    -- 先测量文本总宽度
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, COST_AREA.FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local textW = nvgTextBounds(vg, 0, 0, fullText, nil, nil)

    -- 计算整组宽度：图标 + 间距 + 文本
    local groupW = COST_AREA.ICON_W + COST_AREA.GAP + textW
    local groupStartX = BTN_REFORGE.CX - groupW * 0.5

    -- 图标居中于 groupStartX + iconW/2
    local iconCX = groupStartX + COST_AREA.ICON_W * 0.5
    if imgDustIcon >= 0 then
        drawImageCentered(vg, imgDustIcon, iconCX, COST_AREA.CY, COST_AREA.ICON_W, COST_AREA.ICON_H, 1.0)
    end

    -- 文本起始X = 图标右边缘 + 间距
    local textX = groupStartX + COST_AREA.ICON_W + COST_AREA.GAP

    -- 斜杠前面的数量（足够=绿色, 不足=红色）
    if enough then
        nvgFillColor(vg, nvgRGBA(COST_AREA.ENOUGH_R, COST_AREA.ENOUGH_G, COST_AREA.ENOUGH_B, 255))
    else
        nvgFillColor(vg, nvgRGBA(COST_AREA.SHORT_R, COST_AREA.SHORT_G, COST_AREA.SHORT_B, 255))
    end
    nvgText(vg, textX, COST_AREA.CY, ownedStr, nil)

    -- 测量拥有数量文本宽度
    local ownedW = nvgTextBounds(vg, 0, 0, ownedStr, nil, nil)

    -- 斜杠 + 消耗量（白色）
    nvgFillColor(vg, nvgRGBA(COST_AREA.SLASH_R, COST_AREA.SLASH_G, COST_AREA.SLASH_B, 255))
    nvgText(vg, textX + ownedW, COST_AREA.CY, "/" .. costStr, nil)

    nvgRestore(vg)

    drawPoolPopup(vg)
end

-- ======================== 可洗练词缀弹窗输入 ========================

function RelicReforgePanel.handlePoolTap(tx, ty)
    if not state.poolOpen then return false end
    if state.poolClosing then return true end
    if time.elapsedTime - state.poolAnimT < 0.05 then return true end
    if not hitTest(tx, ty, POOL_POPUP.bgCX, POOL_POPUP.bgCY, POOL_POPUP.bgW, POOL_POPUP.bgH) then
        closePoolPopup()
    end
    return true
end

function RelicReforgePanel.handlePoolDragBegin(dx, dy)
    if not state.poolOpen or state.poolClosing then return false end
    if hitTest(dx, dy, POOL_POPUP.bgCX, POOL_POPUP.bgCY, POOL_POPUP.bgW, POOL_POPUP.bgH) then
        state.poolDragging = true
        state.poolLastDragY = dy
        return true
    end
    return true
end

function RelicReforgePanel.handlePoolDragMove(dx, dy)
    if not state.poolDragging then return false end
    state.poolScrollY = state.poolScrollY - (dy - state.poolLastDragY)
    state.poolLastDragY = dy
    clampPoolScroll()
    return true
end

function RelicReforgePanel.handlePoolDragEnd(dx, dy)
    if state.poolDragging then
        state.poolDragging = false
        return true
    end
    return false
end

function RelicReforgePanel.handlePoolScroll(wheel)
    if not state.poolOpen or state.poolClosing then return false end
    state.poolScrollY = state.poolScrollY - wheel * 80
    clampPoolScroll()
    return true
end

-- ======================== 点击处理 ========================

function RelicReforgePanel.handleTap(tx, ty)
    if not state.visible then return false end
    if state.opening or state.closing then return true end

    if state.poolOpen then
        return RelicReforgePanel.handlePoolTap(tx, ty)
    end

    local relic = state.relic
    if not relic then return true end
    local relicId = state.relicId or tostring(relic.id)

    if hitTest(tx, ty, INFO_BTN.CX, INFO_BTN.CY, INFO_BTN.W, INFO_BTN.H) then
        BF.trigger("relic_reforge_pool_info")
        openPoolPopup()
        return true
    end

    -- "洗练"按钮
    if hitTest(tx, ty, BTN_REFORGE.CX, BTN_REFORGE.CY, BTN_REFORGE.W, BTN_REFORGE.H) then
        BF.trigger("relic_reforge_do")
        if not state.reforging then
            -- 检查资源是否足够
            local qualityDef = RelicDefs.QUALITIES[relic.quality]
            local cost = qualityDef and qualityDef.reforgeCost or 0
            local owned = PlayerStore.GetField("currency", "arcaneDust") or 0
            if owned < cost then
                print("[RelicReforgePanel] 奥术粉尘不足: 拥有" .. owned .. " 需要" .. cost)
                return true
            end
            state.reforging = true
            RelicSystem.requestReforge(relicId)
            print("[RelicReforgePanel] 发起洗练请求: " .. tostring(relicId))
        end
        return true
    end

    -- "替换"按钮
    if hitTest(tx, ty, BTN_REPLACE.CX, BTN_REPLACE.CY, BTN_REPLACE.W, BTN_REPLACE.H) then
        BF.trigger("relic_reforge_replace")
        if state.newAffixId and not state.confirming then
            state.confirming = true
            print("[RelicReforgePanel] 确认替换词缀: " .. tostring(state.newAffixId))
            RelicSystem.requestReforgeConfirm(relicId, state.newAffixId, function(success, reason)
                if not success then
                    state.confirming = false
                    print("[RelicReforgePanel] 确认替换失败: " .. tostring(reason))
                end
            end)
        end
        return true
    end

    -- 点击面板外部关闭
    -- 面板整体区域包含图标到按钮(Y564~Y1650)
    local panelTop = ICON.CY - ICON.SIZE * 0.5 - 20
    local panelBottom = COST_AREA.CY + COST_AREA.ICON_H * 0.5 + 30
    local panelLeft = BG.CX - BG.W * 0.5
    local panelRight = BG.CX + BG.W * 0.5
    if tx < panelLeft or tx > panelRight or ty < panelTop or ty > panelBottom then
        RelicReforgePanel.hide()
        return true
    end

    -- 点击面板内部（消费事件）
    return true
end

return RelicReforgePanel
