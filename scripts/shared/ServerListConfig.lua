-- ============================================================================
-- ServerListConfig - 区服列表静态配置（双端共享）
-- 职责: 定义所有区服的 id、名称、开服时间
-- 运行端: shared（服务端 + 客户端都加载）
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

--- 区服系列（选服面板左侧标签分组）
--- voyage : 启航服，id 11-20 → 展示编号 1-10
--- journey: 旅程服，id 21-30 → 展示编号 11-20
--- destiny: 命运服，id 31-40 → 展示编号 21-30
ServerListConfig.SERIES = {
    voyage = {
        label       = "启航",
        idMin       = 11,
        idMax       = 20,
        displayBase = 10,   -- displayNum = id - displayBase
    },
    journey = {
        label       = "旅程",
        idMin       = 21,
        idMax       = 30,
        displayBase = 10,   -- displayNum = id - 10 → 旅程11服起
    },
    destiny = {
        label       = "命运",
        idMin       = 31,
        idMax       = 40,
        displayBase = 10,   -- displayNum = id - 10 → 命运21服起
    },
}

--- 系列在选服面板中的展示顺序（新系列靠前）
ServerListConfig.SERIES_ORDER = { "destiny", "journey", "voyage" }

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

--- 校验 serverId 是否合法（存在、已开放、未关闭）
---@param serverId number
---@return boolean
function ServerListConfig.isValid(serverId)
    local cfg = ServerListConfig.find(serverId)
    if not cfg then return false end
    if ServerListConfig.isServerClosed(serverId) then
        return false
    end
    if cfg.openTime > 0 and os.time() < cfg.openTime then
        return false
    end
    return true
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

--- 是否非挑战者区服
---@param serverId number|string|nil
---@return boolean
function ServerListConfig.isNonChallengerServer(serverId)
    local cfg = ServerListConfig.find(tonumber(serverId))
    return cfg ~= nil and not ServerListConfig.isChallengerServer(serverId)
end

--- 是否常驻正式/测试区服
---@param serverId number|string|nil
---@return boolean
function ServerListConfig.isPermanentServer(serverId)
    return ServerListConfig.isNonChallengerServer(serverId)
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

--- 校验 serverId 对指定玩家是否可进入
--- 规则: 区服已开放 OR 玩家已在该区服创建过角色
---@param serverId number
---@param createdServerIds table<number|string, any>|nil  玩家已创建角色的区服集合 (gp.servers)
---@return boolean
function ServerListConfig.isAccessible(serverId, createdServerIds)
    local cfg = ServerListConfig.find(serverId)
    if not cfg then return false end
    if ServerListConfig.isServerClosed(serverId) then
        return false
    end
    -- 已开放的区服，任何人都可进入
    if cfg.openTime <= 0 or os.time() >= cfg.openTime then
        return true
    end
    -- 未开放的区服，只有已创建过角色的非挑战者服玩家可进入
    if createdServerIds and not ServerListConfig.isChallengerServer(serverId) then
        if createdServerIds[serverId] or createdServerIds[tostring(serverId)] then
            return true
        end
    end
    return false
end

--- 获取全部已开放的区服列表
---@return table[]
function ServerListConfig.getOpenServers()
    local now = os.time()
    local result = {}
    for _, s in ipairs(ServerListConfig.SERVERS) do
        if ServerListConfig.getStatus(s.id, now) == ChallengerConsts.STATUS_OPEN then
            result[#result + 1] = s
        end
    end
    return result
end

--- 获取 key 前缀
---@param serverId number
---@return string  例如 "s1_"
function ServerListConfig.getKeyPrefix(serverId)
    return "s" .. tostring(serverId) .. "_"
end

--- 获取区服所属系列（正式服）；测试服 1-10 返回 nil
---@param serverId number
---@return string|nil  "voyage" | "journey"
function ServerListConfig.getSeries(serverId)
    for key, cfg in pairs(ServerListConfig.SERIES) do
        if serverId >= cfg.idMin and serverId <= cfg.idMax then
            return key
        end
    end
    return nil
end

--- 获取区服在系列内的展示编号（启航1服→1，旅程1服→1）
---@param serverId number
---@return number|nil
function ServerListConfig.getDisplayNum(serverId)
    local seriesKey = ServerListConfig.getSeries(serverId)
    if not seriesKey then return nil end
    local cfg = ServerListConfig.SERIES[seriesKey]
    return serverId - cfg.displayBase
end

--- 首通附加特殊怪物是否开场出场（旅程19服及以上为 true，旧服为 false 即最后出场）
---@param serverId number|nil
---@return boolean
function ServerListConfig.isFirstClearBonusAtStart(serverId)
    local sid = tonumber(serverId)
    if not sid then return false end
    return sid >= ServerListConfig.FIRST_CLEAR_BONUS_START_SERVER_ID
end

--- 获取全部已开放的正式区服（排除测试服 1-10）
---@return table[]
function ServerListConfig.getOpenFormalServers()
    local result = {}
    for _, s in ipairs(ServerListConfig.getOpenServers()) do
        if ServerListConfig.getSeries(s.id) then
            result[#result + 1] = s
        end
    end
    return result
end

return ServerListConfig

