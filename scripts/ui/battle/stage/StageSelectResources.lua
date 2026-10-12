-- 副本每种一个分类；全部关卡共用选关页的连续列表。
-- 塔ID仅用于界面定位，不进入主线或资源队伍关卡链。
local DC = require("config.DungeonConfig")
local SC = require("config.StageConfig")
local TC = require("config.TowerConfig")
local IdleConfig = require("config.DungeonIdleConfig")
local SRP = require("config.StageRecommendPower")
local StageExpHelper = require("config.StageExpHelper")
local ClientDispatcher = require("runtime.ClientDispatcher")

---@class StageSelectGroup
---@field key number|string
---@field name string
---@field ids number[]
---@field subLabel string|nil
---@field unlockStage number|nil
---@field resourceDungeonId string|nil
---@field isTower boolean|nil
---@field hueIndex number|nil
---@field background string|nil

---@class StageSelectRewardData
---@field iconPath string
---@field quality number
---@field amount number
---@field isEstimate boolean
---@field firstAmount number|nil
---@field repeatAmount number|nil
---@field playerExp number|nil
---@field repeatPlayerExp number|nil
---@field runStartFloor number|nil
---@field runEndFloor number|nil
---@field artifactDropRate number|nil
---@field artifactQualityWeights number[]|nil
---@field equipLevel number|nil
---@field equipMinQuality number|nil
---@field equipMaxQuality number|nil

local M = {}
local groups = {} ---@type StageSelectGroup[]
local TOWER_STAGE_BASE = 400000

function M.isTowerStage(stageId)
    local id = math.tointeger(tonumber(stageId) or 0)
    return id ~= nil and id > TOWER_STAGE_BASE and id <= TOWER_STAGE_BASE + TC.MAX_FLOOR
end

---@return StageSelectGroup[]
function M.getGroups()
    if #groups > 0 then return groups end
    for resourceIndex, id in ipairs(DC.RESOURCE_IDS) do
        local def = DC.DEFINITIONS[id]
        -- 配置层提供章跨度旧ID锚点；UI不压缩/重写实际队伍任务和旧账本。
        local ids = DC.getChapterStageIds(id)
        groups[#groups + 1] = {
            key = "R:" .. id, name = def.name, subLabel = "", unlockStage = def.unlockStage,
            resourceDungeonId = id, hueIndex = resourceIndex,
            background = def.cardImage, ids = ids,
        }
    end
    local ids = {}
    for floor = 1, TC.MAX_FLOOR, TC.CHECKPOINT_INTERVAL do
        ids[#ids + 1] = TOWER_STAGE_BASE + floor
    end
    groups[#groups + 1] = {
        key = "R:babel_tower", name = "通天塔", subLabel = "",
        unlockStage = DC.UNLOCK_CONDITIONS.babel_tower,
        isTower = true, hueIndex = 5,
        background = "image/战斗背景/通天塔.png", ids = ids,
    }
    return groups
end

function M.getGroupKey(stageId)
    if M.isTowerStage(stageId) then return "R:babel_tower" end
    local id = DC.decodeStageId(stageId)
    return id and "R:" .. id or nil
end

--- 显示定位映射只影响选中行；currentStageId仍保存真实旧ID。
---@param stageId number|nil
---@return number|nil
function M.getDisplayStageId(stageId)
    if M.isTowerStage(stageId) then
        return TOWER_STAGE_BASE + TC.getCheckpointFloor(stageId - TOWER_STAGE_BASE)
    end
    if stageId and SC.isResourceStage(stageId) then return DC.getChapterStageId(stageId) end
    return stageId
end

--- 共用主线推荐口径；资源按敌人数修正，塔使用同等级主线参考乘属性倍率。
--- 副本统一保留估算色；不绕过主线模型的等级上限，不作为入场门槛。
---@param stageId number
---@param entry table|nil
---@return number|nil, boolean|nil
function M.getRecommendedPower(stageId, entry)
    local combat = entry or M.getStageEntry(stageId)
    if not combat then return nil end
    if M.isTowerStage(stageId) then
        local level = combat.monsterLevel or 1
        local base = SRP.get(level * 100 + 1)
        if not base then return nil end
        return math.ceil(base * TC.MONSTER_STAT_MULT / 5) * 5, true
    end
    if SC.isResourceStage(stageId) then
        local sourceId = combat.sourceStageId
        local base = sourceId and SRP.get(sourceId)
        local source = sourceId and SC.getStage(sourceId)
        if not base or not source then return nil end
        local ratio = math.max(1, (combat.firstCount or 0) / math.max(1, source.firstCount or 1))
        return math.ceil(base * ratio / 5) * 5, true
    end
    return SRP.get(stageId)
end

--- 只读展示整行击杀收益，不调用随机/发奖接口；塔首通与重打分列。
---@param stageId number
---@param entry table|nil
---@param dungeonData table|nil 只读副本账本；省略则读取最新客户端快照。
---@return StageSelectRewardData|nil
function M.getRewardPreview(stageId, entry, dungeonData)
    if M.isTowerStage(stageId) then
        local dungeon = dungeonData or ClientDispatcher.get("dungeon") or {}
        local tower = dungeon.babel_tower or {}
        local cleared = tower.cleared or {}
        local legacyCleared = math.max(0, math.min(TC.MAX_FLOOR, math.floor(tonumber(tower.floor) or 1) - 1))
        local startFloor = TC.getCheckpointFloor(stageId - TOWER_STAGE_BASE)
        local endFloor = TC.getRunEndFloor(startFloor)
        local firstAmount, firstExp, repeatExp = 0, 0, 0
        for floor = startFloor, endFloor do
            local floorData = TC.getFloor(floor)
            if not floorData then return nil end
            -- 按逐层首通记录与旧floor-1扣除已领取金额；稀疏高层cleared不冒充全部低层已通。
            if floor > legacyCleared and not cleared[floor] and not cleared[tostring(floor)] then
                firstAmount = firstAmount + floorData.firstDiamond
            end
            local perMinute = StageExpHelper.getExpPerMin(floorData.monsterLevel)
            -- 首通/重打各列整组经验口径，逐层先取整再求和。
            firstExp = firstExp + math.floor(perMinute * TC.FIRST_EXP_MINUTES)
            repeatExp = repeatExp + math.floor(perMinute * TC.REPEAT_EXP_MINUTES)
        end
        local def = DC.DEFINITIONS.black_diamond
        local weights = TC.ARTIFACT_QUALITY_WEIGHTS
        return {
            iconPath = def.rewardIcon, quality = def.quality, amount = firstAmount,
            isEstimate = false, firstAmount = firstAmount, repeatAmount = 0,
            playerExp = firstExp, repeatPlayerExp = repeatExp,
            runStartFloor = startFloor, runEndFloor = endFloor,
            artifactDropRate = TC.ARTIFACT_DROP_RATE,
            artifactQualityWeights = { weights[1], weights[2], weights[3] },
        }
    end
    local id, floor = DC.decodeStageId(stageId)
    if not id then return nil end
    local combat = entry or SC.getStage(stageId)
    if not combat then return nil end
    local legacyFloor = combat.resourceFloor or floor
    local def = DC.DEFINITIONS[id]
    local rate = IdleConfig.getIdlePerMin(id, legacyFloor)
    local perMinute = id == "equipment_vault" and rate or rate * IdleConfig.REWARD_MULT
    local amount = perMinute * math.max(0, combat.firstCount or 0) / 20
    local result = {
        iconPath = def.rewardIcon, quality = def.quality, amount = amount, isEstimate = true,
        -- 在线每杀先取整，预览必须逐杀累加；不使用一次总击杀取整的离线口径。
        playerExp = DC.getStageExpAmount(stageId, 1) * math.max(0, combat.firstCount or 0),
    } ---@type StageSelectRewardData
    if id == "equipment_vault" then
        local floorData = DC.getFloor(id, legacyFloor)
        if not floorData then return nil end
        result.equipLevel = floorData.equipLevel
        result.equipMinQuality, result.equipMaxQuality = floorData.equipMinQuality, floorData.equipMaxQuality
    end
    return result
end

function M.getStageEntry(stageId)
    if not M.isTowerStage(stageId) then return SC.getStage(stageId) end
    local floor = stageId - TOWER_STAGE_BASE
    local data = TC.getFloor(floor)
    return {
        id = stageId, name = "通天塔 第" .. floor .. "层",
        stage = floor, monsterLevel = data.monsterLevel,
        monsters = {}, bossId = 0, tower = true,
    }
end

-- 当前队伍任务和主线解锁基准各自保存；不要用资源大ID推高主线。
function M.getProgress()
    local battle = ClientDispatcher.get("battle") or {}
    local sceneMax = require("ui.battle.scene.BattleScene").getMaxStageId() or 0
    local maxId = tonumber(battle.maxStageId) or 0
    local function rank(id)
        local previous = SC.getTerminalPrevStageId(id)
        return previous and previous + 0.5 or id
    end
    local progress = { maxStageId = rank(sceneMax) > rank(maxId) and sceneMax or maxId }
    return progress, ClientDispatcher.get("dungeon") or {}
end

function M.getCurrentTowerStageId(dungeonData)
    local dungeon = dungeonData or ClientDispatcher.get("dungeon") or {}
    local tower = dungeon.babel_tower or {}
    return TOWER_STAGE_BASE + TC.getMaxUnlockedCheckpoint(tower)
end

function M.isStageUnlocked(stageId, battleData, dungeonData)
    if not battleData then battleData, dungeonData = M.getProgress() end
    if M.isTowerStage(stageId) then
        if not M.isTowerUnlocked(battleData) or not TC.isCheckpointFloor(stageId - TOWER_STAGE_BASE) then
            return false
        end
        return stageId <= M.getCurrentTowerStageId(dungeonData)
    end
    return DC.isStageUnlocked(stageId, battleData, dungeonData)
end

function M.isTowerUnlocked(battleData)
    if not battleData then battleData = M.getProgress() end
    local id = tonumber(battleData.maxStageId) or 0
    local previous = SC.getTerminalPrevStageId(id)
    return (previous and previous + 0.5 or id) >= M.getTowerUnlockStage()
end

function M.getTowerUnlockStage()
    return DC.UNLOCK_CONDITIONS.babel_tower or 0
end

return M
