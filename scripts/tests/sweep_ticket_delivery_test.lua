-- 真实在线掉落出口验收：主线首通暂存/领取、挂机及资源券到账；不用正式Boot或玩家文件。
local F = require("tests.SweepRegressionFixture")
local cases, assertions, failures = 0, 0, {}
local function eq(a, b, name)
    assertions = assertions + 1
    assert(a == b, name .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function source(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"))
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function run(name, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. " => " .. tostring(err) end
    print("[sweep_ticket_delivery_test] " .. (ok and "PASS " or "FAIL ") .. name)
end
local function setup()
    local h = F.new()
    F.install(h)
    local env = setmetatable({}, { __index = h.env })
    local wallet, recipients, added = { sweepTicket = 5, gold = 11, gems = 13 }, {}, {}
    local GS = { addExp = function(amount) wallet.exp = (wallet.exp or 0) + amount end }
    for _, key in ipairs({ "sweepTicket", "weaponScroll", "offhandScroll", "armorScroll", "helmetScroll",
        "shoesScroll", "accessoryScroll", "gold", "gems", "essence" }) do
        local method = key:sub(1, 1):upper() .. key:sub(2)
        GS["get" .. method] = function() return wallet[key] or 0 end
        GS["set" .. method] = function(v) wallet[key] = v end
    end
    local text = source("boot.StandaloneBoot")
    local mapFirst = assert(text:find("local SCROLL_DROP_TO_REWARD =", 1, true))
    local takeFirst = assert(text:find("local function takePendingFcRewards(deferNotify)", mapFirst, true))
    local takeLast = assert(text:find("\nend", takeFirst, true)) + 4
    local applyFirst = assert(text:find("    local function applyKillDrop(data)", 1, true))
    local applyLast = assert(text:find("    BattleTriPage.setOnStageClear(", applyFirst, true))
    env.StageConfig, env.DungeonConfig, env.DropSystem = h.SC, h.DC, h.Drop
    env.GameState, env.EquipmentSystem, env.LootBoxSystem = GS, h.ES, h.LS
    env.BlacksmithConfig = h.require("config.BlacksmithConfig")
    env.pendingFcSeeds, env.pendingFcScrolls = {}, {}
    env.ClientDispatcher = { get = function(name) return h.data[name] end, notifySubscribers = function() end }
    env.CharacterPanel = { getTeamSlotIds = function() error("有击杀快照不能读当前队伍") end,
        addHeroesExp = function(ids, amount) recipients[#recipients + 1] = { ids = F.copy(ids), amount = amount } end }
    env.addKillEquipment = function(...) added[#added + 1] = { ... } end
    env.BattleScene = { setOnEnemyDrop = function(fn) h.single = fn end }
    env.BattleTriPage = { setOnDrop = function(fn) h.tri = fn end }
    local chunk = "local pendingFcSeeds,pendingFcScrolls=pendingFcSeeds,pendingFcScrolls\n"
        .. text:sub(mapFirst, takeLast) .. "\n" .. text:sub(applyFirst, applyLast - 1)
        .. "\nreturn { take=takePendingFcRewards, pending=function() return pendingFcScrolls end,"
        .. " seed=function(level,quality) pendingFcSeeds[#pendingFcSeeds+1]={level=level,quality=quality} end }"
    local result = assert(load(chunk, "@真实StandaloneBoot掉落出口", "t", env))()
    -- 精确编译固定首通赠装的正式生成/投递块，不复制算法或启动完整Boot。
    local fixedFirst = assert(text:find("        local fcEquips = DropSystem.generateFirstClearEquips(stageEntry)", 1, true))
    local fixedLast = assert(text:find("        -- 固定首通装备与暂存击杀装备全部投递后", fixedFirst, true))
    local helperLast = assert(text:find("\n--- 取出暂存掉落", mapFirst, true))
    result.fixed = assert(load(text:sub(mapFirst, helperLast - 1)
        .. "\nreturn function(stageEntry) local rewards = {}\n"
        .. text:sub(fixedFirst, fixedLast - 1) .. "\nreturn rewards end", "@真实StandaloneBoot固定首通", "t", env))()
    return h, wallet, recipients, added, result
end

local function testAutoEquipment()
    for _, path in ipairs({ "pending", "fixed" }) do
        run(path .. "新装备自动分解/旧实例不追溯/同RNG", function()
            local a, wa, _, _, ba = setup()
            local b, wb, _, _, bb = setup()
            local config = a.require("config.BlacksmithConfig")
            a.data.equipment.settings = { autoQuality = 0, autoLevel = 0 }
            b.data.equipment.settings = { autoQuality = 6, autoLevel = 0 }
            -- 已有装备虽然符合条件，也必须保留原实例与嵌套状态。
            local old = assert(a.ES.generate("W1", 1, 1))
            old.locked, old.testNested = true, { keep = { 7, 8 } }
            a.ES.addToInventory(a.data.equipment, old)
            b.ES.addToInventory(b.data.equipment, F.copy(old))
            a.LS.addEquipment(a.data.lootbox, F.copy(old))
            b.LS.addEquipment(b.data.lootbox, F.copy(old))
            local inventoryBefore, lootBefore = F.copy(b.data.equipment.inventory), F.copy(b.data.lootbox.seeds)
            a.seed, b.seed, a.rngCalls, b.rngCalls = 101, 101, 0, 0
            local function grant(h, boot)
                if path == "fixed" then return boot.fixed(assert(h.SC.getStage(1905))) end
                boot.seed(1, 1); boot.seed(7, 3); boot.seed(60, 6)
                return boot.take()
            end
            local ra, rb = grant(a, ba), grant(b, bb)
            eq(#ra > 0, true, "实际生成新装备")
            eq(#rb, #ra, "自动分解没有少生成")
            local total = 0
            for index, equip in ipairs(ra) do
                eq(equip.type, "equip", "关闭设置保留原装备回执")
                local amount = config.calcAutoDecomposeEssence(equip.quality, equip.level)
                total = total + amount
                eq(rb[index].type, "essence", "命中规则回执改精粹")
                eq(rb[index].amount, amount, "每件精粹精确同配置")
            end
            eq(wa.essence or 0, 0, "关闭不加精粹")
            eq(wb.essence, total, "仅新增掉落精粹入账一次")
            eq(F.equal(b.data.equipment.inventory, inventoryBefore), true, "已有库存全部保持")
            eq(F.equal(b.data.lootbox.seeds, lootBefore), true, "已有遗匣全部保持")
            eq(b.data.lootbox.autoDecomposeNotice.count, #ra, "通知仅统计新掉落")
            eq(b.data.lootbox.autoDecomposeNotice.essence, total, "通知与真实精粹一致")
            eq(a.rngCalls, b.rngCalls, "开关设置随机次数不变")
            eq(a.seed, b.seed, "开关设置RNG终态不变")
            if path == "pending" then
                eq(#bb.take(), 0, "失败或退出结算再次调用无奖励")
                eq(wb.essence, total, "重复pending不再发精粹")
            end
        end)
    end
    run("首通pending在结算时读设置/锁定安全/AND筛选", function()
        local h, wallet, _, _, boot = setup()
        local original = h.ES.generateRandom
        local generated = {}
        h.ES.generateRandom = function(level, quality)
            local equip = assert(original(level, quality))
            if #generated == 0 then equip.locked = true end
            generated[#generated + 1] = equip
            return equip
        end
        boot.seed(1, 1); boot.seed(7, 3); boot.seed(60, 1); boot.seed(7, 6)
        eq(#generated, 0, "pending阶段不提前生成或分解")
        h.data.equipment.settings = { autoQuality = 3, autoLevel = 7 }
        local rewards = boot.take()
        eq(#generated, 4, "结算生成全部原件")
        eq(rewards[1].type, "equip", "符合条件的锁定实例保留")
        eq(rewards[2].type, "essence", "双阈值都符合才分解")
        eq(rewards[3].type, "equip", "等级不符合保留")
        eq(rewards[4].type, "equip", "品质不符合保留")
        eq(wallet.essence, h.require("config.BlacksmithConfig").calcAutoDecomposeEssence(3, 7), "只结算第二件精粹")
        eq(h.ES.getInventoryCount(h.data.equipment), 3, "三保留件真实入库")
        eq(h.data.equipment.inventory[tostring(generated[1].seq)], generated[1], "锁定原实例无重骰")
        eq(#boot.take(), 0, "已结算pending幂等")
    end)
end

function Start()
    run("主线首通券只暂存，结算后到账一次并显示", function()
        local h, wallet, _, _, boot = setup()
        h.Drop.rollKillDrop = function() return nil end
        h.Drop.rollScrollDrop = function() return nil end
        h.forceRandom = 0.1
        h.tri({ stageId = 1905, teamIdx = 2, dropOnly = true })
        eq(wallet.sweepTicket, 5, "首通未提前到账")
        eq(boot.pending().sweepTicket, 1, "首通暂存券")
        local rewards = boot.take()
        eq(wallet.sweepTicket, 6, "结算到账")
        eq(rewards[1].type, "sweep_ticket", "回执资源类型")
        eq(rewards[1].amount, 1, "回执数量")
        eq(#boot.take(), 0, "重复结算不发")
        eq(wallet.sweepTicket, 6, "重复结算余额不变")
    end)
    run("主线挂机与默认Scene击杀券立即到账，不入遗匣", function()
        local h, wallet, _, _, boot = setup()
        h.Drop.rollKillDrop = function() return nil end
        h.Drop.rollScrollDrop = function() return nil end
        h.forceRandom = 0.1
        h.tri({ stageId = 1905, teamIdx = 3 })
        h.single({ stageId = 1905, teamIdx = 1, isFirstClear = false })
        eq(wallet.sweepTicket, 7, "两次击杀立即到账")
        eq(boot.pending().sweepTicket, nil, "没有首通暂存")
        eq(#h.data.lootbox.seeds, 0, "券不入遗匣")
    end)
    run("装备副本未掉装备仍可掉卷轴和券，按真实击杀快照发经验", function()
        local h, wallet, recipients, added = setup()
        local randoms = { 0.99, 0.01, 0.01, 0.01 }
        local index = 0
        h.env.math.random = function(a)
            if a then return 1 end
            index = index + 1
            return randoms[index] or 0.99
        end
        h.Drop.rollSweepTicket = function() error("资源不能重复roll主线券") end
        h.Drop.rollKillDrop = function() error("资源不能roll主线装备") end
        h.tri({ stageId = h.DC.getStageId("equipment_vault", 1), teamIdx = 2,
            heroIds = { 2, 3 }, dropOnly = true })
        eq(#added, 0, "零装备命中")
        eq(wallet.weaponScroll, 1, "卷轴真实到账")
        eq(wallet.sweepTicket, 6, "券真实到账")
        eq(recipients[1].ids[1], 2, "原队员1")
        eq(recipients[1].ids[2], 3, "原队员2")
        eq(wallet.gold, 11, "不发借用怪物金币")
    end)
    run("金币与黑晶副本不额外发主线券", function()
        for _, id in ipairs({ "gold_mine", "black_diamond" }) do
            local h, wallet = setup()
            h.Drop.rollSweepTicket = function() error("金币黑晶不能roll主线券") end
            h.Drop.rollKillDrop = function() error("金币黑晶不能roll主线装备") end
            h.tri({ stageId = h.DC.getStageId(id, 1), teamIdx = 1, heroIds = { 1 } })
            eq(wallet.sweepTicket, 5, id .. "无券")
            eq(wallet.exp > 0, true, id .. "经验到账")
        end
    end)
    testAutoEquipment()
    print(string.format("[sweep_ticket_delivery_test] SUMMARY cases=%d failures=%d assertions=%d",
        cases, #failures, assertions))
    for _, failure in ipairs(failures) do log:Write(LOG_ERROR, "[sweep_ticket_delivery_test] " .. failure) end
    engine:Exit()
end
