-- ============================================================================
-- BackpackDialogs - 背包换行文字 / 转区确认弹窗（玩法不变）
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local PlayerStore = require("client.data.PlayerStore")
local GameState = require("core.GameState")

local M = {}

function M.bind(deps)
    local DESIGN_W = deps.DESIGN_W
    local DESIGN_H = deps.DESIGN_H
    local TRANSFER_CONFIRM = deps.TRANSFER_CONFIRM
    local itemDetState = deps.itemDetState
    local getImgBtnYellow = deps.getImgBtnYellow
    local getImgBtnGreen = deps.getImgBtnGreen

    local function drawWrappedText(vg, x, y, maxW, text, fontSize, r, g, b)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(r, g, b, 255))

        -- 逐字符分割 UTF-8
        local chars = {}
        local i = 1
        local len = #text
        while i <= len do
            local b0 = string.byte(text, i)
            local charLen = 1
            if b0 >= 0xF0 then charLen = 4
            elseif b0 >= 0xE0 then charLen = 3
            elseif b0 >= 0xC0 then charLen = 2
            end
            chars[#chars + 1] = string.sub(text, i, i + charLen - 1)
            i = i + charLen
        end

        local lineY = y
        local lineHeight = fontSize * 1.4
        local lineStart = 1
        while lineStart <= #chars do
            -- 遇到换行符：直接换行
            if chars[lineStart] == "\n" then
                lineY = lineY + lineHeight
                lineStart = lineStart + 1
            else
                -- 尽可能多地放字符到一行（遇到 \n 也截断）
                local lineEnd = lineStart
                for ci = lineStart, #chars do
                    if chars[ci] == "\n" then
                        lineEnd = ci - 1
                        break
                    end
                    local sub = table.concat(chars, "", lineStart, ci)
                    local tw = nvgTextBounds(vg, 0, 0, sub)
                    if tw > maxW and ci > lineStart then
                        lineEnd = ci - 1
                        break
                    end
                    lineEnd = ci
                end
                if lineEnd >= lineStart then
                    local lineStr = table.concat(chars, "", lineStart, lineEnd)
                    nvgText(vg, x, lineY, lineStr, nil)
                end
                lineY = lineY + lineHeight
                lineStart = lineEnd + 1
            end
        end
    end

    local function shouldShowTransferBtn(def)
        if not def or def.key ~= "privilegeCard" then return false end
        if not PlayerStore.IsReady() then return false end
        return GameState.isPrivilegeCardOwned()
    end

    local function drawTransferConfirm(vg)
        local step = itemDetState.transferConfirmStep
        if step <= 0 then return end

        local C = TRANSFER_CONFIRM
        local title = step == 1 and "转区确认" or "再次确认"
        local body = step == 1
            and "确定要将特权卡转至其他区服吗？\n转区后您将立即退出当前区服。"
            or "特权卡将在您进入其他区服后生效（含挑战者服）。\n请勿选回原区服，否则将自动撤销转区。\n是否继续？"

        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
        nvgFill(vg)

        DarkIcon.drawNine(vg, "plain",
            C.BG_CX - C.BG_W * 0.5, C.BG_CY - C.BG_H * 0.5,
            C.BG_W, C.BG_H)

        DrawUtil.drawTextStroke(vg, C.TITLE_CX, C.TITLE_CY, title,
            C.TITLE_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, C.TITLE_SW,
            { strokeColor = { C.TITLE_SR, C.TITLE_SG, C.TITLE_SB } })

        local bodyX = C.BODY_CX - C.BODY_W * 0.5
        local bodyY = C.BODY_CY - 60
        drawWrappedText(vg, bodyX, bodyY, C.BODY_W, body, C.BODY_FONT, C.BODY_R, C.BODY_G, C.BODY_B)

        local imgBtnYellow = getImgBtnYellow()
        local imgBtnGreen = getImgBtnGreen()
        if imgBtnYellow >= 0 then
            DrawUtil.drawImageCentered(vg, imgBtnYellow, C.BTN_OK_CX, C.BTN_CY, C.BTN_W, C.BTN_H, 1.0)
        end
        if imgBtnGreen >= 0 then
            DrawUtil.drawImageCentered(vg, imgBtnGreen, C.BTN_CANCEL_CX, C.BTN_CY, C.BTN_W, C.BTN_H, 1.0)
        end

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, C.BTN_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(C.BTN_OK_R, C.BTN_OK_G, C.BTN_OK_B, 255))
        nvgText(vg, C.BTN_OK_CX, C.BTN_CY, "确认", nil)
        nvgFillColor(vg, nvgRGBA(C.BTN_CANCEL_R, C.BTN_CANCEL_G, C.BTN_CANCEL_B, 255))
        nvgText(vg, C.BTN_CANCEL_CX, C.BTN_CY, "取消", nil)
    end

    local function closeTransferConfirm()
        itemDetState.transferConfirmStep = 0
        itemDetState.transferConfirmOpenTime = 0
    end

    return {
        drawWrappedText = drawWrappedText,
        shouldShowTransferBtn = shouldShowTransferBtn,
        drawTransferConfirm = drawTransferConfirm,
        closeTransferConfirm = closeTransferConfirm,
    }
end

return M
