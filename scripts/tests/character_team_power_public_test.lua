-- 真实角色面板接线：三队runtime战力、活动队切换与重置，不加载main或真实存档。
local Dispatcher = require("runtime.ClientDispatcher")
local Store = require("core.PlayerStore")
local CP = require("ui.character.panel.CharacterPanel")
local GameState = require("core.GameState")
local TE = require("systems.TalentEffect")
local failures, assertions = 0, 0
local function check(ok, label)
    assertions = assertions + 1
    if ok then print("[PASS] " .. label)
    else failures = failures + 1; print("[FAIL] " .. label) end
end

function Start()
    local ok, err = pcall(function()
        Store.Init()
        local heroes = { roster = {}, deployed = { 1, 0, 0, 0 }, teams = {
            { slots = { 1, 0, 0, 0 } }, { slots = { 2, 0, 3, 0 } },
            { slots = { 5, 6, 7, 0 } },
        } }
        for _, id in ipairs({ 1, 2, 3, 5, 6, 7, 8 }) do
            heroes.roster[id] = { level = 70, awakening = {}, extraTalent = {} }
        end
        Dispatcher.handleStateUpdate(cjson.encode({ modules = { player = { level = 70 },
            battle = { clearedStages = { ["905"] = true, ["1905"] = true }, maxStageId = 1905 },
            heroes = heroes, equipment = { inventory = {}, equipped = {} },
            artifacts = { bag = {}, equippedByTeam = {} }, talents = { litNodes = { 113, 124 } } } }))
        GameState.setLevel(70)
        CP.setHeroesData(Dispatcher.get("heroes"))
        CP.refreshPower()
        local share = TE.calcRuntimeOnlyPower(assert(Dispatcher.get("talents")).litNodes)
        check(share > 0, "runtime份额为真实非零节点")
        for t, count in ipairs({ 1, 2, 3 }) do
            check(CP.setActiveTeam(t), "切活动队" .. t .. "成功")
            local slots, cache = CP.getTeamSlotsData()
            local sum = 0
            for i = 1, 4 do sum = sum + (cache[i] or 0) end
            check(CP.getTotalPower() == sum + share * count,
                "活动队" .. t .. "总战力只加本队" .. count .. "人runtime")
            check(CP.getTotalPower(t) == CP.getTotalPower(), "显式队与活动队总战力同源")
        end
        check(GameState.getPower() == CP.getTotalPower(1), "活动队3时顶栏GameState仍为队1总战力")
        local slot, team = CP.getHeroDeployPosition(3)
        check(slot == 3 and team == 2, "真实CP公开所属队与真实槽3")
        check(CP.getHeroDeployPosition(8) == nil and CP.getHeroDeployPosition(3, 1) == nil,
            "未编队与指定错误队不借活动队号位")
        heroes.teams[2].slots = { 0, 0, 0, 0 }
        Dispatcher.handleStateUpdate(cjson.encode({ modules = { heroes = heroes } }))
        CP.setHeroesData(Dispatcher.get("heroes"))
        CP.setActiveTeam(2)
        check(CP.getTotalPower() == 0, "清空活动队后总战力为0，不残留队1runtime")
        CP.resetSessionData()
        check(CP.getTotalPower(1) == 0 and CP.getTotalPower(2) == 0 and CP.getTotalPower(3) == 0,
            "会话重置同步清理三队槽位和runtime缓存")
    end)
    if not ok then check(false, "异常: " .. tostring(err)) end
    print(string.format("[character_team_power_public_test] %s assertions=%d failures=%d",
        failures == 0 and "ALL PASS" or "FAIL", assertions, failures))
    engine:Exit()
end
