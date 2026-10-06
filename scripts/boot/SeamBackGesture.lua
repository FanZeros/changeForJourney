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
local RecruitAnim = require("ui.tavern.RecruitAnim")

---@param ctx table
function Gesture.bind(ctx)
    local press = nil ---@type table|nil
    local function layout()
        if ctx.layoutSnapshot then return ctx.layoutSnapshot() end
        return { ctx.width(), ctx.height(), ctx.dpr(), ctx.RT.frameScale or 1,
            ctx.RT.frameOx or 0, ctx.RT.frameOy or 0 }
    end
    local function sameLayout(a, b)
        for i = 1, #a do if a[i] ~= b[i] then return false end end
        return true
    end
    local function eligible()
        return not (ctx.extraBlocked and ctx.extraBlocked()) and ctx.bootReady() and not (CEPanel.isOpen() or PlayerInfoPanel.isOpen()
            or OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen() or UpdateNoticePopup.isOpen()
            or DarkTitleScreen.isOpen() or LetterIntro.isOpen() or IntroCutscene.isActive()
            or ScenarioDialogue.isActive() or TutorialManager.isActive()
            or SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen()
            or TerminalConfirmDialog.isOpen() or (RewardPopup.isOpen() and not RewardPopup.currentRowTag())
            or ctx.pageModal() or DungeonBattleScene.isOpen() or TowerBattleScene.isActive())
    end
    local api = {}
    function api.cancel()
        if press then press.moved = true end -- 取消后仍消费原来源的松开，不能透传到下层。
    end
    function api.reset() press = nil end
    function api.hasPress() return press ~= nil end
    function api.cancelIfBlocked()
        if not eligible() then api.cancel() end
    end
    function api.down(x, y, blocked)
        local source = ctx.source()
        if press and press.source ~= source then return false end
        press = nil
        if blocked or not eligible() then return false end
        local button = ctx.hit(x, y)
        if not button then return false end
        press = { key = button.key or button.id, openedAt = button.openedAt or button.generation, x = x, y = y,
            layout = layout(), moved = button.closing == true, source = source }
        return true
    end
    function api.move(x, y, blocked)
        if not press then return false end
        if press.source ~= ctx.source() then return true end
        local button = ctx.hit(x, y)
        if blocked or not eligible() or not sameLayout(press.layout, layout())
            or not button or button.closing or (button.key or button.id) ~= press.key
            or (button.openedAt or button.generation) ~= press.openedAt
            or math.abs(x - press.x) + math.abs(y - press.y) >= ctx.threshold then
            press.moved = true
        end
        return true
    end
    function api.up(x, y, blocked)
        if not press then return false end
        if press.source ~= ctx.source() then return true end
        local start = press
        press = nil
        local button = not blocked and eligible() and ctx.hit(x, y)
        if button and not button.closing and (button.key or button.id) == start.key
            and (button.openedAt or button.generation) == start.openedAt
            and not start.moved and sameLayout(start.layout, layout())
            and math.abs(x - start.x) + math.abs(y - start.y) < ctx.threshold then
            if (button.key or button.id) == "tavern" then
                -- 抽卡结果页：返回条等价于"任意点击"——先跳过/结束本次结果，不直接离开招募页。
                -- 必须早于 isRecruitBusy()（后者也包含动画播放态），否则本分支永远到不了。
                if RecruitAnim.isPlaying() then
                    RecruitAnim.dismiss()
                    return true
                end
                -- 招募弹窗/请求中：返回条不抢输入（原行为）
                if TavernPage.isRecruitBusy() or TavernPopups.isBlocking() then return true end
                -- 指定UP面板：面板自身有关闭按钮，返回条不叠一层关闭
                if TargetRecruitPanel.isOpen() then return true end
            end
            local now = time.elapsedTime
            if not ctx.getLastTap or now - ctx.getLastTap() >= ctx.tapInterval then
                if ctx.setLastTap then ctx.setLastTap(now) end
                if ctx.onClose then ctx.onClose(button) end
                button.close()
            end
        end
        return true
    end
    return api
end

return Gesture
