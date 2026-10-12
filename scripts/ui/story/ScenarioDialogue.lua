-- ============================================================================
-- ScenarioDialogue.lua — 情景对话底层框架
-- 支持两种模板：大情景（全屏覆盖）和 小情景（弹窗对话）
-- 设计为可复用底层，由外部调用 show() 驱动对话流程
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local GameConfig = require("config.GameConfig")
local HeroFrame = require("ui.widget.HeroFrame")
local EventBus = require("core.EventBus")
local I18n = require("core.I18n")
local Story = require("core.I18nStory")
local Display = require("ui.story.StoryDisplay")
local ScenarioConfig = require("config.ScenarioDialogueConfig")
local HeroAssetUtil = require("config.HeroAssetUtil")

local ScenarioDialogue = {}

-- ======================== 设计常量 ========================
local DW = GameConfig.Design.WIDTH   -- 1080
local DH = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 模板布局参数 ========================

--- 对话只走横屏矢量条。

-- ======================== 打字机参数 ========================
local TYPEWRITER_CPS     = 10    -- 字/秒
local ARROW_BLINK_SPEED  = 1.2   -- 箭头闪烁频率 (Hz)

-- ======================== 立绘动画参数 ========================
local PORTRAIT_ANIM_DUR   = 0.25   -- 单阶段动画时长 (秒)
local PORTRAIT_SLIDE_DIST = 150    -- 滑动距离 (设计像素)

-- ======================== 睁眼入场参数 ========================
local EYE_OPEN_DUR = 2.0
local EYE_DIALOGUE_DELAY = 2.0

-- ======================== 打字机音效 ========================
local BLIP_SFX_PATH = "audio/sfx/dialogue_blip.ogg"

-- ======================== 内部状态 ========================
local vg_         = nil
local scene_      = nil   -- 场景引用，用于创建 SoundSource
local active_     = false

-- 对话配置
local mode_       = "large"     -- "large" | "small"

--- 对话真正结束（自然播完/跳过）时广播；硬重置不广播。
--- 必须放在 mode_ 声明之后，闭包才能读取当前对话模式。
local function emitFinished_(reason)
    EventBus.emit("scenario_dialogue_finished", { reason = reason, mode = mode_ })
end

local steps_      = {}          -- { {characterId, name, text}, ... }
local stepIndex_  = 0
local onFinishCb_ = nil
local title_      = nil         -- 横屏章节标题（可选）

-- 当前步骤的打字机状态
local textElapsed_ = 0
local typingDone_  = false
local totalChars_  = 0
local prevCharsShown_ = 0  -- 上一帧已显示字符数，用于检测新字符触发 blip
local displayText_ = ""
local displaySource_ = ""
local displayLanguage_ = ""
local displayStep_ = 0

-- 当前句全文先翻译；语言变化清显示缓存，不推进步骤或触发奖励。
local function syncDisplay()
    local step = steps_[stepIndex_]
    local source = step and step.text or ""
    local lang = I18n.get()
    if displayStep_ ~= stepIndex_ or displaySource_ ~= source or displayLanguage_ ~= lang then
        local sameStep = displayStep_ == stepIndex_ and displaySource_ == source
        local wasDone = sameStep and typingDone_
        displayText_ = Display.text(source)
        displaySource_, displayLanguage_, displayStep_ = source, lang, stepIndex_
        totalChars_ = Story.length(displayText_)
        textElapsed_ = wasDone and (totalChars_ / TYPEWRITER_CPS + 1) or 0
        typingDone_, prevCharsShown_ = wasDone, wasDone and totalChars_ or 0
    end
end

-- 图片句柄
local imgBG_      = -1   -- 剧情独立环境；small保留原对白和关闭时序。
local backgroundIsCg_ = false
local backgroundCache_ = {}
local backgroundFailures_ = {}

--- 立绘缓存: [characterId] = nvgImage handle
local portraitCache_ = {}

-- 立绘动画状态
local portraitAnimState_ = "idle"    -- "idle" | "exiting" | "entering"
local portraitAnimT_     = 0
---@type table|nil
local exitStep_ = nil           -- 固定持有退出步骤，快速连点不能替换正在退出的立绘

-- 睁眼入场状态
local eyeOpenActive_   = false
local eyeOpenT_        = 0
local eyeOpenness_     = 0
local eyeHoldActive_   = false
local eyeHoldT_        = 0
local avatarCache_     = {}
local cgCache_         = {}

-- 消失动画状态（小情景用）
local dismissing_      = false   -- 是否正在播放消失动画
local dismissT_        = 0       -- 消失动画计时器
local DISMISS_DUR      = 0.3     -- 消失动画时长 (秒)

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

local function getCachedImage(cache, key, path)
    if not key or not path then return -1 end
    local cached = cache[key]
    if cached then return cached end
    local handle = nvgCreateImage(vg_, path, 0)
    cache[key] = handle or -1
    return cache[key]
end

local function getBackgroundImage(path)
    if not vg_ or not path or path == "" then return -1 end
    local cached = backgroundCache_[path]
    if cached ~= nil then return cached end
    local handle = nvgCreateImage(vg_, path, 0) or -1
    if handle >= 0 then
        backgroundCache_[path] = handle
        backgroundFailures_[path] = nil
        print("[ScenarioDialogue] loaded bg: " .. path .. " handle=" .. handle)
    elseif not backgroundFailures_[path] then
        backgroundFailures_[path] = true
        print("[ScenarioDialogue] background unavailable: " .. path)
    end
    -- 缺图不缓存失败；后续恢复后可以重开，不影响剧情结束或领奖。
    return handle
end

local function getAvatarImage(step)
    local appearance = ScenarioConfig.getAppearance(step)
    local path = appearance.iconPath or (appearance.heroId and HeroAssetUtil.getIconPath(appearance.heroId))
    return getCachedImage(avatarCache_, path, path)
end

local function getCgImage(step)
    if not step then return -1 end
    -- 开场 CG 写在情景 background 上，不在每句 step.cg。含“CG”的背景不再叠加立绘。
    local path = step.cg or step.cgPath
    if (not path or path == "") and type(step.background) == "string" and string.find(step.background, "CG", 1, true) then
        path = step.background
    end
    if not path or path == "" then return -1 end
    return getCachedImage(cgCache_, path, path)
end

local function getPortraitImage(step)
    local appearance = ScenarioConfig.getAppearance(step)
    local path = appearance.portraitPath or (appearance.heroId and HeroAssetUtil.getPortraitPath(appearance.heroId))
    if not path then return -1 end
    if portraitCache_[path] ~= nil then return portraitCache_[path] end
    local handle = getCachedImage(portraitCache_, path, path)
    print("[ScenarioDialogue] loadPortrait: name=" .. tostring(step.name) .. " path=" .. path .. " handle=" .. handle)
    return handle
end

-- ======================== 公开接口 ========================

--- 初始化：加载共享 UI 图片（只需调用一次）
---@param vg any NanoVG context
---@param sceneRef Scene 场景引用，用于创建 SoundSource
function ScenarioDialogue.init(vg, sceneRef)
    if vg_ ~= vg then
        backgroundCache_, backgroundFailures_ = {}, {}
    end
    vg_ = vg
    scene_ = sceneRef
    print("[ScenarioDialogue] init")
end

--- 开始情景对话
---@param config table 配置表
---   config.mode       string "large"|"small" （默认 "large"）
---   config.background string|nil 独立环境；small仅显式给出时加载，large默认黑棘林道。
---   config.backgroundIsCg boolean|nil 背景已含人物时跳过立绘，不按文件名猜。
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
    title_      = config.title

    -- 显式环境同样适用于small，不改变其模式、人物比例、门控或0.3秒关闭动画。
    local defaultPath = require("config.StoryBackgroundConfig").DEFAULT
    local bgPath = config.background
    if mode_ == "large" and not bgPath then bgPath = defaultPath end
    imgBG_ = getBackgroundImage(bgPath)
    if mode_ == "large" and imgBG_ < 0 and bgPath ~= defaultPath then
        imgBG_ = getBackgroundImage(defaultPath)
        backgroundIsCg_ = false
    else
        backgroundIsCg_ = config.backgroundIsCg == true and imgBG_ >= 0
    end

    -- 初始化第一步
    stepIndex_      = 1
    textElapsed_    = 0
    typingDone_     = false
    totalChars_     = 0
    prevCharsShown_ = 0
    displayStep_    = 0
    syncDisplay()
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
        eyeHoldActive_ = false
        -- 无睁眼时，首个立绘从右侧滑入
        portraitAnimState_ = "entering"
        portraitAnimT_     = 0
    end

    exitStep_ = nil
    print("[ScenarioDialogue] show: mode=" .. mode_ .. " steps=" .. #steps_
        .. " title=" .. tostring(title_))
end

--- 每帧更新
---@param dt number 帧间隔
function ScenarioDialogue.update(dt)
    if not active_ then return end
    syncDisplay()

    -- 消失动画推进
    if dismissing_ then
        dismissT_ = dismissT_ + dt
        if dismissT_ >= DISMISS_DUR then
            dismissing_ = false
            active_     = false
            print("[ScenarioDialogue] dismiss animation finished")
            if onFinishCb_ then
                local callback = onFinishCb_
                onFinishCb_ = nil
                callback()
            end
            -- 先跑 onFinish（可能链播下一段），再广播结束供排队方消化
            emitFinished_("dismissed")
        end
        return
    end

    -- 睁眼动画推进
    if eyeOpenActive_ then
        eyeOpenT_ = eyeOpenT_ + dt
        eyeOpenness_ = easeInOut(math.min(1, eyeOpenT_ / EYE_OPEN_DUR))

        if eyeOpenT_ >= EYE_OPEN_DUR then
            eyeOpenActive_ = false
            eyeOpenness_   = 1
            eyeHoldActive_ = true
            eyeHoldT_      = 0
            print("[ScenarioDialogue] eyeOpen finished, waiting before dialogue")
        end
        return
    end

    if eyeHoldActive_ then
        eyeHoldT_ = eyeHoldT_ + dt
        if eyeHoldT_ >= EYE_DIALOGUE_DELAY then
            eyeHoldActive_ = false
            print("[ScenarioDialogue] dialogue delay finished")
        end
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
                local ch = utf8sub(displayText_, charsShown, charsShown)
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

--- 横屏立绘（逻辑坐标，不走 1080×2400）
---@param step table|nil
---@param alpha number
---@param cx number
---@param cy number
---@param pw number
---@param ph number
---@param offsetX number|nil
local function drawPortraitAt(step, alpha, cx, cy, pw, ph, offsetX)
    if not step or alpha <= 0.01 then return end
    local img = getPortraitImage(step)
    if img < 0 then return end
    local appearance = ScenarioConfig.getAppearance(step)
    if appearance.contain then
        local srcW, srcH = nvgImageSize(vg_, img)
        if srcW > 0 and srcH > 0 then
            local scale = math.min(pw / srcW, ph / srcH)
            DrawUtil.drawImageCentered(vg_, img, cx + (offsetX or 0), cy, srcW * scale, srcH * scale, alpha)
            return
        end
    end
    DrawUtil.drawImageCover(vg_, img, cx + (offsetX or 0), cy, pw, ph, alpha)
end

--- 横屏情景：左立绘 + 底部宽对话条；显式背景独立铺底，无背景small继续压暗宿主页。
---@param w number
---@param h number
local function drawLandscape(w, h)
    if not active_ or stepIndex_ < 1 or stepIndex_ > #steps_ then return end
    syncDisplay()
    local step = steps_[stepIndex_]

    local dismissAlpha = 1.0
    local dismissSlideY = 0
    if dismissing_ then
        local prog = easeInCubic(math.min(1, dismissT_ / DISMISS_DUR))
        dismissAlpha = 1.0 - prog
        dismissSlideY = h * 0.06 * prog
    end

    nvgSave(vg_)
    nvgScissor(vg_, 0, 0, w, h)
    if dismissSlideY > 0 then
        nvgTranslate(vg_, 0, dismissSlideY)
    end

    if mode_ == "large" or imgBG_ >= 0 then
        nvgBeginPath(vg_)
        nvgRect(vg_, 0, 0, w, h)
        nvgFillColor(vg_, nvgRGBA(0, 0, 0, math.floor(255 * dismissAlpha)))
        nvgFill(vg_)
        if imgBG_ >= 0 then
            DrawUtil.drawImageCover(vg_, imgBG_, w * 0.5, h * 0.5, w, h, dismissAlpha)
        end
    else
        nvgBeginPath(vg_)
        nvgRect(vg_, 0, 0, w, h)
        nvgFillColor(vg_, nvgRGBA(0, 0, 0, math.floor(150 * dismissAlpha)))
        nvgFill(vg_)
    end

    local showDialogue = not eyeOpenActive_ and not eyeHoldActive_
    local barH = math.max(150, h * 0.26)
    local barX = w * 0.035
    local barW = w - barX * 2
    local barY = h - barH - h * 0.04
    local cgImage = getCgImage(step)
    local cgOnly = backgroundIsCg_ or cgImage >= 0
    if cgImage >= 0 then
        DrawUtil.drawImageCover(vg_, cgImage, w * 0.5, h * 0.5, w, h, dismissAlpha)
    elseif not cgOnly then
        local portraitH = mode_ == "small" and h * 0.72 or h * 0.92
        local portraitW = portraitH * 0.72
        local portraitCx = w * 0.30
        local portraitCy = (mode_ == "small" and h * 0.46 or h * 0.42) + h * 0.30
        local slide = w * 0.045
        local offsetX = 0
        local alpha = dismissAlpha
        local drawStep = step
        if not dismissing_ and portraitAnimState_ == "exiting" then
            local prog = math.min(1, portraitAnimT_ / PORTRAIT_ANIM_DUR)
            local ease = easeInCubic(prog)
            alpha = dismissAlpha * (1.0 - ease)
            offsetX = -slide * ease
            drawStep = exitStep_ or step
        elseif not dismissing_ and portraitAnimState_ == "entering" then
            local prog = math.min(1, portraitAnimT_ / PORTRAIT_ANIM_DUR)
            local ease = easeOutCubic(prog)
            alpha = dismissAlpha * ease
            offsetX = slide * (1.0 - ease)
        end
        drawPortraitAt(drawStep, alpha, portraitCx, portraitCy, portraitW, portraitH, offsetX)
    end

    if showDialogue then
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, barY - h * 0.02, w, h - barY + h * 0.04)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, math.floor(70 * dismissAlpha)))
    nvgFill(vg_)

    local radius = math.max(8, h * 0.012)
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, barX, barY, barW, barH, radius)
    nvgFillColor(vg_, nvgRGBA(10, 8, 6, math.floor(214 * dismissAlpha)))
    nvgFill(vg_)
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, barX, barY, barW, barH, radius)
    nvgStrokeColor(vg_, nvgRGBA(232, 200, 120, math.floor(120 * dismissAlpha)))
    nvgStrokeWidth(vg_, math.max(1.5, h * 0.002))
    nvgStroke(vg_)

    local appearance = ScenarioConfig.getAppearance(step)
    local showAvatar = appearance.heroId ~= nil or appearance.iconPath ~= nil
    local avatarSize = showAvatar and math.max(54, h * 0.078) or 0
    local avatarX = barX + w * 0.018
    local avatarY = barY - avatarSize * 0.34
    local avatarImg = showAvatar and getAvatarImage(step) or -1
    -- [统一角色框] 头像与立绘共用剧情美术映射；独立NPC卡图不伪造英雄ID。
    if showAvatar then
        HeroFrame.draw(vg_, {
            cx = avatarX + avatarSize * 0.5, cy = avatarY + avatarSize * 0.5,
            size = avatarSize, radius = (avatarSize + 6) * 0.18,
            heroId = appearance.heroId,
            iconHandle = avatarImg,
            state = "owned",
            alpha = dismissAlpha,
        })
    end

    local chipH = math.max(34, h * 0.046)
    local chipW = math.min(barW * 0.32, math.max(200, h * 0.36))
    local chipX = avatarX + avatarSize + w * 0.012
    local chipY = avatarY + (avatarSize - chipH) * 0.5
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, chipX, chipY, chipW, chipH, chipH * 0.2)
    nvgFillColor(vg_, nvgRGBA(28, 18, 12, math.floor(235 * dismissAlpha)))
    nvgFill(vg_)
    nvgStrokeColor(vg_, nvgRGBA(232, 200, 120, math.floor(160 * dismissAlpha)))
    nvgStrokeWidth(vg_, 1.5)
    nvgStroke(vg_)
    if step.name then
        local name = Display.text(step.name)
        local nameSize = math.max(20, h * 0.028)
        nvgFontFace(vg_, "sans")
        nvgFontSize(vg_, nameSize)
        local nameWidth = I18n.displayBounds(vg_, 0, 0, name)
        if nameWidth > chipW - 16 then nameSize = nameSize * (chipW - 16) / nameWidth end
        DrawUtil.drawTextStroke(vg_, chipX + chipW * 0.5, chipY + chipH * 0.52, name,
            nameSize,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 236, 196, 3,
            { alpha = dismissAlpha, strokeColor = { 0x31, 0x24, 0x24 } })
    end

    local textX = barX + w * 0.028
    local textY = barY + barH * 0.22
    local textW = barW - w * 0.07
    if step.text and textElapsed_ > 0 and dismissAlpha > 0.01 then
        local charsToShow = math.min(totalChars_, math.floor(textElapsed_ * TYPEWRITER_CPS))
        if charsToShow > 0 then
            nvgFontFace(vg_, "sans")
            nvgTextLineHeight(vg_, 1.35)
            nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local availableH = barY + barH - h * 0.055 - textY
            local font, rows = Display.fitLayout(vg_, displayText_, textW, availableH,
                math.max(20, h * 0.030), math.max(12, h * 0.018), 1.35)
            nvgFontSize(vg_, font)
            nvgFillColor(vg_, nvgRGBA(232, 220, 196, math.floor(255 * dismissAlpha)))
            Display.drawRows(vg_, textX, textY, rows, charsToShow, font * 1.35)
        end
    end

    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, math.max(14, h * 0.020))
    nvgTextAlign(vg_, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, nvgRGBA(232, 200, 120, math.floor(170 * dismissAlpha)))
    nvgText(vg_, w * 0.96, h * 0.055, string.format("%d / %d", stepIndex_, #steps_), nil)

    if typingDone_ and not dismissing_ then
        local blink = 0.55 + 0.45 * math.sin(textElapsed_ * ARROW_BLINK_SPEED * math.pi * 2)
        nvgFontSize(vg_, math.max(16, h * 0.022))
        nvgTextAlign(vg_, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg_, nvgRGBA(232, 200, 120, math.floor(220 * blink)))
        Display.draw(vg_, barX + barW - w * 0.02, barY + barH - h * 0.028, "轻触继续")
    end
    end

    if eyeOpenActive_ then
        local lidH = (h * 0.5) * (1 - eyeOpenness_)
        if lidH >= 1 then
            nvgBeginPath(vg_)
            nvgRect(vg_, 0, 0, w, lidH)
            nvgFillColor(vg_, nvgRGBA(0, 0, 0, 255))
            nvgFill(vg_)
            nvgBeginPath(vg_)
            nvgRect(vg_, 0, h - lidH, w, lidH)
            nvgFillColor(vg_, nvgRGBA(0, 0, 0, 255))
            nvgFill(vg_)
        end
    end

    nvgResetScissor(vg_)
    nvgRestore(vg_)
end

--- 绘制（在 NanoVGRender 回调中调用）。只走横屏矢量对话条。
---@param frameW number|nil
---@param frameH number|nil
function ScenarioDialogue.draw(frameW, frameH)
    if active_ then syncDisplay() end
    local w = frameW
    local h = frameH
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
        w, h = DH, DW
    end
    drawLandscape(w, h)
end

--- 点击推进对话
--- 睁眼期间：点击跳过睁眼，直接进入对话
--- 打字未完成：跳过打字，立即显示全文
--- 打字已完成：进入下一步
function ScenarioDialogue.advance()
    if not active_ then return end
    syncDisplay()

    -- 睁眼期间点击 → 跳过睁眼，直接进入对话
    if eyeOpenActive_ or eyeHoldActive_ then
        eyeOpenActive_ = false
        eyeHoldActive_ = false
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

    -- 保存当前美术来源；旧剧情编号相同，也可能是不同的说话人。
    local prevStep = steps_[stepIndex_]
    local prevAppearance = ScenarioConfig.getAppearance(prevStep)

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
                local callback = onFinishCb_
                onFinishCb_ = nil
                callback()
            end
            emitFinished_("finished")
        end
    else
        -- 重置为新步骤
        textElapsed_    = 0
        typingDone_     = false
        syncDisplay()
        prevCharsShown_ = 0

        -- 立绘动画按实际美术来源切换，不把镜像和本体误判为其他英雄。
        local newAppearance = ScenarioConfig.getAppearance(steps_[stepIndex_])
        if prevAppearance.heroId ~= newAppearance.heroId or prevAppearance.portraitPath ~= newAppearance.portraitPath then
            exitStep_ = prevStep
            portraitAnimState_ = "exiting"
            portraitAnimT_ = 0
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
        local callback = onFinishCb_
        onFinishCb_ = nil
        callback()
    end
    emitFinished_("skipped")
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
    exitStep_          = nil
    eyeOpenActive_     = false
    eyeOpenT_          = 0
    eyeOpenness_       = 0
    dismissing_        = false
    dismissT_          = 0
    title_             = nil
    displayText_, displaySource_, displayLanguage_, displayStep_ = "", "", "", 0
end

return ScenarioDialogue
