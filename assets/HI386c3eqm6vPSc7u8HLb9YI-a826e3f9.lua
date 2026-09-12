-- ============================================================================
-- GameState - 全局游戏状态容器（PlayerStore 代理模式）
--
-- 多人模式: getter 委托到 PlayerStore.GetField()，数据来自服务端 REPLICATED
-- 单机模式: PlayerStore 未初始化时回退到本地 state 表（Standalone.lua 直接操作）
--
-- 迁移说明:
--   所有 UI 页面应逐步从 GameState.getXxx() 迁移到 PlayerStore.GetField()。
--   本文件作为过渡兼容层，不再是数据的权威来源。
-- ============================================================================

local GameConfig = require("config.GameConfig")
local EventBus   = require("core.EventBus")
local GameEvents = require("config.GameEvents")
local ExpTable   = require("config.ExpTable")

local GameState = {}

--- 单机模式本地状态（Standalone.lua 使用）
local state = {
    name   = GameConfig.Player.DEFAULT_NAME,
    level  = GameConfig.Player.DEFAULT_LEVEL,
    exp    = GameConfig.Player.DEFAULT_EXP,
    maxExp = GameConfig.Player.DEFAULT_MAX_EXP,
    power  = GameConfig.Player.DEFAULT_POWER,
    gold         = GameConfig.Currency.START_GOLD,
    gems         = GameConfig.Currency.START_GEMS,
    essence      = GameConfig.Currency.START_ESSENCE,
    enhanceStone = GameConfig.Currency.START_ENHANCE_STONE,      -- 洗练石
    degradeStone = GameConfig.Currency.START_DEGRADE_STONE,      -- （已隐藏）
    destroyStone = GameConfig.Currency.START_DESTROY_STONE,      -- 点金石
    weaponScroll    = GameConfig.Currency.START_WEAPON_SCROLL,    -- 武器卷轴
    offhandScroll   = GameConfig.Currency.START_OFFHAND_SCROLL,   -- 副手卷轴
    armorScroll     = GameConfig.Currency.START_ARMOR_SCROLL,     -- 护甲卷轴
    accessoryScroll = GameConfig.Currency.START_ACCESSORY_SCROLL, -- 饰品卷轴
    recruitTicket        = GameConfig.Currency.START_RECRUIT_TICKET,
    stellarRecruitTicket = 0,
    goldenKey            = 0,
    sweepTicket   = GameConfig.Currency.START_SWEEP_TICKET,
    arenaTicket   = GameConfig.Currency.START_ARENA_TICKET,
    arenaCoin     = GameConfig.Currency.START_ARENA_COIN,
    tavernCoin    = GameConfig.Currency.START_TAVERN_COIN,
    privilegePoint = GameConfig.Currency.START_PRIVILEGE_POINT,
    arcaneDust = 0,
    corruptStone = GameConfig.Currency.START_CORRUPT_STONE,
    sacredStone = GameConfig.Currency.START_SACRED_STONE,
    speedCardExpireAt = 0,
}

--- PlayerStore 引用（延迟获取，避免循环依赖）
---@type table|nil
local playerStore_ = nil

--- 是否已绑定到 PlayerStore（多人模式标志）
local bound_ = false

--- 获取 PlayerStore（延迟 require）
local function getPS()
    if not playerStore_ then
        local ok, ps = pcall(require, "client.data.PlayerStore")
        ---@diagnostic disable-next-line: assign-type-mismatch
        if ok then playerStore_ = ps end
    end
    return playerStore_
end

--- 判断是否处于多人模式（PlayerStore 已初始化且有数据）
local function isMultiplayer()
    if not bound_ then return false end
    local ps = getPS()
    return ps and ps.IsReady()
end

-- ============================================================================
-- PlayerStore 绑定（多人模式下由 Client.lua 调用）
-- ============================================================================

--- 绑定到 PlayerStore，使 getter 委托到 PlayerStore
--- 同时订阅 player/currency 变化，触发 EventBus 兼容事件
function GameState.bindToPlayerStore()
    local ps = getPS()
    if not ps then
        print("[GameState] WARN: bindToPlayerStore failed, PlayerStore not available")
        return
    end

    bound_ = true

    -- 缓存上一次的 level/power 值（用于检测变化并触发事件）
    local lastLevel = nil
    local lastPower = nil

    -- 订阅 player 模块：检测 level 变化 → emit PLAYER_LEVEL_UP
    ps.Subscribe("player", function(data, _fieldKey)
        if not data then return end
        local newLevel = data.level
        if newLevel and lastLevel and newLevel > lastLevel then
            print("[GameState] player level changed → Lv." .. newLevel)
            EventBus.emit(GameEvents.PLAYER_LEVEL_UP, { level = newLevel })
        end
        lastLevel = newLevel

        local newPower = data.power
        if newPower and newPower ~= lastPower then
            EventBus.emit(GameEvents.PLAYER_POWER_CHANGED, { power = newPower })
        end
        lastPower = newPower
    end)

    -- 订阅 currency 模块：检测竞技券/特权点变化 → emit CURRENCY_CHANGED
    -- 用于 BottomNav 城镇红点刷新
    local lastArenaTicket = nil
    local lastPrivilegePoint = nil
    ps.Subscribe("currency", function(data, _fieldKey)
        if not data then return end
        local newTicket = data.arenaTicket
        if newTicket ~= nil and newTicket ~= lastArenaTicket then
            lastArenaTicket = newTicket
            EventBus.emit(GameEvents.CURRENCY_CHANGED, { arenaTicket = newTicket })
        end
        local newPriv = data.privilegePoint
        if newPriv ~= nil and newPriv ~= lastPrivilegePoint then
            lastPrivilegePoint = newPriv
            EventBus.emit(GameEvents.CURRENCY_CHANGED, { privilegePoint = newPriv })
        end
    end)

    print("[GameState] bound to PlayerStore (multiplayer proxy mode)")
end

--- 解绑 PlayerStore（断线/重置时调用）
function GameState.unbindFromPlayerStore()
    bound_ = false
    print("[GameState] unbound from PlayerStore")
end

-- ============================================================================
-- Getters（多人模式委托 PlayerStore，单机回退本地 state）
-- ============================================================================

function GameState.getName()
    if isMultiplayer() then
        return getPS().GetField("player", "name") or GameConfig.Player.DEFAULT_NAME
    end
    return state.name
end

function GameState.getLevel()
    if isMultiplayer() then
        return getPS().GetField("player", "level") or GameConfig.Player.DEFAULT_LEVEL
    end
    return state.level
end

function GameState.getExp()
    if isMultiplayer() then
        return getPS().GetField("player", "exp") or GameConfig.Player.DEFAULT_EXP
    end
    return state.exp
end

function GameState.getMaxExp()
    if isMultiplayer() then
        return getPS().GetField("player", "maxExp") or GameConfig.Player.DEFAULT_MAX_EXP
    end
    return state.maxExp
end

function GameState.getPower()
    -- 战斗力由客户端 CharacterPanel 计算并通过 setPower() 写入 state.power，
    -- 多人/单机模式均直接读取客户端值。服务端不主动写 player.power 字段。
    return state.power
end

function GameState.getGold()
    if isMultiplayer() then
        return getPS().GetField("currency", "gold") or 0
    end
    return state.gold
end

function GameState.getGems()
    if isMultiplayer() then
        return getPS().GetField("currency", "gems") or 0
    end
    return state.gems
end

function GameState.getEssence()
    if isMultiplayer() then
        return getPS().GetField("currency", "essence") or 0
    end
    return state.essence
end

function GameState.getEnhanceStone()
    if isMultiplayer() then
        return getPS().GetField("currency", "enhanceStone") or 0
    end
    return state.enhanceStone
end

function GameState.getDegradeStone()
    if isMultiplayer() then
        return getPS().GetField("currency", "degradeStone") or 0
    end
    return state.degradeStone
end

function GameState.getDestroyStone()
    if isMultiplayer() then
        return getPS().GetField("currency", "destroyStone") or 0
    end
    return state.destroyStone
end

function GameState.getWeaponScroll()
    if isMultiplayer() then
        return getPS().GetField("currency", "weaponScroll") or 0
    end
    return state.weaponScroll
end

function GameState.getOffhandScroll()
    if isMultiplayer() then
        return getPS().GetField("currency", "offhandScroll") or 0
    end
    return state.offhandScroll
end

function GameState.getArmorScroll()
    if isMultiplayer() then
        return getPS().GetField("currency", "armorScroll") or 0
    end
    return state.armorScroll
end

function GameState.getAccessoryScroll()
    if isMultiplayer() then
        return getPS().GetField("currency", "accessoryScroll") or 0
    end
    return state.accessoryScroll
end

function GameState.getRecruitTicket()
    if isMultiplayer() then
        return getPS().GetField("currency", "recruitTicket") or 0
    end
    return state.recruitTicket
end

function GameState.getStellarRecruitTicket()
    if isMultiplayer() then
        return getPS().GetField("currency", "stellarRecruitTicket") or 0
    end
    return state.stellarRecruitTicket or 0
end

function GameState.getGoldenKey()
    if isMultiplayer() then
        return getPS().GetField("currency", "goldenKey") or 0
    end
    return state.goldenKey or 0
end

function GameState.getSweepTicket()
    if isMultiplayer() then
        return getPS().GetField("currency", "sweepTicket") or 0
    end
    return state.sweepTicket
end

function GameState.getArenaTicket()
    if isMultiplayer() then
        return getPS().GetField("currency", "arenaTicket") or 0
    end
    return state.arenaTicket
end

function GameState.getArenaCoin()
    if isMultiplayer() then
        return getPS().GetField("currency", "arenaCoin") or 0
    end
    return state.arenaCoin
end

function GameState.getTavernCoin()
    if isMultiplayer() then
        return getPS().GetField("currency", "tavernCoin") or 0
    end
    return state.tavernCoin
end

function GameState.getPrivilegePoint()
    if isMultiplayer() then
        return getPS().GetField("currency", "privilegePoint") or 0
    end
    return state.privilegePoint
end

function GameState.getArcaneDust()
    if isMultiplayer() then
        return getPS().GetField("currency", "arcaneDust") or 0
    end
    return state.arcaneDust
end

function GameState.getCorruptStone()
    if isMultiplayer() then
        return getPS().GetField("currency", "corruptStone") or 0
    end
    return state.corruptStone or 0
end

function GameState.getSacredStone()
    if isMultiplayer() then
        return getPS().GetField("currency", "sacredStone") or 0
    end
    return state.sacredStone or 0
end

function GameState.getSpeedCardExpireAt()
    if isMultiplayer() then
        return getPS().GetField("currency", "speedCardExpireAt") or 0
    end
    return state.speedCardExpireAt or 0
end

function GameState.getSpeedCardRemainSecs()
    return math.max(0, GameState.getSpeedCardExpireAt() - os.time())
end

function GameState.getSpeedCardDisplayCount()
    return GameState.getSpeedCardRemainSecs() > 0 and 1 or 0
end

function GameState.formatSpeedCardRemain()
    local remain = GameState.getSpeedCardRemainSecs()
    if remain <= 0 then return "00:00" end
    local h = math.floor(remain / 3600)
    local m = math.floor((remain % 3600) / 60)
    return string.format("%02d:%02d", h, m)
end

-- ==================== 特权卡（永久） ====================

function GameState.isPrivilegeCardOwned()
    if isMultiplayer() then
        return (getPS().GetField("currency", "privilegeCardOwned") or 0) >= 1
    end
    return (state.privilegeCardOwned or 0) >= 1
end

function GameState.getPrivilegeCardDisplayCount()
    return GameState.isPrivilegeCardOwned() and 1 or 0
end

--- 返回经验进度 0.0 ~ 1.0
function GameState.getExpProgress()
    local exp = GameState.getExp()
    local maxExp = GameState.getMaxExp()
    if maxExp <= 0 then return 0 end
    return math.min(exp / maxExp, 1.0)
end

-- ============================================================================
-- Setters（单机模式直接写本地 state，多人模式 no-op + 警告）
-- ============================================================================

--- 内部 setter 工厂：单机模式写 state + emit EventBus，多人模式忽略
---@param fieldName string state 表中的键名
---@param eventPayloadKey string|nil EventBus 事件负载的键名
---@param eventName string|nil EventBus 事件名
local function makeSetter(fieldName, eventPayloadKey, eventName)
    return function(v)
        if isMultiplayer() then
            -- 多人模式下 setter 是 no-op（数据由服务端 REPLICATED 推送）
            return
        end
        state[fieldName] = v
        if eventName and eventPayloadKey then
            EventBus.emit(eventName, { [eventPayloadKey] = v })
        end
    end
end

GameState.setGold          = makeSetter("gold",          "gold",          GameEvents.CURRENCY_CHANGED)
GameState.setGems          = makeSetter("gems",          "gems",          GameEvents.CURRENCY_CHANGED)
GameState.setEssence       = makeSetter("essence",       "essence",       GameEvents.CURRENCY_CHANGED)
GameState.setArcaneDust    = makeSetter("arcaneDust",    "arcaneDust",    GameEvents.CURRENCY_CHANGED)
GameState.setCorruptStone  = makeSetter("corruptStone",  "corruptStone",  GameEvents.CURRENCY_CHANGED)
GameState.setSacredStone   = makeSetter("sacredStone",   "sacredStone",   GameEvents.CURRENCY_CHANGED)
GameState.setEnhanceStone  = makeSetter("enhanceStone",  "enhanceStone",  GameEvents.CURRENCY_CHANGED)
GameState.setDegradeStone  = makeSetter("degradeStone",  "degradeStone",  GameEvents.CURRENCY_CHANGED)
GameState.setDestroyStone  = makeSetter("destroyStone",  "destroyStone",  GameEvents.CURRENCY_CHANGED)
GameState.setWeaponScroll    = makeSetter("weaponScroll",    "weaponScroll",    GameEvents.CURRENCY_CHANGED)
GameState.setOffhandScroll   = makeSetter("offhandScroll",   "offhandScroll",   GameEvents.CURRENCY_CHANGED)
GameState.setArmorScroll     = makeSetter("armorScroll",     "armorScroll",     GameEvents.CURRENCY_CHANGED)
GameState.setAccessoryScroll = makeSetter("accessoryScroll", "accessoryScroll", GameEvents.CURRENCY_CHANGED)
GameState.setRecruitTicket = makeSetter("recruitTicket", "recruitTicket", GameEvents.CURRENCY_CHANGED)
GameState.setStellarRecruitTicket = makeSetter("stellarRecruitTicket", "stellarRecruitTicket", GameEvents.CURRENCY_CHANGED)
GameState.setGoldenKey            = makeSetter("goldenKey",            "goldenKey",            GameEvents.CURRENCY_CHANGED)
GameState.setSweepTicket   = makeSetter("sweepTicket",   "sweepTicket",   GameEvents.CURRENCY_CHANGED)
GameState.setArenaTicket   = makeSetter("arenaTicket",   "arenaTicket",   GameEvents.CURRENCY_CHANGED)
GameState.setArenaCoin     = makeSetter("arenaCoin",     "arenaCoin",     GameEvents.CURRENCY_CHANGED)
GameState.setTavernCoin    = makeSetter("tavernCoin",    "tavernCoin",    GameEvents.CURRENCY_CHANGED)
GameState.setPrivilegePoint = makeSetter("privilegePoint","privilegePoint",GameEvents.CURRENCY_CHANGED)

function GameState.setName(v)
    if isMultiplayer() then return end
    state.name = v or state.name
end

function GameState.setPower(v)
    -- 战斗力由客户端 CharacterPanel 计算，多人模式下也需要存储和触发事件。
    -- 服务端不主动写 player.power，此值仅客户端本地使用。
    local old = state.power
    state.power = v
    if v ~= old then
        EventBus.emit(GameEvents.PLAYER_POWER_CHANGED, { power = v })
    end
end

--- 增加经验（仅单机模式有效，多人模式由服务端处理）
function GameState.addExp(amount)
    if isMultiplayer() then return end
    state.exp = state.exp + amount
    while true do
        if ExpTable.isPlayerMaxLevel(state.level) then
            state.exp = 0
            state.maxExp = 0
            break
        end
        local needed = ExpTable.getPlayerExpForLevel(state.level)
        state.maxExp = needed
        if state.exp >= needed then
            state.exp = state.exp - needed
            state.level = state.level + 1
            EventBus.emit(GameEvents.PLAYER_LEVEL_UP, { level = state.level })
        else
            break
        end
    end
    EventBus.emit(GameEvents.PLAYER_EXP_CHANGED, {
        exp = state.exp, maxExp = state.maxExp,
    })
end

--- 从服务端同步玩家基础数据（仅单机模式使用，多人模式通过 PlayerStore 自动同步）
function GameState.syncPlayerData(data)
    if isMultiplayer() then return end
    if data.level  then state.level  = data.level end
    if data.exp    then state.exp    = data.exp end
    if data.maxExp then state.maxExp = data.maxExp end
    if data.name   then state.name   = data.name end
end

--- 重置所有缓存状态到初始默认值（仅单机模式使用）
function GameState.reset()
    if isMultiplayer() then return end
    state.name   = GameConfig.Player.DEFAULT_NAME
    state.level  = GameConfig.Player.DEFAULT_LEVEL
    state.exp    = GameConfig.Player.DEFAULT_EXP
    state.maxExp = GameConfig.Player.DEFAULT_MAX_EXP
    state.power  = GameConfig.Player.DEFAULT_POWER

    state.gold         = GameConfig.Currency.START_GOLD
    state.gems         = GameConfig.Currency.START_GEMS
    state.essence      = GameConfig.Currency.START_ESSENCE
    state.enhanceStone = GameConfig.Currency.START_ENHANCE_STONE
    state.degradeStone = GameConfig.Currency.START_DEGRADE_STONE
    state.destroyStone = GameConfig.Currency.START_DESTROY_STONE
    state.weaponScroll    = GameConfig.Currency.START_WEAPON_SCROLL
    state.offhandScroll   = GameConfig.Currency.START_OFFHAND_SCROLL
    state.armorScroll     = GameConfig.Currency.START_ARMOR_SCROLL
    state.accessoryScroll = GameConfig.Currency.START_ACCESSORY_SCROLL
    state.recruitTicket = GameConfig.Currency.START_RECRUIT_TICKET
    state.sweepTicket   = GameConfig.Currency.START_SWEEP_TICKET
    state.arenaTicket   = GameConfig.Currency.START_ARENA_TICKET
    state.arenaCoin     = GameConfig.Currency.START_ARENA_COIN
    state.tavernCoin    = GameConfig.Currency.START_TAVERN_COIN
    state.privilegePoint = GameConfig.Currency.START_PRIVILEGE_POINT
    state.corruptStone = GameConfig.Currency.START_CORRUPT_STONE
    state.sacredStone = GameConfig.Currency.START_SACRED_STONE

    EventBus.emit(GameEvents.CURRENCY_CHANGED, {
        gold = state.gold, gems = state.gems, essence = state.essence,
        enhanceStone = state.enhanceStone, degradeStone = state.degradeStone,
        destroyStone = state.destroyStone,
        weaponScroll = state.weaponScroll, offhandScroll = state.offhandScroll,
        armorScroll = state.armorScroll, accessoryScroll = state.accessoryScroll,
        recruitTicket = state.recruitTicket,
        sweepTicket = state.sweepTicket, arenaTicket = state.arenaTicket,
        arenaCoin = state.arenaCoin, tavernCoin = state.tavernCoin,
        privilegePoint = state.privilegePoint,
        corruptStone = state.corruptStone, sacredStone = state.sacredStone,
    })
    EventBus.emit(GameEvents.PLAYER_EXP_CHANGED, {
        exp = state.exp, maxExp = state.maxExp,
    })
    EventBus.emit(GameEvents.PLAYER_POWER_CHANGED, { power = state.power })

    print("[GameState] reset to defaults")
end

return GameState
