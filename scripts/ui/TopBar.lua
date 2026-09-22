-- ============================================================================
-- TopBar - 顶部信息栏渲染（14 个元素，NanoVG 绘制）
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local GameState      = require("core.GameState")
local NumberUtil     = require("core.NumberUtil")
local CharacterPanel = require("ui.CharacterPanel")
local HeroAssetUtil   = require("config.HeroAssetUtil")
local HeroConfig     = require("config.HeroConfig")
local DarkIcon       = require("core.DarkIcon")  -- [暗黑化 P0] 矢量图标库
local BottomNav      = require("ui.BottomNav")

local TopBar = {}

-- Image handles
local imgExpBg   = -1
local imgExpFill = -1
local imgGoldIcon = -1   -- [三队并行] 金币图标（以角色详情页 UI_icon_JB_X 为准）
local imgGemIcon  = -1   -- [三队并行] 钻石图标（以角色详情页 UI_icon_SJ_X 为准）
local imgHeroIcons = {}  -- [heroId] 角色头像图标
-- [暗黑化 P0] 金币/钻石/战力/红点 图标改由 core/DarkIcon.lua 程序化矢量绘制，不再加载贴图

-- ======================== 本地数据缓存（多人模式由 Client.lua 设置） ========================
-- 设置后优先使用，未设置（nil）时回退到 GameState
local cachedName     = nil   ---@type string|nil  玩家昵称（来自 GetUserNickname API）
local cachedLevel    = nil   ---@type number|nil
local cachedExp      = nil   ---@type number|nil
local cachedMaxExp   = nil   ---@type number|nil
local cachedPower    = nil   ---@type number|nil  队伍总战斗力
local cachedGold     = nil   ---@type number|nil
local cachedGems     = nil   ---@type number|nil
local cachedAvatarHeroId  = 1 ---@type number 当前头像英雄 ID
local lastSeenOwnedCount = nil ---@type number|nil 上次查看头像面板时的已拥有英雄数（nil=未初始化）

-- ============================================================================
-- Helper Functions
-- ============================================================================

--- 居中绘制图片
local function drawImageCentered(vg, img, cx, cy, w, h)
    if img < 0 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 居中绘制圆角矩形
local function drawRoundedRectCentered(vg, cx, cy, w, h, r, rr, gg, bb, aa)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - w * 0.5, cy - h * 0.5, w, h, r)
    nvgFillColor(vg, nvgRGBA(rr, gg, bb, aa))
    nvgFill(vg)
end

local drawTextStroke = require("core.DrawUtil").drawTextStroke


-- ============================================================================
-- Public API
-- ============================================================================

--- 初始化（加载图片资源，仅调用一次）
function TopBar.init(vg)
    imgExpBg   = nvgCreateImage(vg, "image/进度条/UI_JYT_1.png", 0)
    imgExpFill = nvgCreateImage(vg, "image/进度条/UI_JYT_2.png", 0)
    imgGoldIcon = nvgCreateImage(vg, "image/货币道具/UI_icon_JB.png", 0)
    imgGemIcon  = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ.png", 0)
    -- 加载角色头像图标
    HeroAssetUtil.preloadIcons(vg, imgHeroIcons)

    if imgExpBg   < 0 then print("[TopBar] WARN: UI_JYT_1.png load failed") end
    if imgExpFill < 0 then print("[TopBar] WARN: UI_JYT_2.png load failed") end
    print("[TopBar] init OK")
end

-- ======================== 数据设置接口 ========================

--- 设置玩家昵称（来自 GetUserNickname API）
---@param name string
function TopBar.setPlayerName(name)
    cachedName = name
end

--- 设置队伍总战斗力（来自 CharacterPanel.getTotalPower）
---@param power number
function TopBar.setTotalPower(power)
    cachedPower = power
end

--- 设置头像英雄 ID（由 PlayerInfoPanel 更换头像时调用）
---@param heroId number
function TopBar.setAvatarHeroId(heroId)
    cachedAvatarHeroId = heroId or 1
end

--- 获取当前头像英雄 ID
---@return number
function TopBar.getAvatarHeroId()
    return cachedAvatarHeroId
end

--- 获取当前拥有的英雄数量
---@return number
local function getOwnedCount()
    local count = 0
    for _, heroId in ipairs(HeroConfig.getAllIds()) do
        if CharacterPanel.isOwned(heroId) then
            count = count + 1
        end
    end
    return count
end

--- 检查是否有新的可更换头像（用于红点提示）
--- 当拥有的英雄数量比上次查看时多时显示红点
---@return boolean
function TopBar.hasAvailableAvatar()
    local currentCount = getOwnedCount()
    if lastSeenOwnedCount == nil then
        if currentCount > 0 then
            lastSeenOwnedCount = currentCount
        end
        return false
    end
    return currentCount > lastSeenOwnedCount
end

--- 标记头像面板已查看（消除红点）
function TopBar.markAvatarViewed()
    lastSeenOwnedCount = getOwnedCount()
end

--- 设置玩家基础数据（来自服务端 player 模块推送）
---@param data table { level, exp, maxExp }
function TopBar.setPlayerData(data)
    if data.level        ~= nil then cachedLevel        = data.level        end
    if data.exp          ~= nil then cachedExp          = data.exp          end
    if data.maxExp       ~= nil then cachedMaxExp       = data.maxExp       end
    if data.avatarHeroId ~= nil then
        cachedAvatarHeroId = data.avatarHeroId
    end
end

--- 设置货币数据（来自服务端 currency 模块推送）
---@param data table { gold, gems }
function TopBar.setCurrencyData(data)
    if data.gold ~= nil then cachedGold = data.gold end
    if data.gems ~= nil then cachedGems = data.gems end
end

--- 重置顶部栏会话缓存（切区/返回选服时调用）
--- 旧区的等级、货币、战力和头像不应在新区数据到达前继续显示。
function TopBar.resetSessionData()
    cachedLevel = nil
    cachedExp = nil
    cachedMaxExp = nil
    cachedPower = nil
    cachedGold = nil
    cachedGems = nil
    cachedAvatarHeroId = 1
    lastSeenOwnedCount = nil
    print("[TopBar] session data reset")
end

--- 每帧绘制（在设计空间 1080x2400 内调用）

-- 页面入口（替代底栏五键）。通栏放在头像行正下方，避开金币/钻石。
-- 页面入口：横屏三栏下 角色常驻右栏 / 城镇常驻左栏，入口键冗余已删；
-- 仅保留中栏页面：日志 / 战斗 / 副本
local PAGE_TABS = {
    [2] = { index = 2, name = "日志", icon = "nav_log",     hotspot = "tab_log" },
    [3] = { index = 3, name = "战斗", icon = "nav_battle",  hotspot = "tab_battle" },
    [5] = { index = 5, name = "副本", icon = "nav_dungeon", hotspot = "tab_dungeon" },
}
local PAGE_TAB_ORDER = { 2, 3, 5 }
local PAGE_BTN_W, PAGE_BTN_H = 196, 64
local PAGE_BTN_GAP = 12
local PAGE_BTN_CY = 244
local PAGE_BTN_START_CX = 108
local PAGE_HOTSPOT_KEYS = {
    tab_log = 2,
    tab_battle = 3,
    tab_dungeon = 5,
}

local function pageBtnCenterX(i)
    return PAGE_BTN_START_CX + (i - 1) * (PAGE_BTN_W + PAGE_BTN_GAP)
end

--- 横屏三联已常驻城镇/战斗/角色，页签条（日志/战斗/副本）不再显示
local function shouldHidePageTabs(hidePageTabs)
    if hidePageTabs then return true end
    local ok, BTP = pcall(require, "ui.BattleTriPage")
    if not ok or not BTP or not BTP.isOpen then return false end
    return BTP.isOpen() == true
end

function TopBar.draw(vg, offsetY, hidePageTabs)
    -- 可选纵向偏移：三行并行左面板调用时上移头像区（热区同步用 TopBar.hitTestAvatar）
    -- hidePageTabs：横屏三联布局下城镇/战斗/角色已常驻，不再画日志/战斗/副本页签
    local oy = tonumber(offsetY) or 0
    hidePageTabs = shouldHidePageTabs(hidePageTabs)
    -- #1 头像背景框: center(239,139+oy), 382x136, black 70%, r=36
    drawRoundedRectCentered(vg, 239, 139 + oy, 382, 136, 36, 0, 0, 0, 178)

    -- #2 玩家头像: center(98,136+oy), 150x150（裁剪为圆角矩形）
    -- 始终先画灰色底作为底层背景
    drawRoundedRectCentered(vg, 98, 136 + oy, 150, 150, 20, 80, 80, 100, 255)
    local avatarId = cachedAvatarHeroId or 1
    local avatarImg = HeroAssetUtil.ensureIcon(vg, imgHeroIcons, avatarId)
    if (not avatarImg or avatarImg < 0) and avatarId ~= 1 then
        avatarImg = HeroAssetUtil.ensureIcon(vg, imgHeroIcons, 1)
    end
    if avatarImg and avatarImg >= 0 then
        -- 用圆角裁剪绘制头像（覆盖在灰色底上）
        local avCX, avCY, avW, avH = 98, 136 + oy, 150, 150
        nvgSave(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, avCX - avW * 0.5, avCY - avH * 0.5, avW, avH, 20)
        local paint = nvgImagePattern(vg, avCX - avW * 0.5, avCY - avH * 0.5, avW, avH, 0, avatarImg, 1.0)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- #2c 红点提示（有可更换头像时显示）[暗黑化 P0: 余烬光点]
    if TopBar.hasAvailableAvatar() then
        DarkIcon.draw(vg, "reddot", 160, 74, 74, 1)
    end

    -- #2e 页面入口：非三联旧布局才画日志/战斗/副本；横屏三联已常驻，不再画
    if not hidePageTabs then
        local selectedTab = BottomNav.getSelectedIndex()
        local allLocked = BottomNav.isAllLocked()
        for _pi, idx in ipairs(PAGE_TAB_ORDER) do local i, tab = _pi, PAGE_TABS[idx]
            local cx = pageBtnCenterX(i)
            local cy = PAGE_BTN_CY + oy
            local x = cx - PAGE_BTN_W * 0.5
            local y = cy - PAGE_BTN_H * 0.5
            local locked = allLocked or BottomNav.isTabLocked(tab.index)
            local isSel = (tab.index == selectedTab)
            local alpha = locked and 0.38 or 1.0
            if isSel then
                DarkIcon.drawNine(vg, "btn", x, y, PAGE_BTN_W, PAGE_BTN_H, { accent = "gold", alpha = alpha })
            else
                DarkIcon.drawNine(vg, "plain", x, y, PAGE_BTN_W, PAGE_BTN_H, { alpha = alpha })
            end
            DarkIcon.draw(vg, tab.icon, cx, cy - 8, 36, alpha)
            local tr, tg, tb = 216, 201, 163
            if isSel then
                tr, tg, tb = 240, 199, 94
            elseif locked then
                tr, tg, tb = 110, 100, 80
            end
            drawTextStroke(vg, cx, cy + 20, tab.name, 20,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, tr, tg, tb, 3,
                { strokeColor = { 0x1a, 0x12, 0x0a } })
            local showBadge, badgeStyle = BottomNav.getBadge(tab.index)
            if showBadge and not locked then
                DarkIcon.draw(vg, "reddot", cx + PAGE_BTN_W * 0.38, cy - PAGE_BTN_H * 0.38, 28, 1)
            end
        end

        local TM = require("systems.TutorialManager")
        if TM.isActive() then
            for _pi, idx in ipairs(PAGE_TAB_ORDER) do local i, tab = _pi, PAGE_TABS[idx]
                TM.registerHotspot(tab.hotspot, pageBtnCenterX(i), PAGE_BTN_CY + oy, PAGE_BTN_W, PAGE_BTN_H)
            end
        end
    end

    -- #3 等级背景框: center(98,200+oy), 66x38, black, r=14
    drawRoundedRectCentered(vg, 98, 200 + oy, 66, 38, 14, 0, 0, 0, 255)

    -- #4 等级文本: center(98,200), font 30, white
    local displayLevel = cachedLevel or GameState.getLevel()
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, 98, 200 + oy, tostring(displayLevel), nil)

    -- #5 经验条背景: UI_JYT_1.png, center(290,138+oy), 206x24
    local expCX, expCY = 290, 138 + oy
    local expW, expH = 206, 24
    drawImageCentered(vg, imgExpBg, expCX, expCY, expW, expH)

    -- #6 经验进度条: UI_JYT_2.png, inside #5, 4px padding, progress
    local pad = 4
    local fillX = expCX - expW * 0.5 + pad
    local fillY = expCY - expH * 0.5 + pad
    local fillW = expW - pad * 2
    local fillH = expH - pad * 2
    local displayExp    = cachedExp or GameState.getExp()
    local displayMaxExp = cachedMaxExp or GameState.getMaxExp()
    local progress = displayMaxExp > 0 and math.min(displayExp / displayMaxExp, 1.0) or 0
    local clipW = fillW * progress

    if clipW > 0 then
        nvgSave(vg)
        nvgScissor(vg, fillX, fillY, clipW, fillH)
        local paint = nvgImagePattern(vg, fillX, fillY, fillW, fillH, 0, imgExpFill, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, fillX, fillY, fillW, fillH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- #7 玩家名称: left=187, Y=103+oy, font 30, white, stroke 4
    --    自适应缩放：名称区域最大宽度 = 头像背景右边界(430) - 左起点(187) - 边距(8)
    local displayName = cachedName or GameState.getName()
    local nameMaxW = 235
    local nameFontSize = 30
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, nameFontSize)
    local advance, bounds = nvgTextBounds(vg, 0, 0, displayName)
    if advance > nameMaxW and advance > 0 then
        nameFontSize = math.max(16, math.floor(nameFontSize * nameMaxW / advance))
    end
    drawTextStroke(vg, 187, 103 + oy, displayName,
        nameFontSize, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4)

    -- #8 战力图标 + 数值: icon center(197,175+oy) 36x36, text left=220, Y=175+oy [暗黑化 P0: 余烬火焰]
    local displayPower = GameState.getPower()
    DarkIcon.draw(vg, "power", 197, 175 + oy, 36, 1)
    drawTextStroke(vg, 220, 175 + oy, tostring(displayPower),
        30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        247, 254, 119, 4)

    -- #9 金币背景: center(732,100), 170x47, r=18, black 80%
    local goldBgCX, goldBgCY = 732, 100
    local goldBgW, goldBgH = 170, 47
    drawRoundedRectCentered(vg, goldBgCX, goldBgCY, goldBgW, goldBgH, 18, 0, 0, 0, 204)

    -- #10 金币图标: center(653,100), 73x73 [三队并行] 以角色详情页图标为准
    drawImageCentered(vg, imgGoldIcon, 653, 100, 73, 73, 1.0)

    -- #11 金币数值: left=goldBgLeft+44, Y=100, font 33, white, stroke 4
    local displayGold = GameState.getGold()  -- [修复] 直读实时值(此前 cachedGold 推送一次后恒旧, 花费不更新)
    local goldBgLeft = goldBgCX - goldBgW * 0.5
    drawTextStroke(vg, goldBgLeft + 44, 100, NumberUtil.format(displayGold),
        33, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4)

    -- #12 钻石背景: center(965,100), 170x47, r=18, black 80%
    local gemBgCX, gemBgCY = 965, 100
    local gemBgW, gemBgH = 170, 47
    drawRoundedRectCentered(vg, gemBgCX, gemBgCY, gemBgW, gemBgH, 18, 0, 0, 0, 204)

    -- #13 钻石图标: center(884,100), 76x76 [三队并行] 以角色详情页图标为准
    drawImageCentered(vg, imgGemIcon, 884, 100, 76, 76, 1.0)

    -- #14 钻石数值: left=diamondBgLeft+44, Y=100, font 33, white, stroke 4
    local displayGems = GameState.getGems()  -- [修复] 同上
    local gemBgLeft = gemBgCX - gemBgW * 0.5
    drawTextStroke(vg, gemBgLeft + 44, 100, NumberUtil.format(displayGems),
        33, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4)
end

--- 头像点击热区检测（与 TopBar.draw 的头像位置随 offsetY 同步）
---@param x number
---@param y number
---@param offsetY number|nil  与 draw 调用传入的 offsetY 一致
---@return boolean
--- 页面入口点击（替代底栏）
---@param x number
---@param y number
---@param offsetY number|nil 面板纵向偏移（横屏三联时与绘制一致）
---@return boolean
function TopBar.handleInput(x, y, offsetY, hidePageTabs)
    if shouldHidePageTabs(hidePageTabs) then return false end
    if BottomNav.isAllLocked() then return false end
    local oy2 = tonumber(offsetY) or 0
    local cy = PAGE_BTN_CY + oy2
    for _pi, idx in ipairs(PAGE_TAB_ORDER) do local i, tab = _pi, PAGE_TABS[idx]
        local cx = pageBtnCenterX(i)
        local halfW, halfH = PAGE_BTN_W * 0.5, PAGE_BTN_H * 0.5
        if x >= cx - halfW and x <= cx + halfW
           and y >= cy - halfH and y <= cy + halfH then
            if BottomNav.isTabLocked(tab.index) then
                print("[TopBar] tab locked: " .. tab.name)
                return true
            end
            if BottomNav.getSelectedIndex() ~= tab.index then
                BottomNav.setSelectedIndex(tab.index)
                local GameSFX = require("systems.GameSFX")
                GameSFX.playUIMove(2)
            end
            return true
        end
    end
    return false
end

--- 引导热点矩形（供外部查询）
---@param key string
---@return number|nil cx
---@return number|nil cy
---@return number|nil w
---@return number|nil h
function TopBar.getPageTabHotspot(key)
    local i = PAGE_HOTSPOT_KEYS[key]
    if not i then return nil end
    return pageBtnCenterX(i), PAGE_BTN_CY, PAGE_BTN_W, PAGE_BTN_H
end

function TopBar.hitTestAvatar(x, y, offsetY)
    local oy = tonumber(offsetY) or 0
    return x >= 98 - 75 and x <= 98 + 75
       and y >= (136 + oy) - 75 and y <= (136 + oy) + 75
end

return TopBar
