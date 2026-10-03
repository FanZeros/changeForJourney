-- ============================================================================
-- TerminalConfirmDialog - 终焉神殿进入确认弹窗
-- 从 BattleScene 抽出，行为与原实现保持一致
-- ============================================================================

local DarkIcon = require("core.DarkIcon")
local BattleDraw = require("ui.battle.scene.BattleDraw")
local I18n = require("core.I18n")

local M = {}

-- 译文在既有单行槽位内缩字号，避免改动弹窗布局或按钮命中区域。
local function fittedFontSize(vg, text, fontSize, maxWidth)
    nvgSave(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local width = nvgTextBounds(vg, 0, 0, text)
    nvgRestore(vg)
    return width > maxWidth and (fontSize * maxWidth / width) or fontSize
end

local DESIGN_W = 1080

local confirmDialog = {
    open     = false,
    closing  = false,
    openTime = 0,
    closeTime = 0,
    pendingNextId = nil,
}

local CONFIRM_OPEN_DUR  = 0.25
local CONFIRM_CLOSE_DUR = 0.20
local CONFIRM_SCALE_FROM = 0.8
local CONFIRM_SCALE_TO   = 1.0

-- 弹窗布局常量（设计分辨率 1080×2400，对齐购买道具弹窗样式）
local CDL = {
    BG_CX = 540, BG_CY = 1100, BG_W = 950, BG_H = 647,
    TITLE_CY  = 847,  TITLE_FONT = 60, TITLE_SW = 6,
    TITLE_SR = 0x46, TITLE_SG = 0x2f, TITLE_SB = 0x20,
    SUB_CY = 960, SUB_FONT = 40,
    LINE1_CY  = 1060, LINE_FONT  = 38,
    LINE2_CY  = 1120,
    LINE3_CY  = 1180, LINE3_FONT = 32,
    OK_CX = 340, OK_CY = 1310, OK_W = 310, OK_H = 100, OK_FONT = 40,
    OK_TR = 0x2a, OK_TG = 0x52, OK_TB = 0x18,
    CANCEL_CX = 740, CANCEL_CY = 1310, CANCEL_W = 310, CANCEL_H = 100, CANCEL_FONT = 40,
    CANCEL_TR = 0x50, CANCEL_TG = 0x46, CANCEL_TB = 0x3c,
}

local function easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end

local function easeInCubic(t)
    return t * t * t
end

---@return number scale, number alpha, boolean done
local function getConfirmAnim()
    if confirmDialog.closing then
        local t = math.min(1.0, (time.elapsedTime - confirmDialog.closeTime) / CONFIRM_CLOSE_DUR)
        local e = easeInCubic(t)
        local scale = CONFIRM_SCALE_TO + (CONFIRM_SCALE_FROM - CONFIRM_SCALE_TO) * e
        return scale, 1.0 - e, (t >= 1.0)
    else
        local t = math.min(1.0, (time.elapsedTime - confirmDialog.openTime) / CONFIRM_OPEN_DUR)
        local e = easeOutCubic(t)
        local scale = CONFIRM_SCALE_FROM + (CONFIRM_SCALE_TO - CONFIRM_SCALE_FROM) * e
        return scale, e, false
    end
end

function M.isOpen()
    return confirmDialog.open or confirmDialog.closing
end

function M.open(nextId)
    confirmDialog.open = true
    confirmDialog.closing = false
    confirmDialog.openTime = time.elapsedTime
    confirmDialog.pendingNextId = nextId
    print("[TerminalConfirmDialog] 终焉神殿确认弹窗打开, nextId=" .. tostring(nextId))
end

--- 绘制终焉神殿确认弹窗
---@param vg userdata
---@param currentStageId number
---@param getStageConfig fun(): table
function M.draw(vg, currentStageId, getStageConfig)
    if not confirmDialog.open and not confirmDialog.closing then return end

    local pScale, pAlpha, done = getConfirmAnim()
    if confirmDialog.closing and done then
        confirmDialog.closing = false
        confirmDialog.open = false
        confirmDialog.pendingNextId = nil
        return
    end

    local stageConfig = getStageConfig()
    local currentDiff = stageConfig.getDifficulty(currentStageId)
    local nextDiff = stageConfig.getNextDifficulty(currentDiff)
    local nextDiffName = stageConfig.getDifficultyDisplayName(nextDiff)

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * pAlpha)))
    nvgFill(vg)

    nvgSave(vg)
    nvgTranslate(vg, CDL.BG_CX, CDL.BG_CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -CDL.BG_CX, -CDL.BG_CY)
    nvgGlobalAlpha(vg, pAlpha)

    DarkIcon.drawNine(vg, "panel", CDL.BG_CX - CDL.BG_W * 0.5, CDL.BG_CY - CDL.BG_H * 0.5, CDL.BG_W, CDL.BG_H, { titleH = 40 })

    -- 标记不参与原名匹配；所有译文都是本帧显示变量。
    local titleText = "\u{26a0} " .. I18n.lookup("终焉神殿")
    local textWidth = CDL.BG_W - 120
    BattleDraw.drawTextStroke(vg, CDL.BG_CX, CDL.TITLE_CY, titleText,
        fittedFontSize(vg, titleText, CDL.TITLE_FONT, textWidth),
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, CDL.TITLE_SW,
        { strokeColor = { CDL.TITLE_SR, CDL.TITLE_SG, CDL.TITLE_SB } })

    local subText = I18n.lookup("确认进入终焉神殿？")
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fittedFontSize(vg, subText, CDL.SUB_FONT, textWidth))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 255))
    nvgText(vg, CDL.BG_CX, CDL.SUB_CY, subText, nil)

    local line1Text = I18n.lookup("进入后将无法退出")
    local line2Text = I18n.format("通关后进入「%s」轮回", I18n.difficulty(nextDiffName))
    nvgFontSize(vg, fittedFontSize(vg, line1Text, CDL.LINE_FONT, textWidth))
    nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
    nvgText(vg, CDL.BG_CX, CDL.LINE1_CY, line1Text, nil)
    nvgFontSize(vg, fittedFontSize(vg, line2Text, CDL.LINE_FONT, textWidth))
    nvgText(vg, CDL.BG_CX, CDL.LINE2_CY, line2Text, nil)

    local line3Text = I18n.lookup("（挑战失败将回退到上一关）")
    nvgFontSize(vg, fittedFontSize(vg, line3Text, CDL.LINE3_FONT, textWidth))
    nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 200))
    nvgText(vg, CDL.BG_CX, CDL.LINE3_CY, line3Text, nil)

    local okText = I18n.lookup("进入")
    DarkIcon.drawNine(vg, "btn", CDL.OK_CX - CDL.OK_W * 0.5, CDL.OK_CY - CDL.OK_H * 0.5, CDL.OK_W, CDL.OK_H, { accent = "green" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, fittedFontSize(vg, okText, CDL.OK_FONT, CDL.OK_W - 60))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(CDL.OK_TR, CDL.OK_TG, CDL.OK_TB, 255))
    nvgText(vg, CDL.OK_CX, CDL.OK_CY, okText, nil)

    local cancelText = I18n.lookup("取消")
    DarkIcon.drawNine(vg, "btn", CDL.CANCEL_CX - CDL.CANCEL_W * 0.5, CDL.CANCEL_CY - CDL.CANCEL_H * 0.5, CDL.CANCEL_W, CDL.CANCEL_H, { accent = "green" })
    nvgFontFace(vg, "sans"); nvgFontSize(vg, fittedFontSize(vg, cancelText, CDL.CANCEL_FONT, CDL.CANCEL_W - 60))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(CDL.CANCEL_TR, CDL.CANCEL_TG, CDL.CANCEL_TB, 255))
    nvgText(vg, CDL.CANCEL_CX, CDL.CANCEL_CY, cancelText, nil)

    nvgRestore(vg)
end

function M.update()
    if confirmDialog.closing then
        local _, _, done = getConfirmAnim()
        if done then
            confirmDialog.closing = false
            confirmDialog.open = false
            confirmDialog.pendingNextId = nil
        end
    end
end

--- 处理输入。打开时拦截全部点击。
---@param dx number
---@param dy number
---@param onConfirm fun(nextId: number)
---@return boolean consumed
function M.handleInput(dx, dy, onConfirm)
    if not confirmDialog.open and not confirmDialog.closing then
        return false
    end
    if confirmDialog.closing then return true end
    if (time.elapsedTime - confirmDialog.openTime) < CONFIRM_OPEN_DUR then return true end

    if dx >= CDL.OK_CX - CDL.OK_W * 0.5 and dx <= CDL.OK_CX + CDL.OK_W * 0.5
       and dy >= CDL.OK_CY - CDL.OK_H * 0.5 and dy <= CDL.OK_CY + CDL.OK_H * 0.5 then
        local nextId = confirmDialog.pendingNextId
        confirmDialog.open = false
        confirmDialog.pendingNextId = nil
        if nextId and onConfirm then
            onConfirm(nextId)
        end
        return true
    end

    if dx >= CDL.CANCEL_CX - CDL.CANCEL_W * 0.5 and dx <= CDL.CANCEL_CX + CDL.CANCEL_W * 0.5
       and dy >= CDL.CANCEL_CY - CDL.CANCEL_H * 0.5 and dy <= CDL.CANCEL_CY + CDL.CANCEL_H * 0.5 then
        confirmDialog.closing = true
        confirmDialog.closeTime = time.elapsedTime
        return true
    end

    if dx < CDL.BG_CX - CDL.BG_W * 0.5 or dx > CDL.BG_CX + CDL.BG_W * 0.5
       or dy < CDL.BG_CY - CDL.BG_H * 0.5 or dy > CDL.BG_CY + CDL.BG_H * 0.5 then
        confirmDialog.closing = true
        confirmDialog.closeTime = time.elapsedTime
    end
    return true
end

return M
