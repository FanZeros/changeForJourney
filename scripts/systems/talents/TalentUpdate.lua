-- ============================================================================
-- TalentUpdate - TAL.update 周期计时器（从 TalentManager 抽出）
-- Bound via M.bind(deps)
-- ============================================================================

local AD  = require("systems.AttributeDef")
local SEM = require("systems.StatusEffectManager")
local ETS = require("systems.ExtraTalentSystem")

local M = {}

function M.bind(deps)
    local getState = deps.getState
    local hasAdv = deps.hasAdv
    local hasAwaken = deps.hasAwaken
    local talentLog = deps.talentLog
    local calcDragonBloodThreatLead = deps.calcDragonBloodThreatLead
    local getTAL_BCS = deps.getTAL_BCS or function() return deps.TAL_BCS end
    local fireLuoxingFlyingSwords = deps.fireLuoxingFlyingSwords
    local getLuoxingFlyingSwordInterval = deps.getLuoxingFlyingSwordInterval
    local resetLuoxingFlyingSwordWindow = deps.resetLuoxingFlyingSwordWindow
    local isMelissaStarGateAttackSourceActive = deps.isMelissaStarGateAttackSourceActive
    local updateMelissaStarGate = deps.updateMelissaStarGate
    local getAliveEnemies = deps.getAliveEnemies
    local isHighestThreat = deps.isHighestThreat
    local findLivingElwyn = deps.findLivingElwyn
    local tryElwynInvulnOnEsBreak = deps.tryElwynInvulnOnEsBreak
    local onFourNewUpdate = deps.onFourNewUpdate

    local function update(dt, allies, enemies, ctx)
    local TAL_BCS = getTAL_BCS()
    local TM = require("systems.ThreatManager")
    TAL_BCS.dealDamage = ctx and ctx.dealDamage
    ETS.update(dt)
    if onFourNewUpdate then
        onFourNewUpdate(dt, allies, enemies, ctx)
    end

    for _, ally in ipairs(allies) do
        if ally.hp > 0 then
            -- ======== HOT 过期清理：卡皮巴拉觉醒2/5 →modifier ========
            if ally.attrs and not SEM.has(ally, SEM.HOT) then
                ally.attrs:removeModifier("awaken_hot_armor")
                ally.attrs:removeModifier("awaken_hot_protection")
            end

            local s = getState(ally)
            if not s then goto continue_ally end

            -- ======== 10秒周期计时器 (101/102/105/109) ========
            local needsTimer = hasAdv(ally, "adv_101_holy_light")
                or hasAdv(ally, "adv_102_dragon_blood")
                or hasAdv(ally, "adv_105_vulnerability_curse")
                or hasAdv(ally, "adv_109_stealth")

            if needsTimer then
                s.advTimer = s.advTimer + dt
                if s.advTimer >= 10.0 then
                    s.advTimer = s.advTimer - 10.0

                    -- 101 圣光环 恢复10%HP
                    if hasAdv(ally, "adv_101_holy_light") and ally.attrs then
                        local maxHp = ally.maxHp or 1
                        local healPct = 0.10
                        -- 201 进阶圣光环 三倍→30%
                        if hasAdv(ally, "adv_201_advanced_holy") then
                            healPct = 0.30
                        end
                        local healAmt = math.floor(maxHp * healPct + 0.5)
                        local actual = ally.attrs:heal(healAmt)
                        ally.hp = ally.attrs:get(AD.HP)
                        if ally.hp > ally.maxHp then ally.hp = ally.maxHp end
                        if actual > 0 then
                            talentLog("[Talent] 圣光环 " .. ally.name .. " 恢复 " .. actual .. " HP")
                        end
                    end

                    -- 102 龙之血: 按模拟平A伤害×50领先仇恨，并强制嘲讽3秒
                    if hasAdv(ally, "adv_102_dragon_blood") then
                        local lead = calcDragonBloodThreatLead(ally, enemies)
                        TM.tauntToLead(ally, allies, lead)
                        TM.forceTarget(ally, 3.0)
                        talentLog("[Talent] 龙之血: 嘲讽领先+" .. tostring(lead) .. " 强制3秒")
                    end

                    -- 105 易伤诅咒: 对一个敌人施加5秒[易伤]+20%
                    if hasAdv(ally, "adv_105_vulnerability_curse") then
                        local alive = getAliveEnemies(enemies)
                        if #alive > 0 then
                            local duration = 8.0
                            local mult = 0.20
                            local has209 = hasAdv(ally, "adv_209_plague_curse")
                            local has210 = hasAdv(ally, "adv_210_corrosion_curse")
                            -- 209 群体诅咒者 诅咒所有敌人 效果+15%
                            if has209 then mult = 0.25 end
                            -- 210 蚀骨诅咒 持续时间隔5秒
                            if has210 then duration = 15.0 end

                            if has209 then
                                for _, enemy in ipairs(alive) do
                                    SEM.apply(enemy, SEM.VULNERABLE, duration, ally, { mult = mult })
                                end
                                talentLog("[Talent] 群体易伤诅咒: 全体敌人 " .. duration .. "s")
                            else
                                local target = alive[math.random(#alive)]
                                SEM.apply(target, SEM.VULNERABLE, duration, ally, { mult = mult })
                                talentLog("[Talent] 易伤诅咒 →" .. target.name)
                            end
                        end
                    end

                    -- 109 隐匿: 清空仇恨 + 5秒暗影状态
                    if hasAdv(ally, "adv_109_stealth") then
                        TM.removeUnit(ally)
                        s.shadowActive = true
                        s.shadowTimer = 5.0
                        ally.attrs:addModifier("talent_shadow", {
                            { key = AD.CRIT_RATE, flat = 15 },
                            { key = AD.CRIT_DMG, flat = 30 },
                        })
                        talentLog("[Talent] 隐匿: " .. ally.name .. " 清空仇恨 + 暗影状态5s")
                    end
                end

                -- 201 进阶圣光环 HP首次<50%/<20%立即释放
                if hasAdv(ally, "adv_201_advanced_holy") and ally.attrs then
                    local hpPct = ally.hp / math.max(1, ally.maxHp)
                    local healPct = 0.30
                    if hpPct < 0.50 and not s.holyTriggered50 then
                        s.holyTriggered50 = true
                        local healAmt = math.floor(ally.maxHp * healPct + 0.5)
                        ally.attrs:heal(healAmt)
                        ally.hp = ally.attrs:get(AD.HP)
                        if ally.hp > ally.maxHp then ally.hp = ally.maxHp end
                        talentLog("[Talent] 进阶圣光: 紧急治疗(<50%)")
                    end
                    if hpPct < 0.20 and not s.holyTriggered20 then
                        s.holyTriggered20 = true
                        local healAmt = math.floor(ally.maxHp * healPct + 0.5)
                        ally.attrs:heal(healAmt)
                        ally.hp = ally.attrs:get(AD.HP)
                        if ally.hp > ally.maxHp then ally.hp = ally.maxHp end
                        talentLog("[Talent] 进阶圣光: 紧急治疗(<20%)")
                    end
                end
            end

            -- ======== 复活吧爱人觉醒2: 被复活者治疗加成倒计时========
            if s.heroId == 15 and next(s.reviveHealBoostTargets) then
                for target, timer in pairs(s.reviveHealBoostTargets) do
                    s.reviveHealBoostTargets[target] = timer - dt
                    if s.reviveHealBoostTargets[target] <= 0 then
                        s.reviveHealBoostTargets[target] = nil
                        target._reviveHealBoost = nil
                        talentLog("[Talent] 复活吧爱人 觉醒2: " .. (target.name or "目标") .. " 治疗加成到期")
                    end
                end
            end

            -- ======== 护盾倒计时（觉醒6等）========
            if ally.shield and ally.shield.timer then
                ally.shield.timer = ally.shield.timer - dt
                if ally.shield.timer <= 0 then
                    ally.shield = nil
                    talentLog("[Talent] " .. (ally.name or "单位") .. " 护盾到期消失")
                end
            end

            -- ======== 接化发掌门觉醒3: 格挡减速倒计时========
            if s.blockSlowTargets and next(s.blockSlowTargets) then
                for target, timer in pairs(s.blockSlowTargets) do
                    s.blockSlowTargets[target] = timer - dt
                    if s.blockSlowTargets[target] <= 0 then
                        if target.attrs then
                            target.attrs:removeModifier("awaken_cecilia_slow_" .. tostring(ally))
                        end
                        s.blockSlowTargets[target] = nil
                    end
                end
            end

            -- ======== 雪皇 冰冻内置CD 倒计时 ========
            if s.freezeCD and next(s.freezeCD) then
                for target, cd in pairs(s.freezeCD) do
                    local left = cd - dt
                    if left <= 0 then
                        s.freezeCD[target] = nil
                    else
                        s.freezeCD[target] = left
                    end
                end
            end

            -- ======== 雪皇觉醒6: 首次<50%HP冰冻全场3秒 ========
            if s.heroId == 12 and hasAwaken(ally, 6) and not s.frozenAllTriggered then
                local hpPct = ally.hp / math.max(1, ally.maxHp or 1)
                if hpPct < 0.50 then
                    s.frozenAllTriggered = true
                    for _, enemy in ipairs(enemies) do
                        if enemy.hp > 0 then
                            SEM.apply(enemy, SEM.FROZEN, 3.0, ally, {})
                        end
                    end
                    talentLog("[Talent] 雪皇 觉醒6: 首次<50%HP→冰冻全场3秒")
                end
            end

            -- ======== 龙之血: 每帧实时判定是否最高仇恨+ 每秒回1%已损失HP ========
            if hasAdv(ally, "adv_102_dragon_blood") then
                s.dragonRegenActive = isHighestThreat(ally, allies, enemies)
            end
            if hasAdv(ally, "adv_102_dragon_blood") and s.dragonRegenActive and ally.attrs then
                local maxHp = ally.maxHp or 1
                local lostHp = maxHp - ally.hp
                if lostHp > 0 then
                    s.dragonRegenFrac = (s.dragonRegenFrac or 0) + lostHp * 0.02 * dt
                    local regen = math.floor(s.dragonRegenFrac)
                    if regen > 0 then
                        s.dragonRegenFrac = s.dragonRegenFrac - regen
                        ally.attrs:heal(regen)
                        ally.hp = ally.attrs:get(AD.HP)
                        if ally.hp > ally.maxHp then ally.hp = ally.maxHp end
                    end
                else
                    s.dragonRegenFrac = 0
                end
            end

            -- ======== 109 暗影状态倒计时========
            if s.shadowActive then
                s.shadowTimer = s.shadowTimer - dt
                if s.shadowTimer <= 0 then
                    s.shadowActive = false
                    ally.attrs:removeModifier("talent_shadow")
                    talentLog("[Talent] 暗影状态结果 " .. ally.name)
                end
            end

            -- ======== 107 巡游射击延迟队列 ========
            if #s.patrolQueue > 0 then
                local i = 1
                while i <= #s.patrolQueue do
                    local entry = s.patrolQueue[i]
                    entry.timer = entry.timer - dt
                    if entry.timer <= 0 then
                        -- 执行立即攻击
                        if entry.target and entry.target.hp > 0 and ally.hp > 0 and ctx.performAttack then
                            -- 213 风之气息: 触发时获得1层攻速12%, 5秒, max3
                            if hasAdv(ally, "adv_213_wind_spirit") then
                                s.windStacks = math.min(3, s.windStacks + 1)
                                s.windTimer = 5.0
                                ally.attrs:removeModifier("talent_wind")
                                ally.attrs:addModifier("talent_wind", {
                                    { key = AD.ATK_SPEED, flat = s.windStacks * 12 },
                                })
                            end
                            -- 214 林间之眼: 巡游射击必定暴击
                            if hasAdv(ally, "adv_214_forest_eye") then
                                ally.attrs:addModifier("talent_patrol_crit", {
                                    { key = AD.CRIT_RATE, flat = 100 },
                                })
                            end
                            ctx.performAttack(ally, enemies, true)
                            -- 移除临时暴击
                            if hasAdv(ally, "adv_214_forest_eye") then
                                ally.attrs:removeModifier("talent_patrol_crit")
                            end
                        end
                        table.remove(s.patrolQueue, i)
                    else
                        i = i + 1
                    end
                end
            end

            -- ======== 213 风之气息倒计时========
            if s.windStacks > 0 then
                s.windTimer = s.windTimer - dt
                if s.windTimer <= 0 then
                    s.windStacks = 0
                    ally.attrs:removeModifier("talent_wind")
                end
            end

            -- ======== 214 暴击提升倒计时========
            if s.critBoostStacks > 0 then
                s.critBoostTimer = s.critBoostTimer - dt
                if s.critBoostTimer <= 0 then
                    s.critBoostStacks = 0
                    ally.attrs:removeModifier("talent_crit_boost")
                end
            end

            -- ======== 210 蚀骨诅咒CD衰减 ========
            if next(s.corrosionCds) then
                for target, cd in pairs(s.corrosionCds) do
                    s.corrosionCds[target] = cd - dt
                    if s.corrosionCds[target] <= 0 then
                        s.corrosionCds[target] = nil
                    end
                end
            end

            -- ======== 217/218 瞬杀/千面: 5秒未受击检测========
            if hasAdv(ally, "adv_217_instant_kill") or hasAdv(ally, "adv_218_thousand_faces") then
                s.timeSinceHit = s.timeSinceHit + dt
                if s.timeSinceHit >= 5.0 and not s.noHitBuffApplied then
                    s.noHitBuffApplied = true
                    local entries = {}
                    if hasAdv(ally, "adv_217_instant_kill") then
                        entries[#entries + 1] = { key = AD.CRIT_RATE, flat = 25 }
                    end
                    if hasAdv(ally, "adv_218_thousand_faces") then
                        entries[#entries + 1] = { key = AD.ATK_SPEED, flat = 50 }
                        entries[#entries + 1] = { key = AD.DMG_BONUS, flat = 10 }
                    end
                    ally.attrs:addModifier("talent_no_hit", entries)
                    talentLog("[Talent] 5秒未受击: " .. ally.name .. " 获得增益")
                end
            end

            -- ======== Hero10 铁憨憨 帝国铁壁 CD递减 + 觉醒5低血护甲 ========
            if s.heroId == 10 then
                -- CD递减
                if s.bulwarkHealCd > 0 then s.bulwarkHealCd = s.bulwarkHealCd - dt end
                if s.bulwarkDmgCapCd > 0 then s.bulwarkDmgCapCd = s.bulwarkDmgCapCd - dt end
                -- 觉醒5: 低于30%HP时护甲+12
                if hasAwaken(ally, 5) and ally.attrs then
                    local hpRatio = (ally.hp or 0) / (ally.maxHp or 1)
                    if hpRatio < 0.30 and not s.bulwarkLowHpArmorApplied then
                        ally.attrs:addModifier("bulwark_low_hp_armor", {
                            { key = AD.PHYS_ARMOR, flat = 12 },
                        })
                        s.bulwarkLowHpArmorApplied = true
                    elseif hpRatio >= 0.30 and s.bulwarkLowHpArmorApplied then
                        ally.attrs:removeModifier("bulwark_low_hp_armor")
                        s.bulwarkLowHpArmorApplied = false
                    end
                end
            end

            -- ======== 星图节点126 杀戮盛宴 攻速buff倒计时========
            if s.slaughterTimer > 0 then
                s.slaughterTimer = s.slaughterTimer - dt
                if s.slaughterTimer <= 0 then
                    s.slaughterTimer = 0
                    if ally.attrs then
                        ally.attrs:removeModifier("starmap_slaughter")
                    end
                end
            end

            -- ======== 星图节点128 共鸣之歌: 全队伤害buff倒计时========
            if s.resonanceTimer > 0 then
                s.resonanceTimer = s.resonanceTimer - dt
                if s.resonanceTimer <= 0 then
                    s.resonanceTimer = 0
                    if ally.attrs then
                        ally.attrs:removeModifier("starmap_resonance")
                    end
                end
            end

            -- ======== Hero20 摘星星星人 常驻星门召唤物 ========
            if s.heroId == 20 then
                updateMelissaStarGate(dt, ally, s, true, enemies, ctx, allies)
            end

            -- ======== Hero16 万剑归宗 灵月飞剑周期触发 ========
            if s.heroId == 16 and ally.hp > 0 then
                local interval = getLuoxingFlyingSwordInterval(ally)
                if interval <= 0 then interval = 5.0 end
                s.flyingSwordWindowSec = interval
                s.flyingSwordTimer = (s.flyingSwordTimer or 0) + dt
                -- 2 倍速/卡顿补帧时限制单帧补发窗口，避免单帧堆叠过多飞剑投射物
                local maxFlyingSwordTicks = 1
                if dt >= interval then
                    maxFlyingSwordTicks = math.min(4, math.floor(dt / interval + 0.0001))
                end
                while s.flyingSwordTimer >= interval and maxFlyingSwordTicks > 0 do
                    maxFlyingSwordTicks = maxFlyingSwordTicks - 1
                    if ctx.dealTalentDamage or ctx.dealDamage then
                        local okFire, fired, consumeWindow = pcall(function()
                            return fireLuoxingFlyingSwords(ally, s, enemies, true, function(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
                                if ctx.dealTalentDamage then
                                    ctx.dealTalentDamage(ally, tgt, dmg, isTgtAlly, pfx, clr, projOpts)
                                else
                                    ctx.dealDamage(tgt, dmg, isTgtAlly, pfx, clr, ally)
                                end
                            end)
                        end)
                        if not okFire then
                            talentLog("[Talent] 万剑归宗 灵月飞剑 tick failed: " .. tostring(fired))
                            resetLuoxingFlyingSwordWindow(s, interval)
                            break
                        end
                        if fired or consumeWindow then
                            resetLuoxingFlyingSwordWindow(s, interval)
                        else
                            -- 有累计伤害但场上无敌人：保留待发，不轮空；窗口仍按 interval 滚动
                            s.flyingSwordTimer = s.flyingSwordTimer - interval
                            break
                        end
                    else
                        resetLuoxingFlyingSwordWindow(s, interval)
                        break
                    end
                end
            end

            -- ======== Hero22 小黑子 法术机关枪连射队列 ========
            if s.heroId == 22 and s.machineGunShotsLeft > 0 and ctx.performAttack then
                s.machineGunShotTimer = (s.machineGunShotTimer or 0) - dt
                if s.machineGunShotTimer <= 0 then
                    -- 标记为连射弹：不计入20次普攻，但走完整 performAttack → onAfterAttack（奥术飞弹等）
                    s.machineGunBurstShot = true
                    ctx.performAttack(ally, enemies, true)
                    s.machineGunShotsLeft = s.machineGunShotsLeft - 1
                    local shotInterval = 0.12
                    if hasAwaken(ally, 6) then shotInterval = shotInterval / 1.5 end
                    s.machineGunShotTimer = shotInterval
                    if s.machineGunShotsLeft <= 0 then
                        s.machineGunInBurst = false
                        if ally.attrs then
                            ally.attrs:removeModifier("sera_burst_pen")
                            ally.attrs:removeModifier("sera_burst_speed")
                        end
                        if hasAwaken(ally, 6) then
                            s.machineGunOverloadTimer = 5.0
                        end
                        talentLog("[Talent] 小黑子 法术机关枪：连射结束")
                    end
                end
            end

            -- ======== Hero22 小黑子 过载层数保留倒计时 ========
            if s.heroId == 22 and (s.machineGunOverloadTimer or 0) > 0 then
                s.machineGunOverloadTimer = s.machineGunOverloadTimer - dt
                if s.machineGunOverloadTimer <= 0 then
                    s.machineGunOverloadTimer = 0
                    s.machineGunOverloadStacks = 0
                    if ally.attrs then
                        ally.attrs:removeModifier("sera_overload")
                    end
                end
            end

            -- ======== 真布诗人觉醒7：无敌倒计时 + 护盾清零检测 ========
            if ally._elwynInvulnTimer and ally._elwynInvulnTimer > 0 then
                ally._elwynInvulnTimer = ally._elwynInvulnTimer - dt
                if ally._elwynInvulnTimer <= 0 then
                    ally._elwynInvulnTimer = nil
                end
            end
            if ally.attrs then
                local curTotalES = (ally.attrs.energyShield or 0) + (ally.attrs.tempEnergyShield or 0)
                if s.prevTotalES == nil then s.prevTotalES = curTotalES end
                if s.prevTotalES > 0 and curTotalES <= 0 then
                    local elwyn, elwynState = findLivingElwyn(allies)
                    if elwyn and elwynState then
                        tryElwynInvulnOnEsBreak(ally, elwyn, elwynState)
                    end
                end
                s.prevTotalES = curTotalES
            end

            ::continue_ally::
        end
    end

    -- ======== 己方摘星星星人死亡后仍存在的星门（觉醒6）========
    for _, ally in ipairs(allies) do
        if ally.hp <= 0 then
            local s = getState(ally)
            if s and s.heroId == 20 then
                updateMelissaStarGate(dt, ally, s, true, enemies, ctx, allies)
            end
        end
    end

    -- ======== 敌方摘星星星人常驻星门召唤物（竞技场/镜像敌人）========
    for _, enemy in ipairs(enemies) do
        local s = getState(enemy)
        if s and s.heroId == 20 and (enemy.hp > 0 or isMelissaStarGateAttackSourceActive(enemy, s)) then
            updateMelissaStarGate(dt, enemy, s, false, allies, ctx, enemies)
        end
    end

    -- ======== 敌方感电减益清理：SHOCKED 过期时移除awaken_shock_debuff_ ========
    for _, enemy in ipairs(enemies) do
        if enemy.attrs and not SEM.has(enemy, SEM.SHOCKED) then
            enemy.attrs:removeModifier("awaken_shock_debuff_" .. tostring(enemy))
        end
    end
    end

    return { update = update }
end

return M

