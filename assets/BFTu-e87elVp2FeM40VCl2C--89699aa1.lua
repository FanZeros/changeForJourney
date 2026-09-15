-- ============================================================================
-- SamsaraCG.lua - 轮回 CG 视频播放模块
-- 在轮回进度条结束后、开场动画 (IntroCutscene) 之前播放 CG_Samsara.mp4
-- 播放期间：视频有声音，BGM 保持播放；结束后切回战斗 BGM 轨道
-- ============================================================================

local GameConfig = require("config.GameConfig")
local GameBGM    = require("systems.GameBGM")

local SamsaraCG = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 视频路径 ========================

local VIDEO_PATH = "video/CG_Samsara.mp4"

-- ======================== 状态 ========================

local state = {
    active       = false,   -- 是否正在播放
    videoReady   = false,   -- 视频首帧是否就绪
    videoReadyT  = 0,       -- 首帧就绪时刻
    videoDuration = 0,      -- 视频总时长（秒）
    onFinish     = nil,     -- 播放结束回调
}

-- 视频播放器（全局单例，不反复创建/销毁）
local videoPlayer = nil
local nvgVideoHandle = nil
local videoPlayerInited = false

-- ======================== 工具函数 ========================

--- 确保 VideoPlayer 实例存在（全局只创建一次）
local function ensureVideoPlayer()
    if videoPlayer then return true end
    if videoPlayerInited then return false end  -- 之前创建失败，不再重试
    videoPlayerInited = true
    local ok = pcall(function()
        videoPlayer = VideoPlayer:new()
    end)
    if not ok or not videoPlayer then
        videoPlayer = nil
        print("[SamsaraCG] VideoPlayer 不可用（非 WASM 环境）")
        return false
    end
    return true
end

-- ======================== 公开 API ========================

--- 开始播放轮回 CG 视频
---@param onFinish function 视频播放完毕后的回调
function SamsaraCG.start(onFinish)
    state.onFinish = onFinish
    state.videoReady = false
    state.videoReadyT = 0
    state.videoDuration = 0
    nvgVideoHandle = nil

    if ensureVideoPlayer() then
        -- 先停止上次残留
        pcall(function() videoPlayer:Stop() end)

        local loadResult = false
        local loadOk = pcall(function()
            loadResult = videoPlayer:Load(VIDEO_PATH, 1080, 2400)
        end)
        print("[SamsaraCG] Load ok=" .. tostring(loadOk) .. " result=" .. tostring(loadResult))

        if loadOk and loadResult then
            videoPlayer:SetVolume(1.0)
            videoPlayer:SetLoop(false)
            videoPlayer:Play()
            state.active = true
            print("[SamsaraCG] 开始播放 CG 视频")
            return
        else
            print("[SamsaraCG] 视频加载失败，跳过")
        end
    else
        print("[SamsaraCG] VideoPlayer 不可用，跳过")
    end

    -- 加载失败 / 不可用 → 立即回调
    SamsaraCG._finishAndContinue()
end

--- 是否正在播放
---@return boolean
function SamsaraCG.isActive()
    return state.active
end

--- 每帧更新（在 update 循环中调用）
---@param dt number
function SamsaraCG.update(dt)
    if not state.active then return end
    if not videoPlayer then
        SamsaraCG._finishAndContinue()
        return
    end

    videoPlayer:Update()

    if not state.videoReady then
        if videoPlayer:IsReady() then
            state.videoReady = true
            state.videoReadyT = time.elapsedTime
            state.videoDuration = videoPlayer:GetDuration()
            if state.videoDuration <= 0 then state.videoDuration = 10.0 end
            print(string.format("[SamsaraCG] 视频首帧就绪 duration=%.3f", state.videoDuration))
        end
    else
        local sinceReady = time.elapsedTime - state.videoReadyT
        if sinceReady >= state.videoDuration - 0.1 then
            print(string.format("[SamsaraCG] 视频播放完毕 sinceReady=%.2f", sinceReady))
            pcall(function() videoPlayer:Stop() end)
            SamsaraCG._finishAndContinue()
        end
    end
end

--- 绘制视频帧（在 NanoVGRender 中调用）
---@param vg any NanoVG 上下文
function SamsaraCG.draw(vg)
    if not state.active then return end

    -- 黑色底色（视频未就绪时全黑）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
    nvgFill(vg)

    if videoPlayer and videoPlayer:IsReady() then
        local texture = videoPlayer:GetTexture()
        if texture then
            if not nvgVideoHandle and nvgCreateVideo then
                nvgVideoHandle = nvgCreateVideo(vg, texture)
            end
            if nvgVideoHandle and nvgVideoHandle > 0 then
                local paint = nvgImagePattern(vg, 0, 0, DESIGN_W, DESIGN_H, 0, nvgVideoHandle, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
        end
    end
end

--- 跳过视频（调试用）
function SamsaraCG.skip()
    if not state.active then return end
    print("[SamsaraCG] 跳过视频")
    if videoPlayer then
        pcall(function() videoPlayer:Stop() end)
    end
    SamsaraCG._finishAndContinue()
end

--- 内部：结束播放并调用完成回调
function SamsaraCG._finishAndContinue()
    state.active = false
    nvgVideoHandle = nil

    -- 切回战斗 BGM 轨道
    GameBGM.setScene("battle")
    print("[SamsaraCG] CG 结束，切回战斗 BGM")

    local cb = state.onFinish
    state.onFinish = nil
    if cb then cb() end
end

return SamsaraCG
