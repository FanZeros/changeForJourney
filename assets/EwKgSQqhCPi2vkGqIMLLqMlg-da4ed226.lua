-- StageBerserk - 首通战斗狂暴模块
-- 职责: 管理首通战斗中的狂暴机制（敌我渐强），防止肉+奶无限磨血
-- 敌我双方都会获得狂暴攻速/攻击力强化

local StageBerserk = {}

-- 状态
local active       = false   -- 是否处于首通狂暴模式
local elapsed      = 0       -- 战斗已持续时间(秒)
local ragePhase    = 0       -- 0=正常, 1=狂暴, 2=超级狂暴

-- 缓存原始攻速和攻击力倍率（用于重算/恢复）
local origIntervals = {}      -- [unit] = 原始 atkInterval
local origAtkCoeffs = {}      -- [unit] = 原始 attrs.atkCoeff（攻击力倍率）
local origUnitAtkCoeffs = {}  -- [unit] = 原始 unit.atkCoeff（部分天赋直接读取）

-- 玩家提示横幅（由 BattleScene 渲染段读取，触发狂暴时弹出）
local bannerText_     = nil  ---@type string|nil
local bannerTimer_    = 0    -- 剩余显示秒数
local BANNER_DURATION = 2.5  -- 提示显示时长(秒)

-- 配置（从 GameConfig 读取，本地缓存）
local cfg = {
    rageTime              = 120,   -- 一阶狂暴触发时间(秒)
    rageAtkBonus          = 0.50,
    superRageTime         = 210,   -- 二阶超级狂暴触发时间(秒)
    superRageAtkBonus     = 1.00,  -- 二阶超级狂暴敌人攻速加成 +100%
    superRageDmgBonus     = 0.30,  -- 二阶超级狂暴敌人攻击力加成 +30%
    allyRageDmgBonus      = 0.30,  -- 一阶狂暴己方攻击力加成 +30%
    allySuperRageDmgBonus = 0.30,  -- 二阶超级狂暴己方攻击力加成 +30%
}

-- 是否处于首通狂暴模式
function StageBerserk.isActive()
    return active
end

-- 获取当前狂暴阶段 (0/1/2)
function StageBerserk.getRagePhase()
    return ragePhase
end

-- 获取已持续时间
function StageBerserk.getElapsed()
    return elapsed
end

-- 获取当前要显示的狂暴提示横幅（供 BattleScene 渲染段调用）
-- 返回: text(string), alpha(0~1), phase(1/2)；无提示时返回 nil
function StageBerserk.getBanner()
    if not active or bannerTimer_ <= 0 or not bannerText_ then
        return nil
    end
    local alpha = 1.0
    if bannerTimer_ < 0.6 then
        alpha = bannerTimer_ / 0.6   -- 最后 0.6 秒淡出
    end
    return bannerText_, alpha, ragePhase
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

-- 进入首通狂暴模式
-- 调用方: BattleScene.loadStage (isFirstClear 时)
function StageBerserk.enter(enemies, allies)
    -- 加载配置
    local GameConfig = require("config.GameConfig")
    if GameConfig.StageBerserk then
        cfg.rageTime              = GameConfig.StageBerserk.RAGE_TIME or 120
        cfg.rageAtkBonus          = GameConfig.StageBerserk.RAGE_ATK_BONUS or 0.50
        cfg.superRageTime         = GameConfig.StageBerserk.SUPER_RAGE_TIME or 210
        cfg.superRageAtkBonus     = GameConfig.StageBerserk.SUPER_RAGE_ATK_BONUS or 1.00
        cfg.superRageDmgBonus     = GameConfig.StageBerserk.SUPER_RAGE_DMG_BONUS or 0.30
        cfg.allyRageDmgBonus      = GameConfig.StageBerserk.ALLY_RAGE_DMG_BONUS or 0.30
        cfg.allySuperRageDmgBonus = GameConfig.StageBerserk.ALLY_SUPER_RAGE_DMG_BONUS or cfg.allyRageDmgBonus
    end
    local timeLimit = GameConfig.Battle and GameConfig.Battle.TIME_LIMIT_SEC or 300
    if cfg.rageTime >= timeLimit then
        cfg.rageTime = math.floor(timeLimit * 0.4)
    end
    if cfg.superRageTime >= timeLimit then
        cfg.superRageTime = math.floor(timeLimit * 0.7)
    end
    if cfg.superRageTime <= cfg.rageTime then
        cfg.superRageTime = math.min(timeLimit - 30, cfg.rageTime + 90)
    end

    -- 重置状态
    active    = true
    elapsed   = 0
    ragePhase = 0
    origIntervals = {}
    origAtkCoeffs = {}
    origUnitAtkCoeffs = {}
    bannerText_   = nil
    bannerTimer_  = 0

    -- 缓存当前场上敌人与己方单位的原始攻速/攻击力倍率
    for _, u in ipairs(enemies or {}) do
        if u.hp and u.hp > 0 then
            cacheBaseValues(u)
        end
    end
    local allyBuffCount = 0
    for _, u in ipairs(allies or {}) do
        if u.hp and u.hp > 0 and isAllyUnit(u) then
            cacheBaseValues(u)
            allyBuffCount = allyBuffCount + 1
        end
    end

    print(string.format("[StageBerserk] enter enemies=%d allies=%d rageTime=%ds/%ds atkBonus=+%.0f%%/+%.0f%% dmgBonus=enemy+%.0f%% ally+%.0f%%/+%.0f%%",
        #(enemies or {}), allyBuffCount, cfg.rageTime, cfg.superRageTime,
        cfg.rageAtkBonus * 100, cfg.superRageAtkBonus * 100,
        cfg.superRageDmgBonus * 100, cfg.allyRageDmgBonus * 100, cfg.allySuperRageDmgBonus * 100))
end

-- 给单位应用攻速/攻击力加成（idempotent）
local function applyUnitBuffs(units, atkBonus, dmgBonus, predicate)
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

-- 每帧由 BattleScene.update 调用
-- dt: 帧间隔, enemies: 敌方单位列表引用（含新入场的单位）, allies: 己方单位列表引用
function StageBerserk.update(dt, enemies, allies)
    if not active then return end

    elapsed = elapsed + dt

    -- 递减提示横幅计时
    if bannerTimer_ > 0 then
        bannerTimer_ = math.max(0, bannerTimer_ - dt)
    end

    -- 狂暴阶段检测
    if ragePhase == 0 and elapsed >= cfg.rageTime then
        ragePhase = 1
        applyUnitBuffs(enemies, cfg.rageAtkBonus, 0, nil)
        applyUnitBuffs(allies, cfg.rageAtkBonus, cfg.allyRageDmgBonus, isAllyUnit)
        bannerText_  = string.format("⚠ 怪物进入狂暴！己方攻速 +%.0f%%、攻击力 +%.0f%%",
            cfg.rageAtkBonus * 100, cfg.allyRageDmgBonus * 100)
        bannerTimer_ = BANNER_DURATION
        print(string.format("[StageBerserk] RAGE triggered at %.1fs (enemy atk speed +%.0f%%, ally atk speed +%.0f%%, atk coeff +%.0f%%)",
            elapsed, cfg.rageAtkBonus * 100, cfg.rageAtkBonus * 100, cfg.allyRageDmgBonus * 100))
    elseif ragePhase == 1 and elapsed >= cfg.superRageTime then
        ragePhase = 2
        applyUnitBuffs(enemies, cfg.superRageAtkBonus, cfg.superRageDmgBonus, nil)
        applyUnitBuffs(allies, cfg.superRageAtkBonus, cfg.allySuperRageDmgBonus, isAllyUnit)
        bannerText_  = string.format("⚠ 怪物超级狂暴！己方攻速 +%.0f%%、攻击力 +%.0f%%",
            cfg.superRageAtkBonus * 100, cfg.allySuperRageDmgBonus * 100)
        bannerTimer_ = BANNER_DURATION
        print(string.format("[StageBerserk] SUPER RAGE triggered at %.1fs (enemy atk speed +%.0f%%, enemy atk coeff +%.0f%%, ally atk speed +%.0f%%, atk coeff +%.0f%%)",
            elapsed, cfg.superRageAtkBonus * 100, cfg.superRageDmgBonus * 100,
            cfg.superRageAtkBonus * 100, cfg.allySuperRageDmgBonus * 100))
    end

    -- 确保新入场的敌人/己方单位也吃到当前阶段的 buff（idempotent）
    if ragePhase >= 1 then
        if ragePhase == 1 then
            applyUnitBuffs(enemies, cfg.rageAtkBonus, 0, nil)
            applyUnitBuffs(allies, cfg.rageAtkBonus, cfg.allyRageDmgBonus, isAllyUnit)
        else
            applyUnitBuffs(enemies, cfg.superRageAtkBonus, cfg.superRageDmgBonus, nil)
            applyUnitBuffs(allies, cfg.superRageAtkBonus, cfg.allySuperRageDmgBonus, isAllyUnit)
        end
    end
end

-- 退出首通狂暴模式
function StageBerserk.exit()
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
    origIntervals = {}
    origAtkCoeffs = {}
    origUnitAtkCoeffs = {}
    bannerText_   = nil
    bannerTimer_  = 0
    print("[StageBerserk] exit")
end

return StageBerserk
