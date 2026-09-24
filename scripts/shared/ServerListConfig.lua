-- ============================================================================
-- ServerListConfig - 单机仍使用的区服数据
-- 存档 key 前缀、挑战者服判断、签到开服时间、首通怪出场。
-- 选服面板分组已删除。
-- ============================================================================

local ServerListConfig = {}
local ChallengerServerConfig = require("shared.ChallengerServerConfig")
local ChallengerConsts = require("shared.challenger.ChallengerConsts")

--- 区服列表（按 id 升序排列）
--- 每个条目包含:
---   id       : 区服唯一标识（正整数，不可变）
---   name     : 区服显示名称
---   openTime : 开服时间戳（os.time 格式），0 表示已开放
-- openTime 单位：UTC 时间戳（os.time 格式）
-- 0 = 已开放
-- 1893456000 = 2030-01-01 00:00:00 UTC+8（远期占位，表示未开放）
ServerListConfig.SERVERS = {
    { id = 1,  name = "测试1服", openTime = 1893456000 },
    { id = 2,  name = "测试2服", openTime = 1893456000 },
    { id = 3,  name = "测试3服", openTime = 1893456000 },
    { id = 11, name = "启航1服", openTime = 0 },
    { id = 12, name = "启航2服", openTime = 0 },
    { id = 13, name = "启航3服", openTime = 1781568000 },
    { id = 14, name = "启航4服", openTime = 1781539200 },  -- 2026-06-16 00:00 CST
    { id = 15, name = "启航5服", openTime = 1781625600 },  -- 2026-06-17 00:00 CST
    { id = 16, name = "启航6服", openTime = 1781625600 },  -- 2026-06-17 00:00 CST
    { id = 17, name = "启航7服", openTime = 0 },
    { id = 18, name = "启航8服", openTime = 0 },
    { id = 19, name = "启航9服", openTime = 0 },
    { id = 20, name = "启航10服", openTime = 0 },
    { id = 21, name = "旅程11服", openTime = 0 },
    { id = 22, name = "旅程12服", openTime = 0 },
    { id = 23, name = "旅程13服", openTime = 0 },
    { id = 24, name = "旅程14服", openTime = 0 },
    { id = 25, name = "旅程15服", openTime = 0 },
    { id = 26, name = "旅程16服", openTime = 0 },
    { id = 27, name = "旅程17服", openTime = 0 },
    { id = 28, name = "旅程18服", openTime = 0 },
    { id = 29, name = "旅程19服", openTime = 0 },
    { id = 30, name = "旅程20服", openTime = 0 },
    { id = 31, name = "命运21服", openTime = 0 },
    { id = 32, name = "命运22服", openTime = 0 },
    { id = 33, name = "命运23服", openTime = 0 },
    { id = 34, name = "命运24服", openTime = 0 },
    { id = 35, name = "命运25服", openTime = 0 },
    { id = 36, name = "命运26服", openTime = 0 },
    { id = 37, name = "命运27服", openTime = 0 },
    { id = 38, name = "命运28服", openTime = 0 },
    { id = 39, name = "命运29服", openTime = 0 },
    { id = 40, name = "命运30服", openTime = 0 },
    { id = 901, name = "挑战者S0", openTime = 0, closeTime = 1784476800, kind = ChallengerConsts.SERVER_KIND_CHALLENGER },
    { id = 902, name = "挑战者S1", openTime = 0, closeTime = 0, kind = ChallengerConsts.SERVER_KIND_CHALLENGER },
}

--- 首通附加特殊怪物「开场出场」的最低区服 id（旅程19服起）
ServerListConfig.FIRST_CLEAR_BONUS_START_SERVER_ID = 29

--- 按 id 查找区服配置
---@param serverId number
---@return table|nil
function ServerListConfig.find(serverId)
    for _, s in ipairs(ServerListConfig.SERVERS) do
        if s.id == serverId then
            return s
        end
    end
    return nil
end

--- 获取区服类型
---@param serverId number|string|nil
---@return string|nil
function ServerListConfig.getServerKind(serverId)
    local cfg = ServerListConfig.find(tonumber(serverId))
    if not cfg then return nil end
    return cfg.kind or ChallengerConsts.SERVER_KIND_PERMANENT
end

--- 是否挑战者服
---@param serverId number|string|nil
---@return boolean
function ServerListConfig.isChallengerServer(serverId)
    return ServerListConfig.getServerKind(serverId) == ChallengerConsts.SERVER_KIND_CHALLENGER
end

--- 获取区服状态
---@param serverId number|string|nil
---@param now number|nil
---@return string "not_open"|"open"|"closed"
function ServerListConfig.getStatus(serverId, now)
    local cfg = ServerListConfig.find(tonumber(serverId))
    if not cfg then return ChallengerConsts.STATUS_CLOSED end
    now = now or os.time()
    if ServerListConfig.isChallengerServer(serverId) then
        local challengerCfg = ChallengerServerConfig.GetByServerId(serverId)
        if challengerCfg then
            return ChallengerServerConfig.GetStatus(challengerCfg, now)
        end
    end
    if cfg.openTime and cfg.openTime > 0 and now < cfg.openTime then
        return ChallengerConsts.STATUS_NOT_OPEN
    end
    if cfg.closeTime and cfg.closeTime > 0 and now >= cfg.closeTime then
        return ChallengerConsts.STATUS_CLOSED
    end
    return ChallengerConsts.STATUS_OPEN
end

--- 区服是否已关闭
---@param serverId number|string|nil
---@param now number|nil
---@return boolean
function ServerListConfig.isServerClosed(serverId, now)
    return ServerListConfig.getStatus(serverId, now) == ChallengerConsts.STATUS_CLOSED
end

--- 获取 key 前缀
---@param serverId number
---@return string  例如 "s1_"
function ServerListConfig.getKeyPrefix(serverId)
    return "s" .. tostring(serverId) .. "_"
end

--- 首通附加特殊怪物是否开场出场（旅程19服及以上为 true，旧服为 false 即最后出场）
---@param serverId number|nil
---@return boolean
function ServerListConfig.isFirstClearBonusAtStart(serverId)
    local sid = tonumber(serverId)
    if not sid then return false end
    return sid >= ServerListConfig.FIRST_CLEAR_BONUS_START_SERVER_ID
end

return ServerListConfig

