-- 神器页独占整次鼠标/触摸手势；同一 Viewport 记录用于显示和落点，不向其它栏派发松手。
local Panel = require("ui.church.ChurchArtifactPanel")
local Detail = require("ui.character.hero.ArtifactDetailPanel")
local Church = require("ui.church.ChurchPage")
local Backpack = require("ui.backpack.BackpackPanel")
local TaskPage = require("ui.story.task.TaskPage")
local LootBoxPage = require("ui.loot.LootBoxPage")
local TalentPage = require("ui.church.talent.TalentPage")
local MarketPage = require("ui.market.MarketPage")
local TavernPage = require("ui.tavern.TavernPage")
local Tower = require("ui.tower.TowerBattleScene")
local Dungeon = require("ui.dungeon.DungeonBattleScene")
local Reward = require("ui.hud.popup.RewardPopup")
local PlayerInfo = require("ui.hud.popup.PlayerInfoPanel")
local Offline = require("ui.hud.popup.OfflineRewardPanel")
local LevelUp = require("ui.hud.popup.LevelUpPopup")
local UpdateNotice = require("ui.hud.popup.UpdateNoticePopup")
local Sweep = require("ui.battle.stage.SweepDialog")
local Damage = require("ui.battle.popup.DamageStatsPanel")
local StageSelect = require("ui.battle.stage.StageSelectDialog")
local TerminalConfirm = require("ui.battle.popup.TerminalConfirmDialog")
local Tutorial = require("systems.TutorialManager")
local Title = require("ui.story.gate.DarkTitleScreenGate")
local StartScreen = require("ui.story.gate.StartScreen")
local Letter = require("ui.story.gate.LetterIntro")
local RecordPanel = require("ui.story.SamsaraRecordPanel")
local Scenario = require("ui.story.ScenarioDialogue")

local M = {}

function M.isActive()
    return Church.isArtifactInputActive() and not Backpack.isOpen() and not TaskPage.isOpen()
        and not LootBoxPage.isOpen() and not TalentPage.isOpen() and not MarketPage.isOpen()
        and not TavernPage.isOpen() and not Tower.isActive() and not Dungeon.isOpen()
        and not Reward.isOpen() and not PlayerInfo.isOpen() and not Offline.isOpen()
        and not LevelUp.isOpen() and not UpdateNotice.isOpen() and not Sweep.isOpen()
        and not Damage.isOpen() and not StageSelect.isOpen() and not TerminalConfirm.isOpen()
        and not Tutorial.isActive()
        and not Title.isOpen() and not StartScreen.isOpen() and not Letter.isOpen()
        and not RecordPanel.isOpen() and not Scenario.isActive()
end

function M.bind(ctx)
    local Viewport, RT = ctx.Viewport, ctx.RT
    local press = nil ---@type table|nil
    local discarded = false
    local api = {}

    local function snapshot()
        local note = Viewport.getNote("left")
        if not note then return nil end
        return { ox = note.ox, oy = note.oy, s = note.s, scaleX = note.scaleX,
            width = ctx.logicalW(), height = ctx.logicalH(), dpr = ctx.dpr(),
            frameScale = RT.frameScale or 1, frameOx = RT.frameOx or 0, frameOy = RT.frameOy or 0 }
    end

    local function unchanged()
        local current = snapshot()
        if not press or not current then return false end
        for key, value in pairs(press.frame) do
            if current[key] ~= value then return false end
        end
        return current.scaleX == press.frame.scaleX
    end

    local function coords(sx, sy)
        local note = Viewport.getNote("left")
        if not note or note.s <= 0 then return nil end
        local p = Viewport.PANELS.left
        local cs = note.s * Viewport.DS
        return (sx - note.ox - p.bx * note.s) / (note.scaleX or cs),
            (sy - note.oy - p.by * note.s) / cs
    end

    function api.cancel()
        if press then discarded = true end
        press = nil
        Panel.cancelPointer()
        Detail.closeImmediate()
    end

    function api.down(pid, sx, sy)
        discarded = false
        if press then api.cancel() discarded = false end
        if pid ~= "left" or not M.isActive() then return false end
        local dx, dy = coords(sx, sy)
        local frame = snapshot()
        if not dx or not frame then return false end
        press = { x = sx, y = sy, dx = dx, dy = dy, moved = false, frame = frame }
        Panel.handleDragBegin(dx, dy)
        return true
    end

    function api.move(sx, sy)
        if discarded then return true end
        if not press then return false end
        if not M.isActive() or not unchanged() then api.cancel() return true end
        if math.abs(sx - press.x) + math.abs(sy - press.y) >= 15 then press.moved = true end
        local dx, dy = coords(sx, sy)
        if math.abs(dx - press.dx) + math.abs(dy - press.dy) >= 15 then press.moved = true end
        Panel.handleDragMove(dx, dy)
        return true
    end

    function api.up(sx, sy)
        if discarded then discarded = false return true end
        if not press then return false end
        if not M.isActive() or not unchanged() then api.cancel() discarded = false return true end
        local start = press
        local dx, dy = coords(sx, sy)
        local dragged = Panel.handleDragEnd(dx, dy)
        press = nil
        if not dragged and not start.moved and math.abs(sx - start.x) + math.abs(sy - start.y) < 15
            and math.abs(dx - start.dx) + math.abs(dy - start.dy) < 15
            and dx >= 0 and dx <= 1080 and dy >= 0 and dy <= 2400 then
            Church.handleInput(dx, dy)
        end
        return true
    end

    function api.hover(pid, sx, sy)
        if press or discarded then return end
        if not M.isActive() then
            Panel.handleHover(-1, -1)
            Detail.closeImmediate()
            return
        end
        if pid ~= "left" then Panel.handleHover(-1, -1) return end
        local dx, dy = coords(sx, sy)
        if dx then Church.handleHover(dx, dy) end
    end

    function api.draw(vg)
        if not Panel.isItemDragging() then return end
        if not M.isActive() or not unchanged() then api.cancel() return end
        if Viewport.beginFromNote(vg, "left") then
            Panel.drawDragOverlay(vg)
            Viewport.finish(vg)
        end
    end

    return api
end

return M
