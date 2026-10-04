-- 远征等级展示模型：不发奖、不写台账；奖励读取既有 TaskConfig。
-- 等级解锁与通关解锁分开，UI 与升级摘要共用真实规则接口。
local ExpTable = require("config.ExpTable")
local TaskConfig = require("config.TaskConfig")
local ArtifactSchema = require("shared.artifact.ArtifactSchema")
local ResourceDefs = require("config.ResourceDefs")
local NumberUtil = require("core.NumberUtil")
local I18n = require("core.I18n")

local Progress = {}
local rangeCache, levelUnlockCache = {}, {}

local function levelValue(value)
    local number = tonumber(value) or 1
    if number ~= number or number == math.huge or number == -math.huge then number = 1 end
    return math.max(1, math.min(ExpTable.PLAYER_MAX_LEVEL, math.floor(number)))
end

function Progress.rewardLabel(reward)
    if type(reward) ~= "table" then return I18n.lookup("奖励配置不可用") end
    local def = ResourceDefs.DEFS[reward.type]
    local name = def and def.name or tostring(reward.type or "奖励")
    return I18n.lookup(name) .. " × " .. NumberUtil.format(reward.amount or 0)
end

-- 缓存仅保存原始规则数据；在显示边界按当前语言组装，不污染共享解锁缓存。
function Progress.unlockLabel(entry)
    if entry.id == "team_slots" then
        return I18n.format("每队可出战 %d 人", ExpTable.getUnlockedSlotCountForTeam(entry.level))
    elseif entry.id == "enhance_cap" then
        return I18n.format("装备强化上限 Lv.%d", ExpTable.getEnhanceLevelCap(entry.level))
    elseif entry.id:match("^artifact_slot_") then
        return I18n.format("神器第 %d 格", ArtifactSchema.getUnlockedSubSlotCount(entry.level))
    elseif entry.id == "church" then
        return I18n.lookup("礼拜堂正式开放（引导门控另计）")
    elseif entry.kind == "stage" and entry.stageId then
        local team = tonumber(entry.id:match("^team_(%d+)$")) or 1
        return I18n.format("小队 %d · 通关%d-%d解锁", team,
            math.floor(entry.stageId / 100), entry.stageId % 100)
    end
    return I18n.lookup(entry.unlockName or "")
end

function Progress.getLevelUnlocks(level)
    level = levelValue(level)
    if levelUnlockCache[level] then return levelUnlockCache[level] end
    local entries = {}
    levelUnlockCache[level] = entries
    if level <= 1 then return entries end
    local previousSlots = ExpTable.getUnlockedSlotCountForTeam(level - 1)
    local currentSlots = ExpTable.getUnlockedSlotCountForTeam(level)
    if currentSlots > previousSlots then
        entries[#entries + 1] = {
            id = "team_slots", kind = "level", level = level,
            unlockName = "每队可出战 " .. currentSlots .. " 人",
        }
    end
    entries[#entries + 1] = {
        id = "enhance_cap", kind = "level", level = level,
        unlockName = "装备强化上限 Lv." .. ExpTable.getEnhanceLevelCap(level),
    }
    local before = ArtifactSchema.getUnlockedSubSlotCount(level - 1)
    local after = ArtifactSchema.getUnlockedSubSlotCount(level)
    if after > before then
        entries[#entries + 1] = {
            id = "artifact_slot_" .. after, kind = "level", level = level,
            unlockName = "神器第 " .. after .. " 格",
        }
    end
    if level == ExpTable.CHURCH_UNLOCK_LEVEL then
        entries[#entries + 1] = {
            id = "church", kind = "level", level = level,
            unlockName = "礼拜堂正式开放（引导门控另计）",
        }
    end
    return entries
end

-- 跨级只保留每种成长的最终上限，新增格位仍逐项保留，不覆盖早一级解锁。
function Progress.getRangeUnlocks(fromLevel, toLevel)
    local from, target = levelValue(fromLevel), levelValue(toLevel)
    local cacheKey = from .. ":" .. target
    if rangeCache[cacheKey] then return rangeCache[cacheKey] end
    local entries, indexes = {}, {}
    for level = from + 1, target do
        for _, entry in ipairs(Progress.getLevelUnlocks(level)) do
            local index = indexes[entry.id]
            if index then entries[index] = entry else
                entries[#entries + 1] = entry
                indexes[entry.id] = #entries
            end
        end
    end
    rangeCache[cacheKey] = entries
    return entries
end

function Progress.build(player, taskData, battle)
    player = type(player) == "table" and player or {}
    taskData = type(taskData) == "table" and taskData or {}
    local level = levelValue(player.level)
    local exp = math.max(0, tonumber(player.exp) or 0)
    local maxExp = ExpTable.getPlayerExpForLevel(level) or 0
    if maxExp == 0 then exp = 0 end
    local claimed = type(taskData.achClaimed) == "table" and taskData.achClaimed or {}
    local snapshot = {
        level = level, exp = exp, maxExp = maxExp,
        ratio = maxExp > 0 and math.min(exp / maxExp, 1) or 1,
        claimableCount = 0, nextLevel = nil, focusIndex = 1,
        slotCount = ExpTable.getUnlockedSlotCountForTeam(level),
        enhanceCap = ExpTable.getEnhanceLevelCap(level),
        artifactSlotCount = ArtifactSchema.getUnlockedSubSlotCount(level),
        currentUnlocks = Progress.getRangeUnlocks(1, level),
        rows = {}, stageUnlocks = {},
    }
    -- 每级只有一个节点；原里程碑与新增奖励分别保留永久台账。
    for target = 1, ExpTable.PLAYER_MAX_LEVEL do
        local row = {
            taskId = "a_plv_bonus_v1_" .. target, level = target,
            status = TaskConfig.STATUS.LOCKED, current = target == level,
            rewards = {}, tasks = {}, unlocks = Progress.getLevelUnlocks(target),
        }
        local allClaimed, anyClaimable = true, false
        for _, task in ipairs(TaskConfig.LEVEL_TASKS[target] or {}) do
            local status = claimed[task.id] and TaskConfig.STATUS.CLAIMED
                or (level >= target and TaskConfig.STATUS.CLAIMABLE or TaskConfig.STATUS.LOCKED)
            row.tasks[#row.tasks + 1] = { taskId = task.id, reward = task.reward, status = status }
            row.rewards[#row.rewards + 1] = task.reward
            allClaimed = allClaimed and status == TaskConfig.STATUS.CLAIMED
            anyClaimable = anyClaimable or status == TaskConfig.STATUS.CLAIMABLE
        end
        row.reward = row.rewards[#row.rewards]
        row.status = allClaimed and TaskConfig.STATUS.CLAIMED
            or (anyClaimable and TaskConfig.STATUS.CLAIMABLE or TaskConfig.STATUS.LOCKED)
        snapshot.rows[#snapshot.rows + 1] = row
        if anyClaimable then snapshot.claimableCount = snapshot.claimableCount + 1 end
    end
    snapshot.nextLevel = level < ExpTable.PLAYER_MAX_LEVEL and level + 1 or nil
    snapshot.focusIndex = level
    local teamCount = ExpTable.getUnlockedTeamCount(battle)
    for team = 2, ExpTable.TEAM_COUNT do
        local stage = ExpTable.getTeamUnlockStage(team)
        snapshot.stageUnlocks[#snapshot.stageUnlocks + 1] = {
            id = "team_" .. team, kind = "stage", stageId = stage,
            unlocked = team <= teamCount,
            unlockName = "小队 " .. team .. " · " .. ExpTable.getTeamUnlockText(team),
        }
    end
    return snapshot
end

return Progress
