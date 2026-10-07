-- 单机扫荡/副本提交发布专项：只抽取真实桥接注册片段，在私有环境保存并执行hooks。
-- 不启动Boot、不修改业务/全局require/package、不读写玩家存档；通知/Flush均为边界替身。
local TAG = "[sweep_bridge_publish_test] "
local assertions, cases, passed = 0, 0, 0
local failures = {} ---@type string[]

local function check(value, message)
    assertions = assertions + 1
    assert(value, message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function run(label, callback)
    cases = cases + 1
    local ok, err = pcall(callback)
    if ok then passed = passed + 1; print(TAG .. "PASS " .. label)
    else failures[#failures + 1] = label .. " => " .. tostring(err); print(TAG .. "FAIL " .. failures[#failures]) end
end
local function source(path)
    local file = assert(cache:GetFile(path), "缺少真实源码 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function newBridge(fragment, fault, mutate)
    local h = { sets = {}, events = {}, logs = {}, flushes = 0, flushResult = true,
        playerSyncs = 0, currencySyncs = 0, fault = fault or "", mutate = mutate == true }
    h.pushes = { heroes = { roster = { [1] = { exp = 71 } } },
        player = { level = 12, exp = 43, name = "candidate", extra = { retained = true } },
        currency = { gold = 81, sweepTicket = 4 }, equipment = { inventory = {} }, lootbox = { seeds = {} } }
    local originalPlayer = h.pushes.player
    local access = {} ---@type table
    local function lockObserved(label)
        eq(access.locked(), true, label .. "发布期间拒绝重入锁开启")
        eq(access.pending(), nil, label .. "候选推送队列先清空")
    end
    local dispatcher = { set = function(name, data, opts)
        lockObserved("set:" .. name)
        h.sets[name] = (h.sets[name] or 0) + 1
        h.events[#h.events + 1] = "set:" .. name
        eq(data, h.pushes[name], "Dispatcher发布原模块引用 " .. name)
        eq(opts.normalized, true, "Dispatcher只发布已规范化数据 " .. name)
        if h.mutate and name == "heroes" then originalPlayer.exp, originalPlayer.level = 999, 99 end
        if h.fault == "set:" .. name then error("expected " .. h.fault) end
    end }
    local gameState = {
        syncPlayerData = function(data)
            lockObserved("GS:player")
            h.playerSyncs = h.playerSyncs + 1
            h.events[#h.events + 1] = "GS:player"
            eq(h.sets.heroes, 1, "GS玩家同步在队员发布后")
            eq(h.sets.player, 1, "GS玩家同步在player模块发布后")
            check(data ~= originalPlayer, "GS使用独立冻结玩家表，不使用共享候选表")
            eq(data.exp, 43, "GS使用发布前冻结经验")
            eq(data.level, 12, "GS使用发布前冻结等级")
            eq(data.extra, originalPlayer.extra, "玩家冻结保留既有浅拷贝字段契约")
            h.syncedPlayer = data
            if h.fault == "GS:player" then error("expected " .. h.fault) end
        end,
        syncFromCurrency = function(data)
            lockObserved("GS:currency")
            h.currencySyncs = h.currencySyncs + 1
            h.events[#h.events + 1] = "GS:currency"
            eq(h.sets.currency, 1, "GS货币同步在currency模块发布后")
            eq(data, h.pushes.currency, "GS使用原已提交货币引用")
            if h.fault == "GS:currency" then error("expected " .. h.fault) end
        end,
    }
    local env = { pairs = pairs, pcall = pcall, tostring = tostring,
        ClientDispatcher = dispatcher, GameState = gameState,
        PDM = { GetModule = function(uid, name)
            eq(uid, 17, "保存透传uid")
            eq(name, "player", "保存候选player而非旧GameState")
            return originalPlayer
        end },
        print = function(message) h.logs[#h.logs + 1] = message end,
    }
    env.require = function(name)
        if name == "rules.dungeon.DungeonService" then
            return { SetPersistCallback = function(callback, hooks) h.persist, h.hooks = callback, hooks end }
        elseif name == "boot.StandaloneSave" then
            return { Flush = function(player)
                h.flushes = h.flushes + 1
                eq(player, originalPlayer, "Flush接到PDM当前候选player")
                eq(access.locked(), false, "保存不提前开启发布锁")
                eq(#h.events, 0, "保存之前不发布奖励")
                return h.flushResult
            end }
        end
        error("私有桥片段禁止加载额外依赖 " .. tostring(name))
    end
    local wrapper = "local deferredTaskPushes_ = nil\nlocal publishingDungeonRewards_ = false\n"
        .. fragment .. "\nreturn { locked = function() return publishingDungeonRewards_ end,"
        .. " pending = function() return deferredTaskPushes_ end,"
        .. " queue = function(pushes) deferredTaskPushes_ = pushes end }"
    access = assert(load(wrapper, "@sweep-bridge/real-registration", "t", env))()
    h.access = access
    check(type(h.persist) == "function", "保存真实注册的persist回调")
    check(type(h.hooks.begin) == "function" and type(h.hooks.finish) == "function", "保存真实begin/finish钩子")
    return h
end

local function verifyPublished(h)
    local ok, err = pcall(h.hooks.finish, 17, true)
    check(ok, "单个订阅/GS异常被真实finish隔离 " .. tostring(err))
    eq(h.access.locked(), false, "正常/异常返回后发布锁清除")
    eq(h.access.pending(), nil, "返回后候选队列不残留")
    for _, name in ipairs({ "heroes", "player", "currency", "equipment", "lootbox" }) do
        eq(h.sets[name], 1, "每个已提交模块仅发布一次 " .. name)
    end
    eq(h.playerSyncs, 1, "玩家GS同步仅一次")
    eq(h.currencySyncs, 1, "货币GS同步仅一次")
    eq(h.events[1], "set:heroes", "先发布队员")
    eq(h.events[2], "set:player", "随后发布player")
    eq(h.events[3], "GS:player", "然后同步冻结player到GS")
    eq(#h.events, 7, "没有额外裸发布/重复同步")
    eq(#h.logs, h.fault == "" and 0 or 1, "故障只记录一次，成功不打故障日志")
    if h.fault ~= "" then check(h.logs[1]:find("expected " .. h.fault, 1, true), "故障日志保留原因") end
    local previous = #h.events
    h.hooks.finish(17, true)
    eq(#h.events, previous, "重复finish不重复发布已消费队列")
    eq(h.access.locked(), false, "重复finish也不锁死")
end

local function testReceipts()
    -- 只执行真实回执展示尾段，奖励弹窗/NumberUtil/副本身份为私有边界替身。
    local text = source("runtime/ClientMessageHandler.lua")
    local first = assert(text:find("     -- 主线与资源扫荡回执统一展示", 1, true), "缺少真实扫荡展示尾段")
    local last = assert(text:find("\n end\n", first, true), "缺少真实ActionResult尾段边界")
    local fragment = text:sub(first, last - 1)
    local function receipt(action, id, perHero, total)
        local popup, closed, logs = {}, 0, 0
        local equipment = { seq = 75, templateId = "W1", quality = 4, level = 11, slot = "weapon",
            equip = { seq = 75, affixes = { { key = "hp", value = 2 } } }, destination = "lootbox", custom = "retain" }
        local data = { action = action, dungeonId = id, success = true, gold = 5, diamond = 17,
            playerExp = 123, heroExp = perHero, heroExpTotal = total, teamIdx = 2,
            equips = { equipment }, scrollDrops = { weaponScroll = 3 } }
        local env = { data = data, pairs = pairs, ipairs = ipairs, tostring = tostring, table = table,
            Protocol = { ACTION_TYPES = { SWEEP = "sweep", DUNGEON_SWEEP = "dungeon_sweep" } },
            RewardPopup = { show = function(title, rewards, opts) popup.title, popup.rewards, popup.opts = title, rewards, opts end },
            print = function() logs = logs + 1 end,
        }
        env.require = function(name)
            if name == "config.DungeonConfig" then return { isResourceDungeon = function(dungeonId) return dungeonId == "black_diamond" end } end
            if name == "ui.battle.stage.SweepDialog" then return { isOpen = function() return true end, close = function() closed = closed + 1 end } end
            if name == "core.NumberUtil" then return { format = function(value) return tostring(value) end } end
            error("回执私有环境禁止依赖 " .. tostring(name))
        end
        assert(load(fragment, "@sweep-bridge/real-receipt", "t", env))()
        if action == "dungeon_sweep" and id == "ancient_ruin" then
            eq(popup.title, nil, "古遗迹不进入新扫荡弹窗路径")
            eq(closed, 0, "旧遗迹不关闭无关扫荡窗")
            return
        end
        eq(popup.title, "扫荡奖励", "两资源协议使用统一奖励标题")
        eq(closed, 1, "奖励前只关闭一次扫荡窗")
        eq(logs, 1, "记录一次自动关闭")
        eq(#popup.rewards, 4, "金币/黑晶/完整装备/卷轴四项")
        eq(popup.rewards[2].type, "diamond", "黑晶用现有diamond资源类型")
        eq(popup.rewards[2].amount, 17, "黑晶金额透传")
        local reward = popup.rewards[3]
        eq(reward.equip, equipment.equip, "完整装备实例不被重造")
        eq(reward.destination, "lootbox", "遗匣目的地保留")
        eq(reward.seq, 75, "装备附加序号保留")
        eq(reward.custom, "retain", "装备未知附加字段保留")
        check(reward ~= equipment, "展示拷贝不写回原回执项")
        check(popup.opts.subtitle:find("远征经验 +123", 1, true), "subtitle展示远征经验")
        if perHero then
            check(popup.opts.subtitle:find("队2每名队员经验 +" .. perHero, 1, true), "权威每人经验带目标队")
            check(not popup.opts.subtitle:find("合计", 1, true), "有每人值不重复合计/按当前编队反推")
        else
            check(popup.opts.subtitle:find("队员经验合计 +" .. total, 1, true), "旧回执仅展示权威合计")
        end
    end
    receipt("sweep", nil, 61, 122)
    receipt("dungeon_sweep", "black_diamond", 61, 122)
    receipt("sweep", nil, nil, 122)
    receipt("dungeon_sweep", "ancient_ruin", 61, 122)
end

function Start()
    local ok, err = pcall(function()
        local text = source("runtime/LocalActionBridge.lua")
        local first = assert(text:find('    require("rules.dungeon.DungeonService").SetPersistCallback', 1, true), "缺少真实DungeonService注册")
        local last = assert(text:find('\n    print("[LocalActionBridge] init uid=', first, true), "缺少真实注册尾边界")
        local fragment = text:sub(first, last - 1)
        for _, fault in ipairs({ "", "set:heroes", "set:player", "set:currency", "set:equipment", "set:lootbox", "GS:player", "GS:currency" }) do
            run("发布不锁死 " .. (fault == "" and "normal" or fault), function()
                local h = newBridge(fragment, fault, true)
                h.hooks.begin(17)
                check(type(h.access.pending()) == "table", "begin建立私有延迟队列")
                eq(h.access.locked(), false, "begin不提前锁发布")
                h.access.queue(h.pushes)
                verifyPublished(h)
            end)
        end
        for _, outcome in ipairs({ "false", "nil" }) do
            run("失败事务不发布 " .. outcome, function()
                local h = newBridge(fragment)
                h.hooks.begin(17)
                h.access.queue(h.pushes)
                if outcome == "false" then h.hooks.finish(17, false)
                else h.hooks.finish(17, nil) end
                eq(#h.events, 0, "失败不发模块/GS通知")
                eq(next(h.sets), nil, "失败不调用Dispatcher.set")
                eq(h.access.pending(), nil, "失败丢弃候选推送")
                eq(h.access.locked(), false, "失败不锁死")
                h.hooks.begin(17)
                h.access.queue(h.pushes)
                verifyPublished(h)
            end)
        end
        run("保存候选player且透传Flush布尔结果", function()
            local h = newBridge(fragment)
            eq(h.persist(17), true, "Flush成功true")
            h.flushResult = false
            eq(h.persist(17), false, "Flush失败false")
            eq(h.flushes, 2, "每次persist只调用一次Flush")
            eq(#h.events, 0, "persist仅保存不发布")
        end)
        run("空候选成功finish清锁", function()
            local h = newBridge(fragment)
            h.hooks.finish(17, true)
            eq(#h.events, 0, "空候选不发布")
            eq(h.access.locked(), false, "空候选清锁")
        end)
        run("真实黑晶/经验subtitle/完整装备去向回执", testReceipts)
    end)
    if not ok then failures[#failures + 1] = "harness => " .. tostring(err) end
    print(TAG .. "SUMMARY cases=" .. cases .. " passed=" .. passed .. " failures=" .. #failures .. " assertions=" .. assertions)
    if #failures > 0 then log:Write(LOG_ERROR, TAG .. table.concat(failures, "\n"))
    else print(TAG .. "ALL PASS") end
    engine:Exit()
end
