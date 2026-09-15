#!/usr/bin/env lua
-- 已结束挑战者区特权卡转出流程契约测试（无引擎依赖）
-- 运行: lua scripts/tests/closed_challenger_transfer_test.lua

do
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local testDir = src:match("(.+[\\/])") or "./"
    local root = testDir:gsub("scripts[\\/]tests[\\/]$", ""):gsub("scripts/tests/$", "")
    package.path = root .. "scripts/?.lua;" .. root .. "scripts/?/init.lua;" .. package.path
end

local Protocol = require("shared.Protocol")
local ServerListConfig = require("shared.ServerListConfig")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if not value then error(message) end
end

local action = Protocol.ACTION_TYPES.TRANSFER_CLOSED_CHALLENGER_CARD
assertEq(action, "transfer_closed_challenger_card", "closed transfer action")
assertTrue(ServerListConfig.isChallengerServer(901), "901 must be a challenger server")
assertTrue(ServerListConfig.isServerClosed(901, 1784476800), "901 must be closed at closeTime")
assertTrue(not ServerListConfig.isServerClosed(901, 1784476799), "901 must be open before closeTime")
assertEq(ServerListConfig.getKeyPrefix(901) .. "mod_currency", "s901_mod_currency", "source currency key")

print("[closed_challenger_transfer_test] ALL PASSED")
