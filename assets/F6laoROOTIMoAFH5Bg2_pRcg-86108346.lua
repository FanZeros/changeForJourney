---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- TowerService - 通天塔业务逻辑
-- 职责: 挑战、波次推进、整层通关、扫荡、强化选择
-- 层级: server/tower  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM         = require("server.character.PlayerDataManager")
local TowerConfig = require("config.TowerConfig")
local CurrencyService = require("server.currency.CurrencyService")

local TowerService = {}

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

-- ======================== 挑战（进入通天塔战斗） ========================

--- 发起通天塔挑战，返回当前层+第一波的战斗配置
---@param uid number
---@return boolean ok
---@return string|nil err
---@return table|nil result { floor, wave, monsterLevel, monsters, rageTime, superRageTime, buffs }
function TowerService.Challenge(uid)
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then
        return false, "数据未加载"
    end

    local bt = ensureBT(dungeon, uid)

    local floor = bt.floor
    if floor > TowerConfig.MAX_FLOOR then
        return false, "已通关全部层数"
    end

    local floorCfg = TowerConfig.getFloor(floor)
    if not floorCfg then
        return false, "层配置不存在"
    end

    -- 重置当局强化（每次挑战从头开始）
    bt.buffs = {}
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
        buffs        = bt.buffs,
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
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then
        return false, "数据未加载"
    end

    local bt = ensureBT(dungeon, uid)
    if bt.floor ~= floor then
        return false, "层数不匹配"
    end

    local floorCfg = TowerConfig.getFloor(floor)
    if not floorCfg then
        return false, "层配置不存在"
    end

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
        return true, nil, {
            floorCleared = true,
            buffChoices  = choices,
        }
    end

    -- 生成下一波怪物
    local nextWave = wave + 1
    local monsters = TowerConfig.generateWaveMonsters(nextWave)

    print(string.format("[TowerService] WaveWin uid=%s floor=%d wave=%d → next=%d",
        tostring(uid), floor, wave, nextWave))

    return true, nil, {
        floorCleared = false,
        nextWave     = nextWave,
        monsters     = monsters,
        monsterLevel = floorCfg.monsterLevel,
        buffChoices  = choices,
    }
end

-- ======================== 整层通关 ========================

--- 通天塔整层通关结算：发放奖励、推进层数
---@param uid number
---@param floor number 通关的层
---@return boolean ok
---@return string|nil err
---@return table|nil result { floor, firstClear, diamondReward, rewards, nextFloor }
function TowerService.FloorWin(uid, floor)
    local dungeon  = PDM.GetModule(uid, "dungeon")
    local currency = PDM.GetModule(uid, "currency")
    if not dungeon or not currency then
        return false, "数据未加载"
    end

    local bt = ensureBT(dungeon, uid)
    if bt.floor ~= floor then
        return false, "层数不匹配"
    end

    local floorCfg = TowerConfig.getFloor(floor)
    if not floorCfg then
        return false, "层配置不存在"
    end

    -- 首通给 firstDiamond；重复通关也给扫荡档钻石，避免玩家完整打完一层无任何收益。
    local firstClear = not (bt.cleared[floor] or bt.cleared[tostring(floor)])
    local diamondReward = firstClear and floorCfg.firstDiamond or floorCfg.sweepDiamond

    -- 标记通关、推进层数
    bt.cleared[floor] = true
    bt.cleared[tostring(floor)] = nil
    bt.floor = math.min(floor + 1, TowerConfig.MAX_FLOOR + 1)

    local rewards = {}
    if diamondReward > 0 then
        rewards[#rewards + 1] = { type = "diamond", amount = diamondReward }
        CurrencyService.GrantReward(uid, rewards[1])
    end

    PDM.MarkDirty(uid, "dungeon")
    if diamondReward > 0 then
        PDM.MarkDirty(uid, "currency")
    end

    print(string.format("[TowerService] FloorWin uid=%s floor=%d firstClear=%s diamond=%d nextFloor=%d",
        tostring(uid), floor, tostring(firstClear), diamondReward, bt.floor))

    return true, nil, {
        floor         = floor,
        firstClear    = firstClear,
        diamondReward = diamondReward,
        rewards       = rewards,
        nextFloor     = bt.floor,
    }
end

-- ======================== 选择强化 ========================

--- 玩家选择一个强化词条
---@param uid number
---@param buffId number 选择的强化ID
---@return boolean ok
---@return string|nil err
---@return table|nil result { buffId, buffName, totalBuffs }
function TowerService.PickBuff(uid, buffId)
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then
        return false, "数据未加载"
    end

    local bt = ensureBT(dungeon, uid)
    local buff = TowerConfig.BUFFS_BY_ID[buffId]
    if not buff then
        return false, "无效的强化ID"
    end

    -- 记录已选强化
    bt.buffs[#bt.buffs + 1] = buffId
    PDM.MarkDirty(uid, "dungeon")

    print(string.format("[TowerService] PickBuff uid=%s buffId=%d name=%s total=%d",
        tostring(uid), buffId, buff.name, #bt.buffs))

    return true, nil, {
        buffId     = buffId,
        buffName   = buff.name,
        totalBuffs = #bt.buffs,
    }
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
