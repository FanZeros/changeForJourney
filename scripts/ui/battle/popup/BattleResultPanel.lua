-- ============================================================================
-- BattleResultPanel - 通用战斗结算面板
-- ============================================================================
--
-- 【使用说明】
-- 通用结算面板，可用于竞技场、副本等任何战斗结束后的结算展示。
-- 副本和通天塔共用的战斗结算。
--
--   local BattleResultPanel = require("ui.battle.popup.BattleResultPanel")
--
--   -- init 阶段（仅一次）：
--   BattleResultPanel.init(vg)
--
--   -- 展示结算：
--   BattleResultPanel.show({
--       isWin        = true,
--       elapsedSecs  = 51,
--       heroStats    = { { heroId=1, quality=3, totalDamage=12345 }, ... },
--       rewards      = { { type="tavern_coin", amount=20 } },
--   })
--
--   -- draw / update / handleInput 在渲染循环中调用
-- ============================================================================

local NumberUtil   = require("core.NumberUtil")
local DrawUtil     = require("core.DrawUtil")
local DarkIcon     = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质底框矢量绘制
local ImageCache   = require("ui.widget.ImageCache")
local ResourceDefs = require("config.ResourceDefs")
local HeroFrame = require("ui.widget.HeroFrame")
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local I18n = require("core.I18n")
local HeroConfig = require("config.HeroConfig")

local BRP = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

-- ======================== 布局常量（基于用户规格） ========================

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

-- [统一角色框] 英雄品质→框映射删除（原 {1→3,2→4,3→5} 缺 UR），改由 HeroFrame 品质色统一

-- 9. 文本"获得"
local OBTAIN_LABEL_X, OBTAIN_LABEL_Y = 93, 1270
local OBTAIN_LABEL_FONT = 40

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

-- ======================== 资源定义表（统一引用中央注册表） ========================
local RESOURCE_DEFS = ResourceDefs.DEFS

-- ======================== 图片句柄 ========================

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
    -- 关闭回调
    onClose     = nil,
    layout      = nil,
    floor       = nil,
    wave        = nil,
}

-- 塔专用横向内容画布，与普通副本的竖版坐标完全隔离。
local TOWER_W, TOWER_H = 1440, 760
local C = {
    background = { 16, 15, 18, 255 }, surface = { 26, 23, 25, 255 },
    border = { 89, 69, 48, 255 }, text = { 231, 220, 200, 255 },
    muted = { 149, 137, 122, 255 }, gold = { 201, 151, 59, 255 },
    red = { 201, 91, 79, 255 },
}
---@type Panel?
local towerRoot = nil
local towerLanguage = ""
-- 仅新增结算显示串；不改全局词典或业务数据，切语言后重建本面板。
local towerText = {
    en = { win = "Tower · Cleared", lose = "Tower · Defeat", floor = "Floor %d",
        time = "Elapsed %d:%02d", stats = "Damage dealt",
        rewards = "Rewards", emptyStats = "No hero statistics", emptyRewards = "No rewards",
        close = "Click anywhere to close" },
    zh_TW = { win = "通天塔 · 通關", lose = "通天塔 · 失敗", floor = "第%d層",
        time = "總耗時 %d分%02d秒", stats = "輸出統計",
        rewards = "獲得獎勵", emptyStats = "暫無角色統計", emptyRewards = "暫無獎勵",
        close = "點擊任意處關閉" },
    ja = { win = "天の塔 · クリア", lose = "天の塔 · 敗北", floor = "%d階",
        time = "所要時間 %d分%02d秒", stats = "与ダメージ",
        rewards = "獲得報酬", emptyStats = "キャラ統計なし", emptyRewards = "報酬なし",
        close = "画面をタップして閉じる" },
    ko = { win = "천공의 탑 · 클리어", lose = "천공의 탑 · 패배", floor = "%d층",
        time = "소요 시간 %d분 %02d초", stats = "피해량 통계",
        rewards = "획득 보상", emptyStats = "영웅 통계 없음", emptyRewards = "보상 없음",
        close = "화면을 눌러 닫기" },
    zh_CN = { win = "通天塔 · 通关", lose = "通天塔 · 失败", floor = "第%d层",
        time = "总耗时 %d分%02d秒", stats = "输出统计",
        rewards = "获得奖励", emptyStats = "暂无角色统计", emptyRewards = "暂无奖励",
        close = "点击任意处关闭" },
}

local function destroyTowerRoot()
    if towerRoot then towerRoot:Destroy() end
    towerRoot = nil
    towerLanguage = ""
end

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

-- 塔面板沿用既有Surface初始化/子树渲染；自绘Widget只负责头像和资源图形。
local ResultIcon = UI.Widget:Extend("TowerResultIcon")
function ResultIcon:Init(props)
    UI.Widget.Init(self, props)
    self.hero = props.hero
    self.reward = props.reward
end
function ResultIcon:Render(vg)
    local l = self:GetAbsoluteLayout()
    local size = math.min(l.w, l.h)
    local cx, cy = l.x + l.w * 0.5, l.y + l.h * 0.5
    local hero = self.hero
    if hero then
        HeroFrame.draw(vg, { cx = cx, cy = cy, size = size,
            heroId = hero.heroId, iconHandle = getHeroIcon(hero.heroId),
            quality = hero.quality, state = "owned" })
        return
    end
    local item = self.reward
    if not item then return end
    local def = RESOURCE_DEFS[item.type]
    DarkIcon.drawQualityBg(vg, item.quality or (def and def.quality) or 1, cx, cy, size, size, 1)
    local img = -1
    if item.iconPath then
        img = resourceIconCache[item.iconPath]
        if not img and cachedVg then
            img = nvgCreateImage(cachedVg, item.iconPath, 0)
            resourceIconCache[item.iconPath] = img
        end
        img = img or -1
    else
        img = getResourceIcon(item.type)
    end
    drawImageCentered(vg, img, cx, cy, size - 16, size - 16, 1)
end

local function towerLabel(caption, x, y, w, h, size, color, align)
    -- 单行测字后缩字号，长英雄名/译文也完整保留，不用省略号或固定双行裁切。
    local measured = UI.MeasureTextWidth(caption, UI.Theme.FontSize(size), "sans")
    local fittedSize = measured > w - 4 and size * (w - 4) / measured or size
    return UI.Label { text = caption, position = "absolute", left = x, top = y,
        width = w, height = h, fontSize = fittedSize, fontColor = color or C.text,
        fontFamily = "sans", fontWeight = "normal", textAlign = align or "left",
        verticalAlign = "middle", whiteSpace = "nowrap", lineHeight = 1.1,
        pointerEvents = "none" }
end

local function buildTowerRoot(language)
    Surface.init()
    local text = towerText[language] or towerText.zh_CN
    local totalSecs = math.max(0, math.floor(state.elapsedSecs))
    local floorText = state.floor and string.format(text.floor, state.floor) or ""
    local stats = UI.Panel { position = "absolute", left = 28, top = 196,
        width = 900, height = 432, backgroundColor = C.surface,
        borderWidth = 1, borderColor = C.border, borderRadius = 4, pointerEvents = "none" }
    -- 三列四行，最多12位全部呈现，不改变传入统计顺序或数值。
    for i = 1, math.min(12, #state.heroStats) do
        local hero = state.heroStats[i]
        local conf = HeroConfig.HEROES[hero.heroId]
        local name = I18n.lookup(hero.name or (conf and conf.name) or tostring(hero.heroId))
        local cell = UI.Panel { position = "absolute", left = 12 + ((i - 1) % 3) * 292,
            top = 12 + math.floor((i - 1) / 3) * 102, width = 280, height = 90,
            backgroundColor = C.background, borderRadius = 4, pointerEvents = "none",
            children = {
                ResultIcon { position = "absolute", left = 8, top = 9,
                    width = 72, height = 72, hero = hero, pointerEvents = "none" },
                towerLabel(name, 92, 6, 180, 38, 19),
                towerLabel(NumberUtil.format(hero.totalDamage or 0), 92, 44, 180, 38, 24, C.gold),
            } }
        stats:AddChild(cell)
    end
    if #state.heroStats == 0 then
        stats:AddChild(towerLabel(text.emptyStats, 24, 180, 852, 50, 26, C.muted, "center"))
    end
    local rewards = UI.Panel { position = "absolute", left = 956, top = 196,
        width = 456, height = 432, backgroundColor = C.surface,
        borderWidth = 1, borderColor = C.border, borderRadius = 4, pointerEvents = "none" }
    -- 塔现行奖励为一条黑晶；其他奖励也逐条显示名字/数量，不沿用竖版横向溢出的图标行。
    local count = #state.rewards
    local columns = count > 4 and 2 or 1
    local rows = math.max(1, math.ceil(count / columns))
    local rowHeight = math.min(94, 408 / rows)
    local cellWidth = 432 / columns
    for i, item in ipairs(state.rewards) do
        local def = RESOURCE_DEFS[item.type]
        local name = I18n.lookup(item.name or (def and def.name) or tostring(item.type))
        local iconSize = math.min(68, rowHeight - 12)
        rewards:AddChild(UI.Panel { position = "absolute",
            left = 12 + ((i - 1) % columns) * cellWidth,
            top = 12 + math.floor((i - 1) / columns) * rowHeight,
            width = cellWidth, height = rowHeight, pointerEvents = "none", children = {
                ResultIcon { position = "absolute", left = 8, top = (rowHeight - iconSize) * 0.5,
                    width = iconSize, height = iconSize, reward = item, pointerEvents = "none" },
                towerLabel(name, iconSize + 24, 3, cellWidth - iconSize - 32, rowHeight * 0.5, 19),
                towerLabel("×" .. NumberUtil.format(item.amount or 0), iconSize + 24, rowHeight * 0.5,
                    cellWidth - iconSize - 32, rowHeight * 0.5 - 3, 23, C.gold),
            } })
    end
    if count == 0 then
        rewards:AddChild(towerLabel(text.emptyRewards, 16, 180, 424, 50, 25, C.muted, "center"))
    end
    towerRoot = UI.Panel { width = TOWER_W, height = TOWER_H,
        backgroundColor = C.background, borderWidth = 2, borderColor = C.border,
        borderRadius = 6, pointerEvents = "none", children = {
            towerLabel(state.isWin and text.win or text.lose, 28, 24, 884, 66, 40,
                state.isWin and C.gold or C.red),
            towerLabel(floorText, 28, 94, 884, 38, 24, C.muted),
            towerLabel(string.format(text.time, math.floor(totalSecs / 60), totalSecs % 60),
                956, 34, 456, 54, 26, C.text, "right"),
            towerLabel(text.stats, 28, 146, 900, 40, 26),
            towerLabel(text.rewards, 956, 146, 456, 40, 26),
            stats, rewards,
            UI.Button { text = text.close, position = "absolute", left = 432, top = 666,
                width = 576, height = 64, fontSize = 24, fontFamily = "sans", fontWeight = "normal",
                textColor = C.text, backgroundColor = C.surface, borderWidth = 2,
                borderColor = C.border, borderRadius = 4, pointerEvents = "none" },
        } }
    towerLanguage = language
end

local function drawTower(vg, width, height)
    local language = I18n.get()
    if not towerRoot or language ~= towerLanguage then
        destroyTowerRoot()
        buildTowerRoot(language)
    end
    local root = towerRoot
    local scale = math.min(width / (TOWER_W + 64), height / (TOWER_H + 64))
    -- 由宿主提供逻辑尺寸，不再次读取物理分辨率或重复应用DPR。
    nvgSave(vg)
    local ok, err = xpcall(function()
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, width, height)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
        nvgFill(vg)
        nvgTranslate(vg, (width - TOWER_W * scale) * 0.5, (height - TOWER_H * scale) * 0.5)
        nvgScale(vg, scale, scale)
        if root then Surface.draw(root, vg, TOWER_W, TOWER_H) end
    end, debug.traceback)
    nvgRestore(vg)
    if not ok then error(err, 0) end
end

-- ======================== Public API ========================

--- 初始化（加载图片资源，仅调用一次）
---@param vg any NanoVG 上下文
function BRP.init(vg)
    destroyTowerRoot()
    cachedVg = vg
    print("[BattleResultPanel] init OK")
end

--- 展示结算面板（layout='tower' 仅启用通天塔横向UI，普通入口不变）
---@param opts table { isWin, elapsedSecs, heroStats, rewards, onClose, layout?, floor?, wave? }
function BRP.show(opts)
    opts = opts or {}
    destroyTowerRoot()
    state.open        = true
    state.isWin       = opts.isWin or false
    state.elapsedSecs = opts.elapsedSecs or 0
    state.heroStats   = opts.heroStats or {}
    state.rewards     = opts.rewards or {}
    state.onClose     = opts.onClose
    state.layout      = opts.layout == "tower" and "tower" or nil
    state.floor       = opts.floor
    state.wave        = opts.wave
    print("[BattleResultPanel] show: " .. (state.isWin and "WIN" or "LOSE")
        .. " heroes=" .. #state.heroStats
        .. " rewards=" .. #state.rewards)
end

--- 关闭结算面板
function BRP.close()
    destroyTowerRoot()
    if not state.open then return end
    state.open = false
    local cb = state.onClose
    state.onClose = nil
    print("[BattleResultPanel] closed")
    if cb then cb() end
end

--- 清档/宿主Stop专用：只丢弃本面板，不调用旧结算回调或删除共享图片句柄。
function BRP.resetToDefault()
    destroyTowerRoot()
    state.open, state.isWin = false, false
    state.onClose, state.layout, state.floor, state.wave = nil, nil, nil, nil
    state.elapsedSecs, state.heroStats, state.rewards = 0, {}, {}
end

--- 是否打开
---@return boolean
function BRP.isOpen()
    return state.open
end

--- 更新（结算面板不再播旋转光效）
---@param _dt number
function BRP.update(_dt)
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
function BRP.draw(vg, width, height)
    if not state.open then return end
    if state.layout == "tower" then
        width, height = width or 1920, height or 1080
        if width > 0 and height > 0 then drawTower(vg, width, height) end
        return
    end

    -- 横屏只拟合实际结算内容，不再缩放整张2400高竖版画布。
    if width and height then
        nvgSave(vg)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, width, height)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
        nvgFill(vg)
        local fit = math.min(width / 1180, height / 1180)
        nvgTranslate(vg, width * 0.5, height * 0.5)
        nvgScale(vg, fit, fit)
        nvgTranslate(vg, -540, -1300)
    end

    -- === 0. 全屏黑色遮罩（50%不透明度） ===
    if not width then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
        nvgFill(vg)
    end

    -- === 3. 消耗时间（结算底板已移除） ===
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

        -- 6.1+6.2) [统一角色框] 品质色描边 + 头像（替代 ZBBJ 贴图映射，修复缺 UR 映射）
        local heroImg = getHeroIcon(hero.heroId)
        HeroFrame.draw(vg, {
            cx = cx, cy = cy, size = HERO_ICON_SIZE,
            heroId = hero.heroId,
            iconHandle = heroImg,
            quality = hero.quality,
            state = "owned",
        })

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
    if width and height then nvgRestore(vg) end
end

return BRP
