-- ============================================================================
-- TowerBattleScene - 通天塔战斗场景（状态管理器）
-- 三行攻坚：复用 TowerTriBattle 渲染三队同波，管理 10 波 + 波间强化
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
    unappliedBuffIds = {}, -- 战斗中择契不重开当前波，新强化在下一波开始应用。

    -- 阶段
    phase    = "idle",  -- idle / battle / floor_win / error

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
        monsterLevel = state.monsterLevel, buffIds = copyBuffIds(state.buffIds),
        pendingChoices = #state.choiceQueue,
        inputModal = TowerTriBattle.isConfirmationOpen() or BattleResultPanel.isOpen() }
end

function TowerScene.getPresentationKey()
    return state.sessionVersion .. ":" .. tostring(state.active) .. ":" .. tostring(state.runId)
        .. ":" .. state.floor .. ":" .. state.wave
        .. ":" .. state.phase .. ":" .. TowerBuffPick.getPresentationKey()
        .. ":" .. TowerTriBattle.getPresentationKey()
end

function TowerScene.getLayout(width, height)
    return TowerLayout.compute(width, height)
end

--- 打开通天塔战斗（由 DungeonPage 在 TOWER_CHALLENGE 成功后调用）
---@param opts table { teamAllies, allies, data, sendAction, onClose }
function TowerScene.open(opts)
    state.sessionVersion = state.sessionVersion + 1
    TowerBuffSidebar.reset()
    state.active = true
    state.phase  = "battle"
    state.floor  = opts.data.floor or 1
    state.wave   = opts.data.wave or 1
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
    TowerBuffSidebar.reset()
    state.active = false
    state.phase = "idle"
    state.pendingSelection = nil
    state.pendingBuffChoices = nil
    state.choiceQueue, state.unappliedBuffIds = {}, {}
    state.runId = nil
    TowerBuffPick.close()
    state.errorMessage = nil
    state.errorLogged = false
    pcall(TowerTriBattle.forceClose)
    TowerBuffRuntime.cleanup()
    if state.onClose then
        state.onClose()
    end
end

--- 清档专用硬清理，不结算旧波次，也不执行旧会话退出回调。
function TowerScene.resetToDefault()
    TowerBuffSidebar.reset()
    state.active = false
    state.phase = "idle"
    state.onClose, state.sendAction = nil, nil
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
        floor        = state.floor,
        wave         = state.wave,
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
    TowerBuffPick.open(state.floor, pending.data.buffChoices, function(buffId, requestId)
        if state.pendingSelection ~= pending or pending.buffId or state.phase ~= "battle" then return false end
        pending.buffId, pending.requestId = buffId, requestId
        return true
    end, { runId = pending.runId, selectionId = pending.selectionId,
        floor = pending.floor, wave = pending.wave }, TowerScene.onPickBuffResult)
    if not visible then TowerBuffPick.hide() end
end

--- 由 DungeonPage.onActionResult 在收到 TOWER_WAVE_WIN 时调用
function TowerScene.onWaveWinResult(data)
    if not state.active or state.phase ~= "battle" or not data then return end
    if data.floor ~= nil and data.floor ~= state.floor then return end
    if data.wave ~= nil and data.wave ~= state.wave then return end
    if state.runId and data.runId ~= state.runId then return end
    if data.success == false then
        print("[TowerBattleScene] TOWER_WAVE_WIN failed: " .. tostring(data.reason))
        return
    end
    if not data.floorCleared and (not data.runId or not data.selectionId
        or data.nextWave ~= state.wave + 1) then return end

    local _, _, waveElapsed = DungeonBattle.getResultState()
    if waveElapsed and waveElapsed > 0 then
        state.totalElapsedSecs = state.totalElapsedSecs + waveElapsed
    else
        local now = time.elapsedTime or 0
        if state.currentWaveStartTime and state.currentWaveStartTime > 0 then
            state.totalElapsedSecs = state.totalElapsedSecs + math.max(0, now - state.currentWaveStartTime)
            state.currentWaveStartTime = now
        end
    end

    accumulateCurrentWaveStats()

    state.pendingBuffChoices = data.buffChoices

    if data.floorCleared then
        TowerBuffPick.close()
        state.choiceQueue, state.unappliedBuffIds = {}, {}
        state.pendingSelection, state.pendingBuffChoices = nil, nil
        TowerTriBattle.forceClose()
        state.phase = "floor_win" -- 本地桥可同步结算，先切 phase 防重复 WaveWin 重入。
        if state.sendAction then
            state.sendAction(Protocol.ACTION_TYPES.TOWER_FLOOR_WIN, { floor = state.floor })
        end
    else
        local pending = { runId = data.runId, selectionId = data.selectionId,
            floor = state.floor, wave = state.wave, data = data }
        local first = #state.choiceQueue == 0
        state.choiceQueue[#state.choiceQueue + 1] = pending
        TowerTriBattle.forceClose()
        state.wave = data.nextWave
        if not TowerScene._openWaveBattle(data.monsters) then return end
        -- 第一组提示一次；收起后后续组只累计，不打断正在进行的战斗。
        if first then openQueuedChoice(true) end
    end
end

--- 成功回执只消费当前择契，不负责推进或重开战斗。
function TowerScene.onPickBuffResult(data)
    local pending = state.pendingSelection
    if not state.active or state.phase ~= "battle" or not pending or not pending.buffId or not data then return end
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
        or data.totalBuffs ~= #ids or data.nextWave ~= pending.data.nextWave then
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

--- 由 DungeonPage.onActionResult 在收到 TOWER_FLOOR_WIN 时调用
function TowerScene.onFloorWinResult(data)
    if not state.active then return end
    if not data or data.success == false then
        state.phase = "error"
        state.errorMessage = (data and data.reason) or "通天塔结算失败，请退出后重试"
        print("[TowerBattleScene] TOWER_FLOOR_WIN failed: " .. tostring(state.errorMessage))
        return
    end
    state.serverFloorResult = data
    -- 显示结算面板
    local rewards = data and data.rewards or {}
    if (#rewards == 0) and data and data.diamondReward and data.diamondReward > 0 then
        rewards[#rewards + 1] = { type = "diamond", amount = data.diamondReward }
    end
    BattleResultPanel.show({
        layout = "tower", floor = state.floor,
        isWin = true,
        elapsedSecs = state.totalElapsedSecs,
        heroStats = buildFloorHeroStats(),
        rewards = rewards,
        onClose = function()
            TowerScene.close()
        end,
    })
end

-- ======================== 渲染（仅在buff选择时绘制） ========================

local function drawErrorFallback(vg, width, height)
    local msg = state.errorMessage or "通天塔战斗状态异常，请退出后重试"
    local cx, cy = width * 0.5, height * 0.5
    local fontScale = math.min(width / 1920, height / 1080)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(20, 16, 16, 235))
    nvgFill(vg)
    drawTextStroke(vg, cx, cy - 140 * fontScale, "通天塔战斗异常", 60 * fontScale,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 220, 180, 5,
        { strokeColor = { 40, 20, 20 } })
    drawTextStroke(vg, cx, cy - 40 * fontScale, msg, 38 * fontScale,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4,
        { strokeColor = { 40, 20, 20 } })
    drawTextStroke(vg, cx, cy + 40 * fontScale, "floor=" .. tostring(state.floor) .. " wave=" .. tostring(state.wave), 32 * fontScale,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 210, 120, 3,
        { strokeColor = { 40, 20, 20 } })
    drawTextStroke(vg, cx, cy + 130 * fontScale, "点击屏幕返回副本界面", 34 * fontScale,
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
        BattleResultPanel.draw(vg, logicalW, logicalH)
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
            TowerBuffPick.close()
            state.choiceQueue, state.unappliedBuffIds = {}, {}
            state.pendingSelection = nil
        end
    elseif state.phase == "floor_win" then
        BattleResultPanel.update(dt)
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
