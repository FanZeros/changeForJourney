-- ============================================================================
-- ClientRender - 多人客户端 NanoVG 主渲染（原 HandleNanoVGRender_Client）
-- 通过 bind(deps) 注入 Client 局部状态
-- ============================================================================

local StartScreen        = require("ui.StartScreen")
local LoadingScreen      = require("ui.LoadingScreen")
local DarkTitleScreen    = require("ui.DarkTitleScreenGate")
local LetterIntro        = require("ui.LetterIntro")
local CharacterSelect    = require("ui.CharacterSelect")
local VersionMismatchPopup = require("ui.VersionMismatchPopup")
local ViewportH          = require("core.ViewportH")
local TownScene          = require("ui.TownScene")
local BlacksmithPage     = require("ui.BlacksmithPage")
local ChurchPage         = require("ui.ChurchPage")
local TavernPage         = require("ui.TavernPage")
local MarketPage         = require("ui.MarketPage")
local GuildPage          = require("ui.GuildPage")
local LootBox            = require("ui.LootBox")
local CharacterPanel     = require("ui.CharacterPanel")
local DebugPanel         = require("ui.DebugPanel")
local DungeonBattleScene = require("ui.DungeonBattleScene")
local TowerBattleScene   = require("ui.TowerBattleScene")
local BottomNav          = require("ui.BottomNav")
local DiaryPage          = require("ui.DiaryPage")
local DungeonPage        = require("ui.DungeonPage")
local BattleScene        = require("ui.BattleScene")
local TopBar             = require("ui.TopBar")
local SignInPanel        = require("ui.SignInPanel")
local BackpackPanel      = require("ui.BackpackPanel")
local TaskPanel          = require("ui.TaskPanel")
local RewardPopup        = require("ui.RewardPopup")
local LevelUpPopup       = require("ui.LevelUpPopup")
local OfflineRewardPanel = require("ui.OfflineRewardPanel")
local UpdateNoticePopup  = require("ui.UpdateNoticePopup")
local PlayerInfoPanel    = require("ui.PlayerInfoPanel")
local HeroRosterPanel    = require("ui.HeroRosterPanel")
local IntroCutscene      = require("ui.IntroCutscene")
local ScenarioDialogue   = require("ui.ScenarioDialogue")
local SpinePowerUpEffect = require("ui.SpinePowerUpEffect")
local TutorialManager    = require("systems.TutorialManager")

local M = {}
local D = {}
M.D = D

function M.bind(deps)
    D = deps
    M.D = D
end

function M.HandleNanoVGRender(eventType, eventData)
    if not D.vg then return end

    -- 横屏 PC 多面板（changeForJourney）：状态感知 letterbox
    if not D.H_skipDone and StartScreen.isOpen() then
        D.H_skipDone = true
        StartScreen.skipForReconnect()
        DarkTitleScreen.open()  -- [DarkTitleScreen] 竖屏标题被跳过，改以横屏暗黑标题呈现
        DarkTitleScreen.setReady(not LoadingScreen.isOpen())
    end
    if StartScreen.isOpen() or LoadingScreen.isOpen() or LetterIntro.isOpen() or CharacterSelect.isActive() then
        local ss = math.min(D.logicalW / 1080, D.logicalH / 2400)
        D.scale = ss
        -- 外层 nvgScale(D.scale) 会缩放 translate 值：偏移需除以 D.scale（缩放空间语义）
        D.designOffsetX = (D.logicalW - 1080 * ss) / (2 * ss)
        D.designOffsetY = (D.logicalH - 2400 * ss) / (2 * ss)
    else
        local vox, voy, vs = ViewportH.layout(D.logicalW, D.logicalH)
        D.H_ox, D.H_oy, D.H_s = vox, voy, vs
        D.scale = vs
        D.designOffsetX = (vox + ViewportH.PANELS.center.bx * vs) / vs
        D.designOffsetY = voy / vs
    end

    nvgBeginFrame(D.vg, D.logicalW, D.logicalH, D.dpr)

    -- 全窗口底色
    nvgBeginPath(D.vg)
    nvgRect(D.vg, 0, 0, D.logicalW, D.logicalH)
    nvgFillColor(D.vg, nvgRGBA(14, 14, 22, 255))
    nvgFill(D.vg)
    -- 左右面板（独立变换，主渲染缩进中面板）
    -- 标题未淡出时不画侧栏，避免标题底下先露出竖屏战斗/城镇
    if D.currentState == D.STATE_IN_GAME and not StartScreen.isOpen() and not LoadingScreen.isOpen() and not LetterIntro.isOpen()
        and not (DarkTitleScreen.isOpen() and not DarkTitleScreen.isFading()) then
        nvgSave(D.vg)
        nvgResetTransform(D.vg)
        ViewportH.begin(D.vg, ViewportH.PANELS.left, D.H_ox, D.H_oy, D.H_s)
        TownScene.draw(D.vg)
        BlacksmithPage.draw(D.vg)
        ChurchPage.draw(D.vg)
        TavernPage.draw(D.vg)
        MarketPage.draw(D.vg)
        GuildPage.draw(D.vg)
        LootBox.draw(D.vg)   -- 全局战利品箱（整页左下角，主线/通天塔/副本共用一份）
        ViewportH.finish(D.vg)
        ViewportH.begin(D.vg, ViewportH.PANELS.right, D.H_ox, D.H_oy, D.H_s)
        CharacterPanel.draw(D.vg)
        ViewportH.finish(D.vg)
        nvgRestore(D.vg)
    end

    nvgScale(D.vg, D.scale, D.scale)

    -- 开始界面（最高优先级，覆盖所有内容）
    if StartScreen.isOpen() then
        nvgSave(D.vg)
        nvgTranslate(D.vg, D.designOffsetX, D.designOffsetY)
        StartScreen.draw(D.vg)
        VersionMismatchPopup.draw(D.vg)
        nvgRestore(D.vg)
        nvgEndFrame(D.vg)
        return
    end

    -- 加载界面（第二优先级）
    if LoadingScreen.isOpen() then
        nvgSave(D.vg)
        nvgTranslate(D.vg, D.designOffsetX, D.designOffsetY)
        LoadingScreen.draw(D.vg)
        nvgRestore(D.vg)
        nvgEndFrame(D.vg)
        return
    end

    -- 标题未淡出：只画标题，避免底下竖屏 BattleScene 先闪一帧
    if DarkTitleScreen.isOpen() and not DarkTitleScreen.isFading() then
        DarkTitleScreen.draw(D.vg, D.logicalW, D.logicalH)
        nvgEndFrame(D.vg)
        return
    end

    if D.currentState == D.STATE_IN_GAME then
      local _rok, _rerr = pcall(function()
        -- 调试面板
        DebugPanel.draw(D.vg, D.designOffsetX, D.screenDesignW)

        -- 进入设计空间
        nvgSave(D.vg)
        nvgTranslate(D.vg, D.designOffsetX, D.designOffsetY)

        local dungeonBattleOpen = DungeonBattleScene.isOpen()
        local towerBattleOpen = TowerBattleScene.isActive()
        if towerBattleOpen then
            local lw = graphics:GetWidth() / (graphics:GetDPR() or 1)
            local lh = graphics:GetHeight() / (graphics:GetDPR() or 1)
            nvgRestore(D.vg)
            nvgSave(D.vg)
            nvgScissor(D.vg, 0, 0, lw, lh)
            TowerBattleScene.draw(D.vg, lw, lh)
            nvgRestore(D.vg)
            nvgSave(D.vg)
            nvgTranslate(D.vg, D.designOffsetX, D.designOffsetY)
            -- 不绘制TopBar/BottomNav
        elseif dungeonBattleOpen then
            DungeonBattleScene.draw(D.vg)
            -- 不绘制TopBar/BottomNav
        else
            local tabIndex = BottomNav.getSelectedIndex()

            --- 绘制指定 tab 的页面内容
            local function drawTabPage(idx)
                if idx == 1 then
                    CharacterPanel.draw(D.vg)
                elseif idx == 2 then
                    DiaryPage.draw(D.vg)
                elseif idx == 3 then
                    BattleScene.draw(D.vg)
                elseif idx == 4 then
                    TownScene.draw(D.vg)
                    BlacksmithPage.draw(D.vg)
                    ChurchPage.draw(D.vg)
                    TavernPage.draw(D.vg)
                    MarketPage.draw(D.vg)
                    GuildPage.draw(D.vg)
                elseif idx == 5 then
                    DungeonPage.draw(D.vg)
                end
            end

            if D.pageTrans.active then
                -- 过渡动画：旧页面淡出，新页面从下方弹起淡入
                local t = D.easeOutBack(D.pageTrans.progress)   -- easeOutBack 回弹，呼应标签弹起感
                local RISE_DIST = 80  -- 新页面起始偏移量（设计像素）
                local cx = D.screenDesignW * 0.5
                local cy = D.screenDesignH * 0.5

                -- 旧页面：快速淡出（前半段结束）
                local oldAlpha = math.max(0, 1 - D.pageTrans.progress * 2)
                nvgSave(D.vg)
                nvgGlobalAlpha(D.vg, oldAlpha)
                drawTabPage(D.pageTrans.fromIndex)
                nvgRestore(D.vg)

                -- 新页面：从下方RISE_DIST px 处上升+ 从0.96 缩放到1.0 + 淡入
                local newAlpha  = math.min(1, D.pageTrans.progress * 1.5)
                local offsetY   = RISE_DIST * (1 - t)                 -- 从下方升起
                local pageScale = 0.96 + 0.04 * t                     -- 0.96 →1.0

                nvgSave(D.vg)
                nvgGlobalAlpha(D.vg, newAlpha)
                nvgTranslate(D.vg, cx, cy + offsetY)
                nvgScale(D.vg, pageScale, pageScale)
                nvgTranslate(D.vg, -cx, -cy)
                drawTabPage(D.pageTrans.toIndex)
                nvgRestore(D.vg)
            else
                drawTabPage(tabIndex)
            end

            local detailOpen = CharacterPanel.isDetailOpen()
            local smithOpen  = BlacksmithPage.isOpen()
            local churchOpen = ChurchPage.isOpen()
            local tavernOpen = TavernPage.isOpen()
            local marketOpen = MarketPage.isOpen()
            local guildOpen  = GuildPage.isOpen()
            local signInOpen = SignInPanel.isOpen()
            local backpackOpen = BackpackPanel.isOpen()
            local taskOpen   = TaskPanel.isOpen()
            if not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not marketOpen and not guildOpen and not signInOpen and not backpackOpen and not taskOpen then
                if tabIndex ~= 5 then
                    TopBar.draw(D.vg)
                end
                BottomNav.draw(D.vg)
            elseif taskOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not guildOpen and not signInOpen and not backpackOpen then
                local animP = TaskPanel.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(D.vg)
                    nvgGlobalAlpha(D.vg, fadeAlpha)
                    TopBar.draw(D.vg)
                    BottomNav.draw(D.vg)
                    nvgRestore(D.vg)
                end
            elseif backpackOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not guildOpen and not signInOpen then
                local animP = BackpackPanel.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(D.vg)
                    nvgGlobalAlpha(D.vg, fadeAlpha)
                    TopBar.draw(D.vg)
                    BottomNav.draw(D.vg)
                    nvgRestore(D.vg)
                end
            elseif signInOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not guildOpen then
                local animP = SignInPanel.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(D.vg)
                    nvgGlobalAlpha(D.vg, fadeAlpha)
                    TopBar.draw(D.vg)
                    BottomNav.draw(D.vg)
                    nvgRestore(D.vg)
                end
            elseif marketOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not guildOpen then
                local animP = MarketPage.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(D.vg)
                    nvgGlobalAlpha(D.vg, fadeAlpha)
                    TopBar.draw(D.vg)
                    BottomNav.draw(D.vg)
                    nvgRestore(D.vg)
                end
            elseif guildOpen and not detailOpen and not smithOpen and not churchOpen and not tavernOpen and not marketOpen then
                local animP = GuildPage.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(D.vg)
                    nvgGlobalAlpha(D.vg, fadeAlpha)
                    TopBar.draw(D.vg)
                    BottomNav.draw(D.vg)
                    nvgRestore(D.vg)
                end
            elseif tavernOpen and not detailOpen and not smithOpen and not churchOpen then
                local animP = TavernPage.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(D.vg)
                    nvgGlobalAlpha(D.vg, fadeAlpha)
                    TopBar.draw(D.vg)
                    BottomNav.draw(D.vg)
                    nvgRestore(D.vg)
                end
            elseif churchOpen and not detailOpen and not smithOpen then
                local animP = ChurchPage.getAnimProgress()
                if animP < 1.0 then
                    local fadeAlpha = 1.0 - animP
                    nvgSave(D.vg)
                    nvgGlobalAlpha(D.vg, fadeAlpha)
                    TopBar.draw(D.vg)
                    BottomNav.draw(D.vg)
                    nvgRestore(D.vg)
                end
            end
        end

        if not towerBattleOpen then
        HeroRosterPanel.draw(D.vg)

        -- 玩家信息弹窗（头像点击打开）
        PlayerInfoPanel.draw(D.vg)

        -- 战利品全屏页面（在RewardPopup 之前，覆盖游戏画面）
        LootBox.drawPage(D.vg)
        -- [仓库入口] 背包全窗模态（竖屏：设计空间=窗口空间，fit=1 等价内嵌绘制）
        if BackpackPanel.isOpen() and BackpackPanel.isWindowMode() then
            BackpackPanel.drawWindow(D.vg, 1080, 2400)
        end
        -- 自动分解设置弹窗（standalone 模式：从战利品面板直接调起，不打开铁匠铺）
        BlacksmithPage.drawAutoDecomposePopupStandalone(D.vg)
        -- 奖励弹窗（最顶层）
        RewardPopup.draw(D.vg)
        -- 冒险等级提升弹窗（最顶层）
        LevelUpPopup.draw(D.vg)
        -- 离线收益面板（最顶层弹窗）
        OfflineRewardPanel.draw(D.vg)
        -- 战斗力提升特效（叠加在弹窗之上）
        SpinePowerUpEffect.draw(D.vg)
        -- 更新提醒弹窗（最最顶层）
        UpdateNoticePopup.draw(D.vg)

        -- 新手过场动画（覆盖所有游戏UI）
        if IntroCutscene.isActive() then
            IntroCutscene.draw(D.vg)
        end

        -- 情景对话（覆盖所有游戏UI，紧接在过场动画之后）
        if ScenarioDialogue.isActive() then
            ScenarioDialogue.draw()
        end

        -- 选择初始角色：横屏改由全窗口 letterbox 绘制（见 HandleNanoVGRender_Client 尾部）

        -- 新手引导蒙层（覆盖在所有游戏UI 之上，情景对话之后）
        if TutorialManager.isActive() then
            TutorialManager.draw()
        end
        end -- not towerBattleOpen

        nvgRestore(D.vg)
      end) -- pcall end (render)
      if not _rok then
        print("[Client] render error: " .. tostring(_rerr))
      end
    end

    -- 遮罩层（最顶层）
    D.drawOverlay()

    -- Update 安全网：检测update handler 是否存活，停滞时自动重新订阅
    do
        if D._diag_updateFrameNum == D._diag_renderLastSeenFrame then
            D._diag_renderStallCount = (D._diag_renderStallCount or 0) + 1
        else
            D._diag_renderStallCount = 0
            D._diag_renderLastSeenFrame = D._diag_updateFrameNum
        end
        -- 连续 ~2秒未更新→重新订阅 Update 事件
        if D._diag_renderStallCount == 120 then
            print("[Client] Update handler stalled, re-subscribing...")
            SubscribeToEvent("Update", "HandleUpdate_Client")
        end
    end


    -- [DarkTitleScreen] 横屏标题（全窗口逻辑坐标，覆盖一切直至点击淡出）
    if DarkTitleScreen.isOpen() then
        nvgResetTransform(D.vg)
        DarkTitleScreen.draw(D.vg, D.logicalW, D.logicalH)
    end

    -- [LetterIntro] 先祖来信（全窗口 16:9 cover，盖住三联面板）
    if LetterIntro.isOpen() then
        nvgResetTransform(D.vg)
        ---@diagnostic disable-next-line: missing-parameter
        LetterIntro.draw(D.vg, D.logicalW, D.logicalH)
    end
    -- 选角：竖屏 1080×2400 letterbox 全窗口覆盖（不再缩进中栏）
    if CharacterSelect.isActive() then
        nvgResetTransform(D.vg)
        local ss = math.min(D.logicalW / 1080, D.logicalH / 2400)
        nvgTranslate(D.vg, (D.logicalW - 1080 * ss) * 0.5, (D.logicalH - 2400 * ss) * 0.5)
        nvgScale(D.vg, ss, ss)
        CharacterSelect.draw()
    end

    nvgEndFrame(D.vg)
end


return M
