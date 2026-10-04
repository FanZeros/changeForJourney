-- 章节背景回归：真实关卡配置/选关绘制，图形与外部页面使用内存替身。
-- 不读写真实存档；覆盖每章取图、23章循环、终焉兼容、圆角cover与加载缓存。
function Start()
    local originalRequire, originalTime = require, time
    local savedGlobals = {}
    local assertions = 0
    local function check(ok, label)
        assertions = assertions + 1
        assert(ok, label)
    end
    local function near(a, b) return math.abs(a - b) < 0.000001 end
    local function noop() end
    local function hook(name, fn)
        savedGlobals[name] = _G[name]
        _G[name] = fn
    end
    local ok, err = pcall(function()
        local SC = originalRequire("config.StageConfig")
        local firstPath = "image/暗黑/L1_row1_forest.png"
        local lastPath = "image/战斗背景/烛龙之巢.png"
        for chapter = 1, SC.TOTAL_CHAPTERS do
            local path, relative = SC.getBattleBackground(chapter * 100 + 1)
            local expected = (chapter - 1) % 23 + 1
            local basePath = SC.getBattleBackground(expected * 100 + 1)
            check(relative == expected and path == basePath, "跨难度背景循环: " .. chapter)
        end
        check(SC.getBattleBackground(101) == firstPath, "首章使用战斗森林背景")
        check(SC.getBattleBackground(201) == "image/战斗背景/幽烬林地.png", "第二章使用幽烬林地")
        for _, entry in ipairs(SC.STAGES) do
            if SC.isTerminalTemple(entry.id) then
                local path, chapter = SC.getBattleBackground(entry.id)
                check(path == lastPath and chapter == 23, "终焉与既有三行战斗背景一致: " .. entry.id)
            end
        end
        check(SC.getBattleBackground(nil) == firstPath and SC.getBattleBackground("invalid") == firstPath,
            "未知关卡安全回退森林")

        local I18n = originalRequire("core.I18n")
        local initialLanguage = I18n.get()
        I18n.set("zh_CN")
        local currentStage, maxStage, jumps = 101, 305, 0
        local fixtures = {
            ["ui.battle.scene.BattleScene"] = {
                getStageId = function() return currentStage end,
                getMaxStageId = function() return maxStage end,
                getClearedStages = function() return {} end,
                gotoStage = function(id) currentStage = id; jumps = jumps + 1; return true end,
            },
            ["config.MonsterConfig"] = { getCardArtId = function(id) return id end, getName = function() return "怪物" end },
            ["config.StageRecommendPower"] = { get = function() return nil end },
            ["ui.battle.stage.BattleEnemySpawn"] = { getFirstClearBonusMonsterIds = function() return {} end },
            ["core.DarkIcon"] = { draw = noop },
            ["core.GameState"] = { getPower = function() return 0 end },
            ["core.I18n"] = I18n,
            ["systems.ButtonFeedback"] = { trigger = noop },
        }
        local events, images, loads, deleted = {}, {}, {}, {}
        local shape, paint = {}, nil
        local nextImage = 0
        local failPath, zeroSizePath, zeroHandlePath = nil, nil, nil
        local texts = {}
        fixtures["core.DrawUtil"] = {
            drawImageCentered = noop, drawImageCover = noop, drawNineSlice = noop,
            drawTextStroke = function(_, _, _, text)
                -- 绘图spy模拟生产文字出口的翻译hook；标题排版仍走真实I18n接口。
                local caption = I18n.lookup(text)
                texts[#texts + 1] = caption
                events[#events + 1] = { text = caption }
            end,
        }
        require = function(name) return fixtures[name] or originalRequire(name) end
        time = { elapsedTime = 20 }
        for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgTranslate", "nvgScale", "nvgIntersectScissor",
            "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgStrokeColor", "nvgStrokeWidth" }) do hook(name, noop) end
        hook("nvgTextBounds", function(_, _, _, text) return utf8.len(text) * 12 end)
        hook("nvgCreateImage", function(_, path)
            loads[path] = (loads[path] or 0) + 1
            if path == failPath then return -1 end
            if path == zeroHandlePath then images[0] = path; return 0 end
            nextImage = nextImage + 1
            images[nextImage] = path
            return nextImage
        end)
        hook("nvgDeleteImage", function(_, image) deleted[image] = true end)
        hook("nvgImageSize", function(_, image)
            if images[image] == zeroSizePath then return 0, 0 end
            return 1896, 720
        end)
        hook("nvgImagePattern", function(_, x, y, w, h, _, image)
            return { x = x, y = y, w = w, h = h, path = images[image] }
        end)
        hook("nvgBeginPath", function() shape, paint = {}, nil end)
        hook("nvgRect", function(_, x, y, w, h) shape = { x = x, y = y, w = w, h = h } end)
        hook("nvgRoundedRect", function(_, x, y, w, h, radius)
            shape = { x = x, y = y, w = w, h = h, radius = radius }
        end)
        hook("nvgFillPaint", function(_, value) paint = value end)
        hook("nvgFillColor", function() paint = nil end)
        hook("nvgFill", function() events[#events + 1] = { shape = shape, paint = paint } end)
        hook("nvgStroke", function() events[#events + 1] = { stroke = shape } end)
        hook("nvgText", function(_, _, _, text) texts[#texts + 1] = text end)
        local Dialog = originalRequire("ui.battle.stage.StageSelectDialog")
        local function draw()
            events, texts = {}, {}
            Dialog.draw({})
            local banners = {}
            for _, e in ipairs(events) do
                if e.paint and e.shape.x == 105 and e.shape.w == 190 then banners[#banners + 1] = e end
            end
            return banners
        end
        Dialog.init({})
        Dialog.open()
        time.elapsedTime = 21
        local banners = draw()
        check(#banners == 7, "七个可见章节均显示真实背景")
        for i, banner in ipairs(banners) do
            check(banner.paint.path == SC.getBattleBackground(i * 100 + 1), "卡片取自身章节而非当前关: " .. i)
            check(banner.shape.radius == 12 and banner.shape.h == 84, "图片填充圆角卡片: " .. i)
            check(near(banner.paint.w / banner.paint.h, 1896 / 720) and banner.paint.w >= 190
                and banner.paint.h >= 84, "cover保持比例并铺满: " .. i)
            check(near(banner.paint.x + banner.paint.w * 0.5, 200)
                and near(banner.paint.y + banner.paint.h * 0.5, banner.shape.y + 42), "cover居中裁切: " .. i)
        end
        check(events[1].text == "选择关卡" and texts[2] == SC.getChapterName(1), "弹窗标题与章节名保留")
        for _, language in ipairs({ "zh_TW", "en", "ja", "ko" }) do
            I18n.set(language)
            check(#draw() == 7, language .. "显示语言不改变章节背景")
            local captions = {}
            for _, text in ipairs(texts) do captions[text] = true end
            check(captions[I18n.lookup("选择关卡")], language .. "弹窗标题保持翻译")
            check(captions[I18n.lookup("1 章")], language .. "章节编号保持翻译")
        end
        I18n.set("zh_CN")
        draw()
        local firstFill, selectedStroke = nil, nil
        for i, event in ipairs(events) do
            if event.paint and event.shape.x == 105 and not firstFill then firstFill = i end
            if event.stroke and event.stroke.x == 105 and not selectedStroke then selectedStroke = i end
        end
        check(firstFill and selectedStroke and selectedStroke > firstFill, "选中金框绘制于背景之后")
        draw()
        check(loads[firstPath] == 1, "重复绘制命中缓存，不每帧创建图片")
        -- 普通23章后另有终焉组，困难首章在列表第25项。
        Dialog.handleScroll(-24, 175, 900)
        banners = draw()
        check(banners[1].paint.path == firstPath and loads[firstPath] == 1,
            "困难首章复用普通首章图片缓存")
        Dialog.handleInput(175, 880)
        draw()
        local hardCaptions = {}
        for _, text in ipairs(texts) do hardCaptions[text] = true end
        check(hardCaptions["24 章"] and hardCaptions["24-4"],
            "困难选关章节与第四关保持连续编号24-4")
        check(currentStage == 101 and maxStage == 305 and jumps == 0,
            "查看困难编号不改变实际进度或解锁")
        Dialog.handleScroll(24, 175, 900)
        Dialog.handleInput(175, 970)
        check(jumps == 0, "点背景卡片仅切章节，不跳关")
        Dialog.handleInput(370, 820)
        check(currentStage == 201 and jumps == 1 and not Dialog.isOpen(), "原关卡点击仍可前往并关闭")

        Dialog.init({})
        check(next(deleted) ~= nil, "重新初始化释放已缓存章节图片")
        currentStage = 101
        failPath = firstPath
        Dialog.open()
        time.elapsedTime = 22
        banners = draw()
        check(#banners == 6, "图片缺失时仅该章回退底色，其余章节正常")
        local attempts = loads[firstPath]
        draw()
        check(loads[firstPath] == attempts, "失败重试限频，避免每帧重复加载")
        failPath = nil
        time.elapsedTime = 25
        banners = draw()
        check(#banners == 7 and loads[firstPath] == attempts + 1, "资源恢复后重试，不永久缓存失败")
        zeroSizePath = firstPath
        check(#draw() == 6, "图片尺寸无效安全回退底色，不除零")
        Dialog.close()
        zeroSizePath, zeroHandlePath = nil, firstPath
        Dialog.init({})
        currentStage = 101
        Dialog.open()
        time.elapsedTime = 26
        banners = draw()
        check(#banners == 7 and banners[1].paint.path == firstPath, "合法句柄0仍绘制背景")
        local zeroAttempts = loads[firstPath]
        draw()
        check(loads[firstPath] == zeroAttempts, "句柄0命中缓存不重复加载")
        Dialog.close()
        Dialog.init({})
        check(deleted[0] == true, "重新初始化也释放句柄0")
        I18n.set(initialLanguage)
        print("[stage_chapter_background_test] ALL PASS: " .. assertions .. " assertions")
    end)
    require, time = originalRequire, originalTime
    for name, value in pairs(savedGlobals) do _G[name] = value end
    if not ok then print("[stage_chapter_background_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
