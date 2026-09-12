---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- BlacksmithService - 铁匠铺业务逻辑
-- 职责: 装备强化、洗练、替换词缀、分解
-- 层级: server/blacksmith  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM              = require("server.character.PlayerDataManager")
local EquipmentSystem  = require("systems.EquipmentSystem")
local EquipmentConfig  = require("config.EquipmentConfig")
local AffixConfig      = require("config.AffixConfig")
local BlacksmithConfig = require("config.BlacksmithConfig")
local ExpTable         = require("config.ExpTable")
local TaskService      = require("server.task.TaskService")
local StageConfig      = require("config.StageConfig")

local QUALITY_COST  = BlacksmithConfig.QUALITY_COST

local BlacksmithService = {}

-- 服务端洗练待定状态 pendingRefines[uid][seqStr] = { affixes = {...} }
local pendingRefines = {}

-- ======================== 槽位强化 ========================

local SLOT_SCROLL_MAP = BlacksmithConfig.SLOT_SCROLL_MAP
local MAX_ENHANCE_LV  = BlacksmithConfig.MAX_ENHANCE_LEVEL

--- 获取指定玩家当前的强化等级上限（冒险等级动态上限）
---@param uid number
---@return number
local function getEnhanceCap(uid)
    local playerData = PDM.GetModule(uid, "player")
    local playerLevel = playerData and (playerData.level or 1) or 1
    return ExpTable.getEnhanceLevelCap(playerLevel)
end

--- 槽位强化（100% 成功，消耗金币 + 对应卷轴）
---@param uid number
---@param partySlot number 出战槽位索引 (1~5)
---@param equipSlot string 装备位置 ("weapon"/"offhand"/"armor"/"accessory")
---@return boolean ok, string? err, table? result
function BlacksmithService.EnhanceSlot(uid, partySlot, equipSlot)
    local slotData = PDM.GetModule(uid, "slotEnhance")
    local currency = PDM.GetModule(uid, "currency")
    if not slotData or not currency then
        return false, "数据未加载"
    end

    -- 校验参数
    partySlot = tonumber(partySlot)
    if not partySlot or partySlot < 1 or partySlot > 5 then
        return false, "无效的出战槽位"
    end
    local scrollField = SLOT_SCROLL_MAP[equipSlot]
    if not scrollField then
        return false, "无效的装备位置"
    end

    -- 获取当前等级
    if not slotData.levels[partySlot] then
        slotData.levels[partySlot] = {}
    end
    local currentLv = slotData.levels[partySlot][equipSlot] or 0
    local enhanceCap = getEnhanceCap(uid)
    if currentLv >= enhanceCap then
        return false, "强化等级已达当前冒险等级上限（" .. enhanceCap .. "级），提升冒险等级后可继续强化"
    end
    if currentLv >= MAX_ENHANCE_LV then
        return false, "已达最大强化等级"
    end

    local nextLv = currentLv + 1
    local cost = BlacksmithConfig.getEnhanceCost(nextLv)
    if not cost then
        return false, "强化配置异常"
    end

    -- 校验资源
    if (currency.gold or 0) < cost.gold then
        return false, "金币不足"
    end
    if (currency[scrollField] or 0) < cost.scroll then
        return false, "卷轴不足"
    end

    -- === 扣资源 ===
    currency.gold = currency.gold - cost.gold
    currency[scrollField] = currency[scrollField] - cost.scroll

    -- === 提升等级（100% 成功） ===
    slotData.levels[partySlot][equipSlot] = nextLv

    PDM.MarkDirty(uid, "currency")
    PDM.MarkDirty(uid, "slotEnhance")

    -- 任务进度
    TaskService.UpdateProgress(uid, "enhance", 1)

    print("[BlacksmithService] ENHANCE_SLOT uid=" .. tostring(uid)
        .. " party=" .. partySlot .. " slot=" .. equipSlot
        .. " lv=" .. nextLv .. " gold=-" .. cost.gold
        .. " " .. scrollField .. "=-" .. cost.scroll)

    return true, nil, {
        enhanceOutcome = "success",
        partySlot = partySlot,
        equipSlot = equipSlot,
        newLevel = nextLv,
    }
end

--- 一键强化到目标等级（批量连续升级）
---@param uid string
---@param partySlot number 出战槽位 1-5
---@param equipSlot string 装备位置 weapon/offhand/armor/accessory
---@param targetLevel number 目标强化等级
---@return boolean, string|nil, table|nil
function BlacksmithService.EnhanceSlotToLevel(uid, partySlot, equipSlot, targetLevel)
    local slotData = PDM.GetModule(uid, "slotEnhance")
    local currency = PDM.GetModule(uid, "currency")
    if not slotData or not currency then
        return false, "数据未加载"
    end

    partySlot = tonumber(partySlot)
    if not partySlot or partySlot < 1 or partySlot > 5 then
        return false, "无效的出战槽位"
    end
    local scrollField = SLOT_SCROLL_MAP[equipSlot]
    if not scrollField then
        return false, "无效的装备位置"
    end

    targetLevel = tonumber(targetLevel)
    if not targetLevel or targetLevel < 1 or targetLevel > MAX_ENHANCE_LV then
        return false, "无效的目标等级"
    end

    -- 目标等级不能超过当前冒险等级上限
    local enhanceCap = getEnhanceCap(uid)
    if targetLevel > enhanceCap then
        return false, "目标等级超过当前冒险等级上限（" .. enhanceCap .. "级），提升冒险等级后可继续强化"
    end

    if not slotData.levels[partySlot] then
        slotData.levels[partySlot] = {}
    end
    local currentLv = slotData.levels[partySlot][equipSlot] or 0
    if currentLv >= targetLevel then
        return false, "当前等级已达到或超过目标等级"
    end
    if currentLv >= MAX_ENHANCE_LV then
        return false, "已达最大强化等级"
    end

    -- 预计算从 currentLv+1 到 targetLevel 的总消耗
    local totalGold = 0
    local totalScroll = 0
    for lv = currentLv + 1, targetLevel do
        local cost = BlacksmithConfig.getEnhanceCost(lv)
        if not cost then
            return false, "强化配置异常 lv=" .. tostring(lv)
        end
        totalGold   = totalGold   + cost.gold
        totalScroll = totalScroll + cost.scroll
    end

    -- 校验资源总量
    if (currency.gold or 0) < totalGold then
        return false, "金币不足"
    end
    if (currency[scrollField] or 0) < totalScroll then
        return false, "卷轴不足"
    end

    -- 批量扣除资源并提升等级
    currency.gold = currency.gold - totalGold
    currency[scrollField] = currency[scrollField] - totalScroll
    slotData.levels[partySlot][equipSlot] = targetLevel

    PDM.MarkDirty(uid, "currency")
    PDM.MarkDirty(uid, "slotEnhance")

    -- 任务进度：按升级次数计算
    local levels = targetLevel - currentLv
    TaskService.UpdateProgress(uid, "enhance", levels)

    print("[BlacksmithService] ENHANCE_SLOT_MAX uid=" .. tostring(uid)
        .. " party=" .. partySlot .. " slot=" .. equipSlot
        .. " lv " .. currentLv .. "→" .. targetLevel
        .. " gold=-" .. totalGold .. " " .. scrollField .. "=-" .. totalScroll)

    return true, nil, {
        enhanceOutcome = "success",
        partySlot = partySlot,
        equipSlot = equipSlot,
        newLevel = targetLevel,
        levelsGained = levels,
    }
end

-- ======================== 洗练装备 ========================

-- 额外资源定义
-- 洗练石: "洗练时保留词缀属性种类不变，重新随机品质等级和数值（可跨等级变化）"
-- 点金石: "洗练时使用可将装备升阶，最高升到史诗品质"
local EXTRA_RES_DEFS = {
    enhanceStone = { field = "enhanceStone", cost = 1, name = "洗练石" },
    destroyStone = { field = "destroyStone", cost = nil, name = "点金石" },  -- cost 动态计算：当前品质即为消耗数
    corruptStone = { field = "corruptStone", cost = 1, name = "腐化石" },
    sacredStone = { field = "sacredStone", cost = 1, name = "神圣石" },
}

local MAX_CORRUPT_COUNT = 3
local CORRUPTED_REFINE_BLOCKED_MSG = "该装备已被腐化，无法洗练，请使用神圣石净化或继续腐化"

local function getCorruptCount(equip)
    return math.max(0, math.floor(tonumber(equip.corruptCount) or 0))
end

local function isCorruptRefineAllowed(extraResource)
    return extraResource == "corruptStone" or extraResource == "sacredStone"
end

local CORRUPT_EFFECTS = {
    { id = 1, weight = 25, name = "无变化" },
    { id = 2, weight = 20, name = "某一条词缀-50%效果" },
    { id = 3, weight = 20, name = "新增第三条词缀" },
    { id = 4, weight = 20, name = "某一条词缀+50%效果" },
    { id = 5, weight = 5,  name = "现有2条词缀+50%效果" },
    { id = 6, weight = 5,  name = "基础属性+50%效果" },
    { id = 7, weight = 5,  name = "出现魔化词条" },
}

local CORRUPT_EFFECT_TOTAL_WEIGHT = 0
for _, effect in ipairs(CORRUPT_EFFECTS) do
    CORRUPT_EFFECT_TOTAL_WEIGHT = CORRUPT_EFFECT_TOTAL_WEIGHT + effect.weight
end

local function rollCorruptEffect()
    local roll = math.random() * CORRUPT_EFFECT_TOTAL_WEIGHT
    local acc = 0
    for _, effect in ipairs(CORRUPT_EFFECTS) do
        acc = acc + effect.weight
        if roll <= acc then
            return effect
        end
    end
    return CORRUPT_EFFECTS[#CORRUPT_EFFECTS]
end

local function copyAffix(affix)
    return {
        affixId = affix.affixId,
        quality = affix.quality,
        value   = affix.value,
        key     = affix.key,
        name    = affix.name,
    }
end

local recalcBaseStatsForEquip

local function rollWeightedAffixTemplate(list, totalWeight)
    if not list or #list == 0 then return nil end
    local roll = math.random() * (totalWeight or 0)
    local acc = 0
    for _, item in ipairs(list) do
        acc = acc + (item.weight or 0)
        if roll <= acc then
            return item
        end
    end
    return list[#list]
end

local function scaleAffixValue(affix, mult)
    local copied = copyAffix(affix)
    copied.value = (tonumber(copied.value) or 0) * mult
    return copied
end

local function copyAffixList(affixes)
    local copied = {}
    for _, affix in ipairs(affixes or {}) do
        copied[#copied + 1] = copyAffix(affix)
    end
    return copied
end

--- 存档用：腐化前基础倍率（1 或 nil 不写入）
local function normalizeStoredBaseMult(mult)
    mult = tonumber(mult)
    if mult == nil or mult == 1 then return nil end
    return mult
end

--- 首次腐化前记录 revert 基线（词缀条数 + 基础倍率），不复制整份词缀
local function ensureCorruptRevertBaseline(equip)
    if equip.corruptOriginalAffixes then return end
    local rev = equip.corruptRevert
    if rev and rev.affixCount ~= nil then return end
    equip.corruptRevert = {
        baseMult = normalizeStoredBaseMult(equip.corruptBaseMult),
        affixCount = #(equip.affixes or {}),
        patches = {},
    }
end

local function findScalePatch(rev, idx)
    for _, patch in ipairs(rev.patches or {}) do
        if patch[1] == "s" and patch[2] == idx then
            return patch
        end
    end
    return nil
end

--- 改值类腐化：仅记录该条词缀「第一次被改前」的数值
local function recordScalePatchBefore(rev, idx, affix)
    if not rev or not affix or findScalePatch(rev, idx) then return end
    rev.patches[#rev.patches + 1] = { "s", idx, tonumber(affix.value) or 0 }
end

local function recordAddPatch(rev)
    if not rev then return end
    rev.patches[#rev.patches + 1] = { "a" }
end

local function hasCorruptRevertData(equip)
    if equip.corruptOriginalAffixes then return true end
    local rev = equip.corruptRevert
    return rev ~= nil and rev.affixCount ~= nil
end

local function applySacredCleanse(equip)
    -- 旧档：整份词缀快照
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
        return
    end

    local rev = equip.corruptRevert
    if not rev then return end

    local affixes = equip.affixes or {}
    for _, patch in ipairs(rev.patches or {}) do
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
    equip.affixes = affixes

    equip.corruptBaseMult = rev.baseMult
    if equip.corruptBaseMult == nil or equip.corruptBaseMult == 1 then
        equip.corruptBaseMult = nil
    end
    equip.corruptCount = nil
    equip.corruptRevert = nil
    equip.corruptOriginalBaseMult = nil
    recalcBaseStatsForEquip(equip)
end

local function buildExcludeKeysFromAffixes(affixes)
    local exclude = {}
    for _, affix in ipairs(affixes or {}) do
        if affix.key then exclude[affix.key] = true end
    end
    return exclude
end

local function appendNormalAffix(affixes, equip, qDef)
    local exclude = buildExcludeKeysFromAffixes(affixes)
    local maxAffixQ = qDef and qDef.maxAffixQuality or 1
    local randomStrength = qDef and qDef.randomStrength or 1.0
    local extra = EquipmentSystem.rollAffixes(1, maxAffixQ, equip.level or 1, exclude, randomStrength, equip.grip)
    if extra and extra[1] then
        affixes[#affixes + 1] = extra[1]
        return true
    end
    return false
end

local function appendCorruptAffix(affixes, equip)
    local exclude = buildExcludeKeysFromAffixes(affixes)
    local candidates = {}
    local totalWeight = 0
    for _, tpl in ipairs(AffixConfig.CORRUPT_AFFIXES or {}) do
        if not exclude[tpl.key] then
            candidates[#candidates + 1] = tpl
            totalWeight = totalWeight + (tpl.weight or 0)
        end
    end
    local tpl = rollWeightedAffixTemplate(candidates, totalWeight)
    if not tpl then return false end

    -- 魔化词条不吃 D~S 词缀品质增幅 / 装备 randomStrength
    local value = EquipmentSystem.calcCorruptAffixValue(tpl, equip)

    affixes[#affixes + 1] = {
        affixId = tpl.id,
        quality = 0,
        value   = value,
        key     = tpl.key,
        name    = tpl.name,
    }
    return true
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

local function buildCorruptedAffixes(equip, effect, qDef, rev)
    local source = equip.affixes or {}
    local result = {}
    for _, affix in ipairs(source) do
        result[#result + 1] = copyAffix(affix)
    end

    if effect.id == 1 then
        return result, false
    elseif effect.id == 2 then
        if #result <= 0 then return result, false end
        local idx = math.random(1, #result)
        recordScalePatchBefore(rev, idx, result[idx])
        result[idx] = scaleAffixValue(result[idx], 0.5)
        return result, true
    elseif effect.id == 3 then
        if #result >= 3 then return result, false end
        local added = appendNormalAffix(result, equip, qDef)
        if added then recordAddPatch(rev) end
        return result, added
    elseif effect.id == 4 then
        if #result <= 0 then return result, false end
        local idx = math.random(1, #result)
        recordScalePatchBefore(rev, idx, result[idx])
        result[idx] = scaleAffixValue(result[idx], 1.5)
        return result, true
    elseif effect.id == 5 then
        if #result <= 0 then return result, false end
        local indices = {}
        for i = 1, #result do indices[#indices + 1] = i end
        for i = #indices, 2, -1 do
            local j = math.random(1, i)
            indices[i], indices[j] = indices[j], indices[i]
        end
        local count = math.min(2, #indices)
        for i = 1, count do
            local idx = indices[i]
            recordScalePatchBefore(rev, idx, result[idx])
            result[idx] = scaleAffixValue(result[idx], 1.5)
        end
        return result, count > 0
    elseif effect.id == 7 then
        if #result >= 3 then return result, false end
        local added = appendCorruptAffix(result, equip)
        if added then recordAddPatch(rev) end
        return result, added
    end

    return result, false
end

--- 构建腐化效果详情（供客户端展示前后对比）
local function buildCorruptEffectDetail(effect, beforeAffixes, afterAffixes, beforeBaseMult, afterBaseMult)
    local detail = {
        effectId = effect.id,
        effectName = effect.name,
        affixChanges = {},
    }
    beforeBaseMult = tonumber(beforeBaseMult) or 1
    afterBaseMult = tonumber(afterBaseMult) or 1

    if effect.id == 1 then
        detail.summary = "本次腐化未改变词缀或基础属性"
    elseif effect.id == 6 then
        detail.baseMultChange = {
            before = beforeBaseMult,
            after = afterBaseMult,
        }
        detail.summary = "装备基础属性提升 50%"
    else
        for i = 1, math.max(#beforeAffixes, #afterAffixes) do
            local b = beforeAffixes[i]
            local a = afterAffixes[i]
            if not b and a then
                detail.affixChanges[#detail.affixChanges + 1] = {
                    index = i,
                    kind = "added",
                    affixId = a.affixId,
                    key = a.key,
                    name = a.name,
                    afterValue = tonumber(a.value) or 0,
                }
            elseif b and a then
                local bv = tonumber(b.value) or 0
                local av = tonumber(a.value) or 0
                if math.abs(av - bv) > 0.0001 then
                    detail.affixChanges[#detail.affixChanges + 1] = {
                        index = i,
                        kind = "scale",
                        affixId = a.affixId,
                        key = a.key or b.key,
                        name = a.name or b.name,
                        beforeValue = bv,
                        afterValue = av,
                    }
                end
            end
        end
        if effect.id == 2 then
            detail.summary = "随机一条词缀效果降低 50%"
        elseif effect.id == 3 then
            detail.summary = "新增一条普通词缀"
        elseif effect.id == 4 then
            detail.summary = "随机一条词缀效果提升 50%"
        elseif effect.id == 5 then
            detail.summary = "两条现有词缀效果各提升 50%"
        elseif effect.id == 7 then
            detail.summary = "新增一条魔化词条"
        end
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

--- 洗练装备（消耗精粹，可选额外资源：洗练石=只洗数值/点金石=装备升阶/腐化石=随机魔化效果/神圣石=净化腐化）
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

        -- 点金石特殊校验：装备已达当前进度允许的最高品质
        if extraResource == "destroyStone" then
            local maxQ = getUpgradeMaxQuality(uid)
            if q >= maxQ then
                local qName = EquipmentConfig.QUALITY[maxQ] and EquipmentConfig.QUALITY[maxQ].name or "最高"
                return false, "装备已达" .. qName .. "品质，无法再升阶"
            end
        end

        -- 洗练石特殊校验：装备必须有词缀才能洗数值
        if extraResource == "enhanceStone" then
            if not qDef or (qDef.affixCount or 0) <= 0 then
                return false, "该品质装备无词缀，无法使用洗练石"
            end
            if not equip.affixes or #equip.affixes == 0 then
                return false, "装备无词缀，无法使用洗练石"
            end
        end

        -- 腐化石特殊校验：装备最多腐化 3 次
        if extraResource == "corruptStone" then
            local currentCorruptCount = math.max(0, math.floor(tonumber(equip.corruptCount) or 0))
            if currentCorruptCount >= MAX_CORRUPT_COUNT then
                return false, "该装备已腐化3次，需要先使用神圣石净化"
            end
        end

        -- 神圣石特殊校验：只净化已腐化装备
        if extraResource == "sacredStone" then
            local currentCorruptCount = math.max(0, math.floor(tonumber(equip.corruptCount) or 0))
            if currentCorruptCount <= 0 then
                return false, "该装备未处于腐化状态"
            end
            if not hasCorruptRevertData(equip) then
                return false, "该装备缺少腐化前记录，无法净化"
            end
        end
    end

    local corruptCount = getCorruptCount(equip)
    if corruptCount > 0 and not isCorruptRefineAllowed(extraResource) then
        return false, CORRUPTED_REFINE_BLOCKED_MSG
    end

    -- 神圣石：净化腐化状态，不消耗精粹，不增加洗练次数
    if extraResource == "sacredStone" then
        currency.sacredStone = (currency.sacredStone or 0) - 1
        applySacredCleanse(equip)

        if pendingRefines[uid] then
            pendingRefines[uid][seqStr] = nil
        end

        PDM.MarkDirty(uid, "currency")
        PDM.MarkDirty(uid, "equipment")
        PDM.FlushImmediate(uid)

        print("[BlacksmithService] REFINE+CLEANSE uid=" .. tostring(uid)
            .. " seq=" .. seqStr .. " sacredStone=-1")

        return true, nil, {
            refinePreview = equip.affixes,
            refineSeq = seq,
            autoReplaced = true,
            cleansed = true,
            corruptCount = 0,
            corruptBaseMult = equip.corruptBaseMult,
            newQuality = equip.quality,
        }
    end

    -- 非点金石/神圣石洗练时，装备本身必须有词缀
    if extraResource ~= "destroyStone" and extraResource ~= "sacredStone" then
        if not qDef or (qDef.affixCount or 0) <= 0 then
            return false, "该品质装备无法洗练"
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

    local essenceCost = BlacksmithConfig.calcRefineEssenceCost(q, equipLv, refineCount, equip.grip)
    if extraResource ~= "destroyStone" and extraResource ~= "corruptStone" then
        essenceCost = BlacksmithConfig.applyRefineLockCostMult(essenceCost, lockedCount)
    end

    if (currency.essence or 0) < essenceCost then
        return false, "精粹不足"
    end

    -- 扣精粹 & 累计洗练次数（上限 20，之后仍可洗练但不再涨消耗）
    currency.essence = currency.essence - essenceCost
    equip.refineCount = BlacksmithConfig.nextRefineCount(refineCount)

    -- 扣额外资源（点金石消耗=当前品质，洗练石=固定1）
    if extraDef then
        local actualCost = extraDef.cost or q  -- 点金石 cost=nil 时使用当前品质
        currency[extraDef.field] = (currency[extraDef.field] or 0) - actualCost
    end

    -- === 根据额外资源类型决定效果 ===

    local newAffixes
    local upgradedQuality = nil    -- 仅点金石时非 nil
    local corruptEffect = nil      -- 仅腐化石时非 nil
    local corruptBeforeAffixes = nil
    local corruptBaseMultBefore = nil
    local extraLog = ""

    local excludeKeys = {}

    if extraResource == "enhanceStone" then
        local maxAffixQ = qDef.maxAffixQuality
        local randomStrength = qDef.randomStrength or 1.0
        newAffixes = EquipmentSystem.rerollAffixValuesWithLocks(
            equip.affixes, maxAffixQ, equipLv, randomStrength, equip.grip, lockedSet)
        extraLog = " extra=洗练石(rerollValues)"
        if lockedCount > 0 then
            extraLog = extraLog .. " locked=" .. lockedCount
        end

    elseif extraResource == "destroyStone" then
        -- ── 点金石：装备升阶 +1，保留原有词缀不变 ──
        local maxQ = getUpgradeMaxQuality(uid)
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
            -- 补充生成缺少的词缀
            local extraAffixes = EquipmentSystem.rollAffixes(
                newAffixCount - #newAffixes, maxAffixQ, equipLv, excludeKeys, randomStrength, equip.grip
            )
            for _, af in ipairs(extraAffixes) do
                newAffixes[#newAffixes + 1] = af
            end
        end
        upgradedQuality = newQ
        extraLog = " extra=点金石(upgrade " .. q .. "→" .. newQ .. " maxQ=" .. maxQ .. " affixes=" .. #newAffixes .. ")"

    elseif extraResource == "corruptStone" then
        -- ── 腐化石：随机魔化效果，直接应用结果 ──
        ensureCorruptRevertBaseline(equip)
        local corruptRev = equip.corruptRevert
        corruptBeforeAffixes = copyAffixList(equip.affixes)
        corruptBaseMultBefore = tonumber(equip.corruptBaseMult) or 1
        corruptEffect = rollCorruptEffect()
        if corruptEffect.id == 6 then
            newAffixes = copyAffixList(equip.affixes)
            equip.corruptBaseMult = corruptBaseMultBefore * 1.5
            recalcBaseStatsForEquip(equip)
        else
            newAffixes = buildCorruptedAffixes(equip, corruptEffect, qDef, corruptRev)
        end
        extraLog = " extra=腐化石(effect=" .. tostring(corruptEffect.id) .. ":" .. corruptEffect.name .. ")"

    else
        -- ── 普通洗练：未锁定槽重随机 ──
        local maxAffixQ  = qDef.maxAffixQuality
        local normalRandomStrength = qDef.randomStrength or 1.0
        newAffixes = EquipmentSystem.rollAffixesForRefine(
            equip.affixes, lockedSet, maxAffixQ, equipLv, normalRandomStrength, equip.grip)
        if lockedCount > 0 then
            extraLog = " locked=" .. lockedCount
        end
    end

    -- 点金石：直接应用结果（无需手动点替换）
    if extraResource == "destroyStone" then
        equip.affixes = newAffixes
        equip.quality = upgradedQuality

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
            autoReplaced = true,
            newQuality = upgradedQuality,
        }
    end

    -- 腐化石：直接应用随机魔化结果（无需手动点替换）
    if extraResource == "corruptStone" then
        equip.affixes = newAffixes
        equip.corruptCount = math.min(MAX_CORRUPT_COUNT, math.max(0, math.floor(tonumber(equip.corruptCount) or 0)) + 1)

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
        local corruptEffectDetail = buildCorruptEffectDetail(
            corruptEffect,
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
            corruptEffectId = corruptEffect and corruptEffect.id or nil,
            corruptEffectName = corruptEffect and corruptEffect.name or nil,
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

    -- 点金石升阶：更新装备品质 + 重算基础属性
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

--- 批量分解装备（获得精粹 + 强化金币返还）
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

    -- 验证所有装备存在且未穿戴
    local toRemove = {}
    for _, seq in ipairs(seqs) do
        seq = tonumber(seq)
        if not seq then
            return false, "无效的装备序列号"
        end
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
    local totalEssence = 0
    local totalRefineReturn = 0
    for _, item in ipairs(toRemove) do
        local equip = item.equip
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
    end
    totalEssence = totalEssence + totalRefineReturn

    -- 执行分解
    for _, item in ipairs(toRemove) do
        EquipmentSystem.removeFromInventory(equipData, item.seq)
    end
    currency.essence = (currency.essence or 0) + totalEssence

    PDM.MarkDirty(uid, "equipment")
    PDM.MarkDirty(uid, "currency")

    print("[BlacksmithService] DECOMPOSE uid=" .. tostring(uid)
        .. " count=" .. #toRemove
        .. " essence=+" .. totalEssence
        .. " (base=" .. (totalEssence - totalRefineReturn) .. " refineReturn=" .. totalRefineReturn .. ")")

    -- 任务进度
    TaskService.UpdateProgress(uid, "decompose", #toRemove)

    return true, nil, {
        decomposed = true,
        decomposeCount = #toRemove,
        essenceReward = totalEssence,
        refineReturn = totalRefineReturn,
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
