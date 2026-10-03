-- 真实 require + 官方 Runtime 独立入口；桩只替换绘制/音频出口，不预注入 package.loaded。
local passed_ = 0
local function check(ok, name)
    assert(ok, "[FAIL] " .. name)
    passed_ = passed_ + 1
end

function Start()
    local originalFunctions = {} ---@type table<string, any>
    local originalLanguage = "zh_CN"
    local I18n = require("core.I18n")
    originalLanguage = I18n.get()
    local captures = {} ---@type string[]
    local measured = {} ---@type string[]
    local fontSize = 20
    local function replace(name, fn)
        originalFunctions[name] = _G[name]
        _G[name] = fn
    end
    local function noOp() end
    local function record(_, _, _, text)
        captures[#captures + 1] = text
        return 0
    end
    local function contains(text)
        for _, capture in ipairs(captures) do if capture == text then return true end end
        return false
    end
    local ok, err = pcall(function()
        local Story = require("core.I18nStory")
        local Display = require("ui.story.StoryDisplay")
        local Scenario = require("ui.story.ScenarioDialogue")
        local Letter = require("ui.story.gate.LetterIntro")
        local Intro = require("ui.story.gate.IntroCutscene")
        local Config = require("config.ScenarioDialogueConfig")
        local EventBus = require("core.EventBus")
        -- 使用已安装的 raw 出口录制；不依赖 require 命中 package.loaded 的特殊行为。
        local rawText, rawBounds = I18n.displayText, I18n.displayBounds
        originalFunctions.__displayText = rawText
        originalFunctions.__displayBounds = rawBounds
        I18n.displayText = record
        I18n.displayBounds = function(_, _, _, text)
            measured[#measured + 1] = text
            return (utf8.len(text) or 0) * fontSize * 0.6
        end
        replace("nvgText", record)
        replace("nvgFontSize", function(_, value) fontSize = value end)
        replace("nvgCreateImage", function() return -1 end)
        replace("nvgImageSize", function() return 1, 1 end)
        for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgScissor", "nvgResetScissor",
            "nvgIntersectScissor", "nvgTranslate", "nvgBeginPath", "nvgRect", "nvgRoundedRect",
            "nvgFillColor", "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke",
            "nvgFontFace", "nvgTextAlign", "nvgTextLineHeight", "nvgMoveTo", "nvgLineTo",
            "nvgFillPaint" }) do replace(name, noOp) end

        local letterSources = {
            "致第三十七任远征长：", "拆开这封信时，我已经荣休了。", "公会管这叫交接。我管这叫甩锅。",
            "帽子、印鉴、名册，都在桌上。", "塔底下的山海怪不讲道理，", "但它们会排队上门。",
            "门外有三条吵闹的命。", "狗会咬，龙会烧，鸡会敲铃。", "先听他们把话说完，再出门。",
            "公会不需要英雄。", "需要一个肯签字的傻子。", "——第三十六任，你的外祖父",
        }
        for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            I18n.set(lang)
            for _, source in ipairs(Story.SOURCES) do
                local translated = Story.lookup(source, lang)
                check(type(translated) == "string" and translated ~= "" and utf8.len(translated) ~= nil,
                    lang .. "完整词条UTF8")
                check(Display.text(source) == translated, lang .. "语言缓存与完整译文")
            end
            for _, source in ipairs(letterSources) do
                check(Story.lookup(source, lang) ~= nil, lang .. "当前信件12行")
            end
            local text = Display.text(Config.OPENING.steps[1].text)
            local rows = Display.layoutText(nil, text, 70, 16)
            local rebuilt = {}
            for _, row in ipairs(rows) do rebuilt[#rebuilt + 1] = row.text end
            check(table.concat(rebuilt) == text, lang .. "折行不丢完整译文")
            for count = 0, Story.length(text) do
                local visible = {}
                for _, row in ipairs(rows) do visible[#visible + 1] = Story.rowPrefix(row, count) end
                check(table.concat(visible) == Story.sub(text, 1, count), lang .. "逐字行前缀UTF8")
            end
            local visible, _, typingDuration, totalDuration = Story.typed(text, 1.9, 10, 2.5)
            check(visible == text and typingDuration < totalDuration, lang .. "长译文时间窗内打完")
        end
        check(Story.lookup(letterSources[1], "invalid") == nil, "未知语言nil")
        check(Story.lookup("unregistered", "en") == nil, "未知源文nil")
        check(Story.lookup("image/角色立绘/大狗嚼.png", "ja") == nil, "资源名不翻译")

        -- 已翻译片段必须绕 lookup：将 lookup 改为抛错，然后绘制预折行行前缀。
        I18n.set("en")
        local source = Config.OPENING.steps[1].text
        local text = Display.text(source)
        local rows = Display.layoutText(nil, text, 140, 18)
        local lookup = I18n.lookup
        I18n.lookup = function() error("fragment translated twice") end
        captures = {}
        local rawOk = pcall(Display.drawRows, nil, 0, 0, rows, 5, 24)
        I18n.lookup = lookup
        check(rawOk and table.concat(captures) == Story.sub(text, 1, 5), "raw绘制不二次翻译")

        Scenario.init(nil, nil)
        local finishes, events = 0, 0
        local listener = function() events = events + 1 end
        EventBus.on("scenario_dialogue_finished", listener)
        local stepSource = Config.OPENING.steps[1].text
        local function show()
            Scenario.reset()
            Scenario.show({ mode = "small", steps = { { name = "卫兵", text = stepSource } },
                onFinish = function() finishes = finishes + 1 end })
        end
        I18n.set("en")
        show()
        Scenario.update(0.5)
        captures = {}
        Scenario.draw(1600, 900)
        check(contains(Story.sub(Display.text(stepSource), 1, 5)), "对话使用译文截字")
        check(Scenario.getProgress() == 1 and Config.OPENING.steps[1].text == stepSource, "源配置与步骤未变")
        I18n.set("ja")
        Scenario.update(0.1)
        captures = {}
        Scenario.draw(1600, 900)
        check(contains(Story.sub(Display.text(stepSource), 1, 1)), "未完句切语重启当前译文")
        Scenario.advance()
        I18n.set("ko")
        Scenario.update(0)
        captures = {}
        Scenario.draw(1600, 900)
        check(contains(Display.text(stepSource)), "已完句切语保留译文全文")
        Scenario.advance()
        Scenario.update(0.4)
        Scenario.update(0.4)
        Scenario.skip()
        check(finishes == 1 and events == 1 and not Scenario.isActive(), "自然finish回调事件仅一次")
        show()
        Scenario.skip()
        Scenario.skip()
        Scenario.update(1)
        check(finishes == 2 and events == 2, "skip回调事件仅一次")
        EventBus.off("scenario_dialogue_finished", listener)

        -- 信件四段仍按源流程揭示；两行完整句合并后本地化，不改变finish触发。
        I18n.set("en")
        local letterFinishes = 0
        Letter.reset()
        Letter.start(function() letterFinishes = letterFinishes + 1 end)
        for _ = 1, 6 do Letter.handleTap() end
        Letter.handleTap()
        captures = {}
        Letter.draw(nil, 1920, 1080)
        check(contains(Display.text(letterSources[1])), "信件第一行译文")
        check(table.concat(captures):find(Display.text("塔底下的山海怪不讲道理，但它们会排队上门。"), 1, true) ~= nil,
            "信件跨行完整句译文")
        I18n.set("ja")
        captures = {}
        Letter.draw(nil, 1920, 1080)
        check(contains(Display.text(letterSources[1])), "信件切语缓存失效")
        Letter.handleTap()
        Letter.handleTap()
        Letter.update(1)
        Letter.update(1)
        check(letterFinishes == 1, "信件finish仅一次")

        -- 旧过场不启音频也可独立验证：第一阶段先停留；用skip保证生命周期出口。
        Intro.init(nil, nil)
        Intro.reset()
        local introFinishes = 0
        Intro.start(function() introFinishes = introFinishes + 1 end)
        Intro.update(0.5)
        check(Intro.isActive() and not Intro.isFinished(), "过场初始化保持播放")
        Intro.skip()
        Intro.skip()
        check(introFinishes == 1 and Intro.isFinished(), "过场skip仅一次")
        Intro.reset()
        print(string.format("I18N STORY DISPLAY: ALL PASS (%d checks)", passed_))
    end)
    if originalFunctions.__displayText then I18n.displayText = originalFunctions.__displayText end
    if originalFunctions.__displayBounds then I18n.displayBounds = originalFunctions.__displayBounds end
    for name, fn in pairs(originalFunctions) do
        if name:sub(1, 2) ~= "__" then _G[name] = fn end
    end
    I18n.set(originalLanguage)
    if not ok then
        print("[i18n_story_display_test] FAILED " .. tostring(err))
        log:Write(LOG_ERROR, "[i18n_story_display_test] " .. tostring(err))
    end
    engine:Exit()
end
