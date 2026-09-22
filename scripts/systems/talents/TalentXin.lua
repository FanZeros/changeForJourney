-- ============================================================================
-- Talent Xin helpers extracted from TalentManager（信光机兵 #7）
-- Bound via M.bind(deps)
-- ============================================================================

local M = {}

function M.bind(deps)
    local hasAwaken = deps.hasAwaken
    local talentLog = deps.talentLog
    local AD = deps.AD

local function onXinAfterAttack(attacker, s, target, isAlly, targetList, dealDmgFn, result)
    if not attacker.attrs then return end
    -- 觉醒2: 连击命中20%概率永久-1魔甲（按目标独立计数)
    if hasAwaken(attacker, 2) and result and result.isCombo and target.hp > 0 and target.attrs then
        if math.random() < 0.20 then
            if not s.awakFlashMagArmorDebuffs then s.awakFlashMagArmorDebuffs = {} end
            local tKey = tostring(target)
            local curDebuff = (s.awakFlashMagArmorDebuffs[tKey] or 0) + 7
            s.awakFlashMagArmorDebuffs[tKey] = curDebuff
            target.attrs:removeModifier("awaken_flash_magarmor_" .. tKey)
            target.attrs:addModifier("awaken_flash_magarmor_" .. tKey, {
                { key = AD.MAG_ARMOR, flat = -curDebuff },
            })
            talentLog("[Talent] 信光机兵 觉醒2: " .. target.name .. " 能量护盾永久-" .. curDebuff)
        end
    end
    -- 觉醒6: 连击无法被闪避（每次攻击后移除临时命中加成）
    if hasAwaken(attacker, 6) then
        attacker.attrs:removeModifier("awaken_flash_hit")
    end

    if s.flashReady then
        attacker.attrs:removeModifier("talent_flash")
        attacker.attrs:removeModifier("awaken_flash7_boost")
        if dealDmgFn and targetList and result and (result.totalDamage or 0) > 0 then
            local beamDmg = math.floor((result.totalDamage or 0) * 0.70 + 0.5)
            if beamDmg > 0 then
                for _, u in ipairs(targetList) do
                    if u ~= target and (u.hp or 0) > 0 then
                        dealDmgFn(u, beamDmg, not isAlly, "必杀 ", { 120, 220, 255 }, {
                            instantDamage = true,
                            statCategory = result.category or "magical",
                        })
                    end
                end
                talentLog("[Talent] 信光机兵 必杀光线 贯穿")
            end
        end
        attacker._beamKill = true
        s.flashReady = false
        s.atkCount = 0
    else
        s.atkCount = s.atkCount + 1
        local flashInterval = 4
        if hasAwaken(attacker, 3) then flashInterval = 3 end
        if s.atkCount % flashInterval == 0 then
            s.flashReady = true
            if hasAwaken(attacker, 7) then
                attacker.attrs:removeModifier("awaken_flash_exclusive")
            end
            talentLog("[Talent] 信光机兵 必杀蓄力：下次攻击连击概率200% (每" .. flashInterval .. "次)")
        end
    end

    if hasAwaken(attacker, 7) then
        if not s.flashReady then
            if not s.awakFlashExclActive then
                s.awakFlashExclActive = true
                attacker.attrs:addModifier("awaken_flash_exclusive", {
                    { key = AD.COMBO_RATE, flat = -999 },
                })
            end
        else
            if s.awakFlashExclActive then
                s.awakFlashExclActive = false
                attacker.attrs:removeModifier("awaken_flash_exclusive")
            end
            attacker.attrs:removeModifier("awaken_flash7_boost")
            attacker.attrs:addModifier("awaken_flash7_boost", {
                { key = AD.COMBO_RATE, flat = 100 },
                { key = AD.COMBO_DMG_UP, flat = 30 },
            })
        end
    end
end

    return { onXinAfterAttack = onXinAfterAttack }
end

return M
