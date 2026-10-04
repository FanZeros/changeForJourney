-- 满包奖励守恒回归：真实服务/装备/遗匣/路由，文件 API 使用内存替身。
-- 不读写玩家存档；生成后禁止重骰，覆盖部分入包、满包、重领与重启。
local ES = require("systems.EquipmentSystem")
local LS = require("systems.LootBoxSystem")
local PDM = require("rules.character.PlayerDataManager")
local Offline = require("rules.offline.OfflineService")
local Sweep = require("rules.sweep.SweepService")
local Battle = require("rules.battle.BattleService")
local Calc = require("systems.OfflineCalc")
local StageProvider = require("shared.StageProvider")
local HeroService = require("rules.hero.HeroService")
local Protocol = require("shared.Protocol")
local OfflineHandler = require("rules.offline.OfflineHandler")
local SweepHandler = require("rules.sweep.SweepHandler")
local BattleHandler = require("rules.battle.BattleHandler")
local LootboxSchema = require("shared.lootbox.LootboxSchema")

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
    for key, child in pairs(value) do out[key] = copy(child) end
    return out
end
local function same(actual, expected, message)
    eq(type(actual), type(expected), message .. " 类型")
    if type(expected) == "table" then
        for key, value in pairs(expected) do same(actual[key], value, message .. "." .. tostring(key)) end
        for key in pairs(actual) do check(expected[key] ~= nil, message .. " 多余字段") end
    elseif type(expected) == "number" then
        check(math.abs(actual - expected) <= 1e-10 * math.max(1, math.abs(expected)), message .. " 数值")
    else
        eq(actual, expected, message)
    end
end
local function sameEquip(actual, expected)
    local a, b = copy(actual), copy(expected)
    a.seq, b.seq = nil, nil
    same(a, b, "完整装备")
end
local function newModules(count)
    local bag = { inventory = {}, equipped = {}, nextSeq = 1 }
    local filler = assert(ES.generate("W1", 1, 1))
    for _ = 1, count do ES.addToInventory(bag, copy(filler)) end
    return {
        equipment = bag, lootbox = { seeds = {} },
        session = { lastOnlineTime = 6400, firstLoginTime = 1,
            claimedScenarios = {}, scenarioRewardsGranted = {} },
        currency = { gold = 40, sweepTicket = 10, weaponScroll = 0 },
        player = { level = 80, exp = 0 },
        heroes = { roster = { [1] = { level = 80, exp = 0 } }, deployed = { 1 },
            teams = { { slots = { 1 } } } },
        battle = { currentStageId = 102, maxStageId = 102, clearedStages = { [101] = true, [102] = true } },
    }
end

function Start()
    local restores = {}
    local modules = newModules(0)
    local dirty = {}
    local generated = {}
    local forbidden = false
    local function patch(target, key, value)
        local original = target[key]
        restores[#restores + 1] = function() target[key] = original end
        target[key] = value
    end
    local function reset(count)
        Offline.Cleanup(1)
        modules, dirty, generated, forbidden = newModules(count), {}, {}, false
    end
    local realGenerate = ES.generateRandom
    local realMarkDirty = PDM.MarkDirty
    local ok, err = pcall(function()
        patch(os, "time", function() return 10000 end)
        patch(PDM, "GetModule", function(_, name) return modules[name] end)
        patch(PDM, "MarkDirty", function(_, name) dirty[name] = (dirty[name] or 0) + 1 end)
        patch(HeroService, "ApplyResonanceSync", function() end)
        patch(HeroService, "SyncHeroLevelsToPlayerLevel", function() end)
        local CP = require("ui.character.panel.CharacterPanel")
        patch(CP, "isHeroesDataApplied", function() return false end)
        patch(CP, "getTeamSlotIds", function() return {} end)
        patch(ES, "generateRandom", function(level, quality)
            check(not forbidden, "确定装备后不能再次随机生成")
            local equip = assert(realGenerate(level, quality))
            equip.locked = true
            equip.ascendLevel = 12
            equip.refineCount = 3
            generated[#generated + 1] = { equip = equip, snapshot = copy(equip) }
            return equip
        end)
        patch(Calc, "calcOfflineIdleRewards", function()
            return { seconds = 3600, kills = 5, gold = 7, adventureExp = 0, adventurerExp = 60,
                equipSeeds = { { level = 80, quality = 6, count = 3 } }, scrollDrops = { weaponScroll = 2 } }
        end)
        patch(Calc, "resolveIdleStageAnchors", function() return 101, 101 end)

        -- 离线预览和真实发奖必须是同一批实例，预览之后容量仍可变化。
        for _, count in ipairs({ 0, 197, 199, 200, 201 }) do
            reset(count)
            local panel = assert(Offline.CalcOnEnter(1))
            local previews = {}
            for _, item in ipairs(panel.rewards) do
                if item.type == "equip" then previews[#previews + 1] = item.equip end
            end
            eq(#previews, 3, "离线完整预览")
            eq(Offline.CalcOnEnter(1), panel, "重复进场复用预览")
            eq(#generated, 3, "重复预览不重骰")
            forbidden = true
            local result = OfflineHandler.actionHandlers[Protocol.ACTION_TYPES.CLAIM_OFFLINE_REWARDS](1, {})
            eq(result.success, true, "离线满包仍可安全领取")
            local direct = math.min(3, math.max(0, 200 - count))
            eq(ES.getInventoryCount(modules.equipment), count + direct, "离线容量不扩张")
            eq(#modules.lootbox.seeds, 3 - direct, "离线溢出全部保留")
            eq(#result.lootboxEquips, 3 - direct, "离线回执准确提示溢出装备")
            for _, item in ipairs(result.lootboxEquips) do
                eq(item.destination, "lootbox", "离线回执去向")
                check(item.equip ~= nil, "离线回执带完整实例")
            end
            eq(dirty.lootbox ~= nil, direct < 3, "遗匣仅实际变更才推送")
            eq(dirty.equipment ~= nil, direct > 0, "背包仅实际变更才推送")
            for index, entry in ipairs(generated) do
                eq(previews[index], entry.equip, "领取复用预览实例")
                sameEquip(entry.equip, entry.snapshot)
                if index <= direct then
                    eq(modules.equipment.inventory[tostring(entry.equip.seq)], entry.equip, "离线实例入包")
                else
                    eq(modules.lootbox.seeds[index - direct].equip, entry.equip, "离线实例入遗匣")
                end
            end
            eq(modules.currency.gold, 47, "离线金币一次")
            eq(modules.currency.weaponScroll, 2, "离线卷轴一次")
            eq(modules.heroes.roster[1].exp, 60, "离线英雄经验一次")
            eq(modules.session.lastOnlineTime, 10000, "安全保管后推进时间")
            local snapshot = copy(modules)
            eq(Offline.ClaimRewards(1), false, "离线不能二次发奖")
            same(modules, snapshot, "二次领取无副作用")
        end
        reset(199)
        local pending = assert(Offline.CalcOnEnter(1))
        ES.addToInventory(modules.equipment, assert(ES.generate("W1", 1, 1)))
        forbidden = true
        eq(Offline.ClaimRewards(1), true, "预览后满包仍可领取")
        eq(#modules.lootbox.seeds, 3, "按领取时容量全部转存")
        eq(pending.rewards[2].equip, modules.lootbox.seeds[1].equip, "变化后不重骰预览")

        -- 遗匣数据缺失：发奖/扣券之前拒绝，离线待领保留，数据恢复后可原样重试。
        reset(200)
        Offline.CalcOnEnter(1)
        modules.lootbox = nil
        dirty = {}
        local before = copy(modules)
        eq(Offline.ClaimRewards(1), false, "离线无安全容器时拒绝")
        same(modules, before, "离线拒绝不发金币经验或推进时间")
        eq(Offline.HasPendingRewards(1), true, "离线拒绝保留待领")
        eq(next(dirty), nil, "离线拒绝不推送")
        modules.lootbox = { seeds = {} }
        forbidden = true
        eq(Offline.ClaimRewards(1), true, "恢复遗匣后重试")
        eq(#modules.lootbox.seeds, 3, "重试三件完整保留")

        -- 扫荡单次和十连都返回全部装备（含去向），不按入包数吞掉溢出结果。
        for _, case in ipairs({ { 0, 1 }, { 190, 1 }, { 199, 1 }, { 200, 1 }, { 199, 10 }, { 201, 1 } }) do
            reset(case[1])
            local result = SweepHandler.actionHandlers[Protocol.ACTION_TYPES.SWEEP](1, { count = case[2], teamIdx = 1 })
            eq(result.success, true, "扫荡安全发奖")
            local total = case[2] * Sweep.EQUIP_DROP_COUNT
            local direct = math.min(total, math.max(0, 200 - case[1]))
            eq(result.equipCount, total, "扫荡结果包含所有已保管装备")
            eq(#generated, total, "扫荡每件仅生成一次")
            eq(ES.getInventoryCount(modules.equipment), case[1] + direct, "扫荡容量")
            eq(#modules.lootbox.seeds, total - direct, "扫荡溢出守恒")
            eq(modules.currency.sweepTicket, 10 - case[2], "扫荡正常扣券")
            eq(dirty.lootbox ~= nil, direct < total, "扫荡遗匣推送")
            eq(dirty.equipment ~= nil, direct > 0, "扫荡背包推送")
            local qualityTotal = 0
            for _, value in pairs(result.equipByQuality) do qualityTotal = qualityTotal + value end
            eq(qualityTotal, total, "品质统计包含遗匣装备")
            for index, entry in ipairs(generated) do
                eq(result.equips[index].equip, entry.equip, "结果提供真实实例")
                eq(result.equips[index].destination, index <= direct and "inventory" or "lootbox", "结果准确去向")
                sameEquip(entry.equip, entry.snapshot)
                if index > direct then eq(modules.lootbox.seeds[index - direct].equip, entry.equip, "扫荡原实例入匣") end
            end
            forbidden = true
            local loaded = cjson.decode(cjson.encode(modules.lootbox))
            LootboxSchema.Fields.lootbox.onLoad(loaded)
            same(loaded, modules.lootbox, "JSON恢复不丢字段或重骰")
            if total > direct then
                local claimed, full = LS.claimAll(loaded, modules.equipment)
                eq(#claimed, 0, "满包领取仍保留遗匣")
                eq(full, true, "满包正确提示")
                for seq = 1, math.max(1, case[1] - 199) do
                    ES.removeFromInventory(modules.equipment, seq)
                end
                local one = LS.claimAll(loaded, modules.equipment)
                eq(#one, 1, "腾出一格只领一件")
                eq(#loaded.seeds, total - direct - 1, "其余装备完整保留")
            end
        end
        reset(200)
        modules.lootbox = nil
        before = copy(modules)
        eq(Sweep.Sweep(1, 1, 1), false, "扫荡无遗匣拒绝")
        same(modules, before, "扫荡拒绝不扣券或发奖")
        eq(#generated, 0, "拒绝不生成随机装备")
        eq(next(dirty), nil, "拒绝不推模块")

        -- 情景5–10：即使起播已预记claimed，满包仍发往遗匣并只记成功一次。
        for scenarioId = 5, 10 do
            reset(200)
            local heroId = (scenarioId - 5) % 3 + 1
            modules.heroes.deployed = { heroId }
            modules.heroes.roster[heroId] = { level = 80, exp = 0 }
            modules.session.initialHeroId = heroId
            modules.battle.clearedStages["101"] = true
            modules.battle.clearedStages["102"] = true
            modules.session.claimedScenarios[tostring(scenarioId)] = true
            local result = BattleHandler.actionHandlers[Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD](1,
                { scenarioId = scenarioId, preClaimed = true })
            eq(result.success, true, "情景满包正常完成发奖")
            eq(result.reward.destination, "lootbox", "情景回执遗匣去向")
            eq(result.reward.equip, modules.lootbox.seeds[1].equip, "情景完整实例入匣")
            eq(ES.getInventoryCount(modules.equipment), 200, "情景不扩容")
            eq(modules.session.scenarioRewardsGranted[tostring(scenarioId)], true, "成功保管才记账")
            check(dirty.lootbox ~= nil, "情景遗匣即时同步")
            local snapshot = copy(modules)
            eq(Battle.ClaimScenarioReward(1, scenarioId, true), false, "preClaimed不能重复发装")
            same(modules, snapshot, "情景重复无副作用")
        end

        -- 满包换装/卸下本来就只改槽引用，不重新入包或改变seq。
        reset(200)
        local second = ES.addToInventory(modules.equipment, assert(ES.generate("W7", 1, 2)))
        ES.removeFromInventory(modules.equipment, 200)
        local bag = modules.equipment
        local inventory, nextSeq = copy(bag.inventory), bag.nextSeq
        eq(ES.applyEquip(bag, 1, 1, "weapon", modules.heroes), true, "满包穿戴")
        eq(ES.applyEquip(bag, second, 1, "weapon", modules.heroes), true, "满包换装")
        eq(ES.applyUnequip(bag, 1, "weapon"), true, "满包卸下")
        ES.applyEquip(bag, 1, 1, "weapon", modules.heroes)
        eq(ES.applyUnequipAll(bag, 1), true, "满包全部卸下")
        same(bag.inventory, inventory, "装卸库存守恒")
        eq(bag.nextSeq, nextSeq, "装卸不分配序列号")

        -- 真实消息路由保留装备和destination，复用既有“已入遗匣”显示。
        local Msg = require("runtime.ClientMessageHandler")
        local shown = {}
        local popupCount = 0
        local routedPopup = false
        local replacements = {
            RewardPopup = { show = function(_, rewards)
                shown = rewards
                popupCount = popupCount + 1
            end },
            TutorialManager = { onScenarioClaimed = function() end },
            BlacksmithPage = {}, ChurchPage = {}, TavernPage = {}, DungeonBattleScene = {},
            MarketPage = {}, GMConsolePanel = {}, DungeonPage = {}, EquipmentDetail = {},
        }
        for i = 1, 100 do
            local name, value = debug.getupvalue(Msg.handleActionResult, i)
            if not name then break end
            if replacements[name] then
                if name == "RewardPopup" then routedPopup = true end
                local index, previous = i, value
                restores[#restores + 1] = function() debug.setupvalue(Msg.handleActionResult, index, previous) end
                debug.setupvalue(Msg.handleActionResult, i, replacements[name])
            end
        end
        check(routedPopup, "捕获真实路由弹窗依赖")
        patch(_G, "BackpackPanel", {})
        local Dialog = require("ui.battle.stage.SweepDialog")
        patch(Dialog, "isOpen", function() return false end)
        local equip = assert(ES.generate("W7", 1, 2))
        for _, destination in ipairs({ "inventory", "lootbox" }) do
            shown = {}
            local beforePopup = popupCount
            Msg.handleActionResult({ action = Protocol.ACTION_TYPES.SWEEP, success = true,
                equips = { { templateId = equip.templateId, quality = equip.quality, level = equip.level,
                    slot = equip.slot, equip = equip, destination = destination } } })
            eq(popupCount, beforePopup + 1, "扫荡实际创建新弹窗")
            eq(shown[1].equip, equip, "扫荡UI不丢完整实例")
            eq(shown[1].destination, destination, "扫荡UI不丢去向")
            shown = {}
            beforePopup = popupCount
            Msg.handleActionResult({ action = Protocol.ACTION_TYPES.CLAIM_SCENARIO_REWARD, success = true,
                rewardType = "equip", reward = { templateId = equip.templateId, quality = equip.quality,
                    level = equip.level, slot = equip.slot, equip = equip, destination = destination } })
            eq(popupCount, beforePopup + 1, "情景实际创建新弹窗")
            eq(shown[1].equip, equip, "情景UI不丢完整实例")
            eq(shown[1].destination, destination, "情景UI不丢去向")
        end
        shown = {}
        local beforePopup = popupCount
        Msg.handleActionResult({ action = Protocol.ACTION_TYPES.CLAIM_OFFLINE_REWARDS, success = true,
            lootboxEquips = { { type = "equip", equip = equip, destination = "lootbox" } } })
        eq(popupCount, beforePopup + 1, "离线转存实际提示")
        eq(shown[1].equip, equip, "离线提示完整实例")
        eq(shown[1].destination, "lootbox", "离线提示去向")
        Msg.handleActionResult({ action = Protocol.ACTION_TYPES.CLAIM_OFFLINE_REWARDS, success = true,
            lootboxEquips = {} })
        eq(popupCount, beforePopup + 1, "无溢出不多弹提示")
        -- 真实PDM推送→Dispatcher双onLoad→StandaloneSave原子写档→恢复→领取。
        -- File/Rename只用内存，不接触当前玩家存档。
        reset(200)
        local Dispatcher = require("runtime.ClientDispatcher")
        local GameState = require("core.GameState")
        local Save = require("boot.StandaloneSave")
        local live = Dispatcher.getAll()
        local previous = {}
        for name, value in pairs(live) do previous[name] = value end
        restores[#restores + 1] = function()
            for name in pairs(live) do live[name] = nil end
            for name, value in pairs(previous) do live[name] = value end
        end
        for name in pairs(live) do live[name] = nil end
        for name, value in pairs(modules) do Dispatcher.set(name, value) end
        modules = live
        PDM.Setup({ serverDispatcher = { pushModule = function(_, name, value)
            Dispatcher.set(name, value)
        end } })
        PDM.AttachLocalModules(1, live)
        patch(PDM, "MarkDirty", function(uid, name)
            dirty[name] = (dirty[name] or 0) + 1
            realMarkDirty(uid, name)
        end)
        patch(GameState, "exportSave", function() return {} end)
        patch(GameState, "importSave", function() end)
        patch(GameState, "syncPlayerData", function() end)
        local disk = {}
        patch(_G, "fileSystem", {
            FileExists = function(_, path) return disk[path] ~= nil end,
            Rename = function(_, from, to)
                if not disk[from] then return false end
                disk[to], disk[from] = disk[from], nil
                return true
            end,
            Delete = function(_, path) disk[path] = nil end,
        })
        patch(_G, "File", function(path)
            return {
                IsOpen = function() return true end,
                ReadString = function() return disk[path] end,
                WriteString = function(_, text) disk[path] = text return true end,
                Close = function() end,
            }
        end)
        eq(Save.RestoreData(), false, "内存新档无旧存档")
        local preview = assert(Offline.CalcOnEnter(1))
        for index, entry in ipairs(generated) do entry.equip.testRewardId = index end
        forbidden = true
        eq(Offline.ClaimRewards(1), true, "满包领取后准备落盘")
        Save.OfflineChecked()
        eq(Save.Flush(), true, "真实Save原子提交")
        local expected = copy(modules.lootbox)
        for name in pairs(live) do live[name] = nil end
        eq(Save.RestoreData(), true, "真实Save恢复")
        same(modules.lootbox, expected, "重启保留全部遗匣装备")
        eq(modules.currency.gold, 47, "重启不丢金币")
        eq(Offline.ClaimRewards(1), false, "重启不重复领取离线")
        ES.removeFromInventory(modules.equipment, 1)
        ES.removeFromInventory(modules.equipment, 2)
        ES.removeFromInventory(modules.equipment, 3)
        local claimed = LS.claimAll(modules.lootbox, modules.equipment)
        eq(#claimed, 3, "重启后三件都可领取")
        for _, equip in ipairs(claimed) do
            local matched = false
            for _, item in ipairs(preview.rewards) do
                if item.equip and item.equip.testRewardId == equip.testRewardId then
                    sameEquip(equip, item.equip)
                    matched = true
                    break
                end
            end
            check(matched, "重启领取仍为原预览装备")
        end
        eq(Save.Flush(), true, "领取结果再次落盘")
        for name in pairs(live) do live[name] = nil end
        eq(Save.RestoreData(), true, "领取后再次重启")
        eq(#modules.lootbox.seeds, 0, "二次重启遗匣已清空")
        eq(ES.getInventoryCount(modules.equipment), 200, "二次重启背包容量守恒")
        eq(#LS.claimAll(modules.lootbox, modules.equipment), 0, "二次重启不能重复出装")
    end)
    Offline.Cleanup(1)
    for i = #restores, 1, -1 do restores[i]() end
    engine:Exit()
    if not ok then error("[full_bag_rewards_test] " .. tostring(err)) end
    print("[full_bag_rewards_test] ALL PASS: " .. assertions .. " assertions")
end
