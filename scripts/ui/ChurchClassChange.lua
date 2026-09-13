-- ChurchClassChange.lua
-- 教堂转职子模块：转职树、确认弹窗、分支图标点击
-- 从 ChurchPage.lua 拆分而来

---@diagnostic disable: undefined-global

local GameConfig     = require("config.GameConfig")
local DrawUtil       = require("core.DrawUtil")
local HC             = require("config.HeroConfig")
local CC             = require("config.ClassConfig")
local CharacterPanel = require("ui.CharacterPanel")
local GameState      = require("core.GameState")
local BF             = require("systems.ButtonFeedback")
local DarkIcon       = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格
local NumberUtil     = require("core.NumberUtil")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

local M = {}

--- 转职门槛等级：与战斗/角色页一致，使用有效等级（含冒险等级、共鸣等级）
---@param heroId number
---@return number
local function getAdvanceHeroLevel(heroId)
    if CharacterPanel.getEffectiveLevel then
        return CharacterPanel.getEffectiveLevel(heroId)
    end
    local ownData = CharacterPanel.getOwnedHero(heroId)
    return ownData and ownData.level or 1
end

-- ======================== 转职界面布局常量 ========================

-- 职业背景图
local CLASS_BG_W, CLASS_BG_H   = 1080, 1700
local CLASS_BG_CX              = 540
local CLASS_BG_CY              = DESIGN_H - CLASS_BG_H * 0.5

-- 标题背景
local TITLE_BG_CX, TITLE_BG_CY = 540, 1092
local TITLE_BG_W, TITLE_BG_H   = 660, 60

-- 标题文字 "转职"
local TITLE_TEXT_CX, TITLE_TEXT_CY = 540, 1092
local TITLE_FONT_SIZE              = 40

-- 重置按钮（位于"转职"标题上方）
local BTN_RESET_CX   = 540
local BTN_RESET_CY   = 1000   -- 标题顶边(1062) - 间距12 - 半高50 = 1000
local BTN_RESET_W    = 410
local BTN_RESET_H    = 100
local BTN_RESET_FONT = 40

-- "初始职业" 文本
local INIT_LABEL_CX, INIT_LABEL_CY = 542, 1178
local INIT_LABEL_FONT               = 40

-- 一转分叉线
local BRANCH_LINE_CX, BRANCH_LINE_CY = 540, 1464
local BRANCH_LINE_W, BRANCH_LINE_H   = 498, 312

-- 初始职业图标 & 名称
local INIT_ICON_CX, INIT_ICON_CY = 540, 1295
local INIT_ICON_W, INIT_ICON_H   = 166, 166
local INIT_NAME_CX, INIT_NAME_CY = 540, 1364
local INIT_NAME_FONT              = 40

-- 一转分支1 图标 & 名称
local BR1_ICON_CX, BR1_ICON_CY = 307, 1616
local BR1_ICON_W, BR1_ICON_H   = 166, 166
local BR1_NAME_CX, BR1_NAME_CY = 307, 1693
local BR1_NAME_FONT             = 40

-- 一转分支2 图标 & 名称
local BR2_ICON_CX, BR2_ICON_CY = 776, 1616
local BR2_ICON_W, BR2_ICON_H   = 166, 166
local BR2_NAME_CX, BR2_NAME_CY = 775, 1693
local BR2_NAME_FONT             = 40

-- 二转 & 锁定遮罩布局
local ADV2 = {
    -- 二转分叉线
    line1CX = 307, line1CY = 1793,
    line2CX = 775, line2CY = 1793,
    lineW   = 261, lineH   = 277,
    -- 二转分支位置（4个）
    iconW = 166, iconH = 166, nameFontSize = 40,
    pos = {
        { iconCX = 189, iconCY = 1941, nameCX = 189, nameCY = 2017 },
        { iconCX = 424, iconCY = 1941, nameCX = 424, nameCY = 2017 },
        { iconCX = 658, iconCY = 1941, nameCX = 658, nameCY = 2017 },
        { iconCX = 893, iconCY = 1941, nameCX = 893, nameCY = 2017 },
    },
    -- 转职等级要求
    firstLevel  = 10,
    secondLevel = 25,
    lockFont    = 40,
    -- 一转锁定遮罩
    lock1 = { bgCX = 540, bgCY = 1626, bgW = 1080, bgH = 320,
              titleCX = 543, titleCY = 1593, descCX = 542, descCY = 1642 },
    -- 二转锁定遮罩
    lock2 = { bgCX = 540, bgCY = 1947, bgW = 1080, bgH = 320,
              titleCX = 543, titleCY = 1914, descCX = 542, descCY = 1963 },
}

-- ======================== 转职数据表 ========================

--- classId → 编号（用于背景图文件名 UI_ZZBJ_X.png）
local CLASS_NUM = {
    [CC.KNIGHT]   = 1,
    [CC.WARRIOR]  = 2,
    [CC.MAGE]     = 3,
    [CC.RANGER]   = 4,
    [CC.ASSASSIN] = 5,
    [CC.PRIEST]   = 6,
}

--- classId → 职业颜色
local CLASS_COLORS = {
    [CC.KNIGHT]   = { r = 0xfd, g = 0x23, b = 0x23 },
    [CC.WARRIOR]  = { r = 0xfd, g = 0xb8, b = 0x23 },
    [CC.MAGE]     = { r = 0x23, g = 0xe1, b = 0xfd },
    [CC.RANGER]   = { r = 0x23, g = 0xfd, b = 0x37 },
    [CC.ASSASSIN] = { r = 0xd6, g = 0x5a, b = 0xff },
    [CC.PRIEST]   = { r = 0xfc, g = 0xff, b = 0x00 },
}

--- classId → 基础职业中文名
local CLASS_DISPLAY_NAMES = {
    [CC.KNIGHT]   = "骑士",
    [CC.WARRIOR]  = "战士",
    [CC.MAGE]     = "法师",
    [CC.RANGER]   = "射手",
    [CC.ASSASSIN] = "刺客",
    [CC.PRIEST]   = "牧师",
}

--- classId → 一转分支 { { id, name }, { id, name } }
local FIRST_ADV_BRANCHES = {
    [CC.KNIGHT]   = { { id = 101, name = "圣骑士" },  { id = 102, name = "龙骑士" } },
    [CC.WARRIOR]  = { { id = 103, name = "狂战士" },  { id = 104, name = "决斗者" } },
    [CC.MAGE]     = { { id = 105, name = "咒术师" },  { id = 106, name = "魔导师" } },
    [CC.RANGER]   = { { id = 107, name = "巡林客" },  { id = 108, name = "弓箭手" } },
    [CC.ASSASSIN] = { { id = 109, name = "暗杀者" },  { id = 110, name = "影袭者" } },
    [CC.PRIEST]   = { { id = 111, name = "大祭祀" },  { id = 112, name = "大主教" } },
}

--- 一转分支 id → 二转分支 { { id, name }, { id, name } }
local SECOND_ADV_BRANCHES = {
    [101] = { { id = 201, name = "圣堂骑士" }, { id = 202, name = "传颂骑士" } },
    [102] = { { id = 203, name = "十字之军" }, { id = 204, name = "怒龙骑士" } },
    [103] = { { id = 205, name = "疾风剑狂" }, { id = 206, name = "嗜血狂徒" } },
    [104] = { { id = 207, name = "武器大师" }, { id = 208, name = "幻影剑士" } },
    [105] = { { id = 209, name = "瘟疫巫师" }, { id = 210, name = "诅咒术士" } },
    [106] = { { id = 211, name = "智慧学者" }, { id = 212, name = "奥能大师" } },
    [107] = { { id = 213, name = "风灵使者" }, { id = 214, name = "林间猎手" } },
    [108] = { { id = 215, name = "鹰眼箭神" }, { id = 216, name = "重弩炮手" } },
    [109] = { { id = 217, name = "瞬狱杀手" }, { id = 218, name = "千面刺客" } },
    [110] = { { id = 219, name = "致命之刃" }, { id = 220, name = "双刃刺客" } },
    [111] = { { id = 221, name = "祝祭神官" }, { id = 222, name = "黑衣祭祀" } },
    [112] = { { id = 223, name = "神之使徒" }, { id = 224, name = "惩戒牧师" } },
}

--- 分支 id → 转职属性加成 { { name, value }, ... }
local ADV_BRANCH_ATTRS = {
    -- ===== 基础职业 =====
    [1] = { { name = "体质", value = "+5" } },
    [2] = { { name = "力量", value = "+5" } },
    [3] = { { name = "智慧", value = "+5" } },
    [4] = { { name = "敏捷", value = "+5" } },
    [5] = { { name = "运气", value = "+5" } },
    [6] = { { name = "精神", value = "+5" } },
    -- ===== 一转 =====
    [101] = { { name = "体质", value = "+5" }, { name = "精神", value = "+5" } },
    [102] = { { name = "体质", value = "+5" }, { name = "力量", value = "+5" } },
    [103] = { { name = "力量", value = "+5" }, { name = "体质", value = "+5" } },
    [104] = { { name = "力量", value = "+5" }, { name = "智慧", value = "+5" } },
    [105] = { { name = "智慧", value = "+5" }, { name = "精神", value = "+5" } },
    [106] = { { name = "智慧", value = "+5" }, { name = "运气", value = "+5" } },
    [107] = { { name = "敏捷", value = "+5" }, { name = "力量", value = "+5" } },
    [108] = { { name = "敏捷", value = "+5" }, { name = "运气", value = "+5" } },
    [109] = { { name = "运气", value = "+5" }, { name = "敏捷", value = "+5" } },
    [110] = { { name = "运气", value = "+5" }, { name = "力量", value = "+5" } },
    [111] = { { name = "精神", value = "+5" }, { name = "运气", value = "+5" } },
    [112] = { { name = "精神", value = "+5" }, { name = "体质", value = "+5" } },
    -- ===== 二转 =====
    [201] = { { name = "精神", value = "+5" }, { name = "体质", value = "+5" }, { name = "治疗加成", value = "+20%" } },
    [202] = { { name = "体质", value = "+5" }, { name = "力量", value = "+5" }, { name = "能量护盾", value = "+49" } },
    [203] = { { name = "体质", value = "+5" }, { name = "力量", value = "+5" }, { name = "护甲", value = "+7" } },
    [204] = { { name = "体质", value = "+5" }, { name = "敏捷", value = "+5" }, { name = "物理暴击率", value = "+6.25%" } },
    [205] = { { name = "力量", value = "+5" }, { name = "敏捷", value = "+5" }, { name = "物理暴击率", value = "+6.25%" } },
    [206] = { { name = "力量", value = "+5" }, { name = "体质", value = "+5" }, { name = "暴击伤害", value = "+25%" } },
    [207] = { { name = "力量", value = "+5" }, { name = "敏捷", value = "+5" }, { name = "物理穿透", value = "+10" } },
    [208] = { { name = "力量", value = "+5" }, { name = "运气", value = "+5" }, { name = "物理暴击伤害", value = "+33%" } },
    [209] = { { name = "智慧", value = "+5" }, { name = "体质", value = "+5" }, { name = "魔法穿透", value = "+10" } },
    [210] = { { name = "智慧", value = "+5" }, { name = "精神", value = "+5" }, { name = "魔法暴击率", value = "+6.25%" } },
    [211] = { { name = "智慧", value = "+5" }, { name = "精神", value = "+5" }, { name = "魔法暴击率", value = "+6.25%" } },
    [212] = { { name = "智慧", value = "+5" }, { name = "运气", value = "+5" }, { name = "魔法穿透", value = "+10" } },
    [213] = { { name = "敏捷", value = "+5" }, { name = "力量", value = "+5" }, { name = "攻击速度", value = "+15%" } },
    [214] = { { name = "敏捷", value = "+5" }, { name = "运气", value = "+5" }, { name = "暴击伤害", value = "+33%" } },
    [215] = { { name = "敏捷", value = "+5" }, { name = "运气", value = "+5" }, { name = "物理穿透", value = "+10" } },
    [216] = { { name = "力量", value = "+5" }, { name = "敏捷", value = "+5" }, { name = "暴击伤害", value = "+25%" } },
    [217] = { { name = "运气", value = "+5" }, { name = "力量", value = "+5" }, { name = "暴击伤害", value = "+33%" } },
    [218] = { { name = "敏捷", value = "+5" }, { name = "运气", value = "+5" }, { name = "物理穿透", value = "+10" } },
    [219] = { { name = "运气", value = "+5" }, { name = "敏捷", value = "+5" }, { name = "暴击率", value = "+6.25%" } },
    [220] = { { name = "运气", value = "+5" }, { name = "力量", value = "+5" }, { name = "物理穿透", value = "+10" } },
    [221] = { { name = "精神", value = "+5" }, { name = "智慧", value = "+5" }, { name = "治疗加成", value = "+20%" } },
    [222] = { { name = "精神", value = "+5" }, { name = "运气", value = "+5" }, { name = "治疗暴击率", value = "+6.25%" } },
    [223] = { { name = "精神", value = "+5" }, { name = "体质", value = "+5" }, { name = "治疗加成", value = "+20%" } },
    [224] = { { name = "精神", value = "+5" }, { name = "智慧", value = "+5" }, { name = "魔法穿透", value = "+10" } },
}

--- 分支 id → 天赋 { name, desc }
local ADV_BRANCH_TALENT = {
    -- ===== 基础职业天赋 =====
    [1] = { name = "阵前叫嚣", desc = "每场战斗开始时，第一次攻击获得20倍仇恨值" },
    [2] = { name = "物理精通", desc = "物理伤害加成+10%" },
    [3] = { name = "魔法精通", desc = "魔法伤害加成+10%" },
    [4] = { name = "远程攻击", desc = "在有骑士/战士存在时，仇恨获得倍率降低80%" },
    [5] = { name = "精准", desc = "暴击率+5%" },
    [6] = { name = "疗愈", desc = "治疗加成+10%" },
    -- ===== 一转天赋 =====
    [101] = { name = "圣光术", desc = "每10秒释放圣光术恢复自己10%生命" },
    [102] = { name = "龙之血", desc = "在战斗开始时和每10秒进行嘲讽，获得相当于模拟平A伤害×50的仇恨值，强制嘲讽3秒；仇恨值保持己方最高时每秒恢复2%已损失生命值" },
    [103] = { name = "狂暴之血", desc = "当前生命值每损失5%，物理攻击加成+2.5%" },
    [104] = { name = "战场决斗", desc = "攻击速度+15%，每5次攻击只会攻击同一个敌人，不会受仇恨值影响，对锁定目标伤害加成+5%" },
    [105] = { name = "易伤诅咒", desc = "每10秒对一个敌人施加持续8秒的[易伤]，使受到额外伤害+20%（乘法计算）" },
    [106] = { name = "奥术飞弹", desc = "每次造成攻击伤害时，有35%概率对随机敌人发射奥术飞弹，造成魔法攻击力*100%的暗影伤害" },
    [107] = { name = "巡游射击", desc = "每当怪物攻击其他角色后1秒，该角色有25%概率无视攻击进度条立即对该怪物进行攻击" },
    [108] = { name = "阵前提速", desc = "战斗开始时获得10层[提速]，每层提供8%攻击速度，每次攻击后减少1层" },
    [109] = { name = "隐匿", desc = "每过去10秒后立即清空仇恨值，清空后获得5秒[暗影]状态：暴击率+15%，暴击伤害+30%" },
    [110] = { name = "影袭", desc = "每当有敌人死亡时，立即填充100%当前攻击进度条，并使下一次攻击伤害加成+30%" },
    [111] = { name = "激励", desc = "每次进行攻击治疗时，立即填充目标25%的攻击进度条，并使目标获得持续3秒的治疗加成+10%" },
    [112] = { name = "团队治疗", desc = "每次进行攻击治疗时，将治疗量的10%为整个团队所有冒险家进行治疗" },
    -- ===== 二转天赋 =====
    [201] = { name = "进阶圣光术", desc = "一转效果[圣光术]治疗的血量提升至三倍，在初次生命值低于50%/20%时立即释放一次[圣光术]" },
    [202] = { name = "传颂祝福", desc = "在战斗中每累计损失10%生命值时，为所有冒险家增加7%伤害加成，最多增加98%" },
    [203] = { name = "十字盾守", desc = "每当受到伤害时提升2点护甲，最多能叠加50次" },
    [204] = { name = "怒龙反击", desc = "每次受到攻击时，立即填充40%当前攻击进度条" },
    [205] = { name = "狂风骤雨", desc = "当前生命值每损失5%，攻击速度+3%，物理暴击率+1.5%" },
    [206] = { name = "嗜血狂怒", desc = "物理攻击加成+35%，当生命值高于50%时每次攻击时减少3%当前生命值" },
    [207] = { name = "武器精通", desc = "无法再装备常规副手，但可在副手装备与主手不同类型的武器" },
    [208] = { name = "幻影剑斩", desc = "攻击同一个敌人时，每次攻击获得1层[连击]，每层[连击]提供10%连击概率和2%连击增伤，最多叠加至10层；切换攻击目标时失去2层[连击]" },
    [209] = { name = "群体诅咒术", desc = "每次诅咒时同时诅咒所有敌人，且[易伤诅咒]的效果提升至25%" },
    [210] = { name = "蚀骨诅咒", desc = "[易伤诅咒]的持续时间延长至15秒。带有诅咒的敌人，每次受到伤害时，都会额外受到一次相当于该角色魔法攻击力*80%的暗影伤害（此效果每1秒最多触发1次）" },
    [211] = { name = "奥术智慧", desc = "[奥术飞弹]的触发概率提升至50%。飞弹现在会优先攻击生命值百分比最低的敌人，且对生命值低于40%的敌人造成的伤害提升100%。当目标生命值低于20%时，[奥术飞弹]必定触发。" },
    [212] = { name = "奥能充盈", desc = "[奥术飞弹]的伤害提升至魔法攻击力*200%。每次触发飞弹时，有30%几率使本次飞弹爆炸，对目标及其相邻单位造成等量伤害。" },
    [213] = { name = "风之气息", desc = "[巡游射击]的触发概率提升至35%。每当触发此效果获得1层[风之气息]，自身攻击速度提升12%，持续5秒，此效果最多叠加3层。" },
    [214] = { name = "林间之眼", desc = "[巡游射击]必定造成暴击，每当进行普通攻击时获得1层[暴击提升]，暴击伤害+8%，持续10秒，此效果最多叠加20层" },
    [215] = { name = "鹰眼", desc = "[阵前提速]获得的[提速]层数+5，每层[提速]额外提供6物理穿透" },
    [216] = { name = "重火力", desc = "攻击速度固定为100%；多余的攻击速度按照1:2转化为物理伤害加成" },
    [217] = { name = "瞬杀", desc = "保持5秒未受到攻击时，暴击概率+25%" },
    [218] = { name = "千面", desc = "保持5秒未受到攻击时，攻击速度+50%，伤害加成+10%" },
    [219] = { name = "致命", desc = "攻击造成暴击时，其攻击进度条立即前进100%，暴击伤害+25%" },
    [220] = { name = "双刃精通", desc = "无法再装备常规副手，但可在副手装备与主手相同类型的武器" },
    [221] = { name = "战争之祭", desc = "[激励]的效果提升至40%。当目标因[激励]效果而立即进行攻击后，其此次攻击造成的伤害提升25%（乘法计算）" },
    [222] = { name = "嗜血祭祀", desc = "[激励]的效果提升至100%，但[激励]变为40%概率触发，因[激励]效果而立即攻击后，被[激励]的单位将恢复本次攻击造成的伤害值的生命值" },
    [223] = { name = "神之赐福", desc = "[团队治疗]治疗量提升至三倍，并且对当前生命值低于20%的冒险家必定造成治疗暴击" },
    [224] = { name = "神圣惩戒", desc = "每当进行任意治疗时，有40%概率对一个随机敌人发射惩戒飞弹，造成治疗量*400%的暗影伤害" },
}

--- 转职消耗金币
local ADV_COST = {
    [1] = 10000,     -- 一转消耗
    [2] = 100000,    -- 二转消耗
}

--- 金币数字格式化：超4位数转K显示
---@param n number
---@return string
local function formatGold(n)
    return NumberUtil.format(n)
end

-- ======================== 转职确认弹窗布局常量 ========================
local CONFIRM = {
    -- 面板背景
    bgCX = 540, bgCY = 1157, bgW = 830, bgH = 1190,
    -- 职业名称
    nameCX = 540, nameCY = 622, nameFont = 40,
    -- 职业图标
    iconCX = 540, iconCY = 802, iconW = 166, iconH = 166,
    -- 转职阶段
    stageCX = 847, stageCY = 915, stageFont = 34,
    -- 基础属性
    attrStartY   = 1016,
    attrSpacing  = 77,
    attrBgW      = 730,    attrBgH = 60,  attrBgR = 14,
    attrLabelX   = 196,
    attrValueX   = 882,
    attrFont     = 34,
    -- "职业天赋"标签
    talentLabelX = 540, talentLabelFont = 30,
    talentLabelGap = 20,
    -- 天赋效果背景框
    talentBgLeft = 175, talentBgRight = 905,
    talentBgGapTop = 20,
    talentBgBottom = 1498,
    talentBgR = 14,
    -- 天赋名称
    talentNameX = 204, talentNameGapTop = 22, talentNameFont = 34,
    -- 天赋效果文本
    talentDescPadTop = 74, talentDescPadLR = 30, talentDescPadBot = 30,
    talentDescFont = 34,
    -- 确认提示
    askCY = 1546, askFont = 34,
    -- 确认按钮
    btnCX = 540, btnCY = 1643, btnW = 410, btnH = 100,
    -- 金币图标+消耗
    coinSize = 87, costFont = 40,
}

-- ======================== 导出数据供外部使用 ========================
-- ChurchPage 的 badge 函数需要这些数据
M.CLASS_NUM            = CLASS_NUM
M.ADV2                 = ADV2
M.FIRST_ADV_BRANCHES   = FIRST_ADV_BRANCHES
M.SECOND_ADV_BRANCHES  = SECOND_ADV_BRANCHES

-- ======================== ctx 注入的共享状态 ========================

---@type table
local state           -- ChurchPage 主 state 表
local img             -- ChurchPage 主 img 表
local easeOutCubic    -- easing 函数
local easeInCubic     -- easing 函数
local POPUP_ANIM_DUR  -- 弹窗动画时长
local POPUP_SCALE_FROM -- 弹窗缩放起始值
local getClient       -- 网络延迟加载
local getProtocol     -- 协议延迟加载
local getDispatcher   -- 事件分发延迟加载

--- 注入共享上下文
---@param ctx table { state, img, easeOutCubic, easeInCubic, POPUP_ANIM_DUR, POPUP_SCALE_FROM, getClient, getProtocol, getDispatcher }
function M.setContext(ctx)
    state           = ctx.state
    img             = ctx.img
    easeOutCubic    = ctx.easeOutCubic
    easeInCubic     = ctx.easeInCubic
    POPUP_ANIM_DUR  = ctx.POPUP_ANIM_DUR
    POPUP_SCALE_FROM = ctx.POPUP_SCALE_FROM
    getClient       = ctx.getClient
    getProtocol     = ctx.getProtocol
    getDispatcher   = ctx.getDispatcher
end

-- ======================== 内部函数 ========================

--- 绘制分支图标状态遮罩（未转职/可转职）
local function drawBranchOverlay(vg, cx, cy, w, h, canAdv)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - w * 0.5, cy - h * 0.5, w, h, 25)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
    nvgFill(vg)
    if canAdv and img.iconUp >= 0 then
        local upSize = 60
        local upX = cx + w * 0.5 - upSize * 0.5
        local upY = cy - h * 0.5 + upSize * 0.5
        drawImageCentered(vg, img.iconUp, upX, upY, upSize, upSize, 1.0)
    end
end

-- ======================== 绘制 API ========================

--- 绘制转职职业背景图（不受 scissor 裁剪，单独调用）
function M.drawBg(vg)
    if not state.selectedHeroId then return end
    local heroCfg = HC.get(state.selectedHeroId)
    if not heroCfg then return end
    local classNum = CLASS_NUM[heroCfg.classId] or 1
    local bgImg = img.classBg[classNum]
    if bgImg and bgImg >= 0 then
        drawImageCentered(vg, bgImg, CLASS_BG_CX, CLASS_BG_CY, CLASS_BG_W, CLASS_BG_H, 1.0)
    end
end

--- 绘制转职 Tab 内容（标题、图标、分支等，不含背景图）
function M.drawContent(vg)
    if not state.selectedHeroId then return end
    local heroCfg = HC.get(state.selectedHeroId)
    if not heroCfg then return end

    local classId = heroCfg.classId
    local classColor = CLASS_COLORS[classId] or { r = 255, g = 255, b = 255 }
    local className = CLASS_DISPLAY_NAMES[classId] or "未知"
    local branches = FIRST_ADV_BRANCHES[classId]

    local ownData = CharacterPanel.getOwnedHero(state.selectedHeroId)
    local heroLevel = getAdvanceHeroLevel(state.selectedHeroId)
    local advBranch = ownData and ownData.advBranch

    -- 标题背景
    drawImageCentered(vg, img.titleBg, TITLE_BG_CX, TITLE_BG_CY, TITLE_BG_W, TITLE_BG_H, 1.0)

    -- 标题文字 "转职"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TITLE_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, TITLE_TEXT_CX, TITLE_TEXT_CY, "转职", nil)

    -- 重置按钮（UI_AN_LV.png，410×100，字号40，纯黑70%不透明）
    do
        local _bfReset = BF.begin(vg, "ccc_reset", BTN_RESET_CX, BTN_RESET_CY, BTN_RESET_W, BTN_RESET_H)
        drawImageCentered(vg, img.confirmBtn, BTN_RESET_CX, BTN_RESET_CY, BTN_RESET_W, BTN_RESET_H, 1.0)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_RESET_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 178))   -- 纯黑 70% 不透明
        nvgText(vg, BTN_RESET_CX, BTN_RESET_CY, "重置", nil)
        BF.finish(vg, _bfReset)
    end

    -- "初始职业"
    drawTextStroke(vg, INIT_LABEL_CX, INIT_LABEL_CY, "初始职业",
        INIT_LABEL_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        classColor.r, classColor.g, classColor.b,
        6,
        { italic = true })

    -- 一转分叉线
    drawImageCentered(vg, img.branchLine, BRANCH_LINE_CX, BRANCH_LINE_CY,
        BRANCH_LINE_W, BRANCH_LINE_H, 1.0)

    -- 初始职业图标
    local initIconId = CLASS_NUM[classId] or 1
    drawImageCentered(vg, img.classIcons2[initIconId] or -1, INIT_ICON_CX, INIT_ICON_CY,
        INIT_ICON_W, INIT_ICON_H, 1.0)

    -- 初始职业名称
    drawTextStroke(vg, INIT_NAME_CX, INIT_NAME_CY, className,
        INIT_NAME_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 6)

    -- 一转分支
    if branches then
        -- 二转分叉线（先绘制，置于一转图标底层）
        drawImageCentered(vg, img.branchLine2, ADV2.line1CX, ADV2.line1CY,
            ADV2.lineW, ADV2.lineH, 1.0)
        drawImageCentered(vg, img.branchLine2, ADV2.line2CX, ADV2.line2CY,
            ADV2.lineW, ADV2.lineH, 1.0)

        -- 分支1
        drawImageCentered(vg, img.classIcons2[branches[1].id] or -1, BR1_ICON_CX, BR1_ICON_CY,
            BR1_ICON_W, BR1_ICON_H, 1.0)
        if heroLevel >= ADV2.firstLevel then
            if advBranch and advBranch.first == branches[1].id then
                -- 已转职：无遮罩
            elseif not advBranch or not advBranch.first then
                drawBranchOverlay(vg, BR1_ICON_CX, BR1_ICON_CY, BR1_ICON_W, BR1_ICON_H, true)
            else
                drawBranchOverlay(vg, BR1_ICON_CX, BR1_ICON_CY, BR1_ICON_W, BR1_ICON_H, false)
            end
        end
        drawTextStroke(vg, BR1_NAME_CX, BR1_NAME_CY, branches[1].name,
            BR1_NAME_FONT,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 6)

        -- 分支2
        drawImageCentered(vg, img.classIcons2[branches[2].id] or -1, BR2_ICON_CX, BR2_ICON_CY,
            BR2_ICON_W, BR2_ICON_H, 1.0)
        if heroLevel >= ADV2.firstLevel then
            if advBranch and advBranch.first == branches[2].id then
                -- 已转职：无遮罩
            elseif not advBranch or not advBranch.first then
                drawBranchOverlay(vg, BR2_ICON_CX, BR2_ICON_CY, BR2_ICON_W, BR2_ICON_H, true)
            else
                drawBranchOverlay(vg, BR2_ICON_CX, BR2_ICON_CY, BR2_ICON_W, BR2_ICON_H, false)
            end
        end
        drawTextStroke(vg, BR2_NAME_CX, BR2_NAME_CY, branches[2].name,
            BR2_NAME_FONT,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 6)

        -- 二转分支（4个）
        local secBranches = {}
        if branches[1] then
            local sb = SECOND_ADV_BRANCHES[branches[1].id]
            if sb then
                secBranches[1] = sb[1]
                secBranches[2] = sb[2]
            end
        end
        if branches[2] then
            local sb = SECOND_ADV_BRANCHES[branches[2].id]
            if sb then
                secBranches[3] = sb[1]
                secBranches[4] = sb[2]
            end
        end

        for i = 1, 4 do
            local sb = secBranches[i]
            local pos = ADV2.pos[i]
            if sb and pos then
                drawImageCentered(vg, img.classIcons2[sb.id] or -1, pos.iconCX, pos.iconCY,
                    ADV2.iconW, ADV2.iconH, 1.0)
                if heroLevel >= ADV2.secondLevel then
                    local parentFirstId = (i <= 2) and branches[1].id or branches[2].id
                    if advBranch and advBranch.second == sb.id then
                        -- 已转职：无遮罩
                    elseif advBranch and advBranch.first == parentFirstId
                           and not advBranch.second then
                        drawBranchOverlay(vg, pos.iconCX, pos.iconCY,
                            ADV2.iconW, ADV2.iconH, true)
                    else
                        drawBranchOverlay(vg, pos.iconCX, pos.iconCY,
                            ADV2.iconW, ADV2.iconH, false)
                    end
                end
                drawTextStroke(vg, pos.nameCX, pos.nameCY, sb.name,
                    ADV2.nameFontSize,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 6)
            end
        end
    end

    -- 等级锁定遮罩
    if heroLevel < ADV2.firstLevel then
        local top = ADV2.lock1.bgCY - ADV2.lock1.bgH * 0.5
        local bot = ADV2.lock2.bgCY + ADV2.lock2.bgH * 0.5
        local w   = ADV2.lock1.bgW
        local cx  = ADV2.lock1.bgCX
        nvgBeginPath(vg)
        nvgRect(vg, cx - w * 0.5, top, w, bot - top)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
        nvgFill(vg)
        local lk1 = ADV2.lock1
        drawTextStroke(vg, lk1.titleCX, lk1.titleCY, "一转",
            ADV2.lockFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            classColor.r, classColor.g, classColor.b, 6,
            { italic = true })
        drawTextStroke(vg, lk1.descCX, lk1.descCY,
            "达到Lv" .. ADV2.firstLevel .. "解锁",
            ADV2.lockFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 6,
            { italic = true })
        local lk2 = ADV2.lock2
        drawTextStroke(vg, lk2.titleCX, lk2.titleCY, "二转",
            ADV2.lockFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            classColor.r, classColor.g, classColor.b, 6,
            { italic = true })
        drawTextStroke(vg, lk2.descCX, lk2.descCY,
            "达到Lv" .. ADV2.secondLevel .. "解锁",
            ADV2.lockFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 6,
            { italic = true })
    elseif heroLevel < ADV2.secondLevel then
        local lk = ADV2.lock2
        nvgBeginPath(vg)
        nvgRect(vg, lk.bgCX - lk.bgW * 0.5, lk.bgCY - lk.bgH * 0.5, lk.bgW, lk.bgH)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
        nvgFill(vg)
        drawTextStroke(vg, lk.titleCX, lk.titleCY, "二转",
            ADV2.lockFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            classColor.r, classColor.g, classColor.b, 6,
            { italic = true })
        drawTextStroke(vg, lk.descCX, lk.descCY,
            "达到Lv" .. ADV2.secondLevel .. "解锁",
            ADV2.lockFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 6,
            { italic = true })
    end
end

-- ======================== 确认弹窗 ========================

--- 打开转职确认弹窗
---@param advLevel number 0=基础, 1=一转, 2=二转
---@param branchId number 分支 id
---@param branchName string 分支名称
---@param classNum number 职业序号 1~6
---@param owned boolean? 是否已拥有
function M.openConfirmPopup(advLevel, branchId, branchName, classNum, owned)
    state.confirmPopup      = true
    state.confirmAdvLevel   = advLevel
    state.confirmBranchId   = branchId
    state.confirmBranchName = branchName
    state.confirmClassNum   = classNum
    state.confirmOwned      = owned or false
    state.confirmClosing    = false
    state.confirmAnimT      = time.elapsedTime
    print("[ChurchClassChange] 打开转职确认: " .. branchName .. " (Lv" .. advLevel .. "转, owned=" .. tostring(state.confirmOwned) .. ")")
end

--- 关闭转职确认弹窗（带动画）
function M.closeConfirmPopup()
    if not state.confirmPopup then return end
    if state.confirmClosing then return end
    state.confirmClosing = true
    state.confirmAnimT = time.elapsedTime
    print("[ChurchClassChange] 关闭转职确认弹窗（动画）")
end

--- 绘制转职确认弹窗
function M.drawConfirmPopup(vg)
    if not state.confirmPopup then return end

    local C = CONFIRM
    local branchId   = state.confirmBranchId
    local branchName = state.confirmBranchName
    local advLevel   = state.confirmAdvLevel
    local classNum   = state.confirmClassNum

    -- 动画进度
    local elapsed = time.elapsedTime - state.confirmAnimT
    local rawT = math.min(1.0, elapsed / POPUP_ANIM_DUR)
    local popProgress
    if state.confirmClosing then
        popProgress = 1.0 - easeInCubic(rawT)
        if rawT >= 1.0 then
            state.confirmPopup = false
            state.confirmClosing = false
            return
        end
    else
        popProgress = easeOutCubic(rawT)
    end
    local popScale = POPUP_SCALE_FROM + (1.0 - POPUP_SCALE_FROM) * popProgress

    -- 获取角色名和等级
    local heroName = ""
    local heroLevel = state.selectedHeroId and getAdvanceHeroLevel(state.selectedHeroId) or 1
    if state.selectedHeroId then
        local heroCfg = HC.get(state.selectedHeroId)
        if heroCfg then heroName = heroCfg.name end
    end

    -- 获取职业颜色
    local heroCfg = state.selectedHeroId and HC.get(state.selectedHeroId)
    local classId = heroCfg and heroCfg.classId
    local classColor = classId and CLASS_COLORS[classId] or { r = 255, g = 255, b = 255 }

    -- 背景遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * popProgress + 0.5)))
    nvgFill(vg)

    -- 缩放变换
    nvgSave(vg)
    nvgTranslate(vg, C.bgCX, C.bgCY)
    nvgScale(vg, popScale, popScale)
    nvgTranslate(vg, -C.bgCX, -C.bgCY)
    nvgGlobalAlpha(vg, popProgress)

    -- 弹窗面板背景
    local bgImg = img.confirmBg[classNum] or img.confirmBg[1]
    drawImageCentered(vg, bgImg, C.bgCX, C.bgCY, C.bgW, C.bgH, 1.0)

    -- 职业名称
    drawTextStroke(vg, C.nameCX, C.nameCY, branchName,
        C.nameFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4,
        { strokeColor = { 0x28, 0x28, 0x28 } })

    -- 职业图标
    drawImageCentered(vg, img.classIcons2[branchId] or -1, C.iconCX, C.iconCY, C.iconW, C.iconH, 1.0)

    -- 转职阶段
    local stageText = advLevel == 0 and "基础职业" or (advLevel == 1 and "一转" or "二转")
    drawTextStroke(vg, C.stageCX, C.stageCY, stageText,
        C.stageFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4,
        { strokeColor = { 0x28, 0x28, 0x28 } })

    -- 基础属性列表
    local attrs = ADV_BRANCH_ATTRS[branchId] or {}
    local attrCount = #attrs
    for i, attr in ipairs(attrs) do
        local ay = C.attrStartY + (i - 1) * C.attrSpacing

        nvgBeginPath(vg)
        nvgRoundedRect(vg, C.bgCX - C.attrBgW * 0.5, ay - C.attrBgH * 0.5,
            C.attrBgW, C.attrBgH, C.attrBgR)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))
        nvgFill(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, C.attrFont)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
        nvgText(vg, C.attrLabelX, ay, attr.name, nil)

        drawTextStroke(vg, C.attrValueX, ay, attr.value,
            C.attrFont, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)
    end

    -- "职业天赋" 标签
    local lastAttrBottomY = C.attrStartY + (attrCount - 1) * C.attrSpacing + C.attrBgH * 0.5
    local talentLabelY = lastAttrBottomY + C.talentLabelGap
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, C.talentLabelFont)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(0x91, 0x8f, 0x88, 255))
    nvgText(vg, C.talentLabelX, talentLabelY, "职业天赋", nil)

    -- 天赋效果背景框
    local talentBgTop = talentLabelY + C.talentLabelFont + C.talentBgGapTop
    local talentBgW = C.talentBgRight - C.talentBgLeft
    local talentBgH = C.talentBgBottom - talentBgTop
    nvgBeginPath(vg)
    nvgRoundedRect(vg, C.talentBgLeft, talentBgTop, talentBgW, talentBgH, C.talentBgR)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))
    nvgFill(vg)

    -- 天赋名称
    local talent = ADV_BRANCH_TALENT[branchId]
    if talent then
        local talentNameY = talentBgTop + C.talentNameGapTop
        drawTextStroke(vg, C.talentNameX, talentNameY, talent.name,
            C.talentNameFont, NVG_ALIGN_LEFT + NVG_ALIGN_TOP,
            classColor.r, classColor.g, classColor.b, 5)

        -- 天赋效果文本（自适应缩放）
        local descLeft = C.talentBgLeft + C.talentDescPadLR
        local descTop  = talentBgTop + C.talentDescPadTop
        local descW    = talentBgW - C.talentDescPadLR * 2
        local maxDescH = C.talentBgBottom - descTop - C.talentDescPadBot

        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

        local fontSize = C.talentDescFont
        local minFont  = 20
        while fontSize > minFont do
            nvgFontSize(vg, fontSize)
            local bounds = nvgTextBoxBounds(vg, descLeft, descTop, descW, talent.desc)
            if bounds and bounds[4] then
                local textH = bounds[4] - descTop
                if textH <= maxDescH then break end
            else
                break
            end
            fontSize = fontSize - 2
        end

        nvgFontSize(vg, fontSize)
        nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
        nvgTextBox(vg, descLeft, descTop, descW, talent.desc, nil)
    end

    -- 底部区域
    if state.confirmOwned then
        -- 已拥有模式
        local _bf1 = BF.begin(vg, "ccc_confirm", C.btnCX, C.btnCY, C.btnW, C.btnH)
        drawImageCentered(vg, img.confirmBtn, C.btnCX, C.btnCY, C.btnW, C.btnH, 1.0)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, C.costFont)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x1e, 0x51, 0x37, 255))
        nvgText(vg, C.btnCX, C.btnCY, "已拥有", nil)
        BF.finish(vg, _bf1)
    else
        -- 判断是否不可转职（等级不足 或 已走另一条路线）
        local locked = false
        local lockReason = ""
        -- 等级不足判断
        if advLevel == 1 and heroLevel < ADV2.firstLevel then
            locked = true
            lockReason = "需要Lv" .. ADV2.firstLevel
        elseif advLevel == 2 and heroLevel < ADV2.secondLevel then
            locked = true
            lockReason = "需要Lv" .. ADV2.secondLevel
        end
        -- 已走另一条路线判断
        if not locked and advLevel > 0 and state.selectedHeroId then
            local ownData = CharacterPanel.getOwnedHero(state.selectedHeroId)
            local ab = ownData and ownData.advBranch
            if ab then
                if advLevel == 1 and ab.first and ab.first ~= branchId then
                    locked = true
                    lockReason = "不可转职"
                elseif advLevel == 2 then
                    local parentFirstId = nil
                    local heroCfg2 = HC.get(state.selectedHeroId)
                    local cid = heroCfg2 and heroCfg2.classId
                    if cid then
                        local br = FIRST_ADV_BRANCHES[cid]
                        if br then
                            for _, b in ipairs(br) do
                                local sb = SECOND_ADV_BRANCHES[b.id]
                                if sb then
                                    for _, s in ipairs(sb) do
                                        if s.id == branchId then parentFirstId = b.id end
                                    end
                                end
                            end
                        end
                    end
                    if ab.first and parentFirstId and ab.first ~= parentFirstId then
                        locked = true
                        lockReason = "不可转职"
                    elseif ab.second and ab.second ~= branchId then
                        locked = true
                        lockReason = "不可转职"
                    end
                end
            end
        end

        if locked then
            -- 不可转职 / 等级不足
            drawImageCentered(vg, img.confirmBtn, C.btnCX, C.btnCY, C.btnW, C.btnH, 0.4)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, C.costFont)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0x80, 0x80, 0x80, 255))
            nvgText(vg, C.btnCX, C.btnCY, lockReason, nil)
        else
            -- 转职确认
            local askText = "是否让" .. heroName .. "转职为" .. branchName
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, C.askFont)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 255))
            nvgText(vg, C.bgCX, C.askCY, askText, nil)

            -- 确认按钮背景
            local _bf2 = BF.begin(vg, "ccc_confirm", C.btnCX, C.btnCY, C.btnW, C.btnH)
            drawImageCentered(vg, img.confirmBtn, C.btnCX, C.btnCY, C.btnW, C.btnH, 1.0)

            -- 金币图标+消耗
            local cost = ADV_COST[advLevel] or 5000
            local costStr = formatGold(cost)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, C.costFont)
            local costTextW = nvgTextBounds(vg, 0, 0, costStr)
            local coinGap = 6
            local totalCoinW = C.coinSize + coinGap + costTextW
            local coinStartX = C.btnCX - totalCoinW * 0.5

            drawImageCentered(vg, img.goldCoin,
                coinStartX + C.coinSize * 0.5, C.btnCY,
                C.coinSize, C.coinSize, 1.0)

            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0x1e, 0x51, 0x37, 255))
            nvgText(vg, coinStartX + C.coinSize + coinGap, C.btnCY, costStr, nil)
            BF.finish(vg, _bf2)
        end
    end

    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

--- 确认弹窗输入处理（模态）
---@param dx number 设计坐标X
---@param dy number 设计坐标Y
---@return boolean consumed
function M.handleConfirmInput(dx, dy)
    if not state.confirmPopup then return false end
    if state.confirmClosing then return true end

    local C = CONFIRM

    -- 确认按钮
    if hitTest(dx, dy, C.btnCX, C.btnCY, C.btnW, C.btnH) then
        if state.confirmOwned then
            BF.trigger("ccc_confirm")
            print("[ChurchClassChange] 关闭已拥有职业信息: " .. state.confirmBranchName)
            M.closeConfirmPopup()
        else
            -- 判断是否已走另一条路线
            local clickLocked = false
            if state.confirmAdvLevel > 0 and state.selectedHeroId then
                local od = CharacterPanel.getOwnedHero(state.selectedHeroId)
                local ab = od and od.advBranch
                if ab then
                    if state.confirmAdvLevel == 1 and ab.first and ab.first ~= state.confirmBranchId then
                        clickLocked = true
                    elseif state.confirmAdvLevel == 2 then
                        if ab.first then
                            local pid = nil
                            local hc = HC.get(state.selectedHeroId)
                            local cid = hc and hc.classId
                            if cid and FIRST_ADV_BRANCHES[cid] then
                                for _, b in ipairs(FIRST_ADV_BRANCHES[cid]) do
                                    local sb = SECOND_ADV_BRANCHES[b.id]
                                    if sb then
                                        for _, s in ipairs(sb) do
                                            if s.id == state.confirmBranchId then pid = b.id end
                                        end
                                    end
                                end
                            end
                            if pid and ab.first ~= pid then clickLocked = true end
                        end
                        if not clickLocked and ab.second and ab.second ~= state.confirmBranchId then
                            clickLocked = true
                        end
                    end
                end
            end
            if clickLocked then
                print("[ChurchClassChange] 不可转职（已走另一条路线）: " .. state.confirmBranchName)
                M.closeConfirmPopup()
                return true
            end
            BF.trigger("ccc_confirm")
            -- 检查金币
            local cost = ADV_COST[state.confirmAdvLevel] or 5000
            local gold = GameState.getGold()
            if gold < cost then
                state.floatText = "金币不足"
                state.floatTextX = C.btnCX
                state.floatTextY = C.btnCY
                state.floatTextTime = time.elapsedTime
                print("[ChurchClassChange] 金币不足: 需要" .. cost .. " 拥有" .. gold)
            else
                print("[ChurchClassChange] 确认转职: " .. state.confirmBranchName
                    .. " heroId=" .. tostring(state.selectedHeroId)
                    .. " branchId=" .. tostring(state.confirmBranchId)
                    .. " advLevel=" .. tostring(state.confirmAdvLevel))
                getClient().sendAction(getProtocol().ACTION_TYPES.ADVANCE_CLASS, {
                    heroId   = state.selectedHeroId,
                    branchId = state.confirmBranchId,
                    advLevel = state.confirmAdvLevel,
                })
                M.closeConfirmPopup()
            end
        end
        return true
    end

    -- 同帧保护：防止 openConfirmPopup() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.confirmAnimT < 0.05 then return true end

    -- 点击面板外部 → 关闭弹窗
    if not hitTest(dx, dy, C.bgCX, C.bgCY, C.bgW, C.bgH) then
        M.closeConfirmPopup()
        return true
    end

    -- 弹窗内其他区域
    return true
end

--- 转职分支图标点击 → 打开确认弹窗
---@param dx number 设计坐标X
---@param dy number 设计坐标Y
---@return boolean consumed
function M.handleBranchInput(dx, dy)
    if not state.selectedHeroId then return false end

    local heroCfg = HC.get(state.selectedHeroId)
    local classId = heroCfg and heroCfg.classId
    local classNum = classId and CLASS_NUM[classId] or 1
    local className = classId and CLASS_DISPLAY_NAMES[classId] or "未知"
    local heroLevel = getAdvanceHeroLevel(state.selectedHeroId)
    local ownData = CharacterPanel.getOwnedHero(state.selectedHeroId)

    -- 基础职业图标
    if classId then
        local initIconId = CLASS_NUM[classId] or 1
        if hitTest(dx, dy, INIT_ICON_CX, INIT_ICON_CY, INIT_ICON_W, INIT_ICON_H) then
            M.openConfirmPopup(0, initIconId, className, classNum, true)
            return true
        end
    end

    -- 一转分支图标（等级不足也可点击查看详情）
    if classId then
        local branches = FIRST_ADV_BRANCHES[classId]
        local advBranch = ownData and ownData.advBranch
        if branches then
            if hitTest(dx, dy, BR1_ICON_CX, BR1_ICON_CY, BR1_ICON_W, BR1_ICON_H) then
                local owned = advBranch and advBranch.first == branches[1].id
                M.openConfirmPopup(1, branches[1].id, branches[1].name, classNum, owned)
                return true
            end
            if hitTest(dx, dy, BR2_ICON_CX, BR2_ICON_CY, BR2_ICON_W, BR2_ICON_H) then
                local owned = advBranch and advBranch.first == branches[2].id
                M.openConfirmPopup(1, branches[2].id, branches[2].name, classNum, owned)
                return true
            end
        end
    end

    -- 二转分支图标（等级不足也可点击查看详情）
    if classId then
        local branches = FIRST_ADV_BRANCHES[classId]
        local advBranch = ownData and ownData.advBranch
        if branches then
            local secBranches = {}
            if branches[1] then
                local sb = SECOND_ADV_BRANCHES[branches[1].id]
                if sb then secBranches[1] = sb[1]; secBranches[2] = sb[2] end
            end
            if branches[2] then
                local sb = SECOND_ADV_BRANCHES[branches[2].id]
                if sb then secBranches[3] = sb[1]; secBranches[4] = sb[2] end
            end
            for i = 1, 4 do
                local sb = secBranches[i]
                local pos = ADV2.pos[i]
                if sb and pos then
                    if hitTest(dx, dy, pos.iconCX, pos.iconCY, ADV2.iconW, ADV2.iconH) then
                        local owned = advBranch and advBranch.second == sb.id
                        M.openConfirmPopup(2, sb.id, sb.name, classNum, owned)
                        return true
                    end
                end
            end
        end
    end

    -- 重置按钮 → 打开二级确认弹窗
    if hitTest(dx, dy, BTN_RESET_CX, BTN_RESET_CY, BTN_RESET_W, BTN_RESET_H) then
        BF.trigger("ccc_reset")
        if state.selectedHeroId then
            M.openResetConfirmPopup()
        end
        return true
    end

    return false
end

-- ======================== 重置转职二级确认弹窗 ========================
-- 参考终焉神殿确认弹窗样式（九宫格背景 + 确认/取消按钮）

local RC = {
    BG_CX = 540, BG_CY = 1100, BG_W = 950, BG_H = 580,
    -- 标题（白色 + 棕色描边）
    TITLE_CY = 880, TITLE_FONT = 56, TITLE_SW = 6,
    TITLE_SR = 0x46, TITLE_SG = 0x2f, TITLE_SB = 0x20,
    -- 副标题
    SUB_CY = 980, SUB_FONT = 38,
    -- 说明行
    LINE1_CY = 1060, LINE_FONT = 36,
    LINE2_CY = 1120,
    -- 确认按钮（绿色）
    OK_CX = 340, OK_CY = 1280, OK_W = 310, OK_H = 100, OK_FONT = 40,
    OK_TR = 0x2a, OK_TG = 0x52, OK_TB = 0x18,
    -- 取消按钮（灰色）
    CANCEL_CX = 740, CANCEL_CY = 1280, CANCEL_W = 310, CANCEL_H = 100, CANCEL_FONT = 40,
    CANCEL_TR = 0x50, CANCEL_TG = 0x46, CANCEL_TB = 0x3c,
}

--- 计算当前英雄重置时可返还的金币
---@return number refundGold
local function calcResetRefund()
    if not state.selectedHeroId then return 0 end
    local ownData = CharacterPanel.getOwnedHero(state.selectedHeroId)
    if not ownData or not ownData.advBranch then return 0 end
    local refund = 0
    if ownData.advBranch.first then
        refund = refund + math.floor(ADV_COST[1] * 0.5)
    end
    if ownData.advBranch.second then
        refund = refund + math.floor(ADV_COST[2] * 0.5)
    end
    return refund
end

--- 打开重置转职确认弹窗
function M.openResetConfirmPopup()
    state.resetConfPopup   = true
    state.resetConfClosing = false
    state.resetConfAnimT   = time.elapsedTime
    state.resetConfRefund  = calcResetRefund()
    print("[ChurchClassChange] 打开重置确认弹窗 refund=" .. tostring(state.resetConfRefund))
end

--- 关闭重置转职确认弹窗（带动画）
function M.closeResetConfirmPopup()
    if not state.resetConfPopup then return end
    if state.resetConfClosing then return end
    state.resetConfClosing = true
    state.resetConfAnimT   = time.elapsedTime
end

--- 绘制重置转职确认弹窗
function M.drawResetConfirmPopup(vg)
    if not state.resetConfPopup then return end

    -- 动画进度
    local elapsed = time.elapsedTime - state.resetConfAnimT
    local rawT = math.min(1.0, elapsed / POPUP_ANIM_DUR)
    local popProgress
    if state.resetConfClosing then
        popProgress = 1.0 - easeInCubic(rawT)
        if rawT >= 1.0 then
            state.resetConfPopup = false
            state.resetConfClosing = false
            return
        end
    else
        popProgress = easeOutCubic(rawT)
    end
    local popScale = POPUP_SCALE_FROM + (1.0 - POPUP_SCALE_FROM) * popProgress

    -- 背景遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * popProgress + 0.5)))
    nvgFill(vg)

    -- 缩放变换
    nvgSave(vg)
    nvgTranslate(vg, RC.BG_CX, RC.BG_CY)
    nvgScale(vg, popScale, popScale)
    nvgTranslate(vg, -RC.BG_CX, -RC.BG_CY)
    nvgGlobalAlpha(vg, popProgress)

    -- 弹窗背景 [暗黑化 P1-B5] 矢量面板
    DarkIcon.drawNine(vg, "panel",
        RC.BG_CX - RC.BG_W * 0.5, RC.BG_CY - RC.BG_H * 0.5,
        RC.BG_W, RC.BG_H)

    -- 标题 "重置转职"
    drawTextStroke(vg, RC.BG_CX, RC.TITLE_CY, "⚠ 重置转职", RC.TITLE_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, RC.TITLE_SW,
        { strokeColor = { RC.TITLE_SR, RC.TITLE_SG, RC.TITLE_SB } })

    -- 副标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, RC.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 255))
    nvgText(vg, RC.BG_CX, RC.SUB_CY, "确认重置当前英雄的转职？", nil)

    -- 说明文本
    nvgFontSize(vg, RC.LINE_FONT)
    nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
    nvgText(vg, RC.BG_CX, RC.LINE1_CY, "重置后将清除所有转职分支", nil)

    local refund = state.resetConfRefund or 0
    local refundText = "返还50%已消耗金币: " .. formatGold(refund) .. " 金币"
    nvgFillColor(vg, nvgRGBA(0xc8, 0x96, 0x20, 255))  -- 金色高亮
    nvgText(vg, RC.BG_CX, RC.LINE2_CY, refundText, nil)

    -- 确认按钮（绿色）[暗黑化 P1-B3]
    DarkIcon.drawNine(vg, "btn",
        RC.OK_CX - RC.OK_W * 0.5, RC.OK_CY - RC.OK_H * 0.5,
        RC.OK_W, RC.OK_H, { accent = "green" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, RC.OK_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(RC.OK_TR, RC.OK_TG, RC.OK_TB, 255))
    nvgText(vg, RC.OK_CX, RC.OK_CY, "确认重置", nil)

    -- 取消按钮（灰色）[暗黑化 P1-B3]
    DarkIcon.drawNine(vg, "btn",
        RC.CANCEL_CX - RC.CANCEL_W * 0.5, RC.CANCEL_CY - RC.CANCEL_H * 0.5,
        RC.CANCEL_W, RC.CANCEL_H)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, RC.CANCEL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(RC.CANCEL_TR, RC.CANCEL_TG, RC.CANCEL_TB, 255))
    nvgText(vg, RC.CANCEL_CX, RC.CANCEL_CY, "取消", nil)

    nvgRestore(vg)
end

--- 处理重置确认弹窗的触摸输入
---@param dx number 设计坐标X
---@param dy number 设计坐标Y
---@return boolean consumed
function M.handleResetConfirmInput(dx, dy)
    if not state.resetConfPopup then return false end
    if state.resetConfClosing then return true end

    -- 确认按钮
    if hitTest(dx, dy, RC.OK_CX, RC.OK_CY, RC.OK_W, RC.OK_H) then
        BF.trigger("ccc_reset_confirm")
        if state.selectedHeroId then
            print("[ChurchClassChange] 确认重置转职 heroId=" .. tostring(state.selectedHeroId))
            getClient().sendAction(getProtocol().ACTION_TYPES.RESET_CLASS, {
                heroId = state.selectedHeroId,
            })
        end
        M.closeResetConfirmPopup()
        return true
    end

    -- 取消按钮
    if hitTest(dx, dy, RC.CANCEL_CX, RC.CANCEL_CY, RC.CANCEL_W, RC.CANCEL_H) then
        BF.trigger("ccc_reset_cancel")
        M.closeResetConfirmPopup()
        return true
    end

    -- 同帧保护
    if time.elapsedTime - state.resetConfAnimT < 0.05 then return true end

    -- 点击面板外部 → 关闭
    if not hitTest(dx, dy, RC.BG_CX, RC.BG_CY, RC.BG_W, RC.BG_H) then
        M.closeResetConfirmPopup()
        return true
    end

    return true
end

return M
