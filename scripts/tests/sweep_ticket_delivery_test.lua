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
        "shoesScroll", "accessoryScroll", "gold", "gems" }) do
        local method = key:sub(1, 1):upper() .. key:sub(2)
        GS["get" .. method] = function() return wallet[key] or 0 end
        GS["set" .. method] = function(v) wallet[key] = v end
    end
    local text = source("boot.StandaloneBoot")
    local mapFirst = assert(text:find("local SCROLL_DROP_TO_REWARD =", 1, true))
    local takeFirst = assert(text:find("local function takePendingFcRewards()", mapFirst, true))
    local takeLast = assert(text:find("\nend", takeFirst, true)) + 4
    local applyFirst = assert(text:find("    local function applyKillDrop(data)", 1, true))
    local applyLast = assert(text:find("    BattleTriPage.setOnStageClear(", applyFirst, true))
    env.StageConfig, env.DungeonConfig, env.DropSystem = h.SC, h.DC, h.Drop
    env.GameState, env.EquipmentSystem, env.LootBoxSystem = GS, h.ES, h.LS
    env.pendingFcSeeds, env.pendingFcScrolls = {}, {}
    env.ClientDispatcher = { get = function(name) return h.data[name] end, notifySubscribers = function() end }
    env.CharacterPanel = { getTeamSlotIds = function() error("有击杀快照不能读当前队伍") end,
        addHeroesExp = function(ids, amount) recipients[#recipients + 1] = { ids = F.copy(ids), amount = amount } end }
    env.addKillEquipment = function(...) added[#added + 1] = { ... } end
    env.BattleScene = { setOnEnemyDrop = function(fn) h.single = fn end }
    env.BattleTriPage = { setOnDrop = function(fn) h.tri = fn end }
    local chunk = "local pendingFcSeeds,pendingFcScrolls=pendingFcSeeds,pendingFcScrolls\n"
        .. text:sub(mapFirst, takeLast) .. "\n" .. text:sub(applyFirst, applyLast - 1)
        .. "\nreturn { take=takePendingFcRewards, pending=function() return pendingFcScrolls end }"
    local result = assert(load(chunk, "@真实StandaloneBoot掉落出口", "t", env))()
    return h, wallet, recipients, added, result
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
    print(string.format("[sweep_ticket_delivery_test] SUMMARY cases=%d failures=%d assertions=%d",
        cases, #failures, assertions))
    for _, failure in ipairs(failures) do log:Write(LOG_ERROR, "[sweep_ticket_delivery_test] " .. failure) end
    engine:Exit()
end
