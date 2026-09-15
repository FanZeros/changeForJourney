#!/usr/bin/env lua
-- 特权里程补差逻辑单测（无引擎依赖）
-- 运行: lua scripts/tests/privilege_mile_compensate_test.lua

do
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local testDir = src:match("(.+[\\/])") or "./"
    local root = testDir:gsub("scripts[\\/]tests[\\/]$", ""):gsub("scripts/tests/$", "")
    package.path = root .. "scripts/?.lua;" .. root .. "scripts/?/init.lua;" .. package.path
end

local Logic = require("server.market.PrivilegeMileCompLogic")

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertEq", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(v, msg)
    if not v then error(msg or "assertTrue failed") end
end

local function assertFalse(v, msg)
    if v then error(msg or "assertFalse failed") end
end

-- isPrivilegeMileClaimed
assertTrue(Logic.isPrivilegeMileClaimed({ [10] = true }, 10), "number key")
assertTrue(Logic.isPrivilegeMileClaimed({ ["10"] = true }, 10), "string key")
assertTrue(Logic.isPrivilegeMileClaimed({ 10, 20 }, 10), "array format")
assertFalse(Logic.isPrivilegeMileClaimed({ [10] = true }, 20), "wrong threshold")
assertFalse(Logic.isPrivilegeMileClaimed(nil, 10), "nil claimed")

-- calcCompensationAmount
local all, allDetail = Logic.calcCompensationAmount({ [10] = true, [20] = true, [30] = true })
assertEq(all, 9, "all three tiers")
assertTrue(allDetail:find("10:%+2") ~= nil, "detail has 10")
assertTrue(allDetail:find("30:%+5") ~= nil, "detail has 30")

local one = Logic.calcCompensationAmount({ [10] = true })
assertEq(one, 2, "only tier 10")

local two = Logic.calcCompensationAmount({ [20] = true, [30] = true })
assertEq(two, 7, "tier 20+30")

assertEq(Logic.calcCompensationAmount({}), 0, "empty claimed")
assertEq(Logic.calcCompensationAmount(nil), 0, "nil claimed")

-- clearThresholdClaim / v3 25 档迁移
local mixed = { [10] = true, [25] = true, "20" }
Logic.clearThresholdClaim(mixed, 25)
assertTrue(Logic.isPrivilegeMileClaimed(mixed, 10), "keep 10")
assertFalse(Logic.isPrivilegeMileClaimed(mixed, 25), "clear 25 map key")

local arr = { 5, 25, 30 }
Logic.clearThresholdClaim(arr, 25)
assertEq(#arr, 2, "array length after remove 25")
assertTrue(Logic.isPrivilegeMileClaimed(arr, 5), "keep 5 in array")
assertFalse(Logic.isPrivilegeMileClaimed(arr, 25), "clear 25 in array")

local priv = { watchCount = 28, claimed = { [25] = true, [20] = true } }
Logic.resetPrivilegeMileProgressForRewardBump(priv)
assertEq(priv.watchCount, 28, "watchCount preserved")
assertFalse(Logic.isPrivilegeMileClaimed(priv.claimed, 25), "reset clears 25 only")
assertTrue(Logic.isPrivilegeMileClaimed(priv.claimed, 20), "reset keeps 20")

local privV5 = { watchCount = 30, claimed = { [5] = true, [10] = true, [15] = true, [20] = true, [25] = true, [30] = true } }
Logic.resetPrivilegeMileProgressForV5(privV5)
assertEq(privV5.watchCount, 30, "v5 watchCount preserved")
assertFalse(Logic.isPrivilegeMileClaimed(privV5.claimed, 5), "v5 clears 5")
assertFalse(Logic.isPrivilegeMileClaimed(privV5.claimed, 10), "v5 clears 10")
assertFalse(Logic.isPrivilegeMileClaimed(privV5.claimed, 15), "v5 clears 15")
assertFalse(Logic.isPrivilegeMileClaimed(privV5.claimed, 20), "v5 clears 20")
assertFalse(Logic.isPrivilegeMileClaimed(privV5.claimed, 25), "v5 clears 25")
assertTrue(Logic.isPrivilegeMileClaimed(privV5.claimed, 30), "v5 keeps 30")

-- 旧版等额不应补（防御：若 NEW==OLD 则 diff=0）
for th, old in pairs(Logic.OLD_PRIVILEGE_MILE_POINTS) do
    local new = Logic.NEW_PRIVILEGE_MILE_POINTS[th]
    assertTrue(new > old, "new amount must exceed old for tier " .. th)
end

print("[privilege_mile_compensate_test] ALL PASSED (" .. tostring(all) .. " max comp)")
