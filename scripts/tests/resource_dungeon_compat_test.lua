-- 三资源副本存档/挂机兼容专项；只编译正式脚本资源，存档与发奖边界使用内存替身。
-- 不初始化 PDM/Boot，不读取真实档，不发起网络请求。
local TAG = "[resource_dungeon_compat_test]"
local assertions = 0

local function eq(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end

function Start()
    local ok, err = pcall(function()
        local now = 1720000000
        local today = math.floor((now + 28800) / 86400)
        local env = setmetatable({ os = { time = function() return now end } }, { __index = _G })
        local real, mocks, loading = {}, {}, {}
        local allowed = {
            ["config.DungeonConfig"] = true, ["config.DungeonIdleConfig"] = true,
            ["config.TowerConfig"] = true, ["config.StageConfig"] = true,
            ["shared.dungeon.DungeonSchema"] = true, ["shared.dungeon.DungeonCompat"] = true,
            ["shared.ModuleRegistry"] = true, ["rules.dungeon.DungeonIdleService"] = true,
        }
        local function compile(name)
            local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少脚本 " .. name)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            return assert(load(table.concat(lines, "\n"), "@" .. name, "t", env))()
        end
        env.require = function(name)
            if mocks[name] then return mocks[name] end
            if real[name] then return real[name] end
            assert(allowed[name] or name:match("^config%.StageConfig_"), "禁止未声明依赖或存档入口: " .. name)
            assert(not loading[name], "循环依赖 " .. name)
            loading[name] = true
            local value = compile(name)
            loading[name] = nil
            real[name] = value
            return value
        end
        local DC = env.require("config.DungeonConfig")
        local IC = env.require("config.DungeonIdleConfig")
        local TC = env.require("config.TowerConfig")
        local Compat = env.require("shared.dungeon.DungeonCompat")
        local Schema = env.require("shared.dungeon.DungeonSchema").Fields.dungeon
        local Registry = env.require("shared.ModuleRegistry")
        local registered = assert(Registry.find("dungeon"))
        local ids = { "gold_mine", "equipment_vault", "black_diamond", "ancient_ruin", "babel_tower" }

        local default, other = Schema.getDefault(), registered.getDefault()
        for _, id in ipairs(ids) do
            eq(default[id].floor, 1, id .. "默认层1")
            eq(other[id].idleAccumSec, 0, id .. "两入口挂机字段")
            check(default[id] ~= other[id] and default[id].cleared ~= other[id].cleared, id .. "独立工厂")
        end
        local old = {
            gold_mine = { floor = "39", cleared = { ["38"] = true }, dailyUsed = "1", dailyDay = today, idleAccumSec = "90061", custom = "gold" },
            ancient_ruin = { floor = "57", cleared = { ["56"] = true }, dailyUsed = "2", dailyDay = today, idleAccumSec = "88000", custom = "dust" },
            babel_tower = { floor = "21", cleared = { ["20"] = true }, dailyUsed = 1, dailyDay = today, buffs = { 2, 5 }, idleAccumSec = 7201 },
            compat = { monsterBuffV1 = true }, customTop = { keep = true },
        }
        Schema.onLoad(old)
        Schema.onServerLoad(old)
        eq(old.gold_mine.floor, 39, "旧金币进度不回退")
        eq(old.ancient_ruin.floor, 57, "旧遗迹保留进度")
        eq(old.ancient_ruin.idleAccumSec, 88000, "旧粉尘不转换不清空")
        eq(old.gold_mine.idleAccumSec, 90061, "旧金币积累保持")
        eq(old.babel_tower.floor, 21, "塔独立进度")
        eq(old.babel_tower.buffs[2], 5, "塔强化保留")
        eq(old.customTop.keep, true, "未知旧字段保留")
        for _, id in ipairs({ "equipment_vault", "black_diamond" }) do
            eq(old[id].floor, 1, id .. "不继承旧进度")
            eq(next(old[id].cleared), nil, id .. "不复制旧首通")
            eq(old[id].idleAccumSec, 0, id .. "不复制旧积累")
            eq(old[id].dailyDay, today, id .. "初始化日序号")
        end
        local snapshot = cjson.encode(old)
        registered.onLoad(old)
        Compat.onLoad(old)
        Schema.onServerLoad(old)
        eq(cjson.encode(old), snapshot, "两入口重复加载幂等")
        local jsonRoundTrip = cjson.decode(snapshot)
        Compat.onLoad(jsonRoundTrip)
        eq(jsonRoundTrip.gold_mine.cleared[38], true, "cjson首通整数键")
        eq(jsonRoundTrip.ancient_ruin.cleared[56], true, "cjson粉尘账本保留")

        local malformed = {
            equipment_vault = { floor = "5.9", cleared = { ["4"] = 1, ["5"] = false, ["2.5"] = true, ["0"] = true, bad = true }, dailyUsed = -2, dailyDay = today, idleAccumSec = "61.9" },
            black_diamond = { floor = 2, cleared = { ["2"] = true }, dailyUsed = 2, dailyDay = today - 1, idleAccumSec = -1 },
            babel_tower = { buffs = "bad" },
        }
        Compat.onLoad(malformed)
        eq(malformed.equipment_vault.floor, 5, "层号规范整数")
        eq(malformed.equipment_vault.cleared[4], true, "旧truthy记录转true")
        eq(malformed.equipment_vault.cleared[2.5], nil, "不接受小数账本键")
        eq(malformed.equipment_vault.cleared[0], nil, "不接受零层账本键")
        eq(malformed.equipment_vault.dailyUsed, 0, "负计数归零")
        eq(malformed.equipment_vault.idleAccumSec, 61, "秒数取整")
        eq(malformed.black_diamond.floor, 3, "已通卡层向前修复")
        eq(malformed.black_diamond.dailyUsed, 0, "新副本跨日重置")
        eq(malformed.black_diamond.dailyDay, today, "跨日更新标记")
        eq(malformed.black_diamond.idleAccumSec, 0, "负积累归零")
        eq(type(malformed.babel_tower.buffs), "table", "塔结构补全")
        local preMigration = {
            gold_mine = { floor = 40 }, ancient_ruin = { floor = 40 }, babel_tower = { floor = 40 },
            equipment_vault = { floor = 40 }, black_diamond = { floor = 40 }, compat = {},
        }
        eq(Compat.migrateMonsterBuffV1(preMigration), true, "旧难度迁移仍存在")
        eq(preMigration.ancient_ruin.floor, Compat.rollbackFloorForBuffV1(40), "旧遗迹首次原难度回退")
        eq(preMigration.babel_tower.floor, Compat.rollbackFloorForBuffV1(40), "旧塔首次原难度回退")
        eq(preMigration.equipment_vault.floor, 40, "旧难度迁移不碰装备")
        eq(preMigration.black_diamond.floor, 40, "旧难度迁移不碰黑钻")
        eq(Compat.migrateMonsterBuffV1(preMigration), false, "迁移不重复")

        eq(DC.MAX_FLOOR.equipment_vault, 109, "装备109层")
        eq(DC.MAX_FLOOR.black_diamond, 115, "黑钻115层")
        for _, id in ipairs({ "gold_mine", "equipment_vault", "black_diamond" }) do
            local last = DC.MAX_FLOOR[id]
            eq(IC.getIdleFloorFromSub({ floor = last, cleared = { [tostring(last)] = true } }, id), last, id .. "挂机读已通末层")
            eq(IC.getIdleFloorFromSub({ floor = 1, cleared = {} }, id), 0, id .. "新档无挂机收益")
            check(IC.getSweepReward(id, last) > 0, id .. "末层收益存在")
        end
        local equip = assert(DC.getFloor("equipment_vault", 109))
        eq(equip.firstEquip, 6, "装备首通6件")
        eq(equip.sweepEquip, 3, "装备扫荡3件")
        check(IC.getIdlePerMin("equipment_vault", 109) > 0 and IC.getIdlePerMin("equipment_vault", 109) < 1, "装备每分钟允许小数")
        for _, seconds in ipairs({ 60, 14399, 14400, 86400, 172800, IC.HARD_CAP_SEC, IC.HARD_CAP_SEC + 86400 }) do
            local amount, minutes = IC.calcReward("equipment_vault", 109, seconds)
            local expected = math.floor(math.floor(IC.effectiveSeconds(seconds) / 60) * 6 / 1440)
            eq(amount, expected, "装备累计件数floor sec=" .. seconds)
            local neededSeconds = amount <= 6 and amount * 14400 or (86400 + (amount - 6) * 28800)
            eq(minutes, math.floor(neededSeconds / 60), "装备只扣整件所需分钟 sec=" .. seconds)
        end
        eq(IC.calcReward("equipment_vault", 109, 86400), 6, "24h仅两次扫荡不会几千件")
        eq(IC.calcReward("equipment_vault", 109, IC.HARD_CAP_SEC), 24, "7日装备尾段24件")
        for _, entry in ipairs({
            { id = "gold_mine", sweep = DC.getGoldMineFloor(38).sweepGold },
            { id = "ancient_ruin", sweep = DC.getAncientRuinFloor(56).sweepDust },
            { id = "babel_tower", sweep = TC.getFloor(20).sweepDiamond },
        }) do
            local floor = entry.id == "gold_mine" and 38 or (entry.id == "ancient_ruin" and 56 or 20)
            local perMin = math.max(1, math.floor(entry.sweep / 720))
            eq(IC.getIdlePerMin(entry.id, floor), perMin, entry.id .. "旧每分钟口径")
            eq(IC.calcReward(entry.id, floor, 172800), math.floor(IC.effectiveSeconds(172800) / 60) * perMin * 2, entry.id .. "旧倍率尾段不变")
        end
        eq(IC.getIdleFloorFromSub({ floor = 21, cleared = { [21] = true } }, "babel_tower"), 20, "独立塔保持旧挂机口径")
        eq(IC.getSweepReward("unknown", 1), 0, "未知ID无收益")
        eq(IC.REWARD_TYPE.ancient_ruin, "arcane_dust", "旧遗迹仍发粉尘")
        for _, id in ipairs(IC.DUNGEON_IDS) do check(id ~= "ancient_ruin", "古迹停止新积累") end

        local modules = { dungeon = old, battle = { maxStageId = 99999 }, session = { lastOnlineTime = now - 3600 } }
        local state = { dirty = 0, flushed = 0, grants = 0, fail = false, currencyGrants = 0,
            expectedCount = 6, expectedSec = 86437, totalEquip = 0 }
        mocks["rules.character.PlayerDataManager"] = {
            GetModule = function(_, name) return modules[name] end,
            MarkDirty = function() state.dirty = state.dirty + 1 end,
            FlushImmediate = function() state.flushed = state.flushed + 1 end,
        }
        mocks["rules.currency.CurrencyService"] = {
            GrantReward = function(_, reward)
                check(reward.type ~= "equip", "装备不走货币服务")
                state.currencyGrants = state.currencyGrants + 1
                state.lastCurrency = reward
                return true
            end,
        }
        mocks["rules.dungeon.DungeonService"] = {
            GrantEquipment = function(uid, id, floor, count)
                eq(uid, 0, "装备调用UID")
                eq(id, "equipment_vault", "装备调用ID")
                eq(floor, 109, "装备调用末层")
                eq(count, state.expectedCount, "装备请求件数")
                eq(modules.dungeon[id].idleAccumSec, state.expectedSec, "交付前不扣积累")
                state.grants = state.grants + 1
                if state.fail then return false, "容量不足", nil end
                state.totalEquip = state.totalEquip + count
                local equips = {}
                for i = 1, count do equips[i] = { seq = i, level = equip.equipLevel } end
                return true, nil, { equips = equips, inventoryCount = 4, lootboxCount = 2 }
            end,
        }
        local Service = env.require("rules.dungeon.DungeonIdleService")
        local stored = cjson.encode(old)
        eq(Service.Preview(0, "unknown"), nil, "未知预览拒绝")
        local unknownOk, unknownErr = Service.Claim(0, "unknown")
        eq(unknownOk, false, "未知领取拒绝")
        eq(unknownErr, "未知副本", "未知ID不能默认金币")
        eq(cjson.encode(old), stored, "未知ID不创建子结构")
        local newOk = Service.Claim(0, "equipment_vault")
        eq(newOk, false, "新装备未通关不发奖")
        old.equipment_vault = { floor = 109, cleared = { [109] = true }, idleAccumSec = 86437 }
        state.fail = true
        local failOk, failErr = Service.Claim(0, "equipment_vault")
        eq(failOk, false, "装备交付失败")
        eq(failErr, "容量不足", "交付错误透传")
        eq(old.equipment_vault.idleAccumSec, 86437, "失败不扣积累")
        eq(state.dirty, 0, "失败不标记持久化")
        eq(state.flushed, 0, "失败不持久化")
        state.fail = false
        local claimOk, _, result = Service.Claim(0, "equipment_vault")
        eq(claimOk, true, "装备领取成功")
        eq(#result.equips, 6, "装备实例回包")
        eq(result.inventoryCount, 4, "背包交付数量回包")
        eq(result.lootboxCount, 2, "遗匣交付数量回包")
        eq(result.accumSec, 37, "成功后扣原始分钟保留秒余量")
        eq(state.currencyGrants, 0, "装备不增任何货币")
        eq(state.flushed, 1, "成功后立即持久化")
        eq(Service.Claim(0, "equipment_vault"), false, "重复领取不重发")
        eq(state.grants, 2, "失败加成功仅两次尝试")
        local dustAmount = IC.calcReward("ancient_ruin", 56, old.ancient_ruin.idleAccumSec)
        modules.battle.maxStageId = 101
        local dustOk, _, dust = Service.Claim(0, "ancient_ruin")
        eq(dustOk, true, "隐藏旧粉尘存量仍可领取")
        eq(dust.amount, dustAmount, "旧粉尘原数量不转换")
        eq(state.lastCurrency.type, "arcane_dust", "旧粉尘发原资源")
        local dustSec = old.ancient_ruin.idleAccumSec
        modules.battle.maxStageId = 99999
        Service.SyncOfflineOnEnter(0)
        Service.HandleIdleAccum(0, 65.5)
        eq(old.ancient_ruin.idleAccumSec, dustSec, "旧遗迹不新增在线离线积累")
        Service.Cleanup(0)
        local function fixture(seconds, consumed)
            old.equipment_vault = { floor = 109, cleared = { [109] = true }, idleAccumSec = seconds,
                idleConsumedSec = consumed or 0 }
        end
        local function claimEquip(expected, label)
            state.expectedCount = expected
            state.expectedSec = old.equipment_vault.idleAccumSec
            local claimSuccess, claimError, claimed = Service.Claim(0, "equipment_vault")
            check(claimSuccess, label .. "领取成功: " .. tostring(claimError))
            eq(claimed.amount, expected, label .. "件数")
            eq(#claimed.equips, expected, label .. "实例数")
            return claimed
        end
        fixture(5 * 3600)
        local five = claimEquip(1, "5h")
        eq(five.accumSec, 3600, "5h发1件留1h")
        eq(five.idleConsumedSec, 14400, "5h游标4h")
        eq(Service.Claim(0, "equipment_vault"), false, "1h尾数重复点不发件")
        eq(old.equipment_vault.idleAccumSec, 3600, "重复点不丢尾数")
        old.equipment_vault.idleAccumSec = old.equipment_vault.idleAccumSec + 3 * 3600
        claimEquip(1, "余1h再累积3h")
        eq(old.equipment_vault.idleAccumSec, 0, "累计8h发2件余0")
        eq(old.equipment_vault.idleConsumedSec, 0, "清空即开启新轮")
        fixture(8 * 3600)
        claimEquip(2, "单次8h")
        eq(old.equipment_vault.idleAccumSec, 0, "8h无损整额消费")
        fixture(24 * 3600)
        claimEquip(6, "单次24h")
        eq(old.equipment_vault.idleConsumedSec, 0, "24h全额后游标重置")
        fixture(30 * 3600)
        local thirty = claimEquip(6, "单次30h")
        eq(thirty.accumSec, 6 * 3600, "30h保留6h原始尾段")
        eq(thirty.idleConsumedSec, 24 * 3600, "30h游标停全速末尾")
        eq(Service.Preview(0, "equipment_vault").amount, 0, "6h尾段不足1件不升全速")
        old = cjson.decode(cjson.encode(old))
        modules.dungeon = old
        Compat.onLoad(old)
        eq(old.equipment_vault.idleConsumedSec, 24 * 3600, "JSON往返保留尾段游标")
        eq(Service.Preview(0, "equipment_vault").amount, 0, "JSON往返领取口径幂等")
        old.equipment_vault.idleAccumSec = old.equipment_vault.idleAccumSec + 2 * 3600
        local tail = claimEquip(1, "尾段6h加2h")
        eq(tail.accumSec, 0, "尾段需8h换1件")
        eq(tail.idleConsumedSec, 0, "尾段清空开启新轮")

        -- 不清空的同一周期，5h后每次再加4h，多次领取与一次25h完全等价。
        fixture(5 * 3600)
        local beforeTotal = state.totalEquip
        claimEquip(1, "分批起点5h")
        for round = 1, 5 do
            old.equipment_vault.idleAccumSec = old.equipment_vault.idleAccumSec + 4 * 3600
            local expected = 1
            local preview = Service.Preview(0, "equipment_vault")
            eq(preview.amount, expected, "分批每4h整件 round=" .. round)
            if expected > 0 then claimEquip(expected, "分批round=" .. round) end
        end
        eq(state.totalEquip - beforeTotal, IC.calcReward("equipment_vault", 109, 25 * 3600), "分批与单次25h件数一致")
        eq(old.equipment_vault.idleAccumSec, 3600, "分批25h保留1h未付尾段")
        eq(old.equipment_vault.idleConsumedSec, 24 * 3600, "分批周期游标24h")

        -- 7日cap以游标加余量计；已付首24h后不能再累积完整7日。
        fixture(6 * 86400 - 60, 86400)
        Service.HandleIdleAccum(0, 120)
        eq(old.equipment_vault.idleAccumSec, 6 * 86400, "在线cap包括已消费游标")
        eq(Service.Preview(0, "equipment_vault").amount, 18, "尾段7日总额不因先领重发")
        claimEquip(18, "先领24h后的7日尾段")
        eq(old.equipment_vault.idleAccumSec, 0, "7日尾段全额清空")
        eq(old.equipment_vault.idleConsumedSec, 0, "7日清空游标不永远卡顶")
        Service.Cleanup(0)
        modules.session.lastOnlineTime = now - 4 * 3600
        Service.SyncOfflineOnEnter(0)
        eq(old.equipment_vault.idleAccumSec, 4 * 3600, "7日清空后离线新轮仍累积")
        claimEquip(1, "7日之后新轮4h")
        fixture(5 * 86400, 86400)
        Service.Cleanup(0)
        modules.session.lastOnlineTime = now - 3 * 86400
        Service.SyncOfflineOnEnter(0)
        eq(old.equipment_vault.idleAccumSec, 6 * 86400, "离线cap包括游标")
        fixture(IC.HARD_CAP_SEC)
        claimEquip(24, "单次7日")
        eq(old.equipment_vault.idleConsumedSec, 0, "单次7日清空重置")
        eq(Service.Claim(0, "equipment_vault"), false, "7日领奖重复点不重发")
        eq(default.equipment_vault.idleConsumedSec, 0, "Schema仅装备游标默认0")
        eq(default.gold_mine.idleConsumedSec, nil, "金币不新增游标字段")
        print(TAG .. " ALL PASS: " .. assertions .. " assertions")
    end)
    if not ok then log:Write(LOG_ERROR, TAG .. " FAIL after " .. assertions .. " assertions: " .. tostring(err)) end
    engine:Exit()
end
