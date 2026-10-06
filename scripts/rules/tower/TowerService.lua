---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- TowerService - 通天塔业务逻辑
-- 职责: 挑战、波次推进、整层通关、扫荡、强化选择
-- 层级: server/tower  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM         = require("rules.character.PlayerDataManager")
local TowerConfig = require("config.TowerConfig")
local ExpTable    = require("config.ExpTable")
local CurrencyService = require("rules.currency.CurrencyService")

local TowerService = {}

-- 当局选择事务仅存内存；Challenge 建立新局，旧档不恢复未完成选择。
-- Service 是 buffs 唯一 append 方，回执必须深拷贝，不能与单机 PDM 共表。
---@type table<number, table>
local runs = {}
local runSerial = 0
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

-- ======================== 内部工具 ========================

--- 获取今日天编号（UTC+8）
local function getTodayNum()
    return math.floor((os.time() + 28800) / 86400)
end

--- 确保 babel_tower 子结构存在（兼容旧存档）
---@param dungeon table PDM dungeon 模块
---@param uid number
---@return table babel_tower 子结构
local function ensureBT(dungeon, uid)
    if not dungeon.babel_tower then
        dungeon.babel_tower = { floor = 1, cleared = {}, dailyUsed = 0, dailyDay = 0, buffs = {} }
        PDM.MarkDirty(uid, "dungeon")
    end
    return dungeon.babel_tower
end

--- 重置每日次数（如果跨天）
local function resetDailyIfNeeded(bt)
    local today = getTodayNum()
    if bt.dailyDay ~= today then
        bt.dailyUsed = 0
        bt.dailyDay = today
    end
end

-- 三军攻坚的队伍门禁：挑战/推进/结算均需普通通关解锁三队。
-- 不影响已有通天塔扫荡（扫荡只读已通关层数，不使用编队）。
---@param uid number
---@return boolean, string|nil
local function checkTeamUnlocks(uid)
    if ExpTable.getUnlockedTeamCount(PDM.GetModule(uid, "battle")) < ExpTable.TEAM_COUNT then
        return false, "三军攻坚需三队解锁（" .. ExpTable.getTeamUnlockText(3) .. "队伍3）"
    end
    return true, nil
end

-- ======================== 挑战（进入通天塔战斗） ========================

--- 发起通天塔挑战，返回所选层+第一波的战斗配置
---@param uid number
---@param requestedFloor number|nil 缺省挑战当前层，全部通关后默认第112层
---@return boolean ok
---@return string|nil err
---@return table|nil result { floor, wave, monsterLevel, monsters, rageTime, superRageTime, buffs }
function TowerService.Challenge(uid, requestedFloor)
    local unlocked, unlockErr = checkTeamUnlocks(uid)
    if not unlocked then return false, unlockErr end
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then
        return false, "数据未加载"
    end

    local bt = ensureBT(dungeon, uid)

    local maxFloor = math.min(tonumber(bt.floor) or 1, TowerConfig.MAX_FLOOR)
    local floor = requestedFloor
    if floor == nil then floor = maxFloor end
    if type(floor) ~= "number" or floor ~= math.floor(floor) or floor < 1
        or floor > TowerConfig.MAX_FLOOR then return false, "无效的层数" end
    if floor > maxFloor then return false, "层数未解锁" end

    local floorCfg = TowerConfig.getFloor(floor)
    if not floorCfg then
        return false, "层配置不存在"
    end

    -- 重置当局强化（每次挑战从头开始）
    bt.buffs = {}
    runSerial = runSerial + 1
    local run = { id = tostring(uid) .. ":" .. runSerial, bt = bt, floor = floor,
        wave = 1, phase = "battle", selections = {}, waveResults = {}, requests = {} }
    runs[uid] = run
    PDM.MarkDirty(uid, "dungeon")

    -- 生成第一波怪物
    local wave = 1
    local monsters = TowerConfig.generateWaveMonsters(wave)

    print(string.format("[TowerService] Challenge uid=%s floor=%d monsterLv=%d",
        tostring(uid), floor, floorCfg.monsterLevel))

    return true, nil, {
        floor        = floor,
        wave         = wave,
        monsterLevel = floorCfg.monsterLevel,
        monsters     = monsters,
        rageTime     = TowerConfig.RAGE_TIME,
        superRageTime = TowerConfig.SUPER_RAGE_TIME,
        runId        = run.id,
        buffs        = copy(bt.buffs),
        battleBg     = TowerConfig.BATTLE_BG,
    }
end

-- ======================== 单波胜利 ========================

--- 通天塔单波胜利，生成下一波怪物或标记层通关
---@param uid number
---@param floor number 当前层
---@param wave number 刚胜利的波次
---@return boolean ok
---@return string|nil err
---@return table|nil result { nextWave, monsters, monsterLevel, floorCleared, buffChoices }
function TowerService.WaveWin(uid, floor, wave)
    local unlocked, unlockErr = checkTeamUnlocks(uid)
    if not unlocked then return false, unlockErr end
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then
        return false, "数据未加载"
    end

    local bt = ensureBT(dungeon, uid)

    local floorCfg = TowerConfig.getFloor(floor)
    if not floorCfg then
        return false, "层配置不存在"
    end
    local run = runs[uid]
    if not run or run.bt ~= bt or run.floor ~= floor then
        return false, "挑战未开始"
    end
    if type(wave) ~= "number" or wave ~= math.floor(wave) or wave < 1
        or wave > TowerConfig.WAVES_PER_FLOOR then return false, "无效的波次" end
    if run.waveResults[wave] then
        print("[TowerService] replay WaveWin run=" .. run.id .. " wave=" .. wave)
        return true, nil, copy(run.waveResults[wave])
    end
    if run.phase ~= "battle" or run.wave ~= wave then return false, "波次不匹配" end

    -- 每波胜利后提供三选一强化选项（由客户端展示，玩家选择后调 PickBuff）
    local buffChoices = TowerConfig.rollBuffs(3, bt.buffs)
    local choices = {}
    for _, buff in ipairs(buffChoices) do
        choices[#choices + 1] = {
            id      = buff.id,
            quality = buff.quality,
            name    = buff.name,
            desc    = buff.desc,
        }
    end

    -- 检查是否是最后一波
    if wave >= TowerConfig.WAVES_PER_FLOOR then
        -- 整层通关
        print(string.format("[TowerService] WaveWin uid=%s floor=%d wave=%d → FLOOR CLEARED",
            tostring(uid), floor, wave))
        run.phase = "floor_win"
        local result = { success = true, runId = run.id, floor = floor, wave = wave,
            floorCleared = true, buffChoices = choices }
        run.waveResults[wave] = result
        return true, nil, copy(result)
    end

    -- 生成下一波怪物
    local nextWave = wave + 1
    local monsters = TowerConfig.generateWaveMonsters(nextWave)

    print(string.format("[TowerService] WaveWin uid=%s floor=%d wave=%d → next=%d",
        tostring(uid), floor, wave, nextWave))

    local selectionId = run.id .. ":" .. wave
    local result = {
        success      = true,
        runId        = run.id,
        selectionId  = selectionId,
        floor        = floor,
        wave         = wave,
        floorCleared = false,
        nextWave     = nextWave,
        monsters     = monsters,
        monsterLevel = floorCfg.monsterLevel,
        buffChoices  = choices,
    }
    run.phase = "buff_pick"
    run.pending = { id = selectionId, wave = wave, result = result }
    run.waveResults[wave] = result
    return true, nil, copy(result)
end

-- ======================== 整层通关 ========================

--- 通天塔整层通关结算：发放奖励、推进层数
---@param uid number
---@param floor number 通关的层
---@return boolean ok
---@return string|nil err
---@return table|nil result { floor, firstClear, diamondReward, rewards, nextFloor }
function TowerService.FloorWin(uid, floor)
    local unlocked, unlockErr = checkTeamUnlocks(uid)
    if not unlocked then return false, unlockErr end
    local dungeon  = PDM.GetModule(uid, "dungeon")
    local currency = PDM.GetModule(uid, "currency")
    if not dungeon or not currency then
        return false, "数据未加载"
    end

    local bt = ensureBT(dungeon, uid)
    local run = runs[uid]
    if not run or run.bt ~= bt or run.floor ~= floor then
        return false, "挑战未开始"
    end
    if run.floorResult then
        print("[TowerService] replay FloorWin run=" .. run.id .. " floor=" .. floor)
        return true, nil, copy(run.floorResult)
    end
    if run.phase ~= "floor_win" or run.wave ~= TowerConfig.WAVES_PER_FLOOR then
        return false, "本层尚未通关"
    end
    for wave = 1, TowerConfig.WAVES_PER_FLOOR do
        if not run.waveResults[wave] then return false, "本层尚未通关" end
    end

    local floorCfg = TowerConfig.getFloor(floor)
    if not floorCfg then
        return false, "层配置不存在"
    end

    -- 旧档可能只有推进层数而没有 cleared 键：历史层不能再次发首通钻石。
    -- 真正首次通关给 firstDiamond；重打完整十波仍给 sweepDiamond。
    bt.cleared = bt.cleared or {}
    local oldFloor = tonumber(bt.floor) or 1
    local firstClear = not (oldFloor > floor or bt.cleared[floor] or bt.cleared[tostring(floor)])
    local diamondReward = firstClear and floorCfg.firstDiamond or floorCfg.sweepDiamond

    bt.cleared[floor] = true
    bt.cleared[tostring(floor)] = nil
    bt.floor = math.max(oldFloor, math.min(floor + 1, TowerConfig.MAX_FLOOR + 1))

    local rewards = {}
    if diamondReward > 0 then
        rewards[#rewards + 1] = { type = "diamond", amount = diamondReward }
    end
    -- 先消费当局并缓存回执，奖励/MarkDirty 的同步回调不能重复发奖。
    run.phase = "settled"
    run.floorResult = {
        floor         = floor,
        firstClear    = firstClear,
        diamondReward = diamondReward,
        rewards       = rewards,
        nextFloor     = bt.floor,
    }
    if diamondReward > 0 then CurrencyService.GrantReward(uid, rewards[1]) end

    PDM.MarkDirty(uid, "dungeon")
    if diamondReward > 0 then
        PDM.MarkDirty(uid, "currency")
    end

    print(string.format("[TowerService] FloorWin uid=%s floor=%d firstClear=%s diamond=%d nextFloor=%d",
        tostring(uid), floor, tostring(firstClear), diamondReward, bt.floor))

    return true, nil, copy(run.floorResult)
end

-- ======================== 选择强化 ========================

--- 玩家选择一个强化词条
---@param uid number
---@param buffId number 选择的强化ID
---@return boolean ok
---@return string|nil err
---@param request table|nil 正式请求携带 runId/selectionId/floor/wave/requestId
---@return table|nil result 独立权威快照（含本次请求身份）
function TowerService.PickBuff(uid, buffId, request)
    local unlocked, unlockErr = checkTeamUnlocks(uid)
    if not unlocked then return false, unlockErr end
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then
        return false, "数据未加载"
    end

    local bt = ensureBT(dungeon, uid)
    local buff = TowerConfig.BUFFS_BY_ID[buffId]
    if not buff then
        return false, "无效的强化ID"
    end

    local run = runs[uid]
    if not run or run.bt ~= bt then return false, "挑战未开始" end
    request = request or {}
    if request.runId ~= nil and request.runId ~= run.id then return false, "挑战已过期" end
    if request.floor ~= nil and request.floor ~= run.floor then return false, "层数不匹配" end
    -- 旧无 token 调用只兼容当前待选，不能在未 Challenge/清波时创造选择。
    local pending = run.pending
    local selectionId = request.selectionId or (pending and pending.id)
    local requestId = request.requestId
    local previous = requestId and run.requests[requestId]
    if previous and (previous.selectionId ~= selectionId or previous.buffId ~= buffId
        or (request.wave ~= nil and request.wave ~= previous.wave)) then
        return false, "请求编号已使用"
    end
    local accepted = selectionId and run.selections[selectionId]
    if accepted then
        if accepted.buffId ~= buffId or (request.wave ~= nil and request.wave ~= accepted.wave) then
            return false, "本次强化已选择"
        end
        if requestId then run.requests[requestId] = accepted end
        local result = copy(accepted)
        result.requestId = requestId
        print("[TowerService] replay PickBuff run=" .. run.id .. " selection=" .. selectionId
            .. " request=" .. tostring(requestId))
        return true, nil, result
    end
    if run.phase ~= "buff_pick" or not pending or selectionId ~= pending.id
        or (request.wave ~= nil and request.wave ~= pending.wave) then return false, "强化选择已过期" end
    local offered = false
    for _, choice in ipairs(pending.result.buffChoices) do
        if choice.id == buffId then offered = true; break end
    end
    if not offered then return false, "强化不在本次选项中" end

    -- 只消费一次 selection，跨波同卡仍合法；先记 accepted/phase 再 MarkDirty 防推送重入。
    bt.buffs[#bt.buffs + 1] = buffId
    local result = {
        success    = true,
        runId      = run.id,
        selectionId = selectionId,
        floor      = run.floor,
        wave       = pending.wave,
        nextWave   = pending.result.nextWave,
        buffId     = buffId,
        buffName   = buff.name,
        totalBuffs = #bt.buffs,
        buffs      = copy(bt.buffs),
    }
    run.selections[selectionId] = result
    if requestId then run.requests[requestId] = result end
    run.pending = nil
    run.wave = result.nextWave
    run.phase = "battle"
    PDM.MarkDirty(uid, "dungeon")

    print(string.format("[TowerService] PickBuff uid=%s run=%s selection=%s request=%s buffId=%d total=%d",
        tostring(uid), run.id, selectionId, tostring(requestId), buffId, #bt.buffs))
    local receipt = copy(result)
    receipt.requestId = requestId
    return true, nil, receipt
end

-- ======================== 扫荡 ========================

--- 通天塔扫荡（消耗每日次数，获得上一层的扫荡奖励）
---@param uid number
---@return boolean ok
---@return string|nil err
---@return table|nil result { sweepFloor, diamondReward, dailyUsed, dailyMax }
function TowerService.Sweep(uid)
    local dungeon  = PDM.GetModule(uid, "dungeon")
    local currency = PDM.GetModule(uid, "currency")
    if not dungeon or not currency then
        return false, "数据未加载"
    end

    local bt = ensureBT(dungeon, uid)
    resetDailyIfNeeded(bt)

    -- 检查每日次数
    if bt.dailyUsed >= TowerConfig.DAILY_SWEEP_LIMIT then
        return false, "今日扫荡次数已用完"
    end

    -- 必须至少通关第1层才能扫荡
    local sweepFloor = bt.floor - 1
    if sweepFloor < 1 then
        return false, "至少通关1层后才能扫荡"
    end

    local floorCfg = TowerConfig.getFloor(sweepFloor)
    if not floorCfg then
        return false, "扫荡层配置不存在"
    end

    -- 扣除次数、发放奖励
    bt.dailyUsed = bt.dailyUsed + 1
    local diamondReward = floorCfg.sweepDiamond

    CurrencyService.GrantReward(uid, { type = "diamond", amount = diamondReward })

    PDM.MarkDirty(uid, "dungeon")
    PDM.MarkDirty(uid, "currency")

    print(string.format("[TowerService] Sweep uid=%s floor=%d diamond=%d used=%d/%d",
        tostring(uid), sweepFloor, diamondReward, bt.dailyUsed, TowerConfig.DAILY_SWEEP_LIMIT))

    return true, nil, {
        sweepFloor    = sweepFloor,
        diamondReward = diamondReward,
        dailyUsed     = bt.dailyUsed,
        dailyMax      = TowerConfig.DAILY_SWEEP_LIMIT,
    }
end

return TowerService
