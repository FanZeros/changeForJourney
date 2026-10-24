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

-- 只针对新随机装备的极小至臻机会；不放开其他品质/点金进度门槛。
DropSystem.MIN_RED_PROBABILITY = 0.0001

--- 已按旧规则合并品质上限的分布加入至臻尾部，原至臻概率更高时原样保留。
--- 无随机、无原地修改；非至臻按同一比例扣回，总件数与非至臻相对构成不变。
---@param probabilities number[]
---@param sourceRed number|nil 整关旧至臻概率，缺省使用当前分布
---@return number[]
function DropSystem.withMinimumRedProbability(probabilities, sourceRed)
    local red = probabilities[6] or 0
    local reference = sourceRed == nil and red or sourceRed
    if reference >= DropSystem.MIN_RED_PROBABILITY then return probabilities end
    local adjusted = {} ---@type number[]
    -- 条件怪物分布也使用整关红率决定提升幅度，已有高难关不因低品质怪额外增红。
    local added = (DropSystem.MIN_RED_PROBABILITY - reference) / (1 - reference)
    for q = 1, 5 do adjusted[q] = (probabilities[q] or 0) * (1 - added) end
    adjusted[6] = red + (1 - red) * added
    return adjusted
end

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

--- 根据原四档关卡权重与最低品质抽样，加入极小至臻尾部，用于新首通随机装备。
---@param qw number[] 权重数组 {q1, q2, q3, q4}（来自 stageEntry.qw）
---@param minQuality number|nil
---@return number quality 1~6
local function rollQualityByStage(qw, minQuality)
    local total = 0
    for i = 1, 4 do
        total = total + (qw[i] or 0)
    end
    if total <= 0 then return minQuality or 1 end

    -- 首通仍只借原四档权重/最低品质，同一品质骰加入至臻尾部，不加额外判定。
    local probabilities = { 0, 0, 0, 0, 0, 0 } ---@type number[]
    for q = 1, 4 do
        local quality = math.max(minQuality or 1, q)
        probabilities[quality] = probabilities[quality] + (qw[q] or 0) / total
    end
    return DropSystem.rollQualityByProbabilities(DropSystem.withMinimumRedProbability(probabilities))
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

--- 先沿用原品质上限，再加入仅至臻的微小例外；不影响点金/固定品质配置。
---@param monsterQuality number
---@param difficulty string|nil
---@param luck number|nil
---@param cap number|nil
---@param sourceRed number|nil 整关旧红率；保留高于底线关的条件怪物分布
---@return number[] probabilities
function DropSystem.getMonsterQualityProbabilities(monsterQuality, difficulty, luck, cap, sourceRed)
    local weights, total = DropSystem.getQualityWeights(monsterQuality, difficulty, luck)
    local probabilities = { 0, 0, 0, 0, 0, 0 } ---@type number[]
    if total <= 0 then probabilities[1] = 1
    else
        for q = 1, 6 do
            local quality = math.min(q, cap or 6)
            probabilities[quality] = probabilities[quality] + weights[q] / total
        end
    end
    return DropSystem.withMinimumRedProbability(probabilities, sourceRed)
end

--- 一次品质随机；已有整关至臻概率足够时保留旧整数区间及幸运抽样。
---@param monsterQuality number
---@param difficulty string|nil
---@param luck number|nil
---@param cap number|nil
---@param sourceRed number|nil
---@return number
function DropSystem.rollQualityByMonster(monsterQuality, difficulty, luck, cap, sourceRed)
    local weights, total = DropSystem.getQualityWeights(monsterQuality, difficulty, luck)
    if total <= 0 then return 1 end
    local red = sourceRed
    if red == nil then red = (cap or 6) < 6 and 0 or weights[6] / total end
    if red < DropSystem.MIN_RED_PROBABILITY then
        return DropSystem.rollQualityByProbabilities(
            DropSystem.getMonsterQualityProbabilities(monsterQuality, difficulty, luck, cap, red))
    end

    local r
    if (luck or 0) > 0 then r = math.random() * total
    else r = math.random(1, total) end
    local acc = 0
    for i = 1, 6 do
        acc = acc + weights[i]
        if weights[i] > 0 and r <= acc then return math.min(i, cap or 6) end
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
---@param luck number|nil
---@param raw boolean|nil 内部旧概率查询，不包含至臻尾部
---@return number[] probabilities
function DropSystem.getStageQualityProbabilities(stageEntry, luck, raw)
    local pool = {}
    for _, id in ipairs(stageEntry.monsters or {}) do pool[#pool + 1] = id end
    if (stageEntry.bossId or 0) > 0 then pool[#pool + 1] = stageEntry.bossId end
    if #pool == 0 then pool[1] = 0 end
    local probabilities = { 0, 0, 0, 0, 0, 0 } ---@type number[]
    local difficulty = stageEntry.difficulty or StageConfig.getDifficulty(stageEntry.sourceStageId or stageEntry.id)
    local cap = StageConfig.getMaxDropQuality(stageEntry)
    for _, monsterId in ipairs(pool) do
        local monster = MC.MONSTERS[monsterId]
        local weights, total = DropSystem.getQualityWeights(monster and monster.quality or 1, difficulty, luck or 0)
        if total <= 0 then probabilities[1] = probabilities[1] + 1 / #pool
        else
            for q = 1, 6 do
                local quality = math.min(q, cap)
                probabilities[quality] = probabilities[quality] + weights[q] / total / #pool
            end
        end
    end
    if raw then return probabilities end
    return DropSystem.withMinimumRedProbability(probabilities)
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
    local maxQ = StageConfig.getMaxDropQuality(stageEntry)
    local rawProbabilities = DropSystem.getStageQualityProbabilities(stageEntry, luck, true)
    local quality = DropSystem.rollQualityByMonster(monsterQ, difficulty, luck, maxQ, rawProbabilities[6])
    if not (context and context.silent) then
        print(string.format("[DropSystem] rollKillDrop: HIT roll=%.4f monsterQ=%d → equipQ=%d (cap=%d luck=%.2f)", roll, monsterQ, quality, maxQ, luck))
    end
    return quality
end

--- 请求级命中后品质抽样：批量扫荡只跳过空击杀，不改怪物池/幸运/难度/至臻规则。
--- 返回的概率只用于独立击杀计数，闭包仍按真实掉落顺序逐件骰品质。
---@param stageEntry StageEntry
---@param context table|nil
---@return number, function
function DropSystem.createKillDropContext(stageEntry, context)
    local luck = getDropLuck(stageEntry, context)
    local rate = math.max(0, math.min(1, stageEntry.dropRate or 0))
    if luck > 0 then rate = math.min(1, math.max(0, stageEntry.dropRate or 0) * (1 + luck / 100)) end
    local difficulty = StageConfig.getDifficulty(stageEntry.id)
    local maxQ = StageConfig.getMaxDropQuality(stageEntry)
    local raw = DropSystem.getStageQualityProbabilities(stageEntry, luck, true)
    return rate, function()
        return DropSystem.rollQualityByMonster(pickMonsterQuality(stageEntry), difficulty, luck, maxQ, raw[6])
    end
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
            local rolled = rollQualityByStage(qw, minQ)
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
---@param options table|nil silent仅关闭本次日志，不改变随机判定
---@return string|nil scrollType 卷轴类型字符串，nil=未掉落
function DropSystem.rollScrollDrop(stageEntry, options)
    local rate = stageEntry.scrollDropRate or 0
    if rate <= 0 then return nil end

    local roll = math.random()
    if roll > rate then return nil end

    local scrollType = randomScrollType()
    if not (options and options.silent) then
        print(string.format("[DropSystem] rollScrollDrop: HIT! roll=%.4f <= rate=%.4f, type=%s", roll, rate, scrollType))
    end
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
