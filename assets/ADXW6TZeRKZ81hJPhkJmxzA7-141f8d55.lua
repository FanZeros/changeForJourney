------------------------------------------------------------------------
-- LootBoxSystem.lua  —— 战利品缓冲区管理（双端共享）
-- 职责: 掉落种子的合并存储、领取时生成装备
-- 数据结构: lootboxData.seeds = { {quality, level, count}, ... }
------------------------------------------------------------------------
local EquipmentSystem = require("systems.EquipmentSystem")

local LootBoxSystem = {}

--- 战利品缓冲区种子总数上限（合并计数后的总件数）
LootBoxSystem.MAX_SEEDS = 9999

--- 装备等级上限（由服务端 EquipLevelCompat 登录时设置，0=不限制）
--- 领取战利品时，如果种子 level > levelCap，则 clamp 到此值
LootBoxSystem.levelCap = 0

------------------------------------------------------------------------
-- 内部工具
------------------------------------------------------------------------

--- 计算种子总件数（所有 seed.count 之和）
---@param lootboxData table
---@return number
local function getTotalCount(lootboxData)
    local total = 0
    for _, seed in ipairs(lootboxData.seeds) do
        total = total + (seed.count or 1)
    end
    return total
end

--- 查找匹配的种子条目（同 quality + level 合并，不区分关卡来源）
---@param seeds table[]
---@param quality number
---@param level number
---@return table|nil seed, number|nil index
local function findSeed(seeds, quality, level)
    for i, seed in ipairs(seeds) do
        if seed.quality == quality and seed.level == level then
            return seed, i
        end
    end
    return nil, nil
end

--- 合并存档中同 quality+level 的旧种子条目（兼容旧存档可能按 stageId 分开的数据）
--- 同时清理遗留的 stageId 字段
---@param lootboxData table
local function consolidateSeeds(lootboxData)
    if not lootboxData or not lootboxData.seeds then return end
    local seeds = lootboxData.seeds
    -- key = "quality:level" → 首次出现的索引
    local keyMap = {}
    local merged = {}
    for _, seed in ipairs(seeds) do
        local key = seed.quality .. ":" .. seed.level
        local target = keyMap[key]
        if target then
            target.count = target.count + (seed.count or 1)
        else
            local entry = {
                quality = seed.quality,
                level   = seed.level,
                count   = seed.count or 1,
            }
            keyMap[key] = entry
            merged[#merged + 1] = entry
        end
    end
    -- 仅在实际发生合并时替换（减少不必要的写入）
    if #merged < #seeds then
        lootboxData.seeds = merged
    else
        -- 即使条目数相同，也清理遗留的 stageId 字段
        for _, seed in ipairs(seeds) do
            seed.stageId = nil
        end
    end
end

------------------------------------------------------------------------
-- 公开 API
------------------------------------------------------------------------

--- 合并旧存档中按 stageId 分开的同类种子（quality+level 相同的合并为一条）
--- 客户端和服务端在首次加载 lootbox 数据后调用
---@param lootboxData table
function LootBoxSystem.consolidateSeeds(lootboxData)
    consolidateSeeds(lootboxData)
end

--- 获取种子总件数
---@param lootboxData table
---@return number
function LootBoxSystem.getTotalCount(lootboxData)
    return getTotalCount(lootboxData)
end

--- 获取种子条目数（不同种类数）
---@param lootboxData table
---@return number
function LootBoxSystem.getEntryCount(lootboxData)
    return #lootboxData.seeds
end

--- 添加一个掉落种子（自动合并同类）
---@param lootboxData table
---@param stageId number 关卡ID
---@param quality number 品质 1-4
---@param level number 怪物等级
---@return boolean success 是否添加成功（false=缓冲区已满）
function LootBoxSystem.addSeed(lootboxData, stageId, quality, level)
    -- 检查上限
    if getTotalCount(lootboxData) >= LootBoxSystem.MAX_SEEDS then
        print("[LootBoxSystem] addSeed SKIP: buffer full (" .. LootBoxSystem.MAX_SEEDS .. ")")
        return false
    end

    local existing = findSeed(lootboxData.seeds, quality, level)
    if existing then
        existing.count = existing.count + 1
    else
        lootboxData.seeds[#lootboxData.seeds + 1] = {
            quality = quality,
            level   = level,
            count   = 1,
        }
    end
    return true
end

--- 领取一件战利品：从指定种子生成装备实例
--- 不修改背包数据，仅消费种子并返回生成的装备
---@param lootboxData table
---@param index number 种子条目索引（1-based）
---@return table|nil equip 生成的装备实例，nil=索引无效/种子为空
function LootBoxSystem.claimOne(lootboxData, index)
    local seed = lootboxData.seeds[index]
    if not seed or seed.count <= 0 then return nil end

    -- 等级兜底：确保不超过当前关卡等级上限
    local effectiveLevel = seed.level
    if LootBoxSystem.levelCap > 0 and effectiveLevel > LootBoxSystem.levelCap then
        effectiveLevel = LootBoxSystem.levelCap
    end

    -- 生成装备（此时才骰词条）
    local equip = EquipmentSystem.generateRandom(effectiveLevel, seed.quality)
    if not equip then return nil end

    -- 消费种子
    seed.count = seed.count - 1
    if seed.count <= 0 then
        table.remove(lootboxData.seeds, index)
    end

    return equip
end

--- 领取指定组的全部种子：逐一生成装备，直到该组耗尽或背包满
---@param lootboxData table
---@param index number 种子条目索引（1-based）
---@param equipData table 背包数据（用于检查容量）
---@return table[] claimed 成功领取的装备列表
---@return boolean bagFull 是否因背包满而中断
function LootBoxSystem.claimGroup(lootboxData, index, equipData)
    local seed = lootboxData.seeds[index]
    if not seed or seed.count <= 0 then return {}, false end

    local claimed = {}
    local bagFull = false

    -- 等级兜底
    local effectiveLevel = seed.level
    if LootBoxSystem.levelCap > 0 and effectiveLevel > LootBoxSystem.levelCap then
        effectiveLevel = LootBoxSystem.levelCap
    end

    while seed.count > 0 do
        if EquipmentSystem.isInventoryFull(equipData) then
            bagFull = true
            break
        end
        local equip = EquipmentSystem.generateRandom(effectiveLevel, seed.quality)
        if not equip then
            print("[LootBoxSystem] WARN: generateRandom failed in claimGroup"
                .. " lv=" .. tostring(effectiveLevel) .. " q=" .. tostring(seed.quality))
            break
        end
        local seq = EquipmentSystem.addToInventory(equipData, equip)
        equip.seq = seq
        claimed[#claimed + 1] = equip
        seed.count = seed.count - 1
    end

    -- 清理归零条目
    if seed.count <= 0 then
        table.remove(lootboxData.seeds, index)
    end

    return claimed, bagFull
end

--- 一键领取全部：逐一生成装备，直到背包满或种子耗尽
---@param lootboxData table
---@param equipData table 背包数据（用于检查容量）
---@return table[] claimed 成功领取的装备列表
---@return boolean bagFull 是否因背包满而中断
function LootBoxSystem.claimAll(lootboxData, equipData)
    local claimed = {}
    local bagFull = false
    local cap = LootBoxSystem.levelCap

    -- 从后往前遍历（避免 table.remove 导致索引跳过）
    local i = #lootboxData.seeds
    while i >= 1 do
        local seed = lootboxData.seeds[i]
        -- 等级兜底
        local effectiveLevel = seed.level
        if cap > 0 and effectiveLevel > cap then
            effectiveLevel = cap
        end
        while seed.count > 0 do
            if EquipmentSystem.isInventoryFull(equipData) then
                bagFull = true
                break
            end
            local equip = EquipmentSystem.generateRandom(effectiveLevel, seed.quality)
            if not equip then
                -- 生成失败（理论上不应发生）：跳过该种子类型，保留种子不消耗
                print("[LootBoxSystem] WARN: generateRandom failed, seed preserved"
                    .. " lv=" .. tostring(effectiveLevel) .. " q=" .. tostring(seed.quality))
                break
            end
            local seq = EquipmentSystem.addToInventory(equipData, equip)
            equip.seq = seq
            claimed[#claimed + 1] = equip
            seed.count = seed.count - 1
        end
        -- 清理归零条目
        if seed.count <= 0 then
            table.remove(lootboxData.seeds, i)
        end
        if bagFull then break end
        i = i - 1
    end

    return claimed, bagFull
end

--- 一键分解全部种子：清空所有种子，返回获得的精粹总量
--- 分解公式: 每件种子 → decBase * (1 + level * decScale)
---@param lootboxData table
---@return number totalEssence 获得的精粹总量
---@return number totalPieces  分解的装备件数
function LootBoxSystem.decomposeAll(lootboxData)
    local BlacksmithConfig = require("config.BlacksmithConfig")
    local totalEssence = 0
    local totalPieces  = 0

    for _, seed in ipairs(lootboxData.seeds) do
        local qCost = BlacksmithConfig.QUALITY_COST[seed.quality]
        if qCost then
            local level = seed.level or 1
            local perPiece = qCost.decBase * (1 + level * qCost.decScale)
            totalEssence = totalEssence + math.floor(perPiece) * seed.count
            totalPieces  = totalPieces + seed.count
        else
            print("[LootBoxSystem] WARN: decomposeAll unknown quality=" .. tostring(seed.quality))
        end
    end

    -- 清空所有种子
    lootboxData.seeds = {}

    print("[LootBoxSystem] decomposeAll: pieces=" .. totalPieces
        .. " essence=" .. totalEssence)
    return totalEssence, totalPieces
end

--- 分解指定组的种子（按索引）
--- 分解公式同 decomposeAll: 每件种子 → decBase * (1 + level * decScale)
---@param lootboxData table
---@param index number 1-based seed group index
---@return number totalEssence 获得的精粹总量
---@return number totalPieces  分解的装备件数
function LootBoxSystem.decomposeOne(lootboxData, index)
    local BlacksmithConfig = require("config.BlacksmithConfig")

    if not lootboxData.seeds or index < 1 or index > #lootboxData.seeds then
        print("[LootBoxSystem] WARN: decomposeOne invalid index=" .. tostring(index))
        return 0, 0
    end

    local seed = lootboxData.seeds[index]
    local totalEssence = 0
    local totalPieces  = 0

    local qCost = BlacksmithConfig.QUALITY_COST[seed.quality]
    if qCost then
        local level = seed.level or 1
        local perPiece = qCost.decBase * (1 + level * qCost.decScale)
        totalEssence = math.floor(perPiece) * seed.count
        totalPieces  = seed.count
    else
        print("[LootBoxSystem] WARN: decomposeOne unknown quality=" .. tostring(seed.quality))
    end

    -- 移除该组种子
    table.remove(lootboxData.seeds, index)

    print("[LootBoxSystem] decomposeOne index=" .. index
        .. " pieces=" .. totalPieces .. " essence=" .. totalEssence)
    return totalEssence, totalPieces
end

--- 获取种子摘要列表（用于客户端 UI 展示）
---@param lootboxData table
---@return table[] summary { {quality, level, count}, ... }
function LootBoxSystem.getSummary(lootboxData)
    local summary = {}
    for _, seed in ipairs(lootboxData.seeds) do
        summary[#summary + 1] = {
            quality = seed.quality,
            level   = seed.level,
            count   = seed.count,
        }
    end
    return summary
end

return LootBoxSystem
