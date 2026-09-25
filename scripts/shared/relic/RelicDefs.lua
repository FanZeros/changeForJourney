-- ============================================================================
-- RelicDefs.lua — 遗物系统静态数据定义
-- 所有数据来源: docs/配置文件/亡誓公会-遗物.txt
-- ============================================================================

local RelicDefs = {}

-- ======================== 类型定义 ========================

-- 名称中英文映射
local TYPE_NAME_MAP = { "龟", "蛇", "鹿", "狼", "鹰" }

---@class RelicTypeDef
---@field name string
---@field key string
---@field iconSmall string 小图标资源名

---@type table<number, RelicTypeDef>
RelicDefs.TYPES = {
    -- 旧的 10×8 方块网格（cells / iconGrid）已随 RelicGrid 移除，现行是祭位模型
    [1] = { name = "岩龟", key = "GUI",  iconSmall = "ICON_YWX_GUI" },
    [2] = { name = "毒蛇", key = "SHE",  iconSmall = "ICON_YWX_SHE" },
    [3] = { name = "白鹿", key = "LU",   iconSmall = "ICON_YWX_LU" },
    [4] = { name = "灰狼", key = "LANG", iconSmall = "ICON_YWX_LANG" },
    [5] = { name = "猎鹰", key = "YING", iconSmall = "ICON_YWX_YING" },
}

-- ======================== 品质定义 ========================

---@class RelicQualityDef
---@field name string
---@field color string hex颜色
---@field strength number 强度系数
---@field reforgeCost number 洗练消耗（0=不可洗练）
---@field canReforge boolean 是否可洗练
---@field upgradeCost number 升级基础消耗

---@type table<number, RelicQualityDef>
RelicDefs.QUALITIES = {
    [1] = { name = "普通", color = "b5b5b5", strength = 12,   reforgeCost = 0,    canReforge = false, upgradeCost = 20 },
    [2] = { name = "优质", color = "a2ff94", strength = 18,   reforgeCost = 0,    canReforge = false, upgradeCost = 40 },
    [3] = { name = "稀有", color = "72f2f5", strength = 23.4, reforgeCost = 40,   canReforge = true,  upgradeCost = 80 },
    [4] = { name = "史诗", color = "ef79ff", strength = 29.3, reforgeCost = 200,  canReforge = true,  upgradeCost = 200 },
    [5] = { name = "传说", color = "ffed00", strength = 36.3, reforgeCost = 1200, canReforge = true,  upgradeCost = 480 },
    [6] = { name = "至臻", color = "ff0000", strength = 45.7, reforgeCost = 2400, canReforge = true,  upgradeCost = 960 },
}

RelicDefs.MAX_LEVEL = 5

-- ======================== 词缀定义 ========================

-- 类型名到 ID 映射（用于解析配置表的"龟,鹿,蛇,狼,鹰"字符串）
local TYPE_NAME_TO_ID = {
    ["龟"] = 1, ["蛇"] = 2, ["鹿"] = 3, ["狼"] = 4, ["鹰"] = 5,
}

---@class RelicAffixDef
---@field types number[] 适用遗物类型ID列表
---@field minLevel number 词条最低等级
---@field values (string|nil)[] 品质1~6的文本（nil表示该品质不可出现）
---@field weight number 权重

---@type table<number, RelicAffixDef>
RelicDefs.AFFIXES = {
    [1]  = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体生命加成+4%","全体生命加成+6%","全体生命加成+8%","全体生命加成+10%","全体生命加成+12%","全体生命加成+15%"} },
    [2]  = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体护甲加成+4%","全体护甲加成+6%","全体护甲加成+8%","全体护甲加成+9%","全体护甲加成+12%","全体护甲加成+15%"} },
    [3]  = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体能量护盾加成+4%","全体能量护盾加成+6%","全体能量护盾加成+8%","全体能量护盾加成+9%","全体能量护盾加成+12%","全体能量护盾加成+15%"} },
    [4]  = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体每秒回血+8","全体每秒回血+12","全体每秒回血+16","全体每秒回血+20","全体每秒回血+24","全体每秒回血+30"} },
    [5]  = { types = {1,2,3,4,5}, minLevel = 1, weight = 80,  values = {"封门人伤害加成+15%","封门人伤害加成+23%","封门人伤害加成+29%","封门人伤害加成+37%","封门人伤害加成+46%","封门人伤害加成+57%"} },
    [6]  = { types = {1,2,3,4,5}, minLevel = 1, weight = 80,  values = {"拾骸者伤害加成+15%","拾骸者伤害加成+23%","拾骸者伤害加成+29%","拾骸者伤害加成+37%","拾骸者伤害加成+46%","拾骸者伤害加成+57%"} },
    [7]  = { types = {1,2,3,4,5}, minLevel = 1, weight = 80,  values = {"裂隙使伤害加成+15%","裂隙使伤害加成+23%","裂隙使伤害加成+29%","裂隙使伤害加成+37%","裂隙使伤害加成+46%","裂隙使伤害加成+57%"} },
    [8]  = { types = {1,2,3,4,5}, minLevel = 1, weight = 80,  values = {"回响客伤害加成+15%","回响客伤害加成+23%","回响客伤害加成+29%","回响客伤害加成+37%","回响客伤害加成+46%","回响客伤害加成+57%"} },
    [9]  = { types = {1,2,3,4,5}, minLevel = 1, weight = 80,  values = {"换面人伤害加成+15%","换面人伤害加成+23%","换面人伤害加成+29%","换面人伤害加成+37%","换面人伤害加成+46%","换面人伤害加成+57%"} },
    [10] = { types = {1,2,3,4,5}, minLevel = 1, weight = 80,  values = {"司仪治疗增幅+24%","司仪治疗增幅+36%","司仪治疗增幅+47%","司仪治疗增幅+59%","司仪治疗增幅+73%","司仪治疗增幅+91%"} },
    [11] = { types = {2,5},       minLevel = 1, weight = 100, values = {"全体闪避值+2","全体闪避值+4","全体闪避值+5","全体闪避值+6","全体闪避值+7","全体闪避值+9"} },
    [12] = { types = {4,5},       minLevel = 1, weight = 100, values = {"全体攻击回血+5","全体攻击回血+8","全体攻击回血+10","全体攻击回血+13","全体攻击回血+16","全体攻击回血+20"} },
    [13] = { types = {1},         minLevel = 5, weight = 20,  values = {nil,nil,nil,nil,"物理格挡比例+6%","物理格挡比例+6%"} },
    [14] = { types = {1},         minLevel = 5, weight = 20,  values = {nil,nil,nil,nil,"魔法格挡比例+6%","魔法格挡比例+6%"} },
    [15] = { types = {1,3},       minLevel = 1, weight = 100, values = {"物理格挡概率+5%","物理格挡概率+7%","物理格挡概率+9%","物理格挡概率+12%","物理格挡概率+15%","物理格挡概率+18%"} },
    [16] = { types = {1,3},       minLevel = 1, weight = 100, values = {"魔法格挡概率+5%","魔法格挡概率+7%","魔法格挡概率+9%","魔法格挡概率+12%","魔法格挡概率+15%","魔法格挡概率+18%"} },
    [17] = { types = {1},         minLevel = 5, weight = 20,  values = {nil,nil,nil,nil,"物理格挡概率+7%且魔法格挡概率+7%","物理格挡概率+9%且魔法格挡概率+9%"} },
    [18] = { types = {1,3},       minLevel = 3, weight = 100, values = {nil,nil,"全体生命加成+12%","全体生命加成+15%","全体生命加成+18%","全体生命加成+23%"} },
    [19] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体物理攻击加成+4%","全体物理攻击加成+6%","全体物理攻击加成+8%","全体物理攻击加成+10%","全体物理攻击加成+13%","全体物理攻击加成+15%"} },
    [20] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体魔法攻击加成+4%","全体魔法攻击加成+6%","全体魔法攻击加成+8%","全体魔法攻击加成+10%","全体魔法攻击加成+13%","全体魔法攻击加成+15%"} },
    [21] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体攻击速度+6%","全体攻击速度+9%","全体攻击速度+12%","全体攻击速度+15%","全体攻击速度+18%","全体攻击速度+23%"} },
    [22] = { types = {1,2,3,4,5}, minLevel = 5, weight = 10,  values = {nil,nil,nil,nil,"全体暴击率+7%","全体暴击率+9%"} },
    [23] = { types = {1,2,3,4,5}, minLevel = 2, weight = 100, values = {nil,"全体暴击伤害+18%","全体暴击伤害+23%","全体暴击伤害+29%","全体暴击伤害+37%","全体暴击伤害+46%"} },
    [24] = { types = {1,2,3,4,5}, minLevel = 3, weight = 10,  values = {nil,nil,"全体物理暴击率+6%","全体物理暴击率+7%","全体物理暴击率+9%","全体物理暴击率+11%"} },
    [25] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体物理暴击伤害+16%","全体物理暴击伤害+24%","全体物理暴击伤害+31%","全体物理暴击伤害+39%","全体物理暴击伤害+49%","全体物理暴击伤害+61%"} },
    [26] = { types = {1,2,3,4,5}, minLevel = 3, weight = 10,  values = {nil,nil,"全体魔法暴击率+6%","全体魔法暴击率+7%","全体魔法暴击率+9%","全体魔法暴击率+11%"} },
    [27] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体魔法暴击伤害+16%","全体魔法暴击伤害+24%","全体魔法暴击伤害+31%","全体魔法暴击伤害+39%","全体魔法暴击伤害+49%","全体魔法暴击伤害+61%"} },
    [28] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体物理穿透+5","全体物理穿透+7","全体物理穿透+9","全体物理穿透+12","全体物理穿透+15","全体物理穿透+18"} },
    [29] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体魔法穿透+5","全体魔法穿透+7","全体魔法穿透+9","全体魔法穿透+12","全体魔法穿透+15","全体魔法穿透+18"} },
    [30] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体伤害加成+6%","全体伤害加成+9%","全体伤害加成+12%","全体伤害加成+15%","全体伤害加成+18%","全体伤害加成+23%"} },
    [31] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体物理伤害加成+8%","全体物理伤害加成+12%","全体物理伤害加成+16%","全体物理伤害加成+20%","全体物理伤害加成+24%","全体物理伤害加成+30%"} },
    [32] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体魔法伤害加成+8%","全体魔法伤害加成+12%","全体魔法伤害加成+16%","全体魔法伤害加成+20%","全体魔法伤害加成+24%","全体魔法伤害加成+30%"} },
    [33] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体连击概率+8%","全体连击概率+12%","全体连击概率+16%","全体连击概率+20%","全体连击概率+24%","全体连击概率+30%"} },
    [34] = { types = {2,5},       minLevel = 1, weight = 100, values = {"全体最大伤害加成+20%","全体最大伤害加成+30%","全体最大伤害加成+39%","全体最大伤害加成+49%","全体最大伤害加成+61%","全体最大伤害加成+76%"} },
    [35] = { types = {2,5},       minLevel = 1, weight = 100, values = {"全体最小伤害加成+24%","全体最小伤害加成+36%","全体最小伤害加成+47%","全体最小伤害加成+59%","全体最小伤害加成+73%","全体最小伤害加成+91%"} },
    [36] = { types = {1,2,3,4,5}, minLevel = 1, weight = 100, values = {"全体命中值+3","全体命中值+5","全体命中值+6","全体命中值+7","全体命中值+9","全体命中值+11"} },
    [37] = { types = {1,2,3,4,5}, minLevel = 4, weight = 20,  values = {nil,nil,nil,"全体物理攻击加成+10%","全体物理攻击加成+12%","全体物理攻击加成+15%"} },
    [38] = { types = {1,2,3,4,5}, minLevel = 4, weight = 20,  values = {nil,nil,nil,"全体魔法攻击加成+10%","全体魔法攻击加成+12%","全体魔法攻击加成+15%"} },
    [39] = { types = {2,5},       minLevel = 3, weight = 50,  values = {nil,nil,"全体连击增伤+8%","全体连击增伤+10%","全体连击增伤+12%","全体连击增伤+15%"} },
    [40] = { types = {1,2,3,4,5}, minLevel = 2, weight = 80,  values = {nil,"全体力量+2","全体力量+3","全体力量+4","全体力量+5","全体力量+6"} },
    [41] = { types = {1,2,3,4,5}, minLevel = 2, weight = 80,  values = {nil,"全体敏捷+2","全体敏捷+3","全体敏捷+4","全体敏捷+5","全体敏捷+6"} },
    [42] = { types = {1,2,3,4,5}, minLevel = 2, weight = 80,  values = {nil,"全体智慧+2","全体智慧+3","全体智慧+4","全体智慧+5","全体智慧+6"} },
    [43] = { types = {1,2,3,4,5}, minLevel = 2, weight = 80,  values = {nil,"全体体质+2","全体体质+3","全体体质+4","全体体质+5","全体体质+6"} },
    [44] = { types = {1,2,3,4,5}, minLevel = 2, weight = 80,  values = {nil,"全体运气+2","全体运气+3","全体运气+4","全体运气+5","全体运气+6"} },
    [45] = { types = {1,2,3,4,5}, minLevel = 2, weight = 80,  values = {nil,"全体精神+2","全体精神+3","全体精神+4","全体精神+5","全体精神+6"} },
    [46] = { types = {1,4},       minLevel = 2, weight = 60,  values = {nil,"全体对血量高于70%增伤+13%","全体对血量高于70%增伤+17%","全体对血量高于70%增伤+21%","全体对血量高于70%增伤+26%","全体对血量高于70%增伤+33%"} },
    [47] = { types = {2,5},       minLevel = 2, weight = 60,  values = {nil,"全体对血量低于30%增伤+18%","全体对血量低于30%增伤+23%","全体对血量低于30%增伤+29%","全体对血量低于30%增伤+37%","全体对血量低于30%增伤+46%"} },
    [48] = { types = {1,3},       minLevel = 2, weight = 60,  values = {nil,"满血时，伤害增加+15%","满血时，伤害增加+20%","满血时，伤害增加+24%","满血时，伤害增加+31%","满血时，伤害增加+38%"} },
    [49] = { types = {3},         minLevel = 2, weight = 80,  values = {nil,"全体治疗量+7","全体治疗量+9","全体治疗量+12","全体治疗量+15","全体治疗量+18"} },
    [50] = { types = {3},         minLevel = 2, weight = 80,  values = {nil,"全体治疗加成+14%","全体治疗加成+19%","全体治疗加成+23%","全体治疗加成+29%","全体治疗加成+37%"} },
    [51] = { types = {3},         minLevel = 2, weight = 20,  values = {nil,"全体治疗暴击率+5%","全体治疗暴击率+6%","全体治疗暴击率+7%","全体治疗暴击率+9%","全体治疗暴击率+11%"} },
    [52] = { types = {3},         minLevel = 2, weight = 60,  values = {nil,"全体治疗暴击加成+24%","全体治疗暴击加成+31%","全体治疗暴击加成+39%","全体治疗暴击加成+49%","全体治疗暴击加成+61%"} },
    [53] = { types = {1},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[封门人]每次攻击获得的仇恨值+51%","[封门人]每次攻击获得的仇恨值+63%","[封门人]每次攻击获得的仇恨值+78%"} },
    [54] = { types = {1},         minLevel = 3, weight = 40,  values = {nil,nil,"[封门人]生命加成+29%","[封门人]生命加成+37%","[封门人]生命加成+46%","[封门人]生命加成+57%"} },
    [55] = { types = {1},         minLevel = 3, weight = 40,  values = {nil,nil,"[封门人]生命加成+20%","[封门人]生命加成+24%","[封门人]生命加成+30%","[封门人]生命加成+38%"} },
    [56] = { types = {1},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[封门人]生命低于25%时，物理格挡与魔法格挡概率+21%","[封门人]生命低于25%时，物理格挡与魔法格挡概率+24%","[封门人]生命低于25%时，物理格挡与魔法格挡概率+30%"} },
    [57] = { types = {1},         minLevel = 3, weight = 20,  values = {nil,nil,"[封门人]护甲加成+9%","[封门人]护甲加成+12%","[封门人]护甲加成+15%","[封门人]护甲加成+19%"} },
    [58] = { types = {1},         minLevel = 3, weight = 60,  values = {nil,nil,"[拾骸者]生命加成+29%","[拾骸者]生命加成+37%","[拾骸者]生命加成+46%","[拾骸者]生命加成+57%"} },
    [59] = { types = {1},         minLevel = 3, weight = 60,  values = {nil,nil,"[拾骸者]生命加成+20%","[拾骸者]生命加成+24%","[拾骸者]生命加成+30%","[拾骸者]生命加成+38%"} },
    [60] = { types = {1},         minLevel = 4, weight = 30,  values = {nil,nil,nil,"[拾骸者]每次攻击获得的仇恨值+51%","[拾骸者]每次攻击获得的仇恨值+63%","[拾骸者]每次攻击获得的仇恨值+78%"} },
    [61] = { types = {1},         minLevel = 4, weight = 30,  values = {nil,nil,nil,"[封门人]与[拾骸者]在战斗开始时仇恨值+501","[封门人]与[拾骸者]在战斗开始时仇恨值+624","[封门人]与[拾骸者]在战斗开始时仇恨值+780"} },
    [62] = { types = {1},         minLevel = 4, weight = 30,  values = {nil,nil,nil,"[拾骸者]生命低于25%时，护甲加成+35%","[拾骸者]生命低于25%时，护甲加成+46%","[拾骸者]生命低于25%时，护甲加成+56%"} },
    [63] = { types = {2},         minLevel = 3, weight = 50,  values = {nil,nil,"[换面人]连击概率+39%","[换面人]连击概率+49%","[换面人]连击概率+61%","[换面人]连击概率+76%"} },
    [64] = { types = {2},         minLevel = 3, weight = 50,  values = {nil,nil,"[换面人]攻击速度+29%","[换面人]攻击速度+37%","[换面人]攻击速度+46%","[换面人]攻击速度+57%"} },
    [65] = { types = {2},         minLevel = 3, weight = 50,  values = {nil,nil,"[裂隙使]魔法暴击伤害+78%","[裂隙使]魔法暴击伤害+98%","[裂隙使]魔法暴击伤害+122%","[裂隙使]魔法暴击伤害+152%"} },
    [66] = { types = {2},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[换面人与裂隙使]攻击与造成伤害有21%概率不获得仇恨","[换面人与裂隙使]攻击与造成伤害有24%概率不获得仇恨","[换面人与裂隙使]攻击与造成伤害有30%概率不获得仇恨"} },
    [67] = { types = {2},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[换面人]战斗开始时免疫伤害次数+1","[换面人]战斗开始时免疫伤害次数+2","[换面人]战斗开始时免疫伤害次数+3"} },
    [68] = { types = {2},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"全体生命值低于50%时闪避加成+21%","全体生命值低于50%时闪避加成+24%","全体生命值低于50%时闪避加成+30%"} },
    [69] = { types = {2},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[换面人与裂隙使]闪避值+15","[换面人与裂隙使]闪避值+18","[换面人与裂隙使]闪避值+23"} },
    [70] = { types = {2},         minLevel = 5, weight = 30,  values = {nil,nil,nil,nil,"远征队员触发闪避时仇恨值-30","远征队员触发闪避时仇恨值-39"} },
    [71] = { types = {2},         minLevel = 5, weight = 30,  values = {nil,nil,nil,nil,"全体伤害最小伤害-21%，最大伤害+39%","全体伤害最小伤害-24%，最大伤害+51%"} },
    [72] = { types = {3},         minLevel = 3, weight = 50,  values = {nil,nil,"[裂隙使]魔法伤害加成+39%","[裂隙使]魔法伤害加成+49%","[裂隙使]魔法伤害加成+61%","[裂隙使]魔法伤害加成+76%"} },
    [73] = { types = {3},         minLevel = 3, weight = 50,  values = {nil,nil,"[裂隙使]魔法穿透+23","[裂隙使]魔法穿透+29","[裂隙使]魔法穿透+37","[裂隙使]魔法穿透+46"} },
    [74] = { types = {3},         minLevel = 3, weight = 50,  values = {nil,nil,"[裂隙使]暴击率+12%","[裂隙使]暴击率+15%","[裂隙使]暴击率+18%","[裂隙使]暴击率+23%"} },
    [75] = { types = {3},         minLevel = 5, weight = 30,  values = {nil,nil,nil,nil,"[裂隙使]造成的攻击伤害将在80%-140%之间浮动","[裂隙使]造成的攻击伤害将在80%-150%之间浮动"} },
    [76] = { types = {3},         minLevel = 3, weight = 50,  values = {nil,nil,"[封门人]伤害加成+29%","[封门人]伤害加成+37%","[封门人]伤害加成+46%","[封门人]伤害加成+57%"} },
    [77] = { types = {3},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[封门人]伤害加成-5%，但生命加成+24%","[封门人]伤害加成-5%，但生命加成+30%","[封门人]伤害加成-5%，但生命加成+39%"} },
    [78] = { types = {3},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[封门人]受到治疗时仇恨值+21","[封门人]受到治疗时仇恨值+24","[封门人]受到治疗时仇恨值+30"} },
    [79] = { types = {3},         minLevel = 5, weight = 30,  values = {nil,nil,nil,nil,"[司仪]对非[封门人]职业进行治疗时，使其仇恨值-15","[司仪]对非[封门人]职业进行治疗时，使其仇恨值-18"} },
    [80] = { types = {4},         minLevel = 3, weight = 50,  values = {nil,nil,"[拾骸者]物理伤害加成+39%","[拾骸者]物理伤害加成+49%","[拾骸者]物理伤害加成+61%","[拾骸者]物理伤害加成+76%"} },
    [81] = { types = {4},         minLevel = 3, weight = 50,  values = {nil,nil,"[拾骸者]物理攻击加成+19%","[拾骸者]物理攻击加成+24%","[拾骸者]物理攻击加成+31%","[拾骸者]物理攻击加成+38%"} },
    [82] = { types = {4},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[拾骸者与回响客]攻击回血+33","[拾骸者与回响客]攻击回血+41","[拾骸者与回响客]攻击回血+51"} },
    [83] = { types = {4},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[拾骸者]物理穿透+29","[拾骸者]物理穿透+37","[拾骸者]物理穿透+46"} },
    [84] = { types = {4},         minLevel = 3, weight = 50,  values = {nil,nil,"[回响客]攻击速度+29%","[回响客]攻击速度+37%","[回响客]攻击速度+46%","[回响客]攻击速度+57%"} },
    [85] = { types = {4},         minLevel = 3, weight = 50,  values = {nil,nil,"[回响客]连击概率+39%","[回响客]连击概率+49%","[回响客]连击概率+61%","[回响客]连击概率+76%"} },
    [86] = { types = {4},         minLevel = 3, weight = 50,  values = {nil,nil,"[回响客]命中值+15","[回响客]命中值+18","[回响客]命中值+23","[回响客]命中值+29"} },
    [87] = { types = {4},         minLevel = 5, weight = 30,  values = {nil,nil,nil,nil,"[回响客]战斗开始时初次攻击伤害加成+51%","[回响客]战斗开始时初次攻击伤害加成+63%"} },
    [88] = { types = {4},         minLevel = 5, weight = 30,  values = {nil,nil,nil,nil,"[回响客]的前2次攻击无法获得仇恨值","[回响客]的前3次攻击无法获得仇恨值"} },
    [89] = { types = {5},         minLevel = 5, weight = 30,  values = {nil,nil,nil,nil,"[换面人]进行攻击时，有50%概率终结血量低于15%的敌人","[换面人]进行攻击时，有50%概率终结血量低于21%的敌人"} },
    [90] = { types = {5},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[换面人]连击增伤+24%","[换面人]连击增伤+31%","[换面人]连击增伤+38%"} },
    [91] = { types = {5},         minLevel = 4, weight = 40,  values = {nil,nil,nil,"[回响客]连击增伤+24%","[回响客]连击增伤+31%","[回响客]连击增伤+38%"} },
    [92] = { types = {5},         minLevel = 5, weight = 30,  values = {nil,nil,nil,nil,"[换面人与回响客]在生命值首次低于30%时，在3秒内闪避值+210","[换面人与回响客]在生命值首次低于30%时，在3秒内闪避值+255"} },
    [93] = { types = {5},         minLevel = 3, weight = 50,  values = {nil,nil,"[换面人]暴击伤害+59%","[换面人]暴击伤害+73%","[换面人]暴击伤害+91%","[换面人]暴击伤害+114%"} },
    [94] = { types = {5},         minLevel = 5, weight = 30,  values = {nil,nil,nil,nil,"[换面人与回响客]暴击概率+18%","[换面人与回响客]暴击概率+23%"} },
    [95] = { types = {5},         minLevel = 3, weight = 50,  values = {nil,nil,"[回响客]暴击伤害+59%","[回响客]暴击伤害+73%","[回响客]暴击伤害+91%","[回响客]暴击伤害+114%"} },
}

-- ======================== 辅助查询 ========================

--- 判断某词缀是否适用于指定遗物类型
---@param affixId number
---@param relicType number
---@return boolean
function RelicDefs.isAffixForType(affixId, relicType)
    local affix = RelicDefs.AFFIXES[affixId]
    if not affix then return false end
    for _, t in ipairs(affix.types) do
        if t == relicType then return true end
    end
    return false
end

--- 获取词缀在指定品质的文本（nil表示该品质不可出现）
---@param affixId number
---@param quality number 1~6
---@return string|nil
function RelicDefs.getAffixText(affixId, quality)
    local affix = RelicDefs.AFFIXES[affixId]
    if not affix then return nil end
    return affix.values[quality]
end

--- 获取某品质的洗练费用（0或nil表示不可洗练）
---@param quality number
---@return number
function RelicDefs.getReforgeCost(quality)
    local q = RelicDefs.QUALITIES[quality]
    if not q or not q.canReforge then return 0 end
    return q.reforgeCost
end

--- 升级到下一级的奥术粉尘消耗
---@param quality number
---@param level number 当前等级
---@return number
function RelicDefs.getUpgradeCost(quality, level)
    local q = RelicDefs.QUALITIES[quality]
    if not q then return 0 end
    level = math.max(1, math.floor(tonumber(level) or 1))
    if level >= RelicDefs.MAX_LEVEL then return 0 end
    local base = q.upgradeCost or 40
    return math.floor(base * (1.0 + (level - 1) * 0.55))
end

return RelicDefs
