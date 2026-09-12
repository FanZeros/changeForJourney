-- SigninSchema.lua — signin 模块 Schema
-- 签到系统（每周+每日）

local SigninSchema = {}

SigninSchema.REWARD_VERSION = 2

SigninSchema.Fields = {
    signin = {
        pdmKey     = "ModSignin",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_signin" },
        getDefault = function()
            return {
                weekId        = 0,
                weeklyClaimed = {},
                monthId       = 0,
                dailyClaimed  = {},
                rewardVersion = SigninSchema.REWARD_VERSION,
            }
        end,
        onLoad = function(data)
            data.weekId  = tonumber(data.weekId)  or 0
            data.monthId = tonumber(data.monthId) or 0
            data.rewardVersion = tonumber(data.rewardVersion) or 0
            if data.weeklyClaimed then
                local fixed = {}
                for k, v in pairs(data.weeklyClaimed) do
                    fixed[tonumber(k) or k] = v
                end
                data.weeklyClaimed = fixed
            else
                data.weeklyClaimed = {}
            end
            if data.dailyClaimed then
                local fixed = {}
                for k, v in pairs(data.dailyClaimed) do
                    fixed[tonumber(k) or k] = v
                end
                data.dailyClaimed = fixed
            else
                data.dailyClaimed = {}
            end
        end,
        desc = "签到系统",
    },
}

return SigninSchema
