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

-- ======================== 全局按下状态 ========================
local pressX, pressY = -9999, -9999   -- 当前按下的设计坐标
local isPressed = false               -- 鼠标/触摸是否处于按下状态

-- ======================== 按钮状态 ========================
--- { [key] = { phase, t0, releaseT0 } }
---   phase: "press" | "hold" | "release"
local active = {}

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
    isPressed = false
end

-- ======================== 按钮 API ========================

--- 在 handleInput 中调用（松开时），标记按钮进入恢复阶段
---@param key string
function M.trigger(key)
    local info = active[key]
    if info and (info.phase == "press" or info.phase == "hold") then
        -- 按钮已在按下状态，切换到恢复
        info.phase = "release"
        info.releaseT0 = time.elapsedTime
    else
        -- 没有按下记录（可能是拖拽后触发、或其他情况），做一次快速弹跳
        active[key] = {
            phase = "release",
            t0 = time.elapsedTime,
            releaseT0 = time.elapsedTime,
        }
    end
    require("systems.GameSFX").playUIClick(2)
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
    local s = 1.0

    -- 没有活跃记录时，检测是否被按下命中
    if not info then
        if not isPressed then return false end
        -- 命中检测
        local hw, hh = (w or 200) * 0.5, (h or 100) * 0.5
        if pressX < cx - hw or pressX > cx + hw
            or pressY < cy - hh or pressY > cy + hh then
            return false
        end
        -- 命中！启动按下动画
        info = {
            phase = "press",
            t0 = now,
            releaseT0 = 0,
        }
        active[key] = info
    end

    -- Phase 1: 快速缩小
    if info.phase == "press" then
        local elapsed = now - info.t0
        if elapsed < PRESS_DUR then
            local t = elapsed / PRESS_DUR
            s = 1.0 - (1.0 - MIN_SCALE) * t
        else
            info.phase = "hold"
        end
    end

    -- Phase 2: 保持缩小，等待 trigger() 或松开
    if info.phase == "hold" then
        s = MIN_SCALE
        if not isPressed then
            -- 鼠标已松开但 trigger 未调用（拖拽出按钮区域等），直接恢复
            info.phase = "release"
            info.releaseT0 = now
        end
    end

    -- Phase 3: ease-out 恢复到 1.0
    if info.phase == "release" then
        local elapsed = now - info.releaseT0
        if elapsed >= RELEASE_DUR then
            active[key] = nil
            return false
        end
        local t = elapsed / RELEASE_DUR
        -- ease-out cubic
        t = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
        s = MIN_SCALE + (1.0 - MIN_SCALE) * t
    end

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
