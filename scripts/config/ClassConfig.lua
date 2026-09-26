-- ============================================================================
-- ClassConfig - 六门契职业表
-- 拍板（2026-09-22）：六契名字采用；classId 换成 seal/spoil/rift/echo/mask/debt；
-- 转职 101–224 数字保留；闪电卖鸡留 spoil；改死亡留给职业延缓；双持规则保留。
-- 旧存档/遗物/塔词条仍可能写 knight 等，一律走 CC.normalize。
-- ============================================================================

local AD = require("systems.AttributeDef")

local CC = {}

-- 新 ID
CC.SEAL  = "seal"   -- 封门人
CC.SPOIL = "spoil"  -- 拾骸者
CC.RIFT  = "rift"   -- 裂隙使
CC.ECHO  = "echo"   -- 回响客
CC.MASK  = "mask"   -- 换面人
CC.DEBT  = "debt"   -- 司仪

-- 旧常量别名（大量 CC.KNIGHT 引用不用逐文件改）
CC.KNIGHT   = CC.SEAL
CC.WARRIOR  = CC.SPOIL
CC.MAGE     = CC.RIFT
CC.RANGER   = CC.ECHO
CC.ASSASSIN = CC.MASK
CC.PRIEST   = CC.DEBT

local LEGACY_TO_NEW = {
    knight = CC.SEAL, warrior = CC.SPOIL, mage = CC.RIFT,
    ranger = CC.ECHO, assassin = CC.MASK, priest = CC.DEBT,
    seal = CC.SEAL, spoil = CC.SPOIL, rift = CC.RIFT,
    echo = CC.ECHO, mask = CC.MASK, debt = CC.DEBT,
}

--- 旧/新 classId → 新 ID
---@param classId string|nil
---@return string|nil
function CC.normalize(classId)
    if not classId then return nil end
    return LEGACY_TO_NEW[classId] or classId
end

CC.CLASSES = {
    [CC.SEAL] = {
        name = "封门人",
        baseAttackThreatMin = 60,  baseAttackThreatMax = 100,
        dmgThreatCoeffMin   = 10.0, dmgThreatCoeffMax   = 15.0,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = nil,
        talentName = "门缝",
        talentDesc = "受到的伤害先储存于门缝（容量为最大生命的12%），每秒释放20%。释放的伤害有30%转向当前敌人，其余由自己承受；储存伤害会增加仇恨。",
        talentId   = "gate_seal_rift",
        armorTypes = { AD.ARMOR_PLATE, AD.ARMOR_HEAVY },
    },
    [CC.SPOIL] = {
        name = "拾骸者",
        baseAttackThreatMin = 10,  baseAttackThreatMax = 20,
        dmgThreatCoeffMin   = 0.5, dmgThreatCoeffMax   = 0.7,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = nil,
        talentName = "拾骸",
        talentDesc = "击杀敌人获得1层骸骨（最多12层），每层攻击速度+1.2%；满12层后，下次攻击消耗6层骸骨并追加一次40%伤害。",
        talentId   = "gate_spoil_bone",
        armorTypes = { AD.ARMOR_HEAVY, AD.ARMOR_LIGHT },
    },
    [CC.RIFT] = {
        name = "裂隙使",
        baseAttackThreatMin = 0,   baseAttackThreatMax = 5,
        dmgThreatCoeffMin   = 0.5, dmgThreatCoeffMax   = 0.7,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = nil,
        talentName = "裂隙",
        talentDesc = "每8秒展开持续4秒的裂隙：自身攻击的护甲克制系数向1.25靠近，并给目标施加1层裂痕。",
        talentId   = "gate_rift_open",
        armorTypes = { AD.ARMOR_CLOTH, AD.ARMOR_LIGHT },
    },
    [CC.ECHO] = {
        name = "回响客",
        baseAttackThreatMin = 1,   baseAttackThreatMax = 2,
        dmgThreatCoeffMin   = 0.8, dmgThreatCoeffMax   = 1.0,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = nil,
        talentName = "回响",
        talentDesc = "普通攻击留下回响，1.2秒后造成原伤害45%的额外伤害（仅产生10%仇恨）；队伍中有封门人时，回响伤害+15%。",
        talentId   = "gate_echo_delay",
        armorTypes = { AD.ARMOR_LIGHT, AD.ARMOR_LEATHER },
    },
    [CC.MASK] = {
        name = "换面人",
        baseAttackThreatMin = 0,   baseAttackThreatMax = 0,
        dmgThreatCoeffMin   = 0.3, dmgThreatCoeffMax   = 0.5,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = nil,
        talentName = "换面",
        talentDesc = "开战时复制当前目标的护甲克制系数，并额外提高0.1。目标死亡3秒后切换至下一目标；切换期间的下一次攻击无视20%护甲。",
        talentId   = "gate_mask_steal",
        armorTypes = { AD.ARMOR_LEATHER, AD.ARMOR_LEATHER },
    },
    [CC.DEBT] = {
        name = "司仪",
        baseAttackThreatMin = 0,   baseAttackThreatMax = 5,
        dmgThreatCoeffMin   = 0.5, dmgThreatCoeffMax   = 0.7,
        healThreatBaseMin   = 20,  healThreatBaseMax   = 30,
        healThreatCoeffMin  = 0.8, healThreatCoeffMax  = 1.2,
        statBonus = nil,
        talentName = "延缓",
        talentDesc = "治疗量按90%结算。过量治疗转为延缓：为队友抵挡一次致命伤害，但抵挡的部分会在4秒内反噬，使其受到的伤害+15%。每人最多承受1层。",
        talentId   = "gate_debt_defer",
        armorTypes = { AD.ARMOR_CLOTH, AD.ARMOR_LEATHER },
    },
}

CC.NAME_TO_ID = {}
for id, cls in pairs(CC.CLASSES) do
    CC.NAME_TO_ID[cls.name] = id
end
CC.NAME_TO_ID["射手"] = CC.ECHO
CC.NAME_TO_ID["骑士"] = CC.SEAL
CC.NAME_TO_ID["战士"] = CC.SPOIL
CC.NAME_TO_ID["法师"] = CC.RIFT
CC.NAME_TO_ID["刺客"] = CC.MASK
CC.NAME_TO_ID["牧师"] = CC.DEBT
CC.NAME_TO_ID["守誓者"] = CC.SEAL
CC.NAME_TO_ID["破阵者"] = CC.SPOIL
CC.NAME_TO_ID["咒术师"] = CC.RIFT
CC.NAME_TO_ID["夜猎者"] = CC.ECHO
CC.NAME_TO_ID["无痕者"] = CC.MASK
CC.NAME_TO_ID["提灯者"] = CC.DEBT

---@param classId string|nil
---@return table|nil
function CC.get(classId)
    return CC.CLASSES[CC.normalize(classId)]
end

---@param name string
---@return string|nil
function CC.getIdByName(name)
    return CC.NAME_TO_ID[name]
end

---@param classId string|nil
---@return number
function CC.getBaseAttackThreat(classId)
    local cls = CC.get(classId)
    if not cls then return 5 end
    return (cls.baseAttackThreatMin + cls.baseAttackThreatMax) * 0.5
end

---@param classId string|nil
---@return number
function CC.getDmgThreatCoeff(classId)
    local cls = CC.get(classId)
    if not cls then return 1.0 end
    return (cls.dmgThreatCoeffMin + cls.dmgThreatCoeffMax) * 0.5
end

---@param classId string|nil
---@return number
function CC.getHealThreatBase(classId)
    local cls = CC.get(classId)
    if not cls then return 25 end
    return (cls.healThreatBaseMin + cls.healThreatBaseMax) * 0.5
end

---@param classId string|nil
---@return number
function CC.getHealThreatCoeff(classId)
    local cls = CC.get(classId)
    if not cls then return 1.0 end
    return (cls.healThreatCoeffMin + cls.healThreatCoeffMax) * 0.5
end

--- 六契基础职不再给面板 +10% 伤 / +5 六围。被动在 ClassGateRuntime。
---@param classId string|nil
---@param attrs table
function CC.applyTalent(classId, attrs)
    classId = CC.normalize(classId)
    if classId == CC.DEBT and attrs then
        -- 司仪治疗量按 90%：治疗加成 -10 百分点
        attrs:addModifier("talent_" .. classId, { { key = AD.HEAL_BONUS, flat = -10 } })
    end
end

---@param classId string|nil
---@param attrs table
function CC.applyStatBonus(classId, attrs)
    local cls = CC.get(classId)
    if not cls or not cls.statBonus or not attrs then return end
    local entries = {}
    for key, val in pairs(cls.statBonus) do
        entries[#entries + 1] = { key = key, flat = val }
    end
    if #entries > 0 then
        attrs:addModifier("class_bonus_" .. CC.normalize(classId), entries)
    end
end

return CC
