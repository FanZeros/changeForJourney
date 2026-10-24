-- ============================================================================
-- StageExpHelper - 按怪物等级就近取同进度主线挂机经验/分钟
-- 副本（金币/装备/黑钻/遗迹）与通天塔共用：让副本经验与同进度主线同级。
-- 只读 StageConfig/IdleIncomeConfig，不写档、不发奖。
-- ============================================================================

local SC = require("config.StageConfig")
local IdleIncome = require("config.IdleIncomeConfig")

local StageExpHelper = {}

---@type table<number, number>
local expCache = {}

--- 按怪物等级取同进度主线关的挂机经验/分钟（就近取 ml 不超过目标的最大主线关）。
--- 注意：SC.STAGES 是按追加顺序的数组，不是 id 索引表，必须读每个元素的 .id/.monsterLevel。
---@param monsterLevel number
---@return number expPerMin
function StageExpHelper.getExpPerMin(monsterLevel)
    local ml = math.floor(tonumber(monsterLevel) or 0)
    if ml < 1 then return 0 end
    local cached = expCache[ml]
    if cached then return cached end

    local bestId, bestMl = nil, -1
    for _, entry in ipairs(SC.STAGES) do
        local eml = entry.monsterLevel or 0
        if entry.mode ~= "terminal" and eml <= ml and eml > bestMl and entry.id then
            bestMl, bestId = eml, entry.id
        end
    end
    local exp = 0
    if bestId then
        local _, perMin = IdleIncome.get(bestId)
        exp = perMin or 0
    end
    expCache[ml] = exp
    return exp
end

--- 按已通关卡 id 取挂机经验/分钟（资源副本用源关更准）。
---@param stageId number
---@return number expPerMin
function StageExpHelper.getExpPerMinByStageId(stageId)
    local sid = math.tointeger(tonumber(stageId) or 0)
    if not sid or sid <= 0 then return 0 end
    local _, perMin = IdleIncome.get(sid)
    return perMin or 0
end

return StageExpHelper
