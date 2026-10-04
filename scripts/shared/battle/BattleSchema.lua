-- BattleSchema.lua — battle 模块 Schema
-- 战斗进度（当前关卡、最远关卡、已通关）

local StageConfig = require("config.StageConfig")
local ExpTable = require("config.ExpTable")

local BattleSchema = {}

-- 关号不是进度序号：999 在普通2305之后，1999在困难4605之后。
---@type table<number, number>
local stageOrder = {}
---@type number|nil
local stageId = StageConfig.NORMAL_FIRST_STAGE
for order = 1, 2000 do
    if not stageId or stageOrder[stageId] then break end
    stageOrder[stageId] = order
    local nextId = StageConfig.getNextStageId(stageId)
    if not nextId and StageConfig.isTerminalTemple(stageId) then
        nextId = StageConfig.getReincarnationTarget(StageConfig.getDifficulty(stageId))
    end
    stageId = nextId
end

--- 三队当前关契约；旧 currentStageId 仅作队一缺失时来源，归一化后镜像队一。
--- 不修改账户共享 max/cleared；空队允许保留选择，锁队不保留越权选择。
--- restoreTerminal 只用于真正读档，实时同步/快照不得打断终焉挑战。
---@param data table
---@param restoreTerminal boolean|nil
---@return number[]
function BattleSchema.normalizeTeamStageIds(data, restoreTerminal)
    local ids = type(data.teamCurrentStageIds) == "table" and data.teamCurrentStageIds or {}
    local cleared = type(data.clearedStages) == "table" and data.clearedStages or {}
    local maxId = tonumber(data.maxStageId) or StageConfig.NORMAL_FIRST_STAGE
    local maxOrder = stageOrder[maxId] or 1
    local unlocked = ExpTable.getUnlockedTeamCount(data)
    local function legalStage(value)
        if type(value) ~= "number" and type(value) ~= "string" then return nil end
        local id = tonumber(value)
        if not id or not StageConfig.getStage(id) then return nil end
        if restoreTerminal and StageConfig.isTerminalTemple(id) then
            id = StageConfig.getTerminalPrevStageId(id)
        end
        if not id then return nil end
        local reachable = (stageOrder[id] or math.huge) <= maxOrder
            or cleared[id] == true or cleared[tostring(id)] == true
        if not reachable and StageConfig.isTerminalTemple(id) then
            local previous = StageConfig.getTerminalPrevStageId(id)
            reachable = previous ~= nil and (cleared[previous] == true or cleared[tostring(previous)] == true)
        end
        return reachable and id or nil
    end
    local out = {}
    for teamIdx = 1, ExpTable.TEAM_COUNT do
        local id = legalStage(ids[teamIdx]) or legalStage(ids[tostring(teamIdx)])
        if teamIdx == 1 then id = id or legalStage(data.currentStageId) end
        out[teamIdx] = teamIdx <= unlocked and (id or StageConfig.NORMAL_FIRST_STAGE)
            or StageConfig.NORMAL_FIRST_STAGE
    end
    data.teamCurrentStageIds = out
    data.currentStageId = out[1]
    return out
end

BattleSchema.Fields = {
    battle = {
        pdmKey     = "ModBattle",
        type       = "json",
        scope      = "server",
        persist    = { via = "local", cloudKey = "mod_battle" },
        getDefault = function()
            return {
                currentStageId = 0101, -- 队一兼容镜像
                teamCurrentStageIds = { 0101, 0101, 0101 },
                maxStageId     = 0101,
                autoBattle     = true,
                clearedStages  = {},
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
            if type(data.clearedStages) ~= "table" then data.clearedStages = {} end
            if data.currentStage and not data.currentStageId then
                data.currentStageId = 0101
                data.currentStage = nil
            end
            if data.maxStage and not data.maxStageId then
                data.maxStageId = data.currentStageId or 0101
                data.maxStage = nil
            end
            if not data.currentStageId then data.currentStageId = 0101 end
            if not data.maxStageId then data.maxStageId = data.currentStageId end
            -- 三队按同一合法性规则恢复；所有终焉只在读档回退到对应难度末关。
            BattleSchema.normalizeTeamStageIds(data, true)
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
            local maxSId = tonumber(data.maxStageId) or 0
            for terminalId, nextDiffFirst in pairs(terminalThresholds) do
                if maxSId >= nextDiffFirst and not data.clearedStages[tostring(terminalId)] then
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
