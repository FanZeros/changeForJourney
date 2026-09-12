#!/usr/bin/env lua
-- 冒险等级 200 级上限回归测试（无引擎依赖）
do
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local testDir = src:match("(.+[\\/])") or "./"
    local root = testDir:gsub("scripts[\\/]tests[\\/]$", ""):gsub("scripts/tests/$", "")
    package.path = root .. "scripts/?.lua;" .. root .. "scripts/?/init.lua;" .. package.path
end

local ExpTable = require("config.ExpTable")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
    end
end

assertEq(ExpTable.PLAYER_MAX_LEVEL, 200, "player max level")
assertEq(ExpTable.HERO_MAX_LEVEL, 200, "hero max level unchanged")
assertEq(ExpTable.getPlayerExpForLevel(149), 4037866344, "149 to 150 exp preserved")
assertEq(ExpTable.getPlayerExpForLevel(150), 4133513940, "150 to 151 exp")
assertEq(ExpTable.getPlayerExpForLevel(199), 11116952945, "199 to 200 exp")
assertEq(ExpTable.getPlayerExpForLevel(200), nil, "level 200 has no next exp")
assertEq(ExpTable.isPlayerMaxLevel(199), false, "level 199 not max")
assertEq(ExpTable.isPlayerMaxLevel(200), true, "level 200 max")
assertEq(ExpTable.getEnhanceLevelCap(200), 200, "enhance cap follows player level")
assertEq(ExpTable.getLevelUnlocks(151)[1].unlockName, "装备强化上限+1", "level 151 unlock")
assertEq(ExpTable.getLevelUnlocks(200)[1].unlockName, "装备强化上限+1", "level 200 unlock")

local player = {
    level = 150,
    exp = ExpTable.getPlayerExpForLevel(150),
    maxExp = 0,
}
ExpTable.autoLevelUpPlayer(player)
assertEq(player.level, 151, "old max-level player can continue leveling")
assertEq(player.exp, 0, "level-up exp consumed")
assertEq(player.maxExp, ExpTable.getPlayerExpForLevel(151), "next max exp refreshed")

local maxPlayer = {
    level = 199,
    exp = ExpTable.getPlayerExpForLevel(199),
    maxExp = ExpTable.getPlayerExpForLevel(199),
}
ExpTable.autoLevelUpPlayer(maxPlayer)
assertEq(maxPlayer.level, 200, "player reaches level 200")
assertEq(maxPlayer.exp, 0, "max-level exp cleared")
assertEq(maxPlayer.maxExp, 0, "max-level maxExp cleared")

print("[player_level_200_test] ALL PASSED")
