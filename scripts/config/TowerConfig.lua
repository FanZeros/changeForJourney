-- ============================================================================
-- TowerConfig - 通天塔副本配置数据表
-- 数据来源: docs/配置文件/401特殊副本 通天塔.txt
-- 包含: 112层局外配置、单波楼层/五层起点、35个强化词条、怪物池查询
-- ============================================================================

local okMC, MC = pcall(require, "config.MonsterConfig")
if not okMC then
    MC = { MONSTERS = {} }
    print("[TowerConfig] WARNING: MonsterConfig not available, monster pool empty")
end

local TowerConfig = {}

-- ======================== 基础常量 ========================

TowerConfig.DUNGEON_ID     = "babel_tower"
TowerConfig.MAX_FLOOR      = 112
TowerConfig.WAVES_PER_FLOOR = 1
TowerConfig.CHECKPOINT_INTERVAL = 5
TowerConfig.ARTIFACT_DROP_RATE = 0.05
TowerConfig.ARTIFACT_QUALITY_WEIGHTS = { 80, 18, 2 }
TowerConfig.FIRST_EXP_MINUTES = 2
TowerConfig.REPEAT_EXP_MINUTES = 1
TowerConfig.DAILY_SWEEP_LIMIT = 2
TowerConfig.UNLOCK_CONDITION  = 0305  -- 最高关卡进度大于 0305

-- 战斗场景资源
TowerConfig.CARD_IMAGE     = "UI_FBRK_3.png"
TowerConfig.BATTLE_BG      = "MAP_FB3.png"

-- 狂暴参数（与副本共享）
TowerConfig.RAGE_TIME            = 30
TowerConfig.RAGE_ATK_BONUS       = 0.50
TowerConfig.SUPER_RAGE_TIME      = 60
TowerConfig.SUPER_RAGE_ATK_BONUS = 1.00

-- 通天塔怪物属性倍率（2026-06 对齐副本 201-206：HP/ATK/防御属性 ×2）
TowerConfig.MONSTER_STAT_MULT = 2.0

-- ======================== 局外层数配置（112层） ========================
-- 首通钻石: 层1=150, 层2=300, 层3+=300+(层-2)*50（与 docs/配置文件/401特殊副本 通天塔.txt 一致）
-- 重打/扫荡不发黑钻；神器按每层独立概率产出。
-- 怪物等级: 9+层*3，最高112层=345级

---@type table[]
TowerConfig.FLOORS = {}
for i = 1, TowerConfig.MAX_FLOOR do
    local diamond
    if i == 1 then diamond = 150
    elseif i == 2 then diamond = 300
    else diamond = 300 + (i - 2) * 50
    end
    TowerConfig.FLOORS[i] = {
        floor        = i,
        firstDiamond = diamond,
        sweepDiamond = 0,
        monsterLevel = math.min(9 + i * 3, 345),  -- 层1=12, 层112=345
        wavePattern  = ((i - 1) % 10) + 1,
    }
end

-- ======================== 楼层敌人配置（十种波型循环，每层只打一波） ========================
-- 保留原十种品质组合，第1/11/21层使用波型1，以此类推。

---@type table[]
TowerConfig.WAVES = {
    { q1 = 10, q2 = 0,  q3 = 0,  q4 = 0, q5 = 0 },  -- 波次1
    { q1 = 10, q2 = 5,  q3 = 0,  q4 = 0, q5 = 0 },  -- 波次2
    { q1 = 10, q2 = 5,  q3 = 3,  q4 = 0, q5 = 0 },  -- 波次3
    { q1 = 10, q2 = 5,  q3 = 3,  q4 = 1, q5 = 0 },  -- 波次4
    { q1 = 5,  q2 = 10, q3 = 3,  q4 = 2, q5 = 0 },  -- 波次5
    { q1 = 5,  q2 = 10, q3 = 6,  q4 = 3, q5 = 0 },  -- 波次6
    { q1 = 5,  q2 = 10, q3 = 6,  q4 = 3, q5 = 1 },  -- 波次7
    { q1 = 0,  q2 = 5,  q3 = 10, q4 = 5, q5 = 2 },  -- 波次8
    { q1 = 0,  q2 = 5,  q3 = 10, q4 = 5, q5 = 3 },  -- 波次9
    { q1 = 0,  q2 = 0,  q3 = 15, q4 = 10, q5 = 4 }, -- 波次10
}

-- ======================== 怪物池（按品质分组，排除特殊怪物） ========================
-- 特殊怪物: ID >= 200（副本怪物/剧情怪物）

---@type table<number, number[]>  quality → monsterId list
TowerConfig.MONSTER_POOL = { [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }

for id, tpl in pairs(MC.MONSTERS) do
    if id < 200 and tpl.quality >= 1 and tpl.quality <= 5 then
        local pool = TowerConfig.MONSTER_POOL[tpl.quality]
        if pool then
            pool[#pool + 1] = id
        end
    end
end
-- 排序使抽取结果可复现（配合 seed）
for q = 1, 5 do
    table.sort(TowerConfig.MONSTER_POOL[q])
end

-- ======================== 强化词条配置（35条） ========================
-- 三选一时按权重加权随机抽取3个不同词条供玩家选择
-- quality: 1=普通(白) 2=优质(绿) 3=稀有(蓝)
-- effectType: "stat"=纯属性加成, "mechanic"=特殊机制(需战斗运行时处理)

---@type table[]
TowerConfig.BUFFS = {
    -- ===== 品质1（权重100）：纯属性加成 =====
    { id = 1,  quality = 1, weight = 100, name = "利刃磨砺", desc = "全体物理攻击力+8%",
      effectType = "stat", stats = { physAtkBonus = 8 } },
    { id = 2,  quality = 1, weight = 100, name = "魔力涌动", desc = "全体魔法攻击力+8%",
      effectType = "stat", stats = { magAtkBonus = 8 } },
    { id = 3,  quality = 1, weight = 100, name = "生命祝福", desc = "全体生命加成+8%",
      effectType = "stat", stats = { hpBonus = 8 } },
    { id = 4,  quality = 1, weight = 100, name = "精准之眼", desc = "全体暴击率+5%",
      effectType = "stat", stats = { critRate = 5 } },
    { id = 5,  quality = 1, weight = 100, name = "致命一击", desc = "全体暴击伤害+24%",
      effectType = "stat", stats = { critDmg = 24 } },
    { id = 6,  quality = 1, weight = 100, name = "风之步伐", desc = "全体闪避值+5",
      effectType = "stat", stats = { dodge = 5 } },

    -- ===== 品质2（权重70）：复合属性 + 条件效果 =====
    { id = 7,  quality = 2, weight = 70,  name = "连环打击", desc = "全体连击概率+6% 全体连击增伤+12%",
      effectType = "stat", stats = { comboRate = 6, comboBonus = 12 } },
    { id = 8,  quality = 2, weight = 70,  name = "生命汲取", desc = "全体生命加成+8% 全体攻击回血+8",
      effectType = "stat", stats = { hpBonus = 8, atkHeal = 8 } },
    { id = 9,  quality = 2, weight = 70,  name = "疾风先手", desc = "每次战斗开始时，全体攻击速度+20%",
      effectType = "stat", stats = { atkSpeed = 20 } },
    { id = 10, quality = 2, weight = 70,  name = "破甲之力", desc = "全体物理穿透与魔法穿透+8",
      effectType = "stat", stats = { physPen = 8, magPen = 8 } },
    { id = 11, quality = 2, weight = 70,  name = "绝境爆发", desc = "远征队员生命低于30%时，额外伤害+25%（乘法计算）",
      effectType = "mechanic", mechanicId = "low_hp_dmg_bonus", params = { threshold = 30, bonus = 25 } },
    { id = 12, quality = 2, weight = 70,  name = "强者之怒", desc = "远征队员生命高于80%时，额外伤害+20%（乘法计算）",
      effectType = "mechanic", mechanicId = "high_hp_dmg_bonus", params = { threshold = 80, bonus = 20 } },
    { id = 13, quality = 2, weight = 70,  name = "绝境护盾", desc = "远征队员生命低于30%时，受到伤害-50%（乘法计算）",
      effectType = "mechanic", mechanicId = "low_hp_dmg_reduce", params = { threshold = 30, reduce = 50 } },
    { id = 14, quality = 2, weight = 70,  name = "先发制人", desc = "战斗前30秒时，全体额外伤害+20%（乘法计算）",
      effectType = "mechanic", mechanicId = "early_dmg_bonus", params = { duration = 30, bonus = 20 } },
    { id = 15, quality = 2, weight = 70,  name = "铁壁防御", desc = "全体格挡比例+10%",
      effectType = "stat", stats = { blockRatio = 10 } },
    { id = 16, quality = 2, weight = 70,  name = "斩杀狂潮", desc = "每击杀一个敌人，全体伤害+5%，持续15秒（上限30%）",
      effectType = "mechanic", mechanicId = "kill_dmg_stack", params = { perKill = 5, duration = 15, cap = 30 } },

    -- ===== 品质3（权重50）：强力/职业专属 =====
    { id = 17, quality = 3, weight = 50,  name = "战意凝聚", desc = "每波开始每击杀一个敌人，全体生命加成+5%（上限50%）",
      effectType = "mechanic", mechanicId = "kill_hp_stack", params = { perKill = 5, cap = 50 } },
    { id = 18, quality = 3, weight = 50,  name = "连击风暴", desc = "全体连击增伤X2",
      effectType = "mechanic", mechanicId = "combo_dmg_double" },
    { id = 19, quality = 3, weight = 50,  name = "终结审判", desc = "对低于10%生命的目标，有10%概率直接消灭",
      effectType = "mechanic", mechanicId = "execute", params = { hpThreshold = 10, chance = 10 } },
    { id = 20, quality = 3, weight = 50,  name = "迅雷之势", desc = "全体攻击间隔-25%（乘法，相当于攻速额外+33%）",
      effectType = "mechanic", mechanicId = "interval_reduce", params = { reduce = 25 } },
    { id = 21, quality = 3, weight = 50,  name = "霜寒领域", desc = "每隔10秒，冰冻全体敌人2秒",
      effectType = "mechanic", mechanicId = "periodic_freeze", params = { interval = 10, duration = 2 } },
    { id = 22, quality = 3, weight = 50,  name = "战争催化", desc = "己方将提前15秒进入狂暴与超级狂暴",
      effectType = "mechanic", mechanicId = "early_rage", params = { advance = 15 } },
    { id = 23, quality = 3, weight = 50,  name = "亡者遗志", desc = "当有己方死亡时，剩余的己方单位在5秒内无法受到任何伤害",
      effectType = "mechanic", mechanicId = "death_immunity", params = { duration = 5 } },
    { id = 24, quality = 3, weight = 50,  name = "守护誓约", desc = "「封门人」仇恨值倍率+200%，且每场战斗开始时仇恨值额外+2000",
      effectType = "mechanic", mechanicId = "knight_threat", params = { mult = 200, initial = 2000 }, classReq = "knight" },
    { id = 25, quality = 3, weight = 50,  name = "不屈之盾", desc = "「封门人」生命低于[40%/20%]时，获得[20%/40%]伤害减免",
      effectType = "mechanic", mechanicId = "knight_fortify", params = { thresholds = {40, 20}, reduces = {20, 40} }, classReq = "knight" },
    { id = 26, quality = 3, weight = 50,  name = "嗜血狂战", desc = "「拾骸者」生命加成+1000%，但无法再受到任何恢复/治疗",
      effectType = "mechanic", mechanicId = "warrior_bloodlust", params = { hpBonus = 1000 }, classReq = "warrior" },
    { id = 27, quality = 3, weight = 50,  name = "狂战之魂", desc = "「拾骸者」生命值每减少5%，攻击速度+10%（实时检测）",
      effectType = "mechanic", mechanicId = "warrior_fury", params = { perLost = 5, atkSpeedPer = 10 }, classReq = "warrior" },
    { id = 28, quality = 3, weight = 50,  name = "蓄能爆裂", desc = "「裂隙使」攻击间隔延长100%，但额外伤害+200%（额外乘法计算）",
      effectType = "mechanic", mechanicId = "mage_charge_burst", params = { intervalMult = 100, dmgMult = 200 }, classReq = "mage" },
    { id = 29, quality = 3, weight = 50,  name = "奥术聚能", desc = "「裂隙使」每秒进行蓄力，获得20%额外伤害，当进行攻击时清空蓄力",
      effectType = "mechanic", mechanicId = "mage_accumulate", params = { perSec = 20 }, classReq = "mage" },
    { id = 30, quality = 3, weight = 50,  name = "精准连射", desc = "「回响客」进行攻击时有概率暴击2次造成「超暴击」（暴击后额外再判断一次暴击）",
      effectType = "mechanic", mechanicId = "ranger_super_crit", classReq = "ranger" },
    { id = 31, quality = 3, weight = 50,  name = "后援射击", desc = "「回响客」每当有一个「拾骸者/封门人」职业存活时，射手攻击速度额外+25%",
      effectType = "mechanic", mechanicId = "ranger_support", params = { perTank = 25 }, classReq = "ranger" },
    { id = 32, quality = 3, weight = 50,  name = "暗影锋刃", desc = "「换面人」暴击率+25%",
      effectType = "stat", stats = { critRate = 25 }, classReq = "assassin" },
    { id = 33, quality = 3, weight = 50,  name = "虚影闪避", desc = "「换面人」每次战斗免疫次数+10",
      effectType = "mechanic", mechanicId = "assassin_immunity", params = { count = 10 }, classReq = "assassin" },
    { id = 34, quality = 3, weight = 50,  name = "圣光恩赐", desc = "「司仪」治疗加成额外+35%",
      effectType = "stat", stats = { healBonus = 35 }, classReq = "priest" },
    { id = 35, quality = 3, weight = 50,  name = "生命圣约", desc = "「司仪」存活时，在场角色生命加成+30%",
      effectType = "mechanic", mechanicId = "priest_aura_hp", params = { hpBonus = 30 }, classReq = "priest" },
}

-- 按 ID 索引
TowerConfig.BUFFS_BY_ID = {}
for _, buff in ipairs(TowerConfig.BUFFS) do
    TowerConfig.BUFFS_BY_ID[buff.id] = buff
end

-- ======================== 查询接口 ========================

--- 获取指定层配置
---@param floor number 层数 (1~112)
---@return table|nil
function TowerConfig.getFloor(floor)
    if floor < 1 or floor > TowerConfig.MAX_FLOOR then return nil end
    return TowerConfig.FLOORS[floor]
end

--- 每五层一组的挑战起点；层号与旧首通账本不重编号。
---@param floor number
---@return integer
function TowerConfig.getCheckpointFloor(floor)
    local level = math.max(1, math.min(TowerConfig.MAX_FLOOR, math.floor(tonumber(floor) or 1)))
    return math.floor((level - 1) / TowerConfig.CHECKPOINT_INTERVAL) * TowerConfig.CHECKPOINT_INTERVAL + 1
end

---@param floor number
---@return boolean
function TowerConfig.isCheckpointFloor(floor)
    local level = math.tointeger(tonumber(floor) or 0)
    return level ~= nil and level >= 1 and level <= TowerConfig.MAX_FLOOR
        and (level - 1) % TowerConfig.CHECKPOINT_INTERVAL == 0
end

---@param startFloor number
---@return integer
function TowerConfig.getRunEndFloor(startFloor)
    return math.min(TowerConfig.MAX_FLOOR,
        TowerConfig.getCheckpointFloor(startFloor) + TowerConfig.CHECKPOINT_INTERVAL - 1)
end

--- 旧档 floor 表示下一未通层，数字/字符串首通键也能证明已通终层。
---@param bt table|nil
---@return integer
function TowerConfig.getHighestClearedFloor(bt)
    local highest = math.max(0, math.min(TowerConfig.MAX_FLOOR,
        math.floor(tonumber(bt and bt.floor) or 1) - 1))
    for key, cleared in pairs(bt and bt.cleared or {}) do
        local floor = math.tointeger(tonumber(key) or 0)
        if cleared == true and floor and floor > highest and floor <= TowerConfig.MAX_FLOOR then
            highest = floor
        end
    end
    return highest
end

---@param bt table|nil
---@return integer
function TowerConfig.getMaxUnlockedCheckpoint(bt)
    return TowerConfig.getCheckpointFloor(math.min(TowerConfig.MAX_FLOOR,
        TowerConfig.getHighestClearedFloor(bt) + 1))
end

--- 获取指定波次配置；单层只有波1，敌人组合随实际层号循环。
---@param wave number 波次 (1)
---@param floor number|nil 实际楼层，旧调用默认第1层
---@return table|nil
function TowerConfig.getWave(wave, floor)
    if wave ~= 1 then return nil end
    local floorCfg = TowerConfig.getFloor(floor or 1)
    return floorCfg and TowerConfig.WAVES[floorCfg.wavePattern] or nil
end

--- 按品质从怪物池随机抽取指定数量的怪物ID
---@param quality number 品质 (1~5)
---@param count number 数量
---@return number[] monsterIds
function TowerConfig.rollMonsters(quality, count)
    local pool = TowerConfig.MONSTER_POOL[quality]
    if not pool or #pool == 0 then return {} end
    local result = {}
    for i = 1, count do
        local idx = math.random(1, #pool)
        result[#result + 1] = pool[idx]
    end
    return result
end

--- 生成指定楼层唯一一波的完整怪物列表
---@param wave number 波次 (1)
---@param floor number|nil 实际楼层
---@return number[] monsterIds 所有抽取的怪物ID列表
function TowerConfig.generateWaveMonsters(wave, floor)
    local waveCfg = TowerConfig.getWave(wave, floor)
    if not waveCfg then return {} end
    local monsters = {}
    for q = 1, 5 do
        local count = waveCfg["q" .. q] or 0
        if count > 0 then
            local rolled = TowerConfig.rollMonsters(q, count)
            for _, mid in ipairs(rolled) do
                monsters[#monsters + 1] = mid
            end
        end
    end
    return monsters
end

--- 加权随机抽取N个不重复的强化词条
---@param count number 抽取数量（通常为3）
---@param excludeIds number[]|nil 排除的buff ID列表（已拥有的）
---@return table[] 抽取到的buff配置列表
function TowerConfig.rollBuffs(count, excludeIds)
    local excludeSet = {}
    if excludeIds then
        for _, id in ipairs(excludeIds) do
            excludeSet[id] = true
        end
    end

    -- 构建候选池
    local candidates = {}
    local totalWeight = 0
    for _, buff in ipairs(TowerConfig.BUFFS) do
        if not excludeSet[buff.id] then
            candidates[#candidates + 1] = buff
            totalWeight = totalWeight + buff.weight
        end
    end

    -- 加权随机抽取（不重复）
    local result = {}
    for _ = 1, math.min(count, #candidates) do
        local roll = math.random() * totalWeight
        local acc = 0
        for i, buff in ipairs(candidates) do
            acc = acc + buff.weight
            if roll <= acc then
                result[#result + 1] = buff
                totalWeight = totalWeight - buff.weight
                table.remove(candidates, i)
                break
            end
        end
    end

    return result
end

return TowerConfig
