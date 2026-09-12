---@diagnostic disable: param-type-mismatch, return-type-mismatch
-- ============================================================================
-- ArenaService - 竞技场业务逻辑层
-- 从 ArenaHandlers 迁移: SaveManager → PDM
-- 异步函数通过 callback(result) 返回结果，Handler 在 callback 中 respond
-- ============================================================================

local PDM              = require("server.character.PlayerDataManager")
local TaskService      = require("server.task.TaskService")
local HeroService      = require("server.hero.HeroService")
local ArenaConfig      = require("config.ArenaConfig")
local ArenaAITemplates = require("config.ArenaAITemplates")
local MailService      = require("server.mail.MailService")

local ArenaService = {}

-- ======================== 工具函数（模块内部） ========================

--- 获取带区服前缀的 cloud key（从 uid 自动推导 serverId）
---@param keyName string  ArenaConfig.CLOUD_KEYS 中的 key 名
---@param uid number      触发操作的玩家 uid
---@return string
local function ck(keyName, uid)
    local serverId = PDM.GetServerId(uid)
    if not serverId then
        print("[ArenaService][WARN] ck() called without serverId for uid=" .. tostring(uid)
            .. " key=" .. keyName .. " — using unprefixed key")
        return ArenaConfig.CLOUD_KEYS[keyName]
    end
    return ArenaConfig.getCloudKey(keyName, serverId)
end

--- 取玩家设置的展示头像
---@param uid number
---@return number
local function getAvatarHeroId(uid)
    local player = PDM.GetModule(uid, "player")
    if player and player.avatarHeroId then
        return player.avatarHeroId
    end
    return 1
end

--- 将玩家名字写入排行榜 score 字段 + 独立 player_nickname 存档
--- 双写策略：score 字段供 GetRankList 直接读取（如支持），player_nickname 供 BatchGet 兜底
---@param uid number
---@param cloudKey string
local function writeRankName(uid, cloudKey)
    local player = PDM.GetModule(uid, "player")
    local name = player and player.name
    if name and name ~= "" then
        serverCloud:Set(uid, cloudKey, name)
        -- 同时写入独立 key，确保离线玩家也能被 BatchGet 查询到昵称
        serverCloud:Set(uid, "player_nickname", name)
    end
end

--- 获取当天编号（UTC+8）
---@return number dayNumber
local function getDayNumber()
    return math.floor((os.time() + 28800) / 86400)
end

--- 检查并重置每日竞技券
---@param arena table
local function resetDailyTickets(arena)
    local today = getDayNumber()
    if (arena.ticketResetDay or 0) ~= today then
        arena.ticketsUsedToday = 0
        arena.ticketResetDay   = today
    end
end

--- 计算剩余竞技券数
---@param arena table
---@param uid number|nil
---@return number remaining
local function getRemainingTickets(arena, uid)
    local dailyLimit = ArenaConfig.TICKET_DAILY_FREE
    local used = arena.ticketsUsedToday or 0
    local remaining = math.max(0, dailyLimit - used)
    if uid then
        local currency = PDM.GetModule(uid, "currency")
        remaining = remaining + math.max(0, currency and currency.arenaTicket or 0)
    end
    return remaining
end

--- 实时计算玩家防守阵容战力，并同步到 player.power
--- 用于竞技场排名展示，避免读取从未更新的 player.power 默认值（1000）
---@param uid number
---@return number power
local function computeAndSyncPower(uid)
    local heroes    = PDM.GetModule(uid, "heroes")
    local equipment = PDM.GetModule(uid, "equipment")
    local challenger = PDM.GetModule(uid, "challenger")
    if not heroes or not heroes.deployed or #heroes.deployed == 0 then
        return 0
    end

    local heroSnap = {}
    for _, hid in ipairs(heroes.deployed) do
        local hero = heroes.roster and (heroes.roster[hid] or heroes.roster[tostring(hid)])
        if hero then
            heroSnap[#heroSnap + 1] = {
                heroId    = hid,
                level     = HeroService.GetHeroEffectiveLevel(uid, hid),
                advBranch = hero.advBranch,
                awakening = hero.awakening,
            }
        end
    end

    local equipSnap = {}
    if equipment and equipment.equipped and equipment.inventory then
        for _, hid in ipairs(heroes.deployed) do
            local slots = equipment.equipped[hid]
            if slots then
                local heroEquips = {}
                for slot, seq in pairs(slots) do
                    local item = equipment.inventory[tostring(seq)]
                    if item then heroEquips[slot] = item end
                end
                if next(heroEquips) then equipSnap[hid] = heroEquips end
            end
        end
    end

    local unlockedAvatarFrames = challenger and challenger.unlockedAvatarFrames or nil
    local power = ArenaAITemplates.calcDefensePower(heroSnap, equipSnap, unlockedAvatarFrames)

    -- 同步更新 PDM
    local player = PDM.GetModule(uid, "player")
    if player and player.power ~= power then
        player.power = power
        PDM.MarkDirty(uid, "player")
    end

    return power
end

--- 构建防守阵容快照（从 PDM 内存数据）
---@param uid number
---@return table|nil snapshot
local function buildDefenseSnapshot(uid)
    local heroes    = PDM.GetModule(uid, "heroes")
    local equipment = PDM.GetModule(uid, "equipment")
    local talents   = PDM.GetModule(uid, "talents")
    local player    = PDM.GetModule(uid, "player")
    local challenger = PDM.GetModule(uid, "challenger")
    if not heroes or not heroes.deployed or #heroes.deployed == 0 then
        return nil
    end

    local heroSnap = {}
    for _, hid in ipairs(heroes.deployed) do
        local hero = heroes.roster and (heroes.roster[hid] or heroes.roster[tostring(hid)])
        if hero then
            heroSnap[#heroSnap + 1] = {
                heroId    = hid,
                level     = HeroService.GetHeroEffectiveLevel(uid, hid),
                exp       = hero.exp or 0,
                advBranch = hero.advBranch,
                awakening = hero.awakening,
            }
        end
    end

    local equipSnap = {}
    if equipment and equipment.equipped and equipment.inventory then
        for _, hid in ipairs(heroes.deployed) do
            local slots = equipment.equipped[hid]
            if slots then
                local heroEquips = {}
                for slot, seq in pairs(slots) do
                    local item = equipment.inventory[tostring(seq)]
                    if item then
                        heroEquips[slot] = item
                    end
                end
                if next(heroEquips) then
                    equipSnap[hid] = heroEquips
                end
            end
        end
    end

    local talentSnap = nil
    if talents and talents.litNodes then
        talentSnap = { litNodes = talents.litNodes }
    end

    -- 槽位强化快照
    local slotEnhance = PDM.GetModule(uid, "slotEnhance")
    local slotEnhanceSnap = nil
    if slotEnhance and slotEnhance.levels then
        slotEnhanceSnap = { levels = slotEnhance.levels }
    end

    -- 遗物 grid 快照（只含已镶嵌的遗物，需要 affixId + quality 供客户端还原属性）
    local relicData = PDM.GetModule(uid, "mod_relics")
    local relicGridSnap = nil
    if relicData and relicData.grid and #relicData.grid > 0 then
        relicGridSnap = {}
        for _, relic in ipairs(relicData.grid) do
            relicGridSnap[#relicGridSnap + 1] = {
                affixId = relic.affixId,
                quality = relic.quality,
            }
        end
    end

    -- 实时计算防守阵容战力（复用 computeAndSyncPower，内部也会更新 player.power）
    local computedPower = computeAndSyncPower(uid)

    return {
        heroes      = heroSnap,
        equipment   = equipSnap,
        talents     = talentSnap,
        slotEnhance = slotEnhanceSnap,
        relicGrid   = relicGridSnap,
        unlockedAvatarFrames = challenger and challenger.unlockedAvatarFrames or nil,
        power       = computedPower,
        timestamp   = os.time(),
    }
end

--- 从小组成员列表构建排名
---@param members table[]
---@return table[] sorted
local function buildRankings(members)
    local ranked = {}
    for _, m in ipairs(members) do
        local v = m.value or m
        ranked[#ranked + 1] = {
            uid          = tonumber(v.uid) or v.uid,
            name         = (v.name and v.name ~= "") and v.name or "玩家",
            weekScore    = tonumber(v.weekScore) or ArenaConfig.WEEK_SCORE_INIT,
            power        = tonumber(v.power) or 0,
            listId       = m.list_id,
            joinTime     = tonumber(v.joinTime) or 0,
            avatarHeroId = tonumber(v.avatarHeroId) or 1,
        }
    end

    -- 竞态防护: 并发加入可能导致成员数 > GROUP_SIZE
    if #ranked > ArenaConfig.GROUP_SIZE then
        print("[Arena][WARN] group has " .. #ranked .. " members (>" .. ArenaConfig.GROUP_SIZE
            .. "), truncating to earliest " .. ArenaConfig.GROUP_SIZE)
        table.sort(ranked, function(a, b)
            return (a.joinTime or 0) < (b.joinTime or 0)
        end)
        for i = ArenaConfig.GROUP_SIZE + 1, #ranked do
            ranked[i] = nil
        end
    end

    table.sort(ranked, function(a, b)
        if a.weekScore ~= b.weekScore then
            return a.weekScore > b.weekScore
        end
        return a.joinTime < b.joinTime
    end)
    for i, r in ipairs(ranked) do
        r.rank = i
    end
    return ranked
end

--- 在排名中找到指定 uid 的名次
---@param rankings table[]
---@param uid number
---@return number rank
---@return table|nil entry
local function findRank(rankings, uid)
    for _, r in ipairs(rankings) do
        if r.uid == uid then
            return r.rank, r
        end
    end
    return ArenaConfig.GROUP_SIZE, nil
end

--- 用 AI 玩家填充排名列表至 GROUP_SIZE
---@param rankings table[]
---@param groupId number
---@param rankScore number
---@return table[] rankings
local function fillRankingsWithAI(rankings, groupId, rankScore)
    local realCount = #rankings
    if realCount >= ArenaConfig.GROUP_SIZE then return rankings end

    local aiNames = ArenaConfig.AI_NAMES
    local nameCount = #aiNames

    for i = 1, ArenaConfig.GROUP_SIZE - realCount do
        local nameIdx = ((groupId or 0) + i - 1) % nameCount + 1
        local aiSeed = (groupId or 0) * 1000 + i
        rankings[#rankings + 1] = {
            uid          = -aiSeed,
            name         = aiNames[nameIdx],
            weekScore    = ArenaConfig.WEEK_SCORE_INIT,
            power        = ArenaAITemplates.deterministicPowerByScore(rankScore or 0, aiSeed),
            listId       = nil,
            joinTime     = 0,
            avatarHeroId = (aiSeed % 15) + 1,
        }
    end
    table.sort(rankings, function(a, b)
        if a.weekScore ~= b.weekScore then
            return a.weekScore > b.weekScore
        end
        return a.joinTime < b.joinTime
    end)
    for i, r in ipairs(rankings) do
        r.rank = i
    end
    return rankings
end

--- 追加对战历史记录
---@param uid number
---@param arena table
---@param entry table
local function appendBattleHistory(uid, arena, entry)
    if not arena.battleHistory then
        arena.battleHistory = {}
    end
    arena.battleHistory[#arena.battleHistory + 1] = entry
    while #arena.battleHistory > ArenaConfig.BATTLE_HISTORY_MAX do
        table.remove(arena.battleHistory, 1)
    end
    PDM.MarkDirty(uid, "arena")
end

--- 商店购买记录周重置
---@param arena table
---@param currentWeekId number
---@param uid number
local function resetShopWeekly(arena, currentWeekId, uid)
    if (arena.shopWeekId or 0) ~= currentWeekId then
        local kept = {}
        for id, count in pairs(arena.shopPurchased or {}) do
            local cfg = ArenaConfig.getShopItem(id)
            if cfg and cfg.limitCycle == "forever" then
                kept[id] = count
            end
        end
        arena.shopPurchased = kept
        arena.shopWeekId = currentWeekId
        PDM.MarkDirty(uid, "arena")
    end
end

-- ======================== 内部异步流程 ========================

--- 结算防守日志（延迟结算）
---@param uid number
---@param arena table
---@param onDone function()
local function settleDefenseLogs(uid, arena, onDone)
    serverCloud.list:Get(uid, ck("DEFENSE_LOG", uid), {
        ok = function(items)
            if not items or #items == 0 then
                onDone()
                return
            end

            local totalScoreChange = 0
            local settledLogs = {}

            for _, item in ipairs(items) do
                local v = item.value or item
                local sc = tonumber(v.scoreChange) or 0
                totalScoreChange = totalScoreChange + sc
                settledLogs[#settledLogs + 1] = {
                    attackerName = v.attackerName or "未知",
                    result       = v.result,
                    scoreChange  = sc,
                    timestamp    = v.timestamp,
                }
            end

            local commit = serverCloud:BatchCommit("settle_def_" .. tostring(uid))
            for _, item in ipairs(items) do
                if item.list_id then
                    commit:ListDelete(item.list_id)
                end
            end
            commit:Commit({
                ok = function()
                    if totalScoreChange ~= 0 then
                        arena.weekScore = math.max(0, (arena.weekScore or ArenaConfig.WEEK_SCORE_INIT) + totalScoreChange)
                        PDM.MarkDirty(uid, "arena")
                    end
                    print("[Arena] settled " .. #items .. " defense logs for uid=" .. tostring(uid)
                        .. " scoreChange=" .. totalScoreChange)
                    for _, log in ipairs(settledLogs) do
                        appendBattleHistory(uid, arena, {
                            type         = "defense",
                            opponentName = log.attackerName,
                            result       = log.result,
                            scoreChange  = log.scoreChange,
                            timestamp    = log.timestamp,
                        })
                    end
                    arena._settledDefenseLogs = settledLogs
                    onDone()
                end,
                error = function(code, reason)
                    print("[Arena][WARN] settle defense log delete failed uid=" .. tostring(uid)
                        .. " code=" .. tostring(code) .. " — scoreChange NOT applied")
                    arena._settledDefenseLogs = settledLogs
                    onDone()
                end,
            })
        end,
        error = function(code, reason)
            print("[Arena] read defense log error uid=" .. tostring(uid)
                .. " code=" .. tostring(code))
            onDone()
        end,
    })
end

--- 生成含周号的小组 cloud key（隔离不同周的小组数据）
---@param uid number
---@param weekId number
---@param groupId number
---@return string
local function getGroupKey(uid, weekId, groupId)
    return ck("GROUP_PREFIX", uid) .. "w" .. tostring(weekId) .. "_" .. tostring(groupId)
end

--- 惰性周结算
---@param uid number
---@param arena table
---@param currentWeekId number
---@param onDone function()
local function lazySettlement(uid, arena, currentWeekId, onDone)
    local lastWeekId = arena.lastSettleWeekId or 0

    if lastWeekId == 0 or currentWeekId <= lastWeekId then
        if arena.weekId ~= currentWeekId then
            arena.weekId    = currentWeekId
            arena.weekScore = ArenaConfig.WEEK_SCORE_INIT
            arena.groupId   = nil
            PDM.MarkDirty(uid, "arena")
        end
        onDone()
        return
    end

    local oldGroupId = arena.groupId
    if not oldGroupId then
        -- 上周无小组，直接重置，补发最低档奖励邮件
        local reward = ArenaConfig.getWeekReward(ArenaConfig.GROUP_SIZE)
        if reward then
            local mailRewards = {}
            if (reward.diamond or 0) > 0 then
                mailRewards[#mailRewards + 1] = { type = "diamond", amount = reward.diamond }
            end
            if (reward.arenaCoin or 0) > 0 then
                mailRewards[#mailRewards + 1] = { type = "arena_coin", amount = reward.arenaCoin }
            end
            if #mailRewards > 0 then
                MailService.SendDynamicMail(uid, {
                    title   = "竞技场周结算奖励",
                    body    = "上周竞技场结算奖励，请查收！",
                    rewards = mailRewards,
                    source  = "arena_weekly",
                })
            end
        end
        arena.weekId            = currentWeekId
        arena.weekScore         = ArenaConfig.WEEK_SCORE_INIT
        arena.lastSettleWeekId  = currentWeekId
        arena.groupId           = nil
        PDM.MarkDirty(uid, "arena")
        onDone()
        return
    end

    -- 读取上周的小组数据（使用含上周周号的 key）
    local groupKey = getGroupKey(uid, lastWeekId, oldGroupId)
    serverCloud.list:Get(ArenaConfig.PUBLIC_UID, groupKey, {
        ok = function(members)
            local rankings = buildRankings(members or {})
            -- 修复：结算时也需填充 AI 对手参与排名，否则唯一真人永远第1名
            fillRankingsWithAI(rankings, oldGroupId, arena.rankScore)
            local myRank = findRank(rankings, uid)
            local reward = ArenaConfig.getWeekReward(myRank)

            local rewardSummary = nil
            if reward then
                arena.rankScore = math.max(0, (arena.rankScore or 0) + reward.rankScoreChange)

                -- 段位首次达成：仅记录 reachedTiers，奖励等玩家手动领取
                -- 修复：结算后 rankScore 可能跳过多个段位（如从 90→340 越过黑铁IV、III）
                -- 必须循环标记从 id=1 到当前段位的所有中间段位，否则玩家无法领取被跳过的段位奖励
                local newTier = ArenaConfig.getTierByScore(arena.rankScore)
                if newTier then
                    for _, t in ipairs(ArenaConfig.TIERS) do
                        if t.id <= newTier.id then
                            if not arena.reachedTiers[t.id] then
                                arena.reachedTiers[t.id] = true
                                print("[Arena] 段位达成(补录) uid=" .. tostring(uid) .. " tier=" .. tostring(t.id))
                            end
                        else
                            break
                        end
                    end
                end

                -- 周结算奖励通过邮件发放（支持多周未登录累积，不会覆盖）
                local mailRewards = {}
                if (reward.diamond or 0) > 0 then
                    mailRewards[#mailRewards + 1] = { type = "diamond", amount = reward.diamond }
                end
                if (reward.arenaCoin or 0) > 0 then
                    mailRewards[#mailRewards + 1] = { type = "arena_coin", amount = reward.arenaCoin }
                end

                if #mailRewards > 0 then
                    local tierName = newTier and ArenaConfig.getTierDisplayName(newTier) or ""
                    local rsc = reward.rankScoreChange
                    local rscText = rsc > 0 and ("+" .. rsc) or tostring(rsc)
                    MailService.SendDynamicMail(uid, {
                        title   = "竞技场周结算奖励",
                        body    = "恭喜你在上周竞技场中获得第" .. myRank .. "名！"
                                .. (tierName ~= "" and ("（" .. tierName .. "）") or "")
                                .. "\n段位分变化：" .. rscText,
                        rewards = mailRewards,
                        source  = "arena_weekly",
                    })
                end

                rewardSummary = {
                    rank            = myRank,
                    rankScoreChange = reward.rankScoreChange,
                    diamond         = reward.diamond,
                    arenaCoin       = reward.arenaCoin,
                    newTier         = newTier and ArenaConfig.getTierDisplayName(newTier) or nil,
                    viaMail         = true,  -- 通知客户端奖励在邮件中
                }

                print("[Arena] weekly settle uid=" .. tostring(uid)
                    .. " rank=" .. myRank
                    .. " rankScoreChange=" .. reward.rankScoreChange
                    .. " diamond=" .. reward.diamond
                    .. " (via mail)")
            end

            arena.weekId            = currentWeekId
            arena.weekScore         = ArenaConfig.WEEK_SCORE_INIT
            arena.lastSettleWeekId  = currentWeekId
            arena.groupId           = nil
            arena.battleHistory     = {}
            arena._weekSettlement   = rewardSummary
            PDM.MarkDirty(uid, "arena")

            -- 分数编码: score = rankScore * 100 + avatarHeroId（与主线排行榜同模式）
            local avatarId = getAvatarHeroId(uid)
            local encodedScore = (arena.rankScore or 0) * 100 + avatarId
            serverCloud:SetInt(uid, ck("RANK_SCORE", uid), encodedScore)
            writeRankName(uid, ck("RANK_SCORE", uid))

            onDone()
        end,
        error = function(code, reason)
            print("[Arena] read old group error uid=" .. tostring(uid)
                .. " code=" .. tostring(code) .. " — sending fallback mail and resetting")
            -- cloud 读取失败：补发最低档奖励邮件，标记已结算（不再重试，避免反复漏发）
            local fallbackReward = ArenaConfig.getWeekReward(ArenaConfig.GROUP_SIZE)
            if fallbackReward then
                local mailRewards = {}
                if (fallbackReward.diamond or 0) > 0 then
                    mailRewards[#mailRewards + 1] = { type = "diamond", amount = fallbackReward.diamond }
                end
                if (fallbackReward.arenaCoin or 0) > 0 then
                    mailRewards[#mailRewards + 1] = { type = "arena_coin", amount = fallbackReward.arenaCoin }
                end
                if #mailRewards > 0 then
                    MailService.SendDynamicMail(uid, {
                        title   = "竞技场周结算奖励",
                        body    = "上周竞技场结算奖励，请查收！",
                        rewards = mailRewards,
                        source  = "arena_weekly",
                    })
                end
            end
            arena.weekId            = currentWeekId
            arena.weekScore         = ArenaConfig.WEEK_SCORE_INIT
            arena.lastSettleWeekId  = currentWeekId
            arena.groupId           = nil
            PDM.MarkDirty(uid, "arena")
            onDone()
        end,
    })
end

--- 分配小组（或读取已有小组）
---@param uid number
---@param arena table
---@param defenseSnapshot table
---@param onDone function(rankings: table[])
local function allocateGroup(uid, arena, defenseSnapshot, onDone)
    if arena.groupId then
        local groupKey = getGroupKey(uid, arena.weekId, arena.groupId)
        serverCloud.list:Get(ArenaConfig.PUBLIC_UID, groupKey, {
            ok = function(members)
                local rankings = buildRankings(members or {})
                fillRankingsWithAI(rankings, arena.groupId, arena.rankScore)
                onDone(rankings)
            end,
            error = function(code, reason)
                print("[Arena] read group error uid=" .. tostring(uid)
                    .. " groupId=" .. tostring(arena.groupId))
                onDone({})
            end,
        })
        return
    end

    local player = PDM.GetModule(uid, "player")
    local playerName = (player and player.name and player.name ~= "") and player.name or "玩家"

    serverCloud:Get(ArenaConfig.PUBLIC_UID, ck("META", uid), {
        ok = function(scores)
            local rawScores = scores or {}
            local meta = rawScores[ck("META", uid)]
            if type(meta) ~= "table" then meta = {} end

            local currentGroupId = tonumber(meta.currentGroupId) or 1
            -- 按周重置 meta.currentGroupId：新的一周从第 1 组开始（旧周 key 含旧周号，不会冲突）
            if tonumber(meta.weekId) ~= arena.weekId then
                currentGroupId = 1
            end
            local groupKey = getGroupKey(uid, arena.weekId, currentGroupId)

            serverCloud.list:Get(ArenaConfig.PUBLIC_UID, groupKey, {
                ok = function(members)
                    members = members or {}
                    local groupId = currentGroupId

                    if #members >= ArenaConfig.GROUP_SIZE then
                        groupId = currentGroupId + 1
                        local metaCommit = serverCloud:BatchCommit("arena_meta_" .. tostring(uid))
                        metaCommit:ScoreSet(ArenaConfig.PUBLIC_UID, ck("META", uid), {
                            currentGroupId = groupId,
                            weekId         = arena.weekId,
                        })
                        metaCommit:Commit({
                            ok = function()
                                print("[Arena] created new group " .. groupId .. " week=" .. arena.weekId)
                            end,
                            error = function(code)
                                print("[Arena] meta update error code=" .. tostring(code))
                            end,
                        })
                        members = {}
                    else
                        -- 当前组未满，也写入 weekId 以确保 meta 按周更新
                        if tonumber(meta.weekId) ~= arena.weekId then
                            local metaCommit = serverCloud:BatchCommit("arena_meta_week_" .. tostring(uid))
                            metaCommit:ScoreSet(ArenaConfig.PUBLIC_UID, ck("META", uid), {
                                currentGroupId = groupId,
                                weekId         = arena.weekId,
                            })
                            metaCommit:Commit({
                                ok = function()
                                    print("[Arena] meta weekId updated to " .. arena.weekId)
                                end,
                                error = function(code)
                                    print("[Arena] meta weekId update error code=" .. tostring(code))
                                end,
                            })
                        end
                    end

                    local alreadyInGroup = false
                    for _, m in ipairs(members) do
                        local v = m.value or m
                        if tonumber(v.uid) == uid then
                            alreadyInGroup = true
                            print("[Arena] uid=" .. tostring(uid) .. " already in group " .. groupId .. ", skip Add")
                            break
                        end
                    end

                    local playerAvatarId = player and player.avatarHeroId or 1
                    local memberEntry = {
                        uid          = uid,
                        name         = playerName,
                        weekScore    = arena.weekScore,
                        power        = defenseSnapshot and defenseSnapshot.power or 0,
                        joinTime     = os.time(),
                        avatarHeroId = playerAvatarId,
                    }
                    local newGroupKey = getGroupKey(uid, arena.weekId, groupId)

                    if not alreadyInGroup then
                        serverCloud.list:Add(ArenaConfig.PUBLIC_UID, newGroupKey, memberEntry, {
                            ok = function()
                                print("[Arena] uid=" .. tostring(uid) .. " joined group " .. groupId
                                    .. " week=" .. arena.weekId)
                            end,
                            error = function(code)
                                print("[Arena] list.Add error uid=" .. tostring(uid)
                                    .. " code=" .. tostring(code))
                            end,
                        })
                    end

                    arena.groupId = groupId
                    -- 修复: allocateGroup 不再覆盖 lastSettleWeekId
                    -- lazySettlement 在结算完成后已正确设置 lastSettleWeekId = currentWeekId
                    -- 此处只需在首次进入时（lastSettleWeekId==0）才更新
                    if (arena.lastSettleWeekId or 0) == 0 then
                        arena.lastSettleWeekId = arena.weekId
                    end
                    PDM.MarkDirty(uid, "arena")

                    -- 加入小组时同步写入全服排行榜（确保每个进入竞技场的玩家都出现在排行榜上）
                    local avatarId = getAvatarHeroId(uid)
                    local encodedScore = (arena.rankScore or 0) * 100 + avatarId
                    serverCloud:SetInt(uid, ck("RANK_SCORE", uid), encodedScore)
                    writeRankName(uid, ck("RANK_SCORE", uid))

                    if defenseSnapshot then
                        local defCommit = serverCloud:BatchCommit("arena_def_" .. tostring(uid))
                        defCommit:ScoreSet(uid, ck("DEFENSE", uid), defenseSnapshot)
                        defCommit:Commit({
                            ok = function()
                                print("[Arena] defense synced uid=" .. tostring(uid))
                            end,
                            error = function(code)
                                print("[Arena] defense sync error uid=" .. tostring(uid))
                            end,
                        })
                    end

                    if not alreadyInGroup then
                        members[#members + 1] = { list_id = nil, value = memberEntry }
                    end

                    -- AI 不持久化到 serverCloud.list，仅在排名时由 fillRankingsWithAI 内存填充
                    local rankings = buildRankings(members)
                    fillRankingsWithAI(rankings, groupId, arena.rankScore)
                    onDone(rankings)
                end,
                error = function(code)
                    print("[Arena] read group for alloc error code=" .. tostring(code))
                    onDone({})
                end,
            })
        end,
        error = function(code)
            print("[Arena] read meta error code=" .. tostring(code))
            onDone({})
        end,
    })
end

--- 异步读取全服段位分排行榜
---@param uid number
---@param topN number
---@param onDone function(globalRankings: table[], globalMyRank: number|nil)
local function fetchGlobalRankings(uid, topN, onDone)
    topN = topN or 50
    serverCloud:GetRankList(ck("RANK_SCORE", uid), 1, topN, {
        ok = function(rankList)
            local userIds = {}
            local results = {}
            local rankKey = ck("RANK_SCORE", uid)
            for i, item in ipairs(rankList) do
                local rawScore = item.iscore[rankKey] or 0
                -- 分数编码: score = rankScore * 100 + avatarHeroId
                local rankScore    = math.floor(rawScore / 100)
                local avatarHeroId = rawScore % 100
                if avatarHeroId < 1 then avatarHeroId = 1 end
                -- 优先从排行榜持久化的 score 字段读取名字（离线玩家也有）
                local persistedName = item.score and item.score[rankKey]
                if type(persistedName) ~= "string" or persistedName == "" then
                    persistedName = nil
                end
                userIds[#userIds + 1] = item.userId
                results[#results + 1] = {
                    rank         = i,
                    uid          = item.userId,
                    rankScore    = rankScore,
                    avatarHeroId = avatarHeroId,
                    name         = persistedName or "",
                }
            end

            -- 用计数器等 GetUserNickname 和 GetUserRank 都完成后再回调
            -- 避免 GetUserRank 先返回导致昵称未填入就触发 onDone
            local pendingCount = 2
            local myRankResult = nil

            local function tryFinish()
                pendingCount = pendingCount - 1
                if pendingCount == 0 then
                    onDone(results, myRankResult)
                end
            end

            if #userIds > 0 then
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do
                            local nick = info.nickname
                            if nick and nick ~= "" then
                                map[info.userId] = nick
                            end
                        end
                        -- 第一轮：用在线昵称覆盖
                        for _, entry in ipairs(results) do
                            if map[entry.uid] then
                                entry.name = map[entry.uid]
                            end
                        end
                        -- 收集仍然缺名字的离线玩家 uid
                        local missingUids = {}
                        for _, entry in ipairs(results) do
                            if not entry.name or entry.name == "" then
                                missingUids[#missingUids + 1] = entry.uid
                            end
                        end
                        -- 第二轮：BatchGet 读取 player_nickname 兜底
                        if #missingUids > 0 then
                            local batch = serverCloud:BatchGet()
                            for _, mUid in ipairs(missingUids) do
                                batch:Player(mUid)
                            end
                            batch:Key("player_nickname")
                            batch:Fetch({
                                ok = function(batchResults)
                                    local nickMap = {}
                                    for _, r in ipairs(batchResults) do
                                        local storedNick = r.score and r.score.player_nickname
                                        if type(storedNick) == "string" and storedNick ~= "" then
                                            nickMap[r.userId] = storedNick
                                        end
                                    end
                                    for _, entry in ipairs(results) do
                                        if (not entry.name or entry.name == "") and nickMap[entry.uid] then
                                            entry.name = nickMap[entry.uid]
                                        end
                                    end
                                    -- 最终 fallback
                                    for _, entry in ipairs(results) do
                                        if not entry.name or entry.name == "" then
                                            entry.name = "玩家" .. tostring(entry.uid)
                                        end
                                    end
                                    tryFinish()
                                end,
                                error = function(code, reason)
                                    print("[Arena] BatchGet player_nickname error code=" .. tostring(code))
                                    for _, entry in ipairs(results) do
                                        if not entry.name or entry.name == "" then
                                            entry.name = "玩家" .. tostring(entry.uid)
                                        end
                                    end
                                    tryFinish()
                                end,
                            })
                        else
                            tryFinish()
                        end
                    end,
                    onError = function()
                        -- GetUserNickname 完全失败：尝试 BatchGet player_nickname 兜底
                        local allUids = {}
                        for _, entry in ipairs(results) do
                            if not entry.name or entry.name == "" then
                                allUids[#allUids + 1] = entry.uid
                            end
                        end
                        if #allUids > 0 then
                            local batch = serverCloud:BatchGet()
                            for _, mUid in ipairs(allUids) do
                                batch:Player(mUid)
                            end
                            batch:Key("player_nickname")
                            batch:Fetch({
                                ok = function(batchResults)
                                    local nickMap = {}
                                    for _, r in ipairs(batchResults) do
                                        local storedNick = r.score and r.score.player_nickname
                                        if type(storedNick) == "string" and storedNick ~= "" then
                                            nickMap[r.userId] = storedNick
                                        end
                                    end
                                    for _, entry in ipairs(results) do
                                        if (not entry.name or entry.name == "") and nickMap[entry.uid] then
                                            entry.name = nickMap[entry.uid]
                                        end
                                    end
                                    for _, entry in ipairs(results) do
                                        if not entry.name or entry.name == "" then
                                            entry.name = "玩家" .. tostring(entry.uid)
                                        end
                                    end
                                    tryFinish()
                                end,
                                error = function(code, reason)
                                    print("[Arena] BatchGet player_nickname fallback error code=" .. tostring(code))
                                    for _, entry in ipairs(results) do
                                        if not entry.name or entry.name == "" then
                                            entry.name = "玩家" .. tostring(entry.uid)
                                        end
                                    end
                                    tryFinish()
                                end,
                            })
                        else
                            for _, entry in ipairs(results) do
                                if not entry.name or entry.name == "" then
                                    entry.name = "玩家" .. tostring(entry.uid)
                                end
                            end
                            tryFinish()
                        end
                    end,
                })
            else
                pendingCount = pendingCount - 1
            end

            serverCloud:GetUserRank(uid, ck("RANK_SCORE", uid), {
                ok = function(myRank, myScore)
                    print("[Arena] globalRankings fetched: top=" .. #results
                        .. " myRank=" .. tostring(myRank))
                    myRankResult = myRank
                    tryFinish()
                end,
                error = function(code, reason)
                    print("[Arena] GetUserRank error code=" .. tostring(code))
                    tryFinish()
                end,
            })
        end,
        error = function(code, reason)
            print("[Arena] GetRankList error code=" .. tostring(code))
            onDone({}, nil)
        end,
    })
end

-- ======================== 公开业务方法 ========================

--- 进入竞技场（异步）
--- 已有分组+本周 → 同步防守+结算日志+读排名
--- 新周/首次 → 周结算→分组→结算日志→排名
---@param uid number
---@param params table|nil
---@param callback function(result: table)
function ArenaService.Enter(uid, params, callback)
    local arena = PDM.GetModule(uid, "arena")
    if not arena then
        callback({ success = false, reason = "数据未加载" })
        return
    end

    local currentWeekId = ArenaConfig.calcWeekId()
    resetDailyTickets(arena)

    -- 修复：确保 reachedTiers 反映当前 rankScore（覆盖初始段位及老存档缺失）
    if not arena.reachedTiers then arena.reachedTiers = {} end
    local curTier = ArenaConfig.getTierByScore(arena.rankScore or 0)
    if curTier then
        local dirty = false
        for _, t in ipairs(ArenaConfig.TIERS) do
            if t.id <= curTier.id then
                if not arena.reachedTiers[t.id] then
                    arena.reachedTiers[t.id] = true
                    dirty = true
                end
            else
                break
            end
        end
        if dirty then
            PDM.MarkDirty(uid, "arena")
        end
    end

    -- 注意：战斗力由服务端 player 模块权威存储，不接受客户端注入
    -- 客户端战斗力在 BattleService.ClaimBattleRewards 等关键结算时已由服务端重算并更新

    local defenseSnapshot = buildDefenseSnapshot(uid)

    --- 构建最终响应
    ---@param rankings table[]
    ---@param includeWeekSettlement boolean
    local function buildResponse(rankings, includeWeekSettlement)
        local myRank = findRank(rankings, uid)
        local tier = ArenaConfig.getTierByScore(arena.rankScore or 0)
        resetShopWeekly(arena, currentWeekId, uid)

        fetchGlobalRankings(uid, 50, function(globalRankings, globalMyRank)
            local result = {
                success         = true,
                rankings        = rankings,
                myRank          = myRank,
                weekScore       = arena.weekScore,
                rankScore       = arena.rankScore,
                tier            = tier and ArenaConfig.getTierDisplayName(tier) or "黑铁级 V",
                tierId          = tier and tier.id or 1,
                tickets         = getRemainingTickets(arena, uid),
                weekId          = currentWeekId,
                defenseLogs     = arena._settledDefenseLogs,
                battleHistory   = arena.battleHistory or {},
                globalRankings  = globalRankings,
                globalMyRank    = globalMyRank,
                shopPurchased   = arena.shopPurchased or {},
                reachedTiers    = arena.reachedTiers  or {},
                claimedTiers    = arena.claimedTiers  or {},
            }
            if includeWeekSettlement then
                result.weekSettlement = arena._weekSettlement
            end
            callback(result)
            arena._weekSettlement = nil
            arena._settledDefenseLogs = nil
        end)
    end

    -- 快速路径: 已有分组且是本周
    if arena.groupId and arena.weekId == currentWeekId then
        -- 同步防守阵容
        if defenseSnapshot then
            local defCommit = serverCloud:BatchCommit("arena_def_enter_" .. tostring(uid))
            defCommit:ScoreSet(uid, ck("DEFENSE", uid), defenseSnapshot)
            defCommit:Commit({
                ok = function()
                    print("[Arena] defense re-synced uid=" .. tostring(uid))
                end,
                error = function(code)
                    print("[Arena] defense re-sync error uid=" .. tostring(uid))
                end,
            })
        end

        -- 每次进入时同步全服排行榜分数（确保头像变更等及时反映）
        local avatarId = getAvatarHeroId(uid)
        local encodedScore = (arena.rankScore or 0) * 100 + avatarId
        serverCloud:SetInt(uid, ck("RANK_SCORE", uid), encodedScore)
        writeRankName(uid, ck("RANK_SCORE", uid))

        settleDefenseLogs(uid, arena, function()
            local groupKey = getGroupKey(uid, arena.weekId, arena.groupId)
            serverCloud.list:Get(ArenaConfig.PUBLIC_UID, groupKey, {
                ok = function(members)
                    local rawMembers = members or {}

                    local rankings = buildRankings(rawMembers)
                    fillRankingsWithAI(rankings, arena.groupId, arena.rankScore)
                    local myRank, myEntry = findRank(rankings, uid)

                    -- 修复: 更新小组列表中自己的 name/power/weekScore
                    if myEntry then
                        local player = PDM.GetModule(uid, "player")
                        local curName  = (player and player.name and player.name ~= "") and player.name or "玩家"
                        local curPower = computeAndSyncPower(uid)
                        local curScore = arena.weekScore or ArenaConfig.WEEK_SCORE_INIT
                        local curAvatarId = player and player.avatarHeroId or 1
                        local needSync = (myEntry.name ~= curName)
                            or (myEntry.power ~= curPower)
                            or (myEntry.weekScore ~= curScore)
                            or (myEntry.avatarHeroId ~= curAvatarId)

                        if needSync then
                            myEntry.name         = curName
                            myEntry.power        = curPower
                            myEntry.weekScore    = curScore
                            myEntry.avatarHeroId = curAvatarId
                            if myEntry.listId then
                                local syncCommit = serverCloud:BatchCommit("arena_entry_sync_" .. tostring(uid))
                                syncCommit:ListModify(myEntry.listId, {
                                    uid          = uid,
                                    name         = curName,
                                    weekScore    = curScore,
                                    power        = curPower,
                                    joinTime     = myEntry.joinTime,
                                    avatarHeroId = curAvatarId,
                                })
                                syncCommit:Commit({
                                    ok = function()
                                        print("[Arena] entry synced uid=" .. tostring(uid)
                                            .. " name=" .. curName .. " power=" .. tostring(curPower))
                                    end,
                                    error = function(code)
                                        print("[Arena] entry sync error uid=" .. tostring(uid)
                                            .. " code=" .. tostring(code))
                                    end,
                                })
                            else
                                print("[Arena][WARN] listId is nil, cannot ListModify for uid=" .. tostring(uid))
                            end
                            -- 重新排序
                            table.sort(rankings, function(a, b)
                                if a.weekScore ~= b.weekScore then
                                    return a.weekScore > b.weekScore
                                end
                                return a.joinTime < b.joinTime
                            end)
                            for i, r in ipairs(rankings) do r.rank = i end
                            myRank = findRank(rankings, uid)
                        end
                    else
                        print("[Arena][WARN] findRank could not find uid=" .. tostring(uid) .. " in rankings!"
                            .. " — clearing groupId to re-allocate")
                        arena.groupId = nil
                        PDM.MarkDirty(uid, "arena")

                        allocateGroup(uid, arena, defenseSnapshot, function(newRankings)
                            buildResponse(newRankings, false)
                        end)
                        return
                    end

                    buildResponse(rankings, false)
                end,
                error = function(code)
                    callback({ success = false, reason = "读取小组数据失败" })
                end,
            })
        end)
        return
    end

    -- 完整流程: 周结算 → 分组 → 结算防守日志 → 返回
    lazySettlement(uid, arena, currentWeekId, function()
        allocateGroup(uid, arena, defenseSnapshot, function(rankings)
            settleDefenseLogs(uid, arena, function()
                buildResponse(rankings, true)
            end)
        end)
    end)
end

--- 获取对手防守阵容（异步）
---@param uid number
---@param targetUid number
---@param callback function(result: table)
function ArenaService.GetOpponent(uid, targetUid, callback)
    local arena = PDM.GetModule(uid, "arena")
    if not arena then
        callback({ success = false, reason = "数据未加载" })
        return
    end

    resetDailyTickets(arena)
    if getRemainingTickets(arena, uid) <= 0 then
        callback({ success = false, reason = "竞技券不足" })
        return
    end

    -- 消耗优先级: currency.arenaTicket > 每日免费额度
    local currency = PDM.GetModule(uid, "currency")
    if currency and (currency.arenaTicket or 0) > 0 then
        currency.arenaTicket = currency.arenaTicket - 1
        PDM.MarkDirty(uid, "currency")
    else
        arena.ticketsUsedToday = (arena.ticketsUsedToday or 0) + 1
    end
    PDM.MarkDirty(uid, "arena")

    -- AI 对手
    if ArenaConfig.isAIPlayer(targetUid) then
        local defense = ArenaAITemplates.generateDefenseByScore(arena.rankScore or 0)
        callback({
            success   = true,
            targetUid = targetUid,
            defense   = defense,
            tickets   = getRemainingTickets(arena, uid),
        })
        return
    end

    -- 真实对手
    serverCloud:Get(targetUid, ck("DEFENSE", uid), {
        ok = function(scores)
            local rawScores = scores or {}
            local defense = rawScores[ck("DEFENSE", uid)]
            if type(defense) ~= "table" or not defense.heroes then
                callback({ success = false, reason = "对手尚未设置防守阵容" })
                return
            end
            callback({
                success   = true,
                targetUid = targetUid,
                defense   = defense,
                tickets   = getRemainingTickets(arena, uid),
            })
        end,
        error = function(code, reason)
            callback({ success = false, reason = "读取对手数据失败" })
        end,
    })
end

--- 提交战斗结果（异步）
---@param uid number
---@param targetUid number
---@param isWin boolean
---@param callback function(result: table)
function ArenaService.BattleResult(uid, targetUid, isWin, callback)
    local arena = PDM.GetModule(uid, "arena")
    if not arena or not arena.groupId then
        callback({ success = false, reason = "未在竞技场中" })
        return
    end

    local groupKey = getGroupKey(uid, arena.weekId, arena.groupId)
    serverCloud.list:Get(ArenaConfig.PUBLIC_UID, groupKey, {
        ok = function(members)
            local rankings = buildRankings(members or {})
            fillRankingsWithAI(rankings, arena.groupId, arena.rankScore)
            local myRank, myEntry = findRank(rankings, uid)
            local oppRank, oppEntry = findRank(rankings, targetUid)

            if not oppEntry then
                callback({ success = false, reason = "对手不在同一小组中" })
                return
            end

            local rankDiff = myRank - oppRank
            local rule = ArenaConfig.getAttackScoring(rankDiff)

            local scoreChange, coinReward
            if isWin then
                scoreChange = rule.winScore
                coinReward  = rule.winCoin
                arena.totalWins = (arena.totalWins or 0) + 1
            else
                scoreChange = rule.loseScore
                coinReward  = rule.loseCoin
                arena.totalLosses = (arena.totalLosses or 0) + 1
            end

            arena.weekScore = math.max(0, (arena.weekScore or ArenaConfig.WEEK_SCORE_INIT) + scoreChange)
            PDM.MarkDirty(uid, "arena")

            local currency = PDM.GetModule(uid, "currency")
            if currency and coinReward > 0 then
                currency.arenaCoin = (currency.arenaCoin or 0) + coinReward
                PDM.MarkDirty(uid, "currency")
            end

            local commit = serverCloud:BatchCommit("arena_result_" .. tostring(uid))
            if myEntry and myEntry.listId then
                local player = PDM.GetModule(uid, "player")
                local curPower = computeAndSyncPower(uid)
                commit:ListModify(myEntry.listId, {
                    uid       = uid,
                    name      = (player and player.name and player.name ~= "") and player.name or myEntry.name,
                    weekScore = arena.weekScore,
                    power     = curPower,
                    joinTime  = myEntry.joinTime,
                })
            end

            if not ArenaConfig.isAIPlayer(targetUid) then
                local player = PDM.GetModule(uid, "player")
                local defScoreChange = isWin
                    and ArenaConfig.DEFENSE_LOSE_SCORE
                    or  ArenaConfig.DEFENSE_WIN_SCORE
                -- 立即更新对手的 GROUP list 条目，让排行榜实时反映分数变化
                -- DEFENSE_LOG 保留用于对手下次登录时同步 PDM，两者数值最终一致不会重复计算
                if oppEntry and oppEntry.listId then
                    local newOppScore = math.max(0, (oppEntry.weekScore or ArenaConfig.WEEK_SCORE_INIT) + defScoreChange)
                    commit:ListModify(oppEntry.listId, {
                        uid          = targetUid,
                        name         = oppEntry.name,
                        weekScore    = newOppScore,
                        power        = oppEntry.power,
                        joinTime     = oppEntry.joinTime,
                        avatarHeroId = oppEntry.avatarHeroId,
                    })
                end
                commit:ListAdd(targetUid, ck("DEFENSE_LOG", uid), {
                    attackerUid  = uid,
                    attackerName = (player and player.name and player.name ~= "") and player.name or "未知",
                    result       = isWin and "lose" or "win",
                    scoreChange  = defScoreChange,
                    timestamp    = os.time(),
                })
            end
            -- AI 对手仅存在于内存排名中（fillRankingsWithAI），无持久化记录，无需 ListModify

            commit:Commit({
                ok = function()
                    print("[Arena] battle result committed uid=" .. tostring(uid)
                        .. " vs=" .. tostring(targetUid)
                        .. " win=" .. tostring(isWin)
                        .. " scoreChange=" .. scoreChange)
                    appendBattleHistory(uid, arena, {
                        type         = "attack",
                        opponentName = oppEntry.name or "未知",
                        result       = isWin and "win" or "lose",
                        scoreChange  = scoreChange,
                        timestamp    = os.time(),
                    })
                    TaskService.UpdateProgress(uid, "arena", 1)
                    TaskService.RefreshAchievements(uid)
                end,
                error = function(code, reason)
                    print("[Arena] battle result commit error uid=" .. tostring(uid)
                        .. " code=" .. tostring(code))
                end,
            })

            callback({
                success      = true,
                isWin        = isWin,
                scoreChange  = scoreChange,
                coinReward   = coinReward,
                weekScore    = arena.weekScore,
                myRank       = myRank,
                oppRank      = oppRank,
                rankDiff     = rankDiff,
                tickets      = getRemainingTickets(arena, uid),
            })
        end,
        error = function(code, reason)
            callback({ success = false, reason = "读取排名数据失败" })
        end,
    })
end

--- 获取防守记录（异步）
---@param uid number
---@param callback function(result: table)
function ArenaService.GetLog(uid, callback)
    local arena = PDM.GetModule(uid, "arena")
    if not arena then
        callback({ success = false, reason = "数据未加载" })
        return
    end

    serverCloud.list:Get(uid, ck("DEFENSE_LOG", uid), {
        ok = function(items)
            if not items or #items == 0 then
                callback({ success = true, logs = {}, totalChange = 0 })
                return
            end

            local logs = {}
            local totalChange = 0
            for _, item in ipairs(items) do
                local v = item.value or item
                local sc = tonumber(v.scoreChange) or 0
                totalChange = totalChange + sc
                logs[#logs + 1] = {
                    attackerName = v.attackerName or "未知",
                    result       = v.result,
                    scoreChange  = sc,
                    timestamp    = v.timestamp,
                }
            end

            local commit = serverCloud:BatchCommit("settle_log_manual_" .. tostring(uid))
            for _, item in ipairs(items) do
                if item.list_id then
                    commit:ListDelete(item.list_id)
                end
            end
            commit:Commit({
                ok = function()
                    arena.weekScore = math.max(0, (arena.weekScore or ArenaConfig.WEEK_SCORE_INIT) + totalChange)
                    PDM.MarkDirty(uid, "arena")
                    print("[Arena] manual settle " .. #items .. " logs uid=" .. tostring(uid))

                    callback({
                        success     = true,
                        logs        = logs,
                        totalChange = totalChange,
                        weekScore   = arena.weekScore,
                    })
                end,
                error = function(code)
                    print("[Arena][WARN] manual settle delete failed uid=" .. tostring(uid)
                        .. " — scoreChange NOT applied")
                    callback({
                        success     = true,
                        logs        = logs,
                        totalChange = 0,
                        weekScore   = arena.weekScore or ArenaConfig.WEEK_SCORE_INIT,
                        settleError = true,
                    })
                end,
            })
        end,
        error = function(code, reason)
            callback({ success = false, reason = "读取防守记录失败" })
        end,
    })
end

--- 竞技场商店购买（同步）
---@param uid number
---@param itemId number
---@return table result
function ArenaService.ShopBuy(uid, itemId, quantity)
    quantity = math.max(1, quantity or 1)

    local item = ArenaConfig.getShopItem(itemId)
    if not item then
        return { success = false, reason = "商品不存在" }
    end

    local arena = PDM.GetModule(uid, "arena")
    if not arena then
        return { success = false, reason = "数据未加载" }
    end

    local currency = PDM.GetModule(uid, "currency")
    if not currency then
        return { success = false, reason = "数据未加载" }
    end

    -- 周重置商店购买记录
    local currentWeekId = ArenaConfig.calcWeekId()
    resetShopWeekly(arena, currentWeekId, uid)

    -- 检查购买次数限制
    local purchased = arena.shopPurchased or {}
    local alreadyBought = purchased[itemId] or 0
    local remaining = item.limitCount - alreadyBought
    if remaining <= 0 then
        return { success = false, reason = "已达购买上限" }
    end
    -- 数量不能超过剩余可购买次数
    if quantity > remaining then
        quantity = remaining
    end

    -- 检查竞技币余额
    local totalPrice = item.price * quantity
    if (currency.arenaCoin or 0) < totalPrice then
        return { success = false, reason = "竞技币不足" }
    end

    -- 扣除竞技币
    currency.arenaCoin = currency.arenaCoin - totalPrice

    -- 发放奖励（按 quantity 倍数）
    local rewardDetail = nil  -- 额外奖励信息（用于客户端展示）
    if item.rewardType == "random_scroll" then
        -- 随机卷轴：每个独立随机类型，按类型聚合后加到 currency
        local SCROLL_TYPES = { "weaponScroll", "offhandScroll", "armorScroll", "accessoryScroll" }
        local perBuy = item.rewardCount or 1
        local totalCount = perBuy * quantity
        local scrolls = {}
        for i = 1, totalCount do
            local st = SCROLL_TYPES[math.random(1, #SCROLL_TYPES)]
            scrolls[st] = (scrolls[st] or 0) + 1
        end
        for st, n in pairs(scrolls) do
            currency[st] = (currency[st] or 0) + n
        end
        rewardDetail = { scrolls = scrolls }
        local parts = {}
        for st, n in pairs(scrolls) do parts[#parts + 1] = st .. "x" .. n end
        print("[Arena] random_scroll → " .. table.concat(parts, ", "))
    elseif item.rewardType == "shard" then
        -- 碎片：加到 heroes.roster[heroId].shards
        local heroes = PDM.GetModule(uid, "heroes")
        if heroes then
            local heroId = item.rewardHeroId
            if not heroes.roster then heroes.roster = {} end
            if not heroes.roster[heroId] then
                heroes.roster[heroId] = { shards = 0, _shardMigrated = true }
            end
            local perBuy = item.rewardCount or 1
            local totalCount = perBuy * quantity
            heroes.roster[heroId].shards = (heroes.roster[heroId].shards or 0) + totalCount
            PDM.MarkDirty(uid, "heroes")
            rewardDetail = { heroId = heroId, shardAmount = totalCount }
            print("[Arena] shard → heroId=" .. heroId .. " x" .. totalCount)
        end
    else
        local field = item.rewardType
        local perBuy = item.rewardCount or 1
        local totalCount = perBuy * quantity
        currency[field] = (currency[field] or 0) + totalCount
    end
    PDM.MarkDirty(uid, "currency")

    -- 更新购买记录
    if not arena.shopPurchased then arena.shopPurchased = {} end
    arena.shopPurchased[itemId] = alreadyBought + quantity
    PDM.MarkDirty(uid, "arena")

    print("[Arena] shop buy uid=" .. tostring(uid) .. " itemId=" .. tostring(itemId)
        .. " qty=" .. quantity .. " price=" .. totalPrice .. " remaining=" .. tostring(currency.arenaCoin))

    return {
        success       = true,
        itemId        = itemId,
        quantity      = quantity,
        purchased     = arena.shopPurchased[itemId],
        arenaCoin     = currency.arenaCoin,
        shopPurchased = arena.shopPurchased,
        rewardDetail  = rewardDetail,
    }
end

-- ============================================================================
-- ClaimTierReward - 手动领取段位首通奖励
-- 条件：玩家已到达该段位（reachedTiers[tierId] == true）且未领取（claimedTiers[tierId] 为空）
-- ============================================================================
function ArenaService.ClaimTierReward(uid, tierId, callback)
    tierId = tonumber(tierId)
    if not tierId then
        callback({ success = false, reason = "参数错误" })
        return
    end

    local arena = PDM.GetModule(uid, "arena")
    if not arena then
        callback({ success = false, reason = "数据未加载" })
        return
    end

    -- 确保字段存在（兼容老存档）
    if not arena.reachedTiers  then arena.reachedTiers  = {} end
    if not arena.claimedTiers  then arena.claimedTiers  = {} end

    -- 校验：必须曾经到达该段位
    -- 修复：rankScore >= scoreMin 即视为已达到（覆盖初始段位及周结算前的空窗期）
    if not arena.reachedTiers[tierId] then
        local tierDef2 = nil
        for _, t in ipairs(ArenaConfig.TIERS) do
            if t.id == tierId then tierDef2 = t; break end
        end
        if tierDef2 and (arena.rankScore or 0) >= tierDef2.scoreMin then
            -- 数据补录：当前分数已达到该段位，补标 reachedTiers
            arena.reachedTiers[tierId] = true
            PDM.MarkDirty(uid, "arena")
            print("[Arena] ClaimTierReward 补录 reachedTiers uid=" .. tostring(uid)
                .. " tierId=" .. tostring(tierId))
        else
            callback({ success = false, reason = "尚未达到该段位" })
            return
        end
    end

    -- 校验：不能重复领取
    if arena.claimedTiers[tierId] then
        callback({ success = false, reason = "已领取" })
        return
    end

    -- 查找配置
    local tierDef = nil
    for _, t in ipairs(ArenaConfig.TIERS) do
        if t.id == tierId then tierDef = t; break end
    end
    if not tierDef then
        callback({ success = false, reason = "段位配置不存在" })
        return
    end

    local diamond = tierDef.firstRewardDiamond or 0
    if diamond <= 0 then
        -- 无钻石奖励的段位也可以标记为已领取
        arena.claimedTiers[tierId] = true
        PDM.MarkDirty(uid, "arena")
        callback({ success = true, tierId = tierId, diamond = 0, claimedTiers = arena.claimedTiers })
        return
    end

    local currency = PDM.GetModule(uid, "currency")
    if not currency then
        callback({ success = false, reason = "数据未加载" })
        return
    end

    -- 发放钻石
    currency.gems = (currency.gems or 0) + diamond
    PDM.MarkDirty(uid, "currency")

    -- 标记已领取
    arena.claimedTiers[tierId] = true
    PDM.MarkDirty(uid, "arena")

    print("[Arena] ClaimTierReward uid=" .. tostring(uid)
        .. " tierId=" .. tostring(tierId)
        .. " diamond=" .. tostring(diamond)
        .. " gems=" .. tostring(currency.gems))

    callback({
        success      = true,
        tierId       = tierId,
        diamond      = diamond,
        gems         = currency.gems,
        claimedTiers = arena.claimedTiers,
    })
end

-- ============================================================================
-- SettleOnLogin - 登录时触发周结算（仅发放邮件，不分组）
-- 目的：确保周一首次登录即可在邮件列表中看到结算奖励
-- ============================================================================
function ArenaService.SettleOnLogin(uid, callback)
    local arena = PDM.GetModule(uid, "arena")
    if not arena then
        callback()
        return
    end

    local currentWeekId = ArenaConfig.calcWeekId()
    local lastWeekId = arena.lastSettleWeekId or 0

    -- 无需结算：从未参加过竞技场，或本周已结算
    if lastWeekId == 0 or currentWeekId <= lastWeekId then
        callback()
        return
    end

    -- 需要结算：复用 lazySettlement 逻辑
    lazySettlement(uid, arena, currentWeekId, function()
        callback()
    end)
end

return ArenaService
