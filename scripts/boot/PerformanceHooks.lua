-- 只包装明确的同步导出函数；不替换require、不追踪业务参数、不重复订阅更新事件。
local Monitor = require("core.PerformanceMonitor")
local M = {}
-- UrhoX 的 require 缓存不保证暴露在 package.loaded；由宿主传入它实际持有的模块表。
-- 这里只保留引用，不主动 require 业务模块，也不读取任何玩家字段。
---@type table<string, table>
local registered = {}
function M.register(modules)
    for name, module in pairs(modules) do
        if type(name) == "string" and type(module) == "table" then registered[name] = module end
    end
end
function M.getModule(name)
    if registered[name] then return registered[name] end
    local module = package and package.loaded and package.loaded[name]
    return type(module) == "table" and module or nil
end
-- 仅固定协议枚举可成为标签；不记录动作参数、英雄/装备ID或自定义模块名。
local actionLabels = {
    equip_item = "穿戴", unequip_item = "卸下", unequip_all = "一键卸下",
    equip_all_best = "一键装备", toggle_equip_lock = "装备锁定",
    enhance_equip = "强化", enhance_equip_max = "批量强化",
    refine_equip = "洗练", refine_replace = "替换洗练", decompose_equip = "分解",
    set_team = "编队", set_deployed = "编队", deploy_hero = "上阵", undeploy_hero = "下阵",
    level_up_hero = "英雄升级", sync_extra_talent = "成长同步",
    activate_talent = "激活天赋", reset_talents = "重置天赋", reset_single_talent = "重置单天赋",
    advance_class = "转职", reset_class = "重置转职", activate_awakening = "觉醒",
    PreviewInventoryCuration = "优选预览", ApplyInventoryCuration = "确认优选",
    CancelInventoryCuration = "取消优选",
}
local moduleLabels = { heroes = "英雄", equipment = "装备", artifacts = "神器",
    talents = "天赋", player = "玩家进度", currency = "货币", battle = "战斗进度",
    lootbox = "遗匣", dungeon = "副本", task = "任务", slotEnhance = "栏位强化" }
local function classifiedWrap(label, fn, labels)
    local byName = {}
    for key, value in pairs(labels) do byName[key] = Monitor.wrap(label .. "." .. value, fn) end
    local other = Monitor.wrap(label .. ".其他", fn)
    return function(name, ...)
        if not Monitor.isEnabled() then return fn(name, ...) end
        return (byName[name] or other)(name, ...)
    end
end
local hooked = setmetatable({}, { __mode = "k" })
local function hook(module, key, label, labels)
    if type(module) ~= "table" or type(module[key]) ~= "function" then return false end
    local keys = hooked[module]
    if not keys then keys = {}; hooked[module] = keys end
    if keys[key] == module[key] then return false end
    local original = module[key]
    local wrapped = Monitor.wrap(label, labels and classifiedWrap(label, original, labels) or original)
    module[key] = wrapped
    keys[key] = wrapped
    return true
end
local function install()
    local modules = {
        { "ui.battle.tri.BattleTriPage", { "update", "draw", "drawL1Underlay", "drawL0", "drawHud", "refreshHeroProgressTeams" }, "三队总览" },
        { "ui.battle.scene.BattleScene", { "update", "draw", "refreshAllyStats" }, "主线战斗" },
        { "ui.battle.scene.BattleView", { "draw" }, "战斗表现" },
        { "ui.battle.combat.BattleEffects", { "update", "draw" }, "战斗特效" },
        { "ui.battle.combat.ProjectileSystem", { "update", "draw" }, "弹道" },
        { "ui.character.panel.CharacterPanel", { "update", "updateBadges", "draw", "refreshPower", "getTotalPower", "addHeroesExp", "patchExtraTalent", "finishExtraTalentBatch" }, "角色面板" },
        { "ui.character.detail.CharacterDetail", { "update", "draw" }, "角色详情" },
        { "ui.character.hero.HeroRosterPanel", { "draw" }, "英雄名册" },
        { "ui.story.ScenarioDialogue", { "update", "draw" }, "剧情对话" },
        { "ui.story.gate.IntroCutscene", { "update", "draw" }, "开场剧情" },
        { "ui.story.gate.LetterIntro", { "update", "draw" }, "先祖来信" },
        { "ui.story.gate.DarkTitleScreenGate", { "update", "draw" }, "标题" },
        { "systems.TutorialManager", { "update", "draw" }, "新手引导" },
        { "ui.town.TownScene", { "update", "draw" }, "城镇" },
        { "ui.blacksmith.BlacksmithPage", { "update", "draw" }, "锻炉" },
        { "ui.church.talent.TalentPage", { "update", "draw" }, "天赋" },
        { "ui.hud.TopBar", { "update", "draw" }, "顶部栏" },
        { "ui.backpack.BackpackPanel", { "update", "draw" }, "仓库" },
        { "ui.loot.LootBoxPage", { "update", "draw", "refresh" }, "遗匣" },
        { "ui.church.ChurchPage", { "update", "draw" }, "礼拜堂" },
        { "ui.tavern.TavernPage", { "update", "draw" }, "酒馆" },
        { "ui.market.MarketPage", { "update", "draw" }, "黑市" },
        { "ui.dungeon.DungeonBattleScene", { "update", "draw" }, "副本战斗" },
        { "ui.tower.TowerBattleScene", { "update", "draw" }, "通天塔" },
        { "ui.dungeon.DungeonPage", { "update", "draw" }, "副本列表" },
        { "ui.battle.stage.SweepDialog", { "update", "draw", "drawPending" }, "扫荡界面" },
        { "ui.battle.stage.StageSelectDialog", { "draw" }, "选关" },
        { "ui.battle.popup.DamageStatsPanel", { "draw" }, "伤害统计" },
        { "systems.EquipmentSystem", { "applyEquip", "generate", "hydrateInventory" }, "装备计算" },
        { "systems.EquipmentPower", { "buildContext", "buildWornContext", "evaluateLoadout", "score", "genericScore" }, "装备战力" },
        { "systems.CombatPowerEstimate", { "estimate" }, "战力估算" },
        { "runtime.LocalActionBridge", { "dispatch", "updateQuickEquip", "updateSweep" }, "本地动作" },
        { "runtime.ClientDispatcher", { "set", "handleStateUpdate" }, "数据同步" },
        { "boot.StandaloneSave", { "Update", "Flush" }, "存档" },
    }
    local count = 0
    -- 只处理宿主已持有/已加载模块，不能诊断安装时主动载入整个游戏或提前初始化。
    for _, spec in ipairs(modules) do
        local module = M.getModule(spec[1])
        if type(module) == "table" then
            for _, key in ipairs(spec[2]) do
                local labels = spec[1] == "runtime.LocalActionBridge" and key == "dispatch" and actionLabels
                    or spec[1] == "runtime.ClientDispatcher" and key == "set" and moduleLabels or nil
                if hook(module, key, spec[3] .. "." .. key, labels) then count = count + 1 end
            end
        end
    end
    print("[Performance] 已接入同步分段 " .. count .. " 个；GPU未启用，不修改业务时钟")
    return count
end
-- 注册与安装都在诊断保护边界内，失败不能截断启动/boot完成；下次安装可继续补装。
function M.install(modules)
    local ok, count = pcall(function()
        if modules then M.register(modules) end
        return install()
    end)
    if not ok then Monitor.fail("分段接线"); return 0 end
    return count
end
-- 适配Standalone已持有的命名引用；集中维护canonical路径，不在宿主堆诊断路径表。
function M.installStandalone(refs)
    return M.install({
        ["ui.battle.tri.BattleTriPage"] = refs.BattleTriPage, ["ui.battle.scene.BattleScene"] = refs.BattleScene,
        ["ui.battle.combat.BattleEffects"] = refs.BattleEffects, ["ui.battle.combat.ProjectileSystem"] = refs.ProjectileSystem,
        ["ui.character.panel.CharacterPanel"] = refs.CharacterPanel, ["ui.character.detail.CharacterDetail"] = refs.CharacterDetail,
        ["ui.character.hero.HeroRosterPanel"] = refs.HeroRosterPanel,
        ["ui.backpack.BackpackPanel"] = refs.BackpackPanel, ["ui.loot.LootBoxPage"] = refs.LootBoxPage,
        ["ui.church.ChurchPage"] = refs.ChurchPage, ["ui.church.talent.TalentPage"] = refs.TalentPage,
        ["ui.tavern.TavernPage"] = refs.TavernPage, ["ui.market.MarketPage"] = refs.MarketPage,
        ["ui.dungeon.DungeonBattleScene"] = refs.DungeonBattleScene, ["ui.tower.TowerBattleScene"] = refs.TowerBattleScene,
        ["ui.dungeon.DungeonPage"] = refs.DungeonPage, ["ui.blacksmith.BlacksmithPage"] = refs.BlacksmithPage,
        ["ui.battle.stage.SweepDialog"] = refs.SweepDialog, ["ui.battle.stage.StageSelectDialog"] = refs.StageSelectDialog,
        ["ui.battle.popup.DamageStatsPanel"] = refs.DamageStatsPanel, ["ui.town.TownScene"] = refs.TownScene,
        ["ui.hud.TopBar"] = refs.TopBar, ["ui.hud.popup.PlayerInfoPanel"] = refs.PlayerInfoPanel,
        ["ui.hud.popup.OfflineRewardPanel"] = refs.OfflineRewardPanel, ["ui.story.ScenarioDialogue"] = refs.ScenarioDialogue,
        ["ui.story.gate.IntroCutscene"] = refs.IntroCutscene, ["ui.story.gate.LetterIntro"] = refs.LetterIntro,
        ["ui.story.gate.DarkTitleScreenGate"] = refs.DarkTitleScreen, ["systems.TutorialManager"] = refs.TutorialManager,
        ["systems.EquipmentSystem"] = refs.EquipmentSystem, ["runtime.LocalActionBridge"] = refs.LocalActionBridge,
        ["runtime.ClientDispatcher"] = refs.ClientDispatcher, ["boot.StandaloneSave"] = refs.StandaloneSave,
    })
end
return M
