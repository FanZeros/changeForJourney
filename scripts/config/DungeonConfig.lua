-- ============================================================================
-- DungeonConfig - 副本配置数据
-- 职责: 定义所有副本的层数、奖励、怪物、增益等静态数据
-- ============================================================================

local DungeonConfig = {}

-- ======================== 职业增益循环 ========================

--- 职业增益类型（每5层循环: 战士→法师→射手→刺客→牧师）
DungeonConfig.CLASS_BONUS_CYCLE = {
    "warrior",   -- 1, 6, 11, 16, 21, 26, 31
    "mage",      -- 2, 7, 12, 17, 22, 27, 32
    "archer",    -- 3, 8, 13, 18, 23, 28, 33
    "assassin",  -- 4, 9, 14, 19, 24, 29, 34
    "priest",    -- 5, 10, 15, 20, 25, 30, 35
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
--- qualityWeights: {品质1比重, 品质2比重, 品质3比重, 品质4比重} 总和=100
---@type table[]
DungeonConfig.ANCIENT_RUIN = {
    { floor = 1,  firstDust = 200,  sweepDust = 100,  firstRelicCount = 3, sweepRelicCount = 1, qualityWeights = {83,15,2,0},   monsterLevel = 20,  monsters = {204, 205, 206} },
    { floor = 2,  firstDust = 300,  sweepDust = 150,  firstRelicCount = 3, sweepRelicCount = 1, qualityWeights = {80,17,3,0},   monsterLevel = 23,  monsters = {204, 205, 206} },
    { floor = 3,  firstDust = 400,  sweepDust = 200,  firstRelicCount = 3, sweepRelicCount = 1, qualityWeights = {78,18,4,0},   monsterLevel = 26,  monsters = {204, 205, 206} },
    { floor = 4,  firstDust = 500,  sweepDust = 250,  firstRelicCount = 3, sweepRelicCount = 1, qualityWeights = {75,20,5,0},   monsterLevel = 29,  monsters = {204, 205, 206} },
    { floor = 5,  firstDust = 600,  sweepDust = 300,  firstRelicCount = 3, sweepRelicCount = 1, qualityWeights = {72,22,6,0},   monsterLevel = 32,  monsters = {204, 205, 206} },
    { floor = 6,  firstDust = 700,  sweepDust = 350,  firstRelicCount = 3, sweepRelicCount = 1, qualityWeights = {70,23,7,0},   monsterLevel = 35,  monsters = {204, 205, 206} },
    { floor = 7,  firstDust = 800,  sweepDust = 400,  firstRelicCount = 3, sweepRelicCount = 1, qualityWeights = {67,25,8,0},   monsterLevel = 38,  monsters = {204, 205, 206} },
    { floor = 8,  firstDust = 900,  sweepDust = 450,  firstRelicCount = 4, sweepRelicCount = 2, qualityWeights = {64,27,9,0},   monsterLevel = 41,  monsters = {204, 205, 206} },
    { floor = 9,  firstDust = 1000, sweepDust = 500,  firstRelicCount = 4, sweepRelicCount = 2, qualityWeights = {62,28,10,0},  monsterLevel = 44,  monsters = {204, 205, 206} },
    { floor = 10, firstDust = 1100, sweepDust = 550,  firstRelicCount = 4, sweepRelicCount = 2, qualityWeights = {59,30,11,0},  monsterLevel = 47,  monsters = {204, 205, 206} },
    { floor = 11, firstDust = 1200, sweepDust = 600,  firstRelicCount = 4, sweepRelicCount = 2, qualityWeights = {56,32,12,0},  monsterLevel = 50,  monsters = {204, 205, 206} },
    { floor = 12, firstDust = 1300, sweepDust = 650,  firstRelicCount = 4, sweepRelicCount = 2, qualityWeights = {54,33,13,0},  monsterLevel = 53,  monsters = {204, 205, 206} },
    { floor = 13, firstDust = 1400, sweepDust = 700,  firstRelicCount = 4, sweepRelicCount = 2, qualityWeights = {51,35,14,0},  monsterLevel = 56,  monsters = {204, 205, 206} },
    { floor = 14, firstDust = 1500, sweepDust = 750,  firstRelicCount = 4, sweepRelicCount = 2, qualityWeights = {48,36,15,1},  monsterLevel = 59,  monsters = {204, 205, 206} },
    { floor = 15, firstDust = 1600, sweepDust = 800,  firstRelicCount = 5, sweepRelicCount = 2, qualityWeights = {46,37,16,1},  monsterLevel = 62,  monsters = {204, 205, 206} },
    { floor = 16, firstDust = 1700, sweepDust = 850,  firstRelicCount = 5, sweepRelicCount = 2, qualityWeights = {43,38,17,2},  monsterLevel = 65,  monsters = {204, 205, 206} },
    { floor = 17, firstDust = 1800, sweepDust = 900,  firstRelicCount = 5, sweepRelicCount = 2, qualityWeights = {40,39,18,3},  monsterLevel = 68,  monsters = {204, 205, 206} },
    { floor = 18, firstDust = 1900, sweepDust = 950,  firstRelicCount = 5, sweepRelicCount = 2, qualityWeights = {38,40,18,4},  monsterLevel = 71,  monsters = {204, 205, 206} },
    { floor = 19, firstDust = 2000, sweepDust = 1000, firstRelicCount = 5, sweepRelicCount = 2, qualityWeights = {35,40,20,5},  monsterLevel = 74,  monsters = {204, 205, 206} },
    { floor = 20, firstDust = 2100, sweepDust = 1050, firstRelicCount = 5, sweepRelicCount = 3, qualityWeights = {32,40,21,7},  monsterLevel = 77,  monsters = {204, 205, 206} },
    { floor = 21, firstDust = 2200, sweepDust = 1100, firstRelicCount = 5, sweepRelicCount = 3, qualityWeights = {30,40,22,8},  monsterLevel = 80,  monsters = {204, 205, 206} },
    { floor = 22, firstDust = 2300, sweepDust = 1150, firstRelicCount = 5, sweepRelicCount = 3, qualityWeights = {27,39,24,10}, monsterLevel = 83,  monsters = {204, 205, 206} },
    { floor = 23, firstDust = 2400, sweepDust = 1200, firstRelicCount = 5, sweepRelicCount = 3, qualityWeights = {24,38,26,12}, monsterLevel = 86,  monsters = {204, 205, 206} },
    { floor = 24, firstDust = 2500, sweepDust = 1250, firstRelicCount = 5, sweepRelicCount = 3, qualityWeights = {22,37,27,14}, monsterLevel = 89,  monsters = {204, 205, 206} },
    { floor = 25, firstDust = 2600, sweepDust = 1300, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {19,36,30,15}, monsterLevel = 92,  monsters = {204, 205, 206} },
    { floor = 26, firstDust = 2700, sweepDust = 1350, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {16,35,33,16}, monsterLevel = 95,  monsters = {204, 205, 206} },
    { floor = 27, firstDust = 2800, sweepDust = 1400, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {14,34,35,17}, monsterLevel = 98,  monsters = {204, 205, 206} },
    { floor = 28, firstDust = 2900, sweepDust = 1450, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {11,33,38,18}, monsterLevel = 101, monsters = {204, 205, 206} },
    { floor = 29, firstDust = 3000, sweepDust = 1500, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {8,32,42,18},  monsterLevel = 104, monsters = {204, 205, 206} },
    { floor = 30, firstDust = 3100, sweepDust = 1550, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {6,31,45,18},  monsterLevel = 107, monsters = {204, 205, 206} },
    { floor = 31, firstDust = 3200, sweepDust = 1600, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {4,31,50,15},  monsterLevel = 110, monsters = {204, 205, 206} },
    { floor = 32, firstDust = 3300, sweepDust = 1650, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {2,30,53,15},  monsterLevel = 113, monsters = {204, 205, 206} },
    { floor = 33, firstDust = 3400, sweepDust = 1700, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {2,30,53,15},  monsterLevel = 116, monsters = {204, 205, 206} },
    { floor = 34, firstDust = 3500, sweepDust = 1750, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,30,55,15},  monsterLevel = 119, monsters = {204, 205, 206} },
    { floor = 35, firstDust = 3600, sweepDust = 1800, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,30,55,15},  monsterLevel = 122, monsters = {204, 205, 206} },
    { floor = 36, firstDust = 3700, sweepDust = 1850, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,27,57,16},  monsterLevel = 125, monsters = {204, 205, 206} },
    { floor = 37, firstDust = 3800, sweepDust = 1900, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,24,59,17},  monsterLevel = 128, monsters = {204, 205, 206} },
    { floor = 38, firstDust = 3900, sweepDust = 1950, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,21,61,18},  monsterLevel = 131, monsters = {204, 205, 206} },
    { floor = 39, firstDust = 4000, sweepDust = 2000, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,18,63,19},  monsterLevel = 134, monsters = {204, 205, 206} },
    { floor = 40, firstDust = 4100, sweepDust = 2050, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,15,65,20},  monsterLevel = 137, monsters = {204, 205, 206} },
    { floor = 41, firstDust = 4200, sweepDust = 2100, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,12,67,21},  monsterLevel = 140, monsters = {204, 205, 206} },
    { floor = 42, firstDust = 4300, sweepDust = 2150, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,9,69,22},   monsterLevel = 143, monsters = {204, 205, 206} },
    { floor = 43, firstDust = 4400, sweepDust = 2200, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,6,71,23},   monsterLevel = 146, monsters = {204, 205, 206} },
    { floor = 44, firstDust = 4500, sweepDust = 2250, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,3,73,24},   monsterLevel = 149, monsters = {204, 205, 206} },
    { floor = 45, firstDust = 4600, sweepDust = 2300, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,75,25},   monsterLevel = 152, monsters = {204, 205, 206} },
    { floor = 46, firstDust = 4700, sweepDust = 2350, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,74,26},   monsterLevel = 155, monsters = {204, 205, 206} },
    { floor = 47, firstDust = 4800, sweepDust = 2400, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,73,27},   monsterLevel = 158, monsters = {204, 205, 206} },
    { floor = 48, firstDust = 4900, sweepDust = 2450, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,72,28},   monsterLevel = 161, monsters = {204, 205, 206} },
    { floor = 49, firstDust = 5000, sweepDust = 2500, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,71,29},   monsterLevel = 164, monsters = {204, 205, 206} },
    { floor = 50, firstDust = 5100, sweepDust = 2550, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,70,30},   monsterLevel = 167, monsters = {204, 205, 206} },
    { floor = 51, firstDust = 5200, sweepDust = 2600, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,69,31},   monsterLevel = 170, monsters = {204, 205, 206} },
    { floor = 52, firstDust = 5300, sweepDust = 2650, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,68,32},   monsterLevel = 173, monsters = {204, 205, 206} },
    { floor = 53, firstDust = 5400, sweepDust = 2700, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,67,33},   monsterLevel = 176, monsters = {204, 205, 206} },
    { floor = 54, firstDust = 5500, sweepDust = 2750, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,66,34},   monsterLevel = 179, monsters = {204, 205, 206} },
    { floor = 55, firstDust = 5600, sweepDust = 2800, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,65,35},   monsterLevel = 182, monsters = {204, 205, 206} },
    { floor = 56, firstDust = 5700, sweepDust = 2850, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,64,36},   monsterLevel = 185, monsters = {204, 205, 206} },
    { floor = 57, firstDust = 5800, sweepDust = 2900, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,63,37},   monsterLevel = 188, monsters = {204, 205, 206} },
    { floor = 58, firstDust = 5900, sweepDust = 2950, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,62,38},   monsterLevel = 191, monsters = {204, 205, 206} },
    { floor = 59, firstDust = 6000, sweepDust = 3000, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,61,39},   monsterLevel = 194, monsters = {204, 205, 206} },
    { floor = 60, firstDust = 6100, sweepDust = 3050, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,60,40},   monsterLevel = 197, monsters = {204, 205, 206} },
    { floor = 61, firstDust = 6200, sweepDust = 3100, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,59,41},   monsterLevel = 200, monsters = {204, 205, 206} },
    { floor = 62, firstDust = 6300, sweepDust = 3150, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,58,42},   monsterLevel = 203, monsters = {204, 205, 206} },
    { floor = 63, firstDust = 6400, sweepDust = 3200, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,57,43},   monsterLevel = 206, monsters = {204, 205, 206} },
    { floor = 64, firstDust = 6500, sweepDust = 3250, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,56,44},   monsterLevel = 209, monsters = {204, 205, 206} },
    { floor = 65, firstDust = 6600, sweepDust = 3300, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,55,45},   monsterLevel = 212, monsters = {204, 205, 206} },
    { floor = 66, firstDust = 6700, sweepDust = 3350, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,54,46},   monsterLevel = 215, monsters = {204, 205, 206} },
    { floor = 67, firstDust = 6800, sweepDust = 3400, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,53,47},   monsterLevel = 218, monsters = {204, 205, 206} },
    { floor = 68, firstDust = 6900, sweepDust = 3450, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,52,48},   monsterLevel = 221, monsters = {204, 205, 206} },
    { floor = 69, firstDust = 7000, sweepDust = 3500, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,51,49},   monsterLevel = 224, monsters = {204, 205, 206} },
    { floor = 70, firstDust = 7100, sweepDust = 3550, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,50,50},   monsterLevel = 227, monsters = {204, 205, 206} },
    { floor = 71, firstDust = 7200, sweepDust = 3600, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,49,51},   monsterLevel = 230, monsters = {204, 205, 206} },
    { floor = 72, firstDust = 7300, sweepDust = 3650, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,48,52},   monsterLevel = 233, monsters = {204, 205, 206} },
    { floor = 73, firstDust = 7400, sweepDust = 3700, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,47,53},   monsterLevel = 236, monsters = {204, 205, 206} },
    { floor = 74, firstDust = 7500, sweepDust = 3750, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,46,54},   monsterLevel = 239, monsters = {204, 205, 206} },
    { floor = 75, firstDust = 7600, sweepDust = 3800, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,45,55},   monsterLevel = 242, monsters = {204, 205, 206} },
    { floor = 76, firstDust = 7700, sweepDust = 3850, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,44,56},   monsterLevel = 245, monsters = {204, 205, 206} },
    { floor = 77, firstDust = 7800, sweepDust = 3900, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,43,57},   monsterLevel = 248, monsters = {204, 205, 206} },
    { floor = 78, firstDust = 7900, sweepDust = 3950, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,42,58},   monsterLevel = 251, monsters = {204, 205, 206} },
    { floor = 79, firstDust = 8000, sweepDust = 4000, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,41,59},   monsterLevel = 254, monsters = {204, 205, 206} },
    { floor = 80, firstDust = 8100, sweepDust = 4050, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,40,60},   monsterLevel = 257, monsters = {204, 205, 206} },
    { floor = 81, firstDust = 8200, sweepDust = 4100, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,39,61},   monsterLevel = 260, monsters = {204, 205, 206} },
    { floor = 82, firstDust = 8300, sweepDust = 4150, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,38,62},   monsterLevel = 263, monsters = {204, 205, 206} },
    { floor = 83, firstDust = 8400, sweepDust = 4200, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,37,63},   monsterLevel = 266, monsters = {204, 205, 206} },
    { floor = 84, firstDust = 8500, sweepDust = 4250, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,36,64},   monsterLevel = 269, monsters = {204, 205, 206} },
    { floor = 85, firstDust = 8600, sweepDust = 4300, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,35,65},   monsterLevel = 272, monsters = {204, 205, 206} },
    { floor = 86, firstDust = 8700, sweepDust = 4350, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,34,66},   monsterLevel = 275, monsters = {204, 205, 206} },
    { floor = 87, firstDust = 8800, sweepDust = 4400, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,33,67},   monsterLevel = 278, monsters = {204, 205, 206} },
    { floor = 88, firstDust = 8900, sweepDust = 4450, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,32,68},   monsterLevel = 281, monsters = {204, 205, 206} },
    { floor = 89, firstDust = 9000, sweepDust = 4500, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,31,69},   monsterLevel = 284, monsters = {204, 205, 206} },
    { floor = 90, firstDust = 9100, sweepDust = 4550, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,30,70},   monsterLevel = 287, monsters = {204, 205, 206} },
    { floor = 91, firstDust = 9200, sweepDust = 4600, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,29,71},   monsterLevel = 290, monsters = {204, 205, 206} },
    { floor = 92, firstDust = 9300, sweepDust = 4650, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,28,72},   monsterLevel = 293, monsters = {204, 205, 206} },
    { floor = 93, firstDust = 9400, sweepDust = 4700, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,27,73},   monsterLevel = 296, monsters = {204, 205, 206} },
    { floor = 94, firstDust = 9500, sweepDust = 4750, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,26,74},   monsterLevel = 299, monsters = {204, 205, 206} },
    { floor = 95, firstDust = 9600, sweepDust = 4800, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,25,75},   monsterLevel = 300, monsters = {204, 205, 206} },
    { floor = 96,  firstDust = 9700, sweepDust = 4850, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,24,76},   monsterLevel = 303, monsters = {204, 205, 206} },
    { floor = 97,  firstDust = 9800, sweepDust = 4900, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,23,77},   monsterLevel = 306, monsters = {204, 205, 206} },
    { floor = 98,  firstDust = 9900, sweepDust = 4950, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,22,78},   monsterLevel = 309, monsters = {204, 205, 206} },
    { floor = 99,  firstDust = 10000, sweepDust = 5000, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,21,79},   monsterLevel = 312, monsters = {204, 205, 206} },
    { floor = 100, firstDust = 10100, sweepDust = 5050, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,20,80},   monsterLevel = 315, monsters = {204, 205, 206} },
    { floor = 101, firstDust = 10200, sweepDust = 5100, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,19,81},   monsterLevel = 318, monsters = {204, 205, 206} },
    { floor = 102, firstDust = 10300, sweepDust = 5150, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,18,82},   monsterLevel = 321, monsters = {204, 205, 206} },
    { floor = 103, firstDust = 10400, sweepDust = 5200, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,17,83},   monsterLevel = 324, monsters = {204, 205, 206} },
    { floor = 104, firstDust = 10500, sweepDust = 5250, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,16,84},   monsterLevel = 327, monsters = {204, 205, 206} },
    { floor = 105, firstDust = 10600, sweepDust = 5300, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,15,85},   monsterLevel = 330, monsters = {204, 205, 206} },
    { floor = 106, firstDust = 10700, sweepDust = 5350, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,14,86},   monsterLevel = 333, monsters = {204, 205, 206} },
    { floor = 107, firstDust = 10800, sweepDust = 5400, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,13,87},   monsterLevel = 336, monsters = {204, 205, 206} },
    { floor = 108, firstDust = 10900, sweepDust = 5450, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,12,88},   monsterLevel = 339, monsters = {204, 205, 206} },
    { floor = 109, firstDust = 11000, sweepDust = 5500, firstRelicCount = 6, sweepRelicCount = 3, qualityWeights = {0,0,11,89},   monsterLevel = 342, monsters = {204, 205, 206} },
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

return DungeonConfig
