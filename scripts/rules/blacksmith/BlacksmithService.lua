---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- BlacksmithService - 铁匠铺业务逻辑
-- 职责: 装备升阶、洗练、替换词缀、分解
-- 层级: server/blacksmith  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM              = require("rules.character.PlayerDataManager")
local EquipmentSystem  = require("systems.EquipmentSystem")
local EquipmentConfig  = require("config.EquipmentConfig")
local AffixConfig      = require("config.AffixConfig")
local BlacksmithConfig = require("config.BlacksmithConfig")
local ExpTable         = require("config.ExpTable")
local TaskService      = require("rules.task.TaskService")
local StageConfig      = require("config.StageConfig")
local AD               = require("systems.AttributeDef")

local QUALITY_COST  = BlacksmithConfig.QUALITY_COST

local BlacksmithService = {}

-- 服务端洗练待定状态 pendingRefines[uid][seqStr] = { affixes = {...} }
local pendingRefines = {}

local SLOT_SCROLL_MAP = BlacksmithConfig.SLOT_SCROLL_MAP
local MAX_ENHANCE_LV  = BlacksmithConfig.MAX_ENHANCE_LEVEL

--- 升阶上限 = 远征等级，表本身另有封顶
---@param uid number
---@return number
local function getEnhanceCap(uid)
    local playerData = PDM.GetModule(uid, "player")
    local playerLevel = playerData and (playerData.level or 1) or 1
    return ExpTable.getEnhanceLevelCap(playerLevel)
end

-- ======================== 装备升阶（跟装备走，不绑角色） ========================

local function findEquip(equipData, seq)
    if not equipData or not equipData.inventory or not seq then return nil end
    local key = tostring(seq)
    return equipData.inventory[key] or equipData.inventory[seq]
end

local function rollAscendAffixes(equip, fromLevel, toLevel)
    EquipmentSystem.migrateLegacyCorruptSnapshot(equip)
    local gained = {}
    local multUps = 0
    local affixes = equip.affixes or {}
    local normalCount = 0
    local exclude = {}
    for _, affix in ipairs(affixes) do
        if not AffixConfig.isCorruptAffix(affix) then normalCount = normalCount + 1 end
        if affix.key then exclude[affix.key] = true end
    end
    local qDef = EquipmentConfig.QUALITY[equip.quality]
    -- 每阶固定副词条由EquipmentSystem按升阶等级派生，随机词条不再写入新ascBonus。
    for level = fromLevel + 1, toLevel do
        if level % BlacksmithConfig.ASCEND_AFFIX_INTERVAL == 0 then
            if normalCount < BlacksmithConfig.ASCEND_NORMAL_AFFIX_LIMIT then
                local rolled = EquipmentSystem.rollAffixes(1,
                    math.max(1, qDef.maxAffixQuality or 0), equip.level or 1,
                    exclude, qDef.randomStrength or 1.0, equip.grip)
                if rolled[1] then
                    local affix = rolled[1]
                    local rev = equip.corruptRevert
                    if rev then
                        -- 腐化新增词条留在尾部；升阶词条插入净化保留段。
                        local insertAt = math.min(#affixes + 1, rev.affixCount + 1)
                        table.insert(affixes, insertAt, affix)
                        for _, patch in ipairs(rev.patches or {}) do
                            if patch[1] == "s" and patch[2] >= insertAt then
                                patch[2] = patch[2] + 1
                            end
                        end
                        rev.affixCount = rev.affixCount + 1
                    else
                        affixes[#affixes + 1] = affix
                    end
                    gained[#gained + 1] = affix
                    normalCount = normalCount + 1
                    exclude[affix.key] = true
                end
            else
                -- 普通词条已满：里程碑改为栏位倍率升级（洗练不丢）
                multUps = multUps + 1
            end
        end
    end
    if multUps > 0 then
        local step = BlacksmithConfig.ASCEND_AFFIX_MULT_STEP or 0.10
        local cur = tonumber(equip.affixMult) or 1
        local nextMult = math.floor((cur + step * multUps) * 1000 + 0.5) / 1000
        equip.affixMult = nextMult
    end
    equip.affixes = affixes
    return gained, multUps
end

--- 按 seq 升 1 阶。消耗为原强化表的 60%。
---@param uid number
---@param seq number
---@return boolean ok, string? err, table? result
function BlacksmithService.AscendEquip(uid, seq)
    seq = tonumber(seq)
    local equipData = PDM.GetModule(uid, "equipment")
    local currency = PDM.GetModule(uid, "currency")
    if not equipData or not currency then return false, "数据未加载" end
    local equip = findEquip(equipData, seq)
    if not equip then return false, "装备不存在" end
    EquipmentSystem.hydrate(equip)
    local scrollField = SLOT_SCROLL_MAP[equip.slot]
    if not scrollField then return false, "无效的装备位置" end

    local currentLv = EquipmentSystem.getAscendLevel(equip)
    local cap = getEnhanceCap(uid)
    if currentLv >= cap then
        return false, "升阶已达当前远征等级上限（" .. cap .. "）"
    end
    if currentLv >= MAX_ENHANCE_LV then
        return false, "已达最大升阶"
    end
    local nextLv = currentLv + 1
    local cost = BlacksmithConfig.getAscendCost(nextLv)
    if not cost then return false, "升阶配置异常" end
    if (currency.gold or 0) < cost.gold then return false, "金币不足" end
    if (currency[scrollField] or 0) < cost.scroll then return false, "卷轴不足" end

    currency.gold = currency.gold - cost.gold
    currency[scrollField] = currency[scrollField] - cost.scroll
    equip.ascendLevel = nextLv
    equip.enhanceLevel = nextLv
    local gainedAffixes, multUps = rollAscendAffixes(equip, currentLv, nextLv)
    if pendingRefines[uid] then pendingRefines[uid][tostring(seq)] = nil end
    PDM.MarkDirty(uid, "currency")
    PDM.MarkDirty(uid, "equipment")
    TaskService.UpdateProgress(uid, "enhance", 1)
    print("[BlacksmithService] ASCEND uid=" .. tostring(uid)
        .. " seq=" .. tostring(seq) .. " lv=" .. nextLv
        .. " gold=-" .. cost.gold .. " " .. scrollField .. "=-" .. cost.scroll)
    return true, nil, {
        enhanceOutcome = "success",
        seq = seq,
        newLevel = nextLv,
        ascendLevel = nextLv,
        gainedAffixes = gainedAffixes,
        multUps = multUps,
        affixMult = equip.affixMult,
        affixes = equip.affixes,
    }
end

--- 升到目标阶（含），按 60% 消耗逐级扣。
function BlacksmithService.AscendEquipToLevel(uid, seq, targetLevel)
    seq = tonumber(seq)
    targetLevel = tonumber(targetLevel)
    local equipData = PDM.GetModule(uid, "equipment")
    local currency = PDM.GetModule(uid, "currency")
    if not equipData or not currency then return false, "数据未加载" end
    local equip = findEquip(equipData, seq)
    if not equip then return false, "装备不存在" end
    EquipmentSystem.hydrate(equip)
    local scrollField = SLOT_SCROLL_MAP[equip.slot]
    if not scrollField then return false, "无效的装备位置" end
    local currentLv = EquipmentSystem.getAscendLevel(equip)
    local cap = math.min(getEnhanceCap(uid), MAX_ENHANCE_LV)
    if not targetLevel or targetLevel <= currentLv or targetLevel > cap then
        return false, "无效的目标升阶"
    end
    local totalGold, totalScroll = 0, 0
    for lv = currentLv + 1, targetLevel do
        local cost = BlacksmithConfig.getAscendCost(lv)
        if not cost then return false, "升阶配置异常" end
        totalGold = totalGold + cost.gold
        totalScroll = totalScroll + cost.scroll
    end
    if (currency.gold or 0) < totalGold then return false, "金币不足" end
    if (currency[scrollField] or 0) < totalScroll then return false, "卷轴不足" end
    currency.gold = currency.gold - totalGold
    currency[scrollField] = currency[scrollField] - totalScroll
    equip.ascendLevel = targetLevel
    equip.enhanceLevel = targetLevel
    local gainedAffixes, multUps = rollAscendAffixes(equip, currentLv, targetLevel)
    if pendingRefines[uid] then pendingRefines[uid][tostring(seq)] = nil end
    PDM.MarkDirty(uid, "currency")
    PDM.MarkDirty(uid, "equipment")
    TaskService.UpdateProgress(uid, "enhance", targetLevel - currentLv)
    print("[BlacksmithService] ASCEND_MAX uid=" .. tostring(uid)
        .. " seq=" .. tostring(seq) .. " lv " .. currentLv .. "→" .. targetLevel
        .. " gold=-" .. totalGold .. " scroll=-" .. totalScroll)
    return true, nil, {
        enhanceOutcome = "success",
        seq = seq,
        newLevel = targetLevel,
        ascendLevel = targetLevel,
        levelsGained = targetLevel - currentLv,
        gainedAffixes = gainedAffixes,
        multUps = multUps,
        affixMult = equip.affixMult,
        affixes = equip.affixes,
    }
end

-- ======================== 洗练装备 ========================

-- 额外资源定义
-- 洗练石: "洗练时保留词缀属性种类不变，重新随机品质等级和数值（可跨等级变化）"
-- 点金石: "洗练时使用可将装备提品，最高提到史诗品质"
local EXTRA_RES_DEFS = {
    enhanceStone = { field = "enhanceStone", cost = 1, name = "洗练石" },
    destroyStone = { field = "destroyStone", cost = nil, name = "点金石" },  -- cost 动态计算：当前品质即为消耗数
    corruptStone = { field = "corruptStone", cost = 1, name = "腐化石" },
    sacredStone = { field = "sacredStone", cost = 1, name = "神圣石" },
}

local MAX_CORRUPT_COUNT = 3
-- 腐化后仍可洗练：精粹消耗 ×2（构筑模型 2026-09-30，原硬禁已取消）
local CORRUPTED_ESSENCE_MULT = 2
-- 腐化石：普通词条转同类型魔化词条时的数值倍率
local CORRUPT_CONVERT_VALUE_MULT = 1.8
-- 腐化石：每层腐化对装备基础属性的倍率（诅咒，可被神圣石逐层洗除）
local CORRUPT_LAYER_BASE_PENALTY = 0.90

local function getCorruptCount(equip)
    return math.max(0, math.floor(tonumber(equip.corruptCount) or 0))
end

--- 点金石后期出口：从普通（非魔化）词缀中随机选一条品级可提升的（quality < 5）
---@param affixes table[]
---@return number|nil index
local function pickUpgradableAffix(affixes)
    local candidates = {}
    for i, affix in ipairs(affixes or {}) do
        if not AffixConfig.isCorruptAffix(affix) and (tonumber(affix.quality) or 1) < 5 then
            candidates[#candidates + 1] = i
        end
    end
    if #candidates == 0 then return nil end
    return candidates[math.random(1, #candidates)]
end

--- 腐化石转换：从普通（非魔化）词缀中随机选一条可转换的
---@param affixes table[]
---@return number|nil index, table|nil corruptTpl
local function pickConvertibleAffix(affixes)
    local candidates = {}
    for i, affix in ipairs(affixes or {}) do
        if not AffixConfig.isCorruptAffix(affix) then
            local corruptKey = AffixConfig.NORMAL_TO_CORRUPT_KEY[affix.key]
            if corruptKey and AffixConfig.BY_KEY[corruptKey] then
                candidates[#candidates + 1] = i
            end
        end
    end
    if #candidates == 0 then return nil, nil end
    local idx = candidates[math.random(1, #candidates)]
    return idx, AffixConfig.BY_KEY[AffixConfig.NORMAL_TO_CORRUPT_KEY[affixes[idx].key]]
end

--- 腐化石转换：把指定普通词缀替换为同类型魔化词条（数值 = 原数值 ×1.8，按模板口径重算后取高）
---@param affix table 原普通词缀
---@param corruptTpl table 魔化模板
---@param equip table
---@return table newAffix
local function buildConvertedAffix(affix, corruptTpl, equip)
    local oldValue = tonumber(affix.value) or 0
    local tplValue = EquipmentSystem.calcCorruptAffixValue(corruptTpl, equip)
    local value = math.max(oldValue * CORRUPT_CONVERT_VALUE_MULT, tplValue * CORRUPT_CONVERT_VALUE_MULT)
    if corruptTpl.dataType == "int" then
        value = math.floor(value + 0.5)
    end
    return {
        affixId = corruptTpl.id,
        quality = 0,
        value   = value,
        key     = corruptTpl.key,
        name    = corruptTpl.name,
        convertedFrom = affix.key,
    }
end

local function copyAffix(affix)
    return {
        affixId  = affix.affixId,
        quality  = affix.quality,
        value    = affix.value,
        key      = affix.key,
        name     = affix.name,
        ascBonus = (tonumber(affix.ascBonus) or 0) > 0 and affix.ascBonus or nil,
    }
end

local recalcBaseStatsForEquip

local function copyAffixList(affixes)
    local copied = {}
    for _, affix in ipairs(affixes or {}) do
        copied[#copied + 1] = copyAffix(affix)
    end
    return copied
end

--- 确保 corruptRevert 存在（新档 patches 带 layer 标记；旧档快照结构由 cleanse 兼容分支处理）
local function ensureCorruptRevert(equip)
    if not equip.corruptRevert then
        equip.corruptRevert = {
            baseMult = nil,
            affixCount = #(equip.affixes or {}),
            patches = {},
        }
    end
    return equip.corruptRevert
end

--- 神圣石：洗除最上层腐化诅咒（逐层回退，构筑模型 2026-09-30）
--- 新档 patches 带 layer 标记，仅回退该层；旧档 patches 无 layer，回退为一次性全清（迁移兼容）
---@param equip table
---@return number newCorruptCount
local function cleanseOneCorruptLayer(equip)
    -- 旧档：整份词缀快照 → 一次性全清
    if equip.corruptOriginalAffixes then
        equip.affixes = copyAffixList(equip.corruptOriginalAffixes)
        equip.corruptCount = nil
        equip.corruptBaseMult = equip.corruptOriginalBaseMult
        equip.corruptOriginalBaseMult = nil
        equip.corruptOriginalAffixes = nil
        equip.corruptRevert = nil
        if equip.corruptBaseMult == nil or equip.corruptBaseMult == 1 then
            equip.corruptBaseMult = nil
        end
        recalcBaseStatsForEquip(equip)
        return 0
    end

    local rev = equip.corruptRevert
    local layer = getCorruptCount(equip)
    if layer <= 0 then
        equip.corruptCount = nil
        equip.corruptBaseMult = nil
        equip.corruptRevert = nil
        return 0
    end

    if not rev then
        -- 无回退记录：仅降层数与诅咒倍率
        layer = layer - 1
        equip.corruptCount = layer > 0 and layer or nil
        equip.corruptBaseMult = layer > 0 and (CORRUPT_LAYER_BASE_PENALTY ^ layer) or nil
        recalcBaseStatsForEquip(equip)
        return layer
    end

    local affixes = equip.affixes or {}
    local patches = rev.patches or {}
    local hasLayerTag = false
    for _, patch in ipairs(patches) do
        if patch.layer then hasLayerTag = true; break end
    end

    if hasLayerTag then
        -- 新档：仅回退最上层的转换 patch（"c" 型：整条还原）
        local kept = {}
        for _, patch in ipairs(patches) do
            if patch.layer == layer and patch[1] == "c" then
                local idx = patch[2]
                local orig = patch[3]
                if affixes[idx] and orig then
                    affixes[idx] = copyAffix(orig)
                end
            else
                kept[#kept + 1] = patch
            end
        end
        rev.patches = kept
    else
        -- 旧档无 layer：一次性全清（改值 patch 还原 + 截断新增段）
        for _, patch in ipairs(patches) do
            if patch[1] == "s" then
                local idx = patch[2]
                local v0 = patch[3]
                if affixes[idx] then
                    affixes[idx] = copyAffix(affixes[idx])
                    affixes[idx].value = v0
                end
            end
        end
        local keepCount = rev.affixCount or #affixes
        while #affixes > keepCount do
            table.remove(affixes)
        end
        layer = 0
    end

    equip.affixes = affixes
    layer = layer - 1
    equip.corruptCount = layer > 0 and layer or nil
    equip.corruptBaseMult = layer > 0 and (CORRUPT_LAYER_BASE_PENALTY ^ layer) or nil
    if layer <= 0 then
        equip.corruptRevert = nil
    end
    recalcBaseStatsForEquip(equip)
    return layer
end

local function buildExcludeKeysFromAffixes(affixes)
    local exclude = {}
    for _, affix in ipairs(affixes or {}) do
        if affix.key then exclude[affix.key] = true end
    end
    return exclude
end

--- 腐化石主构建：复制词缀列表并把选中的一条普通词缀转为同类型魔化词条
---@param equip table
---@param rev table corruptRevert
---@return table[] newAffixes, table|nil convertedInfo { index, before, after }
local function buildConvertedAffixes(equip, rev)
    local source = equip.affixes or {}
    local result = {}
    for _, affix in ipairs(source) do
        result[#result + 1] = copyAffix(affix)
    end
    local idx, corruptTpl = pickConvertibleAffix(result)
    if not idx then return result, nil end
    local layer = getCorruptCount(equip) + 1
    local before = copyAffix(result[idx])
    result[idx] = buildConvertedAffix(before, corruptTpl, equip)
    rev.patches[#rev.patches + 1] = { "c", idx, before, layer = layer }
    return result, { index = idx, before = before, after = result[idx] }
end

recalcBaseStatsForEquip = function(equip)
    local qDef = EquipmentConfig.QUALITY[tonumber(equip.quality) or 1]
    local baseStrength = qDef and qDef.baseStrength or 1.0
    if equip.corruptBaseMult and equip.corruptBaseMult ~= 1 then
        baseStrength = baseStrength * equip.corruptBaseMult
    end
    local baseStats = EquipmentSystem.recalcBaseStats(equip.templateId, equip.level or 1, baseStrength)
    if #baseStats > 0 then
        equip.baseStats = baseStats
    end
end

--- 构建腐化转换详情（供客户端展示前后对比；构筑模型）
local function buildConvertEffectDetail(convertedInfo, beforeAffixes, afterAffixes, beforeBaseMult, afterBaseMult)
    local detail = { affixChanges = {} }
    beforeBaseMult = tonumber(beforeBaseMult) or 1
    afterBaseMult = tonumber(afterBaseMult) or 1

    if convertedInfo then
        local b = convertedInfo.before
        local a = convertedInfo.after
        detail.effectId = 100
        detail.effectName = string.format("%s → %s（魔化）", tostring(b.name), tostring(a.name))
        detail.summary = string.format("一条词缀转为同类型魔化词条，数值 %.2f → %.2f",
            tonumber(b.value) or 0, tonumber(a.value) or 0)
        detail.affixChanges[#detail.affixChanges + 1] = {
            index = convertedInfo.index,
            kind = "converted",
            affixId = a.affixId,
            key = a.key,
            name = a.name,
            beforeName = b.name,
            beforeKey = b.key,
            beforeValue = tonumber(b.value) or 0,
            afterValue = tonumber(a.value) or 0,
        }
    else
        detail.effectId = 101
        detail.effectName = "无可转换词缀"
        detail.summary = "装备没有可转换的普通词缀，本次腐化未生效"
    end

    if math.abs(afterBaseMult - beforeBaseMult) > 0.0001 then
        detail.baseMultChange = { before = beforeBaseMult, after = afterBaseMult }
    end
    return detail
end

--- normal→4(史诗), hard→5(传说), nightmare→6(至臻，待配置)
local DIFF_TO_MAX_QUALITY = {
    [StageConfig.DIFFICULTY_NORMAL]    = 4,  -- 史诗
    [StageConfig.DIFFICULTY_HARD]      = 5,  -- 传说
    [StageConfig.DIFFICULTY_NIGHTMARE] = 6,  -- 至臻
    [StageConfig.DIFFICULTY_HELL]      = 6,
    [StageConfig.DIFFICULTY_PURGATORY] = 6,
    [StageConfig.DIFFICULTY_TORMENT]   = 6,
    [StageConfig.DIFFICULTY_TORMENT2]  = 6,
    [StageConfig.DIFFICULTY_TORMENT3]  = 6,
    [StageConfig.DIFFICULTY_TORMENT4]  = 6,
    [StageConfig.DIFFICULTY_TORMENT5]      = 6,
    [StageConfig.DIFFICULTY_ANNIHILATION]  = 6,
    [StageConfig.DIFFICULTY_ANNIHILATION2] = 6,
    [StageConfig.DIFFICULTY_ANNIHILATION3] = 6,
    [StageConfig.DIFFICULTY_ANNIHILATION4] = 6,
    [StageConfig.DIFFICULTY_ANNIHILATION5] = 6,
}

--- 获取指定玩家的点金石品质上限
---@param uid number
---@return number
local function getUpgradeMaxQuality(uid)
    local battle = PDM.GetModule(uid, "battle")
    local maxStageId = battle and (battle.maxStageId or battle.currentStageId) or 0
    local diff = StageConfig.getDifficulty(maxStageId)
    return DIFF_TO_MAX_QUALITY[diff] or 4
end

--- 解析洗练锁定词缀 index（1-based），返回 set 与数量
---@param lockedIndices table|nil
---@param affixCount number
---@return table lockedSet
---@return number lockedCount
local function normalizeLockedIndices(lockedIndices, affixCount)
    local lockedSet = {}
    local lockedCount = 0
    if not lockedIndices or affixCount <= 0 then
        return lockedSet, lockedCount
    end
    for _, v in ipairs(lockedIndices) do
        local idx = math.floor(tonumber(v) or 0)
        if idx >= 1 and idx <= affixCount and not lockedSet[idx] then
            lockedSet[idx] = true
            lockedCount = lockedCount + 1
        end
    end
    return lockedSet, lockedCount
end

--- 普通洗练/洗练石重随机时保持魔化词条固定（构筑模型）：
--- 先拆出魔化词条，对剩余普通词条 reroll（锁定索引重映射），再把魔化词条插回原位置
---@param existingAffixes table[]
---@param lockedSet table|nil
---@param rollFn fun(list:table[], locks:table|nil):table[]
---@return table[]
local function rerollKeepCorrupt(existingAffixes, lockedSet, rollFn)
    local corruptIdx, corruptAffixes = {}, {}
    local plainAffixes, remap = {}, {}
    for i, affix in ipairs(existingAffixes or {}) do
        if AffixConfig.isCorruptAffix(affix) then
            corruptIdx[#corruptIdx + 1] = i
            corruptAffixes[#corruptAffixes + 1] = affix
        else
            plainAffixes[#plainAffixes + 1] = affix
            remap[i] = #plainAffixes
        end
    end
    if #corruptAffixes == 0 then
        return rollFn(existingAffixes, lockedSet)
    end
    local mappedLocks = nil
    if lockedSet then
        mappedLocks = {}
        for idx in pairs(lockedSet) do
            local ni = remap[idx]
            if ni then mappedLocks[ni] = true end
        end
    end
    local rolled = rollFn(plainAffixes, mappedLocks)
    local result = {}
    for i = 1, #rolled do
        result[i] = rolled[i]
    end
    for j, origIdx in ipairs(corruptIdx) do
        table.insert(result, origIdx, corruptAffixes[j])
    end
    return result
end

--- 洗练装备（消耗精粹，可选额外资源：洗练石=只洗数值/点金石=提品/腐化石=同类型魔化转换+诅咒层/神圣石=洗除一层诅咒）
--- 构筑模型 2026-09-30：腐化后仍可洗练（精粹 ×2），魔化词条在洗练/洗练石中保持固定
---@param uid number
---@param seq number
---@param extraResource string|nil 额外资源 key ("enhanceStone"/"destroyStone"/"corruptStone"/"sacredStone"/nil)
---@param lockedIndices table|nil 锁定的词缀 index 列表（1-based）
---@return boolean ok, string? err, table? result
function BlacksmithService.RefineEquip(uid, seq, extraResource, lockedIndices)
    local equipData = PDM.GetModule(uid, "equipment")
    local currency  = PDM.GetModule(uid, "currency")
    if not equipData or not currency then
        return false, "数据未加载"
    end

    local seqStr = tostring(seq)
    local equip = equipData.inventory and equipData.inventory[seqStr]
    if not equip then
        return false, "装备不存在"
    end

    local q = equip.quality or 1
    local qDef = EquipmentConfig.QUALITY[q]

    -- 2026-09-30：精粹入列可选资源；选精粹=普通洗练（消耗精粹），选四种石头不再消耗精粹
    local chargesEssence = (extraResource == nil or extraResource == "" or extraResource == "essence")
    if extraResource == "essence" then
        extraResource = nil
    end

    -- 校验额外资源
    local extraDef = nil
    if extraResource and extraResource ~= "" then
        extraDef = EXTRA_RES_DEFS[extraResource]
        if not extraDef then
            return false, "无效的额外资源类型"
        end

        -- 点金石消耗动态计算：品质N→N+1 消耗N个
        local actualCost = extraDef.cost or q  -- 点金石 cost=nil 时使用当前品质
        if (currency[extraDef.field] or 0) < actualCost then
            return false, extraDef.name .. "不足（需要" .. actualCost .. "个）"
        end

        -- 点金石特殊校验：达当前进度最高品质后转为词缀提品（后期出口），需至少一条可提品词缀
        if extraResource == "destroyStone" then
            local maxQ = getUpgradeMaxQuality(uid)
            if q >= maxQ and not pickUpgradableAffix(equip.affixes) then
                return false, "装备品质已达上限且无可提品词缀（普通词缀均已 S 品）"
            end
        end

        -- 洗练石特殊校验：装备必须有词缀才能洗数值
        if extraResource == "enhanceStone" then
            if not equip.affixes or #equip.affixes == 0 then
                return false, "装备无词缀，无法使用洗练石"
            end
        end

        -- 腐化石特殊校验：最多 3 层诅咒 + 至少一条可转换普通词缀
        if extraResource == "corruptStone" then
            local currentCorruptCount = math.max(0, math.floor(tonumber(equip.corruptCount) or 0))
            if currentCorruptCount >= MAX_CORRUPT_COUNT then
                return false, "该装备已腐化3层，需要先使用神圣石洗除诅咒"
            end
            if not pickConvertibleAffix(equip.affixes) then
                return false, "装备没有可转换的普通词缀，无法使用腐化石"
            end
        end

        -- 神圣石特殊校验：只洗除已腐化装备的诅咒层
        if extraResource == "sacredStone" then
            local currentCorruptCount = math.max(0, math.floor(tonumber(equip.corruptCount) or 0))
            if currentCorruptCount <= 0 then
                return false, "该装备未处于腐化状态"
            end
        end
    end

    local corruptCount = getCorruptCount(equip)

    -- 神圣石：洗除最上层腐化诅咒（逐层回退），不消耗精粹，不增加洗练次数
    if extraResource == "sacredStone" then
        currency.sacredStone = (currency.sacredStone or 0) - 1
        local newCorruptCount = cleanseOneCorruptLayer(equip)

        if pendingRefines[uid] then
            pendingRefines[uid][seqStr] = nil
        end

        PDM.MarkDirty(uid, "currency")
        PDM.MarkDirty(uid, "equipment")
        PDM.FlushImmediate(uid)

        print("[BlacksmithService] REFINE+CLEANSE uid=" .. tostring(uid)
            .. " seq=" .. seqStr .. " sacredStone=-1 corrupt " .. corruptCount .. "→" .. newCorruptCount)

        return true, nil, {
            refinePreview = equip.affixes,
            refineSeq = seq,
            autoReplaced = true,
            cleansed = true,
            corruptCount = newCorruptCount,
            corruptBaseMult = equip.corruptBaseMult,
            corruptRevert = equip.corruptRevert,
            newQuality = equip.quality,
        }
    end

    -- 非点金石/神圣石洗练时，装备本身必须有词缀
    if extraResource ~= "destroyStone" and extraResource ~= "sacredStone" then
        if not qDef or not equip.affixes or #equip.affixes == 0 then
            return false, "装备无词缀，无法洗练"
        end
    end

    local qCost = QUALITY_COST[q] or QUALITY_COST[1]
    local equipLv = equip.level or 1
    local refineCount = equip.refineCount or 0
    local affixCount = equip.affixes and #equip.affixes or 0

    local lockedSet, lockedCount = normalizeLockedIndices(lockedIndices, affixCount)
    if extraResource ~= "destroyStone" and extraResource ~= "corruptStone" and affixCount > 0 and lockedCount >= affixCount then
        return false, "至少保留1条词缀未锁定"
    end

    -- 普通洗练可能换到任一普通属性；缺失价值配置必须在扣费/累计次数之前拒绝。
    if not extraDef then
        for i, oldAff in ipairs(equip.affixes or {}) do
            if not lockedSet[i] and not AffixConfig.isCorruptAffix(oldAff)
                and (tonumber(oldAff.ascBonus) or 0) > 0 then
                for _, candidate in ipairs(AffixConfig.AFFIXES) do
                    if not AffixConfig.isCorruptAffix(candidate) then
                        local valid, reason = pcall(EquipmentSystem.convertAscBonusForRefine, oldAff, candidate)
                        if not valid then return false, tostring(reason) end
                    end
                end
            end
        end
    end

    -- 精粹消耗：仅普通洗练/选精粹路径（石头路径不再需要精粹）
    local essenceCost = 0
    if chargesEssence then
        essenceCost = BlacksmithConfig.calcRefineEssenceCost(q, equipLv, equip.grip)
        -- 腐化诅咒：洗练精粹 ×2（与锁定倍率不叠加）
        if corruptCount > 0 then
            essenceCost = essenceCost * CORRUPTED_ESSENCE_MULT
        end
        essenceCost = BlacksmithConfig.applyRefineLockCostMult(essenceCost, lockedCount)
        if (currency.essence or 0) < essenceCost then
            return false, "精粹不足"
        end
    end

    -- 扣精粹 & 累计洗练次数（费用固定单价，次数仅作统计展示）
    if chargesEssence then
        currency.essence = currency.essence - essenceCost
    end
    equip.refineCount = BlacksmithConfig.nextRefineCount(refineCount)

    -- 扣额外资源（点金石消耗=当前品质，洗练石=固定1）
    if extraDef then
        local actualCost = extraDef.cost or q  -- 点金石 cost=nil 时使用当前品质
        currency[extraDef.field] = (currency[extraDef.field] or 0) - actualCost
    end

    -- === 根据额外资源类型决定效果 ===

    local oldAffixList = equip.affixes
    local newAffixes
    local upgradedQuality = nil    -- 仅点金石提品时非 nil
    local affixGradeUp = nil       -- 仅点金石后期出口（词缀提品）时非 nil
    local convertedInfo = nil      -- 仅腐化石时非 nil
    local corruptBeforeAffixes = nil
    local corruptBaseMultBefore = nil
    local extraLog = ""

    if extraResource == "enhanceStone" then
        local maxAffixQ = math.max(1, qDef.maxAffixQuality or 0)
        local randomStrength = qDef.randomStrength or 1.0
        local oldAffixes = equip.affixes
        newAffixes = rerollKeepCorrupt(oldAffixes, lockedSet, function(list, locks)
            return EquipmentSystem.rerollAffixValuesWithLocks(
                list, maxAffixQ, equipLv, randomStrength, equip.grip, locks)
        end)
        -- 保底只升不降：逐条取新旧较高者（魔化词条固定不变，锁定槽同值无影响）
        local kept = 0
        for i, newAff in ipairs(newAffixes) do
            local oldAff = oldAffixes and oldAffixes[i]
            if oldAff and not AffixConfig.isCorruptAffix(oldAff)
                and (tonumber(oldAff.value) or 0) > (tonumber(newAff.value) or 0) then
                newAffixes[i] = copyAffix(oldAff)
                kept = kept + 1
            end
        end
        extraLog = " extra=洗练石(rerollValues+keepHigher)"
        if kept > 0 then
            extraLog = extraLog .. " kept=" .. kept
        end
        if lockedCount > 0 then
            extraLog = extraLog .. " locked=" .. lockedCount
        end

    elseif extraResource == "destroyStone" then
        local maxQ = getUpgradeMaxQuality(uid)
        if q < maxQ then
            -- ── 点金石：提品 +1，保留原有词缀不变 ──
            local newQ = math.min(q + 1, maxQ)
            -- 安全降级：若目标品质尚未配置（如至臻品质6），回退到已有最高品质
            local newQDef = EquipmentConfig.QUALITY[newQ]
            if not newQDef then
                newQ = #EquipmentConfig.QUALITY  -- 回退到已配置的最高品质
                newQDef = EquipmentConfig.QUALITY[newQ]
            end

            -- 保留原有词缀，若新品质词缀槽位更多则补充生成
            newAffixes = equip.affixes or {}
            local newAffixCount = newQDef.affixCount or 0
            if #newAffixes < newAffixCount then
                local maxAffixQ = newQDef.maxAffixQuality or 1
                local randomStrength = newQDef.randomStrength or 1.0
                local extraAffixes = EquipmentSystem.rollAffixes(
                    newAffixCount - #newAffixes, maxAffixQ, equipLv,
                    buildExcludeKeysFromAffixes(newAffixes), randomStrength, equip.grip
                )
                for _, af in ipairs(extraAffixes) do
                    newAffixes[#newAffixes + 1] = af
                end
            end
            upgradedQuality = newQ
            extraLog = " extra=点金石(upgrade " .. q .. "→" .. newQ .. " maxQ=" .. maxQ .. " affixes=" .. #newAffixes .. ")"
        else
            -- ── 点金石后期出口：品质已达进度上限 → 随机一条普通词缀品级 +1（最高 S=5）──
            newAffixes = copyAffixList(equip.affixes)
            local idx = pickUpgradableAffix(newAffixes)
            if not idx then
                return false, "装备品质已达上限且无可提品词缀（普通词缀均已 S 品）"
            end
            local before = copyAffix(newAffixes[idx])
            local afterQ = math.min(5, (tonumber(before.quality) or 1) + 1)
            newAffixes[idx].quality = afterQ
            affixGradeUp = { index = idx, before = before, afterQ = afterQ }
            upgradedQuality = nil
            extraLog = " extra=点金石(affixGradeUp " .. tostring(before.name)
                .. " q" .. tostring(before.quality) .. "→" .. afterQ .. ")"
        end

    elseif extraResource == "corruptStone" then
        -- ── 腐化石：一条普通词缀转同类型魔化词条 + 叠加一层诅咒（直接应用）──
        local corruptRev = ensureCorruptRevert(equip)
        corruptBeforeAffixes = copyAffixList(equip.affixes)
        corruptBaseMultBefore = tonumber(equip.corruptBaseMult) or 1
        newAffixes, convertedInfo = buildConvertedAffixes(equip, corruptRev)
        if convertedInfo then
            local newLayer = math.min(MAX_CORRUPT_COUNT, corruptCount + 1)
            equip.corruptCount = newLayer
            equip.corruptBaseMult = CORRUPT_LAYER_BASE_PENALTY ^ newLayer
            recalcBaseStatsForEquip(equip)
        end
        extraLog = " extra=腐化石(convert=" .. (convertedInfo and tostring(convertedInfo.before.name) or "none")
            .. " layer=" .. tostring(equip.corruptCount or 0) .. ")"

    else
        -- ── 普通洗练：未锁定槽重随机（魔化词条保持固定）──
        local maxAffixQ  = math.max(1, qDef.maxAffixQuality or 0)
        local normalRandomStrength = qDef.randomStrength or 1.0
        newAffixes = rerollKeepCorrupt(equip.affixes, lockedSet, function(list, locks)
            return EquipmentSystem.rollAffixesForRefine(
                list, locks, maxAffixQ, equipLv, normalRandomStrength, equip.grip)
        end)
        if lockedCount > 0 then
            extraLog = " locked=" .. lockedCount
        end
    end

    -- 固定升阶投入按位置跟随；更换属性时换算价值，旧装仅预览不改写，魔化槽位不持有。
    local convertedAscSlots = 0
    if newAffixes and oldAffixList then
        for i, newAff in ipairs(newAffixes) do
            local oldAff = oldAffixList[i]
            if oldAff and newAff
                and not AffixConfig.isCorruptAffix(oldAff)
                and not AffixConfig.isCorruptAffix(newAff) then
                newAff.ascBonus = EquipmentSystem.convertAscBonusForRefine(oldAff, newAff)
                if newAff.ascBonus and oldAff.key ~= newAff.key then
                    convertedAscSlots = convertedAscSlots + 1
                end
            end
        end
    end
    if convertedAscSlots > 0 then
        extraLog = extraLog .. " ascendValueConverted=" .. convertedAscSlots
    end

    -- 点金石：直接应用结果（无需手动点替换；后期出口仅改词缀品级，不动品质）
    if extraResource == "destroyStone" then
        equip.affixes = newAffixes
        if upgradedQuality then
            equip.quality = upgradedQuality
        end

        -- 用新品质和已有腐化基础倍率重算基础属性
        recalcBaseStatsForEquip(equip)

        if pendingRefines[uid] then
            pendingRefines[uid][seqStr] = nil
        end

        PDM.MarkDirty(uid, "currency")
        PDM.MarkDirty(uid, "equipment")
        PDM.FlushImmediate(uid)

        print("[BlacksmithService] REFINE+AUTO_REPLACE uid=" .. tostring(uid)
            .. " seq=" .. seqStr .. " cost=" .. essenceCost
            .. " refineCount=" .. equip.refineCount
            .. " newAffixes=" .. #newAffixes .. extraLog)

        TaskService.UpdateProgress(uid, "refine", 1)

        return true, nil, {
            refinePreview = newAffixes,
            refineSeq = seq,
            upgradedQuality = upgradedQuality,
            affixGradeUp = affixGradeUp,
            autoReplaced = true,
            newQuality = upgradedQuality or q,
        }
    end

    -- 腐化石：直接应用转换结果（无需手动点替换；层数/诅咒在效果分支已写入）
    if extraResource == "corruptStone" then
        equip.affixes = newAffixes

        if pendingRefines[uid] then
            pendingRefines[uid][seqStr] = nil
        end

        PDM.MarkDirty(uid, "currency")
        PDM.MarkDirty(uid, "equipment")
        PDM.FlushImmediate(uid)

        print("[BlacksmithService] REFINE+CORRUPT uid=" .. tostring(uid)
            .. " seq=" .. seqStr .. " cost=" .. essenceCost
            .. " refineCount=" .. equip.refineCount
            .. " newAffixes=" .. #newAffixes .. extraLog)

        TaskService.UpdateProgress(uid, "refine", 1)

        local corruptBaseMultAfter = tonumber(equip.corruptBaseMult) or 1
        local corruptEffectDetail = buildConvertEffectDetail(
            convertedInfo,
            corruptBeforeAffixes,
            newAffixes,
            corruptBaseMultBefore,
            corruptBaseMultAfter
        )

        return true, nil, {
            refinePreview = newAffixes,
            refineSeq = seq,
            autoReplaced = true,
            corrupted = true,
            corruptEffectId = corruptEffectDetail.effectId,
            corruptEffectName = corruptEffectDetail.effectName,
            corruptEffectDetail = corruptEffectDetail,
            corruptBeforeAffixes = corruptBeforeAffixes,
            corruptBaseMultBefore = corruptBaseMultBefore,
            corruptCount = equip.corruptCount,
            corruptBaseMult = equip.corruptBaseMult,
            corruptRevert = equip.corruptRevert,
            newQuality = equip.quality,
        }
    end

    -- 普通洗练/洗练石：存到服务端待定状态，等待玩家确认替换
    if not pendingRefines[uid] then
        pendingRefines[uid] = {}
    end
    pendingRefines[uid][seqStr] = {
        affixes = newAffixes,
        upgradedQuality = upgradedQuality,
    }

    PDM.MarkDirty(uid, "currency")
    PDM.MarkDirty(uid, "equipment")
    PDM.FlushImmediate(uid)

    print("[BlacksmithService] REFINE uid=" .. tostring(uid)
        .. " seq=" .. seqStr .. " cost=" .. essenceCost
        .. " refineCount=" .. equip.refineCount
        .. " newAffixes=" .. #newAffixes .. extraLog)

    -- 任务进度
    TaskService.UpdateProgress(uid, "refine", 1)

    return true, nil, {
        refinePreview = newAffixes,
        refineSeq = seq,
        upgradedQuality = upgradedQuality,
    }
end

-- ======================== 替换词缀 ========================

--- 确认洗练结果（替换词缀）
---@param uid number
---@param seq number
---@return boolean ok, string? err, table? result
function BlacksmithService.RefineReplace(uid, seq)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then
        return false, "数据未加载"
    end

    local seqStr = tostring(seq)
    local equip = equipData.inventory and equipData.inventory[seqStr]
    if not equip then
        return false, "装备不存在"
    end

    local pending = pendingRefines[uid] and pendingRefines[uid][seqStr]
    if not pending or not pending.affixes then
        return false, "无待替换的洗练结果，请先洗练"
    end

    -- 应用新词缀
    equip.affixes = pending.affixes

    -- 点金石提品：更新装备品质 + 重算基础属性
    if pending.upgradedQuality then
        local oldQ = equip.quality
        equip.quality = pending.upgradedQuality

        -- 用新品质的 baseStrength 重算基础属性
        local newQDef = EquipmentConfig.QUALITY[pending.upgradedQuality]
        local newBaseStrength = newQDef and newQDef.baseStrength or 1.0
        local newBaseStats = EquipmentSystem.recalcBaseStats(equip.templateId, equip.level or 1, newBaseStrength)
        if #newBaseStats > 0 then
            equip.baseStats = newBaseStats
        end

        print("[BlacksmithService] REFINE_REPLACE UPGRADE quality "
            .. tostring(oldQ) .. " → " .. tostring(equip.quality))
    end

    pendingRefines[uid][seqStr] = nil

    PDM.MarkDirty(uid, "equipment")

    print("[BlacksmithService] REFINE_REPLACE uid=" .. tostring(uid)
        .. " seq=" .. seqStr
        .. " quality=" .. tostring(equip.quality)
        .. " refineCount=" .. (equip.refineCount or 0))

    return true, nil, {
        refineReplaced = true,
        newQuality = equip.quality,
    }
end

-- ======================== 分解装备 ========================

--- 批量分解装备（获得精粹 + 升阶卷轴 70% 返还，金币不退）
---@param uid number
---@param seqs number[]
---@return boolean ok, string? err, table? result
function BlacksmithService.DecomposeEquip(uid, seqs)
    local equipData = PDM.GetModule(uid, "equipment")
    local currency  = PDM.GetModule(uid, "currency")
    if not equipData or not currency then
        return false, "数据未加载"
    end

    if not seqs or #seqs == 0 then
        return false, "未选择装备"
    end

    -- 验证所有装备存在且未穿戴（seq 去重：重复提交同一 seq 不得重复计奖）
    local toRemove = {}
    local seenSeqs = {}
    for _, seq in ipairs(seqs) do
        seq = tonumber(seq)
        if not seq then
            return false, "无效的装备序列号"
        end
        if seenSeqs[seq] then
            return false, "装备序列号重复: " .. tostring(seq)
        end
        seenSeqs[seq] = true
        local seqStr = tostring(seq)
        local equip = equipData.inventory and equipData.inventory[seqStr]
        if not equip then
            return false, "装备不存在: " .. seqStr
        end
        local isEquipped = false
        if equipData.equipped then
            for _, slots in pairs(equipData.equipped) do
                for _, eqSeq in pairs(slots) do
                    if eqSeq == seq then
                        isEquipped = true
                        break
                    end
                end
                if isEquipped then break end
            end
        end
        if isEquipped then
            return false, "不能分解已穿戴的装备"
        end
        -- 锁定的装备跳过（防止客户端漏过滤），不计入分解列表
        if not equip.locked then
            toRemove[#toRemove + 1] = { seq = seq, equip = equip }
        end
    end

    if #toRemove == 0 then
        return false, "选中的装备已锁定，无法分解"
    end

    -- 计算总精粹奖励: decBase * (1 + level * decScale) + 洗练返还
    -- 升阶卷轴按已投入的 70% 退回对应部位，金币不退
    local totalEssence = 0
    local totalRefineReturn = 0
    local scrollRewards = {}
    local totalScrollRefund = 0
    for _, item in ipairs(toRemove) do
        local equip = item.equip
        EquipmentSystem.hydrate(equip)
        local q = equip.quality or 1
        local lv = equip.level or 1
        local qCost = QUALITY_COST[q] or QUALITY_COST[1]
        -- 基础分解奖励
        local reward = math.floor(qCost.decBase * (1 + lv * qCost.decScale))
        totalEssence = totalEssence + reward

        -- 洗练精粹返还：累加该装备历次洗练消耗，返还50%（次数封顶 20）
        local refineCount = equip.refineCount or 0
        if refineCount > 0 then
            local totalSpent = BlacksmithConfig.calcTotalRefineSpent(q, lv, refineCount, equip.grip)
            local refineReturn = math.floor(totalSpent * 0.5)
            totalRefineReturn = totalRefineReturn + refineReturn
        end

        local ascendLv = EquipmentSystem.getAscendLevel(equip)
        local scrollRefund = BlacksmithConfig.calcAscendScrollRefund(ascendLv)
        local scrollField = SLOT_SCROLL_MAP[equip.slot]
        if scrollRefund > 0 and scrollField then
            scrollRewards[scrollField] = (scrollRewards[scrollField] or 0) + scrollRefund
            totalScrollRefund = totalScrollRefund + scrollRefund
        elseif scrollRefund > 0 then
            print("[BlacksmithService] DECOMPOSE skip scroll refund, no slot seq="
                .. tostring(item.seq))
        end
    end
    totalEssence = totalEssence + totalRefineReturn

    -- 执行分解
    for _, item in ipairs(toRemove) do
        EquipmentSystem.removeFromInventory(equipData, item.seq)
    end
    currency.essence = (currency.essence or 0) + totalEssence
    for field, amount in pairs(scrollRewards) do
        currency[field] = (currency[field] or 0) + amount
    end

    PDM.MarkDirty(uid, "equipment")
    PDM.MarkDirty(uid, "currency")

    print("[BlacksmithService] DECOMPOSE uid=" .. tostring(uid)
        .. " count=" .. #toRemove
        .. " essence=+" .. totalEssence
        .. " (base=" .. (totalEssence - totalRefineReturn) .. " refineReturn=" .. totalRefineReturn .. ")"
        .. " scrollRefund=+" .. totalScrollRefund)

    -- 任务进度
    TaskService.UpdateProgress(uid, "decompose", #toRemove)

    return true, nil, {
        decomposed = true,
        decomposeCount = #toRemove,
        essenceReward = totalEssence,
        refineReturn = totalRefineReturn,
        scrollRewards = scrollRewards,
        scrollReward = totalScrollRefund,
    }
end

-- ======================== 工具方法 ========================

--- 断线时清理内存中的洗练待定状态
---@param uid number
function BlacksmithService.Cleanup(uid)
    if pendingRefines[uid] then
        pendingRefines[uid] = nil
        print("[BlacksmithService] cleanup pendingRefines uid=" .. tostring(uid))
    end
end

return BlacksmithService
