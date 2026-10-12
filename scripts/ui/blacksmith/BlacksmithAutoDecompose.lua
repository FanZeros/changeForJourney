-- ============================================================================
-- BlacksmithAutoDecompose.lua
-- 自动分解设置弹窗：品质阈值（1-6 单选，可取消）+ 等级阈值滑条 + 保存回执。
-- 从 BlacksmithDecompose.lua 拆分而来；保持原公开接口与 1080×2400 坐标空间，
-- 由宿主 BlacksmithDecompose 在 setContext 时注入资源与动作出口。
--
-- 保存语义（PR #147）：
--   弹窗打开读取正式设置到独立草稿；点「设置完成」发送 SET_AUTO_DECOMPOSE，
--   服务端回执经 onActionResult 钳制回显，仅成功且存档 Flush 成功才关闭弹窗。
--   失败保留弹窗与草稿，玩家可重试。
-- ============================================================================

---@diagnostic disable: undefined-global

local GameConfig = require("config.GameConfig")
local DrawUtil   = require("core.DrawUtil")
local QualityMark = require("ui.widget.QualityMark")
local I18n       = require("core.I18n")
local BF         = require("systems.ButtonFeedback")
local EquipmentDetail = require("ui.character.equip.EquipmentDetail")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local hitTest           = DrawUtil.hitTest

local DESIGN_W = GameConfig.Design.WIDTH    -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT   -- 2400

local M = {}

-- 品质名称和颜色映射（与宿主分解面板同一份口径）
local QUALITY_CONFIG = {
    { name = "普通", r = 0x99, g = 0x99, b = 0x99 },
    { name = "优质", r = 0xa2, g = 0xff, b = 0x94 },
    { name = "稀有", r = 0x72, g = 0xf2, b = 0xf5 },
    { name = "史诗", r = 0xef, g = 0x79, b = 0xff },
    { name = "传说", r = 0xff, g = 0xed, b = 0x00 },
    { name = "至臻", r = 0xff, g = 0x00, b = 0x00 },
}

-- ======================== 布局常量（原弹窗坐标） ========================
local POP_MASK_ALPHA = 128
local POP_BG_CX, POP_BG_CY, POP_BG_W, POP_BG_H = 540, 1111, 950, 720
local POP_TITLE_CX, POP_TITLE_CY = 540, 830
local POP_TITLE_FONT, POP_TITLE_STROKE = 60, 4
local POP_DESC_CX, POP_DESC_CY, POP_DESC_FONT, POP_DESC_MAX_W = 540, 925, 38, 820
local POP_DESC_R, POP_DESC_G, POP_DESC_B = 0xb6, 0xb0, 0x9d

local POP_QBOX_COUNT = 6
local POP_QBOX_SIZE, POP_QBOX_GAP, POP_QBOX_CY, POP_QBOX_R = 100, 24, 1060, 16
local POP_QBOX_ICON_SIZE = 76
local POP_QBOX_TOTAL_W = POP_QBOX_COUNT * POP_QBOX_SIZE + (POP_QBOX_COUNT - 1) * POP_QBOX_GAP
local POP_QBOX_FIRST_CX = 540 - POP_QBOX_TOTAL_W * 0.5 + POP_QBOX_SIZE * 0.5
local POP_QBOX_SEL_STROKE = 5

local POP_LEVEL_CY = 1185
local POP_MINUS_CX, POP_MINUS_CY, POP_MINUS_W, POP_MINUS_H = 240, POP_LEVEL_CY, 84, 84
local POP_PLUS_CX, POP_PLUS_CY, POP_PLUS_W, POP_PLUS_H = 840, POP_LEVEL_CY, 84, 84
local POP_SLIDER_CX, POP_SLIDER_CY, POP_SLIDER_W, POP_SLIDER_H, POP_SLIDER_R = 540, POP_LEVEL_CY, 400, 24, 12
local POP_KNOB_SIZE = 36
local POP_KNOB_STROKE_R, POP_KNOB_STROKE_G, POP_KNOB_STROKE_B, POP_KNOB_STROKE_W = 0x44, 0x2d, 0x19, 6
local POP_LEVEL_STEP, POP_LEVEL_MAX = 1, 60

local POP_CONFIRM_CX, POP_CONFIRM_CY, POP_CONFIRM_W, POP_CONFIRM_H = 540, 1330, 410, 100
local POP_CONFIRM_TEXT_FONT = 40
local POP_CONFIRM_TEXT_R, POP_CONFIRM_TEXT_G, POP_CONFIRM_TEXT_B = 0x6d, 0x4c, 0x1d

-- ======================== 状态 ========================
local open_ = false
local draftQuality_ = 0   -- 草稿：品质阈值（0=不限制）
local draftLevel_ = 0     -- 草稿：等级阈值（0=不限制）
local sliderDragging_ = false
local pendingSave_ = false
local pendingQuality_ = 0
local pendingLevel_ = 0

-- 宿主注入
local getClient, getProtocol
local getSettings        -- fun(): autoQuality, autoLevel（正式设置读取）
local imgPopupBg, imgBtnMinus, imgBtnPlus, imgReplaceBtn = -1, -1, -1, -1
local popupInited_ = false

-- ======================== 内部工具 ========================
--- 第 i 个品质方框的中心 X
---@param i integer 1-6
---@return number
local function qboxCX(i)
    return POP_QBOX_FIRST_CX + (i - 1) * (POP_QBOX_SIZE + POP_QBOX_GAP)
end

--- 等级滑条比例（0=无，1=满级上限）
---@return number
local function levelSliderFrac()
    return math.max(0, math.min(1, draftLevel_ / POP_LEVEL_MAX))
end

--- 由滑条 X 坐标换算等级（吸附到 STEP 档位）
---@param dx number
---@return integer
local function levelFromSliderX(dx)
    local sliderL = POP_SLIDER_CX - POP_SLIDER_W * 0.5
    local frac = math.max(0, math.min(1, (dx - sliderL) / POP_SLIDER_W))
    local steps = POP_LEVEL_MAX / POP_LEVEL_STEP
    return math.floor(frac * steps + 0.5) * POP_LEVEL_STEP
end

--- 滑条命中区域高度（含滑块溢出）
---@return number
local function sliderHitH()
    return math.max(POP_SLIDER_H, POP_KNOB_SIZE) + 20
end

--- 读取正式设置到草稿；无法读取时保持上次草稿，不凭空归零。
local function syncDraftFromSettings()
    local q, level
    if getSettings then
        q, level = getSettings()
    end
    if q == nil then
        local equipData = require("core.PlayerStore").Get("equipment")
        local settings = equipData and equipData.settings
        q, level = settings and settings.autoQuality, settings and settings.autoLevel
    end
    draftQuality_ = math.max(0, math.min(6, math.floor(tonumber(q) or 0)))
    draftLevel_ = math.max(0, math.min(POP_LEVEL_MAX, math.floor(tonumber(level) or 0)))
end

--- 按当前草稿生成描述分段（品质名用品质色，其余灰白）
---@return {text:string, r:integer, g:integer, b:integer}[]
local function buildConditionSegments()
    local gr, gg, gb = POP_DESC_R, POP_DESC_G, POP_DESC_B
    local segs = {}
    local function addGray(text)
        segs[#segs + 1] = { text = text, r = gr, g = gg, b = gb }
    end
    if draftQuality_ > 0 then
        local qCfg = QUALITY_CONFIG[draftQuality_]
        if qCfg then
            segs[#segs + 1] = { text = qCfg.name, r = qCfg.r, g = qCfg.g, b = qCfg.b }
        end
        addGray("级及以下")
    end
    if draftQuality_ > 0 and draftLevel_ > 0 then addGray("且") end
    if draftLevel_ > 0 then addGray(I18n.format("%s级及以下", tostring(draftLevel_))) end
    if #segs == 0 then
        addGray("未设置条件，掉落装备不会自动分解")
        return segs
    end
    addGray("的装备会在掉落时自动分解")
    return segs
end

--- 仅成功回执才关弹窗并 Flush；失败保留草稿供重试。
---@param clampedQuality number|nil
---@param clampedLevel number|nil
local function finishSave(clampedQuality, clampedLevel)
    if not pendingSave_ then return false end
    pendingSave_ = false
    if clampedQuality then draftQuality_ = clampedQuality end
    if clampedLevel then draftLevel_ = clampedLevel end
    local ok, StandaloneSave = pcall(require, "boot.StandaloneSave")
    if ok and StandaloneSave and StandaloneSave.Flush then StandaloneSave.Flush() end
    open_ = false
    sliderDragging_ = false
    print("[BlacksmithAutoDecompose] 保存成功 品质=" .. tostring(draftQuality_)
        .. " 等级=" .. tostring(draftLevel_))
    return true
end

--- 发送设置；不立即关窗，等服务端回执（成功才关）。
local function requestSave()
    if pendingSave_ then return end
    if not (getClient and getProtocol) then
        print("[BlacksmithAutoDecompose] 缺少动作出口，无法保存")
        return
    end
    pendingSave_ = true
    pendingQuality_ = draftQuality_
    pendingLevel_ = draftLevel_
    getClient().sendAction(getProtocol().ACTION_TYPES.SET_AUTO_DECOMPOSE, {
        autoQuality = draftQuality_,
        autoLevel   = draftLevel_,
    })
    print("[BlacksmithAutoDecompose] 请求保存 品质=" .. tostring(draftQuality_)
        .. " 等级=" .. tostring(draftLevel_))
end

-- ======================== 公开接口 ========================
--- 绑定动作出口与正式设置读取（宿主 setContext 时调用）
---@param ctx table { getClient:function, getProtocol:function, getSettings?:function }
function M.bind(ctx)
    getClient = ctx.getClient
    getProtocol = ctx.getProtocol
    getSettings = ctx.getSettings
end

--- 注入弹窗资源句柄（由宿主转发 setContext 的资源）
---@param ctx table
function M.setContext(ctx)
    imgReplaceBtn = ctx.imgReplaceBtn or -1
end

--- 加载弹窗专属图片（宿主 init 时调用一次）
---@param vg any
function M.init(vg)
    if popupInited_ then return end
    popupInited_ = true
    imgPopupBg  = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TY_EJQRK_POP.png", 0)
    imgBtnMinus = nvgCreateImage(vg, "image/按钮/UI_AN_JIAN.png", 0)
    imgBtnPlus  = nvgCreateImage(vg, "image/按钮/UI_AN_JIA.png", 0)
end

--- 弹窗是否打开
---@return boolean
function M.isOpen()
    return open_
end

--- 打开弹窗（读取正式设置到独立草稿）
function M.open()
    syncDraftFromSettings()
    sliderDragging_ = false
    pendingSave_ = false
    open_ = true
    print("[BlacksmithAutoDecompose] open")
end

--- 关闭弹窗并放弃草稿
function M.reset()
    open_ = false
    sliderDragging_ = false
    pendingSave_ = false
end

--- 绘制自动分解设置按钮入口
---@param vg any
---@param cx number
---@param cy number
---@param w number
---@param h number
---@param font number
function M.drawEntry(vg, cx, cy, w, h, font)
    local didScale = BF.begin(vg, "bsd_auto", cx, cy, w, h)
    if imgReplaceBtn and imgReplaceBtn >= 0 then
        drawImageCentered(vg, imgReplaceBtn, cx, cy, w, h, 1.0)
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, font or 40)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xff, 0xd6, 0x66, 255))
    nvgText(vg, cx, cy, "自动分解", nil)
    BF.finish(vg, didScale)
end

--- 绘制自动分解弹窗
---@param vg any
function M.draw(vg)
    if not open_ then return end

    -- 1. 黑色半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, POP_MASK_ALPHA))
    nvgFill(vg)

    -- 2. 弹窗背景
    drawImageCentered(vg, imgPopupBg, POP_BG_CX, POP_BG_CY, POP_BG_W, POP_BG_H, 1.0)

    -- 3. 标题
    drawTextStroke(vg, POP_TITLE_CX, POP_TITLE_CY, "设置自动分解",
        POP_TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, POP_TITLE_STROKE)

    -- 4. 描述（分段绘制：品质名品质色，其余灰白；超宽自动缩字号）
    local segs = buildConditionSegments()
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, POP_DESC_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local function measureSegs()
        local total = 0
        for _, s in ipairs(segs) do
            s.w = nvgTextBounds(vg, 0, 0, s.text)
            total = total + s.w
        end
        return total
    end
    local totalW = measureSegs()
    if totalW > POP_DESC_MAX_W then
        nvgFontSize(vg, math.max(26, math.floor(POP_DESC_FONT * POP_DESC_MAX_W / totalW)))
        totalW = measureSegs()
    end
    local segX = POP_DESC_CX - totalW * 0.5
    for _, s in ipairs(segs) do
        nvgFillColor(vg, nvgRGBA(s.r, s.g, s.b, 255))
        nvgText(vg, segX, POP_DESC_CY, s.text, nil)
        segX = segX + s.w
    end

    -- 5. 品质方框选择（6 档，选中高亮描边）
    for i = 1, POP_QBOX_COUNT do
        local cx = qboxCX(i)
        local selected = (draftQuality_ == i)
        local didScaleQ = BF.begin(vg, "bsd_qbox_" .. i, cx, POP_QBOX_CY, POP_QBOX_SIZE, POP_QBOX_SIZE)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - POP_QBOX_SIZE * 0.5, POP_QBOX_CY - POP_QBOX_SIZE * 0.5,
            POP_QBOX_SIZE, POP_QBOX_SIZE, POP_QBOX_R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, selected and 60 or 25))
        nvgFill(vg)

        QualityMark.draw(vg, i, cx, POP_QBOX_CY - 8, POP_QBOX_ICON_SIZE, selected and 1.0 or 0.55)

        local qCfg = QUALITY_CONFIG[i]
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 24)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(qCfg.r, qCfg.g, qCfg.b, selected and 255 or 160))
        nvgText(vg, cx, POP_QBOX_CY + 34, qCfg.name, nil)

        if selected then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - POP_QBOX_SIZE * 0.5, POP_QBOX_CY - POP_QBOX_SIZE * 0.5,
                POP_QBOX_SIZE, POP_QBOX_SIZE, POP_QBOX_R)
            nvgStrokeColor(vg, nvgRGBA(qCfg.r, qCfg.g, qCfg.b, 255))
            nvgStrokeWidth(vg, POP_QBOX_SEL_STROKE)
            nvgStroke(vg)
        end
        BF.finish(vg, didScaleQ)
    end

    -- 6. 减按钮（0 档时半透明）
    local didScaleMinus = BF.begin(vg, "bsd_minus", POP_MINUS_CX, POP_MINUS_CY, POP_MINUS_W, POP_MINUS_H)
    drawImageCentered(vg, imgBtnMinus, POP_MINUS_CX, POP_MINUS_CY,
        POP_MINUS_W, POP_MINUS_H, draftLevel_ <= 0 and 0.4 or 1.0)
    BF.finish(vg, didScaleMinus)

    -- 7. 加按钮（满档时半透明）
    local didScalePlus = BF.begin(vg, "bsd_plus", POP_PLUS_CX, POP_PLUS_CY, POP_PLUS_W, POP_PLUS_H)
    drawImageCentered(vg, imgBtnPlus, POP_PLUS_CX, POP_PLUS_CY,
        POP_PLUS_W, POP_PLUS_H, draftLevel_ >= POP_LEVEL_MAX and 0.4 or 1.0)
    BF.finish(vg, didScalePlus)

    -- 8. 滑条背景 + 已填充部分
    local sliderL = POP_SLIDER_CX - POP_SLIDER_W * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderL, POP_SLIDER_CY - POP_SLIDER_H * 0.5,
        POP_SLIDER_W, POP_SLIDER_H, POP_SLIDER_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 51))
    nvgFill(vg)

    local frac = levelSliderFrac()
    local fillW = POP_SLIDER_W * frac
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sliderL, POP_SLIDER_CY - POP_SLIDER_H * 0.5,
            fillW, POP_SLIDER_H, POP_SLIDER_R)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 80))
        nvgFill(vg)
    end

    -- 9. 滑块
    local knobX = sliderL + POP_SLIDER_W * frac
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, POP_SLIDER_CY, POP_KNOB_SIZE * 0.5)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(POP_KNOB_STROKE_R, POP_KNOB_STROKE_G, POP_KNOB_STROKE_B, 255))
    nvgStrokeWidth(vg, POP_KNOB_STROKE_W)
    nvgStroke(vg)

    -- 10. 设置完成按钮
    local didScaleConfirm = BF.begin(vg, "bsd_confirm", POP_CONFIRM_CX, POP_CONFIRM_CY, POP_CONFIRM_W, POP_CONFIRM_H)
    drawImageCentered(vg, imgReplaceBtn, POP_CONFIRM_CX, POP_CONFIRM_CY,
        POP_CONFIRM_W, POP_CONFIRM_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, POP_CONFIRM_TEXT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(POP_CONFIRM_TEXT_R, POP_CONFIRM_TEXT_G, POP_CONFIRM_TEXT_B, 255))
    nvgText(vg, POP_CONFIRM_CX, POP_CONFIRM_CY, "设置完成", nil)
    BF.finish(vg, didScaleConfirm)
end

--- 处理弹窗输入（优先级最高）
---@param dx number
---@param dy number
---@return boolean 是否消费事件
function M.handleInput(dx, dy)
    if not open_ then return false end

    -- 品质方框选择（再次点击已选中的方框则取消为"无"）
    for i = 1, POP_QBOX_COUNT do
        local cx = qboxCX(i)
        if hitTest(dx, dy, cx, POP_QBOX_CY, POP_QBOX_SIZE, POP_QBOX_SIZE) then
            BF.trigger("bsd_qbox_" .. i)
            draftQuality_ = (draftQuality_ == i) and 0 or i
            return true
        end
    end
    -- 等级减按钮
    if hitTest(dx, dy, POP_MINUS_CX, POP_MINUS_CY, POP_MINUS_W, POP_MINUS_H) then
        BF.trigger("bsd_minus")
        draftLevel_ = math.max(0, draftLevel_ - POP_LEVEL_STEP)
        return true
    end
    -- 等级加按钮
    if hitTest(dx, dy, POP_PLUS_CX, POP_PLUS_CY, POP_PLUS_W, POP_PLUS_H) then
        BF.trigger("bsd_plus")
        draftLevel_ = math.min(POP_LEVEL_MAX, draftLevel_ + POP_LEVEL_STEP)
        return true
    end
    -- 滑条点击（含滑块溢出范围），并进入拖拽
    if hitTest(dx, dy, POP_SLIDER_CX, POP_SLIDER_CY, POP_SLIDER_W + POP_KNOB_SIZE, sliderHitH()) then
        sliderDragging_ = true
        draftLevel_ = levelFromSliderX(dx)
        return true
    end
    -- 设置完成：只发送，不立即关窗；成功回执才关。
    if hitTest(dx, dy, POP_CONFIRM_CX, POP_CONFIRM_CY, POP_CONFIRM_W, POP_CONFIRM_H) then
        BF.trigger("bsd_confirm")
        requestSave()
        return true
    end
    -- 弹窗背景外：保存草稿（同样等回执），并关闭。
    if not hitTest(dx, dy, POP_BG_CX, POP_BG_CY, POP_BG_W, POP_BG_H) then
        requestSave()
        return true
    end
    -- 弹窗内部空白：消费事件，防穿透
    return true
end

--- 滑条拖拽开始
---@param dx number
---@param dy number
---@return boolean 是否捕获
function M.dragBegin(dx, dy)
    if not open_ then return false end
    if hitTest(dx, dy, POP_SLIDER_CX, POP_SLIDER_CY, POP_SLIDER_W + POP_KNOB_SIZE, sliderHitH()) then
        sliderDragging_ = true
        draftLevel_ = levelFromSliderX(dx)
        return true
    end
    return false
end

--- 滑条拖拽移动
---@param dx number
---@return boolean 是否消费
function M.dragMove(dx)
    if not open_ or not sliderDragging_ then return false end
    draftLevel_ = levelFromSliderX(dx)
    return true
end

--- 滑条拖拽结束
---@return boolean 是否消费
function M.dragEnd()
    if not open_ or not sliderDragging_ then return false end
    sliderDragging_ = false
    return true
end

--- 服务端动作回执
---@param data table|nil
function M.onActionResult(data)
    if not data or data.action ~= (getProtocol and getProtocol().ACTION_TYPES.SET_AUTO_DECOMPOSE) then
        return false
    end
    if data.success then
        return finishSave(data.autoQuality, data.autoLevel)
    end
    -- 失败保留弹窗与草稿，玩家可重试。
    pendingSave_ = false
    print("[BlacksmithAutoDecompose] 保存失败: " .. tostring(data.reason))
    return false
end

return M
