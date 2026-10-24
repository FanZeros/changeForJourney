-- 无进攻能力宽限：只接受已审计能力检查的肯定结论，不用伤害量或职业标签猜必败。
-- 每场/每线独立持有 owner；终焉由三队更新完成后统一调用一次。
local Capabilities = require("systems.BattleOffenseCapabilities")

local Guard = {}
Guard.GRACE_SEC = 5
Guard.REASON = "no_offense"

---@param owner table
function Guard.reset(owner)
    owner._noOffenseElapsed = nil
    owner._noOffenseLanes = nil
    owner._noOffenseReported = nil
end

local function sameRoster(previous, current)
    if #previous ~= #current then return false end
    for i, unit in ipairs(current) do
        local old = previous[i]
        if old.unit ~= unit or old.alive ~= ((unit.hp or 0) > 0) then return false end
    end
    return true
end

local function sameLanes(previous, lanes)
    if #previous ~= #lanes then return false end
    for i, lane in ipairs(lanes) do
        local old = previous[i]
        for _, key in ipairs({ "allies", "enemies", "combatState", "projectileState", "semState", "talentStates", "talentRefs", "etsState" }) do
            if old[key] ~= lane[key] then return false end
        end
        if not sameRoster(old.roster, lane.allies) then return false end
    end
    return true
end

--- eligible 由宿主明确提供：战斗活动且不在暂停/入场/行军/结算阶段。
--- 首次观察只建立基线，不把首次观察前整段 dt 倒算为无进攻时间。
---@param owner table
---@param realDt number
---@param lanes table[]
---@param eligible boolean
---@return boolean
function Guard.update(owner, realDt, lanes, eligible)
    if eligible ~= true or type(realDt) ~= "number" or realDt <= 0
        or realDt ~= realDt or realDt == math.huge or type(lanes) ~= "table" or #lanes == 0 then
        Guard.reset(owner)
        return false
    end
    for _, lane in ipairs(lanes) do
        local provenNone = Capabilities.inspect(lane)
        if provenNone ~= true then
            if owner._noOffenseElapsed ~= nil and not owner._noOffenseReported then
                print("[BattleOffenseGuard] 进攻能力恢复或仍需等待，取消提前判败")
            end
            Guard.reset(owner)
            return false
        end
    end
    if not owner._noOffenseLanes or not sameLanes(owner._noOffenseLanes, lanes) then
        Guard.reset(owner)
        local refs = {}
        for i, lane in ipairs(lanes) do
            local roster = {}
            for j, unit in ipairs(lane.allies) do
                roster[j] = { unit = unit, alive = (unit.hp or 0) > 0 }
            end
            refs[i] = {
                allies = lane.allies, enemies = lane.enemies, combatState = lane.combatState,
                projectileState = lane.projectileState, semState = lane.semState, talentStates = lane.talentStates,
                talentRefs = lane.talentRefs, etsState = lane.etsState, roster = roster,
            }
        end
        owner._noOffenseLanes = refs
        owner._noOffenseElapsed = 0
        print("[BattleOffenseGuard] 已无已知进攻能力，开始5秒宽限")
        return false
    end
    if owner._noOffenseReported then return false end
    owner._noOffenseElapsed = owner._noOffenseElapsed + realDt
    if owner._noOffenseElapsed < Guard.GRACE_SEC then return false end
    owner._noOffenseReported = true
    print("[BattleOffenseGuard] 无进攻能力持续5秒，战斗失败 reason=" .. Guard.REASON)
    return true
end

return Guard
