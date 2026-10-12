-- 暗黑成功/失败特效：独占 Spine + 分层 PNG + 程序化矢量兜底，保留旧模块/API。
-- 宿主在提前 return 前调用 update(dt)，绘制同样采样全局真实时间。
-- update/draw/isPlaying 不累加 dt，同帧多次调用不会重复推进动画。
local SpineResultEffect = {}
local Sprites = require("ui.fx.DarkEffectSprites")
local DURATION_SUCCESS, DURATION_FAILURE = 1.6667, 1.3333
local playbackId = 0
local disabled = false
---@class DarkResultPlayback
---@field id number
---@field success boolean
---@field startedAt number
---@field duration number
---@field onComplete function|nil
---@field token table
---@type DarkResultPlayback|nil
local current = nil

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function clock()
    local now = time and time.elapsedTime
    if finite(now) and now >= 0 then return now end
    return nil
end

local function finishPlayback(id)
    local entry = current
    if not entry or entry.id ~= id then return end
    current = nil -- 先脱离旧记录：回调重入 play/stop/destroy 不受旧收尾影响。
    local cb = entry.onComplete
    entry.onComplete = nil
    Sprites.release(entry.token) -- 先释放旧 token，完成回调新建播放不受旧收尾影响。
    print("[SpineResultEffect] 完成 id=" .. id)
    if cb and playbackId == id then
        local ok, err = pcall(cb)
        if not ok then print("[SpineResultEffect] 完成回调失败: " .. tostring(err)) end
    end
end

local function expire(now)
    local entry = current
    if entry and now and now - entry.startedAt >= entry.duration then finishPlayback(entry.id) end
end

local function disableEffect(id, reason)
    -- 绘制过程中重入 play/stop 后，旧播放错误不得取消替代的新播放。
    if not current or current.id ~= id or playbackId ~= id then return end
    local entry = current
    entry.onComplete = nil -- 保留已有视觉故障契约：取消，不触发完成。
    current = nil
    if not disabled then
        disabled = true
        print("[SpineResultEffect] 视觉已停用，业务继续: " .. tostring(reason))
    end
    Sprites.release(entry.token)
end

--- 新 play 替换旧播放并取消旧回调，隐藏页面的旧播放同样取消。
---@param isSuccess boolean
---@param onComplete? function
function SpineResultEffect.play(isSuccess, onComplete)
    if disabled then return end
    local now = clock()
    if not now or (onComplete ~= nil and type(onComplete) ~= "function") then
        print("[SpineResultEffect] 拒绝无效播放参数")
        return
    end
    local replaced = current
    if replaced then replaced.onComplete = nil end
    playbackId = playbackId + 1
    current = { id = playbackId, success = not not isSuccess, startedAt = now,
        duration = isSuccess and DURATION_SUCCESS or DURATION_FAILURE, onComplete = onComplete, token = {} }
    if replaced then Sprites.release(replaced.token) end
    print("[SpineResultEffect] 播放" .. (isSuccess and "成功" or "失败") .. " id=" .. playbackId)
end

--- 非法 dt 安全忽略：time.elapsedTime 是唯一权威时钟。
---@param dt? number
function SpineResultEffect.update(dt)
    expire(clock())
end

---@return boolean
function SpineResultEffect.isPlaying()
    expire(clock())
    return current ~= nil
end

function SpineResultEffect.stop()
    playbackId = playbackId + 1
    local stopped = current
    if stopped then stopped.onComplete = nil end
    current = nil
    if stopped then Sprites.release(stopped.token) end
end

--- 使用调用者坐标空间；绘制异常时仍恢复其 NanoVG 状态。
---@param vg any
---@param cx number
---@param cy number
---@param size? number
---@param alpha? number
function SpineResultEffect.draw(vg, cx, cy, size, alpha)
    local now = clock()
    expire(now)
    local entry = current
    if not entry or disabled or not vg or not now then return end
    local target = size or 160
    if not finite(cx) or not finite(cy) or not finite(target) or target <= 0 then
        disableEffect(entry.id, "无效绘制坐标/尺寸")
        return
    end
    local opacity = alpha == nil and 1.0 or (finite(alpha) and math.max(0.0, math.min(1.0, alpha or 0.0)) or 0.0)
    if opacity <= 0 then return end
    local saved = false
    local ok, err = pcall(function()
        nvgSave(vg)
        saved = true
        Sprites.drawResult(vg, entry.success, cx, cy, target,
            math.max(0, now - entry.startedAt), entry.duration, opacity, entry.token)
    end)
    if saved then
        local restored, restoreErr = pcall(nvgRestore, vg)
        if not restored then ok, err = false, restoreErr end
    end
    if not ok then disableEffect(entry.id, err) end
end

---@param vg? any
function SpineResultEffect.preload(vg)
    Sprites.preload(vg) -- 共享一次 PNG 预热；按播放 token 延迟创建独占原生实例。
end

function SpineResultEffect.destroy()
    SpineResultEffect.stop()
    disabled = false -- 显式销毁是视觉失败后唯一允许重试的生命周期边界。
end

return SpineResultEffect
