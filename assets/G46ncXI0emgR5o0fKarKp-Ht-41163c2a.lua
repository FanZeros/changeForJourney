-- ============================================================================
-- NumberUtil - 数值格式化工具
-- ============================================================================

local NumberUtil = {}

--- 2^53 安全上限（JSON number 精度极限）
local MAX_SAFE_NUMBER = 9007199254740992  -- 2^53

--- 将大数值格式化为 K/M/B/T 短表示
--- 小于 10000 原样返回，>=10000 转为 "12.3K" 等
--- 自动去除 ".0" 尾缀以缩短字符串长度
--- 支持范围：0 ~ 9007T（2^53）
---@param n number
---@return string
function NumberUtil.format(n)
    if not n then return "0" end
    n = math.floor(n)
    if n < 0 then n = 0 end
    if n < 10000 then
        return tostring(n)
    elseif n < 1000000 then
        -- 防止边界溢出：999950+ 四舍五入后变成 "1000.0K"，应进位到 M
        local k = n / 1000
        if k >= 999.95 then
            return "1M"
        end
        local s = string.format("%.1fK", k)
        return (s:gsub("%.0K", "K"))  -- "140.0K" → "140K"
    elseif n < 1000000000 then
        local m = n / 1000000
        if m >= 999.95 then
            return "1B"
        end
        local s = string.format("%.1fM", m)
        return (s:gsub("%.0M", "M"))  -- "2.0M" → "2M"
    elseif n < 1000000000000 then
        local b = n / 1000000000
        if b >= 999.95 then
            return "1T"
        end
        local s = string.format("%.1fB", b)
        return (s:gsub("%.0B", "B"))  -- "2.0B" → "2B"
    else
        local t = n / 1000000000000
        local s = string.format("%.1fT", t)
        return (s:gsub("%.0T", "T"))  -- "1.0T" → "1T"
    end
end

--- 安全累加：防止超过 2^53 JSON 精度极限
--- 用于货币等关键数值的加法操作
---@param current number 当前值
---@param delta number 增量
---@return number 累加后的值（不超过 MAX_SAFE_NUMBER）
function NumberUtil.safeAdd(current, delta)
    local result = (current or 0) + (delta or 0)
    if result > MAX_SAFE_NUMBER then
        return MAX_SAFE_NUMBER
    end
    if result < 0 then return 0 end
    return result
end

--- 获取安全上限常量
---@return integer
function NumberUtil.getMaxSafe()
    return MAX_SAFE_NUMBER
end

return NumberUtil
