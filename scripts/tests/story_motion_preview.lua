-- 基于官方 2D/NanoVG 示例的受控剧情预览，直接绘制真实模块与正式资源。
-- 时间在 Start 冻结，Render 只绘制；不启动主入口、不读玩家档。
local Scenario = require("ui.story.ScenarioDialogue")
local Letter = require("ui.story.gate.LetterIntro")
local Intro = require("ui.story.gate.IntroCutscene")
local Config = require("config.ScenarioDialogueConfig")
local I18n = require("core.I18n")
local sample_ = "scenario"
local elapsed_ = 0
local introPhase_ = 3
---@type NVGContextWrapper?
local vg_ = nil

function Start()
    for _, arg in ipairs(GetArguments()) do
        local selected = arg:match("^%-story%-sample=(%a+)$")
        local elapsed = tonumber(arg:match("^%-story%-elapsed=([%d%.]+)$"))
        local introPhase = tonumber(arg:match("^%-story%-phase=(%d+)$"))
        if selected then sample_ = selected end
        if elapsed then elapsed_ = math.max(0, elapsed) end
        if introPhase then introPhase_ = math.max(1, math.min(5, math.floor(introPhase))) end
    end
    vg_ = nvgCreate(1)
    assert(vg_, "预览 NanoVG 创建失败")
    assert(nvgCreateFont(vg_, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "预览字体加载失败")
    I18n.set("zh_CN")
    if sample_ == "letter" then
        Letter.init(vg_)
        Letter.start(nil)
        for _ = 1, 7 do Letter.handleTap() end
        Letter.update(elapsed_)
    elseif sample_ == "intro" then
        Intro.init(vg_, nil)
        Intro.start(nil)
        local durations = { 1.5, 4.0, 7.5, 4.0, 3.5 }
        for i = 1, introPhase_ - 1 do Intro.update(durations[i]) end
        Intro.update(elapsed_)
    elseif sample_ == "cg" then
        Scenario.init(vg_, nil)
        Scenario.show(Config.OPENING)
        Scenario.advance()
        Scenario.update(elapsed_)
    else
        Scenario.init(vg_, nil)
        Scenario.show(Config.OPENING_JOINS[1])
        Scenario.advance()
        Scenario.update(0.25 + elapsed_)
    end
    SubscribeToEvent(vg_, "NanoVGRender", "StoryMotionRender")
    print("[story_motion_preview] READY sample=" .. sample_ .. " elapsed=" .. elapsed_)
end

function StoryMotionRender()
    if not vg_ then return end
    local physW, physH = graphics:GetWidth(), graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local w, h = physW / dpr, physH / dpr
    nvgBeginFrame(vg_, w, h, dpr)
    if sample_ == "letter" then
        Letter.draw(vg_, w, h)
    elseif sample_ == "intro" then
        Intro.draw(vg_, w, h)
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
