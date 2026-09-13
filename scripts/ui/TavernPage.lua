-- TavernPage.lua
-- 酒馆界面：招募（抽卡）
-- 从城镇页面点击酒馆进入的二级界面
-- 弹窗系统（招募说明、历史招募、确认购买）已提取至 TavernPopups.lua

local GameConfig     = require("config.GameConfig")
local GachaConfig    = require("config.GachaConfig")
local UrGachaConfig  = require("config.UrGachaConfig")
local GachaSystem    = require("systems.GachaSystem")
local HeroConfig     = require("config.HeroConfig")
local GameState      = require("core.GameState")
local Protocol       = require("shared.Protocol")
local DrawUtil       = require("core.DrawUtil")
local drawTextStroke = DrawUtil.drawTextStroke
local drawImageCentered      = DrawUtil.drawImageCentered
local drawNineSlice          = DrawUtil.drawNineSlice
local hitTest                = DrawUtil.hitTest
local drawRoundedRectCentered = DrawUtil.drawRoundedRectCentered
local RecruitAnim       = require("ui.RecruitAnim")
local TavernPopups      = require("ui.TavernPopups")
local TavernShopPage    = require("ui.TavernShopPage")
local TargetRecruitPanel = require("ui.TargetRecruitPanel")
local BF                = require("systems.ButtonFeedback")
local ClientDispatcher  = require("network.ClientDispatcher")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格
local TavernPage = {}

--- 网络发送函数注入点（多人模式由 Client.lua 调用 setSendAction 注入）
---@type fun(action:string, params:table)|nil
local _sendAction = nil

---@type any
local vg_ = nil

--- 注入 sendAction 函数（多人模式使用）
function TavernPage.setSendAction(fn)
    _sendAction = fn
end

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量（上半部分） ========================

-- 1. 酒馆背景图（中心坐标）
local BG_CX, BG_CY = 540, 1200
local BG_W, BG_H   = 1080, 2400

-- 2. 建筑名称背景（与教堂完全一致）
local NAME_BG_CX, NAME_BG_CY = 147, 136
local NAME_BG_W, NAME_BG_H   = 294, 123

-- 3. 文本"酒馆"（与教堂一致的偏移）
local NAME_TEXT_CX, NAME_TEXT_CY = 148, 130
local NAME_FONT_SIZE              = 50

-- 4. 返回按钮（与教堂完全一致）
local BTN_BACK_CX, BTN_BACK_CY = 122, 2308
local BTN_BACK_W, BTN_BACK_H   = 184, 143

-- 5. 招募池子分类图（尺寸共用；坐标见 pools 表）
local POOL_W, POOL_H = 440, 204 -- 池子图片尺寸
local POOL_GAP = 12              -- 池子间距（预留第三池）

-- 6. 池子文本（字号/描边共用；坐标见 pools 表）
local POOL_TEXT_SIZE = 40        -- 字号
-- 描边颜色 #613637
local POOL_STROKE_R = 0x61       -- 97
local POOL_STROKE_G = 0x36       -- 54
local POOL_STROKE_B = 0x37       -- 55
local POOL_STROKE_W = 5          -- 描边宽度

-- 7. 抽卡池剩余时间图标背景
local TIMER_BG_CX, TIMER_BG_CY = 999, 292
local TIMER_BG_W, TIMER_BG_H   = 90, 90

-- 8. 抽卡池剩余时间图标
local TIMER_ICON_CX, TIMER_ICON_CY = 999, 292
local TIMER_ICON_W, TIMER_ICON_H   = 54, 54

-- ======================== 布局常量（下半部分） ========================

-- 9. 保底提示背景条
local PITY_BG_CX, PITY_BG_CY = 540, 1666
local PITY_BG_W, PITY_BG_H   = 1080, 90

-- 10. 保底提示图标背景
local PITY_ICON_BG_CX, PITY_ICON_BG_CY = 939, 1666
local PITY_ICON_BG_W, PITY_ICON_BG_H   = 90, 90

-- 11. 保底提示图标
local PITY_ICON_CX, PITY_ICON_CY = 939, 1666
local PITY_ICON_W, PITY_ICON_H   = 54, 54

-- 12. 保底提示文本
local PITY_TEXT_CX, PITY_TEXT_CY = 540, 1666
local PITY_TEXT_SIZE = 42

-- 12b. 指定招募提示文本（保底背景条上方）
local TARGET_TEXT_CX, TARGET_TEXT_CY = 540, 1572
local TARGET_TEXT_SIZE = 38

-- 13. 招募券资源背景栏
local TICKET_BG_CX, TICKET_BG_CY = 429, 1785
local TICKET_BG_W, TICKET_BG_H   = 170, 47
local TICKET_BG_R = 18  -- 圆角

-- 14. 冒险招募券图标
local TICKET_ICON_CX, TICKET_ICON_CY = 365, 1785
local TICKET_ICON_W, TICKET_ICON_H   = 70, 70

-- 15. 冒险招募券资源值
local TICKET_VAL_X, TICKET_VAL_Y = 444, 1785
local TICKET_VAL_SIZE = 33
local TICKET_STROKE_W = 4
-- 描边颜色 #232323
local TICKET_STROKE_R = 0x23
local TICKET_STROKE_G = 0x23
local TICKET_STROKE_B = 0x23

-- 16. 钻石资源栏背景
local DIAMOND_BG_CX, DIAMOND_BG_CY = 662, 1785
local DIAMOND_BG_W, DIAMOND_BG_H   = 170, 47
local DIAMOND_BG_R = 18

-- 17. 钻石图标（参考主界面 TopBar 76×76）
local DIAMOND_ICON_CX, DIAMOND_ICON_CY = 581, 1786
local DIAMOND_ICON_W, DIAMOND_ICON_H   = 76, 76

-- 18. 钻石值
local DIAMOND_VAL_X, DIAMOND_VAL_Y = 673, 1786
local DIAMOND_VAL_SIZE = 33
local DIAMOND_STROKE_W = 4
local DIAMOND_STROKE_R = 0x23
local DIAMOND_STROKE_G = 0x23
local DIAMOND_STROKE_B = 0x23

-- 19. 招募1次按钮
local BTN_1_CX, BTN_1_CY = 314, 1902
local BTN_1_W, BTN_1_H   = 410, 100
local BTN_TEXT_SIZE = 40
-- 按钮文本颜色 #25553d
local BTN_TEXT_R = 0x25
local BTN_TEXT_G = 0x55
local BTN_TEXT_B = 0x3d

-- 20. 招募10次按钮
local BTN_10_CX, BTN_10_CY = 766, 1902
local BTN_10_W, BTN_10_H   = 410, 100

-- 20.5 指定招募按钮
local BTN_TARGET_CX, BTN_TARGET_CY = 540, 2068
local BTN_TARGET_W, BTN_TARGET_H   = 410, 100
local BTN_TARGET_FONT = 40

-- 21. 底部滑块（与教堂一致）
local TAB_BG_CX, TAB_BG_CY = 639, 2308
local TAB_BG_W, TAB_BG_H   = 810, 143

local TAB_ITEMS = {
    { name = "招募",   cx = 439, cy = 2308, textX = 439, textY = 2302 },
    { name = "商店",   cx = 839, cy = 2308, textX = 839, textY = 2302 },
}
local SLIDER_W, SLIDER_H = 410, 143
local SLIDER_INSET_TOP    = 10
local SLIDER_INSET_BOTTOM = 10
local SLIDER_INSET_LEFT   = 70
local SLIDER_INSET_RIGHT  = 70

local TAB_FONT_SIZE = 40
local TAB_ACTIVE_R, TAB_ACTIVE_G, TAB_ACTIVE_B = 0x81, 0x57, 0x3c
local TAB_INACTIVE_R, TAB_INACTIVE_G, TAB_INACTIVE_B = 255, 255, 255

local TAB_ANIM_DURATION = 0.35

-- 九宫格按钮 inset（与招募按钮相同）
local BTN_INSET_TOP    = 10
local BTN_INSET_BOTTOM = 10
local BTN_INSET_LEFT   = 40
local BTN_INSET_RIGHT  = 40

-- ======================== 动画常量 ========================

local ANIM_DURATION       = 0.45  -- 打开动画时长
local CLOSE_ANIM_DURATION = 0.38  -- 关闭动画时长

-- ======================== 状态 ========================

local onCloseCallback_ = nil  -- 关闭动画完成后的回调（用于触发离场情景）
local onOpenCallback_  = nil  -- 打开动画完成后的回调（用于触发入场情景）

local state = {
    open      = false,
    closing   = false,
    openTime  = 0,
    closeTime = 0,
    selectedPool = 1,  -- 当前选中的池子索引（从1开始）
    tab       = "recruit",  -- 当前 tab: "shop" / "recruit"
    tabFrom   = "recruit",  -- 上次 tab（用于动画）
    tabSwitchTime = 0,
    -- 保底数据（从 GachaSystem 实时读取）
    pityRemain = GachaConfig.Pity.SSR_THRESHOLD,
    pityRank   = "SSR",
    -- 指定招募数据（从服务端 currency 模块同步）
    targetRecruitHeroId = nil,   -- 指定的SSR英雄ID（nil=未指定）
    targetRecruitRemain = 0,     -- 剩余SSR保底次数
    targetRecruitName   = nil,   -- 指定的SSR英雄名字（缓存）
    stellarTargetUpHeroId = nil,  -- 星辉指定UP角色ID（nil=未指定）
    stellarTargetUpName   = nil,  -- 星辉指定UP角色名字（缓存）
    -- 资源数据（从 GameState 实时读取）
    ticketCount  = 0,
    diamondCount = 0,
}

-- ======================== 池子数据 ========================

local POOL_ID_STANDARD = "standard"
local POOL_ID_STELLAR  = "stellar"

--- 星辉池保底 fallback（currency 推送丢失时，用 gacha_pull 响应里的 pity 字段）
---@type { sinceUR: number?, sinceSSR: number?, sinceSR: number? }|nil
local stellarPityOverride = nil

local function isStellarPoolId(poolId)
    return poolId == UrGachaConfig.POOL_ID or poolId == POOL_ID_STELLAR
end

local pools = {
    {
        id       = POOL_ID_STANDARD,
        name     = "常规招募",
        timeText = "永久",
        cx       = 249,
        cy       = 342,
        textX    = 80,
        textY    = 375,
        catKey   = "poolCatStandard",
        bgKey    = "bgStandard",
        enabled  = true,
    },
    {
        id       = POOL_ID_STELLAR,
        name     = UrGachaConfig.POOL_NAME,
        timeText = UrGachaConfig.getTimeDisplayText(),
        cx       = UrGachaConfig.UI.poolTabCx,
        cy       = UrGachaConfig.UI.poolTabCy,
        textX    = UrGachaConfig.UI.poolTextX,
        textY    = UrGachaConfig.UI.poolTextY,
        catKey   = "poolCatStellar",
        bgKey    = "bgStellar",
        enabled  = UrGachaConfig.isPoolEnabled(),
        unlocked = false,
    },
}

-- ======================== 图片资源（主界面专用） ========================

local img = {
    -- 上半部分
    bgStandard      = -1,   -- UI_KCBJ_1.png
    bgStellar       = -1,   -- UI_KCBJ_2.png
    nameBg    = -1,   -- UI_TJP_MC.png
    btnBack   = -1,   -- UI_AN_FH.png
    poolCatStandard = -1,   -- UI_KCFL_1.png
    poolCatStellar  = -1,   -- UI_KCFL_2.png
    poolSel   = -1,   -- UI_KCFL_gl.png
    upPortrait      = -1,   -- KCLH_{heroId}.png 当期 UP
    timerBg   = -1,   -- UI_YXTBBJ.png
    timerIcon = -1,   -- UI_icon_NZ.png
    -- 下半部分
    pityBg      = -1, -- UI_JG_SMBJ.png
    pityIcon    = -1, -- UI_icon_TS.png
    ticketIcon  = -1, -- UI_icon_ZMQ_X.png（常规）
    ticketIconStellar = -1, -- UI_icon_ZMQ_2 星辉招募券
    diamondIcon = -1, -- UI_icon_SJ_X.png
    btnLv       = -1, -- UI_AN_LV.png
    tabBg       = -1, -- UI_AN_1.png
    slider      = -1, -- UI_AN_2.png
}

-- ======================== 缓动函数 ========================

local function easeOutCubic(t)
    t = t - 1
    return t * t * t + 1
end

local function easeInCubic(t)
    return t * t * t
end

--- 加载图片（主路径失败时尝试备用路径）
local function loadImage(vg, primaryPath, altPath)
    local h = nvgCreateImage(vg, primaryPath, 0)
    if h and h >= 0 then return h end
    if altPath then
        h = nvgCreateImage(vg, altPath, 0)
        if h and h >= 0 then return h end
    end
    print("[TavernPage] WARNING: 图片加载失败 " .. tostring(primaryPath))
    return -1
end

--- 重新加载当期 UP 立绘（轮换或指定 UP 后调用）
local function reloadUpPortrait(vg, heroId)
    if not vg then return end
    img.upPortrait = loadImage(vg, UrGachaConfig.getUpPortraitPath(heroId))
end

local function getSelectedPool()
    return pools[state.selectedPool] or pools[1]
end

local function getSelectedPoolId()
    local pool = getSelectedPool()
    return pool and pool.id or POOL_ID_STANDARD
end

local function isStellarPoolSelected()
    return getSelectedPoolId() == POOL_ID_STELLAR
end

local function refreshPoolMeta()
    local stellar = pools[2]
    if stellar then
        stellar.name     = UrGachaConfig.POOL_NAME
        stellar.timeText = UrGachaConfig.getTimeDisplayText()
        stellar.cx       = UrGachaConfig.UI.poolTabCx
        stellar.cy       = UrGachaConfig.UI.poolTabCy
        stellar.textX    = UrGachaConfig.UI.poolTextX
        stellar.textY    = UrGachaConfig.UI.poolTextY
        local currencyData = ClientDispatcher.get("currency")
        local heroesData   = ClientDispatcher.get("heroes")
        local unlocked, _ = UrGachaConfig.checkPoolUnlocked(currencyData, heroesData and heroesData.roster, ClientDispatcher.get("battle"))
        stellar.enabled  = UrGachaConfig.isPoolEnabled()
        stellar.unlocked = unlocked
    end
end

local function isStellarPoolUnlocked()
    local currencyData = ClientDispatcher.get("currency")
    local heroesData   = ClientDispatcher.get("heroes")
    return UrGachaConfig.checkPoolUnlocked(currencyData, heroesData and heroesData.roster, ClientDispatcher.get("battle"))
end

local function canPullForCurrentPool(count)
    if isStellarPoolSelected() then
        local ticketCost = (count == 10) and UrGachaConfig.Cost.TEN_TICKET or UrGachaConfig.Cost.SINGLE_TICKET
        local tickets  = GameState.getStellarRecruitTicket()
        local diamonds = GameState.getGems()
        if tickets >= ticketCost then return true, "ticket" end
        local shortfall = ticketCost - tickets
        if shortfall > 0 and diamonds >= shortfall * UrGachaConfig.Cost.SINGLE_DIAMOND then
            return true, "diamond"
        end
        return false, "none"
    end
    return GachaSystem.canPull(count)
end

-- ======================== Tab 映射 ========================

local TAB_MAP = {
    recruit = 1,
    shop    = 2,
}

-- ======================== 数据同步（前向声明） ========================

--- 同步界面上的资源/保底显示
local function syncDisplayData()
    if isStellarPoolSelected() then
        state.ticketCount = GameState.getStellarRecruitTicket()
    else
        state.ticketCount = GameState.getRecruitTicket()
    end
    state.diamondCount = GameState.getGems()

    -- 从服务端推送的 currency 模块数据恢复保底计数到 GachaSystem
    -- 修复：重启游戏后 GachaSystem.pityState 被重置为 0 的问题
    local currencyData = ClientDispatcher.get("currency")
    if currencyData then
        local serverSR  = currencyData.gachaPitySR or 0
        local serverSSR = currencyData.gachaPitySSR or 0
        GachaSystem.setPityCounts(serverSR, serverSSR)

        -- 同步指定招募数据
        state.targetRecruitHeroId = currencyData.targetRecruitHeroId
        state.targetRecruitRemain = currencyData.targetRecruitRemain or 0
        if state.targetRecruitHeroId then
            local heroCfg = HeroConfig.get(state.targetRecruitHeroId)
            state.targetRecruitName = heroCfg and heroCfg.name or "未知"
        else
            state.targetRecruitName = nil
        end

        local prevStellarTargetUpHeroId = state.stellarTargetUpHeroId
        state.stellarTargetUpHeroId = currencyData.stellarTargetUpHeroId
        if state.stellarTargetUpHeroId then
            local heroCfg = HeroConfig.get(state.stellarTargetUpHeroId)
            state.stellarTargetUpName = heroCfg and heroCfg.name or "未知"
        else
            state.stellarTargetUpName = nil
        end
        if prevStellarTargetUpHeroId ~= state.stellarTargetUpHeroId and vg_ then
            reloadUpPortrait(vg_, state.stellarTargetUpHeroId)
        end
    end

    state.pityRemain   = GachaSystem.getSSRPityRemain()
    state.pityRank     = "SSR"
    if isStellarPoolSelected() then
        local currencyData = ClientDispatcher.get("currency")
        local sinceUR = currencyData and currencyData.urPityUR
        if sinceUR == nil and stellarPityOverride then
            sinceUR = stellarPityOverride.sinceUR
        end
        local threshold = UrGachaConfig.Pity.UR_THRESHOLD
        if sinceUR ~= nil then
            state.pityRemain = math.max(0, threshold - sinceUR)
        else
            state.pityRemain = threshold
        end
        state.pityRank = "UR"
    end
end

-- ======================== 公开接口 ========================

--- 初始化（加载图片资源，仅调用一次）
function TavernPage.init(vg)
    vg_ = vg
    -- 上半部分
    img.bgStandard      = loadImage(vg, "image/UI_KCBJ_1.png")
    img.bgStellar       = loadImage(vg, UrGachaConfig.UI.bgPath)
    img.nameBg    = nvgCreateImage(vg, "image/UI_TJP_MC.png", 0)
    img.btnBack   = nvgCreateImage(vg, "image/UI_AN_FH.png", 0)
    img.poolCatStandard = nvgCreateImage(vg, "image/UI_KCFL_1.png", 0)
    img.poolCatStellar  = loadImage(vg, UrGachaConfig.UI.poolTabPath)
    img.poolSel   = nvgCreateImage(vg, "image/UI_KCFL_gl.png", 0)
    reloadUpPortrait(vg)
    img.timerBg   = nvgCreateImage(vg, "image/UI_YXTBBJ.png", 0)
    img.timerIcon = nvgCreateImage(vg, "image/UI_icon_NZ.png", 0)
    -- 下半部分
    img.pityBg      = nvgCreateImage(vg, "image/UI_JG_SMBJ.png", 0)
    img.pityIcon    = nvgCreateImage(vg, "image/UI_icon_TS.png", 0)
    img.ticketIcon  = nvgCreateImage(vg, "image/UI_icon_ZMQ_X.png", 0)
    img.ticketIconStellar = loadImage(vg, UrGachaConfig.UI.ticketIconPath, "image/UI_icon_ZMQ2_X.png")
    -- [暗黑化 P1-B5] 原 image/UI_AN_LV.png 贴图加载已移除（矢量绘制替代）
    img.btnLv       = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    -- [暗黑化 P1-B5] 原 image/UI_AN_2.png 贴图加载已移除（矢量绘制替代）
    img.slider      = nvgCreateImage(vg, "image/UI_AN_2.png", 0)

    -- 初始化弹窗子模块（setContext 已在模块级别调用，此处只需 init 加载图片）
    TavernPopups.init(vg)

    -- 初始化招募动画模块
    RecruitAnim.init(vg)

    -- 初始化商店标签页
    TavernShopPage.init(vg)

    -- 初始化指定招募面板
    TargetRecruitPanel.init(vg)
    img.btnTarget = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)

    -- currency 推送到达后清除星辉保底 fallback，以服务端模块数据为准
    ClientDispatcher.subscribe("currency", function(data)
        if data and data.urPityUR ~= nil then
            stellarPityOverride = nil
        end
        if state.open then
            syncDisplayData()
        end
    end)

    print("[TavernPage] init OK")
end

--- 等待服务端返回的抽卡请求（防止重复发送）
local pendingGachaPull = false
local pendingGachaPullTime = 0       -- 发送时间戳
local GACHA_PULL_TIMEOUT   = 8       -- 超时秒数（缩短至8秒，更快恢复）

--- 打开酒馆
function TavernPage.open()
    -- 打开时检查是否有遗留的僵尸锁（WiFi 僵尸连接场景：请求发出但无响应，无断线事件）
    -- 若已超过超时时长，说明上次请求已死，直接清除避免玩家进来就看到锁死状态
    if pendingGachaPull and (time.elapsedTime - pendingGachaPullTime) >= GACHA_PULL_TIMEOUT then
        pendingGachaPull = false
        print("[TavernPage] open: 清除遗留僵尸锁（超时 " .. GACHA_PULL_TIMEOUT .. "s）")
    end

    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    require("systems.GameSFX").playUIMove(1)
    state.selectedPool = 1
    state.tab = "recruit"
    state.tabFrom = "recruit"
    refreshPoolMeta()
    TavernShopPage.resetScroll()
    TavernShopPage.syncPurchasedFromStore()
    -- 同步资源与保底数据
    syncDisplayData()
    print("[TavernPage] 打开酒馆")
end

--- 关闭酒馆（启动关闭动画）
function TavernPage.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    TavernPopups.resetAll()
    print("[TavernPage] 关闭酒馆（动画）")
end

--- 注册关闭动画完成后的回调（触发一次后自动清除）
function TavernPage.setOnCloseCallback(fn)
    onCloseCallback_ = fn
end

--- 注册打开动画完成后的回调（触发一次后自动清除）
function TavernPage.setOnOpenCallback(fn)
    onOpenCallback_ = fn
end

--- 是否打开
---@return boolean
function TavernPage.isOpen()
    return state.open
end

--- 强制关闭（跳过动画，用于安全恢复 — 离开 tab4 时调用）
function TavernPage.forceClose()
    if not state.open then return end
    print("[TavernPage] forceClose: 跳过动画强制关闭 (closing=" .. tostring(state.closing) .. ")")
    state.open = false
    state.closing = false
    TavernPopups.resetAll()
end

--- 返回打开/关闭动画进度 (0=完全关闭, 1=完全打开)
function TavernPage.getAnimProgress()
    if not state.open then return 0 end
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / CLOSE_ANIM_DURATION)
        return 1 - easeInCubic(rawT)
    else
        local elapsed = time.elapsedTime - state.openTime
        local rawT = math.min(1.0, elapsed / ANIM_DURATION)
        return easeOutCubic(rawT)
    end
end

-- ======================== 招募逻辑 ========================

--- 执行招募（内部，跳过确认框检查）
---@param count number 1 或 10
local function doRecruitDirect(count, forcePayType)
    if isStellarPoolSelected() and not isStellarPoolUnlocked() then
        TavernPopups.showFloatText("进入地狱难度后开放", DESIGN_W * 0.5, DESIGN_H * 0.42)
        return
    end

    local poolId = getSelectedPoolId()
    -- 多人模式：走服务端流程
    if _sendAction then
        if pendingGachaPull then
            print("[TavernPage] 招募请求处理中，请稍候")
            return
        end
        local payType = forcePayType
        if not payType then
            local canDo
            canDo, payType = canPullForCurrentPool(count)
            if not canDo then
                TavernPopups.showFloatText("资源不足", DESIGN_W * 0.5, DESIGN_H * 0.42)
                print("[TavernPage] 资源不足，无法招募")
                return
            end
        end
        pendingGachaPull = true
        pendingGachaPullTime = time.elapsedTime
        _sendAction(Protocol.ACTION_TYPES.GACHA_PULL, { count = count, payType = payType, poolId = poolId })
        print("[TavernPage] 发送招募请求 pool=" .. poolId .. " count=" .. count .. " payType=" .. payType)
        return
    end

    -- 单机模式：本地执行
    local payType = forcePayType
    if not payType then
        local canDo
        canDo, payType = canPullForCurrentPool(count)
        if not canDo then
            TavernPopups.showFloatText("资源不足", DESIGN_W * 0.5, DESIGN_H * 0.42)
            print("[TavernPage] 资源不足，无法招募")
            return
        end
    end

    local results, _
    if isStellarPoolSelected() then
        print("[TavernPage] 星辉招募仅支持联网模式")
        return
    else
        results, _ = GachaSystem.pull(count, payType)
    end
    if not results then return end

    -- 记录历史
    TavernPopups.recordHistory(results, getSelectedPoolId())

    syncDisplayData()

    RecruitAnim.start(results, function()
        syncDisplayData()
        print("[TavernPage] 招募动画结束")
        -- 新手引导：单机模式在动画结束后通知 gacha10_complete
        local _TM = require("systems.TutorialManager")
        for _, r in ipairs(results) do
            if r.type == "hero" and r.heroId then
                _TM.setNewHeroId(r.heroId)
                break
            end
        end
        _TM.notifyEvent("gacha10_complete")
    end)
end

-- 延迟注入 doRecruitDirect 到弹窗子模块（因为定义在 init 之后）
TavernPopups.setContext({
    doRecruitDirect = doRecruitDirect,
    syncDisplayData = syncDisplayData,
    getSelectedPoolId = getSelectedPoolId,
    canPullForCurrentPool = canPullForCurrentPool,
    DESIGN_W = DESIGN_W,
    DESIGN_H = DESIGN_H,
})

--- 执行招募（外部入口，含确认框检查）
---@param count number 1 或 10
local function doRecruit(count)
    -- 检查招募券是否足够，不足则弹确认框
    if not TavernPopups.checkAndShowConfirm(count) then
        return
    end
    -- 招募券足够，直接执行
    doRecruitDirect(count)
end

-- ======================== 绘制辅助 ========================

--- 绘制保底提示文本（高亮部分为 #ffef67）
--- 铁律 #15: 多段文本在 scale 下必须缓存宽度
local _pityTextWidthCache = {}
local function getCachedTextWidth(vg, text, fontSize)
    local key = text .. "\0" .. fontSize
    local w = _pityTextWidthCache[key]
    if not w then
        w = nvgTextBounds(vg, 0, 0, text)
        _pityTextWidthCache[key] = w
    end
    return w
end

local function drawPityText(vg, cx, cy)
    local remain = tostring(state.pityRemain)
    local rank   = state.pityRank .. "级"
    local suffix = isStellarPoolSelected() and "角色" or "冒险家"

    local segments = {
        { text = "接下来",   color = { 255, 255, 255 } },
        { text = remain,     color = { 0xFF, 0xEF, 0x67 } },
        { text = "次内，必得", color = { 255, 255, 255 } },
        { text = rank,       color = { 0xFF, 0xEF, 0x67 } },
        { text = suffix,     color = { 255, 255, 255 } },
    }



    nvgFontFace(vg, "sans")
    nvgFontSize(vg, PITY_TEXT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 先用缓存宽度计算总宽度以居中
    local totalW = 0
    for _, seg in ipairs(segments) do
        local w = getCachedTextWidth(vg, seg.text, PITY_TEXT_SIZE)
        seg.w = w
        totalW = totalW + w
    end

    -- 从居中起始位置绘制
    local startX = cx - totalW * 0.5
    local curX = startX
    for _, seg in ipairs(segments) do
        nvgFillColor(vg, nvgRGBA(seg.color[1], seg.color[2], seg.color[3], 255))
        nvgText(vg, curX, cy, seg.text, nil)
        curX = curX + seg.w
    end
end

--- 绘制指定招募 / 星辉指定UP提示文本（保底背景条上方，带描边增强可读性）
local function drawTargetRecruitText(vg, cx, cy)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TARGET_TEXT_SIZE)

    local segments = nil
    local emptyText = "当前未指定招募保底"

    if isStellarPoolSelected() then
        if state.stellarTargetUpHeroId then
            segments = {
                { text = "UR抽中有", color = { 255, 255, 255 } },
                { text = "50%", color = { 0xFF, 0xEF, 0x67 } },
                { text = "概率为 ", color = { 255, 255, 255 } },
                { text = state.stellarTargetUpName or "未知", color = { 0xFF, 0x88, 0x44 } },
            }
        else
            emptyText = "当前未指定UP角色"
        end
    elseif state.targetRecruitHeroId and state.targetRecruitRemain > 0 then
        -- 有指定招募：多段绘制 "还剩 N 次招募SSR必定招募 XXX"
        segments = {
            { text = "还剩",     color = { 255, 255, 255 } },
            { text = tostring(state.targetRecruitRemain), color = { 0xFF, 0xEF, 0x67 } },
            { text = "次招募SSR必定招募", color = { 255, 255, 255 } },
            { text = state.targetRecruitName or "未知", color = { 0xFF, 0x88, 0x44 } },
        }
    end

    if segments then
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local totalW = 0
        for _, seg in ipairs(segments) do
            local w = getCachedTextWidth(vg, seg.text, TARGET_TEXT_SIZE)
            seg.w = w
            totalW = totalW + w
        end

        -- 描边（黑色轮廓增强可读性）
        local curX = cx - totalW * 0.5
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        for _, seg in ipairs(segments) do
            for ox = -1, 1 do
                for oy = -1, 1 do
                    if ox ~= 0 or oy ~= 0 then
                        nvgText(vg, curX + ox, cy + oy, seg.text, nil)
                    end
                end
            end
            curX = curX + seg.w
        end

        -- 正文
        curX = cx - totalW * 0.5
        for _, seg in ipairs(segments) do
            nvgFillColor(vg, nvgRGBA(seg.color[1], seg.color[2], seg.color[3], 255))
            nvgText(vg, curX, cy, seg.text, nil)
            curX = curX + seg.w
        end
    else
        -- 未指定：带描边的灰色提示
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
        for ox = -1, 1 do
            for oy = -1, 1 do
                if ox ~= 0 or oy ~= 0 then
                    nvgText(vg, cx + ox, cy + oy, emptyText, nil)
                end
            end
        end
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
        nvgText(vg, cx, cy, emptyText, nil)
    end
end

--- 绘制酒馆页面
function TavernPage.draw(vg)
    if not state.open then return end

    -- 计算打开/关闭动画偏移
    local progress
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / CLOSE_ANIM_DURATION)
        progress = 1.0 - easeInCubic(rawT)
        -- 动画结束 → 彻底关闭
        if rawT >= 1.0 then
            state.open = false
            state.closing = false
            local cb = onCloseCallback_
            onCloseCallback_ = nil
            if cb then cb() end
            return
        end
    else
        local elapsed = time.elapsedTime - state.openTime
        local rawT = math.min(1.0, elapsed / ANIM_DURATION)
        progress = easeOutCubic(rawT)
        if rawT >= 1.0 and onOpenCallback_ then
            local cb = onOpenCallback_
            onOpenCallback_ = nil
            cb()
        end
    end

    -- 整体从上方滑入
    local upperOY = (1 - progress) * (-DESIGN_H)

    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)

    -- ============ 1. 酒馆背景图（随卡池切换） ============
    nvgSave(vg)
    nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
    local bgImg = img.bgStandard
    if isStellarPoolSelected() and img.bgStellar >= 0 then
        bgImg = img.bgStellar
    end
    drawImageCentered(vg, bgImg, BG_CX, BG_CY, BG_W, BG_H, 1.0)

    -- ============ 1b. 星辉池当期 UP 立绘 ============
    if isStellarPoolSelected() and img.upPortrait >= 0 then
        local px = UrGachaConfig.UI.portraitCx
        local py = UrGachaConfig.UI.portraitCy
        local pw, ph = nvgImageSize(vg, img.upPortrait)
        if pw > 0 and ph > 0 then
            drawImageCentered(vg, img.upPortrait, px, py, pw, ph, 1.0)
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- ============ 2. 建筑名称背景 ============
    drawImageCentered(vg, img.nameBg, NAME_BG_CX, NAME_BG_CY, NAME_BG_W, NAME_BG_H, 1.0)

    -- ============ 3. 文本"酒馆" ============
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, NAME_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, NAME_TEXT_CX, NAME_TEXT_CY, "酒馆", nil)

    if state.tab == "shop" then
        -- ============ 商店标签页内容 ============
        TavernShopPage.drawContent(vg)
    else
        -- ============ 4. 招募池子列表 ============
        refreshPoolMeta()
        for i, pool in ipairs(pools) do
            if not pool.enabled then goto continue_pool_draw end
            local cx, cy = pool.cx, pool.cy
            local poolAlpha = (pool.unlocked ~= false) and 1.0 or 0.45
            local catImg = img[pool.catKey] or img.poolCatStandard
            if catImg and catImg >= 0 then
                drawImageCentered(vg, catImg, cx, cy, POOL_W, POOL_H, poolAlpha)
            end

            if state.selectedPool == i then
                drawImageCentered(vg, img.poolSel, cx, cy, POOL_W, POOL_H, poolAlpha)
            end

            drawTextStroke(vg,
                pool.textX, pool.textY,
                pool.name,
                POOL_TEXT_SIZE,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                255, 255, 255,
                POOL_STROKE_W,
                { strokeColor = { POOL_STROKE_R, POOL_STROKE_G, POOL_STROKE_B }, alpha = poolAlpha }
            )
            ::continue_pool_draw::
        end

        -- ============ 5. 历史招募图标背景 + 图标 ============
        local _s1 = BF.begin(vg, "tavern_history", TIMER_BG_CX, TIMER_BG_CY, TIMER_BG_W, TIMER_BG_H)
        drawImageCentered(vg, img.timerBg, TIMER_BG_CX, TIMER_BG_CY, TIMER_BG_W, TIMER_BG_H, 1.0)
        drawImageCentered(vg, img.timerIcon, TIMER_ICON_CX, TIMER_ICON_CY, TIMER_ICON_W, TIMER_ICON_H, 1.0)
        BF.finish(vg, _s1)

        -- ============ 6. 保底提示背景条 ============
        drawImageCentered(vg, img.pityBg, PITY_BG_CX, PITY_BG_CY, PITY_BG_W, PITY_BG_H, 1.0)

        -- ============ 7. 保底提示图标背景（复用 timerBg） ============
        local _s2 = BF.begin(vg, "tavern_pity", PITY_ICON_BG_CX, PITY_ICON_BG_CY, PITY_ICON_BG_W, PITY_ICON_BG_H)
        drawImageCentered(vg, img.timerBg, PITY_ICON_BG_CX, PITY_ICON_BG_CY, PITY_ICON_BG_W, PITY_ICON_BG_H, 1.0)

        -- ============ 8. 保底提示图标 ============
        drawImageCentered(vg, img.pityIcon, PITY_ICON_CX, PITY_ICON_CY, PITY_ICON_W, PITY_ICON_H, 1.0)
        BF.finish(vg, _s2)

        -- ============ 9a. 指定招募/星辉指定UP提示文本 ==========
        drawTargetRecruitText(vg, TARGET_TEXT_CX, TARGET_TEXT_CY)

        -- ============ 9b. 保底提示文本 ============
        drawPityText(vg, PITY_TEXT_CX, PITY_TEXT_CY)

        -- ============ 10. 招募券资源背景栏 ============
        drawRoundedRectCentered(vg,
            TICKET_BG_CX, TICKET_BG_CY,
            TICKET_BG_W, TICKET_BG_H,
            TICKET_BG_R,
            0, 0, 0, 204)  -- 纯黑 80%

        -- ============ 11. 招募券图标 ============
        local ticketImg = img.ticketIcon
        if isStellarPoolSelected() and img.ticketIconStellar >= 0 then
            ticketImg = img.ticketIconStellar
        end
        drawImageCentered(vg, ticketImg, TICKET_ICON_CX, TICKET_ICON_CY, TICKET_ICON_W, TICKET_ICON_H, 1.0)

        -- ============ 12. 冒险招募券资源值（居中于背景栏） ============
        drawTextStroke(vg,
            TICKET_BG_CX, TICKET_VAL_Y,
            tostring(state.ticketCount),
            TICKET_VAL_SIZE,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255,
            TICKET_STROKE_W,
            { strokeColor = { TICKET_STROKE_R, TICKET_STROKE_G, TICKET_STROKE_B } }
        )

        -- ============ 13. 钻石资源栏背景 ============
        drawRoundedRectCentered(vg,
            DIAMOND_BG_CX, DIAMOND_BG_CY,
            DIAMOND_BG_W, DIAMOND_BG_H,
            DIAMOND_BG_R,
            0, 0, 0, 204)  -- 纯黑 80%

        -- ============ 14. 钻石图标 ============
        drawImageCentered(vg, img.diamondIcon, DIAMOND_ICON_CX, DIAMOND_ICON_CY, DIAMOND_ICON_W, DIAMOND_ICON_H, 1.0)

        -- ============ 15. 钻石值（居中于背景栏） ============
        drawTextStroke(vg,
            DIAMOND_BG_CX, DIAMOND_VAL_Y,
            tostring(state.diamondCount),
            DIAMOND_VAL_SIZE,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255,
            DIAMOND_STROKE_W,
            { strokeColor = { DIAMOND_STROKE_R, DIAMOND_STROKE_G, DIAMOND_STROKE_B } }
        )

        -- ============ 16. 招募1次按钮 ============
        local _s3 = BF.begin(vg, "tavern_recruit1", BTN_1_CX, BTN_1_CY, BTN_1_W, BTN_1_H)
        DarkIcon.drawNine(vg, "btn", BTN_1_CX - BTN_1_W * 0.5, BTN_1_CY - BTN_1_H * 0.5, BTN_1_W, BTN_1_H, { accent = "green" })

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_TEXT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_TEXT_R, BTN_TEXT_G, BTN_TEXT_B, 255))
        nvgText(vg, BTN_1_CX, BTN_1_CY, "招募1次", nil)
        BF.finish(vg, _s3)

        -- ============ 17. 招募10次按钮 ============
        local _s4 = BF.begin(vg, "tavern_recruit10", BTN_10_CX, BTN_10_CY, BTN_10_W, BTN_10_H)
        DarkIcon.drawNine(vg, "btn", BTN_10_CX - BTN_10_W * 0.5, BTN_10_CY - BTN_10_H * 0.5, BTN_10_W, BTN_10_H, { accent = "green" })

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_TEXT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_TEXT_R, BTN_TEXT_G, BTN_TEXT_B, 255))
        nvgText(vg, BTN_10_CX, BTN_10_CY, "招募10次", nil)
        BF.finish(vg, _s4)
        local _TM = require("systems.TutorialManager")
        if _TM.isActive() then _TM.registerHotspot("tavern_btn_gacha10", BTN_10_CX, BTN_10_CY, BTN_10_W, BTN_10_H) end

        -- ============ 20.5 指定招募 / 指定UP角色按钮 ==========
        local _s6 = BF.begin(vg, "tavern_target", BTN_TARGET_CX, BTN_TARGET_CY, BTN_TARGET_W, BTN_TARGET_H)
        DarkIcon.drawNine(vg, "btn", BTN_TARGET_CX - BTN_TARGET_W * 0.5, BTN_TARGET_CY - BTN_TARGET_H * 0.5, BTN_TARGET_W, BTN_TARGET_H, { accent = "gold" })
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_TARGET_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))
        nvgText(vg, BTN_TARGET_CX, BTN_TARGET_CY, isStellarPoolSelected() and "指定UP角色" or "指定招募", nil)
        BF.finish(vg, _s6)
    end -- state.tab ~= "shop"

    -- ============ 18. 返回按钮 ============
    local _s5 = BF.begin(vg, "tavern_back", BTN_BACK_CX, BTN_BACK_CY, BTN_BACK_W, BTN_BACK_H)
    drawImageCentered(vg, img.btnBack, BTN_BACK_CX, BTN_BACK_CY, BTN_BACK_W, BTN_BACK_H, 1.0)
    BF.finish(vg, _s5)

    -- ============ 19. 底部滑块背景 ============
    drawImageCentered(vg, img.tabBg, TAB_BG_CX, TAB_BG_CY, TAB_BG_W, TAB_BG_H, 1.0)

    -- ============ 20. 滑块按钮（带平移动画） ============
    local tabIdx = TAB_MAP[state.tab] or 2
    local fromIdx = TAB_MAP[state.tabFrom] or 2
    local tabElapsed = time.elapsedTime - state.tabSwitchTime
    local tabT = math.min(1.0, tabElapsed / TAB_ANIM_DURATION)
    local tabEased = easeOutCubic(tabT)

    local targetItem = TAB_ITEMS[tabIdx]
    local fromItem = TAB_ITEMS[fromIdx]
    local sliderCX = fromItem.cx + (targetItem.cx - fromItem.cx) * tabEased
    local sliderCY = fromItem.cy + (targetItem.cy - fromItem.cy) * tabEased

    DarkIcon.drawNine(vg, "btn", sliderCX - SLIDER_W * 0.5, sliderCY - SLIDER_H * 0.5, SLIDER_W, SLIDER_H, { accent = "gold" })

    -- Tab 文本
    local tabKeys = { "recruit", "shop" }
    for i, item in ipairs(TAB_ITEMS) do
        local isActive = (state.tab == tabKeys[i])
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TAB_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(TAB_ACTIVE_R, TAB_ACTIVE_G, TAB_ACTIVE_B, 255))
        else
            nvgFillColor(vg, nvgRGBA(TAB_INACTIVE_R, TAB_INACTIVE_G, TAB_INACTIVE_B, 255))
        end
        nvgText(vg, item.textX, item.textY, item.name, nil)
    end

    nvgRestore(vg)

    -- 招募动画（全屏覆盖，不受酒馆滑入偏移影响）
    RecruitAnim.draw(vg)

    -- 招募请求等待中：绘制遮罩 + 加载提示
    if pendingGachaPull and not RecruitAnim.isPlaying() then
        -- 半透明黑色遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
        nvgFill(vg)

        -- 旋转加载点动画（用 3 个圆点表示进度）
        local elapsed = time.elapsedTime - pendingGachaPullTime
        local dotCount = math.floor(elapsed * 2) % 4  -- 每 0.5 秒切换，0~3 个点
        local dots = string.rep(".", dotCount)

        -- "招募中" 文字 + 动画点
        local loadText = "招募中" .. dots
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 56)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 描边（深色），提高可读性
        nvgFontBlur(vg, 0)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        for ox = -3, 3, 3 do
            for oy = -3, 3, 3 do
                if ox ~= 0 or oy ~= 0 then
                    nvgText(vg, DESIGN_W * 0.5 + ox, DESIGN_H * 0.5 + oy, loadText, nil)
                end
            end
        end
        -- 主文字（亮黄色，醒目）
        nvgFillColor(vg, nvgRGBA(0xFF, 0xEF, 0x67, 255))
        nvgText(vg, DESIGN_W * 0.5, DESIGN_H * 0.5, loadText, nil)

        -- 超时剩余提示（底部小字）
        local remaining = math.max(0, GACHA_PULL_TIMEOUT - elapsed)
        if remaining < GACHA_PULL_TIMEOUT then  -- 始终显示倒计时
            local tipText = string.format("等待服务器响应 (%.0f)", remaining)
            nvgFontSize(vg, 32)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, DESIGN_W * 0.5, DESIGN_H * 0.5 + 80, tipText, nil)
        end
    end

    -- 弹窗绘制（最顶层覆盖：确认框、招募说明、历史招募、飘字）
    TavernPopups.drawAll(vg)

    -- 指定招募面板（最顶层）
    TargetRecruitPanel.draw(vg)
end

--- 处理输入（设计坐标）
function TavernPage.handleInput(dx, dy)
    if not state.open then return false end
    if state.closing then
        -- 安全保护：关闭动画超过 1 秒仍未完成，强制关闭
        local closingElapsed = time.elapsedTime - state.closeTime
        if closingElapsed > 1.0 then
            print("[TavernPage] handleInput: 关闭动画超时(" .. string.format("%.2f", closingElapsed) .. "s)，强制关闭")
            TavernPage.forceClose()
            return false
        end
        return true
    end

    -- 指定招募面板优先处理输入
    if TargetRecruitPanel.isOpen() then
        return TargetRecruitPanel.handleInput(dx, dy)
    end

    -- 弹窗优先处理输入
    if TavernPopups.isBlocking() then
        return TavernPopups.handleInput(dx, dy)
    end

    -- 招募动画正在播放时，优先处理
    if RecruitAnim.isPlaying() then
        return RecruitAnim.handleInput(dx, dy)
    end

    -- 返回按钮
    if hitTest(dx, dy, BTN_BACK_CX, BTN_BACK_CY, BTN_BACK_W, BTN_BACK_H) then
        -- 招募请求进行中，不允许离开（避免引导组8 invisible 步骤期间提前退出）
        if pendingGachaPull then return true end
        BF.trigger("tavern_back")
        TavernPage.close()
        return true
    end

    if state.tab == "shop" then
        -- 商店标签页输入转发
        if TavernShopPage.handleInput(dx, dy) then return true end
    else
        -- 历史招募图标点击 → 打开历史弹窗
        if hitTest(dx, dy, TIMER_BG_CX, TIMER_BG_CY, TIMER_BG_W, TIMER_BG_H) then
            BF.trigger("tavern_history")
            TavernPopups.openHistory()
            return true
        end

        -- 保底提示图标（招募说明）→ 打开说明弹窗
        if hitTest(dx, dy, PITY_ICON_BG_CX, PITY_ICON_BG_CY, PITY_ICON_BG_W, PITY_ICON_BG_H) then
            BF.trigger("tavern_pity")
            TavernPopups.openInfo()
            return true
        end

        -- 招募1次按钮
        if hitTest(dx, dy, BTN_1_CX, BTN_1_CY, BTN_1_W, BTN_1_H) then
            BF.trigger("tavern_recruit1")
            print("[TavernPage] 点击: 招募1次")
            doRecruit(1)
            return true
        end

        -- 招募10次按钮
        if hitTest(dx, dy, BTN_10_CX, BTN_10_CY, BTN_10_W, BTN_10_H) then
            BF.trigger("tavern_recruit10")
            print("[TavernPage] 点击: 招募10次")
            doRecruit(10)
            return true
        end

        -- 指定招募 / 指定UP角色按钮
        if hitTest(dx, dy, BTN_TARGET_CX, BTN_TARGET_CY, BTN_TARGET_W, BTN_TARGET_H) then
            BF.trigger("tavern_target")
            if isStellarPoolSelected() then
                print("[TavernPage] 点击: 指定UP角色")
                TargetRecruitPanel.open("stellar")
            else
                print("[TavernPage] 点击: 指定招募")
                TargetRecruitPanel.open("standard")
            end
            return true
        end
    end

    -- Tab 切换检测
    local tabKeys = { "recruit", "shop" }
    for i, item in ipairs(TAB_ITEMS) do
        if hitTest(dx, dy, item.cx, item.cy, SLIDER_W, SLIDER_H) then
            local newTab = tabKeys[i]
            if state.tab ~= newTab then
                state.tabFrom = state.tab
                state.tabSwitchTime = time.elapsedTime
                state.tab = newTab
                require("systems.GameSFX").playUIMove(2)
                if newTab == "shop" then
                    TavernShopPage.resetScroll()
                    TavernShopPage.syncPurchasedFromStore()
                end
                print("[TavernPage] 切换到: " .. item.name)
            end
            return true
        end
    end

    -- 池子点击检测（仅招募标签页）
    if state.tab ~= "shop" then
        refreshPoolMeta()
        for i, pool in ipairs(pools) do
            local cx, cy = pool.cx, pool.cy
            if hitTest(dx, dy, cx, cy, POOL_W, POOL_H) then
                if pool.unlocked == false then
                    TavernPopups.showFloatText("进入地狱难度后开放", cx, cy - 40)
                    return true
                end
                if state.selectedPool ~= i then
                    state.selectedPool = i
                    syncDisplayData()
                    require("systems.GameSFX").playUIMove(2)
                end
                print("[TavernPage] 选中池子: " .. pool.name)
                return true
            end
        end
    end

    -- 消费掉面板区域的触摸，不透传
    return true
end

-- ======================== update ========================

--- 每帧更新（需要外部在 HandleUpdate 中调用）
---@param dt number
function TavernPage.update(dt)
    -- 超时检测必须在 state.open 保护之前运行：
    -- 若页面关闭时发生断线重连，锁不会被 onServerDisconnect 之外的路径释放，
    -- 放在保护外确保任何情况下都不会永久卡死。
    if pendingGachaPull and (time.elapsedTime - pendingGachaPullTime) >= GACHA_PULL_TIMEOUT then
        pendingGachaPull = false
        print("[TavernPage] 招募请求超时，已释放锁（等待" .. GACHA_PULL_TIMEOUT .. "秒无响应）")
        if state.open then
            TavernPopups.showFloatText("网络超时，请重试", DESIGN_W * 0.5, DESIGN_H * 0.42)
        end
    end

    if not state.open then return end

    -- 弹窗关闭动画完成检测
    TavernPopups.update(dt)

    RecruitAnim.update(dt)

    -- 商店标签页更新（购买弹窗动画等）
    TavernShopPage.update(dt)
end

-- ======================== 数据设置 ========================

--- 服务端招募结果回调（多人模式）
---@param data table handleActionResult 传来的完整 data
function TavernPage.onActionResult(data)
    print("[TavernPage] onActionResult called action=" .. tostring(data.action) .. " success=" .. tostring(data.success) .. " pendingWas=" .. tostring(pendingGachaPull))
    -- 酒馆商店购买响应
    if data.action == Protocol.ACTION_TYPES.TAVERN_SHOP_BUY
        or TavernShopPage.isPendingBuy() then
        TavernShopPage.onBuyResult(data)
        return
    end

    -- 正向守卫：只有两种情况才操作 pendingGachaPull：
    --   1. action == gacha_pull（无论 success 真假）——正常招募响应
    --   2. success == false（服务端内部错误，action 可能为 nil）——兜底释放锁，防止卡死
    -- 其他任何 action（claim_offline_rewards 等）直接 return，不得误杀 pendingGachaPull。
    -- 铁律：正向白名单，防止未来新增 action 绕过守卫。
    if data.action ~= Protocol.ACTION_TYPES.GACHA_PULL and data.success ~= false then
        return
    end

    pendingGachaPull = false
    print("[TavernPage] pendingGachaPull released (action=" .. tostring(data.action) .. " success=" .. tostring(data.success) .. ")")

    if not data.success then
        local msg = TavernPopups.formatGachaFailReason(data.reason)
        TavernPopups.showFloatText(msg, DESIGN_W * 0.5, DESIGN_H * 0.42)
        print("[TavernPage] 招募失败: " .. tostring(data.reason))
        return
    end

    -- 只处理包含 gachaResults 的成功响应
    if not data.gachaResults then return end

    -- 记录历史
    TavernPopups.recordHistory(data.gachaResults, data.poolId or getSelectedPoolId())

    -- 同步保底计数
    if data.pity then
        if isStellarPoolId(data.pity.poolId) then
            stellarPityOverride = {
                sinceUR  = data.pity.sinceUR,
                sinceSSR = data.pity.sinceSSR,
                sinceSR  = data.pity.sinceSR,
            }
        else
            GachaSystem.setPityCounts(data.pity.sinceSR, data.pity.sinceSSR)
        end
    end

    -- 服务端已通过 markDirty 推送了 currency / heroes 数据，
    -- ClientDispatcher 订阅会自动同步 GameState，这里只需刷新显示
    syncDisplayData()

    -- 新手引导：记录本次招募到的第一个英雄 ID，供 character_new_hero 热点定位
    -- 注意：不加 isActive() 守卫——引导组9在离开酒馆后才激活，
    -- 但 newHeroId_ 需要在此处提前记录，否则激活时已拿不到数据
    do
        local _TM2 = require("systems.TutorialManager")
        for _, r in ipairs(data.gachaResults) do
            if r.type == "hero" and r.heroId then
                _TM2.setNewHeroId(r.heroId)
                break
            end
        end
        -- 通知引导组8的 invisible 步骤：招募结果已返回，可结束引导
        _TM2.notifyEvent("gacha10_complete")
    end

    -- 播放招募动画
    RecruitAnim.start(data.gachaResults, function()
        syncDisplayData()
        print("[TavernPage] 招募动画结束（服务端模式）")
    end)
end

-- ======================== 拖拽/滚动支持 ========================

--- 拖拽开始
function TavernPage.handleDragBegin(dx, dy)
    if not state.open or state.closing then return end
    if state.tab == "shop" then
        TavernShopPage.handleDragBegin(dx, dy)
    else
        TavernPopups.handleDragBegin(dx, dy)
    end
end

--- 拖拽移动
function TavernPage.handleDragMove(dx, dy)
    if not state.open or state.closing then return end
    if state.tab == "shop" then
        TavernShopPage.handleDragMove(dx, dy)
    else
        TavernPopups.handleDragMove(dx, dy)
    end
end

--- 拖拽结束
function TavernPage.handleDragEnd(dx, dy)
    if not state.open or state.closing then return end
    if state.tab == "shop" then
        TavernShopPage.handleDragEnd(dx, dy)
    else
        TavernPopups.handleDragEnd(dx, dy)
    end
end

--- 鼠标滚轮
function TavernPage.handleScroll(wheel)
    if not state.open or state.closing then return end
    if state.tab == "shop" then
        TavernShopPage.handleScroll(wheel)
    else
        TavernPopups.handleScroll(wheel)
    end
end

--- 设置保底数据（供外部调用）
function TavernPage.setPityData(remain, rank)
    state.pityRemain = remain or state.pityRemain
    state.pityRank   = rank or state.pityRank
end

--- 刷新显示数据（供外部模块在数据变化后调用，如指定招募确认后）
function TavernPage.refreshDisplay()
    syncDisplayData()
end

--- 设置指定招募显示状态（供 TargetRecruitPanel 确认后乐观更新）
---@param heroId number|nil
---@param heroName string|nil
function TavernPage.setTargetRecruit(heroId, heroName)
    -- remain 继承逻辑：之前没有指定或已用完 → 设为满值；否则保持当前值
    local prevTarget = state.targetRecruitHeroId
    local prevRemain = state.targetRecruitRemain or 0
    if not prevTarget or prevRemain <= 0 then
        state.targetRecruitRemain = 3
    end
    state.targetRecruitHeroId = heroId
    state.targetRecruitName   = heroName
end

--- 设置星辉指定UP显示状态（供 TargetRecruitPanel 确认后乐观更新）
---@param heroId number|nil
---@param heroName string|nil
function TavernPage.setStellarTargetUp(heroId, heroName)
    state.stellarTargetUpHeroId = heroId
    state.stellarTargetUpName = heroName
    if vg_ and heroId then
        reloadUpPortrait(vg_, heroId)
    end
end

--- 设置资源数据（供外部调用）
function TavernPage.setResources(tickets, diamonds)
    state.ticketCount  = tickets or state.ticketCount
    state.diamondCount = diamonds or state.diamondCount
end

--- 轮换星辉池 UP 角色（更新配置并刷新立绘）
---@param vg number|nil NanoVG 上下文；传入则立即重载 KCLH 图
---@param heroId number
---@param opts table|nil { name:string, endTime:number }
function TavernPage.setStellarUpHero(vg, heroId, opts)
    UrGachaConfig.setUpHero(heroId, opts)
    refreshPoolMeta()
    if vg then
        reloadUpPortrait(vg)
    end
    if state.open then
        syncDisplayData()
    end
end

--- 当前选中的招募池 id（"standard" | "stellar"）
---@return string
function TavernPage.getSelectedPoolId()
    return getSelectedPoolId()
end

--- 服务器断线通知（由 Client.lua 在 handleServerDisconnected 中调用）
--- WiFi 场景：Android Doze/WiFi sleep 会断开 WebSocket，S_ActionResult 不补发，
--- 若不在此释放锁，pendingGachaPull 将在重连后永久为 true。
--- 玩家招募已在服务端完成，重连后 pushFullState 会带来新英雄数据，
--- 可前往背包查看。
function TavernPage.onServerDisconnect()
    if pendingGachaPull then
        pendingGachaPull = false
        print("[TavernPage] 服务器断线，释放招募锁（如招募已完成请查看背包）")
        if state.open then
            TavernPopups.showFloatText("网络断开，如已招募请查看背包", DESIGN_W * 0.5, DESIGN_H * 0.42)
        end
    end
end

return TavernPage
