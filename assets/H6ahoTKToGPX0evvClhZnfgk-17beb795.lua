-- ============================================================================
-- BattleService - 战斗/关卡业务逻辑
-- 职责: 关卡推进、首通奖励、战斗结算、情景奖励
-- 层级: server/battle  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local ExpTable        = require("config.ExpTable")
local EquipmentSystem = require("systems.EquipmentSystem")
local DropSystem      = require("systems.DropSystem")
local StageConfig     = require("config.StageConfig")
local StageProvider   = require("shared.StageProvider")
local ChallengerService = require("server.challenger.ChallengerService")
local ChallengerServerConfig = require("shared.ChallengerServerConfig")
local LootBoxSystem   = require("systems.LootBoxSystem")
local HeroConfig      = require("config.HeroConfig")
local GuildConfig     = require("config.GuildConfig")
local BlacksmithConfig = require("config.BlacksmithConfig")
local CurrencyService  = require("server.currency.CurrencyService")
local MonsterConfig    = require("config.MonsterConfig")
local MapAffixConfig   = require("config.MapAffixConfig")
local HeroService      = require("server.hero.HeroService")
local RelicAffix       = require("systems.RelicAffix")
local RelicDefs        = require("data.RelicDefs")
local RelicService     = require("server.relic.RelicService")
local IdleSettleService = require("server.offline.IdleSettleService")

local BattleService = {}

-- ======================== 内部工具 ========================

local function getStageConfig(uid)
    return StageProvider.GetForServer(PDM.GetServerId(uid))
end

--- 将 maxStageId 写入公会排行榜（区服隔离）
--- 分数编码: score = stageId * 100 + avatarHeroId（前N位关卡进度, 后两位头像英雄）
--- 使用 BatchSet 原子写入 iscore + name，避免分步写入时 Set 覆盖 iscore 的问题
---@param uid number
---@param maxStageId number
local function writeGuildStageRank(uid, maxStageId)
    local serverId = PDM.GetServerId(uid)
    if not serverId then return end
    local key = GuildConfig.getCloudKey("STAGE_RANK", serverId)
    -- 取玩家设置的展示头像（与 TopBar/竞技场一致）
    local avatarHeroId = 1
    local player = PDM.GetModule(uid, "player")
    if player and player.avatarHeroId then
        avatarHeroId = player.avatarHeroId
    end
    local score = maxStageId * 100 + math.min(avatarHeroId, 99)
    -- 原子写入：iscore（排行分数）+ score（名字）同时写入，防止竞态
    local playerName = (player and player.name and player.name ~= "") and player.name or nil
    if playerName then
        serverCloud:BatchSet(uid)
            :SetInt(key, score)
            :Set(key, playerName)
            :Save("guild_rank_write")
    else
        -- 先写分数保证排行榜正确
        serverCloud:SetInt(uid, key, score)
        -- 异步查询平台昵称并补写 name
        GetUserNickname({
            userIds = { uid },
            onSuccess = function(nicknames)
                if nicknames and nicknames[1] and nicknames[1].nickname
                   and nicknames[1].nickname ~= "" then
                    local nick = nicknames[1].nickname
                    serverCloud:Set(uid, key, nick)
                    -- 顺便修复 player.name
                    if player then
                        player.name = nick
                        PDM.MarkDirty(uid, "player")
                    end
                end
            end,
        })
    end
end

-- ======================== 通关 & 推进关卡 ========================

--- 通关 & 推进关卡
---@param uid number
---@param clearedId number|nil
---@param nextId number|nil
---@return boolean ok, string? err, table? result
function BattleService.NextStage(uid, clearedId, nextId)
    local canPlay, playErr = ChallengerService.CanPlay(uid)
    if not canPlay then
        return false, playErr or "挑战者活动不可进入"
    end

    local StageConfig = getStageConfig(uid)
    local battle = PDM.GetModule(uid, "battle")
    if not battle then
        return false, "数据未加载"
    end
    if StageConfig.__stageProviderUnavailable then
        return false, "关卡配置不可用"
    end

    local serverConfig = ChallengerServerConfig.GetByServerId(PDM.GetServerId(uid))
    local currentStageId = tonumber(battle.currentStageId)
    if not currentStageId or not StageConfig.getStage(currentStageId) then
        print("[BattleService][WARN] 当前关卡配置异常 uid=" .. tostring(uid)
            .. " currentStageId=" .. tostring(battle.currentStageId))
        return false, "当前关卡数据异常"
    end

    -- 客户端的通关和切关是两条独立消息。禁止合并提交，确保服务端先完成
    -- 当前关卡首通结算，再按已持久化的 clearedStages 校验后续切换。
    if clearedId ~= nil and nextId ~= nil then
        return false, "通关与切关请求不能合并"
    end

    if clearedId ~= nil then
        local clearedIdNum = tonumber(clearedId)
        if not clearedIdNum or clearedIdNum % 1 ~= 0 then
            return false, "非法通关关卡 ID"
        end
        clearedId = clearedIdNum

        local stageEntry = StageConfig.getStage(clearedId)
        if not stageEntry then
            return false, "通关关卡不存在"
        end
        if StageConfig.isTerminalTemple(clearedId) then
            return false, "终焉神殿必须通过轮回流程结算"
        end
        if serverConfig and serverConfig.maxStageId
            and clearedId > tonumber(serverConfig.maxStageId)
        then
            return false, "通关关卡超出活动范围"
        end

        -- 服务端权威：只能结算当前正在挑战的关卡。不得用 maxStageId、轮回目标
        -- 或客户端自称的更远进度自动矫正 currentStageId。
        if clearedId ~= currentStageId then
            print("[BattleService][WARN] 通关关卡与服务端当前关卡不一致 uid=" .. tostring(uid)
                .. " clearedId=" .. tostring(clearedId)
                .. " currentStageId=" .. tostring(currentStageId))
            return false, "通关关卡与当前进度不一致"
        end
    end

    if nextId ~= nil then
        local nextIdNum = tonumber(nextId)
        if not nextIdNum or nextIdNum % 1 ~= 0 then
            return false, "非法关卡 ID"
        end
        nextId = nextIdNum

        local targetEntry = StageConfig.getStage(nextId)
        if not targetEntry then
            return false, "目标关卡不存在"
        end
        if serverConfig and serverConfig.maxStageId
            and not StageConfig.isTerminalTemple(nextId)
            and nextId > tonumber(serverConfig.maxStageId)
        then
            return false, "目标关卡超出活动范围"
        end
    end

    local firstClearRewards = nil

    -- 记录已通关的关卡 ID + 首通奖励
    if clearedId then
        if not battle.clearedStages then
            battle.clearedStages = {}
        end
        local key = tostring(clearedId)
        local wasCleared = battle.clearedStages[key]

        -- 仅首次通关时发放奖励
        if not wasCleared then
            local stageEntry = StageConfig.getStage(clearedId)
            if stageEntry then
                local currency  = PDM.GetModule(uid, "currency")
                local playerData = PDM.GetModule(uid, "player")
                local equipData  = PDM.GetModule(uid, "equipment")

                -- 首通金币
                local fcGold = stageEntry.fcGold or 0
                if fcGold > 0 and currency then
                    currency.gold = (currency.gold or 0) + fcGold
                    PDM.MarkDirty(uid, "currency")
                end

                -- 首通经验
                local fcExp = stageEntry.fcExp or 0
                if fcExp > 0 and playerData then
                    local oldLv = playerData.level or 1
                    playerData.exp = (playerData.exp or 0) + fcExp
                    ExpTable.autoLevelUpPlayer(playerData)
                    PDM.MarkDirty(uid, "player")
                    if playerData.level > oldLv then
                        HeroService.SyncHeroLevelsToPlayerLevel(uid, playerData.level)
                    end
                end

                -- 首通钻石
                local fcDiamond = stageEntry.fcDiamond or 0
                if fcDiamond > 0 and currency then
                    currency.gems = (currency.gems or 0) + fcDiamond
                    PDM.MarkDirty(uid, "currency")
                end

                -- 首通精粹
                local fcEssence = stageEntry.fcEssence or 0
                if fcEssence > 0 and currency then
                    currency.essence = (currency.essence or 0) + fcEssence
                    PDM.MarkDirty(uid, "currency")
                end

                -- 首通奥术粉尘
                local fcArcaneDust = stageEntry.fcArcaneDust or 0
                if fcArcaneDust > 0 and currency then
                    currency.arcaneDust = (currency.arcaneDust or 0) + fcArcaneDust
                    PDM.MarkDirty(uid, "currency")
                end

                -- 首通装备
                local fcEquips = DropSystem.generateFirstClearEquips(stageEntry)
                local droppedList = {}
                if equipData and #fcEquips > 0 then
                    for _, equip in ipairs(fcEquips) do
                        if EquipmentSystem.isInventoryFull(equipData) then
                            print("[BattleService] first-clear equip SKIP (bag full) uid=" .. tostring(uid))
                            break
                        end
                        local seq = EquipmentSystem.addToInventory(equipData, equip)
                        droppedList[#droppedList + 1] = {
                            seq = seq, quality = equip.quality,
                            name = equip.name, templateId = equip.templateId,
                            level = equip.level,
                        }
                        print("[BattleService] first-clear equip uid=" .. tostring(uid)
                            .. " stage=" .. tostring(clearedId) .. " seq=" .. tostring(seq))
                    end
                    if #droppedList > 0 then
                        PDM.MarkDirty(uid, "equipment")
                    end
                end

                -- 首通卷轴（每个独立随机，按类型聚合）
                local scrollReward = DropSystem.generateFirstClearScrolls(stageEntry)
                if scrollReward and scrollReward.scrolls and currency then
                    for field, amount in pairs(scrollReward.scrolls) do
                        currency[field] = (currency[field] or 0) + amount
                    end
                    PDM.MarkDirty(uid, "currency")
                    print("[BattleService] first-clear scrolls uid=" .. tostring(uid))
                end

                -- 噩梦及以后各章 X-5 首通：黄金钥匙 ×2
                local fcGoldenKey = StageConfig.getFirstClearGoldenKey(clearedId, stageEntry)
                if fcGoldenKey > 0 and currency then
                    currency.goldenKey = (currency.goldenKey or 0) + fcGoldenKey
                    PDM.MarkDirty(uid, "currency")
                    print("[BattleService] first-clear goldenKey uid=" .. tostring(uid)
                        .. " stage=" .. tostring(clearedId) .. " +" .. tostring(fcGoldenKey))
                end

                -- 挑战者区服：X-5 首通腐化石；每难度相对 4/8/12/16/20 章 X-5 首通神圣石
                local fcCorruptStone, fcSacredStone = 0, 0
                local currentServerConfig = ChallengerServerConfig.GetByServerId(PDM.GetServerId(uid))
                if currentServerConfig and currentServerConfig.firstClearStonesEnabled ~= false then
                    if StageConfig.getFirstClearCorruptStone then
                        fcCorruptStone = StageConfig.getFirstClearCorruptStone(clearedId, stageEntry) or 0
                    end
                    if StageConfig.getFirstClearSacredStone then
                        fcSacredStone = StageConfig.getFirstClearSacredStone(clearedId, stageEntry) or 0
                    end
                    if fcCorruptStone > 0 and currency then
                        currency.corruptStone = (currency.corruptStone or 0) + fcCorruptStone
                        PDM.MarkDirty(uid, "currency")
                        print("[BattleService] first-clear corruptStone uid=" .. tostring(uid)
                            .. " stage=" .. tostring(clearedId) .. " +" .. tostring(fcCorruptStone))
                    end
                    if fcSacredStone > 0 and currency then
                        currency.sacredStone = (currency.sacredStone or 0) + fcSacredStone
                        PDM.MarkDirty(uid, "currency")
                        print("[BattleService] first-clear sacredStone uid=" .. tostring(uid)
                            .. " stage=" .. tostring(clearedId) .. " +" .. tostring(fcSacredStone))
                    end
                end

                firstClearRewards = {
                    gold         = fcGold,
                    exp          = fcExp,
                    diamond      = fcDiamond,
                    essence      = fcEssence,
                    arcaneDust   = fcArcaneDust,
                    goldenKey    = fcGoldenKey > 0 and fcGoldenKey or nil,
                    corruptStone = fcCorruptStone > 0 and fcCorruptStone or nil,
                    sacredStone  = fcSacredStone > 0 and fcSacredStone or nil,
                    equips       = #droppedList > 0 and droppedList or nil,
                    scroll       = scrollReward,
                }
            end
        end
        battle.clearedStages[key] = true
        if not wasCleared then
            ChallengerService.RecordProgress(uid, clearedId)
        end
    end

    -- 更新当前关卡 ID
    if nextId then
        local nextIdNum = nextId
        local currentId = tonumber(battle.currentStageId)
        local clearedStages = battle.clearedStages or {}
        local allowedTargets = { [currentId] = true }

        if StageConfig.isTerminalTemple(currentId) then
            local terminalPrev = StageConfig.getTerminalPrevStageId(currentId)
            if terminalPrev then
                allowedTargets[terminalPrev] = true
            end
            local difficulty = StageConfig.getDifficulty(currentId)
            local reincarnationTarget = StageConfig.getReincarnationTarget(difficulty)
            if reincarnationTarget and StageConfig.getStage(reincarnationTarget) then
                allowedTargets[reincarnationTarget] = true
            end
        else
            local prevId = StageConfig.getPrevStageId(currentId)
                or StageConfig.getLastStageOfPrevDifficulty(currentId)
            if prevId then
                allowedTargets[prevId] = true
            end

            -- 只有服务端已记录当前关卡通关，才允许进入配置给出的下一节点。
            if clearedStages[tostring(currentId)] then
                local directNext = StageConfig.getNextStageId(currentId)
                if directNext then
                    allowedTargets[directNext] = true

                    -- 已完成过终焉神殿时，客户端可按正常跳过流程直达轮回目标。
                    if StageConfig.isTerminalTemple(directNext)
                        and clearedStages[tostring(directNext)]
                    then
                        local difficulty = StageConfig.getDifficulty(directNext)
                        local reincarnationTarget = StageConfig.getReincarnationTarget(difficulty)
                        if reincarnationTarget and StageConfig.getStage(reincarnationTarget) then
                            allowedTargets[reincarnationTarget] = true
                        end
                    end
                end
            end
        end

        if not allowedTargets[nextIdNum] then
            print("[BattleService][WARN] 非法关卡切换 uid=" .. tostring(uid)
                .. " currentStageId=" .. tostring(currentId)
                .. " nextId=" .. tostring(nextIdNum))
            return false, "目标关卡未解锁"
        end

        -- [DIAG] 检测切换关卡时 effWindow 是否有未结算数据（混合关卡稀释诊断）
        local prevStageId = battle.currentStageId
        if prevStageId and prevStageId ~= nextIdNum then
            local w = battle.effWindow
            if w and w.kills > 0 and w.startTime > 0 then
                local winElapsed = os.time() - w.startTime
                print(string.format(
                    "[BattleService][DIAG] STAGE_CHANGE with active effWindow uid=%s\n"
                    .. "  prevStage=%s → newStage=%s\n"
                    .. "  effWindow: gold=%.1f exp=%.1f kills=%d elapsed=%ds\n"
                    .. "  WARNING: window data from stage %s will be tagged as stage %s at next settle!",
                    tostring(uid), tostring(prevStageId), tostring(nextIdNum),
                    w.gold, w.exp, w.kills, winElapsed,
                    tostring(prevStageId), tostring(nextIdNum)))
            end
        end

        -- 检测轮回：当前在终焉神殿 AND nextId 是下一难度首关（不是回退到同难度）
        local isReincarnation = false
        if StageConfig.isTerminalTemple(battle.currentStageId) then
            local termDiff = StageConfig.getDifficulty(battle.currentStageId)
            local reincTarget = StageConfig.getReincarnationTarget(termDiff)
            -- 只有目标是下一难度首关时才算真正的轮回（排除战败回退）
            if reincTarget and nextIdNum == reincTarget then
                isReincarnation = true
            end
        end
        if isReincarnation then
            -- 标记终焉神殿为已通关
            if not battle.clearedStages then battle.clearedStages = {} end
            battle.clearedStages[tostring(battle.currentStageId)] = true
            -- 入场动画由客户端轮回回调（CG → IntroCutscene）播放，不在此处设置 hasReincarnated，
            -- 否则重启后会误判为“尚未播放”而重复弹出
            print("[BattleService] Reincarnation detected: " .. tostring(battle.currentStageId) .. " → " .. tostring(nextIdNum))
        end

        battle.currentStageId = nextIdNum
        local isFirstClearStage = (battle.currentStageId > (battle.maxStageId or 0))
        if isFirstClearStage then
            -- 首通前结算：以旧 maxStageId 和对应公式结算当前累计挂机时间
            IdleSettleService.PreSettleForFirstClear(uid)
            battle.maxStageId = battle.currentStageId
            writeGuildStageRank(uid, battle.maxStageId)
        end
        battle.battleMode = isFirstClearStage and "firstClear" or "idle"
    end

    PDM.MarkDirty(uid, "battle")
    return true, nil, { firstClearRewards = firstClearRewards }
end

-- ======================== 重置关卡 ========================

--- 重置关卡进度
---@param uid number
---@return boolean ok, string? err
function BattleService.ResetStage(uid)
    local battle = PDM.GetModule(uid, "battle")
    if not battle then
        return false, "数据未加载"
    end

    battle.currentStageId = 101
    battle.clearedStages = {}
    PDM.MarkDirty(uid, "battle")
    return true
end

-- ======================== 轮回（终焉神殿） ========================

--- 轮回：从终焉神殿进入下一难度的首关
---@param uid number
---@param newStageId number  轮回目标关卡 ID（由客户端通过 SC.getReincarnationTarget 计算）
---@return boolean ok, string? err
function BattleService.Reincarnate(uid, newStageId)
    local canPlay, playErr = ChallengerService.CanPlay(uid)
    if not canPlay then
        return false, playErr or "挑战者活动不可进入"
    end

    local StageConfig = getStageConfig(uid)
    local battle = PDM.GetModule(uid, "battle")
    if not battle then
        return false, "数据未加载"
    end
    if StageConfig.__stageProviderUnavailable then
        return false, "关卡配置不可用"
    end

    local currentId = tonumber(battle.currentStageId)
    if not currentId or not StageConfig.isTerminalTemple(currentId) then
        print("[BattleService][WARN] 非终焉关卡请求轮回 uid=" .. tostring(uid)
            .. " currentStageId=" .. tostring(battle.currentStageId))
        return false, "当前关卡不能轮回"
    end

    local newStageIdNum = tonumber(newStageId)
    if not newStageIdNum or newStageIdNum % 1 ~= 0 then
        return false, "非法轮回目标"
    end

    local difficulty = StageConfig.getDifficulty(currentId)
    local expectedTarget = StageConfig.getReincarnationTarget(difficulty)
    if not expectedTarget or newStageIdNum ~= expectedTarget then
        print("[BattleService][WARN] 轮回目标不匹配 uid=" .. tostring(uid)
            .. " currentStageId=" .. tostring(currentId)
            .. " requested=" .. tostring(newStageId)
            .. " expected=" .. tostring(expectedTarget))
        return false, "轮回目标不合法"
    end

    local targetEntry = StageConfig.getStage(newStageIdNum)
    if not targetEntry then
        return false, "目标关卡不存在 " .. tostring(newStageIdNum)
    end

    local serverConfig = ChallengerServerConfig.GetByServerId(PDM.GetServerId(uid))
    if serverConfig and serverConfig.maxStageId
        and newStageIdNum > tonumber(serverConfig.maxStageId)
    then
        return false, "轮回目标超出活动范围"
    end

    if not battle.clearedStages then
        battle.clearedStages = {}
    end
    battle.clearedStages[tostring(currentId)] = true

    battle.currentStageId = newStageIdNum
    ChallengerService.RecordProgress(uid, currentId)
    if newStageIdNum > (battle.maxStageId or 0) then
        battle.maxStageId = newStageIdNum
        writeGuildStageRank(uid, battle.maxStageId)
        battle.battleMode = "firstClear"
    end

    PDM.MarkDirty(uid, "battle")

    print("[BattleService] Reincarnate uid=" .. tostring(uid)
        .. " from=" .. tostring(currentId) .. " to=" .. tostring(newStageIdNum))
    return true
end

-- ======================== Debug 跳转关卡 ========================

--- Debug：跳转到指定关卡并重建进度（终焉前测试用）
---@param uid number
---@param stageId number
---@return boolean ok, string? err
function BattleService.DebugJumpToStage(uid, stageId)
    local StageConfig = getStageConfig(uid)
    local stageIdNum = tonumber(stageId)
    if not stageIdNum then
        return false, "非法关卡 ID"
    end

    local entry = StageConfig.getStage(stageIdNum)
    if not entry then
        return false, "关卡不存在"
    end
    if StageConfig.isTerminalTemple(stageIdNum) then
        return false, "不能跳转到终焉神殿"
    end

    local battle = PDM.GetModule(uid, "battle")
    if not battle then
        return false, "数据未加载"
    end

    battle.currentStageId = stageIdNum
    battle.maxStageId = stageIdNum
    battle.clearedStages = StageConfig.buildClearedStagesUpTo(stageIdNum)
    ChallengerService.RecordProgress(uid, stageIdNum)
    battle.battleMode = "idle"
    battle.idleAccumSec = 0
    PDM.MarkDirty(uid, "battle")

    local session = PDM.GetModule(uid, "session")
    if session and session.hasReincarnated then
        session.hasReincarnated = false
        PDM.MarkDirty(uid, "session")
    end

    print("[BattleService] DebugJumpToStage uid=" .. tostring(uid)
        .. " stageId=" .. tostring(stageIdNum))
    return true
end

-- ======================== 在线挂机模式恢复 ========================

--- 断线时 OfflineService 会将 battleMode 设为 "offline" 并持久化。
--- 玩家重新进入游戏/重连后必须恢复为 idle/firstClear，否则 IdleSettleService 不会结算在线挂机收益。
---@param uid number
---@return boolean restored  是否从 offline 恢复
function BattleService.RestoreBattleModeFromOffline(uid)
    local battle = PDM.GetModule(uid, "battle")
    if not battle or battle.battleMode ~= "offline" then
        return false
    end

    local currentStageId = battle.currentStageId or 101
    local maxStageId = battle.maxStageId or 0
    local cleared = battle.clearedStages and battle.clearedStages[tostring(currentStageId)]
    local attemptingFirstClear = (currentStageId > maxStageId)
        or (currentStageId == maxStageId and maxStageId > 0 and not cleared)
    battle.battleMode = attemptingFirstClear and "firstClear" or "idle"
    PDM.MarkDirty(uid, "battle")
    print("[BattleService] battleMode restored offline→" .. battle.battleMode
        .. " uid=" .. tostring(uid)
        .. " stage=" .. tostring(currentStageId)
        .. " max=" .. tostring(maxStageId)
        .. " cleared=" .. tostring(cleared ~= nil))
    return true
end

-- ======================== 反加速：Claim 频率检测（双窗口） ========================
-- 原理：客户端每 3.0 客户端秒 flush 一次击杀奖励（REWARD_FLUSH_INTERVAL）。
-- 这个 3 秒间隔由客户端 dt 驱动，与墓碑复活时间 (2.0s) + 攻击间隔 (1.0s) 对齐。
-- 如果客户端被加速 N 倍，flush 到达服务端的真实间隔变为 3.0/N 秒。
-- 因此：通过测量 claim 到达频率即可推断客户端加速倍率，与击杀数量无关。
--
-- 为什么不用击杀数限流：
-- 玩家常用肉盾+奶妈低输出组合加速磨怪，击杀率本身很低，但战斗时间被压缩。
-- 击杀数限流对此场景完全无效。
--
-- 双窗口策略：
-- 短窗口 (30s, 1.8x)：快速响应高倍速加速（2x+），低延迟拦截
-- 长窗口 (120s, 1.4x)：捕获持续低倍速加速（1.5x），正常玩家波动不会持续这么久
--
-- 防 TCP 积压误报：
-- 使用 distinct timestamp 计数（同一 os.time() 秒内多个 claim 只算 1 次），
-- 避免弱网恢复后的 burst 被误判为加速。
-- ============================================================================

--- 配置参数
local CLIENT_FLUSH_INTERVAL = 3.0  -- 客户端 flush 间隔（客户端秒）

-- 短窗口：快速响应高倍速加速
local SHORT_WINDOW_DURATION  = 30   -- 真实秒
local SHORT_WINDOW_TOLERANCE = 1.8  -- 允许 1.8x
-- 推导：30s 内正常最多 10 个不同秒有 claim，允许 18 个不同秒
local SHORT_WINDOW_MAX = math.floor(
    (SHORT_WINDOW_DURATION / CLIENT_FLUSH_INTERVAL) * SHORT_WINDOW_TOLERANCE
)

-- 长窗口：捕获持续低倍速加速（正常玩家的短暂波动不会持续 120 秒）
local LONG_WINDOW_DURATION  = 120   -- 真实秒
local LONG_WINDOW_TOLERANCE = 1.4   -- 允许 1.4x
-- 推导：120s 内正常最多 40 个不同秒有 claim，允许 56 个不同秒
local LONG_WINDOW_MAX = math.floor(
    (LONG_WINDOW_DURATION / CLIENT_FLUSH_INTERVAL) * LONG_WINDOW_TOLERANCE
)

--- 每个玩家的 claim 时间戳记录（内存态，随 session 生命周期）
---@type table<number, number[]>
local claimTimestamps = {}

--- 计算时间戳数组中不同秒数的数量（同一秒内多个 claim 只算 1 次）
--- 用于防止 TCP 积压（弱网恢复后 burst）导致误报
---@param stamps number[]
---@return number distinctCount
local function countDistinctSeconds(stamps)
    if #stamps == 0 then return 0 end
    local count = 1
    local prev = stamps[1]
    for i = 2, #stamps do
        if stamps[i] ~= prev then
            count = count + 1
            prev = stamps[i]
        end
    end
    return count
end

--- 记录一次 claim 并检测是否超速（双窗口）
--- 返回 true 表示正常，false 表示超速应丢弃本次 claim
---@param uid number
---@return boolean allowed, number? speedFactor
local function checkClaimFrequency(uid)
    local now = os.time()
    local stamps = claimTimestamps[uid]
    if not stamps then
        stamps = {}
        claimTimestamps[uid] = stamps
    end

    -- 清理长窗口之外的旧时间戳（只保留 LONG_WINDOW_DURATION 内的数据）
    local cutoff = now - LONG_WINDOW_DURATION
    local newStamps = {}
    for _, ts in ipairs(stamps) do
        if ts > cutoff then
            newStamps[#newStamps + 1] = ts
        end
    end

    -- 添加当前时间戳
    newStamps[#newStamps + 1] = now
    claimTimestamps[uid] = newStamps

    -- ── 短窗口检测（30 秒，容忍 1.8x） ──
    local shortCutoff = now - SHORT_WINDOW_DURATION
    local shortStamps = {}
    for _, ts in ipairs(newStamps) do
        if ts > shortCutoff then
            shortStamps[#shortStamps + 1] = ts
        end
    end
    local shortDistinct = countDistinctSeconds(shortStamps)
    if shortDistinct > SHORT_WINDOW_MAX then
        local normalExpected = SHORT_WINDOW_DURATION / CLIENT_FLUSH_INTERVAL
        local speedFactor = shortDistinct / normalExpected
        print(string.format(
            "[BattleService][ANTI-SPEED] uid=%s SHORT_WINDOW: %d distinct seconds in %ds (max=%d) speed=%.1fx",
            tostring(uid), shortDistinct, SHORT_WINDOW_DURATION, SHORT_WINDOW_MAX, speedFactor))
        return false, speedFactor
    end

    -- ── 长窗口检测（120 秒，容忍 1.4x） ──
    local longDistinct = countDistinctSeconds(newStamps)
    if longDistinct > LONG_WINDOW_MAX then
        local normalExpected = LONG_WINDOW_DURATION / CLIENT_FLUSH_INTERVAL
        local speedFactor = longDistinct / normalExpected
        print(string.format(
            "[BattleService][ANTI-SPEED] uid=%s LONG_WINDOW: %d distinct seconds in %ds (max=%d) speed=%.1fx",
            tostring(uid), longDistinct, LONG_WINDOW_DURATION, LONG_WINDOW_MAX, speedFactor))
        return false, speedFactor
    end

    return true, nil
end

--- 清理玩家的 claim 频率记录（玩家离线时调用，避免内存泄漏）
function BattleService.ClearRateLimitBucket(uid)
    claimTimestamps[uid] = nil
end

-- ======================== 结算战斗奖励 ========================

--- 结算战斗奖励（击杀经验 + 金币 + 装备掉落种子）
---@param uid number
---@param rewards table[]
---@return boolean ok, string? err, table? result
function BattleService.ClaimBattleRewards(uid, rewards)
    local canPlay, playErr = ChallengerService.CanPlay(uid)
    if not canPlay then
        return false, playErr or "挑战者活动不可进入"
    end

    local StageConfig = getStageConfig(uid)
    local battle      = PDM.GetModule(uid, "battle")
    local heroes      = PDM.GetModule(uid, "heroes")
    local currency    = PDM.GetModule(uid, "currency")
    local playerData  = PDM.GetModule(uid, "player")
    if not battle or not heroes or not currency or not playerData then
        return false, "数据未加载"
    end
    if StageConfig.__stageProviderUnavailable then
        return false, "关卡配置不可用"
    end

    if not rewards or type(rewards) ~= "table" or #rewards == 0 then
        return false, "无奖励数据"
    end

    -- 防刷：单次上报最多 30 条击杀记录
    if #rewards > 30 then
        return false, "奖励数据异常"
    end

    -- ═══ 反加速：基于 claim 到达频率检测客户端加速 ═══
    -- 原理：客户端 flush 间隔 = 3.0 客户端秒（与墓碑复活 2.0s + 攻击 1.0s 对齐）
    -- 加速 N 倍 → flush 真实间隔 = 3.0/N 秒 → 30 秒窗口内 claim 次数 = 10*N
    local allowed, speedFactor = checkClaimFrequency(uid)
    if not allowed then
        -- 超速检测触发：丢弃整批（客户端无感知，返回空结果）
        print(string.format(
            "[BattleService][ANTI-SPEED] uid=%s CLAIM DROPPED: %d kills discarded (speed=%.1fx)",
            tostring(uid), #rewards, speedFactor or 0))
        return true, nil, { totalGold = 0, totalPlayerExp = 0, heroExp = {} }
    end
    -- ═══ 反加速检测结束 ═══

    -- 安全上限：按关卡怪物等级推算单次击杀最大可能奖励（至臻级倍率 50x）
    -- 若客户端上报值超出此上限则截断，而非直接信任
    local MAX_RANK_MULT = 50
    local function getKillCap(stageId)
        if not stageId then return { gold = 11025, exp = 766316 } end
        local stageEntry = StageConfig.getStage(stageId)
        local monsterLevel = (stageEntry and stageEntry.monsterLevel) or 1
        local maxLevel = MonsterConfig.MAX_LEVEL or 280
        if monsterLevel > maxLevel then monsterLevel = maxLevel end
        local levelData = MonsterConfig.LEVELS[monsterLevel]
        if not levelData then
            levelData = MonsterConfig.LEVELS[maxLevel]
        end
        return {
            gold = math.ceil(levelData.goldDrop * MAX_RANK_MULT),
            exp  = math.ceil(levelData.baseExp  * MAX_RANK_MULT),
        }
    end

    local totalGold = 0
    local heroExpMap = {}
    local totalPlayerExp = 0
    local currentStageId = tonumber(battle.currentStageId)
    local currentStageEntry = currentStageId and StageConfig.getStage(currentStageId)
    if not currentStageEntry then
        return false, "当前关卡数据异常"
    end

    local serverConfig = ChallengerServerConfig.GetByServerId(PDM.GetServerId(uid))
    if serverConfig and serverConfig.seasonAffixMode == "difficulty_count" then
        local affixes = MapAffixConfig.getAffixesForChallengerS1(currentStageEntry.chapter)
        if not affixes or #affixes == 0 then
            print("[BattleService][ERROR] S1词缀配置缺失 uid=" .. tostring(uid)
                .. " stageId=" .. tostring(currentStageId)
                .. " chapter=" .. tostring(currentStageEntry.chapter))
            return false, "S1词缀配置异常"
        end
    end

    for _, entry in ipairs(rewards) do
        local stageId = tonumber(entry.stageId)
        if not stageId or stageId ~= currentStageId then
            print("[BattleService][WARN] 奖励关卡与服务端当前关卡不一致 uid=" .. tostring(uid)
                .. " stageId=" .. tostring(entry.stageId)
                .. " currentStageId=" .. tostring(currentStageId))
            return false, "奖励关卡不一致"
        end

        local cap      = getKillCap(currentStageId)
        local baseExp  = math.min(entry.expReward  or 0, cap.exp)
        local baseGold = math.min(entry.goldReward or 0, cap.gold)
        if (entry.goldReward or 0) > cap.gold or (entry.expReward or 0) > cap.exp then
            print("[BattleService][WARN] 奖励超上限截断 uid=" .. tostring(uid)
                .. " stageId=" .. tostring(entry.stageId)
                .. " gold=" .. tostring(entry.goldReward) .. "/" .. baseGold
                .. " exp=" .. tostring(entry.expReward)  .. "/" .. baseExp)
        end
        local allyCount = entry.allyCount or 1
        local heroIds = entry.heroIds or {}

        totalGold = totalGold + baseGold

        if baseExp > 0 and #heroIds > 0 then
            local expMult = ExpTable.getHeroCountExpMult(allyCount)
            local totalExp = baseExp * expMult
            local perHeroExp = math.floor(totalExp / #heroIds + 0.5)
            for _, hid in ipairs(heroIds) do
                local numHid = tonumber(hid) or hid
                heroExpMap[numHid] = (heroExpMap[numHid] or 0) + perHeroExp
            end
            totalPlayerExp = totalPlayerExp + baseExp
        end
    end

    -- 校验英雄合法性
    for hid, _ in pairs(heroExpMap) do
        if not heroes.roster[hid] then
            -- [DIAG-HERO] 打印完整上下文帮助定位异常原因
            local rosterKeys = {}
            for rid, _ in pairs(heroes.roster) do rosterKeys[#rosterKeys + 1] = tostring(rid) end
            local deployedStr = "nil"
            if heroes.deployed then
                local ids = {}
                for i, v in ipairs(heroes.deployed) do ids[i] = tostring(v) end
                deployedStr = "[" .. table.concat(ids, ",") .. "]"
            end
            print(string.format("[DIAG-HERO] BattleService 英雄数据异常! hid=%s rosterKeys={%s} deployed=%s uid=%s",
                tostring(hid), table.concat(rosterKeys, ","), deployedStr, tostring(uid)))
            return false, "英雄数据异常: " .. tostring(hid)
        end
    end

    -- 修改金币
    local goldBefore = currency.gold
    currency.gold = currency.gold + totalGold
    -- [DIAG] 记录每次结算的金币变化
    print(string.format("[BattleService][DIAG] REWARD uid=%s kills=%d gold +%d (%d→%d) playerExp +%d",
        tostring(uid), #rewards, totalGold, goldBefore, currency.gold, totalPlayerExp))

    -- 发放英雄经验（自动升级）
    for hid, expAmount in pairs(heroExpMap) do
        local hero = heroes.roster[hid]
        hero.exp = (hero.exp or 0) + expAmount
        ExpTable.autoLevelUpHero(hero)
    end
    HeroService.ApplyResonanceSync(uid)

    -- 发放玩家经验（自动升级）
    if totalPlayerExp > 0 then
        local oldLv = playerData.level or 1
        playerData.exp = (playerData.exp or 0) + totalPlayerExp
        ExpTable.autoLevelUpPlayer(playerData)
        if playerData.level > oldLv then
            HeroService.SyncHeroLevelsToPlayerLevel(uid, playerData.level)
        end
    end

    -- 装备掉落判定（存种子到战利品缓冲区，符合自动分解条件的直接转精粹）
    local battleForDrop = PDM.GetModule(uid, "battle")
    local isFirstClearMode = battleForDrop and battleForDrop.battleMode == "firstClear"

    local lootboxData = PDM.GetModule(uid, "lootbox")
    local equipData   = PDM.GetModule(uid, "equipment")
    local droppedSeeds = {}
    local autoDecomposeEssence = 0
    local scrollDrops = {}
    -- 读取自动分解设置（0 = 关闭）
    local autoQuality, autoLevel = 0, 0
    if equipData and equipData.settings then
        autoQuality = equipData.settings.autoQuality or 0
        autoLevel   = equipData.settings.autoLevel   or 0
    end
    if lootboxData then
        for _, entry in ipairs(rewards) do
            local sid = entry.stageId
            if sid and sid > 0 then
                local stageEntry = StageConfig.getStage(sid)
                if stageEntry then
                    -- 装备掉落种子
                    local quality = DropSystem.rollKillDrop(stageEntry)
                    if quality then
                        local level = stageEntry.monsterLevel or 1
                        -- 检查自动分解条件：至少启用一个维度，且所有已启用的维度都满足才触发（0 = 该维度不启用不参与判断）
                        local qualityMatch = autoQuality == 0 or quality <= autoQuality
                        local levelMatch   = autoLevel   == 0 or level   <= autoLevel
                        local anyEnabled   = autoQuality > 0 or autoLevel > 0
                        if anyEnabled and qualityMatch and levelMatch then
                            -- 自动分解：直接给精粹，不入战利品区
                            local qCost = BlacksmithConfig.QUALITY_COST[quality] or BlacksmithConfig.QUALITY_COST[1]
                            local essence = math.floor(qCost.decBase * (1 + level * qCost.decScale))
                            autoDecomposeEssence = autoDecomposeEssence + essence
                            print("[BattleService] auto-decompose uid=" .. tostring(uid)
                                .. " q=" .. quality .. " lv=" .. level .. " essence=+" .. essence)
                        else
                            LootBoxSystem.addSeed(lootboxData, sid, quality, level)
                            droppedSeeds[#droppedSeeds + 1] = { quality = quality, level = level }
                            print("[BattleService] loot seed uid=" .. tostring(uid)
                                .. " stage=" .. tostring(sid) .. " q=" .. tostring(quality))
                        end
                    end
                    -- 卷轴掉落（直接加入货币）
                    local scrollType = DropSystem.rollScrollDrop(stageEntry)
                    if scrollType then
                        currency[scrollType] = (currency[scrollType] or 0) + 1
                        scrollDrops[#scrollDrops + 1] = { type = scrollType, amount = 1 }
                        print("[BattleService] scroll drop uid=" .. tostring(uid)
                            .. " stage=" .. tostring(sid) .. " type=" .. scrollType)
                    end
                end
            end
        end
    else
        print("[BattleService] WARN: lootboxData is nil uid=" .. tostring(uid))
    end

    -- 自动分解精粹结算
    if autoDecomposeEssence > 0 then
        CurrencyService.Add(uid, "essence", autoDecomposeEssence)
        print("[BattleService] auto-decompose total essence=+" .. autoDecomposeEssence .. " uid=" .. tostring(uid))
    end

    PDM.MarkDirty(uid, "currency")
    PDM.MarkDirty(uid, "heroes")
    PDM.MarkDirty(uid, "player")
    if #droppedSeeds > 0 then
        PDM.MarkDirty(uid, "lootbox")
    end

    -- ══════════ 效率窗口累计 ══════════
    local battle = PDM.GetModule(uid, "battle")
    if battle then
        -- 英雄等级变化检测：若部署英雄等级与上次记录时不同，丢弃旧 effHistory
        local deployed = heroes.deployed or {}
        local curSquadLevels = {}
        for _, hid in ipairs(deployed) do
            local hero = heroes.roster and heroes.roster[hid]
            if hero then
                curSquadLevels[hid] = hero.level or 1
            end
        end
        local prevLevels = battle.effSquadLevels or {}
        local levelChanged = false
        -- 检测：任何部署英雄等级变化即触发
        if next(prevLevels) then
            for hid, curLv in pairs(curSquadLevels) do
                if prevLevels[hid] and prevLevels[hid] ~= curLv then
                    levelChanged = true
                    break
                end
            end
        end
        if levelChanged then
            print("[BattleService] effHistory CLEARED: hero level changed"
                .. " uid=" .. tostring(uid)
                .. " prev=" .. (require("cjson").encode(prevLevels))
                .. " cur=" .. (require("cjson").encode(curSquadLevels))
                .. " oldHistLen=" .. #(battle.effHistory or {}))
            battle.effHistory = {}
            battle.effWindow = { gold = 0, exp = 0, kills = 0, startTime = 0 }
            -- 清除 stale 标记：新数据开始积累，不再是"过期"状态
            battle.effHistoryStale = nil
        end
        -- 更新等级快照（每次结算都同步最新等级）
        battle.effSquadLevels = curSquadLevels

        local w = battle.effWindow
        local now = os.time()
        -- startTime=0 表示窗口未启动，首次击杀时才开始计时
        if w.startTime == 0 then
            w.startTime = now
        end
        w.gold  = w.gold + totalGold
        w.exp   = w.exp + totalPlayerExp
        w.kills = w.kills + #rewards
        -- [DIAG] 效率窗口累计状态（每10次击杀结算打一次）
        if w.kills % 10 < #rewards then
            local winElapsed = now - w.startTime
            print(string.format(
                "[BattleService][DIAG] EFF_WINDOW ACCUM uid=%s winElapsed=%ds winGold=%d winExp=%d winKills=%d curGoldTotal=%d",
                tostring(uid), winElapsed, w.gold, w.exp, w.kills, currency.gold))
        end

        -- 窗口结算：累计时间 >= 180 秒
        local elapsed = now - w.startTime
        local EFF_WINDOW_DURATION = 180
        if elapsed >= EFF_WINDOW_DURATION then
            local entry = {
                goldPerSec  = w.gold / elapsed,
                expPerSec   = w.exp / elapsed,
                killsPerSec = w.kills / elapsed,
                stageId     = battle.currentStageId,
                ts          = now,
            }
            table.insert(battle.effHistory, entry)
            if #battle.effHistory > 10 then
                table.remove(battle.effHistory, 1)
            end
            -- 新记录写入：清除 stale 标记，客户端可显示真实效率
            if battle.effHistoryStale then
                battle.effHistoryStale = nil
            end
            -- [DIAG] 效率窗口结算日志
            print(string.format(
                "[BattleService][DIAG] EFF_WINDOW SETTLED uid=%s elapsed=%ds gold=%d goldPerSec=%.2f expPerSec=%.2f kills=%d killsPerSec=%.2f stageId=%s historyLen=%d",
                tostring(uid), elapsed, w.gold, entry.goldPerSec, entry.expPerSec,
                w.kills, entry.killsPerSec, tostring(battle.currentStageId), #battle.effHistory))
            -- 重置窗口（startTime=0 避免 AFK 稀释）
            battle.effWindow = { gold = 0, exp = 0, kills = 0, startTime = 0 }
        end
        PDM.MarkDirty(uid, "battle")
    end
    -- ══════════ 效率窗口累计结束 ══════════

    return true, nil, {
        totalGold = totalGold,
        totalPlayerExp = totalPlayerExp,
        heroExp = heroExpMap,
        droppedSeeds = #droppedSeeds > 0 and droppedSeeds or nil,
        scrollDrops = #scrollDrops > 0 and scrollDrops or nil,
        autoDecomposeEssence = autoDecomposeEssence > 0 and autoDecomposeEssence or nil,
    }
end

-- ======================== 情景对话奖励 ========================

-- 情景奖励映射表
-- type = "none"：纯对话情景，无物品奖励，但需要写 claimedScenarios 防止重复触发
local SCENARIO_REWARDS = {
    [5]  = { templateId = "W7",  quality = 2, level = 1, requiredHeroId = 1, requiredStageId = 101 },
    [6]  = { templateId = "W25", quality = 2, level = 1, requiredHeroId = 2, requiredStageId = 101 },
    [7]  = { templateId = "W37", quality = 2, level = 1, requiredHeroId = 3, requiredStageId = 101 },
    [8]  = { templateId = "A25", quality = 2, level = 1, requiredHeroId = 1, requiredStageId = 102 },
    [9]  = { templateId = "A49", quality = 2, level = 1, requiredHeroId = 2, requiredStageId = 102 },
    [10] = { templateId = "A19", quality = 2, level = 1, requiredHeroId = 3, requiredStageId = 102 },
    [11] = { type = "hero", heroPool = { 2, 3 }, requiredHeroId = 1, requiredStageId = 103 },
    [12] = { type = "hero", heroPool = { 1, 3 }, requiredHeroId = 2, requiredStageId = 103 },
    [13] = { type = "hero", heroPool = { 1, 2 }, requiredHeroId = 3, requiredStageId = 103 },

    -- 日志面板解锁情景（首通 104）：纯对话，仅标记已播放防止重复触发
    [17] = { type = "none" },   -- 日志引导·大狗嚼
    [18] = { type = "none" },   -- 日志引导·黄桃龙
    [19] = { type = "none" },   -- 日志引导·叮咚鸡

    -- 城镇面板解锁情景（首通 105）：纯对话，仅标记已播放防止重复触发
    [20] = { type = "none" },   -- 城镇引导·大狗嚼
    [21] = { type = "none" },   -- 城镇引导·黄桃龙
    [22] = { type = "none" },   -- 城镇引导·叮咚鸡

    -- 城镇初探情景：纯对话，仅标记已播放防止重复触发
    [23] = { type = "none" },   -- 城镇初探·卫兵拦截（主线）
    [24] = { type = "none" },   -- 城镇初探·大狗嚼
    [25] = { type = "none" },   -- 城镇初探·黄桃龙
    [26] = { type = "none" },   -- 城镇初探·叮咚鸡

    -- 建筑入场情景：纯对话，无物品奖励，仅标记已播放防止重复触发
    [27] = { type = "none" },   -- 教堂入场
    [47] = { type = "currency", currencyKey = "weaponScroll", amount = 20 },  -- 铁匠铺入场：武器卷轴×20
    [54] = { type = "none" },   -- 竞技场入场

    -- 酒馆入场情景：奖励冒险招募券×10
    [31] = { type = "currency", currencyKey = "recruitTicket", amount = 10 },

    -- 建筑离场情景（英雄分支）：纯对话，仅标记已播放防止重复触发
    [28] = { type = "none" },   -- 教堂离场·大狗嚼
    [29] = { type = "none" },   -- 教堂离场·黄桃龙
    [30] = { type = "none" },   -- 教堂离场·叮咚鸡
    [32] = { type = "none" },   -- 酒馆离场·大狗嚼
    [33] = { type = "none" },   -- 酒馆离场·黄桃龙
    [34] = { type = "none" },   -- 酒馆离场·叮咚鸡
    [48] = { type = "none" },   -- 铁匠铺离场·卡尔
    [49] = { type = "none" },   -- 铁匠铺离场·麦克
    [50] = { type = "none" },   -- 铁匠铺离场·叮咚鸡

    -- 首次全体阵亡情景（神秘少女出场）：纯对话，仅标记防止重复触发
    [38] = { type = "none" },   -- 首次全体阵亡·大狗嚼
    [39] = { type = "none" },   -- 首次全体阵亡·黄桃龙
    [40] = { type = "none" },   -- 首次全体阵亡·叮咚鸡

    -- 冒险者公会解锁情景（首通 305）：奖励随机品质1遗物
    [55] = { type = "relic", quality = 1, requiredHeroId = 1, requiredStageId = 1305 },
    [56] = { type = "relic", quality = 1, requiredHeroId = 2, requiredStageId = 1305 },
    [57] = { type = "relic", quality = 1, requiredHeroId = 3, requiredStageId = 1305 },

    -- 副本引导情景（首通 305）：纯对话，无奖励
    [58] = { type = "none", requiredHeroId = 1, requiredStageId = 305 },
    [59] = { type = "none", requiredHeroId = 2, requiredStageId = 305 },
    [60] = { type = "none", requiredHeroId = 3, requiredStageId = 305 },
}

--- 领取情景对话奖励
---@param uid number
---@param scenarioId number
---@return boolean ok, string? err, table? result
function BattleService.ClaimScenarioReward(uid, scenarioId)
    local rewardDef = SCENARIO_REWARDS[scenarioId]
    if not rewardDef then
        return false, "无效的情景ID"
    end

    local sessionData = PDM.GetModule(uid, "session")
    if not sessionData then
        return false, "数据未加载"
    end

    -- 防重复
    if not sessionData.claimedScenarios then
        sessionData.claimedScenarios = {}
    end
    local scenarioKey = tostring(scenarioId)
    if sessionData.claimedScenarios[scenarioKey] then
        return false, "奖励已领取"
    end

    -- 纯对话情景（建筑入场等）：无物品奖励，仅标记已播放
    if rewardDef.type == "none" then
        sessionData.claimedScenarios[scenarioKey] = true
        PDM.MarkDirty(uid, "session")
        print("[BattleService] scenario dialogue uid=" .. tostring(uid)
            .. " scenarioId=" .. tostring(scenarioId) .. " marked claimed (no reward)")
        return true, nil, { rewardType = "none" }
    end

    -- 货币奖励情景（如酒馆入场：冒险招募券×10）
    if rewardDef.type == "currency" then
        local currency = PDM.GetModule(uid, "currency")
        if not currency then
            return false, "数据未加载"
        end
        local key    = rewardDef.currencyKey
        local amount = rewardDef.amount or 0
        currency[key] = (currency[key] or 0) + amount
        sessionData.claimedScenarios[scenarioKey] = true
        PDM.MarkDirty(uid, "currency")
        PDM.MarkDirty(uid, "session")
        print("[BattleService] scenario currency uid=" .. tostring(uid)
            .. " scenarioId=" .. tostring(scenarioId)
            .. " key=" .. tostring(key) .. " amount=+" .. tostring(amount))
        return true, nil, {
            rewardType = "currency",
            reward = { currencyKey = key, amount = amount },
        }
    end

    -- 以下为需要英雄关卡校验的情景（角色专属装备/英雄奖励）
    -- 校验初始英雄
    local initialHeroId = sessionData.initialHeroId
    if not initialHeroId or initialHeroId ~= rewardDef.requiredHeroId then
        return false, "角色不匹配"
    end

    -- 校验关卡通关
    local battle = PDM.GetModule(uid, "battle")
    if not battle or not battle.clearedStages then
        return false, "关卡未通关"
    end
    if not battle.clearedStages[tostring(rewardDef.requiredStageId)] then
        return false, "关卡未通关"
    end

    if rewardDef.type == "hero" then
        return BattleService._claimHeroReward(uid, sessionData, scenarioKey, rewardDef)
    elseif rewardDef.type == "relic" then
        return BattleService._claimRelicReward(uid, sessionData, scenarioKey, rewardDef)
    else
        return BattleService._claimEquipReward(uid, sessionData, scenarioKey, rewardDef)
    end
end

--- 内部：领取英雄奖励
function BattleService._claimHeroReward(uid, sessionData, scenarioKey, rewardDef)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then
        return false, "数据未加载"
    end
    if not heroes.roster then heroes.roster = {} end

    -- 过滤已拥有的英雄
    local pool = {}
    for _, hid in ipairs(rewardDef.heroPool) do
        if not heroes.roster[hid] then
            pool[#pool + 1] = hid
        end
    end
    if #pool == 0 then
        pool = rewardDef.heroPool
    end

    local chosenHeroId = pool[math.random(#pool)]
    local heroCfg = HeroConfig.get(chosenHeroId)
    local isNew = not heroes.roster[chosenHeroId]

    if isNew then
        heroes.roster[chosenHeroId] = {
            level = 1, exp = 0, maxExp = 10,
            classId = heroCfg and heroCfg.classId or 1,
            dupeCount = 0,
        }
    else
        local hero = heroes.roster[chosenHeroId]
        local oldDupe = hero.dupeCount or 0
        if oldDupe < 7 then
            hero.dupeCount = oldDupe + 1
        end
    end

    -- 自动上阵
    local autoDeploy = false
    if isNew then
        if not heroes.deployed then heroes.deployed = {} end
        if #heroes.deployed < 5 then
            heroes.deployed[#heroes.deployed + 1] = chosenHeroId
            autoDeploy = true
        end
    end

    sessionData.claimedScenarios[scenarioKey] = true

    PDM.MarkDirty(uid, "heroes")
    PDM.MarkDirty(uid, "session")

    local heroQuality = heroCfg and heroCfg.quality or 1

    print("[BattleService] scenario hero uid=" .. tostring(uid)
        .. " heroId=" .. tostring(chosenHeroId)
        .. " isNew=" .. tostring(isNew)
        .. " autoDeploy=" .. tostring(autoDeploy))

    return true, nil, {
        rewardType = "hero",
        reward = {
            heroId   = chosenHeroId,
            name     = heroCfg and heroCfg.name or "未知",
            quality  = heroQuality,
            isNew    = isNew,
        },
    }
end

--- 内部：领取遗物奖励（随机类型 + 指定品质）
function BattleService._claimRelicReward(uid, sessionData, scenarioKey, rewardDef)
    local relicData = PDM.GetModule(uid, "mod_relics")
    if not relicData then
        return false, "数据未加载"
    end

    -- 背包容量检查
    if #relicData.bag >= RelicService.MAX_BAG then
        return false, "遗物背包已满"
    end

    -- 随机遗物类型 1~5
    local relicType = math.random(1, 5)
    local quality = rewardDef.quality or 1

    -- 随机词缀
    local affixId = RelicAffix.rollAffix(relicType, quality, 1)
    if not affixId then
        return false, "词缀池为空 type=" .. relicType .. " q=" .. quality
    end

    -- 生成遗物对象
    local id = relicData.nextId
    relicData.nextId = id + 1

    local relic = {
        id      = tostring(id),
        type    = relicType,
        quality = quality,
        affixId = affixId,
    }

    -- 加入背包
    relicData.bag[#relicData.bag + 1] = relic

    sessionData.claimedScenarios[scenarioKey] = true

    PDM.MarkDirty(uid, "mod_relics")
    PDM.MarkDirty(uid, "session")

    local typeDef = RelicDefs.TYPES[relicType]
    print("[BattleService] scenario relic uid=" .. tostring(uid)
        .. " id=" .. relic.id
        .. " type=" .. (typeDef and typeDef.name or tostring(relicType))
        .. " q=" .. quality
        .. " affix=" .. affixId)

    return true, nil, {
        rewardType = "relic",
        reward = {
            relicType = relicType,
            quality   = quality,
        },
    }
end

--- 内部：领取装备奖励
function BattleService._claimEquipReward(uid, sessionData, scenarioKey, rewardDef)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then
        return false, "数据未加载"
    end
    if EquipmentSystem.isInventoryFull(equipData) then
        return false, "背包已满"
    end

    local equip = EquipmentSystem.generate(rewardDef.templateId, rewardDef.level, rewardDef.quality)
    if not equip then
        return false, "装备生成失败"
    end

    local seq = EquipmentSystem.addToInventory(equipData, equip)

    sessionData.claimedScenarios[scenarioKey] = true

    PDM.MarkDirty(uid, "equipment")
    PDM.MarkDirty(uid, "session")

    print("[BattleService] scenario equip uid=" .. tostring(uid)
        .. " templateId=" .. rewardDef.templateId .. " seq=" .. tostring(seq))

    return true, nil, {
        rewardType = "equip",
        reward = {
            seq = seq,
            templateId = rewardDef.templateId,
            quality = rewardDef.quality,
            level = rewardDef.level,
            name = equip.name,
        },
    }
end

--- 登录时同步公会排行榜分数
--- 修正 avatarHeroId 编码变更后的过时 cloud score，确保排行榜头像和进度正确
---@param uid number
function BattleService.SyncGuildRankOnLogin(uid)
    local battle = PDM.GetModule(uid, "battle")
    if not battle or not battle.maxStageId or battle.maxStageId <= 0 then return end
    writeGuildStageRank(uid, battle.maxStageId)
    print("[BattleService] SyncGuildRankOnLogin uid=" .. tostring(uid)
        .. " maxStageId=" .. tostring(battle.maxStageId))
end

return BattleService
