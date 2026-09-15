-- ============================================================================
-- ChallengerServerConfig - 挑战者区服活动配置（双端共享）
-- ============================================================================

local Consts = require("shared.challenger.ChallengerConsts")

local C = {}

C.ACTIVITY_ID = Consts.ACTIVITY_ID
C.REWARD_CLAIM_SOURCE = Consts.REWARD_CLAIM_SOURCE
C.CLAIM_SCOPE_PER_NON_CHALLENGER_SERVER = Consts.CLAIM_SCOPE_PER_NON_CHALLENGER_SERVER

C.CHALLENGER_SERVERS = {
    [901] = {
        id = 901,
        activityId = C.ACTIVITY_ID,
        name = "挑战者S0",
        openTime = 0,
        closeTime = 1784476800,
        stageConfigModule = "config.ChallengerStageConfig_202607",
        claimScope = C.CLAIM_SCOPE_PER_NON_CHALLENGER_SERVER,
        rewardTable = {
            {
                minStageId = 1205,
                rewardTier = 1,
                tierName = "青铜挑战者",
                avatarFrameId = nil,
                rewards = {
                    { type = "diamond", amount = 200 },
                },
            },
            {
                minStageId = 2305,
                rewardTier = 2,
                tierName = "青铜挑战者 II",
                avatarFrameId = 2,
                rewards = {
                    { type = "diamond", amount = 500 },
                },
            },
            {
                minStageId = 3505,
                rewardTier = 3,
                tierName = "白银挑战者",
                avatarFrameId = nil,
                rewards = {
                    { type = "diamond", amount = 800 },
                    { type = "adventure_ticket", amount = 5 },
                },
            },
            {
                minStageId = 4605,
                rewardTier = 4,
                tierName = "白银挑战者 II",
                avatarFrameId = 3,
                rewards = {
                    { type = "diamond", amount = 1200 },
                    { type = "adventure_ticket", amount = 8 },
                    { type = "golden_key", amount = 1 },
                },
            },
            {
                minStageId = 5805,
                rewardTier = 5,
                tierName = "黄金挑战者",
                avatarFrameId = nil,
                rewards = {
                    { type = "diamond", amount = 1500 },
                    { type = "adventure_ticket", amount = 10 },
                    { type = "golden_key", amount = 2 },
                },
            },
            {
                minStageId = 6905,
                rewardTier = 6,
                tierName = "黄金挑战者 II",
                avatarFrameId = 4,
                rewards = {
                    { type = "diamond", amount = 1800 },
                    { type = "golden_key", amount = 3 },
                    { type = "arcane_dust", amount = 500 },
                },
            },
            {
                minStageId = 8105,
                rewardTier = 7,
                tierName = "铂金挑战者",
                avatarFrameId = nil,
                rewards = {
                    { type = "diamond", amount = 2000 },
                    { type = "golden_key", amount = 5 },
                    { type = "stellar_ticket", amount = 1 },
                },
            },
            {
                minStageId = 9205,
                rewardTier = 8,
                tierName = "铂金挑战者 II",
                avatarFrameId = 5,
                rewards = {
                    { type = "diamond", amount = 2200 },
                    { type = "golden_key", amount = 6 },
                    { type = "stellar_ticket", amount = 2 },
                    { type = "arcane_dust", amount = 1000 },
                },
            },
            {
                minStageId = 10405,
                rewardTier = 9,
                tierName = "钻石挑战者",
                avatarFrameId = nil,
                rewards = {
                    { type = "diamond", amount = 2500 },
                    { type = "golden_key", amount = 8 },
                    { type = "stellar_ticket", amount = 3 },
                    { type = "sacred_stone", amount = 1 },
                },
            },
            {
                minStageId = 11505,
                rewardTier = 10,
                tierName = "钻石挑战者 II",
                avatarFrameId = 6,
                rewards = {
                    { type = "diamond", amount = 3000 },
                    { type = "golden_key", amount = 10 },
                    { type = "stellar_ticket", amount = 5 },
                    { type = "sacred_stone", amount = 2 },
                },
            },
        },
    },
    [902] = {
        id = 902,
        activityId = "challenger_2026s1",
        name = "挑战者S1",
        openTime = 0,
        closeTime = 1786550399,
        stageConfigModule = "config.ChallengerStageConfig_2026S1",
        seasonAffixMode = "difficulty_count",
        maxStageId = 11505,
        firstClearStonesEnabled = false,
        claimScope = C.CLAIM_SCOPE_PER_NON_CHALLENGER_SERVER,
        rewardTable = {
            {
                minStageId = 1205,
                rewardTier = 1,
                tierName = "青铜挑战者",
                rewards = {
                    { type = "diamond", amount = 200 },
                },
            },
            {
                minStageId = 2305,
                rewardTier = 2,
                tierName = "青铜挑战者 II",
                avatarFrameId = 2,
                avatarFrameIncrement = 1,
                rewards = {
                    { type = "diamond", amount = 500 },
                },
            },
            {
                minStageId = 3505,
                rewardTier = 3,
                tierName = "白银挑战者",
                rewards = {
                    { type = "diamond", amount = 800 },
                    { type = "adventure_ticket", amount = 5 },
                },
            },
            {
                minStageId = 4605,
                rewardTier = 4,
                tierName = "白银挑战者 II",
                avatarFrameId = 3,
                avatarFrameIncrement = 1,
                rewards = {
                    { type = "diamond", amount = 1200 },
                    { type = "adventure_ticket", amount = 8 },
                    { type = "golden_key", amount = 1 },
                },
            },
            {
                minStageId = 5805,
                rewardTier = 5,
                tierName = "黄金挑战者",
                rewards = {
                    { type = "diamond", amount = 1500 },
                    { type = "adventure_ticket", amount = 10 },
                    { type = "golden_key", amount = 2 },
                },
            },
            {
                minStageId = 6905,
                rewardTier = 6,
                tierName = "黄金挑战者 II",
                avatarFrameId = 4,
                avatarFrameIncrement = 1,
                rewards = {
                    { type = "diamond", amount = 1800 },
                    { type = "golden_key", amount = 3 },
                    { type = "arcane_dust", amount = 500 },
                },
            },
            {
                minStageId = 8105,
                rewardTier = 7,
                tierName = "铂金挑战者",
                rewards = {
                    { type = "diamond", amount = 2000 },
                    { type = "golden_key", amount = 5 },
                    { type = "stellar_ticket", amount = 1 },
                },
            },
            {
                minStageId = 9205,
                rewardTier = 8,
                tierName = "铂金挑战者 II",
                avatarFrameId = 5,
                avatarFrameIncrement = 1,
                rewards = {
                    { type = "diamond", amount = 2200 },
                    { type = "golden_key", amount = 6 },
                    { type = "stellar_ticket", amount = 2 },
                    { type = "arcane_dust", amount = 1000 },
                },
            },
            {
                minStageId = 10405,
                rewardTier = 9,
                tierName = "钻石挑战者",
                rewards = {
                    { type = "diamond", amount = 2500 },
                    { type = "golden_key", amount = 8 },
                    { type = "stellar_ticket", amount = 3 },
                },
            },
            {
                minStageId = 11505,
                rewardTier = 10,
                tierName = "钻石挑战者 II",
                avatarFrameId = 6,
                avatarFrameIncrement = 1,
                rewards = {
                    { type = "diamond", amount = 3000 },
                    { type = "golden_key", amount = 10 },
                    { type = "stellar_ticket", amount = 5 },
                },
            },
        },
    },
}
function C.GetByServerId(serverId)
    return C.CHALLENGER_SERVERS[tonumber(serverId)]
end

function C.GetByActivityId(activityId)
    for _, cfg in pairs(C.CHALLENGER_SERVERS) do
        if cfg.activityId == activityId then
            return cfg
        end
    end
    return nil
end

function C.GetDefaultActivity()
    return C.CHALLENGER_SERVERS[901]
end

function C.GetStatus(cfg, now)
    if not cfg then return Consts.STATUS_CLOSED end
    now = now or os.time()
    if cfg.openTime and cfg.openTime > 0 and now < cfg.openTime then
        return Consts.STATUS_NOT_OPEN
    end
    if cfg.closeTime and cfg.closeTime > 0 and now >= cfg.closeTime then
        return Consts.STATUS_CLOSED
    end
    return Consts.STATUS_OPEN
end

function C.IsOpen(serverId, now)
    return C.GetStatus(C.GetByServerId(serverId), now) == Consts.STATUS_OPEN
end

function C.IsClosed(serverId, now)
    return C.GetStatus(C.GetByServerId(serverId), now) == Consts.STATUS_CLOSED
end

return C
