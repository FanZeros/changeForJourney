-- 三队终焉Scene接线：只结账/等待，沿用NavLogic动画完成入口，最后统一三队保存。
local SC = require("config.StageConfig")
local Dispatcher = require("runtime.ClientDispatcher")
local BottomNav = require("ui.hud.BottomNav")
local M = {}

function M.bind(deps)
    local get, set = deps.get, deps.set
    local function completeTriTerminal(stageId)
        stageId = tonumber(stageId)
        if not stageId or not SC.isTerminalTemple(stageId) or get("currentStageId") ~= stageId then return false end
        if get("pendingReincarnation") then return false end
        local targetId = SC.getReincarnationTarget(SC.getDifficulty(stageId))
        if not targetId then return false end
        local battle = Dispatcher.get("battle")
        local savedCleared = type(battle) == "table" and battle.clearedStages or {}
        savedCleared = type(savedCleared) == "table" and savedCleared or {}
        local cleared = get("clearedStages")
        local wasFirstClear = not (cleared[stageId] == true or cleared[tostring(stageId)] == true
            or savedCleared[stageId] == true or savedCleared[tostring(stageId)] == true)
        cleared[stageId] = true
        local maxStage = math.max(get("maxStageId_"), tonumber(type(battle) == "table" and battle.maxStageId) or 0, targetId)
        set("maxStageId_", maxStage)
        set("battleActive", false)
        set("firstClearTimeLeft", nil)
        for _, key in ipairs({ "searchingTimer", "defeatTimer", "reincarnationTimer", "victoryMarch" }) do set(key, nil) end
        local token = get("reincarnationToken") + 1
        set("reincarnationToken", token)
        set("pendingReincarnation", { targetStageId = targetId, terminalStageId = stageId,
            fromDifficulty = SC.getDifficulty(stageId), toDifficulty = SC.getDifficulty(targetId),
            triTerminal = true, token = token, timer = 0, animationStarted = false })
        BottomNav.setAllLocked(true)
        if type(battle) == "table" then
            battle.clearedStages = savedCleared
            savedCleared[tostring(stageId)] = true
            battle.maxStageId = maxStage
            local previous = SC.getTerminalPrevStageId(stageId)
            battle.currentStageId, battle.battleMode = previous, "idle"
            battle.teamStageIds = { ["1"] = previous, ["2"] = previous, ["3"] = previous }
        end
        -- 首通闭包排62/69及结算奖励；此前绝不loadStage或通知目标入场。
        if wasFirstClear then deps.scene.onFirstClear(stageId, 1) end
        if type(battle) == "table" then
            Dispatcher.notifySubscribers("battle")
            require("boot.StandaloneSave").Flush()
        end
        print("[BattleScene] 终焉已结账，三队等待剧情/奖励及轮回动画 stage=" .. stageId)
        return true
    end

    local function updateTriReincarnation(dt)
        local pending = get("pendingReincarnation")
        if not pending or not pending.triTerminal then return false end
        require("ui.battle.tri.TerminalReincarnation").tick(pending, dt, deps.delay,
            get("onReincarnateCallback"), deps.scene.completeReincarnation)
        return true
    end

    local function cancelTriReincarnation()
        local pending = get("pendingReincarnation")
        if pending and pending.triTerminal then
            set("pendingReincarnation", nil)
            set("reincarnationTimer", nil)
        end
    end

    local function completeReincarnation(token)
        local pending = get("pendingReincarnation")
        if token ~= nil and (not pending or pending.token ~= token) then return false end
        if not pending then return false end
        if not pending.triTerminal then return deps.nav.completeReincarnation() end
        if not pending.animationStarted then return false end
        -- 保留NavLogic现有加载/复位；兼容Scene不能先发目标通知或存档。
        set("completingTriReincarnation", true)
        local ok, err = pcall(deps.nav.completeReincarnation)
        set("completingTriReincarnation", false)
        if not ok then error(err) end
        local Page = require("ui.battle.tri.BattleTriPage")
        if Page.isTerminalRaidActive() then
            Page.completeTerminalReincarnation(pending.targetStageId)
        else
            require("ui.battle.stage.StageEntryEvents").notify(pending.targetStageId, 1)
        end
        local battle = Dispatcher.get("battle")
        if type(battle) == "table" then
            local target = pending.targetStageId
            battle.currentStageId, battle.maxStageId = target, get("maxStageId_")
            battle.teamStageIds = { ["1"] = target, ["2"] = target, ["3"] = target }
            local cleared = battle.clearedStages or {}
            battle.battleMode = (cleared[target] == true or cleared[tostring(target)] == true) and "idle" or "firstClear"
        end
        BottomNav.setAllLocked(false)
        local changed = get("onStageChangedCallback")
        if changed then changed(pending.targetStageId) end
        if type(battle) == "table" then
            Dispatcher.notifySubscribers("battle")
            require("boot.StandaloneSave").Flush()
        end
        return true
    end

    return { completeTriTerminal = completeTriTerminal, updateTriReincarnation = updateTriReincarnation,
        cancelTriReincarnation = cancelTriReincarnation, completeReincarnation = completeReincarnation }
end

return M
