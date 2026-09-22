-- ============================================================================
-- BottomNav - 页面路由状态（底栏视觉已全局移除，入口迁到 TopBar）
-- 仍负责: 当前页码、锁定、角标。draw/handleInput/hitTest 为空实现。
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

-- 全局锁定标志（终焉神殿等场景下锁定所有标签）
local allLocked_ = false

-- 各标签角标状态: tabBadges[i] = true 表示该标签需要显示角标
local tabBadges = {}
-- 各标签角标样式: tabBadgeStyle[i] = "redDot" 时使用红点，否则使用默认强化箭头
local tabBadgeStyle = {}

-- ======================== Public API ========================

function BottomNav.init(_vg)
    BottomNav.refreshUnlockState()

    -- 监听货币变化，刷新城镇标签红点（竞技券/特权点消耗后及时清除）
    EventBus.on(GameEvents.CURRENCY_CHANGED, function(data)
        if data and (data.arenaTicket ~= nil or data.privilegePoint ~= nil) then
            BottomNav.refreshTownBadge()
        end
    end)

    print("[BottomNav] init OK (state-only, HUD moved to TopBar)")
end

--- 底栏已移除，无动画（保留接口兼容旧调用）
function BottomNav.update(_dt)
end

--- 底栏已全局隐藏，页面入口迁到 TopBar
function BottomNav.draw(_vg)
end

--- 底栏已隐藏，保留空实现避免旧调用报错
function BottomNav.handleInput(_designX, _designY)
    return nil
end

--- 底栏已隐藏
function BottomNav.hitTest(_designX, _designY)
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

--- 查询指定页签是否锁定（TopBar 页面入口置灰用）
---@param index number 标签索引 (1~5)
---@return boolean
function BottomNav.isTabLocked(index)
    local tab = tabs[index]
    if not tab then return false end
    return tab.locked and true or false
end

--- 设置指定标签的角标显示状态
---@param tabIndex number 标签索引 (1~5)
---@param show boolean 是否显示角标
---@param style? string 角标样式: "redDot" 红点 | nil 默认强化箭头
function BottomNav.setBadge(tabIndex, show, style)
    tabBadges[tabIndex] = show or false
    tabBadgeStyle[tabIndex] = style  -- nil 时恢复为默认箭头样式
end

--- 读取指定标签的角标状态（TopBar 页面入口角标用）
---@param tabIndex number 标签索引 (1~5)
---@return boolean show, string|nil style
function BottomNav.getBadge(tabIndex)
    return tabBadges[tabIndex] == true, tabBadgeStyle[tabIndex]
end

--- 刷新城镇标签(Tab 4)角标：古树(天赋) + 教堂(转职/神器) + 铁匠铺(可强化) + 遗物
function BottomNav.refreshTownBadge()
    -- 古树天赋点未用 → 箭头
    local okTP, TP = pcall(require, "ui.TalentPage")
    if okTP and TP and TP.hasAnyUnusedTalent then
        local ok, unused = pcall(TP.hasAnyUnusedTalent)
        if ok and unused then
            BottomNav.setBadge(4, true, nil)
            return
        end
    end
    -- 教堂角标（神器→箭头，转职→红点）
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
    -- 遗物角标（可强化→箭头，新遗物→红点）
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
function BottomNav.refreshUnlockState()
    local ok, TM = pcall(require, "systems.TutorialManager")
    if not ok then return end

    if TM.isPanelUnlocked("character_panel") then tabs[1].locked = false end
    if TM.isPanelUnlocked("log_panel")      then tabs[2].locked = false end
    if TM.isPanelUnlocked("town_panel")     then tabs[4].locked = false end

    -- tab5：副本（首通通关0305解锁）
    local battleData = PlayerStore.Get("battle")
    local maxStageId = battleData and tonumber(battleData.maxStageId) or 0
    if maxStageId > 305 then tabs[5].locked = false end
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
