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
        local texts, textRecords, cardDraws = {}, {}, {}
        local clip, clipStack = nil, {}
        local fontSize, transformScale = 24, 1
        local function copyClip(value)
            if not value then return nil end
            return { x = value.x, y = value.y, w = value.w, h = value.h }
        end
        fixtures["core.DrawUtil"] = {
            drawImageCentered = noop, drawNineSlice = noop,
            drawImageCover = function(_, image, x, y, w, h)
                cardDraws[#cardDraws + 1] = { path = images[image], x = x, y = y, w = w, h = h,
                    clip = copyClip(clip) }
            end,
            drawTextStroke = function(_, x, y, text, size)
                -- 绘图spy模拟生产文字出口的翻译hook；标题排版仍走真实I18n接口。
                local caption = I18n.lookup(text)
                texts[#texts + 1] = caption
                textRecords[#textRecords + 1] = { text = caption, x = x, y = y, size = size,
                    clip = copyClip(clip) }
                events[#events + 1] = { text = caption }
            end,
        }
        require = function(name) return fixtures[name] or originalRequire(name) end
        time = { elapsedTime = 20 }
        for _, name in ipairs({ "nvgTranslate",
            "nvgFontFace", "nvgTextAlign", "nvgStrokeColor", "nvgStrokeWidth" }) do hook(name, noop) end
        hook("nvgScale", function(_, x) transformScale = transformScale * x end)
        hook("nvgResetTransform", function() transformScale = 1 end)
        hook("nvgSave", function()
            clipStack[#clipStack + 1] = { clip = copyClip(clip), scale = transformScale }
        end)
        hook("nvgRestore", function()
            local saved = table.remove(clipStack)
            check(saved ~= nil, "绘制状态成对恢复")
            clip, transformScale = saved.clip, saved.scale
        end)
        hook("nvgIntersectScissor", function(_, x, y, w, h)
            if clip then
                local right, bottom = math.min(x + w, clip.x + clip.w), math.min(y + h, clip.y + clip.h)
                x, y = math.max(x, clip.x), math.max(y, clip.y)
                w, h = math.max(0, right - x), math.max(0, bottom - y)
            end
            clip = { x = x, y = y, w = w, h = h }
        end)
        hook("nvgFontSize", function(_, size) fontSize = size end)
        hook("nvgTextBounds", function(_, _, _, text)
            local minPixelScale = math.max(1, 0.3 / transformScale)
            return utf8.len(text) * fontSize * 0.75 * minPixelScale
        end)
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
            events, texts, textRecords, cardDraws = {}, {}, {}, {}
            Dialog.draw({})
            check(#clipStack == 0 and clip == nil, "弹窗绘制不泄漏裁剪状态")
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
        local hasFirstChapter = false
        for _, caption in ipairs(texts) do
            if caption == SC.getChapterName(1) then hasFirstChapter = true end
        end
        check(events[1].text == "选择关卡" and hasFirstChapter, "弹窗标题与章节名保留")
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

        -- 用正式首通附加怪规则覆盖4/5/6种敌人，不改关卡配置或存档。
        local capturedSpawn = fixtures["ui.battle.stage.BattleEnemySpawn"]
        local spawn = originalRequire("ui.battle.stage.BattleEnemySpawn")
        -- 模块已捕获旧替身；转发正式方法，避免重载页面或修改生产配置。
        capturedSpawn.getFirstClearBonusMonsterIds = spawn.getFirstClearBonusMonsterIds
        zeroHandlePath = nil
        maxStage = 32305
        local function openAt(id)
            Dialog.close()
            currentStage = id
            Dialog.open()
            time.elapsedTime = time.elapsedTime + 1
            draw()
        end
        local function rowCards(row)
            local result = {}
            local cy = 790 + (row - 1) * 178 + 62
            for _, card in ipairs(cardDraws) do
                if near(card.y, cy) then result[#result + 1] = card end
            end
            return result
        end
        local function drag(x0, y0, x1, y1)
            Dialog.handleDragBegin(x0, y0)
            Dialog.handleDragMove(x1, y1)
            Dialog.handleDragEnd()
            -- 宿主可能误判往返/慢拖为tap，页面本身也必须消费。
            Dialog.handleInput(x1, y1)
            draw()
        end
        openAt(32301)
        local rows = rowCards(5)
        check(#rows == 6, "32305普通怪/Boss/两名附加怪共六种")
        check(#rowCards(3) == 4 and #rowCards(1) == 3, "四种和三种敌人完整保留")
        local initialX, beforeJumps = rows[1].x, jumps
        local countsBefore = {}
        for _, text in ipairs(textRecords) do
            if text.text:match("^x%d+$") then countsBefore[#countsBefore + 1] = text.text end
        end
        local row5Y = 790 + 4 * 178
        Dialog.handleDragBegin(700, row5Y + 62)
        Dialog.handleScroll(-1, 700, row5Y + 62)
        Dialog.handleDragMove(680, row5Y + 62)
        draw()
        check(near(rowCards(5)[1].x, initialX - 120), "按住后滚轮与首次左拖累加")
        Dialog.handleScroll(1, 680, row5Y + 62)
        Dialog.handleDragMove(670, row5Y + 62)
        draw()
        check(near(rowCards(5)[1].x, initialX - 30), "拖动中滚轮与增量拖动不跳回")
        Dialog.handleScroll(-99, 670, row5Y + 62)
        Dialog.handleDragMove(690, row5Y + 62)
        draw()
        check(near(rowCards(5)[1].x, initialX - 140), "滚轮到右端后反向拖动立即响应")
        Dialog.handleScroll(-1, 700, 790 + 62)
        Dialog.handleScroll(-1, 400, row5Y + 62)
        draw()
        check(near(rowCards(1)[1].x, initialX) and near(rowCards(5)[1].x, initialX - 140),
            "滚短列表或标签不改变被拖行偏移")
        Dialog.handleDragEnd()
        Dialog.handleInput(690, row5Y + 62)
        check(jumps == beforeJumps and Dialog.isOpen(), "混用滚轮拖动松手不误选关")
        Dialog.handleScroll(99, 700, row5Y + 62)
        draw()
        check(near(rowCards(5)[1].x, initialX), "滚轮左端钳制不产生空白")
        drag(700, row5Y + 62, 630, row5Y + 62)
        rows = rowCards(5)
        check(near(rows[1].x, initialX - 70), "横拖按实际X位移滚动")
        check(rowCards(3)[1].x == initialX and rowCards(1)[1].x == initialX,
            "每行偏移独立，邻行不被平移")
        check(jumps == beforeJumps and Dialog.isOpen(), "横拖不切关也不关闭弹窗")
        for _, card in ipairs(rows) do
            check(card.clip.x == 455 and card.clip.w == 436 and card.clip.y == row5Y + 6,
                "卡片固定裁剪不侵入左标签或邻行")
        end
        local countsAfter = {}
        for _, text in ipairs(textRecords) do
            if text.text:match("^x%d+$") then
                countsAfter[#countsAfter + 1] = text.text
                check(text.clip.x == 455 and text.clip.w == 436, "数量共用卡片区裁剪")
            end
        end
        check(table.concat(countsBefore, ",") == table.concat(countsAfter, ","), "滚动不改变敌人计数")
        drag(700, row5Y + 62, -1000, row5Y + 62)
        rows = rowCards(5)
        check(near(rows[1].x, initialX - 160) and near(rows[6].x + 46, 889),
            "右端夹紧，末卡及右边框完整留在视口内")
        drag(600, row5Y + 62, 2000, row5Y + 62)
        check(near(rowCards(5)[1].x, initialX), "左端夹紧，无空白过拖")
        Dialog.handleDragBegin(700, row5Y + 62)
        Dialog.handleDragMove(550, row5Y + 62)
        Dialog.handleDragMove(700, row5Y + 62)
        Dialog.handleDragEnd()
        Dialog.handleInput(700, row5Y + 62)
        check(jumps == beforeJumps and Dialog.isOpen(), "往返拖回原点仍消费误tap")
        draw()
        check(near(rowCards(5)[1].x, initialX), "往返拖回原偏移")
        drag(700, row5Y + 62, 702, row5Y - 30)
        check(near(rowCards(5)[1].x, initialX) and jumps == beforeJumps,
            "纵向拖出敌人区不滚横轴、不误切关")
        drag(700, 790 + 62, 550, 790 + 62)
        check(near(rowCards(1)[1].x, initialX), "不足视口宽度的敌人行不滚动")
        drag(700, row5Y + 62, 630, row5Y + 62)
        Dialog.handleInput(175, 836 + 94 + 40)
        draw()
        Dialog.handleInput(175, 880)
        draw()
        check(near(rowCards(5)[1].x, initialX), "切换章节再返回清零横向偏移")
        drag(700, row5Y + 62, 630, row5Y + 62)
        openAt(32301)
        check(near(rowCards(5)[1].x, initialX), "关闭重开清零横向偏移")
        maxStage = 101
        draw()
        drag(700, row5Y + 62, 630, row5Y + 62)
        check(near(rowCards(5)[1].x, initialX - 70) and jumps == beforeJumps,
            "未解锁关卡仍能查看完整敌人但不能切关")
        maxStage = 32305
        Dialog.handleDragBegin(700, row5Y + 62)
        Dialog.handleDragMove(704, row5Y + 63)
        Dialog.handleDragEnd()
        Dialog.handleInput(704, row5Y + 63)
        check(currentStage == 32305 and jumps == beforeJumps + 1 and not Dialog.isOpen(),
            "下一次短点击正常切关，不被上次拖动锁存吞掉")

        -- 真实配置自动找到五种敌人的行，验证宽度计算不只适配六张。
        local fiveStage
        for _, entry in ipairs(SC.STAGES) do
            if not SC.isTerminalTemple(entry.id) then
                local seen = {}
                for _, id in ipairs(entry.monsters or {}) do seen[id] = true end
                if entry.bossId and entry.bossId > 0 then seen[entry.bossId] = true end
                for _, id in ipairs(spawn.getFirstClearBonusMonsterIds(entry) or {}) do seen[id] = true end
                local count = 0
                for _ in pairs(seen) do count = count + 1 end
                if count == 5 then fiveStage = entry; break end
            end
        end
        check(fiveStage ~= nil, "存在五种敌人的正式关卡夹具")
        openAt(fiveStage.id)
        local row = fiveStage.stage
        local rowY = 790 + (row - 1) * 178
        check(#rowCards(row) == 5, "五种敌人全部参与横排")
        drag(700, rowY + 62, -1000, rowY + 62)
        check(near(rowCards(row)[1].x, initialX - 60), "五张卡含描边右端精确夹紧60像素")
        Dialog.handleDragBegin(700, rowY + 62)
        Dialog.handleDragMove(400, rowY + 62)
        Dialog.handleDragMove(420, rowY + 62)
        Dialog.handleDragEnd()
        Dialog.handleInput(420, rowY + 62)
        draw()
        check(near(rowCards(row)[1].x, initialX - 40), "超出端点后回拖20像素立即响应")
        local fiveJumps = jumps
        Dialog.handleDragBegin(600, 790 + 62)
        Dialog.handleDragMove(500, 790 + 62)
        Dialog.handleDragMove(600, 790 + 62)
        Dialog.handleDragEnd()
        Dialog.handleInput(600, 790 + 62)
        check(jumps == fiveJumps and Dialog.isOpen(), "短列表往返拖动也不误选关")

        -- 完整五语说明必须在终焉行下方、使用宽栏折行且不进入敌人clip。
        local sources = {
            "最多三队一起上场，不必三队全部存活。",
            "同编号敌人跨队共享生命，击败全部三名敌人即可通关。",
            "限时 %d 秒；全部参战队伍失守或超时则失败。",
            "胜利进入下一难度，失败退回本难度最后一关。",
        }
        for _, language in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            I18n.set(language)
            Dialog.close()
            currentStage = 999
            Dialog.open()
            -- 动画首帧先测宽；若缓存受最小像素字号影响，后面稳定帧会窄折行/越底。
            time.elapsedTime = time.elapsedTime + 0.005
            draw()
            time.elapsedTime = time.elapsedTime + 1
            draw()
            local joined = ""
            for _, text in ipairs(textRecords) do
                if text.y > 958 and text.x >= 315 then
                    check(text.x == 331 and text.y + text.size * 0.5 < 1680,
                        language .. "说明放行下且完整位于面板内")
                    check(text.clip.x == 315 and text.clip.w == 580,
                        language .. "说明不受敌人窄栏裁剪")
                    check(utf8.len(text.text) * text.size * 0.75 <= 548,
                        language .. "每行测宽不越栏")
                    joined = joined .. text.text
                end
            end
            joined = joined:gsub("%s", "")
            for i, source in ipairs(sources) do
                local translated = i == 3 and I18n.format(source, 300) or I18n.lookup(source)
                check(joined:find(translated:gsub("%s", ""), 1, true) ~= nil,
                    language .. "完整呈现规则段" .. i)
                if language ~= "zh_CN" then
                    check(I18n.lookup(source) ~= source, language .. "规则有正式翻译" .. i)
                end
            end
            check(not joined:find("可三队一起上场", 1, true), "移除旧窄行说明")
        end
        -- 资源列表与主线章节分离；选关行队号进入副本时必须原样保留。
        local resourceSelections = {}
        local acceptResource = true
        local dispatcher = { get = function(key)
            if key == "dungeon" then return {} end
            return { maxStageId = maxStage }
        end }
        fixtures["runtime.ClientDispatcher"] = dispatcher
        local resourceModule = originalRequire("ui.battle.stage.StageSelectResources")
        local realDispatcher = originalRequire("runtime.ClientDispatcher")
        local savedGet = realDispatcher.get
        realDispatcher.get = dispatcher.get
        Dialog.setOnDungeonSelect(function(id, teamIdx)
            resourceSelections[#resourceSelections + 1] = { id = id, teamIdx = teamIdx }
            return acceptResource
        end)
        fixtures["ui.battle.tri.BattleTriPage"] = { getTeamStageId = function() return 101 end }
        for _, teamIdx in ipairs({ 1, 2, 3 }) do
            for index, id in ipairs({ "gold_mine", "equipment_vault", "black_diamond", "babel_tower" }) do
                Dialog.close()
                Dialog.open(teamIdx)
                time.elapsedTime = time.elapsedTime + 1
                local before = jumps
                Dialog.handleInput(635, 686)
                draw()
                local y = index < 4 and (836 + (index - 1) * 190 + 70) or (1434 + 70)
                Dialog.handleScroll(-99, 175, 900)
                Dialog.handleInput(500, y)
                local selection = resourceSelections[#resourceSelections]
                check(selection.id == id and selection.teamIdx == teamIdx,
                    "选关副本路由锁定队号: " .. id .. "/" .. teamIdx)
                check(jumps == before and not Dialog.isOpen(), "副本导航不调用主线跳关且关闭旧弹窗")
            end
        end
        Dialog.open(2)
        time.elapsedTime = time.elapsedTime + 1
        Dialog.handleInput(635, 686)
        acceptResource = false
        local beforeSelections = #resourceSelections
        Dialog.handleInput(500, 900)
        check(Dialog.isOpen() and #resourceSelections == beforeSelections + 1,
            "锁定或拒绝进入副本时保留选关列表")
        Dialog.handleDragBegin(500, 900)
        Dialog.handleDragMove(500, 980)
        Dialog.handleDragMove(500, 900)
        Dialog.handleDragEnd()
        Dialog.handleInput(500, 900)
        check(#resourceSelections == beforeSelections + 1, "副本卡往返拖动不误点击")
        Dialog.handleInput(445, 686)
        check(#draw() == 7, "切回主线恢复原章节列表")
        Dialog.close()
        Dialog.open()
        Dialog.handleInput(635, 686)
        acceptResource = true
        Dialog.handleInput(500, 900)
        check(resourceSelections[#resourceSelections].teamIdx == 1, "普通选关默认资源队伍一")
        for _, language in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            I18n.set(language)
            Dialog.open()
            Dialog.handleInput(635, 686)
            time.elapsedTime = time.elapsedTime + 1
            draw()
            local captions = {}
            for _, caption in ipairs(texts) do captions[caption] = true end
            for _, source in ipairs({ "金币副本", "装备副本", "黑钻副本", "通天塔" }) do
                check(captions[I18n.lookup(source)], language .. "副本入口有完整名称: " .. source)
            end
            Dialog.close()
        end
        realDispatcher.get = savedGet
        resourceModule.release({})
        I18n.set(initialLanguage)
        print("[stage_chapter_background_test] ALL PASS: " .. assertions .. " assertions")
    end)
    require, time = originalRequire, originalTime
    for name, value in pairs(savedGlobals) do _G[name] = value end
    if not ok then print("[stage_chapter_background_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
