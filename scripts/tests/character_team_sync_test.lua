-- 单机跨队编队同步回归：交换必须保留双方、空槽位置和未上阵名册。
function Start()
    local dispatcher = require("runtime.ClientDispatcher")
    local bridge = require("runtime.LocalActionBridge")
    local pdm = require("rules.character.PlayerDataManager")
    local oldGet, oldMarkDirty = pdm.GetModule, pdm.MarkDirty
    local oldModules = dispatcher.getAll()
    local oldHeroes, oldPlayer = oldModules.heroes, oldModules.player
    local pushes = 0
    local heroes = {
        roster = { [1] = { level = 2 }, [2] = { level = 3 }, [25] = { level = 7 } },
        deployed = { 1, 0, 0, 0 },
        teams = { { slots = { 1, 0, 0, 0 } }, { slots = { 2, 0, 0, 0 } }, { slots = {} } },
    }
    oldModules.heroes = heroes
    oldModules.player = { level = 100 }
    pdm.MarkDirty = function(_, key)
        assert(key == "heroes", "仅同步英雄模块")
        pushes = pushes + 1
        dispatcher.set("heroes", heroes)
    end
    local ok, reason = bridge.setTeams({
        [1] = { 2, 0, 0, 0 }, [2] = { 1, 0, 0, 0 },
    })
    assert(ok, tostring(reason))
    assert(pushes == 1, "跨队交换只推送一次，不得先推送不完整阵容")
    assert(heroes.deployed[1] == 2 and heroes.teams[1].slots[1] == 2, "队1保持交换结果")
    assert(heroes.teams[2].slots[1] == 1, "队2保持交换结果")
    assert(heroes.teams[2].slots[2] == 0 and heroes.roster[25].level == 7,
        "空槽与未上阵英雄保持不变")
    local before = pushes
    local failed = bridge.setTeams({ [1] = { 25, 0, 0, 0 }, [2] = { 25, 0, 0, 0 } })
    assert(not failed and pushes == before, "重复英雄应拒绝且不推送")
    assert(heroes.deployed[1] == 2 and heroes.teams[2].slots[1] == 1,
        "失败事务不得污染原编队")
    pdm.GetModule, pdm.MarkDirty = oldGet, oldMarkDirty
    oldModules.heroes, oldModules.player = oldHeroes, oldPlayer
    print("[character_team_sync_test] PASS: atomic swap, roster, empty slot, reject")
end
