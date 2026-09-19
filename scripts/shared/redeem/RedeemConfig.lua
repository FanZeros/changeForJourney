-- ============================================================================
-- RedeemConfig - 兑换码配置（双端共享）
-- 职责: 定义所有有效兑换码及其奖励（单机固定码，阶梯钻石额度）
-- 运行端: shared（服务端校验，客户端不直接使用）
-- ============================================================================

local RedeemConfig = {}

--- 兑换码定义
--- 每个兑换码字段:
---   code      string   兑换码（大写）
---   type      string   "unlimited" 不限量（每玩家限用一次，防重复走 PDM usedCodes）
---   duration  string   "permanent" 永久
---   rewards   table[]  奖励列表 { type=string, amount=number }
--- 阶梯钻石额度：50 / 100 / 200 / 300 / 500 / 800 / 1000 / 2000 / 3000 / 5000
RedeemConfig.CODES = {
    {
        code     = "MX50",
        type     = "unlimited",
        duration = "permanent",
        rewards  = { { type = "diamond", amount = 50 } },
    },
    {
        code     = "MX100",
        type     = "unlimited",
        duration = "permanent",
        rewards  = { { type = "diamond", amount = 100 } },
    },
    {
        code     = "MX200",
        type     = "unlimited",
        duration = "permanent",
        rewards  = { { type = "diamond", amount = 200 } },
    },
    {
        code     = "MX300",
        type     = "unlimited",
        duration = "permanent",
        rewards  = { { type = "diamond", amount = 300 } },
    },
    {
        code     = "MX500",
        type     = "unlimited",
        duration = "permanent",
        rewards  = { { type = "diamond", amount = 500 } },
    },
    {
        code     = "MX800",
        type     = "unlimited",
        duration = "permanent",
        rewards  = { { type = "diamond", amount = 800 } },
    },
    {
        code     = "MX1000",
        type     = "unlimited",
        duration = "permanent",
        rewards  = { { type = "diamond", amount = 1000 } },
    },
    {
        code     = "MX2000",
        type     = "unlimited",
        duration = "permanent",
        rewards  = { { type = "diamond", amount = 2000 } },
    },
    {
        code     = "MX3000",
        type     = "unlimited",
        duration = "permanent",
        rewards  = { { type = "diamond", amount = 3000 } },
    },
    {
        code     = "MX5000",
        type     = "unlimited",
        duration = "permanent",
        rewards  = { { type = "diamond", amount = 5000 } },
    },
}

--- 按码值快速查找表（启动时自动构建）
RedeemConfig.CODE_MAP = {}
for _, entry in ipairs(RedeemConfig.CODES) do
    RedeemConfig.CODE_MAP[string.upper(entry.code)] = entry
end

return RedeemConfig
