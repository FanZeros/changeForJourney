------------------------------------------------------------------------
-- StageConfig.lua  —— 关卡配置表（15 难度 + 14 终焉神殿）
-- 普通:   23章×5关=115关  (0101-2305)   + 终焉神殿 999
-- 困难:   23章×5关=115关  (2401-4605)   + 终焉神殿 1999
-- 噩梦:   23章×5关=115关  (4701-6905)   + 终焉神殿 2999
-- 地狱:   23章×5关=115关  (7001-9205)   + 终焉神殿 3999
-- 炼狱:   23章×5关=115关  (9301-11505)  + 终焉神殿 4999
-- 折磨:   23章×5关=115关  (11601-13805) + 终焉神殿 5999
-- 折磨II: 23章×5关=115关  (13901-16105) + 终焉神殿 6999
-- 折磨III:23章×5关=115关  (16201-18405) + 终焉神殿 7999
-- 折磨IV: 23章×5关=115关  (18501-20705) + 终焉神殿 8999
-- 折磨V:  23章×5关=115关  (20801-23005)   + 终焉神殿 9999
-- 湮灭:   23章×5关=115关  (23101-25305)   + 终焉神殿 10999
-- 湮灭II: 23章×5关=115关  (25401-27605)   + 终焉神殿 11999
-- 湮灭III:23章×5关=115关  (27701-29905)   + 终焉神殿 12999
-- 湮灭IV: 23章×5关=115关  (30001-32205)   + 终焉神殿 13999
-- 湮灭V:  23章×5关=115关  (32301-34505)（最高难度，无终焉神殿）
-- 数据源: docs/配置文件/关卡配置.txt（.tmp/gen_annihilation45.py 生成湮灭 IV/V）
------------------------------------------------------------------------
local SC = {}

---@class StageEntry
---@field id              number
---@field name            string
---@field chapter         number
---@field stage           number
---@field monsterLevel    number
---@field monsters        number[]
---@field bossId          number
---@field idleCount       number
---@field firstCount      number
---@field maxFieldEnemies number
---@field dropRate        number
---@field qw              number[]
---@field fcGold          number
---@field fcExp           number
---@field fcDiamond       number
---@field fcEssence       number   -- 首通精粹（洗练装备）
---@field fcArcaneDust    number   -- 首通奥术粉尘（遗物洗练，chapter<13 为 0）
---@field fcEquip         number
---@field fcMinQ          number
---@field fcScroll        number
---@field scrollDropRate  number
---@field difficulty             string|nil
---@field mode                   string|nil
---@field mapBg                  string|nil
---@field firstClearBonusMonster  number|nil   -- 兼容旧配置：单只首通附加怪
---@field firstClearBonusMonsters number[]|nil -- 首通附加特殊怪 ID 列表（x-3 单只；x-5 两只不同）

------------------------------------------------------------------------
-- 难度常量
------------------------------------------------------------------------
SC.DIFFICULTY_NORMAL    = "normal"
SC.DIFFICULTY_HARD      = "hard"
SC.DIFFICULTY_NIGHTMARE = "nightmare"
SC.DIFFICULTY_HELL      = "hell"
SC.DIFFICULTY_PURGATORY = "purgatory"
SC.DIFFICULTY_TORMENT   = "torment"
SC.DIFFICULTY_TORMENT2  = "torment2"
SC.DIFFICULTY_TORMENT3  = "torment3"
SC.DIFFICULTY_TORMENT4  = "torment4"
SC.DIFFICULTY_TORMENT5     = "torment5"
SC.DIFFICULTY_ANNIHILATION  = "annihilation"
SC.DIFFICULTY_ANNIHILATION2 = "annihilation2"
SC.DIFFICULTY_ANNIHILATION3 = "annihilation3"
SC.DIFFICULTY_ANNIHILATION4 = "annihilation4"
SC.DIFFICULTY_ANNIHILATION5 = "annihilation5"

--- 终焉神殿 ID
SC.TERMINAL_NORMAL    = 999
SC.TERMINAL_HARD      = 1999
SC.TERMINAL_NIGHTMARE = 2999
SC.TERMINAL_HELL      = 3999
SC.TERMINAL_PURGATORY = 4999
SC.TERMINAL_TORMENT   = 5999
SC.TERMINAL_TORMENT2  = 6999
SC.TERMINAL_TORMENT3  = 7999
SC.TERMINAL_TORMENT4     = 8999
SC.TERMINAL_TORMENT5     = 9999
SC.TERMINAL_ANNIHILATION  = 10999
SC.TERMINAL_ANNIHILATION2 = 11999
SC.TERMINAL_ANNIHILATION3 = 12999
SC.TERMINAL_ANNIHILATION4 = 13999

--- 各难度章节范围（内部 chapter 连续编号）
SC.NORMAL_CHAPTERS    = { first = 1,   last = 23 }
SC.HARD_CHAPTERS      = { first = 24,  last = 46 }
SC.NIGHTMARE_CHAPTERS = { first = 47,  last = 69 }
SC.HELL_CHAPTERS      = { first = 70,  last = 92 }
SC.PURGATORY_CHAPTERS = { first = 93,  last = 115 }
SC.TORMENT_CHAPTERS   = { first = 116, last = 138 }
SC.TORMENT2_CHAPTERS  = { first = 139, last = 161 }
SC.TORMENT3_CHAPTERS  = { first = 162, last = 184 }
SC.TORMENT4_CHAPTERS  = { first = 185, last = 207 }
SC.TORMENT5_CHAPTERS       = { first = 208, last = 230 }
SC.ANNIHILATION_CHAPTERS   = { first = 231, last = 253 }
SC.ANNIHILATION2_CHAPTERS  = { first = 254, last = 276 }
SC.ANNIHILATION3_CHAPTERS  = { first = 277, last = 299 }
SC.ANNIHILATION4_CHAPTERS  = { first = 300, last = 322 }
SC.ANNIHILATION5_CHAPTERS  = { first = 323, last = 345 }

--- 各难度最后一个关卡 ID（终焉神殿入口；湮灭V 为最高难度）
SC.NORMAL_LAST_STAGE    = 2305
SC.HARD_LAST_STAGE      = 4605
SC.NIGHTMARE_LAST_STAGE = 6905
SC.HELL_LAST_STAGE      = 9205
SC.PURGATORY_LAST_STAGE = 11505
SC.TORMENT_LAST_STAGE   = 13805
SC.TORMENT2_LAST_STAGE  = 16105
SC.TORMENT3_LAST_STAGE  = 18405
SC.TORMENT4_LAST_STAGE  = 20705
SC.TORMENT5_LAST_STAGE      = 23005
SC.ANNIHILATION_LAST_STAGE  = 25305
SC.ANNIHILATION2_LAST_STAGE = 27605
SC.ANNIHILATION3_LAST_STAGE = 29905
SC.ANNIHILATION4_LAST_STAGE = 32205
SC.ANNIHILATION5_LAST_STAGE = 34505

--- 各难度第一个关卡 ID
SC.NORMAL_FIRST_STAGE    = 0101
SC.HARD_FIRST_STAGE      = 2401
SC.NIGHTMARE_FIRST_STAGE = 4701
SC.HELL_FIRST_STAGE      = 7001
SC.PURGATORY_FIRST_STAGE = 9301
SC.TORMENT_FIRST_STAGE   = 11601
SC.TORMENT2_FIRST_STAGE  = 13901
SC.TORMENT3_FIRST_STAGE  = 16201
SC.TORMENT4_FIRST_STAGE  = 18501
SC.TORMENT5_FIRST_STAGE      = 20801
SC.ANNIHILATION_FIRST_STAGE  = 23101
SC.ANNIHILATION2_FIRST_STAGE = 25401
SC.ANNIHILATION3_FIRST_STAGE = 27701
SC.ANNIHILATION4_FIRST_STAGE = 30001
SC.ANNIHILATION5_FIRST_STAGE = 32301

------------------------------------------------------------------------
-- 加载各难度数据（由 关卡配置.txt 生成）
------------------------------------------------------------------------
local normalStages    = require("config.StageConfig_Normal")
local hardStages      = require("config.StageConfig_Hard")
local nightmareStages = require("config.StageConfig_Nightmare")
local hellStages      = require("config.StageConfig_Hell")
local purgatoryStages = require("config.StageConfig_Purgatory")
local tormentStages   = require("config.StageConfig_Torment")
local torment2Stages  = require("config.StageConfig_Torment2")
local torment3Stages  = require("config.StageConfig_Torment3")
local torment4Stages  = require("config.StageConfig_Torment4")
local torment5Stages       = require("config.StageConfig_Torment5")
local annihilationStages   = require("config.StageConfig_Annihilation")
local annihilation2Stages  = require("config.StageConfig_Annihilation2")
local annihilation3Stages  = require("config.StageConfig_Annihilation3")
local annihilation4Stages  = require("config.StageConfig_Annihilation4")
local annihilation5Stages  = require("config.StageConfig_Annihilation5")

------------------------------------------------------------------------
-- 终焉神殿（14 座，每难度末关 → 终焉神殿 → 下一难度首关）
------------------------------------------------------------------------
local terminalStages = {
    { id=999,  name="终焉神殿",      chapter=0, stage=0, monsterLevel=23,  monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=33355,  fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_NORMAL,    mode="terminal", mapBg="MAP_999.png" },
    { id=1999, name="终焉神殿",      chapter=0, stage=0, monsterLevel=46,  monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=133985, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_HARD,      mode="terminal", mapBg="MAP_999.png" },
    { id=2999, name="终焉神殿",      chapter=0, stage=0, monsterLevel=69,  monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=301317, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_NIGHTMARE, mode="terminal", mapBg="MAP_999.png" },
    { id=3999, name="终焉神殿·地狱", chapter=0, stage=0, monsterLevel=92,  monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=469360, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_HELL,      mode="terminal", mapBg="MAP_999.png" },
    { id=4999, name="终焉神殿·炼狱", chapter=0, stage=0, monsterLevel=115, monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=525683, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_PURGATORY, mode="terminal", mapBg="MAP_999.png" },
    { id=5999, name="终焉神殿·折磨", chapter=0, stage=0, monsterLevel=138, monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=664439, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_TORMENT, mode="terminal", mapBg="MAP_999.png" },
    { id=6999, name="终焉神殿·折磨II", chapter=0, stage=0, monsterLevel=161, monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=802651, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_TORMENT2, mode="terminal", mapBg="MAP_999.png" },
    { id=7999, name="终焉神殿·折磨III", chapter=0, stage=0, monsterLevel=184, monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=940863, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_TORMENT3, mode="terminal", mapBg="MAP_999.png" },
    { id=8999, name="终焉神殿·折磨IV", chapter=0, stage=0, monsterLevel=207, monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=1079074, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_TORMENT4, mode="terminal", mapBg="MAP_999.png" },
    { id=9999, name="终焉神殿·折磨V", chapter=0, stage=0, monsterLevel=230, monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=1217285, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_TORMENT5, mode="terminal", mapBg="MAP_999.png" },
    { id=10999, name="终焉神殿·湮灭", chapter=0, stage=0, monsterLevel=253, monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=1355496, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_ANNIHILATION, mode="terminal", mapBg="MAP_999.png" },
    { id=11999, name="终焉神殿·湮灭II", chapter=0, stage=0, monsterLevel=276, monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=1493707, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_ANNIHILATION2, mode="terminal", mapBg="MAP_999.png" },
    { id=12999, name="终焉神殿·湮灭III", chapter=0, stage=0, monsterLevel=299, monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=1631918, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_ANNIHILATION3, mode="terminal", mapBg="MAP_999.png" },
    { id=13999, name="终焉神殿·湮灭IV", chapter=0, stage=0, monsterLevel=322, monsters={1001,1002,1003}, bossId=0, idleCount=0, firstCount=3, maxFieldEnemies=3, dropRate=0, qw={0,0,0,0}, fcGold=0, fcExp=1770129, fcDiamond=0, fcEssence=0, fcArcaneDust=0, fcEquip=0, fcMinQ=0, fcScroll=0, scrollDropRate=0, difficulty=SC.DIFFICULTY_ANNIHILATION4, mode="terminal", mapBg="MAP_999.png" },
}

------------------------------------------------------------------------
-- 合并所有关卡
------------------------------------------------------------------------
SC.STAGES = {}

local function appendAll(dest, src)
    for _, s in ipairs(src) do
        dest[#dest + 1] = s
    end
end

appendAll(SC.STAGES, normalStages)
appendAll(SC.STAGES, hardStages)
appendAll(SC.STAGES, nightmareStages)
appendAll(SC.STAGES, hellStages)
appendAll(SC.STAGES, purgatoryStages)
appendAll(SC.STAGES, tormentStages)
appendAll(SC.STAGES, torment2Stages)
appendAll(SC.STAGES, torment3Stages)
appendAll(SC.STAGES, torment4Stages)
appendAll(SC.STAGES, torment5Stages)
appendAll(SC.STAGES, annihilationStages)
appendAll(SC.STAGES, annihilation2Stages)
appendAll(SC.STAGES, annihilation3Stages)
appendAll(SC.STAGES, annihilation4Stages)
appendAll(SC.STAGES, annihilation5Stages)
appendAll(SC.STAGES, terminalStages)

------------------------------------------------------------------------
-- 索引表
------------------------------------------------------------------------
---@type table<number, StageEntry>
local idIndex = {}
---@type table<number, StageEntry[]>
local chapterIndex = {}
---@type table<number, string>
local chapterNames = {}

SC.TOTAL_CHAPTERS = 345
SC.TOTAL_STAGES   = 1725

local terminalIds = {
    [SC.TERMINAL_NORMAL]    = SC.DIFFICULTY_NORMAL,
    [SC.TERMINAL_HARD]      = SC.DIFFICULTY_HARD,
    [SC.TERMINAL_NIGHTMARE] = SC.DIFFICULTY_NIGHTMARE,
    [SC.TERMINAL_HELL]      = SC.DIFFICULTY_HELL,
    [SC.TERMINAL_PURGATORY] = SC.DIFFICULTY_PURGATORY,
    [SC.TERMINAL_TORMENT]   = SC.DIFFICULTY_TORMENT,
    [SC.TERMINAL_TORMENT2]  = SC.DIFFICULTY_TORMENT2,
    [SC.TERMINAL_TORMENT3]  = SC.DIFFICULTY_TORMENT3,
    [SC.TERMINAL_TORMENT4]     = SC.DIFFICULTY_TORMENT4,
    [SC.TERMINAL_TORMENT5]     = SC.DIFFICULTY_TORMENT5,
    [SC.TERMINAL_ANNIHILATION]  = SC.DIFFICULTY_ANNIHILATION,
    [SC.TERMINAL_ANNIHILATION2] = SC.DIFFICULTY_ANNIHILATION2,
    [SC.TERMINAL_ANNIHILATION3] = SC.DIFFICULTY_ANNIHILATION3,
    [SC.TERMINAL_ANNIHILATION4] = SC.DIFFICULTY_ANNIHILATION4,
}

local diffToTerminal = {
    [SC.DIFFICULTY_NORMAL]       = SC.TERMINAL_NORMAL,
    [SC.DIFFICULTY_HARD]         = SC.TERMINAL_HARD,
    [SC.DIFFICULTY_NIGHTMARE]    = SC.TERMINAL_NIGHTMARE,
    [SC.DIFFICULTY_HELL]         = SC.TERMINAL_HELL,
    [SC.DIFFICULTY_PURGATORY]    = SC.TERMINAL_PURGATORY,
    [SC.DIFFICULTY_TORMENT]      = SC.TERMINAL_TORMENT,
    [SC.DIFFICULTY_TORMENT2]     = SC.TERMINAL_TORMENT2,
    [SC.DIFFICULTY_TORMENT3]     = SC.TERMINAL_TORMENT3,
    [SC.DIFFICULTY_TORMENT4]     = SC.TERMINAL_TORMENT4,
    [SC.DIFFICULTY_TORMENT5]     = SC.TERMINAL_TORMENT5,
    [SC.DIFFICULTY_ANNIHILATION]  = SC.TERMINAL_ANNIHILATION,
    [SC.DIFFICULTY_ANNIHILATION2] = SC.TERMINAL_ANNIHILATION2,
    [SC.DIFFICULTY_ANNIHILATION3] = SC.TERMINAL_ANNIHILATION3,
    [SC.DIFFICULTY_ANNIHILATION4] = SC.TERMINAL_ANNIHILATION4,
    -- 湮灭V 为最高难度，无终焉神殿
}

local diffToFirstStage = {
    [SC.DIFFICULTY_NORMAL]        = SC.NORMAL_FIRST_STAGE,
    [SC.DIFFICULTY_HARD]          = SC.HARD_FIRST_STAGE,
    [SC.DIFFICULTY_NIGHTMARE]     = SC.NIGHTMARE_FIRST_STAGE,
    [SC.DIFFICULTY_HELL]          = SC.HELL_FIRST_STAGE,
    [SC.DIFFICULTY_PURGATORY]     = SC.PURGATORY_FIRST_STAGE,
    [SC.DIFFICULTY_TORMENT]       = SC.TORMENT_FIRST_STAGE,
    [SC.DIFFICULTY_TORMENT2]      = SC.TORMENT2_FIRST_STAGE,
    [SC.DIFFICULTY_TORMENT3]      = SC.TORMENT3_FIRST_STAGE,
    [SC.DIFFICULTY_TORMENT4]      = SC.TORMENT4_FIRST_STAGE,
    [SC.DIFFICULTY_TORMENT5]      = SC.TORMENT5_FIRST_STAGE,
    [SC.DIFFICULTY_ANNIHILATION]  = SC.ANNIHILATION_FIRST_STAGE,
    [SC.DIFFICULTY_ANNIHILATION2] = SC.ANNIHILATION2_FIRST_STAGE,
    [SC.DIFFICULTY_ANNIHILATION3] = SC.ANNIHILATION3_FIRST_STAGE,
    [SC.DIFFICULTY_ANNIHILATION4] = SC.ANNIHILATION4_FIRST_STAGE,
    [SC.DIFFICULTY_ANNIHILATION5] = SC.ANNIHILATION5_FIRST_STAGE,
}

local diffToLastStage = {
    [SC.DIFFICULTY_NORMAL]        = SC.NORMAL_LAST_STAGE,
    [SC.DIFFICULTY_HARD]          = SC.HARD_LAST_STAGE,
    [SC.DIFFICULTY_NIGHTMARE]     = SC.NIGHTMARE_LAST_STAGE,
    [SC.DIFFICULTY_HELL]          = SC.HELL_LAST_STAGE,
    [SC.DIFFICULTY_PURGATORY]     = SC.PURGATORY_LAST_STAGE,
    [SC.DIFFICULTY_TORMENT]       = SC.TORMENT_LAST_STAGE,
    [SC.DIFFICULTY_TORMENT2]      = SC.TORMENT2_LAST_STAGE,
    [SC.DIFFICULTY_TORMENT3]      = SC.TORMENT3_LAST_STAGE,
    [SC.DIFFICULTY_TORMENT4]      = SC.TORMENT4_LAST_STAGE,
    [SC.DIFFICULTY_TORMENT5]      = SC.TORMENT5_LAST_STAGE,
    [SC.DIFFICULTY_ANNIHILATION]  = SC.ANNIHILATION_LAST_STAGE,
    [SC.DIFFICULTY_ANNIHILATION2] = SC.ANNIHILATION2_LAST_STAGE,
    [SC.DIFFICULTY_ANNIHILATION3] = SC.ANNIHILATION3_LAST_STAGE,
    [SC.DIFFICULTY_ANNIHILATION4] = SC.ANNIHILATION4_LAST_STAGE,
    [SC.DIFFICULTY_ANNIHILATION5] = SC.ANNIHILATION5_LAST_STAGE,
}

local diffUpgrade = {
    [SC.DIFFICULTY_NORMAL]        = SC.DIFFICULTY_HARD,
    [SC.DIFFICULTY_HARD]          = SC.DIFFICULTY_NIGHTMARE,
    [SC.DIFFICULTY_NIGHTMARE]     = SC.DIFFICULTY_HELL,
    [SC.DIFFICULTY_HELL]          = SC.DIFFICULTY_PURGATORY,
    [SC.DIFFICULTY_PURGATORY]    = SC.DIFFICULTY_TORMENT,
    [SC.DIFFICULTY_TORMENT]      = SC.DIFFICULTY_TORMENT2,
    [SC.DIFFICULTY_TORMENT2]     = SC.DIFFICULTY_TORMENT3,
    [SC.DIFFICULTY_TORMENT3]     = SC.DIFFICULTY_TORMENT4,
    [SC.DIFFICULTY_TORMENT4]     = SC.DIFFICULTY_TORMENT5,
    [SC.DIFFICULTY_TORMENT5]     = SC.DIFFICULTY_ANNIHILATION,
    [SC.DIFFICULTY_ANNIHILATION] = SC.DIFFICULTY_ANNIHILATION2,
    [SC.DIFFICULTY_ANNIHILATION2] = SC.DIFFICULTY_ANNIHILATION3,
    [SC.DIFFICULTY_ANNIHILATION3] = SC.DIFFICULTY_ANNIHILATION4,
    [SC.DIFFICULTY_ANNIHILATION4] = SC.DIFFICULTY_ANNIHILATION5,
    -- 湮灭V 为最高难度
}

local diffDowngrade = {
    [SC.DIFFICULTY_HARD]          = SC.DIFFICULTY_NORMAL,
    [SC.DIFFICULTY_NIGHTMARE]     = SC.DIFFICULTY_HARD,
    [SC.DIFFICULTY_HELL]          = SC.DIFFICULTY_NIGHTMARE,
    [SC.DIFFICULTY_PURGATORY]     = SC.DIFFICULTY_HELL,
    [SC.DIFFICULTY_TORMENT]       = SC.DIFFICULTY_PURGATORY,
    [SC.DIFFICULTY_TORMENT2]      = SC.DIFFICULTY_TORMENT,
    [SC.DIFFICULTY_TORMENT3]      = SC.DIFFICULTY_TORMENT2,
    [SC.DIFFICULTY_TORMENT4]      = SC.DIFFICULTY_TORMENT3,
    [SC.DIFFICULTY_TORMENT5]      = SC.DIFFICULTY_TORMENT4,
    [SC.DIFFICULTY_ANNIHILATION]  = SC.DIFFICULTY_TORMENT5,
    [SC.DIFFICULTY_ANNIHILATION2] = SC.DIFFICULTY_ANNIHILATION,
    [SC.DIFFICULTY_ANNIHILATION3] = SC.DIFFICULTY_ANNIHILATION2,
    [SC.DIFFICULTY_ANNIHILATION4] = SC.DIFFICULTY_ANNIHILATION3,
    [SC.DIFFICULTY_ANNIHILATION5] = SC.DIFFICULTY_ANNIHILATION4,
}

local CHAPTER_RANGES = {
    { diff = SC.DIFFICULTY_ANNIHILATION5, range = SC.ANNIHILATION5_CHAPTERS },
    { diff = SC.DIFFICULTY_ANNIHILATION4, range = SC.ANNIHILATION4_CHAPTERS },
    { diff = SC.DIFFICULTY_ANNIHILATION3, range = SC.ANNIHILATION3_CHAPTERS },
    { diff = SC.DIFFICULTY_ANNIHILATION2, range = SC.ANNIHILATION2_CHAPTERS },
    { diff = SC.DIFFICULTY_ANNIHILATION,  range = SC.ANNIHILATION_CHAPTERS },
    { diff = SC.DIFFICULTY_TORMENT5,      range = SC.TORMENT5_CHAPTERS },
    { diff = SC.DIFFICULTY_TORMENT4,  range = SC.TORMENT4_CHAPTERS },
    { diff = SC.DIFFICULTY_TORMENT3,  range = SC.TORMENT3_CHAPTERS },
    { diff = SC.DIFFICULTY_TORMENT2, range = SC.TORMENT2_CHAPTERS },
    { diff = SC.DIFFICULTY_TORMENT,   range = SC.TORMENT_CHAPTERS },
    { diff = SC.DIFFICULTY_PURGATORY, range = SC.PURGATORY_CHAPTERS },
    { diff = SC.DIFFICULTY_HELL,      range = SC.HELL_CHAPTERS },
    { diff = SC.DIFFICULTY_NIGHTMARE, range = SC.NIGHTMARE_CHAPTERS },
    { diff = SC.DIFFICULTY_HARD,      range = SC.HARD_CHAPTERS },
}

for _, s in ipairs(SC.STAGES) do
    idIndex[s.id] = s
    if s.chapter > 0 then
        if not chapterIndex[s.chapter] then
            chapterIndex[s.chapter] = {}
        end
        chapterIndex[s.chapter][#chapterIndex[s.chapter] + 1] = s
        if not chapterNames[s.chapter] then
            local base = s.name:match("^(.-)%d+%-%d+$")
            chapterNames[s.chapter] = base or s.name
        end
    end
end

------------------------------------------------------------------------
-- 公开 API
------------------------------------------------------------------------

---@param id number
---@return StageEntry|nil
function SC.getStage(id)
    return idIndex[id]
end

---@param chapter number
---@param stage number
---@return StageEntry|nil
function SC.getStageByChapter(chapter, stage)
    return idIndex[chapter * 100 + stage]
end

---@param chapter number
---@return StageEntry[]
function SC.getChapterStages(chapter)
    return chapterIndex[chapter] or {}
end

---@param chapter number
---@return string
function SC.getChapterName(chapter)
    return chapterNames[chapter] or ("第" .. chapter .. "章")
end

---@param difficulty string|nil
---@return number[]
function SC.getChapterList(difficulty)
    local range
    if difficulty == SC.DIFFICULTY_HARD then
        range = SC.HARD_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_NIGHTMARE then
        range = SC.NIGHTMARE_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_HELL then
        range = SC.HELL_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_PURGATORY then
        range = SC.PURGATORY_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_TORMENT then
        range = SC.TORMENT_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_TORMENT2 then
        range = SC.TORMENT2_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_TORMENT3 then
        range = SC.TORMENT3_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_TORMENT4 then
        range = SC.TORMENT4_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_TORMENT5 then
        range = SC.TORMENT5_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_ANNIHILATION then
        range = SC.ANNIHILATION_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_ANNIHILATION2 then
        range = SC.ANNIHILATION2_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_ANNIHILATION3 then
        range = SC.ANNIHILATION3_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_ANNIHILATION4 then
        range = SC.ANNIHILATION4_CHAPTERS
    elseif difficulty == SC.DIFFICULTY_ANNIHILATION5 then
        range = SC.ANNIHILATION5_CHAPTERS
    else
        range = SC.NORMAL_CHAPTERS
    end
    local list = {}
    for c = range.first, range.last do
        list[#list + 1] = c
    end
    return list
end

---@param id number
---@return boolean
function SC.hasBoss(id)
    local s = idIndex[id]
    return s ~= nil and s.bossId > 0
end

---@param id number
---@param isFirstClear boolean
---@return number
function SC.getMonsterCount(id, isFirstClear)
    local s = idIndex[id]
    if not s then return 0 end
    return isFirstClear and s.firstCount or s.idleCount
end

---@param id number
---@return boolean
function SC.isTerminalTemple(id)
    return terminalIds[id] ~= nil
end

---@param id number
---@return string
function SC.getDifficulty(id)
    if terminalIds[id] then
        return terminalIds[id]
    end
    local s = idIndex[id]
    if not s then return SC.DIFFICULTY_NORMAL end
    for _, item in ipairs(CHAPTER_RANGES) do
        if s.chapter >= item.range.first then
            return item.diff
        end
    end
    return SC.DIFFICULTY_NORMAL
end

---@param difficulty string
---@return number|nil
function SC.getTerminalTempleId(difficulty)
    return diffToTerminal[difficulty]
end

---@param difficulty string
---@return number
function SC.getFirstStageId(difficulty)
    return diffToFirstStage[difficulty] or SC.NORMAL_FIRST_STAGE
end

---@param currentDifficulty string
---@return string|nil
function SC.getNextDifficulty(currentDifficulty)
    return diffUpgrade[currentDifficulty]
end

---@param currentDifficulty string
---@return number|nil
function SC.getReincarnationTarget(currentDifficulty)
    local nextDiff = SC.getNextDifficulty(currentDifficulty)
    if not nextDiff then return nil end
    return SC.getFirstStageId(nextDiff)
end

--- 沿关卡链前进一步（含终焉神殿 → 下一难度首关）
---@param stageId number
---@return number|nil
local function advanceAlongStageChain(stageId)
    local nextSid = SC.getNextStageId(stageId)
    if nextSid then return nextSid end
    if SC.isTerminalTemple(stageId) then
        return SC.getReincarnationTarget(SC.getDifficulty(stageId))
    end
    return nil
end

--- 构建至 targetId（含）的 clearedStages（string key，与服务端存档一致）
--- 用于 Debug 跳转到终焉前末关：含此前所有难度与终焉神殿，不含当前难度终焉。
---@param targetId number
---@return table<string, boolean>
function SC.buildClearedStagesUpTo(targetId)
    if not targetId or SC.isTerminalTemple(targetId) then
        return {}
    end
    local cleared = {}
    local sid = SC.NORMAL_FIRST_STAGE
    local guard = 0
    while sid and guard < 2000 do
        guard = guard + 1
        cleared[tostring(sid)] = true
        if sid == targetId then break end
        sid = advanceAlongStageChain(sid)
    end
    return cleared
end

--- 推算进度上限（含终焉神殿 → 下一难度首关），与服务端 BattleService.NextStage 校验对齐。
--- 终焉神殿 ID 可能小于同难度末关（如 3999 < 9205），不能仅用数值比较 maxStageId。
---@param maxStageId number
---@param clearedStages table<number, boolean>|nil
---@param currentStageId number|nil
---@return number
function SC.getProgressUpperBound(maxStageId, clearedStages, currentStageId)
    local upper = maxStageId or 0

    local function extendFromTerminal(terminalId)
        if not terminalId or not SC.isTerminalTemple(terminalId) then return end
        local target = SC.getReincarnationTarget(SC.getDifficulty(terminalId))
        if target and target > upper then
            upper = target
        end
    end

    if currentStageId and SC.isTerminalTemple(currentStageId) then
        extendFromTerminal(currentStageId)
    end

    if clearedStages and clearedStages[maxStageId] then
        local nextOfMax = SC.getNextStageId(maxStageId)
        if nextOfMax and SC.isTerminalTemple(nextOfMax) then
            extendFromTerminal(nextOfMax)
        elseif nextOfMax and nextOfMax > upper then
            upper = nextOfMax
        end
        if SC.isTerminalTemple(maxStageId) then
            extendFromTerminal(maxStageId)
        end
    end

    return upper
end

--- 是否应跳过终焉神殿（已进入下一难度或神殿已通关）
---@param currentStageId number 当前难度末关 ID
---@param maxStageId number
---@param clearedStages table<number, boolean>
---@return number|nil skipToId
---@return boolean shouldSkip
function SC.shouldSkipTerminal(currentStageId, maxStageId, clearedStages)
    local diff = SC.getDifficulty(currentStageId)
    local skipToId = SC.getReincarnationTarget(diff)
    if not skipToId then return nil, false end
    local terminalId = SC.getTerminalTempleId(diff)
    local terminalCleared = false
    if terminalId then
        terminalCleared = not not (clearedStages[terminalId] or clearedStages[tostring(terminalId)])
    end
    -- 不能用 getProgressUpperBound 代替 maxStageId：9205 通关后 upper=9301，但尚未挑战终焉时不应跳过
    ---@diagnostic disable-next-line: return-type-mismatch
    return skipToId, (maxStageId >= skipToId) or terminalCleared
end

---@param currentStageId number
---@return number|nil
function SC.getLastStageOfPrevDifficulty(currentStageId)
    local diff = SC.getDifficulty(currentStageId)
    local prevDiff = diffDowngrade[diff]
    if not prevDiff then return nil end
    return diffToLastStage[prevDiff]
end

---@param id number
---@return number|nil
function SC.getNextStageId(id)
    if SC.isTerminalTemple(id) then
        return nil
    end
    local s = idIndex[id]
    if not s then return nil end
    if s.stage < 5 then
        return s.chapter * 100 + (s.stage + 1)
    end
    local difficulty = SC.getDifficulty(id)
    local lastStage = diffToLastStage[difficulty]
    if id == lastStage then
        return SC.getTerminalTempleId(difficulty)
    end
    return (s.chapter + 1) * 100 + 1
end

---@param id number
---@return number|nil
function SC.getPrevStageId(id)
    if SC.isTerminalTemple(id) then
        return nil
    end
    local s = idIndex[id]
    if not s then return nil end
    if s.stage > 1 then
        return s.chapter * 100 + (s.stage - 1)
    end
    local difficulty = SC.getDifficulty(id)
    local firstStage = diffToFirstStage[difficulty]
    if id == firstStage then
        return nil
    end
    return (s.chapter - 1) * 100 + 5
end

---@param id number
---@return number|nil
function SC.getTerminalPrevStageId(id)
    local diff = terminalIds[id]
    if not diff then return nil end
    return diffToLastStage[diff]
end

---@param stageEntry StageEntry
---@return number
function SC.getMaxDropQuality(stageEntry)
    local diff = stageEntry.difficulty or SC.getDifficulty(stageEntry.id)
    if diff == SC.DIFFICULTY_NIGHTMARE or diff == SC.DIFFICULTY_HELL
        or diff == SC.DIFFICULTY_PURGATORY or diff == SC.DIFFICULTY_TORMENT
        or diff == SC.DIFFICULTY_TORMENT2 or diff == SC.DIFFICULTY_TORMENT3
        or diff == SC.DIFFICULTY_TORMENT4 or diff == SC.DIFFICULTY_TORMENT5
        or diff == SC.DIFFICULTY_ANNIHILATION or diff == SC.DIFFICULTY_ANNIHILATION2
        or diff == SC.DIFFICULTY_ANNIHILATION3 or diff == SC.DIFFICULTY_ANNIHILATION4
        or diff == SC.DIFFICULTY_ANNIHILATION5 then
        return 6
    elseif diff == SC.DIFFICULTY_HARD then
        return 5
    end
    return 4
end

---@param chapter number
---@return number
function SC.getRelativeChapter(chapter)
    if chapter >= SC.ANNIHILATION5_CHAPTERS.first then
        return chapter - SC.ANNIHILATION5_CHAPTERS.first + 1
    elseif chapter >= SC.ANNIHILATION4_CHAPTERS.first then
        return chapter - SC.ANNIHILATION4_CHAPTERS.first + 1
    elseif chapter >= SC.ANNIHILATION3_CHAPTERS.first then
        return chapter - SC.ANNIHILATION3_CHAPTERS.first + 1
    elseif chapter >= SC.ANNIHILATION2_CHAPTERS.first then
        return chapter - SC.ANNIHILATION2_CHAPTERS.first + 1
    elseif chapter >= SC.ANNIHILATION_CHAPTERS.first then
        return chapter - SC.ANNIHILATION_CHAPTERS.first + 1
    elseif chapter >= SC.TORMENT5_CHAPTERS.first then
        return chapter - SC.TORMENT5_CHAPTERS.first + 1
    elseif chapter >= SC.TORMENT4_CHAPTERS.first then
        return chapter - SC.TORMENT4_CHAPTERS.first + 1
    elseif chapter >= SC.TORMENT3_CHAPTERS.first then
        return chapter - SC.TORMENT3_CHAPTERS.first + 1
    elseif chapter >= SC.TORMENT2_CHAPTERS.first then
        return chapter - SC.TORMENT2_CHAPTERS.first + 1
    elseif chapter >= SC.TORMENT_CHAPTERS.first then
        return chapter - SC.TORMENT_CHAPTERS.first + 1
    elseif chapter >= SC.PURGATORY_CHAPTERS.first then
        return chapter - SC.PURGATORY_CHAPTERS.first + 1
    elseif chapter >= SC.HELL_CHAPTERS.first then
        return chapter - SC.HELL_CHAPTERS.first + 1
    elseif chapter >= SC.NIGHTMARE_CHAPTERS.first then
        return chapter - SC.NIGHTMARE_CHAPTERS.first + 1
    elseif chapter >= SC.HARD_CHAPTERS.first then
        return chapter - SC.HARD_CHAPTERS.first + 1
    end
    return chapter
end

local DIFF_DISPLAY_NAMES = {
    [SC.DIFFICULTY_NORMAL]    = "普通",
    [SC.DIFFICULTY_HARD]      = "困难",
    [SC.DIFFICULTY_NIGHTMARE] = "噩梦",
    [SC.DIFFICULTY_HELL]      = "地狱",
    [SC.DIFFICULTY_PURGATORY] = "炼狱",
    [SC.DIFFICULTY_TORMENT]   = "折磨",
    [SC.DIFFICULTY_TORMENT2]  = "折磨II",
    [SC.DIFFICULTY_TORMENT3]  = "折磨III",
    [SC.DIFFICULTY_TORMENT4]  = "折磨IV",
    [SC.DIFFICULTY_TORMENT5]      = "折磨V",
    [SC.DIFFICULTY_ANNIHILATION]  = "湮灭",
    [SC.DIFFICULTY_ANNIHILATION2] = "湮灭II",
    [SC.DIFFICULTY_ANNIHILATION3] = "湮灭III",
    [SC.DIFFICULTY_ANNIHILATION4] = "湮灭IV",
    [SC.DIFFICULTY_ANNIHILATION5] = "湮灭V",
}

---@param stageId number
---@return string
function SC.formatProgressDisplay(stageId)
    if not stageId or stageId == 0 then return "普通1-1" end
    local entry = idIndex[stageId]
    if not entry then return "普通1-1" end
    if SC.isTerminalTemple(stageId) then
        return entry.name
    end
    local stageNum = entry.name:match("(%d+%-%d+)$")
    if not stageNum then return entry.name end
    local prefix = DIFF_DISPLAY_NAMES[SC.getDifficulty(stageId)] or "普通"
    return prefix .. stageNum
end

---@param difficulty string
---@return string
function SC.getDifficultyDisplayName(difficulty)
    return DIFF_DISPLAY_NAMES[difficulty] or "普通"
end

--- 是否已抵达噩梦难度（当前/最高进度进入 4701+）
---@param battleData table|nil
---@return boolean
function SC.hasReachedNightmare(battleData)
    if not battleData then return false end
    local maxId = tonumber(battleData.maxStageId) or 0
    local curId = tonumber(battleData.currentStageId) or maxId
    return maxId >= SC.NIGHTMARE_FIRST_STAGE or curId >= SC.NIGHTMARE_FIRST_STAGE
end

--- 首通附加黄金钥匙（噩梦及以后各章 X-5 关投放 2 把）
---@param stageId number
---@param stageEntry StageEntry|nil
---@return number
function SC.getFirstClearGoldenKey(stageId, stageEntry)
    stageId = tonumber(stageId) or 0
    if stageId < SC.NIGHTMARE_FIRST_STAGE then return 0 end
    stageEntry = stageEntry or SC.getStage(stageId)
    if not stageEntry or (stageEntry.stage or 0) ~= 5 then return 0 end
    if SC.isTerminalTemple(stageId) then return 0 end
    return 2
end

--- 是否章末 X-5，且非终焉神殿
---@param stageId number
---@param stageEntry StageEntry|nil
---@return boolean
---@return StageEntry|nil
local function isNonTerminalChapterEnd(stageId, stageEntry)
    stageId = tonumber(stageId) or 0
    if stageId <= 0 or SC.isTerminalTemple(stageId) then return false, nil end
    stageEntry = stageEntry or SC.getStage(stageId)
    if not stageEntry or (stageEntry.stage or 0) ~= 5 then return false, nil end
    return true, stageEntry
end

--- 首通附加腐化石：每个难度各章 X-5 ×1（跳过终焉神殿）
---@param stageId number
---@param stageEntry StageEntry|nil
---@return number
function SC.getFirstClearCorruptStone(stageId, stageEntry)
    local ok = isNonTerminalChapterEnd(stageId, stageEntry)
    return ok and 1 or 0
end

--- 首通附加神圣石：每个难度内每 20 小关一次（相对章 4/8/12/16/20 的 X-5）
--- 新难度从该难度 4-5 起重新计数；跳过终焉神殿
---@param stageId number
---@param stageEntry StageEntry|nil
---@return number
function SC.getFirstClearSacredStone(stageId, stageEntry)
    local ok, entry = isNonTerminalChapterEnd(stageId, stageEntry)
    if not ok or not entry then return 0 end
    local relChapter = SC.getRelativeChapter(entry.chapter or 0)
    if relChapter <= 0 or (relChapter % 4) ~= 0 then return 0 end
    return 1
end

return SC
