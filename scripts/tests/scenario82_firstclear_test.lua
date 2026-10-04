-- ============================================================================
-- scenario82_firstclear_test.lua — 首通情景接线修复回归（2026-10-01）
-- 背景：0922 删除 Client/Server 联网壳（4e184304）时，首通触发情景的接线
--   （原 ClientBoot.setOnFirstClear 里 lastClearedStageId_ + NEXT_STAGE）没搬进单机版，
--   导致所有"首通触发"情景（含情景82 大狗嚼碎片引导）在单机永不入队/播放。
--   且 13df6a95 起客户端播放前预写 claimedScenarios，单机 PDM 与客户端共享同一
--   张表 → 播完领奖被"已领取"拦截。
-- 修复：
--   1) StandaloneBoot.setOnFirstClear 直接调 StoryPlayer.onStage(id,"clear") 补接线
--   2) StoryPlayer.backfillCleared() 旧档补播（已首通未领的情景重新入队）
--   3) ClaimScenarioReward 增 preClaimed 参数 + scenarioRewardsGranted 独立防刷账本
-- 验证：
--   1) backfillCleared 把已首通 205 的情景 82 补入队，take 能取到
--   2) preClaimed=true 领奖：在 claimed 已预标记下仍成功发 10 碎片
--   3) 无 preClaimed 且已 claimed → 拒绝（证明预标记必须配 preClaimed）
--   4) 重复领取被 scenarioRewardsGranted 账本拒绝（preClaimed 也无法刷第二次）
--   5) 关卡未通关时领取失败不记账 → 补通关后可重试成功
--   6) 真实 Standalone 起播闭包 + StoryPlayer/ScenarioDialogue + JSON 存档中断重启
--   7) 旧 claimed/granted 双键、失败重试、skip/重复回调防双发与非82预标记
-- 跑法: /workspace/.cli/UrhoXRuntime tests/scenario82_firstclear_test.lua \
--         -tapcode_dir=. -tool_mode -graphicsheadless -nosound
-- 成败只看 RESULT ALL PASS/FAIL，不把 Runtime 退出0当作通过；不 build、不碰玩家文件。
-- ============================================================================

local PREFIX = "[scenario82] "
local failures = {}
local checks = 0
local function check(cond, msg)
    checks = checks + 1
    if cond then print(PREFIX .. "[PASS] " .. msg)
    else
        failures[#failures + 1] = msg
        print(PREFIX .. "[FAIL] " .. msg)
        error(msg, 2) -- 立即终止；外层统一打印 FAIL 并 Exit，不能悄悄继续或悬挂。
    end
end
local function eq(actual, expected, msg)
    check(actual == expected, msg .. " (实际=" .. tostring(actual) .. " 期望=" .. tostring(expected) .. ")")
end

-- ======================== 加载真实模块 + 覆盖数据源 ========================
-- 沿用 corrupt_convert_test 模式：require 真实服务，覆盖 PDM/ClientDispatcher 的
-- 数据方法指向测试 modules 表（引擎 require 返回单例，覆盖对所有引用者生效）。

---@type any
local PDM = {}
---@type any
local ClientDispatcher = {}
---@type any
local StoryPlayer = {}
---@type any
local BS = {}
local restores = {}
local function replace(owner, key, value)
    local previous = owner[key]
    restores[#restores + 1] = function() owner[key] = previous end
    owner[key] = value
end

---@type table<string, table>
local modules = {}
local function setupLegacy()
    PDM = require("rules.character.PlayerDataManager")
    ClientDispatcher = require("runtime.ClientDispatcher")
    StoryPlayer = require("systems.StoryPlayer")
    BS = require("rules.battle.BattleService")
    replace(PDM, "GetModule", function(_, name) return modules[name] end)
    replace(PDM, "MarkDirty", function() end)
    replace(PDM, "FlushImmediate", function() end)
    replace(ClientDispatcher, "get", function(name) return modules[name] end)
end

local UID = 1

--- 重置数据源。clearedStages/claimed/granted/shards 由各用例指定
---@param opts table { cleared205?:boolean, claimed82?:boolean, shards?:integer }
local function resetModules(opts)
    opts = opts or {}
    modules.session = {
        introCompleted = true,
        initialHeroId = 1,
        claimedScenarios = opts.claimed82 and { ["82"] = true } or {},
        scenarioRewardsGranted = {},
    }
    modules.battle = {
        clearedStages = (opts.cleared205 ~= false) and { ["205"] = true } or {},
        maxStageId = 205,
        currentStageId = 205,
    }
    modules.heroes = { roster = { [1] = { level = 1, shards = opts.shards or 0 } } }
    modules.currency = {}
end

local function shardsOf(heroId)
    local h = modules.heroes.roster[heroId]
    return h and h.shards or 0
end
local function grantedOf(id)
    return modules.session.scenarioRewardsGranted[tostring(id)] == true
end

-- ======================== 用户最小复现：真实生产链 + 内存重启 ========================
-- 只读正式源码；不 require 整个 Standalone（避免启动页面/联网/读玩家档），不改源码字符串。
-- 独立 env 中装真实 Dispatcher/GameState/StoryPlayer/Dialogue/Save；只有绘制叶子与文件 IO 是替身。
local function productionCases()
    local nativeRequire, nativeCache = require, cache
    local allowedSources = {
        ["boot.Standalone"] = true, ["boot.StandaloneSave"] = true,
        ["systems.StoryPlayer"] = true, ["ui.story.ScenarioDialogue"] = true,
        ["runtime.ClientDispatcher"] = true, ["core.GameState"] = true,
        ["core.EventBus"] = true, ["ui.story.StoryDisplay"] = true,
    }
    local sources = {}
    for name in pairs(allowedSources) do
        local path = name:gsub("%.", "/") .. ".lua"
        local file = assert(nativeCache:GetFile(path), "缺少真正项目源码 " .. path)
        assert(file:IsOpen(), "源码无法打开 " .. path)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        sources[name] = table.concat(lines, "\n")
    end
    local function extractPlayback(standalone)
        local first = assert(standalone:find("local function tryPlayPendingStory_()", 1, true), "缺少正式起播闭包")
        local boundary = assert(standalone:find("\n%-%-", first), "找不到起播闭包之后的注释边界")
        -- 从 local function 一直取到下一个顶格注释；完整 onFinish 闭包也在其中。
        return standalone:sub(first, boundary - 1) .. "\nreturn tryPlayPendingStory_"
    end
    local playbackSource = extractPlayback(sources["boot.Standalone"])
    check(playbackSource:find("localSendAction", 1, true) ~= nil, "提取完整正式起播/onFinish闭包而非复制逻辑")
    local config = nativeRequire("config.ScenarioDialogueConfig")
    local Protocol = nativeRequire("shared.Protocol")
    local handler = nativeRequire("rules.battle.BattleHandler").actionHandlers[Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD]
    check(type(handler) == "function", "真实 BattleHandler → ClaimScenarioReward 领奖路由")
    eq(#config.SCENARIO_82.steps, 3, "正式82配置有三句")
    eq(config.SCENARIO_82.mode, "small", "正式82走小情景dismiss动画")

    ---@type table<string, string>
    local disk = {}
    local ioCounts = { writes = 0, reads = 0, renames = 0, images = 0 }
    local function savePath(path)
        assert(path == "standalone_save.json" or path == "standalone_save.pending.json",
            "内存File禁止访问其它路径 " .. tostring(path))
    end
    -- 整个 File/fileSystem 只存在隔离 env，未修改全局，也绝不转发玩家文件调用。
    local memoryFS = {
        FileExists = function(_, path) savePath(path); return disk[path] ~= nil end,
        Delete = function(_, path) savePath(path); disk[path] = nil; return true end,
        Rename = function(_, from, to)
            savePath(from); savePath(to)
            assert(from == "standalone_save.pending.json" and to == "standalone_save.json", "必须临时档原子替换")
            assert(type(disk[from]) == "string", "必须先完整写临时JSON")
            disk[to], disk[from] = disk[from], nil
            ioCounts.renames = ioCounts.renames + 1
            return true
        end,
    }
    local function memoryFile(path, mode)
        savePath(path)
        assert(mode == FILE_READ or mode == FILE_WRITE, "只允许实际Save使用的读写模式")
        local opened = mode == FILE_WRITE or disk[path] ~= nil
        return {
            IsOpen = function() return opened end,
            Close = function() opened = false end,
            ReadString = function()
                assert(opened and mode == FILE_READ, "读未打开的内存文件")
                ioCounts.reads = ioCounts.reads + 1
                return disk[path]
            end,
            WriteString = function(_, json)
                assert(opened and mode == FILE_WRITE and path == "standalone_save.pending.json", "必须写临时文件")
                assert(type(json) == "string" and type(cjson.decode(json).modules) == "table", "真实cjsonJSON而非引用快照")
                disk[path] = json
                ioCounts.writes = ioCounts.writes + 1
                return true
            end,
        }
    end
    local function same(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do if not same(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    local function noop() end
    local function closed() return false end
    local instances = 0
    local current = {} ---@type any
    local function newProcess()
        instances = instances + 1
        local ctx = { actions = {}, notices = {}, finished = {}, dirty = {}, shown = {},
            pending = {}, allowStory = true, rewardOpen = false } ---@type any
        local deps = {} ---@type table<string, any>
        local env = setmetatable({}, { __index = _G }) ---@type any
        env.File, env.fileSystem, env.cjson = memoryFile, memoryFS, cjson
        env.nvgCreateImage = function() ioCounts.images = ioCounts.images + 1; return -1 end
        env.cache = { GetResource = function() error("专项不允许加载GPU/音频资源") end }
        env.require = function(name)
            if deps[name] ~= nil then return deps[name] end
            if name:match("^config%.") or name:match("^shared%.") then return nativeRequire(name) end
            error("隔离env禁止意外加载 " .. tostring(name))
        end
        local function compile(name, text)
            local chunk, why = load(text or sources[name], "@真实" .. name .. "#" .. instances, "t", env)
            assert(chunk, why)
            return chunk()
        end
        deps["core.EventBus"] = compile("core.EventBus")
        deps["core.EventBus"].on("scenario_dialogue_finished", function(data)
            ctx.finished[#ctx.finished + 1] = data.reason
        end)
        deps["runtime.ClientDispatcher"] = compile("runtime.ClientDispatcher")
        ctx.dispatcher = deps["runtime.ClientDispatcher"]
        deps["core.GameState"] = compile("core.GameState")
        ctx.state = deps["core.GameState"]
        -- GameState 的单机同步出口仅写新 Dispatcher；不启动整个 LocalActionBridge/页面。
        ctx.state.setLocalPlayerSync(function(player) ctx.dispatcher.set("player", player) end)
        deps["core.DrawUtil"], deps["ui.widget.HeroFrame"] = {}, {}
        deps["core.I18n"] = nativeRequire("core.I18n")
        deps["core.I18nStory"] = nativeRequire("core.I18nStory")
        deps["ui.story.StoryDisplay"] = compile("ui.story.StoryDisplay")
        deps["ui.story.ScenarioDialogue"] = compile("ui.story.ScenarioDialogue")
        ctx.dialogue = deps["ui.story.ScenarioDialogue"]
        ctx.dialogue.init(nil, nil) -- update/advance真实，场景为空禁止blip；从不draw。
        local realShow = ctx.dialogue.show
        ctx.dialogue.show = function(cfg)
            ctx.shown[#ctx.shown + 1] = cfg
            realShow(cfg) -- spy只记录完整正式config与真实onFinish，不代播/不提前领奖。
        end
        deps["systems.StoryPlayer"] = compile("systems.StoryPlayer")
        ctx.story = deps["systems.StoryPlayer"]
        deps["ui.battle.scene.BattleScene"] = { setBattleData = noop }
        deps["rules.offline.OfflineService"] = {
            HasPendingRewards = function() error("未OfflineChecked不能进入离线奖励分支") end,
            MarkOnline = function() error("专项禁止推进在线/离线时间") end,
        }
        deps["boot.StandaloneSave"] = compile("boot.StandaloneSave")
        ctx.save = deps["boot.StandaloneSave"]
        env.ClientDispatcher, env.ScenarioDialogue = ctx.dispatcher, ctx.dialogue
        env.TutorialManager = { canPlayPendingStory = function() return ctx.allowStory end }
        env.LetterIntro, env.IntroCutscene = { isOpen = closed }, { isActive = closed }
        env.RewardPopup = { isOpen = function() return ctx.rewardOpen end, hasPendingBattleRewards = closed }
        env.OfflineRewardPanel = { isOpen = closed }
        env.ClientMsgHandler = {
            consumePendingScenarioDialogue = function() return table.remove(ctx.pending, 1) end,
            consumePendingFollowUpDialogue = function() return table.remove(ctx.follow or {}, 1) end,
            setPendingTutorialNotify = function(sid) ctx.notices[#ctx.notices + 1] = sid end,
        }
        -- 直接桥的叶子出口计数；完整参数透传真实Handler，真实Service执行资格/去重/发奖。
        env.localSendAction = function(action, params)
            eq(action, Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, "正式onFinish发claim动作")
            eq(params.preClaimed, true, "正式onFinish仍透传preClaimed=true")
            local record = { action = action, params = params }
            ctx.actions[#ctx.actions + 1] = record
            record.result = handler(UID, params)
            return record.result.success
        end
        ctx.play = compile("boot.Standalone.tryPlayPendingStory_", playbackSource)
        current = ctx
        return ctx
    end
    replace(PDM, "GetModule", function(_, name)
        if name == "heroes" and current.unavailableHeroes then return nil end
        return current.dispatcher.get(name)
    end)
    replace(PDM, "MarkDirty", function(_, name)
        current.dirty[#current.dirty + 1] = name
        -- 直接桥仍转发真实GameState反向同步，否则首通经验与JSON读档的等级真实源不一致。
        if name == "player" then current.state.syncPlayerData(current.dispatcher.get(name), { silent = true }) end
        if name == "currency" then current.state.syncFromCurrency(current.dispatcher.get(name), { silent = true }) end
    end)

    local function seed(opts)
        opts = opts or {}
        disk = {}
        local ctx = newProcess()
        local session = { introCompleted = true, initialHeroId = 1, lastOnlineTime = 1234,
            claimedScenarios = opts.claimed or { ["51"] = true }, sentinel = { value = "完整session" } }
        if not opts.noGranted then session.scenarioRewardsGranted = opts.granted or {} end
        ctx.dispatcher.set("session", session)
        ctx.dispatcher.set("battle", { currentStageId = 205, maxStageId = 205,
            clearedStages = opts.cleared == false and {} or { ["205"] = true },
            teamStageIds = { ["1"] = 205, ["2"] = 201, ["3"] = 101 }, idleAccumSec = 17 })
        ctx.dispatcher.set("heroes", { roster = {
            [1] = { level = 3, exp = 4, shards = opts.shards or 0, dupeCount = 0, _shardMigrated = true },
            [25] = { level = 7, exp = 8, shards = 2, dupeCount = 0, _shardMigrated = true },
        }, deployed = { 1, 0, 0, 0 }, teams = { { slots = { 1, 0, 0, 0 } },
            { slots = { 25, 0, 0, 0 } }, { slots = { 0, 0, 0, 0 } } } })
        ctx.dispatcher.set("currency", { gold = 7, gems = 2 })
        ctx.state.importSave({ name = "专项内存玩家", level = 1, exp = 0, gold = 7, gems = 2 })
        ctx.state.syncPlayerData(ctx.state.exportSave(), { silent = true }) -- 与正式初始化一致地归一maxExp/player镜像。
        return ctx
    end
    local function session(ctx) return ctx.dispatcher.get("session") end
    local function shards(ctx) return ctx.dispatcher.get("heroes").roster[1].shards end
    local function marked(data, name)
        local map = data[name]
        return type(map) == "table" and (map["82"] == true or map[82] == true)
    end
    local function unawarded(ctx, label, expectedClaimed)
        eq(#ctx.actions, 0, label .. " 起播/中断前无claim/action")
        eq(#ctx.notices, 0, label .. " 未发领奖引导通知")
        eq(#ctx.dirty, 0, label .. " 未走真实服务MarkDirty")
        eq(shards(ctx), 0, label .. " 碎片仍为0")
        eq(marked(session(ctx), "claimedScenarios"), expectedClaimed == true, label .. " claimed未被起播提前写入")
        check(type(session(ctx).scenarioRewardsGranted) == "table", label .. " 起播建立/保留独立granted账本")
        check(not marked(session(ctx), "scenarioRewardsGranted"), label .. " 起播未记granted")
    end
    local function progress(ctx, index, label)
        local step, total = ctx.dialogue.getProgress()
        eq(step, index, label .. " 当前句")
        eq(total, 3, label .. " 三句总数")
        check(ctx.dialogue.isActive(), label .. " 对话仍活跃")
        eq(ctx.shown[#ctx.shown].steps, config.SCENARIO_82.steps, label .. " 使用正式三句steps原表")
    end
    local function backfill(ctx, label)
        check(ctx.story.backfillCleared() >= 1, label .. " 新实例backfill从已通205补播")
        eq(ctx.story.backfillCleared(), 0, label .. " backfill队列去重")
        ctx.play()
        progress(ctx, 1, label)
    end
    local function restart(ctx, label)
        local before = {}
        for _, name in ipairs({ "session", "battle", "heroes" }) do before[name] = ctx.dispatcher.get(name) end
        local stateBefore = ctx.state.exportSave()
        check(ctx.save.Flush(), label .. " 真实StandaloneSave.Flush成功")
        local json = assert(disk["standalone_save.json"], "应有内存JSON存档")
        local decoded = cjson.decode(json)
        eq(decoded.version, 1, label .. " 保存真实版本头")
        check(decoded.modules.heroes.roster.h1 ~= nil and decoded.modules.heroes.roster.h25 ~= nil,
            label .. " 真实Save用h英雄键保存完整roster")
        eq(decoded.modules.heroes.roster.h1.shards, shards(ctx), label .. " 碎片与账本同次JSON快照")
        ctx.dialogue.reset() -- 硬中断不调用skip/onFinish，真正丢弃旧实例和队列。
        eq(#ctx.finished, 0, label .. " 中断reset不广播对话完成")
        local fresh = newProcess()
        check(fresh.story ~= ctx.story and fresh.dialogue ~= ctx.dialogue and fresh.save ~= ctx.save
            and fresh.dispatcher ~= ctx.dispatcher, label .. " Story/Dialogue/Save/Dispatcher均真新实例")
        eq(fresh.story.take(), nil, label .. " 新queue为空不是复用旧queue")
        eq(fresh.dispatcher.get("session"), nil, label .. " 新进程没有旧module引用")
        check(fresh.save.RestoreData(), label .. " 真实RestoreData读取并解码JSON")
        for _, name in ipairs({ "session", "battle", "heroes" }) do
            local restored = fresh.dispatcher.get(name)
            check(restored ~= before[name] and same(restored, before[name]), label .. " 完整" .. name .. "快照深拷贝往返")
        end
        check(same(fresh.state.exportSave(), stateBefore), label .. " 真实GameState快照往返")
        eq(#fresh.actions, 0, label .. " 读档本身无领奖动作")
        return fresh
    end
    local function finishNormally(ctx, label)
        for index = 1, 3 do
            progress(ctx, index, label .. " 点完第" .. index .. "句前")
            ctx.dialogue.update(100) -- 真实打字机完成全文，非修改内部状态。
            ctx.dialogue.advance()
            eq(#ctx.actions, 0, label .. " 第" .. index .. "句点完尚未dismiss不领奖")
        end
        ctx.dialogue.update(0.29)
        eq(#ctx.actions, 0, label .. " dismiss不足0.3秒不领奖")
        ctx.dialogue.advance() -- 消失动画中连点不重复推进或领奖。
        ctx.dialogue.update(0.02)
        eq(#ctx.actions, 1, label .. " dismiss完成恰好一次正式claim")
        eq(#ctx.notices, 1, label .. " 一次正式领奖通知")
        eq(ctx.notices[1], 82, label .. " 通知情景82")
        eq(ctx.finished[1], "dismissed", label .. " 真实完成事件")
        check(not ctx.dialogue.isActive(), label .. " 对话正常结束")
    end
    local function rewarded(ctx, label)
        local result = ctx.actions[1].result
        check(result.success, label .. " 真实服务领取成功")
        eq(result.rewardType, "shard", label .. " 返回shard")
        eq(result.reward.heroId, 1, label .. " 大狗嚼英雄1")
        eq(result.reward.amount, 10, label .. " 正式回包10")
        eq(shards(ctx), 10, label .. " 总计只发10碎片")
        check(marked(session(ctx), "claimedScenarios") and marked(session(ctx), "scenarioRewardsGranted"),
            label .. " 真正发奖后才同时claimed/granted")
        ctx.dialogue.skip(); ctx.dialogue.advance(); ctx.dialogue.update(1)
        eq(#ctx.actions, 1, label .. " 结束后重复skip/update/advance不重复调用onFinish")
        -- 即使外部重入保存的正式onFinish，真实Handler/Service账本仍拒绝第二次。
        ctx.shown[1].onFinish()
        eq(#ctx.actions, 2, label .. " 重入正式onFinish由真实服务处理")
        check(not ctx.actions[2].result.success, label .. " 幂等账本拒绝重入")
        eq(ctx.actions[2].result.reason, "奖励已领取", label .. " 服务判重复")
        eq(shards(ctx), 10, label .. " 重入没有双发")
    end

    -- 用例6：真实首通资格（服务写clear + 正式onStage事件入口）→起播→每个中断点→JSON→新queue补播。
    -- 不冒称测试整个Boot/随机战斗；首通回调的onStage接线由既有tri_clear_unlock测试覆盖。
    for _, point in ipairs({ 1, 2, 3, "dismiss_before", "dismiss_during" }) do
        local label = "用例6 中断=" .. tostring(point)
        local ctx = seed({ cleared = false, noGranted = true })
        local ok, err = BS.NextStage(UID, 205, nil)
        check(ok, label .. " 真实NextStage首次通205: " .. tostring(err))
        check(ctx.dispatcher.get("battle").clearedStages["205"], label .. " 首通205资格已写")
        ctx.dirty = {} -- 首通动作不是剧情领奖；只计起播后的service调用。
        ctx.story.onStage(205, "clear")
        ctx.story.onStage(205, "clear") -- 同一首通事件重入不得重复入队。
        ctx.rewardOpen = true; ctx.play()
        check(not ctx.dialogue.isActive(), label .. " 等首通奖励弹窗关闭")
        ctx.rewardOpen = false; ctx.play()
        progress(ctx, 1, label .. " 起播")
        eq(ctx.story.take(), nil, label .. " 去重且51已claimed，82取出后queue为空")
        eq(session(ctx).scenarioRewardsGranted and next(session(ctx).scenarioRewardsGranted), nil,
            label .. " 首次起播建空账本")
        local target = type(point) == "number" and point or 3
        for index = 1, target - 1 do
            ctx.dialogue.advance() -- 第一次点击只补完当前句打字。
            progress(ctx, index, label .. " 补全打字")
            ctx.dialogue.advance()
        end
        progress(ctx, target, label .. " 中断位置")
        if type(point) == "string" then
            ctx.dialogue.update(100); ctx.dialogue.advance()
            if point == "dismiss_during" then ctx.dialogue.update(0.15) end
            progress(ctx, 3, label .. " 最后一句消失中")
        end
        unawarded(ctx, label)
        ctx = restart(ctx, label)
        backfill(ctx, label .. " 重启")
        unawarded(ctx, label .. " 重启起播")
        finishNormally(ctx, label .. " 重播正常点完")
        rewarded(ctx, label)
        -- 完成后的reset无需finished=0；先清历史事件，仅用于下一次硬中断断言。
        ctx.finished = {}
        ctx = restart(ctx, label .. " 已领奖重启")
        for attempt = 1, 2 do
            eq(ctx.story.backfillCleared(), 0, label .. " 已领奖backfill#" .. attempt .. "不再入队")
            ctx.play(); ctx.dialogue.skip()
            eq(#ctx.actions, 0, label .. " 已领奖重启skip不再发action")
        end
        eq(shards(ctx), 10, label .. " 重复重启后碎片仍为10")
        ctx = restart(ctx, label .. " 第二次重启")
        eq(ctx.story.backfillCleared(), 0, label .. " 第二次重启不补82")
        eq(shards(ctx), 10, label .. " 第二次重启不双发")
    end

    -- 用例7：旧中断档 claimed82=true + 空granted补播；更早无台账claimed档保守不补。
    for _, key in ipairs({ "82", 82 }) do
        local ctx = seed({ claimed = { [key] = true, ["51"] = true }, granted = {} })
        ctx = restart(ctx, "用例7 旧中断档键=" .. type(key))
        backfill(ctx, "用例7 空台账claimed仍补播")
        unawarded(ctx, "用例7 旧claimed起播保持", true)
        ctx.dialogue.skip()
        eq(#ctx.actions, 1, "用例7 活跃skip真正完成并发一次claim")
        rewarded(ctx, "用例7 旧中断档skip补发")
        ctx.finished = {}
        ctx = restart(ctx, "用例7 skip领奖后重启")
        eq(ctx.story.backfillCleared(), 0, "用例7 skip已领奖不补播")
        eq(shards(ctx), 10, "用例7 skip只发10")

        ctx = seed({ claimed = { [key] = true, ["51"] = true }, noGranted = true, shards = 0 })
        eq(ctx.story.backfillCleared(), 0, "用例7 旧无granted且claimed键=" .. type(key) .. "保守不补")
        ctx = restart(ctx, "用例7 无台账旧档")
        eq(session(ctx).scenarioRewardsGranted, nil, "用例7 RestoreData不擅自补建旧台账")
        eq(ctx.story.backfillCleared(), 0, "用例7 无台账旧档JSON重启仍保守不补")
        ctx.play(); ctx.dialogue.skip()
        eq(#ctx.actions, 0, "用例7 无台账已claimed档不发claim/action")
        eq(shards(ctx), 0, "用例7 已消费碎片旧档也不因余额0重发")
    end
    -- claimed/granted分别覆盖数字、字符串、相反键false；StoryPlayer读取任一true，而非只看claimed。
    -- 双键冲突fixture必须在真实Dispatcher.set归一化之后放入；本用例测Story的读取，不测Schema合并顺序。
    for _, key in ipairs({ "82", 82 }) do
        local other = type(key) == "number" and "82" or 82
        local ctx = seed({ shards = 10 })
        session(ctx).scenarioRewardsGranted = { [key] = true, [other] = false }
        eq(ctx.story.enqueue(82), false, "用例8 granted键=" .. type(key) .. "优先且屏蔽82")
        eq(ctx.story.backfillCleared(), 0, "用例8 claimed未写但granted已领奖不补播")
        ctx = seed()
        session(ctx).claimedScenarios = { [key] = true, [other] = false, ["51"] = true }
        check(ctx.story.enqueue(82), "用例8 空granted覆盖claimed双键，允许补82")
        ctx = seed({ noGranted = true })
        session(ctx).claimedScenarios = { [key] = true, [other] = false, ["51"] = true }
        eq(ctx.story.enqueue(82), false, "用例8 无granted尊重claimed任一true键")
    end

    -- 用例9a：205已有资格但首次取数据失败；失败叶子不替代Service，并保留完整heroes存档。
    local ctx = seed()
    backfill(ctx, "用例9a 已通205首次起播")
    ctx.unavailableHeroes = true
    finishNormally(ctx, "用例9a 首次领奖取数据失败")
    check(not ctx.actions[1].result.success, "用例9a 真实服务首次领奖失败")
    eq(ctx.actions[1].result.reason, "数据未加载", "用例9a 失败来自真实Service而非假回包")
    check(not marked(session(ctx), "scenarioRewardsGranted") and not marked(session(ctx), "claimedScenarios"),
        "用例9a 已通205但失败仍未granted/claimed")
    eq(shards(ctx), 0, "用例9a 失败未发碎片")
    ctx.play()
    eq(#ctx.actions, 1, "用例9a 不声称同会话自动重试")
    ctx.finished = {}
    ctx = restart(ctx, "用例9a 首次失败中断重启")
    backfill(ctx, "用例9a 新Story实例backfill重试")
    unawarded(ctx, "用例9a 重启重新起播")
    finishNormally(ctx, "用例9a 重启重试")
    rewarded(ctx, "用例9a 重试恰发10")

    -- 用例9b：未通205仍不发，必须补通后中断重启backfill才重试，不冒称同会话自动重试。
    ctx = seed({ cleared = false })
    ctx.pending[1] = { scenarioId = 82, config = config.SCENARIO_82 } -- 模拟旧待播/回包，但服务仍校验资格。
    ctx.play(); unawarded(ctx, "用例9 未通205起播")
    finishNormally(ctx, "用例9 首次领奖失败")
    check(not ctx.actions[1].result.success, "用例9 首次真实领奖失败")
    eq(ctx.actions[1].result.reason, "关卡未通关", "用例9 服务校验205资格")
    check(not marked(session(ctx), "scenarioRewardsGranted") and not marked(session(ctx), "claimedScenarios"),
        "用例9 失败不写granted/claimed")
    eq(shards(ctx), 0, "用例9 未通205不发碎片")
    ctx.finished = {}
    ctx = restart(ctx, "用例9 失败中断重启")
    eq(ctx.story.backfillCleared(), 0, "用例9 重启未通205不补播")
    eq(#ctx.actions, 0, "用例9 重启不自动重试失败动作")
    check(not marked(session(ctx), "scenarioRewardsGranted"), "用例9 失败JSON仍未granted")
    check(BS.NextStage(UID, 205, nil), "用例9 重启后真实补通205")
    ctx = restart(ctx, "用例9 补通后再重启")
    backfill(ctx, "用例9 新实例backfill才重试")
    ctx.dirty = {}; unawarded(ctx, "用例9 重试起播")
    finishNormally(ctx, "用例9 重启重试成功")
    rewarded(ctx, "用例9 重试一次发10")

    -- 用例10：非82沿用正式源预标记，不把修复扩大到其它情景（队列/待播/后续三种来源）。
    for _, source in ipairs({ "queue", "pending", "follow" }) do
        ctx = seed({ noGranted = true })
        local pending = { scenarioId = 27, config = config.SCENARIO_27 }
        if source == "queue" then ctx.story.enqueue(27)
        elseif source == "pending" then ctx.pending[1] = pending
        else ctx.follow = { pending } end
        ctx.play()
        check(ctx.dialogue.isActive(), "用例10 非82 " .. source .. "正式起播")
        check(session(ctx).claimedScenarios["27"] == true, "用例10 非82 " .. source .. "仍起播预标记")
        eq(session(ctx).scenarioRewardsGranted, nil, "用例10 非82不提前建台账")
        eq(#ctx.actions, 0, "用例10 非82起播也不提前发action")
        eq(shards(ctx), 0, "用例10 非82未碰82碎片")
        ctx.dialogue.skip()
        check(ctx.actions[1].result.success, "用例10 非82 preClaimed正式服务仍可领奖")
    end
    eq(ioCounts.images, 0, "全部小情景未创建GPU图片")
    check(ioCounts.writes > 0 and ioCounts.reads > 0 and ioCounts.writes == ioCounts.renames,
        "真实Save多次Flush/Restore走内存临时File与原子替换，不触碰玩家文件")
    print(PREFIX .. "production restart instances=" .. instances .. " JSON writes=" .. ioCounts.writes
        .. " reads=" .. ioCounts.reads .. " rename=" .. ioCounts.renames)
end

-- ======================== 旧真实服务用例（保持） ========================

local function legacyCases()
    setupLegacy()
    print(PREFIX .. "start")

    local config = require("config.ScenarioDialogueConfig")
    local awakening = require("config.AwakeningConfig")
    eq(config.SCENARIO_82.rewards[1].amount, 10, "剧情展示配置为10碎片")
    eq(awakening.getShardCost(1), 10, "首次觉醒仍消耗10碎片")

    -- 用例1：旧档补播——已首通 205，情景 82 未领 → backfillCleared 补入队，take 能取到
    resetModules({ cleared205 = true })
    local added = StoryPlayer.backfillCleared()
    check(added >= 1, "用例1: backfillCleared 补入队 (added=" .. tostring(added) .. ")")
    local found82 = false
    local guard = 0
    while guard < 50 do
        guard = guard + 1
        local pending = StoryPlayer.take()
        if not pending then break end
        if pending.scenarioId == 82 then found82 = true end
    end
    check(found82, "用例1: 补播队列含情景82（首通205大狗嚼引导）")

    -- 用例2：preClaimed=true 领奖——claimed[82] 已预标记（模拟客户端播放前预写），
    --   关卡已通 → 仍应成功发 10 碎片（旧代码此处会被"已领取"拒绝）
    resetModules({ cleared205 = true, claimed82 = true, shards = 0 })
    local ok2, err2, res2 = BS.ClaimScenarioReward(UID, 82, true)
    check(ok2, "用例2: preClaimed=true 领奖成功: " .. tostring(err2))
    eq(res2 and res2.rewardType, "shard", "用例2: 奖励类型 shard")
    eq(res2 and res2.reward and res2.reward.amount, 10, "用例2: 奖励回包数量10")
    eq(shardsOf(1), 10, "用例2: 大狗嚼碎片 +10")
    check(grantedOf(82), "用例2: scenarioRewardsGranted 记账")

    -- 用例3：无 preClaimed 且已 claimed → 拒绝（证明预标记场景必须带 preClaimed）
    resetModules({ cleared205 = true, claimed82 = true, shards = 0 })
    local ok3, err3 = BS.ClaimScenarioReward(UID, 82, nil)
    check(not ok3, "用例3: 无 preClaimed 且已 claimed 被拒: " .. tostring(err3))
    eq(shardsOf(1), 0, "用例3: 未发碎片")

    -- 用例4：重复领取被账本拒绝（接用例2 已发放状态，再带 preClaimed 也刷不动）
    resetModules({ cleared205 = true, claimed82 = true, shards = 0 })
    BS.ClaimScenarioReward(UID, 82, true)   -- 第一次发放（shards→10, granted[82]=true）
    local ok4, err4 = BS.ClaimScenarioReward(UID, 82, true)
    check(not ok4, "用例4: 重复领取（即便 preClaimed）被账本拒绝: " .. tostring(err4))
    eq(shardsOf(1), 10, "用例4: 碎片仍为10（未重复发放）")

    -- 用例5：关卡未通关 → 领取失败且不记账；补通关后可重试成功
    resetModules({ cleared205 = false, shards = 0 })
    local ok5a, err5a = BS.ClaimScenarioReward(UID, 82, true)
    check(not ok5a, "用例5a: 未通关205 领取失败: " .. tostring(err5a))
    check(not grantedOf(82), "用例5a: 失败未记账（granted 空，可重试）")
    modules.battle.clearedStages["205"] = true   -- 补通关
    local ok5b, err5b = BS.ClaimScenarioReward(UID, 82, true)
    check(ok5b, "用例5b: 补通关后重试成功: " .. tostring(err5b))
    eq(shardsOf(1), 10, "用例5b: 重试发放 10 碎片")
    check(grantedOf(82), "用例5b: 成功后记账")

end

function Start()
    local ok, err = pcall(function()
        legacyCases()
        productionCases()
    end)
    -- 即使源码load/require/存档/断言抛错也必须清理并Exit，禁止工具退出0被当成通过。
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then
        print(PREFIX .. "[FAIL] exception: " .. tostring(err))
        print(PREFIX .. "RESULT FAIL checks=" .. checks .. " failures=" .. math.max(1, #failures))
    else
        print(PREFIX .. "RESULT ALL PASS checks=" .. checks)
    end
    engine:Exit()
end
