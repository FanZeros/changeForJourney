-- =====================================================================-- AdManager — 统一广告入口
-- 职责：
--   1. ShowAdWithMute  唯一广告调用入口，所有广告必须经此发起
--   2. 三重超时保护    SDK 正常回调 / 8秒焦点清理 / 40秒加载超时赠送奖励
--   3. 崩溃补偿        AD_PENDING/AD_CONFIRM 服务端标记 + 重连自动补偿
--
-- 多人架构适配说明：
--   本项目服务端是数据权威方：
--   广告 SDK 调用前发 AD_PENDING，成功后发 AD_CONFIRM，由服务端结算奖励。
--   重连时服务端推送 adPending 模块，客户端自动判断是否触发补偿。
-- =====================================================================
local Protocol         = require("shared.Protocol")
local ClientDispatcher = require("network.ClientDispatcher")
local GameAlgoService  = require("client.GameAlgoService")

local AdManager = {}

---@diagnostic disable-next-line: undefined-global
local sdk = sdk  -- 引擎注入的全局 SDK 对象

-- ======================== 超时阈值 ========================
local AD_FOCUS_CLEANUP_SECS  = 20.0  -- 焦点恢复后等待 SDK 回调的宽限时间（国内 SDK 服务端验证可能需 5-15s）
local AD_LOADING_TIMEOUT_SECS = 90.0  -- 加载超时安全网（需覆盖 60s最长广告 + 15s SDK验证 + 15s余量）
local AD_ABSOLUTE_TIMEOUT_SECS = 120  -- 🔴 绝对兜底超时（os.time 秒）：无论焦点/计时器状态，超过此秒数强制终止

-- ======================== AD_CONFIRM 重试 ========================
local AD_CONFIRM_MAX_RETRIES   = 60    -- 最大重试次数：覆盖鸿蒙/部分安卓广告返回后网络恢复慢
local AD_CONFIRM_RETRY_DELAY   = 5.0   -- 重试间隔（秒）— 总窗口 5 分钟

-- ======================== 模块状态=================---@type boolean
local adLoading_          = false   -- 广告是否正在加载/展示中（防重入）
---@type boolean
local adCallbackFired_    = false   -- SDK 回调是否已触发（防重复处理）
---@type string|nil
local adPendingScene_     = nil     -- 当前广告场景标识
---@type function|nil
local adPendingCallback_  = nil     -- 用户回调引用
---@type number
local adFocusCleanupTimer_ = 0      -- 焦点恢复后倒计时（>0 时每帧递减）
---@type number
local adLoadingTimer_     = 0       -- 加载超时倒计时
---@type boolean
local adSdkEverResponded_ = false   -- SDK 本次广告是否曾真实回调过（防止 SDK 静默丢弃时触发 timeout_gift）
---@type number
local adFocusLostAt_      = 0       -- 焦点丢失时刻（os.time），用于计算广告展示时长
---@type number
local adShowStartTime_    = 0       -- 广告发起时刻（os.time），焦点事件未触发时的 fallback

-- 焦点超时赠送阈值：广告展示超过此秒数，即使 SDK 回调超时也赠送奖励
-- 国内激励视频最短约 15 秒，阈值必须 >= 最短广告时长，否则玩家跳过也能拿奖励
local AD_FOCUS_TIMEOUT_GIFT_SECS = 15

-- 崩溃补偿最小经过时间：重连时 adPending.elapsed 需 >= 此值才自动补偿
-- 低于此阈值说明可能是玩家主动退出而非崩溃，不予自动补偿
-- 与焦点超时赠送阈值一致，确保只有完整观看广告后崩溃才补偿
local CRASH_MIN_ELAPSED_SECS = 15

-- AD_CONFIRM 重试状态
local adConfirmRetry_ = {
    active    = false,   -- 是否正在等待重试
    scene     = nil,     -- 需要重试的广告场景
    remaining = 0,       -- 剩余重试次数
    timer     = 0,       -- 重试倒计时
}

-- ======================== 依赖注入 =================---@type fun(action: string, params: table)|nil
local sendActionFn_ = nil  -- 由 Init 注入，避免循环依赖 Client.lua

-- ======================== 内部辅助 =================
--- 重置所有广告中间状态（回调处理完成后调用）
local function resetAdState()
    print(string.format("[AdManager] resetAdState: scene=%s responded=%s",
        tostring(adPendingScene_), tostring(adSdkEverResponded_)))
    adLoading_          = false
    adCallbackFired_    = false
    adPendingScene_     = nil
    adPendingCallback_  = nil
    adFocusCleanupTimer_ = 0
    adLoadingTimer_     = 0
    adSdkEverResponded_ = false
    adFocusLostAt_      = 0
    adShowStartTime_    = 0
end

--- 安全调用用户回调（pcall 保护，防止回调异常影响广告状态机）
---@param callback function
---@param success boolean
---@param reason string|nil
local function fireCallback(callback, success, reason)
    local ok, err = pcall(callback, { success = success, reason = reason })
    if not ok then
        print("[AdManager] callback error: " .. tostring(err))
    end
end

-- ======================== 公开接口 =================
--- 初始化广告管理器
--- @param sendActionFn function(action, params)  发送服务端 action 的函数（注入以避免循环依赖）
function AdManager.Init(sendActionFn)
    sendActionFn_ = sendActionFn

    -- 订阅 adPending 模块：服务端在 loadAndPushFullState（登录/重连）时推送
    ClientDispatcher.subscribe("adPending", function(data, moduleName)
        AdManager.OnAdPendingReceived(data)
    end)

    print("[AdManager] Init: ready (server-side crash recovery enabled)")
end

--- 查询广告是否正在展示中（用于 UI 防重复点击）
---@return boolean
function AdManager.IsLoading()
    return adLoading_
end

--- 唯一广告入口：展示激励视频广告，并带三重超时保护
---
--- @param callback function  广告结束回调 function(result)
---                           result.success = true/false
---                           result.reason  = "timeout_gift" | "focus_timeout" | 失败描述
--- @param adScene  string    广告场景标识（如 "privilege"、"offline_double"）
function AdManager.ShowAdWithMute(callback, adScene)
    adScene = adScene or "unknown"

    -- ── 阶段 1：快速拦截──────────────────────────────────────────────────
    -- PC/Web 已接入激励视频 SDK，与移动端统一走 ShowRewardVideoAd
    local platform = GetPlatform()
    print(string.format("[AdManager] ShowAdWithMute: platform=%s scene=%s adLoading=%s responded=%s",
        tostring(platform), adScene, tostring(adLoading_), tostring(adSdkEverResponded_)))

    -- 防重入：广告正在加载中
    if adLoading_ then
        print(string.format("[AdManager] ad already loading (timer=%.1fs focus=%.1fs), ignoring scene=%s",
            adLoadingTimer_, adFocusCleanupTimer_, adScene))
        fireCallback(callback, false, "already_loading")
        return
    end

    -- SDK 可用性检查
    if not sdk then
        print("[AdManager] sdk not available, scene=" .. adScene)
        fireCallback(callback, false, "sdk_unavailable")
        return
    end

    -- ── 阶段 2：预计数与崩溃保护─────────────────────────────────────────
    adLoading_          = true
    adCallbackFired_    = false
    adPendingScene_     = adScene
    adPendingCallback_  = callback
    adLoadingTimer_     = AD_LOADING_TIMEOUT_SECS
    adShowStartTime_    = os.time()

    print(string.format("[AdManager] showing ad scene=%s loadingTimer=%.1fs", adScene, adLoadingTimer_))

    -- ── 阶段 3：通知服务端写入 adPending 标记 ────────────────────────────
    if sendActionFn_ then
        sendActionFn_(Protocol.ACTION_TYPES.AD_PENDING, { scene = adScene })
    end

    -- ── 阶段 4：调用 SDK ──────────────────────────────────────────────────
    sdk:ShowRewardVideoAd(function(result)
        -- 防 SDK 重复/迟到回调：
        --   adCallbackFired_ 防同一次广告的重复回调
        --   not adLoading_   → resetAdState() 后迟到的回调（adCallbackFired_ 已被 reset 为 false）
        if not adLoading_ or adCallbackFired_ then
            print(string.format("[AdManager] duplicate/late SDK callback ignored scene=%s adLoading=%s fired=%s",
                adScene, tostring(adLoading_), tostring(adCallbackFired_)))
            return
        end
        adCallbackFired_     = true
        adSdkEverResponded_  = true  -- SDK 真实回调过，允许后续 timeout_gift

        -- 清零两个计时器（正常回调路径）
        adFocusCleanupTimer_ = 0
        adLoadingTimer_      = 0

        local success = (type(result) == "table" and result.success == true)
            or (type(result) == "boolean" and result == true)

        -- 打印原始 result 内容，便于排查 SDK 返回的具体失败原因
        local resultType = type(result)
        local resultMsg  = (resultType == "table" and result.msg) or "n/a"
        local resultCode = (resultType == "table" and result.code) or "n/a"
        print(string.format("[AdManager] SDK callback scene=%s success=%s type=%s msg=%s code=%s",
            adScene, tostring(success), resultType, tostring(resultMsg), tostring(resultCode)))

        -- 停止加载计时器（SDK 已回调）
        adLoadingTimer_      = 0

        local savedCallback = adPendingCallback_
        local savedScene    = adPendingScene_

        if success then
            -- 通知服务端广告成功完成，结算奖励并清除 pending 标记
            -- 成功：停止加载超时计时器，发送 AD_CONFIRM
            adFocusCleanupTimer_ = 0
            GameAlgoService.TrackAd(savedScene)
            resetAdState()
            if sendActionFn_ and savedScene then
                sendActionFn_(Protocol.ACTION_TYPES.AD_CONFIRM, { scene = savedScene })
                -- 启动重试保护：长时间后台可能导致网络已断，首次发送可能丢失
                adConfirmRetry_.active    = true
                adConfirmRetry_.scene     = savedScene
                adConfirmRetry_.remaining = AD_CONFIRM_MAX_RETRIES
                adConfirmRetry_.timer     = AD_CONFIRM_RETRY_DELAY
            end
            fireCallback(savedCallback, true, nil)
        else
            -- 失败时：不发送确认，不重试。失败属正常外部应用行为，重置状态并启动超时赠送
            if adFocusLostAt_ > 0 then
                -- 焦点曾丢失（广告曾展示）：立即判断广告展示时长决定是否赠送
                -- 🔴 FIX: 不再 defer 到 focus cleanup timer（adCallbackFired_=true 会阻止 timer 运行导致死锁）
                local focusLostDuration = os.time() - adFocusLostAt_
                print(string.format("[AdManager] SDK failure + focus was lost: duration=%ds threshold=%ds scene=%s",
                    focusLostDuration, AD_FOCUS_TIMEOUT_GIFT_SECS, tostring(adPendingScene_)))
                adFocusCleanupTimer_ = 0
                if focusLostDuration >= AD_FOCUS_TIMEOUT_GIFT_SECS then
                    -- 广告展示时间足够长，玩家大概率看完了，SDK 误报 failure → 赠送奖励
                    print(string.format("[AdManager] SDK failure but ad displayed %ds >= %ds, granting reward (focus_timeout_gift)",
                        focusLostDuration, AD_FOCUS_TIMEOUT_GIFT_SECS))
                    local savedScene2 = adPendingScene_
                    GameAlgoService.TrackAd(savedScene2)
                    resetAdState()
                    if sendActionFn_ and savedScene2 then
                        sendActionFn_(Protocol.ACTION_TYPES.AD_CONFIRM, { scene = savedScene2 })
                        adConfirmRetry_.active    = true
                        adConfirmRetry_.scene     = savedScene2
                        adConfirmRetry_.remaining = AD_CONFIRM_MAX_RETRIES
                        adConfirmRetry_.timer     = AD_CONFIRM_RETRY_DELAY
                    end
                    fireCallback(savedCallback, true, "focus_timeout_gift")
                else
                    -- 广告展示时间太短，SDK failure 可信 → 视为失败
                    print(string.format("[AdManager] SDK failure, ad only displayed %ds < %ds, denying reward",
                        focusLostDuration, AD_FOCUS_TIMEOUT_GIFT_SECS))
                    resetAdState()
                    fireCallback(savedCallback, false, "ad_too_short")
                end
            else
                -- 焦点未丢失（banner 类广告或直接失败）：SDK failure 可靠，直接报失败
                adFocusCleanupTimer_ = 0
                resetAdState()
                local msg = (resultType == "table" and result.msg) or "广告未完成"
                print("[AdManager] fireCallback: success=false reason=" .. tostring(msg))
                fireCallback(savedCallback, false, msg)
            end
        end
    end)
end

--- 每帧更新（在 HandleUpdate_Client 中调用）
---@param dt number 帧间隔（秒）
function AdManager.Update(dt)
    -- AD_CONFIRM 重试计时器（独立于主广告流程，不受 adLoading_ 影响）
    if adConfirmRetry_.active then
        adConfirmRetry_.timer = adConfirmRetry_.timer - dt
        if adConfirmRetry_.timer <= 0 then
            adConfirmRetry_.timer = AD_CONFIRM_RETRY_DELAY
            adConfirmRetry_.remaining = adConfirmRetry_.remaining - 1
            print(string.format("[AdManager] AD_CONFIRM retry: scene=%s remaining=%d",
                adConfirmRetry_.scene, adConfirmRetry_.remaining))
            if sendActionFn_ and adConfirmRetry_.scene then
                sendActionFn_(Protocol.ACTION_TYPES.AD_CONFIRM, { scene = adConfirmRetry_.scene })
            end
            if adConfirmRetry_.remaining <= 0 then
                print(string.format("[AdManager] AD_CONFIRM retry exhausted for scene=%s", adConfirmRetry_.scene))
                adConfirmRetry_.active = false
                adConfirmRetry_.scene  = nil
            end
        end
    end

    if not adLoading_ then return end
    if adCallbackFired_ then return end

    -- 🔴 绝对兜底超时：防止焦点丢失清零 adLoadingTimer_ 后无退出路径导致永久卡死
    -- 场景：SDK 抢焦点（adLoadingTimer_=0）但既不恢复焦点也不回调 → 两个倒计时都是0，死锁
    if adShowStartTime_ > 0 then
        local absoluteElapsed = os.time() - adShowStartTime_
        if absoluteElapsed >= AD_ABSOLUTE_TIMEOUT_SECS then
            print(string.format("[AdManager] ABSOLUTE TIMEOUT: %ds >= %ds, force terminating ad. scene=%s focusLost=%d loadTimer=%.1f focusTimer=%.1f responded=%s",
                absoluteElapsed, AD_ABSOLUTE_TIMEOUT_SECS, tostring(adPendingScene_),
                adFocusLostAt_, adLoadingTimer_, adFocusCleanupTimer_, tostring(adSdkEverResponded_)))
            adCallbackFired_     = true
            adFocusCleanupTimer_ = 0
            adLoadingTimer_      = 0
            local savedCallback  = adPendingCallback_
            local savedScene     = adPendingScene_
            if adSdkEverResponded_ or (adFocusLostAt_ > 0 and (os.time() - adFocusLostAt_) >= AD_FOCUS_TIMEOUT_GIFT_SECS) then
                -- 后台超过 120 秒，连接几乎必定已死。
                -- 不发 AD_CONFIRM（发也到不了），不弹奖励面板（避免假阳性）。
                -- 依赖 serverCloud 中已持久化的 adPending，重连后由 crash recovery 自动结算。
                print(string.format("[AdManager] absolute timeout → deferring reward to crash recovery (responded=%s focusDuration=%ds)",
                    tostring(adSdkEverResponded_), adFocusLostAt_ > 0 and (os.time() - adFocusLostAt_) or 0))
                resetAdState()
                -- 启动重试（重连后 RetryNow 会触发，或 crash recovery 触发）
                if sendActionFn_ and savedScene then
                    adConfirmRetry_.active    = true
                    adConfirmRetry_.scene     = savedScene
                    adConfirmRetry_.remaining = AD_CONFIRM_MAX_RETRIES
                    adConfirmRetry_.timer     = AD_CONFIRM_RETRY_DELAY
                end
                -- 不弹奖励面板，回调 "pending"：通知上层奖励待同步，不是失败
                fireCallback(savedCallback, true, "absolute_timeout_deferred")
            else
                -- SDK 从未回调且焦点未长时间丢失 → 视为加载失败
                print("[AdManager] absolute timeout → denying reward (no evidence of ad display)")
                resetAdState()
                fireCallback(savedCallback, false, "absolute_timeout")
            end
            return
        end
    end

    -- 焦点清理计时器（焦点恢复后启动）
    if adFocusCleanupTimer_ > 0 then
        adFocusCleanupTimer_ = adFocusCleanupTimer_ - dt
        if adFocusCleanupTimer_ <= 0 then
            adFocusCleanupTimer_ = 0
            adCallbackFired_ = true
            adLoadingTimer_  = 0

            -- 计算广告展示时长
            -- 优先用 focusLostAt（精确），如果焦点事件未触发则用 adShowStartTime_ 兜底
            local focusLostDuration
            if adFocusLostAt_ > 0 then
                focusLostDuration = os.time() - adFocusLostAt_
            elseif adShowStartTime_ > 0 then
                -- 焦点事件未触发（overlay 类广告），用广告发起时间作 fallback
                focusLostDuration = os.time() - adShowStartTime_
            else
                focusLostDuration = 0
            end

            print(string.format("[AdManager] focus cleanup timeout, SDK did not callback, scene=%s responded=%s focusLostDuration=%ds threshold=%ds focusLostAt=%d showStart=%d",
                tostring(adPendingScene_), tostring(adSdkEverResponded_), focusLostDuration, AD_FOCUS_TIMEOUT_GIFT_SECS,
                adFocusLostAt_, adShowStartTime_))

            local savedCallback = adPendingCallback_

            if focusLostDuration >= AD_FOCUS_TIMEOUT_GIFT_SECS then
                -- 广告展示时间足够长（≥15秒），玩家大概率看完了广告
                -- SDK 回调或 JS-bridge 延迟未在 8 秒内到达，赠送奖励保障体验
                print(string.format("[AdManager] focus_timeout_gift: ad displayed %ds >= %ds, granting reward scene=%s",
                    focusLostDuration, AD_FOCUS_TIMEOUT_GIFT_SECS, tostring(adPendingScene_)))
                local savedScene = adPendingScene_
                resetAdState()
                -- 通知服务端：广告因焦点超时赠送奖励
                if sendActionFn_ and savedScene then
                    sendActionFn_(Protocol.ACTION_TYPES.AD_CONFIRM, { scene = savedScene })
                    adConfirmRetry_.active    = true
                    adConfirmRetry_.scene     = savedScene
                    adConfirmRetry_.remaining = AD_CONFIRM_MAX_RETRIES
                    adConfirmRetry_.timer     = AD_CONFIRM_RETRY_DELAY
                end
                fireCallback(savedCallback, true, "focus_timeout_gift")
            else
                -- 广告展示时间太短（<15秒），玩家可能快速切回未完整观看
                -- 视为广告失败，不赠送奖励
                print(string.format("[AdManager] focus_timeout_fail: ad displayed %ds < %ds, denying reward scene=%s",
                    focusLostDuration, AD_FOCUS_TIMEOUT_GIFT_SECS, tostring(adPendingScene_)))
                resetAdState()
                fireCallback(savedCallback, false, "focus_timeout")
            end
        else
            -- 每秒打印一次剩余时间（倒计时整秒跳变时触发）
            local remaining = math.ceil(adFocusCleanupTimer_)
            if math.ceil(adFocusCleanupTimer_ + dt) ~= remaining then
                print(string.format("[AdManager] focus cleanup countdown: %.0fs left, scene=%s",
                    remaining, tostring(adPendingScene_)))
            end
        end
        return  -- 焦点清理倒计时期间不跑加载超时逻辑
    end

    -- 加载超时计时器（SDK 调用后立即启动）
    if adLoadingTimer_ > 0 then
        adLoadingTimer_ = adLoadingTimer_ - dt
        if adLoadingTimer_ <= 0 then
            adLoadingTimer_ = 0
            adCallbackFired_     = true
            adFocusCleanupTimer_ = 0
            local savedCallback  = adPendingCallback_
            if adSdkEverResponded_ then
                -- SDK 曾真实回调过（广告展示后无结果）→ 赠送奖励保障体验
                print(string.format("[AdManager] loading timeout: gifting reward scene=%s (SDK had responded)",
                    tostring(adPendingScene_)))
                local savedScene = adPendingScene_
                resetAdState()
                -- 通知服务端：广告因加载超时赠送奖励
                if sendActionFn_ and savedScene then
                    sendActionFn_(Protocol.ACTION_TYPES.AD_CONFIRM, { scene = savedScene })
                end
                fireCallback(savedCallback, true, "timeout_gift")
            else
                -- SDK 从未回调（广告被静默丢弃，玩家根本没看到广告）→ 视为失败
                print(string.format("[AdManager] loading timeout: SDK never responded (silently dropped) scene=%s",
                    tostring(adPendingScene_)))
                resetAdState()
                fireCallback(savedCallback, false, "sdk_no_response")
            end
        else
            -- 每 10 秒打印一次加载倒计时（减少日志量）
            local elapsed = AD_LOADING_TIMEOUT_SECS - adLoadingTimer_
            if math.floor(elapsed) % 10 == 0 and math.floor(elapsed - dt) % 10 ~= 0 then
                print(string.format("[AdManager] loading timer: %.0fs elapsed / %.0fs total, responded=%s, scene=%s",
                    elapsed, AD_LOADING_TIMEOUT_SECS, tostring(adSdkEverResponded_), tostring(adPendingScene_)))
            end
        end
    end
end

--- 焦点变化通知（在 HandleInputFocus_Client 中调用）
---@param hasFocus boolean true = 获得焦点，false = 失去焦点
function AdManager.OnFocusChange(hasFocus)
    if not adLoading_ then return end

    if not hasFocus then
        -- 失焦（切后台或广告弹出）：暂停加载超时倒计时，记录失焦时刻
        adLoadingTimer_ = 0
        adFocusLostAt_  = os.time()
        print("[AdManager] focus lost during ad, pausing loading timer, scene="
            .. tostring(adPendingScene_))
    else
        -- 获焦（广告关闭或切回前台）
        if not adCallbackFired_ then
            -- SDK 还没回调：启动 8 秒焦点清理安全网
            adFocusCleanupTimer_ = AD_FOCUS_CLEANUP_SECS
            print(string.format("[AdManager] focus restored, SDK may have already called back, starting %ds cleanup timer, focusLostDuration=%ds, scene=%s",
                AD_FOCUS_CLEANUP_SECS,
                (adFocusLostAt_ > 0) and (os.time() - adFocusLostAt_) or 0,
                tostring(adPendingScene_)))
        end
    end
end

--- 重连恢复：服务端推送 adPending 模块数据后调用
--- 如果 pending 标记存在且经过时间 >= CRASH_MIN_ELAPSED_SECS，自动发 AD_CONFIRM 触发补偿
--- 低于阈值说明可能是玩家主动退出（而非崩溃/进程被杀），不予自动补偿
---@param data table|false|nil  服务端推送的 adPending 模块数据
function AdManager.OnAdPendingReceived(data)
    -- data == false 或 nil 表示无 pending 标记（正常状态）
    if not data or data == false then
        print("[AdManager] OnAdPendingReceived: no pending marker (normal)")
        return
    end

    -- ð´ FIX: 如果当前正在展示广告，不执行崩溃补偿
    -- 场景：断线重连（非崩溃），Lua 状态保留，玩家可能正在看新广告
    -- 此时不应打断当前广告流程；当前广告结束后服务端 pending 会被正确处理
    if adLoading_ then
        print("[AdManager] OnAdPendingReceived: ad currently loading, skip crash recovery (will be handled by current ad flow)")
        return
    end

    local elapsed = data.elapsed or 0
    local scene   = data.scene or "unknown"

    print(string.format("[AdManager] OnAdPendingReceived: scene=%s elapsed=%ds threshold=%ds",
        scene, elapsed, CRASH_MIN_ELAPSED_SECS))

    if elapsed >= CRASH_MIN_ELAPSED_SECS and scene then
        -- 经过时间足够长，判定为崩溃/进程被杀，自动确认广告完成
        print(string.format("[AdManager] crash recovery: auto-confirming ad scene=%s (elapsed %ds >= %ds)",
            scene, elapsed, CRASH_MIN_ELAPSED_SECS))

        if sendActionFn_ then
            sendActionFn_(Protocol.ACTION_TYPES.AD_CONFIRM, { scene = scene })
        end
    else
        -- 经过时间太短，可能是玩家主动退出，不予补偿
        print(string.format("[AdManager] crash recovery SKIPPED: elapsed %ds < %ds, scene=%s",
            elapsed, CRASH_MIN_ELAPSED_SECS, scene))
    end
end

--- AD_CONFIRM ActionResult 回调（由 ClientMessageHandler 分发）
--- 失败时启动延时重试，成功时停止重试
---@param data table  { action, success, reason, scene }
function AdManager.OnAdConfirmResult(data)
    if data.success then
        if data.scene == "privilege" and data.privilege then
            local okMP, MarketPage = pcall(require, "ui.MarketPage")
            if okMP and MarketPage and MarketPage.setPrivilegeData then
                MarketPage.setPrivilegeData(data.privilege)
            end
        end
        -- 成功：如果有活跃重试则停止
        if adConfirmRetry_.active then
            print(string.format("[AdManager] AD_CONFIRM succeeded on retry, stopping retry scene=%s",
                adConfirmRetry_.scene))
            adConfirmRetry_.active = false
            adConfirmRetry_.scene  = nil
        end
        return
    end

    -- 失败：启动重试（如果尚未在重试中）
    local scene = data.scene or (data.params and data.params.scene)
    if not scene then
        print("[AdManager] AD_CONFIRM failed but no scene in response, cannot retry")
        return
    end

    -- 服务端无 pending：通常表示之前的 AD_CONFIRM 已成功结算并清标记，
    -- 或重连补偿已经处理。按幂等成功收敛，避免在弱网/鸿蒙回前台场景无限重试。
    if data.reason == "no_pending" then
        print(string.format("[AdManager] AD_CONFIRM no_pending treated as settled, stopping retry scene=%s", tostring(scene)))
        adConfirmRetry_.active = false
        adConfirmRetry_.scene  = nil
        return
    end

    -- 已在重试中则不重复启动
    if adConfirmRetry_.active then
        print(string.format("[AdManager] AD_CONFIRM failed again (retry active), remaining=%d scene=%s reason=%s",
            adConfirmRetry_.remaining, scene, tostring(data.reason)))
        return
    end

    print(string.format("[AdManager] AD_CONFIRM failed, starting retry: scene=%s reason=%s maxRetries=%d delay=%.1fs",
        scene, tostring(data.reason), AD_CONFIRM_MAX_RETRIES, AD_CONFIRM_RETRY_DELAY))
    adConfirmRetry_.active    = true
    adConfirmRetry_.scene     = scene
    adConfirmRetry_.remaining = AD_CONFIRM_MAX_RETRIES
    adConfirmRetry_.timer     = AD_CONFIRM_RETRY_DELAY
end

--- 断线时清理广告中间态，避免 adLoading_ 卡死导致重连后无法发起新广告
function AdManager.OnServerDisconnect()
    if adLoading_ or adPendingScene_ then
        print(string.format("[AdManager] OnServerDisconnect: clearing ad state scene=%s loading=%s",
            tostring(adPendingScene_), tostring(adLoading_)))
    end
    resetAdState()
end

--- 网络重连后立即重试（由 Client.lua 在重连成功时调用）
--- 利用新建立的活连接立即发送之前失败的 AD_CONFIRM
function AdManager.RetryNow()
    if adConfirmRetry_.active and adConfirmRetry_.scene then
        print(string.format("[AdManager] RetryNow: immediately retrying AD_CONFIRM on new connection, scene=%s remaining=%d",
            adConfirmRetry_.scene, adConfirmRetry_.remaining))
        if sendActionFn_ then
            sendActionFn_(Protocol.ACTION_TYPES.AD_CONFIRM, { scene = adConfirmRetry_.scene })
        end
        -- 重置计时器，给新连接充足时间
        adConfirmRetry_.timer = AD_CONFIRM_RETRY_DELAY
    end
end

return AdManager
