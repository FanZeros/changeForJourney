--- ButtonFeedback: 通用按钮点击缩小反馈（按下即缩 → 松开恢复）
---
--- 原理:
---   Standalone/ClientInput 在 MouseButtonDown/TouchBegin 时调用 BF.onPress(dx, dy)
---   记住按下坐标。draw 阶段 begin() 根据按下坐标做命中检测，命中则立即缩小。
---   松开时 trigger(key) 被调用（在 handleInput 中），标记该按钮进入恢复动画。
---
--- 使用方式:
---   Standalone/ClientInput 中:
---     HandleMouseButtonDown → BF.onPress(dx, dy)
---     HandleMouseButtonUp   → BF.onRelease()
---
---   各页面 handleInput 中: BF.trigger("btnKey")          -- 标记松开
---   各页面 draw 中:
---     local didScale = BF.begin(vg, "btnKey", cx, cy, w, h)
---     ... 绘制按钮 ...
---     BF.finish(vg, didScale)
local M = {}

-- ======================== 配置参数 ========================
local PRESS_DUR   = 0.06   -- 按下缩小动画时长
local RELEASE_DUR = 0.12   -- 松开恢复动画时长
local MIN_SCALE   = 0.92   -- 按下时的最小缩放

-- ======================== 输入与按钮状态 ========================
local pressX, pressY = -9999, -9999   -- 由宿主转换好的设计坐标，不在此重复应用 DPR
local isPressed = false

---@class ButtonFeedbackState
---@field phase string
---@field t0 number
---@field releaseT0 number
---@type table<string, ButtonFeedbackState>
local active = {}

-- ======================== 时间段处理管线 ========================
-- 每个时间段只处理自身阶段，并将当前缩放传给下一段。
-- 这是有序穿透而非互斥分支：同帧可 press → hold → release。
---@param info ButtonFeedbackState
---@param now number
---@param scale number
---@return number
local function pressSegment(info, now, scale)
    if info.phase ~= "press" then return scale end
    local elapsed = now - info.t0
    if elapsed < PRESS_DUR then
        local t = elapsed / PRESS_DUR
        return 1.0 - (1.0 - MIN_SCALE) * t
    end
    info.phase = "hold"
    return scale
end

---@param info ButtonFeedbackState
---@param now number
---@param scale number
---@return number
local function holdSegment(info, now, scale)
    if info.phase ~= "hold" then return scale end
    if not isPressed then
        info.phase = "release"
        info.releaseT0 = now
    end
    return MIN_SCALE
end

---@param info ButtonFeedbackState
---@param now number
---@param scale number
---@return number? scale nil 表示恢复时间段已结束
local function releaseSegment(info, now, scale)
    if info.phase ~= "release" then return scale end
    local elapsed = now - info.releaseT0
    if elapsed >= RELEASE_DUR then return nil end
    local t = elapsed / RELEASE_DUR
    t = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
    return MIN_SCALE + (1.0 - MIN_SCALE) * t
end

local segments = { pressSegment, holdSegment, releaseSegment }

---@param info ButtonFeedbackState
---@param now number
---@return number?
local function sampleFeedback(info, now)
    local scale = 1.0
    for _, segment in ipairs(segments) do
        local nextScale = segment(info, now, scale)
        if nextScale == nil then return nil end
        scale = nextScale
    end
    return scale
end

-- 仅无记录时命中/建档；已有动画不重新命中、不再次播放按下音效。
---@param key string
---@param now number
---@param cx number
---@param cy number
---@param w? number
---@param h? number
---@return ButtonFeedbackState?
local function acquirePress(key, now, cx, cy, w, h)
    if not isPressed then return nil end
    local hw, hh = (w or 200) * 0.5, (h or 100) * 0.5
    if pressX < cx - hw or pressX > cx + hw
        or pressY < cy - hh or pressY > cy + hh then
        return nil
    end
    local info = { phase = "press", t0 = now, releaseT0 = 0 }
    active[key] = info
    require("systems.GameSFX").playUIClick(2)
    return info
end

-- ======================== 全局输入回调 ========================

--- 在 HandleMouseButtonDown / HandleTouchBegin 中调用
---@param dx number 设计坐标 X
---@param dy number 设计坐标 Y
function M.onPress(dx, dy)
    pressX, pressY = dx, dy
    isPressed = true
end

--- 在 HandleMouseButtonUp / HandleTouchEnd 中调用
function M.onRelease()
    -- 不提前终止 press 时间段；不足 .06 秒的短按仍先完成缩小。
    isPressed = false
end

-- ======================== 按钮 API ========================

--- 在 handleInput 中调用（松开时），标记按钮进入恢复阶段
---@param key string
function M.trigger(key)
    local info = active[key]
    if info and (info.phase == "press" or info.phase == "hold") then
        info.phase = "release"
        info.releaseT0 = time.elapsedTime
    else
        -- release 期间复触发也走此分支：重建时间段并再播放一次点击音。
        -- 保持两次 elapsedTime 读取，不合并为单次采样。
        active[key] = {
            phase = "release",
            t0 = time.elapsedTime,
            releaseT0 = time.elapsedTime,
        }
        require("systems.GameSFX").playUIClick(2)
    end
end

--- 在按钮绘制前调用，检测命中并应用缩放变换
---@param vg any NanoVG 上下文
---@param key string 按钮标识
---@param cx number 按钮中心 X（设计坐标）
---@param cy number 按钮中心 Y（设计坐标）
---@param w? number 按钮宽度
---@param h? number 按钮高度
---@return boolean didScale 是否应用了缩放（传给 finish）
function M.begin(vg, key, cx, cy, w, h)
    local info = active[key]
    local now = time.elapsedTime
    if not info then
        info = acquirePress(key, now, cx, cy, w, h)
        if not info then return false end
    end

    local s = sampleFeedback(info, now)
    if s == nil then
        active[key] = nil
        return false
    end

    -- 设计坐标下的原始 NanoVG 变换顺序保持不变。
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, s, s)
    nvgTranslate(vg, -cx, -cy)
    return true
end

--- 在按钮绘制后调用，恢复变换
---@param vg any NanoVG 上下文
---@param didScale boolean begin 的返回值
function M.finish(vg, didScale)
    if didScale then
        nvgRestore(vg)
    end
end

return M
