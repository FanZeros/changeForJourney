-- 三队存档兼容与正式清档入口回归：所有 File/文件系统操作仅落内存。
-- 使用真实 Schema/Dispatcher/GameState/Save/OfflineService；只隔离 UI、装备生成与落盘。
local TAG = "[team_save_reset]"
local assertions, failures, cases, harnessErrors = 0, 0, 0, 0
local function check(value, label)
    assertions = assertions + 1
    if not value then failures = failures + 1 end
    print(TAG .. (value and " PASS " or " FAIL ") .. label)
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function runCase(label, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if not ok then
        harnessErrors = harnessErrors + 1
        check(false, label .. " 异常: " .. tostring(err))
    end
end
local function source(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"))
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end

function Start()
    local ok, err = pcall(function()
        local nativeRequire = require
        local SC = nativeRequire("config.StageConfig")
        local ET = nativeRequire("config.ExpTable")
        local Schema = nativeRequire("shared.battle.BattleSchema")
        local Registry = nativeRequire("shared.ModuleRegistry")
        local CharacterSchema = nativeRequire("shared.schemas.CharacterSchema")
        local resetSource = assert(source("boot.Standalone"):match(
            "(function Standalone%.requestResetToStartScreen%(%).-\nend)\n\n%-%- ====="), "缺少正式清档入口")
        local function noop() end
        local function stub(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local function fixture()
            local env = setmetatable({}, { __index = _G })
            env._G = env
            env.os = { time = function() return 200000 end, date = os.date, clock = os.clock }
            local modules = {
                ["config.StageConfig"] = SC, ["config.ExpTable"] = ET,
                ["config.GameConfig"] = nativeRequire("config.GameConfig"),
                ["config.GameEvents"] = nativeRequire("config.GameEvents"),
                ["shared.Protocol"] = nativeRequire("shared.Protocol"),
                ["shared.ModuleRegistry"] = Registry,
                ["shared.schemas.CharacterSchema"] = CharacterSchema,
                ["shared.battle.BattleSchema"] = Schema,
                ["core.EventBus"] = { emit = noop },
                ["systems.OfflineCalc"] = nativeRequire("systems.OfflineCalc"),
                ["shared.StageProvider"] = { Get = function() return SC end },
                ["config.HeroConfig"] = nativeRequire("config.HeroConfig"),
                ["systems.LootBoxSystem"] = stub(),
                ["config.BlacksmithConfig"] = nativeRequire("config.BlacksmithConfig"),
                ["systems.EquipmentSystem"] = stub({ generateRandom = function(level, quality)
                    return { level = level, quality = quality, templateId = 1, slot = "weapon" }
                end }),
                ["rules.currency.CurrencyService"] = stub(), ["rules.hero.HeroService"] = stub(),
            }
            local real = { ["core.GameState"] = true, ["runtime.ClientDispatcher"] = true,
                ["boot.StandaloneSave"] = true, ["rules.offline.OfflineService"] = true }
            env.require = function(name)
                if modules[name] then return modules[name] end
                local module = real[name] and assert(load(source(name), "@" .. name, "t", env))() or stub()
                modules[name] = module
                return module
            end
            local Dispatcher = env.require("runtime.ClientDispatcher")
            local GS = env.require("core.GameState")
            modules["rules.character.PlayerDataManager"] = {
                GetModule = function(_, name) return Dispatcher.get(name) end,
                MarkDirty = noop, FlushImmediate = noop,
            }
            local stage, maxStage, ledger = 101, 101, {}
            local live = {}
            local resetCalls, titleCalls, pendingResets = 0, 0, 0
            local Scene = stub({ getStageId = function() return stage end,
                getMaxStageId = function() return maxStage end,
                getClearedStages = function() return ledger end,
                setBattleData = function(data)
                    stage, maxStage, ledger = data.currentStageId, data.maxStageId, copy(data.clearedStages)
                end,
                resetToDefault = function() stage, maxStage, ledger = 101, 101, {} end,
            })
            local Page = stub({ getTeamStageIds = function() return live end,
                setTeamStageIds = function(ids) live = copy(ids) end,
                resetToDefault = function() resetCalls = resetCalls + 1 live = {} end,
                isOpen = function() return false end })
            modules["ui.battle.scene.BattleScene"] = Scene
            modules["ui.battle.tri.BattleTriPage"] = Page
            modules["ui.character.panel.CharacterPanel"] = stub({ getTeamSlotIds = function() return {} end,
                isHeroesDataApplied = function() return false end,
                getDeployedTeam = function() return {} end, getTotalPower = function() return 0 end })
            local Service = env.require("rules.offline.OfflineService")
            local disk, fault = {}, { open = false, write = false, rename = false }
            local writes = 0
            local function allowed(path)
                assert(path == "standalone_save.json" or path == "standalone_save.pending.json", "禁止访问真实文件: " .. tostring(path))
            end
            env.File = function(path, mode)
                allowed(path)
                local opened = not fault.open and (mode == FILE_WRITE or disk[path] ~= nil)
                return { IsOpen = function() return opened end, Close = noop,
                    ReadString = function() return disk[path] end,
                    WriteString = function(_, text)
                        writes = writes + 1
                        disk[path] = fault.write and text:sub(1, 7) or text
                        return not fault.write
                    end }
            end
            env.fileSystem = {
                FileExists = function(_, path) allowed(path) return disk[path] ~= nil end,
                Delete = function(_, path) allowed(path) disk[path] = nil return true end,
                Rename = function(_, from, to)
                    allowed(from) allowed(to)
                    if fault.rename then return false end
                    disk[to], disk[from] = disk[from], nil
                    return true
                end,
            }
            local Save = env.require("boot.StandaloneSave")
            Save.SetBattlePage(Page)
            env.GameState, env.CharacterPanel, env.BattleScene = GS, modules["ui.character.panel.CharacterPanel"], Scene
            env.ClientDispatcher, env.BattleTriPage = Dispatcher, Page
            env.StandaloneBoot = { resetPendingBattleRewards = function() pendingResets = pendingResets + 1 end }
            env.DarkTitleScreen = { reopen = function() titleCalls = titleCalls + 1 end }
            env.LootBoxPage = { isVisible = function() return false end }
            for _, name in ipairs({ "GameBGM", "GameSFX", "RewardPopup", "MarketPage", "TavernPage", "BlacksmithPage",
                "BackpackPanel", "ChurchPage", "TalentPage", "HeroRosterPanel", "OfflineRewardPanel", "LevelUpPopup",
                "PlayerInfoPanel", "BottomNav", "TopBar", "IntroCutscene", "LetterIntro" }) do
                env[name] = stub({ isOpen = function() return false end, isVisible = function() return false end })
            end
            local Reset = assert(load("local Standalone = {}\n" .. resetSource .. "\nreturn Standalone", "@正式清档入口", "t", env))()
            local function seed(battle)
                disk["standalone_save.json"] = cjson.encode({ savedAt = 199400,
                    gameState = { level = 10, exp = 11, name = "内存存档" }, modules = {
                        battle = battle, heroes = { roster = { h1 = { level = 2, exp = 7 } }, deployed = { 1 } },
                        player = { level = 1 }, session = { lastOnlineTime = 199400, firstLoginTime = 1000 },
                    } })
                return disk["standalone_save.json"]
            end
            return { env = env, dispatcher = Dispatcher, state = GS, save = Save, service = Service,
                page = Page, scene = Scene, reset = Reset, disk = disk, fault = fault, seed = seed,
                counts = function() return resetCalls, titleCalls, pendingResets, writes end }
        end

        runCase("稀疏终焉旧档", function()
            local f = fixture()
            f.seed({ currentStageId = 999, maxStageId = 999, clearedStages = {},
                teamStageIds = { ["1"] = 999, ["2"] = 2001, ["3"] = 1901 } })
            eq(f.save.RestoreData(), true, "真实Restore成功")
            local battle = f.dispatcher.get("battle")
            eq(battle.currentStageId, 2305, "真正读档退到同难度末关")
            eq(battle.teamStageIds["2"], 2001, "旧档二队不丢位置")
            eq(battle.teamStageIds["3"], 1901, "缺账本的终焉旧档三队不误锁")
            eq(ET.getUnlockedTeamCount(battle), 3, "终焉解锁按真实前驱")
            eq(f.dispatcher.get("heroes").roster[1].exp, 7, "真实h键迁移保留英雄经验")
            eq(f.dispatcher.get("player").level, 10, "GameState优先修正旧player镜像")
            f.save.ApplyBattleProgress()
            eq(f.page.getTeamStageIds()["3"], 1901, "恢复活页仍保留三队位置")
            eq(f.save.Flush(), true, "即时保存成功")
            eq(f.save.RestoreData(), true, "二次读档成功")
            eq(f.dispatcher.get("battle").teamStageIds["3"], 1901, "往返不永久删位置")
        end)
        runCase("旧字段冲突与唯一权威", function()
            local f = fixture()
            f.seed({ currentStageId = 2001, maxStageId = 2305,
                teamCurrentStageIds = { 1001, 1501, 1901 }, clearedStages = {} })
            eq(f.save.RestoreData(), true, "侧线旧档真实恢复")
            local battle = f.dispatcher.get("battle")
            eq(battle.currentStageId, 1001, "仅侧线字段时尊重旧一队权威")
            eq(battle.teamStageIds["1"], 1001, "唯一主线字符串键")
            eq(battle.teamCurrentStageIds, nil, "旧字段迁移后删除")
            f.seed({ currentStageId = 2001, maxStageId = 2305,
                teamStageIds = { ["1"] = 1001, ["2"] = 1501, ["3"] = 1901 },
                teamCurrentStageIds = { 203, 204, 205 }, clearedStages = {} })
            eq(f.save.RestoreData(), true, "主线混合旧档恢复")
            eq(f.dispatcher.get("battle").currentStageId, 2001, "有主线表时保留主线current兼容规则")
            eq(f.dispatcher.get("battle").teamStageIds["2"], 1501, "主线二队优先陈旧侧线数组")
        end)
        runCase("锁队脏档与实时终焉", function()
            local f = fixture()
            f.seed({ currentStageId = 905, maxStageId = 905, clearedStages = {},
                teamStageIds = { ["1"] = 905, ["2"] = 904, ["3"] = 903 } })
            f.save.RestoreData()
            eq(f.dispatcher.get("battle").teamStageIds["2"], 101, "刚抵达905仍拒绝锁队位置")
            eq(f.dispatcher.get("battle").teamStageIds["3"], 101, "脏档三队仍锁定")
            eq(ET.getUnlockedTeamCount({ maxStageId = 1905 }), 2, "刚抵达1905不解锁三队")
            local terminal = { currentStageId = 999, maxStageId = 999, clearedStages = {},
                teamStageIds = { ["1"] = 999, ["2"] = 999, ["3"] = 999 } }
            f.dispatcher.handleStateUpdate(cjson.encode({ modules = { battle = terminal } }))
            eq(f.dispatcher.get("battle").currentStageId, 999, "实时onLoad不回退终焉")
            f.page.setTeamStageIds(terminal.teamStageIds)
            f.scene.setBattleData(terminal)
            local captured = f.save.CaptureBattleProgress(f.dispatcher.get("battle"))
            eq(captured.teamStageIds["3"], 999, "实时采集保留三队终焉")
            eq(f.page.getTeamStageIds()["1"], 999, "采集不回灌驱动")
        end)
        runCase("正式清档丢弃旧离线包", function()
            local f = fixture()
            f.dispatcher.handleStateUpdate(cjson.encode({ modules = {
                battle = { currentStageId = 1001, maxStageId = 1001, clearedStages = { ["905"] = true } },
                heroes = { roster = { ["1"] = { level = 1, exp = 0 } }, deployed = { 1 } },
                session = { lastOnlineTime = 199400, firstLoginTime = 1000 }, player = { level = 1, exp = 0 },
                currency = { gold = 40 }, equipment = { inventory = {} }, lootbox = { seeds = {} },
            } }))
            local panel = f.service.CalcOnEnter(1)
            check(type(panel) == "table" and panel.adventureExp > 0, "真实预览产生非空旧包")
            eq(f.service.HasPendingRewards(1), true, "清档前确有pending")
            f.state.importSave({ stellarRecruitTicket = 9, goldenKey = 8, arcaneDust = 7,
                speedCardExpireAt = 999999, privilegeCardOwned = 1, level = 10 })
            f.reset.requestResetToStartScreen()
            eq(f.service.HasPendingRewards(1), false, "正式入口清旧pending")
            eq(f.service.ClaimRewards(1), false, "清档后拒绝领取旧包")
            eq(f.service.CalcOnEnter(1), nil, "新会话不重发旧包")
            local state = f.state.exportSave()
            for _, field in ipairs({ "stellarRecruitTicket", "goldenKey", "arcaneDust", "speedCardExpireAt", "privilegeCardOwned" }) do
                eq(state[field], 0, "清档重置残留字段 " .. field)
            end
            eq(state.level, 1, "清档重置账户等级")
            local reset, title, pending, writes = f.counts()
            eq(reset, 1, "清档丢旧三队驱动")
            eq(pending, 1, "清档丢Boot暂存奖励")
            eq(title, 1, "正式入口回标题一次")
            eq(writes, 0, "清档回归不访问真实存档")
            eq(f.dispatcher.get("battle").teamStageIds["3"], 101, "清档后三队位置回默认")
            eq(next(f.dispatcher.get("battle").clearedStages), nil, "清档不复活首通账本")
        end)
        for _, faultName in ipairs({ "open", "write", "rename" }) do
            runCase("原子写档失败 " .. faultName, function()
                local f = fixture()
                local original = f.seed({ currentStageId = 101, maxStageId = 101, clearedStages = {} })
                f.save.RestoreData()
                f.save.OfflineChecked()
                local before = f.dispatcher.get("session").lastOnlineTime
                f.fault[faultName] = true
                eq(f.save.Flush(), false, faultName .. "失败返回false")
                eq(f.disk["standalone_save.json"], original, faultName .. "不覆盖完整旧档")
                eq(f.disk["standalone_save.pending.json"], nil, faultName .. "清理失败临时文件")
                eq(f.dispatcher.get("session").lastOnlineTime, before, faultName .. "回滚在线边界")
                f.fault[faultName] = false
                eq(f.save.Flush(), true, faultName .. "失败后可重试")
                eq(f.save.RestoreData(), true, faultName .. "重试后可恢复")
            end)
        end
    end)
    if not ok then harnessErrors = harnessErrors + 1 check(false, "Start异常: " .. tostring(err)) end
    print(string.format("%s SUMMARY cases=%d assertions=%d failures=%d harnessErrors=%d", TAG, cases, assertions, failures, harnessErrors))
    if failures > 0 then log:Write(LOG_ERROR, TAG .. " FAILED") end
    engine:Exit()
end
