-- ============================================================================
-- ArenaAITemplates - 竞技场 AI 阵容模板库
-- 职责: 根据段位桶生成 AI 防守阵容快照（与真实玩家快照格式完全一致）
-- 运行端: server（仅服务端使用，按需生成）
-- ============================================================================

local EquipmentSystem = require "systems.EquipmentSystem"
local ArenaConfig     = require "config.ArenaConfig"
local HC              = require "config.HeroConfig"
local AD              = require "systems.AttributeDef"
local AvatarFrameBridge = require "systems.AvatarFrameBridge"

local AIT = {}

-- ======================== 段位桶定义 ========================
-- 将 36 个段位映射为 4 个强度桶，用于控制 AI 阵容强度

AIT.TIER_BUCKET = {
    T1 = "T1",  -- 黑铁 + 青铜 (tier 1-10,  rankScore 0~999)
    T2 = "T2",  -- 白银 + 黄金 (tier 11-20, rankScore 1000~1999)
    T3 = "T3",  -- 铂金 + 钻石 (tier 21-30, rankScore 2000~3749)
    T4 = "T4",  -- 大师 + 传说 (tier 31-36, rankScore 3750+)
}

--- 根据段位分确定段位桶
---@param rankScore number 段位分
---@return string bucket "T1"/"T2"/"T3"/"T4"
function AIT.getTierBucket(rankScore)
    if rankScore >= 3750 then return AIT.TIER_BUCKET.T4 end
    if rankScore >= 2000 then return AIT.TIER_BUCKET.T3 end
    if rankScore >= 1000 then return AIT.TIER_BUCKET.T2 end
    return AIT.TIER_BUCKET.T1
end

-- ======================== 桶参数配置 ========================
-- 每个桶的英雄品质、等级范围、装备品质范围、天赋节点数

---@type table<string, table>
local BUCKET_PARAMS = {
    T1 = {
        heroQualities   = { 1, 1, 1, 2 },       -- R 为主，少量 SR
        levelRange      = { 1, 15 },
        equipQuality    = { 1, 2 },              -- 普通~优质
        equipLevelRange = { 1, 10 },
        talentNodes     = { 0, 5 },              -- 0~5 个天赋节点
        teamSizes       = { 2, 3 },              -- 2~3 个英雄
        powerRange      = { 500, 2000 },
    },
    T2 = {
        heroQualities   = { 1, 2, 2, 2 },        -- SR 为主，少量 R
        levelRange      = { 10, 30 },
        equipQuality    = { 1, 2, 3 },            -- 普通~稀有
        equipLevelRange = { 8, 25 },
        talentNodes     = { 3, 12 },
        teamSizes       = { 3, 4 },
        powerRange      = { 2000, 5000 },
    },
    T3 = {
        heroQualities   = { 2, 2, 3, 3 },         -- SSR 为主，少量 SR
        levelRange      = { 25, 50 },
        equipQuality    = { 2, 3, 4 },             -- 优质~史诗
        equipLevelRange = { 20, 45 },
        talentNodes     = { 8, 20 },
        teamSizes       = { 4, 5 },
        powerRange      = { 5000, 12000 },
    },
    T4 = {
        heroQualities   = { 2, 3, 3, 3 },          -- SSR 为主
        levelRange      = { 40, 60 },
        equipQuality    = { 3, 4, 5 },              -- 稀有~传说
        equipLevelRange = { 35, 60 },
        talentNodes     = { 15, 30 },
        teamSizes       = { 5, 5 },                 -- 满编 5 人
        powerRange      = { 12000, 25000 },
    },
}

-- ======================== 英雄 ID 按品质分类 ========================

local HEROES_BY_QUALITY = {
    [1] = { 1, 2, 3 },                            -- R:   大狗嚼、黄桃龙、叮咚鸡
    [2] = { 4, 5, 6, 7, 8, 9 },                   -- SR:  接化发掌门、叠甲怪、阿姨压、信光机兵、愤怒的小雀、卡皮巴拉
    [3] = { 10, 11, 12, 13, 14, 15, 21, 22, 23 },  -- SSR: 铁憨憨~复活吧爱人、闪电卖鸡、小黑子、真布诗人
}

-- ======================== 英雄 → 职业映射 ========================

local HERO_CLASS = {
    [1]  = "warrior",   -- 大狗嚼
    [2]  = "mage",      -- 黄桃龙
    [3]  = "ranger",    -- 叮咚鸡
    [4]  = "knight",    -- 接化发掌门
    [5]  = "warrior",   -- 叠甲怪
    [6]  = "mage",      -- 阿姨压
    [7]  = "ranger",    -- 信光机兵
    [8]  = "assassin",  -- 愤怒的小雀
    [9]  = "priest",    -- 卡皮巴拉
    [10] = "knight",    -- 铁憨憨
    [11] = "warrior",   -- 熬夜冠军
    [12] = "mage",      -- 雪皇
    [13] = "ranger",    -- 弹弹弹
    [14] = "assassin",  -- 内鬼
    [15] = "priest",    -- 复活吧爱人
    [21] = "warrior",   -- 闪电卖鸡
    [22] = "mage",      -- 小黑子
    [23] = "priest",    -- 真布诗人
}

-- ======================== 职业 → 武器模板 ID 池 ========================
-- 每个职业可用的武器模板 ID 范围（6 个模板对应 6 个等级梯度）

local CLASS_WEAPONS = {
    knight   = {
        { "W1", "W2", "W3", "W4", "W5", "W6" },       -- 单手剑
        { "W13", "W14", "W15", "W16", "W17", "W18" },  -- 单手斧
    },
    warrior  = {
        { "W7", "W8", "W9", "W10", "W11", "W12" },     -- 双手剑
        { "W19", "W20", "W21", "W22", "W23", "W24" },  -- 双手斧
    },
    mage     = {
        { "W25", "W26", "W27", "W28", "W29", "W30" },  -- 法杖
        { "W31", "W32", "W33", "W34", "W35", "W36" },  -- 魔杖
    },
    ranger   = {
        { "W37", "W38", "W39", "W40", "W41", "W42" },  -- 弓
        { "W43", "W44", "W45", "W46", "W47", "W48" },  -- 弩
    },
    assassin = {
        { "W55", "W56", "W57", "W58", "W59", "W60" },  -- 匕首
        { "W61", "W62", "W63", "W64", "W65", "W66" },  -- 细剑
    },
    priest   = {
        { "W67", "W68", "W69", "W70", "W71", "W72" },  -- 权杖
    },
}

-- 职业 → 副手模板 ID 池（部分职业无副手）
local CLASS_OFFHAND = {
    knight   = {
        { "O7", "O8", "O9", "O10", "O11", "O12" },    -- 重盾
    },
    mage     = {
        { "O13", "O14", "O15", "O16", "O17", "O18" }, -- 魔法书
        { "O19", "O20", "O21", "O22", "O23", "O24" }, -- 法球
    },
    priest   = {
        { "O25", "O26", "O27", "O28", "O29", "O30" }, -- 圣物
    },
    -- warrior, ranger, assassin: 无副手（双手武器或无需副手）
}

-- 职业 → 护甲模板 ID 池
local CLASS_ARMOR = {
    knight   = {
        { "A37", "A38", "A39", "A40", "A41", "A42" },  -- 板甲A
        { "A43", "A44", "A45", "A46", "A47", "A48" },  -- 板甲B
    },
    warrior  = {
        { "A25", "A26", "A27", "A28", "A29", "A30" },  -- 重甲A
        { "A31", "A32", "A33", "A34", "A35", "A36" },  -- 重甲B
    },
    mage     = {
        { "A49", "A50", "A51", "A52", "A53", "A54" },  -- 布甲A
        { "A55", "A56", "A57", "A58", "A59", "A60" },  -- 布甲B
    },
    ranger   = {
        { "A13", "A14", "A15", "A16", "A17", "A18" },  -- 轻甲A
        { "A19", "A20", "A21", "A22", "A23", "A24" },  -- 轻甲B
    },
    assassin = {
        { "A1", "A2", "A3", "A4", "A5", "A6" },       -- 皮甲A
        { "A7", "A8", "A9", "A10", "A11", "A12" },     -- 皮甲B
    },
    priest   = {
        { "A49", "A50", "A51", "A52", "A53", "A54" },  -- 布甲A (与法师共用)
        { "A55", "A56", "A57", "A58", "A59", "A60" },  -- 布甲B
    },
}

-- ======================== 工具函数 ========================

--- 在 [min, max] 范围内生成随机整数
local function randInt(min, max)
    return math.random(min, max)
end

--- 从数组中随机选取一个元素
local function randPick(arr)
    return arr[math.random(1, #arr)]
end

--- 从数组中随机选取 n 个不重复元素
local function randPickN(arr, n)
    if n >= #arr then
        local copy = {}
        for i = 1, #arr do copy[i] = arr[i] end
        return copy
    end
    -- Fisher–Yates 部分洗牌
    local pool = {}
    for i = 1, #arr do pool[i] = arr[i] end
    local result = {}
    for i = 1, n do
        local j = math.random(i, #pool)
        pool[i], pool[j] = pool[j], pool[i]
        result[i] = pool[i]
    end
    return result
end

--- 根据等级范围 [1-6] 选择模板组内对应的模板 ID
--- templateGroup: {"W1","W2","W3","W4","W5","W6"} (6个等级梯度)
--- equipLevel: 装备等级 → 映射到 1~6 梯度
local function pickTemplateByLevel(templateGroup, equipLevel)
    -- 每个模板组有 6 个，对应 6 个梯度
    -- 等级 1-10 → 梯度 1, 10-20 → 梯度 2, ... 50-60 → 梯度 6
    local tier = math.min(6, math.max(1, math.ceil(equipLevel / 10)))
    return templateGroup[tier]
end

-- ======================== 装备生成 ========================

--- 为指定职业生成一套装备（武器 + 可选副手 + 护甲 + 饰品）
---@param classId string 职业 ID
---@param equipLevel number 装备等级
---@param qualityPool number[] 可用品质列表（如 {1,2,3}）
---@return table<string, table> equipMap { [slot] = equipItem }
local function generateClassEquipment(classId, equipLevel, qualityPool)
    local equipMap = {}

    -- 武器
    local weaponGroups = CLASS_WEAPONS[classId]
    if weaponGroups then
        local group = randPick(weaponGroups)
        local templateId = pickTemplateByLevel(group, equipLevel)
        local quality = randPick(qualityPool)
        local item = EquipmentSystem.generate(templateId, equipLevel, quality)
        if item then
            equipMap["weapon"] = item
        end
    end

    -- 副手（部分职业有）
    local offhandGroups = CLASS_OFFHAND[classId]
    if offhandGroups then
        local group = randPick(offhandGroups)
        local templateId = pickTemplateByLevel(group, equipLevel)
        local quality = randPick(qualityPool)
        local item = EquipmentSystem.generate(templateId, equipLevel, quality)
        if item then
            equipMap["offhand"] = item
        end
    end

    -- 护甲
    local armorGroups = CLASS_ARMOR[classId]
    if armorGroups then
        local group = randPick(armorGroups)
        local templateId = pickTemplateByLevel(group, equipLevel)
        local quality = randPick(qualityPool)
        local item = EquipmentSystem.generate(templateId, equipLevel, quality)
        if item then
            equipMap["armor"] = item
        end
    end

    -- 饰品（所有职业通用，C1-C36 共 3 类 × 12 个）
    local accTypes = {
        { "C1", "C2", "C3", "C4", "C5", "C6" },       -- 戒指前半
        { "C7", "C8", "C9", "C10", "C11", "C12" },     -- 戒指后半
        { "C13", "C14", "C15", "C16", "C17", "C18" },   -- 项链前半
        { "C19", "C20", "C21", "C22", "C23", "C24" },   -- 项链后半
        { "C25", "C26", "C27", "C28", "C29", "C30" },   -- 耳环前半
        { "C31", "C32", "C33", "C34", "C35", "C36" },   -- 耳环后半
    }
    local accGroup = randPick(accTypes)
    local accTemplate = pickTemplateByLevel(accGroup, equipLevel)
    local accQuality = randPick(qualityPool)
    local accItem = EquipmentSystem.generate(accTemplate, equipLevel, accQuality)
    if accItem then
        equipMap["accessory"] = accItem
    end

    return equipMap
end

-- ======================== 战斗力计算 ========================
-- 与客户端 CharacterPanel.calcHeroPower 使用完全相同的公式：
-- 遍历属性 × valueModel 加权求和，跳过六围（已通过派生反映）和运行时属性

local POWER_SKIP = {
    [AD.STR] = true, [AD.AGI] = true, [AD.INT] = true,
    [AD.VIT] = true, [AD.LUK] = true, [AD.SPI] = true,
    [AD.HP]           = true,
    [AD.ATK_INTERVAL] = true,
    [AD.PHYS_RES]     = true,
    [AD.MAG_RES]      = true,
}

--- 计算单个英雄的战斗力（含装备）
---@param heroId number 英雄 ID
---@param level number 英雄等级
---@param equipMap table<string, table>|nil 该英雄的装备表 { [slot]=equipItem }
---@param advBranch table|nil 转职分支
---@param awakening table|nil 觉醒数据
---@param unlockedAvatarFrames table|nil 已解锁头像框集合（真实玩家快照）
---@return number power
local function calcHeroPower(heroId, level, equipMap, advBranch, awakening, unlockedAvatarFrames)
    local hero = HC.createHero(heroId, level, advBranch, awakening)
    if not hero or not hero.attrs then return 0 end
    local a = hero.attrs

    -- 应用装备属性
    if equipMap then
        local seq = 0
        for _, equip in pairs(equipMap) do
            seq = seq + 1
            EquipmentSystem.applyToUnit(a, equip, 90000 + seq)  -- 用大序号避免冲突
        end
    end

    AvatarFrameBridge.applyToUnit(a, unlockedAvatarFrames)

    local total = 0
    for key, meta in pairs(AD.META) do
        if not POWER_SKIP[key] and meta.valueModel and meta.valueModel > 0 then
            local val = a:get(key)
            if meta.dataType == AD.TYPE_PCT then
                total = total + val * (meta.valueModel / 100)
            else
                total = total + val * meta.valueModel
            end
        end
    end
    return math.floor(total + 0.5)
end

--- 计算整个 AI 防守阵容的总战斗力
---@param heroSnap table[] 英雄快照数组
---@param equipSnap table<number, table> 装备快照 { [heroId] = equipMap }
---@param unlockedAvatarFrames table|nil 已解锁头像框集合
---@return number totalPower
local function calcDefensePower(heroSnap, equipSnap, unlockedAvatarFrames)
    local total = 0
    for _, hs in ipairs(heroSnap) do
        local eMap = equipSnap and equipSnap[hs.heroId] or nil
        total = total + calcHeroPower(
            hs.heroId,
            hs.level,
            eMap,
            hs.advBranch,
            hs.awakening,
            unlockedAvatarFrames
        )
    end
    return total
end

-- ======================== 核心 API ========================

--- 生成 AI 防守阵容快照
--- 返回格式与真实玩家的 buildDefenseSnapshot() 完全一致
---@param tierBucket string "T1"/"T2"/"T3"/"T4"
---@return table defense { heroes, equipment, talents, power, timestamp }
function AIT.generateDefense(tierBucket)
    local params = BUCKET_PARAMS[tierBucket]
    if not params then
        params = BUCKET_PARAMS.T1
    end

    -- 1. 确定队伍规模
    local teamSize = randInt(params.teamSizes[1], params.teamSizes[2])

    -- 2. 随机选取英雄（不重复）
    -- 先按品质分布构建候选池
    local candidatePool = {}
    for _, q in ipairs(params.heroQualities) do
        local heroes = HEROES_BY_QUALITY[q]
        if heroes then
            for _, hid in ipairs(heroes) do
                candidatePool[#candidatePool + 1] = hid
            end
        end
    end
    -- 去重
    local seen = {}
    local uniquePool = {}
    for _, hid in ipairs(candidatePool) do
        if not seen[hid] then
            seen[hid] = true
            uniquePool[#uniquePool + 1] = hid
        end
    end
    local selectedHeroes = randPickN(uniquePool, teamSize)

    -- 3. 生成英雄快照 + 装备快照
    local heroSnap = {}
    local equipSnap = {}
    local equipLevel = randInt(params.equipLevelRange[1], params.equipLevelRange[2])

    for _, heroId in ipairs(selectedHeroes) do
        local level = randInt(params.levelRange[1], params.levelRange[2])
        heroSnap[#heroSnap + 1] = {
            heroId    = heroId,
            level     = level,
            exp       = 0,
            advBranch = nil,  -- AI 暂不使用进阶分支
        }

        -- 生成该英雄的装备
        local classId = HERO_CLASS[heroId]
        if classId then
            local eMap = generateClassEquipment(classId, equipLevel, params.equipQuality)
            if next(eMap) then
                equipSnap[heroId] = eMap
            end
        end
    end

    -- 4. 生成天赋快照（简化：用连续节点 ID 模拟）
    local talentSnap = nil
    local nodeCount = randInt(params.talentNodes[1], params.talentNodes[2])
    if nodeCount > 0 then
        local litNodes = {}
        for i = 0, nodeCount - 1 do
            litNodes[#litNodes + 1] = i
        end
        talentSnap = { litNodes = litNodes }
    end

    -- 5. 根据实际英雄属性 + 装备计算真实战力值
    local power = calcDefensePower(heroSnap, equipSnap)

    return {
        heroes    = heroSnap,
        equipment = equipSnap,
        talents   = talentSnap,
        power     = power,
        timestamp = os.time(),
    }
end

--- 为 AI 玩家生成防守快照（便捷入口，根据 AI 的 rankScore 自动选择桶）
---@param rankScore number AI 玩家的段位分
---@return table defense 防守快照
function AIT.generateDefenseByScore(rankScore)
    local bucket = AIT.getTierBucket(rankScore)
    return AIT.generateDefense(bucket)
end

--- 随机生成 AI 的段位分（在指定桶范围内）
---@param tierBucket string "T1"/"T2"/"T3"/"T4"
---@return number rankScore
function AIT.randomRankScore(tierBucket)
    local ranges = {
        T1 = { 0, 999 },
        T2 = { 1000, 1999 },
        T3 = { 2000, 3749 },
        T4 = { 3750, 5500 },
    }
    local r = ranges[tierBucket] or ranges.T1
    return randInt(r[1], r[2])
end

--- 根据段位分生成合理的战力值（用于排名列表中 AI 条目显示）
--- 内部生成一次临时阵容并计算真实战斗力，确保展示值与对战实力一致
---@param rankScore number 段位分
---@return number power 战力值
function AIT.randomPowerByScore(rankScore)
    local defense = AIT.generateDefenseByScore(rankScore)
    return defense.power
end

--- 根据段位分和确定性种子生成战力值（兜底填充用，保证同参数产出一致）
--- 使用 math.randomseed 保证同种子 → 同阵容 → 同战力
---@param rankScore number 段位分
---@param seed number 确定性种子（如 groupId * 1000 + i）
---@return number power 战力值
function AIT.deterministicPowerByScore(rankScore, seed)
    math.randomseed(seed)
    local defense = AIT.generateDefenseByScore(rankScore)
    -- 恢复随机性（用当前时间重新播种，避免后续 random 受种子影响）
    math.randomseed(os.time() + seed)
    return defense.power
end

--- 计算防守阵容总战力（公共接口，供 ArenaService 实时计算真实玩家战力）
---@param heroSnap table[] 英雄快照数组 { heroId, level, advBranch }
---@param equipSnap table<number, table> 装备快照 { [heroId] = equipMap }
---@param unlockedAvatarFrames table|nil 已解锁头像框集合
---@return number totalPower
function AIT.calcDefensePower(heroSnap, equipSnap, unlockedAvatarFrames)
    return calcDefensePower(heroSnap, equipSnap, unlockedAvatarFrames)
end

return AIT
