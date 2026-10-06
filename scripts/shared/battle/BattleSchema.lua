-- BattleSchema.lua — battle 模块 Schema
-- 战斗进度（当前关卡、最远关卡、已通关）

local StageConfig = require("config.StageConfig")

local BattleSchema = {}

---@param value any
---@return integer|nil
local function validStageId(value)
    if type(value) ~= "number" and type(value) ~= "string" then return nil end
    local id = math.tointeger(tonumber(value) or 0)
    if id and id > 0 and StageConfig.getStage(id) then return id end
    return nil
end

---@param stageId number
---@return number
local function progressRank(stageId)
    local previous = StageConfig.getTerminalPrevStageId(stageId)
    return previous and previous + 0.5 or stageId
end

--- 单一位置迁移入口；实时镜像不退终焉，只有真实读档才回到同难度末关。
--- 主线表存在时 currentStageId 是一队权威；仅侧线旧表时迁移旧一队位置。
---@param data table
---@param restoring boolean
---@return boolean
function BattleSchema.normalizeTeamStageIds(data, restoring)
    if type(data) ~= "table" then return false end
    local mainTeams = type(data.teamStageIds) == "table" and data.teamStageIds or nil
    local legacyTeams = type(data.teamCurrentStageIds) == "table" and data.teamCurrentStageIds or nil
    local savedTeams = mainTeams or legacyTeams or {}
    local current = validStageId(data.currentStageId)
    local savedFirst = validStageId(savedTeams["1"] or savedTeams[1])
    if not mainTeams and legacyTeams then
        current = savedFirst or current
    else
        current = current or savedFirst
    end
    local firstStage = StageConfig.NORMAL_FIRST_STAGE
    current = current or firstStage
    local maxStage = validStageId(data.maxStageId)
    if not maxStage or StageConfig.isResourceStage(maxStage) then
        maxStage = StageConfig.isResourceStage(current) and firstStage or current
    end
    data.maxStageId = maxStage
    local maxRank = progressRank(maxStage)
    local unlocked = require("config.ExpTable").getUnlockedTeamCount(data)
    local fixedTeams = {}
    for teamIdx = 1, 3 do
        local id = teamIdx == 1 and current
            or validStageId(savedTeams[tostring(teamIdx)] or savedTeams[teamIdx]) or firstStage
        if teamIdx > unlocked then
            id = firstStage
        elseif StageConfig.isResourceStage(id) then
            local DC = require("config.DungeonConfig")
            local dungeonId = DC.decodeStageId(id)
            if maxRank < DC.DEFINITIONS[dungeonId].unlockStage then id = firstStage end
        elseif progressRank(id) > maxRank then
            id = firstStage
        end
        if restoring == true and StageConfig.isTerminalTemple(id) then
            id = StageConfig.getTerminalPrevStageId(id) or firstStage
        end
        fixedTeams[tostring(teamIdx)] = id
    end
    data.teamStageIds = fixedTeams
    data.currentStageId = fixedTeams["1"]
    data.teamCurrentStageIds = nil
    return true
end

BattleSchema.Fields = {
    battle = {
        pdmKey     = "ModBattle",
        type       = "json",
        scope      = "server",
        persist    = { via = "local", cloudKey = "mod_battle" },
        getDefault = function()
            return {
                currentStageId = 0101,
                maxStageId     = 0101,
                autoBattle     = true,
                clearedStages  = {},
                teamStageIds   = { ["1"] = 0101, ["2"] = 0101, ["3"] = 0101 },
                -- 挂机结算字段
                battleMode        = "idle",   -- "idle" | "firstClear" | "offline"
                idleAccumSec      = 0,        -- 在线挂机累积秒数（满60s结算一次）
                lastIdleClaimTime = 0,        -- 上次在线结算时间戳（崩溃恢复用）
                idleHeroCount     = 0,        -- 断线时出战英雄数快照（离线结算用）
                -- 服务端效率追踪
                effWindow  = { gold = 0, exp = 0, kills = 0, startTime = 0 },
                effHistory = {},  -- FIFO 10: { goldPerSec, expPerSec, killsPerSec, stageId, ts }
                effSquadLevels = {},  -- 上次效率记录时的部署英雄等级快照 {[heroId]=level}
            }
        end,
        onLoad = function(data)
            if type(data) ~= "table" then return end
            local cleared = {}
            if type(data.clearedStages) == "table" then
                for key, value in pairs(data.clearedStages) do
                    local id = math.tointeger(tonumber(key) or 0)
                    if id and id > 0 and value == true then cleared[tostring(id)] = true end
                end
            end
            data.clearedStages = cleared
            if data.currentStage and not data.currentStageId then
                data.currentStageId = 0101
                data.currentStage = nil
            end
            if data.maxStage and not data.maxStageId then
                data.maxStageId = data.currentStageId or 0101
                data.maxStage = nil
            end
            -- onLoad 同时服务实时推送，不在此处执行真正重登的终焉回退。
            BattleSchema.normalizeTeamStageIds(data, false)
            -- 🔴 兜底修复：自动补标终焉神殿为已通关（避免重复挑战）
            -- 仅条件1：maxStageId 已进入下一难度（玩家明确通过了终焉）
            -- 注意：不在此处处理"末关已通关但未推进"的情况（条件2），
            -- 因为标记 clearedStages 会导致进入终焉时 isFirstClear=false（变成挂机模式）
            -- 该情况改为在客户端 nextStage() 跳过逻辑中处理（不修改持久化数据）
            local terminalThresholds = {
                [StageConfig.TERMINAL_NORMAL]    = StageConfig.HARD_FIRST_STAGE,
                [StageConfig.TERMINAL_HARD]      = StageConfig.NIGHTMARE_FIRST_STAGE,
                [StageConfig.TERMINAL_NIGHTMARE] = StageConfig.HELL_FIRST_STAGE,
                [StageConfig.TERMINAL_HELL]      = StageConfig.PURGATORY_FIRST_STAGE,
                [StageConfig.TERMINAL_PURGATORY] = StageConfig.TORMENT_FIRST_STAGE,
                [StageConfig.TERMINAL_TORMENT]   = StageConfig.TORMENT2_FIRST_STAGE,
                [StageConfig.TERMINAL_TORMENT2]  = StageConfig.TORMENT3_FIRST_STAGE,
                [StageConfig.TERMINAL_TORMENT3]  = StageConfig.TORMENT4_FIRST_STAGE,
                [StageConfig.TERMINAL_TORMENT4]     = StageConfig.TORMENT5_FIRST_STAGE,
                [StageConfig.TERMINAL_TORMENT5]     = StageConfig.ANNIHILATION_FIRST_STAGE,
                [StageConfig.TERMINAL_ANNIHILATION]  = StageConfig.ANNIHILATION2_FIRST_STAGE,
                [StageConfig.TERMINAL_ANNIHILATION2] = StageConfig.ANNIHILATION3_FIRST_STAGE,
                [StageConfig.TERMINAL_ANNIHILATION3] = StageConfig.ANNIHILATION4_FIRST_STAGE,
                [StageConfig.TERMINAL_ANNIHILATION4] = StageConfig.ANNIHILATION5_FIRST_STAGE,
            }
            local maxProgress = progressRank(data.maxStageId)
            for terminalId, nextDiffFirst in pairs(terminalThresholds) do
                if maxProgress >= nextDiffFirst and data.clearedStages[tostring(terminalId)] ~= true then
                    data.clearedStages[tostring(terminalId)] = true
                end
            end
            -- 挂机结算字段迁移（旧存档无这些字段）
            if not data.battleMode then data.battleMode = "idle" end
            if not data.idleAccumSec then data.idleAccumSec = 0 end
            if not data.lastIdleClaimTime then data.lastIdleClaimTime = 0 end
            if not data.idleHeroCount then data.idleHeroCount = 0 end
            -- 效率追踪字段兼容
            if not data.effWindow then
                data.effWindow = { gold = 0, exp = 0, kills = 0, startTime = 0 }
            end
            if not data.effHistory then data.effHistory = {} end
            if not data.effSquadLevels then data.effSquadLevels = {} end
        end,
        desc = "战斗进度",
    },
}

return BattleSchema
