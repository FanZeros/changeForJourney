-- 首批 i18n 回归：四语全关卡、源数据不变、占位符、测量hook与缓存护栏。
local passed, failed = 0, 0
local function check(ok, name)
    if ok then
        passed = passed + 1
        print("[PASS] " .. name)
    else
        failed = failed + 1
        print("[FAIL] " .. name)
    end
end

function Start()
    local calls = {}
    local bounds = { 1, 2, 3, 4 }
    nvgText = function(_, _, _, text) calls.text = text; return 17 end
    nvgTextBox = function(_, _, _, width, text) calls.box = text; calls.width = width end
    nvgTextBounds = function(_, _, _, text, ...)
        calls.measure = text
        calls.measureArgs = table.pack(...)
        return #text, bounds
    end
    nvgTextBoxBounds = function(_, _, _, width, text, ...)
        calls.boxMeasure = text
        calls.boxMeasureArgs = table.pack(...)
        calls.measureWidth = width
        return bounds
    end
    nvgFontFace = function() end
    nvgFontSize = function() end
    nvgTextAlign = function() end
    nvgFillColor = function() end
    nvgRGBA = function() return 0 end

    local base = require("core.I18nDict")
    base.en["空译文测试"] = ""
    local I18n = require("core.I18n")
    local StageText = require("core.I18nStages")
    local SC = require("config.StageConfig")
    check(#SC.STAGES == 1739, "关卡集合1739条，含14座终焉神殿")
    check(#StageText.REGIONS == 23 and #StageText.DIFFICULTIES == 15, "23地名与15难度")
    local snapshot = {}
    for _, entry in ipairs(SC.STAGES) do
        snapshot[entry.id] = { name = entry.name, chapter = entry.chapter, stage = entry.stage,
            difficulty = entry.difficulty, monsters = table.concat(entry.monsters, ",") }
    end
    local langs = { "zh_TW", "en", "ja", "ko" }
    local checked = 0
    check(SC.getStageDisplayName(104) == "黑棘林道1-4", "普通关卡编号保持1-4")
    check(SC.getStageDisplayName(2404) == "困难·黑棘林道24-4", "困难全名显示连续24-4")
    check(SC.formatProgressDisplay(2404) == "困难24-4", "困难进度显示连续24-4")
    check(SC.getStageDisplayName("2404") == SC.getStageDisplayName(2404), "字符串关卡ID显示一致")
    check(SC.getStageDisplayName(nil) == "?" and SC.getStageDisplayName("无效") == "无效",
        "未知关卡全名安全回退")
    check(SC.formatProgressDisplay(0) == "普通1-1" and SC.formatProgressDisplay(-1) == "普通1-1",
        "未知进度沿用原回退")
    check(SC.getRelativeChapter(24) == 1 and SC.getRelativeChapter(27) == 4,
        "显示调整不改变业务相对章数")
    check(SC.getFirstClearSacredStone(2405) == 0 and SC.getFirstClearSacredStone(2705) == 1,
        "困难神圣石仍按难度内每四章发放")
    local Tasks = require("config.TaskConfig")
    local hardTask
    for _, task in ipairs(Tasks.ACHIEVEMENT) do
        if task.id == "a_clear_2405" then hardTask = task; break end
    end
    check(hardTask and hardTask.desc == "通关困难24-5" and hardTask.stageId == 2405
        and hardTask.condKey == "clear_2405" and hardTask.target == 1,
        "功绩显示连续编号且任务条件不变")
    for _, lang in ipairs(langs) do
        I18n.set(lang)
        local missing, wrong, displayWrong = 0, 0, 0
        for _, entry in ipairs(SC.STAGES) do
            local expected = StageText.lookup(entry.name, lang)
            local actual = tostring(I18n.lookup(entry.name))
            if not expected or expected == "" then missing = missing + 1 end
            if actual ~= expected or string.find(actual, "{", 1, true) then wrong = wrong + 1 end
            local name = SC.getStageDisplayName(entry.id)
            local progress = SC.formatProgressDisplay(entry.id)
            if SC.isTerminalTemple(entry.id) then
                if name ~= entry.name or progress ~= entry.name then displayWrong = displayWrong + 1 end
            else
                local suffix = tostring(entry.chapter) .. "-" .. tostring(entry.stage)
                local baseName = entry.name:match("^(.-)%d+%-%d+$")
                local prefix = SC.getDifficultyDisplayName(SC.getDifficulty(entry.id))
                if name ~= baseName .. suffix or progress ~= prefix .. suffix
                    or I18n.lookup(name) ~= StageText.lookup(name, lang)
                    or I18n.lookup(progress) ~= StageText.lookup(progress, lang) then
                    displayWrong = displayWrong + 1
                end
            end
            checked = checked + 1
        end
        check(missing == 0 and wrong == 0, lang .. "全部1739关名模板与显示入口一致")
        check(displayWrong == 0, lang .. "全部1739关显示连续章号、翻译与终焉名称一致")
        for _, region in ipairs(StageText.REGIONS) do
            local translated = StageText.lookup(region, lang)
            check(type(translated) == "string" and translated ~= "", lang .. "地名完整: " .. region)
        end
        check(I18n.lookup("终焉神殿·湮灭IV") == StageText.lookup("终焉神殿·湮灭IV", lang), lang .. "终焉后缀保留")
        check(I18n.lookup("折磨III·烛龙之巢23-5") == StageText.lookup("折磨III·烛龙之巢23-5", lang), lang .. "高难度前缀只出现一次")
        check(I18n.lookup("困难 01-05") == StageText.lookup("困难01-05", lang), lang .. "扫荡空格进度与前导零")
        I18n.installDrawHook()
        local firstHook = nvgTextBoxBounds
        I18n.installDrawHook()
        check(nvgTextBoxBounds ~= nil and firstHook == nvgTextBoxBounds, lang .. "hook重复安装幂等")
        local source = "困难·黑棘林道1-1"
        nvgText(nil, 5, 6, source, nil)
        check(calls.text == I18n.lookup(source), lang .. "绘制收到译文")
        nvgTextBox(nil, 5, 6, 200, source, nil)
        local measured = nvgTextBoxBounds(nil, 5, 6, 200, source, nil, bounds)
        check(measured == bounds and calls.box == calls.boxMeasure
            and calls.width == calls.measureWidth, lang .. "绘制测量同串同宽且返回bounds透传")
        check(calls.boxMeasureArgs.n == 2 and calls.boxMeasureArgs[2] == bounds, lang .. "bounds兼容重载尾参不丢失")
        local advance, reused = nvgTextBounds(nil, 0, 0, source, nil, bounds)
        check(advance > 0 and reused == bounds and calls.measureArgs[2] == bounds, lang .. "单行测量多返回值透传")
        check(I18n.lookup(I18n.lookup(source)) == I18n.lookup(source), lang .. "译文不重复翻译")
    end
    check(checked == 6956, "四语全量6956个关名组合逐项验证")

    I18n.set("en")
    check(I18n.difficulty("普通") == "Normal" and I18n.lookup("普通") == "Common", "难度Normal不污染品质Common")
    check(I18n.lookup("普通1-1") == "Normal 1-1", "普通进度使用Normal")
    check(I18n.lookup("黑棘林道01-05") == "Blackthorn Trail 01-05", "编号前导零保持")
    check(I18n.lookup("24 章") == "Chapter 24", "章节绝对章号保持")
    check(I18n.lookup("黑棘林道1-1奖励") == "黑棘林道1-1奖励", "不猜测额外后缀")
    check(I18n.lookup("image/黑棘林道1-1.png") == "image/黑棘林道1-1.png", "资源路径不翻译")
    check(I18n.lookup("未知地名1-1") == "未知地名1-1", "未知地名回退")
    check(I18n.lookup("空译文测试") == "空译文测试", "空译文安全回退")
    check(I18n.lookup(nil) == nil and I18n.lookup(0) == 0 and I18n.lookup("") == "", "空与非字符串输入原样保持")
    check(not I18n.set("unknown") and I18n.get() == "en", "未知语言不更改状态")
    local first, second = "50% {1}", "%1 {0}"
    check(I18n.interpolate("{0}|{1}|{0}", first, second) == first .. "|" .. second .. "|" .. first,
        "参数百分号与占位符不二次替换")
    check(I18n.interpolate("{0}/{1}/{10}", "", 0) == "/0/{10}", "空串零值与未知多位索引保持")
    check(I18n.t("level_not_enough_equip", "50% {0}") == "Level too low. Reach Lv.50% {0} to equip", "语义键参数原样替换")
    check(I18n.t("missing_key") == "missing_key", "未知语义键契约保持")
    check(I18n.format("套装 · %d", 3) == "Sets · 3", "printf模板先翻译再格式化")
    -- 富文本已经对完整串本地化，分段后必须绕过短词hook，绘制和度量仍完全同串。
    local rawSource = "资源加载中"
    local rawReturn = I18n.displayText(nil, 7, 8, rawSource, nil)
    check(calls.text == rawSource and rawReturn == 17, "displayText原样透传且保留返回值")
    local rawAdvance, rawBounds = I18n.displayBounds(nil, 7, 8, rawSource, nil, bounds)
    check(calls.measure == rawSource and rawAdvance == #rawSource and rawBounds == bounds,
        "displayBounds原样透传且保留多返回值")
    check(calls.measureArgs.n == 2 and calls.measureArgs[2] == bounds,
        "displayBounds边界重载尾参透传")
    nvgText(nil, 7, 8, rawSource, nil)
    check(calls.text == I18n.lookup(rawSource), "原样显示API不影响普通hook翻译")
    I18n.displayTextBox(nil, 7, 8, 230, rawSource, nil)
    local rawBoxBounds = I18n.displayTextBoxBounds(nil, 7, 8, 230, rawSource, nil, bounds)
    check(calls.box == rawSource and calls.boxMeasure == rawSource and calls.width == 230
        and calls.measureWidth == 230 and rawBoxBounds == bounds, "原样文本框绘制测量同串同宽")
    check(calls.boxMeasureArgs.n == 2 and calls.boxMeasureArgs[2] == bounds,
        "原样文本框边界重载尾参透传")

    local KeywordText = require("ui.widget.KeywordText")
    local kt = KeywordText.new()
    I18n.set("zh_CN")
    local chinese = kt:_layout(nil, "回响", 200, 24)
    check(kt:_layout(nil, "回响", 200, 24) == chinese, "同语言布局命中缓存")
    kt.popup = { name = "回响", desc = "测试" }
    kt.hotspots = { { x1 = 0, y1 = 0, x2 = 10, y2 = 10, name = "回响" } }
    I18n.set("en")
    local english = kt:_layout(nil, "回响", 200, 24)
    check(english ~= chinese and kt.popup == nil and #kt.hotspots == 0, "切语言清旧布局弹窗与热区")
    I18n.set("ja")
    local japanese = kt:_layout(nil, "回响", 200, 24)
    check(japanese ~= english, "日语不复用英文布局")
    I18n.set("ko")
    check(kt:_layout(nil, "回响", 200, 24) ~= japanese, "韩语不复用日语布局")
    I18n.set("zh_CN")
    check(kt:_layout(nil, "回响", 200, 24) ~= chinese, "切回中文重新生成布局")
    kt:clear()
    check(next(kt._cache) == nil and #kt._cacheKeys == 0, "clear释放布局缓存")

    local changed, chineseChanged = 0, 0
    for _, entry in ipairs(SC.STAGES) do
        local old = snapshot[entry.id]
        if entry.name ~= old.name or entry.chapter ~= old.chapter or entry.stage ~= old.stage
            or entry.difficulty ~= old.difficulty or table.concat(entry.monsters, ",") ~= old.monsters then
            changed = changed + 1
        end
        if I18n.lookup(entry.name) ~= old.name then chineseChanged = chineseChanged + 1 end
    end
    check(chineseChanged == 0, "全部1739条中文显示保持原名")
    check(changed == 0, "语言切换不修改关卡业务数据")
    base.en["空译文测试"] = nil
    print(string.format("[i18n_foundation_test] passed=%d failed=%d combinations=%d", passed, failed, checked))
    if failed == 0 then print("I18N FOUNDATION: ALL PASS") end
    engine:Exit()
end
