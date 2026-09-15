-- ============================================================================
-- LootBox - 战利品箱子模块
-- 职责: 战斗界面战利品收集箱（图标绘制、飞入动画、红点提示、点击弹窗）
-- 数据层: 种子计数模式（不存完整装备，仅显示总件数）
-- ============================================================================

local RewardPopup     = require("ui.RewardPopup")
local LootBoxPage     = require("ui.LootBoxPage")

local LootBox = {}

-- ======================== 布局常量 ========================

local BOX_CX, BOX_CY = 109, 2115
local BOX_SIZE        = 160

local TEXT_X, TEXT_Y   = 110, 2174
local TEXT_FONT        = 32
local TEXT_STROKE      = 4

local DOT_SIZE = 74
-- 红点位于箱子右上角
local DOT_CX = BOX_CX + BOX_SIZE * 0.5 - DOT_SIZE * 0.3
local DOT_CY = BOX_CY - BOX_SIZE * 0.5 + DOT_SIZE * 0.3

-- 点击判定半径
local TAP_RADIUS = BOX_SIZE * 0.5 + 20

-- ======================== 状态 ========================

local seedCount = 0     -- 当前种子总件数（来自 lootbox 数据的 count 之和）
local seedSummary = {}  -- 种子摘要 { {quality, level, count}, ... }（用于弹窗展示）

local imgBox    = -1    -- ICON_BX.png
local imgRedDot = -1    -- ICON_HD.png

local cachedVg  = nil

-- 抖动动画
local shakeTimer    = 0     -- 剩余抖动时间
local SHAKE_DURATION = 0.4  -- 总抖动时长（秒）
local SHAKE_AMP      = 12   -- 最大水平偏移（像素）
local SHAKE_FREQ     = 28   -- 抖动频率（越大越快）

-- 领取回调（Standalone 和 Client 各自设置）
local onClaimCallback = nil
local onClaimAllCallback = nil
local onClaimOneCallback = nil  -- function(seedIndex) 点击单个种子图标领取
local onDecomposeAllCallback = nil  -- function() 一键分解
local onDecomposeOneCallback = nil  -- function(seedIndex) 分解单个种子组
local onAutoDecomposeCallback = nil  -- function() 打开自动分解设置弹窗

-- ======================== 工具函数 ========================

local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 or alpha <= 0.01 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 描边文字绘制
local drawTextStroke = require("core.DrawUtil").drawTextStroke

-- ======================== Public API ========================

--- 初始化
---@param vg any NanoVG 上下文
function LootBox.init(vg)
    cachedVg = vg
    imgBox    = nvgCreateImage(vg, "image/ICON_BX.png", 0)
    imgRedDot = nvgCreateImage(vg, "image/ICON_HD.png", 0)
    if imgBox < 0 then print("[LootBox] WARN: ICON_BX.png load failed") end
    if imgRedDot < 0 then print("[LootBox] WARN: ICON_HD.png load failed") end
    seedCount = 0
    seedSummary = {}

    -- 初始化全屏战利品页面
    LootBoxPage.init(vg)
    -- 绑定 LootBoxPage 回调 → 转发给外部注册的回调
    LootBoxPage.setOnClaimOne(function(seedIndex)
        if onClaimOneCallback then onClaimOneCallback(seedIndex) end
    end)
    LootBoxPage.setOnClaimAll(function()
        if onClaimAllCallback then onClaimAllCallback() end
    end)
    LootBoxPage.setOnDecomposeAll(function()
        if onDecomposeAllCallback then onDecomposeAllCallback() end
    end)
    LootBoxPage.setOnDecomposeOne(function(seedIndex)
        if onDecomposeOneCallback then onDecomposeOneCallback(seedIndex) end
    end)
    LootBoxPage.setOnAutoDecompose(function()
        if onAutoDecomposeCallback then onAutoDecomposeCallback() end
    end)

    print("[LootBox] init OK")
end

--- 更新种子数据（由 Standalone/Client 在数据变化时调用）
---@param lootboxData table { seeds = { {quality, level, count}, ... } }
function LootBox.updateSeedData(lootboxData)
    if not lootboxData or not lootboxData.seeds then
        seedCount = 0
        seedSummary = {}
        return
    end
    local total = 0
    local summary = {}
    for _, seed in ipairs(lootboxData.seeds) do
        local c = seed.count or 1
        total = total + c
        summary[#summary + 1] = {
            quality = seed.quality,
            level   = seed.level,
            count   = c,
        }
    end
    seedCount = total
    seedSummary = summary
end

--- 增加种子计数（击杀掉落时调用，仅更新 UI 显示数）
---@param quality number
---@param level number
function LootBox.addSeedHint(quality, level)
    -- 仅触发抖动动画，不修改 seedCount / seedSummary
    -- 数据由 updateSeedData（服务端订阅 / Standalone 显式调用）统一管理
    shakeTimer = SHAKE_DURATION
end

--- 设置领取回调（一键领取）
---@param callback function()  触发一键领取
function LootBox.setOnClaimAll(callback)
    onClaimAllCallback = callback
end

--- 设置领取回调（单个领取，点击种子图标时触发）
---@param callback function(seedIndex: number) 传入种子条目在 seeds 数组中的索引
function LootBox.setOnClaimOne(callback)
    onClaimOneCallback = callback
end

--- 设置分解回调（一键分解所有种子）
---@param callback function()
function LootBox.setOnDecomposeAll(callback)
    onDecomposeAllCallback = callback
end

--- 设置分解回调（分解单个种子组）
---@param callback function(seedIndex: number)
function LootBox.setOnDecomposeOne(callback)
    onDecomposeOneCallback = callback
end

--- 设置自动分解设置回调（打开自动分解设置弹窗）
---@param callback function()
function LootBox.setOnAutoDecompose(callback)
    onAutoDecomposeCallback = callback
end

--- 设置领取回调（兼容旧接口，Standalone 使用）
---@param callback function(equips: table[])
function LootBox.setOnClaim(callback)
    onClaimCallback = callback
end

--- 获取当前箱子物品数量
---@return number
function LootBox.getCount()
    return seedCount
end

--- 更新
---@param dt number
function LootBox.update(dt)
    -- 抖动衰减
    if shakeTimer > 0 then
        shakeTimer = shakeTimer - dt
        if shakeTimer < 0 then shakeTimer = 0 end
    end

    -- 更新全屏战利品页面（惯性滚动等）
    LootBoxPage.update(dt)
end

--- 处理点击
---@param dx number 设计空间X
---@param dy number 设计空间Y
---@return boolean 是否消费事件
function LootBox.handleInput(dx, dy)
    -- LootBoxPage 打开时优先拦截
    if LootBoxPage.isVisible() then
        return LootBoxPage.handleInput(dx, dy)
    end

    -- 矩形区域判定（更宽容）
    local halfW = TAP_RADIUS
    local halfH = TAP_RADIUS + 30  -- 包含文字区域
    if dx < BOX_CX - halfW or dx > BOX_CX + halfW then return false end
    if dy < BOX_CY - halfH or dy > BOX_CY + halfH + 30 then return false end

    -- 触发抖动（无论有无物品）
    shakeTimer = SHAKE_DURATION

    -- 箱子为空时仅抖动，不打开页面
    if seedCount == 0 then return true end

    -- 打开全屏战利品管理页面
    LootBoxPage.show(seedSummary)
    return true
end

--- 刷新 LootBoxPage 数据（外部数据变更后调用）
function LootBox.refreshPage()
    if LootBoxPage.isVisible() then
        LootBoxPage.refresh(seedSummary)
    end
end

--- LootBoxPage 是否打开
function LootBox.isPageOpen()
    return LootBoxPage.isVisible()
end

--- 绘制全屏战利品页面（在全局覆盖层绘制，应在 RewardPopup 之前）
---@param vg any NanoVG 上下文
function LootBox.drawPage(vg)
    LootBoxPage.draw(vg)
end

--- 转发拖拽事件给 LootBoxPage
function LootBox.handleDragBegin(dx, dy)
    if LootBoxPage.isVisible() then
        return LootBoxPage.handleDragBegin(dx, dy)
    end
    return false
end

function LootBox.handleDragMove(dx, dy)
    if LootBoxPage.isVisible() then
        return LootBoxPage.handleDragMove(dx, dy)
    end
    return false
end

function LootBox.handleDragEnd(dx, dy)
    if LootBoxPage.isVisible() then
        return LootBoxPage.handleDragEnd(dx, dy)
    end
    return false
end

function LootBox.handleScroll(wheel)
    if LootBoxPage.isVisible() then
        return LootBoxPage.handleScroll(wheel)
    end
    return false
end

--- 绘制箱子图标（战斗场景内）
---@param vg any NanoVG 上下文
function LootBox.draw(vg)
    -- 计算抖动偏移：衰减正弦波
    local offsetX = 0
    if shakeTimer > 0 then
        local progress = shakeTimer / SHAKE_DURATION          -- 1→0
        offsetX = math.sin(shakeTimer * SHAKE_FREQ) * SHAKE_AMP * progress
    end

    -- 1. 箱子图标（带抖动）
    drawImageCentered(vg, imgBox, BOX_CX + offsetX, BOX_CY, BOX_SIZE, BOX_SIZE, 1.0)

    -- 2. "战利品" 文本（带抖动）+ 件数
    local label = "战利品"
    if seedCount > 0 then
        label = "战利品(" .. seedCount .. ")"
    end
    drawTextStroke(vg, TEXT_X + offsetX, TEXT_Y, label, TEXT_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, TEXT_STROKE)

    -- 3. 红点（有物品时，跟随抖动）
    if seedCount > 0 then
        drawImageCentered(vg, imgRedDot, DOT_CX + offsetX, DOT_CY, DOT_SIZE, DOT_SIZE, 1.0)
    end
end

return LootBox
