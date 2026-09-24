-- ============================================================================
-- KeyboardShortcuts - PC 键盘快捷键
-- Esc 关闭，空格/回车继续，F 倍速，数字键打开城镇页面。H 查看说明。
-- 兑换码和 GM 输入时不抢字母键。
-- ============================================================================

local UiToast = require("core.UiToast")

local KeyboardShortcuts = {}

local helpOpen = false

local LINES = {
    "H  打开或关闭本说明",
    "Esc  关闭当前弹窗或页面",
    "空格 / 回车  继续对话、领取或关掉奖励",
    "F  切换战斗倍速",
    "M  开关音效",
    "I  玩家信息",
    "B  背包",
    "1 铁匠  2 教堂  3 古树  4 酒馆  5 市场  6 遗匣",
}

local function pressed(key)
    return input:GetKeyPress(key)
end

local function ctrlDown()
    return input:GetQualifierDown(QUAL_CTRL)
end

local function getVg()
    local RT = require("boot.StandaloneRT")
    return RT.vg
end

local function toast(text)
    UiToast.show(text, 1.1)
    print("[KeyboardShortcuts] " .. text)
end

local function blockedByTitle()
    local DarkTitleScreen = require("ui.DarkTitleScreenGate")
    local StartScreen = require("ui.StartScreen")
    if DarkTitleScreen.isOpen() or StartScreen.isOpen() then return true end
    return false
end

local function textBusy()
    local RedeemCodePanel = require("ui.RedeemCodePanel")
    if RedeemCodePanel.isOpen() then return true end
    local GMConsolePanel = require("ui.GMConsolePanel")
    if GMConsolePanel.isOpen() then return true end
    return false
end

local function battleLocked()
    local DungeonBattleScene = require("ui.DungeonBattleScene")
    if DungeonBattleScene.isOpen and DungeonBattleScene.isOpen() then return true end
    local TowerBattleScene = require("ui.TowerBattleScene")
    if TowerBattleScene.isActive and TowerBattleScene.isActive() then return true end
    return false
end

local function closeLeftPages()
    local closed = false
    local LootBoxPage = require("ui.LootBoxPage")
    if LootBoxPage.isOpen() then LootBoxPage.close() closed = true end
    local BackpackPanel = require("ui.BackpackPanel")
    if BackpackPanel.isOpen() then BackpackPanel.close() closed = true end
    local TalentPage = require("ui.TalentPage")
    if TalentPage.isOpen() then TalentPage.close() closed = true end
    local ChurchPage = require("ui.ChurchPage")
    if ChurchPage.isOpen() then ChurchPage.close() closed = true end
    local BlacksmithPage = require("ui.BlacksmithPage")
    if BlacksmithPage.isOpen() then BlacksmithPage.close() closed = true end
    local TavernPage = require("ui.TavernPage")
    if TavernPage.isOpen() then TavernPage.close() closed = true end
    local MarketPage = require("ui.MarketPage")
    if MarketPage.isOpen() then MarketPage.close() closed = true end
    return closed
end

---@param isOpen fun(): boolean
---@param closeFn fun()
---@param openFn fun()
local function togglePage(isOpen, closeFn, openFn)
    if isOpen() then
        closeFn()
        return
    end
    if battleLocked() then
        toast("战斗中无法打开")
        return
    end
    closeLeftPages()
    openFn()
end

local function openWithInit(modName, openFn)
    local vg = getVg()
    if not vg then
        print("[KeyboardShortcuts] vg 未就绪，忽略打开 " .. modName)
        return
    end
    local mod = require(modName)
    if mod.init then mod.init(vg) end
    openFn(mod)
end

local function cycleSpeed()
    local DungeonBattleScene = require("ui.DungeonBattleScene")
    if DungeonBattleScene.isOpen and DungeonBattleScene.isOpen() then
        if DungeonBattleScene.cycleBattleSpeed and DungeonBattleScene.cycleBattleSpeed() then
            toast("副本倍速已切换")
            return
        end
        toast("当前不能切换倍速")
        return
    end
    local TowerBattleScene = require("ui.TowerBattleScene")
    if TowerBattleScene.isActive and TowerBattleScene.isActive() then
        local TowerTriBattle = require("ui.TowerTriBattle")
        if TowerTriBattle.cycleBattleSpeed and TowerTriBattle.cycleBattleSpeed() then
            toast("塔倍速已切换")
            return
        end
        toast("当前不能切换倍速")
        return
    end
    local BattleScene = require("ui.BattleScene")
    if BattleScene.cycleBattleSpeed and BattleScene.cycleBattleSpeed() then
        toast("倍速 " .. BattleScene.getSpeedText())
        return
    end
    toast("当前不能切换倍速")
end

local function handleEscape()
    if helpOpen then
        helpOpen = false
        print("[KeyboardShortcuts] 关闭说明")
        return
    end
    local IntroCutscene = require("ui.IntroCutscene")
    if IntroCutscene.isActive() then
        IntroCutscene.skip()
        return
    end
    local ScenarioDialogue = require("ui.ScenarioDialogue")
    if ScenarioDialogue.isActive() then
        ScenarioDialogue.skip()
        return
    end
    local RedeemCodePanel = require("ui.RedeemCodePanel")
    if RedeemCodePanel.isOpen() then
        RedeemCodePanel.close()
        return
    end
    local GMConsolePanel = require("ui.GMConsolePanel")
    if GMConsolePanel.isOpen() then
        GMConsolePanel.close()
        return
    end
    local RewardPopup = require("ui.RewardPopup")
    if RewardPopup.isOpen() then
        RewardPopup.handleInput(-1, -1)
        return
    end
    local LevelUpPopup = require("ui.LevelUpPopup")
    if LevelUpPopup.isOpen() then
        LevelUpPopup.handleInput(0, 0)
        return
    end
    local PlayerInfoPanel = require("ui.PlayerInfoPanel")
    if PlayerInfoPanel.isOpen() then
        PlayerInfoPanel.close()
        return
    end
    local CharacterDetail = require("ui.CharacterDetail")
    if CharacterDetail.isOpen() then
        CharacterDetail.close()
        return
    end
    local HeroRosterPanel = require("ui.HeroRosterPanel")
    if HeroRosterPanel.isVisible() then
        HeroRosterPanel.hide()
        return
    end
    if closeLeftPages() then return end
    local OfflineRewardPanel = require("ui.OfflineRewardPanel")
    if OfflineRewardPanel.isOpen() then
        toast("按空格领取离线收益")
        return
    end
    toast("按 H 查看快捷键")
end

local function handleConfirm()
    local ScenarioDialogue = require("ui.ScenarioDialogue")
    if ScenarioDialogue.isActive() then
        ScenarioDialogue.advance()
        return
    end
    local LetterIntro = require("ui.LetterIntro")
    if LetterIntro.isOpen() then
        LetterIntro.handleTap()
        return
    end
    local RewardPopup = require("ui.RewardPopup")
    if RewardPopup.isOpen() then
        RewardPopup.handleInput(-1, -1)
        return
    end
    local OfflineRewardPanel = require("ui.OfflineRewardPanel")
    if OfflineRewardPanel.isOpen() then
        OfflineRewardPanel.claim()
        return
    end
    local LevelUpPopup = require("ui.LevelUpPopup")
    if LevelUpPopup.isOpen() then
        LevelUpPopup.handleInput(0, 0)
        return
    end
end

function KeyboardShortcuts.update()
    if blockedByTitle() then return end
    if ctrlDown() then return end

    if pressed(KEY_ESCAPE) then
        handleEscape()
        return
    end

    if textBusy() then return end

    if pressed(KEY_H) then
        helpOpen = not helpOpen
        print("[KeyboardShortcuts] 说明 " .. tostring(helpOpen))
        return
    end
    if helpOpen and (pressed(KEY_SPACE) or pressed(KEY_RETURN) or pressed(KEY_RETURN2)) then
        helpOpen = false
        return
    end
    if pressed(KEY_SPACE) or pressed(KEY_RETURN) or pressed(KEY_RETURN2) then
        handleConfirm()
        return
    end
    if pressed(KEY_F) then
        cycleSpeed()
        return
    end
    if pressed(KEY_M) then
        local SettingsPanel = require("ui.SettingsPanel")
        local on = not SettingsPanel.isSoundOn()
        SettingsPanel.setSoundOn(on)
        toast(on and "音效开" or "音效关")
        return
    end
    if pressed(KEY_I) then
        local PlayerInfoPanel = require("ui.PlayerInfoPanel")
        if PlayerInfoPanel.isOpen() then
            PlayerInfoPanel.close()
        else
            PlayerInfoPanel.open()
        end
        return
    end

    if pressed(KEY_B) then
        togglePage(function()
            return require("ui.BackpackPanel").isOpen()
        end, function()
            require("ui.BackpackPanel").close()
        end, function()
            require("ui.BackpackPanel").open("left")
        end)
        return
    end
    if pressed(KEY_1) then
        togglePage(function() return require("ui.BlacksmithPage").isOpen() end,
            function() require("ui.BlacksmithPage").close() end,
            function() openWithInit("ui.BlacksmithPage", function(mod) mod.open() end) end)
        return
    end
    if pressed(KEY_2) then
        togglePage(function() return require("ui.ChurchPage").isOpen() end,
            function() require("ui.ChurchPage").close() end,
            function() openWithInit("ui.ChurchPage", function(mod) mod.open() end) end)
        return
    end
    if pressed(KEY_3) then
        togglePage(function() return require("ui.TalentPage").isOpen() end,
            function() require("ui.TalentPage").close() end,
            function() openWithInit("ui.TalentPage", function(mod) mod.open() end) end)
        return
    end
    if pressed(KEY_4) then
        togglePage(function() return require("ui.TavernPage").isOpen() end,
            function() require("ui.TavernPage").close() end,
            function() openWithInit("ui.TavernPage", function(mod) mod.open() end) end)
        return
    end
    if pressed(KEY_5) then
        togglePage(function() return require("ui.MarketPage").isOpen() end,
            function() require("ui.MarketPage").close() end,
            function() openWithInit("ui.MarketPage", function(mod) mod.open() end) end)
        return
    end
    if pressed(KEY_6) then
        togglePage(function() return require("ui.LootBoxPage").isOpen() end,
            function() require("ui.LootBoxPage").close() end,
            function() require("ui.LootBox").openPage() end)
        return
    end
end

---@param vg any
---@param w number
---@param h number
function KeyboardShortcuts.draw(vg, w, h)
    if not vg or w < 100 or h < 100 then return end
    if blockedByTitle() then return end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(244, 237, 224, helpOpen and 40 or 170))
    nvgText(vg, w * 0.5, h - 22, "H 快捷键", nil)

    if not helpOpen then return end

    local panelW, panelH = math.min(760, w - 80), 420
    local x = (w - panelW) * 0.5
    local y = (h - panelH) * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, panelW, panelH, 16)
    nvgFillColor(vg, nvgRGBA(16, 13, 10, 235))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(196, 160, 90, 230))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontSize(vg, 32)
    nvgFillColor(vg, nvgRGBA(255, 226, 140, 255))
    nvgText(vg, w * 0.5, y + 42, "键盘快捷键", nil)

    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(244, 237, 224, 240))
    for i = 1, #LINES do
        nvgText(vg, x + 48, y + 78 + i * 34, LINES[i], nil)
    end
end

return KeyboardShortcuts
