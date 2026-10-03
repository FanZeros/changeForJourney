-- 真实 require + 官方 Runtime 独立入口；桩只替换绘制/音频出口，不预注入 package.loaded。
local passed_ = 0
local function check(ok, name)
    assert(ok, "[FAIL] " .. name)
    passed_ = passed_ + 1
end

function Start()
    local nativeBounds, nativeSize, nativeFace = nvgTextBounds, nvgFontSize, nvgFontFace
    local metricContext = nvgCreate(1)
    local metricFont = nvgCreateFont(metricContext, "sans", "Fonts/NotoSansCJKkr-Bold.otf")
    local realMetrics = false
    nativeFace(metricContext, "sans")
    nativeSize(metricContext, 20)
    local initialWidth = nativeBounds(metricContext, 0, 0, "mmmm")
    print("[Noto-before-spy] mmmm20=" .. initialWidth)
    local originalFunctions = {} ---@type table<string, any>
    local originalLanguage = "zh_CN"
    local I18n = require("core.I18n")
    originalLanguage = I18n.get()
    local captures = {} ---@type string[]
    local measured = {} ---@type string[]
    local drawCalls = {} ---@type table[]
    local panelRects = {} ---@type table[]
    local fontSize = 20
    local textAlign = NVG_ALIGN_LEFT + NVG_ALIGN_TOP
    -- 确定性字宽模型与绘制spy，仅验证逻辑边界，不代替真实字体/实机截图。
    local function textWidth(text, font)
        if realMetrics then
            nativeFace(metricContext, "sans")
            nativeSize(metricContext, font)
            local advance = nativeBounds(metricContext, 0, 0, text)
            return advance
        end
        local em = 0
        for _, codepoint in utf8.codes(text) do
            local char = utf8.char(codepoint)
            em = em + (codepoint >= 0x2E80 and 1 or
                ((char == "W" or char == "M") and 0.9 or
                ((char == "i" or char == "l" or char == " ") and 0.3 or 0.6)))
        end
        return em * font
    end
    local function replace(name, fn)
        if originalFunctions[name] == nil then originalFunctions[name] = _G[name] end
        _G[name] = fn
    end
    local function noOp() end
    local function record(_, x, y, text)
        captures[#captures + 1] = text
        drawCalls[#drawCalls + 1] = { x = x, y = y, text = text, font = fontSize,
            width = textWidth(text, fontSize), align = textAlign }
        return 0
    end
    local function contains(text)
        for _, capture in ipairs(captures) do if capture == text then return true end end
        return false
    end
    local ok, err = pcall(function()
        check(metricFont >= 0, "生产NotoSansCJKkr-Bold真实字体加载")
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
            return textWidth(text, fontSize)
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

        replace("nvgTextAlign", function(_, value) textAlign = value end)
        replace("nvgRoundedRect", function(_, x, y, width, height)
            panelRects[#panelRects + 1] = { x = x, y = y, w = width, h = height }
        end)
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

        -- 小横屏正文最低14px，全文在窗口内；footer不是新增按钮，仍是全局tap推进契约。
        local letterCases = 0
        for _, metricMode in ipairs({ "spy", "Noto" }) do
        realMetrics = metricMode == "Noto"
        if realMetrics then
            check(textWidth("mmmm", 20) > 0 and math.abs(textWidth("mmmm", 20) - 48) > 0.01,
                "Noto真实字宽不走确定性估算")
        end
        for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            I18n.set(lang)
            local expected = {}
            for index, sourceLine in ipairs(letterSources) do
                if index ~= 6 then
                    local sourceText = index == 5 and (sourceLine .. letterSources[6]) or sourceLine
                    expected[#expected + 1] = Display.text(sourceText)
                end
            end
            for _, size in ipairs({ { 844, 390 }, { 1280, 720 }, { 1920, 1080 } }) do
                local width, height = size[1], size[2]
                local label = metricMode .. " " .. lang .. " " .. width .. "x" .. height
                Letter.reset()
                local completed = 0
                Letter.start(function() completed = completed + 1 end)
                for _ = 1, 7 do Letter.handleTap() end -- 第四段已全文揭示，尚未火漆/淡出。
                captures, drawCalls, panelRects = {}, {}, {}
                Letter.draw(realMetrics and metricContext or nil, width, height)
                local footer = Display.text("· 轻 触 翻 阅 ·")
                local rebuilt, body = {}, {}
                for _, call in ipairs(drawCalls) do
                    if call.text ~= footer then
                        rebuilt[#rebuilt + 1] = call.text
                        body[#body + 1] = call
                    end
                end
                check(table.concat(rebuilt) == table.concat(expected), label .. "全部11单元原序全文可访问")
                local panel = panelRects[1]
                check(panel ~= nil and panel.x >= 0 and panel.y >= 0
                    and panel.x + panel.w <= width and panel.y + panel.h <= height, label .. "信板窗口边界")
                local minFont, maxBottom = 100, 0
                for _, call in ipairs(body) do
                    local left = call.x - ((call.align & NVG_ALIGN_RIGHT) ~= 0 and call.width or 0)
                    local right = left + call.width
                    minFont = math.min(minFont, call.font)
                    maxBottom = math.max(maxBottom, call.y + call.font * 1.38)
                    check(call.font >= 14 and left >= panel.x and right <= panel.x + panel.w + 0.01
                        and call.y >= panel.y and call.y + call.font * 1.38 <= panel.y + panel.h,
                        label .. "每行14最低且字框不越板")
                end
                local footerSeen = false
                for _, call in ipairs(drawCalls) do
                    if call.text == footer then
                        footerSeen = true
                        check(call.y - call.font * 0.5 > maxBottom and call.y + call.font * 0.5 <= height
                            and call.x - call.width * 0.5 >= 0 and call.x + call.width * 0.5 <= width,
                            label .. "末尾翻阅提示完整且始终可达")
                    end
                end
                check(footerSeen, label .. "翻阅出口保留")
                if width == 844 then
                    local differentX = false
                    for _, call in ipairs(body) do
                        if (call.align & NVG_ALIGN_LEFT) ~= 0 and call.x > width * 0.5 then differentX = true end
                    end
                    check(differentX, label .. "小屏完整段分组双栏")
                end
                Letter.handleTap() -- 火漆
                Letter.handleTap() -- 淡出
                Letter.handleTap() -- 完成淡出
                Letter.update(1)
                Letter.update(1)
                check(completed == 1 and not Letter.isOpen(), label .. "出口tap/回调只一次")
                print(string.format("[letter-layout-spy] %s minFont=%.1f bodyBottom=%.1f panelBottom=%.1f",
                    label, minFont, maxBottom, panel.y + panel.h))
                letterCases = letterCases + 1
            end
        end
        end
        realMetrics = false
        check(letterCases == 30, "信件五语×三分辨率×spy/Noto共30布局回归（非实机截图）")

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
    nvgDelete(metricContext)
    I18n.set(originalLanguage)
    if not ok then
        print("[i18n_story_display_test] FAILED " .. tostring(err))
        log:Write(LOG_ERROR, "[i18n_story_display_test] " .. tostring(err))
    end
    engine:Exit()
end
