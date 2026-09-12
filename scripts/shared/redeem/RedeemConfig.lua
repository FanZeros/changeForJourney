-- ============================================================================
-- RedeemConfig - 兑换码配置（双端共享）
-- 职责: 定义所有有效兑换码及其奖励
-- 运行端: shared（服务端校验，客户端不直接使用）
-- ============================================================================

local RedeemConfig = {}

--- 兑换码定义
--- 每个兑换码字段:
---   code      string   兑换码（大写）
---   type      string   "unlimited" 不限量 | "limited" 限量 | "onetime" 一次性
---   limit     number   限量码总可用次数（仅 limited 类型）
---   duration  string   "permanent" 永久 | "timed" 限时
---   rewards   table[]  奖励列表 { type=string, amount=number }
RedeemConfig.CODES = {
    {
        code     = "MXQC88",
        type     = "unlimited",
        duration = "permanent",
        rewards  = {
            { type = "adventure_ticket", amount = 2 },
            { type = "diamond",          amount = 288 },
        },
    },
    {
        code     = "MXZL66",
        type     = "unlimited",
        duration = "permanent",
        rewards  = {
            { type = "adventure_ticket", amount = 2 },
            { type = "diamond",          amount = 288 },
        },
    },
    {
        code     = "SMLT66",
        type     = "unlimited",
        duration = "permanent",
        rewards  = {
            { type = "adventure_ticket", amount = 5 },
            { type = "diamond",          amount = 288 },
        },
    },
}

--- 一次性兑换码批次由服务端加载（RedeemService.Init）
--- 不在 shared 层加载，防止客户端泄露码值

--- 按码值快速查找表（启动时自动构建）
RedeemConfig.CODE_MAP = {}
for _, entry in ipairs(RedeemConfig.CODES) do
    RedeemConfig.CODE_MAP[string.upper(entry.code)] = entry
end

return RedeemConfig
