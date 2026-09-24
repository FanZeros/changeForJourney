-- ============================================================================
-- BattleSceneTick - 攻击进度 / DOT HOT / 天赋计时 / 护盾回血
-- 从 BattleScene.update 抽出；标量 regenAccum 经 ctx 回写
-- ============================================================================

local SEM = require("systems.StatusEffectManager")
local RCH = require("systems.RelicConditionHandler")
local TM  = require("systems.ThreatManager")
local TAL = require("systems.TalentManager")
local MAS = require("systems.MapAffixSystem")
local BattleCombat = require("ui.battle.BattleCombat")

local M = {}

function M.tick(ctx, logicDt)
    -- ---- 更新攻击进度 ----
    -- 预先统计双方存活数，无目标时进度条停在满格等待
    local hasAliveEnemy = false
    for _, u in ipairs(ctx.enemies) do
    if u.hp > 0 then hasAliveEnemy = true; break end
    end
    local hasAliveAlly = false
    for _, u in ipairs(ctx.allies) do
    if u.hp > 0 then hasAliveAlly = true; break end
    end

    for _, unit in ipairs(ctx.allies) do
    if unit.hp > 0 and not SEM.isFrozen(unit) then
        local interval = ctx.getLiveAttackInterval(unit, ctx.DEFAULT_ALLY_INTERVAL)
        BattleCombat.advanceAttackProgress(unit, logicDt, interval, hasAliveEnemy, function()
            ctx.performAttack(unit, ctx.enemies, true)
        end)
    end
    end

    -- [EnemyGuard] 每帧检查 ctx.enemies 是否被污染（仅首次触发）
    ctx.checkEnemiesCorruption("UPDATE_LOOP")

    for _, unit in ipairs(ctx.enemies) do
    if unit.hp > 0 and not SEM.isFrozen(unit) then
        local interval = ctx.getLiveAttackInterval(unit, ctx.DEFAULT_ENEMY_INTERVAL)
        BattleCombat.advanceAttackProgress(unit, logicDt, interval, hasAliveAlly, function()
            ctx.performAttack(unit, ctx.allies, false)
        end)
    end
    end

    -- ---- 遗物条件词条每帧检查（HP阈值、限时buff到期等） ----
    RCH.update(ctx.allies, 0)

    -- ---- 更新血条缓冲（白色拖尾） ----
    BattleCombat.updateHpBuffers(ctx.allies, logicDt)
    BattleCombat.updateHpBuffers(ctx.enemies, logicDt)

    -- ---- 更新仇恨衰减 ----
    TM.update(logicDt)

    -- ---- 更新状态效果（DOT/HOT tick） ----
    SEM.update(logicDt, {
    onDot = function(unit, source, dmg)
        -- 判断目标是否为己方
        local isUnitAlly = false
        for _, u in ipairs(ctx.allies) do
            if u == unit then isUnitAlly = true; break end
        end
        ctx.dealDamageToUnit(unit, dmg, isUnitAlly, "灼烧 ", {255, 120, 30}, source, { isDot = true })
    end,
    onHot = function(unit, source, heal)
        if unit.attrs and unit.hp > 0 then
            local actual = unit.attrs:heal(heal)
            ctx.syncUnitHp(unit)
            if actual > 0 then
                local isUnitAlly = false
                for _, u in ipairs(ctx.allies) do
                    if u == unit then isUnitAlly = true; break end
                end
                local cy = isUnitAlly and ctx.ALLY_CARD_CY or ctx.ENEMY_CARD_CY
                local list = isUnitAlly and ctx.allies or ctx.enemies
                local cx = ctx.DESIGN_W * 0.5
                for ii, u in ipairs(list) do
                    if u == unit then cx = ctx.getCardCX(list, ii); break end
                end
                ctx.addFloatingText("恢复 +" .. require("core.NumberUtil").format(actual), cx, cy, {0, 255, 82}, false)
                -- 战斗统计：HOT 持续治疗输出（来源为己方英雄时归因）
                if source and source.heroId then
                    require("systems.BattleStats").recordHeal(source, actual, true)
                end
            end
        end
    end,
    })

    -- ---- 更新天赋计时器（转职天赋: 10秒周期/巡游射击延迟/暗影倒计时等） ----
    TAL.update(logicDt, ctx.allies, ctx.enemies, {
    healUnit = function(unit, amount)
        if unit.attrs and unit.hp > 0 then
            local actual = unit.attrs:heal(amount)
            ctx.syncUnitHp(unit)
            return actual
        end
        return 0
    end,
    dealDamage = function(target, damage, isTargetAlly, prefix, color, source)
        return ctx.dealDamageToUnit(target, damage, isTargetAlly, prefix, color, source)
    end,
    dealTalentDamage = function(attacker, target, damage, isTargetAlly, prefix, color, projOpts)
        return BattleCombat.dealTalentDamage(attacker, target, damage, isTargetAlly, prefix, color, projOpts, ctx.allies, ctx.enemies)
    end,
    syncHp = function(unit)
        ctx.syncUnitHp(unit)
    end,
    performAttack = function(attacker, targetList, isAlly)
        ctx.performAttack(attacker, targetList, isAlly)
    end,
    })

    -- ---- 地图词缀动态 tick（仅首通模式） ----
    if ctx.isFirstClear and MAS.hasAffixes() then
    MAS.tick(logicDt, ctx.allies, ctx.enemies)
    end

    -- ---- 能量护盾恢复 tick ----
    for _, u in ipairs(ctx.allies) do
    if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(logicDt) end
    end
    for _, u in ipairs(ctx.enemies) do
    if u.hp > 0 and u.attrs then u.attrs:tickEnergyShield(logicDt) end
    end

    -- ---- 每秒回血（HP_REGEN 属性） ----
    ctx.regenAccum = ctx.regenAccum + logicDt
    while ctx.regenAccum >= 1.0 do
    ctx.regenAccum = ctx.regenAccum - 1.0
    local allUnits = {}
    for _, u in ipairs(ctx.allies)  do allUnits[#allUnits + 1] = { unit = u, isAlly = true  } end
    for _, u in ipairs(ctx.enemies) do allUnits[#allUnits + 1] = { unit = u, isAlly = false } end
    for _, entry in ipairs(allUnits) do
        local u = entry.unit
        if u.hp > 0 and u.attrs then
            local regenAmt = require("systems.CombatFormula").calcHpRegen(u.attrs)
            if regenAmt > 0 then
                local actual = u.attrs:heal(regenAmt)
                if actual > 0 then
                    ctx.syncUnitHp(u)
                    -- 显示回血浮字，让玩家看到 HP_REGEN 的实际回复量
                    local list = entry.isAlly and ctx.allies or ctx.enemies
                    local cy = entry.isAlly and ctx.ALLY_CARD_CY or ctx.ENEMY_CARD_CY
                    local cx = ctx.DESIGN_W * 0.5
                    for ii, uu in ipairs(list) do
                        if uu == u then cx = ctx.getCardCX(list, ii); break end
                    end
                    ctx.addFloatingText("回复 +" .. require("core.NumberUtil").format(actual), cx, cy, {0, 255, 82}, false)
                end
            end
        end
    end
    end


end

return M
