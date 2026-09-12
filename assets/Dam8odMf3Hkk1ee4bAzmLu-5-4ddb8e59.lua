-- BattleSchema.lua — battle 模块 Schema
-- 战斗进度（当前关卡、最远关卡、已通关）

local StageConfig = require("config.StageConfig")

local BattleSchema = {}

BattleSchema.Fields = {
    battle = {
        pdmKey     = "ModBattle",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_battle" },
        getDefault = function()
            return {
                currentStageId = 0101,
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
            if not data.clearedStages then data.clearedStages = {} end
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
            -- 终焉神殿（挑战关）不保存进度：玩家重登后回退到前一关
            local terminalFallback = {
                [StageConfig.TERMINAL_NORMAL]    = StageConfig.NORMAL_LAST_STAGE,
                [StageConfig.TERMINAL_HARD]      = StageConfig.HARD_LAST_STAGE,
                [StageConfig.TERMINAL_NIGHTMARE] = StageConfig.NIGHTMARE_LAST_STAGE,
                [StageConfig.TERMINAL_HELL]      = StageConfig.HELL_LAST_STAGE,
                [StageConfig.TERMINAL_PURGATORY] = StageConfig.PURGATORY_LAST_STAGE,
                [StageConfig.TERMINAL_TORMENT]   = StageConfig.TORMENT_LAST_STAGE,
                [StageConfig.TERMINAL_TORMENT2]  = StageConfig.TORMENT2_LAST_STAGE,
                [StageConfig.TERMINAL_TORMENT3]  = StageConfig.TORMENT3_LAST_STAGE,
                [StageConfig.TERMINAL_TORMENT4]     = StageConfig.TORMENT4_LAST_STAGE,
                [StageConfig.TERMINAL_TORMENT5]     = StageConfig.TORMENT5_LAST_STAGE,
                [StageConfig.TERMINAL_ANNIHILATION]  = StageConfig.ANNIHILATION_LAST_STAGE,
                [StageConfig.TERMINAL_ANNIHILATION2] = StageConfig.ANNIHILATION2_LAST_STAGE,
                [StageConfig.TERMINAL_ANNIHILATION3] = StageConfig.ANNIHILATION3_LAST_STAGE,
                [StageConfig.TERMINAL_ANNIHILATION4] = StageConfig.ANNIHILATION4_LAST_STAGE,
            }
            local fallback = terminalFallback[data.currentStageId]
            if fallback then
                data.currentStageId = fallback
            end
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
