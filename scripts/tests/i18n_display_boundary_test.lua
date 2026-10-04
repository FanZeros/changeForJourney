-- 关卡显示边界回归：真实词典/配置/Load/Nav/Sweep，绘制与战斗依赖替身。
-- 不调用扫荡输入/发奖入口，不读写玩家存档。
local failed, passed = 0, 0
local function check(ok, name)
    if ok then passed = passed + 1; print("[PASS] " .. name)
    else failed = failed + 1; print("[FAIL] " .. name) end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function Start()
    local originalRequire, originalTime = require, time
    local savedGlobals = {}
    local function replace(name, value)
        savedGlobals[name] = { value = _G[name] }
        _G[name] = value
    end
    local ok, err = pcall(function()
        local I18n = require("core.I18n")
        local SC = require("config.StageConfig")
        local StageUtils = require("shared.StageUtils") -- 始终是真实五关回退，不 mock。
        local initialLanguage = I18n.get()
        local entry = assert(SC.getStage(2404))
        local sourceEntry = copy(entry)
        local captured, stageValues = {}, {}
        local function record(_, x, y, text)
            captured[#captured + 1] = text
            if x == 904 and y == 900 then stageValues[#stageValues + 1] = text end
        end
        local function contains(expected)
            for _, text in ipairs(captured) do if text == expected then return true end end
            return false
        end
        local function noop() end
        local function inactive() return false end
        local forbiddenCalls = 0
        local function forbidden()
            forbiddenCalls = forbiddenCalls + 1
            error("显示测试禁止扫荡发奖/存档写入", 2)
        end
        local battleData = { maxStageId = 2404, clearedStages = {} }
        local store = setmetatable({ Get = function(key)
            if key == "battle" then return battleData end
            if key == "heroes" then return { deployed = {} } end
            error("未配置的玩家数据读取: " .. tostring(key))
        end }, { __index = function() return forbidden end })
        local fakeDraw = { drawTextStroke = record, drawImageCentered = noop, drawImageMirrored = noop }
        local mocks = {
            ["ui.battle.scene.BattleDraw"] = fakeDraw,
            ["core.DrawUtil"] = fakeDraw,
            ["core.DarkIcon"] = { drawNine = noop },
            ["ui.battle.stage.StageBerserk"] = { isActive = inactive, enter = noop, exit = noop },
            ["systems.MapAffixSystem"] = { onStageLoad = noop, hasAffixes = inactive },
            ["systems.BossAffixSystem"] = { onStageLoad = noop, hasAffixes = inactive },
            ["systems.BattleDiag"] = { installSentinel = noop, scanNow = noop },
            ["ui.battle.combat.BattleCombat"] = { reset = noop, playEnterAnims = noop },
            ["ui.battle.combat.BattleEffects"] = { reset = noop },
            ["ui.battle.combat.ProjectileSystem"] = { reset = noop },
            ["systems.ThreatManager"] = { reset = noop },
            ["systems.StatusEffectManager"] = { reset = noop },
            ["systems.RelicConditionHandler"] = { initBattle = noop },
            ["systems.ArtifactRuntime"] = { initBattle = noop },
            ["ui.widget.SpeechBubble"] = { reset = noop },
            ["core.BattleLayout"] = { MODE = "strip", MAX_PER_SIDE = 4 },
            ["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 },
                Battle = { TIME_LIMIT_SEC = 60 } },
            ["core.PlayerStore"] = store,
            ["core.GameState"] = setmetatable({ getSweepTicket = function() return 10 end },
                { __index = function() return forbidden end }),
            ["runtime.ClientDispatcher"] = setmetatable({ get = function(key) return store.Get(key) end },
                { __index = function() return forbidden end }),
            ["config.ExpTable"] = { getUnlockedTeamCount = function() return 1 end, heroCountExpMult = { 1 } },
            ["config.IdleIncomeConfig"] = { get = function() return 1, 1 end },
            ["ui.character.panel.CharacterPanel"] = { getActiveTeamIdx = function() return 1 end },
            ["ui.widget.ImageCache"] = { getQualityBg = function() return -1 end },
            ["systems.ButtonFeedback"] = { begin = noop, finish = noop },
        }
        require = function(name) return mocks[name] or originalRequire(name) end
        for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgFontFace", "nvgFontSize",
            "nvgTextAlign", "nvgFillColor", "nvgBeginPath", "nvgRoundedRect", "nvgFill",
            "nvgTranslate", "nvgScale", "nvgGlobalAlpha", "nvgCircle", "nvgStrokeColor",
            "nvgStrokeWidth", "nvgStroke" }) do replace(name, noop) end
        replace("nvgRGBA", function() return 0 end)
        replace("nvgTextBounds", function(_, _, _, text)
            local length = utf8.len(text)
            if not length then error("绘制spy收到非法UTF-8") end
            return length * 10
        end)
        replace("nvgText", record)
        time = { elapsedTime = 0 }
        local Load = require("ui.battle.stage.BattleStageLoad")
        local Nav = require("ui.battle.stage.BattleStageNav")
        local Transition = require("ui.battle.stage.BattleTransitionHud")
        local Sweep = require("ui.battle.stage.SweepDialog")
        Sweep.onSweep = forbidden

        check(SC.getStageDisplayName(101) == "黑棘林道1-1"
            and SC.getStageDisplayName(2404) == "困难·黑棘林道24-4"
            and SC.getStageDisplayName("4701") == "噩梦·黑棘林道47-1"
            and SC.getStageDisplayName(1999) == assert(SC.getStage(1999)).name, "配置全名连续章号/终焉原名")
        check(SC.formatProgressDisplay(2404) == "困难24-4"
            and SC.formatProgressDisplay(4701) == "噩梦47-1", "进度显示连续章号")

        local mapPaths, generatedEntries, loadedIds = {}, {}, {}
        local ctx = {
            vg_ = {}, maxStageId_ = 2401, clearedStages = {}, currentChapter = 0, allies = {},
            currentStageId = 0, stageName = "", isFirstClear = false, battleActive = false,
            maxStageId = 2404, getRelativeChapter = SC.getRelativeChapter,
            ensureBattleCards = noop, getStageConfig = function() return SC end,
            recalcIdleIncome = noop, resetWaveTimers = noop, startBattleTalents = noop,
            setMapBackground = function(_, path) mapPaths[#mapPaths + 1] = path end,
            generateEnemyList = function(stage)
                generatedEntries[#generatedEntries + 1] = stage
                return { { monsterId = stage.monsters[1], hp = 100 } }
            end,
            assignEnemiesToField = function(enemies) return enemies, {} end,
            onStageLoadedCallback = function(id, firstClear) loadedIds[#loadedIds + 1] = { id, firstClear } end,
        }
        Load.load(ctx, 2404, true) -- 真实加载；仅跳过天赋启动，仍走全部加载状态。
        check(ctx.stageName == "困难·黑棘林道24-4", "真实Load给ctx新全名")
        check(ctx.currentStageId == 2404 and ctx.maxStageId_ == 2404
            and loadedIds[1][1] == 2404 and loadedIds[1][2] == true
            and generatedEntries[1] == entry, "Load关卡ID/源entry传递不变")
        local bgPath, bgChapter = SC.getBattleBackground(2404)
        check(#mapPaths == 1 and mapPaths[1] == "image/关卡地图/MAP_1.png"
            and ctx.currentChapter == 24 and bgChapter == 1
            and bgPath == SC.getBattleBackground(104) and SC.getRelativeChapter(24) == 1,
            "Load真实chapter保留/地图与相对章仍23章循环")

        local ranges = {
            { max = 2501, ids = "2405,2404,2403,2402,2401", source = "困难 24-1 至 24-5",
                first = "24-1", last = "24-5" },
            -- 五个前关不含当前2404：23-4，不是第六个前关23-3。
            { max = 2404, ids = "2403,2402,2401,2305,2304", source = "困难 23-4 至 24-3",
                first = "23-4", last = "24-3" },
        }
        for _, range in ipairs(ranges) do
            local ids = {}
            for _, stage in ipairs(StageUtils.collectPrevStages(range.max, 5, SC)) do ids[#ids + 1] = stage.id end
            check(table.concat(ids, ",") == range.ids, "真实StageUtils五关ID max=" .. range.max)
        end
        local names = { zh_CN = "困难·黑棘林道24-4", zh_TW = "困難·黑棘林道24-4",
            en = "Hard · Blackthorn Trail 24-4", ja = "ハード・黒棘の林道 24-4", ko = "어려움 · 검은가시 숲길 24-4" }
        for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            I18n.set(lang)
            check(SC.getStageDisplayName(2404) == "困难·黑棘林道24-4", lang .. "全名API不存译文")
            captured = {}
            local source = "普通 1-1 至 1-5"
            local cached = Nav.drawStageTitle(nil, { isFirstClear = false, idleRangeText = source,
                stageName = "黑棘林道1-1", maxStageId = 105, battleActive = false,
                getStageConfig = function() return SC end, getRelativeChapter = SC.getRelativeChapter })
            check(cached == source, lang .. "挂机返回源缓存")
            check(contains(I18n.format("%s %s 至 %s", I18n.difficulty("普通"), "1-1", "1-5")),
                lang .. "挂机范围显示正确译文")
            for _, range in ipairs(ranges) do
                captured = {}
                local actual = Nav.drawStageTitle(nil, { isFirstClear = false, maxStageId = range.max,
                    stageName = ctx.stageName, battleActive = false,
                    getStageConfig = ctx.getStageConfig, getRelativeChapter = SC.getRelativeChapter })
                check(actual == range.source and contains(I18n.format("%s %s 至 %s",
                    I18n.difficulty("困难"), range.first, range.last)), lang .. "未缓存挂机真实chapter max=" .. range.max)
            end
            captured = {}
            ctx.firstClearTimeLeft = 9
            Nav.drawStageTitle(nil, ctx)
            check(contains(names[lang]) and contains(I18n.format("剩余 %d 秒", 9)), lang .. "加载后首通全名与倒计时翻译")
            ctx.battleActive, ctx.drawTextStroke, ctx.defeatByTimeout = false, record, false
            for _, result in ipairs({ "胜利", "失败", "超时失败" }) do
                ctx.defeatTimer = result ~= "胜利" and 0.5 or nil
                ctx.defeatByTimeout = result == "超时失败"
                captured = {}
                Transition.draw(nil, ctx)
                check(contains(names[lang]), lang .. "加载后" .. result .. "过渡全名")
            end
            check(ctx.stageName == "困难·黑棘林道24-4", lang .. "绘制不回写加载全名")
            ctx.battleActive, ctx.defeatTimer = true, nil
            captured = {}
            Transition.draw(nil, { battleActive = false, reincarnationTimer = 0.5,
                currentStageId = 999, stageName = "终焉神殿", defeatByTimeout = false,
                getStageConfig = ctx.getStageConfig, drawTextStroke = record })
            check(contains(I18n.format("即将进入%s难度...", I18n.difficulty("困难"))), lang .. "轮回下一难度翻译")
        end

        I18n.set("zh_CN")
        for _, case in ipairs({
            { max = 2404, cleared = { [2404] = true }, expected = "困难 24-4", label = "2404已通" },
            { max = 2404, cleared = { ["2403"] = true }, expected = "困难 24-3", label = "2404未通退2403" },
            { max = 2401, cleared = { [2305] = true }, expected = "普通 23-5", label = "难度首关未通退2305" },
            { max = 1999, cleared = { ["1999"] = true, [4605] = true }, expected = "困难 46-5", label = "终焉回4605" },
        }) do
            battleData = { maxStageId = case.max, currentStageId = 101, clearedStages = case.cleared }
            local before = copy(battleData)
            Sweep.open() -- 只调用真实open/draw/close，绝不触碰确认输入。
            time.elapsedTime = time.elapsedTime + 1
            captured, stageValues = {}, {}
            Sweep.draw(nil)
            check(#stageValues == 1 and stageValues[1] == case.expected, "真实Sweep绘制最高已通: " .. case.label)
            check(same(battleData, before), "Sweep绘制不修改进度: " .. case.label)
            Sweep.close()
        end
        check(forbiddenCalls == 0, "未调用扫荡发奖/存档写入")
        check(SC.getStage(2404) == entry and same(entry, sourceEntry)
            and entry.name == "困难·黑棘林道1-4", "加载/五语绘制后完整源entry不变")
        I18n.set(initialLanguage)
    end)
    require, time = originalRequire, originalTime
    for name, saved in pairs(savedGlobals) do _G[name] = saved.value end
    if not ok then
        failed = failed + 1
        log:Write(LOG_ERROR, "[i18n_display_boundary_test] " .. tostring(err))
    end
    print(string.format("[i18n_display_boundary_test] passed=%d failed=%d", passed, failed))
    if failed == 0 then print("I18N DISPLAY BOUNDARY: ALL PASS")
    else log:Write(LOG_ERROR, "I18N DISPLAY BOUNDARY: FAIL") end
    engine:Exit()
end
