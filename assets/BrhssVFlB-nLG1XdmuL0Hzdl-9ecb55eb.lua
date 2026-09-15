-- ============================================================================
-- QuotaConsts.lua — 限额 key 定义（双端共享）
-- 路径: scripts/shared/quota/QuotaConsts.lua
--
-- 职责:
--   1. 定义所有 quota key 及其元数据（limit、refreshType、refreshCount）
--   2. 提供 GetAllKeys() 供 PDM 遍历加载
--   3. 提供 FindByKey(quotaKey) 供 PDM.UseQuota 查找定义
--
-- 新增限额只需在 KEYS 表中添加一行，PDM 自动加载。
-- ============================================================================

local QuotaConsts = {}

--- 所有 quota key 定义
--- key:          serverCloud.quota 的云变量 key
--- limit:        上限值
--- refreshType:  刷新类型 ("hour"/"day"/"week_monday"/"week_sunday"/"month")
--- refreshCount: 刷新周期数（1 = 每 1 个周期刷新）
QuotaConsts.KEYS = {
    DAILY_SIGNIN = {
        key          = "daily_signin",
        limit        = 1,
        refreshType  = "day",
        refreshCount = 1,
    },
    WEEKLY_SIGNIN = {
        key          = "weekly_signin",
        limit        = 7,
        refreshType  = "week_monday",
        refreshCount = 1,
    },
    -- 未来扩展示例:
    -- ARENA_TICKET = {
    --     key          = "arena_ticket",
    --     limit        = 5,
    --     refreshType  = "day",
    --     refreshCount = 1,
    -- },
}

--- key 字符串 -> 定义 的反查表（惰性构建）
local keyLookup_ = nil

--- 构建反查表
local function ensureKeyLookup()
    if keyLookup_ then return end
    keyLookup_ = {}
    for _, def in pairs(QuotaConsts.KEYS) do
        keyLookup_[def.key] = def
    end
end

--- 获取所有 key 定义的列表（供 PDM 遍历加载）
---@return table[] 每个元素 = { key, limit, refreshType, refreshCount }
function QuotaConsts.GetAllKeys()
    local result = {}
    for _, def in pairs(QuotaConsts.KEYS) do
        result[#result + 1] = def
    end
    return result
end

--- 按 key 字符串查找定义
---@param quotaKey string  如 "daily_signin"
---@return table|nil  { key, limit, refreshType, refreshCount }
function QuotaConsts.FindByKey(quotaKey)
    ensureKeyLookup()
    ---@diagnostic disable-next-line: return-type-mismatch
    return keyLookup_[quotaKey]
end

return QuotaConsts
