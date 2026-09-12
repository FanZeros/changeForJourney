-- ============================================================================
-- EquipmentSystem - 装备核心系统
-- 职责: 装备生成、词缀Roll、等级缩放、属性条目计算、UnitAttributes修改器桥接
-- 运行端: shared（服务端生成装备，客户端读取属性）
-- ============================================================================

local EquipmentConfig = require("config.EquipmentConfig")
local AffixConfig     = require("config.AffixConfig")
local BlacksmithConfig = require("config.BlacksmithConfig")
local AD              = require("systems.AttributeDef")

local EquipmentSystem = {}

-- ======================== 工具函数 ========================

--- 加权随机：在列表中按 weight 字段随机选一个
---@param list table[] 每项需有 weight 字段
---@param totalWeight number 总权重
---@return table 被选中的项
local function weightedRandom(list, totalWeight)
    local roll = math.random() * totalWeight
    local acc = 0
    for _, item in ipairs(list) do
        acc = acc + item.weight
        if roll <= acc then
            return item
        end
    end
    return list[#list]
end

--- 在 min~max 范围内均匀随机浮点数
---@param min number
---@param max number
---@return number
local function randomFloat(min, max)
    return min + math.random() * (max - min)
end

--- 等级缩放: scaledValue = baseValue * (1 + (level - 1) * LEVEL_SCALE)
---@param baseValue number
---@param level number
---@return number
local function scaleByLevel(baseValue, level)
    return baseValue * (1 + (level - 1) * EquipmentConfig.LEVEL_SCALE)
end

-- ======================== 品质随机 ========================

--- 在全品质范围内随机一个品质（1~MAX）
--- 任何装备的任何品质都可以掉落，不再受模板限制
---@return number 品质 ID (1-6)
function EquipmentSystem.rollQuality()
    local maxQ = #EquipmentConfig.QUALITY  -- 当前为 6

    -- 构建候选品质列表
    local candidates = {}
    for qi = 1, maxQ do
        local qDef = EquipmentConfig.QUALITY[qi]
        if qDef then
            candidates[#candidates + 1] = qi
        end
    end

    if #candidates == 0 then return 1 end

    -- 均匀随机
    return candidates[math.random(1, #candidates)]
end

-- ======================== 词缀生成 ========================

--- 在允许的品质上限内随机一个词缀品质
---@param maxQuality number 最高允许品质 tier (0=无词缀, 1=D, 2=C, 3=B, 4=A, 5=S)
---@return number 品质 ID (1-5)
local function rollAffixQuality(maxQuality)
    if maxQuality <= 0 then return 1 end

    local candidates = {}
    local totalW = 0
    for qi = 1, math.min(maxQuality, 5) do
        local qDef = AffixConfig.QUALITY[qi]
        if qDef then
            candidates[#candidates + 1] = { quality = qi, weight = qDef.weight }
            totalW = totalW + qDef.weight
        end
    end

    if #candidates == 0 then return 1 end
    local picked = weightedRandom(candidates, totalW)
    return picked.quality
end

--- 随机选取 N 条不重复的词缀
---@param count number 需要的词缀数量
---@param excludeKeys table|nil 需排除的属性 key 集合 { [key]=true }
---@return table[] 词缀模板列表
local function pickAffixes(count, excludeKeys)
    if count <= 0 then return {} end

    excludeKeys = excludeKeys or {}

    -- 构建候选列表（排除已有的 key）
    local candidates = {}
    local totalW = 0
    for _, affix in ipairs(AffixConfig.AFFIXES) do
        if not excludeKeys[affix.key] then
            candidates[#candidates + 1] = affix
            totalW = totalW + affix.weight
        end
    end

    local result = {}
    for _ = 1, count do
        if #candidates == 0 or totalW <= 0 then break end

        local picked = weightedRandom(candidates, totalW)
        result[#result + 1] = picked

        -- 移除已选，避免重复
        totalW = 0
        local newCandidates = {}
        for _, c in ipairs(candidates) do
            if c.id ~= picked.id then
                newCandidates[#newCandidates + 1] = c
                totalW = totalW + c.weight
            end
        end
        candidates = newCandidates
    end

    return result
end

--- 生成词缀实例列表
---@param count number 词缀数量
---@param maxAffixQuality number 最高品质 tier
---@param level number 装备等级
---@param excludeKeys table|nil 排除的属性 key
---@param randomStrength number|nil 品质随机属性强度比例（默认 1.0）
---@return table[] 词缀实例 { affixId, quality, value, key, name }
function EquipmentSystem.rollAffixes(count, maxAffixQuality, level, excludeKeys, randomStrength, grip)
    if count <= 0 then return {} end

    randomStrength = randomStrength or 1.0
    local gripMult = (grip == "twohand") and 2 or 1
    local templates = pickAffixes(count, excludeKeys)
    local affixes = {}

    for _, tpl in ipairs(templates) do
        local qId = rollAffixQuality(maxAffixQuality)
        local qDef = AffixConfig.QUALITY[qId]

        -- 在品质倍率区间内随机
        local mult = randomFloat(qDef.minMult, qDef.maxMult)

        -- 基础值 × 倍率 × 等级缩放 × 品质强度比例 × 双手武器倍率
        local rawValue = tpl.baseValue * mult
        local scaledValue = scaleByLevel(rawValue, level) * randomStrength * gripMult

        -- 整数类型取整
        if tpl.dataType == "int" then
            scaledValue = math.floor(scaledValue + 0.5)
        end

        affixes[#affixes + 1] = {
            affixId = tpl.id,
            quality = qId,
            value   = scaledValue,
            key     = tpl.key,
            name    = tpl.name,
        }
    end

    return affixes
end

--- 洗练石专用：保留词缀属性种类，重新 roll 品质等级和数值
--- 效果：保留词条类型（属性不变），但品质等级可变（如C→A或B→D），数值随新等级重算
---@param existingAffixes table[] 当前词缀实例列表
---@param maxAffixQuality number 最高品质 tier（受装备品质限制）
---@param level number 装备等级
---@param randomStrength number|nil 品质随机属性强度比例（默认 1.0）
---@return table[] 新词缀实例（相同 key/name/affixId，新 quality 和 value）
function EquipmentSystem.rerollAffixValues(existingAffixes, maxAffixQuality, level, randomStrength, grip)
    if not existingAffixes or #existingAffixes == 0 then return {} end

    randomStrength = randomStrength or 1.0
    local gripMult = (grip == "twohand") and 2 or 1

    -- 构建 affixId → 模板的快速查找
    local tplById = {}
    for _, affix in ipairs(AffixConfig.AFFIXES) do
        tplById[affix.id] = affix
    end

    local newAffixes = {}
    for _, old in ipairs(existingAffixes) do
        local tpl = tplById[tonumber(old.affixId) or old.affixId]
        if not tpl then
            -- 找不到模板，保留原样
            newAffixes[#newAffixes + 1] = {
                affixId = old.affixId,
                quality = old.quality,
                value   = old.value,
                key     = old.key,
                name    = old.name,
            }
        else
            -- 洗练石效果：保留词条类型，重新随机品质等级和数值
            local qId = rollAffixQuality(maxAffixQuality)
            local qDef = AffixConfig.QUALITY[qId]
            if not qDef then
                qDef = AffixConfig.QUALITY[1]
                qId = 1
            end

            local mult = randomFloat(qDef.minMult, qDef.maxMult)
            local rawValue = tpl.baseValue * mult
            local scaledValue = scaleByLevel(rawValue, level) * randomStrength * gripMult

            if tpl.dataType == "int" then
                scaledValue = math.floor(scaledValue + 0.5)
            end

            newAffixes[#newAffixes + 1] = {
                affixId = old.affixId,   -- 保留同一个词缀模板
                quality = qId,           -- 重新随机的品质等级
                value   = scaledValue,   -- 基于新等级的数值
                key     = old.key,       -- 保留属性种类
                name    = old.name,      -- 保留名称
            }
        end
    end

    return newAffixes
end

--- 复制词缀实例（洗练锁定时保留用）
---@param affix table
---@return table
local function copyAffixInstance(affix)
    return {
        affixId = affix.affixId,
        quality = affix.quality,
        value   = affix.value,
        key     = affix.key,
        name    = affix.name,
    }
end

--- 统计未锁定词缀数量（lockedSet: 1-based index → true）
---@param affixCount number
---@param lockedSet table|nil
---@return number
function EquipmentSystem.countUnlockedAffixes(affixCount, lockedSet)
    if affixCount <= 0 then return 0 end
    if not lockedSet then return affixCount end
    local locked = 0
    for i = 1, affixCount do
        if lockedSet[i] then locked = locked + 1 end
    end
    return affixCount - locked
end

--- 从已锁定词缀收集需排除的属性 key（避免未锁定槽 roll 出重复种类）
---@param affixes table[]
---@param lockedSet table|nil
---@return table
function EquipmentSystem.buildExcludeKeysFromLockedAffixes(affixes, lockedSet)
    local exclude = {}
    if not affixes or not lockedSet then return exclude end
    for i, affix in ipairs(affixes) do
        if lockedSet[i] and affix.key then
            exclude[affix.key] = true
        end
    end
    return exclude
end

--- 将 roll 结果合并回完整词缀列表（锁定槽保留原词缀）
---@param originalAffixes table[]
---@param rolledAffixes table[] 仅未锁定槽的结果，顺序对应未锁定 index
---@param lockedSet table|nil
---@return table[]
function EquipmentSystem.mergeAffixesWithLocks(originalAffixes, rolledAffixes, lockedSet)
    if not lockedSet or not next(lockedSet) then
        return rolledAffixes
    end
    local result = {}
    local rollIdx = 1
    for i, old in ipairs(originalAffixes) do
        if lockedSet[i] then
            result[#result + 1] = copyAffixInstance(old)
        else
            local rolled = rolledAffixes[rollIdx]
            if rolled then
                result[#result + 1] = rolled
                rollIdx = rollIdx + 1
            end
        end
    end
    return result
end

--- 普通洗练：仅重 roll 未锁定词缀
---@param existingAffixes table[]
---@param lockedSet table|nil
---@param maxAffixQuality number
---@param level number
---@param randomStrength number|nil
---@param grip string|nil
---@return table[]
function EquipmentSystem.rollAffixesForRefine(existingAffixes, lockedSet, maxAffixQuality, level, randomStrength, grip)
    local unlocked = EquipmentSystem.countUnlockedAffixes(#existingAffixes, lockedSet)
    if unlocked <= 0 then return existingAffixes end
    local exclude = EquipmentSystem.buildExcludeKeysFromLockedAffixes(existingAffixes, lockedSet)
    local rolled = EquipmentSystem.rollAffixes(unlocked, maxAffixQuality, level, exclude, randomStrength, grip)
    return EquipmentSystem.mergeAffixesWithLocks(existingAffixes, rolled, lockedSet)
end

--- 洗练石：保留种类，仅重 roll 未锁定词缀的品质与数值
---@param existingAffixes table[]
---@param maxAffixQuality number
---@param level number
---@param randomStrength number|nil
---@param grip string|nil
---@param lockedSet table|nil
---@return table[]
function EquipmentSystem.rerollAffixValuesWithLocks(existingAffixes, maxAffixQuality, level, randomStrength, grip, lockedSet)
    if not existingAffixes or #existingAffixes == 0 then return {} end

    randomStrength = randomStrength or 1.0
    local gripMult = (grip == "twohand") and 2 or 1

    local tplById = {}
    for _, affix in ipairs(AffixConfig.AFFIXES) do
        tplById[affix.id] = affix
    end

    local newAffixes = {}
    for i, old in ipairs(existingAffixes) do
        if lockedSet and lockedSet[i] then
            newAffixes[#newAffixes + 1] = copyAffixInstance(old)
        else
            local tpl = tplById[tonumber(old.affixId) or old.affixId]
            if not tpl then
                newAffixes[#newAffixes + 1] = copyAffixInstance(old)
            else
                local qId = rollAffixQuality(maxAffixQuality)
                local qDef = AffixConfig.QUALITY[qId]
                if not qDef then
                    qDef = AffixConfig.QUALITY[1]
                    qId = 1
                end

                local mult = randomFloat(qDef.minMult, qDef.maxMult)
                local rawValue = tpl.baseValue * mult
                local scaledValue = scaleByLevel(rawValue, level) * randomStrength * gripMult

                if tpl.dataType == "int" then
                    scaledValue = math.floor(scaledValue + 0.5)
                end

                newAffixes[#newAffixes + 1] = {
                    affixId = old.affixId,
                    quality = qId,
                    value   = scaledValue,
                    key     = old.key,
                    name    = old.name,
                }
            end
        end
    end

    return newAffixes
end

-- ======================== 基础属性重算 ========================

--- 根据模板和品质强度重新计算基础属性（点金石升阶时使用）
---@param templateId string 装备模板 ID
---@param level number 装备等级
---@param baseStrength number 品质基础属性强度比例
---@return table[] baseStats 新的 baseStats 数组 {{key, value}, ...}
function EquipmentSystem.recalcBaseStats(templateId, level, baseStrength)
    local tpl = EquipmentConfig.ITEMS[templateId]
    if not tpl then return {} end

    baseStrength = baseStrength or 1.0
    local baseStats = {}
    for _, s in ipairs(tpl.stats) do
        local key = s[1]
        local val = s[2]
        local scaled = scaleByLevel(val, level) * baseStrength

        local meta = AD.META[key]
        if meta and meta.dataType == AD.TYPE_INT then
            scaled = math.floor(scaled + 0.5)
        end

        baseStats[#baseStats + 1] = { key, scaled }
    end
    return baseStats
end

-- ======================== 装备生成 ========================

--- 生成一件装备实例
---@param templateId string 装备模板 ID（如 "W1", "O5", "A12", "C3"）
---@param level number|nil 装备等级（nil = 在 levelRange 内随机）
---@param quality number|nil 品质（nil = 全品质范围随机）
---@return table|nil 装备实例（可序列化的纯数据表）
function EquipmentSystem.generate(templateId, level, quality)
    local tpl = EquipmentConfig.ITEMS[templateId]
    if not tpl then
        print("[EquipmentSystem] template not found: " .. tostring(templateId))
        return nil
    end

    -- 等级：指定或在 levelRange 内随机。模板上限为 9999，再加硬顶防止客户端改参刷超高数值。
    local MAX_EQUIP_LEVEL = 9999
    if not level then
        local lo = tpl.levelRange and tpl.levelRange[1] or 1
        local hi = tpl.levelRange and tpl.levelRange[2] or 1
        if hi < lo then lo, hi = hi, lo end
        lo = math.max(1, math.min(MAX_EQUIP_LEVEL, math.floor(lo)))
        hi = math.max(1, math.min(MAX_EQUIP_LEVEL, math.floor(hi)))
        level = math.random(lo, hi)
    end
    level = math.max(1, math.min(MAX_EQUIP_LEVEL, math.floor(tonumber(level) or 1)))

    -- 品质：指定或在全品质范围内随机
    if not quality then
        quality = EquipmentSystem.rollQuality()
    end
    quality = math.max(1, math.min(#EquipmentConfig.QUALITY, quality))

    local qualityDef = EquipmentConfig.QUALITY[quality]

   -- 基础属性 → 等级缩放 → 品质强度加成
   local baseStrength = qualityDef.baseStrength or 1.0
   local baseStats = {}
   for _, s in ipairs(tpl.stats) do
       local key = s[1]
       local val = s[2]
       local scaled = scaleByLevel(val, level) * baseStrength

       -- 整数属性取整
       local meta = AD.META[key]
       if meta and meta.dataType == AD.TYPE_INT then
           scaled = math.floor(scaled + 0.5)
       end

       baseStats[#baseStats + 1] = { key, scaled }
   end

   -- 词缀（应用品质随机属性强度比例，双手武器×2）
    local affixCount = qualityDef.affixCount or 0
    local maxAffixQ  = qualityDef.maxAffixQuality or 0
   local randomStrength = qualityDef.randomStrength or 1.0
    local affixes = EquipmentSystem.rollAffixes(affixCount, maxAffixQ, level, {}, randomStrength, tpl.grip)

    -- 构造装备实例（纯数据，可 JSON 序列化）
    local equip = {
        templateId = templateId,
        name       = tpl.name,
        type       = tpl.type,
        slot       = tpl.slot,
        grip       = tpl.grip,
        level      = level,
        quality    = quality,
        baseStats  = baseStats,
        affixes    = affixes,
    }

    return equip
end

--- 根据槽位随机生成装备
---@param slot string "weapon"/"offhand"/"armor"/"accessory"
---@param level number
---@param quality number|nil
---@return table|nil
function EquipmentSystem.generateBySlot(slot, level, quality)
    local pool = EquipmentConfig.BY_SLOT[slot]
    if not pool or #pool == 0 then return nil end

    -- 过滤等级匹配的模板
    local candidates = {}
    for _, tid in ipairs(pool) do
        local tpl = EquipmentConfig.ITEMS[tid]
        if tpl and level >= tpl.levelRange[1] and level <= tpl.levelRange[2] then
            candidates[#candidates + 1] = tid
        end
    end

    if #candidates == 0 then
        -- 无精确匹配时，从全部模板中随机
        candidates = pool
    end

    local tid = candidates[math.random(1, #candidates)]
    return EquipmentSystem.generate(tid, level, quality)
end

--- 随机生成任意装备
---@param level number
---@param quality number|nil
---@return table|nil
function EquipmentSystem.generateRandom(level, quality)
    local slots = EquipmentConfig.SLOTS
    local slot = slots[math.random(1, #slots)]
    return EquipmentSystem.generateBySlot(slot, level, quality)
end

-- ======================== 槽位强化加成 ========================

local BlacksmithConfig = require("config.BlacksmithConfig")

--- 计算指定槽位的强化加成倍率
--- 双手武器同时享受主手(weapon) + 副手(offhand)加成，但各只享受 50%
---@param slotEnhanceData table|nil slotEnhance 模块数据 { levels = { [partySlot] = { [equipSlot] = lv } } }
---@param partySlot number 出战槽位索引 (1~5)
---@param equipSlot string 装备位置 ("weapon"/"offhand"/"armor"/"accessory")
---@param grip string|nil 装备握持类型 ("onehand"/"twohand"/nil)
---@return number 加成百分比（如 0.05 = 5%）
function EquipmentSystem.calcSlotBoost(slotEnhanceData, partySlot, equipSlot, grip)
    if not slotEnhanceData or not slotEnhanceData.levels then return 0 end
    local partyLevels = slotEnhanceData.levels[partySlot]
    if not partyLevels then return 0 end

    if grip == "twohand" then
        -- 双手武器：主手槽位 50% + 副手槽位 50%
        local weaponLv  = partyLevels["weapon"]  or 0
        local offhandLv = partyLevels["offhand"] or 0
        local weaponBoost  = BlacksmithConfig.getEnhanceBoost(weaponLv)
        local offhandBoost = BlacksmithConfig.getEnhanceBoost(offhandLv)
        return weaponBoost * 0.5 + offhandBoost * 0.5
    else
        local lv = partyLevels[equipSlot] or 0
        return BlacksmithConfig.getEnhanceBoost(lv)
    end
end

--- 通过 deployed 数组反查 heroId 所在的 partySlot 索引
---@param deployed table 出战英雄 ID 数组 { heroId1, heroId2, ... }
---@param heroId number
---@return number|nil partySlot (1~5) 或 nil（未出战）
function EquipmentSystem.findPartySlot(deployed, heroId)
    if not deployed then return nil end
    for i, id in ipairs(deployed) do
        if id == heroId then return i end
    end
    return nil
end

-- ======================== 属性计算 ========================

--- 计算装备实例的属性修改器条目列表
--- 返回值格式与 UnitAttributes:addModifier(id, entries) 的 entries 参数一致
---@param equip table 装备实例
---@param slotBoost number|nil 槽位强化加成倍率（由 calcSlotBoost 计算，0 表示无加成）
---@return table[] entries { { key=string, flat=number }, ... }
function EquipmentSystem.computeModifierEntries(equip, slotBoost)
    local entries = {}
    local boost = slotBoost or 0

    -- 基础属性（仅第一条受槽位强化加成：val * (1 + boost)）
    local baseStats = equip.baseStats or {}
    for i, s in ipairs(baseStats) do
        local key = s[1]
        local val = s[2]

        -- 只有第一条基础属性受强化加成
        if i == 1 and boost > 0 then
            val = val * (1 + boost)
        end

        -- 特殊处理：攻击间隔取负（降低间隔 = 增益）
        if key == "atkInterval" then
            val = -val
        end

        entries[#entries + 1] = { key = key, flat = val }
    end

    -- 词缀属性
    for _, affix in ipairs(equip.affixes or {}) do
        entries[#entries + 1] = { key = affix.key, flat = affix.value }
    end

    return entries
end

--- 为装备生成修改器 ID
---@param seq number 装备序列号（背包中的唯一 ID）
---@return string
function EquipmentSystem.modifierId(seq)
    return "equip_" .. tostring(seq)
end

--- 将装备属性应用到 UnitAttributes
---@param unitAttrs table UnitAttributes 实例
---@param equip table 装备实例
---@param seq number 装备序列号
---@param slotBoost number|nil 槽位强化加成（由 calcSlotBoost 计算）
function EquipmentSystem.applyToUnit(unitAttrs, equip, seq, slotBoost)
    local entries = EquipmentSystem.computeModifierEntries(equip, slotBoost)
    unitAttrs:addModifier(EquipmentSystem.modifierId(seq), entries)
end

--- 从 UnitAttributes 移除装备属性
---@param unitAttrs table UnitAttributes 实例
---@param seq number 装备序列号
function EquipmentSystem.removeFromUnit(unitAttrs, seq)
    unitAttrs:removeModifier(EquipmentSystem.modifierId(seq))
end

-- ======================== 背包操作 ========================

--- 背包容量上限（200 件 × ~180B/件 dehydrated ≈ 36KB，安全低于 50KB 分片阈值）
EquipmentSystem.MAX_INVENTORY = 200

--- 获取背包当前装备数量
---@param equipData table 玩家装备模块数据
---@return number
function EquipmentSystem.getInventoryCount(equipData)
    local count = 0
    for _ in pairs(equipData.inventory) do
        count = count + 1
    end
    return count
end

--- 检查背包是否已满
---@param equipData table
---@return boolean true=已满
function EquipmentSystem.isInventoryFull(equipData)
    return EquipmentSystem.getInventoryCount(equipData) >= EquipmentSystem.MAX_INVENTORY
end

--- 向玩家背包添加装备
---@param equipData table 玩家装备模块数据 (SaveManager.getTable(uid, "equipment"))
---@param equip table 装备实例
---@return number seq 分配的序列号
function EquipmentSystem.addToInventory(equipData, equip)
    local seq = (equipData.nextSeq or 1)
    equipData.nextSeq = seq + 1

    equip.seq = seq
    equipData.inventory[tostring(seq)] = equip

    return seq
end

--- 从背包移除装备
---@param equipData table
---@param seq number
---@return table|nil 被移除的装备
function EquipmentSystem.removeFromInventory(equipData, seq)
    local key = tostring(seq)
    local equip = equipData.inventory[key]
    if equip then
        equipData.inventory[key] = nil
    end
    return equip
end

--- 获取背包中的装备
---@param equipData table
---@param seq number
---@return table|nil
function EquipmentSystem.getFromInventory(equipData, seq)
    return equipData.inventory[tostring(seq)]
end

-- ======================== 数据瘦身（存储优化） ========================

-- 构建 affixId → affix 模板的快速查找表（兼容 cjson 字符串 id）
local _affixById = nil
local function getAffixById()
    if not _affixById then
        _affixById = {}
        for _, affix in ipairs(AffixConfig.AFFIXES) do
            _affixById[affix.id] = affix
            _affixById[tostring(affix.id)] = affix
        end
        for _, affix in ipairs(AffixConfig.CORRUPT_AFFIXES or {}) do
            _affixById[affix.id] = affix
            _affixById[tostring(affix.id)] = affix
        end
    end
    return _affixById
end

--- 解析词缀数值（兼容字符串 / cjson null 等异常存储）
---@param value any
---@return number|nil
function EquipmentSystem.normalizeAffixNumericValue(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end

--- 魔化词条数值：仅基础值 × 等级缩放 × 双手倍率，不含 D~S / 装备品质 randomStrength
---@param tplAffix table
---@param equip table|nil
---@return number
function EquipmentSystem.calcCorruptAffixValue(tplAffix, equip)
    if not tplAffix then return 0 end
    local level = math.max(1, tonumber(equip and equip.level) or 1)
    local levelScale = 1 + (level - 1) * (EquipmentConfig.LEVEL_SCALE or 0)
    local grip = equip and equip.grip or nil
    if not grip and equip and equip.templateId then
        local itemTpl = EquipmentConfig.ITEMS[equip.templateId]
        grip = itemTpl and itemTpl.grip
    end
    local gripMult = (grip == "twohand") and 2 or 1
    local value = (tonumber(tplAffix.baseValue) or 0) * levelScale * gripMult
    if tplAffix.dataType == "int" then
        value = math.floor(value + 0.5)
    end
    return value
end

--- 词缀 value 缺失时按模板 + 品质区间中点估算（旧档/传输异常兜底）
---@param tplAffix table
---@param affixQuality number
---@param equipLevel number
---@param equipQuality number
---@param grip string|nil
---@return number
local function estimateAffixValue(tplAffix, affixQuality, equipLevel, equipQuality, grip)
    if AffixConfig.isCorruptAffix(tplAffix) then
        return EquipmentSystem.calcCorruptAffixValue(tplAffix, {
            level = equipLevel,
            grip = grip,
            quality = equipQuality,
        })
    end
    local qDef = AffixConfig.QUALITY[affixQuality or 1] or AffixConfig.QUALITY[1]
    local eqQDef = EquipmentConfig.QUALITY[equipQuality or 1]
    local randomStrength = eqQDef and eqQDef.randomStrength or 1.0
    local gripMult = (grip == "twohand") and 2 or 1
    local mult = (qDef.minMult + qDef.maxMult) / 2
    local rawValue = tplAffix.baseValue * mult
    local scaledValue = scaleByLevel(rawValue, equipLevel or 1) * randomStrength * gripMult
    if tplAffix.dataType == "int" then
        scaledValue = math.floor(scaledValue + 0.5)
    end
    return scaledValue
end

--- 确保词缀实例含可用数值（hydrate / UI 展示前调用）
---@param affix table
---@param equip table
function EquipmentSystem.ensureAffixValue(affix, equip)
    if not affix then return end
    local affixId = tonumber(affix.affixId) or affix.affixId
    local tplAffix = affixId and getAffixById()[affixId] or nil
    -- 魔化词条：强制回正，清除历史错误写入的 C~S 品质增幅
    if AffixConfig.isCorruptAffix(affix) or (tplAffix and AffixConfig.isCorruptAffix(tplAffix)) then
        tplAffix = tplAffix or getAffixById()[affixId]
        if tplAffix then
            affix.affixId = tonumber(affix.affixId) or affix.affixId
            affix.key = tplAffix.key
            affix.name = tplAffix.name
            affix.quality = 0
            affix.value = EquipmentSystem.calcCorruptAffixValue(tplAffix, equip)
        end
        return
    end
    local numeric = EquipmentSystem.normalizeAffixNumericValue(affix.value)
    if numeric ~= nil then
        affix.value = numeric
        return
    end
    if not tplAffix then return end
    affix.affixId = tonumber(affix.affixId) or affix.affixId
    affix.key = affix.key or tplAffix.key
    affix.name = affix.name or tplAffix.name
    affix.value = estimateAffixValue(
        tplAffix, affix.quality, equip.level, equip.quality, equip.grip)
end

--- 从旧版 corruptOriginalAffixes 快照推导紧凑 revert（加载/存盘时一次性迁移）
---@param equip table
---@return boolean migrated
function EquipmentSystem.migrateLegacyCorruptSnapshot(equip)
    if not equip or not equip.corruptOriginalAffixes then return false end
    if equip.corruptRevert then
        equip.corruptOriginalAffixes = nil
        equip.corruptOriginalBaseMult = nil
        return true
    end

    local orig = equip.corruptOriginalAffixes
    local cur = equip.affixes or {}
    local patches = {}
    local affixCount = #orig
    for i = 1, affixCount do
        local ov = tonumber(orig[i] and orig[i].value) or 0
        local cv = cur[i] and tonumber(cur[i].value) or ov
        if math.abs(cv - ov) > 0.0001 then
            patches[#patches + 1] = { "s", i, ov }
        end
    end
    for _ = affixCount + 1, #cur do
        patches[#patches + 1] = { "a" }
    end

    local baseMult = tonumber(equip.corruptOriginalBaseMult)
    if baseMult == 1 then baseMult = nil end

    equip.corruptRevert = {
        baseMult = baseMult,
        affixCount = affixCount,
        patches = patches,
    }
    equip.corruptOriginalAffixes = nil
    equip.corruptOriginalBaseMult = nil
    return true
end

--- 规范化 corruptRevert 存档结构
---@param equip table
function EquipmentSystem.normalizeCorruptRevert(equip)
    if not equip or not equip.corruptRevert then return end
    local rev = equip.corruptRevert
    local baseMult = tonumber(rev.baseMult)
    if baseMult == 1 then baseMult = nil end
    rev.baseMult = baseMult
    rev.affixCount = math.max(0, math.floor(tonumber(rev.affixCount) or 0))
    if not rev.patches then
        rev.patches = {}
    end
end

--- 水合装备实例：从 templateId 和 affixId 还原可派生字段
--- 用于 onLoad 后将精简存储数据恢复为完整内存对象
---@param equip table 装备实例（可能缺少 name/type/slot/grip 和词缀 key/name）
---@return table 同一 equip 引用（原地修改）
function EquipmentSystem.hydrate(equip)
    if not equip or not equip.templateId then return equip end

    -- 夹紧历史脏数据：客户端改参曾写入超高等级（如 9999999）
    local MAX_EQUIP_LEVEL = 9999
    local lv = tonumber(equip.level) or 1
    local clamped = math.max(1, math.min(MAX_EQUIP_LEVEL, math.floor(lv)))
    if clamped ~= lv then
        equip.level = clamped
        equip.baseStats = nil  -- 强制按合法等级重算
    else
        equip.level = clamped
    end

    if equip.refineCount ~= nil then
        equip.refineCount = BlacksmithConfig.clampRefineCount(equip.refineCount)
    end
    if equip.corruptCount ~= nil then
        equip.corruptCount = math.max(0, math.min(3, math.floor(tonumber(equip.corruptCount) or 0)))
        if equip.corruptCount <= 0 then
            equip.corruptCount = nil
        end
    end
    if equip.corruptBaseMult ~= nil then
        equip.corruptBaseMult = tonumber(equip.corruptBaseMult) or nil
    end
    EquipmentSystem.normalizeCorruptRevert(equip)
    EquipmentSystem.migrateLegacyCorruptSnapshot(equip)

    -- 从模板还原装备基础属性
    local tpl = EquipmentConfig.ITEMS[equip.templateId]
    if tpl then
        equip.name = tpl.name
        equip.type = tpl.type
        equip.slot = tpl.slot
        equip.grip = tpl.grip

        -- 重算 baseStats（从 templateId+level+quality+腐化基础倍率确定性推导）
        if not equip.baseStats then
            local qualityDef = EquipmentConfig.QUALITY[equip.quality]
            local baseStrength = qualityDef and qualityDef.baseStrength or 1.0
            if equip.corruptBaseMult and equip.corruptBaseMult ~= 1 then
                baseStrength = baseStrength * equip.corruptBaseMult
            end
            local baseStats = {}
            for _, s in ipairs(tpl.stats) do
                local key = s[1]
                local val = s[2]
                local scaled = scaleByLevel(val, equip.level or 1) * baseStrength
                local meta = AD.META[key]
                if meta and meta.dataType == AD.TYPE_INT then
                    scaled = math.floor(scaled + 0.5)
                end
                baseStats[#baseStats + 1] = { key, scaled }
            end
            equip.baseStats = baseStats
        end
    end

    -- 从词缀模板还原 key/name，并补齐缺失 value
    if equip.affixes then
        local affixById = getAffixById()
        for _, affix in ipairs(equip.affixes) do
            local affixId = tonumber(affix.affixId) or affix.affixId
            affix.affixId = affixId
            local tplAffix = affixById[affixId]
            if tplAffix then
                affix.key  = tplAffix.key
                affix.name = tplAffix.name
            end
            EquipmentSystem.ensureAffixValue(affix, equip)
        end
    end

    return equip
end

--- 脱水装备实例：去除可派生字段，返回精简副本用于持久化
--- 不修改原对象，返回新 table
---@param equip table|nil 完整装备实例
---@return table|nil 精简副本（无 name/type/slot/grip，词缀无 key/name）
function EquipmentSystem.dehydrate(equip)
    if not equip then return equip end

    local MAX_EQUIP_LEVEL = 9999
    local persistLevel = math.max(1, math.min(MAX_EQUIP_LEVEL, math.floor(tonumber(equip.level) or 1)))
    local lean = {
        templateId = equip.templateId,
        level      = persistLevel,
        quality    = equip.quality,
        locked     = equip.locked or nil,  -- 锁定状态需持久化（false/nil 时省略，保持精简）
        corruptCount = (equip.corruptCount and equip.corruptCount > 0) and equip.corruptCount or nil,
        corruptBaseMult = (equip.corruptBaseMult and equip.corruptBaseMult ~= 1) and equip.corruptBaseMult or nil,
        -- baseStats 省略：可从 templateId+level+quality+腐化基础倍率确定性推导，hydrate 时重算
    }

    local rev = equip.corruptRevert
    if not rev and equip.corruptOriginalAffixes and (equip.corruptCount or 0) > 0 then
        local legacy = {
            affixes = equip.affixes,
            corruptOriginalAffixes = equip.corruptOriginalAffixes,
            corruptOriginalBaseMult = equip.corruptOriginalBaseMult,
        }
        EquipmentSystem.migrateLegacyCorruptSnapshot(legacy)
        rev = legacy.corruptRevert
    end
    if rev and (equip.corruptCount and equip.corruptCount > 0) then
        lean.corruptRevert = {
            baseMult = rev.baseMult,
            affixCount = rev.affixCount,
            patches = rev.patches or {},
        }
    end

    local refineCount = BlacksmithConfig.clampRefineCount(equip.refineCount)
    if refineCount > 0 then
        lean.refineCount = refineCount
    end

    -- 词缀精简：只保留 affixId, quality, value
    if equip.affixes then
        local leanAffixes = {}
        for i, affix in ipairs(equip.affixes) do
            leanAffixes[i] = {
                affixId = affix.affixId,
                quality = affix.quality,
                value   = affix.value,
            }
        end
        lean.affixes = leanAffixes
    end

    return lean
end

--- 批量脱水整个 inventory 表，返回精简副本
---@param inventory table { [seq] = equip }
---@return table { [seq] = leanEquip }
function EquipmentSystem.dehydrateInventory(inventory)
    if not inventory then return {} end
    local lean = {}
    for seq, equip in pairs(inventory) do
        lean[tostring(seq)] = EquipmentSystem.dehydrate(equip)
    end
    return lean
end

--- 批量水合整个 inventory 表（原地修改）
---@param inventory table { [seq] = equip }
function EquipmentSystem.hydrateInventory(inventory)
    if not inventory then return end
    for seqStr, equip in pairs(inventory) do
        equip.seq = tonumber(seqStr) or equip.seq
        EquipmentSystem.hydrate(equip)
    end
end

-- ======================== 装备详情文本 ========================

--- 生成装备属性摘要文本（供调试/日志用）
---@param equip table 装备实例
---@return string
function EquipmentSystem.summary(equip)
    local qualityDef = EquipmentConfig.QUALITY[equip.quality]
    local qualityName = qualityDef and qualityDef.name or "?"

    local parts = {
        string.format("[%s] %s Lv.%d (%s)", qualityName, equip.name, equip.level, equip.slot),
    }

    -- 基础属性
    for _, s in ipairs(equip.baseStats or {}) do
        local meta = AD.META[s[1]]
        local name = meta and meta.name or s[1]
        parts[#parts + 1] = string.format("  %s: %.2f", name, s[2])
    end

    -- 词缀
    for _, affix in ipairs(equip.affixes or {}) do
        local qDef = AffixConfig.QUALITY[affix.quality]
        local qName = qDef and qDef.name or "?"
        parts[#parts + 1] = string.format("  [%s] %s: %.2f", qName, affix.name, affix.value)
    end

    return table.concat(parts, "\n")
end

return EquipmentSystem
