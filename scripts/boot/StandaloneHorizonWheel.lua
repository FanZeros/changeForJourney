-- ============================================================================
-- StandaloneHorizonWheel - 横屏滚轮路由与共享面板坐标
-- 坐标闭包供原输入复用；按压状态在滚轮绑定时传入，不缓存动态值。
-- ============================================================================

local Wheel = {}

---@param deps table
function Wheel.bind(deps)
    local logicalW, logicalH, dpr = deps.logicalW, deps.logicalH, deps.dpr
    local toDesign, pointerPosition = deps.toDesign, deps.pointerPosition
    local talentPageUsesWideLayout = deps.talentPageUsesWideLayout
    local syncTalentPageLayout = deps.syncTalentPageLayout
    local talentPageRightEdge = deps.talentPageRightEdge
    local Viewport, OfflineRewardOverlay = deps.Viewport, deps.OfflineRewardOverlay
    local BottomNav, CharacterPanel, CEPanel = deps.BottomNav, deps.CharacterPanel, deps.CEPanel
    local HeroRosterPanel, RewardPopup = deps.HeroRosterPanel, deps.RewardPopup
    local BlacksmithPage, ChurchPage = deps.BlacksmithPage, deps.ChurchPage
    local TalentPage, TavernPage, MarketPage = deps.TalentPage, deps.TavernPage, deps.MarketPage
    local DungeonBattleScene, TowerBattleScene = deps.DungeonBattleScene, deps.TowerBattleScene
    local DungeonPage, BackpackPanel = deps.DungeonPage, deps.BackpackPanel
    local LootBox, LootBoxPage, TaskPage = deps.LootBox, deps.LootBoxPage, deps.TaskPage
    local LevelUpPopup, OfflineRewardPanel = deps.LevelUpPopup, deps.OfflineRewardPanel
    local UpdateNoticePopup, PlayerInfoPanel = deps.UpdateNoticePopup, deps.PlayerInfoPanel
    local StartScreen, DarkTitleScreen = deps.StartScreen, deps.DarkTitleScreen
    local BattleTriPage, SweepDialog = deps.BattleTriPage, deps.SweepDialog
    local DamageStatsPanel, StageSelectDialog = deps.DamageStatsPanel, deps.StageSelectDialog
    local TerminalConfirmDialog = deps.TerminalConfirmDialog
    local IntroCutscene, LetterIntro, ScenarioDialogue = deps.IntroCutscene, deps.LetterIntro, deps.ScenarioDialogue
    local AwakeningArtwork = require("ui.character.hero.AwakeningArtwork")

    -- 横屏副本(5)页独占画布（全屏弹窗打开时让位）
    local function HorizonPageModalActive()
        if BottomNav.getSelectedIndex() ~= 5 then return false end
        if DungeonBattleScene.isOpen() or TowerBattleScene.isActive() then return false end
        if PlayerInfoPanel.isOpen() or LevelUpPopup.isOpen()
            or OfflineRewardPanel.isOpen() or RewardPopup.isOpen() then
            return false
        end
        return true
    end

    --- 玩家信息面板坐标。三行战斗里面板是全窗居中重画的，点击必须用同一套 letterbox。
    local function playerInfoDesignCoords(sx, sy)
        if BattleTriPage.isOpen() or TowerBattleScene.isActive() or DungeonBattleScene.isOpen() then
            local fit = math.min(logicalW() / 1080, logicalH() / 2400)
            return (sx - (logicalW() - 1080 * fit) * 0.5) / fit,
                   (sy - (logicalH() - 2400 * fit) * 0.5) / fit
        end
        local note = Viewport.getNote("center")
        if note then
            local cs = note.s * Viewport.DS
            return (sx - note.ox - Viewport.PANELS.center.bx * note.s) / cs,
                   (sy - note.oy) / cs
        end
        local fit = math.min(logicalW() / 1080, logicalH() / 2400)
        return (sx - (logicalW() - 1080 * fit) * 0.5) / fit,
               (sy - (logicalH() - 2400 * fit) * 0.5) / fit
    end

    --- 归属面板奖励弹窗的设计坐标：左/右栏走各自 Viewport note，中栏（三行模式）走全窗 letterbox
    local function rewardPopupDesignCoords(sx, sy, pid)
        if pid == 'center' and (BattleTriPage.isOpen() or DungeonBattleScene.isOpen()) then
            return playerInfoDesignCoords(sx, sy)
        end
        local note = Viewport.getNote(pid)
        local pdef = Viewport.PANELS[pid]
        if note and pdef then
            local cs = note.s * Viewport.DS
            return (sx - note.ox - pdef.bx * note.s) / cs,
                   (sy - note.oy - pdef.by * note.s) / cs
        end
        return playerInfoDesignCoords(sx, sy)
    end

    -- 事件坐标 -> 面板命中；全局模态返回 ('modal', dx, dy)
    local function HorizonResolveMouse()
        local mousePos = pointerPosition()
        local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
        -- 离线收益始终全窗居中，优先于下层面板和装备详情路由。
        if OfflineRewardPanel.isOpen() then
            local dx, dy = OfflineRewardOverlay.toDesign(sx, sy)
            return 'offline', dx, dy
        end
        -- 升级层与 finishFrame 共用宿主逻辑坐标，三行/塔/普通模式不得各算一次 letterbox。
        -- 位于 PlayerInfo/奖励/装备浮层之上，Offline 保持原上层优先级。
        if LevelUpPopup.isOpen() then return 'levelup', sx, sy end
        -- 玩家信息是全窗 letterbox，不能走左/中/右栏换算，否则点面板中部会被当成点外面
        if PlayerInfoPanel.isOpen() then
            local pdx, pdy = playerInfoDesignCoords(sx, sy)
            return 'playerinfo', pdx, pdy
        end
        if RewardPopup.isLarge() then return 'rewardlarge', sx, sy end
        -- 全局奖励弹窗：归属面板时点击路由到该面板（面板内任意点击可交互/关闭，
        -- 面板外点击 rp_out 关闭）；无归属时所有点击都路由给它（任意点击可关闭）
        if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
            local rpanel = RewardPopup.currentPanel()
            if rpanel then
                local pid2
                if BattleTriPage.isOpen() then
                    local ps = logicalH() / 1080
                    local leftW = 486 * ps
                    if sx < leftW then pid2 = 'left'
                    elseif sx > logicalW() - leftW then pid2 = 'right'
                    else pid2 = 'center' end
                else
                    pid2 = Viewport.hit(sx, sy, H_ox, H_oy, H_s)
                end
                if pid2 == rpanel then
                    local mx, my = rewardPopupDesignCoords(sx, sy, pid2)
                    H_focusPanel = pid2
                    return pid2, mx, my
                end
                return 'rp_out', 0, 0
            end
            local pdx, pdy = playerInfoDesignCoords(sx, sy)
            return 'modal', pdx, pdy
        end
        -- 塔可能保留三行页打开态；功绩覆盖必须先于 tri/tower 路由。
        if TowerBattleScene.isActive() and TaskPage.isOpen() then
            local layout = TowerBattleScene.getLayout(logicalW(), logicalH())
            if sx >= layout.left.x and sx < layout.left.x + layout.left.w then
                local dx, dy = require("ui.tower.TowerLayout").toTask(layout, sx, sy)
                return 'left', dx, dy
            end
            return 'none', 0, 0 -- 左栏之外仍消费，不操作被覆盖的塔/其它业务页。
        end
        -- 副本页独占横屏画布；不把左右栏的局部坐标冒充副本坐标。
        if HorizonPageModalActive() then
            DungeonPage.setLandscapeMode(true)
            local fit = math.min(logicalW() / 1920, logicalH() / 1080)
            return 'modal', (sx - (logicalW() - 1920 * fit) * 0.5) / fit,
                            (sy - (logicalH() - 1080 * fit) * 0.5) / fit
        end
        if DungeonBattleScene.isOpen() then return 'modal', sx, sy end
        if TowerBattleScene.isActive() then return 'modal', sx, sy end
        -- [三行并行] 战斗模式命中: 面板按战斗布局定位，中段为三行战斗区
        if BattleTriPage.isOpen() then
            -- [全窗模态] 选关/扫荡/统计弹窗打开时，全窗口点击直通三行页弹窗层（含左右面板区）
            if SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen()
                or TerminalConfirmDialog.isOpen() then
                return 'tri', sx, sy
            end
            local ps = logicalH() / 1080
            -- 锻炉页占据中栏（Viewport.center，窗口 x∈[486ps,972ps]）：
            -- 命中该区返回 'center' + 设计坐标，交给 BlacksmithPage 输入链。
            -- 注意 tri 模式右栏被挪到窗口右缘，不能用 Viewport.hit（其 right 区与实际不符）
            if BlacksmithPage.isOpen() then
                local leftW = 486 * ps
                if sx >= leftW and sx < leftW + 486 * ps then
                    local cs = ps * Viewport.DS
                    return 'center', (sx - leftW) / cs, sy / cs
                end
            end
            if talentPageUsesWideLayout() then
                local rightEdge = talentPageRightEdge(0, ps)
                if sx >= 0 and sx < rightEdge then
                    local cs = ps * Viewport.DS
                    return 'left', sx / cs, sy / cs
                end
            end
            local leftW = 486 * ps
            local rightW = leftW
            if sx < leftW then
                return 'left', sx / (ps * 0.45), sy / (ps * 0.45)
            elseif sx > logicalW() - rightW then
                return 'right', (sx - (logicalW() - rightW)) / (rightW / 1080), sy / (ps * 0.45)
            end
            return 'tri', sx, sy
        end
        if talentPageUsesWideLayout() then
            local rightEdge = talentPageRightEdge(H_ox, H_s)
            if sx >= H_ox and sx < rightEdge then
                local cs = H_s * Viewport.DS
                return 'left', (sx - H_ox) / cs, (sy - H_oy) / cs
            end
        end
        local pid, dx, dy = Viewport.hit(sx, sy, H_ox, H_oy, H_s)
        if StartScreen.isOpen() and not H_SKIP_START then return 'none', dx, dy end
        if DungeonBattleScene.isOpen() or PlayerInfoPanel.isOpen()
            or OfflineRewardPanel.isOpen() then
            return 'modal', dx or 0, dy or 0
        end
        if not pid then return 'none', 0, 0 end
        H_focusPanel = pid  -- 当前焦点面板（奖励弹窗 show 时记录触发面板用）
        H_lastPanel = pid
        return pid, dx, dy
    end

    -- 坐标先绑定供 Down/Move/Up 共用；按压闭包就绪后再绑定滚轮。
    local function bindWheel(gestureCtx)
        local marqueeGesture = gestureCtx.marqueeGesture
        local getLevelPress, cancelUnderlyingPress = gestureCtx.getLevelPress, gestureCtx.cancelUnderlyingPress
        return function(eventType, eventData)
            local blocked = gestureCtx.artworkBlocked and gestureCtx.artworkBlocked() or false
            AwakeningArtwork.observe(gestureCtx.RT or {}, blocked)
            if AwakeningArtwork.hasPress() or (AwakeningArtwork.isOpen() and not blocked) then
                AwakeningArtwork.cancelPress()
                cancelUnderlyingPress()
                return
            end
            if marqueeGesture.hasPress() then marqueeGesture.observe(); return end
            -- [UpdateNoticePopup] 全窗模态吞掉滚轮
            if UpdateNoticePopup.isOpen() then return end
            -- [DarkTitleScreen] 标题期吞掉滚轮
            if DarkTitleScreen.isOpen() then return end
            if LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive() then return end
            local wheel = eventData["Wheel"]:GetInt()
            if wheel == 0 then return end
            local mousePos = pointerPosition()
            local sx = mousePos.x / dpr()
            local sy = mousePos.y / dpr()
            local csx, csy = toDesign(sx, sy)
            if CEPanel.handleWheel(csx, csy, wheel, logicalH()) then return end
            if OfflineRewardOverlay.handleWheel(wheel) then return end
            if LevelUpPopup.isOpen() or getLevelPress() then
                cancelUnderlyingPress()
                return
            end
            -- 玩家信息高于经营/战斗页面：滚轮不能先缩放古树或命中战斗装备袋。
            if PlayerInfoPanel.isOpen() then
                local msx, msy = playerInfoDesignCoords(csx, csy)
                PlayerInfoPanel.handleScroll(wheel, msx, msy)
                return
            end
            if RewardPopup.handleLargeScroll(wheel, csx, csy, logicalW(), logicalH()) then return end
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

            -- 副本独占全窗时，先于隐藏的古树、选关及装备袋消费滚轮。
            if DungeonBattleScene.isOpen() then DungeonBattleScene.handleScroll(wheel) return end
            if HorizonPageModalActive() then return end

            -- 塔内功绩覆盖阻断其它业务滚轮；只有左栏可滚奖励轨道。
            if TowerBattleScene.isActive() and TaskPage.isOpen() then
                local layout = TowerBattleScene.getLayout(logicalW(), logicalH())
                if csx >= layout.left.x and csx < layout.left.x + layout.left.w then TaskPage.handleScroll(wheel) end
                return
            end
            -- 塔只读路线/强化滚动先于隐藏主线装备袋和右栏名册；模态也吞掉滚轮。
            if TowerBattleScene.isActive() then
                TowerBattleScene.handleScroll(wheel, csx, csy, logicalW(), logicalH())
                return
            end

            if TerminalConfirmDialog.isOpen() then
                if BattleTriPage.isOpen() then BattleTriPage.handleScroll(wheel, csx, csy) end
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

            -- 弹窗横跨三栏；任何位置的滚轮都交给选关，避免误滚角色列表。
            if BattleTriPage.isOpen() and StageSelectDialog.isOpen() then
                BattleTriPage.handleScroll(wheel, csx, csy)
                return
            end
            -- 装备袋只吃覆盖矩形内的滚轮，左右栏仍滚自己的列表
            if BattleTriPage.handleScroll(wheel, csx, csy) then return end

            -- 全屏战斗场景
            if DungeonBattleScene.isOpen() then DungeonBattleScene.handleScroll(wheel) return end
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
            -- 锻炉页在中栏：优先接管
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

    return {
        HorizonPageModalActive = HorizonPageModalActive,
        playerInfoDesignCoords = playerInfoDesignCoords,
        rewardPopupDesignCoords = rewardPopupDesignCoords,
        HorizonResolveMouse = HorizonResolveMouse,
        bindWheel = bindWheel,
    }
end

return Wheel
