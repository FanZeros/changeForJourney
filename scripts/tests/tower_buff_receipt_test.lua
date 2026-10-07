-- B04：真实 Panel -> GameAction -> LocalActionBridge -> Handler -> Service -> DungeonPage -> Scene。
-- 合成内存模块，不读取/恢复玩家存档；仅隔离绘图初始化、保存出口和消息交付时机。
-- 跑法：UrhoXRuntime tests/tower_buff_receipt_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless -nosound
local assertions, failures = 0, 0
local restores = {}

local function check(value, label)
    assertions = assertions + 1
    print((value and "[TowerBuff][PASS] " or "[TowerBuff][FAIL] ") .. label)
    if not value then failures = failures + 1 end
end

local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

local function patch(owner, key, value)
    local old = owner[key]
    restores[#restores + 1] = function() owner[key] = old end
    owner[key] = value
    return old
end

local function upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value, i end
        if not name then break end
    end
    error("fixture cannot locate upvalue " .. wanted)
end

local function getState(fn)
    return upvalue(fn, "state")
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
        local Config = require("config.TowerConfig")
        local Runtime = require("systems.TowerBuffRuntime")
        local HC = require("config.HeroConfig")
        local CC = require("config.ClassConfig")
        local CP = require("ui.character.panel.CharacterPanel")
        local SEM = require("systems.StatusEffectManager")
        local BC = require("ui.battle.combat.BattleCombat")
        local AD = require("systems.AttributeDef")
        local GameState = require("core.GameState")
        local gameSnapshot = GameState.exportSave()
        restores[#restores + 1] = function() GameState.importSave(gameSnapshot) end
        local sceneState = getState(Scene.isActive)
        local all = Dispatcher.getAll()
        local originals = {}
        for k, v in pairs(all) do originals[k] = v end
        restores[#restores + 1] = function()
            Scene.close()
            Page.close()
            for k in pairs(all) do all[k] = nil end
            for k, v in pairs(originals) do all[k] = v end
        end
        for k in pairs(all) do all[k] = nil end
        all.battle = { maxStageId = 2001, clearedStages = { [1905] = true } }
        all.player = { name = "B04 fixture", level = 1, exp = 0 }
        all.currency = {}
        all.heroes = { roster = {}, teams = {}, deployed = {} }
        all.dungeon = { babel_tower = { floor = 1, cleared = {}, buffs = {}, dailyUsed = 0 } }
        patch(require("boot.StandaloneSave"), "Flush", function() return true end)
        patch(require("rules.redeem.RedeemService"), "Init", function() end)
        local teams = {}
        patch(CP, "getDeployedTeam", function(t) return teams[t or 1] or {} end)
        -- openTower 只定位选关表；复制 StandaloneBoot.run 的回调接线，
        -- 由真实首层行点击调用 requestTowerChallenge，挑战与回执均不替身。
        -- 不运行完整 Boot（避免读取玩家档），也不创建 NanoVG 上下文。
        local Dialog = require("ui.battle.stage.StageSelectDialog")
        local oldDungeonSelect, dungeonSelectIndex = upvalue(Dialog.handleInput, "onDungeonSelect")
        Dialog.setOnDungeonSelect(function(dungeonId, _teamIdx, floor)
            if dungeonId ~= "babel_tower" then return false end
            return Page.requestTowerChallenge(floor)
        end)
        restores[#restores + 1] = function()
            Dialog.close()
            debug.setupvalue(Dialog.handleInput, dungeonSelectIndex, oldDungeonSelect)
        end
        local panelState = getState(Panel.isOpen)
        local kwCards = upvalue(Panel.handleClick, "kwCards")
        for _, card in ipairs(kwCards) do
            patch(card, "isOpen", function() return false end)
            patch(card, "handleInput", function() return false end)
        end
        ---@type table[]
        local receipts = {}
        ---@type table[]
        local queue = {}
        local hold = false
        patch(Msg, "handleActionResult", function(data)
            receipts[#receipts + 1] = data
            if hold and data.action == AT.TOWER_PICK_BUFF then queue[#queue + 1] = data
            else Page.onActionResult(data) end
        end)
        patch(Config, "rollBuffs", function()
            return { Config.BUFFS_BY_ID[20], Config.BUFFS_BY_ID[28], Config.BUFFS_BY_ID[1] }
        end)
        Bridge.init()
        local Store = require("core.PlayerStore")
        Store.Init()
        restores[#restores + 1] = function() Store.Cleanup() end
        local actionCounts = {}
        local oldSend = Action.sendAction
        patch(Action, "sendAction", function(action, params)
            actionCounts[action] = (actionCounts[action] or 0) + 1
            return oldSend(action, params)
        end)
        local opens = 0
        local oldOpen = Tri.open
        patch(Tri, "open", function(opts)
            opens = opens + 1
            return oldOpen(opts)
        end)
        local function last(action)
            for i = #receipts, 1, -1 do
                if receipts[i].action == action then return receipts[i] end
            end
            error("missing receipt " .. action)
        end
        local function reset()
            Scene.close()
            Page.close()
            hold, queue, receipts, actionCounts, opens = false, {}, {}, {}, 0
            Dispatcher.set("battle", { maxStageId = 2001, clearedStages = { [1905] = true } })
            Dispatcher.set("dungeon", { babel_tower = { floor = 1, cleared = {}, buffs = {}, dailyUsed = 0 } })
            teams = {}
            for t = 1, 3 do
                local unit = assert(HC.createHero(9, 1))
                unit.classId = CC.MAGE
                unit.atkInterval = 1
                unit.attrs.final[AD.HP] = unit.attrs:get(AD.MAX_HP)
                unit.hp, unit.maxHp = unit.attrs:get(AD.HP), unit.attrs:get(AD.MAX_HP)
                teams[t] = { unit }
            end
            eq(Page.openTower(), true, "本地真实openTower入口")
            -- 当前选关塔分组首行：MID_X=315/ROW_Y0=790/ROW_H=168。
            -- 不再点旧详情挑战按钮(750,1633)，该点现在是第5层行。
            check(Dialog.isOpen(), "openTower只定位真实选关表")
            eq(actionCounts[AT.TOWER_CHALLENGE], nil, "未点层行不发送挑战")
            eq(Dialog.handleInput(600, 874), true, "真实选关首层行点击")
            eq(actionCounts[AT.TOWER_CHALLENGE], 1, "首层行只发送一次真实挑战")
            eq(Scene.isActive(), true, "正式DungeonPage打开Scene")
            eq(PDM.GetModule(1, "dungeon"), all.dungeon, "PDM与Dispatcher正式同表")
        end
        local function win(wave)
            Action.sendAction(AT.TOWER_WAVE_WIN, { floor = 1, wave = wave })
            eq(last(AT.TOWER_WAVE_WIN).success, true, "真实WaveWin成功" .. wave)
            eq(Panel.isOpen(), true, "真实Panel保留待选" .. wave)
            eq(sceneState.wave, wave + 1, "WaveWin立即推进下一波" .. wave)
            eq(opens, wave + 1, "每次WaveWin只开下一波一次" .. wave)
        end
        local function click(index)
            return Panel.handleClick(540, 744 + (index - 1) * 368)
        end
        local function interval(expected, label)
            check(math.abs(teams[1][1].atkInterval - expected) < 0.0000001,
                label .. " actual=" .. tostring(teams[1][1].atkInterval) .. " expected=" .. expected)
        end
        local function case(name, fn)
            local success, message = xpcall(fn, debug.traceback)
            if not success then check(false, name .. " exception=" .. tostring(message)) end
        end

        case("20同表双写", function()
            reset()
            local initial = last(AT.TOWER_CHALLENGE)
            win(1)
            click(1)
            eq(actionCounts[AT.TOWER_PICK_BUFF], 1, "一次卡片点击只发送一次")
            eq(#all.dungeon.babel_tower.buffs, 1, "Service权威20仅+1")
            eq(#sceneState.buffIds, 1, "Scene快照20仅+1")
            eq(sceneState.buffIds == all.dungeon.babel_tower.buffs, false, "Scene不是Service原表")
            eq(#initial.buffs, 0, "挑战回执快照不被后续选卡污染")
            interval(1, "20选卡不改正在进行的第2波")
            eq(sceneState.wave, 2, "成功选卡保持当前波2")
            eq(opens, 2, "成功选卡不额外开波")
            local reply = last(AT.TOWER_PICK_BUFF)
            Page.onActionResult(reply)
            eq(#all.dungeon.babel_tower.buffs, 1, "重复成功回包不增加")
            eq(opens, 2, "重复回包不重开波")
            interval(1, "重复回包不提前应用20")
            win(2)
            interval(0.75, "下一波开场只应用一次20")
            click(3)
            eq(#all.dungeon.babel_tower.buffs, 2, "跨波另一强化新增一次")
            interval(0.75, "换波不重乘旧20")
            eq(#reply.buffs, 1, "旧选卡回执快照不被新选择污染")
        end)
        case("28倍率", function()
            reset()
            win(1)
            click(2)
            eq(#all.dungeon.babel_tower.buffs, 1, "Service权威28仅+1")
            interval(1, "28选卡不改当前波间隔")
            win(2)
            interval(2, "下一波开场28法师间隔只乘2")
            click(3)
            interval(2, "换波不重乘旧28")
            win(3)
            interval(2, "再换波旧28仍不重乘")
        end)
        case("失败保留当前波", function()
            reset()
            win(1)
            all.battle = { maxStageId = 101 }
            click(1)
            eq(last(AT.TOWER_PICK_BUFF).success, false, "门禁失败是真实Service拒绝")
            eq(#all.dungeon.babel_tower.buffs, 0, "失败权威不新增")
            eq(#sceneState.buffIds, 0, "失败Scene不新增")
            eq(sceneState.wave, 2, "失败不回退WaveWin已开的第2波")
            eq(opens, 2, "失败不额外重开")
            eq(Panel.isOpen(), true, "失败Panel保持可重试")
            eq(panelState.pending, false, "匹配Service失败释放Panel pending")
            interval(1, "失败不应用20")
            Page.onActionResult(last(AT.TOWER_PICK_BUFF))
            eq(opens, 2, "重复失败回包不重开")
            all.battle = { maxStageId = 2001, clearedStages = { [1905] = true } }
            win(2)
            interval(1, "旧选择失败不阻塞下一波且无虚构强化")
            click(1)
            eq(#all.dungeon.babel_tower.buffs, 1, "恢复资格后旧选择重试一次")
            eq(sceneState.wave, 3, "重试成功保持已推进的第3波")
            eq(opens, 3, "旧选择重试不额外开波")
            interval(1, "旧选择重试仍不改当前波")
        end)
        case("迟到回包/重入/同卡跨波", function()
            reset()
            win(1)
            local waveReceipt = last(AT.TOWER_WAVE_WIN)
            hold = true
            click(1)
            eq(sceneState.wave, 2, "未收到选择回执仍已开第2波")
            eq(#sceneState.buffIds, 0, "未回执Scene快照不提前改变")
            click(2)
            eq(actionCounts[AT.TOWER_PICK_BUFF], 1, "pending重复点击不再次发送")
            eq(#all.dungeon.babel_tower.buffs, 1, "pending权威仅选择一次")
            local pick = assert(queue[1], "fixture missing delayed pick")
            Page.onActionResult(waveReceipt)
            click(2)
            eq(actionCounts[AT.TOWER_PICK_BUFF], 1, "重复WaveWin回包不解锁pending")
            win(2)
            interval(1, "选择回执迟到不阻塞第3波或提前应用20")
            Page.onActionResult(pick)
            Page.onActionResult(pick)
            eq(sceneState.wave, 3, "旧选择迟到成功不回退已开的第3波")
            eq(opens, 3, "迟到重复成功不额外开波")
            interval(1, "迟到成功20不改当前波")
            hold = false
            Action.sendAction(AT.TOWER_PICK_BUFF, {
                buffId = pick.buffId, runId = pick.runId, selectionId = pick.selectionId,
                floor = pick.floor, wave = pick.wave, requestId = pick.requestId,
            })
            eq(#all.dungeon.babel_tower.buffs, 1, "同一请求重送不权威新增")
            Page.onActionResult(pick)
            eq(Panel.isOpen(), true, "旧选择回包不关闭下一波Panel")
            click(1)
            eq(#all.dungeon.babel_tower.buffs, 2, "跨波合法同20保留两项")
            eq(all.dungeon.babel_tower.buffs[1], 20, "跨波首卡20")
            eq(all.dungeon.babel_tower.buffs[2], 20, "跨波第二卡20")
            interval(1, "积累两份20仍不改当前波")
            win(3)
            interval(0.5625, "下一波合法20叠加0.75平方而非重开当前波")
            local before = #all.dungeon.babel_tower.buffs
            Action.sendAction(AT.TOWER_PICK_BUFF, {
                buffId = 28, runId = pick.runId, selectionId = pick.selectionId,
                floor = pick.floor, wave = pick.wave,
            })
            eq(last(AT.TOWER_PICK_BUFF).success, false, "同一次选择不能改选另一卡")
            eq(#all.dungeon.babel_tower.buffs, before, "冲突重送不新增")
            reset()
            win(1)
            Page.onActionResult(pick)
            eq(#sceneState.buffIds, 0, "重挑后旧run成功不改快照")
            eq(sceneState.wave, 2, "重挑后旧run不回退新局已开的波")
            eq(Panel.isOpen(), true, "重挑后旧run不关Panel")
        end)
        case("阶段/候选校验", function()
            reset()
            local initial = last(AT.TOWER_CHALLENGE)
            Action.sendAction(AT.TOWER_PICK_BUFF, { buffId = 20, runId = initial.runId,
                selectionId = "not-issued", floor = 1, wave = 1 })
            eq(last(AT.TOWER_PICK_BUFF).success, false, "未清波不允许选卡")
            eq(#all.dungeon.babel_tower.buffs, 0, "未清波拒绝无写入")
            win(1)
            local issued = last(AT.TOWER_WAVE_WIN)
            Action.sendAction(AT.TOWER_PICK_BUFF, { buffId = 2, runId = issued.runId,
                selectionId = issued.selectionId, floor = 1, wave = 1 })
            eq(last(AT.TOWER_PICK_BUFF).success, false, "有效buff但不在候选拒绝")
            eq(#all.dungeon.babel_tower.buffs, 0, "非候选拒绝无写入")
            local okWave = Service.WaveWin(1, 1, 1)
            eq(okWave, true, "重复清波复用候选")
            eq(Service.WaveWin(1, 1, 3), false, "旧选择未消费也不能跳过第2波")
            eq(Service.WaveWin(1, 1, 1.5), false, "拒绝非整数波次")
            eq(Service.WaveWin(1, 1, 0), false, "拒绝波次0")
            eq(Service.WaveWin(1, 1, 11), false, "拒绝超上限波次")
            local _, _, copied = Service.WaveWin(1, 1, 1)
            copied.buffChoices[1].id = 2
            local _, _, clean = Service.WaveWin(1, 1, 1)
            eq(clean.buffChoices[1].id, 20, "修改WaveWin副本不污染候选")
        end)
        case("十波正常结算", function()
            reset()
            patch(require("ui.battle.popup.BattleResultPanel"), "show", function() end)
            for wave = 1, 9 do win(wave); click(1) end
            Action.sendAction(AT.TOWER_WAVE_WIN, { floor = 1, wave = 10 })
            local terminal = last(AT.TOWER_WAVE_WIN)
            eq(terminal.floorCleared, true, "第10波直接整层通关")
            eq(actionCounts[AT.TOWER_PICK_BUFF], 9, "第10波不需要选卡")
            eq(actionCounts[AT.TOWER_FLOOR_WIN], 1, "十波真实结算一次")
            eq(all.dungeon.babel_tower.floor, 2, "真实Service结算推进层2")
            Page.onActionResult(terminal)
            eq(actionCounts[AT.TOWER_FLOOR_WIN], 1, "重复最后WaveWin不重复结算")
        end)
        case("收起三组FIFO与后续不选结算", function()
            reset()
            patch(require("ui.battle.popup.BattleResultPanel"), "show", function() end)
            win(1)
            local first = last(AT.TOWER_WAVE_WIN)
            eq(Panel.hide(), true, "收起保留首组身份")
            win(2)
            local second = last(AT.TOWER_WAVE_WIN)
            win(3)
            eq(Panel.isVisible(), false, "收起后新组累计不弹出")
            eq(#sceneState.choiceQueue, 3, "收起积累三组")
            eq(panelState.request.selectionId, first.selectionId, "当前待选仍是首组")
            eq(Service.PickBuff(1, 28, second), false, "Service拒绝跳过首组择契")
            Panel.show()
            for index, buffId in ipairs({20, 28, 1}) do
                eq(panelState.request.wave, index, "恢复按FIFO呈现原波身份" .. index)
                click(index)
                eq(all.dungeon.babel_tower.buffs[index], buffId, "FIFO权威只追加当前卡" .. index)
                eq(opens, 4, "连续选旧组不重开第4波" .. index)
                interval(1, "累计选择不改第4波" .. index)
            end
            eq(#sceneState.choiceQueue, 0, "三组FIFO全部消费")
            win(4)
            interval(1.5, "第5波开场应用20与28各一次")
            Panel.hide()
            for wave = 5, 9 do win(wave); eq(Panel.isVisible(), false, "后续不选不弹出" .. wave) end
            eq(actionCounts[AT.TOWER_PICK_BUFF], 3, "后六组全不选也不增加选择请求")
            eq(#sceneState.choiceQueue, 6, "后六组保留到整层结算")
            Action.sendAction(AT.TOWER_WAVE_WIN, { floor = 1, wave = 10 })
            local terminal = last(AT.TOWER_WAVE_WIN)
            eq(terminal.floorCleared, true, "积累未选仍可十波通关")
            eq(actionCounts[AT.TOWER_FLOOR_WIN], 1, "未选不阻塞整层结算")
            eq(all.dungeon.babel_tower.floor, 2, "未选正常推进下一层")
            eq(#sceneState.choiceQueue, 0, "整层结算清未选队列")
            Page.onActionResult(terminal)
            eq(actionCounts[AT.TOWER_FLOOR_WIN], 1, "未选末波重复回执不重复结算")
        end)
        case("发送失败与旧失败回包", function()
            reset()
            win(1)
            Panel.setSendAction(nil)
            click(1)
            eq(sceneState.pendingSelection and sceneState.pendingSelection.buffId, nil, "无sender不锁Scene")
            Panel.setSendAction(function() return false end)
            click(1)
            eq(sceneState.pendingSelection and sceneState.pendingSelection.buffId, nil, "sender false释放Scene")
            eq(panelState.pending, false, "sender false释放Panel")
            eq(sceneState.wave, 2, "sender false不回退已开的第2波")
            eq(#all.dungeon.babel_tower.buffs, 0, "sender false不写权威")
            Panel.setSendAction(function() error("fixture sender failure") end)
            click(1)
            eq(sceneState.pendingSelection and sceneState.pendingSelection.buffId, nil, "sender异常释放Scene")
            eq(Panel.isOpen(), true, "sender异常保留Panel")
            Panel.setSendAction(Action.sendAction)
            all.battle = { maxStageId = 101 }
            click(1)
            local failure = last(AT.TOWER_PICK_BUFF)
            all.battle = { maxStageId = 2001, clearedStages = { [1905] = true } }
            hold = true
            click(1)
            Page.onActionResult(failure)
            click(2)
            eq(actionCounts[AT.TOWER_PICK_BUFF], 2, "迟到旧失败不能解锁当前retry")
            Page.onActionResult(queue[1])
            eq(sceneState.wave, 2, "当前retry成功不额外推进")
            eq(opens, 2, "当前retry成功不重开当前波")
        end)
        case("Handler异常保留身份", function()
            reset()
            win(1)
            local oldPick = Service.PickBuff
            Service.PickBuff = function() error("fixture service error") end
            click(1)
            Service.PickBuff = oldPick
            local failure = last(AT.TOWER_PICK_BUFF)
            eq(failure.success, false, "Service抛错被Handler转换失败")
            eq(failure.selectionId, panelState.request.selectionId, "Handler异常回执保留selection身份")
            check(failure.requestId ~= nil, "Handler异常回执保留requestId")
            eq(panelState.pending, false, "Service异常释放Panel")
            eq(sceneState.pendingSelection.buffId, nil, "Service异常释放Scene")
            eq(sceneState.wave, 2, "Service异常不回退当前波")
            click(1)
            eq(sceneState.wave, 2, "Service异常后同卡重试不推进")
            eq(#all.dungeon.babel_tower.buffs, 1, "Service异常后权威只写一次")
        end)
        case("成功丢回执后超时同卡重试", function()
            reset()
            win(1)
            hold = true
            click(1)
            local oldReceipt = assert(queue[1])
            eq(#all.dungeon.babel_tower.buffs, 1, "丢回执前Service已经提交")
            Page.onActionResult({ action = AT.TOWER_PICK_BUFF, success = false, reason = "无身份失败" })
            eq(panelState.pending, true, "无身份失败不能误释放请求")
            -- 专测battle phase中的回执超时，不让5.1秒夹具tick实际战斗自然结算。
            local tick = Tri.update
            Tri.update = function() end
            Scene.update(5.1)
            Tri.update = tick
            eq(panelState.pending, false, "超时释放Panel供同卡重试")
            eq(sceneState.pendingSelection.buffId, nil, "超时释放对应Scene请求")
            click(2)
            eq(actionCounts[AT.TOWER_PICK_BUFF], 1, "结果未知时不能改选另一卡")
            click(1)
            local retry = assert(queue[2])
            check(retry.requestId ~= oldReceipt.requestId, "超时重试使用新requestId")
            eq(#all.dungeon.babel_tower.buffs, 1, "成功丢回执重试不再append")
            Page.onActionResult(oldReceipt)
            eq(panelState.pending, true, "迟到旧成功不能消费新请求")
            eq(sceneState.wave, 2, "旧成功不改变retry期间的当前波")
            Page.onActionResult(retry)
            Page.onActionResult(retry)
            eq(sceneState.wave, 2, "当前重试成功回执不额外推进")
            eq(opens, 2, "成功丢回执不重开当前波")
            interval(1, "成功丢回执重试不提前应用20")
            win(2)
            interval(0.75, "成功丢回执20到下一波只应用一次")
            -- 真实换波仍保留原满血规则。
            eq(teams[1][1].hp, teams[1][1].maxHp, "原波间满血规则不变")
        end)
        case("requestId冲突与快照隔离", function()
            reset()
            win(1)
            click(1)
            local pick = last(AT.TOWER_PICK_BUFF)
            local oldSnapshot = pick.buffs
            oldSnapshot[1] = 28
            local _, _, replay = Service.PickBuff(1, 20, {
                runId = pick.runId, selectionId = pick.selectionId, floor = 1, wave = 1,
                requestId = pick.requestId,
            })
            eq(replay.buffs[1], 20, "修改交付快照不污染Service accepted")
            win(2)
            local issued = last(AT.TOWER_WAVE_WIN)
            eq(Service.PickBuff(1, 20, { runId = issued.runId, selectionId = issued.selectionId,
                floor = 1, wave = 2, requestId = pick.requestId }), false, "同run requestId不能用于另一selection")
            eq(#all.dungeon.babel_tower.buffs, 1, "requestId冲突不append")
            click(1)
            eq(#all.dungeon.babel_tower.buffs, 2, "独立requestId同卡下一波合法")
        end)
        case("真实Page sender透传false与异常", function()
            reset()
            win(1)
            local originalSender = Action.sendAction
            Action.sendAction = function() return false end
            click(1) -- Panel 注入的是 Page 包装器，不是替换后的函数直传。
            Action.sendAction = originalSender
            eq(panelState.pending, false, "真实Page透传false释放Panel")
            eq(sceneState.pendingSelection.buffId, nil, "真实Page透传false释放Scene")
            eq(sceneState.wave, 2, "真实Page false不回退已开的第2波")
            Action.sendAction = function() error("fixture Page sender error") end
            click(1)
            Action.sendAction = originalSender
            eq(panelState.pending, false, "真实Page sender异常释放Panel")
            eq(sceneState.pendingSelection.buffId, nil, "真实Page sender异常释放Scene")
            click(1)
            eq(sceneState.wave, 2, "真实Page sender恢复可重试")
            eq(#all.dungeon.babel_tower.buffs, 1, "真实Page sender失败不写权威")
        end)
        case("MarkDirty同步重入accepted先建立", function()
            reset()
            win(1)
            local issued = last(AT.TOWER_WAVE_WIN)
            local originalDirty = PDM.MarkDirty
            ---@type table|nil
            local nestedReceipt = nil
            PDM.MarkDirty = function(uid, key)
                if key == "dungeon" and nestedReceipt == nil then
                    local success, _, receipt = Service.PickBuff(uid, 20, {
                        runId = issued.runId, selectionId = issued.selectionId,
                        floor = 1, wave = 1,
                    })
                    eq(success, true, "MarkDirty重入时已建立accepted")
                    nestedReceipt = receipt
                end
                return originalDirty(uid, key)
            end
            click(1)
            PDM.MarkDirty = originalDirty
            eq(#all.dungeon.babel_tower.buffs, 1, "MarkDirty重入不重复append")
            eq(nestedReceipt and nestedReceipt.totalBuffs, 1, "MarkDirty重入返回同选择快照")
            eq(sceneState.wave, 2, "MarkDirty重入不推进选择所在当前波")
            eq(opens, 2, "MarkDirty重入不重开当前波")
            interval(1, "MarkDirty重入不提前应用20")
        end)
        case("append后MarkDirty异常同卡重试", function()
            reset()
            win(1)
            local originalDirty = PDM.MarkDirty
            PDM.MarkDirty = function() error("fixture dirty failure after append") end
            click(1)
            PDM.MarkDirty = originalDirty
            eq(last(AT.TOWER_PICK_BUFF).success, false, "append后异常由Handler保留身份返回失败")
            eq(#all.dungeon.babel_tower.buffs, 1, "append后异常已写一次权威")
            eq(#sceneState.buffIds, 0, "异常回执不应用Scene快照")
            eq(sceneState.wave, 2, "append后异常不回退已开的波")
            click(2)
            eq(actionCounts[AT.TOWER_PICK_BUFF], 1, "append后异常不能改选另一卡")
            click(1)
            eq(#all.dungeon.babel_tower.buffs, 1, "append后异常重试不重复append")
            eq(sceneState.wave, 2, "append后异常重试保持当前波")
            interval(1, "append后异常重试不提前应用倍率")
        end)
        case("同步成功后sender false或异常不覆盖新状态", function()
            reset()
            win(1)
            Panel.setSendAction(function(action, params)
                Action.sendAction(action, params)
                return false
            end)
            click(1)
            eq(sceneState.wave, 2, "同步成功后false不回滚")
            eq(Panel.isOpen(), false, "同步成功后false不重新打开Panel")
            win(2)
            Panel.setSendAction(function(action, params)
                Action.sendAction(action, params)
                error("fixture after receipt")
            end)
            click(1)
            eq(sceneState.wave, 3, "同步成功后异常不回滚")
            eq(#all.dungeon.babel_tower.buffs, 2, "同步成功后异常不额外append")
            interval(0.75, "同步成功后sender异常不提前应用第二份20")
            win(3)
            interval(0.5625, "下一波第二份20仅应用一次")
        end)
        Scene.close()
        SEM.mount(nil)
        BC.mount(nil)
        -- 独立运行时重复初始化与跨波保留引用，无 RuntimeContext/新跨战线接口依赖。
        local unit = { hp = 100, atkInterval = 1, classId = CC.MAGE }
        Runtime.initMechanics({ 20, 28 })
        Runtime.applyMechanicInit({ unit }, {})
        check(math.abs(unit.atkInterval - 1.5) < 1e-7, "20+28组合倍率1.5")
        Runtime.applyMechanicInit({ unit }, {})
        check(math.abs(unit.atkInterval - 1.5) < 1e-7, "同波机制重复初始化不重乘")
        Runtime.initMechanics({ 20, 28 })
        Runtime.applyMechanicInit({ unit }, {})
        check(math.abs(unit.atkInterval - 1.5) < 1e-7, "同表跨波机制初始化不重乘")
        local attrs = require("systems.UnitAttributes").create({ atkInterval = 1 })
        local recalced = { hp = 100, atkInterval = 1, classId = CC.MAGE, attrs = attrs }
        Runtime.initMechanics({ 20 })
        Runtime.applyMechanicInit({ recalced }, {})
        attrs:setBase(AD.ATK_INTERVAL, 0.75)
        recalced.atkInterval = attrs:getActualInterval()
        Runtime.applyMechanicInit({ recalced }, {})
        check(math.abs(recalced.atkInterval - 0.5625) < 1e-7, "recalc新基准恰等旧输出仍正确乘0.75")
        attrs:setBase(AD.ATK_INTERVAL, 2)
        recalced.atkInterval = attrs:getActualInterval()
        Runtime.applyMechanicInit({ recalced }, {})
        check(math.abs(recalced.atkInterval - 1.5) < 1e-7, "recalc覆盖新基准2不盲除旧倍率")
        Runtime.cleanup()
        eq(Panel.isOpen(), false, "退出清理Panel")
    end, debug.traceback)
    if not ok then check(false, "fixture exception=" .. tostring(err)) end
    for i = #restores, 1, -1 do
        local restored, restoreError = pcall(restores[i])
        if not restored then check(false, "fixture restore exception=" .. tostring(restoreError)) end
    end
    print("[TowerBuff] SUMMARY assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 then print("[TowerBuff] ALL PASS") end
    engine:Exit()
end
