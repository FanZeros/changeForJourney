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

        -- cleared 是永久首通事实，不是当前战斗模式。回灌可能只含部分账本，
        -- 合并本地与输入账本并归一数字/字符串键；只接受严格true。
        -- 清档需先走 resetToDefault，不能借一次普通恢复清除历史首通。
        local clearedStages = {}
        local function mergeCleared(source)
            if type(source) ~= "table" then return end
            for k, v in pairs(source) do
                local numKey = math.tointeger(tonumber(k) or 0)
                if numKey and numKey > 0 and v == true then
                    clearedStages[numKey] = true
                end
            end
        end
        mergeCleared(get("clearedStages"))
        mergeCleared(data.clearedStages)
        set("clearedStages", clearedStages)

        -- 旧档后备推断只补真实关链中最高节点之前的关卡，不补最高节点。
        -- 终焉ID非单调（999在2305之后），不能按 sid < maxStageId 数值比较。
        local maxSId = math.tointeger(tonumber(data.maxStageId) or 0)
        if maxSId and maxSId > 0 then
            -- 与存档对齐（Debug 跳回低进度时允许降低 maxStageId_）
            set("maxStageId_", maxSId)
            local stageConfig = getStageConfig()
            local sid = stageConfig.getFirstStageId
                and stageConfig.getFirstStageId(stageConfig.DIFFICULTY_NORMAL)
                or 0101
            local prefix, visited = {}, {}
            while sid and sid ~= maxSId and not visited[sid] do
                visited[sid] = true
                prefix[#prefix + 1] = sid
                local nextSid = stageConfig.getNextStageId(sid)
                if not nextSid and stageConfig.isTerminalTemple(sid) then
                    -- 终焉神殿无 next，跨难度继续查找真实前缀
                    local diff = stageConfig.getDifficulty(sid)
                    nextSid = stageConfig.getReincarnationTarget(diff)
                end
                sid = nextSid
            end
            -- 找不到目标时不把整条关链误认作已通，保留已确认的账本即可。
            if sid == maxSId then
                local restoredStages = get("clearedStages")
                for _, passedId in ipairs(prefix) do restoredStages[passedId] = true end
            end
            -- 最高节点和账本到位后立即刷新，不等下一关加载。
            recalcIdleIncome()
        end

        -- 恢复当前关卡（如果与本地不同则切换）
        -- 单机存档里的当前关卡。变量名沿用旧联机字段，不是真正的服务端。
        local savedStageId = data.currentStageId and tonumber(data.currentStageId)

        -- 已通关账本是永久事实；当前关等于最高关不代表首通尚未完成。
        -- 最高关没有后继，普通关也可主动重打，不能通过删标恢复推进状态。
        -- 保留有效当前关，由下方按已通账本恢复挂机／首通模式。

        -- currentStageId 是一队当前关，maxStageId 是所有队共享的解锁上限。
        -- 二三队可以在前方推关，一队也可以主动选择旧关；读档时保留有效的
        -- 当前关，不能把这种合法落后误当成坏档并强制跳到其他队的最高进度。
        local initialBattleDataLoaded = get("initialBattleDataLoaded")

        local currentStageId = get("currentStageId")
        local battleActive = get("battleActive")
        local searchingTimer = get("searchingTimer")
        local defeatTimer = get("defeatTimer")
        local reincarnationTimer = get("reincarnationTimer")
        if savedStageId and savedStageId ~= currentStageId then
            -- 首次加载数据时无条件恢复（否则 init 里 loadStage(0101) 已启动战斗，isBusy=true 会拦截）
            if not initialBattleDataLoaded then
                loadStage(savedStageId)
                set("regenAccum", 0)
                -- 首次加载进入寻怪模式，等本地装备/天赋数据同步完毕再开战
                set("battleActive", false)
                set("searchingTimer", 0)
                print("[BattleScene] 首次加载，恢复关卡(寻怪模式): " .. tostring(savedStageId))
            else
                -- 后续存档回灌：仅在战斗未激活时才接受切换，避免打断进行中的战斗或轮回倒计时
                local isBusy = battleActive or (searchingTimer ~= nil) or (defeatTimer ~= nil) or (reincarnationTimer ~= nil)
                if not isBusy then
                    loadStage(savedStageId, true)  -- skipBattleStart
                    set("regenAccum", 0)
                    for _, u in ipairs(getAllies()) do resetAllyUnit(u) end
                    startBattleTalents()
                    print("[BattleScene] 从本地存档恢复关卡: " .. tostring(savedStageId))
                else
                    local reason = battleActive and "battleActive" or (searchingTimer ~= nil) and "searching" or (defeatTimer ~= nil) and "defeat" or "reincarnation"
                    print("[BattleScene] 战斗进行中，忽略旧存档关卡: saved=" .. tostring(savedStageId) .. " local=" .. tostring(currentStageId) .. " reason=" .. reason)
                end
            end
        elseif not initialBattleDataLoaded then
            -- 首次加载且关卡未切换（savedStageId == currentStageId 或 savedStageId 为 nil）
            -- init 不再预加载关卡，这里统一触发 loadStage 进入寻怪模式
            local stageToLoad = savedStageId or currentStageId
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
        -- 否则 savedStageId（可能是旧值）会导致 isFirstClear 被错误设为 false
        local isFirstClear = not get("clearedStages")[get("currentStageId")]
        set("isFirstClear", isFirstClear)
        if not isFirstClear and StageBerserk.isActive() then
            StageBerserk.exit()
        end
    end

    return { setBattleData = setBattleData }
end

return M
