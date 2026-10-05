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
        for _, name in ipairs({ "dungeon", "currency", "equipment", "lootbox", "battle" }) do
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
        for _, name in ipairs({ "dungeon", "currency", "equipment", "lootbox", "battle" }) do
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
        F.same(modules.equipment, expected.modules.equipment, "冷恢复确定背包装备")
        F.same(modules.lootbox, expected.modules.lootbox, "冷恢复确定遗匣装备")
        F.same(modules.battle, expected.modules.battle, "主线进度保持")
        eq(h.GS.getGold(), expected.gameState.gold, "GameState金币真实落盘")
        eq(h.GS.getGems(), expected.gameState.gems, "GameState黑钻真实落盘")
        eq(#modules.lootbox.seeds, expected.expectedLootCount, "完整入匣装备冷恢复")
        for _, id in ipairs(h.DC.RESOURCE_IDS) do
            eq(modules.dungeon[id].floor, 2, "冷恢复独立副本层")
            eq(modules.dungeon[id].cleared[1], true, "冷恢复首通记录")
            eq(modules.dungeon[id].dailyUsed, 1, "冷恢复扫荡次数")
            eq(h.Service.Win(1, id, 2, 2), false, "冷恢复不保留内存pending不能伪Win")
        end
        eq(modules.dungeon.ancient_ruin.idleAccumSec, 88000, "旧粉尘未被新资源挪用")
        eq(modules.dungeon.babel_tower.floor, 21, "塔独立旧进度")
        local before = F.copy(modules)
        for _ = 1, 3 do
            for _, name in ipairs({ "dungeon", "currency", "equipment", "lootbox" }) do
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
        for _, path in ipairs({ F.SAVE, F.PENDING, F.EXPECTED }) do
            if fileSystem:FileExists(path) then check(fileSystem:Delete(path), "删除仅测试专用文件") end
        end
        print(TAG .. " ALL PASS assertions=" .. assertions .. " realFile=true")
    end)
    if not ok then log:Write(LOG_ERROR, TAG .. " FAIL after " .. assertions .. ": " .. tostring(err)) end
    engine:Exit()
end
