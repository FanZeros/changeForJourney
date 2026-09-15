-- ============================================================================
-- SaveManager - 服务端存档系统
-- 职责: 管理每个玩家的实时数据表、防抖存盘到云端、即时推送到客户端
-- 运行端: 仅服务端
-- ============================================================================
-- 核心概念:
--   单表模型: 每个 scores key 一张实时表（内存），没有备份表
--   统一防抖: 全局一个计时器（默认 5 秒），markDirty 确保计时器在跑
--   markDirty 双职责: 1. 即时推送该模块的展示数据  2. 启动存档防抖计时器
-- ============================================================================

local ModuleRegistry    = require("shared.ModuleRegistry")
local ServerListConfig  = require("shared.ServerListConfig")
local Protocol          = require("shared.Protocol")
local ServerDispatcher  = require("network.ServerDispatcher")
local CharacterSchema   = require("shared.schemas.CharacterSchema")

local SaveManager = {}

-- ======================== 配置 ========================

local DEBOUNCE_SECONDS = 0.5      -- 防抖周期（秒）— 缩短以减少跨服回档风险
local RATE_LIMIT_PER_SEC = 2      -- 每玩家每秒最大请求数
local CLEANUP_RETRY_MAX  = 3      -- 断线存档最大重试次数
local CLEANUP_RETRY_DELAY = 2     -- 断线存档重试间隔（秒）
local LOAD_TIMEOUT_SECONDS = 8.0  -- serverCloud:Get 无回调兜底，避免客户端永久 loading

-- ======================== 内部状态 ========================

--- 区服模块注册信息 { [moduleName] = { key, getDefault, onLoad, onCleanup } }
local registeredModules = {}

--- 全局模块注册信息 { [moduleName] = { key, getDefault, onLoad, onCleanup } }
local globalModules = {}

--- 玩家当前选择的区服 ID  serverId_[uid] = number
local serverId_ = {}

--- 实时数据表  tables[uid] = { [moduleName] = { ...data... }, ... }
local tables = {}

--- 加载状态  loadState[uid] = "loading" | "loaded" | nil
local loadState = {}

--- 脏模块标记  dirtyModules[uid] = { [moduleName] = true, ... }
local dirtyModules = {}

--- 脏 UID 集合  dirtyUIDs[uid] = true
local dirtyUIDs = {}

--- 防抖计时器状态
local debounceTimer = 0           -- 剩余时间
local debounceRunning = false     -- 计时器是否在跑

--- 频率限制  rateLimiter[uid] = { count=0, resetTime=0 }
local rateLimiter = {}

--- sessionVersion 防护  sessionVersions[uid] = number
local sessionVersions = {}

--- 断线存档重试队列  cleanupRetries[uid] = { data={...}, retryCount=N, timer=T }
local cleanupRetries = {}

--- 读档超时追踪 loadTimeouts[uid] = { kind, sv, timer, pendingKeys={ [key]=true }, callback }
local loadTimeouts = {}

--- 读档诊断钩子：由 Server.lua 注入，把服务端读档过程转发到客户端反馈日志
--- @type fun(uid: number, message: string)|nil
local loadDiagHook = nil

local function emitLoadDiag(uid, message)
    print("[SaveManager][LOAD-DIAG] uid=" .. tostring(uid) .. " " .. tostring(message))
    if loadDiagHook then
        local ok, err = pcall(loadDiagHook, uid, "SM " .. tostring(message))
        if not ok then
            print("[SaveManager][LOAD-DIAG] hook error: " .. tostring(err))
        end
    end
end

-- ======================== PDM 防御性跳过（防丢档） ========================
-- PDM (PlayerDataManager) 是 CharacterSchema 中 cloudKey 的权威写入者。
-- SaveManager 不得写入 PDM 管理的 cloudKey，否则可能用陈旧数据覆盖 PDM 的最新数据。
-- 惰性构建一次，后续直接查表。

---@type table<string, true>|nil
local pdmManagedKeys_ = nil

--- 获取 PDM 管理的 cloudKey 集合（惰性构建）
---@return table<string, true>
local function getPdmManagedKeys()
    if pdmManagedKeys_ then return pdmManagedKeys_ end
    pdmManagedKeys_ = {}
    for _, def in pairs(CharacterSchema.Fields) do
        if type(def.persist) == "table" and def.persist.via == "cloud" and def.persist.cloudKey then
            pdmManagedKeys_[def.persist.cloudKey] = true
        end
    end
    -- 打印一次供调试
    local keys = {}
    for k in pairs(pdmManagedKeys_) do keys[#keys + 1] = k end
    table.sort(keys)
    print("[SaveManager] PDM managed cloudKeys (" .. #keys .. "): " .. table.concat(keys, ", "))
    return pdmManagedKeys_
end

--- 检查一个原始 cloudKey (不含区服前缀) 是否被 PDM 管理
---@param rawKey string  如 "mod_player", "global_profile"
---@return boolean
local function isPdmManagedKey(rawKey)
    return getPdmManagedKeys()[rawKey] == true
end

-- ======================== 模块注册 ========================

--- 注册需要持久化的模块
--- 通常在 Server.lua 启动时从 ModuleRegistry 自动注册
---@param moduleName string
---@param config table { key?, getDefault, onLoad?, onCleanup? }
function SaveManager.register(moduleName, config)
    registeredModules[moduleName] = {
        key        = config.key or "save_data",
        getDefault = config.getDefault,
        onLoad     = config.onLoad,
        onCleanup  = config.onCleanup,
    }
    print("[SaveManager] registered module: " .. moduleName
        .. " -> key=" .. (config.key or "save_data"))
end

--- 从 ModuleRegistry 自动注册所有区服模块
function SaveManager.registerFromRegistry()
    for _, m in ipairs(ModuleRegistry.modules) do
        SaveManager.register(m.name, {
            key        = m.key,
            getDefault = m.getDefault,
            onLoad     = m.onLoad,
            onCleanup  = m.onCleanup,
        })
    end
    -- 同时注册全局模块
    for _, m in ipairs(ModuleRegistry.globalModules) do
        globalModules[m.name] = {
            key        = m.key,
            getDefault = m.getDefault,
            onLoad     = m.onLoad,
            onCleanup  = m.onCleanup,
        }
        print("[SaveManager] registered global module: " .. m.name
            .. " -> key=" .. m.key)
    end
end

---@param fn fun(uid: number, message: string)|nil
function SaveManager.setLoadDiagHook(fn)
    loadDiagHook = fn
end

-- ======================== 区服 ID 管理 ========================

--- 设置玩家当前的区服 ID（选服后调用）
---@param uid number
---@param serverId number
function SaveManager.setServerId(uid, serverId)
    serverId_[uid] = serverId
    print("[SaveManager] setServerId uid=" .. tostring(uid) .. " serverId=" .. tostring(serverId))
end

--- 获取玩家当前的区服 ID
---@param uid number
---@return number|nil
function SaveManager.getServerId(uid)
    return serverId_[uid]
end

--- 获取指定 uid 的区服 key 前缀
---@param uid number
---@return string  例如 "s1_"，未选服返回空字符串
local function getServerPrefix(uid)
    local sid = serverId_[uid]
    if sid then
        return ServerListConfig.getKeyPrefix(sid)
    end
    return ""
end

-- ======================== 数据加载 ========================

--- 合并模块数据：默认值为底，云端数据覆盖，执行 onLoad 回调
---@param moduleName string
---@param cloudData table|nil  云端返回的模块数据
---@return table merged
local function mergeModuleData(moduleName, cloudData)
    local reg = registeredModules[moduleName]
    local defaultData = reg.getDefault()
    local merged = {}
    for k, v in pairs(defaultData) do
        merged[k] = v
    end
    if type(cloudData) == "table" then
        for k, v in pairs(cloudData) do
            merged[k] = v
        end
    end
    if reg.onLoad then
        local ok2, err = pcall(reg.onLoad, merged)
        if not ok2 then
            print("[SaveManager] onLoad error for " .. moduleName .. ": " .. tostring(err))
        end
    end
    return merged
end

--- 完成加载流程（设置 _meta、标记 loaded、回调）
---@param uid number
---@param callback function(success: boolean)
local function finalizeLoad(uid, callback)
    tables[uid]._meta = {
        lastSaveTime = os.time(),
        loadTime     = os.time(),
    }
    loadState[uid] = "loaded"
    print("[SaveManager] load complete uid=" .. tostring(uid))
    if callback then callback(true) end
end

--- 启动防抖计时器（如果有脏数据）
local function startDebouncIfDirty()
    if next(dirtyUIDs) and not debounceRunning then
        debounceTimer = DEBOUNCE_SECONDS
        debounceRunning = true
    end
end


--- 加载全局层数据（选服之前调用，仅加载 global_profile 等）
--- 加载后数据存入 tables[uid]，但不标记 loadState 为 "loaded"
---@param uid number
---@param callback function(success: boolean, globalProfile: table|nil)
function SaveManager.loadGlobalProfile(uid, callback)
    -- 递增 sessionVersion
    local sv = (sessionVersions[uid] or 0) + 1
    sessionVersions[uid] = sv

    if not tables[uid] then
        tables[uid] = {}
    end

    -- 收集全局模块的 key
    local keyModules = {}
    for name, reg in pairs(globalModules) do
        local k = reg.key
        if not keyModules[k] then keyModules[k] = {} end
        keyModules[k][#keyModules[k] + 1] = name
    end

    local keyList = {}
    for k in pairs(keyModules) do
        keyList[#keyList + 1] = k
    end

    if #keyList == 0 then
        -- 无全局模块，直接返回
        if callback then callback(true, nil) end
        return
    end

    local pendingKeys = #keyList
    local hasError = false
    local pendingKeyMap = {}
    for _, key in ipairs(keyList) do
        pendingKeyMap[key] = true
    end
    loadTimeouts[uid] = {
        kind = "global",
        sv = sv,
        timer = 0,
        pendingKeys = pendingKeyMap,
        callback = callback,
    }

    for _, key in ipairs(keyList) do
        emitLoadDiag(uid, "global START key=" .. tostring(key) .. " sv=" .. tostring(sv))
        serverCloud:Get(uid, key, {
            ok = function(scores)
                if sessionVersions[uid] ~= sv then return end
                if not loadTimeouts[uid] or loadTimeouts[uid].sv ~= sv then return end
                loadTimeouts[uid].pendingKeys[key] = nil

                local rawScores = scores or {}
                local cloudData = rawScores[key]
                local cloudSize = 0
                local sizeOk, sizeJson = pcall(cjson.encode, cloudData or {})
                if sizeOk and sizeJson then cloudSize = #sizeJson end
                emitLoadDiag(uid, "global OK key=" .. tostring(key) .. " size=" .. tostring(cloudSize))
                if type(cloudData) ~= "table" then cloudData = {} end

                for _, moduleName in ipairs(keyModules[key]) do
                    local reg = globalModules[moduleName]
                    local savedData = cloudData[moduleName]
                    -- 合并默认值 + 云端数据
                    local defaultData = reg.getDefault()
                    local merged = {}
                    for k2, v in pairs(defaultData) do merged[k2] = v end
                    if type(savedData) == "table" then
                        for k2, v in pairs(savedData) do merged[k2] = v end
                    end
                    if reg.onLoad then
                        pcall(reg.onLoad, merged)
                    end
                    tables[uid][moduleName] = merged
                end

                pendingKeys = pendingKeys - 1
                if pendingKeys <= 0 and not hasError then
                    loadTimeouts[uid] = nil
                    -- 首次登录：设置 createTime
                    local gp = tables[uid]["global_profile"]
                    if gp and gp.createTime == 0 then
                        gp.createTime = os.time()
                        -- 标记脏，后续会写入
                        if not dirtyModules[uid] then dirtyModules[uid] = {} end
                        dirtyModules[uid]["global_profile"] = true
                        dirtyUIDs[uid] = true
                        if not debounceRunning then
                            debounceTimer = DEBOUNCE_SECONDS
                            debounceRunning = true
                        end
                    end
                    print("[SaveManager] loadGlobalProfile ok uid=" .. tostring(uid))
                    if callback then callback(true, gp) end
                end
            end,
            error = function(code, reason)
                if sessionVersions[uid] ~= sv then return end
                if not loadTimeouts[uid] or loadTimeouts[uid].sv ~= sv then return end
                print("[SaveManager] loadGlobalProfile error uid=" .. tostring(uid)
                    .. " key=" .. key .. " code=" .. tostring(code))
                emitLoadDiag(uid, "global ERROR key=" .. tostring(key)
                    .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
                if not hasError then
                    hasError = true
                    loadTimeouts[uid] = nil
                    if callback then callback(false, nil) end
                end
            end,
        })
    end
end

--- 从云端加载玩家区服存档并初始化实时表
--- 必须先调用 setServerId 设置区服 ID
--- 支持旧 key ("save_data") → 新 key (mod_xxx) 的自动迁移
---@param uid number
---@param callback function(success: boolean)
function SaveManager.load(uid, callback)
    if loadState[uid] == "loaded" then
        print("[SaveManager] uid=" .. tostring(uid) .. " already loaded")
        if callback then callback(true) end
        return
    end

    loadState[uid] = "loading"

    -- 递增 sessionVersion，让旧回调失效
    local sv = (sessionVersions[uid] or 0) + 1
    sessionVersions[uid] = sv

    local prefix = getServerPrefix(uid)
    if prefix == "" then
        print("[SaveManager] WARNING: load called without setServerId! uid=" .. tostring(uid))
    end

    -- 收集需要加载的 prefixedKey → modules 映射
    local keyModules = {}   -- { [prefixedKey] = { moduleName1, moduleName2, ... } }
    for name, reg in pairs(registeredModules) do
        local k = prefix .. reg.key
        if not keyModules[k] then keyModules[k] = {} end
        keyModules[k][#keyModules[k] + 1] = name
    end

    -- 统计需要完成的 key 数量
    local keyList = {}
    for k in pairs(keyModules) do
        keyList[#keyList + 1] = k
    end

    if #keyList == 0 then
        if not tables[uid] then tables[uid] = {} end
        loadState[uid] = "loaded"
        if callback then callback(true) end
        return
    end

    -- 初始化实时表（保留已加载的全局模块数据）
    if not tables[uid] then tables[uid] = {} end
    -- 清除旧区服模块数据（换服时需要）
    for name in pairs(registeredModules) do
        tables[uid][name] = nil
    end

    table.sort(keyList)

    local pendingKeyMap = {}
    for _, key in ipairs(keyList) do
        pendingKeyMap[key] = true
    end
    loadTimeouts[uid] = {
        kind = "player",
        sv = sv,
        timer = 0,
        pendingKeys = pendingKeyMap,
        callback = callback,
    }

    -- 区服读档改为单次 BatchGet，避免同一玩家进入老区时大量并发 serverCloud:Get
    -- 造成个别 key 回调丢失。此处只加载内存副本，不写云端；权威数据随后由 PDM 覆盖。
    local batch = serverCloud:BatchGet(uid)
    for _, key in ipairs(keyList) do
        emitLoadDiag(uid, "player START key=" .. tostring(key) .. " sv=" .. tostring(sv)
            .. " modules=" .. table.concat(keyModules[key] or {}, ","))
        batch:Key(key)
    end

    batch:Fetch({
        ok = function(scores)
            if sessionVersions[uid] ~= sv then return end
            if not loadTimeouts[uid] or loadTimeouts[uid].sv ~= sv then return end

            local rawScores = scores or {}
            for _, key in ipairs(keyList) do
                loadTimeouts[uid].pendingKeys[key] = nil

                local cloudData = rawScores[key]
                local cloudSize = 0
                local sizeOk, sizeJson = pcall(cjson.encode, cloudData or {})
                if sizeOk and sizeJson then cloudSize = #sizeJson end
                emitLoadDiag(uid, "player OK key=" .. tostring(key) .. " size=" .. tostring(cloudSize)
                    .. " modules=" .. table.concat(keyModules[key] or {}, ","))
                if type(cloudData) ~= "table" then cloudData = {} end

                for _, moduleName in ipairs(keyModules[key]) do
                    local savedData = cloudData[moduleName]
                    tables[uid][moduleName] = mergeModuleData(moduleName, savedData)
                end
            end

            loadTimeouts[uid] = nil
            -- 所有前缀 key 读取完毕，直接完成加载
            -- 注：旧存档迁移已移除（分区服之前仅有测试数据，无需迁移）
            finalizeLoad(uid, callback)
        end,

        error = function(code, reason)
            if sessionVersions[uid] ~= sv then return end
            if not loadTimeouts[uid] or loadTimeouts[uid].sv ~= sv then return end

            print("[SaveManager] cloud BatchGet error uid=" .. tostring(uid)
                .. " code=" .. tostring(code)
                .. " reason=" .. tostring(reason))
            emitLoadDiag(uid, "player ERROR batch keys=" .. table.concat(keyList, ",")
                .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))

            loadTimeouts[uid] = nil
            loadState[uid] = nil
            if callback then callback(false) end
        end,
    })
end

-- ======================== 数据读写 ========================

--- 获取模块实时表引用（直接读写）
---@param uid number
---@param moduleName string
---@return table|nil
function SaveManager.getTable(uid, moduleName)
    if not tables[uid] then return nil end
    return tables[uid][moduleName]
end

--- 获取玩家的所有模块数据（用于全量推送）
---@param uid number
---@return table|nil  { [moduleName] = data, ... }
function SaveManager.getAllTables(uid)
    return tables[uid]
end

-- forward declaration (body defined at line ~483, after globalModules/registeredModules)
local findModuleReg

--- 用 PDM 权威数据覆盖 SaveManager 内存副本（不标脏、不写盘）
--- 登录后 PDM 覆盖 pushData 时同步调用，避免 SM 副本长期滞后于 PDM。
---@param uid number
---@param moduleName string
---@param data table
function SaveManager.replaceModuleMemory(uid, moduleName, data)
    if not tables[uid] or type(data) ~= "table" then return end
    local reg = findModuleReg(moduleName)
    if not reg then return end
    local merged = {}
    local defaultData = reg.getDefault and reg.getDefault() or {}
    if type(defaultData) == "table" then
        for k, v in pairs(defaultData) do merged[k] = v end
    end
    for k, v in pairs(data) do merged[k] = v end
    if reg.onLoad then
        pcall(reg.onLoad, merged)
    end
    tables[uid][moduleName] = merged
end

-- ======================== markDirty（核心） ========================

--- 标记模块已变更
--- 双职责:
---   1. 立即通过 ServerDispatcher 推送该模块数据到客户端
---   2. 将该模块加入脏标记，启动防抖计时器等待批量存盘
---@param uid number
---@param moduleName string
function SaveManager.markDirty(uid, moduleName)
    if not tables[uid] or not tables[uid][moduleName] then
        print("[SaveManager] markDirty: no data for uid=" .. tostring(uid)
            .. " module=" .. moduleName)
        return
    end

    -- 1. 即时推送到客户端
    ServerDispatcher.pushModule(uid, moduleName, tables[uid][moduleName])

    -- 2. 加入脏标记
    if not dirtyModules[uid] then
        dirtyModules[uid] = {}
    end
    dirtyModules[uid][moduleName] = true
    dirtyUIDs[uid] = true

    -- 3. 确保防抖计时器在跑（已在跑则跳过）
    if not debounceRunning then
        debounceTimer = DEBOUNCE_SECONDS
        debounceRunning = true
    end
end

-- ======================== 防抖存盘 ========================

--- 判断模块是否为全局模块
---@param moduleName string
---@return boolean
local function isGlobalModule(moduleName)
    return globalModules[moduleName] ~= nil
end

--- 获取模块的注册信息（优先查全局，再查区服）
---@param moduleName string
---@return table|nil
function findModuleReg(moduleName)
    return globalModules[moduleName] or registeredModules[moduleName]
end

--- 将所有脏数据提交到云端（由防抖计时器触发）
local function flushDirtyData()
    -- 收集需要提交的数据：按 actualKey 分组
    -- keyData[actualKey][uid] = { [moduleName] = data, ... }
    -- actualKey = 全局模块用 reg.key, 区服模块用 prefix .. reg.key
    local keyData = {}
    local hasData = false

    -- 🔴 保存脏标记快照，用于提交失败时恢复（铁律 #1/#2: 传输层失败必须可重试）
    local savedDirtyModules = {}  -- { [uid] = { [moduleName] = true } }

    for uid in pairs(dirtyUIDs) do
        local dirty = dirtyModules[uid]
        if dirty and tables[uid] then
            -- 保存当前脏标记快照
            savedDirtyModules[uid] = {}
            for mn in pairs(dirty) do
                savedDirtyModules[uid][mn] = true
            end

            local prefix = getServerPrefix(uid)
            for moduleName in pairs(dirty) do
                local reg = findModuleReg(moduleName)
                if reg and tables[uid][moduleName] then
                    -- 🔒 防御性跳过 PDM 管理的 cloudKey（PDM 是权威写入者）
                    if isPdmManagedKey(reg.key) then
                        print(string.format(
                            "[SaveManager] SKIP pdm-managed module=%s key=%s uid=%s (PDM is authoritative writer)",
                            moduleName, reg.key, tostring(uid)))
                        savedDirtyModules[uid][moduleName] = nil  -- 不恢复此模块的脏标记
                    else
                        local actualKey
                        if isGlobalModule(moduleName) then
                            actualKey = reg.key       -- 全局模块：无前缀
                        else
                            actualKey = prefix .. reg.key  -- 区服模块：加前缀
                        end
                        if not keyData[actualKey] then keyData[actualKey] = {} end
                        if not keyData[actualKey][uid] then keyData[actualKey][uid] = {} end
                        keyData[actualKey][uid][moduleName] = tables[uid][moduleName]
                        hasData = true
                    end
                end
            end
        end
    end

    if not hasData then
        return
    end

    -- 构建 BatchCommit
    local flushLabel = "save_dirty_" .. tostring(os.time())
    local commit = serverCloud:BatchCommit(flushLabel)
    local totalScoreSets = 0
    local totalBytes = 0

    for actualKey, uidMap in pairs(keyData) do
        for uid, moduleDataMap in pairs(uidMap) do
            -- 按 actualKey 整合全部属于该 key 的模块数据再 ScoreSet
            local fullKeyData = {}
            local prefix = getServerPrefix(uid)

            -- 检查区服模块（使用深拷贝避免活引用竞态）
            for moduleName, reg in pairs(registeredModules) do
                local k = prefix .. reg.key
                if k == actualKey and tables[uid] and tables[uid][moduleName] then
                    fullKeyData[moduleName] = cjson.decode(cjson.encode(tables[uid][moduleName]))
                end
            end

            -- 检查全局模块（使用深拷贝避免活引用竞态）
            for moduleName, reg in pairs(globalModules) do
                if reg.key == actualKey and tables[uid] and tables[uid][moduleName] then
                    fullKeyData[moduleName] = cjson.decode(cjson.encode(tables[uid][moduleName]))
                end
            end

            -- 添加 _meta
            fullKeyData._meta = {
                lastSaveTime = os.time(),
            }

            commit:ScoreSet(uid, actualKey, fullKeyData)

            local keyJson = cjson.encode(fullKeyData)
            local keySize = #keyJson
            totalScoreSets = totalScoreSets + 1
            totalBytes = totalBytes + keySize

        end
    end

    -- 清理脏标记（提交前清理，避免回调期间的新脏数据被忽略）
    dirtyModules = {}
    dirtyUIDs = {}

    commit:Commit({
        ok = function() end,
        error = function(code, reason)
            print(string.format(
                "[SaveManager][ERROR] flush commit FAILED code=%s reason=%s scoreSets=%d",
                tostring(code), tostring(reason), totalScoreSets))
            -- 🔴 恢复脏标记（合并，不覆盖异步期间新增的脏数据）
            for uid, modules in pairs(savedDirtyModules) do
                if tables[uid] then  -- 玩家可能已断线清理
                    if not dirtyModules[uid] then dirtyModules[uid] = {} end
                    for mn in pairs(modules) do
                        dirtyModules[uid][mn] = true
                    end
                    dirtyUIDs[uid] = true
                end
            end
            -- 重新启动防抖计时器，触发下一次重试
            startDebouncIfDirty()
        end,
    })
end

-- ======================== 守卫链接口 ========================

--- 即时存盘指定玩家的脏数据（不清理内存，心跳/断开时使用）
--- @deprecated 仅用于非 PDM 管理的遗留模块。PDM 管理的模块通过 PDM.SavePlayer 存盘。
--- 如果所有区服模块已迁移至 PDM，此函数将无实际写入并可移除。
---@param uid number
function SaveManager.savePlayerNow(uid)
    if not dirtyUIDs[uid] or not dirtyModules[uid] then
        return
    end

    -- 🔴 保存脏标记快照，用于提交失败时恢复
    local savedModules = {}
    for mn in pairs(dirtyModules[uid]) do
        savedModules[mn] = true
    end

    local prefix = getServerPrefix(uid)
    local saveData = {}
    local keysProcessed = {}

    for moduleName in pairs(dirtyModules[uid]) do
        local reg = findModuleReg(moduleName)
        if reg and tables[uid] and tables[uid][moduleName] then
            -- 🔒 防御性跳过 PDM 管理的 cloudKey（PDM 是权威写入者，铁律 #11）
            if isPdmManagedKey(reg.key) then
                print(string.format(
                    "[SaveManager] savePlayerNow SKIP pdm-managed module=%s key=%s uid=%s (PDM is authoritative writer)",
                    moduleName, reg.key, tostring(uid)))
            else
                local actualKey
                if isGlobalModule(moduleName) then
                    actualKey = reg.key
                else
                    actualKey = prefix .. reg.key
                end

                if not keysProcessed[actualKey] then
                    keysProcessed[actualKey] = true
                    local fullKeyData = {}
                    for mn, r in pairs(registeredModules) do
                        local k = prefix .. r.key
                        if k == actualKey and tables[uid] and tables[uid][mn] then
                            fullKeyData[mn] = tables[uid][mn]
                        end
                    end
                    for mn, r in pairs(globalModules) do
                        if r.key == actualKey and tables[uid] and tables[uid][mn] then
                            fullKeyData[mn] = tables[uid][mn]
                        end
                    end
                    fullKeyData._meta = { lastSaveTime = os.time() }
                    saveData[actualKey] = fullKeyData
                end
            end
        end
    end

    dirtyModules[uid] = nil
    dirtyUIDs[uid] = nil

    if not next(saveData) then
        return
    end

    local commitLabel = "save_now_" .. tostring(uid)
    local commit = serverCloud:BatchCommit(commitLabel)
    local totalKeys = 0
    local totalBytes = 0
    for actualKey, fullKeyData in pairs(saveData) do
        commit:ScoreSet(uid, actualKey, fullKeyData)
        totalKeys = totalKeys + 1
    end

    commit:Commit({
        ok = function() end,
        error = function(code, reason)
            print(string.format(
                "[SaveManager][ERROR] savePlayerNow FAILED uid=%s code=%s reason=%s keys=%d",
                tostring(uid), tostring(code), tostring(reason), totalKeys))
            -- 🔴 恢复脏标记（合并，不覆盖异步期间新增的脏数据）
            if tables[uid] then  -- 玩家可能已断线清理
                if not dirtyModules[uid] then dirtyModules[uid] = {} end
                for mn in pairs(savedModules) do
                    dirtyModules[uid][mn] = true
                end
                dirtyUIDs[uid] = true
                startDebouncIfDirty()
            end
        end,
    })
end

--- 检查玩家数据是否加载完成
---@param uid number
---@return boolean
function SaveManager.isLoaded(uid)
    return loadState[uid] == "loaded"
end

--- 检查操作频率是否超限（2次/秒/玩家）
---@param uid number
---@return boolean true=允许, false=超限
function SaveManager.checkRateLimit(uid)
    local now = os.time()
    local limiter = rateLimiter[uid]

    if not limiter then
        rateLimiter[uid] = { count = 1, resetTime = now + 1 }
        return true
    end

    if now >= limiter.resetTime then
        -- 窗口已过期，重置
        limiter.count = 1
        limiter.resetTime = now + 1
        return true
    end

    limiter.count = limiter.count + 1
    if limiter.count > RATE_LIMIT_PER_SEC then
        print("[SaveManager] rate limit exceeded uid=" .. tostring(uid))
        return false
    end

    return true
end

-- ======================== 断线存档重试（内部） ========================

--- 提交断线存档数据（内部使用，支持重试）
---@param uid number
---@param saveData table { [key] = fullKeyData }  已快照的待存盘数据
---@param retryCount number 当前已重试次数
local function commitCleanupData(uid, saveData, retryCount)
    local commit = serverCloud:BatchCommit("cleanup_" .. tostring(uid) .. "_r" .. retryCount)

    for key, fullKeyData in pairs(saveData) do
        commit:ScoreSet(uid, key, fullKeyData)
    end

    commit:Commit({
        ok = function()
            print("[SaveManager] cleanup flush ok uid=" .. tostring(uid))
            cleanupRetries[uid] = nil
        end,
        error = function(code, reason)
            print("[SaveManager] cleanup flush error uid=" .. tostring(uid)
                .. " code=" .. tostring(code) .. " reason=" .. tostring(reason)
                .. " attempt=" .. (retryCount + 1) .. "/" .. (CLEANUP_RETRY_MAX + 1))

            if retryCount < CLEANUP_RETRY_MAX then
                cleanupRetries[uid] = {
                    data       = saveData,
                    retryCount = retryCount + 1,
                    timer      = 0,
                }
                print("[SaveManager] will retry cleanup for uid=" .. tostring(uid)
                    .. " in " .. CLEANUP_RETRY_DELAY .. "s")
            else
                print("[SaveManager] cleanup max retries exceeded uid=" .. tostring(uid)
                    .. " DATA MAY BE LOST")
                cleanupRetries[uid] = nil
            end
        end,
    })
end

-- ======================== 更新（由 Server.lua 每帧调用） ========================

--- 每帧更新，处理防抖计时器 + 断线存档重试
---@param dt number
function SaveManager.update(dt)
    -- 防抖存盘
    if debounceRunning then
        debounceTimer = debounceTimer - dt
        if debounceTimer <= 0 then
            debounceRunning = false
            flushDirtyData()
        end
    end

    -- 断线存档重试队列
    if next(cleanupRetries) then
        for uid, entry in pairs(cleanupRetries) do
            entry.timer = entry.timer + dt
            if entry.timer >= CLEANUP_RETRY_DELAY then
                print("[SaveManager] retrying cleanup flush uid=" .. tostring(uid)
                    .. " attempt=" .. entry.retryCount .. "/" .. CLEANUP_RETRY_MAX)
                local data = entry.data
                local retryCount = entry.retryCount
                cleanupRetries[uid] = nil  -- 先移除，commitCleanupData 失败时会重新加入
                commitCleanupData(uid, data, retryCount)
            end
        end
    end

    -- 读档超时兜底：serverCloud:Get 无回调时必须失败返回，避免客户端永久 loading
    if next(loadTimeouts) then
        local timedOut = {}
        for uid, entry in pairs(loadTimeouts) do
            entry.timer = (entry.timer or 0) + dt
            if entry.timer >= LOAD_TIMEOUT_SECONDS then
                timedOut[#timedOut + 1] = uid
            end
        end
        for _, uid in ipairs(timedOut) do
            local entry = loadTimeouts[uid]
            if entry then
                local pending = {}
                for key in pairs(entry.pendingKeys or {}) do
                    pending[#pending + 1] = tostring(key)
                end
                table.sort(pending)
                print(string.format(
                    "[SaveManager][LOAD-TIMEOUT] uid=%s kind=%s sv=%s pending=[%s] elapsed=%.1fs",
                    tostring(uid), tostring(entry.kind), tostring(entry.sv), table.concat(pending, ","), entry.timer or 0))
                emitLoadDiag(uid, string.format("%s TIMEOUT sv=%s pending=[%s] elapsed=%.1fs",
                    tostring(entry.kind), tostring(entry.sv), table.concat(pending, ","), entry.timer or 0))
                if sessionVersions[uid] == entry.sv then
                    loadState[uid] = nil
                    loadTimeouts[uid] = nil
                    if entry.callback then
                        if entry.kind == "global" then
                            entry.callback(false, nil)
                        else
                            entry.callback(false)
                        end
                    end
                else
                    loadTimeouts[uid] = nil
                end
            end
        end
    end
end

-- ======================== 会话管理 ========================

--- 玩家断开时清理
--- 先 flush 脏数据，再清理内存
---@param uid number
function SaveManager.cleanup(uid)
    -- flush 该玩家的脏数据
    if dirtyUIDs[uid] and dirtyModules[uid] then
        -- 快照待存盘数据（按 actualKey 分组），之后内存会被清理
        local saveData = {}    -- { [actualKey] = fullKeyData }
        local keysProcessed = {}
        local prefix = getServerPrefix(uid)

        for moduleName in pairs(dirtyModules[uid]) do
            local reg = findModuleReg(moduleName)
            if reg and tables[uid] and tables[uid][moduleName] then
                -- 🔒 防御性跳过 PDM 管理的 cloudKey（PDM 是权威写入者）
                if isPdmManagedKey(reg.key) then
                    print(string.format(
                        "[SaveManager] cleanup SKIP pdm-managed module=%s key=%s uid=%s (PDM is authoritative writer)",
                        moduleName, reg.key, tostring(uid)))
                else
                    local actualKey
                    if isGlobalModule(moduleName) then
                        actualKey = reg.key
                    else
                        actualKey = prefix .. reg.key
                    end

                    if not keysProcessed[actualKey] then
                        keysProcessed[actualKey] = true
                        local fullKeyData = {}

                        -- 收集该 actualKey 下的区服模块
                        for mn, r in pairs(registeredModules) do
                            local k = prefix .. r.key
                            if k == actualKey and tables[uid] and tables[uid][mn] then
                                fullKeyData[mn] = cjson.decode(cjson.encode(tables[uid][mn]))
                            end
                        end

                        -- 收集该 actualKey 下的全局模块
                        for mn, r in pairs(globalModules) do
                            if r.key == actualKey and tables[uid] and tables[uid][mn] then
                                fullKeyData[mn] = cjson.decode(cjson.encode(tables[uid][mn]))
                            end
                        end

                        fullKeyData._meta = { lastSaveTime = os.time() }
                        saveData[actualKey] = fullKeyData
                    end
                end
            end
        end

        if next(saveData) then
            commitCleanupData(uid, saveData, 0)
        end

        dirtyModules[uid] = nil
        dirtyUIDs[uid] = nil
    end

    -- 调用各模块 onCleanup（区服模块 + 全局模块）
    for moduleName, reg in pairs(registeredModules) do
        if reg.onCleanup then
            local ok, err = pcall(reg.onCleanup, uid)
            if not ok then
                print("[SaveManager] onCleanup error for " .. moduleName
                    .. ": " .. tostring(err))
            end
        end
    end
    for moduleName, reg in pairs(globalModules) do
        if reg.onCleanup then
            local ok, err = pcall(reg.onCleanup, uid)
            if not ok then
                print("[SaveManager] onCleanup error for global " .. moduleName
                    .. ": " .. tostring(err))
            end
        end
    end

    -- 清理内存
    tables[uid] = nil
    loadState[uid] = nil
    loadTimeouts[uid] = nil
    rateLimiter[uid] = nil
    sessionVersions[uid] = nil
    serverId_[uid] = nil
    ServerDispatcher.clearCache(uid)

    print("[SaveManager] cleanup complete uid=" .. tostring(uid))
end

--- 服务器关闭时 flush 所有玩家的脏数据
--- 🔴 修复: 不再在 shutdown 中清除内存——进程即将退出，OS 会回收内存。
--- 与 PDM.Shutdown 同理: async flush 后立即清空 tables/dirtyModules 等，
--- 导致 flush 的 error 回调无法恢复脏标记，未持久化数据在重启后丢失。
function SaveManager.shutdown()
    print("[SaveManager] shutdown: flushing all dirty data...")

    -- 统计待刷数据量，用于日志
    local dirtyCount = 0
    for uid in pairs(dirtyUIDs) do dirtyCount = dirtyCount + 1 end
    local retryCount = 0
    for uid in pairs(cleanupRetries) do retryCount = retryCount + 1 end
    print(string.format("[SaveManager] shutdown: dirtyUIDs=%d cleanupRetries=%d", dirtyCount, retryCount))

    flushDirtyData()

    -- 尝试提交所有待重试的断线存档
    for uid, entry in pairs(cleanupRetries) do
        print("[SaveManager] shutdown: flushing pending cleanup uid=" .. tostring(uid))
        local commit = serverCloud:BatchCommit("shutdown_cleanup_" .. tostring(uid))
        local keyCount = 0
        for key, fullKeyData in pairs(entry.data) do
            commit:ScoreSet(uid, key, fullKeyData)
            keyCount = keyCount + 1
        end
        local capturedUid = uid
        local capturedKeyCount = keyCount
        commit:Commit({
            ok = function()
                print(string.format(
                    "[SaveManager] shutdown cleanup OK uid=%s keys=%d",
                    tostring(capturedUid), capturedKeyCount))
            end,
            error = function(code, reason)
                -- 🔴 shutdown 阶段无法重试（进程即将退出），只能记录 ERROR 供运维排查
                print(string.format(
                    "[SaveManager][ERROR] shutdown cleanup FAILED uid=%s code=%s reason=%s keys=%d — DATA MAY BE LOST",
                    tostring(capturedUid), tostring(code), tostring(reason), capturedKeyCount))
            end,
        })
    end

    -- 🔴 不清除内存！
    -- 进程即将退出，OS 会回收所有内存。保留 tables/cleanupRetries 等数据
    -- 使得 flushDirtyData 的 error 回调仍可正常执行恢复逻辑。

    print("[SaveManager] shutdown complete (memory retained for async callbacks)")
end

--- 获取加载状态（调试用）
---@param uid number
---@return string|nil
function SaveManager.getLoadState(uid)
    return loadState[uid]
end

return SaveManager
