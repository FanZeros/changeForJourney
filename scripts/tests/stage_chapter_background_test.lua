-- 章节背景回归：真实关卡配置/选关绘制，图形与外部页面使用内存替身。
-- 不读写真实存档；覆盖每章取图、23章循环、终焉兼容、圆角cover与加载缓存。
function Start()
    assert(fileSystem:GetCurrentDir():gsub("/+$", "") == "/home/Maker/game4-validation/stage-regression",
        "isolated stage regression cwd required")
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
        savedGlobals[name] = { value = _G[name] }
        _G[name] = fn
    end
    local ioAttempts = 0
    local function denied()
        ioAttempts = ioAttempts + 1
        error("native IO/network forbidden in chapter fixture")
    end
    -- 在任何生产require前阻断业务IO；只读模块加载由引擎resource cache完成。
    for _, name in ipairs({ "File", "GetFileSystem", "GetCache", "GetEngine", "loadfile", "dofile" }) do
        hook(name, denied)
    end
    for _, name in ipairs({ "cache", "fileSystem", "network", "clientCloud", "serverCloud", "io", "os" }) do
        hook(name, setmetatable({}, { __index = denied, __newindex = denied }))
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
        local monsterConfig = originalRequire("config.MonsterConfig")
        local selectResource = function() return false end
        local dispatcher = { get = function(key)
            if key == "battle" then return { maxStageId = maxStage } end
            return {}
        end }
        local fixtures = {
            ["ui.battle.scene.BattleScene"] = {
                getStageId = function() return currentStage end,
                getMaxStageId = function() return maxStage end,
                getClearedStages = function() return {} end,
                gotoStage = function(id) currentStage = id; jumps = jumps + 1; return true end,
            },
            -- TowerConfig读取真实怪物品质分池；不能用空表绕过其合法数据契约。
            ["config.MonsterConfig"] = { MONSTERS = monsterConfig.MONSTERS,
                getCardArtId = function(id) return id end, getName = function() return "怪物" end },
            ["runtime.ClientDispatcher"] = dispatcher,
            ["ui.battle.tri.BattleTriPage"] = {
                getTeamStageId = function() return currentStage end,
                gotoTeamStage = function(team, id)
                    if SC.isResourceStage(id) then
                        local dungeonId = originalRequire("config.DungeonConfig").decodeStageId(id)
                        return selectResource(dungeonId, team, id)
                    end
                    currentStage = id
                    jumps = jumps + 1
                    return true
                end,
                isTerminalRaidActive = function() return false end,
            },
            ["ui.hud.BottomNav"] = { isAllLocked = function() return false end,
                isTabLocked = function() return false end },
            ["ui.dungeon.DungeonBattleScene"] = { isOpen = function() return false end },
            ["ui.tower.TowerBattleScene"] = { isActive = function() return false end },
            ["ui.battle.stage.ExpeditionOverview"] = {}, -- 本专项不进入概览；禁止读真实英雄/离线账本。
            ["systems.TutorialManager"] = { registerHotspot = noop, notifyEvent = noop },
            ["config.StageRecommendPower"] = { get = function() return nil end },
            ["ui.battle.stage.BattleEnemySpawn"] = { getFirstClearBonusMonsterIds = function() return {} end },
            ["core.GameState"] = { getPower = function() return 0 end },
            ["core.I18n"] = I18n,
            ["systems.ButtonFeedback"] = { trigger = noop, begin = noop, finish = noop },
        }
        fixtures["core.DarkIcon"] = {
            draw = noop, drawQualityBg = noop,
            Palette = { GOLD_HI = { 240, 199, 94 }, BONE = { 216, 201, 163 }, BONE_DIM = { 150, 138, 110 } },
        }
        local events, loads = {}, {}
        local activeVg = {}
        local shape, paint = {}, nil
        local imageLoadsByVg, nextImageByVg, deletedByVg, wrongContextDeletes = {}, {}, {}, 0
        local imageDraws, deleteRecords = {}, {}
        local imagesByVg = {}
        local loadHook = noop
        local function activeImages(vg)
            return imagesByVg[vg] or {}
        end
        local function findHandle(vg, path)
            for handle, loadedPath in pairs(activeImages(vg)) do
                if loadedPath == path then return handle end
            end
            return nil
        end
        local function recordImage(vg, image, usage)
            local path = assert(activeImages(vg)[image], "unknown/deleted image in " .. usage)
            imageDraws[#imageDraws + 1] = { vg = vg, handle = image, path = path, usage = usage }
            return path
        end
        local function contextLoads(vg, path)
            return imageLoadsByVg[vg] and imageLoadsByVg[vg][path] or 0
        end
        local failPath, zeroSizePath, zeroHandlePath = nil, nil, nil
        local texts, textRecords, cardDraws = {}, {}, {}
        local clip, clipStack = nil, {}
        local fontSize, transformScale = 24, 1
        local function copyClip(value)
            if not value then return nil end
            return { x = value.x, y = value.y, w = value.w, h = value.h }
        end
        fixtures["core.DrawUtil"] = {
            drawImageCentered = function(vg, image) recordImage(vg, image, "centered") end,
            drawNineSlice = function(vg, image) recordImage(vg, image, "panel") end,
            drawImageCover = function(vg, image, x, y, w, h)
                cardDraws[#cardDraws + 1] = { path = recordImage(vg, image, "monster"), x = x, y = y, w = w, h = h,
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
        hook("nvgCreateImage", function(vg, path)
            -- 句柄只在各自VG内递增，两个VG允许返回完全相同的整数。
            loadHook(vg, path)
            local byVg = imagesByVg[vg]
            if not byVg then byVg = {}; imagesByVg[vg] = byVg end
            local nextByVg = nextImageByVg[vg] or 0
            loads[path] = (loads[path] or 0) + 1
            local perVgLoads = imageLoadsByVg[vg]
            if not perVgLoads then perVgLoads = {}; imageLoadsByVg[vg] = perVgLoads end
            perVgLoads[path] = (perVgLoads[path] or 0) + 1
            if path == failPath then return -1 end
            if path == zeroHandlePath then byVg[0] = path; return 0 end
            nextByVg = nextByVg + 1
            nextImageByVg[vg] = nextByVg
            byVg[nextByVg] = path
            return nextByVg
        end)
        hook("nvgDeleteImage", function(vg, image)
            vg = assert(vg, "missing NanoVG deletion context")
            local path = activeImages(vg)[image]
            if path == nil then wrongContextDeletes = wrongContextDeletes + 1 end
            local byVg = deletedByVg[vg]
            if not byVg then byVg = {}; deletedByVg[vg] = byVg end
            byVg[image] = true
            deleteRecords[#deleteRecords + 1] = { vg = vg, handle = image, path = path }
            if imagesByVg[vg] then imagesByVg[vg][image] = nil end
        end)
        hook("nvgImagePattern", function(vg, x, y, w, h, _, image)
            return { x = x, y = y, w = w, h = h, path = recordImage(vg, image, "background") }
        end)
        hook("nvgImageSize", function(vg, image)
            local path = assert(activeImages(vg)[image], "unknown/deleted image in size query")
            if path == zeroSizePath then return 0, 0 end
            return 1896, 720
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
        local RewardPreviewCache = originalRequire("ui.battle.stage.StageSelectRewardPreview")
        local function draw(vg)
            events, texts, textRecords, cardDraws, imageDraws = {}, {}, {}, {}, {}
            Dialog.draw(vg or activeVg)

            check(#clipStack == 0 and clip == nil, "弹窗绘制不泄漏裁剪状态")
            local banners = {}
            for _, e in ipairs(events) do
                if e.paint and e.shape.x == 105 and e.shape.w == 190 then banners[#banners + 1] = e end
            end
            return banners
        end
        Dialog.init(activeVg)
        Dialog.open()
        time.elapsedTime = 21
        local banners = draw()
        local bgAHandle = findHandle(activeVg, firstPath)
        local btnAHandle = findHandle(activeVg, "image/通用图标/UI_ICON_XG.png")
        local rewardAPath = "image/测试/跨context奖励.png"
        RewardPreviewCache.draw(activeVg, { quality = 1, iconPath = rewardAPath,
            amount = 1, isEstimate = true }, 0, 0, 420, 34, false)
        local rewardAHandle = findHandle(activeVg, rewardAPath)
        check(bgAHandle ~= nil and btnAHandle ~= nil and rewardAHandle ~= nil,
            "两个VG局部缓存夹具先在旧context创建真实句柄")
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
        check(events[1].text == "队伍 1 · 选择关卡" and hasFirstChapter, "弹窗标题与章节名保留")
        for _, language in ipairs({ "zh_TW", "en", "ja", "ko" }) do
            I18n.set(language)
            check(#draw() == 7, language .. "显示语言不改变章节背景")
            local captions = {}
            for _, text in ipairs(texts) do captions[text] = true end
            check(captions[I18n.lookup("队伍 1 · 选择关卡")], language .. "弹窗标题保持翻译")
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
        Dialog.handleInput(175, 920)
        draw()
        local hardCaptions = {}
        for _, text in ipairs(texts) do hardCaptions[text] = true end
        check(hardCaptions["24 章"] and hardCaptions["24-4"],
            "困难选关章节与第四关保持连续编号24-4")
        check(currentStage == 101 and maxStage == 305 and jumps == 0,
            "查看困难编号不改变实际进度或解锁")
        Dialog.handleScroll(24, 175, 900)
        Dialog.handleInput(175, 1010)
        check(jumps == 0, "点背景卡片仅切章节，不跳关")
        Dialog.handleInput(370, 820)
        check(currentStage == 201 and jumps == 1 and not Dialog.isOpen(), "原关卡点击仍可前往并关闭")

        local buttonPath = "image/通用图标/UI_ICON_XG.png"
        local panelPath = "image/界面底板/通用面板/UI_TY_EJQRK.png"
        local function rewardDraw(vg, path)
            RewardPreviewCache.draw(vg, { quality = 1, iconPath = path,
                amount = 1, isEstimate = true }, 0, 0, 420, 34, false)
        end
        local function drawn(vg, path, usage)
            for _, record in ipairs(imageDraws) do
                if record.vg == vg and record.path == path and record.usage == usage then return true end
            end
            return false
        end
        -- 相同VG仍按原init释放章节与奖励缓存；monster缓存原来不重置。
        local vgA = activeVg
        local monsterPath = "image/怪物卡牌/KP_GW_" .. SC.getStage(101).monsters[1] .. ".png"
        local monsterAttempts = contextLoads(vgA, monsterPath)
        local deletesBefore = #deleteRecords
        Dialog.init(vgA)
        check(deletedByVg[vgA][bgAHandle] and deletedByVg[vgA][rewardAHandle]
            and #deleteRecords > deletesBefore, "同VG重新init释放已缓存章节与奖励图片")
        check(findHandle(vgA, firstPath) == nil and contextLoads(vgA, buttonPath) == 2,
            "同VG重新init保留静态图重请求与章节缓存重置契约")
        currentStage = 101
        Dialog.open()
        time.elapsedTime = 22
        check(#draw() == 7 and contextLoads(vgA, firstPath) == 2
            and contextLoads(vgA, monsterPath) == monsterAttempts,
            "同VG背景重载而怪物缓存维持原契约")
        rewardDraw(vgA, rewardAPath)
        check(contextLoads(vgA, rewardAPath) == 2, "同VG奖励重置后按路径重载")

        -- 新VG预先分配同号整数为其他路径：借用旧handle也许合法，但会画错纹理。
        local vgB = {}
        for i = 1, 40 do nvgCreateImage(vgB, "image/测试/contextB诱饵" .. i .. ".png", 0) end
        deletesBefore = #deleteRecords
        Dialog.init(vgB)
        check(#deleteRecords == deletesBefore and wrongContextDeletes == 0,
            "更换VG不在新旧context调用删除旧句柄")
        check(findHandle(vgB, firstPath) == nil and contextLoads(vgB, buttonPath) == 1,
            "新VG静态图按路径创建，章节保持懒加载")
        check(#draw(vgA) == 0, "新VG绑定后旧VG不能复用当前缓存绘制")
        activeVg = vgB
        check(#draw() == 7 and contextLoads(vgB, firstPath) == 1
            and contextLoads(vgB, monsterPath) == 1, "新VG背景和怪物卡按路径重新加载")
        Dialog.drawButton(vgB)
        check(drawn(vgB, panelPath, "panel") and drawn(vgB, buttonPath, "centered")
            and drawn(vgB, monsterPath, "monster"), "新VG实际绘制面板/按钮/怪物路径而非同号诱饵")
        rewardDraw(vgB, rewardAPath)
        check(contextLoads(vgB, rewardAPath) == 1 and drawn(vgB, rewardAPath, "centered"),
            "新VG奖励按路径加载并绘制，不要求跨VG整数号不同")
        rewardDraw(vgB, rewardAPath)
        check(contextLoads(vgB, rewardAPath) == 1 and #deleteRecords == deletesBefore,
            "新VG重复draw命中奖励缓存且无跨context释放")
        RewardPreviewCache.init(vgB)
        rewardDraw(vgB, rewardAPath)
        check(contextLoads(vgB, rewardAPath) == 2, "奖励同VG显式init仍重置缓存")
        local vgReward = {}
        rewardDraw(vgReward, rewardAPath)
        check(contextLoads(vgReward, rewardAPath) == 1 and drawn(vgReward, rewardAPath, "centered"),
            "奖励draw换VG即隔离，不依赖先显式init")

        -- 四个静态资源各让出一次；末项返回前按钮/弹窗不能假称就绪。
        local vgYield = {}
        loadHook = function(vg)
            if vg == vgYield and coroutine.isyieldable() then coroutine.yield("image") end
        end
        local worker = coroutine.create(function() Dialog.init(vgYield) end)
        for i = 1, 4 do
            local resumed, marker = coroutine.resume(worker)
            check(resumed and marker == "image" and coroutine.status(worker) == "suspended",
                "init合作式逐资源让出" .. i)
            imageDraws = {}
            Dialog.drawButton(vgYield)
            check(#draw(vgYield) == 0 and #imageDraws == 0,
                "资源尚未全返回时不发布完成" .. i)
        end
        check(coroutine.resume(worker) and coroutine.status(worker) == "dead", "init全部资源返回才完成")
        loadHook = noop
        activeVg = vgYield
        check(#draw() == 7 and contextLoads(vgYield, monsterPath) == 1, "合作式init完成后新VG正常绘制")
        Dialog.drawButton(vgYield)
        check(drawn(vgYield, buttonPath, "centered"), "合作式init最终发布正确按钮路径")

        -- 同VG重入及A→B→A：已让出的旧批次不得恢复后覆写最新静态图。
        for _, mode in ipairs({ "same", "cross", "aba" }) do
            local staleVg, latestVg = {}, {}
            if mode ~= "cross" then latestVg = staleVg end
            loadHook = function(vg)
                if vg == staleVg and coroutine.isyieldable() then coroutine.yield("stale") end
            end
            local stale = coroutine.create(function() Dialog.init(staleVg) end)
            check(coroutine.resume(stale) and coroutine.status(stale) == "suspended", "旧批次init确实已让出")
            loadHook = noop
            if mode == "aba" then Dialog.init({}) end
            Dialog.init(latestVg)
            local latestButton = findHandle(latestVg, buttonPath)
            check(coroutine.resume(stale) and coroutine.status(stale) == "dead", "过期init收尾不重新发布")
            activeVg = latestVg
            draw()
            imageDraws = {}
            Dialog.drawButton(latestVg)
            check(#imageDraws == 1 and imageDraws[1].handle == latestButton
                and imageDraws[1].path == buttonPath,
                "旧init不覆盖最新批次按钮: " .. mode)
        end

        -- 直接跑真实StartupQueue；每泵一图，最后一项返回前不发完成回执。
        local StartupQueue = originalRequire("boot.StartupQueue")
        local queueVg, completions = {}, 0
        loadHook = function() StartupQueue.checkpoint() end
        local queue = StartupQueue.new({ { "stage", function() Dialog.init(queueVg) end } }, {
            maxImages = 1, budget = 100, clock = function() return 0 end,
            onComplete = function(_, _, _, succeeded)
                check(succeeded, "真实StartupQueue初始化无异常")
                completions = completions + 1
            end,
        })
        for index = 1, 3 do
            check(not queue:pump() and completions == 0, "真实队列未全部返回不完成" .. index)
            imageDraws = {}
            Dialog.drawButton(queueVg)
            check(#draw(queueVg) == 0 and #imageDraws == 0, "真实队列挂起不画半成品" .. index)
        end
        check(queue:pump() and completions == 1, "真实队列第四图返回后唯一完成")
        loadHook = noop
        activeVg = queueVg
        check(#draw() == 7 and contextLoads(queueVg, buttonPath) == 1, "真实队列完成后首次draw有效")

        -- 懒加载背景/怪物让出后发生context切换，旧draw必须取消并恢复自己的状态。
        for _, usage in ipairs({ "background", "monster" }) do
            local oldVg, newVg = {}, {}
            Dialog.init(oldVg)
            local path = usage == "background" and firstPath or monsterPath
            loadHook = function(vg, requested)
                if vg == oldVg and requested == path and coroutine.isyieldable() then
                    coroutine.yield("lazy")
                end
            end
            local lazy = coroutine.create(function() Dialog.draw(oldVg) end)
            check(coroutine.resume(lazy) and coroutine.status(lazy) == "suspended",
                "旧draw懒加载真实让出: " .. usage)
            loadHook = noop
            Dialog.init(newVg)
            local newCount = contextLoads(newVg, path)
            imageDraws = {}
            check(coroutine.resume(lazy) and coroutine.status(lazy) == "dead"
                and #imageDraws == 0 and #clipStack == 0 and clip == nil,
                "旧draw取消并恢复绘制状态: " .. usage)
            activeVg = newVg
            check(#draw() == 7 and contextLoads(newVg, path) == newCount + 1
                and drawn(newVg, path, usage), "新context未借用旧懒加载结果: " .. usage)
        end

        -- 奖励加载让出期间换context，旧结果不能污染新cache，也不遗留Save/clip。
        local rewardOld, rewardNew = {}, {}
        loadHook = function(vg)
            if vg == rewardOld and coroutine.isyieldable() then coroutine.yield("reward") end
        end
        local rewardWorker = coroutine.create(function() rewardDraw(rewardOld, rewardAPath) end)
        check(coroutine.resume(rewardWorker) and coroutine.status(rewardWorker) == "suspended",
            "奖励图片加载合作式让出")
        check(#clipStack == 0 and clip == nil, "奖励让出前不持有绘制状态")
        loadHook = noop
        rewardDraw(rewardNew, rewardAPath)
        imageDraws = {}
        check(coroutine.resume(rewardWorker) and coroutine.status(rewardWorker) == "dead"
            and #imageDraws == 0, "旧奖励加载恢复后丢弃结果且不绘制")
        rewardDraw(rewardNew, rewardAPath)
        check(contextLoads(rewardNew, rewardAPath) == 1 and drawn(rewardNew, rewardAPath, "centered"),
            "新奖励cache不被旧加载覆盖")

        local rewardBoundaryVg = {}
        local rewardBoundaryPath = "image/测试/奖励失败恢复.png"
        failPath = rewardBoundaryPath
        rewardDraw(rewardBoundaryVg, rewardBoundaryPath)
        local rewardAttempts = contextLoads(rewardBoundaryVg, rewardBoundaryPath)
        rewardDraw(rewardBoundaryVg, rewardBoundaryPath)
        check(contextLoads(rewardBoundaryVg, rewardBoundaryPath) == rewardAttempts,
            "奖励失败在同context限频，不每帧加载")
        local recoveredVg = {}
        failPath = nil
        rewardDraw(recoveredVg, rewardBoundaryPath)
        check(contextLoads(recoveredVg, rewardBoundaryPath) == 1,
            "奖励新context不继承旧context失败退避")
        time.elapsedTime = time.elapsedTime + 3
        rewardDraw(rewardBoundaryVg, rewardBoundaryPath)
        check(contextLoads(rewardBoundaryVg, rewardBoundaryPath) == rewardAttempts + 1
            and drawn(rewardBoundaryVg, rewardBoundaryPath, "centered"), "奖励旧context恢复重新加载路径")
        RewardPreviewCache.init(rewardBoundaryVg)
        zeroHandlePath = rewardBoundaryPath
        imageDraws = {}
        rewardDraw(rewardBoundaryVg, rewardBoundaryPath)
        rewardAttempts = contextLoads(rewardBoundaryVg, rewardBoundaryPath)
        rewardDraw(rewardBoundaryVg, rewardBoundaryPath)
        check(contextLoads(rewardBoundaryVg, rewardBoundaryPath) == rewardAttempts
            and imageDraws[1].handle == 0, "奖励合法0绘制并命中缓存")
        RewardPreviewCache.init(rewardBoundaryVg)
        check(deletedByVg[rewardBoundaryVg][0] == true, "奖励同VG重置释放合法0")
        zeroHandlePath = nil

        -- 恢复独立新context继续原失败重试/0/首通断言。
        activeVg = {}
        currentStage = 101
        Dialog.init(activeVg)
        check(findHandle(activeVg, firstPath) == nil, "新context不预借用旧背景")
        I18n.set("zh_CN")
        time.elapsedTime = 23
        banners = draw()
        check(#banners == 7 and contextLoads(activeVg, firstPath) == 1,
            "恢复新VG首次draw重新加载章节背景")
        Dialog.close()
        -- 同VG显式重置后失败，避免已成功缓存绕过失败fixture。
        Dialog.init(activeVg)
        failPath = firstPath
        Dialog.open()
        time.elapsedTime = 24
        banners = draw()
        check(#banners == 6, "图片缺失时仅该章回退底色，其余章节正常")
        local attempts = loads[firstPath]
        draw()
        check(loads[firstPath] == attempts, "失败重试限频，避免每帧重复加载")
        failPath = nil
        time.elapsedTime = 27
        banners = draw()
        check(#banners == 7 and loads[firstPath] == attempts + 1, "资源恢复后重试，不永久缓存失败")
        zeroSizePath = firstPath
        check(#draw() == 6, "图片尺寸无效安全回退底色，不除零")
        Dialog.close()
        zeroSizePath, zeroHandlePath = nil, firstPath
        Dialog.init(activeVg)
        currentStage = 101
        Dialog.open()
        time.elapsedTime = 28
        banners = draw()
        check(#banners == 7 and banners[1].paint.path == firstPath, "合法句柄0仍绘制背景")
        local zeroAttempts = loads[firstPath]
        draw()
        check(loads[firstPath] == zeroAttempts, "句柄0命中缓存不重复加载")
        Dialog.close()
        Dialog.init(activeVg)
        check(deletedByVg[activeVg][0] == true and wrongContextDeletes == 0,
            "同VG重新初始化也释放合法句柄0，不通过其他VG删除")

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
        -- 上游右视窗滚轮现在只滚纵轴；主线五行不超高，不能把滚轮伪作横滚。
        Dialog.handleScroll(-1, 700, row5Y + 62)
        draw()
        check(near(rowCards(5)[1].x, initialX), "主线右视窗滚轮不串横轴")
        Dialog.handleDragBegin(700, row5Y + 62)
        Dialog.handleDragMove(600, row5Y + 62)
        Dialog.handleDragMove(580, row5Y + 62)
        draw()
        check(near(rowCards(5)[1].x, initialX - 120), "按住后两次横拖精确累加120")
        Dialog.handleDragMove(680, row5Y + 62)
        Dialog.handleDragMove(670, row5Y + 62)
        draw()
        check(near(rowCards(5)[1].x, initialX - 30), "往返与增量横拖不跳回")
        Dialog.handleDragMove(-1000, row5Y + 62)
        Dialog.handleDragMove(-980, row5Y + 62)
        draw()
        check(near(rowCards(5)[1].x, initialX - 140), "横拖到右端后反向20立即响应")
        Dialog.handleScroll(-1, 700, 790 + 62)
        Dialog.handleScroll(-1, 400, row5Y + 62)
        draw()
        check(near(rowCards(1)[1].x, initialX) and near(rowCards(5)[1].x, initialX - 140),
            "滚短列表或标签不改变被拖行横偏移")
        Dialog.handleDragEnd()
        Dialog.handleInput(690, row5Y + 62)
        check(jumps == beforeJumps and Dialog.isOpen(), "混用滚轮拖动松手不误选关")
        Dialog.handleDragBegin(700, row5Y + 62)
        Dialog.handleDragMove(2000, row5Y + 62)
        Dialog.handleDragEnd()
        Dialog.handleInput(700, row5Y + 62)
        draw()
        check(near(rowCards(5)[1].x, initialX), "横拖左端钳制不产生空白")
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
        Dialog.handleInput(175, 876 + 94 + 40)
        draw()
        Dialog.handleInput(175, 920)
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
            "不限时；全部参战队伍失守才失败。",
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
                local translated = I18n.lookup(source)
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
        local resourceModule = originalRequire("ui.battle.stage.StageSelectResources")
        selectResource = function(id, teamIdx)
            resourceSelections[#resourceSelections + 1] = { id = id, teamIdx = teamIdx }
            return acceptResource
        end
        Dialog.setOnDungeonSelect(selectResource)
        currentStage, maxStage = 101, 32305
        for _, teamIdx in ipairs({ 1, 2, 3 }) do
            for index, id in ipairs({ "gold_mine", "equipment_vault", "black_diamond", "babel_tower" }) do
                Dialog.close()
                Dialog.open(teamIdx)
                time.elapsedTime = time.elapsedTime + 1
                local before = jumps
                Dialog.handleInput(250, 808)
                draw()
                -- 上游已把旧整页副本卡迁成左分类+右真实第一行；不替换生产ResourceList。
                Dialog.handleInput(175, 876 + (index - 1) * 94 + 40)
                draw()
                Dialog.handleInput(500, 820)
                local selection = resourceSelections[#resourceSelections]
                check(selection.id == id and selection.teamIdx == teamIdx,
                    "选关副本路由锁定队号: " .. id .. "/" .. teamIdx)
                check(jumps == before and not Dialog.isOpen(), "副本导航不调用主线跳关且关闭旧弹窗")
            end
        end
        Dialog.open(2)
        time.elapsedTime = time.elapsedTime + 1
        Dialog.handleInput(250, 808)
        acceptResource = false
        local beforeSelections = #resourceSelections
        Dialog.handleInput(500, 820)
        check(Dialog.isOpen() and #resourceSelections == beforeSelections + 1,
            "锁定或拒绝进入副本时保留选关列表")
        Dialog.handleDragBegin(500, 900)
        Dialog.handleDragMove(500, 980)
        Dialog.handleDragMove(500, 900)
        Dialog.handleDragEnd()
        Dialog.handleInput(500, 820)
        check(#resourceSelections == beforeSelections + 1, "副本卡往返拖动不误点击")
        Dialog.handleInput(150, 808)
        check(#draw() == 7, "切回主线恢复原章节列表")
        Dialog.close()
        Dialog.open()
        Dialog.handleInput(250, 808)
        acceptResource = true
        Dialog.handleInput(500, 820)
        check(resourceSelections[#resourceSelections].teamIdx == 1, "普通选关默认资源队伍一")
        for _, language in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            I18n.set(language)
            Dialog.open()
            Dialog.handleInput(250, 808)
            time.elapsedTime = time.elapsedTime + 1
            draw()
            -- 当前章名允许两行；仍核验译文全部字符，不只判断任一片段存在。
            for index, source in ipairs({ "金币副本", "装备副本", "黑钻副本", "通天塔" }) do
                local cy = 876 + (index - 1) * 94 + 42
                local caption = ""
                for _, record in ipairs(textRecords) do
                    if near(record.x, 200) and math.abs(record.y - cy) < 42 then
                        caption = caption .. record.text
                    end
                end
                check(caption:gsub("%s", "") == I18n.lookup(source):gsub("%s", ""),
                    language .. "副本入口有完整名称: " .. source)
            end
            Dialog.close()
        end
        check(wrongContextDeletes == 0 and #clipStack == 0 and clip == nil,
            "全部章节/失败恢复/副本流程没有跨VG删除或绘制状态泄漏")
        I18n.set(initialLanguage)
        print("[stage_chapter_background_test] ALL PASS: " .. assertions .. " assertions")
    end)
    require, time = originalRequire, originalTime
    for name, saved in pairs(savedGlobals) do _G[name] = saved.value end
    if not ok then print("[stage_chapter_background_test] FAIL: " .. tostring(err)) end
    print("[stage_chapter_background_test] SUMMARY assertions=" .. assertions
        .. " failures=" .. (ok and 0 or 1) .. " forbiddenIO=" .. ioAttempts)
    engine:Exit()
end
