-- ============================================================================
-- AwakeningPanel - 觉醒面板
-- 绝区零影画式：三块六边形拼图咬合角色核（粗暴 / 机制 / 进化）
-- 立绘铺满三块，嵌合后拼出完整角色
-- ============================================================================

local HC         = require("config.HeroConfig")
local DrawUtil   = require("core.DrawUtil")
local AKC        = require("config.AwakeningConfig")
local HeroAssetUtil = require("config.HeroAssetUtil")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local BF = require("systems.ButtonFeedback")

local M = {}

-- 全屏背景 / 顶栏
local BG_CX, BG_CY = 540, 1200
local BG_W, BG_H   = 1080, 2400
local BADGE_CX, BADGE_CY = 540, 269
local BADGE_W, BADGE_H   = 107, 49
local TITLE_BG_CX, TITLE_BG_CY = 595, 339
local TITLE_BG_W, TITLE_BG_H   = 480, 90
local CLASS_ICON_CX, CLASS_ICON_CY = 353, 339
local CLASS_ICON_SIZE              = 120
local TITLE_TEXT_CX, TITLE_TEXT_CY = 540, 339
local TITLE_FONT_SIZE              = 50

local NODE_COUNT = AKC.NODE_COUNT
local NODE_NAMES  = { "粗暴", "机制", "进化" }
local NODE_ROMANS = { "Ⅰ", "Ⅱ", "Ⅲ" }

-- 三块点顶六边形 120° 围核；立绘铺满三块，嵌合后拼出完整角色
local PUZZLE = {
    cx     = 540,
    cy     = 1048,
    pieceR = 210,
    dist   = 182,
    coreR  = 96,
    -- 上 / 左下 / 右下
    angles = { -90, 150, 30 },
}

local NODE_FILL = {
    { 0xe8, 0x6a, 0x4a },
    { 0x72, 0xe9, 0xff },
    { 0xe0, 0x72, 0xff },
}

-- 底栏
local SUB_TITLE_CX, SUB_TITLE_CY = 540, 1792
local SUB_TITLE_W, SUB_TITLE_H   = 660, 60
local EFFECT_CX, EFFECT_CY = 540, 1930
local EFFECT_W, EFFECT_H   = 910, 139
local EFFECT_FONT           = 36
local BTN_CX, BTN_CY = 540, 2079
local BTN_W, BTN_H   = 410, 100
local BTN_TEXT_FONT  = 40

M.BTN_CX = BTN_CX
M.BTN_CY = BTN_CY
M.BTN_W  = BTN_W
M.BTN_H  = BTN_H

local CLASS_ICON_MAP = {
    knight   = 1,
    warrior  = 2,
    mage     = 3,
    ranger   = 4,
    assassin = 5,
    priest   = 6,
}

local imgBg            = -1
local imgTitleBg       = -1
local imgSubTitleBg    = -1
local imgActivateBtn   = -1
local imgSelectArrow   = -1
local imgNodesA        = {}
local imgNodesB        = {}
local imgBadges        = {}
local imgPortraits     = {}
local imgClassIcons    = {}

local selectedNode = 1
local getOwnedData_ = nil

local ARROW_W, ARROW_H = 98, 127
local ARROW_FLOAT_AMP  = 10
local ARROW_FLOAT_SPEED = 3.0

local SQRT3 = 1.73205080757

-- ======================== 几何 ========================

local function pieceCenter(i)
    local a = math.rad(PUZZLE.angles[i] or -90)
    return PUZZLE.cx + PUZZLE.dist * math.cos(a),
           PUZZLE.cy + PUZZLE.dist * math.sin(a)
end

--- 点顶六边形：max(|dy|, |dy|/2 + |dx|√3/2) ≤ r
local function pointInHex(px, py, cx, cy, r)
    local dx = math.abs(px - cx)
    local dy = math.abs(py - cy)
    return math.max(dy, dy * 0.5 + dx * SQRT3 * 0.5) <= r
end

local function hexPath(vg, cx, cy, r)
    nvgBeginPath(vg)
    for i = 0, 5 do
        local a = math.rad(-90 + i * 60)
        local x = cx + r * math.cos(a)
        local y = cy + r * math.sin(a)
        if i == 0 then
            nvgMoveTo(vg, x, y)
        else
            nvgLineTo(vg, x, y)
        end
    end
    nvgClosePath(vg)
end

local function strokeHex(vg, cx, cy, r, cr, cg, cb, ca, width)
    hexPath(vg, cx, cy, r)
    nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, ca))
    nvgStrokeWidth(vg, width)
    nvgLineJoin(vg, NVG_ROUND)
    nvgStroke(vg)
end

local function fillHex(vg, cx, cy, r, cr, cg, cb, ca)
    hexPath(vg, cx, cy, r)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, ca))
    nvgFill(vg)
end

--- 立绘 cover 到拼图外接圆，三块共用同一张图所以能对上缝
local function portraitPattern(vg, img, alpha)
    if not img or img < 0 or alpha <= 0.01 then return nil end
    local srcW, srcH = nvgImageSize(vg, img)
    if not srcW or srcW <= 0 or not srcH or srcH <= 0 then return nil end
    local cover = (PUZZLE.dist + PUZZLE.pieceR) * 2.08
    local scale = math.max(cover / srcW, cover / srcH)
    local dw, dh = srcW * scale, srcH * scale
    local x = PUZZLE.cx - dw * 0.5
    -- 立绘偏上，让脸落在上块
    local y = PUZZLE.cy - dh * 0.58
    return nvgImagePattern(vg, x, y, dw, dh, 0, img, alpha)
end

local function fillHexPaint(vg, cx, cy, r, paint)
    hexPath(vg, cx, cy, r)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

local function getPortrait(vg, heroId)
    local cached = imgPortraits[heroId]
    if cached ~= nil then return cached end
    local img = nvgCreateImage(vg, HeroAssetUtil.getPortraitPath(heroId), 0)
    if img < 0 then
        img = nvgCreateImage(vg, HeroAssetUtil.getCardPath(heroId), 0)
    end
    imgPortraits[heroId] = img
    return img
end

-- ======================== 初始化 ========================

function M.initImages(vg)
    imgBg          = nvgCreateImage(vg, "image/界面底板/UI_JX_BJ.png", 0)
    imgTitleBg     = nvgCreateImage(vg, "image/界面底板/UI_JX_1.png", 0)
    imgSubTitleBg  = nvgCreateImage(vg, "image/界面底板/UI_ZBT1.png", 0)
    imgActivateBtn = nvgCreateImage(vg, "image/按钮/UI_AN_HUANG.png", 0)
    imgSelectArrow = nvgCreateImage(vg, "image/界面底板/UI_JX_JT.png", 0)

    for i = 1, NODE_COUNT do
        imgNodesA[i] = nvgCreateImage(vg, "image/界面底板/UI_JXICON_A" .. i .. ".png", 0)
        imgNodesB[i] = nvgCreateImage(vg, "image/界面底板/UI_JXICON_B" .. i .. ".png", 0)
    end

    imgBadges["R"]   = nvgCreateImage(vg, "image/品质框/UI_PZBZ_R.png", 0)
    imgBadges["SR"]  = nvgCreateImage(vg, "image/品质框/UI_PZBZ_SR.png", 0)
    imgBadges["SSR"] = nvgCreateImage(vg, "image/品质框/UI_PZBZ_SSR.png", 0)

    print("[AwakeningPanel] initImages OK (puzzle)")
end

function M.setClassIcons(icons)
    imgClassIcons = icons or {}
end

---@param fn function(heroId):table|nil
function M.setOwnedDataGetter(fn)
    getOwnedData_ = fn
end

---@param heroId number
---@return boolean[]
local function getActivatedNodes(heroId)
    local result = { false, false, false }
    if not getOwnedData_ then return result end
    local ownData = getOwnedData_(heroId)
    local migrated = AKC.migrateAwakening(ownData and ownData.awakening)
    for i = 1, NODE_COUNT do
        if migrated[i] then
            result[i] = true
        end
    end
    return result
end

---@param heroId? number
function M.reset(heroId)
    selectedNode = 1
    if heroId then
        local activated = getActivatedNodes(heroId)
        for i = 1, NODE_COUNT do
            if not activated[i] then
                selectedNode = i
                return
            end
        end
        selectedNode = NODE_COUNT
    end
end

---@param nodeIndex number
---@param heroCfg table
---@param heroId number
---@return string, string
local function getNodeInfo(nodeIndex, heroCfg, heroId)
    local title = (NODE_ROMANS[nodeIndex] or "") .. "  " .. (NODE_NAMES[nodeIndex] or "觉醒")
    local effect = AKC.getNodeEffect(heroId, nodeIndex) or "效果待配置"
    return title, effect
end

-- ======================== 拼图绘制 ========================

local function drawPuzzleFrame(vg)
    local outerR = PUZZLE.dist + PUZZLE.pieceR * 0.72
    for layer = 4, 1, -1 do
        local t = layer / 4
        strokeHex(vg, PUZZLE.cx, PUZZLE.cy, outerR + layer * 3,
            0xd4, 0xb4, 0x5a,
            math.floor(18 * t), 2 + layer)
    end
    strokeHex(vg, PUZZLE.cx, PUZZLE.cy, outerR, 0xe8, 0xc9, 0x6a, 90, 3)
end

---@param paint any
local function drawPiece(vg, i, isActive, isSelected, isNext, canClick, paint)
    local cx, cy = pieceCenter(i)
    local r = PUZZLE.pieceR
    local col = NODE_FILL[i] or { 180, 180, 180 }
    local t = time.elapsedTime
    local breathe = (math.sin(t * 2.4 + i * 0.9) + 1.0) * 0.5

    if isActive then
        for g = 5, 1, -1 do
            strokeHex(vg, cx, cy, r + g * 7,
                col[1], col[2], col[3],
                math.floor(16 + breathe * 14), 4)
        end
        fillHex(vg, cx, cy, r, 8, 10, 22, 230)
        if paint then
            fillHexPaint(vg, cx, cy, r, paint)
        end
        fillHex(vg, cx, cy, r, col[1], col[2], col[3], 28)
        strokeHex(vg, cx, cy, r, col[1], col[2], col[3], 230, 5)
        strokeHex(vg, cx, cy, r * 0.92, 255, 255, 255, 50, 2)
    elseif isNext then
        fillHex(vg, cx, cy, r, 10, 14, 28, 230)
        if paint then
            fillHexPaint(vg, cx, cy, r, paint)
            fillHex(vg, cx, cy, r, 8, 12, 28, 150)
        end
        local pulse = 90 + math.floor(breathe * 120)
        strokeHex(vg, cx, cy, r + 4 + breathe * 6, 0x72, 0xe9, 0xff, pulse, 4)
        strokeHex(vg, cx, cy, r, 0x72, 0xe9, 0xff, 200, 3)
    else
        fillHex(vg, cx, cy, r, 6, 8, 16, 230)
        if paint then
            fillHexPaint(vg, cx, cy, r, paint)
            fillHex(vg, cx, cy, r, 4, 6, 14, 175)
        end
        strokeHex(vg, cx, cy, r, 70, 78, 98, 140, 3)
    end

    if isSelected then
        strokeHex(vg, cx, cy, r + 8, 0xff, 0xef, 0x67, 230, 4)
    end

    -- 朝核的咬合榫
    local ang = math.rad(PUZZLE.angles[i])
    local tabX = PUZZLE.cx + (PUZZLE.coreR + 10) * math.cos(ang)
    local tabY = PUZZLE.cy + (PUZZLE.coreR + 10) * math.sin(ang)
    nvgBeginPath(vg)
    nvgCircle(vg, tabX, tabY, isActive and 14 or 11)
    if isActive then
        nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 220))
    elseif isNext then
        nvgFillColor(vg, nvgRGBA(0x72, 0xe9, 0xff, 160))
    else
        nvgFillColor(vg, nvgRGBA(40, 46, 62, 220))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, tabX, tabY, isActive and 14 or 11)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, isActive and 160 or 60))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 罗马数字章压在块外缘，不挡立绘脸
    local badgeX = cx + r * 0.62 * math.cos(ang)
    local badgeY = cy + r * 0.62 * math.sin(ang)
    local iconImg = isActive and imgNodesB[i] or imgNodesA[i]
    local iconAlpha = isActive and 1.0 or (isNext and 0.9 or 0.45)
    if iconImg and iconImg >= 0 then
        drawImageCentered(vg, iconImg, badgeX, badgeY, 72, 72, iconAlpha)
    end

    local label = NODE_NAMES[i] or ""
    local lr, lg, lb = 170, 176, 190
    if isActive then
        lr, lg, lb = 255, 255, 255
    elseif isNext then
        lr, lg, lb = 0x72, 0xe9, 0xff
    end
    drawTextStroke(vg, badgeX, badgeY + 44, label,
        26, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        lr, lg, lb, 4,
        { strokeColor = { 0x18, 0x14, 0x22 } })

    if isActive then
        drawTextStroke(vg, badgeX, badgeY + 68, "已嵌合",
            20, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            col[1], col[2], col[3], 3)
    elseif not isNext and not canClick then
        drawTextStroke(vg, badgeX, badgeY + 68, "未解锁",
            20, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            110, 114, 128, 3)
    elseif isNext then
        drawTextStroke(vg, badgeX, badgeY + 68, "可嵌合",
            20, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            0x72, 0xe9, 0xff, 3)
    end
end

local function drawCore(vg, activatedCount, paint)
    local cx, cy, r = PUZZLE.cx, PUZZLE.cy, PUZZLE.coreR
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r + 6)
    nvgFillColor(vg, nvgRGBA(6, 8, 18, 240))
    nvgFill(vg)

    if paint then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r - 2)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    local allOn = activatedCount >= NODE_COUNT
    if not allOn then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r - 2)
        nvgFillColor(vg, nvgRGBA(4, 6, 16, 80))
        nvgFill(vg)
    end

    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r)
    nvgStrokeColor(vg, nvgRGBA(0xe8, 0xc9, 0x6a, 220))
    nvgStrokeWidth(vg, 5)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r - 8)
    nvgStrokeColor(vg, nvgRGBA(0x72, 0xe9, 0xff, allOn and 180 or 70))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    drawTextStroke(vg, cx, cy + r + 26, activatedCount .. " / " .. NODE_COUNT,
        26, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        0xff, 0xef, 0x67, 4)
end

-- ======================== 绘制 ========================

function M.draw(vg, heroId)
    local heroCfg = HC.get(heroId)
    if not heroCfg then return end

    local activated = getActivatedNodes(heroId)
    local currentShards = 0
    if getOwnedData_ then
        local ownData = getOwnedData_(heroId)
        if ownData then
            currentShards = ownData.shards or 0
        end
    end
    local activatedCount = 0
    for i = 1, NODE_COUNT do
        if activated[i] then activatedCount = activatedCount + 1 end
    end
    local nextNode = activatedCount + 1

    drawImageCentered(vg, imgBg, BG_CX, BG_CY, BG_W, BG_H, 1.0)

    local qualityName = HC.QUALITY_INFO[heroCfg.quality]
        and HC.QUALITY_INFO[heroCfg.quality].name or "R"
    local badgeImg = imgBadges[qualityName]
    if badgeImg and badgeImg >= 0 then
        drawImageCentered(vg, badgeImg, BADGE_CX, BADGE_CY, BADGE_W, BADGE_H, 1.0)
    end
    drawImageCentered(vg, imgTitleBg, TITLE_BG_CX, TITLE_BG_CY, TITLE_BG_W, TITLE_BG_H, 1.0)

    local classIdx = CLASS_ICON_MAP[heroCfg.classId]
    if classIdx and imgClassIcons[classIdx] and imgClassIcons[classIdx] >= 0 then
        drawImageCentered(vg, imgClassIcons[classIdx], CLASS_ICON_CX, CLASS_ICON_CY,
            CLASS_ICON_SIZE, CLASS_ICON_SIZE, 1.0)
    end
    local titleText = heroCfg.title or heroCfg.name or ""
    drawTextStroke(vg, TITLE_TEXT_CX, TITLE_TEXT_CY, titleText,
        TITLE_FONT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 5,
        { strokeColor = { 0x31, 0x24, 0x24 } })

    local portrait = getPortrait(vg, heroId)
    local paint = portraitPattern(vg, portrait, 1.0)

    drawPuzzleFrame(vg)

    -- 拼图块先画，角色核盖住咬合处
    for i = 1, NODE_COUNT do
        if i ~= selectedNode then
            drawPiece(vg, i, activated[i] == true, false, i == nextNode, i <= nextNode, paint)
        end
    end
    drawPiece(vg, selectedNode, activated[selectedNode] == true, true,
        selectedNode == nextNode, selectedNode <= nextNode, paint)
    drawCore(vg, activatedCount, paint)

    local selCx, selCy = pieceCenter(selectedNode)
    if imgSelectArrow >= 0 then
        local arrowFloatY = math.sin(time.elapsedTime * ARROW_FLOAT_SPEED) * ARROW_FLOAT_AMP
        local arrowY = selCy + PUZZLE.pieceR * 0.92 + ARROW_H * 0.22 + arrowFloatY
        drawImageCentered(vg, imgSelectArrow, selCx, arrowY, ARROW_W, ARROW_H, 1.0)
    end

    local nodeTitle, nodeEffect = getNodeInfo(selectedNode, heroCfg, heroId)
    drawImageCentered(vg, imgSubTitleBg, SUB_TITLE_CX, SUB_TITLE_CY, SUB_TITLE_W, SUB_TITLE_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 38)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xff, 0xef, 0x67, 255))
    nvgText(vg, SUB_TITLE_CX, SUB_TITLE_CY, nodeTitle, nil)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, EFFECT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgTextBox(vg, EFFECT_CX - EFFECT_W * 0.5, EFFECT_CY - EFFECT_H * 0.5, EFFECT_W, nodeEffect, nil)

    local selectedCost = AKC.getShardCost(selectedNode)
    local shardSufficient = currentShards >= selectedCost and selectedCost > 0
    local shardRowY = BTN_CY - BTN_H * 0.5 - 28
    local SHARD_ICON_SIZE = 44
    local shardNumText = tostring(currentShards)
    local costText = selectedCost > 0 and ("/" .. selectedCost) or ""
    local fullText = shardNumText .. costText
    local textW = 120
    local totalW = SHARD_ICON_SIZE + 8 + textW
    local startX = BTN_CX - totalW * 0.5
    DrawUtil.drawShardIcon(vg, heroId, startX + SHARD_ICON_SIZE * 0.5, shardRowY, SHARD_ICON_SIZE, 1.0)
    local shardColor = shardSufficient and { 0x72, 0xe9, 0xff } or { 0xaa, 0xaa, 0xaa }
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(shardColor[1], shardColor[2], shardColor[3], 255))
    nvgText(vg, startX + SHARD_ICON_SIZE + 8, shardRowY, fullText, nil)

    local currentNodeActive = activated[selectedNode]
    local btnText, btnAlpha, btnTextAlpha
    if currentNodeActive then
        btnText = "已嵌合"
        btnAlpha = 0.5
        btnTextAlpha = 0.38
    elseif selectedNode > nextNode then
        btnText = "需先嵌合前阶"
        btnAlpha = 0.5
        btnTextAlpha = 0.38
    elseif not shardSufficient then
        btnText = "碎片不足"
        btnAlpha = 0.5
        btnTextAlpha = 0.38
    else
        btnText = "嵌合"
        btnAlpha = 1.0
        btnTextAlpha = 0.75
    end
    local _bfAct = BF.begin(vg, "awp_activate", BTN_CX, BTN_CY, BTN_W, BTN_H)
    drawImageCentered(vg, imgActivateBtn, BTN_CX, BTN_CY, BTN_W, BTN_H, btnAlpha)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_TEXT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(btnTextAlpha * 255)))
    nvgText(vg, BTN_CX, BTN_CY, btnText, nil)
    BF.finish(vg, _bfAct)
end

function M.handleInput(dx, dy, heroId)
    -- 核不抢点击；六边形重叠处优先当前选中
    local hits = {}
    for i = 1, NODE_COUNT do
        local cx, cy = pieceCenter(i)
        if pointInHex(dx, dy, cx, cy, PUZZLE.pieceR) then
            hits[#hits + 1] = i
        end
    end
    if #hits > 0 then
        local pick = hits[1]
        for _, i in ipairs(hits) do
            if i == selectedNode then
                pick = i
                break
            end
        end
        selectedNode = pick
        print("[AwakeningPanel] 选中拼图 " .. pick)
        return true
    end

    if DrawUtil.hitTest(dx, dy, BTN_CX, BTN_CY, BTN_W, BTN_H) then
        BF.trigger("awp_activate")
        local activated = getActivatedNodes(heroId)
        if not activated[selectedNode] then
            local canActivate = true
            for i = 1, selectedNode - 1 do
                if not activated[i] then
                    canActivate = false
                    print("[AwakeningPanel] 需要先嵌合第" .. i .. "阶")
                    break
                end
            end
            if canActivate then
                local ownData = getOwnedData_ and getOwnedData_(heroId)
                local shards = ownData and (ownData.shards or 0) or 0
                local cost = AKC.getShardCost(selectedNode)
                if shards < cost then
                    canActivate = false
                    print("[AwakeningPanel] 碎片不足（需要 " .. cost .. " 个，当前 " .. shards .. " 个）")
                end
            end
            if canActivate then
                print("[AwakeningPanel] 发送嵌合请求 - heroId=" .. heroId .. " node=" .. selectedNode)
                local Client   = require("network.Client")
                local Protocol = require("shared.Protocol")
                Client.sendAction(Protocol.ACTION_TYPES.ACTIVATE_AWAKENING, {
                    heroId    = heroId,
                    nodeIndex = selectedNode,
                })
                if selectedNode < NODE_COUNT then
                    selectedNode = selectedNode + 1
                end
            end
        else
            print("[AwakeningPanel] 拼图 " .. selectedNode .. " 已嵌合")
        end
        return true
    end

    return false
end

return M
