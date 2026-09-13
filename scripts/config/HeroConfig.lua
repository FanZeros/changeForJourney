-- ============================================================================
-- HeroConfig - 英雄角色配置数据表 + 工厂函数
-- 数据来源: docs/配置文件/角色配置.txt
-- 包含: 20个英雄角色（品质/职业/六围/成长/天赋/攻击类型）
-- ============================================================================

local AD = require("systems.AttributeDef")
local CC = require("config.ClassConfig")
local UnitAttributes = require("systems.UnitAttributes")
local AVC = require("config.AdvancementConfig")
local TalentEffect = require("systems.TalentEffect")
local ExpTable = require("config.ExpTable")

local HC = {}

-- 天赋星图：默认的已点亮节点列表（由 ChurchPage 同步）
local _defaultLitNodes = nil

--- 设置默认天赋星图已点亮节点（所有 createHero 调用自动使用）
---@param nodes table|nil 已点亮节点 ID 列表
function HC.setDefaultLitNodes(nodes)
    _defaultLitNodes = nodes
end

--- 获取当前默认天赋星图节点（供外部暂存/恢复使用）
---@return table|nil
function HC._getSavedLitNodes()
    return _defaultLitNodes
end

-- ======================== 品质常量 ========================

HC.QUALITY_R   = 1
HC.QUALITY_SR  = 2
HC.QUALITY_SSR = 3
HC.QUALITY_UR  = 4

HC.QUALITY_INFO = {
    [1] = { name = "R",   color = "a0a0a0" },    -- 灰色
    [2] = { name = "SR",  color = "a2a0ff" },     -- 紫蓝
    [3] = { name = "SSR", color = "ffed00" },     -- 金色
    [4] = { name = "UR",  color = "ff6a00" },     -- 橙红
}

-- ======================== 伤害类型常量 ========================

--- 伤害主类型（对应角色配置.txt "伤害主类型"列）
HC.DMG_PHYSICAL = "物理"
HC.DMG_MAGICAL  = "魔法"
HC.DMG_HEALING  = "治疗"

--- 攻击次类型中文名 → AD 枚举映射
local ATK_TYPE_MAP = {
    ["斩击"] = AD.ATK_SLASH,
    ["粉碎"] = AD.ATK_CRUSH,
    ["穿刺"] = AD.ATK_PIERCE,
    ["火焰"] = AD.ATK_FIRE,
    ["冰霜"] = AD.ATK_ICE,
    ["闪电"] = AD.ATK_LIGHTNING,
    ["暗影"] = AD.ATK_SHADOW,
    ["神圣"] = AD.ATK_HOLY,
    ["治疗"] = AD.ATK_HOLY,   -- "治疗"映射为神圣类型（机制相同）
}

-- ======================== 英雄配置表 ========================
-- id           : 英雄序号 (1~15, 16, 20~23)
-- quality      : 品质 (1=R, 2=SR, 3=SSR, 4=UR)
-- classId      : 职业 ID (对应 ClassConfig)
-- title        : 称谓
-- name         : 名字
-- talentName   : 天赋技能名
-- talentDesc   : 天赋技能效果描述
-- talentId     : 天赋内部 ID
-- gender       : 性别 ("female")
-- atkType      : 伤害次类型 (AD.ATK_*)
-- atkInterval  : 攻击间隔(秒)
-- atkTargets   : 攻击目标数
-- dmgSpread    : 最大与最小伤害波动比例 (如 0.10 = 10%)
-- atkCoeff     : 攻击伤害系数
-- baseStats    : 初始六围 { str, agi, int, vit, luk, spi }
-- growthStats  : 成长六围 { str, agi, int, vit, luk, spi }

HC.HEROES = {
    [1] = {
        quality = 1, classId = CC.WARRIOR,
        title = "汪卫先锋", name = "大狗嚼",
        talentName = "希望之心", talentDesc = "生命值低于70%时，物理攻击力+25%",
        talentId = "karin_hope",
        gender = "female",
        atkType = AD.ATK_SLASH, atkInterval = 1.4, atkTargets = 1,
        dmgSpread = 0.10, atkCoeff = 1.4,
        baseStats  = { str = 12.50, agi = 7.50,  int = 3.75,  vit = 7.50,  luk = 3.75,  spi = 5.00 },
        growthStats = { str = 0.75,  agi = 0.38,  int = 0.00,  vit = 0.38,  luk = 0.00,  spi = 0.00 },
    },
    [2] = {
        quality = 1, classId = CC.MAGE,
        title = "火球一本龙", name = "黄桃龙",
        talentName = "火焰精通", talentDesc = "攻击附加持续2秒的[燃烧]效果，对其每秒造成[魔法攻击力*0.2]的火焰伤害",
        talentId = "maki_fire",
        gender = "female",
        atkType = AD.ATK_FIRE, atkInterval = 2.6, atkTargets = 2,
        dmgSpread = 0.15, atkCoeff = 1.44,
        baseStats  = { str = 3.75,  agi = 5.00,  int = 12.50, vit = 3.75,  luk = 7.50,  spi = 7.50 },
        growthStats = { str = 0.00,  agi = 0.00,  int = 0.75,  vit = 0.00,  luk = 0.38,  spi = 0.38 },
    },
    [3] = {
        quality = 1, classId = CC.RANGER,
        title = "等通知哨兵", name = "叮咚鸡",
        talentName = "精准箭矢", talentDesc = "每3次攻击时造成1.5倍伤害",
        talentId = "linda_precision_arrow",
        gender = "female",
        atkType = AD.ATK_PIERCE, atkInterval = 2.0, atkTargets = 1,
        dmgSpread = 0.08, atkCoeff = 2.0,
        baseStats  = { str = 7.50,  agi = 12.50, int = 3.75,  vit = 5.00,  luk = 7.50,  spi = 3.75 },
        growthStats = { str = 0.38,  agi = 0.75,  int = 0.00,  vit = 0.00,  luk = 0.38,  spi = 0.00 },
    },
    [4] = {
        quality = 2, classId = CC.KNIGHT,
        title = "浑元形意宗师", name = "接化发掌门",
        talentName = "骑士招架", talentDesc = "物理格挡概率+8% 魔法格挡概率+8%，格挡成功时回复3%最大生命值",
        talentId = "cecilia_parry",
        gender = "female",
        atkType = AD.ATK_CRUSH, atkInterval = 2.7, atkTargets = 1,
        dmgSpread = 0.20, atkCoeff = 5.4,
        baseStats  = { str = 9.75,  agi = 6.50,  int = 3.25,  vit = 16.25, luk = 6.50,  spi = 9.75 },
        growthStats = { str = 0.50,  agi = 0.00,  int = 0.00,  vit = 1.00,  luk = 0.00,  spi = 0.50 },
    },
    [5] = {
        quality = 2, classId = CC.WARRIOR,
        title = "叠甲战神", name = "叠甲怪",
        talentName = "战斗征服", talentDesc = "每次攻击为自己增加1层[征服]状态，每层提供2%物理攻击力，最多叠加15层",
        talentId = "victoria_conquer",
        gender = "female",
        atkType = AD.ATK_PIERCE, atkInterval = 1.2, atkTargets = 1,
        dmgSpread = 0.15, atkCoeff = 2.4,
        baseStats  = { str = 16.25, agi = 9.75,  int = 3.25,  vit = 9.75,  luk = 6.50,  spi = 6.50 },
        growthStats = { str = 1.00,  agi = 0.50,  int = 0.00,  vit = 0.50,  luk = 0.00,  spi = 0.00 },
    },
    [6] = {
        quality = 2, classId = CC.MAGE,
        title = "电音天后", name = "阿姨压",
        talentName = "闪电精通", talentDesc = "攻击附加持续2秒的[感电]效果，感电使其受到20%额外伤害",
        talentId = "luna_lightning",
        gender = "female",
        atkType = AD.ATK_LIGHTNING, atkInterval = 3.2, atkTargets = 3,
        dmgSpread = 0.30, atkCoeff = 2.46,
        baseStats  = { str = 3.25,  agi = 9.75,  int = 16.25, vit = 6.50,  luk = 9.75,  spi = 6.50 },
        growthStats = { str = 0.00,  agi = 0.50,  int = 1.00,  vit = 0.00,  luk = 0.50,  spi = 0.00 },
    },
    [7] = {
        quality = 2, classId = CC.RANGER,
        title = "光之巨人", name = "信光机兵",
        talentName = "闪光协议", talentDesc = "每4次攻击后，下一次攻击连击概率+200%",
        talentId = "hoshiori_flash",
        gender = "female",
        atkType = AD.ATK_LIGHTNING, atkInterval = 1.5, atkTargets = 2,
        dmgSpread = 0.08, atkCoeff = 1.67,
        baseStats  = { str = 3.25,  agi = 16.25, int = 9.75,  vit = 6.50,  luk = 6.50,  spi = 9.75 },
        growthStats = { str = 0.00,  agi = 1.00,  int = 0.50,  vit = 0.00,  luk = 0.00,  spi = 0.50 },
    },
    [8] = {
        quality = 2, classId = CC.ASSASSIN,
        title = "弹弓怒鸟", name = "愤怒的小雀",
        talentName = "弹弓怒鸟之眼", talentDesc = "战斗开始时[标记]一个随机敌人，使其受到的伤害+25%",
        talentId = "ayane_mark",
        gender = "female",
        atkType = AD.ATK_SLASH, atkInterval = 1.0, atkTargets = 2,
        dmgSpread = 0.25, atkCoeff = 1.11,
        baseStats  = { str = 9.75,  agi = 9.75,  int = 3.25,  vit = 6.50,  luk = 16.25, spi = 6.50 },
        growthStats = { str = 0.50,  agi = 0.50,  int = 0.00,  vit = 0.00,  luk = 1.00,  spi = 0.00 },
    },
    [9] = {
        quality = 2, classId = CC.PRIEST,
        title = "温泉教主", name = "卡皮巴拉",
        talentName = "自然之愈", talentDesc = "每当进行攻击治疗后，使目标在5秒内每秒恢复治疗量的10%",
        talentId = "flora_regen",
        gender = "female",
        atkType = AD.ATK_HOLY, atkInterval = 2.0, atkTargets = 2,
        dmgSpread = 0.15, atkCoeff = 1.33,
        baseStats  = { str = 3.25,  agi = 6.50,  int = 9.75,  vit = 9.75,  luk = 6.50,  spi = 16.25 },
        growthStats = { str = 0.00,  agi = 0.00,  int = 0.50,  vit = 0.50,  luk = 0.00,  spi = 1.00 },
    },
    [10] = {
        quality = 3, classId = CC.KNIGHT,
        title = "扛门大将军", name = "铁憨憨",
        talentName = "帝国铁壁", talentDesc = "生命加成+20%、仇恨倍率×1.5。战斗中为所有队友承受15%伤害。",
        talentId = "rebecca_bulwark",
        gender = "female",
        atkType = AD.ATK_CRUSH, atkInterval = 2.2, atkTargets = 2,
        dmgSpread = 0.20, atkCoeff = 4.89,
        baseStats  = { str = 12.75, agi = 8.50,  int = 8.50,  vit = 21.25, luk = 4.25,  spi = 12.75 },
        growthStats = { str = 0.63,  agi = 0.00,  int = 0.00,  vit = 1.25,  luk = 0.00,  spi = 0.63 },
    },
    [11] = {
        quality = 3, classId = CC.WARRIOR,
        title = "熬夜修仙党", name = "熬夜冠军",
        talentName = "夜华斩", talentDesc = "每攻击4次斩出2道斩击，斩击优先命中不同敌人，没有多余敌人时可命中同一敌人，造成物理攻击力200%的斩击伤害",
        talentId = "suhua_nightslash",
        gender = "female",
        atkType = AD.ATK_SLASH, atkInterval = 1.6, atkTargets = 1,
        dmgSpread = 0.15, atkCoeff = 6.4,
        baseStats  = { str = 21.25, agi = 12.75, int = 4.25,  vit = 12.75, luk = 8.50,  spi = 8.50 },
        growthStats = { str = 1.25,  agi = 0.63,  int = 0.00,  vit = 0.63,  luk = 0.00,  spi = 0.00 },
    },
    [12] = {
        quality = 3, classId = CC.MAGE,
        title = "甜蜜冰后", name = "雪皇",
        talentName = "冰霜精通", talentDesc = "攻击命中敌人时有25%概率[冰冻]1.5秒，使其攻击冷却进度暂停",
        talentId = "astrid_freeze",
        gender = "female",
        atkType = AD.ATK_ICE, atkInterval = 4.0, atkTargets = 4,
        dmgSpread = 0.30, atkCoeff = 4.71,
        baseStats  = { str = 4.25,  agi = 8.50,  int = 21.25, vit = 8.50,  luk = 12.75, spi = 12.75 },
        growthStats = { str = 0.00,  agi = 0.00,  int = 1.25,  vit = 0.00,  luk = 0.63,  spi = 0.63 },
    },
    [13] = {
        quality = 3, classId = CC.RANGER,
        title = "鱼尾纹克星", name = "弹弹弹",
        talentName = "弹射箭矢", talentDesc = "射出的箭矢将在敌人之间弹射1次",
        talentId = "rosalyn_ricochet",
        gender = "female",
        atkType = AD.ATK_PIERCE, atkInterval = 1.2, atkTargets = 1,
        dmgSpread = 0.05, atkCoeff = 4.8,
        baseStats  = { str = 17.00, agi = 17.00, int = 6.80,  vit = 6.80,  luk = 10.20, spi = 10.20 },
        growthStats = { str = 1.25,  agi = 1.25,  int = 0.00,  vit = 0.00,  luk = 0.00,  spi = 0.00 },
    },
    [14] = {
        quality = 3, classId = CC.ASSASSIN,
        title = "藏得最深的人", name = "内鬼",
        talentName = "暴击精通", talentDesc = "暴击概率+15% 暴击伤害+50%",
        talentId = "yuuya_crit_mastery",
        gender = "female",
        atkType = AD.ATK_SHADOW, atkInterval = 0.9, atkTargets = 1,
        dmgSpread = 0.35, atkCoeff = 3.6,
        baseStats  = { str = 4.00,  agi = 12.00, int = 20.00, vit = 4.00,  luk = 20.00, spi = 8.00 },
        growthStats = { str = 0.00,  agi = 0.50,  int = 1.00,  vit = 0.00,  luk = 1.00,  spi = 0.00 },
    },
    [15] = {
        quality = 3, classId = CC.PRIEST,
        title = "急救复活甲", name = "复活吧爱人",
        talentName = "圣光复活", talentDesc = "当复活吧爱人在场时其他角色首次死亡时有25%概率立即使其复活",
        talentId = "elizabeth_revive",
        gender = "female",
        atkType = AD.ATK_HOLY, atkInterval = 2.0, atkTargets = 3,
        dmgSpread = 0.15, atkCoeff = 1.85,
        baseStats  = { str = 4.25,  agi = 8.50,  int = 12.75, vit = 8.50,  luk = 12.75, spi = 21.25 },
        growthStats = { str = 0.00,  agi = 0.00,  int = 0.63,  vit = 0.00,  luk = 0.63,  spi = 1.25 },
    },
    [16] = {
        quality = 4, classId = CC.WARRIOR,
        title = "御剑飞行家", name = "万剑归宗",
        talentName = "灵月飞剑", talentDesc = "每隔5秒在周围生成3-6柄飞剑，朝随机敌人飞去，每柄飞剑造成的伤害为这5秒中该角色的累计伤害的50%，仅产生10%仇恨",
        talentId = "luoxing_flying_sword",
        gender = "female",
        atkType = AD.ATK_PIERCE, atkInterval = 1.5, atkTargets = 2,
        dmgSpread = 0.15, atkCoeff = 6.67,
        baseStats  = { str = 24.44, agi = 9.78,  int = 4.89,  vit = 24.44, luk = 14.67, spi = 9.78 },
        growthStats = { str = 1.20,  agi = 0.00,  int = 0.00,  vit = 1.20,  luk = 0.60,  spi = 0.00 },
    },
    [20] = {
        quality = 4, classId = CC.MAGE,
        title = "太空出差人", name = "摘星星星人",
        talentName = "星之守护", talentDesc = "战斗开始召唤[星门]，每2.6秒造成300%魔伤且不产生仇恨。继承摘星星星人与队友魔伤、魔穿150%；攻速/连击缩短间隔，最多40%。连击积累[星痕]，每层使下次星辉伤害+12%，最多5层。",
        talentId = "melissa_star_gate",
        gender = "female",
        atkType = AD.ATK_SHADOW, atkInterval = 3.0, atkTargets = 1,
        dmgSpread = 0.30, atkCoeff = 24.0,
        baseStats  = { str = 5.50,  agi = 16.50, int = 27.50, vit = 11.00, luk = 16.50, spi = 11.00 },
        growthStats = { str = 0.00,  agi = 0.75,  int = 1.50,  vit = 0.00,  luk = 0.75,  spi = 0.00 },
    },
    [21] = {
        quality = 3, classId = CC.WARRIOR,
        title = "赛道之王", name = "闪电卖鸡",
        talentName = "银光", talentDesc = "每次攻击有25%概率触发[银光]，额外造成物理伤害×150%的闪电伤害，并使目标麻痹0.3秒（进度条暂停）。每拥有80命中率，触发概率+2%（最多额外增加20%）",
        talentId = "alex_silver_flash",
        gender = "male",
        atkType = AD.ATK_SLASH, atkInterval = 3.0, atkTargets = 2,
        dmgSpread = 0.15, atkCoeff = 6.67,
        baseStats  = { str = 18.89, agi = 18.89, int = 3.78,  vit = 11.33, luk = 7.56,  spi = 7.56 },
        growthStats = { str = 1.00,  agi = 1.00,  int = 0.00,  vit = 0.50,  luk = 0.00,  spi = 0.00 },
    },
    [22] = {
        quality = 3, classId = CC.MAGE,
        title = "两年半练习生", name = "小黑子",
        talentName = "法术机关枪", talentDesc = "每攻击20次时，在短时间内连续攻击10次",
        talentId = "sera_spell_gatling",
        gender = "male",
        atkType = AD.ATK_LIGHTNING, atkInterval = 1.2, atkTargets = 1,
        dmgSpread = 0.30, atkCoeff = 4.8,
        baseStats  = { str = 3.78,  agi = 7.56,  int = 18.89, vit = 7.56,  luk = 18.89, spi = 11.33 },
        growthStats = { str = 0.00,  agi = 0.00,  int = 1.00,  vit = 0.00,  luk = 1.00,  spi = 0.50 },
    },
    [23] = {
        quality = 3, classId = CC.PRIEST,
        title = "即兴说唱王", name = "真布诗人",
        talentName = "能量祝福", talentDesc = "每次攻击治疗命中后，溢出治疗能够完全转为能量护盾；并且溢出治疗转化的能量护盾可溢出为临时能量护盾，最多可溢出为目标能量护盾的50%",
        talentId = "elwyn_energy_blessing",
        gender = "male",
        atkType = AD.ATK_HOLY, atkInterval = 1.5, atkTargets = 3,
        dmgSpread = 0.15, atkCoeff = 1.38,
        baseStats  = { str = 4.25,  agi = 12.75, int = 12.75, vit = 8.50,  luk = 8.50,  spi = 21.25 },
        growthStats = { str = 0.00,  agi = 0.63,  int = 0.63,  vit = 0.00,  luk = 0.00,  spi = 1.25 },
    },
}

-- ======================== 伤害类型数据（角色配置.txt 伤害主类型 + 伤害次类型） ========================
-- dmgMainType: 伤害主类型中文名（物理/魔法/治疗）
-- dmgSubType:  伤害次类型中文名（斩击/粉碎/穿刺/火焰/冰霜/闪电/暗影/神圣/治疗）

local DMG_TYPE_DATA = {
    [1]  = { HC.DMG_PHYSICAL, "斩击" },   -- 大狗嚼
    [2]  = { HC.DMG_MAGICAL,  "火焰" },   -- 黄桃龙
    [3]  = { HC.DMG_PHYSICAL, "穿刺" },   -- 叮咚鸡
    [4]  = { HC.DMG_PHYSICAL, "粉碎" },   -- 接化发掌门
    [5]  = { HC.DMG_PHYSICAL, "穿刺" },   -- 叠甲怪
    [6]  = { HC.DMG_MAGICAL,  "闪电" },   -- 阿姨压
    [7]  = { HC.DMG_MAGICAL,  "闪电" },   -- 信光机兵
    [8]  = { HC.DMG_PHYSICAL, "斩击" },   -- 愤怒的小雀
    [9]  = { HC.DMG_HEALING,  "治疗" },   -- 卡皮巴拉
    [10] = { HC.DMG_PHYSICAL, "粉碎" },   -- 铁憨憨
    [11] = { HC.DMG_PHYSICAL, "斩击" },   -- 熬夜冠军
    [12] = { HC.DMG_MAGICAL,  "冰霜" },   -- 雪皇
    [13] = { HC.DMG_PHYSICAL, "穿刺" },   -- 弹弹弹
    [14] = { HC.DMG_MAGICAL,  "暗影" },   -- 内鬼
    [15] = { HC.DMG_HEALING,  "神圣" },   -- 复活吧爱人
    [16] = { HC.DMG_PHYSICAL, "穿刺" },   -- 万剑归宗
    [20] = { HC.DMG_MAGICAL,  "暗影" },   -- 摘星星星人
    [21] = { HC.DMG_PHYSICAL, "斩击" },   -- 闪电卖鸡
    [22] = { HC.DMG_MAGICAL,  "闪电" },   -- 小黑子
    [23] = { HC.DMG_HEALING,  "神圣" },   -- 真布诗人
}

for id, dmgData in pairs(DMG_TYPE_DATA) do
    if HC.HEROES[id] then
        HC.HEROES[id].dmgMainType = dmgData[1]
        HC.HEROES[id].dmgSubType  = dmgData[2]
    end
end

-- ======================== 可穿戴装备类型（角色配置.txt 最后两列） ========================
-- weaponTypes  : 可穿戴主武器子类型列表（与 EquipmentConfig.ITEMS[id].type 匹配）
-- offhandTypes : 可穿戴副手子类型列表（与 EquipmentConfig.ITEMS[id].type 匹配）

local WEARABLE_DATA = {
    [1]  = { w = {"单手剑","双手剑","单手斧","双手斧"},       o = {"轻盾","重盾"} },       -- 大狗嚼(战士)
    [2]  = { w = {"法杖","魔杖"},                             o = {"魔典","法珠"} },       -- 黄桃龙(法师)
    [3]  = { w = {"弓箭","单手弩"},                           o = {"轻盾","重盾"} },       -- 叮咚鸡(游侠)
    [4]  = { w = {"单手剑","双手剑","单手斧","双手斧"},       o = {"重盾","圣物"} },       -- 接化发掌门(骑士)
    [5]  = { w = {"单手剑","双手剑","单手斧","双手斧"},       o = {"轻盾","重盾"} },       -- 叠甲怪(战士)
    [6]  = { w = {"法杖","魔杖"},                             o = {"魔典","法珠"} },       -- 阿姨压(法师)
    [7]  = { w = {"手铳","魔杖"},                             o = {"魔典","法珠"} },       -- 信光机兵(游侠)
    [8]  = { w = {"细剑","单手剑"},                           o = {"轻盾","重盾"} },       -- 愤怒的小雀(刺客)
    [9]  = { w = {"权杖"},                                    o = {"轻盾","圣物"} },       -- 卡皮巴拉(牧师)
    [10] = { w = {"单手剑","双手剑","单手斧","双手斧"},       o = {"重盾","圣物"} },       -- 铁憨憨(骑士)
    [11] = { w = {"单手剑","双手剑","单手斧","双手斧"},       o = {"轻盾","重盾"} },       -- 熬夜冠军(战士)
    [12] = { w = {"法杖","魔杖"},                             o = {"魔典","法珠"} },       -- 雪皇(法师)
    [13] = { w = {"弓箭","单手弩"},                           o = {"轻盾","重盾"} },       -- 弹弹弹(游侠)
    [14] = { w = {"手铳","匕首","魔杖"},                      o = {"魔典","法珠"} },       -- 内鬼(刺客)
    [15] = { w = {"权杖"},                                    o = {"轻盾","圣物"} },       -- 复活吧爱人(牧师)
    [16] = { w = {"单手剑","双手剑","单手斧","双手斧"},       o = {"轻盾","重盾"} },       -- 万剑归宗(战士)
    [20] = { w = {"法杖","魔杖"},                             o = {"魔典","法珠"} },       -- 摘星星星人(法师)
    [21] = { w = {"单手剑","双手剑","单手斧","双手斧"},       o = {"轻盾","重盾"} },       -- 闪电卖鸡(战士)
    [22] = { w = {"法杖","魔杖"},                             o = {"魔典","法珠"} },       -- 小黑子(法师)
    [23] = { w = {"权杖"},                                    o = {"轻盾","圣物"} },       -- 真布诗人(牧师)
}

for id, wData in pairs(WEARABLE_DATA) do
    if HC.HEROES[id] then
        HC.HEROES[id].weaponTypes  = wData.w
        HC.HEROES[id].offhandTypes = wData.o
    end
end

-- ======================== 工厂方法 ========================

--- 创建英雄战斗单位
--- 参照 MonsterConfig.createMonster 的模式，使用 UnitAttributes 创建完整属性的英雄
---@param heroId number 英雄序号 (1~15, 16, 20~23)
---@param level number 英雄等级
---@param advBranch table|nil 转职分支 { first=number?, second=number? }
---@param awakening table|nil 觉醒数据 { [1]=true, [2]=true, ... }
---@return table|nil 战斗单位 { name, level, hp, maxHp, atkProgress, attrs, heroId, classId, ... }
function HC.createHero(heroId, level, advBranch, awakening)
    local hero = HC.HEROES[heroId]
    if not hero then
        print("[HeroConfig] 未知英雄 ID: " .. tostring(heroId))
        return nil
    end

    level = level or 1

    -- 计算属性：基础 + 等级成长（纯线性，无加速倍率）
    local bs = hero.baseStats
    local gs = hero.growthStats
    local effectiveLevel = level - 1   -- 1级时没有成长加成

    -- 六围 = 基础 + 成长 × (等级-1)
    local str = bs.str + gs.str * effectiveLevel
    local agi = bs.agi + gs.agi * effectiveLevel
    local int = bs.int + gs.int * effectiveLevel
    local vit = bs.vit + gs.vit * effectiveLevel
    local luk = bs.luk + gs.luk * effectiveLevel
    local spi = bs.spi + gs.spi * effectiveLevel

    -- 累计基础战斗属性成长（分段递增的 HP 和 ATK，独立于六围派生）
    local growthHp, growthAtk = ExpTable.getAccumulatedBaseGrowth(level)

    -- 获取职业信息
    local classCfg = CC.get(hero.classId)
    local armorType = AD.ARMOR_LEATHER
    if classCfg and classCfg.armorTypes and classCfg.armorTypes[1] then
        armorType = classCfg.armorTypes[1]
    end

    -- 构建属性配置（六围派生 + 每级基础 HP/ATK 成长）
    local category = AD.getAtkCategory(hero.atkType)
    local cfg = {
        [AD.STR] = str,
        [AD.AGI] = agi,
        [AD.INT] = int,
        [AD.VIT] = vit,
        [AD.LUK] = luk,
        [AD.SPI] = spi,
        [AD.MAX_HP]       = growthHp,
        [AD.ATK_INTERVAL] = hero.atkInterval,
        armorType         = armorType,
        atkType           = hero.atkType,
    }
    -- 根据伤害主类型分配 ATK 成长：物理 → physAtk，魔法/治疗 → magAtk
    if category == "physical" then
        cfg[AD.PHYS_ATK] = growthAtk
    else
        cfg[AD.MAG_ATK] = growthAtk
    end

    -- 创建 UnitAttributes
    local attrs = UnitAttributes.create(cfg)

    -- 应用职业基础属性加成
    CC.applyStatBonus(hero.classId, attrs)

    -- 应用职业天赋
    CC.applyTalent(hero.classId, attrs)

    -- 应用角色特有天赋（作为 modifier，含觉醒增强）
    HC._applyHeroTalent(heroId, attrs, awakening)

    -- 应用转职属性加成（一转+二转的 statBonus 叠加）
    if advBranch then
        AVC.applyStatBonuses(advBranch, attrs)
    end

    -- 应用天赋星图加成
    if _defaultLitNodes then
        TalentEffect.applyToUnit(attrs, _defaultLitNodes, hero.classId)
    end

    -- 攻击伤害系数 & 伤害波动比例（存入 attrs 供 CombatFormula 读取）
    attrs.atkCoeff  = hero.atkCoeff  or 1.0
    attrs.dmgSpread = hero.dmgSpread or 0.0

    -- 满血
    attrs:fillHp()

    -- 构建战斗单位
    local unit = attrs:toBattleUnit(hero.name, level)
    unit.atkInterval = attrs:getActualInterval()
    unit.heroId      = heroId
    unit.classId     = hero.classId
    unit.className   = classCfg and classCfg.name or "未知"
    unit.quality     = hero.quality
    unit.qualityName = HC.QUALITY_INFO[hero.quality] and HC.QUALITY_INFO[hero.quality].name or "?"
    unit.title       = hero.title
    unit.talentName  = hero.talentName
    unit.talentDesc  = hero.talentDesc
    unit.atkTargets  = hero.atkTargets
    unit.dmgSpread   = hero.dmgSpread
    unit.atkCoeff    = hero.atkCoeff
    unit.dmgMainType = hero.dmgMainType
    unit.dmgSubType  = hero.dmgSubType

    -- 转职信息（供 TalentManager / UI 使用）
    unit.advBranch   = advBranch
    unit.advTalentIds = {}
    if advBranch then
        local branches = AVC.getAllBranches(advBranch)
        for _, bId in ipairs(branches) do
            local bCfg = AVC.get(bId)
            if bCfg and bCfg.talentId then
                unit.advTalentIds[#unit.advTalentIds + 1] = bCfg.talentId
            end
        end
    end
    -- [DIAG-ADV] 牧师转职排查：打印创建时的 advTalentIds
    if heroId == 9 or heroId == 15 then
        local tidStr = #unit.advTalentIds > 0 and table.concat(unit.advTalentIds, ",") or "EMPTY"
        local abStr = advBranch and string.format("{first=%s,second=%s}",
            tostring(advBranch.first), tostring(advBranch.second)) or "nil"
        print(string.format("[DIAG-ADV] createHero id=%d name=%s advBranch=%s advTalentIds=[%s]",
            heroId, tostring(unit.name), abStr, tidStr))
    end

    -- 觉醒信息（供 TalentManager 使用）
    unit.awakeningNodes = {}
    if awakening then
        for k, v in pairs(awakening) do
            if v then
                unit.awakeningNodes[tonumber(k) or k] = true
            end
        end
    end

    -- 天赋星图运行时节点集合（供 TalentManager 检查 RUNTIME_ONLY 节点）
    unit.litNodeSet = {}
    if _defaultLitNodes then
        for _, nodeId in ipairs(_defaultLitNodes) do
            unit.litNodeSet[nodeId] = true
        end
    end

    return unit
end

--- 内部：应用英雄特有天赋到属性（非通用职业天赋）
---@param heroId number
---@param attrs table UnitAttributes
---@param awakening table|nil 觉醒数据 { [1]=true, ... }
function HC._applyHeroTalent(heroId, attrs, awakening)
    local hero = HC.HEROES[heroId]
    if not hero then return end

    local awk = awakening or {}
    local entries = {}

    -- 骑士 接化发掌门 #4: 物理格挡概率+8% 魔法格挡概率+8%
    if heroId == 4 then
        entries[#entries + 1] = { key = AD.PHYS_BLOCK_RATE, flat = 8 }
        entries[#entries + 1] = { key = AD.MAG_BLOCK_RATE, flat = 8 }
        -- 觉醒5: 物理/魔法格挡比例提升10%
        if awk[5] then
            entries[#entries + 1] = { key = AD.PHYS_BLOCK_RATIO, flat = 10 }
            entries[#entries + 1] = { key = AD.MAG_BLOCK_RATIO, flat = 10 }
        end
    -- 游侠 弹弹弹 #13: 觉醒2 物理穿透+10（固定面板属性，需在首次伤害计算前生效）
    elseif heroId == 13 then
        if awk[2] or awk["2"] then
            entries[#entries + 1] = { key = AD.PHYS_PEN, flat = 10 }
        end
    -- 刺客 内鬼 #14: 暴击概率+15% 暴击伤害+50%
    elseif heroId == 14 then
        -- 觉醒3: 暴击率 15→25
        local critRate = 15
        if awk[3] then critRate = 25 end
        -- 觉醒1: 暴击伤害 50→75
        local critDmg = 50
        if awk[1] then critDmg = 75 end
        entries[#entries + 1] = { key = AD.CRIT_RATE, flat = critRate }
        entries[#entries + 1] = { key = AD.CRIT_DMG, flat = critDmg }
        -- 觉醒2: 闪避值+15
        if awk[2] then
            entries[#entries + 1] = { key = AD.DODGE, flat = 15 }
        end
    -- 战士 闪电卖鸡 #21: 觉醒2 命中+30（觉醒6 护甲在 TalentManager 战斗内动态结算）
    elseif heroId == 21 then
        if awk[2] then
            entries[#entries + 1] = { key = AD.HIT_VALUE, flat = 30 }
        end
    -- 法师 小黑子 #22: 觉醒2 魔法伤害加成+10%
    elseif heroId == 22 then
        if awk[2] then
            entries[#entries + 1] = { key = AD.MAG_DMG_BONUS, flat = 10 }
        end
    -- 牧师 真布诗人 #23: 觉醒6 治疗暴击率+10%
    elseif heroId == 23 then
        if awk[6] then
            entries[#entries + 1] = { key = AD.HEAL_CRIT_RATE, flat = 10 }
        end
    end
    -- 其他英雄天赋为运行时效果（如燃烧DOT、冰冻、征服层数等），
    -- 需要在战斗逻辑中实现，不是简单的属性加成

    if #entries > 0 then
        attrs:addModifier("hero_talent_" .. heroId, entries)
    end
end

-- ======================== 辅助方法 ========================

--- 获取英雄配置
---@param heroId number
---@return table|nil
function HC.get(heroId)
    return HC.HEROES[heroId]
end

--- 通过名字查找英雄 ID
---@param name string
---@return number|nil
function HC.getIdByName(name)
    for id, hero in pairs(HC.HEROES) do
        if hero.name == name then
            return id
        end
    end
    return nil
end

--- 获取所有英雄 ID 列表（排序）
---@return number[]
function HC.getAllIds()
    local ids = {}
    for id in pairs(HC.HEROES) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

--- 获取指定品质的英雄 ID 列表
---@param quality number 1=R, 2=SR, 3=SSR, 4=UR
---@return number[]
function HC.getIdsByQuality(quality)
    local ids = {}
    for id, hero in pairs(HC.HEROES) do
        if hero.quality == quality then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

--- 获取指定职业的英雄 ID 列表
---@param classId string
---@return number[]
function HC.getIdsByClass(classId)
    local ids = {}
    for id, hero in pairs(HC.HEROES) do
        if hero.classId == classId then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

--- 获取品质颜色 RGB
---@param quality number
---@return number r, number g, number b
function HC.getQualityColorRGB(quality)
    local q = HC.QUALITY_INFO[quality]
    if not q or not q.color then
        return 255, 255, 255
    end
    local hex = q.color
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return r, g, b
end

-- ======================== 碎片配置 ========================

-- 碎片合成所需数量
HC.SHARD_SYNTHESIZE_COST = 10   -- 合成（解锁）一个未拥有英雄所需碎片
-- 重复英雄转化碎片数
HC.SHARD_DUPE_CONVERT    = 10   -- 抽到已拥有英雄时转化为碎片数

--- 获取英雄碎片显示名称
---@param heroId number
---@return string
function HC.getShardName(heroId)
    local hero = HC.HEROES[heroId]
    if hero then
        return hero.name .. "的碎片"
    end
    return "未知碎片"
end

return HC
