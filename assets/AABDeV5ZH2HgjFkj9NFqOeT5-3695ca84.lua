-- ============================================================================
-- ChallengerSchema.lua — 挑战者区服全局权益 Schema
-- ============================================================================

local ChallengerSchema = {}

ChallengerSchema.Fields = {
    challenger = {
        pdmKey     = "ModChallenger",
        type       = "json",
        scope      = "global",
        persist    = { via = "cloud", cloudKey = "global_challenger" },
        getDefault = function()
            return {
                activities = {},
                unlockedAvatarFrames = {},
                avatarFrameGrants = {},
            }
        end,
        onLoad = function(data)
            if not data.activities then data.activities = {} end
            if type(data.unlockedAvatarFrames) ~= "table" then
                data.unlockedAvatarFrames = {}
            end
            local fixedFrames = {}
            for frameId, unlocked in pairs(data.unlockedAvatarFrames) do
                local level = tonumber(unlocked)
                if level and level > 0 then
                    fixedFrames[tostring(frameId)] = math.min(2, math.max(1, math.floor(level)))
                elseif unlocked == true then
                    fixedFrames[tostring(frameId)] = 1
                end
            end
            data.unlockedAvatarFrames = fixedFrames
            if type(data.avatarFrameGrants) ~= "table" then
                data.avatarFrameGrants = {}
            end
            local fixedGrants = {}
            for activityId, tierMap in pairs(data.avatarFrameGrants) do
                if type(tierMap) == "table" then
                    local tiers = {}
                    for tierId, granted in pairs(tierMap) do
                        if granted then tiers[tostring(tierId)] = true end
                    end
                    fixedGrants[tostring(activityId)] = tiers
                end
            end
            data.avatarFrameGrants = fixedGrants
            local fixedActivities = {}
            for activityId, activity in pairs(data.activities) do
                if type(activity) == "table" then
                    activity.serverId = tonumber(activity.serverId) or 0
                    activity.bestStageId = tonumber(activity.bestStageId) or 0
                    activity.settled = activity.settled == true
                    activity.settledAt = tonumber(activity.settledAt) or 0
                    activity.rewardTier = tonumber(activity.rewardTier) or 0
                    activity.tierName = activity.tierName or ""
                    if type(activity.rewards) ~= "table" then activity.rewards = {} end
                    if type(activity.deliveredServers) ~= "table" then activity.deliveredServers = {} end
                    if type(activity.deliveredTiersByServer) ~= "table" then activity.deliveredTiersByServer = {} end
                    local delivered = {}
                    for sid, v in pairs(activity.deliveredServers) do
                        if v then delivered[tostring(sid)] = true end
                    end
                    activity.deliveredServers = delivered
                    local fixedDeliveredTiers = {}
                    for sid, tierMap in pairs(activity.deliveredTiersByServer) do
                        if type(tierMap) == "table" then
                            local fixedTierMap = {}
                            for tierId, tierDelivered in pairs(tierMap) do
                                if tierDelivered then
                                    fixedTierMap[tostring(tierId)] = true
                                end
                            end
                            fixedDeliveredTiers[tostring(sid)] = fixedTierMap
                        end
                    end
                    activity.deliveredTiersByServer = fixedDeliveredTiers
                    fixedActivities[tostring(activityId)] = activity
                end
            end
            data.activities = fixedActivities
        end,
        desc = "挑战者区服全局权益",
    },
}

return ChallengerSchema
