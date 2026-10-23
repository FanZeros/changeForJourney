-- 诊断接线集中层：默认关闭；原始帧时钟、顶层Update/渲染、同源模态输入均只在这里接入。
local Monitor = require("core.PerformanceMonitor")
local Panel = require("ui.dev.PerformancePanel")
local RT = require("boot.StandaloneRT")
local Hooks = require("boot.PerformanceHooks")
local M = {}
local foreground = true
local installedHandlers = {}
local function install(name, factory)
    local original = _G[name]
    if type(original) ~= "function" or original == installedHandlers[name] then return end
    local handler = factory(original)
    installedHandlers[name] = handler
    _G[name] = handler
end
local function opened(name, key)
    local module = Hooks.getModule(name)
    return module and type(module[key]) == "function" and module[key]() or false
end
local function context()
    if opened("runtime.LocalActionBridge", "isSweepPending") then return "扫荡处理中" end
    local pages = {
        { "ui.battle.stage.SweepDialog", "isOpen", "扫荡" },
        { "ui.hud.popup.PlayerInfoPanel", "isOpen", "玩家设置" },
        { "ui.hud.popup.OfflineRewardPanel", "isOpen", "离线奖励" },
        { "ui.character.panel.CharacterPanel", "isDetailOpen", "角色" },
        { "ui.character.hero.HeroRosterPanel", "isVisible", "英雄名册" },
        { "ui.story.ScenarioDialogue", "isActive", "剧情对话" },
        { "ui.story.gate.IntroCutscene", "isActive", "开场剧情" },
        { "ui.story.gate.LetterIntro", "isOpen", "先祖来信" },
        { "ui.story.gate.DarkTitleScreenGate", "isOpen", "标题" },
        { "systems.TutorialManager", "isActive", "新手引导" },
        { "ui.blacksmith.BlacksmithPage", "isOpen", "锻炉" },
        { "ui.church.talent.TalentPage", "isOpen", "天赋" },
        { "ui.backpack.BackpackPanel", "isOpen", "仓库" },
        { "ui.loot.LootBoxPage", "isOpen", "遗匣" },
        { "ui.church.ChurchPage", "isOpen", "礼拜堂" },
        { "ui.tavern.TavernPage", "isOpen", "酒馆" },
        { "ui.market.MarketPage", "isOpen", "黑市" },
        { "ui.dungeon.DungeonBattleScene", "isOpen", "副本" },
        { "ui.tower.TowerBattleScene", "isActive", "通天塔" },
        { "ui.battle.tri.BattleTriPage", "isOpen", "三队战斗" },
    }
    local names = {}
    for _, entry in ipairs(pages) do
        if opened(entry[1], entry[2]) then names[#names + 1] = entry[3] end
    end
    return #names > 0 and table.concat(names, "/") or "标题/城镇/其他"
end
function M.focus(eventData)
    foreground = eventData:GetBool("Focus") and not eventData:GetBool("Minimized")
    Monitor.excludeCurrent("background")
    Panel.resetPointer()
end
function M.updateBefore(dt)
    if Monitor.isEnabled() then
        local ok = pcall(function()
            local exclusion = not foreground and "background" or (Panel.isOpen() and "panel" or nil)
            Monitor.beginFrame(exclusion and "诊断面板/后台" or context(), exclusion)
        end)
        if not ok then Monitor.fail("帧采样") end
    end
    -- 只保护诊断逻辑，原始Update仍在外层执行一次，业务错误照常传播。
    if not pcall(Panel.update, dt or 0) then Monitor.fail("诊断面板更新") end
end
local function coords(px, py)
    local dpr = RT.dpr or 1
    local scale = RT.frameScale or 1
    if scale <= 0 then scale = 1 end
    return (px / dpr - (RT.frameOx or 0)) / scale, (py / dpr - (RT.frameOy or 0)) / scale
end
local function intercept(kind, touch, eventData)
    local modal = Panel.isOpen()
    local id, x, y = "mouse", 0, 0
    if touch then
        id = eventData:GetInt("TouchID")
        x, y = coords(eventData:GetInt("X"), eventData:GetInt("Y"))
    else
        if kind ~= "move" and eventData:GetInt("Button") ~= MOUSEB_LEFT then return modal end
        local pos = input:GetMousePosition()
        x, y = coords(pos.x, pos.y)
    end
    return Panel.handlePointer(kind, x, y, id) or modal
end
function M.installHandlers()
    -- Start可重复调用，也可只重载Standalone；按当前handler身份补装，未被重定义的入口不叠加。
    install("HandleUpdate", function(original)
        local measured = Monitor.wrap("主循环.Update", original)
        return function(eventType, eventData)
            M.updateBefore(eventData:GetFloat("TimeStep"))
            return measured(eventType, eventData)
        end
    end)
    install("HandleNanoVGRender", function(original)
        return Monitor.wrap("主循环.NanoVGRender", original)
    end)
    local names = {
        { "HandleMouseButtonDown", "down", false }, { "HandleMouseMove", "move", false },
        { "HandleMouseButtonUp", "up", false }, { "HandleTouchBegin", "down", true },
        { "HandleTouchMove", "move", true }, { "HandleTouchEnd", "up", true },
    }
    for _, entry in ipairs(names) do
        install(entry[1], function(original)
            local measured = Monitor.wrap("输入." .. entry[1], original)
            return function(eventType, eventData)
                if intercept(entry[2], entry[3], eventData) then return end
                return measured(eventType, eventData)
            end
        end)
    end
    install("HandleMouseWheel", function(original)
        return function(...)
            if Panel.isOpen() then return end
            return original(...)
        end
    end)
end
return M
