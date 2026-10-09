-- ============================================================================
-- ArtifactService.lua — 神器抽取/装配服务（服务端权威）
-- ============================================================================

local PDM             = require("rules.character.PlayerDataManager")
local ArtifactDefs    = require("shared.artifact.ArtifactDefs")
local ArtifactSchema  = require("shared.artifact.ArtifactSchema")
local ExpTable        = require("config.ExpTable")
local TaskService     = require("rules.task.TaskService")
local CurrencyService = require("rules.currency.CurrencyService")

local ArtifactService = {}

local function ensureData(uid)
    local data = PDM.GetModule(uid, "artifacts")
    if data then
        ArtifactSchema.normalizeModule(data)
    end
    return data
end

local function findBagIndex(data, artifactId)
    artifactId = tostring(artifactId or "")
    for i, a in ipairs(data.bag or {}) do
        if tostring(a.id) == artifactId then
            return i, a
        end
    end
    return nil, nil
end

--- [三队适配] 任意队伍是否已装配（返回 teamIdx, slot, subSlot）
local function findEquippedAnyTeam(data, artifactId)
    return ArtifactSchema.findEquippedSlotAnyTeam(data, artifactId)
end



local function getArtifactRefineRatio(artifact)
    if not artifact then return nil end
    local ratio = artifact.valueRatio
    if ratio == nil and artifact.value ~= nil then
        ratio = ArtifactDefs.valueToRatio(artifact.artifactId or artifact.id, tonumber(artifact.quality) or 1, artifact.value)
    end
    if ratio == nil then return nil end
    return math.max(0, math.min(10000, math.floor(tonumber(ratio) or 0)))
end

local function getThreatClearRefineRatio(artifact)
    if not artifact then return nil end
    local ratio = artifact.threatClearRatio
    if ratio == nil then
        local threatClearValue = ArtifactDefs.getThreatClearValue and ArtifactDefs.getThreatClearValue(artifact) or nil
        if threatClearValue ~= nil and ArtifactDefs.threatClearValueToRatio then
            ratio = ArtifactDefs.threatClearValueToRatio(artifact.artifactId or artifact.id, tonumber(artifact.quality) or 1, threatClearValue)
        end
    end
    if ratio == nil then return nil end
    return math.max(0, math.min(10000, math.floor(tonumber(ratio) or 0)))
end

local function canRefineArtifact(artifact)
    local mainRatio = getArtifactRefineRatio(artifact)
    local threatClearRatio = getThreatClearRefineRatio(artifact)
    if mainRatio and mainRatio < 10000 then return true end
    if threatClearRatio and threatClearRatio < 10000 then return true end
    return false
end

local function isValidSlotIndex(value, maxValue)
    value = tonumber(value)
    if not value or value ~= value
        or value == math.huge or value == -math.huge then
        return false
    end
    return value == math.floor(value) and value >= 1 and value <= maxValue
end

local function getPlayerLevel(uid)
    local player = PDM.GetModule(uid, "player")
    return tonumber(player and player.level) or 1
end

local function countBagTypesAfterRemove(data, removeArtifacts)
    local counts = {}
    for _, a in ipairs(data.bag or {}) do
        local tid = tonumber(a.artifactId) or 0
        if tid > 0 then
            counts[tid] = (counts[tid] or 0) + 1
        end
    end
    for _, a in ipairs(removeArtifacts) do
        local tid = tonumber(a.artifactId) or 0
        if tid > 0 and counts[tid] then
            counts[tid] = counts[tid] - 1
            if counts[tid] <= 0 then
                counts[tid] = nil
            end
        end
    end
    return counts
end

local function hasSameTypeInSlot(data, slot, artifact, ignoreSubSlot, teamIdx)
    if not artifact then return false end
    local artifactType = tonumber(artifact.artifactId) or tonumber(artifact.type) or 0
    if artifactType <= 0 then return false end
    local artifactInstanceId = tostring(artifact.id or "")
    for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
        if subSlot ~= ignoreSubSlot then
            local equippedId = ArtifactSchema.getEquippedId(data, slot, subSlot, teamIdx)
            local equippedArtifact = equippedId and select(2, findBagIndex(data, equippedId)) or nil
            local equippedType = equippedArtifact and (tonumber(equippedArtifact.artifactId) or tonumber(equippedArtifact.type) or 0) or 0
            if equippedArtifact and equippedType == artifactType and tostring(equippedArtifact.id or "") ~= artifactInstanceId then
                return true
            end
        end
    end
    return false
end

local function validateMergeGroup(data, artifactIds, usedIds)
    if not artifactIds or #artifactIds ~= 3 then
        return nil, nil, nil, nil, "需要提供3个神器ID"
    end

    local artifacts = {}
    local bagIndices = {}
    for _, id in ipairs(artifactIds) do
        local idStr = tostring(id or "")
        if usedIds and usedIds[idStr] then
            return nil, nil, nil, nil, "不能重复使用神器: " .. idStr
        end
        local idx, artifact = findBagIndex(data, idStr)
        if not artifact then return nil, nil, nil, nil, "神器不在背包中: " .. idStr end
        -- [三队适配] 任一队伍已装配的实例都不能合成
        if findEquippedAnyTeam(data, artifact.id) then
            return nil, nil, nil, nil, "已安装神器不能合成"
        end
        artifacts[#artifacts + 1] = artifact
        bagIndices[#bagIndices + 1] = idx
        if usedIds then usedIds[idStr] = true end
    end

    local baseArtifactId = artifacts[1].artifactId
    local baseQuality = tonumber(artifacts[1].quality) or 1
    for i = 2, 3 do
        if artifacts[i].artifactId ~= baseArtifactId then
            return nil, nil, nil, nil, "合成需要相同神器"
        end
        if tonumber(artifacts[i].quality) ~= baseQuality then
            return nil, nil, nil, nil, "合成需要相同品质"
        end
    end

    if baseQuality >= 6 then
        return nil, nil, nil, nil, "至臻品质无法继续合成"
    end

    local newQuality = baseQuality + 1
    if not ArtifactDefs.getRange(baseArtifactId, newQuality) then
        return nil, nil, nil, nil, "该神器没有更高品质定义"
    end

    return artifacts, bagIndices, baseArtifactId, newQuality, nil
end

local function rollQuality(chest)
    local total = 0
    for _, row in ipairs(chest.rates) do total = total + row.weight end
    local roll = math.random(1, total)
    local acc = 0
    for _, row in ipairs(chest.rates) do
        acc = acc + row.weight
        if roll <= acc then return row.quality end
    end
    return 1
end

local function rollThreatClearValueRatio(artifactDefId, quality)
    return ArtifactDefs.rollThreatClearValueRatio and ArtifactDefs.rollThreatClearValueRatio(artifactDefId, quality) or nil
end

local function addCount(map, key, amount)
    key = tostring(key or "unknown")
    map[key] = (tonumber(map[key]) or 0) + (amount or 1)
end

local function recordDrawStats(data, count, rewards, chestType)
    if type(data.drawStats) ~= "table" then data.drawStats = {} end
    local stats = data.drawStats
    stats.total = (tonumber(stats.total) or 0) + count
    stats.single = tonumber(stats.single) or 0
    stats.ten = tonumber(stats.ten) or 0
    if count == 10 then
        stats.ten = stats.ten + 1
    elseif count == 1 then
        stats.single = stats.single + 1
    end
    if type(stats.byChest) ~= "table" then stats.byChest = {} end
    addCount(stats.byChest, chestType, count)
    if type(stats.byQuality) ~= "table" then stats.byQuality = {} end
    if type(stats.byArtifactId) ~= "table" then stats.byArtifactId = {} end
    for _, artifact in ipairs(rewards or {}) do
        addCount(stats.byQuality, artifact.quality or 0, 1)
        addCount(stats.byArtifactId, artifact.artifactId or 0, 1)
    end
end

local function createArtifact(id, quality)
    local artifactDefId = ArtifactDefs.rollArtifactId(quality)
    if not artifactDefId then return nil, "没有可抽取的神器定义" end

    local artifact = {
        id = tostring(id),
        artifactId = artifactDefId,
        quality = quality,
        valueRatio = ArtifactDefs.rollValueRatio(),
    }
    local threatClearRatio = rollThreatClearValueRatio(artifactDefId, quality)
    if threatClearRatio ~= nil then
        artifact.threatClearRatio = threatClearRatio
    end
    ArtifactDefs.normalizeInstanceValue(artifact)
    return artifact
end

local function getDayId()
    return math.floor((os.time() + 28800) / 86400)
end

function ArtifactService.Draw(uid, count, payType, chestType)
    count = tonumber(count) or 1
    if count ~= 1 and count ~= 10 then return false, "抽取次数错误" end
    chestType = chestType or "normal"
    local chest = ArtifactDefs.getChest(chestType)
    if not chest then return false, "神器宝箱类型错误" end
    if not ArtifactDefs.isChestUnlocked(chestType, PDM.GetModule(uid, "battle")) then
        return false, ArtifactDefs.getChestUnlockText(chestType)
    end

    local data = ensureData(uid)
    if not data then return false, "神器数据未加载" end
    if #data.bag + count > ArtifactDefs.MAX_BAG then return false, "神器背包已满" end
    local keyCost = ArtifactDefs.getDrawKeyCost(count, chestType)
    if not keyCost then return false, "抽取次数错误" end
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, "货币数据未加载" end

    payType = payType or "diamond"
    local keysToUse, diamondNeeded = 0, 0
    local isFreeDaily = false
    local today = getDayId()
    if payType == "free_daily" then
        if not chest.dailyFree then return false, "每日免费仅限普通神器宝箱" end
        if count ~= 1 then return false, "免费抽取只支持单抽" end
        if (data.dailyFreeDrawDayId or 0) == today then return false, "今日免费单抽已使用" end
        isFreeDaily = true
    elseif payType == "key" then
        if (currency.goldenKey or 0) < keyCost then
            return false, "黄金钥匙不足（需要 " .. keyCost .. "）"
        end
        keysToUse = keyCost
    elseif payType == "diamond" then
        keysToUse = math.min(currency.goldenKey or 0, keyCost)
        diamondNeeded = (keyCost - keysToUse) * ArtifactDefs.KEY_DIAMOND_PRICE
        if (currency.gems or 0) < diamondNeeded then
            return false, "黑晶不足（需要 " .. diamondNeeded .. "）"
        end
    else
        return false, "神器支付方式错误"
    end

    -- 全批次生成成功后再提交费用/背包/统计，失败不留下部分奖励或消耗。
    local rewards = {}
    for i = 1, count do
        local quality = rollQuality(chest)
        local artifact, err = createArtifact(data.nextId + i - 1, quality)
        if not artifact then return false, err or "神器生成失败" end
        rewards[#rewards + 1] = artifact
    end
    if not isFreeDaily then
        currency.goldenKey = (currency.goldenKey or 0) - keysToUse
        currency.gems = (currency.gems or 0) - diamondNeeded
        PDM.MarkDirty(uid, "currency")
    end
    for _, artifact in ipairs(rewards) do data.bag[#data.bag + 1] = artifact end
    data.nextId = data.nextId + count
    data.totalDraws = (data.totalDraws or 0) + count
    recordDrawStats(data, count, rewards, chestType)
    if isFreeDaily then data.dailyFreeDrawDayId = today end

    ArtifactSchema.normalizeModule(data)
    PDM.MarkDirty(uid, "artifacts")
    PDM.FlushImmediate(uid)
    TaskService.UpdateProgress(uid, "artifact_draw", count)
    print("[ArtifactService] DRAW uid=" .. tostring(uid) .. " chest=" .. chestType
        .. " count=" .. count .. " keys=" .. keysToUse .. " diamonds=" .. diamondNeeded
        .. " freeDaily=" .. tostring(isFreeDaily) .. " rewards=" .. #rewards)

    return true, nil, {
        count = count, chestType = chestType,
        keyCost = keyCost, keysUsed = keysToUse, diamondCost = diamondNeeded,
        freeDaily = isFreeDaily, dailyFreeDrawDayId = data.dailyFreeDrawDayId or 0,
        balance = currency.gems, goldenKey = currency.goldenKey, artifacts = rewards,
        -- 协议保留旧计数字段为零；它们不影响任何品质判定。
        pityRare = 0, pityEpic = 0, pityHits = {},
    }
end

--- 装配到指定队伍：同实例全队唯一，跨队必须先明确卸下
function ArtifactService.Equip(uid, artifactId, slot, subSlot, teamIdx)
    slot = tonumber(slot)
    subSlot = tonumber(subSlot) or 1
    teamIdx = ArtifactSchema.normalizeTeamIdx(teamIdx)
    if not isValidSlotIndex(slot, ArtifactSchema.SLOT_COUNT) then
        return false, "无效的槽位"
    end
    if not isValidSlotIndex(subSlot, ArtifactSchema.SUB_SLOT_COUNT) then
        return false, "无效的神器格子"
    end

    -- 队伍通关门槛与下面的神器子格等级门槛独立，规则层不能只依赖 UI 禁点。
    local battleProgress = PDM.GetModule(uid, "battle")
    if teamIdx > ExpTable.getUnlockedTeamCount(battleProgress) then
        return false, string.format("队伍%d尚未解锁（%s）", teamIdx, ExpTable.getTeamUnlockText(teamIdx))
    end
    local playerLevel = getPlayerLevel(uid)
    if subSlot > ArtifactSchema.getUnlockedSubSlotCount(playerLevel) then
        local unlockLevel = ArtifactSchema.getSubSlotUnlockLevel(subSlot)
        return false, "远征等级达到" .. tostring(unlockLevel) .. "级后解锁第" .. tostring(subSlot) .. "神器格"
    end

    -- 跨队拒绝必须在normalize前：不能因失败重建旧档、卸原队或覆盖目标。
    local rawData = PDM.GetModule(uid, "artifacts")
    local occupiedTeam = findEquippedAnyTeam(rawData, artifactId)
    if occupiedTeam and occupiedTeam ~= teamIdx then
        return false, "神器已安装在队伍" .. tostring(occupiedTeam) .. "，请先卸下再安装到其他队伍"
    end
    local data = ensureData(uid)
    if not data then return false, "神器数据未加载" end

    local _idx, artifact = findBagIndex(data, artifactId)
    if not artifact then return false, "神器不存在" end

    if hasSameTypeInSlot(data, slot, artifact, subSlot, teamIdx) then
        return false, "同一槽位不能佩戴相同类型神器"
    end

    -- 同队换槽照常移动；跨队占用已拒绝，不用setter偷偷转移来源。
    local currentSlot, currentSubSlot = ArtifactSchema.findEquippedSlot(data, artifact.id, teamIdx)
    if currentSlot then
        ArtifactSchema.setEquippedId(data, currentSlot, currentSubSlot or 1, nil, teamIdx)
    end
    ArtifactSchema.setEquippedId(data, slot, subSlot, artifact.id, teamIdx)

    ArtifactSchema.normalizeModule(data)
    PDM.MarkDirty(uid, "artifacts")
    PDM.FlushImmediate(uid)

    print("[ArtifactService] EQUIP uid=" .. tostring(uid)
        .. " team=" .. tostring(teamIdx)
        .. " slot=" .. tostring(slot)
        .. " subSlot=" .. tostring(subSlot)
        .. " artifactId=" .. tostring(artifact.id))

    return true, nil, { artifactId = tostring(artifact.id), slot = slot, subSlot = subSlot, teamIdx = teamIdx }
end

--- [三队适配] 卸下指定队伍的装配（teamIdx 缺省 1）
function ArtifactService.Unequip(uid, slot, subSlot, teamIdx)
    slot = tonumber(slot)
    subSlot = tonumber(subSlot) or 1
    teamIdx = ArtifactSchema.normalizeTeamIdx(teamIdx)
    if not isValidSlotIndex(slot, ArtifactSchema.SLOT_COUNT) then
        return false, "无效的槽位"
    end
    if not isValidSlotIndex(subSlot, ArtifactSchema.SUB_SLOT_COUNT) then
        return false, "无效的神器格子"
    end

    local data = ensureData(uid)
    if not data then return false, "神器数据未加载" end
    local artifactId = ArtifactSchema.getEquippedId(data, slot, subSlot, teamIdx)
    ArtifactSchema.setEquippedId(data, slot, subSlot, nil, teamIdx)

    ArtifactSchema.normalizeModule(data)
    PDM.MarkDirty(uid, "artifacts")
    PDM.FlushImmediate(uid)

    print("[ArtifactService] UNEQUIP uid=" .. tostring(uid)
        .. " team=" .. tostring(teamIdx)
        .. " slot=" .. tostring(slot)
        .. " subSlot=" .. tostring(subSlot)
        .. " artifactId=" .. tostring(artifactId))

    return true, nil, { artifactId = artifactId, slot = slot, subSlot = subSlot, teamIdx = teamIdx }
end

function ArtifactService.RefineValue(uid, artifactId)
    local data = ensureData(uid)
    if not data then return false, "神器数据未加载" end

    local _idx, artifact = findBagIndex(data, artifactId)
    if not artifact then return false, "神器不存在" end

    if not canRefineArtifact(artifact) then
        return false, "神器数值已达到上限"
    end

    local okDeduct, newBalance = CurrencyService.Deduct(uid, "privilegePoint", 1)
    if not okDeduct then
        return false, "特权点不足"
    end

    artifact.valueRatio = ArtifactDefs.rollValueRatio()
    local threatClearRatio = rollThreatClearValueRatio(artifact.artifactId, artifact.quality)
    if threatClearRatio ~= nil then
        artifact.threatClearRatio = threatClearRatio
    else
        artifact.threatClearRatio = nil
        artifact.threatClearValue = nil
    end
    ArtifactDefs.normalizeInstanceValue(artifact)

    ArtifactSchema.normalizeModule(data)
    PDM.MarkDirty(uid, "artifacts")
    PDM.MarkDirty(uid, "currency")
    PDM.FlushImmediate(uid)

    print("[ArtifactService] REFINE_VALUE uid=" .. tostring(uid)
        .. " artifactId=" .. tostring(artifact.id)
        .. " type=" .. tostring(artifact.artifactId)
        .. " quality=" .. tostring(artifact.quality)
        .. " value=" .. tostring(artifact.value)
        .. " privilegePoint=" .. tostring(newBalance))

    return true, nil, {
        artifact = artifact,
        artifactId = tostring(artifact.id),
        privilegePoint = newBalance,
    }
end

function ArtifactService.Reroll(uid, artifactIds)
    if not artifactIds or #artifactIds ~= 2 then
        return false, "需要选择2个神器"
    end

    local data = ensureData(uid)
    if not data then return false, "神器数据未加载" end

    local used = {}
    local artifacts = {}
    local bagIndices = {}
    for _, id in ipairs(artifactIds) do
        local idStr = tostring(id or "")
        if used[idStr] then return false, "不能重复选择同一个神器" end
        used[idStr] = true
        local idx, artifact = findBagIndex(data, idStr)
        if not artifact then return false, "神器不在背包中: " .. idStr end
        -- 任一队伍已装配实例都受保护，不能置换
        if findEquippedAnyTeam(data, artifact.id) then return false, "已安装神器不能置换" end
        artifacts[#artifacts + 1] = artifact
        bagIndices[#bagIndices + 1] = idx
    end

    local quality = tonumber(artifacts[1].quality) or 1
    if tonumber(artifacts[2].quality) ~= quality then
        return false, "置换需要2个同品质神器"
    end

    local srcType1 = tonumber(artifacts[1].artifactId) or 0
    local srcType2 = tonumber(artifacts[2].artifactId) or 0
    local typeCounts = countBagTypesAfterRemove(data, artifacts)
    local newArtifactId = ArtifactDefs.rollArtifactIdForReroll(quality, { srcType1, srcType2 }, typeCounts)
    if not newArtifactId then
        return false, "没有可置换的新神器类型"
    end

    local id = tostring(data.nextId or 1)
    data.nextId = (data.nextId or 1) + 1
    local newArtifact = {
        id = id,
        artifactId = newArtifactId,
        quality = quality,
        valueRatio = ArtifactDefs.rollValueRatio(),
    }
    local threatClearRatio = rollThreatClearValueRatio(newArtifactId, quality)
    if threatClearRatio ~= nil then
        newArtifact.threatClearRatio = threatClearRatio
    end

    table.sort(bagIndices, function(a, b) return a > b end)
    for _, idx in ipairs(bagIndices) do
        table.remove(data.bag, idx)
    end
    data.bag[#data.bag + 1] = newArtifact

    ArtifactSchema.normalizeModule(data)
    PDM.MarkDirty(uid, "artifacts")
    PDM.FlushImmediate(uid)

    print("[ArtifactService] REROLL uid=" .. tostring(uid)
        .. " consumed=" .. tostring(artifactIds[1]) .. "," .. tostring(artifactIds[2])
        .. " srcTypes=" .. tostring(srcType1) .. "," .. tostring(srcType2)
        .. " quality=" .. tostring(quality)
        .. " newType=" .. tostring(newArtifactId)
        .. " newId=" .. tostring(newArtifact.id))

    return true, nil, {
        artifact = newArtifact,
        artifacts = { newArtifact },
        consumedIds = { tostring(artifactIds[1]), tostring(artifactIds[2]) },
    }
end

function ArtifactService.Merge(uid, artifactIds)
    if not artifactIds or #artifactIds ~= 3 then
        return false, "需要提供3个神器ID"
    end

    local data = ensureData(uid)
    if not data then return false, "神器数据未加载" end

    local _artifacts, bagIndices, baseArtifactId, newQuality, err = validateMergeGroup(data, artifactIds, {})
    if err then return false, err end
    local baseQuality = newQuality - 1

    local id = tostring(data.nextId or 1)
    data.nextId = (data.nextId or 1) + 1
    local newArtifact = {
        id = id,
        artifactId = baseArtifactId,
        quality = newQuality,
        valueRatio = ArtifactDefs.rollValueRatio(),
    }
    local threatClearRatio = rollThreatClearValueRatio(baseArtifactId, newQuality)
    if threatClearRatio ~= nil then
        newArtifact.threatClearRatio = threatClearRatio
    end

    table.sort(bagIndices, function(a, b) return a > b end)
    for _, idx in ipairs(bagIndices) do
        table.remove(data.bag, idx)
    end
    data.bag[#data.bag + 1] = newArtifact

    ArtifactSchema.normalizeModule(data)
    PDM.MarkDirty(uid, "artifacts")
    PDM.FlushImmediate(uid)

    print("[ArtifactService] MERGE uid=" .. tostring(uid)
        .. " consumed=" .. tostring(artifactIds[1]) .. "," .. tostring(artifactIds[2]) .. "," .. tostring(artifactIds[3])
        .. " artifactId=" .. tostring(baseArtifactId)
        .. " " .. tostring(baseQuality) .. "→" .. tostring(newQuality)
        .. " newId=" .. tostring(newArtifact.id))

    return true, nil, { artifact = newArtifact, artifacts = { newArtifact }, mergedCount = 1 }
end

function ArtifactService.MergeBatch(uid, artifactIdGroups)
    if not artifactIdGroups or #artifactIdGroups == 0 then
        return false, "暂无可合成神器"
    end

    local data = ensureData(uid)
    if not data then return false, "神器数据未加载" end

    local usedIds = {}
    local allBagIndices = {}
    local plans = {}
    for _, group in ipairs(artifactIdGroups) do
        local _artifacts, bagIndices, baseArtifactId, newQuality, err = validateMergeGroup(data, group, usedIds)
        if err then return false, err end
        for _, idx in ipairs(bagIndices) do
            allBagIndices[#allBagIndices + 1] = idx
        end
        plans[#plans + 1] = {
            consumed = group,
            artifactId = baseArtifactId,
            quality = newQuality,
        }
    end

    table.sort(allBagIndices, function(a, b) return a > b end)
    for _, idx in ipairs(allBagIndices) do
        table.remove(data.bag, idx)
    end

    local newArtifacts = {}
    for _, plan in ipairs(plans) do
        local id = tostring(data.nextId or 1)
        data.nextId = (data.nextId or 1) + 1
        local newArtifact = {
            id = id,
            artifactId = plan.artifactId,
            quality = plan.quality,
            valueRatio = ArtifactDefs.rollValueRatio(),
        }
        local threatClearRatio = rollThreatClearValueRatio(plan.artifactId, plan.quality)
        if threatClearRatio ~= nil then
            newArtifact.threatClearRatio = threatClearRatio
        end
        data.bag[#data.bag + 1] = newArtifact
        newArtifacts[#newArtifacts + 1] = newArtifact
    end

    ArtifactSchema.normalizeModule(data)
    PDM.MarkDirty(uid, "artifacts")
    PDM.FlushImmediate(uid)

    print("[ArtifactService] MERGE_BATCH uid=" .. tostring(uid)
        .. " groups=" .. tostring(#artifactIdGroups)
        .. " rewards=" .. tostring(#newArtifacts))

    return true, nil, { artifacts = newArtifacts, artifact = newArtifacts[1], mergedCount = #newArtifacts }
end

return ArtifactService
