-- ============================================================================
-- ArtifactDefs.lua — 神器定义与抽取配置（双端共享）
-- ============================================================================

local ArtifactDefs = {}

ArtifactDefs.DRAW_KEY_COST = {
    [1] = 1,
    [10] = 10,
}

--- 黄金钥匙不足时，钻石快速购买单价
ArtifactDefs.KEY_DIAMOND_PRICE = 600

---@deprecated 旧版纯钻石消耗，保留兼容引用
ArtifactDefs.DRAW_COST = {
    [1] = 400,
    [10] = 4000,
}

ArtifactDefs.PITY_RARE = 20
ArtifactDefs.PITY_EPIC = 100
ArtifactDefs.MAX_BAG = 300

ArtifactDefs.QUALITY_RATE = {
    { quality = 1, weight = 75 },
    { quality = 2, weight = 20 },
    { quality = 3, weight = 4 },
    { quality = 4, weight = 1 },
}

ArtifactDefs.QUALITY_NAMES = {
    [1] = "普通",
    [2] = "优质",
    [3] = "稀有",
    [4] = "史诗",
    [5] = "传说",
    [6] = "至臻",
}

ArtifactDefs.QUALITY_COLORS = {
    [1] = { 181, 181, 181 },
    [2] = { 162, 255, 148 },
    [3] = { 114, 242, 245 },
    [4] = { 239, 121, 255 },
    [5] = { 255, 237, 0 },
    [6] = { 255, 0, 0 },
}

ArtifactDefs.ARTIFACTS = {
    [1] = {
        name = "影羽斗篷", minQuality = 1, weight = 100, effectType = "dodge_decay",
        desc = "进入战斗时额外闪避值加成固定+200%；每次触发闪避后，仅减少本次进入战斗获得的额外闪避值加成X%，使该额外加成逐步降低，最低降至0，不影响角色原有闪避值",
        ranges = { [1]={150,100}, [2]={100,75}, [3]={75,55}, [4]={55,38}, [5]={38,25}, [6]={25,15} },
    },
    [2] = {
        name = "星辉护符", minQuality = 1, weight = 100, effectType = "shield_threat_clear",
        desc = "能量护盾加成额外增加X%，能量护盾破碎后，清除当前Y%的仇恨值",
        ranges = { [1]={8,12}, [2]={14,20}, [3]={22,32}, [4]={36,52}, [5]={60,85}, [6]={100,140} },
        threatClearRanges = { [1]={10,15}, [2]={16,22}, [3]={24,34}, [4]={36,48}, [5]={50,65}, [6]={70,90} },
    },
    [3] = {
        name = "生命棱镜", minQuality = 1, weight = 100, effectType = "hp_to_shield",
        desc = "将50%的生命值按X%比例转化为最大护盾",
        ranges = { [1]={80,95}, [2]={95,115}, [3]={115,145}, [4]={145,185}, [5]={185,240}, [6]={240,320} },
    },
    [4] = {
        name = "命运纺锤", minQuality = 1, weight = 100, effectType = "ignore_armor_armor_penalty",
        desc = "无视敌人所有护甲，但护甲加成-X%",
        ranges = { [1]={80,70}, [2]={70,60}, [3]={60,50}, [4]={50,40}, [5]={40,30}, [6]={30,20} },
    },
    [5] = {
        name = "巨人之铠", minQuality = 1, weight = 100, effectType = "counter_attack",
        desc = "受到伤害时有50%概率立即反击，造成X%攻击的伤害",
        ranges = { [1]={30,40}, [2]={45,60}, [3]={65,85}, [4]={90,120}, [5]={130,170}, [6]={180,240} },
    },
    [6] = {
        name = "神圣十架", minQuality = 4, weight = 100, effectType = "revive_damage_bonus",
        desc = "在战斗中首次死亡时，以50%生命值复活，并在复活后额外伤害+X%",
        ranges = { [4]={5,8}, [5]={8,12}, [6]={12,18} },
    },
    [7] = {
        name = "左誓战旗", minQuality = 1, weight = 100, effectType = "left_phys_atk_bonus",
        desc = "使左槽位的友方冒险家物理攻击加成+X%",
        ranges = { [1]={8,12}, [2]={12,18}, [3]={18,26}, [4]={28,40}, [5]={42,58}, [6]={60,80} },
    },
    [8] = {
        name = "右誓法典", minQuality = 1, weight = 100, effectType = "right_mag_atk_bonus",
        desc = "使右槽位的友方冒险家魔法攻击加成+X%",
        ranges = { [1]={8,12}, [2]={12,18}, [3]={18,26}, [4]={28,40}, [5]={42,58}, [6]={60,80} },
    },
    [9] = {
        name = "血誓圣杯", minQuality = 1, weight = 100, effectType = "hp_bonus_no_heal",
        desc = "巨额生命加成额外+X%，无法再以任何形式恢复生命值",
        ranges = { [1]={45,60}, [2]={70,100}, [3]={115,160}, [4]={180,250}, [5]={280,380}, [6]={450,600} },
    },
    [10] = {
        name = "亡魂之祭", minQuality = 4, weight = 100, effectType = "ghost_damage_bonus",
        desc = "死亡时在10秒内变亡魂状态，亡魂状态下无法被攻击选中，亡魂状态额外增加X%伤害加成",
        ranges = { [4]={55,75}, [5]={85,110}, [6]={125,160} },
    },
    [11] = {
        name = "嘲讽面具", minQuality = 1, weight = 100, effectType = "taunt_mask",
        desc = "额外伤害+X，额外获得X的2倍仇恨值",
        ranges = { [1]={20,30}, [2]={32,48}, [3]={52,75}, [4]={80,115}, [5]={125,170}, [6]={185,250} },
    },
    [12] = {
        name = "神徒之骰", minQuality = 1, weight = 100, effectType = "crit_dmg_mult_rate_half",
        desc = "暴击伤害xX%，但暴击概率/2",
        ranges = { [1]={160,180}, [2]={180,210}, [3]={210,250}, [4]={250,300}, [5]={300,360}, [6]={360,430} },
    },
    [13] = {
        name = "狂怒沙漏", minQuality = 1, weight = 100, effectType = "slow_attack_damage_bonus",
        desc = "攻击间隔延长50%，但额外伤害+X%",
        ranges = { [1]={55,65}, [2]={65,80}, [3]={80,100}, [4]={100,130}, [5]={130,170}, [6]={170,230} },
    },
    [14] = {
        name = "审判官之锤", minQuality = 1, weight = 100, effectType = "judgment_res_down",
        desc = "每次攻击命中同一目标，该目标对你造成的该次攻击对应伤害类型的抗性 -X%（最多叠加8层，单目标有效）。切换目标时层数清零",
        ranges = { [1]={1,2}, [2]={2,3}, [3]={3,4}, [4]={4,6}, [5]={6,8}, [6]={8,12} },
    },
    [15] = {
        name = "魔王之瞳", minQuality = 6, weight = 50, effectType = "chaos_damage",
        desc = "你的所有伤害类型变为混沌伤害：同时享受物理和魔法的穿透与加成，不受任何护甲克制关系影响（对所有护甲类型造成 X% 伤害），适合同时拥有双系穿透或双系伤害加成的角色。同时，你的所有护甲/抗性/格挡相关属性无效",
        ranges = { [6]={100,120} },
    },
    [16] = {
        name = "双生壁垒", minQuality = 4, weight = 100, effectType = "block_cap_up",
        desc = "将物理/魔法格挡率上限率提升至X，可进行多次格挡",
        ranges = { [4]={130,150}, [5]={150,180}, [6]={180,230} },
    },
}

function ArtifactDefs.get(id)
    return ArtifactDefs.ARTIFACTS[tonumber(id)]
end

function ArtifactDefs.getQualityName(quality)
    return ArtifactDefs.QUALITY_NAMES[tonumber(quality) or 1] or "普通"
end

function ArtifactDefs.getQualityColor(quality)
    return ArtifactDefs.QUALITY_COLORS[tonumber(quality) or 1] or ArtifactDefs.QUALITY_COLORS[1]
end

function ArtifactDefs.getRange(artifactId, quality)
    local def = ArtifactDefs.get(artifactId)
    if not def or not def.ranges then return nil end
    return def.ranges[tonumber(quality) or 1]
end

function ArtifactDefs.valueToRatio(artifactId, quality, value)
    local range = ArtifactDefs.getRange(artifactId, quality)
    value = tonumber(value) or 0
    if not range then return 0 end
    local a, b = tonumber(range[1]) or 0, tonumber(range[2]) or 0
    local lo, hi = math.min(a, b), math.max(a, b)
    if hi <= lo then return 0 end
    local ratio = (value - lo) / (hi - lo)
    ratio = math.max(0, math.min(1, ratio))
    return math.floor(ratio * 10000 + 0.5)
end

function ArtifactDefs.ratioToValue(artifactId, quality, ratio)
    local range = ArtifactDefs.getRange(artifactId, quality)
    ratio = math.max(0, math.min(10000, math.floor(tonumber(ratio) or 0)))
    if not range then return 0 end
    local a, b = tonumber(range[1]) or 0, tonumber(range[2]) or 0
    local lo, hi = math.min(a, b), math.max(a, b)
    local value = lo + (hi - lo) * ratio / 10000
    return math.floor(value * 10 + 0.5) / 10
end

function ArtifactDefs.rollValueRatio()
    return math.random(0, 10000)
end

function ArtifactDefs.rollValue(artifactId, quality)
    return ArtifactDefs.ratioToValue(artifactId, quality, ArtifactDefs.rollValueRatio())
end

function ArtifactDefs.threatClearValueToRatio(artifactId, quality, value)
    local def = ArtifactDefs.get(artifactId)
    local range = def and def.threatClearRanges and def.threatClearRanges[tonumber(quality) or 1]
    value = tonumber(value) or 0
    if not range then return nil end
    local a, b = tonumber(range[1]) or 0, tonumber(range[2]) or 0
    local lo, hi = math.min(a, b), math.max(a, b)
    if hi <= lo then return 0 end
    local ratio = (value - lo) / (hi - lo)
    ratio = math.max(0, math.min(1, ratio))
    return math.floor(ratio * 10000 + 0.5)
end

function ArtifactDefs.threatClearRatioToValue(artifactId, quality, ratio)
    local def = ArtifactDefs.get(artifactId)
    local range = def and def.threatClearRanges and def.threatClearRanges[tonumber(quality) or 1]
    if not range then return nil end
    ratio = math.max(0, math.min(10000, math.floor(tonumber(ratio) or 0)))
    local a, b = tonumber(range[1]) or 0, tonumber(range[2]) or 0
    local lo, hi = math.min(a, b), math.max(a, b)
    local value = lo + (hi - lo) * ratio / 10000
    return math.floor(value * 10 + 0.5) / 10
end

function ArtifactDefs.rollThreatClearValueRatio(artifactId, quality)
    local def = ArtifactDefs.get(artifactId)
    local range = def and def.threatClearRanges and def.threatClearRanges[tonumber(quality) or 1]
    if not range then return nil end
    return math.random(0, 10000)
end

function ArtifactDefs.rollThreatClearValue(artifactId, quality)
    return ArtifactDefs.threatClearRatioToValue(artifactId, quality, ArtifactDefs.rollThreatClearValueRatio(artifactId, quality))
end

function ArtifactDefs.clampValueToRange(artifactId, quality, value)
    local range = ArtifactDefs.getRange(artifactId, quality)
    value = tonumber(value) or 0
    if not range then return value end
    local a, b = tonumber(range[1]) or 0, tonumber(range[2]) or 0
    local lo, hi = math.min(a, b), math.max(a, b)
    return math.max(lo, math.min(hi, value))
end

function ArtifactDefs.clampThreatClearValueToRange(artifactId, quality, value)
    local def = ArtifactDefs.get(artifactId)
    local range = def and def.threatClearRanges and def.threatClearRanges[tonumber(quality) or 1]
    if not range then return nil end
    value = tonumber(value) or 0
    local a, b = tonumber(range[1]) or 0, tonumber(range[2]) or 0
    local lo, hi = math.min(a, b), math.max(a, b)
    return math.max(lo, math.min(hi, value))
end

function ArtifactDefs.normalizeInstanceValue(artifact)
    if not artifact then return nil end
    local artifactId = tonumber(artifact.artifactId or artifact.id)
    local quality = tonumber(artifact.quality) or 1

    if artifact.valueRatio == nil and artifact.r ~= nil then
        artifact.valueRatio = artifact.r
    end
    if artifact.valueRatio == nil then
        artifact.valueRatio = ArtifactDefs.valueToRatio(artifactId, quality, artifact.value)
    else
        artifact.valueRatio = math.max(0, math.min(10000, math.floor(tonumber(artifact.valueRatio) or 0)))
    end
    artifact.value = ArtifactDefs.ratioToValue(artifactId, quality, artifact.valueRatio)

    if artifact.threatClearRatio == nil and artifact.tr ~= nil then
        artifact.threatClearRatio = artifact.tr
    end
    if artifact.threatClearValue ~= nil and artifact.threatClearRatio == nil then
        artifact.threatClearRatio = ArtifactDefs.threatClearValueToRatio(artifactId, quality, artifact.threatClearValue)
    end
    if artifact.threatClearRatio ~= nil then
        artifact.threatClearRatio = math.max(0, math.min(10000, math.floor(tonumber(artifact.threatClearRatio) or 0)))
        artifact.threatClearValue = ArtifactDefs.threatClearRatioToValue(artifactId, quality, artifact.threatClearRatio)
    elseif artifact.threatClearValue ~= nil then
        artifact.threatClearValue = ArtifactDefs.clampThreatClearValueToRange(artifactId, quality, artifact.threatClearValue) or artifact.threatClearValue
    end
    return artifact
end

function ArtifactDefs.getThreatClearValue(artifact)
    if not artifact then return nil end
    if artifact.threatClearValue ~= nil then return tonumber(artifact.threatClearValue) or 0 end
    if artifact.threatClear ~= nil then return tonumber(artifact.threatClear) or 0 end
    local def = ArtifactDefs.get(artifact.artifactId or artifact.id)
    local quality = tonumber(artifact.quality) or 1
    local range = def and def.threatClearRanges and def.threatClearRanges[quality]
    if not range then return nil end
    local a, b = tonumber(range[1]) or 0, tonumber(range[2]) or 0
    return (a + b) * 0.5
end

function ArtifactDefs.formatValue(value)
    value = tonumber(value) or 0
    if math.abs(value - math.floor(value + 0.5)) < 0.01 then
        return tostring(math.floor(value + 0.5)) .. "%"
    end
    return string.format("%.1f%%", value)
end

local ARTIFACT_POWER_BASE = {
    [1] = 120,
    [2] = 200,
    [3] = 350,
    [4] = 650,
    [5] = 1100,
    [6] = 2000,
}

local ARTIFACT_POWER_SPREAD = {
    [1] = 35,
    [2] = 60,
    [3] = 110,
    [4] = 200,
    [5] = 340,
    [6] = 620,
}

local ARTIFACT_POWER_NEGATIVE_FACTOR = {
    ignore_armor_armor_penalty = 0.85,
    hp_bonus_no_heal = 0.75,
    crit_dmg_mult_rate_half = 0.85,
    slow_attack_damage_bonus = 0.85,
    chaos_damage = 0.70,
}

local function getRangeRatio(artifactId, quality, value)
    local range = ArtifactDefs.getRange(artifactId, quality)
    if not range then return 0.5 end
    local a, b = tonumber(range[1]) or 0, tonumber(range[2]) or 0
    local lo, hi = math.min(a, b), math.max(a, b)
    if hi <= lo then return 0.5 end
    return math.max(0, math.min(1, ((tonumber(value) or lo) - lo) / (hi - lo)))
end

function ArtifactDefs.getPower(artifact)
    if not artifact then return 0 end
    local explicit = tonumber(artifact.power or artifact.strength or artifact.combatPower)
    if explicit then return math.floor(explicit + 0.5) end

    local artifactId = artifact.artifactId or artifact.id
    local def = ArtifactDefs.get(artifactId)
    local quality = math.max(1, math.min(tonumber(artifact.quality) or 1, 6))
    local value = tonumber(artifact.value) or 0
    local base = ARTIFACT_POWER_BASE[quality] or quality * 120
    local spread = ARTIFACT_POWER_SPREAD[quality] or 50
    local ratio = getRangeRatio(artifactId, quality, value)
    local factor = ARTIFACT_POWER_NEGATIVE_FACTOR[def and def.effectType or nil] or 1.0
    local power = (base + spread * ratio) * factor
    return math.max(0, math.floor(power + 0.5))
end

function ArtifactDefs.getEffectText(artifact)
    if not artifact then return "" end
    local def = ArtifactDefs.get(artifact.artifactId or artifact.id)
    if not def then return "" end
    local desc = def.desc or ""
    local value = ArtifactDefs.formatValue(artifact.value)
    desc = desc:gsub("X%%", function() return value end)
    desc = desc:gsub("X", function() return value end)
    local threatClearValue = ArtifactDefs.getThreatClearValue(artifact)
    if threatClearValue ~= nil then
        local clearValueText = ArtifactDefs.formatValue(threatClearValue)
        desc = desc:gsub("Y%%", function() return clearValueText end)
        desc = desc:gsub("Y", function() return clearValueText end)
    end
    return desc
end

function ArtifactDefs.getName(artifact)
    local def = artifact and ArtifactDefs.get(artifact.artifactId or artifact.id)
    return def and def.name or "未知神器"
end

function ArtifactDefs.getEligibleIds(quality)
    quality = tonumber(quality) or 1
    local ids = {}
    for id, def in pairs(ArtifactDefs.ARTIFACTS) do
        if quality >= (def.minQuality or 1) and def.ranges and def.ranges[quality] then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function ArtifactDefs.rollArtifactIdExcept(quality, excludedIds)
    local excluded = {}
    for _, id in ipairs(excludedIds or {}) do
        excluded[tonumber(id)] = true
    end
    local ids = {}
    for _, id in ipairs(ArtifactDefs.getEligibleIds(quality)) do
        if not excluded[tonumber(id)] then
            ids[#ids + 1] = id
        end
    end
    if #ids == 0 then return nil end
    local total = 0
    for _, id in ipairs(ids) do
        total = total + (ArtifactDefs.ARTIFACTS[id].weight or 100)
    end
    local roll = math.random() * total
    local acc = 0
    for _, id in ipairs(ids) do
        acc = acc + (ArtifactDefs.ARTIFACTS[id].weight or 100)
        if roll <= acc then return id end
    end
    return ids[#ids]
end

--- 置换专用：优先产出背包中尚未拥有的类型，其次数量最少的类型
---@param quality number
---@param excludedIds number[] 被消耗的类型，不可重复产出
---@param typeCounts table<number, number>|nil 置换消耗后背包内各类型数量（artifactId -> count）
---@return number|nil
function ArtifactDefs.rollArtifactIdForReroll(quality, excludedIds, typeCounts)
    local excluded = {}
    for _, id in ipairs(excludedIds or {}) do
        excluded[tonumber(id)] = true
    end
    local candidates = {}
    for _, id in ipairs(ArtifactDefs.getEligibleIds(quality)) do
        if not excluded[id] then
            candidates[#candidates + 1] = id
        end
    end
    if #candidates == 0 then return nil end

    typeCounts = typeCounts or {}
    local minCount = math.huge
    for _, id in ipairs(candidates) do
        local c = typeCounts[id] or 0
        if c < minCount then
            minCount = c
        end
    end

    local preferred = {}
    for _, id in ipairs(candidates) do
        if (typeCounts[id] or 0) == minCount then
            preferred[#preferred + 1] = id
        end
    end

    local total = 0
    for _, id in ipairs(preferred) do
        total = total + (ArtifactDefs.ARTIFACTS[id].weight or 100)
    end
    local roll = math.random() * total
    local acc = 0
    for _, id in ipairs(preferred) do
        acc = acc + (ArtifactDefs.ARTIFACTS[id].weight or 100)
        if roll <= acc then return id end
    end
    return preferred[#preferred]
end

function ArtifactDefs.rollArtifactId(quality)
    local ids = ArtifactDefs.getEligibleIds(quality)
    if #ids == 0 then return nil end
    local total = 0
    for _, id in ipairs(ids) do
        total = total + (ArtifactDefs.ARTIFACTS[id].weight or 100)
    end
    local roll = math.random() * total
    local acc = 0
    for _, id in ipairs(ids) do
        acc = acc + (ArtifactDefs.ARTIFACTS[id].weight or 100)
        if roll <= acc then return id end
    end
    return ids[#ids]
end

return ArtifactDefs
