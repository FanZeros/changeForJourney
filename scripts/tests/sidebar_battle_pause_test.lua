-- 侧栏战斗暂停回归：真实设置/暂停策略/时钟/宿主，内存存档与显式UI/战斗替身。
-- 无main、无真实玩家存档、无网络Action；NanoVG spy仅验证布局/命中，不冒称GPU验收。
-- tests/sidebar_battle_pause_test.lua -tapcode_dir=/workspace/game3 -tool_mode -graphicsheadless -nosound
function Start()
    local checks, cases, failures = 0, 0, 0
    local sources = {}
    local function noop() end
    local function check(value, text)
        checks = checks + 1
        assert(value, text)
    end
    local function near(a, b, text) check(math.abs(a - b) < 0.000001, text) end
    local function run(name, fn)
        cases = cases + 1
        local ok, err = xpcall(fn, debug.traceback)
        if ok then print("[sidebar_battle_pause_test] PASS " .. name)
        else failures = failures + 1; print("[sidebar_battle_pause_test] FAIL " .. name .. " " .. tostring(err)) end
    end
    local function source(path)
        if not sources[path] then
            local file = assert(cache:GetFile(path), "missing production resource " .. path)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            sources[path] = table.concat(lines, "\n")
        end
        return sources[path]
    end
    local function compile(name, env)
        return assert(load(source(name:gsub("%.", "/") .. ".lua"), "@" .. name, "t", env))()
    end
    local function stub(fields)
        return setmetatable(fields or {}, { __index = function() return noop end })
    end
    local function fixture()
        local mods, stat = {}, { cpu = 10, language = "zh_CN", writes = 0, labels = {}, oy = 0 }
        local env = setmetatable({ time = { elapsedTime = 100 }, print = noop }, { __index = _G })
        env._G = env
        env.os = { clock = function() return stat.cpu end }
        env.require = function(name)
            if not mods[name] then mods[name] = stub() end
            return mods[name]
        end
        env.File = function(path, mode)
            check(path == "settings_volume.json", "only isolated settings file")
            return { IsOpen = function() return true end, Close = noop,
                ReadString = function() return stat.saved or "" end,
                WriteString = function(_, data) stat.saved = data; stat.writes = stat.writes + 1 end }
        end
        env.fileSystem = { FileExists = function() return stat.saved ~= nil end }
        env.audio = { SetMasterGain = noop }
        mods["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } }
        mods["core.BattleLayout"] = compile("core.BattleLayout", env)
        mods["core.I18n"] = { LANGS = {
            { id = "zh_CN", label = "简体" }, { id = "zh_TW", label = "繁體" },
            { id = "en", label = "EN" }, { id = "ja", label = "日本語" }, { id = "ko", label = "한국어" },
        }, get = function() return stat.language end,
            set = function(id) stat.language = id; return true end, t = function(key) return key end }
        mods["core.DrawUtil"] = { easeOutBack = function(x) return x end,
            hitTest = function(x, y, cx, cy, w, h)
                return x >= cx - w / 2 and x <= cx + w / 2 and y >= cy - h / 2 and y <= cy + h / 2
            end,
            drawTextStroke = function(_, x, y, text, font)
                stat.labels[#stat.labels + 1] = { x = x, y = y + stat.oy, text = text, font = font }
            end }
        mods["ui.hud.popup.RedeemCodePanel"] = stub({
            isOpen = function() return stat.redeem == true end,
            open = function() stat.redeem = true; stat.redeemOpens = (stat.redeemOpens or 0) + 1 end,
        })
        mods["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop, trigger = noop }
        mods["core.DarkIcon"] = { drawNine = function(_, style, x, y, w, h)
            if style == "panel" then stat.panelBottom = y + h end
            if style == "btn" then stat.codeY = y + h / 2 + stat.oy end
        end }
        for _, key in ipairs({ "nvgSave", "nvgRestore", "nvgScale", "nvgBeginPath", "nvgRoundedRect",
            "nvgFillColor", "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgCircle",
            "nvgFontFace", "nvgTextAlign", "nvgRect" }) do env[key] = noop end
        env.nvgFontSize = function(_, size) stat.font = size end
        env.nvgTranslate = function(_, _, y) stat.oy = stat.oy + y end
        env.nvgTextBounds = function(_, _, _, text) return utf8.len(text) * stat.font * 0.62 end
        env.nvgText = function(_, _, y, text) if text == "redeem_code" then stat.codeTextY = y + stat.oy end end
        local settings = compile("ui.hud.popup.SettingsPanel", env)
        mods["ui.hud.popup.SettingsPanel"] = settings
        local clock = compile("ui.battle.combat.BattleClock", env)
        mods["ui.battle.combat.BattleClock"] = clock
        local pageNames = { "ui.loot.LootBoxPage", "ui.story.task.TaskPage", "ui.backpack.BackpackPanel",
            "ui.church.talent.TalentPage", "ui.church.ChurchPage", "ui.tavern.TavernPage",
            "ui.market.MarketPage", "ui.blacksmith.BlacksmithPage", "ui.character.panel.CharacterPanel" }
        local open = {}
        for _, name in ipairs(pageNames) do
            mods[name] = stub({ isOpen = function() return open[name] == true end,
                isLeftMode = function() return stat.backpackLeft ~= false end,
                isDetailOpen = function() return stat.detailOpen == true end })
        end
        local policy = compile("ui.battle.scene.SidePanelBattlePause", env)
        mods["ui.battle.scene.SidePanelBattlePause"] = policy
        return env, mods, stat, settings, clock, policy, open, pageNames
    end

    run("default legacy malformed preferences save restore and independent settings", function()
        local _, _, stat, settings = fixture()
        check(not settings.isPauseBattleOnSidePanelsEnabled(), "default false before init")
        settings.init({})
        check(not settings.isPauseBattleOnSidePanelsEnabled(), "no file default false")
        settings.setPauseBattleOnSidePanelsEnabled(true)
        local savedTrue = stat.saved
        local data = cjson.decode(savedTrue)
        check(data.pauseBattleOnSidePanels == true and data.showEquipmentPower == false
            and data.showDamageNumbers == true and data.language == "zh_CN", "independent preference in settings_volume")
        settings.setPauseBattleOnSidePanelsEnabled(false)
        local savedFalse = stat.saved
        check(cjson.decode(savedFalse).pauseBattleOnSidePanels == false, "false persisted")
        stat.saved = savedTrue; settings.init({})
        check(settings.isPauseBattleOnSidePanelsEnabled(), "restore true")
        stat.saved = savedFalse; settings.init({})
        check(not settings.isPauseBattleOnSidePanelsEnabled(), "restore false")
        settings.setPauseBattleOnSidePanelsEnabled(true)
        stat.saved = cjson.encode({ bgmVolume = 0.3, language = "en" }); settings.init({})
        check(not settings.isPauseBattleOnSidePanelsEnabled() and stat.language == "en", "legacy missing field false")
        settings.setPauseBattleOnSidePanelsEnabled(true)
        stat.saved = "{"; settings.init({})
        check(not settings.isPauseBattleOnSidePanelsEnabled(), "malformed file false")
        stat.saved = cjson.encode({ pauseBattleOnSidePanels = "true" }); settings.init({})
        check(not settings.isPauseBattleOnSidePanelsEnabled(), "nonboolean cannot enable")
    end)

    run("popup embedded five language draw hit regions do not overlap", function()
        local env, _, stat, settings = fixture()
        local labels = { zh_CN = "侧栏打开时暂停战斗", zh_TW = "側欄開啟時暫停戰鬥",
            en = "Pause battle with side panels", ja = "サイドパネルで戦闘を一時停止", ko = "사이드 패널에서 전투 일시 정지" }
        settings.open(); env.time.elapsedTime = 101
        for language, text in pairs(labels) do
            stat.language = language
            for _, offset in ipairs({ false, 40, 120 }) do
                stat.language = language
                stat.oy, stat.labels = 0, {}
                if offset then settings.drawEmbedded({}, offset) else settings.draw({}) end
                local row
                for _, label in ipairs(stat.labels) do if label.text == text then row = label end end
                check(row ~= nil, "localized new label " .. language)
                near(row.y, 1780 + (offset or 0), "pause draw center")
                check(utf8.len(text) * row.font * 0.62 + 12 <= 772 - 177 - 24 + 0.000001,
                    "long label fits before toggle without clipping")
                near(stat.codeY, 1878 + (offset or 0), "redeem background shifted")
                near(stat.codeTextY, stat.codeY, "redeem text shares background center")
                if not offset then near(stat.panelBottom, 2028, "popup covers shifted redeem with original bottom margin") end
                settings.setPauseBattleOnSidePanelsEnabled(false)
                local before = stat.writes
                local function click(x, y)
                    if offset then return settings.handleEmbeddedInput(x, y + offset, offset) end
                    return settings.handleInput(x, y)
                end
                check(click(820, 1780) and settings.isPauseBattleOnSidePanelsEnabled(), "actual drawn center toggles")
                check(stat.writes == before + 1 and not stat.redeem, "one save without redeem/locale overlap")
                check(click(820, 1780) and not settings.isPauseBattleOnSidePanelsEnabled(), "repeat click disables")
                local value = settings.isPauseBattleOnSidePanelsEnabled()
                click(853, 1588)
                check(settings.isPauseBattleOnSidePanelsEnabled() == value, "language chip independent")
                click(540, 1878)
                check(stat.redeem and settings.isPauseBattleOnSidePanelsEnabled() == value, "redeem independent")
                stat.redeem = false
            end
        end
    end)

    run("exact left pages right detail residents excluded and manual pause untouched", function()
        local _, _, stat, settings, _, policy, open, names = fixture()
        open[names[1]] = true
        check(not policy.refresh(), "disabled preference ignores open pages")
        open[names[1]] = false
        settings.setPauseBattleOnSidePanelsEnabled(true)
        check(not policy.refresh(), "resident town character and tower routes do not pause")
        for i = 1, 8 do
            open[names[i]] = true
            check(policy.refresh(), "left operation page " .. names[i])
            open[names[i]] = false
            check(not policy.refresh(), "last left page closed resumes")
        end
        stat.backpackLeft = false; open[names[3]] = true
        check(not policy.refresh(), "non-left backpack excluded")
        stat.backpackLeft = true
        check(policy.refresh(), "left backpack included")
        stat.detailOpen = true; open[names[3]] = false
        check(policy.refresh(), "right detail alone pauses")
        open[names[2]] = true; stat.detailOpen = false
        check(policy.refresh(), "closing right leaves left pause")
        settings.setPauseBattleOnSidePanelsEnabled(false)
        check(not policy.refresh(), "disable while page open immediately resumes")
    end)

    run("wall CPU stats and death fallback exclude paused time no animation catchup", function()
        local env, mods, stat, _, clock = fixture()
        local stats = compile("systems.BattleStats", env)
        local hero = { heroId = 1, name = "hero" }
        stats.recordDamage(hero, 5, "physical", false)
        env.time.elapsedTime = 100.2; stat.cpu = 10.2
        local deathAt = clock.now()
        clock.setPaused(true)
        env.time.elapsedTime = 130.2; stat.cpu = 20.2
        near(clock.now(), deathAt, "paused wall fixed")
        near(clock.cpuNow(), 10.2, "paused CPU fixed")
        clock.setPaused(true)
        clock.setPaused(false)
        near(clock.now(), deathAt, "resume does not add thirty seconds")
        env.time.elapsedTime = 130.3; stat.cpu = 20.3
        near(clock.now() - deathAt, 0.1, "resume wall advances only new frame")
        near(clock.cpuNow(), 10.3, "CPU old semantics minus pause")
        stats.recordDamage(hero, 5, "physical", false)
        near(stats.getDuration(), 0.3, "stats duration excludes paused interval")
        local combat = stub({ getAnimState = function() return "dying" end })
        mods["ui.battle.combat.BattleCombat"] = combat
        mods["ui.battle.combat.BattleCombatAnim"] = { DEATH_ANIM_DURATION = 0.4 }
        mods["core.BattleLayout"] = { STRIP_PITCH = 1 }
        local reset = compile("ui.battle.scene.BattleAllyReset", env)
        local fallen = { hp = 0, _fallenPending = true, _fallenAt = deathAt }
        reset.compactFallen({ fallen }, clock.now())
        check(fallen._fallenPending == true, "death grace not skipped after long pause")
        env.time.elapsedTime = 131.0
        reset.compactFallen({ fallen }, clock.now())
        check(fallen._fallen == true, "death fallback resumes normally after grace")
        local AD = { HP_BONUS = 1, ARMOR_BONUS = 2, ES_BONUS = 3, PHYS_ATK_BONUS = 4, MAG_ATK_BONUS = 5 }
        mods["systems.AttributeDef"] = AD
        local rch = compile("systems.RelicConditionHandler", env)
        local removed = 0
        local unit = { attrs = { removeModifier = function() removed = removed + 1 end } }
        local state = { activeModIds = { buff = true }, timedBuffs = { { expireAt = clock.cpuNow() + 1, modId = "buff" } } }
        clock.setPaused(true); stat.cpu = stat.cpu + 20; env.time.elapsedTime = env.time.elapsedTime + 20
        rch._checkTimedBuffs(unit, state, 0)
        check(removed == 0, "CPU timed buff not expired during pause")
        clock.setPaused(false); stat.cpu = stat.cpu + 1.1
        rch._checkTimedBuffs(unit, state, 0)
        check(removed == 1, "CPU timed buff expires after active CPU interval")
    end)

    run("real Standalone centralized dispatch freezes three battle types keeps UI receipt save", function()
        local env, mods, stat, settings, _, _, open, names = fixture()
        local counters = { tri = 0, normal = 0, dungeon = 0, tower = 0, save = 0, receipts = 0, ui = 0 }
        local kind = "tri"
        mods["ui.battle.tri.BattleTriPage"] = stub({ isOpen = function() return kind == "tri" end,
            update = function(dt) counters.tri = counters.tri + dt end })
        mods["ui.battle.scene.BattleScene"] = stub({ update = function(dt) counters.normal = counters.normal + dt end })
        mods["ui.dungeon.DungeonBattleScene"] = stub({ isOpen = function() return kind == "dungeon" end,
            update = function(dt, paused) counters.ui = counters.ui + dt; if not paused then counters.dungeon = counters.dungeon + dt end end })
        mods["ui.tower.TowerBattleScene"] = stub({ isActive = function() return kind == "tower" end,
            update = function(dt, paused) counters.ui = counters.ui + dt; if not paused then counters.tower = counters.tower + dt end end })
        mods["ui.hud.BottomNav"] = stub({ getSelectedIndex = function() return 4 end })
        mods["core.PlayerStore"] = stub({ Update = function(dt) counters.receipts = counters.receipts + dt end })
        mods["boot.StandaloneSave"] = stub({ Update = function(dt) counters.save = counters.save + dt end })
        mods["ui.hud.popup.PlayerInfoPanel"] = stub({ update = function(dt) counters.ui = counters.ui + dt end })
        mods["runtime.ClientDispatcher"] = stub({ get = function() return {} end, hasData = function() return false end })
        mods["ui.tutorial.TutorialPageRecovery"] = stub({ getStoryPlace = function() return "town" end })
        env.HandleEquipmentHoverTickHorizon = noop
        compile("boot.Standalone", env)
        local function set(name, value)
            for i = 1, 100 do
                local found = debug.getupvalue(env.HandleUpdate, i)
                if found == name then debug.setupvalue(env.HandleUpdate, i, value); return end
                if not found then break end
            end
            error("missing production upvalue " .. name)
        end
        set("bootReady_", true); set("postStartFlowDone_", true); set("storyBackfilled_", true)
        local function frame() env.HandleUpdate("Update", { TimeStep = { GetFloat = function() return 0.01 end } }) end
        settings.setPauseBattleOnSidePanelsEnabled(true)
        for _, battle in ipairs({ "tri", "dungeon", "tower", "normal" }) do
            kind = battle; open[names[1]] = false
            frame(); near(counters[battle], 0.01, battle .. " active dispatch")
            open[names[1]] = true
            local receipts, save, ui = counters.receipts, counters.save, counters.ui
            frame(); env.time.elapsedTime = env.time.elapsedTime + 30; frame()
            near(counters[battle], 0.01, battle .. " no dispatch or dt0 callbacks while paused")
            check(counters.receipts > receipts and counters.save > save and counters.ui > ui,
                battle .. " UI receipts and save continue")
            open[names[1]] = false; frame()
            near(counters[battle], 0.02, battle .. " resume only current frame no accumulated dt")
        end
    end)

    run("real dungeon and tower active guards preserve confirm settlement and receipt timeouts", function()
        local env, mods, stat = fixture()
        local ticks, ui, fx = 0, 0, 0
        mods["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } }
        mods["ui.battle.combat.BattleCombat"] = stub({ DEATH_ANIM_DURATION = 0.4, REVIVE_ANIM_DURATION = 0.35,
            getBattleLogicDt = function(dt) return dt end,
            updateCardAnims = function() fx = fx + 1 end, updateFloatingTexts = function() fx = fx + 1 end,
            updateHitFlashes = function() fx = fx + 1 end })
        mods["ui.battle.combat.ProjectileSystem"] = stub({ update = function() ticks = ticks + 1 end })
        mods["ui.battle.combat.BattleEffects"] = stub({ update = function() fx = fx + 1 end })
        mods["ui.battle.popup.BattleResultPanel"] = stub({ update = function() ui = ui + 1 end,
            isOpen = function() return false end })
        mods["ui.dungeon.DungeonBattle"] = stub({ isResultReady = function() return false end,
            getConfig = function() return { teamIdx = 1 } end,
            update = function() ticks = ticks + 1 end })
        mods["ui.dungeon.DungeonBattleScope"] = { run = function(_, fn, ...) return fn(...) end }
        local function privateState(fn)
            for i = 1, 100 do
                local name, value = debug.getupvalue(fn, i)
                if name == "state" then return value end
                if name == "implementation" then return privateState(value) end
                if not name then break end
            end
            error("missing production state")
        end
        local dungeon = compile("ui.dungeon.DungeonBattleScene", env)
        local state = privateState(dungeon.update)
        state.open, state.battleState = true, "active"
        state.confirmOpen, state.confirmClosing, state.confirmCloseTime = true, true, 90
        dungeon.update(30, true)
        check(ticks == 0 and fx == 0, "dungeon active pause skips damage and visual callbacks")
        check(ui == 1 and not state.confirmOpen and not state.confirmClosing, "dungeon confirm and result UI continue")
        state.battleState, state.resultTimer = "win", 0
        dungeon.update(2, true)
        check(state.resultTimer == 2 and ui == 2, "dungeon pending result progresses with sidebar open")
        local tri = compile("ui.tower.TowerTriBattle", env)
        mods["ui.tower.TowerTriBattle"] = tri
        local ts = privateState(tri.update)
        ts.open, ts.phase = true, "active"
        tri.update(30, true)
        check(ticks == 0, "tower active pause before DungeonBattle ART lanes判胜")
        ts.phase, ts.resultTimer, ts.lanes = "lose", 0, {}
        tri.update(2, true)
        check(ts.resultTimer == 2 and ui == 3, "tower lose result delay/UI continue")
        mods["ui.tower.TowerBuffPick"] = stub({ update = function() stat.pickUpdates = (stat.pickUpdates or 0) + 1 end })
        local scene = compile("ui.tower.TowerBattleScene", env)
        local ss = privateState(scene.update)
        ss.active, ss.phase, ss.serverFloorResult = true, "floor_win", nil
        ss.settlementRequest, ss.settlementElapsed = "pending", 0
        scene.update(5.1, true)
        check(ss.phase == "settlement_retry" and ss.settlementRequest == nil and stat.pickUpdates == 1,
            "tower receipt timeout and picker continue at real dt")
    end)

    print(string.format("[sidebar_battle_pause_test] SUMMARY cases=%d checks=%d failures=%d", cases, checks, failures))
    if failures == 0 then print("[sidebar_battle_pause_test] ALL PASS") end
    engine:Exit()
end
