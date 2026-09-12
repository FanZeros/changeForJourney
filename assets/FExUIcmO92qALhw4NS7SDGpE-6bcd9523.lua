-- ============================================================================
-- VersionMismatchPopup - 版本不一致提醒弹窗（软提示，可关闭）
-- ============================================================================
--
-- 当客户端版本与服务端版本不同时在开始界面弹出，提醒玩家重进游戏更新。
-- 点击"我知道了"关闭，不阻断游戏流程。
--
--   local VersionMismatchPopup = require("ui.VersionMismatchPopup")
--   VersionMismatchPopup.init(vg)
--   VersionMismatchPopup.show(serverVer, clientVer)
--   -- 渲染：
--   VersionMismatchPopup.draw(vg)
--   -- 输入：
--   VersionMismatchPopup.handleInput(dx, dy)
--
-- ============================================================================

local VersionMismatchPopup = {}

-- ======================== 设计常量（1080×2400） ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

-- 遮罩
local MASK_ALPHA = 160

-- 面板
local PANEL_W     = 760
local PANEL_H     = 480
local PANEL_CX    = DESIGN_W * 0.5
local PANEL_CY    = DESIGN_H * 0.5
local PANEL_ROUND = 24

-- 标题
local TITLE_TEXT   = "版本更新提示"
local TITLE_FONT   = 42
local TITLE_Y_OFF  = -170

-- 内容
local CONTENT_FONT = 32
local CONTENT_Y_OFF = -30
local LINE_HEIGHT  = 50

-- 按钮
local BTN_W      = 320
local BTN_H      = 88
local BTN_CX     = PANEL_CX
local BTN_CY_OFF = 160
local BTN_ROUND  = 16
local BTN_TEXT   = "我知道了"
local BTN_FONT   = 36

-- ======================== 状态 ========================

local isOpen_ = false
local hasShown_ = false  -- 每个会话只弹一次
local vg_     = nil
local fontId_ = -1
local contentLines_ = {}

-- ======================== API ========================

function VersionMismatchPopup.init(vg)
    vg_ = vg
    fontId_ = nvgCreateFont(vg, "ver-mismatch", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
end

--- 显示弹窗
---@param serverVer string 服务端版本号
---@param clientVer string 客户端版本号
function VersionMismatchPopup.show(serverVer, clientVer)
    if isOpen_ or hasShown_ then return end
    isOpen_ = true
    hasShown_ = true
    contentLines_ = {
        "检测到游戏有新版本可用，",
        "请退出后重新进入游戏完成更新。",
        "",
        "当前版本: V" .. (clientVer or "?"),
        "最新版本: V" .. (serverVer or "?"),
    }
    print(string.format("[VersionMismatchPopup] shown — client=%s server=%s", tostring(clientVer), tostring(serverVer)))
end

function VersionMismatchPopup.isOpen()
    return isOpen_
end

function VersionMismatchPopup.close()
    isOpen_ = false
    print("[VersionMismatchPopup] closed")
end

function VersionMismatchPopup.draw(vg)
    if not isOpen_ then return end

    local cx = PANEL_CX
    local cy = PANEL_CY

    -- 1) 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, MASK_ALPHA))
    nvgFill(vg)

    -- 2) 面板背景
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
    nvgFontFace(vg, "ver-mismatch")
    nvgFontSize(vg, TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 210, 80, 255))
    nvgText(vg, cx, cy + TITLE_Y_OFF, TITLE_TEXT)

    -- 分隔线
    local sepY = cy + TITLE_Y_OFF + 34
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - PANEL_W * 0.38, sepY)
    nvgLineTo(vg, cx + PANEL_W * 0.38, sepY)
    nvgStrokeColor(vg, nvgRGBA(80, 90, 120, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 4) 内容文字（多行）
    nvgFontSize(vg, CONTENT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 225, 235, 255))

    local totalH = #contentLines_ * LINE_HEIGHT
    local startY = cy + CONTENT_Y_OFF - totalH * 0.5 + LINE_HEIGHT * 0.5
    for i, line in ipairs(contentLines_) do
        if line ~= "" then
            nvgText(vg, cx, startY + (i - 1) * LINE_HEIGHT, line)
        end
    end

    -- 5) 按钮
    local btnY = cy + BTN_CY_OFF
    local btnX = BTN_CX - BTN_W * 0.5

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

--- 点击处理：点击任意位置关闭
---@param dx number 点击 X（设计坐标）
---@param dy number 点击 Y（设计坐标）
---@return boolean consumed
function VersionMismatchPopup.handleInput(dx, dy)
    if not isOpen_ then return false end
    isOpen_ = false
    print("[VersionMismatchPopup] closed by tap")
    return true
end

return VersionMismatchPopup
