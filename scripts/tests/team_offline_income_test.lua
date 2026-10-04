-- T11/T12 专项：真实收益/双锚点/升级 + 内存 PDM 的预览和领取链路。
-- Runtime: timeout 60s .cli/UrhoXRuntime tests/team_offline_income_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 基于 team_stage_unlock_test/offline_boundary_test 的隔离方式，但不替换 OfflineCalc、
-- StageProvider、StageConfig、StageUtils、ExpTable、IdleIncomeConfig 或经验升级函数。
-- 仅隔离 PDM、CharacterPanel 实时入口、HeroService 养成联动、装备入库副作用和时钟。
-- 已选规则：0人仍计算1倍池但无收件人；1~5不变；6~12钳制3倍英雄池；
-- 账户收益只看共享max和严格true首通；缺账本保守回退。终焉income用同难度末关，
-- drop接口仍返回max，实际排除式混合应从同难度末关起取五关（不全局修改StageUtils）。
-- 不启动真正战斗/首通奖励发放；Scene集成只验证真实setBattleData/recalc缓存显示。

local TAG = "[team_offline_income_test]"
local assertions, failures, cases, failedCases, harnessErrors = 0, 0, 0, 0, 0
---@type table<string, { assertions: number, failures: number, cases: number, failedCases: number }>
local groups = {}
local activeGroup = "setup"
---@type fun()[]
local restores = {}

local function check(condition, label, actual, expected)
    assertions = assertions + 1
    local g = groups[activeGroup]
    if g then g.assertions = g.assertions + 1 end
    if not condition then
        failures = failures + 1
        if g then g.failures = g.failures + 1 end
        print(TAG .. " ASSERT " .. activeGroup .. " " .. label
            .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
end
local function eq(actual, expected, label)
    check(actual == expected, label, actual, expected)
end
local function runCase(group, label, fn)
    activeGroup = group
    groups[group] = groups[group] or { assertions = 0, failures = 0, cases = 0, failedCases = 0 }
    local g = groups[group]
    cases = cases + 1
    g.cases = g.cases + 1
    local before = failures
    local ok, err = pcall(fn)
    if not ok then
        harnessErrors = harnessErrors + 1
        check(false, label .. " exception", tostring(err), "no exception")
    end
    if failures > before then
        failedCases = failedCases + 1
        g.failedCases = g.failedCases + 1
    end
end
local function replace(owner, key, value)
    local old = owner[key]
    restores[#restores + 1] = function() owner[key] = old end
    owner[key] = value
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function stable(value)
    if type(value) ~= "table" then return tostring(value) end
    local parts = {}
    for key, item in pairs(value) do parts[#parts + 1] = tostring(key) .. "=" .. stable(item) end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end
local function expectedMult(count)
    if count == 0 then return 1 end
    if count <= 5 then return 1 + (count - 1) * 0.5 end
    return 3
end
local function seedSignature(seeds)
    local parts = {}
    for _, seed in ipairs(seeds or {}) do
        parts[#parts + 1] = string.format("%s/%s/%s/%s", seed.stageId, seed.quality, seed.level, seed.count)
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

function Start()
    local ok, err = pcall(function()
        local Calc = require("systems.OfflineCalc")
        local SC = require("config.StageConfig")
        local ET = require("config.ExpTable")
        local Income = require("config.IdleIncomeConfig")
        local SU = require("shared.StageUtils")
        local Provider = require("shared.StageProvider")
        local PDM = require("rules.character.PlayerDataManager")
        local HeroService = require("rules.hero.HeroService")
        local Equipment = require("systems.EquipmentSystem")
        local dispatcher = require("runtime.ClientDispatcher")
        ---@type table<string, any>
        local modules = {}
        local liveTeams = {}
        local liveReady = false
        local resonanceCalls, syncCalls, dirty = 0, 0, 0
        local now = 200000
        local uidCounter = 78000
        replace(os, "time", function() return now end)
        replace(PDM, "GetModule", function(_, name) return modules[name] end)
        replace(PDM, "MarkDirty", function() dirty = dirty + 1 end)
        replace(PDM, "FlushImmediate", function() end)
        replace(dispatcher, "get", function(name) return modules[name] end)
        replace(HeroService, "ApplyResonanceSync", function() resonanceCalls = resonanceCalls + 1 end)
        replace(HeroService, "SyncHeroLevelsToPlayerLevel", function() syncCalls = syncCalls + 1 end)
        replace(Equipment, "isInventoryFull", function() return false end)
        replace(Equipment, "addToInventory", function(data, equip)
            data.inventory[#data.inventory + 1] = equip
            return equip
        end)
        replace(package.loaded, "ui.character.panel.CharacterPanel", {
            getTeamSlotIds = function() return liveTeams end,
            isHeroesDataApplied = function() return liveReady end,
            getOwnedHero = function() return nil end,
        })
        local Service = require("rules.offline.OfflineService")

        runCase("fixture", "真实配置身份", function()
            eq(Provider.Get(), SC, "StageProvider保留真实配置")
            eq(ET.heroCountExpMult[5], 3, "既有最大档固定3倍")
            eq(ET.getHeroExpForLevel(1), 20, "真实英雄升级表")
            eq(ET.getPlayerExpForLevel(1), 100, "真实账户升级表")
        end)
        for count = 0, 12 do
            runCase("multiplier", "人数" .. count, function()
                eq(ET.getHeroCountExpMult(count), expectedMult(count), "getter人数=" .. count)
            end)
        end
        for _, sid in ipairs({ 101, 905, 2305 }) do
            math.randomseed(1104)
            local base = Calc.calcRewardsFromKills(100, SC.getStage(sid) --[[@as StageEntry]], 1, SC)
            for count = 0, 12 do
                runCase("kills", sid .. "/" .. count, function()
                    math.randomseed(1104)
                    local r = Calc.calcRewardsFromKills(100, SC.getStage(sid) --[[@as StageEntry]], count, SC)
                    check(base.adventureExp > 0, "真实怪物基数非零", base.adventureExp, ">0")
                    eq(r.gold, base.gold, "杀怪金币人数独立 " .. sid .. "/" .. count)
                    eq(r.adventureExp, base.adventureExp, "杀怪远征经验人数独立 " .. sid .. "/" .. count)
                    eq(r.adventurerExp, math.floor(base.adventureExp * expectedMult(count)),
                        "杀怪英雄池 " .. sid .. "/" .. count)
                    eq(seedSignature(r.equipSeeds), seedSignature(base.equipSeeds), "杀怪装备人数独立")
                    eq(stable(r.scrollDrops), stable(base.scrollDrops), "杀怪卷轴人数独立")
                end)
            end
            runCase("kills", sid .. "五到六", function()
                local five = Calc.calcRewardsFromKills(100, SC.getStage(sid) --[[@as StageEntry]], 5, SC)
                local six = Calc.calcRewardsFromKills(100, SC.getStage(sid) --[[@as StageEntry]], 6, SC)
                check(six.adventurerExp >= five.adventurerExp, "5→6英雄池不降 " .. sid,
                    six.adventurerExp, five.adventurerExp)
            end)
        end
        for _, offline in ipairs({ false, true }) do
            local group = offline and "offline_core" or "online_core"
            for _, seconds in ipairs({ 60, 121 }) do
                for _, sid in ipairs({ 101, 2001, 2305 }) do
                    local goldPerMin, expPerMin = Income.get(sid)
                    local gold = math.floor(goldPerMin * seconds / 60 + 0.5)
                    local exp = math.floor(expPerMin * seconds / 60 + 0.5)
                    for count = 0, 12 do
                        runCase(group, sid .. "/" .. seconds .. "/" .. count, function()
                            math.randomseed(1104)
                            local fn = offline and Calc.calcOfflineIdleRewards or Calc.calcOnlineIdleRewards
                            local r = fn(seconds, sid, count, sid, SC)
                            check(type(r) == "table", "真实入口返回收益", type(r), "table")
                            if not r then return end
                            eq(r.gold, gold, "查表金币人数独立 " .. sid .. "/" .. count)
                            eq(r.adventureExp, exp, "查表远征经验人数独立 " .. sid .. "/" .. count)
                            eq(r.adventurerExp, math.floor(exp * expectedMult(count) + 0.5),
                                "查表英雄池 " .. sid .. "/" .. count)
                            eq(r.kills, math.floor(seconds / 3), "真实击杀效率")
                        end)
                    end
                    runCase(group, sid .. "/" .. seconds .. "五到六", function()
                        local fn = offline and Calc.calcOfflineIdleRewards or Calc.calcOnlineIdleRewards
                        local five = fn(seconds, sid, 5, sid, SC)
                        local six = fn(seconds, sid, 6, sid, SC)
                        check(six.adventurerExp >= five.adventurerExp, "5→6池不降", six.adventurerExp, five.adventurerExp)
                    end)
                end
            end
        end

        -- 延长离线仍只用一份账户池；24小时软顶及7日硬顶不因12人改变。
        for _, seconds in ipairs({ 86400, 86460, 604800, 604860 }) do
            runCase("time_caps", "12人时长=" .. seconds, function()
                math.randomseed(1004)
                local base = Calc.calcOfflineIdleRewards(seconds, 2001, 1, 2001, SC)
                math.randomseed(1004)
                local twelve = Calc.calcOfflineIdleRewards(seconds, 2001, 12, 2001, SC)
                local capped = math.min(seconds, 604800)
                local effective = math.min(capped, 86400) + math.max(0, capped - 86400) * 0.5
                local gpm, epm = Income.get(2001)
                eq(twelve.seconds, capped, "12人仍7日硬顶")
                eq(twelve.effectiveSeconds, effective, "12人仍24小时后半额")
                eq(twelve.gold, math.floor(gpm * effective / 60 + 0.5), "折算账户金币一份")
                eq(twelve.adventureExp, math.floor(epm * effective / 60 + 0.5), "折算远征经验一份")
                eq(twelve.adventurerExp, twelve.adventureExp * 3, "长离线英雄池最多3倍")
                eq(twelve.kills, math.floor(capped / 3), "掉落只吃封顶时长")
                eq(twelve.gold, base.gold, "长期金币与人数无关")
                eq(twelve.adventureExp, base.adventureExp, "长期远征经验与人数无关")
                eq(seedSignature(twelve.equipSeeds), seedSignature(base.equipSeeds), "长期装备不按队倍增")
                eq(stable(twelve.scrollDrops), stable(base.scrollDrops), "长期卷轴不按队倍增")
            end)
        end

        -- 独立断言预期锚点，不用目标resolver生成oracle；掉落reference仍走真实计算。
        local function anchorCase(label, battle, incomeId, dropId)
            runCase("anchors", label, function()
                local before = stable(battle)
                local income, drop = Calc.resolveIdleStageAnchors(battle, SC)
                eq(income, incomeId, label .. " income")
                eq(drop, dropId, label .. " drop")
                eq(Calc.resolveIdleIncomeStageId(battle, SC), incomeId, label .. " directIncome")
                eq(Calc.resolveIdleDropStageId(battle, SC), dropId, label .. " directDrop")
                local dropBoundary = SC.isTerminalTemple(dropId)
                    and SC.getReincarnationTarget(SC.getDifficulty(dropId)) or dropId
                local seconds = SC.isTerminalTemple(dropId) and 1200 or 60
                local goldPerMin, expPerMin = Income.get(incomeId)
                for _, offline in ipairs({ false, true }) do
                    math.randomseed(1212)
                    local fn = offline and Calc.calcOfflineIdleRewards or Calc.calcOnlineIdleRewards
                    local reference = fn(seconds, incomeId, 5, dropBoundary, SC)
                    math.randomseed(1212)
                    local r = Calc.calcIdleRewardsForBattle(seconds, battle, 5, offline, SC)
                    local path = label .. (offline and " offline" or " online")
                    check(type(r) == "table", path .. "实际入口", type(r), "table")
                    if r then
                        eq(r.gold, math.floor(goldPerMin * seconds / 60 + 0.5), path .. "账户金币")
                        eq(r.adventureExp, math.floor(expPerMin * seconds / 60 + 0.5), path .. "账户远征经验")
                        eq(r.adventurerExp, reference.adventurerExp, path .. "英雄池不受旧关影响")
                        eq(seedSignature(r.equipSeeds), seedSignature(reference.equipSeeds), path .. "实际掉落前五关")
                        eq(stable(r.scrollDrops), stable(reference.scrollDrops), path .. "实际卷轴")
                        eq(r.kills, reference.kills, path .. "击杀数")
                        if SC.isTerminalTemple(dropId) then
                            local lastId = SC.getTerminalPrevStageId(dropId)
                            assert(lastId, "终焉必须配置同难度末关")
                            check(#r.equipSeeds > 0, path .. "终焉混合实际生成装备", #r.equipSeeds, ">0")
                            for _, seed in ipairs(r.equipSeeds) do
                                check(seed.stageId <= lastId and seed.stageId >= lastId - 4,
                                    path .. "只掉同难度末章五关", seed.stageId, lastId - 4 .. "~" .. lastId)
                            end
                        end
                    end
                end
                eq(stable(battle), before, label .. "解析不得改共享账本")
            end)
        end
        local ledgerKinds = {
            { name = "numTrue", ledger = { [2001] = true }, clear = true },
            { name = "strTrue", ledger = { ["2001"] = true }, clear = true },
            { name = "bothTrue", ledger = { [2001] = true, ["2001"] = true }, clear = true },
            { name = "numFalseStrTrue", ledger = { [2001] = false, ["2001"] = true }, clear = true },
            { name = "numTrueStrFalse", ledger = { [2001] = true, ["2001"] = false }, clear = true },
            { name = "bothFalse", ledger = { [2001] = false, ["2001"] = false }, clear = false },
            { name = "numFalse", ledger = { [2001] = false }, clear = false },
            { name = "numericTruthy", ledger = { [2001] = 1 }, clear = false },
            { name = "stringTruthy", ledger = { ["2001"] = "true" }, clear = false },
            { name = "falseString", ledger = { ["2001"] = "false" }, clear = false },
            { name = "empty", ledger = {}, clear = false },
            { name = "missing", clear = false },
        }
        for _, kind in ipairs(ledgerKinds) do
            for _, current in ipairs({ 1001, 2001, 2101 }) do
                for _, mode in ipairs({ "firstClear", "idle", "offline" }) do
                    anchorCase(kind.name .. "/" .. current .. "/" .. mode,
                        { currentStageId = current, maxStageId = "2001", clearedStages = copy(kind.ledger), battleMode = mode },
                        kind.clear and 2001 or 1905, 2001)
                end
            end
        end
        for _, sid in ipairs({ 101, 2305, 2401, 4701 }) do
            local previous = SC.getPrevStageId(sid) or SC.getLastStageOfPrevDifficulty(sid) or sid
            for _, mode in ipairs({ "firstClear", "idle", "offline" }) do
                anchorCase("boundaryUncleared/" .. sid .. "/" .. mode,
                    { maxStageId = sid, currentStageId = 101, clearedStages = {}, battleMode = mode }, previous, sid)
                anchorCase("boundaryCleared/" .. sid .. "/" .. mode,
                    { maxStageId = sid, currentStageId = sid, clearedStages = { [sid] = true }, battleMode = mode }, sid, sid)
            end
        end
        for _, entry in ipairs(SC.STAGES) do
            if SC.isTerminalTemple(entry.id) then
                local sid = entry.id
                for _, cleared in ipairs({ false, true }) do
                    anchorCase("terminal/" .. sid .. "/" .. tostring(cleared),
                        { maxStageId = sid, currentStageId = sid, clearedStages = { [tostring(sid)] = cleared }, battleMode = "offline" },
                        SC.getTerminalPrevStageId(sid), sid)
                end
            end
        end
        anchorCase("nilBattle", nil, 101, 101)
        anchorCase("maxMissingEmpty", {}, 101, 101)
        anchorCase("maxMissingCurrentUncleared", { currentStageId = "1001", battleMode = "offline" }, 905, 1001)
        anchorCase("maxMissingCurrentCleared", { currentStageId = 1001, clearedStages = { [1001] = true }, battleMode = "firstClear" }, 1001, 1001)
        runCase("drop_boundary", "跨难度前五关真实工具", function()
            local prev = SU.collectPrevStages(2401, 5, SC)
            eq(#prev, 5, "困难首关取普通前五")
            eq(prev[1].id, 2305, "困难首关前关不是数字2400")
            eq(prev[5].id, 2301, "困难首关前五下界")
            local initial = SU.collectPrevStages(101, 5, SC)
            eq(#initial, 0, "开局无前关供core本关fallback")
        end)

        local function teamsForCount(count)
            local teams = { { slots = { 0, 0, 0, 0 } }, { slots = { 0, 0, 0, 0 } }, { slots = { 0, 0, 0, 0 } } }
            for id = 1, count do
                local team = math.floor((id - 1) / 4) + 1
                local slot = (id - 1) % 4 + 1
                teams[team].slots[slot] = id
            end
            return teams
        end
        local function reset(battle, teams, live)
            uidCounter = uidCounter + 1
            local uid = uidCounter
            Service.Cleanup(uid)
            restores[#restores + 1] = function() Service.Cleanup(uid) end
            local roster = {}
            for id = 1, 13 do roster[id] = { level = 1, exp = 3 + id % 2 } end
            modules = {
                battle = copy(battle), heroes = { roster = roster, teams = copy(teams), deployed = copy(teams[1].slots) },
                session = { lastOnlineTime = now - 600, firstLoginTime = 1000 },
                player = { level = 1, exp = 7 }, currency = { gold = 40 }, equipment = { inventory = {} }, lootbox = {},
            }
            liveTeams = live and copy(teams) or {}
            liveReady = live == true
            resonanceCalls, syncCalls, dirty = 0, 0, 0
            return uid
        end
        local function goldInPanel(panel)
            local amount = 0
            for _, r in ipairs(panel.rewards or {}) do if r.type == "gold" then amount = amount + r.amount end end
            return amount
        end
        local function lifetimeExp(data, tableOfExp)
            local total = data.exp or 0
            for lv = 1, (data.level or 1) - 1 do total = total + (tableOfExp[lv] or 0) end
            return total
        end
        local function serviceCase(label, battle, teams, expectedIds, incomeId, snapshotCount, live)
            local report = {}
            runCase("service", label, function()
                local uid = reset(battle, teams, live)
                local recipientCount = #expectedIds
                local effectiveCount = snapshotCount > 0 and math.min(snapshotCount, recipientCount) or recipientCount
                local gpm, epm = Income.get(incomeId)
                local expectedGold, expectedExp = gpm * 10, epm * 10
                local expectedPool = math.floor(expectedExp * expectedMult(effectiveCount) + 0.5)
                local expectedPer = recipientCount > 0 and math.floor(expectedPool / recipientCount + 0.5) or 0
                local beforeHeroes = copy(modules.heroes.roster)
                math.randomseed(1012)
                local panel = Service.CalcOnEnter(uid)
                check(type(panel) == "table", label .. "CalcOnEnter", type(panel), "table")
                if not panel then return end
                report.gold, report.exp, report.pool = goldInPanel(panel), panel.adventureExp, panel.adventurerExp
                eq(goldInPanel(panel), expectedGold, label .. "金币预览")
                eq(panel.adventureExp, expectedExp, label .. "远征预览")
                eq(panel.adventurerExp, expectedPool, label .. "英雄池快照钳制")
                eq(panel.offlineSeconds, 600, label .. "真实离线区间")
                eq(Service.CalcOnEnter(uid), panel, label .. "重复进场沿用pending")
                eq(modules.currency.gold, 40, label .. "预览不提前发金币")
                eq(modules.player.level, 1, label .. "预览不升级账户")
                eq(modules.player.exp, 7, label .. "预览不发账户经验")
                eq(stable(modules.heroes.roster), stable(beforeHeroes), label .. "预览只读英雄")
                local preview = panel.heroExpPreview or {}
                eq(#preview, recipientCount, label .. "仅合法唯一收件人")
                local allowed = {}
                for _, id in ipairs(expectedIds) do allowed[id] = true end
                local seen = {}
                for _, item in ipairs(preview) do
                    check(allowed[item.heroId] and not seen[item.heroId], label .. "预览去重/锁队", item.heroId, "eligible unique")
                    seen[item.heroId] = true
                    eq(item.expGain, expectedPer, label .. "规则每人经验")
                    local prior = beforeHeroes[item.heroId]
                    local sim = ET.simulateHeroExp(prior.level, prior.exp, expectedPer)
                    eq(item.level, sim.level, label .. "真实模拟等级符合规则")
                    eq(item.exp, sim.exp, label .. "真实模拟经验符合规则")
                end
                for _, id in ipairs(expectedIds) do eq(seen[id], true, label .. "合法英雄不漏" .. id) end
                local rebuilt = Service.RebuildHeroPreview(uid)
                if recipientCount > 0 then
                    eq(stable(rebuilt), stable(preview), label .. "重建预览一致")
                else
                    eq(rebuilt, nil, label .. "0人重建不生成收件人")
                end
                local claimOk, claimErr, result = Service.ClaimRewards(uid)
                eq(claimOk, true, label .. "真实领取 " .. tostring(claimErr))
                if not result then check(false, label .. "领取结果", nil, "table"); return end
                eq(result.gold, expectedGold, label .. "规则实领金币")
                eq(result.playerExp, expectedExp, label .. "规则实领远征经验")
                eq(result.heroExp, expectedPer, label .. "规则实领每人英雄经验")
                eq(result.gold, goldInPanel(panel), label .. "预览/实领金币一致")
                eq(result.playerExp, panel.adventureExp, label .. "预览/实领远征一致")
                eq(modules.currency.gold, 40 + result.gold, label .. "实际金币入账一次")
                eq(lifetimeExp(modules.player, ET.player), 7 + result.playerExp, label .. "真实账户连续升级守恒")
                check(modules.player.level > 1, label .. "真实账户升级发生", modules.player.level, ">1")
                for _, item in ipairs(preview) do
                    local actual = modules.heroes.roster[item.heroId]
                    eq(result.heroExp, item.expGain, label .. "预览/实领每人一致")
                    eq(actual.level, item.level, label .. "实领等级与真实预览一致")
                    eq(actual.exp, item.exp, label .. "实领经验与真实预览一致")
                    eq(actual.maxExp, item.maxExp, label .. "实领升级阈值与预览一致")
                end
                local delivered = 0
                for id = 1, 13 do
                    local hero = modules.heroes.roster[id]
                    if allowed[id] then
                        local prior = beforeHeroes[id]
                        local gain = lifetimeExp(hero, ET.hero) - lifetimeExp(prior, ET.hero)
                        delivered = delivered + gain
                        eq(gain, expectedPer, label .. "规则实际英雄增量" .. id)
                        check(hero.level > 1, label .. "真实英雄连续升级" .. id, hero.level, ">1")
                    else
                        eq(stable(hero), stable(beforeHeroes[id]), label .. "未收件英雄不变" .. id)
                    end
                end
                eq(delivered, expectedPer * recipientCount, label .. "实际池分配含既有四舍五入")
                eq(resonanceCalls, recipientCount > 0 and 1 or 0, label .. "0人无养成联动")
                eq(syncCalls, 1, label .. "账户升级联动隔离但确实被调用")
                eq(Service.HasPendingRewards(uid), false, label .. "领取清pending")
                eq(modules.session.lastOnlineTime, now, label .. "领取推进边界")
                local after = stable(modules)
                eq(Service.ClaimRewards(uid), false, label .. "重复领取拒绝")
                eq(stable(modules), after, label .. "重复领取不再发金币或经验")
                Service.Cleanup(uid)
            end)
            return report
        end
        local function ids(count)
            local out = {}
            for id = 1, count do out[#out + 1] = id end
            return out
        end
        for _, count in ipairs({ 6, 8, 12 }) do
            for _, snapshot in ipairs({ 0, 5, 6, 12, 17 }) do
                serviceCase("n=" .. count .. "/hist=" .. snapshot,
                    { maxStageId = 2305, currentStageId = 2305, clearedStages = { ["2305"] = true },
                        battleMode = "offline", idleHeroCount = snapshot }, teamsForCount(count), ids(count), 2305, snapshot, false)
            end
        end
        serviceCase("0人有池无收件人", { maxStageId = 2305, currentStageId = 2305,
            clearedStages = { ["2305"] = true }, idleHeroCount = 12 }, teamsForCount(0), {}, 2305, 12, false)
        for _, live in ipairs({ false, true }) do
            serviceCase("锁队1/脏12/live=" .. tostring(live), { maxStageId = 905, currentStageId = 905,
                clearedStages = {}, idleHeroCount = 12 }, teamsForCount(12), ids(4), 904, 12, live)
            serviceCase("锁队3/脏12/live=" .. tostring(live), { maxStageId = 905, currentStageId = 905,
                clearedStages = { [905] = true }, idleHeroCount = 12 }, teamsForCount(12), ids(8), 905, 12, live)
        end
        local duplicateTeams = { { slots = { 1, "1", 2, 0 } }, { slots = { 2, 3, 4, 0 } }, { slots = { 4, 5, 6, 0 } } }
        serviceCase("跨队重复/空槽去重", { maxStageId = 2305, currentStageId = 2305,
            clearedStages = { ["2305"] = true }, idleHeroCount = 12 }, duplicateTeams, ids(6), 2305, 12, true)
        local variants = { { 2305, 1901, 101 }, { 2001, 1501, 1901 }, { 1001, 1601, 1801 } }
        for _, mode in ipairs({ "firstClear", "idle", "offline" }) do
            local baseline = {}
            for i, current in ipairs(variants) do
                local report = serviceCase("固定max三队选择/" .. mode .. "/" .. i,
                    { maxStageId = 2305, currentStageId = current[1], teamCurrentStageIds = copy(current),
                        clearedStages = { ["2305"] = true }, battleMode = mode, idleHeroCount = 12 },
                    teamsForCount(12), ids(12), 2305, 12, false)
                if i == 1 then baseline = report else
                    runCase("service_invariance", mode .. "/" .. i, function()
                        eq(report.gold, baseline.gold, "固定max切三队旧关金币不降")
                        eq(report.exp, baseline.exp, "固定max切三队旧关账户经验不降")
                        eq(report.pool, baseline.pool, "固定max切三队旧关英雄池不降")
                    end)
                end
            end
        end

        -- 不修改Scene计算或启动图形；读真实闭包并临时设置已有状态以跳过loadStage。
        runCase("scene_display", "真实恢复修模式后的账户显示", function()
            local Scene = require("ui.battle.scene.BattleScene")
            local function upvalue(fn, name)
                for i = 1, 100 do
                    local key, value = debug.getupvalue(fn, i)
                    if not key then break end
                    if key == name then return value, i end
                end
                error("missing upvalue " .. name)
            end
            local function setUpvalue(fn, name, value)
                local old, index = upvalue(fn, name)
                restores[#restores + 1] = function() debug.setupvalue(fn, index, old) end
                debug.setupvalue(fn, index, value)
            end
            local recalc = upvalue(Scene.refreshAllyStats, "recalcIdleIncome")
            local bind = upvalue(Scene.setBattleData, "bindBattleExtracts")
            setUpvalue(bind, "initialBattleDataLoaded", true)
            setUpvalue(bind, "battleActive", true)
            setUpvalue(Scene.setBattleData, "_dataRestore", nil)
            setUpvalue(recalc, "cachedGoldPerMin", 0)
            setUpvalue(recalc, "cachedExpPerMin", 0)
            -- 0名Scene allies：显示仍遵循旧1倍池，账户金币不可随队一模式变化。
            setUpvalue(recalc, "allies", {})
            local gpm, epm = Income.get(2001)
            local displayed = {}
            for _, current in ipairs({ 1001, 2001 }) do
                local data = { currentStageId = current, maxStageId = 2001,
                    clearedStages = { [2001] = true, ["2001"] = true }, battleMode = "offline" }
                modules.battle = data
                setUpvalue(recalc, "currentStageId", current)
                Scene.setBattleData(copy(data))
                -- 第二次调用确保覆盖setBattleData清除本地max首通标记后的正式计算。
                recalc()
                local gold = upvalue(recalc, "cachedGoldPerMin")
                local exp = upvalue(recalc, "cachedExpPerMin")
                eq(gold, gpm, "Scene已通max权威金币 current=" .. current)
                eq(exp, epm * 2, "Scene已通max权威显示经验 current=" .. current)
                eq(modules.battle.clearedStages[2001], true, "恢复修模式不删除权威数字首通")
                eq(modules.battle.clearedStages["2001"], true, "恢复修模式不删除权威字符串首通")
                displayed[#displayed + 1] = { gold = gold, exp = exp }
            end
            eq(displayed[2].gold, displayed[1].gold, "真实Scene current旧/等于max金币不降")
            eq(displayed[2].exp, displayed[1].exp, "真实Scene current旧/等于max经验不降")
            local sceneLedgers = {
                { name = "false", ledger = { [2001] = false } },
                { name = "number", ledger = { [2001] = 1 } },
                { name = "string", ledger = { ["2001"] = "false" } },
                { name = "empty", ledger = {} },
                { name = "missing" },
            }
            local priorGold, priorExp = Income.get(1905)
            for _, sample in ipairs(sceneLedgers) do
                for _, current in ipairs({ 1001, 2001 }) do
                    local data = { currentStageId = current, maxStageId = 2001,
                        clearedStages = copy(sample.ledger), battleMode = "firstClear" }
                    modules.battle = data
                    local savedBefore = stable(data)
                    setUpvalue(recalc, "currentStageId", current)
                    -- 覆盖缺账本回灌复用旧本地记录的路径；保存账本必须有最终解释权。
                    setUpvalue(recalc, "clearedStages", { [2001] = true })
                    Scene.setBattleData(copy(data))
                    recalc()
                    eq(upvalue(recalc, "cachedGoldPerMin"), priorGold,
                        "Scene无严格true凭据回前关 " .. sample.name .. "/" .. current)
                    eq(upvalue(recalc, "cachedExpPerMin"), priorExp * 2,
                        "Scene不借本地truthy升级账户收益 " .. sample.name .. "/" .. current)
                    eq(stable(modules.battle), savedBefore, "显示不写回账户首通记录")
                end
            end
            -- 执行生产Sync函数块，验证读档的宽松本地记录不会下一秒污染账户。
            local sourceFile = cache:GetFile("boot/Standalone.lua")
            assert(sourceFile and sourceFile:IsOpen(), "缺少生产周期同步源码")
            local lines = {}
            while not sourceFile:IsEof() do lines[#lines + 1] = sourceFile:ReadLine() end
            sourceFile:Dispose()
            local syncSource = table.concat(lines, "\n"):match("(local battleSync =.-)\nlocal physW")
            assert(syncSource, "未找到生产周期同步边界")
            for _, sample in ipairs(sceneLedgers) do
                local data = { currentStageId = 1001, maxStageId = 2001,
                    teamCurrentStageIds = { 1001, 101, 101 },
                    clearedStages = copy(sample.ledger), battleMode = "firstClear" }
                modules.battle = data
                setUpvalue(recalc, "currentStageId", 1001)
                setUpvalue(recalc, "clearedStages", { [2001] = true })
                Scene.setBattleData(copy(data))
                local syncEnv = setmetatable({ BattleScene = Scene,
                    ClientDispatcher = { get = function() return modules.battle end,
                        notifySubscribers = function() end },
                    StandaloneSave = { CaptureBattleProgress = function(battle) return battle end },
                }, { __index = _G })
                local syncChunk, syncErr = load(syncSource .. "\nreturn SyncBattleState",
                    "@boot/Standalone.lua#SyncBattleState", "t", syncEnv)
                assert(syncChunk, syncErr)
                local sync = syncChunk() --[[@as fun(dt: number)]]
                sync(1)
                local savedLedger = modules.battle.clearedStages
                check(savedLedger[2001] ~= true and savedLedger["2001"] ~= true,
                    "周期同步不将假首通写回账户 " .. sample.name, savedLedger["2001"], "not true")
                eq(Calc.resolveIdleIncomeStageId(modules.battle, SC), 1905,
                    "周期同步后账户收入仍按真实凭据 " .. sample.name)
                recalc()
                eq(upvalue(recalc, "cachedGoldPerMin"), priorGold,
                    "周期同步后显示不升未通最高档 " .. sample.name)
            end
        end)
    end)
    if not ok then
        harnessErrors = harnessErrors + 1
        runCase("harness", "Start", function() check(false, "Start exception", tostring(err), "no exception") end)
    end
    for i = #restores, 1, -1 do
        local restored, restoreErr = pcall(restores[i])
        if not restored then
            harnessErrors = harnessErrors + 1
            runCase("harness", "restore", function() check(false, "restore exception", tostring(restoreErr), "no exception") end)
        end
    end
    local names = {}
    for name in pairs(groups) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local g = groups[name]
        print(TAG .. " DIAG " .. name .. " cases=" .. g.cases .. " failedCases=" .. g.failedCases
            .. " assertions=" .. g.assertions .. " failures=" .. g.failures)
    end
    print(TAG .. " SUMMARY cases=" .. cases .. " passedCases=" .. (cases - failedCases)
        .. " failedCases=" .. failedCases .. " assertions=" .. assertions .. " passedAssertions=" .. (assertions - failures)
        .. " failures=" .. failures .. " harnessErrors=" .. harnessErrors)
    print(TAG .. (failures == 0 and " ALL PASS" or " FAIL"))
    engine:Exit()
end
