-- SweepService：一券一场重复战斗，主线与资源副本共用，奖励与扣券原子落盘。
local PDM = require("rules.character.PlayerDataManager")
local Rewards = require("shared.sweep.SweepRewards")
local ET = require("config.ExpTable")
local EquipmentSystem = require("systems.EquipmentSystem")
local EquipmentPower = require("systems.EquipmentPower")
local LootBoxSystem = require("systems.LootBoxSystem")
local DropSystem = require("systems.DropSystem")
local HeroResonance = require("shared.heroes.HeroResonance")
local Transaction = require("rules.dungeon.DungeonService")

local SweepService = { SWEEP_COST = Rewards.COST, MAX_COUNT = Rewards.MAX_COUNT }

local function getLuck(ids, heroes, equipment, artifacts, talents)
    local ctx = EquipmentPower.buildWornContext(ids[1], {
        heroes = heroes, equipment = equipment, artifacts = artifacts or {}, talents = talents or {},
    })
    return ctx and DropSystem.captureTeamLuck(ctx.teamUnits) or 0
end

--- 预估不读取 PDM、不消费 RNG、不规范化/修改玩家表。
function SweepService.Preview(heroes, battle, dungeon, equipment, artifacts, talents, teamIdx, stageId, count)
    local ids, err, team = Rewards.getTeam(heroes, battle, teamIdx)
    if not ids then return nil, err end
    local entry, stageErr = Rewards.resolveStage(battle, dungeon, team, stageId)
    if not entry then return nil, stageErr end
    local times = math.tointeger(tonumber(count == nil and 1 or count) or 0)
    if not times or times < 1 or times > Rewards.MAX_COUNT then return nil, "无效的扫荡次数" end
    local luck = getLuck(ids, heroes, equipment, artifacts, talents)
    local result = Rewards.calculate(entry, #ids, times, false, luck, team)
    result.stageId, result.teamIdx, result.count, result.dropLuck = entry.id, team, times, luck
    result.cost = times * Rewards.COST
    return result
end

function SweepService.Sweep(uid, count, teamIdx, stageId)
    local times = math.tointeger(tonumber(count == nil and 1 or count) or 0)
    if not times or times < 1 or times > Rewards.MAX_COUNT then return false, "无效的扫荡次数" end
    local currency = PDM.GetModule(uid, "currency")
    local battle = PDM.GetModule(uid, "battle")
    local heroes = PDM.GetModule(uid, "heroes")
    local player = PDM.GetModule(uid, "player")
    local equipment = PDM.GetModule(uid, "equipment")
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not currency or not battle or not heroes or not player or not equipment then return false, "数据未加载" end
    local ids, teamErr, team = Rewards.getTeam(heroes, battle, teamIdx)
    if not ids then return false, teamErr end
    local entry, stageErr = Rewards.resolveStage(battle, dungeon, team, stageId)
    if not entry then return false, stageErr end
    local cost = times * Rewards.COST
    local owned = tonumber(currency.sweepTicket) or 0
    if owned < cost then return false, "扫荡券不足" end
    local luck = getLuck(ids, heroes, equipment, PDM.GetModule(uid, "artifacts"), PDM.GetModule(uid, "talents"))
    local lootbox = PDM.GetModule(uid, "lootbox")
    local ok, err, result = Transaction.CommitRewardTransaction(uid, function()
        local rewards = Rewards.calculate(entry, #ids, times, true, luck, team)
        if EquipmentSystem.getInventoryCount(equipment) + #rewards.equips > EquipmentSystem.MAX_INVENTORY
            and not lootbox then return false, "遗匣数据未加载" end
        -- 掉落全部生成成功后才交付；持久化/交付失败由同一事务原位回滚。
        currency.sweepTicket = owned - cost
        currency.gold = (currency.gold or 0) + rewards.gold
        currency.gems = (currency.gems or 0) + rewards.diamond
        for field, amount in pairs(rewards.scrollDrops) do
            currency[field] = (currency[field] or 0) + amount
        end
        Transaction.MarkRewardDirty(uid, "currency")
        local granted, byQuality = {}, {}
        local inventoryCount, lootboxCount = 0, 0
        for _, equip in ipairs(rewards.equips) do
            local destination = LootBoxSystem.deliverEquipment(lootbox, equipment, equip)
            if destination == "lootbox" then lootboxCount = lootboxCount + 1
            else inventoryCount = inventoryCount + 1 end
            granted[#granted + 1] = { type = "equip", templateId = equip.templateId,
                quality = equip.quality, level = equip.level, slot = equip.slot,
                equip = equip, destination = destination }
            byQuality[equip.quality] = (byQuality[equip.quality] or 0) + 1
        end
        if inventoryCount > 0 then Transaction.MarkRewardDirty(uid, "equipment") end
        if lootboxCount > 0 then Transaction.MarkRewardDirty(uid, "lootbox") end
        if rewards.heroExp > 0 then
            -- 与 CharacterProgress.addHeroesExp 同序：每场/每杀、每名英雄入账后立即共鸣。
            -- 不能聚合后统一共鸣，地板升级时会改变后续英雄被清零/领取经验的顺序。
            for _, amount in ipairs(rewards.heroExpBatches) do
                for _, id in ipairs(ids) do
                    local hero = heroes.roster[id] or heroes.roster[tostring(id)]
                    hero.exp = (hero.exp or 0) + amount
                    ET.autoLevelUpHero(hero)
                    HeroResonance.syncRosterToResonance(heroes.roster)
                end
            end
            Transaction.MarkRewardDirty(uid, "heroes")
        end
        rewards.heroExpBatches = nil
        if rewards.playerExp > 0 then
            player.exp = (player.exp or 0) + rewards.playerExp
            ET.autoLevelUpPlayer(player)
            Transaction.MarkRewardDirty(uid, "player")
        end
        rewards.equips, rewards.equipByQuality = granted, byQuality
        rewards.count, rewards.teamIdx, rewards.stageId = times, team, entry.id
        rewards.sweepStages, rewards.ticketLeft = { entry.id }, currency.sweepTicket
        rewards.inventoryCount, rewards.lootboxCount = inventoryCount, lootboxCount
        return true, nil, rewards
    end)
    if not ok then return false, err end
    print(string.format("[SweepService] 队%d 关卡%d %d场 金币=%d 黑晶=%d 经验=%d 装备=%d 卷轴=%d 剩余券=%d",
        team, entry.id, times, result.gold, result.diamond, result.playerExp,
        result.equipCount, result.scrollCount, result.ticketLeft))
    return true, nil, result
end

return SweepService
