-- ============================================================================
-- ExpTable - 经验表配置（双端共享）
-- 来源: docs/配置文件/经验表配置.txt
-- ============================================================================
--
-- 冒险家 = 英雄（hero），最高 200 级封顶
-- 冒险等级 = 玩家等级（player），最高 200 级
--
-- 每条记录: { 当级所需经验 }
-- 索引 = 等级（Lua 从 1 开始）
-- ============================================================================

local ExpTable = {}

--- 冒险家（英雄）升级所需经验表
--- hero[lv] = 从 lv 升到 lv+1 所需经验
--- 最大可升至 199→200，hero[200] 不存在表示满级
ExpTable.hero = {
    [1] = 20, [2] = 226, [3] = 935, [4] = 2560, [5] = 5590,
    [6] = 10581, [7] = 18149, [8] = 28963, [9] = 43740, [10] = 63245,
    [11] = 88288, [12] = 119719, [13] = 158427, [14] = 205342, [15] = 261426,
    [16] = 327680, [17] = 405136, [18] = 494861, [19] = 597953, [20] = 715541,
    [21] = 848784, [22] = 998870, [23] = 1167017, [24] = 1354469, [25] = 1562500,
    [26] = 1792407, [27] = 2045517, [28] = 2323181, [29] = 2626775, [30] = 2957701,
    [31] = 3317385, [32] = 3707276, [33] = 4128846, [34] = 4583594, [35] = 5073038,
    [36] = 5598720, [37] = 6162203, [38] = 6765074, [39] = 7408940, [40] = 8095430,
    [41] = 8826194, [42] = 9602902, [43] = 10427245, [44] = 11300934, [45] = 12225701,
    [46] = 13203297, [47] = 14235492, [48] = 15324077, [49] = 16470860, [50] = 17677669,
    [51] = 18946352, [52] = 20278774, [53] = 21676818, [54] = 23142387, [55] = 24677400,
    [56] = 26283796, [57] = 27963529, [58] = 29718574, [59] = 31550920, [60] = 33462576,
    [61] = 35455565, [62] = 37531930, [63] = 39693730, [64] = 41943040, [65] = 44281950,
    [66] = 46712570, [67] = 49237025, [68] = 51857453, [69] = 54576013, [70] = 57394877,
    [71] = 60316233, [72] = 63342286, [73] = 66475254, [74] = 69717373, [75] = 73070893,
    [76] = 76538080, [77] = 80121216, [78] = 83822595, [79] = 87644529, [80] = 91589344,
    [81] = 95659380, [82] = 99856991, [83] = 104184549, [84] = 108644437, [85] = 113239054,
    [86] = 117970813, [87] = 122842141, [88] = 127855480, [89] = 133013284, [90] = 138318024,
    [91] = 143772183, [92] = 149378258, [93] = 155138759, [94] = 161056213, [95] = 167133156,
    [96] = 173372140, [97] = 179775731, [98] = 186346508, [99] = 193087063, [100] = 200000000,
    [101] = 207087938, [102] = 214353508, [103] = 221799356, [104] = 229428139, [105] = 237242527,
    [106] = 245245204, [107] = 253438866, [108] = 261826222, [109] = 270409993, [110] = 279192915,
    [111] = 288177733, [112] = 297367207, [113] = 306764110, [114] = 316371224, [115] = 326191347,
    [116] = 336227288, [117] = 346481867, [118] = 356957919, [119] = 367658287, [120] = 378585831,
    [121] = 389743420, [122] = 401133934, [123] = 412760267, [124] = 424625326, [125] = 436732026,
    [126] = 449083298, [127] = 461682081, [128] = 474531328, [129] = 487634003, [130] = 500993081,
    [131] = 514611551, [132] = 528492410, [133] = 542638669, [134] = 557053349, [135] = 571739484,
    [136] = 586700117, [137] = 601938304, [138] = 617457113, [139] = 633259620, [140] = 649348916,
    [141] = 665728101, [142] = 682400287, [143] = 699368595, [144] = 716636160, [145] = 734206125,
    [146] = 752081647, [147] = 770265891, [148] = 788762036, [149] = 807573268, [150] = 826702788,
    [151] = 846153803, [152] = 865929536, [153] = 886033216, [154] = 906468086, [155] = 927237397,
    [156] = 948344412, [157] = 969792406, [158] = 991584661, [159] = 1013724471, [160] = 1036215143,
    [161] = 1059059991, [162] = 1082262340, [163] = 1105825527, [164] = 1129752897, [165] = 1154047807,
    [166] = 1178713625, [167] = 1203753726, [168] = 1229171499, [169] = 1254970340, [170] = 1281153656,
    [171] = 1307724866, [172] = 1334687397, [173] = 1362044687, [174] = 1389800183, [175] = 1417957343,
    [176] = 1446519634, [177] = 1475490535, [178] = 1504873531, [179] = 1534672122, [180] = 1564889813,
    [181] = 1595530122, [182] = 1626596575, [183] = 1658092709, [184] = 1690022070, [185] = 1722388214,
    [186] = 1755194706, [187] = 1788445122, [188] = 1822143046, [189] = 1856292073, [190] = 1890895807,
    [191] = 1925957862, [192] = 1961481860, [193] = 1997471434, [194] = 2033930226, [195] = 2070861887,
    [196] = 2108270080, [197] = 2146158472, [198] = 2184530746, [199] = 2223390589,
}

--- 冒险等级（玩家）升级所需经验表
--- player[lv] = 从 lv 升到 lv+1 所需经验
--- 最大可升至 199→200，player[200] 不存在表示满级
ExpTable.player = {
    [1] = 100, [2] = 1131, [3] = 4676, [4] = 12800, [5] = 27950,
    [6] = 52908, [7] = 90749, [8] = 144815, [9] = 218700, [10] = 316227,
    [11] = 441442, [12] = 598596, [13] = 792139, [14] = 1026710, [15] = 1307131,
    [16] = 1638400, [17] = 2025681, [18] = 2474308, [19] = 2989768, [20] = 3577708,
    [21] = 4243923, [22] = 4994354, [23] = 5835088, [24] = 6772349, [25] = 7812500,
    [26] = 8962036, [27] = 10227586, [28] = 11615906, [29] = 13133878, [30] = 14788509,
    [31] = 16586926, [32] = 18536380, [33] = 20644234, [34] = 22917973, [35] = 25365192,
    [36] = 27993600, [37] = 30811017, [38] = 33825372, [39] = 37044703, [40] = 40477154,
    [41] = 44130972, [42] = 48014511, [43] = 52136226, [44] = 56504673, [45] = 61128508,
    [46] = 66016487, [47] = 71177462, [48] = 76620385, [49] = 82354300, [50] = 88388347,
    [51] = 94731762, [52] = 101393870, [53] = 108384091, [54] = 115711935, [55] = 123387002,
    [56] = 131418980, [57] = 139817648, [58] = 148592872, [59] = 157754603, [60] = 167312880,
    [61] = 177277828, [62] = 187659654, [63] = 198468653, [64] = 209715200, [65] = 221409753,
    [66] = 233562854, [67] = 246185125, [68] = 259287269, [69] = 272880069, [70] = 286974389,
    [71] = 301581169, [72] = 316711430, [73] = 332376270, [74] = 348586865, [75] = 365354467,
    [76] = 382690404, [77] = 400606081, [78] = 419112978, [79] = 438222648, [80] = 457946721,
    [81] = 478296900, [82] = 499284959, [83] = 520922748, [84] = 543222188, [85] = 566195273,
    [86] = 589854068, [87] = 614210708, [88] = 639277401, [89] = 665066424, [90] = 691590124,
    [91] = 718860917, [92] = 746891291, [93] = 775693799, [94] = 805281065, [95] = 835665780,
    [96] = 866860702, [97] = 898878659, [98] = 931732543, [99] = 965435315, [100] = 1000000000,
    [101] = 1035439690, [102] = 1071767543, [103] = 1108996783, [104] = 1147140697, [105] = 1186212638,
    [106] = 1226226022, [107] = 1267194332, [108] = 1309131112, [109] = 1352049969, [110] = 1395964576,
    [111] = 1440888667, [112] = 1486836039, [113] = 1533820550, [114] = 1581856122, [115] = 1630956737,
    [116] = 1681136441, [117] = 1732409338, [118] = 1784789595, [119] = 1838291439, [120] = 1892929158,
    [121] = 1948717100, [122] = 2005669671, [123] = 2063801339, [124] = 2123126632, [125] = 2183660134,
    [126] = 2245416491, [127] = 2308410405, [128] = 2372656640, [129] = 2438170015, [130] = 2504965408,
    [131] = 2573057756, [132] = 2642462052, [133] = 2713193346, [134] = 2785266747, [135] = 2858697420,
    [136] = 2933500585, [137] = 3009691522, [138] = 3087285565, [139] = 3166298104, [140] = 3246744584,
    [141] = 3328640509, [142] = 3412001436, [143] = 3496842977, [144] = 3583180800, [145] = 3671030627,
    [146] = 3760408236, [147] = 3851329459, [148] = 3943810181, [149] = 4037866344,
    [150] = 4133513940, [151] = 4230769019, [152] = 4329647682, [153] = 4430166083, [154] = 4532340430,
    [155] = 4636186986, [156] = 4741722064, [157] = 4848962030, [158] = 4957923305, [159] = 5068622359,
    [160] = 5181075718, [161] = 5295299956, [162] = 5411311702, [163] = 5529127635, [164] = 5648764487,
    [165] = 5770239039, [166] = 5893568126, [167] = 6018768633, [168] = 6145857495, [169] = 6274851700,
    [170] = 6405768283, [171] = 6538624333, [172] = 6673436988, [173] = 6810223437, [174] = 6949000916,
    [175] = 7089786716, [176] = 7232598173, [177] = 7377452675, [178] = 7524367658, [179] = 7673360610,
    [180] = 7824449066, [181] = 7977650611, [182] = 8132982877, [183] = 8290463546, [184] = 8450110351,
    [185] = 8611941070, [186] = 8775973532, [187] = 8942225611, [188] = 9110715232, [189] = 9281460368,
    [190] = 9454479039, [191] = 9629789311, [192] = 9807409301, [193] = 9987357170, [194] = 10169651131,
    [195] = 10354309439, [196] = 10541350400, [197] = 10730792364, [198] = 10922653731, [199] = 11116952945,
}

--- 冒险家 HP 成长全局系数（生命 = 累计 hp 成长 × 此系数）
ExpTable.HERO_HP_GROWTH_MULT = 1.2

--- 冒险家每级基础战斗属性成长（等级段见 docs/配置文件/经验表配置.txt）
--- heroBaseGrowth[lv] = 从 lv 升到 lv+1 每级获得的 {hp, atk}（hp 再乘 HERO_HP_GROWTH_MULT）
ExpTable.heroBaseGrowth = {
    [1] = { hp = 60, atk = 3.0 }, [2] = { hp = 60, atk = 3.0 }, [3] = { hp = 60, atk = 3.0 }, [4] = { hp = 60, atk = 3.0 }, [5] = { hp = 60, atk = 3.0 },
    [6] = { hp = 60, atk = 3.0 }, [7] = { hp = 60, atk = 3.0 }, [8] = { hp = 60, atk = 3.0 }, [9] = { hp = 60, atk = 3.0 }, [10] = { hp = 60, atk = 3.0 },
    [11] = { hp = 72, atk = 3.5 }, [12] = { hp = 72, atk = 3.5 }, [13] = { hp = 72, atk = 3.5 }, [14] = { hp = 72, atk = 3.5 }, [15] = { hp = 72, atk = 3.5 },
    [16] = { hp = 72, atk = 3.5 }, [17] = { hp = 72, atk = 3.5 }, [18] = { hp = 72, atk = 3.5 }, [19] = { hp = 72, atk = 3.5 }, [20] = { hp = 72, atk = 3.5 },
    [21] = { hp = 84, atk = 4.0 }, [22] = { hp = 84, atk = 4.0 }, [23] = { hp = 84, atk = 4.0 }, [24] = { hp = 84, atk = 4.0 }, [25] = { hp = 84, atk = 4.0 },
    [26] = { hp = 84, atk = 4.0 }, [27] = { hp = 84, atk = 4.0 }, [28] = { hp = 84, atk = 4.0 }, [29] = { hp = 84, atk = 4.0 }, [30] = { hp = 84, atk = 4.0 },
    [31] = { hp = 102, atk = 5.0 }, [32] = { hp = 102, atk = 5.0 }, [33] = { hp = 102, atk = 5.0 }, [34] = { hp = 102, atk = 5.0 }, [35] = { hp = 102, atk = 5.0 },
    [36] = { hp = 102, atk = 5.0 }, [37] = { hp = 102, atk = 5.0 }, [38] = { hp = 102, atk = 5.0 }, [39] = { hp = 102, atk = 5.0 }, [40] = { hp = 102, atk = 5.0 },
    [41] = { hp = 120, atk = 6.0 }, [42] = { hp = 120, atk = 6.0 }, [43] = { hp = 120, atk = 6.0 }, [44] = { hp = 120, atk = 6.0 }, [45] = { hp = 120, atk = 6.0 },
    [46] = { hp = 120, atk = 6.0 }, [47] = { hp = 120, atk = 6.0 }, [48] = { hp = 120, atk = 6.0 }, [49] = { hp = 120, atk = 6.0 }, [50] = { hp = 120, atk = 6.0 },
    [51] = { hp = 144, atk = 7.5 }, [52] = { hp = 144, atk = 7.5 }, [53] = { hp = 144, atk = 7.5 }, [54] = { hp = 144, atk = 7.5 }, [55] = { hp = 144, atk = 7.5 },
    [56] = { hp = 144, atk = 7.5 }, [57] = { hp = 144, atk = 7.5 }, [58] = { hp = 144, atk = 7.5 }, [59] = { hp = 144, atk = 7.5 }, [60] = { hp = 144, atk = 7.5 },
    [61] = { hp = 168, atk = 9.0 }, [62] = { hp = 168, atk = 9.0 }, [63] = { hp = 168, atk = 9.0 }, [64] = { hp = 168, atk = 9.0 }, [65] = { hp = 168, atk = 9.0 },
    [66] = { hp = 168, atk = 9.0 }, [67] = { hp = 168, atk = 9.0 }, [68] = { hp = 168, atk = 9.0 }, [69] = { hp = 168, atk = 9.0 }, [70] = { hp = 168, atk = 9.0 },
    [71] = { hp = 198, atk = 11.0 }, [72] = { hp = 198, atk = 11.0 }, [73] = { hp = 198, atk = 11.0 }, [74] = { hp = 198, atk = 11.0 }, [75] = { hp = 198, atk = 11.0 },
    [76] = { hp = 198, atk = 11.0 }, [77] = { hp = 198, atk = 11.0 }, [78] = { hp = 198, atk = 11.0 }, [79] = { hp = 198, atk = 11.0 }, [80] = { hp = 198, atk = 11.0 },
    [81] = { hp = 234, atk = 13.0 }, [82] = { hp = 234, atk = 13.0 }, [83] = { hp = 234, atk = 13.0 }, [84] = { hp = 234, atk = 13.0 }, [85] = { hp = 234, atk = 13.0 },
    [86] = { hp = 234, atk = 13.0 }, [87] = { hp = 234, atk = 13.0 }, [88] = { hp = 234, atk = 13.0 }, [89] = { hp = 234, atk = 13.0 }, [90] = { hp = 234, atk = 13.0 },
    [91] = { hp = 276, atk = 15.5 }, [92] = { hp = 276, atk = 15.5 }, [93] = { hp = 276, atk = 15.5 }, [94] = { hp = 276, atk = 15.5 }, [95] = { hp = 276, atk = 15.5 },
    [96] = { hp = 276, atk = 15.5 }, [97] = { hp = 276, atk = 15.5 }, [98] = { hp = 276, atk = 15.5 }, [99] = { hp = 276, atk = 15.5 }, [100] = { hp = 276, atk = 15.5 },
    [101] = { hp = 276, atk = 15.5 }, [102] = { hp = 276, atk = 15.5 }, [103] = { hp = 276, atk = 15.5 }, [104] = { hp = 276, atk = 15.5 }, [105] = { hp = 276, atk = 15.5 },
    [106] = { hp = 276, atk = 15.5 }, [107] = { hp = 276, atk = 15.5 }, [108] = { hp = 276, atk = 15.5 }, [109] = { hp = 276, atk = 15.5 }, [110] = { hp = 276, atk = 15.5 },
    [111] = { hp = 276, atk = 15.5 }, [112] = { hp = 276, atk = 15.5 }, [113] = { hp = 276, atk = 15.5 }, [114] = { hp = 276, atk = 15.5 }, [115] = { hp = 276, atk = 15.5 },
    [116] = { hp = 276, atk = 15.5 }, [117] = { hp = 276, atk = 15.5 }, [118] = { hp = 276, atk = 15.5 }, [119] = { hp = 276, atk = 15.5 }, [120] = { hp = 276, atk = 15.5 },
    [121] = { hp = 276, atk = 15.5 }, [122] = { hp = 276, atk = 15.5 }, [123] = { hp = 276, atk = 15.5 }, [124] = { hp = 276, atk = 15.5 }, [125] = { hp = 276, atk = 15.5 },
    [126] = { hp = 276, atk = 15.5 }, [127] = { hp = 276, atk = 15.5 }, [128] = { hp = 276, atk = 15.5 }, [129] = { hp = 276, atk = 15.5 }, [130] = { hp = 276, atk = 15.5 },
    [131] = { hp = 276, atk = 15.5 }, [132] = { hp = 276, atk = 15.5 }, [133] = { hp = 276, atk = 15.5 }, [134] = { hp = 276, atk = 15.5 }, [135] = { hp = 276, atk = 15.5 },
    [136] = { hp = 276, atk = 15.5 }, [137] = { hp = 276, atk = 15.5 }, [138] = { hp = 276, atk = 15.5 }, [139] = { hp = 276, atk = 15.5 }, [140] = { hp = 276, atk = 15.5 },
    [141] = { hp = 276, atk = 15.5 }, [142] = { hp = 276, atk = 15.5 }, [143] = { hp = 276, atk = 15.5 }, [144] = { hp = 276, atk = 15.5 }, [145] = { hp = 276, atk = 15.5 },
    [146] = { hp = 276, atk = 15.5 }, [147] = { hp = 276, atk = 15.5 }, [148] = { hp = 276, atk = 15.5 }, [149] = { hp = 276, atk = 15.5 },
}

for lv = 150, 199 do
    ExpTable.heroBaseGrowth[lv] = { hp = 276, atk = 15.5 }
end

ExpTable.heroCountExpMult = {
    [1] = 1.00,
    [2] = 1.50,
    [3] = 2.00,
    [4] = 2.50,
    [5] = 3.00,
}

--- 冒险等级解锁内容表（按等级）
--- 仅保留槽位解锁；建筑解锁由新手引导系统管理，不再在此处配置
--- unlockName = 解锁内容名称
--- 每个冒险等级（2~200）提升后，装备槽位强化等级上限 +1
ExpTable.levelUnlocks = {
    [2]  = { { unlockName = "出战槽位+1" },   { unlockName = "装备强化上限+1" } },
    [3]  = { { unlockName = "装备强化上限+1" } },
    [4]  = { { unlockName = "装备强化上限+1" } },
    [5]  = { { unlockName = "装备强化上限+1" } },
    [6]  = { { unlockName = "出战槽位+1" },   { unlockName = "装备强化上限+1" } },
    [7]  = { { unlockName = "装备强化上限+1" } },
    [8]  = { { unlockName = "装备强化上限+1" } },
    [9]  = { { unlockName = "装备强化上限+1" } },
    [10] = { { unlockName = "出战槽位+1" },   { unlockName = "装备强化上限+1" } },
    [11] = { { unlockName = "装备强化上限+1" } },
    [12] = { { unlockName = "装备强化上限+1" } },
    [13] = { { unlockName = "装备强化上限+1" } },
    [14] = { { unlockName = "装备强化上限+1" } },
    [15] = { { unlockName = "装备强化上限+1" } },
    [16] = { { unlockName = "装备强化上限+1" } },
    [17] = { { unlockName = "装备强化上限+1" } },
    [18] = { { unlockName = "装备强化上限+1" } },
    [19] = { { unlockName = "装备强化上限+1" } },
    [20] = { { unlockName = "装备强化上限+1" } },
    [21] = { { unlockName = "装备强化上限+1" } },
    [22] = { { unlockName = "装备强化上限+1" } },
    [23] = { { unlockName = "装备强化上限+1" } },
    [24] = { { unlockName = "装备强化上限+1" } },
    [25] = { { unlockName = "装备强化上限+1" } },
    [26] = { { unlockName = "装备强化上限+1" } },
    [27] = { { unlockName = "装备强化上限+1" } },
    [28] = { { unlockName = "装备强化上限+1" } },
    [29] = { { unlockName = "装备强化上限+1" } },
    [30] = { { unlockName = "装备强化上限+1" } },
    [31] = { { unlockName = "装备强化上限+1" } },
    [32] = { { unlockName = "装备强化上限+1" } },
    [33] = { { unlockName = "装备强化上限+1" } },
    [34] = { { unlockName = "装备强化上限+1" } },
    [35] = { { unlockName = "装备强化上限+1" } },
    [36] = { { unlockName = "装备强化上限+1" } },
    [37] = { { unlockName = "装备强化上限+1" } },
    [38] = { { unlockName = "装备强化上限+1" } },
    [39] = { { unlockName = "装备强化上限+1" } },
    [40] = { { unlockName = "装备强化上限+1" } },
    [41] = { { unlockName = "装备强化上限+1" } },
    [42] = { { unlockName = "装备强化上限+1" } },
    [43] = { { unlockName = "装备强化上限+1" } },
    [44] = { { unlockName = "装备强化上限+1" } },
    [45] = { { unlockName = "装备强化上限+1" } },
    [46] = { { unlockName = "装备强化上限+1" } },
    [47] = { { unlockName = "装备强化上限+1" } },
    [48] = { { unlockName = "装备强化上限+1" } },
    [49] = { { unlockName = "装备强化上限+1" } },
    [50] = { { unlockName = "装备强化上限+1" } },
    [51] = { { unlockName = "装备强化上限+1" } },
    [52] = { { unlockName = "装备强化上限+1" } },
    [53] = { { unlockName = "装备强化上限+1" } },
    [54] = { { unlockName = "装备强化上限+1" } },
    [55] = { { unlockName = "装备强化上限+1" } },
    [56] = { { unlockName = "装备强化上限+1" } },
    [57] = { { unlockName = "装备强化上限+1" } },
    [58] = { { unlockName = "装备强化上限+1" } },
    [59] = { { unlockName = "装备强化上限+1" } },
    [60] = { { unlockName = "装备强化上限+1" } },
    [61] = { { unlockName = "装备强化上限+1" } },
    [62] = { { unlockName = "装备强化上限+1" } },
    [63] = { { unlockName = "装备强化上限+1" } },
    [64] = { { unlockName = "装备强化上限+1" } },
    [65] = { { unlockName = "装备强化上限+1" } },
    [66] = { { unlockName = "装备强化上限+1" } },
    [67] = { { unlockName = "装备强化上限+1" } },
    [68] = { { unlockName = "装备强化上限+1" } },
    [69] = { { unlockName = "装备强化上限+1" } },
    [70] = { { unlockName = "装备强化上限+1" } },
    [71] = { { unlockName = "装备强化上限+1" } },
    [72] = { { unlockName = "装备强化上限+1" } },
    [73] = { { unlockName = "装备强化上限+1" } },
    [74] = { { unlockName = "装备强化上限+1" } },
    [75] = { { unlockName = "装备强化上限+1" } },
    [76] = { { unlockName = "装备强化上限+1" } },
    [77] = { { unlockName = "装备强化上限+1" } },
    [78] = { { unlockName = "装备强化上限+1" } },
    [79] = { { unlockName = "装备强化上限+1" } },
    [80] = { { unlockName = "装备强化上限+1" } },
    [81] = { { unlockName = "装备强化上限+1" } },
    [82] = { { unlockName = "装备强化上限+1" } },
    [83] = { { unlockName = "装备强化上限+1" } },
    [84] = { { unlockName = "装备强化上限+1" } },
    [85] = { { unlockName = "装备强化上限+1" } },
    [86] = { { unlockName = "装备强化上限+1" } },
    [87] = { { unlockName = "装备强化上限+1" } },
    [88] = { { unlockName = "装备强化上限+1" } },
    [89] = { { unlockName = "装备强化上限+1" } },
    [90] = { { unlockName = "装备强化上限+1" } },
    [91] = { { unlockName = "装备强化上限+1" } },
    [92] = { { unlockName = "装备强化上限+1" } },
    [93] = { { unlockName = "装备强化上限+1" } },
    [94] = { { unlockName = "装备强化上限+1" } },
    [95] = { { unlockName = "装备强化上限+1" } },
    [96] = { { unlockName = "装备强化上限+1" } },
    [97] = { { unlockName = "装备强化上限+1" } },
    [98] = { { unlockName = "装备强化上限+1" } },
    [99] = { { unlockName = "装备强化上限+1" } },
    [100] = { { unlockName = "装备强化上限+1" } },
    [101] = { { unlockName = "装备强化上限+1" } },
    [102] = { { unlockName = "装备强化上限+1" } },
    [103] = { { unlockName = "装备强化上限+1" } },
    [104] = { { unlockName = "装备强化上限+1" } },
    [105] = { { unlockName = "装备强化上限+1" } },
    [106] = { { unlockName = "装备强化上限+1" } },
    [107] = { { unlockName = "装备强化上限+1" } },
    [108] = { { unlockName = "装备强化上限+1" } },
    [109] = { { unlockName = "装备强化上限+1" } },
    [110] = { { unlockName = "装备强化上限+1" } },
    [111] = { { unlockName = "装备强化上限+1" } },
    [112] = { { unlockName = "装备强化上限+1" } },
    [113] = { { unlockName = "装备强化上限+1" } },
    [114] = { { unlockName = "装备强化上限+1" } },
    [115] = { { unlockName = "装备强化上限+1" } },
    [116] = { { unlockName = "装备强化上限+1" } },
    [117] = { { unlockName = "装备强化上限+1" } },
    [118] = { { unlockName = "装备强化上限+1" } },
    [119] = { { unlockName = "装备强化上限+1" } },
    [120] = { { unlockName = "装备强化上限+1" } },
    [121] = { { unlockName = "装备强化上限+1" } },
    [122] = { { unlockName = "装备强化上限+1" } },
    [123] = { { unlockName = "装备强化上限+1" } },
    [124] = { { unlockName = "装备强化上限+1" } },
    [125] = { { unlockName = "装备强化上限+1" } },
    [126] = { { unlockName = "装备强化上限+1" } },
    [127] = { { unlockName = "装备强化上限+1" } },
    [128] = { { unlockName = "装备强化上限+1" } },
    [129] = { { unlockName = "装备强化上限+1" } },
    [130] = { { unlockName = "装备强化上限+1" } },
    [131] = { { unlockName = "装备强化上限+1" } },
    [132] = { { unlockName = "装备强化上限+1" } },
    [133] = { { unlockName = "装备强化上限+1" } },
    [134] = { { unlockName = "装备强化上限+1" } },
    [135] = { { unlockName = "装备强化上限+1" } },
    [136] = { { unlockName = "装备强化上限+1" } },
    [137] = { { unlockName = "装备强化上限+1" } },
    [138] = { { unlockName = "装备强化上限+1" } },
    [139] = { { unlockName = "装备强化上限+1" } },
    [140] = { { unlockName = "装备强化上限+1" } },
    [141] = { { unlockName = "装备强化上限+1" } },
    [142] = { { unlockName = "装备强化上限+1" } },
    [143] = { { unlockName = "装备强化上限+1" } },
    [144] = { { unlockName = "装备强化上限+1" } },
    [145] = { { unlockName = "装备强化上限+1" } },
    [146] = { { unlockName = "装备强化上限+1" } },
    [147] = { { unlockName = "装备强化上限+1" } },
    [148] = { { unlockName = "装备强化上限+1" } },
    [149] = { { unlockName = "装备强化上限+1" } },
    [150] = { { unlockName = "装备强化上限+1" } },
}

for lv = 151, 200 do
    ExpTable.levelUnlocks[lv] = { { unlockName = "装备强化上限+1" } }
end

--- 获取指定等级的解锁内容列表
---@param level number 冒险等级
---@return table[]|nil 解锁内容列表，无解锁内容返回 nil
function ExpTable.getLevelUnlocks(level)
    return ExpTable.levelUnlocks[level]
end

--- 建筑名称 → 建筑 key 映射（与 TownScene 的 key 对应）
ExpTable.BUILDING_KEY_MAP = {
    ["教堂"]   = "church",
    ["铁匠铺"] = "smith",
    ["酒馆"]   = "tavern",
    ["市场"]   = "market",
    ["竞技场"] = "arena",
    ["冒险者公会"] = "guild",
}

--- 判断指定建筑在当前冒险等级是否已解锁
---@param buildingKey string 建筑 key（"church"/"smith"/"tavern"/"market"/"arena"/"guild"）
---@param playerLevel number 当前冒险等级
---@return boolean
function ExpTable.isBuildingUnlocked(buildingKey, playerLevel)
    for lv, unlocks in pairs(ExpTable.levelUnlocks) do
        for _, entry in ipairs(unlocks) do
            local key = ExpTable.BUILDING_KEY_MAP[entry.unlockName]
            if key == buildingKey then
                return playerLevel >= lv
            end
        end
    end
    return true  -- 未在解锁表中的建筑默认解锁
end

--- 获取指定建筑的解锁等级
---@param buildingKey string 建筑 key
---@return number 解锁等级（未找到返回 1）
function ExpTable.getBuildingUnlockLevel(buildingKey)
    for lv, unlocks in pairs(ExpTable.levelUnlocks) do
        for _, entry in ipairs(unlocks) do
            local key = ExpTable.BUILDING_KEY_MAP[entry.unlockName]
            if key == buildingKey then
                return lv
            end
        end
    end
    return 1
end

--- 获取指定编队槽位的解锁等级
--- 槽位 1~2 为基础槽位（始终解锁），槽位 3/4/5 分别在 Lv2/Lv6/Lv10 解锁
---@param slotIndex number 槽位索引（1~5）
---@return number|nil 解锁所需冒险等级，基础槽位返回 nil
function ExpTable.getSlotUnlockLevel(slotIndex)
    -- 基础槽位无需解锁
    if slotIndex <= 2 then return nil end
    -- 收集所有"出战槽位+1"的等级并排序
    local levels = {}
    for lv, unlocks in pairs(ExpTable.levelUnlocks) do
        for _, entry in ipairs(unlocks) do
            if entry.unlockName == "出战槽位+1" then
                levels[#levels + 1] = lv
            end
        end
    end
    table.sort(levels)
    -- slotIndex 3 对应第 1 个解锁，4 对应第 2 个，5 对应第 3 个
    local idx = slotIndex - 2
    return levels[idx]
end

--- 根据冒险等级计算已解锁的出战槽位数量
--- 基础 2 个槽位，Lv2/Lv6/Lv10 各 +1
---@param playerLevel number 当前冒险等级
---@return number 已解锁槽位总数（2~5，受 MAX_SLOTS 限制）
function ExpTable.getUnlockedSlotCount(playerLevel)
    local base = 2
    local extra = 0
    for lv, unlocks in pairs(ExpTable.levelUnlocks) do
        if playerLevel >= lv then
            for _, entry in ipairs(unlocks) do
                if entry.unlockName == "出战槽位+1" then
                    extra = extra + 1
                end
            end
        end
    end
    return math.min(base + extra, 4)  -- 最多 4 个（与每队 4 槽一致）
end

-- ======================== 多队伍（三队并行战斗）解锁规则 ========================
-- 队1 开局解锁；队2/队3 达到冒险等级阈值解锁（阈值可调）
ExpTable.TEAM_COUNT = 3
ExpTable.TEAM_UNLOCK_LEVELS = { 10, 20 }  -- [i] = 解锁第 (i+1) 队所需等级
ExpTable.TEAM_MAX_SLOTS = 4               -- 每队最多上阵人数（左4角色 vs 右4敌人）

--- 根据冒险等级计算已解锁的队伍数量
---@param playerLevel number 当前冒险等级
---@return number 已解锁队伍数（1~TEAM_COUNT）
function ExpTable.getUnlockedTeamCount(playerLevel)
    local count = 1
    for i, lv in ipairs(ExpTable.TEAM_UNLOCK_LEVELS) do
        if playerLevel >= lv then
            count = i + 1
        end
    end
    return math.min(count, ExpTable.TEAM_COUNT)
end

--- 获取解锁指定队伍所需的冒险等级
---@param teamIdx number 队伍索引（1~TEAM_COUNT）
---@return number|nil 解锁等级；队1 无需解锁返回 nil
function ExpTable.getTeamUnlockLevel(teamIdx)
    return ExpTable.TEAM_UNLOCK_LEVELS[teamIdx - 1]
end

--- 每队出战槽位数（复用"出战槽位+1"节奏 Lv2/Lv6/Lv10，上限 4）
---@param playerLevel number 当前冒险等级
---@return number 该队已解锁槽位数（2~TEAM_MAX_SLOTS）
function ExpTable.getUnlockedSlotCountForTeam(playerLevel)
    return math.min(ExpTable.getUnlockedSlotCount(playerLevel), ExpTable.TEAM_MAX_SLOTS)
end

--- 装备槽位强化等级上限（初始 1，每升一级冒险等级 +1）
--- 规则: 上限 = 冒险等级（Lv.1→上限1, Lv.2→上限2, ..., Lv.200→上限200）
---@param playerLevel number 当前冒险等级
---@return number 当前强化等级上限
function ExpTable.getEnhanceLevelCap(playerLevel)
    return math.max(1, playerLevel or 1)
end

--- 冒险家最大等级（200 级封顶）
ExpTable.HERO_MAX_LEVEL = 200

--- 冒险等级最大等级（200 级封顶）
ExpTable.PLAYER_MAX_LEVEL = 200

--- 查询英雄从 lv 升到 lv+1 所需经验，满级返回 nil
---@param lv number
---@return number|nil
function ExpTable.getHeroExpForLevel(lv)
    return ExpTable.hero[lv]
end

--- 查询玩家从 lv 升到 lv+1 所需经验，满级返回 nil
---@param lv number
---@return number|nil
function ExpTable.getPlayerExpForLevel(lv)
    return ExpTable.player[lv]
end

--- 判断英雄是否满级
---@param lv number
---@return boolean
function ExpTable.isHeroMaxLevel(lv)
    return lv >= ExpTable.HERO_MAX_LEVEL
end

--- 判断玩家是否满级
---@param lv number
---@return boolean
function ExpTable.isPlayerMaxLevel(lv)
    return lv >= ExpTable.PLAYER_MAX_LEVEL
end

--- 根据上场冒险家数量获取经验倍率
---@param count number 上场冒险家数量（1~5）
---@return number 倍率（默认 1.0）
function ExpTable.getHeroCountExpMult(count)
    return ExpTable.heroCountExpMult[count] or 1.0
end

--- 获取指定等级的基础战斗属性成长（HP + ATK）
--- 返回该等级每级获得的 {hp, atk}，用于累加到角色战斗属性
---@param level number 英雄等级（1~200）
---@return {hp: number, atk: number}
function ExpTable.getHeroBaseGrowth(level)
    return ExpTable.heroBaseGrowth[level] or { hp = 60, atk = 3.0 }
end

--- 计算从 1 级到指定等级的累计基础战斗属性成长
--- 1 级时累计为 0（无成长），2 级时获得 Lv1 那档的成长
---@param level number 英雄等级（1~200）
---@return number totalHp, number totalAtk
function ExpTable.getAccumulatedBaseGrowth(level)
    local totalHp, totalAtk = 0, 0
    for lv = 1, level - 1 do
        local g = ExpTable.getHeroBaseGrowth(lv)
        totalHp = totalHp + g.hp
        totalAtk = totalAtk + g.atk
    end
    return totalHp * ExpTable.HERO_HP_GROWTH_MULT, totalAtk
end

--- 自动升级英雄（累积经验 → 连续升级）
--- 直接修改 hero 表的 level/exp/maxExp 字段
---@param hero table { level, exp, maxExp, ... }
function ExpTable.autoLevelUpHero(hero)
    while true do
        local currentLevel = hero.level or 1
        if ExpTable.isHeroMaxLevel(currentLevel) then
            hero.exp = 0
            hero.maxExp = 0
            break
        end
        local needed = ExpTable.getHeroExpForLevel(currentLevel)
        if not needed or hero.exp < needed then
            hero.maxExp = needed or 0
            break
        end
        hero.exp = hero.exp - needed
        hero.level = currentLevel + 1
    end
end

--- 自动升级玩家（累积经验 → 连续升级）
--- 直接修改 playerData 表的 level/exp/maxExp 字段
---@param playerData table { level, exp, maxExp, ... }
function ExpTable.autoLevelUpPlayer(playerData)
    while true do
        local lv = playerData.level or 1
        if ExpTable.isPlayerMaxLevel(lv) then
            playerData.exp = 0
            playerData.maxExp = 0
            break
        end
        local needed = ExpTable.getPlayerExpForLevel(lv)
        if not needed or playerData.exp < needed then
            playerData.maxExp = needed or 0
            break
        end
        playerData.exp = playerData.exp - needed
        playerData.level = lv + 1
    end
end

return ExpTable
