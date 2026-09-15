-- ============================================================================
-- HeroHandler - 英雄管理网络入口（薄路由层）
-- 职责: 接收请求 → 提取参数 → 调 HeroService → 返回结果
-- 层级: server/hero  |  禁止业务逻辑，逻辑全在 HeroService
-- ============================================================================

local Protocol   = require("shared.Protocol")
local HeroService = require("server.hero.HeroService")

local HeroHandler = {}

local handlers = {}

--- 上阵英雄
handlers[Protocol.ACTION_TYPES.DEPLOY_HERO] = function(uid, params)
    local ok, err = HeroService.DeployHero(uid, params and params.heroId)
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true }
end

--- 下阵英雄
handlers[Protocol.ACTION_TYPES.UNDEPLOY_HERO] = function(uid, params)
    local ok, err = HeroService.UndeployHero(uid, params and params.heroId)
    if not ok then
        return { success = false, reason = err }
    end
    return { success = true }
end

--- 批量设置出战阵容
handlers[Protocol.ACTION_TYPES.SET_DEPLOYED] = function(uid, params)
    local ok, err, result = HeroService.SetDeployed(uid, params and params.heroIds)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success  = true,
        deployed = result.deployed,
    }
end

--- [三队并行] 批量设置指定队伍阵容
handlers[Protocol.ACTION_TYPES.SET_TEAM] = function(uid, params)
    local ok, err, result = HeroService.SetTeam(
        uid,
        params and params.teamIdx,
        params and params.heroIds
    )
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success  = true,
        teamIdx  = result.teamIdx,
        slots    = result.slots,
        deployed = result.deployed,
    }
end

--- 英雄升级
handlers[Protocol.ACTION_TYPES.LEVEL_UP_HERO] = function(uid, params)
    local ok, err, result = HeroService.LevelUpHero(uid, params and params.heroId)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success  = true,
        heroId   = result.heroId,
        newLevel = result.newLevel,
        goldCost = result.goldCost,
    }
end

--- 新玩家选择初始英雄
handlers[Protocol.ACTION_TYPES.SELECT_INITIAL_HERO] = function(uid, params)
    local ok, err, result = HeroService.SelectInitialHero(uid, params and params.heroId)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success = true,
        heroId  = result.heroId,
    }
end

--- 设置头像
handlers[Protocol.ACTION_TYPES.SET_AVATAR] = function(uid, params)
    local ok, err, result = HeroService.SetAvatar(uid, params and params.avatarHeroId)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success      = true,
        avatarHeroId = result.avatarHeroId,
    }
end

--- 设置头像框
handlers[Protocol.ACTION_TYPES.SET_AVATAR_FRAME] = function(uid, params)
    local ok, err, result = HeroService.SetAvatarFrame(uid, params and params.avatarFrameId)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success       = true,
        avatarFrameId = result.avatarFrameId,
    }
end

--- 碎片合成英雄
handlers[Protocol.ACTION_TYPES.SYNTHESIZE_HERO] = function(uid, params)
    local ok, err, result = HeroService.SynthesizeHero(uid, params and params.heroId)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success         = true,
        heroId          = result.heroId,
        remainingShards = result.remainingShards,
    }
end

--- 满觉醒碎片转酒馆币
handlers[Protocol.ACTION_TYPES.CONVERT_SHARD_TO_COIN] = function(uid, params)
    local ok, err, result = HeroService.ConvertShardToCoin(uid, params and params.heroId)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success         = true,
        heroId          = result.heroId,
        remainingShards = result.remainingShards,
        coinGained      = result.coinGained,
        totalTavernCoin = result.totalTavernCoin,
    }
end

--- UR碎片1:1转化为其他英雄碎片
handlers[Protocol.ACTION_TYPES.CONVERT_UR_SHARD] = function(uid, params)
    local ok, err, result = HeroService.ConvertUrShard(
        uid,
        params and params.fromHeroId,
        params and params.toHeroId,
        params and params.amount
    )
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success = true,
        fromHeroId = result.fromHeroId,
        toHeroId = result.toHeroId,
        amount = result.amount,
        remainingFromShards = result.remainingFromShards,
        targetShards = result.targetShards,
        dailyUsed = result.dailyUsed,
        dailyLimit = result.dailyLimit,
    }
end

--- 消耗特权点恢复UR碎片转化次数
handlers[Protocol.ACTION_TYPES.RESTORE_UR_SHARD_CONVERT] = function(uid, params)
    local ok, err, result = HeroService.RestoreUrShardConvertLimit(uid)
    if not ok then
        return { success = false, reason = err }
    end
    return {
        success = true,
        dailyUsed = result.dailyUsed,
        dailyLimit = result.dailyLimit,
        cost = result.cost,
    }
end

HeroHandler.actionHandlers = handlers

return HeroHandler
