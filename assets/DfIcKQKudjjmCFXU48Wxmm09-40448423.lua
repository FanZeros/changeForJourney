-- ============================================================================
-- TopBar - 顶部信息栏渲染（14 个元素，NanoVG 绘制）
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local GameState      = require("core.GameState")
local NumberUtil     = require("core.NumberUtil")
local CharacterPanel = require("ui.CharacterPanel")
local HeroAssetUtil   = require("config.HeroAssetUtil")
local AvatarFrameUtil = require("config.AvatarFrameUtil")
local HeroConfig     = require("config.HeroConfig")
local DarkIcon       = require("core.DarkIcon")  -- [暗黑化 P0] 矢量图标库

local TopBar = {}

-- Image handles
local imgExpBg   = -1
local imgExpFill = -1
local imgFrameIcons = {}  -- [frameId] 头像框
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
local cachedAvatarFrameId = 1 ---@type number 当前头像框 ID
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

local trainingDummyVisible = false

local DUMMY_BTN = {
    CX = 98, CY = 286, W = 166, H = 58,
}

-- ============================================================================
-- Public API
-- ============================================================================

--- 初始化（加载图片资源，仅调用一次）
function TopBar.init(vg)
    imgExpBg   = nvgCreateImage(vg, "image/UI_JYT_1.png", 0)
    imgExpFill = nvgCreateImage(vg, "image/UI_JYT_2.png", 0)
    AvatarFrameUtil.preloadFrames(vg, imgFrameIcons)

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

--- 设置头像框 ID（由 PlayerInfoPanel 更换头像框时调用）
---@param frameId number
function TopBar.setAvatarFrameId(frameId)
    cachedAvatarFrameId = frameId or 1
end

--- 获取当前头像框 ID
---@return number
function TopBar.getAvatarFrameId()
    return cachedAvatarFrameId
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
    if data.avatarFrameId ~= nil then
        cachedAvatarFrameId = data.avatarFrameId
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
    cachedAvatarFrameId = 1
    lastSeenOwnedCount = nil
    print("[TopBar] session data reset")
end

--- 每帧绘制（在设计空间 1080x2400 内调用）
function TopBar.draw(vg)
    -- #1 头像背景框: center(239,139), 382x136, black 70%, r=36
    drawRoundedRectCentered(vg, 239, 139, 382, 136, 36, 0, 0, 0, 178)

    -- #2 玩家头像: center(98,136), 150x150（裁剪为圆角矩形）
    -- 始终先画灰色底作为底层背景
    drawRoundedRectCentered(vg, 98, 136, 150, 150, 20, 80, 80, 100, 255)
    local avatarImg = imgHeroIcons[cachedAvatarHeroId] or imgHeroIcons[1]
    if avatarImg and avatarImg >= 0 then
        -- 用圆角裁剪绘制头像（覆盖在灰色底上）
        local avCX, avCY, avW, avH = 98, 136, 150, 150
        nvgSave(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, avCX - avW * 0.5, avCY - avH * 0.5, avW, avH, 20)
        local paint = nvgImagePattern(vg, avCX - avW * 0.5, avCY - avH * 0.5, avW, avH, 0, avatarImg, 1.0)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- #2b 头像框覆盖层（新头像框素材画布为 300×300，显示尺寸 160×160）
    local frameImg = AvatarFrameUtil.getIconHandle(imgFrameIcons, cachedAvatarFrameId)
    drawImageCentered(vg, frameImg, 98, 136, 160, 160)

    -- #2c 红点提示（有可更换头像时显示）[暗黑化 P0: 余烬光点]
    if TopBar.hasAvailableAvatar() then
        DarkIcon.draw(vg, "reddot", 160, 74, 74, 1)
    end

    -- #2d 测试木桩入口：仅作为战斗页快捷入口，由 ClientInput 控制点击范围
    if trainingDummyVisible then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, DUMMY_BTN.CX - DUMMY_BTN.W * 0.5, DUMMY_BTN.CY - DUMMY_BTN.H * 0.5,
            DUMMY_BTN.W, DUMMY_BTN.H, 18)
        nvgFillColor(vg, nvgRGBA(0x3c, 0x2a, 0x1f, 210))
        nvgFill(vg)
        nvgStrokeWidth(vg, 3)
        nvgStrokeColor(vg, nvgRGBA(0xff, 0xd2, 0x73, 220))
        nvgStroke(vg)
        drawTextStroke(vg, DUMMY_BTN.CX, DUMMY_BTN.CY, "测试木桩", 28,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 235, 170, 3,
            { strokeColor = { 0x3a, 0x21, 0x12 } })
    end

    -- #3 等级背景框: center(98,200), 66x38, black, r=14
    drawRoundedRectCentered(vg, 98, 200, 66, 38, 14, 0, 0, 0, 255)

    -- #4 等级文本: center(98,200), font 30, white
    local displayLevel = cachedLevel or GameState.getLevel()
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, 98, 200, tostring(displayLevel), nil)

    -- #5 经验条背景: UI_JYT_1.png, center(290,138), 206x24
    local expCX, expCY = 290, 138
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

    -- #7 玩家名称: left=187, Y=103, font 30, white, stroke 4
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
    drawTextStroke(vg, 187, 103, displayName,
        nameFontSize, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4)

    -- #8 战力图标 + 数值: icon center(197,175) 36x36, text left=220, Y=175 [暗黑化 P0: 余烬火焰]
    local displayPower = GameState.getPower()
    DarkIcon.draw(vg, "power", 197, 175, 36, 1)
    drawTextStroke(vg, 220, 175, tostring(displayPower),
        30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        247, 254, 119, 4)

    -- #9 金币背景: center(732,100), 170x47, r=18, black 80%
    local goldBgCX, goldBgCY = 732, 100
    local goldBgW, goldBgH = 170, 47
    drawRoundedRectCentered(vg, goldBgCX, goldBgCY, goldBgW, goldBgH, 18, 0, 0, 0, 204)

    -- #10 金币图标: center(653,100), 73x73 [暗黑化 P0: 暗金做旧币]
    DarkIcon.draw(vg, "gold", 653, 100, 73, 1)

    -- #11 金币数值: left=goldBgLeft+44, Y=100, font 33, white, stroke 4
    local displayGold = cachedGold or GameState.getGold()
    local goldBgLeft = goldBgCX - goldBgW * 0.5
    drawTextStroke(vg, goldBgLeft + 44, 100, NumberUtil.format(displayGold),
        33, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4)

    -- #12 钻石背景: center(965,100), 170x47, r=18, black 80%
    local gemBgCX, gemBgCY = 965, 100
    local gemBgW, gemBgH = 170, 47
    drawRoundedRectCentered(vg, gemBgCX, gemBgCY, gemBgW, gemBgH, 18, 0, 0, 0, 204)

    -- #13 钻石图标: center(884,100), 76x76 [暗黑化 P0: 血红宝石]
    DarkIcon.draw(vg, "gem", 884, 100, 76, 1)

    -- #14 钻石数值: left=diamondBgLeft+44, Y=100, font 33, white, stroke 4
    local displayGems = cachedGems or GameState.getGems()
    local gemBgLeft = gemBgCX - gemBgW * 0.5
    drawTextStroke(vg, gemBgLeft + 44, 100, NumberUtil.format(displayGems),
        33, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4)
end

--- 设置测试木桩入口是否显示
---@param visible boolean
function TopBar.setTrainingDummyVisible(visible)
    trainingDummyVisible = visible == true
end

--- 测试木桩入口命中检测
---@param x number
---@param y number
---@return boolean
function TopBar.hitTestTrainingDummy(x, y)
    if not trainingDummyVisible then return false end
    return x >= DUMMY_BTN.CX - DUMMY_BTN.W * 0.5 and x <= DUMMY_BTN.CX + DUMMY_BTN.W * 0.5
       and y >= DUMMY_BTN.CY - DUMMY_BTN.H * 0.5 and y <= DUMMY_BTN.CY + DUMMY_BTN.H * 0.5
end

return TopBar
