-- ============================================================================
-- BattleStageNavLogic - 前进/后退/终焉进入/轮回完成（玩法不变）
-- ============================================================================

local BottomNav = require("ui.BottomNav")
local TerminalConfirmDialog = require("ui.TerminalConfirmDialog")

local M = {}

function M.bind(deps)
    local getStageConfig = deps.getStageConfig
    local loadStage = deps.loadStage
    local resetAllyUnit = deps.resetAllyUnit
    local startBattleTalents = deps.startBattleTalents
    local recalcIdleIncome = deps.recalcIdleIncome
    local getAllies = deps.getAllies
    local get = deps.get
    local set = deps.set

    local function applyStageSwitch(stageId, zoomTarget, logPrefix)
        set("searchingTimer", nil)
        set("defeatTimer", nil)
        set("bgTransAnim", { timer = 0, zoomTarget = zoomTarget })
        loadStage(stageId, true)
        set("regenAccum", 0)
        for _, u in ipairs(getAllies()) do resetAllyUnit(u) end
        startBattleTalents()
        local cb = get("onStageChangedCallback")
        if cb then cb(stageId) end
        print("[BattleScene] " .. logPrefix .. " → " .. tostring(get("stageName")))
    end

    local function doEnterTerminalTemple(nextId)
        applyStageSwitch(nextId, get("BG_ZOOM_FWD_TARGET"), "确认进入终焉神殿")
        BottomNav.setAllLocked(true)
        require("systems.GameBGM").setScene("samsara", { fromStart = true })
    end

    local function nextStage()
        local stageConfig = getStageConfig()
        local currentStageId = get("currentStageId")
        local nextId = stageConfig.getNextStageId(currentStageId)
        if nextId then
            -- 终焉神殿：只有历史最高关卡已进入下一难度时才跳过
            if stageConfig.isTerminalTemple(nextId) then
                local skipToId, shouldSkip = stageConfig.shouldSkipTerminal(
                    currentStageId, get("maxStageId_"), get("clearedStages"))
                if skipToId and shouldSkip then
                    print("[BattleScene] 终焉神殿已跳过(maxStage=" .. get("maxStageId_")
                        .. " upper=" .. tostring(stageConfig.getProgressUpperBound(get("maxStageId_"), get("clearedStages"), nil))
                        .. " skipTo=" .. tostring(skipToId) .. ") → " .. tostring(skipToId))
                    nextId = skipToId
                else
                    TerminalConfirmDialog.open(nextId)
                    return
                end
            end
            applyStageSwitch(nextId, get("BG_ZOOM_FWD_TARGET"), "前进")
        else
            print("[BattleScene] 已是最后一关")
        end
    end

    local function prevStage()
        local stageConfig = getStageConfig()
        local currentStageId = get("currentStageId")
        local prevId = stageConfig.getPrevStageId(currentStageId)
        -- 跨难度回退：当前是某难度第一关时，回退到上一难度末关
        if not prevId then
            prevId = stageConfig.getLastStageOfPrevDifficulty(currentStageId)
        end
        if prevId then
            applyStageSwitch(prevId, get("BG_ZOOM_BACK_TARGET"), "后退")
        else
            print("[BattleScene] 已是第一关")
        end
    end

    local function gotoStage(stageId)
        stageId = tonumber(stageId)
        if not stageId or stageId < 1 then return false, "无效关卡" end
        if stageId > get("maxStageId_") then return false, "关卡尚未解锁" end
        set("bgTransAnim", { timer = 0, zoomTarget = get("BG_ZOOM_FWD_TARGET") })
        loadStage(stageId, true)
        local cb = get("onStageChangedCallback")
        if cb then cb(stageId) end
        return true
    end

    local function completeReincarnation()
        local pendingReincarnation = get("pendingReincarnation")
        if not pendingReincarnation then
            print("[BattleScene] completeReincarnation called but no pending data")
            return
        end
        local pr = pendingReincarnation
        set("pendingReincarnation", nil)

        if pr.terminalStageId then
            get("clearedStages")[pr.terminalStageId] = true
        end
        if pr.targetStageId and pr.targetStageId > get("maxStageId_") then
            set("maxStageId_", pr.targetStageId)
            recalcIdleIncome()
        end

        require("systems.GameBGM").setScene("battle")
        set("bgTransAnim", { timer = 0, zoomTarget = get("BG_ZOOM_FWD_TARGET") })
        loadStage(pr.targetStageId, true)
        set("regenAccum", 0)
        for _, u in ipairs(getAllies()) do resetAllyUnit(u) end
        startBattleTalents()
        local cb = get("onStageChangedCallback")
        if cb then cb(pr.targetStageId) end
        print("[BattleScene] 轮回完成 → " .. tostring(get("stageName"))
            .. " (难度: " .. tostring(pr.toDifficulty) .. ")")
    end

    return {
        doEnterTerminalTemple = doEnterTerminalTemple,
        nextStage = nextStage,
        prevStage = prevStage,
        gotoStage = gotoStage,
        completeReincarnation = completeReincarnation,
    }
end

return M
