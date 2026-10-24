-- StageBerserk - 首通战斗狂暴模块
-- 会话推进、阶段策略、单位基准恢复、提示横幅各自负责；对外仍是原来的七个 API。
-- 所有可变状态留在本源码实例内，兼容副本用 load 创建独立实例。
local StageBerserk = {}

-- 配置跨会话保留。enter 没有 StageBerserk 配置时沿用上一次值，不能重建默认表。
local cfg = {
    rageTime              = 120,
    rageAtkBonus          = 0.50,
    superRageTime         = 210,
    superRageAtkBonus     = 1.00,
    superRageDmgBonus     = 0.30,
    allyRageDmgBonus      = 0.30,
    allySuperRageDmgBonus = 0.30,
}

local function refreshConfig()
    -- 每次 enter 都 require；逐字段访问不能改成预取子表，配置可以动态提供值。
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
end

-- 单位基准账本：三张表分别惰性捕获，恢复也分三轮，不能合成单条快照。
-- nil/false 用 or 重捕获、0 保留；未有 attrs 的单位可在后续帧补捕获。
local UnitBases = {
    intervals = {},
    attrCoeffs = {},
    unitCoeffs = {},
}

function UnitBases:clear()
    self.intervals = {}
    self.attrCoeffs = {}
    self.unitCoeffs = {}
end

function UnitBases:capture(u)
    if not u then return end
    self.intervals[u] = self.intervals[u] or u.atkInterval
    if u.attrs then
        self.attrCoeffs[u] = self.attrCoeffs[u] or u.attrs.atkCoeff or 1.0
    end
    self.unitCoeffs[u] = self.unitCoeffs[u] or u.atkCoeff or (u.attrs and u.attrs.atkCoeff) or 1.0
end

local function isAllyUnit(u)
    return u and u.heroId ~= nil
end

function UnitBases:captureLiving(units, predicate)
    local count = 0
    for _, u in ipairs(units or {}) do
        if u.hp and u.hp > 0 and (not predicate or predicate(u)) then
            self:capture(u)
            count = count + 1
        end
    end
    return count
end

-- 每次从基准除攻速、乘伤害，不叠乘当前值；死亡单位不应用，但退出仍恢复。
function UnitBases:apply(units, atkBonus, dmgBonus, predicate)
    for _, u in ipairs(units or {}) do
        if u.hp and u.hp > 0 and (not predicate or predicate(u)) then
            self:capture(u)
            local baseInterval = self.intervals[u] or u.atkInterval or 1.0
            u.atkInterval = baseInterval / (1.0 + atkBonus)
            if dmgBonus > 0 then
                if u.attrs then
                    local baseCoeff = self.attrCoeffs[u] or u.attrs.atkCoeff or 1.0
                    u.attrs.atkCoeff = baseCoeff * (1.0 + dmgBonus)
                end
                local baseUnitCoeff = self.unitCoeffs[u] or u.atkCoeff or 1.0
                u.atkCoeff = baseUnitCoeff * (1.0 + dmgBonus)
            end
        end
    end
end

function UnitBases:restore()
    for u, baseInterval in pairs(self.intervals) do
        if u then u.atkInterval = baseInterval end
    end
    for u, baseCoeff in pairs(self.attrCoeffs) do
        if u and u.attrs then u.attrs.atkCoeff = baseCoeff end
    end
    for u, baseCoeff in pairs(self.unitCoeffs) do
        if u then u.atkCoeff = baseCoeff end
    end
end

-- 横幅只处理内容和显示寿命；是否活动、当前阶段由会话提供。
local Banner = { timer = 0 }
---@type string|nil
Banner.text = nil
local BANNER_DURATION = 2.5

function Banner:clear()
    self.text = nil
    self.timer = 0
end

function Banner:tick(dt)
    if self.timer > 0 then self.timer = math.max(0, self.timer - dt) end
end

function Banner:show(text)
    self.text = text
    self.timer = BANNER_DURATION
end

function Banner:get(active, phase)
    if not active or self.timer <= 0 or not self.text then return nil end
    local alpha = 1.0
    if self.timer < 0.6 then alpha = self.timer / 0.6 end
    return self.text, alpha, phase
end

-- 阶段策略按调用时的 cfg 应用，不把配置或倍率提前快照进策略。
local phases = {
    [1] = {
        reached = function(elapsed) return elapsed >= cfg.rageTime end,
        apply = function(enemies, allies)
            UnitBases:apply(enemies, cfg.rageAtkBonus, 0, nil)
            UnitBases:apply(allies, cfg.rageAtkBonus, cfg.allyRageDmgBonus, isAllyUnit)
        end,
        announce = function(elapsed)
            Banner:show(string.format("⚠ 怪物进入狂暴！己方攻速 +%.0f%%、攻击力 +%.0f%%",
                cfg.rageAtkBonus * 100, cfg.allyRageDmgBonus * 100))
            print(string.format("[StageBerserk] RAGE triggered at %.1fs (enemy atk speed +%.0f%%, ally atk speed +%.0f%%, atk coeff +%.0f%%)",
                elapsed, cfg.rageAtkBonus * 100, cfg.rageAtkBonus * 100, cfg.allyRageDmgBonus * 100))
        end,
    },
    [2] = {
        reached = function(elapsed) return elapsed >= cfg.superRageTime end,
        apply = function(enemies, allies)
            UnitBases:apply(enemies, cfg.superRageAtkBonus, cfg.superRageDmgBonus, nil)
            UnitBases:apply(allies, cfg.superRageAtkBonus, cfg.allySuperRageDmgBonus, isAllyUnit)
        end,
        announce = function(elapsed)
            Banner:show(string.format("⚠ 怪物超级狂暴！己方攻速 +%.0f%%、攻击力 +%.0f%%",
                cfg.superRageAtkBonus * 100, cfg.allySuperRageDmgBonus * 100))
            print(string.format("[StageBerserk] SUPER RAGE triggered at %.1fs (enemy atk speed +%.0f%%, enemy atk coeff +%.0f%%, ally atk speed +%.0f%%, atk coeff +%.0f%%)",
                elapsed, cfg.superRageAtkBonus * 100, cfg.superRageDmgBonus * 100,
                cfg.superRageAtkBonus * 100, cfg.allySuperRageDmgBonus * 100))
        end,
    },
}

local Session = { active = false, elapsed = 0, phase = 0 }

function Session:reset(active)
    self.active = active
    self.elapsed = 0
    self.phase = 0
    UnitBases:clear()
    Banner:clear()
end

function Session:advance(dt, enemies, allies)
    if not self.active then return end
    self.elapsed = self.elapsed + dt
    Banner:tick(dt)

    -- 只检查紧邻下一阶段，大 dt 也不在一帧跨两级。
    local nextPhase = phases[self.phase + 1]
    if nextPhase and nextPhase.reached(self.elapsed) then
        self.phase = self.phase + 1
        nextPhase.apply(enemies, allies)
        nextPhase.announce(self.elapsed)
    end

    -- 升阶帧也再次应用，保持原来的两轮写入；补位/复活仍惰性捕获基准。
    if self.phase >= 1 then phases[self.phase].apply(enemies, allies) end
end

function StageBerserk.isActive()
    return Session.active
end

function StageBerserk.getRagePhase()
    return Session.phase
end

function StageBerserk.getElapsed()
    return Session.elapsed
end

-- 有横幅返回三值，无横幅返回一个 nil（不能变成零返回值）。
function StageBerserk.getBanner()
    return Banner:get(Session.active, Session.phase)
end

-- enter 不恢复上一会话，仍先读配置，再清状态和捕获当前存活单位。
function StageBerserk.enter(enemies, allies)
    refreshConfig()
    Session:reset(true)
    UnitBases:captureLiving(enemies, nil)
    local allyBuffCount = UnitBases:captureLiving(allies, isAllyUnit)
    print(string.format("[StageBerserk] enter enemies=%d allies=%d rageTime=%ds/%ds atkBonus=+%.0f%%/+%.0f%% dmgBonus=enemy+%.0f%% ally+%.0f%%/+%.0f%%",
        #(enemies or {}), allyBuffCount, cfg.rageTime, cfg.superRageTime,
        cfg.rageAtkBonus * 100, cfg.superRageAtkBonus * 100,
        cfg.superRageDmgBonus * 100, cfg.allyRageDmgBonus * 100, cfg.allySuperRageDmgBonus * 100))
end

-- dt: 帧间隔；列表引用包含新入场单位。命令 API 仍不返回值。
function StageBerserk.update(dt, enemies, allies)
    Session:advance(dt, enemies, allies)
end

function StageBerserk.exit()
    UnitBases:restore()
    Session:reset(false)
    print("[StageBerserk] exit")
end

return StageBerserk
