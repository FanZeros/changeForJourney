-- ============================================================================
-- SpinePowerUpEffect - 战斗力提升 Spine 动画 + 数值展示
-- 触发时机：天赋点技/转职/穿戴装备等导致战斗力提升时
-- 底层封装：nvgSpineCreate / nvgSpineRender + DrawUtil 描边文字
-- 用法：
--   local SpinePowerUpEffect = require("ui.SpinePowerUpEffect")
--   SpinePowerUpEffect.init()                      -- Start 时初始化（订阅事件）
--   SpinePowerUpEffect.draw(vg)                    -- NanoVGRender 中每帧调用
--   SpinePowerUpEffect.destroy()                   -- Stop 时清理
-- ============================================================================

---@diagnostic disable: undefined-global

local EventBus   = require("core.EventBus")
local GameEvents = require("config.GameEvents")
local GameState  = require("core.GameState")
local DrawUtil   = require("core.DrawUtil")

local SpinePowerUpEffect = {}

-- ======================== 常量 ========================

-- Spine 资源（三件套在 assets/image/spine/ 下）
local SPINE_JSON  = "image/spine/UI_SPINE_ZDLTS.json"
local ANIM_NAME   = "1"

-- 骨架原始尺寸（来自 JSON skeleton 字段）
local DATA_X = -345.5
local DATA_Y = -73.59
local DATA_W = 691
local DATA_H = 228.54

-- 布局坐标（设计分辨率）
local SPINE_X = 571          -- Spine 动画中心 X
local SPINE_Y = 1949         -- Spine 动画中心 Y

local TEXT_POWER_X  = 503    -- 当前战斗力 X
local TEXT_POWER_Y  = 1992   -- 当前战斗力 Y
local TEXT_DELTA_X  = 627    -- 提升数值 X
local TEXT_DELTA_Y  = 1992   -- 提升数值 Y
local TEXT_SIZE     = 47     -- 字号
local TEXT_STROKE   = 4      -- 描边宽度

-- 颜色
local COLOR_WHITE = { 255, 255, 255 }        -- 当前战斗力：纯白
local COLOR_GOLD  = { 0xfc, 0xe8, 0x5d }     -- 提升数值：#fce85d

-- 文字时间轴（秒）
local TEXT_FADE_IN_AT   = 0.66    -- 文字开始淡入的时刻
local TEXT_FADE_IN_DUR  = 0.25    -- 淡入持续时长
local TEXT_FADE_OUT_AT  = 2.33    -- 文字开始淡出的时刻
local TEXT_FADE_OUT_DUR = 0.35    -- 淡出持续时长
local EFFECT_END_TIME   = TEXT_FADE_OUT_AT + TEXT_FADE_OUT_DUR  -- 整体效果结束时刻

-- 稳定化延迟（秒）：每次收到 power 变化后重置计时器，
-- 连续这么久没有新变化才认为初始化数据同步完成，开始响应后续的真实变化
local STABILIZE_DELAY = 2.0

-- ======================== 内部状态 ========================

local spineInstance = nil
local loaded    = false
local playing   = false
local lastTime  = 0

-- 显示数据
local displayPower = 0       -- 当前战斗力
local displayDelta = 0       -- 本次提升量
local animElapsed  = 0       -- 动画总经过时间
local spineCompleted = false -- Spine 动画是否已播完

-- 上一次记录的战斗力（用于计算差值）
local prevPower = nil

-- 待播放队列（短时间内多次提升合并展示）
local pendingAnim = nil      -- play() 在 load 之前被调用时暂存

-- 稳定化状态：进入游戏后服务端数据分批到达，等数据稳定后才开始响应
local stabilizing    = false  -- 是否处于稳定化阶段
local stabilizeTimer = 0      -- 距上次 power 变化的计时器

-- ======================== Spine 管理 ========================

---@param vg any
---@return boolean
local function ensureLoaded(vg)
    if loaded and spineInstance then return true end
    if not vg then return false end

    spineInstance = nvgSpineCreate(vg)
    if not spineInstance then
        print("[SpinePowerUpEffect] nvgSpineCreate failed")
        return false
    end

    if not spineInstance:Load(SPINE_JSON) then
        print("[SpinePowerUpEffect] Failed to load: " .. SPINE_JSON)
        spineInstance = nil
        return false
    end

    -- atlas pma:true
    spineInstance:SetPremultipliedAlpha(true)
    spineInstance:SetDefaultMix(0.1)
    spineInstance:SetSpeed(1.0)

    -- 播放完成回调：标记 Spine 动画已结束
    spineInstance:SetCompleteListener(function(track, anim)
        spineCompleted = true
    end)

    loaded = true
    print("[SpinePowerUpEffect] Loaded OK")
    return true
end

-- ======================== 播放控制 ========================

--- 内部播放（已知 power 和 delta）
---@param power number 当前战斗力
---@param delta number 提升量
local function playInternal(power, delta)
    displayPower = power
    displayDelta = delta
    animElapsed    = 0
    spineCompleted = false

    if not loaded or not spineInstance then
        pendingAnim = true
        playing = true
        lastTime = time.elapsedTime
        return
    end

    spineInstance:SetAnimation(0, ANIM_NAME, false)
    playing   = true
    pendingAnim = nil
    lastTime  = time.elapsedTime
end

-- ======================== 事件监听 ========================

---@param data table { power = number }
local function onPowerChanged(data)
    local newPower = data.power or 0

    -- 稳定化阶段：服务端数据分批到达，只静默更新基准值（不重置计时器，避免用户操作延长稳定期）
    if stabilizing then
        prevPower = newPower
        return
    end

    -- 首次同步（兜底），仅记录基准值
    if prevPower == nil then
        prevPower = newPower
        return
    end

    local delta = newPower - prevPower
    prevPower = newPower

    -- 只在战斗力提升时触发（降低不触发）
    if delta > 0 then
        -- 如果正在播放，合并增量
        if playing then
            displayPower = newPower
            displayDelta = displayDelta + delta
        else
            playInternal(newPower, delta)
        end
    end
end

-- ======================== 公开 API ========================

--- 初始化（在 Start / init 阶段调用）
function SpinePowerUpEffect.init()
    prevPower      = nil
    stabilizing    = true            -- 进入稳定化阶段
    stabilizeTimer = STABILIZE_DELAY -- 初始计时器
    EventBus.on(GameEvents.PLAYER_POWER_CHANGED, onPowerChanged)
end

--- 每帧绘制（在 NanoVGRender 中调用）
---@param vg any NanoVG 上下文
function SpinePowerUpEffect.draw(vg)
    -- 稳定化计时：等待服务端数据全部到达后才开始响应战斗力变化
    if stabilizing then
        local frameDt = time.timeStep or 0.016
        stabilizeTimer = stabilizeTimer - frameDt
        if stabilizeTimer <= 0 then
            stabilizing = false
            -- prevPower 已在稳定化期间被更新到最新值，后续变化才会触发动画
        end
    end

    if not playing then return end

    -- 懒加载
    if not ensureLoaded(vg) then return end

    -- 处理待播放
    if pendingAnim then
        spineInstance:SetAnimation(0, ANIM_NAME, false)
        pendingAnim = nil
        lastTime = time.elapsedTime
    end

    -- 计算 dt
    local now = time.elapsedTime
    local dt = now - lastTime
    if dt > 0.1 then dt = 0.016 end
    lastTime = now

    -- 累计动画经过时间
    animElapsed = animElapsed + dt

    -- 整体效果结束判定
    if animElapsed >= EFFECT_END_TIME then
        playing = false
        spineCompleted = false
        return
    end

    -- ---- Spine 骨架渲染 ----
    if not spineCompleted then
        spineInstance:Update(dt)
        spineInstance:SetScale(1.0, -1.0)
        local dataCenterX = DATA_X + DATA_W * 0.5
        local dataCenterY = DATA_Y + DATA_H * 0.5
        local posX = SPINE_X - dataCenterX
        local posY = SPINE_Y + dataCenterY
        spineInstance:SetPosition(posX, posY)
        nvgSpineRender(vg, spineInstance)
    end

    -- ---- 文字渲染（按时间轴淡入淡出） ----
    local textAlpha = 0.0
    if animElapsed < TEXT_FADE_IN_AT then
        -- 还没到出现时间
        textAlpha = 0.0
    elseif animElapsed < TEXT_FADE_IN_AT + TEXT_FADE_IN_DUR then
        -- 淡入阶段
        textAlpha = (animElapsed - TEXT_FADE_IN_AT) / TEXT_FADE_IN_DUR
    elseif animElapsed < TEXT_FADE_OUT_AT then
        -- 完全可见阶段
        textAlpha = 1.0
    elseif animElapsed < EFFECT_END_TIME then
        -- 淡出阶段
        textAlpha = 1.0 - (animElapsed - TEXT_FADE_OUT_AT) / TEXT_FADE_OUT_DUR
    end

    if textAlpha > 0.01 then
        nvgFontFace(vg, "sans")
        local textOpts = { alpha = textAlpha }

        -- 当前战斗力（纯白，左对齐）
        DrawUtil.drawTextStroke(vg,
            TEXT_POWER_X, TEXT_POWER_Y,
            tostring(displayPower),
            TEXT_SIZE, NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE,
            COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3],
            TEXT_STROKE, textOpts)

        -- 提升数值（金黄，左对齐）
        DrawUtil.drawTextStroke(vg,
            TEXT_DELTA_X, TEXT_DELTA_Y,
            "+" .. tostring(displayDelta),
            TEXT_SIZE, NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE,
            COLOR_GOLD[1], COLOR_GOLD[2], COLOR_GOLD[3],
            TEXT_STROKE, textOpts)
    end
end

--- 是否正在播放
---@return boolean
function SpinePowerUpEffect.isPlaying()
    return playing
end

--- 预加载（可在 LoadingScreen 阶段调用）
---@param vg any
function SpinePowerUpEffect.preload(vg)
    ensureLoaded(vg)
end

--- 释放资源
function SpinePowerUpEffect.destroy()
    EventBus.off(GameEvents.PLAYER_POWER_CHANGED, onPowerChanged)
    if spineInstance then
        spineInstance:Unload()
        spineInstance = nil
    end
    loaded         = false
    playing        = false
    spineCompleted = false
    animElapsed    = 0
    prevPower      = nil
    pendingAnim    = nil
    stabilizing    = false
    stabilizeTimer = 0
end

return SpinePowerUpEffect
