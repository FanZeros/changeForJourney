-- ============================================================================
-- TalentManager - 英雄天赋运行时管理器
-- 管理所有英雄专属天赋+ 转职天赋的战斗逻辑（非纯属性加成部分）
-- 纯属性加成天赋#4接化发掌门/#14内鬼)已在 HeroConfig._applyHeroTalent 中实现
-- 纯装备类天赋(207武器精通220双刃精通在装备系统中处理，此处不涉及
-- 模块级单例，参考ThreatManager 模式
-- ============================================================================

local AD  = require("systems.AttributeDef")
local CF  = require("systems.CombatFormula")
local SEM = require("systems.StatusEffectManager")
local RCH = require("systems.RelicConditionHandler")
local Diag = require("systems.BattleDiag")
local ETS = require("systems.ExtraTalentSystem")
local TalentAyane = require("systems.talents.TalentAyane")
local TalentLuoxing = require("systems.talents.TalentLuoxing")
local TalentMelissa = require("systems.talents.TalentMelissa")
local TalentAlex = require("systems.talents.TalentAlex")
local TalentElwyn = require("systems.talents.TalentElwyn")
local TalentSera = require("systems.talents.TalentSera")
local TalentSuhua = require("systems.talents.TalentSuhua")
local TalentUpdate = require("systems.talents.TalentUpdate")
local TalentRosa = require("systems.talents.TalentRosa")
local TalentXin = require("systems.talents.TalentXin")
local TalentAfterAttack = require("systems.talents.TalentAfterAttack")

local MAS
local function getMAS()
    if not MAS then MAS = require("systems.MapAffixSystem") end
    return MAS
end

local function talentLog(msg)
    if Diag.logEnabled then
        print(msg)
    end
end

local TAL = {}
-- [多实例] 战斗双方列表引用（随战斗 mount 切换）; state/unitStates 为 unit-keyed 全局共享
local function newBattleRefs()
    return { bAllies = {}, bEnemies = {} }
end
local TAL_DEFAULT = newBattleRefs()
local TAL_BCS = TAL_DEFAULT
function TAL.newBattleRefs() return newBattleRefs() end
function TAL.mount(s) TAL_BCS = s or TAL_DEFAULT end
function TAL.mountedState() return TAL_BCS end


-- ======================== 每单位状态========================

local state = {}

-- 模块级引用（onBattleStart 时缓存）

-- ======================== 辅助 ========================

local function getState(unit)
    return state[unit]
end

local function ensureState(unit)
    if not state[unit] then
        state[unit] = {
            heroId         = tonumber(unit.heroId) or unit.heroId or 0,
            atkCount       = 0,
            conquerStacks  = 0,
            hopeBuff       = false,
            flashReady     = false,
            preciseBuff    = false,
            reviveUsed     = {},
            isCountering   = false,
            -- ===== 转职天赋状态=====
            advTimer       = 0,       -- 10秒周期计时器 (101/102/105/109 共用)
            -- 101 圣光环
            holyTriggered50 = false,  -- 201进阶: 首次<50%触发
            holyTriggered20 = false,  -- 201进阶: 首次<20%触发
            -- 102 龙之血
            dragonRegenActive = false,
            dragonRegenFrac = 0,
            -- 104 决斗者
            duelTarget     = nil,     -- 锁定的目标单位引用
            duelCount      = 0,       -- 连续攻击同一目标的次数
            -- 108 阵前提速
            hasteStacks    = 0,       -- 提速层数
            -- 109 隐匿
            shadowActive   = false,   -- 暗影状态
            shadowTimer    = 0,       -- 暗影剩余时间
            -- 110 影袭
            shadowStrikeBuff = false, -- 下次攻击+30%
            -- 107 巡游射击
            patrolQueue    = {},      -- { { target, timer }, ... } 延迟反击队列
            -- 208 幻影剑斩
            phantomTarget  = nil,     -- 上次攻击的目标
            phantomStacks  = 0,       -- 连击层数
            -- 202 传颂祝福
            praiseTotalLost = 0,      -- 战斗中累计损失HP
            praiseStacks   = 0,       -- 当前祝福层数 (每10%一阶, max14)
            -- 203 十字盾守
            crossShieldStacks = 0,    -- 护甲叠层 (max50)
            -- 206 嗜血狂怒
            bloodthirstApplied = false,
            -- 210 蚀骨诅咒
            corrosionCds   = {},      -- [target] = cooldownTimer
            -- 213 风之气息
            windStacks     = 0,
            windTimer      = 0,
            -- 214 林间之眼
            critBoostStacks = 0,
            critBoostTimer  = 0,
            -- 217/218 瞬杀/千面
            timeSinceHit   = 0,
            noHitBuffApplied = false,
            -- 111/221/222 激励
            inspiredAtkBonus = false,   -- 被激励者下次攻击伤害加成
            inspiredHealBack = false,   -- 222嗜血: 攻击后回血
            -- ===== 觉醒状态=====
            -- Hero4 接化发掌门: 觉醒7 格挡吸收伤害
            blockAbsorbedDmg = 0,
            -- Hero5 叠甲怪: 觉醒7 征服满层增效标记
            conquerMaxBoostApplied = false,
            -- Hero8 愤怒的小雀: 觉醒6 首次攻击标记目标必暴标记
            markFirstHitCrit = {},     -- [target] = true
            -- Hero10 铁憨憨 帝国铁壁
            bulwarkApplied = false,       -- 基础天赋是否已应用
            bulwarkHealCd = 0,            -- 觉醒2 吸收回血CD
            bulwarkLowHpArmorApplied = false, -- 觉醒5 低血护甲是否激活
            bulwarkDmgCapCd = 0,          -- 觉醒7 防秒杀CD
            -- Hero12 雪皇: 觉醒5 首次冰冻标记
            firstFreezeUsed = {},      -- [target] = true
            -- Hero12 雪皇: 冰冻内置CD（防无限冰冻），[target] = 剩余不可再次被冰冻的秒数
            freezeCD = {},
            -- Hero12 雪皇: 觉醒6 首次<50%触发
            frozenAllTriggered = false,
            -- Hero12 雪皇: 觉醒7 冰冻叠层魔攻
            freezeAtkStacks = 0,
            -- Hero8 愤怒的小雀: 仇册（打过自己的人）
            feudAttackers = {},
            -- Hero14 内鬼: 觉醒4 首次攻击目标必暴
            firstHitTargets = {},      -- [target] = true
            -- Hero14 内鬼: 觉醒6 击杀暴伤叠加
            killCritDmgStacks = 0,
            -- Hero15 复活吧爱人: 觉醒2 被复活者治疗加成
            reviveHealBoostTargets = {},  -- [target] = remainingTime
            -- Hero15 复活吧爱人: 觉醒7 自身复活已用
            selfReviveUsed = false,
            -- Hero16 万剑归宗: 灵月飞剑
            flyingSwordTimer = 0,
            flyingSwordDamage = 0,
            flyingSwordCarryover = 0,
            flyingSwordWindowSec = 5.0,
            -- Hero20 摘星星星人: 星之守护
            starGateAssistCd = 0,
            starGateTimer = 0,
            starGateSummoned = false,
            starGateCount = 0,
            starGateResonanceDamage = 0,
            starGateResonanceDmgBonus = 0,
            starGateResonancePen = 0,
            starGateResonanceUnits = 0,
            starGateBaseDamage = 0,
            -- 折中加强：攻速/连击转化为星门频率，连击积累星痕
            starGateStarMarks = 0,
            starGateLastAttackComboCount = 0,
            starGateSpeedFactor = 0,
            starGateInterval = 2.6,
            -- Hero21 闪电卖鸡: 氮气
            silverLightProgressBoost = false,
            silverFlashChecked = false,
            nitroStacks = 0,
            -- Hero22 小黑子: 法术机关枪
            machineGunNormalCount = 0,   -- 普攻与连击计入，连射弹不计入
            machineGunBurstShot = false,   -- 本帧 performAttack 是否为连射弹
            lastAttackWasBurst = false,  -- 上一击是否为连射（供 onAfterAttack 判定）
            machineGunShotsLeft = 0,
            machineGunShotTimer = 0,
            machineGunInBurst = false,
            machineGunOverloadStacks = 0,
            machineGunOverloadTimer = 0,
            -- Hero23 真布诗人: 能量祝福 / 觉醒7
            prevTotalES = nil,
            elwynInvulnProcChance = 1.0,
            awakElwynTeamBuffApplied = false,
            -- ===== 星图 RUNTIME_ONLY 节点状态=====
            -- Node125 不死鸟之翼 每场每人1次
            phoenixUsed = false,
            -- Node126 杀戮盛宴 攻速buff剩余时间
            slaughterTimer = 0,
            -- Node128 共鸣之歌: 全队buff剩余时间（由触发者维护）
            resonanceTimer = 0,
        }
    end
    return state[unit]
end

--- 检查单位是否拥有指定转职天赋
---@param unit table
---@param talentId string
---@return boolean
local function hasAdv(unit, talentId)
    if not unit.advTalentIds then return false end
    for _, tid in ipairs(unit.advTalentIds) do
        if tid == talentId then return true end
    end
    return false
end

--- 检查单位是否已激活指定觉醒节点（旧 1–7 会映射到新 1/2/3）
---@param unit table
---@param nodeIndex number 1~7
---@return boolean
local function hasAwaken(unit, nodeIndex)
    if not unit then return false end
    return require("config.AwakeningConfig").hasNode(unit.awakeningNodes, nodeIndex)
end

--- 检查单位所属队伍是否已点亮指定天赋星图节点
---@param unit table
---@param nodeId number 星图节点ID
---@return boolean
local function hasStarNode(unit, nodeId)
    if unit.litNodeSet == nil then return false end
    if unit.litNodeSet[nodeId] then return true end
    return unit.litNodeSet[tostring(nodeId)] == true
end

--- 队伍是否已点亮指定星图节点（任一友军 litNodeSet 或账号默认星图）
---@param nodeId number
---@return boolean
local function teamHasStarNode(nodeId)
    if TAL_BCS.bAllies then
        for _, ally in ipairs(TAL_BCS.bAllies) do
            if hasStarNode(ally, nodeId) then return true end
        end
    end
    local HC = require("config.HeroConfig")
    local lit = HC._getSavedLitNodes()
    if lit then
        for _, id in ipairs(lit) do
            if (tonumber(id) or id) == nodeId then return true end
        end
    end
    return false
end

--- 过量治疗转能量护盾（天赋124，默认转化率30%）
---@param target table
---@param overflow number 溢出治疗量
---@param convertRate number|nil
---@return number 实际获得的护盾
local function applyOverhealToEnergyShield(target, overflow, convertRate)
    if not target or not target.attrs or overflow <= 0 then return 0 end
    convertRate = convertRate or 0.30
    overflow = math.floor(overflow + 0.0001)
    local maxES = math.floor((target.attrs.final[AD.ENERGY_SHIELD] or 0) + 0.0001)
    if maxES <= 0 then return 0 end
    local esGain = math.floor(overflow * convertRate + 0.5)
    if esGain <= 0 then return 0 end
    local curES = math.floor(target.attrs.energyShield or 0)
    local newES = math.min(maxES, curES + esGain)
    local actualGain = newES - curES
    if actualGain > 0 then
        target.attrs.energyShield = newES
    end
    return actualGain
end

--- 检查单位在团队仇恨中是否为最高仇恨
local function isHighestThreat(unit, allyList, enemyList)
    local TM = require("systems.ThreatManager")
    local myThreat = TM.getThreat(unit)
    for _, ally in ipairs(allyList) do
        if ally ~= unit and ally.hp > 0 then
            if TM.getThreat(ally) > myThreat then return false end
        end
    end
    return true
end

--- 获取存活敌人列表
local function getAliveEnemies(list)
    local alive = {}
    for _, u in ipairs(list) do
        if u.hp > 0 then alive[#alive + 1] = u end
    end
    return alive
end

local function calcDragonBloodThreatLead(unit, opposingUnits)
    if not unit or not unit.attrs then return 0 end
    local totalDmg = 0
    local count = 0
    for _, target in ipairs(opposingUnits or {}) do
        if target and target.hp and target.hp > 0 and target.attrs then
            local ok, result = pcall(CF.calcAttack, unit.attrs, target.attrs)
            if ok and result and (result.totalDamage or 0) > 0 then
                totalDmg = totalDmg + result.totalDamage
                count = count + 1
            end
        end
    end
    if count <= 0 then return 0 end
    return math.floor((totalDmg / count) * 50 + 0.5)
end

--- 计算天赋固定伤害（含伤害加成、暴击、类型倍率、护甲）
---@param attacker table
---@param target table
---@param baseDmg number 未加成的基础伤害
---@param opts table|nil { critRate=, critDmg=, atkType=, forceCrit=, ignoreArmor=, extraDmgBonusPct=, extraPen= }
---@return number damage
---@return boolean isCrit
local function calcTalentFixedDamage(attacker, target, baseDmg, opts)
    opts = opts or {}
    if not attacker.attrs or not target.attrs or baseDmg <= 0 then return 0, false end

    local atkType = opts.atkType or attacker.atkType or AD.ATK_SLASH
    local category = AD.getAtkCategory(atkType)

    local dmgBonusPct = attacker.attrs:get(AD.DMG_BONUS)
    local chaosMult = attacker.attrs.artifactChaosDamageMult
    if chaosMult then
        dmgBonusPct = dmgBonusPct + attacker.attrs:get(AD.PHYS_DMG_BONUS) + attacker.attrs:get(AD.MAG_DMG_BONUS)
    elseif category == "physical" then
        dmgBonusPct = dmgBonusPct + attacker.attrs:get(AD.PHYS_DMG_BONUS)
    else
        dmgBonusPct = dmgBonusPct + attacker.attrs:get(AD.MAG_DMG_BONUS)
    end

    if opts.extraDmgBonusPct then
        dmgBonusPct = dmgBonusPct + opts.extraDmgBonusPct
    end

    local critRate = opts.critRate
    if critRate == nil then
        critRate = attacker.attrs:get(AD.CRIT_RATE)
        if category == "physical" then
            critRate = critRate + attacker.attrs:get(AD.PHYS_CRIT_RATE)
        else
            critRate = critRate + attacker.attrs:get(AD.MAG_CRIT_RATE)
        end
    end
    local critDmg = opts.critDmg
    if critDmg == nil then
        critDmg = attacker.attrs:get(AD.CRIT_DMG)
        if category == "physical" then
            critDmg = critDmg + attacker.attrs:get(AD.PHYS_CRIT_DMG)
        else
            critDmg = critDmg + attacker.attrs:get(AD.MAG_CRIT_DMG)
        end
    end

    if attacker.attrs.artifactCritRateMult then
        critRate = critRate * attacker.attrs.artifactCritRateMult
    end
    if attacker.attrs.artifactCritDmgMult then
        critDmg = critDmg * attacker.attrs.artifactCritDmgMult
    end

    local armorType = target.armorType or AD.ARMOR_LEATHER
    local resistance = 0
    local penBonus = 1.0
    if not opts.ignoreArmor then
        local rawArmor = target.attrs:get(AD.ARMOR) or 0
        local corrodePct = getMAS().getCorrodeArmorPct(target)
        if corrodePct > 0 then
            rawArmor = rawArmor * (1 - corrodePct)
        end
        local rawPen
        if chaosMult then
            rawPen = attacker.attrs:get(AD.PHYS_PEN) + attacker.attrs:get(AD.MAG_PEN)
        else
            rawPen = category == "physical"
                and attacker.attrs:get(AD.PHYS_PEN)
                or attacker.attrs:get(AD.MAG_PEN)
        end
        if opts.extraPen then
            rawPen = rawPen + opts.extraPen
        end
        if attacker.attrs.artifactIgnoreArmor then
            rawArmor = 0
        end
        local effectiveArmor = math.max(0, rawArmor - rawPen)
        local excessPen = math.max(0, rawPen - rawArmor)
        resistance = CF.armorToResistance(effectiveArmor)
        penBonus = excessPen > 0 and (1 + (0.01 * excessPen) / (0.01 * excessPen + 1)) or 1.0
    end
    local typeMult = AD.getTypeMult(atkType, armorType)

    local dmg = baseDmg * (1 + dmgBonusPct / 100)
    local isCrit = false
    if opts.forceCrit then
        isCrit = true
        dmg = dmg * (critDmg / 100)
    else
        local rolledCrit, critMult = CF.rollCrit(critRate, critDmg)
        if rolledCrit then
            isCrit = true
            dmg = dmg * critMult
        end
    end

    if chaosMult then
        dmg = dmg * chaosMult * (1 - resistance) * penBonus
    else
        dmg = dmg * typeMult * (1 - resistance) * penBonus
    end
    if attacker.attrs.artifactExtraDamageMult then
        dmg = dmg * attacker.attrs.artifactExtraDamageMult
    end
    dmg = CF.applyFinalDamageBonus(attacker.attrs, dmg)
    return math.max(1, math.floor(dmg + 0.5)), isCrit
end

-- 英雄专属辅助（从本文件抽出，bind 后保持原 local 名）
local _ayane = TalentAyane.bind({
    hasAwaken = hasAwaken,
    getState = getState,
    ensureState = ensureState,
    getAliveEnemies = getAliveEnemies,
    talentLog = talentLog,
})
local getAyaneMarkMult = _ayane.getAyaneMarkMult
local clearAyaneMarks = _ayane.clearAyaneMarks
local applyAyaneMark = _ayane.applyAyaneMark
local applyAyaneBattleStartMark = _ayane.applyAyaneBattleStartMark
local getPrimaryAyane = _ayane.getPrimaryAyane
local hasAnyAyaneMark = _ayane.hasAnyAyaneMark

local _luoxing = TalentLuoxing.bind({
    hasAwaken = hasAwaken,
    getState = getState,
    ensureState = ensureState,
    getAliveEnemies = getAliveEnemies,
    talentLog = talentLog,
    calcTalentFixedDamage = calcTalentFixedDamage,
    AD = AD,
    SEM = SEM,
    CF = CF,
})
local isFlyingSwordTalentDmg = _luoxing.isFlyingSwordTalentDmg
local getLuoxingFlyingSwordInterval = _luoxing.getLuoxingFlyingSwordInterval
local resetLuoxingFlyingSwordWindow = _luoxing.resetLuoxingFlyingSwordWindow
local getLuoxingAccumAmount = _luoxing.getLuoxingAccumAmount
local addLuoxingWindowDamage = _luoxing.addLuoxingWindowDamage
local wrapDealDmgForLuoxing = _luoxing.wrapDealDmgForLuoxing
local getYouyeAttackCritStats = _luoxing.getYouyeAttackCritStats
local tryYouyeSuperCrit = _luoxing.tryYouyeSuperCrit
local fireLuoxingFlyingSwords = _luoxing.fireLuoxingFlyingSwords

local _melissa = TalentMelissa.bind({
    hasAwaken = hasAwaken,
    getState = getState,
    ensureState = ensureState,
    getAliveEnemies = getAliveEnemies,
    talentLog = talentLog,
    calcTalentFixedDamage = calcTalentFixedDamage,
    AD = AD,
    SEM = SEM,
    CF = CF,
})
local getMelissaStarGateInterval = _melissa.getMelissaStarGateInterval
local getMelissaStarGateDmgMult = _melissa.getMelissaStarGateDmgMult
local getMelissaStarGateCount = _melissa.getMelissaStarGateCount
local canMelissaStarGatePersistAfterDeath = _melissa.canMelissaStarGatePersistAfterDeath
local syncMelissaStarGateVisualState = _melissa.syncMelissaStarGateVisualState
local isMelissaStarGateAttackSourceActive = _melissa.isMelissaStarGateAttackSourceActive
local getMelissaStarGateEffectiveInterval = _melissa.getMelissaStarGateEffectiveInterval
local addMelissaStarMarks = _melissa.addMelissaStarMarks
local getMelissaStarMarkDamageScale = _melissa.getMelissaStarMarkDamageScale
local getMelissaStarGateResonanceScale = _melissa.getMelissaStarGateResonanceScale
local rollMelissaStarGateAtkType = _melissa.rollMelissaStarGateAtkType
local getMelissaStarGateStatusMult = _melissa.getMelissaStarGateStatusMult
local calcMelissaUnitResonance = _melissa.calcMelissaUnitResonance
local getMelissaStarGateResonanceLimit = _melissa.getMelissaStarGateResonanceLimit
local calcMelissaTeamResonance = _melissa.calcMelissaTeamResonance
local summonMelissaStarGate = _melissa.summonMelissaStarGate
local calcMelissaStarGateDamage = _melissa.calcMelissaStarGateDamage
local fireMelissaStarGate = _melissa.fireMelissaStarGate
local triggerMelissaStarGates = _melissa.triggerMelissaStarGates
local updateMelissaStarGate = _melissa.updateMelissaStarGate

local _alex = TalentAlex.bind({
    hasAwaken = hasAwaken,
    talentLog = talentLog,
    AD = AD,
    SEM = SEM,
    getBattleRefs = function() return TAL_BCS end,
})
local tryAlexSilverFlash = _alex.tryAlexSilverFlash

local _elwyn = TalentElwyn.bind({
    hasAwaken = hasAwaken,
    getState = getState,
    talentLog = talentLog,
    AD = AD,
})
local applyElwynEnergyBlessing = _elwyn.applyElwynEnergyBlessing
local findLivingElwyn = _elwyn.findLivingElwyn
local tryElwynInvulnOnEsBreak = _elwyn.tryElwynInvulnOnEsBreak

local _sera = TalentSera.bind({
    hasAwaken = hasAwaken,
    talentLog = talentLog,
    AD = AD,
})
local tickSeraMachineGunCount = _sera.tickSeraMachineGunCount

local _suhua = TalentSuhua.bind({
    hasAwaken = hasAwaken,
    talentLog = talentLog,
    AD = AD,
    CF = CF,
})
local runSuhuaNightSlash = _suhua.runSuhuaNightSlash

local _rosa = TalentRosa.bind({
    hasAwaken = hasAwaken,
    AD = AD,
})
local tryRosaBounce = _rosa.tryRosaBounce

local _xin = TalentXin.bind({
    hasAwaken = hasAwaken,
    talentLog = talentLog,
    AD = AD,
})
local onXinAfterAttack = _xin.onXinAfterAttack

local _after
local function bindTalentAfterAttack()
    _after = TalentAfterAttack.bind({
        getState = getState,
        ensureState = ensureState,
        hasAdv = hasAdv,
        hasAwaken = hasAwaken,
        hasStarNode = hasStarNode,
        teamHasStarNode = teamHasStarNode,
        talentLog = talentLog,
        getAliveEnemies = getAliveEnemies,
        applyOverhealToEnergyShield = applyOverhealToEnergyShield,
        calcTalentFixedDamage = calcTalentFixedDamage,
        wrapDealDmgForLuoxing = wrapDealDmgForLuoxing,
        addMelissaStarMarks = addMelissaStarMarks,
        addLuoxingWindowDamage = addLuoxingWindowDamage,
        getLuoxingAccumAmount = getLuoxingAccumAmount,
        applyAyaneMark = applyAyaneMark,
        clearAyaneMarks = clearAyaneMarks,
        applyElwynEnergyBlessing = applyElwynEnergyBlessing,
        runSuhuaNightSlash = runSuhuaNightSlash,
        tryAlexSilverFlash = tryAlexSilverFlash,
        tryYouyeSuperCrit = tryYouyeSuperCrit,
        tryRosaBounce = tryRosaBounce,
        onXinAfterAttack = onXinAfterAttack,
        getTAL_BCS = function() return TAL_BCS end,
    })
end
bindTalentAfterAttack()



local _talentUpdate
local function bindTalentUpdate()
    _talentUpdate = TalentUpdate.bind({
        getState = getState,
        hasAdv = hasAdv,
        hasAwaken = hasAwaken,
        talentLog = talentLog,
        calcDragonBloodThreatLead = calcDragonBloodThreatLead,
        getTAL_BCS = function() return TAL_BCS end,
        fireLuoxingFlyingSwords = fireLuoxingFlyingSwords,
        getLuoxingFlyingSwordInterval = getLuoxingFlyingSwordInterval,
        resetLuoxingFlyingSwordWindow = resetLuoxingFlyingSwordWindow,
        isMelissaStarGateAttackSourceActive = isMelissaStarGateAttackSourceActive,
        updateMelissaStarGate = updateMelissaStarGate,
        getAliveEnemies = getAliveEnemies,
        isHighestThreat = isHighestThreat,
        findLivingElwyn = findLivingElwyn,
        tryElwynInvulnOnEsBreak = tryElwynInvulnOnEsBreak,
    })
end
bindTalentUpdate()




-- ======================== 核心 API ========================

--- 重置所有天赋状态（关卡切换时调用）
function TAL.reset()
    ETS.flush()
    state = {}
    TAL_BCS.bAllies  = {}
    TAL_BCS.bEnemies = {}
end

--- 初始化单位天赋状态（单位加入战场时调用）
---@param unit table
function TAL.initUnit(unit)
    local s = ensureState(unit)
    if unit and unit.heroId == 20 then
        syncMelissaStarGateVisualState(unit, s)
    end
    print("[TAL.initUnit] heroId=" .. tostring(unit.heroId) .. " name=" .. tostring(unit.name))
end

--- 战斗开始钩子
---@param allies table 己方单位列表
---@param enemies table 敌方单位列表
function TAL.onBattleStart(allies, enemies)
    TAL_BCS.bAllies  = allies
    TAL_BCS.bEnemies = enemies

    --- 为一组单位应用战斗开始天赋（转职天赋 + 英雄专属）
    ---@param units table[] 要处理的单位列表
    ---@param opposingUnits table[] 对方单位列表（供标记类技能选目标）
    local function applyBattleStartTalents(units, opposingUnits)
        for _, unit in ipairs(units) do
            local s = ensureState(unit)

            -- #10 铁憨憨 帝国铁壁：战斗开始时施加被动属性
            if unit.heroId == 10 and unit.hp > 0 and unit.attrs then
                -- 生命加成: 基础+20%, 觉醒1→+25%, 觉醒6→+35%
                local hpBonus = 20
                if hasAwaken(unit, 6) then hpBonus = 35
                elseif hasAwaken(unit, 1) then hpBonus = 25 end
                -- 仇恨倍率: 基础+0.5(1.5倍), 觉醒3→+1(2倍)
                -- AD.THREAT 同时作为 selectTarget 静态权重(×10) 和 onDamageDone/onHealingDone 的仇恨生成倍率
                local threatBonus = 0.5
                if hasAwaken(unit, 3) then threatBonus = 1 end
                -- 觉醒3: 护甲+8
                local armorBonus = hasAwaken(unit, 3) and 8 or 0

                unit.attrs:addModifier("bulwark_passive", {
                    { key = AD.HP_BONUS, flat = hpBonus },
                    { key = AD.THREAT, flat = threatBonus },
                    { key = AD.PHYS_ARMOR, flat = armorBonus },
                })
                -- addModifier 会自动 recalculate，HP_BONUS 在底层已处理 MAX_HP 缩放
                unit.maxHp = unit.attrs.final[AD.MAX_HP]
                -- 满血开局：将当前HP设为新的MAX_HP
                unit.attrs.final[AD.HP] = unit.maxHp
                unit.hp = unit.maxHp

                local ss = getState(unit)
                if ss then ss.bulwarkApplied = true end
                talentLog("[Talent] 铁憨憨 帝国铁壁: HP+" .. hpBonus .. "% 仇恨+" .. threatBonus
                    .. " 护甲+" .. armorBonus)
            end

            -- #23 真布诗人：觉醒3/4 全队能量护盾加成
            if unit.heroId == 23 and unit.hp > 0 and unit.attrs and not s.awakElwynTeamBuffApplied then
                s.awakElwynTeamBuffApplied = true
                for _, ally in ipairs(units) do
                    if ally.hp > 0 and ally.attrs then
                        local entries = {}
                        if hasAwaken(unit, 3) then
                            entries[#entries + 1] = { key = AD.ES_BONUS, flat = 10 }
                        end
                        if hasAwaken(unit, 4) then
                            entries[#entries + 1] = { key = AD.ES_DMG_REDUCE, flat = 10 }
                        end
                        if #entries > 0 then
                            ally.attrs:addModifier("awaken_elwyn_team_" .. tostring(unit), entries)
                        end
                    end
                end
                if hasAwaken(unit, 3) or hasAwaken(unit, 4) then
                    talentLog("[Talent] 真布诗人 觉醒：全队能量护盾加成已施加")
                end
            end

            -- #16 万剑归宗：飞剑累计窗口与触发间隔同步
            if unit.heroId == 16 and unit.hp > 0 then
                local interval = getLuoxingFlyingSwordInterval(unit)
                resetLuoxingFlyingSwordWindow(s, interval)
                s.flyingSwordCarryover = 0
            end

            -- #20 摘星星星人：战斗开始时召唤永久存在的星门
            if unit.heroId == 20 and unit.hp > 0 then
                summonMelissaStarGate(unit, s)
            end

            if unit._etsPreciseStart and unit._etsPreciseStart > 0 then
                s.preciseChain = true
                unit._etsPreciseStart = unit._etsPreciseStart - 1
            end
            if unit._etsBeamStart and unit._etsBeamStart > 0 then
                s.flashReady = true
                unit._etsBeamStart = unit._etsBeamStart - 1
            end
            if unit._etsGatlingStart and unit._etsGatlingStart > 0 then
                s.machineGunShotsLeft = unit._etsGatlingStart
                s.machineGunShotTimer = 0.05
                s.machineGunInBurst = true
                unit._etsGatlingStart = nil
            end

            -- #14 内鬼 觉醒5: 战斗开始获得10次免疫（共用 RCH.immunityCount）
            if unit.heroId == 14 and unit.hp > 0 and hasAwaken(unit, 5) then
                RCH.addImmunityCharges(unit, 10)
                talentLog("[Talent] 内鬼 觉醒5: 战斗开始+10免疫 (剩余" .. RCH.getImmunityCount(unit) .. "次)")
            end

            -- #8 愤怒的小雀 弹弓怒鸟之眼：在 applyBattleStartTalents 末尾统一施加（多愤怒的小雀不叠标记）

            -- === 转职天赋: 战斗开始===

            -- 102 龙之血 战斗开始时嘲讽：按模拟平A伤害×50领先仇恨，并强制嘲讽3秒，之后每10秒再次触发
            if hasAdv(unit, "adv_102_dragon_blood") then
                local TM = require("systems.ThreatManager")
                local lead = calcDragonBloodThreatLead(unit, opposingUnits)
                TM.tauntToLead(unit, units, lead)
                TM.forceTarget(unit, 3.0)
                talentLog("[Talent] 龙之血: 开局嘲讽领先+" .. tostring(lead) .. " 强制3秒")
            end

            -- 108 阵前提速 获得10%鹰眼215=15%
            if hasAdv(unit, "adv_108_battle_haste") then
                local stacks = 10
                if hasAdv(unit, "adv_215_eagle_eye") then
                    stacks = 15
                end
                s.hasteStacks = stacks
                unit.attrs:addModifier("talent_haste", {
                    { key = AD.ATK_SPEED, flat = stacks * 8 },
                })
                -- 215 鹰眼: 每层额外+6物穿
                if hasAdv(unit, "adv_215_eagle_eye") then
                    unit.attrs:addModifier("talent_eagle_pen", {
                        { key = AD.PHYS_PEN, flat = stacks * 6 },
                    })
                end
                talentLog("[Talent] 阵前提速×" .. stacks .. " (攻速" .. (stacks * 8) .. "%)")
            end

            -- 104 决斗者 攻击速度+15%, 对锁定目标伤害加成5%
            if hasAdv(unit, "adv_104_duelist") then
                unit.attrs:addModifier("talent_duel_spd", {
                    { key = AD.ATK_SPEED, flat = 15 },
                })
                unit.attrs:addModifier("talent_duel_dmg", {
                    { key = AD.DMG_BONUS, flat = 5 },
                })
                talentLog("[Talent] 决斗者 攻速15%, 伤害+5%")
            end

            -- 206 嗜血狂怒 物理攻击加成+35%
            if hasAdv(unit, "adv_206_bloodthirst") and not s.bloodthirstApplied then
                unit.attrs:addModifier("talent_bloodthirst", {
                    { key = AD.PHYS_ATK_BONUS, flat = 35 },
                })
                s.bloodthirstApplied = true
                talentLog("[Talent] 嗜血狂怒 物攻加成+35%")
            end

            -- 216 重火力 攻速锁100%, 多余攻速→物理伤害加成(1:2)
            if hasAdv(unit, "adv_216_heavy_fire") then
                local curAtkSpeed = unit.attrs:get(AD.ATK_SPEED) or 0
                local excess = math.max(0, curAtkSpeed - 100)
                -- 移除所有攻速加成，固定到100%
                unit.attrs:addModifier("talent_heavy_fire", {
                    { key = AD.ATK_SPEED, flat = 100 - curAtkSpeed }, -- 将攻速调整到100
                    { key = AD.PHYS_DMG_BONUS, flat = excess * 2 },
                })
                talentLog("[Talent] 重火力 攻速→100%, 物伤加成+" .. (excess * 2) .. "%")
            end

            -- 219 致命之刃: 被动暴击伤害+25%
            if hasAdv(unit, "adv_219_lethal_blade") then
                unit.attrs:addModifier("talent_lethal_crit", {
                    { key = AD.CRIT_DMG, flat = 25 },
                })
                talentLog("[Talent] 致命之刃: 暴击伤害+25%")
            end
        end
        applyAyaneBattleStartMark(units, opposingUnits)
    end

    -- 双方均应用战斗开始天赋
    applyBattleStartTalents(allies, enemies)
    applyBattleStartTalents(enemies, allies)
    ETS.onBattleStart(allies, enemies)
end

--- 攻击前钩子（performAttack开头，目标选择后调用）
---@param attacker table 攻击方单位
function TAL.onBeforeAttack(attacker)
    local s = getState(attacker)
    if not s then
        print("[TAL.onBeforeAttack] WARNING: getState nil! heroId=" .. tostring(attacker.heroId) .. " name=" .. tostring(attacker.name))
        return
    end
    local heroId = s.heroId

    -- === 原有英雄天赋 ===

    -- #1 大狗嚼 衔骨狂：HP<70%时攻速+20%，普攻额外撕咬
    if heroId == 1 and attacker.attrs then
        local hpPct = attacker.hp / math.max(1, attacker.maxHp)
        if hpPct < 0.7 and not s.hopeBuff then
            local entries = {
                { key = AD.ATK_SPEED, flat = 20 },
            }
            -- 觉醒1: 再加攻速10%（合计30%）
            if hasAwaken(attacker, 1) then entries[#entries+1] = { key = AD.ATK_SPEED, flat = 10 } end
            -- 觉醒2: 物穿+10
            if hasAwaken(attacker, 2) then entries[#entries+1] = { key = AD.PHYS_PEN, flat = 10 } end
            -- 觉醒3: 伤害加成+10%
            if hasAwaken(attacker, 3) then entries[#entries+1] = { key = AD.DMG_BONUS, flat = 10 } end
            -- 觉醒5: 护甲+10
            if hasAwaken(attacker, 5) then
                entries[#entries+1] = { key = AD.PHYS_ARMOR, flat = 10 }
            end
            -- 觉醒6: 攻速25%（额外）
            if hasAwaken(attacker, 6) then entries[#entries+1] = { key = AD.ATK_SPEED, flat = 25 } end
            -- 觉醒7: HP<35%时所有效果翻倍
            if hasAwaken(attacker, 7) and hpPct < 0.35 then
                -- 翻倍所有flat/pct →
                for _, e in ipairs(entries) do
                    if e.flat then e.flat = e.flat * 2 end
                    if e.pct then e.pct = e.pct * 2 end
                end
            end
            attacker.attrs:addModifier("talent_hope", entries)
            s.hopeBuff = true
            talentLog("[Talent] 大狗嚼 衔骨狂：激励(HP=" .. math.floor(hpPct * 100) .. "%)")
        elseif hpPct >= 0.7 and s.hopeBuff then
            attacker.attrs:removeModifier("talent_hope")
            s.hopeBuff = false
        elseif s.hopeBuff and hasAwaken(attacker, 7) then
            -- 觉醒7: 需要重新检测5%阈值切换
            local below35 = hpPct < 0.35
            local wasBelowKey = s.hopeBelowThreshold or false
            if below35 ~= wasBelowKey then
                s.hopeBelowThreshold = below35
                -- 重建 modifier
                attacker.attrs:removeModifier("talent_hope")
                s.hopeBuff = false
                -- 下次循环会重新添加
            end
        end
    end

    -- #3 叮咚鸡 已读不回：前两刀 70% 伤害，第三刀 1.8 倍且必暴
    if heroId == 3 and attacker.attrs then
        s.atkCount = s.atkCount + 1
        local forcePrec = s.preciseChain or false
        attacker.attrs:removeModifier("talent_precise")
        s.preciseBuff = false
        if s.atkCount % 3 == 0 or forcePrec then
            -- 觉醒1: 第三刀 1.8→2.2 倍
            local precBonus = hasAwaken(attacker, 1) and 120 or 80
            local entries = {
                { key = AD.DMG_BONUS, flat = precBonus },
                { key = AD.PHYS_CRIT_RATE, flat = 100 },
            }
            -- 觉醒4: 无视护甲（穿透9999)
            if hasAwaken(attacker, 4) then
                entries[#entries+1] = { key = AD.PHYS_PEN, flat = 9999 }
            end
            attacker.attrs:addModifier("talent_precise", entries)
            s.preciseBuff = true
            s.preciseChain = false
            attacker._preciseKill = true
            talentLog("[Talent] 叮咚鸡 已读不回：第" .. s.atkCount .. "次通知到了 ×" .. (1 + precBonus / 100))
        else
            attacker.attrs:addModifier("talent_precise", {
                { key = AD.DMG_BONUS, flat = -30 },
            })
            s.preciseBuff = false
            attacker._preciseKill = nil
        end
    end

    -- #3 叮咚鸡觉醒2: 物理暴击+5%（永久加成，首次激活时添加成
    if heroId == 3 and hasAwaken(attacker, 2) and not s.awakPrecCritApplied then
        s.awakPrecCritApplied = true
        attacker.attrs:addModifier("awaken_linda_crit", {
            { key = AD.PHYS_CRIT_RATE, flat = 5 },
        })
        -- 觉醒6: 暴击伤害+25%
        if hasAwaken(attacker, 6) then
            attacker.attrs:addModifier("awaken_linda_critdmg", {
                { key = AD.CRIT_DMG, flat = 25 },
            })
        end
    end

    -- #7 信光机兵 必杀蓄力：蓄满时打贯穿光线；觉醒7才给连击
    if heroId == 7 and attacker.attrs and s.flashReady then
        if hasAwaken(attacker, 7) then
            attacker.attrs:addModifier("talent_flash", {
                { key = AD.COMBO_RATE, flat = 200 },
            })
            talentLog("[Talent] 信光机兵 必杀蓄力：光线+连击")
        else
            talentLog("[Talent] 信光机兵 必杀蓄力：光线就绪")
        end
    end

    -- #7 信光机兵觉醒效果（非闪光时也生效的永久加成）
    if heroId == 7 and attacker.attrs then
        -- 觉醒1: 连击增伤+5% (永久加成，首次添加
        -- 觉醒4: 连击增伤+10%
        -- 觉醒5: 连击概率+20%
        -- 觉醒6: 连击无法被闪避（通过临时命中值加成实现）
        if not s.awakFlashApplied then
            s.awakFlashApplied = true
            local entries = {}
            local comboDmgBonus = 0
            if hasAwaken(attacker, 1) then comboDmgBonus = comboDmgBonus + 5 end
            if hasAwaken(attacker, 4) then comboDmgBonus = comboDmgBonus + 10 end
            if comboDmgBonus > 0 then
                entries[#entries+1] = { key = AD.COMBO_DMG_UP, flat = comboDmgBonus }
            end
            if hasAwaken(attacker, 5) then
                entries[#entries+1] = { key = AD.COMBO_RATE, flat = 20 }
            end
            if #entries > 0 then
                attacker.attrs:addModifier("awaken_flash_passive", entries)
            end
        end
        -- 觉醒6: 连击无法被闪避，临时命中+9999
        if hasAwaken(attacker, 6) then
            attacker.attrs:addModifier("awaken_flash_hit", {
                { key = AD.HIT_VALUE, flat = 9999 },
            })
        end
        -- 觉醒7: 连击+100%、连击增伤30%，但只能由闪光协议触发
        -- 非闪光时连击概率清零（在onAfterAttack中处理）
    end

    -- #8 愤怒的小雀觉醒: 攻击标记目标时的临时增益（onAfterAttack中移除）
    if heroId == 8 and attacker.attrs then
        -- 清除上次的临时modifier
        attacker.attrs:removeModifier("awaken_mark_crit")
        attacker.attrs:removeModifier("awaken_mark_first_crit")
        attacker.attrs:removeModifier("awaken_mark_critdmg")
        -- 觉醒3/5: 仅当存在标记目标时才应用暴击加成
        local anyMarked = false
        for _, enemy in ipairs(TAL_BCS.bEnemies) do
            if enemy.hp > 0 and SEM.has(enemy, SEM.MARKED) then
                anyMarked = true
                break
            end
        end
        -- 觉醒3: 攻击标记目标暴击+15%（先应用，onAfterAttack中移除）
        if hasAwaken(attacker, 3) and anyMarked then
            attacker.attrs:addModifier("awaken_mark_crit", {
                { key = AD.PHYS_CRIT_RATE, flat = 15 },
            })
        end
        -- 觉醒5: 对标记目标暴击伤害30%
        if hasAwaken(attacker, 5) and anyMarked then
            attacker.attrs:addModifier("awaken_mark_critdmg", {
                { key = AD.CRIT_DMG, flat = 30 },
            })
        end
        -- 觉醒6: 首次攻击标记目标必暴
        if hasAwaken(attacker, 6) then
            -- 使用 markFirstHitCrit 跟踪，需在onAfterAttack 中根据目标判断
            -- 先应用必暴buff，onAfterAttack中会根据是否已使用来移除
            -- 需要遍历检查是否有未消费的标记目标
            local hasUnusedTarget = false
            for _, enemy in ipairs(TAL_BCS.bEnemies) do
                if enemy.hp > 0 and SEM.has(enemy, SEM.MARKED) and not s.markFirstHitCrit[enemy] then
                    hasUnusedTarget = true
                    break
                end
            end
            if hasUnusedTarget then
                attacker.attrs:addModifier("awaken_mark_first_crit", {
                    { key = AD.PHYS_CRIT_RATE, flat = 100 },
                })
            end
        end
    end

    -- #14 内鬼觉醒4: 对新敌人首次攻击必定暴击
    if heroId == 14 and attacker.attrs and hasAwaken(attacker, 4) then
        attacker.attrs:removeModifier("awaken_firsthit_crit")
        -- 先应用，onAfterAttack中根据目标判断是否保留
        local hasNewTarget = false
        for _, enemy in ipairs(TAL_BCS.bEnemies) do
            if enemy.hp > 0 and not s.firstHitTargets[enemy] then
                hasNewTarget = true
                break
            end
        end
        if hasNewTarget then
            attacker.attrs:addModifier("awaken_firsthit_crit", {
                { key = AD.PHYS_CRIT_RATE, flat = 100 },
            })
        end
    end

    -- === 转职天赋: 攻击前 ===

    -- 103 狂暴之血: HP每损失5%, 物攻+2.5%
    if hasAdv(attacker, "adv_103_berserker_blood") and attacker.attrs then
        attacker.attrs:removeModifier("talent_berserker")
        local hpPct = attacker.hp / math.max(1, attacker.maxHp)
        local lostPct = math.floor((1.0 - hpPct) * 100 / 5) -- 5%一阶
        local bonus = lostPct * 2.5
        if bonus > 0 then
            attacker.attrs:addModifier("talent_berserker", {
                { key = AD.PHYS_ATK_BONUS, flat = bonus },
            })
        end
        -- 205 狂风骤雨: 额外每5%损失→攻速3%, 物暴击1.5%
        if hasAdv(attacker, "adv_205_storm_fury") then
            attacker.attrs:removeModifier("talent_storm")
            if lostPct > 0 then
                attacker.attrs:addModifier("talent_storm", {
                    { key = AD.ATK_SPEED, flat = lostPct * 3 },
                    { key = AD.PHYS_CRIT_RATE, flat = lostPct * 1.5 },
                })
            end
        end
    end

    -- 206 嗜血狂怒 HP>50%时每次攻击减3%当前HP
    if hasAdv(attacker, "adv_206_bloodthirst") and attacker.attrs then
        local hpPct = attacker.hp / math.max(1, attacker.maxHp)
        if hpPct > 0.5 then
            local selfDmg = math.floor(attacker.hp * 0.03)
            if selfDmg > 0 then
                -- FIX: 通过 attrs:takeDamage 同步扣血，避免 unit.hp →attrs.final[HP] 脱节
                local actualSelfDmg = attacker.attrs:takeDamage(selfDmg)
                attacker.hp = attacker.attrs:get(AD.HP)
                if attacker.hp > attacker.maxHp then attacker.hp = attacker.maxHp end
                if attacker.hp <= 0 then attacker.hp = 1; attacker.attrs.final[AD.HP] = 1 end
            end
        end
    end

    -- 110 影袭: 消费影袭buff →+30%伤害
    if hasAdv(attacker, "adv_110_shadow_strike") and s.shadowStrikeBuff then
        attacker.attrs:addModifier("talent_shadow_strike", {
            { key = AD.DMG_BONUS, flat = 30 },
        })
    end

    -- 219 致命之刃: 重置每轮限制（免费攻击不重置，只有自然充能的攻击才重置）
    if s.lethalBladeUsed then
        if s.lethalBladeSkipReset then
            s.lethalBladeSkipReset = false  -- 这是免费攻击，跳过本次重置
        else
            s.lethalBladeUsed = false  -- 自然充能攻击，解除限制
        end
    end

    -- 109 隐匿暗影状态 暴击+15%, 暴击伤害+30%（由update管理添加/移除)

    -- 217 瞬杀: 5秒未受击→暴击25%（由update管理)
    -- 218 千面: 5秒未受击→攻速50%,伤害+10%（由update管理)

    -- #21 闪电卖鸡 银光：觉醒5 上次触发后填充15%攻击进度；每轮攻击只判定一次银光
    if heroId == 21 then
        s.silverFlashChecked = false
        if s.silverLightProgressBoost then
            attacker.atkProgress = math.min(1.0, (attacker.atkProgress or 0) + 0.15)
            s.silverLightProgressBoost = false
            talentLog("[Talent] 闪电卖鸡 觉醒5：攻击进度+15%")
        end
        -- 觉醒6：每80命中+5护甲（战斗内动态，与命中值挂钩）
        if hasAwaken(attacker, 6) and attacker.attrs then
            local hitVal = attacker.attrs:get(AD.HIT_VALUE)
            local armorBonus = math.floor(hitVal / 80) * 5
            attacker.attrs:removeModifier("awaken_alex_hit_armor")
            if armorBonus > 0 then
                attacker.attrs:addModifier("awaken_alex_hit_armor", {
                    { key = AD.ARMOR, flat = armorBonus },
                })
            end
        end
    end

    -- #22 小黑子 法术机关枪：
    -- 普攻与连击计入 machineGunNormalCount；连射弹标记 machineGunBurstShot 不计入，但仍走完整 performAttack
    if heroId == 22 and attacker.attrs then
        s.lastAttackWasBurst = false
        if s.machineGunBurstShot then
            s.machineGunBurstShot = false
            s.lastAttackWasBurst = true
        else
            tickSeraMachineGunCount(attacker, s)
        end
    end
end

--- 获取锁定目标索引（决斗者04专用，在目标选择阶段调用)
--- 返回 nil 表示不干预目标选择
---@param attacker table
---@param targetList table
---@return number|nil
function TAL.getLockedTarget(attacker, targetList)
    if not hasAdv(attacker, "adv_104_duelist") then return nil end
    local s = getState(attacker)
    if not s then return nil end

    -- 5次攻击后释放锁定，切换新目标
    if s.duelCount >= 5 then
        s.duelTarget = nil
        s.duelCount = 0
        return nil
    end

    -- 锁定目标存活检测
    if s.duelTarget and s.duelTarget.hp > 0 then
        -- 查找在 targetList 中的索引
        for i, u in ipairs(targetList) do
            if u == s.duelTarget then
                return i
            end
        end
    end
    -- 目标不存在或已死亡，重新选择（返回nil让正常选择，然后在onAfterAttack中锁定）
    s.duelTarget = nil
    s.duelCount = 0
    return nil
end

--- 连击额外攻击的天赋钩子。熬夜冠军「夜华斩」、小黑子「法术机关枪」：连击同样推进攻击计数并可触发被动。
--- 由 BattleCombat.performComboAttack 在连击命中后调用。
---@param attacker table 攻击方单位
---@param target table 连击目标
---@param isAlly boolean 攻击方是否为己方
---@param targetList table 被攻击方的单位列表
---@param dealDmgFn function 伤害回调
function TAL.onComboAttack(attacker, target, isAlly, targetList, dealDmgFn, comboMeta)
    if not attacker or not dealDmgFn or not targetList then return end
    local s = getState(attacker)
    if not s then return end
    dealDmgFn = wrapDealDmgForLuoxing(attacker, dealDmgFn)
    if s.heroId == 16 and comboMeta and comboMeta.category ~= "healing" then
        local amt = getLuoxingAccumAmount(comboMeta, comboMeta.totalDamage)
        if amt > 0 then
            addLuoxingWindowDamage(attacker, amt, nil, nil)
        end
    end
    if s.heroId == 14 and comboMeta and comboMeta.isCrit then
        tryYouyeSuperCrit(attacker, target, comboMeta, isAlly, dealDmgFn)
    end
    if s.heroId == 11 then
        runSuhuaNightSlash(attacker, s, target, isAlly, targetList, dealDmgFn)
    elseif s.heroId == 22 and attacker.attrs then
        tickSeraMachineGunCount(attacker, s)
    end
end

--- 攻击后钩子
---@param attacker table 攻击方单位
---@param target table 被攻击目标
---@param result table CF.calcAttack 返回的结果
---@param isAlly boolean 攻击方是否为己方
---@param targetList table 被攻击方的单位列表
---@param dealDmgFn function dealDamageToUnit(target, damage, isTargetAlly, prefix, color)
---@param attackerAllies table|nil 攻击方所属队伍列表（可选，星图128共鸣之歌需要）
function TAL.onAfterAttack(attacker, target, result, isAlly, targetList, dealDmgFn, attackerAllies)
    return _after.onAfterAttack(attacker, target, result, isAlly, targetList, dealDmgFn, attackerAllies)
end

function TAL.modifyDamageForTarget(target, damage, isTargetAlly, syncHpFn, dmgCategory)
    if damage <= 0 then return damage end

    if not isTargetAlly then return damage end

    damage = ETS.absorbWithIceStatue(target, damage, TAL_BCS.bEnemies)
    if damage <= 0 then return 0 end

    -- 真布诗人觉醒7：无敌期间免疫伤害
    if target._elwynInvulnTimer and target._elwynInvulnTimer > 0 then
        return 0
    end

    -- 受伤者是铁憨憨自己则不触发吸收（避免循环）
    local targetState = getState(target)
    if targetState and targetState.heroId == 10 then
        -- 觉醒7: 铁憨憨自身受伤防秒杀
        if hasAwaken(target, 7) and targetState.bulwarkDmgCapCd <= 0 and target.attrs then
            local maxHp = target.attrs.final[AD.MAX_HP] or 1
            local cap = math.floor(maxHp * 0.30)
            if damage > cap then
                damage = cap
                targetState.bulwarkDmgCapCd = 8.0
            end
        end
        return damage
    end

    -- 查找存活的铁憨憨
    local rebecca = nil
    local rebeccaState = nil
    for _, ally in ipairs(TAL_BCS.bAllies or {}) do
        local as = getState(ally)
        if as and as.heroId == 10 and ally.hp > 0 then
            rebecca = ally
            rebeccaState = as
            break
        end
    end

    -- 觉醒7: 全队防秒杀（铁憨憨在场，队友单次受伤不超过自身最大生命30%，8秒CD）
    if rebecca and rebeccaState and hasAwaken(rebecca, 7)
       and rebeccaState.bulwarkDmgCapCd <= 0 and target.attrs then
        local allyMaxHp = target.attrs.final[AD.MAX_HP] or 1
        local allyCap = math.floor(allyMaxHp * 0.30)
        if damage > allyCap then
            damage = allyCap
            rebeccaState.bulwarkDmgCapCd = 8.0
        end
    end

    if not rebecca or not rebecca.attrs then return damage end

    -- 计算吸收比例: 基础15%, 觉醒4→20%
    local absorbRate = 0.15
    if hasAwaken(rebecca, 4) then absorbRate = 0.20 end

    local absorbedFromAlly = math.floor(damage * absorbRate + 0.5)
    if absorbedFromAlly <= 0 then return damage end

    -- 转移伤害走铁憨憨自身护甲和格挡
    local transferDmg = absorbedFromAlly
    local CF = require("systems.CombatFormula")
    local category = dmgCategory or "physical"

    -- 1. 护甲抗性减免（统一护甲；能量护盾由 takeDamage 单独消耗，不再当作魔抗）
    local effectiveArmor = rebecca.attrs:get(AD.ARMOR)
    local resistance = CF.armorToResistance(effectiveArmor)
    transferDmg = math.floor(transferDmg * (1 - resistance) + 0.5)

    -- 2. 格挡（含地图词缀格挡压制；超 100% 部分可抵消 debuff）
    local blockRate, blockRatio = 0, 0
    if category == "physical" then
        blockRate = getMAS().getEffectiveBlockRate(rebecca.attrs, AD.PHYS_BLOCK_RATE)
        blockRatio = rebecca.attrs:get(AD.PHYS_BLOCK_RATIO)
    else
        blockRate = getMAS().getEffectiveBlockRate(rebecca.attrs, AD.MAG_BLOCK_RATE)
        blockRatio = rebecca.attrs:get(AD.MAG_BLOCK_RATIO)
    end
    local isBlocked, blockMult = CF.rollBlock(blockRate, blockRatio)
    if isBlocked then
        transferDmg = math.floor(transferDmg * blockMult + 0.5)
    end

    -- 3. 觉醒4: 额外减免15%
    if hasAwaken(rebecca, 4) then
        transferDmg = math.floor(transferDmg * 0.85 + 0.5)
    end

    if transferDmg <= 0 then transferDmg = 1 end
    -- 觉醒7: 防秒杀（转移伤害不超过30%最大HP，8秒CD）
    if hasAwaken(rebecca, 7) and rebeccaState.bulwarkDmgCapCd <= 0 then
        local maxHp = rebecca.attrs.final[AD.MAX_HP] or 1
        local cap = math.floor(maxHp * 0.30)
        if transferDmg > cap then
            transferDmg = cap
            rebeccaState.bulwarkDmgCapCd = 8.0
        end
    end

    -- 对铁憨憨造成转移伤害
    local rebHpBefore = rebecca.hp
    rebecca.attrs:takeDamage(transferDmg)
    rebecca.hp = rebecca.attrs:get(AD.HP)
    if rebecca.hp < 0 then rebecca.hp = 0 end
    if syncHpFn then syncHpFn(rebecca) end
    -- 转移伤害致死时设置死亡动画标记
    if rebecca.hp <= 0 and rebHpBefore > 0 then
        local overkill = math.max(0, transferDmg - rebHpBefore)
        rebecca._overkillRatio = math.min(1.0, overkill / (rebecca.maxHp or rebHpBefore))
        ETS.onShareFatal(rebecca)
    end

    -- 觉醒2: 吸收时回复2%最大HP（3秒CD）
    if hasAwaken(rebecca, 2) and rebeccaState.bulwarkHealCd <= 0 and rebecca.hp > 0 then
        local maxHp = rebecca.attrs.final[AD.MAX_HP] or 1
        local heal = math.floor(maxHp * 0.02 + 0.5)
        rebecca.attrs:heal(heal)
        rebecca.hp = rebecca.attrs:get(AD.HP)
        if syncHpFn then syncHpFn(rebecca) end
        rebeccaState.bulwarkHealCd = 3.0
    end

    -- 返回减少后的伤害给目标
    return damage - absorbedFromAlly
end

function TAL.onDamageTaken(unit, attacker, damage, isUnitAlly, performAttackFn, enemyList, result)
    local s = getState(unit)
    if not s then
        print("[TAL.onDamageTaken] WARNING: getState nil! heroId=" .. tostring(unit.heroId) .. " name=" .. tostring(unit.name) .. " attacker=" .. tostring(attacker.name))
        return
    end

    -- ======== 护盾消耗（觉醒6等提供的护盾优先吸收伤害）=======
    if unit.shield and unit.shield.amount > 0 and damage > 0 then
        local absorbed = math.min(unit.shield.amount, damage)
        unit.shield.amount = unit.shield.amount - absorbed
        -- 护盾吸收的伤害回补HP（因为伤害已经从HP扣除了）
        -- 注意：直接操作 attrs.final[AD.HP] 而非调用 heal()；
        -- 因为 heal() 有死亡保护（HP<=0 时拒绝恢复），而护盾回补的语义是
        -- "这部分伤害本不该从HP扣除"，必须无条件回补）
        if absorbed > 0 and unit.attrs then
            local hp = unit.attrs.final[AD.HP]
            local maxHp = unit.attrs.final[AD.MAX_HP]
            unit.attrs.final[AD.HP] = math.min(hp + absorbed, maxHp)
            unit.hp = unit.attrs:get(AD.HP)
            if unit.hp > unit.maxHp then unit.hp = unit.maxHp end
        end
        if unit.shield.amount <= 0 then
            unit.shield = nil
            talentLog("[Talent] 护盾已耗尽")
        else
            talentLog("[Talent] 护盾吸收 " .. absorbed .. " 伤害 (剩余=" .. unit.shield.amount .. ")")
        end
    end

    -- #4 接化发掌门 不屈之盾：格挡成功时回复3%最大生命中+ 觉醒
    if s.heroId == 4 and unit.hp > 0 and result and result.isBlocked then
        local maxHp = unit.maxHp or 1
        -- 觉醒2: 格挡回复从3%→5%
        local healPct = 0.03
        if hasAwaken(unit, 2) then healPct = 0.05 end
        local healAmt = math.floor(maxHp * healPct + 0.5)
        if healAmt > 0 and unit.attrs then
            unit.attrs:heal(healAmt)
            unit.hp = unit.attrs:get(AD.HP)
            if unit.hp > unit.maxHp then unit.hp = unit.maxHp end
            talentLog("[Talent] 接化发掌门 不屈之盾：格挡回复" .. healAmt .. " HP (" .. math.floor(healPct * 100) .. "%)")
        end
        -- 觉醒1: 格挡后仇恨+150
        if hasAwaken(unit, 1) then
            local TM = require("systems.ThreatManager")
            TM.addThreat(unit, 50)
            talentLog("[Talent] 接化发掌门 觉醒1: 格挡→仇恨50")
        end
        -- 觉醒3: 格挡成功使攻击者攻速15%持续2秒
        if hasAwaken(unit, 3) and attacker.hp > 0 and attacker.attrs then
            -- 使用SEM模拟2秒debuff（通过VULNERABLE类型携带数据，或直接用modifier+定时）
            -- 简化实现 直接应用modifier并在update中管理2秒倒计时
            attacker.attrs:removeModifier("awaken_cecilia_slow_" .. tostring(unit))
            attacker.attrs:addModifier("awaken_cecilia_slow_" .. tostring(unit), {
                { key = AD.ATK_SPEED, flat = -15 },
            })
            -- 记录到状态中用于update清理
            if not s.blockSlowTargets then s.blockSlowTargets = {} end
            s.blockSlowTargets[attacker] = 2.0
            talentLog("[Talent] 接化发掌门 觉醒3: " .. (attacker.name or "攻击者") .. " 攻速-15% (2s)")
        end
        -- 觉醒4: 格挡成功后25%概率使攻击者眩晕1秒）
        if hasAwaken(unit, 4) and attacker.hp > 0 then
            if math.random() < 0.25 then
                SEM.apply(attacker, SEM.FROZEN, 1.0, unit, { isStun = true })
                talentLog("[Talent] 接化发掌门 觉醒4: " .. (attacker.name or "攻击者") .. " 被眩晕1s!")
            end
        end
        -- 觉醒6: 10%概率使本次格挡比例为100%（全额抵挡）
        -- → 此效果在calcAttack中应先行判断，这里做补偿伤害返还
        if hasAwaken(unit, 6) then
            if math.random() < 0.10 then
                -- 全额格挡 →回复本次受到的全部伤害
                if damage > 0 and unit.attrs then
                    unit.attrs:heal(damage)
                    unit.hp = unit.attrs:get(AD.HP)
                    if unit.hp > unit.maxHp then unit.hp = unit.maxHp end
                    talentLog("[Talent] 接化发掌门 觉醒6: 完美格挡! 回复全部伤害 " .. damage)
                end
            end
        end
        -- 化劲：格挡掉的伤害进反击池（觉醒7额外再记一份）
        do
            local blockedAmt = result.blockedDamage or math.floor(damage * 0.3 + 0.5)
            if hasAwaken(unit, 7) then
                blockedAmt = math.floor(blockedAmt * 1.5 + 0.5)
            end
            s.blockAbsorbedDmg = (s.blockAbsorbedDmg or 0) + blockedAmt
            ETS.onBlock(unit, blockedAmt)
            talentLog("[Talent] 接化发掌门 化劲蓄力+" .. blockedAmt .. " (累计=" .. s.blockAbsorbedDmg .. ")")
        end
    end

    -- #8 愤怒的小雀 仇册：记下打过自己的人，优先标记
    if isUnitAlly and attacker and (attacker.hp or 0) > 0 then
        for _, ally in ipairs(TAL_BCS.bAllies or {}) do
            if ally.heroId == 8 and (ally.hp or 0) > 0 then
                local as = getState(ally)
                if as then
                    as.feudAttackers = as.feudAttackers or {}
                    as.feudAttackers[attacker] = true
                    if not SEM.has(attacker, SEM.MARKED) then
                        applyAyaneMark(ally, attacker, TAL_BCS.bEnemies or {})
                        talentLog("[Talent] 愤怒的小雀 仇册：记下 " .. (attacker.name or "?"))
                    end
                end
                break
            end
        end
    end

    -- #10 铁憨憨「帝国铁壁」：伤害吸收已移至 TAL.modifyDamageForTarget（takeDamage前拦截）

    -- （内鬼觉醒5免疫次数由 RelicConditionHandler.onBeforeTakeDamage 统一消费）

    -- === 转职天赋: 受伤害===

    -- 107 巡游射击: 怪物攻击其他角色后，该角色25%概率立即攻击
    -- 这里处理的是：怪物(attacker)攻击了目标unit)，巡游射击者(ally)延迟反击
    if isUnitAlly and attacker.hp > 0 then
        for _, ally in ipairs(TAL_BCS.bAllies) do
            if ally ~= unit and ally.hp > 0 and hasAdv(ally, "adv_107_patrol_shot") then
                local chance = 0.25
                if hasAdv(ally, "adv_213_wind_spirit") then chance = 0.35 end
                if math.random() < chance then
                    local as = getState(ally)
                    if as then
                        -- 加入延迟队列表秒后触发）
                        as.patrolQueue[#as.patrolQueue + 1] = {
                            target = attacker,
                            timer  = 1.0,
                        }
                    end
                end
            end
        end
    end

    -- 202 传颂祝福: 累计损失HP，每10%一层→全队伤害+7%
    if hasAdv(unit, "adv_202_praise_blessing") and unit.attrs then
        s.praiseTotalLost = s.praiseTotalLost + damage
        local maxHp = unit.maxHp or 1
        local newStacks = math.min(14, math.floor(s.praiseTotalLost / (maxHp * 0.10)))
        if newStacks > s.praiseStacks then
            s.praiseStacks = newStacks
            -- 更新全队伤害加成
            for _, ally in ipairs(TAL_BCS.bAllies) do
                if ally.hp > 0 and ally.attrs then
                    ally.attrs:removeModifier("talent_praise")
                    ally.attrs:addModifier("talent_praise", {
                        { key = AD.DMG_BONUS, flat = s.praiseStacks * 7 },
                    })
                end
            end
            talentLog("[Talent] 传颂祝福 ×" .. s.praiseStacks .. " (全队伤害+" .. (s.praiseStacks * 7) .. "%)")
        end
    end

    -- 203 十字盾守: 受伤+2护甲(3秒, max50）
    if hasAdv(unit, "adv_203_cross_shield") and unit.attrs then
        if s.crossShieldStacks < 50 then
            s.crossShieldStacks = s.crossShieldStacks + 1
            unit.attrs:removeModifier("talent_cross_shield")
            unit.attrs:addModifier("talent_cross_shield", {
                { key = AD.PHYS_ARMOR, flat = s.crossShieldStacks * 2 },
            })
        end
    end

    -- 204 怒龙反击: 受击→进度条+40%
    if hasAdv(unit, "adv_204_dragon_counter") then
        unit.atkProgress = math.min(1.0, (unit.atkProgress or 0) + 0.40)
        talentLog("[Talent] 怒龙反击: 进度+40%")
    end

    -- 217/218 瞬杀/千面: 受击重置计时
    if hasAdv(unit, "adv_217_instant_kill") or hasAdv(unit, "adv_218_thousand_faces") then
        s.timeSinceHit = 0
        if s.noHitBuffApplied then
            unit.attrs:removeModifier("talent_no_hit")
            s.noHitBuffApplied = false
        end
    end
end

--- 己方死亡拦截钩子（HP≤0时调用，返回true表示阻止死亡）
---@param dyingUnit table 即将死亡的单位
---@param allies table 己方全部单位列表
---@param syncHpFn function syncUnitHp(unit) 的引用
---@return boolean 是否阻止死亡（true=复活）
function TAL.onAllyDeath(dyingUnit, allies, syncHpFn)
    if ETS.tryTicketRevive(dyingUnit, allies, syncHpFn) then
        return true
    end

    -- ======== 星图节点125 不死鸟之翼 免疫致命伤害 + 3秒恢复0%HP ========
    if hasStarNode(dyingUnit, 125) then
        local ds = getState(dyingUnit)
        if ds and not ds.phoenixUsed then
            ds.phoenixUsed = true
            -- 免疫致命伤害：将HP恢复到1
            if dyingUnit.attrs then
                dyingUnit.attrs.final[AD.HP] = 1
                dyingUnit.hp = 1
                -- 施加3秒持续治疗(总量=20%最大HP, →HOT dps = maxHp*0.2/3)
                local maxHp = dyingUnit.maxHp or 1
                local hotDps = math.floor(maxHp * 0.20 / 3.0 + 0.5)
                SEM.apply(dyingUnit, SEM.HOT, 3.0, dyingUnit, { hps = hotDps })
                syncHpFn(dyingUnit)
                talentLog("[Talent] 不死鸟之翼 " .. (dyingUnit.name or "?") .. " 免疫致命伤害! 3秒恢复0%HP (hps=" .. hotDps .. ")")
            else
                dyingUnit.hp = 1
            end
            return true
        end
    end

    -- ======== #15 复活吧爱人 觉醒7: 自身首次死亡必定复活 ========
    if dyingUnit.heroId == 15 then
        local selfState = getState(dyingUnit)
        if selfState and hasAwaken(dyingUnit, 7) and not selfState.selfReviveUsed then
            selfState.selfReviveUsed = true
            -- 复活自身 100% HP
            if dyingUnit.attrs then
                dyingUnit.attrs:fillHp()
                syncHpFn(dyingUnit)
            else
                dyingUnit.hp = dyingUnit.maxHp
            end
            -- 全队回复20%最大生命
            for _, a in ipairs(allies) do
                if a.hp > 0 and a.attrs then
                    local healAmt = math.floor((a.maxHp or 1) * 0.20 + 0.5)
                    if healAmt > 0 then
                        a.attrs:heal(healAmt)
                        a.hp = a.attrs:get(AD.HP)
                        if a.hp > a.maxHp then a.hp = a.maxHp end
                    end
                end
            end
            talentLog("[Talent] 复活吧爱人 觉醒7 圣光奇迹: 自身复活! 全队回复20%HP")
            return true
        end
    end

    -- ======== #15 复活吧爱人 圣光复活：在场时其他角色死亡复活 + 觉醒 ========
    for _, ally in ipairs(allies) do
        if ally.heroId == 15 and ally.hp > 0 and ally ~= dyingUnit then
            local elizState = getState(ally)
            if elizState and not elizState.reviveUsed[dyingUnit] then
                -- 计算复活概率: 基础25%, 觉醒1→40%, 觉醒5→60%；追加技永久层叠加上限80%
                local extraRate = ETS.getReviveRateBonus(ETS.getOwned(15), ally)
                local reviveRate = 0.25 + extraRate
                if hasAwaken(ally, 1) then reviveRate = 0.40 + extraRate end
                if hasAwaken(ally, 5) then reviveRate = 0.60 + extraRate end
                reviveRate = math.min(0.80, reviveRate)
                -- 觉醒4: 战斗中首次死亡的角色必定复活
                if hasAwaken(ally, 4) then
                    reviveRate = 1.0
                end

                if math.random() < reviveRate then
                    elizState.reviveUsed[dyingUnit] = true
                    if dyingUnit.attrs then
                        dyingUnit.attrs:fillHp()
                        syncHpFn(dyingUnit)
                    else
                        dyingUnit.hp = dyingUnit.maxHp
                    end

                    -- 觉醒2: 被复活的角色5秒内受治疗效果30%（标记在单位上，任何治疗者都生效果
                    if hasAwaken(ally, 2) then
                        elizState.reviveHealBoostTargets[dyingUnit] = 5.0
                        dyingUnit._reviveHealBoost = true
                        talentLog("[Talent] 复活吧爱人 觉醒2: " .. (dyingUnit.name or "复活者") .. " 治疗效果+30% (5s)")
                    end

                    -- 觉醒6: 复活时施加20%最大HP护盾(5s)
                    if hasAwaken(ally, 6) then
                        local shieldAmt = math.floor((dyingUnit.maxHp or 1) * 0.20 + 0.5)
                        dyingUnit.shield = { amount = shieldAmt, timer = 5.0 }
                        talentLog("[Talent] 复活吧爱人 觉醒6: " .. (dyingUnit.name or "复活者") .. " 获得护盾 " .. shieldAmt)
                    end

                    talentLog("[Talent] 复活吧爱人 圣光复活: " .. (dyingUnit.name or "?") .. " 被复活！(概率=" .. math.floor(reviveRate * 100) .. "%)")
                    ETS.onSuccessfulRevive(ally, dyingUnit)
                    return true
                else
                    elizState.reviveUsed[dyingUnit] = true
                end
            end
        end
    end
    if dyingUnit.heroId == 15 then
        ETS.onLoverDeathNuke(dyingUnit, allies, TAL_BCS.bEnemies, TAL_BCS.dealDamage)
    end
    return false
end

--- 敌人死亡钩子（敌方HP≤0时调用）
---@param deadEnemy table 死亡的敌方单位
---@param allies table 己方单位列表
---@param enemies table 敌方单位列表
function TAL.onEnemyDeath(deadEnemy, allies, enemies)
    ETS.onEnemyDeath(deadEnemy, allies, enemies)
    for _, ally in ipairs(allies) do
        if ally.hp > 0 then
            local s = getState(ally)

            -- 110 影袭: 敌人死亡→攻击进度+100% + 下次伤害+30%
            if hasAdv(ally, "adv_110_shadow_strike") then
                ally.atkProgress = 1.0
                if s then
                    s.shadowStrikeBuff = true
                end
                talentLog("[Talent] 影袭: " .. ally.name .. " 进度条已满+ 伤害+30%")
            end

            -- ======== 觉醒: 敌人死亡触发 ========

            -- #11 熬夜冠军 觉醒7: 夜华斩击杀敌人时立即刷新攻击计时
            if s and s.heroId == 11 and hasAwaken(ally, 7) then
                -- 将攻击计数重置到下次能立即触发夜华斩
                local slashInterval = 4
                if hasAwaken(ally, 3) then slashInterval = 3 end
                -- 设置为 slashInterval-1，这样下次攻击就会触发
                s.atkCount = slashInterval - 1
                talentLog("[Talent] 熬夜冠军 觉醒7: 击杀刷新→下次攻击触发夜华斩 (atkCount=" .. s.atkCount .. ")")
            end

            -- #14 内鬼 觉醒5: 击杀随机获得1~2次免疫（共用 RCH.immunityCount）
            if s and s.heroId == 14 and hasAwaken(ally, 5) then
                local killImmunity = math.random(1, 2)
                RCH.addImmunityCharges(ally, killImmunity)
                talentLog("[Talent] 内鬼 觉醒5: 击杀+" .. killImmunity .. "免疫 (剩余" .. RCH.getImmunityCount(ally) .. "次)")
            end

            -- #14 内鬼 觉醒6: 击杀敌人后暴击伤害10%，最多500%
            if s and s.heroId == 14 and hasAwaken(ally, 6) and ally.attrs then
                s.killCritDmgStacks = math.min(100, s.killCritDmgStacks + 10)
                ally.attrs:removeModifier("awaken_kill_critdmg")
                ally.attrs:addModifier("awaken_kill_critdmg", {
                    { key = AD.CRIT_DMG, flat = s.killCritDmgStacks },
                })
                talentLog("[Talent] 内鬼 觉醒6: 击杀→暴击伤害" .. s.killCritDmgStacks .. "%/100%")
            end

            -- ======== 星图节点126 杀戮盛宴 击杀敌人后攻速30%，持续5秒）========
            if hasStarNode(ally, 126) and s and ally.attrs then
                s.slaughterTimer = 5.0
                ally.attrs:removeModifier("starmap_slaughter")
                ally.attrs:addModifier("starmap_slaughter", {
                    { key = AD.ATK_SPEED, flat = 30 },
                })
                talentLog("[Talent] 杀戮盛宴 " .. (ally.name or "?") .. " 攻速30% (5s)")
            end
        end
    end

    -- #8 愤怒的小雀 仇册：被标记敌人死亡 → 优先传给仇人，否则随机
    local ayane = getPrimaryAyane(allies, false)
    if ayane and SEM.has(deadEnemy, SEM.MARKED) then
        local as = getState(ayane)
        local aliveEnemies = getAliveEnemies(enemies)
        local newTarget = nil
        if as and as.feudAttackers then
            as.feudAttackers[deadEnemy] = nil
            for foe, _ in pairs(as.feudAttackers) do
                if foe and (foe.hp or 0) > 0 then
                    newTarget = foe
                    break
                end
            end
        end
        if not newTarget and #aliveEnemies > 0 then
            newTarget = aliveEnemies[math.random(#aliveEnemies)]
        end
        if newTarget then
            applyAyaneMark(ayane, newTarget, enemies)
            talentLog("[Talent] 愤怒的小雀 仇册转移→" .. (newTarget.name or "?")
                .. " (增伤=" .. math.floor(getAyaneMarkMult(ayane) * 100) .. "%)")
        else
            clearAyaneMarks(enemies)
        end
    end
    TAL.checkMarkTarget(allies, enemies)
end

--- 每帧更新钩子（在 SEM.update 之后调用）
---@param dt number 帧间隔
---@param allies table 己方列表
---@param enemies table 敌方列表
---@param ctx table { healUnit, dealDamage, syncHp, performAttack }
function TAL.update(dt, allies, enemies, ctx)
    return _talentUpdate.update(dt, allies, enemies, ctx)
end

function TAL.getConquerStacks(unit)
    local s = getState(unit)
    if s and s.heroId == 5 then
        return s.conquerStacks
    end
    return 0
end



--- 愤怒的小雀 觉醒2 补标检查：当前无敌人带标记时重新标记一个随机敌人
---@param allies table[] 己方单位
---@param enemies table[] 敌方单位
function TAL.checkMarkTarget(allies, enemies)
    local ayane = getPrimaryAyane(allies, false)
    if not ayane then return end
    if hasAnyAyaneMark(enemies) then return end
    local aliveEnemies = getAliveEnemies(enemies)
    if #aliveEnemies == 0 then return end
    local as = getState(ayane)
    local target = nil
    if as and as.feudAttackers then
        for foe, _ in pairs(as.feudAttackers) do
            if foe and (foe.hp or 0) > 0 then
                target = foe
                break
            end
        end
    end
    if not target then
        target = aliveEnemies[math.random(#aliveEnemies)]
    end
    applyAyaneMark(ayane, target, enemies)
    talentLog("[Talent] 愤怒的小雀 仇册补标 " .. (target.name or "?")
        .. " (增伤=" .. math.floor(getAyaneMarkMult(ayane) * 100) .. "%)")
end
return TAL
