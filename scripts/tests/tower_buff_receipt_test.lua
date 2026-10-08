-- 通天塔五层组：真实 GameAction -> Bridge -> Handler -> Service -> Page -> Scene/择契Panel。
-- 仅内存模块、保存出口与回执时机替身；不读玩家档、不启动Boot、不访问网络。
-- UrhoXRuntime tests/tower_buff_receipt_test.lua -tapcode_dir=/workspace/game6 -tool_mode -graphicsheadless -nosound
local assertions, failures = 0, 0
local restores = {}
local function check(value, label)
    assertions = assertions + 1
    if not value then failures = failures + 1; print("[TowerBuff][FAIL] " .. label) end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function patch(owner, key, value)
    local old = owner[key]
    restores[#restores + 1] = function() owner[key] = old end
    owner[key] = value
    return old
end
local function upvalue(fn, wanted)
    for i = 1, 100 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value, i end
        if not name then break end
    end
    error("fixture cannot locate upvalue " .. wanted)
end

function Start()
    local ok, err = xpcall(function()
        local Protocol = require("shared.Protocol")
        local AT = Protocol.ACTION_TYPES
        local Dispatcher = require("runtime.ClientDispatcher")
        local PDM = require("rules.character.PlayerDataManager")
        local Bridge = require("runtime.LocalActionBridge")
        local Action = require("runtime.GameAction")
        local Msg = require("runtime.ClientMessageHandler")
        local Page = require("ui.dungeon.DungeonPage")
        local Scene = require("ui.tower.TowerBattleScene")
        local Panel = require("ui.tower.TowerBuffPick")
        local Tri = require("ui.tower.TowerTriBattle")
        local Service = require("rules.tower.TowerService")
        local Transaction = require("rules.dungeon.DungeonService")
        local Config = require("config.TowerConfig")
        local Runtime = require("systems.TowerBuffRuntime")
        local ArtifactDefs = require("shared.artifact.ArtifactDefs")
        local ArtifactSchema = require("shared.artifact.ArtifactSchema")
        local Schema = require("shared.schemas.CharacterSchema")
        local HC = require("config.HeroConfig")
        local CC = require("config.ClassConfig")
        local CP = require("ui.character.panel.CharacterPanel")
        local AD = require("systems.AttributeDef")
        local ExpTable = require("config.ExpTable")
        local StageExp = require("config.StageExpHelper")
        local BRP = require("ui.battle.popup.BattleResultPanel")
        local GameState = require("core.GameState")
        local gameSnapshot = GameState.exportSave()
        restores[#restores + 1] = function() GameState.importSave(gameSnapshot) end
        local sceneState = upvalue(Scene.isActive, "state")
        local panelState = upvalue(Panel.isOpen, "state")
        local all = Dispatcher.getAll()
        local originals = copy(all)
        local originalRefs = {}
        for k, v in pairs(all) do originalRefs[k] = v end
        restores[#restores + 1] = function()
            Scene.resetToDefault()
            Service.ResetToDefault()
            Page.close()
            for k in pairs(all) do all[k] = nil end
            for k, v in pairs(originalRefs) do all[k] = v end
        end
        local saveOk, saveThrows, saveCount = true, false, 0
        local persisted = {}
        patch(require("boot.StandaloneSave"), "Flush", function()
            saveCount = saveCount + 1
            if saveThrows then error("fixture write exception") end
            if saveOk then persisted[#persisted + 1] = copy(all) end
            return saveOk
        end)
        patch(require("rules.redeem.RedeemService"), "Init", function() end)
        local teams = {}
        patch(CP, "getDeployedTeam", function(t) return teams[t or 1] or {} end)
        for _, card in ipairs(upvalue(Panel.handleClick, "kwCards")) do
            patch(card, "isOpen", function() return false end)
            patch(card, "handleInput", function() return false end)
        end
        local receipts, held = {}, {}
        local holdPick, holdFloor = false, false
        patch(Msg, "handleActionResult", function(data)
            receipts[#receipts + 1] = copy(data)
            if (holdPick and data.action == AT.TOWER_PICK_BUFF) or (holdFloor and data.action == AT.TOWER_FLOOR_WIN) then
                held[#held + 1] = copy(data)
            else Page.onActionResult(data) end
        end)
        patch(Config, "rollBuffs", function()
            return { Config.BUFFS_BY_ID[20], Config.BUFFS_BY_ID[28], Config.BUFFS_BY_ID[1] }
        end)
        local randomValue, randomSequence, randomCalls = .99, {}, 0
        local originalRandom = math.random
        patch(math, "random", function(a, b)
            if a ~= nil then return originalRandom(a, b) end
            randomCalls = randomCalls + 1
            if #randomSequence > 0 then return table.remove(randomSequence, 1) end
            return randomValue
        end)
        local artifactCalls, ratioCalls = 0, 0
        patch(ArtifactDefs, "rollArtifactId", function(quality)
            artifactCalls = artifactCalls + 1
            check(quality >= 1 and quality <= 3, "塔神器品质仅1..3")
            return 2
        end)
        patch(ArtifactDefs, "rollValueRatio", function() ratioCalls = ratioCalls + 1; return 4321 end)
        patch(ArtifactDefs, "rollThreatClearValueRatio", function() return 6789 end)
        local shown, panelOpen = {}, false
        patch(BRP, "show", function(opts) shown[#shown + 1] = copy(opts); panelOpen = true end)
        patch(BRP, "isOpen", function() return panelOpen end)
        patch(BRP, "resetToDefault", function() panelOpen = false end)
        patch(BRP, "update", function() end)
        Bridge.init()
        local Store = require("core.PlayerStore")
        Store.Init()
        restores[#restores + 1] = function() Store.Cleanup() end
        local actionCounts, opens = {}, 0
        local oldSend = Action.sendAction
        patch(Action, "sendAction", function(action, params)
            actionCounts[action] = (actionCounts[action] or 0) + 1
            return oldSend(action, params)
        end)
        local oldOpen = Tri.open
        patch(Tri, "open", function(opts) opens = opens + 1; return oldOpen(opts) end)
        local function last(action)
            for i = #receipts, 1, -1 do if receipts[i].action == action then return receipts[i] end end
            error("missing receipt " .. action)
        end
        local function reset(floor, cleared, requestedFloor)
            Scene.close()
            Service.ResetToDefault(1)
            Page.close()
            panelOpen = false
            holdPick, holdFloor, held, receipts = false, false, {}, {}
            actionCounts, opens, shown, persisted = {}, 0, {}, {}
            saveOk, saveThrows, saveCount = true, false, 0
            randomValue, randomSequence, randomCalls, artifactCalls, ratioCalls = .99, {}, 0, 0, 0
            for k in pairs(all) do all[k] = nil end
            for name, field in pairs(Schema.Fields) do
                if field.getDefault then all[name] = field.getDefault() end
            end
            all.battle = { maxStageId = 2001, clearedStages = { [1905] = true } }
            all.player = { name = "Tower fixture", level = 1, exp = 0 }
            all.currency = { gems = 0, gold = 0, arcaneDust = 0 }
            GameState.syncFromCurrency(all.currency, { silent = true })
            all.heroes = { roster = {}, teams = {}, deployed = {} }
            all.artifacts = ArtifactSchema.Fields.artifacts.getDefault()
            all.artifacts.pityRare, all.artifacts.pityEpic, all.artifacts.totalDraws = 7, 12, 19
            all.artifacts.dailyFreeDrawDayId = 55
            all.dungeon = { babel_tower = { floor = floor or 1, cleared = cleared or {}, buffs = {},
                dailyUsed = 0, dailyDay = math.floor((os.time() + 28800) / 86400) } }
            teams = {}
            for t = 1, 3 do
                local id = 8 + t
                local unit = assert(HC.createHero(id, 1))
                unit.classId, unit.atkInterval = CC.MAGE, 1
                unit.attrs.final[AD.HP] = unit.attrs:get(AD.MAX_HP)
                unit.hp, unit.maxHp = unit.attrs:get(AD.HP), unit.attrs:get(AD.MAX_HP)
                teams[t] = { unit }
                all.heroes.roster[id] = { level = 1, exp = 0 }
                all.heroes.teams[t] = { slots = { id } }
            end
            all.heroes.deployed = { 9 }
            GameState.syncPlayerData(all.player)
            for name, data in pairs(all) do Dispatcher.set(name, data) end
            -- 正式Page挑战接口与Action桥，不通过旧选关坐标硬编码。
            eq(Page.requestTowerChallenge(requestedFloor or Config.getCheckpointFloor(floor or 1)), true, "Page真实挑战入口")
            eq(Scene.isActive(), true, "Page正式打开Scene")
            eq(PDM.GetModule(1, "dungeon"), all.dungeon, "PDM与Dispatcher同表")
            eq(sceneState.wave, 1, "开局单波")
            eq(opens, 1, "开局仅一次")
        end
        local function win(floor)
            Action.sendAction(AT.TOWER_WAVE_WIN, { floor = floor, wave = 1, runId = sceneState.runId })
            eq(last(AT.TOWER_WAVE_WIN).success, true, "真实单波清层" .. floor)
            if not holdFloor and floor < sceneState.endFloor and last(AT.TOWER_FLOOR_WIN).success then
                eq(sceneState.floor, floor + 1, "逐层自动继续" .. floor)
                eq(sceneState.wave, 1, "续层wave恒1" .. floor)
                eq(Panel.isOpen(), true, "每层待选保留" .. floor)
            end
        end
        local function click(index) return Panel.handleClick(540, 744 + (index - 1) * 368) end
        local function interval(expected, label)
            check(math.abs(teams[1][1].atkInterval - expected) < 1e-7, label .. " actual=" .. tostring(teams[1][1].atkInterval))
        end
        local function case(name, fn)
            local success, message = xpcall(fn, debug.traceback)
            if not success then check(false, name .. " exception=" .. tostring(message)) end
        end
        case("checkpoint门禁与1到5", function()
            reset()
            eq(Config.MAX_FLOOR, 112, "保留112真实层")
            eq(Config.WAVES_PER_FLOOR, 1, "每层一波")
            eq(Service.Challenge(1, 6), false, "未通5不可挑战6")
            for _, bad in ipairs({ 0, 2, 5, 7, 112, 113, 1.5 }) do eq(Service.Challenge(1, bad), false, "拒绝非法/非起点" .. bad) end
            eq(Service.FloorWin(1, 1), false, "未清层不能结算")
            local diamonds, exp = 0, 0
            for floor = 1, 5 do
                win(floor)
                local receipt = last(AT.TOWER_FLOOR_WIN)
                eq(receipt.floor, floor, "实际floor回执" .. floor)
                eq(receipt.firstClear, true, "每层独立首通" .. floor)
                eq(receipt.diamondReward, Config.getFloor(floor).firstDiamond, "逐层首钻" .. floor)
                eq(receipt.playerExp, math.floor(StageExp.getExpPerMin(Config.getFloor(floor).monsterLevel) * 2), "每层首通2分" .. floor)
                eq(receipt.continueRun, floor < 5, "本组界线" .. floor)
                diamonds, exp = diamonds + receipt.diamondReward, exp + receipt.playerExp
                if floor < 5 then Panel.hide() end
            end
            eq(opens, 5, "1..5各开一次无第6层")
            eq(saveCount, 5, "每层独立保存一次")
            eq(all.currency.gems, diamonds, "本组首钻总和")
            eq(all.dungeon.babel_tower.floor, 6, "通5解锁6")
            eq(#shown, 1, "组末唯一总面板")
            eq(shown[1].floor, 5, "面板真实第5层")
            eq(shown[1].rewards[1].amount, diamonds, "面板汇总本组黑钻")
            eq(sceneState.runPlayerExp, exp, "组经验仅每层和无额外")
            eq(#sceneState.choiceQueue, 0, "组末清未选")
            eq(#all.dungeon.babel_tower.buffs, 0, "组末清权威暗契")
            eq(Service.Challenge(1, 6), true, "通5后6可挑战")
        end)
        case("20不双写下一层生效", function()
            reset(); win(1); click(1)
            eq(#all.dungeon.babel_tower.buffs, 1, "Service20只追加1")
            eq(#sceneState.buffIds, 1, "Scene20独立快照只1")
            check(sceneState.buffIds ~= all.dungeon.babel_tower.buffs, "Scene/PDM快照隔离")
            interval(1, "第2层进行中选20不重开不应用")
            local pick = last(AT.TOWER_PICK_BUFF)
            Page.onActionResult(pick); Page.onActionResult(pick)
            eq(opens, 2, "重复Pick不重开")
            win(2); interval(.75, "第3层20只乘一次")
            click(1); win(3); interval(.5625, "第4层同卡跨清层0.75平方")
            eq(pick.buffs[1], 20, "旧Pick快照不污染")
        end)
        case("28组合与FIFO迟到", function()
            reset(); win(1); Panel.hide(); win(2); win(3)
            eq(Panel.isVisible(), false, "收起后累计不弹出")
            eq(#sceneState.choiceQueue, 3, "累计三层FIFO")
            local first, second = sceneState.choiceQueue[1], sceneState.choiceQueue[2]
            eq(Service.PickBuff(1, 28, { runId = second.runId, selectionId = second.selectionId, floor = second.floor, wave = 1 }), false, "不能跳过FIFO首项")
            Panel.show()
            eq(panelState.request.floor, 1, "选项身份保持已清1不是当前4")
            holdPick = true; click(1)
            local pick = held[1]
            eq(sceneState.floor, 4, "等待Pick仍在4")
            click(2); eq(actionCounts[AT.TOWER_PICK_BUFF], 1, "pending不重复发送")
            Page.onActionResult(last(AT.TOWER_FLOOR_WIN)); eq(opens, 4, "重复Floor回执不重开")
            Page.onActionResult(pick); Page.onActionResult(pick)
            interval(1, "迟到20不改进行中4")
            eq(panelState.request.floor, 2, "迟到后FIFO第二原层2")
            holdPick = false; click(2)
            eq(panelState.request.floor, 3, "FIFO第三原层3")
            click(3); eq(#sceneState.choiceQueue, 0, "FIFO三组消费")
            eq(all.dungeon.babel_tower.buffs[1], 20, "FIFO20")
            eq(all.dungeon.babel_tower.buffs[2], 28, "FIFO28")
            interval(1, "累计选择不改4")
            win(4); interval(1.5, "第5层20/28各乘一次")
            win(5)
            eq(Service.PickBuff(1, 20, {runId=first.runId,selectionId=first.selectionId,floor=1,wave=1}), false, "组末旧accepted也过期")
            Page.onActionResult(pick); eq(#sceneState.buffIds, 0, "组末迟到Pick无污染")
        end)
        case("Pick失败、超时与身份冲突", function()
            reset(); win(1)
            local issued = last(AT.TOWER_FLOOR_WIN)
            eq(Service.PickBuff(1, 2, issued), false, "非候选拒绝")
            all.battle = { maxStageId = 101 }; click(1)
            eq(last(AT.TOWER_PICK_BUFF).success, false, "真实门禁失败")
            eq(panelState.pending, false, "失败释放Panel")
            eq(sceneState.floor, 2, "失败不回退/重开层2")
            all.battle = { maxStageId = 2001, clearedStages = { [1905] = true } }
            holdPick = true; click(1)
            local old = held[1]
            eq(#all.dungeon.babel_tower.buffs, 1, "回执丢失前权威已一次")
            Page.onActionResult({action=AT.TOWER_PICK_BUFF,success=false,reason="无身份"})
            eq(panelState.pending, true, "无身份失败不可释放")
            local tick = Tri.update; Tri.update = function() end; Scene.update(5.1); Tri.update = tick
            eq(panelState.pending, false, "5秒超时允许同卡重试")
            click(2); eq(actionCounts[AT.TOWER_PICK_BUFF], 2, "未知结果不可改选另一卡")
            click(1)
            local retry = held[2]
            check(retry.requestId ~= old.requestId, "重试requestId不同")
            Page.onActionResult(old); eq(panelState.pending, true, "旧成功不能消费retry")
            Page.onActionResult(retry); Page.onActionResult(retry)
            eq(#all.dungeon.babel_tower.buffs, 1, "重试不重复权威append")
            eq(#sceneState.buffIds, 1, "当前retry快照仅1")
            eq(Service.PickBuff(1, 28, {runId=old.runId,selectionId=old.selectionId,floor=1,wave=1}), false, "同selection不能改卡")
            win(2)
            local next = last(AT.TOWER_FLOOR_WIN)
            eq(Service.PickBuff(1, 20, {runId=next.runId,selectionId=next.selectionId,floor=2,wave=1,requestId=old.requestId}), false, "requestId不能复用其他selection")
            eq(Service.PickBuff(1, 20, {runId=next.runId,selectionId=next.selectionId,floor=3,wave=1}), false, "原floor校验不按run.floor")
            interval(.75, "超时20仅下一层应用")
        end)
        case("清波结算重复与过期回执", function()
            reset(); holdFloor = true; win(1)
            local floorResult = held[1]
            eq(opens, 1, "成功未交付前不开层2")
            eq(sceneState.floor, 1, "结算等待真实原floor")
            local wrong = copy(floorResult); wrong.runId = "old-run"
            eq(Scene.onFloorWinResult(wrong), false, "旧run结算忽略")
            wrong = copy(floorResult); wrong.floor = 2
            eq(Scene.onFloorWinResult(wrong), false, "未来floor忽略")
            wrong = copy(floorResult); wrong.requestId = "old-request"
            eq(Scene.onFloorWinResult(wrong), false, "旧请求忽略")
            wrong = copy(floorResult); wrong.monsters = nil
            eq(Scene.onFloorWinResult(wrong), false, "残缺续层回执忽略")
            Page.onActionResult(last(AT.TOWER_WAVE_WIN))
            eq(actionCounts[AT.TOWER_FLOOR_WIN], 1, "Wave重复不再结算")
            Page.onActionResult(floorResult); Page.onActionResult(floorResult)
            eq(opens, 2, "Floor重复只开一次层2")
            local _, _, replay = Service.FloorWin(1, 1, {runId=floorResult.runId})
            eq(replay.diamondReward, floorResult.diamondReward, "run.floor已2仍按已清floor缓存回执")
            eq(saveCount, 1, "重复Floor无二次保存")
            replay.rewards[1].amount = 99999
            local _, _, clean = Service.FloorWin(1, 1)
            eq(clean.rewards[1].amount, Config.getFloor(1).firstDiamond, "Floor缓存快照隔离")
            local before = sceneState.runPlayerExp
            Page.onActionResult(floorResult)
            eq(sceneState.runPlayerExp, before, "重复回执无重复汇总")
        end)
        case("保存失败固定开奖和重试入口", function()
            reset(); randomSequence = {.01,.85}; saveOk = false
            win(1)
            local failure = last(AT.TOWER_FLOOR_WIN)
            eq(failure.success, false, "真实保存false")
            eq(sceneState.phase, "settlement_retry", "保存失败停原层可重试")
            eq(opens, 1, "保存失败不开下一层")
            eq(all.dungeon.babel_tower.floor, 1, "保存失败进度回滚")
            eq(all.dungeon.babel_tower.cleared[1], nil, "保存失败首通回滚")
            eq(#all.artifacts.bag, 0, "保存失败神器回滚")
            eq(all.artifacts.nextId, 1, "保存失败nextId回滚")
            eq(all.currency.gems or 0, 0, "保存失败黑钻回滚")
            eq(all.player.exp, 0, "保存失败经验回滚")
            eq(artifactCalls, 1, "一次开奖")
            eq(ratioCalls, 1, "数值只开奖一次")
            eq(Service.Challenge(1, 1), false, "保存失败不能重挑重抽")
            saveThrows = true
            Scene.handleClick(480,600,1440,760)
            eq(last(AT.TOWER_FLOOR_WIN).success, false, "保存异常也可重试")
            eq(sceneState.floor, 1, "异常仍同层")
            eq(artifactCalls, 1, "异常重试不重新开奖")
            saveThrows, saveOk, holdFloor = false, true, true
            eq(Scene.retryFloorWin(), true, "公开同层重试入口")
            local retry = held[1]
            Page.onActionResult(failure)
            eq(sceneState.phase, "floor_win", "旧失败不覆盖当前retry")
            Page.onActionResult(retry)
            eq(sceneState.floor, 2, "成功当前retry才开层2")
            eq(opens, 2, "失败重试不重开原层")
            eq(#all.artifacts.bag, 1, "重试神器不丢且只1")
            eq(all.artifacts.bag[1].quality, 2, "固定85%品质2")
            eq(all.artifacts.bag[1].valueRatio, 4321, "固定主值")
            eq(all.artifacts.bag[1].threatClearRatio, 6789, "固定次值")
            eq(artifactCalls, 1, "成功重试不重抽")
            eq(all.currency.gems, Config.getFloor(1).firstDiamond, "首钻仅成功一次")
            eq(all.artifacts.pityRare, 7, "免费不增pityRare")
            eq(all.artifacts.pityEpic, 12, "免费不增pityEpic")
            eq(all.artifacts.totalDraws, 19, "免费不增totalDraws")
            eq(all.artifacts.dailyFreeDrawDayId, 55, "不消耗每日免费抽")
        end)
        case("成功丢Floor回执超时重试固定结果", function()
            reset(); holdFloor = true; win(1)
            local old = held[1]
            eq(sceneState.floor, 1, "未回执不开层2")
            Scene.update(5.1)
            eq(sceneState.phase, "settlement_retry", "结算回执超时允许重试")
            eq(Scene.retryFloorWin(), true, "超时同层重送")
            eq(saveCount, 1, "已提交重试无新事务")
            local retry = held[2]
            Page.onActionResult(old); eq(opens, 1, "旧成功不能消费新request")
            Page.onActionResult(retry); Page.onActionResult(retry)
            eq(opens, 2, "当前retry成功只开层2一次")
        end)
        case("概率不命中和品质边界", function()
            for _, sample in ipairs({ {roll=.05,drop=false}, {roll=.99,drop=false},
                {roll=.0499,q=.7999,quality=1,drop=true}, {roll=0,q=.8,quality=2,drop=true},
                {roll=0,q=.9799,quality=2,drop=true}, {roll=0,q=.98,quality=3,drop=true} }) do
                reset(); randomSequence = {sample.roll}
                if sample.q then randomSequence[2] = sample.q end
                win(1)
                eq(#all.artifacts.bag, sample.drop and 1 or 0, "5%边界与80/18/2命中")
                if sample.drop then eq(all.artifacts.bag[1].quality, sample.quality, "品质概率边界") end
                eq(all.artifacts.totalDraws, 19, "掉落不变抽取计数")
            end
        end)
        case("背包满可靠重试不丢奖", function()
            reset(); randomSequence = {.01,.99}
            for i = 1, ArtifactDefs.MAX_BAG do
                all.artifacts.bag[i] = {id=tostring(i),artifactId=2,quality=1,valueRatio=2000}
            end
            local oldBag = all.artifacts.bag
            win(1)
            eq(last(AT.TOWER_FLOOR_WIN).success, false, "满包返回可重试失败")
            eq(all.artifacts.bag, oldBag, "满包失败恢复原bag别名")
            eq(#all.artifacts.bag, ArtifactDefs.MAX_BAG, "满包不删原神器")
            eq(all.dungeon.babel_tower.floor, 1, "满包不推进")
            table.remove(all.artifacts.bag)
            Scene.retryFloorWin()
            eq(last(AT.TOWER_FLOOR_WIN).success, true, "整理后同开奖成功")
            eq(#all.artifacts.bag, ArtifactDefs.MAX_BAG, "原物加掉落一件")
            local found = false
            for _, a in ipairs(all.artifacts.bag) do if a.valueRatio == 4321 and a.quality == 3 then found = true end end
            check(found, "满包中奖品质/数值保留")
            eq(artifactCalls, 1, "满包重试不重抽")
        end)
        case("退出整理后重挑不锁局也不重抽", function()
            reset(); randomSequence = {.01,.99}
            for i = 1, ArtifactDefs.MAX_BAG do
                all.artifacts.bag[i] = {id=tostring(i),artifactId=2,quality=1,valueRatio=2000}
            end
            win(1)
            local oldRun = sceneState.runId
            eq(sceneState.phase,"settlement_retry","满包显示两入口")
            Scene.handleClick(960,600,1440,760)
            eq(Scene.isActive(),false,"真实返回整理按钮关闭")
            eq(Service.FloorWin(1,1,{runId=oldRun}),false,"退出旧run不再结算")
            table.remove(all.artifacts.bag)
            randomValue = .99
            eq(Page.requestTowerChallenge(1),true,"整理后原组可重挑不永久锁")
            check(sceneState.runId ~= oldRun,"重挑建立新run")
            win(1)
            eq(last(AT.TOWER_FLOOR_WIN).success,true,"重挑同floor缓存奖品交付")
            eq(artifactCalls,1,"重挑神器不重新开奖")
            eq(last(AT.TOWER_FLOOR_WIN).artifacts[1].quality,3,"重挑保留原品质3")
            check(last(AT.TOWER_FLOOR_WIN).selectionId:find(sceneState.runId,1,true)==1,"续层选项身份来自新run")
            eq(last(AT.TOWER_FLOOR_WIN).rewards[2].name,ArtifactDefs.getName({artifactId=2}),"神器回执含名称")
            eq(last(AT.TOWER_FLOOR_WIN).rewards[2].iconPath,"image/神器图标/UI_icon_SQ_A2.png","神器回执图标")
            Scene.close()
            eq(Page.requestTowerChallenge(1),true,"成功消费后可再重打")
            win(1)
            eq(#last(AT.TOWER_FLOOR_WIN).artifacts,0,"成功后消费prize下次按新概率")
            eq(last(AT.TOWER_FLOOR_WIN).diamondReward,0,"成功后首奖不重复")
        end)
        case("旧档与重打无首奖", function()
            reset(6,nil,1)
            local previous = 6
            for floor = 1, 5 do
                win(floor)
                eq(last(AT.TOWER_FLOOR_WIN).firstClear, false, "旧floor历史不重发首奖" .. floor)
                eq(last(AT.TOWER_FLOOR_WIN).diamondReward, 0, "旧档重打0黑钻" .. floor)
                eq(last(AT.TOWER_FLOOR_WIN).playerExp, math.floor(StageExp.getExpPerMin(Config.getFloor(floor).monsterLevel)), "重打1分钟" .. floor)
                eq(all.dungeon.babel_tower.floor, previous, "重打不倒退已解锁floor")
                if floor < 5 then Panel.hide() end
            end
            reset(1,{["1"]=true,["5"]=true},1); win(1)
            eq(last(AT.TOWER_FLOOR_WIN).diamondReward,0,"字符串cleared首钻不重复")
            check(all.dungeon.babel_tower.cleared["5"] or all.dungeon.babel_tower.cleared[5], "保留其他历史cleared（允许Schema键规范化）")
            eq(Service.Challenge(1,1),true,"已解锁起点允许重打")
            -- Service默认起点跟旧floor所在组，不按floor直接挑战。
            Scene.close(); Service.ResetToDefault(1)
            all.dungeon.babel_tower.floor = 9
            local _, _, result = Service.Challenge(1)
            eq(result.floor,6,"默认floor9所在组6")
        end)
        case("末组111/112", function()
            reset(111,nil,111)
            eq(sceneState.endFloor,112,"末组只两层")
            win(111); eq(sceneState.floor,112,"111续112")
            win(112); eq(opens,2,"末组仅开两层")
            eq(last(AT.TOWER_FLOOR_WIN).continueRun,false,"112组末")
            eq(all.dungeon.babel_tower.floor,113,"保持全通旧floor113语义")
            eq(#shown,1,"末组唯一面板")
            eq(Service.Challenge(1),true,"全通默认可重打111")
            local _,_,initial=Service.Challenge(1)
            eq(initial.floor,111,"全通默认111非112")
            eq(Service.WaveWin(1,111,1),true,"重打末组单波")
            local _,_,reply=Service.FloorWin(1,111)
            eq(reply.diamondReward,0,"末组历史重打0黑钻")
        end)
        case("同步通知重入先消费floor", function()
            reset()
            local initial=last(AT.TOWER_CHALLENGE)
            local oldDirty=PDM.MarkDirty
            local nested, calls=nil,0
            PDM.MarkDirty=function(uid,key)
                if key=="dungeon" and calls==0 then
                    calls=calls+1
                    local success,_,result=Service.FloorWin(uid,1,{runId=initial.runId})
                    eq(success,true,"提交通知前已有floor缓存")
                    nested=result
                end
                return oldDirty(uid,key)
            end
            win(1); PDM.MarkDirty=oldDirty
            eq(nested and nested.floor,1,"重入回执原floor")
            eq(saveCount,1,"通知重入不再保存/发奖")
            eq(all.currency.gems,Config.getFloor(1).firstDiamond,"通知重入首钻一次")
        end)
        case("Pick同步重入和append后异常", function()
            reset(); win(1)
            local issued=last(AT.TOWER_FLOOR_WIN)
            local oldDirty=PDM.MarkDirty
            local nested=nil
            PDM.MarkDirty=function(uid,key)
                if key=="dungeon" and not nested then
                    local success,_,result=Service.PickBuff(uid,20,{runId=issued.runId,selectionId=issued.selectionId,floor=1,wave=1})
                    eq(success,true,"Pick通知前accepted已建")
                    nested=result
                end
                return oldDirty(uid,key)
            end
            click(1); PDM.MarkDirty=oldDirty
            eq(#all.dungeon.babel_tower.buffs,1,"Pick重入不双写")
            eq(opens,2,"Pick重入不重开层")
            win(2)
            PDM.MarkDirty=function() error("fixture dirty after append") end
            click(1); PDM.MarkDirty=oldDirty
            eq(last(AT.TOWER_PICK_BUFF).success,false,"append后异常失败身份保留")
            eq(#all.dungeon.babel_tower.buffs,2,"异常权威已追加一次")
            click(2); click(1)
            eq(#all.dungeon.babel_tower.buffs,2,"append后异常同卡重试不重复")
            eq(sceneState.floor,3,"异常重试不推进")
        end)
        case("Sweep零黑钻、旧经验、缓存重试", function()
            reset(6,nil,1)
            local before=all.currency.gems or 0
            randomSequence={.01,.5}; saveOk=false
            local success=Service.Sweep(1)
            eq(success,false,"Sweep保存失败")
            eq(all.dungeon.babel_tower.dailyUsed,0,"Sweep失败不消耗日次")
            eq(#all.artifacts.bag,0,"Sweep神器回滚")
            saveOk=true
            local _,_,result=Service.Sweep(1)
            eq(result.diamondReward,0,"Sweep恒0钻")
            eq(all.currency.gems or 0,before,"Sweep货币无钻")
            eq(result.playerExp,math.floor(StageExp.getExpPerMin(Config.getFloor(5).monsterLevel)*10),"Sweep保留原10分经验")
            eq(artifactCalls,1,"Sweep重试固定开奖")
            eq(#all.artifacts.bag,1,"Sweep免费神器只1")
            eq(all.artifacts.totalDraws,19,"Sweep不增抽卡计数")
            local _,_,second=Service.Sweep(1)
            eq(second.diamondReward,0,"第二Sweep无钻")
            eq(Service.Sweep(1),false,"日次上限")
        end)
        case("退出失败与清档", function()
            reset(); win(1); click(1)
            local pick=last(AT.TOWER_PICK_BUFF)
            Scene.close()
            eq(#all.dungeon.babel_tower.buffs,0,"退出清权威暗契")
            eq(Service.PickBuff(1,20,pick),false,"退出旧选择过期")
            eq(#sceneState.choiceQueue,0,"退出清Scene选择")
            reset(); win(1); Panel.hide(); panelOpen=true
            local tick=Tri.update; Tri.update=function() end; Scene.update(.1); Tri.update=tick
            eq(#all.dungeon.babel_tower.buffs,0,"失败面板清权威")
            eq(#sceneState.choiceQueue,0,"失败面板清FIFO")
            eq(Panel.isOpen(),false,"失败清择契Panel")
            reset(); win(1)
            local old=last(AT.TOWER_FLOOR_WIN)
            local closeCount=0
            sceneState.onClose=function() closeCount=closeCount+1 end
            Scene.resetToDefault(); Service.ResetToDefault(1)
            eq(closeCount,0,"清档不执行旧退出回调")
            eq(Scene.isActive(),false,"清档Scene inactive")
            eq(sceneState.floor,1,"清档floor1")
            eq(sceneState.runId,nil,"清档run清空")
            eq(next(sceneState.floorReceipts),nil,"清档floor缓存空")
            Page.onActionResult(old)
            eq(Scene.isActive(),false,"旧成功清档后不打开场景")
            eq(Service.FloorWin(1,1),false,"清档旧floor缓存失效")
        end)
        Scene.close()
        require("systems.StatusEffectManager").mount(nil)
        require("ui.battle.combat.BattleCombat").mount(nil)
        local unit={hp=100,atkInterval=1,classId=CC.MAGE}
        Runtime.initMechanics({20,28}); Runtime.applyMechanicInit({unit},{})
        check(math.abs(unit.atkInterval-1.5)<1e-7,"20+28倍率1.5")
        Runtime.applyMechanicInit({unit},{})
        check(math.abs(unit.atkInterval-1.5)<1e-7,"重复机制初始化不重乘")
        Runtime.initMechanics({20,28}); Runtime.applyMechanicInit({unit},{})
        check(math.abs(unit.atkInterval-1.5)<1e-7,"跨层同表不重乘")
        Runtime.cleanup()
        eq(Panel.isOpen(),false,"最终Panel清理")
        check(originals~=nil,"原模块快照只在内存")
    end,debug.traceback)
    if not ok then check(false,"fixture exception="..tostring(err)) end
    for i=#restores,1,-1 do
        local restored,restoreError=pcall(restores[i])
        if not restored then check(false,"restore exception="..tostring(restoreError)) end
    end
    print("[TowerBuff] SUMMARY assertions="..assertions.." failures="..failures)
    if failures==0 then print("[TowerBuff] ALL PASS")
    else log:Write(LOG_ERROR,"[TowerBuff] FAIL failures="..failures) end
    engine:Exit()
end
