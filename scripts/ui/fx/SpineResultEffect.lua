-- ============================================================================
-- SpineResultEffect - 通用成功/失败 Spine 动画特效
-- 底层封装：直接使用 nvgSpineCreate / nvgSpineRender 在 NanoVG 中播放
-- 特效故障只影响表现，不得中断锻炉及同帧其他栏位的绘制。
-- ============================================================================

local SpineResultEffect = {}

local SPINE_JSON = "image/spine/UI_SPINE_QHTX.json"
local ANIM_SUCCESS = "1"
local ANIM_FAILURE = "2"
-- 与资源动画时长一致；优先读取当前轨道时长，旧扩展用此值兜底。
local ANIM_DURATION = { [ANIM_SUCCESS] = 1.6667, [ANIM_FAILURE] = 1.3333 }
local END_GRACE = 0.3

---@type SpineInstance|nil
local spineInstance = nil
local loaded = false
local disabled = false
local playing = false
local completed = false
---@type number
local lastTime = 0
---@type number
local startedAt = 0
---@type number
local duration = 0
local playbackId = 0
---@type string|nil
local currentAnim = nil
---@type function|nil
local onCompleteCb = nil

local DATA_X = -501
local DATA_Y = -449.5
local DATA_W = 1002
local DATA_H = 899

local function releaseInstance()
    local instance = spineInstance
    spineInstance = nil
    loaded = false
    if instance then
        -- 先解除 Lua 状态，Unload/Dispose 的监听不得完成旧播放。
        pcall(function() instance:SetCompleteListener(function() end) end)
        pcall(function() instance:Unload() end)
        pcall(function() instance:Dispose() end)
    end
end

local function disableEffect(reason)
    playing = false
    completed = false
    onCompleteCb = nil
    currentAnim = nil
    SpineResultEffect._pendingAnim = nil
    if not disabled then
        disabled = true
        print("[SpineResultEffect] 特效已停用，业务与绘制继续: " .. tostring(reason))
    end
    releaseInstance()
end

local function finishPlayback()
    local cb = onCompleteCb
    playing = false
    completed = false
    onCompleteCb = nil
    currentAnim = nil
    SpineResultEffect._pendingAnim = nil
    if cb then
        -- 不在 Spine Update 的监听栈内调用业务；先清旧状态，允许回调重新播放。
        local ok, err = pcall(cb)
        if not ok then print("[SpineResultEffect] 完成回调失败: " .. tostring(err)) end
    end
end

---@param vg any
---@return boolean
local function ensureLoaded(vg)
    if disabled then return false end
    if loaded and spineInstance then return true end
    if not vg then return false end
    if type(nvgSpineCreate) ~= "function" or type(nvgSpineRender) ~= "function" then
        disableEffect("Spine 扩展不可用")
        return false
    end

    local ok, err = pcall(function()
        local instance = nvgSpineCreate(vg)
        if not instance then error("nvgSpineCreate 返回空实例") end
        spineInstance = instance
        if not instance:Load(SPINE_JSON) then error("加载失败: " .. SPINE_JSON) end
        instance:SetPremultipliedAlpha(true)
        instance:SetDefaultMix(0.1)
        instance:SetSpeed(1.0)
        instance:SetCompleteListener(function(track, anim)
            if playing and track == 0 and anim == currentAnim then completed = true end
        end)
    end)
    if not ok then
        disableEffect(err)
        return false
    end
    loaded = true
    print("[SpineResultEffect] Loaded OK")
    return true
end

local function startAnimation()
    local instance = spineInstance
    local anim = SpineResultEffect._pendingAnim
    if not instance or not anim then return end
    local ok, err = pcall(function()
        if not instance:SetAnimation(0, anim, false) then error("动画不存在: " .. anim) end
    end)
    if not ok then
        disableEffect(err)
        return
    end
    -- 查询时长属于可选能力；缺少此 API 的旧扩展仍按资源时长播放。
    local durationOk, trackDuration = pcall(function() return instance:GetAnimationDuration(0) end)
    if durationOk and type(trackDuration) == "number"
        and trackDuration > 0 and trackDuration < math.huge then
        duration = trackDuration
    end
    SpineResultEffect._pendingAnim = nil
    print("[SpineResultEffect] Playing: " .. anim)
end

--- 播放成功或失败动画。业务成功与否不依赖特效是否可用。
---@param isSuccess boolean
---@param onComplete? function
function SpineResultEffect.play(isSuccess, onComplete)
    if disabled then return end
    local anim = isSuccess and ANIM_SUCCESS or ANIM_FAILURE
    playbackId = playbackId + 1
    currentAnim = anim
    duration = ANIM_DURATION[anim]
    startedAt = time.elapsedTime
    lastTime = startedAt
    completed = false
    playing = true
    onCompleteCb = onComplete
    SpineResultEffect._pendingAnim = anim
    if loaded and spineInstance then startAnimation() end
end

---@return boolean
function SpineResultEffect.isPlaying()
    -- 关闭页面后未 draw，或旧扩展漏发完成事件，也不能一直保持播放态。
    if playing and time.elapsedTime - startedAt >= duration + END_GRACE then
        finishPlayback()
    end
    return playing
end

function SpineResultEffect.stop()
    playing = false
    completed = false
    onCompleteCb = nil
    currentAnim = nil
    SpineResultEffect._pendingAnim = nil
    local instance = spineInstance
    if instance then
        local ok, err = pcall(function() instance:ClearTracks() end)
        if not ok then disableEffect(err) end
    end
end

--- NanoVGRender 中绘制；返回前恢复外层变换、裁剪与颜色状态。
---@param vg any
---@param cx number
---@param cy number
---@param size number|nil
function SpineResultEffect.draw(vg, cx, cy, size)
    if not SpineResultEffect.isPlaying() or not ensureLoaded(vg) then return end
    if SpineResultEffect._pendingAnim then startAnimation() end
    local instance = spineInstance
    if not playing or not instance then return end

    local now = time.elapsedTime
    local dt = math.max(0, math.min(now - lastTime, 0.1))
    lastTime = now
    local thisPlayback = playbackId
    local saved = false
    local ok, err = pcall(function()
        nvgSave(vg)
        saved = true
        instance:Update(dt)
        local target = size or 160
        local scale = math.min(target / DATA_W, target / DATA_H)
        instance:SetScale(scale, -scale)
        local drawW = DATA_W * scale
        local drawH = DATA_H * scale
        local posX = cx - drawW * 0.5 - DATA_X * scale
        local posY = cy - drawH * 0.5 + (DATA_H + DATA_Y) * scale
        instance:SetPosition(posX, posY)
        nvgSpineRender(vg, instance)
    end)
    if saved then
        local restored, restoreErr = pcall(nvgRestore, vg)
        if not restored then ok, err = false, restoreErr end
    end
    if not ok then
        disableEffect(err)
    elseif playing and completed and playbackId == thisPlayback then
        finishPlayback()
    end
end

--- 初始化时预热，避免首次升阶才同步加载资源。
---@param vg any
function SpineResultEffect.preload(vg)
    ensureLoaded(vg)
end

function SpineResultEffect.destroy()
    SpineResultEffect.stop()
    releaseInstance()
    disabled = false
end

return SpineResultEffect
