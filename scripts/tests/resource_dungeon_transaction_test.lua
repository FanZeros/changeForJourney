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
            local heroes, roster, hero = modules.heroes, modules.heroes.roster, modules.heroes.roster[1]
            local player, session = modules.player, modules.session
            local artifacts, artifactBag = modules.artifacts, modules.artifacts.bag
            local firstArtifact = artifactBag[1]
            local tower, towerCleared = modules.dungeon.babel_tower, modules.dungeon.babel_tower.cleared
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
            eq(modules.heroes, heroes, label .. "heroes模块外部别名")
            eq(modules.heroes.roster, roster, label .. "roster外部别名")
            eq(modules.heroes.roster[1], hero, label .. "hero外部别名")
            eq(modules.player, player, label .. "player模块外部别名")
            eq(modules.session, session, label .. "session模块外部别名")
            eq(modules.artifacts, artifacts, label .. "artifacts模块外部别名")
            eq(modules.artifacts.bag, artifactBag, label .. "神器bag外部别名")
            if firstArtifact then eq(artifactBag[1], firstArtifact, label .. "原神器引用") end
            eq(modules.dungeon.babel_tower, tower, label .. "塔子表外部别名")
            eq(tower.cleared, towerCleared, label .. "塔首通账本外部别名")
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
                local sweepWrites, sweepRenames = h.writeAttempts, h.renameAttempts
                assertRollback(modules, function() return h.Service.Sweep(1, id) end, id .. "/sweep/" .. failure)
                if failure == "open" or failure == "write" or failure == "rename" then
                    check(h.writeAttempts > sweepWrites, "扫荡实际进入真实File写入失败边界")
                end
                if failure == "rename" then check(h.renameAttempts > sweepRenames, "扫荡实际进入真实Rename失败边界") end
                eq(modules.dungeon[id].dailyUsed, 0, "失败不改旧扫荡日次")
                eq(modules.currency.sweepTicket, 30, "失败原位返还扫荡券")
                h.failure = ""
                local swept, sweepErr, sweepReply = h.Service.Sweep(1, id)
                check(swept, "扫荡真实写盘重试 " .. tostring(sweepErr))
                eq(modules.dungeon[id].dailyUsed, 0, "新规则成功也不扣旧每日次")
                eq(modules.currency.sweepTicket, 29, "重试只扣成功一券")
                eq(sweepReply.stageId, h.DC.getStageId(id, 1), "真实写档锁定已通资源层")
                local saved = cjson.decode(F.read(F.SAVE))
                eq(saved.modules.currency.sweepTicket, 29, "券余额随完整奖励真实File落盘")

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

        -- 新扫荡同样走真实File事务：生成/交付中途失败不能部分入包或扣券。
        for _, failure in ipairs({ "generation", "delivery" }) do
            modules = F.install(h, 199)
            modules.dungeon.equipment_vault.floor = 2
            modules.dungeon.equipment_vault.cleared[1] = true
            local random, generate, delivery = h.env.math.random, h.ES.generateRandom, LS.deliverEquipment
            -- 私有math副本，稳定命中每杀装备，不更改Runtime全局RNG。
            h.env.math = F.copy(math)
            h.env.math.random = function(a, b)
                if a == nil then return 0 end
                return b == nil and 1 or a
            end
            local calls = 0
            if failure == "generation" then
                h.ES.generateRandom = function(...)
                    calls = calls + 1
                    if calls == 3 then return nil end
                    return generate(...)
                end
            else
                LS.deliverEquipment = function(...)
                    calls = calls + 1
                    local result = delivery(...)
                    if calls == 3 then error("expected sweep partial delivery exception") end
                    return result
                end
            end
            assertRollback(modules, function() return h.Service.Sweep(1, "equipment_vault", 2, 1, 1) end,
                "扫荡真实File/" .. failure)
            eq(calls, 3, "真实扫荡第三件中途失败")
            eq(modules.currency.sweepTicket, 30, "扫荡中途失败不扣券")
            h.ES.generateRandom, LS.deliverEquipment = generate, delivery
            check(h.Service.Sweep(1, "equipment_vault", 2, 1, 1), "扫荡中途失败后可原请求重试")
            eq(modules.currency.sweepTicket, 29, "重试只扣一券")
            eq(cjson.decode(F.read(F.SAVE)).modules.currency.sweepTicket, 29, "重试券实际落盘")
            h.env.math.random = random
        end

        -- 塔与资源共用真实File事务；固定私有RNG命中神器，保存失败不可重抽或部分发奖。
        local towerService = h.require("rules.tower.TowerService")
        local artifactSchema = h.require("shared.artifact.ArtifactSchema")
        local nativeMath = h.env.math
        h.env.math = F.copy(math)
        local towerRandomCalls = 0
        h.env.math.random = function(a, b)
            towerRandomCalls = towerRandomCalls + 1
            if a == nil then return 0.01 end
            return b == nil and 1 or a
        end
        for _, failure in ipairs({ "false", "open", "rename" }) do
            modules = F.install(h, 0)
            towerService.ResetToDefault(1)
            local tower = modules.dungeon.babel_tower
            tower.floor, tower.cleared, tower.buffs = 1, {}, {}
            modules.artifacts.bag[1] = { id = "1", artifactId = 2, quality = 1, valueRatio = 4321 }
            modules.artifacts.nextId = 2
            artifactSchema.normalizeModule(modules.artifacts)
            h.queue = {}
            check(h.Save.Flush() == true, "塔专用旧档通过真实File建立")
            h.queue = false
            local challenged, challengeErr, initial = towerService.Challenge(1, 1)
            check(challenged, "真实塔挑战1 " .. tostring(challengeErr))
            check(towerService.WaveWin(1, 1, 1, initial), "真实塔单波通关")
            h.failure = failure
            local writes, renames, randomBefore = h.writeAttempts, h.renameAttempts, towerRandomCalls
            assertRollback(modules, function() return towerService.FloorWin(1, 1, initial) end,
                "塔真实File/floor1/" .. failure)
            check(towerRandomCalls > randomBefore, "首次结算真实生成神器及续层配置")
            local cachedRandomCalls = towerRandomCalls
            eq(tower.floor, 1, "塔失败不推进")
            eq(tower.cleared[1], nil, "塔失败首通不落内存")
            eq(#modules.artifacts.bag, 1, "塔失败保留原神器不发候选")
            eq(modules.artifacts.nextId, 2, "塔失败nextId原位回滚")
            if failure == "open" or failure == "rename" then
                check(h.writeAttempts > writes, "塔失败实际调用原生File")
            end
            if failure == "rename" then check(h.renameAttempts > renames, "塔失败实际调用原生Rename") end
            assertRollback(modules, function() return towerService.FloorWin(1, 1, initial) end,
                "塔同开奖再次失败/" .. failure)
            eq(towerRandomCalls, cachedRandomCalls, "塔失败重试神器及续层不重抽")
            h.failure = ""
            local gemsBefore = modules.currency.gems
            local succeeded, retryErr, receipt = towerService.FloorWin(1, 1, initial)
            check(succeeded, "塔同层真实File保存重试 " .. tostring(retryErr))
            eq(receipt.firstClear, true, "塔重试仍为首通")
            eq(receipt.diamondReward, h.TC.getFloor(1).firstDiamond, "塔首钻按真实配置")
            eq(modules.currency.gems, gemsBefore + receipt.diamondReward, "塔首钻只成功发放一次")
            check(receipt.playerExp > 0 and receipt.heroExpTotal > 0, "塔经验随首通结算")
            eq(tower.floor, 2, "塔成功推进一层")
            eq(tower.cleared[1], true, "塔成功首通写内存")
            eq(#modules.artifacts.bag, 2, "塔成功只发一件神器")
            eq(modules.artifacts.nextId, 3, "塔成功只消费一个实例ID")
            local deliveredArtifact = {} -- 正式神器onLoad按品质/实例ID排序，不能假定新物在bag末尾。
            for _, artifact in ipairs(modules.artifacts.bag) do
                if artifact.id == receipt.artifacts[1].id then deliveredArtifact = artifact end
            end
            F.same(deliveredArtifact, receipt.artifacts[1], "塔回执神器与实际交付一致")
            local saved = cjson.decode(F.read(F.SAVE))
            eq(saved.modules.dungeon.babel_tower.cleared[1], true, "塔首通通过真实File落盘")
            eq(saved.modules.currency.gems, modules.currency.gems, "塔首钻通过真实File落盘")
            F.same(saved.modules.player, modules.player, "塔玩家经验通过真实File落盘")
            F.same(saved.modules.artifacts, modules.artifacts, "塔神器及实例计数通过真实File落盘")
            local beforeRepeat, diskBeforeRepeat = F.copy(modules), F.read(F.SAVE)
            local repeatWrites, repeatPushes, repeatEvents = h.writeAttempts, h.pushes, h.events
            local repeated, _, cached = towerService.FloorWin(1, 1, initial)
            check(repeated, "塔已成功层返回缓存回执")
            F.same(cached, receipt, "塔重复成功回执含固定神器")
            F.same(modules, beforeRepeat, "塔缓存回执不再次发奖或经验")
            eq(F.read(F.SAVE), diskBeforeRepeat, "塔重复回执不回写真实File")
            eq(h.writeAttempts, repeatWrites, "塔重复回执无File写入")
            eq(h.pushes, repeatPushes, "塔重复回执无模块通知")
            eq(h.events, repeatEvents, "塔重复回执无货币事件")
            eq(towerRandomCalls, cachedRandomCalls, "塔成功重试和重复回执都不重抽")
        end
        towerService.ResetToDefault(1)
        h.env.math = nativeMath

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
        -- 旧Page详情→独立Scene→Win UI链已从正式openResource入口移除。
        -- 本测试不运行该已不可达链，也不伪造detailOpen；现行战线输入由
        -- team_sweep_input_test与sweep_dialog_preview_test验收，不含设备触控或渲染像素。
        print(TAG .. " LEGACY UI NOT RUN: replaced by Tri selection; current input verified separately")
        -- 不走死UI，真实Handler/规则/双onLoad/原子Rename照常生成综合冷恢复快照。
        -- 单波迁移冻结旧塔 floor=21 已领取的 1..20 层，不重编号，也不随资源奖励重写。
        eq(h.TC.WAVES_PER_FLOOR, 1, "真实TowerConfig已切换为每层单波")
        eq(modules.dungeon.compat.towerSingleWaveV2, true, "旧塔历史冻结迁移已标记")
        local towerBefore = F.copy(modules.dungeon[h.TC.DUNGEON_ID])
        eq(towerBefore.floor, 21, "单波迁移保留旧塔下一未通层号")
        for floor = 1, 20 do
            eq(towerBefore.cleared[floor], true, "单波迁移冻结旧塔已领取首通/" .. floor)
        end
        local towerClearedCount = 0
        for _ in pairs(towerBefore.cleared) do towerClearedCount = towerClearedCount + 1 end
        eq(towerClearedCount, 20, "单波迁移不增删旧塔已领取历史")
        F.same(towerBefore.buffs, { 2, 5 }, "单波迁移保留旧塔强化")
        local battleBefore = F.copy(modules.battle)
        for index, id in ipairs(h.DC.RESOURCE_IDS) do
            local team = index == 2 and 3 or 2
            local params = challenge(id, team)
            local reply = h.Handler.actionHandlers[AT.DUNGEON_WIN](1, params)
            check(reply.success and reply.firstClear, "综合快照真实Handler首通成功")
            eq(reply.teamIdx, team, "综合快照真实Handler保留目标队伍")
            eq(modules.dungeon[id].floor, 2, "综合快照独立副本推进")
            local tickets = modules.currency.sweepTicket
            local swept, sweepErr = h.Service.Sweep(1, id, team, 1, 1)
            check(swept, "综合快照扫荡真实File保存 " .. tostring(sweepErr))
            eq(modules.currency.sweepTicket, tickets - 1, "综合快照一券一场不返券")
            eq(modules.dungeon[id].dailyUsed, 0, "综合快照扫荡不消耗旧日次")
            modules.dungeon[id].idleAccumSec = 30 * 3600 + 37
            check(h.Idle.Claim(1, id), "综合快照真实挂机领取")
            F.same(modules.battle, battleBefore, "综合快照副本事务不改主线")
            F.same(modules.dungeon[h.TC.DUNGEON_ID], towerBefore, "资源事务不改旧塔冻结历史")
        end
        -- 保留原21层历史后真实首通21；同一综合档跨进程恢复新神器与1..21账本。
        towerService = h.require("rules.tower.TowerService")
        towerService.ResetToDefault(1)
        local finalMath = h.env.math
        h.env.math = F.copy(math)
        h.env.math.random = function(a, b)
            if a == nil then return 0.01 end
            return b == nil and 1 or a
        end
        local challenged, towerErr, towerInitial = towerService.Challenge(1, 21)
        check(challenged, "综合快照真实塔挑战21 " .. tostring(towerErr))
        check(towerService.WaveWin(1, 21, 1, towerInitial), "综合快照真实塔单波21")
        local won, winErr, towerReceipt = towerService.FloorWin(1, 21, towerInitial)
        check(won, "综合快照真实File保存塔21 " .. tostring(winErr))
        check(towerReceipt.firstClear and #towerReceipt.artifacts == 1, "综合快照塔21首通和神器一次交付")
        eq(modules.dungeon.babel_tower.floor, 22, "综合快照真实塔首通推进22")
        eq(modules.dungeon.babel_tower.cleared[21], true, "综合快照真实塔21首通保存")
        for floor = 1, 20 do
            eq(modules.dungeon.babel_tower.cleared[floor], true, "塔21首通不删旧冻结账本/" .. floor)
        end
        F.same(modules.artifacts.bag[1], towerReceipt.artifacts[1], "综合快照真实神器与塔回执相同")
        h.env.math = finalMath
        eq(h.ES.getInventoryCount(modules.equipment), 200, "综合快照保持背包容量")
        check(#modules.lootbox.seeds > 0, "综合快照满包的确定装备入匣")
        local expected = { modules = F.copy(modules), gameState = h.GS.exportSave(),
            disk = cjson.decode(F.read(F.SAVE)), expectedLootCount = #modules.lootbox.seeds }
        F.writeExpected(expected)
        print(TAG .. " ALL PASS assertions=" .. assertions .. " realFile=true coldFixture=" .. F.SAVE)
    end)
    if not ok then log:Write(LOG_ERROR, TAG .. " FAIL after " .. assertions .. ": " .. tostring(err)) end
    engine:Exit()
end
