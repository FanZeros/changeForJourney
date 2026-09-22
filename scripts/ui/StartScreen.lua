-- ============================================================================
-- StartScreen  - 开始游戏界面
-- 静态背景图 + LOGO + 开始游戏按钮，点击任意位置进入游戏
-- ============================================================================

local GameConfig         = require("config.GameConfig")

local StartScreen = {}

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ── 资源句柄 ──
local vg_          = nil
local imgLogo_     = -1
local imgGlow_     = -1
local imgDeco_     = -1
local imgMask_     = -1                -- 底部渐变遮罩
local imgBgFallback_ = -1             -- 静态背景图

-- ── BGM ──
local bgmNode_     = nil   ---@type Node
local bgmSource_   = nil   ---@type SoundSource
local BGM_PATH       = "audio/bgm_title.ogg"
local BGM_VOLUME     = 0.6
local BGM_SPEED      = 1.0   -- 播放速度倍率（1.0 = 原速）

-- ── 状态 ──
local isOpen_     = true
local fadeOut_    = false
local fadeAlpha_  = 1.0
local glowTimer_  = 0   -- 发光呼吸动画计时
local bgmStarted_ = false  -- BGM 是否已开始播放（延迟到首帧）
local bgmDelayTimer_ = nil -- draw 首帧后开始计时，达到 0.6 秒才播放

-- ── 回调 ──
local onStartCallback_        = nil

-- ── 工具函数 ──
local function drawImg(vg, img, cx, cy, w, h, alpha)
    local paint = nvgImagePattern(vg, cx - w * 0.5, cy - h * 0.5, w, h, 0, img, alpha or 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, cx - w * 0.5, cy - h * 0.5, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

local function startGame()
    fadeOut_ = true
    print("[StartScreen] start game")
    return true
end


-- ============================================================================
-- Public API
-- ============================================================================

--- 初始化（在 NanoVG 上下文创建后调用）
---@param nvgCtx userdata
---@param scene Scene|nil  传入场景用于播放 BGM（可选）
function StartScreen.init(nvgCtx, scene)
    vg_ = nvgCtx

    -- 加载图片
    imgLogo_ = nvgCreateImage(vg_, "image/界面底板/标题与加载/UI_LOGO_TM.png", 0)
    imgGlow_ = nvgCreateImage(vg_, "image/界面底板/标题与加载/UI_KSYXFG.png", 0)
    imgDeco_ = nvgCreateImage(vg_, "image/界面底板/标题与加载/UI_KSYXJT.png", 0)

    -- 底部渐变遮罩（与加载界面相同）
    imgMask_ = nvgCreateImage(vg_, "image/界面底板/标题与加载/UI_ZRJM_HD.png", 0)

    -- 视频首帧静态图（视频解码就绪前的fallback，避免黑屏闪烁）
    imgBgFallback_ = nvgCreateImage(vg_, "image/界面底板/标题与加载/UI_DLJMBJ_FRAME1.jpg", 0)

    -- BGM（预加载资源，延迟到首次 update 时播放，避免初始化期间音乐空转）
    if scene then
        local snd = cache:GetResource("Sound", BGM_PATH)
        if snd then
            snd.looped = true
            bgmNode_ = scene:CreateChild("StartScreenBGM", LOCAL)
            bgmSource_ = bgmNode_:CreateComponent("SoundSource")
            bgmSource_.soundType = "Music"
            bgmSource_.gain = 0  -- 初始静音，update 时再淡入
            bgmStarted_ = false
        end
    end
end

--- 设置点击"开始游戏后的回调
function StartScreen.setOnStart(fn)
    onStartCallback_ = fn
end

--- 每帧更新
function StartScreen.update(dt)
    if not isOpen_ then return end

    -- BGM 延迟播放计时（draw 首帧触发后开始倒计时）
    if not bgmStarted_ and bgmDelayTimer_ and bgmSource_ then
        bgmDelayTimer_ = bgmDelayTimer_ + dt
        if bgmDelayTimer_ >= 0.6 then
            local snd = cache:GetResource("Sound", BGM_PATH)
            if snd then
                bgmSource_:Play(snd)
                bgmSource_.frequency = snd:GetFrequency() * BGM_SPEED
                bgmSource_.gain = BGM_VOLUME
                bgmStarted_ = true
            end
        end
    end

    -- 发光呼吸计时
    glowTimer_ = glowTimer_ + dt

    -- 淡出过渡
    if fadeOut_ then
        fadeAlpha_ = fadeAlpha_ - dt * 2.0  -- 0.5 秒淡出
        if fadeAlpha_ <= 0 then
            fadeAlpha_ = 0
            isOpen_ = false
            fadeOut_ = false
            local bn = bgmNode_
            local bs = bgmSource_
            bgmNode_ = nil
            bgmSource_ = nil
            -- 触发回调，传递 BGM 资源
            if onStartCallback_ then
                onStartCallback_(bs, bn)
            end
        end
    end
end

--- 绘制（在设计空间 1080×2400 内调用）
function StartScreen.draw(vg)
    if not isOpen_ then return end

    nvgSave(vg)

    -- 1. 静态背景图
    if imgBgFallback_ >= 0 then
        drawImg(vg, imgBgFallback_, DESIGN_W * 0.5, DESIGN_H * 0.5, DESIGN_W, DESIGN_H, 1.0)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(10, 10, 20, 255))
        nvgFill(vg)
    end

    -- 1.5 底部渐变遮罩（与加载界面相同，底部对齐，裁剪到设计宽度）
    if imgMask_ >= 0 then
        local mw, mh = 1098, 1229
        nvgSave(vg)
        nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        drawImg(vg, imgMask_, DESIGN_W * 0.5, DESIGN_H - mh * 0.5, mw, mh, 1.0)
        nvgRestore(vg)
    end

    -- 淡出仅作用于 UI 叠加元素（LOGO、发光、文字），静态背景保持全屏
    if fadeOut_ then
        nvgGlobalAlpha(vg, math.max(fadeAlpha_, 0))
    end

    -- 2. LOGO  (cx=537 cy=424 874×545) / 上下浮动动画
    if imgLogo_ >= 0 then
        local logoFloat = math.sin(glowTimer_ * 1.2) * 12  -- 幅度12px，周期约5.2秒
        -- LOGO 透明画布 1920×1080：等比缩放至宽度 1080（高 607），保持构图
        drawImg(vg, imgLogo_, 540, 403 + logoFloat, 1080, 607, 1.0)
    end

    -- 3. 开始游戏背景光 (cx=540 cy=2002 1057×317)  呼吸闪烁
    if imgGlow_ >= 0 then
        local glowAlpha = 0.7 + 0.3 * math.sin(glowTimer_ * 2.0)
        drawImg(vg, imgGlow_, 540, 2002, 1057, 317, glowAlpha)
    end

    -- 4. 装饰点(cx=340 cy=2002 152×44) / 向左漂浮
    if imgDeco_ >= 0 then
        local driftL = math.sin(glowTimer_ * 1.8) * 8
        drawImg(vg, imgDeco_, 340 - driftL, 2002, 152, 44, 1.0)
    end

    -- 5. 装饰点(cx=739 cy=2002 152×44 旋转180°) / 向右漂浮
    if imgDeco_ >= 0 then
        local driftR = math.sin(glowTimer_ * 1.8) * 8
        nvgSave(vg)
        nvgTranslate(vg, 739 + driftR, 2002)
        nvgRotate(vg, math.pi)
        local paint = nvgImagePattern(vg, -76, -22, 152, 44, 0, imgDeco_, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, -76, -22, 152, 44)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 6. 文字"开始游戏 (cx=540 cy=2001 字号50 纯白)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 50)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, 540, 2001, "开始游戏", nil)

    -- 7. 防沉迷提示文字(cx=540 cy=2186 字号30 纯白 黑色描边5)
    do
        local line1 = "抵制不良游戏，拒绝盗版游戏。注意自我保护，谨防受骗上当"
        local line2 = "适度游戏益脑，沉迷游戏伤身。合理安排时间，享受健康生活"
        local lineH = 38  -- 行间距
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 描边（纯黑，宽度5）
        nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgStrokeWidth(vg, 5)
        nvgFontBlur(vg, 0)
        nvgTextLetterSpacing(vg, 0)
        -- 用 strokeText 模拟描边：先画黑色文字作为底层描边
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        for ox = -2, 2 do
            for oy = -2, 2 do
                if ox ~= 0 or oy ~= 0 then
                    nvgText(vg, 540 + ox, 2186 - lineH * 0.5 + oy, line1, nil)
                    nvgText(vg, 540 + ox, 2186 + lineH * 0.5 + oy, line2, nil)
                end
            end
        end
        -- 纯白填充
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, 540, 2186 - lineH * 0.5, line1, nil)
        nvgText(vg, 540, 2186 + lineH * 0.5, line2, nil)
    end

    -- 8. 版本号（防沉迷文字下方居中）
    do
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 26)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 153))
        local VersionConfig = require("shared.VersionConfig")
        nvgText(vg, 540, 2377, "V" .. VersionConfig.CURRENT, nil)
    end

    nvgRestore(vg)

    -- 首帧绘制后开始计时，延迟 1.5 秒再播放 BGM
    if not bgmStarted_ and bgmSource_ then
        if not bgmDelayTimer_ then
            bgmDelayTimer_ = 0
        end
    end
end

--- 处理点击（设计坐标），返回 true 表示已消费
function StartScreen.handleClick(dx, dy)
    if not isOpen_ or fadeOut_ then return false end
    return startGame()
end

--- 处理滚轮（设计坐标），返回 true 表示已消费
function StartScreen.handleScroll(...)
    return false
end

--- 拖拽开始转发
function StartScreen.handleDragBegin(...)
    return false
end

--- 拖拽移动转发
function StartScreen.handleDragMove(...)
    return false
end

--- 拖拽结束转发
function StartScreen.handleDragEnd(...)
    return false
end

--- 是否仍在显示
function StartScreen.isOpen()
    return isOpen_
end

--- 重连/横屏路径强制跳过开始界面（不走淡出动画，直接关闭并触发回调）
function StartScreen.skipForReconnect()
    if not isOpen_ then return end

    isOpen_   = false
    fadeOut_  = false
    fadeAlpha_ = 0

    -- 传递 BGM 资源给后续界面
    local bn = bgmNode_
    local bs = bgmSource_
    bgmNode_     = nil
    bgmSource_   = nil

    if onStartCallback_ then
        onStartCallback_(bs, bn)
    end

    print("[StartScreen] skipped for reconnect")
end

--- 重新打开开始界面（清除存档后调用）
--- 重置内部状态并重新创建 BGM
---@param scene Scene 场景节点（用于创建 BGM）
function StartScreen.reopen(scene)
    -- 重置状态
    isOpen_    = true
    fadeOut_   = false
    fadeAlpha_ = 1.0
    glowTimer_ = 0
    -- 重新创建 BGM（延迟到首次 update 时播放）
    if scene then
        local snd = cache:GetResource("Sound", BGM_PATH)
        if snd then
            snd.looped = true
            bgmNode_ = scene:CreateChild("StartScreenBGM", LOCAL)
            bgmSource_ = bgmNode_:CreateComponent("SoundSource")
            bgmSource_.soundType = "Music"
            bgmSource_.gain = 0
            bgmStarted_ = false
            bgmDelayTimer_ = nil
        end
    end

    print("[StartScreen] reopened")
end

return StartScreen
