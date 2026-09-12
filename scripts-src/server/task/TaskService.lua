-- ============================================================================
-- TaskService - 任务系统业务逻辑
-- 职责: 周期重置、进度追踪、奖励发放、成就刷新（纯业务，禁止网络 IO）
-- 层级: server/task  |  通过 PDM 读写数据
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local TaskConfig      = require("config.TaskConfig")
local CurrencyService = require("server.currency.CurrencyService")

local TaskService = {}

-- ======================== 内部工具 ========================

--- 检查并重置过期的日/周任务进度
---@param taskData table task 模块数据
local function ensurePeriods(taskData)
    local curDay  = TaskConfig.getDayNumber()
    local curWeek = TaskConfig.getWeekNumber()

    if taskData.dayId ~= curDay then
        taskData.dayId        = curDay
        taskData.dailyProg    = {}
        taskData.dailyClaimed = {}
    end

    if taskData.weekId ~= curWeek then
        taskData.weekId        = curWeek
        taskData.weeklyProg    = {}
        taskData.weeklyClaimed = {}
        taskData._weekLoginDays = {}
    end
end

-- ======================== 领取任务奖励 ========================

--- 领取指定任务的奖励
---@param uid number
---@param taskId string
---@return boolean, string|nil, table|nil
function TaskService.ClaimTask(uid, taskId)
    if not taskId or type(taskId) ~= "string" then
        return false, "invalid_params"
    end

    local taskDef = TaskConfig.findById(taskId)
    if not taskDef then
        return false, "unknown_task"
    end

    local category = TaskConfig.getCategory(taskId)
    if not category then
        return false, "unknown_category"
    end

    local taskData = PDM.GetModule(uid, "task")
    if not taskData then
        return false, "no_data"
    end

    ensurePeriods(taskData)

    -- 选择对应的进度表和领取表
    local progTable, claimedTable
    if category == "daily" then
        progTable    = taskData.dailyProg
        claimedTable = taskData.dailyClaimed
    elseif category == "weekly" then
        progTable    = taskData.weeklyProg
        claimedTable = taskData.weeklyClaimed
    else -- achievement
        progTable    = taskData.achProg
        claimedTable = taskData.achClaimed
    end

    if claimedTable[taskId] then
        return false, "already_claimed"
    end

    local current = progTable[taskDef.condKey] or 0
    if current < taskDef.target then
        return false, "not_complete"
    end

    -- 标记已领取
    claimedTable[taskId] = true
    PDM.MarkDirty(uid, "task")

    -- 发放奖励
    CurrencyService.GrantReward(uid, taskDef.reward)

    print("[TaskService] ClaimTask uid=" .. tostring(uid)
        .. " taskId=" .. taskId
        .. " reward=" .. taskDef.reward.type .. "×" .. taskDef.reward.amount)

    return true, nil, {
        taskId = taskId,
        reward = taskDef.reward,
    }
end

-- ======================== 进度更新（供其他 Service/Handler 调用） ========================

--- 增量更新指定 condKey 的进度（日任务 + 周任务 + 成就）
---@param uid number
---@param condKey string  进度追踪 key（如 "enhance", "decompose", "recruit"）
---@param delta number    增量值（默认 1）
function TaskService.UpdateProgress(uid, condKey, delta)
    delta = delta or 1
    local taskData = PDM.GetModule(uid, "task")
    if not taskData then return end

    ensurePeriods(taskData)

    -- 日任务进度
    local hasDailyCond = false
    for _, t in ipairs(TaskConfig.DAILY) do
        if t.condKey == condKey then hasDailyCond = true; break end
    end
    if hasDailyCond then
        taskData.dailyProg[condKey] = (taskData.dailyProg[condKey] or 0) + delta
    end

    -- 周任务进度
    local hasWeeklyCond = false
    for _, t in ipairs(TaskConfig.WEEKLY) do
        if t.condKey == condKey then hasWeeklyCond = true; break end
    end
    if hasWeeklyCond then
        taskData.weeklyProg[condKey] = (taskData.weeklyProg[condKey] or 0) + delta
    end

    -- 成就进度（仅累加型成就）
    local hasAchCond = false
    for _, t in ipairs(TaskConfig.ACHIEVEMENT) do
        if t.condKey == condKey then hasAchCond = true; break end
    end
    if hasAchCond then
        taskData.achProg[condKey] = (taskData.achProg[condKey] or 0) + delta
    end

    PDM.MarkDirty(uid, "task")
end

--- 刷新状态型成就进度（读取玩家当前状态，直接写入 achProg）
---@param uid number
function TaskService.RefreshAchievements(uid)
    local taskData = PDM.GetModule(uid, "task")
    if not taskData then return end

    ensurePeriods(taskData)

    local heroes = PDM.GetModule(uid, "heroes")
    local player = PDM.GetModule(uid, "player")
    local arena  = PDM.GetModule(uid, "arena")

    if not heroes or not player then return end

    -- 冒险等级
    taskData.achProg["player_level"] = player.level or 1

    -- SR / SSR 拥有数, 觉醒最大次数, 转职统计
    local srCount  = 0
    local ssrCount = 0
    local awkRMax  = 0
    local awkSRMax = 0
    local awkSSRMax = 0
    local adv1Count = 0
    local adv2Count = 0

    local okHC, HeroConfig = pcall(require, "config.HeroConfig")
    if not okHC then HeroConfig = nil end

    if heroes.roster then
        for heroId, heroData in pairs(heroes.roster) do
            -- 碎片存根（无 level 字段）不算"拥有"，跳过
            if not heroData.level then goto continue_hero end

            -- HeroConfig 使用 quality 字段: 1=R, 2=SR, 3=SSR
            local quality = 1
            if HeroConfig and HeroConfig.get then
                local cfg = HeroConfig.get(heroId)
                if cfg then quality = cfg.quality or 1 end
            end

            if quality == 2 then
                srCount = srCount + 1
            elseif quality == 3 then
                ssrCount = ssrCount + 1
            end

            local awkCount = 0
            if heroData.awakening then
                for _ in pairs(heroData.awakening) do awkCount = awkCount + 1 end
            end
            if quality == 1 then
                awkRMax = math.max(awkRMax, awkCount)
            elseif quality == 2 then
                awkSRMax = math.max(awkSRMax, awkCount)
            elseif quality == 3 then
                awkSSRMax = math.max(awkSSRMax, awkCount)
            end

            if heroData.advBranch then
                if heroData.advBranch.first then adv1Count = adv1Count + 1 end
                if heroData.advBranch.second then adv2Count = adv2Count + 1 end
            end

            ::continue_hero::
        end
    end

    taskData.achProg["sr_count"]    = srCount
    taskData.achProg["ssr_count"]   = ssrCount
    taskData.achProg["awk_r_max"]   = awkRMax
    taskData.achProg["awk_sr_max"]  = awkSRMax
    taskData.achProg["awk_ssr_max"] = awkSSRMax
    taskData.achProg["adv1_count"]  = adv1Count
    taskData.achProg["adv2_count"]  = adv2Count

    -- 竞技场段位
    if arena then
        local okAC, ArenaConfig = pcall(require, "config.ArenaConfig")
        if okAC and ArenaConfig and ArenaConfig.getTierByScore then
            local tier = ArenaConfig.getTierByScore(arena.rankScore or 0)
            taskData.achProg["arena_tier"] = tier and tier.icon or 0
        end
    end

    PDM.MarkDirty(uid, "task")
end

-- ======================== 生命周期 ========================

--- 玩家进入：记录登录、初始化在线时间追踪
---@param uid number
function TaskService.OnPlayerEnter(uid)
    local taskData = PDM.GetModule(uid, "task")
    if not taskData then return end

    ensurePeriods(taskData)

    -- 日任务: 登录
    if not taskData.dailyProg["login"] or taskData.dailyProg["login"] < 1 then
        taskData.dailyProg["login"] = 1
    end

    -- 周任务: 登录天数
    if not taskData._weekLoginDays then
        taskData._weekLoginDays = {}
    end
    local todayKey = tostring(TaskConfig.getDayNumber())
    if not taskData._weekLoginDays[todayKey] then
        taskData._weekLoginDays[todayKey] = true
        taskData.weeklyProg["login_days"] = (taskData.weeklyProg["login_days"] or 0) + 1
    end

    -- 初始化在线时间起点
    taskData._onlineStart = os.time()

    PDM.MarkDirty(uid, "task")

    -- 刷新状态型成就
    TaskService.RefreshAchievements(uid)

    print("[TaskService] OnPlayerEnter uid=" .. tostring(uid)
        .. " login=1, loginDays=" .. tostring(taskData.weeklyProg["login_days"]))
end

--- 定期调用：累计在线分钟数
---@param uid number
function TaskService.TickOnlineTime(uid)
    local taskData = PDM.GetModule(uid, "task")
    if not taskData then return end

    ensurePeriods(taskData)

    local now = os.time()
    local start = taskData._onlineStart or now
    local elapsed = now - start

    local minutes = math.floor(elapsed / 60)
    if minutes >= 1 then
        taskData.dailyProg["online_min"] = (taskData.dailyProg["online_min"] or 0) + minutes
        taskData._onlineStart = now - (elapsed % 60)
        PDM.MarkDirty(uid, "task")
    end
end

return TaskService
