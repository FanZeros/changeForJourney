-- 单场真实全灭恢复观察器：只验票/发回执，不治疗、不发奖、不参与胜负。
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local Tracker = {}
Tracker.__index = Tracker

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function positiveInt(value)
    return finite(value) and value > 0 and value % 1 == 0
end
local function slot(value)
    return positiveInt(value) and value <= 4
end
local function nonterminal(config, id)
    return positiveInt(id) and type(config) == "table"
        and type(config.getStage) == "function" and type(config.isTerminalTemple) == "function"
        and type(config.getStage(id)) == "table" and config.isTerminalTemple(id) == false
end
local function partySize(allies)
    if type(allies) ~= "table" then return nil end
    local count = #allies
    if count < 1 or count > 4 then return nil end
    -- 不让 ipairs 的空洞截断、额外数字键或非数组值成为全灭证据。
    for key in pairs(allies) do
        if not positiveInt(key) or key > count then return nil end
    end
    for i = 1, count do
        if type(allies[i]) ~= "table" then return nil end
    end
    return count
end
local function health(unit, full)
    local attrs = unit.attrs
    local final = type(attrs) == "table" and attrs.final
    if type(final) ~= "table" or not finite(unit.hp) or not finite(final[AD.HP]) then
        return false
    end
    if not full then return unit.hp <= 0 and final[AD.HP] <= 0 end
    local maxHp = final[AD.MAX_HP]
    return finite(maxHp) and maxHp > 0 and finite(unit.maxHp)
        and unit.hp == maxHp and final[AD.HP] == maxHp and unit.maxHp == maxHp
end
local function snapshot(allies)
    local count = partySize(allies)
    if not count then return nil end
    local heroes, ids, slots = {}, {}, {}
    for i = 1, count do
        local unit = allies[i]
        local id = unit.heroId
        local partySlot = unit.partySlot
        local order = unit._slotOrder
        local position = partySlot ~= nil and partySlot or order
        if not positiveInt(id) or not HC.get(id) or unit.monsterId ~= nil
            or not slot(position) or (order ~= nil and not slot(order))
            or ids[id] or slots[position] or not health(unit, false) then return nil end
        ids[id], slots[position] = true, true
        heroes[#heroes + 1] = {
            unit = unit, heroId = id, partySlot = partySlot, slotOrder = order, position = position,
        }
    end
    table.sort(heroes, function(a, b) return a.position < b.position end)
    return heroes
end
local function sameParty(ticket, allies, full)
    if allies ~= ticket.allies or partySize(allies) ~= #ticket.heroes then return false end
    local present = {}
    for _, unit in ipairs(allies) do present[unit] = (present[unit] or 0) + 1 end
    for _, hero in ipairs(ticket.heroes) do
        local unit = hero.unit
        if present[unit] ~= 1 or unit.heroId ~= hero.heroId or unit.monsterId ~= nil
            or unit.partySlot ~= hero.partySlot or unit._slotOrder ~= hero.slotOrder
            or not health(unit, full) then return false end
    end
    return true
end

function Tracker.new(getState)
    local self = setmetatable({}, Tracker)
    self:init(getState)
    return self
end
function Tracker:init(getState)
    self.getState = getState
    self.generation = 0
    self.loadDepth = 0
    self.capturing = false
    self.trusted = true -- 仅当前进程单场来源；不是全局阴性，也不持久化。
    ---@type function|nil
    self.capture = nil
    ---@type function|nil
    self.commit = nil
    ---@type table|nil
    self.pending = nil
end
function Tracker:cancel()
    self.generation = self.generation + 1
    self.pending = nil
end
function Tracker:disableSource()
    self:cancel()
    self.trusted = false
end
function Tracker:resetSource()
    self:cancel()
    self.trusted = true -- 仅真实 Scene init/reset 调用；广播读档/reload/换队不洗白。
end
function Tracker:setCallbacks(capture, commit)
    self:cancel() -- 即使换成相同函数，也不能沿用旧上下文凭据；Stop 可传 nil,nil。
    self.capture = type(capture) == "function" and capture or nil
    self.commit = type(commit) == "function" and commit or nil
end
function Tracker:isCurrent(generation)
    return generation == self.generation
end

-- 仅 BattleCasualty 的真实失败分支调用；ctx 的来源/代次须仍是本场。
function Tracker:captureWipe(ctx)
    if not self.trusted or not self.capture or not self.commit or self.loadDepth ~= 0 or self.pending or self.capturing then return end
    local state = self.getState()
    local config = state.getStageConfig()
    if ctx.rescueTracker ~= self or ctx.rescueGeneration ~= self.generation
        or ctx.allies ~= state.allies or ctx.enemies ~= state.enemies
        or ctx.enemyQueue ~= state.enemyQueue or ctx.currentStageId ~= state.currentStageId
        or not state.battleActive or state.defeatTimer ~= nil or state.defeatByTimeout
        or state.terminalDefeatPending or not nonterminal(config, state.currentStageId) then return end
    local heroes = snapshot(state.allies)
    if not heroes then return end
    local generation, capture, commit = self.generation, self.capture, self.commit
    local ticket = {
        owner = self, generation = generation, status = "captured", config = config,
        failedStageId = state.currentStageId, isFirstClear = state.isFirstClear,
        allies = state.allies, failedEnemies = state.enemies, failedQueue = state.enemyQueue,
        heroes = heroes, commit = commit,
    }
    self.capturing = true
    local ok, context = pcall(capture) -- 无参数，真实失败瞬间的上下文；不复制玩家档到回执。
    self.capturing = false
    local after = self.getState()
    if not ok then print("[BattleRescueTracker] capture failed"); return end
    if type(context) ~= "table" or not self.trusted or not self:isCurrent(generation)
        or self.capture ~= capture or self.commit ~= commit
        or after.currentStageId ~= ticket.failedStageId or after.enemies ~= ticket.failedEnemies
        or after.getStageConfig() ~= config or not after.battleActive or after.defeatTimer ~= nil
        or after.isFirstClear ~= ticket.isFirstClear or after.defeatByTimeout or after.terminalDefeatPending
        or after.enemyQueue ~= ticket.failedQueue or not sameParty(ticket, after.allies, false) then return end
    ticket.context = context -- 仅内部不透明凭据；绝不并入 serializable receipt。
    self.pending = ticket
end

-- 先于失败恢复 loadStage 取得一次性票，绝不靠恢复后清零的 timeout 字段推理。
function Tracker:prepareRecovery(ctx, targetId)
    local ticket = self.pending
    if not ticket or ticket.status ~= "captured" then return nil end
    local state = self.getState()
    local expected = ticket.isFirstClear
        and (ticket.config.getPrevStageId(ticket.failedStageId) or ticket.failedStageId)
        or ticket.failedStageId
    if not self.trusted or ctx.rescueTracker ~= self or ctx.rescueGeneration ~= self.generation
        or not self:isCurrent(ticket.generation) or state.currentStageId ~= ticket.failedStageId
        or state.getStageConfig() ~= ticket.config or state.enemies ~= ticket.failedEnemies
        or state.enemyQueue ~= ticket.failedQueue or state.isFirstClear ~= ticket.isFirstClear
        or not finite(ctx.defeatTimer) or ctx.defeatTimer < 0 or ctx.defeatByTimeout or ctx.terminalDefeatPending
        or not finite(state.defeatTimer) or state.defeatTimer < 0 or state.battleActive
        or state.defeatByTimeout or state.terminalDefeatPending
        or targetId ~= expected or not nonterminal(ticket.config, targetId)
        or not sameParty(ticket, state.allies, false) then self:cancel(); return nil end
    ticket.targetId, ticket.status = targetId, "prepared"
    return ticket
end

-- 所有加载都推进 generation；只有 depth=0 且显式携带本次票的那一次加载保票。
function Tracker:beginLoad(stageId, skipBattleStart, ticket)
    local expected = self.trusted and ticket ~= nil and ticket == self.pending and ticket.owner == self
        and ticket.status == "prepared" and ticket.generation == self.generation
        and self.loadDepth == 0 and skipBattleStart == true and stageId == ticket.targetId
    self.generation = self.generation + 1
    self.loadDepth = self.loadDepth + 1
    if expected then
        ticket.generation, ticket.status = self.generation, "loading"
    else
        self.pending = nil
    end
    return { generation = self.generation, ticket = expected and ticket or nil }
end
function Tracker:finishLoad(marker, loaded)
    self.loadDepth = math.max(0, self.loadDepth - 1)
    if not loaded or not self:isCurrent(marker.generation) then
        if marker.ticket == self.pending then self.pending = nil end
        return false
    end
    local ticket = marker.ticket
    if ticket then
        local state = self.getState()
        if ticket ~= self.pending or ticket.status ~= "loading" or self.loadDepth ~= 0
            or state.currentStageId ~= ticket.targetId or state.getStageConfig() ~= ticket.config
            or not nonterminal(ticket.config, state.currentStageId) or state.allies ~= ticket.allies
            or state.enemies == ticket.failedEnemies or state.enemyQueue == ticket.failedQueue
            or not state.battleActive or state.defeatTimer ~= nil or state.terminalDefeatPending then
            self.pending = nil
        else
            ticket.enemies, ticket.enemyQueue, ticket.status = state.enemies, state.enemyQueue, "loaded"
        end
    end
    return true
end
function Tracker:readyRecovery(ticket)
    if not ticket or ticket ~= self.pending or ticket.status ~= "loaded" then return nil end
    local state = self.getState()
    if not self:isCurrent(ticket.generation) or state.currentStageId ~= ticket.targetId
        or state.enemies ~= ticket.enemies or state.enemyQueue ~= ticket.enemyQueue
        or not sameParty(ticket, state.allies, true) then self.pending = nil; return nil end
    ticket.status = "ready"
    return ticket
end

-- Scene 回灌全部状态后提交；先消票再 pcall，回调重入/报错均不会重复发放。
function Tracker:commitRecovery(ticket)
    if not ticket or ticket ~= self.pending or ticket.status ~= "ready" then return end
    local state = self.getState()
    if not self.trusted or ticket.owner ~= self or not self:isCurrent(ticket.generation) or self.loadDepth ~= 0
        or self.commit ~= ticket.commit or state.getStageConfig() ~= ticket.config
        or state.currentStageId ~= ticket.targetId or not nonterminal(ticket.config, ticket.targetId)
        or state.enemies ~= ticket.enemies or state.enemyQueue ~= ticket.enemyQueue
        or not state.battleActive or state.defeatTimer ~= nil or state.defeatByTimeout
        or state.terminalDefeatPending or not sameParty(ticket, state.allies, true) then
        self:cancel(); return
    end
    local heroIds = {}
    for _, hero in ipairs(ticket.heroes) do heroIds[#heroIds + 1] = hero.heroId end
    local receipt = {
        schemaVersion = 1, source = "live_nonterminal_wipe_recovery", scope = "single_scene",
        failedStageId = ticket.failedStageId, recoveredStageId = state.currentStageId,
        heroIds = heroIds, recoveryComplete = true,
    }
    self.pending = nil
    local ok = pcall(ticket.commit, ticket.context, receipt)
    if not ok then print("[BattleRescueTracker] commit failed") end
end

return Tracker
