-- ============================================================================
-- SpineResultEffect - 通用成功/失败 Spine 动画特效
-- 底层封装：直接使用 nvgSpineCreate / nvgSpineRender 在 NanoVG 中播放
-- 用法：
--   local SpineResultEffect = require("ui.fx.SpineResultEffect")
--   SpineResultEffect.play(true, function() print("done") end)   -- 成功
--   SpineResultEffect.play(false)                                 -- 失败
--   在 NanoVGRender 中调用 SpineResultEffect.draw(vg, cx, cy, size)
-- ============================================================================

---@diagnostic disable: undefined-global
-- nvgSpineCreate / nvgSpineRender 是引擎内置全局函数（NanoVG Spine 扩展）

local SpineResultEffect = {}

-- Spine 资源路径（三件套在 assets/image/spine/ 下）
local SPINE_JSON = "image/spine/UI_SPINE_QHTX.json"

-- 动画名称映射
local ANIM_SUCCESS = "1"
local ANIM_FAILURE = "2"

-- 内部状态
local spineInstance = nil   -- nvgSpineCreate 返回的实例
local loaded = false        -- 是否已加载
local playing = false       -- 是否正在播放
local lastTime = 0          -- 上一帧 elapsedTime，用于算 dt
local onCompleteCb = nil    -- 播放完成回调
local initVg = nil          -- 记录初始化时的 vg 上下文

-- Spine 骨架原始尺寸（从 JSON skeleton 字段读取）
local DATA_X = -501
local DATA_Y = -449.5
local DATA_W = 1002
local DATA_H = 899

--- 初始化 Spine 实例（懒加载，首次 draw 时自动调用）
---@param vg any NanoVG 上下文
---@return boolean 是否成功
local function ensureLoaded(vg)
    if loaded and spineInstance then return true end
    if not vg then return false end

    spineInstance = nvgSpineCreate(vg)
    if not spineInstance then
        print("[SpineResultEffect] nvgSpineCreate failed")
        return false
    end

    if not spineInstance:Load(SPINE_JSON) then
        print("[SpineResultEffect] Failed to load: " .. SPINE_JSON)
        spineInstance = nil
        return false
    end

    -- atlas 中 pma:true，启用预乘 alpha
    spineInstance:SetPremultipliedAlpha(true)
    spineInstance:SetDefaultMix(0.1)
    spineInstance:SetSpeed(1.0)

    -- 注册完成回调
    spineInstance:SetCompleteListener(function(track, anim)
        if playing then
            playing = false
            if onCompleteCb then
                local cb = onCompleteCb
                onCompleteCb = nil
                cb()
            end
        end
    end)

    loaded = true
    initVg = vg
    print("[SpineResultEffect] Loaded OK")
    return true
end

--- 播放成功或失败动画
---@param isSuccess boolean true=成功动画(1), false=失败动画(2)
---@param onComplete? function 播放完成后的回调
function SpineResultEffect.play(isSuccess, onComplete)
    if not loaded or not spineInstance then
        -- 未加载时记录待播放状态，等 draw 时初始化后补播
        playing = true
        onCompleteCb = onComplete
        -- 暂存要播放的动画名
        SpineResultEffect._pendingAnim = isSuccess and ANIM_SUCCESS or ANIM_FAILURE
        lastTime = time.elapsedTime
        return
    end

    local animName = isSuccess and ANIM_SUCCESS or ANIM_FAILURE
    spineInstance:SetAnimation(0, animName, false)
    playing = true
    onCompleteCb = onComplete
    lastTime = time.elapsedTime
    SpineResultEffect._pendingAnim = nil
    print("[SpineResultEffect] Playing: " .. animName)
end

--- 是否正在播放
---@return boolean
function SpineResultEffect.isPlaying()
    return playing
end

--- 停止播放
function SpineResultEffect.stop()
    playing = false
    onCompleteCb = nil
    SpineResultEffect._pendingAnim = nil
    if spineInstance then
        spineInstance:ClearTracks()
    end
end

--- 每帧绘制（在 NanoVG 渲染函数中调用）
--- 自动处理 update + render，调用方只需提供绘制中心
--- 缩放到调用方给出的槽位尺寸，并按骨架边界居中。
---@param vg any NanoVG 上下文
---@param cx number 绘制中心 X（设计坐标）
---@param cy number 绘制中心 Y（设计坐标）
---@param size number|nil 目标边长，默认按装备槽 160
function SpineResultEffect.draw(vg, cx, cy, size)
    if not playing then return end

    -- 懒加载
    if not ensureLoaded(vg) then return end

    -- 处理待播放动画（play 在 load 之前被调用的情况）
    if SpineResultEffect._pendingAnim then
        spineInstance:SetAnimation(0, SpineResultEffect._pendingAnim, false)
        SpineResultEffect._pendingAnim = nil
        lastTime = time.elapsedTime
    end

    -- 计算 dt
    local now = time.elapsedTime
    local dt = now - lastTime
    if dt > 0.1 then dt = 0.016 end  -- 防止暂停后大跳
    lastTime = now

    -- 更新骨架动画
    spineInstance:Update(dt)

    local target = size or 160
    local scale = math.min(target / DATA_W, target / DATA_H)
    spineInstance:SetScale(scale, -scale)
    local drawW = DATA_W * scale
    local drawH = DATA_H * scale
    local boxX = cx - drawW * 0.5
    local boxY = cy - drawH * 0.5
    local posX = boxX - DATA_X * scale
    local posY = boxY + (DATA_H + DATA_Y) * scale
    spineInstance:SetPosition(posX, posY)

    -- 渲染
    nvgSpineRender(vg, spineInstance)
end

--- 预加载 Spine 实例（启动时调用，避免首次播放卡顿）
---@param vg any NanoVG 上下文
function SpineResultEffect.preload(vg)
    ensureLoaded(vg)
end

--- 释放资源
function SpineResultEffect.destroy()
    if spineInstance then
        spineInstance:Unload()
        spineInstance = nil
    end
    loaded = false
    playing = false
    onCompleteCb = nil
    SpineResultEffect._pendingAnim = nil
end

return SpineResultEffect
