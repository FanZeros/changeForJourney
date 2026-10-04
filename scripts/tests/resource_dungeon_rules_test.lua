-- 资源副本规则回归：真实配置、出怪、服务、装备交付与JSON往返。
-- PDM仅替换为内存模块，不读取或写入真实玩家存档。
local DC = require("config.DungeonConfig")
local SC = require("config.StageConfig")
local Spawn = require("ui.battle.stage.BattleEnemySpawn")
local Service = require("rules.dungeon.DungeonService")
local Handler = require("rules.dungeon.DungeonHandler")
local PDM = require("rules.character.PlayerDataManager")
local ES = require("systems.EquipmentSystem")
local Protocol = require("shared.Protocol")
local cjson = require("cjson")

local assertions = 0
local function check(value, message)
    assertions = assertions + 1
    assert(value, message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end
local function newModules(count)
    local equipment = { inventory = {}, equipped = {}, nextSeq = 1 }
    local filler = assert(ES.generate("W1", 1, 1))
    for _ = 1, count or 0 do ES.addToInventory(equipment, copy(filler)) end
    local dungeon = {}
    for _, id in ipairs(DC.RESOURCE_IDS) do
        dungeon[id] = { floor = 1, cleared = {}, dailyUsed = 0, dailyDay = 0 }
    end
    dungeon.ancient_ruin = { floor = 5, cleared = { [4] = true }, dailyUsed = 0, dailyDay = 0 }
    dungeon.babel_tower = { floor = 7, cleared = { [6] = true }, buffs = { 1 } }
    return {
        equipment = equipment, lootbox = { seeds = {} }, dungeon = dungeon,
        currency = { gold = 10, gems = 20, arcaneDust = 30 },
        battle = { currentStageId = 2501, maxStageId = 2501, clearedStages = { [2305] = true },
            teamStageIds = { 2501, 1305, 605 } },
        heroes = { roster = { [1] = { level = 100 }, [2] = { level = 100 }, [3] = { level = 100 } },
            deployed = { 1 }, teams = { { slots = { 1 } }, { slots = { 2 } }, { slots = { 3 } } } },
    }
end

function Start()
    local modules = newModules(0)
    local dirty = {}
    local restores = {}
    local function patch(owner, key, value)
        local previous = owner[key]
        restores[#restores + 1] = function() owner[key] = previous end
        owner[key] = value
    end
    local ok, err = pcall(function()
        patch(PDM, "GetModule", function(_, key) return modules[key] end)
        patch(PDM, "MarkDirty", function(_, key) dirty[key] = (dirty[key] or 0) + 1 end)
        patch(os, "time", function() return 100000 end)

        eq(#DC.RESOURCE_IDS, 3, "三类资源副本")
        for _, id in ipairs(DC.RESOURCE_IDS) do
            eq(DC.DAILY_SWEEP_LIMIT[id], 2, "保留每日两次扫荡")
            check(DC.getCombatEntry(id, 0) == nil and DC.getCombatEntry(id, 1.5) == nil,
                "非法层号不构造配置")
            for floor = 1, DC.MAX_FLOOR[id] do
                local entry = assert(DC.getCombatEntry(id, floor))
                local source = assert(SC.getStage(entry.id))
                local sourceSnapshot = cjson.encode(source)
                local base = Spawn.generateEnemyList(source, true)
                local enemies = Spawn.generateEnemyList(entry, true)
                eq(#enemies, #base + 2, "真实敌人数为对应主线加二")
                eq(entry.maxFieldEnemies, 4, "同屏四敌人槽")
                local field, queue = Spawn.assignEnemiesToField(enemies, 4)
                eq(#field, math.min(4, #enemies), "四槽上场")
                eq(#field + #queue, #enemies, "后备数量守恒")
                eq(entry.fcGold + entry.fcExp + entry.fcDiamond + entry.fcEquip, 0, "禁止主线首通奖")
                eq(entry.dropRate + entry.scrollDropRate, 0, "禁止主线随机掉落")
                check(not SC.isTerminalTemple(entry.id), "不误入终焉协同")
                entry.monsters[1] = -1
                eq(cjson.encode(source), sourceSnapshot, "修改副本配置不污染主线")
                check(DC.getFloor(id, floor) ~= nil, "所有楼层都有奖励")
            end
        end

        -- 队伍/层号/解锁门禁和Handler完整回包。
        for _, id in ipairs(DC.RESOURCE_IDS) do
            modules = newModules(0)
            local battleBefore = cjson.encode(modules.battle)
            for team = 1, 3 do
                local reply = Handler.actionHandlers[Protocol.ACTION_TYPES.DUNGEON_CHALLENGE](1,
                    { dungeonId = id, floor = 1, teamIdx = team })
                check(reply.success and reply.resourceCombat and reply.stageEntry ~= nil, "真实Handler保留战斗配置")
                eq(reply.teamIdx, team, "回包锁队")
                eq(reply.maxFieldEnemies, 4, "回包同屏槽")
            end
            check(not select(1, Service.Challenge(1, id, 1, 0)), "非法队号拒绝")
            check(not select(1, Service.Challenge(1, id, 1, 1.5)), "小数队号拒绝")
            check(not select(1, Service.Challenge(1, id, 2, 1)), "只能当前层")
            modules.heroes.teams[3].slots = { 0, 0, 0, 0 }
            check(not select(1, Service.Challenge(1, id, 1, 3)), "空队拒绝")
            modules.battle.maxStageId = DC.UNLOCK_CONDITIONS[id] - 1
            check(not select(1, Service.Challenge(1, id, 1, 1)), "锁副本拒绝")
            modules.battle.maxStageId = 2501
            eq(cjson.encode(modules.battle), battleBefore, "挑战不改主线")
        end

        -- 各资源只发自己的首通奖，重复请求不重领，最大层账本JSON后仍防重。
        for _, id in ipairs(DC.RESOURCE_IDS) do
            modules = newModules(0)
            local before = copy(modules.currency)
            local battleBefore = cjson.encode(modules.battle)
            local reply = Handler.actionHandlers[Protocol.ACTION_TYPES.DUNGEON_WIN](1,
                { dungeonId = id, floor = 1, teamIdx = 1 })
            check(reply.success and reply.firstClear, "首通成功")
            eq(reply.nextFloor, 2, "推进独立副本层")
            eq(cjson.encode(modules.battle), battleBefore, "结算不改主线")
            local data = DC.getFloor(id, 1)
            if id == "gold_mine" then
                eq(modules.currency.gold - before.gold, data.firstGold, "金币副本奖励")
                eq(modules.currency.gems, before.gems, "金币不发黑钻")
            elseif id == "black_diamond" then
                eq(modules.currency.gems - before.gems, data.firstDiamond, "黑钻使用已有gems")
                eq(modules.currency.gold, before.gold, "黑钻不发金币")
            else
                eq(#reply.equips, 6, "装备首通六件")
                eq(ES.getInventoryCount(modules.equipment), 6, "六件实际入包")
                eq(modules.currency.gold, before.gold, "装备不发金币")
                for _, reward in ipairs(reply.equips) do
                    check(reward.equip and reward.destination == "inventory", "完整装备与去向")
                    check(reward.quality >= data.equipMinQuality and reward.quality <= data.equipMaxQuality,
                        "装备品质范围")
                end
            end
            eq(modules.currency.arcaneDust, before.arcaneDust, "三资源不发旧粉尘")
            local currencyAfter = cjson.encode(modules.currency)
            local equipAfter = cjson.encode(modules.equipment)
            check(not select(1, Service.Win(1, id, 1, 1)), "旧层重复胜利拒绝")
            eq(cjson.encode(modules.currency), currencyAfter, "重复不发货币")
            eq(cjson.encode(modules.equipment), equipAfter, "重复不发装备")
            local max = DC.MAX_FLOOR[id]
            modules.dungeon[id].floor = max
            modules.dungeon[id].cleared = { [tostring(max)] = true }
            modules.dungeon = cjson.decode(cjson.encode(modules.dungeon))
            local winOk, _, final = Service.Win(1, id, max, 1)
            check(winOk and not final.firstClear, "末层字符串键防重")
            eq(DC.getHighestClearedFloor(modules.dungeon[id], id), max, "末层可扫荡")
        end

        -- 装备满包/部分入包/缺安全容器/生成失败事务。
        for _, count in ipairs({ 0, 197, 199, 200, 201 }) do
            modules = newModules(count)
            local winOk, _, reply = Service.Win(1, "equipment_vault", 1, 2)
            check(winOk, "满包装备副本仍通关")
            local direct = math.min(6, math.max(0, 200 - count))
            eq(reply.inventoryCount, direct, "入包数")
            eq(reply.lootboxCount, 6 - direct, "溢出入匣数")
            eq(ES.getInventoryCount(modules.equipment), count + direct, "背包不扩容")
            eq(#modules.lootbox.seeds, 6 - direct, "遗匣守恒")
            eq(#reply.equips, 6, "回执保存每件实例")
        end
        modules = newModules(200)
        modules.lootbox = nil
        local before = cjson.encode(modules)
        check(not select(1, Service.Win(1, "equipment_vault", 1, 1)), "缺遗匣拒绝发奖")
        eq(cjson.encode(modules), before, "缺遗匣不写首通不推进")
        modules = newModules(0)
        local originalGenerate = ES.generateRandom
        local calls = 0
        patch(ES, "generateRandom", function(level, quality)
            calls = calls + 1
            if calls == 3 then return nil end
            return originalGenerate(level, quality)
        end)
        before = cjson.encode(modules)
        check(not select(1, Service.Win(1, "equipment_vault", 1, 1)), "中途生成失败拒绝整批")
        eq(cjson.encode(modules), before, "生成失败不部分发奖")
        ES.generateRandom = originalGenerate

        -- 每日扫荡两次、跨天恢复、最高已通末层与失败不扣次。
        for _, id in ipairs(DC.RESOURCE_IDS) do
            modules = newModules(200)
            modules.dungeon[id].floor = DC.MAX_FLOOR[id]
            modules.dungeon[id].cleared = { [DC.MAX_FLOOR[id]] = true }
            for used = 1, 2 do
                local sweepOk, _, reply = Service.Sweep(1, id)
                check(sweepOk, "每日扫荡成功")
                eq(reply.dailyUsed, used, "扫荡日次")
                eq(reply.sweepFloor, DC.MAX_FLOOR[id], "扫荡已通末层")
            end
            before = cjson.encode(modules)
            check(not select(1, Service.Sweep(1, id)), "第三次拒绝")
            eq(cjson.encode(modules), before, "耗尽不改数据")
            modules.dungeon[id].dailyDay = modules.dungeon[id].dailyDay - 1
            check(select(1, Service.Sweep(1, id)), "跨天再次可扫")
        end
        modules = newModules(200)
        modules.dungeon.equipment_vault.floor = 2
        modules.lootbox = nil
        before = cjson.encode(modules)
        check(not select(1, Service.Sweep(1, "equipment_vault")), "扫荡缺遗匣拒绝")
        eq(cjson.encode(modules), before, "扫荡失败不扣日次")
        check(not select(1, Service.Sweep(1, "unknown")), "未知副本拒绝")
        check(not select(1, Service.Win(1, "babel_tower", 1)), "塔不误用普通结算")
    end)
    for i = #restores, 1, -1 do restores[i]() end
    if ok then print("[resource_dungeon_rules_test] ALL PASS assertions=" .. assertions)
    else print("[resource_dungeon_rules_test] FAIL " .. tostring(err)) end
    engine:Exit()
end
