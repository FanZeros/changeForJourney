-- ============================================================================
-- ServerDispatcher - 服务端数据分发层
-- 职责: 服务端唯一的数据推送出口，负责拆分发送、缓存、补齐、重连重发
-- 运行端: 仅服务端
-- ============================================================================

local Protocol = require("shared.Protocol")
local ArtifactSchema = require("shared.artifact.ArtifactSchema")

local ServerDispatcher = {}

-- per-UID 缓存：最近一次全量推送的完整数据
-- cache[uid] = { [moduleName] = moduleData, ... }
local cache = {}

-- 连接映射：uid → connection
-- 由 Server.lua 维护，ServerDispatcher 通过引用使用
local connections = {}

-- ======================== 初始化 ========================

--- 设置连接映射表的引用（由 Server.lua 调用）
---@param connMap table uid → connection 的映射表
function ServerDispatcher.init(connMap)
    connections = connMap
end

-- ======================== 内部工具 ========================

--- 将数据编码为 JSON 字符串
---@param data table
---@return string
local function encode(data)
    local ok, result = pcall(cjson.encode, data)
    if ok then return result end
    print("[ServerDispatcher] encode error: " .. tostring(result))
    return "{}"
end

--- 向指定 UID 的客户端发送远程事件
---@param uid number
---@param eventName string
---@param payload table
local function sendToClient(uid, eventName, payload)
    local conn = connections[uid]
    if not conn then
        print("[ServerDispatcher] no connection for uid=" .. tostring(uid))
        return
    end

    local jsonStr = encode(payload)
    local vm = VariantMap()
    vm["Data"] = Variant(jsonStr)

    conn:SendRemoteEvent(eventName, true, vm)
end

local function prepareModuleForPush(moduleName, moduleData)
    if moduleName == "equipment" and type(moduleData) == "table" and moduleData.inventory then
        local EquipmentSystem = require("systems.EquipmentSystem")
        local lean = {}
        for k, v in pairs(moduleData) do
            lean[k] = v
        end
        lean.inventory = EquipmentSystem.dehydrateInventory(moduleData.inventory)
        return lean
    end

    if moduleName == "artifacts" and type(moduleData) == "table" then
        return ArtifactSchema.dehydrateModule(moduleData)
    end

    return moduleData
end

local function prepareModulesForPush(allModulesData)
    local lean = {}
    for name, data in pairs(allModulesData or {}) do
        lean[name] = prepareModuleForPush(name, data)
    end
    return lean
end

--- 按模块拆分数据，检查每条是否超过安全阈值
--- 超过阈值的模块进一步分片
---@param allModulesData table { [moduleName] = moduleData }
---@return table[] 消息列表 { { modules = { [name]=data }, batchId?, totalCount?, partIndex?, totalParts? } }
local function splitMessages(allModulesData)
    local messages = {}
    local moduleNames = {}
    for name in pairs(allModulesData) do
        moduleNames[#moduleNames + 1] = name
    end
    table.sort(moduleNames)

    -- 逐模块检测大小
    local totalSize = #encode(allModulesData)

    if totalSize < Protocol.MSG_SAFE_SIZE then
        -- 小数据包，不拆分
        messages[1] = { modules = allModulesData }
        return messages
    end

    -- 需要拆分：按模块分发
    local batchId = tostring(os.time()) .. "_" .. tostring(math.random(10000))

    for _, name in ipairs(moduleNames) do
        local moduleData = allModulesData[name]
        local moduleJson = encode({ [name] = moduleData })

        if #moduleJson < Protocol.MSG_SAFE_SIZE then
            -- 单模块未超限，作为一条消息
            messages[#messages + 1] = {
                modules = { [name] = moduleData },
                batchId = batchId,
            }
        else
            -- 单模块超限，需要分片（简化实现：以 JSON 字符串分片）
            local chunks = {}
            local chunkSize = Protocol.MSG_SAFE_SIZE - 1000  -- 留出头部空间
            for i = 1, #moduleJson, chunkSize do
                chunks[#chunks + 1] = moduleJson:sub(i, i + chunkSize - 1)
            end
            for ci, chunk in ipairs(chunks) do
                messages[#messages + 1] = {
                    moduleName = name,
                    chunk = chunk,
                    partIndex = ci,
                    totalParts = #chunks,
                    batchId = batchId,
                }
            end
        end
    end

    -- 为第一条消息标注总数
    if #messages > 0 then
        messages[1].totalCount = #messages
    end

    return messages
end

-- ======================== 公开接口 ========================

--- 全量推送（进入游戏 / 重连）
---@param uid number
---@param allModulesData table { [moduleName] = moduleData }
function ServerDispatcher.pushFullState(uid, allModulesData)
    local TAG = "[ServerDispatcher][DIAG-RESET]"
    local t0 = os.clock()

    -- 诊断：列出所有推送模块及关键数据大小
    local modNames = {}
    local heroCount = 0
    for name, data in pairs(allModulesData) do
        modNames[#modNames + 1] = name
        if name == "heroes" and type(data) == "table" and data.roster then
            for _ in pairs(data.roster) do heroCount = heroCount + 1 end
        end
    end
    print(string.format("%s pushFullState START uid=%s moduleList=[%s] heroesRosterCount=%d clock=%.4f",
        TAG, tostring(uid), table.concat(modNames, ","), heroCount, t0))

    local pushData = prepareModulesForPush(allModulesData)

    -- 更新缓存
    cache[uid] = {}
    for name, data in pairs(pushData) do
        cache[uid][name] = data
    end

    -- 拆分并发送
    local messages = splitMessages(pushData)
    for i, msg in ipairs(messages) do
        sendToClient(uid, Protocol.RES_STATE_UPDATE, msg)
    end

    print(string.format("%s pushFullState DONE uid=%s msgCount=%d elapsed=%.4fs clock=%.4f",
        TAG, tostring(uid), #messages, os.clock() - t0, os.clock()))
end

--- 增量推送（markDirty 触发，仅推送单个模块）
---@param uid number
---@param moduleName string
---@param moduleData table|false  -- false 表示清除该模块（客户端收到后按无数据处理）
function ServerDispatcher.pushModule(uid, moduleName, moduleData)
    local pushModuleData = prepareModuleForPush(moduleName, moduleData)

    -- 更新缓存
    if not cache[uid] then
        cache[uid] = {}
    end
    cache[uid][moduleName] = pushModuleData

    -- 检查大小，超限时走分片逻辑（与 pushFullState 一致）
    local singleModuleData = { [moduleName] = pushModuleData }
    local messages = splitMessages(singleModuleData)
    for _, msg in ipairs(messages) do
        sendToClient(uid, Protocol.RES_STATE_UPDATE, msg)
    end

    if #messages > 1 then
        print("[ServerDispatcher] pushModule SPLIT uid=" .. tostring(uid)
            .. " module=" .. moduleName .. " msgs=" .. #messages)
    end
end

--- 补齐响应（客户端请求缺失模块）
--- 优先读 PDM 权威数据；批次超时（missing 为空）时返回 false 触发全量重建
---@param uid number
---@param missingModules string[] 缺失的模块名列表
function ServerDispatcher.handleResendRequest(uid, missingModules)
    local cached = cache[uid]
    if not cached then
        print("[ServerDispatcher] no cache for uid=" .. tostring(uid) .. ", triggering full rebuild")
        return false
    end

    missingModules = missingModules or {}
    if #missingModules == 0 then
        print("[ServerDispatcher] handleResendRequest empty missing uid=" .. tostring(uid)
            .. " → full rebuild")
        return false
    end

    local PDM = require("server.character.PlayerDataManager")
    local pdmLoaded = PDM.IsLoaded(uid)

    local resendData = {}
    for _, name in ipairs(missingModules) do
        local data = nil
        if pdmLoaded then
            data = PDM.GetModule(uid, name)
        end
        if not data then
            data = cached[name]
        end
        if data then
            resendData[name] = data
        end
    end

    if not next(resendData) then
        print("[ServerDispatcher] handleResendRequest no data for requested modules uid="
            .. tostring(uid))
        return false
    end

    local payload = { modules = resendData, isResend = true }
    sendToClient(uid, Protocol.RES_STATE_UPDATE, payload)
    return true
end

--- 重连重发（从缓存重发全部数据）
---@param uid number
---@return boolean 是否成功（缓存为空返回 false）
function ServerDispatcher.resendFromCache(uid)
    local cached = cache[uid]
    if not cached or not next(cached) then
        print("[ServerDispatcher] no cache for reconnect uid=" .. tostring(uid))
        return false
    end

    local messages = splitMessages(cached)
    for _, msg in ipairs(messages) do
        sendToClient(uid, Protocol.RES_STATE_UPDATE, msg)
    end

    print("[ServerDispatcher] resendFromCache uid=" .. tostring(uid))
    return true
end

--- 检查缓存是否存在
---@param uid number
---@return boolean
function ServerDispatcher.hasCache(uid)
    return cache[uid] ~= nil and next(cache[uid]) ~= nil
end

--- 清理缓存
---@param uid number
function ServerDispatcher.clearCache(uid)
    cache[uid] = nil
end

--- 向指定客户端发送自定义事件
---@param uid number
---@param eventName string
---@param data table
function ServerDispatcher.sendEvent(uid, eventName, data)
    sendToClient(uid, eventName, data)
end

return ServerDispatcher
