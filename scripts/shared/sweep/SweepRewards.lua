-- 扫荡共用规则：已通关关卡的一场重复战斗，不含首通大奖或挂机时长。
-- 预估只读；实际掉落批量抽取数量，逐件生成完整装备。扫荡不产券，避免券自循环。
local SC = require("config.StageConfig")
local DC = require("config.DungeonConfig")
local MC = require("config.MonsterConfig")
local ET = require("config.ExpTable")
local DropSystem = require("systems.DropSystem")
local BatchRandom = require("shared.sweep.BatchRandom")
local EquipmentSystem = require("systems.EquipmentSystem")

---@class SweepCalculatedReward
---@field gold number
---@field diamond number
---@field playerExp number
---@field heroExp number
---@field heroExpTotal number
---@field equipCount number
---@field equips table[]
---@field scrollDrops table<string, number>
---@field ticketDrop number
---@field kills number
---@field scrollCount number?
---@field heroExpBatch {amount: number, count: number}?

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

local SCROLL_TYPES = { "weaponScroll", "offhandScroll", "armorScroll", "helmetScroll", "shoesScroll", "accessoryScroll" }

-- 每杀 floor(raw)+Bernoulli(frac) 的总和；不能对 raw*总杀数只做一次随机取整。
local function roundedTotal(raw, trials, checkpoint)
    local base = math.floor(raw)
    return base * trials + BatchRandom.binomial(trials, raw - base, nil, checkpoint)
end

-- 独立卷轴先抽总数，再按条件二项分布拆六类，保留多项分布及类别间负相关。
local function rollScrolls(target, amount, checkpoint)
    local remaining = amount
    for index, key in ipairs(SCROLL_TYPES) do
        local value = index == #SCROLL_TYPES and remaining
            or BatchRandom.binomial(remaining, 1 / (#SCROLL_TYPES - index + 1), nil, checkpoint)
        if value > 0 then target[key] = value end
        remaining = remaining - value
    end
end

local function generateEquips(result, amount, level, rollQuality, checkpoint)
    if checkpoint then checkpoint("generate", 0, amount) end
    for index = 1, amount do
        -- 品质按掉落顺序独立抽取，不按品质分组，以免改变有限仓位优先接收的分布。
        local equip = EquipmentSystem.generateRandom(level, rollQuality())
        if not equip then error("扫荡装备生成失败") end
        result.equips[#result.equips + 1] = equip
        if checkpoint then checkpoint("generate", index, amount) end
    end
end

--- 返回值只供界面/扫荡结算，预估装备数允许小数，不能当实际装备交付。
--- 批量计数保持独立击杀的奖励分布，不保留旧版同seed逐件结果或RNG消费序列。
--- 调用方负责全局RNG独占，检查点只暂停私有计算，绝不用于live奖励事务。
function M.calculate(entry, heroCount, count, roll, luck, teamIdx, control)
    local checkpoint = control and control.checkpoint
    local dropContext = { teamIdx = teamIdx, dropLuck = luck, silent = control and control.summaryLogs == true }
    ---@type SweepCalculatedReward
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
            -- 只抽每杀随机尾数的总和，金币/黑晶不再为数百万个空击杀建临时奖励表。
            local sampleCheckpoint = checkpoint and function() return checkpoint("generate", 0, 0) end or nil
            local id, floor = DC.decodeStageId(entry.id)
            assert(id and floor, "扫荡资源副本配置无效")
            local amount = roundedTotal(DC.getStageRewardAmount(entry.id, 1), totalKills, sampleCheckpoint)
            if id == "gold_mine" then result.gold = amount
            elseif id == "black_diamond" then result.diamond = amount
            else
                local data = assert(DC.getFloor(id, floor), "扫荡装备副本配置无效")
                local scrollRate = DC.getEquipDropRates(floor)
                local scrolls = roundedTotal(scrollRate, totalKills, sampleCheckpoint)
                rollScrolls(result.scrollDrops, scrolls, sampleCheckpoint)
                -- 扫荡不发券，不再为必定丢弃的资源券消耗随机数。
                generateEquips(result, amount, data.equipLevel, function()
                    return DropSystem.rollQualityByProbabilities(data.equipQualityProbabilities)
                end, checkpoint)
            end
            if id ~= "equipment_vault" and checkpoint then checkpoint("generate", 0, 0) end
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
            local sampleCheckpoint = checkpoint and function() return checkpoint("generate", 0, 0) end or nil
            local rate, rollQuality = DropSystem.createKillDropContext(entry, dropContext)
            local amount = BatchRandom.binomial(totalKills, rate, nil, sampleCheckpoint)
            local scrollRate = math.max(0, math.min(1, entry.scrollDropRate or 0))
            rollScrolls(result.scrollDrops, BatchRandom.binomial(totalKills, scrollRate, nil, sampleCheckpoint), sampleCheckpoint)
            generateEquips(result, amount, entry.monsterLevel, rollQuality, checkpoint)
        else
            ---@type number
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
