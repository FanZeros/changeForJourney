local cjson = cjson ---@diagnostic disable-line: undefined-global

-- ============================================================================
-- PlayerStore.lua — 客户端统一数据访问层（全项目唯一）
-- 路径: scripts/client/data/PlayerStore.lua
--
-- 职责:
--   1. 客户端代码读取玩家数据的唯一入口
--   2. 从 CharacterSchema 动态构建 fieldKey 映射，零硬编码
--   3. 监听 ClientDispatcher 的模块更新，维护本地只读缓存
--   4. 提供变更订阅机制，UI 通过 Subscribe 响应数据变化
--
-- 与 ClientDispatcher 的关系:
--   ClientDispatcher 是网络层数据接收器（拆分消息、组装、分发）
--   PlayerStore 是业务层数据访问器（Schema 感知、类型安全、统一入口）
--   PlayerStore 订阅 ClientDispatcher，不直接处理网络消息
--
-- 数据访问:
--   UI 统一通过 PlayerStore.Get(fieldKey) 读取（已完成迁移）
--   底层数据来自 ClientDispatcher（网络层）
--
-- 新增子系统接入方式:
--   1. 在 CharacterSchema 中注册子系统字段（Phase 2）
--   2. PlayerStore.Init() 自动订阅新字段 → 无需修改本文件
--   3. UI 通过 PlayerStore.Get(fieldKey) 读取新模块数据
-- ============================================================================

local PlayerStore = {}

local CharacterSchema  = require("shared.schemas.CharacterSchema")
local ClientDispatcher = require("network.ClientDispatcher")

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 模块数据缓存（只读镜像）
--- cache_[fieldKey] = moduleData
local cache_ = {}

--- 变更订阅者
--- subscribers_[fieldKey] = { callback1, callback2, ... }
local subscribers_ = {}

--- 全局更新回调（任何已注册模块变化时触发）
--- onAnyChange_ = function(fieldKey, data) end
local onAnyChange_ = nil

--- Schema 中注册的 fieldKey 集合（Init 时构建）
--- registeredKeys_[fieldKey] = true
local registeredKeys_ = {}

--- 是否已初始化
local inited_ = false

--- ClientDispatcher 的回调引用（用于 Cleanup 时取消订阅）
--- dispatcherCallbacks_[fieldKey] = callback
local dispatcherCallbacks_ = {}

--- WaitForChange 内部状态（前置声明，确保 Cleanup 闭包能正确捕获）
local activeWatchers_ = {}
local watcherIdSeq_ = 0
local updateSubscribed_ = false

--- 全局超时提示回调：当 WaitForChange 超时且调用者未提供 onTimeout 时触发
--- 用于统一向玩家展示"操作超时"提示（如 Toast、Loading 消失等）
--- @type fun(key: string, elapsed: number)|nil
local onWaitTimeout_ = nil

-- ============================================================================
-- 初始化 / 清理
-- ============================================================================

--- 初始化 PlayerStore（Client.lua Start 时调用一次）
--- 从 CharacterSchema.Fields 动态注册所有字段的 ClientDispatcher 订阅
function PlayerStore.Init()
    if inited_ then
        print("[PlayerStore] already initialized, skip")
        return
    end

    -- 遍历 CharacterSchema.Fields，为每个字段订阅 ClientDispatcher
    -- fieldKey 与 ClientDispatcher 的 moduleName 一致
    -- （CharacterSchema 约定 fieldKey = ModuleRegistry.modules[i].name）
    local count = 0
    for fieldKey, _def in pairs(CharacterSchema.Fields) do
        registeredKeys_[fieldKey] = true

        -- 创建闭包回调
        local callback = function(data, _moduleName)
            cache_[fieldKey] = data

            -- 通知该字段的订阅者
            local subs = subscribers_[fieldKey]
            if subs then
                for i = 1, #subs do
                    local ok, err = pcall(subs[i], data, fieldKey)
                    if not ok then
                        print("[PlayerStore] subscriber error field=" .. fieldKey
                            .. ": " .. tostring(err))
                    end
                end
            end

            -- 全局变更回调
            if onAnyChange_ then
                onAnyChange_(fieldKey, data)
            end
        end

        dispatcherCallbacks_[fieldKey] = callback
        ClientDispatcher.subscribe(fieldKey, callback)
        count = count + 1
    end

    -- 同步 ClientDispatcher 中已有的数据到缓存
    -- （可能在 Init 之前就收到了部分数据）
    for fieldKey in pairs(registeredKeys_) do
        local existing = ClientDispatcher.get(fieldKey)
        if existing then
            cache_[fieldKey] = existing
        end
    end

    inited_ = true
    print("[PlayerStore] Init complete, " .. count .. " fields registered")
end

--- 清理 PlayerStore（断线/重置时调用）
function PlayerStore.Cleanup()
    -- 取消 ClientDispatcher 订阅
    for fieldKey, callback in pairs(dispatcherCallbacks_) do
        ClientDispatcher.unsubscribe(fieldKey, callback)
    end

    cache_ = {}
    subscribers_ = {}
    registeredKeys_ = {}
    dispatcherCallbacks_ = {}
    onAnyChange_ = nil
    inited_ = false

    -- 清理 WaitForChange watchers
    -- ⚠️ 不再调用 UnsubscribeFromEvent("Update")，避免误杀 HandleUpdate_Client
    --    handleWatcherUpdate 通过 #activeWatchers_==0 自行跳过
    activeWatchers_ = {}
    watcherIdSeq_ = 0

    print("[PlayerStore] Cleanup complete")
end

--- 清空数据镜像但保留订阅关系
--- 用于同一客户端会话内切区/返回选服，等待新区全量数据重新填充。
function PlayerStore.ClearCache()
    cache_ = {}
    activeWatchers_ = {}
    watcherIdSeq_ = 0
    print("[PlayerStore] cache cleared")
end

-- ============================================================================
-- 数据读取（核心 API）
-- ============================================================================

--- 获取模块数据（只读）
--- UI 层通过此方法读取所有玩家数据
---@param fieldKey string  CharacterSchema 中的字段名（= 模块名）
---@return table|nil
function PlayerStore.Get(fieldKey)
    return cache_[fieldKey]
end

--- 获取模块数据中的指定子字段
--- 便捷方法，避免 UI 频繁做 nil 检查
---@param fieldKey string
---@param subKey string
---@return any
function PlayerStore.GetField(fieldKey, subKey)
    local mod = cache_[fieldKey]
    if mod then return mod[subKey] end
    return nil
end

--- 检查是否有数据（至少有一个模块已加载）
---@return boolean
function PlayerStore.IsReady()
    return inited_ and next(cache_) ~= nil
end

--- 检查指定模块是否已加载
---@param fieldKey string
---@return boolean
function PlayerStore.Has(fieldKey)
    return cache_[fieldKey] ~= nil
end

-- ============================================================================
-- 变更订阅
-- ============================================================================

--- 订阅指定模块的数据变更
---@param fieldKey string
---@param callback function(data: table, fieldKey: string)
function PlayerStore.Subscribe(fieldKey, callback)
    if not subscribers_[fieldKey] then
        subscribers_[fieldKey] = {}
    end
    table.insert(subscribers_[fieldKey], callback)
end

--- 取消订阅
---@param fieldKey string
---@param callback function
function PlayerStore.Unsubscribe(fieldKey, callback)
    local subs = subscribers_[fieldKey]
    if not subs then return end
    for i = #subs, 1, -1 do
        if subs[i] == callback then
            table.remove(subs, i)
            break
        end
    end
end

--- 设置全局变更回调（任何已注册模块变化时触发）
---@param callback function(fieldKey: string, data: table)|nil
function PlayerStore.SetOnAnyChange(callback)
    onAnyChange_ = callback
end

-- ============================================================================
-- WaitForChange — 等待 REPLICATED 数据到达后再回调
-- ============================================================================
-- 解决"结果事件先于数据到达"的 50-80ms 时序窗口：
--   T0  服务端 SetStat → SendToClient(RESULT)
--   T1  客户端收到 RESULT → 读 PlayerStore → 旧值（数据还没到）
--   T2  数据到达 → PlayerStore 更新 → 没人再读了
-- WaitForChange 在 T0 快照旧引用，per-frame 检测 cache_ 引用变化，
-- 变化即回调，超时兜底。

--- per-frame 检测函数（全局事件回调）
--- ⚠️ 不再调用 UnsubscribeFromEvent("Update")！
--- 因为全局 UnsubscribeFromEvent 会把所有 Update handler（包括 HandleUpdate_Client）一起取消，
--- 导致游戏逻辑停止更新、UI 冻结。改为通过标志位跳过执行。
local function handleWatcherUpdate(eventType, eventData)
    -- 无活跃 watcher 时直接跳过（替代 UnsubscribeFromEvent 的"避免空转"）
    if #activeWatchers_ == 0 then return end

    local dt = eventData["TimeStep"]:GetFloat()

    for i = #activeWatchers_, 1, -1 do
        local w = activeWatchers_[i]
        w.elapsed = w.elapsed + dt

        -- 检测变化：cjson.decode 每次产生新 table，引用不同即数据已更新
        local curRef = cache_[w.key]
        local changed = false

        if w.opts.compare then
            -- 自定义比较（传入 decode 后的新旧值）
            changed = w.opts.compare(w.oldSnapshot, curRef)
        else
            -- 默认：引用比较（table 换了引用 = 数据变了）
            changed = (curRef ~= w.oldSnapshot)
        end

        if changed then
            table.remove(activeWatchers_, i)
            if w.opts.onChange then
                local ok, err = pcall(w.opts.onChange, curRef, w.oldSnapshot)
                if not ok then
                    print("[PlayerStore] WaitForChange onChange error key="
                        .. w.key .. ": " .. tostring(err))
                end
            end
        elseif w.elapsed >= w.opts.timeout then
            table.remove(activeWatchers_, i)
            if w.opts.onTimeout then
                local ok, err = pcall(w.opts.onTimeout)
                if not ok then
                    print("[PlayerStore] WaitForChange onTimeout error key="
                        .. w.key .. ": " .. tostring(err))
                end
            else
                -- 无 onTimeout 时：触发全局超时提示 + 用当前值兜底 onChange
                print("[PlayerStore][WARN] WaitForChange TIMEOUT key="
                    .. w.key .. " elapsed=" .. string.format("%.1f", w.elapsed) .. "s")
                if onWaitTimeout_ then
                    pcall(onWaitTimeout_, w.key, w.elapsed)
                end
                if w.opts.onChange then
                    local val = cache_[w.key]
                    pcall(w.opts.onChange, val, w.oldSnapshot)
                end
            end
        end
    end
end

--- 等待 PlayerStore 某个字段变化
---@param key string       要监听的 PlayerStore 键名（= fieldKey）
---@param opts table       配置项
---@return function cancel 取消函数
---
--- opts 字段：
---   timeout    number   超时秒数（默认 5.0）
---   onChange   function(newVal, oldVal)  变化回调
---   onTimeout  function()               超时回调（可选，不设则超时时以当前值触发 onChange）
---   compare    function(old, new)->bool  自定义比较（可选，返回 true 表示"变了"）
function PlayerStore.WaitForChange(key, opts)
    opts = opts or {}
    opts.timeout = opts.timeout or 5.0

    watcherIdSeq_ = watcherIdSeq_ + 1
    local id = watcherIdSeq_

    local watcher = {
        id          = id,
        key         = key,
        oldSnapshot = cache_[key],   -- 快照当前引用
        opts        = opts,
        elapsed     = 0,
    }

    table.insert(activeWatchers_, watcher)

    -- 按需订阅 Update 事件
    if not updateSubscribed_ then
        SubscribeToEvent("Update", handleWatcherUpdate)
        updateSubscribed_ = true
    end

    -- 返回取消函数（页面销毁时调用，防止回调泄漏）
    -- ⚠️ 不再调用 UnsubscribeFromEvent("Update")，仅移除 watcher 条目；
    --    handleWatcherUpdate 通过 #activeWatchers_==0 自行跳过，避免误杀其他 Update handler
    return function()
        for i = #activeWatchers_, 1, -1 do
            if activeWatchers_[i].id == id then
                table.remove(activeWatchers_, i)
                break
            end
        end
    end
end

-- ============================================================================
-- 超时提示配置
-- ============================================================================

--- 注册全局超时提示回调
--- 当 WaitForChange 超时且调用者未提供 onTimeout 时，自动触发此回调。
--- 适合用于向玩家展示轻提示（Toast / 飘字）告知"操作超时，请检查网络"。
---@param fn fun(key: string, elapsed: number)
function PlayerStore.SetWaitTimeoutHook(fn)
    onWaitTimeout_ = fn
end

-- ============================================================================
-- 调试 / 工具
-- ============================================================================

--- 获取已注册的 fieldKey 列表（调试用）
---@return string[]
function PlayerStore.GetRegisteredKeys()
    local keys = {}
    for k in pairs(registeredKeys_) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

--- 打印当前缓存状态（调试用）
function PlayerStore.DumpState()
    print("[PlayerStore] === State Dump ===")
    print("[PlayerStore] inited=" .. tostring(inited_))
    local count = 0
    for fieldKey, data in pairs(cache_) do
        local size = 0
        if type(data) == "table" then
            local ok, json = pcall(cjson.encode, data)
            if ok then size = #json end
        end
        print("[PlayerStore]   " .. fieldKey .. " = " .. size .. " bytes")
        count = count + 1
    end
    print("[PlayerStore] total modules cached: " .. count)
    print("[PlayerStore] === End Dump ===")
end

return PlayerStore
