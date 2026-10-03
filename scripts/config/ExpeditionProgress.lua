-- 远征等级展示模型：不发奖、不写台账；奖励读取既有 TaskConfig。
-- 等级解锁与通关解锁分开，UI 与升级摘要共用真实规则接口。
local ExpTable = require("config.ExpTable")
local TaskConfig = require("config.TaskConfig")
local ArtifactSchema = require("shared.artifact.ArtifactSchema")
local ResourceDefs = require("config.ResourceDefs")
local NumberUtil = require("core.NumberUtil")

local Progress = {}
local rangeCache = {}

local function levelValue(value)
    local number = tonumber(value) or 1
    if number ~= number or number == math.huge or number == -math.huge then number = 1 end
    return math.max(1, math.min(ExpTable.PLAYER_MAX_LEVEL, math.floor(number)))
end

function Progress.rewardLabel(reward)
    if type(reward) ~= "table" then return "奖励配置不可用" end
    local def = ResourceDefs.DEFS[reward.type]
    return (def and def.name or tostring(reward.type or "奖励")) .. " × " .. NumberUtil.format(reward.amount or 0)
end

function Progress.getLevelUnlocks(level)
    level = levelValue(level)
    local entries = {}
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
    for _, task in ipairs(TaskConfig.ACHIEVEMENT) do
        if task.group == "level" then
            snapshot.rows[#snapshot.rows + 1] = {
                taskId = task.id, level = task.target, reward = task.reward,
                status = claimed[task.id] and TaskConfig.STATUS.CLAIMED
                    or (level >= task.target and TaskConfig.STATUS.CLAIMABLE or TaskConfig.STATUS.LOCKED),
                unlocks = Progress.getLevelUnlocks(task.target),
            }
        end
    end
    table.sort(snapshot.rows, function(a, b) return a.level < b.level end)
    local firstClaimable, firstLocked = nil, nil
    for index, row in ipairs(snapshot.rows) do
        if row.status == TaskConfig.STATUS.CLAIMABLE then
            snapshot.claimableCount = snapshot.claimableCount + 1
            firstClaimable = firstClaimable or index
        elseif row.status == TaskConfig.STATUS.LOCKED then
            firstLocked = firstLocked or index
        end
        if row.level > level and not snapshot.nextLevel then snapshot.nextLevel = row.level end
    end
    snapshot.focusIndex = firstClaimable or firstLocked or math.max(1, #snapshot.rows)
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
