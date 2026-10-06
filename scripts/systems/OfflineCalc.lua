-- ============================================================================
-- OfflineCalc - 挂机/离线收益计算模块
-- 职责: 离线按每支非空队伍当前关独立计算；旧在线结算保留账户双锚点兼容
-- 运行端: server
-- 公式: 每队 kills = seconds × IDLE_KILL_RATE；时间边界只计算一次，不按队叠加
-- ============================================================================

local MC = require("config.MonsterConfig")
local SC = require("config.StageConfig")
local ET = require("config.ExpTable")
local StageUtils = require("shared.StageUtils")
local EquipmentSystem = require("systems.EquipmentSystem")
local IdleIncomeConfig = require("config.IdleIncomeConfig")
local DC = require("config.DungeonConfig")

---@class OfflineTeamSpec
---@field teamIdx number
---@field stageId number
---@field heroCount number

---@class OfflineTeamReward: OfflineTeamSpec
---@field gold number
---@field diamond number
---@field adventureExp number
---@field adventurerExp number
---@field kills number
---@field equipSeeds table[]
---@field scrollDrops table<string, number>

---@class OfflineTeamRewards
---@field gold number
---@field diamond number
---@field adventureExp number
---@field adventurerExp number
---@field kills number
---@field equipSeeds table[]
---@field scrollDrops table<string, number>
---@field teamRewards OfflineTeamReward[]
---@field seconds number
---@field rawSeconds number
---@field effectiveSeconds number
---@field fullRateSeconds number
---@field tailRatio number
---@field maxSeconds number
---@field hardCapSeconds number
---@field cappedByHardCap boolean
---@field grantedEquips table[]|nil

local OfflineCalc = {}

-- ======================== 常量 ========================

OfflineCalc.IDLE_KILL_RATE    = 1/3     -- 固定杀怪效率：每 3 秒 1 只（在线/离线通用）
OfflineCalc.FULL_RATE_SECONDS = 86400   -- 离线前 24 小时按满额计
OfflineCalc.TAIL_RATIO        = 0.5     -- 超过 24 小时的部分按 50% 计
OfflineCalc.HARD_CAP_SECONDS  = 86400 * 7  -- 硬顶：离线收益最多累积 7 日，超出部分不再产生任何收益
OfflineCalc.MAX_SECONDS       = OfflineCalc.FULL_RATE_SECONDS  -- 兼容旧字段：进度条满格点
OfflineCalc.MIN_SECONDS       = 60      -- 最少 1 分钟才产生收益（离线入口使用）
OfflineCalc.SWEEP_STAGE_COUNT = 5       -- 覆盖关卡数（与扫荡一致）

--- 把实际离线秒数收敛到硬顶内（收益与掉落共用同一上限）
---@param seconds number
---@return number capped
function OfflineCalc.capSeconds(seconds)
    local raw = math.max(0, seconds)
    if raw > OfflineCalc.HARD_CAP_SECONDS then
        return OfflineCalc.HARD_CAP_SECONDS
    end
    return raw
end

--- 离线有效秒数：先按 HARD_CAP_SECONDS 截断，前 FULL_RATE_SECONDS 满额，超出部分按 TAIL_RATIO
---@param seconds number
---@return number effective
function OfflineCalc.effectiveOfflineSeconds(seconds)
    local raw = OfflineCalc.capSeconds(seconds)
    local full = OfflineCalc.FULL_RATE_SECONDS
    if raw <= full then return raw end
    return full + (raw - full) * OfflineCalc.TAIL_RATIO
end

--- 解析账户挂机收益锚点；队伍当前关与模式不代表账户最高节点是否已通。
--- 最高普通节点有首通凭据时用本关，否则保守回前关；难度首关跨回上一难度。
--- 终焉不在普通收益表中，无论是否已通都使用同难度末关。
---@param battleData table|nil
---@param stageConfig table|nil
---@return number stageId
function OfflineCalc.resolveIdleIncomeStageId(battleData, stageConfig)
    local cfg = stageConfig or SC
    if not battleData then return 101 end
    local maxId = tonumber(battleData.maxStageId) or tonumber(battleData.currentStageId) or 101

    if cfg.isTerminalTemple and cfg.isTerminalTemple(maxId) then
        return cfg.getTerminalPrevStageId(maxId) or maxId
    end
    local ledger = type(battleData.clearedStages) == "table" and battleData.clearedStages or {}
    if ledger[maxId] == true or ledger[tostring(maxId)] == true then
        return maxId
    end
    local previous = cfg.getPrevStageId(maxId)
    if not previous and cfg.getLastStageOfPrevDifficulty then
        previous = cfg.getLastStageOfPrevDifficulty(maxId)
    end
    return previous or maxId
end

--- 掉落采用账户最高节点的排除式边界，collectPrevStages负责取前五关。
--- 不读取队一旧关或模式；终焉的同难度前驱在核心计算中单独处理。
---@param battleData table|nil
---@param stageConfig table|nil
---@return number stageId
function OfflineCalc.resolveIdleDropStageId(battleData, stageConfig)
    if not battleData then return 101 end
    return tonumber(battleData.maxStageId) or tonumber(battleData.currentStageId) or 101
end

--- 统一入口：解析 battle 模块上的双锚点
---@param battleData table|nil
---@param stageConfig table|nil
---@return number incomeStageId
---@return number dropStageId
function OfflineCalc.resolveIdleStageAnchors(battleData, stageConfig)
    local incomeStageId = OfflineCalc.resolveIdleIncomeStageId(battleData, stageConfig)
    local dropStageId   = OfflineCalc.resolveIdleDropStageId(battleData, stageConfig)
    return incomeStageId, dropStageId
end

-- ======================== 内部工具 ========================

local function getMaxDropQuality(stageConfig, stageEntry)
    local cfg = stageConfig or SC
    if cfg.getMaxDropQuality then
        return cfg.getMaxDropQuality(stageEntry)
    end
    return SC.getMaxDropQuality(stageEntry)
end

--- 构建品质池（普通怪 + Boss），与 DropSystem.pickMonsterQuality 保持一致
---@param stageEntry table
---@return table pool  怪物 ID 数组（含 Boss）
local function buildQualityPool(stageEntry)
    local pool = {}
    local monsters = stageEntry.monsters
    if monsters then
        for _, id in ipairs(monsters) do
            pool[#pool + 1] = id
        end
    end
    -- Boss 也加入品质池（与 DropSystem 一致）
    if stageEntry.bossId and stageEntry.bossId > 0 then
        pool[#pool + 1] = stageEntry.bossId
    end
    return pool
end

--- 将 source 中的装备种子合并到 dest（同 stageId+quality+level 累加 count）
---@param dest table
---@param source table
local function mergeEquipSeedsInto(dest, source)
    for _, seed in ipairs(source) do
        local found = false
        for _, existing in ipairs(dest) do
            if existing.stageId == seed.stageId
                and existing.quality == seed.quality
                and existing.level == seed.level then
                existing.count = existing.count + seed.count
                found = true
                break
            end
        end
        if not found then
            dest[#dest + 1] = {
                stageId = seed.stageId,
                quality = seed.quality,
                level   = seed.level,
                count   = seed.count,
            }
        end
    end
end

--- 将 source 中的卷轴掉落合并到 dest
---@param dest table
---@param source table
local function mergeScrollDropsInto(dest, source)
    for k, v in pairs(source) do
        dest[k] = (dest[k] or 0) + v
    end
end

-- ======================== 奖励计算 ========================

--- 根据击杀数计算奖励（单关卡）
---@param kills number      击杀数
---@param stageEntry table  关卡配置
---@param heroCount number  出战英雄数量
---@param stageConfig table|nil
---@return table rewards
function OfflineCalc.calcRewardsFromKills(kills, stageEntry, heroCount, stageConfig)
    local monsterLevel = math.min(stageEntry.monsterLevel or 1, 60)
    local levelData = MC.LEVELS[monsterLevel]
    if not levelData then
        return { gold = 0, adventureExp = 0, adventurerExp = 0, equipSeeds = {}, scrollDrops = {} }
    end

    -- 计算怪物类型的平均经验/金币倍率
    -- 挂机模式每关出 2 只怪：
    --   Boss 关（bossId > 0）: 1 只普通怪 + 1 只 Boss
    --   非 Boss 关: 2 只普通怪（轮询 stageEntry.monsters）
    -- 因此平均倍率需要按实际出怪组成加权计算
    local monsterTypes = stageEntry.monsters or {}
    if #monsterTypes == 0 then
        return { gold = 0, adventureExp = 0, adventurerExp = 0, equipSeeds = {}, scrollDrops = {} }
    end

    local hasBoss = stageEntry.bossId and stageEntry.bossId > 0
    local totalExpMult  = 0
    local totalGoldMult = 0
    local totalCount    = 0

    if hasBoss then
        -- Boss 关: 1 只普通（取第一种）+ 1 只 Boss
        local normalTemplate = MC.MONSTERS[monsterTypes[1]]
        if normalTemplate then
            local qd = MC.QUALITY[normalTemplate.quality] or MC.QUALITY[1]
            totalExpMult  = totalExpMult  + qd.expMult
            totalGoldMult = totalGoldMult + qd.goldMult
            totalCount    = totalCount + 1
        end
        local bossTemplate = MC.MONSTERS[stageEntry.bossId]
        if bossTemplate then
            local qd = MC.QUALITY[bossTemplate.quality] or MC.QUALITY[1]
            totalExpMult  = totalExpMult  + qd.expMult
            totalGoldMult = totalGoldMult + qd.goldMult
            totalCount    = totalCount + 1
        end
    else
        -- 非 Boss 关: 2 只普通怪轮询（与 generateIdleEnemyList 一致）
        local perStage = 2
        for i = 1, perStage do
            local typeIdx = ((i - 1) % #monsterTypes) + 1
            local template = MC.MONSTERS[monsterTypes[typeIdx]]
            if template then
                local qd = MC.QUALITY[template.quality] or MC.QUALITY[1]
                totalExpMult  = totalExpMult  + qd.expMult
                totalGoldMult = totalGoldMult + qd.goldMult
                totalCount    = totalCount + 1
            end
        end
    end

    if totalCount == 0 then
        return { gold = 0, adventureExp = 0, adventurerExp = 0, equipSeeds = {}, scrollDrops = {} }
    end
    local avgExpMult  = totalExpMult  / totalCount
    local avgGoldMult = totalGoldMult / totalCount

    -- 单次击杀的经验/金币
    local expPerKill  = math.floor(levelData.baseExp  * avgExpMult  + 0.5)
    local goldPerKill = math.floor(levelData.goldDrop * avgGoldMult + 0.5)

    -- 总量
    local totalGold = goldPerKill * kills
    local totalExp  = expPerKill  * kills

    -- 英雄经验乘以出战人数系数
    local heroCountMult = ET.getHeroCountExpMult(heroCount)
    local totalHeroExp = math.floor(totalExp * heroCountMult)

    -- 装备掉落种子（按 dropRate 概率，装备品质由怪物品质决定）
    -- 使用概率取整：小数部分作为额外掉落概率，避免低击杀数时永远为0
    local dropRate = stageEntry.dropRate or 0.05
    local rawEquipCount = kills * dropRate
    local equipCount = math.floor(rawEquipCount)
    local equipFrac = rawEquipCount - equipCount
    if equipFrac > 0 and math.random() < equipFrac then
        equipCount = equipCount + 1
    end
    local equipSeeds = {}
    if equipCount > 0 then
        local qualityPool = buildQualityPool(stageEntry)
        local poolSize = #qualityPool
        local maxDropQ = getMaxDropQuality(stageConfig, stageEntry)
        for i = 1, equipCount do
            local quality
            if poolSize > 0 then
                local typeIdx = ((i - 1) % poolSize) + 1
                local monsterId = qualityPool[typeIdx]
                local template = MC.MONSTERS[monsterId]
                local monsterQ = template and template.quality or 1
                quality = OfflineCalc._rollQualityByMonster(monsterQ)
            else
                quality = 1
            end
            if quality > maxDropQ then quality = maxDropQ end
            equipSeeds[#equipSeeds + 1] = {
                stageId = stageEntry.id,
                quality = quality,
                level   = stageEntry.monsterLevel,
                count   = 1,
            }
        end
        equipSeeds = OfflineCalc._mergeSeeds(equipSeeds)
    end

    -- 卷轴掉落（同样使用概率取整）
    local scrollDropRate = stageEntry.scrollDropRate or 0
    local scrollDrops = {}
    if scrollDropRate > 0 then
        local scrollTypes = { "weaponScroll", "offhandScroll", "armorScroll", "helmetScroll", "shoesScroll", "accessoryScroll" }
        local rawScrollCount = kills * scrollDropRate
        local totalScrolls = math.floor(rawScrollCount)
        local scrollFrac = rawScrollCount - totalScrolls
        if scrollFrac > 0 and math.random() < scrollFrac then
            totalScrolls = totalScrolls + 1
        end
        for _ = 1, totalScrolls do
            local st = scrollTypes[math.random(1, #scrollTypes)]
            scrollDrops[st] = (scrollDrops[st] or 0) + 1
        end
    end
    -- 扫荡券：约每 5 只怪 1 张，比卷轴更频繁
    local ticketRate = math.min(0.35, math.max(0.12, scrollDropRate * 4))
    if ticketRate <= 0 then ticketRate = 0.20 end
    local rawTickets = kills * ticketRate
    local ticketCount = math.floor(rawTickets)
    if math.random() < (rawTickets - ticketCount) then
        ticketCount = ticketCount + 1
    end
    if ticketCount > 0 then
        scrollDrops.sweepTicket = ticketCount
    end

    return {
        gold          = totalGold,
        adventureExp  = totalExp,
        adventurerExp = totalHeroExp,
        equipSeeds    = equipSeeds,
        scrollDrops   = scrollDrops,
    }
end

--- 根据怪物品质加权随机装备品质 (1-6)
---@param monsterQuality number 怪物品质 1~6
---@return number quality 1~6
function OfflineCalc._rollQualityByMonster(monsterQuality)
    local qualityData = MC.QUALITY[monsterQuality] or MC.QUALITY[1]
    local dw = qualityData.dropWeights
    local totalWeight = 0
    for i = 1, 6 do totalWeight = totalWeight + (dw[i] or 0) end
    if totalWeight <= 0 then return 1 end

    local roll = math.random(totalWeight)
    local acc = 0
    for i = 1, 6 do
        acc = acc + (dw[i] or 0)
        if roll <= acc then return i end
    end
    return 1
end

--- 合并 stageId+quality+level 相同的种子，累加 count
---@param seeds table
---@return table merged
function OfflineCalc._mergeSeeds(seeds)
    local map = {}
    local result = {}
    for _, seed in ipairs(seeds) do
        local key = seed.stageId .. "_" .. seed.quality .. "_" .. seed.level
        if map[key] then
            map[key].count = map[key].count + seed.count
        else
            local entry = {
                stageId = seed.stageId,
                quality = seed.quality,
                level   = seed.level,
                count   = seed.count,
            }
            map[key] = entry
            result[#result + 1] = entry
        end
    end
    return result
end

--- 根据击杀数构建装备种子列表（独立接口，供外部直接调用）
---@param kills number
---@param stageEntry table
---@param stageConfig table|nil
---@return table equipSeeds
function OfflineCalc.buildEquipSeeds(kills, stageEntry, stageConfig)
    local dropRate = stageEntry.dropRate or 0.05
    local rawCount = kills * dropRate
    local equipCount = math.floor(rawCount)
    local frac = rawCount - equipCount
    if frac > 0 and math.random() < frac then
        equipCount = equipCount + 1
    end
    if equipCount <= 0 then return {} end

    local qualityPool = buildQualityPool(stageEntry)
    local poolSize = #qualityPool
    local maxDropQ = getMaxDropQuality(stageConfig, stageEntry)
    local equipSeeds = {}

    for i = 1, equipCount do
        local quality
        if poolSize > 0 then
            local typeIdx = ((i - 1) % poolSize) + 1
            local monsterId = qualityPool[typeIdx]
            local template = MC.MONSTERS[monsterId]
            local monsterQ = template and template.quality or 1
            quality = OfflineCalc._rollQualityByMonster(monsterQ)
        else
            quality = 1
        end
        if quality > maxDropQ then quality = maxDropQ end
        equipSeeds[#equipSeeds + 1] = {
            stageId = stageEntry.id,
            quality = quality,
            level   = stageEntry.monsterLevel,
            count   = 1,
        }
    end
    return OfflineCalc._mergeSeeds(equipSeeds)
end

--- 根据击杀数构建卷轴掉落（独立接口）
---@param kills number
---@param stageEntry table
---@return table scrollDrops { weaponScroll=N, ... }
function OfflineCalc.buildScrollDrops(kills, stageEntry)
    local scrollDropRate = stageEntry.scrollDropRate or 0
    if scrollDropRate <= 0 then return {} end

    local scrollTypes = { "weaponScroll", "offhandScroll", "armorScroll", "helmetScroll", "shoesScroll", "accessoryScroll" }
    local rawCount = kills * scrollDropRate
    local totalScrolls = math.floor(rawCount)
    local frac = rawCount - totalScrolls
    if frac > 0 and math.random() < frac then
        totalScrolls = totalScrolls + 1
    end
    local scrollDrops = {}
    for _ = 1, totalScrolls do
        local st = scrollTypes[math.random(1, #scrollTypes)]
        scrollDrops[st] = (scrollDrops[st] or 0) + 1
    end
    return scrollDrops
end

-- ======================== v2 核心：统一挂机计算 ========================

--- 内部核心计算（纯逻辑，无策略门槛）
--- 基于 IDLE_KILL_RATE × 时间 计算击杀数，再分配到 dropStageId 前 N 关
---@param seconds number    金币/经验所用秒数（离线入口传入折算后的有效秒数）
---@param incomeStageId number  金币/经验查表锚点（IdleIncomeConfig）
---@param heroCount number  出战英雄数
---@param dropStageId number|nil  装备/卷轴混合掉落锚点（默认与 incomeStageId 相同）
---@param stageConfig table|nil
---@param dropSeconds number|nil  掉落所用秒数，省略则与 seconds 相同
---@return table|nil rewards
local function _calcIdleCore(seconds, incomeStageId, heroCount, dropStageId, stageConfig, dropSeconds)
    local cfg = stageConfig or SC
    dropStageId = dropStageId or incomeStageId
    local totalKills = math.floor((dropSeconds or seconds) * OfflineCalc.IDLE_KILL_RATE)
    if totalKills <= 0 then return nil end

    -- 终焉关号不是普通关序号；下一难度首关仅作排除式遍历边界，
    -- 使掉落来自同难度末关起的前五关，不授予下一难度收益或解锁。
    local dropBoundary = dropStageId
    if cfg.isTerminalTemple and cfg.isTerminalTemple(dropStageId) then
        local target = cfg.getReincarnationTarget(cfg.getDifficulty(dropStageId))
        if target then dropBoundary = target end
    end
    local stages = StageUtils.collectPrevStages(dropBoundary, OfflineCalc.SWEEP_STAGE_COUNT, cfg)
    if #stages == 0 then
        -- fallback: 如果前面无关卡（刚开始游戏），尝试用 dropStageId 本身
        local entry = cfg.getStage(dropStageId)
        if not entry then return nil end
        stages = { entry }
    end

    -- 击杀数平均分配到各关卡（余数分配给前几关）
    local killsPerStage = math.floor(totalKills / #stages)
    local remainder = totalKills - killsPerStage * #stages

    local totalGold, totalExp, totalHeroExp = 0, 0, 0
    local allEquipSeeds = {}
    local allScrollDrops = {}

    for i, stageEntry in ipairs(stages) do
        local stageKills = killsPerStage + (i <= remainder and 1 or 0)
        if stageKills > 0 then
            local r = OfflineCalc.calcRewardsFromKills(stageKills, stageEntry, heroCount, cfg)
            totalGold    = totalGold    + r.gold
            totalExp     = totalExp     + r.adventureExp
            totalHeroExp = totalHeroExp + r.adventurerExp
            mergeEquipSeedsInto(allEquipSeeds, r.equipSeeds)
            mergeScrollDropsInto(allScrollDrops, r.scrollDrops)
        end
    end

    -- 金币/玩家经验按关卡查表，英雄经验沿用 heroCountMult
    -- gold / adventureExp（玩家经验）直接由 IdleIncomeConfig 按关卡查表得到，
    -- 按 seconds/60 比例缩放；adventurerExp（英雄经验）沿用原有 heroCountMult 关系。
    -- equipSeeds / scrollDrops 仍由上方击杀计算驱动（不改变掉落逻辑）。
    local cfgGoldPerMin, cfgExpPerMin = IdleIncomeConfig.get(incomeStageId)
    local minutes = seconds / 60
    local newGold = math.floor(cfgGoldPerMin * minutes + 0.5)
    local newExp  = math.floor(cfgExpPerMin * minutes + 0.5)
    local heroCountMult = ET.getHeroCountExpMult(heroCount)
    local newHeroExp = math.floor(newExp * heroCountMult + 0.5)

    return {
        gold          = newGold,
        adventureExp  = newExp,
        adventurerExp = newHeroExp,
        equipSeeds    = allEquipSeeds,
        scrollDrops   = allScrollDrops,
        kills         = totalKills,
        seconds       = seconds,
    }
end

--- 【入口 A】离线面板结算
--- 前 24 小时满额，超出部分按 TAIL_RATIO 计，硬顶 HARD_CAP_SECONDS（7 日）。门槛仍是 MIN_SECONDS。
---@param seconds number  实际离线秒数
---@param incomeStageId number  金币/经验锚点
---@param heroCount number
---@param dropStageId number|nil  掉落混合锚点（省略则与 incomeStageId 相同）
---@param stageConfig table|nil
---@return table|nil rewards
function OfflineCalc.calcOfflineIdleRewards(seconds, incomeStageId, heroCount, dropStageId, stageConfig)
    local rawActual = math.max(0, seconds)
    if rawActual < OfflineCalc.MIN_SECONDS then return nil end
    -- 硬顶：超过 7 日的部分不计收益也不计掉落
    local raw = OfflineCalc.capSeconds(rawActual)
    local effective = OfflineCalc.effectiveOfflineSeconds(raw)
    -- 金币/经验吃折算时长；装备和卷轴按封顶后的离线时长掉，避免长时间离线反而少掉东西
    local rewards = _calcIdleCore(effective, incomeStageId, heroCount, dropStageId, stageConfig, raw)
    if rewards then
        rewards.rawSeconds = rawActual
        rewards.seconds = raw
        rewards.effectiveSeconds = effective
        rewards.fullRateSeconds = OfflineCalc.FULL_RATE_SECONDS
        rewards.tailRatio = OfflineCalc.TAIL_RATIO
        rewards.maxSeconds = OfflineCalc.FULL_RATE_SECONDS
        rewards.hardCapSeconds = OfflineCalc.HARD_CAP_SECONDS
        rewards.cappedByHardCap = rawActual > raw
    end
    return rewards
end

-- ======================== 按队伍当前关的离线计算 ========================

--- 各队独立刷当前关；合计只累加奖励/击杀，不叠加离线时长。
--- 主线收入用有效秒数，装备/卷轴沿用原封顶 raw 秒数；资源全走在线共享 DC API。
--- 调用方负责解锁/出战资格校验，此处再次拒绝非法、重复或空队参数。
---@param seconds number
---@param teams OfflineTeamSpec[]
---@param stageConfig table|nil
---@return OfflineTeamRewards|nil
function OfflineCalc.calcTeamOfflineRewards(seconds, teams, stageConfig)
    if seconds ~= seconds or seconds == math.huge then return nil end
    local actual = math.max(0, seconds)
    if actual < OfflineCalc.MIN_SECONDS or type(teams) ~= "table" then return nil end
    local raw = OfflineCalc.capSeconds(actual)
    local effective = OfflineCalc.effectiveOfflineSeconds(raw)
    local kills = math.floor(raw * OfflineCalc.IDLE_KILL_RATE)
    local cfg = stageConfig or SC
    ---@type OfflineTeamRewards
    local total = {
        gold = 0, diamond = 0, adventureExp = 0, adventurerExp = 0, kills = 0,
        equipSeeds = {}, scrollDrops = {}, teamRewards = {},
        seconds = raw, rawSeconds = actual, effectiveSeconds = effective,
        fullRateSeconds = OfflineCalc.FULL_RATE_SECONDS,
        tailRatio = OfflineCalc.TAIL_RATIO, maxSeconds = OfflineCalc.FULL_RATE_SECONDS,
        hardCapSeconds = OfflineCalc.HARD_CAP_SECONDS, cappedByHardCap = actual > raw,
    }
    local seen = {}
    for _, team in ipairs(teams) do
        if type(team) ~= "table" then goto continue_team end
        local teamIdx = math.tointeger(tonumber(team.teamIdx) or 0)
        local stageId = math.tointeger(tonumber(team.stageId) or 0)
        local heroCount = math.tointeger(tonumber(team.heroCount) or 0)
        if teamIdx and teamIdx >= 1 and teamIdx <= (ET.TEAM_COUNT or 3)
            and not seen[teamIdx] and stageId and stageId > 0 and heroCount
            and heroCount > 0 and heroCount <= (ET.TEAM_MAX_SLOTS or 4) then
            local entry = cfg.getStage(stageId)
            if entry then
                ---@type OfflineTeamReward
                local reward = {
                    teamIdx = teamIdx, stageId = stageId, heroCount = heroCount,
                    gold = 0, diamond = 0, adventureExp = 0, adventurerExp = 0,
                    equipSeeds = {}, scrollDrops = {}, kills = kills,
                }
                if cfg.isResourceStage and cfg.isResourceStage(stageId) then
                    -- DC 内封装每分钟旧效率及货币 REWARD_MULT，装备不乘倍率。
                    -- 不把资源关送入主线收入表/怪物掉落，否则会混入经验、卷轴和扫荡券。
                    local resource = DC.getStageRewards(stageId, effective * OfflineCalc.IDLE_KILL_RATE)
                    reward.gold = resource.gold or 0
                    reward.diamond = resource.diamond or 0
                    reward.equipSeeds = resource.equipSeeds or {}
                else
                    -- 重登通常已由 Schema 将终焉退至同难度末关；旧直接调用也保持此边界。
                    local incomeId = stageId
                    if cfg.isTerminalTemple and cfg.isTerminalTemple(stageId) then
                        incomeId = cfg.getTerminalPrevStageId(stageId) or stageId
                        entry = cfg.getStage(incomeId) or entry
                    end
                    local dropped = OfflineCalc.calcRewardsFromKills(kills, entry, heroCount, cfg)
                    reward.equipSeeds = dropped.equipSeeds
                    reward.scrollDrops = dropped.scrollDrops
                    local goldPerMin, expPerMin = IdleIncomeConfig.get(incomeId)
                    reward.gold = math.floor(goldPerMin * effective / 60 + 0.5)
                    reward.adventureExp = math.floor(expPerMin * effective / 60 + 0.5)
                    reward.adventurerExp = math.floor(reward.adventureExp
                        * ET.getHeroCountExpMult(heroCount) + 0.5)
                end
                seen[teamIdx] = true
                total.teamRewards[#total.teamRewards + 1] = reward
                total.gold = total.gold + reward.gold
                total.diamond = total.diamond + reward.diamond
                total.adventureExp = total.adventureExp + reward.adventureExp
                total.adventurerExp = total.adventurerExp + reward.adventurerExp
                total.kills = total.kills + reward.kills
                mergeEquipSeedsInto(total.equipSeeds, reward.equipSeeds)
                mergeScrollDropsInto(total.scrollDrops, reward.scrollDrops)
            end
        end
        ::continue_team::
    end
    if #total.teamRewards == 0 then return nil end
    return total
end

--- 【入口 B】在线定时结算（无门槛，由调用方保证 interval >= 60s）
---@param seconds number
---@param incomeStageId number
---@param heroCount number
---@param dropStageId number|nil
---@param stageConfig table|nil
---@return table|nil rewards
function OfflineCalc.calcOnlineIdleRewards(seconds, incomeStageId, heroCount, dropStageId, stageConfig)
    return _calcIdleCore(seconds, incomeStageId, heroCount, dropStageId, stageConfig)
end

--- 从 battle 模块解析双锚点并计算挂机收益（在线/离线统一推荐入口）
---@param seconds number
---@param battleData table|nil
---@param heroCount number
---@param isOffline boolean|nil  true 时应用 MIN/MAX 门槛
---@param stageConfig table|nil
---@return table|nil rewards
function OfflineCalc.calcIdleRewardsForBattle(seconds, battleData, heroCount, isOffline, stageConfig)
    local incomeStageId, dropStageId = OfflineCalc.resolveIdleStageAnchors(battleData, stageConfig)
    if isOffline then
        return OfflineCalc.calcOfflineIdleRewards(seconds, incomeStageId, heroCount, dropStageId, stageConfig)
    end
    return OfflineCalc.calcOnlineIdleRewards(seconds, incomeStageId, heroCount, dropStageId, stageConfig)
end

return OfflineCalc
