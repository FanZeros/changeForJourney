-- ============================================================================
-- AdHandler - 广告崩溃/超时补偿服务端处理
-- 职责:
--   AD_PENDING  → 写入 adPending 标记（广告 SDK 调用前）
--   AD_CONFIRM  → 结算奖励 + 清除标记（广告成功回调后）
--   CheckAndPushPending → 登录/重连时检查并推送未确认标记
-- 层级: server/ad  |  纯 Handler + 内联逻辑（暂无独立 Service）
-- ============================================================================

local Protocol          = require("shared.Protocol")
local SaveManager       = require("server.SaveManager")
local ServerDispatcher  = require("network.ServerDispatcher")
local TaskService       = require("server.task.TaskService")
local MarketService     = require("server.market.MarketService")
local PDM              = require("server.character.PlayerDataManager")

local TAG = "[AdHandler]"

--- 广告场景白名单（只有已注册的 scene 才能获得补偿）
local VALID_SCENES = {
    privilege      = true,   -- 特权广告
    offline_bonus  = true,   -- 离线奖励双倍
}

--- adPending 最大有效期（秒）：超过此时间视为过期，不补偿
local PENDING_EXPIRY_SECS = 86400  -- 24小时

--- 崩溃补偿最小经过时间（秒）：低于此时间不认为是崩溃，不自动补偿
--- 与客户端 AdManager.CRASH_MIN_ELAPSED_SECS 保持一致（15秒）
local CRASH_MIN_ELAPSED_SECS = 15

local AdHandler = {}
local handlers = {}

-- ─────────────────────────── 内部工具 ───────────────────────────

--- serverCloud key for adPending（per-player）
local AD_PENDING_KEY = "ad_pending"

--- 内存缓存：避免每次都读 cloud（写入时同步更新缓存）
---@type table<number, table|nil>
local pendingCache_ = {}

--- 最近已结算广告缓存：用于处理弱网/重试导致的 AD_CONFIRM 幂等返回
---@type table<number, table<string, number>>
local settledCache_ = {}
local SETTLED_CACHE_SECS = 600

--- 获取当前 adPending 数据（优先从内存缓存读取）
---@param uid number
---@return table|nil  { scene = string, timestamp = number }
local function getPending(uid)
    return pendingCache_[uid]
end

--- 写入 adPending 标记（同时写 cloud + 内存缓存）
---@param uid number
---@param scene string
local function setPending(uid, scene)
    local data = {
        scene     = scene,
        timestamp = os.time(),
    }
    pendingCache_[uid] = data
    -- 持久化到 serverCloud，确保断线/崩溃后重连仍可读取
    serverCloud:Set(uid, AD_PENDING_KEY, data)
    return true
end

--- 清除 adPending 标记（同时清 cloud + 内存缓存）
---@param uid number
local function clearPending(uid)
    if pendingCache_[uid] then
        pendingCache_[uid] = nil
        serverCloud:Set(uid, AD_PENDING_KEY, false)
        -- 推送 false 通知客户端清除 adPending 标记
        ---@diagnostic disable-next-line: param-type-mismatch
        ServerDispatcher.pushModule(uid, "adPending", false)
    end
end

local function markSettled(uid, scene)
    if not uid or not scene then return end
    settledCache_[uid] = settledCache_[uid] or {}
    settledCache_[uid][scene] = os.time()
end

local function wasRecentlySettled(uid, scene)
    local byScene = settledCache_[uid]
    local ts = byScene and byScene[scene]
    if not ts then return false end
    if os.time() - ts > SETTLED_CACHE_SECS then
        byScene[scene] = nil
        return false
    end
    return true
end

--- 根据 scene 执行对应奖励结算
---@param uid number
---@param scene string
---@return boolean success
---@return string|nil reason
local function settleReward(uid, scene)
    if scene == "privilege" then
        -- force=true: AD_CONFIRM 路径已通过 pending 标记验证玩家确实看了广告
        -- 即使 adStored 因时序边界为 0 也应发奖（安全性由 pending 系统保证）
        local ok, reason, payload = MarketService.WatchPrivilegeAd(uid, true)
        if not ok then
            print(string.format("%s settleReward FAIL scene=%s uid=%s reason=%s",
                TAG, scene, tostring(uid), tostring(reason)))
            return false, reason
        end
        -- 推送特权状态更新
        if payload then
            ServerDispatcher.pushModule(uid, "privilege", payload)
        end
        -- 推进广告任务进度
        TaskService.UpdateProgress(uid, "watch_ad", 1)
        return true, nil, payload

    elseif scene == "offline_bonus" then
        -- 离线奖励的广告加成由 OfflineService.ClaimRewards 处理
        -- 此处仅标记"广告已看"，实际结算由玩家点击领取时触发
        -- 通过推送 adConfirmed 模块让客户端知道广告已确认
        ServerDispatcher.pushModule(uid, "adConfirmed", { scene = scene, success = true })
        TaskService.UpdateProgress(uid, "watch_ad", 1)
        return true
    end

    print(string.format("%s settleReward unknown scene=%s uid=%s", TAG, scene, tostring(uid)))
    return false, "unknown_scene"
end

-- ─────────────────────────── Handler ───────────────────────────

--- AD_PENDING: 广告即将展示，写入标记
handlers[Protocol.ACTION_TYPES.AD_PENDING] = function(uid, params)
    local scene = params and params.scene
    if not scene or not VALID_SCENES[scene] then
        return { success = false, reason = "invalid_scene" }
    end

    -- 如果已有 pending 且未过期：
    --   同 scene → 拒绝重复标记（防止同场景滥用刷时间戳）
    --   不同 scene → 覆盖旧 pending（旧的已无法正常补偿，新的需要正确跟踪）
    -- FIX: 原逻辑对跨 scene 也拒绝，导致旧 pending 残留时新广告 CONFIRM 被 scene_mismatch 拒绝
    local existing = getPending(uid)
    if existing and (os.time() - existing.timestamp) < PENDING_EXPIRY_SECS then
        if existing.scene == scene then
            -- 同 scene 重复请求：拒绝（防止刷新时间戳延长补偿窗口）
            print(string.format("%s AD_PENDING same-scene duplicate, keeping existing uid=%s scene=%s",
                TAG, tostring(uid), scene))
            return { success = true, alreadyPending = true }
        else
            -- 不同 scene：覆盖旧 pending（旧奖励已丢失，确保新广告能正确 CONFIRM）
            print(string.format("%s AD_PENDING overriding stale pending uid=%s old=%s new=%s",
                TAG, tostring(uid), existing.scene, scene))
            -- 继续执行下方 setPending，覆盖旧值
        end
    end

    local ok = setPending(uid, scene)
    if not ok then
        return { success = false, reason = "save_error" }
    end

    print(string.format("%s AD_PENDING set uid=%s scene=%s", TAG, tostring(uid), scene))
    return { success = true }
end

--- AD_CONFIRM: 广告成功完成，结算奖励并清除标记
handlers[Protocol.ACTION_TYPES.AD_CONFIRM] = function(uid, params)
    local scene = params and params.scene
    if not scene or not VALID_SCENES[scene] then
        return { success = false, reason = "invalid_scene" }
    end

    -- 获取 pending 标记
    local pending = getPending(uid)

    -- 🔴 安全校验：必须有 pending 标记才能结算（防止绕过广告直接刷奖励）
    if not pending then
        if wasRecentlySettled(uid, scene) then
            print(string.format("%s AD_CONFIRM idempotent success: recently settled uid=%s scene=%s",
                TAG, tostring(uid), scene))
            local payload = (scene == "privilege") and MarketService.GetPrivilegeAdPayload(uid) or nil
            return { success = true, scene = scene, idempotent = true, privilege = payload }
        end
        print(string.format("%s AD_CONFIRM REJECTED: no pending marker uid=%s scene=%s",
            TAG, tostring(uid), scene))
        return { success = false, reason = "no_pending", scene = scene }
    end

    -- 🔴 安全校验：scene 必须与 pending 一致（防止跨场景利用）
    if pending.scene ~= scene then
        print(string.format("%s AD_CONFIRM REJECTED: scene mismatch uid=%s pending=%s got=%s",
            TAG, tostring(uid), pending.scene, scene))
        return { success = false, reason = "scene_mismatch", scene = scene }
    end

    -- 🔴 先结算再清标记：结算失败时保留 pending 以便重连补偿（铁律 #3 事务一致性）
    local ok, reason, payload = settleReward(uid, scene)
    if not ok then
        -- 结算失败，保留 pending 标记，下次重连仍可触发补偿
        print(string.format("%s AD_CONFIRM settle FAILED, keeping pending uid=%s scene=%s reason=%s",
            TAG, tostring(uid), scene, tostring(reason)))
        return { success = false, reason = reason, scene = scene }
    end

    -- 结算成功后才清除标记
    markSettled(uid, scene)
    clearPending(uid)

    print(string.format("%s AD_CONFIRM settled uid=%s scene=%s", TAG, tostring(uid), scene))
    return { success = true, scene = scene, privilege = payload }
end

-- ─────────────────────────── 公开 API ───────────────────────────

--- 登录/重连时检查并推送 adPending（由 Server.lua loadAndPushFullState 调用）
--- 异步从 serverCloud 读取（内存缓存可能因进程重启而丢失）
---@param uid number
function AdHandler.CheckAndPushPending(uid)
    -- 先检查内存缓存
    local cached = pendingCache_[uid]
    if cached then
        local elapsed = os.time() - cached.timestamp
        if elapsed > PENDING_EXPIRY_SECS then
            print(string.format("%s CheckAndPushPending EXPIRED (cache) uid=%s scene=%s elapsed=%ds",
                TAG, tostring(uid), cached.scene, elapsed))
            clearPending(uid)
            return
        end
        print(string.format("%s CheckAndPushPending PUSH (cache) uid=%s scene=%s elapsed=%ds",
            TAG, tostring(uid), cached.scene, elapsed))
        ServerDispatcher.pushModule(uid, "adPending", {
            scene     = cached.scene,
            timestamp = cached.timestamp,
            elapsed   = elapsed,
        })
        return
    end

    -- 内存无缓存（进程重启/首次加载），从 cloud 异步读取
    serverCloud:Get(uid, AD_PENDING_KEY, {
        ok = function(scores)
            local data = scores and scores[AD_PENDING_KEY]
            if not data or data == false or type(data) ~= "table" then
                return  -- 无 pending 标记
            end

            local elapsed = os.time() - (data.timestamp or 0)

            -- 过期清除
            if elapsed > PENDING_EXPIRY_SECS then
                print(string.format("%s CheckAndPushPending EXPIRED (cloud) uid=%s scene=%s elapsed=%ds",
                    TAG, tostring(uid), data.scene, elapsed))
                pendingCache_[uid] = nil
                serverCloud:Set(uid, AD_PENDING_KEY, false)
                return
            end

            -- 写入内存缓存
            pendingCache_[uid] = data

            -- 推送给客户端
            print(string.format("%s CheckAndPushPending PUSH (cloud) uid=%s scene=%s elapsed=%ds",
                TAG, tostring(uid), data.scene, elapsed))
            ServerDispatcher.pushModule(uid, "adPending", {
                scene     = data.scene,
                timestamp = data.timestamp,
                elapsed   = elapsed,
            })
        end,
        error = function(code, reason)
            print(string.format("%s CheckAndPushPending cloud read error uid=%s code=%s",
                TAG, tostring(uid), tostring(code)))
        end,
    })
end

--- 返回崩溃补偿最小经过时间（客户端也可能需要此常量）
function AdHandler.GetCrashMinElapsed()
    return CRASH_MIN_ELAPSED_SECS
end

AdHandler.actionHandlers = handlers

return AdHandler
