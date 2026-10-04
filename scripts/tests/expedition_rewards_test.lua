-- 单机远征等级/领奖事务回归。生产模块从资源源码 load 隔离实例，存档仅使用内存 File。
-- Runtime: tests/expedition_rewards_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
function Start()
    local originalRequire, originalFile, originalSystem = _G.require, File, fileSystem
    local originalTime = os.time
    local assertions, cases = 0, 0
    local function eq(actual, expected, label)
        assertions = assertions + 1
        assert(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
    end
    local function check(value, label) eq(not not value, true, label) end
    local function same(actual, expected, label)
        if type(expected) ~= "table" then eq(actual, expected, label); return end
        eq(type(actual), "table", label .. " table")
        for key, value in pairs(expected) do same(actual[key], value, label .. "." .. tostring(key)) end
        for key in pairs(actual) do check(expected[key] ~= nil, label .. " unexpected " .. tostring(key)) end
    end
    local function runCase(label, fn)
        fn()
        cases = cases + 1
        print("[expedition_rewards_test] PASS " .. label)
    end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for key, item in pairs(value) do out[key] = copy(item) end
        return out
    end
    ---@type table<string, any>
    local loaded, mocks = {}, {}
    ---@type table<string, string>
    local memory = {}
    local failure = ""
    local writeCount, renameCount = 0, 0
    local now = 100000
    local savePath, pendingPath = "standalone_save.json", "standalone_save.pending.json"
    local results = {}
    local allow = { [savePath] = true, [pendingPath] = true }
    local function pathAllowed(path)
        assert(allow[path], "禁止真实存档/意外文件访问 " .. tostring(path))
    end
    -- 所有路径都 fail-closed，失败模式模拟已经写出部分字节的磁盘错误。
    _G.File = function(path, mode)
        pathAllowed(path)
        local opened = failure ~= "open" or mode ~= FILE_WRITE
        if opened and mode == FILE_WRITE then memory[path] = "" end
        return {
            IsOpen = function() return opened end,
            Close = function() opened = false end,
            ReadString = function() return memory[path] or "" end,
            WriteString = function(_, text)
                assert(path == pendingPath, "不能直接截断玩家旧档")
                writeCount = writeCount + 1
                if failure == "write" or failure == "throw" then
                    memory[path] = text:sub(1, 9)
                    if failure == "throw" then error("injected partial write") end
                    return false
                end
                memory[path] = text
                return true
            end,
        }
    end
    _G.fileSystem = {
        FileExists = function(_, path) pathAllowed(path); return memory[path] ~= nil end,
        Delete = function(_, path) pathAllowed(path); memory[path] = nil; return true end,
        Rename = function(_, src, dest)
            pathAllowed(src); pathAllowed(dest)
            renameCount = renameCount + 1
            if failure == "rename" then return false end
            memory[dest], memory[src] = memory[src], nil
            return true
        end,
    }
    os.time = function() return now end
    local production = {
        ["core.GameState"] = true, ["core.EventBus"] = true,
        ["runtime.LocalActionBridge"] = true, ["runtime.LocalDispatcher"] = true,
        ["runtime.ClientDispatcher"] = true, ["rules.character.PlayerDataManager"] = true,
        ["rules.task.TaskService"] = true, ["rules.task.TaskHandler"] = true,
        ["rules.currency.CurrencyService"] = true, ["boot.StandaloneSave"] = true,
    }
    local configs = {
        ["config.GameConfig"] = true, ["config.GameEvents"] = true,
        ["config.ExpTable"] = true, ["config.TaskConfig"] = true,
        ["config.ResourceDefs"] = true, ["config.HeroConfig"] = true,
        ["config.AwakeningConfig"] = true, ["config.StageConfig"] = true,
        ["shared.Protocol"] = true, ["shared.ModuleRegistry"] = true,
        ["shared.schemas.CharacterSchema"] = true, ["shared.heroes.TeamSlots"] = true,
        ["shared.quota.QuotaConsts"] = true,
    }
    mocks["runtime.ClientMessageHandler"] = { handleActionResult = function(result)
        results[#results + 1] = result
    end }
    mocks["ui.battle.scene.BattleScene"] = { setBattleData = function() end }
    local offline = {
        HasPendingRewards = function() return false end,
        MarkOnline = function(uid)
            local session = loaded["rules.character.PlayerDataManager"].GetModule(uid, "session")
            if session and (session.lastOnlineTime or 0) > 0 then session.lastOnlineTime = now end
        end,
    }
    mocks["rules.offline.OfflineService"] = offline
    -- 非目标 Handler 不加载业务依赖；GM 测试使用真实 PDM 的反向 player MarkDirty 路径。
    mocks["rules.gm.GMHandler"] = { actionHandlers = {
        gm_player_level_up = function(uid)
            local pdm = loaded["rules.character.PlayerDataManager"]
            local player = pdm.GetModule(uid, "player")
            player.level = player.level + 1
            player.exp = 0
            pdm.MarkDirty(uid, "player")
            return { success = true, newLevel = player.level }
        end,
    } }
    mocks["rules.redeem.RedeemService"] = { Init = function() end }
    mocks["systems.EquipmentSystem"] = { hydrateInventory = function() end }
    mocks["systems.ExtraTalentSystem"] = { normalize = function(data) return data end }
    local ignoredHandlers = {
        "rules.battle.BattleHandler", "rules.hero.HeroHandler", "rules.gacha.GachaHandler",
        "rules.equipment.EquipmentHandler", "rules.blacksmith.BlacksmithHandler", "rules.redeem.RedeemHandler",
        "rules.awakening.AwakeningHandler", "rules.advancement.AdvancementHandler", "rules.talent.TalentHandler",
        "rules.signin.SignInHandler", "rules.market.MarketHandler", "rules.loot.LootHandler",
        "rules.sweep.SweepHandler", "rules.artifact.ArtifactHandler", "rules.dungeon.DungeonHandler",
        "rules.offline.OfflineHandler", "rules.tower.TowerHandler",
    }
    for _, name in ipairs(ignoredHandlers) do mocks[name] = {} end
    -- 原18例也不以名称前缀放行任意业务依赖。
    for _, name in ipairs({
        "shared.player.PlayerSchema", "shared.currency.CurrencySchema", "shared.heroes.HeroesSchema",
        "shared.equipment.EquipmentSchema", "shared.battle.BattleSchema", "shared.lootbox.LootboxSchema",
        "shared.talents.TalentsSchema", "shared.signin.SigninSchema", "shared.redeem.RedeemSchema",
        "shared.task.TaskSchema", "shared.task.TaskCompat", "shared.session.SessionSchema",
        "shared.quota.QuotaSchema", "shared.slotenhance.SlotEnhanceSchema", "shared.tavern.TavernSchema",
        "shared.artifact.ArtifactSchema", "shared.artifact.ArtifactDefs", "shared.dungeon.DungeonSchema",
        "shared.dungeon.DungeonCompat", "shared.profile.ProfileSchema", "config.DungeonConfig",
    }) do configs[name] = true end
    local function isolatedRequire(name)
        if mocks[name] then return mocks[name] end
        if loaded[name] then return loaded[name] end
        if production[name] then
            local path = name:gsub("%.", "/") .. ".lua"
            local source = cache:GetFile(path)
            assert(source and source:IsOpen(), "missing production source " .. path)
            local lines = {}
            while not source:IsEof() do lines[#lines + 1] = source:ReadLine() end
            source:Dispose()
            local chunk, err = load(table.concat(lines, "\n"), "@" .. path, "t", _G)
            assert(chunk, err)
            local value = chunk()
            loaded[name] = value
            return value
        end
        if configs[name] then
            local value = originalRequire(name)
            loaded[name] = value
            return value
        end
        error("unexpected dependency " .. name)
    end
    -- 只读配置及Schema预加载时使用引擎require，避免把非目标依赖当成运行期业务。
    for name in pairs(configs) do loaded[name] = originalRequire(name) end
    _G.require = isolatedRequire
    local ok, err = pcall(function()
        local State = require("core.GameState")
        local Bus = require("core.EventBus")
        local Events = require("config.GameEvents")
        local Exp = require("config.ExpTable")
        local Bridge = require("runtime.LocalActionBridge")
        local Dispatcher = require("runtime.ClientDispatcher")
        local PDM = require("rules.character.PlayerDataManager")
        local Tasks = require("rules.task.TaskService")
        local Config = require("config.TaskConfig")
        local Currency = require("rules.currency.CurrencyService")
        local Save = require("boot.StandaloneSave")
        local Protocol = require("shared.Protocol")
        local ups, playerNotifications = {}, 0
        local rewardNotices = 0
        local levelTasks, allLevelTasks, heroRewards = {}, {}, {}
        for _, task in ipairs(Config.ACHIEVEMENT) do
            if task.group == "level" then
                allLevelTasks[#allLevelTasks + 1] = task
                if task.id:match("^a_plv_%d+$") then levelTasks[#levelTasks + 1] = task end
            elseif task.group == "hero" then heroRewards[task.id] = copy(task.reward) end
        end
        eq(#levelTasks, 9, "保留全部九个现有远征奖励")
        eq(#allLevelTasks, 209, "原九项外加200项独立bonus")
        local originalRewards = {}
        for _, task in ipairs(levelTasks) do originalRewards[task.id] = copy(task.reward) end
        local function bonusId(level) return "a_plv_bonus_v1_" .. level end
        Bus.on(Events.PLAYER_LEVEL_UP, function(event)
            eq(PDM.GetModule(1, "player"), Dispatcher.get("player"), "升级时PDM Dispatcher同表")
            eq(PDM.GetModule(1, "player").level, event.toLevel, "规则层先提交最终等级")
            eq(State.getLevel(), event.toLevel, "升级事件读取单机getter")
            eq(event.player.level, event.toLevel, "升级payload完整player")
            eq(event.level, event.toLevel, "旧level字段兼容")
            ups[#ups + 1] = event
        end)
        Dispatcher.subscribe("player", function() playerNotifications = playerNotifications + 1 end)
        local function flushBaseline()
            failure = ""
            eq(Save.Flush(), true, "内存基线真实Flush成功")
        end
        local function setFixture(level, claimed)
            failure = ""
            State.syncPlayerData({ level = level, exp = 0 }, { silent = true })
            State.setGold(100)
            State.setGems(20)
            local currencySchema = require("shared.schemas.CharacterSchema").Fields.currency
            local currency = currencySchema.getDefault()
            currencySchema.onLoad(currency) -- 与真实RestoreData的规范化结构一致，余额仍是全新fixture。
            currency.gold, currency.gems = 100, 20
            State.syncFromCurrency(currency, { silent = true })
            Dispatcher.set("currency", currency)
            local task = require("shared.schemas.CharacterSchema").Fields.task.getDefault()
            task.achClaimed = claimed or {}
            Dispatcher.set("task", task)
            Dispatcher.set("heroes", { roster = {}, deployed = {} })
            Dispatcher.set("session", { lastOnlineTime = 50000 })
            Tasks.RefreshAchievements(1)
            results = {}
            flushBaseline()
            rewardNotices = 0
        end
        local function lastResult()
            assert(#results > 0, "must deliver action result")
            return results[#results]
        end
        local function dispatch(taskId)
            eq(Bridge.dispatch(Protocol.ACTION_TYPES.CLAIM_TASK, { taskId = taskId }), true, "已路由任务请求")
            return lastResult()
        end
        local function all(level, scope)
            eq(Bridge.dispatch(Protocol.ACTION_TYPES.CLAIM_ALL_TASKS, { scope = scope or "level", level = level }),
                true, "已路由一键请求")
            return lastResult()
        end
        local function expectClaims(result, expected, label)
            eq(result.success, true, label .. "成功")
            eq(result.scope, "level", label .. "页签")
            eq(#result.claimed, #expected, label .. "领取项数")
            eq(#result.rewards, #expected, label .. "完整奖励项数")
            local seen = {}
            for index, id in ipairs(result.claimed) do
                check(not seen[id], label .. "不重复 " .. id)
                seen[id] = true
                local def = Config.findById(id)
                same(result.rewards[index], def.reward, label .. "回包同源 " .. id)
            end
            for _, id in ipairs(expected) do check(seen[id], label .. "必须领取 " .. id) end
        end
        local function expectBalances(expected, label)
            same(Dispatcher.get("currency"), expected, label .. "currency")
            local saved = cjson.decode(memory[savePath])
            same(saved.modules.currency, expected, label .. "落盘currency")
            for key, value in pairs(expected) do
                if State.exportSave()[key] ~= nil then
                    eq(State.exportSave()[key], value, label .. "GameState " .. key)
                    eq(saved.gameState[key], value, label .. "落盘GameState " .. key)
                end
            end
        end
        local function addRewards(expected, entries, skipped)
            for _, task in ipairs(entries) do
                if not (skipped or {})[task.id] then
                    local key = Currency.REWARD_TO_CURRENCY[task.reward.type]
                    assert(key, "等级奖励须能映射currency " .. task.id)
                    expected[key] = (expected[key] or 0) + task.reward.amount
                end
            end
            return expected
        end

        runCase("init前跨级提交与唯一事件", function()
            State.syncPlayerData({ level = 1, exp = 0 }, { silent = true })
            local before = playerNotifications
            local amount = Exp.getPlayerExpForLevel(1) + Exp.getPlayerExpForLevel(2) + Exp.getPlayerExpForLevel(3) + 7
            State.addExp(amount)
            eq(State.getLevel(), 4, "跨三等级")
            eq(State.getExp(), 7, "跨级余经验")
            eq(State.getMaxExp(), Exp.getPlayerExpForLevel(4), "最终maxExp")
            eq(#ups, 1, "跨级仅一次庆祝")
            eq(ups[1].fromLevel, 1, "fromLevel起点")
            eq(ups[1].toLevel, 4, "toLevel终点")
            eq(playerNotifications - before, 1, "提交仅一次Dispatcher通知")
            Tasks.RefreshAchievements(1) -- 无task时安全
            State.setLocalPlayerSync(nil)
            State.setLevel(5)
            eq(#ups, 2, "init前setLevel也发唯一升级")
            eq(PDM.GetModule(1, "player").level, 5, "init前setter已接规则player")
        end)
        Bridge.init()
        Dispatcher.subscribe("currency", function() rewardNotices = rewardNotices + 1 end)
        runCase("反向规则GM同步不漏不重复", function()
            local before = #ups
            eq(Bridge.dispatch("gm_player_level_up", {}), true, "GM反向路由")
            eq(State.getLevel(), 6, "反向同步getter")
            eq(#ups, before + 1, "GM发一个升级")
            eq(ups[#ups].fromLevel, 5, "GM旧等级")
            PDM.MarkDirty(1, "player")
            PDM.MarkDirty(1, "player")
            eq(#ups, before + 1, "重复MarkDirty无额外升级")
            State.setExp(15)
            eq(State.getExp(), 15, "直接setExp镜像")
            eq(PDM.GetModule(1, "player").exp, 15, "setExp规则读取一致")
            eq(#ups, before + 1, "只改exp不升级")
        end)
        runCase("顶级经验边界与反向降级不庆祝", function()
            State.syncPlayerData({ level = Exp.PLAYER_MAX_LEVEL - 1, exp = 0 }, { silent = true })
            local before = #ups
            State.addExp(Exp.getPlayerExpForLevel(Exp.PLAYER_MAX_LEVEL - 1) + 500)
            eq(State.getLevel(), Exp.PLAYER_MAX_LEVEL, "经验达到最高等级")
            eq(State.getExp(), 0, "顶级清空余经验")
            eq(State.getMaxExp(), 0, "顶级maxExp为0")
            eq(#ups, before + 1, "到顶仅一个升级")
            State.addExp(500)
            eq(#ups, before + 1, "已顶级再获经验不庆祝")
            local player = PDM.GetModule(1, "player")
            player.level, player.exp = 10, 0
            PDM.MarkDirty(1, "player")
            eq(State.getLevel(), 10, "反向降低等级同步")
            eq(#ups, before + 1, "降级不误庆祝")
            PDM.MarkDirty(1, "player")
            eq(#ups, before + 1, "降级后重复不庆祝")
        end)
        runCase("等级进度无需heroes，getter不启用代理", function()
            setFixture(10)
            Dispatcher.getAll().heroes = nil
            Tasks.RefreshAchievements(1)
            eq(Dispatcher.get("task").achProg.player_level, 10, "无heroes仍有等级进度")
            Dispatcher.get("player").level = 99
            eq(State.getLevel(), 10, "不启用PDM/PlayerStore getter代理")
            Bridge.syncPlayerIntoPdm()
            eq(Dispatcher.get("player").level, 10, "重新镜像不倒灌旧等级")
        end)
        runCase("单领所有奖励原样保留且重复拒绝", function()
            setFixture(5)
            local task = levelTasks[1]
            local reward = copy(task.reward)
            local key = Currency.REWARD_TO_CURRENCY[reward.type]
            local balance = Dispatcher.get("currency")[key] or 0
            local previousWrites = writeCount
            local result = dispatch(task.id)
            eq(result.success, true, "单领成功")
            eq(result.reward.type, reward.type, "保留原奖励type")
            eq(result.reward.amount, reward.amount, "保留原奖励amount")
            eq(Dispatcher.get("currency")[key], balance + reward.amount, "实际发奖")
            eq(Dispatcher.get("task").achClaimed[task.id], true, "成功才记永久账本")
            local saved = cjson.decode(memory[savePath])
            eq(saved.modules.currency[key], balance + reward.amount, "模块余额已落档")
            eq(saved.gameState[key], balance + reward.amount, "GameState余额已落档")
            eq(writeCount, previousWrites + 1, "领奖只写一批")
            eq(dispatch(task.id).reason, "already_claimed", "重复领取拒绝")
            eq(writeCount, previousWrites + 1, "重复不再写档")
        end)
        runCase("Lv1/33/100/200指定等级同级原礼包加bonus一次提交", function()
            for _, level in ipairs({1, 33, 100, 200}) do
                setFixture(level, { a_legacy_history = true })
                local entries = Config.LEVEL_TASKS[level]
                local expectedIds = {}
                for _, task in ipairs(entries) do expectedIds[#expectedIds + 1] = task.id end
                local expected = addRewards(copy(Dispatcher.get("currency")), entries)
                local writesBefore = writeCount
                expectClaims(all(level), expectedIds, "指定Lv" .. level)
                eq(writeCount, writesBefore + 1, "同级所有奖励原子一次落盘 " .. level)
                expectBalances(expected, "指定级实际奖励 " .. level)
                local saved = cjson.decode(memory[savePath])
                for _, task in ipairs(allLevelTasks) do
                    eq(not not saved.modules.task.achClaimed[task.id], task.target == level,
                        "指定level不误领历史/其他级 " .. task.id)
                end
                eq(saved.modules.task.achClaimed.a_legacy_history, true, "指定级保留历史")
                eq(rewardNotices, 1, "同级只推最终一次货币 " .. level)
                eq(all(level).reason, "nothing_to_claim", "同级整组重复拒绝 " .. level)
                eq(dispatch(bonusId(level)).reason, "already_claimed", "bonus单领也不重复 " .. level)
                if Config.findById("a_plv_" .. level) then
                    eq(dispatch("a_plv_" .. level).reason, "already_claimed", "同级旧礼包不重复 " .. level)
                end
                eq(writeCount, writesBefore + 1, "重复无多余写档 " .. level)
                local noticesBefore = rewardNotices
                if level < 200 then
                    eq(all(level + 1).reason, "nothing_to_claim", "未来级不可批领 " .. level)
                    eq(dispatch(bonusId(level + 1)).reason, "not_complete", "未来bonus不能单领 " .. level)
                    eq(writeCount, writesBefore + 1, "未来请求不写档")
                    eq(rewardNotices, noticesBefore, "未来请求不推奖励")
                end
                -- 不沿用进程内账本，真实RestoreData必须从内存File中的JSON重新恢复。
                Dispatcher.set("task", { achClaimed = {}, achProg = {} })
                State.setGems(0)
                eq(Save.RestoreData(), true, "指定级真实内存Flush/Restore " .. level)
                expectBalances(expected, "指定级读档奖励 " .. level)
                for _, id in ipairs(expectedIds) do eq(Dispatcher.get("task").achClaimed[id], true, "读档保留 " .. id) end
                writesBefore = writeCount
                eq(all(level).reason, "nothing_to_claim", "恢复后同级不重复 " .. level)
                eq(writeCount, writesBefore, "恢复后拒绝不再写档 " .. level)
            end
        end)
        runCase("旧已领可补bonus及bonus先领可补原礼包", function()
            for _, level in ipairs({5, 100, 200}) do
                local originalId, extraId = "a_plv_" .. level, bonusId(level)
                setFixture(level, { [originalId] = true, a_retired_task = true })
                local expected = addRewards(copy(Dispatcher.get("currency")), { Config.findById(extraId) })
                expectClaims(all(level), { extraId }, "旧已领补bonus " .. level)
                expectBalances(expected, "补bonus余额 " .. level)
                eq(dispatch(originalId).reason, "already_claimed", "不重发原奖励 " .. level)
                eq(dispatch(extraId).reason, "already_claimed", "补bonus后重复拒绝 " .. level)
                eq(Dispatcher.get("task").achClaimed.a_retired_task, true, "退役历史保留")
                setFixture(level, { [extraId] = true, a_retired_task = true })
                expected = addRewards(copy(Dispatcher.get("currency")), { Config.findById(originalId) })
                -- 直接调用真实Service，单独验证level筛选不依赖Handler替它实现。
                local success, reason, result = Tasks.ClaimAll(1, "level", level)
                eq(success, true, "Service反向部分已领成功 " .. level)
                eq(reason, nil, "Service无失败原因")
                result.success = success
                expectClaims(result, { originalId }, "bonus先领补原礼包 " .. level)
                expectBalances(expected, "反向补原奖励 " .. level)
                eq(dispatch(extraId).reason, "already_claimed", "反向不重发bonus")
                eq(all(level).reason, "nothing_to_claim", "反向补齐后不可重复")
            end
        end)
        runCase("非法level/scope在发奖落盘之前拒绝", function()
            setFixture(200, { a_legacy_history = true })
            local currency = copy(Dispatcher.get("currency"))
            local history = copy(Dispatcher.get("task").achClaimed)
            local previous, writesBefore = memory[savePath], writeCount
            for _, level in ipairs({0, -1, 201, 1.5, "33", false, {}, math.huge, -math.huge, 0 / 0}) do
                local result = all(level)
                eq(result.success, false, "非法level失败 " .. tostring(level))
                eq(result.reason, "invalid_params", "Handler传递非法level拒绝 " .. tostring(level))
            end
            for _, scope in ipairs({"hero", "clear"}) do
                eq(all(33, scope).reason, "invalid_params", "非level页签不可传level " .. scope)
            end
            eq(all(nil, "bad_scope").reason, "invalid_scope", "非法scope拒绝")
            eq(writeCount, writesBefore, "非法参数不写档")
            eq(memory[savePath], previous, "非法参数旧档不变")
            same(Dispatcher.get("currency"), currency, "非法参数余额无变化")
            same(Dispatcher.get("task").achClaimed, history, "非法参数领取账本无变化")
            eq(rewardNotices, 0, "非法参数无奖励通知")
        end)
        runCase("无效奖励全量预校验无部分发放", function()
            setFixture(10, { a_legacy_history = true })
            local second = levelTasks[2]
            local old = second.reward
            second.reward = { type = "unknown", amount = 1 }
            local before = memory[savePath]
            local writesBefore = writeCount
            local result = all()
            second.reward = old
            eq(result.success, false, "一键无效奖励失败")
            eq(result.reason, "invalid_reward", "明确预校验错误")
            eq(memory[savePath], before, "预校验失败旧档保持")
            eq(writeCount, writesBefore, "全量预校验在写档/发奖前")
            check(not Dispatcher.get("task").achClaimed[levelTasks[1].id], "首项也未领")
            eq(Dispatcher.get("task").achClaimed.a_legacy_history, true, "历史不清除")
            for _, amount in ipairs({ 0, -1, 0.5, math.huge }) do
                local first = levelTasks[1]
                local original = first.reward
                first.reward = { type = "gold", amount = amount }
                eq(dispatch(first.id).reason, "invalid_reward", "拒绝无效数量 " .. tostring(amount))
                first.reward = original
            end
            local first = levelTasks[1]
            local original = first.reward
            first.reward = nil
            eq(dispatch(first.id).reason, "invalid_reward", "nil reward不抛错")
            first.reward = original
        end)
        runCase("无效bonus同级全量预校验不先发原礼包", function()
            setFixture(100, { a_legacy_history = true })
            local bonus = Config.findById(bonusId(100))
            local reward = bonus.reward
            local previous, writesBefore = memory[savePath], writeCount
            local currency = copy(Dispatcher.get("currency"))
            for _, invalid in ipairs({
                {type="unknown", amount=100}, {type="diamond", amount=0},
                {type="diamond", amount=-1}, {type="diamond", amount=0.5},
                {type="diamond", amount=math.huge}, {type="diamond", amount=0 / 0},
            }) do
                bonus.reward = invalid
                local result = all(100)
                bonus.reward = reward
                eq(result.success, false, "无效bonus拒绝")
                eq(result.reason, "invalid_reward", "无效bonus原因")
                eq(memory[savePath], previous, "无效bonus不写旧档")
                eq(writeCount, writesBefore, "预校验不进入Flush")
                same(Dispatcher.get("currency"), currency, "无效bonus不先发原礼包")
                check(not Dispatcher.get("task").achClaimed.a_plv_100, "原礼包也不记账")
                check(not Dispatcher.get("task").achClaimed[bonus.id], "bonus不记账")
            end
            bonus.reward = nil
            eq(all(100).reason, "invalid_reward", "nil bonus奖励不抛错")
            bonus.reward = reward
            eq(rewardNotices, 0, "预校验无奖励通知")
        end)
        runCase("GrantReward中途false与exception一键整体回滚", function()
            setFixture(10, { a_legacy_history = true })
            local grant = Currency.GrantReward
            local balance = copy(Dispatcher.get("currency"))
            local function failGrant(throws)
                local calls = 0
                Currency.GrantReward = function(uid, reward)
                    calls = calls + 1
                    if calls == 2 then
                        if throws then error("injected GrantReward exception") end
                        return false
                    end
                    return grant(uid, reward)
                end
                local result = all()
                Currency.GrantReward = grant
                eq(result.success, false, "发奖中途失败")
                eq(result.reason, "reward_failed", "发奖失败原因")
                for key, value in pairs(balance) do same(Dispatcher.get("currency")[key], value, "回滚余额 " .. key) end
                check(not Dispatcher.get("task").achClaimed[levelTasks[1].id], "已发首项未记账")
                eq(Dispatcher.get("task").achClaimed.a_legacy_history, true, "rollback保留历史")
                eq(rewardNotices, 0, "失败发奖不提前广播货币")
            end
            failGrant(false)
            failGrant(true)
        end)
        runCase("同级及整页已发bonus后GrantReward失败整体回滚", function()
            local grant = Currency.GrantReward
            for _, batch in ipairs({"node", "page"}) do
                for _, throws in ipairs({false, true}) do
                    setFixture(batch == "node" and 100 or 33, { a_legacy_history = true, [bonusId(1)] = true })
                    local currency = copy(Dispatcher.get("currency"))
                    local state = copy(State.exportSave())
                    local history = Dispatcher.get("task").achClaimed
                    local historyBefore = copy(history)
                    local heroes = copy(Dispatcher.get("heroes"))
                    local previous, writesBefore = memory[savePath], writeCount
                    local grantedBonus, calls = false, 0
                    Currency.GrantReward = function(uid, reward)
                        calls = calls + 1
                        local success = grant(uid, reward)
                        if reward.type == "diamond" and reward.amount == 100 then grantedBonus = true end
                        -- 节点第二项bonus已真实发出；整页至少发完一个bonus再在下一项失败。
                        if (batch == "node" and calls == 2) or (batch == "page" and grantedBonus and calls == 6) then
                            if throws then error("injected failure after real bonus grant") end
                            return false
                        end
                        return success
                    end
                    local result = all(batch == "node" and 100 or nil)
                    Currency.GrantReward = grant
                    check(grantedBonus, "失败前真实发过bonus " .. batch)
                    eq(result.success, false, "新奖励中途失败 " .. batch)
                    eq(result.reason, "reward_failed", "新奖励失败原因")
                    eq(writeCount, writesBefore, "发奖失败尚未进入保存")
                    eq(memory[savePath], previous, "失败旧档保持")
                    eq(Dispatcher.get("task").achClaimed, history, "失败保留账本引用")
                    same(history, historyBefore, "原及bonus账本全部回滚")
                    same(Dispatcher.get("currency"), currency, "真实已发bonus货币回滚")
                    same(State.exportSave(), state, "真实已发bonusGameState回滚")
                    same(Dispatcher.get("heroes"), heroes, "等级失败不改变heroes")
                    eq(rewardNotices, 0, "失败不通知奖励")
                    eq(all(batch == "node" and 100 or nil).success, true, "撤销故障后可重试 " .. batch)
                end
            end
        end)
        runCase("单领/一键写档失败保旧档和台账且可重试", function()
            for _, mode in ipairs({ "open", "write", "throw", "rename" }) do
                setFixture(10, { a_legacy_history = true })
                local previous = memory[savePath]
                local currency = copy(Dispatcher.get("currency"))
                local state = State.exportSave()
                local history = Dispatcher.get("task").achClaimed
                failure = mode
                local result = dispatch(levelTasks[1].id)
                eq(result.success, false, mode .. "单领失败")
                eq(result.reason, "save_failed", mode .. "单领保存失败原因")
                eq(memory[savePath], previous, mode .. "partial也保留旧档")
                eq(Dispatcher.get("task").achClaimed, history, mode .. "账本引用保留")
                check(not history[levelTasks[1].id], mode .. "不记未落盘奖励")
                result = all()
                eq(result.success, false, mode .. "一键失败")
                eq(result.reason, "save_failed", mode .. "一键保存失败原因")
                eq(memory[savePath], previous, mode .. "一键旧档保持")
                for key, value in pairs(currency) do same(Dispatcher.get("currency")[key], value, mode .. "回滚currency " .. key) end
                for key, value in pairs(state) do eq(State.exportSave()[key], value, mode .. "回滚GameState " .. key) end
                eq(history.a_legacy_history, true, mode .. "历史始终保留")
                for level = 1, 10 do check(not history[bonusId(level)], mode .. "失败不记bonus " .. level) end
                eq(rewardNotices, 0, mode .. "失败无领奖通知")
                failure = ""
                Save.Update(3) -- 自动重试写档只能写回滚后的旧奖励台账
                check(not cjson.decode(memory[savePath]).modules.task.achClaimed[levelTasks[1].id], "重试不能静默记失败领取")
                for level = 1, 10 do
                    check(not cjson.decode(memory[savePath]).modules.task.achClaimed[bonusId(level)], "重试不记失败bonus " .. level)
                end
                eq(all().success, true, mode .. "恢复后可重新一键领取")
            end
        end)
        runCase("一键保全部现有奖励并一次落盘", function()
            setFixture(200, { a_plv_5 = true, a_legacy_history = true })
            local expected = copy(Dispatcher.get("currency"))
            for _, task in ipairs(levelTasks) do
                if task.id ~= "a_plv_5" then
                    local reward = originalRewards[task.id]
                    local key = Currency.REWARD_TO_CURRENCY[reward.type]
                    expected[key] = (expected[key] or 0) + reward.amount
                end
            end
            for level = 1, 200 do expected.gems = expected.gems + 100 end
            local before = writeCount
            local result = all()
            eq(result.success, true, "一键成功")
            eq(#result.claimed, 208, "跳过旧已领八项加200bonus")
            eq(#result.rewards, 208, "所有奖励完整回包")
            eq(writeCount, before + 1, "全页一次写档")
            local saved = cjson.decode(memory[savePath])
            for key, value in pairs(expected) do
                same(saved.modules.currency[key], value, "保留累计模块奖励 " .. key)
                if State.exportSave()[key] ~= nil then eq(saved.gameState[key], value, "完整GameState奖励 " .. key) end
            end
            for _, task in ipairs(allLevelTasks) do eq(saved.modules.task.achClaimed[task.id], true, "持久账本 " .. task.id) end
            eq(saved.modules.task.achClaimed.a_legacy_history, true, "未识别历史也保留")
            eq(all().reason, "nothing_to_claim", "全部已领后一键不重复")
        end)
        runCase("bonus单领及同级保存失败保双账本并真实读档可重试", function()
            for _, mode in ipairs({"open", "write", "throw", "rename"}) do
                for _, batch in ipairs({"bonus", "node"}) do
                    setFixture(100, {a_legacy_history=true, [bonusId(33)]=true})
                    local previous = memory[savePath]
                    local currency = copy(Dispatcher.get("currency"))
                    local state = copy(State.exportSave())
                    local history = Dispatcher.get("task").achClaimed
                    local historyBefore = copy(history)
                    local heroes = copy(Dispatcher.get("heroes"))
                    failure = mode
                    local result = batch == "bonus" and dispatch(bonusId(100)) or all(100)
                    eq(result.success, false, mode .. "新奖励保存失败 " .. batch)
                    eq(result.reason, "save_failed", mode .. "新奖励失败原因 " .. batch)
                    eq(memory[savePath], previous, mode .. "新奖励保旧档")
                    eq(memory[pendingPath], nil, mode .. "失败清理残缺临时档")
                    eq(Dispatcher.get("task").achClaimed, history, "失败保账本引用")
                    same(history, historyBefore, "新旧领取记录一起回滚")
                    same(Dispatcher.get("currency"), currency, "新奖励余额回滚")
                    same(State.exportSave(), state, "新奖励GameState回滚")
                    same(Dispatcher.get("heroes"), heroes, "新奖励失败不改heroes")
                    eq(rewardNotices, 0, "保存失败不推奖励")
                    failure = ""
                    Save.Update(3)
                    same(cjson.decode(memory[savePath]).modules.task.achClaimed, historyBefore,
                        "自动保存重试只能保存失败前账本")
                    eq(Save.RestoreData(), true, "新奖励失败后真实RestoreData")
                    same(Dispatcher.get("task").achClaimed, historyBefore, "读档不出现失败奖励")
                    local expected = addRewards(copy(Dispatcher.get("currency")),
                        batch == "bonus" and {Config.findById(bonusId(100))} or Config.LEVEL_TASKS[100])
                    local writesBefore = writeCount
                    result = batch == "bonus" and dispatch(bonusId(100)) or all(100)
                    eq(result.success, true, "保存恢复后新奖励可重试 " .. batch)
                    eq(writeCount, writesBefore + 1, "新奖励重试只写一次")
                    expectBalances(expected, "新奖励恢复后余额")
                    eq(Dispatcher.get("task").achClaimed[bonusId(100)], true, "成功bonus有账本")
                    eq(not not Dispatcher.get("task").achClaimed.a_plv_100, batch == "node", "仅成功的原礼包记账")
                end
            end
        end)
        runCase("整页209项全部累计/旧礼包全领仍补20000及真实存档往返", function()
            for _, skipOriginals in ipairs({false, true}) do
                local history = {a_retired_task=true, ["a_hero_4"]=true}
                if skipOriginals then
                    for _, task in ipairs(levelTasks) do history[task.id] = true end
                end
                setFixture(200, history)
                local expected = addRewards(copy(Dispatcher.get("currency")), allLevelTasks, history)
                local expectedIds = {}
                for _, task in ipairs(allLevelTasks) do
                    if not history[task.id] then expectedIds[#expectedIds + 1] = task.id end
                end
                local heroes = copy(Dispatcher.get("heroes"))
                local writesBefore = writeCount
                expectClaims(all(), expectedIds, "整页全部累计")
                eq(#expectedIds, skipOriginals and 200 or 209, "原已领只补新bonus")
                eq(expected.gems, skipOriginals and 20020 or 20860, "20000bonus加原840黑晶")
                if not skipOriginals then
                    eq(expected.gold, 120100, "原120000金币累计")
                    eq(expected.essence, 6150, "原150加6000精粹累计")
                    eq(expected.recruitTicket, 2, "原招募券累计")
                    eq(expected.enhanceStone, 2, "原强化星累计")
                    eq(expected.arcaneDust, 600, "原奥术粉尘累计")
                    eq(expected.sweepTicket, 1, "原扫荡券累计")
                    eq(expected.stellarRecruitTicket, 1, "原星耀券累计")
                end
                eq(writeCount, writesBefore + 1, "200级整页原子一批写档")
                expectBalances(expected, "全部累计奖励")
                same(Dispatcher.get("heroes"), heroes, "等级奖励不改英雄数据")
                for id, reward in pairs(heroRewards) do
                    same(Config.findById(id).reward, reward, "等级领取不改变hero配置 " .. id)
                    eq(not not Dispatcher.get("task").achClaimed[id], id == "a_hero_4", "level页签不领取hero " .. id)
                end
                for _, task in ipairs(levelTasks) do same(task.reward, originalRewards[task.id], "原礼包内容未变") end
                flushBaseline()
                Dispatcher.set("task", {achClaimed={}, achProg={}})
                State.setGold(0)
                State.setGems(0)
                eq(Save.RestoreData(), true, "整页真实Flush/RestoreData")
                expectBalances(expected, "整页读档所有奖励")
                for _, task in ipairs(allLevelTasks) do
                    eq(Dispatcher.get("task").achClaimed[task.id], true, "所有持久ID恢复 " .. task.id)
                end
                eq(Dispatcher.get("task").achClaimed.a_retired_task, true, "恢复未知历史")
                eq(Dispatcher.get("task").achClaimed.a_hero_4, true, "恢复hero旧台账")
                writesBefore = writeCount
                eq(all().reason, "nothing_to_claim", "往返后整页不重复")
                for _, level in ipairs({1, 33, 100, 200}) do
                    eq(all(level).reason, "nothing_to_claim", "往返后指定级不重复 " .. level)
                    eq(dispatch(bonusId(level)).reason, "already_claimed", "往返后bonus不重复 " .. level)
                end
                eq(writeCount, writesBefore, "往返后重复全不写档")
            end
        end)
        runCase("老档静默修复镜像保留头像和所有历史", function()
            local before = #ups
            local old = { version = 1, savedAt = 90000, gameState = { level = 80, exp = 12, gold = 456, gems = 789 },
                modules = { player = { level = 1, exp = 0, avatarHeroId = 25 },
                    task = { achClaimed = { a_plv_5 = true, a_plv_10 = true, a_retired_task = true } },
                    currency = { gold = 456, gems = 789 }, session = {} } }
            memory[savePath] = cjson.encode(old)
            eq(Save.RestoreData(), true, "恢复旧档")
            eq(State.getLevel(), 80, "单机真实等级优先")
            eq(State.getExp(), 12, "老档经验优先")
            eq(PDM.GetModule(1, "player").level, 80, "旧镜像即时修复到规则层")
            eq(PDM.GetModule(1, "player").avatarHeroId, 25, "头像字段不被覆盖")
            eq(#ups, before, "读档silent不庆祝")
            Tasks.RefreshAchievements(1)
            eq(Dispatcher.get("task").achProg.player_level, 80, "老档进度使用真实等级")
            local history = Dispatcher.get("task").achClaimed
            eq(history.a_plv_5, true, "旧已领5保留")
            eq(history.a_retired_task, true, "退役任务历史保留")
            eq(dispatch("a_plv_5").reason, "already_claimed", "老档重复领取仍拒绝")
            local gemsBefore = State.getGems()
            expectClaims(all(5), {bonusId(5)}, "老档旧已领仍补bonus")
            eq(State.getGems(), gemsBefore + 100, "老档新增黑晶真实发放")
            eq(Dispatcher.get("task").achClaimed.a_plv_10, true, "老档另一礼包台账不受影响")
            flushBaseline()
            before = #ups
            eq(Save.RestoreData(), true, "新格式再次往返")
            eq(#ups, before, "再次恢复无重复庆祝")
            eq(Dispatcher.get("task").achClaimed.a_retired_task, true, "往返历史不丢")
            eq(Dispatcher.get("task").achClaimed[bonusId(5)], true, "老档新增bonus往返不丢")
            eq(all(5).reason, "nothing_to_claim", "老档新增已领往返不重复")
        end)
        runCase("Flush在线边界失败回滚与无Rename安全拒绝", function()
            setFixture(80)
            Save.OfflineChecked()
            local previous = memory[savePath]
            local oldTime = Dispatcher.get("session").lastOnlineTime
            failure = "rename"
            eq(Save.Flush(), false, "Flush明确false")
            eq(Dispatcher.get("session").lastOnlineTime, oldTime, "失败不推进在线时间")
            eq(memory[savePath], previous, "替换失败旧档仍在")
            failure = ""
            local rename = fileSystem.Rename
            fileSystem.Rename = nil
            eq(Save.Flush(), false, "无安全替换API不退回覆盖旧档")
            fileSystem.Rename = rename
            eq(Save.Flush(), true, "安全接口恢复可保存")
            eq(cjson.decode(memory[savePath]).modules.session.lastOnlineTime, now, "成功才落在线边界")
            check(renameCount > 0, "真实进入Rename接口")
        end)
        -- 保留原事务回归计数；下方是另外的完整源码实例，不借用旧fixture状态。
        eq(cases, 18, "原18例完整保留")
        -- 此断言之前原18例仍为17325个断言，额外门禁不计作旧覆盖。
        eq(assertions - 1, 17325, "原17325断言完整保留")

        -- 每次factory都重建业务/Schema/UI模型；仅可传入内存JSON字符串。
        -- 不加载main、Standalone启动器、真实PlayerStore/OfflineService，不使用package.loaded。
        local function newChain(json)
            ---@type table<string, any>
            local h = { loaded = {}, errors = {}, trace = {}, results = {}, shows = {}, toasts = {},
                files = {}, writes = 0, renames = 0, grants = 0, fail = "", clock = {elapsedTime = 100},
                view = {}, amounts = {}, drawing = false, sfx = {}, leafCalls = {} }
            if json then h.files[savePath] = json end
            local function note(kind, data)
                h.trace[#h.trace + 1] = {kind = kind, data = data}
            end
            local function bad(message)
                h.errors[#h.errors + 1] = message
                error(message)
            end
            local function noop() end
            local env = {
                assert = assert, error = error, pairs = pairs, ipairs = ipairs, next = next,
                type = type, tostring = tostring, tonumber = tonumber, select = select,
                pcall = pcall, xpcall = xpcall, rawset = rawset, rawget = rawget,
                setmetatable = setmetatable, getmetatable = getmetatable,
                math = math, string = string, table = table, cjson = cjson,
                os = {time = function() return now end, clock = os.clock, date = os.date},
                time = h.clock, H_focusPanel = false,
                print = function(...)
                    local parts = {...}
                    local message = tostring(parts[1] or "")
                    -- 生产pcall吞错也必须fail-closed，不能仅靠Runtime退出码判成功。
                    if message:find("subscriber error", 1, true) or message:find("onAnyUpdate error", 1, true)
                        or message:find("handler error", 1, true) or message:find("[LocalActionBridge] skip", 1, true) then
                        h.errors[#h.errors + 1] = message
                    end
                    print(...)
                end,
            }
            env._G = env
            setmetatable(env, {__index = function(_, key) return bad("unexpected global " .. tostring(key)) end})
            for _, key in ipairs({"FILE_READ", "FILE_WRITE", "NVG_ALIGN_LEFT", "NVG_ALIGN_RIGHT",
                "NVG_ALIGN_CENTER", "NVG_ALIGN_TOP", "NVG_ALIGN_BOTTOM", "NVG_ALIGN_MIDDLE"}) do
                env[key] = _G[key]
            end
            local function allowed(path)
                if not allow[path] then bad("chain禁止真实文件 " .. tostring(path)) end
            end
            env.File = function(path, mode)
                allowed(path)
                if mode ~= FILE_WRITE and mode ~= FILE_READ then bad("unexpected File mode") end
                if mode == FILE_WRITE and path ~= pendingPath then bad("不能直接截断旧档") end
                local opened = true
                if mode == FILE_WRITE then h.files[path] = "" end
                return {
                    IsOpen = function() return opened end,
                    Close = function() opened = false end,
                    ReadString = function() return h.files[path] or "" end,
                    WriteString = function(_, text)
                        if path ~= pendingPath or mode ~= FILE_WRITE then bad("unexpected write") end
                        h.writes = h.writes + 1
                        h.files[path] = text
                        note("write", text)
                        return true
                    end,
                }
            end
            env.fileSystem = {
                FileExists = function(_, path) allowed(path); return h.files[path] ~= nil end,
                Delete = function(_, path) allowed(path); h.files[path] = nil; return true end,
                Rename = function(_, src, dest)
                    allowed(src); allowed(dest)
                    if src ~= pendingPath or dest ~= savePath then bad("unexpected Rename direction") end
                    h.renames = h.renames + 1
                    if h.fail == "rename" then note("rename_failed"); return false end
                    h.files[dest], h.files[src] = h.files[src], nil
                    note("rename_ok", h.files[dest])
                    return true
                end,
            }
            -- 全部图形/SFX边界为显式spy；draw逻辑、排序、42行裁剪与输入滚动仍走完整Popup。
            for _, key in ipairs({"nvgSave", "nvgRestore", "nvgTranslate", "nvgScale", "nvgGlobalAlpha",
                "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgCircle", "nvgFillColor", "nvgFill",
                "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFillPaint", "nvgRotate",
                "nvgMoveTo", "nvgLineTo", "nvgClosePath", "nvgIntersectScissor", "nvgResetScissor",
                "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgTextBox"}) do env[key] = noop end
            env.nvgCreateImage = function() return 1 end
            env.nvgTextBounds = function(_, _, _, text) return #text * 12 end
            env.nvgRGBA = function(...) return {...} end
            env.nvgImagePattern = function() return {} end
            env.nvgRadialGradient = function() return {} end
            env.nvgLinearGradient = function() return {} end
            env.nvgText = function(_, x, y, text)
                h.texts[#h.texts + 1] = {x = x, y = y, text = text}
            end
            h.texts = {}
            local leaf = {}
            for _, name in ipairs(ignoredHandlers) do leaf[name] = {} end
            leaf["rules.gm.GMHandler"] = {}
            leaf["rules.redeem.RedeemService"] = {Init = noop}
            leaf["rules.offline.OfflineService"] = {HasPendingRewards = function() return false end,
                MarkOnline = function() bad("unexpected offline MarkOnline") end}
            leaf["core.PlayerStore"] = setmetatable({}, {__index = function(_, key)
                return bad("禁止PlayerStore代理 " .. tostring(key))
            end})
            leaf["systems.EquipmentSystem"] = {hydrateInventory = noop}
            leaf["systems.ExtraTalentSystem"] = {normalize = function(data) return data end}
            leaf["systems.LootBoxSystem"] = {consolidateSeeds = function(data)
                if #data.seeds ~= 0 then bad("non-target loot fixture") end
            end, revealLegacy = noop}
            leaf["systems.TalentEffect"] = {}
            leaf["core.I18n"] = {lookup = function(value) return value end, format = string.format,
                difficulty = function(value) return value end}
            leaf["core.DrawUtil"] = {drawTextStroke = noop, drawImageCentered = noop,
                seamSlideX = function() return 0 end}
            leaf["core.DarkIcon"] = {drawQualityBg = noop, draw = noop, drawIconDark = noop,
                QUALITY_TRIM = {{1,2,3},{1,2,3},{1,2,3},{1,2,3},{1,2,3},{1,2,3}}}
            leaf["ui.town.TownPageChrome"] = {OPEN_DUR = 0.3, CLOSE_DUR = 0.3,
                slideProgress = function() return 1 end, drawNamePlate = noop, drawBack = noop,
                hitBack = function() return false end}
            leaf["ui.story.task.ExpeditionTrackView"] = {draw = function(_, snapshot, layout)
                h.view = {snapshot = copy(snapshot), layout = copy(layout)}
            end}
            leaf["ui.widget.DesignWidgetSurface"] = {init = noop}
            leaf["ui.widget.ImageCache"] = {init = noop, getQualityBg = function() return 1 end,
                getEquipIcon = function() return 1 end}
            leaf["ui.widget.HeroFrame"] = {draw = noop}
            leaf["config.ArtifactAssetUtil"] = {drawIcon = noop}
            leaf["systems.GameSFX"] = {play = function(key) h.sfx[#h.sfx + 1] = key end}
            leaf["core.UiToast"] = {show = function(message)
                h.toasts[#h.toasts + 1] = message; note("toast", message)
            end}
            -- CMH.setup所有非目标页面显式注入；不能通过任意ui.*前缀自动放行。
            for _, name in ipairs({"ui.loot.LootBox", "ui.loot.LootBoxPage", "ui.blacksmith.BlacksmithPage",
                "ui.backpack.BackpackPanel", "ui.church.ChurchPage", "ui.church.talent.TalentPage",
                "ui.tavern.TavernPage", "ui.market.MarketPage", "ui.dungeon.DungeonPage",
                "ui.dungeon.DungeonBattleScene", "ui.dev.GMConsolePanel", "ui.hud.TopBar",
                "ui.character.panel.CharacterPanel", "ui.character.equip.EquipmentDetail",
                "ui.hud.popup.RedeemCodePanel", "systems.TutorialManager"}) do
                leaf[name] = {onActionResult = function()
                    h.leafCalls[#h.leafCalls + 1] = name
                end}
            end
            leaf["ui.battle.scene.BattleScene"] = {setBattleData = noop}
            local sources = copy(production)
            sources["runtime.GameAction"], sources["runtime.ClientMessageHandler"] = true, true
            sources["ui.story.task.TaskPage"], sources["config.ExpeditionProgress"] = true, true
            sources["ui.hud.popup.RewardPopup"], sources["ui.widget.RewardCascade"] = true, true
            sources["ui.widget.BattleRewardQueue"], sources["core.NumberUtil"] = true, true
            for name in pairs(configs) do sources[name] = true end
            for _, name in ipairs({"config.EquipmentConfig", "config.ScenarioDialogueConfig", "config.TavernConfig",
                "config.ClassConfig", "config.AdvancementConfig", "systems.AttributeDef", "systems.UnitAttributes",
                "config.StageConfig_Normal", "config.StageConfig_Hard", "config.StageConfig_Nightmare",
                "config.StageConfig_Hell", "config.StageConfig_Purgatory", "config.StageConfig_Torment",
                "config.StageConfig_Torment2", "config.StageConfig_Torment3", "config.StageConfig_Torment4",
                "config.StageConfig_Torment5", "config.StageConfig_Annihilation", "config.StageConfig_Annihilation2",
                "config.StageConfig_Annihilation3", "config.StageConfig_Annihilation4", "config.StageConfig_Annihilation5"}) do
                sources[name] = true
            end
            env.require = function(name)
                if leaf[name] then return leaf[name] end
                if h.loaded[name] then return h.loaded[name] end
                if not sources[name] then return bad("chain unexpected dependency " .. name) end
                local path = name:gsub("%.", "/") .. ".lua"
                local file = cache:GetFile(path) -- 仅从白名单资源读取完整源码，不走File存档接口。
                assert(file and file:IsOpen(), "missing full source " .. path)
                local lines = {}
                while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
                file:Dispose()
                local chunk, compileError = load(table.concat(lines, "\n"), "@" .. path, "t", env)
                assert(chunk, compileError)
                local value = chunk()
                h.loaded[name] = value
                return value
            end
            h.require = env.require
            h.State = env.require("core.GameState")
            h.Dispatcher = env.require("runtime.ClientDispatcher")
            h.Save = env.require("boot.StandaloneSave")
            if json then
                h.restored = h.Save.RestoreData() -- 与生产一致：恢复数据先于Bridge.init、CMH.setup及UI.init。
                note("restore_before_init", h.restored)
            end
            h.Bridge = env.require("runtime.LocalActionBridge")
            h.Tasks = env.require("rules.task.TaskService")
            h.Currency = env.require("rules.currency.CurrencyService")
            h.Page = env.require("ui.story.task.TaskPage")
            h.Popup = env.require("ui.hud.popup.RewardPopup")
            h.Msg = env.require("runtime.ClientMessageHandler")
            h.Action = env.require("runtime.GameAction")
            local realFlush = h.Save.Flush
            h.Save.Flush = function()
                note("flush_begin")
                local success = realFlush()
                note(success and "flush_ok" or "flush_failed", h.files[savePath])
                return success
            end
            local realGrant = h.Currency.GrantReward
            h.Currency.GrantReward = function(uid, reward)
                h.grants = h.grants + 1
                note("grant", copy(reward))
                return realGrant(uid, reward)
            end
            local realShow = h.Popup.show
            h.Popup.show = function(title, rewards, opts)
                local shown = {title = title, rewards = copy(rewards), opts = copy(opts),
                    json = h.files[savePath], traceIndex = #h.trace + 1}
                h.shows[#h.shows + 1] = shown
                note("show", shown)
                return realShow(title, rewards, opts) -- spy必须继续调用完整生产show。
            end
            local realHandle = h.Msg.handleActionResult
            h.Msg.handleActionResult = function(result)
                h.results[#h.results + 1] = {data = copy(result), traceIndex = #h.trace + 1}
                note("result", copy(result)) -- 先记录，再调用真实CMH（Bridge内部会pcall）。
                local handled, why = pcall(realHandle, result)
                if not handled then h.errors[#h.errors + 1] = "CMH: " .. tostring(why) end
                note("cmh_done", handled)
            end
            h.Msg.setup({sendAction = h.Action.sendAction, ui = {}})
            h.Bridge.init()
            h.Popup.init({})
            h.Page.init({})
            local numberUtil = env.require("core.NumberUtil")
            local realFormat = numberUtil.format
            numberUtil.format = function(amount)
                if h.drawing then h.amounts[#h.amounts + 1] = amount end
                return realFormat(amount)
            end
            h.baseline = copy(h.Dispatcher.get("currency"))
            return h
        end
        local function audit(h)
            eq(#h.errors, 0, "完整链路无被pcall吞掉的隔离/CMH异常 " .. table.concat(h.errors, ";"))
        end
        local function chainFixture(h, level, claimed)
            h.State.syncPlayerData({level = level, exp = 0}, {silent = true})
            local schema = h.require("shared.schemas.CharacterSchema")
            local currency = schema.Fields.currency.getDefault()
            schema.Fields.currency.onLoad(currency)
            currency.gold, currency.gems = 100, 20
            h.State.syncFromCurrency(currency, {silent = true})
            h.Dispatcher.set("currency", currency)
            local task = schema.Fields.task.getDefault()
            task.achClaimed = claimed or {}
            h.Dispatcher.set("task", task)
            h.Dispatcher.set("heroes", {roster = {}, deployed = {}})
            h.baseline = copy(currency)
            h.Tasks.RefreshAchievements(1)
            eq(h.Save.Flush(), true, "完整链路基线内存Flush")
            h.trace, h.results, h.shows, h.toasts = {}, {}, {}, {}
            h.writes, h.renames, h.grants = 0, 0, 0
        end
        local function openNode(h, level)
            h.Page.openExpedition()
            h.Page.draw({})
            local view = h.view
            eq(view.snapshot.level, level, "真实Page传真实模型等级")
            local layout = view.layout
            local y = layout.y + layout.rowH * 0.5 + (level - 1) * (layout.rowH + layout.gap) - layout.scrollY
            check(y >= layout.y and y <= layout.y + layout.h, "当前等级命中在真实列表内")
            return layout.x + layout.w * 0.5, y
        end
        local function receipt(h, count, title)
            audit(h)
            eq(#h.results, 1, "一次成功ActionResult")
            local result = h.results[1]
            eq(result.data.success, true, "真实CMH接收成功")
            eq(#result.data.rewards, count, "回包完整奖励项")
            eq(#h.shows, 1, "仅一次成功popup")
            local show = h.shows[1]
            eq(show.title, title or "功绩奖励", "真实CMH正确标题")
            same(show.rewards, result.data.rewards, "spy截获完整show参数")
            check(h.Popup.isOpen(), "真show确实打开Popup")
            eq(h.Popup.currentRowTag(), nil, "主动领奖不是战斗掉落")
            local saved = cjson.decode(show.json)
            local expected = copy(h.baseline)
            for _, reward in ipairs(show.rewards) do
                local key = h.Currency.REWARD_TO_CURRENCY[reward.type]
                expected[key] = (expected[key] or 0) + reward.amount
            end
            same(h.Dispatcher.get("currency"), expected, "show时完整余额与发奖一致")
            same(saved.modules.currency, expected, "show前完整余额已落盘")
            for key, value in pairs(expected) do
                if h.State.exportSave()[key] ~= nil then
                    same(h.State.exportSave()[key], value, "show时GameState " .. key)
                    same(saved.gameState[key], value, "show前GameState落盘 " .. key)
                end
            end
            for _, id in ipairs(result.data.claimed) do
                eq(saved.modules.task.achClaimed[id], true, "show前该项已落盘 " .. id)
            end
            local flushIndex, renameIndex = 0, 0
            for index, event in ipairs(h.trace) do
                if event.kind == "flush_ok" then flushIndex = index end
                if event.kind == "rename_ok" then renameIndex = index end
            end
            check(renameIndex > 0 and renameIndex < flushIndex and flushIndex < result.traceIndex
                and result.traceIndex < show.traceIndex, "Rename→Flush成功→先记录Result→真实CMH→真show顺序")
            eq(#h.toasts, 0, "成功无失败Toast")
        end
        local function popupState(h)
            -- 只读完整drawContent的upvalue；不提取函数、不写upvalue、不添加生产API。
            for index = 1, 100 do
                local name, value = debug.getupvalue(h.Popup.drawContent, index)
                if not name then break end
                if name == "state" then return value end
            end
            error("完整Popup必须暴露drawContent内部state供只读验收")
        end
        local function drawPopup(h)
            h.amounts, h.texts = {}, {}
            h.drawing = true
            h.Popup.draw({})
            h.drawing = false
            audit(h)
            return h.amounts
        end
        runCase("真实Page同节点连续2/3次经GameAction持久化后CMH及Popup一次", function()
            for _, clicks in ipairs({2, 3}) do
                local h = newChain()
                chainFixture(h, 100)
                local x, y = openNode(h, 100)
                for _ = 1, clicks do eq(h.Page.handleInput(x, y), true, "设计坐标同节点连点消费") end
                receipt(h, 2)
                eq(h.grants, 2, "旧礼包与bonus各发一次")
                eq(h.writes, 1, "连点只有一批写入")
                eq(h.renames, 1, "连点只有一次替换")
                eq(h.State.getGems(), 960, "Lv100旧840加bonus100共940")
                eq(h.Dispatcher.get("task").achClaimed.a_plv_100, true, "旧礼包独立账本")
                eq(h.Dispatcher.get("task").achClaimed[bonusId(100)], true, "bonus独立账本")
                local items = popupState(h).items
                eq(#items, 2, "真Popup保存同级两项未聚合")
                eq(items[1].amount + items[2].amount, 940, "真Popup同级940可观察")
                h.clock.elapsedTime = h.clock.elapsedTime + 0.4; h.Popup.update(0.4)
                local shown = drawPopup(h)
                eq(#shown, 2, "真实draw实际走两项数量角标")
                eq(shown[1] + shown[2], 940, "真实draw同级数量940")
                h.clock.elapsedTime = h.clock.elapsedTime + 10; h.Popup.update(10)
                check(h.Popup.isOpen(), "非战斗主动领奖超过3秒仍打开")
                eq(popupState(h).animPhase, "open", "非战斗不开始自动关闭")
                eq(h.Page.getExpeditionClaimableCount(), 99, "只领取当前节点，不误领旧等级")
                audit(h)
            end
        end)
        runCase("真实Page200级整页209项20840黑晶单popup42行滚到末端", function()
            local h = newChain()
            chainFixture(h, 200)
            openNode(h, 200)
            for _ = 1, 3 do eq(h.Page.handleInput(860, 300), true, "真实Page整页连点") end
            receipt(h, 209)
            eq(h.grants, 209, "整页每项一次真实GrantReward")
            eq(h.writes, 1, "整页209项一次写入")
            eq(h.renames, 1, "整页一次Rename")
            eq(h.State.getGems(), 20860, "真实全页20840增量")
            eq(h.Page.getExpeditionClaimableCount(), 0, "全页模型已全部领取")
            local state = popupState(h)
            eq(#state.items, 209, "真Popup包含209不是聚合资源数")
            eq(math.ceil(#state.items / 5), 42, "真Popup42行")
            eq(state.scrollMax, 7200, "真布局42行可滚7200设计单位")
            local gems = 0
            for index, item in ipairs(state.items) do
                same(item, h.shows[1].rewards[index], "真Popup完整同序项 " .. index)
                if item.type == "diamond" then gems = gems + item.amount end
            end
            eq(gems, 20840, "真Popup完整20840不是余额")
            h.clock.elapsedTime = h.clock.elapsedTime + 0.5; h.Popup.update(0.5)
            eq(state.scrollY, state.scrollMax, "真实autoScroll半秒到末端")
            h.Popup.handleScroll(1000)
            eq(state.scrollY, 0, "真实滚轮回顶并取消自动滚动")
            eq(state.autoScroll, nil, "手动滚动取消autoScroll")
            local visibleCount = 0
            -- 每次窗口移动两行，累计验收全部209数量角标（图形叶子spy，不宣称GPU像素）。
            for start = 1, 201, 10 do
                if start > 1 then h.Popup.handleScroll(-6) end
                local amounts = drawPopup(h)
                -- draw也包含贴边零面积的邻行，按只读state确定当前可见网格。
                local expected = {}
                for index, item in ipairs(state.items) do
                    local row = math.ceil(index / 5)
                    local cy = 918 + (row - 1) * 180 - state.scrollY
                    if cy + 80 >= 838 and cy - 80 <= 1178 then expected[#expected + 1] = item.amount end
                end
                same(amounts, expected, "真实draw窗口按scrollY裁剪数量 " .. start)
                local last = math.min(209, start + 9)
                for index = start, last do
                    local row = math.ceil(index / 5)
                    local cy = 918 + (row - 1) * 180 - state.scrollY
                    check(cy >= 838 and cy <= 1178, "第" .. index .. "项中心确实滚入窗口")
                    visibleCount = visibleCount + 1
                end
            end
            eq(visibleCount, 209, "完整遍历所有209项而非仅末两行")
            eq(state.scrollY, 7200, "滚轮末端精确钳制")
            local tail = drawPopup(h)
            eq(tail[#tail], state.items[209].amount, "真实draw末项209数量角标")
            h.clock.elapsedTime = h.clock.elapsedTime + 10; h.Popup.update(10)
            check(h.Popup.isOpen(), "全页主动领奖也不3秒自动关")
            eq(#h.shows, 1, "滚动及update不新增popup")
            audit(h)
        end)
        runCase("真实clear Page单领经CMH data.reward分支及真任务奖励Popup", function()
            local h = newChain()
            chainFixture(h, 5)
            local config = h.require("config.TaskConfig")
            local def
            for _, task in ipairs(config.ACHIEVEMENT) do
                if task.difficulty == "normal" then def = task; break end
            end
            assert(def and def.stageId, "必须找到真实通关任务")
            h.Dispatcher.set("battle", {maxStageId = def.stageId, currentStageId = def.stageId,
                clearedStages = {[tostring(def.stageId)] = true}})
            h.Tasks.RefreshAchievements(1)
            eq(h.Save.Flush(), true, "通关fixture真实保存")
            h.baseline = copy(h.Dispatcher.get("currency"))
            h.trace, h.results, h.shows, h.toasts = {}, {}, {}, {}
            h.writes, h.renames, h.grants = 0, 0, 0
            h.Page.open("clear")
            for _ = 1, 3 do eq(h.Page.handleInput(900, 570), true, "真实clear首行连续点击") end
            audit(h)
            eq(#h.results, 1, "单领仅一次回执")
            local result = h.results[1].data
            eq(result.action, Protocol.ACTION_TYPES.CLAIM_TASK, "真实Page路由单领Action")
            eq(result.success, true, "真实单领成功")
            same(result.reward, def.reward, "真实单领reward回包")
            eq(result.rewards, nil, "不拿批领分支代替单领")
            eq(#h.shows, 1, "CMH单领一次show")
            eq(h.shows[1].title, "任务奖励", "完整CMH单领标题")
            same(h.shows[1].rewards, {{type = def.reward.type, amount = def.reward.amount}}, "单领show参数")
            local showIndex = h.shows[1].traceIndex
            eq(h.trace[showIndex - 1].kind, "result", "单领先记录回执再CMH show")
            local commitIndex = 0
            for index, event in ipairs(h.trace) do if event.kind == "flush_ok" then commitIndex = index end end
            check(commitIndex > 0 and commitIndex < h.results[1].traceIndex, "单领Flush成功前不show")
            eq(h.grants, 1, "单领一次发奖")
            eq(h.writes, 1, "单领一次写入")
            eq(h.renames, 1, "单领一次Rename")
            eq(#h.toasts, 0, "单领成功不Toast")
            local key = h.Currency.REWARD_TO_CURRENCY[def.reward.type]
            eq(h.Dispatcher.get("currency")[key], h.baseline[key] + def.reward.amount, "单领余额真实累计")
            local saved = cjson.decode(h.shows[1].json)
            eq(saved.modules.task.achClaimed[def.id], true, "单领show前已记永久账本")
            eq(saved.modules.currency[key], h.Dispatcher.get("currency")[key], "单领show前余额落档")
            eq(#popupState(h).items, 1, "真单领Popup一项")
            h.clock.elapsedTime = h.clock.elapsedTime + 0.4; h.Popup.update(0.4)
            same(drawPopup(h), {def.reward.amount}, "真实单领draw数量")
            audit(h)
        end)
        runCase("rename失败保留已打开成功Popup与余额台账而不重开", function()
            local h = newChain()
            chainFixture(h, 100)
            local x, y = openNode(h, 100)
            eq(h.Page.handleInput(x, y), true, "先成功领取当前节点")
            receipt(h, 2)
            h.Page.draw({})
            local layout = h.view.layout
            local previousY = layout.y + layout.rowH * 0.5 + 98 * (layout.rowH + layout.gap) - layout.scrollY
            local state = popupState(h)
            local oldItems, oldPhase = copy(state.items), state.animPhase
            local oldJSON = h.files[savePath]
            local currency, ledger = copy(h.Dispatcher.get("currency")), copy(h.Dispatcher.get("task").achClaimed)
            h.fail = "rename"
            eq(h.Page.handleInput(x, previousY), true, "旧节点rename失败")
            audit(h)
            eq(#h.results, 2, "成功后失败回执仍完整")
            eq(h.results[2].data.reason, "save_failed", "后一次明确保存失败")
            eq(#h.shows, 1, "失败不得新开成功popup")
            eq(#h.toasts, 1, "失败一次Toast")
            check(h.Popup.isOpen(), "失败不改变已有成功Popup打开状态")
            same(state.items, oldItems, "失败不替换已有成功Popup内容")
            eq(state.animPhase, oldPhase, "失败不重启已有成功Popup动画")
            eq(h.files[savePath], oldJSON, "失败旧JSON保持")
            same(h.Dispatcher.get("currency"), currency, "已有成功余额不增减")
            same(h.Dispatcher.get("task").achClaimed, ledger, "已有成功台账保持")
            eq(h.State.getGems(), 960, "成功940不被失败领奖影响")
            audit(h)
        end)
        runCase("rename失败真实Toast无新popup，冷重建JSON恢复未领重试及再次冷恢复防重", function()
            local h = newChain()
            chainFixture(h, 100, {a_retired_task = true, [bonusId(33)] = true})
            local x, y = openNode(h, 100)
            local oldJSON = h.files[savePath]
            local balance = copy(h.Dispatcher.get("currency"))
            local ledger = copy(h.Dispatcher.get("task").achClaimed)
            h.fail = "rename"
            eq(h.Page.handleInput(x, y), true, "真实Page失败请求")
            audit(h)
            eq(#h.results, 1, "失败仍有ActionResult")
            eq(h.results[1].data.success, false, "rename失败结果")
            eq(h.results[1].data.reason, "save_failed", "真实失败原因")
            eq(#h.toasts, 1, "真实CMH失败Toast一次")
            eq(h.toasts[1], "存档失败，奖励未领取，请重试", "真实Toast准确失败信息")
            eq(#h.shows, 0, "失败不调用成功show")
            check(not h.Popup.isOpen(), "失败不打开成功Popup")
            eq(h.files[savePath], oldJSON, "失败旧JSON字节不变")
            eq(h.files[pendingPath], nil, "失败清理pending")
            same(h.Dispatcher.get("currency"), balance, "失败余额回滚")
            same(h.Dispatcher.get("task").achClaimed, ledger, "失败领取账本回滚")
            eq(h.State.getGems(), 20, "失败GameState余额不变")
            local cold = newChain(oldJSON) -- 唯一迁移值是JSON，全部模块与闭包从完整源码新建。
            for _, name in ipairs({"core.GameState", "runtime.ClientDispatcher", "rules.character.PlayerDataManager",
                "runtime.LocalActionBridge", "rules.task.TaskService", "rules.currency.CurrencyService",
                "runtime.ClientMessageHandler", "ui.hud.popup.RewardPopup", "ui.story.task.TaskPage"}) do
                check(cold.loaded[name] ~= h.loaded[name], "冷重建模块身份不同 " .. name)
            end
            eq(cold.restored, true, "新实例初始化前从内存JSON恢复")
            eq(cold.trace[1].kind, "restore_before_init", "JSON恢复先于初始化及领奖")
            same(cold.Dispatcher.get("currency"), balance, "冷恢复失败前余额")
            same(cold.Dispatcher.get("task").achClaimed, ledger, "冷恢复失败项仍未领")
            local cx, cy = openNode(cold, 100)
            eq(cold.view.snapshot.rows[100].status, Config.STATUS.CLAIMABLE, "冷恢复真实模型仍可领")
            for _ = 1, 3 do eq(cold.Page.handleInput(cx, cy), true, "冷恢复重试连点") end
            receipt(cold, 2)
            eq(cold.writes, 1, "冷恢复重试只写一次")
            eq(cold.grants, 2, "重试同级各发一次")
            eq(cold.State.getGems(), 960, "恢复重试只增940")
            local finalJSON = cold.files[savePath]
            local again = newChain(finalJSON)
            eq(again.restored, true, "再冷建初始化前Restore成功")
            local ax, ay = openNode(again, 100)
            for _ = 1, 3 do eq(again.Page.handleInput(ax, ay), true, "成功后冷恢复同节点重复") end
            eq(again.Save.RestoreData(), true, "同新实例再次Restore仍防重")
            eq(again.Page.handleInput(ax, ay), true, "再次Restore重复不发")
            eq(again.grants, 0, "两种Restore重复没有发奖")
            eq(again.writes, 0, "两种Restore重复没有落盘")
            eq(#again.shows, 0, "两种Restore重复没有成功popup")
            eq(again.State.getGems(), 960, "冷重建余额940仅一次")
            eq(again.files[savePath], finalJSON, "冷恢复重复不改JSON")
            -- 强制重复Action也验真实CMH失败：Page自己的状态守卫未发请求不能代替后端幂等。
            eq(again.Action.sendAction(Protocol.ACTION_TYPES.CLAIM_ALL_TASKS, {scope = "level", level = 100}), true,
                "真实GameAction重复请求")
            eq(again.results[1].data.reason, "nothing_to_claim", "后端重复明确拒绝")
            eq(#again.toasts, 1, "后端重复真实Toast")
            eq(#again.shows, 0, "后端重复也不新开成功Popup")
            eq(again.grants, 0, "后端拒绝不发奖")
            eq(again.writes, 0, "后端拒绝不写档")
            audit(again)
        end)
    end)
    _G.require, _G.File, _G.fileSystem, os.time = originalRequire, originalFile, originalSystem, originalTime
    if ok then
        print("[expedition_rewards_test] ALL PASS cases=" .. cases .. " assertions=" .. assertions .. " (memory File only)")
    else
        print("[expedition_rewards_test] FAIL " .. tostring(err))
    end
    engine:Exit()
end
