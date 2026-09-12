-- ============================================================================
-- UpdateNoticePopup - TapTap 客户端更新提醒弹窗
-- ============================================================================
--
-- 当检测到 nvgSpineCreate 不可用时弹出，提醒玩家更新 TapTap 客户端。
--
--   local UpdateNoticePopup = require("ui.UpdateNoticePopup")
--   UpdateNoticePopup.init(vg)
--   UpdateNoticePopup.show()
--   -- 渲染：
--   UpdateNoticePopup.draw(vg)
--   -- 输入（点击"确定"关闭）：
--   UpdateNoticePopup.handleInput(dx, dy)
--
-- ============================================================================

local UpdateNoticePopup = {}

-- ======================== 设计常量（1080×2400） ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

-- 遮罩
local MASK_ALPHA = 180  -- ~70% 不透明度

-- 面板
local PANEL_W     = 720
local PANEL_H     = 440
local PANEL_CX    = DESIGN_W * 0.5
local PANEL_CY    = DESIGN_H * 0.5
local PANEL_ROUND = 24

-- 标题
local TITLE_TEXT   = "温馨提示"
local TITLE_FONT   = 42
local TITLE_Y_OFF  = -150  -- 相对面板中心

-- 内容
local CONTENT_TEXT = "部分动画效果无法正常显示，请检查\nTapTap是否为最新版本。如已是最新，\n请关闭游戏和TapTap后台后重新打开。"
local CONTENT_FONT = 32
local CONTENT_Y_OFF = -40  -- 相对面板中心
local LINE_HEIGHT  = 46

-- 按钮
local BTN_W      = 320
local BTN_H      = 88
local BTN_CX     = PANEL_CX
local BTN_CY_OFF = 140  -- 相对面板中心
local BTN_ROUND  = 16
local BTN_TEXT   = "我知道了"
local BTN_FONT   = 36

-- ======================== 状态 ========================

local isOpen_ = false
---@type integer|nil
local vg_     = nil
local fontId_ = -1

-- ======================== API ========================

function UpdateNoticePopup.init(vg)
    vg_ = vg
    fontId_ = nvgCreateFont(vg, "upd-notice", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
end

function UpdateNoticePopup.show()
    if isOpen_ then return end
    isOpen_ = true
    print("[UpdateNoticePopup] shown — please update TapTap client")
end

function UpdateNoticePopup.isOpen()
    return isOpen_
end

function UpdateNoticePopup.close()
    isOpen_ = false
    print("[UpdateNoticePopup] closed")
end

function UpdateNoticePopup.draw(vg)
    if not isOpen_ then return end

    local cx = PANEL_CX
    local cy = PANEL_CY

    -- 1) 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, MASK_ALPHA))
    nvgFill(vg)

    -- 2) 面板背景（深蓝灰色圆角矩形）
    local px = cx - PANEL_W * 0.5
    local py = cy - PANEL_H * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, PANEL_W, PANEL_H, PANEL_ROUND)
    nvgFillColor(vg, nvgRGBA(32, 36, 48, 245))
    nvgFill(vg)

    -- 面板边框
    nvgStrokeColor(vg, nvgRGBA(80, 90, 120, 160))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 3) 标题
    nvgFontFace(vg, "upd-notice")
    nvgFontSize(vg, TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 210, 80, 255))
    nvgText(vg, cx, cy + TITLE_Y_OFF, TITLE_TEXT)

    -- 分隔线
    local sepY = cy + TITLE_Y_OFF + 32
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - PANEL_W * 0.4, sepY)
    nvgLineTo(vg, cx + PANEL_W * 0.4, sepY)
    nvgStrokeColor(vg, nvgRGBA(80, 90, 120, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 4) 内容文字（多行）
    nvgFontSize(vg, CONTENT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 225, 235, 255))

    local lines = {}
    for line in CONTENT_TEXT:gmatch("([^\n]+)") do
        lines[#lines + 1] = line
    end
    local totalTextH = #lines * LINE_HEIGHT
    local startY = cy + CONTENT_Y_OFF - totalTextH * 0.5 + LINE_HEIGHT * 0.5
    for i, line in ipairs(lines) do
        nvgText(vg, cx, startY + (i - 1) * LINE_HEIGHT, line)
    end

    -- 5) 按钮
    local btnY = cy + BTN_CY_OFF
    local btnX = BTN_CX - BTN_W * 0.5

    -- 按钮背景（渐变蓝色）
    local bgPaint = nvgLinearGradient(vg, btnX, btnY - BTN_H * 0.5, btnX, btnY + BTN_H * 0.5,
        nvgRGBA(60, 130, 240, 255), nvgRGBA(40, 90, 200, 255))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY - BTN_H * 0.5, BTN_W, BTN_H, BTN_ROUND)
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)

    -- 按钮文字
    nvgFontSize(vg, BTN_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, BTN_CX, btnY, BTN_TEXT)
end

--- 点击处理：点击任意位置关闭弹窗
---@param dx number 点击 X（设计坐标）
---@param dy number 点击 Y（设计坐标）
---@return boolean consumed 是否消费了事件
function UpdateNoticePopup.handleInput(dx, dy)
    if not isOpen_ then return false end
    -- 点击任意位置关闭（按钮或遮罩均可）
    isOpen_ = false
    print("[UpdateNoticePopup] closed by tap")
    return true
end

return UpdateNoticePopup
