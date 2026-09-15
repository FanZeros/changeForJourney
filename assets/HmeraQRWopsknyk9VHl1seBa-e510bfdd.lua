-- ============================================================================
-- SignInService - 签到业务逻辑
-- 职责: 每周/每日/补签校验与奖励发放（纯业务，禁止网络 IO）
-- 层级: server/signin  |  通过 PDM 读写数据
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local SignInConfig    = require("shared.signin.SignInConfig")
local SigninSchema    = require("shared.signin.SigninSchema")
local CurrencyService = require("server.currency.CurrencyService")
local SaveManager     = require("server.SaveManager")
local ServerListConfig = require("shared.ServerListConfig")

local SignInService = {}

-- ======================== 内部工具：获取玩家所在服的开服时间 ========================

---@param uid number
---@return number openTime 开服 UTC 时间戳，0 表示未配置
local function getOpenTime(uid)
    local sid = SaveManager.getServerId(uid)
    if not sid then return 0 end
    local cfg = ServerListConfig.find(sid)
    if not cfg then return 0 end
    local ot = cfg.openTime or 0

    -- 🔴 修复: openTime=0 表示"服务器已开放(无固定开服日)"
    -- 此时签到周期应以玩家首次登录时间为基准，而不是回退到自然月日期
    if ot <= 0 then
        local sessionData = PDM.GetModule(uid, "session")
        if sessionData and (sessionData.firstLoginTime or 0) > 0 then
            ot = sessionData.firstLoginTime
        end
        -- 如果 firstLoginTime 也为 0（玩家还没完成首次登录），保持 ot=0
        -- SignInConfig 会 fallback 到自然月，但这种情况极少发生（进入签到前必然已完成首登）
    end

    return ot
end

---@param t table|nil
---@return boolean
local function hasAnyEntry(t)
    if type(t) ~= "table" then return false end
    return next(t) ~= nil
end

---@param signin table
---@return boolean
local function hasLegacySignInProgress(signin)
    return (tonumber(signin.weekId) or 0) > 0
        or (tonumber(signin.monthId) or 0) > 0
        or hasAnyEntry(signin.weeklyClaimed)
        or hasAnyEntry(signin.dailyClaimed)
end

-- ======================== 内部工具 ========================

--- 检查并重置过期的签到周期
---@param signin table 签到模块数据
---@param openTime number 开服 UTC 时间戳（0 退回自然月）
---@return boolean dirty
local function ensurePeriods(signin, openTime)
    local curWeek   = SignInConfig.getWeeklyPeriodId(openTime)
    local curPeriod = SignInConfig.getServerPeriodId(openTime)
    local rewardVersion = SigninSchema.REWARD_VERSION or 1
    local dirty = false

    if (tonumber(signin.rewardVersion) or 0) < rewardVersion then
        local isLegacyPlayer = hasLegacySignInProgress(signin)
        signin.rewardVersion = rewardVersion
        if isLegacyPlayer then
            signin.weekId        = curWeek
            signin.monthId       = curPeriod
            signin.weeklyClaimed = {}
            signin.dailyClaimed  = {}
        end
        return true
    end

    if signin.weekId ~= curWeek then
        signin.weekId        = curWeek
        signin.weeklyClaimed = {}
        dirty = true
    end
    if signin.monthId ~= curPeriod then
        signin.monthId      = curPeriod
        signin.dailyClaimed = {}
        dirty = true
    end
    return dirty
end

--- 发放奖励（委托 CurrencyService.GrantReward，单一映射源）
---@param uid number
---@param reward table { type, amount }
---@return boolean
local function grantReward(uid, reward)
    return CurrencyService.GrantReward(uid, reward)
end

-- ======================== 每周签到 ========================

---@param uid number
---@return boolean ok
---@return string|nil errReason
---@return table|nil result { day, reward }
function SignInService.WeeklySign(uid)
    local signin = PDM.GetModule(uid, "signin")
    if not signin then return false, "no_data" end

    local openTime = getOpenTime(uid)
    ensurePeriods(signin, openTime)

    local dayOfWeek = SignInConfig.getDayOfWeek(openTime)  -- 1-7（基于开服时间）

    if signin.weeklyClaimed[dayOfWeek] then
        return false, "already_claimed"
    end

    -- 限额校验（服务端防刷）
    -- weeklyClaimed 是唯一事实源；quota 是二次保险（同 DailySign 逻辑）。
    local quotaOk, quotaErr = PDM.UseQuota(uid, "weekly_signin", 1)
    if not quotaOk and quotaErr == "quota_exceeded" then
        print("[SignIn] WeeklySign quota_exceeded but weeklyClaimed[" .. dayOfWeek
            .. "]=nil for uid=" .. tostring(uid) .. ", overriding quota (claimed is truth)")
        PDM.RefreshQuota(uid, "weekly_signin", nil)
    elseif not quotaOk then
        return false, quotaErr
    end

    local reward = SignInConfig.WEEKLY_REWARDS[dayOfWeek]
    if not reward then
        return false, "invalid_day"
    end

    signin.weeklyClaimed[dayOfWeek] = true
    PDM.MarkDirty(uid, "signin")

    grantReward(uid, reward)

    return true, nil, { day = dayOfWeek, reward = reward }
end

-- ======================== 每日签到 ========================

---@param uid number
---@return boolean ok
---@return string|nil errReason
---@return table|nil result { day, reward }
function SignInService.DailySign(uid)
    local signin = PDM.GetModule(uid, "signin")
    if not signin then return false, "no_data" end

    local openTime = getOpenTime(uid)
    ensurePeriods(signin, openTime)

    local dayOfPeriod = SignInConfig.getDayOfServerPeriod(openTime)  -- 1-30，已保证不超 30

    if signin.dailyClaimed[dayOfPeriod] then
        return false, "already_claimed"
    end

    -- 限额校验（服务端防刷）
    -- dailyClaimed 是唯一事实源；quota 是二次保险。
    -- 如果 quota 说超限但 dailyClaimed 没标记过，说明 quota 与业务状态不一致
    -- （可能是上次 quota 消耗后 claimed 未持久化，或 quota 重置时间差异），
    -- 此时信任 dailyClaimed，跳过 quota 限制并异步刷新 quota 缓存。
    local quotaOk, quotaErr = PDM.UseQuota(uid, "daily_signin", 1)
    if not quotaOk and quotaErr == "quota_exceeded" then
        print("[SignIn] DailySign quota_exceeded but dailyClaimed[" .. dayOfPeriod
            .. "]=nil for uid=" .. tostring(uid) .. ", overriding quota (claimed is truth)")
        -- 异步刷新 quota 缓存，修正脏数据（不阻塞本次签到）
        PDM.RefreshQuota(uid, "daily_signin", nil)
        -- 不拦截，继续发放奖励
    elseif not quotaOk then
        return false, quotaErr
    end

    local reward = SignInConfig.DAILY_REWARDS[dayOfPeriod]
    if not reward then
        return false, "invalid_day"
    end

    signin.dailyClaimed[dayOfPeriod] = true
    PDM.MarkDirty(uid, "signin")

    grantReward(uid, reward)

    return true, nil, { day = dayOfPeriod, reward = reward }
end

-- ======================== 补签（消耗钻石） ========================

---@param uid number
---@param source string "weekly" | "daily"
---@param day number
---@return boolean ok
---@return string|nil errReason
---@return table|nil result { source, day, reward, cost }
function SignInService.RetroSign(uid, source, day)
    if not source or not day then
        return false, "invalid_params"
    end

    local signin = PDM.GetModule(uid, "signin")
    if not signin then return false, "no_data" end

    local openTime = getOpenTime(uid)
    ensurePeriods(signin, openTime)

    -- 检查钻石是否足够
    local cost = SignInConfig.RETRO_COST
    local hasBalance, _ = CurrencyService.CheckBalance(uid, "gems", cost)
    if not hasBalance then
        return false, "not_enough_gems"
    end

    local reward
    if source == "weekly" then
        if day < 1 or day > 7 then
            return false, "invalid_day"
        end
        if signin.weeklyClaimed[day] then
            return false, "already_claimed"
        end
        local dayOfWeek = SignInConfig.getDayOfWeek(openTime)
        if day >= dayOfWeek then
            return false, "cannot_retro_future"
        end
        reward = SignInConfig.WEEKLY_REWARDS[day]
        if not reward then return false, "invalid_day" end
        signin.weeklyClaimed[day] = true
    elseif source == "daily" then
        if day < 1 or day > 30 then
            return false, "invalid_day"
        end
        if signin.dailyClaimed[day] then
            return false, "already_claimed"
        end
        local curDay = SignInConfig.getDayOfServerPeriod(openTime)
        if day >= curDay then
            return false, "cannot_retro_future"
        end
        reward = SignInConfig.DAILY_REWARDS[day]
        if not reward then return false, "invalid_day" end
        signin.dailyClaimed[day] = true
    else
        return false, "invalid_source"
    end

    -- 扣除钻石（必须检查返回值，Deduct 可能因数据异常失败）
    local deducted, newBalance = CurrencyService.Deduct(uid, "gems", cost)
    if not deducted then
        return false, "not_enough_gems"
    end
    PDM.MarkDirty(uid, "signin")

    -- 发放奖励
    grantReward(uid, reward)

    return true, nil, {
        source = source,
        day    = day,
        reward = reward,
        cost   = cost,
    }
end

-- ======================== 查询/刷新签到状态 ========================

--- 检查周期是否过期并重置，有变化时 MarkDirty（确保客户端拿到最新数据）
---@param uid number
---@return boolean ok
---@return string|nil errReason
function SignInService.RefreshAndGet(uid)
    local signin = PDM.GetModule(uid, "signin")
    if not signin then return false, "no_data" end

    local openTime = getOpenTime(uid)
    local oldWeekId = signin.weekId
    local oldMonthId = signin.monthId
    local oldRewardVersion = tonumber(signin.rewardVersion) or 0
    local dirty = ensurePeriods(signin, openTime)

    if dirty then
        PDM.MarkDirty(uid, "signin")
        if oldRewardVersion < (SigninSchema.REWARD_VERSION or 1) then
            print("[SignIn] RefreshAndGet: 签到奖励版本升级，当前周期可重新领取/补签 uid=" .. tostring(uid)
                .. " oldVersion=" .. tostring(oldRewardVersion)
                .. " newVersion=" .. tostring(SigninSchema.REWARD_VERSION))
        else
            if oldWeekId ~= signin.weekId then
                print("[SignIn] RefreshAndGet: 每周签到已重置 uid=" .. tostring(uid)
                    .. " newWeek=" .. tostring(signin.weekId))
            end
            if oldMonthId ~= signin.monthId then
                print("[SignIn] RefreshAndGet: 每日签到已重置 uid=" .. tostring(uid)
                    .. " newPeriod=" .. tostring(signin.monthId))
            end
        end
    end

    return true
end

return SignInService
