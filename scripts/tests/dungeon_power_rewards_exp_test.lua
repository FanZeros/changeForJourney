-- 副本战力、收益曲线与经验专项；真实配置/经验/存档模块，文件与通知仅用内存替身。
-- 不加载游戏 Boot，不访问玩家存档或网络；可作独立 Start 入口运行。
local TAG = "[dungeon_power_rewards_exp_test]"
local assertions = 0
local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end
local function eq(actual, expected, label)
    check(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function same(actual, expected)
    if type(actual) ~= type(expected) then return false end
    if type(actual) ~= "table" then return actual == expected end
    for key, item in pairs(expected) do
        if not same(actual[key], item) then return false end
    end
    for key in pairs(actual) do if expected[key] == nil then return false end end
    return true
end
local function source(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少脚本 " .. name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function isolated(mocks)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local modules = {}
    env.require = function(name)
        if mocks[name] then return mocks[name] end
        if modules[name] then return modules[name] end
        assert(name:match("^config%.") or name == "systems.OfflineCalc" or name == "systems.DropSystem" or name == "systems.AttributeDef"
            or name == "systems.UnitAttributes" or name == "shared.StageUtils" or name == "core.GameState"
            or name == "shared.artifact.ArtifactDefs" or name == "shared.artifact.ArtifactSchema"
            or name == "core.I18nTower"
            or name == "rules.dungeon.DungeonService" or name == "rules.tower.TowerService"
            or name == "boot.StandaloneSave" or name:match("^ui%.battle%.stage%.StageSelect"),
            "禁止加载未声明业务入口 " .. name)
        local value = assert(load(source(name), "@" .. name, "t", env))()
        modules[name] = value
        return value
    end
    return env
end

function Start()
    local ok, err = pcall(function()
        local events, drawn = {}, {}
        local mocks = {
            ["core.EventBus"] = { emit = function(name, data) events[#events + 1] = { name, data } end },
            ["systems.EquipmentSystem"] = {},
            ["runtime.ClientDispatcher"] = { get = function() return {} end },
            ["core.I18n"] = { lookup = function(text) return text end,
                get = function() return nil end,
                format = function(fmt, ...) return string.format(fmt, ...) end },
            ["core.NumberUtil"] = { format = function(value) return tostring(math.floor(value)) end },
            ["core.DrawUtil"] = { drawImageCentered = function() end,
                drawTextStroke = function(_, _, _, text) drawn[#drawn + 1] = text end },
            ["core.DarkIcon"] = { drawQualityBg = function() end },
        }
        local env = isolated(mocks)
        local DC = env.require("config.DungeonConfig")
        local SC = env.require("config.StageConfig")
        local IC = env.require("config.DungeonIdleConfig")
        local ET = env.require("config.ExpTable")
        local Income = env.require("config.IdleIncomeConfig")
        local SRP = env.require("config.StageRecommendPower")
        local Resources = env.require("ui.battle.stage.StageSelectResources")
        local Calc = env.require("systems.OfflineCalc")
        local mainPower, mainEstimate = Resources.getRecommendedPower(101)
        eq(mainPower, SRP.get(101), "主线战力保留原表")
        eq(mainEstimate, false, "主线实测状态保留")
        local coverage = 0
        local endpoints = { gold_mine = {1711,344}, equipment_vault = {1661,334}, black_diamond = {1696,341} }
        for _, id in ipairs(DC.RESOURCE_IDS) do
            eq(DC.MAX_FLOOR[id], endpoints[id][1], "资源全层保留最终边界" .. id)
            eq(#DC.getChapterStageIds(id), endpoints[id][2], "章列表保留旧终点" .. id)
            for floor = 1, DC.MAX_FLOOR[id] do
                local cfg = DC.getFloor(id, floor)
                local sid = DC.getStageId(id, floor)
                local combat = SC.getStage(sid)
                check(cfg ~= nil and combat ~= nil, "所有旧副本floor存在" .. id .. ":" .. floor)
                check(SC.getStage(combat.sourceStageId) ~= nil, "所有副本源主线存在" .. id .. ":" .. floor)
            end
            eq(SC.getStage(DC.getStageId(id, DC.MAX_FLOOR[id])).sourceStageId, 34505, "最终345-5源一致" .. id)
            for _, sid in ipairs(DC.getChapterStageIds(id)) do
                local combat = SC.getStage(sid)
                local base = SRP.get(combat.sourceStageId)
                local value, estimated = Resources.getRecommendedPower(sid, combat)
                if base then
                    check(value and value >= base, "资源战力参考不低于来源")
                    eq(estimated, true, "副本不冒充主线实测")
                    coverage = coverage + 1
                else eq(value, nil, "超模型范围不编造战力") end
                local _, perMin = Income.get(combat.sourceStageId)
                eq(DC.getStageExpAmount(sid, 20), perMin, "经验只使用源主线ID")
                check(perMin > 0, "资源副本经验非零")
                local row = Resources.getRewardPreview(sid)
                eq(row.playerExp, DC.getStageExpAmount(sid, 1) * combat.firstCount, "在线整行经验逐杀取整汇总")
                for count = 1, 4 do
                    local rewards = DC.getStageRewards(sid, 20, count)
                    eq(rewards.adventureExp, perMin, "玩家经验不随人数叠加")
                    eq(rewards.adventurerExp, math.floor(perMin * ET.getHeroCountExpMult(count) + 0.5),
                        "队员经验池按实际人数")
                end
            end
        end
        check(coverage > 40, "覆盖三种副本章节战力")
        local TC = env.require("config.TowerConfig")
        local StageExp = env.require("config.StageExpHelper")
        for _, start in ipairs({1, 6, 111}) do
            local diamond, firstExp, repeatExp = 0, 0, 0
            for floor = start, TC.getRunEndFloor(start) do
                local cfg = TC.getFloor(floor)
                diamond = diamond + cfg.firstDiamond
                firstExp = firstExp + math.floor(StageExp.getExpPerMin(cfg.monsterLevel) * 2)
                repeatExp = repeatExp + math.floor(StageExp.getExpPerMin(cfg.monsterLevel))
            end
            local preview = Resources.getRewardPreview(400000 + start, nil, {babel_tower={floor=1,cleared={}}})
            eq(preview.firstAmount, diamond, "塔本组剩余首钻汇总")
            eq(preview.repeatAmount, 0, "塔重打预览0黑钻")
            eq(preview.playerExp, firstExp, "塔首通2分逐层取整汇总")
            eq(preview.repeatPlayerExp, repeatExp, "塔重打1分逐层取整汇总")
            eq(preview.artifactDropRate, .05, "预览每层神器概率")
            eq(table.concat(preview.artifactQualityWeights, ","), "80,18,2", "预览神器品质权重")
            eq(preview.runEndFloor, TC.getRunEndFloor(start), "末组112截断")
        end
        eq(Resources.getRewardPreview(400001, nil, {babel_tower={floor=6,cleared={}}}).firstAmount, 0,
            "旧floor6首组首奖已领")
        local fresh = Resources.getRewardPreview(400001, nil, {babel_tower={floor=1,cleared={}}})
        eq(Resources.getRewardPreview(400001, nil, {babel_tower={floor=1,cleared={["5"]=true}}}).firstAmount,
            fresh.firstAmount - TC.getFloor(5).firstDiamond, "稀疏高层cleared不抹低层首奖")
        local towerPower, towerEstimated = Resources.getRecommendedPower(400001)
        eq(towerPower, SRP.get(1201) * 2, "塔同等级参考乘属性倍率")
        eq(towerEstimated, true, "塔仅作参考")
        eq(Resources.getRecommendedPower(400112), nil, "塔345级不绕过外推上限")
        eq(DC.getStageExpAmount(999999, 20), 0, "非法副本无经验")
        eq(DC.getStageExpAmount(300001, -1), 0, "负击杀无经验")
        -- 真正奖励绘制入口只收静态数据，校验玩家可见文案与随机状态。
        env.time = { elapsedTime = 1 }
        env.NVG_ALIGN_LEFT, env.NVG_ALIGN_MIDDLE = 1, 16
        for _, name in ipairs({ "nvgDeleteImage", "nvgFontFace", "nvgFontSize", "nvgSave",
            "nvgRestore", "nvgIntersectScissor", "nvgBeginPath", "nvgRoundedRect",
            "nvgFillColor", "nvgFill" }) do env[name] = function() end end
        env.nvgCreateImage = function() return 1 end
        env.nvgRGBA = function() return {} end
        env.nvgTextBounds = function(_, _, _, text) return #text * 5 end
        local RewardPreview = env.require("ui.battle.stage.StageSelectRewardPreview")
        eq(RewardPreview.formatEstimate(0), "0", "零奖励直接数字")
        eq(RewardPreview.formatEstimate(0.125), "0.125", "小数奖励无预估符号")
        for _, sid in ipairs({ 100001, 200001, 300001, 400001 }) do
            local before = #drawn
            RewardPreview.draw({}, Resources.getRewardPreview(sid), 0, 0, 700, 34, false)
            local hasExp = false
            for i = before + 1, #drawn do
                local text = drawn[i]
                check(not text:find("预估", 1, true) and not text:find("≈", 1, true), "奖励无预估文案")
                if text:find("远征经验", 1, true) then hasExp = true end
            end
            check(hasExp, "每类副本展示远征经验")
        end
        for floor = 27, DC.MAX_FLOOR.black_diamond do
            local current = IC.getIdlePerMin("black_diamond", floor)
            local previous = IC.getIdlePerMin("black_diamond", floor - 1)
            check(current >= previous and current - previous < 0.04, "黑钻全层无整数断崖")
            eq(math.type(IC.calcReward("black_diamond", floor, 86400)), "integer", "领取整数")
        end
        eq(IC.calcReward("black_diamond", 55, 86400), 5700, "55层24h")
        eq(IC.calcReward("black_diamond", 56, 86400), 5800, "56层24h")
        eq(IC.calcReward("black_diamond", 56, IC.HARD_CAP_SEC + 86400),
            IC.calcReward("black_diamond", 56, IC.HARD_CAP_SEC), "硬顶保持")

        local teams = { { teamIdx = 1, stageId = 100001, heroCount = 1 },
            { teamIdx = 2, stageId = 200006, heroCount = 3 },
            { teamIdx = 3, stageId = 300056, heroCount = 4 } }
        local beforeRandom = math.random
        local randomCalls = 0
        math.random = function(...) randomCalls = randomCalls + 1; return beforeRandom(...) end
        local previewOk, preview = pcall(Calc.previewTeamOfflineRewards, 3600, teams)
        math.random = beforeRandom
        assert(previewOk, preview)
        eq(randomCalls, 0, "预览不消耗随机数")
        local actual = Calc.calcTeamOfflineRewards(3600, teams)
        for i, reward in ipairs(actual.teamRewards) do
            eq(reward.adventureExp, preview.teamRewards[i].adventureExp, "离线实际与预览经验一致")
            eq(reward.adventurerExp, preview.teamRewards[i].adventurerExp, "各队人数倍率一致")
            eq(reward.adventureExp, DC.getStageExpAmount(teams[i].stageId, 1200), "1h资源经验")
        end

        -- 提取正式 Driver 的记账/排队方法，不启动战斗场景。
        local driverText = source("ui.battle.tri.BattleTriDriver")
        local first = assert(driverText:find("    function drv:reportKill(unit)", 1, true))
        local last = assert(driverText:find("    function drv:tickRewards(dt)", first, true))
        local driver = { stageId = 300001, teamIdx = 2, kills = 0, pendingKills = {},
            allies = { { heroId = 7, hp = 10 }, { heroId = 8, hp = 10 }, { heroId = 9, hp = 0 } } }
        local driverEnv = setmetatable({ drv = driver, SC = SC }, { __index = env })
        assert(load(driverText:sub(first, last - 1), "@Driver奖励方法", "t", driverEnv))()
        driver:reportKill({ expReward = 999999, goldReward = 999999 })
        driver.allies = { { heroId = 99, hp = 0 } }
        driver:queuePendingKills()
        local drop = driver.rewardQueue[1]
        eq(drop.teamIdx, 2, "掉落保留原队伍")
        eq(#drop.heroIds, 2, "关末死亡不抹去逐杀快照")
        eq(drop.heroIds[1], 7, "不发给切换后的阵容")

        -- 实际 Boot 消费分支；源怪奖励与首通逻辑不能再次执行。
        local boot = source("boot.StandaloneBoot")
        first = assert(boot:find("    local function applyKillDrop(data)", 1, true))
        last = assert(boot:find("        local stageEntry = StageConfig.getStage(data.stageId)", first, true))
        local GS = env.require("core.GameState")
        GS.setLocalPlayerSync(function() end)
        local recipient, perHero = {}, 0
        local bootEnv = setmetatable({ StageConfig = SC, DungeonConfig = DC, GameState = GS,
            CharacterPanel = { getTeamSlotIds = function() error("有快照不应读当前编队") end,
                addHeroesExp = function(ids, amount) recipient, perHero = ids, amount end },
            addKillEquipment = function() end }, { __index = env })
        local mapFirst = assert(boot:find("local SCROLL_DROP_TO_REWARD =", 1, true))
        local mapLast = assert(boot:find("\n}", mapFirst, true)) + 2
        local consume = assert(load(boot:sub(mapFirst, mapLast) .. "\n" .. boot:sub(first, last - 1) .. "    end\nreturn applyKillDrop",
            "@Boot资源发奖", "t", bootEnv))()
        local playerBefore = GS.exportSave()
        local expectedExp = DC.getStageExpAmount(drop.stageId, 1)
        local expectedPlayer = { level = playerBefore.level, exp = playerBefore.exp }
        expectedPlayer.exp = expectedPlayer.exp + expectedExp
        ET.autoLevelUpPlayer(expectedPlayer)
        consume(drop)
        eq(GS.getLevel(), expectedPlayer.level, "在线玩家升级使用正式经验链")
        eq(GS.getExp(), expectedPlayer.exp, "在线玩家经验到账")
        eq(recipient[1], 7, "经验发给原队员")
        eq(perHero, math.floor(math.floor(expectedExp * 1.5 + 0.5) / 2 + 0.5), "两人池均分")

        -- 实际 Save 的临时写入/替换逻辑，仅允许两个虚拟文件名。
        local files, failWrite, failRename = {}, false, false
        local modules = { player = { level = 5, exp = 27, name = "副本测试", maxExp = ET.getPlayerExpForLevel(5) },
            heroes = { roster = { [7] = { level = 3, exp = 19 } } } }
        mocks["runtime.ClientDispatcher"] = { snapshotAll = function() return modules end,
            get = function(name) return modules[name] end }
        mocks["ui.battle.scene.BattleScene"] = {}
        mocks["shared.battle.BattleSchema"] = {}
        mocks["rules.offline.OfflineService"] = {}
        env.File = function(path, mode)
            assert(path == "standalone_save.pending.json" and mode == FILE_WRITE, "只允许虚拟临时文件")
            return { IsOpen = function() return true end, Close = function() end,
                WriteString = function(_, text)
                    if failWrite then return false end
                    files[path] = text
                    return true
                end }
        end
        env.fileSystem = { Delete = function(_, path) files[path] = nil end,
            Rename = function(_, from, to)
                assert(from == "standalone_save.pending.json" and to == "standalone_save.json")
                if failRename then return false end
                files[to], files[from] = files[from], nil
                return true
            end }
        local Save = env.require("boot.StandaloneSave")
        local live = GS.exportSave()
        local eventBefore = #events
        check(Save.Flush(modules.player), "候选玩家提交成功")
        local saved = cjson.decode(files["standalone_save.json"])
        eq(saved.gameState.level, 5, "磁盘GameState与player同级")
        eq(saved.gameState.exp, 27, "磁盘GameState与player同经验")
        eq(saved.modules.heroes.roster.h7.exp, 19, "英雄ID/经验保存")
        eq(GS.getLevel(), live.level, "提交前不改变live玩家")
        eq(#events, eventBefore, "构造候选存档不发升级通知")
        local oldFile = files["standalone_save.json"]
        for _, failure in ipairs({ "write", "rename" }) do
            failWrite, failRename = failure == "write", failure == "rename"
            eq(Save.Flush(modules.player), false, failure .. "失败透传")
            eq(files["standalone_save.json"], oldFile, failure .. "不覆盖旧档")
            eq(GS.getExp(), live.exp, failure .. "不提前给玩家经验")
            eq(#events, eventBefore, failure .. "不发布经验事件")
        end

        -- 读取实际本地桥的副本提交钩子；验证失败零通知、成功先heroes后player。
        local bridge = source("runtime.LocalActionBridge")
        first = assert(bridge:find('    require("rules.dungeon.DungeonService").SetPersistCallback', 1, true))
        last = assert(bridge:find('    print("[LocalActionBridge] init', first, true))
        local order, persist, hooks = {}, nil, nil
        local bridgeEnv = setmetatable({ PDM = { GetModule = function() return modules.player end },
            ClientDispatcher = { set = function(name) order[#order + 1] = name end },
            GameState = { syncPlayerData = function(player)
                order[#order + 1] = "player"
                GS.syncPlayerData(player)
            end, syncFromCurrency = function() end },
            require = function(name)
                if name == "rules.dungeon.DungeonService" then
                    return { SetPersistCallback = function(fn, h) persist, hooks = fn, h end }
                end
                assert(name == "boot.StandaloneSave")
                return Save
            end }, { __index = env })
        assert(load(bridge:sub(first, last - 1), "@Bridge副本提交钩子", "t", bridgeEnv))()
        hooks.begin()
        bridgeEnv.deferredTaskPushes_ = { heroes = modules.heroes, player = modules.player }
        hooks.finish(1, false)
        eq(#order, 0, "事务失败零模块通知")
        hooks.begin()
        bridgeEnv.deferredTaskPushes_ = { heroes = modules.heroes, player = modules.player }
        hooks.finish(1, true)
        eq(order[1], "heroes", "成功先同步队员")
        eq(order[2], "player", "成功同步玩家真实源")
        eq(GS.getExp(), 27, "下一动作使用的新玩家经验")
        GS.importSave(saved.gameState)
        eq(GS.getExp(), saved.modules.player.exp, "冷恢复经验与模块一致")
        -- 注入异常订阅者和同步重入，不能跳过玩家提交或把候选引用覆盖。
        local guardStart = assert(bridge:find("function M.dispatch(action, params)", 1, true))
        local guardEnd = assert(bridge:find("    if not inited_ then", guardStart, true))
        bridgeEnv.M = {}
        assert(load(bridge:sub(guardStart, guardEnd - 1) .. " return true end",
            "@Bridge重入门禁", "t", bridgeEnv))()
        local reentry = true
        bridgeEnv.ClientDispatcher.set = function(name)
            if name == "heroes" then
                reentry = bridgeEnv.M.dispatch("test")
                modules.player.exp = 999 -- 模拟订阅者直接改共享引用，冻结副本仍应生效。
                error("模拟队员订阅者异常")
            end
        end
        modules.player.exp = 27
        GS.importSave(live)
        hooks.begin()
        bridgeEnv.deferredTaskPushes_ = { heroes = modules.heroes, player = modules.player }
        hooks.finish(1, true)
        eq(reentry, false, "提交通知期间拒绝action重入")
        eq(GS.getExp(), 27, "异常heroes通知不跳过玩家同步")
        eq(bridgeEnv.M.dispatch("test"), true, "通知完成解除重入门禁")

        -- 正式副本事务：写失败原位恢复玩家/队员经验，并复用真实桥提交钩子。
        modules.player.exp = 27
        modules.heroes.teams = { { slots = { 7 } } }
        modules.heroes.deployed = { 7 }
        mocks["rules.character.PlayerDataManager"] = {
            GetModule = function(_, name) return modules[name] end,
            MarkDirty = function(_, name) bridgeEnv.deferredTaskPushes_[name] = modules[name] end,
        }
        mocks["systems.LootBoxSystem"] = {}
        mocks["shared.heroes.TeamSlots"] = {}
        mocks["shared.ModuleRegistry"] = { find = function() return nil end }
        mocks["shared.schemas.CharacterSchema"] = { Fields = {} }
        bridgeEnv.ClientDispatcher.set = function(name) order[#order + 1] = name end
        local Service = env.require("rules.dungeon.DungeonService")
        Service.SetPersistCallback(persist, hooks)
        local previousPlayer = copy(modules.player)
        local previousHeroes = copy(modules.heroes)
        for _, failure in ipairs({ "write", "rename" }) do
            failWrite, failRename = failure == "write", failure == "rename"
            local notifications = #order
            local committed = Service.CommitRewardTransaction(1, function()
                Service.GrantIdleExp(1, 1, 6, 1)
                return true, nil, {}
            end)
            eq(committed, false, failure .. "事务失败")
            check(same(modules.player, previousPlayer), failure .. "玩家经验原位回滚")
            check(same(modules.heroes, previousHeroes), failure .. "队员经验原位回滚")
            eq(#order, notifications, failure .. "事务零通知")
        end
        failWrite, failRename = false, false
        check(Service.CommitRewardTransaction(1, function()
            Service.GrantIdleExp(1, 1, 6, 1)
            return true, nil, {}
        end), "实际副本经验事务成功")
        eq(GS.getExp(), modules.player.exp, "成功后GameState与玩家模块经验一致")
        eq(GS.getLevel(), modules.player.level, "成功后GameState与玩家模块等级一致")
        local transactionSave = cjson.decode(files["standalone_save.json"])
        eq(transactionSave.gameState.exp, modules.player.exp, "事务磁盘玩家经验一致")
        eq(transactionSave.modules.heroes.roster.h7.exp, modules.heroes.roster[7].exp, "事务磁盘队员经验一致")

        mocks["rules.currency.CurrencyService"] = { GrantReward = function() return true end }
        modules.dungeon = { babel_tower = { floor = 2, dailyUsed = 0,
            dailyDay = math.floor((os.time() + 28800) / 86400), buffs = {} } }
        modules.currency = {}
        mocks["rules.character.PlayerDataManager"].MarkDirty = function() end
        modules.artifacts = env.require("shared.artifact.ArtifactSchema").Fields.artifacts.getDefault()
        local beforeTowerGems = modules.currency.gems or 0
        local Tower = env.require("rules.tower.TowerService")
        -- 此处专测原经验与0钻，不让神器概率影响只读经验oracle。
        local oldRandom = env.math
        env.math = setmetatable({ random = function() return .99 end }, { __index = math })
        local towerOk, _, towerResult = Tower.Sweep(1)
        env.math = oldRandom
        check(towerOk, "塔扫荡成功")
        eq(towerResult.diamondReward, 0, "塔扫荡无黑钻")
        eq(modules.currency.gems or 0, beforeTowerGems, "扫荡余额无黑钻变化")
        eq(towerResult.playerExp, math.floor(StageExp.getExpPerMin(TC.getFloor(1).monsterLevel) * 10),
            "塔扫荡保持原10分钟经验")
        check(towerResult.playerExp > 0 and towerResult.heroExpTotal > 0, "塔扫荡发两类经验")
        print(TAG .. " ALL PASS: " .. assertions .. " assertions")
    end)
    if not ok then log:Write(LOG_ERROR, TAG .. " FAIL after " .. assertions .. ": " .. tostring(err)) end
    engine:Exit()
end
