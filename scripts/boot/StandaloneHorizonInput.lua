-- ============================================================================
-- StandaloneHorizonInput - 横屏输入绑定（绘制与坐标变换由 StandaloneHorizon 提供）
-- 共享运行时与离线收益覆盖实例通过 ctx 复用。
-- ============================================================================

local TopBar            = require("ui.hud.TopBar")
local BottomNav         = require("ui.hud.BottomNav")
local BattleScene       = require("ui.battle.scene.BattleScene")
local CharacterPanel    = require("ui.character.panel.CharacterPanel")
local CEPanel           = require("ui.dev.CEPanel")
local HeroRosterPanel   = require("ui.character.hero.HeroRosterPanel")
local RewardPopup       = require("ui.hud.popup.RewardPopup")
local TownScene         = require("ui.town.TownScene")
local BlacksmithPage    = require("ui.blacksmith.BlacksmithPage")
local ChurchPage        = require("ui.church.ChurchPage")
local TalentPage        = require("ui.church.talent.TalentPage")
local TavernPage        = require("ui.tavern.TavernPage")
local MarketPage        = require("ui.market.MarketPage")
local DungeonBattleScene = require("ui.dungeon.DungeonBattleScene")
local TowerBattleScene   = require("ui.tower.TowerBattleScene")
local DungeonPage        = require("ui.dungeon.DungeonPage")
local BackpackPanel      = require("ui.backpack.BackpackPanel")
local LootBox           = require("ui.loot.LootBox")
local LootBoxPage       = require("ui.loot.LootBoxPage")
local TaskPage          = require("ui.story.task.TaskPage")
local LevelUpPopup      = require("ui.hud.popup.LevelUpPopup")
local OfflineRewardPanel = require("ui.hud.popup.OfflineRewardPanel")
local UpdateNoticePopup = require("ui.hud.popup.UpdateNoticePopup")
local PlayerInfoPanel   = require("ui.hud.popup.PlayerInfoPanel")
local StartScreen       = require("ui.story.gate.StartScreen")
local DarkTitleScreen   = require("ui.story.gate.DarkTitleScreenGate")
local BattleTriPage     = require("ui.battle.tri.BattleTriPage")
local SweepDialog       = require("ui.battle.stage.SweepDialog")
local DamageStatsPanel  = require("ui.battle.popup.DamageStatsPanel")
local StageSelectDialog = require("ui.battle.stage.StageSelectDialog")
local IntroCutscene      = require("ui.story.gate.IntroCutscene")
local LetterIntro        = require("ui.story.gate.LetterIntro")
local CharacterDetail    = require("ui.character.detail.CharacterDetail")
local EquipmentBag       = require("ui.character.equip.EquipmentBag")
local EquipCrossDrag     = require("ui.character.EquipCrossDrag")
local ScenarioDialogue   = require("ui.story.ScenarioDialogue")
local TutorialManager    = require("systems.TutorialManager")

local Input = {}

---@param ctx table
function Input.bind(ctx)
    local vg, logicalW, logicalH = ctx.vg, ctx.logicalW, ctx.logicalH
    local windowW, windowH, dpr = ctx.windowW, ctx.windowH, ctx.dpr
    local DESIGN_W, DESIGN_H, bootReady_ = ctx.DESIGN_W, ctx.DESIGN_H, ctx.bootReady_
    local toDesign = ctx.toDesign
    local talentPageUsesWideLayout = ctx.talentPageUsesWideLayout
    local syncTalentPageLayout = ctx.syncTalentPageLayout
    local talentPageRightEdge = ctx.talentPageRightEdge
    local equipOverlayDesign = ctx.equipOverlayDesign
    local seamHitAt = ctx.seamHitAt
    local RT, Viewport, OfflineRewardOverlay = ctx.RT, ctx.Viewport, ctx.OfflineRewardOverlay

    local TAP_THRESHOLD = 15
    local MIN_TAP_INTERVAL = 0.12
    local lastTapTime = 0
    local pressStartDX = 0
    local pressStartDY = 0
    local pressValid = false
    local touchPosition = nil ---@type any
    local function pointerPosition()
        return touchPosition or input:GetMousePosition()
    end
    -- 遗匣按压由左栏捕获；移出左栏后不再把同次拖拽转交右栏/战斗。
    local lootPress = false

    -- [底栏移除] 横屏副本(5)页全窗竖版模态是否激活（全屏弹窗打开时让位）
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
        if BattleTriPage.isOpen() then
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
        if pid == 'center' and BattleTriPage.isOpen() then
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
        -- 玩家信息是全窗 letterbox，不能走左/中/右栏换算，否则点面板中部会被当成点外面
        if PlayerInfoPanel.isOpen() then
            local pdx, pdy = playerInfoDesignCoords(sx, sy)
            return 'playerinfo', pdx, pdy
        end
        -- 三行全局奖励 / 离线收益 / 通天塔离线收益使用居中的 1080×2400 letterbox。
        if (OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen())
            and (BattleTriPage.isOpen() or TowerBattleScene.isActive()) then
            local pdx, pdy = playerInfoDesignCoords(sx, sy)
            return 'modal', pdx, pdy
        end
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
        -- [底栏移除] 横屏副本(5)页全窗竖版模态：中段命中映射到设计坐标；
        -- 左右栏让出（TopBar 页签/角色面板仍可点），全屏弹窗打开时让位
        if HorizonPageModalActive() then
            local ps = logicalH() / 1080
            local leftW = 486 * ps
            if sx >= leftW and sx <= logicalW() - leftW then
                local fit = math.min(logicalW() / DESIGN_W(), logicalH() / DESIGN_H())
                return 'modal', (sx - (logicalW() - DESIGN_W() * fit) * 0.5) / fit,
                                (sy - (logicalH() - DESIGN_H() * fit) * 0.5) / fit
            end
        end
        -- [三行并行] 战斗模式命中: 面板按战斗布局定位，中段为三行战斗区
        if BattleTriPage.isOpen() then
            -- [全窗模态] 选关/扫荡/统计弹窗打开时，全窗口点击直通三行页弹窗层（含左右面板区）
            if SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen() then
                return 'tri', sx, sy
            end
            local ps = logicalH() / 1080
            -- [锻炉双页 0929] 锻炉页占据中栏（Viewport.center，窗口 x∈[486ps,972ps]）：
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
        if TowerBattleScene.isActive() then
            return 'modal', sx, sy
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
        if DungeonBattleScene.isOpen()
            or LevelUpPopup.isOpen() or PlayerInfoPanel.isOpen()
            or OfflineRewardPanel.isOpen() then
            return 'modal', dx or 0, dy or 0
        end
        if not pid then return 'none', 0, 0 end
        H_focusPanel = pid  -- 当前焦点面板（奖励弹窗 show 时记录触发面板用）
        H_lastPanel = pid
        return pid, dx, dy
    end

    local equipOverlayPress = false
    local equipOverlayStartX, equipOverlayStartY = 0, 0
    -- [浮选详情修复] 本次按下刚顺手关掉了浮选详情：按下继续下放给底层页面（恢复拖拽），
    -- 但松开时不按 tap 派发点击，避免"点空白关详情"误触页面按钮。
    local detailDismissPress = false
    local equipmentPressPanel = nil
    ---@type integer|nil
    local offlineTouchId = nil

    --- 离线弹窗接管时仅释放下层按压，不派发点击或装备落点。
    local function cancelUnderlyingPress()
        if EquipCrossDrag.isArmed() then EquipCrossDrag.cancel() end
        if equipOverlayPress then
            require("ui.character.equip.EquipmentDetail").handleDragEnd()
        end
        if lootPress then LootBox.handleDragEnd(-1, -1) end
        if equipmentPressPanel == 'left' and BackpackPanel.isOpen() then
            BackpackPanel.handleDragEnd(-1, -1)
        end
        if equipmentPressPanel == 'right' or CharacterPanel.isDraggingCard() then
            CharacterPanel.handleDragEnd(-1, -1)
        end
        if equipmentPressPanel == 'center' and BlacksmithPage.isOpen() then
            BlacksmithPage.handleDragEnd(-1, -1)
        end
        if equipmentPressPanel == 'tri' then
            BattleTriPage.handleDragEnd(-1, -1)
        end
        equipOverlayPress, lootPress, pressValid, detailDismissPress = false, false, false, false
        equipmentPressPanel = nil
    end

    local function offlineInputActive()
        return OfflineRewardPanel.isOpen() and not UpdateNoticePopup.isOpen()
            and not DarkTitleScreen.isOpen() and not LetterIntro.isOpen()
            and not IntroCutscene.isActive() and not ScenarioDialogue.isActive()
    end

    local function tutorialInputActive()
        return TutorialManager.isActive() and TutorialManager.isInputActive()
            and not OfflineRewardPanel.isOpen() and not UpdateNoticePopup.isOpen()
            and not DarkTitleScreen.isOpen() and not LetterIntro.isOpen()
            and not IntroCutscene.isActive() and not ScenarioDialogue.isActive()
            and not DungeonBattleScene.isOpen() and not TowerBattleScene.isActive()
    end
    local tutorialPress = false
    local tutorialBlockedPress = false
    local tutorialStartX, tutorialStartY = 0, 0

    function HandleMouseButtonDownHorizon(eventType, eventData)
        tutorialPress, tutorialBlockedPress = false, false
        if OfflineRewardPanel.isOpen() then cancelUnderlyingPress() end
        equipmentPressPanel = nil
        detailDismissPress = false  -- [浮选详情修复] 每次按下先复位，防早退路径残留误抑制下次 tap
        if vg() then
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            if CEPanel.handleDown(sx, sy, logicalH()) then
                if OfflineRewardPanel.isOpen() then OfflineRewardOverlay.cancel() end
                return
            end
        end
        if not bootReady_() then return end
        -- [UpdateNoticePopup] 全窗模态：弹窗期间吞掉按下，点击穿透不到下层面板（关闭由 ButtonUp 触发）
        if UpdateNoticePopup.isOpen() then
            pressValid = true
            pressStartDX, pressStartDY = 0, 0
            return
        end
        -- [DarkTitleScreen] 标题期吞掉按下（继续由 ButtonUp 触发）
        if DarkTitleScreen.isOpen() then return end
        -- [LetterIntro] 开场期也要记 pressValid，否则抬起被当成无效点击
        if LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive() then
            pressValid = true
            pressStartDX, pressStartDY = 0, 0
            return
        end
        local button = eventData["Button"]:GetInt()
        if tutorialInputActive() then
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            if button == MOUSEB_LEFT then
                tutorialPress = true
                tutorialStartX, tutorialStartY = sx, sy
                if not TutorialManager.canPointerStart(sx, sy) then
                    tutorialBlockedPress = true
                    cancelUnderlyingPress()
                    return
                end
            elseif not TutorialManager.canPointerStart(sx, sy) then
                return
            end
        end
        if OfflineRewardPanel.isOpen() then
            if offlineTouchId ~= nil then return end
            cancelUnderlyingPress()
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            OfflineRewardOverlay.handleDown(sx, sy, button)
            return
        end
        if button == MOUSEB_LEFT then
            detailDismissPress = false
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            local dx, dy, ED = equipOverlayDesign(sx, sy)
            if dx then
                equipOverlayPress = true
                equipOverlayStartX, equipOverlayStartY = sx, sy
                pressValid = true
                ED.handleDragBegin(dx, dy)
                print("[Horizon] 详情浮层按下")
                return
            end
            -- [浮选详情修复] 详情开着时按下空白：关掉详情，但不再吞掉这次按下——
            -- 继续走下方正常路由，让底层页面收到 handleDragBegin（列表拖拽/装备拖拽可用）。
            -- 松开时由 detailDismissPress 抑制 tap 派发，保留“第一次点击只关详情、不误触按钮”语义。
            local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
            local preserveComparison = false
            if EquipmentDetail.isPinned() and CharacterDetail.isEquipTab() then
                local pid, px, py = HorizonResolveMouse()
                if pid == 'right' or (pid == 'center' and BottomNav.getSelectedIndex() == 1) then
                    local panel = require("ui.character.detail.CharacterDetailEquip")
                    preserveComparison = panel.containsComparisonPoint(px, py)
                end
            end
            if EquipmentDetail.isCompactCorner() and not preserveComparison then
                EquipmentDetail.close()
                equipOverlayPress = false
                detailDismissPress = true
                print("[Horizon] 按下关闭装备详情并下放拖拽")
            else
                equipOverlayPress = false
            end
        end
        if button == MOUSEB_RIGHT then
            if RewardPopup.isOpen() or OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen() then return end
            local pid, dx, dy = HorizonResolveMouse()
            if pid == 'tri' then
                BattleTriPage.handleRightClick(dx, dy)
                return
            end
            if pid == 'playerinfo' then
                if CharacterPanel.handleRightClick then CharacterPanel.handleRightClick(dx, dy) end
                return
            end
            if pid == 'right' or pid == 'center' then
                if CharacterPanel.handleRightClick then CharacterPanel.handleRightClick(dx, dy) end
                return
            end
            if pid == 'left' then
                if LootBoxPage.isOpen() then
                    LootBoxPage.handleRightClick(dx, dy)
                    return
                end
                if not TaskPage.isOpen() and BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then
                    BackpackPanel.handleRightClick(dx, dy)
                end
                return
            end
            return
        end
        if button ~= MOUSEB_LEFT then return end
        lootPress = false
        LootBox.handleDragEnd(0, 0)
        local pid, dx, dy = HorizonResolveMouse()
        equipmentPressPanel = pid
        -- 玩家信息全窗模态：按下也走设计坐标，避免抬起位移判定串栏
        if pid == 'playerinfo' then
            pressStartDX, pressStartDY = dx or 0, dy or 0
            pressValid = true
            PlayerInfoPanel.handleDragBegin(dx, dy)
            return
        end
        -- [三栏并行] 三栏页自管输入（返回按钮等）
        if pid == 'tri' then
            pressStartDX, pressStartDY = dx or 0, dy or 0
            pressValid = true
            if SweepDialog.isOpen() then
                BattleTriPage.handleDragBegin(dx, dy)
                return
            end
            if EquipmentBag.shouldBattleOverlay() and EquipmentBag.hasOverlayRegion()
                and EquipmentBag.hitOverlayWindow(dx, dy) then
                local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
                local onDetail = false
                if EquipmentDetail.isOpen() then
                    local ddx, ddy = EquipmentBag.overlayToDetail(dx, dy)
                    onDetail = EquipmentDetail.containsPoint(ddx, ddy) == true
                end
                if not onDetail then
                    local bdx, bdy = EquipmentBag.overlayToDesign(dx, dy)
                    local peek = EquipmentBag.peekOverlayAt(bdx, bdy)
                    if peek then
                        EquipCrossDrag.arm(peek, dx, dy, "overlay")
                        print("[Horizon] 战斗背包按下 seq=" .. tostring(peek.seq))
                    end
                end
            end
            BattleTriPage.handleDragBegin(dx, dy)
            return
        end
        pressStartDX, pressStartDY = dx or 0, dy or 0
        pressValid = (pid ~= 'none')
        if pid == 'modal' and HorizonPageModalActive() then
            return
        end
        if pid == 'modal' and (BattleTriPage.isOpen() or TowerBattleScene.isActive()) then
            if OfflineRewardPanel.isOpen() then
                OfflineRewardPanel.handleDragBegin(dx, dy)
                return
            end
            if LevelUpPopup.isOpen() then
                return
            end
            if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
                RewardPopup.handleDragBegin(dx, dy)
                return
            end
        end
        if pid == 'modal' and RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
            RewardPopup.handleDragBegin(dx, dy)
            return
        end
        if pid == 'none' then return end
        -- 归属面板的奖励弹窗：其面板内按下先交给弹窗（拖拽滚动等）
        if RewardPopup.isOpen() and not RewardPopup.currentRowTag()
            and RewardPopup.currentPanel() == pid then
            RewardPopup.handleDragBegin(dx, dy)
            return
        end
        if pid == 'left' then
            if LootBoxPage.isOpen() then
                lootPress = true
                LootBox.handleDragBegin(dx, dy)
                return
            end
            if TaskPage.isOpen() then
                TaskPage.handleDragBegin(dx, dy)
                return
            end
            if BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then
                local mousePos = pointerPosition()
                local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
                local peek = BackpackPanel.peekEquipAt(dx, dy)
                if peek then
                    EquipCrossDrag.arm(peek, sx, sy, "backpack")
                    print("[Horizon] 左栏背包按下 seq=" .. tostring(peek.seq))
                end
                BackpackPanel.handleDragBegin(dx, dy)
                return
            end
            -- [锻炉双页 0929] 锻炉页已移中栏（center/tri 分支处理），左栏不再接管
            if TalentPage.isOpen() then TalentPage.handleDragBegin(dx, dy) return end
            if ChurchPage.isOpen() then ChurchPage.handleDragBegin(dx, dy) return end
            if TavernPage.isOpen() then TavernPage.handleDragBegin(dx, dy) return end
            if MarketPage.isOpen() then MarketPage.handleDragBegin(dx, dy) return end
        elseif pid == 'center' then
            -- [锻炉双页 0929] 锻炉页在中栏：优先接管
            if BlacksmithPage.isOpen() then BlacksmithPage.handleDragBegin(dx, dy) return end
            if BottomNav.getSelectedIndex() == 1 then CharacterPanel.handleDragBegin(dx, dy) end
        elseif pid == 'right' then
            -- [0930] 配装页装备（含角色六装备槽已装备）可跨栏拖到锻炉工作台/换槽
            local CharacterDetail = require("ui.character.detail.CharacterDetail")
            if CharacterDetail.isOpen() and CharacterDetail.isEquipTab and CharacterDetail.isEquipTab() then
                local mousePos = pointerPosition()
                local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
                local EquipPanel = require("ui.character.detail.CharacterDetailEquip")
                local peek = EquipPanel.peekSlotEquipAt(dx, dy) or EquipPanel.peekItemAt(dx, dy)
                if peek then
                    EquipCrossDrag.arm(peek, sx, sy, "rightpanel")
                    print("[Horizon] 右栏配装按下 seq=" .. tostring(peek.seq))
                end
            end
            CharacterPanel.handleDragBegin(dx, dy)
        end
    end

    function HandleMouseMoveHorizon(eventType, eventData)
        if UpdateNoticePopup.isOpen() then return end  -- 全窗模态：屏蔽下层 hover
        if DarkTitleScreen.isOpen() then return end
        if LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive() then return end
        if OfflineRewardPanel.isOpen() then
            if offlineTouchId ~= nil then return end
            cancelUnderlyingPress()
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            OfflineRewardOverlay.handleMove(sx, sy)
            return
        end
        local pid, dx, dy = HorizonResolveMouse()
        if lootPress then
            if pid == 'left' and pressValid then
                LootBox.handleDragMove(dx, dy)
            else
                LootBox.handleDragEnd(0, 0)
                pressValid = false
            end
            return
        end
        if EquipCrossDrag.isArmed() then
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            if EquipCrossDrag.move(sx, sy) then
                return
            end
            local source = EquipCrossDrag.getSource()
            if source == "overlay" then
                if pid ~= "tri" then return end
            elseif source == "rightpanel" then
                if pid ~= "right" then return end
            elseif pid ~= "left" then
                return
            end
        end
        if pid == 'none' then return end
        if pid == 'playerinfo' then
            PlayerInfoPanel.handleDragMove(dx, dy)
            return
        end
        -- 归属面板的奖励弹窗：其面板内拖拽交给弹窗滚动
        if RewardPopup.isOpen() and not RewardPopup.currentRowTag()
            and RewardPopup.currentPanel() == pid then
            RewardPopup.handleDragMove(dx, dy)
            return
        end
        -- 三行 / 通天塔离线收益是全窗 letterbox，拖拽必须在左栏/战斗区之前消费。
        if pid == 'modal' and (BattleTriPage.isOpen() or TowerBattleScene.isActive()) then
            if OfflineRewardPanel.isOpen() then
                OfflineRewardPanel.handleDragMove(dx, dy)
                return
            end
            if LevelUpPopup.isOpen() then
                return
            end
            if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
                RewardPopup.handleDragMove(dx, dy)
                return
            end
        end
        if pid == 'modal' and HorizonPageModalActive() then
            return
        end
        if pid == 'modal' then
            if DungeonBattleScene.isOpen() then DungeonBattleScene.handleDragMove(dx, dy) return end
            if LevelUpPopup.isOpen() then return end
            if PlayerInfoPanel.isOpen() then PlayerInfoPanel.handleDragMove(dx, dy) return end
            if OfflineRewardPanel.isOpen() then OfflineRewardPanel.handleDragMove(dx, dy) return end
            if RewardPopup.handleDragMove(dx, dy) then return end
            return
        end
        if equipOverlayPress then
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            local odx, ody, ED = equipOverlayDesign(sx, sy)
            if odx and ED then ED.handleDragMove(odx, ody) end
            return
        end
        if not pressValid then
            -- 鼠标进浮选详情后保持候选，不让来源仓库的离开事件立即关闭它。
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            if equipOverlayDesign(sx, sy) then return end
            if SweepDialog.isOpen() and pid == 'tri' then
                BattleTriPage.handleDragMove(dx, dy)
                return
            end
            if LootBoxPage.isOpen() then
                if pid == 'left' then LootBoxPage.handleHover(dx, dy)
                else LootBoxPage.handleHover(-1, -1) end
            end
            if pid == 'right'
                or (pid == 'center' and BottomNav.getSelectedIndex() == 1 and not BlacksmithPage.isOpen()) then
                if CharacterPanel.handleHover then CharacterPanel.handleHover(dx, dy) end
            else
                if CharacterPanel.handleHover then CharacterPanel.handleHover(-1, -1) end
            end
            if pid == 'left' then
                if MarketPage.isOpen and MarketPage.isOpen() and MarketPage.handleHover then
                    MarketPage.handleHover(dx, dy)
                elseif MarketPage.handleHover then
                    MarketPage.handleHover(-1, -1)
                end
                if BackpackPanel.isOpen and BackpackPanel.isOpen() and BackpackPanel.handleHover then
                    BackpackPanel.handleHover(dx, dy)
                elseif BackpackPanel.handleHover then
                    BackpackPanel.handleHover(-1, -1)
                end
                if EquipmentBag.isOpen and EquipmentBag.isOpen() and EquipmentBag.handleHover then
                    EquipmentBag.handleHover(dx, dy)
                elseif EquipmentBag.handleHover then
                    EquipmentBag.handleHover(-1, -1)
                end
            else
                if MarketPage.handleHover then MarketPage.handleHover(-1, -1) end
                if BackpackPanel.handleHover then BackpackPanel.handleHover(-1, -1) end
                if EquipmentBag.handleHover then EquipmentBag.handleHover(-1, -1) end
            end
            return
        end
        if pid == 'tri' then
            BattleTriPage.handleDragMove(dx, dy)
            return
        end
        if pid == 'left' then
            if LootBoxPage.isOpen() then return end -- 非遗匣起始的拖拽不能穿透其下方页面
            if TaskPage.isOpen() then TaskPage.handleDragMove(dx, dy) return end
            if BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then BackpackPanel.handleDragMove(dx, dy) return end
            if TalentPage.isOpen() then TalentPage.handleDragMove(dx, dy) return end
            if ChurchPage.isOpen() then ChurchPage.handleDragMove(dx, dy) return end
            if TavernPage.isOpen() then TavernPage.handleDragMove(dx, dy) return end
            if MarketPage.isOpen() then MarketPage.handleDragMove(dx, dy) return end
        elseif pid == 'center' then
            -- [锻炉双页 0929] 锻炉页在中栏：优先接管
            if BlacksmithPage.isOpen() then BlacksmithPage.handleDragMove(dx, dy) return end
            if BottomNav.getSelectedIndex() == 1 then CharacterPanel.handleDragMove(dx, dy) end
        elseif pid == 'right' then
            CharacterPanel.handleDragMove(dx, dy)
        end
    end

    -- 鼠标静止时也推进装备悬停计时（Standalone.HandleUpdate 每帧调用）。
    -- 移到其他格子由命中检测立即收起旧说明。
    function HandleEquipmentHoverTickHorizon()
        if OfflineRewardPanel.isOpen() or UpdateNoticePopup.isOpen() then return end
        if DarkTitleScreen.isOpen() or LetterIntro.isOpen() or IntroCutscene.isActive()
            or ScenarioDialogue.isActive() or pressValid or equipOverlayPress
            or EquipCrossDrag.isArmed() then return end
        local mp = pointerPosition()
        local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
        if equipOverlayDesign(sx, sy) then return end
        local pid, dx, dy = HorizonResolveMouse()
        if pid == 'right'
            or (pid == 'center' and BottomNav.getSelectedIndex() == 1 and not BlacksmithPage.isOpen()) then
            if CharacterPanel.handleHover then CharacterPanel.handleHover(dx, dy) end
        elseif CharacterPanel.handleHover then
            CharacterPanel.handleHover(-1, -1)
        end
        if pid == 'left' then
            if MarketPage.isOpen and MarketPage.isOpen() and MarketPage.handleHover then
                MarketPage.handleHover(dx, dy)
            end
            if BackpackPanel.isOpen and BackpackPanel.isOpen() and BackpackPanel.handleHover then
                BackpackPanel.handleHover(dx, dy)
            end
            if EquipmentBag.isOpen and EquipmentBag.isOpen() and EquipmentBag.handleHover then
                EquipmentBag.handleHover(dx, dy)
            end
        else
            if MarketPage.handleHover then MarketPage.handleHover(-1, -1) end
            if BackpackPanel.handleHover then BackpackPanel.handleHover(-1, -1) end
            if EquipmentBag.handleHover then EquipmentBag.handleHover(-1, -1) end
        end
    end

    function HandleMouseButtonUpHorizon(eventType, eventData)
        if tutorialPress then
            tutorialPress = false
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            local moved = math.abs(sx - tutorialStartX) + math.abs(sy - tutorialStartY)
            if eventData["Button"]:GetInt() == MOUSEB_LEFT and moved < TAP_THRESHOLD
                and tutorialInputActive() and TutorialManager.handleScreenClick(sx, sy, tutorialBlockedPress) then
                cancelUnderlyingPress()
                return
            end
            if tutorialBlockedPress then
                tutorialBlockedPress = false
                cancelUnderlyingPress()
                return
            end
        end
        if not OfflineRewardPanel.isOpen() and OfflineRewardOverlay.hasPress() then
            OfflineRewardOverlay.cancel()
            cancelUnderlyingPress()
            return
        end
        if OfflineRewardPanel.isOpen() and not offlineInputActive() then
            cancelUnderlyingPress()
            OfflineRewardOverlay.cancel()
        end
        if offlineInputActive() then
            if offlineTouchId ~= nil then return end
            cancelUnderlyingPress()
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            if vg() and CEPanel.handleUp(sx, sy, logicalH()) then
                OfflineRewardOverlay.cancel()
                return
            end
            OfflineRewardOverlay.handleUp(sx, sy, eventData["Button"]:GetInt())
            return
        end
        if equipOverlayPress then
            equipOverlayPress = false
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            local dx, dy, ED = equipOverlayDesign(sx, sy)
            local detail = ED or require("ui.character.equip.EquipmentDetail")
            detail.handleDragEnd()
            local moved = math.abs(sx - equipOverlayStartX) + math.abs(sy - equipOverlayStartY)
            if dx and ED and moved < TAP_THRESHOLD
                and eventData["Button"]:GetInt() == MOUSEB_LEFT then
                ED.handleInput(dx, dy)
                print("[Horizon] 详情浮层点击")
            end
            pressValid = false
            return
        end
        if vg() then
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            if CEPanel.handleUp(sx, sy, logicalH()) then
                return
            end
        end
        local button = eventData["Button"]:GetInt()
        local wasLootPress = lootPress
        if button == MOUSEB_LEFT then
            -- 不论鼠标在哪一栏、是否有新覆盖层，都释放遗匣的拖拽状态。
            LootBox.handleDragEnd(0, 0)
            lootPress = false
            if EquipCrossDrag.isArmed() then
                local mousePos = pointerPosition()
                local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
                local dragged = EquipCrossDrag.finish(sx, sy)
                if dragged then
                    if BackpackPanel.haltScroll then BackpackPanel.haltScroll() end
                    if EquipmentBag.haltScroll then EquipmentBag.haltScroll() end
                    pressValid = false
                    print("[Horizon] 左栏拖放穿戴结束")
                    return
                end
            end
            -- 角色拖拽由起始面板持有；松手即结算，不能按落点分栏遗留拖拽态。
            if CharacterPanel.isDraggingCard() then
                local pid, dx, dy = HorizonResolveMouse()
                if pid ~= 'right' and not (pid == 'center' and BottomNav.getSelectedIndex() == 1) then
                    dx, dy = -1, -1  -- 跨栏/弹窗外释放仅取消，不得命中其它栏的槽位
                end
                CharacterPanel.handleInput(dx, dy)
                CharacterPanel.handleDragEnd(dx, dy)
                pressValid = false
                return
            end
            -- 滚动/未达拖拽阈值的角色按压跨栏松开时也要清除起点状态。
            local pid, dx, dy = HorizonResolveMouse()
            if pid ~= 'right' and not (pid == 'center' and BottomNav.getSelectedIndex() == 1) then
                CharacterPanel.handleDragEnd(-1, -1)
            end
        end
        if not bootReady_() then return end
        -- [UpdateNoticePopup] 全窗模态：任意释放 = 关闭弹窗并消费事件（优先于标题/业务层）
        if UpdateNoticePopup.isOpen() then
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            -- 还原 letterbox 设计坐标（同 drawUpdateNotice 的逆变换），点击任意处均可关闭
            local fit = math.min(logicalW() / 1080, logicalH() / 2400)
            if fit <= 0 then fit = 1 end
            local dx = (sx - (logicalW() - 1080 * fit) * 0.5) / fit
            local dy = (sy - (logicalH() - 2400 * fit) * 0.5) / fit
            UpdateNoticePopup.handleInput(dx, dy)
            pressValid = false
            return
        end
        -- [DarkTitleScreen] 标题期任意释放 = 点击继续
        if DarkTitleScreen.isOpen() then
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            if DarkTitleScreen.handleLanguageTap(sx, sy) then
                return
            end
            if DarkTitleScreen.isReady() and not DarkTitleScreen.isFading()
                and BottomNav.getSelectedIndex() == 3
                and not BattleTriPage.isOpen()
                and not DungeonBattleScene.isOpen()
                and not TowerBattleScene.isActive() then
                BattleTriPage.open()
            end
            DarkTitleScreen.handleTap()
            return
        end
        if button ~= MOUSEB_LEFT then return end
        local mousePos = pointerPosition()
        local seamX, seamY = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
        local seamBtn = seamHitAt(seamX, seamY)
        if seamBtn and not OfflineRewardPanel.isOpen() then
            local now = time.elapsedTime
            if now - lastTapTime >= MIN_TAP_INTERVAL then
                lastTapTime = now
                local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
                if EquipmentDetail.isCompactCorner() then
                    EquipmentDetail.close()
                    print("[SeamBack] 返回同时关闭装备详情")
                end
                print("[SeamBack] close dir=" .. tostring(seamBtn.dir)
                    .. string.format(" at %.0f,%.0f", seamX, seamY))
                seamBtn.close()
            end
            pressValid = false
            return
        end
        local pid, dx, dy = HorizonResolveMouse()
        local isTap = false
        if wasLootPress and pid ~= 'left' then pressValid = false end
        if pressValid and (not equipmentPressPanel or equipmentPressPanel == pid) then
            local dist = math.abs(dx - pressStartDX) + math.abs(dy - pressStartDY)
            isTap = dist < TAP_THRESHOLD
        elseif equipmentPressPanel == 'right' then
            -- 跨栏结束右侧属性滚动；不能以两栏相同局部坐标伪装成点击。
            CharacterPanel.handleDragEnd(-1, -1)
        elseif equipmentPressPanel == 'left' and BackpackPanel.isOpen() then
            BackpackPanel.handleDragEnd(-1, -1)
        end
        equipmentPressPanel = nil
        -- 配装部位属于纯 UI 操作，详情外第一击也可立即选槽/取消；
        -- 判定放在真跨栏拖拽已结算之后，绝不把拖放当成点击。
        if isTap and not TutorialManager.isActive() and not RewardPopup.isOpen()
            and (pid == 'right' or (pid == 'center' and BottomNav.getSelectedIndex() == 1)) then
            local detail = require("ui.character.detail.CharacterDetail")
            if detail.handleEquipmentSlotTap then detail.handleEquipmentSlotTap(dx, dy) end
        end
        -- [浮选详情修复] 这次按下用于关闭浮选详情：拖拽已下放给页面，但松开不派发点击，
        -- 避免“点空白关详情”顺手触发页面按钮（领取/回收/筛选等）。
        if detailDismissPress then
            if isTap and not RewardPopup.isOpen() and not TutorialManager.isActive()
                and (pid == 'right' or (pid == 'center' and BottomNav.getSelectedIndex() == 1)) then
                CharacterDetail.handleNavigationTap(dx, dy)
            elseif isTap and not RewardPopup.isOpen()
                and (not TutorialManager.isActive() or TutorialManager.getCurrentHighlight() == "equip_item_gifted")
                and pid == 'left' and BackpackPanel.isOpen() and BackpackPanel.isLeftMode()
                and BackpackPanel.peekEquipAt(dx, dy) then
                -- 悬停关闭后的装备格仍走单击/双击时间窗，不重复派发其他按钮。
                BackpackPanel.handleDragEnd(dx, dy)
                BackpackPanel.handleInput(dx, dy)
            end
            detailDismissPress = false
            isTap = false
        elseif isTap and pid == 'left' and not RewardPopup.isOpen() and not TutorialManager.isActive()
            and not LootBoxPage.isOpen() and not TaskPage.isOpen()
            and BackpackPanel.isOpen() and BackpackPanel.isLeftMode() and BackpackPanel.peekEquipAt(dx, dy) then
            -- 装备格单击/双击自管时间窗，不受通用0.12秒按钮防抖吞掉第二击。
            BackpackPanel.handleDragEnd(dx, dy)
            BackpackPanel.handleInput(dx, dy)
            isTap = false
        end
        pressValid = false
        if isTap then
            local now = time.elapsedTime
            if now - lastTapTime < MIN_TAP_INTERVAL then isTap = false
            else lastTapTime = now end
        end
        -- 玩家信息全窗模态：坐标已是 1080×2400 设计空间
        if pid == 'playerinfo' then
            PlayerInfoPanel.handleDragEnd(dx, dy)
            if isTap then PlayerInfoPanel.handleInput(dx, dy) end
            return
        end
        -- 归属面板的奖励弹窗：点击其面板之外 → 关闭弹窗并消费事件
        if pid == 'rp_out' then
            if RewardPopup.isOpen() then RewardPopup.close() end
            return
        end
        -- 全局领奖 / 离线收益必须在中缝返回与左栏页面之前消费。
        if pid == 'modal' and (BattleTriPage.isOpen() or TowerBattleScene.isActive()) then
            if OfflineRewardPanel.isOpen() then
                OfflineRewardPanel.handleDragEnd(dx, dy)
                if isTap then OfflineRewardPanel.handleInput(dx, dy) end
                return
            end
            if LevelUpPopup.isOpen() then
                if isTap then LevelUpPopup.handleInput(dx, dy) end
                return
            end
            if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
                RewardPopup.handleDragEnd(dx, dy)
                if isTap then RewardPopup.handleInput(dx, dy) end
                return
            end
        end
        if pid == 'modal' and BattleTriPage.isOpen()
            and RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
            RewardPopup.handleDragEnd(dx, dy)
            if isTap then RewardPopup.handleInput(dx, dy) end
            return
        end
        -- [LetterIntro] 开场链输入：信件任意释放即翻段（不依赖 isTap，避免 pressValid 丢失）
        if LetterIntro.isOpen() then
            LetterIntro.handleTap()
            return
        end
        if IntroCutscene.isActive() then
            return
        end
        -- 剧情不依赖 isTap：横屏覆盖层里 pressValid 容易丢，丢了就点不下去
        if ScenarioDialogue.isActive() then
            local now = time.elapsedTime
            if now - lastTapTime >= MIN_TAP_INTERVAL then
                lastTapTime = now
                print("[ScenarioDialogue] advance from release step pending")
                ScenarioDialogue.advance()
            end
            return
        end
        if wasLootPress and pid ~= 'left' then return end
        if pid == 'none' then return end
        if pid == 'tri' then
            BattleTriPage.handleDragEnd(dx, dy)
            if isTap then BattleTriPage.handleInput(dx, dy) end
            return
        end
        if pid == 'modal' then
            -- [底栏移除] 副本页全窗模态点击（设计坐标）
            if HorizonPageModalActive() then
                if isTap then DungeonPage.handleInput(dx, dy) end
                return
            end
            if TowerBattleScene.isActive() then
                if isTap then TowerBattleScene.handleClick(dx, dy, logicalW(), logicalH()) end
                return
            end
            if DungeonBattleScene.isOpen() then
                DungeonBattleScene.handleDragEnd(dx, dy)
                if isTap then DungeonBattleScene.handleInput(dx, dy) end
                return
            end
            if LevelUpPopup.isOpen() then
                if isTap then LevelUpPopup.handleInput(dx, dy) end
                return
            end
            if PlayerInfoPanel.isOpen() then
                PlayerInfoPanel.handleDragEnd(dx, dy)
                if isTap then PlayerInfoPanel.handleInput(dx, dy) end
                return
            end
            if OfflineRewardPanel.isOpen() then
                OfflineRewardPanel.handleDragEnd(dx, dy)
                if isTap then OfflineRewardPanel.handleInput(dx, dy) end
                return
            end
            if RewardPopup.isOpen() then
                RewardPopup.handleDragEnd(dx, dy)
                if isTap then RewardPopup.handleInput(dx, dy) end
                return
            end
            return
        end
        -- 左面板：功能页组点击链
        if pid == 'left' then
            -- 归属左栏的奖励弹窗：左栏内任意点击交给弹窗（可交互/关闭）
            if RewardPopup.isOpen() and not RewardPopup.currentRowTag()
                and RewardPopup.currentPanel() == 'left' then
                RewardPopup.handleDragEnd(dx, dy)
                if isTap then RewardPopup.handleInput(dx, dy) end
                return
            end
            -- [三行并行] 头像热区（TopBar 绘制在左面板时 oy=-30，热区同步）：仅城镇主视图（无二级页）时
            if isTap and not (BackpackPanel.isOpen() or BlacksmithPage.isOpen() or ChurchPage.isOpen()
                or TalentPage.isOpen() or TavernPage.isOpen() or MarketPage.isOpen() or LootBoxPage.isOpen() or TaskPage.isOpen()) then
                if TopBar.hitTestAvatar(dx, dy, -30) then
                    PlayerInfoPanel.open()
                    return
                end
                -- [底栏移除] 页面入口在 TopBar（812ddc7）：左栏链补接其输入
                if TopBar.handleInput(dx, dy, -30) then
                    return
                end
            end
            if LootBoxPage.isOpen() then
                LootBox.handleDragEnd(dx, dy)
                if isTap and wasLootPress then LootBox.handleInput(dx, dy) end
                return
            end
            if TaskPage.isOpen() then
                TaskPage.handleDragEnd(dx, dy)
                if isTap then TaskPage.handleInput(dx, dy) end
                return
            end
            -- [仓库入口] 背包左栏页（与黑市/教堂同链）
            if BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then
                BackpackPanel.handleDragEnd(dx, dy)
                if not isTap then return end
                BackpackPanel.handleInput(dx, dy)
                return
            end
            -- [锻炉双页 0929] 锻炉页已移中栏（center 分支处理），左栏链不再接管
            if TalentPage.isOpen() then
                TalentPage.handleDragEnd(dx, dy)
                if not isTap then return end
                TalentPage.handleInput(dx, dy)
                return
            end
            if ChurchPage.isOpen() then
                ChurchPage.handleDragEnd(dx, dy)
                if not isTap then return end
                ChurchPage.handleInput(dx, dy)
                return
            end
            if TavernPage.isOpen() then
                TavernPage.handleDragEnd(dx, dy)
                if not isTap then return end
                TavernPage.handleInput(dx, dy)
                return
            end
            if MarketPage.isOpen() then
                MarketPage.handleDragEnd(dx, dy)
                if not isTap then return end
                MarketPage.handleInput(dx, dy)
                return
            end
            if isTap then TownScene.handleInput(dx, dy) end
            return
        end
        -- 右面板：角色链
        if pid == 'right' then
            -- 归属右栏的奖励弹窗：右栏内任意点击交给弹窗（可交互/关闭）
            if RewardPopup.isOpen() and not RewardPopup.currentRowTag()
                and RewardPopup.currentPanel() == 'right' then
                RewardPopup.handleDragEnd(dx, dy)
                if isTap then RewardPopup.handleInput(dx, dy) end
                return
            end
            if CharacterPanel.isDraggingCard() then
                CharacterPanel.handleInput(dx, dy)
                CharacterPanel.handleDragEnd(dx, dy)
                return
            end
            CharacterPanel.handleDragEnd(dx, dy)
            if isTap then CharacterPanel.handleInput(dx, dy) end
            return
        end
        -- 中面板：主视图链
        if pid == 'center' and RewardPopup.isOpen() and not RewardPopup.currentRowTag()
            and RewardPopup.currentPanel() == 'center' then
            RewardPopup.handleDragEnd(dx, dy)
            if isTap then RewardPopup.handleInput(dx, dy) end
            return
        end
        -- [锻炉双页 0929] 锻炉页在中栏：优先接管（tri 模式下中段命中映射到 center 设计坐标）
        if pid == 'center' and BlacksmithPage.isOpen() then
            BlacksmithPage.handleDragEnd(dx, dy)
            if isTap then BlacksmithPage.handleInput(dx, dy) end
            return
        end
        if DungeonBattleScene.isOpen() or TowerBattleScene.isActive() then return end
        local tabIndex = BottomNav.getSelectedIndex()
        -- [底栏移除] 非三行旧布局：中栏顶部 TopBar 页签入口（三行布局画左栏、走左栏链）
        if isTap and not BattleTriPage.isOpen()
            and not CharacterPanel.isDetailOpen()
            and TopBar.handleInput(dx, dy, 0) then
            return
        end
        if tabIndex == 1 then
            if CharacterPanel.isDraggingCard() then
                CharacterPanel.handleInput(dx, dy)
                CharacterPanel.handleDragEnd(dx, dy)
                return
            end
            CharacterPanel.handleDragEnd(dx, dy)
            if isTap and CharacterPanel.handleInput(dx, dy) then return end
        elseif tabIndex == 3 then
            if isTap and BattleScene.handleInput(dx, dy) then return end
        end
        -- [底栏移除] tab2/5 走全窗模态链（resolve 'modal'），此处不再以中栏坐标误投
        if not isTap then return end
        -- 横屏模式无调试面板（DebugPanel 仅竖屏 screen-space）
        local detailOpen = CharacterPanel.isDetailOpen()
        if not detailOpen then
            if TopBar.hitTestAvatar(dx, dy, 0) then
                PlayerInfoPanel.open()
                return
            end
        end
        -- [底栏移除] BottomNav 已收为纯状态模块，无命中逻辑
    end

    local function offlineTouchPosition(eventData)
        local x = eventData["X"]:GetInt() / dpr()
        local y = eventData["Y"]:GetInt() / dpr()
        return toDesign(x, y)
    end

    local function handleTopTouch(eventData, released)
        if not OfflineRewardPanel.isOpen() or offlineInputActive() then return false end
        cancelUnderlyingPress()
        OfflineRewardOverlay.cancel()
        if not released then return true end
        local sx, sy = offlineTouchPosition(eventData)
        if UpdateNoticePopup.isOpen() then
            local dx, dy = OfflineRewardOverlay.toDesign(sx, sy)
            UpdateNoticePopup.handleInput(dx, dy)
        elseif DarkTitleScreen.isOpen() then
            if not DarkTitleScreen.handleLanguageTap(sx, sy) then DarkTitleScreen.handleTap() end
        elseif LetterIntro.isOpen() then
            LetterIntro.handleTap()
        elseif ScenarioDialogue.isActive() then
            ScenarioDialogue.advance()
        end
        return true
    end

    local activeTouchId = nil ---@type integer|nil
    local function dispatchTouch(eventType, eventData, handler)
        touchPosition = { x = eventData["X"]:GetInt(), y = eventData["Y"]:GetInt() }
        local proxy = { Button = { GetInt = function() return MOUSEB_LEFT end } }
        local ok, err = pcall(handler, eventType, proxy)
        touchPosition = nil
        if not ok then error(err) end
    end

    function HandleTouchBeginHorizon(eventType, eventData)
        if handleTopTouch(eventData, false) then return end
        if OfflineRewardPanel.isOpen() then
            if offlineTouchId == nil then
                offlineTouchId = eventData["TouchID"]:GetInt()
                cancelUnderlyingPress()
                local sx, sy = offlineTouchPosition(eventData)
                OfflineRewardOverlay.handleDown(sx, sy, MOUSEB_LEFT)
            end
            return
        end
        if activeTouchId ~= nil then return end
        activeTouchId = eventData["TouchID"]:GetInt()
        dispatchTouch(eventType, eventData, HandleMouseButtonDownHorizon)
    end

    function HandleTouchEndHorizon(eventType, eventData)
        if handleTopTouch(eventData, true) then
            if eventData["TouchID"]:GetInt() == offlineTouchId then offlineTouchId = nil end
            return
        end
        if OfflineRewardPanel.isOpen() or offlineTouchId ~= nil then
            if eventData["TouchID"]:GetInt() == offlineTouchId then
                if offlineInputActive() then
                    local sx, sy = offlineTouchPosition(eventData)
                    OfflineRewardOverlay.handleUp(sx, sy, MOUSEB_LEFT)
                else
                    OfflineRewardOverlay.cancel()
                end
                offlineTouchId = nil
            end
            return
        end
        if eventData["TouchID"]:GetInt() ~= activeTouchId then return end
        activeTouchId = nil
        dispatchTouch(eventType, eventData, HandleMouseButtonUpHorizon)
    end

    function HandleTouchMoveHorizon(eventType, eventData)
        if OfflineRewardPanel.isOpen() or offlineTouchId ~= nil then
            if eventData["TouchID"]:GetInt() == offlineTouchId and offlineInputActive() then
                local sx, sy = offlineTouchPosition(eventData)
                OfflineRewardOverlay.handleMove(sx, sy)
            end
            return
        end
        if eventData["TouchID"]:GetInt() ~= activeTouchId then return end
        dispatchTouch(eventType, eventData, HandleMouseMoveHorizon)
    end

    function HandleMouseWheelHorizon(eventType, eventData)
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
        if LevelUpPopup.isOpen() and (BattleTriPage.isOpen() or TowerBattleScene.isActive()) then
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
        if BattleTriPage.isOpen() and StageSelectDialog.isOpen() then
            BattleTriPage.handleScroll(wheel, sx, sy)
            return
        end
        -- 装备袋只吃覆盖矩形内的滚轮，左右栏仍滚自己的列表
        if BattleTriPage.handleScroll(wheel, sx, sy) then return end

        -- 全屏战斗场景
        if DungeonBattleScene.isOpen() then DungeonBattleScene.handleScroll(wheel) return end
        -- 全屏弹窗
        if LevelUpPopup.isOpen() then return end
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

return Input
