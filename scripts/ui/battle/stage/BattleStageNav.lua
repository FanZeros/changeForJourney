-- ============================================================================
-- BattleStageNav - 关卡名 / 前进后退按钮 / 剩余敌人 / 我的队伍
-- 从 BattleScene.draw 抽出
-- ============================================================================

local BattleDraw = require("ui.battle.scene.BattleDraw")
local StageBerserk = require("ui.battle.stage.StageBerserk")
local I18n = require("core.I18n")

local M = {}

-- 只测量绘制时的译文，不截断关卡原名，也不把译文回写业务缓存。
local function fittedFontSize(vg, text, fontSize, maxWidth)
    nvgSave(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local width = nvgTextBounds(vg, 0, 0, text)
    nvgRestore(vg)
    return width > maxWidth and (fontSize * maxWidth / width) or fontSize
end

M.NAV = {
    STAGE_CX = 540, STAGE_CY = 1276,
    BACK_BG_CX = 116, BACK_BG_CY = 1277, BACK_BG_W = 232, BACK_BG_H = 226,
    BACK_ICON_CX = 81, BACK_ICON_CY = 1258, BACK_ICON_W = 53, BACK_ICON_H = 81,
    BACK_TEXT_CX = 88, BACK_TEXT_CY = 1326,
    FWD_BG_CX = 964, FWD_BG_CY = 1277, FWD_BG_W = 232, FWD_BG_H = 226,
    FWD_ICON_CX = 998, FWD_ICON_CY = 1258, FWD_ICON_W = 53, FWD_ICON_H = 81,
    FWD_TEXT_CX = 991, FWD_TEXT_CY = 1325,
}

---@param remainCount number
function M.drawRemainEnemies(vg, remainCount)
    local remainText = I18n.format("剩余敌人 %s", tostring(remainCount))
    BattleDraw.drawTextStroke(vg, 540, 525, remainText, fittedFontSize(vg, remainText, 40, 900),
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
end

---@class BattleStageNavTitleCtx
---@field isFirstClear boolean
---@field idleRangeText string|nil
---@field maxStageId number
---@field getStageConfig fun(): table
---@field getRelativeChapter fun(chapter: number): number
---@field stageName string
---@field battleActive boolean
---@field firstClearTimeLeft number|nil

---@param ctx BattleStageNavTitleCtx
---@return string|nil idleRangeText
function M.drawStageTitle(vg, ctx)
    local NAV = M.NAV
    local idleRangeText = ctx.idleRangeText
    if not ctx.isFirstClear then
        if not idleRangeText then
            local stageConfig = ctx.getStageConfig()
            local stages = require("shared.StageUtils").collectPrevStages(ctx.maxStageId, 5, stageConfig)
            if #stages > 0 then
                local last = stages[#stages]
                local first = stages[1]
                local diffName = stageConfig.getDifficultyDisplayName(stageConfig.getDifficulty(first.id))
                idleRangeText = string.format("%s %d-%d 至 %d-%d",
                    diffName, ctx.getRelativeChapter(last.chapter), last.stage,
                    ctx.getRelativeChapter(first.chapter), first.stage)
            else
                idleRangeText = "挂机中"
            end
        end
        -- 仅在 draw 拆开既有原文范围；返回值仍保留原文，切语言无需重建缓存。
        local displayRangeText = I18n.lookup(idleRangeText)
        local rangeDiff, startStage, endStage = idleRangeText:match("^([^%s]+) (%d+%-%d+) 至 (%d+%-%d+)$")
        if rangeDiff then
            displayRangeText = I18n.format("%s %s 至 %s",
                I18n.difficulty(rangeDiff), startStage, endStage)
        end
        BattleDraw.drawTextStroke(vg, NAV.STAGE_CX, NAV.STAGE_CY, displayRangeText,
            fittedFontSize(vg, displayRangeText, 40, 560),
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
        BattleDraw.drawTextStroke(vg, NAV.STAGE_CX, NAV.STAGE_CY + 44, "挂机中...", 30,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 200, 220, 255, 3)
    else
        local displayStageName = I18n.lookup(ctx.stageName)
        BattleDraw.drawTextStroke(vg, NAV.STAGE_CX, NAV.STAGE_CY, displayStageName,
            fittedFontSize(vg, displayStageName, 40, 560),
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
        if ctx.battleActive and ctx.firstClearTimeLeft then
            local secs = math.max(0, math.ceil(ctx.firstClearTimeLeft))
            local urgent = secs <= 30
            local timeLeftText = I18n.format("剩余 %d 秒", secs)
            BattleDraw.drawTextStroke(vg, NAV.STAGE_CX, NAV.STAGE_CY + 48,
                timeLeftText, fittedFontSize(vg, timeLeftText, 34, 560),
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                urgent and 255 or 255, urgent and 144 or 255, urgent and 144 or 255, 4,
                { strokeColor = { 0x31, 0x24, 0x24 } })
        end
        if StageBerserk.isActive() then
            local bElapsed = StageBerserk.getElapsed()
            local bPhase   = StageBerserk.getRagePhase()
            local tText, tR, tG, tB
            if bPhase == 2 then
                tText = I18n.format("超级狂暴! %.0fs", bElapsed)
                tR, tG, tB = 255, 34, 34
            elseif bPhase == 1 then
                tText = I18n.format("狂暴中 %.0fs", bElapsed)
                tR, tG, tB = 255, 102, 0
            else
                tText = I18n.format("已用时 %.0fs", bElapsed)
                tR, tG, tB = 255, 255, 255
            end
            local subY = (ctx.battleActive and ctx.firstClearTimeLeft) and (NAV.STAGE_CY + 92) or (NAV.STAGE_CY + 48)
            BattleDraw.drawTextStroke(vg, NAV.STAGE_CX, subY, tText, fittedFontSize(vg, tText, 34, 560),
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, tR, tG, tB, 4,
                { strokeColor = { 0x31, 0x24, 0x24 } })
        end
    end
    return idleRangeText
end

---@class BattleStageNavButtonsCtx
---@field isFirstClear boolean
---@field isTerminal boolean
---@field currentStageId number
---@field maxStageId number
---@field getStageConfig fun(): table
---@field imgBtnBack number
---@field imgBtnIcon number
---@field imgBtnFwd number
---@field imgBtnFwdGrey number

function M.drawNavButtons(vg, ctx)
    local NAV = M.NAV
    if ctx.isFirstClear then
        local backAlpha = ctx.isTerminal and 0.3 or 1.0
        BattleDraw.drawImageMirrored(vg, ctx.imgBtnBack, NAV.BACK_BG_CX, NAV.BACK_BG_CY, NAV.BACK_BG_W, NAV.BACK_BG_H, backAlpha)
        BattleDraw.drawImageMirrored(vg, ctx.imgBtnIcon, NAV.BACK_ICON_CX, NAV.BACK_ICON_CY, NAV.BACK_ICON_W, NAV.BACK_ICON_H, backAlpha)
        -- 按钮文字：可用=亮白，终点禁用=灰蓝色
        local backR, backG, backB = 255, 255, 255
        if ctx.isTerminal then backR, backG, backB = 0x8b, 0x95, 0xa5 end
        BattleDraw.drawTextStroke(vg, NAV.BACK_TEXT_CX, NAV.BACK_TEXT_CY, "后退", 40,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, backR, backG, backB, 4)
    end

    if not ctx.isFirstClear then
        local canAdvance = not ctx.isTerminal
        local fwdImg = canAdvance and ctx.imgBtnFwd or ctx.imgBtnFwdGrey
        BattleDraw.drawImageCentered(vg, fwdImg, NAV.FWD_BG_CX, NAV.FWD_BG_CY, NAV.FWD_BG_W, NAV.FWD_BG_H, 1.0)
        local fwdAlpha = canAdvance and 1.0 or 0.4
        local stageConfig = ctx.getStageConfig()
        local nextId = stageConfig.getNextStageId(ctx.currentStageId)
        local fwdFloating = canAdvance and nextId ~= nil
            and (nextId > ctx.maxStageId or stageConfig.isTerminalTemple(nextId))
        local fwdFloatX = fwdFloating and math.sin(time.elapsedTime * 3.0) * 10 or 0
        local fwdBlink = fwdFloating and (0.5 + 0.5 * math.sin(time.elapsedTime * 10.0)) or 1.0
        local fwdIconAlpha = fwdAlpha * (fwdFloating and (0.55 + 0.45 * fwdBlink) or 1.0)
        BattleDraw.drawImageCentered(vg, ctx.imgBtnIcon, NAV.FWD_ICON_CX + fwdFloatX, NAV.FWD_ICON_CY, NAV.FWD_ICON_W, NAV.FWD_ICON_H, fwdIconAlpha)
        -- 按钮文字：可前进=亮白（浮动态闪烁），终点禁用=棕色
        local fwdCBase, fwdCg, fwdCb = 255, 255, 255
        if not canAdvance then
            fwdCBase, fwdCg, fwdCb = 0x8b, 0x95, 0xa5
        elseif fwdFloating then
            fwdCg = math.floor(220 + (255 - 220) * fwdBlink)
            fwdCb = math.floor(60  + (255 - 60)  * fwdBlink)
        end
        BattleDraw.drawTextStroke(vg, NAV.FWD_TEXT_CX + fwdFloatX, NAV.FWD_TEXT_CY, "前进", 40,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, fwdCBase, fwdCg, fwdCb, 4)
    end
end

function M.drawTeamLabel(vg)
    BattleDraw.drawTextStroke(vg, 540, 2046, "我的队伍", 40,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
end

return M
