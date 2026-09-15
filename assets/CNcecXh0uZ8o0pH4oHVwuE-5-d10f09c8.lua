-- ============================================================================
-- BattleResultPanel - 通用战斗结算面板
-- ============================================================================
--
-- 【使用说明】
-- 通用结算面板，可用于竞技场、副本等任何战斗结束后的结算展示。
-- 竞技场专用元素（竞技分变动）通过 arenaMode 标志控制显示。
--
--   local BattleResultPanel = require("ui.BattleResultPanel")
--
--   -- init 阶段（仅一次）：
--   BattleResultPanel.init(vg)
--
--   -- 展示结算：
--   BattleResultPanel.show({
--       isWin        = true,
--       elapsedSecs  = 51,
--       heroStats    = { { heroId=1, quality=3, totalDamage=12345 }, ... },
--       rewards      = { { type="arena_coin", amount=20 } },
--       -- 竞技场专用（可选）
--       arenaMode    = true,
--       scoreChange  = 15,
--   })
--
--   -- draw / update / handleInput 在渲染循环中调用
-- ============================================================================

local NumberUtil   = require("core.NumberUtil")
local DrawUtil     = require("core.DrawUtil")
local DarkIcon     = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质底框矢量绘制
local ImageCache   = require("ui.ImageCache")
local ResourceDefs = require("config.ResourceDefs")

local drawTextStroke = DrawUtil.drawTextStroke

local BRP = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

-- ======================== 布局常量（基于用户规格） ========================

-- 1. 结算背景
local BG_CX, BG_CY = 540, 1192
local BG_W, BG_H   = 1080, 1017

-- 2. 闪光动态背景（旋转）
local GLOW_CX, GLOW_CY = 540, 876
local GLOW_W, GLOW_H   = 908, 909

-- 3. 消耗时间
local TIME_CX, TIME_CY = 540, 827
local TIME_FONT = 40

-- 4. 文本"输出统计"
local STAT_LABEL_X, STAT_LABEL_Y = 133, 891
local STAT_LABEL_FONT = 40

-- 5. 输出统计背景框
local STAT_BG_CX, STAT_BG_CY = 540, 1069
local STAT_BG_W, STAT_BG_H   = 968, 288

-- 6. 角色输出组合
local HERO_ICON_SIZE = 114
-- 列 X: 147, 478, 809
local HERO_COL_X = { 147, 478, 809 }
-- 行 Y: 995, 1135
local HERO_ROW_Y = { 995, 1135 }
-- 文字左对齐 X 偏移（相对图标中心）
local HERO_DMG_OFFSET_X = 81  -- 228 - 147 = 81
local HERO_DMG_FONT = 40

-- 品质映射：英雄品质 1=R → 框3, 2=SR → 框4, 3=SSR → 框5
local HERO_QUALITY_TO_FRAME = { [1] = 3, [2] = 4, [3] = 5 }

-- 9. 文本"获得"
local OBTAIN_LABEL_X, OBTAIN_LABEL_Y = 93, 1270
local OBTAIN_LABEL_FONT = 40

-- 10. 竞技分图标（竞技场专用）
local SCORE_ICON_CX, SCORE_ICON_CY = 903, 1263
local SCORE_ICON_W, SCORE_ICON_H   = 70, 70

-- 11. 竞技分增减文本（竞技场专用）
local SCORE_TEXT_X, SCORE_TEXT_Y = 977, 1263
local SCORE_TEXT_FONT = 40

-- 12. 获得奖励背景框
local REWARD_BG_CX, REWARD_BG_CY = 540, 1462
local REWARD_BG_W, REWARD_BG_H   = 968, 310

-- 13. 奖励图标
local REWARD_ICON_SIZE = 160
local REWARD_FIRST_CX  = 160
local REWARD_CY        = 1414
local REWARD_GAP       = 180  -- 图标间距

-- 14. "点击空白处关闭"
local HINT_CX, HINT_CY = 540, 1797
local HINT_FONT = 50

-- 角标样式（与 RewardPopup 一致）
local BADGE_FONT   = 40
local BADGE_STROKE = 4

-- 光晕旋转速度（弧度/秒）
local GLOW_ROTATE_SPEED = 0.5

-- ======================== 资源定义表（统一引用中央注册表） ========================
local RESOURCE_DEFS = ResourceDefs.DEFS

-- ======================== 图片句柄 ========================

local imgWinBg   = -1   -- UI_JJCJS_ZDSL.png
local imgLoseBg  = -1   -- UI_JJCJS_ZDSB.png
local imgWinGlow = -1   -- UI_GXHD_2.png
local imgLoseGlow = -1  -- UI_GXHD_3.png
local imgScoreIcon = -1 -- UI_icon_JJCFS_X.png

-- 英雄头像缓存: heroId → nvgImage
local heroIconCache = {}
-- 资源图标缓存: type → nvgImage
local resourceIconCache = {}

local cachedVg = nil

-- ======================== 状态 ========================

local state = {
    open        = false,
    isWin       = false,
    elapsedSecs = 0,
    heroStats   = {},     -- { heroId, quality, totalDamage }[]
    rewards     = {},     -- { type, amount }[]
    arenaMode   = false,
    scoreChange = 0,
    -- 动画
    glowAngle   = 0,
    -- 关闭回调
    onClose     = nil,
}

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

--- 绘制旋转图片
local function drawImageRotated(vg, img, cx, cy, w, h, angle, alpha)
    if img < 0 or alpha <= 0.01 then return end
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, angle)
    local x = -w * 0.5
    local y = -h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    nvgRestore(vg)
end

--- 获取英雄头像（懒加载）
local function getHeroIcon(heroId)
    local cached = heroIconCache[heroId]
    if cached then return cached end
    if not cachedVg then return -1 end
    local path = "image/角色图标/UI_icon_hero_" .. tostring(heroId) .. ".png"
    local img = nvgCreateImage(cachedVg, path, 0)
    heroIconCache[heroId] = img
    return img
end

--- 获取资源图标（懒加载）
local function getResourceIcon(resType)
    local cached = resourceIconCache[resType]
    if cached then return cached end
    if not cachedVg then return -1 end
    local def = RESOURCE_DEFS[resType]
    if not def then return -1 end
    local img = nvgCreateImage(cachedVg, def.iconPath, 0)
    resourceIconCache[resType] = img
    return img
end

--- 绘制数量角标（右下角，16方向描边，与 RewardPopup 样式一致）
local function drawBadge(vg, text, cx, cy, iconSize)
    local bx = cx + iconSize * 0.5 - 8
    local by = cy + iconSize * 0.5 - 8
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BADGE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    -- 描边层
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
    local sStep = math.pi * 2 / 16
    for si = 0, 15 do
        local sa = si * sStep
        nvgText(vg, bx + math.cos(sa) * BADGE_STROKE, by + math.sin(sa) * BADGE_STROKE, text, nil)
    end
    -- 填充层
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, bx, by, text, nil)
end

-- ======================== Public API ========================

--- 初始化（加载图片资源，仅调用一次）
---@param vg any NanoVG 上下文
function BRP.init(vg)
    cachedVg = vg
    imgWinBg    = nvgCreateImage(vg, "image/UI_JJCJS_ZDSL.png", 0)
    imgLoseBg   = nvgCreateImage(vg, "image/UI_JJCJS_ZDSB.png", 0)
    imgWinGlow  = nvgCreateImage(vg, "image/UI_GXHD_2.png", 0)
    imgLoseGlow = nvgCreateImage(vg, "image/UI_GXHD_3.png", 0)
    imgScoreIcon = nvgCreateImage(vg, "image/UI_icon_JJCFS_X.png", 0)
    print("[BattleResultPanel] init OK")
end

--- 展示结算面板
---@param opts table { isWin, elapsedSecs, heroStats, rewards, arenaMode, scoreChange, onClose }
function BRP.show(opts)
    opts = opts or {}
    state.open        = true
    state.isWin       = opts.isWin or false
    state.elapsedSecs = opts.elapsedSecs or 0
    state.heroStats   = opts.heroStats or {}
    state.rewards     = opts.rewards or {}
    state.arenaMode   = opts.arenaMode or false
    state.scoreChange = opts.scoreChange or 0
    state.onClose     = opts.onClose
    state.glowAngle   = 0
    print("[BattleResultPanel] show: " .. (state.isWin and "WIN" or "LOSE")
        .. " heroes=" .. #state.heroStats
        .. " rewards=" .. #state.rewards
        .. " arena=" .. tostring(state.arenaMode))
end

--- 关闭结算面板
function BRP.close()
    if not state.open then return end
    state.open = false
    local cb = state.onClose
    state.onClose = nil
    print("[BattleResultPanel] closed")
    if cb then cb() end
end

--- 是否打开
---@return boolean
function BRP.isOpen()
    return state.open
end

--- 更新（光晕旋转动画）
---@param dt number
function BRP.update(dt)
    if not state.open then return end
    state.glowAngle = state.glowAngle + GLOW_ROTATE_SPEED * dt
end

--- 处理点击（点击任意位置关闭）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function BRP.handleInput(dx, dy)
    if not state.open then return false end
    BRP.close()
    return true
end

-- ======================== 绘制 ========================

---@param vg any NanoVG 上下文
function BRP.draw(vg)
    if not state.open then return end

    -- === 0. 全屏黑色遮罩（50%不透明度） ===
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))  -- 50% = 255*0.5 ≈ 128
    nvgFill(vg)

    -- === 1. 闪光动态背景（旋转，在结算背景后面） ===
    local glowImg = state.isWin and imgWinGlow or imgLoseGlow
    drawImageRotated(vg, glowImg, GLOW_CX, GLOW_CY, GLOW_W, GLOW_H, state.glowAngle, 1.0)

    -- === 2. 结算背景 ===
    local bgImg = state.isWin and imgWinBg or imgLoseBg
    drawImageCentered(vg, bgImg, BG_CX, BG_CY, BG_W, BG_H, 1.0)

    -- === 3. 消耗时间 ===
    local totalSecs = math.floor(state.elapsedSecs)
    local mins = math.floor(totalSecs / 60)
    local secs = totalSecs % 60
    local timeText = string.format("总耗时：%d分%02d秒", mins, secs)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TIME_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, TIME_CX, TIME_CY, timeText, nil)

    -- === 4. 文本"输出统计" ===
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, STAT_LABEL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xb1, 0xb1, 0xb1, 255))
    nvgText(vg, STAT_LABEL_X, STAT_LABEL_Y, "输出统计", nil)

    -- === 5. 输出统计背景框（纯黑20%不透明度） ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        STAT_BG_CX - STAT_BG_W * 0.5, STAT_BG_CY - STAT_BG_H * 0.5,
        STAT_BG_W, STAT_BG_H, 12)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 51))  -- 20% = 255*0.2 ≈ 51
    nvgFill(vg)

    -- === 6~8. 角色输出组合（最多6个，2行3列） ===
    for i, hero in ipairs(state.heroStats) do
        if i > 6 then break end
        local col = ((i - 1) % 3) + 1
        local row = ((i - 1) < 3) and 1 or 2
        local cx = HERO_COL_X[col]
        local cy = HERO_ROW_Y[row]

        -- 6.1) 品质背景框 [暗黑化 P2-A]
        local frameQ = HERO_QUALITY_TO_FRAME[hero.quality] or 3
        DarkIcon.drawQualityBg(vg, frameQ, cx, cy, HERO_ICON_SIZE, HERO_ICON_SIZE, 1.0)

        -- 6.2) 角色头像（与品质框同尺寸）
        local heroImg = getHeroIcon(hero.heroId)
        if heroImg >= 0 then
            drawImageCentered(vg, heroImg, cx, cy, HERO_ICON_SIZE, HERO_ICON_SIZE, 1.0)
        end

        -- 6.3) 累计输出数值
        local dmgText = NumberUtil.format(hero.totalDamage or 0)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, HERO_DMG_FONT)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, cx + HERO_DMG_OFFSET_X, cy, dmgText, nil)
    end

    -- === 9. 文本"获得" ===
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, OBTAIN_LABEL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xb1, 0xb1, 0xb1, 255))
    nvgText(vg, OBTAIN_LABEL_X, OBTAIN_LABEL_Y, "获得", nil)

    -- === 10~11. 竞技分变动（竞技场专用） ===
    if state.arenaMode then
        -- 10. 竞技分图标
        drawImageCentered(vg, imgScoreIcon, SCORE_ICON_CX, SCORE_ICON_CY,
            SCORE_ICON_W, SCORE_ICON_H, 1.0)

        -- 11. 竞技分增减文本
        local sc = state.scoreChange
        local scoreText, scoreR, scoreG, scoreB
        if sc >= 0 then
            scoreText = "+" .. tostring(sc)
            scoreR, scoreG, scoreB = 0x90, 0xff, 0x8a  -- 绿色
        else
            scoreText = tostring(sc)
            scoreR, scoreG, scoreB = 0xff, 0x78, 0x78  -- 红色
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, SCORE_TEXT_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(scoreR, scoreG, scoreB, 255))
        nvgText(vg, SCORE_TEXT_X, SCORE_TEXT_Y, scoreText, nil)
    end

    -- === 12. 获得奖励背景框（纯黑20%不透明度） ===
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        REWARD_BG_CX - REWARD_BG_W * 0.5, REWARD_BG_CY - REWARD_BG_H * 0.5,
        REWARD_BG_W, REWARD_BG_H, 12)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 51))  -- 20%
    nvgFill(vg)

    -- === 13. 获得奖励图标 ===
    for i, item in ipairs(state.rewards) do
        local cx = REWARD_FIRST_CX + (i - 1) * REWARD_GAP
        local cy = REWARD_CY

        -- 品质背景框（优先使用 item.quality 覆盖）
        local def = RESOURCE_DEFS[item.type]
        local q = item.quality or (def and def.quality) or 1
        DarkIcon.drawQualityBg(vg, q, cx, cy, REWARD_ICON_SIZE, REWARD_ICON_SIZE, 1.0)  -- [暗黑化 P2-A]

        -- 资源图标（优先使用 item.iconPath 覆盖）
        local resImg = -1
        if item.iconPath then
            local cacheKey = item.iconPath
            if resourceIconCache[cacheKey] then
                resImg = resourceIconCache[cacheKey]
            elseif cachedVg then
                resImg = nvgCreateImage(cachedVg, item.iconPath, 0)
                resourceIconCache[cacheKey] = resImg
            end
        else
            resImg = getResourceIcon(item.type)
        end
        if resImg >= 0 then
            local iconPadding = 12
            local iconInner = REWARD_ICON_SIZE - iconPadding * 2
            drawImageCentered(vg, resImg, cx, cy, iconInner, iconInner, 1.0)
        end

        -- 数量角标（右下角，与 RewardPopup 一致；amount<=1 时不显示）
        if item.amount and item.amount > 1 then
            local badgeText = "×" .. NumberUtil.format(item.amount)
            drawBadge(vg, badgeText, cx, cy, REWARD_ICON_SIZE)
        end
    end

    -- === 14. "点击空白处关闭" ===
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, HINT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, HINT_CX, HINT_CY, "点击空白处关闭", nil)
end

return BRP
