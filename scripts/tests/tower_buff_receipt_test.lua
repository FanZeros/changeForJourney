-- 通天塔连续登塔与限时暗契：真实 GameAction -> Bridge -> Handler -> Service -> Page -> Scene/择契Panel。
-- 仅内存模块、保存出口与回执时机替身；不读玩家档、不启动Boot、不访问网络。
-- 独立脚本入口（生产稳定后再执行，不运行main）：
-- /workspace/.cli/UrhoXRuntime tests/tower_buff_receipt_test.lua -tapcode_dir=/workspace/changeForJourney -tool_mode -graphicsheadless -nosound
-- 契约：当前C选择 -> C+1..C+10有效；来源S待选 -> S+3可选、进入S+4失效。
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
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function near(actual, expected, label)
    check(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
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
        local realRollBuffs = patch(Config, "rollBuffs", function()
            return { Config.BUFFS_BY_ID[20], Config.BUFFS_BY_ID[28], Config.BUFFS_BY_ID[1] }
        end)
        local randomValue, randomSequence, randomCalls = .99, {}, 0
        local originalRandom = math.random
        patch(math, "random", function(a, b)
            if b ~= nil then return originalRandom(a, b) end
            if a ~= nil then return originalRandom(a) end
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
                unit.classId = CC.MAGE
                -- 间隔基准必须同时设置attrs与unit；prepareFloor真实stat重算不能把旧夹具1秒当外部变更。
                unit.attrs:setBase(AD.ATK_INTERVAL, unit.attrs:getBase(AD.ATK_INTERVAL) / unit.attrs:getActualInterval())
                unit.atkInterval = unit.attrs:getActualInterval()
                unit.attrs._forceFullHpOnRecalc = nil
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
            eq(saveCount, 1, "挑战入口单独保存离线来源")
            saveCount, persisted = 0, {} -- 以下只计挑战后的逐层结算，不混入入口持久化。
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
            near(teams[1][1].atkInterval, expected, label)
        end
        local function leaseIn(leases, id)
            for _, lease in ipairs(leases or {}) do if lease.id == id then return lease end end
            return nil
        end
        local function assertLease(leases, id, effective, expires, label)
            local lease = leaseIn(leases, id)
            check(lease ~= nil, label .. "存在租约" .. id)
            if not lease then return end
            eq(lease.effectiveFloor, effective, label .. "起效层")
            eq(lease.expiresFloor, expires, label .. "到期层")
        end
        local function snapshot(data, label)
            eq(type(data.buffLeases), "table", label .. "完整租约数组")
            eq(type(data.pendingSelections), "table", label .. "完整待选数组")
            eq(type(data.buffRevision), "number", label .. "权威版本")
            local seen = {}
            for _, lease in ipairs(data.buffLeases or {}) do
                eq(seen[lease.id], nil, label .. "同id唯一")
                seen[lease.id] = true
                check(Config.BUFFS_BY_ID[lease.id] ~= nil, label .. "真实卡id")
                check(type(lease.effectiveFloor) == "number" and type(lease.expiresFloor) == "number"
                    and lease.effectiveFloor <= lease.expiresFloor, label .. "合法租约范围")
            end
            local previous = 0
            for _, choice in ipairs(data.pendingSelections or {}) do
                eq(choice.id, data.runId .. ":floor:" .. choice.floor, label .. "待选id")
                eq(choice.wave, 1, label .. "待选wave")
                eq(choice.expiresFloor, choice.floor + 3, label .. "来源S最后S+3")
                check(choice.floor > previous, label .. "来源FIFO升序无重复")
                previous = choice.floor
                eq(type(choice.result), "table", label .. "待选结果")
                if choice.result then
                    eq(choice.result.nextFloor, choice.floor + 1, label .. "来源nextFloor")
                    eq(type(choice.result.buffChoices), "table", label .. "待选真实卡组")
                end
            end
        end
        local function selectionRequest(source)
            return {runId=source.runId, selectionId=source.selectionId, floor=source.floor, wave=1}
        end
        local function assertSceneSnapshot(data, label)
            eq(sceneState.buffRevision, data.buffRevision, label .. "Scene版本")
            check(same(sceneState.buffLeases, data.buffLeases), label .. "Scene完整租约")
            check(sceneState.buffLeases ~= data.buffLeases, label .. "租约数组不共享")
            eq(#sceneState.choiceQueue, #data.pendingSelections, label .. "待选长度")
            for i, issued in ipairs(data.pendingSelections) do
                local pending = sceneState.choiceQueue[i]
                check(pending ~= nil, label .. "待选存在" .. i)
                if pending then
                    eq(pending.selectionId, issued.id, label .. "待选身份" .. i)
                    eq(pending.floor, issued.floor, label .. "待选来源" .. i)
                    eq(pending.expiresFloor, issued.expiresFloor, label .. "待选期限" .. i)
                    check(same(pending.data, issued.result), label .. "待选卡组" .. i)
                    check(pending.data ~= issued.result, label .. "待选快照隔离" .. i)
                end
            end
        end
        local function case(name, fn)
            local restoreStart = #restores
            local success, message = xpcall(fn, debug.traceback)
            if not success then check(false, name .. " exception=" .. tostring(message)) end
            -- 新case的临时开奖/通知替身即使断言异常也必须恢复，不污染后续旧回归。
            for i = #restores, restoreStart + 1, -1 do
                local restored, restoreError = pcall(restores[i])
                if not restored then check(false, name .. " restore=" .. tostring(restoreError)) end
                restores[i] = nil
            end
        end
        case("checkpoint门禁与跨5/10连续推进", function()
            reset()
            eq(Config.MAX_FLOOR, 112, "保留112真实层")
            eq(sceneState.endFloor, 112, "本局终点独立于5层检查点")
            eq(Config.WAVES_PER_FLOOR, 1, "每层一波")
            eq(Service.Challenge(1, 6), false, "未通5不可挑战6")
            for _, bad in ipairs({ 0, 2, 5, 7, 112, 113, 1.5 }) do eq(Service.Challenge(1, bad), false, "拒绝非法/非起点" .. bad) end
            eq(Service.FloorWin(1, 1), false, "未清层不能结算")
            local diamonds, exp = 0, 0
            local runId = sceneState.runId
            for floor = 1, 10 do
                win(floor)
                local receipt = last(AT.TOWER_FLOOR_WIN)
                eq(receipt.floor, floor, "实际floor回执" .. floor)
                eq(receipt.firstClear, true, "每层独立首通" .. floor)
                eq(receipt.diamondReward, Config.getFloor(floor).firstDiamond, "逐层首钻" .. floor)
                eq(receipt.playerExp, math.floor(StageExp.getExpPerMin(Config.getFloor(floor).monsterLevel) * 2), "每层首通2分" .. floor)
                eq(receipt.continueRun, true, "跨检查点不结束" .. floor)
                eq(sceneState.runId, runId, "跨检查点保持run身份")
                diamonds, exp = diamonds + receipt.diamondReward, exp + receipt.playerExp
                Panel.hide()
            end
            eq(opens, 11, "通10自动开11")
            eq(saveCount, 10, "每层独立保存一次")
            eq(all.currency.gems, diamonds, "逐层首钻总和")
            eq(all.dungeon.babel_tower.floor, 11, "通10解锁11")
            eq(#shown, 0, "5/10无强制结束面板")
            eq(sceneState.runPlayerExp, exp, "局经验仅每层和无额外")
            eq(#sceneState.choiceQueue, 3, "跨检查点仅保留当前11仍有效的8/9/10待选")
            eq(sceneState.choiceQueue[1].floor, 8, "旧机会按来源期限淘汰不是无限FIFO")
            snapshot(last(AT.TOWER_FLOOR_WIN), "通10")
            assertSceneSnapshot(last(AT.TOWER_FLOOR_WIN), "通10")
            eq(#persisted, 10, "十层均已内存保存提交")
            eq(persisted[10].dungeon.babel_tower.floor, 11, "最后提交含下层进度")
            Scene.close()
            eq(all.currency.gems, diamonds, "退出不追回已到账钻")
            eq(#all.dungeon.babel_tower.buffs, 0, "退出清权威暗契")
            eq(Service.Challenge(1, 11), true, "退出后可从11重开")
        end)
        case("20唯一续期下一层生效与旧Pick不延寿", function()
            reset(); win(1); click(1)
            eq(#all.dungeon.babel_tower.buffs, 1, "Service20仅一个id")
            eq(#sceneState.buffIds, 1, "Scene20独立快照只1")
            check(sceneState.buffIds ~= all.dungeon.babel_tower.buffs, "Scene/PDM快照隔离")
            interval(1, "第2层进行中选20不重开不应用")
            local pick = copy(last(AT.TOWER_PICK_BUFF))
            snapshot(pick, "首选20")
            assertLease(pick.buffLeases, 20, 3, 12, "当前2选择")
            eq(pick.effectiveFloor, 3, "Pick起效不是来源1+1")
            eq(pick.expiresFloor, 12, "Pick到期按当前2+10")
            eq(pick.renewed, false, "首选非续期")
            Page.onActionResult(pick); Page.onActionResult(pick)
            eq(opens, 2, "重复Pick不重开")
            win(2); interval(.75, "第3层20只乘一次")
            click(1)
            local renewal = copy(last(AT.TOWER_PICK_BUFF))
            snapshot(renewal, "当前3续20")
            eq(renewal.renewed, true, "同id刷新不是追加")
            eq(#renewal.buffLeases, 1, "续期仍仅一份租约")
            assertLease(renewal.buffLeases, 20, 3, 13, "续期保留起效延到13")
            check(renewal.buffRevision > pick.buffRevision, "续期版本递增")
            interval(.75, "续期不改变当前3倍率")
            win(3); interval(.75, "第4层续期仍0.75不是平方")
            local revision = sceneState.buffRevision
            local success, _, replay = Service.PickBuff(1, 20, selectionRequest(pick))
            eq(success, true, "旧accepted仍幂等")
            eq(replay.buffRevision, pick.buffRevision, "重试返回原版本")
            assertLease(replay.buffLeases, 20, 3, 12, "重试旧Pick保留原期限")
            Page.onActionResult(replay); Page.onActionResult(pick)
            eq(sceneState.buffRevision, revision, "旧Pick不倒退新Floor版本")
            assertLease(sceneState.buffLeases, 20, 3, 13, "旧Pick不倒退或延寿")
            for floor = 4, 12 do win(floor); Panel.hide(); interval(.75, "续期有效层" .. (floor + 1)) end
            win(13)
            interval(1, "进入14续期到期还原间隔")
            eq(#sceneState.buffLeases, 0, "续期到期删除租约")
            eq(#all.dungeon.babel_tower.buffs, 0, "权威同id也已到期")
            Page.onActionResult(renewal); Page.onActionResult(pick)
            eq(#sceneState.buffLeases, 0, "到期后旧回执不能复活租约")
            interval(1, "旧Pick不延寿")
            eq(pick.buffs[1], 20, "旧Pick快照不污染")
        end)
        case("28组合与有效FIFO迟到", function()
            reset(); win(1); Panel.hide(); win(2)
            eq(Panel.isVisible(), false, "收起后累计不弹出")
            eq(#sceneState.choiceQueue, 2, "当前3累计两层有效FIFO")
            local first, second = copy(sceneState.choiceQueue[1]), copy(sceneState.choiceQueue[2])
            eq(Service.PickBuff(1, 28, selectionRequest(second)), false, "不能跳过FIFO首项")
            Panel.show()
            eq(panelState.request.floor, 1, "选项身份来源1不是当前3")
            holdPick = true; click(1)
            local pick = copy(held[1])
            click(2); eq(actionCounts[AT.TOWER_PICK_BUFF], 1, "pending不重复发送")
            -- 源1在当前3提交，故迟到当前4只测试已接受回执，不依赖过期边界解释。
            holdFloor = true; win(3)
            local floorResult = copy(held[2])
            Page.onActionResult(pick); Page.onActionResult(pick)
            eq(panelState.request.floor, 2, "迟到后FIFO第二原层2")
            Page.onActionResult(floorResult); Page.onActionResult(floorResult)
            holdFloor = false
            eq(sceneState.floor, 4, "当前Floor交付开4")
            eq(opens, 4, "重复Floor回执不重开")
            interval(.75, "第4层已提交20开始生效")
            holdPick = false; click(2)
            eq(panelState.request.floor, 3, "FIFO第三原层3")
            click(3); eq(#sceneState.choiceQueue, 0, "有效三组消费")
            eq(all.dungeon.babel_tower.buffs[1], 20, "FIFO20")
            eq(all.dungeon.babel_tower.buffs[2], 28, "FIFO28")
            interval(.75, "当前4选择28不改战斗")
            win(4); interval(1.5, "第5层20/28各乘一次")
            win(5); interval(1.5, "跨5到6不清空/重乘暗契")
            eq(#sceneState.buffIds, 3, "跨检查点三个未到期暗契")
            eq(Service.PickBuff(1, 20, selectionRequest(first)), true, "跨检查点旧accepted仍幂等")
            Page.onActionResult(pick); eq(#sceneState.buffIds, 3, "迟到Pick不重复追加")
            Scene.close()
            eq(Service.PickBuff(1, 20, selectionRequest(first)), false, "退出后旧accepted过期")
            Page.onActionResult(pick); eq(#sceneState.buffIds, 0, "退出后迟到Pick无污染")
        end)
        case("单次租约十层包含首尾与过期", function()
            reset(); win(1); click(1)
            local accepted = copy(last(AT.TOWER_PICK_BUFF))
            local currentBattle = upvalue(Tri.isOpen, "state").lanes
            interval(1, "当前2不受新租约影响")
            local activeFloors = 0
            for floor = 2, 11 do
                win(floor); Panel.hide()
                activeFloors = activeFloors + 1
                interval(.75, "单次20生效层" .. (floor + 1))
                assertLease(sceneState.buffLeases, 20, 3, 12, "单次租约不逐层延寿")
                snapshot(last(AT.TOWER_FLOOR_WIN), "十层回执" .. floor)
            end
            eq(activeFloors, 10, "从3到12恰十层")
            check(upvalue(Tri.isOpen, "state").lanes ~= currentBattle, "正常逐层重建战斗")
            win(12)
            interval(1, "进入13过期不留20倍率")
            eq(leaseIn(sceneState.buffLeases, 20), nil, "Scene过期移除")
            eq(#all.dungeon.babel_tower.buffs, 0, "Service过期移除")
            local success, _, replay = Service.PickBuff(1, 20, selectionRequest(accepted))
            eq(success, true, "过期后旧accepted只重放原结果")
            assertLease(replay.buffLeases, 20, 3, 12, "重放不重新起租")
            Page.onActionResult(accepted); Page.onActionResult(replay)
            win(13); interval(1, "旧Pick后下一层也不复活")
            eq(#last(AT.TOWER_FLOOR_WIN).buffLeases, 0, "权威后续Floor仍空")
        end)
        case("租约到期层保存失败不提前删除且重试只推进一次", function()
            reset(); win(1); click(1)
            for floor=2,11 do win(floor); Panel.hide() end
            eq(sceneState.floor,12,"进入租约最后有效层")
            interval(.75,"末有效层仍有20")
            local revision, opensBefore = sceneState.buffRevision, opens
            saveOk=false; win(12)
            eq(last(AT.TOWER_FLOOR_WIN).success,false,"到期切层保存失败")
            eq(sceneState.floor,12,"保存失败不进入过期13")
            eq(sceneState.buffRevision,revision,"保存失败不采纳到期版本")
            assertLease(sceneState.buffLeases,20,3,12,"失败保留当前层租约")
            eq(all.dungeon.babel_tower.buffs[1],20,"保存失败回滚权威buffs")
            eq(opens,opensBefore,"保存失败不开新层")
            saveOk=true; Scene.retryFloorWin()
            eq(last(AT.TOWER_FLOOR_WIN).success,true,"同层retry成功")
            eq(sceneState.floor,13,"retry成功才进入13")
            eq(#sceneState.buffLeases,0,"成功后才移除到期租约")
            eq(#all.dungeon.babel_tower.buffs,0,"成功提交空buffs")
            interval(1,"成功后新层恢复基础间隔")
            eq(opens,opensBefore+1,"retry只开一次下层")
        end)
        case("待选三层S+3可选与S+4过期", function()
            reset(); win(1)
            local source = copy(last(AT.TOWER_FLOOR_WIN))
            eq(source.choiceExpiresFloor, 4, "来源1到期4")
            Panel.hide(); win(2); win(3)
            eq(sceneState.floor, 4, "到来源1最后有效层4")
            eq(#sceneState.choiceQueue, 3, "当前4仍有1/2/3")
            eq(panelState.request.floor, 1, "最后有效层保留源1")
            Panel.show(); click(1)
            eq(last(AT.TOWER_PICK_BUFF).success, true, "源1当前4最后可选")
            assertLease(last(AT.TOWER_PICK_BUFF).buffLeases, 20, 5, 14, "延迟选择按当前4起租")
            interval(1, "迟选不更改当前4")
            reset(); win(1)
            source = copy(last(AT.TOWER_FLOOR_WIN))
            Panel.hide(); win(2); win(3); win(4)
            eq(sceneState.floor, 5, "进入来源1的S+4")
            eq(#sceneState.choiceQueue, 3, "淘汰源1仅留2/3/4")
            eq(panelState.request.floor, 2, "面板切到有效FIFO源2")
            eq(Panel.isVisible(), false, "源1过期不强行重新弹出")
            local floorResult = copy(last(AT.TOWER_FLOOR_WIN))
            local revision = floorResult.buffRevision
            eq(Service.PickBuff(1, 20, selectionRequest(source)), false, "Service拒绝S+4未提交旧候选")
            eq(#all.dungeon.babel_tower.buffs, 0, "过期选择不写权威")
            eq(sceneState.buffRevision, revision, "过期拒绝无版本变更")
            Page.onActionResult(source)
            assertSceneSnapshot(floorResult, "旧Floor不复活过期待选")
            Panel.show(); click(2)
            eq(last(AT.TOWER_PICK_BUFF).success, true, "过期后有效源2可继续选择")
            assertLease(last(AT.TOWER_PICK_BUFF).buffLeases, 28, 6, 15, "源2当前5新租约")
        end)
        case("Pick回执彻底丢失后Floor权威恢复", function()
            reset(); win(1)
            holdPick = true; click(1)
            local lost = copy(held[1])
            eq(panelState.pending, true, "已提交但Panel等待")
            eq(#sceneState.buffLeases, 0, "丢回执前Scene不猜测成功")
            interval(1, "当前2不提前应用")
            win(2)
            local authoritative = copy(last(AT.TOWER_FLOOR_WIN))
            snapshot(authoritative, "丢Pick后的Floor")
            assertSceneSnapshot(authoritative, "Floor恢复已提交选择")
            assertLease(sceneState.buffLeases, 20, 3, 12, "恢复原租期不另起租")
            eq(#sceneState.choiceQueue, 1, "已消费源1不复活")
            eq(panelState.request.floor, 2, "Floor使面板换为源2")
            eq(panelState.pending, false, "Floor释放丢回执pending")
            interval(.75, "恢复后第3层实际应用")
            local revision, opensBefore = sceneState.buffRevision, opens
            Page.onActionResult(lost); Page.onActionResult(lost)
            eq(sceneState.buffRevision, revision, "迟到丢包不能回滚")
            eq(panelState.request.floor, 2, "迟到旧Pick不吃新待选")
            eq(opens, opensBefore, "恢复不重开当前战斗")
        end)
        case("旧Pick后到新Floor及新Pick先到旧Floor", function()
            -- A：Pick先提交、Floor后提交，但Floor先交付。新Floor必须恢复租约并清旧pending。
            reset(); win(1); holdPick = true; click(1)
            local oldPick = copy(held[1])
            holdFloor = true; win(2)
            local newFloor = copy(held[2])
            check(newFloor.buffRevision > oldPick.buffRevision, "A权威版本先Pick后Floor")
            Page.onActionResult(newFloor)
            local revision, queue = sceneState.buffRevision, copy(sceneState.choiceQueue)
            Page.onActionResult(oldPick); Page.onActionResult(newFloor); Page.onActionResult(oldPick)
            eq(sceneState.buffRevision, revision, "A旧Pick不覆盖新Floor")
            check(same(sceneState.choiceQueue, queue), "A乱序不消费下一待选")
            interval(.75, "A新Floor起效20")
            eq(opens, 3, "A只开3层")
            -- B：先在Scene当前2锁定Pick发送，再延迟传输；Floor先在Service提交到3。
            reset(); win(1)
            local sender, delayed = Action.sendAction, {}
            patch(Action, "sendAction", function(action, params)
                if action == AT.TOWER_PICK_BUFF then delayed.params = copy(params); return true end
                return sender(action, params)
            end)
            click(1)
            eq(panelState.pending, true, "B先锁定真实Panel请求")
            holdFloor = true; win(2)
            local oldFloor = copy(held[1])
            eq(sceneState.floor, 2, "B旧Floor等待交付")
            holdPick = true; sender(AT.TOWER_PICK_BUFF, delayed.params)
            local newPick = copy(held[2])
            check(newPick.buffRevision > oldFloor.buffRevision, "B权威版本先Floor后Pick")
            assertLease(newPick.buffLeases, 20, 4, 13, "B以Service当前3起租")
            snapshot(newPick, "B完整Pick含源2")
            Page.onActionResult(newPick)
            assertSceneSnapshot(newPick, "B先收更高Pick版本")
            eq(panelState.request.floor, 2, "B Pick完整快照恢复尚未见的源2")
            interval(1, "B新Pick不改Scene当前2")
            Page.onActionResult(oldFloor); Page.onActionResult(oldFloor); Page.onActionResult(newPick)
            eq(sceneState.floor, 3, "B旧Floor仍负责推进3")
            eq(sceneState.buffRevision, newPick.buffRevision, "B旧Floor不倒退版本")
            assertLease(sceneState.buffLeases, 20, 4, 13, "B保留新Pick租约")
            eq(#sceneState.choiceQueue, 1, "B源2不重复不丢失")
            eq(panelState.request.floor, 2, "B源2身份保留")
            interval(1, "B新租约第3层未到起效层")
            holdFloor = false; win(3)
            interval(.75, "B第4层才应用20")
            eq(opens, 4, "B乱序每层只开一次")
        end)
        case("畸形Floor快照不能消费身份收益且同回执可恢复", function()
            reset(); holdFloor = true; win(1)
            local good = copy(held[1])
            local beforeRequest = sceneState.settlementRequest
            local variants = {
                function(d) d.buffLeases = nil end,
                function(d) d.buffRevision = nil end,
                function(d) d.buffLeases = {{id=20,effectiveFloor=8,expiresFloor=7}} end,
                function(d) d.buffLeases = {{id=20,effectiveFloor=2,expiresFloor=12},{id=20,effectiveFloor=2,expiresFloor=12}} end,
                function(d) d.pendingSelections = nil end,
                function(d) d.pendingSelections[1].expiresFloor = 5 end,
                function(d) d.pendingSelections[1].result = nil end,
                function(d) d.pendingSelections[1].result.buffChoices = nil end,
            }
            for i, corrupt in ipairs(variants) do
                local bad = copy(good); corrupt(bad)
                eq(Scene.onFloorWinResult(bad), false, "畸形Floor拒绝" .. i)
                eq(sceneState.settlementRequest, beforeRequest, "畸形Floor保留请求" .. i)
                eq(sceneState.floorReceipts[1], nil, "畸形Floor未消费缓存" .. i)
                eq(sceneState.runPlayerExp, 0, "畸形Floor未汇总经验" .. i)
                eq(#sceneState.runRewards, 0, "畸形Floor未汇总收益" .. i)
                eq(sceneState.floor, 1, "畸形Floor不推进" .. i)
                eq(opens, 1, "畸形Floor不开战斗" .. i)
            end
            Page.onActionResult(good)
            eq(sceneState.floor, 2, "修复快照同身份可成功")
            eq(sceneState.runPlayerExp, good.playerExp, "修复仅汇总一次经验")
            eq(saveCount, 1, "拒绝客户端坏快照不重复权威保存")
            assertSceneSnapshot(good, "修复Floor")
        end)
        case("畸形Pick快照不采纳版本不消费pending", function()
            reset(); win(1); holdPick = true; click(1)
            local good = copy(held[1])
            local revision = sceneState.buffRevision
            local variants = {
                function(d) d.buffLeases[1].expiresFloor = 1 end,
                function(d) d.buffLeases[2] = copy(d.buffLeases[1]) end,
                function(d) d.pendingSelections = nil end,
                function(d) d.pendingSelections = {{id=d.runId..":floor:2",floor=2,wave=1,
                    expiresFloor=999,result={nextFloor=3,buffChoices={Config.BUFFS_BY_ID[20]}}}} end,
            }
            for i, corrupt in ipairs(variants) do
                local bad = copy(good); corrupt(bad)
                Page.onActionResult(bad)
                eq(sceneState.buffRevision, revision, "畸形Pick不采纳版本" .. i)
                eq(#sceneState.buffLeases, 0, "畸形Pick不写租约" .. i)
                eq(panelState.pending, true, "畸形Pick不释放pending" .. i)
                eq(#sceneState.choiceQueue, 1, "畸形Pick不消费选择" .. i)
            end
            Page.onActionResult(good)
            assertSceneSnapshot(good, "修复Pick")
            eq(Panel.isOpen(), false, "修复Pick才消费待选")
            eq(opens, 2, "畸形及修复Pick均不重开战斗")
        end)
        case("过期候选重新入池使用真实Config.rollBuffs", function()
            reset(); win(1); click(1)
            local excludes = {}
            patch(Config, "rollBuffs", function(count, excluded)
                excludes[#excludes + 1] = copy(excluded)
                return realRollBuffs(count, excluded)
            end)
            local function contains(list, id)
                for _, value in ipairs(list) do if value == id then return true end end
                return false
            end
            for floor = 2, 11 do
                win(floor); Panel.hide()
                check(contains(excludes[#excludes], 20), "20未到期须从真实候选池排除" .. floor)
                for _, choice in ipairs(last(AT.TOWER_FLOOR_WIN).buffChoices) do
                    check(choice.id ~= 20, "真实roll不抽活跃20" .. floor)
                end
            end
            -- 精确命中20所在权重区间，不替换roll实现、不靠多次随机碰运气。
            local total, before = 0, 0
            for _, buff in ipairs(Config.BUFFS) do
                total = total + buff.weight
                if buff.id < 20 then before = before + buff.weight end
            end
            randomSequence = {.99, (before + Config.BUFFS_BY_ID[20].weight * .5) / total, .99, .99}
            win(12)
            check(not contains(excludes[#excludes], 20), "进入13到期20不再排除")
            local result = last(AT.TOWER_FLOOR_WIN)
            eq(result.buffChoices[1].id, 20, "真实加权抽取重新抽到过期20")
            eq(leaseIn(result.buffLeases, 20), nil, "回池不等于自动重获租约")
            -- 旧有效FIFO来源10/11先选非20，固定两次，失败也不能形成死循环。
            for sourceFloor = 10, 11 do
                eq(panelState.request.floor, sourceFloor, "真实roll保留有效FIFO来源")
                Panel.show(); click(1)
                eq(last(AT.TOWER_PICK_BUFF).success, true, "先消费仍有效旧FIFO")
            end
            eq(panelState.request.floor, 12, "轮到回池卡来源12")
            Panel.show(); click(1)
            local repick = last(AT.TOWER_PICK_BUFF)
            eq(repick.buffId, 20, "重新入池卡可正式选择")
            eq(repick.renewed, false, "过期后是新租约不是续期")
            assertLease(repick.buffLeases, 20, 14, 23, "重新选择按当前13起租")
            interval(1, "重新选择不改变当前13")
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
        case("整局1到112逐层提交且只终层结束", function()
            reset()
            local diamonds, exp = 0, 0
            for floor = 1, 112 do
                win(floor)
                local result = last(AT.TOWER_FLOOR_WIN)
                diamonds, exp = diamonds + result.diamondReward, exp + result.playerExp
                eq(result.continueRun, floor < 112, "仅112结束" .. floor)
                if floor < 112 then Panel.hide() end
            end
            eq(opens, 112, "整局每真实层只开一次")
            eq(#shown, 1, "全局唯一终局面板")
            eq(shown[1].floor, 112, "终局为112层")
            eq(shown[1].rewards[1].amount, diamonds, "全局黑钻只展示已发总和")
            eq(shown[1].rewards[2].amount, exp, "全局经验汇总")
            eq(all.currency.gems, diamonds, "终局汇总不二次发奖")
            eq(all.dungeon.babel_tower.floor, 113, "整局全通进度113")
            eq(#sceneState.choiceQueue, 0, "终层清FIFO")
            eq(#all.dungeon.babel_tower.buffs, 0, "终层清权威暗契")
            local before = all.currency.gems
            Page.onActionResult(last(AT.TOWER_FLOOR_WIN))
            eq(#shown, 1, "终层重复回执不再弹面板")
            eq(all.currency.gems, before, "终层重复回执不发奖")
        end)
        case("词条耗尽空选项仍跨检查点继续", function()
            reset()
            local oldRoll = Config.rollBuffs
            Config.rollBuffs = function() return {} end
            for floor = 1, 6 do
                Action.sendAction(AT.TOWER_WAVE_WIN, { floor=floor, wave=1, runId=sceneState.runId })
                eq(last(AT.TOWER_FLOOR_WIN).success, true, "无候选也正常提交" .. floor)
                eq(sceneState.floor, floor + 1, "无候选继续" .. floor)
                eq(#sceneState.choiceQueue, 0, "空候选不生成待选")
                eq(Panel.isOpen(), false, "空候选不弹空面板")
            end
            Config.rollBuffs = oldRoll
        end)
        case("失败与撤退展示已提交收益不重复发奖", function()
            reset()
            for floor=1,6 do win(floor); Panel.hide() end
            local diamonds, exp = all.currency.gems, all.player.exp
            local finishLose = upvalue(Tri.update, "finishLose")
            finishLose()
            Scene.update(1.3)
            eq(#shown, 1, "真实失败边界展示摘要")
            eq(shown[1].isWin, false, "当前未通层仍失败")
            eq(shown[1].floor, 7, "失败层7不是已通6")
            eq(shown[1].rewards[1].amount, diamonds, "失败展示前六层已到账黑钻")
            eq(all.currency.gems, diamonds, "失败摘要不重复发钻")
            eq(all.player.exp, exp, "失败摘要不重复发经验")
            eq(all.dungeon.babel_tower.floor, 7, "失败不发当前层进度")
            eq(#sceneState.choiceQueue, 0, "真实失败清FIFO")
            panelOpen = false -- 真实BRP.close先清open，再调用onClose。
            shown[1].onClose()
            eq(Scene.isActive(), false, "关闭失败摘要结束本局")
            eq(Page.requestTowerChallenge(6), true, "失败后从检查点6重开")
            win(6)
            eq(last(AT.TOWER_FLOOR_WIN).diamondReward, 0, "重开不重复发第6层首钻")
            Panel.hide()
            eq(Tri.requestRetreat(), true, "真实撤退确认入口")
            local layout = Scene.getLayout(1920,1080)
            local rect = require("ui.tower.TowerLayout").confirm(layout).retreat
            Scene.handleClick(rect.x+rect.w*.5,rect.y+rect.h*.5,1920,1080)
            Scene.update(1.3)
            eq(#shown, 2, "主动撤退也展示已获摘要")
            eq(shown[2].isWin, false, "撤退不伪造成功")
            eq(all.currency.gems, diamonds, "撤退不重发历史首钻")
        end)
        case("失败清理同步清档不重开旧面板", function()
            reset(); win(1); Panel.hide()
            sceneState.onCleanup = function() Scene.resetToDefault(); Service.ResetToDefault(1) end
            upvalue(Tri.update, "finishLose")()
            Scene.update(1.3)
            eq(Scene.isActive(), false, "同步清档后保持inactive")
            eq(Tri.isOpen(), false, "同步清档后不遍历旧lane")
            eq(#shown, 0, "清档不能被旧失败回调重开面板")
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
            eq(#all.dungeon.babel_tower.buffs,1,"异常续期权威同id仍唯一")
            click(2); click(1)
            eq(#all.dungeon.babel_tower.buffs,1,"续期后异常同卡重试不重复")
            assertLease(sceneState.buffLeases,20,3,13,"异常续期保留一次刷新")
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
        case("塔结算同步回执保持新波ETS挂载", function()
            reset()
            local ETS = require("systems.ExtraTalentSystem")
            local towerState = upvalue(Tri.isOpen, "state")
            local finishWin = upvalue(Tri.update, "finishWin")
            local oldLanes = towerState.lanes
            ETS.mount(oldLanes[2].etsState)
            finishWin() -- 真正塔胜利边界，Action回执同步关闭旧波并打开新波。
            eq(sceneState.floor, 2, "真实finishWin同步推进第2层")
            eq(sceneState.wave, 1, "下一层仍为单波")
            check(towerState.lanes ~= oldLanes, "同步胜利回执替换旧lane表")
            eq(ETS.mountedState(), towerState.lanes[3].etsState, "结算返回保持新波最后lane挂载")
            check(ETS.mountedState() ~= oldLanes[2].etsState, "结算不能重新挂回进入前的旧lane")
            eq(opens, 2, "同步胜利只重开一次")
        end)
        case("塔结算同步close保持宿主ETS挂载", function()
            reset()
            local ETS = require("systems.ExtraTalentSystem")
            local towerState = upvalue(Tri.isOpen, "state")
            local finishWin = upvalue(Tri.update, "finishWin")
            local originalSender = Action.sendAction
            local hostState = towerState.hostExtraTalents
            ETS.mount(towerState.lanes[2].etsState)
            Action.sendAction = function(action, params)
                if action == AT.TOWER_WAVE_WIN then Scene.close(); return true end
                return originalSender(action, params)
            end
            finishWin()
            Action.sendAction = originalSender
            eq(Tri.isOpen(), false, "同步胜利sender关闭塔场")
            eq(ETS.mountedState(), hostState, "结算返回保持close已恢复的宿主ETS域")
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
        local comboUnit = assert(HC.createHero(9, 1))
        comboUnit.attrs:setBase(AD.COMBO_DMG_UP, 40)
        comboUnit.hp = comboUnit.attrs:get(AD.MAX_HP)
        for floor = 1, 112 do
            Runtime.initMechanics({18})
            Runtime.applyMechanicInit({comboUnit},{})
            eq(comboUnit.attrs:get(AD.COMBO_DMG_UP), 80, "单张18跨层不重复增长" .. floor)
        end
        comboUnit.attrs:setBase(AD.COMBO_DMG_UP, 60)
        Runtime.initMechanics({18}); Runtime.applyMechanicInit({comboUnit},{})
        eq(comboUnit.attrs:get(AD.COMBO_DMG_UP), 120, "基础属性更新后仍只翻倍一次")
        Runtime.cleanup()
        case("Runtime prepareFloor移除stat与mechanic且保留外部modifiers", function()
            local UA = require("systems.UnitAttributes")
            local function make(classId, id)
                local attrs = UA.create({maxHp=1000,physAtk=100,magAtk=100,atkInterval=2,comboDmgUp=40})
                attrs:setBase(AD.COMBO_DMG_UP,40)
                attrs:addModifier("fixture_equipment", {{key=AD.PHYS_ATK_BONUS,flat=11}})
                attrs:addModifier("fixture_talent", {{key=AD.COMBO_DMG_UP,flat=10}})
                attrs:addModifier("fixture_artifact", {{key=AD.HP_BONUS,flat=20}})
                attrs:addModifier("not_tower_buff_1", {{key=AD.CRIT_DMG,flat=7}})
                attrs:addModifier("tower_external_keep", {{key=AD.DODGE,flat=3}})
                attrs._forceFullHpOnRecalc = nil
                attrs.final[AD.HP] = attrs:get(AD.MAX_HP)
                return {heroId=id,instanceId=id,classId=classId,attrs=attrs,
                    hp=attrs:get(AD.HP),maxHp=attrs:get(AD.MAX_HP),atkInterval=attrs:getActualInterval()}
            end
            local mage, warrior, ranger, priest = make(CC.MAGE,901), make(CC.WARRIOR,902), make(CC.RANGER,903), make(CC.PRIEST,904)
            local allies = {mage,warrior,ranger,priest}
            local external = {}
            for i, unit in ipairs(allies) do external[i] = copy(unit.attrs.modifiers) end
            local function prepare(ids)
                Runtime.prepareFloor(allies,ids)
                Runtime.applyMechanicInit(allies,{})
            end
            prepare({1,3,7,9,17,18,20,26,28,31,35})
            near(mage.attrs:get(AD.PHYS_ATK_BONUS),19,"stat1含原装备11+8")
            near(mage.attrs:get(AD.COMBO_DMG_UP),124,"7+18在原50上先加12再翻倍")
            near(mage.atkInterval,2/1.2*.75*2,"9+20+28法师组合")
            near(ranger.atkInterval,2/1.45*.75,"9+31先算攻速再乘20")
            eq(Runtime.isHealBlocked(warrior),true,"26禁疗生效")
            check(mage.attrs.modifiers.tower_buff_1~=nil,"stat具名modifier已建立")
            check(ranger.attrs.modifiers["tower_ranger_support_903"]~=nil,"31modifier已建立")
            Runtime.onEnemyKill(mage)
            eq(Runtime.getKillHpStack(),5,"17击杀HP叠层")
            check(mage.attrs.modifiers.tower_kill_hp_stack~=nil,"17实时HP modifier")
            for _, unit in ipairs(allies) do
                unit.hp=math.floor(unit.maxHp*.5)
                unit.attrs.final[AD.HP]=unit.hp
            end
            local oldRatios = {}
            for i, unit in ipairs(allies) do oldRatios[i]=unit.hp/unit.maxHp end
            prepare({})
            near(mage.atkInterval,2,"20/28/9到期还原间隔")
            near(ranger.atkInterval,2,"31与20同时到期还原射手间隔")
            near(mage.attrs:get(AD.PHYS_ATK_BONUS),11,"stat1移除只留装备")
            near(mage.attrs:get(AD.COMBO_DMG_UP),50,"18/7移除保留基础与天赋")
            eq(Runtime.isHealBlocked(warrior),false,"26到期解除禁疗")
            eq(Runtime.getKillHpStack(),0,"17到期清叠层")
            eq(Runtime.getDamageMultiplier(mage,{hp=100,maxHp=100}),1,"28到期清额外伤害")
            for i, unit in ipairs(allies) do
                check(same(unit.attrs.modifiers,external[i]),"仅清塔自有族保留外部modifier"..i)
                eq(unit.maxHp,1200,"3/26/35/17移除保留外部20%HP"..i)
                eq(unit.hp,math.floor(oldRatios[i]*1200+.5),"清HP后保持原血量比例"..i)
                eq(unit.attrs:get(AD.HP),unit.hp,"HP与attrs同步"..i)
            end
            -- 不同租约逐个退出，不能只有全空路径才清理。
            prepare({20,28}); near(mage.atkInterval,3,"20/28合成1.5倍基础")
            prepare({20}); near(mage.atkInterval,1.5,"只28到期保留20")
            prepare({28}); near(mage.atkInterval,4,"只20到期保留28")
            prepare({}); near(mage.atkInterval,2,"均到期原基础")
            prepare({20,20,28,28,18,18,1,1})
            near(mage.atkInterval,3,"prepare重复id去重不叠乘")
            eq(mage.attrs:get(AD.COMBO_DMG_UP),100,"重复18只翻倍一次")
            eq(mage.attrs:get(AD.PHYS_ATK_BONUS),19,"重复stat1仅一次")
            prepare({}); mage.attrs:setBase(AD.ATK_INTERVAL,3); mage.atkInterval=3
            prepare({20}); near(mage.atkInterval,2.25,"外部新基础正确乘20")
            prepare({}); near(mage.atkInterval,3,"到期恢复外部新基础非旧2")
            Runtime.cleanup()
        end)
        case("Runtime死亡单位清旧塔属性先建新stat再由开层复活", function()
            local UA = require("systems.UnitAttributes")
            local attrs = UA.create({maxHp=1000,atkInterval=2})
            local dead = {heroId=991,instanceId=991,classId=CC.MAGE,attrs=attrs,hp=1000,maxHp=1000,atkInterval=2}
            attrs.final[AD.HP]=1000
            Runtime.prepareFloor({dead},{1,3,20,28})
            Runtime.applyMechanicInit({dead},{})
            near(dead.atkInterval,3,"死亡前有20/28")
            dead.hp=0; attrs.final[AD.HP]=0
            Runtime.prepareFloor({dead},{2,9})
            eq(dead.hp,0,"prepare不擅自复活")
            eq(attrs:get(AD.HP),0,"死亡attrs仍0")
            eq(dead.maxHp,1000,"死者旧HP buff已移除")
            eq(attrs.modifiers.tower_buff_1,nil,"死者旧stat1清除")
            eq(attrs.modifiers.tower_buff_3,nil,"死者旧stat3清除")
            check(attrs.modifiers.tower_buff_2~=nil,"死者下一层新stat2不漏应用")
            check(attrs.modifiers.tower_buff_9~=nil,"死者下一层攻速stat9不漏应用")
            near(dead.atkInterval,2/1.2,"死亡仍恢复旧机制再应用新攻速")
            attrs:fillHp(); dead.hp=attrs:get(AD.HP); dead.maxHp=attrs:get(AD.MAX_HP)
            Runtime.applyMechanicInit({dead},{})
            near(dead.atkInterval,2/1.2,"复活开层不残留20/28倍率")
            eq(dead.hp,1000,"仅正式满血边界复活")
            Runtime.prepareFloor({dead},{})
            eq(attrs:get(AD.MAG_ATK_BONUS),0,"新stat2下次也可移除")
            near(dead.atkInterval,2,"新stat9移除还原")
            Runtime.cleanup()
        end)
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
