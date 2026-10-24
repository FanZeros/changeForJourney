-- ============================================================================
-- LocalActionBridge - 单机把 Client.sendAction 接到服务端 Handler
-- 无服务器连接时：PDM 与 ClientDispatcher 共用同一份模块表，走现有 Service。
-- ============================================================================

local Protocol         = require("shared.Protocol")
local CharacterSchema  = require("shared.schemas.CharacterSchema")
local ClientDispatcher = require("runtime.ClientDispatcher")
local PDM              = require("rules.character.PlayerDataManager")
local GameState        = require("core.GameState")
local ServerDispatcher = require("runtime.LocalDispatcher")
local TeamSlots       = require("shared.heroes.TeamSlots")
local ExpTable        = require("config.ExpTable")

local M = {}

local LOCAL_UID = 1
local inited_ = false
local handlers_ = {}
local pdmAttached_ = false
-- 玩家模块也被规则层原地写入，冻结已通知标量，不能以共享表自身作旧值。
local publishedPlayer_ = {}
---@type table<string, table>|nil
local deferredTaskPushes_ = nil
local publishingDungeonRewards_ = false
---@type table|nil
local quickEquipJob_ = nil
local quickEquipEpoch_ = 0
local quickEquipSerial_ = 0
local QUICK_EQUIP_BUDGET = 0.004
local QUICK_EQUIP_STEPS = 4096
local QUICK_EQUIP_KEYS = { "equipment", "heroes", "artifacts", "talents" }
---@type table|nil
local sweepJob_ = nil
local sweepEpoch_, sweepSerial_ = 0, 0
local sweepLastState_ = { pending = false, phase = "idle", completed = 0, total = 0 }
local SWEEP_KEYS = { "currency", "battle", "heroes", "player", "equipment", "dungeon", "lootbox", "artifacts", "talents" }
local SWEEP_BUDGET, SWEEP_STEPS = 0.004, 4096

--- GameState 单机提交钩子；这里只镜像 player，不反向调用 syncPlayerData。
--- init 前也可使用，确保升级事件观察者的 PDM 与 Dispatcher 已同源。
---@param player table|nil
function M.syncPlayerIntoPdm(player)
    local data = ClientDispatcher.get("player")
    local changed = data == nil
    data = data or {}
    player = player or { name = GameState.getName(), level = GameState.getLevel(),
        exp = GameState.getExp(), maxExp = GameState.getMaxExp(), power = GameState.getPower() }
    for _, field in ipairs({ "name", "level", "exp", "maxExp", "power" }) do
        if publishedPlayer_[field] ~= player[field] then changed = true end
        data[field] = player[field]
        publishedPlayer_[field] = player[field]
    end
    -- 头像不在 GameState 的五标量镜像内，规则层直接写共享模块时也必须通知。
    if publishedPlayer_.avatarHeroId ~= data.avatarHeroId then changed = true end
    publishedPlayer_.avatarHeroId = data.avatarHeroId
    if not pdmAttached_ then
        ClientDispatcher.getAll().player = data
        PDM.AttachLocalModules(LOCAL_UID, ClientDispatcher.getAll())
    end
    -- 每次 action 只核对镜像；无变化不触发槽位解锁/全名册战力重建。
    if changed then ClientDispatcher.set("player", data, { normalized = pdmAttached_ }) end
end

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
        { "rules.redeem.RedeemHandler", nil },
        { "rules.awakening.AwakeningHandler", nil },
        { "rules.advancement.AdvancementHandler", nil },
        { "rules.talent.TalentHandler", nil },
        { "rules.signin.SignInHandler", nil },
        { "rules.gm.GMHandler", "actionHandlers" },
        { "rules.market.MarketHandler", nil },
        { "rules.loot.LootHandler", nil },
        { "rules.sweep.SweepHandler", "actionHandlers" },
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
    -- 单机优选动作由桥接层适配；服务只返回权威 token/统计，客户端不传装备名单。
    for _, action in ipairs({ "PreviewInventoryCuration", "ApplyInventoryCuration", "CancelInventoryCuration" }) do
        handlers_[action] = function(uid, params)
            if action == "ApplyInventoryCuration" and (deferredTaskPushes_ or publishingDungeonRewards_) then
                return { success = false, reason = "busy", requestId = params.requestId }
            end
            local service = require("rules.equipment.InventoryCurationService")
            local success, reason, payload = service[action](uid, params.token)
            local result = {}
            for key, value in pairs(payload or {}) do result[key] = value end
            result.success, result.reason, result.requestId = success, reason, params.requestId
            return result
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
    local okMsg, Msg = pcall(require, "runtime.ClientMessageHandler")
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
                    if deferredTaskPushes_ then
                        deferredTaskPushes_[fieldKey] = moduleData
                        return
                    end
                    if fieldKey == "player" then
                        -- syncPlayerData 自己先发布 player 再发升级，不能提前/重复 set。
                        GameState.syncPlayerData(moduleData)
                    else
                        -- 业务模块已经在初始化/读档时规范化；升阶/穿戴等无需再水合全库存。
                        ClientDispatcher.set(fieldKey, moduleData, { normalized = true })
                        if fieldKey == "currency" then
                            GameState.syncFromCurrency(moduleData)
                        end
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
                if name == "player" then
                    GameState.syncPlayerData(data)
                else
                    ClientDispatcher.set(name, data)
                    if name == "currency" then GameState.syncFromCurrency(data) end
                end
            end
        end
    end)
    PDM.AttachLocalModules(LOCAL_UID, ClientDispatcher.getAll())
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
    -- 不在这里写 firstLoginTime。开场是否播放只看 introCompleted；
    -- 登录时间由 OfflineService.CalcOnEnter 在真正进游戏时记录。
    ensureModule("session", function()
        return defaultFromSchema("session")
    end)
    ensureModule("talents", function()
        return defaultFromSchema("talents")
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
    ensureModule("global_profile", function()
        return defaultFromSchema("global_profile")
    end)
    ensureModule("quotas", defaultQuotas)

    attachPdm()
    GameState.setLocalPlayerSync(function(player) M.syncPlayerIntoPdm(player) end)
    M.syncPlayerIntoPdm()
    require("rules.task.TaskService").SetPersistCallback(function(uid)
        GameState.syncFromCurrency(PDM.GetModule(uid, "currency"), { silent = true })
        return require("boot.StandaloneSave").Flush()
    end, {
        begin = function() deferredTaskPushes_ = {} end,
        finish = function(_uid, success)
            local pushes = deferredTaskPushes_ or {}
            deferredTaskPushes_ = nil
            if not success then return end
            -- 只在持久化成功后通知最终奖励/台账，失败不触发领成功视觉。
            for name, data in pairs(pushes) do
                ClientDispatcher.set(name, data, { normalized = true })
                if name == "currency" then GameState.syncFromCurrency(data) end
            end
        end,
    })
    require("rules.dungeon.DungeonService").SetPersistCallback(function(uid)
        -- 候选经验进入磁盘快照，GameState 仅在提交成功后同步，失败不提前升级。
        return require("boot.StandaloneSave").Flush(PDM.GetModule(uid, "player"))
    end, {
        begin = function() deferredTaskPushes_ = {} end,
        finish = function(_uid, success)
            local pushes = deferredTaskPushes_ or {}
            deferredTaskPushes_ = nil
            if not success then return end
            -- 先冻结玩家，再发布队员。订阅者重入 action 不能用旧 GameState 覆盖候选经验。
            local player = nil ---@type table|nil
            if pushes.player then
                player = {}
                for key, value in pairs(pushes.player) do player[key] = value end
            end
            publishingDungeonRewards_ = true
            local function publish(fn, name, data)
                local ok, err = pcall(fn, name, data, { normalized = true })
                if not ok then print("[LocalActionBridge] 副本提交通知失败: " .. tostring(err)) end
            end
            if pushes.heroes then publish(ClientDispatcher.set, "heroes", pushes.heroes) end
            if player then
                publish(ClientDispatcher.set, "player", pushes.player)
                publish(function(_, data) GameState.syncPlayerData(data) end, "player", player)
            end
            -- 单个订阅异常不能跳过其他已提交模块或留下重入锁；不重复裸发布。
            for name, data in pairs(pushes) do
                if name ~= "heroes" and name ~= "player" then
                    publish(ClientDispatcher.set, name, data)
                    if name == "currency" then
                        publish(function(_, value) GameState.syncFromCurrency(value) end, name, data)
                    end
                end
            end
            publishingDungeonRewards_ = false
        end,
    })
    require("rules.equipment.InventoryCurationService").SetPersistCallback(function()
        return require("boot.StandaloneSave").Flush()
    end, {
        begin = function()
            -- 不覆盖另一事务的暂存队列；服务在 begin 成功后才可修改数据。
            assert(deferredTaskPushes_ == nil and not publishingDungeonRewards_, "curation notification hold busy")
            deferredTaskPushes_ = {}
        end,
        finish = function(_uid, success)
            local pushes = deferredTaskPushes_ or {}
            deferredTaskPushes_ = nil
            if not success then return end
            publishingDungeonRewards_ = true
            -- 按最终原表发布，lootbox 不再次规范化/揭示旧种子，也不消费随机。
            for _, name in ipairs({ "equipment", "lootbox" }) do
                if pushes[name] then
                    local ok, err = pcall(ClientDispatcher.set, name, pushes[name], { normalized = true })
                    if not ok then print("[LocalActionBridge] curation notify failed: " .. tostring(err)) end
                end
            end
            publishingDungeonRewards_ = false
        end,
    })
    -- 旧库存需连同补偿酒馆币一起提交，不能在单模块 Schema 中截断碎片。
    local Shards = require("rules.hero.HeroShardService")
    local previewOk, previewErr, preview = Shards.ReconcileAll(LOCAL_UID, { preview = true, silent = true })
    if previewOk and preview and preview.changed then
        local DungeonService = require("rules.dungeon.DungeonService")
        local saved, saveErr = DungeonService.CommitRewardTransaction(LOCAL_UID, function()
            local ok, err, result = Shards.ReconcileAll(LOCAL_UID, { silent = true })
            if not ok then return false, err end
            DungeonService.MarkRewardDirty(LOCAL_UID, "heroes")
            DungeonService.MarkRewardDirty(LOCAL_UID, "currency")
            return true, nil, result
        end)
        if not saved then
            print("[LocalActionBridge] 碎片库存归并未提交，保留原库存: " .. tostring(saveErr))
        end
    elseif not previewOk then
        print("[LocalActionBridge] 碎片库存归并预检失败，保留原库存: " .. tostring(previewErr))
    end
    print("[LocalActionBridge] init uid=" .. LOCAL_UID)
end

-- 一键装备独占一个私有计算任务；其余动作仍沿原同步路径，数据变化让旧任务失效。
function M.isQuickEquipPending()
    return quickEquipJob_ ~= nil
end

function M.cancelQuickEquip()
    quickEquipEpoch_ = quickEquipEpoch_ + 1
    quickEquipJob_ = nil
end

local function quickEquipCurrent(job)
    if quickEquipJob_ ~= job or job.epoch ~= quickEquipEpoch_ then return false end
    local store = require("core.PlayerStore")
    for _, name in ipairs(QUICK_EQUIP_KEYS) do
        -- 在线经验推送/永久成长可连续发生；不能靠 heroes 的整模块版本饿死换装。
        -- Service 始终私有快照搜索，最后无 yield 按最新英雄重新校验选定六槽。
        if name ~= "heroes" and (PDM.GetModule(LOCAL_UID, name) ~= job.sources[name]
            or store.GetRevision(name) ~= job.revisions[name]) then return false end
    end
    return true
end

local function startQuickEquip(handler, params)
    if quickEquipJob_ then return true end
    quickEquipSerial_ = quickEquipSerial_ + 1
    local store = require("core.PlayerStore")
    local job = { epoch = quickEquipEpoch_, id = quickEquipSerial_, heroId = params.heroId,
        sources = {}, revisions = {}, steps = 0, deadline = 0, committed = false }
    for _, name in ipairs(QUICK_EQUIP_KEYS) do
        job.sources[name] = PDM.GetModule(LOCAL_UID, name)
        job.revisions[name] = store.GetRevision(name)
    end
    local control = {
        isCurrent = function() return quickEquipCurrent(job) end,
        checkpoint = function()
            job.steps = job.steps + 1
            if job.steps >= QUICK_EQUIP_STEPS or os.clock() >= job.deadline then
                if not quickEquipCurrent(job) then error("quick_equip_stale", 0) end
                coroutine.yield()
                if not quickEquipCurrent(job) then error("quick_equip_stale", 0) end
            end
        end,
        onCommitted = function(result) job.committed = result end,
    }
    job.worker = coroutine.create(function()
        return handler(LOCAL_UID, { heroId = job.heroId }, control)
    end)
    quickEquipJob_ = job
    return true
end

-- 由宿主每帧驱动一次；4ms是软预算，单次属性重建/最终提交不在中途切开。
function M.updateQuickEquip()
    local job = quickEquipJob_
    if sweepJob_ or not job or deferredTaskPushes_ or publishingDungeonRewards_ then return end
    ---@type table
    local result
    if not quickEquipCurrent(job) then
        result = { success = false, reason = "quick_equip_stale" }
    else
        job.steps, job.deadline = 0, os.clock() + QUICK_EQUIP_BUDGET
        local ok, value = coroutine.resume(job.worker)
        -- MarkDirty同步订阅可能清档或排入新任务，旧任务绝不清理/回执新会话。
        if quickEquipJob_ ~= job or job.epoch ~= quickEquipEpoch_ then return end
        if ok and coroutine.status(job.worker) ~= "dead" then return end
        if ok and type(value) == "table" then
            result = value
        else
            print("[LocalActionBridge] quick equip failed: " .. tostring(value))
            if job.committed then
                result = job.committed
                result.notificationFailed = true
            else
                result = { success = false, reason = value == "quick_equip_stale"
                    and "quick_equip_stale" or "quick_equip_failed" }
            end
        end
    end
    quickEquipJob_ = nil
    result.action, result.heroId, result.quickEquipId = Protocol.ACTION_TYPES.EQUIP_ALL_BEST, job.heroId, job.id
    deliverActionResult(result)
end

-- 扫荡持有唯一私有 worker。pending 包括提交后的完整奖励呈现准备；宿主据此独占 RNG。
function M.isSweepPending()
    return sweepJob_ ~= nil
end

function M.getSweepState()
    local source = sweepJob_ and sweepJob_.state or sweepLastState_
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
end

function M.cancelSweep(reason)
    sweepEpoch_ = sweepEpoch_ + 1
    local job = sweepJob_
    sweepJob_ = nil
    if not job then return end
    job.state.pending = false
    -- Stop/reset 丢弃的是展示协程，不把已到账的成功改成可重试失败。
    job.state.phase = job.committed and "complete" or "cancelled"
    job.state.success = job.committed and true or false
    job.state.reason = reason or "sweep_cancelled"
    sweepLastState_ = job.state
end

local function sweepCurrent(job)
    if sweepJob_ ~= job or job.epoch ~= sweepEpoch_ then return false, "sweep_cancelled" end
    -- 自己提交会正常触发 revision；提交后仅检查生命周期，不把自身通知当成外部改档。
    if job.committed then return true end
    local store = require("core.PlayerStore")
    for _, name in ipairs(SWEEP_KEYS) do
        if PDM.GetModule(LOCAL_UID, name) ~= job.sources[name]
            or store.GetRevision(name) ~= job.revisions[name] then return false, "sweep_stale" end
    end
    return true
end

local function sweepIdentity(job, result)
    result.action = job.action
    result.requestId, result.sweepRequestId = job.params.requestId, job.id
    if result.teamIdx == nil then result.teamIdx = job.params.teamIdx end
    if result.stageId == nil then result.stageId = job.params.stageId end
    if job.action == Protocol.ACTION_TYPES.DUNGEON_SWEEP then
        if result.dungeonId == nil then result.dungeonId = job.params.dungeonId or "gold_mine" end
        if result.sweepFloor == nil then result.sweepFloor = job.params.floor end
    end
    return result
end

local function prepareSweepPresentation(job, result, checkpoint)
    if result.success ~= true then return end
    local Msg = require("runtime.ClientMessageHandler")
    -- 预排序仅处理私有回执；这里可让出，已提交 live 状态绝不再次扣券或发奖。
    if Msg.prepareSweepPresentation then
        result.sweepPresentation = Msg.prepareSweepPresentation(result, function(a, b, c)
            -- 呈现 helper 可用(done,total)或(phase,done,total)，对外统一阶段。
            if type(a) == "string" then checkpoint("presentation", b, c)
            else checkpoint("presentation", a, b) end
        end)
    end
end

local function startSweep(action, handler, params)
    if sweepJob_ or quickEquipJob_ or deferredTaskPushes_ or publishingDungeonRewards_ then
        deliverActionResult({ success = false, action = action, reason = "sweep_busy",
            requestId = params.requestId, sweepRequestId = params.sweepRequestId or params.requestId,
            dungeonId = action == Protocol.ACTION_TYPES.DUNGEON_SWEEP and (params.dungeonId or "gold_mine") or nil,
            teamIdx = params.teamIdx, stageId = params.stageId })
        return true
    end
    sweepSerial_ = sweepSerial_ + 1
    local request = {}
    -- 请求仅冻结协议标量，不暴露 worker/candidate 给 UI。
    for _, key in ipairs({ "count", "times", "teamIdx", "stageId", "dungeonId", "floor", "requestId", "sweepRequestId" }) do
        request[key] = params[key]
    end
    local id = request.sweepRequestId or request.requestId or ("sweep-bridge:" .. tostring(sweepSerial_))
    local job = { epoch = sweepEpoch_, serial = sweepSerial_, id = id, params = request, action = action,
        sources = {}, revisions = {}, steps = 0, deadline = 0, committed = false,
        state = { pending = true, phase = "queued", completed = 0, total = 0, requestId = id,
            sweepRequestId = id, count = request.count or request.times, action = action,
            teamIdx = request.teamIdx, stageId = request.stageId } }
    local store = require("core.PlayerStore")
    for _, name in ipairs(SWEEP_KEYS) do
        job.sources[name] = PDM.GetModule(LOCAL_UID, name)
        job.revisions[name] = store.GetRevision(name)
    end
    local function checkpoint(phase, completed, total)
        local current, reason = sweepCurrent(job)
        if not current then error(reason, 0) end
        job.state.phase = phase or job.state.phase
        job.state.completed, job.state.total = completed or 0, total or 0
        job.steps = job.steps + 1
        if job.steps >= SWEEP_STEPS or os.clock() >= job.deadline then
            coroutine.yield()
            local resumed, resumedReason = sweepCurrent(job)
            if not resumed then error(resumedReason, 0) end
        end
    end
    local control = {
        check = function() return sweepCurrent(job) end,
        isCancelled = function() return not sweepCurrent(job) end,
        checkpoint = checkpoint,
        summaryLogs = true,
        onCommitted = function(result)
            job.committed = sweepIdentity(job, result)
            job.committed.success = true
            job.state.phase = "presentation"
        end,
    }
    job.worker = coroutine.create(function()
        local result = handler(LOCAL_UID, request, control)
        if type(result) ~= "table" then error("sweep_no_result", 0) end
        sweepIdentity(job, result)
        if result.success == true then
            -- 兼容服务在无通知路径返回成功；正式 Service 在通知前先 onCommitted。
            job.committed = result
            checkpoint("presentation", 0, 0)
            prepareSweepPresentation(job, result, checkpoint)
        end
        return result
    end)
    sweepJob_ = job
    print("[LocalActionBridge] sweep queued id=" .. tostring(id))
    return true
end

-- 每帧最多恢复一次，且必须在任何战斗/动效/自动保存前调用。
function M.updateSweep()
    local job = sweepJob_
    if not job or job.delivering or deferredTaskPushes_ or publishingDungeonRewards_ then return end
    local current, reason = sweepCurrent(job)
    local result = nil ---@type table|nil
    if not current then
        result = { success = false, reason = reason }
    else
        job.steps, job.deadline = 0, os.clock() + SWEEP_BUDGET
        local ok, value = coroutine.resume(job.worker)
        if sweepJob_ ~= job or job.epoch ~= sweepEpoch_ then return end
        if ok and coroutine.status(job.worker) ~= "dead" then return end
        if ok and type(value) == "table" then result = value
        elseif job.committed then
            result = job.committed
            result.success, result.notificationFailed = true, true
            -- 已提交的呈现失败只降级完整同步呈现，不伪造业务失败/重试。
            print("[LocalActionBridge] sweep committed, presentation fallback: " .. tostring(value))
        else
            print("[LocalActionBridge] sweep failed: " .. tostring(value))
            result = { success = false, reason = value == "sweep_stale" and "sweep_stale" or "sweep_failed" }
        end
    end
    sweepIdentity(job, result)
    job.delivering = true
    deliverActionResult(result)
    -- 回执内可能 Stop/reset；旧任务不能清除新会话任务或重发终态。
    if sweepJob_ ~= job or job.epoch ~= sweepEpoch_ then return end
    job.state.pending, job.state.success = false, result.success == true
    job.state.phase = result.success == true and "complete" or "failed"
    job.state.reason = result.reason
    sweepLastState_, sweepJob_ = job.state, nil
end

---@param action string
---@param params table|nil
---@return boolean handled
function M.dispatch(action, params)
    -- 事务提交发布中不能重入任何动作（包括GM）；等通知整段完成再允许生命周期切换。
    if publishingDungeonRewards_ or deferredTaskPushes_ then return false end
    params = params or {}
    local AT = Protocol.ACTION_TYPES
    if action == AT.GM_RESET_SAVE then
        M.cancelSweep("reset")
        M.cancelQuickEquip()
    elseif sweepJob_ then
        -- 在镜像同步之前拒绝所有业务动作；不让 UI、热键或同步通知消耗 RNG/改模块。
        -- 重发同一在途身份不提前终结原请求，其他请求得到各自唯一 busy 回执。
        local id = params.sweepRequestId or params.requestId
        if action ~= sweepJob_.action or id ~= sweepJob_.id then
            deliverActionResult({ success = false, action = action, reason = "sweep_busy",
                requestId = params.requestId, sweepRequestId = id,
                dungeonId = action == AT.DUNGEON_SWEEP and (params.dungeonId or "gold_mine") or nil,
                teamIdx = params.teamIdx, stageId = params.stageId })
        end
        return true
    end
    -- 已落盘奖励的模块通知尚未发布完，拒绝同步重入，避免旧玩家镜像覆盖新经验。
    if publishingDungeonRewards_ then return false end
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
    M.syncPlayerIntoPdm()

    if action == AT.SWEEP then return startSweep(action, handler, params) end
    if action == AT.DUNGEON_SWEEP then
        local sweepHandler = require("rules.sweep.SweepHandler")
        if sweepHandler.isResourceSweep(params) then
            return startSweep(action, sweepHandler.resourceSweep, params)
        end
    end
    if action == AT.EQUIP_ALL_BEST then return startQuickEquip(handler, params) end
    if action == AT.GUILD_ENTER then
        local fallback = tryLocalCloudFallback(action, params)
        if fallback then
            deliverActionResult(fallback)
            print("[LocalActionBridge] local fallback action=" .. tostring(action)
                .. " success=" .. tostring(fallback.success)
                .. " reason=" .. tostring(fallback.reason))
            return true
        end
    end

    local ok, result = pcall(handler, LOCAL_UID, params)
    if not ok then
        print("[LocalActionBridge] handler error action=" .. tostring(action) .. ": " .. tostring(result))
        result = { success = false, action = action, reason = "本地处理失败", requestId = params.requestId }
        if action == AT.TOGGLE_EQUIP_LOCK then
            result.seq, result.lockRequestId = params.seq, params.lockRequestId
        end
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

---@param teamLayouts table<number, integer[]>
---@return boolean ok
---@return string? reason
function M.setTeams(teamLayouts)
    if sweepJob_ then return false, "sweep_busy" end
    if not inited_ then M.init() end
    local heroes = ClientDispatcher.get("heroes")
    if not heroes then return false, "英雄数据未加载" end
    local battleProgress = PDM.GetModule(LOCAL_UID, "battle")
    local teamCount = ExpTable.TEAM_COUNT
    for teamIdx, ids in pairs(teamLayouts) do
        if type(teamIdx) ~= "number" or teamIdx ~= math.floor(teamIdx)
            or teamIdx < 1 or teamIdx > teamCount or type(ids) ~= "table" then
            return false, "无效的队伍编号或阵容"
        end
    end
    local copy = { roster = heroes.roster, deployed = heroes.deployed, teams = {} }
    for i = 1, teamCount do
        local team = heroes.teams and heroes.teams[i]
        local ids = team and team.slots or (i == 1 and heroes.deployed or {})
        copy.teams[i] = { slots = {} }
        for slot, id in ipairs(ids or {}) do copy.teams[i].slots[slot] = id end
    end
    -- 校验时隔离参与队伍的旧占位；候选队伍间单独查重，再整体写入副本。
    local seen = {}
    for _, ids in pairs(teamLayouts) do
        for _, id in ipairs(ids) do
            local numId = tonumber(id)
            if numId and numId ~= 0 then
                if seen[numId] then return false, "重复的英雄: " .. tostring(numId) end
                seen[numId] = true
            end
        end
    end
    for teamIdx in pairs(teamLayouts) do
        copy.teams[teamIdx].slots = {}
    end
    if teamLayouts[1] then copy.deployed = {} end
    for teamIdx, ids in pairs(teamLayouts) do
        local ok, reason = TeamSlots.validate(copy, teamIdx, ids, battleProgress)
        if not ok then return false, reason end
    end
    for teamIdx, ids in pairs(teamLayouts) do
        copy.teams[teamIdx].slots = ids
    end
    if teamLayouts[1] then copy.deployed = teamLayouts[1] end
    TeamSlots.normalize(copy)
    heroes.teams, heroes.deployed = copy.teams, copy.deployed
    PDM.MarkDirty(LOCAL_UID, "heroes")
    print("[LocalActionBridge] teams committed atomically")
    return true
end

return M
