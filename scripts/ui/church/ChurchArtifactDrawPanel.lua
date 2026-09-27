-- ============================================================================
-- ChurchArtifactDrawPanel.lua
-- 教堂神器页「宝箱」子页签：神器宝箱抽取（从市场·典藏页迁移而来）
-- 职责：宝箱展示 + 保底进度 + 单抽/十连 + 黄金钥匙不足时的黑晶补购弹窗
-- 抽取协议/保底/钥匙补购逻辑与原 MarketCollection 完全一致（玩法不变）
-- 坐标系 1080×2400，绘制在教堂 Tab 内容区
-- ============================================================================

---@diagnostic disable: undefined-global

local GameConfig    = require("config.GameConfig")
local DarkIcon      = require("core.DarkIcon")
local DrawUtil      = require("core.DrawUtil")
local GameState     = require("core.GameState")
local PlayerStore   = require("core.PlayerStore")
local StageConfig   = require("config.StageConfig")
local ArtifactDefs  = require("shared.artifact.ArtifactDefs")
local RewardPopup   = require("ui.hud.popup.RewardPopup")
local BF            = require("systems.ButtonFeedback")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local hitTest           = DrawUtil.hitTest

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

local M = {}

-- ======================== 布局常量 ========================
-- 沿用市场典藏布局，整体下移 CONTENT_OY 使其在教堂内容区更居中
local CONTENT_OY = 300

local COL = {
    TITLE_CX = 540, TITLE_CY = 497 + CONTENT_OY, TITLE_FONT = 42,
    TITLE_R = 0x7b, TITLE_G = 0x53, TITLE_B = 0x39,
    TITLE_W = 660, TITLE_H = 60,
    CHEST_CX = 536, CHEST_CY = 883 + CONTENT_OY, CHEST_W = 984, CHEST_H = 616,
    NAME_X = 795, NAME_Y = 647 + CONTENT_OY, NAME_FONT = 70,
    DESC_X = 788, DESC_Y = 746 + CONTENT_OY, DESC_FONT = 30,
    PITY_W = 380, PITY_H = 70, PITY_R = 35, PITY_A = 128,
    RARE_PITY_X = 782, RARE_PITY_Y = 850 + CONTENT_OY,
    EPIC_PITY_X = 782, EPIC_PITY_Y = 934 + CONTENT_OY,
    PITY_FONT = 30,
    BTN_ONE_X = 323, BTN_TEN_X = 783, BTN_Y = 1081 + CONTENT_OY,
    BTN_W = 316, BTN_H = 122,
    BTN_TEXT_Y = 1058 + CONTENT_OY, BTN_FONT = 32,
    COST_ICON_Y = 1111 + CONTENT_OY, COST_ICON_SIZE = 58,
    COST_TEXT_Y = 1111 + CONTENT_OY, COST_FONT = 30,
    TEN_KEY = ArtifactDefs.DRAW_KEY_COST[10],
}

-- 黄金钥匙不足时的快速购买确认框（居中模态，不随 CONTENT_OY 偏移）
local KEY_CF = {
    MASK_A = 128,
    CX = 540, CY = 1110, W = 950, H = 647,
    TITLE_CX = 540, TITLE_CY = 856, TITLE_SIZE = 50, TITLE_STROKE_W = 6,
    SUB_CX = 540, SUB_CY = 967, SUB_SIZE = 40,
    SUB_R = 0xB6, SUB_G = 0xB0, SUB_B = 0x9D,
    CONTENT_CX = 540, CONTENT_CY = 1121, CONTENT_W = 800, CONTENT_H = 218, CONTENT_R = 16, CONTENT_A = 13,
    ARROW_CX = 540, ARROW_CY = 1123, ARROW_W = 48, ARROW_H = 48,
    DIAMOND_CX = 415, DIAMOND_CY = 1122, DIAMOND_W = 160, DIAMOND_H = 160,
    KEY_CX = 664, KEY_CY = 1122, KEY_W = 160, KEY_H = 160,
    BADGE_SIZE = 40, BADGE_STROKE_W = 5, BADGE_OX = 60, BADGE_OY = 55,
    BUY_CX = 540, BUY_CY = 1301, BUY_W = 410, BUY_H = 100,
    BUY_TEXT_SIZE = 40, BUY_TEXT_R = 0x64, BUY_TEXT_G = 0x51, BUY_TEXT_B = 0x29,
}

local QUALITY_COLORS = {
    normal = { 181, 181, 181 },
    good   = { 162, 255, 148 },
    rare   = { 114, 242, 245 },
    epic   = { 239, 121, 255 },
}

local POPUP_OPEN_DUR   = 0.25
local POPUP_CLOSE_DUR  = 0.20
local POPUP_SCALE_FROM = 0.8
local POPUP_SCALE_TO   = 1.0

local function easeOutCubic(t) return 1 - (1 - t) * (1 - t) * (1 - t) end
local function easeInCubic(t) return t * t * t end

local img = {
    topBg             = -1, -- UI_JTSQ_BJ.png（与神器装配页同一顶部背景）
    titleDeco         = -1,
    collectionChestBg = -1,
    collectionDrawBtn = -1,
    goldenKey         = -1,
    gem               = -1,
    diamondBig        = -1,
    confirmArrow      = -1,
}

local state = {
    keyConfirmVisible = false,
    keyConfirmClosing = false,
    keyConfirmAnimTime = 0,
    keyConfirmCloseTime = 0,
    keyConfirmCount = 1,
    keyConfirmNeedKeys = 0,
    keyConfirmDiamondCost = 0,
    artifactFreeDrawDayId = 0,
}

local ctx_ = nil

-- ======================== 辅助 ========================

local function showFloat(text, x, y)
    if ctx_ and ctx_.state then
        ctx_.state.floatText = text
        ctx_.state.floatTextX = x or 540
        ctx_.state.floatTextY = y or 980
        ctx_.state.floatTextTime = time.elapsedTime
    else
        print("[ChurchArtifactDrawPanel] " .. tostring(text))
    end
end

local function getSendAction()
    if ctx_ and ctx_.getClient then
        local client = ctx_.getClient()
        if client and client.sendAction then return client.sendAction end
    end
    return nil
end

local function getProtocol()
    return (ctx_ and ctx_.getProtocol and ctx_.getProtocol()) or nil
end

local function getDayId()
    return math.floor((os.time() + 28800) / 86400)
end

local function hasArtifactFreeDraw()
    local artifacts = PlayerStore.Get("artifacts") or {}
    local usedDayId = tonumber(artifacts.dailyFreeDrawDayId) or tonumber(state.artifactFreeDrawDayId) or 0
    return usedDayId ~= getDayId()
end

function M.isArtifactChestUnlocked()
    local battle = PlayerStore.Get("battle")
    return StageConfig.hasReachedNightmare(battle)
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
    local fn = getSendAction()
    local Protocol = getProtocol()
    if not fn or not Protocol then return false end
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
            showFloat("正在开启宝箱", count == 10 and COL.BTN_TEN_X or COL.BTN_ONE_X, COL.BTN_Y - 120)
        else
            showFloat("网络未连接", 540, COL.BTN_Y - 120)
        end
        return true
    end

    local shortfall = keyCost - keys
    local diamondCost = shortfall * ArtifactDefs.KEY_DIAMOND_PRICE
    openKeyConfirm(count, shortfall, diamondCost)
    print(string.format("[ChurchArtifactDrawPanel] 黄金钥匙不足: 需%d 有%d 补购%d把 花费%d钻",
        keyCost, keys, shortfall, diamondCost))
    return false
end

-- ======================== 绘制 ========================

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

local function drawCollectionLockedContent(vg)
    drawImageCentered(vg, img.titleDeco, COL.TITLE_CX, COL.TITLE_CY, COL.TITLE_W, COL.TITLE_H, 1.0)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, COL.TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(COL.TITLE_R, COL.TITLE_G, COL.TITLE_B, 255))
    nvgText(vg, COL.TITLE_CX, COL.TITLE_CY, "神器宝箱", nil)

    drawImageCentered(vg, img.collectionChestBg, COL.CHEST_CX, COL.CHEST_CY, COL.CHEST_W, COL.CHEST_H, 0.45)
    drawTextStroke(vg, COL.NAME_X, COL.NAME_Y, "神器宝箱", COL.NAME_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        180, 180, 180, 6, { strokeColor = { 0, 0, 0 }, italic = true })

    nvgFontFace(vg, "sans"); nvgFontSize(vg, 40)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(141, 95, 65, 255))
    nvgText(vg, 540, 1320 + CONTENT_OY, "抵达噩梦难度后开放", nil)

    local progress = StageConfig.formatProgressDisplay(
        (PlayerStore.Get("battle") or {}).maxStageId or 0)
    nvgFontSize(vg, 32)
    nvgFillColor(vg, nvgRGBA(150, 150, 150, 220))
    nvgText(vg, 540, 1380 + CONTENT_OY, "当前进度：" .. progress, nil)
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

--- 「宝箱」页签背景（与神器装配页 drawBg 相同结构：顶部大图 + 下部暗色底板）
function M.drawBg(vg)
    if img.topBg >= 0 then
        drawImageCentered(vg, img.topBg, 540, 674.5, 1080, 1349, 1.0)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, 1349)
        nvgFillColor(vg, nvgRGBA(44, 42, 48, 255))
        nvgFill(vg)
    end
    DarkIcon.drawNine(vg, "plain", 0, 1689 - 1422 * 0.5, 1080, 1422)
end

function M.drawContent(vg)
    if not M.isArtifactChestUnlocked() then
        drawCollectionLockedContent(vg)
        return
    end

    drawImageCentered(vg, img.titleDeco, COL.TITLE_CX, COL.TITLE_CY, COL.TITLE_W, COL.TITLE_H, 1.0)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, COL.TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(COL.TITLE_R, COL.TITLE_G, COL.TITLE_B, 255))
    nvgText(vg, COL.TITLE_CX, COL.TITLE_CY, "神器宝箱", nil)

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
    drawCollectionDrawButton(vg, "church_artifact_draw_1", COL.BTN_ONE_X, oneText, oneCost)
    drawCollectionDrawButton(vg, "church_artifact_draw_10", COL.BTN_TEN_X, "抽10次", COL.TEN_KEY)
end

function M.drawKeyConfirmDialog(vg)
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
    nvgText(vg, KEY_CF.SUB_CX, KEY_CF.SUB_CY, "是否使用黑晶快速购买", nil)

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

    local _bfBuy = BF.begin(vg, "church_artifact_key_confirm", KEY_CF.BUY_CX, KEY_CF.BUY_CY, KEY_CF.BUY_W, KEY_CF.BUY_H)
    DarkIcon.drawNine(vg, "btn", KEY_CF.BUY_CX - KEY_CF.BUY_W * 0.5, KEY_CF.BUY_CY - KEY_CF.BUY_H * 0.5, KEY_CF.BUY_W, KEY_CF.BUY_H, { accent = "gold" })
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, KEY_CF.BUY_TEXT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(KEY_CF.BUY_TEXT_R, KEY_CF.BUY_TEXT_G, KEY_CF.BUY_TEXT_B, 255))
    nvgText(vg, KEY_CF.BUY_CX, KEY_CF.BUY_CY, "购买", nil)
    BF.finish(vg, _bfBuy)

    nvgRestore(vg)
end

-- ======================== 输入 ========================

---@return boolean consumed
function M.handleTabInput(dx, dy)
    if state.keyConfirmVisible then
        if state.keyConfirmClosing then return true end
        if time.elapsedTime - state.keyConfirmAnimTime < 0.05 then return true end

        if hitTest(dx, dy, KEY_CF.BUY_CX, KEY_CF.BUY_CY, KEY_CF.BUY_W, KEY_CF.BUY_H) then
            BF.trigger("church_artifact_key_confirm")
            if GameState.getGems() < state.keyConfirmDiamondCost then
                showFloat("黑晶不足", KEY_CF.BUY_CX, KEY_CF.BUY_CY - 80)
                return true
            end
            local drawCount = state.keyConfirmCount
            closeKeyConfirm()
            sendArtifactDraw(drawCount)
            showFloat("正在开启宝箱", drawCount == 10 and COL.BTN_TEN_X or COL.BTN_ONE_X, COL.BTN_Y - 120)
            return true
        end

        if not hitTest(dx, dy, KEY_CF.CX, KEY_CF.CY, KEY_CF.W, KEY_CF.H) then
            closeKeyConfirm()
        end
        return true
    end

    if not M.isArtifactChestUnlocked() then
        return true
    end

    local drawCount, btnId = nil, nil
    if hitTest(dx, dy, COL.BTN_ONE_X, COL.BTN_Y, COL.BTN_W, COL.BTN_H) then
        drawCount, btnId = 1, "church_artifact_draw_1"
    elseif hitTest(dx, dy, COL.BTN_TEN_X, COL.BTN_Y, COL.BTN_W, COL.BTN_H) then
        drawCount, btnId = 10, "church_artifact_draw_10"
    end
    if drawCount then
        BF.trigger(btnId)
        checkKeyAndDraw(drawCount)
        return true
    end

    return true  -- 宝箱页签消费所有点击（无穿透内容）
end

-- ======================== 结果处理 ========================

--- ARTIFACT_DRAW 成功回包：同步保底计数 + 弹奖励
---@return table[] rewards
function M.onArtifactDrawSuccess(data)
    local artifactData = PlayerStore.Get("artifacts")
    if artifactData then
        if data.pityRare ~= nil then artifactData.pityRare = data.pityRare end
        if data.pityEpic ~= nil then artifactData.pityEpic = data.pityEpic end
        if data.dailyFreeDrawDayId ~= nil then
            artifactData.dailyFreeDrawDayId = data.dailyFreeDrawDayId
            state.artifactFreeDrawDayId = data.dailyFreeDrawDayId
        end
    end
    local rewards = {}
    for _, artifact in ipairs(data.artifacts or {}) do
        rewards[#rewards + 1] = {
            type = "artifact",
            id = artifact.id,
            artifactId = artifact.artifactId,
            name = ArtifactDefs.getName(artifact),
            quality = artifact.quality or 1,
            value = artifact.value or 0,
            valueRatio = artifact.valueRatio,
            threatClearValue = artifact.threatClearValue,
            threatClearRatio = artifact.threatClearRatio,
        }
    end
    if #rewards > 0 then
        RewardPopup.show("神器宝箱", rewards)
    end
    return rewards
end

-- ======================== 生命周期 ========================

function M.setContext(ctx)
    ctx_ = ctx
end

function M.init(vg)
    img.topBg             = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_JTSQ_BJ.png", 0)
    img.titleDeco         = nvgCreateImage(vg, "image/界面底板/竞技场排行/UI_JJC_BTBJ.png", 0)
    img.collectionChestBg = nvgCreateImage(vg, "image/界面底板/商店/UI_SCDC_KC1.png", 0)
    img.collectionDrawBtn = nvgCreateImage(vg, "image/界面底板/商店/UI_SCDC_AN.png", 0)
    img.goldenKey         = nvgCreateImage(vg, "image/货币道具/UI_icon_HJYS.png", 0)
    img.gem               = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ_X.png", 0)
    img.diamondBig        = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ_X.png", 0)
    img.confirmArrow      = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_JIANTOU.png", 0)
    if img.collectionChestBg < 0 then
        print("[ChurchArtifactDrawPanel] WARN: UI_SCDC_KC1.png load failed")
    end
    print("[ChurchArtifactDrawPanel] init OK")
end

function M.reset()
    state.keyConfirmVisible = false
    state.keyConfirmClosing = false
end

--- 钥匙补购弹窗是否可见（ChurchInput 用于模态优先路由）
function M.isKeyConfirmVisible()
    return state.keyConfirmVisible == true
end

return M
