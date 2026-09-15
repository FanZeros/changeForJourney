-- ============================================================================
-- QuotaSchema.lua — 限额子系统 Schema
-- 路径: scripts/shared/quota/QuotaSchema.lua
--
-- 职责:
--   定义 "quotas" 字段，注册到 CharacterSchema 后 PDM 自动管理。
--   persist = { via = "quota" } 表示数据由 serverCloud.quota 管理，
--   PDM 仅作为缓存层（加载时拉取，不负责持久化存盘）。
--
-- 数据结构（运行时缓存）:
--   quotas = {
--     ["daily_signin"]  = { value = 0, limit = 1 },
--     ["weekly_signin"] = { value = 0, limit = 1 },
--     ...
--   }
-- ============================================================================

local QuotaSchema = {}

QuotaSchema.Fields = {
    quotas = {
        pdmKey     = "ModQuotas",
        type       = "json",
        scope      = "server",
        persist    = { via = "quota" },
        getDefault = function()
            return {}
        end,
        desc = "限额数据（服务端自管理，PDM 仅缓存）",
    },
}

return QuotaSchema
