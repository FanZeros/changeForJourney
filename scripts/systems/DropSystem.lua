------------------------------------------------------------------------
-- DropSystem.lua  —— 装备掉落系统
-- 职责: 击杀掉落概率判定、品质加权随机、首通奖励生成
-- 依赖: StageConfig, EquipmentSystem, MonsterConfig
------------------------------------------------------------------------
local EquipmentSystem = require("systems.EquipmentSystem")
local MC = require("config.MonsterConfig")
local StageConfig     = require("config.StageConfig")
local AD              = require("systems.AttributeDef")

local DropSystem = {}

--- 有效幸运值：非法/负数归零，按本队合计封顶，避免异常值污染随机区间。
---@param value number|nil
---@return number
function DropSystem.normalizeLuck(value)
    if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then return 0 end
    return math.min(value, AD.DROP_LUCK_CAP)
end

--- 从本场出战属性获取幸运快照，不借编辑队、不重建英雄、不排除本场阵亡成员。
---@param allies table[]|nil
---@return number
function DropSystem.captureTeamLuck(allies)
    local total = 0
    local seen = {}
    for _, unit in ipairs(allies or {}) do
        local heroId = tonumber(unit.heroId)
        local attrs = unit._baseSnapshot or unit.attrs
        if heroId and heroId > 0 and not seen[heroId] then
            seen[heroId] = true
            if attrs and type(attrs.get) == "function" then
                total = total + DropSystem.normalizeLuck(attrs:get(AD.DROP_LUCK))
            end
        end
    end
    return DropSystem.normalizeLuck(total)
end

--- 只接受主线来源的明确队号和已经确定的幸运值；旧调用保持零幸运。
local function getDropLuck(stageEntry, context)
    if type(context) ~= "table" or stageEntry.mode == "resource_dungeon" or stageEntry.mode == "terminal" then return 0 end
    local teamIdx = context.teamIdx
    if type(teamIdx) ~= "number" or teamIdx % 1 ~= 0 or teamIdx < 1 or teamIdx > 3 then return 0 end
    return DropSystem.normalizeLuck(context.dropLuck)
end

--- 地狱难度击杀掉落：传说/至臻装备权重倍率（仅 rollKillDrop 生效，不影响首通 fcMinQ）
local HELL_EQUIP_WEIGHT_BOOST = {
    [5] = 3.0,
    [6] = 3.0,
}

------------------------------------------------------------------------
-- 内部工具
------------------------------------------------------------------------

--- 根据关卡品质权重表加权随机选取装备品质 (1-4)，用于首通奖励
---@param qw number[] 权重数组 {q1, q2, q3, q4}（来自 stageEntry.qw）
---@return number quality 1~4
local function rollQualityByStage(qw)
    local total = 0
    for i = 1, 4 do
        total = total + (qw[i] or 0)
    end
    if total <= 0 then return 1 end

    local r = math.random(1, total)
    local acc = 0
    for i = 1, 4 do
        acc = acc + (qw[i] or 0)
        if r <= acc then
            return i
        end
    end
    return 1  -- fallback
end

--- 怪物掉落品质权重；主线、副本与离线共用难度倍率，幸运仅由调用方传入。
---@param monsterQuality number
---@param difficulty string|nil
---@param luck number|nil
---@return number[] weights
---@return number total
function DropSystem.getQualityWeights(monsterQuality, difficulty, luck)
    local qualityData = MC.QUALITY[monsterQuality] or MC.QUALITY[1]
    local dw = qualityData.dropWeights
    local isHighDiff = difficulty == StageConfig.DIFFICULTY_HELL
        or difficulty == StageConfig.DIFFICULTY_PURGATORY
        or difficulty == StageConfig.DIFFICULTY_TORMENT
        or difficulty == StageConfig.DIFFICULTY_TORMENT2
        or difficulty == StageConfig.DIFFICULTY_TORMENT3
        or difficulty == StageConfig.DIFFICULTY_TORMENT4
        or difficulty == StageConfig.DIFFICULTY_TORMENT5
        or difficulty == StageConfig.DIFFICULTY_ANNIHILATION
        or difficulty == StageConfig.DIFFICULTY_ANNIHILATION2
        or difficulty == StageConfig.DIFFICULTY_ANNIHILATION3
        or difficulty == StageConfig.DIFFICULTY_ANNIHILATION4
        or difficulty == StageConfig.DIFFICULTY_ANNIHILATION5
    local total = 0
    local weights = {}
    for i = 1, 6 do
        local w = dw[i] or 0 --[[@as number]]
        if isHighDiff and HELL_EQUIP_WEIGHT_BOOST[i] then
            ---@diagnostic disable-next-line: assign-type-mismatch
            w = w * HELL_EQUIP_WEIGHT_BOOST[i]
        end
        -- 只放大已有的高品质权重；零幸运沿用原整数抽样和 RNG 调用次数。
        if (luck or 0) > 0 then w = w * (1 + (i - 1) * luck / 500) end
        weights[i] = w
        total = total + w
    end
    return weights, total
end

--- 根据怪物品质抽样；零幸运沿用整数区间，高品质零权重不产生掉落。
---@param monsterQuality number
---@param difficulty string|nil
---@param luck number|nil
---@return number
function DropSystem.rollQualityByMonster(monsterQuality, difficulty, luck)
    local weights, total = DropSystem.getQualityWeights(monsterQuality, difficulty, luck)
    if total <= 0 then return 1 end

    local r
    if (luck or 0) > 0 then r = math.random() * total
    else r = math.random(1, total) end
    local acc = 0
    for i = 1, 6 do
        acc = acc + weights[i]
        if weights[i] > 0 and r <= acc then return i end
    end
    return 1
end

--- 从关卡怪物列表中随机抽取一个怪物品质（服务端自主决策）
--- 包含 Boss：Boss 参与品质池（权重等同 1 个普通怪位），使高难度关卡有机会掉落传说装备
---@param stageEntry StageEntry
---@return number monsterQuality 1~6
local function pickMonsterQuality(stageEntry)
    local monsters = stageEntry.monsters
    local pool = {}
    if monsters then
        for _, id in ipairs(monsters) do
            pool[#pool + 1] = id
        end
    end
    -- Boss 也加入品质池
    if stageEntry.bossId and stageEntry.bossId > 0 then
        pool[#pool + 1] = stageEntry.bossId
    end
    if #pool == 0 then return 1 end
    local monsterId = pool[math.random(1, #pool)]
    local template = MC.MONSTERS[monsterId]
    return template and template.quality or 1
end

--- 一件已命中掉落的品质分布；普通怪与Boss各占一个品质池位置。
--- 只读查询不判定是否掉装备，不消耗随机数，不包含首通最低品质。
---@param stageEntry table
---@return number[] probabilities
function DropSystem.getStageQualityProbabilities(stageEntry)
    local pool = {}
    for _, id in ipairs(stageEntry.monsters or {}) do pool[#pool + 1] = id end
    if (stageEntry.bossId or 0) > 0 then pool[#pool + 1] = stageEntry.bossId end
    if #pool == 0 then pool[1] = 0 end
    local probabilities = { 0, 0, 0, 0, 0, 0 }
    local difficulty = stageEntry.difficulty or StageConfig.getDifficulty(stageEntry.sourceStageId or stageEntry.id)
    local cap = StageConfig.getMaxDropQuality(stageEntry)
    for _, monsterId in ipairs(pool) do
        local monster = MC.MONSTERS[monsterId]
        local weights, total = DropSystem.getQualityWeights(monster and monster.quality or 1, difficulty, 0)
        if total <= 0 then probabilities[1] = probabilities[1] + 1 / #pool
        else
            for q = 1, 6 do
                local quality = math.min(q, cap)
                probabilities[quality] = probabilities[quality] + weights[q] / total / #pool
            end
        end
    end
    return probabilities
end

--- 对已确定的六品质概率抽样；只消耗一次随机数。
---@param probabilities number[]
---@return number
function DropSystem.rollQualityByProbabilities(probabilities)
    local roll = math.random()
    local cumulative = 0
    local fallback = 1
    for q = 1, 6 do
        local probability = probabilities[q] or 0
        if probability > 0 then
            fallback = q
            cumulative = cumulative + probability
            if roll < cumulative then return q end
        end
    end
    return fallback
end

------------------------------------------------------------------------
-- 公开 API
------------------------------------------------------------------------

--- 判定一次击杀是否掉落装备，装备品质由怪物品质决定
---@param stageEntry StageEntry 关卡配置条目
---@param context table|nil {teamIdx, dropLuck}，只用于主线击杀，缺省为旧规则
---@return number|nil quality 掉落装备品质 (1-6)，nil=未掉落
function DropSystem.rollKillDrop(stageEntry, context)
    local rate = stageEntry.dropRate or 0
    if rate <= 0 then
        return nil
    end

    local luck = getDropLuck(stageEntry, context)
    if luck > 0 then rate = math.min(1, rate * (1 + luck / 100)) end
    local roll = math.random()
    if roll > rate then
        return nil
    end

    -- 命中掉落：服务端随机选取一个怪物品质，再按其权重决定装备品质
    local monsterQ = pickMonsterQuality(stageEntry)
    local difficulty = StageConfig.getDifficulty(stageEntry.id)
    local quality = DropSystem.rollQualityByMonster(monsterQ, difficulty, luck)
    -- 品质上限：普通最高 4，困难 5，噩梦/地狱/炼狱/折磨(I/II/III) 6
    local maxQ = StageConfig.getMaxDropQuality(stageEntry)
    if quality > maxQ then quality = maxQ end
    print(string.format("[DropSystem] rollKillDrop: HIT roll=%.4f monsterQ=%d → equipQ=%d (cap=%d luck=%.2f)", roll, monsterQ, quality, maxQ, luck))
    return quality
end

--- 为一次击杀掉落生成装备实例
---@param stageEntry StageEntry
---@param context table|nil 主线小队幸运快照
---@return table|nil equip 装备实例，nil=未掉落
function DropSystem.generateKillDrop(stageEntry, context)
    local quality = DropSystem.rollKillDrop(stageEntry, context)
    if not quality then return nil end

    local level = stageEntry.monsterLevel or 1
    local equip = EquipmentSystem.generateRandom(level, quality)
    return equip
end

--- 为首通奖励生成装备列表
---@param stageEntry StageEntry
---@return table[] equips 装备实例数组
function DropSystem.generateFirstClearEquips(stageEntry)
    local count = stageEntry.fcEquip or 0
    local minQ  = stageEntry.fcMinQ  or 1
    local level = stageEntry.monsterLevel or 1

    local equips = {}
    for i = 1, count do
        -- 品质 = max(最低品质, 加权随机品质)
        local qw = stageEntry.qw
        local quality = minQ
        if qw and #qw > 0 then
            local rolled = rollQualityByStage(qw)
            if rolled > quality then
                quality = rolled
            end
        end
        local equip = EquipmentSystem.generateRandom(level, quality)
        if equip then
            equips[#equips + 1] = equip
        end
    end
    return equips
end

------------------------------------------------------------------------
-- 卷轴掉落
------------------------------------------------------------------------

--- 六种卷轴类型
local SCROLL_TYPES = { "weaponScroll", "offhandScroll", "armorScroll", "helmetScroll", "shoesScroll", "accessoryScroll" }

--- 随机选取一种卷轴类型
---@return string scrollType
local function randomScrollType()
    ---@diagnostic disable-next-line: return-type-mismatch
    return SCROLL_TYPES[math.random(1, #SCROLL_TYPES)]
end

--- 扫荡券统一掉率：卷轴掉率的 4 倍，最低 12%、最高 40%；只读查询不消耗随机数。
---@param scrollRate number|nil
---@return number
function DropSystem.getSweepTicketRate(scrollRate)
    return math.min(0.40, math.max(0.12, (scrollRate or 0.05) * 4))
end

--- 主线每次击杀独立判定扫荡券；资源与终焉不得借主线入口重复发券。
---@param stageEntry table|nil
---@return boolean
function DropSystem.rollSweepTicket(stageEntry)
    if stageEntry and (stageEntry.mode == "resource_dungeon" or stageEntry.mode == "terminal"
        or StageConfig.isResourceStage(stageEntry.id) or StageConfig.isTerminalTemple(stageEntry.id)) then
        return false
    end
    local rate = DropSystem.getSweepTicketRate(stageEntry and stageEntry.scrollDropRate)
    return math.random() <= rate
end

--- 判定一次击杀是否掉落卷轴
---@param stageEntry StageEntry 关卡配置条目
---@return string|nil scrollType 卷轴类型字符串，nil=未掉落
function DropSystem.rollScrollDrop(stageEntry)
    local rate = stageEntry.scrollDropRate or 0
    if rate <= 0 then return nil end

    local roll = math.random()
    if roll > rate then return nil end

    local scrollType = randomScrollType()
    print(string.format("[DropSystem] rollScrollDrop: HIT! roll=%.4f <= rate=%.4f, type=%s", roll, rate, scrollType))
    return scrollType
end

--- 为首通奖励生成卷轴（每个独立随机）
---@param stageEntry StageEntry
---@return table|nil result { scrolls={[scrollType]=count,...} }，nil=无卷轴奖励
function DropSystem.generateFirstClearScrolls(stageEntry)
    local count = stageEntry.fcScroll or 0
    if count <= 0 then return nil end

    -- 每个卷轴独立随机类型，按类型聚合数量
    local scrolls = {}
    for i = 1, count do
        local st = randomScrollType()
        scrolls[st] = (scrolls[st] or 0) + 1
    end
    local parts = {}
    for st, n in pairs(scrolls) do
        parts[#parts + 1] = st .. "x" .. n
    end
    print("[DropSystem] generateFirstClearScrolls: " .. table.concat(parts, ", ") .. " (total=" .. count .. ")")
    return { scrolls = scrolls }
end

return DropSystem
