-- ============================================================================
-- BossAffixSystem.lua — Boss 专属词缀战斗运行时（v2.64）
--
-- 职责：Hard+ 难度的章节 Boss（unit.isBoss）在首通战斗中获得专属强化词缀，
--       与 Normal 拉开机制差异（此前 Hard+ Boss 仅数值缩放、纯角色复用）。
--
-- 三类效果（对应 BossAffixConfig.AFFIXES[*].type）：
--   static —— onStageLoad 后由 applyToBosses 一次性改属性（守护壁垒/强韧/迅捷）
--   enrage —— tick 中检测 Boss 血量跌破阈值，一次性触发攻速+伤害强化（暴怒）
--   regen  —— tick 中每秒回血（再生）
--   thorns —— onBossDamaged 钩子反弹所受伤害给攻击者（荆棘之体）
--
-- 约束：
--   * 只作用于 isBoss 单位、只在首通模式（与地图词缀一致；挂机/扫荡不叠加）。
--   * 不影响 StageRecommendPower 采样口径：battle-lab 采样打的是各章 stage1
--     首关（无 Boss），Boss 词缀只在 stage5 生效，两者解耦。
--   * 全百分比参数，自动适配任意 monsterLevel。
-- ============================================================================

local BossAffixConfig = require("config.BossAffixConfig")
local AD              = require("systems.AttributeDef")

local BossAffixSystem = {}

--- 每条战线独占配置、再生余量、暴怒幂等表和提示。
---@class BossAffixState
---@field activeAffixes table[]|nil
---@field runtime table
local function newState()
    return { activeAffixes = nil,
        runtime = { regenAccum = 0, enraged = {}, bannerText = nil, bannerTimer = 0 } }
end
local defaultState = newState()
local state_ = defaultState
function BossAffixSystem.newState() return newState() end
function BossAffixSystem.mount(state) state_ = state or defaultState end
function BossAffixSystem.getState() return state_ end
function BossAffixSystem.restoreDefault() state_ = defaultState end
local BANNER_DURATION = 2.5

--- 重算实际攻击间隔（改 ATK_SPEED 后调用）
local function recalcInterval(unit)
    if not unit or not unit.attrs then return end
    if unit.attrs.getActualInterval then
        unit.atkInterval = unit.attrs:getActualInterval()
    else
        local baseInterval = unit.attrs.final[AD.ATK_INTERVAL] or 1.5
        local spd = unit.attrs.final[AD.ATK_SPEED] or 0
        unit.atkInterval = baseInterval / (1 + math.max(0, spd) / 100)
    end
end

--- 同步 unit.hp / maxHp（回血或改血上限后）
local function syncHp(unit)
    local BattleCombat = require("ui.battle.combat.BattleCombat")
    if BattleCombat and BattleCombat.syncUnitHp then
        BattleCombat.syncUnitHp(unit)
    elseif unit.attrs then
        unit.hp = unit.attrs:get(AD.HP)
        unit.maxHp = unit.attrs:get(AD.MAX_HP)
    end
end

--- 取参数（按 id）
---@param id string
---@return table|nil
local function getP(id)
    if not state_.activeAffixes then return nil end
    for _, a in ipairs(state_.activeAffixes) do
        if a.id == id then return a.params end
    end
    return nil
end

-- ============================================================================
-- 生命周期
-- ============================================================================

--- 关卡加载时设置激活词缀
---@param chapter number 全局章节号
---@param difficulty string 难度字符串（SC.getDifficulty）
function BossAffixSystem.onStageLoad(chapter, difficulty)
    state_.runtime.regenAccum = 0
    state_.runtime.enraged = {}
    state_.runtime.bannerText = nil
    state_.runtime.bannerTimer = 0
    state_.activeAffixes = BossAffixConfig.getAffixesForBoss(chapter, difficulty)
end

--- 清空（挂机/Normal/离开战斗）
function BossAffixSystem.clear()
    state_.activeAffixes = nil
    state_.runtime.regenAccum = 0
    state_.runtime.enraged = {}
    state_.runtime.bannerText = nil
    state_.runtime.bannerTimer = 0
end

---@return boolean
function BossAffixSystem.hasAffixes()
    return state_.activeAffixes ~= nil and #state_.activeAffixes > 0
end

---@return table[]|nil
function BossAffixSystem.getActiveAffixes()
    return state_.activeAffixes
end

--- 把 static 类词缀应用到 Boss 单位（出场后一次性）
---@param enemies table[] 全部敌方（场上+队列），内部筛 isBoss
function BossAffixSystem.applyToBosses(enemies)
    if not state_.activeAffixes then return end
    for _, enemy in ipairs(enemies or {}) do
        if enemy.isBoss and enemy.attrs and enemy.attrs.final then
            local fin = enemy.attrs.final
            -- 守护壁垒：最大生命百分比护盾
            local shieldP = getP("warden_shield")
            if shieldP then
                local maxHp = fin[AD.MAX_HP] or 0
                local amount = math.floor(maxHp * (shieldP.shieldPct or 0) + 0.5)
                if amount > 0 then
                    fin[AD.ENERGY_SHIELD] = (fin[AD.ENERGY_SHIELD] or 0) + amount
                    enemy.attrs.energyShield = (enemy.attrs.energyShield or 0) + amount
                end
            end
            -- 强韧：最大生命提升（当前血按比例同步，保持满血出场）
            local fortP = getP("fortify")
            if fortP then
                local oldMax = fin[AD.MAX_HP] or 0
                local newMax = math.floor(oldMax * (1 + (fortP.hpPct or 0)) + 0.5)
                if newMax > oldMax then
                    local curHp = fin[AD.HP] or oldMax
                    local ratio = oldMax > 0 and (curHp / oldMax) or 1
                    fin[AD.MAX_HP] = newMax
                    fin[AD.HP] = math.floor(newMax * ratio + 0.5)
                    enemy.maxHp = newMax
                    enemy.hp = fin[AD.HP]
                end
            end
            -- 迅捷：攻速提升
            local hasteP = getP("haste")
            if hasteP then
                fin[AD.ATK_SPEED] = (fin[AD.ATK_SPEED] or 0) + (hasteP.atkSpeedPct or 0) * 100
                recalcInterval(enemy)
            end
        end
    end
end

-- ============================================================================
-- 动态效果：每帧 tick（enrage / regen）
-- ============================================================================

--- 每帧调用（仅首通、Boss 在场时）
---@param dt number
---@param enemies table[]
function BossAffixSystem.tick(dt, enemies)
    if not state_.activeAffixes then return end

    -- 暴怒提示横幅计时
    if state_.runtime.bannerTimer > 0 then
        state_.runtime.bannerTimer = math.max(0, state_.runtime.bannerTimer - dt)
    end

    local enrageP = getP("enrage")
    local regenP = getP("regen")
    if not enrageP and not regenP then return end

    -- 再生：每秒回血累积
    if regenP then
        state_.runtime.regenAccum = state_.runtime.regenAccum + dt
        while state_.runtime.regenAccum >= 1.0 do
            state_.runtime.regenAccum = state_.runtime.regenAccum - 1.0
            for _, enemy in ipairs(enemies or {}) do
                if enemy.isBoss and enemy.hp and enemy.hp > 0 and enemy.attrs then
                    local maxHp = enemy.attrs.final[AD.MAX_HP] or 0
                    local amount = maxHp * (regenP.hpPctPerSec or 0)
                    if amount > 0 and enemy.attrs:heal(amount) > 0 then
                        syncHp(enemy)
                    end
                end
            end
        end
    end

    -- 暴怒：血量跌破阈值一次性触发
    if enrageP then
        for _, enemy in ipairs(enemies or {}) do
            if enemy.isBoss and enemy.hp and enemy.hp > 0 and enemy.attrs
               and not state_.runtime.enraged[enemy] then
                local maxHp = enemy.attrs.final[AD.MAX_HP] or 0
                if maxHp > 0 and (enemy.hp / maxHp) <= (enrageP.threshold or 0) then
                    state_.runtime.enraged[enemy] = true
                    local fin = enemy.attrs.final
                    fin[AD.DMG_BONUS] = (fin[AD.DMG_BONUS] or 0) + (enrageP.dmgPct or 0) * 100
                    fin[AD.ATK_SPEED] = (fin[AD.ATK_SPEED] or 0) + (enrageP.atkSpeedPct or 0) * 100
                    recalcInterval(enemy)
                    state_.runtime.bannerText = "⚠ " .. (enemy.name or "Boss") .. " 进入暴怒！"
                    state_.runtime.bannerTimer = BANNER_DURATION
                    print(string.format("[BossAffix] 暴怒触发 boss=%s hp%%=%.0f%% dmg+%.0f%% spd+%.0f%%",
                        tostring(enemy.name), enemy.hp / maxHp * 100,
                        (enrageP.dmgPct or 0) * 100, (enrageP.atkSpeedPct or 0) * 100))
                end
            end
        end
    end
end

-- ============================================================================
-- 受击钩子：荆棘之体反弹
-- ============================================================================

--- Boss 受到伤害后调用（在 dealDamageToUnit 中，伤害实际结算后）
---@param boss table 受击的敌方 Boss
---@param attacker table 攻击者（反弹目标）
---@param actualDamage number 实际造成的伤害
---@param dealDamageFn function|nil 可选伤害函数注入（测试用）；缺省走 BattleCombat.dealDamageToUnit
---@return boolean reflected 是否发生了反弹（调用方避免二次处理）
function BossAffixSystem.onBossDamaged(boss, attacker, actualDamage, dealDamageFn)
    if not state_.activeAffixes then return false end
    local thornsP = getP("thorns")
    if not thornsP then return false end
    if not boss or not boss.isBoss or boss.hp <= 0 then return false end
    if not attacker or not attacker.heroId or attacker.hp <= 0 then return false end
    if boss._thornsReflecting then return false end  -- 防重入

    local reflect = math.floor((actualDamage or 0) * (thornsP.reflectPct or 0) + 0.5)
    if reflect <= 0 then return false end

    local deal = dealDamageFn
    if not deal then
        local BattleCombat = require("ui.battle.combat.BattleCombat")
        if not BattleCombat or not BattleCombat.dealDamageToUnit then return false end
        deal = BattleCombat.dealDamageToUnit
    end

    boss._thornsReflecting = true
    deal(attacker, reflect, true, "荆棘", { 200, 120, 255 }, boss, { noCounter = true })
    boss._thornsReflecting = nil
    return true
end

-- ============================================================================
-- UI：暴怒提示横幅（BattleScene 渲染段读取）
-- ============================================================================

---@return string|nil text, number|nil alpha
function BossAffixSystem.getBanner()
    if state_.runtime.bannerTimer <= 0 or not state_.runtime.bannerText then return nil end
    local alpha = 1.0
    if state_.runtime.bannerTimer < 0.6 then alpha = state_.runtime.bannerTimer / 0.6 end
    return state_.runtime.bannerText, alpha
end

return BossAffixSystem
