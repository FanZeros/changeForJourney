-- ============================================================================
-- EquipmentConfig - 装备静态配置表
-- 包含: 武器/副手/护甲/头盔/鞋子/饰品模板、品质定义、槽位定义、等级缩放系数
-- 数据来源: 装备配置.txt
-- ============================================================================

local EquipmentConfig = {}

-- ======================== 品质定义 ========================

EquipmentConfig.QUALITY = {
    [1] = { name = "普通", color = "ffffff", affixCount = 0, maxAffixQuality = 0, baseStrength = 1.0, randomStrength = 1.0 },
    [2] = { name = "优质", color = "a2ff94", affixCount = 1, maxAffixQuality = 2, baseStrength = 1.1, randomStrength = 1.1 },
    [3] = { name = "稀有", color = "72f2f5", affixCount = 1, maxAffixQuality = 3, baseStrength = 1.2, randomStrength = 1.2 },
    [4] = { name = "史诗", color = "ef79ff", affixCount = 2, maxAffixQuality = 3, baseStrength = 1.3, randomStrength = 1.3 },
    [5] = { name = "传说", color = "ffed00", affixCount = 2, maxAffixQuality = 4, baseStrength = 1.4, randomStrength = 1.4 },
    [6] = { name = "至臻", color = "ff0000", affixCount = 2, maxAffixQuality = 5, baseStrength = 1.5, randomStrength = 1.5 },
}

-- ======================== 等级缩放 ========================

EquipmentConfig.LEVEL_SCALE = 0.05  -- 每级 +5%

-- ======================== 槽位定义 ========================

EquipmentConfig.SLOTS = { "weapon", "offhand", "armor", "helmet", "shoes", "accessory" }
EquipmentConfig.SLOT_NAME = {
    weapon    = "主手",
    offhand   = "副手",
    armor     = "护甲",
    helmet    = "头盔",
    shoes     = "鞋子",
    accessory = "饰品",
}

-- ======================== 装备模板表 ========================

EquipmentConfig.ITEMS = {}

local ITEMS = EquipmentConfig.ITEMS

-- 每个槽位独立编号，使用前缀字符串 ID
-- 武器: W1~W72, 副手: O1~O30, 护甲: A1~A60, 头盔: H1~, 鞋子: S1~, 饰品: C1~C36
local SLOT_PREFIX = {
    weapon    = "W",
    offhand   = "O",
    armor     = "A",
    helmet    = "H",
    shoes     = "S",
    accessory = "C",
}
EquipmentConfig.SLOT_PREFIX = SLOT_PREFIX

-- 每个槽位的当前计数器
local slotCounter = {
    weapon    = 0,
    offhand   = 0,
    armor     = 0,
    helmet    = 0,
    shoes     = 0,
    accessory = 0,
}

--- 为指定槽位生成下一个字符串 ID（如 W1, O2, A3, C4）
---@param slot string
---@return string
local function nextSlotId(slot)
    slotCounter[slot] = slotCounter[slot] + 1
    return SLOT_PREFIX[slot] .. slotCounter[slot]
end

--- 批量添加同类型装备（共享属性 key，不同数值层级）
---@param slot string 槽位
---@param typeName string 装备子类型名
---@param grip string|nil 握持方式 "onehand"/"twohand"（仅武器）
---@param statKeys string[] 属性 key 列表
---@param tiers table[] 每个层级: { n=名称, lv={min,max}, v={val1,val2,...} }
local function addGroup(slot, typeName, grip, statKeys, tiers)
    for _, t in ipairs(tiers) do
        local id = nextSlotId(slot)
        local stats = {}
        for i, key in ipairs(statKeys) do
            if t.v[i] ~= nil then
                stats[#stats + 1] = { key, t.v[i] }
            end
        end
        ITEMS[id] = {
            id = id,
            name = t.n,
            type = typeName,
            slot = slot,
            grip = grip,
            levelRange = t.lv,
            stats = stats,
        }
    end
end

--- 添加单件装备（属性各不相同，如饰品）
---@param name string
---@param typeName string
---@param slot string
---@param lv table {min,max}
---@param stats table[] { {key,value}, ... }
local function addItem(name, typeName, slot, lv, stats)
    local id = nextSlotId(slot)
    ITEMS[id] = {
        id = id,
        name = name,
        type = typeName,
        slot = slot,
        levelRange = lv,
        stats = stats,
    }
end

-- ======================== 武器（72件）========================

-- 单手剑（1-6）: [主] physAtk, [次1] hitValue, [次2] atkSpeed%
addGroup("weapon", "单手剑", "onehand", {"physAtk", "hitValue", "atkSpeed"}, {
    { n = "练习用剑", lv = {1,16},  v = {6.28, 0.80, 1.6} },
    { n = "铁质长剑", lv = {17,32}, v = {9, 1.13, 2.3} },
    { n = "钢制长剑", lv = {33,48}, v = {11.32, 1.45, 2.9} },
    { n = "骑士佩剑", lv = {49,64}, v = {13.82, 1.76, 3.5} },
    { n = "叠甲战神之剑", lv = {65,80}, v = {16.34, 2.09, 4.1} },
    { n = "水晶长剑", lv = {81,9999}, v = {18.86, 2.41, 4.9} },
})

-- 双手剑（7-12）: [主] physAtk, [次1] physPen, [次2] physDmgBonus%
addGroup("weapon", "双手剑", "twohand", {"physAtk", "physPen", "physDmgBonus"}, {
    { n = "练习用大剑", lv = {1,16},  v = {12.58, 2.57, 4.3} },
    { n = "生铁重剑", lv = {17,32},  v = {18, 3.60, 6.0} },
    { n = "黑铁大剑", lv = {33,48}, v = {22.62, 4.63, 7.7} },
    { n = "斩铁巨刃", lv = {49,64}, v = {27.66, 5.66, 9.5} },
    { n = "叠甲战神巨剑", lv = {65,80}, v = {32.68, 6.69, 11.2} },
    { n = "水晶大剑", lv = {81,9999}, v = {37.72, 7.71, 12.9} },
})

-- 单手斧（13-18）: [主] physAtk, [次1] str
addGroup("weapon", "单手斧", "onehand", {"physAtk", "str"}, {
    { n = "伐木斧", lv = {1,16},  v = {6.28, 0.86} },
    { n = "铁手斧", lv = {17,32},  v = {9, 1.20} },
    { n = "钢斧", lv = {33,48}, v = {11.32, 1.54} },
    { n = "蛮族利斧", lv = {49,64}, v = {13.82, 1.89} },
    { n = "掠夺者之斧", lv = {65,80}, v = {16.34, 2.23} },
    { n = "水晶手斧", lv = {81,9999}, v = {18.86, 2.57} },
})

-- 双手斧（19-24）: [主] physAtk, [次1] maxDmgBonus%, [次2] physDmgBonus%
addGroup("weapon", "双手斧", "twohand", {"physAtk", "maxDmgBonus", "physDmgBonus"}, {
    { n = "双刃巨斧", lv = {1,16},  v = {12.58, 10.7, 4.3} },
    { n = "铁巨斧", lv = {17,32},  v = {18, 15.0, 6.0} },
    { n = "长柄战斧", lv = {33,48}, v = {22.62, 19.3, 7.7} },
    { n = "蛮族巨斧", lv = {49,64}, v = {27.66, 23.6, 9.5} },
    { n = "掠夺者巨斧", lv = {65,80}, v = {32.68, 28, 11.2} },
    { n = "水晶巨斧", lv = {81,9999}, v = {37.72, 32.1, 12.9} },
})

-- 法杖（25-30）: [主] magAtk, [次1] magPen, [次2] magDmgBonus%
addGroup("weapon", "法杖", "twohand", {"magAtk", "magPen", "magDmgBonus"}, {
    { n = "学徒木杖", lv = {1,16},  v = {12.58, 2.57, 4.3} },
    { n = "符文长杖", lv = {17,32},  v = {18, 3.60, 6.0} },
    { n = "铁质长杖", lv = {33,48}, v = {22.62, 4.63, 7.7} },
    { n = "银质长杖", lv = {49,64}, v = {27.66, 5.66, 9.5} },
    { n = "镀金长杖", lv = {65,80}, v = {32.68, 6.69, 11.2} },
    { n = "水晶长杖", lv = {81,9999}, v = {37.72, 7.71, 12.9} },
})

-- 魔杖（31-36）: [主] magAtk, [次1] hitValue, [次2] atkSpeed%
addGroup("weapon", "魔杖", "onehand", {"magAtk", "hitValue", "atkSpeed"}, {
    { n = "短魔杖", lv = {1,16},  v = {6.28, 0.80, 1.6} },
    { n = "符文魔杖", lv = {17,32},  v = {9, 1.13, 2.3} },
    { n = "仪式魔杖", lv = {33,48}, v = {11.32, 1.45, 2.9} },
    { n = "精灵魔杖", lv = {49,64}, v = {13.82, 1.76, 3.5} },
    { n = "镀金魔杖", lv = {65,80}, v = {16.34, 2.09, 4.1} },
    { n = "水晶魔杖", lv = {81,9999}, v = {18.86, 2.41, 4.9} },
})

-- 弓箭（37-42）: [主] physAtk, [次1] hitValue, [次2] physPen
addGroup("weapon", "弓箭", "twohand", {"physAtk", "hitValue", "physPen"}, {
    { n = "木质短弓", lv = {1,16},  v = {12.58, 1.61, 2.57} },
    { n = "铁制长弓", lv = {17,32},  v = {18, 2.25, 3.60} },
    { n = "狩猎弓", lv = {33,48}, v = {22.62, 2.89, 4.63} },
    { n = "游侠弓", lv = {49,64}, v = {27.66, 3.54, 5.66} },
    { n = "风行者之弓", lv = {65,80}, v = {32.68, 4.18, 6.69} },
    { n = "水晶长弓", lv = {81,9999}, v = {37.72, 4.82, 7.71} },
})

-- 单手弩（43-48）: [主] physAtk, [次1] atkSpeed%, [次2] hitValue
addGroup("weapon", "单手弩", "onehand", {"physAtk", "atkSpeed", "hitValue"}, {
    { n = "轻弩", lv = {1,16},  v = {6.28, 1.6, 0.80} },
    { n = "铁弩", lv = {17,32},  v = {9, 2.3, 1.13} },
    { n = "狩猎弩", lv = {33,48}, v = {11.32, 2.9, 1.45} },
    { n = "游侠弩", lv = {49,64}, v = {13.82, 3.5, 1.76} },
    { n = "风行者手弩", lv = {65,80}, v = {16.34, 4.1, 2.09} },
    { n = "水晶手弩", lv = {81,9999}, v = {18.86, 4.9, 2.41} },
})

-- 手铳（49-54）: [主] magAtk, [次1] hitValue, [次2] comboRate%
-- 注意: 配置文档中#49燧发手铳的次要属性顺序与50-54不同（49是连击概率在前），代码统一用 hitValue,comboRate 顺序
addGroup("weapon", "手铳", "onehand", {"magAtk", "hitValue", "comboRate"}, {
    { n = "燧发手铳", lv = {1,16},  v = {6.28, 0.80, 2.2} },
    { n = "铁质手铳", lv = {17,32},  v = {9, 1.13, 3.0} },
    { n = "短铳", lv = {33,48}, v = {11.32, 1.45, 3.9} },
    { n = "矮人手枪", lv = {49,64}, v = {13.82, 1.76, 4.7} },
    { n = "机械手铳", lv = {65,80}, v = {16.34, 2.09, 5.6} },
    { n = "水晶手枪", lv = {81,9999}, v = {18.86, 2.41, 6.4} },
})

-- 匕首（55-60）: [主] magAtk, [次1] atkSpeed%, [次2] comboRate%
addGroup("weapon", "匕首", "onehand", {"magAtk", "atkSpeed", "comboRate"}, {
    { n = "玻璃碎片", lv = {1,16},  v = {6.28, 1.6, 2.2} },
    { n = "铜匕首", lv = {17,32},  v = {9, 2.3, 3.0} },
    { n = "铁匕首", lv = {33,48}, v = {11.32, 2.9, 3.9} },
    { n = "盗贼短匕", lv = {49,64}, v = {13.82, 3.5, 4.7} },
    { n = "刺客之刃", lv = {65,80}, v = {16.34, 4.1, 5.6} },
    { n = "水晶之刃", lv = {81,9999}, v = {18.86, 4.9, 6.4} },
})

-- 细剑（61-66）: [主] physAtk, [次1] atkSpeed%, [次2] physPen
addGroup("weapon", "细剑", "onehand", {"physAtk", "atkSpeed", "physPen"}, {
    { n = "练习用刺剑", lv = {1,16},  v = {6.28, 1.6, 1.29} },
    { n = "刺剑", lv = {17,32},  v = {9, 2.3, 1.80} },
    { n = "绅士细剑", lv = {33,48}, v = {11.32, 2.9, 2.31} },
    { n = "练武者细剑", lv = {49,64}, v = {13.82, 3.5, 2.83} },
    { n = "决斗者细剑", lv = {65,80}, v = {16.34, 4.1, 3.34} },
    { n = "水晶刺剑", lv = {81,9999}, v = {18.86, 4.9, 3.86} },
})

-- 权杖（67-72）: [主] healAmount, [次1] healBonus%
addGroup("weapon", "权杖", "onehand", {"healAmount", "healBonus"}, {
    { n = "木质权杖", lv = {1,16},  v = {6.28, 5.1} },
    { n = "铁质权杖", lv = {17,32},  v = {9, 7.2} },
    { n = "祭祀权杖", lv = {33,48}, v = {11.32, 9.3} },
    { n = "主教权杖", lv = {49,64}, v = {13.82, 11.3} },
    { n = "光之权杖", lv = {65,80}, v = {16.34, 13.4} },
    { n = "水晶权杖", lv = {81,9999}, v = {18.86, 15.4} },
})

-- ======================== 副手（30件）========================

-- 轻盾（73-78）: [主] dodge, [次1] atkSpeed%, [次2] physBlockRate%
addGroup("offhand", "轻盾", nil, {"dodge", "atkSpeed", "physBlockRate"}, {
    { n = "陈旧木盾", lv = {1,16},  v = {3.14, 1.6, 1.2} },
    { n = "镶皮圆盾", lv = {17,32},  v = {4.40, 2.2, 1.8} },
    { n = "钢边轻鸢盾", lv = {33,48}, v = {5.66, 2.8, 2.3} },
    { n = "斥候疾风盾", lv = {49,64}, v = {6.91, 3.4, 2.7} },
    { n = "守望者轻盾", lv = {65,80}, v = {8.18, 4.0, 3.3} },
    { n = "流光镜盾", lv = {81,9999}, v = {9.43, 4.8, 3.8} },
})

-- 重盾（79-84）: [主] physArmor, [次1] physBlockRate%, [次2] magBlockRate%
addGroup("offhand", "重盾", nil, {"armor", "physBlockRate", "magBlockRate"}, {
    { n = "厚实木盾", lv = {1,16},  v = {4.49, 1.2, 1.2} },
    { n = "铸铁方盾", lv = {17,32},  v = {6.28, 1.8, 1.8} },
    { n = "钢制塔盾", lv = {33,48}, v = {8.08, 2.3, 2.3} },
    { n = "守卫巨盾", lv = {49,64}, v = {9.87, 2.7, 2.7} },
    { n = "蛮族巨盾", lv = {65,80}, v = {11.68, 3.3, 3.3} },
    { n = "水晶巨盾", lv = {81,9999}, v = {13.47, 3.8, 3.8} },
})

-- 魔典（85-90）: [主] armor, [次1] magPen, [次2] magDmgBonus%
addGroup("offhand", "魔典", nil, {"armor", "magPen", "magDmgBonus"}, {
    { n = "学徒魔典", lv = {1,16},  v = {4.49, 1.26, 2.1} },
    { n = "见习魔典", lv = {17,32},  v = {6.28, 1.76, 2.9} },
    { n = "咒文魔典", lv = {33,48}, v = {8.08, 2.26, 3.8} },
    { n = "秘法魔典", lv = {49,64}, v = {9.87, 2.76, 4.6} },
    { n = "奥术魔典", lv = {65,80}, v = {11.68, 3.26, 5.5} },
    { n = "大法师魔典", lv = {81,9999}, v = {13.47, 3.78, 6.2} },
})

-- 法珠（91-96）: [主] 能量护盾, [次1] 魔法格挡概率%, [次2] 魔法穿透
addGroup("offhand", "法珠", nil, {"energyShield", "magBlockRate", "magPen"}, {
    { n = "学徒法珠", lv = {1,16},  v = {31.42, 1.2, 1.26} },
    { n = "见习法珠", lv = {17,32},  v = {44, 1.8, 1.76} },
    { n = "魔力法珠", lv = {33,48}, v = {56.58, 2.3, 2.26} },
    { n = "闪光法珠", lv = {49,64}, v = {69.14, 2.7, 2.76} },
    { n = "奥术法珠", lv = {65,80}, v = {81.72, 3.3, 3.26} },
    { n = "水晶法珠", lv = {81,9999}, v = {94.28, 3.8, 3.78} },
})

-- 圣物（97-102）: [主] 能量护盾, [次1] 治疗暴击率%, [次2] 治疗暴击加成%
addGroup("offhand", "圣物", nil, {"energyShield", "healCritRate", "healCritDmg"}, {
    { n = "木质圣杯", lv = {1,16},  v = {31.42, 0.8, 4.2} },
    { n = "铁质圣杯", lv = {17,32},  v = {44, 1.1, 5.9} },
    { n = "祭祀圣杯", lv = {33,48}, v = {56.58, 1.4, 7.6} },
    { n = "主教圣杯", lv = {49,64}, v = {69.14, 1.8, 9.2} },
    { n = "光之圣杯", lv = {65,80}, v = {81.72, 2.0, 10.9} },
    { n = "水晶圣杯", lv = {81,9999}, v = {94.28, 2.4, 12.6} },
})

-- ======================== 护甲（60件）========================

-- 皮甲A（103-108）: [主] maxHp, [次1] dodge
addGroup("armor", "皮甲", nil, {"maxHp", "dodge"}, {
    { n = "磨损皮衣", lv = {1,16},  v = {101, 1.22} },
    { n = "皮制胸甲", lv = {17,32},  v = {142, 1.70} },
    { n = "镶钉皮甲", lv = {33,48}, v = {182, 2.18} },
    { n = "巡林客外套", lv = {49,64}, v = {223, 2.67} },
    { n = "追猎者战衣", lv = {65,80}, v = {264, 3.15} },
    { n = "蛇皮软甲", lv = {81,9999}, v = {303, 3.65} },
})

-- 皮甲B（109-114）: [主] 生命值, [次1] 护甲, [次2] 能量护盾
addGroup("armor", "皮甲", nil, {"maxHp", "armor", "energyShield"}, {
    { n = "粗制皮背心", lv = {1,16},  v = {101, 0.87, 6.07} },
    { n = "灵便皮外套", lv = {17,32},  v = {142, 1.22, 8} },
    { n = "无声影皮甲", lv = {33,48}, v = {182, 1.56, 10.93} },
    { n = "刺客夜行服", lv = {49,64}, v = {223, 1.90, 13.35} },
    { n = "无踪者秘装", lv = {65,80}, v = {264, 2.25, 15.78} },
    { n = "夜行者风衣", lv = {81,9999}, v = {303, 2.60, 18.22} },
})

-- 轻甲A（115-120）: [主] maxHp, [次1] physArmor
addGroup("armor", "轻甲", nil, {"maxHp", "armor"}, {
    { n = "陈旧锁子甲", lv = {1,16},  v = {101, 0.87} },
    { n = "锻铁环甲", lv = {17,32},  v = {142, 1.22} },
    { n = "精钢链甲衫", lv = {33,48}, v = {182, 1.56} },
    { n = "骑兵胸甲", lv = {49,64}, v = {223, 1.90} },
    { n = "勇士战铠", lv = {65,80}, v = {264, 2.25} },
    { n = "勇者战甲", lv = {81,9999}, v = {303, 2.60} },
})

-- 轻甲B（121-126）: [主] maxHp, [次1] physArmor, [次2] dodge
addGroup("armor", "轻甲", nil, {"maxHp", "armor", "dodge"}, {
    { n = "破烂鳞甲", lv = {1,16},  v = {101, 0.87, 0.60} },
    { n = "铜钢鳞甲", lv = {17,32},  v = {142, 1.22, 0.85} },
    { n = "秘银鳞甲", lv = {33,48}, v = {182, 1.56, 1.10} },
    { n = "游侠之鳞", lv = {49,64}, v = {223, 1.90, 1.33} },
    { n = "监视者之服", lv = {65,80}, v = {264, 2.25, 1.58} },
    { n = "神射手之衣", lv = {81,9999}, v = {303, 2.60, 1.82} },
})

-- 重甲A（127-132）: [主] 生命值, [次1] 能量护盾, [次2] 生命加成%
addGroup("armor", "重甲", nil, {"maxHp", "energyShield", "hpBonus"}, {
    { n = "硬铁重衣", lv = {1,16},  v = {101, 6.07, 1.0} },
    { n = "铸铁重甲", lv = {17,32},  v = {142, 8, 1.4} },
    { n = "钢制重甲", lv = {33,48}, v = {182, 10.93, 1.8} },
    { n = "骑士重铠", lv = {49,64}, v = {223, 13.35, 2.2} },
    { n = "战争之铠", lv = {65,80}, v = {264, 15.78, 2.6} },
    { n = "山岳巨铠", lv = {81,9999}, v = {303, 18.22, 3.1} },
})

-- 重甲B（133-138）: [主] maxHp, [次1] physArmor, [次2] hpBonus
addGroup("armor", "重甲", nil, {"maxHp", "armor", "hpBonus"}, {
    { n = "笨重铁甲", lv = {1,16},  v = {101, 0.87, 1.0} },
    { n = "黑铁胸铠", lv = {17,32},  v = {142, 1.22, 1.4} },
    { n = "全身覆甲", lv = {33,48}, v = {182, 1.56, 1.8} },
    { n = "银光亮铠", lv = {49,64}, v = {223, 1.90, 2.2} },
    { n = "金鳞之甲", lv = {65,80}, v = {264, 2.25, 2.6} },
    { n = "龙鳞之甲", lv = {81,9999}, v = {303, 2.60, 3.1} },
})

-- 板甲A（139-144）: [主] maxHp, [次1] hpBonus, [次2] physArmor
addGroup("armor", "板甲", nil, {"maxHp", "hpBonus", "armor"}, {
    { n = "拼接板甲", lv = {1,16},  v = {101, 1.0, 0.87} },
    { n = "全身板甲", lv = {17,32},  v = {142, 1.4, 1.22} },
    { n = "亮面板甲", lv = {33,48}, v = {182, 1.8, 1.56} },
    { n = "圣骑士板甲", lv = {49,64}, v = {223, 2.2, 1.90} },
    { n = "帝国之铠", lv = {65,80}, v = {264, 2.6, 2.25} },
    { n = "神圣裁决铠", lv = {81,9999}, v = {303, 3.1, 2.60} },
})

-- 板甲B（145-150）: [主] maxHp, [次1] hpBonus, [次2] magArmor
addGroup("armor", "板甲", nil, {"maxHp", "hpBonus", "energyShield"}, {
    { n = "厚重板甲", lv = {1,16},  v = {101, 1.0, 0.87} },
    { n = "鸢制板甲", lv = {17,32},  v = {142, 1.4, 1.22} },
    { n = "银光版甲", lv = {33,48}, v = {182, 1.8, 1.56} },
    { n = "审判官板甲", lv = {49,64}, v = {223, 2.2, 1.90} },
    { n = "卫士之甲", lv = {65,80}, v = {264, 2.6, 2.25} },
    { n = "元帅之甲", lv = {81,9999}, v = {303, 3.1, 2.60} },
})

-- 布甲A（151-156）: [主] 生命值, [次1] 能量护盾
addGroup("armor", "布甲", nil, {"maxHp", "energyShield"}, {
    { n = "粗布长袍", lv = {1,16},  v = {101, 12.15} },
    { n = "棉质法袍", lv = {17,32},  v = {142, 17} },
    { n = "丝绸导师袍", lv = {33,48}, v = {182, 21.85} },
    { n = "咒法师长袍", lv = {49,64}, v = {223, 26.72} },
    { n = "奥术师之袍", lv = {65,80}, v = {264, 31.57} },
    { n = "大贤者之袍", lv = {81,9999}, v = {303, 36.43} },
})

-- 布甲B（157-162）: [主] 能量护盾, [次1] 能量护盾加成%
addGroup("armor", "布甲", nil, {"energyShield", "esBonus"}, {
    { n = "亚麻衬衣", lv = {1,16},  v = {30.35, 1.0} },
    { n = "祭司法袍", lv = {17,32},  v = {42, 1.4} },
    { n = "金线刺绣袍", lv = {33,48}, v = {54.65, 1.8} },
    { n = "微光者法袍", lv = {49,64}, v = {66.78, 2.2} },
    { n = "主教礼袍", lv = {65,80}, v = {78.93, 2.6} },
    { n = "光明圣袍", lv = {81,9999}, v = {91.07, 3.1} },
})

-- ======================== 头盔（60件）========================

-- 皮甲头盔A: [主] hitValue, [次] maxHp
addGroup("helmet", "皮甲", nil, {"hitValue", "maxHp"}, {
    { n = "软皮风帽", lv = {1,16}, v = {0.80, 30} },
    { n = "镶钉皮盔", lv = {17,32}, v = {1.12, 42} },
    { n = "巡林客风帽", lv = {33,48}, v = {1.44, 54} },
    { n = "追猎者面罩", lv = {49,64}, v = {1.76, 66} },
    { n = "蛇皮兜帽", lv = {65,80}, v = {2.08, 78} },
    { n = "影皮头盔", lv = {81,9999}, v = {2.40, 90} },
})

-- 皮甲头盔B: [主] energyShield, [次] armor
addGroup("helmet", "皮甲", nil, {"energyShield", "armor"}, {
    { n = "粗制皮帽", lv = {1,16}, v = {5.00, 0.70} },
    { n = "灵便皮盔", lv = {17,32}, v = {7.00, 0.98} },
    { n = "无声影盔", lv = {33,48}, v = {9.00, 1.26} },
    { n = "刺客面罩", lv = {49,64}, v = {11.00, 1.54} },
    { n = "无踪者兜帽", lv = {65,80}, v = {13.00, 1.82} },
    { n = "夜行者风帽", lv = {81,9999}, v = {15.00, 2.10} },
})

-- 轻甲头盔A: [主] hitValue, [次] maxHp
addGroup("helmet", "轻甲", nil, {"hitValue", "maxHp"}, {
    { n = "陈旧链盔", lv = {1,16}, v = {0.80, 30} },
    { n = "锻铁环盔", lv = {17,32}, v = {1.12, 42} },
    { n = "精钢链盔", lv = {33,48}, v = {1.44, 54} },
    { n = "骑兵盔", lv = {49,64}, v = {1.76, 66} },
    { n = "勇士战盔", lv = {65,80}, v = {2.08, 78} },
    { n = "勇者战盔", lv = {81,9999}, v = {2.40, 90} },
})

-- 轻甲头盔B: [主] energyShield, [次] armor
addGroup("helmet", "轻甲", nil, {"energyShield", "armor"}, {
    { n = "破烂鳞盔", lv = {1,16}, v = {5.00, 0.70} },
    { n = "铜钢鳞盔", lv = {17,32}, v = {7.00, 0.98} },
    { n = "秘银鳞盔", lv = {33,48}, v = {9.00, 1.26} },
    { n = "游侠盔", lv = {49,64}, v = {11.00, 1.54} },
    { n = "监视者盔", lv = {65,80}, v = {13.00, 1.82} },
    { n = "神射手盔", lv = {81,9999}, v = {15.00, 2.10} },
})

-- 重甲头盔A: [主] hitValue, [次] maxHp
addGroup("helmet", "重甲", nil, {"hitValue", "maxHp"}, {
    { n = "硬铁盔", lv = {1,16}, v = {0.80, 30} },
    { n = "铸铁盔", lv = {17,32}, v = {1.12, 42} },
    { n = "钢制重盔", lv = {33,48}, v = {1.44, 54} },
    { n = "骑士盔", lv = {49,64}, v = {1.76, 66} },
    { n = "战争之盔", lv = {65,80}, v = {2.08, 78} },
    { n = "山岳巨盔", lv = {81,9999}, v = {2.40, 90} },
})

-- 重甲头盔B: [主] energyShield, [次] armor
addGroup("helmet", "重甲", nil, {"energyShield", "armor"}, {
    { n = "笨重铁盔", lv = {1,16}, v = {5.00, 0.70} },
    { n = "黑铁盔", lv = {17,32}, v = {7.00, 0.98} },
    { n = "覆甲战盔", lv = {33,48}, v = {9.00, 1.26} },
    { n = "银光盔", lv = {49,64}, v = {11.00, 1.54} },
    { n = "金鳞盔", lv = {65,80}, v = {13.00, 1.82} },
    { n = "龙鳞盔", lv = {81,9999}, v = {15.00, 2.10} },
})

-- 板甲头盔A: [主] hitValue, [次] maxHp
addGroup("helmet", "板甲", nil, {"hitValue", "maxHp"}, {
    { n = "拼接板盔", lv = {1,16}, v = {0.80, 30} },
    { n = "全身板盔", lv = {17,32}, v = {1.12, 42} },
    { n = "亮面板盔", lv = {33,48}, v = {1.44, 54} },
    { n = "圣骑士盔", lv = {49,64}, v = {1.76, 66} },
    { n = "帝国盔", lv = {65,80}, v = {2.08, 78} },
    { n = "神圣裁决盔", lv = {81,9999}, v = {2.40, 90} },
})

-- 板甲头盔B: [主] energyShield, [次] armor
addGroup("helmet", "板甲", nil, {"energyShield", "armor"}, {
    { n = "厚重板盔", lv = {1,16}, v = {5.00, 0.70} },
    { n = "鸢制板盔", lv = {17,32}, v = {7.00, 0.98} },
    { n = "银光板盔", lv = {33,48}, v = {9.00, 1.26} },
    { n = "审判官盔", lv = {49,64}, v = {11.00, 1.54} },
    { n = "卫士盔", lv = {65,80}, v = {13.00, 1.82} },
    { n = "元帅盔", lv = {81,9999}, v = {15.00, 2.10} },
})

-- 布甲头盔A: [主] hitValue, [次] maxHp
addGroup("helmet", "布甲", nil, {"hitValue", "maxHp"}, {
    { n = "粗布头巾", lv = {1,16}, v = {0.80, 30} },
    { n = "棉质法帽", lv = {17,32}, v = {1.12, 42} },
    { n = "丝绸导师帽", lv = {33,48}, v = {1.44, 54} },
    { n = "咒法师帽", lv = {49,64}, v = {1.76, 66} },
    { n = "奥术师兜帽", lv = {65,80}, v = {2.08, 78} },
    { n = "大贤者冠", lv = {81,9999}, v = {2.40, 90} },
})

-- 布甲头盔B: [主] energyShield, [次] esBonus
addGroup("helmet", "布甲", nil, {"energyShield", "esBonus"}, {
    { n = "亚麻头巾", lv = {1,16}, v = {10.00, 1.00} },
    { n = "祭司帽", lv = {17,32}, v = {14.00, 1.40} },
    { n = "金线法帽", lv = {33,48}, v = {18.00, 1.80} },
    { n = "微光者冠", lv = {49,64}, v = {22.00, 2.20} },
    { n = "主教冠", lv = {65,80}, v = {26.00, 2.60} },
    { n = "光明圣冠", lv = {81,9999}, v = {30.00, 3.00} },
})

-- ======================== 鞋子（60件）========================

-- 皮甲鞋子A: [主] atkSpeed, [次] agi
addGroup("shoes", "皮甲", nil, {"atkSpeed", "agi"}, {
    { n = "磨损皮靴", lv = {1,16}, v = {1.6, 0.80} },
    { n = "皮制短靴", lv = {17,32}, v = {2.2, 1.12} },
    { n = "镶钉皮靴", lv = {33,48}, v = {2.8, 1.44} },
    { n = "巡林客靴", lv = {49,64}, v = {3.4, 1.76} },
    { n = "追猎者靴", lv = {65,80}, v = {4.0, 2.08} },
    { n = "蛇皮快靴", lv = {81,9999}, v = {4.6, 2.40} },
})

-- 皮甲鞋子B: [主] dodge, [次] agi
addGroup("shoes", "皮甲", nil, {"dodge", "agi"}, {
    { n = "粗制皮鞋", lv = {1,16}, v = {1.00, 0.80} },
    { n = "灵便皮靴", lv = {17,32}, v = {1.40, 1.12} },
    { n = "无声影靴", lv = {33,48}, v = {1.80, 1.44} },
    { n = "刺客软靴", lv = {49,64}, v = {2.20, 1.76} },
    { n = "无踪者靴", lv = {65,80}, v = {2.60, 2.08} },
    { n = "夜行者靴", lv = {81,9999}, v = {3.00, 2.40} },
})

-- 轻甲鞋子A: [主] atkSpeed, [次] agi
addGroup("shoes", "轻甲", nil, {"atkSpeed", "agi"}, {
    { n = "陈旧链靴", lv = {1,16}, v = {1.6, 0.80} },
    { n = "锻铁环靴", lv = {17,32}, v = {2.2, 1.12} },
    { n = "精钢链靴", lv = {33,48}, v = {2.8, 1.44} },
    { n = "骑兵靴", lv = {49,64}, v = {3.4, 1.76} },
    { n = "勇士战靴", lv = {65,80}, v = {4.0, 2.08} },
    { n = "勇者战靴", lv = {81,9999}, v = {4.6, 2.40} },
})

-- 轻甲鞋子B: [主] dodge, [次] agi
addGroup("shoes", "轻甲", nil, {"dodge", "agi"}, {
    { n = "破烂鳞靴", lv = {1,16}, v = {1.00, 0.80} },
    { n = "铜钢鳞靴", lv = {17,32}, v = {1.40, 1.12} },
    { n = "秘银鳞靴", lv = {33,48}, v = {1.80, 1.44} },
    { n = "游侠靴", lv = {49,64}, v = {2.20, 1.76} },
    { n = "监视者靴", lv = {65,80}, v = {2.60, 2.08} },
    { n = "神射手靴", lv = {81,9999}, v = {3.00, 2.40} },
})

-- 重甲鞋子A: [主] atkSpeed, [次] agi
addGroup("shoes", "重甲", nil, {"atkSpeed", "agi"}, {
    { n = "硬铁靴", lv = {1,16}, v = {1.6, 0.80} },
    { n = "铸铁靴", lv = {17,32}, v = {2.2, 1.12} },
    { n = "钢制重靴", lv = {33,48}, v = {2.8, 1.44} },
    { n = "骑士靴", lv = {49,64}, v = {3.4, 1.76} },
    { n = "战争之靴", lv = {65,80}, v = {4.0, 2.08} },
    { n = "山岳巨靴", lv = {81,9999}, v = {4.6, 2.40} },
})

-- 重甲鞋子B: [主] dodge, [次] agi
addGroup("shoes", "重甲", nil, {"dodge", "agi"}, {
    { n = "笨重铁靴", lv = {1,16}, v = {1.00, 0.80} },
    { n = "黑铁靴", lv = {17,32}, v = {1.40, 1.12} },
    { n = "覆甲战靴", lv = {33,48}, v = {1.80, 1.44} },
    { n = "银光靴", lv = {49,64}, v = {2.20, 1.76} },
    { n = "金鳞靴", lv = {65,80}, v = {2.60, 2.08} },
    { n = "龙鳞靴", lv = {81,9999}, v = {3.00, 2.40} },
})

-- 板甲鞋子A: [主] atkSpeed, [次] agi
addGroup("shoes", "板甲", nil, {"atkSpeed", "agi"}, {
    { n = "拼接板靴", lv = {1,16}, v = {1.6, 0.80} },
    { n = "全身板靴", lv = {17,32}, v = {2.2, 1.12} },
    { n = "亮面板靴", lv = {33,48}, v = {2.8, 1.44} },
    { n = "圣骑士靴", lv = {49,64}, v = {3.4, 1.76} },
    { n = "帝国靴", lv = {65,80}, v = {4.0, 2.08} },
    { n = "神圣裁决靴", lv = {81,9999}, v = {4.6, 2.40} },
})

-- 板甲鞋子B: [主] dodge, [次] agi
addGroup("shoes", "板甲", nil, {"dodge", "agi"}, {
    { n = "厚重板靴", lv = {1,16}, v = {1.00, 0.80} },
    { n = "鸢制板靴", lv = {17,32}, v = {1.40, 1.12} },
    { n = "银光板靴", lv = {33,48}, v = {1.80, 1.44} },
    { n = "审判官靴", lv = {49,64}, v = {2.20, 1.76} },
    { n = "卫士靴", lv = {65,80}, v = {2.60, 2.08} },
    { n = "元帅靴", lv = {81,9999}, v = {3.00, 2.40} },
})

-- 布甲鞋子A: [主] atkSpeed, [次] agi
addGroup("shoes", "布甲", nil, {"atkSpeed", "agi"}, {
    { n = "粗布鞋", lv = {1,16}, v = {1.6, 0.80} },
    { n = "棉质法鞋", lv = {17,32}, v = {2.2, 1.12} },
    { n = "丝绸导师鞋", lv = {33,48}, v = {2.8, 1.44} },
    { n = "咒法师鞋", lv = {49,64}, v = {3.4, 1.76} },
    { n = "奥术师靴", lv = {65,80}, v = {4.0, 2.08} },
    { n = "大贤者靴", lv = {81,9999}, v = {4.6, 2.40} },
})

-- 布甲鞋子B: [主] dodge, [次] agi
addGroup("shoes", "布甲", nil, {"dodge", "agi"}, {
    { n = "亚麻便鞋", lv = {1,16}, v = {1.00, 0.80} },
    { n = "祭司鞋", lv = {17,32}, v = {1.40, 1.12} },
    { n = "金线法鞋", lv = {33,48}, v = {1.80, 1.44} },
    { n = "微光者靴", lv = {49,64}, v = {2.20, 1.76} },
    { n = "主教靴", lv = {65,80}, v = {2.60, 2.08} },
    { n = "光明圣靴", lv = {81,9999}, v = {3.00, 2.40} },
})

-- ======================== 饰品（36件）========================

-- 戒指（163-174）
addItem("蓝宝石戒", "戒指", "accessory", {1,7}, {{"str", 3.60}})                          -- [主] str
addItem("金光之戒", "戒指", "accessory", {8,9999}, {{"str", 4.28}, {"physCritDmg", 17}})    -- [主] str, [次1] physCritDmg
addItem("珊瑚之戒", "戒指", "accessory", {18,9999}, {{"energyShield", 64.29}, {"esBonus", 4.3}}) -- [主] 能量护盾, [次1] 能量护盾加成
addItem("海灵之戒", "戒指", "accessory", {28,9999}, {{"physAtk", 12.86}, {"physAtkBonus", 4.3}}) -- [主] 物理攻击力, [次1] 物理攻击加成
addItem("黄宝石戒", "戒指", "accessory", {38,9999}, {{"armor", 9.18}, {"armorBonus", 4.3}}) -- [主] 护甲, [次1] 护甲加成
addItem("红宝石戒", "戒指", "accessory", {48,9999}, {{"maxHp", 214}, {"physBlockRate", 5.1}})  -- [主] maxHp, [次1] physBlockRate
addItem("紫宝石戒", "戒指", "accessory", {1,7}, {{"spi", 3.60}})                           -- [主] spi
addItem("宝钻之戒", "戒指", "accessory", {8,9999}, {{"int", 4.28}, {"magCritDmg", 17}})     -- [主] int, [次1] magCritDmg
addItem("月光之戒", "戒指", "accessory", {18,9999}, {{"dodge", 6.43}, {"dodgeBonus", 4.3}}) -- [主] 闪避值, [次1] 闪避加成
addItem("蛋白石戒", "戒指", "accessory", {28,9999}, {{"magAtk", 12.86}, {"magAtkBonus", 4.3}}) -- [主] 魔法攻击力, [次1] 魔法攻击加成
addItem("晶钻之戒", "戒指", "accessory", {38,9999}, {{"hitValue", 8.04}, {"critRate", 2.6}})   -- [主] hitValue, [次1] critRate
addItem("水晶之戒", "戒指", "accessory", {48,9999}, {{"maxHp", 214}, {"magBlockRate", 5.1}})   -- [主] maxHp, [次1] magBlockRate

-- 项链（175-186）
addItem("海灵吊饰", "项链", "accessory", {1,7}, {{"int", 3.60}})                           -- [主] int
addItem("珊瑚吊饰", "项链", "accessory", {8,9999}, {{"str", 4.28}, {"agi", 1.71}})            -- [主] str, [次1] agi
addItem("琥珀挂坠", "项链", "accessory", {18,9999}, {{"luk", 4.28}, {"critDmg", 12.9}})        -- [主] luk, [次1] critDmg
addItem("翠玉挂坠", "项链", "accessory", {28,9999}, {{"maxHp", 214}, {"dodge", 2.57}})         -- [主] maxHp, [次1] dodge
addItem("蓝玉挂坠", "项链", "accessory", {38,9999}, {{"energyShield", 64.29}, {"abnormalRes", 5.1}}) -- [主] 能量护盾, [次1] 异常抗性
addItem("金光挂坠", "项链", "accessory", {48,9999}, {{"magAtk", 12.86}, {"magPen", 5.14}})     -- [主] magAtk, [次1] magPen
addItem("青玉挂坠", "项链", "accessory", {1,7}, {{"agi", 3.60}})                           -- [主] agi
addItem("黄玉挂坠", "项链", "accessory", {8,9999}, {{"vit", 4.28}, {"spi", 1.71}})            -- [主] vit, [次1] spi
addItem("玛瑙挂坠", "项链", "accessory", {18,9999}, {{"hitValue", 8.04}, {"atkSpeed", 6.4}})   -- [主] hitValue, [次1] atkSpeed
addItem("白玉挂坠", "项链", "accessory", {28,9999}, {{"physAtk", 12.86}, {"physDmgBonus", 8.6}}) -- [主] physAtk, [次1] physDmgBonus
addItem("红玉挂坠", "项链", "accessory", {38,9999}, {{"physPen", 12.86}, {"physDmgBonus", 8.6}}) -- [主] physPen, [次1] physDmgBonus
addItem("水晶挂坠", "项链", "accessory", {48,9999}, {{"physAtk", 12.86}, {"physPen", 5.14}})   -- [主] physAtk, [次1] physPen

-- 耳环（187-198）
addItem("蓝宝石耳环", "耳环", "accessory", {1,7}, {{"luk", 3.60}})                         -- [主] luk
addItem("银质耳环",   "耳环", "accessory", {8,9999}, {{"int", 4.28}, {"luk", 1.71}})          -- [主] int, [次1] luk
addItem("珊瑚耳环",   "耳环", "accessory", {18,9999}, {{"healAmount", 12.86}, {"healBonus", 10.3}}) -- [主] healAmount, [次1] healBonus
addItem("海玉耳环",   "耳环", "accessory", {28,9999}, {{"hpRegen", 21.43}, {"healCritDmg", 17}}) -- [主] hpRegen, [次1] healCritDmg
addItem("黄宝石耳环", "耳环", "accessory", {38,9999}, {{"magPen", 12.86}, {"magDmgBonus", 8.6}}) -- [主] magPen, [次1] magDmgBonus
addItem("红宝石耳环", "耳环", "accessory", {48,9999}, {{"maxHp", 214}, {"hpRegen", 8.57}})     -- [主] maxHp, [次1] hpRegen
addItem("珍珠耳环",   "耳环", "accessory", {1,7}, {{"vit", 3.60}})                         -- [主] vit
addItem("紫晶耳环",   "耳环", "accessory", {8,9999}, {{"magPen", 12.86}, {"physPen", 5.14}})  -- [主] magPen, [次1] physPen
addItem("赌徒之环",   "耳环", "accessory", {18,9999}, {{"luk", 4.28}, {"maxDmgBonus", 21.4}})  -- [主] luk, [次1] maxDmgBonus
addItem("羽制耳环",   "耳环", "accessory", {28,9999}, {{"magAtk", 12.86}, {"magDmgBonus", 8.6}}) -- [主] magAtk, [次1] magDmgBonus
addItem("碎玉之环",   "耳环", "accessory", {38,9999}, {{"physPen", 12.86}, {"magPen", 5.14}})  -- [主] physPen, [次1] magPen
addItem("水晶耳环",   "耳环", "accessory", {48,9999}, {{"agi", 4.28}, {"comboRate", 8.6}})     -- [主] agi, [次1] comboRate

-- ======================== 索引构建 ========================

--- 按槽位分组的模板 ID 列表（用于随机掉落）
EquipmentConfig.BY_SLOT = {}
for _, slot in ipairs(EquipmentConfig.SLOTS) do
    EquipmentConfig.BY_SLOT[slot] = {}
end
for id, item in pairs(ITEMS) do
    local list = EquipmentConfig.BY_SLOT[item.slot]
    if list then
        list[#list + 1] = id
    end
end
-- 对每个槽位的 ID 列表排序（按数字部分）
for _, slot in ipairs(EquipmentConfig.SLOTS) do
    local list = EquipmentConfig.BY_SLOT[slot]
    table.sort(list, function(a, b)
        local na = tonumber(string.sub(a, 2)) or 0
        local nb = tonumber(string.sub(b, 2)) or 0
        return na < nb
    end)
end

--- 每个槽位的装备数量
EquipmentConfig.SLOT_COUNT = {}
for slot, counter in pairs(slotCounter) do
    EquipmentConfig.SLOT_COUNT[slot] = counter
end

--- 装备总数
do
    local total = 0
    for _, n in pairs(slotCounter) do
        total = total + n
    end
    EquipmentConfig.TOTAL_COUNT = total
end

-- ======================== 图标路径 ========================

--- 根据装备模板 ID 获取图标路径
---@param templateId string 模板 ID（如 "W1", "O5", "A12", "C3"）
---@return string 图标资源路径
function EquipmentConfig.getIconPath(templateId)
    return "image/装备图标/UI_icon_ZB_" .. templateId .. ".png"
end

--- 根据品质等级获取品质背景框路径
---@param quality number 品质等级（1-6）
---@return string 背景框资源路径
function EquipmentConfig.getQualityBgPath(quality)
    local q = math.min(quality or 1, 6)
    return "image/品质框/UI_icon_ZBBJ_" .. tostring(q) .. ".png"
end

return EquipmentConfig
