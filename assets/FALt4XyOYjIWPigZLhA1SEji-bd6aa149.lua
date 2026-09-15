-- ============================================================================
-- ArtifactSchema.lua — 神器模块 Schema
-- ============================================================================

local ArtifactSchema = {}
local ArtifactDefs = require("shared.artifact.ArtifactDefs")

ArtifactSchema.SLOT_COUNT = 4
ArtifactSchema.SUB_SLOT_COUNT = 3
ArtifactSchema.SECOND_SLOT_UNLOCK_LEVEL = 40
ArtifactSchema.THIRD_SLOT_UNLOCK_LEVEL = 80

function ArtifactSchema.getUnlockedSubSlotCount(playerLevel)
    playerLevel = tonumber(playerLevel) or 1
    if playerLevel >= ArtifactSchema.THIRD_SLOT_UNLOCK_LEVEL then
        return 3
    end
    if playerLevel >= ArtifactSchema.SECOND_SLOT_UNLOCK_LEVEL then
        return 2
    end
    return 1
end

function ArtifactSchema.getSubSlotUnlockLevel(subSlot)
    subSlot = tonumber(subSlot) or 1
    if subSlot <= 1 then return 1 end
    if subSlot == 2 then return ArtifactSchema.SECOND_SLOT_UNLOCK_LEVEL end
    if subSlot == 3 then return ArtifactSchema.THIRD_SLOT_UNLOCK_LEVEL end
    return nil
end

local function isValidIndex(value, maxValue)
    if value == nil or value ~= value
        or value == math.huge or value == -math.huge then
        return false
    end
    return value == math.floor(value) and value >= 1 and value <= maxValue
end

function ArtifactSchema.getEquippedId(data, slot, subSlot)
    if type(data) ~= "table" or type(data.equipped) ~= "table" then return nil end
    slot = tonumber(slot)
    subSlot = tonumber(subSlot) or 1
    if not isValidIndex(slot, ArtifactSchema.SLOT_COUNT)
        or not isValidIndex(subSlot, ArtifactSchema.SUB_SLOT_COUNT) then
        return nil
    end
    local row = data.equipped[slot] or data.equipped[tostring(slot)]
    if type(row) == "table" then
        return row[subSlot] or row[tostring(subSlot)]
    end
    if subSlot == 1 then
        return row
    end
    return nil
end

function ArtifactSchema.setEquippedId(data, slot, subSlot, artifactId)
    if type(data) ~= "table" then return end
    data.equipped = data.equipped or {}
    slot = tonumber(slot)
    subSlot = tonumber(subSlot) or 1
    if not isValidIndex(slot, ArtifactSchema.SLOT_COUNT)
        or not isValidIndex(subSlot, ArtifactSchema.SUB_SLOT_COUNT) then
        return
    end
    local row = {}
    local function mergeRow(src)
        if type(src) == "table" then
            for i = 1, ArtifactSchema.SUB_SLOT_COUNT do
                local id = src[i] or src[tostring(i)]
                if id ~= nil and tostring(id) ~= "" then
                    row[i] = tostring(id)
                end
            end
        elseif src ~= nil and tostring(src) ~= "" then
            row[1] = row[1] or tostring(src)
        end
    end
    mergeRow(data.equipped[slot])
    mergeRow(data.equipped[tostring(slot)])
    data.equipped[slot] = row
    data.equipped[tostring(slot)] = nil
    if artifactId == nil or tostring(artifactId) == "" then
        row[subSlot] = nil
        if not next(row) then
            data.equipped[slot] = nil
        end
    else
        row[subSlot] = tostring(artifactId)
    end
end

function ArtifactSchema.findEquippedSlot(data, artifactId)
    artifactId = tostring(artifactId or "")
    if artifactId == "" or type(data) ~= "table" or type(data.equipped) ~= "table" then return nil, nil end
    for slot = 1, ArtifactSchema.SLOT_COUNT do
        local row = data.equipped[slot] or data.equipped[tostring(slot)]
        if type(row) == "table" then
            for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
                local id = row[subSlot] or row[tostring(subSlot)]
                if tostring(id or "") == artifactId then
                    return slot, subSlot
                end
            end
        elseif tostring(row or "") == artifactId then
            return slot, 1
        end
    end
    return nil, nil
end

local function normalizeCountMap(map)
    local fixed = {}
    if type(map) == "table" then
        for k, v in pairs(map) do
            fixed[tostring(k)] = math.max(0, math.floor(tonumber(v) or 0))
        end
    end
    return fixed
end

local function normalizeDrawStats(stats)
    if type(stats) ~= "table" then stats = {} end
    stats.total = math.max(0, math.floor(tonumber(stats.total) or 0))
    stats.single = math.max(0, math.floor(tonumber(stats.single) or 0))
    stats.ten = math.max(0, math.floor(tonumber(stats.ten) or 0))
    stats.byQuality = normalizeCountMap(stats.byQuality)
    stats.byArtifactId = normalizeCountMap(stats.byArtifactId)
    return stats
end

local function normalizeArtifact(raw, ratioMode)
    if type(raw) ~= "table" then return nil end

    local id = raw.id or raw.i or raw[1]
    if id == nil then return nil end

    local artifact = {
        id = tostring(id),
        artifactId = tonumber(raw.artifactId) or tonumber(raw.type) or tonumber(raw.a) or tonumber(raw[2]) or 1,
        quality = math.floor(tonumber(raw.quality) or tonumber(raw.q) or tonumber(raw[3]) or 1),
    }

    local storedValue = raw.valueRatio or raw.vr
    if storedValue == nil and ratioMode then storedValue = raw[4] end
    if storedValue ~= nil then
        artifact.valueRatio = tonumber(storedValue) or 0
    else
        artifact.value = tonumber(raw.value) or tonumber(raw.v) or tonumber(raw[4]) or 0
    end

    local threatClearStored = raw.threatClearRatio or raw.tcr
    if threatClearStored == nil and ratioMode then threatClearStored = raw[5] end
    if threatClearStored ~= nil then
        artifact.threatClearRatio = tonumber(threatClearStored) or 0
    else
        local threatClearValue = raw.threatClearValue or raw.threatClear or raw.tc or raw[5]
        if threatClearValue ~= nil then
            artifact.threatClearValue = tonumber(threatClearValue) or 0
        end
    end

    ArtifactDefs.normalizeInstanceValue(artifact)
    return artifact
end

local function normalizeBag(list, ratioMode)
    if type(list) ~= "table" then return {} end
    local dense = {}
    for _, a in pairs(list) do
        local artifact = normalizeArtifact(a, ratioMode)
        if artifact then
            dense[#dense + 1] = artifact
        end
    end
    table.sort(dense, function(a, b)
        local qa, qb = tonumber(a.quality) or 1, tonumber(b.quality) or 1
        if qa ~= qb then return qa > qb end
        return tonumber(a.id) > tonumber(b.id)
    end)
    return dense
end

function ArtifactSchema.normalizeModule(data)
    if type(data) ~= "table" then return end
    if data.b ~= nil then data.bag = data.b end
    if data.e ~= nil then data.equipped = data.e end
    if data.n ~= nil then data.nextId = data.n end
    if data.r ~= nil then data.pityRare = data.r end
    if data.p ~= nil then data.pityEpic = data.p end
    if data.t ~= nil then data.totalDraws = data.t end
    if data.s ~= nil then data.drawStats = data.s end
    if data.df ~= nil then data.dailyFreeDrawDayId = data.df end
    local ratioMode = data.av == 1 or data.av == true or data.valueMode == "ratio"

    if not data.bag then data.bag = {} end
    if not data.equipped then data.equipped = {} end
    if not data.nextId then data.nextId = 1 end
    if not data.pityRare then data.pityRare = 0 end
    if not data.pityEpic then data.pityEpic = 0 end
    if not data.totalDraws then data.totalDraws = 0 end
    if data.dailyFreeDrawDayId == nil then data.dailyFreeDrawDayId = 0 end
    data.drawStats = normalizeDrawStats(data.drawStats)

    data.nextId = math.max(1, math.floor(tonumber(data.nextId) or 1))
    data.pityRare = math.max(0, math.floor(tonumber(data.pityRare) or 0))
    data.pityEpic = math.max(0, math.floor(tonumber(data.pityEpic) or 0))
    data.totalDraws = math.max(0, math.floor(tonumber(data.totalDraws) or 0))
    data.dailyFreeDrawDayId = math.max(0, math.floor(tonumber(data.dailyFreeDrawDayId) or 0))
    data.bag = normalizeBag(data.bag, ratioMode)
    data.valueMode = "ratio"

    local bagById = {}
    for _, artifact in ipairs(data.bag) do
        local id = tostring(artifact.id or "")
        if id ~= "" and not bagById[id] then
            bagById[id] = artifact
        end
    end

    local fixedEquipped = {}
    local usedEquippedIds = {}
    for slot = 1, ArtifactSchema.SLOT_COUNT do
        local v = data.equipped[slot] or data.equipped[tostring(slot)]
        local row = {}
        local slotTypes = {}
        local function keepEquippedId(subSlot, id)
            id = tostring(id or "")
            local artifact = bagById[id]
            if id == "" or not artifact or usedEquippedIds[id] then
                return
            end
            local artifactType = tonumber(artifact.artifactId) or 0
            if artifactType > 0 and slotTypes[artifactType] then
                return
            end
            usedEquippedIds[id] = true
            if artifactType > 0 then slotTypes[artifactType] = true end
            row[subSlot] = id
        end
        if type(v) == "table" then
            for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
                local id = v[subSlot] or v[tostring(subSlot)]
                if id ~= nil and tostring(id) ~= "" then
                    keepEquippedId(subSlot, id)
                end
            end
        elseif v ~= nil and tostring(v) ~= "" then
            keepEquippedId(1, v)
        end
        if next(row) then fixedEquipped[slot] = row end
    end
    data.equipped = fixedEquipped

    data.b = nil
    data.e = nil
    data.n = nil
    data.r = nil
    data.p = nil
    data.t = nil
    data.s = nil
    data.df = nil
    data.av = nil
end

function ArtifactSchema.dehydrateModule(data)
    if type(data) ~= "table" then return data end
    ArtifactSchema.normalizeModule(data)

    local leanBag = {}
    for i, artifact in ipairs(data.bag or {}) do
        local row = {
            tonumber(artifact.id) or artifact.id,
            tonumber(artifact.artifactId) or 1,
            tonumber(artifact.quality) or 1,
            tonumber(artifact.valueRatio) or 0,
        }
        if artifact.threatClearRatio ~= nil then
            row[5] = tonumber(artifact.threatClearRatio) or 0
        end
        leanBag[i] = row
    end

    local leanEquipped = {}
    for slot, row in pairs(data.equipped or {}) do
        local leanRow = {}
        if type(row) == "table" then
            for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
                local id = row[subSlot] or row[tostring(subSlot)]
                if id ~= nil and tostring(id) ~= "" then
                    leanRow[tostring(subSlot)] = tonumber(id) or id
                end
            end
        elseif row ~= nil and tostring(row) ~= "" then
            leanRow["1"] = tonumber(row) or row
        end
        if next(leanRow) then
            leanEquipped[tostring(slot)] = leanRow
        end
    end

    return {
        av = 1,
        b = leanBag,
        e = leanEquipped,
        n = tonumber(data.nextId) or 1,
        r = tonumber(data.pityRare) or 0,
        p = tonumber(data.pityEpic) or 0,
        t = tonumber(data.totalDraws) or 0,
        s = data.drawStats,
        df = tonumber(data.dailyFreeDrawDayId) or 0,
    }
end

ArtifactSchema.Fields = {
    artifacts = {
        pdmKey     = "Artifacts",
        type       = "json",
        scope      = "server",
        persist    = { via = "cloud", cloudKey = "mod_artifacts" },
        getDefault = function()
            return {
                bag        = {},
                equipped   = {},
                nextId     = 1,
                pityRare   = 0,
                pityEpic   = 0,
                totalDraws = 0,
                dailyFreeDrawDayId = 0,
                drawStats  = {},
            }
        end,
        onLoad = function(data)
            ArtifactSchema.normalizeModule(data)
        end,
        onSave = function(data)
            return ArtifactSchema.dehydrateModule(data)
        end,
        desc = "神器背包/装配/抽取保底",
    },
}

return ArtifactSchema
