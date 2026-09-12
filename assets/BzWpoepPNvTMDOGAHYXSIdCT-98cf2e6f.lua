-- ============================================================================
-- GMLogger - GM 操作审计日志（环形缓冲区）
-- 职责: 记录所有 GM 操作的操作人、操作类型、参数、结果、时间戳
-- 层级: server/gm  |  纯内存（不落盘）
-- ============================================================================

local GMLogger = {}

-- ======================== 配置 ========================

local MAX_ENTRIES = 500        -- 环形缓冲区最大条目
local buffer = {}              -- 日志缓冲区
local writeIndex = 0           -- 当前写入位置（0-based，取模使用）
local totalCount = 0           -- 总写入条数

-- ======================== 记录日志 ========================

--- 记录一条 GM 操作日志
---@param operator number     操作人 UID
---@param action string       操作类型（Protocol.ACTION_TYPES 值）
---@param params table|nil    操作参数
---@param result table|nil    操作结果 { success, reason? }
function GMLogger.Log(operator, action, params, result)
    writeIndex = (writeIndex % MAX_ENTRIES) + 1  -- 1-based 循环
    totalCount = totalCount + 1

    buffer[writeIndex] = {
        id       = totalCount,
        time     = os.time(),
        operator = operator,
        action   = action,
        params   = params,
        success  = result and result.success or false,
        reason   = result and result.reason or nil,
    }

    -- 控制台日志（方便观测）
    local statusStr = (result and result.success) and "OK" or ("FAIL:" .. tostring(result and result.reason or "unknown"))
    print(string.format("[GMLogger] #%d op=%s actor=%s status=%s",
        totalCount, tostring(action), tostring(operator), statusStr))
end

-- ======================== 查询日志 ========================

--- 获取最近 N 条日志（按时间倒序）
---@param count number|nil  默认 50
---@return table[]  日志条目列表（最新在前）
function GMLogger.GetRecentLogs(count)
    count = count or 50
    local total = math.min(totalCount, MAX_ENTRIES)
    count = math.min(count, total)

    local result = {}
    for i = 1, count do
        local idx = ((writeIndex - i) % MAX_ENTRIES) + 1
        local entry = buffer[idx]
        if entry then
            result[#result + 1] = entry
        end
    end
    return result
end

--- 获取统计信息
---@return table { totalOps, bufferSize, oldestTime }
function GMLogger.GetStats()
    local oldestTime = nil
    if totalCount > 0 then
        local oldestIdx
        if totalCount <= MAX_ENTRIES then
            oldestIdx = 1
        else
            oldestIdx = (writeIndex % MAX_ENTRIES) + 1
        end
        local entry = buffer[oldestIdx]
        if entry then oldestTime = entry.time end
    end

    return {
        totalOps   = totalCount,
        bufferSize = math.min(totalCount, MAX_ENTRIES),
        maxSize    = MAX_ENTRIES,
        oldestTime = oldestTime,
    }
end

-- ======================== 包装器（供 Handler 层使用） ========================

--- 创建带审计日志的 GM 操作包装器
--- 用法: handlers[action] = GMLogger.WrapGMAction(action, actualHandlerFn)
---@param action string       操作类型名
---@param fn function         实际 handler 函数 (uid, params) → result
---@return function           包装后的 handler
function GMLogger.WrapGMAction(action, fn)
    return function(uid, params)
        local result = fn(uid, params)
        GMLogger.Log(uid, action, params, result)
        return result
    end
end

return GMLogger
