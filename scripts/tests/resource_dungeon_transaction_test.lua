-- 独立真实File事务验收。与冷恢复入口串行运行；正式存档路径永不传给原生File。
local F = require("tests.ResourceDungeonPersistenceFixture")
local TAG = "[resource_dungeon_transaction_test]"
local assertions = 0
local function check(value, label) assertions = assertions + 1; assert(value, label) end
local function eq(a, b, label) check(a == b, label .. ": " .. tostring(a) .. " / " .. tostring(b)) end

function Start()
    local ok, err = pcall(function()
        check(fileSystem:CreateDir(F.ROOT) or fileSystem:DirExists(F.ROOT), "建立测试专用目录")
        check(not fileSystem:DirExists(F.ROOT .. "/missing-parent"), "真实失败目的目录必须不存在")
        local h = F.new()
        local AT = h.Protocol.ACTION_TYPES
        local function challenge(id, team)
            local reply = h.Handler.actionHandlers[AT.DUNGEON_CHALLENGE](1, { dungeonId = id, floor = 1, teamIdx = team })
            check(reply.success and reply.challengeId > 0, "真实Handler锁定挑战")
            return { dungeonId = id, floor = 1, teamIdx = team, challengeId = reply.challengeId }
        end
        local function assertRollback(modules, operation, label)
            local before = F.copy(modules)
            local gsBefore = h.GS.exportSave()
            local diskBefore = F.read(F.SAVE)
            local dungeon, sub = modules.dungeon, modules.dungeon.equipment_vault
            local cleared, bag, seeds = sub.cleared, modules.equipment.inventory, modules.lootbox.seeds
            local firstEquip = next(bag) and bag[next(bag)]
            local pushBefore, eventBefore = h.pushes, h.events
            h.committed = false
            local success = operation()
            eq(success, false, label .. "失败回执")
            F.same(modules, before, label .. "模块值回滚")
            F.same(h.GS.exportSave(), gsBefore, label .. "GameState回滚")
            eq(F.read(F.SAVE), diskBefore, label .. "旧真实File逐字节保留")
            eq(modules.dungeon, dungeon, label .. "原模块引用")
            eq(modules.dungeon.equipment_vault, sub, label .. "原子表引用")
            eq(sub.cleared, cleared, label .. "onLoad替换的cleared原表还原")
            eq(modules.equipment.inventory, bag, label .. "inventory外部别名")
            eq(modules.lootbox.seeds, seeds, label .. "seeds外部别名")
            if firstEquip then eq(bag[next(bag)], firstEquip, label .. "原装备引用") end
            eq(h.PDM.GetModule(1, "dungeon"), h.Dispatcher.get("dungeon"), label .. "双源同表")
            eq(h.pushes, pushBefore, label .. "没有候选模块通知")
            eq(h.events, eventBefore, label .. "没有候选货币事件")
            eq(h.queue, false, label .. "延后通知已释放")
        end
        for _, id in ipairs(h.DC.RESOURCE_IDS) do
            for _, failure in ipairs({ "false", "nil", "throw", "open", "write", "rename" }) do
                local modules = F.install(h, id == "equipment_vault" and 199 or 0)
                local params = challenge(id, 3)
                h.failure = failure
                local writes, renames = h.writeAttempts, h.renameAttempts
                assertRollback(modules, function()
                    return h.Handler.actionHandlers[AT.DUNGEON_WIN](1, params).success
                end, id .. "/win/" .. failure)
                if failure == "open" or failure == "write" or failure == "rename" then
                    check(h.writeAttempts > writes, "调用真实File失败出口")
                end
                if failure == "rename" then check(h.renameAttempts > renames, "调用真实FileSystem.Rename失败") end
                local again = h.Handler.actionHandlers[AT.DUNGEON_CHALLENGE](1, params)
                eq(again.challengeId, params.challengeId, "失败pending仍是同一挑战")
                h.failure = ""
                local reply = h.Handler.actionHandlers[AT.DUNGEON_WIN](1, params)
                check(reply.success and reply.firstClear, "失败后同pending可真实保存重试")
                eq(h.Handler.actionHandlers[AT.DUNGEON_WIN](1, params).success, false, "成功后pending只消费一次")

                modules = F.install(h, id == "equipment_vault" and 199 or 0)
                modules.dungeon[id].floor = 2
                modules.dungeon[id].cleared[1] = true
                h.failure = failure
                assertRollback(modules, function() return h.Service.Sweep(1, id) end, id .. "/sweep/" .. failure)
                eq(modules.dungeon[id].dailyUsed, 0, "失败不扣扫荡日次")
                h.failure = ""
                check(h.Service.Sweep(1, id), "扫荡真实写盘重试")
                eq(modules.dungeon[id].dailyUsed, 1, "只扣成功一次")

                modules = F.install(h, id == "equipment_vault" and 199 or 0)
                modules.dungeon[id].floor = 2
                modules.dungeon[id].cleared[1] = true
                modules.dungeon[id].idleAccumSec = 30 * 3600 + 37
                h.failure = failure
                assertRollback(modules, function() return h.Idle.Claim(1, id) end, id .. "/idle/" .. failure)
                eq(modules.dungeon[id].idleAccumSec, 30 * 3600 + 37, "失败不扣积累")
                h.failure = ""
                check(h.Idle.Claim(1, id), "挂机真实写盘重试")
            end
        end

        -- 生成/实际交付中途异常同样原位回滚，没有部分入包、首通或通知。
        local modules = F.install(h, 199)
        local params = challenge("equipment_vault", 2)
        local LS = h.require("systems.LootBoxSystem")
        local deliver = LS.deliverEquipment
        local delivered = 0
        LS.deliverEquipment = function(...)
            delivered = delivered + 1
            local value = deliver(...)
            if delivered == 3 then error("expected partial delivery exception") end
            return value
        end
        assertRollback(modules, function()
            return h.Handler.actionHandlers[AT.DUNGEON_WIN](1, params).success
        end, "实际交付第三件后异常")
        LS.deliverEquipment = deliver
        check(h.Handler.actionHandlers[AT.DUNGEON_WIN](1, params).success, "交付异常后可重试")

        -- 无接线必须fail closed，不能因PDM.FlushImmediate只print而承认成功。
        modules = F.install(h, 0)
        params = challenge("gold_mine", 2)
        h.Service.SetPersistCallback(nil)
        assertRollback(modules, function()
            return h.Handler.actionHandlers[AT.DUNGEON_WIN](1, params).success
        end, "未接线")
        -- 重新创建隔离生命周期，不用换全局File/require；保存旧真实文件不会读取正式档。
        h = F.new()
        modules = F.install(h, 199)
        F.ui(h)
        local battleBefore, heroesBefore = F.copy(modules.battle), F.copy(modules.heroes)
        for index, id in ipairs(h.DC.RESOURCE_IDS) do
            local team = index == 2 and 3 or 2
            local beforeSends = #h.sends
            h.Dialog.open(team)
            h.Dialog.handleInput(635, 686)
            h.Dialog.handleInput(300, 836 + (index - 1) * 190 + 40)
            eq(h.Dialog.isOpen(), false, "真实选关详情导航关闭弹窗")
            eq(#h.sends, beforeSends, "打开详情不自动发挑战")
            h.Page.handleInput(750, 1633)
            local request = h.sends[#h.sends]
            eq(request.action, AT.DUNGEON_CHALLENGE, "真实Page按钮发送Challenge")
            eq(request.params.teamIdx, team, "Page锁定选关队号不是activeTeam1")
            check(h.Scene.isOpen(), "同步真实Handler回执通过Page pending开Scene")
            eq(h.Battle.getConfig().teamIdx, team, "Scene队号未丢失")
            eq(#h.sceneState.enemies, 4, "实际Scene四槽")
            for _, units in ipairs({ h.sceneState.enemies, h.sceneState.enemyQueue }) do
                for _, unit in ipairs(units) do unit.hp = 0; unit.attrs.final[h.require("systems.AttributeDef").HP] = 0 end
            end
            for _ = 1, 30 do h.Scene.update(0.41) end
            local reply = h.replies[#h.replies]
            eq(reply.action, AT.DUNGEON_WIN, "真实Scene生命周期发送Win")
            check(reply.success and reply.firstClear, "Win真实保存后才回成功")
            eq(reply.teamIdx, team, "Win按原队结算")
            check(h.Battle.isResultReady(), "真实成功回执解锁Scene结算")
            eq(modules.dungeon[id].floor, 2, "独立层推进")
            check(#h.displayed > 0 and #h.displayed[#h.displayed] > 0, "实际Scene展示服务端奖励")
            h.Scene.close()
            h.Page.close()
            F.same(modules.battle, battleBefore, "UI闭环不改主线")
            F.same(modules.heroes, heroesBefore, "UI闭环不改编队")
            check(h.Service.Sweep(1, id), "为冷恢复保存成功扫荡日次")
            modules.dungeon[id].idleAccumSec = 30 * 3600 + 37
            check(h.Idle.Claim(1, id), "为冷恢复保存真实挂机领取")
        end
        eq(h.ES.getInventoryCount(modules.equipment), 200, "UI闭环保持背包容量")
        check(#modules.lootbox.seeds > 0, "UI胜利满包的确定装备入匣")
        local expected = { modules = F.copy(modules), gameState = h.GS.exportSave(),
            disk = cjson.decode(F.read(F.SAVE)), expectedLootCount = #modules.lootbox.seeds }
        F.writeExpected(expected)
        print(TAG .. " ALL PASS assertions=" .. assertions .. " realFile=true coldFixture=" .. F.SAVE)
    end)
    if not ok then log:Write(LOG_ERROR, TAG .. " FAIL after " .. assertions .. ": " .. tostring(err)) end
    engine:Exit()
end
