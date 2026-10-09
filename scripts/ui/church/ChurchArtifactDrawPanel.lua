-- ============================================================================
-- ChurchArtifactDrawPanel.lua
-- 教堂神器宝箱：普通/高级档位、品质概率、单抽/十连与黄金钥匙补购。
-- 每次抽取独立随机；高级宝箱需要主线通关，沿用同种黄金钥匙。
-- 坐标系 1080×2400，绘制在教堂 Tab 内容区
-- ============================================================================

---@diagnostic disable: undefined-global

local GameConfig    = require("config.GameConfig")
local DarkIcon      = require("core.DarkIcon")
local DrawUtil      = require("core.DrawUtil")
local GameState     = require("core.GameState")
local PlayerStore   = require("core.PlayerStore")
local I18n          = require("core.I18n")
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
-- 设计空间由宿主 Viewport 缩放；内容坐标与命中坐标保持一致。
local COL = {
    TITLE_CX = 540, TITLE_CY = 250, TITLE_FONT = 42,
    BTN_FONT = 32,
}

-- 上下两档宝箱卡片：整张场景背景承载标题、品质概率与抽取按钮。
local CARD = { X = 70, W = 940, H = 780 }
local CARDS = {
    { type = "normal",   Y = 320 },
    { type = "advanced", Y = 1140 },
}

--- 单张宝箱卡片的绘制与命中坐标；绘制与输入共用同一份布局。
---@param card table
---@return table
local function chestCardLayout(card)
    local left, top = CARD.X, card.Y
    return {
        type = card.type,
        left = left, top = top,
        nameX = left + 64, nameY = top + 56,
        probX = left + 600, probY = top + 280, probW = CARD.W - 656, probH = 250,
        btnOneX = left + 250, btnTenX = left + 690,
        btnY = top + 660, btnW = 320, btnH = 130,
        btnTextY = top + 636, costY = top + 686,
    }
end

-- 黄金钥匙不足时的快速购买确认框（居中模态）
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

local POPUP_OPEN_DUR   = 0.25
local POPUP_CLOSE_DUR  = 0.20
local POPUP_SCALE_FROM = 0.8
local POPUP_SCALE_TO   = 1.0

local function easeOutCubic(t) return 1 - (1 - t) * (1 - t) * (1 - t) end
local function easeInCubic(t) return t * t * t end

local img = {
    chestNormal       = -1,
    chestAdvanced     = -1,
    collectionDrawBtn = -1,
    goldenKey         = -1,
    gem               = -1,
    diamondBig        = -1,
    confirmArrow      = -1,
}

local state = {
    selectedChest = "normal",
    pendingChest = "normal",
    keyConfirmChest = "normal",
    keyConfirmVisible = false,
    keyConfirmClosing = false,
    keyConfirmAnimTime = 0,
    keyConfirmCloseTime = 0,
    keyConfirmCount = 1,
    keyConfirmNeedKeys = 0,
    keyConfirmDiamondCost = 0,
    artifactFreeDrawDayId = 0,
    drawPending = false,
    resultGeneration = 0,
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

function M.isArtifactChestUnlocked(chestType)
    return ArtifactDefs.isChestUnlocked(chestType or state.selectedChest, PlayerStore.Get("battle"))
end

local function getChestUnlockText(chestType)
    local chest = ArtifactDefs.getChest(chestType)
    if chest and chest.unlockStage then
        return I18n.format("通关普通%d-%d解锁", chest.unlockStage // 100, chest.unlockStage % 100)
    end
    return I18n.lookup(ArtifactDefs.getChestUnlockText(chestType))
end

local function getKeyCost(count, chestType)
    chestType = chestType or state.selectedChest
    local chest = ArtifactDefs.getChest(chestType)
    if count == 1 and chest and chest.dailyFree and hasArtifactFreeDraw() then return 0 end
    return ArtifactDefs.getDrawKeyCost(count, chestType) or 0
end

--- 按实际支付优先序计算按钮展示：先用现有钥匙，缺口按神器宝箱单价换黑晶。
---@return table[] costs { {kind="key"|"gems", icon=number, amount=number} }
---@return boolean affordable
local function getDrawCosts(count, chestType)
    chestType = chestType or state.selectedChest
    local required = ArtifactDefs.getDrawKeyCost(count, chestType) or 0
    if count == 1 and getKeyCost(count, chestType) == 0 then return {}, true end

    local keys = math.max(0, tonumber(GameState.getGoldenKey()) or 0)
    local keysUsed = math.min(keys, required)
    local missing = required - keysUsed
    local gems = missing * ArtifactDefs.KEY_DIAMOND_PRICE
    local costs = {}
    if keysUsed > 0 then costs[#costs + 1] = { kind = "key", icon = img.goldenKey, amount = keysUsed } end
    if gems > 0 then costs[#costs + 1] = { kind = "gems", icon = img.gem, amount = gems } end
    return costs, (tonumber(GameState.getGems()) or 0) >= gems
end

local function sendArtifactDraw(count, chestType)
    if state.drawPending then return false end
    chestType = chestType or state.selectedChest
    if not M.isArtifactChestUnlocked(chestType) then return false end
    local fn = getSendAction()
    local Protocol = getProtocol()
    if not fn or not Protocol then return false end
    local payType = (count == 1 and getKeyCost(count, chestType) == 0) and "free_daily" or "diamond"
    -- 请求锁在发送前设置，兼容单机桥接同步返回成功/失败。
    state.drawPending = true
    state.pendingChest = chestType
    local handled = fn(Protocol.ACTION_TYPES.ARTIFACT_DRAW, { count = count, payType = payType, chestType = chestType })
    if handled == false and state.drawPending then
        state.drawPending = false
        return false
    end
    return true
end

local function openKeyConfirm(count, needKeys, diamondCost, chestType)
    state.keyConfirmChest = chestType or state.selectedChest
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

local function toastAnchor(chestType)
    for _, card in ipairs(CARDS) do
        if card.type == (chestType or state.selectedChest) then
            return chestCardLayout(card)
        end
    end
    return chestCardLayout(CARDS[1])
end

local function checkKeyAndDraw(count, chestType)
    if state.drawPending then showFloat("正在开启宝箱，请稍候") return false end
    chestType = chestType or state.selectedChest
    local layout = toastAnchor(chestType)
    if not M.isArtifactChestUnlocked(chestType) then
        showFloat(getChestUnlockText(chestType), 540, layout.btnY - 150)
        return false
    end
    local keyCost = getKeyCost(count, chestType)
    local keys = GameState.getGoldenKey()
    if keyCost <= 0 or keys >= keyCost then
        if sendArtifactDraw(count, chestType) then
            if state.drawPending then
                showFloat("正在开启宝箱", count == 10 and layout.btnTenX or layout.btnOneX, layout.btnY - 150)
            end
        else
            showFloat("网络未连接", 540, layout.btnY - 150)
        end
        return true
    end

    local shortfall = keyCost - keys
    local diamondCost = shortfall * ArtifactDefs.KEY_DIAMOND_PRICE
    openKeyConfirm(count, shortfall, diamondCost, chestType)
    print(string.format("[ChurchArtifactDrawPanel] 黄金钥匙不足: 需%d 有%d 补购%d把 花费%d钻",
        keyCost, keys, shortfall, diamondCost))
    return false
end

local function getRepeatCost(count, chestType)
    local needed = getKeyCost(count, chestType)
    if needed == 0 then return { parts = {}, enough = true, freeText = "今日免费" } end
    local keys = math.min(GameState.getGoldenKey() or 0, needed)
    local gems = (needed - keys) * ArtifactDefs.KEY_DIAMOND_PRICE
    local parts = {}
    if keys > 0 then parts[#parts + 1] = { type = "golden_key", amount = keys } end
    if gems > 0 then parts[#parts + 1] = { type = "diamond", amount = gems } end
    return { parts = parts, enough = (GameState.getGems() or 0) >= gems }
end

local function continueArtifactDraw(count, generation, chestType)
    if generation ~= state.resultGeneration or not ctx_ or not ctx_.state
        or not ctx_.state.open or ctx_.state.closing then return end
    if count ~= 1 and count ~= 10 then return end
    print("[ChurchArtifactDrawPanel] 继续开箱 count=" .. count)
    checkKeyAndDraw(count, chestType)
end

-- ======================== 绘制 ========================

local function drawFittedText(vg, x, y, text, size, maxWidth, color, align)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, size)
    local width = nvgTextBounds(vg, 0, 0, text)
    if width > maxWidth then nvgFontSize(vg, math.max(20, size * maxWidth / width)) end
    nvgTextAlign(vg, align or (NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE))
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 255))
    nvgText(vg, x, y, text, nil)
end

local function drawCollectionDrawButton(vg, id, layout, countText, count)
    local bf = BF.begin(vg, id, layout.cx, layout.btnY, layout.btnW, layout.btnH)
    drawImageCentered(vg, img.collectionDrawBtn, layout.cx, layout.btnY, layout.btnW, layout.btnH, 1.0)
    drawTextStroke(vg, layout.cx, layout.btnTextY, countText, COL.BTN_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4, { strokeColor = { 0, 0, 0 } })

    local costs, affordable = getDrawCosts(count, layout.type)
    local costParts = {}
    local costFont, iconSize, iconGap, partGap = 30, 36, 4, 6
    if #costs == 0 then
        costParts[1] = { text = "免费" }
    else
        local mixed = #costs > 1
        if mixed then costFont, iconSize, iconGap = 24, 28, 4 end
        for _, cost in ipairs(costs) do
            costParts[#costParts + 1] = {
                icon = cost.icon,
                text = tostring(math.floor(cost.amount + 0.5)),
            }
        end
    end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, costFont)
    local totalW = 0
    for i, part in ipairs(costParts) do
        part.textW = nvgTextBounds(vg, 0, 0, part.text)
        totalW = totalW + part.textW
        if part.icon and part.icon >= 0 then totalW = totalW + iconSize + iconGap end
        if i > 1 then totalW = totalW + partGap end
    end
    local x = layout.cx - totalW * 0.5
    for i, part in ipairs(costParts) do
        if part.icon and part.icon >= 0 then
            drawImageCentered(vg, part.icon, x + iconSize * 0.5, layout.costY, iconSize, iconSize, 1.0)
            x = x + iconSize + iconGap
        end
        local r, g, b = 255, 255, 255
        if not affordable then r, g, b = 0x8b, 0x95, 0xa5 end
        drawTextStroke(vg, x, layout.costY, part.text, costFont,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, r, g, b, 3, { strokeColor = { 0, 0, 0 } })
        x = x + part.textW
        if i < #costParts then x = x + partGap end
    end
    BF.finish(vg, bf)
end

-- 宝箱页背景铺满设计空间，避免上下与圆角缺口透出下层内容。
function M.drawBg(vg)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(22, 20, 24, 255))
    nvgFill(vg)

    DarkIcon.drawNine(vg, "plain", 0, 200, DESIGN_W, DESIGN_H - 200 - 180)
end

--- 单张宝箱卡片：完整场景作为底板，文字与按钮由运行时叠加。
local function drawChestCard(vg, card)
    local layout = chestCardLayout(card)
    local chestType = card.type
    local chest = ArtifactDefs.getChest(chestType)
    local unlocked = M.isArtifactChestUnlocked(chestType)
    local selected = state.selectedChest == chestType

    DarkIcon.drawNine(vg, "panel", layout.left, layout.top, CARD.W, CARD.H,
        { accent = selected and "gold" or "steel" })

    -- 完整场景填满卡片内侧；外框保留，锁定档只压暗场景而不隐藏概率。
    local image = (chestType == "advanced") and img.chestAdvanced or img.chestNormal
    drawImageCentered(vg, image, layout.left + CARD.W * 0.5, layout.top + CARD.H * 0.5,
        CARD.W - 24, CARD.H - 24, unlocked and 1.0 or 0.4)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, layout.left + 12, layout.top + 12, CARD.W - 24, 96, 12)
    nvgFillColor(vg, nvgRGBA(10, 10, 12, 190))
    nvgFill(vg)

    -- 标题使用档位色，宝箱主体的材质颜色与之对应；锁定条件由点击提示提供。
    local titleColor = chestType == "advanced" and { 198, 151, 238 } or { 192, 204, 218 }
    if not unlocked then titleColor = DarkIcon.Palette.BONE_DIM end
    drawFittedText(vg, layout.nameX, layout.nameY, I18n.lookup(chest.name), 46, 520, titleColor,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 五档概率：普通至传说逐行显示，锁定档仍展示但压暗。
    DarkIcon.drawNine(vg, "plain", layout.probX, layout.probY, layout.probW, layout.probH)
    for quality = 1, 5 do
        local probability = ArtifactDefs.getQualityProbability(chestType, quality)
        local text = I18n.format("%s：%s", I18n.lookup(ArtifactDefs.getQualityName(quality)),
            string.format("%g%%", probability))
        local color = ArtifactDefs.getQualityColor(quality)
        drawFittedText(vg, layout.probX + 26, layout.probY + 30 + (quality - 1) * 44, text, 30,
            layout.probW - 52, color, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end

    -- 抽取按钮：整卡按解锁状态压暗，锁定档不发送动作。
    nvgSave(vg)
    if not unlocked then nvgGlobalAlpha(vg, 0.4) end
    local oneText = getKeyCost(1, chestType) == 0 and "免费单抽" or "抽1次"
    drawCollectionDrawButton(vg, "church_artifact_draw_1_" .. chestType,
        { cx = layout.btnOneX, btnY = layout.btnY, btnW = layout.btnW, btnH = layout.btnH,
            btnTextY = layout.btnTextY, costY = layout.costY, type = chestType }, oneText, 1)
    drawCollectionDrawButton(vg, "church_artifact_draw_10_" .. chestType,
        { cx = layout.btnTenX, btnY = layout.btnY, btnW = layout.btnW, btnH = layout.btnH,
            btnTextY = layout.btnTextY, costY = layout.costY, type = chestType }, "抽10次", 10)
    nvgRestore(vg)
end

function M.drawContent(vg)
    drawFittedText(vg, COL.TITLE_CX, COL.TITLE_CY, I18n.lookup("神器宝箱"), COL.TITLE_FONT, 900, DarkIcon.Palette.BONE)
    for _, card in ipairs(CARDS) do drawChestCard(vg, card) end
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
            local layout = toastAnchor(state.keyConfirmChest)
            closeKeyConfirm()
            if sendArtifactDraw(drawCount, state.keyConfirmChest) then
                if state.drawPending then
                    showFloat("正在开启宝箱", drawCount == 10 and layout.btnTenX or layout.btnOneX, layout.btnY - 150)
                end
            else
                showFloat("开箱请求未发送，请重试", 540, layout.btnY - 150)
            end
            return true
        end

        if not hitTest(dx, dy, KEY_CF.CX, KEY_CF.CY, KEY_CF.W, KEY_CF.H) then
            closeKeyConfirm()
        end
        return true
    end

    -- 两档宝箱同页展示：点击卡片任意非按钮区域即选中该档位（锁定档也可查看价格与概率）。
    for _, card in ipairs(CARDS) do
        if hitTest(dx, dy, CARD.X + CARD.W * 0.5, card.Y + CARD.H * 0.5, CARD.W, CARD.H) then
            for _, layout in ipairs({ chestCardLayout(card) }) do
                if hitTest(dx, dy, layout.btnOneX, layout.btnY, layout.btnW, layout.btnH) then
                    BF.trigger("church_artifact_draw_1_" .. card.type)
                    checkKeyAndDraw(1, card.type)
                    return true
                end
                if hitTest(dx, dy, layout.btnTenX, layout.btnY, layout.btnW, layout.btnH) then
                    BF.trigger("church_artifact_draw_10_" .. card.type)
                    checkKeyAndDraw(10, card.type)
                    return true
                end
            end
            if state.drawPending then showFloat("正在开启宝箱，请稍候") return true end
            if state.selectedChest ~= card.type then
                state.selectedChest = card.type
                BF.trigger("church_artifact_chest_" .. card.type)
            end
            return true
        end
    end

    return true  -- 宝箱页签消费所有点击（无穿透内容）
end

-- ======================== 结果处理 ========================

function M.onArtifactDrawResult()
    state.drawPending = false
end

--- ARTIFACT_DRAW 成功回包：同步免费日标记并展示对应档位的奖励。
---@return table[] rewards
function M.onArtifactDrawSuccess(data)
    local chestType = data.chestType or state.pendingChest
    M.onArtifactDrawResult()
    state.resultGeneration = state.resultGeneration + 1
    local generation = state.resultGeneration
    local artifactData = PlayerStore.Get("artifacts")
    if artifactData then
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
        RewardPopup.show(ArtifactDefs.getChest(chestType).name, rewards, {
            panel = "left", cascade = true,
            repeatDraw = {
                getCost = function(count) return getRepeatCost(count, chestType) end,
                onContinue = function(count) continueArtifactDraw(count, generation, chestType) end,
            },
        })
        print("[ChurchArtifactDrawPanel] 宝箱获得动画: count=" .. #rewards .. ", panel=left")
    end
    return rewards
end

-- ======================== 生命周期 ========================

function M.setContext(ctx)
    ctx_ = ctx
end

function M.init(vg)
    img.chestNormal       = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_SQBX_PT.png", 0)
    img.chestAdvanced     = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_SQBX_GJ.png", 0)
    img.collectionDrawBtn = nvgCreateImage(vg, "image/界面底板/商店/UI_SCDC_AN.png", 0)
    img.goldenKey         = nvgCreateImage(vg, "image/货币道具/UI_icon_HJYS.png", 0)
    img.gem               = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ_X.png", 0)
    -- 大图与小图复用同一黑晶句柄。
    img.diamondBig        = img.gem
    img.confirmArrow      = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_JIANTOU.png", 0)
    if img.chestNormal < 0 or img.chestAdvanced < 0 then
        print("[ChurchArtifactDrawPanel] WARN: chest image load failed")
    end
    print("[ChurchArtifactDrawPanel] init OK")
end

function M.reset()
    state.selectedChest = "normal"
    state.keyConfirmVisible = false
    state.keyConfirmClosing = false
    state.resultGeneration = state.resultGeneration + 1
end

--- 钥匙补购弹窗是否可见（ChurchInput 用于模态优先路由）
function M.isKeyConfirmVisible()
    return state.keyConfirmVisible == true
end

return M
