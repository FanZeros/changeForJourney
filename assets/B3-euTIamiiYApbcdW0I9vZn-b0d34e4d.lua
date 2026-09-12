-- ChurchPage.lua
-- 教堂界面：转职 / 天赋 / 神器 三个 Tab
-- 从城镇页面点击教堂进入的二级界面

---@diagnostic disable: undefined-global
-- nvgSpineCreate / nvgSpineRender 是引擎内置全局函数（NanoVG Spine 扩展）

local GameConfig       = require("config.GameConfig")
local DrawUtil         = require("core.DrawUtil")
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

-- 懒加载网络模块（避免循环依赖）
local Client_
local Protocol_
local ClientDispatcher_
local function getClient()
    if not Client_ then Client_ = require("network.Client") end
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
    CX = 122, CY = 2308, W = 184, H = 143,
}

-- 4. Tab 栏 + 滑块（三 Tab，布局参考铁匠铺）
local TAB = {
    BG_CX = 639, BG_CY = 2308, BG_W = 810, BG_H = 143,
    SLIDER_W = 277, SLIDER_H = 143,
    INSET_TOP = 10, INSET_BOTTOM = 10, INSET_LEFT = 70, INSET_RIGHT = 70,
    FONT_SIZE = 40,
    ACTIVE_R = 0x81, ACTIVE_G = 0x57, ACTIVE_B = 0x3c,
    INACTIVE_R = 255, INACTIVE_G = 255, INACTIVE_B = 255,
    ANIM_DUR = 0.35,
}

-- 5. 三个滑块按钮位置
local TAB_ITEMS = {
    { name = "转职", cx = 372, cy = 2308, textX = 372, textY = 2302 },
    { name = "天赋", cx = 638, cy = 2308, textX = 638, textY = 2302 },
    { name = "神器", cx = 905, cy = 2308, textX = 905, textY = 2302 },
}

local TAB_KEYS = { "zhuanzhi", "tianfu", "shenqi" }

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

-- 7. 角色列表区域（复刻 CharacterPanel 冒险家列表）
local ROSTER = {
    LIST_BG_CX = 540, LIST_BG_W = 1080, LIST_BG_H = 1579,
    MY_HEROES_CX = 540, MY_HEROES_CY = 996,
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
ROSTER.DEPLOYED_DX = -ROSTER.CARD_W * 0.5 + 134 * 0.5

-- 战斗力计算跳过的属性（与 CharacterPanel 一致）
local POWER_SKIP = {
    [AD.STR]=true,[AD.AGI]=true,[AD.INT]=true,
    [AD.VIT]=true,[AD.LUK]=true,[AD.SPI]=true,
    [AD.HP]=true,[AD.ATK_INTERVAL]=true,
    [AD.PHYS_RES]=true,[AD.MAG_RES]=true,
}

-- 战斗力缓存（选中角色变更时更新）
local cachedPowerHeroId = nil
local cachedPowerValue  = 0

--- 清除教堂页战力缓存（共鸣/装备/等级变化后重算）
local function clearPowerCache()
    cachedPowerHeroId = nil
    cachedPowerValue = 0
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
    tab        = "tianfu",   -- "tianfu" | "zhuanzhi"
    tabFrom    = "tianfu",
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
    tfZoomSliderValue   = 0,      -- 缩放滑块值 0(顶)~1(底)
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

-- ======================== 缓动函数 ========================

local function easeOutCubic(t)
    t = t - 1
    return t * t * t + 1
end

local function easeInCubic(t)
    return t * t * t
end

local function easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local f = 2 * t - 2
        return 0.5 * f * f * f + 1
    end
end

-- drawImageCentered / drawNineSlice / hitTest → 已由头部 DrawUtil 导入

--- 获取角色卡牌图片（延迟加载）
local function getHeroCardImage(vg, heroId)
    if img.heroCards[heroId] then return img.heroCards[heroId] end
    local cardImg = nvgCreateImage(vg, "image/角色卡牌/KP_YX_" .. heroId .. ".png", 0)
    img.heroCards[heroId] = cardImg
    return cardImg
end

--- 检查指定英雄是否有可用转职（用于入口链路角标）
--- 一转条件：level >= firstLevel 且尚未一转 且金币足够
--- 二转条件：level >= secondLevel 且已一转但尚未二转 且金币足够
---@param heroId number
---@return boolean
function ChurchPage.hasAdvanceForHero(heroId)
    local heroCfg = HC.get(heroId)
    if not heroCfg then return false end
    local classId = heroCfg.classId
    -- 该职业需要有转职分支
    if not ClassChange.FIRST_ADV_BRANCHES[classId] then return false end
    -- 需要已拥有
    local ownData = CharacterPanel.getOwnedHero(heroId)
    if not ownData then return false end
    local heroLevel = ownData.level or 1
    local advBranch = ownData.advBranch
    local gold = GameState.getGold()
    -- 一转可用：等级达标 且 尚未一转 且 金币足够
    local cost1 = AVC.COST[1]
    if heroLevel >= ClassChange.ADV2.firstLevel and (not advBranch or not advBranch.first)
       and cost1 and gold >= cost1.gold then
        return true
    end
    -- 二转可用：等级达标 且 已一转 且 尚未二转 且 金币足够
    local cost2 = AVC.COST[2]
    if heroLevel >= ClassChange.ADV2.secondLevel and advBranch and advBranch.first and not advBranch.second
       and cost2 and gold >= cost2.gold then
        return true
    end
    return false
end

--- 检查是否有任何拥有的英雄可以转职
---@return boolean
function ChurchPage.hasAnyAdvance()
    local allIds = HC.getAllIds()
    for _, id in ipairs(allIds) do
        if CharacterPanel.isOwned(id) and CharacterPanel.isHeroDeployed(id) and ChurchPage.hasAdvanceForHero(id) then
            return true
        end
    end
    return false
end

--- 检查玩家是否有未使用的天赋点
---@return boolean
function ChurchPage.hasAnyUnusedTalent()
    local talentsData = getDispatcher().get("talents")
    local playerData  = getDispatcher().get("player")
    local litCount   = (talentsData and talentsData.litNodes) and #talentsData.litNodes or 1
    local usedPoints = litCount - 1
    local maxPoints  = (playerData and playerData.level) or 1
    local remaining  = maxPoints - usedPoints
    return remaining > 0
end

--- 检查教堂是否需要显示角标（天赋、转职、神器任一满足）
---@return boolean
function ChurchPage.hasAnyChurchBadge()
    return ChurchPage.hasAnyUnusedTalent() or ChurchPage.hasAnyAdvance() or ArtifactPanel.canUpgradeAnyArtifact()
end

--- 获取教堂角标的显示信息（区分天赋/神器可提升 vs 仅转职可用）
--- 天赋可用或神器可提升 → 绿色箭头（默认）；仅转职可用 → 红点；都无 → 不显示
---@return boolean show, string|nil style
function ChurchPage.getChurchBadgeInfo()
    if ChurchPage.hasAnyUnusedTalent() or ArtifactPanel.canUpgradeAnyArtifact() then
        return true, nil        -- 绿色箭头
    elseif ChurchPage.hasAnyAdvance() then
        return true, "redDot"   -- 红点
    else
        return false, nil
    end
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
--- 绘制角色列表（一比一复刻角色面板 CharacterPanel 的冒险家列表）
local function drawRosterList(vg)
    local ownedList = getOwnedHeroList()
    local rosterCount = #ownedList

    -- 1) 列表背景图（与角色面板相同的 UI_JSJM_0.png）
    drawImageCentered(vg, img.listBg, ROSTER.LIST_BG_CX, ROSTER.LIST_BG_CY, ROSTER.LIST_BG_W, ROSTER.LIST_BG_H, 1.0)

    -- 2) "选择冒险家"提示（原战斗力位置，标题上方）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    local listTopY = ROSTER.LIST_BG_CY - ROSTER.LIST_BG_H * 0.5
    nvgText(vg, ROSTER.MY_HEROES_CX, listTopY + 36, "选择", nil)

    -- 3) "我的冒险家"标题（42px 棕色 0x7b5339）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x7b, 0x53, 0x39, 255))
    nvgText(vg, ROSTER.MY_HEROES_CX, ROSTER.MY_HEROES_CY, "我的冒险家", nil)

    if rosterCount == 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
        nvgText(vg, 540, ROSTER.ROW1_CY, "暂无冒险家", nil)
        return
    end

    -- 3) 角色卡片行（可滚动，裁剪到可视范围；用 Intersect 保留外层动画裁剪）
    nvgSave(vg)
    nvgIntersectScissor(vg, 0, ROSTER.SCROLL_TOP, DESIGN_W, ROSTER.SCROLL_BOTTOM - ROSTER.SCROLL_TOP)

    local scrollY = state.rosterScrollY
    for idx = 1, rosterCount do
        local entry = ownedList[idx]
        local heroCfg = HC.get(entry.heroId)
        if not heroCfg then goto continueRoster end

        -- 确定行列
        local row = math.ceil(idx / ROSTER.MAX_PER_ROW)
        local col = idx - (row - 1) * ROSTER.MAX_PER_ROW    -- 1~5

        -- 当前行有多少张卡（最后一行可能不满）
        local rowStart = (row - 1) * ROSTER.MAX_PER_ROW + 1
        local rowEnd   = math.min(row * ROSTER.MAX_PER_ROW, rosterCount)
        local rowCount = rowEnd - rowStart + 1

        -- 行的 Y 中心（应用滚动偏移）
        local rowCY = ROSTER.ROW1_CY + (row - 1) * ROSTER.ROW_SPACING - scrollY

        -- 快速跳过完全不可见的行
        local cardTop    = rowCY - ROSTER.CARD_H * 0.5 + ROSTER.TAG_OFFSET_Y
        local cardBottom = rowCY + ROSTER.NAME_BG_DY + ROSTER.NAME_BG_H2 * 0.5
        if cardBottom < ROSTER.SCROLL_TOP or cardTop > ROSTER.SCROLL_BOTTOM then
            goto continueRoster
        end

        -- 水平居中分布（按实际卡片数居中）
        local totalW = rowCount * ROSTER.CARD_W + (rowCount - 1) * ROSTER.CARD_SPACING
        local startCX = (DESIGN_W - totalW) * 0.5 + ROSTER.CARD_W * 0.5
        local cx = startCX + (col - 1) * (ROSTER.CARD_W + ROSTER.CARD_SPACING)
        local cy = rowCY

        -- a) 角色卡片
        local cardImg = getHeroCardImage(vg, entry.heroId)
        drawImageCentered(vg, cardImg, cx, cy, ROSTER.CARD_W, ROSTER.CARD_H, 1.0)

        -- b) 职业图标（左上角，60x60）
        local iconIdx = ClassChange.CLASS_NUM[heroCfg.classId]
        if iconIdx and img.classIcons[iconIdx] then
            drawImageCentered(vg, img.classIcons[iconIdx], cx, cy + ROSTER.TAG_OFFSET_Y, 60, 60, 1.0)
        end

        -- c) 战斗力图标+数值（居中于卡片）
        if not rosterPowerCache[entry.heroId] then
            local pw = 0
            local statLevel = entry.level or 1
            local heroUnit = HC.createHero(entry.heroId, statLevel, entry.advBranch, entry.awakening)
            if heroUnit and heroUnit.attrs then
                local a = heroUnit.attrs
                CharacterPanel.applyEquippedItems(a, entry.heroId)
                for key, meta in pairs(AD.META) do
                    if not POWER_SKIP[key] and meta.valueModel and meta.valueModel > 0 then
                        local val = a:get(key)
                        if meta.dataType == AD.TYPE_PCT then
                            pw = pw + val * (meta.valueModel / 100)
                        else
                            pw = pw + val * meta.valueModel
                        end
                    end
                end
            end
            rosterPowerCache[entry.heroId] = math.floor(pw + 0.5)
        end
        local rPower = rosterPowerCache[entry.heroId] or 0
        local rPowerStr = tostring(rPower)
        local POWER_GAP = 4
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        local rptW = nvgTextBounds(vg, 0, 0, rPowerStr)
        local rpcW = ROSTER.POWER_ICON_SIZE + POWER_GAP + rptW
        local rpcX = cx - rpcW * 0.5
        drawImageCentered(vg, img.power, rpcX + ROSTER.POWER_ICON_SIZE * 0.5,
            cy + ROSTER.POWER_DY, ROSTER.POWER_ICON_SIZE, ROSTER.POWER_ICON_SIZE, 1.0)
        drawTextStroke(vg, rpcX + ROSTER.POWER_ICON_SIZE + POWER_GAP,
            cy + ROSTER.POWER_DY, rPowerStr,
            30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            247, 254, 119, 4)

        -- d) 经验条
        local expBarCX = cx + ROSTER.EXP_BAR_DX
        local expBarCY = cy + ROSTER.EXP_BAR_DY
        drawImageCentered(vg, img.expBarBg, expBarCX, expBarCY, ROSTER.EXP_BAR_BG_W, ROSTER.EXP_BAR_BG_H, 1.0)
        local expProgress = (entry.maxExp > 0) and (entry.exp / entry.maxExp) or 0
        expProgress = math.max(0, math.min(1, expProgress))
        local fillW = ROSTER.EXP_BAR_BG_W - ROSTER.EXP_BAR_PADDING * 2 - ROSTER.EXP_FILL_LEFT_INSET
        local fillH = ROSTER.EXP_BAR_BG_H - ROSTER.EXP_BAR_PADDING * 2
        local fillX = expBarCX - ROSTER.EXP_BAR_BG_W * 0.5 + ROSTER.EXP_BAR_PADDING + ROSTER.EXP_FILL_LEFT_INSET
        local fillY = expBarCY - ROSTER.EXP_BAR_BG_H * 0.5 + ROSTER.EXP_BAR_PADDING
        local clipW = fillW * expProgress
        if clipW > 0 and img.expBarFill >= 0 then
            nvgSave(vg)
            nvgIntersectScissor(vg, fillX, fillY, clipW, fillH)
            local paint = nvgImagePattern(vg, fillX, fillY, fillW, fillH, 0, img.expBarFill, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, fillX, fillY, fillW, fillH)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
            nvgRestore(vg)
        end

        -- e) 等级徽章（与角色面板一致：显示有效等级，含共鸣）
        local badgeLevel = entry.level or 1
        local badgeCX = cx + ROSTER.LVL_BADGE_DX
        local badgeCY = cy + ROSTER.LVL_BADGE_DY
        drawImageCentered(vg, img.lvlBadge, badgeCX, badgeCY, ROSTER.LVL_BADGE_SIZE, ROSTER.LVL_BADGE_SIZE, 1.0)
        drawTextStroke(vg, badgeCX, badgeCY, tostring(badgeLevel),
            28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)

        -- f) 角色名背景（纯黑矩形，10%不透明度，圆角24）
        local nameBgCY = cy + ROSTER.NAME_BG_DY
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - ROSTER.NAME_BG_W2 * 0.5, nameBgCY - ROSTER.NAME_BG_H2 * 0.5,
            ROSTER.NAME_BG_W2, ROSTER.NAME_BG_H2, ROSTER.NAME_BG_RADIUS)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
        nvgFill(vg)

        -- g) 角色名文字（白色，黑描边4）
        drawTextStroke(vg, cx, nameBgCY, heroCfg.name,
            28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4)

        -- h) 出战中标识
        if CharacterPanel.isHeroDeployed(entry.heroId) then
            drawImageCentered(vg, img.deployed, cx + ROSTER.DEPLOYED_DX, cy + ROSTER.DEPLOYED_DY, ROSTER.DEPLOYED_W, ROSTER.DEPLOYED_H, 1.0)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 28)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, cx + ROSTER.DEPLOYED_DX, cy + ROSTER.DEPLOYED_TXT_DY, "出战中", nil)
        end

        -- i) 可转职角标（右上角 ICON_UP 40x40）
        if ChurchPage.hasAdvanceForHero(entry.heroId) and img.iconUp >= 0 then
            local upSize = 40
            local upX = cx + ROSTER.CARD_W * 0.5 - upSize * 0.5 - 2
            local upY = cy - ROSTER.CARD_H * 0.5 + upSize * 0.5 + 2
            drawImageCentered(vg, img.iconUp, upX, upY, upSize, upSize, 1.0)
        end

        ::continueRoster::
    end

    nvgResetScissor(vg)
    nvgRestore(vg)
end

-- ======================== Public API ========================

--- Tab 键名映射到索引
local TAB_MAP = {
    zhuanzhi = 1,
    tianfu   = 2,
    shenqi   = 3,
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
    syncTalentLitNodes()
end

--- 初始化（加载图片资源，仅调用一次）
function ChurchPage.init(vg)
    img.bg       = nvgCreateImage(vg, "image/UI_JTZZBJ.png", 0)
    img.nameBg   = nvgCreateImage(vg, "image/UI_TJP_MC.png", 0)
    img.btnBack  = nvgCreateImage(vg, "image/UI_AN_FH.png", 0)
    img.tabBg    = nvgCreateImage(vg, "image/UI_AN_1.png", 0)
    img.slider   = nvgCreateImage(vg, "image/UI_AN_2.png", 0)
    img.plus     = nvgCreateImage(vg, "image/UI_ICON_JIA.png", 0)

    -- 转职相关图片
    for i = 1, 6 do
        img.classBg[i] = nvgCreateImage(vg, "image/UI_ZZBJ_" .. i .. ".png", 0)
    end
    img.titleBg    = nvgCreateImage(vg, "image/UI_ZBT1.png", 0)
    img.branchLine  = nvgCreateImage(vg, "image/UI_ZZXT_1Z.png", 0)
    img.branchLine2 = nvgCreateImage(vg, "image/UI_ZZXT_2Z.png", 0)
    -- 加载所有职业图标（基础1~6、一转101~112、二转201~224）
    local classIconIds = {
        1, 2, 3, 4, 5, 6,                                         -- 基础职业
        101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, -- 一转
        201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, -- 二转
        213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224,
    }
    for _, cid in ipairs(classIconIds) do
        img.classIcons2[cid] = nvgCreateImage(vg, "image/职业图标/UI_icon_ZY_" .. cid .. ".png", 0)
    end

    -- 角色列表背景（与角色面板相同）
    img.listBg = nvgCreateImage(vg, "image/UI_JSJM_0.png", 0)
    -- 职业小图标（角色卡牌左上角）
    for i = 1, 6 do
        img.classIcons[i] = nvgCreateImage(vg, "image/ICON_ZY_" .. i .. ".png", 0)
    end

    -- 卡片详情图片（与角色面板相同）
    img.power      = nvgCreateImage(vg, "image/ICON_ZDL.png", 0)
    img.lvlBadge   = nvgCreateImage(vg, "image/UI_JSJM_DJ.png", 0)
    img.expBarBg   = nvgCreateImage(vg, "image/UI_JSMB_JYT1.png", 0)
    img.expBarFill = nvgCreateImage(vg, "image/UI_JSMB_JYT2.png", 0)
    img.deployed   = nvgCreateImage(vg, "image/UI_JSJM_CZZ.png", 0)

    -- 转职确认弹窗图片
    for i = 1, 6 do
        img.confirmBg[i] = nvgCreateImage(vg, "image/UI_ZYTS_" .. i .. ".png", 0)
    end
    img.confirmBtn  = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    img.cancelBtn   = nvgCreateImage(vg, "image/UI_AN_FANG.png", 0)
    img.resetConfBg = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    img.goldCoin    = nvgCreateImage(vg, "image/UI_icon_JB.png", 0)
    img.iconUp     = nvgCreateImage(vg, "image/ICON_UP.png", 0)
    img.redDot     = nvgCreateImage(vg, "image/ICON_HD.png", 0)
    img.resGold    = nvgCreateImage(vg, "image/UI_icon_JB_X.png", 0)
    img.resDiamond = nvgCreateImage(vg, "image/UI_icon_SJ_X.png", 0)

    -- 天赋面板图片
    img.tfBg          = nvgCreateImage(vg, "image/UI_JTTF_BJ.png", 0)
    img.tfBorderGlow  = nvgCreateImage(vg, "image/UI_JTTF_BJGY.png", 0)
    img.tfPointGlow   = nvgCreateImage(vg, "image/UI_JTTF_HG.png", 0)
    img.tfSliderThumb = nvgCreateImage(vg, "image/UI_JTTF_HK.png", 0)

    -- 天赋详情面板背景（5种颜色）
    local colorFileMap = { ["红"]="HONG", ["绿"]="LV", ["黄"]="HUANG", ["蓝"]="LAN", ["紫"]="ZI" }
    for colorName, fileSuffix in pairs(colorFileMap) do
        img.tfDetailBg[colorName] = nvgCreateImage(vg, "image/UI_TFWBK_" .. fileSuffix .. ".png", 0)
    end

    img.tfResetBtn = nvgCreateImage(vg, "image/UI_AN_HONG.png", 0)
    img.tfInfoIcon = nvgCreateImage(vg, "image/UI_icon_TS.png", 0)

    -- 天赋星图初始化
    TalentStarMap.init(vg)

    -- 订阅天赋数据变更，自动同步星图渲染状态 + 刷新角标
    getDispatcher().subscribe("talents", function()
        syncTalentLitNodes()
        clearPowerCache()
        local okBN, BN = pcall(require, "ui.BottomNav")
        if okBN and BN and BN.refreshTownBadge then
            BN.refreshTownBadge()
        end
    end)

    -- 订阅玩家数据变更（升级 → 天赋点上限增加 → 刷新角标）
    getDispatcher().subscribe("player", function()
        clearPowerCache()
        local okBN, BN = pcall(require, "ui.BottomNav")
        if okBN and BN and BN.refreshTownBadge then
            BN.refreshTownBadge()
        end
    end)

    -- 订阅英雄数据变更（等级/共鸣变化 → 刷新战力缓存）
    getDispatcher().subscribe("heroes", function()
        clearPowerCache()
    end)

    -- 订阅装备变更（穿戴/卸下影响战力预览）
    getDispatcher().subscribe("equipment", function()
        clearPowerCache()
    end)

    -- 构造共享上下文，注入到子模块
    local ctx = {
        state            = state,
        img              = img,
        easeOutCubic     = easeOutCubic,
        easeInCubic      = easeInCubic,
        POPUP_ANIM_DUR   = ANIM.POPUP_DUR,
        POPUP_SCALE_FROM = ANIM.POPUP_SCALE_FROM,
        getClient        = getClient,
        getProtocol      = getProtocol,
        getDispatcher    = getDispatcher,
    }
    TalentPanel.setContext(ctx)
    ClassChange.setContext(ctx)
    ArtifactPanel.setContext(ctx)
    ArtifactPanel.init(vg)

    print("[ChurchPage] init OK")
end

--- 打开教堂
function ChurchPage.open()
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    require("systems.GameSFX").playUIMove(1)
    state.tab = "zhuanzhi"
    state.tabFrom = "zhuanzhi"
    state.tabSwitchTime = 0
    state.selectedHeroId = nil
    state.slotExpanded = false
    state.slotAnimTime = 0
    state.slotAnimDir = 0
    state.slotLiftProgress = 0
    state._deferClearHero = false
    state.rosterScrollY = 0
    resetRosterScrollState()
    -- 天赋面板状态重置
    state.tfZoomSliderValue = 0
    state.tfSliderDragging = false
    state.tfMapDragging = false
    state.tfLastDragTime = 0
    state.tfDragVelocityX = 0
    state.tfDragVelocityY = 0
    state.tfDetailOpen = false
    state.tfDetailNodeId = nil
    state.tfDetailClosing = false
    state.confirmClosing = false
    -- 重置星图视角到原点
    TalentStarMap.resetCamera()
    -- 从存档同步天赋点亮状态到星图
    syncTalentLitNodes()
    ArtifactPanel.reset()
    print("[ChurchPage] 打开教堂")
end

--- 关闭教堂（启动关闭动画）
function ChurchPage.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    print("[ChurchPage] 关闭教堂（动画）")
end

--- 注册关闭动画完成后的回调（每次 open 前设置，触发一次后自动清除）
function ChurchPage.setOnCloseCallback(fn)
    onCloseCallback_ = fn
end

--- 注册打开动画完成后的回调（每次 open 前设置，触发一次后自动清除）
function ChurchPage.setOnOpenCallback(fn)
    onOpenCallback_ = fn
end

--- 是否打开
---@return boolean
function ChurchPage.isOpen()
    return state.open
end

--- 强制关闭（跳过动画，用于安全恢复 — 离开 tab4 时调用）
function ChurchPage.forceClose()
    if not state.open then return end
    print("[ChurchPage] forceClose: 跳过动画强制关闭 (closing=" .. tostring(state.closing) .. ")")
    state.open = false
    state.closing = false
end

--- 返回打开/关闭动画进度 (0=完全关闭, 1=完全打开)
--- 用于 Client.lua 在动画期间渐变隐藏底部导航栏
function ChurchPage.getAnimProgress()
    if not state.open then return 0 end
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        local rawT = math.min(1.0, elapsed / ANIM.CLOSE_DUR)
        return 1 - easeInCubic(rawT)
    else
        local elapsed = time.elapsedTime - state.openTime
        local rawT = math.min(1.0, elapsed / ANIM.OPEN_DUR)
        return easeOutCubic(rawT)
    end
end

--- 展开槽位（点击空槽位后）
local function expandSlot()
    if state.slotExpanded then return end
    state.slotAnimDir = 1
    state.slotAnimTime = time.elapsedTime
    state.slotExpanded = true
    state.rosterScrollY = 0
    resetRosterScrollState()
    -- 列表随槽位上移一起显示（不需要单独滑入）
    state.rosterSlideProgress = 1.0
    state.rosterSlideDir = 0
    print("[ChurchPage] 展开角色列表")
end

--- 收起槽位
local function collapseSlot()
    if not state.slotExpanded then return end
    state.slotAnimDir = -1
    state.slotAnimTime = time.elapsedTime
    state.slotExpanded = false
    print("[ChurchPage] 收起角色列表")
end

--- 选择英雄放入槽位（带飞行动画 + 列表滑出）
local function selectHero(heroId, fromCX, fromCY)
    state.selectedHeroId = heroId
    state.slotAnimDir = 0
    -- slotLiftProgress 保持 1.0，不动

    -- 启动卡片飞行动画
    state.selectAnim = true
    state.selectAnimTime = time.elapsedTime
    state.selectAnimFromX = fromCX or CHAR_SLOT.CX
    state.selectAnimFromY = fromCY or CHAR_SLOT.CY

    -- 启动列表向下滑出动画（不立即隐藏）
    state.rosterSlideDir = -1
    state.rosterSlideTime = time.elapsedTime
    state.rosterSlideProgress = 1.0

    local heroCfg = HC.get(heroId)
    print("[ChurchPage] 选择冒险家: " .. (heroCfg and heroCfg.name or ("ID:" .. heroId)))
end

--- 更新槽位动画进度
local function updateSlotAnim()
    if state.slotAnimDir == 0 then return end

    local elapsed = time.elapsedTime - state.slotAnimTime
    local t = math.min(1.0, elapsed / ANIM.SLOT_DUR)
    local eased = easeOutCubic(t)

    if state.slotAnimDir == 1 then
        state.slotLiftProgress = eased
    else
        state.slotLiftProgress = 1.0 - eased
    end

    if t >= 1.0 then
        state.slotAnimDir = 0
        if not state.slotExpanded then
            state.slotLiftProgress = 0
        else
            state.slotLiftProgress = 1.0
        end
    end
end

--- 更新卡片飞行动画
local function updateSelectAnim()
    if not state.selectAnim then return end
    local elapsed = time.elapsedTime - state.selectAnimTime
    local t = math.min(1.0, elapsed / ANIM.SELECT_DUR)
    if t >= 1.0 then
        state.selectAnim = false
        state.slotExpanded = false
    end
end

--- 更新角色列表滑入/滑出动画
local function updateRosterSlide()
    if state.rosterSlideDir == 0 then return end
    local elapsed = time.elapsedTime - state.rosterSlideTime
    local t = math.min(1.0, elapsed / ANIM.ROSTER_SLIDE_DUR)
    local eased = easeOutCubic(t)
    if state.rosterSlideDir == 1 then
        state.rosterSlideProgress = eased
    else
        state.rosterSlideProgress = 1.0 - eased
    end
    if t >= 1.0 then
        state.rosterSlideDir = 0
        if state.rosterSlideProgress < 0.01 then
            state.rosterSlideProgress = 0
            state.slotExpanded = false
        else
            state.rosterSlideProgress = 1.0
        end
    end
end

--- 点击事件处理
---@return boolean consumed
function ChurchPage.handleInput(dx, dy)
    if not state.open then return false end
    if state.closing then
        -- 安全保护：关闭动画超过 1 秒仍未完成，强制关闭
        local closingElapsed = time.elapsedTime - state.closeTime
        if closingElapsed > 1.0 then
            print("[ChurchPage] handleInput: 关闭动画超时(" .. string.format("%.2f", closingElapsed) .. "s)，强制关闭")
            ChurchPage.forceClose()
            return false
        end
        return true
    end

    -- ========== 重置确认弹窗（模态，优先拦截）→ 委托 ClassChange ==========
    if state.resetConfPopup then
        return ClassChange.handleResetConfirmInput(dx, dy)
    end

    -- ========== 转职确认弹窗（模态，优先拦截）→ 委托 ClassChange ==========
    if state.confirmPopup then
        return ClassChange.handleConfirmInput(dx, dy)
    end

    -- ========== 天赋效果总览（模态，优先于详情）→ 委托 TalentPanel ==========
    if state.tfOverviewOpen then
        return TalentPanel.handleOverviewInput(dx, dy)
    end

    -- ========== 天赋详情面板（模态，优先拦截）→ 委托 TalentPanel ==========
    if state.tfDetailOpen then
        return TalentPanel.handleDetailInput(dx, dy)
    end

    -- ========== 神器 Tab 交互 → 委托 ArtifactPanel ==========
    if state.tab == "shenqi" then
        local consumed = ArtifactPanel.handleTabInput(dx, dy)
        if consumed then return true end
    end

    -- 返回按钮
    if hitTest(dx, dy, BTN_BACK.CX, BTN_BACK.CY, BTN_BACK.W, BTN_BACK.H) then
        ChurchPage.close()
        return true
    end

    -- 角色列表中的点击检测（展开且在转职tab时）
    -- roster 使用屏幕设计坐标（独立浮层，不跟随上半部分偏移）
    if state.slotExpanded and state.tab == "zhuanzhi" and state.slotLiftProgress > 0.9 then
        local ownedList = getOwnedHeroList()
        local rosterCount = #ownedList
        local scrollOff = state.rosterScrollY
        for idx, entry in ipairs(ownedList) do
            -- 与 drawRosterList 完全一致的居中分布计算
            local row = math.ceil(idx / ROSTER.MAX_PER_ROW)
            local col = idx - (row - 1) * ROSTER.MAX_PER_ROW    -- 1~5

            local rowStart = (row - 1) * ROSTER.MAX_PER_ROW + 1
            local rowEnd   = math.min(row * ROSTER.MAX_PER_ROW, rosterCount)
            local rowCount = rowEnd - rowStart + 1

            local rowCY = ROSTER.ROW1_CY + (row - 1) * ROSTER.ROW_SPACING - scrollOff
            local totalW = rowCount * ROSTER.CARD_W + (rowCount - 1) * ROSTER.CARD_SPACING
            local startCX = (DESIGN_W - totalW) * 0.5 + ROSTER.CARD_W * 0.5
            local cx = startCX + (col - 1) * (ROSTER.CARD_W + ROSTER.CARD_SPACING)
            local cy = rowCY

            if hitTest(dx, dy, cx, cy, ROSTER.CARD_W, ROSTER.CARD_H) then
                selectHero(entry.heroId, cx, cy)
                return true
            end
        end
    end

    -- 角色选择框点击（仅在转职 tab 中，跟随上移偏移）
    if state.tab == "zhuanzhi" then
        local slotOY = -ANIM.SLOT_LIFT * state.slotLiftProgress
        local slotCY = CHAR_SLOT.CY + slotOY
        if hitTest(dx, dy, CHAR_SLOT.CX, slotCY, CHAR_SLOT.W, CHAR_SLOT.H) then
            if state.slotExpanded then
                -- 已展开时点击槽位 → 收起
                collapseSlot()
            elseif state.slotLiftProgress >= 1.0 then
                -- 槽位已在上移位置（之前选过角色）→ 列表从下方滑入
                state.slotExpanded = true
                state.slotAnimDir = 0
                state.rosterScrollY = 0
                resetRosterScrollState()
                state.rosterSlideDir = 1
                state.rosterSlideTime = time.elapsedTime
                state.rosterSlideProgress = 0
                print("[ChurchPage] 重新展开角色列表（从下方滑入）")
            else
                -- 未展开且未上移 → 展开角色列表（播放上移动画）
                state.selectedHeroId = nil  -- 清除已选角色
                expandSlot()
            end
            return true
        end
    end

    -- ========== 点击列表上方空白区域 → 收起"我的冒险家"面板 ==========
    if state.tab == "zhuanzhi" and not state.selectAnim then
        local listTopY = ROSTER.LIST_BG_CY - ROSTER.LIST_BG_H * 0.5
        if state.slotExpanded and state.rosterSlideProgress > 0.5 then
            -- 列表展开时，点击列表背景上方区域 → 列表向下滑出
            if dy < listTopY then
                if state.selectedHeroId then
                    -- 已选过角色：仅滑出列表，保持槽位上移
                    state.rosterSlideDir = -1
                    state.rosterSlideTime = time.elapsedTime
                    state.rosterSlideProgress = 1.0
                    print("[ChurchPage] 点击上方区域，滑出角色列表")
                else
                    -- 未选过角色：完全收起（槽位下移回原位）
                    collapseSlot()
                    print("[ChurchPage] 点击上方区域，收起角色列表")
                end
                return true
            end
        elseif not state.slotExpanded and state.slotLiftProgress >= 1.0 and state.selectedHeroId then
            -- 已选角色、转职树显示时，点击上方空白区域 → 重新展开角色列表
            if dy < listTopY then
                state.slotExpanded = true
                state.slotAnimDir = 0
                state.rosterScrollY = 0
                resetRosterScrollState()
                state.rosterSlideDir = 1
                state.rosterSlideTime = time.elapsedTime
                state.rosterSlideProgress = 0
                print("[ChurchPage] 点击上方区域，重新展开角色列表")
                return true
            end
        end
    end

    -- ========== 天赋 Tab 交互 → 委托 TalentPanel ==========
    if state.tab == "tianfu" then
        local consumed = TalentPanel.handleTabInput(dx, dy)
        if consumed then return true end
    end

    -- ========== 转职分支图标点击 → 委托 ClassChange ==========
    if state.tab == "zhuanzhi" and state.selectedHeroId and not state.slotExpanded
       and state.slotLiftProgress > 0.9 and not state.selectAnim then
        local consumed = ClassChange.handleBranchInput(dx, dy)
        if consumed then return true end
    end

    -- Tab 切换检测
    for i, item in ipairs(TAB_ITEMS) do
        if hitTest(dx, dy, item.cx, item.cy, TAB.SLIDER_W, TAB.SLIDER_H) then
            local newTab = TAB_KEYS[i]
            if state.tab ~= newTab then
                state.tabFrom = state.tab
                state.tabSwitchTime = time.elapsedTime
                state.tab = newTab
                require("systems.GameSFX").playUIMove(2)
                TalentStarMap.stopInertia()

                -- 切换到非转职 tab 时：延迟清除英雄态，让旧 Tab 滑出期间仍渲染职业背景
                if newTab ~= "zhuanzhi" then
                    state._deferClearHero = true
                    -- 冻结槽位动画（不独立收起，整体跟 tab 一起滑走）
                    if state.slotExpanded then
                        state.slotExpanded = false
                    end
                    state.slotAnimDir = 0  -- 停止独立动画
                else
                    state._deferClearHero = false
                end

                print("[ChurchPage] 切换到 " .. newTab)
            end
            return true
        end
    end

    return true  -- 教堂打开时消费所有点击
end

-- ======================== 拖拽三段式 ========================

-- ======================== 拖拽三段式 → 委托 TalentPanel ========================

--- 拖拽开始
---@return boolean consumed
function ChurchPage.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end

    if isRosterVisible() and isInRosterScrollArea(dx, dy) then
        state.rosterDragging = true
        state.rosterLastDragY = dy
        state.rosterScrollVelocity = 0
        return true
    end

    if state.tab ~= "tianfu" and state.tab ~= "shenqi" then return false end
    if state.tab == "tianfu" then
        return TalentPanel.handleDragBegin(dx, dy)
    end
    return ArtifactPanel.handleDragBegin(dx, dy)
end

--- 拖拽移动
---@return boolean consumed
function ChurchPage.handleDragMove(dx, dy)
    if not state.open or state.closing then return false end

    if state.rosterDragging then
        local delta = state.rosterLastDragY - dy
        state.rosterScrollY = state.rosterScrollY + delta
        state.rosterLastDragY = dy
        state.rosterScrollVelocity = -delta
        clampRosterScroll()
        return true
    end

    if state.tab ~= "tianfu" and state.tab ~= "shenqi" then return false end
    if state.tab == "tianfu" then
        return TalentPanel.handleDragMove(dx, dy)
    end
    return ArtifactPanel.handleDragMove(dx, dy)
end

--- 拖拽结束
function ChurchPage.handleDragEnd(dx, dy)
    if not state.open or state.closing then return end
    if state.rosterDragging then
        state.rosterDragging = false
        return
    end
    if state.tab == "tianfu" then
        TalentPanel.handleDragEnd(dx, dy)
    elseif state.tab == "shenqi" then
        ArtifactPanel.handleDragEnd(dx, dy)
    end
end

--- 鼠标滚轮滚动
---@param wheel number
function ChurchPage.handleScroll(wheel)
    if not state.open or state.closing then return end
    if isRosterVisible() then
        state.rosterScrollY = state.rosterScrollY - wheel * 80
        state.rosterScrollVelocity = 0
        clampRosterScroll()
        return
    end
    if state.tab == "tianfu" and TalentPanel.handleScroll then
        TalentPanel.handleScroll(wheel)
    elseif state.tab == "shenqi" then
        ArtifactPanel.handleScroll(wheel)
    end
end

--- 绘制教堂界面
function ChurchPage.draw(vg)
    if not state.open then return end

    -- 更新槽位动画
    updateSlotAnim()
    updateSelectAnim()
    updateRosterSlide()

    -- 更新角色列表滚动惯性
    if state.rosterScrollVelocity ~= 0 and not state.rosterDragging then
        state.rosterScrollY = state.rosterScrollY - state.rosterScrollVelocity
        state.rosterScrollVelocity = state.rosterScrollVelocity * 0.92
        clampRosterScroll()
        if math.abs(state.rosterScrollVelocity) < 0.5 or state.rosterScrollY <= 0 or state.rosterScrollY >= getRosterScrollMax() then
            state.rosterScrollVelocity = 0
        end
    end

    -- 更新星图惯性滑动 (每帧)
    do
        local now = time.elapsedTime
        local lastT = state._lastDrawTime or now
        local frameDt = now - lastT
        state._lastDrawTime = now
        if frameDt > 0 and frameDt < 0.2 then
            TalentStarMap.update(frameDt)
        end
    end

    -- === 弹出/关闭动画 ===
    local rawT, progress, lowerProgress

    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        rawT = math.min(1.0, elapsed / ANIM.CLOSE_DUR)
        progress      = 1 - easeInCubic(rawT)
        lowerProgress = progress
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
        rawT = math.min(1.0, elapsed / ANIM.OPEN_DUR)
        progress      = easeOutCubic(rawT)
        lowerProgress = easeOutCubic(rawT)
        if rawT >= 1.0 and onOpenCallback_ then
            local cb = onOpenCallback_
            onOpenCallback_ = nil
            cb()
        end
    end

    local upperDist = state.closing and ANIM.UPPER_SLIDE_OUT or ANIM.UPPER_SLIDE_IN
    local upperOY = -upperDist * (1 - progress)
    local lowerOY =  ANIM.LOWER_SLIDE_DIST * (1 - lowerProgress)
    local overlayAlpha = math.floor(180 * progress)

    -- === 全屏遮罩 ===
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)

    -- === Tab 滑动动画（提前计算，供背景和内容共用） ===
    local tabIdx = TAB_MAP[state.tab] or 1
    local fromIdx = TAB_MAP[state.tabFrom] or 1
    local tabElapsed = time.elapsedTime - state.tabSwitchTime
    local tabT = math.min(1.0, tabElapsed / TAB.ANIM_DUR)
    local tabEased = easeInOutCubic(tabT)

    local direction = 0
    if tabIdx ~= fromIdx then
        direction = (tabIdx < fromIdx) and -1 or 1
    end
    -- 垂直滑动: 转职(idx=1)在上，天赋(idx=2)在下
    -- tianfu→zhuanzhi: direction=-1, 旧页下滑(+Y), 新页从上进入(-Y→0)
    -- zhuanzhi→tianfu: direction=1, 旧页上滑(-Y), 新页从下进入(+Y→0)
    local newOY_tab = DESIGN_H * direction * (1 - tabEased)
    local oldOY_tab = -DESIGN_H * direction * tabEased
    local isAnimating = (tabT < 1.0 and tabIdx ~= fromIdx)

    -- 延迟清除：Tab 切换动画结束后清除旧 Tab 的英雄选中态
    if not isAnimating and state._deferClearHero then
        state.selectedHeroId = nil
        state._deferClearHero = false
        state.slotLiftProgress = 0
    end

    -- === 槽位上移偏移 ===
    local slotLiftOY = -ANIM.SLOT_LIFT * state.slotLiftProgress

    -- 计算教堂上半部分（属于转职视图）在 tab 动画期间的垂直偏移
    local upperTabOY = 0
    if isAnimating then
        if state.tabFrom == "zhuanzhi" then
            upperTabOY = oldOY_tab  -- 转职是旧 tab，跟着滑出
        elseif state.tab == "zhuanzhi" then
            upperTabOY = newOY_tab  -- 转职是新 tab，跟着滑入
        end
    end

    -- ================== 上半部分（从上方滑入） ==================
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY + upperTabOY)

    local isArtifactTab = (state.tab == "shenqi")

    -- 1. 教堂背景图（神器 Tab 隐藏，避免遮挡 UI_JTSQ_BJ）
    local hideChurchBg = isArtifactTab
        and not (isAnimating and state.tabFrom == "shenqi")
    if not hideChurchBg then
        nvgSave(vg)
        nvgTranslate(vg, 0, slotLiftOY)
        nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        drawImageCentered(vg, img.bg, CHURCH.BG_CX, CHURCH.BG_CY, CHURCH.BG_W, CHURCH.BG_H, 1.0)
        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    if not isArtifactTab then
        -- 2. 建筑名称背景（不跟随上移）
        drawImageCentered(vg, img.nameBg, CHURCH.NAME_BG_CX, CHURCH.NAME_BG_CY, CHURCH.NAME_BG_W, CHURCH.NAME_BG_H, 1.0)

    -- 3. 文本"教堂"（不跟随上移）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, CHURCH.NAME_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, CHURCH.NAME_TEXT_CX, CHURCH.NAME_TEXT_CY, "教堂", nil)

    -- 3.5 资源显示：金币 & 宝石（与主界面 TopBar 相同位置和样式）
    do
        local resY = 100
        -- 金币背景
        local goldBgX = 732 - 170 * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, goldBgX, resY - 47 * 0.5, 170, 47, 18)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
        nvgFill(vg)
        -- 金币图标
        drawImageCentered(vg, img.resGold, 653, resY, 73, 73, 1.0)
        -- 金币数值
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 33)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, goldBgX + 44, resY, NumberUtil.format(GameState.getGold()), nil)

        -- 宝石背景
        local gemBgX = 965 - 170 * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, gemBgX, resY - 47 * 0.5, 170, 47, 18)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 204))
        nvgFill(vg)
        -- 宝石图标
        drawImageCentered(vg, img.resDiamond, 884, resY, 76, 76, 1.0)
        -- 宝石数值
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 33)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, gemBgX + 44, resY, NumberUtil.format(GameState.getGems()), nil)
    end

    -- 4. 角色选择框（跟随上移）
    nvgSave(vg)
    nvgTranslate(vg, 0, slotLiftOY)

    if state.selectedHeroId then
        -- 已选角色 → 显示角色卡牌 + 详细信息（与角色面板一致）
        local heroCfg = HC.get(state.selectedHeroId)
        local ownData = CharacterPanel.getOwnedHero(state.selectedHeroId)
        local cx, cy = CHAR_SLOT.CX, CHAR_SLOT.CY

        -- a) 角色卡牌（飞行动画期间隐藏槽位上的卡片，由飞行动画绘制）
        if not state.selectAnim then
        local cardImg = getHeroCardImage(vg, state.selectedHeroId)
        drawImageCentered(vg, cardImg, cx, cy, CHAR_SLOT.W, CHAR_SLOT.H, 1.0)
        end

        if heroCfg then
            -- b) 职业图标（左上角，60x60）
            local iconIdx = ClassChange.CLASS_NUM[heroCfg.classId]
            if iconIdx and img.classIcons[iconIdx] then
                drawImageCentered(vg, img.classIcons[iconIdx], cx, cy + ROSTER.TAG_OFFSET_Y, 60, 60, 1.0)
            end

            -- c) 战斗力图标+数值（居中于卡片，与角色面板一致）
            local realLevel = ownData and ownData.level or 1
            local statLevel = realLevel
            -- 使用缓存，仅当角色变更时重新计算
            if cachedPowerHeroId ~= state.selectedHeroId then
                cachedPowerHeroId = state.selectedHeroId
                cachedPowerValue = 0
                local selAdvBranch = ownData and ownData.advBranch or nil
                local selAwakening = ownData and ownData.awakening or nil
                local heroUnit = HC.createHero(state.selectedHeroId, statLevel, selAdvBranch, selAwakening)
                if heroUnit and heroUnit.attrs then
                    local a = heroUnit.attrs
                    CharacterPanel.applyEquippedItems(a, state.selectedHeroId)
                    local total = 0
                    for key, meta in pairs(AD.META) do
                        if not POWER_SKIP[key] and meta.valueModel and meta.valueModel > 0 then
                            local val = a:get(key)
                            if meta.dataType == AD.TYPE_PCT then
                                total = total + val * (meta.valueModel / 100)
                            else
                                total = total + val * meta.valueModel
                            end
                        end
                    end
                    cachedPowerValue = math.floor(total + 0.5)
                end
            end
            local power = cachedPowerValue
            local powerStr = tostring(power)
            local POWER_GAP = 4
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 30)
            local ptW = nvgTextBounds(vg, 0, 0, powerStr)
            local pcW = ROSTER.POWER_ICON_SIZE + POWER_GAP + ptW
            local pcX = cx - pcW * 0.5
            drawImageCentered(vg, img.power, pcX + ROSTER.POWER_ICON_SIZE * 0.5,
                cy + ROSTER.POWER_DY, ROSTER.POWER_ICON_SIZE, ROSTER.POWER_ICON_SIZE, 1.0)
            drawTextStroke(vg, pcX + ROSTER.POWER_ICON_SIZE + POWER_GAP,
                cy + ROSTER.POWER_DY, powerStr,
                30, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                247, 254, 119, 4)

            -- d) 经验条
            local exp = ownData and ownData.exp or 0
            local maxExp = ownData and ownData.maxExp or 5
            local expBarCX = cx + ROSTER.EXP_BAR_DX
            local expBarCY = cy + ROSTER.EXP_BAR_DY
            drawImageCentered(vg, img.expBarBg, expBarCX, expBarCY, ROSTER.EXP_BAR_BG_W, ROSTER.EXP_BAR_BG_H, 1.0)
            local expProgress = (maxExp > 0) and (exp / maxExp) or 0
            expProgress = math.max(0, math.min(1, expProgress))
            local fillW = ROSTER.EXP_BAR_BG_W - ROSTER.EXP_BAR_PADDING * 2 - ROSTER.EXP_FILL_LEFT_INSET
            local fillH = ROSTER.EXP_BAR_BG_H - ROSTER.EXP_BAR_PADDING * 2
            local fillX = expBarCX - ROSTER.EXP_BAR_BG_W * 0.5 + ROSTER.EXP_BAR_PADDING + ROSTER.EXP_FILL_LEFT_INSET
            local fillY = expBarCY - ROSTER.EXP_BAR_BG_H * 0.5 + ROSTER.EXP_BAR_PADDING
            local clipW = fillW * expProgress
            if clipW > 0 and img.expBarFill >= 0 then
                nvgSave(vg)
                nvgIntersectScissor(vg, fillX, fillY, clipW, fillH)
                local paint = nvgImagePattern(vg, fillX, fillY, fillW, fillH, 0, img.expBarFill, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, fillX, fillY, fillW, fillH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
                nvgResetScissor(vg)
                nvgRestore(vg)
            end

            -- e) 等级徽章
            local badgeCX = cx + ROSTER.LVL_BADGE_DX
            local badgeCY = cy + ROSTER.LVL_BADGE_DY
            drawImageCentered(vg, img.lvlBadge, badgeCX, badgeCY, ROSTER.LVL_BADGE_SIZE, ROSTER.LVL_BADGE_SIZE, 1.0)
            drawTextStroke(vg, badgeCX, badgeCY, tostring(statLevel),
                28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)

            -- f) 角色名背景 + 文字
            local nameBgCY = cy + ROSTER.NAME_BG_DY
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - ROSTER.NAME_BG_W2 * 0.5, nameBgCY - ROSTER.NAME_BG_H2 * 0.5,
                ROSTER.NAME_BG_W2, ROSTER.NAME_BG_H2, ROSTER.NAME_BG_RADIUS)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
            nvgFill(vg)
            drawTextStroke(vg, cx, nameBgCY, heroCfg.name,
                28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)
        end
    else
        -- 空槽位
        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            CHAR_SLOT.CX - CHAR_SLOT.W * 0.5,
            CHAR_SLOT.CY - CHAR_SLOT.H * 0.5,
            CHAR_SLOT.W, CHAR_SLOT.H,
            CHAR_SLOT.R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
        nvgFill(vg)
        -- 加号图标居中
        drawImageCentered(vg, img.plus, CHAR_SLOT.CX, CHAR_SLOT.CY, CHAR_SLOT.PLUS_W, CHAR_SLOT.PLUS_H, 1.0)
        -- 空槽位右上角可转职角标
        if ChurchPage.hasAnyAdvance() and img.iconUp >= 0 then
            local upSize = 40
            local upX = CHAR_SLOT.CX + CHAR_SLOT.W * 0.5 - upSize * 0.5 - 2
            local upY = CHAR_SLOT.CY - CHAR_SLOT.H * 0.5 + upSize * 0.5 + 2
            drawImageCentered(vg, img.iconUp, upX, upY, upSize, upSize, 1.0)
        end
    end

    nvgRestore(vg)  -- 结束槽位上移偏移
    end

    nvgRestore(vg)  -- 结束上半部分偏移

    -- === Tab 全屏背景（上半部分之后绘制，覆盖教堂室内背景） ===
    nvgSave(vg)
    nvgTranslate(vg, 0, lowerOY)
    if isAnimating then
        -- 旧 tab 背景（垂直滑出）：先裁剪到屏幕可见区域，再纵向平移
        local oVisTop = math.max(0, oldOY_tab)
        local oVisBot = math.min(DESIGN_H, oldOY_tab + DESIGN_H)
        if oVisBot > oVisTop then
            nvgSave(vg)
            nvgScissor(vg, 0, oVisTop, DESIGN_W, oVisBot - oVisTop)
            nvgTranslate(vg, 0, oldOY_tab)
            if state.tabFrom == "tianfu" then TalentPanel.drawBg(vg) end
            if state.tabFrom == "zhuanzhi" then ClassChange.drawBg(vg) end
            if state.tabFrom == "shenqi" then ArtifactPanel.drawBg(vg) end
            nvgRestore(vg)
        end
        -- 新 tab 背景（垂直滑入）
        local nVisTop = math.max(0, newOY_tab)
        local nVisBot = math.min(DESIGN_H, newOY_tab + DESIGN_H)
        if nVisBot > nVisTop then
            nvgSave(vg)
            nvgScissor(vg, 0, nVisTop, DESIGN_W, nVisBot - nVisTop)
            nvgTranslate(vg, 0, newOY_tab)
            if state.tab == "tianfu" then TalentPanel.drawBg(vg) end
            if state.tab == "zhuanzhi" then ClassChange.drawBg(vg) end
            if state.tab == "shenqi" then ArtifactPanel.drawBg(vg) end
            nvgRestore(vg)
        end
    else
        if state.tab == "tianfu" then TalentPanel.drawBg(vg) end
        if state.tab == "zhuanzhi" then ClassChange.drawBg(vg) end
        if state.tab == "shenqi" then ArtifactPanel.drawBg(vg) end
    end
    nvgRestore(vg)

    -- （教堂名称移至 Tab 内容之后绘制，确保在星图上方）

    -- ================== 下半部分（从下方滑入） ==================
    nvgSave(vg)
    nvgTranslate(vg, 0, lowerOY)

    -- Tab 内容剪裁区域（延伸到屏幕底部，让星图显示在底部按钮后方）
    local clipTop = 0
    local clipBottom = DESIGN_H
    local clipH = clipBottom - clipTop

    -- （Tab 动画变量和背景已在上半部分之前绘制）

    -- drawTabContent 内联委托
    local function drawTabContent(tabKey)
        if tabKey == "tianfu" then TalentPanel.drawContent(vg) end
        if tabKey == "zhuanzhi" then ClassChange.drawContent(vg) end
        if tabKey == "shenqi" then ArtifactPanel.drawContent(vg) end
    end

    -- 绘制旧面板内容（垂直滑出，仅动画中）
    if isAnimating then
        local oVisTop = math.max(clipTop, clipTop + oldOY_tab)
        local oVisBot = math.min(clipTop + clipH, clipTop + oldOY_tab + clipH)
        if oVisBot > oVisTop then
            nvgSave(vg)
            nvgScissor(vg, 0, oVisTop, DESIGN_W, oVisBot - oVisTop)
            nvgTranslate(vg, 0, oldOY_tab)
            drawTabContent(state.tabFrom)
            nvgRestore(vg)
        end
    end

    -- 绘制新面板内容（垂直滑入）
    if isAnimating then
        local nVisTop = math.max(clipTop, clipTop + newOY_tab)
        local nVisBot = math.min(clipTop + clipH, clipTop + newOY_tab + clipH)
        if nVisBot > nVisTop then
            nvgSave(vg)
            nvgScissor(vg, 0, nVisTop, DESIGN_W, nVisBot - nVisTop)
            nvgTranslate(vg, 0, newOY_tab)
            drawTabContent(state.tab)
            nvgRestore(vg)
        end
    else
        nvgSave(vg)
        nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)
        drawTabContent(state.tab)
        nvgRestore(vg)
    end

    -- 6. 返回按钮
    drawImageCentered(vg, img.btnBack, BTN_BACK.CX, BTN_BACK.CY, BTN_BACK.W, BTN_BACK.H, 1.0)

    -- 7. 页面选项滑块背景
    drawImageCentered(vg, img.tabBg, TAB.BG_CX, TAB.BG_CY, TAB.BG_W, TAB.BG_H, 1.0)

    -- 8. 滑块按钮（带平移动画）
    local targetItem = TAB_ITEMS[tabIdx]
    local fromItem = TAB_ITEMS[fromIdx]
    local sliderCX = fromItem.cx + (targetItem.cx - fromItem.cx) * tabEased
    local sliderCY = fromItem.cy + (targetItem.cy - fromItem.cy) * tabEased

    drawNineSlice(vg, img.slider,
        sliderCX - TAB.SLIDER_W * 0.5, sliderCY - TAB.SLIDER_H * 0.5,
        TAB.SLIDER_W, TAB.SLIDER_H,
        TAB.INSET_TOP, TAB.INSET_RIGHT, TAB.INSET_BOTTOM, TAB.INSET_LEFT)

    -- Tab 文本
    for i, item in ipairs(TAB_ITEMS) do
        local isActive = (state.tab == TAB_KEYS[i])

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TAB.FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(TAB.ACTIVE_R, TAB.ACTIVE_G, TAB.ACTIVE_B, 255))
        else
            nvgFillColor(vg, nvgRGBA(TAB.INACTIVE_R, TAB.INACTIVE_G, TAB.INACTIVE_B, 255))
        end
        nvgText(vg, item.textX, item.textY, item.name, nil)

        -- Tab 角标：转职Tab(i=1) 有可转职英雄→绿色箭头 / 天赋Tab(i=2) 有未用天赋点→绿色箭头 / 神器Tab(i=3) 有可合成神器→绿色箭头
        local showTabBadge = false
        if i == 1 then
            showTabBadge = ChurchPage.hasAnyAdvance()
        elseif i == 2 then
            showTabBadge = ChurchPage.hasAnyUnusedTalent()
        elseif i == 3 then
            showTabBadge = ArtifactPanel.canUpgradeAnyArtifact()
        end
        if showTabBadge and img.iconUp >= 0 then
            local upSize = 30
            local textHalfW = nvgTextBounds(vg, 0, 0, item.name) * 0.5
            local upX = item.textX + textHalfW + 10
            local upY = item.textY - 18
            drawImageCentered(vg, img.iconUp, upX, upY, upSize, upSize, 1.0)
        end
    end

    -- 新手引导热点：天赋 Tab（TAB_ITEMS[2]）
    local _TM = require("systems.TutorialManager")
    if _TM.isActive() then
        local ti2 = TAB_ITEMS[2]
        _TM.registerHotspot("talent_toggle", ti2.cx, ti2.cy + lowerOY, TAB.SLIDER_W, TAB.SLIDER_H)
    end

    nvgRestore(vg)  -- 结束下半部分偏移

    -- === 教堂名称（在 Tab 内容之上重绘，跟随 upperOY，确保不被星图覆盖） ===
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)
    drawImageCentered(vg, img.nameBg, CHURCH.NAME_BG_CX, CHURCH.NAME_BG_CY, CHURCH.NAME_BG_W, CHURCH.NAME_BG_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, CHURCH.NAME_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, CHURCH.NAME_TEXT_CX, CHURCH.NAME_TEXT_CY, "教堂", nil)
    nvgRestore(vg)

    -- ================== 角色列表浮层（独立绘制，不被下半部分遮盖） ==================
    -- 仅在展开状态（slotExpanded）时绘制；选中冒险家后 slotExpanded=false 但 slotLiftProgress 保持1.0
    if (state.slotExpanded or state.rosterSlideProgress > 0.01) and state.slotLiftProgress > 0.01 and state.tab == "zhuanzhi" then
        local rosterAlpha = state.slotLiftProgress * state.rosterSlideProgress
        nvgSave(vg)
        nvgGlobalAlpha(vg, rosterAlpha)

        -- 列表滑入/滑出偏移（从下方滑入/向下滑出）
        local slideOY = ANIM.ROSTER_SLIDE_DIST * (1.0 - state.rosterSlideProgress)
        nvgTranslate(vg, 0, slideOY)

        -- 直接绘制列表（无黑色遮罩，列表背景图自带底色）
        -- 列表背景底部不截断，直接显示到设计分辨率底部
        drawRosterList(vg)

        nvgGlobalAlpha(vg, 1.0)
        nvgRestore(vg)
    end

    -- ================== 卡片飞行动画 ==================
    if state.selectAnim and state.selectedHeroId then
        local elapsed = time.elapsedTime - state.selectAnimTime
        local t = math.min(1.0, elapsed / ANIM.SELECT_DUR)
        local eased = easeOutCubic(t)

        -- 目标位置 = 槽位已上移后的位置
        local targetCX = CHAR_SLOT.CX
        local targetCY = CHAR_SLOT.CY - ANIM.SLOT_LIFT

        -- 从列表卡片位置飞向槽位
        local curX = state.selectAnimFromX + (targetCX - state.selectAnimFromX) * eased
        local curY = state.selectAnimFromY + (targetCY - state.selectAnimFromY) * eased

        -- 缩放：卡片从列表尺寸到槽位尺寸（两者相同则无缩放）
        local cardImg = getHeroCardImage(vg, state.selectedHeroId)
        nvgSave(vg)
        nvgGlobalAlpha(vg, 1.0)
        drawImageCentered(vg, cardImg, curX, curY, ROSTER.CARD_W, ROSTER.CARD_H, 1.0)
        nvgRestore(vg)
    end

    -- ================== 天赋详情面板 ==================
    TalentPanel.drawDetailPanel(vg)

    -- ================== 天赋效果总览弹窗 ==================
    TalentPanel.drawOverviewPanel(vg)

    -- ================== 转职确认弹窗（最顶层） ==================
    ClassChange.drawConfirmPopup(vg)

    -- ================== 重置确认弹窗（最顶层） ==================
    ClassChange.drawResetConfirmPopup(vg)

    -- ================== Spine 卡牌特效 ==================
    SpineCardEffect.draw(vg)

    -- ================== 飘字提示（最最顶层） ==================
    if state.floatText then
        local FLOAT_DURATION = 1.5   -- 飘字持续时间（秒）
        local FLOAT_DIST     = 100   -- 向上飘动距离
        local elapsed = time.elapsedTime - state.floatTextTime
        if elapsed >= FLOAT_DURATION then
            state.floatText = nil  -- 飘字结束
        else
            local t = elapsed / FLOAT_DURATION
            local alpha = 1.0 - t   -- 0~1 范围（drawTextStroke opts.alpha 使用 0~1）
            local offsetY = -FLOAT_DIST * t
            drawTextStroke(vg, state.floatTextX, state.floatTextY + offsetY,
                state.floatText,
                40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 80, 80, 6,
                { alpha = alpha })
        end
    end
end

--- 处理服务端转职操作结果
function ChurchPage.onActionResult(data)
    if not state.open then return end

    -- 神器装配结果
    local Protocol = getProtocol()
    if data.action == Protocol.ACTION_TYPES.ARTIFACT_EQUIP and data.success then
        state.floatText = "神器安装成功，下波战斗生效"
        state.floatTextX = 540
        state.floatTextY = 980
        state.floatTextTime = time.elapsedTime
        ArtifactPanel.onArtifactEquipResult(true)
    elseif data.action == Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP and data.success then
        state.floatText = "神器已卸下，下波战斗生效"
        state.floatTextX = 540
        state.floatTextY = 980
        state.floatTextTime = time.elapsedTime
    elseif data.action == Protocol.ACTION_TYPES.ARTIFACT_MERGE and data.success then
        state.floatText = "神器合成成功"
        state.floatTextX = 540
        state.floatTextY = 980
        state.floatTextTime = time.elapsedTime
    elseif data.action == Protocol.ACTION_TYPES.ARTIFACT_REROLL and data.success then
        state.floatText = "神器置换成功"
        state.floatTextX = 540
        state.floatTextY = 980
        state.floatTextTime = time.elapsedTime
        local okPanel, ArtifactPanel = pcall(require, "ui.ChurchArtifactPanel")
        if okPanel and ArtifactPanel and ArtifactPanel.onArtifactRerollResult then
            ArtifactPanel.onArtifactRerollResult(true)
        end
    elseif data.action == Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE and data.success then
        state.floatText = "神器洗练成功"
        state.floatTextX = 540
        state.floatTextY = 980
        state.floatTextTime = time.elapsedTime
        local okPanel, ArtifactPanel = pcall(require, "ui.ChurchArtifactPanel")
        if okPanel and ArtifactPanel and ArtifactPanel.onArtifactRefineValueResult then
            ArtifactPanel.onArtifactRefineValueResult(true, data.artifactId)
        end
    elseif (data.action == Protocol.ACTION_TYPES.ARTIFACT_EQUIP
        or data.action == Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP
        or data.action == Protocol.ACTION_TYPES.ARTIFACT_MERGE
        or data.action == Protocol.ACTION_TYPES.ARTIFACT_REROLL
        or data.action == Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE) and not data.success then
        if data.action == Protocol.ACTION_TYPES.ARTIFACT_EQUIP then
            ArtifactPanel.onArtifactEquipResult(false)
        end
        state.floatText = data.reason or "神器操作失败"
        state.floatTextX = 540
        state.floatTextY = 980
        state.floatTextTime = time.elapsedTime
    end

    if data.action == Protocol.ACTION_TYPES.ARTIFACT_DRAW
        or data.action == Protocol.ACTION_TYPES.ARTIFACT_EQUIP
        or data.action == Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP
        or data.action == Protocol.ACTION_TYPES.ARTIFACT_MERGE
        or data.action == Protocol.ACTION_TYPES.ARTIFACT_REROLL
        or data.action == Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE then
        local okBN, BN = pcall(require, "ui.BottomNav")
        if okBN and BN and BN.refreshTownBadge then
            BN.refreshTownBadge()
        end
    end

    -- 转职成功结果（由 ADVANCE_CLASS handler 返回，含 branchId + advLevel + branchName）
    if data.branchId and data.advLevel then
        print("[ChurchPage] 转职成功: " .. tostring(data.branchName)
            .. " heroId=" .. tostring(data.heroId)
            .. " advLevel=" .. tostring(data.advLevel))
        -- 同步 advBranch 到 CharacterPanel，使转职天赋在当前会话立即生效
        if data.heroId then
            CharacterPanel.setHeroAdvBranch(data.heroId, data.branchId, data.advLevel)
        end
        -- 清除战斗力缓存，下次绘制会重新计算
        clearPowerCache()
        -- 刷新城镇Tab角标（转职后可能不再有可转职英雄）
        local okBN, BN = pcall(require, "ui.BottomNav")
        if okBN and BN and BN.refreshTownBadge then
            BN.refreshTownBadge()
        end
        -- 转职成功 Spine 特效：在角色卡片当前位置播放（卡片已上移 ANIM.SLOT_LIFT）
        local cardActualCY = CHAR_SLOT.CY - ANIM.SLOT_LIFT * state.slotLiftProgress
        SpineCardEffect.playJobChange(CHAR_SLOT.CX, cardActualCY)
    end

    -- 重置转职成功结果（由 RESET_CLASS handler 返回）
    if data.action == getProtocol().ACTION_TYPES.RESET_CLASS and data.success and data.heroId then
        print("[ChurchPage] 重置转职成功 heroId=" .. tostring(data.heroId)
            .. " removedOffhand=" .. tostring(data.removedOffhandSeq))
        CharacterPanel.resetHeroAdvBranch(data.heroId)
        -- 清除战斗力缓存
        clearPowerCache()
        -- 刷新城镇Tab角标
        local okBN, BN = pcall(require, "ui.BottomNav")
        if okBN and BN and BN.refreshTownBadge then
            BN.refreshTownBadge()
        end
    end
end

--- 预加载天赋背景 Spine（在 LoadingScreen 阶段调用，避免进入教堂时卡顿）
---@param vg any NanoVG 上下文
function ChurchPage.preloadSpine(vg)
    TalentPanel.preloadSpine(vg)
end

return ChurchPage
