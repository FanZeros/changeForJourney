-- ============================================================================
-- ScenarioDialogue.lua — 情景对话底层框架
-- 支持两种模板：大情景（全屏覆盖）和 小情景（弹窗对话）
-- 设计为可复用底层，由外部调用 show() 驱动对话流程
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local GameConfig = require("config.GameConfig")

local ScenarioDialogue = {}

-- ======================== 设计常量 ========================
local DW = GameConfig.Design.WIDTH   -- 1080
local DH = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 模板布局参数 ========================

--- 大/小模板共享 UI 元素
local COMMON = {
    -- 文本背景：UI_QJDH_BJ1.png, 1080×668, X540, Y底部对齐
    textBG   = { cx = 540, cy = DH - 668 * 0.5, w = 1080, h = 668 },
    -- 角色名背景：UI_QJDH_1.png, X290 Y1913, 370×70
    nameBG   = { cx = 290, cy = 1913, w = 370, h = 70 },
    -- 角色名文本：X290 Y1892, 字号56, 纯白, 描边#312424 大小6
    nameText = { cx = 290, cy = 1892, fontSize = 56,
                 color = { 255, 255, 255 },
                 strokeColor = { 0x31, 0x24, 0x24 }, strokeSize = 6 },
    -- 对话文本区域：X547 Y2172, 879×322, 字号48, 颜色#5f3737, 上左对齐
    textArea = { cx = 547, cy = 2172, w = 879, h = 322,
                 fontSize = 48, color = { 0x5f, 0x37, 0x37 } },
    -- 箭头：ICON_SJX, X947 Y2312, 48×43
    arrow    = { cx = 947, cy = 2312, w = 48, h = 43 },
}

--- 大情景立绘参数：X440 Y1253, 2359×1545
local PORTRAIT_LARGE = { cx = 540, cy = 1209.50, w = 2359, h = 1545 }

--- 小情景立绘参数：X275 Y1546, 1464×960（按大情景 ×1.1795 等比缩放）
local PORTRAIT_SMALL = { cx = 275, cy = 1546, w = 1464, h = 960 }

-- ======================== 打字机参数 ========================
local TYPEWRITER_CPS     = 10    -- 字/秒
local ARROW_BLINK_SPEED  = 1.2   -- 箭头闪烁频率 (Hz)
local ARROW_BOUNCE_AMP   = 4     -- 箭头弹跳幅度 (px)
local ARROW_BOUNCE_SPEED = 3.0   -- 箭头弹跳频率 (rad/s)
local TEXT_LINE_HEIGHT    = 1.4   -- 文本行高倍数

-- ======================== 立绘动画参数 ========================
local PORTRAIT_ANIM_DUR   = 0.25   -- 单阶段动画时长 (秒)
local PORTRAIT_SLIDE_DIST = 150    -- 滑动距离 (设计像素)

-- ======================== 睁眼入场参数 ========================
local EYE_OPEN_DUR = 2.0   -- 睁眼动画时长 (秒)

-- ======================== 打字机音效 ========================
local BLIP_SFX_PATH = "audio/sfx/dialogue_blip.ogg"

-- ======================== 内部状态 ========================
local vg_         = nil
local scene_      = nil   -- 场景引用，用于创建 SoundSource
local active_     = false

-- 对话配置
local mode_       = "large"     -- "large" | "small"
local steps_      = {}          -- { {characterId, name, text}, ... }
local stepIndex_  = 0
local onFinishCb_ = nil

-- 当前步骤的打字机状态
local textElapsed_ = 0
local typingDone_  = false
local totalChars_  = 0
local prevCharsShown_ = 0  -- 上一帧已显示字符数，用于检测新字符触发 blip

-- 图片句柄
local imgTextBG_  = -1   -- UI_QJDH_BJ1.png
local imgNameBG_  = -1   -- UI_QJDH_1.png
local imgArrow_   = -1   -- ICON_SJX.png
local imgBG_      = -1   -- 大情景全屏背景图

--- 立绘缓存: [characterId] = nvgImage handle
local portraitCache_ = {}

-- 立绘动画状态
local portraitAnimState_ = "idle"    -- "idle" | "exiting" | "entering"
local portraitAnimT_     = 0
local exitCharId_        = nil       -- 正在退出的角色 ID

-- 睁眼入场状态
local eyeOpenActive_   = false   -- 是否正在播放睁眼动画
local eyeOpenT_        = 0       -- 睁眼计时器
local eyeOpenness_     = 0       -- 0=完全闭眼, 1=完全睁开

-- 消失动画状态（小情景用）
local dismissing_      = false   -- 是否正在播放消失动画
local dismissT_        = 0       -- 消失动画计时器
local DISMISS_DUR      = 0.3     -- 消失动画时长 (秒)
local DISMISS_SLIDE    = 80      -- 下滑距离 (设计像素)

-- ======================== UTF-8 工具 ========================

--- UTF-8 安全子串截取
---@param s string
---@param startChar number 起始字符位置 (1-based)
---@param endChar number   结束字符位置 (含)
---@return string
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

--- 判断 UTF-8 字符是否为中文（CJK 统一汉字）
local function isChinese(char)
    if not char or char == "" then return false end
    local ok, cp = pcall(utf8.codepoint, char)
    if not ok then return false end
    return (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF)
end

--- 播放打字机 blip 音效
local function playBlip()
    if not scene_ then return end
    local snd = cache:GetResource("Sound", BLIP_SFX_PATH)
    if not snd then return end
    local src = scene_:CreateComponent("SoundSource")
    src.soundType = SOUND_EFFECT
    src.gain = 0.5
    src:Play(snd)
end

-- ======================== 缓动函数 ========================

local function easeOutCubic(t)
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t) ^ 3
end

local function easeInCubic(t)
    t = math.max(0, math.min(1, t))
    return t ^ 3
end

local function easeInOut(t)
    t = math.max(0, math.min(1, t))
    return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
end

-- ======================== 内部绘制辅助 ========================

--- 按需加载并缓存角色立绘
---@param characterId number
---@return number nvgImage handle
local function getPortraitImage(characterId)
    if not characterId then return -1 end
    local cached = portraitCache_[characterId]
    if cached then return cached end

    local path = string.format("image/角色立绘/UI_DLH_%d.png", characterId)
    local handle = nvgCreateImage(vg_, path, 0)
    portraitCache_[characterId] = handle
    print("[ScenarioDialogue] loadPortrait: id=" .. characterId .. " handle=" .. handle)
    return handle
end

--- 获取当前模板的立绘布局参数
---@return table {cx, cy, w, h}
local function getPortraitLayout()
    return mode_ == "small" and PORTRAIT_SMALL or PORTRAIT_LARGE
end

--- 绘制角色立绘（带水平偏移和透明度）
---@param characterId number
---@param alpha number 0~1
---@param offsetX number|nil 水平偏移 (设计像素)
local function drawPortrait(characterId, alpha, offsetX)
    if not characterId or alpha <= 0.01 then return end
    local img = getPortraitImage(characterId)
    if img < 0 then return end

    local p = getPortraitLayout()
    local cx = p.cx + (offsetX or 0)
    DrawUtil.drawImageCentered(vg_, img, cx, p.cy, p.w, p.h, alpha)
end

--- 绘制带动画的立绘
---@param characterId number 当前步骤的角色 ID
local function drawPortraitAnimated(characterId)
    if portraitAnimState_ == "idle" then
        drawPortrait(characterId, 1.0, 0)

    elseif portraitAnimState_ == "exiting" then
        local prog = math.min(1, portraitAnimT_ / PORTRAIT_ANIM_DUR)
        local ease = easeInCubic(prog)
        drawPortrait(exitCharId_ or characterId, 1.0 - ease, -PORTRAIT_SLIDE_DIST * ease)

    elseif portraitAnimState_ == "entering" then
        local prog = math.min(1, portraitAnimT_ / PORTRAIT_ANIM_DUR)
        local ease = easeOutCubic(prog)
        drawPortrait(characterId, ease, PORTRAIT_SLIDE_DIST * (1.0 - ease))
    end
end

--- 绘制全屏背景（大情景专用）
local function drawFullscreenBG()
    -- 纯黑底色，确保完全遮盖底层
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, DW, DH)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, 255))
    nvgFill(vg_)

    -- 地图背景
    if imgBG_ >= 0 then
        DrawUtil.drawImageCentered(vg_, imgBG_, DW * 0.5, DH * 0.5, DW, DH, 1.0)
    end
end

--- 绘制上下"眼皮"遮罩（从 IntroCutscene 移入）
---@param openness number 0=完全闭合, 1=完全睁开
local function drawEyelids(openness)
    local halfH = DH * 0.5
    local lidH = halfH * (1 - openness)
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

--- 绘制文本背景
---@param alpha number 0~1
local function drawTextBG(alpha)
    if imgTextBG_ < 0 or alpha <= 0.01 then return end
    local l = COMMON.textBG
    DrawUtil.drawImageCentered(vg_, imgTextBG_, l.cx, l.cy, l.w, l.h, alpha)
end

--- 绘制角色名背景
---@param alpha number 0~1
local function drawNameBG(alpha)
    if imgNameBG_ < 0 or alpha <= 0.01 then return end
    local l = COMMON.nameBG
    DrawUtil.drawImageCentered(vg_, imgNameBG_, l.cx, l.cy, l.w, l.h, alpha)
end

--- 绘制角色名（带描边）
---@param name string
---@param alpha number 0~1
local function drawName(name, alpha)
    if not name or alpha <= 0.01 then return end
    local l = COMMON.nameText
    DrawUtil.drawTextStroke(vg_, l.cx, l.cy, name, l.fontSize,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        l.color[1], l.color[2], l.color[3],
        l.strokeSize,
        { alpha = alpha, strokeColor = l.strokeColor })
end

--- 绘制对话文本（打字机逐字显示 + 区域内自动换行）
---@param text string
---@param elapsed number 从本步骤开始的计时
---@param alpha number 0~1
local function drawDialogueText(text, elapsed, alpha)
    if not text or alpha <= 0.01 or elapsed <= 0 then return end

    local charCount = utf8.len(text) or 0
    if charCount == 0 then return end

    local charsToShow = math.floor(elapsed * TYPEWRITER_CPS)
    if charsToShow > charCount then charsToShow = charCount end
    if charsToShow <= 0 then return end

    local visibleText = utf8sub(text, 1, charsToShow)

    local l = COMMON.textArea
    local areaLeft = l.cx - l.w * 0.5
    local areaTop  = l.cy - l.h * 0.5

    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, l.fontSize)
    nvgTextLineHeight(vg_, TEXT_LINE_HEIGHT)
    nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg_, nvgRGBA(l.color[1], l.color[2], l.color[3],
                               math.floor(alpha * 255)))
    nvgTextBox(vg_, areaLeft, areaTop, l.w, visibleText, nil)
end

--- 绘制继续箭头（打字完成后闪烁 + 轻微弹跳）
---@param alpha number 0~1
local function drawArrow(alpha)
    if imgArrow_ < 0 or alpha <= 0.01 then return end
    local l = COMMON.arrow

    local blink = 0.65 + 0.35 * math.sin(textElapsed_ * ARROW_BLINK_SPEED * math.pi * 2)
    local finalAlpha = alpha * blink

    local bounceY = math.sin(textElapsed_ * ARROW_BOUNCE_SPEED) * ARROW_BOUNCE_AMP

    DrawUtil.drawImageCentered(vg_, imgArrow_, l.cx, l.cy + bounceY, l.w, l.h, finalAlpha)
end

-- ======================== 公开接口 ========================

--- 初始化：加载共享 UI 图片（只需调用一次）
---@param vg any NanoVG context
---@param sceneRef Scene 场景引用，用于创建 SoundSource
function ScenarioDialogue.init(vg, sceneRef)
    vg_ = vg
    scene_ = sceneRef
    imgTextBG_ = nvgCreateImage(vg, "image/UI_QJDH_BJ1.png", 0)
    imgNameBG_ = nvgCreateImage(vg, "image/UI_QJDH_1.png", 0)
    imgArrow_  = nvgCreateImage(vg, "image/ICON_SJX.png", 0)
    print("[ScenarioDialogue] init: textBG=" .. imgTextBG_
        .. " nameBG=" .. imgNameBG_ .. " arrow=" .. imgArrow_)
end

--- 开始情景对话
---@param config table 配置表
---   config.mode       string "large"|"small" （默认 "large"）
---   config.background string|nil 大情景背景图路径（默认 "image/关卡地图/MAP_1.png"）
---   config.eyeOpen    boolean|nil 是否以睁眼动画入场（默认 false）
---   config.steps      table  对话步骤列表:
---       { characterId = 1, name = "角色名", text = "对话内容" }
---   config.onFinish   function|nil 全部对话结束后的回调
function ScenarioDialogue.show(config)
    if not config or not config.steps or #config.steps == 0 then
        print("[ScenarioDialogue] show: no steps provided")
        return
    end

    mode_       = config.mode or "large"
    steps_      = config.steps
    onFinishCb_ = config.onFinish

    -- 加载大情景全屏背景图
    if mode_ == "large" then
        local bgPath = config.background or "image/关卡地图/MAP_1.png"
        imgBG_ = nvgCreateImage(vg_, bgPath, 0)
        print("[ScenarioDialogue] loaded bg: " .. bgPath .. " handle=" .. imgBG_)
    else
        imgBG_ = -1
    end

    -- 初始化第一步
    stepIndex_      = 1
    textElapsed_    = 0
    typingDone_     = false
    totalChars_     = utf8.len(steps_[1].text) or 0
    prevCharsShown_ = 0
    active_         = true

    -- 睁眼入场：眼皮从全闭缓缓打开，背后是完整的情景画面
    if config.eyeOpen then
        eyeOpenActive_ = true
        eyeOpenT_      = 0
        eyeOpenness_   = 0
        -- 睁眼期间立绘直接静态显示（由眼皮揭露），不需要滑入动画
        portraitAnimState_ = "idle"
        portraitAnimT_     = 0
        -- 打字机延迟到睁眼完成后才开始
        textElapsed_ = 0
        print("[ScenarioDialogue] show with eyeOpen animation")
    else
        eyeOpenActive_ = false
        eyeOpenness_   = 1
        -- 无睁眼时，首个立绘从右侧滑入
        portraitAnimState_ = "entering"
        portraitAnimT_     = 0
    end

    exitCharId_ = nil

    print("[ScenarioDialogue] show: mode=" .. mode_ .. " steps=" .. #steps_)
end

--- 每帧更新
---@param dt number 帧间隔
function ScenarioDialogue.update(dt)
    if not active_ then return end

    -- 消失动画推进
    if dismissing_ then
        dismissT_ = dismissT_ + dt
        if dismissT_ >= DISMISS_DUR then
            dismissing_ = false
            active_     = false
            print("[ScenarioDialogue] dismiss animation finished")
            if onFinishCb_ then
                onFinishCb_()
                onFinishCb_ = nil
            end
        end
        return
    end

    -- 睁眼动画推进
    if eyeOpenActive_ then
        eyeOpenT_ = eyeOpenT_ + dt
        eyeOpenness_ = easeInOut(math.min(1, eyeOpenT_ / EYE_OPEN_DUR))

        if eyeOpenT_ >= EYE_OPEN_DUR then
            -- 睁眼完成
            eyeOpenActive_ = false
            eyeOpenness_   = 1
            print("[ScenarioDialogue] eyeOpen finished, typewriter starts")
        end
        -- 睁眼期间不推进打字机（文本隐藏在眼皮后面，等睁眼完成再开始）
        return
    end

    textElapsed_ = textElapsed_ + dt

    -- 立绘动画推进
    if portraitAnimState_ ~= "idle" then
        portraitAnimT_ = portraitAnimT_ + dt
        if portraitAnimT_ >= PORTRAIT_ANIM_DUR then
            if portraitAnimState_ == "exiting" then
                portraitAnimState_ = "entering"
                portraitAnimT_ = 0
            else
                portraitAnimState_ = "idle"
                portraitAnimT_ = 0
            end
        end
    end

    -- 检测打字是否完成 + 触发 blip 音效
    if not typingDone_ then
        local charsShown = math.floor(textElapsed_ * TYPEWRITER_CPS)
        if charsShown > totalChars_ then charsShown = totalChars_ end
        -- 新字符出现且为中文时播放 blip
        if charsShown > prevCharsShown_ then
            local step = steps_[stepIndex_]
            if step and step.text then
                local ch = utf8sub(step.text, charsShown, charsShown)
                if isChinese(ch) then
                    playBlip()
                end
            end
            prevCharsShown_ = charsShown
        end
        if charsShown >= totalChars_ then
            typingDone_ = true
        end
    end
end

--- 绘制（在 NanoVGRender 回调中调用）
function ScenarioDialogue.draw()
    if not active_ or stepIndex_ < 1 or stepIndex_ > #steps_ then return end

    local step = steps_[stepIndex_]

    -- 消失动画：计算淡出和下滑
    local dismissAlpha  = 1.0
    local dismissSlideY = 0
    if dismissing_ then
        local prog = easeInCubic(math.min(1, dismissT_ / DISMISS_DUR))
        dismissAlpha  = 1.0 - prog
        dismissSlideY = DISMISS_SLIDE * prog
    end

    nvgSave(vg_)
    nvgScissor(vg_, 0, 0, DW, DH)

    -- 消失动画时整体下移
    if dismissSlideY > 0 then
        nvgTranslate(vg_, 0, dismissSlideY)
    end

    -- 0. 大情景：绘制全屏背景（黑底 + 地图），完全覆盖底层所有内容
    if mode_ == "large" then
        drawFullscreenBG()
    end

    -- 1. 角色立绘（带滑入/滑出动画）
    if dismissing_ then
        drawPortrait(step.characterId, dismissAlpha, 0)
    else
        drawPortraitAnimated(step.characterId)
    end

    -- 2. 文本背景
    drawTextBG(dismissAlpha)

    -- 3. 角色名背景
    drawNameBG(dismissAlpha)

    -- 4. 角色名（带描边）
    drawName(step.name, dismissAlpha)

    -- 5. 对话文本（打字机效果）
    drawDialogueText(step.text, textElapsed_, dismissAlpha)

    -- 6. 箭头（打字完成后显示，消失时隐藏）
    if typingDone_ and not dismissing_ then
        drawArrow(1.0)
    end

    -- 7. 睁眼入场遮罩：上下眼皮覆盖在所有内容之上
    if eyeOpenActive_ then
        drawEyelids(eyeOpenness_)
    end

    nvgResetScissor(vg_)
    nvgRestore(vg_)
end

--- 点击推进对话
--- 睁眼期间：点击跳过睁眼，直接进入对话
--- 打字未完成：跳过打字，立即显示全文
--- 打字已完成：进入下一步
function ScenarioDialogue.advance()
    if not active_ then return end

    -- 睁眼期间点击 → 跳过睁眼，直接进入对话
    if eyeOpenActive_ then
        eyeOpenActive_ = false
        eyeOpenness_   = 1
        eyeOpenT_      = EYE_OPEN_DUR
        print("[ScenarioDialogue] eyeOpen skipped by tap")
        return
    end

    -- 打字未完成 → 跳过打字，立即显示全文
    if not typingDone_ then
        textElapsed_ = (totalChars_ / TYPEWRITER_CPS) + 1.0
        typingDone_  = true
        return
    end

    -- 保存当前角色 ID
    local prevCharId = steps_[stepIndex_] and steps_[stepIndex_].characterId

    -- 消失动画期间忽略点击
    if dismissing_ then return end

    -- 打字已完成 → 切换到下一步
    stepIndex_ = stepIndex_ + 1
    if stepIndex_ > #steps_ then
        -- 所有步骤完成
        if mode_ == "small" then
            -- 小情景：启动消失动画
            stepIndex_ = #steps_  -- 保持在最后一步以便绘制
            dismissing_ = true
            dismissT_   = 0
            print("[ScenarioDialogue] starting dismiss animation")
        else
            -- 大情景：直接结束
            active_ = false
            print("[ScenarioDialogue] finished all steps")
            if onFinishCb_ then
                onFinishCb_()
                onFinishCb_ = nil
            end
        end
    else
        -- 重置为新步骤
        textElapsed_    = 0
        typingDone_     = false
        totalChars_     = utf8.len(steps_[stepIndex_].text) or 0
        prevCharsShown_ = 0

        -- 立绘动画：角色变化时触发退出→进入
        local newCharId = steps_[stepIndex_].characterId
        if prevCharId and newCharId and prevCharId ~= newCharId then
            exitCharId_        = prevCharId
            portraitAnimState_  = "exiting"
            portraitAnimT_      = 0
        end

        print("[ScenarioDialogue] step " .. stepIndex_ .. "/" .. #steps_)
    end
end

--- 是否正在播放
---@return boolean
function ScenarioDialogue.isActive()
    return active_
end

--- 是否为全屏覆盖模式（大情景）
---@return boolean
function ScenarioDialogue.isFullscreen()
    return active_ and mode_ == "large"
end

--- 跳过整段对话
function ScenarioDialogue.skip()
    if not active_ then return end
    dismissing_ = false
    dismissT_   = 0
    active_    = false
    stepIndex_ = 0
    print("[ScenarioDialogue] skipped")
    if onFinishCb_ then
        onFinishCb_()
        onFinishCb_ = nil
    end
end

--- 获取当前进度
---@return number currentStep 当前步骤索引
---@return number totalSteps  总步骤数
function ScenarioDialogue.getProgress()
    return stepIndex_, #steps_
end

--- 重置状态（不释放图片缓存）
function ScenarioDialogue.reset()
    active_         = false
    stepIndex_      = 0
    steps_          = {}
    textElapsed_    = 0
    typingDone_     = false
    totalChars_     = 0
    prevCharsShown_ = 0
    onFinishCb_     = nil
    imgBG_       = -1
    portraitAnimState_ = "idle"
    portraitAnimT_     = 0
    exitCharId_        = nil
    eyeOpenActive_     = false
    eyeOpenT_          = 0
    eyeOpenness_       = 0
    dismissing_        = false
    dismissT_          = 0
end

return ScenarioDialogue
