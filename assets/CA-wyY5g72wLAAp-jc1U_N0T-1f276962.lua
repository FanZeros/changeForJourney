-- ============================================================================
-- GuildHandler - 冒险者公会网络事件路由层（薄 Handler）
-- 异步 handler 返回 nil，通过 respond() 在回调中发送结果
-- ============================================================================

local Protocol         = require("shared.Protocol")
local ServerDispatcher = require("network.ServerDispatcher")
local GuildService     = require("server.guild.GuildService")

local GuildHandler = {}
local handlers = {}

--- 异步响应封装
---@param uid number
---@param result table
local function respond(uid, result)
    ServerDispatcher.sendEvent(uid, Protocol.RES_ACTION_RESULT, result)
end

--- GUILD_ENTER: 进入公会（异步）
handlers[Protocol.ACTION_TYPES.GUILD_ENTER] = function(uid, params)
    GuildService.Enter(uid, params, function(result)
        respond(uid, result)
    end)
    return nil
end

GuildHandler.actionHandlers = handlers
return GuildHandler
