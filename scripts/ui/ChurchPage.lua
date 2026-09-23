-- ChurchPage.lua
-- 教堂界面：转职 / 神器 两个 Tab（天赋已独立到 TalentPage / 终焉古树）
-- 从城镇页面点击教堂进入的二级界面

---@diagnostic disable: undefined-global
-- nvgSpineCreate / nvgSpineRender 是引擎内置全局函数（NanoVG Spine 扩展）

local GameConfig       = require("config.GameConfig")
local DarkIcon       = require("core.DarkIcon")  -- [暗黑化 P0]
local DrawUtil         = require("core.DrawUtil")
local TownPageChrome   = require("ui.TownPageChrome")
local drawTextStroke   = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice    = DrawUtil.drawNineSlice
local hitTest          = DrawUtil.hitTest
local HC               = require("config.HeroConfig")
local CC               = require("config.ClassConfig")
local CharacterPanel   = require("ui.CharacterPanel")
local AD               = require("systems.AttributeDef")
local GameState        = require("core.GameState")
local NumberUtil       = require("core.NumberUtil")
local TalentStarMap    = require("ui.TalentStarMap")
local SpineCardEffect  = require("ui.SpineCardEffect")
local TalentPanel      = require("ui.ChurchTalentPanel")
local ClassChange      = require("ui.ChurchClassChange")
local ArtifactPanel    = require("ui.ChurchArtifactPanel")
local AVC              = require("config.AdvancementConfig")
local ChurchDraw       = require("ui.ChurchDraw")
local ChurchInput      = require("ui.ChurchInput")
local ChurchRosterDraw = require("ui.ChurchRosterDraw")
local ChurchSlotAnim   = require("ui.ChurchSlotAnim")
local ChurchInit       = require("ui.ChurchInit")
local ChurchBadge      = require("ui.ChurchBadge")
local ChurchResults    = require("ui.ChurchResults")
local ChurchLifecycle  = require("ui.ChurchLifecycle")

-- 懒加载网络模块（避免循环依赖）
local Client_
local Protocol_
local ClientDispatcher_
local function getClient()
    if not Client_ then Client_ = require("network.GameAction") end
    return Client_
end
local function getProtocol()
    if not Protocol_ then Protocol_ = require("shared.Protocol") end
    return Protocol_
end
local function getDispatcher()
    if not ClientDispatcher_ then ClientDispatcher_ = require("network.ClientDispatcher") end
    return ClientDispatcher_
end

local ChurchPage = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量（分组表） ========================

-- 1. 教堂背景图 + 建筑名称
local CHURCH = {
    BG_CX = 540, BG_CY = 1200, BG_W = 1080, BG_H = 2400,
    NAME_BG_CX = 147, NAME_BG_CY = 136, NAME_BG_W = 294, NAME_BG_H = 123,
    NAME_TEXT_CX = 148, NAME_TEXT_CY = 130, NAME_FONT_SIZE = 50,
}

-- 2. 角色选择框
local CHAR_SLOT = {
    CX = 540, CY = 1482, W = 198, H = 438, R = 8,
    PLUS_W = 64, PLUS_H = 64,
}

-- 3. 返回按钮
local BTN_BACK = {
    CX = 958, CY = 1150, W = 184, H = 143,
}

-- 4. Tab 栏 + 滑块（两 Tab：转职 / 神器）
local TAB = {
    BG_CX = 639, BG_CY = 2308, BG_W = 810, BG_H = 143,
    SLIDER_W = 410, SLIDER_H = 143,
    INSET_TOP = 10, INSET_BOTTOM = 10, INSET_LEFT = 70, INSET_RIGHT = 70,
    FONT_SIZE = 40,
    ACTIVE_R = 0xD8, ACTIVE_G = 0xC9, ACTIVE_B = 0xA3,  -- [fix] 深色滑块上深棕不可读 → 骨白
    INACTIVE_R = 255, INACTIVE_G = 255, INACTIVE_B = 255,
    ANIM_DUR = 0.35,
}

-- 5. 两个滑块按钮位置
local TAB_ITEMS = {
    { name = "转职", cx = 439, cy = 2308, textX = 439, textY = 2302 },
    { name = "神器", cx = 839, cy = 2308, textX = 839, textY = 2302 },
}

local TAB_KEYS = { "zhuanzhi", "shenqi" }

-- 6. 动画常量
local ANIM = {
    OPEN_DUR = 0.45,
    CLOSE_DUR = 0.38,
    UPPER_SLIDE_IN = 1200,
    UPPER_SLIDE_OUT = 2500,
    LOWER_SLIDE_DIST = 1600,
    POPUP_DUR = 0.22,
    POPUP_SCALE_FROM = 0.85,
    SLOT_DUR = 0.35,
    SLOT_LIFT = 1010,
    SELECT_DUR = 0.35,
    ROSTER_SLIDE_DUR = 0.30,
    ROSTER_SLIDE_DIST = 1400,
}

-- 7. 角色列表区域（复刻 CharacterPanel 远征队员列表）
local ROSTER = {
    LIST_BG_CX = 540, LIST_BG_W = 1080, LIST_BG_H = 1579,
    MY_HEROES_CX = 540,
    CARD_W = 198, CARD_H = 438, CARD_SPACING = 7, MAX_PER_ROW = 5,
    ROW1_CY = 1291, ROW_SPACING = 543,
    NAME_BG_DY = 253, NAME_BG_W2 = 193, NAME_BG_H2 = 48, NAME_BG_RADIUS = 24,
    TAG_OFFSET_Y = -215,
    SCROLL_TOP = 1050, SCROLL_BOTTOM = 2400,
    POWER_DY = 136, POWER_ICON_SIZE = 36,
    LVL_BADGE_DX = -63, LVL_BADGE_DY = 181, LVL_BADGE_SIZE = 56,
    EXP_BAR_DX = 12, EXP_BAR_DY = 183,
    EXP_BAR_BG_W = 148, EXP_BAR_BG_H = 28, EXP_BAR_PADDING = 4,
    EXP_FILL_LEFT_INSET = 15,
    DEPLOYED_W = 134, DEPLOYED_H = 56, DEPLOYED_DY = -146, DEPLOYED_TXT_DY = -149,
}
-- Computed fields (depend on other ROSTER fields)
ROSTER.LIST_BG_CY = DESIGN_H - ROSTER.LIST_BG_H * 0.5
ROSTER.MY_HEROES_CY = (ROSTER.LIST_BG_CY - ROSTER.LIST_BG_H * 0.5) + 52
ROSTER.DEPLOYED_DX = -ROSTER.CARD_W * 0.5 + 134 * 0.5

-- 战斗力计算跳过的属性（与 CharacterPanel 一致）
local POWER_SKIP = {
    [AD.STR]=true,[AD.AGI]=true,[AD.INT]=true,
    [AD.VIT]=true,[AD.LUK]=true,[AD.SPI]=true,
    [AD.HP]=true,[AD.ATK_INTERVAL]=true,
    [AD.PHYS_RES]=true,[AD.MAG_RES]=true,
}

-- 战斗力缓存（选中角色变更时更新）
local powerCache = { heroId = nil, value = 0 }

--- 清除教堂页战力缓存（共鸣/装备/等级变化后重算）
local function clearPowerCache()
    powerCache.heroId = nil
    powerCache.value = 0
    rosterPowerCache = {}
end

-- 转职布局常量和数据表已迁移至 ChurchClassChange.lua
-- 父模块通过 ClassChange.XXX 访问导出数据

-- 转职数据表已迁移至 ChurchClassChange.lua
-- 通过 ClassChange.CLASS_NUM / ClassChange.ADV2 / ClassChange.FIRST_ADV_BRANCHES 等访问

-- CLASS_DISPLAY_NAMES / FIRST_ADV_BRANCHES / SECOND_ADV_BRANCHES
-- ADV_BRANCH_ATTRS / ADV_BRANCH_TALENT / ADV_COST / CONFIRM
-- → 已迁移至 ChurchClassChange.lua（通过 ClassChange.XXX 访问）

-- ======================== 状态 ========================

local onCloseCallback_ = nil  -- 关闭动画完成后的回调（用于触发离场情景）
local onOpenCallback_  = nil  -- 打开动画完成后的回调（用于触发入场情景）

local state = {
    open       = false,
    closing    = false,
    openTime   = 0,
    closeTime  = 0,
    tab        = "zhuanzhi", -- "zhuanzhi" | "shenqi"
    tabFrom    = "zhuanzhi",
    tabSwitchTime = 0,
    selectedHeroId = nil,    -- 当前选中的角色

    -- 槽位展开状态
    slotExpanded    = false,   -- 是否已展开（显示角色列表）
    slotAnimTime    = 0,       -- 展开/收起动画开始时间
    slotAnimDir     = 0,       -- 1=展开中 -1=收起中 0=静止
    slotLiftProgress = 0,      -- 当前上移进度 0~1

    -- 角色列表滚动
    rosterScrollY   = 0,
    rosterDragging  = false,
    rosterLastDragY = 0,
    rosterScrollVelocity = 0,

    -- 选择角色飞行动画
    selectAnim      = false,
    selectAnimTime  = 0,
    selectAnimFromX = 0,
    selectAnimFromY = 0,

    -- 角色列表滑入/滑出动画
    rosterSlideDir      = 0,   -- 1=滑入, -1=滑出, 0=静止
    rosterSlideTime     = 0,
    rosterSlideProgress = 0,   -- 0=隐藏, 1=完全显示

    -- 转职确认弹窗
    confirmPopup        = false,  -- 是否显示确认弹窗
    confirmAdvLevel     = 0,      -- 0=基础, 1=一转, 2=二转
    confirmBranchId     = 0,      -- 分支 id
    confirmBranchName   = "",     -- 分支名称
    confirmClassNum     = 1,      -- 职业序号（1~6, 用于背景图）
    confirmOwned        = false,  -- 是否已拥有（已转职/基础职业）

    -- 飘字提示
    floatText           = nil,    -- 飘字文本（nil=不显示）
    floatTextX          = 0,      -- 飘字起始X
    floatTextY          = 0,      -- 飘字起始Y
    floatTextTime       = 0,      -- 飘字开始时间

    -- 天赋面板
    tfZoomSliderValue   = TalentStarMap.getDefaultSliderValue(), -- 默认 1:1
    tfSliderDragging    = false,  -- 是否正在拖拽滑块
    tfMapDragging       = false,  -- 是否正在拖拽星图
    tfLastDragX         = 0,      -- 上次拖拽坐标 X
    tfLastDragY         = 0,      -- 上次拖拽坐标 Y
    tfLastDragTime      = 0,      -- 上次拖拽时间 (用于惯性速度计算)
    tfDragVelocityX     = 0,      -- 拖拽速度 X (屏幕px/s)
    tfDragVelocityY     = 0,      -- 拖拽速度 Y (屏幕px/s)

    -- 天赋详情面板
    tfDetailOpen        = false,  -- 是否显示天赋详情
    tfDetailNodeId      = nil,    -- 当前查看的节点ID
    tfDetailAnimT       = 0,      -- 天赋详情弹窗动画开始时间
    tfDetailClosing     = false,  -- 天赋详情弹窗是否正在关闭

    -- 天赋效果总览弹窗
    tfOverviewOpen      = false,
    tfOverviewClosing   = false,
    tfOverviewAnimT     = 0,
    tfOverviewScrollY   = 0,
    tfOverviewDragging  = false,
    tfOverviewLastDragY = 0,
    tfOverviewLines     = nil,    -- 缓存的展示行

    -- 转职确认弹窗动画
    confirmAnimT        = 0,      -- 转职确认弹窗动画开始时间
    confirmClosing      = false,  -- 转职确认弹窗是否正在关闭
}

-- ======================== 图片资源 ========================

-- 所有图片句柄合并到单表，减少模块级 upvalue 数量
local img = {
    bg          = -1,   -- UI_JTZZBJ.png
    nameBg      = -1,   -- UI_TJP_MC.png（共用）
    btnBack     = -1,   -- UI_AN_FH.png
    tabBg       = -1,   -- UI_AN_1.png
    slider      = -1,   -- UI_AN_2.png
    plus        = -1,   -- UI_ICON_JIA.png
    -- 转职相关
    classBg     = {},    -- classBg[1~6] = nvg image handle
    titleBg     = -1,    -- UI_ZBT1.png
    branchLine  = -1,    -- UI_ZZXT_1Z.png
    branchLine2 = -1,    -- UI_ZZXT_2Z.png（二转分叉线）
    classIcons2 = {},    -- UI_icon_ZY_{序号}.png（按职业序号索引）
    heroCards   = {},    -- 角色卡牌图片缓存
    -- 角色列表
    listBg      = -1,    -- UI_JSJM_0.png
    classIcons  = {},    -- ICON_ZY_1~6.png 职业小图标
    -- 卡片详情
    power       = -1,    -- ICON_ZDL.png 战斗力图标
    lvlBadge    = -1,    -- UI_JSJM_DJ.png 等级徽章
    expBarBg    = -1,    -- UI_JSMB_JYT1.png 经验条背景
    expBarFill  = -1,    -- UI_JSMB_JYT2.png 经验条填充
    deployed    = -1,    -- UI_JSJM_CZZ.png 出战中标识
    -- 转职确认弹窗
    confirmBg   = {},    -- UI_ZYTS_1~6.png 职业提示背景
    confirmBtn  = -1,    -- UI_AN_LV.png 确认按钮
    cancelBtn   = -1,    -- UI_AN_FANG.png 取消按钮（灰色）
    resetConfBg = -1,    -- UI_TY_EJQRK.png 重置确认九宫格背景
    goldCoin    = -1,    -- UI_icon_JB.png 金币图标
    iconUp      = -1,    -- ICON_UP.png 可提升角标（绿色箭头）
    redDot      = -1,    -- ICON_HD.png 红点角标
    -- 资源栏
    resGold     = -1,    -- UI_icon_JB_X.png
    resDiamond  = -1,    -- UI_icon_SJ_X.png
    -- 天赋面板
    tfBg          = -1,  -- UI_JTTF_BJ.png (已废弃，改用 Spine)
    tfBorderGlow  = -1,  -- UI_JTTF_BJGY.png (已废弃，改用 Spine)
    tfPointGlow   = -1,  -- UI_JTTF_HG.png
    tfSliderThumb = -1,  -- UI_JTTF_HK.png
    -- 天赋详情面板背景（按颜色索引）
    tfDetailBg    = {},  -- tfDetailBg["红"]=handle, ...
    tfResetBtn    = -1,  -- UI_AN_HONG.png 单节点重置按钮（红色）
    tfInfoIcon    = -1,  -- UI_icon_TS.png 天赋效果总览（感叹号）
}

-- 列表卡片战斗力缓存 { [heroId] = power }
local rosterPowerCache = {}

-- Spine 天赋背景（spineTfBg）已迁移至 ChurchTalentPanel.lua

-- ======================== 缓动函数（TownPageChrome） ========================
local easeOutCubic   = TownPageChrome.easeOutCubic
local easeInCubic    = TownPageChrome.easeInCubic
local easeInOutCubic = TownPageChrome.easeInOutCubic

-- drawImageCentered / drawNineSlice / hitTest → 已由头部 DrawUtil 导入

--- 获取角色卡牌图片（延迟加载）
local function getHeroCardImage(vg, heroId)
    if img.heroCards[heroId] then return img.heroCards[heroId] end
    local cardImg = nvgCreateImage(vg, "image/角色卡牌/KP_YX_" .. heroId .. ".png", 0)
    img.heroCards[heroId] = cardImg
    return cardImg
end

--- 获取转职职业图标（延迟加载）
local function getClassIcon2(vg, classId)
    local h = img.classIcons2[classId]
    if h ~= nil then return h end
    if not vg or not classId then
        img.classIcons2[classId] = -1
        return -1
    end
    local icon = nvgCreateImage(vg, "image/职业图标/UI_icon_ZY_" .. classId .. ".png", 0)
    img.classIcons2[classId] = icon or -1
    return img.classIcons2[classId]
end

local _badge
local function bindChurchBadge()
    _badge = ChurchBadge.bind({
        HC = HC,
        ClassChange = ClassChange,
        CharacterPanel = CharacterPanel,
        GameState = GameState,
        AVC = AVC,
        ArtifactPanel = ArtifactPanel,
        getDispatcher = getDispatcher,
    })
end

--- 检查指定英雄是否有可用转职（用于入口链路角标）
---@param heroId number
---@return boolean
function ChurchPage.hasAdvanceForHero(heroId)
    if not _badge then bindChurchBadge() end
    return _badge.hasAdvanceForHero(heroId)
end

--- 检查是否有任何拥有的英雄可以转职
---@return boolean
function ChurchPage.hasAnyAdvance()
    if not _badge then bindChurchBadge() end
    return _badge.hasAnyAdvance()
end

--- 检查玩家是否有未使用的天赋点
---@return boolean
function ChurchPage.hasAnyUnusedTalent()
    if not _badge then bindChurchBadge() end
    return _badge.hasAnyUnusedTalent()
end

--- 检查教堂是否需要显示角标（天赋、转职、神器任一满足）
---@return boolean
function ChurchPage.hasAnyChurchBadge()
    if not _badge then bindChurchBadge() end
    return _badge.hasAnyChurchBadge()
end

--- 获取教堂角标的显示信息（区分天赋/神器可提升 vs 仅转职可用）
---@return boolean show, string|nil style
function ChurchPage.getChurchBadgeInfo()
    if not _badge then bindChurchBadge() end
    return _badge.getChurchBadgeInfo()
end

--- 获取拥有的英雄列表（排序：品质高→低，ID升序）
local function getOwnedHeroList()
    local list = {}
    local allIds = HC.getAllIds()
    for _, id in ipairs(allIds) do
        if CharacterPanel.isOwned(id) then
            local hero = HC.get(id)
            local ownData = CharacterPanel.getOwnedHero(id)
            list[#list + 1] = {
                heroId    = id,
                quality   = hero and hero.quality or 1,
                level     = ownData and ownData.level or 1,
                exp       = ownData and ownData.exp or 0,
                maxExp    = ownData and ownData.maxExp or 5,
                advBranch = ownData and ownData.advBranch or nil,
                awakening = ownData and ownData.awakening or nil,
                extraTalent = ownData and ownData.extraTalent or nil,
            }
        end
    end
    -- 排序：品质高→低，同品质按ID升序
    table.sort(list, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.heroId < b.heroId
    end)
    return list
end

local function getRosterScrollMax()
    local count = #getOwnedHeroList()
    if count <= 0 then return 0 end
    local rows = math.ceil(count / ROSTER.MAX_PER_ROW)
    local contentBottom = ROSTER.ROW1_CY + (rows - 1) * ROSTER.ROW_SPACING + ROSTER.NAME_BG_DY + ROSTER.NAME_BG_H2 * 0.5
    return math.max(0, contentBottom - ROSTER.SCROLL_BOTTOM)
end

local function clampRosterScroll()
    local maxScroll = getRosterScrollMax()
    state.rosterScrollY = math.max(0, math.min(maxScroll, state.rosterScrollY or 0))
end

local function isRosterVisible()
    return state.open and not state.closing
       and state.tab == "zhuanzhi"
       and state.slotExpanded
       and state.slotLiftProgress > 0.9
       and state.rosterSlideProgress > 0.5
end

local function isInRosterScrollArea(dx, dy)
    return dx >= 0 and dx <= DESIGN_W and dy >= ROSTER.SCROLL_TOP and dy <= ROSTER.SCROLL_BOTTOM
end

local function resetRosterScrollState()
    state.rosterDragging = false
    state.rosterLastDragY = 0
    state.rosterScrollVelocity = 0
end

-- ensureSpineTfBgLoaded / drawTalentBg / drawTalentContent / openTalentDetail
-- closeTalentDetail / isTfDetailVisible / drawTalentDetailPanel
-- → 已迁移至 ChurchTalentPanel.lua（通过 TalentPanel.xxx 调用）
--
-- drawClassChangeBg / drawBranchOverlay / drawClassChangeContent
-- drawTabContent / openConfirmPopup / closeConfirmPopup / drawClassConfirmPopup
-- → 已迁移至 ChurchClassChange.lua（通过 ClassChange.xxx 调用）
--- 绘制角色列表（一比一复刻角色面板 CharacterPanel 的远征队员列表）
local _rosterDraw
local function bindRosterDraw()
    _rosterDraw = ChurchRosterDraw.bind({
        ROSTER = ROSTER,
        DarkIcon = DarkIcon,
        DrawUtil = DrawUtil,
        CharacterPanel = CharacterPanel,
        HC = HC,
        AD = AD,
        POWER_SKIP = POWER_SKIP,
        ClassChange = ClassChange,
        drawImageCentered = drawImageCentered,
        drawTextStroke = drawTextStroke,
        getHeroCardImage = getHeroCardImage,
        getOwnedHeroList = getOwnedHeroList,
        img = img,
        rosterPowerCache = rosterPowerCache,
        hasAdvanceForHero = ChurchPage.hasAdvanceForHero,
        DESIGN_W = DESIGN_W,
        state = state,
    })
end

local function drawRosterList(vg)
    if not _rosterDraw then bindRosterDraw() end
    return _rosterDraw.drawRosterList(vg)
end

-- ======================== Public API ========================

--- Tab 键名映射到索引
local TAB_MAP = {
    zhuanzhi = 1,
    shenqi   = 2,
}

--- 将存档中的天赋数据同步到 TalentStarMap 渲染状态 + HeroConfig 默认天赋
local function syncTalentLitNodes()
    local d = getDispatcher()
    local talentsData = d.get("talents")
    if not talentsData or not talentsData.litNodes then return end
    TalentStarMap.resetLit()  -- 清空（保留 node 0）
    for _, nodeId in ipairs(talentsData.litNodes) do
        TalentStarMap.setNodeLit(nodeId, true)
    end
    -- 同步到 HeroConfig，使后续 createHero 自动应用天赋加成
    HC.setDefaultLitNodes(talentsData.litNodes)
end

--- 强制从 PlayerStore 刷新天赋星图（重连/操作失败兜底）
function ChurchPage.syncTalentFromStore()
    local ok, TP = pcall(require, "ui.TalentPage")
    if ok and TP and TP.syncTalentFromStore then
        TP.syncTalentFromStore()
        return
    end
    syncTalentLitNodes()
end

local _churchInit
local function bindChurchInit()
    _churchInit = ChurchInit.bind({
        img = img,
        state = state,
        ANIM = ANIM,
        easeOutCubic = easeOutCubic,
        easeInCubic = easeInCubic,
        TalentStarMap = TalentStarMap,
        TalentPanel = TalentPanel,
        ClassChange = ClassChange,
        ArtifactPanel = ArtifactPanel,
        getDispatcher = getDispatcher,
        getClient = getClient,
        getProtocol = getProtocol,
        getClassIcon2 = getClassIcon2,
        syncTalentLitNodes = syncTalentLitNodes,
        clearPowerCache = clearPowerCache,
    })
end

--- 初始化（加载图片资源，仅调用一次）
function ChurchPage.init(vg)
    if not _churchInit then bindChurchInit() end
    return _churchInit.init(vg)
end

local _life
local function bindChurchLifecycle()
    _life = ChurchLifecycle.bind({
        state = state,
        ANIM = ANIM,
        easeOutCubic = easeOutCubic,
        easeInCubic = easeInCubic,
        TalentStarMap = TalentStarMap,
        ArtifactPanel = ArtifactPanel,
        resetRosterScrollState = resetRosterScrollState,
        syncTalentLitNodes = syncTalentLitNodes,
        ensureInit = function()
            if not _churchInit then bindChurchInit() end
            if not _churchInit.isInited() and _churchInit.getVg() then
                ChurchPage.init(_churchInit.getVg())
            end
            return _churchInit.isInited()
        end,
        getOnCloseCallback = function() return onCloseCallback_ end,
        setOnCloseCallback = function(fn) onCloseCallback_ = fn end,
        getOnOpenCallback = function() return onOpenCallback_ end,
        setOnOpenCallback = function(fn) onOpenCallback_ = fn end,
    })
end

--- 打开教堂
function ChurchPage.open()
    if not _life then bindChurchLifecycle() end
    return _life.open()
end

--- 关闭教堂（启动关闭动画）
function ChurchPage.close()
    if not _life then bindChurchLifecycle() end
    return _life.close()
end

--- 注册关闭动画完成后的回调（每次 open 前设置，触发一次后自动清除）
function ChurchPage.setOnCloseCallback(fn)
    if not _life then bindChurchLifecycle() end
    return _life.setOnCloseCallback(fn)
end

--- 注册打开动画完成后的回调（每次 open 前设置，触发一次后自动清除）
function ChurchPage.setOnOpenCallback(fn)
    if not _life then bindChurchLifecycle() end
    return _life.setOnOpenCallback(fn)
end

--- 是否打开
---@return boolean
function ChurchPage.isOpen()
    if not _life then bindChurchLifecycle() end
    return _life.isOpen()
end

--- 强制关闭（跳过动画，用于安全恢复 — 离开 tab4 时调用）
function ChurchPage.forceClose()
    if not _life then bindChurchLifecycle() end
    return _life.forceClose()
end

--- 返回打开/关闭动画进度 (0=完全关闭, 1=完全打开)
function ChurchPage.getAnimProgress()
    if not _life then bindChurchLifecycle() end
    return _life.getAnimProgress()
end

--- 槽位展开/选择/滑动
local _slot
local function bindSlotAnim()
    _slot = ChurchSlotAnim.bind({
        ANIM = ANIM,
        CHAR_SLOT = CHAR_SLOT,
        HC = HC,
        state = state,
        resetRosterScrollState = resetRosterScrollState,
        easeOutCubic = easeOutCubic,
    })
end

local function expandSlot()
    if not _slot then bindSlotAnim() end
    return _slot.expandSlot()
end

local function collapseSlot()
    if not _slot then bindSlotAnim() end
    return _slot.collapseSlot()
end

local function selectHero(heroId, fromCX, fromCY)
    if not _slot then bindSlotAnim() end
    return _slot.selectHero(heroId, fromCX, fromCY)
end

local function updateSlotAnim()
    if not _slot then bindSlotAnim() end
    return _slot.updateSlotAnim()
end

local function updateSelectAnim()
    if not _slot then bindSlotAnim() end
    return _slot.updateSelectAnim()
end

local function updateRosterSlide()
    if not _slot then bindSlotAnim() end
    return _slot.updateRosterSlide()
end

--- 点击/拖拽/滚轮
local _input
local function bindInput()
    _input = ChurchInput.bind({
        ANIM = ANIM,
        CHAR_SLOT = CHAR_SLOT,
        ClassChange = ClassChange,
        TalentPanel = TalentPanel,
        ArtifactPanel = ArtifactPanel,
        TownPageChrome = TownPageChrome,
        TAB_ITEMS = TAB_ITEMS,
        TAB_KEYS = TAB_KEYS,
        TAB = TAB,
        CHURCH = CHURCH,
        ROSTER = ROSTER,
        DESIGN_W = DESIGN_W,
        DESIGN_H = DESIGN_H,
        clampRosterScroll = clampRosterScroll,
        isRosterVisible = isRosterVisible,
        isInRosterScrollArea = isInRosterScrollArea,
        expandSlot = expandSlot,
        collapseSlot = collapseSlot,
        selectHero = selectHero,
        getOwnedHeroList = getOwnedHeroList,
        forceClose = ChurchPage.forceClose,
        closePage = ChurchPage.close,
        resetRosterScrollState = resetRosterScrollState,
        TalentStarMap = TalentStarMap,
        state = state,
        hitTest = hitTest,
    })
end

function ChurchPage.handleInput(dx, dy)
    if not _input then bindInput() end
    return _input.handleInput(dx, dy)
end

function ChurchPage.handleDragBegin(dx, dy)
    if not _input then bindInput() end
    return _input.handleDragBegin(dx, dy)
end

function ChurchPage.handleDragMove(dx, dy)
    if not _input then bindInput() end
    return _input.handleDragMove(dx, dy)
end

function ChurchPage.handleDragEnd(dx, dy)
    if not _input then bindInput() end
    return _input.handleDragEnd(dx, dy)
end

function ChurchPage.handleScroll(wheel, msx, msy)
    if not _input then bindInput() end
    return _input.handleScroll(wheel, msx, msy)
end

--- 绘制教堂界面
local _pageDraw
local function bindPageDraw()
    _pageDraw = ChurchDraw.bind({
        ANIM = ANIM,
        CHURCH = CHURCH,
        CHAR_SLOT = CHAR_SLOT,
        DESIGN_H = DESIGN_H,
        DESIGN_W = DESIGN_W,
        DarkIcon = DarkIcon,
        DrawUtil = DrawUtil,
        GameState = GameState,
        HC = HC,
        NumberUtil = NumberUtil,
        POWER_SKIP = POWER_SKIP,
        ROSTER = ROSTER,
        TAB = TAB,
        TAB_ITEMS = TAB_ITEMS,
        TAB_KEYS = TAB_KEYS,
        TAB_MAP = TAB_MAP,
        TownPageChrome = TownPageChrome,
        clampRosterScroll = clampRosterScroll,
        drawImageCentered = drawImageCentered,
        drawRosterList = drawRosterList,
        drawTextStroke = drawTextStroke,
        easeInCubic = easeInCubic,
        easeInOutCubic = easeInOutCubic,
        easeOutCubic = easeOutCubic,
        getHeroCardImage = getHeroCardImage,
        getRosterScrollMax = getRosterScrollMax,
        img = img,
        powerCache = powerCache,
        hasAnyAdvance = ChurchPage.hasAnyAdvance,
        hasAnyUnusedTalent = function() return false end,
        state = state,
        updateRosterSlide = updateRosterSlide,
        updateSelectAnim = updateSelectAnim,
        updateSlotAnim = updateSlotAnim,
        getOnCloseCallback = function() return onCloseCallback_ end,
        setOnCloseCallback = function(v) onCloseCallback_ = v end,
        getOnOpenCallback = function() return onOpenCallback_ end,
        setOnOpenCallback = function(v) onOpenCallback_ = v end,
    })
end

local function drawPageImpl(vg)
    if not _pageDraw then bindPageDraw() end
    return _pageDraw.drawPageImpl(vg)
end


local _results
local function bindChurchResults()
    _results = ChurchResults.bind({
        state = state,
        ANIM = ANIM,
        CHAR_SLOT = CHAR_SLOT,
        getProtocol = getProtocol,
        ArtifactPanel = ArtifactPanel,
        CharacterPanel = CharacterPanel,
        SpineCardEffect = SpineCardEffect,
        clearPowerCache = clearPowerCache,
    })
end

--- 处理服务端转职操作结果
function ChurchPage.onActionResult(data)
    if not _results then bindChurchResults() end
    return _results.onActionResult(data)
end

--- 预加载天赋背景 Spine（转发给 TalentPage）
---@param vg any NanoVG 上下文
function ChurchPage.preloadSpine(vg)
    local ok, TP = pcall(require, "ui.TalentPage")
    if ok and TP and TP.preloadSpine then
        TP.preloadSpine(vg)
    else
        TalentPanel.preloadSpine(vg)
    end
end

--- [水平滑入] 整页从屏幕边缘滑入/滑出(与中缝返回条同步);0=完全展开
function ChurchPage.getSeamAnim()
    return state.openTime, state.closeTime, ANIM.OPEN_DUR, ANIM.CLOSE_DUR
end

function ChurchPage.draw(vg)
    local ot, ct, od, cd = ChurchPage.getSeamAnim()
    local ox = DrawUtil.seamSlideX(-1, ot, ct, od, cd, 1080)
    if ox ~= 0 then
        nvgSave(vg)
        nvgTranslate(vg, ox, 0)
    end
    drawPageImpl(vg)
    if ox ~= 0 then
        nvgRestore(vg)
    end
end

return ChurchPage
