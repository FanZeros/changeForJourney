-- 只返回正向证明：false 既可能有进攻能力，也可能尚缺已审计信息。
-- 计时、死亡结算、入场复活门禁与状态切换日志均由宿主 Guard 负责。
local AD = require("systems.AttributeDef")
local ART = require("systems.ArtifactRuntime")
local TAL = require("systems.TalentManager")
local ETS = require("systems.ExtraTalentSystem")
local CGR = require("systems.ClassGateRuntime")
local ESR = require("systems.EquipmentSetRuntime")

local M = {}
local HEALERS = { [9] = true, [15] = true, [19] = true, [23] = true }
local NON_DAMAGE_STATUS = {
    shocked = true, frozen = true, marked = true, hot = true,
    vulnerable = true, arcane_mark = true,
}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---@param units table
---@param unit table
---@return boolean
local function contains(units, unit)
    for _, member in pairs(units) do if member == unit then return true end end
    return false
end

-- 正向白名单仅收录已审计的基础属性、治疗、防守及攻击依赖增益节点。
-- 不以连续编号或外部注册表替未来新增机制自动背书；其他节点保守不判败。
local HEALER_STARS = {
    [0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
    [5] = true, [6] = true, [7] = true, [8] = true, [9] = true,
    [10] = true, [11] = true, [12] = true, [13] = true, [14] = true, [15] = true,
    [16] = true, [20] = true, [24] = true, [31] = true, [32] = true,
    [39] = true, [40] = true, [53] = true, [54] = true, [55] = true, [56] = true,
    [60] = true, [73] = true, [74] = true, [75] = true, [76] = true, [80] = true,
    [81] = true, [84] = true, [85] = true, [92] = true, [93] = true, [100] = true,
    [101] = true, [104] = true, [105] = true, [112] = true, [116] = true, [117] = true,
    [124] = true, [125] = true, [128] = true,
    [201] = true, [202] = true, [203] = true, [207] = true,
}
---@param unit table
---@return boolean
local function knownStarsAndAwakening(unit)
    if type(unit.litNodeSet) ~= "table" or type(unit.awakeningNodes) ~= "table" then return false end
    for key, enabled in pairs(unit.litNodeSet) do
        local id = tonumber(key)
        if enabled ~= false and (enabled ~= true or not id or not HEALER_STARS[id]) then
            return false
        end
    end
    for key, enabled in pairs(unit.awakeningNodes) do
        if key ~= "_awk3Migrated" then
            local id = tonumber(key)
            if enabled ~= false and (enabled ~= true or not id or id % 1 ~= 0 or id < 1 or id > 7) then
                return false
            end
        elseif type(enabled) ~= "boolean" then return false end
    end
    return true
end

---@param unit table
---@param lane table
---@return boolean provenNone
---@return string reason
local function pureHealer(unit, lane)
    if type(unit) ~= "table" or not HEALERS[unit.heroId] then return false, "unit_not_audited_healer" end
    if type(unit.attrs) ~= "table" or unit.attrs.atkType ~= AD.ATK_HOLY then
        return false, "unit_not_holy_healing"
    end
    if type(unit.advTalentIds) ~= "table" or not knownStarsAndAwakening(unit) then
        return false, "unit_unknown_mechanism"
    end
    local ok, reason = CGR.inspectHealerOffense(unit)
    if not ok then return false, reason end
    ok, reason = ART.inspectOffense(unit)
    if not ok then return false, reason end
    ok, reason = ESR.inspectHealerOffense(unit)
    if not ok then return false, reason end
    ok, reason = ETS.inspectHealerOffense(unit, lane.etsState, lane.allies)
    if not ok then return false, reason end
    return true, "audited_holy_healer"
end

---@param lane table
---@return boolean provenNone
---@return string reason
local function projectilesNone(lane)
    for _, projectile in pairs(lane.projectileState.projectiles) do
        if type(projectile) ~= "table" then return false, "projectile_unknown" end
        -- 穿透与返程回调各自拥有完成标记，不能只看弹头已命中。
        if projectile.pierceEvents ~= nil then
            if type(projectile.pierceEvents) ~= "table" then return false, "projectile_unknown_pierce" end
            if next(projectile.pierceEvents) ~= nil and projectile.arrived ~= true then
                local idx = projectile.nextEventIdx
                if not finite(idx) or idx % 1 ~= 0 or idx < 1 or idx <= #projectile.pierceEvents then
                    return false, "projectile_pending_pierce"
                end
            end
        end
        if projectile.isFlybackReturn and projectile.returnHitDone ~= true then
            return false, "projectile_pending_return"
        end
        if projectile.onReturnHit ~= nil and projectile.returnHitDone ~= true then
            return false, "projectile_unknown_return"
        end
        -- 已结算弹头或返程仍可能只为视觉淡出保留。
        local resolved = projectile.arrived == true
            or (projectile.hitResolved == true and not projectile.isFlybackReturn)
            or (projectile.isFlybackReturn == true and projectile.returnHitDone == true)
        if not resolved then
            if projectile.offenseOrigin ~= "normal_attack" or type(projectile.onArrive) ~= "function"
                or projectile.chainProjectile or projectile.isFlybackReturn then
                return false, "projectile_unknown_callback"
            end
            local source = projectile.offenseSource
            if type(source) ~= "table" then return false, "projectile_missing_source" end
            if projectile.offenseSide == "ally" and projectile.offenseKind == "heal"
                and contains(lane.allies, source) then
                -- 死亡来源仍接受同样完整的纯治疗审计，不仅凭角色标签豁免。
                local ok, reason = pureHealer(source, lane)
                if not ok then return false, reason end
            elseif projectile.offenseSide == "enemy" and projectile.offenseKind == "damage"
                and contains(lane.enemies, source) then
                -- 仅忽略宿主明确标记的普通敌方攻击契约。
                -- 己方反应伤害已在上方审计；这里不执行任何回调。
            else
                return false, "projectile_offense_or_unknown_side"
            end
        end
    end
    return true, "projectiles_none"
end

---@param lane table
---@return boolean provenNone
---@return string reason
function M.inspect(lane)
    if type(lane) ~= "table" then return false, "lane_missing" end
    for _, key in ipairs({ "allies", "enemies", "combatState", "projectileState", "semState",
        "talentStates", "talentRefs", "etsState" }) do
        if type(lane[key]) ~= "table" then return false, "lane_missing_" .. key end
    end
    if type(lane.combatState.comboQueue) ~= "table" or type(lane.projectileState.projectiles) ~= "table"
        or type(lane.semState.effects) ~= "table" then return false, "lane_missing_queues" end
    if lane.talentRefs.bAllies ~= lane.allies or lane.talentRefs.bEnemies ~= lane.enemies then
        return false, "lane_talent_refs_mismatch"
    end
    if type(lane.talentRefs.pendingDeaths) ~= "table" or next(lane.talentRefs.pendingDeaths) ~= nil
        or lane.talentRefs.deathHookDepth ~= 0 then return false, "lane_pending_death" end
    if lane.extraOffenseKnown ~= nil and lane.extraOffenseKnown ~= true then
        return false, "lane_unknown_extra_mechanism"
    end
    local ok, reason = ETS.inspectLaneOffense(lane.etsState)
    if not ok then return false, reason end
    local live = 0
    for _, unit in pairs(lane.allies) do
        if type(unit) ~= "table" or not finite(unit.hp) then return false, "unit_unknown" end
        ok, reason = TAL.inspectOffense(unit, lane.talentStates, lane.talentRefs)
        if not ok then return false, reason end
        ok, reason = ART.inspectOffense(unit, unit.hp <= 0)
        if not ok then return false, reason end
        if unit.hp > 0 then
            live = live + 1
            ok, reason = pureHealer(unit, lane)
            if not ok then return false, reason end
        end
    end
    if live == 0 then return false, "lane_no_live_allies" end
    local liveEnemy = false
    for _, enemy in pairs(lane.enemies) do
        if type(enemy) ~= "table" or not finite(enemy.hp) then return false, "enemy_unknown" end
        if enemy.hp > 0 then liveEnemy = true end
        local effects = lane.semState.effects[enemy]
        if effects ~= nil then
            if type(effects) ~= "table" then return false, "status_unknown" end
            for kind, effect in pairs(effects) do
                if type(effect) ~= "table" or not NON_DAMAGE_STATUS[kind] then
                    return false, kind == "burning" and "status_enemy_burning" or "status_unknown"
                end
            end
        end
    end
    if not liveEnemy then return false, "lane_no_live_enemies" end
    for _, entry in pairs(lane.combatState.comboQueue) do
        if type(entry) ~= "table" or type(entry.attacker) ~= "table" then
            return false, "combo_unknown"
        end
        -- 正式队列仅包含伤害连击；显式治疗仍要求来源通过完整审计。
        if entry.isAlly == false and entry.targetIsAlly == true and contains(lane.enemies, entry.attacker) then
            -- 普通敌方连击本身不提供己方翻盘能力。
        elseif entry.isAlly == true and entry.offenseKind == "heal" and entry.offenseOrigin == "normal_attack"
            and contains(lane.allies, entry.attacker) then
            ok, reason = pureHealer(entry.attacker, lane)
            if not ok then return false, reason end
        else return false, "combo_pending_offense_or_unknown" end
    end
    ok, reason = projectilesNone(lane)
    if not ok then return false, reason end
    return true, "audited_no_offense"
end

return M
