-- ============================================================================
-- GuildConfig - 冒险者公会配置（双端共享）
-- 职责: 排行榜 cloud key 定义
-- 运行端: shared（服务端 + 客户端都加载）
-- ============================================================================

local GuildConfig = {}

local ServerListConfig = require("shared.ServerListConfig")

--- 基础 key 名映射（不含区服前缀）
local BASE_KEYS = {
    STAGE_RANK = "guild_stage_rank",  -- 关卡进度排行榜 (SetInt, score=maxStageId)
}

--- 获取带区服前缀的 cloud key
---@param keyName string  BASE_KEYS 中的 key 名
---@param serverId number 区服 ID
---@return string  带前缀的完整 key，如 "s1_guild_stage_rank"
function GuildConfig.getCloudKey(keyName, serverId)
    local base = BASE_KEYS[keyName]
    if not base then
        error("[GuildConfig] unknown cloud key name: " .. tostring(keyName))
    end
    local prefix = ServerListConfig.getKeyPrefix(serverId)
    return prefix .. base
end

GuildConfig.CLOUD_KEYS = BASE_KEYS

return GuildConfig
