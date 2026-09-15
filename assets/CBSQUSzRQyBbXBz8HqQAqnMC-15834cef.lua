---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- SignInConfig - 签到奖励配置（双端共享）
-- 职责: 定义每周/每日签到的奖励表、补签消耗
-- 运行端: shared（服务端 + 客户端都加载）
-- ============================================================================

local SignInConfig = {}

--- 补签消耗钻石数
SignInConfig.RETRO_COST = 120

--- 每周签到奖励配置（7天循环）
SignInConfig.WEEKLY_REWARDS = {
    { type = "diamond",          amount = 432 },
    { type = "sweep_ticket",     amount = 1   },
    { type = "adventure_ticket", amount = 1   },
    { type = "diamond",          amount = 582 },
    { type = "golden_key",       amount = 5   },
    { type = "enhance_star",     amount = 6   },
    { type = "stellar_ticket",   amount = 5   },
}

--- 每日签到奖励配置（30天循环）
SignInConfig.DAILY_REWARDS = {
    { type = "diamond",          amount = 432  },
    { type = "diamond",          amount = 582  },
    { type = "adventure_ticket", amount = 10   },
    { type = "enhance_star",     amount = 8    },
    { type = "golden_key",       amount = 2    },
    { type = "privilege_point",  amount = 2    },
    { type = "adventure_ticket", amount = 10   },
    { type = "diamond",          amount = 432  },
    { type = "diamond",          amount = 582  },
    { type = "stellar_ticket",   amount = 2    },
    { type = "diamond",          amount = 582  },
    { type = "sweep_ticket",     amount = 4    },
    { type = "diamond",          amount = 882  },
    { type = "adventure_ticket", amount = 10   },
    { type = "golden_key",       amount = 3    },
    { type = "diamond",          amount = 582  },
    { type = "enhance_star",     amount = 8    },
    { type = "privilege_point",  amount = 3    },
    { type = "sweep_ticket",     amount = 5    },
    { type = "stellar_ticket",   amount = 3    },
    { type = "diamond",          amount = 582  },
    { type = "privilege_point",  amount = 3    },
    { type = "adventure_ticket", amount = 3    },
    { type = "golden_key",       amount = 5    },
    { type = "sweep_ticket",     amount = 4    },
    { type = "stellar_ticket",   amount = 5    },
    { type = "break_protect",    amount = 5    },
    { type = "adventure_ticket", amount = 20   },
    { type = "privilege_point",  amount = 5    },
    { type = "stellar_ticket",   amount = 10   },
}

--- 资源 type → currency 模块字段名映射
--- 服务端发放奖励时使用
SignInConfig.REWARD_TO_CURRENCY = {
    gold              = "gold",
    diamond           = "gems",
    essence           = "essence",
    enhance_star      = "enhanceStone",
    degrade_protect   = "degradeStone",
    break_protect     = "destroyStone",
    adventure_ticket  = "recruitTicket",
    stellar_ticket    = "stellarRecruitTicket",
    golden_key        = "goldenKey",
    corrupt_stone     = "corruptStone",
    sacred_stone      = "sacredStone",
    sweep_ticket      = "sweepTicket",
    arena_ticket      = "arenaTicket",
    arena_coin        = "arenaCoin",
    tavern_coin       = "tavernCoin",
    privilege_point   = "privilegePoint",
}

--- 获取当天编号（UTC+8，自 epoch 以来的天数）
---@return number
function SignInConfig.getDayNumber()
    return math.floor((os.time() + 28800) / 86400)
end

--- 获取当前周编号（UTC+8，自 epoch 以来的周数，周一为起始）
---@return number
function SignInConfig.getWeekNumber()
    -- epoch (1970-01-01) 是周四，偏移 3 天让周一为起始
    return math.floor((os.time() + 28800 + 3 * 86400) / (7 * 86400))
end

--- 获取当月编号（UTC+8，年*12+月）
---@return number
function SignInConfig.getMonthNumber()
    local t = os.date("!*t", os.time() + 28800)
    return t.year * 12 + t.month
end

--- 获取今天在本月中的天数（1-31）
---@return number
function SignInConfig.getDayOfMonth()
    local t = os.date("!*t", os.time() + 28800)
    return t.day --[[@as number]]
end

--- 获取开服日期距今经过的完整天数（以 UTC+8 凌晨为日界线）
--- 周期编号和天数都基于此函数，保证刷新时间统一为凌晨 0 点
---@param openTime number UTC 时间戳（os.time 格式）
---@return number 经过的完整天数（0=开服当天）
local function getElapsedDays(openTime)
    local nowDay  = math.floor((os.time() + 28800) / 86400)       -- 今天的日编号（UTC+8）
    local openDay = math.floor((openTime + 28800) / 86400)        -- 开服那天的日编号（UTC+8）
    return math.max(0, nowDay - openDay)
end

--- 获取每周签到周期编号（与 getDayOfWeek/getWeeklyRemainSeconds 同源）
--- openTime>0 时按开服日期起算 7 天游周期；openTime<=0 时退回自然周
---@param openTime number|nil 开服时间戳
---@return number
function SignInConfig.getWeeklyPeriodId(openTime)
    if not openTime or openTime <= 0 then
        return SignInConfig.getWeekNumber()
    end
    local days = getElapsedDays(openTime)
    return math.floor(days / 7)
end

--- 获取今天是每周签到周期内第几天（1-7，基于开服时间的7天循环）
--- 刷新时间: 每日凌晨 0 点（UTC+8）
---@param openTime number|nil 开服时间戳，0 或 nil 退回自然周
---@return number 1-7
function SignInConfig.getDayOfWeek(openTime)
    if not openTime or openTime <= 0 then
        -- fallback: 自然周
        local t = os.date("!*t", os.time() + 28800)
        local wd = t.wday
        return wd == 1 and 7 or (wd - 1)
    end
    local days = getElapsedDays(openTime)
    return days % 7 + 1
end

--- 获取每周签到活动剩余秒数（基于开服时间的7天循环）
---@param openTime number|nil 开服时间戳，0 或 nil 退回自然周
---@return number 剩余秒数
function SignInConfig.getWeeklyRemainSeconds(openTime)
    if not openTime or openTime <= 0 then
        -- fallback: 自然周
        local now = os.time() + 28800
        local t = os.date("!*t", now)
        local dayOfWeek = t.wday == 1 and 7 or (t.wday - 1)
        local daysLeft = 7 - dayOfWeek
        local todayRemain = (23 - t.hour) * 3600 + (59 - t.min) * 60 + (59 - t.sec)
        return daysLeft * 86400 + todayRemain
    end
    local days = getElapsedDays(openTime)
    local dayInWeek = days % 7 + 1  -- 1-7
    local daysLeft = 7 - dayInWeek  -- 本周期内剩余整天
    -- 今天剩余秒数（距 UTC+8 凌晨）
    local now = os.time() + 28800
    local t = os.date("!*t", now)
    local todayRemain = (23 - t.hour) * 3600 + (59 - t.min) * 60 + (59 - t.sec)
    return daysLeft * 86400 + todayRemain
end

--- 获取每日签到（月度）活动剩余秒数（距离本月末 23:59:59 UTC+8）
---@return number 剩余秒数
function SignInConfig.getDailyRemainSeconds()
    local now = os.time() + 28800  -- UTC+8 timestamp
    local t = os.date("!*t", now)
    -- 计算本月总天数
    local year, month = t.year, t.month
    local nextMonth = month == 12 and os.time({ year = year + 1, month = 1, day = 1 })
                                   or os.time({ year = year, month = month + 1, day = 1 })
    local daysInMonth = math.floor((nextMonth - os.time({ year = year, month = month, day = 1 })) / 86400)
    local daysLeft = daysInMonth - t.day  -- 距月末还有几天
    local todayRemain = (23 - t.hour) * 3600 + (59 - t.min) * 60 + (59 - t.sec)
    return daysLeft * 86400 + todayRemain
end

--- 将秒数格式化为 "X天Y时" 格式
---@param seconds number
---@return string
function SignInConfig.formatRemainTime(seconds)
    local s = math.max(0, math.floor(seconds))
    local days = math.floor(s / 86400)
    local hours = math.floor((s % 86400) / 3600)
    return days .. "天" .. hours .. "时"
end

--- 以开服时间为基准获取当前 30 天签到周期编号（openTime<=0 退回自然月）
--- 刷新时间: 每日凌晨 0 点（UTC+8）
---@param openTime number UTC 时间戳（os.time 格式），0 或 nil 表示未设置
---@return number 周期编号（0 起始）
function SignInConfig.getServerPeriodId(openTime)
    if not openTime or openTime <= 0 then
        return SignInConfig.getMonthNumber()
    end
    local days = getElapsedDays(openTime)
    return math.floor(days / 30)
end

--- 以开服时间为基准获取当前周期内第几天（1-30，openTime<=0 退回自然月当天）
--- 刷新时间: 每日凌晨 0 点（UTC+8）
---@param openTime number UTC 时间戳（os.time 格式），0 或 nil 表示未设置
---@return number 天数（1-30）
function SignInConfig.getDayOfServerPeriod(openTime)
    if not openTime or openTime <= 0 then
        return math.min(SignInConfig.getDayOfMonth(), 30)
    end
    local days = getElapsedDays(openTime)
    return days % 30 + 1
end

--- 以开服时间为基准获取当前周期剩余秒数（openTime<=0 退回自然月剩余）
---@param openTime number UTC 时间戳（os.time 格式），0 或 nil 表示未设置
---@return number 剩余秒数
function SignInConfig.getServerPeriodRemainSeconds(openTime)
    if not openTime or openTime <= 0 then
        return SignInConfig.getDailyRemainSeconds()
    end
    local days = getElapsedDays(openTime)
    local remainDaysInPeriod = 29 - (days % 30)  -- 本周期内剩余天数
    -- 今天剩余秒数（距凌晨）
    local now = os.time() + 28800
    local todayRemain = 86400 - (now % 86400)
    return remainDaysInPeriod * 86400 + todayRemain
end

return SignInConfig
