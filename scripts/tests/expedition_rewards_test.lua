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
        if configs[name] or name:match("^shared%.") or name:match("^config%.") then
            local value = originalRequire(name)
            loaded[name] = value
            return value
        end
        if name:match("^rules%..+Handler$") then return {} end
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
        local levelTasks = {}
        for _, task in ipairs(Config.ACHIEVEMENT) do
            if task.group == "level" then levelTasks[#levelTasks + 1] = task end
        end
        eq(#levelTasks, 9, "保留全部九个现有远征奖励")
        local originalRewards = {}
        for _, task in ipairs(levelTasks) do originalRewards[task.id] = copy(task.reward) end
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
            local currency = require("shared.schemas.CharacterSchema").Fields.currency.getDefault()
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
        local function all()
            eq(Bridge.dispatch(Protocol.ACTION_TYPES.CLAIM_ALL_TASKS, { scope = "level" }), true, "已路由一键请求")
            return lastResult()
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
                eq(rewardNotices, 0, mode .. "失败无领奖通知")
                failure = ""
                Save.Update(3) -- 自动重试写档只能写回滚后的旧奖励台账
                check(not cjson.decode(memory[savePath]).modules.task.achClaimed[levelTasks[1].id], "重试不能静默记失败领取")
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
            local before = writeCount
            local result = all()
            eq(result.success, true, "一键成功")
            eq(#result.claimed, 8, "跳过旧已领只发八项")
            eq(#result.rewards, 8, "所有奖励完整回包")
            eq(writeCount, before + 1, "全页一次写档")
            local saved = cjson.decode(memory[savePath])
            for key, value in pairs(expected) do
                same(saved.modules.currency[key], value, "保留累计模块奖励 " .. key)
                if State.exportSave()[key] ~= nil then eq(saved.gameState[key], value, "完整GameState奖励 " .. key) end
            end
            for _, task in ipairs(levelTasks) do eq(saved.modules.task.achClaimed[task.id], true, "持久账本 " .. task.id) end
            eq(saved.modules.task.achClaimed.a_legacy_history, true, "未识别历史也保留")
            eq(all().reason, "nothing_to_claim", "全部已领后一键不重复")
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
            flushBaseline()
            before = #ups
            eq(Save.RestoreData(), true, "新格式再次往返")
            eq(#ups, before, "再次恢复无重复庆祝")
            eq(Dispatcher.get("task").achClaimed.a_retired_task, true, "往返历史不丢")
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
    end)
    _G.require, _G.File, _G.fileSystem, os.time = originalRequire, originalFile, originalSystem, originalTime
    if ok then
        print("[expedition_rewards_test] ALL PASS cases=" .. cases .. " assertions=" .. assertions .. " (memory File only)")
    else
        print("[expedition_rewards_test] FAIL " .. tostring(err))
    end
    engine:Exit()
end
