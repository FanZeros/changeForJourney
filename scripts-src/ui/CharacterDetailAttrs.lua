---@diagnostic disable: param-type-mismatch
------------------------------------------------------------------------
-- CharacterDetailAttrs.lua  —— 角色属性收集模块
-- 从 CharacterDetail.lua 拆分出来
-- 职责：属性排序定义 + collectAttributes 函数
------------------------------------------------------------------------
local HC               = require("config.HeroConfig")
local AD               = require("systems.AttributeDef")
local PlayerStore      = require("client.data.PlayerStore")
local ClientDispatcher = require("network.ClientDispatcher")
local EquipmentConfig  = require("config.EquipmentConfig")
local EquipmentSystem  = require("systems.EquipmentSystem")
local RelicBridge      = require("systems.RelicBridge")
local ArtifactBridge   = require("systems.ArtifactBridge")
local AvatarFrameBridge = require("systems.AvatarFrameBridge")

local M = {}

-- ======================== 属性排序定义 ========================

--- 左列候选属性（按优先级排列，hero不具有的属性跳过）
M.ATTR_LEFT_PRIORITY = {
    AD.MAX_HP,
    AD.MAX_MANA,
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

-- ======================== 六围排列定义 ========================

M.STAT_LAYOUT = {
    { col = 1, row = 1, key = AD.STR, name = "力量", icon = "ICON_SX_LL" },
    { col = 1, row = 2, key = AD.AGI, name = "敏捷", icon = "ICON_SX_MJ" },
    { col = 1, row = 3, key = AD.INT, name = "智慧", icon = "ICON_SX_ZH" },
    { col = 2, row = 1, key = AD.VIT, name = "体质", icon = "ICON_SX_TZ" },
    { col = 2, row = 2, key = AD.LUK, name = "运气", icon = "ICON_SX_YQ" },
    { col = 2, row = 3, key = AD.SPI, name = "精神", icon = "ICON_SX_JS" },
}

-- ======================== 属性收集 ========================

local function getHeroEquipped(eqData, heroId)
    if not eqData or not eqData.equipped then return nil end
    return eqData.equipped[heroId] or eqData.equipped[tostring(heroId)]
end

local function getHeroRuntimeData(heroesData, heroId)
    if not heroesData or not heroesData.roster then return nil end
    return heroesData.roster[heroId] or heroesData.roster[tostring(heroId)]
end

local function applyDetailRuntimeBonuses(attrs, heroId, classId, heroesData, eqData)
    local heroEq = getHeroEquipped(eqData, heroId)
    if heroEq and eqData and eqData.inventory then
        local slotEnhanceData = ClientDispatcher.get("slotEnhance") or PlayerStore.Get("slotEnhance")
        local partySlot = EquipmentSystem.findPartySlot(heroesData and heroesData.deployed, heroId)

        local appliedSeqs = {}
        for _, slotKey in ipairs(EquipmentConfig.SLOTS) do
            local seq = heroEq[slotKey]
            if seq and not appliedSeqs[seq] then
                local equip = eqData.inventory[tostring(seq)] or eqData.inventory[seq]
                if equip then
                    EquipmentSystem.hydrate(equip)
                    local slotBoost = 0
                    if partySlot and slotEnhanceData then
                        slotBoost = EquipmentSystem.calcSlotBoost(slotEnhanceData, partySlot, slotKey, equip.grip)
                    end
                    EquipmentSystem.applyToUnit(attrs, equip, seq, slotBoost)
                    appliedSeqs[seq] = true
                end
            end
        end
    end

    RelicBridge.applyToUnit(attrs, classId)

    local challenger = ClientDispatcher.get("challenger") or PlayerStore.Get("challenger")
    AvatarFrameBridge.applyToUnit(attrs, challenger and challenger.unlockedAvatarFrames or nil)

    local partySlotForArtifact = EquipmentSystem.findPartySlot(heroesData and heroesData.deployed, heroId)
    if partySlotForArtifact then
        ArtifactBridge.applyToUnit(attrs, partySlotForArtifact)
    end
end

local function buildHeroAttrsForDetail(heroId, level, heroesData, eqData)
    local heroCfg = HC.get(heroId)
    if not heroCfg then return nil, nil end
    local hd = getHeroRuntimeData(heroesData, heroId)
    local unit = HC.createHero(heroId, level, hd and hd.advBranch or nil, hd and hd.awakening or nil)
    if not unit or not unit.attrs then return nil, heroCfg end
    applyDetailRuntimeBonuses(unit.attrs, heroId, heroCfg.classId, heroesData, eqData)
    return unit, heroCfg
end

local function calcMelissaStarGatePanelInfo(heroId, level, attrs, heroesData, eqData)
    if tonumber(heroId) ~= 20 or not attrs then return nil end
    local hd = getHeroRuntimeData(heroesData, heroId)
    local awakening = hd and hd.awakening or nil
    local awakened7 = awakening and (awakening[7] or awakening["7"]) and true or false
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

    for _, deployedHeroId in ipairs((heroesData and heroesData.deployed) or {}) do
        local sourceId = tonumber(deployedHeroId) or deployedHeroId
        if tonumber(sourceId) == tonumber(heroId) then
            addContribution(sourceId, attrs, HC.get(sourceId))
        else
            local hd2 = getHeroRuntimeData(heroesData, sourceId)
            local level2 = (hd2 and hd2.level) or level or 1
            local unit2, cfg2 = buildHeroAttrsForDetail(sourceId, level2, heroesData, eqData)
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
        "星门会继承梅丽莎自身与出战队伍中贡献最高的魔法角色，最多%d名。每名角色贡献 = (魔法伤害加成 + 魔法攻击加成×25%%)×150%%；魔法穿透×150%%。7觉醒时继承范围扩展为全队，继承结果再×150%%。星门最终伤害中，本体魔伤与共鸣为乘法：基础伤害 × (1+本体魔伤%.1f%%) × 共鸣%.2f。当前共鸣魔伤+%.1f%%，共鸣魔穿+%.1f。来源：%s",
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
---@return table { left={}, right={}, stats={} }
function M.collectAttributes(heroId, heroCfg, level)
    -- 获取转职和觉醒数据
    local heroesData = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
    local advBranch = nil
    local awakening = nil
    if heroesData and heroesData.roster then
        local hd = heroesData.roster[heroId] or heroesData.roster[tostring(heroId)]
        if hd then
            advBranch = hd.advBranch
            awakening = hd.awakening
        end
    end
    local hero = HC.createHero(heroId, level, advBranch, awakening)
    if not hero or not hero.attrs then
        return { left = {}, right = {} }
    end
    local attrs = hero.attrs

    -- === 应用已穿戴装备、遗物、神器属性（与战斗/战力口径一致） ===
    local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    applyDetailRuntimeBonuses(attrs, heroId, heroCfg.classId, heroesData, eqData)

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

    for _, key in ipairs(M.ATTR_LEFT_PRIORITY) do
        local val = attrs:getUncapped(key)
        local meta = AD.getMeta(key)
        if meta and val ~= 0 and val ~= (meta.default or 0) then
            if key ~= AD.MAX_HP then
                left[#left + 1] = { key = key, name = meta.name, value = AD.formatAttrDisplayValue(key, val) }
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
    right[#right + 1] = { key = AD.ATK_INTERVAL, name = "攻击间隔", value = string.format("%.1fs", heroCfg.atkInterval) }
    right[#right + 1] = { key = "_atkTargets", name = "攻击目标", value = tostring(heroCfg.atkTargets),
        desc = "普攻每次可命中的敌方目标数量" }

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
    if effCrit > 0 then
        local critDesc = (category == "healing")
            and "治疗暴击判定使用的暴击率"
            or "通用暴击率 + 类型暴击率，与战斗中普攻/连击暴击判定一致；神器倍率已计入"
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
    if effCritDmg and effCritDmg > 0 then
        right[#right + 1] = {
            key = "_effCritDmg",
            name = (category == "healing") and "治疗暴击伤害" or "暴击伤害",
            value = string.format("%.1f%%", effCritDmg),
            desc = "实战暴击伤害倍率；神器倍率已计入。",
        }
    end

    local starGateInfo = calcMelissaStarGatePanelInfo(heroId, level, attrs, heroesData, eqData)
    if starGateInfo then
        right[#right + 1] = {
            key = "_melissaStarGateResonance",
            name = "星门共鸣",
            value = string.format("×%.2f", starGateInfo.mult),
            desc = starGateInfo.desc,
        }
        if starGateInfo.pen and starGateInfo.pen > 0 then
            right[#right + 1] = {
                key = "_melissaStarGatePen",
                name = "星门魔穿",
                value = string.format("+%.1f", starGateInfo.pen),
                desc = "星门专属继承魔法穿透，来自共鸣角色的魔法穿透×150%，7觉醒时继承结果再×150%。该数值只作用于星门伤害，不改变梅丽莎面板魔法穿透。",
            }
        end
    end

    local skipCritKeys = {
        [AD.CRIT_RATE] = true,
        [AD.PHYS_CRIT_RATE] = true,
        [AD.MAG_CRIT_RATE] = true,
        [AD.CRIT_DMG] = true,
        [AD.PHYS_CRIT_DMG] = true,
        [AD.MAG_CRIT_DMG] = true,
    }
    if category == "healing" then
        skipCritKeys[AD.HEAL_CRIT_RATE] = true
        skipCritKeys[AD.HEAL_CRIT_DMG] = true
    end

    for _, key in ipairs(M.ATTR_RIGHT_PRIORITY) do
        if skipCritKeys[key] then goto continue_attr end
        local val = attrs:getUncapped(key)
        local meta = AD.getMeta(key)
        if meta and val ~= 0 and val ~= (meta.default or 0) then
            right[#right + 1] = { key = key, name = meta.name, value = AD.formatAttrDisplayValue(key, val) }
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
        stats[st.key] = math.floor(val)
    end

    return { left = left, right = right, stats = stats }
end

return M
