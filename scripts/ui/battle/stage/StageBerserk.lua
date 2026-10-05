-- StageBerserk - 首通战斗狂暴模块
-- 职责: 管理首通战斗中的狂暴机制（敌我渐强），防止肉+奶无限磨血
-- 每条战线持有自己的阶段、计时、原始数值和横幅；mount不清理单位。
local StageBerserk = {}

---@class StageBerserkState
---@field active boolean
---@field elapsed number
---@field ragePhase number
---@field origIntervals table
---@field origAtkCoeffs table
---@field origUnitAtkCoeffs table
---@field bannerText string|nil
---@field bannerTimer number
---@field cfg table
local function newState()
    return { active = false, elapsed = 0, ragePhase = 0,
        origIntervals = {}, origAtkCoeffs = {}, origUnitAtkCoeffs = {},
        bannerText = nil, bannerTimer = 0,
        cfg = { rageTime = 120, rageAtkBonus = 0.50,
            superRageTime = 210, superRageAtkBonus = 1.00, superRageDmgBonus = 0.30,
            allyRageDmgBonus = 0.30, allySuperRageDmgBonus = 0.30 },
    }
end
local defaultState = newState()
local state_ = defaultState
function StageBerserk.newState() return newState() end
function StageBerserk.mount(state) state_ = state or defaultState end
function StageBerserk.getState() return state_ end
function StageBerserk.restoreDefault() state_ = defaultState end
local BANNER_DURATION = 2.5

function StageBerserk.isActive() return state_.active end
function StageBerserk.getRagePhase() return state_.ragePhase end
function StageBerserk.getElapsed() return state_.elapsed end

function StageBerserk.getBanner()
    if not state_.active or state_.bannerTimer <= 0 or not state_.bannerText then return nil end
    local alpha = state_.bannerTimer < 0.6 and state_.bannerTimer / 0.6 or 1.0
    return state_.bannerText, alpha, state_.ragePhase
end

local function cacheBaseValues(unit)
    if not unit then return end
    state_.origIntervals[unit] = state_.origIntervals[unit] or unit.atkInterval
    if unit.attrs then
        state_.origAtkCoeffs[unit] = state_.origAtkCoeffs[unit] or unit.attrs.atkCoeff or 1.0
    end
    state_.origUnitAtkCoeffs[unit] = state_.origUnitAtkCoeffs[unit]
        or unit.atkCoeff or (unit.attrs and unit.attrs.atkCoeff) or 1.0
end
local function isAllyUnit(unit) return unit and unit.heroId ~= nil end

-- Driver以attrs实时攻速为源；狂暴是乘区，不应被getActualInterval绕过。
-- 保留地图/暴怒/时空裂隙在本帧改变的属性攻速，挂机/未狂暴原值返回。
function StageBerserk.getAttackInterval(unit, liveInterval)
    if not state_.active or state_.ragePhase <= 0 or not state_.origUnitAtkCoeffs[unit] then
        return liveInterval
    end
    local cfg = state_.cfg
    local bonus = state_.ragePhase == 1 and cfg.rageAtkBonus or cfg.superRageAtkBonus
    return liveInterval / (1 + bonus)
end

-- 退出只恢复本容器追踪的单位；别的战线开场/退出绝不恢复本线数值。
function StageBerserk.exit()
    for unit, value in pairs(state_.origIntervals) do unit.atkInterval = value end
    for unit, value in pairs(state_.origAtkCoeffs) do
        if unit.attrs then unit.attrs.atkCoeff = value end
    end
    for unit, value in pairs(state_.origUnitAtkCoeffs) do unit.atkCoeff = value end
    state_.active, state_.elapsed, state_.ragePhase = false, 0, 0
    state_.origIntervals, state_.origAtkCoeffs, state_.origUnitAtkCoeffs = {}, {}, {}
    state_.bannerText, state_.bannerTimer = nil, 0
    print("[StageBerserk] exit")
end

function StageBerserk.enter(enemies, allies)
    -- 同实例重开先恢复旧单位，不能丢弃旧cache而留下已乘狂暴的系数。
    if state_.active then StageBerserk.exit() end
    local GameConfig = require("config.GameConfig")
    local cfg = state_.cfg
    local settings = GameConfig.StageBerserk or {}
    cfg.rageTime = settings.RAGE_TIME or 120
    cfg.rageAtkBonus = settings.RAGE_ATK_BONUS or 0.50
    cfg.superRageTime = settings.SUPER_RAGE_TIME or 210
    cfg.superRageAtkBonus = settings.SUPER_RAGE_ATK_BONUS or 1.00
    cfg.superRageDmgBonus = settings.SUPER_RAGE_DMG_BONUS or 0.30
    cfg.allyRageDmgBonus = settings.ALLY_RAGE_DMG_BONUS or 0.30
    cfg.allySuperRageDmgBonus = settings.ALLY_SUPER_RAGE_DMG_BONUS or cfg.allyRageDmgBonus
    local timeLimit = GameConfig.Battle and GameConfig.Battle.TIME_LIMIT_SEC or 300
    if cfg.rageTime >= timeLimit then cfg.rageTime = math.floor(timeLimit * 0.4) end
    if cfg.superRageTime >= timeLimit then cfg.superRageTime = math.floor(timeLimit * 0.7) end
    if cfg.superRageTime <= cfg.rageTime then
        cfg.superRageTime = math.min(timeLimit - 30, cfg.rageTime + 90)
    end
    state_.active, state_.elapsed, state_.ragePhase = true, 0, 0
    state_.origIntervals, state_.origAtkCoeffs, state_.origUnitAtkCoeffs = {}, {}, {}
    state_.bannerText, state_.bannerTimer = nil, 0
    for _, unit in ipairs(enemies or {}) do
        if unit.hp and unit.hp > 0 then cacheBaseValues(unit) end
    end
    local allyCount = 0
    for _, unit in ipairs(allies or {}) do
        if unit.hp and unit.hp > 0 and isAllyUnit(unit) then
            cacheBaseValues(unit)
            allyCount = allyCount + 1
        end
    end
    print(string.format("[StageBerserk] enter enemies=%d allies=%d rageTime=%ds/%ds atkBonus=+%.0f%%/+%.0f%% dmgBonus=enemy+%.0f%% ally+%.0f%%/+%.0f%%",
        #(enemies or {}), allyCount, cfg.rageTime, cfg.superRageTime,
        cfg.rageAtkBonus * 100, cfg.superRageAtkBonus * 100,
        cfg.superRageDmgBonus * 100, cfg.allyRageDmgBonus * 100, cfg.allySuperRageDmgBonus * 100))
end

local function applyUnitBuffs(units, atkBonus, dmgBonus, predicate)
    for _, unit in ipairs(units or {}) do
        if unit.hp and unit.hp > 0 and (not predicate or predicate(unit)) then
            cacheBaseValues(unit)
            local interval = state_.origIntervals[unit] or unit.atkInterval or 1.0
            unit.atkInterval = interval / (1 + atkBonus)
            if dmgBonus > 0 then
                if unit.attrs then
                    local base = state_.origAtkCoeffs[unit] or unit.attrs.atkCoeff or 1.0
                    unit.attrs.atkCoeff = base * (1 + dmgBonus)
                end
                local base = state_.origUnitAtkCoeffs[unit] or unit.atkCoeff or 1.0
                unit.atkCoeff = base * (1 + dmgBonus)
            end
        end
    end
end

-- 含新入场单位；按当前阶段幂等应用，仍采用现行120/210秒规则。
function StageBerserk.update(dt, enemies, allies)
    if not state_.active then return end
    local cfg = state_.cfg
    state_.elapsed = state_.elapsed + dt
    state_.bannerTimer = math.max(0, state_.bannerTimer - dt)
    if state_.ragePhase == 0 and state_.elapsed >= cfg.rageTime then
        state_.ragePhase = 1
        state_.bannerText = string.format("\u{26A0} 怪物进入狂暴！己方攻速 +%.0f%%、攻击力 +%.0f%%",
            cfg.rageAtkBonus * 100, cfg.allyRageDmgBonus * 100)
        state_.bannerTimer = BANNER_DURATION
        print(string.format("[StageBerserk] RAGE triggered at %.1fs", state_.elapsed))
    elseif state_.ragePhase == 1 and state_.elapsed >= cfg.superRageTime then
        state_.ragePhase = 2
        state_.bannerText = string.format("\u{26A0} 怪物超级狂暴！己方攻速 +%.0f%%、攻击力 +%.0f%%",
            cfg.superRageAtkBonus * 100, cfg.allySuperRageDmgBonus * 100)
        state_.bannerTimer = BANNER_DURATION
        print(string.format("[StageBerserk] SUPER RAGE triggered at %.1fs", state_.elapsed))
    end
    if state_.ragePhase == 1 then
        applyUnitBuffs(enemies, cfg.rageAtkBonus, 0)
        applyUnitBuffs(allies, cfg.rageAtkBonus, cfg.allyRageDmgBonus, isAllyUnit)
    elseif state_.ragePhase == 2 then
        applyUnitBuffs(enemies, cfg.superRageAtkBonus, cfg.superRageDmgBonus)
        applyUnitBuffs(allies, cfg.superRageAtkBonus, cfg.allySuperRageDmgBonus, isAllyUnit)
    end
end

return StageBerserk
