---@diagnostic disable: param-type-mismatch
------------------------------------------------------------------------
-- CharacterDetailAttrs.lua  —— 角色属性收集模块
-- 从 CharacterDetail.lua 拆分出来
-- 职责：属性排序定义 + collectAttributes 函数
------------------------------------------------------------------------
local HC               = require("config.HeroConfig")
local AD               = require("systems.AttributeDef")
local PlayerStore      = require("core.PlayerStore")
local ClientDispatcher = require("runtime.ClientDispatcher")
local EquipmentConfig  = require("config.EquipmentConfig")
local EquipmentSystem  = require("systems.EquipmentSystem")
local ArtifactBridge   = require("systems.ArtifactBridge")
local EquipmentSetSystem = require("systems.EquipmentSetSystem")
local EquipmentSetRuntime = require("systems.EquipmentSetRuntime")
local UnitAttributes = require("systems.UnitAttributes")
local AttributeView = require("ui.character.detail.CharacterAttributeView")
local CF = require("systems.CombatFormula")

local M = {}

-- 预览只在快照上水合/规范化；保留数字键和共享引用，不经 JSON 往返。
local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do copy[deepCopy(key, seen)] = deepCopy(item, seen) end
    return copy
end

-- 原始存档保留固定槽位；有 teams 时不借陈旧 deployed 队1数据。
local function getTeamSlotIds(heroesData, teamIdx)
    if heroesData and type(heroesData.teams) == "table" then
        local team = heroesData.teams[teamIdx] or heroesData.teams[tostring(teamIdx)]
        return (team and team.slots) or {}
    end
    if teamIdx == 1 then return (heroesData and heroesData.deployed) or {} end
    return {}
end

-- 神器与星门共用所属队解析；只有无 teams 的旧档才兼容 deployed。
local function findArtifactPosition(heroesData, heroId)
    local targetId = tonumber(heroId)
    if not targetId or targetId <= 0 then return nil, nil end
    for teamIdx = 1, 3 do
        local ids = getTeamSlotIds(heroesData, teamIdx)
        for slot = 1, 4 do
            local id = ids[slot] or ids[tostring(slot)]
            if tonumber(id) == targetId then return slot, teamIdx end
        end
    end
    return nil, nil
end

-- ======================== 属性排序定义 ========================

--- 左列固定候选属性（包含 0/默认值；兼容别名按实际 key 去重）
M.ATTR_LEFT_PRIORITY = {
    AD.MAX_HP,
    AD.PHYS_ARMOR,
    AD.MAG_ARMOR,
    AD.DODGE,
    AD.HIT_VALUE,
    AD.HP_REGEN,
    AD.ATK_HEAL,
    AD.THREAT,
    AD.PHYS_BLOCK_RATE,
    AD.PHYS_BLOCK_RATIO,
    AD.MAG_BLOCK_RATE,
    AD.MAG_BLOCK_RATIO,
    AD.ABNORMAL_RES,
    AD.HP_BONUS,
    AD.ARMOR_BONUS,
    AD.DODGE_BONUS,
    AD.ES_BONUS,
    AD.FINAL_HP_BONUS,
    AD.FINAL_ARMOR_BONUS,
    AD.FINAL_ENERGY_SHIELD_BONUS,
    AD.FINAL_DODGE_BONUS,
    AD.DROP_LUCK,
}

--- 右列候选属性（前3个为特殊显示：攻击类型/攻击间隔/攻击目标，不走 AD.META）
M.ATTR_RIGHT_SPECIAL = { "atkTypeName", "atkInterval", "atkTargets" }

M.ATTR_RIGHT_PRIORITY = {
    AD.ATK_SPEED,
    AD.CRIT_RATE,
    AD.CRIT_DMG,
    AD.PHYS_CRIT_RATE,
    AD.PHYS_CRIT_DMG,
    AD.MAG_CRIT_RATE,
    AD.MAG_CRIT_DMG,
    AD.PHYS_PEN,
    AD.MAG_PEN,
    AD.DMG_BONUS,
    AD.PHYS_DMG_BONUS,
    AD.MAG_DMG_BONUS,
    AD.COMBO_RATE,
    AD.COMBO_DMG_UP,
    AD.ADVANTAGE_DMG_BONUS,
    AD.DISADVANTAGE_DMG_BONUS,
    AD.PHYS_ATK_BONUS,
    AD.MAG_ATK_BONUS,
    AD.FINAL_PHYS_ATK_BONUS,
    AD.FINAL_MAG_ATK_BONUS,
    AD.FINAL_DAMAGE_BONUS,
    AD.FINAL_STR_BONUS,
    AD.FINAL_AGI_BONUS,
    AD.FINAL_INT_BONUS,
    AD.FINAL_VIT_BONUS,
    AD.FINAL_LUK_BONUS,
    AD.FINAL_SPI_BONUS,
    AD.HEAL_AMOUNT,
    AD.HEAL_BONUS,
    AD.HEAL_CRIT_RATE,
    AD.HEAL_CRIT_DMG,
}

-- ======================== 面板展示排序（重要程度优先） ========================
-- 合并左右列后按此顺序展示；未列出的属性保持原有相对顺序排在最后。
M.ATTR_DISPLAY_ORDER = {
    -- 核心战斗
    AD.MAX_HP,
    AD.PHYS_ATK, AD.MAG_ATK, AD.HEAL_AMOUNT,   -- 本职攻击/治疗
    AD.ATK_SPEED,
    "_effCritRate", "_effCritDmg",
    AD.COMBO_RATE, AD.COMBO_DMG_UP,
    -- 输出向
    AD.PHYS_PEN, AD.MAG_PEN,
    AD.PHYS_DMG_BONUS, AD.MAG_DMG_BONUS, AD.DMG_BONUS, AD.FINAL_DAMAGE_BONUS,
    AD.ADVANTAGE_DMG_BONUS, AD.DISADVANTAGE_DMG_BONUS,
    -- 防御核心
    AD.ARMOR, AD.RESISTANCE, AD.ENERGY_SHIELD,
    -- 生存/辅助
    AD.HIT_VALUE, AD.DODGE,
    AD.PHYS_BLOCK_RATE, AD.MAG_BLOCK_RATE, AD.PHYS_BLOCK_RATIO, AD.MAG_BLOCK_RATIO,
    AD.ABNORMAL_RES, AD.HP_REGEN, AD.ATK_HEAL, AD.THREAT,
    -- 加成/最终类
    AD.ARMOR_BONUS, AD.FINAL_ARMOR_BONUS,
    AD.ES_BONUS, AD.FINAL_ENERGY_SHIELD_BONUS,
    AD.DODGE_BONUS, AD.FINAL_DODGE_BONUS,
    AD.HP_BONUS, AD.FINAL_HP_BONUS,
    AD.PHYS_ATK_BONUS, AD.MAG_ATK_BONUS, AD.FINAL_PHYS_ATK_BONUS, AD.FINAL_MAG_ATK_BONUS,
    AD.HEAL_BONUS, AD.HEAL_CRIT_RATE, AD.HEAL_CRIT_DMG,
    AD.FINAL_STR_BONUS, AD.FINAL_AGI_BONUS, AD.FINAL_INT_BONUS,
    AD.FINAL_VIT_BONUS, AD.FINAL_LUK_BONUS, AD.FINAL_SPI_BONUS,
    -- 探索属性独立展示，不混入六围或战斗伤害。
    AD.DROP_LUCK,
    -- 基础信息
    "_atkType", AD.ATK_INTERVAL, "_atkTargets",
    -- 特殊机制/神器
    "_melissaStarGateResonance", "_melissaStarGatePen",
    "_artifactCritRateMult", "_artifactCritDmgMult", "_artifactIgnoreArmor",
    "_artifactChaosDamage", "_artifactExtraDamage", "_artifactBlockCap", "_artifactNoHeal",
}

-- 最终乘区已计入生命、攻击与六围的实际值；总属性列表不重复展示中间倍率。
-- 属性收集仍保留完整数据，装备来源与只读预览不能丢失这些词条。
local HIDDEN_DISPLAY_KEYS = {
    [AD.FINAL_HP_BONUS] = true, [AD.FINAL_ARMOR_BONUS] = true,
    [AD.FINAL_ENERGY_SHIELD_BONUS] = true, [AD.FINAL_DODGE_BONUS] = true,
    [AD.FINAL_PHYS_ATK_BONUS] = true, [AD.FINAL_MAG_ATK_BONUS] = true,
    [AD.FINAL_DAMAGE_BONUS] = true,
    [AD.FINAL_STR_BONUS] = true, [AD.FINAL_AGI_BONUS] = true,
    [AD.FINAL_INT_BONUS] = true, [AD.FINAL_VIT_BONUS] = true,
    [AD.FINAL_LUK_BONUS] = true, [AD.FINAL_SPI_BONUS] = true,
}

--- 仅过滤显示行，不修改源数组、属性容器或装备预览差值。
function M.filterDisplayRows(rows)
    local visible = {}
    for _, row in ipairs(rows or {}) do
        if not HIDDEN_DISPLAY_KEYS[row.key] then visible[#visible + 1] = row end
    end
    return visible
end

local DISPLAY_ORDER_INDEX = {}
for i, key in ipairs(M.ATTR_DISPLAY_ORDER) do DISPLAY_ORDER_INDEX[key] = i end

--- 展示排序索引（key → 序号，未列出返回 nil）
---@return table<string|number, number>
function M.displayOrderIndex()
    return DISPLAY_ORDER_INDEX
end

-- ======================== 六围排列定义 ========================

M.STAT_LAYOUT = {
    { col = 1, row = 1, key = AD.STR, name = "力量" },
    { col = 1, row = 2, key = AD.AGI, name = "敏捷" },
    { col = 1, row = 3, key = AD.INT, name = "秘识" },
    { col = 2, row = 1, key = AD.VIT, name = "体质" },
    { col = 2, row = 2, key = AD.LUK, name = "命数" },
    { col = 2, row = 3, key = AD.SPI, name = "魂火" },
}

-- ======================== 属性收集 ========================

local function getHeroEquipped(eqData, heroId)
    return EquipmentSystem.getHeroSlots(eqData, heroId)
end

local function getHeroRuntimeData(heroesData, heroId)
    if not heroesData or not heroesData.roster then return nil end
    return heroesData.roster[heroId] or heroesData.roster[tostring(heroId)]
end

local function applyDetailTeamAura(unit, heroId, heroesData, eqData)
    local _, teamIdx = findArtifactPosition(heroesData, heroId)
    unit.teamIdx = teamIdx
    local units = { unit }
    -- 仅判断所属队的套装标记，不为队光环重建整个名册或执行任何开战计时器。
    -- 空属性来源只提供 _setSix 给公共 API；数值和幂等/clone 规则仍由它处理。
    local ids = teamIdx and getTeamSlotIds(heroesData, teamIdx) or {}
    local seen = { [tonumber(heroId) or heroId] = true }
    for slot = 1, 4 do
        local sourceId = tonumber(ids[slot] or ids[tostring(slot)])
        if sourceId and sourceId > 0 and not seen[sourceId] and HC.get(sourceId) then
            seen[sourceId] = true
            local counts = EquipmentSetSystem.countSets(eqData, sourceId,
                EquipmentSystem.getFromInventory, EquipmentSystem.getHeroSlots)
            for _, summary in ipairs(EquipmentSetSystem.summarize(counts)) do
                if summary.setId == "last_rite" and summary.sixActive then
                    local sourceAttrs = UnitAttributes.create({})
                    sourceAttrs._setSix = "last_rite"
                    units[#units + 1] = { heroId = sourceId, teamIdx = teamIdx, attrs = sourceAttrs }
                    break
                end
            end
        end
    end
    EquipmentSetRuntime.applyTeamAura(units)
end

local function applyDetailRuntimeBonuses(unit, heroId, heroesData, eqData, options)
    local attrs = unit.attrs
    local heroEq = getHeroEquipped(eqData, heroId)
    if heroEq and eqData and eqData.inventory then
        require("systems.EquipmentPower").applyEquipment(attrs, eqData, heroId)
    end
    -- 只复用确定性四件属性，不调用 onBattleStart/条件被动/计时器。
    EquipmentSetRuntime.applyStaticBonuses(attrs)

    local partySlotForArtifact, teamIdx = findArtifactPosition(heroesData, heroId)
    if partySlotForArtifact then
        ArtifactBridge.applyToUnit(attrs, partySlotForArtifact, options.artifacts, teamIdx)
    end
    applyDetailTeamAura(unit, heroId, heroesData, eqData)
end

local function buildHeroAttrsForDetail(heroId, level, heroesData, eqData, options)
    local heroCfg = HC.get(heroId)
    if not heroCfg then return nil, nil end
    local hd = getHeroRuntimeData(heroesData, heroId) or {}
    -- 每条详情路径都在完整隔离快照中重建，缺失养成不得借本地 Owned/旧星图默认值。
    local createOptions = { litNodes = options.talents.litNodes or false, silent = true }
    local unit = HC.createHero(heroId, level, hd.advBranch, hd.awakening or {}, hd.extraTalent or {}, createOptions)
    if not unit or not unit.attrs then return nil, heroCfg end
    applyDetailRuntimeBonuses(unit, heroId, heroesData, eqData, options)
    return unit, heroCfg
end

local function calcMelissaStarGatePanelInfo(heroId, level, attrs, heroesData, eqData, options)
    if tonumber(heroId) ~= 20 or not attrs then return nil end
    local hd = getHeroRuntimeData(heroesData, heroId)
    local awakening = hd and hd.awakening or nil
    local awakened7 = require("config.AwakeningConfig").hasNode(awakening, 7)
    local limit = awakened7 and 4 or 3
    local includeSelf = true
    local resonanceWeight = 1.50
    local resonanceScale = awakened7 and 1.50 or 1.0
    local contributions = {}

    local function addContribution(sourceHeroId, sourceAttrs, sourceCfg)
        if not sourceAttrs or not sourceCfg then return end
        if (not includeSelf) and tonumber(sourceHeroId) == 20 then return end
        local category = AD.getAtkCategory(sourceCfg.atkType)
        if (not awakened7) and category ~= "magical" then return end
        local magDmgBonus = sourceAttrs:getUncapped(AD.MAG_DMG_BONUS) or 0
        local magAtkBonus = sourceAttrs:getUncapped(AD.MAG_ATK_BONUS) or 0
        local magPen = sourceAttrs:getUncapped(AD.MAG_PEN) or 0
        local inheritedDmg = math.max(0, magDmgBonus + magAtkBonus * 0.25)
        local inheritedPen = math.max(0, magPen)
        local score = inheritedDmg + inheritedPen * 0.6
        if score <= 0 then return end
        contributions[#contributions + 1] = {
            name = sourceCfg.name or tostring(sourceHeroId),
            inheritedDmg = inheritedDmg,
            inheritedPen = inheritedPen,
            score = score,
        }
    end

    -- 普通属性与配装快照只计所属队；未编队展示自身，不借其他队贡献。
    local _, teamIdx = findArtifactPosition(heroesData, heroId)
    local deployed = teamIdx and getTeamSlotIds(heroesData, teamIdx) or { heroId }
    local seen = {}
    for slot = 1, 4 do
        local sourceId = tonumber(deployed[slot] or deployed[tostring(slot)])
        if sourceId and sourceId > 0 and not seen[sourceId] then
            seen[sourceId] = true
            if sourceId == tonumber(heroId) then
                addContribution(sourceId, attrs, HC.get(sourceId))
            else
                local hd2 = getHeroRuntimeData(heroesData, sourceId)
                local level2 = (hd2 and hd2.level) or level or 1
                local unit2, cfg2 = buildHeroAttrsForDetail(sourceId, level2, heroesData, eqData, options)
                addContribution(sourceId, unit2 and unit2.attrs or nil, cfg2)
            end
        end
    end

    table.sort(contributions, function(a, b) return (a.score or 0) > (b.score or 0) end)
    local count = math.min(limit, #contributions)
    local totalDmg = 0
    local totalPen = 0
    local sourceParts = {}
    for i = 1, count do
        local c = contributions[i]
        local dmgPart = c.inheritedDmg * resonanceWeight
        local penPart = c.inheritedPen * resonanceWeight
        totalDmg = totalDmg + dmgPart
        totalPen = totalPen + penPart
        sourceParts[#sourceParts + 1] = string.format("%s: %.1f%%魔伤 / %.1f魔穿", c.name, dmgPart, penPart)
    end

    local finalDmgBonus = totalDmg * resonanceScale
    local finalPen = totalPen * resonanceScale
    local mult = 1 + finalDmgBonus / 100
    local selfMagDmg = attrs:getUncapped(AD.MAG_DMG_BONUS) or 0
    local desc = string.format(
        "星门会继承摘星星星人自身与出战队伍中贡献最高的魔法角色，最多%d名。每名角色贡献 = (魔法伤害加成 + 魔法攻击加成×25%%)×150%%；魔法穿透×150%%。7觉醒时继承范围扩展为全队，继承结果再×150%%。星门最终伤害中，本体魔伤与共鸣为乘法：基础伤害 × (1+本体魔伤%.1f%%) × 共鸣%.2f。当前共鸣魔伤+%.1f%%，共鸣魔穿+%.1f。来源：%s",
        limit, selfMagDmg, mult, finalDmgBonus, finalPen, (#sourceParts > 0 and table.concat(sourceParts, "；") or "无")
    )
    return {
        mult = mult,
        dmgBonus = finalDmgBonus,
        pen = finalPen,
        count = count,
        desc = desc,
    }
end

--- 收集英雄属性（基础 + 装备），生成左列/右列/六围数据
---@param heroId number|string
---@param heroCfg table HeroConfig 条目
---@param level number
---@param options? table 完整 heroes/equipment/artifacts/talents 快照；提供时不回读存档
---@return table { left={}, right={}, stats={}, attrs=UnitAttributes }
function M.collectAttributes(heroId, heroCfg, level, options)
    -- 两页共用完整有效属性链；默认来源也先隔离，神器/觉醒/词条规范化不能写真档。
    local source = options or {
        heroes = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes"),
        equipment = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment"),
        artifacts = ClientDispatcher.get("artifacts") or PlayerStore.Get("artifacts"),
        talents = ClientDispatcher.get("talents") or PlayerStore.Get("talents"),
    }
    local runtimeOptions = deepCopy({ heroes = source.heroes or {}, equipment = source.equipment or {},
        artifacts = source.artifacts or {}, talents = source.talents or {} })
    local heroesData, eqData = runtimeOptions.heroes, runtimeOptions.equipment
    local hero = buildHeroAttrsForDetail(heroId, level, heroesData, eqData, runtimeOptions)
    if not hero or not hero.attrs then
        return { left = {}, right = {}, stats = {} }
    end
    local attrs = hero.attrs

    -- === 左列：基础/防御属性 ===
    local left = {}
    left[#left + 1] = { key = AD.MAX_HP, name = "生命值", value = AttributeView.formatNumber(attrs:get(AD.MAX_HP)) }

    local category = AD.getAtkCategory(heroCfg.atkType)
    if category == "physical" then
        left[#left + 1] = { key = AD.PHYS_ATK, name = "物理攻击力", value = AttributeView.formatNumber(attrs:get(AD.PHYS_ATK)) }
    elseif category == "magical" then
        left[#left + 1] = { key = AD.MAG_ATK, name = "魔法攻击力", value = AttributeView.formatNumber(attrs:get(AD.MAG_ATK)) }
    elseif category == "healing" then
        left[#left + 1] = { key = AD.HEAL_AMOUNT, name = "治疗量", value = AttributeView.formatNumber(attrs:get(AD.HEAL_AMOUNT)) }
    end

    -- 基础值在前，对应加成紧跟后面。0 也保留，避免列表提前结束。
    local alwaysLeft = {
        { key = AD.ARMOR, name = "护甲" },
        { key = AD.ARMOR_BONUS, name = "护甲加成" },
        { key = AD.FINAL_ARMOR_BONUS, name = "最终护甲" },
        { key = AD.RESISTANCE, name = "伤害抗性" },
        { key = AD.ENERGY_SHIELD, name = "护盾上限" },
        { key = AD.ES_BONUS, name = "护盾加成" },
        { key = AD.FINAL_ENERGY_SHIELD_BONUS, name = "最终护盾" },
        { key = AD.HIT_VALUE, name = "命中值" },
        { key = AD.DODGE, name = "闪避值" },
        { key = AD.DODGE_BONUS, name = "闪避加成" },
        { key = AD.FINAL_DODGE_BONUS, name = "最终闪避" },
        { key = AD.HP_BONUS, name = "生命加成" },
        { key = AD.FINAL_HP_BONUS, name = "最终生命" },
    }
    local alwaysLeftSet = {}
    for _, item in ipairs(alwaysLeft) do
        alwaysLeftSet[item.key] = true
        local val = attrs:getUncapped(item.key)
        left[#left + 1] = {
            key = item.key,
            name = item.name,
            value = AD.formatAttrDisplayValue(item.key, val),
        }
    end

    -- 固定本职候选行，不以装备带来的数值决定可见性。
    -- PHYS_ARMOR/MAG_ARMOR 是 ARMOR/ENERGY_SHIELD 的同 key 别名。
    alwaysLeftSet[AD.MAX_HP] = true
    if category == "physical" then alwaysLeftSet[AD.PHYS_ATK] = true
    elseif category == "magical" then alwaysLeftSet[AD.MAG_ATK] = true
    elseif category == "healing" then alwaysLeftSet[AD.HEAL_AMOUNT] = true end
    for _, key in ipairs(M.ATTR_LEFT_PRIORITY) do
        if not alwaysLeftSet[key] then
            local meta = AD.getMeta(key)
            if meta then
                local val = attrs:getUncapped(key)
                left[#left + 1] = { key = key, name = meta.name, value = AD.formatAttrDisplayValue(key, val) }
                alwaysLeftSet[key] = true
            end
        end
    end

    -- === 右列：攻击/加成属性 ===
    local right = {}
    local atkTypeName = AD.ATK_TYPE_NAME[heroCfg.atkType] or "未知"
    local multRow = AD.TYPE_MULT[heroCfg.atkType]
    local atkDesc
    if multRow then
        local parts = {}
        for armorId = 1, 5 do
            local aName = AD.ARMOR_TYPE_NAME[armorId] or "?"
            local mult  = multRow[armorId] or 1.0
            if mult < 0 then
                parts[#parts + 1] = string.format("%s:治疗", aName)
            else
                parts[#parts + 1] = string.format("%s:%d%%", aName, math.floor(mult * 100 + 0.5))
            end
        end
        atkDesc = "对各护甲伤害: " .. table.concat(parts, " ")
    else
        atkDesc = "决定伤害类型与护甲克制关系"
    end
    right[#right + 1] = { key = "_atkType", name = "攻击类型", value = atkTypeName,
        desc = atkDesc }
    local actualInterval = attrs:getActualInterval()
    right[#right + 1] = { key = AD.ATK_INTERVAL, name = "攻击间隔",
        value = AttributeView.formatInterval(actualInterval),
        numericValue = actualInterval }
    right[#right + 1] = { key = "_atkTargets", name = "攻击目标", value = tostring(heroCfg.atkTargets),
        desc = "普攻每次可命中的敌方目标数量" }

    -- 只显示本职攻击力。物理不看魔法，魔法不看物理，治疗不看两边攻击力。
    right[#right + 1] = {
        key = AD.ATK_SPEED,
        name = "攻击速度",
        value = AD.formatAttrDisplayValue(AD.ATK_SPEED, attrs:get(AD.ATK_SPEED)),
    }

    -- 暴击率：合并通用+类型，与战斗公式/统计口径一致（展示截断前实际值）
    local effCrit = AD.getEffectiveCritRate(attrs, category)
    if category ~= "healing" then
        effCrit = attrs:getUncapped(AD.CRIT_RATE)
        if category == "physical" then
            effCrit = effCrit + attrs:getUncapped(AD.PHYS_CRIT_RATE)
        elseif category == "magical" then
            effCrit = effCrit + attrs:getUncapped(AD.MAG_CRIT_RATE)
        end
    else
        effCrit = attrs:getUncapped(AD.HEAL_CRIT_RATE)
    end
    if category ~= "healing" and attrs.artifactCritRateMult then
        effCrit = effCrit * attrs.artifactCritRateMult
    end
    local overflowEnabled = category ~= "healing" and (attrs.critOverflowRatio or 0) > 0
    do -- 展示原始暴击率，说明判定上限与专属觉醒门控。
        local critDesc = (category == "healing")
            and "治疗暴击判定使用的暴击率"
            or "通用暴击率 + 类型暴击率，神器倍率已计入；实战暴击概率最高100%，溢出默认不增加暴击伤害。"
        if overflowEnabled then
            critDesc = "通用暴击率 + 类型暴击率，神器倍率已计入；实战暴击概率最高100%。老六觉醒Ⅲ已解锁：每溢出1个百分点，使暴击伤害提高1%（乘算）。"
        elseif tonumber(heroId) == 18 then
            critDesc = critDesc .. "老六觉醒Ⅲ可解锁溢出转暴伤。"
        end
        right[#right + 1] = {
            key = "_effCritRate",
            name = (category == "healing") and "治疗暴击率" or "暴击率",
            value = string.format("%.1f%%", effCrit),
            desc = critDesc,
        }
    end

    local effCritDmg
    if category == "healing" then
        effCritDmg = attrs:getUncapped(AD.HEAL_CRIT_DMG)
    else
        effCritDmg = attrs:getUncapped(AD.CRIT_DMG)
        if category == "physical" then
            effCritDmg = effCritDmg + attrs:getUncapped(AD.PHYS_CRIT_DMG)
        elseif category == "magical" then
            effCritDmg = effCritDmg + attrs:getUncapped(AD.MAG_CRIT_DMG)
        end
    end
    if category ~= "healing" and attrs.artifactCritDmgMult then
        effCritDmg = effCritDmg * attrs.artifactCritDmgMult
    end
    -- 复用实战转换函数；未解锁专属觉醒只封顶概率，不放大暴伤。
    local overflowPct = 0
    if category ~= "healing" then
        if overflowEnabled then overflowPct = math.max(0, effCrit - 100) end
        local _, convertedDmg = CF.applyCritOverflow(effCrit, effCritDmg, attrs)
        effCritDmg = convertedDmg
    end
    do -- 有效暴击伤害常驻，格式与 numericValue 始终同源。
        local dmgDesc = (category == "healing") and "治疗暴击时使用的治疗倍率，基础200%。"
            or "实战暴击伤害倍率；神器倍率已计入。"
        if overflowPct > 0 then
            dmgDesc = string.format(
                "实战暴击伤害倍率；老六觉醒Ⅲ将 %.1f 个百分点的溢出暴击率转为暴伤提升（乘算）。", overflowPct)
        end
        right[#right + 1] = {
            key = "_effCritDmg",
            name = (category == "healing") and "暴击治疗" or "暴击伤害",
            value = string.format("%.1f%%", effCritDmg),
            desc = dmgDesc,
        }
    end

    local starGateInfo = calcMelissaStarGatePanelInfo(heroId, level, attrs, heroesData, eqData, runtimeOptions)
    if starGateInfo then
        right[#right + 1] = {
            key = "_melissaStarGateResonance",
            name = "星门共鸣",
            value = string.format("×%.2f", starGateInfo.mult),
            desc = starGateInfo.desc,
        }
        do -- 星门是英雄20的固有机制；其穿透为0时仍显示，其他英雄不显示。
            right[#right + 1] = {
                key = "_melissaStarGatePen",
                name = "星门魔穿",
                value = string.format("+%.1f", starGateInfo.pen),
                desc = "星门专属继承魔法穿透，来自共鸣角色的魔法穿透×150%，7觉醒时继承结果再×150%。该数值只作用于星门伤害，不改变摘星星星人面板魔法穿透。",
            }
        end
    end

    local skipCritKeys = {
        [AD.ATK_SPEED] = true,
        [AD.CRIT_RATE] = true,
        [AD.PHYS_CRIT_RATE] = true,
        [AD.MAG_CRIT_RATE] = true,
        [AD.CRIT_DMG] = true,
        [AD.PHYS_CRIT_DMG] = true,
        [AD.MAG_CRIT_DMG] = true,
    }
    if category == "physical" then
        skipCritKeys[AD.MAG_ATK] = true
        skipCritKeys[AD.MAG_ATK_BONUS] = true
        skipCritKeys[AD.MAG_PEN] = true
        skipCritKeys[AD.MAG_DMG_BONUS] = true
        skipCritKeys[AD.FINAL_MAG_ATK_BONUS] = true
        skipCritKeys[AD.HEAL_AMOUNT] = true
        skipCritKeys[AD.HEAL_BONUS] = true
    elseif category == "magical" then
        skipCritKeys[AD.PHYS_ATK] = true
        skipCritKeys[AD.PHYS_ATK_BONUS] = true
        skipCritKeys[AD.PHYS_PEN] = true
        skipCritKeys[AD.PHYS_DMG_BONUS] = true
        skipCritKeys[AD.FINAL_PHYS_ATK_BONUS] = true
        skipCritKeys[AD.HEAL_AMOUNT] = true
        skipCritKeys[AD.HEAL_BONUS] = true
    elseif category == "healing" then
        skipCritKeys[AD.PHYS_ATK] = true
        skipCritKeys[AD.MAG_ATK] = true
        skipCritKeys[AD.PHYS_ATK_BONUS] = true
        skipCritKeys[AD.MAG_ATK_BONUS] = true
        skipCritKeys[AD.PHYS_PEN] = true
        skipCritKeys[AD.MAG_PEN] = true
        skipCritKeys[AD.PHYS_DMG_BONUS] = true
        skipCritKeys[AD.MAG_DMG_BONUS] = true
        skipCritKeys[AD.FINAL_PHYS_ATK_BONUS] = true
        skipCritKeys[AD.FINAL_MAG_ATK_BONUS] = true
    end
    -- 治疗量已在左列；治疗暴击已合并为有效暴击，非治疗职业不展示治疗专属行。
    skipCritKeys[AD.HEAL_AMOUNT] = true
    skipCritKeys[AD.HEAL_CRIT_RATE] = true
    skipCritKeys[AD.HEAL_CRIT_DMG] = true
    if category == "healing" then
        skipCritKeys[AD.DMG_BONUS] = true
        skipCritKeys[AD.FINAL_DAMAGE_BONUS] = true
        skipCritKeys[AD.ADVANTAGE_DMG_BONUS] = true
        skipCritKeys[AD.DISADVANTAGE_DMG_BONUS] = true
        -- 治疗普攻走 calcHealAttack（无连击、伤害浮动或伤害加成）。
        skipCritKeys[AD.COMBO_RATE] = true
        skipCritKeys[AD.COMBO_DMG_UP] = true
    end

    for _, key in ipairs(M.ATTR_RIGHT_PRIORITY) do
        if skipCritKeys[key] then goto continue_attr end
        local val = attrs:getUncapped(key)
        local meta = AD.getMeta(key)
        if meta then
            right[#right + 1] = { key = key, name = meta.name, value = AD.formatAttrDisplayValue(key, val) }
            skipCritKeys[key] = true
        end
        ::continue_attr::
    end

    if attrs.artifactCritRateMult and attrs.artifactCritRateMult ~= 1.0 then
        right[#right + 1] = {
            key = "_artifactCritRateMult",
            name = "神器暴击率",
            value = string.format("×%.2f", attrs.artifactCritRateMult),
            desc = "神器特殊效果：最终暴击率按该倍率调整，已计入上方暴击率显示。",
        }
    end
    if attrs.artifactCritDmgMult and attrs.artifactCritDmgMult ~= 1.0 then
        right[#right + 1] = {
            key = "_artifactCritDmgMult",
            name = "神器暴击伤害",
            value = string.format("×%.2f", attrs.artifactCritDmgMult),
            desc = "神器特殊效果：最终暴击伤害按该倍率调整，已计入上方暴击伤害显示。",
        }
    end
    if attrs.artifactIgnoreArmor then
        right[#right + 1] = {
            key = "_artifactIgnoreArmor",
            name = "神器无视护甲",
            value = "生效",
            desc = "神器特殊效果：攻击结算时无视目标护甲。",
        }
    end
    if attrs.artifactChaosDamageMult then
        right[#right + 1] = {
            key = "_artifactChaosDamage",
            name = "混沌伤害",
            value = string.format("%.0f%%", attrs.artifactChaosDamageMult * 100),
            desc = "神器特殊效果：所有伤害转为混沌伤害，合并物理/魔法穿透与伤害加成。",
        }
    end
    if attrs.artifactExtraDamageMult and attrs.artifactExtraDamageMult ~= 1.0 then
        right[#right + 1] = {
            key = "_artifactExtraDamage",
            name = "额外伤害",
            value = string.format("×%.2f", attrs.artifactExtraDamageMult),
            desc = "神器特殊效果：作为独立乘区提高最终伤害。",
        }
    end
    if attrs.artifactBlockCap then
        left[#left + 1] = {
            key = "_artifactBlockCap",
            name = "格挡上限",
            value = string.format("%.0f%%", attrs.artifactBlockCap),
            desc = "神器特殊效果：物理/魔法格挡率可突破100%，最高按该上限计算。",
        }
    end
    if attrs.artifactNoHeal then
        left[#left + 1] = {
            key = "_artifactNoHeal",
            name = "生命恢复",
            value = "禁止",
            desc = "神器特殊效果：无法再以任何形式恢复生命值。",
        }
    end

    -- === 六围属性 ===
    local stats = {}
    for _, st in ipairs(M.STAT_LAYOUT) do
        local val = attrs:get(st.key)
        stats[st.key] = val
    end

    -- 数值与格式化同源，绝不从带百分号/溢出提示的字符串反解析。
    local specialValues = {
        _atkTargets = heroCfg.atkTargets,
        _effCritRate = effCrit,
        _effCritDmg = effCritDmg,
        _melissaStarGateResonance = starGateInfo and starGateInfo.mult,
        _melissaStarGatePen = starGateInfo and starGateInfo.pen,
        _artifactCritRateMult = attrs.artifactCritRateMult,
        _artifactCritDmgMult = attrs.artifactCritDmgMult,
        _artifactChaosDamage = attrs.artifactChaosDamageMult and attrs.artifactChaosDamageMult * 100,
        _artifactExtraDamage = attrs.artifactExtraDamageMult,
        _artifactBlockCap = attrs.artifactBlockCap,
    }
    local cappedValues = {
        [AD.MAX_HP] = true, [AD.PHYS_ATK] = true, [AD.MAG_ATK] = true,
        [AD.HEAL_AMOUNT] = true, [AD.ATK_SPEED] = true,
    }
    for _, column in ipairs({ left, right }) do
        for _, row in ipairs(column) do
            if row.numericValue == nil then
                if AD.getMeta(row.key) then
                    row.numericValue = cappedValues[row.key] and attrs:get(row.key) or attrs:getUncapped(row.key)
                else
                    row.numericValue = specialValues[row.key]
                end
            end
        end
    end

    return { left = left, right = right, stats = stats, attrs = attrs }
end

-- ======================== 属性页只读展示缓存 ========================
-- collectAttributes 仍逐调用返回独立属性容器（预览/战斗不能共享可变 attrs）。
-- 只有每个详情宿主私有的展示闭包复用行与六围；不在英雄之间或宿主之间共享。
local function sameValue(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not sameValue(value, b[key]) then return false end
    end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function presentationDependencies(heroId, heroCfg, level, options)
    ---@type table|nil
    local heroes = nil
    ---@type table|nil
    local equipment = nil
    ---@type table|nil
    local artifacts = nil
    ---@type table|nil
    local talents = nil
    ---@type table|boolean|nil
    local litNodes = nil
    if options ~= nil then
        heroes, equipment = options.heroes or {}, options.equipment or {}
        artifacts, talents = options.artifacts or {}, options.talents or {}
        litNodes = talents.litNodes or false
    else
        heroes = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
        equipment = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
        artifacts = ClientDispatcher.get("artifacts") or PlayerStore.Get("artifacts")
        talents = ClientDispatcher.get("talents") or PlayerStore.Get("talents")
        litNodes = talents and talents.litNodes or false
    end
    local deps = { heroId = heroId, heroCfg = heroCfg, level = level, explicit = options ~= nil,
        language = require("core.I18n").get(), heroesPresent = heroes ~= nil,
        artifacts = artifacts, litNodes = litNodes,
        talents = talents and talents.litNodes, teams = {}, heroes = {}, worn = {} }
    -- 非英雄模块版本也区分 ClearCache/Cleanup → 同内容重入；纯经验发布不进入 key。
    if not options and PlayerStore.GetRevision then
        deps.equipmentRevision = PlayerStore.GetRevision("equipment")
        deps.artifactsRevision = PlayerStore.GetRevision("artifacts")
        deps.talentsRevision = PlayerStore.GetRevision("talents")
        deps.storeHeroesPresent = PlayerStore.Get("heroes") ~= nil
    end
    for team = 1, 3 do
        local ids = getTeamSlotIds(heroes, team)
        local slots = {}
        for slot = 1, 4 do slots[slot] = ids[slot] or ids[tostring(slot)] or false end
        deps.teams[team] = slots
    end
    local function addHero(id)
        if deps.heroes[id] then return end
        local hd = getHeroRuntimeData(heroes, id)
        deps.heroes[id] = { present = hd ~= nil, level = hd and hd.level,
            advBranch = hd and hd.advBranch, awakening = hd and hd.awakening,
            extraTalent = hd and hd.extraTalent, cfg = HC.get(id) }
        local slots = getHeroEquipped(equipment, id)
        local worn = { slots = slots, items = {} }
        local inventory = equipment and equipment.inventory
        for _, slot in ipairs(EquipmentConfig.SLOTS) do
            local seq = slots and slots[slot]
            if seq then worn.items[slot] = inventory and (inventory[tostring(seq)] or inventory[seq]) or false end
        end
        deps.worn[id] = worn
    end
    addHero(heroId)
    -- 任意英雄都会受本队司仪六件光环影响；缓存依赖不能只为星门收集队友穿戴项。
    local _, team = findArtifactPosition(heroes, heroId)
    local ids = team and getTeamSlotIds(heroes, team) or {}
    for slot = 1, 4 do
        local id = tonumber(ids[slot] or ids[tostring(slot)])
        if id and id > 0 then addHero(id) end
    end
    return deps
end

--- 创建宿主私有展示读取器。返回的行/六围只供该宿主绘制，不供预览修改。
--- 不改 collectAttributes 的独立返回值契约；缺省 collector 仍使用真实属性管线。
---@param collector? function
---@return function
function M.createPresentationCache(collector)
    collector = collector or M.collectAttributes
    local saved = {} ---@type table
    local presentation = {} ---@type table
    local populated = false
    return function(heroId, heroCfg, level, options)
        local deps = presentationDependencies(heroId, heroCfg, level, options)
        if populated and sameValue(deps, saved) then return presentation, presentation.rows end
        local data = collector(heroId, heroCfg, level, options)
        local columns = deepCopy({ data.left, data.right })
        local rows, originalIndex = {}, {}
        for _, column in ipairs(columns) do
            for _, row in ipairs(column) do
                rows[#rows + 1] = row
                originalIndex[row] = #rows
            end
        end
        table.sort(rows, function(a, b)
            local oa, ob = DISPLAY_ORDER_INDEX[a.key] or 9999, DISPLAY_ORDER_INDEX[b.key] or 9999
            if oa ~= ob then return oa < ob end
            return originalIndex[a] < originalIndex[b]
        end)
        -- 不保存/暴露可变 UnitAttributes；保留源行顺序，排序不写 _origIdx 到返回行。
        presentation = { rows = M.filterDisplayRows(rows), stats = deepCopy(data.stats) }
        -- getFromInventory/追加技旧档回退可能水合数据：保存完成后的实际字段，避免次帧伪失效。
        saved = deepCopy(presentationDependencies(heroId, heroCfg, level, options))
        populated = true
        return presentation, presentation.rows
    end
end

return M
