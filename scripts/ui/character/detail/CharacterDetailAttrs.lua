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

-- 神器装配按队读取，不能只反查槽位后默认读队1。
local function findArtifactPosition(heroesData, heroId)
    for teamIdx = 1, 3 do
        local team = heroesData and heroesData.teams
            and (heroesData.teams[teamIdx] or heroesData.teams[tostring(teamIdx)])
        for slot, id in ipairs((team and team.slots) or {}) do
            if tonumber(id) == tonumber(heroId) then return slot, teamIdx end
        end
    end
    for slot, id in ipairs((heroesData and heroesData.deployed) or {}) do
        if tonumber(id) == tonumber(heroId) then return slot, 1 end
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
    AD.MAX_DMG_BONUS,
    AD.MIN_DMG_BONUS,
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
    AD.MAX_DMG_BONUS, AD.MIN_DMG_BONUS,
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
    -- 基础信息
    "_atkType", AD.ATK_INTERVAL, "_atkTargets",
    -- 特殊机制/神器
    "_melissaStarGateResonance", "_melissaStarGatePen",
    "_artifactCritRateMult", "_artifactCritDmgMult", "_artifactIgnoreArmor",
    "_artifactChaosDamage", "_artifactExtraDamage", "_artifactBlockCap", "_artifactNoHeal",
}

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

local function applyDetailRuntimeBonuses(attrs, heroId, classId, heroesData, eqData, options)
    local heroEq = getHeroEquipped(eqData, heroId)
    if heroEq and eqData and eqData.inventory then
        local appliedSeqs = {}
        for _, slotKey in ipairs(EquipmentConfig.SLOTS) do
            local seq = heroEq[slotKey]
            if seq and not appliedSeqs[seq] then
                local equip = eqData.inventory[tostring(seq)] or eqData.inventory[seq]
                if equip then
                    EquipmentSystem.hydrate(equip)
                    local slotBoost = EquipmentSystem.getAscendBoost(equip)
                    EquipmentSystem.applyToUnit(attrs, equip, seq, slotBoost)
                    appliedSeqs[seq] = true
                end
            end
        end
        EquipmentSetSystem.applyToUnit(
            attrs, eqData, heroId,
            EquipmentSystem.getFromInventory, EquipmentSystem.getHeroSlots)
    end

    local partySlotForArtifact, teamIdx = findArtifactPosition(heroesData, heroId)
    if partySlotForArtifact then
        ArtifactBridge.applyToUnit(attrs, partySlotForArtifact, options and options.artifacts, teamIdx)
    end
end

local function buildHeroAttrsForDetail(heroId, level, heroesData, eqData, options)
    local heroCfg = HC.get(heroId)
    if not heroCfg then return nil, nil end
    local hd = getHeroRuntimeData(heroesData, heroId)
    -- 显式空表阻止 ExtraTalentSystem.getOwned 的写真档回退。
    local extraTalent = hd and hd.extraTalent
    if options and extraTalent == nil then extraTalent = {} end
    local awakening = hd and hd.awakening
    if options and awakening == nil then awakening = {} end
    local unit = HC.createHero(heroId, level, hd and hd.advBranch or nil, awakening, extraTalent)
    if not unit or not unit.attrs then return nil, heroCfg end
    applyDetailRuntimeBonuses(unit.attrs, heroId, heroCfg.classId, heroesData, eqData, options)
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

    local deployed = (heroesData and heroesData.deployed) or {}
    if options then
        local _, teamIdx = findArtifactPosition(heroesData, heroId)
        local team = heroesData and heroesData.teams and
            (heroesData.teams[teamIdx] or heroesData.teams[tostring(teamIdx)])
        if team and team.slots then deployed = team.slots end
    end
    for _, deployedHeroId in ipairs(deployed) do
        local sourceId = tonumber(deployedHeroId) or deployedHeroId
        if tonumber(sourceId) == tonumber(heroId) then
            addContribution(sourceId, attrs, HC.get(sourceId))
        else
            local hd2 = getHeroRuntimeData(heroesData, sourceId)
            local level2 = (hd2 and hd2.level) or level or 1
            local unit2, cfg2 = buildHeroAttrsForDetail(sourceId, level2, heroesData, eqData, options)
            addContribution(sourceId, unit2 and unit2.attrs or nil, cfg2)
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
---@param options? table 显式 heroes/equipment/artifacts 快照；提供时不回读存档，六围保留小数
---@return table { left={}, right={}, stats={}, attrs=UnitAttributes }
function M.collectAttributes(heroId, heroCfg, level, options)
    -- 旧调用保留数据来源；预览调用只读隔离快照，禁止临时改 PlayerStore/HC。
    local heroesData = options and deepCopy(options.heroes or {})
        or ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
    local eqData = options and deepCopy(options.equipment or {})
        or ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    local runtimeOptions = options and { artifacts = deepCopy(options.artifacts or {}) } or nil
    local hd = getHeroRuntimeData(heroesData, heroId)
    local extraTalent = hd and hd.extraTalent
    if options and extraTalent == nil then extraTalent = {} end
    local awakening = hd and hd.awakening
    if options and awakening == nil then awakening = {} end
    local hero = HC.createHero(heroId, level, hd and hd.advBranch, awakening, extraTalent)
    if not hero or not hero.attrs then
        return { left = {}, right = {}, stats = {} }
    end
    local attrs = hero.attrs

    -- === 应用已穿戴装备、神器属性（与战斗/战力口径一致） ===
    applyDetailRuntimeBonuses(attrs, heroId, heroCfg.classId, heroesData, eqData, runtimeOptions)

    -- === 左列：基础/防御属性 ===
    local left = {}
    left[#left + 1] = { key = AD.MAX_HP, name = "生命值", value = tostring(math.floor(attrs:get(AD.MAX_HP))) }

    local category = AD.getAtkCategory(heroCfg.atkType)
    if category == "physical" then
        left[#left + 1] = { key = AD.PHYS_ATK, name = "物理攻击力", value = tostring(math.floor(attrs:get(AD.PHYS_ATK))) }
    elseif category == "magical" then
        left[#left + 1] = { key = AD.MAG_ATK, name = "魔法攻击力", value = tostring(math.floor(attrs:get(AD.MAG_ATK))) }
    elseif category == "healing" then
        left[#left + 1] = { key = AD.HEAL_AMOUNT, name = "治疗量", value = tostring(math.floor(attrs:get(AD.HEAL_AMOUNT))) }
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
        value = string.format("%.1fs", options and actualInterval or heroCfg.atkInterval),
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
    if attrs.artifactCritRateMult then
        effCrit = effCrit * attrs.artifactCritRateMult
    end
    do -- 有效暴击率常驻，0% 也保留；不再随装备出现/消失。
        local critDesc = (category == "healing")
            and "治疗暴击判定使用的暴击率"
            or "通用暴击率 + 类型暴击率，与战斗中普攻/连击暴击判定一致；神器倍率已计入。超过 100% 的部分按 1:1 转为暴击伤害"
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
    if attrs.artifactCritDmgMult then
        effCritDmg = effCritDmg * attrs.artifactCritDmgMult
    end
    -- 暴击溢出：超过 100% 的暴击率按 1:1 转为暴击伤害，面板与实战口径一致
    local overflowPct = 0
    if category ~= "healing" and effCrit and effCrit > 100 then
        overflowPct = effCrit - 100
        effCritDmg = effCritDmg * (1 + overflowPct / 100)
    end
    do -- 有效暴击伤害常驻，格式与 numericValue 始终同源。
        local dmgDesc = "实战暴击伤害倍率；神器倍率已计入。"
        if overflowPct > 0 then
            dmgDesc = string.format(
                "实战暴击伤害倍率；其中 %.1f%% 由溢出暴击率按 1:1 转化而来。", overflowPct)
        end
        right[#right + 1] = {
            key = "_effCritDmg",
            name = (category == "healing") and "治疗暴击伤害" or "暴击伤害",
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
        skipCritKeys[AD.MAX_DMG_BONUS] = true
        skipCritKeys[AD.MIN_DMG_BONUS] = true
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
        stats[st.key] = options and val or math.floor(val)
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

return M
