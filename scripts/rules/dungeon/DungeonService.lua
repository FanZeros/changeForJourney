-- ============================================================================
-- DungeonService - 资源副本挑战、首通与每日扫荡
-- 奖励在规则层一次结算；副本不推进主线，旧遗迹仅保留兼容。
-- ============================================================================
local PDM = require("rules.character.PlayerDataManager")
local DC = require("config.DungeonConfig")
local EquipmentSystem = require("systems.EquipmentSystem")
local LootBoxSystem = require("systems.LootBoxSystem")
local ExpTable = require("config.ExpTable")
local TeamSlots = require("shared.heroes.TeamSlots")

local DungeonService = {}

local function isKnown(id)
    return DC.isResourceDungeon(id) or id == "ancient_ruin"
end

local function getSub(dungeon, id)
    if not dungeon[id] then
        dungeon[id] = { floor = 1, cleared = {}, dailyUsed = 0, dailyDay = 0, idleAccumSec = 0 }
    end
    return dungeon[id]
end

local function getUnlockedData(uid, id)
    if not isKnown(id) then return nil, nil, "未知副本" end
    local dungeon = PDM.GetModule(uid, "dungeon")
    local battle = PDM.GetModule(uid, "battle")
    if not dungeon or not battle then return nil, nil, "数据未加载" end
    if (tonumber(battle.maxStageId or battle.currentStageId) or 0) < (DC.UNLOCK_CONDITIONS[id] or 0) then
        return nil, nil, "副本未解锁"
    end
    return getSub(dungeon, id), battle, nil
end

local function checkTeam(uid, battle, teamIdx)
    -- 旧调用未携带队号时保持兼容；正式资源入口始终显式传队号。
    if teamIdx == nil then return true, nil end
    local team = math.tointeger(tonumber(teamIdx) or 0)
    if not team or team < 1 or team > ExpTable.TEAM_COUNT then return false, "无效的队伍编号" end
    if team > ExpTable.getUnlockedTeamCount(battle) then return false, "该队伍尚未解锁" end
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then return false, "队伍数据未加载" end
    TeamSlots.normalize(heroes)
    local slots = heroes.teams and heroes.teams[team] and heroes.teams[team].slots or {}
    for _, heroId in ipairs(slots) do
        local id = tonumber(heroId) or 0
        if id > 0 and heroes.roster and (heroes.roster[id] or heroes.roster[tostring(id)]) then return true, nil end
    end
    return false, "该队伍未出战英雄"
end

--- 批量先生成、检查安全容器，再交付；失败不消耗日次或首通记录。
---@return boolean, string|nil, table|nil
function DungeonService.GrantEquipment(uid, dungeonId, floor, count)
    if dungeonId ~= "equipment_vault" then return false, "非装备副本" end
    count = math.tointeger(tonumber(count) or 0)
    local floorData = DC.getFloor(dungeonId, floor)
    local equipment = PDM.GetModule(uid, "equipment")
    local lootbox = PDM.GetModule(uid, "lootbox")
    if not count or count < 0 or not floorData then return false, "装备奖励配置无效" end
    if not equipment then return false, "装备数据未加载" end
    if EquipmentSystem.getInventoryCount(equipment) + count > EquipmentSystem.MAX_INVENTORY and not lootbox then
        return false, "遗匣数据未加载"
    end
    local generated = {}
    for i = 1, count do
        local quality = math.random(floorData.equipMinQuality, floorData.equipMaxQuality)
        local equip = EquipmentSystem.generateRandom(floorData.equipLevel, quality)
        if not equip then return false, "装备生成失败" end
        generated[i] = equip
    end
    local result = { equips = {}, inventoryCount = 0, lootboxCount = 0 }
    for _, equip in ipairs(generated) do
        local destination = LootBoxSystem.deliverEquipment(lootbox, equipment, equip)
        if destination == "lootbox" then result.lootboxCount = result.lootboxCount + 1
        else result.inventoryCount = result.inventoryCount + 1 end
        result.equips[#result.equips + 1] = {
            type = "equip", templateId = equip.templateId, quality = equip.quality,
            level = equip.level, slot = equip.slot, equip = equip, destination = destination,
        }
    end
    if result.inventoryCount > 0 then PDM.MarkDirty(uid, "equipment") end
    if result.lootboxCount > 0 then PDM.MarkDirty(uid, "lootbox") end
    return true, nil, result
end

local function grantRewards(uid, id, floorData, firstClear)
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, "数据未加载" end
    if id == "equipment_vault" then
        local count = firstClear and floorData.firstEquip or floorData.sweepEquip
        return DungeonService.GrantEquipment(uid, id, floorData.floor, count)
    end
    local gold = id == "gold_mine" and (firstClear and floorData.firstGold or floorData.sweepGold) or 0
    local diamond = id == "black_diamond" and (firstClear and floorData.firstDiamond or floorData.sweepDiamond) or 0
    local dust = id == "ancient_ruin" and (firstClear and floorData.firstDust or floorData.sweepDust) or 0
    currency.gold = (currency.gold or 0) + gold
    currency.gems = (currency.gems or 0) + diamond
    currency.arcaneDust = (currency.arcaneDust or 0) + dust
    if gold > 0 or diamond > 0 or dust > 0 then PDM.MarkDirty(uid, "currency") end
    return true, nil, { gold = gold, diamond = diamond, dust = dust }
end

function DungeonService.Sweep(uid, dungeonId)
    local sub, _, err = getUnlockedData(uid, dungeonId)
    if not sub then return false, err end
    local today = math.floor((os.time() + 28800) / 86400)
    local used = sub.dailyDay == today and (sub.dailyUsed or 0) or 0
    local limit = DC.DAILY_SWEEP_LIMIT[dungeonId] or 2
    if used >= limit then return false, "今日扫荡次数已用完" end
    local floor = DC.getHighestClearedFloor(sub, dungeonId)
    if floor < 1 then return false, "暂无可扫荡层" end
    local floorData = DC.getFloor(dungeonId, floor)
    if not floorData then return false, "层配置不存在" end
    local ok, grantErr, result = grantRewards(uid, dungeonId, floorData, false)
    if not ok then return false, grantErr end
    sub.dailyUsed, sub.dailyDay = used + 1, today
    PDM.MarkDirty(uid, "dungeon")
    result.dungeonId, result.sweepFloor = dungeonId, floor
    result.dailyUsed, result.dailyMax = sub.dailyUsed, limit
    print(string.format("[DungeonService] 扫荡 %s 层=%d 次数=%d/%d", dungeonId, floor, sub.dailyUsed, limit))
    return true, nil, result
end

function DungeonService.Challenge(uid, dungeonId, floor, teamIdx)
    local sub, battle, err = getUnlockedData(uid, dungeonId)
    if not sub then return false, err end
    floor = math.tointeger(tonumber(floor) or 0)
    if not floor or floor ~= sub.floor then return false, "只能挑战当前层" end
    local floorData = DC.getFloor(dungeonId, floor)
    if not floorData then return false, "层配置不存在" end
    local teamOk, teamErr = checkTeam(uid, battle, teamIdx)
    if not teamOk then return false, teamErr end
    local entry = DC.getCombatEntry(dungeonId, floor)
    local result = {
        dungeonId = dungeonId, floor = floor, teamIdx = teamIdx,
        monsterLevel = floorData.monsterLevel, monsters = floorData.monsters,
        resourceCombat = entry ~= nil, stageEntry = entry,
        maxFieldEnemies = entry and entry.maxFieldEnemies or 5,
        firstGold = floorData.firstGold, firstDust = floorData.firstDust,
        firstDiamond = floorData.firstDiamond, firstEquip = floorData.firstEquip,
        classBonus = entry and "" or DC.getClassBonus(floor),
        classBonusValue = entry and 0 or DC.CLASS_BONUS_VALUE,
        rageTime = entry and 120 or DC.RAGE_TIME,
        rageAtkBonus = DC.RAGE_ATK_BONUS,
        superRageTime = entry and 210 or DC.SUPER_RAGE_TIME,
        superRageAtkBonus = DC.SUPER_RAGE_ATK_BONUS,
        superRageDmgBonus = DC.SUPER_RAGE_DMG_BONUS,
        allyRageDmgBonus = DC.ALLY_RAGE_DMG_BONUS,
        allySuperRageDmgBonus = DC.ALLY_SUPER_RAGE_DMG_BONUS,
    }
    print(string.format("[DungeonService] 挑战 %s 层=%d 队伍=%s 主线复用=%s", dungeonId, floor, tostring(teamIdx), tostring(entry ~= nil)))
    return true, nil, result
end

function DungeonService.Win(uid, dungeonId, floor, teamIdx)
    local sub, battle, err = getUnlockedData(uid, dungeonId)
    if not sub then return false, err end
    floor = math.tointeger(tonumber(floor) or 0)
    if not floor or floor ~= sub.floor then return false, "楼层不匹配" end
    local floorData = DC.getFloor(dungeonId, floor)
    if not floorData then return false, "层配置不存在" end
    local teamOk, teamErr = checkTeam(uid, battle, teamIdx)
    if not teamOk then return false, teamErr end
    local cleared = sub.cleared or {}
    local firstClear = cleared[floor] ~= true and cleared[tostring(floor)] ~= true
    local result = { gold = 0, diamond = 0, dust = 0, equips = {} }
    if firstClear then
        local ok, grantErr, rewards = grantRewards(uid, dungeonId, floorData, true)
        if not ok then return false, grantErr end
        result = rewards
        cleared[floor] = true
        sub.cleared = cleared
    end
    if sub.floor < DC.MAX_FLOOR[dungeonId] then sub.floor = sub.floor + 1 end
    PDM.MarkDirty(uid, "dungeon")
    result.dungeonId, result.floor, result.teamIdx = dungeonId, floor, teamIdx
    result.firstClear, result.nextFloor = firstClear, sub.floor
    print(string.format("[DungeonService] 通关 %s 层=%d 首通=%s 下一层=%d", dungeonId, floor, tostring(firstClear), sub.floor))
    return true, nil, result
end

return DungeonService
