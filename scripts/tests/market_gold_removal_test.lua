-- 黑市下架金币专项：复用 auto_diamond_exchange_test 的白名单源码 + load(env) 隔离脚手架。
-- 真实 MarketService / CurrencyService / Handler，仅 PDM 使用内存，不加载 main、不访问玩家档。
-- 界面仅执行真实商品配置片段，验证列表与价格，不代表实际绘图或像素验收。
local TAG = "[market_gold_removal_test] "
local assertions, failures, forbidden = 0, 0, 0
local function check(value, message)
    assertions = assertions + 1
    if not value then failures = failures + 1; print(TAG .. "FAIL " .. message) end
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " 实际=" .. tostring(actual) .. " 预期=" .. tostring(expected))
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
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local ALLOWED = {
    ["rules.market.MarketService"] = true, ["rules.market.MarketHandler"] = true,
    ["rules.currency.CurrencyService"] = true, ["config.ResourceDefs"] = true,
    ["shared.market.StellarDiamondQuota"] = true, ["shared.artifact.ArtifactDefs"] = true,
    ["shared.Protocol"] = true, ["ui.market.MarketPage"] = true,
}
local sources = {} ---@type table<string, string>
local function source(name)
    assert(ALLOWED[name], "拒绝非白名单源码 " .. name)
    if not sources[name] then
        local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少源码 " .. name)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        sources[name] = table.concat(lines, "\n")
    end
    return sources[name]
end
local function denied()
    forbidden = forbidden + 1
    error("隔离测试禁止文件、网络或非白名单依赖")
end
local function fixture()
    local f = { memory = { currency = { gems = 1000000, gold = 4321 },
        market = { shopConfigVersion = 8, purchased = {} } }, reads = 0, dirty = 0, flushes = 0 } ---@type any
    local env = {} ---@type any
    for _, key in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "select", "tonumber",
        "tostring", "type", "setmetatable", "getmetatable", "rawget", "rawset" }) do env[key] = _G[key] end
    env.math, env.string, env.table, env.utf8 = copy(math), copy(string), copy(table), copy(utf8)
    env._G, env.print, env.os = env, function() end, { time = function() return 1800000000 end }
    env.File, env.loadfile, env.dofile, env.GetFileSystem = denied, denied, denied, denied
    for _, name in ipairs({ "cache", "fileSystem", "network", "clientCloud", "serverCloud", "io", "package", "engine" }) do
        env[name] = setmetatable({}, { __index = function() return denied end })
    end
    local modules = {
        ["rules.character.PlayerDataManager"] = {
            GetModule = function(uid, key)
                assert(uid == 42, "仅允许内存玩家42")
                f.reads = f.reads + 1
                return f.memory[key]
            end,
            MarkDirty = function(uid) assert(uid == 42); f.dirty = f.dirty + 1 end,
            FlushImmediate = function(uid) assert(uid == 42); f.flushes = f.flushes + 1 end,
        },
    }
    env.require = function(name)
        if modules[name] ~= nil then return modules[name] end
        if not ALLOWED[name] or name == "ui.market.MarketPage" then return denied() end
        local result = assert(load(source(name), "@market-gold/" .. name, "t", env))()
        modules[name] = assert(result, "模块返回nil " .. name)
        return result
    end
    f.env, f.service = env, env.require("rules.market.MarketService")
    return f
end

local EXPECTED = {
    { 12, "远征招募券", 180, 1, "adventure_ticket", "recruitTicket" },
    { 13, "洗练石", 90, 2, "enhance_star", "enhanceStone" },
    { 14, "点金石", 250, 1, "break_protect", "destroyStone" },
    { 22, "腐化石", 250, 1, "corrupt_stone", "corruptStone" },
    { 15, "奥术粉尘", 90, 300, "arcane_dust", "arcaneDust" },
    { 17, "精粹", 94, 600, "essence", "essence" },
    { 20, "黄金钥匙", 150, 1, "golden_key", "goldenKey" },
}
local function runTests()
    local f = fixture()
    local page = source("ui.market.MarketPage")
    local config = assert(page:match("local SHOP_ITEMS = (%b{})"), "缺少界面商品配置")
    local items = assert(load("local ArtifactDefs = require('shared.artifact.ArtifactDefs')\nreturn " .. config,
        "@market-gold/ui-config", "t", f.env))()
    eq(#items, 7, "界面仅保留7项商品")
    eq(tonumber(page:match("local SHOP_CONFIG_VERSION = (%d+)")), 8, "界面不升级配置版本")
    local seen = {}
    for index, expected in ipairs(EXPECTED) do
        local item = assert(items[index], "缺少界面商品")
        eq(item.id, expected[1], "展示顺序保留稳定ID")
        eq(item.name, expected[2], "商品名称不变")
        eq(item.price, expected[3], "商品单价不变")
        eq(item.rewardCount, expected[4], "单次奖励不变")
        eq(item.currency, "diamond", "支付货币不变")
        check(item.id ~= 16 and item.name ~= "金币", "列表无金币商品")
        check(not seen[item.id], "商品ID不重复")
        seen[item.id] = true
    end

    for _, quantity in ipairs({ 1, 7, 99 }) do
        local old = fixture()
        old.memory.market.purchased[16] = { count = 123, firstBuyTime = 456 }
        local before = copy(old.memory)
        local ok, reason, result = old.service.Buy(42, 16, quantity)
        eq(ok, false, "旧金币商品拒绝购买")
        eq(reason, "商品不存在", "返回明确的下架原因")
        eq(result, nil, "下架请求无奖励回执")
        check(same(before, old.memory), "金币/黑晶/购买记录均不变")
        eq(old.reads, 0, "下架请求不读取玩家模块")
        eq(old.dirty, 0, "下架请求不标脏")
        eq(old.flushes, 0, "下架请求不落盘")
        local protocol = old.env.require("shared.Protocol")
        local handlers = old.env.require("rules.market.MarketHandler")
        local receipt = handlers[protocol.ACTION_TYPES.MARKET_BUY](42, { itemId = "16", quantity = tostring(quantity) })
        eq(receipt.success, false, "旧字符串ID请求拒绝")
        eq(receipt.reason, "商品不存在", "Handler返回下架原因")
        check(same(before, old.memory), "Handler不改变内存数据")
        eq(old.reads + old.dirty + old.flushes, 0, "Handler无数据读写")
    end

    for _, expected in ipairs(EXPECTED) do
        for _, quantity in ipairs({ 1, 7, 99 }) do
            local current = fixture()
            local ok, reason, result = current.service.Buy(42, expected[1], quantity)
            check(ok and reason == nil and result ~= nil, "其他商品单次/批量购买成功")
            if result then
                eq(result.itemId, expected[1], "回执ID不变")
                eq(result.rewardType, expected[5], "奖励类型不变")
                eq(result.rewardName, expected[2], "奖励名称不变")
                eq(result.rewardCount, expected[4] * quantity, "批量奖励数量准确")
                eq(current.memory.currency[expected[6]], expected[4] * quantity, "真实货币服务到账准确")
                eq(current.memory.market.purchased[expected[1]].count, quantity, "记录使用稳定商品ID")
            end
            eq(current.memory.currency.gems, 1000000 - expected[3] * quantity, "真实货币服务扣黑晶准确")
            eq(current.memory.currency.gold, 4321, "其他商品不影响金币")
            eq(current.flushes, 1, "成功购买保留立即刷盘接线")
        end
        local poor = fixture()
        poor.memory.currency.gems = expected[3] - 1
        local before = copy(poor.memory)
        local ok, reason = poor.service.Buy(42, expected[1], 1)
        eq(ok, false, "其他商品余额不足仍拒绝")
        eq(reason, "余额不足", "余额不足原因不变")
        check(same(before, poor.memory), "余额不足不扣费不发奖")
        eq(poor.dirty + poor.flushes, 0, "余额不足无写入")
    end

    local cleanup = fixture()
    cleanup.memory.market.purchased[16] = { count = 123, firstBuyTime = 456 }
    for _, expected in ipairs(EXPECTED) do
        cleanup.memory.market.purchased[expected[1]] = { count = 17, firstBuyTime = 200 }
    end
    local before = copy(cleanup.memory)
    cleanup.service.ResetDailyShopItems(42)
    eq(cleanup.memory.market.purchased[16], nil, "下架商品旧记录自然清理")
    eq(cleanup.memory.market.shopConfigVersion, 8, "不升级版本或全量迁移")
    for _, expected in ipairs(EXPECTED) do
        check(same(cleanup.memory.market.purchased[expected[1]], before.market.purchased[expected[1]]), "保留其他商品购买记录")
    end
    check(same(cleanup.memory.currency, before.currency), "记录清理不改变钱包")
    eq(cleanup.dirty, 1, "仅记录清理标脏一次")
    eq(cleanup.flushes, 0, "登录清理不额外立即刷盘")
    cleanup.service.ResetDailyShopItems(42)
    eq(cleanup.dirty, 1, "重复清理幂等")
    eq(forbidden, 0, "无文件/网络/非白名单访问")
end

function Start()
    local ok, err = pcall(runTests)
    if not ok then failures = failures + 1; print(TAG .. "ERROR " .. tostring(err)) end
    print(string.format("%sassertions=%d failures=%d %s", TAG, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
