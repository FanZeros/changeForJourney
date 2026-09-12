-- ============================================================================
-- LoadingScreen - 加载界面
-- 全屏背景视频 + 底部渐变遮罩 + "载入中" + 进度条
-- ============================================================================

local GameConfig = require("config.GameConfig")
local SpineResultEffect = require("ui.SpineResultEffect")
local SpineCardEffect   = require("ui.SpineCardEffect")
local ChurchPage        = require("ui.ChurchPage")
local LevelUpPopup      = require("ui.LevelUpPopup")

local LoadingScreen = {}

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ── 资源句柄 ──
local vg_           = nil
local imgMask_      = -1   -- 底部渐变遮罩
local imgBarBg_     = -1   -- 进度条背景
local imgBarFill_   = -1   -- 进度条填充
local videoPlayer_  = nil
local videoHandle_  = nil

-- ── BGM（从 StartScreen 接管） ──
local bgmSource_    = nil   ---@type SoundSource
local bgmNode_      = nil   ---@type Node
local bgmVolume_    = 0.6   -- 与 StartScreen 保持一致

-- ── 状态 ──
local isOpen_          = false
local progress_        = 0     -- 当前显示进度 0~1
local targetProgress_  = 0     -- 目标进度
local fadeOut_         = false
local fadeAlpha_       = 1.0
local dotTimer_        = 0     -- "载入中..." 动画计时

-- ── 网络状态提示 ──
local statusText_      = ""    -- 状态提示文本（如"重试 1/3"）
local tapToRetryCallback_ = nil -- 点击重试回调（非nil时显示"点击屏幕重试"）

-- ── 网络 / Spine 状态 ──
local networkProgress_    = 0     -- 网络连接进度 0~1（由外部设置）
local spinePreloaded_     = false -- Spine 预加载是否已完成
local spineNotSupported_  = false -- nvgSpineCreate 不可用标志（通知外部弹窗）
local portraitPreloaded_  = false -- 情景立绘预加载是否已完成

-- 注意：主界面关键资源（UI 图片、角色图标、Spine 文件等）已全部配置在
-- resources.json 的 startup / main_ui 预下载组中，由引擎在脚本启动前预下载完成，
-- 无需在 LoadingScreen 中手动调用 DownloadResources。
-- ── 回调 ──
local onCompleteCallback_ = nil

-- ── 进度条参数 ──
local BAR_CX  = 540
local BAR_CY  = 2279
local BAR_W   = 822
local BAR_H   = 18
local BAR_PAD = 0
-- 填充条（加载完成时）尺寸
local FILL_W  = 844
local FILL_H  = 42

-- ── 工具函数 ──
local function drawImg(vg, img, cx, cy, w, h, alpha)
    local paint = nvgImagePattern(vg, cx - w * 0.5, cy - h * 0.5, w, h, 0, img, alpha or 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, cx - w * 0.5, cy - h * 0.5, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

-- ============================================================================
-- Public API
-- ============================================================================

--- 初始化（在 NanoVG 上下文创建后调用）
function LoadingScreen.init(nvgCtx)
    print("[LoadingScreen] init start")
    vg_ = nvgCtx
    print("[LoadingScreen] loading images...")
    imgMask_    = nvgCreateImage(vg_, "image/UI_ZRJM_HD.png", 0)
    imgBarBg_   = nvgCreateImage(vg_, "image/UI_ZRJM_JDT2.png", 0)
    imgBarFill_ = nvgCreateImage(vg_, "image/UI_ZRJM_JDT1.png", 0)
    print("[LoadingScreen] images OK")
    print("[LoadingScreen] init complete (Spine preload deferred to loading phase)")
end

--- 打开加载界面
--- @param opts? { videoPlayer: any, videoHandle: any, bgmSource: SoundSource, bgmNode: Node } 可选，从 StartScreen 传入已有的视频播放器和 BGM
function LoadingScreen.open(opts)
    isOpen_         = true
    progress_       = 0
    targetProgress_ = 0
    fadeOut_         = false
    fadeAlpha_       = 1.0
    dotTimer_        = 0
    networkProgress_  = 0
    spinePreloaded_   = false
    spineNotSupported_ = false
    statusText_       = ""
    tapToRetryCallback_ = nil

    -- 优先复用外部传入的视频播放器（避免重建导致黑屏闪烁）
    if opts and opts.videoPlayer then
        videoPlayer_ = opts.videoPlayer
        videoHandle_ = opts.videoHandle  -- 可能为 nil，draw 时会自动创建
    end

    -- 接管 BGM（从 StartScreen 延续播放）
    if opts and opts.bgmSource then
        bgmSource_ = opts.bgmSource
        bgmNode_   = opts.bgmNode
        bgmSource_.gain = bgmVolume_  -- 恢复音量
    end

    -- 没有可复用的播放器时才新建
    if not videoPlayer_ then
        videoPlayer_ = VideoPlayer:new()
        if videoPlayer_ then
            local ok = videoPlayer_:Load("video/UI_DLJMBJ_Compat.mp4", 1080, 2400)
            if ok then
                videoPlayer_:SetLoop(true)
                videoPlayer_:SetVolume(0)
                videoPlayer_:Play()
            end
        end
        videoHandle_ = nil
    end

    -- Spine 预加载（资源文件已由 resources.json 预下载组在引擎启动时就绪）
    if vg_ and not spinePreloaded_ then
        if type(nvgSpineCreate) ~= "function" then ---@diagnostic disable-line: undefined-global
            spineNotSupported_ = true
            print("[LoadingScreen] nvgSpineCreate not available — Spine preload skipped, need client update")
        else
            print("[LoadingScreen] Spine preloading...")
            SpineResultEffect.preload(vg_)
            SpineCardEffect.preload(vg_)
            ChurchPage.preloadSpine(vg_)
            LevelUpPopup.preload(vg_)
            print("[LoadingScreen] Spine preload complete")
        end
        spinePreloaded_ = true
    end

    -- 情景立绘预加载（所有情景中出现过的 characterId，避免首次显示时卡顿）
    if vg_ and not portraitPreloaded_ then
        local portraitIds = { 1, 2, 3, 5, 9, 10, 11, 13, 20, 21 }
        print("[LoadingScreen] Portrait preloading...")
        for _, cid in ipairs(portraitIds) do
            local path = string.format("image/角色立绘/UI_DLH_%d.png", cid)
            nvgCreateImage(vg_, path, 0)  ---@diagnostic disable-line: undefined-global
        end
        print("[LoadingScreen] Portrait preload complete (" .. #portraitIds .. " images)")
        portraitPreloaded_ = true
    end
end

--- 设置加载完成后的回调
function LoadingScreen.setOnComplete(fn)
    onCompleteCallback_ = fn
end

--- 设置网络连接进度 0~1（由 Client.lua 根据连接状态调用）
function LoadingScreen.setNetworkProgress(v)
    networkProgress_ = math.max(0, math.min(1, v))
end

--- 设置目标进度 0~1（内部使用，外部请用 setNetworkProgress）
function LoadingScreen.setProgress(v)
    targetProgress_ = math.max(0, math.min(1, v))
end

--- 设置状态提示文本（显示在"载入中..."下方，如"重试 1/3"）
function LoadingScreen.setStatusText(text)
    statusText_ = text or ""
end

--- 开启点击重试模式（显示"点击屏幕重试"提示，点击后调用 callback）
function LoadingScreen.setTapToRetry(callback)
    tapToRetryCallback_ = callback
end

--- 清除点击重试状态
function LoadingScreen.clearTapToRetry()
    tapToRetryCallback_ = nil
end

--- 每帧更新
function LoadingScreen.update(dt)
    if not isOpen_ then return end

    -- 视频帧更新
    if videoPlayer_ then
        videoPlayer_:Update()
    end

    -- "载入中..." 动画计时
    dotTimer_ = dotTimer_ + dt

    -- 点击重试检测
    if tapToRetryCallback_ and input:GetMouseButtonPress(MOUSEB_LEFT) then
        local cb = tapToRetryCallback_
        tapToRetryCallback_ = nil
        statusText_ = ""
        cb()
        return -- 回调可能重置状态，本帧不再继续
    end

    -- 进度完全由网络连接状态驱动（资源已由引擎预下载组在启动前就绪）
    -- 网络进入 STATE_IN_GAME（networkProgress_=1.0）时，游戏已可玩，放行
    if networkProgress_ >= 1.0 then
        targetProgress_ = 1.0
    else
        targetProgress_ = math.min(networkProgress_ * 0.95, 0.95) -- 未就绪时最高 95%
    end

    -- 平滑插值进度
    if progress_ < targetProgress_ then
        progress_ = progress_ + (targetProgress_ - progress_) * math.min(1, dt * 3)
        if targetProgress_ - progress_ < 0.005 then
            progress_ = targetProgress_
        end
    end

    -- 进度到达 100% 后自动淡出
    if progress_ >= 1.0 and not fadeOut_ then
        fadeOut_ = true
    end

    if fadeOut_ then
        fadeAlpha_ = fadeAlpha_ - dt * 2.0  -- 0.5 秒淡出
        -- BGM 音量同步衰减
        if bgmSource_ then
            bgmSource_.gain = math.max(fadeAlpha_, 0) * bgmVolume_
        end
        if fadeAlpha_ <= 0 then
            fadeAlpha_ = 0
            isOpen_ = false
            fadeOut_ = false
            -- 释放视频资源
            if videoPlayer_ then
                videoPlayer_:Stop()
                videoPlayer_ = nil
            end
            videoHandle_ = nil
            -- 停止 BGM 并清理节点
            if bgmSource_ then bgmSource_:Stop() end
            if bgmNode_ then bgmNode_:Remove() end
            bgmSource_ = nil
            bgmNode_ = nil
            -- 触发回调
            if onCompleteCallback_ then
                onCompleteCallback_()
            end
        end
    end
end

--- 绘制（在设计空间 1080×2400 内调用）
function LoadingScreen.draw(vg)
    if not isOpen_ then return end

    nvgSave(vg)
    if fadeOut_ then
        nvgGlobalAlpha(vg, math.max(fadeAlpha_, 0))
    end

    -- 1. 全屏背景视频
    -- 尝试创建 videoHandle（仅首次）
    if not videoHandle_ and videoPlayer_ and videoPlayer_:IsReady() then
        local texture = videoPlayer_:GetTexture()
        if texture and nvgCreateVideo then
            videoHandle_ = nvgCreateVideo(vg, texture)
        end
    end
    -- 已有 handle 就直接绘制，避免循环衔接时闪黑
    if videoHandle_ and videoHandle_ > 0 then
        drawImg(vg, videoHandle_, DESIGN_W * 0.5, DESIGN_H * 0.5, DESIGN_W, DESIGN_H, 1.0)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(10, 10, 20, 255))
        nvgFill(vg)
    end

    -- 2. 底部渐变遮罩（底部对齐，裁剪到设计宽度）
    if imgMask_ >= 0 then
        local mw, mh = 1098, 1229
        nvgSave(vg)
        nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        drawImg(vg, imgMask_, DESIGN_W * 0.5, DESIGN_H - mh * 0.5, mw, mh, 1.0)
        nvgRestore(vg)
    end

    -- 3. 文字 "载入中" + 省略号动画
    local dotCount = math.floor(dotTimer_ * 2) % 4  -- 0~3 个点循环
    local dots = string.rep(".", dotCount)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 50)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, 540, 2219, "载入中" .. dots, nil)

    -- 4. 进度条背景
    if imgBarBg_ >= 0 then
        drawImg(vg, imgBarBg_, BAR_CX, BAR_CY, BAR_W, BAR_H, 1.0)
    end

    -- 5. 进度条填充（独立尺寸，居中于 BAR_CX/BAR_CY，用 scissor 裁剪）
    if imgBarFill_ >= 0 and progress_ > 0 then
        local fillX    = BAR_CX - FILL_W * 0.5
        local fillY    = BAR_CY - FILL_H * 0.5
        local fillW    = FILL_W * progress_

        nvgSave(vg)
        nvgScissor(vg, fillX, fillY, fillW, FILL_H)

        local pat = nvgImagePattern(vg, fillX, fillY, FILL_W, FILL_H, 0, imgBarFill_, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, fillX, fillY, FILL_W, FILL_H)
        nvgFillPaint(vg, pat)
        nvgFill(vg)

        nvgRestore(vg)
    end

    -- 6. 网络状态提示文本（进度条下方）
    local statusBaseY = BAR_CY + FILL_H * 0.5 + 30
    if statusText_ ~= "" or tapToRetryCallback_ then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        if tapToRetryCallback_ then
            if statusText_ ~= "" then
                nvgText(vg, 540, statusBaseY, statusText_, nil)
            end
            local blinkAlpha = math.floor(dotTimer_ * 3) % 2 == 0 and 255 or 140
            nvgFillColor(vg, nvgRGBA(255, 220, 100, blinkAlpha))
            nvgText(vg, 540, statusBaseY + (statusText_ ~= "" and 36 or 0), "点击屏幕重试", nil)
        else
            nvgText(vg, 540, statusBaseY, statusText_, nil)
        end
    end

    nvgRestore(vg)
end

--- 是否仍在显示
function LoadingScreen.isOpen()
    return isOpen_
end

--- 检查 Spine 是否不被支持（用于弹窗提醒玩家更新客户端）
---@return boolean true 表示不支持 Spine，需要提醒更新
function LoadingScreen.isSpineNotSupported()
    return spineNotSupported_
end

return LoadingScreen
