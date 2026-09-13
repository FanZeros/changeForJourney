-- TalentStarMap.lua
-- 天赋星图渲染与交互模块
-- 坐标系: 网格中心 (0,0), 五角星布局约 ±21, 格间距 360px
-- 天赋节点尺寸: 小(100%), 中(120%), 大(150%)
-- 连接线: 12px 宽, 3种状态 (未激活/已激活/可激活闪烁)

local TalentStarMap = {}

local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P2-10] 矢量天赋符号系统

-- [暗黑化 P3-调整] 星图节点图标压暗档（与 DarkIcon.ICON_TINT_DARK 同档，独立常量避免反向依赖 ui 模块）
local ICON_TINT_DARK = { 72, 64, 54 }

-- ======================== 常量 ========================

local GRID_SPACING  = 360   -- 坐标点间距 (px)
local LINE_WIDTH    = 12    -- 连接线宽度
local NODE_MAX      = 208   -- 当前最大天赋节点 ID（201-208 为终焉环占位，待填内容）

-- 缩放范围
local ZOOM_MIN      = 0.20
local ZOOM_MAX      = 0.45
local ZOOM_DEFAULT  = 0.45  -- 默认最大（展示图标原始尺寸）

-- 各类型原图尺寸 (px) 和缩放倍率
-- 小型: 原图280, 显示100%;  中型: 原图300, 显示120%;  大型: 原图300, 显示150%
local ICON_BASE = {
    small  = 280,
    medium = 300,
    large  = 300,
}
local SIZE_SCALE = {
    small  = 1.0,
    medium = 1.2,
    large  = 1.5,
}

-- 颜色映射 (RGB)
local COLOR_MAP = {
    ["绿"] = { 0x4C, 0xAF, 0x50 },
    ["红"] = { 0xF4, 0x43, 0x36 },
    ["黄"] = { 0xFF, 0xC1, 0x07 },
    ["蓝"] = { 0x21, 0x96, 0xF3 },
    ["紫"] = { 0x9C, 0x27, 0xB0 },
    ["无"] = { 0xAA, 0xAA, 0xAA },
}

-- ======================== 节点数据 ========================
-- 每个节点: { id, gx, gy, sizeType, name, effect, adj, icon, color }
-- gx/gy = 网格坐标; adj = 相邻节点id列表

local NODES = {
    [0]  = { id=0,  gx=0,   gy=0,   st="small",  name="起始点",     adj={1,2,3,4},         icon="UI_icon_TF_0.png",    color="无" },
    [1]  = { id=1,  gx=0.08,   gy=-1.65,   st="small",  name="灵巧",       adj={0,5,6},           icon="UI_icon_TF_1.png",    color="绿" },
    [2]  = { id=2,  gx=2.47,   gy=0.09,   st="small",  name="刚力",       adj={0,11,12},         icon="UI_icon_TF_2.png",    color="红" },
    [3]  = { id=3,  gx=0,   gy=4.19,  st="small",  name="体魄",       adj={0,9,10},          icon="UI_icon_TF_3.png",    color="黄" },
    [4]  = { id=4,  gx=-2.48,  gy=0.06,   st="small",  name="聪颖",       adj={0,7,8},           icon="UI_icon_TF_4.png",    color="蓝" },
    [5]  = { id=5,  gx=3.22,   gy=-5.18,   st="small",  name="急速",       adj={1,12,18,14},      icon="UI_icon_TF_5.png",    color="绿" },
    [6]  = { id=6,  gx=-2.09,  gy=-4.32,   st="small",  name="幸运草",     adj={1,7,18,13},       icon="UI_icon_TF_6.png",    color="绿" },
    [7]  = { id=7,  gx=-2.97,  gy=-1.38,   st="small",  name="魔杖",       adj={4,6,17,13},       icon="UI_icon_TF_7.png",    color="蓝" },
    [8]  = { id=8,  gx=-4.41,  gy=2.07,  st="small",  name="魔力铠甲",   adj={4,9,17,16},       icon="UI_icon_TF_8.png",    color="蓝" },
    [9]  = { id=9,  gx=-1.28,  gy=3.09,  st="small",  name="冥想",       adj={3,8,20,16},       icon="UI_icon_TF_9.png",    color="黄" },
    [10] = { id=10, gx=1.28,   gy=3.09,  st="small",  name="仁心",       adj={3,11,20,15},      icon="UI_icon_TF_10.png",   color="黄" },
    [11] = { id=11, gx=4.41,   gy=2.07,  st="small",  name="磨刃",       adj={2,10,19,15},      icon="UI_icon_TF_11.png",   color="红" },
    [12] = { id=12, gx=2.99,   gy=-1.15,   st="small",  name="铁壁",       adj={2,5,19,14},       icon="UI_icon_TF_12.png",   color="红" },
    [13] = { id=13, gx=-2.2,  gy=-2.44,   st="medium", name="弱点飞镖",   adj={6,7},             icon="UI_icon_TF_13.png",   color="绿" },
    [14] = { id=14, gx=2.11,   gy=-2.12,   st="medium", name="捷击",       adj={5,12},            icon="UI_icon_TF_14.png",   color="绿" },
    [15] = { id=15, gx=1.27,   gy=1.3,  st="medium", name="生机",       adj={10,11},           icon="UI_icon_TF_15.png",   color="黄" },
    [16] = { id=16, gx=-1.27,  gy=1.3,  st="medium", name="魔法帽",     adj={8,9},             icon="UI_icon_TF_16.png",   color="蓝" },
    [17] = { id=17, gx=-6.49,  gy=0.56,   st="small",  name="魔焰",       adj={7,8,21,25,26},    icon="UI_icon_TF_17.png",   color="蓝" },
    [18] = { id=18, gx=0.83,   gy=-4.81,   st="small",  name="灵敏",       adj={5,6,22,27,28},    icon="UI_icon_TF_18.png",   color="绿" },
    [19] = { id=19, gx=6.5,   gy=0.65,   st="small",  name="战锤",       adj={11,12,23,29,30},  icon="UI_icon_TF_19.png",   color="红" },
    [20] = { id=20, gx=0,   gy=9.25,  st="small",  name="圣徽",       adj={9,10,24,31,32},   icon="UI_icon_TF_20.png",   color="黄" },
    [21] = { id=21, gx=-4.51,  gy=0.24,   st="large",  name="博学",       adj={17},              icon="UI_icon_TF_21.png",   color="蓝" },
    [22] = { id=22, gx=0.34,   gy=-3.19,   st="large",  name="轻如蝉翼",   adj={18},              icon="UI_icon_TF_22.png",   color="绿" },
    [23] = { id=23, gx=4.52,   gy=0.37,   st="large",  name="刚猛之力",   adj={19},              icon="UI_icon_TF_23.png",   color="红" },
    [24] = { id=24, gx=0,   gy=6.91,  st="large",  name="不屈",       adj={20},              icon="UI_icon_TF_24.png",   color="黄" },
    [25] = { id=25, gx=-10.16,  gy=3.67,  st="small",  name="灵魂飞弹",   adj={17,33},           icon="UI_icon_TF_25.png",   color="蓝" },
    [26] = { id=26, gx=-5.96,  gy=-1.07,   st="small",  name="魔杖",       adj={17,34},           icon="UI_icon_TF_7.png",    color="蓝" },
    [27] = { id=27, gx=-0.24,  gy=-5.9,   st="small",  name="致命",       adj={18,35},           icon="UI_icon_TF_27.png",   color="绿" },
    [28] = { id=28, gx=4.02,   gy=-7.97,   st="small",  name="连斩",       adj={18,36},           icon="UI_icon_TF_28.png",   color="绿" },
    [29] = { id=29, gx=6.35,   gy=-0.66,   st="small",  name="磨刃",       adj={19,37},           icon="UI_icon_TF_11.png",   color="红" },
    [30] = { id=30, gx=10.16,   gy=3.67,  st="small",  name="破甲稿",     adj={19,38},           icon="UI_icon_TF_30.png",   color="红" },
    [31] = { id=31, gx=1.68,   gy=7.94,  st="small",  name="重甲",       adj={20,39},           icon="UI_icon_TF_31.png",   color="黄" },
    [32] = { id=32, gx=-1.68,  gy=7.94,  st="small",  name="法盾",       adj={20,40},           icon="UI_icon_TF_32.png",   color="黄" },
    [33] = { id=33, gx=-8.92, gy=4.8,  st="small",  name="水晶杖",     adj={25,41,42},        icon="UI_icon_TF_33.png",   color="蓝" },
    [34] = { id=34, gx=-6.52, gy=-2.3,   st="small",  name="秘法暴击",   adj={26,43,44},        icon="UI_icon_TF_34.png",   color="蓝" },
    [35] = { id=35, gx=-1.38,  gy=-7.54,  st="small",  name="急速",       adj={27,45,46},        icon="UI_icon_TF_5.png",    color="绿" },
    [36] = { id=36, gx=7.8,   gy=-10.12,  st="small",  name="瞄准",       adj={28,47,48},        icon="UI_icon_TF_36.png",   color="绿" },
    [37] = { id=37, gx=7.54,  gy=-1.23,   st="small",  name="猎弓",       adj={29,49,50},        icon="UI_icon_TF_37.png",   color="红" },
    [38] = { id=38, gx=8.92,  gy=4.8,  st="small",  name="巨斧",       adj={30,51,52},        icon="UI_icon_TF_38.png",   color="红" },
    [39] = { id=39, gx=2.97,   gy=8.06, st="small",  name="圣徽",       adj={31,53,54},        icon="UI_icon_TF_20.png",   color="黄" },
    [40] = { id=40, gx=-2.97,  gy=8.06, st="small",  name="体能",       adj={32,55,56},        icon="UI_icon_TF_40.png",   color="黄" },
    [41] = { id=41, gx=-7.07, gy=5.01,  st="small",  name="魔焰",       adj={33,61,62},        icon="UI_icon_TF_17.png",   color="蓝" },
    [42] = { id=42, gx=-12.21, gy=4.25,  st="small",  name="魔杖",       adj={33,57},           icon="UI_icon_TF_7.png",    color="蓝" },
    [43] = { id=43, gx=-7.86, gy=-0.78,   st="small",  name="聪颖",       adj={34,57},           icon="UI_icon_TF_4.png",    color="蓝" },
    [44] = { id=44, gx=-6.93, gy=-4.2,   st="small",  name="秘法注能",   adj={34,63,64},        icon="UI_icon_TF_44.png",   color="蓝" },
    [45] = { id=45, gx=-3.58,  gy=-9.05,  st="small",  name="致命",       adj={35,65,66},        icon="UI_icon_TF_27.png",   color="绿" },
    [46] = { id=46, gx=0.4,  gy=-7.07,  st="small",  name="幸运草",     adj={35,58},           icon="UI_icon_TF_6.png",    color="绿" },
    [47] = { id=47, gx=5.15,   gy=-9.61,  st="small",  name="灵巧",       adj={36,58},           icon="UI_icon_TF_1.png",    color="绿" },
    [48] = { id=48, gx=7.55,   gy=-7.28,  st="small",  name="急速",       adj={36,67,68},        icon="UI_icon_TF_5.png",    color="绿" },
    [49] = { id=49, gx=6.53,  gy=-1.97,   st="small",  name="钻心箭",     adj={37,69,70},        icon="UI_icon_TF_49.png",   color="红" },
    [50] = { id=50, gx=8.51,  gy=-0.2,   st="small",  name="刚力",       adj={37,59},           icon="UI_icon_TF_2.png",    color="红" },
    [51] = { id=51, gx=12.21,  gy=4.25,  st="small",  name="磨刃",       adj={38,59},           icon="UI_icon_TF_11.png",   color="红" },
    [52] = { id=52, gx=7.07,  gy=5.01,  st="small",  name="战锤",       adj={38,71,72},        icon="UI_icon_TF_19.png",   color="红" },
    [53] = { id=53, gx=3.15,   gy=6.76, st="small",  name="权杖",       adj={39,73,74},        icon="UI_icon_TF_53.png",   color="黄" },
    [54] = { id=54, gx=1.82,   gy=10.16, st="small",  name="体魄",       adj={39,60},           icon="UI_icon_TF_3.png",    color="黄" },
    [55] = { id=55, gx=-1.82,  gy=10.16, st="small",  name="冥想",       adj={40,60},           icon="UI_icon_TF_9.png",    color="黄" },
    [56] = { id=56, gx=-3.15,  gy=6.76, st="small",  name="自愈",       adj={40,75,76},        icon="UI_icon_TF_56.png",   color="黄" },
    [57] = { id=57, gx=-11.49, gy=2.04,   st="medium", name="奥能印记",   adj={42,43,77},        icon="UI_icon_TF_57.png",   color="蓝" },
    [58] = { id=58, gx=3.38,   gy=-9.23,  st="medium", name="迅捷指环",   adj={46,47,78},        icon="UI_icon_TF_58.png",   color="绿" },
    [59] = { id=59, gx=11.49,  gy=2.04,   st="medium", name="力量训练",   adj={50,51,79},        icon="UI_icon_TF_59.png",   color="红" },
    [60] = { id=60, gx=0,   gy=14.31, st="medium", name="龟壳之境",   adj={54,55,80},        icon="UI_icon_TF_60.png",   color="黄" },
    [61] = { id=61, gx=-4.69,  gy=4.41,  st="small",  name="魔焰",       adj={41,81,94},        icon="UI_icon_TF_17.png",   color="蓝" },
    [62] = { id=62, gx=-5.94,  gy=4,  st="small",  name="蚀魔",       adj={41,86},           icon="UI_icon_TF_25.png",   color="蓝" },
    [63] = { id=63, gx=-5.73,  gy=-3.65,   st="small",  name="秘法暴击",   adj={44,87},           icon="UI_icon_TF_34.png",   color="蓝" },
    [64] = { id=64, gx=-6.2,  gy=-5.96,   st="small",  name="魔杖",       adj={44,82,95},        icon="UI_icon_TF_7.png",    color="蓝" },
    [65] = { id=65, gx=-6.53,  gy=-8.76,   st="small",  name="致命",       adj={45,82,96},        icon="UI_icon_TF_27.png",   color="绿" },
    [66] = { id=66, gx=-3.77,  gy=-7.8,   st="small",  name="暗器",       adj={45,88},           icon="UI_icon_TF_66.png",   color="绿" },
    [67] = { id=67, gx=6.33,   gy=-6.77,   st="small",  name="急速",       adj={48,89},           icon="UI_icon_TF_5.png",    color="绿" },
    [68] = { id=68, gx=5.74,   gy=-4.83,   st="small",  name="连斩",       adj={48,83,97},        icon="UI_icon_TF_28.png",   color="绿" },
    [69] = { id=69, gx=5.63,   gy=-3.5,   st="small",  name="重拳",       adj={49,83,98},        icon="UI_icon_TF_11.png",   color="红" },
    [70] = { id=70, gx=5.33,   gy=-2.22,   st="small",  name="猎弓",       adj={49,90},           icon="UI_icon_TF_37.png",   color="红" },
    [71] = { id=71, gx=5.94,   gy=4,  st="small",  name="破甲稿",     adj={52,91},           icon="UI_icon_TF_30.png",   color="红" },
    [72] = { id=72, gx=4.69,   gy=4.41,  st="small",  name="战锤",       adj={52,84,99},        icon="UI_icon_TF_19.png",   color="红" },
    [73] = { id=73, gx=3.49,   gy=4.39,  st="small",  name="坚甲",       adj={53,84,100},       icon="UI_icon_TF_31.png",   color="黄" },
    [74] = { id=74, gx=2.61,   gy=5.22,  st="small",  name="仁心",       adj={53,92},           icon="UI_icon_TF_10.png",   color="黄" },
    [75] = { id=75, gx=-2.61,  gy=5.22,  st="small",  name="自愈",       adj={56,85},           icon="UI_icon_TF_56.png",   color="黄" },
    [76] = { id=76, gx=-3.49,  gy=4.39,  st="small",  name="法盾",       adj={56,81,93},        icon="UI_icon_TF_32.png",   color="黄" },
    [77] = { id=77, gx=-8.47,  gy=1.03,   st="large",  name="五芒星盘",   adj={57},              icon="UI_icon_TF_77.png",   color="蓝" },
    [78] = { id=78, gx=1.63,   gy=-6.5,   st="large",  name="刺客假面",   adj={58},              icon="UI_icon_TF_78.png",   color="绿" },
    [79] = { id=79, gx=8.47,   gy=1.12,   st="large",  name="狼牙棒",     adj={59},              icon="UI_icon_TF_79.png",   color="红" },
    [80] = { id=80, gx=0,   gy=11.38,  st="large",  name="黄金铠甲",   adj={60},              icon="UI_icon_TF_80.png",   color="黄" },
    [81] = { id=81, gx=-3.26,  gy=3.15,  st="medium", name="魔法盾",     adj={61,76},           icon="UI_icon_TF_81.png",   color="紫" },
    [82] = { id=82, gx=-4.99,  gy=-5.63,   st="medium", name="水晶球",     adj={64,65},           icon="UI_icon_TF_82.png",   color="紫" },
    [83] = { id=83, gx=4.48,   gy=-3.83,   st="medium", name="暴虐",       adj={68,69},           icon="UI_icon_TF_83.png",   color="紫" },
    [84] = { id=84, gx=3.26,   gy=3.15,  st="medium", name="骑士头盔",   adj={72,73},           icon="UI_icon_TF_84.png",   color="紫" },
    [85] = { id=85, gx=-2.25,  gy=3.94,  st="small",  name="体魄",       adj={75,101,105},      icon="UI_icon_TF_3.png",    color="黄" },
    [86] = { id=86, gx=-4.6,  gy=3.26,  st="small",  name="魔杖",       adj={62,101,106},      icon="UI_icon_TF_7.png",    color="蓝" },
    [87] = { id=87, gx=-4.56,  gy=-3.03,   st="small",  name="聪颖",       adj={63,102,107},      icon="UI_icon_TF_4.png",    color="蓝" },
    [88] = { id=88, gx=-3.79,  gy=-6.52,   st="small",  name="幸运草",     adj={66,102,108},      icon="UI_icon_TF_6.png",    color="绿" },
    [89] = { id=89, gx=5.2,   gy=-6.02,   st="small",  name="灵巧",       adj={67,103,109},      icon="UI_icon_TF_1.png",    color="绿" },
    [90] = { id=90, gx=4.09,   gy=-2.15,   st="small",  name="磨刃",       adj={70,103,110},      icon="UI_icon_TF_11.png",   color="红" },
    [91] = { id=91, gx=4.6,   gy=3.26,  st="small",  name="刚力",       adj={71,104,111},      icon="UI_icon_TF_2.png",    color="红" },
    [92] = { id=92, gx=2.25,   gy=3.94,  st="small",  name="冥想",       adj={74,104,112},      icon="UI_icon_TF_9.png",    color="黄" },
    [93] = { id=93, gx=-3.69,  gy=5.7, st="small",  name="魔甲强化",   adj={76,113,117},      icon="UI_icon_TF_8.png",    color="蓝" },
    [94] = { id=94, gx=-5.79, gy=5.25,  st="small",  name="魔杖",       adj={61,113,118},      icon="UI_icon_TF_7.png",    color="蓝" },
    [95] = { id=95, gx=-7.33, gy=-6.42,   st="small",  name="秘法注能",   adj={64,114,119},      icon="UI_icon_TF_44.png",   color="蓝" },
    [96] = { id=96, gx=-6.66,  gy=-10.06,  st="small",  name="急速",       adj={65,114,120},      icon="UI_icon_TF_5.png",    color="绿" },
    [97] = { id=97, gx=6.92,   gy=-5.56,  st="small",  name="连斩",       adj={68,115,121},      icon="UI_icon_TF_28.png",   color="绿" },
    [98] = { id=98, gx=6.73,  gy=-3.12,   st="small",  name="钻心箭",     adj={69,115,122},      icon="UI_icon_TF_49.png",   color="红" },
    [99] = { id=99, gx=5.79,  gy=5.25,  st="small",  name="磨刃",       adj={72,116,123},      icon="UI_icon_TF_11.png",   color="红" },
    [100]= { id=100,gx=3.69,   gy=5.7, st="small",  name="重甲",       adj={73,116,124},      icon="UI_icon_TF_31.png",   color="黄" },
    [101]= { id=101,gx=-2.29,  gy=2.25,  st="medium", name="真视之盾",   adj={85,86},           icon="UI_icon_TF_101.png",  color="紫" },
    [102]= { id=102,gx=-3.8,  gy=-4.12,   st="medium", name="奥术之翼",   adj={87,88},           icon="UI_icon_TF_102.png",  color="紫" },
    [103]= { id=103,gx=3.34,   gy=-3.17,   st="medium", name="狂暴打击",   adj={89,90},           icon="UI_icon_TF_103.png",  color="紫" },
    [104]= { id=104,gx=2.29,   gy=2.25,  st="medium", name="小圆盾",     adj={91,92},           icon="UI_icon_TF_104.png",  color="紫" },
    [105]= { id=105,gx=-1.47,  gy=5.7,  st="medium", name="骑士之魂",   adj={85},              icon="UI_icon_TF_105.png",  color="黄" },
    [106]= { id=106,gx=-7.59,  gy=3.12,  st="medium", name="法师之悟",   adj={86},              icon="UI_icon_TF_106.png",  color="蓝" },
    [107]= { id=107,gx=-4.28,  gy=-1.23,   st="medium", name="魔力洞穿",   adj={87},              icon="UI_icon_TF_107.png",  color="蓝" },
    [108]= { id=108,gx=-0.94,  gy=-4.84,   st="medium", name="刺客之锋",   adj={88},              icon="UI_icon_TF_108.png",  color="绿" },
    [109]= { id=109,gx=3.35,   gy=-6.52,   st="medium", name="射手之力",   adj={89},              icon="UI_icon_TF_109.png",  color="绿" },
    [110]= { id=110,gx=4.51,   gy=-0.94,   st="medium", name="穿心之箭",   adj={90},              icon="UI_icon_TF_110.png",  color="红" },
    [111]= { id=111,gx=7.59,   gy=3.12,  st="medium", name="战士之怒",   adj={91},              icon="UI_icon_TF_111.png",  color="红" },
    [112]= { id=112,gx=1.47,   gy=5.7,  st="medium", name="牧师之恩",   adj={92},              icon="UI_icon_TF_112.png",  color="黄" },
    [113]= { id=113,gx=-4.69, gy=5.56, st="large",  name="秘法印记",   adj={93,94},           icon="UI_icon_TF_113.png",  color="紫" },
    [114]= { id=114,gx=-7.81, gy=-9.03,  st="large",  name="雷霆万钧",   adj={95,96},           icon="UI_icon_TF_114.png",  color="紫" },
    [115]= { id=115,gx=6.81,  gy=-4.29,  st="large",  name="斩尽杀绝",   adj={97,98},           icon="UI_icon_TF_115.png",  color="紫" },
    [116]= { id=116,gx=4.69,  gy=5.56, st="large",  name="铁壁之盾",   adj={99,100},          icon="UI_icon_TF_116.png",  color="紫" },
    [117]= { id=117,gx=-4.36,  gy=7.2, st="small",  name="抗魔体质",   adj={93,125,129},      icon="UI_icon_TF_117.png",  color="黄" },
    [118]= { id=118,gx=-6.64, gy=6.25,  st="small",  name="魔焰",       adj={94,125,130},      icon="UI_icon_TF_17.png",   color="蓝" },
    [119]= { id=119,gx=-8.44, gy=-6.9,   st="small",  name="秘法注能",   adj={95,126,131},      icon="UI_icon_TF_44.png",   color="蓝" },
    [120]= { id=120,gx=-5.89,  gy=-11.01,  st="small",  name="趁胜追击",   adj={96,126,132},      icon="UI_icon_TF_120.png",  color="绿" },
    [121]= { id=121,gx=8.16,   gy=-5.83,  st="small",  name="致命",       adj={97,127,133},      icon="UI_icon_TF_27.png",   color="绿" },
    [122]= { id=122,gx=7.9,  gy=-2.95,   st="small",  name="钻心箭",     adj={98,127,134},      icon="UI_icon_TF_49.png",   color="红" },
    [123]= { id=123,gx=6.64,  gy=6.25,  st="small",  name="战锤",       adj={99,128,135},      icon="UI_icon_TF_19.png",   color="红" },
    [124]= { id=124,gx=4.36,   gy=7.2, st="small",  name="过量治疗",   adj={100,128,136},     icon="UI_icon_TF_124.png",  color="黄" },
    [125]= { id=125,gx=-5.39, gy=6.5, st="large",  name="不死鸟之魂", adj={117,118,153},     icon="UI_icon_TF_125.png",  color="紫" },
    [126]= { id=126,gx=-8.82, gy=-10.73,  st="large",  name="杀戮盛宴",   adj={119,120,154},     icon="UI_icon_TF_126.png",  color="紫" },
    [127]= { id=127,gx=8,  gy=-4.3,  st="large",  name="赌命一击",   adj={121,122,155},     icon="UI_icon_TF_127.png",  color="紫" },
    [128]= { id=128,gx=5.39,  gy=6.5, st="large",  name="共鸣之歌",   adj={123,124,156},     icon="UI_icon_TF_128.png",  color="紫" },
    [129]= { id=129,gx=-3.47,  gy=9.31, st="large",  name="荆棘护肩",   adj={117,151,152},     icon="UI_icon_TF_129.png",  color="黄" },
    [130]= { id=130,gx=-9.54, gy=5.97,  st="large",  name="深渊之眼",   adj={118,137,138},     icon="UI_icon_TF_130.png",  color="蓝" },
    [131]= { id=131,gx=-8.17, gy=-3.36,   st="large",  name="魔导之书",   adj={119,139,140},     icon="UI_icon_TF_131.png",  color="蓝" },
    [132]= { id=132,gx=-1.64,  gy=-9.27,  st="large",  name="无尽连锁",   adj={120,141,142},     icon="UI_icon_TF_132.png",  color="绿" },
    [133]= { id=133,gx=8.96,   gy=-9.01,  st="large",  name="大号子弹",   adj={121,143,144},     icon="UI_icon_TF_133.png",  color="绿" },
    [134]= { id=134,gx=9.03,  gy=-1.42,   st="large",  name="弑神之刃",   adj={122,145,146},     icon="UI_icon_TF_134.png",  color="红" },
    [135]= { id=135,gx=9.54,  gy=5.97,  st="large",  name="石中剑",     adj={123,147,148},     icon="UI_icon_TF_135.png",  color="红" },
    [136]= { id=136,gx=3.47,   gy=9.31, st="large",  name="妙手回春",   adj={124,149,150},     icon="UI_icon_TF_136.png",  color="黄" },
    [137]= { id=137,gx=-7.53, gy=7.19, st="small",  name="幽蓝聚能",   adj={130,153,157},     icon="UI_icon_TF_32.png",   color="蓝" },
    [138]= { id=138,gx=-9.17, gy=7.11,  st="small",  name="蚀魂法矛",   adj={130,157},         icon="UI_icon_TF_25.png",   color="蓝" },
    [139]= { id=139,gx=-9.05, gy=-4.3,   st="small",  name="星火预兆",   adj={131,158},         icon="UI_icon_TF_34.png",   color="蓝" },
    [140]= { id=140,gx=-9.59, gy=-7.42,  st="small",  name="秘纹爆裂",   adj={131,154,158},     icon="UI_icon_TF_44.png",   color="蓝" },
    [141]= { id=141,gx=-5.24, gy=-12.06,  st="small",  name="幻影步",     adj={132,154,159},     icon="UI_icon_TF_18.png",   color="绿" },
    [142]= { id=142,gx=-2.2,  gy=-10.41,  st="small",  name="风切",       adj={132,159},         icon="UI_icon_TF_5.png",    color="绿" },
    [143]= { id=143,gx=9.58,   gy=-7.91,  st="small",  name="精准刺击",   adj={133,160},         icon="UI_icon_TF_13.png",   color="绿" },
    [144]= { id=144,gx=9.41,  gy=-5.98,  st="small",  name="连环攻势",   adj={133,155,160},     icon="UI_icon_TF_28.png",   color="绿" },
    [145]= { id=145,gx=9.15,  gy=-2.74,  st="small",  name="战意高涨",   adj={134,155,161},     icon="UI_icon_TF_38.png",   color="红" },
    [146]= { id=146,gx=10.21,  gy=-1.74,   st="small",  name="破阵尖锋",   adj={134,161},         icon="UI_icon_TF_30.png",   color="红" },
    [147]= { id=147,gx=9.17,  gy=7.11,  st="small",  name="血刃准星",   adj={135,162},         icon="UI_icon_TF_37.png",   color="红" },
    [148]= { id=148,gx=7.53,  gy=7.19, st="small",  name="裂甲重击",   adj={135,156,162},     icon="UI_icon_TF_49.png",   color="红" },
    [149]= { id=149,gx=4.9,  gy=8.44, st="small",  name="圣辉祷言",   adj={136,156,163},     icon="UI_icon_TF_20.png",   color="黄" },
    [150]= { id=150,gx=4.38,   gy=10.1, st="small",  name="坚韧骨甲",   adj={136,163},         icon="UI_icon_TF_31.png",   color="黄" },
    [151]= { id=151,gx=-4.38,  gy=10.1, st="small",  name="灵能屏障",   adj={129,164},         icon="UI_icon_TF_32.png",   color="黄" },
    [152]= { id=152,gx=-4.9, gy=8.44, st="small",  name="生命泉涌",   adj={129,153,164},     icon="UI_icon_TF_56.png",   color="黄" },
    [153]= { id=153,gx=-5.97, gy=7.61, st="large",  name="灵魂壁垒",   adj={125,137,152,169,184,185}, icon="UI_icon_TF_81.png",   color="紫" },
    [154]= { id=154,gx=-9.91, gy=-12.55,  st="large",  name="星陨回响",   adj={126,140,141,172,173,186}, icon="UI_icon_TF_82.png",   color="紫" },
    [155]= { id=155,gx=9.22,  gy=-4.1,  st="large",  name="极限狩猎",   adj={127,144,145,176,177,187}, icon="UI_icon_TF_83.png",   color="紫" },
    [156]= { id=156,gx=5.97,  gy=7.61, st="large",  name="圣盾反击",   adj={128,148,149,180,181,188}, icon="UI_icon_TF_84.png",   color="紫" },
    [157]= { id=157,gx=-11.06, gy=6.41,  st="medium", name="星轨法阵",   adj={137,138,165},     icon="UI_icon_TF_77.png",   color="蓝" },
    [158]= { id=158,gx=-9.17, gy=-2.44,   st="medium", name="苍穹秘仪",   adj={139,140,165},     icon="UI_icon_TF_102.png",  color="蓝" },
    [159]= { id=159,gx=-0.27,  gy=-9.36,  st="medium", name="疾影步法",   adj={141,142,166},     icon="UI_icon_TF_78.png",   color="绿" },
    [160]= { id=160,gx=9.7,   gy=-10.23,  st="medium", name="百裂连环",   adj={143,144,166},     icon="UI_icon_TF_132.png",  color="绿" },
    [161]= { id=161,gx=10.89,  gy=-0.59,   st="medium", name="破军锋芒",   adj={145,146,167},     icon="UI_icon_TF_79.png",   color="红" },
    [162]= { id=162,gx=11.06,  gy=6.41,  st="medium", name="裂地重击",   adj={147,148,167},     icon="UI_icon_TF_134.png",  color="红" },
    [163]= { id=163,gx=3.38,   gy=11.23, st="medium", name="圣光守护",   adj={149,150,168},     icon="UI_icon_TF_136.png",  color="黄" },
    [164]= { id=164,gx=-3.38,  gy=11.23, st="medium", name="不灭屏障",   adj={151,152,168},     icon="UI_icon_TF_80.png",   color="黄" },
    [165]= { id=165,gx=-14.67, gy=3.49,   st="large",  name="星界魔典",   adj={157,158,197},     icon="UI_icon_TF_130.png",  color="蓝" },
    [166]= { id=166,gx=6.11,   gy=-12.11,  st="large",  name="风暴之心",   adj={159,160,198},     icon="UI_icon_TF_114.png",  color="绿" },
    [167]= { id=167,gx=14.67,  gy=3.49,   st="large",  name="破晓战旗",   adj={161,162,199},     icon="UI_icon_TF_135.png",  color="红" },
    [168]= { id=168,gx=0,   gy=17.02, st="large",  name="圣堂结界",   adj={163,164,200},     icon="UI_icon_TF_128.png",  color="黄" },
    [169]= { id=169,gx=-10.68, gy=8.11, st="small",  name="星辉护罩",   adj={153,170,185,189,203}, icon="UI_icon_TF_32.png",   color="蓝" },
    [170]= { id=170,gx=-13.39, gy=7.44,  st="small",  name="虚空穿刺",   adj={169,189},         icon="UI_icon_TF_25.png",   color="蓝" },
    [171]= { id=171,gx=-11.6, gy=-2.41,   st="small",  name="秘法凝视",   adj={172,190},         icon="UI_icon_TF_34.png",   color="蓝" },
    [172]= { id=172,gx=-11.01, gy=-7.65,  st="small",  name="奥术爆鸣",   adj={154,171,186,190,204}, icon="UI_icon_TF_44.png",   color="蓝" },
    [173]= { id=173,gx=-3.88, gy=-12.84,  st="small",  name="影步残响",   adj={154,174,186,191,207}, icon="UI_icon_TF_18.png",   color="绿" },
    [174]= { id=174,gx=1.29,  gy=-11.78,  st="small",  name="迅风律动",   adj={173,191},         icon="UI_icon_TF_5.png",    color="绿" },
    [175]= { id=175,gx=11.22,   gy=-10.44,  st="small",  name="弱点锁定",   adj={176,192},         icon="UI_icon_TF_13.png",   color="绿" },
    [176]= { id=176,gx=11.01,  gy=-7.65,  st="small",  name="千刃连携",   adj={155,175,187,192,208}, icon="UI_icon_TF_28.png",   color="绿" },
    [177]= { id=177,gx=13.41,  gy=-0.28,  st="small",  name="战旗鼓舞",   adj={155,178,187,193,206}, icon="UI_icon_TF_38.png",   color="红" },
    [178]= { id=178,gx=15.21,  gy=1.85,   st="small",  name="破甲冲锋",   adj={177,193},         icon="UI_icon_TF_30.png",   color="红" },
    [179]= { id=179,gx=13.39,  gy=7.44,  st="small",  name="血色瞄准",   adj={180,194},         icon="UI_icon_TF_37.png",   color="红" },
    [180]= { id=180,gx=10.68,  gy=8.11, st="small",  name="崩裂重击",   adj={156,179,188,194,205}, icon="UI_icon_TF_49.png",   color="红" },
    [181]= { id=181,gx=4.41,  gy=12.66, st="small",  name="圣辉恩泽",   adj={156,182,188,195,202}, icon="UI_icon_TF_20.png",   color="黄" },
    [182]= { id=182,gx=2.94,   gy=15.04, st="small",  name="磐石守护",   adj={181,195},         icon="UI_icon_TF_31.png",   color="黄" },
    [183]= { id=183,gx=-2.94,  gy=15.04, st="small",  name="灵魂护幕",   adj={184,196},         icon="UI_icon_TF_32.png",   color="黄" },
    [184]= { id=184,gx=-4.41, gy=12.66, st="small",  name="生命回响",   adj={153,183,185,196,201}, icon="UI_icon_TF_40.png",   color="黄" },
    [185]= { id=185,gx=-6.82, gy=9.38, st="large",  name="永恒壁垒",   adj={153,169,184},     icon="UI_icon_TF_81.png",   color="紫" },
    [186]= { id=186,gx=-11.99, gy=-16.5,  st="large",  name="奥术风暴",   adj={154,172,173},     icon="UI_icon_TF_82.png",   color="紫" },
    [187]= { id=187,gx=11.03,  gy=-3.58,  st="large",  name="终结狩猎",   adj={155,176,177},     icon="UI_icon_TF_83.png",   color="紫" },
    [188]= { id=188,gx=6.82,  gy=9.38, st="large",  name="守护誓约",   adj={156,180,181},     icon="UI_icon_TF_84.png",   color="紫" },
    [189]= { id=189,gx=-16.11, gy=6.78,  st="medium", name="星渊法核",   adj={169,170,197},     icon="UI_icon_TF_77.png",   color="蓝" },
    [190]= { id=190,gx=-15.21, gy=1.85,   st="medium", name="秘银法环",   adj={171,172,197},     icon="UI_icon_TF_102.png",  color="蓝" },
    [191]= { id=191,gx=6.46,  gy=-13.89,  st="medium", name="疾风回旋",   adj={173,174,198},     icon="UI_icon_TF_78.png",   color="绿" },
    [192]= { id=192,gx=11.43,   gy=-13.22,  st="medium", name="裂影连击",   adj={175,176,198},     icon="UI_icon_TF_132.png",  color="绿" },
    [193]= { id=193,gx=17.02,  gy=3.98,   st="medium", name="破军锋刃",   adj={177,178,199},     icon="UI_icon_TF_79.png",   color="红" },
    [194]= { id=194,gx=16.11,  gy=6.78,  st="medium", name="裂甲狂潮",   adj={179,180,199},     icon="UI_icon_TF_134.png",  color="红" },
    [195]= { id=195,gx=1.47,   gy=17.41, st="medium", name="圣佑脉冲",   adj={181,182,200},     icon="UI_icon_TF_136.png",  color="黄" },
    [196]= { id=196,gx=-1.47,  gy=17.41, st="medium", name="坚毅圣印",   adj={183,184,200},     icon="UI_icon_TF_80.png",   color="黄" },
    [197]= { id=197,gx=-19.4, gy=6.3,   st="large",  name="星界虹吸",   adj={165,189,190},     icon="UI_icon_TF_130.png",  color="蓝" },
    [198]= { id=198,gx=11.99,   gy=-16.5,  st="large",  name="风暴连锁",   adj={166,191,192},     icon="UI_icon_TF_114.png",  color="绿" },
    [199]= { id=199,gx=19.4,  gy=6.3,   st="large",  name="破灭战阵",   adj={167,193,194},     icon="UI_icon_TF_135.png",  color="红" },
    [200]= { id=200,gx=0,   gy=20.4, st="large",  name="不朽圣域",   adj={168,195,196},     icon="UI_icon_TF_128.png",  color="黄" },

    -- ==================== [终焉环占位 201-208] ====================
    -- 贴在五角星外轮廓上的预留节点，供追加终焉级内容；name/effect 由后续设计填充
    -- 占位期间渲染为紫色问号铭牌（matchTalentKind fallback → query 符号）
    [201]= { id=201,gx=-5.94, gy=11.73, st="medium", name="终焉·？？",  adj={185,184},         icon="",                    color="紫" },
    [202]= { id=202,gx=5.94,  gy=11.73, st="medium", name="终焉·？？",  adj={181,188},         icon="",                    color="紫" },
    [203]= { id=203,gx=-9.32, gy=9.27, st="medium", name="终焉·？？",  adj={185,169},         icon="",                    color="紫" },
    [204]= { id=204,gx=-12.2, gy=-12.75,  st="medium", name="终焉·？？",  adj={172,186},         icon="",                    color="紫" },
    [205]= { id=205,gx=9.32,  gy=9.27, st="medium", name="终焉·？？",  adj={188,180},         icon="",                    color="紫" },
    [206]= { id=206,gx=12.99,  gy=-2.02,  st="medium", name="终焉·？？",  adj={177,187},         icon="",                    color="紫" },
    [207]= { id=207,gx=-8.35, gy=-15.54,  st="medium", name="终焉·？？",  adj={186,173},         icon="",                    color="紫" },
    [208]= { id=208,gx=11.7,  gy=-6,  st="medium", name="终焉·？？",  adj={176,187},         icon="",                    color="紫" },
}

-- ======================== 效果描述 ========================
-- 从配置文件注入 effect 字段
local EFFECTS = {
    [0]   = "一切的开始，可以从这里向周围逐渐点亮天赋",
    [1]   = "全体敏捷+1",
    [2]   = "全体力量+1",
    [3]   = "全体体质+1",
    [4]   = "全体智慧+1",
    [5]   = "全体攻击速度+4%",
    [6]   = "全体运气+1",
    [7]   = "全体魔法攻击加成+2.5%",
    [8]   = "全体能量护盾+14",
    [9]   = "全体精神+1",
    [10]  = "全体治疗量+3",
    [11]  = "全体物理攻击加成+2.5%",
    [12]  = "全体护甲+2",
    [13]  = "全体暴击率+2.5%",
    [14]  = "全体敏捷+1 攻击速度+2%",
    [15]  = "全体生命加成+4.2%",
    [16]  = "全体智慧+1 精神+1",
    [17]  = "全体魔法伤害加成+5%",
    [18]  = "全体闪避加成+3.3%",
    [19]  = "全体物理伤害加成+5%",
    [20]  = "全体治疗加成+6%",
    [21]  = "全体智慧+3",
    [22]  = "全体敏捷+3",
    [23]  = "全体力量+3",
    [24]  = "全体体质+3",
    [25]  = "全体魔法穿透+4",
    [26]  = "全体魔法攻击加成+3.3%",
    [27]  = "全体暴击伤害+10%",
    [28]  = "全体连击概率+7%",
    [29]  = "全体物理攻击加成+3.3%",
    [30]  = "全体物理穿透+4",
    [31]  = "全体护甲+3",
    [32]  = "全体能量护盾+21",
    [33]  = "全体魔法攻击加成+3%",
    [34]  = "全体魔法暴击率+2.5%",
    [35]  = "全体攻击速度+5%",
    [36]  = "全体命中值+2",
    [37]  = "全体物理暴击率+2.5%",
    [38]  = "全体物理攻击加成+3%",
    [39]  = "全体治疗加成+8%",
    [40]  = "全体生命加成+3.3%",
    [41]  = "全体魔法伤害加成+10%",
    [42]  = "全体魔法攻击加成+5%",
    [43]  = "全体智慧+2",
    [44]  = "全体魔法暴击伤害+20%",
    [45]  = "全体暴击伤害+15%",
    [46]  = "全体运气+2",
    [47]  = "全体敏捷+2",
    [48]  = "全体攻击速度+8%",
    [49]  = "全体物理暴击伤害+20%",
    [50]  = "全体力量+2",
    [51]  = "全体物理攻击加成+5%",
    [52]  = "全体物理伤害加成+10%",
    [53]  = "全体治疗暴击率+4%",
    [54]  = "全体体质+2",
    [55]  = "全体精神+2",
    [56]  = "全体每秒回血+10",
    [57]  = "全体魔法攻击力+6 全体智慧+2",
    [58]  = "全体运气+2 全体敏捷+2",
    [59]  = "全体物理攻击力+6 全体力量+2",
    [60]  = "全体体质+2 全体精神+2",
    [61]  = "全体魔法伤害加成+10%",
    [62]  = "全体魔法穿透+6",
    [63]  = "全体魔法暴击率+4%",
    [64]  = "全体魔法攻击加成+5%",
    [65]  = "全体暴击伤害+15%",
    [66]  = "全体暴击率+3%",
    [67]  = "全体攻击速度+8%",
    [68]  = "全体连击概率+10%",
    [69]  = "全体物理攻击加成+5%",
    [70]  = "全体物理暴击率+4%",
    [71]  = "全体物理穿透+6",
    [72]  = "全体物理伤害加成+10%",
    [73]  = "全体护甲+4",
    [74]  = "全体治疗量+6",
    [75]  = "全体每秒回血+10",
    [76]  = "全体能量护盾+28",
    [77]  = "全体魔法伤害加成+15%，魔法穿透+6",
    [78]  = "全体攻击速度+12%，连击概率+9%",
    [79]  = "全体物理伤害加成+15%，物理穿透+6",
    [80]  = "全体生命值+116，护甲+3",
    [81]  = "全体能量护盾伤害减免+12%",
    [82]  = "全体魔法暴击率+5%，魔法伤害加成+7%",
    [83]  = "全体暴击伤害+20%，物理暴击率+2.5%",
    [84]  = "全体护甲+8，物理格挡概率+1%",
    [85]  = "全体体质+2",
    [86]  = "全体魔法攻击加成+5%",
    [87]  = "全体智慧+2",
    [88]  = "全体运气+2",
    [89]  = "全体敏捷+2",
    [90]  = "全体物理攻击加成+5%",
    [91]  = "全体力量+2",
    [92]  = "全体精神+2",
    [93]  = "全体能量护盾+28",
    [94]  = "全体魔法攻击加成+5%",
    [95]  = "全体魔法暴击伤害+20%",
    [96]  = "全体攻击速度+8%",
    [97]  = "全体连击概率+10%",
    [98]  = "全体物理暴击伤害+20%",
    [99]  = "全体物理攻击加成+5%",
    [100] = "全体护甲+4",
    [101] = "全体能量护盾伤害减免+10%，能量护盾+28",
    [102] = "全体魔法暴击率+4%，魔法暴击伤害+8%",
    [103] = "全体物理暴击率+4%，物理暴击伤害+8%",
    [104] = "全体物理格挡概率+2%，护甲+5",
    [105] = "全体体质+2；[骑士]职业额外获得仇恨值+15%",
    [106] = "全体智慧+2；[法师]职业额外获得魔法伤害加成+5%",
    [107] = "全体魔法暴击率+4%，魔法穿透+3",
    [108] = "全体物理暴击率+3%；[刺客]职业额外获得暴击伤害+10%",
    [109] = "全体命中值+3；[射手]职业额外获得攻击速度+5%",
    [110] = "全体物理暴击率+4%，物理穿透+3",
    [111] = "全体力量+2；[战士]职业额外获得物理伤害加成+5%",
    [112] = "全体每秒回血+7；[牧师]职业额外获得治疗加成+10%",
    [113] = "全体冒险家造成魔法伤害时，有15%概率使目标受到的伤害增加8%，持续5秒",
    [114] = "全体攻击速度+15%，连击概率+10%",
    [115] = "全体冒险家暴击时，本次伤害加成额外提升，提升量=目标已损失生命值百分比×30%",
    [116] = "全体物理格挡概率+3%，魔法格挡概率+3%，护甲加成+5.8%",
    [117] = "全体能量护盾加成+4.7%；当前生命值低于50%时额外能量护盾加成+5.8%",
    [118] = "全体魔法伤害加成+10%",
    [119] = "全体魔法暴击伤害+20%",
    [120] = "全体攻击速度+7%；连续攻击同一目标时每次攻击额外攻击速度+2%（最多叠加5次）",
    [121] = "全体暴击伤害+15%",
    [122] = "全体物理暴击伤害+20%",
    [123] = "全体物理伤害加成+10%",
    [124] = "全体治疗加成+12%；溢出的治疗量转化为目标的能量护盾（转化率30%）",
    [125] = "全体冒险家受到致命伤害时，免疫此次伤害并在3秒内恢复20%最大生命值，每场战斗每个冒险家最多触发1次",
    [126] = "全体冒险家击杀敌人后，攻击速度+30%，持续5秒",
    [127] = "全体冒险家暴击伤害+50%，但伤害加成-10%",
    [128] = "全体冒险家每次施放治疗或攻击时，有15%概率使全队获得持续3秒的5%伤害加成",
    [129] = "全体护甲加成+9.3%，生命加成-3.3%",
    [130] = "全体魔法伤害加成+20%，魔法穿透+6",
    [131] = "全体魔法暴击率+6%，魔法暴击伤害+28%",
    [132] = "全体连击概率+15%，连击增伤+8%",
    [133] = "全体暴击伤害+45%",
    [134] = "全体物理暴击率+6%，物理暴击伤害+28%",
    [135] = "全体物理伤害加成+20%，物理穿透+6",
    [136] = "全体治疗暴击率+10%，治疗暴击加成+7%",
    [137] = "全体能量护盾加成+6.7%",
    [138] = "全体魔法穿透+8",
    [139] = "全体魔法暴击率+5%",
    [140] = "全体魔法暴击伤害+27%",
    [141] = "全体闪避值+4",
    [142] = "全体攻击速度+10%",
    [143] = "全体暴击率+4%",
    [144] = "全体连击概率+13%",
    [145] = "全体物理攻击加成+6.5%",
    [146] = "全体物理穿透+8",
    [147] = "全体物理暴击率+5%",
    [148] = "全体物理暴击伤害+27%",
    [149] = "全体治疗加成+16%",
    [150] = "全体护甲加成+7%",
    [151] = "全体能量护盾加成+6.7%",
    [152] = "全体每秒回血+13",
    [153] = "全体能量护盾加成+13.3%，魔法格挡概率+4%，每秒回血+7",
    [154] = "全体魔法暴击率+6%，攻击速度+18%",
    [155] = "全体暴击伤害+28%，物理暴击率+6%，命中值+2",
    [156] = "全体护甲加成+11.7%，物理格挡概率+4%，治疗加成+12%",
    [157] = "全体魔法伤害加成+15%，魔法穿透+7",
    [158] = "全体魔法暴击率+6%，魔法暴击伤害+21%",
    [159] = "全体攻击速度+12%，闪避值+3",
    [160] = "全体连击概率+16%，暴击伤害+16%",
    [161] = "全体物理攻击加成+8%，物理穿透+6",
    [162] = "全体物理伤害加成+16%，物理暴击伤害+21%",
    [163] = "全体治疗加成+20%，护甲加成+4.7%",
    [164] = "全体生命加成+8.3%，能量护盾加成+5%",
    [165] = "全体魔法伤害加成+20%，魔法攻击加成+10%",
    [166] = "全体攻击速度+18%，连击概率+16%",
    [167] = "全体物理伤害加成+20%，物理攻击加成+10%",
    [168] = "全体生命加成+10%，护甲加成+5.8%，能量护盾加成+4.2%",
    [169] = "全体能量护盾加成+8%",
    [170] = "全体魔法穿透+10",
    [171] = "全体魔法暴击率+6%",
    [172] = "全体魔法暴击伤害+32%",
    [173] = "全体闪避值+5",
    [174] = "全体攻击速度+12%",
    [175] = "全体暴击率+5%",
    [176] = "全体连击概率+15%",
    [177] = "全体物理攻击加成+8%",
    [178] = "全体物理穿透+10",
    [179] = "全体物理暴击率+6%",
    [180] = "全体物理暴击伤害+32%",
    [181] = "全体治疗加成+20%",
    [182] = "全体护甲加成+8.5%",
    [183] = "全体能量护盾加成+8%",
    [184] = "全体生命加成+10%",
    [185] = "全体生命加成+12%，能量护盾加成+8%，魔法格挡概率+4%",
    [186] = "全体魔法暴击率+7%，魔法暴击伤害+28%，攻击速度+10%",
    [187] = "全体暴击率+5%，暴击伤害+35%，命中值+3",
    [188] = "全体护甲加成+12%，物理格挡概率+4%，治疗加成+14%",
    [189] = "全体魔法伤害加成+18%，魔法穿透+8",
    [190] = "全体魔法攻击加成+12%，魔法暴击率+5%",
    [191] = "全体攻击速度+14%，闪避值+4",
    [192] = "全体连击概率+18%，连击增伤+10%",
    [193] = "全体物理攻击加成+10%，物理穿透+8",
    [194] = "全体物理伤害加成+18%，物理暴击伤害+24%",
    [195] = "全体治疗加成+22%，治疗暴击率+5.5%",
    [196] = "全体生命加成+11%，护甲加成+6%",
    [197] = "全体魔法伤害加成+24%，魔法攻击加成+12%，能量护盾加成+6%",
    [198] = "全体攻击速度+22%，连击概率+18%，暴击率+4%",
    [199] = "全体物理伤害加成+24%，物理攻击加成+12%，物理穿透+8",
    [200] = "全体生命加成+14%，护甲加成+8%，能量护盾加成+6%",

    -- [终焉环占位 201-208] 效果待设计填充
    [201] = "【终焉·待定】预留槽位 I（北·西段）",
    [202] = "【终焉·待定】预留槽位 II（北·东段）",
    [203] = "【终焉·待定】预留槽位 III（西·北段）",
    [204] = "【终焉·待定】预留槽位 IV（西·南段）",
    [205] = "【终焉·待定】预留槽位 V（东·北段）",
    [206] = "【终焉·待定】预留槽位 VI（东·南段）",
    [207] = "【终焉·待定】预留槽位 VII（南·西段）",
    [208] = "【终焉·待定】预留槽位 VIII（南·东段）",
}
for id, eff in pairs(EFFECTS) do
    if NODES[id] then NODES[id].effect = eff end
end

-- ======================== 边列表 ========================
-- 预计算唯一边列表 { {a, b}, ... }

local EDGES = {}
do
    local seen = {}
    for id = 0, NODE_MAX do
        local node = NODES[id]
        if node then
            for _, adjId in ipairs(node.adj) do
                local lo = math.min(id, adjId)
                local hi = math.max(id, adjId)
                local key = lo * 1000 + hi
                if not seen[key] then
                    seen[key] = true
                    EDGES[#EDGES + 1] = { lo, hi }
                end
            end
        end
    end
    print("[TalentStarMap] 边数: " .. #EDGES)
end

-- ======================== 运行时状态 ========================

---@type userdata NanoVG context
local vg_ = nil

-- 相机 (世界坐标)
local camX = 0
local camY = 0
local zoom = ZOOM_DEFAULT

-- 相机边界 (世界坐标，五角星外接约 20.4 格 + 余量)
local CAM_BOUND = 22 * GRID_SPACING

-- 惯性滑动
local velocityX = 0      -- 世界坐标速度 (px/s)
local velocityY = 0
local inertiaActive = false
local INERTIA_DECAY = 5.0       -- 衰减系数 (越大越快停)
local INERTIA_THRESHOLD = 10.0  -- 速度低于此值停止 (px/s)

-- 节点点亮状态 (id → boolean)
local litNodes = {}

-- 图标纹理缓存 (icon文件名 → nvg image handle)
local iconImages = {}

-- 视口参数 (由 draw 传入)
local viewW = 1080
local viewH = 1800
local viewOffX = 0   -- 视口在设计坐标中的左上角偏移
local viewOffY = 350 -- 星图区域顶部偏移 (天赋点数/标签下方)

-- 闪烁动画 (使用 time.elapsedTime 驱动)

-- ======================== 内部工具函数 ========================

--- 网格坐标 → 世界坐标 (px)
--- 注意: 数据中 gy 正方向是"上"，屏幕 Y 正方向是"下"，所以 Y 翻转
local function gridToWorld(gx, gy)
    return gx * GRID_SPACING, -gy * GRID_SPACING
end

--- 世界坐标 → 屏幕坐标
local function worldToScreen(wx, wy)
    local sx = (wx - camX) * zoom + viewW * 0.5 + viewOffX
    local sy = (wy - camY) * zoom + viewH * 0.5 + viewOffY
    return sx, sy
end

--- 屏幕坐标 → 世界坐标
local function screenToWorld(sx, sy)
    local wx = (sx - viewOffX - viewW * 0.5) / zoom + camX
    local wy = (sy - viewOffY - viewH * 0.5) / zoom + camY
    return wx, wy
end

--- 尝试加载图标图片 (延迟加载，首次使用时)
local function getIconImage(iconFile)
    if not iconFile or iconFile == "" then return -1 end
    if iconImages[iconFile] ~= nil then return iconImages[iconFile] end
    local path = "image/天赋图标/" .. iconFile
    local handle = nvgCreateImage(vg_, path, 0)
    if handle <= 0 then
        handle = -1  -- 加载失败标记
    end
    iconImages[iconFile] = handle
    return handle
end

-- ======================== 绘制函数 ========================

--- 绘制连接线
local function drawEdges(vg)
    nvgLineCap(vg, NVG_ROUND)
    nvgLineJoin(vg, NVG_ROUND)

    for _, edge in ipairs(EDGES) do
        local idA, idB = edge[1], edge[2]
        local nodeA = NODES[idA]
        local nodeB = NODES[idB]
        if nodeA and nodeB then
            local litA = litNodes[idA] or false
            local litB = litNodes[idB] or false

            -- 决定颜色 [暗黑化] 三态: 已激活=琥珀金饰线 / 可激活=金闪 / 未激活=暗棕隐线
            local r, g, b, a
            if litA and litB then
                r, g, b, a = 201, 151, 59, 235
            elseif litA or litB then
                -- 可激活: 金色闪烁 (在暗金 45% 和亮金之间)
                local flash = (math.sin(time.elapsedTime * 4.0) + 1.0) * 0.5  -- 0~1
                r = math.floor(140 + (240 - 140) * flash)
                g = math.floor(105 + (200 - 105) * flash)
                b = math.floor(38 + (80 - 38) * flash)
                a = math.floor(180 + (255 - 180) * flash)
            else
                -- 未激活: 暗棕（在暗底上隐约可见走向）
                r, g, b, a = 46, 38, 28, 210
            end

            local wax, way = gridToWorld(nodeA.gx, nodeA.gy)
            local wbx, wby = gridToWorld(nodeB.gx, nodeB.gy)
            local sax, say = worldToScreen(wax, way)
            local sbx, sby = worldToScreen(wbx, wby)

            nvgBeginPath(vg)
            nvgStrokeWidth(vg, LINE_WIDTH * zoom)
            nvgStrokeColor(vg, nvgRGBA(r, g, b, a))
            nvgMoveTo(vg, sax, say)
            nvgLineTo(vg, sbx, sby)
            nvgStroke(vg)
        end
    end
end

--- 绘制单个节点
local function drawNode(vg, node)
    local wx, wy = gridToWorld(node.gx, node.gy)
    local sx, sy = worldToScreen(wx, wy)

    -- 图标尺寸 = 原图大小 × 类型倍率 × 相机缩放
    local baseSize = ICON_BASE[node.st] or 280
    local scale = SIZE_SCALE[node.st] or 1.0
    local iconSize = baseSize * scale * zoom
    local iconHalf = iconSize * 0.5

    -- 剔除屏幕外节点 (带余量)
    local margin = iconSize * 1.5
    if sx < -margin or sx > viewW + viewOffX * 2 + margin then return end
    if sy < -margin or sy > viewH + viewOffY * 2 + margin then return end

    local isLit = litNodes[node.id] or false

    -- [暗黑化 P2-10] 矢量天赋符号（金属铭牌 + 系色效果符号），替代 85 张 KTX 贴图
    -- 点亮态全亮；未点亮态整体 55% 透明（铭牌自带暗铁底，无需原遮罩 blend）
    DarkIcon.drawTalentGlyphByName(vg, node.name, node.color, sx, sy, iconSize * 0.70, isLit and 1.0 or 0.55)
end

--- 绘制所有节点
local function drawNodes(vg)
    for id = 0, NODE_MAX do
        local node = NODES[id]
        if node then
            drawNode(vg, node)
        end
    end
end

-- ======================== 公开 API ========================

--- 初始化 (在 ChurchPage init 中调用)
---@param vg any NanoVG context
function TalentStarMap.init(vg)
    vg_ = vg
    -- 重置相机
    camX = 0
    camY = 0
    zoom = ZOOM_DEFAULT
    -- 节点0默认点亮
    litNodes = { [0] = true }
    -- 清空图标缓存
    iconImages = {}
    print("[TalentStarMap] init OK, nodes=" .. tostring(NODE_MAX + 1) .. ", edges=" .. #EDGES)
end

--- 绘制星图
---@param vg any NanoVG context
---@param ox number 视口左上角X (在设计坐标系中)
---@param oy number 视口左上角Y (星图区域起始Y)
---@param w number 视口宽度
---@param h number 视口高度
function TalentStarMap.draw(vg, ox, oy, w, h)
    viewOffX = ox
    viewOffY = oy
    viewW = w
    viewH = h

    -- 裁剪到星图区域（使用 IntersectScissor 与外层 scissor 取交集）
    nvgSave(vg)
    nvgIntersectScissor(vg, ox, oy, w, h)

    -- 先绘制连接线, 再绘制节点 (节点覆盖在线上)
    drawEdges(vg)
    drawNodes(vg)

    nvgResetScissor(vg)
    nvgRestore(vg)
end

--- 设置缩放级别 (从滑块值 0~1 映射)
--- 0 = 最顶 = 最大缩放; 1 = 最底 = 最小缩放
---@param sliderValue number 0~1
function TalentStarMap.setZoom(sliderValue)
    -- 滑块 0(顶)=最大, 1(底)=最小
    zoom = ZOOM_MAX - (ZOOM_MAX - ZOOM_MIN) * sliderValue
end

--- 获取当前缩放值
---@return number
function TalentStarMap.getZoom()
    return zoom
end

--- 将相机限制在边界内
local function clampCamera()
    camX = math.max(-CAM_BOUND, math.min(CAM_BOUND, camX))
    camY = math.max(-CAM_BOUND, math.min(CAM_BOUND, camY))
end

--- 平移相机 (拖拽时调用)
---@param dsx number 屏幕坐标增量X
---@param dsy number 屏幕坐标增量Y
function TalentStarMap.pan(dsx, dsy)
    -- 屏幕增量转世界增量 (取反，拖拽方向与移动方向相反)
    camX = camX - dsx / zoom
    camY = camY - dsy / zoom
    clampCamera()
end

--- 重置相机到原点
function TalentStarMap.resetCamera()
    camX = 0
    camY = 0
    zoom = ZOOM_DEFAULT
    velocityX = 0
    velocityY = 0
    inertiaActive = false
end

--- 启动惯性滑动
---@param vx number 世界坐标速度X (px/s)
---@param vy number 世界坐标速度Y (px/s)
function TalentStarMap.startInertia(vx, vy)
    velocityX = vx
    velocityY = vy
    local speed = math.sqrt(vx * vx + vy * vy)
    inertiaActive = speed > INERTIA_THRESHOLD
end

--- 停止惯性
function TalentStarMap.stopInertia()
    velocityX = 0
    velocityY = 0
    inertiaActive = false
end

--- 每帧更新（惯性衰减）
---@param dt number 帧间隔 (秒)
function TalentStarMap.update(dt)
    if not inertiaActive then return end
    -- 指数衰减
    local factor = math.exp(-INERTIA_DECAY * dt)
    velocityX = velocityX * factor
    velocityY = velocityY * factor
    -- 应用位移
    camX = camX + velocityX * dt
    camY = camY + velocityY * dt
    clampCamera()
    -- 速度过低则停止
    local speed = math.sqrt(velocityX * velocityX + velocityY * velocityY)
    if speed < INERTIA_THRESHOLD then
        velocityX = 0
        velocityY = 0
        inertiaActive = false
    end
end

--- 设置节点点亮状态
---@param id number 节点ID (0-136)
---@param lit boolean 是否点亮
function TalentStarMap.setNodeLit(id, lit)
    litNodes[id] = lit or nil
end

--- 获取节点点亮状态
---@param id number
---@return boolean
function TalentStarMap.isNodeLit(id)
    return litNodes[id] or false
end

--- 点亮所有节点 (测试用)
function TalentStarMap.lightAll()
    for id = 0, NODE_MAX do
        litNodes[id] = true
    end
end

--- 重置所有节点为未点亮 (保留起始点)
function TalentStarMap.resetLit()
    litNodes = { [0] = true }
end

--- 检测触摸点击命中哪个节点
---@param sx number 屏幕坐标X (设计坐标系)
---@param sy number 屏幕坐标Y (设计坐标系)
---@return number? 命中的节点ID
function TalentStarMap.hitTest(sx, sy)
    -- 从最外层节点开始检测（大节点优先）
    for id = NODE_MAX, 0, -1 do
        local node = NODES[id]
        if node then
            local wx, wy = gridToWorld(node.gx, node.gy)
            local nsx, nsy = worldToScreen(wx, wy)
            local baseSize = ICON_BASE[node.st] or 280
            local scale = SIZE_SCALE[node.st] or 1.0
            local radius = baseSize * scale * zoom * 0.5
            local dx = sx - nsx
            local dy = sy - nsy
            if dx * dx + dy * dy <= radius * radius then
                return id
            end
        end
    end
    return nil
end

--- 获取节点信息
---@param id number
---@return table|nil
function TalentStarMap.getNode(id)
    return NODES[id]
end

--- 获取节点图标的 NanoVG 图片句柄（延迟加载）
---@param id number 节点ID
---@return number imgHandle (>=0 有效, <0 无效)
function TalentStarMap.getIconHandle(id)
    local node = NODES[id]
    if not node or not node.icon then return -1 end
    local h = getIconImage(node.icon)
    return h or -1
end

--- [暗黑化 P2-10] 按节点ID绘制矢量天赋符号（铭牌+系色符号）——详情面板等场景用
---@param vg any
---@param id number 节点ID
---@param cx number 中心 X
---@param cy number 中心 Y
---@param size number 直径
---@param alpha number|nil 透明度 0-1
function TalentStarMap.drawTalentIcon(vg, id, cx, cy, size, alpha)
    local node = NODES[id]
    if not node then return end
    DarkIcon.drawTalentGlyphByName(vg, node.name, node.color, cx, cy, size, alpha)
end

--- 拖拽事件处理 (返回是否消费)
---@param phase string "began"|"moved"|"ended"
---@param sx number 屏幕X
---@param sy number 屏幕Y
---@param dsx number 屏幕增量X (moved时有效)
---@param dsy number 屏幕增量Y (moved时有效)
---@return boolean consumed
function TalentStarMap.handleDrag(phase, sx, sy, dsx, dsy)
    if phase == "moved" then
        TalentStarMap.pan(dsx, dsy)
        return true
    end
    return false
end

return TalentStarMap
