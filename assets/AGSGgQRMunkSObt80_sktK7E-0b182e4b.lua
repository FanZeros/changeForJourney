-- ============================================================================
-- EquipmentConfig - 装备静态配置表
-- 包含: 198 件装备模板、品质定义、槽位定义、等级缩放系数
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

EquipmentConfig.SLOTS = { "weapon", "offhand", "armor", "accessory" }
EquipmentConfig.SLOT_NAME = {
    weapon    = "主手",
    offhand   = "副手",
    armor     = "护甲",
    accessory = "饰品",
}

-- ======================== 装备模板表 ========================

EquipmentConfig.ITEMS = {}

local ITEMS = EquipmentConfig.ITEMS

-- 每个槽位独立编号，使用前缀字符串 ID
-- 武器: W1~W72, 副手: O1~O30, 护甲: A1~A60, 饰品: C1~C36
local SLOT_PREFIX = {
    weapon    = "W",
    offhand   = "O",
    armor     = "A",
    accessory = "C",
}
EquipmentConfig.SLOT_PREFIX = SLOT_PREFIX

-- 每个槽位的当前计数器
local slotCounter = {
    weapon    = 0,
    offhand   = 0,
    armor     = 0,
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
    { n = "练习用剑",   lv = {1,16},  v = {7.14, 0.89, 1.8} },
    { n = "铁质长剑",   lv = {17,32}, v = {10.00, 1.25, 2.5} },
    { n = "钢制长剑",   lv = {33,48}, v = {12.86, 1.61, 3.2} },
    { n = "骑士佩剑",   lv = {49,64}, v = {15.71, 1.96, 3.9} },
    { n = "叠甲战神之剑", lv = {65,80}, v = {18.57, 2.32, 4.6} },
    { n = "水晶长剑",   lv = {81,9999}, v = {21.43, 2.68, 5.4} },
})

-- 双手剑（7-12）: [主] physAtk, [次1] physPen, [次2] physDmgBonus%
addGroup("weapon", "双手剑", "twohand", {"physAtk", "physPen", "physDmgBonus"}, {
    { n = "练习用大剑", lv = {1,16},  v = {14.29, 2.86, 4.8} },
    { n = "生铁重剑",   lv = {17,32},  v = {20.00, 4.00, 6.7} },
    { n = "黑铁大剑",   lv = {33,48}, v = {25.71, 5.14, 8.6} },
    { n = "斩铁巨刃",   lv = {49,64}, v = {31.43, 6.29, 10.5} },
    { n = "叠甲战神巨剑", lv = {65,80}, v = {37.14, 7.43, 12.4} },
    { n = "水晶大剑",   lv = {81,9999}, v = {42.86, 8.57, 14.3} },
})

-- 单手斧（13-18）: [主] physAtk, [次1] str
addGroup("weapon", "单手斧", "onehand", {"physAtk", "str"}, {
    { n = "伐木斧",     lv = {1,16},  v = {7.14, 0.95} },
    { n = "铁手斧",     lv = {17,32},  v = {10.00, 1.33} },
    { n = "钢斧",       lv = {33,48}, v = {12.86, 1.71} },
    { n = "蛮族利斧",   lv = {49,64}, v = {15.71, 2.10} },
    { n = "掠夺者之斧", lv = {65,80}, v = {18.57, 2.48} },
    { n = "水晶手斧",   lv = {81,9999}, v = {21.43, 2.86} },
})

-- 双手斧（19-24）: [主] physAtk, [次1] maxDmgBonus%, [次2] physDmgBonus%
addGroup("weapon", "双手斧", "twohand", {"physAtk", "maxDmgBonus", "physDmgBonus"}, {
    { n = "双刃巨斧",   lv = {1,16},  v = {14.29, 11.9, 4.8} },
    { n = "铁巨斧",     lv = {17,32},  v = {20.00, 16.7, 6.7} },
    { n = "长柄战斧",   lv = {33,48}, v = {25.71, 21.4, 8.6} },
    { n = "蛮族巨斧",   lv = {49,64}, v = {31.43, 26.2, 10.5} },
    { n = "掠夺者巨斧", lv = {65,80}, v = {37.14, 31.0, 12.4} },
    { n = "水晶巨斧",   lv = {81,9999}, v = {42.86, 35.7, 14.3} },
})

-- 法杖（25-30）: [主] magAtk, [次1] magPen, [次2] magDmgBonus%
addGroup("weapon", "法杖", "twohand", {"magAtk", "magPen", "magDmgBonus"}, {
    { n = "学徒木杖",   lv = {1,16},  v = {14.29, 2.86, 4.8} },
    { n = "符文长杖",   lv = {17,32},  v = {20.00, 4.00, 6.7} },
    { n = "铁质长杖",   lv = {33,48}, v = {25.71, 5.14, 8.6} },
    { n = "银质长杖",   lv = {49,64}, v = {31.43, 6.29, 10.5} },
    { n = "镀金长杖",   lv = {65,80}, v = {37.14, 7.43, 12.4} },
    { n = "水晶长杖",   lv = {81,9999}, v = {42.86, 8.57, 14.3} },
})

-- 魔杖（31-36）: [主] magAtk, [次1] hitValue, [次2] atkSpeed%
addGroup("weapon", "魔杖", "onehand", {"magAtk", "hitValue", "atkSpeed"}, {
    { n = "短魔杖",     lv = {1,16},  v = {7.14, 0.89, 1.8} },
    { n = "符文魔杖",   lv = {17,32},  v = {10.00, 1.25, 2.5} },
    { n = "仪式魔杖",   lv = {33,48}, v = {12.86, 1.61, 3.2} },
    { n = "精灵魔杖",   lv = {49,64}, v = {15.71, 1.96, 3.9} },
    { n = "镀金魔杖",   lv = {65,80}, v = {18.57, 2.32, 4.6} },
    { n = "水晶魔杖",   lv = {81,9999}, v = {21.43, 2.68, 5.4} },
})

-- 弓箭（37-42）: [主] physAtk, [次1] hitValue, [次2] physPen
addGroup("weapon", "弓箭", "twohand", {"physAtk", "hitValue", "physPen"}, {
    { n = "木质短弓",   lv = {1,16},  v = {14.29, 1.79, 2.86} },
    { n = "铁制长弓",   lv = {17,32},  v = {20.00, 2.50, 4.00} },
    { n = "狩猎弓",     lv = {33,48}, v = {25.71, 3.21, 5.14} },
    { n = "游侠弓",     lv = {49,64}, v = {31.43, 3.93, 6.29} },
    { n = "风行者之弓", lv = {65,80}, v = {37.14, 4.64, 7.43} },
    { n = "水晶长弓",   lv = {81,9999}, v = {42.86, 5.36, 8.57} },
})

-- 单手弩（43-48）: [主] physAtk, [次1] atkSpeed%, [次2] hitValue
addGroup("weapon", "单手弩", "onehand", {"physAtk", "atkSpeed", "hitValue"}, {
    { n = "轻弩",       lv = {1,16},  v = {7.14, 1.8, 0.89} },
    { n = "铁弩",       lv = {17,32},  v = {10.00, 2.5, 1.25} },
    { n = "狩猎弩",     lv = {33,48}, v = {12.86, 3.2, 1.61} },
    { n = "游侠弩",     lv = {49,64}, v = {15.71, 3.9, 1.96} },
    { n = "风行者手弩", lv = {65,80}, v = {18.57, 4.6, 2.32} },
    { n = "水晶手弩",   lv = {81,9999}, v = {21.43, 5.4, 2.68} },
})

-- 手铳（49-54）: [主] magAtk, [次1] hitValue, [次2] comboRate%
-- 注意: 配置文档中#49燧发手铳的次要属性顺序与50-54不同（49是连击概率在前），代码统一用 hitValue,comboRate 顺序
addGroup("weapon", "手铳", "onehand", {"magAtk", "hitValue", "comboRate"}, {
    { n = "燧发手铳",   lv = {1,16},  v = {7.14, 0.89, 2.4} },
    { n = "铁质手铳",   lv = {17,32},  v = {10.00, 1.25, 3.3} },
    { n = "短铳",       lv = {33,48}, v = {12.86, 1.61, 4.3} },
    { n = "矮人手枪",   lv = {49,64}, v = {15.71, 1.96, 5.2} },
    { n = "机械手铳",   lv = {65,80}, v = {18.57, 2.32, 6.2} },
    { n = "水晶手枪",   lv = {81,9999}, v = {21.43, 2.68, 7.1} },
})

-- 匕首（55-60）: [主] magAtk, [次1] atkSpeed%, [次2] comboRate%
addGroup("weapon", "匕首", "onehand", {"magAtk", "atkSpeed", "comboRate"}, {
    { n = "玻璃碎片",   lv = {1,16},  v = {7.14, 1.8, 2.4} },
    { n = "铜匕首",     lv = {17,32},  v = {10.00, 2.5, 3.3} },
    { n = "铁匕首",     lv = {33,48}, v = {12.86, 3.2, 4.3} },
    { n = "盗贼短匕",   lv = {49,64}, v = {15.71, 3.9, 5.2} },
    { n = "刺客之刃",   lv = {65,80}, v = {18.57, 4.6, 6.2} },
    { n = "水晶之刃",   lv = {81,9999}, v = {21.43, 5.4, 7.1} },
})

-- 细剑（61-66）: [主] physAtk, [次1] atkSpeed%, [次2] physPen
addGroup("weapon", "细剑", "onehand", {"physAtk", "atkSpeed", "physPen"}, {
    { n = "练习用刺剑", lv = {1,16},  v = {7.14, 1.8, 1.43} },
    { n = "刺剑",       lv = {17,32},  v = {10.00, 2.5, 2.00} },
    { n = "绅士细剑",   lv = {33,48}, v = {12.86, 3.2, 2.57} },
    { n = "练武者细剑", lv = {49,64}, v = {15.71, 3.9, 3.14} },
    { n = "决斗者细剑", lv = {65,80}, v = {18.57, 4.6, 3.71} },
    { n = "水晶刺剑",   lv = {81,9999}, v = {21.43, 5.4, 4.29} },
})

-- 权杖（67-72）: [主] healAmount, [次1] healBonus%
addGroup("weapon", "权杖", "onehand", {"healAmount", "healBonus"}, {
    { n = "木质权杖",   lv = {1,16},  v = {7.14, 5.7} },
    { n = "铁质权杖",   lv = {17,32},  v = {10.00, 8.0} },
    { n = "祭祀权杖",   lv = {33,48}, v = {12.86, 10.3} },
    { n = "主教权杖",   lv = {49,64}, v = {15.71, 12.6} },
    { n = "光之权杖",   lv = {65,80}, v = {18.57, 14.9} },
    { n = "水晶权杖",   lv = {81,9999}, v = {21.43, 17.1} },
})

-- ======================== 副手（30件）========================

-- 轻盾（73-78）: [主] dodge, [次1] atkSpeed%, [次2] physBlockRate%
addGroup("offhand", "轻盾", nil, {"dodge", "atkSpeed", "physBlockRate"}, {
    { n = "陈旧木盾",   lv = {1,16},  v = {3.57, 1.8, 1.4} },
    { n = "镶皮圆盾",   lv = {17,32},  v = {5.00, 2.5, 2.0} },
    { n = "钢边轻鸢盾", lv = {33,48}, v = {6.43, 3.2, 2.6} },
    { n = "斥候疾风盾", lv = {49,64}, v = {7.85, 3.9, 3.1} },
    { n = "守望者轻盾", lv = {65,80}, v = {9.29, 4.6, 3.7} },
    { n = "流光镜盾",   lv = {81,9999}, v = {10.72, 5.4, 4.3} },
})

-- 重盾（79-84）: [主] physArmor, [次1] physBlockRate%, [次2] magBlockRate%
addGroup("offhand", "重盾", nil, {"armor", "physBlockRate", "magBlockRate"}, {
    { n = "厚实木盾",   lv = {1,16},  v = {5.10, 1.4, 1.4} },
    { n = "铸铁方盾",   lv = {17,32},  v = {7.14, 2.0, 2.0} },
    { n = "钢制塔盾",   lv = {33,48}, v = {9.18, 2.6, 2.6} },
    { n = "守卫巨盾",   lv = {49,64}, v = {11.22, 3.1, 3.1} },
    { n = "蛮族巨盾",   lv = {65,80}, v = {13.27, 3.7, 3.7} },
    { n = "水晶巨盾",   lv = {81,9999}, v = {15.31, 4.3, 4.3} },
})

-- 魔典（85-90）: [主] armor, [次1] magPen, [次2] magDmgBonus%
addGroup("offhand", "魔典", nil, {"armor", "magPen", "magDmgBonus"}, {
    { n = "学徒魔典",   lv = {1,16},  v = {5.10, 1.43, 2.4} },
    { n = "见习魔典",   lv = {17,32},  v = {7.14, 2.00, 3.3} },
    { n = "咒文魔典",   lv = {33,48}, v = {9.18, 2.57, 4.3} },
    { n = "秘法魔典",   lv = {49,64}, v = {11.22, 3.14, 5.2} },
    { n = "奥术魔典",   lv = {65,80}, v = {13.27, 3.71, 6.2} },
    { n = "大法师魔典", lv = {81,9999}, v = {15.31, 4.29, 7.1} },
})

-- 法珠（91-96）: [主] 能量护盾, [次1] 魔法格挡概率%, [次2] 魔法穿透
addGroup("offhand", "法珠", nil, {"energyShield", "magBlockRate", "magPen"}, {
    { n = "学徒法珠",   lv = {1,16},  v = {35.71, 1.4, 1.43} },
    { n = "见习法珠",   lv = {17,32},  v = {50.00, 2.0, 2.00} },
    { n = "魔力法珠",   lv = {33,48}, v = {64.29, 2.6, 2.57} },
    { n = "闪光法珠",   lv = {49,64}, v = {78.57, 3.1, 3.14} },
    { n = "奥术法珠",   lv = {65,80}, v = {92.86, 3.7, 3.71} },
    { n = "水晶法珠",   lv = {81,9999}, v = {107.14, 4.3, 4.29} },
})

-- 圣物（97-102）: [主] 能量护盾, [次1] 治疗暴击率%, [次2] 治疗暴击加成%
addGroup("offhand", "圣物", nil, {"energyShield", "healCritRate", "healCritDmg"}, {
    { n = "木质圣杯",   lv = {1,16},  v = {35.71, 0.9, 4.8} },
    { n = "铁质圣杯",   lv = {17,32},  v = {50.00, 1.3, 6.7} },
    { n = "祭祀圣杯",   lv = {33,48}, v = {64.29, 1.6, 8.6} },
    { n = "主教圣杯",   lv = {49,64}, v = {78.57, 2.0, 10.5} },
    { n = "光之圣杯",   lv = {65,80}, v = {92.86, 2.3, 12.4} },
    { n = "水晶圣杯",   lv = {81,9999}, v = {107.14, 2.7, 14.3} },
})

-- ======================== 护甲（60件）========================

-- 皮甲A（103-108）: [主] maxHp, [次1] dodge
addGroup("armor", "皮甲", nil, {"maxHp", "dodge"}, {
    { n = "磨损皮衣",   lv = {1,16},  v = {119, 1.43} },
    { n = "皮制胸甲",   lv = {17,32},  v = {167, 2.00} },
    { n = "镶钉皮甲",   lv = {33,48}, v = {214, 2.57} },
    { n = "巡林客外套", lv = {49,64}, v = {262, 3.14} },
    { n = "追猎者战衣", lv = {65,80}, v = {310, 3.71} },
    { n = "蛇皮软甲",   lv = {81,9999}, v = {357, 4.29} },
})

-- 皮甲B（109-114）: [主] 生命值, [次1] 护甲, [次2] 能量护盾
addGroup("armor", "皮甲", nil, {"maxHp", "armor", "energyShield"}, {
    { n = "粗制皮背心", lv = {1,16},  v = {119, 1.02, 7.14} },
    { n = "灵便皮外套", lv = {17,32},  v = {167, 1.43, 10.00} },
    { n = "无声影皮甲", lv = {33,48}, v = {214, 1.84, 12.86} },
    { n = "刺客夜行服", lv = {49,64}, v = {262, 2.24, 15.71} },
    { n = "无踪者秘装", lv = {65,80}, v = {310, 2.65, 18.57} },
    { n = "夜行者风衣", lv = {81,9999}, v = {357, 3.06, 21.43} },
})

-- 轻甲A（115-120）: [主] maxHp, [次1] physArmor
addGroup("armor", "轻甲", nil, {"maxHp", "armor"}, {
    { n = "陈旧锁子甲", lv = {1,16},  v = {119, 1.02} },
    { n = "锻铁环甲",   lv = {17,32},  v = {167, 1.43} },
    { n = "精钢链甲衫", lv = {33,48}, v = {214, 1.84} },
    { n = "骑兵胸甲",   lv = {49,64}, v = {262, 2.24} },
    { n = "勇士战铠",   lv = {65,80}, v = {310, 2.65} },
    { n = "勇者战甲",   lv = {81,9999}, v = {357, 3.06} },
})

-- 轻甲B（121-126）: [主] maxHp, [次1] physArmor, [次2] dodge
addGroup("armor", "轻甲", nil, {"maxHp", "armor", "dodge"}, {
    { n = "破烂鳞甲",   lv = {1,16},  v = {119, 1.02, 0.71} },
    { n = "铜钢鳞甲",   lv = {17,32},  v = {167, 1.43, 1.00} },
    { n = "秘银鳞甲",   lv = {33,48}, v = {214, 1.84, 1.29} },
    { n = "游侠之鳞",   lv = {49,64}, v = {262, 2.24, 1.57} },
    { n = "监视者之服", lv = {65,80}, v = {310, 2.65, 1.86} },
    { n = "神射手之衣", lv = {81,9999}, v = {357, 3.06, 2.14} },
})

-- 重甲A（127-132）: [主] 生命值, [次1] 能量护盾, [次2] 生命加成%
addGroup("armor", "重甲", nil, {"maxHp", "energyShield", "hpBonus"}, {
    { n = "硬铁重衣",   lv = {1,16},  v = {119, 7.14, 1.2} },
    { n = "铸铁重甲",   lv = {17,32},  v = {167, 10.00, 1.7} },
    { n = "钢制重甲",   lv = {33,48}, v = {214, 12.86, 2.1} },
    { n = "骑士重铠",   lv = {49,64}, v = {262, 15.71, 2.6} },
    { n = "战争之铠",   lv = {65,80}, v = {310, 18.57, 3.1} },
    { n = "山岳巨铠",   lv = {81,9999}, v = {357, 21.43, 3.6} },
})

-- 重甲B（133-138）: [主] maxHp, [次1] physArmor, [次2] hpBonus
addGroup("armor", "重甲", nil, {"maxHp", "armor", "hpBonus"}, {
    { n = "笨重铁甲",   lv = {1,16},  v = {119, 1.02, 1.2} },
    { n = "黑铁胸铠",   lv = {17,32},  v = {167, 1.43, 1.7} },
    { n = "全身覆甲",   lv = {33,48}, v = {214, 1.84, 2.1} },
    { n = "银光亮铠",   lv = {49,64}, v = {262, 2.24, 2.6} },
    { n = "金鳞之甲",   lv = {65,80}, v = {310, 2.65, 3.1} },
    { n = "龙鳞之甲",   lv = {81,9999}, v = {357, 3.06, 3.6} },
})

-- 板甲A（139-144）: [主] maxHp, [次1] hpBonus, [次2] physArmor
addGroup("armor", "板甲", nil, {"maxHp", "hpBonus", "armor"}, {
    { n = "拼接板甲",   lv = {1,16},  v = {119, 1.2, 1.02} },
    { n = "全身板甲",   lv = {17,32},  v = {167, 1.7, 1.43} },
    { n = "亮面板甲",   lv = {33,48}, v = {214, 2.1, 1.84} },
    { n = "圣骑士板甲", lv = {49,64}, v = {262, 2.6, 2.24} },
    { n = "帝国之铠",   lv = {65,80}, v = {310, 3.1, 2.65} },
    { n = "神圣裁决铠", lv = {81,9999}, v = {357, 3.6, 3.06} },
})

-- 板甲B（145-150）: [主] maxHp, [次1] hpBonus, [次2] magArmor
addGroup("armor", "板甲", nil, {"maxHp", "hpBonus", "energyShield"}, {
    { n = "厚重板甲",   lv = {1,16},  v = {119, 1.2, 1.02} },
    { n = "鸢制板甲",   lv = {17,32},  v = {167, 1.7, 1.43} },
    { n = "银光版甲",   lv = {33,48}, v = {214, 2.1, 1.84} },
    { n = "审判官板甲", lv = {49,64}, v = {262, 2.6, 2.24} },
    { n = "卫士之甲",   lv = {65,80}, v = {310, 3.1, 2.65} },
    { n = "元帅之甲",   lv = {81,9999}, v = {357, 3.6, 3.06} },
})

-- 布甲A（151-156）: [主] 生命值, [次1] 能量护盾
addGroup("armor", "布甲", nil, {"maxHp", "energyShield"}, {
    { n = "粗布长袍",   lv = {1,16},  v = {119, 14.29} },
    { n = "棉质法袍",   lv = {17,32},  v = {167, 20.00} },
    { n = "丝绸导师袍", lv = {33,48}, v = {214, 25.71} },
    { n = "咒法师长袍", lv = {49,64}, v = {262, 31.43} },
    { n = "奥术师之袍", lv = {65,80}, v = {310, 37.14} },
    { n = "大贤者之袍", lv = {81,9999}, v = {357, 42.86} },
})

-- 布甲B（157-162）: [主] 能量护盾, [次1] 能量护盾加成%
addGroup("armor", "布甲", nil, {"energyShield", "esBonus"}, {
    { n = "亚麻衬衣",   lv = {1,16},  v = {35.71, 1.2} },
    { n = "祭司法袍",   lv = {17,32},  v = {50.00, 1.7} },
    { n = "金线刺绣袍", lv = {33,48}, v = {64.29, 2.1} },
    { n = "微光者法袍", lv = {49,64}, v = {78.57, 2.6} },
    { n = "主教礼袍",   lv = {65,80}, v = {92.86, 3.1} },
    { n = "光明圣袍",   lv = {81,9999}, v = {107.14, 3.6} },
})

-- ======================== 饰品（36件）========================

-- 戒指（163-174）
addItem("蓝宝石戒", "戒指", "accessory", {1,7}, {{"str", 4.00}})                          -- [主] str
addItem("金光之戒", "戒指", "accessory", {8,9999}, {{"str", 4.76}, {"physCritDmg", 19.0}})    -- [主] str, [次1] physCritDmg
addItem("珊瑚之戒", "戒指", "accessory", {18,9999}, {{"energyShield", 71.43}, {"esBonus", 4.8}}) -- [主] 能量护盾, [次1] 能量护盾加成
addItem("海灵之戒", "戒指", "accessory", {28,9999}, {{"physAtk", 14.29}, {"physAtkBonus", 4.8}}) -- [主] 物理攻击力, [次1] 物理攻击加成
addItem("黄宝石戒", "戒指", "accessory", {38,9999}, {{"armor", 10.20}, {"armorBonus", 4.8}}) -- [主] 护甲, [次1] 护甲加成
addItem("红宝石戒", "戒指", "accessory", {48,9999}, {{"maxHp", 238}, {"physBlockRate", 5.7}})  -- [主] maxHp, [次1] physBlockRate
addItem("紫宝石戒", "戒指", "accessory", {1,7}, {{"spi", 4.00}})                           -- [主] spi
addItem("宝钻之戒", "戒指", "accessory", {8,9999}, {{"int", 4.76}, {"magCritDmg", 19.0}})     -- [主] int, [次1] magCritDmg
addItem("月光之戒", "戒指", "accessory", {18,9999}, {{"dodge", 7.14}, {"dodgeBonus", 4.8}}) -- [主] 闪避值, [次1] 闪避加成
addItem("蛋白石戒", "戒指", "accessory", {28,9999}, {{"magAtk", 14.29}, {"magAtkBonus", 4.8}}) -- [主] 魔法攻击力, [次1] 魔法攻击加成
addItem("晶钻之戒", "戒指", "accessory", {38,9999}, {{"hitValue", 8.93}, {"critRate", 2.9}})   -- [主] hitValue, [次1] critRate
addItem("水晶之戒", "戒指", "accessory", {48,9999}, {{"maxHp", 238}, {"magBlockRate", 5.7}})   -- [主] maxHp, [次1] magBlockRate

-- 项链（175-186）
addItem("海灵吊饰", "项链", "accessory", {1,7}, {{"int", 4.00}})                           -- [主] int
addItem("珊瑚吊饰", "项链", "accessory", {8,9999}, {{"str", 4.76}, {"agi", 1.90}})            -- [主] str, [次1] agi
addItem("琥珀挂坠", "项链", "accessory", {18,9999}, {{"luk", 4.76}, {"critDmg", 14.3}})        -- [主] luk, [次1] critDmg
addItem("翠玉挂坠", "项链", "accessory", {28,9999}, {{"maxHp", 238}, {"dodge", 2.86}})         -- [主] maxHp, [次1] dodge
addItem("蓝玉挂坠", "项链", "accessory", {38,9999}, {{"energyShield", 71.43}, {"abnormalRes", 5.7}}) -- [主] 能量护盾, [次1] 异常抗性
addItem("金光挂坠", "项链", "accessory", {48,9999}, {{"magAtk", 14.29}, {"magPen", 5.71}})     -- [主] magAtk, [次1] magPen
addItem("青玉挂坠", "项链", "accessory", {1,7}, {{"agi", 4.00}})                           -- [主] agi
addItem("黄玉挂坠", "项链", "accessory", {8,9999}, {{"vit", 4.76}, {"spi", 1.90}})            -- [主] vit, [次1] spi
addItem("玛瑙挂坠", "项链", "accessory", {18,9999}, {{"hitValue", 8.93}, {"atkSpeed", 7.1}})   -- [主] hitValue, [次1] atkSpeed
addItem("白玉挂坠", "项链", "accessory", {28,9999}, {{"physAtk", 14.29}, {"physDmgBonus", 9.5}}) -- [主] physAtk, [次1] physDmgBonus
addItem("红玉挂坠", "项链", "accessory", {38,9999}, {{"physPen", 14.29}, {"physDmgBonus", 9.5}}) -- [主] physPen, [次1] physDmgBonus
addItem("水晶挂坠", "项链", "accessory", {48,9999}, {{"physAtk", 14.29}, {"physPen", 5.71}})   -- [主] physAtk, [次1] physPen

-- 耳环（187-198）
addItem("蓝宝石耳环", "耳环", "accessory", {1,7}, {{"luk", 4.00}})                         -- [主] luk
addItem("银质耳环",   "耳环", "accessory", {8,9999}, {{"int", 4.76}, {"luk", 1.90}})          -- [主] int, [次1] luk
addItem("珊瑚耳环",   "耳环", "accessory", {18,9999}, {{"healAmount", 14.29}, {"healBonus", 11.4}}) -- [主] healAmount, [次1] healBonus
addItem("海玉耳环",   "耳环", "accessory", {28,9999}, {{"hpRegen", 23.81}, {"healCritDmg", 19.0}}) -- [主] hpRegen, [次1] healCritDmg
addItem("黄宝石耳环", "耳环", "accessory", {38,9999}, {{"magPen", 14.29}, {"magDmgBonus", 9.5}}) -- [主] magPen, [次1] magDmgBonus
addItem("红宝石耳环", "耳环", "accessory", {48,9999}, {{"maxHp", 238}, {"hpRegen", 9.52}})     -- [主] maxHp, [次1] hpRegen
addItem("珍珠耳环",   "耳环", "accessory", {1,7}, {{"vit", 4.00}})                         -- [主] vit
addItem("紫晶耳环",   "耳环", "accessory", {8,9999}, {{"magPen", 14.29}, {"physPen", 5.71}})  -- [主] magPen, [次1] physPen
addItem("赌徒之环",   "耳环", "accessory", {18,9999}, {{"luk", 4.76}, {"maxDmgBonus", 23.8}})  -- [主] luk, [次1] maxDmgBonus
addItem("羽制耳环",   "耳环", "accessory", {28,9999}, {{"magAtk", 14.29}, {"magDmgBonus", 9.5}}) -- [主] magAtk, [次1] magDmgBonus
addItem("碎玉之环",   "耳环", "accessory", {38,9999}, {{"physPen", 14.29}, {"magPen", 5.71}})  -- [主] physPen, [次1] magPen
addItem("水晶耳环",   "耳环", "accessory", {48,9999}, {{"agi", 4.76}, {"comboRate", 9.5}})     -- [主] agi, [次1] comboRate

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
EquipmentConfig.TOTAL_COUNT = slotCounter.weapon + slotCounter.offhand + slotCounter.armor + slotCounter.accessory

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
    return "image/UI_icon_ZBBJ_" .. tostring(q) .. ".png"
end

return EquipmentConfig
