-- 返回条独占按下到松开的手势，避免中缝坐标被当成战斗拖拽。
local Gesture = {}
local CEPanel = require("ui.dev.CEPanel")
local PlayerInfoPanel = require("ui.hud.popup.PlayerInfoPanel")
local OfflineRewardPanel = require("ui.hud.popup.OfflineRewardPanel")
local LevelUpPopup = require("ui.hud.popup.LevelUpPopup")
local UpdateNoticePopup = require("ui.hud.popup.UpdateNoticePopup")
local DarkTitleScreen = require("ui.story.gate.DarkTitleScreenGate")
local LetterIntro = require("ui.story.gate.LetterIntro")
local IntroCutscene = require("ui.story.gate.IntroCutscene")
local ScenarioDialogue = require("ui.story.ScenarioDialogue")
local TutorialManager = require("systems.TutorialManager")
local SweepDialog = require("ui.battle.stage.SweepDialog")
local DamageStatsPanel = require("ui.battle.popup.DamageStatsPanel")
local StageSelectDialog = require("ui.battle.stage.StageSelectDialog")
local TerminalConfirmDialog = require("ui.battle.popup.TerminalConfirmDialog")
local RewardPopup = require("ui.hud.popup.RewardPopup")
local DungeonBattleScene = require("ui.dungeon.DungeonBattleScene")
local TowerBattleScene = require("ui.tower.TowerBattleScene")
local TavernPage = require("ui.tavern.TavernPage")
local TavernPopups = require("ui.tavern.TavernPopups")
local TargetRecruitPanel = require("ui.tavern.TargetRecruitPanel")

---@param ctx table
function Gesture.bind(ctx)
    local press = nil ---@type table|nil
    local function layout()
        return { ctx.width(), ctx.height(), ctx.dpr(), ctx.RT.frameScale or 1,
            ctx.RT.frameOx or 0, ctx.RT.frameOy or 0 }
    end
    local function sameLayout(a, b)
        for i = 1, #a do if a[i] ~= b[i] then return false end end
        return true
    end
    local function eligible()
        return ctx.bootReady() and not (CEPanel.isOpen() or PlayerInfoPanel.isOpen()
            or OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen() or UpdateNoticePopup.isOpen()
            or DarkTitleScreen.isOpen() or LetterIntro.isOpen() or IntroCutscene.isActive()
            or ScenarioDialogue.isActive() or TutorialManager.isActive()
            or SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen()
            or TerminalConfirmDialog.isOpen() or (RewardPopup.isOpen() and not RewardPopup.currentRowTag())
            or ctx.pageModal() or DungeonBattleScene.isOpen() or TowerBattleScene.isActive())
    end
    local api = {}
    function api.cancel() press = nil end
    function api.hasPress() return press ~= nil end
    function api.cancelIfBlocked()
        if not eligible() then press = nil end
    end
    function api.down(x, y)
        press = nil
        if not eligible() then return false end
        local button = ctx.hit(x, y)
        if not button then return false end
        press = { key = button.key, openedAt = button.openedAt, x = x, y = y,
            layout = layout(), moved = false, source = ctx.source() }
        return true
    end
    function api.move(x, y)
        if not press then return false end
        if press.source ~= ctx.source() then return true end
        if not eligible() or not sameLayout(press.layout, layout())
            or math.abs(x - press.x) + math.abs(y - press.y) >= ctx.threshold then
            press.moved = true
        end
        return true
    end
    function api.up(x, y)
        if not press then return false end
        if press.source ~= ctx.source() then return true end
        local start = press
        press = nil
        local button = eligible() and ctx.hit(x, y)
        if button and button.key == start.key and button.openedAt == start.openedAt
            and not start.moved and sameLayout(start.layout, layout())
            and math.abs(x - start.x) + math.abs(y - start.y) < ctx.threshold then
            if button.key == "tavern" and (TavernPage.isRecruitBusy()
                or TargetRecruitPanel.isOpen() or TavernPopups.isBlocking()) then return true end
            local now = time.elapsedTime
            if now - ctx.getLastTap() >= ctx.tapInterval then
                ctx.setLastTap(now)
                print("[SeamBack] close owner=" .. tostring(button.key)
                    .. string.format(" at %.0f,%.0f", x, y))
                button.close()
            end
        end
        return true
    end
    return api
end

return Gesture
