-- ============================================================================
-- AttributeDef - 属性定义、元数据、六围派生、攻击/护甲类型
-- 所有属性 key、数值类型、默认值、上限、价值模型集中管理
-- ============================================================================

local AD = {}

-- ======================== 属性 Key 常量 ========================

-- 基础属性（六围）
AD.STR = "str"   -- 力量
AD.AGI = "agi"   -- 敏捷
AD.INT = "int"   -- 智慧
AD.VIT = "vit"   -- 体质
AD.LUK = "luk"   -- 运气
AD.SPI = "spi"   -- 精神

-- 防御属性
AD.MAX_HP           = "maxHp"           -- 生命值上限
AD.MAX_MANA         = "maxMana"         -- 法力值上限
AD.HP               = "hp"              -- 当前生命值（运行时）
AD.ARMOR            = "armor"           -- 护甲（统一，原 physArmor + magArmor 合并）
AD.RESISTANCE       = "resistance"      -- 伤害抗性（由护甲派生，百分比）
AD.ENERGY_SHIELD    = "energyShield"    -- 能量护盾上限
AD.ES_REGEN_INTERVAL = "esRegenInterval" -- 能量护盾恢复间隔（秒）
-- 向后兼容别名（旧代码/旧存档引用）
AD.PHYS_ARMOR       = "armor"           -- [兼容] 物理护甲 → 护甲
AD.MAG_ARMOR        = "energyShield"    -- [兼容] 魔法护甲 → 能量护盾
AD.PHYS_RES         = "resistance"      -- [兼容] 物理抗性 → 伤害抗性
AD.MAG_RES          = "resistance"      -- [兼容] 魔法抗性 → 伤害抗性
AD.DODGE            = "dodge"           -- 闪避值
AD.THREAT           = "threat"          -- 仇恨值
AD.HP_REGEN         = "hpRegen"         -- 每秒回血
AD.ATK_HEAL         = "atkHeal"         -- 攻击回血
AD.PHYS_BLOCK_RATE  = "physBlockRate"   -- 物理格挡概率
AD.PHYS_BLOCK_RATIO = "physBlockRatio"  -- 物理格挡比例
AD.MAG_BLOCK_RATE   = "magBlockRate"    -- 魔法格挡概率
AD.MAG_BLOCK_RATIO  = "magBlockRatio"   -- 魔法格挡比例
AD.ABNORMAL_RES     = "abnormalRes"     -- 异常抗性
AD.HP_BONUS         = "hpBonus"         -- 生命加成（%）
AD.DODGE_BONUS      = "dodgeBonus"     -- 闪避加成（%）
AD.ES_REGEN_SPEED   = "esRegenSpeed"   -- 能量护盾恢复速度（%）
AD.ES_BONUS         = "esBonus"        -- 能量护盾加成（%）
AD.ES_DMG_REDUCE    = "esDmgReduce"   -- 能量护盾伤害减免（%）
AD.ARMOR_BONUS      = "armorBonus"     -- 护甲加成（%）

-- 攻击属性
AD.PHYS_ATK       = "physAtk"       -- 物理攻击力
AD.MAG_ATK        = "magAtk"        -- 魔法攻击力
AD.ATK_INTERVAL   = "atkInterval"   -- 攻击间隔（秒）
AD.ATK_SPEED      = "atkSpeed"      -- 攻击速度（%）
AD.CRIT_RATE      = "critRate"      -- 通用暴击率（%）
AD.CRIT_DMG       = "critDmg"       -- 通用暴击伤害（%）
AD.PHYS_CRIT_RATE = "physCritRate"  -- 物理暴击率（%）
AD.PHYS_CRIT_DMG  = "physCritDmg"   -- 物理暴击伤害（%）
AD.MAG_CRIT_RATE  = "magCritRate"   -- 魔法暴击率（%）
AD.MAG_CRIT_DMG   = "magCritDmg"    -- 魔法暴击伤害（%）
AD.PHYS_PEN       = "physPen"       -- 物理穿透
AD.MAG_PEN        = "magPen"        -- 魔法穿透
AD.DMG_BONUS      = "dmgBonus"      -- 通用伤害加成（%）
AD.PHYS_DMG_BONUS = "physDmgBonus"  -- 物理伤害加成（%）
AD.MAG_DMG_BONUS  = "magDmgBonus"   -- 魔法伤害加成（%）
AD.COMBO_RATE     = "comboRate"     -- 连击概率（%）
AD.COMBO_DMG_UP   = "comboDmgUp"    -- 连击增伤（%）
AD.MAX_DMG_BONUS  = "maxDmgBonus"   -- 最大伤害加成（%）
AD.MIN_DMG_BONUS  = "minDmgBonus"   -- 最小伤害加成（%）
AD.HIT_VALUE      = "hitValue"      -- 命中值
AD.PHYS_ATK_BONUS = "physAtkBonus"  -- 物理攻击加成（%）
AD.MAG_ATK_BONUS  = "magAtkBonus"   -- 魔法攻击加成（%）

-- 魔化最终属性（最终乘区，单位：百分点）
AD.FINAL_PHYS_ATK_BONUS      = "finalPhysAtkBonus"      -- 最终物攻（%）
AD.FINAL_MAG_ATK_BONUS       = "finalMagAtkBonus"       -- 最终魔攻（%）
AD.FINAL_HP_BONUS            = "finalHpBonus"           -- 最终生命（%）
AD.FINAL_DAMAGE_BONUS        = "finalDamageBonus"       -- 最终伤害（%）
AD.FINAL_STR_BONUS           = "finalStrBonus"          -- 最终力量（%）
AD.FINAL_AGI_BONUS           = "finalAgiBonus"          -- 最终敏捷（%）
AD.FINAL_INT_BONUS           = "finalIntBonus"          -- 最终智慧（%）
AD.FINAL_VIT_BONUS           = "finalVitBonus"          -- 最终体质（%）
AD.FINAL_LUK_BONUS           = "finalLukBonus"          -- 最终运气（%）
AD.FINAL_SPI_BONUS           = "finalSpiBonus"          -- 最终精神（%）
AD.FINAL_ARMOR_BONUS         = "finalArmorBonus"        -- 最终护甲（%）
AD.FINAL_ENERGY_SHIELD_BONUS = "finalEnergyShieldBonus" -- 最终能量护盾（%）
AD.FINAL_DODGE_BONUS         = "finalDodgeBonus"        -- 最终闪避（%）

-- 治疗属性
AD.HEAL_AMOUNT    = "healAmount"    -- 治疗量
AD.HEAL_BONUS     = "healBonus"     -- 治疗加成（%）
AD.HEAL_CRIT_RATE = "healCritRate"  -- 治疗暴击率（%）
AD.HEAL_CRIT_DMG  = "healCritDmg"   -- 治疗暴击加成（%）

-- ======================== 六围 Key 列表 ========================

AD.BASE_STATS = { AD.STR, AD.AGI, AD.INT, AD.VIT, AD.LUK, AD.SPI }

-- 基础六围对应的魔化最终加成 key
AD.FINAL_BASE_STAT_BONUS = {
    [AD.STR] = AD.FINAL_STR_BONUS,
    [AD.AGI] = AD.FINAL_AGI_BONUS,
    [AD.INT] = AD.FINAL_INT_BONUS,
    [AD.VIT] = AD.FINAL_VIT_BONUS,
    [AD.LUK] = AD.FINAL_LUK_BONUS,
    [AD.SPI] = AD.FINAL_SPI_BONUS,
}

-- 常规最终属性对应的魔化最终加成 key
AD.FINAL_ATTR_BONUS = {
    [AD.PHYS_ATK]      = AD.FINAL_PHYS_ATK_BONUS,
    [AD.MAG_ATK]       = AD.FINAL_MAG_ATK_BONUS,
    [AD.MAX_HP]        = AD.FINAL_HP_BONUS,
    [AD.ARMOR]         = AD.FINAL_ARMOR_BONUS,
    [AD.ENERGY_SHIELD] = AD.FINAL_ENERGY_SHIELD_BONUS,
    [AD.DODGE]         = AD.FINAL_DODGE_BONUS,
}

-- ======================== 数值类型 ========================

AD.TYPE_INT   = "int"     -- 整数
AD.TYPE_FLOAT = "float"   -- 小数
AD.TYPE_PCT   = "pct"     -- 百分比（存储为百分数，如 200 表示 200%）

-- ======================== 属性元数据 ========================
-- name       : 中文名
-- valueModel : 价值模型（平衡权值）
--              ★ 非百分比属性(int/float): valueModel = 1 点该属性的价值
--              ★ 百分比属性(pct):        valueModel = 100% (即100个百分点) 的价值
--                 → 1 个百分点的价值 = valueModel / 100
--              示例: 暴击率 valueModel=100 → 100%暴击率 = 100价值 → 1%暴击率 = 1价值
--              示例: 物理攻击力 valueModel=0.5 → 1点物攻 = 0.5价值
-- dataType   : 数值类型 int/float/pct
-- default    : 默认基础值
-- cap        : 上限（nil = 无上限）

AD.META = {
    -- 基础属性（六围）
    [AD.STR] = { name = "力量",   valueModel = 5,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.AGI] = { name = "敏捷",   valueModel = 5,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.INT] = { name = "智慧",   valueModel = 5,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.VIT] = { name = "体质",   valueModel = 5,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.LUK] = { name = "运气",   valueModel = 5,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.SPI] = { name = "精神",   valueModel = 5,  dataType = AD.TYPE_FLOAT, default = 0 },

    -- 防御属性
    [AD.MAX_HP]           = { name = "生命值",       valueModel = 0.03, dataType = AD.TYPE_INT,   default = 0 },
    [AD.MAX_MANA]         = { name = "法力值",       valueModel = 0,    dataType = AD.TYPE_INT,   default = 0 },
    [AD.HP]               = { name = "当前生命",     valueModel = 0,    dataType = AD.TYPE_INT,   default = 0 },
    [AD.ARMOR]            = { name = "护甲",         valueModel = 0.7,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.RESISTANCE]       = { name = "伤害抗性",     valueModel = 0,    dataType = AD.TYPE_PCT,   default = 0 },
    [AD.ENERGY_SHIELD]    = { name = "能量护盾",     valueModel = 0.1,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.ES_REGEN_INTERVAL] = { name = "护盾恢复间隔", valueModel = 0,   dataType = AD.TYPE_FLOAT, default = 1.2 },
    [AD.DODGE]            = { name = "闪避值",       valueModel = 1,    dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.THREAT]           = { name = "仇恨值",       valueModel = 0.08, dataType = AD.TYPE_INT,   default = 1 },
    [AD.HP_REGEN]         = { name = "每秒回血",     valueModel = 0.3,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.ATK_HEAL]         = { name = "攻击回血",     valueModel = 0.45, dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.PHYS_BLOCK_RATE]  = { name = "物理格挡概率", valueModel = 50,   dataType = AD.TYPE_PCT,   default = 0,  cap = 100 },
    [AD.PHYS_BLOCK_RATIO] = { name = "物理格挡比例", valueModel = 0,    dataType = AD.TYPE_PCT,   default = 60, cap = 80 },
    [AD.MAG_BLOCK_RATE]   = { name = "魔法格挡概率", valueModel = 50,   dataType = AD.TYPE_PCT,   default = 0,  cap = 100 },
    [AD.MAG_BLOCK_RATIO]  = { name = "魔法格挡比例", valueModel = 0,    dataType = AD.TYPE_PCT,   default = 60, cap = 80 },
    [AD.ABNORMAL_RES]     = { name = "异常抗性",     valueModel = 50,   dataType = AD.TYPE_PCT,   default = 0,  cap = 80 },
    [AD.HP_BONUS]         = { name = "生命加成",       valueModel = 60,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.DODGE_BONUS]      = { name = "闪避加成",       valueModel = 60,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.ES_REGEN_SPEED]   = { name = "护盾恢复速度",   valueModel = 0,    dataType = AD.TYPE_PCT,   default = 0 },
    [AD.ES_BONUS]         = { name = "能量护盾加成",   valueModel = 60,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.ES_DMG_REDUCE]    = { name = "能量护盾伤害减免", valueModel = 60, dataType = AD.TYPE_PCT,   default = 20, cap = 80 },
    [AD.ARMOR_BONUS]      = { name = "护甲加成",       valueModel = 60,   dataType = AD.TYPE_PCT,   default = 0 },

    -- 攻击属性
    [AD.PHYS_ATK]       = { name = "物理攻击力",   valueModel = 0.5,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.MAG_ATK]        = { name = "魔法攻击力",   valueModel = 0.5,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.ATK_INTERVAL]   = { name = "攻击间隔",     valueModel = 40,   dataType = AD.TYPE_FLOAT, default = 1.0 },
    [AD.ATK_SPEED]      = { name = "攻击速度",     valueModel = 40,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.CRIT_RATE]      = { name = "暴击率",       valueModel = 100,  dataType = AD.TYPE_PCT,   default = 0 },
    [AD.CRIT_DMG]       = { name = "暴击伤害",     valueModel = 20,   dataType = AD.TYPE_PCT,   default = 200 },
    [AD.PHYS_CRIT_RATE] = { name = "物理暴击率",   valueModel = 80,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.PHYS_CRIT_DMG]  = { name = "物理暴击伤害", valueModel = 15,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.MAG_CRIT_RATE]  = { name = "魔法暴击率",   valueModel = 80,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.MAG_CRIT_DMG]   = { name = "魔法暴击伤害", valueModel = 15,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.PHYS_PEN]       = { name = "物理穿透",     valueModel = 0.5,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.MAG_PEN]        = { name = "魔法穿透",     valueModel = 0.5,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.DMG_BONUS]      = { name = "伤害加成",     valueModel = 40,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.PHYS_DMG_BONUS] = { name = "物理伤害加成", valueModel = 30,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.MAG_DMG_BONUS]  = { name = "魔法伤害加成", valueModel = 30,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.COMBO_RATE]     = { name = "连击概率",     valueModel = 30,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.COMBO_DMG_UP]   = { name = "连击增伤",     valueModel = 60,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.MAX_DMG_BONUS]  = { name = "最大伤害加成", valueModel = 12,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.MIN_DMG_BONUS]  = { name = "最小伤害加成", valueModel = 10,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.HIT_VALUE]      = { name = "命中值",       valueModel = 0.8,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.PHYS_ATK_BONUS] = { name = "物理攻击加成", valueModel = 60,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.MAG_ATK_BONUS]  = { name = "魔法攻击加成", valueModel = 60,   dataType = AD.TYPE_PCT,   default = 0 },

    -- 魔化最终属性
    [AD.FINAL_PHYS_ATK_BONUS]      = { name = "最终物攻",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_MAG_ATK_BONUS]       = { name = "最终魔攻",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_HP_BONUS]            = { name = "最终生命",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_DAMAGE_BONUS]        = { name = "最终伤害",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_STR_BONUS]           = { name = "最终力量",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_AGI_BONUS]           = { name = "最终敏捷",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_INT_BONUS]           = { name = "最终智慧",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_VIT_BONUS]           = { name = "最终体质",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_LUK_BONUS]           = { name = "最终运气",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_SPI_BONUS]           = { name = "最终精神",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_ARMOR_BONUS]         = { name = "最终护甲",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_ENERGY_SHIELD_BONUS] = { name = "最终能量护盾",   valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },
    [AD.FINAL_DODGE_BONUS]         = { name = "最终闪避",       valueModel = 60, dataType = AD.TYPE_PCT, default = 0 },

    -- 治疗属性
    [AD.HEAL_AMOUNT]    = { name = "治疗量",       valueModel = 0.5,  dataType = AD.TYPE_FLOAT, default = 0 },
    [AD.HEAL_BONUS]     = { name = "治疗加成",     valueModel = 25,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.HEAL_CRIT_RATE] = { name = "治疗暴击率",   valueModel = 80,   dataType = AD.TYPE_PCT,   default = 0 },
    [AD.HEAL_CRIT_DMG]  = { name = "治疗暴击加成", valueModel = 15,   dataType = AD.TYPE_PCT,   default = 200 },
}

-- ======================== 六围派生表 ========================
-- 每 1 点基础属性 → 对目标属性增加 perPoint 的数值
-- 目标为 pct 类型时，perPoint 单位是百分点

-- ======================== 属性说明（用于 UI 气泡提示） ========================

AD.DESC = {
    -- 基础属性（六围）
    [AD.STR] = "每1点增加1物理攻击力、0.5%物理伤害加成、1.0护甲、5生命值",
    [AD.AGI] = "每1点增加0.5物理攻击力、0.5魔法攻击力、0.4%攻击速度、0.15护甲、0.1%闪避加成、0.4命中值、0.35闪避值",
    [AD.INT] = "每1点增加1魔法攻击力、0.5%魔法伤害加成、3.0能量护盾、0.5%能量护盾加成、8生命值",
    [AD.VIT] = "每1点增加33生命值、0.5%护甲加成、2.0能量护盾",
    [AD.LUK] = "每1点增加0.5物理攻击力、0.5魔法攻击力、0.5%最大伤害加成、0.3%暴击概率、1.5%暴击伤害、0.34闪避值",
    [AD.SPI] = "每1点增加2.5能量护盾、0.5%能量护盾加成、0.1%异常状态抗性、1治疗量、0.4%治疗加成、10生命值",

    -- 防御属性
    [AD.MAX_HP]           = "单位生命值，归零则判定死亡",
    [AD.ARMOR]            = "将同比转化为伤害抗性，转化率 = 0.01×护甲/(0.01×护甲+1)",
    [AD.RESISTANCE]       = "通常只能通过护甲转化而来",
    [AD.ENERGY_SHIELD]    = "受到生命值伤害之前先消耗能量护盾，该值为能量护盾上限",
    [AD.ES_REGEN_INTERVAL] = "基础值为1.2秒，能量护盾恢复间隔",
    [AD.DODGE]            = "影响被命中概率，命中率=(命中值+150)/(闪避值+150)",
    [AD.THREAT]           = "影响被敌方随机攻击的权重，仇恨值越高越容易被集火",
    [AD.HP_REGEN]         = "每秒恢复的生命值，可被治疗属性增幅",
    [AD.ATK_HEAL]         = "每次攻击时回复的生命值，可被治疗属性增幅",
    [AD.PHYS_BLOCK_RATE]  = "有概率格挡物理伤害，格挡后只受到(1-格挡比例)的伤害，上限100%",
    [AD.PHYS_BLOCK_RATIO] = "物理格挡时减免的伤害比例，基础60%，上限80%",
    [AD.MAG_BLOCK_RATE]   = "有概率格挡魔法伤害，格挡后只受到(1-格挡比例)的伤害，上限100%",
    [AD.MAG_BLOCK_RATIO]  = "魔法格挡时减免的伤害比例，基础60%，上限80%",
    [AD.ABNORMAL_RES]     = "减少受到的异常状态持续时间，上限80%",
    [AD.HP_BONUS]         = "百分比增加生命值上限",
    [AD.DODGE_BONUS]     = "百分比增加闪避值",

    -- 攻击属性
    [AD.PHYS_ATK]       = "单位基础物理攻击力",
    [AD.MAG_ATK]        = "单位基础魔法攻击力",
    [AD.ATK_INTERVAL]   = "每多少秒攻击一次，仅作为基础属性",
    [AD.ATK_SPEED]      = "影响攻击间隔的百分比加成，实际间隔=基础间隔/(1+攻击速度%)",
    [AD.CRIT_RATE]      = "通用暴击率，同时作用于物理伤害与魔法伤害",
    [AD.CRIT_DMG]       = "基础200%，暴击时伤害乘以该值，即默认暴击造成2倍伤害",
    [AD.PHYS_CRIT_RATE] = "与暴击率为加法关系，造成物理伤害时额外增加到暴击率计算中",
    [AD.PHYS_CRIT_DMG]  = "基础0%，与暴击伤害为加法关系，物理暴击时额外增加",
    [AD.MAG_CRIT_RATE]  = "与暴击率为加法关系，造成魔法伤害时额外增加到暴击率计算中",
    [AD.MAG_CRIT_DMG]   = "基础0%，与暴击伤害为加法关系，魔法暴击时额外增加",
    [AD.PHYS_PEN]       = "造成物理伤害时与护甲对抗，能1:1抵消目标的护甲",
    [AD.MAG_PEN]        = "造成魔法伤害时与护甲对抗，能1:1抵消目标的护甲",
    [AD.DMG_BONUS]      = "通用伤害加成，同时作用于物理伤害与魔法伤害",
    [AD.PHYS_DMG_BONUS] = "所有伤害加成为加法关系，造成物理伤害时计入",
    [AD.MAG_DMG_BONUS]  = "所有伤害加成为加法关系，造成魔法伤害时计入",
    [AD.COMBO_RATE]     = "有概率在0.1秒后额外攻击一次，超过100%仍有效",
    [AD.COMBO_DMG_UP]   = "每次连击后增加的额外伤害，逐次递增",
    [AD.MAX_DMG_BONUS]  = "影响角色能造成的最大伤害加成",
    [AD.MIN_DMG_BONUS]  = "影响角色能造成的最小伤害加成",
    [AD.HIT_VALUE]      = "影响命中概率，命中率=(命中值+150)/(闪避值+150)",
    [AD.PHYS_ATK_BONUS] = "百分比增加物理攻击力",
    [AD.MAG_ATK_BONUS]  = "百分比增加魔法攻击力",

    -- 魔化最终属性
    [AD.FINAL_PHYS_ATK_BONUS]      = "最终乘区百分比增加物理攻击力",
    [AD.FINAL_MAG_ATK_BONUS]       = "最终乘区百分比增加魔法攻击力",
    [AD.FINAL_HP_BONUS]            = "最终乘区百分比增加生命值上限",
    [AD.FINAL_DAMAGE_BONUS]        = "作为独立乘区百分比提高造成的最终伤害",
    [AD.FINAL_STR_BONUS]           = "最终乘区百分比增加力量，并重新计算六围派生",
    [AD.FINAL_AGI_BONUS]           = "最终乘区百分比增加敏捷，并重新计算六围派生",
    [AD.FINAL_INT_BONUS]           = "最终乘区百分比增加智慧，并重新计算六围派生",
    [AD.FINAL_VIT_BONUS]           = "最终乘区百分比增加体质，并重新计算六围派生",
    [AD.FINAL_LUK_BONUS]           = "最终乘区百分比增加运气，并重新计算六围派生",
    [AD.FINAL_SPI_BONUS]           = "最终乘区百分比增加精神，并重新计算六围派生",
    [AD.FINAL_ARMOR_BONUS]         = "最终乘区百分比增加护甲",
    [AD.FINAL_ENERGY_SHIELD_BONUS] = "最终乘区百分比增加能量护盾",
    [AD.FINAL_DODGE_BONUS]         = "最终乘区百分比增加闪避值",

    -- 治疗属性
    [AD.HEAL_AMOUNT]    = "单位基础治疗量",
    [AD.HEAL_BONUS]     = "对治疗值进行百分比加成",
    [AD.HEAL_CRIT_RATE] = "治疗时有概率触发暴击",
    [AD.HEAL_CRIT_DMG]  = "基础200%，治疗暴击时额外乘以该值",
}

--- 获取属性说明文本
---@param key string
---@return string
function AD.getDesc(key)
    return AD.DESC[key] or ""
end

--- 与 CombatFormula.calcAttack / calcHealAttack 一致的有效暴击率
---@param attrs table UnitAttributes
---@param category string "physical"|"magical"|"healing"
---@return number
function AD.getEffectiveCritRate(attrs, category)
    if not attrs then return 0 end
    if category == "healing" then
        return attrs:get(AD.HEAL_CRIT_RATE)
    end
    local rate = attrs:get(AD.CRIT_RATE)
    if category == "physical" then
        rate = rate + attrs:get(AD.PHYS_CRIT_RATE)
    elseif category == "magical" then
        rate = rate + attrs:get(AD.MAG_CRIT_RATE)
    end
    return rate
end

-- ======================== 六围派生表 ========================

AD.DERIVATIVES = {
    [AD.STR] = {
        { attr = AD.PHYS_ATK,       perPoint = 1.0 },   -- +1 物理攻击力
        { attr = AD.PHYS_DMG_BONUS, perPoint = 0.5 },   -- +0.5% 物理伤害加成
        { attr = AD.ARMOR,          perPoint = 1.0 },   -- +1.0 护甲
        { attr = AD.MAX_HP,         perPoint = 5 },     -- +5 生命值
    },
    [AD.AGI] = {
        { attr = AD.PHYS_ATK,      perPoint = 0.5 },   -- +0.5 物理攻击力 (0.25)
        { attr = AD.MAG_ATK,       perPoint = 0.5 },   -- +0.5 魔法攻击力 (0.25)
        { attr = AD.ATK_SPEED,     perPoint = 0.4 },   -- +0.4% 攻击速度 (0.16)
        { attr = AD.ARMOR,         perPoint = 0.15 },  -- +0.15 护甲 (0.105)
        { attr = AD.DODGE_BONUS,   perPoint = 0.1 },   -- +0.1% 闪避加成 (0.06)
        { attr = AD.HIT_VALUE,     perPoint = 0.4 },   -- +0.4 命中值 (0.32)
        { attr = AD.DODGE,         perPoint = 0.35 },  -- +0.35 闪避值 (0.35) = 1.495
    },
    [AD.INT] = {
        { attr = AD.MAG_ATK,        perPoint = 1.0 },   -- +1 魔法攻击力 (0.50)
        { attr = AD.MAG_DMG_BONUS,  perPoint = 0.5 },   -- +0.5% 魔法伤害加成 (0.15)
        { attr = AD.ENERGY_SHIELD,  perPoint = 3.0 },   -- +3.0 能量护盾 (0.30)
        { attr = AD.ES_BONUS,       perPoint = 0.5 },   -- +0.5% 能量护盾加成 (0.30)
        { attr = AD.MAX_HP,         perPoint = 8 },     -- +8 生命值 (0.24) = 1.490
    },
    [AD.VIT] = {
        { attr = AD.MAX_HP,         perPoint = 33 },    -- +33 生命值 (0.99)
        { attr = AD.ARMOR_BONUS,    perPoint = 0.5 },   -- +0.5% 护甲加成 (0.30)
        { attr = AD.ENERGY_SHIELD,  perPoint = 2.0 },   -- +2.0 能量护盾 (0.20) = 1.490
    },
    [AD.LUK] = {
        { attr = AD.PHYS_ATK,      perPoint = 0.5 },  -- +0.5 物理攻击力 (0.25)
        { attr = AD.MAG_ATK,       perPoint = 0.5 },  -- +0.5 魔法攻击力 (0.25)
        { attr = AD.MAX_DMG_BONUS, perPoint = 0.5 },  -- +0.5% 最大伤害加成 (0.06)
        { attr = AD.CRIT_RATE,     perPoint = 0.3 },  -- +0.3% 暴击概率 (0.30)
        { attr = AD.CRIT_DMG,      perPoint = 1.5 },  -- +1.5% 暴击伤害 (0.30)
        { attr = AD.DODGE,         perPoint = 0.34 }, -- +0.34 闪避值 (0.34) = 1.500
    },
    [AD.SPI] = {
        { attr = AD.ENERGY_SHIELD, perPoint = 2.5 },   -- +2.5 能量护盾 (0.25)
        { attr = AD.ES_BONUS,      perPoint = 0.5 },   -- +0.5% 能量护盾加成 (0.30)
        { attr = AD.ABNORMAL_RES,  perPoint = 0.1 },   -- +0.1% 异常状态抗性 (0.05)
        { attr = AD.HEAL_AMOUNT,   perPoint = 1.0 },   -- +1 治疗量 (0.50)
        { attr = AD.HEAL_BONUS,    perPoint = 0.4 },   -- +0.4% 治疗加成 (0.10)
        { attr = AD.MAX_HP,        perPoint = 10 },    -- +10 生命值 (0.30) = 1.500
    },
}

-- ======================== 攻击类型 ========================

AD.ATK_SLASH     = 1   -- 斩击（物理）
AD.ATK_CRUSH     = 2   -- 粉碎（物理）
AD.ATK_PIERCE    = 3   -- 穿刺（物理）
AD.ATK_FIRE      = 4   -- 火焰（魔法）
AD.ATK_ICE       = 5   -- 冰霜（魔法）
AD.ATK_LIGHTNING = 6   -- 闪电（魔法）
AD.ATK_SHADOW    = 7   -- 暗影（魔法）
AD.ATK_HOLY      = 8   -- 神圣（治疗）

AD.ATK_TYPE_NAME = {
    [1] = "斩击", [2] = "粉碎", [3] = "穿刺",
    [4] = "火焰", [5] = "冰霜", [6] = "闪电",
    [7] = "暗影", [8] = "神圣",
}

-- 攻击类型 → 伤害大类: "physical" / "magical" / "healing"
AD.ATK_CATEGORY = {
    [1] = "physical", [2] = "physical", [3] = "physical",
    [4] = "magical",  [5] = "magical",  [6] = "magical",
    [7] = "magical",  [8] = "healing",
}

-- ======================== 护甲类型 ========================

AD.ARMOR_LEATHER = 1   -- 皮甲
AD.ARMOR_LIGHT   = 2   -- 轻甲
AD.ARMOR_HEAVY   = 3   -- 重甲
AD.ARMOR_PLATE   = 4   -- 板甲
AD.ARMOR_CLOTH   = 5   -- 布甲

AD.ARMOR_TYPE_NAME = {
    [1] = "皮甲", [2] = "轻甲", [3] = "重甲",
    [4] = "板甲", [5] = "布甲",
}

--- 护甲类型名称 → 枚举值反向映射（用于装备 type 字符串转枚举）
AD.ARMOR_TYPE_ENUM = {
    ["皮甲"] = AD.ARMOR_LEATHER,
    ["轻甲"] = AD.ARMOR_LIGHT,
    ["重甲"] = AD.ARMOR_HEAVY,
    ["板甲"] = AD.ARMOR_PLATE,
    ["布甲"] = AD.ARMOR_CLOTH,
}

-- ======================== 攻击类型 × 护甲类型 伤害倍率表 ========================
-- TYPE_MULT[atkType][armorType] → 伤害倍率（1.0 = 100%，负数 = 治疗）

AD.TYPE_MULT = {
    --                皮甲   轻甲   重甲   板甲   布甲
    [1] = {  1.10,  0.85,  0.95,  0.70,  1.50 },  -- 斩击
    [2] = {  1.20,  1.10,  0.75,  0.60,  1.40 },  -- 粉碎
    [3] = {  0.90,  1.20,  1.10,  0.85,  1.60 },  -- 穿刺
    [4] = {  1.15,  1.10,  1.25,  1.40,  0.75 },  -- 火焰
    [5] = {  1.05,  1.00,  1.15,  1.30,  0.80 },  -- 冰霜
    [6] = {  1.30,  1.25,  1.50,  1.65,  0.65 },  -- 闪电
    [7] = {  1.00,  0.95,  1.05,  1.10,  0.90 },  -- 暗影
    [8] = { -1.00, -1.00, -1.00, -1.00, -1.00 },  -- 神圣（负=治疗）
}

-- ======================== 辅助方法 ========================

--- 获取属性元数据
---@param key string
---@return table|nil
function AD.getMeta(key)
    return AD.META[key]
end

--- 获取属性默认值
---@param key string
---@return number
function AD.getDefault(key)
    local m = AD.META[key]
    return m and m.default or 0
end

--- 获取属性上限（nil = 无上限）
---@param key string
---@return number|nil
function AD.getCap(key)
    local m = AD.META[key]
    return m and m.cap
end

--- 格式化属性详情中的数值展示：显示截断前实际值；超出上限时附加 (+超出量)，不展示上限本身
---@param key string
---@param actualVal number 截断前的实际值
---@return string
function AD.formatAttrDisplayValue(key, actualVal)
    local meta = AD.getMeta(key)
    if not meta then
        return tostring(actualVal)
    end

    local cap = meta.cap
    local over = (cap and actualVal > cap) and (actualVal - cap) or 0

    if meta.dataType == AD.TYPE_PCT then
        if over > 0.05 then
            return string.format("%.1f%% (+%.1f%%)", actualVal, over)
        end
        return string.format("%.1f%%", actualVal)
    elseif meta.dataType == AD.TYPE_FLOAT then
        if over > 0.05 then
            return string.format("%.1f (+%.1f)", actualVal, over)
        end
        return string.format("%.1f", actualVal)
    end

    if over >= 1 then
        return string.format("%d (+%d)", math.floor(actualVal + 0.5), math.floor(over + 0.5))
    end
    return tostring(math.floor(actualVal + 0.5))
end

--- 获取攻击类型对护甲类型的伤害倍率
---@param atkType number 攻击类型 (1-8)
---@param armorType number 护甲类型 (1-5)
---@return number 倍率
function AD.getTypeMult(atkType, armorType)
    local row = AD.TYPE_MULT[atkType]
    if not row then return 1.0 end
    return row[armorType] or 1.0
end

--- 获取攻击类型的伤害大类
---@param atkType number
---@return string "physical"|"magical"|"healing"
function AD.getAtkCategory(atkType)
    return AD.ATK_CATEGORY[atkType] or "physical"
end

return AD
