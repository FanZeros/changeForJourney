-- ============================================================================
-- TowerBattleScene - 通天塔战斗场景（状态管理器）
-- 三行攻坚：每真实层一波、五层一局，逐层提交后自动继续，暗契跨本组保留。
-- ============================================================================

local TowerTriBattle     = require("ui.tower.TowerTriBattle")
local DungeonBattle      = require("ui.dungeon.DungeonBattle")
local TowerBuffPick      = require("ui.tower.TowerBuffPick")
local TowerBuffRuntime   = require("systems.TowerBuffRuntime")
local TowerConfig        = require("config.TowerConfig")
local Protocol           = require("shared.Protocol")
local BattleResultPanel  = require("ui.battle.popup.BattleResultPanel")
local BattleDraw         = require("ui.battle.scene.BattleDraw")
local BattleStats        = require("systems.BattleStats")
local HeroConfig         = require("config.HeroConfig")
local AD                 = require("systems.AttributeDef")
local TowerLayout        = require("ui.tower.TowerLayout")
local TowerBuffSidebar   = require("ui.tower.TowerBuffSidebar")
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")

---@type Widget?
local settlementRoot = nil
local settlementKey = ""
local function destroySettlementRoot()
    if settlementRoot then settlementRoot:Destroy(); settlementRoot = nil end
    settlementKey = ""
end

local drawTextStroke = BattleDraw.drawTextStroke

local TowerScene = {}

-- ======================== 状态 ========================

local state = {
    active = false,
    sessionVersion = 0,

    -- 层/波
    floor     = 1,
    wave      = 1,
    monsterLevel = 1,

    -- 强化
    buffIds  = {},   -- Service 回执的独立快照，Scene 禁止 append 权威 buffs
    pendingBuffChoices = nil,
    runId = nil,
    pendingSelection = nil,
    choiceQueue = {},
    unappliedBuffIds = {}, -- 择契不重开当前层，新强化在下一层开始应用。
    startFloor = 1,
    endFloor = 5,
    floorReceipts = {},
    runRewards = {},
    runPlayerExp = 0,
    runHeroExpTotal = 0,
    settlementRequest = nil,
    settlementSerial = 0,
    settlementElapsed = 0,
    onCleanup = nil,
    cleanupDone = false,

    -- 阶段
    phase    = "idle",  -- idle / battle / floor_win / settlement_retry / error

    -- 异常兜底
    errorMessage = nil,
    errorLogged  = false,

    -- 回调
    onClose    = nil,
    sendAction = nil,
    allies     = nil,   -- 三队合并引用（跨波保持）
    teamAllies = nil,   -- { [1]=table[], [2]=table[], [3]=table[] }

    -- 服务端结果
    serverFloorResult = nil,
    totalElapsedSecs = 0,
    currentWaveStartTime = 0,
    floorHeroDamage = {},
}

local function copyBuffIds(ids)
    local result = {}
    for i, id in ipairs(ids or {}) do result[i] = id end
    return result
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function cleanupRun()
    if state.cleanupDone then return end
    state.cleanupDone = true
    local callback = state.onCleanup
    if callback and state.runId then
        local ok, err = pcall(callback, state.runId)
        if not ok then print("[TowerBattleScene] cleanup failed: " .. tostring(err)) end
    end
end

local function clearChoices()
    TowerBuffPick.close()
    state.pendingSelection, state.pendingBuffChoices = nil, nil
    state.choiceQueue, state.unappliedBuffIds, state.buffIds = {}, {}, {}
end

local function resetFloorStats()
    state.floorHeroDamage = {}
end

local function flattenTeamAllies()
    local list = {}
    local teams = state.teamAllies or {}
    for t = 1, 3 do
        for _, unit in ipairs(teams[t] or {}) do
            list[#list + 1] = unit
        end
    end
    return list
end

local function accumulateCurrentWaveStats()
    local waveStats = BattleStats.buildHeroDamageStats(flattenTeamAllies(), HeroConfig.HEROES)
    for _, hero in ipairs(waveStats) do
        local heroId = hero.heroId
        if heroId then
            state.floorHeroDamage[heroId] = (state.floorHeroDamage[heroId] or 0) + (hero.totalDamage or 0)
        end
    end
end

local function buildFloorHeroStats()
    local heroStats = {}
    for _, unit in ipairs(flattenTeamAllies()) do
        if unit.heroId then
            local hConf = HeroConfig.HEROES[unit.heroId]
            heroStats[#heroStats + 1] = {
                heroId      = unit.heroId,
                quality     = hConf and hConf.quality or 1,
                totalDamage = state.floorHeroDamage[unit.heroId] or 0,
            }
        end
    end
    table.sort(heroStats, function(a, b) return (a.totalDamage or 0) > (b.totalDamage or 0) end)
    return heroStats
end

local function applyBuffsToAllTeams(buffIds)
    local teams = state.teamAllies or {}
    for t = 1, 3 do
        TowerBuffRuntime.applyStatBuffs(teams[t] or {}, buffIds)
    end
end

-- ======================== Public API ========================

function TowerScene.isActive()
    return state.active
end

-- 仅复制展示身份与已确认强化，不泄露战斗单位/权威run可变表。
function TowerScene.getDisplayState()
    return { floor = state.floor, wave = state.wave, phase = state.phase,
        startFloor = state.startFloor, endFloor = state.endFloor,
        monsterLevel = state.monsterLevel, buffIds = copyBuffIds(state.buffIds),
        pendingChoices = #state.choiceQueue,
        inputModal = TowerTriBattle.isConfirmationOpen() or BattleResultPanel.isOpen() }
end

function TowerScene.getPresentationKey()
    return state.sessionVersion .. ":" .. tostring(state.active) .. ":" .. tostring(state.runId)
        .. ":" .. state.floor .. ":" .. state.wave
        .. ":" .. state.phase .. ":" .. TowerBuffPick.getPresentationKey()
        .. ":" .. TowerTriBattle.getPresentationKey()
        .. ":" .. TowerBuffSidebar.getPresentationKey()
end

function TowerScene.getLayout(width, height)
    return TowerLayout.compute(width, height)
end

--- 打开通天塔战斗（由 DungeonPage 在 TOWER_CHALLENGE 成功后调用）
---@param opts table { teamAllies, allies, data, sendAction, onClose }
function TowerScene.open(opts)
    destroySettlementRoot()
    state.sessionVersion = state.sessionVersion + 1
    TowerBuffSidebar.reset()
    state.active = true
    state.phase  = "battle"
    state.floor  = opts.data.floor or 1
    state.wave   = 1
    state.startFloor = opts.data.startFloor or state.floor
    state.endFloor = opts.data.endFloor or TowerConfig.getRunEndFloor(state.startFloor)
    state.floorReceipts, state.runRewards = {}, {}
    state.runPlayerExp, state.runHeroExpTotal = 0, 0
    state.settlementRequest = nil
    state.settlementElapsed = 0
    state.onCleanup, state.cleanupDone = opts.onCleanup, false
    state.monsterLevel = opts.data.monsterLevel or 1
    TowerBuffPick.close()
    state.pendingSelection = nil
    state.choiceQueue, state.unappliedBuffIds = {}, {}
    state.runId = opts.data.runId
    state.buffIds = copyBuffIds(opts.data.buffs)
    state.onClose = opts.onClose
    state.sendAction = opts.sendAction
    state.teamAllies = opts.teamAllies
    if type(state.teamAllies) ~= "table" then
        state.teamAllies = { [1] = opts.allies or {}, [2] = {}, [3] = {} }
    end
    state.allies = flattenTeamAllies()
    state.pendingBuffChoices = nil
    state.serverFloorResult = nil
    state.totalElapsedSecs = 0
    state.currentWaveStartTime = time.elapsedTime or 0
    resetFloorStats()
    state.errorMessage = nil
    state.errorLogged = false

    TowerBuffPick.setSendAction(state.sendAction)

    local okBuff, buffErr = pcall(function()
        applyBuffsToAllTeams(state.buffIds)
        TowerBuffRuntime.initMechanics(state.buffIds)
    end)
    if not okBuff then
        print("[TowerBattleScene] ERROR init tower buffs: " .. tostring(buffErr))
        state.phase = "error"
        state.errorMessage = "通天塔强化初始化失败，请退出后重试"
        return
    end

    local okOpen = TowerScene._openWaveBattle(opts.data.monsters)
    if not okOpen then
        return
    end

    print("[TowerBattleScene] open floor=" .. state.floor .. " wave=" .. state.wave
        .. " teams=" .. tostring(#(state.teamAllies[1] or {})) .. "/"
        .. tostring(#(state.teamAllies[2] or {})) .. "/"
        .. tostring(#(state.teamAllies[3] or {})))
end

function TowerScene.close()
    destroySettlementRoot()
    cleanupRun()
    TowerBuffSidebar.reset()
    state.active = false
    state.phase = "idle"
    clearChoices()
    state.floorReceipts, state.runRewards = {}, {}
    state.serverFloorResult, state.settlementRequest = nil, nil
    state.runId = nil
    state.errorMessage = nil
    state.errorLogged = false
    pcall(TowerTriBattle.forceClose)
    TowerBuffRuntime.cleanup()
    local callback = state.onClose
    state.onClose, state.onCleanup, state.sendAction = nil, nil, nil
    if callback then callback() end
end

--- 清档专用硬清理，不结算旧波次，也不执行旧会话退出回调。
function TowerScene.resetToDefault()
    destroySettlementRoot()
    TowerBuffSidebar.reset()
    state.active = false
    state.phase = "idle"
    state.onClose, state.sendAction, state.onCleanup = nil, nil, nil
    state.cleanupDone = true
    state.floorReceipts, state.runRewards = {}, {}
    state.runPlayerExp, state.runHeroExpTotal = 0, 0
    state.settlementRequest, state.settlementElapsed = nil, 0
    state.startFloor, state.endFloor = 1, 5
    state.allies, state.teamAllies = nil, nil
    state.buffIds, state.floorHeroDamage = {}, {}
    state.pendingBuffChoices, state.serverFloorResult = nil, nil
    state.pendingSelection = nil
    state.choiceQueue, state.unappliedBuffIds = {}, {}
    state.runId = nil
    state.errorMessage, state.errorLogged = nil, false
    state.floor, state.wave, state.monsterLevel = 1, 1, 1
    state.totalElapsedSecs, state.currentWaveStartTime = 0, 0
    TowerBuffPick.close()
    TowerBuffPick.setSendAction(nil)
    BattleResultPanel.resetToDefault()
    TowerTriBattle.forceClose()
    TowerBuffRuntime.cleanup()
    print("[TowerBattleScene] resetToDefault: discarded battle/buffs/callbacks")
end

--- 内部：用指定怪物列表打开一波战斗
function TowerScene._openWaveBattle(monsters)
    state.currentWaveStartTime = time.elapsedTime or 0
    -- 择契与当前波分离：不重置敌人、计时、投射物或机制计数。
    local okBuff, buffErr = pcall(function()
        if #state.unappliedBuffIds > 0 then
            applyBuffsToAllTeams(state.unappliedBuffIds)
            state.unappliedBuffIds = {}
        end
        TowerBuffRuntime.initMechanics(state.buffIds)
    end)
    if not okBuff then
        print("[TowerBattleScene] ERROR prepare wave buffs: " .. tostring(buffErr))
        state.phase = "error"
        state.errorMessage = "通天塔强化生效失败，请退出后重试"
        return false
    end
    local rageAdvance = TowerBuffRuntime.getRageAdvance()
    local data = {
        dungeonId    = "babel_tower",
        runId        = state.runId,
        floor        = state.floor,
        wave         = 1,
        monsterLevel = state.monsterLevel,
        monsters     = monsters or {},
        classBonus   = "",
        classBonusValue = 0,
        rageTime     = math.max(5, TowerConfig.RAGE_TIME - rageAdvance),
        rageAtkBonus = TowerConfig.RAGE_ATK_BONUS,
        superRageTime = math.max(10, TowerConfig.SUPER_RAGE_TIME - rageAdvance),
        superRageAtkBonus = TowerConfig.SUPER_RAGE_ATK_BONUS,
        superRageDmgBonus = 0.30,
        allyRageDmgBonus  = 0.30,
        allySuperRageDmgBonus = 0.30,
    }

    print("[TowerBattleScene] _openWaveBattle: teams allies="
        .. tostring(#(state.teamAllies[1] or {})) .. "/"
        .. tostring(#(state.teamAllies[2] or {})) .. "/"
        .. tostring(#(state.teamAllies[3] or {}))
        .. " monsters=" .. tostring(monsters and #monsters or 0))

    local ok, err = pcall(function()
        TowerTriBattle.open({
            teamAllies = state.teamAllies,
            data       = data,
            onClose    = function()
                print("[TowerBattleScene] onClose triggered, phase=" .. tostring(state.phase))
                if state.phase == "battle" or state.phase == "error" then
                    TowerScene.close()
                end
            end,
        })
    end)
    if not ok then
        print("[TowerBattleScene] ERROR opening TowerTriBattle: " .. tostring(err))
        pcall(TowerTriBattle.forceClose)
        state.phase = "error"
        state.errorMessage = "通天塔战斗初始化失败，请退出后重试"
        return false
    end
    if not TowerTriBattle.isOpen() then
        print("[TowerBattleScene] ERROR TowerTriBattle stayed closed after open")
        state.phase = "error"
        state.errorMessage = "通天塔战斗场景未能打开，请退出后重试"
        return false
    end
    print("[TowerBattleScene] _openWaveBattle done, TowerTriBattle.isOpen=" .. tostring(TowerTriBattle.isOpen()))
    return true
end

-- ======================== 波次胜利处理 ========================

local function openQueuedChoice(visible)
    local pending = state.choiceQueue[1]
    state.pendingSelection = pending
    if not pending then TowerBuffPick.close(); return end
    TowerBuffPick.open(pending.floor, pending.data.buffChoices, function(buffId, requestId)
        if state.pendingSelection ~= pending or pending.buffId or state.phase ~= "battle" then return false end
        pending.buffId, pending.requestId = buffId, requestId
        return true
    end, { runId = pending.runId, selectionId = pending.selectionId,
        floor = pending.floor, wave = pending.wave }, TowerScene.onPickBuffResult)
    if not visible then TowerBuffPick.hide() end
end

--- 同一已清层结算重试；sender失败/超时仅释放本次请求，不关闭或开新层。
function TowerScene.retryFloorWin()
    if not state.active or (state.phase ~= "floor_win" and state.phase ~= "settlement_retry")
        or state.serverFloorResult or state.settlementRequest then return false end
    state.settlementSerial = state.settlementSerial + 1
    local request = { floor = state.floor, wave = 1, runId = state.runId,
        requestId = state.sessionVersion .. ":floor:" .. state.settlementSerial }
    state.settlementRequest, state.settlementElapsed = request, 0
    state.phase, state.errorMessage = "floor_win", nil
    local called, sent = pcall(function()
        if not state.sendAction then return false end
        return state.sendAction(Protocol.ACTION_TYPES.TOWER_FLOOR_WIN, request)
    end)
    if (not called or sent == false) and state.settlementRequest == request then
        state.settlementRequest = nil
        state.phase = "settlement_retry"
        state.errorMessage = "结算请求未完成，点击重试同层奖励"
    end
    return called and sent ~= false
end

--- 清波与结算分离，收到成功逐层结算前不生成/开下一层。
function TowerScene.onWaveWinResult(data)
    if not state.active or state.phase ~= "battle" or not data then return false end
    if data.floor ~= state.floor or data.wave ~= 1 or data.runId ~= state.runId then return false end
    if data.success ~= true or data.floorCleared ~= true then return false end
    local _, _, waveElapsed = DungeonBattle.getResultState()
    if waveElapsed and waveElapsed > 0 then
        state.totalElapsedSecs = state.totalElapsedSecs + waveElapsed
    else
        state.totalElapsedSecs = state.totalElapsedSecs + math.max(0, (time.elapsedTime or 0) - state.currentWaveStartTime)
    end
    accumulateCurrentWaveStats()
    -- 保留FIFO选择和正在等待的选择回执，不跨层丢弃或重新open Panel。
    state.phase = "floor_win"
    TowerTriBattle.forceClose()
    TowerScene.retryFloorWin()
    return true
end

--- 成功回执只消费当前择契，不负责推进或重开战斗。
function TowerScene.onPickBuffResult(data)
    local pending = state.pendingSelection
    if not state.active or (state.phase ~= "battle" and state.phase ~= "floor_win"
        and state.phase ~= "settlement_retry") or state.serverFloorResult
        or not pending or not pending.buffId or not data then return end
    if data.runId ~= pending.runId or data.selectionId ~= pending.selectionId
        or data.floor ~= pending.floor or data.wave ~= pending.wave or data.buffId ~= pending.buffId
        or data.requestId ~= pending.requestId then
        print("[TowerBattleScene] ignore unmatched PickBuff request=" .. tostring(data.requestId))
        return
    end
    if data.success ~= true then
        TowerBuffPick.setPending(false, pending.requestId, data.retryOnly)
        pending.buffId = nil
        pending.requestId = nil
        print("[TowerBattleScene] TOWER_PICK_BUFF failed: " .. tostring(data.reason))
        return
    end
    -- 必须恰好追加当前选择的一份权威快照，不能只靠 buffId 回执推进。
    local ids = data.buffs
    if type(ids) ~= "table" or #ids ~= #state.buffIds + 1 or ids[#ids] ~= pending.buffId
        or data.totalBuffs ~= #ids or data.nextWave ~= 1
        or data.nextFloor ~= pending.data.nextFloor then
        print("[TowerBattleScene] ignore incomplete PickBuff snapshot request=" .. tostring(data.requestId))
        return
    end
    for i, id in ipairs(state.buffIds) do if ids[i] ~= id then return end end
    local buffId = pending.buffId
    local visible = TowerBuffPick.isVisible()
    state.buffIds = copyBuffIds(ids)
    table.remove(state.choiceQueue, 1)
    state.pendingSelection = nil -- 先消费身份，迟到回执不能重复加入待应用列表。
    state.pendingBuffChoices = nil
    state.unappliedBuffIds[#state.unappliedBuffIds + 1] = buffId
    TowerBuffPick.close()
    openQueuedChoice(visible)
    print("[TowerBattleScene] accepted PickBuff selection=" .. pending.selectionId
        .. " request=" .. tostring(data.requestId) .. " total=" .. #state.buffIds
        .. " battle wave unchanged=" .. state.wave)
end

local function accumulateRewards(data)
    state.runPlayerExp = state.runPlayerExp + (data.playerExp or 0)
    state.runHeroExpTotal = state.runHeroExpTotal + (data.heroExpTotal or 0)
    for _, reward in ipairs(data.rewards or {}) do
        local item = copy(reward)
        if item.type == "diamond" then
            local found = false
            for _, existing in ipairs(state.runRewards) do
                if existing.type == "diamond" then
                    existing.amount = existing.amount + (item.amount or 0)
                    found = true
                    break
                end
            end
            if not found then state.runRewards[#state.runRewards + 1] = item end
        else
            state.runRewards[#state.runRewards + 1] = item
        end
    end
end

--- 只消费匹配当前已清层请求的回执，重复/过期/旧run均不能推进或重复汇总。
function TowerScene.onFloorWinResult(data)
    local request = state.settlementRequest
    if not state.active or (state.phase ~= "floor_win" and state.phase ~= "settlement_retry")
        or not request or not data or data.floor ~= request.floor or data.runId ~= request.runId
        or data.requestId ~= request.requestId or data.wave ~= 1
        or state.floorReceipts[data.floor] then return false end
    if data.success ~= true then
        state.settlementRequest = nil
        state.phase = "settlement_retry"
        state.errorMessage = data.reason or "结算未保存，点击重试同层奖励"
        print("[TowerBattleScene] FloorWin retry floor=" .. state.floor .. " reason=" .. tostring(data.reason))
        return false
    end
    if type(data.rewards) ~= "table" or type(data.continueRun) ~= "boolean" then return false end
    if data.continueRun then
        if state.floor >= state.endFloor or data.nextFloor ~= state.floor + 1
            or type(data.monsters) ~= "table" or type(data.monsterLevel) ~= "number"
            or not data.selectionId or type(data.buffChoices) ~= "table" then return false end
    elseif state.floor ~= state.endFloor then return false end
    -- 在推进/打开战斗的同步回调前消费身份与奖励。
    state.floorReceipts[data.floor] = copy(data)
    state.settlementRequest, state.settlementElapsed = nil, 0
    accumulateRewards(data)
    if data.continueRun then
        local first = #state.choiceQueue == 0
        if #data.buffChoices > 0 then
            state.choiceQueue[#state.choiceQueue + 1] = { runId = data.runId,
                selectionId = data.selectionId, floor = data.floor, wave = 1, data = copy(data) }
        end
        state.floor, state.wave, state.monsterLevel = data.nextFloor, 1, data.monsterLevel
        state.phase = "battle"
        -- 不使用FloorWin的buffs覆盖Scene：未送达Pick回执尚不能提前生效。
        if not TowerScene._openWaveBattle(data.monsters) then return true end
        if first and #state.choiceQueue > 0 then openQueuedChoice(true) end
        print("[TowerBattleScene] continued floor=" .. state.floor .. " wave=1")
    else
        state.serverFloorResult = copy(data)
        clearChoices()
        cleanupRun()
        TowerBuffRuntime.cleanup()
        local rewards = copy(state.runRewards)
        rewards[#rewards + 1] = { type = "player_exp", name = "远征经验", amount = state.runPlayerExp }
        rewards[#rewards + 1] = { type = "hero_exp", name = "队员经验", amount = state.runHeroExpTotal }
        BattleResultPanel.show({ layout = "tower", floor = state.floor, wave = 1,
            isWin = true, elapsedSecs = state.totalElapsedSecs, heroStats = buildFloorHeroStats(),
            rewards = rewards, onClose = function() TowerScene.close() end })
    end
    return true
end

-- ======================== 渲染（仅在buff选择时绘制） ========================

local function settlementFit(width, height)
    local scale = math.min(width / 1440, height / 760)
    return scale, (width - 1440 * scale) * .5, (height - 760 * scale) * .5
end

local function drawSettlement(vg, width, height)
    local retry = state.phase == "settlement_retry" and state.settlementRequest == nil
    local key = tostring(retry) .. ":" .. state.floor .. ":" .. tostring(state.errorMessage)
    if key ~= settlementKey then
        destroySettlementRoot()
        Surface.init()
        local function label(text, top, size)
            return UI.Label { text = text, position = "absolute", left = 48, top = top,
                width = 1344, height = 100, fontSize = size, fontFamily = "sans", fontWeight = "normal",
                fontColor = { 231, 219, 195 }, textAlign = "center", verticalAlign = "middle",
                whiteSpace = "normal", maxLines = 2, pointerEvents = "none" }
        end
        settlementRoot = UI.Panel { width = 1440, height = 760,
            backgroundColor = { 20, 16, 16, 248 }, pointerEvents = "none", children = {
                label("通天塔 · 第" .. state.floor .. "层", 96, 42),
                label(state.errorMessage or "正在提交本层奖励，请稍候", 246, 28),
                label(retry and "返回整理后重挑本组，仍保留本层开奖结果" or "奖励提交成功后才会开始下一层", 382, 25),
                UI.Button { text = "重试本层", position = "absolute", left = 300, top = 556,
                    width = 360, height = 88, disabled = not retry, fontSize = 28,
                    fontFamily = "sans", fontWeight = "normal", pointerEvents = "none" },
                UI.Button { text = "返回整理", position = "absolute", left = 780, top = 556,
                    width = 360, height = 88, disabled = not retry, variant = "secondary", fontSize = 28,
                    fontFamily = "sans", fontWeight = "normal", pointerEvents = "none" },
            } }
        settlementKey = key
    end
    local scale, ox, oy = settlementFit(width, height)
    if scale <= 0 or not settlementRoot then return end
    nvgSave(vg)
    nvgTranslate(vg, ox, oy)
    nvgScale(vg, scale, scale)
    Surface.draw(settlementRoot, vg, 1440, 760)
    nvgRestore(vg)
end

local function drawErrorFallback(vg, width, height)
    local settling = state.phase == "settlement_retry" or state.phase == "floor_win"
    local msg = state.errorMessage or (settling and "正在提交本层奖励，请稍候" or "通天塔战斗状态异常，请退出后重试")
    local cx, cy = width * 0.5, height * 0.5
    local fontScale = math.min(width / 1920, height / 1080)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(20, 16, 16, 235))
    nvgFill(vg)
    drawTextStroke(vg, cx, cy - 140 * fontScale, settling and "通天塔逐层结算" or "通天塔战斗异常", 60 * fontScale,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 220, 180, 5,
        { strokeColor = { 40, 20, 20 } })
    drawTextStroke(vg, cx, cy - 40 * fontScale, msg, 38 * fontScale,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4,
        { strokeColor = { 40, 20, 20 } })
    drawTextStroke(vg, cx, cy + 40 * fontScale, "第" .. tostring(state.floor) .. "层", 32 * fontScale,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 210, 120, 3,
        { strokeColor = { 40, 20, 20 } })
    local hint = settling and (state.settlementRequest and "奖励提交中，下一层尚未开始" or "点击屏幕重试本层结算（不重新开奖）")
        or "点击屏幕返回副本界面"
    drawTextStroke(vg, cx, cy + 130 * fontScale, hint, 34 * fontScale,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 210, 230, 255, 3,
        { strokeColor = { 40, 20, 20 } })
end

function TowerScene.draw(vg, logicalW, logicalH)
    if not state.active then return end
    logicalW = logicalW or 1080
    logicalH = logicalH or 2400

    -- 侧栏在战斗/确认/择契模态之下，保持TaskPage等奖励宿主的后续覆盖顺序。
    TowerBuffSidebar.draw(vg, logicalW, logicalH, TowerScene.getDisplayState())
    local triOpen = TowerTriBattle.isOpen()
    if triOpen then
        local okDraw, drawErr = xpcall(function()
            TowerTriBattle.draw(vg, logicalW, logicalH)
        end, debug.traceback)
        if not okDraw then
            print("[TowerBattleScene] ERROR TowerTriBattle.draw failed floor=" .. tostring(state.floor)
                .. " wave=" .. tostring(state.wave)
                .. " err=" .. tostring(drawErr))
            state.phase = "error"
            state.errorMessage = "通天塔战斗绘制异常，请退出后重试"
            state.errorLogged = true
            triOpen = false
        end
    end

    if state.phase == "battle" then
        if not triOpen then
            if not state.errorLogged then
                print("[TowerBattleScene] ERROR battle phase but TowerTriBattle is closed floor=" .. tostring(state.floor)
                    .. " wave=" .. tostring(state.wave))
                state.errorLogged = true
            end
            state.phase = "error"
            state.errorMessage = "通天塔战斗画面丢失，请退出后重试"
            drawErrorFallback(vg, logicalW, logicalH)
        end
    elseif state.phase == "floor_win" then
        if state.serverFloorResult then BattleResultPanel.draw(vg, logicalW, logicalH)
        else drawSettlement(vg, logicalW, logicalH) end
    elseif state.phase == "settlement_retry" then
        drawSettlement(vg, logicalW, logicalH)
    elseif state.phase == "error" then
        drawErrorFallback(vg, logicalW, logicalH)
    end
    if state.phase == "battle" and not BattleResultPanel.isOpen()
        and not TowerTriBattle.isConfirmationOpen() and TowerBuffPick.isVisible() then
        TowerBuffPick.draw(vg, logicalW, logicalH)
    end
end

-- ======================== 更新 ========================

function TowerScene.update(dt)
    if not state.active then return end

    if state.phase == "battle" then
        if not TowerTriBattle.isOpen() then
            if not state.errorLogged then
                print("[TowerBattleScene] ERROR update found battle phase but TowerTriBattle is closed floor=" .. tostring(state.floor)
                    .. " wave=" .. tostring(state.wave))
                state.errorLogged = true
            end
            state.phase = "error"
            state.errorMessage = "通天塔战斗画面丢失，请退出后重试"
            return
        end
        local ok, err = xpcall(function()
            TowerTriBattle.update(dt)
        end, debug.traceback)
        if not ok then
            print("[TowerBattleScene] ERROR TowerTriBattle.update failed floor=" .. tostring(state.floor)
                .. " wave=" .. tostring(state.wave)
                .. " buffs=" .. tostring(table.concat(state.buffIds or {}, ","))
                .. " err=" .. tostring(err))
            state.phase = "error"
            state.errorMessage = "通天塔战斗逻辑异常，请退出后重试"
            TowerTriBattle.forceClose()
        end
        TowerBuffPick.update(dt)
        if BattleResultPanel.isOpen() then
            -- 失败面板出现即丢弃本局暗契，不等玩家点关闭才清Service。
            clearChoices()
            cleanupRun()
            TowerBuffRuntime.cleanup()
        end
    elseif state.phase == "floor_win" or state.phase == "settlement_retry" then
        if state.serverFloorResult then BattleResultPanel.update(dt)
        else
            TowerBuffPick.update(dt)
            if state.settlementRequest then
                state.settlementElapsed = state.settlementElapsed + dt
                if state.settlementElapsed >= 5 then
                    state.settlementRequest = nil
                    state.phase = "settlement_retry"
                    state.errorMessage = "结算回执超时，点击重试同层奖励"
                end
            end
        end
    end
end

-- ======================== 输入 ========================

function TowerScene.handleClick(dx, dy, logicalW, logicalH)
    if not state.active then return false end
    logicalW = logicalW or 1080
    logicalH = logicalH or 2400

    if state.phase == "floor_win" and BattleResultPanel.isOpen() then
        BattleResultPanel.handleInput(dx, dy)
        return true
    elseif state.phase == "settlement_retry" then
        local scale, ox, oy = settlementFit(logicalW, logicalH)
        if scale > 0 and state.settlementRequest == nil then
            local x, y = (dx - ox) / scale, (dy - oy) / scale
            if y >= 556 and y <= 644 then
                if x >= 300 and x <= 660 then TowerScene.retryFloorWin()
                elseif x >= 780 and x <= 1140 then TowerScene.close() end
            end
        end
        return true
    elseif state.phase == "floor_win" then
        return true
    elseif state.phase == "error" then
        TowerScene.close()
        return true
    elseif state.phase == "battle" then
        if TowerTriBattle.isConfirmationOpen() or BattleResultPanel.isOpen() then
            TowerTriBattle.handleClick(dx, dy, logicalW, logicalH)
        elseif TowerBuffPick.isVisible() then
            TowerBuffPick.handleClick(dx, dy, logicalW, logicalH)
        else
            local action = TowerBuffSidebar.handleClick(dx, dy, logicalW, logicalH)
            if action == "resume_pick" then
                TowerBuffPick.show()
            elseif action == "retreat" then
                TowerTriBattle.requestRetreat()
            elseif action == "toggle_buffs" then
                TowerBuffSidebar.toggleCollapsed()
            else
                local layout = TowerLayout.compute(logicalW, logicalH)
                if TowerLayout.panelAt(layout, dx, dy) == "center" then
                    TowerTriBattle.handleClick(dx, dy, logicalW, logicalH)
                end
            end
        end
        return true
    end

    return true
end

local function sidebarInputAllowed()
    return state.active and (state.phase == "battle" or state.phase == "buff_pick")
        and not TowerBuffPick.isVisible() and not TowerTriBattle.isConfirmationOpen()
        and not BattleResultPanel.isOpen()
end

function TowerScene.handleScroll(wheel, x, y, width, height)
    if not state.active then return false end
    if sidebarInputAllowed() then TowerBuffSidebar.handleScroll(wheel, x, y, width, height) end
    return true
end

function TowerScene.handleDragBegin(x, y, width, height)
    TowerBuffSidebar.dragEnd()
    if sidebarInputAllowed() then TowerBuffSidebar.dragBegin(x, y, width, height) end
end

function TowerScene.handleDragMove(x, y, width, height)
    if sidebarInputAllowed() then TowerBuffSidebar.dragMove(x, y, width, height)
    else TowerBuffSidebar.dragEnd() end
end

function TowerScene.handleDragEnd()
    TowerBuffSidebar.dragEnd()
end

return TowerScene
