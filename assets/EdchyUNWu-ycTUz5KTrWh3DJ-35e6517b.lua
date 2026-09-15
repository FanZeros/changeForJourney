-- ============================================================================
-- TowerBattleScene - 通天塔战斗场景（状态管理器）
-- 复用 DungeonBattleScene 做渲染和战斗，管理10波流程+波间强化选择
-- 不直接渲染，通过 DungeonBattleScene 显示战斗画面
-- ============================================================================

local DungeonBattleScene = require("ui.DungeonBattleScene")
local DungeonBattle      = require("ui.DungeonBattle")
local TowerBuffPick      = require("ui.TowerBuffPick")
local TowerBuffRuntime   = require("systems.TowerBuffRuntime")
local TowerConfig        = require("config.TowerConfig")
local Protocol           = require("shared.Protocol")
local BattleResultPanel  = require("ui.BattleResultPanel")
local BattleDraw         = require("ui.BattleDraw")
local BattleStats        = require("systems.BattleStats")
local HeroConfig         = require("config.HeroConfig")

local drawTextStroke = BattleDraw.drawTextStroke

local TowerScene = {}

-- ======================== 状态 ========================

local state = {
    active = false,

    -- 层/波
    floor     = 1,
    wave      = 1,
    monsterLevel = 1,

    -- 强化
    buffIds  = {},
    pendingBuffChoices = nil,

    -- 阶段
    phase    = "idle",  -- idle / battle / buff_pick / floor_win / error

    -- 异常兜底
    errorMessage = nil,
    errorLogged  = false,

    -- 回调
    onClose    = nil,
    sendAction = nil,
    allies     = nil,   -- 己方单位引用（跨波保持）

    -- 服务端结果
    serverFloorResult = nil,
    totalElapsedSecs = 0,
    currentWaveStartTime = 0,
    floorHeroDamage = {},
}

local function resetFloorStats()
    state.floorHeroDamage = {}
end

local function accumulateCurrentWaveStats()
    local waveStats = BattleStats.buildHeroDamageStats(state.allies, HeroConfig.HEROES)
    for _, hero in ipairs(waveStats) do
        local heroId = hero.heroId
        if heroId then
            state.floorHeroDamage[heroId] = (state.floorHeroDamage[heroId] or 0) + (hero.totalDamage or 0)
        end
    end
end

local function buildFloorHeroStats()
    local heroStats = {}
    for _, unit in ipairs(state.allies or {}) do
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

-- ======================== Public API ========================

function TowerScene.isActive()
    return state.active
end

--- 打开通天塔战斗（由 DungeonPage 在 TOWER_CHALLENGE 成功后调用）
---@param opts table { allies, data, sendAction, onClose }
function TowerScene.open(opts)
    state.active = true
    state.phase  = "battle"
    state.floor  = opts.data.floor or 1
    state.wave   = opts.data.wave or 1
    state.monsterLevel = opts.data.monsterLevel or 1
    state.buffIds = opts.data.buffs or {}
    state.onClose = opts.onClose
    state.sendAction = opts.sendAction
    state.allies = opts.allies
    state.pendingBuffChoices = nil
    state.serverFloorResult = nil
    state.totalElapsedSecs = 0
    state.currentWaveStartTime = time.elapsedTime or 0
    resetFloorStats()
    state.errorMessage = nil
    state.errorLogged = false

    -- 连接 sendAction 到 TowerBuffPick（用于选强化时通知服务端去重）
    TowerBuffPick.setSendAction(state.sendAction)

    local okBuff, buffErr = pcall(function()
        -- 初始化强化运行时
        TowerBuffRuntime.applyStatBuffs(state.allies, state.buffIds)
        TowerBuffRuntime.initMechanics(state.buffIds)
    end)
    if not okBuff then
        print("[TowerBattleScene] ERROR init tower buffs: " .. tostring(buffErr))
        state.phase = "error"
        state.errorMessage = "通天塔强化初始化失败，请退出后重试"
        return
    end

    -- 打开 DungeonBattleScene 进行第一波战斗
    local okOpen = TowerScene._openWaveBattle(opts.data.monsters)
    if not okOpen then
        return
    end

    print("[TowerBattleScene] open floor=" .. state.floor .. " wave=" .. state.wave)
end

function TowerScene.close()
    state.active = false
    state.phase = "idle"
    state.errorMessage = nil
    state.errorLogged = false
    TowerBuffRuntime.cleanup()
    if state.onClose then
        state.onClose()
    end
end

--- 内部：用指定怪物列表打开一波战斗
function TowerScene._openWaveBattle(monsters)
    state.currentWaveStartTime = time.elapsedTime or 0
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

    print("[TowerBattleScene] _openWaveBattle: allies=" .. tostring(state.allies and #state.allies)
        .. " monsters=" .. tostring(monsters and #monsters or 0))

    local ok, err = pcall(function()
        DungeonBattleScene.open({
            allies = state.allies,
            data   = data,
            dungeonId = "babel_tower",
            onClose = function()
                -- DungeonBattleScene 正常关闭（非 forceClose）时，关闭通天塔
                -- 触发场景：用户撤退 / 己方全灭 / 意外关闭
                -- forceClose（波次切换）不会触发此回调
                print("[TowerBattleScene] onClose triggered, phase=" .. tostring(state.phase))
                TowerScene.close()
            end,
        })
    end)
    if not ok then
        print("[TowerBattleScene] ERROR opening DungeonBattleScene: " .. tostring(err))
        pcall(DungeonBattleScene.forceClose)
        state.phase = "error"
        state.errorMessage = "通天塔战斗初始化失败，请退出后重试"
        return false
    end
    if not DungeonBattleScene.isOpen() then
        print("[TowerBattleScene] ERROR DungeonBattleScene stayed closed after open")
        state.phase = "error"
        state.errorMessage = "通天塔战斗场景未能打开，请退出后重试"
        return false
    end
    print("[TowerBattleScene] _openWaveBattle done, DungeonBattleScene.isOpen=" .. tostring(DungeonBattleScene.isOpen()))
    return true
end

-- ======================== 波次胜利处理 ========================

--- 由 DungeonPage.onActionResult 在收到 TOWER_WAVE_WIN 时调用
function TowerScene.onWaveWinResult(data)
    if not state.active then return end
    if not data then return end

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
        -- 最后一波：整层通关，直接结算，不再弹三选一强化
        DungeonBattleScene.forceClose()
        -- 报告整层通关
        if state.sendAction then
            state.sendAction(Protocol.ACTION_TYPES.TOWER_FLOOR_WIN, { floor = state.floor })
        end
        state.phase = "floor_win"
    else
        -- 非最后波：选强化后进入下一波（不 forceClose，保留背景）
        state.phase = "buff_pick"
        TowerBuffPick.open(state.floor, data.buffChoices, function(buffId)
            state.buffIds[#state.buffIds + 1] = buffId
            -- 关闭当前波次战斗
            DungeonBattleScene.forceClose()
            local okBuff, buffErr = pcall(function()
                -- 应用新强化
                TowerBuffRuntime.applyStatBuffs(state.allies, { buffId })
                TowerBuffRuntime.initMechanics(state.buffIds)
            end)
            if not okBuff then
                print("[TowerBattleScene] ERROR apply picked buff " .. tostring(buffId) .. ": " .. tostring(buffErr))
                state.phase = "error"
                state.errorMessage = "通天塔强化生效失败，请退出后重试"
                return
            end
            -- 波间回复10% HP
            for _, unit in ipairs(state.allies) do
                if unit.hp > 0 and unit.attrs then
                    local heal = math.floor(unit.maxHp * 0.10)
                    unit.attrs:heal(heal)
                    unit.hp = unit.attrs:get(require("systems.AttributeDef").HP)
                    if unit.hp > unit.maxHp then unit.hp = unit.maxHp end
                end
            end
            -- 开始下一波
            state.wave = data.nextWave
            state.phase = "battle"
            local okOpen = TowerScene._openWaveBattle(data.monsters)
            if not okOpen then
                return
            end
        end)
    end
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

local function drawErrorFallback(vg)
    local msg = state.errorMessage or "通天塔战斗状态异常，请退出后重试"
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(20, 16, 16, 235))
    nvgFill(vg)
    drawTextStroke(vg, 540, 1060, "通天塔战斗异常", 60,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 220, 180, 5,
        { strokeColor = { 40, 20, 20 } })
    drawTextStroke(vg, 540, 1160, msg, 38,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4,
        { strokeColor = { 40, 20, 20 } })
    drawTextStroke(vg, 540, 1240, "floor=" .. tostring(state.floor) .. " wave=" .. tostring(state.wave), 32,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 210, 120, 3,
        { strokeColor = { 40, 20, 20 } })
    drawTextStroke(vg, 540, 1330, "点击屏幕返回副本界面", 34,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 210, 230, 255, 3,
        { strokeColor = { 40, 20, 20 } })
end

function TowerScene.draw(vg)
    if not state.active then return end

    local dungeonOpen = DungeonBattleScene.isOpen()
    -- 渲染 DungeonBattleScene 作为背景（战斗中实时/选强化时冻结）
    if dungeonOpen then
        local okDraw, drawErr = xpcall(function()
            DungeonBattleScene.draw(vg)
        end, debug.traceback)
        if not okDraw then
            print("[TowerBattleScene] ERROR DungeonBattleScene.draw failed floor=" .. tostring(state.floor)
                .. " wave=" .. tostring(state.wave)
                .. " buffs=" .. tostring(table.concat(state.buffIds or {}, ","))
                .. " err=" .. tostring(drawErr))
            state.phase = "error"
            state.errorMessage = "通天塔战斗绘制异常，请退出后重试"
            state.errorLogged = true
            dungeonOpen = false
        end
    end

    if state.phase == "battle" then
        if not dungeonOpen then
            if not state.errorLogged then
                print("[TowerBattleScene] ERROR battle phase but DungeonBattleScene is closed floor=" .. tostring(state.floor)
                    .. " wave=" .. tostring(state.wave))
                state.errorLogged = true
            end
            state.phase = "error"
            state.errorMessage = "通天塔战斗画面丢失，请退出后重试"
            drawErrorFallback(vg)
        end
    elseif state.phase == "buff_pick" then
        -- 强化选择：DungeonBattleScene 作为冻结背景 + 三选一面板叠加
        TowerBuffPick.draw(vg)
    elseif state.phase == "floor_win" then
        -- 整层通关结算面板（DungeonBattleScene 已关闭，需手动绘制）
        BattleResultPanel.draw(vg)
    elseif state.phase == "error" then
        drawErrorFallback(vg)
    end
end

-- ======================== 更新 ========================

function TowerScene.update(dt)
    if not state.active then return end

    if state.phase == "battle" then
        if not DungeonBattleScene.isOpen() then
            if not state.errorLogged then
                print("[TowerBattleScene] ERROR update found battle phase but DungeonBattleScene is closed floor=" .. tostring(state.floor)
                    .. " wave=" .. tostring(state.wave))
                state.errorLogged = true
            end
            state.phase = "error"
            state.errorMessage = "通天塔战斗画面丢失，请退出后重试"
            return
        end
        local ok, err = xpcall(function()
            DungeonBattleScene.update(dt)
        end, debug.traceback)
        if not ok then
            print("[TowerBattleScene] ERROR DungeonBattleScene.update failed floor=" .. tostring(state.floor)
                .. " wave=" .. tostring(state.wave)
                .. " buffs=" .. tostring(table.concat(state.buffIds or {}, ","))
                .. " err=" .. tostring(err))
            state.phase = "error"
            state.errorMessage = "通天塔战斗逻辑异常，请退出后重试"
            DungeonBattleScene.forceClose()
        end
    elseif state.phase == "floor_win" then
        -- 更新结算面板动画和输入
        BattleResultPanel.update(dt)
    end
end

-- ======================== 输入 ========================

function TowerScene.handleClick(dx, dy)
    if not state.active then return false end

    if state.phase == "floor_win" and BattleResultPanel.isOpen() then
        BattleResultPanel.handleInput(dx, dy)
        return true
    elseif state.phase == "error" then
        TowerScene.close()
        return true
    elseif state.phase == "buff_pick" and TowerBuffPick.isOpen() then
        return TowerBuffPick.handleClick(dx, dy)
    elseif state.phase == "battle" then
        DungeonBattleScene.handleInput(dx, dy)
        return true
    end

    return true
end

return TowerScene
