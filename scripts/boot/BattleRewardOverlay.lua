-- 自动战斗奖励只在中栏无遮挡时展示；只读页面状态，不影响结算或页面关闭。
local SweepDialog = require("ui.battle.stage.SweepDialog")
local DamageStatsPanel = require("ui.battle.popup.DamageStatsPanel")
local StageSelectDialog = require("ui.battle.stage.StageSelectDialog")
local TerminalConfirmDialog = require("ui.battle.popup.TerminalConfirmDialog")
local EquipmentBag = require("ui.character.equip.EquipmentBag")
local BlacksmithPage = require("ui.blacksmith.BlacksmithPage")
local TalentPage = require("ui.church.talent.TalentPage")
local BackpackPanel = require("ui.backpack.BackpackPanel")
local DungeonBattleScene = require("ui.dungeon.DungeonBattleScene")
local TowerBattleScene = require("ui.tower.TowerBattleScene")
local BottomNav = require("ui.hud.BottomNav")
local PlayerInfoPanel = require("ui.hud.popup.PlayerInfoPanel")
local OfflineRewardPanel = require("ui.hud.popup.OfflineRewardPanel")
local LevelUpPopup = require("ui.hud.popup.LevelUpPopup")
local UpdateNoticePopup = require("ui.hud.popup.UpdateNoticePopup")
local StartScreen = require("ui.story.gate.StartScreen")
local DarkTitleScreen = require("ui.story.gate.DarkTitleScreenGate")
local LetterIntro = require("ui.story.gate.LetterIntro")
local IntroCutscene = require("ui.story.gate.IntroCutscene")
local ScenarioDialogue = require("ui.story.ScenarioDialogue")

local M = {}

function M.isBlocked()
    return SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen()
        or TerminalConfirmDialog.isOpen() or EquipmentBag.shouldBattleOverlay()
        or BlacksmithPage.isOpen()
        or (TalentPage.isOpen() and TalentPage.getHorizonWidthScale() > 1.001)
        or (BackpackPanel.isOpen() and not BackpackPanel.isLeftMode())
        or BottomNav.getSelectedIndex() == 5
        or DungeonBattleScene.isOpen() or TowerBattleScene.isActive()
        or PlayerInfoPanel.isOpen() or OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen()
        or UpdateNoticePopup.isOpen() or StartScreen.isOpen() or DarkTitleScreen.isOpen()
        or LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive()
end

return M
