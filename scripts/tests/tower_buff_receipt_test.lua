-- B04：真实 Panel -> GameAction -> LocalActionBridge -> Handler -> Service -> DungeonPage -> Scene。
-- 合成内存模块，不读玩家存档；仅记录/延迟消息交付、替换无关初始化和绘图关键词边界。
-- 跑法：.cli/UrhoXRuntime tests/tower_buff_receipt_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
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

local function getState(fn)
    for i = 1, 40 do
        local name, value = debug.getupvalue(fn, i)
        if name == "state" then return value end
        if not name then break end
    end
    error("fixture cannot locate state")
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
        local sceneState = getState(Scene.isActive)
        local all = Dispatcher.getAll()
        local originals = {}
        for k, v in pairs(all) do originals[k] = v end
        restores[#restores + 1] = function()
            Scene.close()
            for k in pairs(all) do all[k] = nil end
            for k, v in pairs(originals) do all[k] = v end
        end
        for k in pairs(all) do all[k] = nil end
        all.battle = { maxStageId = 1906, clearedStages = { [1905] = true } }
        all.player = { name = "B04 fixture", level = 1, exp = 0 }
        all.currency = {}
        all.heroes = { roster = {}, teams = {}, deployed = {} }
        all.dungeon = { babel_tower = { floor = 1, cleared = {}, buffs = {}, dailyUsed = 0 } }
        patch(require("boot.StandaloneSave"), "Flush", function() return true end)
        patch(require("rules.redeem.RedeemService"), "Init", function() end)
        local teams = {}
        patch(CP, "getUnlockedTeamCount", function() return 3 end)
        patch(CP, "getDeployedTeam", function(t) return teams[t or 1] or {} end)
        patch(CP, "isHeroesDataApplied", function() return true end)
        -- 没有draw，不生成关键词热区；保留Panel整卡hitTest和真正发送动作。
        local panelState = getState(Panel.isOpen)
        for i = 1, 40 do
            local name, value = debug.getupvalue(Panel.handleClick, i)
            if name == "kwCards" then
                for _, card in ipairs(value) do
                    patch(card, "isOpen", function() return false end)
                    patch(card, "handleInput", function() return false end)
                end
                break
            end
            if not name then break end
        end
        local receipts, queue = {}, {}
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
            hold, queue, receipts, actionCounts, opens = false, {}, {}, {}, 0
            all.battle = { maxStageId = 1906, clearedStages = { [1905] = true } }
            all.dungeon = { babel_tower = { floor = 1, cleared = {}, buffs = {}, dailyUsed = 0 } }
            teams = {}
            for t = 1, 3 do
                local unit = assert(HC.createHero(9, 1))
                unit.classId = CC.MAGE
                unit.atkInterval = 1
                unit.attrs.final[AD.HP] = unit.attrs:get(AD.MAX_HP)
                unit.hp, unit.maxHp = unit.attrs:get(AD.HP), unit.attrs:get(AD.MAX_HP)
                teams[t] = { unit }
            end
            Action.sendAction(AT.TOWER_CHALLENGE, {})
            eq(Scene.isActive(), true, "正式DungeonPage打开Scene")
            eq(PDM.GetModule(1, "dungeon"), all.dungeon, "PDM与Dispatcher正式同表")
        end
        local function win(wave)
            Action.sendAction(AT.TOWER_WAVE_WIN, { floor = 1, wave = wave })
            eq(last(AT.TOWER_WAVE_WIN).success, true, "真实WaveWin成功" .. wave)
            eq(Panel.isOpen(), true, "真实Panel待选" .. wave)
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
            interval(0.75, "20间隔倍率0.75")
            eq(sceneState.wave, 2, "成功回执后换波2")
            eq(opens, 2, "只开下一波一次")
            local reply = last(AT.TOWER_PICK_BUFF)
            Page.onActionResult(reply)
            eq(#all.dungeon.babel_tower.buffs, 1, "重复成功回包不增加")
            eq(opens, 2, "重复回包不重开波")
            interval(0.75, "重复回包无额外倍率")
            -- 换波选择stat卡，旧20不能再乘一次。
            win(2)
            click(3)
            eq(#all.dungeon.babel_tower.buffs, 2, "跨波另一强化新增一次")
            interval(0.75, "换波不重乘旧20")
        end)
        case("28倍率", function()
            reset()
            win(1)
            click(2)
            eq(#all.dungeon.babel_tower.buffs, 1, "Service权威28仅+1")
            interval(2, "28法师间隔只乘2")
            win(2)
            click(3)
            interval(2, "换波不重乘旧28")
        end)
        case("失败保留当前波", function()
            reset()
            win(1)
            all.battle = { maxStageId = 101 }
            click(1)
            eq(last(AT.TOWER_PICK_BUFF).success, false, "门禁失败是真实Service拒绝")
            eq(#all.dungeon.babel_tower.buffs, 0, "失败权威不新增")
            eq(#sceneState.buffIds, 0, "失败Scene不新增")
            eq(sceneState.wave, 1, "失败不换波")
            eq(opens, 1, "失败不重开")
            eq(Panel.isOpen(), true, "失败Panel保持可重试")
            interval(1, "失败不应用20")
            Page.onActionResult(last(AT.TOWER_PICK_BUFF))
            eq(opens, 1, "重复失败回包不重开")
            all.battle = { maxStageId = 1906, clearedStages = { [1905] = true } }
            click(1)
            eq(#all.dungeon.babel_tower.buffs, 1, "恢复资格后当前选择重试一次")
            eq(sceneState.wave, 2, "重试成功换波")
        end)
        case("迟到回包/重入/同卡跨波", function()
            reset()
            win(1)
            local waveReceipt = last(AT.TOWER_WAVE_WIN)
            hold = true
            click(1)
            eq(sceneState.wave, 1, "未收到成功回执不提前换波")
            eq(#sceneState.buffIds, 0, "未回执Scene快照不提前改变")
            click(2)
            eq(actionCounts[AT.TOWER_PICK_BUFF], 1, "pending重复点击不再次发送")
            eq(#all.dungeon.babel_tower.buffs, 1, "pending权威仅选择一次")
            local pick = queue[1]
            if pick then
                -- 重入同一波结果不能重置正在等待的选择。
                Page.onActionResult(waveReceipt)
                click(2)
                eq(actionCounts[AT.TOWER_PICK_BUFF], 1, "重复WaveWin回包不解锁pending")
                Page.onActionResult(pick)
                Page.onActionResult(pick)
                eq(sceneState.wave, 2, "迟到成功处理一次")
                eq(opens, 2, "迟到重复成功只换波一次")
                interval(0.75, "迟到成功20一次")
                hold = false
                -- 直接重送正式请求，Service应按selection而非buffId幂等。
                Action.sendAction(AT.TOWER_PICK_BUFF, {
                    buffId = pick.buffId, runId = pick.runId, selectionId = pick.selectionId,
                    floor = pick.floor, wave = pick.wave,
                })
                eq(#all.dungeon.babel_tower.buffs, 1, "同一请求重送不权威新增")
                win(2)
                Page.onActionResult(pick)
                eq(Panel.isOpen(), true, "旧选择回包不关闭下一波Panel")
                click(1)
                eq(#all.dungeon.babel_tower.buffs, 2, "跨波合法同20保留两项")
                eq(all.dungeon.babel_tower.buffs[1], 20, "跨波首卡20")
                eq(all.dungeon.babel_tower.buffs[2], 20, "跨波第二卡20")
                interval(0.5625, "跨波合法20叠加0.75平方而非额外换波乘算")
                -- 同run错误候选/过期阶段、退出重挑的旧回执都不能污染。
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
                eq(sceneState.wave, 1, "重挑后旧run不换波")
                eq(Panel.isOpen(), true, "重挑后旧run不关Panel")
            else check(false, "fixture missing delayed pick") end
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
        case("发送失败与旧失败回包", function()
            reset()
            win(1)
            Panel.setSendAction(nil)
            click(1)
            eq(sceneState.pendingSelection and sceneState.pendingSelection.buffId, nil, "无sender不锁Scene")
            Panel.setSendAction(function() error("fixture sender failure") end)
            click(1)
            eq(sceneState.pendingSelection and sceneState.pendingSelection.buffId, nil, "sender异常释放Scene")
            eq(Panel.isOpen(), true, "sender异常保留Panel")
            Panel.setSendAction(Action.sendAction)
            all.battle = { maxStageId = 101 }
            click(1)
            local failure = last(AT.TOWER_PICK_BUFF)
            all.battle = { maxStageId = 1906, clearedStages = { [1905] = true } }
            hold = true
            click(1)
            Page.onActionResult(failure)
            click(2)
            eq(actionCounts[AT.TOWER_PICK_BUFF], 2, "迟到旧失败不能解锁当前retry")
            Page.onActionResult(queue[1])
            eq(sceneState.wave, 2, "当前retry成功仍推进一次")
        end)
        Scene.close()
        SEM.mount(nil)
        BC.mount(nil)
        -- 独立引擎初始化幂等：同一波重复applyMechanicInit与跨波保留单位。
        local unit = { hp = 100, atkInterval = 1, classId = CC.MAGE }
        Runtime.initMechanics({ 20, 28 })
        Runtime.applyMechanicInit({ unit }, {})
        check(math.abs(unit.atkInterval - 1.5) < 1e-7, "20+28组合倍率1.5")
        Runtime.applyMechanicInit({ unit }, {})
        check(math.abs(unit.atkInterval - 1.5) < 1e-7, "同波机制重复初始化不重乘")
        Runtime.initMechanics({ 20, 28 })
        Runtime.applyMechanicInit({ unit }, {})
        check(math.abs(unit.atkInterval - 1.5) < 1e-7, "同表跨波机制初始化不重乘")
        -- attrs重算覆盖间隔为新基准（包含恰好等于旧输出的碰撞）。
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
    for i = #restores, 1, -1 do restores[i]() end
    print("[TowerBuff] SUMMARY assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 then print("[TowerBuff] ALL PASS") end
    engine:Exit()
end
