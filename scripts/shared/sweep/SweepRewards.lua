-- 扫荡共用规则：已通关关卡的一场重复战斗，不含首通大奖或挂机时长。
-- 预估只读；实际掉落复用在线逐杀接口。扫荡不产券，避免券自循环。
local SC = require("config.StageConfig")
local DC = require("config.DungeonConfig")
local MC = require("config.MonsterConfig")
local ET = require("config.ExpTable")
local DropSystem = require("systems.DropSystem")

local M = { COST = 1 }

local function isCleared(stageId, battle, dungeon)
    local id, floor = DC.decodeStageId(stageId)
    if id then
        if not DC.isStageUnlocked(stageId, battle, dungeon) then return false end
        local sub = dungeon and dungeon[id]
        if type(sub) ~= "table" then return false end
        local cleared = sub.cleared or {}
        if cleared[floor] == true or cleared[tostring(floor)] == true then return true end
        -- 仅无账本的旧档沿用 floor-1；新章节跳关不能凭最高层扫未打过的层。
        return not (dungeon.compat and dungeon.compat.resourceClearedV1)
            and next(cleared) == nil and floor < (tonumber(sub.floor) or 1)
    end
    if SC.isTerminalTemple(stageId) then return false end
    local cleared = battle and battle.clearedStages or {}
    return cleared[stageId] == true or cleared[tostring(stageId)] == true
end

function M.isCleared(stageId, battle, dungeon)
    return stageId ~= nil and isCleared(stageId, battle, dungeon)
end

--- 优先保留战线当前已通关关卡；资源回退同副本已通层，主线回退最高已通关。
function M.resolveDefaultStage(battle, dungeon, teamIdx, preferred)
    battle = battle or {}
    local tasks = battle.teamStageIds or {}
    local current = tonumber(preferred or tasks[tostring(teamIdx)] or tasks[teamIdx]
        or (teamIdx == 1 and battle.currentStageId))
    if current and isCleared(current, battle, dungeon) then return current end
    local id = current and DC.decodeStageId(current)
    if id then
        local sub = dungeon and dungeon[id]
        local highest = DC.getHighestClearedFloor(sub, id)
        for floor = highest, 1, -1 do
            local stageId = DC.getStageId(id, floor)
            if stageId and isCleared(stageId, battle, dungeon) then return stageId end
        end
        return nil
    end
    local highest = 0
    for key, cleared in pairs(battle.clearedStages or {}) do
        local stageId = math.tointeger(tonumber(key) or 0)
        if cleared == true and stageId and stageId > highest and SC.getStage(stageId)
            and not SC.isResourceStage(stageId) and not SC.isTerminalTemple(stageId) then
            highest = stageId
        end
    end
    return highest > 0 and highest or nil
end

--- 校验只读，不用 normalize 改写编队；字符串键旧存档同样可读。
function M.getTeam(heroes, battle, teamIdx)
    local team = math.tointeger(tonumber(teamIdx == nil and 1 or teamIdx) or 0)
    if not team or team < 1 or team > ET.TEAM_COUNT then return nil, "无效的队伍编号" end
    if team > ET.getUnlockedTeamCount(battle) then return nil, "该队伍尚未解锁" end
    if type(heroes) ~= "table" or type(heroes.roster) ~= "table" then return nil, "队伍数据未加载" end
    local teams = type(heroes.teams) == "table" and heroes.teams or {}
    local row = teams[team] or teams[tostring(team)]
    local slots = row and row.slots or (team == 1 and heroes.deployed) or {}
    if type(slots) ~= "table" or #slots > ET.TEAM_MAX_SLOTS then return nil, "无效的队伍槽位" end
    local ids, seen = {}, {}
    for _, value in ipairs(slots) do
        local id = math.tointeger(tonumber(value) or -1)
        if not id or id < 0 then return nil, "无效的出战英雄" end
        if id > 0 then
            if seen[id] then return nil, "重复的出战英雄" end
            if not (heroes.roster[id] or heroes.roster[tostring(id)]) then return nil, "未拥有出战英雄" end
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    if #ids == 0 then return nil, "该队伍未出战英雄" end
    for other = 1, ET.TEAM_COUNT do
        if other ~= team then
            local otherRow = teams[other] or teams[tostring(other)]
            for _, value in ipairs(otherRow and otherRow.slots or {}) do
                if seen[tonumber(value)] then return nil, "出战英雄重复编队" end
            end
        end
    end
    return ids, nil, team
end

function M.resolveStage(battle, dungeon, teamIdx, stageId)
    local id = stageId == nil and M.resolveDefaultStage(battle, dungeon, teamIdx)
        or math.tointeger(tonumber(stageId) or 0)
    local entry = id and SC.getStage(id)
    if not entry or (entry.monsterLevel or 0) <= 0 or not isCleared(id, battle, dungeon) then
        return nil, "请先通关该关卡后再扫荡"
    end
    return entry
end

local function addScrolls(target, source)
    for key, amount in pairs(source) do
        if key ~= "sweepTicket" then target[key] = (target[key] or 0) + amount end
    end
end

--- 返回值只供界面/扫荡结算，预估装备数允许小数，不能当实际装备交付。
function M.calculate(entry, heroCount, count, roll, luck, teamIdx)
    local result = { gold = 0, diamond = 0, playerExp = 0, heroExp = 0, heroExpTotal = 0,
        equipCount = 0, equips = {}, scrollDrops = {}, ticketDrop = 0, kills = 0 }
    local kills = math.max(0, math.floor(entry.idleCount or 0))
    local totalKills = kills * count
    local multiplier = ET.getHeroCountExpMult(heroCount)
    if SC.isResourceStage(entry.id) then
        -- 经验先按在线每杀双重取整，再乘杀数；同关每批等量，用常量空间表示顺序。
        local exp = DC.getStageExpAmount(entry.id, 1)
        local perHero = math.floor(math.floor(exp * multiplier + 0.5) / heroCount + 0.5)
        result.playerExp = exp * totalKills
        result.heroExp = perHero * totalKills
        result.heroExpBatch = { amount = perHero, count = totalKills }
        if roll then
            -- 每杀继续调用原 RNG 接口（含资源券判定，但不交付券），不合并随机掉落。
            for _ = 1, totalKills do
                local rewards = DC.getStageRewards(entry.id, 1, heroCount)
                result.gold = result.gold + rewards.gold
                result.diamond = result.diamond + rewards.diamond
                addScrolls(result.scrollDrops, rewards.scrollDrops)
                for _, seed in ipairs(rewards.equipSeeds) do
                    local equip = require("systems.EquipmentSystem").generateRandom(seed.level, seed.quality)
                    if not equip then error("扫荡装备生成失败") end
                    result.equips[#result.equips + 1] = equip
                end
            end
        else
            -- 纯预估只查询一次每杀期望，不遍历 count 场或生成 count*kills 数组。
            local id = DC.decodeStageId(entry.id)
            local amount = DC.getStageRewardAmount(entry.id, 1) * totalKills
            if id == "gold_mine" then result.gold = amount
            elseif id == "black_diamond" then result.diamond = amount
            else result.equipCount = amount end
            addScrolls(result.scrollDrops, DC.getStageScrollEstimate(entry.id, totalKills))
        end
        result.heroExpTotal = result.heroExp * heroCount
    else
        -- 与 BattleEnemySpawn.generateEnemyList(entry,false) 一致，Boss占一个名额。
        local monsters = entry.monsters or {}
        local normals = kills - ((entry.bossId or 0) > 0 and 1 or 0)
        local baseGold, baseExp = 0, 0
        local level = MC.LEVELS[entry.monsterLevel]
        if not level or #monsters == 0 or kills == 0 then error("扫荡战斗配置无效") end
        for i = 1, kills do
            local monsterId = i <= normals and monsters[((i - 1) % #monsters) + 1] or entry.bossId
            local monster = MC.MONSTERS[monsterId]
            if not monster then error("扫荡怪物配置无效") end
            local quality = MC.QUALITY[monster.quality] or MC.QUALITY[1]
            baseGold = baseGold + math.floor(level.goldDrop * quality.goldMult + 0.5)
            baseExp = baseExp + math.floor(level.baseExp * quality.expMult + 0.5)
        end
        result.gold, result.playerExp = baseGold * count, baseExp * count
        result.heroExpTotal = math.floor(baseExp * multiplier) * count
        result.heroExp = math.floor(baseExp * multiplier / heroCount + 0.5) * count
        result.heroExpBatch = { amount = math.floor(baseExp * multiplier / heroCount + 0.5), count = count }
        if roll then
            for _ = 1, kills * count do
                local quality = DropSystem.rollKillDrop(entry, { teamIdx = teamIdx, dropLuck = luck })
                if quality then
                    local equip = require("systems.EquipmentSystem").generateRandom(entry.monsterLevel, quality)
                    if not equip then error("扫荡装备生成失败") end
                    result.equips[#result.equips + 1] = equip
                end
                local scroll = DropSystem.rollScrollDrop(entry)
                if scroll then result.scrollDrops[scroll] = (result.scrollDrops[scroll] or 0) + 1 end
            end
        else
            local rate = math.min(1, (entry.dropRate or 0) * (1 + (luck or 0) / 100))
            result.equipCount = kills * count * rate
            result.scrollCount = kills * count * (entry.scrollDropRate or 0)
        end
    end
    result.kills = kills * count
    if roll then result.equipCount = #result.equips end
    if not result.scrollCount then
        result.scrollCount = 0
        for _, amount in pairs(result.scrollDrops) do result.scrollCount = result.scrollCount + amount end
    end
    return result
end

return M
