#!/usr/bin/env lua
-- 神器第三栏位 Schema 回归测试（无引擎依赖）
-- 运行: lua scripts/tests/artifact_third_subslot_test.lua

do
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local testDir = src:match("(.+[\\/])") or "./"
    local root = testDir:gsub("scripts[\\/]tests[\\/]$", ""):gsub("scripts/tests/$", "")
    package.path = root .. "scripts/?.lua;" .. root .. "scripts/?/init.lua;" .. package.path
end

local ArtifactSchema = require("shared.artifact.ArtifactSchema")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
    end
end

assertEq(ArtifactSchema.SUB_SLOT_COUNT, 3, "sub slot count")
assertEq(ArtifactSchema.getUnlockedSubSlotCount(1), 1, "level 1 slots")
assertEq(ArtifactSchema.getUnlockedSubSlotCount(39), 1, "level 39 slots")
assertEq(ArtifactSchema.getUnlockedSubSlotCount(40), 2, "level 40 slots")
assertEq(ArtifactSchema.getUnlockedSubSlotCount(79), 2, "level 79 slots")
assertEq(ArtifactSchema.getUnlockedSubSlotCount(80), 3, "level 80 slots")
assertEq(ArtifactSchema.getSubSlotUnlockLevel(3), 80, "third slot unlock level")

local data = {
    bag = {
        { id = "101", artifactId = 1, quality = 1, valueRatio = 5000 },
        { id = "102", artifactId = 2, quality = 1, valueRatio = 5000 },
        { id = "103", artifactId = 3, quality = 1, valueRatio = 5000 },
    },
    equipped = {},
}
ArtifactSchema.setEquippedId(data, 1, 1, "101")
ArtifactSchema.setEquippedId(data, 1, 2, "102")
ArtifactSchema.setEquippedId(data, 1, 3, "103")
assertEq(ArtifactSchema.getEquippedId(data, 1, 3), "103", "third slot read")
local slot, subSlot = ArtifactSchema.findEquippedSlot(data, "103")
assertEq(slot, 1, "third slot owner")
assertEq(subSlot, 3, "third slot index")

local saved = ArtifactSchema.dehydrateModule({
    bag = {},
    equipped = data.equipped,
    nextId = 1,
    pityRare = 0,
    pityEpic = 0,
    totalDraws = 0,
    drawStats = {},
})
assertEq(saved.e["1"]["3"], 103, "third slot persisted")

local loaded = { b = saved.b, e = saved.e }
ArtifactSchema.normalizeModule(loaded)
assertEq(ArtifactSchema.getEquippedId(loaded, 1, 3), "103", "third slot normalized")

ArtifactSchema.setEquippedId(loaded, 1, 3, nil)
assertEq(ArtifactSchema.getEquippedId(loaded, 1, 3), nil, "third slot unequip")
assertEq(ArtifactSchema.getEquippedId(loaded, 1, 1), "101", "first slot preserved")
assertEq(ArtifactSchema.getEquippedId(loaded, 1, 2), "102", "second slot preserved")

local repaired = {
    bag = {
        { id = "201", artifactId = 7, quality = 1, valueRatio = 5000 },
        { id = "202", artifactId = 7, quality = 1, valueRatio = 5000 },
        { id = "203", artifactId = 8, quality = 1, valueRatio = 5000 },
    },
    e = {
        ["1"] = { ["1"] = "201", ["2"] = "202", ["3"] = "999" },
        ["2"] = { ["1"] = "201", ["2"] = "203" },
        ["1.5"] = { ["1"] = "203" },
    },
}
ArtifactSchema.normalizeModule(repaired)
assertEq(ArtifactSchema.getEquippedId(repaired, 1, 1), "201", "repair keeps first valid reference")
assertEq(ArtifactSchema.getEquippedId(repaired, 1, 2), nil, "repair removes same-type duplicate")
assertEq(ArtifactSchema.getEquippedId(repaired, 1, 3), nil, "repair removes missing bag reference")
assertEq(ArtifactSchema.getEquippedId(repaired, 2, 1), nil, "repair removes duplicate instance reference")
assertEq(ArtifactSchema.getEquippedId(repaired, 2, 2), "203", "repair keeps valid second-slot reference")
assertEq(ArtifactSchema.getEquippedId(repaired, 1.5, 1), nil, "fractional slot rejected")

local invalidIndexData = { equipped = {} }
ArtifactSchema.setEquippedId(invalidIndexData, 1.5, 1, "301")
ArtifactSchema.setEquippedId(invalidIndexData, 1, 2.5, "302")
assertEq(next(invalidIndexData.equipped), nil, "fractional set rejected")

print("[artifact_third_subslot_test] ALL PASSED")
