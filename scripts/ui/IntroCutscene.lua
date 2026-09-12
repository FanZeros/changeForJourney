-- ============================================================================
-- IntroCutscene.lua — 新手过场动画（6 段时间轴）
-- 仅在首次登录（firstLoginTime == 0）时触发，全屏 NanoVG 覆盖
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local GameConfig = require("config.GameConfig")

local IntroCutscene = {}

-- ======================== 设计常量 ========================
local DW = GameConfig.Design.WIDTH   -- 1080
local DH = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 状态 ========================
local active  = false   -- 是否正在播放
local phase   = 0       -- 当前时间轴阶段 (1-6)
local phaseT  = 0       -- 当前阶段已用时间
local finished = false  -- 是否已完成

-- NanoVG 句柄 / 场景引用（由 init 传入）
local vg_     = nil
local scene_  = nil  -- 用于创建 SoundSource

-- 图片句柄
local imgBG1  = -1   -- JQBJ_1.png
local imgBG2  = -1   -- JQBJ_2.png
-- imgMAP1 已移除：睁眼效果移至 ScenarioDialogue

-- 回调
local onFinishCb = nil

-- ======================== 音效 ========================
local SFX_PATH = "audio/sfx/"
local SFX_DEFS = {
    swordHit1       = SFX_PATH .. "cutscene_sword_hit_1.ogg",
    swordHit2       = SFX_PATH .. "cutscene_sword_hit_2.ogg",
    swordHit3       = SFX_PATH .. "cutscene_sword_hit_3.ogg",
    bodyFall        = SFX_PATH .. "cutscene_body_fall.ogg",
    weakBreathing   = SFX_PATH .. "cutscene_weak_breathing.ogg",
    natureAmbience  = SFX_PATH .. "cutscene_nature_ambience.ogg",
    dialogueBlip    = SFX_PATH .. "dialogue_blip.ogg",
}
---@type table<string, SoundSource>
local sfxSources_ = {}        -- 复用的 SoundSource（循环音效需要引用来停止）
local sfxPlayed_  = {}         -- 一次性音效播放标记，防重复

-- ======================== 眼睛效果参数 ========================
-- "眼皮"效果 — 上下两个黑色矩形模拟眼睑
-- openness: 0 = 完全闭眼(黑屏)，1 = 完全睁开
local eyeOpenness = 0

-- ======================== 时间轴配置 ========================
--[[
  阶段1: 全屏黑屏 (1.5s)
  阶段2: 模拟睁眼 → JQBJ_1 + 文本 (4.0s)
         0~1.0s: 睁眼动画
         1.0~4.0s: 展示
  阶段3: 眨眼2次 → 闭眼 → 黑屏 + 文本 (5.0s)
         0~0.5s: 眨眼1 (闭→开)
         0.5~1.0s: 展示
         1.0~1.5s: 眨眼2 (闭→开)
         1.5~2.0s: 展示
         2.0~2.8s: 闭眼
         2.8~5.0s: 黑屏+文本
  阶段4: 淡入 JQBJ_2 + 文本 (4.0s)
         0~1.0s: 淡入
         1.0~4.0s: 展示
  阶段5: 淡出 → 黑屏 + 文本 (3.5s)
         0~1.0s: 淡出
         1.0~3.5s: 黑屏+文本
  （原阶段6 睁眼效果已移至 ScenarioDialogue）
]]

local PHASE_DURATIONS = {
    [1] = 1.5,
    [2] = 4.0,
    [3] = 7.5,
    [4] = 4.0,
    [5] = 3.5,
}

-- ======================== 辅助 ========================

--- 线性插值
local function lerp(a, b, t)
    return a + (b - a) * math.max(0, math.min(1, t))
end

--- 平滑 ease-in-out
local function easeInOut(t)
    t = math.max(0, math.min(1, t))
    return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2)^2 / 2
end

--- 绘制全屏黑色
local function drawBlack(alpha)
    if alpha <= 0.01 then return end
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, DW, DH)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, math.floor(alpha * 255)))
    nvgFill(vg_)
end

--- 绘制全屏背景图（居中裁剪以覆盖整个设计区域）
local function drawBG(img, alpha)
    if img < 0 or alpha <= 0.01 then return end
    -- 使用 drawImageCentered 以设计分辨率中心绘制
    DrawUtil.drawImageCentered(vg_, img, DW * 0.5, DH * 0.5, DW, DH, alpha)
end

--- 绘制上下"眼皮"遮罩
local function drawEyelids(openness)
    -- openness 0=完全闭合(黑屏), 1=完全睁开
    local halfH = DH * 0.5
    local lidH = halfH * (1 - openness) -- 每侧眼皮高度
    if lidH < 1 then return end

    -- 上眼皮
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, DW, lidH)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, 255))
    nvgFill(vg_)

    -- 下眼皮
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, DH - lidH, DW, lidH)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, 255))
    nvgFill(vg_)
end

--- 绘制白色文本
local function drawText(text, x, y, fontSize)
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, fontSize or 58)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, nvgRGBA(255, 255, 255, 255))
    nvgText(vg_, x, y, text, nil)
end

--- 绘制白色文本（带透明度）
local function drawTextAlpha(text, x, y, fontSize, alpha)
    if alpha <= 0.01 then return end
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, fontSize or 58)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, nvgRGBA(255, 255, 255, math.floor(alpha * 255)))
    nvgText(vg_, x, y, text, nil)
end

-- ======================== 打字机效果 ========================
-- UTF-8 安全的子串截取
local function utf8sub(s, startChar, endChar)
    local sLen = utf8.len(s)
    if not sLen or endChar <= 0 then return "" end
    if endChar > sLen then endChar = sLen end
    local startByte = utf8.offset(s, startChar)
    local endByte   = utf8.offset(s, endChar + 1)
    if not startByte then return "" end
    if endByte then
        return s:sub(startByte, endByte - 1)
    else
        return s:sub(startByte)
    end
end

--- 打字机速度：字/秒
local TYPEWRITER_CPS = 10
--- 打完字后停留时间（秒）
local TEXT_HOLD_DUR  = 0.8
--- 文本淡出时长（秒）
local TEXT_FADE_DUR  = 0.5

--- 绘制打字机文本（逐字出现 → 短暂停留 → 淡出消失）
--- 持续时间 = 打字时间 + 停留 + 淡出，自动计算
--- @param text string 完整文本
--- @param x number 绘制坐标X
--- @param y number 绘制坐标Y
--- @param fontSize number|nil 字号
--- @param elapsed number 从文本开始出现算起经过的时间
--- @param maxDur number|nil 可用的最大时间窗口（超出则压缩停留时间）
local function drawTextTyped(text, x, y, fontSize, elapsed, maxDur)
    if elapsed <= 0 then return end

    local totalChars = utf8.len(text) or 0
    if totalChars == 0 then return end

    -- 计算各阶段时长
    local typingDur = totalChars / TYPEWRITER_CPS
    local totalDur  = typingDur + TEXT_HOLD_DUR + TEXT_FADE_DUR

    -- 如果可用时间不够，压缩停留时间（保证至少淡出）
    if maxDur and totalDur > maxDur then
        totalDur = maxDur
    end

    -- 超出总时长后不再绘制
    if elapsed >= totalDur then return end

    -- 打字机：已显示字符数
    local charsToShow = math.floor(elapsed * TYPEWRITER_CPS)
    if charsToShow > totalChars then charsToShow = totalChars end
    if charsToShow <= 0 then return end

    local visibleText = utf8sub(text, 1, charsToShow)

    -- 透明度
    local alpha = 1.0
    -- 开头渐显（前 0.15s）
    if elapsed < 0.15 then
        alpha = elapsed / 0.15
    end
    -- 末尾淡出
    local fadeStart = totalDur - TEXT_FADE_DUR
    if fadeStart > 0 and elapsed > fadeStart then
        alpha = alpha * (1.0 - easeInOut((elapsed - fadeStart) / TEXT_FADE_DUR))
    end

    drawTextAlpha(visibleText, x, y, fontSize, alpha)
end

-- ======================== 音效辅助 ========================

--- 播放一次性音效（同一 key 在整个过场中只触发一次）
---@param key string SFX_DEFS 的 key
---@param gain number|nil 音量 0~1，默认 1.0
local function playSfxOnce(key, gain)
    if sfxPlayed_[key] then return end
    sfxPlayed_[key] = true
    local path = SFX_DEFS[key]
    if not path then return end
    local snd = cache:GetResource("Sound", path)
    if not snd then
        print("[IntroCutscene] sfx not found: " .. path)
        return
    end
    local src = scene_:CreateComponent("SoundSource")
    src.soundType = SOUND_EFFECT
    src.gain = gain or 1.0
    src:Play(snd)
    sfxSources_[key] = src
end

--- 播放循环音效
---@param key string
---@param gain number|nil
local function playSfxLoop(key, gain)
    if sfxSources_[key] then return end  -- 已在播放
    local path = SFX_DEFS[key]
    if not path then return end
    local snd = cache:GetResource("Sound", path)
    if not snd then return end
    snd.looped = true
    local src = scene_:CreateComponent("SoundSource")
    src.soundType = SOUND_EFFECT
    src.gain = gain or 1.0
    src:Play(snd)
    sfxSources_[key] = src
end

--- 停止指定循环音效
---@param key string
local function stopSfx(key)
    local src = sfxSources_[key]
    if src then
        src:Stop()
        src:Remove()
        sfxSources_[key] = nil
    end
end

--- 设置音效音量（用于淡入淡出）
---@param key string
---@param gain number
local function setSfxGain(key, gain)
    local src = sfxSources_[key]
    if src then src.gain = gain end
end

--- 判断 UTF-8 字符是否为中文（CJK 统一汉字）
local function isChinese(char)
    if not char or char == "" then return false end
    local ok, cp = pcall(utf8.codepoint, char)
    if not ok then return false end
    return (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF)
end

--- 播放打字机 blip 音效（每个字符触发一次，可快速重复）
local function playBlip()
    local path = SFX_DEFS.dialogueBlip
    if not path then return end
    local snd = cache:GetResource("Sound", path)
    if not snd then return end
    local src = scene_:CreateComponent("SoundSource")
    src.soundType = SOUND_EFFECT
    src.gain = 0.5
    src:Play(snd)
    -- 播放完毕后自动清理不做特别处理，短音效会自然结束
end

--- 停止所有音效并清理
local function stopAllSfx()
    for k, src in pairs(sfxSources_) do
        if src then
            src:Stop()
            src:Remove()
        end
    end
    sfxSources_ = {}
    sfxPlayed_  = {}
end

-- ======================== 各阶段更新 & 绘制 ========================

--- 阶段1: 全屏黑屏
local function updatePhase1(dt)
    -- 纯黑屏等待
end

local function drawPhase1()
    drawBlack(1.0)
end

--- 阶段2: 睁眼 → JQBJ_1 + 文本 + 剑击抖动
-- 抖动效果参数
local shakeX = 0
local shakeY = 0
local shakeIntensity = 0  -- 当前抖动强度（用于判断是否应用偏移）

-- 多次剑击冲击：时间、强度、衰减速率、初始冲击方向
local SHAKE_IMPACTS = {
    { time = 0.7,  intensity = 28, decay = 0.15, dirX =  0.8, dirY = -0.6  },  -- 第一击，最猛
    { time = 1.5,  intensity = 20, decay = 0.13, dirX = -0.7, dirY = -0.7  },  -- 第二击，稍弱
    { time = 2.2,  intensity = 12, decay = 0.10, dirX =  0.5, dirY = -0.85 },  -- 第三击，余波
}

local function updatePhase2(dt)
    if phaseT < 1.0 then
        -- 0~1s: 缓缓睁眼
        eyeOpenness = easeInOut(phaseT / 1.0)
    else
        eyeOpenness = 1.0
    end

    -- 剑击音效：与抖动冲击同步
    if phaseT >= 0.7 then playSfxOnce("swordHit1", 1.0) end
    if phaseT >= 1.5 then playSfxOnce("swordHit2", 0.85) end
    if phaseT >= 2.2 then playSfxOnce("swordHit3", 0.6) end

    -- 多次剑击抖动：叠加所有已触发冲击的贡献
    shakeX = 0
    shakeY = 0
    shakeIntensity = 0
    for _, impact in ipairs(SHAKE_IMPACTS) do
        if phaseT >= impact.time then
            local st = phaseT - impact.time
            local amp = impact.intensity * math.exp(-st / impact.decay)
            if amp > 0.5 then
                if st < 0.03 then
                    -- 初始冲击：固定方向猛位移
                    shakeX = shakeX + amp * impact.dirX
                    shakeY = shakeY + amp * impact.dirY
                else
                    -- 衰减振动：高频→低频
                    local freq = 18 * math.exp(-st / 0.3)
                    shakeX = shakeX + math.sin(st * freq * 2.0 * math.pi) * amp
                    shakeY = shakeY + math.cos(st * freq * 2.7 * math.pi) * amp * 0.7
                end
                shakeIntensity = shakeIntensity + amp
            end
        end
    end
end

local function drawPhase2()
    -- 绘制背景（带抖动偏移）
    if shakeIntensity > 0.5 then
        nvgSave(vg_)
        nvgTranslate(vg_, shakeX, shakeY)
        drawBG(imgBG1, 1.0)
        nvgRestore(vg_)
    else
        drawBG(imgBG1, 1.0)
    end

    -- 文本：打字机效果 + 淡出
    local TEXT_START = 0.8
    local AVAIL      = PHASE_DURATIONS[2] - TEXT_START  -- 可用时间窗口

    local line1 = "这就是……宿命吗？"
    local line2 = "我终究……还是倒在这里了吗"
    local line1TypingDur = (utf8.len(line1) or 0) / TYPEWRITER_CPS
    -- 第二行在第一行打完后 0.3s 开始
    local line2Delay = line1TypingDur + 0.3

    if phaseT >= TEXT_START then
        local textElapsed = phaseT - TEXT_START
        drawTextTyped(line1, 540, 1150, 58, textElapsed, AVAIL)
        drawTextTyped(line2, 540, 1250, 58, textElapsed - line2Delay, AVAIL - line2Delay)
    end

    -- 眼皮遮罩
    drawEyelids(eyeOpenness)
end

--- 阶段3: 濒死眨眼 → 视线模糊 → 闭眼 → 黑屏 + 文本
-- 虚弱效果参数
local phase3Blur     = 0   -- 模糊程度 (0=清晰, 1=极度模糊)
local phase3Darkness = 0   -- 暗化程度 (0=正常, 1=全黑)

local function updatePhase3(dt)
    local t = phaseT

    -- 音效：倒地 + 闷哼
    if t >= 0.1 then playSfxOnce("bodyFall", 0.9) end
    if t >= 0.6 then playSfxOnce("weakBreathing", 0.8) end

    -- 眼皮颤抖：阻尼正弦波，模拟濒死者无力控制眼皮
    local function tremor(amp)
        return math.sin(t * 16) * amp
    end

    --[[
      时间轴（总 5.0s）:
      0.00~0.30  眨眼1闭合（尚有力气，闭合较快）
      0.30~1.00  眨眼1睁开（费力，缓慢，带颤抖，仅到0.6）
      1.00~1.60  维持/下坠（肌肉疲劳，0.6慢慢滑向0.45，微颤）
      1.60~2.00  眨眼2闭合（更慢更无力）
      2.00~2.90  眨眼2睁开（极度费力，颤抖明显，仅到0.25）
      2.90~3.40  维持/下坠（几乎撑不住，0.25滑向0.12，细微抽动）
      3.40~4.20  最终闭合（极缓，中途有一次微弱挣扎抽动）
      4.20~5.00  完全闭眼，黑屏，文字淡入
    ]]

    if t < 0.30 then
        ---- 眨眼1: 闭合 ----
        eyeOpenness  = lerp(1.0, 0.02, easeInOut(t / 0.30))
        phase3Blur   = lerp(0, 0.12, t / 0.30)

    elseif t < 1.00 then
        ---- 眨眼1: 费力睁开 ----
        local prog = (t - 0.30) / 0.70
        -- ease-out: 一开始稍快（挣扎发力），后面越来越慢（力竭）
        local ease = 1 - (1 - prog) * (1 - prog)
        local base = lerp(0.02, 0.60, ease)
        eyeOpenness  = base + tremor(0.04 * (1 - prog))
        phase3Blur   = lerp(0.12, 0.25, ease)
        phase3Darkness = lerp(0, 0.12, ease)

    elseif t < 1.60 then
        ---- 维持/下坠: 睁着但撑不住，缓慢滑落 ----
        local prog = (t - 1.00) / 0.60
        local base = lerp(0.60, 0.45, easeInOut(prog))
        eyeOpenness  = base + tremor(0.025)
        phase3Blur   = lerp(0.25, 0.32, prog)
        phase3Darkness = lerp(0.12, 0.18, prog)

    elseif t < 2.00 then
        ---- 眨眼2: 闭合（更慢） ----
        local prog = easeInOut((t - 1.60) / 0.40)
        eyeOpenness  = lerp(0.45, 0.02, prog)
        phase3Blur   = lerp(0.32, 0.45, prog)
        phase3Darkness = lerp(0.18, 0.25, prog)

    elseif t < 2.90 then
        ---- 眨眼2: 极度费力睁开，大量颤抖 ----
        local prog = (t - 2.00) / 0.90
        -- 更强的 ease-out，几乎打不开
        local ease = 1 - (1 - prog)^3
        local base = lerp(0.02, 0.25, ease)
        -- 颤抖更剧烈，随着睁开逐渐减弱
        eyeOpenness  = math.max(0, base + tremor(0.05 * (1 - prog)))
        phase3Blur   = lerp(0.45, 0.60, ease)
        phase3Darkness = lerp(0.25, 0.38, ease)

    elseif t < 3.40 then
        ---- 维持/下坠: 几乎撑不住 ----
        local prog = (t - 2.90) / 0.50
        local base = lerp(0.25, 0.12, easeInOut(prog))
        -- 细微抽动
        eyeOpenness  = math.max(0, base + tremor(0.015))
        phase3Blur   = lerp(0.60, 0.72, prog)
        phase3Darkness = lerp(0.38, 0.48, prog)

    elseif t < 4.20 then
        ---- 最终闭合: 极缓，中途有一次微弱的挣扎 ----
        local prog = (t - 3.40) / 0.80
        local base = lerp(0.12, 0, easeInOut(prog))
        -- 在约 40% 进度时有一次微弱的抽动（垂死挣扎）
        local flutter = 0
        if prog > 0.35 and prog < 0.55 then
            flutter = math.sin((prog - 0.35) / 0.20 * math.pi) * 0.07
        end
        eyeOpenness  = math.max(0, base + flutter)
        phase3Blur   = lerp(0.72, 1.0, prog)
        phase3Darkness = lerp(0.48, 0.85, prog)

    else
        ---- 完全闭眼 ----
        eyeOpenness  = 0
        phase3Blur   = 1.0
        phase3Darkness = 1.0
    end
end

--- 绘制模糊背景：多次偏移叠加模拟失焦
local function drawBGBlurred(img, blur)
    if img < 0 then return end
    if blur <= 0.02 then
        drawBG(img, 1.0)
        return
    end

    -- 底层：原图
    drawBG(img, 1.0)

    -- 叠加 8 个方向的偏移副本模拟散焦
    local offset    = blur * 22        -- 最大偏移像素
    local copyAlpha = blur * 0.13      -- 每份副本透明度
    local dirs = {
        { 1, 0}, {-1,  0}, {0,  1}, { 0, -1},
        { 0.71, 0.71}, {-0.71, 0.71}, {0.71, -0.71}, {-0.71, -0.71},
    }
    for _, d in ipairs(dirs) do
        nvgSave(vg_)
        nvgTranslate(vg_, d[1] * offset, d[2] * offset)
        DrawUtil.drawImageCentered(vg_, img, DW * 0.5, DH * 0.5, DW, DH, copyAlpha)
        nvgRestore(vg_)
    end
end

--- 绘制暗角效果（隧道视野）
local function drawVignette(intensity)
    if intensity <= 0.01 then return end
    local cx, cy = DW * 0.5, DH * 0.5
    local radius = math.max(DW, DH) * 0.6
    local innerR = radius * (1.0 - intensity * 0.6)

    local paint = nvgRadialGradient(vg_, cx, cy, innerR, radius,
        nvgRGBA(0, 0, 0, 0),
        nvgRGBA(0, 0, 0, math.floor(intensity * 220)))
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, DW, DH)
    nvgFillPaint(vg_, paint)
    nvgFill(vg_)
end

local function drawPhase3()
    -- 模糊背景
    drawBGBlurred(imgBG1, phase3Blur)

    -- 暗化叠加（模拟视线变暗）
    drawBlack(phase3Darkness * 0.5)

    -- 暗角（隧道视野）
    drawVignette(phase3Darkness)

    -- 眼皮遮罩
    drawEyelids(eyeOpenness)

    -- 完全闭眼后文本：打字机 + 淡出 (4.2s 后)
    if phaseT >= 4.2 then
        local textElapsed = phaseT - 4.2
        local maxDur = PHASE_DURATIONS[3] - 4.2  -- 可用 3.3s
        drawTextTyped("一切的轮回，再次开始了么……", 540, 1200, 58, textElapsed, maxDur)
    end
end

--- 阶段4: 淡入 JQBJ_2 + 文本
local bgFadeAlpha4 = 0

local function updatePhase4(dt)
    local t = phaseT

    -- 自然环境音：森林鸟鸣渐入
    if t >= 0.3 then
        playSfxLoop("natureAmbience", 0.0)
        -- 0.3s~1.3s 渐入到 0.5
        local fadeIn = math.min(1.0, (t - 0.3) / 1.0)
        setSfxGain("natureAmbience", fadeIn * 0.5)
    end

    if t < 1.0 then
        bgFadeAlpha4 = easeInOut(t / 1.0)
    else
        bgFadeAlpha4 = 1.0
    end
    eyeOpenness = 1.0  -- 此阶段眼睛全开
end

local function drawPhase4()
    -- 先画黑底
    drawBlack(1.0)
    -- 淡入 JQBJ_2
    drawBG(imgBG2, bgFadeAlpha4)

    -- 文本：打字机 + 淡出
    if phaseT >= 0.8 then
        local textElapsed = phaseT - 0.8
        local maxDur = PHASE_DURATIONS[4] - 0.8  -- 可用 3.2s
        drawTextTyped("不知能否斩断宿命，挣脱轮回呢……", 540, 1200, 58, textElapsed, maxDur)
    end
end

--- 阶段5: 淡出 → 黑屏 + 文本
local bgFadeAlpha5 = 1.0
local phase5PrevChars_ = 0   -- 上一帧已显示字符数，用于检测新字符触发 blip
local PHASE5_TEXT = "团长！团长！"
local PHASE5_TEXT_LEN = utf8.len(PHASE5_TEXT) or 0

local function updatePhase5(dt)
    local t = phaseT

    -- 打字机 blip 音效：仅中文字符触发
    if t >= 1.0 then
        local textElapsed = t - 1.0
        local charsNow = math.floor(textElapsed * TYPEWRITER_CPS)
        if charsNow > PHASE5_TEXT_LEN then charsNow = PHASE5_TEXT_LEN end
        if charsNow > phase5PrevChars_ then
            local ch = utf8sub(PHASE5_TEXT, charsNow, charsNow)
            if isChinese(ch) then
                playBlip()
            end
            phase5PrevChars_ = charsNow
        end
    end

    -- 环境音渐出
    if t >= 1.5 then
        local fadeOut = math.min(1.0, (t - 1.5) / 1.5)
        setSfxGain("natureAmbience", 0.5 * math.max(0, 1.0 - fadeOut))
    end
    -- 过场结束前停止环境音
    if t >= 3.0 then stopSfx("natureAmbience") end

    if t < 1.0 then
        bgFadeAlpha5 = 1.0 - easeInOut(t / 1.0)
    else
        bgFadeAlpha5 = 0
    end
end

local function drawPhase5()
    -- 黑底
    drawBlack(1.0)
    -- 淡出 JQBJ_2
    drawBG(imgBG2, bgFadeAlpha5)

    -- 文本：打字机 + 淡出 (淡出后出现)
    if phaseT >= 1.0 then
        local textElapsed = phaseT - 1.0
        local maxDur = PHASE_DURATIONS[5] - 1.0  -- 可用 2.5s
        drawTextTyped("团长！团长！", 540, 1150, 58, textElapsed, maxDur)
    end
end

-- ======================== 阶段调度表 ========================
local phaseUpdaters = {
    updatePhase1, updatePhase2, updatePhase3,
    updatePhase4, updatePhase5,
}

local phaseDrawers = {
    drawPhase1, drawPhase2, drawPhase3,
    drawPhase4, drawPhase5,
}

-- ======================== 公开接口 ========================

--- 初始化（加载图片资源）
---@param vg any NanoVG context
---@param sceneRef Scene 场景引用，用于创建 SoundSource
function IntroCutscene.init(vg, sceneRef)
    vg_ = vg
    scene_ = sceneRef
    imgBG1 = nvgCreateImage(vg, "image/JQBJ_1.png", 0)
    imgBG2 = nvgCreateImage(vg, "image/JQBJ_2.png", 0)
    print("[IntroCutscene] init: BG1=" .. imgBG1 .. " BG2=" .. imgBG2)
end

--- 开始播放过场动画
---@param onFinish function|nil 播放完成后的回调
function IntroCutscene.start(onFinish)
    active = true
    finished = false
    phase = 1
    phaseT = 0
    eyeOpenness = 0
    phase3Blur = 0
    phase3Darkness = 0
    bgFadeAlpha4 = 0
    bgFadeAlpha5 = 1.0
    shakeX = 0
    shakeY = 0
    shakeIntensity = 0
    phase5PrevChars_ = 0
    stopAllSfx()  -- 重置音效状态
    onFinishCb = onFinish
    print("[IntroCutscene] started")
end

--- 是否正在播放
function IntroCutscene.isActive()
    return active
end

--- 是否已完成
function IntroCutscene.isFinished()
    return finished
end

--- 每帧更新
function IntroCutscene.update(dt)
    if not active then return end

    phaseT = phaseT + dt

    -- 执行当前阶段更新
    local updater = phaseUpdaters[phase]
    if updater then updater(dt) end

    -- 检查阶段是否结束
    local dur = PHASE_DURATIONS[phase]
    if dur and phaseT >= dur then
        phase = phase + 1
        phaseT = 0

        if phase > 5 then
            -- 全部阶段完成
            active = false
            finished = true
            print("[IntroCutscene] finished all phases")
            if onFinishCb then
                onFinishCb()
                onFinishCb = nil
            end
        else
            print("[IntroCutscene] entering phase " .. phase)
        end
    end
end

--- 绘制（在 NanoVGRender 中调用）
function IntroCutscene.draw(vg)
    if not active then return end

    -- 裁剪到设计分辨率区域，防止图片/抖动超出边界
    nvgSave(vg_)
    nvgScissor(vg_, 0, 0, DW, DH)

    -- 先画一个全屏黑底作为安全底色
    drawBlack(1.0)

    -- 绘制当前阶段
    local drawer = phaseDrawers[phase]
    if drawer then drawer() end

    nvgResetScissor(vg_)
    nvgRestore(vg_)
end

--- 跳过（调试用，可用于点击跳过）
function IntroCutscene.skip()
    if not active then return end
    stopAllSfx()  -- 跳过时立即停止所有音效
    active = false
    finished = true
    print("[IntroCutscene] skipped")
    if onFinishCb then
        onFinishCb()
        onFinishCb = nil
    end
end

--- 重置状态（清除存档后需要调用，让开场动画可以重新触发）
function IntroCutscene.reset()
    active   = false
    finished = false
    phase    = 0
    phaseT   = 0
    onFinishCb = nil
    sfxPlayed_ = {}
    stopAllSfx()
    print("[IntroCutscene] reset – ready for replay")
end

return IntroCutscene
