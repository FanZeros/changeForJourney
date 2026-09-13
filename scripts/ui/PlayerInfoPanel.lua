-- ============================================================================
-- PlayerInfoPanel - 玩家信息弹窗（完整版：上半部分 + 下半部分）
-- 点击主界面左上角头像打开，全屏遮罩 + 九宫格弹窗
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local GameState      = require("core.GameState")
local DrawUtil       = require("core.DrawUtil")
local StageConfig    = require("config.StageConfig")
local PlayerStore    = require("client.data.PlayerStore")
local ArenaConfig    = require("config.ArenaConfig")
local CharacterPanel    = require("ui.CharacterPanel")
local HeroConfig        = require("config.HeroConfig")
local HeroAssetUtil     = require("config.HeroAssetUtil")
local AvatarFrameUtil   = require("config.AvatarFrameUtil")
local AvatarSelectPanel = require("ui.AvatarSelectPanel")
local SettingsPanel     = require("ui.SettingsPanel")
local GMConsolePanel    = require("ui.GMConsolePanel")
local TopBar            = require("ui.TopBar")

local BF                 = require("systems.ButtonFeedback")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格
local drawTextStroke     = DrawUtil.drawTextStroke
local drawImageCentered  = DrawUtil.drawImageCentered
local drawNineSlice      = DrawUtil.drawNineSlice
local hitTest            = DrawUtil.hitTest

local PlayerInfoPanel = {}

-- ======================== 状态 ========================

local state = {
    open       = false,
    animTime   = 0,       -- 打开动画时间戳
    closing    = false,
    closeTime  = 0,
    cardScrollY = 0,      -- 卡片区域滚动偏移（>0 表示内容上移）
    avatarHeroId  = 1,     -- 当前头像使用的英雄 ID
    avatarFrameId = 1,     -- 当前头像框 ID
    -- UID 复制提示
    toastText  = nil,     ---@type string|nil  提示文字（非 nil 时显示）
    toastTimer = 0,       -- 提示显示剩余时间
}

-- ======================== 图片资源句柄 ========================

local img = {
    bg       = -1,  -- UI_TY_EJQRK.png  弹窗九宫格背景
    avatar   = -1,  -- 角色头像
    frameIcons = {},  -- [frameId] 头像框
    power    = -1,  -- ICON_ZDL.png 战力图标
    expBg    = -1,  -- UI_WJXX_JDT.png  经验进度条背景
    expFill  = -1,  -- UI_WJXX_JDT1.png 经验进度条填充
    -- 下半部分
    tierBadge  = {},  -- [1~8] 段位徽章 ICON_DW_1~8.png
    heroCards  = {},  -- [heroId] 角色卡牌 KP_YX_*.png
    heroIcons  = {},  -- [heroId] 角色头像图标 UI_icon_hero_*.png
    classIcons = {},  -- [1~6] 职业图标 ICON_ZY_1~6.png
    lvlBadge   = -1,  -- UI_JSJM_DJ.png 等级徽章
    expBarBgS  = -1,  -- UI_JSMB_JYT1.png 卡片经验条背景
    expBarFillS= -1,  -- UI_JSMB_JYT2.png 卡片经验条填充
    settingBtn = -1,  -- UI_AN_SZ.png 设置按钮
    redDot     = -1,  -- ICON_HD.png 红点提示
}

-- ======================== 布局常量 ========================

-- 遮罩
local MASK_ALPHA = 128  -- 50%

-- 弹窗背景（九宫格）
local BG = {
    CX = 540, CY = 1067, W = 950, H = 1747,
    IT = 180, IL = 40, IR = 40, IB = 50,
}

-- 标题
local TTL = {
    X = 540, Y = 261, FONT = 60,
    FR = 255, FG = 255, FB = 255,   -- 纯白
    SW = 6, SR = 0x59, SG = 0x32, SB = 0x19,  -- 描边 593219
}

-- 玩家简要信息区域背景
local INFO_BG = {
    CX = 540, CY = 499, W = 800, H = 216, R = 16,
    A = 13,  -- 纯黑 5% 不透明度 → 255*0.05≈13
}

-- 玩家头像
local AVATAR = {
    CX = 245, CY = 499, W = 160, H = 160,
}

-- 玩家头像框
local FRAME = {
    CX = 245, CY = 499, W = 160, H = 160,
}

-- 玩家名称
local NAME = {
    X = 355, Y = 432, FONT = 38,
    R = 0x50, G = 0x2c, B = 0x15,  -- 502c15
}

-- 装饰线1
local DECO1 = {
    CX = 610, CY = 463, W = 512, H = 6, R = 3,
    CR = 0x8d, CG = 0x5f, CB = 0x41,  -- 8d5f41
    A = 51,  -- 20% → 255*0.2≈51
}

-- 玩家UID
local UID = {
    X = 355, Y = 492, FONT = 38,
    R = 0x50, G = 0x2c, B = 0x15,
}

-- UID 点击区域（用于复制 UID）
local UID_HIT = {
    CX = 540, CY = 492, W = 400, H = 50,
}

-- 复制提示 Toast
local TOAST = {
    DURATION = 1.5,  -- 显示时长（秒）
    FONT = 32,
    R = 16, -- 圆角
}

-- 装饰线2
local DECO2 = {
    CX = 610, CY = 521, W = 512, H = 6, R = 3,
    CR = 0x8d, CG = 0x5f, CB = 0x41,
    A = 51,
}

-- 战力背景框
local PWR_BG = {
    CX = 453, CY = 559, W = 200, H = 50, R = 17,
    CR = 0x64, CG = 0x35, CB = 0x16,  -- 643516
    A = 128,  -- 50%
}

-- 战力图标+文本
local PWR = {
    ICON_W = 44, ICON_H = 44,
    FONT = 30,
    FR = 0xf7, FG = 0xfe, FB = 0x77,  -- f7fe77
    SW = 4, SR = 0x23, SG = 0x23, SB = 0x23,  -- 232323
}

-- 关卡进度背景框
local STG_BG = {
    CX = 668, CY = 559, W = 200, H = 50, R = 17,
    CR = 0x64, CG = 0x35, CB = 0x16,
    A = 128,
}

-- 关卡进度文本
local STG = {
    FONT = 30,
    FR = 0xf7, FG = 0xfe, FB = 0x77,
    SW = 4, SR = 0x23, SG = 0x23, SB = 0x23,
}

-- 冒险等级文本
local ADV_LV = {
    X = 143, Y = 655, FONT = 38,
    FR = 255, FG = 255, FB = 255,
    SW = 5, SR = 0, SG = 0, SB = 0,
}

-- 冒险等级经验数值
local ADV_EXP = {
    X = 940, Y = 656, FONT = 38,
    FR = 255, FG = 255, FB = 255,
    SW = 5, SR = 0, SG = 0, SB = 0,
}

-- 经验进度条背景
local EXP_BAR = {
    CX = 540, CY = 699, W = 804, H = 30,
    PAD = 6,  -- 内间距
}

-- ── 下半部分：竞技场信息 ──

-- 竞技场信息背景框
local ARENA_BG = {
    CX = 540, CY = 833, W = 800, H = 174, R = 16,
    A = 13,  -- 纯黑 5%
}

-- "竞技场排位" 标题文本
local ARENA_TITLE = {
    X = 303, Y = 804, FONT = 48,
    R = 0x50, G = 0x2c, B = 0x15,
}

-- 段位分数值
local RANK_SCORE = {
    X = 305, Y = 866, FONT = 38,
    FR = 255, FG = 255, FB = 255,
    SW = 5, SR = 0, SG = 0, SB = 0,
}

-- 段位徽章图片
local RANK_BADGE = {
    CX = 792, CY = 840, W = 232, H = 232,
}

-- 段位名称文本
local RANK_NAME = {
    X = 794, Y = 904, FONT = 50,
    FR = 255, FG = 255, FB = 255,
    SW = 5, SR = 0, SG = 0, SB = 0,
}

-- ── 下半部分：队伍配置 ──

-- 队伍配置背景框
local TEAM_BG = {
    CX = 540, CY = 1333, W = 800, H = 740, R = 16,
    A = 13,  -- 纯黑 5%
}

-- "队伍配置" 标题文本
local TEAM_TITLE = {
    X = 540, Y = 967, FONT = 38,
    FR = 255, FG = 255, FB = 255,
    SW = 5, SR = 0, SG = 0, SB = 0,
}

-- 队伍卡片布局（与 CharacterPanelDraw 完全一致的卡片尺寸）
local TEAM_CARDS = {
    FIRST_ROW_CY = 1270,  -- 第一行卡片 Y 中心（下移40px）
    MAX_PER_ROW  = 3,     -- 每行最多 3 张
    CARD_W       = 198,   -- 与 CharacterPanelDraw 一致
    CARD_H       = 438,   -- 与 CharacterPanelDraw 一致
    SPACING      = 7,     -- 与 CharacterPanelDraw 一致
    ROW_SPACING  = 543,   -- 与 CharacterPanelDraw 一致
    CLIP_TOP     = 993,   -- 裁剪区域上边
    CLIP_BOTTOM  = 1703,  -- 裁剪区域下边（背景框下边）
}

-- 卡片子元素常量（直接复用 CharacterPanelDraw 原始值，不缩放）
local CARD_TAG_OFFSET_Y   = -215   -- 职业图标 Y 偏移
local CARD_TAG_SIZE       = 60     -- 职业图标尺寸
local CARD_POWER_Y_OFFSET = 680 - 544  -- 战斗力 Y 相对卡片中心偏移 (POWER_Y - CARD_CY = 136)
local CARD_POWER_ICON_SIZE = 36
local CARD_LVL_BADGE_SIZE = 56
local CARD_LVL_BADGE_DX   = -63   -- 等级徽章 X 偏移
local CARD_LVL_BADGE_DY   = 181   -- 等级徽章 Y 偏移
local CARD_EXP_BAR_DX     = 12    -- 经验条 X 偏移
local CARD_EXP_BAR_DY     = 183   -- 经验条 Y 偏移
local CARD_EXP_BAR_BG_W   = 148
local CARD_EXP_BAR_BG_H   = 28
local CARD_EXP_BAR_PADDING = 4
local CARD_EXP_FILL_LEFT_INSET = 15
local CARD_NAME_BG_DY     = 253   -- 角色名 Y 偏移
local CARD_NAME_BG_W      = 193
local CARD_NAME_BG_H      = 48
local CARD_NAME_BG_RADIUS = 24

-- 职业图标映射
local CLASS_ICON_MAP = {
    knight   = 1,
    warrior  = 2,
    mage     = 3,
    ranger   = 4,
    assassin = 5,
    priest   = 6,
}

-- ── 下半部分：设置按钮 ──

local SETTING_BTN = {
    CX = 540, CY = 1801, W = 130, H = 143,
}

local SETTING_TXT = {
    X = 540, Y = 1861, FONT = 38,
    FR = 255, FG = 255, FB = 255,
    SW = 5, SR = 0, SG = 0, SB = 0,
}

-- GM 控制台入口按钮（设置按钮右侧）
local GM_BTN = {
    CX = 700, CY = 1801, W = 130, H = 143,
}
local GM_TXT = {
    X = 700, Y = 1861, FONT = 34,
    FR = 255, FG = 200, FB = 50,
    SW = 5, SR = 0, SG = 0, SB = 0,
}

-- 动画参数
local ANIM_OPEN_DUR  = 0.25
local ANIM_CLOSE_DUR = 0.15

-- ======================== 缓存数据 ========================

local cachedUID        = nil  ---@type string|nil
local cachedName       = nil  ---@type string|nil
local cachedServerName = nil  ---@type string|nil  当前区服名称
local cachedServerId = nil    ---@type number|nil    当前区服 id

--- 判断当前玩家是否为 GM（完全由服务端鉴权，客户端无白名单）
local function isGM()
    local Client = require("network.Client")
    return Client.isGM()
end

-- ============================================================================
-- Public API
-- ============================================================================

--- 初始化（加载图片资源，仅调用一次）
function PlayerInfoPanel.init(vg)
    -- 上半部分
    img.bg      = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    img.avatar  = nvgCreateImage(vg, "image/角色图标/UI_icon_hero_1.png", 0)
    AvatarFrameUtil.preloadFrames(vg, img.frameIcons)
    img.power   = nvgCreateImage(vg, "image/ICON_ZDL.png", 0)
    img.expBg   = nvgCreateImage(vg, "image/UI_WJXX_JDT.png", 0)
    img.expFill = nvgCreateImage(vg, "image/UI_WJXX_JDT1.png", 0)

    -- 下半部分：段位徽章 (1~8)
    for i = 1, 8 do
        img.tierBadge[i] = nvgCreateImage(vg, "image/ICON_DW_" .. i .. ".png", 0)
    end

    -- 下半部分：角色卡牌
    HeroAssetUtil.preloadCards(vg, img.heroCards)

    -- 角色头像图标（供更换头像面板使用）
    HeroAssetUtil.preloadIcons(vg, img.heroIcons)

    -- 下半部分：职业图标 (1~6)
    for i = 1, 6 do
        img.classIcons[i] = nvgCreateImage(vg, "image/ICON_ZY_" .. i .. ".png", 0)
    end

    -- 下半部分：卡片子元素
    img.lvlBadge    = nvgCreateImage(vg, "image/UI_JSJM_DJ.png", 0)
    img.expBarBgS   = nvgCreateImage(vg, "image/UI_JSMB_JYT1.png", 0)
    img.expBarFillS = nvgCreateImage(vg, "image/UI_JSMB_JYT2.png", 0)

    -- 下半部分：设置按钮
    img.settingBtn = nvgCreateImage(vg, "image/UI_AN_SZ.png", 0)

    -- 红点提示图标
    img.redDot = nvgCreateImage(vg, "image/ICON_HD.png", 0)

    if img.bg < 0 then print("[PlayerInfoPanel] WARN: UI_TY_EJQRK.png load failed") end
    if img.power < 0 then print("[PlayerInfoPanel] WARN: ICON_ZDL.png load failed") end
    if img.settingBtn < 0 then print("[PlayerInfoPanel] WARN: UI_AN_SZ.png load failed") end

    -- 初始化更换头像面板
    AvatarSelectPanel.init(vg)

    -- 初始化设置面板
    SettingsPanel.init(vg)

    -- 初始化 GM 控制台面板
    GMConsolePanel.init(vg)

    print("[PlayerInfoPanel] init OK")
end

--- 设置玩家UID（由外部 lobby:GetMyUserId() 获取后传入）
---@param uid string|number
function PlayerInfoPanel.setUID(uid)
    local prev = cachedUID
    cachedUID = tostring(uid or "")
    print(string.format("[PlayerInfoPanel] setUID: %s → %s", tostring(prev), tostring(cachedUID)))
end

--- [DIAG] 获取当前缓存的 UID（用于诊断）
---@return string|nil
function PlayerInfoPanel.getUID()
    return cachedUID
end

--- 设置玩家名称缓存（与 TopBar 同源）
---@param name string
function PlayerInfoPanel.setPlayerName(name)
    cachedName = name
end

--- 设置当前区服名称
---@param name string
function PlayerInfoPanel.setServerName(name)
    cachedServerName = name
end

--- 设置当前区服 id
---@param serverId number|string|nil
function PlayerInfoPanel.setServerId(serverId)
    cachedServerId = tonumber(serverId)
end

--- 获取当前区服 id
---@return number|nil
function PlayerInfoPanel.getServerId()
    return cachedServerId
end

--- 打开面板
function PlayerInfoPanel.open()
    if state.open then return end
    state.open = true
    state.closing = false
    state.animTime = time.elapsedTime
    state.cardScrollY = 0
    print("[PlayerInfoPanel] 打开")
end

--- 关闭面板（带动画）
function PlayerInfoPanel.close()
    if not state.open or state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    print("[PlayerInfoPanel] 关闭（动画中）")
end

--- 是否打开
function PlayerInfoPanel.isOpen()
    return state.open
end

--- 点击处理（返回 true 表示消费了事件）
function PlayerInfoPanel.handleInput(dx, dy)
    if not state.open then return false end
    if state.closing then return true end

    -- GMConsolePanel 优先拦截（最顶层）
    if GMConsolePanel.isOpen() then
        GMConsolePanel.handleInput(dx, dy)
        return true
    end

    -- SettingsPanel 优先拦截
    if SettingsPanel.isOpen() then
        SettingsPanel.handleInput(dx, dy)
        return true
    end

    -- AvatarSelectPanel 优先拦截
    if AvatarSelectPanel.isOpen() then
        AvatarSelectPanel.handleInput(dx, dy)
        return true
    end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.animTime < 0.05 then return true end

    -- 点击弹窗外部 → 关闭
    if not hitTest(dx, dy, BG.CX, BG.CY, BG.W, BG.H) then
        PlayerInfoPanel.close()
        return true
    end

    -- UID 点击 → 复制到剪贴板
    if hitTest(dx, dy, UID_HIT.CX, UID_HIT.CY, UID_HIT.W, UID_HIT.H) then
        local uidStr = cachedUID or ""
        if #uidStr > 0 then
            ui.useSystemClipboard = true
            ui:SetClipboardText(uidStr)
            state.toastText = "UID 已复制"
            state.toastTimer = TOAST.DURATION
            print("[PlayerInfoPanel] UID 已复制: " .. uidStr)
        end
        return true
    end

    -- 头像点击 → 打开更换头像面板
    if hitTest(dx, dy, AVATAR.CX, AVATAR.CY, AVATAR.W, AVATAR.H) then
        BF.trigger("pip_avatar")
        TopBar.markAvatarViewed()  -- 消除头像红点
        AvatarSelectPanel.open({
            avatarHeroId = state.avatarHeroId or 1,
            avatarFrameId = state.avatarFrameId or 1,
            onAvatarConfirmed = function(heroId)
                state.avatarHeroId = heroId
                local heroIcon = img.heroIcons[heroId]
                if heroIcon and heroIcon >= 0 then
                    img.avatar = heroIcon
                end
                TopBar.setAvatarHeroId(heroId)
                local Client = require("network.Client")
                local Protocol = require("shared.Protocol")
                Client.sendAction(Protocol.ACTION_TYPES.SET_AVATAR, { avatarHeroId = heroId })
                print("[PlayerInfoPanel] 头像更换为 hero_" .. heroId .. " (已同步服务器)")
            end,
            onFrameConfirmed = function(frameId)
                state.avatarFrameId = frameId
                TopBar.setAvatarFrameId(frameId)
                local Client = require("network.Client")
                local Protocol = require("shared.Protocol")
                Client.sendAction(Protocol.ACTION_TYPES.SET_AVATAR_FRAME, { avatarFrameId = frameId })
                print("[PlayerInfoPanel] 头像框更换为 frame_" .. frameId .. " (已同步服务器)")
            end,
        })
        return true
    end

    -- 设置按钮点击检测
    if hitTest(dx, dy, SETTING_BTN.CX, SETTING_BTN.CY, SETTING_BTN.W, SETTING_BTN.H) then
        BF.trigger("pip_setting")
        print("[PlayerInfoPanel] 设置按钮被点击 → 打开设置面板")
        SettingsPanel.open()
        return true
    end

    -- GM 控制台按钮点击检测（仅白名单玩家可见可点）
    if isGM() and hitTest(dx, dy, GM_BTN.CX, GM_BTN.CY, GM_BTN.W, GM_BTN.H) then
        BF.trigger("pip_gm")
        print("[PlayerInfoPanel] GM 按钮被点击 → 打开 GM 控制台")
        GMConsolePanel.open()
        return true
    end

    -- 弹窗内部点击消费事件防穿透
    return true
end

--- 拖拽开始（转发给子面板）
function PlayerInfoPanel.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    if GMConsolePanel.isOpen() then
        return GMConsolePanel.handleDragBegin and GMConsolePanel.handleDragBegin(dx, dy) or true
    end
    if SettingsPanel.isOpen() then
        return SettingsPanel.handleDragBegin(dx, dy)
    end
    if AvatarSelectPanel.isOpen() then
        return AvatarSelectPanel.handleDragBegin(dx, dy)
    end
    return false
end

--- 拖拽移动（转发给子面板）
function PlayerInfoPanel.handleDragMove(dx, dy)
    if not state.open or state.closing then return false end
    if GMConsolePanel.isOpen() then
        return GMConsolePanel.handleDragMove and GMConsolePanel.handleDragMove(dx, dy) or true
    end
    if SettingsPanel.isOpen() then
        return SettingsPanel.handleDragMove(dx, dy)
    end
    if AvatarSelectPanel.isOpen() then
        return AvatarSelectPanel.handleDragMove(dx, dy)
    end
    return false
end

--- 拖拽结束（转发给子面板）
function PlayerInfoPanel.handleDragEnd(dx, dy)
    if not state.open or state.closing then return false end
    if GMConsolePanel.isOpen() then
        if GMConsolePanel.handleDragEnd then GMConsolePanel.handleDragEnd(dx, dy) end
        return true
    end
    if SettingsPanel.isOpen() then
        return SettingsPanel.handleDragEnd()
    end
    if AvatarSelectPanel.isOpen() then
        AvatarSelectPanel.handleDragEnd()
        return true
    end
    return false
end

--- 滚动处理（卡片区域滚动）
---@param wheel number 滚轮值（正=向上滚）
function PlayerInfoPanel.handleScroll(wheel)
    if not state.open or state.closing then return false end
    -- SettingsPanel 不需要滚轮，但打开时消费事件
    if SettingsPanel.isOpen() then return true end
    -- AvatarSelectPanel 优先拦截滚轮
    if AvatarSelectPanel.isOpen() then
        return AvatarSelectPanel.handleWheel(wheel)
    end
    -- 计算最大滚动量
    local teamSlots = CharacterPanel.getTeamSlotsData()
    local occupiedCount = 0
    for i = 1, 5 do
        if teamSlots[i] and teamSlots[i].state == "occupied" then
            occupiedCount = occupiedCount + 1
        end
    end
    local rows = math.ceil(occupiedCount / TEAM_CARDS.MAX_PER_ROW)
    local contentH = rows * TEAM_CARDS.ROW_SPACING  -- 与 CharacterPanelDraw 一致的行间距
    local clipH = TEAM_CARDS.CLIP_BOTTOM - TEAM_CARDS.CLIP_TOP
    local maxScroll = math.max(0, contentH - clipH)

    state.cardScrollY = state.cardScrollY - wheel * 40
    state.cardScrollY = math.max(0, math.min(maxScroll, state.cardScrollY))
    return true
end

-- ======================== 辅助绘制 ========================

--- 获取关卡进度文本（如 "地狱12-3"）
local function getStageProgressText()
    local battleData = PlayerStore.Get("battle")
    local stageId = battleData and (battleData.maxStageId or battleData.currentStageId)
    if not stageId or stageId == 0 then
        local okBattle, BattleScene = pcall(require, "ui.BattleScene")
        if okBattle and BattleScene and BattleScene.getCurrentStageId then
            stageId = BattleScene.getCurrentStageId()
        end
    end
    return StageConfig.formatProgressDisplay(stageId)
end

--- 绘制单张卡片（与 CharacterPanelDraw 完全一致的尺寸和层级）
---@param vg any NanoVG context
---@param cx number 卡片中心 X
---@param cy number 卡片中心 Y
---@param slot table 槽位数据 { heroId, level, exp, maxExp }
---@param power number 该槽位的战斗力
local function drawTeamCard(vg, cx, cy, slot, power)
    local heroId = slot.heroId
    local heroCfg = HeroConfig.get(heroId)
    if not heroCfg then return end

    local cw = TEAM_CARDS.CARD_W
    local ch = TEAM_CARDS.CARD_H

    -- a) 角色卡片背景
    local cardImg = img.heroCards[heroId] or img.heroCards[1]
    if cardImg and cardImg >= 0 then
        drawImageCentered(vg, cardImg, cx, cy, cw, ch, 1.0)
    end

    -- b) 职业图标
    local iconIdx = CLASS_ICON_MAP[heroCfg.classId]
    if iconIdx and img.classIcons[iconIdx] and img.classIcons[iconIdx] >= 0 then
        drawImageCentered(vg, img.classIcons[iconIdx], cx, cy + CARD_TAG_OFFSET_Y, CARD_TAG_SIZE, CARD_TAG_SIZE, 1.0)
    end

    -- c) 战斗力图标 + 数值
    local powerStr = tostring(power or 0)
    local POWER_GAP = 4
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    local textW = nvgTextBounds(vg, 0, 0, powerStr)
    local comboW = CARD_POWER_ICON_SIZE + POWER_GAP + textW
    local comboStartX = cx - comboW * 0.5
    local powerCY = cy + CARD_POWER_Y_OFFSET
    drawImageCentered(vg, img.power, comboStartX + CARD_POWER_ICON_SIZE * 0.5, powerCY,
        CARD_POWER_ICON_SIZE, CARD_POWER_ICON_SIZE, 1.0)
    drawTextStroke(vg, comboStartX + CARD_POWER_ICON_SIZE + POWER_GAP, powerCY, powerStr,
        30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        247, 254, 119, 4)

    -- d) 经验进度条
    if img.expBarBgS >= 0 then
        local expBarCX = cx + CARD_EXP_BAR_DX
        local expBarCY = cy + CARD_EXP_BAR_DY
        drawImageCentered(vg, img.expBarBgS, expBarCX, expBarCY, CARD_EXP_BAR_BG_W, CARD_EXP_BAR_BG_H, 1.0)

        local expProgress = (slot.maxExp and slot.maxExp > 0)
            and math.min(1, (slot.exp or 0) / slot.maxExp) or 0
        if expProgress > 0 and img.expBarFillS >= 0 then
            local fillW = CARD_EXP_BAR_BG_W - CARD_EXP_BAR_PADDING * 2 - CARD_EXP_FILL_LEFT_INSET
            local fillH = CARD_EXP_BAR_BG_H - CARD_EXP_BAR_PADDING * 2
            local fillX = expBarCX - CARD_EXP_BAR_BG_W * 0.5 + CARD_EXP_BAR_PADDING + CARD_EXP_FILL_LEFT_INSET
            local fillY = expBarCY - CARD_EXP_BAR_BG_H * 0.5 + CARD_EXP_BAR_PADDING
            local clipW = fillW * expProgress
            nvgSave(vg)
            nvgScissor(vg, fillX, fillY, clipW, fillH)
            local paint = nvgImagePattern(vg, fillX, fillY, fillW, fillH, 0, img.expBarFillS, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, fillX, fillY, fillW, fillH)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
            nvgRestore(vg)  -- nvgRestore 自动还原外层 scissor，不需要 nvgResetScissor
        end
    end

    -- e) 等级徽章
    if img.lvlBadge >= 0 then
        local badgeCX = cx + CARD_LVL_BADGE_DX
        local badgeCY = cy + CARD_LVL_BADGE_DY
        drawImageCentered(vg, img.lvlBadge, badgeCX, badgeCY, CARD_LVL_BADGE_SIZE, CARD_LVL_BADGE_SIZE, 1.0)
        drawTextStroke(vg, badgeCX, badgeCY, tostring(slot.level or 1),
            28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)
    end

    -- f) 角色名背景 + 文字
    local nameBgCY = cy + CARD_NAME_BG_DY
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - CARD_NAME_BG_W * 0.5, nameBgCY - CARD_NAME_BG_H * 0.5,
        CARD_NAME_BG_W, CARD_NAME_BG_H, CARD_NAME_BG_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)
    drawTextStroke(vg, cx, nameBgCY, heroCfg.name,
        28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4)
end

--- 每帧更新（转发给 SettingsPanel → RedeemCodePanel 处理键盘输入）
function PlayerInfoPanel.update(dt)
    if not state.open then return end
    -- Toast 倒计时
    if state.toastTimer > 0 then
        state.toastTimer = state.toastTimer - dt
        if state.toastTimer <= 0 then
            state.toastText = nil
            state.toastTimer = 0
        end
    end
    SettingsPanel.update(dt)
end

-- ============================================================================
-- Draw
-- ============================================================================

function PlayerInfoPanel.draw(vg)
    if not state.open then return end

    -- 动画进度
    local animProgress = 1.0
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        animProgress = 1.0 - math.min(elapsed / ANIM_CLOSE_DUR, 1.0)
        if animProgress <= 0 then
            state.open = false
            state.closing = false
            return
        end
    else
        local elapsed = time.elapsedTime - state.animTime
        animProgress = math.min(elapsed / ANIM_OPEN_DUR, 1.0)
        -- easeOutBack 弹性效果
        animProgress = DrawUtil.easeOutBack(animProgress)
    end

    nvgSave(vg)

    -- ── 1. 全屏黑色遮罩 50% ──
    local maskAlpha = math.floor(MASK_ALPHA * (state.closing
        and (1.0 - math.min((time.elapsedTime - state.closeTime) / ANIM_CLOSE_DUR, 1.0))
        or math.min((time.elapsedTime - state.animTime) / ANIM_OPEN_DUR, 1.0)))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)  -- 设计分辨率全覆盖
    nvgFillColor(vg, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(vg)

    -- 弹窗缩放动画（从中心缩放）
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, animProgress, animProgress)
    nvgTranslate(vg, -BG.CX, -BG.CY)

    -- ── 2. 弹窗背景框（九宫格）──
    DarkIcon.drawNine(vg, "panel", BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5, BG.W, BG.H, { titleH = BG.IT })

    -- ── 3. 标题 "玩家信息" ──
    drawTextStroke(vg, TTL.X, TTL.Y, "玩家信息",
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        TTL.FR, TTL.FG, TTL.FB, TTL.SW,
        { strokeColor = { TTL.SR, TTL.SG, TTL.SB } })

    -- ── 4. 玩家简要信息区域背景 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        INFO_BG.CX - INFO_BG.W * 0.5, INFO_BG.CY - INFO_BG.H * 0.5,
        INFO_BG.W, INFO_BG.H, INFO_BG.R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, INFO_BG.A))
    nvgFill(vg)

    -- ── 5. 玩家头像 ──
    local _bf1 = BF.begin(vg, "pip_avatar", AVATAR.CX, AVATAR.CY, AVATAR.W, AVATAR.H)
    drawImageCentered(vg, img.avatar, AVATAR.CX, AVATAR.CY, AVATAR.W, AVATAR.H, 1.0)

    -- ── 6. 玩家头像框 ──
    local frameImg = AvatarFrameUtil.getIconHandle(img.frameIcons, state.avatarFrameId)
    drawImageCentered(vg, frameImg, FRAME.CX, FRAME.CY, FRAME.W, FRAME.H, 1.0)

    -- ── 6b. 头像红点（有新头像/新头像框时显示）──
    if img.redDot >= 0 and TopBar.hasAvailableAvatar() then
        local RD_SIZE = 50
        local RD_INSET = 10
        drawImageCentered(vg, img.redDot,
            AVATAR.CX + AVATAR.W * 0.5 - RD_INSET,
            AVATAR.CY - AVATAR.H * 0.5 + RD_INSET,
            RD_SIZE, RD_SIZE, 1.0)
    end
    BF.finish(vg, _bf1)

    -- ── 7. 玩家名称 ──
    local displayName = cachedName or GameState.getName()
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, NAME.FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(NAME.R, NAME.G, NAME.B, 255))
    nvgText(vg, NAME.X, NAME.Y, displayName, nil)

    -- ── 8. 装饰线1 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        DECO1.CX - DECO1.W * 0.5, DECO1.CY - DECO1.H * 0.5,
        DECO1.W, DECO1.H, DECO1.R)
    nvgFillColor(vg, nvgRGBA(DECO1.CR, DECO1.CG, DECO1.CB, DECO1.A))
    nvgFill(vg)

    -- ── 9. 玩家UID ──
    local displayUID = cachedUID or "---"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, UID.FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(UID.R, UID.G, UID.B, 255))
    nvgText(vg, UID.X, UID.Y, "UID: " .. displayUID, nil)

    -- ── 9.5 当前区服名称（右对齐，与装饰线右边缘对齐） ──
    if cachedServerName then
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x8d, 0x5f, 0x41, 200))
        nvgText(vg, DECO1.CX + DECO1.W * 0.5, UID.Y, cachedServerName, nil)
    end

    -- ── 10. 装饰线2 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        DECO2.CX - DECO2.W * 0.5, DECO2.CY - DECO2.H * 0.5,
        DECO2.W, DECO2.H, DECO2.R)
    nvgFillColor(vg, nvgRGBA(DECO2.CR, DECO2.CG, DECO2.CB, DECO2.A))
    nvgFill(vg)

    -- ── 11. 战力背景框 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        PWR_BG.CX - PWR_BG.W * 0.5, PWR_BG.CY - PWR_BG.H * 0.5,
        PWR_BG.W, PWR_BG.H, PWR_BG.R)
    nvgFillColor(vg, nvgRGBA(PWR_BG.CR, PWR_BG.CG, PWR_BG.CB, PWR_BG.A))
    nvgFill(vg)

    -- ── 12. 战力图标 + 战力数值（组合居中在战力背景框内）──
    local displayPower = CharacterPanel.getTotalPower()
    local powerStr = tostring(displayPower)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, PWR.FONT)
    local textW = nvgTextBounds(vg, 0, 0, powerStr)
    local iconW = PWR.ICON_W
    local gap = 4
    local totalW = iconW + gap + textW
    local startX = PWR_BG.CX - totalW * 0.5

    drawImageCentered(vg, img.power,
        startX + iconW * 0.5, PWR_BG.CY,
        iconW, PWR.ICON_H, 1.0)

    drawTextStroke(vg, startX + iconW + gap, PWR_BG.CY, powerStr,
        PWR.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        PWR.FR, PWR.FG, PWR.FB, PWR.SW,
        { strokeColor = { PWR.SR, PWR.SG, PWR.SB } })

    -- ── 13. 关卡进度背景框 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        STG_BG.CX - STG_BG.W * 0.5, STG_BG.CY - STG_BG.H * 0.5,
        STG_BG.W, STG_BG.H, STG_BG.R)
    nvgFillColor(vg, nvgRGBA(STG_BG.CR, STG_BG.CG, STG_BG.CB, STG_BG.A))
    nvgFill(vg)

    -- ── 14. 关卡进度文本 ──
    local stageText = getStageProgressText()
    drawTextStroke(vg, STG_BG.CX, STG_BG.CY, stageText,
        STG.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        STG.FR, STG.FG, STG.FB, STG.SW,
        { strokeColor = { STG.SR, STG.SG, STG.SB } })

    -- ── 15. 冒险等级文本 ──
    local advLevel = GameState.getLevel()
    drawTextStroke(vg, ADV_LV.X, ADV_LV.Y, "冒险等级LV." .. advLevel,
        ADV_LV.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        ADV_LV.FR, ADV_LV.FG, ADV_LV.FB, ADV_LV.SW,
        { strokeColor = { ADV_LV.SR, ADV_LV.SG, ADV_LV.SB } })

    -- ── 16. 冒险等级经验进度数值 ──
    local advExp    = GameState.getExp()
    local advMaxExp = GameState.getMaxExp()
    local expText = tostring(advExp) .. "/" .. tostring(advMaxExp)
    drawTextStroke(vg, ADV_EXP.X, ADV_EXP.Y, expText,
        ADV_EXP.FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        ADV_EXP.FR, ADV_EXP.FG, ADV_EXP.FB, ADV_EXP.SW,
        { strokeColor = { ADV_EXP.SR, ADV_EXP.SG, ADV_EXP.SB } })

    -- ── 17. 冒险经验进度条背景 ──
    drawImageCentered(vg, img.expBg, EXP_BAR.CX, EXP_BAR.CY, EXP_BAR.W, EXP_BAR.H, 1.0)

    -- ── 18. 冒险经验进度条填充 ──
    local progress = advMaxExp > 0 and math.min(advExp / advMaxExp, 1.0) or 0
    local pad = EXP_BAR.PAD
    local barLeft = EXP_BAR.CX - EXP_BAR.W * 0.5 + pad
    local barTop  = EXP_BAR.CY - EXP_BAR.H * 0.5 + pad
    local barW    = EXP_BAR.W - pad * 2
    local barH    = EXP_BAR.H - pad * 2
    local fillW   = barW * progress

    if fillW > 0 and img.expFill >= 0 then
        nvgSave(vg)
        nvgScissor(vg, barLeft, barTop, fillW, barH)
        local paint = nvgImagePattern(vg, barLeft, barTop, barW, barH, 0, img.expFill, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, barLeft, barTop, barW, barH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- ================================================================
    -- 下半部分
    -- ================================================================

    -- ── 19. 竞技场信息背景框 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        ARENA_BG.CX - ARENA_BG.W * 0.5, ARENA_BG.CY - ARENA_BG.H * 0.5,
        ARENA_BG.W, ARENA_BG.H, ARENA_BG.R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, ARENA_BG.A))
    nvgFill(vg)

    -- ── 20. "竞技场排位" 标题（居中对齐）──
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, ARENA_TITLE.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(ARENA_TITLE.R, ARENA_TITLE.G, ARENA_TITLE.B, 255))
    nvgText(vg, ARENA_TITLE.X, ARENA_TITLE.Y, "竞技场排位", nil)

    -- ── 21. 段位分（居中对齐）──
    local rankScore = 0
    local okArenaPage, ArenaPage = pcall(require, "ui.ArenaPage")
    if okArenaPage and ArenaPage and ArenaPage.getRankScore then
        rankScore = ArenaPage.getRankScore()
    end
    drawTextStroke(vg, RANK_SCORE.X, RANK_SCORE.Y, "段位分:" .. tostring(rankScore),
        RANK_SCORE.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        RANK_SCORE.FR, RANK_SCORE.FG, RANK_SCORE.FB, RANK_SCORE.SW,
        { strokeColor = { RANK_SCORE.SR, RANK_SCORE.SG, RANK_SCORE.SB } })

    -- ── 22. 段位徽章 ──
    local tier = ArenaConfig.getTierByScore(rankScore)
    local badgeIdx = tier and tier.icon or 1
    local badgeImg = img.tierBadge[badgeIdx]
    if badgeImg and badgeImg >= 0 then
        drawImageCentered(vg, badgeImg, RANK_BADGE.CX, RANK_BADGE.CY, RANK_BADGE.W, RANK_BADGE.H, 1.0)
    end

    -- ── 23. 段位名称 ──
    local tierDisplayName = tier and ArenaConfig.getTierDisplayName(tier) or "黑铁级 V"
    drawTextStroke(vg, RANK_NAME.X, RANK_NAME.Y, tierDisplayName,
        RANK_NAME.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        RANK_NAME.FR, RANK_NAME.FG, RANK_NAME.FB, RANK_NAME.SW,
        { strokeColor = { RANK_NAME.SR, RANK_NAME.SG, RANK_NAME.SB } })

    -- ── 24. 队伍配置背景框 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        TEAM_BG.CX - TEAM_BG.W * 0.5, TEAM_BG.CY - TEAM_BG.H * 0.5,
        TEAM_BG.W, TEAM_BG.H, TEAM_BG.R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, TEAM_BG.A))
    nvgFill(vg)

    -- ── 25. "队伍配置" 标题 ──
    drawTextStroke(vg, TEAM_TITLE.X, TEAM_TITLE.Y, "队伍配置",
        TEAM_TITLE.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        TEAM_TITLE.FR, TEAM_TITLE.FG, TEAM_TITLE.FB, TEAM_TITLE.SW,
        { strokeColor = { TEAM_TITLE.SR, TEAM_TITLE.SG, TEAM_TITLE.SB } })

    -- ── 26. 队伍卡片（带裁剪和滚动，与 CharacterPanelDraw 一致的尺寸）──
    local teamSlots, slotPowerCache = CharacterPanel.getTeamSlotsData()
    if teamSlots then
        -- 收集出战的角色槽位及其原始索引（用于获取战斗力缓存）
        local occupiedSlots = {}
        local occupiedIndices = {}
        for i = 1, 5 do
            if teamSlots[i] and teamSlots[i].state == "occupied" and teamSlots[i].heroId then
                occupiedSlots[#occupiedSlots + 1] = teamSlots[i]
                occupiedIndices[#occupiedIndices + 1] = i
            end
        end

        -- 裁剪区域
        nvgSave(vg)
        nvgScissor(vg,
            TEAM_BG.CX - TEAM_BG.W * 0.5,
            TEAM_CARDS.CLIP_TOP,
            TEAM_BG.W,
            TEAM_CARDS.CLIP_BOTTOM - TEAM_CARDS.CLIP_TOP)

        local cw = TEAM_CARDS.CARD_W
        local sp = TEAM_CARDS.SPACING
        local maxPerRow = TEAM_CARDS.MAX_PER_ROW
        local scrollOff = state.cardScrollY

        for idx, slot in ipairs(occupiedSlots) do
            local row = math.ceil(idx / maxPerRow)
            local col = ((idx - 1) % maxPerRow) + 1

            -- 计算该行卡片数量（用于水平居中）
            local rowStart = (row - 1) * maxPerRow + 1
            local rowEnd = math.min(row * maxPerRow, #occupiedSlots)
            local cardsInRow = rowEnd - rowStart + 1

            local rowTotalW = cardsInRow * cw + (cardsInRow - 1) * sp
            local rowStartX = TEAM_BG.CX - rowTotalW * 0.5

            local cx = rowStartX + (col - 1) * (cw + sp) + cw * 0.5
            local cy = TEAM_CARDS.FIRST_ROW_CY + (row - 1) * TEAM_CARDS.ROW_SPACING - scrollOff

            local slotIdx = occupiedIndices[idx]
            local power = slotPowerCache and slotPowerCache[slotIdx] or 0
            drawTeamCard(vg, cx, cy, slot, power)
        end

        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    -- ── 27. 设置按钮 ──
    local _bf2 = BF.begin(vg, "pip_setting", SETTING_BTN.CX, SETTING_BTN.CY, SETTING_BTN.W, SETTING_BTN.H)
    if img.settingBtn >= 0 then
        drawImageCentered(vg, img.settingBtn,
            SETTING_BTN.CX, SETTING_BTN.CY,
            SETTING_BTN.W, SETTING_BTN.H, 1.0)
    end

    -- ── 28. "设置" 文本 ──
    drawTextStroke(vg, SETTING_TXT.X, SETTING_TXT.Y, "设置",
        SETTING_TXT.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        SETTING_TXT.FR, SETTING_TXT.FG, SETTING_TXT.FB, SETTING_TXT.SW,
        { strokeColor = { SETTING_TXT.SR, SETTING_TXT.SG, SETTING_TXT.SB } })
    BF.finish(vg, _bf2)

    -- ── 29. GM 控制台入口按钮（仅白名单可见） ──
    if isGM() then
        local _bfGM = BF.begin(vg, "pip_gm", GM_BTN.CX, GM_BTN.CY, GM_BTN.W, GM_BTN.H)

        -- 绘制按钮背景（复用设置按钮图片）
        if img.settingBtn >= 0 then
            drawImageCentered(vg, img.settingBtn,
                GM_BTN.CX, GM_BTN.CY,
                GM_BTN.W, GM_BTN.H, 1.0)
        end

        -- GM 标识文本（金色醒目）
        drawTextStroke(vg, GM_TXT.X, GM_TXT.Y, "GM",
            GM_TXT.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            GM_TXT.FR, GM_TXT.FG, GM_TXT.FB, GM_TXT.SW,
            { strokeColor = { GM_TXT.SR, GM_TXT.SG, GM_TXT.SB } })

        BF.finish(vg, _bfGM)
    end

    -- ── Toast 提示（UID 已复制等）──
    if state.toastText and state.toastTimer > 0 then
        -- 淡入淡出：前 0.15s 淡入，最后 0.3s 淡出
        local alpha = 1.0
        local elapsed = TOAST.DURATION - state.toastTimer
        if elapsed < 0.15 then
            alpha = elapsed / 0.15
        elseif state.toastTimer < 0.3 then
            alpha = state.toastTimer / 0.3
        end
        local a = math.floor(alpha * 200)

        -- 测量文本宽度
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TOAST.FONT)
        local tw = nvgTextBounds(vg, 0, 0, state.toastText)
        local padX, padY = 24, 12
        local toastW = tw + padX * 2
        local toastH = TOAST.FONT + padY * 2
        local toastCX = 540
        local toastCY = 1500  -- 弹窗中下部

        -- 背景圆角矩形
        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            toastCX - toastW * 0.5, toastCY - toastH * 0.5,
            toastW, toastH, TOAST.R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, a))
        nvgFill(vg)

        -- 文字
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 255)))
        nvgText(vg, toastCX, toastCY, state.toastText, nil)
    end

    nvgRestore(vg)

    -- 在 PlayerInfoPanel 变换之外绘制子面板（它们有自己的遮罩和缩放）
    AvatarSelectPanel.draw(vg)
    SettingsPanel.draw(vg)
    GMConsolePanel.draw(vg)
end

--- 服务器推送 player 数据后同步头像（由 Client.lua 调用）
---@param heroId number
function PlayerInfoPanel.setAvatarHeroId(heroId)
    if heroId and heroId >= 1 then
        state.avatarHeroId = heroId
        if img.heroIcons then
            local heroIcon = img.heroIcons[heroId]
            if heroIcon and heroIcon >= 0 then
                img.avatar = heroIcon
            end
        end
    end
end

--- 服务器推送 player 数据后同步头像框（由 Client.lua 调用）
---@param frameId number
function PlayerInfoPanel.setAvatarFrameId(frameId)
    if frameId and frameId >= 1 then
        state.avatarFrameId = frameId
    end
end

return PlayerInfoPanel
