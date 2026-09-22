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
local TalentBeforeAttack = require("systems.talents.TalentBeforeAttack")
local TalentDamageTaken = require("systems.talents.TalentDamageTaken")
local TalentModifyDamage = require("systems.talents.TalentModifyDamage")
local TalentAllyDeath = require("systems.talents.TalentAllyDeath")
local TalentEnemyDeath = require("systems.talents.TalentEnemyDeath")
local TalentComboAttack = require("systems.talents.TalentComboAttack")
local TalentFatFish = require("systems.talents.TalentFatFish")
local ClassGateRuntime = require("systems.ClassGateRuntime")
local EquipmentSetRuntime = require("systems.EquipmentSetRuntime")

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

local _fatFish = TalentFatFish.bind({
    hasAwaken = hasAwaken,
    getState = getState,
    talentLog = talentLog,
    getAliveEnemies = getAliveEnemies,
    calcTalentFixedDamage = calcTalentFixedDamage,
})
local onFatFishAfterAttack = _fatFish.onAfterAttack

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
        onFatFishAfterAttack = onFatFishAfterAttack,
        getTAL_BCS = function() return TAL_BCS end,
    })
end
bindTalentAfterAttack()

local _before
local function bindTalentBeforeAttack()
    _before = TalentBeforeAttack.bind({
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
        getTAL_BCS = function() return TAL_BCS end,
        getPrimaryAyane = getPrimaryAyane,
        applyAyaneMark = applyAyaneMark,
        tryAlexSilverFlash = tryAlexSilverFlash,
        fireLuoxingFlyingSwords = fireLuoxingFlyingSwords,
        addMelissaStarMarks = addMelissaStarMarks,
        addLuoxingWindowDamage = addLuoxingWindowDamage,
        getLuoxingAccumAmount = getLuoxingAccumAmount,
        applyElwynEnergyBlessing = applyElwynEnergyBlessing,
        runSuhuaNightSlash = runSuhuaNightSlash,
        tickSeraMachineGunCount = tickSeraMachineGunCount,
        findLivingElwyn = findLivingElwyn,
        tryElwynInvulnOnEsBreak = tryElwynInvulnOnEsBreak,
        isHighestThreat = isHighestThreat,
        isMelissaStarGateAttackSourceActive = isMelissaStarGateAttackSourceActive,
        updateMelissaStarGate = updateMelissaStarGate,
    })
end
bindTalentBeforeAttack()

local _taken
local function bindTalentDamageTaken()
    _taken = TalentDamageTaken.bind({
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
        getTAL_BCS = function() return TAL_BCS end,
        getPrimaryAyane = getPrimaryAyane,
        applyAyaneMark = applyAyaneMark,
        tryAlexSilverFlash = tryAlexSilverFlash,
        fireLuoxingFlyingSwords = fireLuoxingFlyingSwords,
        addMelissaStarMarks = addMelissaStarMarks,
        addLuoxingWindowDamage = addLuoxingWindowDamage,
        getLuoxingAccumAmount = getLuoxingAccumAmount,
        applyElwynEnergyBlessing = applyElwynEnergyBlessing,
        runSuhuaNightSlash = runSuhuaNightSlash,
        tickSeraMachineGunCount = tickSeraMachineGunCount,
        findLivingElwyn = findLivingElwyn,
        tryElwynInvulnOnEsBreak = tryElwynInvulnOnEsBreak,
        isHighestThreat = isHighestThreat,
        isMelissaStarGateAttackSourceActive = isMelissaStarGateAttackSourceActive,
        updateMelissaStarGate = updateMelissaStarGate,
    })
end
bindTalentDamageTaken()

local _modDmg
local function bindTalentModifyDamage()
    _modDmg = TalentModifyDamage.bind({
        getState = getState,
        hasAdv = hasAdv,
        hasAwaken = hasAwaken,
        hasStarNode = hasStarNode,
        talentLog = talentLog,
        getTAL_BCS = function() return TAL_BCS end,
        getMAS = getMAS,
    })
end
bindTalentModifyDamage()

local _allyDeath
local function bindTalentAllyDeath()
    _allyDeath = TalentAllyDeath.bind({
        getState = getState,
        hasAdv = hasAdv,
        hasAwaken = hasAwaken,
        hasStarNode = hasStarNode,
        talentLog = talentLog,
        getTAL_BCS = function() return TAL_BCS end,
    })
end
bindTalentAllyDeath()

local _enemyDeath
local function bindTalentEnemyDeath()
    _enemyDeath = TalentEnemyDeath.bind({
        getState = getState,
        hasAdv = hasAdv,
        hasAwaken = hasAwaken,
        hasStarNode = hasStarNode,
        talentLog = talentLog,
        getAliveEnemies = getAliveEnemies,
        getPrimaryAyane = getPrimaryAyane,
        applyAyaneMark = applyAyaneMark,
        clearAyaneMarks = clearAyaneMarks,
        getAyaneMarkMult = getAyaneMarkMult,
        hasAnyAyaneMark = hasAnyAyaneMark,
    })
end
bindTalentEnemyDeath()

local _combo
local function bindTalentComboAttack()
    _combo = TalentComboAttack.bind({
        getState = getState,
        wrapDealDmgForLuoxing = wrapDealDmgForLuoxing,
        getLuoxingAccumAmount = getLuoxingAccumAmount,
        addLuoxingWindowDamage = addLuoxingWindowDamage,
        tryYouyeSuperCrit = tryYouyeSuperCrit,
        runSuhuaNightSlash = runSuhuaNightSlash,
        tickSeraMachineGunCount = tickSeraMachineGunCount,
    })
end
bindTalentComboAttack()

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
    ClassGateRuntime.onBattleStart(allies, enemies)
    for _, u in ipairs(allies or {}) do
        EquipmentSetRuntime.onBattleStart(u, allies)
    end
end

--- 攻击前钩子（performAttack开头，目标选择后调用）
---@param attacker table 攻击方单位
function TAL.onBeforeAttack(attacker)
    return _before.onBeforeAttack(attacker)
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
    return _combo.onComboAttack(attacker, target, isAlly, targetList, dealDmgFn, comboMeta)
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
    local r = _after.onAfterAttack(attacker, target, result, isAlly, targetList, dealDmgFn, attackerAllies)
    ClassGateRuntime.onAfterAttack(attacker, target, result, isAlly, dealDmgFn, attackerAllies)
    EquipmentSetRuntime.onAfterAttack(attacker, target, result, isAlly, dealDmgFn, targetList)
    if result and result.totalDamage then
        EquipmentSetRuntime.addSwordWindowDamage(attacker, result.totalDamage)
    end
    return r
end

function TAL.modifyDamageForTarget(target, damage, isTargetAlly, syncHpFn, dmgCategory)
    return _modDmg.modifyDamageForTarget(target, damage, isTargetAlly, syncHpFn, dmgCategory)
end

function TAL.onDamageTaken(unit, attacker, damage, isUnitAlly, performAttackFn, enemyList, result)
    return _taken.onDamageTaken(unit, attacker, damage, isUnitAlly, performAttackFn, enemyList, result)
end

--- 己方死亡拦截钩子（HP≤0时调用，返回true表示阻止死亡）
---@param dyingUnit table 即将死亡的单位
---@param allies table 己方全部单位列表
---@param syncHpFn function syncUnitHp(unit) 的引用
---@return boolean 是否阻止死亡（true=复活）
function TAL.onAllyDeath(dyingUnit, allies, syncHpFn)
    return _allyDeath.onAllyDeath(dyingUnit, allies, syncHpFn)
end

--- 敌人死亡钩子（敌方HP≤0时调用）
---@param deadEnemy table 死亡的敌方单位
---@param allies table 己方单位列表
---@param enemies table 敌方单位列表
function TAL.onEnemyDeath(deadEnemy, allies, enemies)
    local r = _enemyDeath.onEnemyDeath(deadEnemy, allies, enemies)
    ClassGateRuntime.onEnemyDeath(deadEnemy, allies)
    EquipmentSetRuntime.onEnemyDeath(deadEnemy, allies)
    return r
end

--- 每帧更新钩子（在 SEM.update 之后调用）
---@param dt number 帧间隔
---@param allies table 己方列表
---@param enemies table 敌方列表
---@param ctx table { healUnit, dealDamage, syncHp, performAttack }
function TAL.update(dt, allies, enemies, ctx)
    local r = _talentUpdate.update(dt, allies, enemies, ctx)
    ClassGateRuntime.update(dt, allies, enemies, ctx)
    EquipmentSetRuntime.update(dt, allies, enemies, ctx)
    return r
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
    return _enemyDeath.checkMarkTarget(allies, enemies)
end
return TAL
