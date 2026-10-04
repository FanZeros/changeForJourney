-- T03 三队当前关持久化回归：真实 Schema/Save/同步代码，File 仅使用内存替身。
-- Runtime: tests/team_stage_persistence_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
function Start()
    local originalRequire, originalFile, originalSystem = _G.require, File, fileSystem
    local assertions, passed, failed = 0, 0, 0
    local function eq(actual, expected, label)
        assertions = assertions + 1
        assert(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
    end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for key, item in pairs(value) do out[key] = copy(item) end
        return out
    end
    local function runCase(label, fn)
        local ok, err = pcall(fn)
        if ok then
            passed = passed + 1
            print("[team_stage_persistence_test] PASS " .. label)
        else
            failed = failed + 1
            print("[team_stage_persistence_test] FAIL " .. label .. " " .. tostring(err))
        end
    end
    local function sourceText(path)
        local source = cache:GetFile(path)
        assert(source and source:IsOpen(), "missing source " .. path)
        local lines = {}
        while not source:IsEof() do lines[#lines + 1] = source:ReadLine() end
        source:Dispose()
        return table.concat(lines, "\n")
    end
    local stage = originalRequire("config.StageConfig")
    local schema = originalRequire("shared.battle.BattleSchema")
    local field = schema.Fields.battle
    ---@type table<string, any>
    local modules, mocks, loaded = {}, {}, {}
    ---@type table<string, string>
    local memory = {}
    local savePath, pendingPath = "standalone_save.json", "standalone_save.pending.json"
    local failure = ""
    local notifications = 0
    local liveStages = nil ---@type table|nil
    local appliedStages = nil ---@type table|nil
    local mainStage, mainMax = 101, 101
    local mainCleared = {}
    local mainApplied = nil ---@type table|nil
    local function allowed(path)
        assert(path == savePath or path == pendingPath, "禁止访问真实文件 " .. tostring(path))
    end
    _G.File = function(path, mode)
        allowed(path)
        local open = true
        return {
            IsOpen = function() return open end,
            Close = function() open = false end,
            ReadString = function() return memory[path] or "" end,
            WriteString = function(_, text)
                eq(path, pendingPath, "不得直接截断玩家旧档")
                if failure == "write" then memory[path] = text:sub(1, 9); return false end
                memory[path] = text
                return true
            end,
        }
    end
    _G.fileSystem = {
        FileExists = function(_, path) allowed(path); return memory[path] ~= nil end,
        Delete = function(_, path) allowed(path); memory[path] = nil; return true end,
        Rename = function(_, src, dest)
            allowed(src); allowed(dest)
            if failure == "rename" then return false end
            memory[dest], memory[src] = memory[src], nil
            return true
        end,
    }
    local dispatcher = {
        get = function(name) return modules[name] end,
        snapshotAll = function() return modules end,
        notifySubscribers = function() notifications = notifications + 1 end,
        handleStateUpdate = function(json)
            for name, data in pairs(cjson.decode(json).modules) do
                if name == "battle" then field.onLoad(data) end
                modules[name] = data
            end
        end,
    }
    local scene = {
        setBattleData = function(data) mainApplied = copy(data); mainStage = data.currentStageId end,
        getStageId = function() return mainStage end,
        getMaxStageId = function() return mainMax end,
        getClearedStages = function() return mainCleared end,
    }
    local page = {
        getTeamStageIds = function() return liveStages end,
        setTeamStageIds = function(ids) appliedStages = copy(ids) end,
    }
    mocks["runtime.ClientDispatcher"] = dispatcher
    mocks["core.GameState"] = {
        exportSave = function() return {} end, importSave = function() end,
        syncPlayerData = function() end,
    }
    mocks["ui.battle.scene.BattleScene"] = scene
    mocks["ui.battle.tri.BattleTriPage"] = page
    mocks["rules.offline.OfflineService"] = {
        HasPendingRewards = function() return false end, MarkOnline = function() end,
    }
    local function isolatedRequire(name)
        if mocks[name] then return mocks[name] end
        if loaded[name] then return loaded[name] end
        if name == "boot.StandaloneSave" then
            local path = name:gsub("%.", "/") .. ".lua"
            local chunk, err = load(sourceText(path), "@" .. path, "t", _G)
            assert(chunk, err)
            loaded[name] = chunk()
            return loaded[name]
        end
        return originalRequire(name)
    end
    _G.require = isolatedRequire
    local ok, err = pcall(function()
        local save = isolatedRequire("boot.StandaloneSave")
        if save.SetBattlePage then save.SetBattlePage(page) end
        -- 只读生产同步函数块，避免启动真实场景/标题/资源；并非重写一份同步逻辑。
        local standaloneSource = sourceText("boot/Standalone.lua")
        local syncSource = standaloneSource:match("(local battleSync =.-)\nlocal physW")
        assert(syncSource, "未找到生产 SyncBattleState 边界")
        local syncEnv = setmetatable({ BattleScene = scene, BattleTriPage = page,
            ClientDispatcher = dispatcher, StandaloneSave = save, BattleSchema = schema,
        }, { __index = _G })
        local syncChunk, syncErr = load(syncSource .. "\nreturn SyncBattleState", "@boot/Standalone.lua#SyncBattleState", "t", syncEnv)
        assert(syncChunk, syncErr)
        local sync = syncChunk() --[[@as fun(dt: number)]]
        local function stages(data, a, b, c, label)
            eq(type(data.teamCurrentStageIds), "table", label .. "三队数组")
            eq(data.teamCurrentStageIds[1], a, label .. "队1")
            eq(data.teamCurrentStageIds[2], b, label .. "队2")
            eq(data.teamCurrentStageIds[3], c, label .. "队3")
            eq(data.currentStageId, a, label .. "队1旧字段镜像")
        end
        local function normalize(data)
            field.onLoad(data)
            return data
        end
        local function fixture()
            failure = ""
            modules = { player = {}, session = {}, heroes = {
                deployed = { 1, 0, 0, 0 }, roster = { [1] = { level = 1 } },
                teams = { { slots = { 1, 0, 0, 0 } }, { slots = {} }, { slots = { 0, 0, 0, 0 } } },
            }, battle = { currentStageId = 2001, maxStageId = 2305,
                teamCurrentStageIds = { 2001, 1701, 1901 }, clearedStages = { ["905"] = true, ["1905"] = true },
                battleMode = "idle", idleAccumSec = 18 } }
            mainStage, mainMax = 2001, 2305
            mainCleared = { [905] = true, [1905] = true }
            liveStages, appliedStages, mainApplied = nil, nil, nil
        end
        local function disk() return cjson.decode(memory[savePath]) end
        runCase("新档默认独立三队与旧字段镜像", function()
            stages(field.getDefault(), 101, 101, 101, "default")
            local a, b = field.getDefault(), field.getDefault()
            a.teamCurrentStageIds[2] = 201
            eq(b.teamCurrentStageIds[2], 101, "默认数组不得跨玩家共享")
        end)
        runCase("旧档保留队一旧关不抬到共享max", function()
            local old = normalize({ currentStageId = "1001", maxStageId = "2305", clearedStages = { ["905"] = true, ["1905"] = true } })
            stages(old, 1001, 101, 101, "legacy")
            eq(old.maxStageId, "2305", "共享max值/类型不改")
            eq(old.clearedStages["905"], true, "共享首通保留")
            stages(normalize({ currentStage = 9, maxStage = 20 }), 101, 101, 101, "更旧字段迁移")
        end)
        runCase("JSON数组和数字字符串队键均可迁移", function()
            for _, ids in ipairs({ { 1001, 1501, 1901 }, { ["1"] = "1001", ["2"] = "1501", ["3"] = "1901" } }) do
                local data = normalize(cjson.decode(cjson.encode({ currentStageId = 2001, maxStageId = 2305, teamCurrentStageIds = ids })))
                stages(data, 1001, 1501, 1901, "json")
                eq(data.teamCurrentStageIds["1"], nil, "规范化只保留数字索引")
                eq(data.maxStageId, 2305, "三队选择不更改共享max")
            end
        end)
        runCase("非法关卡/越权新关/锁队污染安全回退", function()
            local data = normalize({ currentStageId = 501, maxStageId = 905,
                teamCurrentStageIds = { 1000000, 801, 701 }, clearedStages = {} })
            stages(data, 501, 101, 101, "锁队")
            data = normalize({ currentStageId = 501, maxStageId = 2001,
                teamCurrentStageIds = { false, 201.5, 2305 }, clearedStages = {} })
            stages(data, 501, 101, 101, "非法")
            eq(data.maxStageId, 2001, "拒绝新关不提升共享进度")
            data = normalize({ currentStageId = 101, maxStageId = 999,
                teamCurrentStageIds = { 2305, 2001, 2401 } })
            stages(data, 2305, 2001, 101, "终焉max按关链顺序")
            eq(data.maxStageId, 999, "终焉max本值保留")
        end)
        runCase("14座终焉三队读档一致回退且不伪造首通", function()
            for _, entry in ipairs(stage.STAGES) do
                if stage.isTerminalTemple(entry.id) then
                    local previous = stage.getTerminalPrevStageId(entry.id)
                    local data = normalize({ currentStageId = entry.id, maxStageId = previous,
                        teamCurrentStageIds = { entry.id, tostring(entry.id), entry.id },
                        clearedStages = { [tostring(previous)] = true } })
                    local unlocked = originalRequire("config.ExpTable").getUnlockedTeamCount(data)
                    stages(data, previous, unlocked >= 2 and previous or 101, unlocked >= 3 and previous or 101, "terminal " .. entry.id)
                    eq(data.maxStageId, previous, "终焉回退不改共享max")
                    eq(data.clearedStages[tostring(entry.id)], nil, "未通终焉不能标首通")
                end
            end
            local crossed = normalize({ currentStageId = 1001, maxStageId = 2401 })
            eq(crossed.clearedStages["999"], true, "既有跨难度终焉补标规则仍有效")
        end)
        runCase("锁队解锁边界沿用首通而非刚抵达", function()
            stages(normalize({ currentStageId = 501, maxStageId = 905, teamCurrentStageIds = { 501, 801, 901 } }), 501, 101, 101, "905未通")
            stages(normalize({ currentStageId = 501, maxStageId = 905, clearedStages = { [905] = true }, teamCurrentStageIds = { 501, 801, 901 } }), 501, 801, 101, "905已通")
            stages(normalize({ currentStageId = 501, maxStageId = 1905, clearedStages = { ["1905"] = true }, teamCurrentStageIds = { 501, 801, 1901 } }), 501, 801, 1901, "1905已通")
        end)
        runCase("Flush捕获新选择，JSON恢复空队仍保留合法关", function()
            fixture()
            liveStages = { 1001, 1501, 1901 }
            eq(save.Flush(), true, "真实内存Flush")
            stages(disk().modules.battle, 1001, 1501, 1901, "退出即时采集")
            stages(modules.battle, 2001, 1701, 1901, "快照不得污染实时数据")
            liveStages = nil
            modules = {}
            eq(save.RestoreData(), true, "新进程恢复数据")
            save.ApplyBattleProgress()
            stages(modules.battle, 1001, 1501, 1901, "恢复数据")
            assert(mainApplied and appliedStages, "恢复必须同时回灌Scene/Page")
            eq(mainApplied.currentStageId, 1001, "队一Scene恢复旧关")
            eq(appliedStages[2], 1501, "Page队二恢复空队合法关")
            eq(appliedStages[3], 1901, "Page队三恢复全0空队合法关")
            eq(#modules.heroes.teams[2].slots, 0, "空队不得复制队一英雄")
            eq(modules.battle.maxStageId, 2305, "共享max未变")
            eq(modules.battle.clearedStages["1905"], true, "共享首通未变")
        end)
        runCase("未初始化live不会用101覆盖存档", function()
            fixture()
            eq(save.Flush(), true, "启动时无live也可落盘")
            stages(disk().modules.battle, 2001, 1701, 1901, "无live")
            eq(save.RestoreData(), true, "重复恢复")
            eq(appliedStages, nil, "RestoreData纯数据阶段不得启动Page")
        end)
        runCase("恢复时终焉回退/实时快照不回退", function()
            fixture()
            modules.battle.currentStageId = 999
            modules.battle.maxStageId = 2305
            modules.battle.clearedStages["2305"] = true
            modules.battle.teamCurrentStageIds = { 999, 999, 999 }
            liveStages = { 999, 999, 999 }
            eq(save.Flush(), true, "进行中终焉保存")
            stages(disk().modules.battle, 999, 999, 999, "实时终焉")
            liveStages = nil
            eq(save.RestoreData(), true, "终焉恢复")
            save.ApplyBattleProgress()
            stages(modules.battle, 2305, 2305, 2305, "终焉读档回退")
            assert(appliedStages, "终焉回退必须回灌Page")
            eq(appliedStages[3], 2305, "Page不重启终焉")
        end)
        runCase("半迁移/混合键/JSON空值及重复加载幂等", function()
            local data = normalize(cjson.decode('{"currentStageId":"1001","maxStageId":2305,"teamCurrentStageIds":{"1":null,"2":"1501","3":false,"4":2305}}'))
            stages(data, 1001, 1501, 101, "半迁移")
            eq(data.teamCurrentStageIds[4], nil, "拒绝额外队号")
            local before = cjson.encode(data)
            normalize(data)
            eq(cjson.encode(data), before, "重复onLoad不改数据")
            data = normalize({ currentStageId = 2001, maxStageId = 2305,
                teamCurrentStageIds = { [1] = 1001, ["1"] = "1501", [2] = 201.5, ["2"] = "1801" } })
            stages(data, 1001, 1801, 101, "混合键合法数字优先")
        end)
        runCase("分帧启动完成前禁止默认进度抢写", function()
            fixture()
            liveStages = { 101, 101, 101 }
            syncEnv.bootQueue_ = { {}, {} }
            syncEnv.bootIdx_ = 1
            sync(2)
            stages(modules.battle, 2001, 1701, 1901, "未回灌")
            syncEnv.bootQueue_ = nil
            liveStages = { 2001, 1701, 1901 }
        end)
        runCase("1秒同步仅切旧关也更新三队，max/cleared不变", function()
            fixture()
            liveStages = { 2001, 1701, 1901 }
            sync(1)
            liveStages = { 1001, 1601, 1801 }
            mainStage = 1001
            sync(1)
            stages(modules.battle, 1001, 1601, 1801, "手选旧关")
            eq(modules.battle.maxStageId, 2305, "旧关同步不降低共享max")
            eq(modules.battle.clearedStages["905"], true, "旧关同步不清首通")
            eq(appliedStages, nil, "周期采集不把旧存档回灌Page")
            liveStages[2] = 1602
            sync(1)
            eq(modules.battle.teamCurrentStageIds[2], 1602, "仅队二自动推进也检测")
        end)
        runCase("副本缺席live、终焉同步与写失败均不串队", function()
            fixture()
            sync(1)
            liveStages = { 999, 999, 999 }
            mainStage = 999
            mainCleared[2305] = true
            sync(1)
            stages(modules.battle, 999, 999, 999, "实时同步终焉")
            fixture()
            liveStages = { 1001, 1501, 1901 }
            eq(save.Flush(), true, "建立旧档")
            local before = memory[savePath]
            liveStages = { 1002, 1502, 1902 }
            failure = "rename"
            eq(save.Flush(), false, "替换失败有真实失败结果")
            eq(memory[savePath], before, "写失败保留玩家旧档")
            failure = ""
            eq(save.Flush(), true, "可重试新选择")
            stages(disk().modules.battle, 1002, 1502, 1902, "重试")
        end)
    end)
    _G.require, _G.File, _G.fileSystem = originalRequire, originalFile, originalSystem
    if not ok then
        failed = failed + 1
        print("[team_stage_persistence_test] FAIL harness " .. tostring(err))
    end
    print("[team_stage_persistence_test] RESULT passed=" .. passed .. " failed=" .. failed .. " assertions=" .. assertions .. " (memory File; Page restore spy)")
    if failed == 0 then
        print("[team_stage_persistence_test] ALL PASS")
    else
        log:Write(LOG_ERROR, "[team_stage_persistence_test] " .. failed .. " cases failed")
    end
    engine:Exit()
end
