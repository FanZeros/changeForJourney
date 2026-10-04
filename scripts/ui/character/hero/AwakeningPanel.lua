-- ============================================================================
-- AwakeningPanel - 觉醒面板（绝区零影画式）
-- 角色 CG 切成三竖条错位排布：未解锁灰度渲染，解锁显示原色
-- Ⅰ 初醒 / Ⅱ 共鸣 / Ⅲ 蜕变；点切片查看，底部嵌合
-- ============================================================================

local HC         = require("config.HeroConfig")
local DrawUtil   = require("core.DrawUtil")
local AKC        = require("config.AwakeningConfig")
local HeroAssetUtil = require("config.HeroAssetUtil")
local I18n       = require("core.I18n")
local KeywordText = require("ui.widget.KeywordText")
local HeroFrame = require("ui.widget.HeroFrame")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local BF = require("systems.ButtonFeedback")

local M = {}

-- 觉醒效果关键词富文本（白字与面板一致）；弹窗由 CharacterDetailDraw 帧末统一绘制
M.kwText = KeywordText.new({ textColor = { 255, 255, 255 } })

-- 全屏背景 / 顶栏
local BG_CX, BG_CY = 540, 1200
local BG_W, BG_H   = 1080, 2400
-- 称号行固定在页顶（阶段代号之上）
local TITLE_BG_CX, TITLE_BG_CY = 595, 200
local TITLE_BG_W, TITLE_BG_H   = 480, 90
local CLASS_ICON_CX, CLASS_ICON_CY = 353, 200
local CLASS_ICON_SIZE              = 120
local TITLE_TEXT_CX, TITLE_TEXT_CY = 540, 200
local TITLE_FONT_SIZE              = 50

local NODE_COUNT = AKC.NODE_COUNT
local NODE_NAMES  = { "初醒", "共鸣", "蜕变" }
local NODE_ROMANS = { "Ⅰ", "Ⅱ", "Ⅲ" }

-- 影画切片：上条向右下斜、下条向左下斜（Z 形分割）
-- 切片只限定显示区域；CG 等比铺满高度，横向共用居中裁切。
local SLICES = {
    W      = 336,    -- 单条垂直跨度（三栏顶底对齐的列宽）
    H      = 1512,   -- 单条高（大狗 CG 完整高度）
    GAP    = 0,
    SX     = 36,     -- 左缘（(1080-3*336)/2）
    SY     = 300,    -- 基准顶：阶段代号(y~222)紧贴其下
    SLANT  = 48,     -- 底部中片保留 336-2*48=240 宽，斜切不挤成尖条
    STAG   = { 0, 0, 0 },
    V_BIAS = 0.0,
}

local NODE_FILL = {
    { 0xe8, 0x6a, 0x4a },
    { 0x72, 0xe9, 0xff },
    { 0xe0, 0x72, 0xff },
}

-- 底栏（切片底 = SY+H = 1812，文字区紧跟其下）
local SUB_TITLE_CX, SUB_TITLE_CY = 540, 1860
-- 效果说明下移约 2/3 行（36 字号默认行高 49，取整为 33），避免首行压住阶段标题。
local EFFECT_CX, EFFECT_CY = 540, 1963
local EFFECT_W, EFFECT_H   = 910, 139
local EFFECT_FONT           = 36
-- 底栏操作：碎片标识在左、嵌合按钮在右（放大）
local SHARD_ICON_SIZE = 114
local SHARD_ICON_CX   = 196
local SHARD_ROW_CY    = 2160
local BTN_CX, BTN_CY = 720, 2160
local BTN_W, BTN_H   = 520, 100
local BTN_TEXT_FONT  = 46

M.BTN_CX = BTN_CX
M.BTN_CY = BTN_CY
M.BTN_W  = BTN_W
M.BTN_H  = BTN_H

local CLASS_ICON_MAP = {
    knight   = 1, seal  = 1,
    warrior  = 2, spoil = 2,
    mage     = 3, rift  = 3,
    ranger   = 4, echo  = 4,
    assassin = 5, mask  = 5,
    priest   = 6, debt  = 6,
}

local imgBg            = -1
local imgTitleBg       = -1
local imgActivateBtn   = -1
local imgSelectArrow   = -1
local imgClassIcons    = {}

---@type table<number, integer>
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

--- 第 i 条在进度 t（0=顶，1=底）处的左右缘
--- 相邻切片共用分割线，避免选中后覆盖邻片而改变显示范围。
local function sliceEdges(i, t)
    local x = sliceX(i)
    local s = SLICES.SLANT * t
    local left, right
    if i == 1 then
        left, right = x, x + SLICES.W + s
    elseif i == NODE_COUNT then
        left, right = x - s, x + SLICES.W
    else
        left, right = x + s, x + SLICES.W - s
    end
    return left, right
end

--- 斜切条路径
local function slicePath(vg, i, expand)
    local e = expand or 0
    local y0 = sliceY(i) - e
    local y1 = sliceY(i) + SLICES.H + e
    local l0, r0 = sliceEdges(i, 0)
    local l1, r1 = sliceEdges(i, 1)
    nvgBeginPath(vg)
    nvgMoveTo(vg, l0 - e, y0)
    nvgLineTo(vg, r0 + e, y0)
    nvgLineTo(vg, r1 + e, y1)
    nvgLineTo(vg, l1 - e, y1)
    nvgClosePath(vg)
end

---@param px number
---@param py number
---@return boolean
local function pointInSlice(px, py, i)
    local y0 = sliceY(i)
    local y1 = y0 + SLICES.H
    if py < y0 or py > y1 then return false end
    local t = (py - y0) / SLICES.H
    local left, right = sliceEdges(i, t)
    -- 分割线归右侧切片；外缘闭合，不扩张热区造成重复命中。
    return px >= left and (px < right or (i == NODE_COUNT and px <= right))
end

-- ======================== CG 资源 ========================

--- 解析角色 CG：正式 CG -> 立绘 -> 卡牌。未解锁态绘制时染色，不再加载灰度图。
---@return integer colorHandle 彩色句柄，缺失为 -1
local function resolveCG(vg, heroId)
    local cached = cgCache[heroId]
    if cached then return cached end
    local color = nvgCreateImage(vg, string.format("image/角色CG/CG_H%d.png", heroId), 0) or -1
    if color < 0 then
        color = nvgCreateImage(vg, HeroAssetUtil.getPortraitPath(heroId), 0) or -1
    end
    if color < 0 then
        color = nvgCreateImage(vg, HeroAssetUtil.getCardPath(heroId), 0) or -1
    end
    cgCache[heroId] = color
    return color
end

--- CG 等比铺满 1512 高度，返回 (dw, dh, v0, sw)，保留完整源图高度
---@return number|nil dw
---@return number|nil dh
---@return number|nil v0
---@return number|nil sw
local function cgLayout(vg, img)
    local sw, sh = nvgImageSize(vg, img)
    if not sw or sw <= 0 or not sh or sh <= 0 then return nil end
    local scale = SLICES.H / sh
    local dw, dh = sw * scale, sh * scale
    local v0 = (dh - SLICES.H) * SLICES.V_BIAS
    if v0 < 0 then v0 = 0 end
    return dw, dh, v0, sw
end

--- ImagePattern 展开整张 CG，不是源裁剪；所有切片及灰/彩态共用同一变换。
local function slicePaint(vg, img, i, dw, dh, v0, sw, alpha, gray)
    if not img or img < 0 or alpha <= 0.01 or not sw then return nil end
    local totalSliceWidth = NODE_COUNT * SLICES.W + (NODE_COUNT - 1) * SLICES.GAP
    local ox = SLICES.SX + (totalSliceWidth - dw) * 0.5
    local oy = SLICES.SY - v0
    if gray then
        local tone = math.floor(168 * alpha)
        local tint = nvgRGBA(tone, tone, tone, 255)
        ---@cast tint NVGcolor
        return nvgImagePatternTinted(vg, ox, oy, dw, dh, 0, img, tint)
    end
    return nvgImagePattern(vg, ox, oy, dw, dh, 0, img, alpha)
end

-- ======================== 初始化 ========================

function M.initImages(vg)
    imgBg          = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JX_BJ.png", 0)
    imgTitleBg     = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JX_1.png", 0)
    imgActivateBtn = nvgCreateImage(vg, "image/按钮/UI_AN_HUANG.png", 0)
    imgSelectArrow = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JX_JT.png", 0)

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
    M.kwText:clear()   -- 切角色时清关键词弹窗/热区
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
    local title = (NODE_ROMANS[nodeIndex] or "") .. "  " .. I18n.lookup(NODE_NAMES[nodeIndex] or "觉醒")
    local effect = AKC.getNodeEffect(heroId, nodeIndex) or "效果待配置"
    return title, effect
end

-- ======================== 影画切片绘制 ========================

--- 单条切片
---@param i number 1~3
---@param state string "active" 已嵌合 | "next" 可嵌合 | "locked" 未解锁
---@param isSelected boolean
local function drawSlice(vg, i, state, isSelected, cgImg, dw, dh, v0, sw)
    local col = NODE_FILL[i] or { 180, 180, 180 }
    local t = time.elapsedTime
    local breathe = (math.sin(t * 2.4 + i * 0.9) + 1.0) * 0.5

    -- 1) 深底
    slicePath(vg, i)
    nvgFillColor(vg, nvgRGBA(8, 10, 18, 235))
    nvgFill(vg)

    -- 2) CG 片：解锁=彩色，未解锁=绘制时染灰（两态共用斜切取样几何）
    local paint = slicePaint(vg, cgImg, i, dw, dh, v0, sw, 1.0, state ~= "active")
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
        if cgImg and cgImg >= 0 then
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
        slicePath(vg, i)
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

    -- 4) 顶部阶段铭牌：罗马数字 + 名称（上移到切片上方，不压 CG）
    local l0, r0 = sliceEdges(i, 0)
    local cx = (l0 + r0) * 0.5
    local topY = sliceY(i) - 78
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

    -- 5) 底部状态（居中于斜切条底部）
    local bl, br = sliceEdges(i, 1)
    local cx = (bl + br) * 0.5
    local by = sliceY(i) + SLICES.H - 30
    if state == "active" then
        drawTextStroke(vg, cx, by, "已嵌合",
            22, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            244, 237, 224, 3)
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
    local cgImg = resolveCG(vg, heroId)
    local dw, dh, v0, sw
    if cgImg and cgImg >= 0 then
        dw, dh, v0, sw = cgLayout(vg, cgImg)
    end

    -- 固定绘制顺序；选中只改变描边，不改变任何切片的图片覆盖范围。
    for i = 1, NODE_COUNT do
        local state = activated[i] and "active" or (i == nextNode and "next" or "locked")
        drawSlice(vg, i, state, i == selectedNode, cgImg, dw, dh, v0, sw)
    end

    -- 选中切片上浮箭头（居中于斜切条顶部）
    local selL, selR = sliceEdges(selectedNode, 0)
    local selX = (selL + selR) * 0.5
    local selTop = sliceY(selectedNode)
    if imgSelectArrow >= 0 then
        local arrowFloatY = math.sin(time.elapsedTime * ARROW_FLOAT_SPEED) * ARROW_FLOAT_AMP
        -- 阶段代号已占切片上方，箭头改放到切片内部顶部
        drawImageCentered(vg, imgSelectArrow, selX, selTop + ARROW_H * 0.5 + 8 + arrowFloatY,
            ARROW_W, ARROW_H, 1.0)
    end

    -- 底栏标题（去掉两侧花纹底板，只留文字）
    local nodeTitle, nodeEffect = getNodeInfo(selectedNode, heroCfg, heroId)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xff, 0xef, 0x67, 255))
    nvgText(vg, SUB_TITLE_CX, SUB_TITLE_CY, nodeTitle, nil)

    -- 关键词富文本：觉醒效果说明中的机制词可点击弹出解释（弹窗由 CharacterDetailDraw 帧末绘制）
    M.kwText:draw(vg, nodeEffect,
        EFFECT_CX - EFFECT_W * 0.5, EFFECT_CY - EFFECT_H * 0.5, EFFECT_W,
        EFFECT_FONT, nil, EFFECT_CX)

    local selectedCost = AKC.getShardCost(selectedNode)
    local shardSufficient = currentShards >= selectedCost and selectedCost > 0
    local shardNumText = tostring(currentShards)
    local costText = selectedCost > 0 and ("/" .. selectedCost) or ""
    local fullText = shardNumText .. costText
    DrawUtil.drawShardIcon(vg, heroId, SHARD_ICON_CX, SHARD_ROW_CY, SHARD_ICON_SIZE, 1.0)
    -- 碎片数量：够=亮青，不够=灰蓝色
    local shardColor = shardSufficient and { 0x72, 0xe9, 0xff } or { 0x8b, 0x95, 0xa5 }
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 66)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(shardColor[1], shardColor[2], shardColor[3], 255))
    nvgText(vg, SHARD_ICON_CX + SHARD_ICON_SIZE * 0.5 + 18, SHARD_ROW_CY, fullText, nil)

    local currentNodeActive = activated[selectedNode]
    local btnText, btnAlpha, btnDisabled
    if currentNodeActive then
        btnText = "已嵌合"
        btnAlpha = 0.5
        btnDisabled = true
    elseif selectedNode > nextNode then
        btnText = "需先嵌合前阶"
        btnAlpha = 0.5
        btnDisabled = true
    elseif not shardSufficient then
        btnText = "碎片不足"
        btnAlpha = 0.5
        btnDisabled = true
    else
        btnText = "嵌合"
        btnAlpha = 1.0
        btnDisabled = false
    end
    local _bfAct = BF.begin(vg, "awp_activate", BTN_CX, BTN_CY, BTN_W, BTN_H)
    drawImageCentered(vg, imgActivateBtn, BTN_CX, BTN_CY, BTN_W, BTN_H, btnAlpha)
    -- 按钮文字：可嵌合/已嵌合=亮骨白；条件未满足才用灰蓝色。
    local tr, tg, tb = 244, 237, 224
    if btnDisabled and not currentNodeActive then
        tr, tg, tb = 0x8b, 0x95, 0xa5
    end
    drawTextStroke(vg, BTN_CX, BTN_CY, btnText, BTN_TEXT_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, tr, tg, tb, 4,
        { strokeColor = { 0x2a, 0x1c, 0x14 } })
    BF.finish(vg, _bfAct)
end

function M.handleInput(dx, dy, heroId)
    -- 效果描述关键词点击（弹窗的关闭由 CharacterDetail.handleInput 统一处理）
    if M.kwText:handleInput(dx, dy) then
        return true
    end

    -- 点击与固定切片范围一致，不随当前选中阶段变化。
    for i = 1, NODE_COUNT do
        if pointInSlice(dx, dy, i) then
            if selectedNode ~= i then
                selectedNode = i
                print("[AwakeningPanel] 选中切片 " .. i)
            end
            return true
        end
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
                local Client   = require("runtime.GameAction")
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
