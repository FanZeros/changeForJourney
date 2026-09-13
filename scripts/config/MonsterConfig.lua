-- ============================================================================
-- MonsterConfig - 怪物配置数据表 + 工厂函数
-- 数据来源: docs/配置文件/怪物配置.txt
-- 包含: 怪物模板(63)、等级曲线(345)、品质表(6)
-- ============================================================================

local AD = require("systems.AttributeDef")
local UnitAttributes = require("systems.UnitAttributes")

local MC = {}

--- 怪物等级曲线上限（湮灭V 末章 345）
MC.MAX_LEVEL = 345

-- 怪物实例唯一 ID 计数器（用于 findUnitIndex 精确定位）
local _instanceCounter = 0

-- ======================== 品质表 ========================

-- dropWeights: 装备品质1~6的掉落权重，来源: docs/配置文件/怪物配置.txt "怪物品质" 表
MC.QUALITY = {
    [1] = { name = "普通级", color = nil,      expMult = 1,     goldMult = 1,     hpMult = 1.00,  atkMult = 1.00, attrMult = 1.00,  dropWeights = {1000,   0,   0,   0,   0,   0} },
    [2] = { name = "精英级", color = "a2ff94", expMult = 1.5,   goldMult = 1.5,   hpMult = 1.50,  atkMult = 1.20, attrMult = 1.50,  dropWeights = { 600, 300,   0,   0,   0,   0} },
    [3] = { name = "勇者级", color = "72f2f5", expMult = 3,     goldMult = 3,     hpMult = 3.00,  atkMult = 1.50, attrMult = 3.00,  dropWeights = { 300, 500, 150,   0,   0,   0} },
    [4] = { name = "史诗级", color = "ef79ff", expMult = 7.5,   goldMult = 7.5,   hpMult = 7.50,  atkMult = 1.90, attrMult = 7.50,  dropWeights = { 100, 300, 400, 150,   0,   0} },
    [5] = { name = "传说级", color = "ffed00", expMult = 22.5,  goldMult = 22.5,  hpMult = 22.50, atkMult = 2.50, attrMult = 22.50, dropWeights = {   0, 100, 300, 450, 100,  20} },
    [6] = { name = "至臻级", color = "ff0000", expMult = 30,    goldMult = 30,    hpMult = 30.00, atkMult = 3.00, attrMult = 30.00, dropWeights = {   0,   0, 150, 500, 300,  60} },
}

-- ======================== 等级配置表 ========================
-- attrScale: 增加的其他属性强度（百分比数值，使用时 /100）

MC.LEVELS = {
    [  1] = { baseHp = 50, baseAtk = 5, attrScale = 5.00, baseExp = 1, goldDrop = 1 },
    [  2] = { baseHp = 83, baseAtk = 7, attrScale = 10.00, baseExp = 2, goldDrop = 2 },
    [  3] = { baseHp = 148, baseAtk = 10, attrScale = 15.00, baseExp = 4, goldDrop = 3 },
    [  4] = { baseHp = 247, baseAtk = 14, attrScale = 20.00, baseExp = 7, goldDrop = 4 },
    [  5] = { baseHp = 382, baseAtk = 21, attrScale = 25.00, baseExp = 11, goldDrop = 5 },
    [  6] = { baseHp = 610, baseAtk = 30, attrScale = 30.00, baseExp = 16, goldDrop = 6 },
    [  7] = { baseHp = 827, baseAtk = 40, attrScale = 35.00, baseExp = 22, goldDrop = 7 },
    [  8] = { baseHp = 1086, baseAtk = 51, attrScale = 40.00, baseExp = 29, goldDrop = 8 },
    [  9] = { baseHp = 1391, baseAtk = 64, attrScale = 45.00, baseExp = 37, goldDrop = 9 },
    [ 10] = { baseHp = 1745, baseAtk = 79, attrScale = 50.00, baseExp = 46, goldDrop = 10 },
    [ 11] = { baseHp = 2365, baseAtk = 100, attrScale = 55.00, baseExp = 56, goldDrop = 11 },
    [ 12] = { baseHp = 2836, baseAtk = 119, attrScale = 60.00, baseExp = 67, goldDrop = 12 },
    [ 13] = { baseHp = 3367, baseAtk = 139, attrScale = 65.00, baseExp = 79, goldDrop = 13 },
    [ 14] = { baseHp = 3959, baseAtk = 161, attrScale = 70.00, baseExp = 92, goldDrop = 14 },
    [ 15] = { baseHp = 4616, baseAtk = 185, attrScale = 75.00, baseExp = 106, goldDrop = 15 },
    [ 16] = { baseHp = 5877, baseAtk = 222, attrScale = 80.00, baseExp = 121, goldDrop = 16 },
    [ 17] = { baseHp = 6710, baseAtk = 251, attrScale = 85.00, baseExp = 137, goldDrop = 17 },
    [ 18] = { baseHp = 7623, baseAtk = 281, attrScale = 90.00, baseExp = 154, goldDrop = 18 },
    [ 19] = { baseHp = 8620, baseAtk = 314, attrScale = 95.00, baseExp = 172, goldDrop = 19 },
    [ 20] = { baseHp = 9707, baseAtk = 349, attrScale = 100.00, baseExp = 191, goldDrop = 20 },
    [ 21] = { baseHp = 11979, baseAtk = 405, attrScale = 105.00, baseExp = 211, goldDrop = 21 },
    [ 22] = { baseHp = 13327, baseAtk = 444, attrScale = 110.00, baseExp = 232, goldDrop = 22 },
    [ 23] = { baseHp = 14787, baseAtk = 486, attrScale = 115.00, baseExp = 254, goldDrop = 23 },
    [ 24] = { baseHp = 16364, baseAtk = 531, attrScale = 120.00, baseExp = 277, goldDrop = 24 },
    [ 25] = { baseHp = 18066, baseAtk = 577, attrScale = 125.00, baseExp = 301, goldDrop = 25 },
    [ 26] = { baseHp = 21890, baseAtk = 658, attrScale = 130.00, baseExp = 326, goldDrop = 26 },
    [ 27] = { baseHp = 23983, baseAtk = 710, attrScale = 135.00, baseExp = 352, goldDrop = 27 },
    [ 28] = { baseHp = 26232, baseAtk = 764, attrScale = 140.00, baseExp = 379, goldDrop = 28 },
    [ 29] = { baseHp = 28646, baseAtk = 822, attrScale = 145.00, baseExp = 407, goldDrop = 29 },
    [ 30] = { baseHp = 31235, baseAtk = 882, attrScale = 150.00, baseExp = 436, goldDrop = 30 },
    [ 31] = { baseHp = 37410, baseAtk = 991, attrScale = 155.00, baseExp = 466, goldDrop = 31 },
    [ 32] = { baseHp = 40585, baseAtk = 1058, attrScale = 160.00, baseExp = 497, goldDrop = 32 },
    [ 33] = { baseHp = 43980, baseAtk = 1127, attrScale = 165.00, baseExp = 529, goldDrop = 33 },
    [ 34] = { baseHp = 47609, baseAtk = 1199, attrScale = 170.00, baseExp = 562, goldDrop = 34 },
    [ 35] = { baseHp = 51485, baseAtk = 1274, attrScale = 175.00, baseExp = 596, goldDrop = 35 },
    [ 36] = { baseHp = 61187, baseAtk = 1420, attrScale = 180.00, baseExp = 631, goldDrop = 36 },
    [ 37] = { baseHp = 65938, baseAtk = 1502, attrScale = 185.00, baseExp = 667, goldDrop = 37 },
    [ 38] = { baseHp = 71004, baseAtk = 1587, attrScale = 190.00, baseExp = 704, goldDrop = 38 },
    [ 39] = { baseHp = 76404, baseAtk = 1676, attrScale = 195.00, baseExp = 742, goldDrop = 39 },
    [ 40] = { baseHp = 82159, baseAtk = 1768, attrScale = 200.00, baseExp = 781, goldDrop = 40 },
    [ 41] = { baseHp = 97117, baseAtk = 1957, attrScale = 205.00, baseExp = 821, goldDrop = 41 },
    [ 42] = { baseHp = 104174, baseAtk = 2057, attrScale = 210.00, baseExp = 862, goldDrop = 42 },
    [ 43] = { baseHp = 111684, baseAtk = 2162, attrScale = 215.00, baseExp = 904, goldDrop = 43 },
    [ 44] = { baseHp = 119675, baseAtk = 2269, attrScale = 220.00, baseExp = 947, goldDrop = 44 },
    [ 45] = { baseHp = 128176, baseAtk = 2381, attrScale = 225.00, baseExp = 991, goldDrop = 45 },
    [ 46] = { baseHp = 150938, baseAtk = 2621, attrScale = 230.00, baseExp = 1036, goldDrop = 46 },
    [ 47] = { baseHp = 161374, baseAtk = 2742, attrScale = 235.00, baseExp = 1082, goldDrop = 47 },
    [ 48] = { baseHp = 172467, baseAtk = 2867, attrScale = 240.00, baseExp = 1129, goldDrop = 48 },
    [ 49] = { baseHp = 184255, baseAtk = 2997, attrScale = 245.00, baseExp = 1177, goldDrop = 49 },
    [ 50] = { baseHp = 196780, baseAtk = 3130, attrScale = 250.00, baseExp = 1226, goldDrop = 50 },
    [ 51] = { baseHp = 231096, baseAtk = 3431, attrScale = 255.00, baseExp = 1276, goldDrop = 51 },
    [ 52] = { baseHp = 246491, baseAtk = 3576, attrScale = 260.00, baseExp = 1327, goldDrop = 52 },
    [ 53] = { baseHp = 262841, baseAtk = 3726, attrScale = 265.00, baseExp = 1379, goldDrop = 53 },
    [ 54] = { baseHp = 280201, baseAtk = 3880, attrScale = 270.00, baseExp = 1432, goldDrop = 54 },
    [ 55] = { baseHp = 298633, baseAtk = 4038, attrScale = 275.00, baseExp = 1486, goldDrop = 55 },
    [ 56] = { baseHp = 350021, baseAtk = 4412, attrScale = 280.00, baseExp = 1541, goldDrop = 56 },
    [ 57] = { baseHp = 372703, baseAtk = 4584, attrScale = 285.00, baseExp = 1597, goldDrop = 57 },
    [ 58] = { baseHp = 396775, baseAtk = 4761, attrScale = 290.00, baseExp = 1654, goldDrop = 58 },
    [ 59] = { baseHp = 422321, baseAtk = 4943, attrScale = 295.00, baseExp = 1712, goldDrop = 59 },
    [ 60] = { baseHp = 449431, baseAtk = 5131, attrScale = 300.00, baseExp = 1771, goldDrop = 60 },
    [ 61] = { baseHp = 526016, baseAtk = 5590, attrScale = 305.00, baseExp = 1831, goldDrop = 61 },
    [ 62] = { baseHp = 559407, baseAtk = 5793, attrScale = 310.00, baseExp = 1892, goldDrop = 62 },
    [ 63] = { baseHp = 594832, baseAtk = 6002, attrScale = 315.00, baseExp = 1954, goldDrop = 63 },
    [ 64] = { baseHp = 632411, baseAtk = 6216, attrScale = 320.00, baseExp = 2017, goldDrop = 64 },
    [ 65] = { baseHp = 672276, baseAtk = 6437, attrScale = 325.00, baseExp = 2081, goldDrop = 65 },
    [ 66] = { baseHp = 786019, baseAtk = 6996, attrScale = 330.00, baseExp = 2146, goldDrop = 66 },
    [ 67] = { baseHp = 835160, baseAtk = 7235, attrScale = 335.00, baseExp = 2212, goldDrop = 67 },
    [ 68] = { baseHp = 887280, baseAtk = 7480, attrScale = 340.00, baseExp = 2279, goldDrop = 68 },
    [ 69] = { baseHp = 942556, baseAtk = 7732, attrScale = 345.00, baseExp = 2347, goldDrop = 69 },
    [ 70] = { baseHp = 1001180, baseAtk = 7990, attrScale = 350.00, baseExp = 2416, goldDrop = 70 },
    [ 71] = { baseHp = 1169686, baseAtk = 8667, attrScale = 355.00, baseExp = 2486, goldDrop = 71 },
    [ 72] = { baseHp = 1241997, baseAtk = 8947, attrScale = 360.00, baseExp = 2557, goldDrop = 72 },
    [ 73] = { baseHp = 1318677, baseAtk = 9234, attrScale = 365.00, baseExp = 2629, goldDrop = 73 },
    [ 74] = { baseHp = 1399987, baseAtk = 9528, attrScale = 370.00, baseExp = 2702, goldDrop = 74 },
    [ 75] = { baseHp = 1486206, baseAtk = 9830, attrScale = 375.00, baseExp = 2776, goldDrop = 75 },
    [ 76] = { baseHp = 1735392, baseAtk = 10646, attrScale = 380.00, baseExp = 2851, goldDrop = 76 },
    [ 77] = { baseHp = 1841795, baseAtk = 10973, attrScale = 385.00, baseExp = 2927, goldDrop = 77 },
    [ 78] = { baseHp = 1954613, baseAtk = 11308, attrScale = 390.00, baseExp = 3004, goldDrop = 78 },
    [ 79] = { baseHp = 2074230, baseAtk = 11651, attrScale = 395.00, baseExp = 3082, goldDrop = 79 },
    [ 80] = { baseHp = 2201054, baseAtk = 12002, attrScale = 400.00, baseExp = 3161, goldDrop = 80 },
    [ 81] = { baseHp = 2569068, baseAtk = 12981, attrScale = 405.00, baseExp = 3241, goldDrop = 81 },
    [ 82] = { baseHp = 2725642, baseAtk = 13362, attrScale = 410.00, baseExp = 3322, goldDrop = 82 },
    [ 83] = { baseHp = 2891641, baseAtk = 13752, attrScale = 415.00, baseExp = 3404, goldDrop = 83 },
    [ 84] = { baseHp = 3067630, baseAtk = 14151, attrScale = 420.00, baseExp = 3487, goldDrop = 84 },
    [ 85] = { baseHp = 3254207, baseAtk = 14561, attrScale = 425.00, baseExp = 3571, goldDrop = 85 },
    [ 86] = { baseHp = 3797211, baseAtk = 15728, attrScale = 430.00, baseExp = 3656, goldDrop = 86 },
    [ 87] = { baseHp = 4027623, baseAtk = 16172, attrScale = 435.00, baseExp = 3742, goldDrop = 87 },
    [ 88] = { baseHp = 4271891, baseAtk = 16626, attrScale = 440.00, baseExp = 3829, goldDrop = 88 },
    [ 89] = { baseHp = 4530844, baseAtk = 17090, attrScale = 445.00, baseExp = 3917, goldDrop = 89 },
    [ 90] = { baseHp = 4805365, baseAtk = 17566, attrScale = 450.00, baseExp = 4006, goldDrop = 90 },
    [ 91] = { baseHp = 5606025, baseAtk = 18954, attrScale = 455.00, baseExp = 4096, goldDrop = 91 },
    [ 92] = { baseHp = 5945117, baseAtk = 19470, attrScale = 460.00, baseExp = 4187, goldDrop = 92 },
    [ 93] = { baseHp = 6304584, baseAtk = 19997, attrScale = 465.00, baseExp = 4279, goldDrop = 93 },
    [ 94] = { baseHp = 6685649, baseAtk = 20537, attrScale = 470.00, baseExp = 4372, goldDrop = 94 },
    [ 95] = { baseHp = 7089608, baseAtk = 21089, attrScale = 475.00, baseExp = 4466, goldDrop = 95 },
    [ 96] = { baseHp = 8269618, baseAtk = 22735, attrScale = 480.00, baseExp = 4561, goldDrop = 96 },
    [ 97] = { baseHp = 8768675, baseAtk = 23334, attrScale = 485.00, baseExp = 4657, goldDrop = 97 },
    [ 98] = { baseHp = 9297705, baseAtk = 23946, attrScale = 490.00, baseExp = 4754, goldDrop = 98 },
    [ 99] = { baseHp = 9858508, baseAtk = 24572, attrScale = 495.00, baseExp = 4852, goldDrop = 99 },
    [100] = { baseHp = 10452988, baseAtk = 25212, attrScale = 500.00, baseExp = 4951, goldDrop = 100 },
    [101] = { baseHp = 12191484, baseAtk = 27160, attrScale = 505.00, baseExp = 5051, goldDrop = 101 },
    [102] = { baseHp = 12926003, baseAtk = 27855, attrScale = 510.00, baseExp = 5152, goldDrop = 102 },
    [103] = { baseHp = 13704623, baseAtk = 28565, attrScale = 515.00, baseExp = 5254, goldDrop = 103 },
    [104] = { baseHp = 14529991, baseAtk = 29290, attrScale = 520.00, baseExp = 5357, goldDrop = 104 },
    [105] = { baseHp = 15404910, baseAtk = 30032, attrScale = 525.00, baseExp = 5461, goldDrop = 105 },
    [106] = { baseHp = 17965590, baseAtk = 32330, attrScale = 530.00, baseExp = 5566, goldDrop = 106 },
    [107] = { baseHp = 19046706, baseAtk = 33135, attrScale = 535.00, baseExp = 5672, goldDrop = 107 },
    [108] = { baseHp = 20192718, baseAtk = 33959, attrScale = 540.00, baseExp = 5779, goldDrop = 108 },
    [109] = { baseHp = 21407521, baseAtk = 34800, attrScale = 545.00, baseExp = 5887, goldDrop = 109 },
    [110] = { baseHp = 22695242, baseAtk = 35659, attrScale = 550.00, baseExp = 5996, goldDrop = 110 },
    [111] = { baseHp = 26466283, baseAtk = 38364, attrScale = 555.00, baseExp = 6106, goldDrop = 111 },
    [112] = { baseHp = 28057590, baseAtk = 39298, attrScale = 560.00, baseExp = 6217, goldDrop = 112 },
    [113] = { baseHp = 29744405, baseAtk = 40252, attrScale = 565.00, baseExp = 6329, goldDrop = 113 },
    [114] = { baseHp = 31532459, baseAtk = 41227, attrScale = 570.00, baseExp = 6442, goldDrop = 114 },
    [115] = { baseHp = 33427827, baseAtk = 42222, attrScale = 575.00, baseExp = 6556, goldDrop = 115 },
    [116] = { baseHp = 38980641, baseAtk = 45401, attrScale = 580.00, baseExp = 6671, goldDrop = 116 },
    [117] = { baseHp = 41322960, baseAtk = 46483, attrScale = 585.00, baseExp = 6787, goldDrop = 117 },
    [118] = { baseHp = 43805847, baseAtk = 47588, attrScale = 590.00, baseExp = 6904, goldDrop = 118 },
    [119] = { baseHp = 46437738, baseAtk = 48717, attrScale = 595.00, baseExp = 7022, goldDrop = 119 },
    [120] = { baseHp = 49227572, baseAtk = 49870, attrScale = 600.00, baseExp = 7141, goldDrop = 120 },
    [121] = { baseHp = 57403309, baseAtk = 53600, attrScale = 605.00, baseExp = 7261, goldDrop = 121 },
    [122] = { baseHp = 60851138, baseAtk = 54853, attrScale = 610.00, baseExp = 7382, goldDrop = 122 },
    [123] = { baseHp = 64505866, baseAtk = 56133, attrScale = 615.00, baseExp = 7504, goldDrop = 123 },
    [124] = { baseHp = 68379908, baseAtk = 57440, attrScale = 620.00, baseExp = 7627, goldDrop = 124 },
    [125] = { baseHp = 72486423, baseAtk = 58775, attrScale = 625.00, baseExp = 7751, goldDrop = 125 },
    [126] = { baseHp = 84523294, baseAtk = 63145, attrScale = 630.00, baseExp = 7876, goldDrop = 126 },
    [127] = { baseHp = 89598472, baseAtk = 64597, attrScale = 635.00, baseExp = 8002, goldDrop = 127 },
    [128] = { baseHp = 94978190, baseAtk = 66080, attrScale = 640.00, baseExp = 8129, goldDrop = 128 },
    [129] = { baseHp = 100680721, baseAtk = 67593, attrScale = 645.00, baseExp = 8257, goldDrop = 129 },
    [130] = { baseHp = 106725435, baseAtk = 69138, attrScale = 650.00, baseExp = 8386, goldDrop = 130 },
    [131] = { baseHp = 124446147, baseAtk = 74252, attrScale = 655.00, baseExp = 8516, goldDrop = 131 },
    [132] = { baseHp = 131916845, baseAtk = 75934, attrScale = 660.00, baseExp = 8647, goldDrop = 132 },
    [133] = { baseHp = 139835816, baseAtk = 77650, attrScale = 665.00, baseExp = 8779, goldDrop = 133 },
    [134] = { baseHp = 148229955, baseAtk = 79403, attrScale = 670.00, baseExp = 8912, goldDrop = 134 },
    [135] = { baseHp = 157127772, baseAtk = 81192, attrScale = 675.00, baseExp = 9046, goldDrop = 135 },
    [136] = { baseHp = 183215438, baseAtk = 87169, attrScale = 680.00, baseExp = 9181, goldDrop = 136 },
    [137] = { baseHp = 194212444, baseAtk = 89116, attrScale = 685.00, baseExp = 9317, goldDrop = 137 },
    [138] = { baseHp = 205869301, baseAtk = 91104, attrScale = 690.00, baseExp = 9454, goldDrop = 138 },
    [139] = { baseHp = 218225599, baseAtk = 93133, attrScale = 695.00, baseExp = 9592, goldDrop = 139 },
    [140] = { baseHp = 231323305, baseAtk = 95205, attrScale = 700.00, baseExp = 9731, goldDrop = 140 },
    [141] = { baseHp = 269727593, baseAtk = 102185, attrScale = 705.00, baseExp = 9871, goldDrop = 141 },
    [142] = { baseHp = 285915479, baseAtk = 104440, attrScale = 710.00, baseExp = 10012, goldDrop = 142 },
    [143] = { baseHp = 303074667, baseAtk = 106742, attrScale = 715.00, baseExp = 10154, goldDrop = 143 },
    [144] = { baseHp = 321263437, baseAtk = 109091, attrScale = 720.00, baseExp = 10297, goldDrop = 144 },
    [145] = { baseHp = 340543564, baseAtk = 111489, attrScale = 725.00, baseExp = 10441, goldDrop = 145 },
    [146] = { baseHp = 397078580, baseAtk = 119633, attrScale = 730.00, baseExp = 10586, goldDrop = 146 },
    [147] = { baseHp = 420907675, baseAtk = 122244, attrScale = 735.00, baseExp = 10732, goldDrop = 147 },
    [148] = { baseHp = 446166546, baseAtk = 124910, attrScale = 740.00, baseExp = 10879, goldDrop = 148 },
    [149] = { baseHp = 472940978, baseAtk = 127630, attrScale = 745.00, baseExp = 11027, goldDrop = 149 },
    [150] = { baseHp = 501321907, baseAtk = 130406, attrScale = 750.00, baseExp = 11176, goldDrop = 150 },
    [151] = { baseHp = 584546294, baseAtk = 139901, attrScale = 755.00, baseExp = 11326, goldDrop = 151 },
    [152] = { baseHp = 619623601, baseAtk = 142926, attrScale = 760.00, baseExp = 11477, goldDrop = 152 },
    [153] = { baseHp = 656805577, baseAtk = 146012, attrScale = 765.00, baseExp = 11629, goldDrop = 153 },
    [154] = { baseHp = 696218502, baseAtk = 149162, attrScale = 770.00, baseExp = 11782, goldDrop = 154 },
    [155] = { baseHp = 737996232, baseAtk = 152376, attrScale = 775.00, baseExp = 11936, goldDrop = 155 },
    [156] = { baseHp = 860508722, baseAtk = 163439, attrScale = 780.00, baseExp = 12091, goldDrop = 156 },
    [157] = { baseHp = 912143925, baseAtk = 166942, attrScale = 785.00, baseExp = 12247, goldDrop = 157 },
    [158] = { baseHp = 966877270, baseAtk = 170516, attrScale = 790.00, baseExp = 12404, goldDrop = 158 },
    [159] = { baseHp = 1024894647, baseAtk = 174164, attrScale = 795.00, baseExp = 12562, goldDrop = 159 },
    [160] = { baseHp = 1086393095, baseAtk = 177885, attrScale = 800.00, baseExp = 12721, goldDrop = 160 },
    [161] = { baseHp = 1266739629, baseAtk = 190767, attrScale = 805.00, baseExp = 12881, goldDrop = 161 },
    [162] = { baseHp = 1342748837, baseAtk = 194824, attrScale = 810.00, baseExp = 13042, goldDrop = 162 },
    [163] = { baseHp = 1423318627, baseAtk = 198963, attrScale = 815.00, baseExp = 13204, goldDrop = 163 },
    [164] = { baseHp = 1508722635, baseAtk = 203187, attrScale = 820.00, baseExp = 13367, goldDrop = 164 },
    [165] = { baseHp = 1599250913, baseAtk = 207497, attrScale = 825.00, baseExp = 13531, goldDrop = 165 },
    [166] = { baseHp = 1864732010, baseAtk = 222489, attrScale = 830.00, baseExp = 13696, goldDrop = 166 },
    [167] = { baseHp = 1976620910, baseAtk = 227188, attrScale = 835.00, baseExp = 13862, goldDrop = 167 },
    [168] = { baseHp = 2095223175, baseAtk = 231982, attrScale = 840.00, baseExp = 14029, goldDrop = 168 },
    [169] = { baseHp = 2220941605, baseAtk = 236874, attrScale = 845.00, baseExp = 14197, goldDrop = 169 },
    [170] = { baseHp = 2354203172, baseAtk = 241865, attrScale = 850.00, baseExp = 14366, goldDrop = 170 },
    [171] = { baseHp = 2745006508, baseAtk = 259305, attrScale = 855.00, baseExp = 14536, goldDrop = 171 },
    [172] = { baseHp = 2909712029, baseAtk = 264748, attrScale = 860.00, baseExp = 14707, goldDrop = 172 },
    [173] = { baseHp = 3084299910, baseAtk = 270300, attrScale = 865.00, baseExp = 14879, goldDrop = 173 },
    [174] = { baseHp = 3269363095, baseAtk = 275966, attrScale = 870.00, baseExp = 15052, goldDrop = 174 },
    [175] = { baseHp = 3465530101, baseAtk = 281746, attrScale = 875.00, baseExp = 15226, goldDrop = 175 },
    [176] = { baseHp = 4040813872, baseAtk = 302026, attrScale = 880.00, baseExp = 15401, goldDrop = 176 },
    [177] = { baseHp = 4283267985, baseAtk = 308330, attrScale = 885.00, baseExp = 15577, goldDrop = 177 },
    [178] = { baseHp = 4540269374, baseAtk = 314763, attrScale = 890.00, baseExp = 15754, goldDrop = 178 },
    [179] = { baseHp = 4812690876, baseAtk = 321325, attrScale = 895.00, baseExp = 15932, goldDrop = 179 },
    [180] = { baseHp = 5101457699, baseAtk = 328020, attrScale = 900.00, baseExp = 16111, goldDrop = 180 },
    [181] = { baseHp = 5948305617, baseAtk = 351593, attrScale = 905.00, baseExp = 16291, goldDrop = 181 },
    [182] = { baseHp = 6305209384, baseAtk = 358896, attrScale = 910.00, baseExp = 16472, goldDrop = 182 },
    [183] = { baseHp = 6683527407, baseAtk = 366347, attrScale = 915.00, baseExp = 16654, goldDrop = 183 },
    [184] = { baseHp = 7084544541, baseAtk = 373948, attrScale = 920.00, baseExp = 16837, goldDrop = 184 },
    [185] = { baseHp = 7509622734, baseAtk = 381703, attrScale = 925.00, baseExp = 17021, goldDrop = 185 },
    [186] = { baseHp = 8756226212, baseAtk = 409096, attrScale = 930.00, baseExp = 17206, goldDrop = 186 },
    [187] = { baseHp = 9281605365, baseAtk = 417557, attrScale = 935.00, baseExp = 17392, goldDrop = 187 },
    [188] = { baseHp = 9838507297, baseAtk = 426188, attrScale = 940.00, baseExp = 17579, goldDrop = 188 },
    [189] = { baseHp = 10428823375, baseAtk = 434994, attrScale = 945.00, baseExp = 17767, goldDrop = 189 },
    [190] = { baseHp = 11054558447, baseAtk = 443977, attrScale = 950.00, baseExp = 17956, goldDrop = 190 },
    [191] = { baseHp = 12889621420, baseAtk = 475799, attrScale = 955.00, baseExp = 18146, goldDrop = 191 },
    [192] = { baseHp = 13663004435, baseAtk = 485602, attrScale = 960.00, baseExp = 18337, goldDrop = 192 },
    [193] = { baseHp = 14482790461, baseAtk = 495602, attrScale = 965.00, baseExp = 18529, goldDrop = 193 },
    [194] = { baseHp = 15351763679, baseAtk = 505803, attrScale = 970.00, baseExp = 18722, goldDrop = 194 },
    [195] = { baseHp = 16272875319, baseAtk = 516210, attrScale = 975.00, baseExp = 18916, goldDrop = 195 },
    [196] = { baseHp = 18974179057, baseAtk = 553168, attrScale = 980.00, baseExp = 19111, goldDrop = 196 },
    [197] = { baseHp = 20112635681, baseAtk = 564526, attrScale = 985.00, baseExp = 19307, goldDrop = 197 },
    [198] = { baseHp = 21319399731, baseAtk = 576112, attrScale = 990.00, baseExp = 19504, goldDrop = 198 },
    [199] = { baseHp = 22598569655, baseAtk = 587931, attrScale = 995.00, baseExp = 19702, goldDrop = 199 },
    [200] = { baseHp = 23954489805, baseAtk = 599988, attrScale = 1000.00, baseExp = 19901, goldDrop = 200 },
    [201] = { baseHp = 27930941712, baseAtk = 642902, attrScale = 1005.00, baseExp = 20101, goldDrop = 201 },
    [202] = { baseHp = 29606804245, baseAtk = 656062, attrScale = 1010.00, baseExp = 20302, goldDrop = 202 },
    [203] = { baseHp = 31383218560, baseAtk = 669486, attrScale = 1015.00, baseExp = 20504, goldDrop = 203 },
    [204] = { baseHp = 33266217763, baseAtk = 683180, attrScale = 1020.00, baseExp = 20707, goldDrop = 204 },
    [205] = { baseHp = 35262196949, baseAtk = 697150, attrScale = 1025.00, baseExp = 20911, goldDrop = 205 },
    [206] = { baseHp = 41115728408, baseAtk = 746970, attrScale = 1030.00, baseExp = 21116, goldDrop = 206 },
    [207] = { baseHp = 43582678292, baseAtk = 762219, attrScale = 1035.00, baseExp = 21322, goldDrop = 207 },
    [208] = { baseHp = 46197645200, baseAtk = 777773, attrScale = 1040.00, baseExp = 21529, goldDrop = 208 },
    [209] = { baseHp = 48969510152, baseAtk = 793641, attrScale = 1045.00, baseExp = 21737, goldDrop = 209 },
    [210] = { baseHp = 51907687031, baseAtk = 809827, attrScale = 1050.00, baseExp = 21946, goldDrop = 210 },
    [211] = { baseHp = 60524370008, baseAtk = 867656, attrScale = 1055.00, baseExp = 22156, goldDrop = 211 },
    [212] = { baseHp = 64155838538, baseAtk = 885325, attrScale = 1060.00, baseExp = 22367, goldDrop = 212 },
    [213] = { baseHp = 68005195211, baseAtk = 903350, attrScale = 1065.00, baseExp = 22579, goldDrop = 213 },
    [214] = { baseHp = 72085513313, baseAtk = 921736, attrScale = 1070.00, baseExp = 22792, goldDrop = 214 },
    [215] = { baseHp = 76410650532, baseAtk = 940492, attrScale = 1075.00, baseExp = 23006, goldDrop = 215 },
    [216] = { baseHp = 89094825615, baseAtk = 1007606, attrScale = 1080.00, baseExp = 23221, goldDrop = 216 },
    [217] = { baseHp = 94440521632, baseAtk = 1028082, attrScale = 1085.00, baseExp = 23437, goldDrop = 217 },
    [218] = { baseHp = 100106959440, baseAtk = 1048969, attrScale = 1090.00, baseExp = 23654, goldDrop = 218 },
    [219] = { baseHp = 106113383547, baseAtk = 1070275, attrScale = 1095.00, baseExp = 23872, goldDrop = 219 },
    [220] = { baseHp = 112480193129, baseAtk = 1092009, attrScale = 1100.00, baseExp = 24091, goldDrop = 220 },
    [221] = { baseHp = 131151912449, baseAtk = 1169888, attrScale = 1105.00, baseExp = 24311, goldDrop = 221 },
    [222] = { baseHp = 139021033826, baseAtk = 1193618, attrScale = 1110.00, baseExp = 24532, goldDrop = 222 },
    [223] = { baseHp = 147362302515, baseAtk = 1217823, attrScale = 1115.00, baseExp = 24754, goldDrop = 223 },
    [224] = { baseHp = 156204047356, baseAtk = 1242514, attrScale = 1120.00, baseExp = 24977, goldDrop = 224 },
    [225] = { baseHp = 165576296918, baseAtk = 1267700, attrScale = 1125.00, baseExp = 25201, goldDrop = 225 },
    [226] = { baseHp = 193061969631, baseAtk = 1358061, attrScale = 1130.00, baseExp = 25426, goldDrop = 226 },
    [227] = { baseHp = 204645694589, baseAtk = 1385562, attrScale = 1135.00, baseExp = 25652, goldDrop = 227 },
    [228] = { baseHp = 216924443074, baseAtk = 1413613, attrScale = 1140.00, baseExp = 25879, goldDrop = 228 },
    [229] = { baseHp = 229939916499, baseAtk = 1442228, attrScale = 1145.00, baseExp = 26107, goldDrop = 229 },
    [230] = { baseHp = 243736318359, baseAtk = 1471416, attrScale = 1150.00, baseExp = 26336, goldDrop = 230 },
    [231] = { baseHp = 284196554796, baseAtk = 1576248, attrScale = 1155.00, baseExp = 26566, goldDrop = 231 },
    [232] = { baseHp = 301248355014, baseAtk = 1608120, attrScale = 1160.00, baseExp = 26797, goldDrop = 232 },
    [233] = { baseHp = 319323263275, baseAtk = 1640630, attrScale = 1165.00, baseExp = 27029, goldDrop = 233 },
    [234] = { baseHp = 338482666061, baseAtk = 1673792, attrScale = 1170.00, baseExp = 27262, goldDrop = 234 },
    [235] = { baseHp = 358791633045, baseAtk = 1707619, attrScale = 1175.00, baseExp = 27496, goldDrop = 235 },
    [236] = { baseHp = 418351051885, baseAtk = 1829230, attrScale = 1180.00, baseExp = 27731, goldDrop = 236 },
    [237] = { baseHp = 443452122078, baseAtk = 1866169, attrScale = 1185.00, baseExp = 27967, goldDrop = 237 },
    [238] = { baseHp = 470059256513, baseAtk = 1903848, attrScale = 1190.00, baseExp = 28204, goldDrop = 238 },
    [239] = { baseHp = 498262819044, baseAtk = 1942282, attrScale = 1195.00, baseExp = 28442, goldDrop = 239 },
    [240] = { baseHp = 528158595357, baseAtk = 1981486, attrScale = 1200.00, baseExp = 28681, goldDrop = 240 },
    [241] = { baseHp = 615832930106, baseAtk = 2122549, attrScale = 1205.00, baseExp = 28921, goldDrop = 241 },
    [242] = { baseHp = 652782913142, baseAtk = 2165362, attrScale = 1210.00, baseExp = 29162, goldDrop = 242 },
    [243] = { baseHp = 691949895191, baseAtk = 2209032, attrScale = 1215.00, baseExp = 29404, goldDrop = 243 },
    [244] = { baseHp = 733466896192, baseAtk = 2253577, attrScale = 1220.00, baseExp = 29647, goldDrop = 244 },
    [245] = { baseHp = 777474917284, baseAtk = 2299015, attrScale = 1225.00, baseExp = 29891, goldDrop = 245 },
    [246] = { baseHp = 906535761638, baseAtk = 2462631, attrScale = 1230.00, baseExp = 30136, goldDrop = 246 },
    [247] = { baseHp = 960927914716, baseAtk = 2512252, attrScale = 1235.00, baseExp = 30382, goldDrop = 247 },
    [248] = { baseHp = 1018583597009, baseAtk = 2562868, attrScale = 1240.00, baseExp = 30629, goldDrop = 248 },
    [249] = { baseHp = 1079698620269, baseAtk = 2614497, attrScale = 1245.00, baseExp = 30877, goldDrop = 249 },
    [250] = { baseHp = 1144480544956, baseAtk = 2667161, attrScale = 1250.00, baseExp = 31126, goldDrop = 250 },
    [251] = { baseHp = 1334464323668, baseAtk = 2856923, attrScale = 1255.00, baseExp = 31376, goldDrop = 251 },
    [252] = { baseHp = 1414532190618, baseAtk = 2914438, attrScale = 1260.00, baseExp = 31627, goldDrop = 252 },
    [253] = { baseHp = 1499404129615, baseAtk = 2973104, attrScale = 1265.00, baseExp = 31879, goldDrop = 253 },
    [254] = { baseHp = 1589368384982, baseAtk = 3032946, attrScale = 1270.00, baseExp = 32132, goldDrop = 254 },
    [255] = { baseHp = 1684730495701, baseAtk = 3093986, attrScale = 1275.00, baseExp = 32386, goldDrop = 255 },
    [256] = { baseHp = 1964395766403, baseAtk = 3314061, attrScale = 1280.00, baseExp = 32641, goldDrop = 256 },
    [257] = { baseHp = 2082259520067, baseAtk = 3380726, attrScale = 1285.00, baseExp = 32897, goldDrop = 257 },
    [258] = { baseHp = 2207195098981, baseAtk = 3448726, attrScale = 1290.00, baseExp = 33154, goldDrop = 258 },
    [259] = { baseHp = 2339626812660, baseAtk = 3518087, attrScale = 1295.00, baseExp = 33412, goldDrop = 259 },
    [260] = { baseHp = 2480004429189, baseAtk = 3588838, attrScale = 1300.00, baseExp = 33671, goldDrop = 260 },
    [261] = { baseHp = 2891685173015, baseAtk = 3844055, attrScale = 1305.00, baseExp = 33931, goldDrop = 261 },
    [262] = { baseHp = 3065186291226, baseAtk = 3921327, attrScale = 1310.00, baseExp = 34192, goldDrop = 262 },
    [263] = { baseHp = 3249097476559, baseAtk = 4000147, attrScale = 1315.00, baseExp = 34454, goldDrop = 263 },
    [264] = { baseHp = 3444043333043, baseAtk = 4080544, attrScale = 1320.00, baseExp = 34717, goldDrop = 264 },
    [265] = { baseHp = 3650685940945, baseAtk = 4162551, attrScale = 1325.00, baseExp = 34981, goldDrop = 265 },
    [266] = { baseHp = 4256699815887, baseAtk = 4458509, attrScale = 1330.00, baseExp = 35246, goldDrop = 266 },
    [267] = { baseHp = 4512101812820, baseAtk = 4548079, attrScale = 1335.00, baseExp = 35512, goldDrop = 267 },
    [268] = { baseHp = 4782827929600, baseAtk = 4639441, attrScale = 1340.00, baseExp = 35779, goldDrop = 268 },
    [269] = { baseHp = 5069797613415, baseAtk = 4732632, attrScale = 1345.00, baseExp = 36047, goldDrop = 269 },
    [270] = { baseHp = 5373985478290, baseAtk = 4827688, attrScale = 1350.00, baseExp = 36316, goldDrop = 270 },
    [271] = { baseHp = 6266067076597, baseAtk = 5170879, attrScale = 1355.00, baseExp = 36586, goldDrop = 271 },
    [272] = { baseHp = 6642031109322, baseAtk = 5274703, attrScale = 1360.00, baseExp = 36857, goldDrop = 272 },
    [273] = { baseHp = 7040552984042, baseAtk = 5380605, attrScale = 1365.00, baseExp = 37129, goldDrop = 273 },
    [274] = { baseHp = 7462986171274, baseAtk = 5488626, attrScale = 1370.00, baseExp = 37402, goldDrop = 274 },
    [275] = { baseHp = 7910765349771, baseAtk = 5598810, attrScale = 1375.00, baseExp = 37676, goldDrop = 275 },
    [276] = { baseHp = 9223952406908, baseAtk = 5996759, attrScale = 1380.00, baseExp = 37951, goldDrop = 276 },
    [277] = { baseHp = 9777389559602, baseAtk = 6117108, attrScale = 1385.00, baseExp = 38227, goldDrop = 277 },
    [278] = { baseHp = 10364032941488, baseAtk = 6239865, attrScale = 1390.00, baseExp = 38504, goldDrop = 278 },
    [279] = { baseHp = 10985874926318, baseAtk = 6365080, attrScale = 1395.00, baseExp = 38782, goldDrop = 279 },
    [280] = { baseHp = 11645027430267, baseAtk = 6492800, attrScale = 1400.00, baseExp = 39061, goldDrop = 280 },
    [281] = { baseHp = 13578101992931, baseAtk = 6954230, attrScale = 1405.00, baseExp = 39341, goldDrop = 281 },
    [282] = { baseHp = 14392788120937, baseAtk = 7093736, attrScale = 1410.00, baseExp = 39622, goldDrop = 282 },
    [283] = { baseHp = 15256355416653, baseAtk = 7236033, attrScale = 1415.00, baseExp = 39904, goldDrop = 283 },
    [284] = { baseHp = 16171736750142, baseAtk = 7381179, attrScale = 1420.00, baseExp = 40187, goldDrop = 284 },
    [285] = { baseHp = 17142040963671, baseAtk = 7529228, attrScale = 1425.00, baseExp = 40471, goldDrop = 285 },
    [286] = { baseHp = 19987619773045, baseAtk = 8064252, attrScale = 1430.00, baseExp = 40756, goldDrop = 286 },
    [287] = { baseHp = 21186876968008, baseAtk = 8225966, attrScale = 1435.00, baseExp = 41042, goldDrop = 287 },
    [288] = { baseHp = 22458089594698, baseAtk = 8390916, attrScale = 1440.00, baseExp = 41329, goldDrop = 288 },
    [289] = { baseHp = 23805574979020, baseAtk = 8559166, attrScale = 1445.00, baseExp = 41617, goldDrop = 289 },
    [290] = { baseHp = 25233909486431, baseAtk = 8730783, attrScale = 1450.00, baseExp = 41906, goldDrop = 290 },
    [291] = { baseHp = 29422738470749, baseAtk = 9351126, attrScale = 1455.00, baseExp = 42196, goldDrop = 291 },
    [292] = { baseHp = 31188102787724, baseAtk = 9538585, attrScale = 1460.00, baseExp = 42487, goldDrop = 292 },
    [293] = { baseHp = 33059388963747, baseAtk = 9729794, attrScale = 1465.00, baseExp = 42779, goldDrop = 293 },
    [294] = { baseHp = 35042952310362, baseAtk = 9924830, attrScale = 1470.00, baseExp = 43072, goldDrop = 294 },
    [295] = { baseHp = 37145529457804, baseAtk = 10123767, attrScale = 1475.00, baseExp = 43366, goldDrop = 295 },
    [296] = { baseHp = 43311687357534, baseAtk = 10843019, attrScale = 1480.00, baseExp = 43661, goldDrop = 296 },
    [297] = { baseHp = 45910388607866, baseAtk = 11060324, attrScale = 1485.00, baseExp = 43957, goldDrop = 297 },
    [298] = { baseHp = 48665011933248, baseAtk = 11281976, attrScale = 1490.00, baseExp = 44254, goldDrop = 298 },
    [299] = { baseHp = 51584912658183, baseAtk = 11508062, attrScale = 1495.00, baseExp = 44552, goldDrop = 299 },
    [300] = { baseHp = 54680007426644, baseAtk = 11738672, attrScale = 1500.00, baseExp = 44851, goldDrop = 300 },
    [301] = { baseHp = 63756888669367, baseAtk = 12572590, attrScale = 1505.00, baseExp = 45151, goldDrop = 301 },
    [302] = { baseHp = 67582301998559, baseAtk = 12824494, attrScale = 1510.00, baseExp = 45452, goldDrop = 302 },
    [303] = { baseHp = 71637240127532, baseAtk = 13081437, attrScale = 1515.00, baseExp = 45754, goldDrop = 303 },
    [304] = { baseHp = 75935474544274, baseAtk = 13343520, attrScale = 1520.00, baseExp = 46057, goldDrop = 304 },
    [305] = { baseHp = 80491603026051, baseAtk = 13610846, attrScale = 1525.00, baseExp = 46361, goldDrop = 305 },
    [306] = { baseHp = 93853209138440, baseAtk = 14577697, attrScale = 1530.00, baseExp = 46666, goldDrop = 306 },
    [307] = { baseHp = 99484401695927, baseAtk = 14869710, attrScale = 1535.00, baseExp = 46972, goldDrop = 307 },
    [308] = { baseHp = 105453465806892, baseAtk = 15167564, attrScale = 1540.00, baseExp = 47279, goldDrop = 308 },
    [309] = { baseHp = 111780673764546, baseAtk = 15471377, attrScale = 1545.00, baseExp = 47587, goldDrop = 309 },
    [310] = { baseHp = 118487514199688, baseAtk = 15781269, attrScale = 1550.00, baseExp = 47896, goldDrop = 310 },
    [311] = { baseHp = 138156441567067, baseAtk = 16902227, attrScale = 1555.00, baseExp = 48206, goldDrop = 311 },
    [312] = { baseHp = 146445828070421, baseAtk = 17240738, attrScale = 1560.00, baseExp = 48517, goldDrop = 312 },
    [313] = { baseHp = 155232577764006, baseAtk = 17586021, attrScale = 1565.00, baseExp = 48829, goldDrop = 313 },
    [314] = { baseHp = 164546532439236, baseAtk = 17938211, attrScale = 1570.00, baseExp = 49142, goldDrop = 314 },
    [315] = { baseHp = 174419324395010, baseAtk = 18297446, attrScale = 1575.00, baseExp = 49456, goldDrop = 315 },
    [316] = { baseHp = 203372932254977, baseAtk = 19597061, attrScale = 1580.00, baseExp = 49771, goldDrop = 316 },
    [317] = { baseHp = 215575308199756, baseAtk = 19989476, attrScale = 1585.00, baseExp = 50087, goldDrop = 317 },
    [318] = { baseHp = 228509826701251, baseAtk = 20389741, attrScale = 1590.00, baseExp = 50404, goldDrop = 318 },
    [319] = { baseHp = 242220416312866, baseAtk = 20798013, attrScale = 1595.00, baseExp = 50722, goldDrop = 319 },
    [320] = { baseHp = 256753641301208, baseAtk = 21214451, attrScale = 1600.00, baseExp = 51041, goldDrop = 320 },
    [321] = { baseHp = 299374745767769, baseAtk = 22721181, attrScale = 1605.00, baseExp = 51361, goldDrop = 321 },
    [322] = { baseHp = 317337230523465, baseAtk = 23176087, attrScale = 1610.00, baseExp = 51682, goldDrop = 322 },
    [323] = { baseHp = 336377464364533, baseAtk = 23640091, attrScale = 1615.00, baseExp = 52004, goldDrop = 323 },
    [324] = { baseHp = 356560112236095, baseAtk = 24113378, attrScale = 1620.00, baseExp = 52327, goldDrop = 324 },
    [325] = { baseHp = 377953718979981, baseAtk = 24596131, attrScale = 1625.00, baseExp = 52651, goldDrop = 325 },
    [326] = { baseHp = 440694036341383, baseAtk = 26342968, attrScale = 1630.00, baseExp = 52976, goldDrop = 326 },
    [327] = { baseHp = 467135678531646, baseAtk = 26870317, attrScale = 1635.00, baseExp = 53302, goldDrop = 327 },
    [328] = { baseHp = 495163819253354, baseAtk = 27408214, attrScale = 1640.00, baseExp = 53629, goldDrop = 328 },
    [329] = { baseHp = 524873648418396, baseAtk = 27956870, attrScale = 1645.00, baseExp = 53957, goldDrop = 329 },
    [330] = { baseHp = 556366067333369, baseAtk = 28516501, attrScale = 1650.00, baseExp = 54286, goldDrop = 330 },
    [331] = { baseHp = 648722834521599, baseAtk = 30541692, attrScale = 1655.00, baseExp = 54616, goldDrop = 331 },
    [332] = { baseHp = 687646204602825, baseAtk = 31153022, attrScale = 1660.00, baseExp = 54947, goldDrop = 332 },
    [333] = { baseHp = 728904976888954, baseAtk = 31776581, attrScale = 1665.00, baseExp = 55279, goldDrop = 333 },
    [334] = { baseHp = 772639275512282, baseAtk = 32412612, attrScale = 1670.00, baseExp = 55612, goldDrop = 334 },
    [335] = { baseHp = 818997632053039, baseAtk = 33061365, attrScale = 1675.00, baseExp = 55946, goldDrop = 335 },
    [336] = { baseHp = 954951238984898, baseAtk = 35409250, attrScale = 1680.00, baseExp = 56281, goldDrop = 336 },
    [337] = { baseHp = 1012248313334070, baseAtk = 36117939, attrScale = 1685.00, baseExp = 56617, goldDrop = 337 },
    [338] = { baseHp = 1072983212144230, baseAtk = 36840803, attrScale = 1690.00, baseExp = 56954, goldDrop = 338 },
    [339] = { baseHp = 1137362204883020, baseAtk = 37578126, attrScale = 1695.00, baseExp = 57292, goldDrop = 339 },
    [340] = { baseHp = 1205603937186170, baseAtk = 38330197, attrScale = 1700.00, baseExp = 57631, goldDrop = 340 },
    [341] = { baseHp = 1405734190770300, baseAtk = 41052176, attrScale = 1705.00, baseExp = 57971, goldDrop = 341 },
    [342] = { baseHp = 1490078242226740, baseAtk = 41873732, attrScale = 1710.00, baseExp = 58312, goldDrop = 342 },
    [343] = { baseHp = 1579482936770610, baseAtk = 42711719, attrScale = 1715.00, baseExp = 58654, goldDrop = 343 },
    [344] = { baseHp = 1674251912987140, baseAtk = 43566468, attrScale = 1720.00, baseExp = 58997, goldDrop = 344 },
    [345] = { baseHp = 1774707027776680, baseAtk = 44438313, attrScale = 1725.00, baseExp = 59341, goldDrop = 345 },
}

-- ======================== 怪物模板表 ========================
-- atkType:  1=斩击 2=粉碎 3=穿刺 4=火焰 5=冰霜 6=闪电 7=暗影 8=神圣
-- armorType: 1=皮甲 2=轻甲 3=重甲 4=板甲 5=布甲
-- attrs: 额外属性 { [AD属性key] = 基础值 }，实际值 = 基础值 × (1 + attrScale/100)

MC.MONSTERS = {
    [1]  = { quality = 1, name = "天狗",       atkType = 1, armorType = 1, atkTargets = 1, atkInterval = 1.6, hpRatio = 1.00, atkRatio = 1.60, attrs = {} },
    [2]  = { quality = 1, name = "鹿蜀",   atkType = 6, armorType = 5, atkTargets = 1, atkInterval = 2.0, hpRatio = 1.20, atkRatio = 1.60, attrs = {} },
    [3]  = { quality = 2, name = "山膏",     atkType = 1, armorType = 2, atkTargets = 1, atkInterval = 1.8, hpRatio = 1.00, atkRatio = 1.80, attrs = {} },
    [4]  = { quality = 1, name = "酸与",   atkType = 3, armorType = 1, atkTargets = 1, atkInterval = 1.2, hpRatio = 0.40, atkRatio = 0.96, attrs = {
        [AD.DODGE] = 0.40,
    }},
    [5]  = { quality = 2, name = "巫彭", atkType = 8, armorType = 5, atkTargets = 2, atkInterval = 3.0, hpRatio = 0.80, atkRatio = 0.60, attrs = {
        [AD.MAG_ARMOR] = 4.00,
    }},
    [6]  = { quality = 3, name = "蛊雕", atkType = 3, armorType = 2, atkTargets = 1, atkInterval = 2.0, hpRatio = 0.80, atkRatio = 0.80, attrs = {
        [AD.HIT_VALUE] = 0.50,
    }},
    [7]  = { quality = 3, name = "九尾狐",   atkType = 7, armorType = 1, atkTargets = 1, atkInterval = 1.8, hpRatio = 1.00, atkRatio = 0.90, attrs = {
        [AD.CRIT_RATE] = 0.3,
    }},
    [8]  = { quality = 5, name = "雷神",   atkType = 6, armorType = 5, atkTargets = 2, atkInterval = 4.0, hpRatio = 0.80, atkRatio = 0.80, attrs = {
        [AD.PHYS_ARMOR] = 0.29, [AD.MAG_ARMOR] = 2.00,
    }},
    [9]  = { quality = 5, name = "诸犍",   atkType = 2, armorType = 3, atkTargets = 3, atkInterval = 5.0, hpRatio = 0.60, atkRatio = 1.00, attrs = {
        [AD.PHYS_ARMOR] = 0.29, [AD.MAG_ARMOR] = 2.00,
    }},
    [10] = { quality = 2, name = "猛豹", atkType = 3, armorType = 2, atkTargets = 1, atkInterval = 1.6, hpRatio = 0.67, atkRatio = 1.07, attrs = {
        [AD.PHYS_PEN] = 0.67,
    }},
    [11] = { quality = 3, name = "窫窳", atkType = 1, armorType = 2, atkTargets = 1, atkInterval = 1.8, hpRatio = 0.50, atkRatio = 0.90, attrs = {
        [AD.HIT_VALUE] = 0.31, [AD.CRIT_RATE] = 0.3,
    }},
    [12] = { quality = 2, name = "精卫",       atkType = 6, armorType = 1, atkTargets = 1, atkInterval = 1.0, hpRatio = 0.50, atkRatio = 0.50, attrs = {
        [AD.MAG_PEN] = 0.50, [AD.DODGE] = 0.25,
    }},
    [13] = { quality = 2, name = "豪彘",       atkType = 6, armorType = 4, atkTargets = 1, atkInterval = 1.6, hpRatio = 0.50, atkRatio = 0.80, attrs = {
        [AD.MAG_PEN] = 0.50, [AD.PHYS_ARMOR] = 0.36,
    }},
    [14] = { quality = 1, name = "马腹",       atkType = 1, armorType = 1, atkTargets = 1, atkInterval = 1.8, hpRatio = 0.61, atkRatio = 1.42, attrs = {
        [AD.ATK_HEAL] = 0.67,
    }},
    [15] = { quality = 2, name = "长右",       atkType = 1, armorType = 2, atkTargets = 1, atkInterval = 2.0, hpRatio = 0.61, atkRatio = 1.58, attrs = {
        [AD.ATK_HEAL] = 0.67,
    }},
    [16] = { quality = 5, name = "穷奇",   atkType = 3, armorType = 2, atkTargets = 2, atkInterval = 3.0, hpRatio = 1.00, atkRatio = 0.50, attrs = {
        [AD.PHYS_ARMOR] = 0.24, [AD.MAG_ARMOR] = 1.67,
    }},
    [17] = { quality = 5, name = "毕方",     atkType = 4, armorType = 1, atkTargets = 3, atkInterval = 3.6, hpRatio = 0.49, atkRatio = 1.17, attrs = {
        [AD.MAG_ARMOR] = 2.44, [AD.COMBO_RATE] = 0.1,
    }},
    [18] = { quality = 3, name = "金乌",   atkType = 4, armorType = 5, atkTargets = 1, atkInterval = 2.4, hpRatio = 0.36, atkRatio = 1.31, attrs = {
        [AD.MAG_ARMOR] = 1.82, [AD.HIT_VALUE] = 0.45,
    }},
    [19] = { quality = 1, name = "英招", atkType = 3, armorType = 2, atkTargets = 1, atkInterval = 1.8, hpRatio = 0.50, atkRatio = 0.90, attrs = {
        [AD.HIT_VALUE] = 0.31, [AD.PHYS_ARMOR] = 0.36,
    }},
    [20] = { quality = 2, name = "孰湖", atkType = 1, armorType = 3, atkTargets = 1, atkInterval = 2.8, hpRatio = 0.40, atkRatio = 1.12, attrs = {
        [AD.MAG_ARMOR] = 2.00, [AD.PHYS_ARMOR] = 0.29, [AD.HIT_VALUE] = 0.25,
    }},
    [21] = { quality = 5, name = "泰逢", atkType = 1, armorType = 3, atkTargets = 2, atkInterval = 3.6, hpRatio = 0.77, atkRatio = 0.55, attrs = {
        [AD.PHYS_ARMOR] = 0.22, [AD.MAG_ARMOR] = 1.54, [AD.HIT_VALUE] = 0.19,
    }},
    [22] = { quality = 1, name = "罴",       atkType = 2, armorType = 1, atkTargets = 1, atkInterval = 2.4, hpRatio = 0.80, atkRatio = 0.96, attrs = {
        [AD.PHYS_ARMOR] = 0.29, [AD.COMBO_RATE] = 0.7,
    }},
    [23] = { quality = 2, name = "旄牛",   atkType = 2, armorType = 3, atkTargets = 1, atkInterval = 2.8, hpRatio = 1.00, atkRatio = 1.40, attrs = {
        [AD.PHYS_ARMOR] = 0.36,
    }},
    [24] = { quality = 3, name = "驺虞",       atkType = 5, armorType = 3, atkTargets = 2, atkInterval = 3.0, hpRatio = 0.80, atkRatio = 0.60, attrs = {
        [AD.PHYS_ARMOR] = 0.29, [AD.MAG_ARMOR] = 2.00,
    }},
    [25] = { quality = 5, name = "当康",   atkType = 2, armorType = 3, atkTargets = 3, atkInterval = 4.0, hpRatio = 0.57, atkRatio = 0.38, attrs = {
        [AD.PHYS_ARMOR] = 0.41, [AD.MAG_ARMOR] = 1.43, [AD.DODGE] = 0.14,
    }},
    [26] = { quality = 2, name = "旋龟",       atkType = 2, armorType = 4, atkTargets = 1, atkInterval = 3.6, hpRatio = 0.67, atkRatio = 1.20, attrs = {
        [AD.PHYS_ARMOR] = 0.48, [AD.MAG_ARMOR] = 1.67,
    }},
    [27] = { quality = 1, name = "冰夷",     atkType = 5, armorType = 5, atkTargets = 1, atkInterval = 2.0, hpRatio = 1.00, atkRatio = 1.00, attrs = {
        [AD.MAG_ARMOR] = 2.50,
    }},
    [28] = { quality = 5, name = "黄能",       atkType = 2, armorType = 4, atkTargets = 3, atkInterval = 5.0, hpRatio = 0.62, atkRatio = 0.51, attrs = {
        [AD.PHYS_ARMOR] = 0.44, [AD.MAG_ARMOR] = 1.54, [AD.HIT_VALUE] = 0.10,
    }},
    [29] = { quality = 3, name = "玄冥",       atkType = 5, armorType = 1, atkTargets = 2, atkInterval = 2.6, hpRatio = 0.75, atkRatio = 0.33, attrs = {
        [AD.PHYS_ARMOR] = 0.18, [AD.MAG_ARMOR] = 2.50, [AD.HIT_VALUE] = 0.16,
    }},
    [30] = { quality = 3, name = "孟极",     atkType = 5, armorType = 1, atkTargets = 1, atkInterval = 1.8, hpRatio = 0.44, atkRatio = 1.20, attrs = {
        [AD.DODGE] = 0.22, [AD.HIT_VALUE] = 0.28,
    }},
    [31] = { quality = 5, name = "梼杌",     atkType = 7, armorType = 3, atkTargets = 3, atkInterval = 3.0, hpRatio = 0.36, atkRatio = 0.55, attrs = {
        [AD.DODGE] = 0.18, [AD.PHYS_ARMOR] = 0.26, [AD.HIT_VALUE] = 0.23,
    }},
    [32] = { quality = 2, name = "蜚",     atkType = 3, armorType = 1, atkTargets = 1, atkInterval = 1.4, hpRatio = 0.15, atkRatio = 1.29, attrs = {
        [AD.ATK_SPEED] = 0.4, [AD.DODGE] = 0.31,
    }},
    [33] = { quality = 5, name = "相柳",   atkType = 7, armorType = 1, atkTargets = 2, atkInterval = 4.0, hpRatio = 0.46, atkRatio = 1.85, attrs = {
        [AD.DODGE] = 0.15, [AD.HIT_VALUE] = 0.19,
    }},
    [34] = { quality = 4, name = "乘黄",   atkType = 6, armorType = 3, atkTargets = 2, atkInterval = 3.0, hpRatio = 0.80, atkRatio = 0.60, attrs = {
        [AD.PHYS_ARMOR] = 0.19, [AD.MAG_ARMOR] = 1.33, [AD.HIT_VALUE] = 0.17,
    }},
    [35] = { quality = 5, name = "饕餮",   atkType = 2, armorType = 4, atkTargets = 3, atkInterval = 5.0, hpRatio = 0.80, atkRatio = 0.67, attrs = {
        [AD.PHYS_ARMOR] = 0.19, [AD.MAG_ARMOR] = 1.33, [AD.PHYS_PEN] = 0.27,
    }},
    [36] = { quality = 2, name = "夸父",     atkType = 2, armorType = 4, atkTargets = 2, atkInterval = 3.6, hpRatio = 0.86, atkRatio = 0.51, attrs = {
        [AD.PHYS_ARMOR] = 0.20, [AD.MAG_ARMOR] = 1.43, [AD.PHYS_PEN] = 0.29,
    }},
    [37] = { quality = 1, name = "何罗鱼",       atkType = 5, armorType = 4, atkTargets = 1, atkInterval = 2.4, hpRatio = 0.86, atkRatio = 1.37, attrs = {
        [AD.PHYS_ARMOR] = 0.20, [AD.PHYS_PEN] = 0.29,
    }},
    [38] = { quality = 2, name = "氐人",   atkType = 6, armorType = 5, atkTargets = 1, atkInterval = 2.0, hpRatio = 0.40, atkRatio = 1.60, attrs = {
        [AD.MAG_ARMOR] = 2.00, [AD.MAG_PEN] = 0.40,
    }},
    [39] = { quality = 5, name = "龙伯",   atkType = 5, armorType = 3, atkTargets = 3, atkInterval = 5.0, hpRatio = 1.00, atkRatio = 0.56, attrs = {
        [AD.PHYS_ARMOR] = 0.24, [AD.MAG_ARMOR] = 1.67,
    }},
    [40] = { quality = 1, name = "耕父",   atkType = 7, armorType = 5, atkTargets = 1, atkInterval = 2.0, hpRatio = 0.50, atkRatio = 1.00, attrs = {
        [AD.DODGE] = 0.50,
    }},
    [41] = { quality = 3, name = "贰负", atkType = 7, armorType = 5, atkTargets = 1, atkInterval = 2.4, hpRatio = 0.29, atkRatio = 0.69, attrs = {
        [AD.DODGE] = 0.71,
    }},
    [42] = { quality = 1, name = "旱魃",     atkType = 4, armorType = 5, atkTargets = 1, atkInterval = 2.0, hpRatio = 0.40, atkRatio = 0.80, attrs = {
        [AD.MAG_ARMOR] = 2.00, [AD.DODGE] = 0.40,
    }},
    [43] = { quality = 5, name = "祝融", atkType = 4, armorType = 4, atkTargets = 3, atkInterval = 5.0, hpRatio = 1.00, atkRatio = 0.33, attrs = {
        [AD.PHYS_ARMOR] = 0.29, [AD.MAG_ARMOR] = 1.00, [AD.DODGE] = 0.10,
    }},
    [44] = { quality = 1, name = "鱼妇",       atkType = 7, armorType = 3, atkTargets = 1, atkInterval = 2.6, hpRatio = 0.75, atkRatio = 0.65, attrs = {
        [AD.PHYS_ARMOR] = 0.36, [AD.MAG_ARMOR] = 1.25, [AD.MAG_PEN] = 0.25,
    }},
    [45] = { quality = 2, name = "夏耕之尸",   atkType = 1, armorType = 2, atkTargets = 1, atkInterval = 2.0, hpRatio = 0.50, atkRatio = 1.00, attrs = {
        [AD.PHYS_ARMOR] = 0.36, [AD.MAG_ARMOR] = 2.50,
    }},
    [46] = { quality = 5, name = "烛龙",     atkType = 7, armorType = 4, atkTargets = 2, atkInterval = 4.0, hpRatio = 0.29, atkRatio = 1.14, attrs = {
        [AD.DODGE] = 0.29, [AD.MAG_ARMOR] = 1.43, [AD.MAG_PEN] = 0.29,
    }},
    [47] = { quality = 3, name = "视肉",       atkType = 7, armorType = 5, atkTargets = 1, atkInterval = 2.2, hpRatio = 0.33, atkRatio = 1.47, attrs = {
        [AD.DODGE] = 0.17, [AD.HIT_VALUE] = 0.21, [AD.MAG_PEN] = 0.33,
    }},
    [48] = { quality = 2, name = "刑天",   atkType = 2, armorType = 2, atkTargets = 1, atkInterval = 2.4, hpRatio = 0.33, atkRatio = 1.60, attrs = {
        [AD.HIT_VALUE] = 0.21, [AD.PHYS_ARMOR] = 0.24, [AD.MAG_ARMOR] = 1.67,
    }},
    [49] = { quality = 3, name = "奢比之尸",       atkType = 7, armorType = 5, atkTargets = 1, atkInterval = 2.2, hpRatio = 0.40, atkRatio = 1.76, attrs = {
        [AD.DODGE] = 0.20, [AD.MAG_ARMOR] = 2.00, [AD.MAG_PEN] = 0.00,
    }},
    [50] = { quality = 5, name = "应龙",       atkType = 4, armorType = 4, atkTargets = 4, atkInterval = 4.4, hpRatio = 0.67, atkRatio = 0.37, attrs = {
        [AD.PHYS_ARMOR] = 0.24, [AD.MAG_ARMOR] = 1.67, [AD.HIT_VALUE] = 0.21,
    }},
    [51] = { quality = 2, name = "鸓",     atkType = 4, armorType = 2, atkTargets = 1, atkInterval = 2.4, hpRatio = 0.40, atkRatio = 1.92, attrs = {
        [AD.MAG_ARMOR] = 2.00, [AD.MAG_PEN] = 0.40,
    }},
    [52] = { quality = 5, name = "朱厌",       atkType = 4, armorType = 4, atkTargets = 3, atkInterval = 4.0, hpRatio = 0.33, atkRatio = 0.89, attrs = {
        [AD.MAG_ARMOR] = 1.67, [AD.MAG_PEN] = 0.33, [AD.HIT_VALUE] = 0.21,
    }},
    [53] = { quality = 2, name = "肥遗",     atkType = 3, armorType = 2, atkTargets = 1, atkInterval = 2.0, hpRatio = 0.80, atkRatio = 0.80, attrs = {
        [AD.PHYS_ARMOR] = 0.29, [AD.PHYS_PEN] = 0.40,
    }},
    [54] = { quality = 5, name = "巴蛇",       atkType = 3, armorType = 4, atkTargets = 2, atkInterval = 3.6, hpRatio = 0.67, atkRatio = 0.60, attrs = {
        [AD.PHYS_ARMOR] = 0.24, [AD.PHYS_PEN] = 0.33, [AD.DODGE] = 0.17,
    }},
    -- ---- 终焉神殿怪物 (至臻级) ----
    [1001] = { quality = 6, name = "帝江",      atkType = 1, armorType = 4, atkTargets = 2, atkInterval = 1.00, hpRatio = 0.67, atkRatio = 0.33, attrs = {
        [AD.PHYS_ARMOR] = 0.24, [AD.MAG_ARMOR] = 1.67,
    }},
    [1002] = { quality = 6, name = "夸娥",      atkType = 2, armorType = 2, atkTargets = 1, atkInterval = 5.00, hpRatio = 0.67, atkRatio = 1.67, attrs = {
        [AD.DODGE] = 0.17, [AD.PHYS_ARMOR] = 0.24, [AD.MAG_ARMOR] = 1.67,
    }},
    [1003] = { quality = 6, name = "共工",      atkType = 7, armorType = 5, atkTargets = 5, atkInterval = 5.00, hpRatio = 0.57, atkRatio = 0.57, attrs = {
        [AD.DODGE] = 0.14, [AD.ABNORMAL_RES] = 0.3, [AD.MAG_ARMOR] = 1.43,
    }},
    [1005] = { quality = 6, name = "大狗嚼?",    atkType = 1, armorType = 3, atkTargets = 1, atkInterval = 1.40, hpRatio = 1.33, atkRatio = 0.93, attrs = {} },
    [1006] = { quality = 6, name = "黄桃龙?",    atkType = 4, armorType = 5, atkTargets = 2, atkInterval = 2.60, hpRatio = 0.80, atkRatio = 0.52, attrs = {
        [AD.MAG_ARMOR] = 2.00, [AD.MAG_PEN] = 0.40,
    }},
    [1007] = { quality = 6, name = "叮咚鸡?",    atkType = 3, armorType = 2, atkTargets = 1, atkInterval = 2.00, hpRatio = 1.00, atkRatio = 1.00, attrs = {
        [AD.DODGE] = 0.25,
    }},
    -- ---- 剧情特殊怪物 ----
    [1004] = { quality = 5, name = "昆吾之怒", atkType = 2, armorType = 4, atkTargets = 2, atkInterval = 3.00, hpRatio = 1.00, atkRatio = 1.50, attrs = {} },
    -- ---- 副本怪物 ----
    [201] = { quality = 5, name = "陆吾·左臂",   atkType = 1, armorType = 1, atkTargets = 2, atkInterval = 1.50, hpRatio = 1.78, atkRatio = 0.67, attrs = {
        [AD.PHYS_ARMOR] = 0.32, [AD.MAG_ARMOR] = 2.22, [AD.ABNORMAL_RES] = 0.4,
    }},
    [202] = { quality = 5, name = "陆吾·金瞳",   atkType = 4, armorType = 5, atkTargets = 1, atkInterval = 3.00, hpRatio = 2.18, atkRatio = 2.18, attrs = {
        [AD.PHYS_ARMOR] = 0.26, [AD.MAG_ARMOR] = 1.82, [AD.ABNORMAL_RES] = 0.4,
    }},
    [203] = { quality = 5, name = "陆吾·右臂",   atkType = 2, armorType = 2, atkTargets = 3, atkInterval = 1.20, hpRatio = 1.78, atkRatio = 0.36, attrs = {
        [AD.PHYS_ARMOR] = 0.32, [AD.MAG_ARMOR] = 2.22, [AD.ABNORMAL_RES] = 0.4,
    }},
    [204] = { quality = 5, name = "开明兽·左臂",   atkType = 1, armorType = 3, atkTargets = 2, atkInterval = 1.50, hpRatio = 1.78, atkRatio = 0.67, attrs = {
        [AD.DODGE] = 0.22, [AD.PHYS_ARMOR] = 0.32, [AD.MAG_ARMOR] = 2.22,
    }},
    [205] = { quality = 5, name = "开明兽·九目",   atkType = 6, armorType = 4, atkTargets = 1, atkInterval = 3.00, hpRatio = 2.18, atkRatio = 2.18, attrs = {
        [AD.DODGE] = 0.18, [AD.PHYS_ARMOR] = 0.26, [AD.MAG_ARMOR] = 1.82,
    }},
    [206] = { quality = 5, name = "开明兽·右臂",   atkType = 2, armorType = 2, atkTargets = 3, atkInterval = 1.20, hpRatio = 1.78, atkRatio = 0.36, attrs = {
        [AD.DODGE] = 0.22, [AD.PHYS_ARMOR] = 0.32, [AD.MAG_ARMOR] = 2.22,
    }},
}

-- ======================== 远程怪物集合 ========================
-- 数据来源: docs/配置文件/怪物配置.txt "是否远程" 列（值为1=远程）
-- 不在此集合中的怪物视为近战

MC.MONSTER_RANGED = {
    [2]  = true,  -- 森林精灵
    [5]  = true,  -- 哥布林牧师
    [6]  = true,  -- 哥布林猎手
    [8]  = true,  -- 森之巨灵
    [10] = true,  -- 豺狼人猎手
    [12] = true,  -- 猎鹰
    [13] = true,  -- 蝎子
    [16] = true,  -- 盗贼领主
    [17] = true,  -- 火烈鸟
    [18] = true,  -- 火焰元素
    [19] = true,  -- 半人马弓手
    [24] = true,  -- 白熊
    [27] = true,  -- 水元素
    [29] = true,  -- 雪怪
    [33] = true,  -- 血浴之母
    [34] = true,  -- 远古灵兽
    [38] = true,  -- 潮汐海灵
    [41] = true,  -- 幽灵看守者
    [42] = true,  -- 邪教徒
    [46] = true,  -- 幽冥龙
    [47] = true,  -- 幽灵
    [49] = true,  -- 怨灵
    [50] = true,  -- 骨龙
    [51] = true,  -- 红幼龙
    [52] = true,  -- 红龙
    [53] = true,  -- 绿幼龙
    [54] = true,  -- 绿龙
    -- ---- 终焉神殿 ----
    [1003] = true, -- ??? (暗影远程)
    [1006] = true, -- 黄桃龙? (火焰远程)
    [1007] = true, -- 叮咚鸡? (穿刺远程)
}

-- ======================== 怪物攻击特效映射 ========================
-- monsterId → 攻击特效Key（所有怪物均有特效）
-- 数据来源: docs/配置文件/怪物配置.txt "攻击特效调用" 列

MC.MONSTER_EFFECTS = {
    -- ---- 近战怪物 ----
    [1]  = "EF_MS_1",    -- 野狼
    [3]  = "EF_ATK_1",   -- 哥布林
    [4]  = "EF_MS_13",   -- 森林蜘蛛
    [7]  = "EF_MS_7",    -- 邪恶之狼
    [9]  = "EF_MS_9",    -- 丛林巨兽
    [11] = "EF_ATK_11",  -- 豺狼人杀手
    [14] = "EF_MS_1",    -- 强盗
    [15] = "EF_MS_1",    -- 土匪
    [20] = "EF_ATK_5",   -- 半人马处刑者
    [21] = "EF_ATK_5",   -- 半人马领主
    [22] = "EF_MS_22",   -- 熊怪
    [23] = "EF_MS_22",   -- 熊怪精英
    [25] = "EF_MS_22",   -- 熊怪领主
    [26] = "EF_ATK_8",   -- 巨龟
    [28] = "EF_ATK_8",   -- 龙龟
    [30] = "EF_MS_30",   -- 冰原狼
    [31] = "EF_MS_7",    -- 黑狼王(复用邪恶之狼)
    [32] = "EF_MS_13",   -- 血蜘蛛
    [35] = "EF_ATK_5",   -- 远古巨兽
    [36] = "EF_MS_36",   -- 石巨人
    [37] = "EF_MS_30",   -- 大虾(复用冰原狼)
    [39] = "EF_MS_39",   -- 深海巨人
    [40] = "EF_MS_47",   -- 被诅咒者
    [43] = "EF_MS_43",   -- 地狱石巨人
    [44] = "EF_MS_1",    -- 僵尸
    [45] = "EF_ATK_1",   -- 骷髅战士
    [48] = "EF_ATK_11",  -- 野蛮骷髅
    -- ---- 远程怪物 ----
    [2]  = "EF_ATK_6",   -- 森林精灵 → 闪电链
    [5]  = "EF_ATK_9",   -- 哥布林牧师 → 贝塞尔
    [6]  = "EF_ATK_3",   -- 哥布林猎手 → 箭矢
    [8]  = "EF_MS_8",    -- 森之巨灵 → 直线
    [10] = "EF_ATK_3",   -- 豺狼人猎手 → 箭矢
    [12] = "EF_ATK_6",   -- 猎鹰 → 闪电链
    [13] = "EF_MS_13",   -- 蝎子 → 针刺直线
    [16] = "EF_MS_16",   -- 盗贼领主 → 飞斧旋转贝塞尔
    [17] = "EF_ATK_2",   -- 火烈鸟 → 火球
    [18] = "EF_ATK_2",   -- 火焰元素 → 火球
    [19] = "EF_ATK_3",   -- 半人马弓手 → 箭矢
    [24] = "EF_MS_24",   -- 白熊 → 直线
    [27] = "EF_MS_27",   -- 水元素 → 直线
    [29] = "EF_MS_24",   -- 雪怪 → 直线(复用白熊)
    [33] = "EF_MS_13",   -- 血浴之母 → 针刺直线(复用蝎子)
    [34] = "EF_MS_8",    -- 远古灵兽 → 直线(复用森之巨灵)
    [38] = "EF_MS_24",   -- 潮汐海灵 → 直线(复用白熊)
    [41] = "EF_ATK_13",  -- 幽灵看守者 → 能量箭
    [42] = "EF_ZY_106",  -- 邪教徒 → 贝塞尔
    [46] = "EF_MS_46",   -- 幽冥龙 → 直线
    [47] = "EF_MS_47",   -- 幽灵 → 贝塞尔
    [49] = "EF_MS_7",    -- 怨灵 → 爪击抖动(复用邪恶之狼)
    [50] = "EF_MS_46",   -- 骨龙 → 直线(复用幽冥龙)
    [51] = "EF_MS_50",   -- 红幼龙 → 直线
    [52] = "EF_MS_50",   -- 红龙 → 直线(复用红幼龙)
    [53] = "EF_MS_53",   -- 绿幼龙 → 直线
    [54] = "EF_MS_53",   -- 绿龙 → 直线(复用绿幼龙)
    -- ---- 终焉神殿怪物 ----
    [1001] = "EF_MS_7",   -- ??? (近战斩击)
    [1002] = "EF_MS_36",  -- ??? (近战粉碎)
    [1003] = "EF_MS_47",  -- ??? (远程暗影)
    [1005] = "EF_ATK_1",  -- 大狗嚼? (近战斩击)
    [1006] = "EF_ATK_2",  -- 黄桃龙? (远程火焰)
    [1007] = "EF_ATK_3",  -- 叮咚鸡? (远程穿刺)
    -- ---- 剧情特殊怪物 ----
    [1004] = "EF_MS_39",  -- 昆吾之怒 (近战粉碎，复用深海巨人特效)
    -- ---- 副本怪物 ----
    [201] = "EF_ATK_4",   -- 石魔左臂
    [202] = "EF_MS_43",   -- 金幽石魔
    [203] = "EF_MS_8",    -- 石魔右臂
    [204] = "EF_ATK_1",   -- 石像左臂
    [205] = "EF_ATK_10",  -- 遗迹石像
    [206] = "EF_ATK_11",  -- 石像右臂
}

-- ======================== 工厂函数 ========================

--- 根据怪物ID和等级创建战斗单位
---@param monsterId number 怪物模板ID (1~54, 1001~1003)
---@param level number 怪物等级 (1~345)
---@param opts table|nil 可选 { statMult=number } 额外属性倍率（通天塔等）
---@return table|nil 战斗单位
function MC.createMonster(monsterId, level, opts)
    opts = opts or {}
    local statMult = opts.statMult or 1.0
    if statMult <= 0 then statMult = 1.0 end
    local template = MC.MONSTERS[monsterId]
    if not template then
        print("[MonsterConfig] ERROR: monsterId " .. tostring(monsterId) .. " not found")
        return nil
    end

    if level > MC.MAX_LEVEL then
        print("[MonsterConfig] WARNING: level " .. tostring(level) .. " clamped to " .. MC.MAX_LEVEL)
        level = MC.MAX_LEVEL
    end

    local levelData = MC.LEVELS[level]
    if not levelData then
        levelData = MC.LEVELS[MC.MAX_LEVEL]
        print("[MonsterConfig] WARNING: level " .. tostring(level) .. " missing, fallback to " .. MC.MAX_LEVEL)
    end

    local qualityData = MC.QUALITY[template.quality]

    -- 计算基础属性（模板比率 × 品质系数 × 可选倍率）
    local maxHp = math.floor(levelData.baseHp * template.hpRatio * qualityData.hpMult * statMult + 0.5)
    local baseAtk = levelData.baseAtk * template.atkRatio * qualityData.atkMult * statMult
    local attrScale = levelData.attrScale / 100  -- 5% → 0.05

    -- 根据攻击类型确定攻击力类别
    local category = AD.getAtkCategory(template.atkType)

    ---@type table<any, any>
    local cfg = {
        [AD.MAX_HP]       = maxHp,
        [AD.ATK_INTERVAL] = template.atkInterval,
        armorType         = template.armorType,
        atkType           = template.atkType,
    }

    if category == "physical" then
        cfg[AD.PHYS_ATK] = baseAtk
    elseif category == "magical" then
        cfg[AD.MAG_ATK] = baseAtk
    elseif category == "healing" then
        -- 神圣类型：设置治疗量，同时给一个小额魔法攻击力作为后备
        cfg[AD.HEAL_AMOUNT] = baseAtk
        cfg[AD.MAG_ATK] = baseAtk * 0.3
    end

    -- 应用额外属性（基础值 × 等级增强 × 品质系数 × 可选倍率）
    for attrKey, value in pairs(template.attrs) do
        cfg[attrKey] = value * (1 + attrScale) * qualityData.attrMult * statMult
    end

    -- 创建属性容器
    local attrs = UnitAttributes.create(cfg)
    attrs:fillHp()

    -- 构建战斗单位
    local unit = attrs:toBattleUnit(template.name, level)
    unit.atkInterval = attrs:getActualInterval()
    unit.monsterId   = monsterId
    unit.quality     = template.quality
    unit.qualityName = qualityData.name
    unit.qualityColor = qualityData.color
    unit.expReward   = math.floor(levelData.baseExp * qualityData.expMult + 0.5)
    unit.goldReward  = math.floor(levelData.goldDrop * qualityData.goldMult + 0.5)
    unit.atkEffect   = MC.MONSTER_EFFECTS[monsterId]
    unit.isRanged    = MC.MONSTER_RANGED[monsterId] or false  -- 远程/近战标志
    unit.atkTargets  = template.atkTargets             -- 攻击目标数 (1~4)
    _instanceCounter = _instanceCounter + 1
    unit.instanceId  = _instanceCounter               -- 实例唯一ID，供 findUnitIndex 精确定位

    return unit
end

-- ======================== 辅助方法 ========================

--- 获取怪物名称
---@param monsterId number
---@return string
function MC.getName(monsterId)
    local t = MC.MONSTERS[monsterId]
    return t and t.name or ("未知#" .. tostring(monsterId))
end

--- 获取所有怪物ID列表（排序）
---@return number[]
function MC.getAllIds()
    local ids = {}
    for id in pairs(MC.MONSTERS) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

--- 获取指定品质的怪物ID列表
---@param quality number 品质等级 (1~6)
---@return number[]
function MC.getIdsByQuality(quality)
    local ids = {}
    for id, m in pairs(MC.MONSTERS) do
        if m.quality == quality then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

--- 获取品质颜色的 RGBA (用于 NanoVG)
---@param quality number
---@return number r, number g, number b
function MC.getQualityColorRGB(quality)
    local q = MC.QUALITY[quality]
    if not q or not q.color then
        return 255, 255, 255  -- 普通级白色
    end
    local hex = q.color
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return r, g, b
end

return MC
