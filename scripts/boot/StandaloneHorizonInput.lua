-- 横屏指针与触摸路由；绘制、帧坐标和离线覆盖实例由宿主提供。
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
local TerminalConfirmDialog = require("ui.battle.popup.TerminalConfirmDialog")
local IntroCutscene      = require("ui.story.gate.IntroCutscene")
local LetterIntro        = require("ui.story.gate.LetterIntro")
local CharacterDetail    = require("ui.character.detail.CharacterDetail")
local AwakeningArtwork  = require("ui.character.hero.AwakeningArtwork")
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
    local seamGesture = ctx.seamGesture
    local seamInputBlocked = ctx.seamInputBlocked
    local RT, Viewport, OfflineRewardOverlay = ctx.RT, ctx.Viewport, ctx.OfflineRewardOverlay
    local artifactModule = require("boot.ArtifactGesture")
    local artifactGesture = ctx.artifactGesture or artifactModule.bind(ctx) or artifactModule

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
    ctx.pointerSource = function() return touchPosition and touchPosition.id or "mouse" end
    ctx.getLastTap = function() return lastTapTime end
    ctx.setLastTap = function(t) lastTapTime = t end
    -- 遗匣按压由左栏捕获；移出左栏后不再把同次拖拽转交右栏/战斗。
    local lootPress = false

    -- 滚轮与其它指针输入共用原坐标闭包；宿主状态仍在调用时读取。
    local horizonWheel = require("boot.StandaloneHorizonWheel").bind({
        logicalW = logicalW, logicalH = logicalH, dpr = dpr, toDesign = toDesign,
        pointerPosition = pointerPosition, Viewport = Viewport, OfflineRewardOverlay = OfflineRewardOverlay,
        talentPageUsesWideLayout = talentPageUsesWideLayout,
        syncTalentPageLayout = syncTalentPageLayout, talentPageRightEdge = talentPageRightEdge,
        BottomNav = BottomNav, CharacterPanel = CharacterPanel, CEPanel = CEPanel,
        HeroRosterPanel = HeroRosterPanel, RewardPopup = RewardPopup,
        BlacksmithPage = BlacksmithPage, ChurchPage = ChurchPage,
        TalentPage = TalentPage, TavernPage = TavernPage, MarketPage = MarketPage,
        DungeonBattleScene = DungeonBattleScene, TowerBattleScene = TowerBattleScene,
        DungeonPage = DungeonPage, BackpackPanel = BackpackPanel,
        LootBox = LootBox, LootBoxPage = LootBoxPage, TaskPage = TaskPage,
        LevelUpPopup = LevelUpPopup, OfflineRewardPanel = OfflineRewardPanel,
        UpdateNoticePopup = UpdateNoticePopup, PlayerInfoPanel = PlayerInfoPanel,
        StartScreen = StartScreen, DarkTitleScreen = DarkTitleScreen,
        BattleTriPage = BattleTriPage, SweepDialog = SweepDialog,
        DamageStatsPanel = DamageStatsPanel, StageSelectDialog = StageSelectDialog,
        TerminalConfirmDialog = TerminalConfirmDialog,
        IntroCutscene = IntroCutscene, LetterIntro = LetterIntro, ScenarioDialogue = ScenarioDialogue,
    })
    local HorizonPageModalActive = horizonWheel.HorizonPageModalActive
    local playerInfoDesignCoords = horizonWheel.playerInfoDesignCoords
    local rewardPopupDesignCoords = horizonWheel.rewardPopupDesignCoords
    local HorizonResolveMouse = horizonWheel.HorizonResolveMouse

    local equipOverlayPress = false
    local equipOverlayStartX, equipOverlayStartY = 0, 0
    -- 关浮选详情后按下可继续拖拽，但同次松开不派发按钮点击。
    local detailDismissPress = false
    local equipmentPressPanel = nil
    local marqueeGesture = require("boot.DecomposeMarqueeGesture").bind({
        panel = BackpackPanel, RT = RT, width = logicalW, height = logicalH, dpr = dpr,
        DS = Viewport.DS, tri = BattleTriPage.isOpen, source = ctx.pointerSource,
        blocked = function()
            return RewardPopup.isOpen() or OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen()
                or PlayerInfoPanel.isOpen() or UpdateNoticePopup.isOpen() or DarkTitleScreen.isOpen()
                or LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive()
                or CEPanel.isOpen() or TutorialManager.isActive() or StartScreen.isOpen()
                or SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen()
                or TerminalConfirmDialog.isOpen() or HorizonPageModalActive()
                or DungeonBattleScene.isOpen() or TowerBattleScene.isActive()
                or TaskPage.isOpen() or LootBoxPage.isOpen() or TalentPage.isOpen()
                or ChurchPage.isOpen() or TavernPage.isOpen() or MarketPage.isOpen()
                or EquipCrossDrag.isArmed() or pressValid or equipOverlayPress
        end,
    })
    if not seamGesture then
        seamGesture = require("boot.SeamBackGesture").bind({
            RT = RT, width = logicalW, height = logicalH, dpr = dpr, hit = seamHitAt,
            threshold = TAP_THRESHOLD, bootReady = bootReady_, pageModal = HorizonPageModalActive,
            tapInterval = MIN_TAP_INTERVAL, getLastTap = function() return lastTapTime end,
            setLastTap = function(t) lastTapTime = t end, source = ctx.pointerSource,
        })
    end
    ---@type integer|nil
    local offlineTouchId = nil

    -- 塔独占按压身份；阶段/模态/坐标变化永久取消旧按压，往返拖动不伪点击。
    local towerPress = nil ---@type table?
    local function towerKey()
        return TowerBattleScene.getPresentationKey() .. ":" .. tostring(TaskPage.isOpen())
            .. ":" .. tostring(RewardPopup.isOpen()) .. ":" .. tostring(PlayerInfoPanel.isOpen())
            .. ":" .. tostring(OfflineRewardPanel.isOpen()) .. ":" .. tostring(LevelUpPopup.isOpen())
            .. ":" .. tostring(UpdateNoticePopup.isOpen()) .. ":" .. tostring(DarkTitleScreen.isOpen())
            .. ":" .. tostring(LetterIntro.isOpen()) .. ":" .. tostring(IntroCutscene.isActive())
            .. ":" .. tostring(ScenarioDialogue.isActive()) .. ":" .. tostring(CEPanel.isOpen())
            .. ":" .. tostring(TerminalConfirmDialog.isOpen())
    end
    local function validateTowerPress()
        local p = towerPress
        if not p then return false end
        if not TowerBattleScene.isActive() or p.key ~= towerKey()
            or p.w ~= logicalW() or p.h ~= logicalH() or p.scale ~= (RT.frameScale or 1)
            or p.ox ~= (RT.frameOx or 0) or p.oy ~= (RT.frameOy or 0) or p.dpr ~= dpr() then
            p.cancelled = true
            TowerBattleScene.handleDragEnd()
            if p.task then TaskPage.handleDragEnd(-1, -1) end
        end
        return not p.cancelled
    end
    -- Update与绘制都调用：观测到瞬变后不因身份/尺寸恢复而复活旧Down。
    ctx.observeTowerPress = function()
        validateTowerPress()
        marqueeGesture.observe()
    end
    local function towerInputActive()
        return TowerBattleScene.isActive() and not RewardPopup.isOpen() and not PlayerInfoPanel.isOpen()
            and not OfflineRewardPanel.isOpen() and not LevelUpPopup.isOpen()
            and not UpdateNoticePopup.isOpen() and not DarkTitleScreen.isOpen()
            and not LetterIntro.isOpen() and not IntroCutscene.isActive()
            and not ScenarioDialogue.isActive() and not CEPanel.isOpen()
            and not TerminalConfirmDialog.isOpen()
    end
    local function towerMove(x, y)
        local p = towerPress
        if not p then return end
        if p.source ~= ctx.pointerSource() then return end
        if not validateTowerPress() then return end
        if math.abs(x - p.x) + math.abs(y - p.y) >= TAP_THRESHOLD then p.moved = true end
        local layout = TowerBattleScene.getLayout(logicalW(), logicalH())
        if require("ui.tower.TowerLayout").panelAt(layout, x, y) ~= p.panel then
            p.cancelled = true
            TowerBattleScene.handleDragEnd()
            if p.task then TaskPage.handleDragEnd(-1, -1) end
            return
        end
        if p.task then
            local dx, dy = require("ui.tower.TowerLayout").toTask(layout, x, y)
            TaskPage.handleDragMove(dx, dy)
        else
            TowerBattleScene.handleDragMove(x, y, logicalW(), logicalH())
        end
    end

    --- 离线弹窗接管时仅释放下层按压，不派发点击或装备落点。
    local function cancelUnderlyingPress()
        marqueeGesture.cancel()
        if towerPress then
            towerPress.cancelled = true
            TowerBattleScene.handleDragEnd()
        end
        seamGesture.cancel()
        artifactGesture.cancel()
        if EquipCrossDrag.isArmed() then EquipCrossDrag.cancel() end
        if equipOverlayPress then
            require("ui.character.equip.EquipmentDetail").handleDragEnd()
        end
        if lootPress then LootBox.handleDragEnd(-1, -1) end
        if equipmentPressPanel == 'left' then
            if LootBoxPage.isOpen() then LootBox.handleDragEnd(-1, -1)
            elseif TaskPage.isOpen() then TaskPage.handleDragEnd(-1, -1)
            elseif BackpackPanel.isOpen() then BackpackPanel.handleDragEnd(-1, -1)
            elseif TalentPage.isOpen() then TalentPage.handleDragEnd(-1, -1)
            elseif ChurchPage.isOpen() then ChurchPage.handleDragEnd(-1, -1)
            elseif TavernPage.isOpen() then TavernPage.handleDragEnd(-1, -1)
            elseif MarketPage.isOpen() then MarketPage.handleDragEnd(-1, -1) end
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

    local rewardGesture = require("boot.RewardGesture").bindHost(ctx, RewardPopup, cancelUnderlyingPress, pointerPosition)
    local terminalInput = nil ---@type table|nil
    local function terminalDown(sx, sy, button)
        terminalInput = require("boot.TerminalInput").bind({ RT = RT, logicalW = logicalW,
            logicalH = logicalH, dpr = dpr, playerInfoDesignCoords = playerInfoDesignCoords,
            cancelUnderlyingPress = cancelUnderlyingPress })
        terminalInput.down(sx, sy, button)
    end

    local function offlineInputActive()
        return OfflineRewardPanel.isOpen() and not UpdateNoticePopup.isOpen()
            and not DarkTitleScreen.isOpen() and not LetterIntro.isOpen()
            and not IntroCutscene.isActive() and not ScenarioDialogue.isActive()
    end

    local function levelUpInputActive()
        return LevelUpPopup.isOpen() and not LevelUpPopup.isPresentationBlocked()
            and not OfflineRewardPanel.isOpen()
            and not UpdateNoticePopup.isOpen() and not DarkTitleScreen.isOpen()
            and not LetterIntro.isOpen() and not IntroCutscene.isActive()
            and not ScenarioDialogue.isActive()
    end

    -- 升级独占整次手势；出现时只取消下层按压，不把旧拖拽 Up 派成新按钮点击。
    -- Popup 自管进入/退出动画的 consume；这里不判断动画阶段、不复刻它的按钮布局。
    local levelPress, levelMoved = false, false
    local levelStartX, levelStartY = 0, 0
    local levelWidth, levelHeight, levelScale, levelOx, levelOy, levelDpr = 0, 0, 1, 0, 0, 1
    local levelPresentationVersion = nil ---@type number|nil
    ---@type integer|nil
    local levelTouchId = nil
    -- 同一模态下开始的副指也要吃掉其结束；主指关闭弹窗后不能把副指 Up 下放。
    local levelTouches = {} ---@type table<number, boolean>

    local function levelDown(sx, sy, button)
        if not levelUpInputActive() then return false end
        cancelUnderlyingPress()
        if button == MOUSEB_LEFT then
            levelPress, levelMoved = true, false
            levelStartX, levelStartY = sx, sy
            levelWidth, levelHeight = logicalW(), logicalH()
            levelPresentationVersion = LevelUpPopup.getPresentationVersion()
            levelScale, levelOx, levelOy, levelDpr = RT.frameScale or 1,
                RT.frameOx or 0, RT.frameOy or 0, dpr()
        end
        return true
    end

    local function levelMove(sx, sy)
        if not levelUpInputActive() and not levelPress then return false end
        cancelUnderlyingPress()
        if levelPress and math.abs(sx - levelStartX) + math.abs(sy - levelStartY) >= TAP_THRESHOLD then
            levelMoved = true
        end
        return true
    end

    local function levelUp(sx, sy, button)
        if not levelUpInputActive() and not levelPress then return false end
        cancelUnderlyingPress()
        if button == MOUSEB_LEFT then
            local isTap = levelUpInputActive() and levelPress and not levelMoved
                and LevelUpPopup.getPresentationVersion() == levelPresentationVersion
                and logicalW() == levelWidth and logicalH() == levelHeight
                and (RT.frameScale or 1) == levelScale and (RT.frameOx or 0) == levelOx
                and (RT.frameOy or 0) == levelOy and dpr() == levelDpr
                and math.abs(sx - levelStartX) + math.abs(sy - levelStartY) < TAP_THRESHOLD
            levelPress, levelMoved = false, false
            if isTap then LevelUpPopup.handleInput(sx, sy, logicalW(), logicalH()) end
        end
        return true
    end

    local function tutorialInputActive()
        return TutorialManager.isActive() and TutorialManager.isInputActive() and not RewardPopup.isLarge()
            and not LevelUpPopup.isOpen() and not OfflineRewardPanel.isOpen() and not UpdateNoticePopup.isOpen()
            and not DarkTitleScreen.isOpen() and not LetterIntro.isOpen()
            and not IntroCutscene.isActive() and not ScenarioDialogue.isActive()
            and not DungeonBattleScene.isOpen() and not TowerBattleScene.isActive()
    end
    local tutorialPress = false
    local tutorialBlockedPress = false
    local tutorialStartX, tutorialStartY = 0, 0
    local tutorialEntryPress = nil ---@type any

    local function artworkBlocked()
        return StartScreen.isOpen() or DarkTitleScreen.isOpen() or LetterIntro.isOpen()
            or IntroCutscene.isActive() or ScenarioDialogue.isActive() or RewardPopup.isOpen()
            or PlayerInfoPanel.isOpen() or LevelUpPopup.isOpen() or OfflineRewardPanel.isOpen()
            or UpdateNoticePopup.isOpen() or CEPanel.isOpen() or TutorialManager.isActive()
            or StageSelectDialog.isOpen() or SweepDialog.isOpen() or DamageStatsPanel.isOpen()
            or TerminalConfirmDialog.isOpen() or DungeonBattleScene.isOpen() or TowerBattleScene.isActive()
    end

    -- 全图持有整次指针手势，失效后的松手也不能落到原页面或后来出现的弹窗。
    local artworkPointer = AwakeningArtwork.bindInput({ runtime = RT, blocked = artworkBlocked,
        cancelUnderlyingPress = cancelUnderlyingPress, source = ctx.pointerSource,
        position = function()
            local mp = pointerPosition()
            return toDesign(mp.x / dpr(), mp.y / dpr())
        end })

    function HandleMouseButtonDownHorizon(eventType, eventData)
        local button = eventData["Button"]:GetInt()
        if artworkPointer("down", button) then return end
        if marqueeGesture.hasPress() then
            if button ~= MOUSEB_RIGHT then marqueeGesture.cancel() end
            return
        end
        validateTowerPress()
        if towerPress and (button ~= MOUSEB_LEFT or towerPress.source ~= ctx.pointerSource()) then return end
        if towerPress then
            TowerBattleScene.handleDragEnd()
            if towerPress.task then TaskPage.handleDragEnd(-1, -1) end
            towerPress = nil
        end
        -- 入口主键按压期间忽略副鼠标键，不能清掉其英雄身份后偷换落点。
        if tutorialEntryPress and button ~= MOUSEB_LEFT then return end
        if seamGesture.hasPress() then seamGesture.reset() end
        if tutorialEntryPress then TutorialManager.cancelDetailEntryPress() end
        tutorialEntryPress = nil
        tutorialPress, tutorialBlockedPress = false, false
        if OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen() then cancelUnderlyingPress() end
        equipmentPressPanel = nil
        detailDismissPress = false  -- [浮选详情修复] 每次按下先复位，防早退路径残留误抑制下次 tap
        if vg() then
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            if CEPanel.handleDown(sx, sy, logicalH()) then
                artifactGesture.cancel()
                levelPress, levelMoved = false, false
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
        if button == MOUSEB_LEFT and seamGesture then
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            if seamHitAt(sx, sy) and (not seamInputBlocked or not seamInputBlocked())
                and not equipOverlayDesign(sx, sy) then
                cancelUnderlyingPress()
                seamGesture.down(sx, sy, false)
                return
            end
        end
        if tutorialInputActive() then
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            if button == MOUSEB_LEFT then
                tutorialPress = true
                tutorialStartX, tutorialStartY = sx, sy
                if not TutorialManager.canPointerStart(sx, sy, button) then
                    tutorialBlockedPress = true
                    cancelUnderlyingPress()
                    return
                end
                tutorialEntryPress = TutorialManager.beginDetailEntryPress()
                if tutorialEntryPress then
                    tutorialEntryPress.width, tutorialEntryPress.height = logicalW(), logicalH()
                    tutorialEntryPress.scale, tutorialEntryPress.ox, tutorialEntryPress.oy,
                        tutorialEntryPress.dpr = RT.frameScale or 1, RT.frameOx or 0, RT.frameOy or 0, dpr()
                    -- 入口仅是点击，不启动头像编队拖拽；松手仍走原点击业务。
                    local pid, dx, dy = HorizonResolveMouse()
                    equipmentPressPanel = pid
                    pressStartDX, pressStartDY = dx or 0, dy or 0
                    pressValid = pid ~= 'none'
                    return
                end
            elseif not TutorialManager.canPointerStart(sx, sy, button) then
                return
            end
        end
        if OfflineRewardPanel.isOpen() then
            levelPress, levelMoved = false, false
            if offlineTouchId ~= nil then return end
            cancelUnderlyingPress()
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            OfflineRewardOverlay.handleDown(sx, sy, button)
            return
        end
        if levelUpInputActive() or levelPress then
            if levelTouchId ~= nil then return end
            local mousePos = input:GetMousePosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            levelDown(sx, sy, button)
            return
        end
        if rewardGesture.pointer("begin", button) then return end
        if TerminalConfirmDialog.isOpen() then
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            terminalDown(sx, sy, button)
            return
        end
        if TowerBattleScene.isActive() and towerInputActive() then
            cancelUnderlyingPress()
            if button ~= MOUSEB_LEFT then return end
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            local layout = TowerBattleScene.getLayout(logicalW(), logicalH())
            local panel = require("ui.tower.TowerLayout").panelAt(layout, sx, sy)
            towerPress = { key = towerKey(), w = logicalW(), h = logicalH(),
                scale = RT.frameScale or 1, ox = RT.frameOx or 0, oy = RT.frameOy or 0,
                dpr = dpr(), source = ctx.pointerSource(), x = sx, y = sy, panel = panel,
                task = TaskPage.isOpen() and panel == "left", moved = false, cancelled = panel == nil }
            pressValid = false
            equipmentPressPanel = nil
            if towerPress.task then
                local dx, dy = require("ui.tower.TowerLayout").toTask(layout, sx, sy)
                TaskPage.handleDragBegin(dx, dy)
            elseif not TaskPage.isOpen() then
                TowerBattleScene.handleDragBegin(sx, sy, logicalW(), logicalH())
            end
            return
        end
        if button == MOUSEB_LEFT and (DungeonBattleScene.isOpen() or HorizonPageModalActive()) then
            equipOverlayPress = false
        end
        if button == MOUSEB_LEFT and not (DungeonBattleScene.isOpen() or HorizonPageModalActive()) then
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
                    local mp = pointerPosition()
                    local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
                    if marqueeGesture.begin(dx, dy, sx, sy) then return end
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
        local artifactPos = pointerPosition()
        local artifactX, artifactY = toDesign(artifactPos.x / dpr(), artifactPos.y / dpr())
        if not seamHitAt(artifactX, artifactY) and artifactGesture.down(pid, artifactX, artifactY) then
            pressValid = false
            return
        end
        equipmentPressPanel = pid
        if pid == 'playerinfo' then
            pressStartDX, pressStartDY = dx or 0, dy or 0
            pressValid = true
            PlayerInfoPanel.handleDragBegin(dx, dy)
            return
        end
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
            -- 锻炉页已移中栏（center/tri 分支处理），左栏不再接管
            if TalentPage.isOpen() then TalentPage.handleDragBegin(dx, dy) return end
            if ChurchPage.isOpen() then ChurchPage.handleDragBegin(dx, dy) return end
            if TavernPage.isOpen() then TavernPage.handleDragBegin(dx, dy) return end
            if MarketPage.isOpen() then MarketPage.handleDragBegin(dx, dy) return end
        elseif pid == 'center' then
            -- 锻炉页在中栏：优先接管
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
        if artworkPointer("move", MOUSEB_LEFT) then return end
        if marqueeGesture.hasPress() then
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            marqueeGesture.move(sx, sy)
            return
        end
        if towerPress then
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            towerMove(sx, sy)
            return
        end
        if tutorialEntryPress then
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            if math.abs(sx - tutorialStartX) + math.abs(sy - tutorialStartY) >= TAP_THRESHOLD
                or not TutorialManager.isDetailEntryPressValid(tutorialEntryPress)
                or tutorialEntryPress.width ~= logicalW() or tutorialEntryPress.height ~= logicalH()
                or tutorialEntryPress.scale ~= (RT.frameScale or 1) or tutorialEntryPress.ox ~= (RT.frameOx or 0)
                or tutorialEntryPress.oy ~= (RT.frameOy or 0) or tutorialEntryPress.dpr ~= dpr() then
                TutorialManager.cancelDetailEntryPress()
                tutorialEntryPress.invalid = true
            end
            return
        end
        if seamGesture.hasPress() then
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            seamGesture.move(sx, sy, seamInputBlocked and seamInputBlocked())
            return
        end
        if UpdateNoticePopup.isOpen() then return end  -- 全窗模态：屏蔽下层 hover
        if DarkTitleScreen.isOpen() then return end
        if LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive() then return end
        if OfflineRewardPanel.isOpen() then
            levelPress, levelMoved = false, false
            if offlineTouchId ~= nil then return end
            cancelUnderlyingPress()
            local mousePos = pointerPosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            OfflineRewardOverlay.handleMove(sx, sy)
            return
        end
        if levelUpInputActive() or levelPress then
            if levelTouchId ~= nil then return end
            local mousePos = input:GetMousePosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            levelMove(sx, sy)
            return
        end
        if rewardGesture.pointer("move", MOUSEB_LEFT) then return end
        local artifactPos = pointerPosition()
        local artifactX, artifactY = toDesign(artifactPos.x / dpr(), artifactPos.y / dpr())
        if TerminalConfirmDialog.isOpen() or terminalInput then
            if not terminalInput or terminalInput.move(artifactX, artifactY) then return end
        end
        if artifactGesture.move(artifactX, artifactY) then return end
        local pid, dx, dy = HorizonResolveMouse()
        if not pressValid then artifactGesture.hover(pid, artifactX, artifactY) end
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
        if pid == 'modal' and HorizonPageModalActive() then
            return
        end
        if pid == 'modal' then
            if DungeonBattleScene.isOpen() then DungeonBattleScene.handleDragMove(dx, dy) return end
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
            -- 锻炉页在中栏：优先接管
            if BlacksmithPage.isOpen() then BlacksmithPage.handleDragMove(dx, dy) return end
            if BottomNav.getSelectedIndex() == 1 then CharacterPanel.handleDragMove(dx, dy) end
        elseif pid == 'right' then
            CharacterPanel.handleDragMove(dx, dy)
        end
    end

    -- 鼠标静止时也推进装备悬停计时（Standalone.HandleUpdate 每帧调用）。
    -- 移到其他格子由命中检测立即收起旧说明。
    function HandleEquipmentHoverTickHorizon()
        AwakeningArtwork.observe(RT, artworkBlocked())
        if AwakeningArtwork.isOpen() or AwakeningArtwork.hasPress() then return end
        rewardGesture.observe()
        ctx.observeTowerPress()
        if RewardPopup.isLarge() or marqueeGesture.hasPress() then return end
        if TowerBattleScene.isActive() or towerPress then return end
        if OfflineRewardPanel.isOpen() or UpdateNoticePopup.isOpen() or LevelUpPopup.isOpen() or levelPress then return end
        if DarkTitleScreen.isOpen() or LetterIntro.isOpen() or IntroCutscene.isActive()
            or ScenarioDialogue.isActive() or pressValid or equipOverlayPress
            or EquipCrossDrag.isArmed() then return end
        local mp = pointerPosition()
        local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
        if equipOverlayDesign(sx, sy) then return end
        local pid, dx, dy = HorizonResolveMouse()
        artifactGesture.hover(pid, sx, sy)
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
        if artworkPointer("up", eventData["Button"]:GetInt()) then return end
        if marqueeGesture.hasPress() then
            if eventData["Button"]:GetInt() == MOUSEB_RIGHT and ctx.pointerSource() == "mouse" then
                local mp = pointerPosition()
                local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
                marqueeGesture.up(sx, sy)
            else
                marqueeGesture.cancel()
            end
            return
        end
        if towerPress then
            if eventData["Button"]:GetInt() ~= MOUSEB_LEFT or towerPress.source ~= ctx.pointerSource() then return end
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            towerMove(sx, sy)
            local p = towerPress
            local isTap = validateTowerPress() and towerInputActive() and not p.moved
            TowerBattleScene.handleDragEnd()
            towerPress = nil
            pressValid = false
            equipmentPressPanel = nil
            if p.task then
                local layout = TowerBattleScene.getLayout(logicalW(), logicalH())
                local dx, dy = require("ui.tower.TowerLayout").toTask(layout, sx, sy)
                if isTap then TaskPage.handleDragEnd(dx, dy) else TaskPage.handleDragEnd(-1, -1) end
                if isTap then TaskPage.handleInput(dx, dy) end
            elseif isTap and not TaskPage.isOpen() then
                local now = time.elapsedTime
                if now - lastTapTime >= MIN_TAP_INTERVAL then
                    lastTapTime = now
                    TowerBattleScene.handleClick(sx, sy, logicalW(), logicalH())
                end
            end
            return
        end
        seamGesture.cancelIfBlocked()
        if seamGesture.hasPress() then
            if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            seamGesture.up(sx, sy, seamInputBlocked and seamInputBlocked())
            pressValid = false
            return
        end
        if tutorialEntryPress and eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
        if tutorialEntryPress and (not TutorialManager.isDetailEntryPressValid(tutorialEntryPress)
            or tutorialEntryPress.width ~= logicalW() or tutorialEntryPress.height ~= logicalH()
            or tutorialEntryPress.scale ~= (RT.frameScale or 1) or tutorialEntryPress.ox ~= (RT.frameOx or 0)
            or tutorialEntryPress.oy ~= (RT.frameOy or 0) or tutorialEntryPress.dpr ~= dpr()) then
            tutorialEntryPress = nil
            tutorialPress, tutorialBlockedPress = false, false
            TutorialManager.cancelDetailEntryPress()
            cancelUnderlyingPress()
            if tutorialInputActive() then return end
        end
        tutorialEntryPress = nil
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
            levelPress, levelMoved = false, false
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
        -- 最高模态链必须先于装备浮选/拖放/seam：CE、Update 保留原有优先级。
        if vg() then
            local mousePos = input:GetMousePosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            if CEPanel.handleUp(sx, sy, logicalH()) then
                CharacterPanel.handleDragEnd(-1, -1)
                artifactGesture.cancel()
                levelPress, levelMoved = false, false
                if LevelUpPopup.isOpen() then cancelUnderlyingPress() end
                return
            end
        end
        if bootReady_() and UpdateNoticePopup.isOpen() then
            local mousePos = input:GetMousePosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            local fit = math.min(logicalW() / 1080, logicalH() / 2400)
            if fit <= 0 then fit = 1 end
            local dx = (sx - (logicalW() - 1080 * fit) * 0.5) / fit
            local dy = (sy - (logicalH() - 2400 * fit) * 0.5) / fit
            CharacterPanel.handleDragEnd(-1, -1)
            UpdateNoticePopup.handleInput(dx, dy)
            levelPress, levelMoved = false, false
            pressValid = false
            return
        end
        if LevelUpPopup.isOpen() and not levelUpInputActive() then
            -- 标题/开场仍保留原优先级；升级捕获不得抢掉后来出现的更高层继续事件。
            cancelUnderlyingPress()
            levelPress, levelMoved = false, false
        end
        if levelUpInputActive() or levelPress then
            if levelTouchId ~= nil then return end
            local mousePos = input:GetMousePosition()
            local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
            levelUp(sx, sy, eventData["Button"]:GetInt())
            return
        end
        if rewardGesture.pointer("end", eventData["Button"]:GetInt()) then return end
        local terminalPos = pointerPosition()
        local terminalX, terminalY = toDesign(terminalPos.x / dpr(), terminalPos.y / dpr())
        if terminalInput then
            local consumed = terminalInput.up(terminalX, terminalY, eventData["Button"]:GetInt())
            if eventData["Button"]:GetInt() == MOUSEB_LEFT then terminalInput = nil end
            if consumed then return end
        elseif TerminalConfirmDialog.isOpen() then cancelUnderlyingPress() return end
        if towerInputActive() then
            -- 塔打开前的旧Down/无Down松手不下放到新塔按钮或旧名册落队。
            cancelUnderlyingPress()
            return
        end
        if eventData["Button"]:GetInt() == MOUSEB_LEFT then
            local mp = pointerPosition()
            local sx, sy = toDesign(mp.x / dpr(), mp.y / dpr())
            if artifactGesture.up(sx, sy) then pressValid = false return end
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
        local button = eventData["Button"]:GetInt()
        local wasLootPress = lootPress
        if button == MOUSEB_LEFT then
            -- 领奖若在拖拽途中出现，先撤销旧来源，再走弹窗Up；不能先尝试落队。
            if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
                CharacterPanel.handleDragEnd(-1, -1)
            end
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
        local seamBtn = (not seamInputBlocked or not seamInputBlocked()) and seamHitAt(seamX, seamY)
        if seamBtn then
            cancelUnderlyingPress()
            return -- 没有在返回箭头上按下：只释放来源，绝不把跨栏落点当成返回。
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
        if equipmentPressPanel == 'tri' and pid ~= 'tri' then
            -- 战斗掉落从中栏拖到侧栏松手：释放起点滚动，禁止误点目标栏。
            BattleTriPage.handleDragEnd(-1, -1)
            isTap = false
        end
        equipmentPressPanel = nil
        -- 配装部位属于纯 UI 操作，详情外第一击也可立即选槽/取消；
        -- 判定放在真跨栏拖拽已结算之后，绝不把拖放当成点击。
        if isTap and not TutorialManager.isActive() and not RewardPopup.isOpen()
            and (pid == 'right' or (pid == 'center' and BottomNav.getSelectedIndex() == 1)) then
            local detail = require("ui.character.detail.CharacterDetail")
            if detail.handleEquipmentSlotTap then detail.handleEquipmentSlotTap(dx, dy) end
        end
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
            if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
                RewardPopup.handleDragEnd(dx, dy)
                if isTap then RewardPopup.handleInput(dx, dy) end
                return
            end
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
            if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
                RewardPopup.handleDragEnd(dx, dy)
                if isTap then RewardPopup.handleInput(dx, dy) end
                return
            end
            if TowerBattleScene.isActive() then
                if isTap then TowerBattleScene.handleClick(dx, dy, logicalW(), logicalH()) end
                return
            end
            if DungeonBattleScene.isOpen() then
                DungeonBattleScene.handleDragEnd(dx, dy)
                if isTap then DungeonBattleScene.handleInput(dx, dy, logicalW(), logicalH()) end
                return
            end
            if PlayerInfoPanel.isOpen() then
                PlayerInfoPanel.handleDragEnd(dx, dy)
                if isTap then PlayerInfoPanel.handleInput(dx, dy) end
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
            -- 锻炉页已移中栏（center 分支处理），左栏链不再接管
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
        -- 锻炉页在中栏：优先接管（tri 模式下中段命中映射到 center 设计坐标）
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
        if not (OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen() or levelTouchId ~= nil)
            or not (UpdateNoticePopup.isOpen() or DarkTitleScreen.isOpen() or LetterIntro.isOpen()
                or IntroCutscene.isActive() or ScenarioDialogue.isActive()) then return false end
        cancelUnderlyingPress()
        levelPress, levelMoved = false, false
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
        touchPosition = { x = eventData["X"]:GetInt(), y = eventData["Y"]:GetInt(), id = eventData["TouchID"]:GetInt() }
        local proxy = { Button = { GetInt = function() return MOUSEB_LEFT end } }
        local ok, err = pcall(handler, eventType, proxy)
        touchPosition = nil
        if not ok then error(err) end
    end

    function HandleTouchBeginHorizon(eventType, eventData)
        if AwakeningArtwork.hasPress() or (AwakeningArtwork.isOpen() and not artworkBlocked()) then
            AwakeningArtwork.captureTouch(eventData["TouchID"]:GetInt())
            if activeTouchId ~= nil then return end
            activeTouchId = eventData["TouchID"]:GetInt()
            dispatchTouch(eventType, eventData, HandleMouseButtonDownHorizon)
            return
        end
        if handleTopTouch(eventData, false) then return end
        if levelUpInputActive() then
            cancelUnderlyingPress()
            levelTouches[eventData["TouchID"]:GetInt()] = true
            if levelTouchId == nil then
                local sx, sy = offlineTouchPosition(eventData)
                levelTouchId = eventData["TouchID"]:GetInt()
                if vg() and CEPanel.handleDown(sx, sy, logicalH()) then return end
                levelDown(sx, sy, MOUSEB_LEFT)
            end
            return
        end
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
        -- 模态可能在拖拽中途出现；主指结束时即释放所有权，早退分支也不得锁住下一指。
        local releasedActive = eventData["TouchID"]:GetInt() == activeTouchId
        if releasedActive then activeTouchId = nil end
        if AwakeningArtwork.releaseTouch(eventData["TouchID"]:GetInt()) then
            if releasedActive then dispatchTouch(eventType, eventData, HandleMouseButtonUpHorizon) end
            return
        end
        if releasedActive and towerPress then
            dispatchTouch(eventType, eventData, HandleMouseButtonUpHorizon)
            return
        end
        if releasedActive and seamGesture and seamGesture.hasPress() then
            dispatchTouch(eventType, eventData, HandleMouseButtonUpHorizon)
            return
        end
        if handleTopTouch(eventData, true) then
            if eventData["TouchID"]:GetInt() == offlineTouchId then offlineTouchId = nil end
            if eventData["TouchID"]:GetInt() == levelTouchId then levelTouchId = nil end
            levelTouches[eventData["TouchID"]:GetInt()] = nil
            return
        end
        if not OfflineRewardPanel.isOpen()
            and (levelUpInputActive() or levelTouchId ~= nil or levelTouches[eventData["TouchID"]:GetInt()]) then
            cancelUnderlyingPress()
            if eventData["TouchID"]:GetInt() == levelTouchId then
                local sx, sy = offlineTouchPosition(eventData)
                if vg() and CEPanel.handleUp(sx, sy, logicalH()) then
                    levelPress, levelMoved = false, false
                else
                    levelUp(sx, sy, MOUSEB_LEFT)
                end
                levelTouchId = nil
            end
            levelTouches[eventData["TouchID"]:GetInt()] = nil
            return
        end
        if OfflineRewardPanel.isOpen() or offlineTouchId ~= nil then
            levelPress, levelMoved = false, false
            if eventData["TouchID"]:GetInt() == levelTouchId then levelTouchId = nil end
            levelTouches[eventData["TouchID"]:GetInt()] = nil
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
        if not releasedActive then return end
        dispatchTouch(eventType, eventData, HandleMouseButtonUpHorizon)
    end

    function HandleTouchMoveHorizon(eventType, eventData)
        if AwakeningArtwork.hasTouch(eventData["TouchID"]:GetInt()) then
            if eventData["TouchID"]:GetInt() == activeTouchId then dispatchTouch(eventType, eventData, HandleMouseMoveHorizon) end
            return
        end
        if eventData["TouchID"]:GetInt() == activeTouchId and seamGesture and seamGesture.hasPress() then
            dispatchTouch(eventType, eventData, HandleMouseMoveHorizon)
            return
        end
        if handleTopTouch(eventData, false) then return end
        if not OfflineRewardPanel.isOpen()
            and (levelUpInputActive() or levelTouchId ~= nil or levelTouches[eventData["TouchID"]:GetInt()]) then
            cancelUnderlyingPress()
            if eventData["TouchID"]:GetInt() == levelTouchId then
                local sx, sy = offlineTouchPosition(eventData)
                levelMove(sx, sy)
            end
            return
        end
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

    HandleMouseWheelHorizon = horizonWheel.bindWheel({
        marqueeGesture = marqueeGesture, getLevelPress = function() return levelPress end,
        cancelUnderlyingPress = cancelUnderlyingPress, artworkBlocked = artworkBlocked, RT = RT,
    })

end

return Input
