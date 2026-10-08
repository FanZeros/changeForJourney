-- 扫荡成长共用入口：资源每杀/主线每场，每名英雄加经验→升级→立即共鸣。
-- 同关批次等量；只跨过确定没有任何升级的完整批次，保留地板清经验的时序。
local ET = require("config.ExpTable")
local Resonance = require("shared.heroes.HeroResonance")

local M = {}

local function getHero(roster, id)
    return roster[id] or roster[tostring(id)]
end

local function applyBatch(roster, ids, amount)
    for _, id in ipairs(ids) do
        local hero = getHero(roster, id)
        hero.exp = (hero.exp or 0) + amount
        ET.autoLevelUpHero(hero)
        Resonance.syncRosterToResonance(roster)
    end
end

-- IEEE 双精度可精确累加的整数范围；不满足条件的旧数据保留逐批原路径。
local EXACT_INTEGER = 9007199254740991
local function exactNonnegative(value)
    return type(value) == "number" and value >= 0 and value <= EXACT_INTEGER and value % 1 == 0
end

local function safeBatchCount(roster, ids, amount, remaining)
    if not exactNonnegative(amount) or amount <= 0 then return 0 end
    -- 合法槽位ID不重复，但旧档可能让两个ID引用同一个hero表，须按真实入账次数计算。
    local received = {}
    for _, id in ipairs(ids) do
        local hero = getHero(roster, id)
        received[hero] = (received[hero] or 0) + amount
    end
    local safe = remaining
    for hero, perBatch in pairs(received) do
        local level = hero.level or 1
        if not exactNonnegative(level) or level < 1 then return 0 end
        if not ET.isHeroMaxLevel(level) then
            local exp = hero.exp or 0
            local needed = ET.getHeroExpForLevel(level)
            if not exactNonnegative(exp) or not exactNonnegative(perBatch)
                or (needed and (not exactNonnegative(needed) or needed <= 0)) then return 0 end
            -- 缺经验表时原autoLevelUp只维护maxExp、不升级；仍不可溢出整数精确范围。
            local room = (needed or EXACT_INTEGER) - exp
            local limit = needed and math.ceil(room / perBatch) - 1 or math.floor(room / perBatch)
            safe = math.min(safe, math.max(0, limit))
        end
    end
    return safe
end

local function applyHeroes(roster, ids, batch)
    local amount, remaining = batch.amount, batch.count
    if amount <= 0 or remaining <= 0 then return end
    -- 第一批必须原序执行：初始名册可能尚未共鸣，满级英雄也必须清exp/maxExp。
    applyBatch(roster, ids, amount)
    remaining = remaining - 1
    while remaining > 0 do
        local skipped = safeBatchCount(roster, ids, amount, remaining)
        if skipped > 0 then
            -- 此段无人升级，地板已在上一真实批次同步；共鸣重复调用不会改任何字段。
            -- 满级仍走autoLevelUp清零，绝不把其跳过段经验累积到回执或存档。
            for _, id in ipairs(ids) do
                local hero = getHero(roster, id)
                if not ET.isHeroMaxLevel(hero.level or 1) then
                    hero.exp = (hero.exp or 0) + amount * skipped
                end
                ET.autoLevelUpHero(hero)
            end
            remaining = remaining - skipped
        else
            -- 跨升级/满级/共鸣边界时保留完整的逐英雄顺序，不聚合经验。
            applyBatch(roster, ids, amount)
            remaining = remaining - 1
        end
    end
end

local function progress(data, beforeLevel, hero)
    local level = data.level or 1
    local capped = hero and ET.isHeroMaxLevel(level) or not hero and ET.isPlayerMaxLevel(level)
    local needed = hero and ET.getHeroExpForLevel(level) or not hero and ET.getPlayerExpForLevel(level)
    return { level = level, exp = data.exp or 0, maxExp = capped and 0 or (data.maxExp or needed or 0),
        gain = level - beforeLevel, capped = capped, beforeLevel = beforeLevel }
end

--- 修改指定候选并返回成长回执；真实事务和只读模拟均调用此函数。
function M.Apply(heroes, ids, player, rewards)
    local roster, before = heroes.roster, {}
    for index, id in ipairs(ids) do before[index] = getHero(roster, id).level or 1 end
    local playerBefore = player and (player.level or 1)
    if rewards.heroExp > 0 then applyHeroes(roster, ids, rewards.heroExpBatch) end
    if player and rewards.playerExp > 0 then
        player.exp = (player.exp or 0) + rewards.playerExp
        ET.autoLevelUpPlayer(player)
    end
    local heroProgress = {}
    for index, id in ipairs(ids) do
        local result = progress(getHero(roster, id), before[index], true)
        result.heroId = id
        heroProgress[index] = result
    end
    local playerProgress = player and progress(player, playerBefore, false) or nil
    return playerProgress, heroProgress
end

local function copyGrowth(data)
    return { level = data.level, exp = data.exp, maxExp = data.maxExp }
end

--- 全名册参与共鸣（包括未上阵/旁队），但只复制成长字段，不复制装备或改写输入表。
function M.Preview(heroes, ids, player, rewards)
    local roster, copies = {}, {}
    for id, hero in pairs(heroes.roster) do
        if type(hero) == "table" then
            local copy = copies[hero]
            if not copy then copy = copyGrowth(hero); copies[hero] = copy end
            roster[id] = copy
        else
            roster[id] = hero
        end
    end
    return M.Apply({ roster = roster }, ids, player and copyGrowth(player) or nil, rewards)
end

return M
