-- ============================================================================
-- PlayerDataManager.lua — 统一数据管理器（PDM，全项目唯一）
-- 路径: scripts/server/character/PlayerDataManager.lua
--
-- 职责:
--   1. 已迁移模块的唯一 serverCloud 读写入口
--   2. 从 CharacterSchema 动态构建字段注册表，零硬编码
--   3. 管理玩家数据生命周期：加载 → 读写 → 脏标记 → 定时存盘 → 清理
--   4. 通过 ServerDispatcher 同步数据到客户端
--
-- 与 SaveManager 的关系:
--   迁移期间两者共存，每个模块由其中一个独占管理。
--   已迁移到 Schema 的模块走 PDM，未迁移的仍走 SaveManager。
--   迁移完成后 SaveManager 废弃，PDM 成为唯一数据管理器。
--
-- 新增子系统接入方式:
--   1. 编写 XxxSchema.lua，定义 Fields（pdmKey + type + scope + persist + getDefault）
--   2. 在 CharacterSchema.lua 底部 require + RegisterSubsystemFields
--   3. PDM 自动加载/存盘/同步该模块，无需修改本文件
--   4. 业务 Service 通过 PDM.GetModule/MarkDirty 读写
--
-- serverCloud 数据格式（与 SaveManager 完全一致）:
--   ScoreSet(uid, actualKey, { [fieldKey] = moduleData, _meta = { lastSaveTime } })
--   actualKey = prefix .. cloudKey  （prefix = "s{serverId}_" 或 ""）
-- ============================================================================

local PlayerDataManager = {}

local CharacterSchema  = require("shared.schemas.CharacterSchema")
local ServerListConfig = require("shared.ServerListConfig")
local QuotaConsts      = require("shared.quota.QuotaConsts")

local cjson = cjson  ---@diagnostic disable-line: undefined-global

-- ============================================================================
-- 配置
-- ============================================================================

local DEBOUNCE_SECONDS    = 0.5   -- 脏数据防抖周期（秒）— 缩短以减少跨服回档风险
local CLEANUP_RETRY_MAX   = 10    -- 断线存档最大重试次数（从 3 提升到 10，防止短暂网络抖动导致永久丢档）
local CLEANUP_RETRY_DELAY = 2     -- 断线存档首次重试间隔（秒），后续指数退避（见 commitCleanupData error handler）

--- 告警钩子：当存档重试耗尽、数据面临丢失风险时触发
--- 外部通过 PlayerDataManager.SetDataLossAlertHook(fn) 注册
--- @type fun(uid: number, lostKeys: string[], retryCount: number)|nil
local onDataLossAlert_ = nil

-- ============================================================================
-- 前向声明（解决 local function 前向引用）
-- ============================================================================
local flushDirtyData  -- 定义在第 ~860 行，FlushImmediate 需要前向引用

-- ============================================================================
-- 从 CharacterSchema 动态构建字段注册表
-- ============================================================================

--- fieldKey -> def 映射（Setup 时刷新）
local fieldDefs_ = {}

--- 刷新字段注册表（Schema 注册完毕后调用）
local function refreshFieldDefs()
    fieldDefs_ = {}
    for fieldKey, def in pairs(CharacterSchema.Fields) do
        fieldDefs_[fieldKey] = def
    end
    local count = 0
    for _ in pairs(fieldDefs_) do count = count + 1 end
    print("[PDM] refreshFieldDefs: " .. count .. " fields registered")
end

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 玩家数据
--- playerData_[uid] = {
---   modules        = { [fieldKey] = moduleData },
---   serverId       = number | nil,
---   dirty          = { [fieldKey] = true },
---   sessionVersion = number,
--- }
local playerData_ = {}

--- 全局脏 UID 集合
local dirtyUIDs_ = {}

--- 防抖计时器
local debounceTimer_   = 0
local debounceRunning_ = false

--- 断线存档重试队列
--- cleanupRetries_[uid] = { data = {}, retryCount = N, timer = T }
local cleanupRetries_ = {}

--- 外部依赖引用（由 Setup 注入）
local serverDispatcher_ = nil

-- ============================================================================
-- 写入串行化 + save_seq 递增序列号（防丢档核心机制）
-- ============================================================================

--- 每 (uid, actualKey) 的递增序列号，写入 _meta.save_seq
--- saveSeq_[uid][actualKey] = number
local saveSeq_ = {}

--- 当前有 in-flight 提交的 key 集合（防止并发写入导致旧数据覆盖新数据）
--- pendingKeys_[uid][actualKey] = timestamp (os.clock 时刻)
local pendingKeys_ = {}

--- pending 超时阈值（秒）：超过此时间未收到回调则强制释放锁并重发
local PENDING_TIMEOUT_SECONDS = 60

--- 读档超时阈值（秒）：serverCloud:Get / quota 读档无回调时失败返回，避免客户端永久 loading
local LOAD_TIMEOUT_SECONDS = 8.0

--- 等待重发的 key 集合（pending 期间又有新脏数据，需要 pending 完成后重发）
--- pendingReflush_[uid][actualKey] = true
local pendingReflush_ = {}

--- 读档超时追踪 loadTimeouts_[uid] = { sv, timer, pendingKeys={ [key]=true }, callback }
local loadTimeouts_ = {}

--- 读档诊断钩子：由 Server.lua 注入，把 PDM 读档过程转发到客户端反馈日志
--- @type fun(uid: number, message: string)|nil
local loadDiagHook_ = nil

local function emitLoadDiag(uid, message)
    print("[PDM][LOAD-DIAG] uid=" .. tostring(uid) .. " " .. tostring(message))
    if loadDiagHook_ then
        local ok, err = pcall(loadDiagHook_, uid, "PDM " .. tostring(message))
        if not ok then
            print("[PDM][LOAD-DIAG] hook error: " .. tostring(err))
        end
    end
end

--- 获取并递增 save_seq
---@param uid number
---@param actualKey string
---@return number newSeq
local function nextSaveSeq(uid, actualKey)
    if not saveSeq_[uid] then saveSeq_[uid] = {} end
    local current = saveSeq_[uid][actualKey] or 0
    local next = current + 1
    saveSeq_[uid][actualKey] = next
    return next
end

--- 标记 key 为 pending（有 in-flight 提交）
---@param uid number
---@param actualKey string
local function markPending(uid, actualKey)
    if not pendingKeys_[uid] then pendingKeys_[uid] = {} end
    pendingKeys_[uid][actualKey] = os.clock()
end

--- 清除 pending 标记
---@param uid number
---@param actualKey string
local function clearPending(uid, actualKey)
    if pendingKeys_[uid] then
        pendingKeys_[uid][actualKey] = nil
    end
end

--- 检查 key 是否有 pending 提交
---@param uid number
---@param actualKey string
---@return boolean
local function isPending(uid, actualKey)
    return pendingKeys_[uid] and pendingKeys_[uid][actualKey] ~= nil
end

--- 标记 key 需要在 pending 完成后重发
---@param uid number
---@param actualKey string
local function markReflush(uid, actualKey)
    if not pendingReflush_[uid] then pendingReflush_[uid] = {} end
    pendingReflush_[uid][actualKey] = true
end

--- 取出并清除 reflush 标记
---@param uid number
---@param actualKey string
---@return boolean needReflush
local function popReflush(uid, actualKey)
    if pendingReflush_[uid] and pendingReflush_[uid][actualKey] then
        pendingReflush_[uid][actualKey] = nil
        return true
    end
    return false
end

--- 清除玩家的全部串行化状态（RemovePlayer 时调用）
---@param uid number
local function clearSerializationState(uid)
    saveSeq_[uid] = nil
    pendingKeys_[uid] = nil
    pendingReflush_[uid] = nil
end

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化 PDM（Server.Start 时调用一次）
---@param opts table { serverDispatcher: table }
function PlayerDataManager.Setup(opts)
    serverDispatcher_ = opts.serverDispatcher
    loadDiagHook_ = opts.loadDiagHook
    refreshFieldDefs()
    print("[PDM] Setup complete")
end

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 获取区服 key 前缀
---@param uid number
---@return string
local function getServerPrefix(uid)
    local pd = playerData_[uid]
    if pd and pd.serverId then
        return ServerListConfig.getKeyPrefix(pd.serverId)
    end
    return ""
end

--- 获取字段的 actualKey（含区服前缀）
---@param uid number
---@param fieldKey string
---@return string|nil
local function getActualKey(uid, fieldKey)
    local def = fieldDefs_[fieldKey]
    if not def or not def.persist or type(def.persist) ~= "table" then
        return nil
    end
    local cloudKey = def.persist.cloudKey
    if not cloudKey then
        -- quota 等 via!="cloud" 的字段没有 cloudKey，不走 cloud 存储
        return nil
    end
    if def.scope == "global" then
        return cloudKey
    else
        return getServerPrefix(uid) .. cloudKey
    end
end

--- 合并模块数据：默认值为底，云端数据覆盖，执行 onLoad
---@param fieldKey string
---@param cloudData table|nil
---@return table
local function mergeModuleData(fieldKey, cloudData)
    local def = fieldDefs_[fieldKey]
    if not def then return cloudData or {} end

    local defaultData = def.getDefault and def.getDefault() or {}

    -- scalar/string 类型不做 table merge，直接取值
    if type(defaultData) ~= "table" then
        if cloudData ~= nil then return cloudData end
        return defaultData
    end

    local merged = {}

    for k, v in pairs(defaultData) do
        merged[k] = v
    end
    if type(cloudData) == "table" then
        for k, v in pairs(cloudData) do
            merged[k] = v
        end
    end

    if def.onLoad then
        local ok, err = pcall(def.onLoad, merged)
        if not ok then
            print("[PDM] onLoad error for " .. fieldKey .. ": " .. tostring(err))
        end
    end
    if def.onServerLoad then
        local ok, err = pcall(def.onServerLoad, merged)
        if not ok then
            print("[PDM] onServerLoad error for " .. fieldKey .. ": " .. tostring(err))
        end
    end
    return merged
end

--- 确保玩家数据容器已初始化
---@param uid number
---@return table playerData
local function ensurePlayerData(uid)
    if not playerData_[uid] then
        playerData_[uid] = {
            modules        = {},
            serverId       = nil,
            dirty          = {},
            sessionVersion = 0,
        }
    end
    return playerData_[uid]
end

--- 启动防抖计时器（如果不在跑）
local function startDebounceIfDirty()
    if next(dirtyUIDs_) and not debounceRunning_ then
        debounceTimer_ = DEBOUNCE_SECONDS
        debounceRunning_ = true
    end
end

-- ============================================================================
-- 区服 ID 管理
-- ============================================================================

--- 设置玩家区服 ID（选服后调用）
---@param uid number
---@param serverId number
function PlayerDataManager.SetServerId(uid, serverId)
    local pd = ensurePlayerData(uid)
    pd.serverId = serverId
    print("[PDM] SetServerId uid=" .. tostring(uid) .. " serverId=" .. tostring(serverId))
end

--- 获取玩家区服 ID
---@param uid number
---@return number|nil
function PlayerDataManager.GetServerId(uid)
    local pd = playerData_[uid]
    return pd and pd.serverId
end

-- ============================================================================
-- 玩家生命周期：加载
-- ============================================================================

--- 加载全局层数据（选服之前调用，仅加载 scope="global" 的字段）
---@param uid number
---@param callback function(success: boolean)
function PlayerDataManager.LoadGlobalProfile(uid, callback)
    local pd = ensurePlayerData(uid)
    pd.sessionVersion = pd.sessionVersion + 1
    local sv = pd.sessionVersion

    -- 收集全局字段，按 cloudKey 分组
    local globalFields = CharacterSchema.GetFieldsByScope("global")
    local keyFieldMap = {}  -- { [cloudKey] = { fieldKey1, ... } }
    for fk, def in pairs(globalFields) do
        if type(def.persist) == "table" and def.persist.cloudKey then
            local ck = def.persist.cloudKey
            if not keyFieldMap[ck] then keyFieldMap[ck] = {} end
            keyFieldMap[ck][#keyFieldMap[ck] + 1] = fk
        end
    end

    local keyList = {}
    for k in pairs(keyFieldMap) do keyList[#keyList + 1] = k end

    if #keyList == 0 then
        print("[PDM] LoadGlobalProfile: no global fields, uid=" .. tostring(uid))
        if callback then callback(true) end
        return
    end

    local pendingKeys = #keyList
    local hasError = false
    local pendingKeyMap = {}
    for _, cloudKey in ipairs(keyList) do
        pendingKeyMap[cloudKey] = true
    end
    loadTimeouts_[uid] = {
        kind = "global",
        sv = sv,
        timer = 0,
        pendingKeys = pendingKeyMap,
        callback = callback,
    }

    for _, cloudKey in ipairs(keyList) do
        emitLoadDiag(uid, "global START key=" .. tostring(cloudKey) .. " sv=" .. tostring(sv)
            .. " fields=" .. table.concat(keyFieldMap[cloudKey] or {}, ","))
        serverCloud:Get(uid, cloudKey, {
            ok = function(scores)
                if not playerData_[uid] or playerData_[uid].sessionVersion ~= sv then return end
                if not loadTimeouts_[uid] or loadTimeouts_[uid].sv ~= sv then return end
                loadTimeouts_[uid].pendingKeys[cloudKey] = nil

                local rawScores = scores or {}
                local cloudData = rawScores[cloudKey]
                local cloudSize = 0
                local sizeOk, sizeJson = pcall(cjson.encode, cloudData or {})
                if sizeOk and sizeJson then cloudSize = #sizeJson end
                emitLoadDiag(uid, "global OK key=" .. tostring(cloudKey) .. " size=" .. tostring(cloudSize)
                    .. " fields=" .. table.concat(keyFieldMap[cloudKey] or {}, ","))
                if type(cloudData) ~= "table" then cloudData = {} end

                for _, fieldKey in ipairs(keyFieldMap[cloudKey]) do
                    pd.modules[fieldKey] = mergeModuleData(fieldKey, cloudData[fieldKey])
                end

                pendingKeys = pendingKeys - 1
                if pendingKeys <= 0 and not hasError then
                    loadTimeouts_[uid] = nil
                    print("[PDM] LoadGlobalProfile ok uid=" .. tostring(uid))
                    if callback then callback(true) end
                end
            end,
            error = function(code, reason)
                if not playerData_[uid] or playerData_[uid].sessionVersion ~= sv then return end
                if not loadTimeouts_[uid] or loadTimeouts_[uid].sv ~= sv then return end
                print("[PDM] LoadGlobalProfile error uid=" .. tostring(uid)
                    .. " key=" .. cloudKey .. " code=" .. tostring(code)
                    .. " reason=" .. tostring(reason))
                emitLoadDiag(uid, "global ERROR key=" .. tostring(cloudKey)
                    .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
                if not hasError then
                    hasError = true
                    loadTimeouts_[uid] = nil
                    if callback then callback(false) end
                end
            end,
        })
    end
end

--- 加载所有 quota 字段到 pd.modules.quotas 缓存
---@param uid number
---@param sv number  sessionVersion（防止异步回调过期）
---@param callback function(ok: boolean)
local function loadQuotaFields(uid, sv, callback)
    local pd = playerData_[uid]
    if not pd then
        if callback then callback(false) end
        return
    end

    -- quota 只用于签到限额等二级保险，不应阻塞登录主流程。
    -- 某些单用户 quota:Get 可能无回调，曾导致 Phase2 永久卡住。
    -- 登录时使用默认缓存即可；真正消耗时 UseQuota 会通过 quota:Add 写入服务端，
    -- 业务状态仍由 signin.dailyClaimed / weeklyClaimed 等持久模块兜底防重领。
    pd.modules.quotas = pd.modules.quotas or {}
    local allKeys = QuotaConsts.GetAllKeys()
    for _, keyDef in ipairs(allKeys) do
        pd.modules.quotas[keyDef.key] = pd.modules.quotas[keyDef.key] or {
            value = 0,
            limit = keyDef.limit,
        }
    end
    emitLoadDiag(uid, "quota DEFAULT keys=" .. tostring(#allKeys) .. " sv=" .. tostring(sv))
    print("[PDM] loadQuotaFields default ok uid=" .. tostring(uid) .. " keys=" .. tostring(#allKeys))
    if callback then callback(true) end
end

--- 加载玩家区服数据（选服后调用）
--- 必须先调用 SetServerId
---@param uid number
---@param callback function(success: boolean)
function PlayerDataManager.LoadPlayer(uid, callback)
    local TAG = "[PDM][DIAG-RESET]"
    local lpT0 = os.clock()
    print(string.format("%s LoadPlayer START uid=%s clock=%.4f", TAG, tostring(uid), lpT0))

    local pd = playerData_[uid]
    if not pd then
        print("[PDM] LoadPlayer: no playerData for uid=" .. tostring(uid))
        print(string.format("%s LoadPlayer ABORT — no playerData uid=%s", TAG, tostring(uid)))
        if callback then callback(false) end
        return
    end

    pd.sessionVersion = pd.sessionVersion + 1
    local sv = pd.sessionVersion
    print(string.format("%s LoadPlayer sessionVersion=%d uid=%s", TAG, sv, tostring(uid)))

    local prefix = getServerPrefix(uid)
    if prefix == "" then
        print("[PDM] WARNING: LoadPlayer called without SetServerId! uid=" .. tostring(uid))
    end

    -- 收集区服字段，按 actualKey 分组
    local serverFields = CharacterSchema.GetFieldsByScope("server")
    local keyFieldMap = {}  -- { [actualKey] = { fieldKey1, ... } }
    for fk, def in pairs(serverFields) do
        if type(def.persist) == "table" and def.persist.cloudKey then
            local actualKey = prefix .. def.persist.cloudKey
            if not keyFieldMap[actualKey] then keyFieldMap[actualKey] = {} end
            keyFieldMap[actualKey][#keyFieldMap[actualKey] + 1] = fk
        end
    end

    local keyList = {}
    for k in pairs(keyFieldMap) do keyList[#keyList + 1] = k end

    if #keyList == 0 then
        print("[PDM] LoadPlayer: no cloud server fields, loading quota only uid=" .. tostring(uid))
        loadQuotaFields(uid, sv, function(quotaOk)
            if not playerData_[uid] or pd.sessionVersion ~= sv then return end
            pd.modules._meta = {
                lastSaveTime = os.time(),
                loadTime     = os.time(),
            }
            if callback then callback(true) end
        end)
        return
    end

    -- 清除旧区服模块数据（换服时需要）
    for fk in pairs(serverFields) do
        pd.modules[fk] = nil
    end

    table.sort(keyList)

    local pendingKeyMap = {}
    for _, actualKey in ipairs(keyList) do
        pendingKeyMap[actualKey] = true
    end
    loadTimeouts_[uid] = {
        kind = "player",
        sv = sv,
        timer = 0,
        pendingKeys = pendingKeyMap,
        callback = callback,
    }

    -- 使用单次 BatchGet 读取全部区服模块，避免大量并发 serverCloud:Get 中某个 key 回调丢失
    -- 导致 Phase2 永久卡 loading。读不到的 key 仅在内存中使用默认值，不 MarkDirty、不写回云端，防止覆盖真实存档。
    local batch = serverCloud:BatchGet(uid)
    for _, actualKey in ipairs(keyList) do
        emitLoadDiag(uid, "player START key=" .. tostring(actualKey) .. " sv=" .. tostring(sv)
            .. " fields=" .. table.concat(keyFieldMap[actualKey] or {}, ","))
        batch:Key(actualKey)
    end

    batch:Fetch({
        ok = function(scores)
            if not playerData_[uid] or pd.sessionVersion ~= sv then return end
            if not loadTimeouts_[uid] or loadTimeouts_[uid].sv ~= sv then return end

            local rawScores = scores or {}
            for _, actualKey in ipairs(keyList) do
                loadTimeouts_[uid].pendingKeys[actualKey] = nil

                local cloudData = rawScores[actualKey]
                local cloudSize = 0
                local sizeOk, sizeJson = pcall(cjson.encode, cloudData or {})
                if sizeOk and sizeJson then cloudSize = #sizeJson end
                emitLoadDiag(uid, "player OK key=" .. tostring(actualKey) .. " size=" .. tostring(cloudSize)
                    .. " fields=" .. table.concat(keyFieldMap[actualKey] or {}, ","))
                if type(cloudData) ~= "table" then cloudData = {} end

                for _, fieldKey in ipairs(keyFieldMap[actualKey]) do
                    pd.modules[fieldKey] = mergeModuleData(fieldKey, cloudData[fieldKey])
                end

                -- 从云端读取 save_seq，初始化本地计数器（后续写入从此值递增）。
                -- 如果 BatchGet 缺失该 key，cloudData 会是空表，只使用默认值，不推进 save_seq、不写回云端。
                local cloudMeta = cloudData["_meta"]
                if type(cloudMeta) == "table" and cloudMeta.save_seq then
                    if not saveSeq_[uid] then saveSeq_[uid] = {} end
                    local loaded = tonumber(cloudMeta.save_seq) or 0
                    local existing = saveSeq_[uid][actualKey] or 0
                    if loaded > existing then
                        saveSeq_[uid][actualKey] = loaded
                        print(string.format("[PDM] LoadPlayer restore save_seq uid=%s key=%s seq=%d",
                            tostring(uid), actualKey, loaded))
                    end
                end
            end

            -- cloud 字段全部加载完毕，追加 quota 加载
            loadTimeouts_[uid].pendingKeys["__quota__"] = true
            emitLoadDiag(uid, "quota START sv=" .. tostring(sv))
            loadQuotaFields(uid, sv, function(quotaOk)
                if not playerData_[uid] or pd.sessionVersion ~= sv then return end
                if not loadTimeouts_[uid] or loadTimeouts_[uid].sv ~= sv then return end
                emitLoadDiag(uid, "quota DONE ok=" .. tostring(quotaOk) .. " sv=" .. tostring(sv))
                loadTimeouts_[uid] = nil
                -- quota 失败不阻塞（降级空缓存已在 loadQuotaFields 内处理）
                pd.modules._meta = {
                    lastSaveTime = os.time(),
                    loadTime     = os.time(),
                }
                -- 诊断：加载完成时记录关键模块状态
                local heroMod = pd.modules["heroes"]
                local rosterCount = 0
                if heroMod and type(heroMod) == "table" and heroMod.roster then
                    for _ in pairs(heroMod.roster) do rosterCount = rosterCount + 1 end
                end
                local playerMod = pd.modules["player"]
                print(string.format(
                    "%s LoadPlayer DONE uid=%s rosterCount=%d playerLevel=%s elapsed=%.4fs",
                    TAG, tostring(uid), rosterCount,
                    tostring(playerMod and playerMod.level),
                    os.clock() - lpT0))
                print("[PDM] LoadPlayer ok uid=" .. tostring(uid))
                if callback then callback(true) end
            end)
        end,
        error = function(code, reason)
            if not playerData_[uid] or pd.sessionVersion ~= sv then return end
            if not loadTimeouts_[uid] or loadTimeouts_[uid].sv ~= sv then return end
            print("[PDM] LoadPlayer BatchGet error uid=" .. tostring(uid)
                .. " code=" .. tostring(code)
                .. " reason=" .. tostring(reason))
            emitLoadDiag(uid, "player ERROR batch keys=" .. table.concat(keyList, ",")
                .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
            loadTimeouts_[uid] = nil
            if callback then callback(false) end
        end,
    })
end

-- ============================================================================
-- 数据读写（核心 API）
-- ============================================================================

--- 获取模块数据引用（直接读写模块内部字段）
--- Service 可通过 local t = PDM.GetModule(uid, "player"); t.level = t.level + 1
---@param uid number
---@param fieldKey string  CharacterSchema 中的字段名（= 模块名）
---@return table|nil
function PlayerDataManager.GetModule(uid, fieldKey)
    local pd = playerData_[uid]
    if not pd then return nil end
    return pd.modules[fieldKey]
end

--- 替换模块数据（整体覆盖 + 自动 MarkDirty）
---@param uid number
---@param fieldKey string
---@param data table
function PlayerDataManager.SetModule(uid, fieldKey, data)
    local pd = playerData_[uid]
    if not pd then
        print("[PDM] SetModule: no playerData for uid=" .. tostring(uid))
        return
    end
    pd.modules[fieldKey] = data
    PlayerDataManager.MarkDirty(uid, fieldKey)
end

--- 标记模块数据已变更
--- 双职责:
---   1. 即时推送到客户端（通过 ServerDispatcher.pushModule）
---   2. 标记脏等待定时存盘
---@param uid number
---@param fieldKey string
function PlayerDataManager.MarkDirty(uid, fieldKey)
    local pd = playerData_[uid]
    if not pd or not pd.modules[fieldKey] then
        print("[PDM] MarkDirty: no data for uid=" .. tostring(uid) .. " field=" .. fieldKey)
        print("[PDM][DIAG-RESET] MarkDirty FAILED — pd=" .. tostring(pd ~= nil)
            .. " modules[" .. tostring(fieldKey) .. "]=" .. tostring(pd and pd.modules[fieldKey] ~= nil)
            .. " caller=" .. tostring(debug.traceback(nil, 2):match("[^\n]*\n[^\n]*")))
        return
    end

    -- 诊断日志：追踪 reset 链路中的每次 MarkDirty
    local modData = pd.modules[fieldKey]
    local dataPreview = ""
    if fieldKey == "heroes" and type(modData) == "table" then
        local rc = 0
        if modData.roster then for _ in pairs(modData.roster) do rc = rc + 1 end end
        dataPreview = string.format(" rosterCount=%d deployed=%s", rc, tostring(modData.deployed))
    elseif fieldKey == "player" and type(modData) == "table" then
        dataPreview = string.format(" level=%s stage=%s", tostring(modData.level), tostring(modData.stage))
    end
    print(string.format("[PDM][DIAG-RESET] MarkDirty uid=%s field=%s%s clock=%.4f",
        tostring(uid), fieldKey, dataPreview, os.clock()))

    -- 1. 即时推送到客户端
    if serverDispatcher_ then
        serverDispatcher_.pushModule(uid, fieldKey, pd.modules[fieldKey])
    end

    -- 2. 脏标记 + 启动防抖
    pd.dirty[fieldKey] = true
    dirtyUIDs_[uid] = true
    startDebounceIfDirty()
end

--- 立即 flush 指定玩家的脏数据（绕过 debounce 计时器）
--- 用于高价值操作后立即持久化（如抽卡、充值、重要道具获取等），
--- 缩小进程崩溃时的数据丢失窗口（从 0.5s debounce 降为 0）。
--- 注意：仍然遵守写入串行化——如果目标 key 有 in-flight commit，会标记 reflush 等待回调后重发。
---@param uid number
function PlayerDataManager.FlushImmediate(uid)
    local pd = playerData_[uid]
    if not pd or not next(pd.dirty) then
        return
    end
    -- 确保该 uid 在 dirtyUIDs 中（flushDirtyData 遍历它）
    dirtyUIDs_[uid] = true
    -- 直接触发 flush，不等 debounce
    flushDirtyData()
end

--- 注册数据丢失风险告警钩子
--- 当 commitCleanupData 重试次数耗尽、数据面临永久丢失时调用此回调。
--- 用于接入外部告警系统（如推送到 Lark/Slack/日志平台）。
---@param fn fun(uid: number, lostKeys: string[], retryCount: number)
function PlayerDataManager.SetDataLossAlertHook(fn)
    onDataLossAlert_ = fn
end

--- 获取所有模块数据（用于全量推送）
---@param uid number
---@return table|nil  { [fieldKey] = moduleData, ... }
function PlayerDataManager.GetAllModules(uid)
    local pd = playerData_[uid]
    return pd and pd.modules
end

--- 检查玩家数据是否已加载
---@param uid number
---@return boolean
function PlayerDataManager.IsLoaded(uid)
    local pd = playerData_[uid]
    return pd ~= nil and next(pd.modules) ~= nil
end

-- ============================================================================
-- 全量推送（进入游戏时调用）
-- ============================================================================

--- 推送 PDM 管理的所有模块数据到客户端
---@param uid number
function PlayerDataManager.PushFullState(uid)
    local pd = playerData_[uid]
    if not pd or not serverDispatcher_ then return end
    serverDispatcher_.pushFullState(uid, pd.modules)
end

-- ============================================================================
-- 存盘
-- ============================================================================

--- 构建指定 actualKey 下的完整数据（包含该 key 下的所有模块，不仅是脏的）
--- serverCloud 需要整 key 覆写，不能只写部分模块
--- 🔴 写入 _meta.save_seq 递增序列号，防止旧提交覆盖新提交
---@param uid number
---@param targetActualKey string
---@param snapshot boolean|nil  true 时深拷贝（断线存档用）
---@return table fullKeyData
local function buildFullKeyData(uid, targetActualKey, snapshot)
    local pd = playerData_[uid]
    local fullKeyData = {}

    for fk, def in pairs(fieldDefs_) do
        local fkActualKey = getActualKey(uid, fk)
        if fkActualKey == targetActualKey and pd.modules[fk] then
            local moduleData
            if snapshot then
                moduleData = cjson.decode(cjson.encode(pd.modules[fk]))
            else
                moduleData = pd.modules[fk]
            end
            -- onSave 钩子：存储前数据瘦身（如装备去除可派生字段）
            if def.onSave then
                local lean = def.onSave(moduleData)
                if lean then moduleData = lean end
            end
            fullKeyData[fk] = moduleData
        end
    end

    -- 🔴 save_seq: 递增序列号，每次构建 +1，用于检测乱序写入
    local seq = nextSaveSeq(uid, targetActualKey)
    fullKeyData._meta = {
        lastSaveTime = os.time(),
        save_seq     = seq,
    }
    return fullKeyData
end

-- ============================================================================
-- 断线存档（带重试）— 前置声明供 SavePlayer/RemovePlayer/Shutdown 使用
-- ============================================================================

--- 提交存档数据（内部，支持重试 + 写入串行化回调）
---@param uid number
---@param saveData table { [actualKey] = fullKeyData }
---@param retryCount number
---@param serializedKeys table|nil  { [actualKey]=true } 调用方持有的 pending 锁集合，回调时释放
local function commitCleanupData(uid, saveData, retryCount, serializedKeys)
    local commitLabel = "pdm_cleanup_" .. tostring(uid) .. "_r" .. retryCount
    local commit = serverCloud:BatchCommit(commitLabel)

    local totalKeys = 0
    for key, fullKeyData in pairs(saveData) do
        commit:ScoreSet(uid, key, fullKeyData)
        totalKeys = totalKeys + 1
    end

    commit:Commit({
        ok = function()
            cleanupRetries_[uid] = nil

            -- 🔴 重连检测: cleanup 写入的是断线前旧快照，如果玩家已重连，
            -- 内存中有最新数据——必须立即标脏所有 cleanup 涉及的 key，
            -- 让下次 flush 用内存最新值覆盖云端刚写入的旧快照。
            local pd = playerData_[uid]
            if pd then
                local markedCount = 0
                for actualKey in pairs(saveData) do
                    for fk in pairs(fieldDefs_) do
                        local fkAk = getActualKey(uid, fk)
                        if fkAk == actualKey and pd.modules[fk] then
                            pd.dirty[fk] = true
                            markedCount = markedCount + 1
                        end
                    end
                end
                if markedCount > 0 then
                    dirtyUIDs_[uid] = true
                    print(string.format(
                        "[PDM][WARN] cleanup ok but player reconnected — marked %d fields dirty to overwrite stale snapshot uid=%s",
                        markedCount, tostring(uid)))
                end
            end

            -- 🔴 串行化: 释放 pending 锁，处理 reflush
            if serializedKeys then
                for actualKey in pairs(serializedKeys) do
                    clearPending(uid, actualKey)
                    if popReflush(uid, actualKey) then
                        -- pending 期间有新数据写入，需要重新 flush
                        if pd then
                            for fk in pairs(fieldDefs_) do
                                local fkAk = getActualKey(uid, fk)
                                if fkAk == actualKey and pd.modules[fk] then
                                    pd.dirty[fk] = true
                                end
                            end
                            dirtyUIDs_[uid] = true
                        end
                    end
                end
                startDebounceIfDirty()
            end
        end,
        error = function(code, reason)
            print(string.format(
                "[PDM][ERROR] commitCleanupData FAILED uid=%s code=%s reason=%s keys=%d attempt=%d/%d",
                tostring(uid), tostring(code), tostring(reason),
                totalKeys, retryCount + 1, CLEANUP_RETRY_MAX + 1))

            -- 🔴 串行化: 错误时也必须释放 pending 锁（否则永远阻塞）
            if serializedKeys then
                for actualKey in pairs(serializedKeys) do
                    clearPending(uid, actualKey)
                    popReflush(uid, actualKey)  -- 清除 reflush，dirty 恢复会触发新 flush
                end
            end

            if retryCount < CLEANUP_RETRY_MAX then
                -- 指数退避: 2s, 4s, 8s, 16s... (上限 30s)
                local backoffDelay = math.min(CLEANUP_RETRY_DELAY * (2 ^ retryCount), 30)
                cleanupRetries_[uid] = {
                    data       = saveData,
                    retryCount = retryCount + 1,
                    timer      = 0,
                    delay      = backoffDelay,
                }
                print(string.format(
                    "[PDM][WARN] commitCleanupData retry scheduled uid=%s attempt=%d/%d nextDelay=%.1fs",
                    tostring(uid), retryCount + 1, CLEANUP_RETRY_MAX, backoffDelay))
            else
                print(string.format(
                    "[PDM][ERROR] cleanup max retries exceeded uid=%s DATA MAY BE LOST keys=%d " ..
                    "(all %d retries failed over ~%ds — possible persistent cloud outage)",
                    tostring(uid), totalKeys, CLEANUP_RETRY_MAX,
                    CLEANUP_RETRY_DELAY * (2 ^ CLEANUP_RETRY_MAX - 1)))

                -- 🔴 告警钩子：通知外部系统数据面临丢失风险
                if onDataLossAlert_ then
                    local lostKeys = {}
                    for key in pairs(saveData) do
                        lostKeys[#lostKeys + 1] = key
                    end
                    local ok2, err2 = pcall(onDataLossAlert_, uid, lostKeys, CLEANUP_RETRY_MAX)
                    if not ok2 then
                        print("[PDM][ERROR] onDataLossAlert hook threw: " .. tostring(err2))
                    end
                end

                cleanupRetries_[uid] = nil
            end
        end,
    })
end

--- 将所有脏数据批量提交到 serverCloud（由防抖计时器触发）
--- 🔴 写入串行化: 同一 (uid, actualKey) 有 in-flight 提交时，跳过该 key 并标记 reflush
flushDirtyData = function()
    -- 诊断：记录 flush 触发时的脏 UID 列表
    local flushDiagUIDs = {}
    for uid in pairs(dirtyUIDs_) do
        local pd = playerData_[uid]
        local dList = {}
        if pd then for fk in pairs(pd.dirty) do dList[#dList + 1] = fk end end
        flushDiagUIDs[#flushDiagUIDs + 1] = string.format("%s:[%s]", tostring(uid), table.concat(dList, ","))
    end
    print(string.format("[PDM][DIAG-RESET] flushDirtyData TRIGGERED clock=%.4f dirtyUIDs={%s}",
        os.clock(), table.concat(flushDiagUIDs, "; ")))

    local hasData = false
    local flushTime = os.time()
    local flushLabel = "pdm_flush_" .. tostring(flushTime)
    local commit = serverCloud:BatchCommit(flushLabel)

    -- 🔴 保存脏标记快照，用于提交失败时恢复（铁律 #1/#2: 传输层失败必须可重试）
    local savedDirty = {}  -- { [uid] = { [fieldKey] = true } }

    -- 🔴 保存 per-uid 的已序列化快照数据，用于 commit 失败 + 玩家已移除时的 cleanupRetries 兜底
    local perUidSaveData = {}  -- { [uid] = { [actualKey] = fullKeyData } }

    -- 🔴 串行化: 记录本次实际提交的 key（用于回调中释放 pending 锁）
    local committedKeys = {}  -- { [uid] = { [actualKey] = true } }

    local totalScoreSets = 0
    local totalBytes = 0

    for uid in pairs(dirtyUIDs_) do
        local pd = playerData_[uid]
        if pd and next(pd.dirty) then
            -- 保存当前脏标记快照
            savedDirty[uid] = {}
            for fk in pairs(pd.dirty) do
                savedDirty[uid][fk] = true
            end

            -- 收集脏字段涉及的 actualKey（去重）+ 按 key 分组字段
            local actualKeys = {}
            local dirtyFieldsByKey = {}  -- { [actualKey] = { [fieldKey] = true } }
            for fieldKey in pairs(pd.dirty) do
                local ak = getActualKey(uid, fieldKey)
                if ak then
                    actualKeys[ak] = true
                    if not dirtyFieldsByKey[ak] then dirtyFieldsByKey[ak] = {} end
                    dirtyFieldsByKey[ak][fieldKey] = true
                end
            end

            -- 🔴 串行化: 对每个 actualKey 检查 pending，跳过有 in-flight 提交的 key
            committedKeys[uid] = {}
            perUidSaveData[uid] = {}
            local skippedFields = {}  -- 被跳过的字段，保留其脏标记

            for actualKey in pairs(actualKeys) do
                if isPending(uid, actualKey) then
                    -- 有 in-flight 提交，标记 reflush 等待回调后重发
                    markReflush(uid, actualKey)
                    for fk in pairs(dirtyFieldsByKey[actualKey] or {}) do
                        skippedFields[fk] = true
                    end
                    print(string.format(
                        "[PDM] flush: key pending, deferred uid=%s key=%s",
                        tostring(uid), actualKey))
                else
                    -- 无 pending: 标记 pending，构建快照并提交
                    markPending(uid, actualKey)
                    committedKeys[uid][actualKey] = true

                    local fullKeyData = buildFullKeyData(uid, actualKey, true)
                    local keyJson = cjson.encode(fullKeyData)
                    local keySize = #keyJson

                    -- 🔴 硬限制: 超过 150KB 拒绝提交，防止 serverCloud 静默丢弃
                    local FLUSH_HARD_LIMIT = 150000
                    if keySize > FLUSH_HARD_LIMIT then
                        local sizeDetails = {}
                        if type(fullKeyData) == "table" then
                            for subKey, subVal in pairs(fullKeyData) do
                                local subOk, subJson = pcall(cjson.encode, subVal)
                                if subOk then
                                    sizeDetails[#sizeDetails + 1] = string.format("%s=%dB", tostring(subKey), #subJson)
                                end
                            end
                        end
                        print(string.format(
                            "[PDM][ERROR] flush BLOCKED uid=%s key=%s size=%d > %d HARD LIMIT! breakdown=[%s] — data NOT saved, dirty preserved",
                            tostring(uid), actualKey, keySize, FLUSH_HARD_LIMIT, table.concat(sizeDetails, ", ")))
                        -- 释放 pending 锁（不提交但不能留死锁）
                        clearPending(uid, actualKey)
                        committedKeys[uid][actualKey] = nil
                        -- 保留脏标记，跳过该字段所有模块
                        for fk in pairs(fieldDefs_) do
                            local fkActualKey = getActualKey(uid, fk)
                            if fkActualKey == actualKey then
                                skippedFields[fk] = true
                            end
                        end
                    elseif keySize > 50000 then
                        -- 警告：接近危险区，但仍允许提交
                        local sizeDetails = {}
                        if type(fullKeyData) == "table" then
                            for subKey, subVal in pairs(fullKeyData) do
                                local subOk, subJson = pcall(cjson.encode, subVal)
                                if subOk then
                                    sizeDetails[#sizeDetails + 1] = string.format("%s=%dB", tostring(subKey), #subJson)
                                end
                            end
                        end
                        print(string.format(
                            "[PDM][WARN] flush data LARGE uid=%s key=%s totalSize=%d > 50KB! breakdown=[%s]",
                            tostring(uid), actualKey, keySize, table.concat(sizeDetails, ", ")))
                        commit:ScoreSet(uid, actualKey, fullKeyData)
                        perUidSaveData[uid][actualKey] = fullKeyData
                        totalScoreSets = totalScoreSets + 1
                        totalBytes = totalBytes + keySize
                        hasData = true
                    else
                        commit:ScoreSet(uid, actualKey, fullKeyData)
                        perUidSaveData[uid][actualKey] = fullKeyData
                        totalScoreSets = totalScoreSets + 1
                        totalBytes = totalBytes + keySize
                        hasData = true
                    end
                end
            end

            -- 只清除已提交字段的脏标记，保留被跳过字段的脏标记
            local newDirty = {}
            for fk in pairs(skippedFields) do
                newDirty[fk] = true
            end
            pd.dirty = newDirty
        end
    end

    -- 重建 dirtyUIDs_（只保留仍有脏数据的 UID）
    local newDirtyUIDs = {}
    for uid in pairs(dirtyUIDs_) do
        local pd = playerData_[uid]
        if pd and next(pd.dirty) then
            newDirtyUIDs[uid] = true
        end
    end
    dirtyUIDs_ = newDirtyUIDs

    if not hasData then
        -- 如果有被跳过的脏数据，重启防抖等待 pending 释放后重试
        startDebounceIfDirty()
        return
    end

    commit:Commit({
        ok = function()
            -- 🔴 串行化: 释放 pending 锁，处理 reflush
            for uid, keys in pairs(committedKeys) do
                for actualKey in pairs(keys) do
                    clearPending(uid, actualKey)
                    if popReflush(uid, actualKey) then
                        -- pending 期间有新数据写入，重新标记脏触发下一轮 flush
                        local pd = playerData_[uid]
                        if pd then
                            for fk in pairs(fieldDefs_) do
                                local fkAk = getActualKey(uid, fk)
                                if fkAk == actualKey and pd.modules[fk] then
                                    pd.dirty[fk] = true
                                end
                            end
                            dirtyUIDs_[uid] = true
                        end
                    end
                end
            end
            startDebounceIfDirty()
        end,
        error = function(code, reason)
            print(string.format(
                "[PDM][ERROR] flush commit FAILED code=%s reason=%s scoreSets=%d",
                tostring(code), tostring(reason), totalScoreSets))

            -- 🔴 串行化: 错误时也必须释放 pending 锁
            for uid, keys in pairs(committedKeys) do
                for actualKey in pairs(keys) do
                    clearPending(uid, actualKey)
                    popReflush(uid, actualKey)  -- 清除 reflush，dirty 恢复会触发新 flush
                end
            end

            -- 🔴 恢复脏标记（合并，不覆盖异步期间新增的脏数据）
            for uid, fields in pairs(savedDirty) do
                local pd = playerData_[uid]
                if pd then
                    -- 玩家仍在内存：恢复脏标记，等待下次 flush 重试
                    for fk in pairs(fields) do
                        pd.dirty[fk] = true
                    end
                    dirtyUIDs_[uid] = true
                else
                    -- 🔴 玩家已断线清理（RemovePlayer 已执行），playerData_ 为 nil
                    -- 无法恢复脏标记，但我们有已序列化的快照数据
                    -- 提升到 cleanupRetries_ 队列继续重试（复用断线存档重试机制）
                    local saveData = perUidSaveData[uid]
                    if saveData and next(saveData) then
                        if not cleanupRetries_[uid] then
                            cleanupRetries_[uid] = {
                                data       = saveData,
                                retryCount = 0,
                                timer      = 0,
                                delay      = CLEANUP_RETRY_DELAY,
                            }
                            print("[PDM] flush failed + player removed — promoted to cleanupRetries uid=" .. tostring(uid))
                        else
                            -- 🔴 合并而非丢弃：将失败的 key 合并到已有 cleanup entry 中
                            -- 用最新快照覆盖同 key（flush 的快照比 cleanup 的旧快照更新）
                            local existing = cleanupRetries_[uid]
                            local mergedCount = 0
                            for key, fullKeyData in pairs(saveData) do
                                existing.data[key] = fullKeyData
                                mergedCount = mergedCount + 1
                            end
                            -- 合并后重置重试计数（新数据需要完整重试机会）
                            existing.retryCount = 0
                            existing.timer = 0
                            existing.delay = CLEANUP_RETRY_DELAY
                            print(string.format(
                                "[PDM] flush failed + player removed — merged %d keys into existing cleanupRetries uid=%s",
                                mergedCount, tostring(uid)))
                        end
                    end
                end
            end
            -- 重新启动防抖计时器，触发下一次重试
            startDebounceIfDirty()
        end,
    })
end

--- 即时存盘指定玩家（强制，不等防抖）
--- 使用快照 + commitCleanupData（带重试），确保断线场景可靠
--- 🔴 写入串行化: 跳过有 in-flight 提交的 key，标记 reflush 等回调后重发
---@param uid number
function PlayerDataManager.SavePlayer(uid)
    local pd = playerData_[uid]
    if not pd or not next(pd.dirty) then
        -- [DIAG] 无脏数据时也记录一下
        print(string.format("[PDM][DIAG] SavePlayer NO-OP uid=%s (no dirty)", tostring(uid)))
        return
    end

    -- [DIAG] 记录脏字段列表
    local dirtyFieldsStr = ""
    for fk in pairs(pd.dirty) do
        dirtyFieldsStr = dirtyFieldsStr .. fk .. ","
    end
    print(string.format("[PDM][DIAG] SavePlayer uid=%s dirtyFields=[%s]",
        tostring(uid), dirtyFieldsStr))

    -- 收集脏字段涉及的 actualKey（去重）+ 按 key 分组字段
    local actualKeys = {}
    local dirtyFieldsByKey = {}
    for fieldKey in pairs(pd.dirty) do
        local ak = getActualKey(uid, fieldKey)
        if ak then
            actualKeys[ak] = true
            if not dirtyFieldsByKey[ak] then dirtyFieldsByKey[ak] = {} end
            dirtyFieldsByKey[ak][fieldKey] = true
        end
    end

    if not next(actualKeys) then
        pd.dirty = {}
        dirtyUIDs_[uid] = nil
        return
    end

    -- 🔴 串行化: 跳过有 pending 提交的 key
    local saveData = {}
    local serializedKeys = {}
    local skippedFields = {}

    for actualKey in pairs(actualKeys) do
        if isPending(uid, actualKey) then
            markReflush(uid, actualKey)
            for fk in pairs(dirtyFieldsByKey[actualKey] or {}) do
                skippedFields[fk] = true
            end
            print(string.format(
                "[PDM] SavePlayer: key pending, deferred uid=%s key=%s",
                tostring(uid), actualKey))
        else
            markPending(uid, actualKey)
            serializedKeys[actualKey] = true
            saveData[actualKey] = buildFullKeyData(uid, actualKey, true)
        end
    end

    -- 只清除已提交字段的脏标记，保留被跳过字段的脏标记
    local newDirty = {}
    for fk in pairs(skippedFields) do
        newDirty[fk] = true
    end
    pd.dirty = newDirty

    if not next(newDirty) then
        dirtyUIDs_[uid] = nil
    end

    if not next(saveData) then
        -- 所有 key 都被跳过，启动防抖等待 reflush
        startDebounceIfDirty()
        return
    end

    -- 传入 serializedKeys 让 commitCleanupData 回调时释放 pending 锁
    commitCleanupData(uid, saveData, 0, serializedKeys)
end

-- ============================================================================
-- 玩家生命周期：重连防护
-- ============================================================================

--- 清除断线存档重试队列（重连时调用，防止旧快照覆盖新数据）
--- 常驻服务器踩坑.md: "每次检查是否已重连（避免覆盖新数据）"
---@param uid number
function PlayerDataManager.ClearCleanupRetries(uid)
    if cleanupRetries_[uid] then
        print(string.format(
            "[PDM] ClearCleanupRetries: discarding stale cleanup snapshot uid=%s retryCount=%d",
            tostring(uid), cleanupRetries_[uid].retryCount))
        cleanupRetries_[uid] = nil
    end
end

-- ============================================================================
-- 玩家生命周期：移除
-- ============================================================================

--- 移除玩家（断线/踢出时调用）
--- 铁律：先存后清（SaveAll → Dispose，反了 = 回档）
--- 🔴 串行化: 清除 pending/reflush 状态，最终快照以最高 save_seq 提交
---@param uid number
---@param skipSave boolean|nil  true 时跳过存盘
function PlayerDataManager.RemovePlayer(uid, skipSave)
    local TAG = "[PDM][DIAG-RESET]"
    local t0 = os.clock()
    print(string.format("%s RemovePlayer START uid=%s skipSave=%s clock=%.4f caller=%s",
        TAG, tostring(uid), tostring(skipSave), t0,
        tostring(debug.traceback(nil, 2):match("[^\n]*\n[^\n]*"))))

    local pd = playerData_[uid]
    if not pd then
        print(string.format("%s RemovePlayer ABORT — no playerData uid=%s", TAG, tostring(uid)))
        return
    end

    -- 诊断：记录被移除时的脏字段和模块状态
    local dirtyList = {}
    for fk in pairs(pd.dirty) do dirtyList[#dirtyList + 1] = fk end
    local modList = {}
    for mk in pairs(pd.modules) do modList[#modList + 1] = mk end
    print(string.format("%s RemovePlayer state: dirtyFields=[%s] modules=[%s] dirtyUID=%s",
        TAG, table.concat(dirtyList, ","), table.concat(modList, ","),
        tostring(dirtyUIDs_[uid] ~= nil)))

    -- 🔴 串行化: 检查是否有 pending 的 in-flight 提交
    -- RemovePlayer 通常在断线 5 分钟后调用，此时 pending 应已完成
    -- 如有残留 pending，日志告警（最终快照的 save_seq 更高，serverCloud 端可溯源）
    if pendingKeys_[uid] and next(pendingKeys_[uid]) then
        local pendingList = {}
        for ak in pairs(pendingKeys_[uid]) do
            pendingList[#pendingList + 1] = ak
        end
        print(string.format(
            "[PDM][WARN] RemovePlayer: %d keys still pending uid=%s keys=[%s] — cleanup snapshot will have higher save_seq",
            #pendingList, tostring(uid), table.concat(pendingList, ",")))
    end

    -- 清除串行化状态（pending/reflush），最终快照将以最新 save_seq 提交
    clearSerializationState(uid)

    -- 先存
    if not skipSave and next(pd.dirty) then
        local saveData = {}
        local keysProcessed = {}

        for fieldKey in pairs(pd.dirty) do
            local actualKey = getActualKey(uid, fieldKey)
            if actualKey and not keysProcessed[actualKey] then
                keysProcessed[actualKey] = true
                saveData[actualKey] = buildFullKeyData(uid, actualKey, true)
            end
        end

        if next(saveData) then
            commitCleanupData(uid, saveData, 0)
        end
    end

    -- 后清（包括 saveSeq_ 已在 clearSerializationState 中清除）
    print(string.format("%s RemovePlayer CLEARING memory uid=%s clock=%.4f",
        TAG, tostring(uid), os.clock()))
    playerData_[uid] = nil
    dirtyUIDs_[uid] = nil
    loadTimeouts_[uid] = nil

    if serverDispatcher_ then
        serverDispatcher_.clearCache(uid)
    end

    print(string.format("%s RemovePlayer COMPLETE uid=%s elapsed=%.4fs",
        TAG, tostring(uid), os.clock() - t0))
end

-- ============================================================================
-- 定时更新（由 Server.lua 每帧调用）
-- ============================================================================

---@param dt number
function PlayerDataManager.Update(dt)
    -- 防抖存盘
    if debounceRunning_ then
        debounceTimer_ = debounceTimer_ - dt
        if debounceTimer_ <= 0 then
            debounceRunning_ = false
            local ok, err = pcall(flushDirtyData)
            if not ok then
                print("[PDM] flushDirtyData error: " .. tostring(err))
            end
        end
    end

    -- 读档超时兜底：serverCloud:Get / quota:Get 无回调时必须失败返回，避免客户端永久 loading
    if next(loadTimeouts_) then
        local timedOutLoads = {}
        for uid, entry in pairs(loadTimeouts_) do
            entry.timer = (entry.timer or 0) + dt
            if entry.timer >= LOAD_TIMEOUT_SECONDS then
                timedOutLoads[#timedOutLoads + 1] = uid
            end
        end
        for _, uid in ipairs(timedOutLoads) do
            local entry = loadTimeouts_[uid]
            if entry then
                local pending = {}
                for key in pairs(entry.pendingKeys or {}) do
                    pending[#pending + 1] = tostring(key)
                end
                table.sort(pending)
                print(string.format(
                    "[PDM][LOAD-TIMEOUT] uid=%s kind=%s sv=%s pending=[%s] elapsed=%.1fs",
                    tostring(uid), tostring(entry.kind), tostring(entry.sv), table.concat(pending, ","), entry.timer or 0))
                emitLoadDiag(uid, string.format("%s TIMEOUT sv=%s pending=[%s] elapsed=%.1fs",
                    tostring(entry.kind), tostring(entry.sv), table.concat(pending, ","), entry.timer or 0))
                local pd = playerData_[uid]
                loadTimeouts_[uid] = nil
                if pd and pd.sessionVersion == entry.sv and entry.callback then
                    entry.callback(false)
                end
            end
        end
    end

    -- 🔴 pending 超时检测：防止 commit 回调永远不触发导致写入永久卡住
    -- 如果某个 key 在 pending 状态超过 PENDING_TIMEOUT_SECONDS，强制释放并标记重发
    local now = os.clock()
    local timedOutKeys = nil  -- 收集后统一处理，避免迭代中修改
    for uid, keys in pairs(pendingKeys_) do
        for actualKey, startTime in pairs(keys) do
            if (now - startTime) > PENDING_TIMEOUT_SECONDS then
                if not timedOutKeys then timedOutKeys = {} end
                timedOutKeys[#timedOutKeys + 1] = { uid = uid, key = actualKey, elapsed = now - startTime }
            end
        end
    end
    if timedOutKeys then
        for _, entry in ipairs(timedOutKeys) do
            local uid, actualKey = entry.uid, entry.key
            print(string.format(
                "[PDM][ERROR] pending TIMEOUT uid=%s key=%s elapsed=%.1fs > %ds — " ..
                "force releasing lock (commit callback likely never fired)",
                tostring(uid), actualKey, entry.elapsed, PENDING_TIMEOUT_SECONDS))
            clearPending(uid, actualKey)
            -- 恢复脏标记使下次 flush 重发（pcall 保护，防止 getActualKey 崩溃——铁律 #8/#10）
            local pd = playerData_[uid]
            if pd then
                for fk in pairs(fieldDefs_) do
                    local ok, fkAk = pcall(getActualKey, uid, fk)
                    if ok and fkAk == actualKey and pd.modules[fk] then
                        pd.dirty[fk] = true
                        dirtyUIDs_[uid] = true
                    end
                end
            end
            popReflush(uid, actualKey)
        end
        startDebounceIfDirty()
    end

    -- 断线存档重试（指数退避）
    if next(cleanupRetries_) then
        for uid, entry in pairs(cleanupRetries_) do
            entry.timer = entry.timer + dt
            local retryDelay = entry.delay or CLEANUP_RETRY_DELAY
            if entry.timer >= retryDelay then
                local data = entry.data
                local retryCount = entry.retryCount
                cleanupRetries_[uid] = nil
                -- 🔴 防丢档: 玩家已重连（playerData_ 已有新数据），丢弃旧快照
                -- 常驻服务器踩坑.md: "每次检查是否已重连（避免覆盖新数据）"
                if playerData_[uid] then
                    print(string.format(
                        "[PDM] cleanupRetry SKIPPED: player reconnected uid=%s retryCount=%d (stale snapshot discarded)",
                        tostring(uid), retryCount))
                else
                    commitCleanupData(uid, data, retryCount)
                end
            end
        end
    end
end

-- ============================================================================
-- Quota API（限额读写）
-- ============================================================================

--- 获取限额当前状态（从本地缓存读取）
---@param uid number
---@param quotaKey string  如 "daily_signin"
---@return table|nil  { value: number, limit: number } 或 nil（玩家不存在）
function PlayerDataManager.GetQuotaState(uid, quotaKey)
    local pd = playerData_[uid]
    if not pd or not pd.modules.quotas then return nil end
    return pd.modules.quotas[quotaKey]
end

--- 使用限额（乐观更新 + 异步提交）
--- 成功时本地 value 立即 +amount，异步 quota:Add 到服务端；
--- 异步失败时回滚本地值。
---@param uid number
---@param quotaKey string  如 "daily_signin"
---@param amount number    消耗数量（正整数，默认 1）
---@return boolean ok
---@return string|nil errMsg  失败原因: "not_loaded" | "unknown_key" | "quota_exceeded"
function PlayerDataManager.UseQuota(uid, quotaKey, amount)
    amount = amount or 1

    local pd = playerData_[uid]
    if not pd or not pd.modules.quotas then
        return false, "not_loaded"
    end

    -- 1. 查找 key 定义
    local keyDef = QuotaConsts.FindByKey(quotaKey)
    if not keyDef then
        print("[PDM] UseQuota: unknown key=" .. tostring(quotaKey))
        return false, "unknown_key"
    end

    -- 2. 本地校验
    local state = pd.modules.quotas[quotaKey]
    if not state then
        state = { value = 0, limit = keyDef.limit }
        pd.modules.quotas[quotaKey] = state
    end

    if state.value + amount > state.limit then
        return false, "quota_exceeded"
    end

    -- 3. 乐观更新（不回滚，见 error 回调注释）
    state.value = state.value + amount

    -- 4. 推送缓存变更到客户端
    PlayerDataManager.MarkDirty(uid, "quotas")

    -- 5. 异步提交到 serverCloud
    serverCloud.quota:Add(uid, keyDef.key, amount,
        keyDef.limit, keyDef.refreshType, keyDef.refreshCount, {
        ok = function()
            -- 成功，无需额外操作（本地已更新）
        end,
        error = function(code, reason)
            -- 不回滚本地缓存：quota 是防刷二次保险，业务状态以
            -- dailyClaimed/weeklyClaimed 为准。回滚反而导致 quota 与
            -- 业务数据不一致（quota 允许再签但 claimed 已标记）。
            -- 下次 LoadPlayer 时 quota:Get 会拿到服务端真实值。
            print("[PDM] UseQuota server error (no rollback) uid=" .. tostring(uid)
                .. " key=" .. quotaKey
                .. " code=" .. tostring(code)
                .. " reason=" .. tostring(reason))
        end,
    })

    return true, nil
end

--- 刷新限额缓存（重新从服务端 quota:Get）
---@param uid number
---@param quotaKey string  如 "daily_signin"
---@param callback function(ok: boolean)|nil
function PlayerDataManager.RefreshQuota(uid, quotaKey, callback)
    local pd = playerData_[uid]
    if not pd then
        if callback then callback(false) end
        return
    end

    local keyDef = QuotaConsts.FindByKey(quotaKey)
    if not keyDef then
        print("[PDM] RefreshQuota: unknown key=" .. tostring(quotaKey))
        if callback then callback(false) end
        return
    end

    serverCloud.quota:Get(uid, keyDef.key, {
        ok = function(datas)
            if not playerData_[uid] then
                if callback then callback(false) end
                return
            end
            if not pd.modules.quotas then
                pd.modules.quotas = {}
            end
            if datas and #datas > 0 then
                pd.modules.quotas[quotaKey] = {
                    value = datas[1].value or 0,
                    limit = datas[1].limit or keyDef.limit,
                }
            else
                pd.modules.quotas[quotaKey] = { value = 0, limit = keyDef.limit }
            end
            PlayerDataManager.MarkDirty(uid, "quotas")
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[PDM] RefreshQuota error uid=" .. tostring(uid)
                .. " key=" .. quotaKey
                .. " code=" .. tostring(code)
                .. " reason=" .. tostring(reason))
            if callback then callback(false) end
        end,
    })
end

-- ============================================================================
-- 定时更新 / 关闭
-- ============================================================================

--- 服务器关闭时 flush 所有脏数据
--- 🔴 修复: 不再在 Shutdown 中清除内存——进程即将退出，OS 会回收内存。
--- 之前的做法是 async flush 后立即清空 playerData_/cleanupRetries_/dirtyUIDs_ 等，
--- 导致 flush 的 error 回调无法恢复脏标记或提升到 cleanupRetries_，
--- 最终造成未持久化的数据（如保底计数）在服务器重启后丢失。
function PlayerDataManager.Shutdown()
    print("[PDM] Shutdown: flushing all dirty data...")

    -- 统计待刷数据量，用于日志
    local dirtyCount = 0
    for uid in pairs(dirtyUIDs_) do dirtyCount = dirtyCount + 1 end
    local retryCount = 0
    for uid in pairs(cleanupRetries_) do retryCount = retryCount + 1 end
    print(string.format("[PDM] Shutdown: dirtyUIDs=%d cleanupRetries=%d", dirtyCount, retryCount))

    -- 🔴 Shutdown: 不清除 pendingKeys，让 flushDirtyData 的 isPending 检查正常工作。
    -- 如果某 key 仍有 in-flight commit，flush 会跳过它并标记 reflush，
    -- 待 in-flight 的回调执行后自然触发重发。这避免了重复提交同一 key 导致的
    -- 写入竞争（旧值覆盖新值）。
    -- 注：Shutdown 时 in-flight 的回调仍会执行（内存未清空），所以这里安全。

    flushDirtyData()

    -- 提交所有待重试的断线存档
    for uid, entry in pairs(cleanupRetries_) do
        print("[PDM] Shutdown: flushing pending cleanup uid=" .. tostring(uid))
        local commit = serverCloud:BatchCommit("pdm_shutdown_" .. tostring(uid))
        for key, fullKeyData in pairs(entry.data) do
            commit:ScoreSet(uid, key, fullKeyData)
        end
        commit:Commit()
    end

    -- 🔴 不清除内存！
    -- 进程即将退出，OS 会回收所有内存。保留 playerData_/cleanupRetries_ 等数据
    -- 使得 flushDirtyData 的 error 回调仍可正常执行恢复逻辑。
    -- 之前在此处的 playerData_={}, cleanupRetries_={}, dirtyUIDs_={} 等赋值
    -- 是导致保底计数丢失的根因——async commit 尚未完成时内存已被清空。

    print("[PDM] Shutdown complete (memory retained for async callbacks)")
end

return PlayerDataManager
