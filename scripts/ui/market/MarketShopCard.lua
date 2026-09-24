-- ============================================================================
-- MarketShopCard - 市场商品卡绘制（玩法不变）
-- ============================================================================

local DarkIcon = require("core.DarkIcon")

local M = {}

function M.bind(deps)
    local SL = deps.SL
    local DLG = deps.DLG
    local P1 = deps.P1
    local DESIGN_W = deps.DESIGN_W
    local SHOP_ITEMS = deps.SHOP_ITEMS
    local BF = deps.BF
    local img = deps.img
    local state = deps.state
    local drawImageCentered = deps.drawImageCentered
    local drawTextStroke = deps.drawTextStroke
    local getActualPrice = deps.getActualPrice
    local getCooldownRemaining = deps.getCooldownRemaining
    local getPopupAnim = deps.getPopupAnim
    local getPurchased = deps.getPurchased
    local isSoldOut = deps.isSoldOut

    local function drawShopCard(vg, idx, item, cx, cy)
    -- [暗黑化 P1-B5] 矢量卡底 + 品质语义描边
    local q = item.quality or 1
    DarkIcon.drawNine(vg, "plain",
        cx - SL.CARD_W * 0.5, cy - SL.CARD_H * 0.5,
        SL.CARD_W, SL.CARD_H,
        { accent = DarkIcon.QUALITY_TRIM[math.min(6, math.max(1, q))] })

    local bought = getPurchased(item.id)
    local soldOut = isSoldOut(item)

    -- 商品区
    drawTextStroke(vg, cx, cy + SL.NAME_OY, item.name,
        SL.NAME_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, SL.NAME_SW, { strokeColor = { 0, 0, 0 } })

    -- 商品图标
    local iconImg = img.itemIcons[idx]
    if iconImg and iconImg >= 0 then
        drawImageCentered(vg, iconImg, cx, cy + SL.ICON_OY, SL.ICON_W, SL.ICON_H, soldOut and 0.4 or 1.0)
    end

    -- 数量角标
    drawTextStroke(vg, cx + SL.COUNT_OX, cy + SL.COUNT_OY, tostring(item.rewardCount or 1),
        SL.COUNT_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        255, 255, 255, SL.COUNT_SW, { strokeColor = { 0, 0, 0 } })

    -- 限购文本（仅限购商品显示；不限购不显示）
    if item.limitCount ~= -1 then
        local remaining = item.limitCount - bought
        if remaining < 0 then remaining = 0 end
        local limitText
        if item.restockType == "cooldown" then
            local cdLeft = getCooldownRemaining(item)
            local cdStr
            if cdLeft > 0 then
                local h = math.floor(cdLeft / 3600)
                local m = math.floor((cdLeft % 3600) / 60)
                local s = cdLeft % 60
                cdStr = string.format("%d:%02d:%02d", h, m, s)
            else
                cdStr = item.restockPeriod or "2h"
            end
            limitText = "限购" .. remaining .. "分" .. cdStr
        elseif item.restockType == "daily" then
            limitText = "限购" .. remaining .. "份/日"
        else
            limitText = "限购" .. remaining .. "份"
        end
        nvgFontFace(vg, "sans"); nvgFontSize(vg, SL.LIMIT_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(SL.LIMIT_R, SL.LIMIT_G, SL.LIMIT_B, 255))
        nvgText(vg, cx, cy + SL.LIMIT_OY, limitText, nil)
    end

    -- 购买按钮
    ---@diagnostic disable-next-line: assign-type-mismatch
    local btnCY = cy + SL.BTN_OY
    ---@diagnostic disable-next-line: assign-type-mismatch
    local _sc = BF.begin(vg, "market_buy_" .. idx, cx, btnCY, SL.BTN_W, SL.BTN_H)
    if soldOut then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - SL.BTN_W * 0.5, btnCY - SL.BTN_H * 0.5, SL.BTN_W, SL.BTN_H, 12)
        nvgFillColor(vg, nvgRGBA(80, 80, 80, 200))
        nvgFill(vg)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, SL.BTN_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
        nvgText(vg, cx, btnCY, "已售罄", nil)
    else
        DarkIcon.drawNine(vg, "btn", cx - SL.BTN_W * 0.5, btnCY - SL.BTN_H * 0.5, SL.BTN_W, SL.BTN_H, { accent = "gold" })

        local actualPrice = getActualPrice(item)
        local priceStr = tostring(actualPrice)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, SL.BTN_FONT)
        local bounds = {}
        local textW = nvgTextBounds(vg, 0, 0, priceStr, nil, bounds)
        local iconW = SL.BTN_ICON_W
        local iconH = SL.BTN_ICON_H
        local gap = 4

        local totalW = iconW + gap + textW
        local startX = cx - totalW * 0.5

        local costImg = img.costIcons[idx]
        if costImg and costImg >= 0 then
            drawImageCentered(vg, costImg, startX + iconW * 0.5, btnCY, iconW, iconH, 1.0)
        end
        drawTextStroke(vg, startX + iconW + gap, btnCY, priceStr,
            SL.BTN_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            255, 255, 255, SL.BTN_SW, { strokeColor = { 0, 0, 0 } })
    end
    BF.finish(vg, _sc)
    end
    return { drawShopCard = drawShopCard }
end

return M
