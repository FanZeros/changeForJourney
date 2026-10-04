-- 副本入口呈现：页面内反馈、返回按钮和通天塔条件，不修改进度或奖励。
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local I18n = require("core.I18n")
local ExpTable = require("config.ExpTable")
local TowerConfig = require("config.TowerConfig")
local ClientDispatcher = require("runtime.ClientDispatcher")

local Entry = {}
local message = ""
---@type number
local messageUntil = 0
local BACK = { cx = 540, cy = 225, w = 360, h = 90 }

local function drawText(vg, x, y, text, maxWidth, fontSize, r, g, b)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    local width = nvgTextBounds(vg, 0, 0, text) or 0
    local size = fontSize
    if width > maxWidth and width > 0 then size = fontSize * maxWidth / width end
    DrawUtil.drawTextStroke(vg, x, y, text, size,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, r, g, b, 3)
end

function Entry.showMessage(text)
    message = text or ""
    messageUntil = time.elapsedTime + 3
    print("[DungeonEntry] " .. message)
end

function Entry.clearMessage()
    message, messageUntil = "", 0
end

function Entry.getMessage()
    return time.elapsedTime < messageUntil and message or ""
end

function Entry.hitBack(x, y)
    return DrawUtil.hitTest(x, y, BACK.cx, BACK.cy, BACK.w, BACK.h)
end

function Entry.drawHeader(vg, detailOpen)
    drawText(vg, 540, 110, I18n.t("tab_dungeon"), 850, 56, 240, 220, 175)
    DarkIcon.drawNine(vg, "btn", BACK.cx - BACK.w / 2, BACK.cy - BACK.h / 2,
        BACK.w, BACK.h, { accent = "gold" })
    drawText(vg, BACK.cx, BACK.cy, I18n.lookup(detailOpen and "返回列表" or "返回主界面"),
        BACK.w - 40, 34, 240, 220, 175)
end

function Entry.drawMessage(vg)
    local text = Entry.getMessage()
    if text == "" then return end
    DarkIcon.drawNine(vg, "plain", 80, 2070, 920, 110, {})
    drawText(vg, 540, 2125, text, 850, 36, 255, 210, 160)
end

--- 展示条件只读编队数量，不在逐帧绘制时创建战斗英雄。
---@param floor number
---@return boolean disabled, string reason
function Entry.getTowerChallengeState(floor)
    if floor > TowerConfig.MAX_FLOOR then
        return true, I18n.format("%d层已全部通关", TowerConfig.MAX_FLOOR)
    end
    if ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle")) < ExpTable.TEAM_COUNT then
        local stage = ExpTable.getTeamUnlockStage(3) or 1905
        return true, I18n.format("通关%d-%d解锁三队后可挑战", math.floor(stage / 100), stage % 100)
    end
    local CharacterPanel = require("ui.character.panel.CharacterPanel")
    if not CharacterPanel.isHeroesDataApplied() then
        return true, I18n.lookup("编队数据加载中")
    end
    local counts = CharacterPanel.getTeamOccupiedCounts()
    for team = 1, ExpTable.TEAM_COUNT do
        if (counts[team] or 0) < 1 then
            return true, I18n.format("队伍%d为空，请在右侧部署队员", team)
        end
    end
    return false, I18n.lookup("三队均需至少1人，任意一队全灭即失败")
end

function Entry.getTowerRewards(floor)
    local current = TowerConfig.getFloor(floor)
    local previous = TowerConfig.getFloor(floor - 1)
    return current and current.firstDiamond or 0, previous and previous.sweepDiamond or 0
end

function Entry.drawTowerInfo(vg, floor, disabled, reason)
    local first, sweep = Entry.getTowerRewards(floor)
    drawText(vg, 540, 1465, I18n.format("本层首通 %s · 上层扫荡 %s",
        tostring(first), tostring(sweep)), 760, 30, 240, 220, 175)
    drawText(vg, 540, 1710, reason, 820, 30,
        disabled and 230 or 180, disabled and 175 or 220, disabled and 145 or 185)
end

function Entry.drawTowerCardHint(vg, y, floor)
    local disabled, reason = Entry.getTowerChallengeState(floor)
    if not disabled then reason = I18n.lookup("三队就绪，可挑战") end
    drawText(vg, 540, y, reason, 900, 30, 240, 220, 175)
end

return Entry
