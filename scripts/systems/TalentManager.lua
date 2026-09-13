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
            -- Hero21 闪电卖鸡: 银光
            silverLightProgressBoost = false,
            silverFlashChecked = false,
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

--- 检查单位是否已激活指定觉醒节点
---@param unit table
---@param nodeIndex number 1~7
---@return boolean
local function hasAwaken(unit, nodeIndex)
    return unit.awakeningNodes ~= nil and unit.awakeningNodes[nodeIndex] == true
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

--- 愤怒的小雀标记增伤倍率
---@param ayane table
---@return number
local function getAyaneMarkMult(ayane)
    return hasAwaken(ayane, 1) and 0.35 or 0.25
end

--- 清除敌方列表上所有愤怒的小雀标记（全局唯一标记，施加前先清场）
---@param opponents table[]
local function clearAyaneMarks(opponents)
    for _, u in ipairs(opponents or {}) do
        if u and SEM.has(u, SEM.MARKED) then
            SEM.remove(u, SEM.MARKED)
            if u.attrs then
                u.attrs:removeModifier("awaken_mark_debuff")
            end
        end
    end
end

--- 施加愤怒的小雀标记（先清场，保证全场仅一个标记目标）
---@param ayane table 愤怒的小雀单位
---@param target table 标记目标
---@param opponents table[] 对方单位列表
local function applyAyaneMark(ayane, target, opponents)
    if not ayane or not target or target.hp <= 0 then return end
    clearAyaneMarks(opponents)
    local markMult = getAyaneMarkMult(ayane)
    SEM.apply(target, SEM.MARKED, 99999, ayane, { mult = markMult })
    if hasAwaken(ayane, 4) and target.attrs then
        target.attrs:addModifier("awaken_mark_debuff", {
            { key = AD.DODGE, flat = -30 },
            { key = AD.PHYS_ARMOR, flat = -15 },
        })
    end
    if hasAwaken(ayane, 6) then
        local s = getState(ayane)
        if s then s.markFirstHitCrit[target] = nil end
    end
end

--- 战斗开始：队伍内多个愤怒的小雀也只标记一个随机敌人
---@param units table[] 己方/对方单位列表
---@param opposingUnits table[] 被标记的一方
local function applyAyaneBattleStartMark(units, opposingUnits)
    local ayane = nil
    for _, unit in ipairs(units) do
        if unit.heroId == 8 and unit.hp > 0 then
            ayane = unit
            break
        end
    end
    if not ayane then return end
    local aliveOpponents = getAliveEnemies(opposingUnits)
    if #aliveOpponents == 0 then return end
    local target = aliveOpponents[math.random(#aliveOpponents)]
    applyAyaneMark(ayane, target, opposingUnits)
    talentLog("[Talent] 愤怒的小雀 弹弓怒鸟之眼：标记" .. (target.name or "?")
        .. " (受伤+" .. math.floor(getAyaneMarkMult(ayane) * 100) .. "%)")
end

--- 获取队伍中第一个存活愤怒的小雀（标记/补标来源）
---@param allies table[]
---@param requireAw2 boolean|nil 是否要求觉醒2
---@return table|nil
local function getPrimaryAyane(allies, requireAw2)
    for _, ally in ipairs(allies) do
        if ally.hp > 0 and ally.heroId == 8 then
            if not requireAw2 or hasAwaken(ally, 2) then
                return ally
            end
        end
    end
    return nil
end

--- 敌方是否已有愤怒的小雀标记
---@param enemies table[]
---@return boolean
local function hasAnyAyaneMark(enemies)
    for _, e in ipairs(getAliveEnemies(enemies)) do
        if SEM.has(e, SEM.MARKED) then return true end
    end
    return false
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

--- 灵月飞剑累计：排除飞剑本体/飞回（避免递归喂池）
local function isFlyingSwordTalentDmg(prefix, projOpts)
    if prefix == "灵月飞剑" or prefix == "飞回" then return true end
    if projOpts and (projOpts.flyingSwordIndex or projOpts.flyingSwordOnHit) then return true end
    return false
end

--- 灵月飞剑触发间隔（秒）；觉醒2→4秒，觉醒6→3秒
---@param attacker table
---@return number
local function getLuoxingFlyingSwordInterval(attacker)
    local interval = 5.0
    if hasAwaken(attacker, 2) then interval = 4.0 end
    if hasAwaken(attacker, 6) then interval = 3.0 end
    return interval
end

--- 重置万剑归宗飞剑累计窗口（与 interval 对齐）
local function resetLuoxingFlyingSwordWindow(s, interval)
    s.flyingSwordTimer = 0
    s.flyingSwordDamage = 0
    s.flyingSwordWindowSec = interval
end

--- 万剑归宗窗口累计（普攻/连击/附加天赋伤；不含灵月飞剑）
--- 使用 damageDealt（含护盾吸收）而非 actualDamage（仅 HP）
local function getLuoxingAccumAmount(result, fallback)
    if not result then return fallback or 0 end
    local dealt = result.damageDealt
    if dealt and dealt > 0 then return dealt end
    return result.totalDamage or fallback or 0
end

local function addLuoxingWindowDamage(attacker, amount, prefix, projOpts)
    if not attacker or not amount or amount <= 0 then return end
    local s = getState(attacker)
    if not s or s.heroId ~= 16 then return end
    if isFlyingSwordTalentDmg(prefix, projOpts) then return end
    s.flyingSwordDamage = (s.flyingSwordDamage or 0) + amount
end

--- 包装 dealDmgFn：万剑归宗附加天赋伤害计入飞剑窗口
local function wrapDealDmgForLuoxing(attacker, dealDmgFn)
    if not dealDmgFn then return dealDmgFn end
    local s = getState(attacker)
    if not s or s.heroId ~= 16 then return dealDmgFn end
    return function(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
        dealDmgFn(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
        addLuoxingWindowDamage(attacker, dmg, pfx, projOpts)
    end
end

--- 内鬼攻击暴击率/暴击伤害（与 CombatFormula.calcAttack 一致）
local function getYouyeAttackCritStats(attacker, category)
    local critRate = attacker.attrs:get(AD.CRIT_RATE)
    local critDmg  = attacker.attrs:get(AD.CRIT_DMG)
    if category == "physical" then
        critRate = critRate + attacker.attrs:get(AD.PHYS_CRIT_RATE)
        critDmg  = critDmg  + attacker.attrs:get(AD.PHYS_CRIT_DMG)
    else
        critRate = critRate + attacker.attrs:get(AD.MAG_CRIT_RATE)
        critDmg  = critDmg  + attacker.attrs:get(AD.MAG_CRIT_DMG)
    end
    if attacker.attrs.artifactCritRateMult then
        critRate = critRate * attacker.attrs.artifactCritRateMult
    end
    if attacker.attrs.artifactCritDmgMult then
        critDmg = critDmg * attacker.attrs.artifactCritDmgMult
    end
    return critRate, critDmg
end

--- 内鬼觉醒7：暴击率>100%部分每4%→1%超暴击；超暴击再乘一次暴击伤害
local YOUYE_SUPER_CRIT_RATE_CAP = 20  -- 超暴击概率上限（%），避免高暴击率下无限叠强
local YOUYE_SUPER_CRIT_OVERFLOW_RATIO = 4  -- 溢出暴击率每 N% 转化为 1% 超暴击

local function tryYouyeSuperCrit(attacker, target, result, isAlly, dealDmgFn)
    if not attacker or not hasAwaken(attacker, 7) then return end
    if not result or not result.isCrit or not attacker.attrs then return end
    if not target or target.hp <= 0 or not dealDmgFn then return end

    local critRate, critDmg = getYouyeAttackCritStats(attacker, result.category)
    local superCritRate = math.min(YOUYE_SUPER_CRIT_RATE_CAP, math.max(0, critRate - 100) / YOUYE_SUPER_CRIT_OVERFLOW_RATIO)
    if superCritRate <= 0 or math.random() * 100 >= superCritRate then return end

    local critMult = critDmg / 100
    if critMult <= 1 then return end

    local baseDmg = result.totalDamage or 0
    if baseDmg <= 0 then return end

    local extraDmg = math.floor(baseDmg * (critMult - 1) + 0.5)
    if extraDmg <= 0 then return end

    dealDmgFn(target, extraDmg, not isAlly, "超暴击 ", { 255, 120, 255 }, {
        statCategory = result.category or "magical",
        critEligible = false,
    })
    talentLog(string.format("[Talent] 内鬼 觉醒7: 超暴击 (率=%.1f%% 额外=%d)", superCritRate, extraDmg))
end

--- 万剑归宗 #16：发射灵月飞剑
---@param attacker table
---@param s table
---@param targetList table
---@param isAlly boolean
---@param dealDmgFn function
---@return boolean fired 是否成功发射
---@return boolean consumeWindow 是否消耗本轮间隔（无伤害的空窗仍消耗）
local function fireLuoxingFlyingSwords(attacker, s, targetList, isAlly, dealDmgFn)
    if not attacker or attacker.hp <= 0 or not dealDmgFn or not targetList then return false, false end

    -- 每柄飞剑 = 窗口累计伤害 × 比例（默认50%；觉醒3：60%）
    local swordDmgPct = 0.50
    if hasAwaken(attacker, 3) then swordDmgPct = 0.60 end

    local accumulated = math.floor((s.flyingSwordDamage or 0) + (s.flyingSwordCarryover or 0) + 0.5)
    if accumulated <= 0 then
        return false, true
    end

    local perSwordDmg = math.floor(accumulated * swordDmgPct + 0.5)
    if perSwordDmg <= 0 then
        return false, true
    end

    local alive = getAliveEnemies(targetList)
    if #alive == 0 then
        return false, false
    end

    s.flyingSwordDamage = 0
    s.flyingSwordCarryover = 0

    local minSwords, maxSwords = 3, 6
    if hasAwaken(attacker, 1) then minSwords = 4 end
    if hasAwaken(attacker, 6) then maxSwords = 7 end
    if minSwords > maxSwords then minSwords, maxSwords = maxSwords, minSwords end

    local swordCount = math.random(minSwords, maxSwords)
    swordCount = math.floor(swordCount + 0.5)
    perSwordDmg = math.floor(perSwordDmg + 0.5)
    local flybackChance = hasAwaken(attacker, 7) and 0.50 or (hasAwaken(attacker, 4) and 0.25 or 0)
    local flybackExtraMult = hasAwaken(attacker, 7) and 1.5 or 1.0
    local recordChance = hasAwaken(attacker, 5) and 0.10 or 0

    local function addCarryover(amt)
        s.flyingSwordCarryover = (s.flyingSwordCarryover or 0) + amt
    end

    for i = 1, swordCount do
        local st = alive[math.random(#alive)]
        if st and st.hp > 0 then
            local dmg = perSwordDmg
            local projOpts = {
                flyingSwordIndex = i,
                flyingSwordCount = swordCount,
                threatScale = 0.1, -- 灵月飞剑伤害仅产生 10% 仇恨
            }
            if recordChance > 0 then
                projOpts.recordOnHit = { chance = recordChance, baseDmg = dmg, addCarryover = addCarryover }
            end
            if flybackChance > 0 then
                projOpts.flyingSwordOnHit = {
                    chance       = flybackChance,
                    extraMult    = flybackExtraMult,
                    baseDmg      = dmg,
                    isTargetAlly = not isAlly,
                    recordChance = recordChance,
                    addCarryover = addCarryover,
                }
            end
            local okDmg, dmgErr = pcall(dealDmgFn, st, dmg, not isAlly, "灵月飞剑", { 180, 220, 255 }, projOpts)
            if not okDmg then
                talentLog("[Talent] 万剑归宗 灵月飞剑 dealDmgFn failed: " .. tostring(dmgErr))
            end
        end
    end

    -- Lua 5.4：%d 仅接受整数；属性伤害可能为浮点
    talentLog(string.format("[Talent] 万剑归宗 灵月飞剑：%.0f柄，单柄=%.0f (窗口%.0fs×%.0f%%)",
        swordCount, perSwordDmg, getLuoxingFlyingSwordInterval(attacker), swordDmgPct * 100))
    return true, true
end

--- 摘星星星人 #20：星门固定触发间隔；基础2.6秒，觉醒3缩短为2.2秒
---@param melissa table
---@return number
local function getMelissaStarGateInterval(melissa)
    if hasAwaken(melissa, 3) then return 2.2 end
    return 2.6
end

--- 摘星星星人 #20：星门基础伤害比例；觉醒1/5递进
---@param melissa table
---@return number
local function getMelissaStarGateDmgMult(melissa)
    if hasAwaken(melissa, 5) then return 4.00 end
    if hasAwaken(melissa, 1) then return 3.40 end
    return 3.00
end

--- 摘星星星人 #20：星门数量；基础1个，觉醒6为2个
---@param melissa table
---@return number
local function getMelissaStarGateCount(melissa)
    return hasAwaken(melissa, 6) and 2 or 1
end

--- 摘星星星人 #20：觉醒6后星门可在本体死亡后继续攻击
---@param melissa table
---@return boolean
local function canMelissaStarGatePersistAfterDeath(melissa)
    return hasAwaken(melissa, 6)
end

--- 同步星门表现层状态；ProjectileSystem 根据这些标记绘制死亡后仍存在的星门
---@param melissa table
---@param s table
local function syncMelissaStarGateVisualState(melissa, s)
    if not melissa or not s then return end
    melissa._starGateSummoned = s.starGateSummoned == true
    melissa._starGateCount = s.starGateCount or 0
    melissa._starGatePersistsAfterDeath = canMelissaStarGatePersistAfterDeath(melissa)
end

--- 摘星星星人 #20：星门当前是否仍是可攻击来源
---@param melissa table
---@param s table|nil
---@return boolean
local function isMelissaStarGateAttackSourceActive(melissa, s)
    if not melissa then return false end
    if melissa.hp and melissa.hp > 0 then return true end
    s = s or getState(melissa)
    return canMelissaStarGatePersistAfterDeath(melissa)
        and s ~= nil
        and s.starGateSummoned == true
        and (s.starGateCount or 0) > 0
end

--- 摘星星星人 #20：星门攻速/连击转化。
--- 每100%攻速转化为10%星门提速，每100%连击转化为8%星门提速，最多40%。
---@param melissa table
---@param s table
---@return number interval
---@return number speedFactor
local function getMelissaStarGateEffectiveInterval(melissa, s)
    local baseInterval = getMelissaStarGateInterval(melissa)
    local atkSpeed = melissa.attrs and melissa.attrs:get(AD.ATK_SPEED) or 0
    local comboRate = melissa.attrs and melissa.attrs:get(AD.COMBO_RATE) or 0
    local speedFactor = math.max(0, atkSpeed) * 0.001 + math.max(0, comboRate) * 0.0008
    speedFactor = math.min(0.40, speedFactor)
    local interval = baseInterval / (1 + speedFactor)
    s.starGateSpeedFactor = speedFactor
    s.starGateInterval = interval
    return interval, speedFactor
end

--- 摘星星星人 #20：从本次普攻产生的额外连击积累星痕，单次最多2层。
---@param melissa table
---@param comboCount number|nil
local function addMelissaStarMarks(melissa, comboCount)
    if not melissa or melissa.heroId ~= 20 then return end
    local s = getState(melissa)
    if not s or not comboCount or comboCount <= 0 then return end
    local gained = math.min(2, math.floor(comboCount))
    s.starGateStarMarks = math.min(5, (s.starGateStarMarks or 0) + gained)
    s.starGateLastAttackComboCount = comboCount
    talentLog(string.format("[Talent] 摘星星星人 星痕：+%d，当前%d/5", gained, s.starGateStarMarks))
end

--- 摘星星星人 #20：星痕对本次星门伤害的倍率。
---@param melissa table
---@param s table
---@return number
local function getMelissaStarMarkDamageScale(melissa, s)
    local marks = math.min(5, math.max(0, s and s.starGateStarMarks or 0))
    return 1 + marks * 0.12
end

--- 摘星星星人 #20：计算星门元素类型
---@param melissa table
---@return number
local function getMelissaStarGateResonanceScale(melissa)
    return hasAwaken(melissa, 7) and 1.50 or 1.0
end

--- 摘星星星人 #20：计算星门元素类型
---@param melissa table
---@return number atkType
local function rollMelissaStarGateAtkType(melissa)
    if not hasAwaken(melissa, 2) then return AD.ATK_SHADOW end
    local types = { AD.ATK_ICE, AD.ATK_LIGHTNING, AD.ATK_FIRE }
    return types[math.random(1, #types)] or AD.ATK_SHADOW
end

--- 摘星星星人 #20：星门命中异常状态目标时的伤害倍率
---@param melissa table
---@param target table
---@return number
local function getMelissaStarGateStatusMult(melissa, target)
    if not hasAwaken(melissa, 4) then return 1.0 end
    if SEM.has(target, SEM.FROZEN) or SEM.has(target, SEM.SHOCKED) or SEM.has(target, SEM.BURNING) then
        return 1.5
    end
    return 1.0
end

--- 摘星星星人 #20：单个角色提供的星象共鸣属性。
--- 基础形态读取摘星星星人自身与其他魔法伤害角色；觉醒7读取全队魔法词条。
--- 设计重点：直接继承对应属性；主继承魔法穿透/魔法伤害加成，少量继承魔法攻击加成折算为伤害加成。
---@param unit table
---@param melissa table
---@return table|nil resonance { name=string, magDmgBonus=number, magPen=number, score=number }
local function calcMelissaUnitResonance(unit, melissa)
    if not unit or not unit.attrs then return nil end
    if unit.hp <= 0 and unit ~= melissa then return nil end
    local isAwaken7 = hasAwaken(melissa, 7)
    if not isAwaken7 and unit.dmgMainType ~= "魔法" then return nil end

    local magPen = unit.attrs:get(AD.MAG_PEN) or 0
    local magDmgBonus = unit.attrs:get(AD.MAG_DMG_BONUS) or 0
    local magAtkBonus = unit.attrs:get(AD.MAG_ATK_BONUS) or 0
    local inheritedDmgBonus = math.max(0, magDmgBonus + magAtkBonus * 0.25)
    local inheritedPen = math.max(0, magPen)
    local score = inheritedDmgBonus + inheritedPen * 0.6
    if score <= 0 then return nil end
    return {
        name = unit.name or (unit == melissa and "摘星星星人" or "?"),
        magDmgBonus = inheritedDmgBonus,
        magPen = inheritedPen,
        score = score,
    }
end

--- 摘星星星人 #20：星象共鸣读取人数上限；基础最多3名魔法角色，觉醒7提升至4名
---@param melissa table
---@return number
local function getMelissaStarGateResonanceLimit(melissa)
    return hasAwaken(melissa, 7) and 4 or 3
end

--- 摘星星星人 #20：计算星象共鸣；基础读取摘星星星人自身与魔法角色，觉醒7读取全队。
---@param melissa table
---@param teamUnits table[]|nil
---@return table resonance { magDmgBonus=number, magPen=number, sourceText=string, independentMult=number }
---@return number count
local function calcMelissaTeamResonance(melissa, teamUnits)
    local contributions = {}
    local includeSelf = true
    for _, unit in ipairs(teamUnits or {}) do
        if includeSelf or unit ~= melissa then
            local value = calcMelissaUnitResonance(unit, melissa)
            if value then
                contributions[#contributions + 1] = value
            end
        end
    end
    if #contributions == 0 then return { magDmgBonus = 0, magPen = 0, sourceText = "无", independentMult = 1.0 }, 0 end

    table.sort(contributions, function(a, b) return (a.score or 0) > (b.score or 0) end)
    local resonanceWeight = 1.50
    local totalDmgBonus = 0
    local totalPen = 0
    local sourceParts = {}
    local count = math.min(getMelissaStarGateResonanceLimit(melissa), #contributions)
    for i = 1, count do
        local c = contributions[i]
        local dmgPart = (c.magDmgBonus or 0) * resonanceWeight
        local penPart = (c.magPen or 0) * resonanceWeight
        totalDmgBonus = totalDmgBonus + dmgPart
        totalPen = totalPen + penPart
        sourceParts[#sourceParts + 1] = string.format("%s:魔伤%.1f%%/魔穿%.1f", c.name or "?", dmgPart, penPart)
    end
    local scale = getMelissaStarGateResonanceScale(melissa)
    local finalDmgBonus = totalDmgBonus * scale
    local finalPen = totalPen * scale
    return {
        magDmgBonus = finalDmgBonus,
        magPen = finalPen,
        sourceText = table.concat(sourceParts, "; "),
        independentMult = 1 + finalDmgBonus / 100,
    }, count
end

--- 摘星星星人 #20：召唤战斗中永久存在的星门
---@param melissa table
---@param s table
local function summonMelissaStarGate(melissa, s)
    if not melissa or not s or s.heroId ~= 20 then return end
    s.starGateSummoned = melissa.hp > 0 or canMelissaStarGatePersistAfterDeath(melissa)
    s.starGateCount = getMelissaStarGateCount(melissa)
    s.starGateTimer = 0
    s.starGateStarMarks = 0
    s.starGateLastAttackComboCount = 0
    s.starGateResonanceDamage = 0
    s.starGateResonanceDmgBonus = 0
    s.starGateResonancePen = 0
    s.starGateResonanceUnits = 0
    s.starGateBaseDamage = 0
    s.starGateResonanceSourceText = "无"
    s.starGateResonanceMult = 1.0
    s.starGateTargetTakenMult = 1.0
    s.starGateArtifactExtraMult = 1.0
    s.starGateFinalDamage = 0
    syncMelissaStarGateVisualState(melissa, s)
    talentLog(string.format("[Talent] 摘星星星人 星门召唤：%d个星门永久存在", s.starGateCount))
end

--- 摘星星星人 #20：计算单个星门本次发射伤害
---@param melissa table
---@param target table
---@param teamUnits table[]|nil
---@param dmgScale number|nil
---@return number damage
---@return boolean isCrit
---@return number atkType
local function calcMelissaStarGateDamage(melissa, target, teamUnits, dmgScale)
    if not melissa or not melissa.attrs or not target or target.hp <= 0 then return 0, false, AD.ATK_SHADOW end
    local atkType = rollMelissaStarGateAtkType(melissa)
    local magAtk = melissa.attrs:get(AD.MAG_ATK) or 0
    local atkCoeff = melissa.atkCoeff or melissa.attrs.atkCoeff or 1.0
    local baseDmg = magAtk * atkCoeff * getMelissaStarGateDmgMult(melissa) * (dmgScale or 1.0)
    local resonanceAttrs, resonanceUnits = calcMelissaTeamResonance(melissa, teamUnits)
    local statusMult = getMelissaStarGateStatusMult(melissa, target)
    local rawDmg = baseDmg * statusMult
    if rawDmg <= 0 then return 0, false, atkType end

    local s = getState(melissa)
    if s then
        s.starGateBaseDamage = baseDmg
        s.starGateResonanceDamage = 0
        s.starGateResonanceDmgBonus = resonanceAttrs.magDmgBonus or 0
        s.starGateResonancePen = resonanceAttrs.magPen or 0
        s.starGateResonanceUnits = resonanceUnits
        s.starGateResonanceSourceText = resonanceAttrs.sourceText or "无"
        s.starGateResonanceMult = resonanceAttrs.independentMult or 1.0
    end

    local dmg, isCrit = calcTalentFixedDamage(melissa, target, rawDmg, {
        atkType = atkType,
        extraPen = resonanceAttrs.magPen,
    })
    local resonanceMult = resonanceAttrs.independentMult or 1.0
    if resonanceMult ~= 1.0 then
        dmg = math.max(1, math.floor(dmg * resonanceMult + 0.5))
    end
    local targetTakenMult = SEM.getDamageTakenMult(target)
    if targetTakenMult and targetTakenMult ~= 1.0 then
        dmg = math.max(1, math.floor(dmg * targetTakenMult + 0.5))
    end
    if s then
        s.starGateTargetTakenMult = targetTakenMult or 1.0
        s.starGateArtifactExtraMult = melissa.attrs.artifactExtraDamageMult or 1.0
        s.starGateFinalDamage = dmg
    end
    return dmg, isCrit, atkType
end

--- 摘星星星人 #20：常驻星门发射攻击投射物
---@param melissa table
---@param isAlly boolean
---@param targetList table[]
---@param dealDmgFn function
---@param teamUnits table[]|nil
---@param gateIndex number
---@param gateCount number
---@param preferredTarget table|nil
---@param dmgScale number|nil
---@return boolean fired
local function fireMelissaStarGate(melissa, isAlly, targetList, dealDmgFn, teamUnits, gateIndex, gateCount, preferredTarget, dmgScale)
    if not melissa or not isMelissaStarGateAttackSourceActive(melissa) or not melissa.attrs or not dealDmgFn or not targetList then return false end
    local alive = getAliveEnemies(targetList)
    if #alive == 0 then return false end
    local target = preferredTarget
    if not target or target.hp <= 0 then
        target = alive[math.random(#alive)]
    end
    if not target or target.hp <= 0 then return false end

    local dmg, isCrit, atkType = calcMelissaStarGateDamage(melissa, target, teamUnits, dmgScale)
    if dmg <= 0 then return false end

    dealDmgFn(target, dmg, not isAlly, "星门", { 220, 160, 255 }, {
        sourceAttacker = melissa,
        starGateIndex = gateIndex or 1,
        starGateCount = gateCount or 1,
        starGateRadius = 118,
        statCategory = AD.getAtkCategory(atkType),
        isCrit = isCrit,
        critEligible = true,
        useBasicProjectile = true,
    })
    return true
end

--- 摘星星星人 #20：触发当前所有星门固定周期发射
---@param melissa table
---@param isAlly boolean
---@param targetList table[]
---@param dealDmgFn function
---@param teamUnits table[]|nil
---@param preferredTarget table|nil
---@param dmgScale number|nil
---@return boolean fired
local function triggerMelissaStarGates(melissa, isAlly, targetList, dealDmgFn, teamUnits, preferredTarget, dmgScale)
    if not melissa or not isMelissaStarGateAttackSourceActive(melissa) or not dealDmgFn or not targetList then return false end
    local s = ensureState(melissa)
    if not s.starGateSummoned then
        summonMelissaStarGate(melissa, s)
    end
    s.starGateCount = getMelissaStarGateCount(melissa)
    syncMelissaStarGateVisualState(melissa, s)

    local firedAny = false
    local markScale = dmgScale or getMelissaStarMarkDamageScale(melissa, s)
    for gateIndex = 1, s.starGateCount do
        local okFire, firedOrErr = pcall(function()
            return fireMelissaStarGate(melissa, isAlly, targetList, dealDmgFn, teamUnits, gateIndex, s.starGateCount, preferredTarget, markScale)
        end)
        if okFire then
            firedAny = firedAny or firedOrErr == true
        else
            talentLog("[Talent] 摘星星星人 星门发射失败: " .. tostring(firedOrErr))
        end
    end
    if firedAny then
        s.starGateStarMarks = 0
        s.starGateLastAttackComboCount = 0
        local selfMagDmg = (melissa.attrs and melissa.attrs:get(AD.MAG_DMG_BONUS)) or 0
        talentLog(string.format("[Talent] 摘星星星人 星门：基础%.0f 自身魔伤+%.1f%% 共鸣独立×%.2f 受伤×%.2f 神器额外×%.2f 最终%.0f(魔伤+%.1f%% 魔穿+%.1f %d人) 来源=%s",
            s.starGateBaseDamage or 0,
            selfMagDmg,
            s.starGateResonanceMult or 1.0,
            s.starGateTargetTakenMult or 1.0,
            s.starGateArtifactExtraMult or 1.0,
            s.starGateFinalDamage or 0,
            s.starGateResonanceDmgBonus or 0,
            s.starGateResonancePen or 0,
            s.starGateResonanceUnits or 0,
            s.starGateResonanceSourceText or "无"))
    end
    return firedAny
end

--- 摘星星星人 #20：推进常驻星门召唤物状态；星门按固定间隔自动发射
---@param dt number
---@param melissa table
---@param s table
---@param isAlly boolean
---@param targetList table[]
---@param ctx table
---@param teamUnits table[]|nil
local function updateMelissaStarGate(dt, melissa, s, isAlly, targetList, ctx, teamUnits)
    if not melissa or not s or s.heroId ~= 20 then return end
    if melissa.hp <= 0 and not canMelissaStarGatePersistAfterDeath(melissa) then
        s.starGateSummoned = false
        s.starGateCount = 0
        syncMelissaStarGateVisualState(melissa, s)
        return
    end
    if not s.starGateSummoned then
        summonMelissaStarGate(melissa, s)
    else
        s.starGateCount = getMelissaStarGateCount(melissa)
        syncMelissaStarGateVisualState(melissa, s)
    end

    local interval = getMelissaStarGateEffectiveInterval(melissa, s)
    if interval <= 0 then interval = 1.0 end
    s.starGateTimer = (s.starGateTimer or 0) + dt
    local pendingTicks = math.floor(s.starGateTimer / interval)
    local maxTicks = math.min(3, pendingTicks)
    while s.starGateTimer >= interval and maxTicks > 0 do
        maxTicks = maxTicks - 1
        local dealFn = nil
        if ctx and ctx.dealTalentDamage then
            dealFn = function(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
                ctx.dealTalentDamage(melissa, tgt, dmg, isTgtAlly, pfx, clr, projOpts)
            end
        elseif ctx and ctx.dealDamage then
            dealFn = function(tgt, dmg, isTgtAlly, pfx, clr)
                ctx.dealDamage(tgt, dmg, isTgtAlly, pfx, clr, melissa)
            end
        end
        if not dealFn then
            s.starGateTimer = s.starGateTimer - interval
            break
        end
        local okFire, firedOrErr = pcall(function()
            return triggerMelissaStarGates(melissa, isAlly, targetList, dealFn, teamUnits, nil, nil)
        end)
        if not okFire then
            talentLog("[Talent] 摘星星星人 星门 tick failed: " .. tostring(firedOrErr))
            s.starGateTimer = 0
            break
        end
        s.starGateTimer = s.starGateTimer - interval
    end
end

--- 闪电卖鸡 #21：银光触发
---@param attacker table
---@param s table
---@param target table
---@param isAlly boolean
---@param dealDmgFn function
---@param result table|nil 当次攻击公式结果（银光伤害基于本次物理伤害）
local function tryAlexSilverFlash(attacker, s, target, isAlly, dealDmgFn, result)
    if not dealDmgFn or not target or target.hp <= 0 or not attacker.attrs or not result then return end

    local hitVal = attacker.attrs:get(AD.HIT_VALUE)
    local extraProc = math.min(20, math.floor(hitVal / 80) * 2)
    local baseProc = hasAwaken(attacker, 1) and 30 or 25
    local procChance = (baseProc + extraProc) / 100

    if math.random() >= procChance then return end

    -- 设计：额外造成「本次物理伤害 ×150%/180%」的闪电伤害（已含护甲/暴击，不再二次结算护甲）
    local dmgMult = hasAwaken(attacker, 3) and 1.8 or 1.5
    local physDmg = result.totalDamage or 0
    if physDmg <= 0 then return end

    local bonusDmg = math.floor(physDmg * dmgMult + 0.5)
    -- 觉醒7：额外享受魔法伤害加成（MAG_DMG_BONUS）
    if hasAwaken(attacker, 7) then
        local magDmgBonus = attacker.attrs:get(AD.MAG_DMG_BONUS)
        if magDmgBonus ~= 0 then
            bonusDmg = math.floor(bonusDmg * (1 + magDmgBonus / 100) + 0.5)
        end
    end

    if bonusDmg > 0 then
        dealDmgFn(target, bonusDmg, not isAlly, "银光", { 200, 230, 255 }, {
            silverFlashVfx = true,
            instantDamage = true,
        })
    end

    local paralyzeDur = hasAwaken(attacker, 4) and 0.5 or 0.3
    SEM.apply(target, SEM.FROZEN, paralyzeDur, attacker, {})

    if hasAwaken(attacker, 5) then
        s.silverLightProgressBoost = true
    end

    talentLog(string.format("[Talent] 闪电卖鸡 银光 → %s (%.0f伤害, 麻痹%.1fs)",
        target.name or "?", bonusDmg, paralyzeDur))
end

--- 真布诗人 #23：溢出治疗转能量护盾 + 临时护盾
---@param attacker table
---@param target table
---@param result table
---@return number normalGain, number tempGain
local function applyElwynEnergyBlessing(attacker, target, result)
    if not target or not target.attrs or not result then return 0, 0 end

    local overflow = result.overhealAmount
    if overflow == nil then
        overflow = math.max(0, (result.healAmount or 0) - (result.appliedHealAmount or 0))
    end
    overflow = math.floor(overflow + 0.0001)
    if overflow <= 0 then return 0, 0 end

    local convertRate = 1.0
    if hasAwaken(attacker, 2) then convertRate = 1.2 end
    if hasAwaken(attacker, 6) and result.isCrit then
        convertRate = convertRate + 0.5
    end

    local esGain = math.floor(overflow * convertRate + 0.5)
    if esGain <= 0 then return 0, 0 end

    -- final[ENERGY_SHIELD] 可能为浮点；Lua 5.4 的 string.format %d 不接受非整数
    local maxES = math.floor((target.attrs.final[AD.ENERGY_SHIELD] or 0) + 0.0001)
    if maxES <= 0 then return 0, 0 end

    local curES = math.floor(math.min(maxES, target.attrs.energyShield or 0) + 0.0001)
    local room = math.max(0, maxES - curES)
    local toNormal = math.min(room, esGain)
    if toNormal > 0 then
        target.attrs.energyShield = curES + toNormal
    end

    local tempGain = 0
    local remaining = esGain - toNormal
    if remaining > 0 then
        local tempCapPct = 0.50
        if hasAwaken(attacker, 1) then tempCapPct = tempCapPct + 0.10 end
        if hasAwaken(attacker, 5) then tempCapPct = tempCapPct + 0.20 end
        local tempCap = math.floor(maxES * tempCapPct + 0.5)
        local curTemp = math.floor(target.attrs.tempEnergyShield or 0)
        tempGain = math.min(math.max(0, tempCap - curTemp), remaining)
        if tempGain > 0 then
            target.attrs.tempEnergyShield = curTemp + tempGain
            talentLog(string.format("[Talent] 真布诗人 能量祝福：%s 临时护盾+%.0f (上限%.0f)",
                target.name or "?", tempGain, tempCap))
        end
    end

    if toNormal > 0 then
        talentLog(string.format("[Talent] 真布诗人 能量祝福：%s 护盾+%.0f", target.name or "?", toNormal))
    end
    return toNormal, tempGain
end

--- 查找场上存活的真布诗人（觉醒7用）
---@param units table[]
---@return table|nil unit
---@return table|nil state
local function findLivingElwyn(units)
    for _, u in ipairs(units or {}) do
        if u.heroId == 23 and u.hp > 0 then
            return u, getState(u)
        end
    end
    return nil, nil
end

--- 真布诗人觉醒7：护盾清零时触发无敌
---@param ally table
---@param elwyn table
---@param elwynState table
local function tryElwynInvulnOnEsBreak(ally, elwyn, elwynState)
    if not hasAwaken(elwyn, 7) or not ally or ally.hp <= 0 then return end
    if ally._elwynInvulnTimer and ally._elwynInvulnTimer > 0 then return end

    local chance = elwynState.elwynInvulnProcChance or 1.0
    if math.random() >= chance then return end

    ally._elwynInvulnTimer = 2.0
    elwynState.elwynInvulnProcChance = chance * 0.5
    talentLog(string.format("[Talent] 真布诗人 觉醒7：%s 无敌2秒 (下次概率%.0f%%)",
        ally.name or "?", elwynState.elwynInvulnProcChance * 100))
end

-- ======================== 核心 API ========================

--- 重置所有天赋状态（关卡切换时调用）
function TAL.reset()
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
end

--- 小黑子「法术机关枪」：推进攻击计数（普攻与连击共用；连射弹在 onBeforeAttack 中排除）
---@param attacker table
---@param s table
local function tickSeraMachineGunCount(attacker, s)
    if not attacker.attrs then return end
    s.machineGunNormalCount = (s.machineGunNormalCount or 0) + 1
    local interval = 20
    if hasAwaken(attacker, 1) then interval = 18 end
    if hasAwaken(attacker, 5) then interval = 15 end
    if s.machineGunNormalCount % interval == 0 then
        s.machineGunShotsLeft = hasAwaken(attacker, 3) and 12 or 10
        s.machineGunShotTimer = 0
        s.machineGunInBurst = true
        if hasAwaken(attacker, 4) then
            attacker.attrs:addModifier("sera_burst_pen", {
                { key = AD.MAG_PEN, flat = 9999 },
            })
        end
        if hasAwaken(attacker, 6) then
            attacker.attrs:addModifier("sera_burst_speed", {
                { key = AD.ATK_SPEED, flat = 50 },
            })
        end
        talentLog(string.format("[Talent] 小黑子 法术机关枪：第%d次攻击启动连射×%d",
            s.machineGunNormalCount, s.machineGunShotsLeft))
    end
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

    -- #1 大狗嚼 希望之心：HP<70%时物理攻击力+25%
    if heroId == 1 and attacker.attrs then
        local hpPct = attacker.hp / math.max(1, attacker.maxHp)
        if hpPct < 0.7 and not s.hopeBuff then
            local entries = {
                { key = AD.PHYS_ATK, pct = 25 },
            }
            -- 觉醒1: 攻速10%
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
            talentLog("[Talent] 大狗嚼 希望之心：激励(HP=" .. math.floor(hpPct * 100) .. "%)")
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

    -- #3 叮咚鸡 精准箭矢：每3次攻击造成1.5倍伤害
    if heroId == 3 and attacker.attrs then
        s.atkCount = s.atkCount + 1
        -- 觉醒3: 上次精准命中后25%概率继续精准（通过标记实现)
        local forcePrec = s.preciseChain or false
        if s.atkCount % 3 == 0 or forcePrec then
            -- 觉醒1: 倍率1.5→1.8
            local precBonus = hasAwaken(attacker, 1) and 80 or 50
            local entries = {
                { key = AD.DMG_BONUS, flat = precBonus },
            }
            -- 觉醒4: 无视护甲（穿透9999)
            if hasAwaken(attacker, 4) then
                entries[#entries+1] = { key = AD.PHYS_PEN, flat = 9999 }
            end
            -- 觉醒2: 物暴击5%（与精准箭矢独立的永久加成在onBattleStart处理更合理，但这里也可添加）
            attacker.attrs:addModifier("talent_precise", entries)
            s.preciseBuff = true
            s.preciseChain = false
            talentLog("[Talent] 叮咚鸡 精准箭矢：第" .. s.atkCount .. "次攻击，伤害×" .. (1 + precBonus / 100))
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

    -- #7 信光机兵 闪光协议：闪光就绪时连击+200%
    if heroId == 7 and attacker.attrs and s.flashReady then
        local flashCombo = 200
        attacker.attrs:addModifier("talent_flash", {
            { key = AD.COMBO_RATE, flat = flashCombo },
        })
        talentLog("[Talent] 信光机兵 闪光协议：连击概率" .. flashCombo .. "%")
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

--- 熬夜冠军「夜华斩」核心：推进攻击计数，满间隔时斩出多道斩击。
--- 主攻击（onAfterAttack）与连击（onComboAttack）共用同一逻辑，使连击也能推进/触发该天赋。
---@param attacker table
---@param s table 熬夜冠军天赋状态
---@param target table 当前攻击目标（斩击目标不足时的回退目标）
---@param isAlly boolean 攻击方是否为己方
---@param targetList table 被攻击方的单位列表
---@param dealDmgFn function 伤害回调 dealDmgFn(target, dmg, isTargetAlly, prefix, color, opts)
local function runSuhuaNightSlash(attacker, s, target, isAlly, targetList, dealDmgFn)
    -- 觉醒2: 攻击速度+15%（永久，首次添加）
    if hasAwaken(attacker, 2) and not s.awakSuhuaAtkSpd then
        s.awakSuhuaAtkSpd = true
        attacker.attrs:addModifier("awaken_suhua_atkspd", {
            { key = AD.ATK_SPEED, flat = 15 },
        })
    end
    -- 觉醒5: 物理暴击+10%（永久）
    if hasAwaken(attacker, 5) and not s.awakSuhuaCrit then
        s.awakSuhuaCrit = true
        attacker.attrs:addModifier("awaken_suhua_crit", {
            { key = AD.PHYS_CRIT_RATE, flat = 10 },
        })
    end
    -- 觉醒6: 物理暴击伤害+35%（永久）
    if hasAwaken(attacker, 6) and not s.awakSuhuaCritDmg then
        s.awakSuhuaCritDmg = true
        attacker.attrs:addModifier("awaken_suhua_critdmg", {
            { key = AD.CRIT_DMG, flat = 35 },
        })
    end
    s.atkCount = s.atkCount + 1
    -- 觉醒3: 夜华斩间隔缩短为每3攻
    local slashInterval = 4
    if hasAwaken(attacker, 3) then slashInterval = 3 end
    if s.atkCount % slashInterval ~= 0 then return end

    -- 觉醒1: 伤害系数200%→250%
    local slashMult = 2.0
    if hasAwaken(attacker, 1) then slashMult = 2.5 end

    -- 觉醒4: 斩击数从2提升到3
    local slashCount = 2
    if hasAwaken(attacker, 4) then slashCount = 3 end

    -- 收集存活敌人（排除当前目标优先）
    local otherAlive = {}
    for _, u in ipairs(targetList) do
        if u.hp > 0 and u ~= target then
            otherAlive[#otherAlive + 1] = u
        end
    end

    -- 选择斩击目标：优先不同敌人，不够时命中当前目标
    local slashTargets = {}
    local tempOther = {}
    for i, u in ipairs(otherAlive) do tempOther[i] = u end

    for si = 1, slashCount do
        if #tempOther > 0 then
            local ri = math.random(#tempOther)
            slashTargets[si] = tempOther[ri]
            table.remove(tempOther, ri)
        else
            slashTargets[si] = target
        end
    end

    -- 判断是否所有斩击命中同一目标（用于贝塞尔曲线方向）
    local allSame = true
    for si = 2, slashCount do
        if slashTargets[si] ~= slashTargets[1] then allSame = false; break end
    end

    -- 计算斩击伤害（走完整战斗公式：伤害加成、暴击、类型倍率、护甲抗性）
    -- 基础伤害 = physAtk * atkCoeff * slashMult
    local physAtk = attacker.attrs and attacker.attrs:get(AD.PHYS_ATK) or 0
    local atkCoeff = attacker.atkCoeff or 1.0
    local baseSlashDmg = physAtk * atkCoeff * slashMult

    -- 伤害加成%
    local dmgBonusPct = attacker.attrs:get(AD.DMG_BONUS)
        + attacker.attrs:get(AD.PHYS_DMG_BONUS)

    -- 暴击参数
    local critRate = attacker.attrs:get(AD.CRIT_RATE)
        + attacker.attrs:get(AD.PHYS_CRIT_RATE)
    local critDmg = attacker.attrs:get(AD.CRIT_DMG)
        + attacker.attrs:get(AD.PHYS_CRIT_DMG)

    -- 类型倍率（熬夜冠军 ATK_SLASH）
    local atkType = attacker.atkType or AD.ATK_SLASH

    -- 发射斩击（不检测hp > 0，即使目标被普攻击杀也发射）
    local sides = { 1, -1, 0.5 }  -- 贝塞尔方向：左、右、微偏
    for si = 1, slashCount do
        local st = slashTargets[si]

        -- 针对每个目标独立计算护甲抗性和类型倍率
        local armorType = st.armorType or AD.ARMOR_LEATHER
        local effectiveArmor = math.max(0,
            (st.attrs and st.attrs:get(AD.PHYS_ARMOR) or 0)
            - attacker.attrs:get(AD.PHYS_PEN))
        local resistance = CF.armorToResistance(effectiveArmor)
        local typeMult = AD.getTypeMult(atkType, armorType)

        -- 伤害计算流水线
        local dmg = baseSlashDmg
        dmg = dmg * (1 + dmgBonusPct / 100)

        -- 暴击（每道斩击独立判定）
        local isCrit, critMultiplier = CF.rollCrit(critRate, critDmg)
        if isCrit then
            dmg = dmg * critMultiplier
        end

        dmg = dmg * typeMult
        if attacker.attrs.artifactExtraDamageMult then
            dmg = dmg * attacker.attrs.artifactExtraDamageMult
        end
        dmg = CF.applyFinalDamageBonus(attacker.attrs, dmg)
        dmg = dmg * (1 - resistance)
        dmg = math.max(1, math.floor(dmg + 0.5))

        local opts = {
            isCrit = isCrit,
            statCategory = "physical",
            critEligible = true,
        }
        if allSame then
            opts.bezierSide = sides[si] or (si % 2 == 1 and 1 or -1)
        end
        dealDmgFn(st, dmg, not isAlly, "夜华斩", { 255, 50, 80 }, opts)
    end

    talentLog("[Talent] 熬夜冠军 夜华斩：" .. slashCount .. "道斩击(基础=" .. math.floor(baseSlashDmg) .. ")")
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
    local s = getState(attacker)
    if not s then return end
    local heroId = s.heroId

    dealDmgFn = wrapDealDmgForLuoxing(attacker, dealDmgFn)

    -- === 原有英雄天赋 ===

    -- #20 摘星星星人 星之守护：星门固定周期发射；连击产生的星痕在星门发射时结算
    if heroId == 20 and result and result.comboCount and result.comboCount > 0 then
        addMelissaStarMarks(attacker, result.comboCount)
    end

    -- 跳过miss的后续效果
    if result and result.isMiss then return end

    -- #1 大狗嚼 觉醒4: 希望之心激活时，吸取造成伤害的10%回复HP
    if heroId == 1 and s.hopeBuff and hasAwaken(attacker, 4) then
        if result and result.totalDamage and result.totalDamage > 0 and attacker.attrs then
            local healAmt = math.floor(result.totalDamage * 0.10 + 0.5)
            if healAmt > 0 then
                attacker.attrs:heal(healAmt)
                attacker.hp = attacker.attrs:get(AD.HP)
                if attacker.hp > attacker.maxHp then attacker.hp = attacker.maxHp end
                talentLog("[Talent] 大狗嚼 觉醒4: 吸血 " .. healAmt .. " HP (伤害=" .. result.totalDamage .. ")")
            end
        end
    end

    -- #3 叮咚鸡 精准箭矢：移除临时buff + 觉醒效果
    if heroId == 3 and s.preciseBuff then
        -- 觉醒5: 精准箭矢造成暴击时额外50%伤害
        if hasAwaken(attacker, 5) and result and result.isCrit and dealDmgFn and target.hp > 0 then
            local bonusDmg = math.floor((result.totalDamage or 0) * 0.50 + 0.5)
            if bonusDmg > 0 then
                dealDmgFn(target, bonusDmg, not isAlly, "精准暴击 ", { 255, 200, 50 })
            end
        end
        -- 觉醒3: 精准命中后25%概率下次攻击也是精准
        if hasAwaken(attacker, 3) then
            if math.random() < 0.25 then
                s.preciseChain = true
                talentLog("[Talent] 叮咚鸡 觉醒3：精准连锁触发")
            end
        end
        -- 觉醒7: 精准箭矢散射3个敌人
        if hasAwaken(attacker, 7) and dealDmgFn and targetList then
            local scatterDmg = result and result.totalDamage or 0
            if scatterDmg > 0 then
                local otherAlive = {}
                for _, u in ipairs(targetList) do
                    if u.hp > 0 and u ~= target then
                        otherAlive[#otherAlive + 1] = u
                    end
                end
                -- 散射到最多2个其他目标（加上原目标共3个）
                local scatterCount = math.min(2, #otherAlive)
                for si = 1, scatterCount do
                    local ri = math.random(#otherAlive)
                    local st = otherAlive[ri]
                    if st.hp > 0 then
                        dealDmgFn(st, scatterDmg, not isAlly, "散射 ", { 200, 255, 200 })
                    end
                    table.remove(otherAlive, ri)
                end
                if scatterCount > 0 then
                    talentLog("[Talent] 叮咚鸡 觉醒7：散射命中 " .. scatterCount .. " 个额外目标")
                end
            end
        end
        attacker.attrs:removeModifier("talent_precise")
        s.preciseBuff = false
    end

    -- #7 信光机兵 闪光协议：消费闪避/ 计数 + 觉醒效果
    if heroId == 7 and attacker.attrs then
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
            -- 觉醒7: 闪光消耗时移除闪光专属加成
            attacker.attrs:removeModifier("awaken_flash7_boost")
            s.flashReady = false
            s.atkCount = 0
        else
            s.atkCount = s.atkCount + 1
            -- 觉醒3: 闪光协议间隔缩短为每3秒
            local flashInterval = 4
            if hasAwaken(attacker, 3) then flashInterval = 3 end
            if s.atkCount % flashInterval == 0 then
                s.flashReady = true
                -- 觉醒7: 闪光专属模式，连击100%、连击增伤30%
                if hasAwaken(attacker, 7) then
                    attacker.attrs:removeModifier("awaken_flash_exclusive")
                    -- 非闪光状态清除连击概率（连击只能由闪光触发）
                end
                talentLog("[Talent] 信光机兵 闪光协议：下次攻击连击概率200% (每" .. flashInterval .. "秒)")
            end
        end

        -- 觉醒7: 闪光专属模式处理 - 非闪光时禁用普通连击
        if hasAwaken(attacker, 7) then
            if not s.flashReady then
                -- 非闪光就绪状态，移除所有连击概率
                if not s.awakFlashExclActive then
                    s.awakFlashExclActive = true
                    attacker.attrs:addModifier("awaken_flash_exclusive", {
                        { key = AD.COMBO_RATE, flat = -999 },
                    })
                end
            else
                -- 闪光就绪，恢复连击应用额外加成
                if s.awakFlashExclActive then
                    s.awakFlashExclActive = false
                    attacker.attrs:removeModifier("awaken_flash_exclusive")
                end
                -- 闪光时额外连击100%、连击增伤30%（叠加在talent_flash上）
                attacker.attrs:removeModifier("awaken_flash7_boost")
                attacker.attrs:addModifier("awaken_flash7_boost", {
                    { key = AD.COMBO_RATE, flat = 100 },
                    { key = AD.COMBO_DMG_UP, flat = 30 },
                })
            end
        end
    end

    -- #5 叠甲怪 战斗征服：叠加征服层数
    if heroId == 5 and attacker.attrs then
        -- 觉醒2: 最大层数5 (15→20)
        local maxConquer = 15
        if hasAwaken(attacker, 2) then maxConquer = 20 end
        s.conquerStacks = math.min(maxConquer, s.conquerStacks + 1)
        attacker.attrs:removeModifier("talent_conquer")
        if s.conquerStacks > 0 then
            local entries = {
                { key = AD.PHYS_ATK, pct = s.conquerStacks * 2 },
            }
            -- 觉醒1: 每层+1%攻速
            if hasAwaken(attacker, 1) then
                entries[#entries+1] = { key = AD.ATK_SPEED, flat = s.conquerStacks * 1 }
            end
            -- 觉醒3: 每层+0.5闪避
            if hasAwaken(attacker, 3) then
                entries[#entries+1] = { key = AD.DODGE, flat = s.conquerStacks * 0.5 }
            end
            -- 觉醒4: 每层+1%连击概率
            if hasAwaken(attacker, 4) then
                entries[#entries+1] = { key = AD.COMBO_RATE, flat = s.conquerStacks * 1 }
            end
            -- 觉醒5: 每层+1%连击增伤
            if hasAwaken(attacker, 5) then
                entries[#entries+1] = { key = AD.COMBO_DMG_UP, flat = s.conquerStacks * 1 }
            end
            -- 觉醒6: 每层+1%物理伤害加成
            if hasAwaken(attacker, 6) then
                entries[#entries+1] = { key = AD.PHYS_DMG_BONUS, flat = s.conquerStacks * 1 }
            end
            -- 觉醒7: 满层时所有效果提速0%
            if hasAwaken(attacker, 7) and s.conquerStacks >= maxConquer then
                if not s.conquerMaxBoostApplied then
                    s.conquerMaxBoostApplied = true
                    -- →.5倍所有flat/pct
                    for _, e in ipairs(entries) do
                        if e.flat then e.flat = math.floor(e.flat * 1.5 + 0.5) end
                        if e.pct then e.pct = math.floor(e.pct * 1.5 + 0.5) end
                    end
                    talentLog("[Talent] 叠甲怪 征服觉醒7：满层效果50%!")
                elseif s.conquerMaxBoostApplied then
                    -- 已满层且已应用50%提升，保留
                    for _, e in ipairs(entries) do
                        if e.flat then e.flat = math.floor(e.flat * 1.5 + 0.5) end
                        if e.pct then e.pct = math.floor(e.pct * 1.5 + 0.5) end
                    end
                end
            end
            attacker.attrs:addModifier("talent_conquer", entries)
        end
        if s.conquerStacks % 5 == 0 or s.conquerStacks == 1 then
            talentLog("[Talent] 叠甲怪 征服×" .. s.conquerStacks .. "/" .. maxConquer .. " (物攻+" .. (s.conquerStacks * 2) .. "%)")
        end
    end

    -- === 转职天赋: 攻击后（伤害类） ===

    if result and result.category ~= "healing" and not result.isMiss then
        -- #8 愤怒的小雀觉醒: 攻击标记目标的战斗效果（需在伤害计算后处理）
        if heroId == 8 and attacker.attrs then
            local isMarked = SEM.has(target, SEM.MARKED)
            -- 觉醒3: 攻击标记目标暴击+15%（攻击后移除临时modifier)
            if hasAwaken(attacker, 3) then
                attacker.attrs:removeModifier("awaken_mark_crit")
            end
            -- 觉醒5: 暴击伤害+30%（攻击后移除临时modifier)
            if hasAwaken(attacker, 5) then
                attacker.attrs:removeModifier("awaken_mark_critdmg")
            end
            -- 觉醒6: 首次攻击标记目标必暴（记录已消费 + 移除modifier)
            if hasAwaken(attacker, 6) and isMarked and not s.markFirstHitCrit[target] then
                s.markFirstHitCrit[target] = true  -- 标记已消费首次必暴）
            end
            attacker.attrs:removeModifier("awaken_mark_first_crit")
            -- 觉醒7: 标记目标HP<15%时直接斩杀
            if hasAwaken(attacker, 7) and isMarked and target.hp > 0 then
                local targetHpPct = target.hp / math.max(1, target.maxHp)
                if targetHpPct < 0.15 then
                    if dealDmgFn then
                        dealDmgFn(target, target.hp, not isAlly, "斩杀 ", { 255, 0, 50 })
                        talentLog("[Talent] 愤怒的小雀 觉醒7：斩杀 " .. target.name .. "!")
                    end
                    -- 斩杀后立即转移标记（不依赖延迟的 onEnemyDeath）
                    if targetList then
                        local aliveEnemies = getAliveEnemies(targetList)
                        if #aliveEnemies > 0 then
                            local newTarget = aliveEnemies[math.random(#aliveEnemies)]
                            applyAyaneMark(attacker, newTarget, targetList)
                            talentLog("[Talent] 愤怒的小雀 觉醒7: 斩杀后标记转移→" .. (newTarget.name or "?"))
                        else
                            clearAyaneMarks(targetList)
                        end
                    end
                end
            end
        end

        -- #14 内鬼 暴击精通觉醒：onAfterAttack效果
        if heroId == 14 and attacker.attrs then
            -- 觉醒4: 首次攻击新目标必暴（消费记录 + 移除modifier)
            if hasAwaken(attacker, 4) then
                if not s.firstHitTargets[target] then
                    s.firstHitTargets[target] = true
                end
                attacker.attrs:removeModifier("awaken_firsthit_crit")
            end
            -- 觉醒7: 超暴击（暴击率溢出→超暴击率，触发后再乘一次暴击伤害）
            if hasAwaken(attacker, 7) and result and result.isCrit then
                tryYouyeSuperCrit(attacker, target, result, isAlly, dealDmgFn)
            end
        end

        -- #2 黄桃龙 火焰精通：附加燃烧
        if heroId == 2 and attacker.attrs and target.hp > 0 then
            local magAtk = attacker.attrs:get(AD.MAG_ATK) or 0
            local burnMult = 0.2
            -- 觉醒1: 燃烧伤害+10%
            if hasAwaken(attacker, 1) then burnMult = burnMult + 0.02 end
            -- 觉醒5: 燃烧伤害+25%
            if hasAwaken(attacker, 5) then burnMult = burnMult + 0.05 end
            local dps = math.floor(magAtk * burnMult + 0.5)
            if dps > 0 then
                local burnData = { dps = dps }
                -- 觉醒3: 燃烧可造成魔法暴击
                if hasAwaken(attacker, 3) then
                    burnData.canCrit = true
                    local baseCritRate = attacker.attrs:get(AD.MAG_CRIT_RATE) or 0
                    local baseCritDmg  = attacker.attrs:get(AD.MAG_CRIT_DMG) or 50
                    -- 觉醒6: 自带+10%魔法暴击率与+50%魔法暴击伤害
                    if hasAwaken(attacker, 6) then
                        baseCritRate = baseCritRate + 10
                        baseCritDmg  = baseCritDmg + 50
                    end
                    burnData.critRate = baseCritRate
                    burnData.critDmg  = baseCritDmg
                end
                -- 觉醒7: 可叠加燃烧，最多5层
                if hasAwaken(attacker, 7) then
                    burnData.stackable = true
                    burnData.maxStacks = 3
                end
                SEM.apply(target, SEM.BURNING, 2.0, attacker, burnData)
            end
            -- 觉醒2: 攻击燃烧中的敌人立即结算一次燃烧伤害
            if hasAwaken(attacker, 2) and SEM.has(target, SEM.BURNING) then
                local burnEffect = SEM.get(target, SEM.BURNING)
                if burnEffect and burnEffect.data.dps and burnEffect.data.dps > 0 and dealDmgFn then
                    local instantDmg = math.floor(burnEffect.data.dps + 0.5)
                    dealDmgFn(target, instantDmg, not isAlly, "燃烧结算 ", { 255, 120, 30 })
                end
            end
            -- 觉醒4: 2+敌人处于燃烧时魔法攻击加成15%
            if hasAwaken(attacker, 4) then
                attacker.attrs:removeModifier("awaken_burn_bonus")
                local burnCount = SEM.countUnitsWithEffect(targetList, SEM.BURNING)
                if burnCount >= 2 then
                    attacker.attrs:addModifier("awaken_burn_bonus", {
                        { key = AD.MAG_ATK_BONUS, flat = 15 },
                    })
                end
            end
        end

        -- #6 阿姨压 闪电精通：附加感电
        if heroId == 6 and target.hp > 0 then
            -- 觉醒1: 魔法伤害加成+10%（永久，首次添加成
            if hasAwaken(attacker, 1) and not s.awakLunaDmgApplied then
                s.awakLunaDmgApplied = true
                attacker.attrs:addModifier("awaken_luna_dmg", {
                    { key = AD.MAG_DMG_BONUS, flat = 10 },
                })
            end
            -- 觉醒2: 感电增伤30%
            local shockMult = 0.20
            if hasAwaken(attacker, 2) then shockMult = 0.30 end
            -- 觉醒3: 感电持续3秒
            local shockDur = 2.0
            if hasAwaken(attacker, 3) then shockDur = 3.0 end
            local shockData = { mult = shockMult }
            -- 觉醒4: 感电额外-105能量护盾
            if hasAwaken(attacker, 4) then shockData.magArmorDebuff = 105 end
            -- 觉醒5: 感电目标攻速10%
            if hasAwaken(attacker, 5) then shockData.atkSpeedDebuff = 10 end
            -- 觉醒7: 感电敌人额外10%受暴击概率
            if hasAwaken(attacker, 7) then shockData.critVuln = 10 end
            SEM.apply(target, SEM.SHOCKED, shockDur, attacker, shockData)
            -- 应用debuff到目标属性
            if target.attrs then
                target.attrs:removeModifier("awaken_shock_debuff_" .. tostring(target))
                local debuffEntries = {}
                if shockData.magArmorDebuff then
                    debuffEntries[#debuffEntries+1] = { key = AD.MAG_ARMOR, flat = -shockData.magArmorDebuff }
                end
                if shockData.atkSpeedDebuff then
                    debuffEntries[#debuffEntries+1] = { key = AD.ATK_SPEED, flat = -shockData.atkSpeedDebuff }
                end
                if #debuffEntries > 0 then
                    target.attrs:addModifier("awaken_shock_debuff_" .. tostring(target), debuffEntries)
                end
            end
            -- 觉醒6: 每有一个敌人处于感电，魔攻加成+5%
            if hasAwaken(attacker, 6) and targetList then
                attacker.attrs:removeModifier("awaken_luna_shock_bonus")
                local shockCount = SEM.countUnitsWithEffect(targetList, SEM.SHOCKED)
                if shockCount > 0 then
                    attacker.attrs:addModifier("awaken_luna_shock_bonus", {
                        { key = AD.MAG_ATK_BONUS, flat = shockCount * 5 },
                    })
                end
            end
        end

        -- #12 雪皇 冰霜精通：25%概率附加冰冻1.5秒 + 觉醒
        if heroId == 12 and target.hp > 0 then
            -- 觉醒1: 概率25%→35%  觉醒3: 概率→50%
            local freezeChance = 0.25
            if hasAwaken(attacker, 1) then freezeChance = 0.35 end
            if hasAwaken(attacker, 3) then freezeChance = 0.50 end
            -- 觉醒4: 持续时间+0.5秒
            local freezeDur = 1.5
            if hasAwaken(attacker, 4) then freezeDur = 2.0 end
            -- 内置CD：目标被冰冻后，需待其解冻并再经过 FREEZE_INTERNAL_CD 秒才能被本天赋再次冰冻，避免无限冰冻锁怪
            local FREEZE_INTERNAL_CD = 0.02
            local onFreezeCD = (s.freezeCD[target] or 0) > 0
            if not onFreezeCD and math.random() < freezeChance then
                -- 觉醒5: 首次冰冻额外+2秒
                local actualDur = freezeDur
                if hasAwaken(attacker, 5) and not s.firstFreezeUsed[target] then
                    s.firstFreezeUsed[target] = true
                    actualDur = actualDur + 2.0
                    talentLog("[Talent] 雪皇 觉醒5: 首次冰冻 " .. target.name .. " 额外+2s")
                end
                -- 觉醒2: 冰冻目标额外受到20%伤害
                local frozenData = {}
                if hasAwaken(attacker, 2) then
                    frozenData.extraDmgMult = 0.20
                end
                SEM.apply(target, SEM.FROZEN, actualDur, attacker, frozenData)
                -- 触发内置CD = 本次冰冻时长 + 固定CD（解冻后还需等待 FREEZE_INTERNAL_CD 秒才能再次冰冻）
                s.freezeCD[target] = actualDur + FREEZE_INTERNAL_CD
                -- 觉醒7: 每冰冻一名敌人，魔攻加成+3%，最多10层
                if hasAwaken(attacker, 7) then
                    s.freezeAtkStacks = math.min(20, s.freezeAtkStacks + 1)
                    attacker.attrs:removeModifier("awaken_freeze_matk")
                    attacker.attrs:addModifier("awaken_freeze_matk", {
                        { key = AD.MAG_ATK_BONUS, flat = s.freezeAtkStacks * 3 },
                    })
                    talentLog("[Talent] 雪皇 觉醒7: 冰冻叠层×" .. s.freezeAtkStacks .. " (魔攻+" .. (s.freezeAtkStacks * 3) .. "%)")
                end
            end
        end

        -- #13 弹弹弹弹射箭矢：弹2次到其他敌人 + 觉醒
        if heroId == 13 and dealDmgFn and targetList then
            -- 觉醒1: 攻速10%（永久，首次添加成
            if hasAwaken(attacker, 1) and not s.awakRosaAtkSpd then
                s.awakRosaAtkSpd = true
                attacker.attrs:addModifier("awaken_rosa_atkspd", {
                    { key = AD.ATK_SPEED, flat = 10 },
                })
            end
            -- 觉醒2: 物理穿透+10 已在 HeroConfig.createHero 中作为固定属性生效，确保首次伤害也吃到加成。
            -- 这里不再运行时补加，避免第二次攻击后重复计算。
            -- 觉醒5: 物理攻击加成+25%（永久）
            if hasAwaken(attacker, 5) and not s.awakRosaPhysAtk then
                s.awakRosaPhysAtk = true
                attacker.attrs:addModifier("awaken_rosa_physatk", {
                    { key = AD.PHYS_ATK_BONUS, flat = 25 },
                })
            end
            -- 觉醒6: 攻速25%（永久）
            if hasAwaken(attacker, 6) and not s.awakRosaAtkSpd2 then
                s.awakRosaAtkSpd2 = true
                attacker.attrs:addModifier("awaken_rosa_atkspd2", {
                    { key = AD.ATK_SPEED, flat = 25 },
                })
            end

            -- 觉醒3: 弹射次数+1（共2次）  觉醒7: 弹射3次,可重复弹射
            local bounceCount = 1
            if hasAwaken(attacker, 3) then bounceCount = 2 end
            if hasAwaken(attacker, 7) then bounceCount = 3 end

            local baseDmg = result.totalDamage or 0
            local allowRepeatBounce = hasAwaken(attacker, 7)

            local hitTargets = { [target] = true }
            s.rosaBounceGen = (s.rosaBounceGen or 0) + 1
            local bounceGen = s.rosaBounceGen

            -- 每跳必须弹向与上一跳不同的敌人；无觉醒7时不可重复已弹过的敌人
            local function pickBounceTarget(chainFrom)
                local candidates = {}
                for _, u in ipairs(targetList) do
                    if u.hp > 0 and u ~= chainFrom then
                        if not allowRepeatBounce and hitTargets[u] then
                            -- skip
                        else
                            candidates[#candidates + 1] = u
                        end
                    end
                end
                if #candidates == 0 then return nil end
                return candidates[math.random(#candidates)]
            end

            -- 连续弹射：上一箭命中后再发下一箭；无新目标则结束
            local function fireBounce(bi, chainFrom)
                if bounceGen ~= s.rosaBounceGen then return end
                if bi > bounceCount then return end

                local dmgMult = 0.5
                if hasAwaken(attacker, 4) then
                    dmgMult = 0.5 + bi * 0.15
                end
                local bounceDmg = math.floor(baseDmg * dmgMult + 0.5)
                if bounceDmg <= 0 then return end

                local bounceTarget = pickBounceTarget(chainFrom)
                if not bounceTarget then return end

                hitTargets[bounceTarget] = true
                dealDmgFn(bounceTarget, bounceDmg, not isAlly, "弹射 ", { 180, 220, 255 }, {
                    bounceFromUnit = chainFrom,
                    target = bounceTarget,
                    isRicochet = true,
                    isCrit = result.isCrit,
                    statCategory = result.category or "physical",
                    critEligible = false,
                    onProjectileLand = function()
                        if bounceGen ~= s.rosaBounceGen then return end
                        fireBounce(bi + 1, bounceTarget)
                    end,
                })
            end

            fireBounce(1, target)
        end

        -- #11 熬夜冠军 夜华斩：每攻速次斩出2道斩击
        -- 斩击优先命中不同敌人，没有多余敌人时可命中同一敌人
        -- 造成物理攻击*100%的斩击伤害，投射物使用贝塞尔曲线
        if heroId == 11 and dealDmgFn and targetList then
            runSuhuaNightSlash(attacker, s, target, isAlly, targetList, dealDmgFn)
        end

        -- #16 万剑归宗 灵月飞剑：累计实际造成伤害（含护盾吸收、暴击与各类增伤）
        if heroId == 16 and result and not result.isMiss and result.category ~= "healing" then
            addLuoxingWindowDamage(attacker, getLuoxingAccumAmount(result, 0), nil, nil)
        end

        -- #20 摘星星星人 星之守护：星门已改为固定间隔自动发射；其他魔法角色不再立即触发星门，避免回到攻速/连击协同

        -- #21 闪电卖鸡 银光（每轮攻击仅判定一次，避免多目标重复触发）
        if heroId == 21 and dealDmgFn and target and not result.isMiss and result.category ~= "healing" then
            if not s.silverFlashChecked then
                s.silverFlashChecked = true
                tryAlexSilverFlash(attacker, s, target, isAlly, dealDmgFn, result)
            end
        end

        -- #22 小黑子 法术机关枪：仅连射弹触发过载叠层 + 觉醒7全体（触发连射的那次普攻不算连射）
        if heroId == 22 and s.lastAttackWasBurst and result and not result.isMiss and result.category ~= "healing" then
            if hasAwaken(attacker, 6) and attacker.attrs then
                s.machineGunOverloadStacks = math.min(10, (s.machineGunOverloadStacks or 0) + 1)
                attacker.attrs:removeModifier("sera_overload")
                attacker.attrs:addModifier("sera_overload", {
                    { key = AD.MAG_ATK_BONUS, flat = s.machineGunOverloadStacks * 2 },
                })
            end
            if hasAwaken(attacker, 7) and dealDmgFn and targetList and math.random() < 0.20 then
                local aoeDmg = result.totalDamage or 0
                if aoeDmg > 0 then
                    for _, u in ipairs(targetList) do
                        if u.hp > 0 and u ~= target then
                            dealDmgFn(u, aoeDmg, not isAlly, "连射 ", { 180, 220, 255 })
                        end
                    end
                    talentLog("[Talent] 小黑子 觉醒7：连射全体")
                end
            end
        end

        -- #4 接化发掌门 觉醒7: 释放累积的格挡伤害作为固定伤害
        if heroId == 4 and hasAwaken(attacker, 7) and s.blockAbsorbedDmg > 0 then
            local bonusDmg = s.blockAbsorbedDmg
            s.blockAbsorbedDmg = 0
            if bonusDmg > 0 and target.hp > 0 and dealDmgFn then
                dealDmgFn(target, bonusDmg, not isAlly, "格挡反伤 ", { 200, 200, 255 })
                talentLog("[Talent] 接化发掌门 觉醒7: 释放格挡伤害 " .. bonusDmg)
            end
        end

        -- 106 奥术飞弹: 35%概率对随机敌人发射飞弹（魔攻*100%暗影伤害)
        if hasAdv(attacker, "adv_106_arcane_missile") and dealDmgFn and targetList then
            local missileChance = 0.35
            local missileMult = 1.0
            local has211 = hasAdv(attacker, "adv_211_arcane_wisdom")
            local has212 = hasAdv(attacker, "adv_212_arcane_surge")

            -- 211 奥术智慧: 概率→50%
            if has211 then missileChance = 0.50 end
            -- 212 奥能充盈: 伤害→魔攻×200%
            if has212 then missileMult = 2.0 end

            -- 211: 目标<20% HP时必定触发
            local targetHpPct = target.hp / math.max(1, target.maxHp)
            if has211 and targetHpPct < 0.20 then
                missileChance = 1.0
            end

            if math.random() < missileChance then
                -- 211: 优先攻击HP%最低的敌人；默认随机存活敌人
                local missileTarget = target
                if has211 then
                    local lowest, lowestPct = nil, 2.0
                    for _, u in ipairs(targetList) do
                        if u.hp > 0 then
                            local pct = u.hp / math.max(1, u.maxHp)
                            if pct < lowestPct then
                                lowestPct = pct
                                lowest = u
                            end
                        end
                    end
                    if lowest then missileTarget = lowest end
                else
                    local alive = getAliveEnemies(targetList)
                    if #alive > 0 then
                        missileTarget = alive[math.random(#alive)]
                    end
                end

                if missileTarget and missileTarget.hp > 0 and attacker.attrs then
                    local magAtk = attacker.attrs:get(AD.MAG_ATK) or 0
                    local atkCoeff = attacker.atkCoeff or attacker.attrs.atkCoeff or 1.0
                    local baseDmg = magAtk * atkCoeff * missileMult

                    local critRate = attacker.attrs:get(AD.CRIT_RATE) + attacker.attrs:get(AD.MAG_CRIT_RATE)
                    local critDmg  = attacker.attrs:get(AD.CRIT_DMG)  + attacker.attrs:get(AD.MAG_CRIT_DMG)
                    local shockedEffect = SEM.get(missileTarget, SEM.SHOCKED)
                    if shockedEffect and shockedEffect.data and shockedEffect.data.critVuln then
                        critRate = critRate + shockedEffect.data.critVuln
                    end

                    local missileDmg, missileCrit = calcTalentFixedDamage(attacker, missileTarget, baseDmg, {
                        atkType  = AD.ATK_SHADOW,
                        critRate = critRate,
                        critDmg  = critDmg,
                    })

                    -- 遗物/副本等来自触发普攻的增伤（与 BattleCombat._talentDmgMult 一致）
                    if result._talentDmgMult and result._talentDmgMult > 1.0 then
                        missileDmg = math.floor(missileDmg * result._talentDmgMult + 0.5)
                    end

                    -- 211: <40% HP 伤害翻倍
                    if has211 then
                        local mtPct = missileTarget.hp / math.max(1, missileTarget.maxHp)
                        if mtPct < 0.40 then
                            missileDmg = missileDmg * 2
                        end
                    end

                    local semMult = SEM.getDamageTakenMult(missileTarget)
                    if semMult and semMult ~= 1.0 then
                        missileDmg = math.floor(missileDmg * semMult + 0.5)
                    end

                    local missilePrefix = missileCrit and "暴击飞弹 " or "飞弹 "
                    local missileColor  = missileCrit and { 255, 180, 50 } or { 160, 100, 255 }

                    if missileDmg > 0 then
                        dealDmgFn(missileTarget, missileDmg, not isAlly, missilePrefix, missileColor, {
                            talentProjKey = "EF_ZY_106",
                            statCategory = "magical",
                            isCrit = missileCrit,
                            critEligible = true,
                        })

                        -- 212 奥能充盈: 30%概率爆炸AOE
                        if has212 and math.random() < 0.30 then
                            local mtIdx = 0
                            for i, u in ipairs(targetList) do
                                if u == missileTarget then mtIdx = i; break end
                            end
                            local explosionPrefix = missileCrit and "暴击爆炸 " or "飞弹爆炸 "
                            local explosionColor  = missileCrit and { 255, 140, 50 } or { 200, 80, 255 }
                            for offset = -1, 1 do
                                local idx = mtIdx + offset
                                if idx >= 1 and idx <= #targetList then
                                    local u = targetList[idx]
                                    if u ~= missileTarget and u.hp > 0 then
                                        dealDmgFn(u, missileDmg, not isAlly, explosionPrefix, explosionColor, {
                                            talentProjKey = "EF_ZY_224",
                                            statCategory = "magical",
                                            isCrit = missileCrit,
                                            critEligible = false,
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 104 决斗者 锁定目标 + 伤害加成+5%
        if hasAdv(attacker, "adv_104_duelist") then
            if s.duelTarget ~= target then
                -- 切换目标
                s.duelTarget = target
                s.duelCount = 1
            else
                s.duelCount = s.duelCount + 1
            end
        end

        -- 208 幻影剑斩: 攻击同一目标叠加[连击]
        if hasAdv(attacker, "adv_208_phantom_slash") and attacker.attrs then
            attacker.attrs:removeModifier("talent_phantom")
            if s.phantomTarget == target then
                s.phantomStacks = math.min(10, s.phantomStacks + 1)
            else
                -- 切换目标失去2层
                s.phantomStacks = math.max(0, s.phantomStacks - 2)
                s.phantomTarget = target
            end
            if s.phantomStacks > 0 then
                attacker.attrs:addModifier("talent_phantom", {
                    { key = AD.COMBO_RATE, flat = s.phantomStacks * 10 },
                    { key = AD.COMBO_DMG_UP, flat = s.phantomStacks * 2 },
                })
            end
        end

        -- 108 阵前提速 每次攻击消耗1层
        if hasAdv(attacker, "adv_108_battle_haste") and s.hasteStacks > 0 then
            s.hasteStacks = s.hasteStacks - 1
            attacker.attrs:removeModifier("talent_haste")
            if s.hasteStacks > 0 then
                attacker.attrs:addModifier("talent_haste", {
                    { key = AD.ATK_SPEED, flat = s.hasteStacks * 8 },
                })
            end
            -- 215 鹰眼: 更新穿透
            if hasAdv(attacker, "adv_215_eagle_eye") then
                attacker.attrs:removeModifier("talent_eagle_pen")
                if s.hasteStacks > 0 then
                    attacker.attrs:addModifier("talent_eagle_pen", {
                        { key = AD.PHYS_PEN, flat = s.hasteStacks * 6 },
                    })
                end
            end
        end

        -- 110 影袭: 消费影袭buff
        if hasAdv(attacker, "adv_110_shadow_strike") and s.shadowStrikeBuff then
            attacker.attrs:removeModifier("talent_shadow_strike")
            s.shadowStrikeBuff = false
            talentLog("[Talent] 影袭: 伤害加成已消耗")
        end

        -- 219 致命之刃: 暴击时进度条+100%, 暴击伤害+25% (每轮攻击进度只能触发一次）
        if hasAdv(attacker, "adv_219_lethal_blade") and result.isCrit and not s.lethalBladeUsed then
            attacker.atkProgress = math.min(1.0, (attacker.atkProgress or 0) + 1.0)
            s.lethalBladeUsed = true
            s.lethalBladeSkipReset = true  -- 下次免费攻击，onBeforeAttack 不重置
            talentLog("[Talent] 致命之刃: 暴击→进度条+100% (本轮已消费")
        end

        -- 210 蚀骨诅咒 带诅咒的敌人受伤时额外暗影伤害(3秒CD)
        if isAlly and dealDmgFn and target.hp > 0 and SEM.has(target, SEM.VULNERABLE) then
            -- 查找拥有210天赋的己方单位
            for _, ally in ipairs(TAL_BCS.bAllies) do
                if hasAdv(ally, "adv_210_corrosion_curse") and ally.hp > 0 then
                    local as = getState(ally)
                    if as then
                        local cd = as.corrosionCds[target] or 0
                        if cd <= 0 then
                            local magAtk = ally.attrs and ally.attrs:get(AD.MAG_ATK) or 0
                            local corDmg = math.floor(magAtk * 0.8 + 0.5)
                            if corDmg > 0 then
                                dealDmgFn(target, corDmg, not isAlly, "蚀骨", { 180, 50, 220 })
                                as.corrosionCds[target] = 1.0  -- 1秒CD
                            end
                        end
                    end
                    break -- 只触发一次）10
                end
            end
        end

        -- 214 林间之眼: 普通攻击获得[暴击提升]
        if hasAdv(attacker, "adv_214_forest_eye") and attacker.attrs then
            s.critBoostStacks = math.min(20, s.critBoostStacks + 1)
            s.critBoostTimer = 10.0
            attacker.attrs:removeModifier("talent_crit_boost")
            attacker.attrs:addModifier("talent_crit_boost", {
                { key = AD.CRIT_DMG, flat = s.critBoostStacks * 8 },
            })
        end
    end

    -- === 转职天赋: 攻击后（治疗类） ===

    if result and result.category == "healing" then
        -- [DIAG-ADV] 诊断：转职天赋检查（牧师111/112效果不生效排查）
        if heroId == 9 or heroId == 15 then
            local tids = attacker.advTalentIds
            local tidStr = tids and table.concat(tids, ",") or "NIL"
            local abStr = "nil"
            if attacker.advBranch then
                abStr = string.format("{first=%s,second=%s}",
                    tostring(attacker.advBranch.first), tostring(attacker.advBranch.second))
            end
            print(string.format(
                "[DIAG-ADV] HEAL_CHECK healer=%s(id%s) advTalentIds=[%s] advBranch=%s target=%s(hp%.0f)",
                tostring(attacker.name), tostring(heroId), tidStr, abStr,
                tostring(target.name), target.hp or 0))
        end
        -- [通用] 复活吧爱人觉醒2: 被复活者额外回复20%治疗量（任何治疗者都生效果
        if target and target._reviveHealBoost and target.hp > 0 then
            local bonusHeal = math.floor((result.healAmount or 0) * 0.30 + 0.5)
            if bonusHeal > 0 and target.attrs then
                target.attrs:heal(bonusHeal)
                target.hp = target.attrs:get(AD.HP)
                if target.hp > target.maxHp then target.hp = target.maxHp end
            end
        end

        -- #9 卡皮巴拉自然之愈：治疗后给目标HOT + 觉醒
        if heroId == 9 and target.hp > 0 then
            local healAmt = result.healAmount or 0
            -- 觉醒1: HOT恢复比例 10%→15%
            local hotPct = 0.10
            if hasAwaken(attacker, 1) then hotPct = 0.15 end
            -- 觉醒7: HOT恢复比例 15%→25%
            if hasAwaken(attacker, 7) then hotPct = 0.25 end
            -- 觉醒4: 治疗暴击时HOT效果翻倍
            local hotMult = 1.0
            if hasAwaken(attacker, 4) and result.isCrit then
                hotMult = 2.0
            end
            local hps = math.floor(healAmt * hotPct * hotMult + 0.5)
            if hps > 0 then
                local hotData = { hps = hps }
                -- 觉醒2: 有HOT的队友获得+10物甲/魔甲
                if hasAwaken(attacker, 2) then
                    hotData.armorBuff = true
                    -- 添加护甲buff（HOT消失时需移除，由SEM管理或update检查）
                    if target.attrs and not SEM.has(target, SEM.HOT) then
                        target.attrs:addModifier("awaken_hot_armor", {
                            { key = AD.PHYS_ARMOR, flat = 10 },
                        })
                    end
                end
                -- 觉醒5: 有HOT的队友受伤减少5%
                if hasAwaken(attacker, 5) then
                    hotData.dmgReduction = true
                end
                SEM.apply(target, SEM.HOT, 5.0, attacker, hotData)
                if hotMult > 1 then
                    talentLog("[Talent] 卡皮巴拉觉醒4: 暴击HOT翻倍 hps=" .. hps)
                end
            end
            -- 觉醒3: 治疗暴击+15%（永久加成，首次添加成
            if hasAwaken(attacker, 3) and not s.awakFloraHealCrit then
                s.awakFloraHealCrit = true
                if attacker.attrs then
                    attacker.attrs:addModifier("awaken_flora_healcrit", {
                        { key = AD.HEAL_CRIT_RATE, flat = 5 },
                    })
                end
            end
            -- 觉醒6: 治疗加成+15%（永久加成，首次添加成
            if hasAwaken(attacker, 6) and not s.awakFloraHealBonus then
                s.awakFloraHealBonus = true
                if attacker.attrs then
                    attacker.attrs:addModifier("awaken_flora_healbonus", {
                        { key = AD.HEAL_BONUS, flat = 15 },
                    })
                end
            end
        end

        -- #15 复活吧爱人 觉醒: 治疗加成与治疗暴击（永久首次加成)
        if heroId == 15 and target.hp > 0 and result.category == "healing" then
            -- 觉醒2: 治疗加成+15%
            if hasAwaken(attacker, 2) and not s.awakElizHealBonus then
                s.awakElizHealBonus = true
                if attacker.attrs then
                    attacker.attrs:addModifier("awaken_eliz_healbonus", {
                        { key = AD.HEAL_BONUS, flat = 15 },
                    })
                end
            end
            -- 觉醒3: 治疗暴击+10%
            if hasAwaken(attacker, 3) and not s.awakElizHealCrit then
                s.awakElizHealCrit = true
                if attacker.attrs then
                    attacker.attrs:addModifier("awaken_eliz_healcrit", {
                        { key = AD.HEAL_CRIT_RATE, flat = 10 },
                    })
                end
            end
            -- 觉醒2: 复活治疗加成已移至通用治疗处理（任何治疗者都生效果
        end

        -- #23 真布诗人 能量祝福：溢出治疗转能量护盾 + 临时护盾
        local healerId = tonumber(attacker.heroId) or heroId
        if healerId == 23 and target.hp > 0 and result.category == "healing" then
            applyElwynEnergyBlessing(attacker, target, result)
        end

        -- 111 激励 治疗时填充目标5%攻击进度 + 3秒治疗加成10%
        if hasAdv(attacker, "adv_111_inspire") and target.hp > 0 then
            local fillPct = 0.25
            local has221 = hasAdv(attacker, "adv_221_war_ritual")
            local has222 = hasAdv(attacker, "adv_222_blood_ritual")

            -- 221 战争之祭: 填充→50%
            if has221 then fillPct = 0.40 end
            -- 222 嗜血祭祀: 填充→100%, →0%概率触发
            if has222 then
                fillPct = 1.0
                if math.random() > 0.40 then
                    -- 未触发
                    goto skip_inspire
                end
            end

            target.atkProgress = math.min(1.0, (target.atkProgress or 0) + fillPct)

            -- 标记目标：下次攻击有特殊效果
            local ts = ensureState(target)
            if has221 then
                ts.inspiredAtkBonus = true  -- 221: 下次攻击+25%伤害
            end
            if has222 then
                ts.inspiredHealBack = true  -- 222: 攻击后回血
            end

            -- 治疗加成+10% (3秒)
            if target.attrs and not has222 then
                target.attrs:addModifier("talent_inspire_heal", {
                    { key = AD.HEAL_BONUS, flat = 10 },
                })
                -- 简单延时：3秒后移除（在update中管理更复杂，这里简化用SEM机制）
            end

            talentLog("[Talent] 激励 " .. target.name .. " 进度+" .. math.floor(fillPct * 100) .. "%")
            ::skip_inspire::
        end

        -- 112 团队治疗: 将治疗量10%分配给全队
        if hasAdv(attacker, "adv_112_group_heal") then
            local healAmt = result.healAmount or 0
            local groupPct = 0.10
            local has223 = hasAdv(attacker, "adv_223_divine_blessing")
            -- 223 神之赐福: 治疗量→三倍(→30%)
            if has223 then groupPct = 0.30 end

            local groupHeal = math.floor(healAmt * groupPct + 0.5)
            if groupHeal > 0 then
                local allyList = isAlly and TAL_BCS.bAllies or TAL_BCS.bEnemies
                for _, ally in ipairs(allyList) do
                    if ally.hp > 0 and ally ~= target then
                        if ally.attrs then
                            -- 223: <20%HP时必定治疗暴击，治疗量×2
                            local actualHeal = groupHeal
                            if has223 then
                                local allyPct = ally.hp / math.max(1, ally.maxHp)
                                if allyPct < 0.20 then
                                    actualHeal = actualHeal * 2
                                end
                            end
                            ally.attrs:heal(actualHeal)
                            -- syncUnitHp 需要通过 ctx 调用，这里直接同步
                            ally.hp = ally.attrs:get(AD.HP)
                            if ally.hp > ally.maxHp then ally.hp = ally.maxHp end
                        end
                    end
                end
            end
        end

        -- 224 神圣惩戒: 40%概率对随机敌人发射惩戒飞弹（治疗量×400%暗影伤害)
        if hasAdv(attacker, "adv_224_divine_punishment") and dealDmgFn then
            if math.random() < 0.40 then
                local healAmt = result.appliedHealAmount or result.healAmount or 0
                if healAmt > 0 then
                    local enemyList = isAlly and TAL_BCS.bEnemies or TAL_BCS.bAllies
                    local alive = getAliveEnemies(enemyList)
                    if #alive > 0 then
                        local randTarget = alive[math.random(#alive)]
                        local baseDmg = healAmt * 4.0
                        local punishDmg, punishCrit = calcTalentFixedDamage(attacker, randTarget, baseDmg, {
                            atkType = AD.ATK_SHADOW,
                        })

                        if result._talentDmgMult and result._talentDmgMult > 1.0 then
                            punishDmg = math.floor(punishDmg * result._talentDmgMult + 0.5)
                        end
                        local rchBonus = RCH.getDamageBonus(attacker, randTarget)
                        if rchBonus > 0 then
                            punishDmg = math.floor(punishDmg * (1 + rchBonus / 100) + 0.5)
                        end
                        local semMult = SEM.getDamageTakenMult(randTarget)
                        if semMult and semMult ~= 1.0 then
                            punishDmg = math.floor(punishDmg * semMult + 0.5)
                        end

                        if punishDmg > 0 and randTarget.hp > 0 then
                            local prefix = punishCrit and "暴击惩戒 " or "惩戒 "
                            dealDmgFn(randTarget, punishDmg, not isAlly, prefix, { 255, 215, 0 }, {
                                talentProjKey = "EF_ZY_224",
                                statCategory = "magical",
                                isCrit = punishCrit,
                                critEligible = true,
                            })
                            talentLog("[Talent] 神圣惩戒 →" .. randTarget.name .. " (" .. punishDmg .. ")")
                        end
                    end
                end
            end
        end
    end

    -- === 激励效果消费（被激励者的攻击后处理） ===
    if result and result.category ~= "healing" and not result.isMiss then
        -- 221 战争之祭: 被激励后攻击伤害+25%（乘法，这里简化为额外伤害)
        if s.inspiredAtkBonus then
            s.inspiredAtkBonus = false
            -- 额外伤害已在攻击中通过modifier处理不太方便,
            -- 这里用dealDmgFn补偿25%
            if dealDmgFn and target.hp > 0 and result.totalDamage then
                local bonusDmg = math.floor(result.totalDamage * 0.25 + 0.5)
                if bonusDmg > 0 then
                    dealDmgFn(target, bonusDmg, not isAlly, "激励", { 255, 200, 50 })
                end
            end
        end
        -- 222 嗜血祭祀: 攻击后回复造成伤害等值HP
        if s.inspiredHealBack then
            s.inspiredHealBack = false
            local totalDmg = result.totalDamage or 0
            if totalDmg > 0 and attacker.attrs then
                attacker.attrs:heal(totalDmg)
                attacker.hp = attacker.attrs:get(AD.HP)
                if attacker.hp > attacker.maxHp then attacker.hp = attacker.maxHp end
                talentLog("[Talent] 嗜血祭祀: " .. attacker.name .. " 回血 " .. totalDmg)
            end
        end
    end

    -- ======== 星图 RUNTIME_ONLY 节点: onAfterAttack 触发 ========

    -- 节点113 秘法印记: 造成魔法伤害时，15%概率使目标受伤+8%，持续5秒）
    if hasStarNode(attacker, 113) then
        if attacker.dmgMainType == "魔法" and target.hp > 0 then
            if math.random() < 0.15 then
                SEM.apply(target, SEM.ARCANE_MARK, 5.0, attacker, { mult = 0.08 })
                talentLog("[Talent] 秘法印记: " .. (attacker.name or "?") .. " →" .. (target.name or "?") .. " 受伤+8% (5s)")
            end
        end
    end

    -- 节点115 斩尽杀绝 暴击时额外伤害= 目标已损失HP% × 30%
    if hasStarNode(attacker, 115) then
        if result and result.isCrit and target.hp > 0 and dealDmgFn then
            local maxHp = target.maxHp or 1
            local lostPct = 1.0 - (target.hp / math.max(1, maxHp))
            local bonusMult = lostPct * 0.30
            local baseDmg = result.totalDamage or 0
            local bonusDmg = math.floor(baseDmg * bonusMult + 0.5)
            if bonusDmg > 0 then
                dealDmgFn(target, bonusDmg, not isAlly, "斩杀 ", { 200, 50, 50 })
                talentLog("[Talent] 斩尽杀绝 " .. (attacker.name or "?") .. " 暴击额外+" .. bonusDmg .. " (已损 " .. math.floor(lostPct * 100) .. "%×30%)")
            end
        end
    end

    -- 节点124 过量治疗: 溢出的治疗量转化为目标能量护盾（转化率30%）
    if teamHasStarNode(124) and result and result.category == "healing" then
        if target and target.hp > 0 and target.attrs then
            local overflow = result.overhealAmount
            if overflow == nil then
                -- 兼容未写入 overhealAmount 的治疗路径
                local healAmt = result.healAmount or 0
                local applied = result.appliedHealAmount or 0
                overflow = math.max(0, healAmt - applied)
            end
            applyOverhealToEnergyShield(target, overflow)
        end
    end

    -- 节点128 共鸣之歌: 攻击/治疗后15%概率全队伤害+5%，持续5秒）
    if hasStarNode(attacker, 128) and attackerAllies then
        if math.random() < 0.15 then
            for _, ally in ipairs(attackerAllies) do
                if ally.hp > 0 and ally.attrs then
                    local as = getState(ally)
                    if as then
                        as.resonanceTimer = 3.0
                        ally.attrs:removeModifier("starmap_resonance")
                        ally.attrs:addModifier("starmap_resonance", {
                            { key = AD.DMG_BONUS, flat = 5 },
                        })
                    end
                end
            end
            talentLog("[Talent] 共鸣之歌: " .. (attacker.name or "?") .. " 触发全队伤害+5% (3s)")
        end
    end
end

--- 伤害拦截：在 takeDamage 之前修改伤害值（用于铁憨憨吸收队友伤害）
--- 返回目标实际应受伤害，差值由铁憨憨承受
---@param target table 受伤单位
---@param damage number 原始伤害
---@param isTargetAlly boolean 受伤者是否为己方
---@param syncHpFn function 同步HP函数
---@param dmgCategory string|nil 伤害类型 "physical"/"magical"
---@return number 修改后的伤害
function TAL.modifyDamageForTarget(target, damage, isTargetAlly, syncHpFn, dmgCategory)
    if damage <= 0 then return damage end

    if not isTargetAlly then return damage end

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
        -- 觉醒7: 记录格挡掉的伤害，下次攻击作为固定伤害增伤
        if hasAwaken(unit, 7) then
            local blockedAmt = result.blockedDamage or math.floor(damage * 0.3 + 0.5)
            s.blockAbsorbedDmg = s.blockAbsorbedDmg + blockedAmt
            talentLog("[Talent] 接化发掌门 觉醒7: 吸收伤害+" .. blockedAmt .. " (累计=" .. s.blockAbsorbedDmg .. ")")
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
                -- 计算复活概率: 基础25%, 觉醒1次0%, 觉醒5→50%
                local reviveRate = 0.25
                if hasAwaken(ally, 1) then reviveRate = 0.40 end
                if hasAwaken(ally, 5) then reviveRate = 0.60 end
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
                    return true
                else
                    elizState.reviveUsed[dyingUnit] = true
                end
            end
        end
    end
    return false
end

--- 敌人死亡钩子（敌方HP≤0时调用）
---@param deadEnemy table 死亡的敌方单位
---@param allies table 己方单位列表
---@param enemies table 敌方单位列表
function TAL.onEnemyDeath(deadEnemy, allies, enemies)
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

    -- #8 愤怒的小雀 觉醒2: 被标记敌人死亡 → 转移标记（全队仅一次）
    local ayane = getPrimaryAyane(allies, true)
    if ayane and SEM.has(deadEnemy, SEM.MARKED) then
        local aliveEnemies = getAliveEnemies(enemies)
        if #aliveEnemies > 0 then
            local newTarget = aliveEnemies[math.random(#aliveEnemies)]
            applyAyaneMark(ayane, newTarget, enemies)
            talentLog("[Talent] 愤怒的小雀 觉醒2: 标记转移→" .. (newTarget.name or "?")
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
    local TM = require("systems.ThreatManager")

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

--- 获取单位的征服层数（渲染用）
---@param unit table
---@return number 征服层数(0=无）
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
    local ayane = getPrimaryAyane(allies, true)
    if not ayane then return end
    if hasAnyAyaneMark(enemies) then return end
    local aliveEnemies = getAliveEnemies(enemies)
    if #aliveEnemies == 0 then return end
    local target = aliveEnemies[math.random(#aliveEnemies)]
    applyAyaneMark(ayane, target, enemies)
    talentLog("[Talent] 愤怒的小雀 觉醒2: 补标 " .. (target.name or "?")
        .. " (增伤=" .. math.floor(getAyaneMarkMult(ayane) * 100) .. "%)")
end
return TAL
