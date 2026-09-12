-- SessionSchema.lua — session 模块 Schema
-- 会话信息（在线时间、首登时间、开场完成标记）

local SessionSchema = {}

SessionSchema.Fields = {
    session = {
        pdmKey     = "ModSession",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_session" },
        getDefault = function()
            return {
                lastOnlineTime    = 0,
                firstLoginTime    = 0,
                introCompleted    = false,
                hasReincarnated   = false,
                firstGachaTenDone = false,   -- 新手首次十连SR保底是否已使用
                offlineBonusCount = 0,       -- 今日已领取额外离线收益次数
                offlineBonusDate  = "",      -- 上次重置日期（YYYY-MM-DD UTC+8）
                claimedScenarios  = {},      -- 已领取情景奖励记录（防重复，key=tostring(scenarioId)）
                initialHeroId     = nil,     -- 玩家初始选择的英雄 ID（由 HeroService.SelectInitialHero 写入）
            }
        end,
        onLoad = function(data)
            data.lastOnlineTime = tonumber(data.lastOnlineTime) or 0
            data.firstLoginTime = tonumber(data.firstLoginTime) or 0
            if data.introCompleted    == nil then data.introCompleted    = false end
            if data.hasReincarnated   == nil then data.hasReincarnated   = false end
            if data.firstGachaTenDone == nil then data.firstGachaTenDone = false end
            data.offlineBonusCount = tonumber(data.offlineBonusCount) or 0
            data.offlineBonusDate  = data.offlineBonusDate or ""
        end,
        desc = "会话信息",
    },
}

return SessionSchema
