-- ============================================================================
-- ClientDispatcher - 客户端数据分发层
-- 职责: 客户端唯一的数据接收入口，收齐拆分消息 → 组装 → 分发到页面
-- 运行端: 仅客户端
-- ============================================================================

local Protocol = require("shared.Protocol")
local ModuleRegistry = require("shared.ModuleRegistry")
local CharacterSchema = require("shared.schemas.CharacterSchema")

local ClientDispatcher = {}

-- 模块数据缓存：最新的各模块数据
-- moduleData[moduleName] = data
---@type table<string, table>
local moduleData = {}

-- 订阅回调：当模块数据更新时通知
-- subscribers[moduleName] = { callback1, callback2, ... }
local subscribers = {}

-- 批次收集器：用于组装拆分消息
-- pending[batchId] = { totalCount=N, received={}, timer=T }
local pending = {}

-- 补齐超时（秒）
local RESEND_TIMEOUT = 2.0

-- 全局更新回调（收到任何数据时触发，用于 LOGO 载入页等）
local onAnyUpdate = nil

-- ======================== 内部工具 ========================

--- 解码 JSON
---@param jsonStr string
---@return table|nil
local function decode(jsonStr)
    local ok, result = pcall(cjson.decode, jsonStr)
    if ok then
        ---@cast result table
        return result
    end
    print("[ClientDispatcher] decode error: " .. tostring(result))
    return nil
end

--- 分发已收齐的数据到订阅者
---@param modules table { [moduleName] = data }
local function dispatchModules(modules)
    for name, data in pairs(modules) do
        -- cjson 反序列化后数字 key 变成字符串，需要与 Server 端一致地修正
        ModuleRegistry.applyOnLoad(name, data)
        CharacterSchema.applyOnLoad(name, data)
        moduleData[name] = data

        -- 通知该模块的订阅者
        local subs = subscribers[name]
        if subs then
            for i = 1, #subs do
                local ok, err = pcall(subs[i], data, name)
                if not ok then
                    print("[ClientDispatcher] subscriber error module=" .. name .. ": " .. tostring(err))
                end
            end
        end
    end

    -- 全局回调
    if onAnyUpdate then
        onAnyUpdate(modules)
    end
end

--- 请求服务端补齐缺失模块
---@param batchId string
---@param missingModules string[]
local function requestResend(batchId, missingModules)
    local conn = network:GetServerConnection()
    if not conn then
        print("[ClientDispatcher] no server connection for resend request")
        return
    end

    local vm = VariantMap()
    vm["Data"] = Variant(cjson.encode({
        batchId = batchId,
        missing = missingModules,
    }))
    conn:SendRemoteEvent("C_ResendRequest", true, vm)
    print("[ClientDispatcher] requesting resend for batch=" .. batchId
        .. " missing=" .. #missingModules)
end

-- ======================== 公开接口 ========================

--- 读取模块数据
---@param moduleName string
---@return table|nil
function ClientDispatcher.get(moduleName)
    return moduleData[moduleName]
end

--- 订阅模块数据变化
---@param moduleName string
---@param callback function(data, moduleName)
function ClientDispatcher.subscribe(moduleName, callback)
    if not subscribers[moduleName] then
        subscribers[moduleName] = {}
    end
    table.insert(subscribers[moduleName], callback)
end

--- 取消订阅
---@param moduleName string
---@param callback function
function ClientDispatcher.unsubscribe(moduleName, callback)
    local subs = subscribers[moduleName]
    if not subs then return end
    for i = #subs, 1, -1 do
        if subs[i] == callback then
            table.remove(subs, i)
            break
        end
    end
end

--- 手动通知指定模块的订阅者（用于 Standalone 模式直接修改数据后刷新 UI）
---@param moduleName string
function ClientDispatcher.notifySubscribers(moduleName)
    local data = moduleData[moduleName]
    if not data then return end
    local subs = subscribers[moduleName]
    if not subs then return end
    for i = 1, #subs do
        local ok, err = pcall(subs[i], data, moduleName)
        if not ok then
            print("[ClientDispatcher] notifySubscribers error module=" .. moduleName .. ": " .. tostring(err))
        end
    end
end

--- 设置全局更新回调
---@param callback function|nil
function ClientDispatcher.setOnAnyUpdate(callback)
    onAnyUpdate = callback
end

--- 处理从服务端收到的 StateUpdate 消息
--- 由 Client.lua 的事件处理器调用
---@param jsonStr string 收到的 JSON 数据
function ClientDispatcher.handleStateUpdate(jsonStr)
    local TAG = "[ClientDispatcher][DIAG-RESET]"
    local t0 = os.clock()
    local msg = decode(jsonStr)
    if not msg then
        print(string.format("%s handleStateUpdate ABORT — decode returned nil clock=%.4f jsonLen=%d",
            TAG, t0, jsonStr and #jsonStr or 0))
        return
    end

    -- 情况 1：无批次头的单条完整消息（小数据包/增量推送）
    if not msg.batchId then
        if msg.modules then
            local modNames = {}
            local heroCount = 0
            for name, data in pairs(msg.modules) do
                modNames[#modNames + 1] = name
                if name == "heroes" and type(data) == "table" and data.roster then
                    for _ in pairs(data.roster) do heroCount = heroCount + 1 end
                end
            end
            print(string.format("%s handleStateUpdate DIRECT modules=[%s] heroesRosterCount=%d clock=%.4f",
                TAG, table.concat(modNames, ","), heroCount, t0))
            dispatchModules(msg.modules)
        end
        return
    end

    -- 情况 2：有批次头的拆分消息
    local batchId = msg.batchId

    if not pending[batchId] then
        pending[batchId] = {
            totalCount = msg.totalCount or 1,
            received = {},
            timer = 0,
        }
    end

    local batch = pending[batchId]

    -- 更新总数（首条消息携带）
    if msg.totalCount then
        batch.totalCount = msg.totalCount
    end

    -- 收集
    batch.received[#batch.received + 1] = msg

    -- 检查是否收齐
    if #batch.received >= batch.totalCount then
        -- 收齐：组装完整数据
        local allModules = {}
        -- 收集分片消息：{ [moduleName] = { totalParts=N, [partIndex]=chunkStr } }
        local chunkCollector = {}

        for _, m in ipairs(batch.received) do
            if m.modules then
                -- 正常的模块消息
                for name, data in pairs(m.modules) do
                    allModules[name] = data
                end
            elseif m.chunk and m.moduleName then
                -- 分片消息：单模块超限被 JSON 字符串分片
                local modName = m.moduleName
                if not chunkCollector[modName] then
                    chunkCollector[modName] = { totalParts = m.totalParts or 1 }
                end
                chunkCollector[modName][m.partIndex] = m.chunk
            end
        end

        -- 重组分片模块
        for modName, chunks in pairs(chunkCollector) do
            local parts = {}
            local complete = true
            for i = 1, chunks.totalParts do
                if chunks[i] then
                    parts[i] = chunks[i]
                else
                    complete = false
                    print("[ClientDispatcher] missing chunk " .. i
                        .. "/" .. chunks.totalParts .. " for module " .. modName)
                    break
                end
            end
            if complete then
                local fullJson = table.concat(parts)
                local ok2, decoded = pcall(cjson.decode, fullJson)
                if ok2 and type(decoded) == "table" then
                    for name, data in pairs(decoded) do
                        allModules[name] = data
                    end
                else
                    print("[ClientDispatcher] chunk reassembly decode error for "
                        .. modName .. ": " .. tostring(decoded))
                end
            end
        end

        -- 诊断：批量重组完成
        local finalModNames = {}
        local finalHeroCount = 0
        for name, data in pairs(allModules) do
            finalModNames[#finalModNames + 1] = name
            if name == "heroes" and type(data) == "table" and data.roster then
                for _ in pairs(data.roster) do finalHeroCount = finalHeroCount + 1 end
            end
        end
        print(string.format("%s handleStateUpdate BATCH COMPLETE batchId=%s modules=[%s] heroesRosterCount=%d elapsed=%.4fs clock=%.4f",
            TAG, tostring(batchId), table.concat(finalModNames, ","), finalHeroCount,
            os.clock() - t0, os.clock()))

        dispatchModules(allModules)
        pending[batchId] = nil
    end
end

--- 每帧更新（检查超时补齐）
--- 由 Client.lua 在 HandleUpdate 中调用
---@param dt number
function ClientDispatcher.update(dt)
    local toRemove = {}

    for batchId, batch in pairs(pending) do
        batch.timer = batch.timer + dt

        if batch.timer >= RESEND_TIMEOUT then
            -- 超时：请求补齐
            -- 收集已收到的模块名
            local receivedNames = {}
            for _, m in ipairs(batch.received) do
                if m.modules then
                    for name in pairs(m.modules) do
                        receivedNames[name] = true
                    end
                end
            end

            -- 无法确定缺失哪些模块（需要服务端全量重发）
            requestResend(batchId, {})
            toRemove[#toRemove + 1] = batchId
        end
    end

    for _, batchId in ipairs(toRemove) do
        pending[batchId] = nil
    end
end

--- 清空所有缓存和订阅（重置）
function ClientDispatcher.reset()
    moduleData = {}
    subscribers = {}
    pending = {}
    onAnyUpdate = nil
end

--- 清空已接收的模块数据，但保留订阅者和全局回调
--- 用于同一客户端会话内切区/返回选服，避免旧区数据在新区全量包到达前被读取。
function ClientDispatcher.clearModuleData()
    moduleData = {}
    pending = {}
    print("[ClientDispatcher] module data cleared")
end

--- 检查进入游戏所需的核心区服数据是否已到齐
---@return boolean
function ClientDispatcher.hasData()
    local required = { "player", "currency", "heroes", "battle", "session" }
    for _, name in ipairs(required) do
        if moduleData[name] == nil then
            return false
        end
    end
    return true
end

--- 调试：返回缺失的核心模块列表
---@return string
function ClientDispatcher.getMissingRequiredModules()
    local required = { "player", "currency", "heroes", "battle", "session" }
    local missing = {}
    for _, name in ipairs(required) do
        if moduleData[name] == nil then
            missing[#missing + 1] = name
        end
    end
    return table.concat(missing, ",")
end

return ClientDispatcher
