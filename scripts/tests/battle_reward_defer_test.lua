-- 自动战斗奖励延迟回归：隔离加载真实 RewardPopup / RewardCascade / BattleRewardOverlay。
-- 只有页面状态、资源绘制叶子、底层 NanoVG 和 SFX 是 spy；不加载 main，不访问玩家存档或联网。
-- cwd=/workspace: /workspace/.cli/UrhoXRuntime tests/battle_reward_defer_test.lua
--                 -tapcode_dir=/workspace -tool_mode -graphicsheadless -nosound
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
    local sourceReads, routingSourceReads, forbiddenRequires = 0, 0, 0
    local function source(name, routing)
        local path = name:gsub("%.", "/") .. ".lua"
        local f = assert(cache:GetFile(path), "缺少真实源码 " .. path)
        assert(f:IsOpen(), "无法读取真实源码 " .. path)
        local lines = {}
        while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
        f:Dispose()
        if routing then routingSourceReads = routingSourceReads + 1
        else sourceReads = sourceReads + 1 end
        return table.concat(lines, "\n")
    end
    local ok, err = pcall(function()
        local popupSource = source("ui.hud.popup.RewardPopup")
        local cascadeSource = source("ui.widget.RewardCascade")
        local queueSource = source("ui.widget.BattleRewardQueue")
        local blockerSource = source("boot.BattleRewardOverlay")
        local triSource = source("ui.battle.tri.BattleTriPage", true)
        local horizonInputSource = source("boot.StandaloneHorizonInput", true)
        local seamGestureSource = source("boot.SeamBackGesture", true)
        local marqueeGestureSource = source("boot.DecomposeMarqueeGesture", true)
        local horizonWheelSource = source("boot.StandaloneHorizonWheel", true)
        ---@type any
        local env = setmetatable({}, { __index = _G })
        local clock = { elapsedTime = 100 }
        env.time = clock
        env.H_focusPanel = "center"
        local sounds, texts, ops, timelines = {}, {}, {}, {}
        local textRecords, panelRecords, matrixStack = {}, {}, {}
        -- NanoVG 仿射矩阵 [a,b,c,d,e,f]：完整跟踪 save/restore、平移、缩放、旋转，
        -- 文本/面板记录窗口实际坐标，而不是仅检查设计空间常量。
        ---@type number[]
        local transform = { 1, 0, 0, 1, 0, 0 }
        local fontSize = 0
        local function point(x, y)
            return transform[1] * x + transform[3] * y + transform[5],
                transform[2] * x + transform[4] * y + transform[6]
        end
        local function compose(a, b, c, d, e, f)
            local m = transform
            transform = { m[1] * a + m[3] * b, m[2] * a + m[4] * b,
                m[1] * c + m[3] * d, m[2] * c + m[4] * d,
                m[1] * e + m[3] * f + m[5], m[2] * e + m[4] * f + m[6] }
        end
        local drawCalls, stackDepth = 0, 0
        local function noop() end
        local mods = {
            ["core.I18n"] = { lookup = function(value) return value end },
            ["config.EquipmentConfig"] = {},
            ["core.DarkIcon"] = { QUALITY_TRIM = { { 180, 180, 180 }, { 230, 220, 140 },
                { 140, 220, 250 }, { 240, 170, 250 }, { 255, 200, 100 } }, drawIconDark = noop },
            ["config.HeroConfig"] = { get = function() return nil end },
            ["core.NumberUtil"] = { format = function(value) return tostring(value) end },
            ["core.DrawUtil"] = { drawTextStroke = function(vg, x, y, text) env.nvgText(vg, x, y, text) end,
                -- 新版Popup把原背景rect交给共享图片绘制叶子；保留实际尺寸/仿射记录。
                drawImageCentered = function(vg, _, cx, cy, w, h)
                    env.nvgBeginPath(vg)
                    env.nvgRect(vg, cx - w * 0.5, cy - h * 0.5, w, h)
                    env.nvgFill(vg)
                end },
            ["ui.widget.ImageCache"] = { init = noop, getEquipIcon = function() return -1 end,
                getQualityBg = function() return -1 end },
            ["config.ArtifactAssetUtil"] = { drawIcon = noop },
            ["config.ResourceDefs"] = { DEFS = { gold = { quality = 2, iconPath = "spy/gold.png" },
                diamond = { quality = 5, iconPath = "spy/diamond.png" } } },
            ["systems.GameSFX"] = { play = function(key) sounds[#sounds + 1] = key end },
            ["ui.widget.HeroFrame"] = { draw = noop },
            -- 本专项没有repeatDraw请求；新增主动开箱页脚不应进入普通/战斗绘制路径。
            ["ui.widget.ResultRepeatFooter"] = {
                EXTRA_HEIGHT = 100, HINT_Y = 1334,
                draw = function() error("普通/战斗奖励误绘制主动开箱页脚") end,
                hit = function() error("普通/战斗奖励误命中主动开箱页脚") end,
            },
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
        local function affineSpy(name, effect)
            local record = drawSpy(name)
            return function(...)
                record(...)
                effect(...)
            end
        end
        env.nvgTranslate = affineSpy("nvgTranslate", function(_, x, y) compose(1, 0, 0, 1, x, y) end)
        env.nvgScale = affineSpy("nvgScale", function(_, x, y) compose(x, 0, 0, y, 0, 0) end)
        env.nvgRotate = affineSpy("nvgRotate", function(_, angle)
            local c, s = math.cos(angle), math.sin(angle)
            compose(c, s, -s, c, 0, 0)
        end)
        env.nvgFontSize = affineSpy("nvgFontSize", function(_, size) fontSize = size end)
        env.nvgRect = affineSpy("nvgRect", function(_, x, y, w, h)
            if w == 1080 and h == 685 then
                local left, top = point(x, y)
                local right, bottom = point(x + w, y + h)
                panelRecords[#panelRecords + 1] = { left = left, top = top, right = right, bottom = bottom }
            end
        end)
        env.nvgSave = function()
            drawCalls = drawCalls + 1
            stackDepth = stackDepth + 1
            matrixStack[stackDepth] = { matrix = transform, font = fontSize }
        end
        env.nvgRestore = function()
            drawCalls = drawCalls + 1
            assert(stackDepth > 0, "NanoVG restore 无对应 save")
            local saved = matrixStack[stackDepth]
            transform, fontSize = saved.matrix, saved.font
            matrixStack[stackDepth] = nil
            stackDepth = stackDepth - 1
        end
        env.nvgText = function(_, x, y, text)
            drawCalls = drawCalls + 1
            texts[#texts + 1] = text
            local wx, wy = point(x, y)
            textRecords[#textRecords + 1] = { text = text, x = wx, y = wy, designX = x, designY = y,
                halfHeight = fontSize * 0.5 * math.sqrt(transform[3]^2 + transform[4]^2) }
            ops[#ops + 1] = string.format("text|%.7f|%.7f|%s", x, y, text)
        end
        env.nvgTextBounds = function(_, _, _, text) return #text * 12 end
        env.nvgCreateImage = function() return 900 end
        env.nvgRGBA = function(r, g, b, a) return string.format("rgba(%d,%d,%d,%d)", r, g, b, a) end
        env.nvgRadialGradient = function() return "radial" end
        env.nvgLinearGradient = function() return "linear" end
        env.nvgImagePattern = function() return "image" end

        mods["ui.widget.RewardItemView"] = compile("ui.widget.RewardItemView", source("ui.widget.RewardItemView", true))
        mods["ui.widget.RewardLargeView"] = compile("ui.widget.RewardLargeView", source("ui.widget.RewardLargeView", true))
        local rewardGestureSource = source("boot.RewardGesture", true)
        local Queue = compile("ui.widget.BattleRewardQueue", queueSource)
        mods["ui.widget.BattleRewardQueue"] = Queue
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
            textRecords, panelRecords, matrixStack = {}, {}, {}
            transform, fontSize = { 1, 0, 0, 1, 0, 0 }, 0
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
        local function render(method, rect)
            texts, ops, textRecords, panelRecords, drawCalls = {}, {}, {}, {}, 0
            if method == "global" then Reward.draw({})
            elseif method == "content" then Reward.drawContent({})
            else
                local r = rect or { 486, 0, 948, 1080 }
                Reward.drawRegion({}, r[1], r[2], r[3], r[4], 1)
            end
            equal(stackDepth, 0, "绘制后恢复全部 NanoVG 状态")
            near(transform[1], 1, "绘制后仿射 a 恢复")
            near(transform[4], 1, "绘制后仿射 d 恢复")
            near(transform[5], 0, "绘制后仿射平移 x 恢复")
            near(transform[6], 0, "绘制后仿射平移 y 恢复")
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
            -- 多件动画必须用独立装备；gold 在 pending batch 中会按元数据累计为一项。
            for i = 1, n do
                items[i] = { type = "equip", templateId = "spy/W" .. tostring(i), quality = 3,
                    level = (start or 100) + i }
            end
            return items
        end
        local function gold(amount) return { { type = "gold", amount = amount } } end
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
        run("兼容 pending 请求合为一批，回调按请求顺序恰一次", function()
            fixture()
            forcedBlock = true
            local closed = {}
            for i, title in ipairs({ "合批首通A", "合批掉落B", "合批首通C" }) do
                battle(title, rewardItems(i, i * 100), { cascade = false,
                    onClose = function() closed[#closed + 1] = title end })
            end
            advance(900)
            invisible()
            forcedBlock = false
            Reward.update(0)
            currentTitle("战斗掉落")
            equal(#timelines, 1, "三个兼容请求只创建一批时间轴")
            equal(timelines[1].count, 6, "三请求六件装备独立保留")
            equal(#closed, 0, "合批展示不提前回调")
            advance(0.1)
            Reward.close()
            advance(0.24)
            equal(#closed, 0, "完整 .25s 关闭动画前不回调")
            advance(0.02)
            equal(table.concat(closed, ","), "合批首通A,合批掉落B,合批首通C", "关闭批次按原请求顺序回调")
            equal(Reward.currentRowTag(), nil, "close guard 时无下一展示")
            equal(Reward.handleInput(0, 0), true, "close guard 吞残留点击")
            advance(0.16)
            Reward.update(0)
            equal(#closed, 3, "后续 pump 不重复回调")
            equal(Reward.hasPendingBattleRewards(), false, "合批完成后清空剧情等待")
            equal(Reward.isOpen(), false, "合批完成后无残留展示")
        end)
        run("active 原动画不覆盖，后续请求只合并 pending batch", function()
            fixture()
            battle("可见首通A", rewardItems(12))
            advance(0.18)
            local active, progress, elapsed = timelines[1], timelines[1]:t(1), timelines[1]:elapsed()
            local before, soundCount = render("content"), #sounds
            battle("排队掉落B", rewardItems(3), { cascade = false })
            battle("排队掉落C", rewardItems(4), { cascade = false })
            currentTitle("可见首通A")
            equal(#timelines, 1, "忙碌时排队不创建替代时间轴")
            equal(active.count, 12, "后续请求不追加到 active items")
            near(active:t(1), progress, "active 首件进度不重启")
            near(active:elapsed(), elapsed, "active elapsed 保持")
            equal(render("content"), before, "active 绘制保持原动画")
            equal(#sounds, soundCount, "pending 合并不偷播音效")
            closeAndDrain(); currentTitle("战斗掉落")
            equal(#timelines, 2, "后续 B/C 只开启一条新时间轴")
            equal(timelines[2].count, 7, "后续 batch 保留七件装备")
            closeAndDrain()
            equal(Reward.hasPendingBattleRewards(), false, "后续合批全部 drain")
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
        run("global 扫荡奖励优先于 deferred batch，不覆盖 queued 请求", function()
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
            currentTitle("战斗掉落")
            equal(timelines[2].count, 3, "global 后两个延迟请求合为三装备 batch")
            closeAndDrain()
            equal(table.concat(closed, ","), "global,A,B", "global 完成后合批仍按原请求顺序回调")
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
        run("Queue 同元数据资源累计，装备超过十件独立，输入与回调隔离", function()
            fixture()
            local queue = Queue.new(mods["config.ResourceDefs"].DEFS)
            local first, second = gold(100), gold(250)
            local gear = rewardItems(16)
            first[#first + 1] = gear[1]
            local callbacks = {}
            local opts = { row = 1, panel = "center", subtitle = "同批", cascade = false,
                onClose = function() callbacks[#callbacks + 1] = "A"; error("expected callback failure") end }
            queue:push("首通", first, opts)
            for i = 2, #gear do second[#second + 1] = gear[i] end
            queue:push("掉落", second, { row = 1, panel = "center", subtitle = "同批", cascade = true,
                onClose = function() callbacks[#callbacks + 1] = "B" end })
            queue:push("掉落", gold(50), { row = 1, panel = "center", subtitle = "同批",
                onClose = function() callbacks[#callbacks + 1] = "C" end })
            equal(#queue.entries, 1, "兼容请求仅一 pending batch")
            local batch = queue:pop()
            equal(batch.count, 3, "batch 保留三个请求")
            equal(batch.title, "战斗掉落", "不同标题合并使用战斗掉落")
            equal(batch.opts.cascade, true, "任意请求 cascade=true 则合批级联")
            equal(#batch.rewards, 17, "资源合为一项，16 装备不累计")
            equal(batch.rewards[1].amount, 400, "单项 gold 数量累计为400")
            equal(first[1].amount, 100, "第一请求 amount 不被修改")
            equal(second[1].amount, 250, "第二请求 amount 不被修改")
            equal(opts.onClose ~= batch.opts.onClose, true, "调用者 opts.onClose 不被改写")
            for i = 1, 16 do
                equal(batch.rewards[i + 1].templateId, gear[i].templateId, "装备顺序保留 " .. i)
                check(batch.rewards[i + 1] ~= gear[i], "装备副本隔离 " .. i)
            end
            first[1].amount, gear[1].level = 9999, 9999
            equal(batch.rewards[1].amount, 400, "调用者后续修改不改变展示数量")
            equal(batch.rewards[2].level, 101, "调用者装备后续修改不改变展示等级")
            batch.opts.onClose()
            equal(table.concat(callbacks, ","), "A,B,C", "A 报错仍按请求顺序调用 B/C")
            batch.opts.onClose()
            equal(table.concat(callbacks, ","), "A,B,C", "重复关闭 wrapper 不重复任一回调")
            equal(queue:hasPending(), false, "pop 后没有残余 batch")
        end)
        run("真实合批close隔离首回调错误，其余完成通知恰一次", function()
            fixture()
            forcedBlock = true
            local closed = {}
            battle("错误隔离A", gold(10), { cascade = false, onClose = function()
                closed[#closed + 1] = "A"
                error("expected Popup batch callback failure")
            end })
            battle("错误隔离B", gold(20), { cascade = false, onClose = function() closed[#closed + 1] = "B" end })
            battle("错误隔离C", gold(30), { cascade = false, onClose = function() closed[#closed + 1] = "C" end })
            forcedBlock = false
            Reward.update(0)
            advance(.4)
            Reward.close()
            advance(.24)
            equal(#closed, 0, "真实closing完成前不执行任一错误回调")
            advance(.02)
            equal(table.concat(closed, ","), "A,B,C", "真实Popup错误首回调不阻断后续B/C")
            advance(10)
            equal(table.concat(closed, ","), "A,B,C", "错误回调不会导致重入或遗漏")
            equal(Reward.hasPendingBattleRewards(), false, "错误回调后batch生命周期仍完成")
        end)
        run("seed 品质/等级及其它资源元数据区分，不合并点击边界", function()
            fixture()
            local queue = Queue.new(mods["config.ResourceDefs"].DEFS)
            local opts = { row = 1, panel = "center", subtitle = "同批" }
            queue:push("同标题", {
                { type = "seed", quality = 2, level = 5, amount = 2 },
                { type = "seed", quality = 3, level = 5, amount = 3 },
                { type = "seed", quality = 2, level = 6, amount = 4 },
                { type = "gold", amount = 5, destination = "bag" },
                { type = "gold", amount = 6, destination = "lootbox" },
                { type = "shard", heroId = 1, amount = 7 },
                { type = "shard", heroId = 2, amount = 8 },
            }, opts)
            queue:push("同标题", {
                { type = "seed", quality = 2, level = 5, amount = 20 },
                { type = "seed", quality = 3, level = 5, amount = 30 },
                { type = "seed", quality = 2, level = 6, amount = 40 },
                { type = "gold", amount = 50, destination = "bag" },
                { type = "gold", amount = 60, destination = "lootbox" },
                { type = "shard", heroId = 1, amount = 70 },
                { type = "shard", heroId = 2, amount = 80 },
            }, opts)
            equal(#queue.entries, 1, "同 row/panel/subtitle 合批")
            local batch = queue.entries[1]
            equal(batch.title, "同标题", "相同标题合批仍保留标题")
            equal(#batch.rewards, 7, "不同 q/level/destination/heroId 严格分开")
            for i, amount in ipairs({ 22, 33, 44, 55, 66, 77, 88 }) do
                equal(batch.rewards[i].amount, amount, "只同元数据累计 " .. i)
            end
            equal(batch.rewards[1].quality, 2, "seed第一品质保留")
            equal(batch.rewards[2].quality, 3, "seed第二品质保留")
            equal(batch.rewards[3].level, 6, "seed独立等级保留")
            for _, extra in ipairs({ { row = 2 }, { panel = "left" }, { subtitle = "不同批" },
                { onItemClick = function() end }, {} }) do
                local nextOpts = { row = 1, panel = "center", subtitle = "同批" }
                for key, value in pairs(extra) do nextOpts[key] = value end
                queue:push("边界", gold(1), nextOpts)
            end
            equal(#queue.entries, 6, "不同row/panel/subtitle和有click前后均独立batch")
            -- 快照永远是展示边界，不被之后兼容请求合并。
            queue:prepend({ state = { marker = true } })
            equal(#queue.entries, 7, "prepend active快照独立保留")
            equal(queue:pop().state.marker, true, "快照在所有pending之前恢复")
        end)
        run("pending gold 真Popup只一项累计，装备合批超过十件级联", function()
            fixture()
            forcedBlock = true
            local a, b = gold(100), gold(250)
            battle("累计金币", a)
            battle("累计金币", b)
            forcedBlock = false
            Reward.update(0)
            equal(timelines[1].count, 1, "真实Popup累计gold仅一件")
            advance(0.6)
            currentTitle("累计金币")
            check(hasText("×350"), "真实资源角标显示累计350")
            equal(a[1].amount, 100, "Popup不修改第一amount输入")
            equal(b[1].amount, 250, "Popup不修改第二amount输入")
            closeAndDrain()
            forcedBlock = true
            battle("装备合批", rewardItems(8))
            battle("装备合批", rewardItems(8, 200))
            forcedBlock = false
            Reward.update(0)
            equal(timelines[2].count, 16, "真实Popup16装备保留级联")
            advance(0.18)
            check(timelines[2]:t(1) > 0 and timelines[2]:t(2) == nil, "合批第一件独立弹出")
            equal(timelines[2]:t(16), nil, "合批尾件未提前出现")
            currentTitle("装备合批")
            check(hasText("点击跳过"), "十件以上真实级联显示跳过提示")
        end)
        run("无cascade battle opening .35秒后停留3秒再关闭 .25秒", function()
            fixture()
            local closed = 0
            battle("自动关闭普通掉落", gold(1), { cascade = false, onClose = function() closed = closed + 1 end })
            advance(0.34)
            equal(closed, 0, "opening未完成不能关闭")
            advance(0.02)
            local full = render("content")
            advance(2.98)
            equal(render("content"), full, ".35+2.99秒仍完整open，不提前closing")
            equal(closed, 0, "停留3秒前无回调")
            advance(0.02)
            advance(0.1)
            check(render("content") ~= full, "3秒后真实closing缩放淡出")
            equal(closed, 0, "closing .1秒不提前回调")
            advance(0.14)
            equal(closed, 0, "closing .24秒不提前回调")
            advance(0.02)
            equal(closed, 1, "closing .25秒完成才回调一次")
            advance(1)
            equal(closed, 1, "自动关闭回调不重复")
            equal(Reward.hasPendingBattleRewards(), false, "自动关闭清空battle生命周期")
        end)
        run("隐式panel固定战斗中栏，focus轮换不拆pending批次", function()
            fixture()
            forcedBlock = true
            local closed = {}
            for _, panel in ipairs({ "left", "right", "center" }) do
                env.H_focusPanel = panel
                Reward.show("隐式中栏奖励", gold(10), { row = 1, cascade = false,
                    onClose = function() closed[#closed + 1] = panel end })
            end
            forcedBlock = false
            Reward.update(0)
            equal(#timelines, 1, "focus轮换三个请求只一个batch")
            equal(timelines[1].count, 1, "隐式同中栏gold累计为一项")
            equal(Reward.currentPanel(), "center", "battle隐式panel不跟随left/right焦点")
            advance(.4)
            currentTitle("隐式中栏奖励")
            check(hasText("×30"), "焦点轮换奖励数量累计30")
            closeAndDrain()
            equal(table.concat(closed, ","), "left,right,center", "隐式批次回调顺序保留")
            equal(Reward.hasPendingBattleRewards(), false, "焦点轮换不留其它panel后续batch")
        end)
        run("onItemClick pending同gold不累计，原始两项index与数量保留", function()
            fixture()
            forcedBlock = true
            local first, second = { type = "gold", amount = 10 }, { type = "gold", amount = 20 }
            local clicked, closed = {}, 0
            battle("逐项资源领取", { first, second }, { cascade = false,
                onItemClick = function(item, index) clicked[#clicked + 1] = { item.amount, index } end,
                onClose = function() closed = closed + 1 end })
            forcedBlock = false
            Reward.update(0)
            equal(timelines[1].count, 2, "有click请求内部不把同资源压成一项")
            advance(.6)
            currentTitle("逐项资源领取")
            check(hasText("×10") and hasText("×20"), "同gold10/20各自绘制")
            -- 两个单行格中心443/637，layout .7绕540/974缩放。
            equal(Reward.handleInput(540 + (443 - 540) * .7, 974 + (1008 - 974) * .7), true, "点击原第一项")
            equal(Reward.handleInput(540 + (637 - 540) * .7, 974 + (1008 - 974) * .7), true, "点击原第二项")
            equal(#clicked, 2, "两项click恰一次")
            equal(clicked[1][1], 10, "第一项amount10不累计")
            equal(clicked[1][2], 1, "第一项index仍1")
            equal(clicked[2][1], 20, "第二项amount20不累计")
            equal(clicked[2][2], 2, "第二项index仍2")
            equal(first.amount, 10, "原第一amount不变")
            equal(second.amount, 20, "原第二amount不变")
            advance(1000)
            equal(closed, 0, "主动领取不自动close")
            closeAndDrain()
            equal(closed, 1, "主动领取最终正常关闭")
        end)
        run("大批cascade尾件落地后才开始3秒停留", function()
            fixture()
            local closed = 0
            battle("自动关闭级联", rewardItems(16), { onClose = function() closed = closed + 1 end })
            local timeline = timelines[1]
            local readyAfter = timeline.revealStart - clock.elapsedTime + timeline:startAt(16) + timeline.popDur
            advance(readyAfter - 0.01)
            equal(timeline:finished(), false, "最后装备未落地不能启动停留")
            equal(closed, 0, "cascade阶段无回调")
            advance(0.02)
            equal(timeline:finished(), true, "最后装备落地")
            equal(#sounds, 17, "开场加16次装备获得音恰一次")
            local full = render("content")
            check(hasText("Lv.101"), "16装备自动followScroll后尾件等级实际可见")
            equal(hasText("Lv.116"), false, "自动滚到底后首件不是留在屏幕未滚动")
            advance(2.98)
            equal(render("content"), full, "cascade完成后2.99秒仍完整open")
            equal(closed, 0, "不是从opening开始计大批停留")
            advance(0.02)
            advance(0.24)
            equal(closed, 0, "尾件完成+3秒后的closing仍等待 .25秒")
            advance(0.02)
            equal(closed, 1, "大批自动关闭恰一次")
        end)
        run("停留阶段1000秒遮挡保留剩余时间而非重开或立即关闭", function()
            fixture()
            local closed = 0
            battle("停留遮挡", gold(1), { cascade = false, onClose = function() closed = closed + 1 end })
            advance(1.6) -- .35 opening + 1.25秒可见停留，剩余1.75秒。
            local before, soundCount = render("content"), #sounds
            forcedBlock = true
            invisible(); transparentInput()
            advance(1000)
            equal(closed, 0, "1000秒遮挡不消耗停留")
            forcedBlock = false
            Reward.update(0)
            equal(render("content"), before, "停留恢复原展示非opening")
            equal(#sounds, soundCount, "停留恢复无重播")
            advance(1.74)
            equal(render("content"), before, "恢复只剩1.75秒，1.74秒尚未close")
            equal(closed, 0, "恢复不立即关闭")
            advance(0.02)
            advance(0.26)
            equal(closed, 1, "恢复剩余时间结束关闭，不重新等3秒")
        end)
        run("global可见1000秒快照平移battle停留，恢复仅余时长", function()
            fixture()
            local rowClosed, globalClosed = 0, 0
            battle("停留global暂停", gold(1), { cascade = false, onClose = function() rowClosed = rowClosed + 1 end })
            advance(1.35) -- 剩余2秒。
            local before = render("content")
            Reward.show("长期global", gold(2), { panel = "center", cascade = false,
                onClose = function() globalClosed = globalClosed + 1 end })
            advance(1000)
            currentTitle("长期global", "global")
            equal(rowClosed, 0, "global期间battle快照不消耗停留")
            equal(globalClosed, 0, "普通no-row永不自动close")
            closeAndDrain()
            equal(globalClosed, 1, "global只经手动关闭回调")
            equal(render("content"), before, "快照恢复原open画面")
            advance(1.99)
            equal(render("content"), before, "global后剩余2秒，1.99秒保持open")
            equal(rowClosed, 0, "global结束不提前回调")
            advance(0.02)
            advance(0.26)
            equal(rowClosed, 1, "global后仅剩余2秒而非重新3秒")
        end)
        run("手动skip级联仍按opening结束后计3秒", function()
            fixture()
            local closed = 0
            battle("手动跳过自动计时", rewardItems(16), { onClose = function() closed = closed + 1 end })
            advance(0.18)
            equal(Reward.handleInput(0, 0), true, "手动首击只skip")
            check(timelines[1]:finished(), "手动skip使全批落地")
            equal(closed, 0, "skip不是close")
            advance(0.18)
            local full = render("content")
            advance(2.98)
            equal(render("content"), full, "skip后从 .35 opening 算，阈值前完整open")
            advance(0.02)
            advance(0.26)
            equal(closed, 1, "skip后无需第二点击也会自动关闭")
        end)
        run("普通no-row级联和onItemClick battle不自动关闭", function()
            fixture()
            local closed = 0
            Reward.show("普通无row", rewardItems(10), { panel = "center", cascade = true,
                onClose = function() closed = closed + 1 end })
            advance(1000)
            currentTitle("普通无row", "global")
            equal(closed, 0, "普通cascade无row长停留不自动close")
            equal(Reward.currentRowTag(), nil, "普通无row保持原归属")
            closeAndDrain()
            equal(closed, 1, "普通无row仍可手动关闭")
            battle("主动逐件领取", rewardItems(12), { onItemClick = function() end,
                onClose = function() closed = closed + 1 end })
            advance(1000)
            currentTitle("主动逐件领取")
            equal(closed, 1, "有onItemClick battle不自动close")
            closeAndDrain()
            equal(closed, 2, "有onItemClick battle仍可手动关闭")
        end)
        run("滚轮延后停留，行内区域外滚轮不消费不延期", function()
            fixture()
            local closed = 0
            battle("滚轮停留", rewardItems(20), { cascade = false, onClose = function() closed = closed + 1 end })
            advance(3.15)
            equal(Reward.handleScrollRegion(1, 900, 300, 555, 50, 838, 322), true, "区域内滚轮路由消费")
            advance(2.99)
            currentTitle("滚轮停留")
            equal(closed, 0, "滚轮后2.99秒仍停留")
            equal(Reward.handleScrollRegion(1, 500, 300, 555, 50, 838, 322), false, "区域外滚轮不消费")
            advance(0.02)
            advance(0.26)
            equal(closed, 1, "区域外滚轮不延后，区域内滚轮后3秒关闭")
        end)
        run("拖动长按延时且松开不关闭，行内逆变换保留真实拖动", function()
            fixture()
            local closed = 0
            battle("拖动停留", rewardItems(20), { cascade = false, onClose = function() closed = closed + 1 end })
            advance(3.15)
            local rx, ry, rw, rh = 555, 50, 838, 322
            local fit = math.min(rw / (1080 * 1.04), rh / 920)
            local wx = rx + rw * 0.5
            local wy = ry + rh * 0.48 + (1000 - 974) * fit
            equal(Reward.handleDragRegion("begin", wx, wy, rx, ry, rw, rh), true, "区域begin逆变换进入网格")
            equal(Reward.handleDragRegion("move", wx, wy - 50 * fit, rx, ry, rw, rh), true, "区域move真实滚动")
            equal(Reward.consumedDrag(), true, "区域move累计超过12设计像素")
            advance(1000)
            equal(closed, 0, "1000秒长按拖动不自动close")
            equal(Reward.handleDragRegion("end", wx, wy - 50 * fit, rx, ry, rw, rh), true, "区域end松开")
            equal(Reward.handleInputRegion(wx, wy - 50 * fit, rx, ry, rw, rh), true, "松开click被drag guard吞掉")
            equal(Reward.consumedDrag(), false, "本次松开清drag guard")
            advance(2.99)
            currentTitle("拖动停留")
            equal(closed, 0, "松开后2.99秒未关闭")
            advance(0.02)
            advance(0.26)
            equal(closed, 1, "松开后重新停留3秒才自动close")
        end)
        run("仿射spy校验真实838x322战斗行提示及多尺寸开关动画", function()
            local rects = { { 555, 50, 838, 322 }, { 20, 30, 420, 160 }, { 0, 0, 1920, 1080 },
                { 800, 400, 320, 600 }, { 120, 80, 1100, 200 } }
            for _, count in ipairs({ 1, 6, 16 }) do
                for _, rect in ipairs(rects) do
                    fixture()
                    battle("提示布局", rewardItems(count), { cascade = false })
                    for _, dt in ipairs({ 0.03, 0.07, 0.08, 0.1, 0.08 }) do
                        advance(dt)
                        render("row", rect)
                        equal(#panelRecords, 1, "真实面板仅绘制一次")
                        local panel = panelRecords[1]
                        local hint = textRecords[#textRecords]
                        equal(hint.text, "点击空白处关闭", "真实底部提示文本")
                        near(hint.designX, 540, "hint设计x")
                        near(hint.designY, 1252.5, "hint收进面板设计y")
                        check(hint.x >= panel.left and hint.x <= panel.right, "opening提示x在仿射面板内")
                        check(hint.y - hint.halfHeight >= panel.top and hint.y + hint.halfHeight <= panel.bottom,
                            "opening提示整字号在仿射面板内")
                        check(hint.y + hint.halfHeight <= rect[2] + rect[4], "opening提示整字号不被战斗框裁掉")
                    end
                    -- open时锚点精确映射到 rx+rw/2, ry+rh*.48（设计panel中心974）。
                    render("row", rect)
                    local panel, hint = panelRecords[1], textRecords[#textRecords]
                    near((panel.top + panel.bottom) * 0.5, rect[2] + rect[4] * 0.48, "open面板中心974映射")
                    local layout = count <= 5 and 0.7 or 1
                    local fit = math.min(rect[3] / (1080 * 1.04), rect[4] / 920)
                    near(hint.y, rect[2] + rect[4] * 0.48 + (1252.5 - 974) * layout * fit,
                        "open提示真实窗口y包含布局缩放")
                    Reward.close()
                    for _, dt in ipairs({ 0.04, 0.06, 0.08, 0.06 }) do
                        advance(dt)
                        render("row", rect)
                        local closingPanel, closingHint = panelRecords[1], textRecords[#textRecords]
                        check(closingHint.y - closingHint.halfHeight >= closingPanel.top
                            and closingHint.y + closingHint.halfHeight <= closingPanel.bottom,
                            "closing提示整字号始终在仿射面板内")
                        check(closingHint.y + closingHint.halfHeight <= rect[2] + rect[4], "closing提示不被战斗框裁掉")
                    end
                end
            end
        end)
        run("真实TriPage内框、绘制与drag/scroll路由，Horizon外帧缩放滚轮", function()
            fixture()
            local routed, clientReads, pumps = {}, 0, 0
            local rewardProxy = {
                currentRowTag = function() return Reward.currentRowTag() end,
                isOpen = function() return Reward.isOpen() end,
                isLarge = function() return Reward.isLarge() end,
                handleLargeScroll = function() return false end,
                currentPanel = function() return Reward.currentPanel() end,
            }
            for _, name in ipairs({ "drawRegion", "handleDragRegion", "handleScrollRegion", "handleInputRegion" }) do
                rewardProxy[name] = function(...)
                    routed[#routed + 1] = { name = name, args = { ... } }
                    return Reward[name](...)
                end
            end
            local function closedPage()
                return { isOpen = function() return false end, isActive = function() return false end,
                    isVisible = function() return false end, shouldBattleOverlay = function() return false end,
                    init = noop, draw = noop, handleWheel = function() return false end }
            end
            local routeMods = {}
            for _, name in ipairs({ "core.BattleLayout", "ui.battle.scene.BattleView", "ui.battle.combat.BattleCombat",
                "ui.battle.combat.ProjectileSystem", "systems.ThreatManager", "systems.TalentManager",
                "ui.battle.combat.BattleEffects", "systems.StatusEffectManager", "ui.battle.tri.TerminalRaid",
                "systems.BattleStats", "ui.hud.TopBar", "ui.character.panel.CharacterPanel", "ui.dev.CEPanel",
                "ui.character.hero.HeroRosterPanel", "ui.town.TownScene", "ui.blacksmith.BlacksmithPage",
                "ui.church.ChurchPage", "ui.church.talent.TalentPage", "ui.tavern.TavernPage",
                "ui.tavern.TavernPopups", "ui.tavern.TargetRecruitPanel", "ui.tavern.RecruitAnim", "ui.market.MarketPage",
                "ui.dungeon.DungeonBattleScene", "ui.tower.TowerBattleScene", "ui.dungeon.DungeonPage",
                "ui.backpack.BackpackPanel", "ui.loot.LootBox", "ui.loot.LootBoxPage", "ui.story.task.TaskPage",
                "ui.hud.popup.LevelUpPopup", "ui.hud.popup.OfflineRewardPanel", "ui.hud.popup.UpdateNoticePopup",
                "ui.hud.popup.PlayerInfoPanel", "ui.story.gate.StartScreen", "ui.story.gate.DarkTitleScreenGate",
                "ui.battle.stage.SweepDialog", "ui.battle.popup.DamageStatsPanel", "ui.battle.stage.StageSelectDialog",
                "ui.battle.popup.TerminalConfirmDialog", "ui.story.gate.IntroCutscene", "ui.story.gate.LetterIntro",
                "ui.character.detail.CharacterDetail", "ui.character.equip.EquipmentBag", "ui.character.EquipCrossDrag",
                "ui.story.ScenarioDialogue", "systems.TutorialManager", "boot.ArtifactGesture" }) do
                routeMods[name] = closedPage()
            end
            routeMods["ui.character.hero.AwakeningArtwork"] = { bindInput = function() return function() return false end end,
                observe = noop, hasPress = function() return false end, isOpen = function() return false end }
            routeMods["core.BattleLayout"] = { STRIP_W = 1600, STRIP_H = 600, setMode = noop }
            routeMods["ui.widget.SoundToggle"] = { initImages = noop }
            routeMods["core.I18n"] = { lookup = function(text) return text end, format = string.format }
            routeMods["config.ExpTable"] = { TEAM_COUNT = 3, getUnlockedTeamCount = function() return 0 end,
                getTeamUnlockText = function() return "锁定" end }
            routeMods["config.StageConfig"] = { isTerminalTemple = function() return false end }
            routeMods["runtime.ClientDispatcher"] = { get = function(key)
                equal(key, "battle", "routing只读注入battle空状态")
                clientReads = clientReads + 1
                return {}
            end }
            routeMods["ui.battle.scene.BattleScene"] = { getStageId = function() return 1 end,
                getClearedStages = function() return routeMods["runtime.ClientDispatcher"].get("battle").clearedStages or {} end,
                pumpBattleCards = function() pumps = pumps + 1; error("routing禁止全图鉴pump") end }
            -- 新增入场/挂载helper只用于零解锁空驱动的路由夹具；不替代本专项被测输入/绘制。
            routeMods["ui.battle.combat.BattleCombatAnim"] = {}
            routeMods["systems.RelicConditionHandler"] = closedPage()
            routeMods["ui.battle.stage.BattleSpeed"] = {}
            routeMods["ui.battle.tri.TerminalReincarnation"] = {
                discardDriver = function() error("零解锁routing不应持有/清理driver") end,
            }
            routeMods["systems.TutorialManager"].getCurrentHighlight = function() return nil end
            routeMods["ui.battle.scene.BattleMountScope"] = {
                wrap = function() end,
                run = function(callback, ...) return callback(...) end,
            }
            routeMods["ui.battle.tri.BattleEntryPreparation"] = { new = function()
                return { invalidate = noop,
                    prepare = function() error("routing禁止入场准备") end,
                    isPrepared = function() error("routing禁止入场凭据") end }
            end }
            routeMods["ui.character.equip.EquipmentBag"].setOverlayRegion = noop
            routeMods["ui.dev.CEPanel"].handleWheel = function() return false end
            routeMods["ui.dev.CEPanel"].handleDown = function() return false end
            routeMods["ui.dev.CEPanel"].handleUp = function() return false end
            routeMods["ui.loot.LootBox"].handleDragEnd = noop
            routeMods["ui.character.EquipCrossDrag"].isArmed = function() return false end
            routeMods["ui.character.panel.CharacterPanel"].isDraggingCard = function() return false end
            routeMods["ui.character.panel.CharacterPanel"].handleDragEnd = noop
            routeMods["ui.character.equip.EquipmentDetail"] = { isPinned = function() return false end,
                isCompactCorner = function() return false end }
            local artifact = { down = function() return false end, move = function() return false end,
                up = function() return false end, hover = noop, cancel = noop }
            routeMods["ui.hud.BottomNav"] = { getSelectedIndex = function() return 3 end }
            routeMods["ui.hud.popup.RewardPopup"] = rewardProxy
            local stageOpen = false
            routeMods["ui.battle.stage.StageSelectDialog"].isOpen = function() return stageOpen end
            local stageScrolls = {}
            routeMods["ui.battle.stage.StageSelectDialog"].handleScroll = function(wheel, x, y)
                stageScrolls[#stageScrolls + 1] = { wheel, x, y }
                return true
            end
            ---@type any
            local routeEnv = setmetatable({}, { __index = env })
            routeEnv.require = function(name)
                if not routeMods[name] then
                    forbiddenRequires = forbiddenRequires + 1
                    error("routing sandbox 禁止依赖 " .. tostring(name))
                end
                return routeMods[name]
            end
            routeEnv.nvgScissor = noop
            -- 返回条也编译真实 helper，页面状态沿用上面的显式 spy 白名单；不 mock 手势。
            local seamChunk = assert(load(seamGestureSource, "@boot.SeamBackGesture", "t", routeEnv))
            routeMods["boot.SeamBackGesture"] = seamChunk()
            routeMods["boot.DecomposeMarqueeGesture"] = assert(load(marqueeGestureSource,
                "@boot.DecomposeMarqueeGesture", "t", routeEnv))()
            routeMods["boot.RewardGesture"] = assert(load(rewardGestureSource, "@boot.RewardGesture", "t", routeEnv))()
            routeMods["boot.StandaloneHorizonWheel"] = assert(load(horizonWheelSource,
                "@boot.StandaloneHorizonWheel", "t", routeEnv))()
            local triChunk = assert(load(triSource, "@ui.battle.tri.BattleTriPage", "t", routeEnv))
            local Tri = triChunk()
            routeMods["ui.battle.tri.BattleTriPage"] = Tri
            -- open只走空Battle/零解锁spy，不生成驱动、不调用真实存档/结算。
            Tri.open()
            equal(pumps, 0, "真实open不再调用全图鉴pump，零解锁不生成驱动")
            local sizes = { { 1920, 1080 }, { 1440, 810 }, { 2560, 1440 } }
            local interiors = { { .2835, .0117, .7201, .3103 }, { .2835, .3475, .7207, .6482 },
                { .2877, .6812, .7099, .9883 } }
            for _, size in ipairs(sizes) do
                for row = 1, 3 do
                    local x, y, w, h = Tri.getInteriorRectFor(row, size[1], size[2])
                    local ir, pw = interiors[row], size[2] * 1672 / 941
                    near(x, (size[1] - pw) * .5 + ir[1] * pw, "真实内框x " .. row)
                    near(y, ir[2] * size[2], "真实内框y " .. row)
                    near(w, (ir[3] - ir[1]) * pw, "真实内框w " .. row)
                    near(h, (ir[4] - ir[2]) * size[2], "真实内框h " .. row)
                end
            end
            local rx, ry, rw, rh = Tri.getInteriorRectFor(1, 1920, 1080)
            check(rw > 837 and rw < 839 and rh > 322 and rh < 323, "真实第一战斗框约838x322")
            battle("真实Tri提示路由", rewardItems(20), { cascade = false })
            advance(.5)
            texts, ops, textRecords, panelRecords, drawCalls = {}, {}, {}, {}, 0
            Tri.draw({}, 1920, 1080)
            equal(routed[#routed].name, "drawRegion", "真实Tri draw接入奖励region")
            near(routed[#routed].args[2], rx, "Tri绘制传真实内框x")
            near(routed[#routed].args[3], ry, "Tri绘制传真实内框y")
            equal(stackDepth, 0, "真实Tri draw恢复状态")
            local hint = textRecords[#textRecords]
            equal(hint.text, "点击空白处关闭", "真实Tri draw底部提示")
            check(hint.y + hint.halfHeight < ry + rh, "真实Tri框底不裁掉提示")
            local fit = math.min(rw / (1080 * 1.04), rh / 920)
            local wx, wy = rx + rw * .5, ry + rh * .48 + (1000 - 974) * fit
            equal(Tri.handleDragBegin(wx, wy), true, "真实Tri begin返回奖励消费")
            equal(Tri.handleDragMove(wx, wy - 40 * fit), true, "真实Tri move返回奖励消费")
            equal(Reward.consumedDrag(), true, "真实Tri逆映射超过drag阈值")
            equal(Tri.handleDragEnd(wx, wy - 40 * fit), true, "真实Tri end返回奖励消费")
            equal(Tri.handleInput(wx, wy - 40 * fit), true, "真实Tri up不关闭拖动奖励")
            equal(Reward.consumedDrag(), false, "真实Tri up清拖动guard")
            for i, phase in ipairs({ "begin", "move", "end" }) do
                local record = routed[#routed - 4 + i]
                equal(record.name, "handleDragRegion", "真实Tri drag接线 " .. phase)
                equal(record.args[1], phase, "真实Tri phase " .. phase)
                near(record.args[4], rx, "真实Tri drag rect x")
                near(record.args[7], rh, "真实Tri drag rect h")
            end
            equal(Tri.handleScroll(1, wx, wy), true, "真实Tri scroll接入区域")
            equal(routed[#routed].name, "handleScrollRegion", "真实Tri scroll接线")
            equal(Tri.handleScroll(1, rx - 1, wy), false, "真实Tri区域外滚轮透给其它面板")
            check(clientReads > 0, "真实Tri启动/绘制只查询spy状态")

            local pointer = { x = 0, y = 0 }
            routeEnv.input = { GetMousePosition = function() return pointer end }
            local horizonChunk = assert(load(horizonInputSource, "@boot.StandaloneHorizonInput", "t", routeEnv))
            local HorizonInput = horizonChunk()
            local frame = { scale = 1.0, ox = 0, oy = 0, dpr = 1 }
            local seamEnabled, seamCloses = false, 0
            HorizonInput.bind({ vg = function() return {} end, logicalW = function() return 1920 end,
                logicalH = function() return 1080 end, dpr = function() return frame.dpr end,
                windowW = function() return 1920 end, windowH = function() return 1080 end,
                DESIGN_W = function() return 1080 end, DESIGN_H = function() return 2400 end,
                bootReady_ = function() return true end, artifactGesture = artifact,
                toDesign = function(x, y) return (x - frame.ox) / frame.scale, (y - frame.oy) / frame.scale end,
                talentPageUsesWideLayout = function() return false end, syncTalentPageLayout = noop,
                equipOverlayDesign = function() return nil end,
                seamHitAt = function()
                    if seamEnabled then return { dir = "left", close = function() seamCloses = seamCloses + 1 end } end
                    return nil
                end,
                RT = {}, Viewport = { DS = .45, PANELS = {} },
                OfflineRewardOverlay = { handleWheel = function() return false end, hasPress = function() return false end } })
            for _, sample in ipairs({ { .5, 70, 30, 2 }, { 1.5, 100, 200, 3 }, { .8, -40, 90, 1 } }) do
                frame.scale, frame.ox, frame.oy, frame.dpr = sample[1], sample[2], sample[3], sample[4]
                pointer.x = (wx * frame.scale + frame.ox) * frame.dpr
                pointer.y = (wy * frame.scale + frame.oy) * frame.dpr
                local previous = #routed
                routeEnv.HandleMouseWheelHorizon("MouseWheel", { Wheel = { GetInt = function() return 1 end } })
                equal(#routed, previous + 1, "Horizon普通路径仅路由一次滚轮")
                local record = routed[#routed]
                equal(record.name, "handleScrollRegion", "Horizon真实滚轮到Tri再到Reward")
                near(record.args[2], wx, "Horizon滚轮消除DPR和外帧scale/ox")
                near(record.args[3], wy, "Horizon滚轮消除外帧oy")
                stageOpen = true
                routeEnv.HandleMouseWheelHorizon("MouseWheel", { Wheel = { GetInt = function() return -1 end } })
                local scroll = stageScrolls[#stageScrolls]
                local dialogFit = math.min(1920 / 1080, 1080 / 2400) * 2
                equal(scroll[1], -1, "Horizon选关优先路径滚轮值")
                near(scroll[2], (wx - 960) / dialogFit + 540, "选关优先路径也消除外帧scale/ox")
                near(scroll[3], (wy - 540) / dialogFit + 1195, "选关优先路径也消除外帧oy")
                stageOpen = false
            end
            -- 实际Horizon down/up：从battle网格按下跨到左栏或seam松开，
            -- 必须结束原Reward dragging，且不能伪装成目标栏click。
            frame.scale, frame.ox, frame.oy, frame.dpr = .75, 80, 30, 2
            local function movePointer(x, y)
                pointer.x = (x * frame.scale + frame.ox) * frame.dpr
                pointer.y = (y * frame.scale + frame.oy) * frame.dpr
            end
            for _, seam in ipairs({ false, true }) do
                fixture()
                local closed, sideClicks = 0, 0
                routeMods["ui.hud.TopBar"].hitTestAvatar = function() sideClicks = sideClicks + 1; return false end
                routeMods["ui.hud.TopBar"].handleInput = function() sideClicks = sideClicks + 1; return false end
                battle("跨栏拖动释放", rewardItems(20), { cascade = false, onClose = function() closed = closed + 1 end })
                advance(.5)
                movePointer(wx, wy)
                routeEnv.HandleMouseButtonDownHorizon("MouseButtonDown", { Button = { GetInt = function() return MOUSEB_LEFT end } })
                equal(routed[#routed].args[1], "begin", "Horizon down进入真实Reward drag")
                movePointer(wx, wy - 40 * fit)
                routeEnv.HandleMouseMoveHorizon("MouseMove", {})
                equal(Reward.consumedDrag(), true, "Horizon move真拖动超过阈值")
                advance(10)
                equal(closed, 0, "拖动持有不自动关闭")
                movePointer(200, 200)
                seamEnabled = seam
                routeEnv.HandleMouseButtonUpHorizon("MouseButtonUp", { Button = { GetInt = function() return MOUSEB_LEFT end } })
                seamEnabled = false
                local record = routed[#routed]
                equal(record.name, "handleDragRegion", "跨栏/seam up路由回起点dragEnd")
                equal(record.args[1], "end", "跨栏/seam释放结束Reward dragging")
                near(record.args[2], -1, "跨栏/seam释放用无命中窗口x")
                near(record.args[3], -1, "跨栏/seam释放用无命中窗口y")
                equal(sideClicks, 0, "跨栏拖动up不派发侧栏点击")
                equal(closed, 0, "跨栏/seam松开不立即close奖励")
                advance(2.99)
                currentTitle("跨栏拖动释放")
                equal(closed, 0, "跨栏/seam松开后2.99秒仍停留")
                advance(.02)
                advance(.26)
                equal(closed, 1, "跨栏/seam结束drag后3秒自动关闭，不悬挂")
            end
            equal(seamCloses, 0, "tri网格拖到seam松手不伪装成返回按钮点击")
        end)
        run("隔离边界：核心与公共奖励路由仅加载spy依赖", function()
            equal(sourceReads, 4, "只读 Popup/Queue/Cascade/Blocker 四份实际核心源码")
            equal(routingSourceReads, 8, "只读战斗路由与奖励公共视图/手势源码")
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
