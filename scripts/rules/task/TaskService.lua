-- ============================================================================
-- TaskService - 任务系统业务逻辑
-- 职责: 周期重置、进度追踪、奖励发放、成就刷新（纯业务，禁止网络 IO）
-- 层级: server/task  |  通过 PDM 读写数据
-- ============================================================================

local PDM             = require("rules.character.PlayerDataManager")
local TaskConfig      = require("config.TaskConfig")
local CurrencyService = require("rules.currency.CurrencyService")

local TaskService = {}

---@type fun(uid: number): boolean|nil
local persist_ = nil
---@type table
local claimHooks_ = {}

--- 单机桥注入真正的 Flush；hooks 只负责延后本地推送，不承担发奖逻辑。
---@param callback fun(uid: number): boolean|nil
---@param hooks table|nil { begin=function, finish=function(uid,success) }
function TaskService.SetPersistCallback(callback, hooks)
    persist_ = callback
    claimHooks_ = hooks or {}
end

local function copyTable(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = copyTable(item) end
    return copy
end

--- 保持模块及已有领取表的引用，失败只还原本次修改，不清历史台账。
local function restoreTable(target, snapshot)
    for key in pairs(target) do
        if snapshot[key] == nil then target[key] = nil end
    end
    for key, value in pairs(snapshot) do
        if type(value) == "table" and type(target[key]) == "table" then
            restoreTable(target[key], value)
        else
            target[key] = copyTable(value)
        end
    end
end

--- 与 CurrencyService 相同的类型映射，不以 UI 的窄映射判断发奖。
local function validateReward(uid, reward)
    if type(reward) ~= "table" or type(reward.type) ~= "string"
        or type(reward.amount) ~= "number" or reward.amount ~= reward.amount
        or reward.amount <= 0 or reward.amount == math.huge
        or reward.amount ~= math.floor(reward.amount) then
        return false
    end
    local legacyId = require("config.ResourceDefs").SHARD_ID_TO_HERO[reward.type]
    if reward.type == "shard" or legacyId then
        local heroId = legacyId or tonumber(reward.heroId)
        return heroId ~= nil and heroId > 0 and heroId == math.floor(heroId)
            and PDM.GetModule(uid, "heroes") ~= nil
    end
    return CurrencyService.REWARD_TO_CURRENCY[reward.type] ~= nil
        and PDM.GetModule(uid, "currency") ~= nil
end

local function persistClaim(uid)
    if persist_ then return persist_(uid) == true end
    if PDM.IsLocalMode(uid) then
        local GameState = require("core.GameState")
        GameState.syncFromCurrency(PDM.GetModule(uid, "currency"), { silent = true })
        return require("boot.StandaloneSave").Flush() == true
    end
    return true
end

--- 同页奖励整体提交：先全量校验，再发奖，成功后记账，真实落盘后才回成功。
local function commitClaims(uid, entries)
    for _, entry in ipairs(entries) do
        if not validateReward(uid, entry.task.reward) then return false, "invalid_reward" end
    end
    local snapshots = {}
    for _, name in ipairs({ "task", "currency", "heroes" }) do
        local data = PDM.GetModule(uid, name)
        if data then snapshots[name] = { data = data, before = copyTable(data) } end
    end
    local reason = "reward_failed"
    local ok, success = pcall(function()
        if claimHooks_.begin then claimHooks_.begin(uid) end
        for _, entry in ipairs(entries) do
            if CurrencyService.GrantReward(uid, entry.task.reward) ~= true then return false end
        end
        for _, entry in ipairs(entries) do entry.claimed[entry.task.id] = true end
        PDM.MarkDirty(uid, "task")
        reason = "save_failed"
        return persistClaim(uid)
    end)
    local committed = ok and success == true
    if not committed then
        for _, snapshot in pairs(snapshots) do restoreTable(snapshot.data, snapshot.before) end
        -- 默认持久化路径也可能已镜像新余额，失败必须同时还原 GameState。
        if PDM.IsLocalMode(uid) then
            require("core.GameState").syncFromCurrency(PDM.GetModule(uid, "currency"), { silent = true })
        end
        print("[TaskService] claim rollback uid=" .. tostring(uid) .. " reason=" .. reason
            .. (not ok and " error=" .. tostring(success) or ""))
    end
    if claimHooks_.finish then
        local notified, err = pcall(claimHooks_.finish, uid, committed)
        if not notified then print("[TaskService] claim notify failed: " .. tostring(err)) end
    elseif not committed then
        for name in pairs(snapshots) do PDM.MarkDirty(uid, name) end
    end
    if not committed then return false, reason end
    return true
end

-- ======================== 内部工具 ========================

--- 检查并重置过期的日/周任务进度
---@param taskData table task 模块数据
local function ensurePeriods(taskData)
    -- 老档只补缺省表，不覆盖永久领取历史。
    for _, key in ipairs({ "dailyProg", "dailyClaimed", "weeklyProg", "weeklyClaimed", "achProg", "achClaimed" }) do
        if type(taskData[key]) ~= "table" then taskData[key] = {} end
    end
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
    -- 状态型任务领取校验也读取规则层当前玩家，而非依赖页面刷新。
    if category == "achievement" then TaskService.RefreshAchievements(uid) end

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

    local ok, reason = commitClaims(uid, { { task = taskDef, claimed = claimedTable } })
    if not ok then return false, reason end

    print("[TaskService] ClaimTask uid=" .. tostring(uid)
        .. " taskId=" .. taskId
        .. " reward=" .. taskDef.reward.type .. "×" .. taskDef.reward.amount)

    return true, nil, {
        taskId = taskId,
        reward = taskDef.reward,
    }
end

--- 当前页签对应的功绩列表
---@param scope string "clear"|"level"|"hero"
---@return table[]
local function achievementsInScope(scope)
    local out = {}
    for _, task in ipairs(TaskConfig.ACHIEVEMENT) do
        if scope == "level" or scope == "hero" then
            if task.group == scope then
                out[#out + 1] = task
            end
        elseif task.difficulty == "normal" or task.difficulty == "hard" or task.difficulty == "nightmare" then
            out[#out + 1] = task
        end
    end
    return out
end

--- 一键领取指定页签下全部可领功绩
---@param uid number
---@param scope string
---@param level number? 指定远征节点时只领取该级未领项，旧单领与整页批领接口保持兼容。
---@return boolean, string|nil, table|nil
function TaskService.ClaimAll(uid, scope, level)
    if scope ~= "clear" and scope ~= "level" and scope ~= "hero" then
        return false, "invalid_scope"
    end
    if level ~= nil and (scope ~= "level" or type(level) ~= "number" or level ~= level
        or level < 1 or level > require("config.ExpTable").PLAYER_MAX_LEVEL or level ~= math.floor(level)) then
        return false, "invalid_params"
    end
    TaskService.RefreshAchievements(uid)
    local taskData = PDM.GetModule(uid, "task")
    if not taskData then return false, "no_data" end
    local entries, claimed, rewards = {}, {}, {}
    for _, task in ipairs(achievementsInScope(scope)) do
        if (level == nil or task.target == level) and not taskData.achClaimed[task.id]
            and (taskData.achProg[task.condKey] or 0) >= task.target then
            entries[#entries + 1] = { task = task, claimed = taskData.achClaimed }
            claimed[#claimed + 1] = task.id
            rewards[#rewards + 1] = task.reward
        end
    end
    if #entries == 0 then return false, "nothing_to_claim" end
    local ok, reason = commitClaims(uid, entries)
    if not ok then return false, reason end
    print("[TaskService] ClaimAll uid=" .. tostring(uid)
        .. " scope=" .. scope .. " count=" .. tostring(#claimed))
    return true, nil, { scope = scope, claimed = claimed, rewards = rewards }
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

    local battle = PDM.GetModule(uid, "battle")
    if battle then
        local stageCount = 0
        if type(battle.clearedStages) == "table" then
            for _, cleared in pairs(battle.clearedStages) do
                if cleared then stageCount = stageCount + 1 end
            end
        end
        taskData.achProg["stage_count"] = stageCount
        taskData.achProg["max_stage"] = tonumber(battle.maxStageId) or tonumber(battle.currentStageId) or 0
        local TaskConfig = require("config.TaskConfig")
        local cleared = battle.clearedStages or {}
        for _, task in ipairs(TaskConfig.ACHIEVEMENT) do
            if task.stageId then
                local done = cleared[tostring(task.stageId)] or cleared[task.stageId]
                taskData.achProg[task.condKey] = done and 1 or 0
            end
        end
    end

    local heroes = PDM.GetModule(uid, "heroes")
    local player = PDM.GetModule(uid, "player")

    -- 远征等级不依赖 heroes 模块到齐（新档/精简测试同样可刷新）。
    if player then taskData.achProg["player_level"] = player.level or 1 end
    if not heroes then
        PDM.MarkDirty(uid, "task")
        return
    end

    -- SR / SSR 拥有数, 觉醒最大次数, 转职统计
    local srCount  = 0
    local ssrCount = 0
    local heroCount = 0
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
            heroCount = heroCount + 1

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

            local awkCount = require("config.AwakeningConfig").countActivated(heroData.awakening)
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
    taskData.achProg["hero_count"]  = heroCount
    taskData.achProg["awk_r_max"]   = awkRMax
    taskData.achProg["awk_sr_max"]  = awkSRMax
    taskData.achProg["awk_ssr_max"] = awkSSRMax
    taskData.achProg["awk_max"]     = math.max(awkRMax, awkSRMax, awkSSRMax)
    taskData.achProg["adv1_count"]  = adv1Count
    taskData.achProg["adv2_count"]  = adv2Count
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
        taskData.weeklyProg["online_min"] = (taskData.weeklyProg["online_min"] or 0) + minutes
        taskData._onlineStart = now - (elapsed % 60)
        PDM.MarkDirty(uid, "task")
    end
end

return TaskService
