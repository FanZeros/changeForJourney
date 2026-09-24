-- ============================================================================
-- LocalActionBridge - 单机把 Client.sendAction 接到服务端 Handler
-- 无服务器连接时：PDM 与 ClientDispatcher 共用同一份模块表，走现有 Service。
-- ============================================================================

local Protocol         = require("shared.Protocol")
local CharacterSchema  = require("shared.schemas.CharacterSchema")
local ClientDispatcher = require("app.ClientDispatcher")
local PDM              = require("rules.character.PlayerDataManager")
local GameState        = require("core.GameState")
local ServerDispatcher = require("app.LocalDispatcher")

local M = {}

local LOCAL_UID = 1
local inited_ = false
local handlers_ = {}
local pdmAttached_ = false

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
        { "rules.battle.BattleHandler", "actionHandlers" },
        { "rules.hero.HeroHandler", "actionHandlers" },
        { "rules.gacha.GachaHandler", "actionHandlers" },
        { "rules.equipment.EquipmentHandler", "actionHandlers" },
        { "rules.blacksmith.BlacksmithHandler", "actionHandlers" },
        { "rules.task.TaskHandler", "actionHandlers" },
        { "rules.mail.MailHandler", "actionHandlers" },
        { "rules.redeem.RedeemHandler", nil },
        { "rules.awakening.AwakeningHandler", nil },
        { "rules.advancement.AdvancementHandler", nil },
        { "rules.talent.TalentHandler", nil },
        { "rules.signin.SignInHandler", nil },
        { "rules.gm.GMHandler", "actionHandlers" },
        { "rules.market.MarketHandler", nil },
        { "rules.loot.LootHandler", nil },
        { "rules.sweep.SweepHandler", "actionHandlers" },
        { "rules.relic.RelicHandler", "actionHandlers" },
        { "rules.artifact.ArtifactHandler", "actionHandlers" },
        { "rules.dungeon.DungeonHandler", "actionHandlers" },
        { "rules.offline.OfflineHandler", "actionHandlers" },
        { "rules.tower.TowerHandler", "actionHandlers" },
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
    data.helmetScroll = GameState.getHelmetScroll()
    data.shoesScroll = GameState.getShoesScroll()
    data.recruitTicket = GameState.getRecruitTicket()
    data.stellarRecruitTicket = GameState.getStellarRecruitTicket()
    data.goldenKey = GameState.getGoldenKey()
    data.sweepTicket = GameState.getSweepTicket()
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
    cur.helmetScroll = GameState.getHelmetScroll()
    cur.shoesScroll = GameState.getShoesScroll()
    cur.recruitTicket = GameState.getRecruitTicket()
    cur.stellarRecruitTicket = GameState.getStellarRecruitTicket()
    cur.goldenKey = GameState.getGoldenKey()
    cur.sweepTicket = GameState.getSweepTicket()
    cur.tavernCoin = GameState.getTavernCoin()
    cur.arcaneDust = GameState.getArcaneDust()
    cur.corruptStone = GameState.getCorruptStone()
    cur.sacredStone = GameState.getSacredStone()
    cur.speedCardExpireAt = GameState.getSpeedCardExpireAt()
end

local function deliverActionResult(result)
    if type(result) ~= "table" then return end
    local okMsg, Msg = pcall(require, "app.ClientMessageHandler")
    if okMsg and Msg and Msg.handleActionResult then
        pcall(Msg.handleActionResult, result)
    end
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
    if action == AT.GUILD_ENTER then
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
        require("rules.SaveManager").setServerId(LOCAL_UID, 1)
    end)
    PDM.AttachLocalModules(LOCAL_UID, ClientDispatcher.getAll(), 1)
    pdmAttached_ = true
end

local function hookGmAuth()
    local ok, GMHandler = pcall(require, "rules.gm.GMHandler")
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
        require("rules.redeem.RedeemService").Init()
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
    if action == AT.GUILD_ENTER then
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
