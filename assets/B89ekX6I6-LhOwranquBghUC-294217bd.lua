-- ============================================================================
-- BottomNav - 页面路由状态（底栏视觉已移除，入口迁到 TopBar）
-- 仍负责: 当前页、锁定、角标。draw/handleInput 为空实现。
-- ============================================================================

local GameEvents  = require("config.GameEvents")
local EventBus    = require("core.EventBus")
local PlayerStore = require("client.data.PlayerStore")

local BottomNav = {}

local TAB_COUNT = 5

local tabs = {
    { name = "角色", locked = true },  -- 由引导1解锁
    { name = "日志", locked = true },  -- 由引导3解锁
    { name = "战斗", locked = false },
    { name = "城镇", locked = true },  -- 由引导4解锁
    { name = "副本", locked = true },  -- 首通0305解锁
}

local selectedIndex = 3  -- 默认选中"战斗"
local allLocked_ = false

-- 各标签角标状态: tabBadges[i] = true 表示该标签需要显示角标
local tabBadges = {}
-- 各标签角标样式: tabBadgeStyle[i] = "redDot" 时使用红点，否则使用默认强化箭头
local tabBadgeStyle = {}

-- ======================== Public API ========================

function BottomNav.init(_vg)
    BottomNav.refreshUnlockState()

    EventBus.on(GameEvents.CURRENCY_CHANGED, function(data)
        if data and (data.arenaTicket ~= nil or data.privilegePoint ~= nil) then
            BottomNav.refreshTownBadge()
        end
    end)

    print("[BottomNav] init OK (state-only, HUD moved to TopBar)")
end

function BottomNav.update(_dt)
end

--- 底栏已全局隐藏，页面入口迁到 TopBar
function BottomNav.draw(_vg)
end

function BottomNav.handleInput(_designX, _designY)
    return nil
end

function BottomNav.hitTest(_designX, _designY)
    return false
end

function BottomNav.getSelectedIndex()
    return selectedIndex
end

function BottomNav.setSelectedIndex(index)
    if index >= 1 and index <= TAB_COUNT and not tabs[index].locked then
        selectedIndex = index
        print("[BottomNav] Selected: " .. tabs[index].name)
    end
end

function BottomNav.isTabLocked(tabIndex)
    local tab = tabs[tabIndex]
    return tab ~= nil and tab.locked == true
end

function BottomNav.getTabName(tabIndex)
    local tab = tabs[tabIndex]
    return tab and tab.name or ""
end

function BottomNav.getBadge(tabIndex)
    return tabBadges[tabIndex] == true, tabBadgeStyle[tabIndex]
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
