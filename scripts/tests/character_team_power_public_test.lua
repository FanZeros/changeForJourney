-- 真实角色面板接线：三队runtime战力、活动队切换与重置，不加载main或真实存档。
local Dispatcher = require("runtime.ClientDispatcher")
local Store = require("core.PlayerStore")
local CP = require("ui.character.panel.CharacterPanel")
local GameState = require("core.GameState")
local TE = require("systems.TalentEffect")
local EventBus = require("core.EventBus")
local GameEvents = require("config.GameEvents")
local failures, assertions = 0, 0
local function check(ok, label)
    assertions = assertions + 1
    if ok then print("[PASS] " .. label)
    else failures = failures + 1; print("[FAIL] " .. label) end
end

function Start()
    local ok, err = pcall(function()
        Store.Init()
        ---@type number[][]
        local snapshots = {}
        ---@type number[]
        local legacy = {}
        ---@type boolean[]
        local readyStates = {}
        EventBus.on(GameEvents.TEAM_POWER_CHANGED, function(data)
            snapshots[#snapshots + 1] = { data.powers[1], data.powers[2], data.powers[3] }
            readyStates[#readyStates + 1] = data.ready
        end)
        EventBus.on(GameEvents.PLAYER_POWER_CHANGED, function(data)
            legacy[#legacy + 1] = data.power
        end)
        CP.refreshPower()
        check(readyStates[#readyStates] == false, "开机无英雄数据的快照明确未就绪")
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
        check(#snapshots > 0, "真实CP刷新发布专用三队快照")
        check(readyStates[#readyStates] == true, "真实英雄水合后快照才标记就绪")
        local before = assert(snapshots[#snapshots], "缺三队初始快照")
        for t = 1, 3 do
            check(before[t] == CP.getTotalPower(t), "快照队" .. t .. "等于正式缓存总战力")
        end
        local oldSnapshotCount, oldLegacyCount = #snapshots, #legacy
        heroes.roster[2].level = 71
        Dispatcher.handleStateUpdate(cjson.encode({ modules = { heroes = heroes } }))
        CP.setHeroesData(Dispatcher.get("heroes"))
        CP.refreshPower()
        local after = assert(snapshots[#snapshots], "缺二队成长快照")
        check(#snapshots > oldSnapshotCount and after[2] > before[2], "仅二队英雄升级也发布二队增长")
        check(after[1] == before[1] and after[3] == before[3], "二队成长不伪造一三队增长")
        check(#legacy == oldLegacyCount and GameState.getPower() == before[1],
            "一队未变时兼容事件不重发且顶栏口径不变")
        local repeatCount = #snapshots
        CP.refreshPower()
        local repeated = assert(snapshots[#snapshots], "缺重复刷新快照")
        check(#snapshots == repeatCount + 1 and repeated[1] == after[1]
            and repeated[2] == after[2] and repeated[3] == after[3], "重复刷新完整快照数值不重复增长")
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
