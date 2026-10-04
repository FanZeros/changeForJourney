-- 副本入口闭环回归：真实 Entry / Page / KeyboardShortcuts 与五语字典。
-- 仅从 cache:GetFile 读取声明的 Lua 资源；不 require 玩家存档，不建 GPU。
-- NanoVG leaves 的测宽只是确定性逻辑测量，不代表真实字体或 GPU 验收。
local TAG = "[dungeon_entry_state_test]"
local assertions, cases = 0, 0
local failures = {}

local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end

local function eq(actual, expected, label)
    check(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

local function runCase(label, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if ok then
        print(TAG .. " PASS " .. label)
    else
        failures[#failures + 1] = label .. ": " .. tostring(err)
        print(TAG .. " FAIL " .. failures[#failures])
    end
end

function Start()
    local ok, err = pcall(function()
        local nativeRequire, nativeTime = require, time
        local packageSnapshot = {}
        for name, value in pairs(package.loaded) do packageSnapshot[name] = value end
        local function noop() end
        local function forbidden() error("禁止读取或写入真实玩家档") end
        ---@type any
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.File, env.fileSystem, env.io = forbidden, {}, nil
        env.fileSystem.FileExists = forbidden
        env.fileSystem.CreateDir = forbidden
        local clock = { elapsedTime = 100, unix = 1791072000 }
        env.time = clock
        env.os = setmetatable({ time = function() return clock.unix end }, { __index = os })
        local today = math.floor((clock.unix + 28800) / 86400)
        local modules = {
            battle = { maxStageId = 605, clearedStages = {} },
            currency = { gold = 17, gems = 29 },
            dungeon = {
                gold_mine = { floor = 2, dailyUsed = 0 },
                ancient_ruin = { floor = 2, dailyUsed = 0 },
                babel_tower = { floor = 2, dailyUsed = 0, dailyDay = today, idleAccumSec = 0 },
            },
        }
        local roster = { applied = true, counts = { 1, 1, 1 }, exported = 0 }
        local nav = { selected = 5, locked = false, changes = {} }
        local overlay = { reward = false, level = false, pip = false, offline = false,
            notice = false, tutorial = false, tower = false, dungeon = false }
        local calls = { reward = 0, level = 0, pip = 0, notice = 0, toast = 0,
            towerOpen = 0, dungeonOpen = 0 }
        local sends = {}
        local transport = { mode = "deferred" }
        local function popup(key)
            return {
                isOpen = function() return overlay[key] == true end,
                close = function() calls[key] = calls[key] + 1; overlay[key] = false end,
                handleInput = function() calls[key] = calls[key] + 1; overlay[key] = false end,
            }
        end
        ---@type any
        local capture = { labels = {}, bounds = {}, nine = {}, alpha = 1,
            color = { 0, 0, 0, 255 }, size = 30, align = 0 }
        local function width(text, size)
            local amount = 0
            for _, cp in utf8.codes(text) do amount = amount + (cp > 127 and size or size * 0.62) end
            return amount
        end
        env.nvgFontSize = function(_, size) capture.size = size end
        env.nvgTextAlign = function(_, align) capture.align = align end
        env.nvgRGBA = function(r, g, b, a) return { r, g, b, a } end
        env.nvgFillColor = function(_, color) capture.color = color end
        env.nvgGlobalAlpha = function(_, alpha) capture.alpha = alpha end
        env.nvgTextBounds = function(_, _, _, text)
            local w = width(text, capture.size)
            capture.bounds[#capture.bounds + 1] = { text = text, size = capture.size, width = w }
            return w
        end
        env.nvgText = function(_, x, y, text)
            capture.labels[#capture.labels + 1] = { x = x, y = y, text = text,
                size = capture.size, width = width(text, capture.size), color = capture.color,
                align = capture.align }
        end
        env.nvgCreateImage = function() return -1 end
        for _, name in ipairs({ "nvgFontFace", "nvgSave", "nvgRestore", "nvgBeginPath",
            "nvgRect", "nvgRoundedRect", "nvgFill", "nvgScissor", "nvgTranslate",
            "nvgScale", "nvgSkewX", "nvgFillPaint" }) do env[name] = noop end
        local mocks = {
            ["core.PlayerStore"] = { Get = function(key) return modules[key] end },
            ["runtime.ClientDispatcher"] = { get = function(key) return modules[key] end },
            ["config.MonsterConfig"] = { MONSTERS = {} },
            ["core.DrawUtil"] = {
                hitTest = function(x, y, cx, cy, w, h)
                    return x >= cx - w / 2 and x <= cx + w / 2
                        and y >= cy - h / 2 and y <= cy + h / 2
                end,
                drawTextStroke = function(vg, x, y, text, size, align, r, g, b)
                    env.nvgFontSize(vg, size)
                    env.nvgTextAlign(vg, align)
                    env.nvgFillColor(vg, env.nvgRGBA(r, g, b, 255))
                    env.nvgText(vg, x, y, text)
                end,
            },
            ["core.DarkIcon"] = {
                drawQualityBg = noop,
                drawNine = function(_, kind, x, y, w, h, options)
                    capture.nine[#capture.nine + 1] = { kind = kind, x = x, y = y, w = w, h = h,
                        options = options, globalAlpha = capture.alpha }
                end,
            },
            ["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop, trigger = noop },
            ["ui.character.panel.CharacterPanel"] = {
                isHeroesDataApplied = function() return roster.applied end,
                getTeamOccupiedCounts = function() return roster.counts end,
                getActiveTeamIdx = function() return 1 end,
                getDeployedTeam = function(team)
                    roster.exported = roster.exported + 1
                    local allies = {}
                    for i = 1, roster.counts[team or 1] or 0 do allies[i] = { heroId = team * 10 + i } end
                    return allies
                end,
            },
            ["runtime.GameAction"] = { sendAction = function(action, params)
                if transport.mode == "throw" then error("fixture transport failure") end
                if transport.mode == "false" then return false end
                sends[#sends + 1] = { action = action, params = params }
                return true
            end },
            ["ui.hud.BottomNav"] = {
                isAllLocked = function() return nav.locked end,
                getSelectedIndex = function() return nav.selected end,
                setSelectedIndex = function(index) nav.selected = index; nav.changes[#nav.changes + 1] = index end,
            },
            ["systems.TutorialManager"] = { isActive = function() return overlay.tutorial end },
            ["ui.tower.TowerBattleScene"] = {
                isActive = function() return overlay.tower end,
                open = function() calls.towerOpen = calls.towerOpen + 1 end,
            },
            ["ui.dungeon.DungeonBattleScene"] = {
                isOpen = function() return overlay.dungeon end, init = noop,
                open = function() calls.dungeonOpen = calls.dungeonOpen + 1 end,
            },
            ["ui.tower.TowerTriBattle"] = { init = noop },
            ["ui.tower.TowerBuffPick"] = { init = noop },
            ["ui.hud.popup.RewardPopup"] = popup("reward"),
            ["ui.hud.popup.LevelUpPopup"] = popup("level"),
            ["ui.hud.popup.PlayerInfoPanel"] = popup("pip"),
            ["ui.hud.popup.UpdateNoticePopup"] = popup("notice"),
            ["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return overlay.offline end },
            ["core.UiToast"] = { show = function() calls.toast = calls.toast + 1 end },
        }
        local closed = { isOpen = function() return false end, isActive = function() return false end,
            isVisible = function() return false end, close = noop, hide = noop }
        for _, name in ipairs({ "ui.story.gate.DarkTitleScreenGate", "ui.story.gate.IntroCutscene",
            "ui.story.ScenarioDialogue", "ui.hud.popup.RedeemCodePanel", "ui.dev.GMConsolePanel",
            "ui.character.detail.CharacterDetail", "ui.character.hero.HeroRosterPanel",
            "ui.loot.LootBoxPage", "ui.backpack.BackpackPanel", "ui.church.talent.TalentPage",
            "ui.church.ChurchPage", "ui.blacksmith.BlacksmithPage", "ui.tavern.TavernPage",
            "ui.market.MarketPage" }) do mocks[name] = closed end
        local realNames = {
            ["ui.dungeon.DungeonEntry"] = true, ["ui.dungeon.DungeonPage"] = true,
            ["ui.dev.KeyboardShortcuts"] = true, ["shared.Protocol"] = true,
            ["core.NumberUtil"] = true, ["config.ExpTable"] = true,
            ["config.TowerConfig"] = true, ["config.DungeonConfig"] = true,
            ["config.DungeonIdleConfig"] = true, ["config.KeywordConfig"] = true,
        }
        local real, loading = {}, {}
        local function compile(name)
            local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少真实 Lua " .. name)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            return assert(load(table.concat(lines, "\n"), "@" .. name, "t", env))()
        end
        env.require = function(name)
            if mocks[name] then return mocks[name] end
            if real[name] then return real[name] end
            assert(realNames[name] or name:match("^core%.I18n") or name:match("^core%.i18n%.") ,
                "禁止未声明依赖或玩家档模块 " .. name)
            assert(not loading[name], "意外循环依赖 " .. name)
            loading[name] = true
            local value = compile(name)
            loading[name] = nil
            real[name] = value
            return value
        end
        ---@type any
        local Entry = env.require("ui.dungeon.DungeonEntry")
        ---@type any
        local Page = env.require("ui.dungeon.DungeonPage")
        ---@type any
        local I18n = env.require("core.I18n")
        ---@type any
        local Extra = env.require("core.I18nDictExtra")
        ---@type any
        local Tower = env.require("config.TowerConfig")
        ---@type any
        local Protocol = env.require("shared.Protocol")
        local vg = {}
        I18n.installDrawHook()
        Page.init(vg)
        local function state(fn, wanted)
            for index = 1, 100 do
                local name, value = debug.getupvalue(fn, index)
                if not name then break end
                if name == wanted then return value end
            end
            error("缺少真实页面状态 " .. wanted)
        end
        local function clearCapture()
            capture.labels, capture.bounds, capture.nine, capture.alpha = {}, {}, {}, 1
        end
        local function draw()
            clearCapture()
            Page.update(0.3)
            Page.draw(vg)
        end
        local function labelAt(x, y)
            for _, label in ipairs(capture.labels) do
                if label.x == x and label.y == y then return label end
            end
            error("没有真实正文坐标 " .. x .. "," .. y)
        end
        local function nineAt(x, y)
            for _, nine in ipairs(capture.nine) do
                if nine.x == x and nine.y == y and nine.kind == "btn" then return nine end
            end
            error("没有真实 DarkIcon 按钮坐标 " .. x .. "," .. y)
        end
        local function measuredInSlot(x, y, maxWidth, label)
            local body = labelAt(x, y)
            check(body.width <= maxWidth + 0.0001, label .. "正文在测宽槽内")
            local measured = false
            for _, bounds in ipairs(capture.bounds) do
                if bounds.text == body.text then measured = true end
            end
            check(measured, label .. "必须经过真实 nvgTextBounds 调用")
        end
        local function resetPage()
            transport.mode = "deferred"
            if state(Page.handleInput, "detailOpen") then Page.handleBack() end
            Page.handleBack()
            nav.selected = 5
            Entry.clearMessage()
        end
        local function openTower()
            resetPage()
            Page.refreshFromStore()
            eq(Page.handleInput(540, 1360), true, "真实通天塔卡片输入被消费")
            eq(state(Page.handleInput, "detailOpen"), true, "真实卡片打开详情")
            draw()
            eq(labelAt(540, 705).text, I18n.lookup("通天塔"), "真实详情标题")
        end
        local function challenge()
            local before = #sends
            eq(Page.handleInput(750, 1633), true, "真实挑战输入")
            return #sends - before
        end
        local function reject(reason)
            local exported = roster.exported
            eq(challenge(), 0, "不发送挑战")
            eq(roster.exported, exported, "拒绝时不创建战斗英雄")
            eq(Entry.getMessage(), reason, "页面内拒绝提示")
            draw()
            eq(labelAt(540, 2125).text, reason, "真实 Page.draw 显示拒绝提示")
            measuredInSlot(540, 2125, 850, "拒绝提示")
            eq(nineAt(555, 1583).options.alpha, 0.4, "真实挑战底板禁用灰态")
            local color = labelAt(750, 1633).color
            eq(table.concat(color, ","), "139,149,165,255", "真实挑战文字灰态")
        end
        local stableFloors = cjson.encode(Tower.FLOORS)
        runCase("6-5入口与19-5挑战是两道独立门禁", function()
            I18n.set("zh_CN")
            modules.battle = { maxStageId = 604, clearedStages = {} }
            resetPage(); Page.refreshFromStore(); Page.handleInput(540, 1360)
            eq(state(Page.handleInput, "detailOpen"), false, "6-5前卡片不能开")
            modules.battle = { maxStageId = 605, clearedStages = {} }
            openTower()
            reject(I18n.format("通关%d-%d解锁三队后可挑战", 19, 5))
            modules.battle = { maxStageId = 1905, clearedStages = {} }
            openTower()
            reject(I18n.format("通关%d-%d解锁三队后可挑战", 19, 5))
        end)
        runCase("数字/字符串通关键与严格越过19-5开放", function()
            for _, progress in ipairs({
                { maxStageId = 1905, clearedStages = { [1905] = true } },
                { maxStageId = 1905, clearedStages = { ["1905"] = true } },
                { maxStageId = 1906, clearedStages = {} },
                { maxStageId = "1906", clearedStages = {} },
            }) do
                modules.battle = progress
                openTower()
                eq(nineAt(555, 1583).options.alpha, 1, "开放的真实挑战底板")
                eq(challenge(), 1, "真实 Page 输入发送一次塔挑战")
                local request = sends[#sends]
                eq(request.action, Protocol.ACTION_TYPES.TOWER_CHALLENGE, "保持塔挑战协议")
                check(type(request.params.requestId) == "number", "真实挑战带请求关联ID")
                eq(challenge(), 0, "pending时不能连点发送")
            end
        end)
        local sources = { "返回列表", "返回主界面", "今日扫荡次数:%d/%d",
            "通关%d-%d解锁三队后可挑战", "队伍%d为空，请在右侧部署队员",
            "三队均需至少1人，任意一队全灭即失败", "编队数据加载中", "三队就绪，可挑战",
            "%d层已全部通关", "全部通关", "本层首通 %s · 上层扫荡 %s",
            "挑战发送失败，请重试", "挑战响应超时，请重试", "挑战失败，请重试" }
        for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            runCase("五语词条/三个空队/未加载 " .. lang, function()
                I18n.set(lang)
                for _, source in ipairs(sources) do
                    local expected = lang == "zh_CN" and source or Extra[lang][source]
                    check(type(expected) == "string" and expected ~= "", lang .. "词典无fallback " .. source)
                    eq(I18n.lookup(source), expected, lang .. "真实词条命中 " .. source)
                end
                modules.battle = { maxStageId = 1906, clearedStages = {} }
                roster.applied = true
                modules.dungeon.babel_tower.floor = 2
                for team = 1, 3 do
                    roster.counts = { 1, 1, 1 }; roster.counts[team] = 0
                    openTower()
                    reject(I18n.format("队伍%d为空，请在右侧部署队员", team))
                end
                roster.counts, roster.applied = { 1, 1, 1 }, false
                openTower()
                reject(I18n.lookup("编队数据加载中"))
                roster.applied = true
            end)
            runCase("真实塔正文奖励/规则/全部通关 " .. lang, function()
                I18n.set(lang)
                modules.battle = { maxStageId = 1906, clearedStages = {} }
                roster.counts, roster.applied = { 1, 1, 1 }, true
                for _, fixture in ipairs({ { 1, 150, 0 }, { 2, 300, 75 }, { 112, 5800, 2875 }, { 113, 0, 2900 } }) do
                    local floor, first, sweep = table.unpack(fixture)
                    modules.dungeon.babel_tower.floor = floor
                    openTower()
                    local beforeExport = roster.exported
                    draw()
                    eq(roster.exported, beforeExport, "逐帧绘制仅查编队state")
                    local actualFirst, actualSweep = Entry.getTowerRewards(floor)
                    eq(actualFirst, first, "真实首通奖励 " .. floor)
                    eq(actualSweep, sweep, "真实上一层扫荡 " .. floor)
                    local template = lang == "zh_CN" and "本层首通 %s · 上层扫荡 %s"
                        or Extra[lang]["本层首通 %s · 上层扫荡 %s"]
                    eq(labelAt(540, 1465).text, string.format(template, tostring(first), tostring(sweep)),
                        "真实 Page→Entry.drawTowerInfo 五语数字正文")
                    measuredInSlot(540, 1465, 760, "奖励正文")
                    measuredInSlot(540, 1710, 820, "规则正文")
                    local expectedReason = floor > 112 and I18n.format("%d层已全部通关", 112)
                        or I18n.lookup("三队均需至少1人，任意一队全灭即失败")
                    eq(labelAt(540, 1710).text, expectedReason, "真实详情规则正文")
                    eq(labelAt(750, 1633).text, I18n.lookup(floor > 112 and "全部通关" or "三军攻坚"),
                        "真实详情挑战标签")
                    if floor > 112 then
                        reject(expectedReason)
                        eq(nineAt(135, 1583).globalAlpha, 1, "全塔通关不封扫荡底板")
                        local sent = #sends
                        Page.handleInput(330, 1633)
                        eq(#sends, sent + 1, "113层真实输入仍发送扫荡")
                        eq(sends[#sends].action, Protocol.ACTION_TYPES.TOWER_SWEEP, "113层塔扫荡协议")
                    end
                end
                eq(cjson.encode(Tower.FLOORS), stableFloors, "奖励查询和绘制不修改配置")
            end)
        end
        runCase("Header绘制与热区同一矩形、消息三秒过期", function()
            I18n.set("en")
            modules.dungeon.babel_tower.floor = 2
            openTower()
            eq(labelAt(540, 225).text, I18n.lookup("返回列表"), "详情header返回列表")
            local back = nineAt(360, 180)
            eq(back.w, 360, "header绘制宽"); eq(back.h, 90, "header绘制高")
            for _, point in ipairs({ { 360, 180, true }, { 720, 270, true }, { 540, 225, true },
                { 359.99, 225, false }, { 720.01, 225, false }, { 540, 179.99, false }, { 540, 270.01, false } }) do
                eq(Entry.hitBack(point[1], point[2]), point[3], "绘制边界与输入一致")
            end
            measuredInSlot(540, 225, 320, "header返回正文")
            Page.handleInput(540, 225)
            eq(nav.selected, 5, "详情返回不切页签")
            draw(); eq(labelAt(540, 225).text, I18n.lookup("返回主界面"), "列表header返回主界面")
            Entry.showMessage(I18n.lookup("编队数据加载中"))
            local shown = Entry.getMessage()
            clock.elapsedTime = clock.elapsedTime + 2.999
            draw(); eq(labelAt(540, 2125).text, shown, "3秒前消息显示")
            clock.elapsedTime = clock.elapsedTime + 0.001
            eq(Entry.getMessage(), "", "达到3秒消息过期")
            draw()
            for _, label in ipairs(capture.labels) do check(label.y ~= 2125, "过期消息不绘制") end
            Page.handleInput(540, 225)
            eq(nav.selected, 3, "列表真实返回到tab3")
            eq(Entry.getMessage(), "", "退出列表清消息")
        end)
        runCase("失败发送/超时/返回后旧回包不复活", function()
            I18n.set("zh_CN")
            modules.battle = { maxStageId = 1906, clearedStages = {} }
            roster.counts, roster.applied = { 1, 1, 1 }, true
            openTower()
            for _, mode in ipairs({ "throw", "false" }) do
                transport.mode = mode
                eq(challenge(), 0, "发送失败不记录动作")
                eq(Entry.getMessage(), I18n.lookup("挑战发送失败，请重试"), "失败发送反馈")
                eq(state(Page.update, "pendingChallenge"), false, "失败发送释放等待")
            end
            transport.mode = "deferred"
            eq(challenge(), 1, "失败后可重试")
            local old = sends[#sends]
            Page.update(5)
            eq(Entry.getMessage(), I18n.lookup("挑战响应超时，请重试"), "超时反馈")
            eq(state(Page.update, "pendingChallenge"), false, "超时释放等待")
            eq(challenge(), 1, "超时后可重试")
            local current = sends[#sends]
            local opened = calls.towerOpen
            Page.onActionResult({ action = old.action, requestId = old.params.requestId, success = true, floor = 2 })
            eq(calls.towerOpen, opened, "旧请求回包不打开战斗")
            eq(state(Page.update, "pendingChallenge"), true, "旧回包不解除新请求")
            Page.onActionResult({ action = current.action, success = true, floor = 2 })
            eq(calls.towerOpen, opened, "无ID回包不打开战斗")
            Page.handleInput(540, 225)
            Page.onActionResult({ action = current.action, requestId = current.params.requestId, success = true, floor = 2 })
            eq(calls.towerOpen, opened, "已返回详情后旧回包不能复活")
        end)
        runCase("Esc全局优先、详情→列表→tab3与返回保护", function()
            ---@type any
            local Keyboard = env.require("ui.dev.KeyboardShortcuts")
            env.input = { GetKeyPress = function(_, key) return key == KEY_ESCAPE end,
                GetQualifierDown = function() return false end }
            openTower()
            for _, key in ipairs({ "reward", "level", "pip", "notice" }) do
                overlay[key] = true
                local before = calls[key]
                Keyboard.update()
                eq(calls[key], before + 1, "Esc优先关闭全局 " .. key)
                eq(state(Page.handleInput, "detailOpen"), true, "全局弹窗不返回详情 " .. key)
                eq(nav.selected, 5, "全局弹窗不切页签 " .. key)
            end
            overlay.offline = true
            local toastCount = calls.toast
            Keyboard.update()
            eq(calls.toast, toastCount + 1, "offline消费Esc并提示")
            eq(state(Page.handleInput, "detailOpen"), true, "offline不穿透详情")
            overlay.offline = false
            for _, key in ipairs({ "tutorial", "tower", "dungeon" }) do
                overlay[key] = true
                Page.handleInput(540, 225)
                eq(state(Page.handleInput, "detailOpen"), true, "真实header返回保护 " .. key)
                eq(nav.selected, 5, "保护不改nav " .. key)
                overlay[key] = false
            end
            nav.locked = true; Page.handleInput(540, 225)
            eq(state(Page.handleInput, "detailOpen"), true, "nav锁定保护")
            nav.locked = false
            Keyboard.update()
            eq(state(Page.handleInput, "detailOpen"), false, "真实Esc详情返回列表")
            eq(nav.selected, 5, "Esc第一步保持副本页")
            Keyboard.update()
            eq(nav.selected, 3, "真实Esc第二步返回tab3")
            eq(calls.towerOpen, 0, "Esc不触塔战斗出口")
            eq(calls.dungeonOpen, 0, "Esc不触普通战斗出口")
        end)
        runCase("旧日扫荡展示只读，返回释放扫荡pending", function()
            modules.dungeon.babel_tower = { floor = 113, dailyUsed = 2, dailyDay = today - 1, idleAccumSec = 0 }
            I18n.set("zh_CN")
            local stable = cjson.encode(modules.dungeon)
            openTower()
            eq(labelAt(540, 1530).text, I18n.format("今日扫荡次数:%d/%d", 2, 2), "跨日展示剩余2次")
            local before = #sends
            Page.handleInput(330, 1633)
            eq(#sends, before + 1, "旧日耗尽不封今天扫荡")
            Page.handleInput(330, 1633)
            eq(#sends, before + 1, "pending不重复扫荡")
            Page.handleInput(540, 225)
            openTower()
            Page.handleInput(330, 1633)
            eq(#sends, before + 2, "真实返回释放扫荡pending")
            eq(cjson.encode(modules.dungeon), stable, "跨日呈现不修改真实输入模块")
        end)
        runCase("脚本与全局缓存隔离", function()
            eq(require, nativeRequire, "全局require未替换")
            eq(time, nativeTime, "全局time未替换")
            for name, value in pairs(package.loaded) do eq(value, packageSnapshot[name], "缓存未污染 " .. name) end
            for name, value in pairs(packageSnapshot) do eq(package.loaded[name], value, "原缓存保留 " .. name) end
            eq(cjson.encode(Tower.FLOORS), stableFloors, "全部测试后塔奖励配置仍只读")
        end)
    end)
    if not ok then failures[#failures + 1] = "夹具错误: " .. tostring(err) end
    if #failures > 0 then
        print(TAG .. " FAIL: " .. #failures .. " failures, " .. assertions .. " assertions, " .. cases .. " cases")
        for _, failure in ipairs(failures) do print(TAG .. " FAIL " .. failure) end
    else
        print(TAG .. " ALL PASS: " .. assertions .. " assertions, " .. cases .. " cases")
    end
    engine:Exit()
end
