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
local ClientDispatcher = require("runtime.ClientDispatcher")

-- ============================================================================
-- 内部协作：镜像与版本 / 订阅发布 / Schema 绑定 / 等待队列
-- ============================================================================

-- 各容器持有当前表；清理时替换表，不复制玩家数据或捕获过期镜像。
local mirror = { data = {}, revisions = {}, revisionSeq = 0 }
local subscriptions = { fields = {}, onAnyChange = nil }
local binding = { registeredKeys = {}, callbacks = {}, inited = false }
local waiters = { active = {}, idSeq = 0, onTimeout = nil }

local function markRevision(fieldKey)
    mirror.revisionSeq = mirror.revisionSeq + 1
    mirror.revisions[fieldKey] = mirror.revisionSeq
end

local function writeMirror(fieldKey, data)
    mirror.data[fieldKey] = data
    markRevision(fieldKey)
end

local function clearRevisions()
    -- 仅使原有四类派生缓存失效；全局序列和其他字段的版本不重置。
    for _, key in ipairs({ "heroes", "equipment", "artifacts", "talents" }) do markRevision(key) end
end

local function resetWaiters()
    waiters.active = {}
    waiters.idSeq = 0
end

local function notifyField(fieldKey, data)
    -- 保持当前列表引用和 numeric-for 上界语义，回调中增删订阅不另做快照。
    local subs = subscriptions.fields[fieldKey]
    if subs then
        for i = 1, #subs do
            local ok, err = pcall(subs[i], data, fieldKey)
            if not ok then
                print("[PlayerStore] subscriber error field=" .. fieldKey
                    .. ": " .. tostring(err))
            end
        end
    end
end

local function publishField(fieldKey, data)
    writeMirror(fieldKey, data)
    notifyField(fieldKey, data)
    -- 字段回调可能替换/清空全局回调；此处现读，且仍不以 pcall 隔离。
    if subscriptions.onAnyChange then
        subscriptions.onAnyChange(fieldKey, data)
    end
end

local function bindSchemaFields()
    local count = 0
    for fieldKey, _def in pairs(CharacterSchema.Fields) do
        binding.registeredKeys[fieldKey] = true
        local callback = function(data, _moduleName)
            publishField(fieldKey, data)
        end
        binding.callbacks[fieldKey] = callback
        ClientDispatcher.subscribe(fieldKey, callback)
        count = count + 1
    end
    return count
end

local function syncExistingMirror()
    -- Init 前到达的数据只写镜像与版本，不触发字段/全局订阅。
    for fieldKey in pairs(binding.registeredKeys) do
        local existing = ClientDispatcher.get(fieldKey)
        if existing then writeMirror(fieldKey, existing) end
    end
end

local function unbindSchemaFields()
    for fieldKey, callback in pairs(binding.callbacks) do
        ClientDispatcher.unsubscribe(fieldKey, callback)
    end
end

-- ============================================================================
-- 初始化 / 清理
-- ============================================================================

--- 初始化 PlayerStore（Client.lua Start 时调用一次）
--- 从 CharacterSchema.Fields 动态注册所有字段的 ClientDispatcher 订阅
function PlayerStore.Init()
    if binding.inited then
        print("[PlayerStore] already initialized, skip")
        return
    end

    local count = bindSchemaFields()
    syncExistingMirror()
    binding.inited = true
    print("[PlayerStore] Init complete, " .. count .. " fields registered")
end

--- 清理 PlayerStore（断线/重置时调用）
function PlayerStore.Cleanup()
    clearRevisions()
    unbindSchemaFields()

    mirror.data = {}
    subscriptions.fields = {}
    binding.registeredKeys = {}
    binding.callbacks = {}
    subscriptions.onAnyChange = nil
    binding.inited = false
    resetWaiters()

    -- 全局超时 hook 与 revision 序列仍保留；不修改宿主事件订阅。
    print("[PlayerStore] Cleanup complete")
end

--- 清空数据镜像但保留订阅关系
--- 用于同一客户端会话内切区/返回选服，等待新区全量数据重新填充。
function PlayerStore.ClearCache()
    clearRevisions()
    mirror.data = {}
    resetWaiters()
    print("[PlayerStore] cache cleared")
end

function PlayerStore.GetRevision(fieldKey)
    return mirror.revisions[fieldKey] or 0
end

-- ============================================================================
-- 数据读取（核心 API）
-- ============================================================================

--- 获取模块数据（只读）
--- UI 层通过此方法读取所有玩家数据
---@param fieldKey string  CharacterSchema 中的字段名（= 模块名）
---@return table|nil
function PlayerStore.Get(fieldKey)
    return mirror.data[fieldKey]
end

--- 获取模块数据中的指定子字段
--- 便捷方法，避免 UI 频繁做 nil 检查
---@param fieldKey string
---@param subKey string
---@return any
function PlayerStore.GetField(fieldKey, subKey)
    local mod = mirror.data[fieldKey]
    if mod then return mod[subKey] end
    return nil
end

--- 检查是否有数据（至少有一个模块已加载）
---@return boolean
function PlayerStore.IsReady()
    return binding.inited and next(mirror.data) ~= nil
end

--- 检查指定模块是否已加载
---@param fieldKey string
---@return boolean
function PlayerStore.Has(fieldKey)
    return mirror.data[fieldKey] ~= nil
end

-- ============================================================================
-- 变更订阅
-- ============================================================================

--- 订阅指定模块的数据变更
---@param fieldKey string
---@param callback function(data: table, fieldKey: string)
function PlayerStore.Subscribe(fieldKey, callback)
    if not subscriptions.fields[fieldKey] then
        subscriptions.fields[fieldKey] = {}
    end
    table.insert(subscriptions.fields[fieldKey], callback)
end

--- 取消订阅
---@param fieldKey string
---@param callback function
function PlayerStore.Unsubscribe(fieldKey, callback)
    local subs = subscriptions.fields[fieldKey]
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
    subscriptions.onAnyChange = callback
end

-- ============================================================================
-- WaitForChange — 等待 REPLICATED 数据到达后再回调
-- ============================================================================
-- 解决"结果事件先于数据到达"的 50-80ms 时序窗口：
--   T0  服务端 SetStat → SendToClient(RESULT)
--   T1  客户端收到 RESULT → 读 PlayerStore → 旧值（数据还没到）
--   T2  数据到达 → PlayerStore 更新 → 没人再读了
-- WaitForChange 在 T0 快照旧引用，per-frame 检测 mirror.data 引用变化，
-- 变化即回调，超时兜底。

-- 选项属于调用者，compare/timeout/回调每次使用时现读，不缓存配置值。
local function watcherChanged(w, curRef)
    if w.opts.compare then
        -- compare 与原实现一样不隔离异常，elapsed 已在调用前推进。
        return w.opts.compare(w.oldSnapshot, curRef)
    end
    return curRef ~= w.oldSnapshot
end

local function notifyWatcherChange(w, curRef)
    if w.opts.onChange then
        local ok, err = pcall(w.opts.onChange, curRef, w.oldSnapshot)
        if not ok then
            print("[PlayerStore] WaitForChange onChange error key="
                .. w.key .. ": " .. tostring(err))
        end
    end
end

local function notifyWatcherTimeout(w)
    if w.opts.onTimeout then
        local ok, err = pcall(w.opts.onTimeout)
        if not ok then
            print("[PlayerStore] WaitForChange onTimeout error key="
                .. w.key .. ": " .. tostring(err))
        end
    else
        print("[PlayerStore][WARN] WaitForChange TIMEOUT key="
            .. w.key .. " elapsed=" .. string.format("%.1f", w.elapsed) .. "s")
        if waiters.onTimeout then
            pcall(waiters.onTimeout, w.key, w.elapsed)
        end
        -- 超时 hook 可以清理镜像或修改 opts，兜底必须在 hook 后现读。
        if w.opts.onChange then
            local val = mirror.data[w.key]
            pcall(w.opts.onChange, val, w.oldSnapshot)
        end
    end
end

local function advanceWaiters(dt)
    if #waiters.active == 0 then return end

    -- 固定倒序上界，但每轮读取当前容器；不替回调的取消/重入行为补保护。
    for i = #waiters.active, 1, -1 do
        local w = waiters.active[i]
        w.elapsed = w.elapsed + dt
        local curRef = mirror.data[w.key]
        local changed = watcherChanged(w, curRef)

        if changed then
            table.remove(waiters.active, i)
            notifyWatcherChange(w, curRef)
        elseif w.elapsed >= w.opts.timeout then
            table.remove(waiters.active, i)
            notifyWatcherTimeout(w)
        end
    end
end

local function cancelWatcher(id)
    for i = #waiters.active, 1, -1 do
        if waiters.active[i].id == id then
            table.remove(waiters.active, i)
            break
        end
    end
end

--- 主 Update 每帧调用；全局 SubscribeToEvent 对同事件是替换，不可由等待器另行订阅。
--- 超时使用原始帧时间，不受战斗暂停或变速影响。
---@param dt number
function PlayerStore.Update(dt)
    advanceWaiters(dt)
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

    waiters.idSeq = waiters.idSeq + 1
    local id = waiters.idSeq

    local watcher = {
        id          = id,
        key         = key,
        oldSnapshot = mirror.data[key],   -- 快照当前引用
        opts        = opts,
        elapsed     = 0,
    }

    table.insert(waiters.active, watcher)

    -- 只登记等待项；Standalone.HandleUpdate 统一调用 Update，不抢占游戏事件回调。

    -- 返回取消函数（页面销毁时调用，防止回调泄漏）
    -- 仅移除自己的等待项，不改变主循环订阅。
    return function()
        cancelWatcher(id)
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
    waiters.onTimeout = fn
end

-- ============================================================================
-- 调试 / 工具
-- ============================================================================

--- 获取已注册的 fieldKey 列表（调试用）
---@return string[]
function PlayerStore.GetRegisteredKeys()
    local keys = {}
    for k in pairs(binding.registeredKeys) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

--- 打印当前缓存状态（调试用）
function PlayerStore.DumpState()
    print("[PlayerStore] === State Dump ===")
    print("[PlayerStore] inited=" .. tostring(binding.inited))
    local count = 0
    for fieldKey, data in pairs(mirror.data) do
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
