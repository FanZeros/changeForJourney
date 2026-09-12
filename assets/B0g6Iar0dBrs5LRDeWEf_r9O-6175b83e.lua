-- ============================================================================
-- RedeemCodePanel - 兑换码界面
-- 入口：设置界面点击兑换码按钮
-- 坐标系: 设计分辨率 1080×2400，所有位置为中心点坐标
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local Protocol = require("shared.Protocol")

local RewardPopup     = require("ui.RewardPopup")
local BF              = require("systems.ButtonFeedback")
local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest

local RedeemCodePanel = {}

-- ======================== 外部回调 ========================

---@type fun(action: string, params: table)|nil
local sendActionFn_ = nil

-- ======================== 状态 ========================

local state = {
    open      = false,
    animTime  = 0,
    closing   = false,
    closeTime = 0,
    -- 输入
    inputText  = "",       -- 当前输入的文本
    inputFocus = false,    -- 输入框是否聚焦
    cursorBlink = 0,       -- 光标闪烁计时
    -- 提交状态
    submitting = false,    -- 正在提交中
    submitTime = 0,        -- 提交时间戳（超时保护用）
    -- 结果反馈
    toastText  = nil,      ---@type string|nil
    toastTimer = 0,
}

-- ======================== 图片资源句柄 ========================

local img = {
    bg        = -1,   -- UI_EJBB.png 九宫格弹窗背景
    confirmBtn = -1,  -- UI_AN_LV.png 确定按钮
}

-- ======================== 布局常量 ========================

-- 动画
local ANIM_OPEN_DUR  = 0.25
local ANIM_CLOSE_DUR = 0.15

-- 1. 背景框（九宫格）
local BG = {
    CX = 540, CY = 1199, W = 996, H = 627,
    IT = 175, IL = 100, IR = 100, IB = 100,
}

-- 2. 标题 "兑换码"
local TTL = {
    X = 540, Y = 1019, FONT = 60,
    R = 0x36, G = 0x2c, B = 0x21,
}

-- 3. 输入框
local INPUT_BOX = {
    CX = 540, CY = 1177, W = 700, H = 90, R = 12,
    A = 26,  -- 纯黑 10%
}

-- 4. 占位符文本 "请输入兑换码"
local PLACEHOLDER = {
    X = 540, Y = 1177, FONT = 42,
    A = 77,  -- 纯黑 30%
}

-- 5. 确定按钮
local CONFIRM_BTN = {
    CX = 540, CY = 1333, W = 410, H = 100,
}

-- 6. "确定" 文本
local CONFIRM_TXT = {
    X = 540, Y = 1333, FONT = 40,
    A = 179,  -- 纯黑 70%
}

-- 输入文本样式
local INPUT_TXT = {
    FONT = 42,
    R = 0, G = 0, B = 0, A = 200,
}

-- 光标样式
local CURSOR = {
    BLINK_PERIOD = 1.0,  -- 闪烁周期（秒）
    W = 2, H = 36,
    R = 0, G = 0, B = 0, A = 180,
}

-- 提交反馈 toast
local TOAST = { DURATION = 2.0, FONT = 32, R = 16 }

-- 提交超时保护（秒）：超过此时间未收到服务端响应则自动重置
local SUBMIT_TIMEOUT_SECS = 10

-- ============================================================================
-- UTF-8 辅助
-- ============================================================================

--- 删除 UTF-8 字符串最后一个字符
---@param s string
---@return string
local function utf8RemoveLast(s)
    if #s == 0 then return s end
    local i = #s
    while i > 0 do
        local byte = s:byte(i)
        if byte < 0x80 or byte >= 0xC0 then
            -- 找到字符起始字节
            return s:sub(1, i - 1)
        end
        i = i - 1
    end
    return ""
end

--- 计算 UTF-8 字符串的字符数
---@param s string
---@return number
local function utf8Len(s)
    local count = 0
    local i = 1
    while i <= #s do
        local byte = s:byte(i)
        if byte < 0x80 then
            i = i + 1
        elseif byte < 0xE0 then
            i = i + 2
        elseif byte < 0xF0 then
            i = i + 3
        else
            i = i + 4
        end
        count = count + 1
    end
    return count
end

-- ============================================================================
-- Public API
-- ============================================================================

--- 初始化（加载图片资源，仅调用一次）
function RedeemCodePanel.init(vg)
    img.bg         = nvgCreateImage(vg, "image/UI_EJBB.png", 0)
    img.confirmBtn = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)

    if img.bg < 0 then print("[RedeemCodePanel] WARN: UI_EJBB.png load failed") end
    if img.confirmBtn < 0 then print("[RedeemCodePanel] WARN: UI_AN_LV.png load failed") end

    -- 注意: TextInput 事件由 GMConsolePanel 统一订阅并转发，避免后订阅覆盖前订阅
    print("[RedeemCodePanel] init OK")
end

--- 打开面板
function RedeemCodePanel.open()
    if state.open then return end
    state.open = true
    state.closing = false
    state.animTime = time.elapsedTime
    state.inputText = ""
    state.inputFocus = true
    state.cursorBlink = 0
    state.submitting = false
    state.toastText = nil
    state.toastTimer = 0
    -- 显示移动端软键盘
    input:SetScreenKeyboardVisible(true)
    print("[RedeemCodePanel] 打开")
end

--- 关闭面板
function RedeemCodePanel.close()
    if not state.open or state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    state.inputFocus = false
    -- 隐藏移动端软键盘
    input:SetScreenKeyboardVisible(false)
    print("[RedeemCodePanel] 关闭")
end

--- 是否打开
function RedeemCodePanel.isOpen()
    return state.open
end

--- 显示 toast 反馈
local function showToast(text)
    state.toastText  = text
    state.toastTimer = TOAST.DURATION
end

--- 注入发送回调（由 Client.lua / Standalone.lua 调用）
---@param fn fun(action: string, params: table)
function RedeemCodePanel.setSendAction(fn)
    sendActionFn_ = fn
end

--- 操作结果回调（由 Client.lua 的 handleActionResult 转发）
---@param data table
function RedeemCodePanel.onActionResult(data)
    if not state.submitting then return end
    state.submitting = false

    if data.success then
        showToast(data.message or "兑换成功")
        state.inputText = ""
        -- 弹出奖励面板展示兑换奖励
        if data.rewards and #data.rewards > 0 then
            RewardPopup.show("兑换奖励", data.rewards)
        end
        print("[RedeemCodePanel] 兑换成功: " .. tostring(data.message))
    else
        showToast(data.reason or "兑换失败")
        print("[RedeemCodePanel] 兑换失败: " .. tostring(data.reason))
    end
end

--- 提交兑换码
local function submitCode()
    local code = state.inputText
    if #code == 0 then
        print("[RedeemCodePanel] 兑换码为空，不提交")
        return
    end
    if state.submitting then
        print("[RedeemCodePanel] 正在提交中，请等待")
        return
    end

    if not sendActionFn_ then
        print("[RedeemCodePanel] WARN: sendAction 未设置，无法提交")
        showToast("网络未就绪")
        return
    end

    state.submitting = true
    state.submitTime = time.elapsedTime
    print("[RedeemCodePanel] 提交兑换码: " .. code)
    sendActionFn_(Protocol.ACTION_TYPES.REDEEM_CODE, { code = code })
end

--- 点击处理
function RedeemCodePanel.handleInput(dx, dy)
    if not state.open or state.closing then return true end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.animTime < 0.05 then return true end

    -- 点击弹窗外部 → 关闭
    if not hitTest(dx, dy, BG.CX, BG.CY, BG.W, BG.H) then
        RedeemCodePanel.close()
        return true
    end

    -- 点击输入框 → 聚焦 + 弹出键盘
    if hitTest(dx, dy, INPUT_BOX.CX, INPUT_BOX.CY, INPUT_BOX.W, INPUT_BOX.H) then
        state.inputFocus = true
        state.cursorBlink = 0
        input:SetScreenKeyboardVisible(true)
        print("[RedeemCodePanel] 输入框获取焦点")
        return true
    end

    -- 确定按钮
    if hitTest(dx, dy, CONFIRM_BTN.CX, CONFIRM_BTN.CY, CONFIRM_BTN.W, CONFIRM_BTN.H) then
        BF.trigger("rcp_confirm")
        submitCode()
        return true
    end

    -- 弹窗内部消费事件
    return true
end

--- 每帧更新（处理退格键 + 回车键 + 光标闪烁 + toast 倒计时）
function RedeemCodePanel.update(dt)
    if not state.open then return end

    -- toast 倒计时（关闭动画期间也需要更新）
    if state.toastTimer > 0 then
        state.toastTimer = state.toastTimer - dt
        if state.toastTimer <= 0 then
            state.toastText = nil
            state.toastTimer = 0
        end
    end

    if state.closing then return end

    -- 提交超时保护：超过 SUBMIT_TIMEOUT_SECS 未收到响应则自动重置
    if state.submitting and (time.elapsedTime - state.submitTime) > SUBMIT_TIMEOUT_SECS then
        print("[RedeemCodePanel] 提交超时，自动重置 submitting 状态")
        state.submitting = false
        showToast("请求超时，请重试")
    end

    -- 光标闪烁
    state.cursorBlink = state.cursorBlink + dt

    -- 退格键（提交中不允许编辑）
    if state.inputFocus and not state.submitting and input:GetKeyPress(KEY_BACKSPACE) then
        state.inputText = utf8RemoveLast(state.inputText)
        state.cursorBlink = 0  -- 重置闪烁
    end

    -- 回车键 → 提交
    if state.inputFocus and input:GetKeyPress(KEY_RETURN) then
        submitCode()
    end
end

-- ======================== 全局事件处理（文本输入）========================

--- TextInput 事件处理（全局函数，SubscribeToEvent 注册）
---@param eventType string
---@param eventData TextInputEventData
function HandleRedeemTextInput(eventType, eventData)
    if not state.open or state.closing or not state.inputFocus then return end

    local char = eventData["Text"]:GetString()
    if char and #char > 0 then
        -- 限制输入长度（兑换码一般不超过 30 字符）
        if utf8Len(state.inputText) < 30 then
            state.inputText = state.inputText .. char
            state.cursorBlink = 0  -- 重置闪烁
        end
    end
end

-- ======================== 绘制 ========================

function RedeemCodePanel.draw(vg)
    if not state.open then return end

    -- 动画进度
    local animProgress = 1.0
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        animProgress = 1.0 - math.min(elapsed / ANIM_CLOSE_DUR, 1.0)
        if animProgress <= 0 then
            state.open = false
            state.closing = false
            return
        end
    else
        local elapsed = time.elapsedTime - state.animTime
        animProgress = math.min(elapsed / ANIM_OPEN_DUR, 1.0)
        animProgress = DrawUtil.easeOutBack(animProgress)
    end

    nvgSave(vg)

    -- 弹窗缩放动画（以弹窗中心为原点）
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, animProgress, animProgress)
    nvgTranslate(vg, -BG.CX, -BG.CY)

    -- ── 1. 背景框（九宫格）──
    drawNineSlice(vg, img.bg,
        BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5,
        BG.W, BG.H,
        BG.IT, BG.IR, BG.IB, BG.IL)

    -- ── 2. 标题 "兑换码"（无描边，纯色文本）──
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TTL.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(TTL.R, TTL.G, TTL.B, 255))
    nvgText(vg, TTL.X, TTL.Y, "兑换码", nil)

    -- ── 3. 输入框背景 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        INPUT_BOX.CX - INPUT_BOX.W * 0.5, INPUT_BOX.CY - INPUT_BOX.H * 0.5,
        INPUT_BOX.W, INPUT_BOX.H, INPUT_BOX.R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, INPUT_BOX.A))
    nvgFill(vg)

    -- ── 4. 占位符 或 输入文本 ──
    local hasText = #state.inputText > 0
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, PLACEHOLDER.FONT)

    local textEndX = INPUT_BOX.CX  -- 光标默认居中（无文本时）

    if not hasText then
        -- 占位符 "请输入兑换码"（居中）
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, PLACEHOLDER.A))
        nvgText(vg, PLACEHOLDER.X, PLACEHOLDER.Y, "请输入兑换码", nil)
    else
        -- 已输入文本（左对齐，左边距 20px）
        local textLeft = INPUT_BOX.CX - INPUT_BOX.W * 0.5 + 20
        nvgFontSize(vg, INPUT_TXT.FONT)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(INPUT_TXT.R, INPUT_TXT.G, INPUT_TXT.B, INPUT_TXT.A))
        textEndX = nvgText(vg, textLeft, INPUT_BOX.CY, state.inputText, nil)
    end

    -- 光标（聚焦时闪烁）
    if state.inputFocus then
        local blinkPhase = (state.cursorBlink % CURSOR.BLINK_PERIOD) / CURSOR.BLINK_PERIOD
        if blinkPhase < 0.5 then
            local cursorX = textEndX + 2
            nvgBeginPath(vg)
            nvgRect(vg,
                cursorX, INPUT_BOX.CY - CURSOR.H * 0.5,
                CURSOR.W, CURSOR.H)
            nvgFillColor(vg, nvgRGBA(CURSOR.R, CURSOR.G, CURSOR.B, CURSOR.A))
            nvgFill(vg)
        end
    end

    -- ── 5. 确定按钮 ──
    local _bf1 = BF.begin(vg, "rcp_confirm", CONFIRM_BTN.CX, CONFIRM_BTN.CY, CONFIRM_BTN.W, CONFIRM_BTN.H)
    local btnAlpha = state.submitting and 0.5 or 1.0
    if img.confirmBtn >= 0 then
        drawImageCentered(vg, img.confirmBtn, CONFIRM_BTN.CX, CONFIRM_BTN.CY, CONFIRM_BTN.W, CONFIRM_BTN.H, btnAlpha)
    end

    -- ── 6. 按钮文本（提交中显示"提交中..."）──
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, CONFIRM_TXT.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local btnTextAlpha = state.submitting and 100 or CONFIRM_TXT.A
    nvgFillColor(vg, nvgRGBA(0, 0, 0, btnTextAlpha))
    nvgText(vg, CONFIRM_TXT.X, CONFIRM_TXT.Y, state.submitting and "提交中..." or "确定", nil)
    BF.finish(vg, _bf1)

    -- ── 7. Toast 反馈 ──
    if state.toastText and state.toastTimer > 0 then
        local fadeIn  = 0.15
        local fadeOut = 0.3
        local elapsed = TOAST.DURATION - state.toastTimer
        local alpha = 1.0
        if elapsed < fadeIn then
            alpha = elapsed / fadeIn
        elseif state.toastTimer < fadeOut then
            alpha = state.toastTimer / fadeOut
        end
        local ta = math.floor(alpha * 220)

        -- 测量文字宽度
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TOAST.FONT)
        local tw = nvgTextBounds(vg, 0, 0, state.toastText)
        local pw, ph = tw + 40, TOAST.FONT + 24
        local tx, ty = BG.CX, BG.CY + BG.H * 0.5 + 50

        -- 背景圆角矩形
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx - pw * 0.5, ty - ph * 0.5, pw, ph, TOAST.R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, ta))
        nvgFill(vg)

        -- 文字
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 255)))
        nvgText(vg, tx, ty, state.toastText, nil)
    end

    nvgRestore(vg)
end

return RedeemCodePanel
