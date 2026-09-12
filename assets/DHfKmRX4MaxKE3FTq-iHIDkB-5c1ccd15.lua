-- ============================================================================
-- AwakeningPanel - 觉醒面板绘制模块
-- 在角色详情面板的"觉醒"Tab 下展示觉醒节点、连线和激活按钮
-- ============================================================================

local HC         = require("config.HeroConfig")
local CC         = require("config.ClassConfig")
local GameConfig = require("config.GameConfig")
local DrawUtil   = require("core.DrawUtil")
local AKC        = require("config.AwakeningConfig")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local BF = require("systems.ButtonFeedback")

local M = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量（来自用户需求） ========================

-- 1) 全屏背景
local BG_CX, BG_CY = 540, 1200
local BG_W, BG_H   = 1080, 2400

-- 2) 品质标志
local BADGE_CX, BADGE_CY = 540, 269
local BADGE_W, BADGE_H   = 107, 49

-- 3) 称号标题背景
local TITLE_BG_CX, TITLE_BG_CY = 595, 339
local TITLE_BG_W, TITLE_BG_H   = 480, 90

-- 4) 职业图标
local CLASS_ICON_CX, CLASS_ICON_CY = 353, 339
local CLASS_ICON_SIZE              = 120

-- 5) 角色称号
local TITLE_TEXT_CX, TITLE_TEXT_CY = 540, 339
local TITLE_FONT_SIZE              = 50

-- 6) 七个觉醒图标位置
local AWAKEN_NODES = {
    { cx = 540, cy = 640  },  -- 节点 1
    { cx = 255, cy = 880  },  -- 节点 2
    { cx = 535, cy = 1031 },  -- 节点 3
    { cx = 812, cy = 864  },  -- 节点 4
    { cx = 892, cy = 1224 },  -- 节点 5
    { cx = 541, cy = 1422 },  -- 节点 6
    { cx = 183, cy = 1226 },  -- 节点 7
}

-- 7-8) 图标尺寸
local ICON_SIZE       = 251
local GLOW_SIZE       = 607  -- glow 尺寸（宽高用较大值）
local GLOW_SIZE_H     = 604
local GLOW_BREATHE_SPEED = 2.5   -- 呼吸频率
local GLOW_BREATHE_MIN   = 0.35  -- 最暗 alpha
local GLOW_BREATHE_MAX   = 1.0   -- 最亮 alpha

-- 9) 连线配置：顺序连线 1→2→3→4→5→6→7
local CONNECTIONS = {
    { 1, 2 }, { 2, 3 }, { 3, 4 },
    { 4, 5 }, { 5, 6 }, { 6, 7 },
}

local LINE_WIDTH       = 6
local LINE_GLOW_WIDTH  = 29
local LINE_GLOW_COLOR  = { 0x72, 0xe9, 0xff }
local LINE_GLOW_ALPHA  = 51   -- 20% opacity

-- 10) "已激活" 文本
local ACTIVATED_FONT  = 42
local ACTIVATED_DY    = 56   -- 在图标下方偏移（节点1: 640+56=696）

-- 11) 觉醒标题栏
local SUB_TITLE_CX, SUB_TITLE_CY = 540, 1792
local SUB_TITLE_W, SUB_TITLE_H   = 660, 60

-- 12) 效果文本框
local EFFECT_CX, EFFECT_CY = 540, 1930
local EFFECT_W, EFFECT_H   = 910, 139
local EFFECT_FONT           = 38

-- 13) 激活按钮
local BTN_CX, BTN_CY = 540, 2079
local BTN_W, BTN_H   = 410, 100

-- 14) "激活" 文字
local BTN_TEXT_CX, BTN_TEXT_CY = 540, 2079
local BTN_TEXT_FONT            = 40

-- 导出按钮常量（给 CharacterDetail handleInput 用）
M.BTN_CX = BTN_CX
M.BTN_CY = BTN_CY
M.BTN_W  = BTN_W
M.BTN_H  = BTN_H
M.AWAKEN_NODES = AWAKEN_NODES
M.ICON_SIZE    = ICON_SIZE

-- ======================== 职业图标映射 ========================

local CLASS_ICON_MAP = {
    knight   = 1,
    warrior  = 2,
    mage     = 3,
    ranger   = 4,
    assassin = 5,
    priest   = 6,
}

-- ======================== 图片句柄 ========================

local imgBg            = -1
local imgTitleBg       = -1
local imgSubTitleBg    = -1
local imgActivateBtn   = -1
local imgGlowA         = -1  -- 未激活光效（持久背景）
local imgGlowB         = -1  -- 已激活光效（持久背景）
local imgSelectArrow   = -1  -- 选中箭头 UI_JX_JT.png
-- imgShardIcon 已移至 DrawUtil.drawShardIcon 统一管理
local imgNodesA        = {}  -- 未激活图标 [1..7]
local imgNodesB        = {}  -- 已激活图标 [1..7]
local imgBadges        = {}  -- 品质标志 {R,SR,SSR}

-- 外部注入的共享图标
local imgClassIcons = {}

-- ======================== 状态 ========================

local selectedNode = 1  -- 当前选中的节点（1-7）

-- 外部注入的数据获取函数
local getOwnedData_ = nil  -- function(heroId) → ownData or nil

-- 选中箭头参数
local ARROW_W, ARROW_H = 98, 127
local ARROW_FLOAT_AMP  = 10   -- 漂浮振幅（像素）
local ARROW_FLOAT_SPEED = 3.0 -- 漂浮速度（弧度/秒）
local ARROW_OFFSET_Y   = ICON_SIZE * 0.5 + ARROW_H * 0.5 - 50  -- 图标下方紧贴

-- ======================== 初始化 ========================

--- 初始化图片资源（在 CharacterDetail.init 中调用）
function M.initImages(vg)
    imgBg          = nvgCreateImage(vg, "image/UI_JX_BJ.png", 0)
    imgTitleBg     = nvgCreateImage(vg, "image/UI_JX_1.png", 0)
    imgSubTitleBg  = nvgCreateImage(vg, "image/UI_ZBT1.png", 0)
    imgActivateBtn = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    imgGlowA       = nvgCreateImage(vg, "image/UI_JXICON_A.png", 0)
    imgGlowB       = nvgCreateImage(vg, "image/UI_JXICON_B.png", 0)
    imgSelectArrow = nvgCreateImage(vg, "image/UI_JX_JT.png", 0)
    -- imgShardIcon 已移至 DrawUtil.drawShardIcon 统一管理

    for i = 1, 7 do
        imgNodesA[i] = nvgCreateImage(vg, "image/UI_JXICON_A" .. i .. ".png", 0)
        imgNodesB[i] = nvgCreateImage(vg, "image/UI_JXICON_B" .. i .. ".png", 0)
    end

    imgBadges["R"]   = nvgCreateImage(vg, "image/UI_PZBZ_R.png", 0)
    imgBadges["SR"]  = nvgCreateImage(vg, "image/UI_PZBZ_SR.png", 0)
    imgBadges["SSR"] = nvgCreateImage(vg, "image/UI_PZBZ_SSR.png", 0)

    print("[AwakeningPanel] initImages OK")
end

--- 注入共享的职业图标
function M.setClassIcons(icons)
    imgClassIcons = icons or {}
end

--- 注入拥有数据获取函数
---@param fn function(heroId):table|nil
function M.setOwnedDataGetter(fn)
    getOwnedData_ = fn
end

-- ======================== 数据辅助 ========================

--- 获取指定角色的觉醒激活状态列表
---@param heroId number
---@return boolean[] activated  索引 1..7
local function getActivatedNodes(heroId)
    local result = { false, false, false, false, false, false, false }
    if not getOwnedData_ then return result end
    local ownData = getOwnedData_(heroId)
    if not ownData or not ownData.awakening then return result end
    for i = 1, 7 do
        if ownData.awakening[i] then
            result[i] = true
        end
    end
    return result
end

--- 重置面板状态（切换角色或打开面板时调用）
--- 自动选中第一个未激活的觉醒节点，方便玩家操作
---@param heroId? number 当前角色 ID，传入时自动定位
function M.reset(heroId)
    selectedNode = 1
    if heroId then
        local activated = getActivatedNodes(heroId)
        for i = 1, 7 do
            if not activated[i] then
                selectedNode = i
                return
            end
        end
        -- 全部已激活，停留在最后一个
        selectedNode = 7
    end
end

--- 获取觉醒节点的描述文本
---@param nodeIndex number 1..7
---@param heroCfg table HeroConfig entry
---@param heroId number
---@return string title, string effectText
local function getNodeInfo(nodeIndex, heroCfg, heroId)
    local title = "觉醒" .. nodeIndex
    local effect = AKC.getNodeEffect(heroId, nodeIndex)
    if not effect then
        effect = "效果待配置"
    end
    return title, effect
end

-- ======================== 绘制 ========================

--- 绘制觉醒面板内容
---@param vg any NanoVG context
---@param heroId number 当前角色 ID
function M.draw(vg, heroId)
    local heroCfg = HC.get(heroId)
    if not heroCfg then return end

    local activated = getActivatedNodes(heroId)

    -- 计算碎片数量和当前节点消耗
    local currentShards = 0
    local activatedCount = 0
    if getOwnedData_ then
        local ownData = getOwnedData_(heroId)
        if ownData then
            currentShards = ownData.shards or 0
        end
    end
    for i = 1, 7 do
        if activated[i] then activatedCount = activatedCount + 1 end
    end
    -- 下一个可激活的节点索引（用于显示消耗）
    local nextNodeIndex = activatedCount + 1
    local nextNodeCost = AKC.getShardCost(nextNodeIndex)  -- 0 if > 7

    -- === 1) 全屏背景 ===
    drawImageCentered(vg, imgBg, BG_CX, BG_CY, BG_W, BG_H, 1.0)

    -- === 2) 品质标志 ===
    local qualityName = HC.QUALITY_INFO[heroCfg.quality]
        and HC.QUALITY_INFO[heroCfg.quality].name or "R"
    local badgeImg = imgBadges[qualityName]
    if badgeImg and badgeImg >= 0 then
        drawImageCentered(vg, badgeImg, BADGE_CX, BADGE_CY, BADGE_W, BADGE_H, 1.0)
    end

    -- === 3) 称号标题背景 ===
    drawImageCentered(vg, imgTitleBg, TITLE_BG_CX, TITLE_BG_CY, TITLE_BG_W, TITLE_BG_H, 1.0)

    -- === 4) 职业图标 ===
    local classIdx = CLASS_ICON_MAP[heroCfg.classId]
    if classIdx and imgClassIcons[classIdx] and imgClassIcons[classIdx] >= 0 then
        drawImageCentered(vg, imgClassIcons[classIdx], CLASS_ICON_CX, CLASS_ICON_CY,
            CLASS_ICON_SIZE, CLASS_ICON_SIZE, 1.0)
    end

    -- === 5) 角色称号文本（带描边） ===
    local titleText = heroCfg.title or heroCfg.name or ""
    drawTextStroke(vg, TITLE_TEXT_CX, TITLE_TEXT_CY, titleText,
        TITLE_FONT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 5,
        { strokeColor = { 0x31, 0x24, 0x24 } })

    -- === 9) 连线（在图标下层绘制） ===
    -- 外发光参数：颜色 #72e9ff, 不透明度 50%, 柔和, 大小 29px, 范围 50%
    -- 用多层递减透明度线条模拟 Photoshop 柔和外发光
    local GLOW_LAYERS = 8
    local glowR, glowG, glowB = LINE_GLOW_COLOR[1], LINE_GLOW_COLOR[2], LINE_GLOW_COLOR[3]
    local glowBaseAlpha = LINE_GLOW_ALPHA  -- 51 (20%)

    for _, conn in ipairs(CONNECTIONS) do
        local n1 = AWAKEN_NODES[conn[1]]
        local n2 = AWAKEN_NODES[conn[2]]
        if n1 and n2 then
            -- 外发光层：从外到内逐层绘制，总距离平滑衰减
            for layer = GLOW_LAYERS, 1, -1 do
                local t = layer / GLOW_LAYERS  -- 1.0(最外) → 接近0(最内)
                local alpha = glowBaseAlpha * (1.0 - t)  -- 线性平滑衰减：最内层最亮，最外层趋近0
                local w = LINE_WIDTH + LINE_GLOW_WIDTH * 2 * t
                nvgBeginPath(vg)
                nvgMoveTo(vg, n1.cx, n1.cy)
                nvgLineTo(vg, n2.cx, n2.cy)
                nvgStrokeColor(vg, nvgRGBA(glowR, glowG, glowB, math.floor(alpha + 0.5)))
                nvgStrokeWidth(vg, w)
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)
            end

            -- 白色线条层（6px 纯白）
            nvgBeginPath(vg)
            nvgMoveTo(vg, n1.cx, n1.cy)
            nvgLineTo(vg, n2.cx, n2.cy)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgStrokeWidth(vg, LINE_WIDTH)
            nvgLineCap(vg, NVG_ROUND)
            nvgStroke(vg)
        end
    end

    -- === 6-8) 觉醒图标（光效背景 + 图标 + 选中箭头） ===
    local arrowFloatY = math.sin(time.elapsedTime * ARROW_FLOAT_SPEED) * ARROW_FLOAT_AMP

    for i = 1, 7 do
        local node = AWAKEN_NODES[i]
        local isActive = activated[i]
        local isSelected = (i == selectedNode)

        -- 光效背景（始终显示：未激活用 A，已激活用 B）+ 呼吸闪烁
        local glowImg = isActive and imgGlowB or imgGlowA
        if glowImg >= 0 then
            local phase = time.elapsedTime * GLOW_BREATHE_SPEED + i * 0.7
            local t = (math.sin(phase) + 1.0) * 0.5  -- 0~1
            local glowAlpha = GLOW_BREATHE_MIN + t * (GLOW_BREATHE_MAX - GLOW_BREATHE_MIN)
            drawImageCentered(vg, glowImg, node.cx, node.cy, GLOW_SIZE, GLOW_SIZE_H, glowAlpha)
        end

        -- 图标
        local iconImg = isActive and imgNodesB[i] or imgNodesA[i]
        if iconImg and iconImg >= 0 then
            drawImageCentered(vg, iconImg, node.cx, node.cy, ICON_SIZE, ICON_SIZE, 1.0)
        end

        -- === 10) "已激活" 文本 ===
        if isActive then
            drawTextStroke(vg, node.cx, node.cy + ACTIVATED_DY, "已激活",
                ACTIVATED_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 6)
        end

        -- 选中箭头（在图标下方上下漂浮）
        if isSelected and imgSelectArrow >= 0 then
            local arrowY = node.cy + ARROW_OFFSET_Y + arrowFloatY
            drawImageCentered(vg, imgSelectArrow, node.cx, arrowY, ARROW_W, ARROW_H, 1.0)
        end
    end

    -- === 11) 觉醒标题背景 + 文字 ===
    local nodeTitle, nodeEffect = getNodeInfo(selectedNode, heroCfg, heroId)
    drawImageCentered(vg, imgSubTitleBg, SUB_TITLE_CX, SUB_TITLE_CY, SUB_TITLE_W, SUB_TITLE_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 38)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xff, 0xef, 0x67, 255))
    nvgText(vg, SUB_TITLE_CX, SUB_TITLE_CY, nodeTitle, nil)

    -- === 12) 效果文本框 ===
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, EFFECT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    local effectTop = EFFECT_CY - EFFECT_H * 0.5
    nvgTextBox(vg, EFFECT_CX - EFFECT_W * 0.5, effectTop, EFFECT_W, nodeEffect, nil)

    -- === 12.5) 碎片数量显示（图标+数量样式） ===
    local selectedCost = AKC.getShardCost(selectedNode)
    local shardSufficient = currentShards >= selectedCost and selectedCost > 0
    local shardRowY = BTN_CY - BTN_H * 0.5 - 28
    local SHARD_ICON_SIZE = 44

    -- 计算整体宽度以居中布局
    local shardNumText = tostring(currentShards)
    local costText = selectedCost > 0 and ("/" .. selectedCost) or ""
    local fullText = shardNumText .. costText

    -- 图标 + 文本整体居中
    local textW = 120  -- 预估文本宽度
    local totalW = SHARD_ICON_SIZE + 8 + textW
    local startX = BTN_CX - totalW * 0.5

    -- 碎片图标（英雄头像+碎片角标）
    DrawUtil.drawShardIcon(vg, heroId, startX + SHARD_ICON_SIZE * 0.5, shardRowY, SHARD_ICON_SIZE, 1.0)

    -- 碎片数量文本
    local shardColor = shardSufficient and { 0x72, 0xe9, 0xff } or { 0xaa, 0xaa, 0xaa }
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(shardColor[1], shardColor[2], shardColor[3], 255))
    nvgText(vg, startX + SHARD_ICON_SIZE + 8, shardRowY, fullText, nil)

    -- === 13) 激活按钮（三态） ===
    local currentNodeActive = activated[selectedNode]
    local btnText, btnAlpha, btnTextAlpha
    if currentNodeActive then
        btnText = "已激活"
        btnAlpha = 0.5
        btnTextAlpha = 0.38
    elseif not shardSufficient then
        btnText = "碎片不足"
        btnAlpha = 0.5
        btnTextAlpha = 0.38
    else
        btnText = "激活"
        btnAlpha = 1.0
        btnTextAlpha = 0.75
    end
    local _bfAct = BF.begin(vg, "awp_activate", BTN_CX, BTN_CY, BTN_W, BTN_H)
    drawImageCentered(vg, imgActivateBtn, BTN_CX, BTN_CY, BTN_W, BTN_H, btnAlpha)

    -- === 14) 按钮文字 ===
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_TEXT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(btnTextAlpha * 255)))
    nvgText(vg, BTN_TEXT_CX, BTN_TEXT_CY, btnText, nil)
    BF.finish(vg, _bfAct)
end

--- 处理点击输入
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@param heroId number 当前角色 ID
---@return boolean consumed 是否消费了事件
function M.handleInput(dx, dy, heroId)
    -- 检测节点点击（从后往前遍历，覆盖层级）
    for i = 7, 1, -1 do
        local node = AWAKEN_NODES[i]
        if DrawUtil.hitTest(dx, dy, node.cx, node.cy, ICON_SIZE, ICON_SIZE) then
            selectedNode = i
            print("[AwakeningPanel] 选中节点 " .. i)
            return true
        end
    end

    -- 检测激活按钮点击
    if DrawUtil.hitTest(dx, dy, BTN_CX, BTN_CY, BTN_W, BTN_H) then
        BF.trigger("awp_activate")
        local activated = getActivatedNodes(heroId)
        if not activated[selectedNode] then
            -- 顺序校验：前置节点必须全部激活
            local canActivate = true
            for i = 1, selectedNode - 1 do
                if not activated[i] then
                    canActivate = false
                    print("[AwakeningPanel] 需要先激活第" .. i .. "阶觉醒")
                    break
                end
            end
            -- 碎片校验
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
                print("[AwakeningPanel] 发送激活请求 - heroId=" .. heroId .. " node=" .. selectedNode)
                local Client   = require("network.Client")
                local Protocol = require("shared.Protocol")
                Client.sendAction(Protocol.ACTION_TYPES.ACTIVATE_AWAKENING, {
                    heroId    = heroId,
                    nodeIndex = selectedNode,
                })
                -- 自动选中下一个觉醒节点，方便连续激活
                if selectedNode < 7 then
                    selectedNode = selectedNode + 1
                end
            end
        else
            print("[AwakeningPanel] 节点 " .. selectedNode .. " 已激活，无需操作")
        end
        return true
    end

    return false
end

return M
