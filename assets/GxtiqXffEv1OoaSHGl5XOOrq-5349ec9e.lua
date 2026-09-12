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
    { name = "角色", iconFile = "image/ICON_GN_1.png",   locked = true },  -- 由引导1解锁
    { name = "日志", iconFile = "image/ICON_GN_2.png",   locked = true },  -- 由引导3解锁
    { name = "战斗", iconFile = "image/ICON_GN_3.png" },
    { name = "城镇", iconFile = "image/ICON_GN_4.png",   locked = true },  -- 由引导4解锁
    { name = "副本", iconFile = "image/ICON_GN_5.png",   locked = true },  -- 首通0305解锁
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
    imgNavBg  = nvgCreateImage(vg, "image/UI_YWJM_DB.png", 0)
    imgTabBg1 = nvgCreateImage(vg, "image/UI_YWJM_DBAN1.png", 0)
    imgTabBg2 = nvgCreateImage(vg, "image/UI_YWJM_DBAN2.png", 0)
    imgTabBg3 = nvgCreateImage(vg, "image/UI_YWJM_DBAN3.png", 0)

    -- [暗黑化 P0] 页签图标/红点由 core/DarkIcon.lua 矢量绘制，无需加载

    imgIconUp    = nvgCreateImage(vg, "image/ICON_UP.png", 0)
    imgIconUpBig = nvgCreateImage(vg, "image/ICON_UP_big.png", 0)

    -- 根据当前冒险等级初始化标签解锁状态
    BottomNav.refreshUnlockState(vg)

    -- 监听货币变化，刷新城镇标签红点（竞技券/特权点消耗后及时清除）
    EventBus.on(GameEvents.CURRENCY_CHANGED, function(data)
        if data and (data.arenaTicket ~= nil or data.privilegePoint ~= nil) then
            BottomNav.refreshTownBadge()
        end
    end)

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
function BottomNav.draw(vg)
    -- 导航栏背景
    drawImageCentered(vg, imgNavBg, NAV_CX, NAV_CY, NAV_W, NAV_H, 1.0)

    -- 未选中图标的 Y 中心（背景中心 + 上偏移）
    local unselIconCY = UNSEL_BG_CY + UNSEL_ICON_Y_OFFSET

    -- 先绘制非选中标签（底层），再绘制选中标签（顶层弹出）
    -- 第一遍：所有 t < 0.5 的标签（偏未选中）
    for pass = 1, 2 do
        for i = 1, TAB_COUNT do
            local cx = TAB_SPACING * (i - 0.5)
            local tab = tabs[i]
            local t = tabActivation[i]

            -- pass 1: 画未选中和锁定的（t < 0.5）
            -- pass 2: 画选中/正在选中的（t >= 0.5）
            local isTopLayer = (t >= 0.5)
            if (pass == 1 and isTopLayer) or (pass == 2 and not isTopLayer) then
                goto continue
            end

            if tab.locked then
                -- ===== 锁定态（无动画）[暗黑化 P0: 矢量图标 45% 透明表示锁定] =====
                drawImageCentered(vg, imgTabBg3, cx, UNSEL_BG_CY, UNSEL_W, UNSEL_H, 1.0)
                DarkIcon.draw(vg, DarkIcon.NAV_NAMES[i], cx, unselIconCY,
                    UNSEL_ICON_SIZE, 0.45)
            else
                -- ===== 动画态 =====
                -- 插值：位置、大小
                local bgCY   = lerp(UNSEL_BG_CY, SEL_BG_CY, t)
                local bgW    = lerp(UNSEL_W, SEL_W, t)
                local bgH    = lerp(UNSEL_H, SEL_H, t)
                local iconSz = lerp(UNSEL_ICON_SIZE, SEL_ICON_SIZE, t)
                local iconCY = lerp(unselIconCY, SEL_ICON_CY, t)

                -- 背景：交叉淡入淡出
                drawImageCentered(vg, imgTabBg1, cx, bgCY, bgW, bgH, 1 - t)
                drawImageCentered(vg, imgTabBg2, cx, bgCY, bgW, bgH, t)

                -- 图标（始终可见，位置和大小插值）[暗黑化 P0: 矢量图标]
                DarkIcon.draw(vg, DarkIcon.NAV_NAMES[i], cx, iconCY, iconSz, 1.0)

                -- 角标（右上角，跟随图标位置和大小动画）
                if tabBadges[i] then
                    local BADGE_SM = 64   -- 未选中态角标尺寸
                    local BADGE_LG = 74   -- 选中态角标尺寸（与战利品红点一致）
                    local badgeSz = lerp(BADGE_SM, BADGE_LG, t)
                    -- 位置：贴近图标右上角
                    local badgeX = cx + iconSz * 0.5 - badgeSz * 0.3
                    local badgeY = iconCY - iconSz * 0.5 + badgeSz * 0.3
                    if tabBadgeStyle[i] == "redDot" then
                        -- 红点样式 [暗黑化 P0: 余烬光点]
                        DarkIcon.draw(vg, "reddot", badgeX, badgeY, badgeSz, 1.0)
                    else
                        -- 默认强化箭头样式：选中/未选中切换大小，始终可见
                        local badgeImg = (t >= 0.5) and imgIconUpBig or imgIconUp
                        if badgeImg >= 0 then
                            drawImageCentered(vg, badgeImg, badgeX, badgeY, badgeSz, badgeSz, 1.0)
                        end
                    end
                end

                -- 标签名文字（随选中淡入）
                if t > 0.05 then
                    drawTextStroke(vg, cx, SEL_TEXT_CY, tab.name,
                        SEL_TEXT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                        255, 255, 255, SEL_STROKE_WIDTH, t)
                end
            end

            ::continue::
        end
    end

   -- 新手引导热点注册
   local TM = require("systems.TutorialManager")
   if TM.isActive() then
        print("[BottomNav][DIAG] TM active, registering hotspots")
       TM.registerHotspot("tab_character", 108,  2352, 216, 207)
       TM.registerHotspot("tab_log",       324,  2352, 216, 207)
       TM.registerHotspot("tab_town",      756,  2352, 216, 207)
       TM.registerHotspot("tab_dungeon",   972,  2352, 216, 207)
   else
        print("[BottomNav][DIAG] TM NOT active")
   end
end

--- 处理点击输入（接收设计空间坐标）
function BottomNav.handleInput(designX, designY)
    -- 全局锁定时不响应任何点击
    if allLocked_ then return end

    local touchBottom = NAV_CY + NAV_H * 0.5
    if designY > touchBottom then return end
    if designX < 0 or designX > NAV_W then return end

    -- 判断点击了哪个标签列
    local tabIndex = math.floor(designX / TAB_SPACING) + 1
    tabIndex = math.max(1, math.min(TAB_COUNT, tabIndex))

    -- 按列区分点击区域顶部：选中列使用弹出高度，其他列使用未选中高度
    local touchTop
    if tabIndex == selectedIndex then
        touchTop = SEL_BG_CY - SEL_H * 0.5
    else
        touchTop = UNSEL_BG_CY - UNSEL_H * 0.5
    end
    if designY < touchTop then return end

    -- 锁定标签不可点击
    if tabs[tabIndex].locked then return end

    if tabIndex ~= selectedIndex then
        selectedIndex = tabIndex
        print("[BottomNav] Selected: " .. tabs[tabIndex].name)
        local GameSFX = require("systems.GameSFX")
        GameSFX.playUIMove(2)  -- Tab 切换
    end
    return true  -- 命中了 BottomNav 区域
end

--- 检测坐标是否在标签栏点击区域内（设计空间坐标）
function BottomNav.hitTest(designX, designY)
    local touchBottom = NAV_CY + NAV_H * 0.5
    if designY > touchBottom then return false end
    if designX < 0 or designX > NAV_W then return false end
    -- 使用未选中标签的顶部作为保守判定
    local touchTop = UNSEL_BG_CY - UNSEL_H * 0.5
    if designY < touchTop then return false end
    return true
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
    -- 市场特权红点（有可观看广告）
    local okMP, MP = pcall(require, "ui.MarketPage")
    if okMP and MP and MP.hasPrivilegeRedDot then
        if MP.hasPrivilegeRedDot() then
            BottomNav.setBadge(4, true, "redDot")
            return
        end
    end
    -- 竞技场红点（有竞技券）
    local okAP, AP = pcall(require, "ui.ArenaPage")
    if okAP and AP and AP.hasTicketRedDot then
        if AP.hasTicketRedDot() then
            BottomNav.setBadge(4, true, "redDot")
            return
        end
    end
    -- 公会遗物角标（可强化→箭头，新遗物→红点）
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
