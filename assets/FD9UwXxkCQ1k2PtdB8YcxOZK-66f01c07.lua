-- ============================================================================
-- OfflineCalc - 挂机/离线收益计算模块（v2 统一杀怪效率）
-- 职责: 基于固定杀怪效率 + maxStageId 前 N 关加权混合，计算挂机收益
-- 运行端: server
-- 公式: kills = seconds × IDLE_KILL_RATE; rewards = 多关卡加权(kills, stages, heroCount)
-- ============================================================================

local MC = require("config.MonsterConfig")
local SC = require("config.StageConfig")
local ET = require("config.ExpTable")
local StageUtils = require("shared.StageUtils")
local EquipmentSystem = require("systems.EquipmentSystem")
local IdleIncomeConfig = require("config.IdleIncomeConfig")

local OfflineCalc = {}

-- ======================== 常量 ========================

OfflineCalc.IDLE_KILL_RATE    = 1/3     -- 固定杀怪效率：每 3 秒 1 只（在线/离线通用）
OfflineCalc.MAX_SECONDS       = 43200   -- 最大累计 12 小时（离线入口使用）
OfflineCalc.MIN_SECONDS       = 60      -- 最少 1 分钟才产生收益（离线入口使用）
OfflineCalc.SWEEP_STAGE_COUNT = 5       -- 覆盖关卡数（与扫荡一致）

--- 解析挂机收益锚点关卡（金币/经验查表 + 前 5 关掉落混合）
--- 规则：常规挂机用 maxStageId；首通进行中（当前关未 cleared）用上一关（已通关最高关）
--- 例：在 10-1 首通且 maxStageId=1001 时 → 905（9-5），collectPrevStages 得到 9-5…9-1
---@param battleData table|nil  battle 模块（currentStageId / maxStageId / clearedStages / battleMode）
---@param stageConfig table|nil 关卡配置模块，默认 config.StageConfig
---@return number stageId
function OfflineCalc.resolveIdleIncomeStageId(battleData, stageConfig)
    local cfg = stageConfig or SC
    if not battleData then return 101 end

    local current = tonumber(battleData.currentStageId)
    local maxId   = tonumber(battleData.maxStageId) or current or 101

    local function usePrevIfAny(stageId)
        if not stageId then return nil end
        local prev = cfg.getPrevStageId(stageId)
        return prev or stageId
    end

    -- 首通进行中：current == max 且该关尚未写入 clearedStages
    if current and current == maxId then
        local key = tostring(current)
        local cleared = battleData.clearedStages and battleData.clearedStages[key]
        if not cleared then
            local anchor = usePrevIfAny(current)
            if anchor then return anchor end
        end
    end

    -- 在线实时路径：battleMode 标记（断线存盘后会变成 offline，由上一条覆盖）
    if battleData.battleMode == "firstClear" and current then
        local anchor = usePrevIfAny(current)
        if anchor then return anchor end
    end

    -- 推进中但 max 尚未更新（兼容极端时序）
    if current and current > maxId then
        return maxId
    end

    return maxId
end

--- 解析挂机掉落混合锚点（collectPrevStages 用）
--- 首通进行中用 currentStageId（如 1001 → 9-5…9-1）；常规挂机用 income 锚点
---@param battleData table|nil
---@param stageConfig table|nil
---@return number stageId
function OfflineCalc.resolveIdleDropStageId(battleData, stageConfig)
    if not battleData then return 101 end

    local current = tonumber(battleData.currentStageId)
    local maxId   = tonumber(battleData.maxStageId) or current or 101

    if current and current == maxId then
        local cleared = battleData.clearedStages and battleData.clearedStages[tostring(current)]
        if not cleared then
            return current
        end
    end

    if battleData.battleMode == "firstClear" and current then
        return current
    end

    return OfflineCalc.resolveIdleIncomeStageId(battleData, stageConfig)
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
    local heroCountMult = ET.heroCountExpMult[heroCount] or 1.0
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
        local scrollTypes = { "weaponScroll", "offhandScroll", "armorScroll", "accessoryScroll" }
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

    local scrollTypes = { "weaponScroll", "offhandScroll", "armorScroll", "accessoryScroll" }
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
---@param seconds number    挂机秒数
---@param incomeStageId number  金币/经验查表锚点（IdleIncomeConfig）
---@param heroCount number  出战英雄数
---@param dropStageId number|nil  装备/卷轴混合掉落锚点（默认与 incomeStageId 相同）
---@return table|nil rewards
local function _calcIdleCore(seconds, incomeStageId, heroCount, dropStageId, stageConfig)
    local cfg = stageConfig or SC
    dropStageId = dropStageId or incomeStageId
    local totalKills = math.floor(seconds * OfflineCalc.IDLE_KILL_RATE)
    if totalKills <= 0 then return nil end

    -- 取 dropStageId 前 N 关（跨难度安全）
    local stages = StageUtils.collectPrevStages(dropStageId, OfflineCalc.SWEEP_STAGE_COUNT, cfg)
    if #stages == 0 then
        -- fallback: 如果前面无关卡（刚开始游戏），尝试用 dropStageId 本身
        local entry = cfg.getStage(dropStageId)
        if not entry then return nil end
        stages = { entry }
    end

    -- [DEBUG] 收益计算诊断日志
    local stageIds = {}
    local stageLevels = {}
    for _, s in ipairs(stages) do
        stageIds[#stageIds + 1] = tostring(s.id or "?")
        stageLevels[#stageLevels + 1] = tostring(s.monsterLevel or "?")
    end
    print(string.format("[INCOME_DEBUG] _calcIdleCore: incomeStage=%s dropStage=%s heroCount=%d stageCount=%d stages=[%s] monsterLevels=[%s]",
        tostring(incomeStageId), tostring(dropStageId), heroCount, #stages,
        table.concat(stageIds, ","), table.concat(stageLevels, ",")))

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
            -- [DEBUG] 每关贡献
            print(string.format("[INCOME_DEBUG]   stage[%d] id=%s monsterLv=%d kills=%d → gold=%d exp=%d heroExp=%d",
                i, tostring(stageEntry.id), stageEntry.monsterLevel or 0, stageKills,
                r.gold, r.adventureExp, r.adventurerExp))
        end
    end
    -- [DEBUG] 旧公式汇总（保留用于新旧方案对比）
    print(string.format("[INCOME_DEBUG]   TOTAL(OLD): gold=%d exp=%d heroExp=%d (from %d kills across %d stages)",
        totalGold, totalExp, totalHeroExp, totalKills, #stages))

    -- ==================== 新方案：逐关固定收益配置 ====================
    -- gold / adventureExp（玩家经验）直接由 IdleIncomeConfig 按关卡查表得到，
    -- 按 seconds/60 比例缩放；adventurerExp（英雄经验）沿用原有 heroCountMult 关系。
    -- equipSeeds / scrollDrops 仍由上方击杀计算驱动（不改变掉落逻辑）。
    local cfgGoldPerMin, cfgExpPerMin = IdleIncomeConfig.get(incomeStageId)
    local minutes = seconds / 60
    local newGold = math.floor(cfgGoldPerMin * minutes + 0.5)
    local newExp  = math.floor(cfgExpPerMin * minutes + 0.5)
    local heroCountMult = ET.heroCountExpMult[heroCount] or 1.0
    local newHeroExp = math.floor(newExp * heroCountMult + 0.5)

    -- [DEBUG] 新方案汇总 + 新旧差距对比
    print(string.format("[INCOME_DEBUG]   TOTAL(NEW): gold=%d exp=%d heroExp=%d (cfg %d/%d per-min, incomeStage=%s, %.2f min)",
        newGold, newExp, newHeroExp, cfgGoldPerMin, cfgExpPerMin, tostring(incomeStageId), minutes))
    print(string.format("[INCOME_COMPARE] incomeStage=%s  gold: %d→%d(%+d)  playerExp: %d→%d(%+d)  heroExp: %d→%d(%+d)",
        tostring(incomeStageId),
        totalGold, newGold, newGold - totalGold,
        totalExp, newExp, newExp - totalExp,
        totalHeroExp, newHeroExp, newHeroExp - totalHeroExp))

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

--- 【入口 A】离线面板结算（有 MIN_SECONDS 门槛 + MAX_SECONDS 上限）
---@param seconds number
---@param incomeStageId number  金币/经验锚点
---@param heroCount number
---@param dropStageId number|nil  掉落混合锚点（省略则与 incomeStageId 相同）
---@param stageConfig table|nil
---@return table|nil rewards
function OfflineCalc.calcOfflineIdleRewards(seconds, incomeStageId, heroCount, dropStageId, stageConfig)
    seconds = math.min(seconds, OfflineCalc.MAX_SECONDS)
    if seconds < OfflineCalc.MIN_SECONDS then return nil end
    local rewards = _calcIdleCore(seconds, incomeStageId, heroCount, dropStageId, stageConfig)
    if rewards then
        rewards.maxSeconds = OfflineCalc.MAX_SECONDS
    end
    return rewards
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
