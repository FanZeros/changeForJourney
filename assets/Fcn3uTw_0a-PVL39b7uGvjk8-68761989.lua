------------------------------------------------------------------------
-- DropSystem.lua  —— 装备掉落系统
-- 职责: 击杀掉落概率判定、品质加权随机、首通奖励生成
-- 依赖: StageConfig, EquipmentSystem, MonsterConfig
------------------------------------------------------------------------
local EquipmentSystem = require("systems.EquipmentSystem")
local MC = require("config.MonsterConfig")
local StageConfig     = require("config.StageConfig")

local DropSystem = {}

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

--- 根据怪物品质加权随机选取装备品质 (1-6)，用于击杀掉落
---@param monsterQuality number 怪物品质 1~6
---@param difficulty string|nil 关卡难度（地狱时提升 Q5/Q6 权重）
---@return number quality 1~6
local function rollQualityByMonster(monsterQuality, difficulty)
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
        local w = dw[i] or 0
        if isHighDiff and HELL_EQUIP_WEIGHT_BOOST[i] then
            ---@diagnostic disable-next-line: assign-type-mismatch
            w = w * HELL_EQUIP_WEIGHT_BOOST[i]
        end
        weights[i] = w
        total = total + w
    end
    if total <= 0 then return 1 end

    local r = math.random(1, total)
    local acc = 0
    for i = 1, 6 do
        acc = acc + weights[i]
        if r <= acc then return i end
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

------------------------------------------------------------------------
-- 公开 API
------------------------------------------------------------------------

--- 判定一次击杀是否掉落装备，装备品质由怪物品质决定
---@param stageEntry StageEntry 关卡配置条目
---@return number|nil quality 掉落装备品质 (1-5)，nil=未掉落
function DropSystem.rollKillDrop(stageEntry)
    local rate = stageEntry.dropRate or 0
    if rate <= 0 then
        return nil
    end

    local roll = math.random()
    if roll > rate then
        return nil
    end

    -- 命中掉落：服务端随机选取一个怪物品质，再按其权重决定装备品质
    local monsterQ = pickMonsterQuality(stageEntry)
    local difficulty = StageConfig.getDifficulty(stageEntry.id)
    local quality = rollQualityByMonster(monsterQ, difficulty)
    -- 品质上限：普通最高 4，困难 5，噩梦/地狱/炼狱/折磨(I/II/III) 6
    local maxQ = StageConfig.getMaxDropQuality(stageEntry)
    if quality > maxQ then quality = maxQ end
    print(string.format("[DropSystem] rollKillDrop: HIT roll=%.4f monsterQ=%d → equipQ=%d (cap=%d)", roll, monsterQ, quality, maxQ))
    return quality
end

--- 为一次击杀掉落生成装备实例
---@param stageEntry StageEntry
---@return table|nil equip 装备实例，nil=未掉落
function DropSystem.generateKillDrop(stageEntry)
    local quality = DropSystem.rollKillDrop(stageEntry)
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

--- 四种卷轴类型
local SCROLL_TYPES = { "weaponScroll", "offhandScroll", "armorScroll", "accessoryScroll" }

--- 随机选取一种卷轴类型
---@return string scrollType
local function randomScrollType()
    ---@diagnostic disable-next-line: return-type-mismatch
    return SCROLL_TYPES[math.random(1, #SCROLL_TYPES)]
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
