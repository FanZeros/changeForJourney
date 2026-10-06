-- ============================================================================
-- DungeonConfig - 副本配置数据
-- 职责: 定义所有副本的层数、奖励、怪物、增益等静态数据
-- ============================================================================

local DungeonConfig = {}

-- ======================== 职业增益循环 ========================

--- 职业增益类型（每5层循环: 战士→法师→射手→刺客→牧师）
DungeonConfig.CLASS_BONUS_CYCLE = {
    "spoil",     -- 拾骸者（原战士）
    "rift",      -- 裂隙使（原法师）
    "echo",      -- 回响客（原射手；旧值 archer 对不上 ranger）
    "mask",      -- 换面人（原刺客）
    "debt",      -- 司仪（原牧师）
}

--- 职业增益数值
DungeonConfig.CLASS_BONUS_VALUE = 0.20  -- +20% 伤害/治疗

--- 根据层数获取增益职业
---@param floor number 层数
---@return string 职业标识
function DungeonConfig.getClassBonus(floor)
    local idx = ((floor - 1) % 5) + 1
    return DungeonConfig.CLASS_BONUS_CYCLE[idx]
end

-- ======================== 狂暴机制 ========================

DungeonConfig.RAGE_TIME       = 30    -- 狂暴触发时间(秒)
DungeonConfig.RAGE_ATK_BONUS  = 0.50  -- 狂暴攻速加成 +50%

DungeonConfig.SUPER_RAGE_TIME      = 60    -- 超级狂暴触发时间(秒)
DungeonConfig.SUPER_RAGE_ATK_BONUS = 1.00  -- 超级狂暴攻速加成 +100%
DungeonConfig.SUPER_RAGE_DMG_BONUS = 0.30  -- 超级狂暴敌方攻击力 +30%
DungeonConfig.ALLY_RAGE_DMG_BONUS = 0.30   -- 狂暴己方攻击力 +30%
DungeonConfig.ALLY_SUPER_RAGE_DMG_BONUS = 0.30 -- 超级狂暴己方攻击力 +30%

-- ======================== 解锁条件 ========================

DungeonConfig.UNLOCK_CONDITIONS = {
    gold_mine    = 0305,  -- 最高关卡进度大于 0305
    ancient_ruin = 1305,  -- 最高关卡进度大于 1305
    babel_tower  = 0605,  -- 通天塔：关卡进度6-5解锁
}

-- ======================== 副本定义 ========================

--- 黄金矿洞 - 115层配置
---@type table[]
DungeonConfig.GOLD_MINE = {
    { floor = 1,  firstGold = 5000,    sweepGold = 2500,    monsterLevel = 3,   monsters = {201, 202, 203} },
    { floor = 2,  firstGold = 10000,   sweepGold = 5000,    monsterLevel = 6,   monsters = {201, 202, 203} },
    { floor = 3,  firstGold = 20000,   sweepGold = 10000,   monsterLevel = 9,   monsters = {201, 202, 203} },
    { floor = 4,  firstGold = 35000,   sweepGold = 17500,   monsterLevel = 12,  monsters = {201, 202, 203} },
    { floor = 5,  firstGold = 55000,   sweepGold = 27500,   monsterLevel = 15,  monsters = {201, 202, 203} },
    { floor = 6,  firstGold = 80000,   sweepGold = 40000,   monsterLevel = 18,  monsters = {201, 202, 203} },
    { floor = 7,  firstGold = 110000,  sweepGold = 55000,   monsterLevel = 21,  monsters = {201, 202, 203} },
    { floor = 8,  firstGold = 145000,  sweepGold = 72500,   monsterLevel = 24,  monsters = {201, 202, 203} },
    { floor = 9,  firstGold = 185000,  sweepGold = 92500,   monsterLevel = 27,  monsters = {201, 202, 203} },
    { floor = 10, firstGold = 230000,  sweepGold = 115000,  monsterLevel = 30,  monsters = {201, 202, 203} },
    { floor = 11, firstGold = 280000,  sweepGold = 140000,  monsterLevel = 33,  monsters = {201, 202, 203} },
    { floor = 12, firstGold = 335000,  sweepGold = 167500,  monsterLevel = 36,  monsters = {201, 202, 203} },
    { floor = 13, firstGold = 395000,  sweepGold = 197500,  monsterLevel = 39,  monsters = {201, 202, 203} },
    { floor = 14, firstGold = 460000,  sweepGold = 230000,  monsterLevel = 42,  monsters = {201, 202, 203} },
    { floor = 15, firstGold = 530000,  sweepGold = 265000,  monsterLevel = 45,  monsters = {201, 202, 203} },
    { floor = 16, firstGold = 605000,  sweepGold = 302500,  monsterLevel = 48,  monsters = {201, 202, 203} },
    { floor = 17, firstGold = 685000,  sweepGold = 342500,  monsterLevel = 51,  monsters = {201, 202, 203} },
    { floor = 18, firstGold = 770000,  sweepGold = 385000,  monsterLevel = 54,  monsters = {201, 202, 203} },
    { floor = 19, firstGold = 860000,  sweepGold = 430000,  monsterLevel = 57,  monsters = {201, 202, 203} },
    { floor = 20, firstGold = 955000,  sweepGold = 477500,  monsterLevel = 60,  monsters = {201, 202, 203} },
    { floor = 21, firstGold = 1055000, sweepGold = 527500,  monsterLevel = 63,  monsters = {201, 202, 203} },
    { floor = 22, firstGold = 1160000, sweepGold = 580000,  monsterLevel = 66,  monsters = {201, 202, 203} },
    { floor = 23, firstGold = 1270000, sweepGold = 635000,  monsterLevel = 69,  monsters = {201, 202, 203} },
    { floor = 24, firstGold = 1385000, sweepGold = 692500,  monsterLevel = 72,  monsters = {201, 202, 203} },
    { floor = 25, firstGold = 1505000, sweepGold = 752500,  monsterLevel = 75,  monsters = {201, 202, 203} },
    { floor = 26, firstGold = 1630000, sweepGold = 815000,  monsterLevel = 78,  monsters = {201, 202, 203} },
    { floor = 27, firstGold = 1760000, sweepGold = 880000,  monsterLevel = 81,  monsters = {201, 202, 203} },
    { floor = 28, firstGold = 1895000, sweepGold = 947500,  monsterLevel = 84,  monsters = {201, 202, 203} },
    { floor = 29, firstGold = 2035000, sweepGold = 1017500, monsterLevel = 87,  monsters = {201, 202, 203} },
    { floor = 30, firstGold = 2180000, sweepGold = 1090000, monsterLevel = 90,  monsters = {201, 202, 203} },
    { floor = 31, firstGold = 2330000, sweepGold = 1165000, monsterLevel = 93,  monsters = {201, 202, 203} },
    { floor = 32, firstGold = 2485000, sweepGold = 1242500, monsterLevel = 96,  monsters = {201, 202, 203} },
    { floor = 33, firstGold = 2645000, sweepGold = 1322500, monsterLevel = 99,  monsters = {201, 202, 203} },
    { floor = 34, firstGold = 2810000, sweepGold = 1405000, monsterLevel = 102, monsters = {201, 202, 203} },
    { floor = 35, firstGold = 2980000, sweepGold = 1490000, monsterLevel = 105, monsters = {201, 202, 203} },
    { floor = 36, firstGold = 3155000, sweepGold = 1577500, monsterLevel = 108, monsters = {201, 202, 203} },
    { floor = 37, firstGold = 3335000, sweepGold = 1667500, monsterLevel = 111, monsters = {201, 202, 203} },
    { floor = 38, firstGold = 3520000, sweepGold = 1760000, monsterLevel = 114, monsters = {201, 202, 203} },
    { floor = 39, firstGold = 3710000, sweepGold = 1855000, monsterLevel = 117, monsters = {201, 202, 203} },
    { floor = 40, firstGold = 3905000, sweepGold = 1952500, monsterLevel = 120, monsters = {201, 202, 203} },
    { floor = 41, firstGold = 4105000, sweepGold = 2052500, monsterLevel = 123, monsters = {201, 202, 203} },
    { floor = 42, firstGold = 4310000, sweepGold = 2155000, monsterLevel = 126, monsters = {201, 202, 203} },
    { floor = 43, firstGold = 4520000, sweepGold = 2260000, monsterLevel = 129, monsters = {201, 202, 203} },
    { floor = 44, firstGold = 4735000, sweepGold = 2367500, monsterLevel = 132, monsters = {201, 202, 203} },
    { floor = 45, firstGold = 4955000, sweepGold = 2477500, monsterLevel = 135, monsters = {201, 202, 203} },
    { floor = 46, firstGold = 5180000, sweepGold = 2590000, monsterLevel = 138, monsters = {201, 202, 203} },
    { floor = 47, firstGold = 5410000, sweepGold = 2705000, monsterLevel = 141, monsters = {201, 202, 203} },
    { floor = 48, firstGold = 5645000, sweepGold = 2822500, monsterLevel = 144, monsters = {201, 202, 203} },
    { floor = 49, firstGold = 5885000, sweepGold = 2942500, monsterLevel = 147, monsters = {201, 202, 203} },
    { floor = 50, firstGold = 6130000, sweepGold = 3065000, monsterLevel = 150, monsters = {201, 202, 203} },
    { floor = 51, firstGold = 6380000, sweepGold = 3190000, monsterLevel = 153, monsters = {201, 202, 203} },
    { floor = 52, firstGold = 6635000, sweepGold = 3317500, monsterLevel = 156, monsters = {201, 202, 203} },
    { floor = 53, firstGold = 6895000, sweepGold = 3447500, monsterLevel = 159, monsters = {201, 202, 203} },
    { floor = 54, firstGold = 7160000, sweepGold = 3580000, monsterLevel = 162, monsters = {201, 202, 203} },
    { floor = 55, firstGold = 7430000, sweepGold = 3715000, monsterLevel = 165, monsters = {201, 202, 203} },
    { floor = 56, firstGold = 7705000, sweepGold = 3852500, monsterLevel = 168, monsters = {201, 202, 203} },
    { floor = 57, firstGold = 7985000, sweepGold = 3992500, monsterLevel = 171, monsters = {201, 202, 203} },
    { floor = 58, firstGold = 8270000, sweepGold = 4135000, monsterLevel = 174, monsters = {201, 202, 203} },
    { floor = 59, firstGold = 8560000, sweepGold = 4280000, monsterLevel = 177, monsters = {201, 202, 203} },
    { floor = 60, firstGold = 8855000, sweepGold = 4427500, monsterLevel = 180, monsters = {201, 202, 203} },
    { floor = 61, firstGold = 9155000, sweepGold = 4577500, monsterLevel = 183, monsters = {201, 202, 203} },
    { floor = 62, firstGold = 9460000, sweepGold = 4730000, monsterLevel = 186, monsters = {201, 202, 203} },
    { floor = 63, firstGold = 9770000, sweepGold = 4885000, monsterLevel = 189, monsters = {201, 202, 203} },
    { floor = 64, firstGold = 10085000, sweepGold = 5042500, monsterLevel = 192, monsters = {201, 202, 203} },
    { floor = 65, firstGold = 10405000, sweepGold = 5202500, monsterLevel = 195, monsters = {201, 202, 203} },
    { floor = 66, firstGold = 10730000, sweepGold = 5365000, monsterLevel = 198, monsters = {201, 202, 203} },
    { floor = 67, firstGold = 11060000, sweepGold = 5530000, monsterLevel = 201, monsters = {201, 202, 203} },
    { floor = 68, firstGold = 11395000, sweepGold = 5697500, monsterLevel = 204, monsters = {201, 202, 203} },
    { floor = 69, firstGold = 11735000, sweepGold = 5867500, monsterLevel = 207, monsters = {201, 202, 203} },
    { floor = 70, firstGold = 12080000, sweepGold = 6040000, monsterLevel = 210, monsters = {201, 202, 203} },
    { floor = 71, firstGold = 12430000, sweepGold = 6215000, monsterLevel = 213, monsters = {201, 202, 203} },
    { floor = 72, firstGold = 12785000, sweepGold = 6392500, monsterLevel = 216, monsters = {201, 202, 203} },
    { floor = 73, firstGold = 13145000, sweepGold = 6572500, monsterLevel = 219, monsters = {201, 202, 203} },
    { floor = 74, firstGold = 13510000, sweepGold = 6755000, monsterLevel = 222, monsters = {201, 202, 203} },
    { floor = 75, firstGold = 13880000, sweepGold = 6940000, monsterLevel = 225, monsters = {201, 202, 203} },
    { floor = 76, firstGold = 14255000, sweepGold = 7127500, monsterLevel = 228, monsters = {201, 202, 203} },
    { floor = 77, firstGold = 14635000, sweepGold = 7317500, monsterLevel = 231, monsters = {201, 202, 203} },
    { floor = 78, firstGold = 15020000, sweepGold = 7510000, monsterLevel = 234, monsters = {201, 202, 203} },
    { floor = 79, firstGold = 15410000, sweepGold = 7705000, monsterLevel = 237, monsters = {201, 202, 203} },
    { floor = 80, firstGold = 15805000, sweepGold = 7902500, monsterLevel = 240, monsters = {201, 202, 203} },
    { floor = 81, firstGold = 16205000, sweepGold = 8102500, monsterLevel = 243, monsters = {201, 202, 203} },
    { floor = 82, firstGold = 16610000, sweepGold = 8305000, monsterLevel = 246, monsters = {201, 202, 203} },
    { floor = 83, firstGold = 17020000, sweepGold = 8510000, monsterLevel = 249, monsters = {201, 202, 203} },
    { floor = 84, firstGold = 17430000, sweepGold = 8715000, monsterLevel = 252, monsters = {201, 202, 203} },
    { floor = 85, firstGold = 17840000, sweepGold = 8920000, monsterLevel = 255, monsters = {201, 202, 203} },
    { floor = 86, firstGold = 18250000, sweepGold = 9125000, monsterLevel = 258, monsters = {201, 202, 203} },
    { floor = 87, firstGold = 18660000, sweepGold = 9330000, monsterLevel = 261, monsters = {201, 202, 203} },
    { floor = 88, firstGold = 19070000, sweepGold = 9535000, monsterLevel = 264, monsters = {201, 202, 203} },
    { floor = 89, firstGold = 19480000, sweepGold = 9740000, monsterLevel = 267, monsters = {201, 202, 203} },
    { floor = 90, firstGold = 19890000, sweepGold = 9945000, monsterLevel = 270, monsters = {201, 202, 203} },
    { floor = 91, firstGold = 20300000, sweepGold = 10150000, monsterLevel = 273, monsters = {201, 202, 203} },
    { floor = 92, firstGold = 20710000, sweepGold = 10355000, monsterLevel = 276, monsters = {201, 202, 203} },
    { floor = 93, firstGold = 21120000, sweepGold = 10560000, monsterLevel = 279, monsters = {201, 202, 203} },
    { floor = 94, firstGold = 21530000, sweepGold = 10765000, monsterLevel = 282, monsters = {201, 202, 203} },
    { floor = 95, firstGold = 21940000, sweepGold = 10970000, monsterLevel = 285, monsters = {201, 202, 203} },
    { floor = 96, firstGold = 22350000, sweepGold = 11175000, monsterLevel = 288, monsters = {201, 202, 203} },
    { floor = 97, firstGold = 22760000, sweepGold = 11380000, monsterLevel = 291, monsters = {201, 202, 203} },
    { floor = 98, firstGold = 23170000, sweepGold = 11585000, monsterLevel = 294, monsters = {201, 202, 203} },
    { floor = 99, firstGold = 23580000, sweepGold = 11790000, monsterLevel = 297, monsters = {201, 202, 203} },
    { floor = 100, firstGold = 23990000, sweepGold = 11995000, monsterLevel = 300, monsters = {201, 202, 203} },
    { floor = 101, firstGold = 24400000,  sweepGold = 12200000,  monsterLevel = 303, monsters = {201, 202, 203} },
    { floor = 102, firstGold = 24810000,  sweepGold = 12405000,  monsterLevel = 306, monsters = {201, 202, 203} },
    { floor = 103, firstGold = 25220000,  sweepGold = 12610000,  monsterLevel = 309, monsters = {201, 202, 203} },
    { floor = 104, firstGold = 25630000,  sweepGold = 12815000,  monsterLevel = 312, monsters = {201, 202, 203} },
    { floor = 105, firstGold = 26040000,  sweepGold = 13020000,  monsterLevel = 315, monsters = {201, 202, 203} },
    { floor = 106, firstGold = 26450000,  sweepGold = 13225000,  monsterLevel = 318, monsters = {201, 202, 203} },
    { floor = 107, firstGold = 26860000,  sweepGold = 13430000,  monsterLevel = 321, monsters = {201, 202, 203} },
    { floor = 108, firstGold = 27270000,  sweepGold = 13635000,  monsterLevel = 324, monsters = {201, 202, 203} },
    { floor = 109, firstGold = 27680000,  sweepGold = 13840000,  monsterLevel = 327, monsters = {201, 202, 203} },
    { floor = 110, firstGold = 28090000,  sweepGold = 14045000,  monsterLevel = 330, monsters = {201, 202, 203} },
    { floor = 111, firstGold = 28500000,  sweepGold = 14250000,  monsterLevel = 333, monsters = {201, 202, 203} },
    { floor = 112, firstGold = 28910000,  sweepGold = 14455000,  monsterLevel = 336, monsters = {201, 202, 203} },
    { floor = 113, firstGold = 29320000,  sweepGold = 14660000,  monsterLevel = 339, monsters = {201, 202, 203} },
    { floor = 114, firstGold = 29730000,  sweepGold = 14865000,  monsterLevel = 342, monsters = {201, 202, 203} },
    { floor = 115, firstGold = 30140000,  sweepGold = 15070000,  monsterLevel = 345, monsters = {201, 202, 203} },
}

--- 上古遗迹 - 109层配置
---@type table[]
DungeonConfig.ANCIENT_RUIN = {
    { floor = 1,  firstDust = 200,  sweepDust = 100,  monsterLevel = 20,  monsters = {204, 205, 206} },
    { floor = 2,  firstDust = 300,  sweepDust = 150,  monsterLevel = 23,  monsters = {204, 205, 206} },
    { floor = 3,  firstDust = 400,  sweepDust = 200,  monsterLevel = 26,  monsters = {204, 205, 206} },
    { floor = 4,  firstDust = 500,  sweepDust = 250,  monsterLevel = 29,  monsters = {204, 205, 206} },
    { floor = 5,  firstDust = 600,  sweepDust = 300,  monsterLevel = 32,  monsters = {204, 205, 206} },
    { floor = 6,  firstDust = 700,  sweepDust = 350,  monsterLevel = 35,  monsters = {204, 205, 206} },
    { floor = 7,  firstDust = 800,  sweepDust = 400,  monsterLevel = 38,  monsters = {204, 205, 206} },
    { floor = 8,  firstDust = 900,  sweepDust = 450,  monsterLevel = 41,  monsters = {204, 205, 206} },
    { floor = 9,  firstDust = 1000, sweepDust = 500,  monsterLevel = 44,  monsters = {204, 205, 206} },
    { floor = 10, firstDust = 1100, sweepDust = 550,  monsterLevel = 47,  monsters = {204, 205, 206} },
    { floor = 11, firstDust = 1200, sweepDust = 600,  monsterLevel = 50,  monsters = {204, 205, 206} },
    { floor = 12, firstDust = 1300, sweepDust = 650,  monsterLevel = 53,  monsters = {204, 205, 206} },
    { floor = 13, firstDust = 1400, sweepDust = 700,  monsterLevel = 56,  monsters = {204, 205, 206} },
    { floor = 14, firstDust = 1500, sweepDust = 750,  monsterLevel = 59,  monsters = {204, 205, 206} },
    { floor = 15, firstDust = 1600, sweepDust = 800,  monsterLevel = 62,  monsters = {204, 205, 206} },
    { floor = 16, firstDust = 1700, sweepDust = 850,  monsterLevel = 65,  monsters = {204, 205, 206} },
    { floor = 17, firstDust = 1800, sweepDust = 900,  monsterLevel = 68,  monsters = {204, 205, 206} },
    { floor = 18, firstDust = 1900, sweepDust = 950,  monsterLevel = 71,  monsters = {204, 205, 206} },
    { floor = 19, firstDust = 2000, sweepDust = 1000, monsterLevel = 74,  monsters = {204, 205, 206} },
    { floor = 20, firstDust = 2100, sweepDust = 1050, monsterLevel = 77,  monsters = {204, 205, 206} },
    { floor = 21, firstDust = 2200, sweepDust = 1100, monsterLevel = 80,  monsters = {204, 205, 206} },
    { floor = 22, firstDust = 2300, sweepDust = 1150, monsterLevel = 83,  monsters = {204, 205, 206} },
    { floor = 23, firstDust = 2400, sweepDust = 1200, monsterLevel = 86,  monsters = {204, 205, 206} },
    { floor = 24, firstDust = 2500, sweepDust = 1250, monsterLevel = 89,  monsters = {204, 205, 206} },
    { floor = 25, firstDust = 2600, sweepDust = 1300, monsterLevel = 92,  monsters = {204, 205, 206} },
    { floor = 26, firstDust = 2700, sweepDust = 1350, monsterLevel = 95,  monsters = {204, 205, 206} },
    { floor = 27, firstDust = 2800, sweepDust = 1400, monsterLevel = 98,  monsters = {204, 205, 206} },
    { floor = 28, firstDust = 2900, sweepDust = 1450, monsterLevel = 101, monsters = {204, 205, 206} },
    { floor = 29, firstDust = 3000, sweepDust = 1500, monsterLevel = 104, monsters = {204, 205, 206} },
    { floor = 30, firstDust = 3100, sweepDust = 1550, monsterLevel = 107, monsters = {204, 205, 206} },
    { floor = 31, firstDust = 3200, sweepDust = 1600, monsterLevel = 110, monsters = {204, 205, 206} },
    { floor = 32, firstDust = 3300, sweepDust = 1650, monsterLevel = 113, monsters = {204, 205, 206} },
    { floor = 33, firstDust = 3400, sweepDust = 1700, monsterLevel = 116, monsters = {204, 205, 206} },
    { floor = 34, firstDust = 3500, sweepDust = 1750, monsterLevel = 119, monsters = {204, 205, 206} },
    { floor = 35, firstDust = 3600, sweepDust = 1800, monsterLevel = 122, monsters = {204, 205, 206} },
    { floor = 36, firstDust = 3700, sweepDust = 1850, monsterLevel = 125, monsters = {204, 205, 206} },
    { floor = 37, firstDust = 3800, sweepDust = 1900, monsterLevel = 128, monsters = {204, 205, 206} },
    { floor = 38, firstDust = 3900, sweepDust = 1950, monsterLevel = 131, monsters = {204, 205, 206} },
    { floor = 39, firstDust = 4000, sweepDust = 2000, monsterLevel = 134, monsters = {204, 205, 206} },
    { floor = 40, firstDust = 4100, sweepDust = 2050, monsterLevel = 137, monsters = {204, 205, 206} },
    { floor = 41, firstDust = 4200, sweepDust = 2100, monsterLevel = 140, monsters = {204, 205, 206} },
    { floor = 42, firstDust = 4300, sweepDust = 2150, monsterLevel = 143, monsters = {204, 205, 206} },
    { floor = 43, firstDust = 4400, sweepDust = 2200, monsterLevel = 146, monsters = {204, 205, 206} },
    { floor = 44, firstDust = 4500, sweepDust = 2250, monsterLevel = 149, monsters = {204, 205, 206} },
    { floor = 45, firstDust = 4600, sweepDust = 2300, monsterLevel = 152, monsters = {204, 205, 206} },
    { floor = 46, firstDust = 4700, sweepDust = 2350, monsterLevel = 155, monsters = {204, 205, 206} },
    { floor = 47, firstDust = 4800, sweepDust = 2400, monsterLevel = 158, monsters = {204, 205, 206} },
    { floor = 48, firstDust = 4900, sweepDust = 2450, monsterLevel = 161, monsters = {204, 205, 206} },
    { floor = 49, firstDust = 5000, sweepDust = 2500, monsterLevel = 164, monsters = {204, 205, 206} },
    { floor = 50, firstDust = 5100, sweepDust = 2550, monsterLevel = 167, monsters = {204, 205, 206} },
    { floor = 51, firstDust = 5200, sweepDust = 2600, monsterLevel = 170, monsters = {204, 205, 206} },
    { floor = 52, firstDust = 5300, sweepDust = 2650, monsterLevel = 173, monsters = {204, 205, 206} },
    { floor = 53, firstDust = 5400, sweepDust = 2700, monsterLevel = 176, monsters = {204, 205, 206} },
    { floor = 54, firstDust = 5500, sweepDust = 2750, monsterLevel = 179, monsters = {204, 205, 206} },
    { floor = 55, firstDust = 5600, sweepDust = 2800, monsterLevel = 182, monsters = {204, 205, 206} },
    { floor = 56, firstDust = 5700, sweepDust = 2850, monsterLevel = 185, monsters = {204, 205, 206} },
    { floor = 57, firstDust = 5800, sweepDust = 2900, monsterLevel = 188, monsters = {204, 205, 206} },
    { floor = 58, firstDust = 5900, sweepDust = 2950, monsterLevel = 191, monsters = {204, 205, 206} },
    { floor = 59, firstDust = 6000, sweepDust = 3000, monsterLevel = 194, monsters = {204, 205, 206} },
    { floor = 60, firstDust = 6100, sweepDust = 3050, monsterLevel = 197, monsters = {204, 205, 206} },
    { floor = 61, firstDust = 6200, sweepDust = 3100, monsterLevel = 200, monsters = {204, 205, 206} },
    { floor = 62, firstDust = 6300, sweepDust = 3150, monsterLevel = 203, monsters = {204, 205, 206} },
    { floor = 63, firstDust = 6400, sweepDust = 3200, monsterLevel = 206, monsters = {204, 205, 206} },
    { floor = 64, firstDust = 6500, sweepDust = 3250, monsterLevel = 209, monsters = {204, 205, 206} },
    { floor = 65, firstDust = 6600, sweepDust = 3300, monsterLevel = 212, monsters = {204, 205, 206} },
    { floor = 66, firstDust = 6700, sweepDust = 3350, monsterLevel = 215, monsters = {204, 205, 206} },
    { floor = 67, firstDust = 6800, sweepDust = 3400, monsterLevel = 218, monsters = {204, 205, 206} },
    { floor = 68, firstDust = 6900, sweepDust = 3450, monsterLevel = 221, monsters = {204, 205, 206} },
    { floor = 69, firstDust = 7000, sweepDust = 3500, monsterLevel = 224, monsters = {204, 205, 206} },
    { floor = 70, firstDust = 7100, sweepDust = 3550, monsterLevel = 227, monsters = {204, 205, 206} },
    { floor = 71, firstDust = 7200, sweepDust = 3600, monsterLevel = 230, monsters = {204, 205, 206} },
    { floor = 72, firstDust = 7300, sweepDust = 3650, monsterLevel = 233, monsters = {204, 205, 206} },
    { floor = 73, firstDust = 7400, sweepDust = 3700, monsterLevel = 236, monsters = {204, 205, 206} },
    { floor = 74, firstDust = 7500, sweepDust = 3750, monsterLevel = 239, monsters = {204, 205, 206} },
    { floor = 75, firstDust = 7600, sweepDust = 3800, monsterLevel = 242, monsters = {204, 205, 206} },
    { floor = 76, firstDust = 7700, sweepDust = 3850, monsterLevel = 245, monsters = {204, 205, 206} },
    { floor = 77, firstDust = 7800, sweepDust = 3900, monsterLevel = 248, monsters = {204, 205, 206} },
    { floor = 78, firstDust = 7900, sweepDust = 3950, monsterLevel = 251, monsters = {204, 205, 206} },
    { floor = 79, firstDust = 8000, sweepDust = 4000, monsterLevel = 254, monsters = {204, 205, 206} },
    { floor = 80, firstDust = 8100, sweepDust = 4050, monsterLevel = 257, monsters = {204, 205, 206} },
    { floor = 81, firstDust = 8200, sweepDust = 4100, monsterLevel = 260, monsters = {204, 205, 206} },
    { floor = 82, firstDust = 8300, sweepDust = 4150, monsterLevel = 263, monsters = {204, 205, 206} },
    { floor = 83, firstDust = 8400, sweepDust = 4200, monsterLevel = 266, monsters = {204, 205, 206} },
    { floor = 84, firstDust = 8500, sweepDust = 4250, monsterLevel = 269, monsters = {204, 205, 206} },
    { floor = 85, firstDust = 8600, sweepDust = 4300, monsterLevel = 272, monsters = {204, 205, 206} },
    { floor = 86, firstDust = 8700, sweepDust = 4350, monsterLevel = 275, monsters = {204, 205, 206} },
    { floor = 87, firstDust = 8800, sweepDust = 4400, monsterLevel = 278, monsters = {204, 205, 206} },
    { floor = 88, firstDust = 8900, sweepDust = 4450, monsterLevel = 281, monsters = {204, 205, 206} },
    { floor = 89, firstDust = 9000, sweepDust = 4500, monsterLevel = 284, monsters = {204, 205, 206} },
    { floor = 90, firstDust = 9100, sweepDust = 4550, monsterLevel = 287, monsters = {204, 205, 206} },
    { floor = 91, firstDust = 9200, sweepDust = 4600, monsterLevel = 290, monsters = {204, 205, 206} },
    { floor = 92, firstDust = 9300, sweepDust = 4650, monsterLevel = 293, monsters = {204, 205, 206} },
    { floor = 93, firstDust = 9400, sweepDust = 4700, monsterLevel = 296, monsters = {204, 205, 206} },
    { floor = 94, firstDust = 9500, sweepDust = 4750, monsterLevel = 299, monsters = {204, 205, 206} },
    { floor = 95, firstDust = 9600, sweepDust = 4800, monsterLevel = 300, monsters = {204, 205, 206} },
    { floor = 96,  firstDust = 9700, sweepDust = 4850, monsterLevel = 303, monsters = {204, 205, 206} },
    { floor = 97,  firstDust = 9800, sweepDust = 4900, monsterLevel = 306, monsters = {204, 205, 206} },
    { floor = 98,  firstDust = 9900, sweepDust = 4950, monsterLevel = 309, monsters = {204, 205, 206} },
    { floor = 99,  firstDust = 10000, sweepDust = 5000, monsterLevel = 312, monsters = {204, 205, 206} },
    { floor = 100, firstDust = 10100, sweepDust = 5050, monsterLevel = 315, monsters = {204, 205, 206} },
    { floor = 101, firstDust = 10200, sweepDust = 5100, monsterLevel = 318, monsters = {204, 205, 206} },
    { floor = 102, firstDust = 10300, sweepDust = 5150, monsterLevel = 321, monsters = {204, 205, 206} },
    { floor = 103, firstDust = 10400, sweepDust = 5200, monsterLevel = 324, monsters = {204, 205, 206} },
    { floor = 104, firstDust = 10500, sweepDust = 5250, monsterLevel = 327, monsters = {204, 205, 206} },
    { floor = 105, firstDust = 10600, sweepDust = 5300, monsterLevel = 330, monsters = {204, 205, 206} },
    { floor = 106, firstDust = 10700, sweepDust = 5350, monsterLevel = 333, monsters = {204, 205, 206} },
    { floor = 107, firstDust = 10800, sweepDust = 5400, monsterLevel = 336, monsters = {204, 205, 206} },
    { floor = 108, firstDust = 10900, sweepDust = 5450, monsterLevel = 339, monsters = {204, 205, 206} },
    { floor = 109, firstDust = 11000, sweepDust = 5500, monsterLevel = 342, monsters = {204, 205, 206} },
}

--- 每日扫荡上限
DungeonConfig.DAILY_SWEEP_LIMIT = {
    gold_mine    = 2,
    ancient_ruin = 2,
}

--- 副本总层数
DungeonConfig.MAX_FLOOR = {
    gold_mine    = 115,
    ancient_ruin = 109,
}

-- ======================== 查询接口 ========================

--- 获取黄金矿洞指定层配置
---@param floor number 层数 (1~115)
---@return table|nil 层数据
function DungeonConfig.getGoldMineFloor(floor)
    local maxFloor = DungeonConfig.MAX_FLOOR.gold_mine
    if floor < 1 or floor > maxFloor then return nil end
    return DungeonConfig.GOLD_MINE[floor]
end

--- 获取上古遗迹指定层配置
---@param floor number 层数 (1~109)
---@return table|nil 层数据
function DungeonConfig.getAncientRuinFloor(floor)
    local maxFloor = DungeonConfig.MAX_FLOOR.ancient_ruin
    if floor < 1 or floor > maxFloor then return nil end
    return DungeonConfig.ANCIENT_RUIN[floor]
end

--- 获取指定层的扫荡金币奖励
---@param floor number
---@return number
function DungeonConfig.getSweepGold(floor)
    local data = DungeonConfig.getGoldMineFloor(floor)
    if not data then return 0 end
    return data.sweepGold
end

--- 获取指定层的首通金币奖励
---@param floor number
---@return number
function DungeonConfig.getFirstClearGold(floor)
    local data = DungeonConfig.getGoldMineFloor(floor)
    if not data then return 0 end
    return data.firstGold
end

-- ======================== 三类资源副本 ========================

local StageConfig = require("config.StageConfig")

DungeonConfig.RESOURCE_IDS = { "gold_mine", "equipment_vault", "black_diamond" }
DungeonConfig.EXTRA_ENEMIES = 2
DungeonConfig.DEFINITIONS = {
    gold_mine = {
        name = "金币副本", unlockStage = 305, maxFloor = 115,
        cardImage = "image/战斗背景/金币副本.png",
        rewardType = "gold", rewardIcon = "image/货币道具/UI_icon_JB_X.png", quality = 2,
    },
    equipment_vault = {
        name = "装备副本", unlockStage = 1305, maxFloor = 109,
        cardImage = "image/战斗背景/装备副本.png",
        rewardType = "equip", rewardIcon = "image/货币道具/UI_icon_FBBX.png", quality = 4,
    },
    black_diamond = {
        name = "黑钻副本", unlockStage = 605, maxFloor = 115,
        cardImage = "image/战斗背景/黑钻副本.png",
        rewardType = "diamond", rewardIcon = "image/货币道具/UI_icon_SJ_X.png", quality = 5,
    },
}
for _, id in ipairs(DungeonConfig.RESOURCE_IDS) do
    local def = DungeonConfig.DEFINITIONS[id]
    DungeonConfig.UNLOCK_CONDITIONS[id] = def.unlockStage
    DungeonConfig.MAX_FLOOR[id] = def.maxFloor
    DungeonConfig.DAILY_SWEEP_LIMIT[id] = 2
end

function DungeonConfig.isResourceDungeon(id)
    return DungeonConfig.DEFINITIONS[id] ~= nil
end

-- 各层沿主线普通关卡顺序前进，跳过终焉神殿，不把副本写进主线关卡链。
local sourceStages = {} ---@type table<string, number[]>
local sourceEnemyCounts = {} ---@type table<string, number[]>
local function getSourceStage(id, floor)
    local def = DungeonConfig.DEFINITIONS[id]
    if not def then return nil end
    if not sourceStages[id] then
        local ids, counts = {}, {}
        local highestCount = 0
        ---@type number|nil
        local stageId = def.unlockStage
        while #ids < def.maxFloor and stageId do
            if not StageConfig.isTerminalTemple(stageId) then
                local source = StageConfig.getStage(stageId)
                highestCount = math.max(highestCount, source.firstCount or source.idleCount or 4)
                ids[#ids + 1] = stageId
                counts[#ids] = highestCount
            end
            local nextId = StageConfig.getNextStageId(stageId)
            if not nextId and StageConfig.isTerminalTemple(stageId) then
                nextId = StageConfig.getReincarnationTarget(StageConfig.getDifficulty(stageId))
            end
            stageId = nextId
        end
        sourceStages[id] = ids
        sourceEnemyCounts[id] = counts
    end
    return StageConfig.getStage(sourceStages[id][floor])
end

--- 资源副本与预览共用的完整主线型出怪配置；复制后修改，不污染 StageConfig。
---@return table|nil
function DungeonConfig.getCombatEntry(id, floor)
    floor = math.tointeger(tonumber(floor) or 0)
    local def = DungeonConfig.DEFINITIONS[id]
    if not def or not floor or floor < 1 or floor > def.maxFloor then return nil end
    local source = getSourceStage(id, floor)
    if not source then return nil end
    ---@type table<string, any>
    local entry = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            local copy = {}
            for k, v in pairs(value) do copy[k] = v end
            entry[key] = copy
        else
            entry[key] = value
        end
    end
    -- 首层只借下一层的普通怪池，起点/等级/数量/奖励仍沿用解锁关卡。
    if floor == 1 then
        local normalSource = getSourceStage(id, 2)
        if not normalSource then return nil end
        entry.monsters = {}
        for k, v in pairs(normalSource.monsters) do entry.monsters[k] = v end
        entry.bossId = 0 -- 出怪器直接比较 > 0，不能设 nil。
        entry.firstClearBonusMonster, entry.firstClearBonusMonsters = nil, nil
    end
    entry.name = def.name
    -- 资源连续关不应在借用主线下一章首关时从28/32名敌人骤降至12名。
    entry.firstCount = sourceEnemyCounts[id][floor] + DungeonConfig.EXTRA_ENEMIES
    entry.idleCount = entry.firstCount
    entry.firstClearBonusMonster, entry.firstClearBonusMonsters = nil, nil
    entry.maxFieldEnemies = 4
    entry.mode = "resource_dungeon"
    entry.dropRate, entry.scrollDropRate = 0, 0
    entry.fcGold, entry.fcExp, entry.fcDiamond, entry.fcEssence = 0, 0, 0, 0
    entry.fcArcaneDust, entry.fcEquip, entry.fcScroll = 0, 0, 0
    return entry
end

--- 获取层配置，旧遗迹仍能按原规则结清旧数据，不挪用为新装备副本。
---@return table|nil
function DungeonConfig.getFloor(id, floor)
    floor = math.tointeger(tonumber(floor) or 0)
    if not floor or floor < 1 or floor > (DungeonConfig.MAX_FLOOR[id] or 0) then return nil end
    if id == "ancient_ruin" then return DungeonConfig.getAncientRuinFloor(floor) end
    local combat = DungeonConfig.getCombatEntry(id, floor)
    if not combat then return nil end
    local result = { floor = floor, monsterLevel = combat.monsterLevel, monsters = combat.monsters }
    if id == "gold_mine" then
        local old = DungeonConfig.getGoldMineFloor(floor)
        if not old then return nil end
        result.firstGold, result.sweepGold = old.firstGold, old.sweepGold
    elseif id == "equipment_vault" then
        local cap = StageConfig.getMaxDropQuality(combat)
        result.firstEquip, result.sweepEquip = 6, 3
        result.equipLevel = combat.monsterLevel
        result.equipMinQuality, result.equipMaxQuality = math.min(3, cap), cap
    elseif id == "black_diamond" then
        result.firstDiamond = 150 + (floor - 1) * 50
        result.sweepDiamond = math.floor(result.firstDiamond / 2)
    end
    return result
end

--- 含终层的最高已通层；旧档没有账本时沿用 floor-1。
function DungeonConfig.getHighestClearedFloor(sub, id)
    local maxFloor = DungeonConfig.MAX_FLOOR[id] or 0
    local highest = math.min(maxFloor, math.max(0, math.floor(tonumber(sub and sub.floor) or 1) - 1))
    for key, cleared in pairs(sub and sub.cleared or {}) do
        local floor = math.tointeger(tonumber(key) or 0)
        if cleared == true and floor and floor > highest and floor <= maxFloor then highest = floor end
    end
    return highest
end

-- 资源关卡使用独立ID；只记录队伍位置，不进入主线进度链。
local RESOURCE_STAGE_BASE = { gold_mine = 100000, equipment_vault = 200000, black_diamond = 300000 }
local resourceStages = {}

function DungeonConfig.getStageId(id, floor)
    local base = RESOURCE_STAGE_BASE[id]
    local level = math.tointeger(tonumber(floor) or 0)
    if not base or not level or level < 1 or level > (DungeonConfig.MAX_FLOOR[id] or 0) then return nil end
    return base + level
end

function DungeonConfig.decodeStageId(stageId)
    local value = math.tointeger(tonumber(stageId) or 0)
    if not value then return nil end
    for id, base in pairs(RESOURCE_STAGE_BASE) do
        local floor = value - base
        if floor >= 1 and floor <= DungeonConfig.MAX_FLOOR[id] then return id, floor end
    end
    return nil
end

function DungeonConfig.getStage(stageId)
    local id, floor = DungeonConfig.decodeStageId(stageId)
    if not id then return nil end
    if resourceStages[stageId] then return resourceStages[stageId] end
    local entry = DungeonConfig.getCombatEntry(id, floor)
    if not entry then return nil end
    entry.sourceStageId = entry.id
    entry.id = stageId
    entry.resourceDungeonId, entry.resourceFloor = id, floor
    entry.displayChapter = 1
    entry.stage = floor
    entry.name = DungeonConfig.DEFINITIONS[id].name .. " " .. entry.displayChapter .. "-" .. entry.stage
    entry.firstClearBonusMonster, entry.firstClearBonusMonsters = nil, nil
    entry.mapBg = DungeonConfig.DEFINITIONS[id].cardImage
    resourceStages[stageId] = entry
    return entry
end

function DungeonConfig.isStageUnlocked(stageId, battleData, dungeonData)
    local id, floor = DungeonConfig.decodeStageId(stageId)
    if not id then return false end
    local def = DungeonConfig.DEFINITIONS[id]
    local maxId = tonumber(battleData and battleData.maxStageId) or 0
    local previous = StageConfig.getTerminalPrevStageId(maxId)
    local maxRank = previous and previous + 0.5 or maxId
    if maxRank < def.unlockStage then return false end
    local sub = type(dungeonData) == "table" and dungeonData[id] or nil
    return floor <= math.min(def.maxFloor, DungeonConfig.getHighestClearedFloor(sub, id) + 1)
end

-- 只读期望数量，与真实逐杀结算共用效率；不骰奖励、不生成装备。
function DungeonConfig.getStageRewardAmount(stageId, kills)
    local id, floor = DungeonConfig.decodeStageId(stageId)
    if not id or (tonumber(kills) or 0) <= 0 then return 0 end
    local idle = require("config.DungeonIdleConfig")
    local rate = idle.getIdlePerMin(id, floor)
    local perMinute = id == "equipment_vault" and rate or rate * idle.REWARD_MULT
    return math.max(0, kills) * perMinute / 20 -- 每3秒1只，即每分钟20只。
end

-- 在线每次击杀与离线固定杀怪效率复用原每分钟收益，不把一次扫荡变为无限波大奖。
function DungeonConfig.getStageRewards(stageId, kills)
    local id, floor = DungeonConfig.decodeStageId(stageId)
    local rewards = { gold = 0, diamond = 0, adventureExp = 0, adventurerExp = 0, equipSeeds = {}, scrollDrops = {} }
    if not id or (tonumber(kills) or 0) <= 0 then return rewards end
    local raw = DungeonConfig.getStageRewardAmount(stageId, kills)
    local amount = math.floor(raw)
    if math.random() < raw - amount then amount = amount + 1 end
    if id == "gold_mine" then rewards.gold = amount
    elseif id == "black_diamond" then rewards.diamond = amount
    elseif amount > 0 then
        local data = DungeonConfig.getFloor(id, floor)
        for _ = 1, amount do
            rewards.equipSeeds[#rewards.equipSeeds + 1] = {
                stageId = stageId, count = 1, level = data.equipLevel,
                quality = math.random(data.equipMinQuality, data.equipMaxQuality),
            }
        end
    end
    return rewards
end


return DungeonConfig
