-- ============================================================================
-- BottomNav - 底部导航栏（5 个标签，选中/未选中/锁定三态 + 切换动画）
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local ExpTable    = require("config.ExpTable")
local GameState   = require("core.GameState")
local GameEvents  = require("config.GameEvents")
local EventBus    = require("core.EventBus")
local PlayerStore = require("client.data.PlayerStore")
local DarkIcon    = require("core.DarkIcon")  -- [暗黑化 P0] 矢量图标库

local BottomNav = {}

-- ======================== 常量 ========================

-- 导航栏背景
local NAV_CX, NAV_CY = 540, 2352
local NAV_W, NAV_H   = 1080, 303

-- 标签分布
local TAB_COUNT   = 5
local TAB_SPACING = NAV_W / TAB_COUNT  -- 216

-- 未选中标签
local UNSEL_W, UNSEL_H       = 194, 207
local UNSEL_BG_CY            = NAV_CY
local UNSEL_ICON_SIZE        = 106
local UNSEL_ICON_Y_OFFSET    = -13

-- 选中标签
local SEL_W, SEL_H           = 240, 253
local SEL_BG_CY              = 2264
local SEL_ICON_SIZE          = 138
local SEL_ICON_CY            = 2258
local SEL_TEXT_CY            = 2353
local SEL_TEXT_SIZE          = 60
local SEL_STROKE_WIDTH       = 6

-- 动画
local ANIM_SPEED = 10.0

-- ======================== 标签数据 ========================

local tabs = {
    { name = "角色", iconFile = "image/通用图标/ICON_GN_1.png",   locked = true },  -- 由引导1解锁
    { name = "日志", iconFile = "image/通用图标/ICON_GN_2.png",   locked = true },  -- 由引导3解锁
    { name = "战斗", iconFile = "image/通用图标/ICON_GN_3.png" },
    { name = "城镇", iconFile = "image/通用图标/ICON_GN_4.png",   locked = true },  -- 由引导4解锁
    { name = "副本", iconFile = "image/通用图标/ICON_GN_5.png",   locked = true },  -- 首通0305解锁
}

local selectedIndex = 3  -- 默认选中"战斗"

-- 全局锁定标志（终焉神殿等场景下锁定所有标签）
local allLocked_ = false

-- 每个标签的激活度 0(未选中) ~ 1(选中)，用于动画插值
local tabActivation = { 0, 0, 1, 0, 0 }

-- ======================== 图片 handles ========================

local imgNavBg  = -1
local imgTabBg1 = -1
local imgTabBg2 = -1
local imgTabBg3 = -1
-- [暗黑化 P0] 页签图标/红点改由 core/DarkIcon.lua 程序化矢量绘制，不再加载贴图
local imgIconUp    = -1   -- ICON_UP.png 强化角标（小）
local imgIconUpBig = -1   -- ICON_UP_big.png 强化角标（大，选中态用）

-- 各标签角标状态: tabBadges[i] = true 表示该标签需要显示角标
local tabBadges = {}
-- 各标签角标样式: tabBadgeStyle[i] = "redDot" 时使用红点，否则使用默认强化箭头
local tabBadgeStyle = {}

-- ======================== 工具函数 ========================

local function lerp(a, b, t)
    return a + (b - a) * t
end

--- 居中绘制图片（支持透明度）
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

--- 16 向描边文字（支持透明度）
local _drawTextStroke = require("core.DrawUtil").drawTextStroke
local function drawTextStroke(vg, x, y, text, fontSize, align, fr, fg, fb, sw, alpha)
    _drawTextStroke(vg, x, y, text, fontSize, align, fr, fg, fb, sw, { alpha = alpha })
end

-- ======================== Public API ========================

function BottomNav.init(vg)
    imgNavBg  = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_DB.png", 0)
    imgTabBg1 = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_DBAN1.png", 0)
    imgTabBg2 = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_DBAN2.png", 0)
    imgTabBg3 = nvgCreateImage(vg, "image/界面底板/通用面板/UI_YWJM_DBAN3.png", 0)

    -- [暗黑化 P0] 页签图标/红点由 core/DarkIcon.lua 矢量绘制，无需加载

    imgIconUp    = nvgCreateImage(vg, "image/通用图标/ICON_UP.png", 0)
    imgIconUpBig = nvgCreateImage(vg, "image/通用图标/ICON_UP_big.png", 0)

    -- 根据当前冒险等级初始化标签解锁状态
    BottomNav.refreshUnlockState(vg)


    print("[BottomNav] init OK")
end

--- 每帧更新动画（在 HandleUpdate 中调用）
function BottomNav.update(dt)
    for i = 1, TAB_COUNT do
        if not tabs[i].locked then
            local target = (i == selectedIndex) and 1 or 0
            local diff = target - tabActivation[i]
            if math.abs(diff) < 0.001 then
                tabActivation[i] = target
            else
            ---@diagnostic disable-next-line: assign-type-mismatch
                tabActivation[i] = tabActivation[i] + diff * math.min(dt * ANIM_SPEED, 1)
            end
        end
    end
end

--- 每帧绘制
-- 底栏视觉已全局移除，页面入口迁到 TopBar（本模块仅保留页码/锁定/角标状态）
function BottomNav.draw(vg)
end

--- 底栏已隐藏，保留空实现避免旧调用报错
function BottomNav.handleInput(designX, designY)
    return nil
end

--- 底栏已隐藏
function BottomNav.hitTest(designX, designY)
    return false
end

function BottomNav.getSelectedIndex()
    return selectedIndex
end

function BottomNav.setSelectedIndex(index)
    if index >= 1 and index <= TAB_COUNT and not tabs[index].locked then
        selectedIndex = index
    end
end

--- 设置指定标签的角标显示状态
---@param tabIndex number 标签索引 (1~5)
---@param show boolean 是否显示角标
---@param style? string 角标样式: "redDot" 红点 | nil 默认强化箭头
function BottomNav.setBadge(tabIndex, show, style)
    tabBadges[tabIndex] = show or false
    tabBadgeStyle[tabIndex] = style  -- nil 时恢复为默认箭头样式
end

--- 刷新城镇标签(Tab 4)角标：合并教堂(天赋/转职) + 铁匠铺(可强化)
function BottomNav.refreshTownBadge()
    -- 教堂角标（优先级高：天赋→箭头，转职→红点）
    local okCP, CP = pcall(require, "ui.ChurchPage")
    if okCP and CP and CP.getChurchBadgeInfo then
        local show, style = CP.getChurchBadgeInfo()
        if show then
            BottomNav.setBadge(4, true, style)
            return
        end
    end
    -- 铁匠铺可强化→箭头
    local okBP, BP = pcall(require, "ui.BlacksmithPage")
    if okBP and BP and BP.canEnhanceAny then
        local ok, canEnh = pcall(BP.canEnhanceAny)
        if ok and canEnh then
            BottomNav.setBadge(4, true, nil)
            return
        end
    end
    local okRS, RS = pcall(require, "systems.RelicSystem")
    if okRS and RS and RS.getRelicBadgeInfo then
        local show, style = RS.getRelicBadgeInfo()
        if show then
            BottomNav.setBadge(4, true, style)
            return
        end
    end
    -- 都没有→清除
    BottomNav.setBadge(4, false, nil)
end

--- 刷新副本标签(Tab 5)角标：有可扫荡次数时显示红点
function BottomNav.refreshDungeonBadge()
    local okDC, DungeonConfig = pcall(require, "config.DungeonConfig")
    if not okDC then
        BottomNav.setBadge(5, false, nil)
        return
    end

    -- 副本 Tab 5 未解锁时不显示红点
    if tabs[5].locked then
        BottomNav.setBadge(5, false, nil)
        return
    end

    local dungeonData = PlayerStore.Get("dungeon")
    if not dungeonData then
        BottomNav.setBadge(5, false, nil)
        return
    end

    local battleData = PlayerStore.Get("battle")
    local maxStageId = battleData and tonumber(battleData.maxStageId) or 0

    -- 检查每个副本是否有剩余扫荡次数
    for dungeonId, dailyLimit in pairs(DungeonConfig.DAILY_SWEEP_LIMIT) do
        -- 检查副本是否已解锁
        local unlockReq = DungeonConfig.UNLOCK_CONDITIONS[dungeonId]
        if not unlockReq or maxStageId >= unlockReq then
            -- 已解锁，检查剩余扫荡次数
            local dData = dungeonData[dungeonId]
            local dailyUsed = dData and dData.dailyUsed or 0
            local dailyMax = dungeonData.dailyMax or dailyLimit
            if dailyMax - dailyUsed > 0 then
                -- 有剩余扫荡次数，显示红点
                BottomNav.setBadge(5, true, "redDot")
                return
            end
        end
    end

    -- 没有可扫荡次数，清除红点
    BottomNav.setBadge(5, false, nil)
end

--- 根据引导完成状态刷新标签 1/2/4 的锁定状态
--- 在 init() 时调用一次，引导完成后也会通过 setTabLocked 实时解锁
function BottomNav.refreshUnlockState(vg)
    -- 打印调用栈（取前3层），方便追踪触发来源
    local stack = debug and debug.traceback and debug.traceback("", 2) or "N/A"
    -- 只取第2行（直接调用者），避免日志过长
    local caller = stack:match("\n\t?([^\n]+)") or stack
    print("[BottomNav][refreshUnlockState] called from: " .. caller)

    local ok, TM = pcall(require, "systems.TutorialManager")
    if not ok then
        print("[BottomNav][refreshUnlockState] TM require FAILED: " .. tostring(TM))
        return
    end

    print("[BottomNav][refreshUnlockState] BEFORE: tab1.locked=" .. tostring(tabs[1].locked)
        .. " tab2.locked=" .. tostring(tabs[2].locked)
        .. " tab4.locked=" .. tostring(tabs[4].locked))

    -- tab1：角色面板
    local char_unlocked = TM.isPanelUnlocked("character_panel")
    local log_unlocked  = TM.isPanelUnlocked("log_panel")
    local town_unlocked = TM.isPanelUnlocked("town_panel")

    print("[BottomNav][refreshUnlockState] isPanelUnlocked: character=" .. tostring(char_unlocked)
        .. " log=" .. tostring(log_unlocked)
        .. " town=" .. tostring(town_unlocked))

    if char_unlocked then tabs[1].locked = false end
    if log_unlocked  then tabs[2].locked = false end
    if town_unlocked then tabs[4].locked = false end

   -- tab5：副本（首通通关0305解锁）
   local battleData = PlayerStore.Get("battle")
   local maxStageId = battleData and tonumber(battleData.maxStageId) or 0
    if maxStageId > 305 then tabs[5].locked = false end

    print("[BottomNav][refreshUnlockState] AFTER: tab1.locked=" .. tostring(tabs[1].locked)
        .. " tab2.locked=" .. tostring(tabs[2].locked)
        .. " tab4.locked=" .. tostring(tabs[4].locked)
        .. " tab5.locked=" .. tostring(tabs[5].locked))
end

--- 设置指定标签的锁定状态（供引导系统在解锁时调用）
---@param tabIndex number 标签索引 (1~5)
---@param locked boolean
function BottomNav.setTabLocked(tabIndex, locked)
    if tabIndex < 1 or tabIndex > TAB_COUNT then return end
    tabs[tabIndex].locked = locked
    -- 若解锁后当前选中的是锁定标签，切回战斗
    if not locked and selectedIndex == tabIndex then return end
    if locked and selectedIndex == tabIndex then
        selectedIndex = 3
    end
    print("[BottomNav] tab " .. tabIndex .. " locked=" .. tostring(locked))
end

--- 全局锁定/解锁所有标签（终焉神殿等场景使用）
---@param locked boolean
function BottomNav.setAllLocked(locked)
    allLocked_ = locked and true or false
    print("[BottomNav] allLocked=" .. tostring(allLocked_))
end

--- 查询是否全局锁定
---@return boolean
function BottomNav.isAllLocked()
    return allLocked_
end

return BottomNav
