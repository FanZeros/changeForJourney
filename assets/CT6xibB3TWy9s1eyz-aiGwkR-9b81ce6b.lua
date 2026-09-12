-- ============================================================================
-- AdvancementConfig - 转职配置数据表
-- 数据来源: docs/配置文件/职业配置.txt
-- 包含: 12个一转职业 + 24个二转职业的属性加成、天赋定义
-- ============================================================================

local AD = require("systems.AttributeDef")
local CC = require("config.ClassConfig")

local AVC = {}

-- ======================== 转职等级常量 ========================

AVC.ADV_FIRST  = 1   -- 一转
AVC.ADV_SECOND = 2   -- 二转

-- ======================== 转职消耗 ========================

AVC.COST = {
    [1] = { level = 10, gold = 10000    },   -- 一转要求
    [2] = { level = 25, gold = 100000   },   -- 二转要求
}

-- ======================== 一转配置表 ========================
-- id           : 一转 branch ID (101~112)
-- name         : 一转职业名称
-- baseClass    : 前置基础职业 (CC.KNIGHT 等)
-- advLevel     : 转职等级 (1)
-- statBonus    : 属性加成 { { key=AD.xxx, flat=n }, ... }
-- talentName   : 天赋名称
-- talentDesc   : 天赋效果描述
-- talentId     : 天赋内部 ID (用于 TalentManager 路由)
-- combatPower  : 天赋提供的战斗力

AVC.BRANCHES = {
    -- ==================== 骑士一转 ====================
    [101] = {
        name = "圣骑士", baseClass = CC.KNIGHT, advLevel = 1,
        statBonus = {
            { key = AD.VIT, flat = 5 },
            { key = AD.SPI, flat = 5 },
        },
        talentName = "圣光术",
        talentDesc = "每10秒释放圣光术恢复自己10%生命",
        talentId = "adv_101_holy_light",
        combatPower = 15,
    },
    [102] = {
        name = "龙骑士", baseClass = CC.KNIGHT, advLevel = 1,
        statBonus = {
            { key = AD.VIT, flat = 5 },
            { key = AD.STR, flat = 5 },
        },
        talentName = "龙之血",
        talentDesc = "在战斗开始时和每10秒进行嘲讽，获得相当于模拟平A伤害×50的仇恨值，强制嘲讽3秒；仇恨值保持己方最高时每秒恢复2%已损失生命值",
        talentId = "adv_102_dragon_blood",
        combatPower = 15,
    },
    -- ==================== 战士一转 ====================
    [103] = {
        name = "狂战士", baseClass = CC.WARRIOR, advLevel = 1,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.VIT, flat = 5 },
        },
        talentName = "狂暴之血",
        talentDesc = "当前生命值每损失5%，物理攻击加成+2.5%",
        talentId = "adv_103_berserker_blood",
        combatPower = 15,
    },
    [104] = {
        name = "决斗者", baseClass = CC.WARRIOR, advLevel = 1,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.AGI, flat = 5 },
        },
        talentName = "战场决斗",
        talentDesc = "攻击速度+15%，每5次攻击只会攻击同一个敌人，不会受仇恨值影响，对锁定目标伤害加成+5%",
        talentId = "adv_104_duelist",
        combatPower = 15,
    },
    -- ==================== 法师一转 ====================
    [105] = {
        name = "咒术师", baseClass = CC.MAGE, advLevel = 1,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.SPI, flat = 5 },
        },
        talentName = "易伤诅咒",
        talentDesc = "每10秒对一个敌人施加持续8秒的[易伤]，使受到额外伤害+20%（乘法计算）",
        talentId = "adv_105_vulnerability_curse",
        combatPower = 15,
    },
    [106] = {
        name = "魔导师", baseClass = CC.MAGE, advLevel = 1,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.LUK, flat = 5 },
        },
        talentName = "奥术飞弹",
        talentDesc = "每次造成攻击伤害时，有35%概率对随机敌人发射奥术飞弹，造成魔法攻击力*100%的暗影伤害",
        talentId = "adv_106_arcane_missile",
        combatPower = 15,
    },
    -- ==================== 射手一转 ====================
    [107] = {
        name = "巡林客", baseClass = CC.RANGER, advLevel = 1,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.STR, flat = 5 },
        },
        talentName = "巡游射击",
        talentDesc = "每当怪物攻击其他角色后1秒，该角色有25%概率无视攻击进度条立即对该怪物进行攻击",
        talentId = "adv_107_patrol_shot",
        combatPower = 15,
    },
    [108] = {
        name = "弓箭手", baseClass = CC.RANGER, advLevel = 1,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.LUK, flat = 5 },
        },
        talentName = "阵前提速",
        talentDesc = "战斗开始时获得10层[提速]，每层提供8%攻击速度，每次攻击后减少1层",
        talentId = "adv_108_battle_haste",
        combatPower = 15,
    },
    -- ==================== 刺客一转 ====================
    [109] = {
        name = "暗杀者", baseClass = CC.ASSASSIN, advLevel = 1,
        statBonus = {
            { key = AD.LUK, flat = 5 },
            { key = AD.AGI, flat = 5 },
        },
        talentName = "隐匿",
        talentDesc = "每过去10秒后立即清空仇恨值，清空后获得5秒[暗影]状态：暴击率+15%，暴击伤害+30%",
        talentId = "adv_109_stealth",
        combatPower = 15,
    },
    [110] = {
        name = "影袭者", baseClass = CC.ASSASSIN, advLevel = 1,
        statBonus = {
            { key = AD.LUK, flat = 5 },
            { key = AD.STR, flat = 5 },
        },
        talentName = "影袭",
        talentDesc = "每当有敌人死亡时，立即填充100%当前攻击进度条，并使下一次攻击伤害加成+30%",
        talentId = "adv_110_shadow_strike",
        combatPower = 15,
    },
    -- ==================== 牧师一转 ====================
    [111] = {
        name = "大祭祀", baseClass = CC.PRIEST, advLevel = 1,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.LUK, flat = 5 },
        },
        talentName = "激励",
        talentDesc = "每次进行攻击治疗时，立即填充目标25%的攻击进度条，并使目标获得持续3秒的治疗加成+10%",
        talentId = "adv_111_inspire",
        combatPower = 15,
    },
    [112] = {
        name = "大主教", baseClass = CC.PRIEST, advLevel = 1,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.VIT, flat = 5 },
        },
        talentName = "团队治疗",
        talentDesc = "每次进行攻击治疗时，将治疗量的10%为整个团队所有冒险家进行治疗",
        talentId = "adv_112_group_heal",
        combatPower = 15,
    },

    -- ==================== 二转职业 ====================

    -- ===== 圣骑士 → 二转 =====
    [201] = {
        name = "圣堂骑士", baseClass = CC.KNIGHT, advLevel = 2,
        parentBranch = 101,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.VIT, flat = 5 },
            { key = AD.HEAL_BONUS, flat = 20 },
        },
        talentName = "进阶圣光术",
        talentDesc = "一转效果[圣光术]治疗的血量提升至三倍，在初次生命值低于50%/20%时立即释放一次[圣光术]",
        talentId = "adv_201_advanced_holy",
        combatPower = 20,
    },
    [202] = {
        name = "传颂骑士", baseClass = CC.KNIGHT, advLevel = 2,
        parentBranch = 101,
        statBonus = {
            { key = AD.VIT, flat = 5 },
            { key = AD.STR, flat = 5 },
            { key = AD.MAG_ARMOR, flat = 7 },
        },
        talentName = "传颂祝福",
        talentDesc = "在战斗中每累计损失10%生命值时，为所有冒险家增加7%伤害加成，最多增加98%",
        talentId = "adv_202_praise_blessing",
        combatPower = 20,
    },
    -- ===== 龙骑士 → 二转 =====
    [203] = {
        name = "十字之军", baseClass = CC.KNIGHT, advLevel = 2,
        parentBranch = 102,
        statBonus = {
            { key = AD.VIT, flat = 5 },
            { key = AD.STR, flat = 5 },
            { key = AD.PHYS_ARMOR, flat = 7 },
        },
        talentName = "十字盾守",
        talentDesc = "每当受到伤害时提升2点护甲，最多能叠加50次",
        talentId = "adv_203_cross_shield",
        combatPower = 20,
    },
    [204] = {
        name = "怒龙骑士", baseClass = CC.KNIGHT, advLevel = 2,
        parentBranch = 102,
        statBonus = {
            { key = AD.VIT, flat = 5 },
            { key = AD.AGI, flat = 5 },
            { key = AD.PHYS_CRIT_RATE, flat = 6.25 },
        },
        talentName = "怒龙反击",
        talentDesc = "每次受到攻击时，立即填充40%当前攻击进度条",
        talentId = "adv_204_dragon_counter",
        combatPower = 20,
    },
    -- ===== 狂战士 → 二转 =====
    [205] = {
        name = "疾风剑狂", baseClass = CC.WARRIOR, advLevel = 2,
        parentBranch = 103,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.AGI, flat = 5 },
            { key = AD.PHYS_CRIT_RATE, flat = 6.25 },
        },
        talentName = "狂风骤雨",
        talentDesc = "当前生命值每损失5%，攻击速度+3%，物理暴击率+1.5%",
        talentId = "adv_205_storm_fury",
        combatPower = 20,
    },
    [206] = {
        name = "嗜血狂徒", baseClass = CC.WARRIOR, advLevel = 2,
        parentBranch = 103,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.VIT, flat = 5 },
            { key = AD.CRIT_DMG, flat = 25 },
        },
        talentName = "嗜血狂怒",
        talentDesc = "物理攻击加成+35%，当生命值高于50%时每次攻击时减少3%当前生命值",
        talentId = "adv_206_bloodthirst",
        combatPower = 20,
    },
    -- ===== 决斗者 → 二转 =====
    [207] = {
        name = "武器大师", baseClass = CC.WARRIOR, advLevel = 2,
        parentBranch = 104,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.AGI, flat = 5 },
            { key = AD.PHYS_PEN, flat = 10 },
        },
        talentName = "武器精通",
        talentDesc = "无法再装备常规副手，但可在副手装备与主手不同类型的武器",
        talentId = "adv_207_weapon_master",
        combatPower = 20,
    },
    [208] = {
        name = "幻影剑士", baseClass = CC.WARRIOR, advLevel = 2,
        parentBranch = 104,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.PHYS_CRIT_DMG, flat = 33 },
        },
        talentName = "幻影剑斩",
        talentDesc = "攻击同一个敌人时，每次攻击获得1层[连击]，每层[连击]提供10%连击概率和2%连击增伤，最多叠加至10层；切换攻击目标时失去2层[连击]",
        talentId = "adv_208_phantom_slash",
        combatPower = 20,
    },
    -- ===== 咒术师 → 二转 =====
    [209] = {
        name = "瘟疫巫师", baseClass = CC.MAGE, advLevel = 2,
        parentBranch = 105,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.VIT, flat = 5 },
            { key = AD.MAG_PEN, flat = 10 },
        },
        talentName = "群体诅咒术",
        talentDesc = "每次诅咒时同时诅咒所有敌人，且[易伤诅咒]的效果提升至25%",
        talentId = "adv_209_plague_curse",
        combatPower = 20,
    },
    [210] = {
        name = "诅咒术士", baseClass = CC.MAGE, advLevel = 2,
        parentBranch = 105,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.SPI, flat = 5 },
            { key = AD.MAG_CRIT_RATE, flat = 6.25 },
        },
        talentName = "蚀骨诅咒",
        talentDesc = "[易伤诅咒]的持续时间延长至15秒。带有诅咒的敌人，每次受到伤害时，都会额外受到一次相当于该角色魔法攻击力*80%的暗影伤害（此效果每1秒最多触发1次）",
        talentId = "adv_210_corrosion_curse",
        combatPower = 20,
    },
    -- ===== 魔导师 → 二转 =====
    [211] = {
        name = "智慧学者", baseClass = CC.MAGE, advLevel = 2,
        parentBranch = 106,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.SPI, flat = 5 },
            { key = AD.MAG_CRIT_RATE, flat = 6.25 },
        },
        talentName = "奥术智慧",
        talentDesc = "[奥术飞弹]的触发概率提升至50%。飞弹现在会优先攻击生命值百分比最低的敌人，且对生命值低于40%的敌人造成的伤害提升100%。当目标生命值低于20%时，[奥术飞弹]必定触发。",
        talentId = "adv_211_arcane_wisdom",
        combatPower = 20,
    },
    [212] = {
        name = "奥能大师", baseClass = CC.MAGE, advLevel = 2,
        parentBranch = 106,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.MAG_PEN, flat = 10 },
        },
        talentName = "奥能充盈",
        talentDesc = "[奥术飞弹]的伤害提升至魔法攻击力*200%。每次触发飞弹时，有30%几率使本次飞弹爆炸，对目标及其相邻单位造成等量伤害。",
        talentId = "adv_212_arcane_surge",
        combatPower = 20,
    },
    -- ===== 巡林客 → 二转 =====
    [213] = {
        name = "风灵使者", baseClass = CC.RANGER, advLevel = 2,
        parentBranch = 107,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.STR, flat = 5 },
            { key = AD.ATK_SPEED, flat = 15 },
        },
        talentName = "风之气息",
        talentDesc = "[巡游射击]的触发概率提升至35%。每当触发此效果获得1层[风之气息]，自身攻击速度提升12%，持续5秒，此效果最多叠加3层。",
        talentId = "adv_213_wind_spirit",
        combatPower = 20,
    },
    [214] = {
        name = "林间猎手", baseClass = CC.RANGER, advLevel = 2,
        parentBranch = 107,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.CRIT_DMG, flat = 33 },
        },
        talentName = "林间之眼",
        talentDesc = "[巡游射击]必定造成暴击，每当进行普通攻击时获得1层[暴击提升]，暴击伤害+8%，持续10秒，此效果最多叠加20层",
        talentId = "adv_214_forest_eye",
        combatPower = 20,
    },
    -- ===== 弓箭手 → 二转 =====
    [215] = {
        name = "鹰眼箭神", baseClass = CC.RANGER, advLevel = 2,
        parentBranch = 108,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.PHYS_PEN, flat = 10 },
        },
        talentName = "鹰眼",
        talentDesc = "[阵前提速]获得的[提速]层数+5，每层[提速]额外提供6物理穿透",
        talentId = "adv_215_eagle_eye",
        combatPower = 20,
    },
    [216] = {
        name = "重弩炮手", baseClass = CC.RANGER, advLevel = 2,
        parentBranch = 108,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.AGI, flat = 5 },
            { key = AD.CRIT_DMG, flat = 25 },
        },
        talentName = "重火力",
        talentDesc = "攻击速度固定为100%；多余的攻击速度按照1:2转化为物理伤害加成",
        talentId = "adv_216_heavy_fire",
        combatPower = 20,
    },
    -- ===== 暗杀者 → 二转 =====
    [217] = {
        name = "瞬狱杀手", baseClass = CC.ASSASSIN, advLevel = 2,
        parentBranch = 109,
        statBonus = {
            { key = AD.LUK, flat = 5 },
            { key = AD.STR, flat = 5 },
            { key = AD.CRIT_DMG, flat = 33 },
        },
        talentName = "瞬杀",
        talentDesc = "保持5秒未受到攻击时，暴击概率+25%",
        talentId = "adv_217_instant_kill",
        combatPower = 20,
    },
    [218] = {
        name = "千面刺客", baseClass = CC.ASSASSIN, advLevel = 2,
        parentBranch = 109,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.PHYS_PEN, flat = 10 },
        },
        talentName = "千面",
        talentDesc = "保持5秒未受到攻击时，攻击速度+50%，伤害加成+10%",
        talentId = "adv_218_thousand_faces",
        combatPower = 20,
    },
    -- ===== 影袭者 → 二转 =====
    [219] = {
        name = "致命之刃", baseClass = CC.ASSASSIN, advLevel = 2,
        parentBranch = 110,
        statBonus = {
            { key = AD.LUK, flat = 5 },
            { key = AD.AGI, flat = 5 },
            { key = AD.CRIT_RATE, flat = 6.25 },
        },
        talentName = "致命",
        talentDesc = "攻击造成暴击时，其攻击进度条立即前进100%（每轮进度只能触发一次），暴击伤害+25%",
        talentId = "adv_219_lethal_blade",
        combatPower = 20,
    },
    [220] = {
        name = "双刃刺客", baseClass = CC.ASSASSIN, advLevel = 2,
        parentBranch = 110,
        statBonus = {
            { key = AD.LUK, flat = 5 },
            { key = AD.STR, flat = 5 },
            { key = AD.PHYS_PEN, flat = 10 },
        },
        talentName = "双刃精通",
        talentDesc = "无法再装备常规副手，但可在副手装备与主手相同类型的武器",
        talentId = "adv_220_dual_blade",
        combatPower = 20,
    },
    -- ===== 大祭祀 → 二转 =====
    [221] = {
        name = "祝祭神官", baseClass = CC.PRIEST, advLevel = 2,
        parentBranch = 111,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.INT, flat = 5 },
            { key = AD.HEAL_BONUS, flat = 20 },
        },
        talentName = "战争之祭",
        talentDesc = "[激励]的效果提升至40%。当目标因[激励]效果而立即进行攻击后，其此次攻击造成的伤害提升25%（乘法计算）",
        talentId = "adv_221_war_ritual",
        combatPower = 20,
    },
    [222] = {
        name = "黑衣祭祀", baseClass = CC.PRIEST, advLevel = 2,
        parentBranch = 111,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.HEAL_CRIT_RATE, flat = 6.25 },
        },
        talentName = "嗜血祭祀",
        talentDesc = "[激励]的效果提升至100%，但[激励]变为40%概率触发，因[激励]效果而立即攻击后，被[激励]的单位将恢复本次攻击造成的伤害值的生命值",
        talentId = "adv_222_blood_ritual",
        combatPower = 20,
    },
    -- ===== 大主教 → 二转 =====
    [223] = {
        name = "神之使徒", baseClass = CC.PRIEST, advLevel = 2,
        parentBranch = 112,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.VIT, flat = 5 },
            { key = AD.HEAL_BONUS, flat = 20 },
        },
        talentName = "神之赐福",
        talentDesc = "[团队治疗]治疗量提升至三倍，并且对当前生命值低于20%的冒险家必定造成治疗暴击",
        talentId = "adv_223_divine_blessing",
        combatPower = 20,
    },
    [224] = {
        name = "惩戒牧师", baseClass = CC.PRIEST, advLevel = 2,
        parentBranch = 112,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.INT, flat = 5 },
            { key = AD.MAG_PEN, flat = 10 },
        },
        talentName = "神圣惩戒",
        talentDesc = "每当进行任意治疗时，有40%概率对一个随机敌人发射惩戒飞弹，造成治疗量*400%的暗影伤害",
        talentId = "adv_224_divine_punishment",
        combatPower = 20,
    },
}

-- ======================== 一转分支映射 ========================
-- baseClass → { branchId1, branchId2 }

AVC.FIRST_BRANCHES = {
    [CC.KNIGHT]   = { 101, 102 },
    [CC.WARRIOR]  = { 103, 104 },
    [CC.MAGE]     = { 105, 106 },
    [CC.RANGER]   = { 107, 108 },
    [CC.ASSASSIN] = { 109, 110 },
    [CC.PRIEST]   = { 111, 112 },
}

-- ======================== 二转分支映射 ========================
-- firstBranchId → { branchId1, branchId2 }

AVC.SECOND_BRANCHES = {
    [101] = { 201, 202 },
    [102] = { 203, 204 },
    [103] = { 205, 206 },
    [104] = { 207, 208 },
    [105] = { 209, 210 },
    [106] = { 211, 212 },
    [107] = { 213, 214 },
    [108] = { 215, 216 },
    [109] = { 217, 218 },
    [110] = { 219, 220 },
    [111] = { 221, 222 },
    [112] = { 223, 224 },
}

-- ======================== 辅助方法 ========================

--- 获取转职分支配置
---@param branchId number 101~224
---@return table|nil
function AVC.get(branchId)
    return AVC.BRANCHES[branchId]
end

--- 获取英雄当前最高的转职分支 ID
--- 优先返回二转，否则一转，否则 nil
---@param advBranch table|nil 英雄存档中的 advBranch = { first=number?, second=number? }
---@return number|nil 最高转职分支ID
function AVC.getHighestBranch(advBranch)
    if not advBranch then return nil end
    return advBranch.second or advBranch.first
end

--- 获取英雄所有已完成的转职分支 ID 列表（用于属性叠加）
--- 返回 { firstBranchId?, secondBranchId? }
---@param advBranch table|nil
---@return number[] 已完成的转职分支 ID 列表
function AVC.getAllBranches(advBranch)
    if not advBranch then return {} end
    local list = {}
    if advBranch.first then
        list[#list + 1] = advBranch.first
    end
    if advBranch.second then
        list[#list + 1] = advBranch.second
    end
    return list
end

--- 应用转职属性加成到 UnitAttributes
---@param advBranch table|nil 英雄存档中的 advBranch
---@param attrs table UnitAttributes 实例
function AVC.applyStatBonuses(advBranch, attrs)
    local branches = AVC.getAllBranches(advBranch)
    for _, branchId in ipairs(branches) do
        local cfg = AVC.BRANCHES[branchId]
        if cfg and cfg.statBonus then
            attrs:addModifier("adv_stat_" .. branchId, cfg.statBonus)
        end
    end
end

--- 校验是否可以执行转职
---@param heroLevel number 英雄等级
---@param gold number 当前金币
---@param advLevel number 转职等级 (1=一转, 2=二转)
---@param classId string 英雄职业 ID
---@param branchId number 目标转职分支 ID
---@param advBranch table|nil 已有转职数据
---@return boolean ok, string? reason
function AVC.canAdvance(heroLevel, gold, advLevel, classId, branchId, advBranch)
    local req = AVC.COST[advLevel]
    if not req then
        return false, "无效的转职等级"
    end

    local branch = AVC.BRANCHES[branchId]
    if not branch then
        return false, "无效的转职分支"
    end

    -- 校验转职等级匹配
    if branch.advLevel ~= advLevel then
        return false, "转职等级不匹配"
    end

    -- 校验等级要求
    if heroLevel < req.level then
        return false, "英雄等级不足（需要 Lv" .. req.level .. "）"
    end

    -- 校验金币
    if gold < req.gold then
        return false, "金币不足（需要 " .. req.gold .. "）"
    end

    if advLevel == 1 then
        -- 一转：不能已有一转
        if advBranch and advBranch.first then
            return false, "已完成一转"
        end
        -- 校验职业匹配
        if branch.baseClass ~= classId then
            return false, "职业不匹配"
        end
    elseif advLevel == 2 then
        -- 二转：必须已有一转
        if not advBranch or not advBranch.first then
            return false, "未完成一转"
        end
        -- 不能已有二转
        if advBranch.second then
            return false, "已完成二转"
        end
        -- 校验前置一转匹配
        if branch.parentBranch ~= advBranch.first then
            return false, "前置一转不匹配"
        end
    end

    return true
end

--- 检查英雄是否拥有指定 talentId 的转职天赋
---@param advBranch table|nil 英雄存档中的 advBranch = { first=number?, second=number? }
---@param talentId string 天赋 ID（如 "adv_207_weapon_master"）
---@return boolean
function AVC.hasTalent(advBranch, talentId)
    if not advBranch then return false end
    local branches = AVC.getAllBranches(advBranch)
    for _, bId in ipairs(branches) do
        local cfg = AVC.BRANCHES[bId]
        if cfg and cfg.talentId == talentId then
            return true
        end
    end
    return false
end

--- 获取 207/220 天赋的副手武器模式
--- 返回 "different"(207武器精通)、"same"(220双刃精通)、nil(无此天赋)
---@param advBranch table|nil
---@return string|nil mode "different"|"same"|nil
function AVC.getDualWieldMode(advBranch)
    if AVC.hasTalent(advBranch, "adv_207_weapon_master") then
        return "different"
    end
    if AVC.hasTalent(advBranch, "adv_220_dual_blade") then
        return "same"
    end
    return nil
end

return AVC
