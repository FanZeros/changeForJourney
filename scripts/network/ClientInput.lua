-- ============================================================================
-- ClientInput.lua - 客户端输入处理子模块
-- 职责: 鼠标/触摸/滚轮事件 → 设计坐标转换 → 事件分发到各 UI 模块
-- 从 Client.lua 拆分，减少主文件行数
-- ============================================================================

local TopBar           = require("ui.TopBar")
local BottomNav        = require("ui.BottomNav")
local BattleScene      = require("ui.BattleScene")
local CharacterPanel   = require("ui.CharacterPanel")
local DebugPanel       = require("ui.DebugPanel")
local HeroRosterPanel  = require("ui.HeroRosterPanel")
local RewardPopup      = require("ui.RewardPopup")
local TownScene        = require("ui.TownScene")
local BlacksmithPage   = require("ui.BlacksmithPage")
local ChurchPage       = require("ui.ChurchPage")
local TavernPage       = require("ui.TavernPage")
local ArenaPage        = require("ui.ArenaPage")
local MarketPage       = require("ui.MarketPage")
local GuildPage        = require("ui.GuildPage")
local ArenaBattleScene = require("ui.ArenaBattleScene")
local DungeonBattleScene = require("ui.DungeonBattleScene")
local TowerBattleScene   = require("ui.TowerBattleScene")
local LootBox          = require("ui.LootBox")
local StartScreen      = require("ui.StartScreen")
local DarkTitleScreen  = require("ui.DarkTitleScreenGate")  -- [DarkTitleScreen] 横屏暗黑标题
local LetterIntro      = require("ui.LetterIntro")      -- [LetterIntro] 先祖来信（首登剧情）
local LevelUpPopup     = require("ui.LevelUpPopup")
local OfflineRewardPanel = require("ui.OfflineRewardPanel")
local UpdateNoticePopup = require("ui.UpdateNoticePopup")
local VersionMismatchPopup = require("ui.VersionMismatchPopup")
local PlayerInfoPanel  = require("ui.PlayerInfoPanel")
local DiaryPage        = require("ui.DiaryPage")
local DrawUtil         = require("core.DrawUtil")
local ScenarioDialogue = require("ui.ScenarioDialogue")
local DungeonPage      = require("ui.DungeonPage")
local CharacterSelect  = require("ui.CharacterSelect")
local TutorialManager  = require("systems.TutorialManager")
local BF               = require("systems.ButtonFeedback")
local GameSFX          = require("systems.GameSFX")

local M = {}

-- ======================== 上下文（由 Client.setContext 注入） ========================

local dpr, scale, designOffsetX, designOffsetY = 1, 1, 0, 0
local currentStateFn   -- function() → string   (读取连接状态)
local STATE_IN_GAME    -- string 常量

-- 完整点击判定：按下+松开位移过大视为滑动，不触发点击
local TAP_THRESHOLD = 15
local pressStartDX, pressStartDY = 0, 0
local pressValid = false

-- 最小点击间隔（防止移动端单击误触发双击）
local MIN_TAP_INTERVAL = 0.12  -- 秒（120ms）
local lastTapTime = 0

--- 注入上下文
---@param ctx table
function M.setContext(ctx)
    dpr            = ctx.dpr
    scale          = ctx.scale
    designOffsetX  = ctx.designOffsetX
    designOffsetY  = ctx.designOffsetY or 0
    currentStateFn = ctx.currentStateFn
    STATE_IN_GAME  = ctx.STATE_IN_GAME
end

-- ======================== 坐标转换 ========================

--- 物理像素 → 设计坐标
local function toDesign(px, py)
    local sx = px / dpr / scale
    local sy = py / dpr / scale
    if HORIZON_MODE and currentStateFn and currentStateFn() == STATE_IN_GAME
        and not StartScreen.isOpen() then
        local lw, lh = graphics:GetWidth() / (graphics:GetDPR() or 1), graphics:GetHeight() / (graphics:GetDPR() or 1)
        local vox, voy, vs = ViewportI.layout(lw, lh)
        local pid, pdx, pdy = ViewportI.hit(sx, sy, vox, voy, vs)
        if pid then
            H_panel = pid
            return pdx, pdy, sx, sy
        end
        H_panel = 'center'
        return sx - (vox + ViewportI.PANELS.center.bx * vs), sy - voy, sx, sy
    end
    return sx - designOffsetX, sy - designOffsetY, sx, sy
end

function M.updateLayoutFull(newDpr, newScale, newDesignOffsetX, newDesignOffsetY)
    dpr           = newDpr
    scale         = newScale
    designOffsetX = newDesignOffsetX
    designOffsetY = newDesignOffsetY
end

-- ======================== 拖拽分发（统一 Mouse/Touch） ========================

-- [fix] effectiveTab 前向声明：横屏面板路由在文件后段定义（原 local 定义晚于
-- 上方分发器的闭包捕获，运行时会解析为 nil 全局，LSP undefined-global）
local effectiveTab

--- 按下事件分发
local function dispatchDragBegin(dx, dy)
    -- [DarkTitleScreen] 标题期吞掉按下（继续由 dispatchDragEndAndTap 触发）
    if DarkTitleScreen.isOpen() then return end
    -- [LetterIntro] 信件期吞掉按下（轻触翻段由 dispatchDragEndAndTap 触发）
    if LetterIntro.isOpen() then return end
    pressStartDX, pressStartDY = dx, dy
    pressValid = true
    BF.onPress(dx, dy)

    -- 角色选择界面拦截（全屏，吞掉所有输入）
    if CharacterSelect.isActive() then return end

    -- 情景对话拦截（全屏，吞掉所有输入）
    if ScenarioDialogue.isActive() then return end

    -- 竞技场/副本对战全屏拦截
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.handleDragBegin(dx, dy)
        return
    end
    if DungeonBattleScene.isOpen() then
        DungeonBattleScene.handleDragBegin(dx, dy)
        return
    end
    if UpdateNoticePopup.isOpen() then return end
    if PlayerInfoPanel.isOpen() then
        PlayerInfoPanel.handleDragBegin(dx, dy)
        return
    end
    if RewardPopup.handleDragBegin(dx, dy) then return end
    if LevelUpPopup.isOpen() then return end
    if OfflineRewardPanel.isOpen() then
        OfflineRewardPanel.handleDragBegin(dx, dy)
        return
    end
    if LootBox.handleDragBegin(dx, dy) then return end

    local tabIndex = effectiveTab()
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        BlacksmithPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 4 and ChurchPage.isOpen() then
        ChurchPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 4 and TavernPage.isOpen() then
        TavernPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 4 and ArenaPage.isOpen() then
        ArenaPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 4 and MarketPage.isOpen() then
        MarketPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 4 and GuildPage.isOpen() then
        GuildPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 2 then
        DiaryPage.handleDragBegin(dx, dy)
        return
    end
    if tabIndex == 1 then
        CharacterPanel.handleDragBegin(dx, dy)
        return
    end
    -- 默认：战斗场景长按检测开始
    if tabIndex == 3 or tabIndex == nil then
        BattleScene.handlePressBegin(dx, dy)
    end
end

--- 移动事件分发
local function dispatchDragMove(dx, dy)
    -- [DarkTitleScreen] 标题期吞掉拖动
    if DarkTitleScreen.isOpen() then return end
    -- [LetterIntro] 信件期吞掉拖动
    if LetterIntro.isOpen() then return end
    -- 角色选择界面拦截
    if CharacterSelect.isActive() then return end

    -- 情景对话拦截
    if ScenarioDialogue.isActive() then return end

    -- 竞技场/副本对战全屏拦截
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.handleDragMove(dx, dy)
        return
    end
    if DungeonBattleScene.isOpen() then
        DungeonBattleScene.handleDragMove(dx, dy)
        return
    end
    if UpdateNoticePopup.isOpen() then return end
    if PlayerInfoPanel.isOpen() then
        PlayerInfoPanel.handleDragMove(dx, dy)
        return
    end
    if RewardPopup.handleDragMove(dx, dy) then return end
    if LevelUpPopup.isOpen() then return end
    if OfflineRewardPanel.isOpen() then
        OfflineRewardPanel.handleDragMove(dx, dy)
        return
    end
    if LootBox.handleDragMove(dx, dy) then return end

    local tabIndex = effectiveTab()
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        BlacksmithPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 4 and ChurchPage.isOpen() then
        ChurchPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 4 and TavernPage.isOpen() then
        TavernPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 4 and ArenaPage.isOpen() then
        ArenaPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 4 and MarketPage.isOpen() then
        MarketPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 4 and GuildPage.isOpen() then
        GuildPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 2 then
        DiaryPage.handleDragMove(dx, dy)
        return
    end
    if tabIndex == 1 then
        CharacterPanel.handleDragMove(dx, dy)
    end
end

local function openTrainingDummyBattle()
    local allies = CharacterPanel.getDeployedTeam()
    if not allies or #allies == 0 then
        print("[TrainingDummy] no deployed heroes, cannot open")
        return
    end
    print("[TrainingDummy] opening battle with allies=" .. tostring(#allies))
    DungeonBattleScene.open({
        allies = allies,
        data = {
            dungeonId = "training_dummy",
            floor = 1,
            monsterLevel = 1,
            monsters = { 1 },
            classBonus = "",
            classBonusValue = 0,
            rageTime = 999999,
            superRageTime = 999999,
            trainingDummy = true,
            dummyMaxHp = 1000000000000,
            dummyRegen = 1000000000000,
        },
        onClose = function()
            print("[TrainingDummy] closed")
        end,
    })
end

--- 松开事件分发（含点击判定）
local function dispatchDragEndAndTap(dx, dy)
    -- [DarkTitleScreen] 标题期任意释放 = 点击继续
    if DarkTitleScreen.isOpen() then
        DarkTitleScreen.handleTap()
        pressValid = false
        return
    end
    -- [LetterIntro] 信件期任意释放 = 轻触翻段
    if LetterIntro.isOpen() then
        LetterIntro.handleTap()
        pressValid = false
        return
    end
    BF.onRelease()
    BattleScene.handlePressEnd()
    -- 判断是否为有效点击
    local isTap = false
    if pressValid then
        local dist = math.abs(dx - pressStartDX) + math.abs(dy - pressStartDY)
        isTap = dist < TAP_THRESHOLD
    end
    pressValid = false

    -- 最小点击间隔保护（防止移动端单触误触发双击）
    if isTap then
        local now = time.elapsedTime
        if now - lastTapTime < MIN_TAP_INTERVAL then
            isTap = false
        else
            lastTapTime = now
        end
    end

    -- ===== [INPUT_DEBUG] 输入诊断：每次 tap 打印所有拦截层状态 =====
    if isTap then
        print(string.format("[INPUT_DEBUG] TAP(%.0f,%.0f) CharSel=%s ScnDlg=%s Arena=%s UpdNotice=%s PInfo=%s Reward=%s LvUp=%s OffRwd=%s LootBox=%s BS=%s Church=%s Tavern=%s ArenaP=%s Market=%s GuildP=%s tab=%s",
            dx, dy,
            tostring(CharacterSelect.isActive()),
            tostring(ScenarioDialogue.isActive()),
            tostring(ArenaBattleScene.isOpen()),
            tostring(DungeonBattleScene.isOpen()),
            tostring(UpdateNoticePopup.isOpen()),
            tostring(PlayerInfoPanel.isOpen()),
            tostring(RewardPopup.isOpen()),
            tostring(LevelUpPopup.isOpen()),
            tostring(OfflineRewardPanel.isOpen()),
            tostring(LootBox.isPageOpen()),
            tostring(BlacksmithPage.isOpen()),
            tostring(ChurchPage.isOpen()),
            tostring(TavernPage.isOpen()),
            tostring(ArenaPage.isOpen()),
            tostring(MarketPage.isOpen()),
            tostring(GuildPage.isOpen()),
            tostring(BottomNav.getSelectedIndex())
        ))
    end

    -- 角色选择界面拦截（点击选卡/按钮，其他输入吞掉）
    if CharacterSelect.isActive() then
        if isTap then print("[INPUT_DEBUG] >>> 被 CharacterSelect 拦截") end
        if isTap then CharacterSelect.handleTap(dx, dy) end
        return
    end

    -- 情景对话拦截（点击推进对话，其他输入吞掉）
    if ScenarioDialogue.isActive() then
        if isTap then print("[INPUT_DEBUG] >>> 被 ScenarioDialogue 拦截") end
        if isTap then ScenarioDialogue.advance() end
        return
    end

    -- 新手引导拦截（点击高亮区域推进/非高亮区域吞掉）
    if TutorialManager.isActive() then
        if isTap then
            local consumed = TutorialManager.handleClick(dx, dy)
            if consumed then
                print("[INPUT_DEBUG] >>> 被 TutorialManager 拦截（非高亮区域）")
                return
            end
            -- consumed=false：点击落在高亮区域，允许穿透，引导已推进
        end
    end

    -- 竞技场/副本对战拦截
    if ArenaBattleScene.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 ArenaBattleScene 拦截") end
        ArenaBattleScene.handleDragEnd(dx, dy)
        if isTap then ArenaBattleScene.handleInput(dx, dy) end
        return
    end
    if TowerBattleScene.isActive() then
        if isTap then TowerBattleScene.handleClick(dx, dy) end
        return
    end
    if DungeonBattleScene.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 DungeonBattleScene 拦截") end
        DungeonBattleScene.handleDragEnd(dx, dy)
        if isTap then DungeonBattleScene.handleInput(dx, dy) end
        return
    end
    -- UpdateNoticePopup 拦截（最顶层）
    if UpdateNoticePopup.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 UpdateNoticePopup 拦截") end
        if isTap then UpdateNoticePopup.handleInput(dx, dy) end
        return
    end
    -- PlayerInfoPanel 拦截（拖拽结束 + 点击处理）
    if PlayerInfoPanel.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 PlayerInfoPanel 拦截") end
        PlayerInfoPanel.handleDragEnd(dx, dy)
        if isTap then PlayerInfoPanel.handleInput(dx, dy) end
        return
    end
    -- RewardPopup 拦截
    if RewardPopup.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 RewardPopup 拦截") end
        RewardPopup.handleDragEnd(dx, dy)
        if isTap then RewardPopup.handleInput(dx, dy) end
        return
    end
    -- LevelUpPopup 拦截
    if LevelUpPopup.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 LevelUpPopup 拦截") end
        if isTap then LevelUpPopup.handleInput(dx, dy) end
        return
    end
    -- OfflineRewardPanel 拦截
    if OfflineRewardPanel.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 OfflineRewardPanel 拦截") end
        OfflineRewardPanel.handleDragEnd(dx, dy)
        if isTap then OfflineRewardPanel.handleInput(dx, dy) end
        return
    end
    -- LootBoxPage 拦截
    if LootBox.isPageOpen() then
        LootBox.handleDragEnd(dx, dy)
        if isTap then LootBox.handleInput(dx, dy) end
        return
    end
    -- 自动分解弹窗 standalone 拦截（从战利品面板调起，BlacksmithPage 未打开时）
    if isTap and BlacksmithPage.isAutoDecomposePopupStandaloneOpen() then
        BlacksmithPage.handleAutoDecomposePopupStandaloneInput(dx, dy)
        return
    end

    local tabIndex = effectiveTab()

    -- 铁匠铺
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 BlacksmithPage 拦截 (tab=4)") end
        BlacksmithPage.handleDragEnd(dx, dy)
        if not isTap then return end
        BlacksmithPage.handleInput(dx, dy)
        return
    end
    -- 教堂
    if tabIndex == 4 and ChurchPage.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 ChurchPage 拦截 (tab=4)") end
        ChurchPage.handleDragEnd(dx, dy)
        if not isTap then return end
        ChurchPage.handleInput(dx, dy)
        return
    end
    -- 酒馆
    if tabIndex == 4 and TavernPage.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 TavernPage 拦截 (tab=4)") end
        TavernPage.handleDragEnd(dx, dy)
        if not isTap then return end
        TavernPage.handleInput(dx, dy)
        return
    end
    -- 竞技场
    if tabIndex == 4 and ArenaPage.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 ArenaPage 拦截 (tab=4)") end
        ArenaPage.handleDragEnd(dx, dy)
        if not isTap then return end
        ArenaPage.handleInput(dx, dy)
        return
    end
    -- 市场
    if tabIndex == 4 and MarketPage.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 MarketPage 拦截 (tab=4)") end
        MarketPage.handleDragEnd(dx, dy)
        if not isTap then return end
        MarketPage.handleInput(dx, dy)
        return
    end
    -- 冒险者公会
    if tabIndex == 4 and GuildPage.isOpen() then
        if isTap then print("[INPUT_DEBUG] >>> 被 GuildPage 拦截 (tab=4)") end
        GuildPage.handleDragEnd(dx, dy)
        if not isTap then return end
        GuildPage.handleInput(dx, dy)
        return
    end
    -- 日记页（公告弹窗拖拽）
    if tabIndex == 2 then
        DiaryPage.handleDragEnd(dx, dy)
        if not isTap then return end
    end
    -- 角色界面
    if tabIndex == 1 then
        if CharacterPanel.isDraggingCard() then
            CharacterPanel.handleInput(dx, dy)
            CharacterPanel.handleDragEnd(dx, dy)
            return
        end
        CharacterPanel.handleDragEnd(dx, dy)
    end

    -- 滑动操作不触发任何点击
    if not isTap then return end

    -- 以下全部是点击事件分发
    -- 注意：DebugPanel 使用 sx,sy（未减 designOffset）
    local sx = dx + designOffsetX
    local sy = dy + designOffsetY
    if DebugPanel.handleInput(sx, sy) then return end
    if HeroRosterPanel.handleInput(dx, dy) then return end

    -- 头像点击 → 打开玩家信息面板
    -- 头像中心(98,136), 150x150, 仅在无子页面遮挡时响应
    local detailOpen = BlacksmithPage.isOpen() or ChurchPage.isOpen()
                    or TavernPage.isOpen() or ArenaPage.isOpen()
                    or MarketPage.isOpen() or GuildPage.isOpen()
                    or CharacterPanel.isDetailOpen()
                    or DiaryPage.hasOverlayOpen()
    if not detailOpen and not ArenaBattleScene.isOpen() and not DungeonBattleScene.isOpen() then
        if TopBar.hitTestTrainingDummy(dx, dy) then
            openTrainingDummyBattle()
            return
        end
        if DrawUtil.hitTest(dx, dy, 98, 136, 150, 150) then
            PlayerInfoPanel.open()
            return
        end
    end

    if tabIndex == 1 then
        if CharacterPanel.handleInput(dx, dy) then return end
    elseif tabIndex == 2 then
        if DiaryPage.handleInput(dx, dy) then return end
    elseif tabIndex == 3 then
        if BattleScene.handleInput(dx, dy) then return end
    elseif tabIndex == 4 then
        if BlacksmithPage.isOpen() then
            BlacksmithPage.handleInput(dx, dy)
            return
        end
        if ChurchPage.isOpen() then
            ChurchPage.handleInput(dx, dy)
            return
        end
        if TavernPage.isOpen() then
            TavernPage.handleInput(dx, dy)
            return
        end
        if ArenaPage.isOpen() then
            ArenaPage.handleInput(dx, dy)
            return
        end
        if MarketPage.isOpen() then
            MarketPage.handleInput(dx, dy)
            return
        end
        if GuildPage.isOpen() then
            GuildPage.handleInput(dx, dy)
            return
        end
        if TownScene.handleInput(dx, dy) then return end
    elseif tabIndex == 5 then
        if DungeonPage.handleInput(dx, dy) then return end
    end
    if isTap then print("[INPUT_DEBUG] >>> 到达 BottomNav（未被任何弹窗/页面拦截）") end
    local navHit = BottomNav.handleInput(dx, dy)
    if isTap then
        if navHit then
            GameSFX.playUIClick(2)  -- 命中了 BottomNav Tab
        else
            GameSFX.play("click")   -- 未命中任何可交互区域
        end
    end
end

--- 滚轮事件分发
function M.dispatchScroll(wheel)
    -- [DarkTitleScreen] 标题期吞掉滚轮
    if DarkTitleScreen.isOpen() then return end
    -- [LetterIntro] 信件期吞掉滚轮
    if LetterIntro.isOpen() then return end
    if CharacterSelect.isActive() then return end
    if ScenarioDialogue.isActive() then return end
    if ArenaBattleScene.isOpen() then
        ArenaBattleScene.handleScroll(wheel)
        return
    end
    if DungeonBattleScene.isOpen() then
        DungeonBattleScene.handleScroll(wheel)
        return
    end
    if UpdateNoticePopup.isOpen() then return end
    if PlayerInfoPanel.isOpen() then PlayerInfoPanel.handleScroll(wheel); return end
    if RewardPopup.isOpen() then RewardPopup.handleScroll(wheel); return end
    if LevelUpPopup.isOpen() then return end
    if OfflineRewardPanel.isOpen() then OfflineRewardPanel.handleScroll(wheel); return end
    if LootBox.isPageOpen() then LootBox.handleScroll(wheel); return end

    local tabIndex = effectiveTab()
    if tabIndex == 4 and BlacksmithPage.isOpen() then
        BlacksmithPage.handleScroll(wheel)
        return
    end
    if tabIndex == 4 and ChurchPage.isOpen() then
        ChurchPage.handleScroll(wheel)
        return
    end
    if tabIndex == 4 and TavernPage.isOpen() then
        TavernPage.handleScroll(wheel)
        return
    end
    if tabIndex == 4 and ArenaPage.isOpen() then
        ArenaPage.handleScroll(wheel)
        return
    end
    if tabIndex == 4 and MarketPage.isOpen() then
        MarketPage.handleScroll(wheel)
        return
    end
    if tabIndex == 4 and GuildPage.isOpen() then
        GuildPage.handleScroll(wheel)
        return
    end
    if tabIndex == 2 then
        DiaryPage.handleScroll(wheel)
        return
    end
    if tabIndex == 1 then
        CharacterPanel.handleScroll(wheel)
    end
    HeroRosterPanel.handleScroll(wheel * 60)
end

-- ======================== 全局事件处理函数 ========================

function M.handleMouseButtonDown(eventType, eventData)
    -- 开始界面拖拽拦截（选服面板滑动）
    if StartScreen.isOpen() then
        local button = eventData["Button"]:GetInt()
        if button == MOUSEB_LEFT then
            local mousePos = input:GetMousePosition()
            local dx, dy = toDesign(mousePos.x, mousePos.y)
            StartScreen.handleDragBegin(dx, dy)
        end
        return
    end
    if currentStateFn() ~= STATE_IN_GAME then return end
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end

    local mousePos = input:GetMousePosition()
    local dx, dy = toDesign(mousePos.x, mousePos.y)
    dispatchDragBegin(dx, dy)
end

function M.handleMouseMove(eventType, eventData)
    -- 开始界面拖拽拦截
    if StartScreen.isOpen() then
        local mousePos = input:GetMousePosition()
        local dx, dy = toDesign(mousePos.x, mousePos.y)
        StartScreen.handleDragMove(dx, dy)
        return
    end
    if currentStateFn() ~= STATE_IN_GAME then return end

    local mousePos = input:GetMousePosition()
    local dx, dy = toDesign(mousePos.x, mousePos.y)
    dispatchDragMove(dx, dy)
end

function M.handleMouseButtonUp(eventType, eventData)
    -- 开始界面拦截（拖拽结束 + 点击判定）
    if StartScreen.isOpen() then
        local button = eventData["Button"]:GetInt()
        if button == MOUSEB_LEFT then
            local mousePos = input:GetMousePosition()
            local dx, dy = toDesign(mousePos.x, mousePos.y)
            -- VersionMismatchPopup 拦截（覆盖在 StartScreen 之上）
            if VersionMismatchPopup.isOpen() then
                VersionMismatchPopup.handleInput(dx, dy)
                return
            end
            StartScreen.handleDragEnd(dx, dy)
            StartScreen.handleClick(dx, dy)
        end
        return
    end
    if currentStateFn() ~= STATE_IN_GAME then return end
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end

    local mousePos = input:GetMousePosition()
    local dx, dy = toDesign(mousePos.x, mousePos.y)
    dispatchDragEndAndTap(dx, dy)
end

function M.handleTouchBegin(eventType, eventData)
    -- 开始界面拖拽拦截（选服面板滑动）
    if StartScreen.isOpen() then
        local tx = eventData["X"]:GetInt()
        local ty = eventData["Y"]:GetInt()
        local dx, dy = toDesign(tx, ty)
        StartScreen.handleDragBegin(dx, dy)
        return
    end
    if currentStateFn() ~= STATE_IN_GAME then return end

    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local dx, dy = toDesign(tx, ty)
    dispatchDragBegin(dx, dy)
end

function M.handleTouchMove(eventType, eventData)
    -- 开始界面拖拽拦截
    if StartScreen.isOpen() then
        local tx = eventData["X"]:GetInt()
        local ty = eventData["Y"]:GetInt()
        local dx, dy = toDesign(tx, ty)
        StartScreen.handleDragMove(dx, dy)
        return
    end
    if currentStateFn() ~= STATE_IN_GAME then return end

    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local dx, dy = toDesign(tx, ty)
    dispatchDragMove(dx, dy)
end

function M.handleTouchEnd(eventType, eventData)
    -- 开始界面拦截（拖拽结束 + 点击判定）
    if StartScreen.isOpen() then
        local tx = eventData["X"]:GetInt()
        local ty = eventData["Y"]:GetInt()
        local dx, dy = toDesign(tx, ty)
        -- VersionMismatchPopup 拦截（覆盖在 StartScreen 之上）
        if VersionMismatchPopup.isOpen() then
            VersionMismatchPopup.handleInput(dx, dy)
            return
        end
        StartScreen.handleDragEnd(dx, dy)
        StartScreen.handleClick(dx, dy)
        return
    end
    if currentStateFn() ~= STATE_IN_GAME then return end

    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    local dx, dy = toDesign(tx, ty)
    dispatchDragEndAndTap(dx, dy)
end

function M.handleMouseWheel(eventType, eventData)
    -- 开始界面滚轮 → 选服面板滚动
    if StartScreen.isOpen() then
        local wheel = eventData["Wheel"]:GetInt()
        local mousePos = input:GetMousePosition()
        local dx, dy = toDesign(mousePos.x, mousePos.y)
        StartScreen.handleScroll(dx, dy, wheel)
        return
    end
    if currentStateFn() ~= STATE_IN_GAME then return end
    local wheel = eventData["Wheel"]:GetInt()
    M.dispatchScroll(wheel)
end


-- ============================================================================
-- 横屏 PC 多面板（changeForJourney）：输入面板路由
-- ============================================================================
ViewportI = require("core.Viewport")
HORIZON_MODE = true
H_panel = 'center'

-- [fix] 赋值给文件头部前向声明的 local（不可再加 local，否则上方闭包捕获的仍是 nil）
function effectiveTab()
    if not HORIZON_MODE then return BottomNav.getSelectedIndex() end
    if H_panel == 'left' then return 4 end
    if H_panel == 'right' then return 1 end
    return BottomNav.getSelectedIndex()
end

return M
