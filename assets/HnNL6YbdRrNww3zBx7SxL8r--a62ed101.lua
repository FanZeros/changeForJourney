-- ============================================================================
-- PrivilegeMileCompLogic — 特权里程特权点补差纯逻辑（无 PDM/网络依赖，可单测）
-- ============================================================================

local M = {}

M.PRIVILEGE_MILE_REWARD_VERSION = 5

M.OLD_PRIVILEGE_MILE_POINTS = { [10] = 3, [20] = 5 }
M.NEW_PRIVILEGE_MILE_POINTS = { [10] = 5, [20] = 7 }

---@param claimed table|nil
---@param threshold number
---@return boolean
function M.isPrivilegeMileClaimed(claimed, threshold)
    if not claimed or type(claimed) ~= "table" then return false end
    if claimed[threshold] == true or claimed[tostring(threshold)] == true then
        return true
    end
    for _, th in ipairs(claimed) do
        if tonumber(th) == threshold then
            return true
        end
    end
    return false
end

---@param claimed table|nil
---@return number totalDiff
---@return string detail  如 "10:+2, 20:+2, 30:+5"
function M.calcCompensationAmount(claimed)
    local totalDiff = 0
    local detailParts = {}
    for threshold, oldAmount in pairs(M.OLD_PRIVILEGE_MILE_POINTS) do
        if M.isPrivilegeMileClaimed(claimed, threshold) then
            local newAmount = M.NEW_PRIVILEGE_MILE_POINTS[threshold] or oldAmount
            local diff = newAmount - oldAmount
            if diff > 0 then
                totalDiff = totalDiff + diff
                detailParts[#detailParts + 1] = threshold .. ":+" .. diff
            end
        end
    end
    table.sort(detailParts)
    return totalDiff, table.concat(detailParts, ", ")
end

---@param claimed table|nil
---@param threshold number
function M.clearThresholdClaim(claimed, threshold)
    if not claimed or type(claimed) ~= "table" then return end
    claimed[threshold] = nil
    claimed[tostring(threshold)] = nil
    local i = 1
    while i <= #claimed do
        if tonumber(claimed[i]) == threshold then
            table.remove(claimed, i)
        else
            i = i + 1
        end
    end
end

--- 指定档位奖励改版后，清除对应档位领取标记，保留观看次数与其它档位。
---@param priv table
---@param thresholds number[]
function M.resetPrivilegeMileClaims(priv, thresholds)
    if not priv or type(priv) ~= "table" then return end
    if not priv.claimed then
        priv.claimed = {}
        return
    end
    for _, threshold in ipairs(thresholds or {}) do
        M.clearThresholdClaim(priv.claimed, threshold)
    end
end

--- 25 档奖励改为星辉招募券、30 档奖励改为随主线进度的大量精粹：
--- 清除对应档位领取标记，保留观看次数与其它档位。
---@param priv table
function M.resetPrivilegeMileProgressForRewardBump(priv)
    M.resetPrivilegeMileClaims(priv, { 25, 30 })
end

--- v5：5/10/15/20/25 档奖励改版，30 档保持不变。
---@param priv table
function M.resetPrivilegeMileProgressForV5(priv)
    M.resetPrivilegeMileClaims(priv, { 5, 10, 15, 20, 25 })
end

return M
