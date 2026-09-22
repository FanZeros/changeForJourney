-- ============================================================================
-- MarketCollection - 市场典藏神器宝箱绘制 / 钥匙确认（玩法不变）
-- ============================================================================

local DarkIcon = require("core.DarkIcon")
local GameState = require("core.GameState")
local PlayerStore = require("client.data.PlayerStore")
local StageConfig = require("config.StageConfig")
local ArtifactDefs = require("shared.artifact.ArtifactDefs")

local M = {}

function M.bind(deps)
    local COL = deps.COL
    local P1 = deps.P1
    local KEY_CF = deps.KEY_CF
    local DESIGN_W = deps.DESIGN_W
    local DESIGN_H = deps.DESIGN_H
    local BF = deps.BF
    local img = deps.img
    local state = deps.state
    local QUALITY_COLORS = deps.QUALITY_COLORS
    local POPUP_OPEN_DUR = deps.POPUP_OPEN_DUR
    local POPUP_CLOSE_DUR = deps.POPUP_CLOSE_DUR
    local POPUP_SCALE_FROM = deps.POPUP_SCALE_FROM
    local POPUP_SCALE_TO = deps.POPUP_SCALE_TO
    local easeOutCubic = deps.easeOutCubic
    local easeInCubic = deps.easeInCubic
    local drawImageCentered = deps.drawImageCentered
    local drawTextStroke = deps.drawTextStroke
    local Protocol = deps.Protocol
    local getSendAction = deps.getSendAction
    local getDayId = deps.getDayId
    local hasArtifactFreeDraw = deps.hasArtifactFreeDraw

    local function isArtifactChestUnlocked()
        local battle = PlayerStore.Get("battle")
        return StageConfig.hasReachedNightmare(battle)
    end

    local function drawLockedContent(vg)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 48)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
        nvgText(vg, 540, 1100, "敬请期待", nil)

        nvgFontSize(vg, 36)
        nvgFillColor(vg, nvgRGBA(150, 150, 150, 200))
        nvgText(vg, 540, 1170, "该功能尚未开放", nil)
    end

    local function drawCollectionLockedContent(vg)
        drawImageCentered(vg, img.titleDeco, P1.DECO_CX, P1.DECO_CY, P1.DECO_W, P1.DECO_H, 1.0)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, COL.TITLE_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(COL.TITLE_R, COL.TITLE_G, COL.TITLE_B, 255))
        nvgText(vg, COL.TITLE_CX, COL.TITLE_CY, "典藏", nil)

        drawImageCentered(vg, img.collectionChestBg, COL.CHEST_CX, COL.CHEST_CY, COL.CHEST_W, COL.CHEST_H, 0.45)
        drawTextStroke(vg, COL.NAME_X, COL.NAME_Y, "神器宝箱", COL.NAME_FONT,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            180, 180, 180, 6, { strokeColor = { 0, 0, 0 }, italic = true })

        nvgFontFace(vg, "sans"); nvgFontSize(vg, 40)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(141, 95, 65, 255))
        nvgText(vg, 540, 1320, "抵达噩梦难度后开放", nil)

        local progress = StageConfig.formatProgressDisplay(
            (PlayerStore.Get("battle") or {}).maxStageId or 0)
        nvgFontSize(vg, 32)
        nvgFillColor(vg, nvgRGBA(150, 150, 150, 220))
        nvgText(vg, 540, 1380, "当前进度：" .. progress, nil)
    end

    local function drawRichTextCentered(vg, x, y, fontSize, strokeWidth, segments)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        local totalW = 0
        for _, seg in ipairs(segments) do
            totalW = totalW + nvgTextBounds(vg, 0, 0, seg.text)
        end
        local cursorX = x - totalW * 0.5
        for _, seg in ipairs(segments) do
            local w = nvgTextBounds(vg, 0, 0, seg.text)
            local c = seg.color or { 255, 255, 255 }
            drawTextStroke(vg, cursorX, y, seg.text, fontSize,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                c[1], c[2], c[3], strokeWidth, { strokeColor = { 0, 0, 0 }, italic = seg.italic == true })
            cursorX = cursorX + w
        end
    end

    local function drawPityText(vg, x, y, leftCount, qualityText, qualityColor)
        drawRichTextCentered(vg, x, y, COL.PITY_FONT, 4, {
            { text = tostring(leftCount), color = { 0xff, 0xe8, 0x28 } },
            { text = "次内必得", color = { 255, 255, 255 } },
            { text = qualityText, color = qualityColor },
            { text = "神器", color = { 255, 255, 255 } },
        })
    end

    local function getCollectionPityLeft()
        local artifacts = PlayerStore.Get("artifacts") or {}
        local rareCount = tonumber(artifacts.pityRare) or 0
        local epicCount = tonumber(artifacts.pityEpic) or 0
        local rareLeft = ArtifactDefs.PITY_RARE - rareCount
        local epicLeft = ArtifactDefs.PITY_EPIC - epicCount
        return math.max(1, rareLeft), math.max(1, epicLeft)
    end

    local function getKeyCost(count)
        if count == 1 and hasArtifactFreeDraw() then return 0 end
        return ArtifactDefs.DRAW_KEY_COST[count] or count
    end

    local function sendArtifactDraw(count)
        local fn = getSendAction and getSendAction() or nil
        if not fn then return false end
        local payType = (count == 1 and hasArtifactFreeDraw()) and "free_daily" or "diamond"
        fn(Protocol.ACTION_TYPES.ARTIFACT_DRAW, { count = count, payType = payType })
        return true
    end

    local function openKeyConfirm(count, needKeys, diamondCost)
        state.keyConfirmVisible = true
        state.keyConfirmClosing = false
        state.keyConfirmCount = count
        state.keyConfirmNeedKeys = needKeys
        state.keyConfirmDiamondCost = diamondCost
        state.keyConfirmAnimTime = time.elapsedTime
    end

    local function closeKeyConfirm()
        if not state.keyConfirmVisible then return end
        state.keyConfirmClosing = true
        state.keyConfirmCloseTime = time.elapsedTime
    end

    local function getKeyConfirmAnim()
        if state.keyConfirmClosing then
            local t = math.min((time.elapsedTime - state.keyConfirmCloseTime) / POPUP_CLOSE_DUR, 1.0)
            if t >= 1.0 then
                state.keyConfirmVisible = false
                state.keyConfirmClosing = false
                return POPUP_SCALE_FROM, 0
            end
            local scale = POPUP_SCALE_TO + (POPUP_SCALE_FROM - POPUP_SCALE_TO) * easeInCubic(t)
            return scale, 1.0 - t
        end
        local t = math.min((time.elapsedTime - state.keyConfirmAnimTime) / POPUP_OPEN_DUR, 1.0)
        local scale = POPUP_SCALE_FROM + (POPUP_SCALE_TO - POPUP_SCALE_FROM) * easeOutCubic(t)
        return scale, t
    end

    local function checkKeyAndDraw(count)
        local keyCost = getKeyCost(count)
        local keys = GameState.getGoldenKey()
        if keyCost <= 0 or keys >= keyCost then
            if sendArtifactDraw(count) then
                state.floatText = "正在开启宝箱"
                state.floatTextX = count == 10 and COL.BTN_TEN_X or COL.BTN_ONE_X
                state.floatTextY = COL.BTN_Y - 120
                state.floatTextTime = time.elapsedTime
            else
                state.floatText = "网络未连接"
                state.floatTextX = 540
                state.floatTextY = COL.BTN_Y - 120
                state.floatTextTime = time.elapsedTime
            end
            return true
        end

        local shortfall = keyCost - keys
        local diamondCost = shortfall * ArtifactDefs.KEY_DIAMOND_PRICE
        openKeyConfirm(count, shortfall, diamondCost)
        print(string.format("[MarketPage] 黄金钥匙不足: 需%d 有%d 补购%d把 花费%d钻",
            keyCost, keys, shortfall, diamondCost))
        return false
    end

    local function drawCollectionDrawButton(vg, id, cx, countText, keyCost)
        local bf = BF.begin(vg, id, cx, COL.BTN_Y, COL.BTN_W, COL.BTN_H)
        drawImageCentered(vg, img.collectionDrawBtn, cx, COL.BTN_Y, COL.BTN_W, COL.BTN_H, 1.0)
        drawTextStroke(vg, cx, COL.BTN_TEXT_Y, countText, COL.BTN_FONT,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4, { strokeColor = { 0, 0, 0 } })

        local costStr = keyCost <= 0 and "免费" or ("x" .. tostring(keyCost))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, COL.COST_FONT)
        local costTextW = nvgTextBounds(vg, 0, 0, costStr)
        local gap = 8
        local totalW = COL.COST_ICON_SIZE + gap + costTextW
        local iconX = cx - totalW * 0.5 + COL.COST_ICON_SIZE * 0.5
        local textX = iconX + COL.COST_ICON_SIZE * 0.5 + gap
        local keyIcon = img.goldenKey >= 0 and img.goldenKey or img.gem
        drawImageCentered(vg, keyIcon, iconX, COL.COST_ICON_Y, COL.COST_ICON_SIZE, COL.COST_ICON_SIZE, 1.0)
        drawTextStroke(vg, textX, COL.COST_TEXT_Y, costStr, COL.COST_FONT,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4, { strokeColor = { 0, 0, 0 } })
        BF.finish(vg, bf)
    end

    local function drawKeyConfirmDialog(vg)
        if not state.keyConfirmVisible then return end

        local pScale, pAlpha = getKeyConfirmAnim()
        if pAlpha <= 0.01 then return end

        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(KEY_CF.MASK_A * pAlpha)))
        nvgFill(vg)

        nvgSave(vg)
        nvgTranslate(vg, KEY_CF.CX, KEY_CF.CY)
        nvgScale(vg, pScale, pScale)
        nvgTranslate(vg, -KEY_CF.CX, -KEY_CF.CY)
        nvgGlobalAlpha(vg, pAlpha)

        DarkIcon.drawNine(vg, "panel", KEY_CF.CX - KEY_CF.W * 0.5, KEY_CF.CY - KEY_CF.H * 0.5, KEY_CF.W, KEY_CF.H, { titleH = 150 })

        drawTextStroke(vg, KEY_CF.TITLE_CX, KEY_CF.TITLE_CY, "黄金钥匙不足",
            KEY_CF.TITLE_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, KEY_CF.TITLE_STROKE_W, { strokeColor = { 0x59, 0x32, 0x19 } })

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, KEY_CF.SUB_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(KEY_CF.SUB_R, KEY_CF.SUB_G, KEY_CF.SUB_B, 255))
        nvgText(vg, KEY_CF.SUB_CX, KEY_CF.SUB_CY, "是否使用钻石快速购买", nil)

        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            KEY_CF.CONTENT_CX - KEY_CF.CONTENT_W * 0.5,
            KEY_CF.CONTENT_CY - KEY_CF.CONTENT_H * 0.5,
            KEY_CF.CONTENT_W, KEY_CF.CONTENT_H, KEY_CF.CONTENT_R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, KEY_CF.CONTENT_A))
        nvgFill(vg)

        drawImageCentered(vg, img.confirmArrow, KEY_CF.ARROW_CX, KEY_CF.ARROW_CY, KEY_CF.ARROW_W, KEY_CF.ARROW_H, 1.0)
        DarkIcon.drawQualityBg(vg, 6, KEY_CF.DIAMOND_CX, KEY_CF.DIAMOND_CY, KEY_CF.DIAMOND_W, KEY_CF.DIAMOND_H, 1.0)
        drawImageCentered(vg, img.diamondBig, KEY_CF.DIAMOND_CX, KEY_CF.DIAMOND_CY, KEY_CF.DIAMOND_W, KEY_CF.DIAMOND_H, 1.0)
        DarkIcon.drawQualityBg(vg, 6, KEY_CF.KEY_CX, KEY_CF.KEY_CY, KEY_CF.KEY_W, KEY_CF.KEY_H, 1.0)
        drawImageCentered(vg, img.goldenKey, KEY_CF.KEY_CX, KEY_CF.KEY_CY, KEY_CF.KEY_W, KEY_CF.KEY_H, 1.0)

        local diamondEnough = GameState.getGems() >= state.keyConfirmDiamondCost
        local dBadgeR, dBadgeG, dBadgeB = 255, 255, 255
        if not diamondEnough then dBadgeR, dBadgeG, dBadgeB = 255, 50, 50 end
        drawTextStroke(vg,
            KEY_CF.DIAMOND_CX + KEY_CF.BADGE_OX, KEY_CF.DIAMOND_CY + KEY_CF.BADGE_OY,
            tostring(state.keyConfirmDiamondCost),
            KEY_CF.BADGE_SIZE, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
            dBadgeR, dBadgeG, dBadgeB, KEY_CF.BADGE_STROKE_W, { strokeColor = { 0, 0, 0 } })
        drawTextStroke(vg,
            KEY_CF.KEY_CX + KEY_CF.BADGE_OX, KEY_CF.KEY_CY + KEY_CF.BADGE_OY,
            tostring(state.keyConfirmNeedKeys),
            KEY_CF.BADGE_SIZE, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
            255, 255, 255, KEY_CF.BADGE_STROKE_W, { strokeColor = { 0, 0, 0 } })

        local _bfBuy = BF.begin(vg, "market_key_confirm", KEY_CF.BUY_CX, KEY_CF.BUY_CY, KEY_CF.BUY_W, KEY_CF.BUY_H)
        DarkIcon.drawNine(vg, "btn", KEY_CF.BUY_CX - KEY_CF.BUY_W * 0.5, KEY_CF.BUY_CY - KEY_CF.BUY_H * 0.5, KEY_CF.BUY_W, KEY_CF.BUY_H, { accent = "gold" })
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, KEY_CF.BUY_TEXT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(KEY_CF.BUY_TEXT_R, KEY_CF.BUY_TEXT_G, KEY_CF.BUY_TEXT_B, 255))
        nvgText(vg, KEY_CF.BUY_CX, KEY_CF.BUY_CY, "购买", nil)
        BF.finish(vg, _bfBuy)

        nvgRestore(vg)
    end

    local function drawCollectionContent(vg)
        if not isArtifactChestUnlocked() then
            drawCollectionLockedContent(vg)
            return
        end

        drawImageCentered(vg, img.titleDeco, P1.DECO_CX, P1.DECO_CY, P1.DECO_W, P1.DECO_H, 1.0)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, COL.TITLE_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(COL.TITLE_R, COL.TITLE_G, COL.TITLE_B, 255))
        nvgText(vg, COL.TITLE_CX, COL.TITLE_CY, "典藏", nil)

        drawImageCentered(vg, img.collectionChestBg, COL.CHEST_CX, COL.CHEST_CY, COL.CHEST_W, COL.CHEST_H, 1.0)

        drawTextStroke(vg, COL.NAME_X, COL.NAME_Y, "神器宝箱", COL.NAME_FONT,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 6, { strokeColor = { 0, 0, 0 }, italic = true })

        drawRichTextCentered(vg, COL.DESC_X, COL.DESC_Y - 18, COL.DESC_FONT, 4, {
            { text = "获得100金币，赠送", color = { 255, 255, 255 } },
            { text = "普通", color = QUALITY_COLORS.normal },
            { text = "、", color = { 255, 255, 255 } },
            { text = "优质", color = QUALITY_COLORS.good },
            { text = "、", color = { 255, 255, 255 } },
        })
        drawRichTextCentered(vg, COL.DESC_X, COL.DESC_Y + 18, COL.DESC_FONT, 4, {
            { text = "稀有", color = QUALITY_COLORS.rare },
            { text = "、", color = { 255, 255, 255 } },
            { text = "史诗", color = QUALITY_COLORS.epic },
            { text = "品质神器", color = { 255, 255, 255 } },
        })

        local rareLeft, epicLeft = getCollectionPityLeft()

        nvgBeginPath(vg)
        nvgRoundedRect(vg, COL.RARE_PITY_X - COL.PITY_W * 0.5, COL.RARE_PITY_Y - COL.PITY_H * 0.5,
            COL.PITY_W, COL.PITY_H, COL.PITY_R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, COL.PITY_A)); nvgFill(vg)
        drawPityText(vg, COL.RARE_PITY_X, COL.RARE_PITY_Y, rareLeft, "稀有", QUALITY_COLORS.rare)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, COL.EPIC_PITY_X - COL.PITY_W * 0.5, COL.EPIC_PITY_Y - COL.PITY_H * 0.5,
            COL.PITY_W, COL.PITY_H, COL.PITY_R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, COL.PITY_A)); nvgFill(vg)
        drawPityText(vg, COL.EPIC_PITY_X, COL.EPIC_PITY_Y, epicLeft, "史诗", QUALITY_COLORS.epic)

        local oneCost = getKeyCost(1)
        local oneText = oneCost <= 0 and "免费单抽" or "抽1次"
        drawCollectionDrawButton(vg, "collection_draw_1", COL.BTN_ONE_X, oneText, oneCost)
        drawCollectionDrawButton(vg, "collection_draw_10", COL.BTN_TEN_X, "抽10次", COL.TEN_KEY)
    end

    return {
        isArtifactChestUnlocked = isArtifactChestUnlocked,
        drawLockedContent = drawLockedContent,
        drawCollectionContent = drawCollectionContent,
        drawKeyConfirmDialog = drawKeyConfirmDialog,
        checkKeyAndDraw = checkKeyAndDraw,
        closeKeyConfirm = closeKeyConfirm,
        getKeyCost = getKeyCost,
        getCollectionPityLeft = getCollectionPityLeft,
        sendArtifactDraw = sendArtifactDraw,
        getDayId = getDayId,
    }
end

return M
