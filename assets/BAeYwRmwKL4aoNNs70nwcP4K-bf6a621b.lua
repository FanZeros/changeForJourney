-- ============================================================================
-- DungeonBattle - 副本战斗模块
-- 职责: 管理副本模式下的战斗（狂暴计时、职业加成、胜负处理）
-- 与 BattleScene 的关系: 独立模块，通过 hook 注入副本逻辑
-- ============================================================================

local MC       = require("config.MonsterConfig")
local AD       = require("systems.AttributeDef")
local Protocol = require("shared.Protocol")
local GameConfig = require("config.GameConfig")
local TowerConfig = require("config.TowerConfig")

local DungeonBattle = {}

-- ======================== 状态 ========================

local active       = false   -- 是否处于副本战斗中
local elapsed      = 0       -- 战斗已持续时间(秒)
local ragePhase    = 0       -- 0=正常, 1=狂暴, 2=超级狂暴

-- 结算状态
local resultPending   = false  -- 是否等待结算（胜利/失败后进入此状态）
local resultIsWin     = false  -- 结算结果：胜利/失败
local resultElapsed   = 0      -- 结算时记录的战斗耗时
local serverResult    = nil    -- 服务端返回的奖励数据（仅胜利时有）

-- 战斗配置（来自服务端 Challenge 返回）
local cfg = {
    dungeonId     = "",
    floor         = 1,
    monsterLevel  = 1,
    monsters      = {},      -- { {id=monsterId, count=N}, ... }
    firstGold     = 0,
    classBonus    = "",      -- 当层加成的职业 classId（如 "warrior"）
    classBonusValue   = 0.20,
    rageTime          = 30,
    rageAtkBonus      = 0.50,
    superRageTime     = 60,
    superRageAtkBonus = 1.00,
    superRageDmgBonus = 0.30,
    allyRageDmgBonus  = 0.30,
    allySuperRageDmgBonus = 0.30,
    trainingDummy     = false,
    dummyMaxHp        = 1000000000000,
    dummyRegen        = 1000000000000,
}

-- 缓存原始攻击间隔/攻击力倍率（用于恢复/重算）
local origIntervals = {}      -- [unit] = 原始 atkInterval
local origAtkCoeffs = {}      -- [unit] = 原始 attrs.atkCoeff
local origUnitAtkCoeffs = {}  -- [unit] = 原始 unit.atkCoeff（部分天赋直接读取）

-- ======================== 外部引用（延迟 require，避免循环） ========================

---@type table|nil
local BattleScene_ = nil
local function getBattleScene()
    if not BattleScene_ then
        BattleScene_ = require("ui.BattleScene")
    end
    return BattleScene_
end

local function cacheBaseValues(u)
    if not u then return end
    origIntervals[u] = origIntervals[u] or u.atkInterval
    if u.attrs then
        origAtkCoeffs[u] = origAtkCoeffs[u] or u.attrs.atkCoeff or 1.0
    end
    origUnitAtkCoeffs[u] = origUnitAtkCoeffs[u] or u.atkCoeff or (u.attrs and u.attrs.atkCoeff) or 1.0
end

local function isAllyUnit(u)
    return u and u.heroId ~= nil
end

local function isNonPriestAlly(u)
    return isAllyUnit(u)
end

-- ======================== 公共 API ========================

--- 是否处于副本战斗模式
---@return boolean
function DungeonBattle.isActive()
    return active
end

--- 获取当前配置（供 UI 读取）
function DungeonBattle.getConfig()
    return cfg
end

function DungeonBattle.isTrainingDummy()
    return active and cfg.trainingDummy == true
end

--- 获取战斗剩余时间（秒）
---@return number
function DungeonBattle.getTimeRemaining()
    if not active then return 0 end
    if cfg.trainingDummy then return 0 end
    local limit = GameConfig.Battle.TIME_LIMIT_SEC
    return math.max(0, limit - elapsed)
end

--- 是否已超过战斗限时
---@return boolean
function DungeonBattle.isTimeLimitExceeded()
    if not active then return false end
    if cfg.trainingDummy then return false end
    return elapsed >= GameConfig.Battle.TIME_LIMIT_SEC
end

--- 获取已持续时间
---@return number
function DungeonBattle.getElapsed()
    return elapsed
end

--- 获取当前狂暴阶段 (0/1/2)
---@return number
function DungeonBattle.getRagePhase()
    return ragePhase
end

--- 获取职业加成信息
---@return string classId, number bonusValue
function DungeonBattle.getClassBonus()
    return cfg.classBonus, cfg.classBonusValue
end

-- ======================== 进入副本战斗 ========================

--- 根据服务端返回的数据进入副本战斗
--- 调用方: DungeonPage.onActionResult → DungeonBattleScene.open
---@param data table 服务端 Challenge 返回的 result
---@param allies table 副本己方单位列表引用
function DungeonBattle.enter(data, allies)
    -- 保存配置
    cfg.dungeonId         = data.dungeonId or "gold_mine"
    cfg.floor             = data.floor or 1
    cfg.wave              = data.wave or 1
    cfg.monsterLevel      = data.monsterLevel or 1
    cfg.monsters          = data.monsters or {}
    cfg.firstGold         = data.firstGold or 0
    cfg.classBonus        = data.classBonus or ""
    cfg.classBonusValue   = data.classBonusValue or 0.20
    cfg.rageTime          = data.rageTime or 30
    cfg.rageAtkBonus      = data.rageAtkBonus or 0.50
    cfg.superRageTime     = data.superRageTime or 60
    cfg.superRageAtkBonus = data.superRageAtkBonus or 1.00
    cfg.superRageDmgBonus = data.superRageDmgBonus or 0.30
    cfg.allyRageDmgBonus  = data.allyRageDmgBonus or 0.30
    cfg.allySuperRageDmgBonus = data.allySuperRageDmgBonus or cfg.allyRageDmgBonus
    cfg.trainingDummy     = data.trainingDummy == true
    cfg.dummyMaxHp        = data.dummyMaxHp or 1000000000000
    cfg.dummyRegen        = data.dummyRegen or cfg.dummyMaxHp

    -- 重置状态
    active    = true
    elapsed   = 0
    ragePhase = 0
    origIntervals = {}
    origAtkCoeffs = {}
    origUnitAtkCoeffs = {}

    local allyBuffCount = 0
    for _, u in ipairs(allies or {}) do
        if u.hp and u.hp > 0 and isAllyUnit(u) then
            cacheBaseValues(u)
            allyBuffCount = allyBuffCount + 1
        end
    end

    print(string.format("[DungeonBattle] enter floor=%d monsterLv=%d classBonus=%s rageTime=%d/%d allies=%d dummy=%s",
        cfg.floor, cfg.monsterLevel, cfg.classBonus, cfg.rageTime, cfg.superRageTime, allyBuffCount, tostring(cfg.trainingDummy)))
end

-- ======================== 生成敌人列表 ========================

--- 根据副本配置生成敌人列表
--- cfg.monsters 是纯数字数组，每个元素是一个 monsterId
---@return table[] enemyList
function DungeonBattle.generateEnemies()
    local list = {}
    if cfg.trainingDummy then
        local unit = MC.createMonster(1, math.max(1, cfg.monsterLevel or 1))
        if unit then
            local dummyHp = cfg.dummyMaxHp or 1000000000000
            local dummyRegen = cfg.dummyRegen or dummyHp
            unit.name = "测试木桩"
            unit.maxHp = dummyHp
            unit.hp = dummyHp
            unit.atkTargets = 1
            unit.atkInterval = 999999
            unit.expReward = 0
            unit.goldReward = 0
            unit._trainingDummy = true
            if unit.attrs then
                unit.attrs:setBases({
                    [AD.MAX_HP] = dummyHp,
                    [AD.PHYS_ATK] = 0,
                    [AD.MAG_ATK] = 0,
                    [AD.HEAL_AMOUNT] = 0,
                    [AD.HP_REGEN] = dummyRegen,
                    [AD.ATK_INTERVAL] = 999999,
                    [AD.ATK_SPEED] = 0,
                    [AD.ATK_HEAL] = 0,
                })
                unit.attrs:clearModifiers()
                unit.attrs.atkType = AD.ATK_SLASH
                unit.attrs:fillHp()
                unit.hp = unit.attrs.final[AD.HP]
                unit.maxHp = unit.attrs.final[AD.MAX_HP]
                unit.atkInterval = unit.attrs:getActualInterval()
            end
            list[#list + 1] = unit
        end
        print(string.format("[DungeonBattle] generated training dummy hp=%s regen=%s", tostring(cfg.dummyMaxHp), tostring(cfg.dummyRegen)))
        return list
    end

    local statMult = 1.0
    if cfg.dungeonId == TowerConfig.DUNGEON_ID then
        statMult = TowerConfig.MONSTER_STAT_MULT or 1.0
    end
    for _, entry in ipairs(cfg.monsters) do
        -- entry 可能是纯数字(monsterId) 或 table({id=..., count=...})
        local monsterId, count
        if type(entry) == "number" then
            monsterId = entry
            count = 1
        else
            monsterId = entry.id or entry[1]
            count     = entry.count or entry[2] or 1
        end
        for _ = 1, count do
            local unit = MC.createMonster(monsterId, cfg.monsterLevel, { statMult = statMult })
            if unit then
                list[#list + 1] = unit
            end
        end
    end
    print(string.format("[DungeonBattle] generated %d enemies for floor %d", #list, cfg.floor))
    return list
end

-- ======================== 每帧更新（狂暴计时） ========================

--- 每帧由 DungeonBattleScene.update 调用
---@param dt number
---@param enemies table 副本场上的怪物列表引用
---@param allies table 副本己方单位列表引用
function DungeonBattle.update(dt, enemies, allies)
    if not active then return end

    elapsed = elapsed + dt
    if cfg.trainingDummy then return end

    -- 狂暴阶段检测
    if ragePhase == 0 and elapsed >= cfg.rageTime then
        ragePhase = 1
        applyRageBuffs(enemies, cfg.rageAtkBonus, 0, nil)
        applyRageBuffs(allies, cfg.rageAtkBonus, cfg.allyRageDmgBonus, isAllyUnit)
        print(string.format("[DungeonBattle] RAGE triggered at %.1fs (enemy +%.0f%% atk speed, ally +%.0f%% atk speed +%.0f%% atk coeff)",
            elapsed, cfg.rageAtkBonus * 100, cfg.rageAtkBonus * 100, cfg.allyRageDmgBonus * 100))
    elseif ragePhase == 1 and elapsed >= cfg.superRageTime then
        ragePhase = 2
        applyRageBuffs(enemies, cfg.superRageAtkBonus, cfg.superRageDmgBonus, nil)
        applyRageBuffs(allies, cfg.superRageAtkBonus, cfg.allySuperRageDmgBonus, isAllyUnit)
        print(string.format("[DungeonBattle] SUPER RAGE triggered at %.1fs (enemy +%.0f%% atk speed +%.0f%% atk coeff, ally +%.0f%% atk speed +%.0f%% atk coeff)",
            elapsed, cfg.superRageAtkBonus * 100, cfg.superRageDmgBonus * 100,
            cfg.superRageAtkBonus * 100, cfg.allySuperRageDmgBonus * 100))
    end

    -- 确保后备队列中新入场的怪物/己方单位也吃到当前阶段 buff（idempotent）
    if ragePhase >= 1 then
        if ragePhase == 1 then
            applyRageBuffs(enemies, cfg.rageAtkBonus, 0, nil)
            applyRageBuffs(allies, cfg.rageAtkBonus, cfg.allyRageDmgBonus, isAllyUnit)
        else
            applyRageBuffs(enemies, cfg.superRageAtkBonus, cfg.superRageDmgBonus, nil)
            applyRageBuffs(allies, cfg.superRageAtkBonus, cfg.allySuperRageDmgBonus, isAllyUnit)
        end
    end
end

-- ======================== 狂暴加成 ========================

--- 应用狂暴加成到所有存活单位（idempotent：原始值懒缓存，可重复调用）
---@param units table 单位列表
---@param atkBonus number 攻速加成，0.50 表示 +50%
---@param dmgBonus number 攻击力倍率加成，0.30 表示 +30%
---@param predicate function|nil 单位过滤器
function applyRageBuffs(units, atkBonus, dmgBonus, predicate)
    for _, u in ipairs(units or {}) do
        if u.hp and u.hp > 0 and (not predicate or predicate(u)) then
            cacheBaseValues(u)

            local baseInterval = origIntervals[u] or u.atkInterval or 1.0
            u.atkInterval = baseInterval / (1.0 + atkBonus)

            if dmgBonus > 0 then
                if u.attrs then
                    local baseCoeff = origAtkCoeffs[u] or u.attrs.atkCoeff or 1.0
                    u.attrs.atkCoeff = baseCoeff * (1.0 + dmgBonus)
                end
                local baseUnitCoeff = origUnitAtkCoeffs[u] or u.atkCoeff or 1.0
                u.atkCoeff = baseUnitCoeff * (1.0 + dmgBonus)
            end
        end
    end
end

-- ======================== 职业加成伤害倍率 ========================

--- 获取指定单位在副本中的伤害倍率（含通天塔强化加成）
---@param unit table 攻击者
---@param target table|nil 目标（通天塔钩子需要）
---@return number multiplier (1.0 = 无加成)
function DungeonBattle.getDamageMultiplier(unit, target)
    if not active then return 1.0 end
    local mult = 1.0
    -- 职业加成
    if cfg.classBonus ~= "" and unit.classId and unit.classId == cfg.classBonus then
        mult = mult * (1.0 + cfg.classBonusValue)
    end
    -- 通天塔 mechanic 强化加成
    if cfg.dungeonId == "babel_tower" then
        local ok, TBR = pcall(require, "systems.TowerBuffRuntime")
        if ok and TBR and TBR.getDamageMultiplier then
            mult = mult * TBR.getDamageMultiplier(unit, target)
        end
    end
    return mult
end

--- 通天塔：消费受击免疫（亡者遗志/刺客免疫次数）
---@param defender table
---@return boolean immune
function DungeonBattle.consumeDamageImmunity(defender)
    if not active then return false end
    if cfg.dungeonId ~= "babel_tower" then return false end
    if not isAllyUnit(defender) then return false end
    local ok, TBR = pcall(require, "systems.TowerBuffRuntime")
    if ok and TBR and TBR.consumeDamageImmunity then
        return TBR.consumeDamageImmunity(defender)
    end
    return false
end

--- 通天塔：受击伤害倍率（减伤）
---@param defender table
---@return number multiplier (1.0=全额)
function DungeonBattle.getDamageTakenMultiplier(defender)
    if not active then return 1.0 end
    if cfg.dungeonId ~= "babel_tower" then return 1.0 end
    if not isAllyUnit(defender) then return 1.0 end
    local ok, TBR = pcall(require, "systems.TowerBuffRuntime")
    if ok and TBR and TBR.getDamageTakenMultiplier then
        return TBR.getDamageTakenMultiplier(defender)
    end
    return 1.0
end

--- 通天塔：治疗是否被阻断
---@param unit table
---@return boolean
function DungeonBattle.isHealBlocked(unit)
    if not active then return false end
    if cfg.dungeonId ~= "babel_tower" then return false end
    local ok, TBR = pcall(require, "systems.TowerBuffRuntime")
    if ok and TBR and TBR.isHealBlocked then
        return TBR.isHealBlocked(unit)
    end
    return false
end

--- 通天塔：斩杀判定
---@param target table
---@return boolean
function DungeonBattle.checkExecute(target)
    if not active then return false end
    if cfg.dungeonId ~= "babel_tower" then return false end
    local ok, TBR = pcall(require, "systems.TowerBuffRuntime")
    if ok and TBR and TBR.checkExecute then
        return TBR.checkExecute(target)
    end
    return false
end

--- 通天塔：超级暴击判定
---@param attacker table
---@param isCrit boolean
---@return boolean
function DungeonBattle.shouldSuperCrit(attacker, isCrit)
    if not active then return false end
    if cfg.dungeonId ~= "babel_tower" then return false end
    if not isCrit then return false end
    local ok, TBR = pcall(require, "systems.TowerBuffRuntime")
    if ok and TBR and TBR.shouldSuperCrit then
        return TBR.shouldSuperCrit(attacker, isCrit)
    end
    return false
end

--- 通天塔：击杀敌人回调
---@param killer table
function DungeonBattle.onEnemyKill(killer)
    if not active then return end
    if cfg.dungeonId ~= "babel_tower" then return end
    local ok, TBR = pcall(require, "systems.TowerBuffRuntime")
    if ok and TBR and TBR.onEnemyKill then
        TBR.onEnemyKill(killer)
    end
end

--- 通天塔：己方死亡回调
---@param deadUnit table
function DungeonBattle.onAllyDeath(deadUnit)
    if not active then return end
    if cfg.dungeonId ~= "babel_tower" then return end
    local ok, TBR = pcall(require, "systems.TowerBuffRuntime")
    if ok and TBR and TBR.onAllyDeath then
        TBR.onAllyDeath(deadUnit)
    end
end

--- 通天塔：攻击间隔倍率
---@param unit table
---@return number multiplier
function DungeonBattle.getAtkIntervalMultiplier(unit)
    if not active then return 1.0 end
    if cfg.dungeonId ~= "babel_tower" then return 1.0 end
    local ok, TBR = pcall(require, "systems.TowerBuffRuntime")
    if ok and TBR and TBR.getAtkIntervalMultiplier then
        return TBR.getAtkIntervalMultiplier(unit)
    end
    return 1.0
end

-- ======================== 胜负处理 ========================

--- 副本战斗胜利回调（由 BattleScene 的胜利判定调用）
--- 不再立即 exit，进入结算等待状态，等服务端返回奖励数据后由 BattleScene 展示结算面板
function DungeonBattle.onVictory()
    if not active then return end
    if cfg.trainingDummy then return end

    print(string.format("[DungeonBattle] VICTORY floor=%d elapsed=%.1fs ragePhase=%d",
        cfg.floor, elapsed, ragePhase))

    -- 记录结算状态
    resultPending = true
    resultIsWin   = true
    resultElapsed = elapsed
    serverResult  = nil  -- 等待服务端返回

    -- 发送胜利请求到服务端
    local Client = require("network.Client")
    if cfg.dungeonId == "babel_tower" then
        -- 通天塔：发送波次胜利（由 TowerBattleScene 管理后续流程）
        Client.sendAction(Protocol.ACTION_TYPES.TOWER_WAVE_WIN, {
            floor = cfg.floor,
            wave  = cfg.wave or 1,
        })
    else
        Client.sendAction(Protocol.ACTION_TYPES.DUNGEON_WIN, {
            dungeonId = cfg.dungeonId,
            floor     = cfg.floor,
        })
    end

    -- 不再立即 exit，由 BattleScene 在结算面板关闭后调用 exit
end

--- [Debug] 立即胜利当前副本战斗。
--- 通天塔会按当前小波胜利处理；普通副本按当前层胜利处理。
function DungeonBattle.debugInstantWin()
    if not active then return false end
    if resultPending then return true end
    DungeonBattle.onVictory()
    print("[DungeonBattle][Debug] 立即胜利: dungeon=" .. tostring(cfg.dungeonId)
        .. " floor=" .. tostring(cfg.floor)
        .. " wave=" .. tostring(cfg.wave or 1))
    return true
end

--- 副本战斗失败回调
--- 不再立即 exit，进入结算等待状态
function DungeonBattle.onDefeat()
    if not active then return end

    print(string.format("[DungeonBattle] DEFEAT floor=%d elapsed=%.1fs", cfg.floor, elapsed))

    -- 记录结算状态
    resultPending = true
    resultIsWin   = false
    resultElapsed = elapsed
    serverResult  = nil  -- 失败无奖励

    -- 失败不发请求（层数不变，玩家可重试）
    -- 不再立即 exit，由 BattleScene 在结算面板关闭后调用 exit
end

--- 设置服务端返回的结算数据（由 DungeonPage.onActionResult 调用）
---@param data table 服务端 DUNGEON_WIN 返回的数据
function DungeonBattle.setServerResult(data)
    serverResult = data
    print(string.format("[DungeonBattle] setServerResult: gold=%s firstClear=%s",
        tostring(data and data.gold), tostring(data and data.firstClear)))
end

--- 获取结算状态
---@return boolean pending, boolean isWin, number elapsedSecs, table|nil result
function DungeonBattle.getResultState()
    return resultPending, resultIsWin, resultElapsed, serverResult
end

--- 结算是否已有服务端数据（胜利时需等待；失败时可直接显示）
---@return boolean
function DungeonBattle.isResultReady()
    if not resultPending then return false end
    if not resultIsWin then return true end  -- 失败无需等服务端
    return serverResult ~= nil               -- 胜利需等服务端返回
end

--- 退出副本战斗模式，恢复 BattleScene 正常状态
function DungeonBattle.exit()
    for u, baseInterval in pairs(origIntervals) do
        if u then
            u.atkInterval = baseInterval
        end
    end
    for u, baseCoeff in pairs(origAtkCoeffs) do
        if u and u.attrs then
            u.attrs.atkCoeff = baseCoeff
        end
    end
    for u, baseCoeff in pairs(origUnitAtkCoeffs) do
        if u then
            u.atkCoeff = baseCoeff
        end
    end

    active        = false
    elapsed       = 0
    ragePhase     = 0
    resultPending = false
    resultIsWin   = false
    resultElapsed = 0
    serverResult  = nil
    origIntervals = {}
    origAtkCoeffs = {}
    origUnitAtkCoeffs = {}
    print("[DungeonBattle] exit dungeon mode")
end

return DungeonBattle
