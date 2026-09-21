-- ============================================================================
-- AwakeningPanel - 觉醒面板（绝区零影画式）
-- 角色 CG 切成三竖条错位排布：未解锁灰度渲染，解锁显示原色
-- Ⅰ 粗暴 / Ⅱ 机制 / Ⅲ 进化；点切片查看，底部嵌合
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
local TITLE_BG_CX, TITLE_BG_CY = 595, 319
local TITLE_BG_W, TITLE_BG_H   = 480, 90
local CLASS_ICON_CX, CLASS_ICON_CY = 353, 319
local CLASS_ICON_SIZE              = 120
local TITLE_TEXT_CX, TITLE_TEXT_CY = 540, 319
local TITLE_FONT_SIZE              = 50

local NODE_COUNT = AKC.NODE_COUNT
local NODE_NAMES  = { "粗暴", "机制", "进化" }
local NODE_ROMANS = { "Ⅰ", "Ⅱ", "Ⅲ" }

-- 影画切片：CG 三竖条直角对齐，无缝拼合
-- 面板为 1080x2400 设计页；切片区拉高让竖版 CG 尽量少裁
local SLICES = {
    W     = 336,     -- 单条宽
    H     = 1150,    -- 单条高
    GAP   = 0,       -- 条间距（三栏无缝拼合）
    SX    = 36,      -- 左缘（(1080-3*336-0)/2）
    SY    = 396,     -- 基准顶（标题栏 y~384 之下）
    SLANT = 0,       -- 直角矩形，三栏顶底齐平
    STAG  = { 0, 0, 0 }, -- 三栏纵向对齐，不再错位
    V_BIAS = 0.18,   -- CG 纵向取窗偏上（保脸）
}

local NODE_FILL = {
    { 0xe8, 0x6a, 0x4a },
    { 0x72, 0xe9, 0xff },
    { 0xe0, 0x72, 0xff },
}

-- 底栏
local SUB_TITLE_CX, SUB_TITLE_CY = 540, 1690
local EFFECT_CX, EFFECT_CY = 540, 1830
local EFFECT_W, EFFECT_H   = 910, 139
local EFFECT_FONT           = 36
-- 底栏操作：碎片标识在左、嵌合按钮在右（放大）
local SHARD_ICON_SIZE = 114
local SHARD_ICON_CX   = 196
local SHARD_ROW_CY    = 2110
local BTN_CX, BTN_CY = 720, 2110
local BTN_W, BTN_H   = 520, 128
local BTN_TEXT_FONT  = 46

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
local imgActivateBtn   = -1
local imgSelectArrow   = -1
local imgBadges        = {}
local imgClassIcons    = {}

---@type table<number, table>
local cgCache = {}

local selectedNode = 1
local getOwnedData_ = nil

local ARROW_W, ARROW_H = 98, 127
local ARROW_FLOAT_AMP  = 10
local ARROW_FLOAT_SPEED = 3.0

-- ======================== 几何 ========================

--- 第 i 条底边左缘 X
local function sliceX(i)
    return SLICES.SX + (i - 1) * (SLICES.W + SLICES.GAP)
end

--- 第 i 条顶边 Y（含错位）
local function sliceY(i)
    return SLICES.SY + (SLICES.STAG[i] or 0)
end

--- 平行四边形路径：顶边相对底边右移 SLANT
local function slicePath(vg, i, expand)
    local e = expand or 0
    local x0 = sliceX(i) - e
    local x1 = sliceX(i) + SLICES.W + e
    local y0 = sliceY(i) - e
    local y1 = sliceY(i) + SLICES.H + e
    local s = SLICES.SLANT
    nvgBeginPath(vg)
    nvgMoveTo(vg, x0 + s, y0)
    nvgLineTo(vg, x1 + s, y0)
    nvgLineTo(vg, x1, y1)
    nvgLineTo(vg, x0, y1)
    nvgClosePath(vg)
end

---@param px number
---@param py number
---@return boolean
local function pointInSlice(px, py, i)
    local x0 = sliceX(i)
    local x1 = x0 + SLICES.W
    local y0 = sliceY(i)
    local y1 = y0 + SLICES.H
    if py < y0 or py > y1 then return false end
    local t = (py - y0) / SLICES.H
    local s = SLICES.SLANT * (1 - t)
    local pad = 8
    return px >= x0 + s - pad and px <= x1 + s + pad
end

-- ======================== CG 资源 ========================

--- 解析角色 CG：正式 CG -> 立绘 -> 卡牌；同时取对应灰度版
---@return integer colorHandle 彩色句柄，缺失为 -1
---@return integer grayHandle 灰度句柄，缺失为 -1
local function resolveCG(vg, heroId)
    local cached = cgCache[heroId]
    if cached then return cached.color, cached.gray end
    local color = nvgCreateImage(vg, string.format("image/角色CG/CG_H%d.png", heroId), 0) or -1
    local gray = -1
    if color >= 0 then
        gray = nvgCreateImage(vg, string.format("image/角色CG/CG_H%d_gray.png", heroId), 0) or -1
    else
        color = nvgCreateImage(vg, HeroAssetUtil.getPortraitPath(heroId), 0) or -1
        if color >= 0 then
            gray = nvgCreateImage(vg, string.format("image/角色CG/FALLBACK_H%d_gray.png", heroId), 0) or -1
        else
            color = nvgCreateImage(vg, HeroAssetUtil.getCardPath(heroId), 0) or -1
        end
    end
    cgCache[heroId] = { color = color, gray = gray }
    return color, gray
end

--- CG cover 到切片总幅，返回 (dw, dh, v0)
---@return number|nil dw
---@return number|nil dh
---@return number|nil v0
local function cgLayout(vg, img)
    local sw, sh = nvgImageSize(vg, img)
    if not sw or sw <= 0 or not sh or sh <= 0 then return nil end
    local totalW = SLICES.W * NODE_COUNT + SLICES.GAP * (NODE_COUNT - 1)
    local scale = math.max(totalW / sw, SLICES.H / sh)
    local dw, dh = sw * scale, sh * scale
    local v0 = (dh - SLICES.H) * SLICES.V_BIAS
    if v0 < 0 then v0 = (dh - SLICES.H) * 0.5 end
    return dw, dh, v0
end

--- 第 i 条的取样 paint：显示 CG 第 i 列，竖向公共窗 v0
local function slicePaint(vg, img, i, dw, dh, v0, alpha)
    if not img or img < 0 or alpha <= 0.01 then return nil end
    local ox = sliceX(i) - dw * (i - 1) / NODE_COUNT
    local oy = sliceY(i) - v0
    return nvgImagePattern(vg, ox, oy, dw, dh, 0, img, alpha)
end

-- ======================== 初始化 ========================

function M.initImages(vg)
    imgBg          = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JX_BJ.png", 0)
    imgTitleBg     = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JX_1.png", 0)
    imgActivateBtn = nvgCreateImage(vg, "image/按钮/UI_AN_HUANG.png", 0)
    imgSelectArrow = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JX_JT.png", 0)

    imgBadges["R"]   = nvgCreateImage(vg, "image/品质框/UI_PZBZ_R.png", 0)
    imgBadges["SR"]  = nvgCreateImage(vg, "image/品质框/UI_PZBZ_SR.png", 0)
    imgBadges["SSR"] = nvgCreateImage(vg, "image/品质框/UI_PZBZ_SSR.png", 0)

    cgCache = {}
    print("[AwakeningPanel] initImages OK (mindscape slices)")
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

-- ======================== 影画切片绘制 ========================

--- 单条切片
---@param i number 1~3
---@param state string "active" 已嵌合 | "next" 可嵌合 | "locked" 未解锁
---@param isSelected boolean
local function drawSlice(vg, i, state, isSelected, cgImg, grayImg, dw, dh, v0)
    local col = NODE_FILL[i] or { 180, 180, 180 }
    local t = time.elapsedTime
    local breathe = (math.sin(t * 2.4 + i * 0.9) + 1.0) * 0.5

    -- 1) 深底
    slicePath(vg, i)
    nvgFillColor(vg, nvgRGBA(8, 10, 18, 235))
    nvgFill(vg)

    -- 2) CG 片：解锁=彩色，未解锁=灰度
    local img = (state == "active") and cgImg or (grayImg >= 0 and grayImg or cgImg)
    local paint = slicePaint(vg, img, i, dw, dh, v0, 1.0)
    if paint then
        slicePath(vg, i)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    if state == "active" then
        slicePath(vg, i)
        nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 22))
        nvgFill(vg)
    else
        -- 未解锁：压暗 + 轻灰罩，保证灰片可读
        slicePath(vg, i)
        if grayImg >= 0 then
            nvgFillColor(vg, nvgRGBA(8, 10, 20, 110))
        else
            nvgFillColor(vg, nvgRGBA(14, 14, 18, 200))
        end
        nvgFill(vg)
    end

    -- 3) 边框
    if isSelected then
        if state == "active" then
            for g = 3, 1, -1 do
                slicePath(vg, i, g * 5)
                nvgStrokeColor(vg, nvgRGBA(0xe8, 0xc9, 0x6a, math.floor(40 + breathe * 40)))
                nvgStrokeWidth(vg, 3)
                nvgStroke(vg)
            end
        end
        slicePath(vg, i, 4)
        nvgStrokeColor(vg, nvgRGBA(0xff, 0xef, 0x67, 235))
        nvgStrokeWidth(vg, 4)
        nvgStroke(vg)
    elseif state == "active" then
        slicePath(vg, i)
        nvgStrokeColor(vg, nvgRGBA(0xe8, 0xc9, 0x6a, 210))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    elseif state == "next" then
        slicePath(vg, i, 3 + breathe * 5)
        nvgStrokeColor(vg, nvgRGBA(0x72, 0xe9, 0xff, math.floor(70 + breathe * 110)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        slicePath(vg, i)
        nvgStrokeColor(vg, nvgRGBA(0x72, 0xe9, 0xff, 190))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    else
        slicePath(vg, i)
        nvgStrokeColor(vg, nvgRGBA(70, 78, 98, 140))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end

    -- 4) 顶部阶段铭牌：罗马数字 + 名称
    local cx = sliceX(i) + SLICES.W * 0.5 + SLICES.SLANT * 0.5
    local topY = sliceY(i)
    local nr, ng, nb = 150, 156, 172
    if state == "active" then
        nr, ng, nb = 255, 255, 255
    elseif state == "next" then
        nr, ng, nb = 0x72, 0xe9, 0xff
    end
    drawTextStroke(vg, cx, topY + 56, NODE_ROMANS[i] or "",
        56, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        nr, ng, nb, 5,
        { strokeColor = { 0x10, 0x0c, 0x18 } })
    drawTextStroke(vg, cx, topY + 96, NODE_NAMES[i] or "",
        26, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        nr, ng, nb, 4,
        { strokeColor = { 0x10, 0x0c, 0x18 } })

    -- 5) 底部状态
    local by = sliceY(i) + SLICES.H - 30
    if state == "active" then
        drawTextStroke(vg, cx, by, "已嵌合",
            22, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            col[1], col[2], col[3], 3)
    elseif state == "next" then
        drawTextStroke(vg, cx, by, "可嵌合",
            22, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            0x72, 0xe9, 0xff, 3)
    else
        drawTextStroke(vg, cx, by, "未解锁",
            22, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            110, 116, 132, 3)
    end
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

    -- 影画切片
    local cgImg, grayImg = resolveCG(vg, heroId)
    local dw, dh, v0
    if cgImg and cgImg >= 0 then
        dw, dh, v0 = cgLayout(vg, cgImg)
    end

    for i = 1, NODE_COUNT do
        local state = activated[i] and "active" or (i == nextNode and "next" or "locked")
        if i ~= selectedNode then
            drawSlice(vg, i, state, false, cgImg, grayImg, dw, dh, v0)
        end
    end
    local selState = activated[selectedNode] and "active"
        or (selectedNode == nextNode and "next" or "locked")
    drawSlice(vg, selectedNode, selState, true, cgImg, grayImg, dw, dh, v0)

    -- 选中切片上浮箭头
    local selX = sliceX(selectedNode) + SLICES.W * 0.5 + SLICES.SLANT * 0.5
    local selTop = sliceY(selectedNode)
    if imgSelectArrow >= 0 then
        local arrowFloatY = math.sin(time.elapsedTime * ARROW_FLOAT_SPEED) * ARROW_FLOAT_AMP
        drawImageCentered(vg, imgSelectArrow, selX, selTop - ARROW_H * 0.3 - 6 + arrowFloatY,
            ARROW_W, ARROW_H, 1.0)
    end

    -- 底栏标题（去掉两侧花纹底板，只留文字）
    local nodeTitle, nodeEffect = getNodeInfo(selectedNode, heroCfg, heroId)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
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
    local shardNumText = tostring(currentShards)
    local costText = selectedCost > 0 and ("/" .. selectedCost) or ""
    local fullText = shardNumText .. costText
    DrawUtil.drawShardIcon(vg, heroId, SHARD_ICON_CX, SHARD_ROW_CY, SHARD_ICON_SIZE, 1.0)
    local shardColor = shardSufficient and { 0x72, 0xe9, 0xff } or { 0xaa, 0xaa, 0xaa }
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 66)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(shardColor[1], shardColor[2], shardColor[3], 255))
    nvgText(vg, SHARD_ICON_CX + SHARD_ICON_SIZE * 0.5 + 18, SHARD_ROW_CY, fullText, nil)

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
    local tr = math.floor(244 * btnTextAlpha)
    local tg = math.floor(237 * btnTextAlpha)
    local tb = math.floor(224 * btnTextAlpha)
    drawTextStroke(vg, BTN_CX, BTN_CY, btnText, BTN_TEXT_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, tr, tg, tb, 4,
        { strokeColor = { 0x2a, 0x1c, 0x14 } })
    BF.finish(vg, _bfAct)
end

function M.handleInput(dx, dy, heroId)
    -- 切片命中（斜切平行四边形），重叠处优先当前选中
    local hits = {}
    for i = 1, NODE_COUNT do
        if pointInSlice(dx, dy, i) then
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
        if selectedNode ~= pick then
            selectedNode = pick
            print("[AwakeningPanel] 选中切片 " .. pick)
        end
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
            print("[AwakeningPanel] 切片 " .. selectedNode .. " 已嵌合")
        end
        return true
    end

    return false
end

return M
