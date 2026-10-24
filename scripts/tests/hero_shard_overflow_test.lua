-- 英雄碎片容量/溢出专项。仅此新测试文件；不启动main/Boot，不联网，不读配置凭据/玩家档。
-- 宿主cache唯一用途：读取固定白名单Lua源码；沙箱File/FS/cache/cloud一律拒绝。
-- /workspace/.cli/UrhoXRuntime tests/hero_shard_overflow_test.lua \
--   -tapcode_dir=/workspace/changeForJourney -tool_mode -graphicsheadless -nosound
-- 必须看到 ALL PASS + checks/groups；Runtime exit=0本身不是测试通过证据。
local TAG = "[hero_shard_overflow_test] "
local nativeCache = cache
local sources = {} ---@type table<string, string>
local sourceReads = {} ---@type string[]
local failures = {} ---@type string[]
local checks, groups = 0, 0
local SOURCE_FILES = {
    ["shared.heroes.HeroShardPolicy"] = "shared/heroes/HeroShardPolicy.lua",
    ["rules.hero.HeroShardService"] = "rules/hero/HeroShardService.lua",
    ["rules.hero.HeroService"] = "rules/hero/HeroService.lua",
    ["rules.gacha.GachaService"] = "rules/gacha/GachaService.lua",
    ["rules.gacha.UrGachaService"] = "rules/gacha/UrGachaService.lua",
    ["rules.gacha.TavernService"] = "rules/gacha/TavernService.lua",
    ["rules.gacha.GachaHandler"] = "rules/gacha/GachaHandler.lua",
    ["rules.awakening.AwakeningService"] = "rules/awakening/AwakeningService.lua",
    ["rules.currency.CurrencyService"] = "rules/currency/CurrencyService.lua",
    ["rules.dungeon.DungeonService"] = "rules/dungeon/DungeonService.lua",
    ["shared.heroes.HeroesSchema"] = "shared/heroes/HeroesSchema.lua",
    ["shared.heroes.HeroResonance"] = "shared/heroes/HeroResonance.lua",
    ["shared.heroes.TeamSlots"] = "shared/heroes/TeamSlots.lua",
    ["config.GachaConfig"] = "config/GachaConfig.lua",
    ["config.UrGachaConfig"] = "config/UrGachaConfig.lua",
    ["config.TavernConfig"] = "config/TavernConfig.lua",
    ["config.AwakeningConfig"] = "config/AwakeningConfig.lua",
    ["config.ExpTable"] = "config/ExpTable.lua",
    ["config.ResourceDefs"] = "config/ResourceDefs.lua",
    -- 只提取并执行init末尾真实库存归并块，不执行Bridge其他初始化/Handler加载。
    ["runtime.LocalActionBridge"] = "runtime/LocalActionBridge.lua",
}
local function check(value, label)
    checks = checks + 1
    assert(value, label)
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, child in pairs(a) do if not same(child, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(name)
    local path = assert(SOURCE_FILES[name], "source denied: " .. tostring(name))
    if not sources[name] then
        local file = assert(nativeCache:GetFile(path), "allowlisted source unavailable: " .. path)
        assert(file:IsOpen() and file:GetMode() == FILE_READ, "source must be read-only: " .. path)
        local ok, text = pcall(function()
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            return table.concat(lines, "\n")
        end)
        file:Dispose()
        assert(ok, text)
        sources[name] = text
        sourceReads[#sourceReads + 1] = path
    end
    return sources[name]
end
local function owned(shards, stage)
    local awakening = { _awk3Migrated = true }
    for i = 1, stage or 0 do awakening[i] = true end
    return { level = 1, exp = 0, shards = shards or 0, awakening = awakening,
        _awk3Migrated = true, _shardMigrated = true }
end

local contexts = {} ---@type any[]
local function fixture()
    local h = { deps = {}, modules = {}, dirty = {}, task = {}, forbidden = {},
        snapshots = {}, saveMode = "ok", saveCalls = 0, flushImmediateCalls = 0,
        now = 1792800000, randomCalls = 0, sequence = {}, state = {}, notices = {} } ---@type any
    contexts[#contexts + 1] = h
    local env = {} ---@type any
    h.env = env
    -- 没有__index=_G，未知依赖绝不落回真实模块/磁盘/网络。
    for _, name in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select",
        "tonumber", "tostring", "type", "setmetatable", "getmetatable", "rawget", "rawset" }) do env[name] = _G[name] end
    env.math, env.string, env.table = copy(math), copy(string), copy(table)
    env._G = env
    env.print = function() end
    local function deny(label)
        return function()
            h.forbidden[#h.forbidden + 1] = label
            error("isolated shard test forbids " .. label)
        end
    end
    local function blocked(label)
        return setmetatable({}, { __index = function(_, key) return deny(label .. "." .. tostring(key)) end })
    end
    env.File, env.GetFileSystem = deny("File"), deny("GetFileSystem")
    for _, name in ipairs({ "fileSystem", "cache", "io", "network", "clientCloud", "serverCloud",
        "engine", "package", "debug" }) do env[name] = blocked(name) end
    env.loadfile, env.dofile, env.load = deny("loadfile"), deny("dofile"), deny("load")
    env.SubscribeToEvent, env.SendEvent = deny("SubscribeToEvent"), deny("SendEvent")
    env.os = { time = function() return h.now end, clock = function() return 1 end }
    env.math.random = function(a, b)
        h.randomCalls = h.randomCalls + 1
        if a ~= nil then return b and a or 1 end
        return #h.sequence > 0 and table.remove(h.sequence, 1) or .999
    end
    local function mock(name, values)
        h.deps[name] = setmetatable(values, { __index = function(_, method)
            return deny("unmocked " .. name .. "." .. tostring(method))
        end })
        return h.deps[name]
    end
    h.PDM = mock("rules.character.PlayerDataManager", {
        GetModule = function(uid, name) eq(uid, 1, "fixture uid隔离"); return h.modules[name] end,
        MarkDirty = function(uid, name)
            eq(uid, 1, "dirty uid隔离")
            h.dirty[#h.dirty + 1] = name
            h.notices[#h.notices + 1] = copy(h.modules)
        end,
        FlushImmediate = function() h.flushImmediateCalls = h.flushImmediateCalls + 1 end,
    })
    -- HeroConfig这里只替身ID/品质数据，不替身任何容量/保留/转币算法；真实配置负责成本与汇率。
    local heroData = {}
    for id = 1, 25 do
        local q = id <= 3 and 1 or id <= 9 and 2 or 3
        if id == 17 then q = 2 elseif id == 18 or id == 19 then q = 1
        elseif id == 16 or id == 20 or id == 25 then q = 4 end
        heroData[id] = { id = id, quality = q, classId = 1, name = "fixture" .. id }
    end
    mock("config.HeroConfig", { QUALITY_R = 1, QUALITY_SR = 2, QUALITY_SSR = 3, QUALITY_UR = 4,
        SHARD_SYNTHESIZE_COST = 10, SHARD_DUPE_CONVERT = 10,
        get = function(id) return heroData[id] end,
        getAllIds = function() local ids = {}; for i = 1, 25 do ids[i] = i end; return ids end })
    mock("systems.ExtraTalentSystem", { normalize = function(value) return copy(value or {}) end })
    mock("rules.task.TaskService", {
        UpdateProgress = function(uid, key, amount) h.task[#h.task + 1] = { uid, key, amount } end,
        RefreshAchievements = function() end,
    })
    h.GS = mock("core.GameState", {
        exportSave = function() return copy(h.state) end,
        syncFromCurrency = function(currency) h.state = copy(currency) end,
    })
    mock("shared.ModuleRegistry", { find = function() return nil end })
    mock("shared.schemas.CharacterSchema", { Fields = {} })
    -- Dungeon真实事务加载所需但本专项绝不调用的装备/副本叶子。
    for _, name in ipairs({ "config.DungeonConfig", "systems.EquipmentSystem", "systems.LootBoxSystem",
        "config.BlacksmithConfig" }) do mock(name, {}) end
    mock("shared.Protocol", { ACTION_TYPES = { DRAW_CARD = "draw_card", GACHA_PULL = "gacha_pull",
        STELLAR_TARGET_UP = "stellar_target_up", TAVERN_SHOP_BUY = "tavern_shop_buy" } })
    env.require = function(name)
        if h.deps[name] ~= nil then return h.deps[name] end
        if not SOURCE_FILES[name] or name == "runtime.LocalActionBridge" then return deny("require " .. tostring(name))() end
        local chunk, why = load(source(name), "@" .. SOURCE_FILES[name], "t", env)
        assert(chunk, why)
        local module = chunk()
        assert(type(module) == "table", "expected module table: " .. name)
        h.deps[name] = module
        return module
    end
    h.require = env.require
    h.reset = function(roster)
        h.modules = {
            heroes = { roster = copy(roster or {}), deployed = {}, teams = {},
                urShardConvertDayId = math.floor((h.now + 28800) / 86400), urShardConvertCount = 7 },
            currency = { gems = 1000000, gold = 1000, tavernCoin = 100000, privilegePoint = 10,
                recruitTicket = 100, stellarRecruitTicket = 100, gachaPitySR = 0, gachaPitySSR = 0,
                urPitySR = 0, urPitySSR = 0, urPityUR = 0 },
            session = { firstGachaTenDone = true }, battle = { maxStageId = 7001 },
            tavern = { shopPurchased = {}, shopDayId = math.floor((h.now + 28800) / 86400),
                shopWeekId = math.floor((h.now - 1704038400) / 604800) },
            dungeon = {}, equipment = {}, lootbox = {}, player = { level = 1, exp = 0 }, artifacts = {},
        }
        h.dirty, h.task, h.sequence, h.notices = {}, {}, {}, {}
        h.randomCalls, h.saveCalls, h.flushImmediateCalls, h.snapshots = 0, 0, 0, {}
        h.state = copy(h.modules.currency)
        h.saveMode = "ok"
        return h.modules
    end
    h.persist = function()
        h.saveCalls = h.saveCalls + 1
        if h.saveMode == "throw" then error("fixture save failure") end
        if h.saveMode == "false" then return false end
        if h.saveMode == "nil" then return nil end
        h.snapshots[#h.snapshots + 1] = copy(h.modules)
        return true
    end
    h.startup = function()
        local bridgeSource = source("runtime.LocalActionBridge")
        local first = assert(bridgeSource:find('    local Shards = require("rules.hero.HeroShardService")', 1, true),
            "真实Bridge.init缺少碎片归并接线")
        local last = assert(bridgeSource:find('    print("[LocalActionBridge] init uid=', first, true), "归并块结束锚点")
        local block = bridgeSource:sub(first, last - 1)
        check(block:find("preview = true", 1, true) ~= nil, "Bridge真实预检接线")
        check(block:find("CommitRewardTransaction", 1, true) ~= nil, "Bridge真实事务接线")
        local chunk, why = load("local LOCAL_UID=1\n" .. block, "@LocalActionBridge.init.shardReconcile", "t", env)
        assert(chunk, why)
        chunk()
    end
    h.reset()
    return h
end
local function group(label, fn)
    groups = groups + 1
    local ok, why = xpcall(fn, debug.traceback)
    if not ok then
        failures[#failures + 1] = label .. ": " .. tostring(why)
        print(TAG .. "FAIL " .. failures[#failures])
    else print(TAG .. "PASS " .. label) end
end
local function receipt(result, gain, overflow, coins, label)
    eq(type(result), "table", label .. "receipt")
    eq(result.shardGain, gain, label .. "实际新增片")
    eq(result.amount, gain, label .. "amount也是实际新增片")
    eq(result.overflowShards, overflow, label .. "超额片")
    eq(result.tavernCoin, coins, label .. "转币实际值")
end
local function noMutation(h, fn, label)
    local before, dirty, rng = copy(h.modules), #h.dirty, h.randomCalls
    eq(fn(), false, label .. "拒绝")
    check(same(h.modules, before), label .. "零库存/费用/日次变更")
    eq(#h.dirty, dirty, label .. "零通知")
    eq(h.randomCalls, rng, label .. "零RNG")
end

function Start()
    group("纯policy容量100/90/80/50/0与真实汇率", function()
        local h = fixture()
        local p, a, ur = h.require("shared.heroes.HeroShardPolicy"), h.require("config.AwakeningConfig"), h.require("config.UrGachaConfig")
        eq(a.getShardCost(1), 10, "觉醒I实际成本")
        eq(a.getShardCost(2), 30, "觉醒II实际成本")
        eq(a.getShardCost(3), 50, "觉醒III实际成本")
        for id = 1, 25 do
            eq(p.capacity(id, nil), 100, "未拥有hero" .. id)
            eq(p.capacity(id, { shards = 99 }), 100, "碎片存根未拥有" .. id)
            for stage, cap in ipairs({ 90, 80, 50, 0 }) do
                local entry = owned(0, stage - 1)
                local before = copy(entry)
                eq(p.capacity(id, entry), cap, "hero" .. id .. " stage" .. (stage - 1))
                check(same(entry, before), "capacity不迁移写回" .. id)
            end
        end
        for _, pair in ipairs({ {1,5}, {4,25}, {10,100}, {16,450}, {20,450}, {25,450} }) do
            eq(ur.getShardStardustValue(pair[1]), pair[2], "真实汇率hero" .. pair[1])
            local plan = assert(p.planGrant(pair[1], owned(0, 3), 10))
            receipt(plan, 0, 10, pair[2] * 10, "满觉醒hero" .. pair[1])
        end
        eq(p.capacity(1, { level=1, awakening={ [1]=true,[2]=true,[3]=true } }), 80, "未标记旧前三节点仅映新I")
        eq(p.capacity(1, { level=1, awakening={ [1]=true,[4]=true } }), 50, "旧1/4映新I/II")
        eq(p.capacity(1, { level=1, awakening={ [1]=true,[4]=true,[7]=true } }), 0, "旧七阶满觉醒")
        eq(p.capacity(1, { level=1, _awk3Migrated=true, awakening={ ['1']=true,['2']=true,['3']=true } }), 0,
            "hero级标记保护新三阶JSON字符串键")
        eq(p.capacity(0, nil), nil, "未知id拒绝")
    end)
    group("纯plan缺口边界/历史超额/安全整数与只读", function()
        local h = fixture()
        local p = h.require("shared.heroes.HeroShardPolicy")
        for stage, cap in ipairs({ 90, 80, 50, 0 }) do
            for _, incoming in ipairs({ 1, 10 }) do
                for _, before in ipairs({ math.max(0, cap - 1), cap, cap + 1 }) do
                    local entry = owned(before, stage - 1)
                    local snapshot = copy(entry)
                    local plan = assert(p.planGrant(1, entry, incoming))
                    local kept = math.min(incoming, math.max(0, cap - before))
                    local overflow = math.max(0, before + incoming - cap)
                    receipt(plan, kept, overflow, overflow * 5, "边界cap" .. cap .. "/before" .. before .. "/in" .. incoming)
                    eq(plan.afterShards, math.min(cap, before + incoming), "最终库存钳cap")
                    check(same(snapshot, entry), "plan不修改输入")
                end
            end
        end
        local stub = assert(p.planGrant(1, {shards=99}, 10))
        receipt(stub, 1, 9, 45, "未拥有cap100缺1")
        eq(stub.afterShards, 100, "stub只留100")
        for _, bad in ipairs({ 0, -1, .5, math.huge, -math.huge, 0/0, 9007199254740992, "10", false }) do
            eq(p.planGrant(1, owned(0), bad), nil, "拒绝bad grant=" .. tostring(bad))
            eq(p.isSafeInteger(bad), false, "安全整数拒绝=" .. tostring(bad))
        end
        eq(p.planGrant(1, owned(-1), 1), nil, "负库存拒绝")
        eq(p.planGrant(1, owned(.5), 1), nil, "小数库存拒绝")
        eq(p.planGrant(1, owned(9007199254740991), 1), nil, "累计安全整数溢出拒绝")
        eq(p.planGrant(16, owned(9007199254740991, 3), 0, {allowZero=true}), nil, "转币乘法安全溢出拒绝")
        check(p.planGrant(1, owned(0), 0, {allowZero=true}) ~= nil, "仅内部归并允许零输入")
    end)
    group("真实ShardService Grant/Plan/GrantHero/未知来源奖励", function()
        local h = fixture()
        local s, c = h.require("rules.hero.HeroShardService"), h.require("rules.currency.CurrencyService")
        h.reset({ [1] = owned(89) })
        local coin = h.modules.currency.tavernCoin
        local plan = assert(s.Plan(1, 1, 10))
        eq(h.modules.heroes.roster[1].shards, 89, "Plan不写库存")
        eq(#h.dirty, 0, "Plan不通知")
        receipt(plan, 1, 9, 45, "Plan89+10")
        local entryAlias = h.modules.heroes.roster[1]
        local ok, err, result = s.Grant(1, 1, 10)
        check(ok, "Grant实际成功 " .. tostring(err))
        eq(h.modules.heroes.roster[1], entryAlias, "Grant保留hero条目别名")
        eq(entryAlias.shards, 90, "Grant旧别名可见最终片数")
        receipt(result, 1, 9, 45, "Grant89+10")
        eq(h.modules.heroes.roster[1].shards, 90, "Grant最终90")
        eq(h.modules.currency.tavernCoin, coin + 45, "Grant币余额")
        for _, notice in ipairs(h.notices) do
            eq(notice.heroes.roster[1].shards, 90, "通知时已同时写片")
            eq(notice.currency.tavernCoin, coin + 45, "通知时已同时写币")
        end
        noMutation(h, function() return s.ApplyTo(h.modules.heroes, h.modules.currency, plan) end, "过期Plan")
        for _, bad in ipairs({ 0, -1, .1, math.huge, 0/0, 9007199254740992 }) do
            noMutation(h, function() return s.Grant(1, 1, bad) end, "Grant非法amount " .. tostring(bad))
        end
        noMutation(h, function() return s.Grant(1, 99999, 1) end, "Grant非法英雄")
        h.modules.currency.tavernCoin = 9007199254740991
        noMutation(h, function() return s.Grant(1, 1, 1) end, "币加法越界")
        for _, id in ipairs({1, 4, 10, 16}) do
            h.reset({ [id] = { shards = 100, _shardMigrated = true } })
            local beforeCoin = h.modules.currency.tavernCoin
            local granted, why, r = s.GrantHero(1, id)
            check(granted, "新整卡真实GrantHero " .. tostring(why))
            eq(r.isNew, true, "存根不是已有英雄")
            eq(r.type, "hero", "新整卡保留hero结果")
            receipt(r, 0, 10, h.require("config.UrGachaConfig").getShardStardustValue(id) * 10, "整卡使cap100->90")
            eq(h.modules.heroes.roster[id].shards, 90, "整卡只保留觉醒90")
            eq(h.modules.heroes.roster[id].level, 1, "真实解锁")
            eq(h.modules.currency.tavernCoin, beforeCoin + r.tavernCoin, "整卡旧库存返币")
        end
        h.reset({ [1]=owned(90) })
        check(c.GrantReward(1,{type="shard",heroId=1,amount=3}), "统一Currency shard来源")
        eq(h.modules.heroes.roster[1].shards,90,"Currency shard不超cap")
        eq(h.modules.currency.tavernCoin,100015,"Currency shard转实际币")
        local defs = h.require("config.ResourceDefs")
        local legacy = assert(defs.HERO_TO_SHARD_ID[1], "真实旧碎片ID映射")
        check(c.GrantReward(1,{type=tostring(legacy),amount=2}),"旧数字奖励ID进入统一服务")
        eq(h.modules.currency.tavernCoin,100025,"旧数字ID也转币")
        eq(c.GrantRewards(1,{{type="shard",heroId=1,amount=2},{type="gold",amount=7}}),2,"批量奖励计成功项")
        eq(h.modules.currency.tavernCoin,100035,"批量碎片实际币")
        eq(h.modules.currency.gold,1007,"批量非碎片奖励不受影响")
        for _, reward in ipairs({{type="shard",heroId=1,amount=.5},{type="shard",heroId=999,amount=1},
            {type="shard",heroId=1,amount=math.huge},{type="unknown",amount=10}}) do
            noMutation(h,function() return c.GrantReward(1,reward) end,"奖励来源非法边界")
        end
    end)
    group("真实普通/UR招募：一抽一结果、缺1保1余9转币", function()
        local h = fixture()
        local normal, stellar = h.require("rules.gacha.GachaService"), h.require("rules.gacha.UrGachaService")
        local gc, uc = h.require("config.GachaConfig"), h.require("config.UrGachaConfig")
        for _, spec in ipairs({ {pool="standard",id=1,quality=1,rate=5}, {pool="stellar",id=16,quality=4,rate=450} }) do
            for _, count in ipairs({1,10}) do
                h.reset({ [spec.id] = owned(89) })
                local cfg = spec.pool == "standard" and gc or uc
                local original = cfg.getPoolGroup
                cfg.getPoolGroup = function()
                    return { items={{type="hero",heroId=spec.id,quality=spec.quality,weight=1}},totalWeight=1 }
                end
                local ok, err, result = normal.GachaPull(1,count,"ticket",spec.pool)
                cfg.getPoolGroup = original
                check(ok,"真实招募 " .. spec.pool .. " " .. tostring(err))
                eq(#result.gachaResults,count,"一抽一结果不追加币结果")
                eq(result.poolId,spec.pool,"回执pool")
                for i, r in ipairs(result.gachaResults) do
                    eq(r.index,i,"顺序index")
                    eq(r.heroId,spec.id,"真实英雄id")
                    receipt(r,i==1 and 1 or 0,i==1 and 9 or 10,(i==1 and 9 or 10)*spec.rate,"draw"..i)
                end
                eq(h.modules.heroes.roster[spec.id].shards,90,"多抽最终不超90")
                eq(h.modules.currency.tavernCoin,100000+(count*10-1)*spec.rate,"多抽实际币总和")
                local key = spec.pool == "standard" and "recruitTicket" or "stellarRecruitTicket"
                eq(h.modules.currency[key],100-count,"只扣实际抽数券")
                eq(h.modules.currency.gems,1000000,"券抽不扣钻")
                eq(h.modules.currency.gachaDrawStats[spec.pool].total,count,"抽数统计不计附加币行")
            end
        end
        -- 原生碎片奖（非重复整卡），以及普通兜底无pool条目，都必须真正发奖并归并。
        for _, fallback in ipairs({false,true}) do
            h.reset({[1]=owned(90)})
            local original = gc.getPoolGroup
            gc.getPoolGroup = function()
                if fallback then return nil end
                return {items={{type="shard",heroId=1,quality=0,amount=1,weight=1}},totalWeight=1}
            end
            local ok, why, result = normal.GachaPull(1,1,"ticket","standard")
            gc.getPoolGroup = original
            check(ok,"原片/兜底实际授予 " .. tostring(why))
            eq(#result.gachaResults,1,"原片/兜底一抽一结果")
            receipt(result.gachaResults[1],0,1,5,"原片/兜底超额")
            eq(h.modules.currency.tavernCoin,100005,"原片/兜底实际加币")
            eq(h.modules.heroes.roster[1].shards,90,"原片/兜底不超cap")
        end
        -- 普通与星辰都通过真实整卡解锁存根，不能保留原100片。
        for _, spec in ipairs({{pool="standard",id=1,quality=1,rate=5},{pool="stellar",id=16,quality=4,rate=450}}) do
            h.reset({[spec.id]={shards=100,_shardMigrated=true}})
            local cfg = spec.pool == "standard" and gc or uc
            local original = cfg.getPoolGroup
            cfg.getPoolGroup = function() return {items={{type="hero",heroId=spec.id,quality=spec.quality,weight=1}},totalWeight=1} end
            local ok, why, result = normal.GachaPull(1,1,"ticket",spec.pool)
            cfg.getPoolGroup = original
            check(ok,"存根抽中整卡 " .. tostring(why))
            eq(#result.gachaResults,1,"存根整卡仍一个结果")
            eq(result.gachaResults[1].isNew,true,"存根解锁新卡")
            receipt(result.gachaResults[1],0,10,10*spec.rate,"存根整卡回执")
            eq(h.modules.heroes.roster[spec.id].shards,90,"存根整卡cap变小")
        end
        -- 满觉醒UR不得继续囤片；所有整卡转10片等价币，一抽仍只一行。
        for _, spec in ipairs({{pool="standard",id=1,q=1,rate=5},{pool="stellar",id=16,q=4,rate=450}}) do
            h.reset({[spec.id]=owned(0,3)})
            local cfg=spec.pool=="standard" and gc or uc
            local original=cfg.getPoolGroup
            cfg.getPoolGroup=function() return {items={{type="hero",heroId=spec.id,quality=spec.q,weight=1}},totalWeight=1} end
            local ok,why,result=normal.GachaPull(1,1,"ticket",spec.pool)
            cfg.getPoolGroup=original
            check(ok,"满觉醒真实整卡 "..tostring(why))
            eq(#result.gachaResults,1,"满觉醒一抽一行")
            eq(result.gachaResults[1].type,"decompose","纯币结果不能仍宣称新增碎片")
            receipt(result.gachaResults[1],0,10,10*spec.rate,"满觉醒真实回执")
            eq(h.modules.heroes.roster[spec.id].shards,0,"满觉醒包括UR不留片")
            eq(h.modules.currency.tavernCoin,100000+10*spec.rate,"满觉醒包括UR实际入币")
        end
        eq(type(stellar.Pull),"function","真实星辰服务加载")
    end)
    group("真实GachaHandler回执不丢实际碎片/币信息", function()
        local h=fixture()
        local handler=h.require("rules.gacha.GachaHandler")
        local at=h.require("shared.Protocol").ACTION_TYPES
        local cfg=h.require("config.GachaConfig")
        cfg.getPoolGroup=function() return {items={{type="hero",heroId=1,quality=1,weight=1}},totalWeight=1} end
        h.reset({[1]=owned(89)})
        local reply=handler.actionHandlers[at.GACHA_PULL](1,{count=1,payType="ticket",poolId="standard"})
        eq(reply.success,true,"Handler真实调用服务成功")
        eq(#reply.gachaResults,1,"Handler不追加奖励行")
        receipt(reply.gachaResults[1],1,9,45,"Handler保留完整实际回执")
        noMutation(h,function()
            return handler.actionHandlers[at.GACHA_PULL](1,{count=2,payType="diamond"}).success
        end,"Handler非法count传递服务拒绝")
    end)
    group("十连暂存失败不泄露live条目，成功原别名可见最新库存", function()
        local h=fixture()
        local g,s=h.require("rules.gacha.GachaService"),h.require("rules.hero.HeroShardService")
        for _, spec in ipairs({{pool="standard",id=1,q=1},{pool="stellar",id=16,q=4}}) do
            local cfg=h.require(spec.pool=="standard" and "config.GachaConfig" or "config.UrGachaConfig")
            local originalGroup=cfg.getPoolGroup
            cfg.getPoolGroup=function() return {items={{type="hero",heroId=spec.id,quality=spec.q,weight=1}},totalWeight=1} end
            for _, failedAt in ipairs({2,5,10}) do
                h.reset({[spec.id]=owned(3)})
                h.modules.session.firstGachaTenDone=false
                local originalPlan=s.PlanHeroFor
                local before,liveHeroes,liveRoster,liveEntry,liveCurrency=copy(h.modules),h.modules.heroes,
                    h.modules.heroes.roster,h.modules.heroes.roster[spec.id],h.modules.currency
                local calls=0
                s.PlanHeroFor=function(...)
                    calls=calls+1
                    eq(liveEntry.shards,3,"暂存第"..calls.."抽不得提前修改live hero")
                    check(same(h.modules,before),"暂存第"..calls.."抽live全部不变")
                    if calls==failedAt then return nil,"fixture failed draw" end
                    return originalPlan(...)
                end
                local ok=g.GachaPull(1,10,"ticket",spec.pool)
                s.PlanHeroFor=originalPlan
                eq(ok,false,"第"..failedAt.."抽失败整十连拒绝")
                eq(calls,failedAt,"在目标抽失败后立即停止")
                check(same(h.modules,before),"失败不扣费/保底/任务/首次十连状态")
                eq(h.modules.heroes,liveHeroes,"失败heroes别名")
                eq(liveHeroes.roster,liveRoster,"失败roster别名")
                eq(liveRoster[spec.id],liveEntry,"失败hero别名")
                eq(h.modules.currency,liveCurrency,"失败currency别名")
                eq(#h.dirty,0,"失败零通知")
                eq(h.flushImmediateCalls,0,"失败零Flush")
                eq(#h.task,0,"失败零任务计数")
            end
            h.reset({[spec.id]=owned(3)})
            local heroes,roster,entry,currency=h.modules.heroes,h.modules.heroes.roster,
                h.modules.heroes.roster[spec.id],h.modules.currency
            local ok,why,result=g.GachaPull(1,10,"ticket",spec.pool)
            check(ok,"真实十连成功 "..tostring(why))
            eq(#result.gachaResults,10,"成功十行")
            eq(h.modules.heroes,heroes,"成功heroes别名")
            eq(heroes.roster,roster,"成功roster别名")
            eq(roster[spec.id],entry,"成功hero别名")
            eq(entry.shards,90,"旧hero别名看到最终90")
            eq(h.modules.currency,currency,"成功currency别名")
            cfg.getPoolGroup=originalGroup
        end
    end)
    group("普通/UR非法count只能1或10且拒绝不扣费", function()
        local h = fixture()
        local g = h.require("rules.gacha.GachaService")
        for _, pool in ipairs({"standard","stellar"}) do
            for _, count in ipairs({0,-1,2,3,9,11,1.5,math.huge,-math.huge,0/0,9007199254740992,"bad",false}) do
                h.reset({[1]=owned(0),[16]=owned(0)})
                noMutation(h,function() return g.GachaPull(1,count,"diamond",pool) end,pool.." count="..tostring(count))
                eq(h.flushImmediateCalls,0,"非法count不能flush")
                eq(#h.task,0,"非法count不计招募任务")
            end
        end
        h.reset({[16]=owned(0)})
        h.modules.battle.maxStageId=1001
        noMutation(h,function() return g.GachaPull(1,1,"ticket","stellar") end,"UR未解锁")
    end)
    group("商店钳缺口与UR互转超量拒绝/日限不变", function()
        local h = fixture()
        local shop, hero, tc = h.require("rules.gacha.TavernService"), h.require("rules.hero.HeroService"), h.require("config.TavernConfig")
        for _, id in ipairs({1,4,10,16}) do
            local item = {}
            for _, candidate in ipairs(tc.SHOP_ITEMS) do
                if candidate.rewardType=="shard" and candidate.rewardHeroId==id then item=candidate; break end
            end
            check(item.id~=nil,"真实碎片商品hero"..id)
            h.reset({[id]=owned(89)})
            local result=shop.ShopBuy(1,item.id,10)
            eq(result.success,true,"缺1允许只买1")
            eq(result.quantity,1,"商店实际数量钳1")
            eq(result.shardGain,1,"商店回执仅实际保留1片")
            eq(result.amount,1,"商店amount只记实际1片")
            eq(result.overflowShards,0,"商店不得购买溢出片")
            eq(#result.rewards,1,"商店仅一条实际奖励")
            eq(result.rewards[1].type,"shard","商店奖励类型")
            eq(result.rewards[1].heroId,id,"商店奖励目标")
            eq(result.rewards[1].amount,1,"商店rewards不谎报请求10片")
            eq(h.modules.heroes.roster[id].shards,90,"商店只入1")
            eq(h.modules.currency.tavernCoin,100000-item.price,"商店只扣1价不多扣不转币套利")
            eq(h.modules.tavern.shopPurchased[item.id],1,"购买台账实际1")
            noMutation(h,function() return shop.ShopBuy(1,item.id,10).success end,"已够用后商店拒购")
            h.reset({[id]={shards=99,_shardMigrated=true}})
            noMutation(h,function() return shop.ShopBuy(1,item.id,1).success end,"未拥有不能购片")
            h.reset({[id]=owned(89)})
            h.modules.currency.tavernCoin=item.price
            eq(shop.ShopBuy(1,item.id,10).success,true,"先钳缺口后验余额，只够1份也能购1")
            eq(h.modules.currency.tavernCoin,0,"先钳缺口只扣一份实际余额")
            for _, bad in ipairs({0,-1,.5,math.huge,0/0,9007199254740992}) do
                noMutation(h,function() return shop.ShopBuy(1,item.id,bad).success end,"商店非法数量 "..tostring(bad))
            end
        end
        h.reset({[16]=owned(40),[20]=owned(89)})
        noMutation(h,function() return hero.ConvertUrShard(1,16,20,2) end,"UR目标缺1拒绝转2")
        local ok, why, result=hero.ConvertUrShard(1,16,20,1)
        check(ok,"UR精确缺口成功 "..tostring(why))
        eq(result.amount,1,"UR实际转换量")
        eq(h.modules.heroes.roster[16].shards,39,"UR来源扣1")
        eq(h.modules.heroes.roster[20].shards,90,"UR目标到cap")
        eq(h.modules.heroes.urShardConvertCount,8,"日限只记1")
        eq(h.modules.currency.tavernCoin,100000,"UR互转不应溢出转币")
        noMutation(h,function() return hero.ConvertUrShard(1,16,20,1) end,"目标满后不扣来源与日限")
        h.reset({[16]=owned(40),[20]=owned(0)})
        h.modules.heroes.urShardConvertCount=30
        noMutation(h,function() return hero.ConvertUrShard(1,16,20,1) end,"旧每日30上限不变")
        for _, bad in ipairs({0,-1,.5,math.huge,0/0}) do
            h.reset({[16]=owned(40),[20]=owned(0)})
            noMutation(h,function() return hero.ConvertUrShard(1,16,20,bad) end,"UR非法amount "..tostring(bad))
        end
        h.reset({[16]=owned(40),[20]={shards=99,_shardMigrated=true}})
        check(hero.ConvertUrShard(1,16,20,1),"UR未拥有stub按100cap")
        eq(h.modules.heroes.roster[20].shards,100,"UR存根100不提前解锁")
        eq(h.modules.heroes.roster[20].level,nil,"UR转换不伪造拥有")
        h.reset({[16]=owned(40),[20]=owned(89)})
        h.modules.heroes.urShardConvertDayId=h.modules.heroes.urShardConvertDayId-1
        h.modules.heroes.urShardConvertCount=30
        noMutation(h,function() return hero.ConvertUrShard(1,16,20,2) end,"跨日但超目标缺口拒绝也不改日限账本")
    end)
    group("合成/觉醒消耗与旧档dupe迁移不截断不重复补偿", function()
        local h=fixture()
        local hero, awakening, policy=h.require("rules.hero.HeroService"),h.require("rules.awakening.AwakeningService"),h.require("shared.heroes.HeroShardPolicy")
        h.reset({[1]={shards=100,_shardMigrated=true}})
        check(hero.SynthesizeHero(1,1),"真实合成消耗10")
        eq(h.modules.heroes.roster[1].shards,90,"合成后90")
        eq(policy.capacity(1,h.modules.heroes.roster[1]),90,"合成拥有cap90")
        for node, remain in ipairs({80,50,0}) do
            local ok,why=awakening.Activate(1,1,node)
            check(ok,"真实觉醒节点"..node.." "..tostring(why))
            eq(h.modules.heroes.roster[1].shards,remain,"觉醒消耗后余片")
            eq(policy.capacity(1,h.modules.heroes.roster[1]),remain,"觉醒后容量同步减少")
        end
        eq(h.modules.currency.tavernCoin,100000,"消耗觉醒不额外转币")
        local hs=h.require("shared.heroes.HeroesSchema")
        h.reset({['1']={level=1,dupeCount=12,shards=5,awakening={['1']=true,['4']=true,['7']=true}}})
        hs.Fields.heroes.onLoad(h.modules.heroes)
        local entry=h.modules.heroes.roster[1]
        eq(entry.shards,140,"旧dupe只迁移未消费9份x15+5，Schema不能静默截片")
        eq(policy.capacity(1,entry),0,"旧7阶迁移满觉醒cap0")
        local s=h.require("rules.hero.HeroShardService")
        local ok,why,r=s.ReconcileAll(1)
        check(ok,"迁移后归并 "..tostring(why))
        eq(r.tavernCoin,700,"旧库存全部补币")
        eq(h.modules.currency.tavernCoin,100700,"旧档补币入账")
        hs.Fields.heroes.onLoad(h.modules.heroes)
        local again,_,rr=s.ReconcileAll(1)
        check(again,"旧迁移重入")
        eq(rr.changed,false,"重复onLoad/归并幂等")
        eq(h.modules.currency.tavernCoin,100700,"不重复迁移dupe/补币")
    end)
    group("ReconcileAll纯预检/静默/批量幂等与异常零修改", function()
        local h=fixture()
        local s=h.require("rules.hero.HeroShardService")
        h.reset({[1]=owned(97),[4]=owned(92),['16']=owned(3,3),[10]={shards=103,_shardMigrated=true}})
        local before=copy(h.modules)
        local ok,why,preview=s.ReconcileAll(1,{preview=true,silent=true})
        check(ok,"归并preview "..tostring(why))
        eq(preview.changed,true,"preview有变化")
        eq(preview.overflowShards,15,"preview超额7+2+3+3")
        eq(preview.tavernCoin,1735,"preview币35+50+1350+300")
        check(same(h.modules,before),"preview完全只读")
        eq(#h.dirty,0,"preview零dirty")
        local applied,_,r=s.ReconcileAll(1,{silent=true})
        check(applied,"静默归并")
        eq(r.tavernCoin,preview.tavernCoin,"preview/实际币一致")
        eq(#h.dirty,0,"silent零推送由事务掌控")
        eq(h.modules.heroes.roster[1].shards,90,"R钳90")
        eq(h.modules.heroes.roster[4].shards,90,"SR钳90")
        eq(h.modules.heroes.roster[16].shards,0,"UR满觉醒无剩片")
        eq(h.modules.heroes.roster['16'],nil,"字符串键归一不重复英雄")
        eq(h.modules.heroes.roster[10].shards,100,"未拥有保合成+觉醒100")
        local after=copy(h.modules)
        local again,_,rr=s.ReconcileAll(1)
        check(again,"二次归并成功")
        eq(rr.changed,false,"二次无变化")
        eq(rr.tavernCoin,0,"二次不再补币")
        check(same(h.modules,after),"二次库存不变")
        eq(#h.dirty,0,"二次不通知")
        h.reset({[1]=owned(100),[4]=owned(-1)})
        noMutation(h,function() return s.ReconcileAll(1) end,"一项非法不得先改另一英雄")
        h.reset({[1]=owned(100),['1']=owned(100)})
        noMutation(h,function() return s.ReconcileAll(1) end,"重复numeric/string键不得双倍补偿")
    end)
    group("真实Bridge归并块+真实Dungeon事务：成功/false/nil/throw/重试", function()
        for _, mode in ipairs({"ok","false","nil","throw"}) do
            local h=fixture()
            h.reset({[1]=owned(99),['16']=owned(2,3)})
            local tx=h.require("rules.dungeon.DungeonService")
            tx.SetPersistCallback(h.persist)
            local modules,roster,entry,currency=h.modules,h.modules.heroes.roster,h.modules.heroes.roster[1],h.modules.currency
            local before,gsBefore=copy(modules),copy(h.state)
            h.saveMode=mode
            h.startup()
            eq(h.saveCalls,1,"changed启动只尝试一次保存 "..mode)
            if mode~="ok" then
                check(same(modules,before),"保存失败原位还原所有值 "..mode)
                check(same(h.state,gsBefore),"保存失败还原GameState "..mode)
                eq(modules.heroes.roster,roster,"失败保留roster别名")
                eq(modules.heroes.roster[1],entry,"失败保留hero别名")
                eq(modules.currency,currency,"失败保留currency别名")
                eq(#h.dirty,0,"失败不发候选通知")
                eq(#h.snapshots,0,"失败未提交内存保存")
                h.saveMode="ok"
                h.startup()
                eq(h.saveCalls,2,"失败后同库存可重试")
            end
            eq(modules.heroes.roster[1].shards,90,"成功R保留90")
            eq(modules.heroes.roster[16].shards,0,"成功UR满觉醒归零")
            eq(modules.currency.tavernCoin,100945,"成功只补9x5+2x450")
            eq(#h.snapshots,1,"仅成功一次完整快照")
            eq(h.snapshots[1].currency.tavernCoin,100945,"快照含最终币")
            eq(h.snapshots[1].heroes.roster[16].shards,0,"快照含最终片")
            eq(#h.dirty,2,"成功只发heroes/currency通知")
            for _, notice in ipairs(h.notices) do
                eq(notice.currency.tavernCoin,100945,"通知发生于完整提交后")
                eq(notice.heroes.roster[16].shards,0,"通知无半归并状态")
            end
            local saves,dirty=h.saveCalls,#h.dirty
            h.startup()
            eq(h.saveCalls,saves,"启动块重复幂等不保存")
            eq(#h.dirty,dirty,"启动块重复不通知")
            eq(modules.currency.tavernCoin,100945,"重复不补币")
        end
    end)
    group("隔离白名单完整性", function()
        check(#sourceReads>=15,"真实production模块已读取执行而非全mock")
        for _, h in ipairs(contexts) do eq(#h.forbidden,0,"无未知require/File/FS/cloud访问") end
        for _, path in ipairs(sourceReads) do
            check(path:sub(-4)==".lua" and not path:find("..",1,true),"仅读固定Lua源码")
        end
        check(checks>500,"断言计数非空证明")
    end)
    if #failures==0 then
        print(TAG .. "ALL PASS checks="..checks.." groups="..groups.." sources="..#sourceReads.." playerIO=false network=false")
    else
        print(TAG .. "FAILED checks="..checks.." groups="..groups.." failures="..#failures)
        log:Write(LOG_ERROR,TAG .. table.concat(failures,"\n"))
    end
    engine:Exit()
end
