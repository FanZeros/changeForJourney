-- 只认左侧二级操作页和右侧角色详情，不把常驻城镇/角色栏或塔路线/暗契算作暂停。
local SettingsPanel = require("ui.hud.popup.SettingsPanel")
local BattleClock = require("ui.battle.combat.BattleClock")
local LootBoxPage = require("ui.loot.LootBoxPage")
local TaskPage = require("ui.story.task.TaskPage")
local BackpackPanel = require("ui.backpack.BackpackPanel")
local TalentPage = require("ui.church.talent.TalentPage")
local ChurchPage = require("ui.church.ChurchPage")
local TavernPage = require("ui.tavern.TavernPage")
local MarketPage = require("ui.market.MarketPage")
local BlacksmithPage = require("ui.blacksmith.BlacksmithPage")
local CharacterPanel = require("ui.character.panel.CharacterPanel")

local SidePanelBattlePause = {}

---@return boolean
function SidePanelBattlePause.isSidePanelOpen()
    return LootBoxPage.isOpen() or TaskPage.isOpen()
        or (BackpackPanel.isOpen() and BackpackPanel.isLeftMode())
        or TalentPage.isOpen() or ChurchPage.isOpen() or TavernPage.isOpen()
        or MarketPage.isOpen() or BlacksmithPage.isOpen()
        or CharacterPanel.isDetailOpen()
end

---@return boolean
function SidePanelBattlePause.shouldPause()
    return SettingsPanel.isPauseBattleOnSidePanelsEnabled()
        and SidePanelBattlePause.isSidePanelOpen()
end

--- 每帧开始与集中派发前同步，回执/教程同帧打开侧页也不会再攻击一帧。
---@return boolean
function SidePanelBattlePause.refresh()
    local value = SidePanelBattlePause.shouldPause()
    BattleClock.setPaused(value)
    return value
end

return SidePanelBattlePause
