-- RedeemSchema.lua — redeem 模块 Schema
-- 兑换码系统

local RedeemSchema = {}

RedeemSchema.Fields = {
    redeem = {
        pdmKey     = "ModRedeem",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_redeem" },
        getDefault = function()
            return {
                usedCodes = {},
            }
        end,
        onLoad = function(data)
            if not data.usedCodes then data.usedCodes = {} end
        end,
        desc = "兑换码",
    },
}

return RedeemSchema
