-- 自动战斗奖励延迟回归：隔离加载真实 RewardPopup / RewardCascade / BattleRewardOverlay。
-- 只有页面状态、资源绘制叶子、底层 NanoVG 和 SFX 是 spy；不加载 main，不访问玩家存档或联网。
-- cwd=/workspace: /home/Maker/validation-runtime/UrhoXRuntime tests/battle_reward_defer_test.lua
--                 -tapcode_dir=. -tool_mode -graphicsheadless -nosound
local assertions, cases, failures = 0, 0, 0
local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end
local function equal(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function near(actual, expected, label)
    check(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
        label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function run(label, fn)
    cases = cases + 1
    local ok, why = pcall(fn)
    if ok then print("[PASS] battle_reward_defer_test " .. label)
    else failures = failures + 1; print("[FAIL] battle_reward_defer_test " .. label .. ": " .. tostring(why)) end
end

function Start()
    -- cache:GetFile 仅打开项目源码；这里从不使用 File 写文件或加载存档模块。
    local sourceReads, forbiddenRequires = 0, 0
    local function source(name)
        local path = name:gsub("%.", "/") .. ".lua"
        local f = assert(cache:GetFile(path), "缺少真实源码 " .. path)
        assert(f:IsOpen(), "无法读取真实源码 " .. path)
        local lines = {}
        while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
        f:Dispose()
        sourceReads = sourceReads + 1
        return table.concat(lines, "\n")
    end
    local ok, err = pcall(function()
        local popupSource = source("ui.hud.popup.RewardPopup")
        local cascadeSource = source("ui.widget.RewardCascade")
        local blockerSource = source("boot.BattleRewardOverlay")
        ---@type any
        local env = setmetatable({}, { __index = _G })
        local clock = { elapsedTime = 100 }
        env.time = clock
        env.H_focusPanel = "center"
        local sounds, texts, ops, timelines = {}, {}, {}, {}
        local drawCalls, stackDepth = 0, 0
        local function noop() end
        local mods = {
            ["config.EquipmentConfig"] = {},
            ["core.DarkIcon"] = { QUALITY_TRIM = { { 180, 180, 180 }, { 230, 220, 140 },
                { 140, 220, 250 }, { 240, 170, 250 }, { 255, 200, 100 } }, drawIconDark = noop },
            ["config.HeroConfig"] = { get = function() return nil end },
            ["core.NumberUtil"] = { format = function(value) return tostring(value) end },
            ["core.DrawUtil"] = { drawTextStroke = noop },
            ["ui.widget.ImageCache"] = { init = noop, getEquipIcon = function() return -1 end,
                getQualityBg = function() return -1 end },
            ["config.ArtifactAssetUtil"] = { drawIcon = noop },
            ["config.ResourceDefs"] = { DEFS = { gold = { quality = 2, iconPath = "spy/gold.png" },
                diamond = { quality = 5, iconPath = "spy/diamond.png" } } },
            ["systems.GameSFX"] = { play = function(key) sounds[#sounds + 1] = key end },
            ["ui.widget.HeroFrame"] = { draw = noop },
        }
        -- 未白名单的依赖直接报错，而非回落到全局 require 或偷偷加载生产页面/存档。
        env.require = function(name)
            if mods[name] == nil then
                forbiddenRequires = forbiddenRequires + 1
                error("隔离测试禁止加载依赖 " .. tostring(name))
            end
            return mods[name]
        end
        local function compile(name, text)
            local chunk, why = load(text, "@" .. name, "t", env)
            assert(chunk, why)
            return chunk()
        end
        -- 所有 NanoVG 调用仅记录，没有 context / GPU / 字体 / 图片资源创建。
        local function drawSpy(name)
            return function(...)
                drawCalls = drawCalls + 1
                local args, record = { ... }, { name }
                for i = 2, #args do
                    local v = args[i]
                    record[#record + 1] = type(v) == "number" and string.format("%.7f", v) or tostring(v)
                end
                ops[#ops + 1] = table.concat(record, "|")
            end
        end
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgCircle", "nvgFillColor",
            "nvgFillPaint", "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgMoveTo",
            "nvgLineTo", "nvgClosePath", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgTranslate",
            "nvgScale", "nvgRotate", "nvgGlobalAlpha", "nvgIntersectScissor", "nvgResetScissor" }) do
            env[name] = drawSpy(name)
        end
        env.nvgSave = function() drawCalls = drawCalls + 1; stackDepth = stackDepth + 1 end
        env.nvgRestore = function()
            drawCalls = drawCalls + 1
            stackDepth = stackDepth - 1
            assert(stackDepth >= 0, "NanoVG restore 无对应 save")
        end
        env.nvgText = function(_, x, y, text)
            drawCalls = drawCalls + 1
            texts[#texts + 1] = text
            ops[#ops + 1] = string.format("text|%.7f|%.7f|%s", x, y, text)
        end
        env.nvgTextBounds = function(_, _, _, text) return #text * 12 end
        env.nvgCreateImage = function() return 900 end
        env.nvgRGBA = function(r, g, b, a) return string.format("rgba(%d,%d,%d,%d)", r, g, b, a) end
        env.nvgRadialGradient = function() return "radial" end
        env.nvgLinearGradient = function() return "linear" end
        env.nvgImagePattern = function() return "image" end

        local Cascade = compile("ui.widget.RewardCascade", cascadeSource)
        local actualNew = Cascade.new
        Cascade.new = function(count, opts)
            local timeline = actualNew(count, opts)
            timelines[#timelines + 1] = timeline
            return timeline
        end
        mods["ui.widget.RewardCascade"] = Cascade
        -- 页面 spy 只提供真实 blocker 读取的公开状态；不模拟 blocker 内部条件。
        local flags = { sweep = false, stats = false, select = false, terminal = false, equipment = false,
            forge = false, talent = false, talentWidth = 1, backpack = false, leftBackpack = true,
            dungeon = false, tower = false, nav = 3, info = false, offline = false, level = false,
            update = false, start = false, title = false, letter = false, intro = false, story = false,
            church = false, tavern = false, market = false, task = false, loot = false, rightDetail = false }
        local function pageFlag(key)
            return { isOpen = function() return flags[key] end, isActive = function() return flags[key] end }
        end
        for name, key in pairs({
            ["ui.battle.stage.SweepDialog"] = "sweep", ["ui.battle.popup.DamageStatsPanel"] = "stats",
            ["ui.battle.stage.StageSelectDialog"] = "select", ["ui.battle.popup.TerminalConfirmDialog"] = "terminal",
            ["ui.blacksmith.BlacksmithPage"] = "forge", ["ui.dungeon.DungeonBattleScene"] = "dungeon",
            ["ui.tower.TowerBattleScene"] = "tower", ["ui.hud.popup.PlayerInfoPanel"] = "info",
            ["ui.hud.popup.OfflineRewardPanel"] = "offline", ["ui.hud.popup.LevelUpPopup"] = "level",
            ["ui.hud.popup.UpdateNoticePopup"] = "update", ["ui.story.gate.StartScreen"] = "start",
            ["ui.story.gate.DarkTitleScreenGate"] = "title", ["ui.story.gate.LetterIntro"] = "letter",
            ["ui.story.gate.IntroCutscene"] = "intro", ["ui.story.ScenarioDialogue"] = "story",
            ["ui.church.ChurchPage"] = "church", ["ui.tavern.TavernPage"] = "tavern",
            ["ui.market.MarketPage"] = "market", ["ui.story.task.TaskPage"] = "task",
            ["ui.loot.LootBox"] = "loot", ["ui.character.detail.CharacterDetailPanel"] = "rightDetail",
        }) do mods[name] = pageFlag(key) end
        mods["ui.character.equip.EquipmentBag"] = { shouldBattleOverlay = function() return flags.equipment end }
        mods["ui.church.talent.TalentPage"] = { isOpen = function() return flags.talent end,
            getHorizonWidthScale = function() return flags.talentWidth end }
        mods["ui.backpack.BackpackPanel"] = { isOpen = function() return flags.backpack end,
            isLeftMode = function() return flags.leftBackpack end }
        mods["ui.hud.BottomNav"] = { getSelectedIndex = function() return flags.nav end }
        local Blocker = compile("boot.BattleRewardOverlay", blockerSource)
        local forcedBlock = false
        local function predicate() return forcedBlock or Blocker.isBlocked() end
        local function clearFlags()
            for key, value in pairs(flags) do if type(value) == "boolean" then flags[key] = false end end
            flags.leftBackpack, flags.talentWidth, flags.nav = true, 1, 3
        end
        ---@type any
        local Reward = {}
        local function fixture()
            clearFlags()
            forcedBlock = false
            clock.elapsedTime = clock.elapsedTime + 1000
            sounds, texts, ops, timelines = {}, {}, {}, {}
            drawCalls, stackDepth = 0, 0
            env.H_focusPanel = "center"
            Reward = compile("ui.hud.popup.RewardPopup", popupSource)
            Reward.setBattleBlocked(predicate)
            Reward.init({})
        end
        local function advance(dt)
            clock.elapsedTime = clock.elapsedTime + dt
            Reward.update(dt)
        end
        local function render(method)
            texts, ops, drawCalls = {}, {}, 0
            if method == "global" then Reward.draw({})
            elseif method == "content" then Reward.drawContent({})
            else Reward.drawRegion({}, 486, 0, 948, 1080, 1) end
            equal(stackDepth, 0, "绘制后恢复全部 NanoVG 状态")
            return table.concat(ops, "\n")
        end
        local function hasText(text)
            for _, seen in ipairs(texts) do if seen == text then return true end end
            return false
        end
        local function currentTitle(title, method)
            render(method)
            check(hasText(title), "真实绘制标题 " .. title)
        end
        local function rewardItems(n, start)
            local items = {}
            for i = 1, n do items[i] = { type = "gold", amount = (start or 100) + i } end
            return items
        end
        local function battle(title, items, extra)
            local opts = { row = 1, panel = "center", cascade = true }
            for key, value in pairs(extra or {}) do opts[key] = value end
            Reward.show(title, items or rewardItems(12), opts)
        end
        local function invisible()
            equal(Reward.isOpen(), false, "blocked/pending 不占据 isOpen 输入层")
            equal(Reward.currentRowTag(), nil, "blocked/pending 无可见 rowTag")
            equal(Reward.currentPanel(), nil, "blocked/pending 无可见 panel")
            equal(Reward.hitPanel(540, 1000), false, "blocked/pending hitPanel 不可命中")
            for _, method in ipairs({ "global", "content", "row" }) do
                render(method)
                equal(drawCalls, 0, method .. " 不提交任何绘制")
            end
        end
        local function transparentInput()
            equal(Reward.handleInput(540, 1000), false, "blocked input 透给 overlay")
            equal(Reward.handleInputRegion(960, 540, 486, 0, 948, 1080), false, "blocked 行内 input 透给 overlay")
            equal(Reward.handleDragBegin(540, 1000), false, "blocked dragBegin 透传")
            equal(Reward.handleDragMove(540, 900), false, "blocked dragMove 透传")
            equal(Reward.handleDragEnd(540, 900), false, "blocked dragEnd 透传")
            check(Reward.handleScroll(3) ~= true, "blocked scroll 不消费")
            equal(Reward.consumedDrag(), false, "blocked consumedDrag 不吞 overlay 点击")
        end
        local function closeAndDrain()
            Reward.close()
            advance(0.26)
            advance(0.16)
            Reward.update(0)
        end

        run("真实 blocker 所有中栏状态阻挡，关闭后恢复", function()
            fixture()
            equal(Blocker.isBlocked(), false, "空闲中栏不阻挡")
            for _, key in ipairs({ "sweep", "stats", "select", "terminal", "equipment", "forge", "dungeon",
                "tower", "info", "offline", "level", "update", "start", "title", "letter", "intro", "story" }) do
                flags[key] = true
                equal(Blocker.isBlocked(), true, "真实中栏 blocker " .. key)
                flags[key] = false
                equal(Blocker.isBlocked(), false, "中栏关闭后 blocker 释放 " .. key)
            end
            flags.talent, flags.talentWidth = true, 1.5
            equal(Blocker.isBlocked(), true, "宽古树覆盖中栏")
            flags.talent, flags.talentWidth = false, 1
            flags.backpack, flags.leftBackpack = true, false
            equal(Blocker.isBlocked(), true, "全窗背包覆盖中栏")
            flags.backpack, flags.leftBackpack = false, true
            flags.nav = 5
            equal(Blocker.isBlocked(), true, "副本塔导航页覆盖中栏")
            flags.nav = 3
            equal(Blocker.isBlocked(), false, "回到战斗中栏释放")
        end)
        run("真实 blocker 不误挡侧栏与窄古树", function()
            fixture()
            for _, key in ipairs({ "church", "tavern", "market", "task", "loot", "rightDetail" }) do
                flags[key] = true
                equal(Blocker.isBlocked(), false, "侧栏不阻挡 " .. key)
            end
            flags.backpack, flags.leftBackpack = true, true
            flags.talent, flags.talentWidth = true, 1
            equal(Blocker.isBlocked(), false, "左背包/窄古树不覆盖中栏")
            battle("侧栏共存首通", rewardItems(2))
            equal(Reward.currentRowTag(), 1, "侧栏开启时 row 仍正常显示")
            advance(0.18)
            currentTitle("侧栏共存首通")
            check(#sounds > 1, "侧栏共存时真实 cascade 正常播放")
        end)
        run("长等待不创建时间轴不偷播 SFX，pending 不可见", function()
            fixture()
            flags.stats = true
            battle("长等待首通", rewardItems(12))
            equal(Reward.hasPendingBattleRewards(), true, "queued 奖励可供剧情等待")
            equal(#timelines, 0, "等待时不创建/启动真实 cascade")
            equal(#sounds, 0, "等待时没有获得/开场 SFX")
            invisible(); transparentInput()
            for _ = 1, 20 do advance(60); invisible(); transparentInput() end
            equal(#timelines, 0, "1200 秒等待不偷跑时间轴")
            equal(#sounds, 0, "1200 秒等待不补播音效")
            flags.stats = false
            Reward.update(0)
            equal(Reward.currentRowTag(), 1, "空闲 update 才 pump 首通")
            equal(#timelines, 1, "pump 只创建一次时间轴")
            equal(#sounds, 1, "pump 开场只播一次 SFX")
            near(timelines[1].revealStart, clock.elapsedTime + Cascade.LEAD, "等待时长不计入 cascade 起点")
            equal(timelines[1]:t(1), nil, "解遮挡当帧首件尚未出现")
            currentTitle("长等待首通")
            advance(0.18)
            check(timelines[1]:t(1) > 0 and timelines[1]:t(1) < 1, "解遮挡后按原 lead 逐件开始")
            equal(#sounds, 2, "解遮挡后只获得第一件，不补播全部")
        end)
        run("FIFO 多个请求不覆盖，各回调恰一次", function()
            fixture()
            forcedBlock = true
            local closed = {}
            for i, title in ipairs({ "FIFO首通A", "FIFO掉落B", "FIFO首通C" }) do
                battle(title, rewardItems(i, i * 100), { cascade = false,
                    onClose = function() closed[#closed + 1] = title end })
            end
            advance(900)
            invisible()
            forcedBlock = false
            Reward.update(0)
            for i, title in ipairs({ "FIFO首通A", "FIFO掉落B", "FIFO首通C" }) do
                currentTitle(title)
                equal(#closed, i - 1, "先前请求才被关闭，当前未覆盖 " .. title)
                equal(#timelines, i, "每个出队请求只创建一个时间轴")
                advance(0.1)
                Reward.close()
                advance(0.26)
                equal(#closed, i, "动画完成才回调 " .. title)
                equal(closed[i], title, "FIFO 回调顺序 " .. title)
                -- closed guard 不让下一个 row 在残留 up 中被关。
                equal(Reward.currentRowTag(), nil, "close guard 时下一个尚未显示")
                equal(Reward.handleInput(0, 0), true, "close guard 吞残留点击")
                advance(0.16)
                Reward.update(0)
            end
            equal(Reward.hasPendingBattleRewards(), false, "全部 FIFO 完成后清空剧情等待")
            equal(Reward.isOpen(), false, "全部完成后无残留展示")
        end)
        run("正在展示 row 时后续 row FIFO，不覆盖当前", function()
            fixture()
            battle("可见首通A", rewardItems(2), { cascade = false })
            advance(0.4)
            battle("排队掉落B", rewardItems(3), { cascade = false })
            battle("排队掉落C", rewardItems(4), { cascade = false })
            currentTitle("可见首通A")
            equal(#timelines, 1, "忙碌时排队不创建替代时间轴")
            closeAndDrain(); currentTitle("排队掉落B")
            closeAndDrain(); currentTitle("排队掉落C")
            closeAndDrain()
            equal(Reward.hasPendingBattleRewards(), false, "后续队列全部 drain")
        end)
        run("opening/cascade 长遮挡冻结，恢复原动画与首件进度", function()
            fixture()
            local closed = 0
            battle("暂停首通", rewardItems(12), { onClose = function() closed = closed + 1 end })
            advance(0.18)
            local timeline = timelines[1]
            local progress, elapsed = timeline:t(1), timeline:elapsed()
            local before = render("content")
            local soundCount = #sounds
            check(progress > 0 and progress < 1 and hasText("点击跳过"), "遮挡前 opening 且首件 pop")
            forcedBlock = true
            invisible(); transparentInput()
            for _ = 1, 20 do advance(60) end
            invisible(); transparentInput()
            equal(#sounds, soundCount, "悬挂 1200 秒不播放任何补偿 SFX")
            equal(#timelines, 1, "悬挂不新建/重启 cascade")
            equal(closed, 0, "悬挂不触发 onClose")
            forcedBlock = false
            Reward.update(0)
            near(timeline:elapsed(), elapsed, "恢复 cascade 保留暂停前 elapsed")
            near(timeline:t(1), progress, "恢复首件保留原 pop 进度")
            equal(render("content"), before, "恢复 opening 的实际 alpha/scale/粒子/text 全部原进度")
            equal(#sounds, soundCount, "恢复当帧不重播首件或开场 SFX")
            advance(0.05)
            check(timeline:t(2) > 0 and timeline:t(3) == nil, "随后只推进下一件，未偷跑尾部")
            equal(#sounds, soundCount + 1, "恢复后下一件仅播放一次获得 SFX")
        end)
        run("closing 遮挡冻结，不提前 callback；恢复后仅剩余时长", function()
            fixture()
            local closed = 0
            battle("关闭暂停掉落", rewardItems(1), { cascade = false, onClose = function() closed = closed + 1 end })
            advance(0.5)
            Reward.close()
            advance(0.1)
            local before = render("content")
            forcedBlock = true
            invisible()
            advance(500)
            equal(closed, 0, "blocked closing 长等待不执行 callback")
            forcedBlock = false
            Reward.update(0)
            equal(render("content"), before, "恢复 closing 的实际 alpha/scale 原进度")
            advance(0.1)
            equal(closed, 0, "恢复后尚未够剩余 closing 时长")
            advance(0.06)
            equal(closed, 1, "累计可见关闭时长到阈值后仅回调一次")
            advance(1)
            equal(closed, 1, "后续 update 不重入 callback")
            equal(Reward.hasPendingBattleRewards(), false, "完成 closing 清 battle 等待")
        end)
        run("blocked close 不碰隐藏 row，输入继续透给 overlay", function()
            fixture()
            local closed, clicks, overlayClicks = 0, 0, 0
            battle("隐藏不可关首通", rewardItems(2), { onClose = function() closed = closed + 1 end,
                onItemClick = function() clicks = clicks + 1 end })
            advance(0.18)
            local before, soundCount = timelines[1]:t(1), #sounds
            flags.sweep = true
            invisible(); transparentInput()
            if not Reward.handleInput(540, 1000) then overlayClicks = overlayClicks + 1 end
            equal(overlayClicks, 1, "奖励 false 使 overlay 获得本次输入")
            Reward.close() -- generic/global close 不得关掉当前不可见 battle row。
            advance(600)
            equal(closed, 0, "blocked generic close 不触发 row callback")
            equal(clicks, 0, "blocked input 不触发 row 物品 callback")
            equal(#sounds, soundCount, "blocked input 不 skip cascade 或播音效")
            flags.sweep = false
            Reward.update(0)
            currentTitle("隐藏不可关首通")
            near(timelines[1]:t(1), before, "generic close 后 row/cascade 仍原进度")
            equal(closed, 0, "重新可见时 row 未被提前关")
        end)
        run("遮挡第一次查询为 consumedDrag 也必须清除 row 手势", function()
            fixture()
            battle("拖拽暂停掉落", rewardItems(20), { cascade = false })
            advance(0.6)
            equal(Reward.handleDragBegin(540, 1000), true, "可见 row 接受 dragBegin")
            equal(Reward.handleDragMove(540, 950), true, "可见 row 接受 dragMove")
            equal(Reward.consumedDrag(), true, "遮挡前真实拖动超过阈值")
            forcedBlock = true
            equal(Reward.consumedDrag(), false, "首个 blocked consumedDrag 不能吞 overlay 手势")
            invisible(); transparentInput()
            advance(300)
            forcedBlock = false
            Reward.update(0)
            equal(Reward.consumedDrag(), false, "恢复后无旧 dragMoved")
            currentTitle("拖拽暂停掉落")
        end)
        run("resume 同一关闭手势 guard，不 skip 或误关 row", function()
            fixture()
            local closed = 0
            battle("手势保护掉落", rewardItems(1), { cascade = false, onClose = function() closed = closed + 1 end })
            advance(0.5)
            flags.stats = true
            invisible()
            advance(90)
            equal(Reward.handleDragBegin(0, 0), false, "遮挡窗口的 down 不属于 row")
            flags.stats = false -- overlay 在自己的 up/click 中关闭。
            equal(Reward.handleInput(0, 0), true, "恢复同帧吞关闭手势，不启动 row close")
            Reward.update(0)
            advance(0.02)
            equal(closed, 0, "关闭手势不会触发回调")
            currentTitle("手势保护掉落")
            advance(0.2)
            equal(Reward.handleInput(0, 0), true, "新的独立点击正常关闭 row")
            advance(0.26)
            equal(closed, 1, "新手势关闭后正常回调一次")
        end)
        run("global 扫荡奖励优先于 deferred FIFO，不覆盖 queued 请求", function()
            fixture()
            flags.sweep = true
            local closed = {}
            battle("延迟首通A", rewardItems(1), { cascade = false, onClose = function() closed[#closed + 1] = "A" end })
            battle("延迟掉落B", rewardItems(2), { cascade = false, onClose = function() closed[#closed + 1] = "B" end })
            Reward.show("扫荡全局奖励", rewardItems(3), { panel = "center", cascade = false,
                onClose = function() closed[#closed + 1] = "global" end })
            equal(Reward.isOpen(), true, "普通 no-row global 即时显示，即使中栏 predicate 为 true")
            equal(Reward.currentRowTag(), nil, "global 保持无 row")
            currentTitle("扫荡全局奖励", "global")
            equal(Reward.hasPendingBattleRewards(), true, "global 不清空 battle 等待")
            flags.sweep = false
            advance(600)
            currentTitle("扫荡全局奖励", "global")
            equal(#closed, 0, "deferred pump 不覆盖/关闭仍打开的 global")
            closeAndDrain()
            equal(closed[1], "global", "global 先完成")
            currentTitle("延迟首通A")
            closeAndDrain(); currentTitle("延迟掉落B")
            closeAndDrain()
            equal(table.concat(closed, ","), "global,A,B", "global 完成后恢复完整 FIFO")
        end)
        run("global 插入保留悬挂 active row/cascade/callback，再恢复后续 FIFO", function()
            fixture()
            local closed = {}
            battle("悬挂首通A", rewardItems(12), { onClose = function() closed[#closed + 1] = "A" end })
            advance(0.18)
            local active, progress, elapsed = timelines[1], timelines[1]:t(1), timelines[1]:elapsed()
            local soundCount = #sounds
            flags.sweep = true
            invisible()
            battle("后续掉落B", rewardItems(1), { cascade = false, onClose = function() closed[#closed + 1] = "B" end })
            advance(100)
            Reward.show("扫荡结果", rewardItems(1), { panel = "center", cascade = false,
                onClose = function() closed[#closed + 1] = "global" end })
            currentTitle("扫荡结果", "global")
            flags.sweep = false
            advance(100)
            currentTitle("扫荡结果", "global")
            closeAndDrain()
            equal(table.concat(closed, ","), "global", "global close 不触碰悬挂 row callback")
            currentTitle("悬挂首通A")
            equal(#timelines, 2, "恢复原 row 不新建时间轴；仅 global 创建第二条")
            -- closeAndDrain 包括 guard 的时间；原 row 应仍只恢复原进度，没有旧等待时长。
            near(active:t(1), progress, "global 完成恢复原首件 pop")
            near(active:elapsed(), elapsed, "global 可见时长不计入 row 时间轴")
            equal(#sounds, soundCount, "global 恢复原 row 不重播开场/已播获得音")
            advance(0.2)
            Reward.handleInput(0, 0) -- 未完成 cascade 的首击只 skip。
            advance(0.1)
            currentTitle("悬挂首通A")
            Reward.handleInput(0, 0)
            advance(0.26); advance(0.16); Reward.update(0)
            currentTitle("后续掉落B")
            closeAndDrain()
            equal(table.concat(closed, ","), "global,A,B", "悬挂 active 在后续 queue 之前恢复且回调仅一次")
        end)
        run("global 打断 closing row 保留剩余关闭动画和 callback", function()
            fixture()
            local rowClosed, globalClosed = 0, 0
            battle("被打断关闭掉落", rewardItems(1), { cascade = false, onClose = function() rowClosed = rowClosed + 1 end })
            advance(0.5)
            Reward.close()
            advance(0.1)
            local before = render("content")
            flags.sweep = true
            invisible()
            advance(30)
            Reward.show("打断关闭扫荡结果", rewardItems(1), { cascade = false, panel = "center",
                onClose = function() globalClosed = globalClosed + 1 end })
            flags.sweep = false
            advance(30)
            equal(rowClosed, 0, "global 展示期间隐藏 closing row 不回调")
            closeAndDrain()
            equal(globalClosed, 1, "global 正常关闭")
            equal(rowClosed, 0, "global close 不直接关闭隐藏 row")
            check(Reward.hasPendingBattleRewards(), "closing row 仍处于待完成生命周期")
            equal(render("content"), before, "恢复 closing 原 alpha/scale，不重开 row")
            advance(0.1)
            equal(rowClosed, 0, "剩余 closing 时长未满不回调")
            advance(0.06)
            equal(rowClosed, 1, "恢复后累计关闭时长完成才回调")
            advance(1)
            equal(rowClosed, 1, "closing 回调恰一次")
            equal(Reward.hasPendingBattleRewards(), false, "closing row 不丢不悬挂")
        end)
        run("reset 丢旧 pending/悬挂行，不触发旧 callback，允许新会话", function()
            fixture()
            local oldClosed, newClosed = 0, 0
            battle("旧悬挂首通", rewardItems(12), { onClose = function() oldClosed = oldClosed + 1 end })
            advance(0.18)
            forcedBlock = true
            invisible()
            battle("旧 pending 掉落", rewardItems(2), { onClose = function() oldClosed = oldClosed + 1 end })
            equal(Reward.hasPendingBattleRewards(), true, "reset 前有旧待奖励")
            Reward.clearBattleRewards()
            equal(Reward.hasPendingBattleRewards(), false, "reset 清 pending 和悬挂 row")
            equal(oldClosed, 0, "reset 不是领奖，不执行旧 onClose")
            forcedBlock = false
            advance(1000)
            invisible()
            equal(oldClosed, 0, "reset 后旧奖励永久丢弃，不延迟回调")
            battle("新会话掉落", rewardItems(1), { cascade = false, onClose = function() newClosed = newClosed + 1 end })
            currentTitle("新会话掉落")
            closeAndDrain()
            equal(newClosed, 1, "新会话奖励正常关闭")
            equal(oldClosed, 0, "新会话不会触发旧 callback")
        end)
        run("clear 只清 battle，普通 left 奖励保持即时/动画/输入/回调", function()
            fixture()
            forcedBlock = true
            local leftClosed, oldClosed, clicked = 0, 0, 0
            battle("待清首通", rewardItems(2), { onClose = function() oldClosed = oldClosed + 1 end })
            local item = rewardItems(1)[1]
            Reward.show("左栏普通宝箱", { item }, { panel = "left", cascade = true,
                onClose = function() leftClosed = leftClosed + 1 end,
                onItemClick = function(got, index)
                    check(got == item and index == 1, "普通 left 保留原 item/index callback")
                    clicked = clicked + 1
                end })
            equal(Reward.currentPanel(), "left", "普通 left 不受 battle blocker")
            equal(Reward.currentRowTag(), nil, "普通 left 不转成 row")
            equal(Reward.isOpen(), true, "普通 left 即时 open")
            equal(#sounds, 1, "普通 left 原开场音即时播放")
            advance(0.18)
            local leftTimeline, progress = timelines[1], timelines[1]:t(1)
            currentTitle("左栏普通宝箱", "content")
            check(progress > 0 and progress < 1, "blocked 中栏时 left 仍正常 cascade")
            Reward.clearBattleRewards()
            equal(Reward.hasPendingBattleRewards(), false, "clear 删除 battle pending")
            equal(Reward.currentPanel(), "left", "clear 不删除普通 left")
            currentTitle("左栏普通宝箱", "content")
            equal(oldClosed, 0, "clear 不执行旧 battle callback")
            advance(0.4)
            check(leftTimeline:finished(), "普通 left 不冻结、不受 blocked 中栏影响")
            equal(Reward.hitPanel(540, 1000), true, "普通 left 命中面板原行为")
            -- 单件缩放0.7，格子中心1008经974锚点缩放后为997.8。
            equal(Reward.handleInput(540, 997.8), true, "普通 left 仍可点击物品")
            equal(clicked, 1, "普通 left 物品 callback 恰一次")
            closeAndDrain()
            equal(leftClosed, 1, "普通 left 正常 onClose")
            equal(oldClosed, 0, "普通 left 完成后不复活旧 battle")
            equal(Reward.hasPendingBattleRewards(), false, "普通 left 不创建 battle pending")
        end)
        run("隔离边界：只有三份源码，只允许 spy 依赖", function()
            equal(sourceReads, 3, "只读 Popup/Cascade/Blocker 三份实际源码")
            equal(forbiddenRequires, 0, "无 main、玩家存档、网络模块加载")
        end)
    end)
    if not ok then failures = failures + 1; print("[FAIL] battle_reward_defer_test Start: " .. tostring(err)) end
    if failures == 0 then
        print("[battle_reward_defer_test] ALL PASS: " .. cases .. " cases, " .. assertions .. " assertions")
    else
        print("[FAIL] battle_reward_defer_test: " .. failures .. " failures / " .. cases .. " cases, " .. assertions .. " assertions")
    end
    engine:Exit()
end
