-- ============================================================================
-- BattleDataRestore - BattleScene.setBattleData 抽出（玩法不变）
-- ============================================================================

local StageBerserk = require("ui.battle.stage.StageBerserk")

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

    local function setBattleData(data)
        if not data then return end

        -- 恢复已通关关卡集合
        if data.clearedStages then
            local clearedStages = {}
            for k, v in pairs(data.clearedStages) do
                -- 服务端以 tostring(stageId) 为 key 存储，本地以 number 为 key
                local numKey = tonumber(k)
                if numKey and v then
                    clearedStages[numKey] = true
                end
            end
            set("clearedStages", clearedStages)
        end

        -- 用 maxStageId 补全 clearedStages（后备推断：低于 maxStageId 的关卡必定已通关）
        local maxSId = data.maxStageId and tonumber(data.maxStageId)
        if maxSId then
            -- 与服务端存档对齐（Debug 跳回低进度时需降低 maxStageId_）
            set("maxStageId_", maxSId)
            -- 更新挂机收益显示（maxStageId 变化后立即刷新，不等下一关加载）
            recalcIdleIncome()
            local stageConfig = getStageConfig()
            local sid = stageConfig.getFirstStageId
                and stageConfig.getFirstStageId(stageConfig.DIFFICULTY_NORMAL)
                or 0101
            local clearedStages = get("clearedStages")
            while sid and sid < maxSId do
                if not clearedStages[sid] then
                    clearedStages[sid] = true
                end
                local nextSid = stageConfig.getNextStageId(sid)
                if not nextSid and stageConfig.isTerminalTemple(sid) then
                    -- 终焉神殿无 next，跨难度继续填充
                    local diff = stageConfig.getDifficulty(sid)
                    nextSid = stageConfig.getReincarnationTarget(diff)
                end
                sid = nextSid
            end
        end

        -- 恢复当前关卡（如果与本地不同则切换）
        local serverStageId = data.currentStageId and tonumber(data.currentStageId)

        -- 🔴 修复中间状态：通关消息已落盘但推进消息未到（两条消息间掉线/存档）
        -- 表现：currentStageId == maxStageId 且 clearedStages[maxStageId] == true
        -- 此时客户端误判为挂机模式（isFirstClear=false），实际应为首通模式
        -- 修复：从本地 clearedStages 中移除该标记，让 isFirstClear 正确计算为 true
        -- 安全性：服务端 clearedStages 不变，不会重复发放首通奖励
        -- ⚠️ 守卫：如果 maxStageId 的下一关是终焉神殿，说明玩家已打到难度末关并从神殿
        --   返回/重连，此时应保持挂机模式（显示前进按钮→进入终焉神殿确认框），不触发修复
        local stageConfig = getStageConfig()
        local nextOfMax = maxSId and stageConfig.getNextStageId(maxSId)
        local isAtTerminalEntrance = nextOfMax and stageConfig.isTerminalTemple(nextOfMax)
        local clearedStages = get("clearedStages")
        if maxSId and serverStageId and serverStageId == maxSId and clearedStages[maxSId]
           and not isAtTerminalEntrance then
            clearedStages[maxSId] = nil
            print("[BattleScene] 修复中间状态: 关卡" .. tostring(maxSId)
                .. "已标记通关但未推进(currentStageId==maxStageId)，恢复为首通模式")
        end

        -- 首次加载兜底：如果 currentStageId 落后于 maxStageId，
        -- 说明上次存档异常或版本更新导致进度不同步，以 maxStageId 为准恢复到最新进度
        local initialBattleDataLoaded = get("initialBattleDataLoaded")
        if not initialBattleDataLoaded and serverStageId and maxSId then
            if maxSId > serverStageId then
                print("[BattleScene] 检测到进度落后: currentStageId=" .. tostring(serverStageId)
                    .. " 但 maxStageId=" .. tostring(maxSId) .. "，使用 maxStageId 恢复")
                serverStageId = maxSId
            end
        end

        local currentStageId = get("currentStageId")
        local battleActive = get("battleActive")
        local searchingTimer = get("searchingTimer")
        local defeatTimer = get("defeatTimer")
        local reincarnationTimer = get("reincarnationTimer")
        if serverStageId and serverStageId ~= currentStageId then
            -- 首次加载数据时无条件恢复（否则 init 里 loadStage(0101) 已启动战斗，isBusy=true 会拦截）
            if not initialBattleDataLoaded then
                loadStage(serverStageId)
                set("regenAccum", 0)
                -- 首次加载进入寻怪模式，等服务端装备/天赋数据同步完毕再开战
                set("battleActive", false)
                set("searchingTimer", 0)
                print("[BattleScene] 首次加载，恢复关卡(寻怪模式): " .. tostring(serverStageId))
            else
                -- 后续推送：仅在战斗未激活时才接受切换，避免打断进行中的战斗或轮回倒计时
                local isBusy = battleActive or (searchingTimer ~= nil) or (defeatTimer ~= nil) or (reincarnationTimer ~= nil)
                if not isBusy then
                    loadStage(serverStageId, true)  -- skipBattleStart
                    set("regenAccum", 0)
                    for _, u in ipairs(getAllies()) do resetAllyUnit(u) end
                    startBattleTalents()
                    print("[BattleScene] 从服务端恢复关卡: " .. tostring(serverStageId))
                else
                    local reason = battleActive and "battleActive" or (searchingTimer ~= nil) and "searching" or (defeatTimer ~= nil) and "defeat" or "reincarnation"
                    print("[BattleScene] 战斗进行中，忽略服务端关卡切换: server=" .. tostring(serverStageId) .. " local=" .. tostring(currentStageId) .. " reason=" .. reason)
                end
            end
        elseif not initialBattleDataLoaded then
            -- 首次加载且关卡未切换（serverStageId == currentStageId 或 serverStageId 为 nil）
            -- init 不再预加载关卡，这里统一触发 loadStage 进入寻怪模式
            local stageToLoad = serverStageId or currentStageId
            loadStage(stageToLoad)
            set("battleActive", false)
            set("searchingTimer", 0)
            print("[BattleScene] 首次加载，加载关卡(寻怪模式): " .. tostring(stageToLoad))
        end
        -- 首次加载时立即计算收益预估（OfflineCalc 统一公式，无需等待效率积累）
        if not initialBattleDataLoaded then
            recalcIdleIncome()
        end

        set("initialBattleDataLoaded", true)

        -- 无论是否切换关卡，都刷新 isFirstClear（clearedStages 可能已更新）
        -- 注意：当战斗进行中(isBusy)时关卡切换被忽略，此时应以本地 currentStageId 为准
        -- 否则 serverStageId（可能是旧值）会导致 isFirstClear 被错误设为 false
        local isFirstClear = not get("clearedStages")[get("currentStageId")]
        set("isFirstClear", isFirstClear)
        if not isFirstClear and StageBerserk.isActive() then
            StageBerserk.exit()
        end
    end

    return { setBattleData = setBattleData }
end

return M
