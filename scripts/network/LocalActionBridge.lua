-- ============================================================================
-- LocalActionBridge - 单机把 Client.sendAction 接到服务端 Handler
-- 无服务器连接时：PDM 与 ClientDispatcher 共用同一份模块表，走现有 Service。
-- ============================================================================

local Protocol         = require("shared.Protocol")
local CharacterSchema  = require("shared.schemas.CharacterSchema")
local ClientDispatcher = require("network.ClientDispatcher")
local PDM              = require("server.character.PlayerDataManager")
local GameState        = require("core.GameState")
local ServerDispatcher = require("network.ServerDispatcher")

local M = {}

local LOCAL_UID = 1
local inited_ = false
local handlers_ = {}
local pdmAttached_ = false
local arenaRankings_ = nil
local arenaMyRank_ = 1

local function registerHandlers(handlers)
    if type(handlers) ~= "table" then return end
    for action, fn in pairs(handlers) do
        if action ~= "__cleanup" and type(fn) == "function" then
            handlers_[action] = fn
        end
    end
end

local function loadHandlers()
    handlers_ = {}
    local packs = {
        { "server.battle.BattleHandler", "actionHandlers" },
        { "server.hero.HeroHandler", "actionHandlers" },
        { "server.gacha.GachaHandler", "actionHandlers" },
        { "server.equipment.EquipmentHandler", "actionHandlers" },
        { "server.blacksmith.BlacksmithHandler", "actionHandlers" },
        { "server.arena.ArenaHandler", "actionHandlers" },
        { "server.task.TaskHandler", "actionHandlers" },
        { "server.mail.MailHandler", "actionHandlers" },
        { "server.redeem.RedeemHandler", nil },
        { "server.awakening.AwakeningHandler", nil },
        { "server.advancement.AdvancementHandler", nil },
        { "server.talent.TalentHandler", nil },
        { "server.signin.SignInHandler", nil },
        { "server.gm.GMHandler", "actionHandlers" },
        { "server.market.MarketHandler", nil },
        { "server.loot.LootHandler", nil },
        { "server.guild.GuildHandler", "actionHandlers" },
        { "server.sweep.SweepHandler", "actionHandlers" },
        { "server.relic.RelicHandler", "actionHandlers" },
        { "server.artifact.ArtifactHandler", "actionHandlers" },
        { "server.dungeon.DungeonHandler", "actionHandlers" },
        { "server.offline.OfflineHandler", "actionHandlers" },
        { "server.tower.TowerHandler", "actionHandlers" },
    }
    for _, pack in ipairs(packs) do
        local ok, mod = pcall(require, pack[1])
        if ok and mod then
            if pack[2] then
                registerHandlers(mod[pack[2]])
            else
                registerHandlers(mod)
            end
        else
            print("[LocalActionBridge] skip " .. pack[1] .. ": " .. tostring(mod))
        end
    end
    local n = 0
    for _ in pairs(handlers_) do n = n + 1 end
    print("[LocalActionBridge] handlers loaded: " .. n)
end

local function defaultFromSchema(fieldKey)
    local def = CharacterSchema.Fields[fieldKey]
    if def and def.getDefault then
        local ok, data = pcall(def.getDefault)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}
end

local function defaultCurrency()
    local data = defaultFromSchema("currency")
    data.gold = GameState.getGold()
    data.gems = GameState.getGems()
    data.essence = GameState.getEssence()
    data.enhanceStone = GameState.getEnhanceStone()
    data.degradeStone = GameState.getDegradeStone()
    data.destroyStone = GameState.getDestroyStone()
    data.weaponScroll = GameState.getWeaponScroll()
    data.offhandScroll = GameState.getOffhandScroll()
    data.armorScroll = GameState.getArmorScroll()
    data.accessoryScroll = GameState.getAccessoryScroll()
    data.recruitTicket = GameState.getRecruitTicket()
    data.stellarRecruitTicket = GameState.getStellarRecruitTicket()
    data.goldenKey = GameState.getGoldenKey()
    data.sweepTicket = GameState.getSweepTicket()
    data.arenaTicket = GameState.getArenaTicket()
    data.arenaCoin = GameState.getArenaCoin()
    data.tavernCoin = GameState.getTavernCoin()
    data.arcaneDust = GameState.getArcaneDust()
    data.corruptStone = GameState.getCorruptStone()
    data.sacredStone = GameState.getSacredStone()
    data.speedCardExpireAt = GameState.getSpeedCardExpireAt()
    return data
end

local function defaultPlayer()
    local data = defaultFromSchema("player")
    data.name = GameState.getName()
    data.level = GameState.getLevel()
    data.exp = GameState.getExp()
    data.maxExp = GameState.getMaxExp()
    data.power = GameState.getPower()
    return data
end

local function defaultQuotas()
    local QuotaConsts = require("shared.quota.QuotaConsts")
    local quotas = {}
    for _, def in ipairs(QuotaConsts.GetAllKeys()) do
        quotas[def.key] = { value = 0, limit = def.limit }
    end
    return quotas
end

local function ensureModule(name, fallback)
    local data = ClientDispatcher.get(name)
    if data then return data end
    if type(fallback) == "function" then
        data = fallback()
    else
        data = fallback
    end
    if data then
        ClientDispatcher.set(name, data)
    end
    return data
end

local function syncCurrencyIntoPdm()
    local cur = ClientDispatcher.get("currency")
    if not cur then
        cur = defaultCurrency()
        ClientDispatcher.set("currency", cur)
        return
    end
    cur.gold = GameState.getGold()
    cur.gems = GameState.getGems()
    cur.essence = GameState.getEssence()
    cur.enhanceStone = GameState.getEnhanceStone()
    cur.degradeStone = GameState.getDegradeStone()
    cur.destroyStone = GameState.getDestroyStone()
    cur.weaponScroll = GameState.getWeaponScroll()
    cur.offhandScroll = GameState.getOffhandScroll()
    cur.armorScroll = GameState.getArmorScroll()
    cur.accessoryScroll = GameState.getAccessoryScroll()
    cur.recruitTicket = GameState.getRecruitTicket()
    cur.stellarRecruitTicket = GameState.getStellarRecruitTicket()
    cur.goldenKey = GameState.getGoldenKey()
    cur.sweepTicket = GameState.getSweepTicket()
    cur.arenaTicket = GameState.getArenaTicket()
    cur.arenaCoin = GameState.getArenaCoin()
    cur.tavernCoin = GameState.getTavernCoin()
    cur.arcaneDust = GameState.getArcaneDust()
    cur.corruptStone = GameState.getCorruptStone()
    cur.sacredStone = GameState.getSacredStone()
    cur.speedCardExpireAt = GameState.getSpeedCardExpireAt()
end

local function deliverActionResult(result)
    if type(result) ~= "table" then return end
    local okMsg, Msg = pcall(require, "network.ClientMessageHandler")
    if okMsg and Msg and Msg.handleActionResult then
        pcall(Msg.handleActionResult, result)
    end
end

local function remainingArenaTickets(arena)
    local ArenaConfig = require("config.ArenaConfig")
    local used = arena and arena.ticketsUsedToday or 0
    local remaining = math.max(0, ArenaConfig.TICKET_DAILY_FREE - used)
    local currency = ClientDispatcher.get("currency")
    remaining = remaining + math.max(0, currency and currency.arenaTicket or 0)
    return remaining
end

local function resetDailyTickets(arena)
    local today = math.floor((os.time() + 28800) / 86400)
    if (arena.ticketResetDay or 0) ~= today then
        arena.ticketsUsedToday = 0
        arena.ticketResetDay = today
    end
end

local function buildLocalArenaRankings()
    if arenaRankings_ then return arenaRankings_, arenaMyRank_ end
    local ArenaConfig = require("config.ArenaConfig")
    local ArenaAITemplates = require("config.ArenaAITemplates")
    local CharacterPanel = require("ui.CharacterPanel")
    local arena = ClientDispatcher.get("arena") or defaultFromSchema("arena")
    local player = ClientDispatcher.get("player") or defaultPlayer()
    local myPower = 0
    if CharacterPanel.getTotalPower then
        myPower = CharacterPanel.getTotalPower() or 0
    end
    local rankScore = arena.rankScore or 0
    local weekScore = arena.weekScore or ArenaConfig.WEEK_SCORE_INIT
    local groupId = arena.groupId or 1
    local rankings = {
        {
            uid = LOCAL_UID,
            name = player.name or GameState.getName() or "玩家",
            weekScore = weekScore,
            power = myPower,
            listId = nil,
            joinTime = 0,
            avatarHeroId = player.avatarHeroId or 1,
            rankScore = rankScore,
        },
    }
    local names = ArenaConfig.AI_NAMES
    for i = 1, ArenaConfig.GROUP_SIZE - 1 do
        local aiSeed = groupId * 1000 + i
        local nameIdx = ((groupId + i - 1) % #names) + 1
        rankings[#rankings + 1] = {
            uid = -aiSeed,
            name = names[nameIdx],
            weekScore = ArenaConfig.WEEK_SCORE_INIT,
            power = ArenaAITemplates.deterministicPowerByScore(rankScore, aiSeed),
            listId = nil,
            joinTime = i,
            avatarHeroId = (aiSeed % 15) + 1,
            rankScore = rankScore,
        }
    end
    table.sort(rankings, function(a, b)
        if a.weekScore ~= b.weekScore then
            return a.weekScore > b.weekScore
        end
        return (a.joinTime or 0) < (b.joinTime or 0)
    end)
    local myRank = 1
    for i, r in ipairs(rankings) do
        r.rank = i
        if r.uid == LOCAL_UID then
            myRank = i
        end
    end
    arenaRankings_ = rankings
    arenaMyRank_ = myRank
    return rankings, myRank
end

local function findArenaEntry(uid)
    local rankings = arenaRankings_ or select(1, buildLocalArenaRankings())
    for i, r in ipairs(rankings) do
        if r.uid == uid then
            return r, i
        end
    end
    return nil, nil
end

local function localArenaEnter()
    local ArenaConfig = require("config.ArenaConfig")
    local arena = ensureModule("arena", function()
        return defaultFromSchema("arena")
    end)
    resetDailyTickets(arena)
    if not arena.groupId then
        arena.groupId = 1
        arena.weekId = ArenaConfig.calcWeekId()
        arena.weekScore = arena.weekScore or ArenaConfig.WEEK_SCORE_INIT
        PDM.MarkDirty(LOCAL_UID, "arena")
    end
    local rankings, myRank = buildLocalArenaRankings()
    local tier = ArenaConfig.getTierByScore(arena.rankScore or 0)
    return {
        success = true,
        action = Protocol.ACTION_TYPES.ARENA_ENTER,
        rankings = rankings,
        myRank = myRank,
        weekScore = arena.weekScore or ArenaConfig.WEEK_SCORE_INIT,
        rankScore = arena.rankScore or 0,
        tier = tier and ArenaConfig.getTierDisplayName(tier) or "黑铁级 V",
        tierId = tier and tier.id or 1,
        tickets = remainingArenaTickets(arena),
        weekId = arena.weekId or ArenaConfig.calcWeekId(),
        defenseLogs = {},
        battleHistory = arena.battleHistory or {},
        globalRankings = rankings,
        globalMyRank = myRank,
        shopPurchased = arena.shopPurchased or {},
        reachedTiers = arena.reachedTiers or {},
        claimedTiers = arena.claimedTiers or {},
    }
end

local function localArenaGetOpponent(params)
    local ArenaConfig = require("config.ArenaConfig")
    local ArenaAITemplates = require("config.ArenaAITemplates")
    local arena = ClientDispatcher.get("arena")
    if not arena then
        return { success = false, reason = "数据未加载", action = Protocol.ACTION_TYPES.ARENA_GET_OPPONENT }
    end
    resetDailyTickets(arena)
    if remainingArenaTickets(arena) <= 0 then
        return { success = false, reason = "竞技券不足", action = Protocol.ACTION_TYPES.ARENA_GET_OPPONENT }
    end
    local targetUid = params and tonumber(params.targetUid)
    if not targetUid then
        return { success = false, reason = "缺少目标玩家", action = Protocol.ACTION_TYPES.ARENA_GET_OPPONENT }
    end
    local currency = ClientDispatcher.get("currency")
    if currency and (currency.arenaTicket or 0) > 0 then
        currency.arenaTicket = currency.arenaTicket - 1
        PDM.MarkDirty(LOCAL_UID, "currency")
    else
        arena.ticketsUsedToday = (arena.ticketsUsedToday or 0) + 1
        PDM.MarkDirty(LOCAL_UID, "arena")
    end
    local defense
    if ArenaConfig.isAIPlayer(targetUid) then
        defense = ArenaAITemplates.generateDefenseByScore(arena.rankScore or 0)
    else
        defense = { heroes = {}, power = 0 }
    end
    return {
        success = true,
        action = Protocol.ACTION_TYPES.ARENA_GET_OPPONENT,
        targetUid = targetUid,
        defense = defense,
        tickets = remainingArenaTickets(arena),
    }
end

local function localArenaBattleResult(params)
    local ArenaConfig = require("config.ArenaConfig")
    local arena = ClientDispatcher.get("arena")
    if not arena then
        return { success = false, reason = "数据未加载", action = Protocol.ACTION_TYPES.ARENA_BATTLE_RESULT }
    end
    local targetUid = params and tonumber(params.targetUid)
    local isWin = params and params.isWin
    if not targetUid or isWin == nil then
        return { success = false, reason = "参数不完整", action = Protocol.ACTION_TYPES.ARENA_BATTLE_RESULT }
    end
    buildLocalArenaRankings()
    local myEntry, myRank = findArenaEntry(LOCAL_UID)
    local oppEntry, oppRank = findArenaEntry(targetUid)
    if not myRank then myRank = arenaMyRank_ or 1 end
    if not oppRank then oppRank = myRank end
    local rankDiff = myRank - oppRank
    local rule = ArenaConfig.getAttackScoring(rankDiff)
    local scoreChange, coinReward
    if isWin then
        scoreChange = rule.winScore
        coinReward = rule.winCoin
        arena.totalWins = (arena.totalWins or 0) + 1
    else
        scoreChange = rule.loseScore
        coinReward = rule.loseCoin
        arena.totalLosses = (arena.totalLosses or 0) + 1
    end
    arena.weekScore = math.max(0, (arena.weekScore or ArenaConfig.WEEK_SCORE_INIT) + scoreChange)
    if myEntry then
        myEntry.weekScore = arena.weekScore
    end
    if oppEntry and ArenaConfig.isAIPlayer(targetUid) then
        local defChange = isWin and ArenaConfig.DEFENSE_LOSE_SCORE or ArenaConfig.DEFENSE_WIN_SCORE
        oppEntry.weekScore = math.max(0, (oppEntry.weekScore or ArenaConfig.WEEK_SCORE_INIT) + defChange)
    end
    if arenaRankings_ then
        table.sort(arenaRankings_, function(a, b)
            if a.weekScore ~= b.weekScore then
                return a.weekScore > b.weekScore
            end
            return (a.joinTime or 0) < (b.joinTime or 0)
        end)
        for i, r in ipairs(arenaRankings_) do
            r.rank = i
            if r.uid == LOCAL_UID then
                arenaMyRank_ = i
                myRank = i
            end
            if r.uid == targetUid then
                oppRank = i
            end
        end
    end
    PDM.MarkDirty(LOCAL_UID, "arena")
    local currency = ClientDispatcher.get("currency")
    if currency and coinReward > 0 then
        currency.arenaCoin = (currency.arenaCoin or 0) + coinReward
        PDM.MarkDirty(LOCAL_UID, "currency")
    end
    if not arena.battleHistory then arena.battleHistory = {} end
    arena.battleHistory[#arena.battleHistory + 1] = {
        type = "attack",
        opponentName = oppEntry and oppEntry.name or "未知",
        result = isWin and "win" or "lose",
        scoreChange = scoreChange,
        timestamp = os.time(),
    }
    local TaskService = require("server.task.TaskService")
    pcall(TaskService.UpdateProgress, LOCAL_UID, "arena", 1)
    pcall(TaskService.RefreshAchievements, LOCAL_UID)
    return {
        success = true,
        action = Protocol.ACTION_TYPES.ARENA_BATTLE_RESULT,
        isWin = isWin,
        scoreChange = scoreChange,
        coinReward = coinReward,
        weekScore = arena.weekScore,
        myRank = myRank,
        oppRank = oppRank,
        rankDiff = rankDiff,
        tickets = remainingArenaTickets(arena),
    }
end

local function localArenaGetLog()
    return {
        success = true,
        action = Protocol.ACTION_TYPES.ARENA_GET_LOG,
        logs = {},
        totalChange = 0,
    }
end

local function localArenaClaimTier(params)
    local ArenaConfig = require("config.ArenaConfig")
    local arena = ClientDispatcher.get("arena")
    if not arena then
        return { success = false, reason = "数据未加载", action = Protocol.ACTION_TYPES.ARENA_CLAIM_TIER }
    end
    local tierId = params and tonumber(params.tierId)
    if not tierId then
        return { success = false, reason = "缺少段位ID", action = Protocol.ACTION_TYPES.ARENA_CLAIM_TIER }
    end
    if not arena.reachedTiers then arena.reachedTiers = {} end
    if not arena.claimedTiers then arena.claimedTiers = {} end
    local tierDef
    for _, t in ipairs(ArenaConfig.TIERS) do
        if t.id == tierId then tierDef = t; break end
    end
    if not arena.reachedTiers[tierId] then
        if tierDef and (arena.rankScore or 0) >= (tierDef.scoreMin or 0) then
            arena.reachedTiers[tierId] = true
        else
            return { success = false, reason = "尚未达到该段位", action = Protocol.ACTION_TYPES.ARENA_CLAIM_TIER }
        end
    end
    if arena.claimedTiers[tierId] then
        return { success = false, reason = "已领取", action = Protocol.ACTION_TYPES.ARENA_CLAIM_TIER }
    end
    if not tierDef then
        return { success = false, reason = "段位配置不存在", action = Protocol.ACTION_TYPES.ARENA_CLAIM_TIER }
    end
    local diamond = tierDef.firstRewardDiamond or 0
    local currency = ClientDispatcher.get("currency")
    if diamond > 0 then
        if not currency then
            return { success = false, reason = "数据未加载", action = Protocol.ACTION_TYPES.ARENA_CLAIM_TIER }
        end
        currency.gems = (currency.gems or 0) + diamond
        PDM.MarkDirty(LOCAL_UID, "currency")
    end
    arena.claimedTiers[tierId] = true
    PDM.MarkDirty(LOCAL_UID, "arena")
    return {
        success = true,
        action = Protocol.ACTION_TYPES.ARENA_CLAIM_TIER,
        tierId = tierId,
        diamond = diamond,
        gems = currency and currency.gems,
        claimedTiers = arena.claimedTiers,
    }
end

local function localGuildEnter()
    local player = ClientDispatcher.get("player") or defaultPlayer()
    local battle = ClientDispatcher.get("battle") or {}
    local StageConfig = require("config.StageConfig")
    local stageId = tonumber(battle.maxStageId) or 101
    local progressName = tostring(stageId)
    if StageConfig.formatProgressDisplay then
        progressName = StageConfig.formatProgressDisplay(stageId) or progressName
    end
    local my = {
        uid = LOCAL_UID,
        name = player.name or GameState.getName() or "玩家",
        stageId = stageId,
        progress = progressName,
        avatarHeroId = player.avatarHeroId or 1,
        avatarFrameId = player.avatarFrameId or 1,
        rank = 1,
    }
    return {
        success = true,
        action = Protocol.ACTION_TYPES.GUILD_ENTER,
        rankData = { my },
        myRankData = my,
    }
end

local function tryLocalCloudFallback(action, params)
    local AT = Protocol.ACTION_TYPES
    if action == AT.ARENA_ENTER then
        return localArenaEnter()
    elseif action == AT.ARENA_GET_OPPONENT then
        return localArenaGetOpponent(params)
    elseif action == AT.ARENA_BATTLE_RESULT then
        return localArenaBattleResult(params)
    elseif action == AT.ARENA_GET_LOG then
        return localArenaGetLog()
    elseif action == AT.ARENA_CLAIM_TIER then
        return localArenaClaimTier(params)
    elseif action == AT.GUILD_ENTER then
        return localGuildEnter()
    end
    return nil
end

local function attachPdm()
    if pdmAttached_ then
        return
    end
    PDM.Setup({
        serverDispatcher = {
            pushModule = function(_uid, fieldKey, moduleData)
                if fieldKey and moduleData then
                    ClientDispatcher.set(fieldKey, moduleData)
                    if fieldKey == "currency" then
                        GameState.syncFromCurrency(moduleData)
                    elseif fieldKey == "player" then
                        GameState.syncPlayerData(moduleData)
                    end
                end
            end,
            pushFullState = function() end,
        },
    })
    ServerDispatcher.setLocalEventSink(function(_uid, eventName, payload)
        if type(payload) ~= "table" then return end
        if eventName == Protocol.RES_ACTION_RESULT then
            deliverActionResult(payload)
        elseif eventName == Protocol.RES_STATE_UPDATE and payload.modules then
            for name, data in pairs(payload.modules) do
                ClientDispatcher.set(name, data)
            end
        end
    end)
    pcall(function()
        require("server.SaveManager").setServerId(LOCAL_UID, 1)
    end)
    PDM.AttachLocalModules(LOCAL_UID, ClientDispatcher.getAll(), 1)
    pdmAttached_ = true
end

local function hookGmAuth()
    local ok, GMHandler = pcall(require, "server.gm.GMHandler")
    if not ok or not GMHandler then return end
    GMHandler.RequireAuth = function(_uid)
        return true
    end
    GMHandler.IsGM = function(_uid)
        return true
    end
end

function M.init()
    if inited_ then
        attachPdm()
        return
    end
    inited_ = true
    loadHandlers()
    hookGmAuth()
    pcall(function()
        require("server.redeem.RedeemService").Init()
    end)

    ensureModule("equipment", function()
        return defaultFromSchema("equipment")
    end)
    ensureModule("lootbox", function()
        return defaultFromSchema("lootbox")
    end)
    ensureModule("heroes", function()
        local data = defaultFromSchema("heroes")
        if not data.roster or not next(data.roster) then
            data.roster = { [1] = { level = 1, exp = 0, shards = 0 } }
            data.deployed = { 1 }
        end
        return data
    end)
    ensureModule("player", defaultPlayer)
    ensureModule("currency", defaultCurrency)
    ensureModule("session", function()
        local data = defaultFromSchema("session")
        local now = os.time()
        if (data.firstLoginTime or 0) == 0 then data.firstLoginTime = now end
        if (data.lastOnlineTime or 0) == 0 then data.lastOnlineTime = now end
        return data
    end)
    do
        local session = ClientDispatcher.get("session")
        if session then
            local now = os.time()
            if (session.firstLoginTime or 0) == 0 then session.firstLoginTime = now end
            if (session.lastOnlineTime or 0) == 0 then session.lastOnlineTime = now end
        end
    end
    ensureModule("talents", function()
        return defaultFromSchema("talents")
    end)
    ensureModule("mod_relics", function()
        return defaultFromSchema("mod_relics")
    end)
    ensureModule("artifacts", function()
        return defaultFromSchema("artifacts")
    end)
    ensureModule("slotEnhance", function()
        return defaultFromSchema("slotEnhance")
    end)
    ensureModule("battle", function()
        return defaultFromSchema("battle")
    end)
    ensureModule("arena", function()
        return defaultFromSchema("arena")
    end)
    ensureModule("task", function()
        return defaultFromSchema("task")
    end)
    ensureModule("mail", function()
        return defaultFromSchema("mail")
    end)
    ensureModule("redeem", function()
        return defaultFromSchema("redeem")
    end)
    ensureModule("signin", function()
        return defaultFromSchema("signin")
    end)
    ensureModule("market", function()
        return defaultFromSchema("market")
    end)
    ensureModule("tavern", function()
        return defaultFromSchema("tavern")
    end)
    ensureModule("dungeon", function()
        return defaultFromSchema("dungeon")
    end)
    ensureModule("challenger", function()
        return defaultFromSchema("challenger")
    end)
    ensureModule("global_profile", function()
        return defaultFromSchema("global_profile")
    end)
    ensureModule("quotas", defaultQuotas)

    attachPdm()
    print("[LocalActionBridge] init uid=" .. LOCAL_UID)
end

---@param action string
---@param params table|nil
---@return boolean handled
function M.dispatch(action, params)
    if not inited_ then
        M.init()
    end
    params = params or {}
    local handler = handlers_[action]
    if not handler then
        local fallback = tryLocalCloudFallback(action, params)
        if fallback then
            deliverActionResult(fallback)
            print("[LocalActionBridge] fallback action=" .. tostring(action)
                .. " success=" .. tostring(fallback.success))
            return true
        end
        print("[LocalActionBridge] no handler action=" .. tostring(action))
        return false
    end

    syncCurrencyIntoPdm()

    local AT = Protocol.ACTION_TYPES
    if action == AT.ARENA_ENTER
        or action == AT.ARENA_GET_OPPONENT
        or action == AT.ARENA_BATTLE_RESULT
        or action == AT.ARENA_GET_LOG
        or action == AT.ARENA_CLAIM_TIER
        or action == AT.GUILD_ENTER then
        local fallback = tryLocalCloudFallback(action, params)
        if fallback then
            deliverActionResult(fallback)
            print("[LocalActionBridge] local-cloud action=" .. tostring(action)
                .. " success=" .. tostring(fallback.success)
                .. " reason=" .. tostring(fallback.reason))
            return true
        end
    end

    local ok, result = pcall(handler, LOCAL_UID, params)
    if not ok then
        print("[LocalActionBridge] handler error action=" .. tostring(action) .. ": " .. tostring(result))
        result = { success = false, action = action, reason = "本地处理失败" }
    elseif result == nil then
        print("[LocalActionBridge] async/no-result action=" .. tostring(action))
        return true
    else
        result.action = action
        if result.success == nil then
            result.success = true
        end
    end

    deliverActionResult(result)
    print("[LocalActionBridge] action=" .. tostring(action)
        .. " success=" .. tostring(result.success)
        .. " reason=" .. tostring(result.reason))
    return true
end

return M
