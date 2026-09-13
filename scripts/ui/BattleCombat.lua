-- ============================================================================
-- BattleCombat - 战斗逻辑模块（攻�?伤害/动画状态机�?
-- �?BattleScene.lua 提取
-- ============================================================================

local CF  = require("systems.CombatFormula")
local AD  = require("systems.AttributeDef")
local TM  = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local PS  = require("ui.ProjectileSystem")
local Diag = require("systems.BattleDiag")
local BattleLayout = require("core.BattleLayout")
local RCH = require("systems.RelicConditionHandler")
local ART = require("systems.ArtifactRuntime")
local MAS = require("systems.MapAffixSystem")
local DungeonBattle = require("ui.DungeonBattle")
local NumberUtil = require("core.NumberUtil")
local BattleStats = require("systems.BattleStats")
local SettingsPanel = require("ui.SettingsPanel")

local BattleCombat = {}
-- ======================== [多实例] 战斗状态容器 ========================
-- 每场并行战斗一个实例: { floatingTexts, cardAnims, hitFlashes, hpBuffers,
--   ftPool, comboQueue, unitDamageAccum, ctx }
-- BCS 恒指向当前挂载实例; 现有单战斗场景统一使用 defaultState（行为不变）
local function newState(id)
    return {
        id = id or "?",
        floatingTexts   = {},
        cardAnims       = {},
        hitFlashes      = {},
        hpBuffers       = {},
        ftPool          = {},
        comboQueue      = {},
        unitDamageAccum = {},
        ctx             = {},
    }
end
local defaultState = newState("default")
local BCS = defaultState
function BattleCombat.newState(id) return newState(id) end
--- 挂载某场战斗的状态（三栏并行战斗按栏切换）
function BattleCombat.mount(s) BCS = s or defaultState end
function BattleCombat.mountedState() return BCS end


-- ======================== 常量 ========================

local DESIGN_W = 1080

-- 卡片尺寸（用于坐标计算）
local CARD_W     = 198
local CARD_SPACING = 7

-- 浮动文字
local FLOAT_TOTAL_FRAMES = 20
local FLOAT_FPS          = 30
local FLOAT_DURATION     = FLOAT_TOTAL_FRAMES / FLOAT_FPS
local FLOAT_MOVE_DIST    = 240
local MAX_FLOATING_TEXTS = 15            -- 同时存在的飘字上�?
local FLOAT_FAST_FADE    = 17 / FLOAT_FPS -- 强制进入最�?帧快速消�?

-- 攻击动画
local LUNGE_DISTANCE   = 60
local LUNGE_DURATION   = 0.12
local RETURN_DURATION  = 0.15
local RECOIL_DURATION  = 0.08
local RECOIL_RETURN    = 0.12
local RECOIL_DISTANCE  = 30
local CHARGE_START     = 0.7
local CHARGE_DISTANCE  = 25

-- 死亡/复活动画（从 BattleScene 引入常量�?
local DEATH_HITSTOP        = 0.06
local DEATH_BURST_DUR      = 0.22
local DEATH_SETTLE_DUR     = 0.12
local DEATH_ANIM_DURATION  = DEATH_HITSTOP + DEATH_BURST_DUR + DEATH_SETTLE_DUR
local DEATH_ANIM_DISTANCE  = 80
local DEATH_OVERSHOOT      = 1.15
local REVIVE_ANIM_DURATION = 0.35
local REVIVE_ANIM_DISTANCE = 80
local TOMBSTONE_FADEIN     = 0.25

-- 入场动画
local ENTER_ANIM_DURATION  = 0.30
local ENTER_ANIM_DISTANCE  = 100
local ENTER_STAGGER        = 0.06

-- 血条缓�?
local HP_BUFFER_SPEED = 1.2

-- 受击闪烁
local HIT_FLASH_DURATION = 0.3

-- 远程角色缩放攻击动画
local RANGED_CHARGE_SCALE  = 0.85   -- 蓄力时缩小到 85%
local RANGED_LUNGE_SCALE   = 1.15   -- 攻击时放大到 115%

--- 判断是否远程/治疗单位
--- 英雄：按投射物配置判断；怪物：按 isRanged 标志判断（所有怪物都有特效但不都是远程�?
local function isRangedUnit(unit)
    if unit.heroId and PS.hasProjectile(unit.heroId) then
        return true
    end
    if unit.monsterId then
        return unit.isRanged == true
    end
    return false
end

-- ======================== 共享状�?========================
-- 这些表通过 setContext 注入外部引用，但动画/浮动文字/闪烁是本模块自有状�?


--- 可随「特效显示」开关屏蔽的战斗卡牌动画（攻击前摇/后摇、受击后退）
local COMBAT_CARD_ANIM_STATES = {
    lunge = true,
    ["return"] = true,
    recoil = true,
    recoil_return = true,
}

local function isCombatCardAnimEnabled()
    return SettingsPanel.isEffectsEnabled()
end

local function isCombatCardAnimState(state)
    return state ~= nil and COMBAT_CARD_ANIM_STATES[state] == true
end

local function playAttackCardAnim(attacker, isAlly)
    if not isCombatCardAnimEnabled() then return end
    BCS.cardAnims[attacker] = {
        state    = "lunge",
        timer    = 0,
        isAlly   = isAlly,
        lungeDir = isAlly and -1 or 1,
        isRanged = isRangedUnit(attacker),
    }
end

-- 浮动文字对象池（减少 GC 压力�?
local function acquireFt()
    local n = #BCS.ftPool
    if n > 0 then
        local ft = BCS.ftPool[n]
        BCS.ftPool[n] = nil
        return ft
    end
    return {}
end
local function releaseFt(ft)
    ft.text = nil
    ft.color = nil
    BCS.ftPool[#BCS.ftPool + 1] = ft
end

-- 连击队列：{ attacker, isAlly, targetIsAlly, comboHitIndex, targetIndex, delay, timer, atkStableId, targetRef, tgtStableId }

-- 每个单位的累计伤害统计（unit �?number�?

-- 外部上下文（�?setContext 注入�?

-- ======================== 公共常量导出 ========================

BattleCombat.DEATH_ANIM_DURATION  = DEATH_ANIM_DURATION
BattleCombat.REVIVE_ANIM_DURATION = REVIVE_ANIM_DURATION
BattleCombat.REVIVE_ANIM_DISTANCE = REVIVE_ANIM_DISTANCE
BattleCombat.TOMBSTONE_FADEIN     = TOMBSTONE_FADEIN
BattleCombat.CHARGE_START         = CHARGE_START
BattleCombat.CHARGE_DISTANCE      = CHARGE_DISTANCE

-- ======================== 注入上下�?========================

--- 注入外部引用（allies, enemies 等）
---@param context table { getAllies, getEnemies, ALLY_CARD_CY, ENEMY_CARD_CY, onAttackHit }
function BattleCombat.setContext(context)
    BCS.ctx = context
end

-- ======================== 辅助函数 ========================

--- 在单位列表中查找目标的索引（优先引用匹配，fallback �?heroId�?
--- 解决 setAllies 替换列表后旧引用匹配失败的问�?
---@param list table 单位列表
---@param target table 要查找的单位
---@return number|nil 索引，未找到返回 nil
local function findUnitIndex(list, target)
    -- 1. 优先：引用相�?
    for i, u in ipairs(list) do
        if u == target then return i end
    end
    -- 2. instanceId 匹配（怪物实例，同 monsterId 可能有多个）
    if target.instanceId then
        for i, u in ipairs(list) do
            if u.instanceId == target.instanceId then return i end
        end
    end
    -- 3. fallback：heroId 匹配（allies �?setAllies 替换后旧引用失效�?
    if target.heroId then
        for i, u in ipairs(list) do
            if u.heroId == target.heroId then return i end
        end
    end
    return nil
end

--- 判断单位是否属于己方列表（统计归因：仅己方英雄输出计入 BattleStats）
local function isAllyUnit(unit)
    if not unit or not BCS.ctx.getAllies then return false end
    for _, u in ipairs(BCS.ctx.getAllies()) do
        if u == unit then return true end
    end
    return false
end

--- 从天赋投射物选项提取战斗统计元数据
local function statMetaFromProjOpts(projOpts)
    if not projOpts then return nil end
    if projOpts.isDot or projOpts.statCategory or projOpts.isCrit or projOpts.critEligible ~= nil
        or projOpts.threatScale then
        return {
            isDot = projOpts.isDot,
            category = projOpts.statCategory,
            isCrit = projOpts.isCrit,
            critEligible = projOpts.critEligible,
            threatScale = projOpts.threatScale,
        }
    end
    return nil
end

--- 从列表中重新解析单位（优�?findUnitIndex，失败则用稳�?ID 精确匹配�?
--- @param list table 当前单位列表
--- @param staleRef table|nil 可能过时的单位引�?
--- @param stableId table|nil { heroId=number|nil, instanceId=number|nil }
--- @return table|nil unit, number|nil index
local function resolveUnitInList(list, staleRef, stableId)
    -- 快速路径：原始引用仍有�?
    if staleRef then
        local idx = findUnitIndex(list, staleRef)
        if idx then
            return list[idx], idx
        end
    end

    -- 快速路径失败且无稳定标�?�?直接返回 nil
    if not stableId then return nil, nil end

    -- 慢路径：用稳定标识符逐层匹配
    -- 优先 instanceId（全局唯一�?
    if stableId.instanceId then
        for i, u in ipairs(list) do
            if u.instanceId == stableId.instanceId then
                print(string.format("[COMBO-RESOLVE] unit=%s resolved via instanceId (idx=%d)",
                    tostring(stableId.instanceId), i))
                return u, i
            end
        end
    end
    -- 次�?heroId（英雄阵容内唯一�?
    if stableId.heroId then
        for i, u in ipairs(list) do
            if u.heroId == stableId.heroId then
                print(string.format("[COMBO-RESOLVE] unit=%s resolved via heroId (idx=%d)",
                    tostring(stableId.heroId), i))
                return u, i
            end
        end
    end

    -- 所有精确标识符都失�?�?返回 nil（不使用 monsterId fallback�?
    return nil, nil
end

--- 获取卡片在设计空间中的中�?X 坐标
--- [左4vs右4] 获取卡片中心坐标: X 按阵营列, Y 按队伍内索引竖排
local function getCardPos(units, index)
    return BattleLayout.posForList(units, index, nil)
end

local function getCardCX(units, index)
    local cx = getCardPos(units, index)
    return cx
end

local function getCardCY(units, index)
    local _, cy = getCardPos(units, index)
    return cy
end
BattleCombat.getCardCX = getCardCX
BattleCombat.getCardCY = getCardCY
BattleCombat.getCardPos = getCardPos

--- 获取存活单位列表
local function getAliveUnits(units)
    local alive = {}
    for i, u in ipairs(units) do
        if u.hp > 0 and not u.artifactUntargetable then
            alive[#alive + 1] = { index = i, unit = u }
        end
    end
    return alive
end
BattleCombat.getAliveUnits = getAliveUnits

local function selectDamageRetargetIndex(attacker, targetList, isAlly)
    if not targetList then return nil end

    local idx
    if not isAlly then
        idx = TM.selectTarget(targetList)
    elseif attacker and attacker.attrs then
        idx = TAL.getLockedTarget(attacker, targetList)
        if not idx then
            idx = CF.selectTarget(targetList)
        end
    end

    if idx then
        local unit = targetList[idx]
        if unit and unit.hp and unit.hp > 0 and not unit.artifactUntargetable and unit.attrs then
            return idx
        end
    end

    local alive = getAliveUnits(targetList)
    if #alive == 0 then return nil end
    for _ = 1, #alive do
        local candidate = alive[math.random(#alive)]
        local unit = targetList[candidate.index]
        if unit and unit.attrs then
            return candidate.index
        end
    end
    return nil
end

local function resolveDamageTarget(targetList, staleRef, stableId, attacker, isAlly)
    local unit, idx = resolveUnitInList(targetList, staleRef, stableId)
    if unit and unit.hp and unit.hp > 0 and not unit.artifactUntargetable and unit.attrs then
        return unit, idx
    end

    idx = selectDamageRetargetIndex(attacker, targetList, isAlly)
    if not idx then return nil, nil end
    return targetList[idx], idx
end

local function getUnitHpValues(unit)
    if unit.attrs then
        return unit.attrs:get(AD.HP), unit.attrs:get(AD.MAX_HP)
    end
    return unit.hp or 0, unit.maxHp or 0
end

local function isValidHealTarget(unit)
    if not unit or (unit.hp or 0) <= 0 or unit.artifactUntargetable then return false end
    if DungeonBattle and DungeonBattle.isHealBlocked and DungeonBattle.isHealBlocked(unit) then return false end
    if not ART.canHeal(unit) then return false end
    return true
end

local function getHealableAliveUnits(units, excludeIndex)
    local alive = {}
    for i, u in ipairs(units) do
        if i ~= excludeIndex and isValidHealTarget(u) then
            alive[#alive + 1] = { index = i, unit = u }
        end
    end
    return alive
end

local function isHealableUnit(unit)
    if not isValidHealTarget(unit) then return false end
    local hp, maxHp = getUnitHpValues(unit)
    if hp > 0 and maxHp > 0 and hp < maxHp then return true end
    -- 护盾未满也视为需要治疗（奶妈不会因全员护盾满HP而停止行动）
    if unit.attrs and unit.attrs.final then
        local maxES = unit.attrs.final[AD.ENERGY_SHIELD] or 0
        if maxES > 0 then
            local curES = unit.attrs.energyShield or 0
            if curES < maxES then return true end
        end
    end
    return false
end

local function collectHealCandidates(units, excludeIndex)
    local candidates = {}
    for i, u in ipairs(units) do
        if i ~= excludeIndex and isHealableUnit(u) then
            local hp, maxHp = getUnitHpValues(u)
            candidates[#candidates + 1] = {
                index = i,
                pct = hp / math.max(1, maxHp),
                missing = maxHp - hp,
            }
        end
    end
    table.sort(candidates, function(a, b)
        if a.pct == b.pct then
            return a.missing > b.missing
        end
        return a.pct < b.pct
    end)
    return candidates
end

local function shuffleList(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

--- 同步 attrs �?unit 表面字段（hp / maxHp�?
local function syncUnitHp(unit)
    if unit.attrs then
        unit.hp    = unit.attrs:get(AD.HP)
        unit.maxHp = unit.attrs:get(AD.MAX_HP)
    end
end
BattleCombat.syncUnitHp = syncUnitHp

--- 添加浮动文字
---@param text string
---@param cx number
---@param cy number
---@param color table {r,g,b}
---@param isCrit boolean
---@param fontSize number|nil
local function addFloatingText(text, cx, cy, color, isCrit, fontSize)
    -- 飘字上限：超出时将最早的飘字跳到快速淡出阶�?
    while #BCS.floatingTexts >= MAX_FLOATING_TEXTS do
        local oldest = BCS.floatingTexts[1]
        if oldest.timer < FLOAT_FAST_FADE then
            oldest.timer = FLOAT_FAST_FADE  -- 跳到最�?帧淡�?
        else
            -- 已在淡出中，直接移除
            releaseFt(oldest)
            table.remove(BCS.floatingTexts, 1)
        end
        -- 只强制一个后跳出，留�?update 自然清理
        break
    end

    local angle = -math.pi * 0.5 + (math.random() - 0.5) * math.pi * 0.5
    local baseSize = fontSize or 80
    if isCrit then baseSize = baseSize * 2 end
    local entry = acquireFt()
    entry.text     = text
    entry.x        = cx
    entry.y        = cy
    entry.dirX     = math.cos(angle)
    entry.dirY     = math.sin(angle)
    entry.timer    = 0
    entry.duration = FLOAT_DURATION
    entry.color    = color
    entry.isCrit   = isCrit or false
    entry.fontSize = baseSize
    BCS.floatingTexts[#BCS.floatingTexts + 1] = entry
end
BattleCombat.addFloatingText = addFloatingText

--- 设置受击后退（跟随设置「特效显示」开关）
local function setRecoil(target, lungeDir)
    if not isCombatCardAnimEnabled() then return end
    -- 已死亡的单位不设置 recoil，防止覆盖死亡动画
    if target.hp <= 0 then return end
    BCS.cardAnims[target] = { state = "recoil", timer = 0, lungeDir = lungeDir }
end

--- 设置受击闪烁（跟随设置「特效显示」开关）
local function setHitFlash(target)
    if not SettingsPanel.isEffectsEnabled() then return end
    BCS.hitFlashes[target] = { timer = 0 }
end

--- 应用全局伤害乘数（如竞技场全体减伤），BCS.ctx.globalDmgMult 默认 1.0
local function applyGlobalDmgMult(damage)
    local mult = BCS.ctx.globalDmgMult
    if mult and mult ~= 1.0 then
        return math.max(1, math.floor(damage * mult))
    end
    return damage
end

--- 天赋/弹射等伤害在 BattleStats 中的类型（未显式传入时按攻击者 atkType 推断）
local function resolveDamageStatCategory(source, statMeta)
    if statMeta and statMeta.category then
        return statMeta.category
    end
    if source and source.atkType then
        return AD.getAtkCategory(source.atkType)
    end
    return "physical"
end

--- 统一伤害处理（供 DOT/AOE/弹射/反击复用�?
---@param target table 受伤单位
---@param damage number 伤害�?
---@param isTargetAlly boolean
---@param prefix string
---@param color table {r,g,b}
---@param source table|nil 伤害来源（天赋/弹射/DOT 归因）
---@param statMeta table|nil { isDot?, category?, isCrit?, critEligible? }
local function dealDamageToUnit(target, damage, isTargetAlly, prefix, color, source, statMeta)
    if not target or target.hp <= 0 then return 0 end
    damage = applyGlobalDmgMult(damage)
    local hpBefore = target.hp
    local actual
    local takenForStats
    if target.attrs then
        if source and not (statMeta and statMeta.noCounter) then
            damage = ART.onBeforeTakeDamage(target, source, damage, isTargetAlly)
        end
        local shieldBefore = (target.attrs.energyShield or 0) + (target.attrs.tempEnergyShield or 0)
        actual = target.attrs:takeDamage(damage)
        local shieldAfter = (target.attrs.energyShield or 0) + (target.attrs.tempEnergyShield or 0)
        takenForStats = actual + math.max(0, shieldBefore - shieldAfter)
        ART.checkShieldBreak(target, shieldBefore)
        syncUnitHp(target)
    else
        actual = math.min(target.hp, damage)
        takenForStats = actual
        target.hp = target.hp - actual
    end
    if target.hp <= 0 and hpBefore > 0 then
        local overkill = math.max(0, damage - hpBefore)
        target._overkillRatio = math.min(1.0, overkill / (target.maxHp or hpBefore))
        target._killedBy = source
        if source and isTargetAlly == false then
            DungeonBattle.onEnemyKill(source)
        end
    end
    -- 战斗统计：己方英雄对敌方输出（弹射/飞剑/奥术飞弹/DOT 等非普攻路径）
    if takenForStats > 0 and source and source.heroId and not isTargetAlly and isAllyUnit(source) then
        if statMeta and statMeta.isDot then
            BattleStats.recordDotDamage(source, takenForStats)
        else
            local critEligible = statMeta and statMeta.critEligible
            if critEligible == nil then
                critEligible = false
            end
            BattleStats.recordDamage(
                source, takenForStats,
                resolveDamageStatCategory(source, statMeta),
                statMeta and statMeta.isCrit or false,
                critEligible
            )
        end
        -- 天赋/投射物伤害仇恨（如灵月飞剑 threatScale=0.1）
        if statMeta and statMeta.threatScale then
            TM.onDamageDealt(source, actual, false, statMeta.threatScale)
        end
    end
    -- 战斗统计：己方承伤（DOT/范围/天赋等非普攻路径打到己方时）
    if isTargetAlly then
        BattleStats.recordTaken(target, takenForStats or actual)
    end
    local tgtList = isTargetAlly and BCS.ctx.getAllies() or BCS.ctx.getEnemies()
    local tgtIdx = findUnitIndex(tgtList, target)
    local tgtCX, tgtCY = getCardPos(tgtList, tgtIdx or math.ceil(#tgtList * 0.5))
    local showCrit = statMeta and statMeta.isCrit or false
    -- 伤害飘字配色：普通白色 / 暴击红色
    addFloatingText((prefix or "") .. "-" .. NumberUtil.format(actual), tgtCX, tgtCY,
        showCrit and { 255, 60, 60 } or { 255, 255, 255 }, showCrit)
    setHitFlash(target)
    if actual > 0 then
        require("systems.GameSFX").play("hit")
    end
    return actual
end
BattleCombat.dealDamageToUnit = dealDamageToUnit

--- 灵月飞剑/飞回：目标在投射物飞行期间死亡时转火，避免伤害池已消耗但统计丢失
---@param attacker table
---@param primaryTarget table
---@param damage number
---@param isTargetAlly boolean
---@param prefix string|nil
---@param color table|nil
---@param meta table|nil
---@param projOpts table|nil
---@param allyList table|nil
---@param enemyList table|nil
---@return number actual
local function applyFlyingSwordDamageWithRetarget(attacker, primaryTarget, damage, isTargetAlly, prefix, color, meta, projOpts, allyList, enemyList)
    local isFlySword = prefix == "灵月飞剑" or prefix == "飞回"
        or (projOpts and (projOpts.flyingSwordIndex or projOpts.flyingSwordOnHit))
    if not isFlySword then
        return dealDamageToUnit(primaryTarget, damage, isTargetAlly, prefix or "", color or { 255, 238, 96 }, attacker, meta)
    end

    local pool = isTargetAlly and (allyList or BCS.ctx.getAllies()) or (enemyList or BCS.ctx.getEnemies())
    local function tryHit(unit)
        if not unit or unit.hp <= 0 then return 0 end
        return dealDamageToUnit(unit, damage, isTargetAlly, prefix or "", color or { 255, 238, 96 }, attacker, meta)
    end

    local actual = tryHit(primaryTarget)
    if actual > 0 then return actual end

    local alive = getAliveUnits(pool)
    if #alive == 0 then return 0 end
    for _ = 1, #alive do
        actual = tryHit(alive[math.random(#alive)])
        if actual > 0 then return actual end
    end
    return 0
end

--- 灵月飞剑 inbound 方向（圆环点 → 目标，用于飞回穿透/折返）
local function computeFlyingSwordApproachDir(startX, startY, endX, endY, projOpts)
    local fromX, fromY = startX, startY
    if projOpts and projOpts.flyingSwordIndex and projOpts.flyingSwordCount then
        local count = projOpts.flyingSwordCount
        local idx = projOpts.flyingSwordIndex
        local radius = projOpts.flyingSwordRadius or 90
        local angleOnRing = (2 * math.pi / count) * (idx - 1) - math.pi * 0.5
        fromX = startX + math.cos(angleOnRing) * radius
        fromY = startY + math.sin(angleOnRing) * radius
    end
    local dx, dy = endX - fromX, endY - fromY
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then
        return 0, -1
    end
    return dx / len, dy / len
end

--- 解析天赋/弹射投射物起点（默认攻击者卡片；弹射时从上一命中目标卡片出发）
---@param attacker table
---@param projOpts table|nil
---@param allyList table|nil
---@param enemyList table|nil
---@return number startX, number startY
function BattleCombat.resolveTalentProjStart(attacker, projOpts, allyList, enemyList)
    allyList = allyList or BCS.ctx.getAllies()
    enemyList = enemyList or BCS.ctx.getEnemies()

    if projOpts and projOpts.bounceFromUnit then
        local from = projOpts.bounceFromUnit
        for li, u in ipairs(enemyList) do
            if u == from then
                return getCardPos(enemyList, li)
            end
        end
        for li, u in ipairs(allyList) do
            if u == from then
                return getCardPos(allyList, li)
            end
        end
    end

    if projOpts and projOpts.starGateIndex then
        local baseX, baseY
        local atkIdx = findUnitIndex(allyList, attacker)
        local isAllyGate = true
        if atkIdx then
            baseX, baseY = getCardPos(allyList, atkIdx)
        else
            atkIdx = findUnitIndex(enemyList, attacker)
            if atkIdx then
                isAllyGate = false
                baseX, baseY = getCardPos(enemyList, atkIdx)
            else
                baseX, baseY = getCardPos(allyList, math.max(1, math.ceil(#allyList / 2)))
            end
        end
        local count = projOpts.starGateCount or 1
        local idx = projOpts.starGateIndex or 1
        local xOffset = isAllyGate and 150 or -150
        local yOffset = -118
        if count >= 2 then
            local pairSign = (idx == 1) and -1 or 1
            xOffset = pairSign * 118
            yOffset = -118
        end
        return baseX + xOffset, baseY + yOffset
    end

    local atkIdx = findUnitIndex(allyList, attacker)
    if not atkIdx and attacker and attacker.heroId then
        for ai, u in ipairs(allyList) do
            if u.heroId == attacker.heroId then
                atkIdx = ai
                break
            end
        end
    end
    if atkIdx then
        return getCardPos(allyList, atkIdx)
    end
    return getCardPos(allyList, math.max(1, math.ceil(#allyList / 2)))
end

--- 天赋/周期伤害（带投射物），供 TAL.update 等非攻击流水线调用
---@param attacker table
---@param target table
---@param damage number
---@param isTargetAlly boolean
---@param prefix string|nil
---@param color table|nil
---@param projOpts table|nil
---@param allyList table|nil
---@param enemyList table|nil
function BattleCombat.dealTalentDamage(attacker, target, damage, isTargetAlly, prefix, color, projOpts, allyList, enemyList)
    local meta = statMetaFromProjOpts(projOpts)
    local function applyDamage()
        return applyFlyingSwordDamageWithRetarget(attacker, target, damage, isTargetAlly, prefix, color, meta, projOpts, allyList, enemyList)
    end
    if not BCS.ctx.onTalentDealDamage or not attacker or not attacker.heroId then
        return applyDamage()
    end
    local lookupList = isTargetAlly and (allyList or BCS.ctx.getAllies()) or (enemyList or BCS.ctx.getEnemies())
    for li, lu in ipairs(lookupList) do
        if lu == target then
            local tdCX, tdCY = getCardPos(lookupList, li)
            BCS.ctx.onTalentDealDamage(attacker, target, tdCX, tdCY, prefix, applyDamage, projOpts)
            return
        end
    end
    return applyDamage()
end

--- 天赋伤害投射物 + 命中后回调（灵月飞剑飞回等）
---@param attacker table
---@param target table
---@param tgtCX number
---@param tgtCY number
---@param prefix string|nil
---@param applyDamage function|nil
---@param projOpts table|nil
---@param allyList table|nil
---@param enemyList table|nil
function BattleCombat.onTalentDealDamage(attacker, target, tgtCX, tgtCY, prefix, applyDamage, projOpts, allyList, enemyList)
    local BattleEffects = require("ui.BattleEffects")
    allyList = allyList or BCS.ctx.getAllies()
    enemyList = enemyList or BCS.ctx.getEnemies()

    if not attacker or not attacker.heroId then
        if applyDamage then applyDamage() end
        return
    end

    BattleEffects.spawnTalentVfx(tgtCX, tgtCY, projOpts)
    if projOpts and projOpts.instantDamage then
        if applyDamage then applyDamage() end
        if projOpts.onProjectileLand then projOpts.onProjectileLand() end
        return
    end

    local function tryRecordOnHit()
        local ro = projOpts and projOpts.recordOnHit
        if not ro or not ro.addCarryover then return end
        if target.hp <= 0 then return end
        if math.random() < ro.chance then
            ro.addCarryover(ro.baseDmg)
        end
    end

    local startX, startY = BattleCombat.resolveTalentProjStart(attacker, projOpts, allyList, enemyList)
    local endX, endY = tgtCX, tgtCY

    local function buildFlybackContinuation()
        local fb = projOpts and projOpts.flyingSwordOnHit
        if not fb then return nil end
        if not target or target.hp <= 0 then return nil end
        if math.random() >= fb.chance then return nil end
        local flybackDmg = math.floor((fb.baseDmg or 0) * (fb.extraMult or 1) + 0.5)
        if flybackDmg <= 0 then return nil end
        local dirX, dirY = computeFlyingSwordApproachDir(startX, startY, endX, endY, projOpts)
        return {
            hitX = endX,
            hitY = endY,
            dirX = dirX,
            dirY = dirY,
            onReturnHit = function()
                local actual = applyFlyingSwordDamageWithRetarget(
                    attacker, target, flybackDmg, fb.isTargetAlly, "飞回", { 255, 200, 100 },
                    statMetaFromProjOpts(projOpts), projOpts, allyList, enemyList)
                if actual > 0 and fb.recordChance and fb.recordChance > 0 and fb.addCarryover then
                    if math.random() < fb.recordChance then
                        fb.addCarryover(flybackDmg)
                    end
                end
            end,
        }
    end

    local function onProjectileHit()
        if projOpts and projOpts._hitResolved then return end
        if projOpts then projOpts._hitResolved = true end

        if applyDamage then applyDamage() end
        tryRecordOnHit()
        if projOpts and projOpts.onProjectileLand then
            projOpts.onProjectileLand()
        end
        return buildFlybackContinuation()
    end

    local talentKey = projOpts and projOpts.talentProjKey or nil
    local spawnOpts = projOpts or { target = target }
    if talentKey and PS.hasTalentProjectile(talentKey) then
        PS.spawnTalent(talentKey, startX, startY, endX, endY, onProjectileHit, spawnOpts)
    elseif projOpts and projOpts.useBasicProjectile and PS.hasHeroEffect(attacker.heroId) then
        PS.spawn(attacker.heroId, startX, startY, endX, endY, onProjectileHit, spawnOpts)
    elseif PS.hasSkillProjectile(attacker.heroId) then
        PS.spawnSkill(attacker.heroId, startX, startY, endX, endY, onProjectileHit, spawnOpts)
    elseif PS.hasHeroEffect(attacker.heroId) then
        PS.spawn(attacker.heroId, startX, startY, endX, endY, onProjectileHit, spawnOpts)
    else
        onProjectileHit()
    end
end

-- 单帧最多补发攻击次数。
-- 低帧/高攻速/倍速时，一帧内可能自然积压超过 8 次攻击；固定低上限会让战斗计时继续走、攻击却追不上，表现为丢伤害。
BattleCombat.MIN_ATTACKS_PER_FRAME = 8
BattleCombat.MAX_ATTACKS_PER_FRAME = 64

--- 推进攻击进度并在进度溢出时连续触发攻击（保留超出 1.0 的部分）
---@param unit table
---@param dt number
---@param interval number
---@param hasTarget boolean
---@param onAttack function
function BattleCombat.advanceAttackProgress(unit, dt, interval, hasTarget, onAttack)
    if interval <= 0 then interval = 0.01 end
    local nextProgress = (unit.atkProgress or 0) + dt / interval
    unit.atkProgress = nextProgress
    unit.atkProgressVisual = math.min(1.0, nextProgress)
    if not hasTarget then
        if unit.atkProgress >= 1.0 then
            unit.atkProgress = 1.0
        end
        unit.atkProgressVisual = unit.atkProgress
        return
    end
    local hits = 0
    local pendingHits = math.floor(unit.atkProgress)
    local maxHits = math.min(BattleCombat.MAX_ATTACKS_PER_FRAME, math.max(BattleCombat.MIN_ATTACKS_PER_FRAME, pendingHits))
    while unit.atkProgress >= 1.0 and hits < maxHits do
        unit.atkProgress = unit.atkProgress - 1.0
        onAttack()
        hits = hits + 1
    end
    if hits > 0 then
        -- 高攻速/低帧率下同一帧会直接完成一次或多次攻击，逻辑进度会被扣回小数。
        -- 绘制层保留本帧满格反馈，避免玩家看到进度条长期停在低值误以为角色不行动。
        unit.atkProgressVisual = 1.0
    else
        unit.atkProgressVisual = unit.atkProgress
    end
    if hits >= BattleCombat.MAX_ATTACKS_PER_FRAME and unit.atkProgress >= 1.0 then
        print(string.format("[BattleCombat] low FPS attack backlog capped: unit=%s pending=%d remain=%.2f dt=%.3f interval=%.3f",
            tostring(unit.name or unit.heroId or unit.monsterId or "?"), pendingHits, unit.atkProgress, dt, interval))
    end
end

-- ======================== 攻击逻辑 ========================

local _perfAtkDepth = 0   -- 递归/嵌套调用深度追踪
--- 执行一次攻�?
---@param attacker table
---@param targetList table
---@param isAlly boolean
local function performAttack(attacker, targetList, isAlly)
    _perfAtkDepth = _perfAtkDepth + 1
    local _curDepth = _perfAtkDepth
    local chosenIndex
    local allies  = BCS.ctx.getAllies()
    local enemies = BCS.ctx.getEnemies()
    local allyList = isAlly and allies or enemies

    -- 攻击目标数（配置表字段，默认 1�?
    local atkTargets = attacker.atkTargets or 1

    -- 治疗判断
    local isHealer = attacker.attrs
        and AD.getAtkCategory(attacker.attrs.atkType) == "healing"

    -- [HealDiag] 奶妈行动诊断（仅调试日志开启时）
    if isHealer and Diag.logEnabled then
        local candidates = collectHealCandidates(allyList)
        print(string.format("[HealDiag1] healer=%s candidates=%d allyCount=%d",
            tostring(attacker.name), #candidates, #allyList))
    end
    if not attacker.attrs then
        print("[BattleDiag] NO_ATTRS_ON_ATTACK attacker=" .. tostring(attacker.name)
            .. "(id" .. tostring(attacker.heroId or attacker.monsterId or "?") .. ")"
            .. " isAlly=" .. tostring(isAlly)
            .. " hp=" .. tostring(attacker.hp))
    end
    if isHealer then
        -- 治疗多目标：优先选择未满血/护盾的友军
        local candidates = collectHealCandidates(allyList)
        if #candidates == 0 then
            -- 全员满血时仍然治疗（溢出无害），随机选择一个可治疗的存活友军
            local alive = getHealableAliveUnits(allyList)
            if #alive == 0 then _perfAtkDepth = _perfAtkDepth - 1; return end
            chosenIndex = alive[math.random(#alive)].index
        else
            if Diag.logEnabled then
                local healerHealAmt = attacker.attrs and attacker.attrs:get(AD.HEAL_AMOUNT) or -1
                local diagParts = {"[HealDiag2] SELECT healer=" .. tostring(attacker.name)
                    .. "(id" .. tostring(attacker.heroId) .. ")"
                    .. " healAmt_attr=" .. tostring(healerHealAmt)
                    .. " atkType=" .. tostring(attacker.attrs and attacker.attrs.atkType or "nil")
                    .. " candidates=" .. #candidates}
                for ci = 1, math.min(#candidates, 4) do
                    local c = candidates[ci]
                    local cu = allyList[c.index]
                    local cuAttrHp = cu.attrs and cu.attrs.final[AD.HP] or -1
                    local cuAttrMax = cu.attrs and cu.attrs.final[AD.MAX_HP] or -1
                    diagParts[#diagParts + 1] = string.format(
                        " [%d]%s hp=%.0f/%.0f attrHp=%.0f/%.0f pct=%.2f",
                        c.index, tostring(cu.name), cu.hp or 0, cu.maxHp or 0,
                        cuAttrHp, cuAttrMax, c.pct)
                end
                print(table.concat(diagParts))
            end
            chosenIndex = candidates[1].index
        end
    else
        if not isAlly then
            chosenIndex = TM.selectTarget(targetList)
        elseif attacker.attrs then
            -- 决斗者天�? 锁定目标优先
            chosenIndex = TAL.getLockedTarget(attacker, targetList)
            if not chosenIndex then
                chosenIndex = CF.selectTarget(targetList)
            end
        end
        if not chosenIndex or chosenIndex == 0 then
            local alive = getAliveUnits(targetList)
            if #alive == 0 then _perfAtkDepth = _perfAtkDepth - 1; return end
            -- [前后排] 兜底随机也按位置加权
            local totalW = 0
            for _, entry in ipairs(alive) do
                entry.weight = BattleLayout.hitWeight(entry.index)
                totalW = totalW + entry.weight
            end
            local rollW = math.random() * totalW
            chosenIndex = alive[#alive].index
            for _, entry in ipairs(alive) do
                rollW = rollW - entry.weight
                if rollW <= 0 then chosenIndex = entry.index break end
            end
        end
    end

    local target = isHealer and allyList[chosenIndex] or targetList[chosenIndex]
    if not target or target.hp <= 0 then _perfAtkDepth = _perfAtkDepth - 1; return end

    -- 多目标：收集额外目标（排除主目标�?
    local extraTargetIndices = {}
    if atkTargets > 1 then
        local pool = isHealer and allyList or targetList
        if isHealer then
            -- 治疗多目标：额外目标优先选择最需要治疗的友军；候选不足时再随机补其他存活友军，避免固定偏向前排槽位
            local selected = { [chosenIndex] = true }
            local healCandidates = collectHealCandidates(pool, chosenIndex)
            for _, c in ipairs(healCandidates) do
                extraTargetIndices[#extraTargetIndices + 1] = c.index
                selected[c.index] = true
                if #extraTargetIndices >= atkTargets - 1 then break end
            end
            if #extraTargetIndices < atkTargets - 1 then
                local fallback = getHealableAliveUnits(pool, chosenIndex)
                for i = #fallback, 1, -1 do
                    if selected[fallback[i].index] then
                        table.remove(fallback, i)
                    end
                end
                shuffleList(fallback)
                for _, entry in ipairs(fallback) do
                    extraTargetIndices[#extraTargetIndices + 1] = entry.index
                    if #extraTargetIndices >= atkTargets - 1 then break end
                end
            end
        else
            -- 攻击多目标：按仇恨权重排序，取最高的 N-1 个（跳过主目标）
            local candidates = {}
            for i, u in ipairs(pool) do
                if u.hp > 0 and i ~= chosenIndex and not u.artifactUntargetable then
                    local dynamicThreat = TM.getThreat(u)
                    local staticThreat = 1
                    if u.attrs then
                        staticThreat = u.attrs:get(AD.THREAT)
                        if staticThreat < 1 then staticThreat = 1 end
                    end
                    -- [前后排] 乘以位置受击权重: 额外目标同样偏向后排
                    local weight = (dynamicThreat + staticThreat * TM.STATIC_THREAT_WEIGHT)
                        * BattleLayout.hitWeight(i)
                    candidates[#candidates + 1] = { index = i, weight = weight }
                end
            end
            table.sort(candidates, function(a, b) return a.weight > b.weight end)
            for ei = 1, math.min(atkTargets - 1, #candidates) do
                extraTargetIndices[#extraTargetIndices + 1] = candidates[ei].index
            end
        end
    end

    TAL.onBeforeAttack(attacker)

    -- 遗物条件词条：攻击前回调（初次攻击加成等）�?PVP 双向触发
    local rchDmgMult = RCH.onBeforeAttack(attacker)

    playAttackCardAnim(attacker, isAlly)

    -- 构建完整目标索引列表（主目标 + 额外目标�?
    local allTargetIndices = { chosenIndex }
    for _, ei in ipairs(extraTargetIndices) do
        allTargetIndices[#allTargetIndices + 1] = ei
    end

    -- 计算攻击者位置（所有目标共用）
    local atkIdx = findUnitIndex(allyList, attacker)
    local skipProjectile = false
    if atkIdx then
        attacker = allyList[atkIdx]
    else
        -- 增强重解析：�?resolveUnitInList 做最后尝�?
        local resolved, resolvedIdx = resolveUnitInList(allyList, attacker, {
            heroId     = attacker.heroId,
            instanceId = attacker.instanceId,
        })
        if resolved then
            attacker = resolved
            atkIdx   = resolvedIdx
        else
            -- 真正找不到：记录诊断，跳过投射物动画
            local freshRef = isAlly and BCS.ctx.getAllies() or BCS.ctx.getEnemies()
            Diag.onFindUnitFailed(attacker, allyList, isAlly, "performAttack", {
                ctxTableId = tostring(freshRef),
                callDepth  = _curDepth,
            })
            skipProjectile = true
        end
    end
    local atkCX, atkCY
    if atkIdx then
        atkCX, atkCY = getCardPos(allyList, atkIdx)
    else
        -- 使用列表中点作为伤害数字的显示位置（不发射投射物�?
        atkCX, atkCY = getCardPos(allyList, math.max(1, math.ceil(#allyList / 2)))
    end

    -- 累计总伤害（用于统一计算攻击吸血�?
    local totalDmgDealt = 0

    -- 多目标攻击：基础攻击仇恨每次出手只计算一次，伤害仇恨仍按每个目标分别计算
    local baseThreatCounted = false

    -- [单发穿透] 多目标攻击收集为一次穿透弹的命中事件（替代逐目标各丢一弹）
    local piercePack = nil
    if atkTargets > 1 and not isHealer and not skipProjectile and BCS.ctx.onPierceAttack then
        piercePack = { events = {} }
    end

    -- 连击必须在主伤害 applyHit 落地后再排队（避免投射物未到时连击先触发，与弹射叠在一起像误触发）
    local comboDelayStep = LUNGE_DURATION + RETURN_DURATION + 0.05
    local function queueComboAfterHit(curIndex, curTarget, comboCount)
        if isHealer or not comboCount or comboCount <= 0 or not curTarget then return end
        for chi = 1, comboCount do
            BCS.comboQueue[#BCS.comboQueue + 1] = {
                attacker      = attacker,
                isAlly        = isAlly,
                targetIsAlly  = not isAlly,
                comboHitIndex = chi,
                targetIndex   = curIndex,
                delay         = comboDelayStep * chi,
                timer         = 0,
                atkStableId = {
                    heroId     = attacker.heroId,
                    instanceId = attacker.instanceId,
                },
                targetRef   = curTarget,
                tgtStableId = {
                    heroId     = curTarget.heroId,
                    instanceId = curTarget.instanceId,
                },
            }
        end
    end

    -- 对每个目标独立执行攻�?
    for ti, curIndex in ipairs(allTargetIndices) do
        local tgtList = isHealer and allyList or targetList
        local curTarget = tgtList[curIndex]
        if curTarget and curTarget.hp > 0 then

            local useFormula = attacker.attrs and curTarget.attrs

            if useFormula then
                local result = CF.calcAttack(attacker.attrs, curTarget.attrs)

                -- 治疗目标与攻击者同侧；普通攻击目标在对面
                local tgtIsAlly
                if isHealer then
                    tgtIsAlly = isAlly
                else
                    tgtIsAlly = not isAlly
                end
                local tgtCX, tgtCY = getCardPos(tgtList, curIndex)

                if result.isMiss then
                    addFloatingText("MISS", tgtCX, tgtCY, { 255, 122, 122 }, false)
                    setRecoil(curTarget, isAlly and -1 or 1)
                    -- 遗物条件词条：触发闪避时仇恨值减少（被攻击方闪避）�?PVP 双向触发
                    if curTarget then
                        RCH.onDodge(curTarget)
                        ART.onDodge(curTarget)
                    end
                    -- miss 不中断，继续攻击下一个目�?
                elseif result.category == "healing" then
                    if Diag.logEnabled and (result.healAmount or 0) <= 0 then
                        local atkHealAmt = attacker.attrs and attacker.attrs:get(AD.HEAL_AMOUNT) or -1
                        local atkHealBase = attacker.attrs and attacker.attrs:getBase(AD.HEAL_AMOUNT) or -1
                        print(string.format(
                            "[HealDiag3] HEAL_RESULT_ZERO healer=%s(id%s) target=%s"
                            .. " result.healAmount=%s atkHealAmt=%.1f atkHealBase=%.1f"
                            .. " atkCoeff=%.2f hasAttrs=%s",
                            tostring(attacker.name), tostring(attacker.heroId),
                            tostring(curTarget.name),
                            tostring(result.healAmount),
                            atkHealAmt, atkHealBase,
                            attacker.attrs and attacker.attrs.atkCoeff or -1,
                            tostring(attacker.attrs ~= nil)
                        ))
                    end
                    local curTgt = curTarget  -- 闭包捕获（可能陈旧）
                    local curTgtCX, curTgtCY = tgtCX, tgtCY
                    -- 存储稳定标识，用于飞行期间列表被替换后重新解析
                    local tgtStableId = {
                        heroId     = curTarget.heroId,
                        instanceId = curTarget.instanceId,
                    }
                    local function applyHealHit()
                        -- 重新解析目标引用（防止 setAllies 替换列表后旧引用失效）
                        local liveAllyList = isAlly and BCS.ctx.getAllies() or BCS.ctx.getEnemies()
                        local resolved, resolvedIdx = resolveUnitInList(liveAllyList, curTgt, tgtStableId)
                        if resolved then
                            curTgt = resolved
                            curTgtCX, curTgtCY = getCardPos(liveAllyList, resolvedIdx)
                        end
                        -- 投射物飞行期间，目标可能已死亡、禁疗或被副本机制禁疗；落地时检查是否需要重选
                        -- 注意：目标HP满但护盾不满时不重选（仍然治疗原目标，溢出无害）
                        local tgtDead = not curTgt or (curTgt.hp or 0) <= 0
                        local tgtBlocked = not tgtDead and ((DungeonBattle and DungeonBattle.isHealBlocked and DungeonBattle.isHealBlocked(curTgt)) or not ART.canHeal(curTgt))
                        if tgtDead or tgtBlocked then
                            local liveAllyList = isAlly and BCS.ctx.getAllies() or BCS.ctx.getEnemies()
                            local retargetCandidates = collectHealCandidates(liveAllyList)
                            if #retargetCandidates == 0 then
                                -- 无需补血目标时仍对任意可治疗的活着友军治疗（溢出无害）
                                local alive = getHealableAliveUnits(liveAllyList)
                                if #alive == 0 then return end
                                local fallback = alive[math.random(#alive)]
                                curTgt = liveAllyList[fallback.index]
                                curTgtCX, curTgtCY = getCardPos(liveAllyList, fallback.index)
                            else
                                local retarget = retargetCandidates[1]
                                curTgt = liveAllyList[retarget.index]
                                curTgtCX, curTgtCY = getCardPos(liveAllyList, retarget.index)
                            end
                        end
                        if not curTgt.attrs then
                            Diag.onAttrsNil(curTgt, "applyHealHit")
                            return
                        end
                        local healAmt = result.healAmount or 0
                        if not ART.canHeal(curTgt) then
                            healAmt = 0
                        end
                        -- 副本职业加成（治疗）
                        local dungeonHealMult = DungeonBattle.getDamageMultiplier(attacker)
                        if dungeonHealMult > 1.0 then
                            healAmt = math.floor(healAmt * dungeonHealMult)
                        end
                        -- 地图词缀：治疗荒漠 — 削弱治疗加成
                        local healReduce = MAS.getHealReduce()
                        if healReduce > 0 then
                            healAmt = math.floor(healAmt * (1 - healReduce) + 0.5)
                        end
                        -- [HealDiag2] 记录治疗前完整状�?
                        local preUnitHp = curTgt.hp
                        local preUnitMaxHp = curTgt.maxHp
                        local preAttrHp = curTgt.attrs.final[AD.HP] or -1
                        local preAttrMaxHp = curTgt.attrs.final[AD.MAX_HP] or -1
                        local desync = math.abs(preUnitHp - preAttrHp) > 1
                        local actual = curTgt.attrs:heal(healAmt)
                        result.appliedHealAmount = actual
                        result.overhealAmount = math.max(0, healAmt - actual)
                        if Diag.logEnabled then
                            print(string.format(
                                "[HealDiag2] HEAL healer=%s(id%s) target=%s healAmt=%.0f actual=%.0f"
                                .. " pre_unitHp=%.0f/%.0f pre_attrHp=%.0f/%.0f desync=%s frac=%.3f"
                                .. " post_attrHp=%.0f",
                                tostring(attacker.name), tostring(attacker.heroId),
                                tostring(curTgt.name), healAmt, actual,
                                preUnitHp, preUnitMaxHp or 0,
                                preAttrHp, preAttrMaxHp,
                                tostring(desync),
                                curTgt.attrs._healFrac or 0,
                                curTgt.attrs.final[AD.HP] or -1
                            ))
                        end
                        if actual == 0 and healAmt > 0 then
                            Diag.onHealZero(attacker, curTgt, healAmt, actual, "applyHealHit")
                        end
                        syncUnitHp(curTgt)
                        -- 飘字只显示绿色 +数值（暴击放大），无需"治疗"说明
                        local color = { 0, 255, 82 }
                        addFloatingText("+" .. NumberUtil.format(actual), curTgtCX, curTgtCY, color, result.isCrit)
                        setHitFlash(curTgt)
                        if isAlly and actual > 0 then
                            TM.onHealingDone(attacker, actual)
                            BattleStats.recordHeal(attacker, actual, false)  -- 战斗统计：己方治疗输出
                        end
                        -- 治疗触发的伤害天赋（惩戒飞弹等）可复用遗物初次攻击增伤
                        result._talentDmgMult = 1.0
                        if rchDmgMult and rchDmgMult > 1.0 then
                            result._talentDmgMult = result._talentDmgMult * rchDmgMult
                        end
                        -- 治疗也触发 onAfterAttack（天赋后续处理，支持投射物如惩戒飞弹）
                        TAL.onAfterAttack(attacker, curTgt, result, isAlly, targetList, function(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
                            local meta = statMetaFromProjOpts(projOpts)
                            local function doTalentDamage()
                                local sourceAttacker = (projOpts and projOpts.sourceAttacker) or attacker
                                dealDamageToUnit(tgt, dmg, isTgtAlly, pfx or "", clr or {255, 238, 96}, sourceAttacker, meta)
                            end

                            if BCS.ctx.onTalentDealDamage then
                                local lookupList = (isAlly == isTgtAlly) and allyList or targetList
                                for li, lu in ipairs(lookupList) do
                                    if lu == tgt then
                                        local tdCX, tdCY = getCardPos(lookupList, li)
                                        local sourceAttacker = (projOpts and projOpts.sourceAttacker) or attacker
                                        BCS.ctx.onTalentDealDamage(sourceAttacker, tgt, tdCX, tdCY, pfx, doTalentDamage, projOpts)
                                        break
                                    end
                                end
                            else
                                doTalentDamage()
                            end
                        end, allyList)
                    end

                    -- 通知 BattleScene：由场景决定是否通过投射物延迟治�?
                    if skipProjectile then
                        applyHealHit()  -- 攻击者不可寻址，跳过投射物动画直接生效
                    elseif BCS.ctx.onAttackHit then
                        BCS.ctx.onAttackHit(attacker, curTgt, atkCX, atkCY, curTgtCX, curTgtCY, result, applyHealHit)
                    else
                        applyHealHit()
                    end
                else
                    local curTgt = curTarget  -- 闭包捕获
                    local curTgtCX, curTgtCY = tgtCX, tgtCY
                    local tgtStableId = {
                        heroId     = curTarget.heroId,
                        instanceId = curTarget.instanceId,
                    }

                    -- 将伤害应用包装成闭包，支持投射物延迟伤害
                    local function applyHit()
                        local liveTargetList
                        if isAlly then
                            liveTargetList = BCS.ctx.getEnemies and BCS.ctx.getEnemies() or targetList
                        else
                            liveTargetList = BCS.ctx.getAllies and BCS.ctx.getAllies() or targetList
                        end
                        local resolved, resolvedIdx = resolveDamageTarget(liveTargetList, curTgt, tgtStableId, attacker, isAlly)
                        if not resolved then
                            return
                        end
                        curTgt = resolved
                        local targetIsAlly = not isAlly                        curTgtCX, curTgtCY = getCardPos(liveTargetList, resolvedIdx)
                        if not curTgt.attrs then
                            Diag.onAttrsNil(curTgt, "applyHit")
                            return
                        end
                        local semMult = SEM.getDamageTakenMult(curTgt)
                        local hpBefore = curTgt.hp
                        local hit = result.hits[1]
                        -- 地图词缀：厚重鳞甲 — 己方攻击怪物时概率压制暴击
                        if isAlly and hit.isCrit and MAS.shouldSuppressCrit() then
                            hit.isCrit = false
                            result.isCrit = false
                            -- 还原伤害：移除暴击倍率
                            if hit.critMult and hit.critMult > 0 then
                                hit.damage = math.max(1, math.floor(hit.damage / hit.critMult + 0.5))
                            end
                            result.totalDamage = hit.damage
                        end
                        local finalDmg = (semMult ~= 1.0) and math.floor(hit.damage * semMult) or hit.damage

                        -- 遗物条件词条：攻击增伤（初次攻击 + 对低血量目标增伤）�?PVP 双向触发
                        if rchDmgMult > 1.0 then
                            finalDmg = math.floor(finalDmg * rchDmgMult)
                        end
                        local rchBonus = RCH.getDamageBonus(attacker, curTgt)
                        if rchBonus > 0 then
                            finalDmg = math.floor(finalDmg * (1 + rchBonus / 100))
                        end

                        -- 副本职业加成 + 通天塔攻击强化
                        local dungeonMult = DungeonBattle.getDamageMultiplier(attacker, curTgt)
                        if dungeonMult > 1.0 then
                            finalDmg = math.floor(finalDmg * dungeonMult)
                        end

                        -- 通天塔受击免疫（显式消费）与减伤倍率
                        if DungeonBattle.consumeDamageImmunity and DungeonBattle.consumeDamageImmunity(curTgt) then
                            addFloatingText("免疫", curTgtCX, curTgtCY, {200, 200, 255}, false)
                            setRecoil(curTgt, isAlly and -1 or 1)
                            return
                        end
                        local towerTakenMult = DungeonBattle.getDamageTakenMultiplier(curTgt)
                        if towerTakenMult < 1.0 then
                            finalDmg = math.floor(finalDmg * towerTakenMult)
                        end

                        -- 遗物条件词条：受击免疫（战斗开始免疫N次伤害）�?PVP 双向触发
                        finalDmg = RCH.onBeforeTakeDamage(curTgt, finalDmg)
                        if finalDmg <= 0 then
                            addFloatingText("免疫", curTgtCX, curTgtCY, {200, 200, 255}, false)
                            setRecoil(curTgt, isAlly and -1 or 1)
                            return
                        end

                        finalDmg = applyGlobalDmgMult(finalDmg)
                        -- 地图词缀：怪物攻击加成（衰败之地 + 濒死狂怒 + 生命猎手）
                        if not isAlly then
                            local affixMult = 1.0 + MAS.getDecayDamageBonus() + MAS.getBerserkDmgBonus(attacker)
                            local lifeBonus = MAS.getLifeHunterBonus()
                            if lifeBonus > 0 and curTgt.attrs then
                                -- 生命猎手：只对HP部分增伤（护盾吸收后的剩余）
                                local es = curTgt.attrs.energyShield or 0
                                if es <= 0 then
                                    affixMult = affixMult + lifeBonus
                                end
                            end
                            if affixMult > 1.0 then
                                finalDmg = math.floor(finalDmg * affixMult + 0.5)
                            end
                        end
                        -- 铁憨憨帝国铁壁：拦截队友伤害（takeDamage前）
                        local tgtIsAllyForAbsorb = not isAlly
                        if isHealer then tgtIsAllyForAbsorb = isAlly end
                        finalDmg = TAL.modifyDamageForTarget(curTgt, finalDmg, tgtIsAllyForAbsorb, syncUnitHp, result.category)
                        finalDmg = ART.onBeforeTakeDamage(curTgt, attacker, finalDmg, tgtIsAllyForAbsorb)
                        result.damageDealt = finalDmg
                        local shieldBefore = (curTgt.attrs.energyShield or 0) + (curTgt.attrs.tempEnergyShield or 0)
                        local actual = curTgt.attrs:takeDamage(finalDmg)
                        local shieldAfter = (curTgt.attrs.energyShield or 0) + (curTgt.attrs.tempEnergyShield or 0)
                        local takenForStats = actual + math.max(0, shieldBefore - shieldAfter)
                        ART.checkShieldBreak(curTgt, shieldBefore)
                        syncUnitHp(curTgt)

                        -- 地图词缀钩子：怪物攻击命中己方 → 蚀甲叠层；己方攻击命中怪物 → 濒死检测
                        if not isAlly then
                            MAS.onAllyHit(curTgt)
                        else
                            MAS.onEnemyDamaged(curTgt)
                        end

                        -- 飘字配色：普通白色 / 暴击红色（物理魔法不再分色，格挡由前缀表达）
                        local prefix = ""
                        if hit.isCrit then
                            prefix = "暴击 "
                        end
                        if hit.isBlocked then
                            prefix = prefix .. "格挡 "
                        end

                        addFloatingText(prefix .. "-" .. NumberUtil.format(actual), curTgtCX, curTgtCY,
                            hit.isCrit and { 255, 60, 60 } or { 255, 255, 255 }, hit.isCrit)

                        -- 暴击回调（供台词系统触发暴击台词�?
                        if hit.isCrit and BCS.ctx.onCrit then
                            BCS.ctx.onCrit(attacker, isAlly)
                        end

                        if curTgt.hp <= 0 and hpBefore > 0 then
                            local totalRawDmg = result.totalDamage * semMult
                            local overkill = math.max(0, totalRawDmg - hpBefore)
                            curTgt._overkillRatio = math.min(1.0, overkill / (curTgt.maxHp or hpBefore))
                            -- 击杀归因标记（供台词系统触发击杀台词�?
                            curTgt._killedBy = attacker
                        end

                        setRecoil(curTgt, isAlly and -1 or 1)
                        setHitFlash(curTgt)
                        if actual > 0 then require("systems.GameSFX").play("hit") end

                        if isAlly then
                            local includeBaseThreat = not baseThreatCounted
                            TM.onDamageDealt(attacker, result.totalDamage, includeBaseThreat)
                            if includeBaseThreat then baseThreatCounted = true end
                        end
                        -- 遗物条件词条：攻击后仇恨加成（每次攻击获得仇恨�?X%）�?PVP 双向触发
                        RCH.onAfterAttack(attacker, result.totalDamage)
                        -- 遗物条件词条：终结机制（攻击低血量敌人有概率秒杀）�?PVP 双向触发
                        if curTgt.hp > 0 then
                            local executed = RCH.onAfterHit(attacker, curTgt)
                            if not executed then
                                -- 通天塔斩杀判定
                                executed = DungeonBattle.checkExecute(curTgt)
                            end
                            if executed then
                                local killDmg = curTgt.hp
                                curTgt.attrs:takeDamage(killDmg)
                                syncUnitHp(curTgt)
                                addFloatingText("终结!", curTgtCX, curTgtCY, {255, 50, 50}, true)
                                curTgt._overkillRatio = 0.5
                                curTgt._killedBy = attacker
                                BCS.unitDamageAccum[attacker] = (BCS.unitDamageAccum[attacker] or 0) + killDmg
                                if isAlly and killDmg > 0 then
                                    BattleStats.recordDamage(attacker, killDmg, result.category, false, false)
                                end
                            end
                        end

                        -- 通天塔击杀回调（斩杀狂潮/战意凝聚层数）
                        if curTgt.hp <= 0 and hpBefore > 0 then
                            DungeonBattle.onEnemyKill(attacker)
                            -- 地图词缀：复仇之誓 — 己方击杀怪物时，剩余怪物额外攻击一次
                            if isAlly and MAS.onEnemyKilled() then
                                local allyList = isAlly and allies or enemies
                                for _, remainEnemy in ipairs(enemies) do
                                    if remainEnemy.hp > 0 then
                                        performAttack(remainEnemy, allyList, false)
                                        break  -- 每次击杀只触发一轮（避免连锁爆炸）
                                    end
                                end
                            end
                        end

                        totalDmgDealt = totalDmgDealt + result.totalDamage
                        -- 累计伤害统计（结算面板用�?
                        BCS.unitDamageAccum[attacker] = (BCS.unitDamageAccum[attacker] or 0) + takenForStats

                        -- 战斗统计面板：己方输出 / 己方承伤
                        if isAlly then
                            BattleStats.recordDamage(attacker, takenForStats, result.category, hit.isCrit)
                        else
                            BattleStats.recordTaken(curTgt, takenForStats)
                        end

                        result.actualDamage = actual

                        local counterAttacks = ART.consumeCounterAttacks(curTgt)
                        if counterAttacks then
                            for _, counter in ipairs(counterAttacks) do
                                if counter.target and counter.target.hp and counter.target.hp > 0 then
                                    dealDamageToUnit(counter.target, counter.damage or 0, counter.isTargetAlly, "反击 ", {255, 180, 60}, curTgt, {
                                        category = result.category,
                                        threatScale = 0,
                                        noCounter = true,
                                    })
                                end
                            end
                        end

                        local tgtIsAlly2 = not isAlly
                        if isHealer then tgtIsAlly2 = isAlly end
   TAL.onDamageTaken(curTgt, attacker, result.totalDamage, tgtIsAlly2, performAttack, isAlly and allies or enemies, result)

                        -- Store talent damage multipliers for talent procs using raw stats (e.g., Arcane Missile)
                        result._talentDmgMult = 1.0
                        if rchDmgMult and rchDmgMult > 1.0 then
                            result._talentDmgMult = result._talentDmgMult * rchDmgMult
                        end
                        if rchBonus and rchBonus > 0 then
                            result._talentDmgMult = result._talentDmgMult * (1 + rchBonus / 100)
                        end
                        if dungeonMult and dungeonMult > 1.0 then
                            result._talentDmgMult = result._talentDmgMult * dungeonMult
                        end
                        ART.onAfterAttack(attacker, curTgt, result)
                        TAL.onAfterAttack(attacker, curTgt, result, isAlly, targetList, function(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
                            -- 封装实际伤害为回调，支持延迟（投射物到达后执行）
                            local meta = statMetaFromProjOpts(projOpts)
                            local function doTalentDamage()
                                local sourceAttacker = (projOpts and projOpts.sourceAttacker) or attacker
                                dealDamageToUnit(tgt, dmg, isTgtAlly, pfx or "", clr or {255, 238, 96}, sourceAttacker, meta)
                            end

                            if BCS.ctx.onTalentDealDamage then
                                -- 查找目标位置
                                local lookupList = (isAlly == isTgtAlly) and allyList or targetList
                                for li, lu in ipairs(lookupList) do
                                    if lu == tgt then
                                        local tdCX, tdCY = getCardPos(lookupList, li)
                                        -- 由场景决定立�?延迟：传�?doTalentDamage 作为伤害回调
                                        local sourceAttacker = (projOpts and projOpts.sourceAttacker) or attacker
                                        BCS.ctx.onTalentDealDamage(sourceAttacker, tgt, tdCX, tdCY, pfx, doTalentDamage, projOpts)
                                        break
                                    end
                                end
                            else
                                doTalentDamage()
                            end
                        end, allyList)

                        -- 主伤害与弹射天赋处理完毕后再排连击（弹射本身不 roll 连击）
                        if result.comboCount and result.comboCount > 0 and not result.isMiss then
                            queueComboAfterHit(curIndex, curTgt, result.comboCount)
                        end
                    end

                    -- 通知 BattleScene：由场景决定立即/延迟伤害
                    if skipProjectile then
                        applyHit()  -- 攻击者不可寻址，跳过投射物动画直接生效
                    elseif piercePack then
                        -- [单发穿透] 只收集结算事件, 由一发穿透弹沿线依次触发
                        piercePack.events[#piercePack.events + 1] = {
                            target = curTgt,
                            tgtCX  = curTgtCX,
                            tgtCY  = curTgtCY,
                            result = result,
                            applyHit = applyHit,
                        }
                    elseif BCS.ctx.onAttackHit then
                        BCS.ctx.onAttackHit(attacker, curTgt, atkCX, atkCY, curTgtCX, curTgtCY, result, applyHit)
                    else
                        applyHit()
                    end
                end
            else
                -- 兜底：无 attrs 简化伤�?
                print("[BattleDiag] FALLBACK_PATH attacker=" .. tostring(attacker.name)
                    .. "(id" .. tostring(attacker.heroId or attacker.monsterId or "?") .. ")"
                    .. " atkAttrs=" .. tostring(attacker.attrs ~= nil)
                    .. " target=" .. tostring(curTarget.name)
                    .. "(id" .. tostring(curTarget.heroId or curTarget.monsterId or "?") .. ")"
                    .. " tgtAttrs=" .. tostring(curTarget.attrs ~= nil)
                    .. " isAlly=" .. tostring(isAlly))
                local hpBefore = curTarget.hp
                local baseDmg = 15 + math.random(10)
                local isCrit = math.random() < 0.15
                if isCrit then baseDmg = math.floor(baseDmg * 2) end
                local actualDmg = math.min(curTarget.hp, baseDmg)
                curTarget.hp = curTarget.hp - actualDmg
                -- FIX: 同步 attrs.final[HP]，防�?unit.hp �?attrs 脱节导致治疗失效
                if curTarget.attrs then
                    curTarget.attrs.final[AD.HP] = math.max(0, curTarget.hp)
                end
                -- 累计伤害统计（结算面板用�?
                BCS.unitDamageAccum[attacker] = (BCS.unitDamageAccum[attacker] or 0) + actualDmg
                if curTarget.hp <= 0 and hpBefore > 0 then
                    local overkill = math.max(0, baseDmg - hpBefore)
                    curTarget._overkillRatio = math.min(1.0, overkill / (curTarget.maxHp or hpBefore))
                end

                local tgtCX, tgtCY = getCardPos(targetList, curIndex)
                -- 伤害飘字配色：普通白色 / 暴击红色
                local ftColor = isCrit and { 255, 60, 60 } or { 255, 255, 255 }
                addFloatingText(
                    (isCrit and "暴击 " or "") .. "-" .. NumberUtil.format(actualDmg),
                    tgtCX, tgtCY, ftColor, isCrit
                )
                setRecoil(curTarget, isAlly and -1 or 1)
                setHitFlash(curTarget)
                if actualDmg > 0 then require("systems.GameSFX").play("hit") end

                if isAlly then
                    local includeBaseThreat = not baseThreatCounted
                    TM.onDamageDealt(attacker, actualDmg, includeBaseThreat)
                    if includeBaseThreat then baseThreatCounted = true end
                end
            end
        end -- curTarget alive check
    end -- target loop

    -- [单发穿透] 目标收集完毕 → 发射一发穿透弹（无收集/无宿主支持时各目标已走原路径）
    if piercePack and #piercePack.events > 0 then
        BCS.ctx.onPierceAttack(attacker, atkCX, atkCY, piercePack)
    end

    -- 攻击吸血（所有目标伤害合计后统一计算一次）
    if totalDmgDealt > 0 and attacker.hp > 0 and attacker.attrs and ART.canHeal(attacker) then
        local atkHeal = CF.calcAtkHeal(attacker.attrs)
        if atkHeal > 0 then
            local healActual = attacker.attrs:heal(atkHeal)
            syncUnitHp(attacker)
            if healActual > 0 then
                -- 直接复用上方 resolveUnitInList 返回�?atkIdx
                local aCX, aCY = getCardPos(allyList, atkIdx or math.max(1, math.ceil(#allyList / 2)))
                addFloatingText("+" .. NumberUtil.format(math.floor(healActual)), aCX, aCY, { 0, 255, 82 }, false)
            end
        end
    end

    _perfAtkDepth = _perfAtkDepth - 1
end
BattleCombat.performAttack = performAttack

-- ======================== 连击额外攻击 ========================

--- 执行一次连击额外攻击（完整动画+投射�?伤害�?
---@param entry table 连击队列条目
local function performComboAttack(entry)
    local isAlly        = entry.isAlly
    local comboHitIndex = entry.comboHitIndex

    -- ══�?从当前上下文重新获取列表 ══�?
    local allies  = BCS.ctx.getAllies()
    local enemies = BCS.ctx.getEnemies()
    local allyList = isAlly and allies or enemies

    -- 使用 targetIsAlly 确定目标列表（支持治疗扩展）
    local tgtIsAlly  = entry.targetIsAlly
    if tgtIsAlly == nil then tgtIsAlly = not isAlly end  -- 兼容旧格式队列条�?
    local targetList = tgtIsAlly and allies or enemies

    -- ══�?重新解析攻击�?══�?
    local attacker, atkIdx = resolveUnitInList(
        allyList, entry.attacker, entry.atkStableId
    )
    if not attacker or attacker.hp <= 0 then
        return  -- 攻击者已死或已不在场，取消连�?
    end

    -- ══�?重新解析目标 ══�?
    local curTarget, tgtIdx = resolveDamageTarget(
        targetList, entry.targetRef, entry.tgtStableId, attacker, isAlly
    )
    if not curTarget then
        return  -- 没有可命中的目标，取消连击
    end

    -- ══�?校验 attrs（连击必须走公式路径�?══�?
    if not attacker.attrs or not curTarget.attrs then
        return
    end

    -- ══�?计算位置（使用实际索引，resolveUnitInList 成功时保证非 nil�?══�?
    local atkCX, atkCY = getCardPos(allyList, atkIdx)    local tgtCX, tgtCY = getCardPos(targetList, tgtIdx)

    -- 播放攻击动画（lunge + return�?
    playAttackCardAnim(attacker, isAlly)

    -- 计算伤害（带连击增伤�?
    local result = CF.calcAttack(attacker.attrs, curTarget.attrs, nil, comboHitIndex)

    if result.isMiss then
        addFloatingText("MISS", tgtCX, tgtCY, { 255, 122, 122 }, false)
        setRecoil(curTarget, isAlly and -1 or 1)
        ART.onDodge(curTarget)
        return
    end

    -- ══�?applyComboHit 闭包变量映射 ══�?
    -- curTgt     = curTarget  (解析后的最新引用，�?BCS.cardAnims key 一�?
    -- curTgtCX   = tgtCX      (当前帧位�?
    -- curTgtCY   = tgtCY
    -- attacker   = attacker   (解析后的最新引�?
    -- allyList   = allyList   (当前帧列表，用于吸血位置计算)
    -- atkIdx     = atkIdx     (解析返回的索引，用于吸血浮字位置)
    -- result     = result     (本次攻击计算结果)
    local curTgt = curTarget
    local curTgtCX, curTgtCY = tgtCX, tgtCY

    local function applyComboHit()
        local liveTargetList
        if tgtIsAlly then
            liveTargetList = BCS.ctx.getAllies and BCS.ctx.getAllies() or targetList
        else
            liveTargetList = BCS.ctx.getEnemies and BCS.ctx.getEnemies() or targetList
        end
        targetList = liveTargetList
        local resolved, resolvedIdx = resolveDamageTarget(liveTargetList, curTgt, entry.tgtStableId, attacker, isAlly)
        if not resolved then return end
        curTgt = resolved
        curTgtCX, curTgtCY = getCardPos(liveTargetList, resolvedIdx)
        if not result.hits or not result.hits[1] then return end
        local semMult = SEM.getDamageTakenMult(curTgt)
        local hpBefore = curTgt.hp
        local hit = result.hits[1]
        local finalDmg = (semMult ~= 1.0) and math.floor(hit.damage * semMult) or hit.damage
        finalDmg = applyGlobalDmgMult(finalDmg)
        -- 铁憨憨帝国铁壁：拦截队友伤害（连击目标与主攻击一致）
        local comboTgtIsAlly = not isAlly
        finalDmg = TAL.modifyDamageForTarget(curTgt, finalDmg, comboTgtIsAlly, syncUnitHp, result.category)
        result.damageDealt = finalDmg
        local shieldBefore = (curTgt.attrs.energyShield or 0) + (curTgt.attrs.tempEnergyShield or 0)
        local actual = curTgt.attrs:takeDamage(finalDmg)
        local shieldAfter = (curTgt.attrs.energyShield or 0) + (curTgt.attrs.tempEnergyShield or 0)
        local takenForStats = actual + math.max(0, shieldBefore - shieldAfter)
        ART.checkShieldBreak(curTgt, shieldBefore)
        syncUnitHp(curTgt)

        local baseColor = (result.category == "magical")
            and { 113, 253, 255 } or { 255, 238, 96 }
        local prefix = ""
        local color  = baseColor
        if hit.isCrit then
            prefix = "暴击 "
        end
        if hit.isBlocked then
            prefix = prefix .. "格挡 "
            color  = { 180, 180, 180 }
        end

        addFloatingText(prefix .. "-" .. NumberUtil.format(actual), curTgtCX, curTgtCY, color, hit.isCrit)

        if curTgt.hp <= 0 and hpBefore > 0 then
            local overkill = math.max(0, finalDmg - hpBefore)
            curTgt._overkillRatio = math.min(1.0, overkill / (curTgt.maxHp or hpBefore))
        end

        setRecoil(curTgt, isAlly and -1 or 1)
        setHitFlash(curTgt)
        if actual > 0 then require("systems.GameSFX").play("hit") end
        -- 累计伤害统计（结算面板用�?
        BCS.unitDamageAccum[attacker] = (BCS.unitDamageAccum[attacker] or 0) + takenForStats

        -- 战斗统计面板：己方输出 / 己方承伤
        if isAlly then
            BattleStats.recordDamage(attacker, takenForStats, result.category, hit.isCrit)
        else
            BattleStats.recordTaken(curTgt, takenForStats)
        end

        if isAlly then
            TM.onDamageDealt(attacker, result.totalDamage)
        end

        -- 攻击吸血
        if actual > 0 and attacker.hp > 0 and attacker.attrs and ART.canHeal(attacker) then
            local atkHeal = CF.calcAtkHeal(attacker.attrs)
            if atkHeal > 0 then
                local healActual = attacker.attrs:heal(atkHeal)
                syncUnitHp(attacker)
                if healActual > 0 then
                    local aCX, aCY = getCardPos(allyList, atkIdx)
                    addFloatingText("+" .. NumberUtil.format(math.floor(healActual)), aCX, aCY, { 0, 255, 82 }, false)
                end
            end
        end

        -- 连击命中后：让按攻击计数触发的天赋（如熬夜冠军夜华斩）也能被连击推进/触发（仅对应英雄生效）
        TAL.onComboAttack(attacker, curTgt, isAlly, targetList, function(tgt, dmg, isTgtAlly, pfx, clr, projOpts)
            local meta = statMetaFromProjOpts(projOpts)
            local function doTalentDamage()
                local sourceAttacker = (projOpts and projOpts.sourceAttacker) or attacker
                dealDamageToUnit(tgt, dmg, isTgtAlly, pfx or "", clr or { 255, 238, 96 }, sourceAttacker, meta)
            end
            if BCS.ctx.onTalentDealDamage then
                local lookupList = (isAlly == isTgtAlly) and allyList or targetList
                for li, lu in ipairs(lookupList) do
                    if lu == tgt then
                        local tdCX, tdCY = getCardPos(lookupList, li)
                        local sourceAttacker = (projOpts and projOpts.sourceAttacker) or attacker
                        BCS.ctx.onTalentDealDamage(sourceAttacker, tgt, tdCX, tdCY, pfx, doTalentDamage, projOpts)
                        break
                    end
                end
            else
                doTalentDamage()
            end
        end, {
            damageDealt = finalDmg,
            totalDamage = actual,
            category = result.category,
            isCrit = hit.isCrit,
        })
    end

    -- 通知 BattleScene（投射物/受击特效�?
    if BCS.ctx.onAttackHit then
        BCS.ctx.onAttackHit(attacker, curTgt, atkCX, atkCY, curTgtCX, curTgtCY, result, applyComboHit)
    else
        applyComboHit()
    end
end

--- 更新连击队列（每帧调用）
function BattleCombat.updateComboQueue(dt)
    local i = 1
    while i <= #BCS.comboQueue do
        local entry = BCS.comboQueue[i]
        entry.timer = entry.timer + dt
        if entry.timer >= entry.delay then
            performComboAttack(entry)
            table.remove(BCS.comboQueue, i)
        else
            i = i + 1
        end
    end
end

-- ======================== 动画状态机 ========================

--- 更新卡片攻击动画
function BattleCombat.updateCardAnims(dt)
    local toRemove = {}
    for unit, anim in pairs(BCS.cardAnims) do
        if not isCombatCardAnimEnabled() and isCombatCardAnimState(anim.state) then
            toRemove[#toRemove + 1] = unit
            goto continue
        end
        -- delay 处理（入场交错延迟）
        if anim.delay and anim.delay > 0 then
            anim.delay = anim.delay - dt
            if anim.delay > 0 then
                goto continue
            end
            -- delay 刚结束，把超出的时间加到 timer
            anim.timer = anim.timer + (-anim.delay)
            anim.delay = 0
            goto skip_timer
        end
        anim.timer = anim.timer + dt
        ::skip_timer::
        if anim.state == "entering" then
            if anim.timer >= ENTER_ANIM_DURATION then
                toRemove[#toRemove + 1] = unit
            end
        elseif anim.state == "lunge" then
            if anim.timer >= LUNGE_DURATION then
                anim.state = "return"
                anim.timer = 0
            end
        elseif anim.state == "return" then
            if anim.timer >= RETURN_DURATION then
                toRemove[#toRemove + 1] = unit
            end
        elseif anim.state == "recoil" then
            if anim.timer >= RECOIL_DURATION then
                anim.state = "recoil_return"
                anim.timer = 0
            end
        elseif anim.state == "recoil_return" then
            if anim.timer >= RECOIL_RETURN then
                toRemove[#toRemove + 1] = unit
            end
        elseif anim.state == "dying" then
            if anim.timer >= DEATH_ANIM_DURATION then
                if anim.noTombstone then
                    anim.state = "gone"   -- [死亡即补位] 退场完成 → 空位期（完全隐藏，等待新怪从右补入）
                else
                    anim.state = "tombstone_in"
                end
                anim.timer = 0
            end
        elseif anim.state == "gone" then
            -- 空位期：停留至被替换（不渲染，无过渡）
        elseif anim.state == "tombstone_in" then
            if anim.timer >= TOMBSTONE_FADEIN then
                anim.state = "dead_done"
            end
        elseif anim.state == "reviving" then
            if anim.timer >= REVIVE_ANIM_DURATION then
                toRemove[#toRemove + 1] = unit
            end
        end
        ::continue::
    end
    for _, unit in ipairs(toRemove) do
        BCS.cardAnims[unit] = nil
    end
end

--- 获取卡片动画 Y 偏移
function BattleCombat.getCardAnimOffsetY(unit)
    local anim = BCS.cardAnims[unit]
    if anim and not isCombatCardAnimEnabled() and isCombatCardAnimState(anim.state) then
        return 0
    end
    if not anim then return 0 end

    if anim.state == "lunge" then
        if anim.isRanged then return 0 end  -- 远程角色用缩放，不位�?
        local t = math.min(1, anim.timer / LUNGE_DURATION)
        t = 1 - (1 - t) * (1 - t)  -- ease-out
        return anim.lungeDir * LUNGE_DISTANCE * t
    elseif anim.state == "return" then
        if anim.isRanged then return 0 end  -- 远程角色用缩放，不位�?
        local t = math.min(1, anim.timer / RETURN_DURATION)
        t = t * t  -- ease-in
        return anim.lungeDir * LUNGE_DISTANCE * (1 - t)
    elseif anim.state == "recoil" then
        local t = math.min(1, anim.timer / RECOIL_DURATION)
        t = 1 - (1 - t) * (1 - t)
        return anim.lungeDir * RECOIL_DISTANCE * t
    elseif anim.state == "recoil_return" then
        local t = math.min(1, anim.timer / RECOIL_RETURN)
        t = 1 - (1 - t) * (1 - t)
        return anim.lungeDir * RECOIL_DISTANCE * (1 - t)
    elseif anim.state == "dying" then
        local elapsed = anim.timer
        local mult = anim.knockbackMult or 1.0
        local dist = DEATH_ANIM_DISTANCE * mult
        if elapsed < DEATH_HITSTOP then
            return 0
        elseif elapsed < DEATH_HITSTOP + DEATH_BURST_DUR then
            local t = (elapsed - DEATH_HITSTOP) / DEATH_BURST_DUR
            t = 1 - (1 - t) * (1 - t) * (1 - t)
            return anim.lungeDir * dist * DEATH_OVERSHOOT * t
        else
            local t = math.min(1, (elapsed - DEATH_HITSTOP - DEATH_BURST_DUR) / DEATH_SETTLE_DUR)
            t = 1 - (1 - t) * (1 - t)
            local ratio = DEATH_OVERSHOOT + (1.0 - DEATH_OVERSHOOT) * t
            return anim.lungeDir * dist * ratio
        end
    elseif anim.state == "reviving" then
        local t = math.min(1, anim.timer / REVIVE_ANIM_DURATION)
        t = 1 - (1 - t) * (1 - t)
        return anim.lungeDir * REVIVE_ANIM_DISTANCE * (1 - t)
    elseif anim.state == "entering" then
        if anim.delay and anim.delay > 0 then
            return anim.lungeDir * ENTER_ANIM_DISTANCE
        end
        local t = math.min(1, anim.timer / ENTER_ANIM_DURATION)
        t = 1 - (1 - t) * (1 - t)  -- ease-out
        return anim.lungeDir * ENTER_ANIM_DISTANCE * (1 - t)
    end
    return 0
end

--- 获取过渡动画 alpha（死亡淡�?复活淡入/墓碑淡入�?
function BattleCombat.getTransitionAlpha(unit)
    local anim = BCS.cardAnims[unit]
    if not anim then return 1.0 end
    if anim.state == "dying" then
        if anim.timer < DEATH_HITSTOP then
            return 1.0  -- 停顿期间完全不透明
        end
        local fadeT = math.min(1, (anim.timer - DEATH_HITSTOP) / (DEATH_ANIM_DURATION - DEATH_HITSTOP))
        return 1.0 - fadeT
    elseif anim.state == "tombstone_in" then
        return math.min(1, anim.timer / TOMBSTONE_FADEIN)
    elseif anim.state == "gone" then
        return 0   -- 空位期：完全隐藏
    elseif anim.state == "reviving" then
        return math.min(1, anim.timer / REVIVE_ANIM_DURATION)
    elseif anim.state == "entering" then
        if anim.delay and anim.delay > 0 then
            return 0
        end
        return math.min(1, anim.timer / ENTER_ANIM_DURATION)
    end
    return 1.0
end

--- 获取蓄力后退偏移（远程角色返�?，用缩放代替�?
function BattleCombat.getChargeOffsetY(unit, isAllyGroup)
    if not isCombatCardAnimEnabled() then return 0 end
    if unit.hp <= 0 then return 0 end
    if BCS.cardAnims[unit] then return 0 end
    if isRangedUnit(unit) then return 0 end  -- 远程角色用缩放，不用位移
    local p = unit.atkProgress or 0
    if p < CHARGE_START then return 0 end
    local t = (p - CHARGE_START) / (1.0 - CHARGE_START)
    local dir = isAllyGroup and 1 or -1
    return dir * CHARGE_DISTANCE * t
end

--- 获取远程角色的卡片缩放（蓄力缩小 + 攻击放大�?
--- 近战角色始终返回 1.0
function BattleCombat.getCardScale(unit, isAllyGroup)
    if not isCombatCardAnimEnabled() then return 1.0 end
    if not isRangedUnit(unit) then return 1.0 end
    if unit.hp <= 0 then return 1.0 end

    -- 攻击动画缩放（lunge 放大, return 回弹�?
    local anim = BCS.cardAnims[unit]
    if anim then
        if anim.state == "lunge" and anim.isRanged then
            local t = math.min(1, anim.timer / LUNGE_DURATION)
            t = 1 - (1 - t) * (1 - t)  -- ease-out
            return RANGED_CHARGE_SCALE + (RANGED_LUNGE_SCALE - RANGED_CHARGE_SCALE) * t
        elseif anim.state == "return" and anim.isRanged then
            local t = math.min(1, anim.timer / RETURN_DURATION)
            t = t * t  -- ease-in
            return RANGED_LUNGE_SCALE + (1.0 - RANGED_LUNGE_SCALE) * t
        end
        return 1.0  -- 其他动画状态（recoil/dying等）不缩�?
    end

    -- 蓄力阶段缩放（进度条 70%�?00% 时逐渐缩小�?
    local p = unit.atkProgress or 0
    if p < CHARGE_START then return 1.0 end
    local t = (p - CHARGE_START) / (1.0 - CHARGE_START)
    return 1.0 + (RANGED_CHARGE_SCALE - 1.0) * t
end

--- 获取卡片动画状态名
function BattleCombat.getAnimState(unit)
    local anim = BCS.cardAnims[unit]
    return anim and anim.state or nil
end

--- 设置卡片动画
function BattleCombat.setCardAnim(unit, animData)
    BCS.cardAnims[unit] = animData
end

--- 清除卡片动画
function BattleCombat.clearCardAnim(unit)
    BCS.cardAnims[unit] = nil
end

--- 清除受击闪烁
function BattleCombat.clearHitFlash(unit)
    BCS.hitFlashes[unit] = nil
end

--- 播放入场动画（交错滑�?+ 淡入�?
---@param units table  单位列表
---@param lungeDir number  -1=从上方滑入（敌方），1=从下方滑入（己方�?
function BattleCombat.playEnterAnims(units, lungeDir)
    for i, unit in ipairs(units) do
        BCS.cardAnims[unit] = {
            state    = "entering",
            timer    = 0,
            lungeDir = lungeDir,
            delay    = (i - 1) * ENTER_STAGGER,
        }
    end
end

-- ======================== 浮动文字更新 ========================

function BattleCombat.updateFloatingTexts(dt)
    local i = 1
    while i <= #BCS.floatingTexts do
        local ft = BCS.floatingTexts[i]
        ft.timer = ft.timer + dt
        if ft.timer >= ft.duration then
            releaseFt(ft)
            table.remove(BCS.floatingTexts, i)
        else
            i = i + 1
        end
    end
end

-- ======================== 受击闪烁更新 ========================

function BattleCombat.updateHitFlashes(dt)
    local toRemove = {}
    for unit, flash in pairs(BCS.hitFlashes) do
        flash.timer = flash.timer + dt
        if flash.timer >= HIT_FLASH_DURATION then
            toRemove[#toRemove + 1] = unit
        end
    end
    for _, unit in ipairs(toRemove) do
        BCS.hitFlashes[unit] = nil
    end
end

--- 获取受击闪烁 alpha（0~255；特效关闭时不绘制）
function BattleCombat.getHitFlashAlpha(unit)
    if not SettingsPanel.isEffectsEnabled() then return 0 end
    local flash = BCS.hitFlashes[unit]
    if not flash then return 0 end
    local t = flash.timer / HIT_FLASH_DURATION
    local alpha = (1 - t) * 180
    if t < 0.3 then
        alpha = 200
    end
    return math.max(0, math.floor(alpha))
end

-- ======================== 血条缓�?========================

function BattleCombat.updateHpBuffers(unitList, dt)
    for _, unit in ipairs(unitList) do
        local cur = (unit.maxHp > 0) and (math.max(0, unit.hp) / unit.maxHp) or 0
        local buf = BCS.hpBuffers[unit]
        if buf == nil then
            BCS.hpBuffers[unit] = cur
        elseif buf > cur then
            BCS.hpBuffers[unit] = math.max(cur, buf - HP_BUFFER_SPEED * dt)
        else
            BCS.hpBuffers[unit] = cur
        end
    end
end

function BattleCombat.getHpBuffer(unit)
    return BCS.hpBuffers[unit]
end

-- ======================== 状态重�?========================

function BattleCombat.reset()
    BCS.floatingTexts = {}
    BCS.cardAnims     = {}
    BCS.hitFlashes    = {}
    BCS.hpBuffers     = {}
    BCS.comboQueue    = {}
    BCS.unitDamageAccum = {}
    BattleStats.reset()   -- 战斗统计随每波战斗清零（仅统计本次战斗）
end

--- 获取单位累计伤害（结算面板用�?
---@param unit table
---@return number
function BattleCombat.getUnitDamage(unit)
    return BCS.unitDamageAccum[unit] or 0
end

--- 获取浮动文字列表（供 BattleDraw 渲染�?
function BattleCombat.getFloatingTexts()
    return BCS.floatingTexts
end

return BattleCombat
