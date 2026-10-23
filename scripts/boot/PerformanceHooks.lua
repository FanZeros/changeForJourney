-- 只包装明确的同步导出函数；不替换require、不追踪业务参数、不重复订阅更新事件。
local Monitor = require("core.PerformanceMonitor")
local M = {}
local hooked = setmetatable({}, { __mode = "k" })
local function hook(module, key, label)
    if type(module) ~= "table" or type(module[key]) ~= "function" then return false end
    local keys = hooked[module]
    if not keys then keys = {}; hooked[module] = keys end
    if keys[key] then return end
    module[key] = Monitor.wrap(label, module[key])
    keys[key] = true
    return true
end
function M.install()
    local modules = {
        { "ui.battle.tri.BattleTriPage", { "update", "draw" }, "三队总览" },
        { "ui.battle.scene.BattleScene", { "update", "draw", "refreshAllyStats" }, "主线战斗" },
        { "ui.battle.scene.BattleView", { "draw" }, "战斗表现" },
        { "ui.battle.combat.BattleEffects", { "update", "draw" }, "战斗特效" },
        { "ui.battle.combat.ProjectileSystem", { "update", "draw" }, "弹道" },
        { "ui.character.panel.CharacterPanel", { "update", "draw", "refreshPower", "getTotalPower" }, "角色面板" },
        { "ui.backpack.BackpackPanel", { "update", "draw" }, "仓库" },
        { "ui.loot.LootBoxPage", { "update", "draw", "refresh" }, "遗匣" },
        { "ui.church.ChurchPage", { "update", "draw" }, "礼拜堂" },
        { "ui.tavern.TavernPage", { "update", "draw" }, "酒馆" },
        { "ui.market.MarketPage", { "update", "draw" }, "黑市" },
        { "ui.dungeon.DungeonBattleScene", { "update", "draw" }, "副本战斗" },
        { "ui.tower.TowerBattleScene", { "update", "draw" }, "通天塔" },
        { "ui.battle.stage.SweepDialog", { "update", "draw", "drawPending" }, "扫荡界面" },
        { "systems.EquipmentSystem", { "applyEquip", "generate", "hydrateInventory" }, "装备计算" },
        { "systems.EquipmentPower", { "buildContext", "buildWornContext", "evaluateLoadout", "score", "genericScore" }, "装备战力" },
        { "systems.CombatPowerEstimate", { "estimate" }, "战力估算" },
        { "runtime.LocalActionBridge", { "dispatch", "updateQuickEquip", "updateSweep" }, "本地动作" },
        { "runtime.ClientDispatcher", { "set", "handleStateUpdate" }, "数据同步" },
        { "boot.StandaloneSave", { "Update", "Flush" }, "存档" },
    }
    local count = 0
    -- 只处理已加载模块，不能诊断安装时主动载入整个游戏或提前初始化。
    for _, spec in ipairs(modules) do
        local module = package.loaded[spec[1]]
        if type(module) == "table" then
            for _, key in ipairs(spec[2]) do
                if hook(module, key, spec[3] .. "." .. key) then count = count + 1 end
            end
        end
    end
    print("[Performance] 已接入同步分段 " .. count .. " 个；GPU未启用，不修改业务时钟")
end
return M
