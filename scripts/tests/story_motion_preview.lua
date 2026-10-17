-- 基于官方 2D/NanoVG 示例的受控剧情预览，直接绘制真实模块与正式资源。
-- 时间在 Start 冻结，Render 只绘制；不启动主入口、不读玩家档。
local Scenario = require("ui.story.ScenarioDialogue")
local Letter = require("ui.story.gate.LetterIntro")
local Intro = require("ui.story.gate.IntroCutscene")
local Config = require("config.ScenarioDialogueConfig")
local I18n = require("core.I18n")
local SAMPLE = "scenario"
local ELAPSED = 0
---@type NVGContextWrapper?
local vg_ = nil

function Start()
    vg_ = nvgCreate(1)
    assert(vg_, "预览 NanoVG 创建失败")
    assert(nvgCreateFont(vg_, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "预览字体加载失败")
    I18n.set("zh_CN")
    if SAMPLE == "letter" then
        Letter.init(vg_)
        Letter.start(nil)
        for _ = 1, 7 do Letter.handleTap() end
        Letter.update(ELAPSED)
    elseif SAMPLE == "intro" then
        Intro.init(vg_, nil)
        Intro.start(nil)
        Intro.update(1.5)
        Intro.update(4)
        Intro.update(ELAPSED)
    elseif SAMPLE == "cg" then
        Scenario.init(vg_, nil)
        Scenario.show(Config.OPENING)
        Scenario.advance()
        Scenario.update(ELAPSED)
    else
        Scenario.init(vg_, nil)
        Scenario.show(Config.OPENING_JOINS[1])
        Scenario.advance()
        Scenario.update(0.25 + ELAPSED)
    end
    SubscribeToEvent(vg_, "NanoVGRender", "StoryMotionRender")
    print("[story_motion_preview] READY sample=" .. SAMPLE .. " elapsed=" .. ELAPSED)
end

function StoryMotionRender()
    if not vg_ then return end
    local physW, physH = graphics:GetWidth(), graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local w, h = physW / dpr, physH / dpr
    nvgBeginFrame(vg_, w, h, dpr)
    if SAMPLE == "letter" then
        Letter.draw(vg_, w, h)
    elseif SAMPLE == "intro" then
        -- 与 StandaloneHorizon 宿主相同的等比 cover；只裁环境，不把字幕横向压扁。
        local design = require("config.GameConfig").Design
        local scale = math.max(w / design.WIDTH, h / design.HEIGHT)
        nvgSave(vg_)
        nvgTranslate(vg_, (w - design.WIDTH * scale) * 0.5, (h - design.HEIGHT * scale) * 0.5)
        nvgScale(vg_, scale, scale)
        Intro.draw(vg_)
        nvgRestore(vg_)
    else
        Scenario.draw(w, h)
    end
    nvgEndFrame(vg_)
end

function Stop()
    Scenario.reset()
    Letter.reset()
    Intro.reset()
    if vg_ then nvgDelete(vg_); vg_ = nil end
end
