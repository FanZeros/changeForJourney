-- ============================================================================
-- StandaloneHorizonWheel - 横屏滚轮路由；只抽取原处理函数，不改变消费顺序或坐标。
-- 页面依赖由 Input.bind 传入，不在模块加载时另行 require 或绑定事件。
-- ============================================================================

---@class StandaloneHorizonWheelContext
---@field deps table<string, table> 原输入模块已持有的页面、Viewport 与离线覆盖实例
---@field native fun(): table, number, number, number 动态返回 RT、H_ox、H_oy、H_s，不缓存原生状态
---@field logicalW fun(): number
---@field logicalH fun(): number
---@field dpr fun(): number
---@field toDesign fun(sx: number, sy: number): number, number
---@field pointerPosition fun(): any 查询原鼠标/触摸闭包，不缓存按压位置
---@field levelPress fun(): boolean 查询原升级按压闭包
---@field recordInputActive fun(): boolean
---@field cancelUnderlyingPress fun()
---@field playerInfoDesignCoords fun(sx: number, sy: number): number, number
---@field rewardPopupDesignCoords fun(sx: number, sy: number, pid: string): number, number
---@field syncTalentPageLayout fun()
---@field HorizonResolveMouse fun(): string, number, number
---@field HorizonPageModalActive fun(): boolean

local Wheel = {}

--- 返回处理函数；全局接口仍由 Input.bind 以原名称绑定。
---@param ctx StandaloneHorizonWheelContext
---@return fun(eventType: string, eventData: MouseWheelEventData)
function Wheel.bind(ctx)
    local deps = ctx.deps
    local UpdateNoticePopup, DarkTitleScreen = deps.UpdateNoticePopup, deps.DarkTitleScreen
    local LetterIntro, ScenarioDialogue = deps.LetterIntro, deps.ScenarioDialogue
    local SamsaraRecordPanel, CEPanel = deps.SamsaraRecordPanel, deps.CEPanel
    local OfflineRewardOverlay, LevelUpPopup = deps.OfflineRewardOverlay, deps.LevelUpPopup
    local PlayerInfoPanel, RewardPopup = deps.PlayerInfoPanel, deps.RewardPopup
    local BattleTriPage, Viewport = deps.BattleTriPage, deps.Viewport
    local TowerBattleScene, TaskPage = deps.TowerBattleScene, deps.TaskPage
    local TalentPage, OfflineRewardPanel = deps.TalentPage, deps.OfflineRewardPanel
    local StageSelectDialog, DungeonBattleScene = deps.StageSelectDialog, deps.DungeonBattleScene
    local HeroRosterPanel, LootBoxPage, LootBox = deps.HeroRosterPanel, deps.LootBoxPage, deps.LootBox
    local BackpackPanel, ChurchPage = deps.BackpackPanel, deps.ChurchPage
    local TavernPage, MarketPage = deps.TavernPage, deps.MarketPage
    local CharacterPanel, BlacksmithPage, BottomNav = deps.CharacterPanel, deps.BlacksmithPage, deps.BottomNav
    local logicalW, logicalH, dpr, toDesign = ctx.logicalW, ctx.logicalH, ctx.dpr, ctx.toDesign
    local pointerPosition, recordInputActive = ctx.pointerPosition, ctx.recordInputActive
    local cancelUnderlyingPress = ctx.cancelUnderlyingPress
    local playerInfoDesignCoords, rewardPopupDesignCoords = ctx.playerInfoDesignCoords, ctx.rewardPopupDesignCoords
    local syncTalentPageLayout = ctx.syncTalentPageLayout
    local HorizonResolveMouse, HorizonPageModalActive = ctx.HorizonResolveMouse, ctx.HorizonPageModalActive

    return function(eventType, eventData)
        -- [UpdateNoticePopup] 全窗模态吞掉滚轮
        if UpdateNoticePopup.isOpen() then return end
        -- [DarkTitleScreen] 标题期吞掉滚轮
        if DarkTitleScreen.isOpen() then return end
        if LetterIntro.isOpen() or ScenarioDialogue.isSliceActive() or ScenarioDialogue.isActive() then return end
        local wheel = eventData["Wheel"]:GetInt()
        if wheel == 0 then return end
        if recordInputActive() then
            SamsaraRecordPanel.handleWheel(wheel)
            return
        end
        local mousePos = pointerPosition()
        local sx = mousePos.x / dpr()
        local sy = mousePos.y / dpr()
        local csx, csy = toDesign(sx, sy)
        if CEPanel.handleWheel(csx, csy, wheel, logicalH()) then return end
        if OfflineRewardOverlay.handleWheel(wheel) then return end
        if LevelUpPopup.isOpen() or ctx.levelPress() then
            cancelUnderlyingPress()
            return
        end
        -- 玩家信息高于经营/战斗页面：滚轮不能先缩放古树或命中战斗装备袋。
        if PlayerInfoPanel.isOpen() then
            local msx, msy = playerInfoDesignCoords(csx, csy)
            PlayerInfoPanel.handleScroll(wheel, msx, msy)
            return
        end
        -- 归属面板的奖励弹窗：指针在其面板内且命中面板时滚轮滚弹窗列表
        if RewardPopup.isOpen() and not RewardPopup.currentRowTag() and RewardPopup.currentPanel() then
            local pid2
            if BattleTriPage.isOpen() then
                local ps = logicalH() / 1080
                local leftW = 486 * ps
                if csx < leftW then pid2 = 'left'
                elseif csx > logicalW() - leftW then pid2 = 'right'
                else pid2 = 'center' end
            else
                -- 与原函数在命中时读取全局值的时机相同；RT 仍由宿主闭包持有。
                local _, H_ox, H_oy, H_s = ctx.native()
                pid2 = Viewport.hit(csx, csy, H_ox, H_oy, H_s)
            end
            if pid2 == RewardPopup.currentPanel() then
                local mx, my = rewardPopupDesignCoords(csx, csy, pid2)
                if RewardPopup.hitPanel(mx, my) then
                    RewardPopup.handleScroll(wheel)
                    return
                end
            end
        end
        if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
            local pdx, pdy = playerInfoDesignCoords(csx, csy)
            if RewardPopup.hitPanel(pdx, pdy) then
                RewardPopup.handleScroll(wheel)
                return
            end
        end

        -- 塔内功绩覆盖阻断其它业务滚轮；只有左栏可滚奖励轨道。
        if TowerBattleScene.isActive() and TaskPage.isOpen() then
            if csx >= 0 and csx <= 486 * (logicalH() / 1080) then TaskPage.handleScroll(wheel) end
            return
        end

        -- 古树打开且指针在页面上时，滚轮只做星图缩放，不交给战斗区
        if TalentPage.isOpen() then
            syncTalentPageLayout()
            local pid, msx, msy = HorizonResolveMouse()
            if pid == "left" then
                TalentPage.handleScroll(wheel, msx, msy)
                print("[TalentPage] wheel zoom wheel=" .. tostring(wheel))
                return
            end
        end

        -- 全局领奖 / 离线收益覆盖三栏时先消费滚轮，不能被中栏装备袋抢走。
        if OfflineRewardPanel.isOpen() then
            OfflineRewardPanel.handleScroll(wheel)
            return
        end
        if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
            local pdx, pdy = playerInfoDesignCoords(csx, csy)
            if RewardPopup.hitPanel(pdx, pdy) then
                RewardPopup.handleScroll(wheel)
                return
            end
        end

        -- 弹窗横跨三栏；任何位置的滚轮都交给选关，避免误滚角色列表。
        -- 保留历史 sx/sy 入参，本次抽取不修正其坐标语义。
        if BattleTriPage.isOpen() and StageSelectDialog.isOpen() then
            BattleTriPage.handleScroll(wheel, sx, sy)
            return
        end
        -- 装备袋只吃覆盖矩形内的滚轮，左右栏仍滚自己的列表
        if BattleTriPage.handleScroll(wheel, sx, sy) then return end

        -- 全屏战斗场景
        if DungeonBattleScene.isOpen() then DungeonBattleScene.handleScroll(wheel) return end
        -- 全屏弹窗
        if OfflineRewardPanel.isOpen() then OfflineRewardPanel.handleScroll(wheel) return end

        -- [按鼠标位置路由] 滚轮作用于鼠标所在的面板（左右面板可同开二级页，
        -- 不再依赖"最近点击面板"记录；滚到哪边就滚哪边的列表）
        local pid, msx, msy = HorizonResolveMouse()
        if pid == 'playerinfo' then
            PlayerInfoPanel.handleScroll(wheel, msx, msy)
            return
        end

        -- [底栏移除] 副本页全窗模态：不透传滚轮
        if pid == 'modal' and HorizonPageModalActive() then
            return
        end

        if pid == 'modal' then
            PlayerInfoPanel.handleScroll(wheel, msx, msy)
            return
        end

        if HeroRosterPanel.isVisible() then
            HeroRosterPanel.handleScroll(wheel)
            return
        end

        if pid == 'left' then
            if LootBoxPage.isOpen() then LootBox.handleScroll(wheel) return end
            if TaskPage.isOpen() then TaskPage.handleScroll(wheel) return end
            if BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then BackpackPanel.handleScroll(wheel, msx, msy) return end
            if TalentPage.isOpen() then TalentPage.handleScroll(wheel, msx, msy) return end
            if ChurchPage.isOpen() then ChurchPage.handleScroll(wheel, msx, msy) return end
            if TavernPage.isOpen() then TavernPage.handleScroll(wheel) return end
            if MarketPage.isOpen() then MarketPage.handleScroll(wheel) return end
            return
        end

        if pid == 'right' then
            CharacterPanel.handleScroll(wheel, msx, msy)
            return
        end

        if pid == 'tri' then
            BattleTriPage.handleScroll(wheel)
            return
        end

        -- center：主视图 Tab 页
        -- [锻炉双页 0929] 锻炉页在中栏：优先接管
        if BlacksmithPage.isOpen() then
            BlacksmithPage.handleScroll(wheel, msx, msy)
            return
        end
        local tab = BottomNav.getSelectedIndex()
        if tab == 1 then
            CharacterPanel.handleScroll(wheel, msx, msy)
        end
    end
end

return Wheel
