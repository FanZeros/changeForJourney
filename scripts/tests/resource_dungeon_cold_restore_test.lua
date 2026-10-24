-- 必须在transaction入口结束后的另一独立Runtime进程运行，真实File冷读并清理专用测试文件。
local F = require("tests.ResourceDungeonPersistenceFixture")
local TAG = "[resource_dungeon_cold_restore_test]"
local assertions = 0
local function check(value, label) assertions = assertions + 1; assert(value, label) end
local function eq(a, b, label) check(a == b, label .. ": " .. tostring(a) .. " / " .. tostring(b)) end

function Start()
    local ok, err = pcall(function()
        local expected = cjson.decode(F.read(F.EXPECTED))
        local diskBefore = F.read(F.SAVE)
        local stored = cjson.decode(diskBefore)
        local h = F.new() -- 冷编译真实Dispatcher/Registry/Schema/Save，所有运行时pending初始为空。
        local expectedAffix = expected.modules.equipment.inventory["200"].affixes[1].value
        -- Save.RestoreData 会把每模块重新 encode({modules={...}}) 再交给 Dispatcher decode。
        -- 期望复现相同的精确 JSON 流水，不使用 epsilon 或舍入容差掩盖数值漂移。
        for _, name in ipairs({ "dungeon", "currency", "equipment", "lootbox", "battle", "artifacts" }) do
            F.same(expected.modules[name], stored.modules[name], "期望文件与实际保存模块完全一致/" .. name)
            local transported = cjson.decode(cjson.encode({ modules = { [name] = expected.modules[name] } }))
            expected.modules[name] = transported.modules[name]
        end
        local transportedAffix = expected.modules.equipment.inventory["200"].affixes[1].value
        -- expected 同样经过 JSON，稀疏数字键已转成字符串；先按正式双 onLoad 还原形状。
        -- 原始账本逐条核对和值数一致，不能让规范化掩盖首通记录丢失。
        local rawCleared = {}
        for id, sub in pairs(expected.modules.dungeon) do
            if type(sub) == "table" and type(sub.cleared) == "table" then
                rawCleared[id] = F.copy(sub.cleared)
            end
        end
        for _, name in ipairs({ "dungeon", "currency", "equipment", "lootbox", "battle", "artifacts" }) do
            local data = expected.modules[name]
            local registered = h.Registry.find(name)
            if registered and registered.onLoad then registered.onLoad(data) end
            local schema = h.Schema.Fields[name]
            if schema and schema.onLoad then schema.onLoad(data) end
        end
        for id, cleared in pairs(rawCleared) do
            local count = 0
            for key, value in pairs(cleared) do
                local floor = math.tointeger(tonumber(key) or 0)
                check(floor and floor > 0 and value == true, "期望原始首通键值有效")
                eq(expected.modules.dungeon[id].cleared[floor], value, "期望规范化保留每条原首通")
                count = count + 1
            end
            local restoredCount = 0
            for _ in pairs(expected.modules.dungeon[id].cleared) do restoredCount = restoredCount + 1 end
            eq(restoredCount, count, "期望规范化不增删首通记录")
        end
        eq(next(h.Dispatcher.getAll()), nil, "新进程无内存模块")
        check(h.Save.RestoreData(), "真实File通过StandaloneSave恢复")
        h.PDM.AttachLocalModules(1, h.Dispatcher.getAll())
        local modules = h.Dispatcher.getAll()
        local actualAffix = modules.equipment.inventory["200"].affixes[1].value
        print(TAG .. string.format(" affix200 stored=%.17g expectedOnce=%.17g transported=%.17g actual=%.17g",
            stored.modules.equipment.inventory["200"].affixes[1].value,
            expectedAffix, transportedAffix, actualAffix))
        eq(actualAffix, transportedAffix, "实际水合词条等于精确双JSON流水，不能重骰或再改精度")
        F.same(modules.dungeon, expected.modules.dungeon, "双onLoad冷恢复副本账本/日次/余秒/游标")
        F.same(modules.currency, expected.modules.currency, "冷恢复奖励余额")
        eq(modules.currency.sweepTicket, stored.modules.currency.sweepTicket,
            "一券一场扣除及合法挂机所得券余额按真实File冷恢复")
        eq(modules.currency.sweepTicket, expected.modules.currency.sweepTicket, "冷恢复不返还已消费扫荡券")
        F.same(modules.equipment, expected.modules.equipment, "冷恢复确定背包装备")
        F.same(modules.lootbox, expected.modules.lootbox, "冷恢复确定遗匣装备")
        F.same(modules.battle, expected.modules.battle, "主线进度保持")
        F.same(modules.artifacts, expected.modules.artifacts, "冷恢复塔21确定神器及实例计数")
        eq(#modules.artifacts.bag, 1, "冷恢复塔21成功首通神器仅一件")
        eq(h.GS.getGold(), expected.gameState.gold, "GameState金币真实落盘")
        eq(h.GS.getGems(), expected.gameState.gems, "GameState黑钻真实落盘")
        eq(#modules.lootbox.seeds, expected.expectedLootCount, "完整入匣装备冷恢复")
        for _, id in ipairs(h.DC.RESOURCE_IDS) do
            eq(modules.dungeon[id].floor, 2, "冷恢复独立副本层")
            eq(modules.dungeon[id].cleared[1], true, "冷恢复首通记录")
            eq(modules.dungeon[id].dailyUsed, 0, "冷恢复新扫荡不扣旧每日次数")
            eq(h.Service.Win(1, id, 2, 2), false, "冷恢复不保留内存pending不能伪Win")
        end
        eq(modules.dungeon.ancient_ruin.idleAccumSec, 88000, "旧粉尘未被新资源挪用")
        eq(modules.dungeon[h.TC.DUNGEON_ID].floor, 22, "塔21真实首通后独立进度冷恢复")
        eq(modules.dungeon.compat.towerSingleWaveV2, true, "冷恢复保留单波历史冻结标记")
        eq(stored.modules.dungeon.compat.towerSingleWaveV2, true, "历史冻结标记通过真实File落盘")
        for floor = 1, 21 do
            eq(modules.dungeon[h.TC.DUNGEON_ID].cleared[floor], true, "冷恢复旧冻结历史及新首通/" .. floor)
        end
        local towerClearedCount = 0
        for _ in pairs(modules.dungeon[h.TC.DUNGEON_ID].cleared) do towerClearedCount = towerClearedCount + 1 end
        eq(towerClearedCount, 21, "冷恢复塔1..21历史不增删")
        local before = F.copy(modules)
        for _ = 1, 3 do
            for _, name in ipairs({ "dungeon", "currency", "equipment", "lootbox", "artifacts" }) do
                h.Registry.applyOnLoad(name, modules[name])
                h.Schema.applyOnLoad(name, modules[name])
            end
        end
        F.same(modules, before, "Registry/Schema双onLoad重复值幂等")
        eq(F.read(F.SAVE), diskBefore, "只读冷恢复不回写旧真实File")
        -- 再次冷实例恢复同一文件，不沿用上次onLoad或pending状态。
        local second = F.new()
        check(second.Save.RestoreData(), "第二个冷实例仍使用真实File")
        F.same(second.Dispatcher.get("dungeon"), modules.dungeon, "二次冷恢复不重进层不重发奖")
        F.same(second.Dispatcher.get("lootbox"), modules.lootbox, "二次冷恢复不重骰装备")
        F.same(second.Dispatcher.get("artifacts"), modules.artifacts, "二次冷恢复不重骰塔神器")
        -- 原只读逐字节/二次冷恢复断言完成后，再真实重打冻结第1层；不重发首通黑钻。
        local towerService = h.require("rules.tower.TowerService")
        eq(towerService.FloorWin(1, 21), false, "冷进程不能沿用已提交塔楼层pending")
        h.env.math = F.copy(math)
        h.env.math.random = function(a, b)
            if a == nil then return 0.99 end -- 本次重打不命中神器，不影响冷恢复原物。
            return b == nil and 1 or a
        end
        h.committed = true -- Challenge只通知已落盘进度，不表示候选奖励已提交。
        local challenged, challengeErr, initial = towerService.Challenge(1, 1)
        check(challenged, "冷恢复可真实重打冻结第1层 " .. tostring(challengeErr))
        check(towerService.WaveWin(1, 1, 1, initial), "冷恢复重打真实单波")
        local gemsBefore, artifactsBefore = modules.currency.gems, F.copy(modules.artifacts)
        h.committed = false
        local succeeded, winErr, receipt = towerService.FloorWin(1, 1, initial)
        check(succeeded, "冷恢复重打真实File事务提交 " .. tostring(winErr))
        eq(receipt.firstClear, false, "冷恢复冻结历史不能再次首通")
        eq(receipt.diamondReward, 0, "冷恢复重打第1层不发黑钻")
        eq(modules.currency.gems, gemsBefore, "冷恢复重打实际黑钻余额不变")
        eq(modules.dungeon.babel_tower.floor, 22, "冷恢复重打不倒退22层进度")
        F.same(modules.artifacts, artifactsBefore, "重打未命中不变更冷恢复神器")
        local repeatedDisk = cjson.decode(F.read(F.SAVE))
        eq(repeatedDisk.modules.currency.gems, gemsBefore, "重打零黑钻通过真实File保存")
        eq(repeatedDisk.modules.dungeon.babel_tower.floor, 22, "重打不倒退通过真实File保存")
        for _, path in ipairs({ F.SAVE, F.PENDING, F.EXPECTED }) do
            if fileSystem:FileExists(path) then check(fileSystem:Delete(path), "删除仅测试专用文件") end
        end
        print(TAG .. " ALL PASS assertions=" .. assertions .. " realFile=true")
    end)
    if not ok then log:Write(LOG_ERROR, TAG .. " FAIL after " .. assertions .. ": " .. tostring(err)) end
    engine:Exit()
end
