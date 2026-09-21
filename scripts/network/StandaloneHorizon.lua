---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- StandaloneHorizon - 横屏 PC 多面板渲染/输入（从 Standalone.lua 拆出）
-- 职责: 三栏视口绘制、中缝返回条、横屏点击/拖拽/滚轮路由
-- 不改变任何交互语义；Standalone 通过 Horizon.bind(ctx) 注入运行时状态
-- ============================================================================

local Viewport           = require("core.Viewport")
local BattleLayout       = require("core.BattleLayout")
local DrawUtil           = require("core.DrawUtil")
local DarkIcon           = require("core.DarkIcon")
local TopBar             = require("ui.TopBar")
local BottomNav          = require("ui.BottomNav")
local BattleScene        = require("ui.BattleScene")
local CharacterPanel     = require("ui.CharacterPanel")
local CharacterDetail    = require("ui.CharacterDetail")
local TownScene          = require("ui.TownScene")
local BlacksmithPage     = require("ui.BlacksmithPage")
local ChurchPage         = require("ui.ChurchPage")
local TavernPage         = require("ui.TavernPage")
local MarketPage         = require("ui.MarketPage")
local BackpackPanel      = require("ui.BackpackPanel")
local DungeonBattleScene = require("ui.DungeonBattleScene")
local TowerBattleScene   = require("ui.TowerBattleScene")
local DungeonPage        = require("ui.DungeonPage")
local DiaryPage          = require("ui.DiaryPage")
local BattleTriPage      = require("ui.BattleTriPage")
local SweepDialog        = require("ui.SweepDialog")
local DamageStatsPanel   = require("ui.DamageStatsPanel")
local StageSelectDialog  = require("ui.StageSelectDialog")
local ProjectileSystem   = require("ui.ProjectileSystem")
local BattleEffects      = require("ui.BattleEffects")
local StartScreen        = require("ui.StartScreen")
local DarkTitleScreen    = require("ui.DarkTitleScreenGate")
local LetterIntro        = require("ui.LetterIntro")
local IntroCutscene      = require("ui.IntroCutscene")
local ScenarioDialogue   = require("ui.ScenarioDialogue")
local HeroRosterPanel    = require("ui.HeroRosterPanel")
local PlayerInfoPanel    = require("ui.PlayerInfoPanel")
local LootBox            = require("ui.LootBox")
local RewardPopup        = require("ui.RewardPopup")
local OfflineRewardPanel = require("ui.OfflineRewardPanel")
local SpinePowerUpEffect = require("ui.SpinePowerUpEffect")
local LevelUpPopup       = require("ui.LevelUpPopup")

local Horizon = {}

---@class StandaloneHorizonCtx
---@field vg any
---@field logicalW number
---@field logicalH number
---@field dpr number
---@field DESIGN_W number
---@field DESIGN_H number
---@field bootReady boolean
---@field preload table
---@field drawPreloadOverlay fun(vg: any, W: number, H: number)

---@type StandaloneHorizonCtx
local ctx

function Horizon.bind(c)
    ctx = c
    print("[StandaloneHorizon] bound")
end

local WORLD_BG_PATH = "image/界面底板/城镇世界/UI_WORLD_BG.png"
local WORLD_BG_FALLBACK = "image/界面底板/城镇世界/UI_CZ_BJ.png"
local imgWorldBg_ = -1
local worldBgTried_ = false

local TAP_THRESHOLD = 15
---@type number
local pressStartDX = 0
---@type number
local pressStartDY = 0
local pressValid = false
local MIN_TAP_INTERVAL = 0.12
local lastTapTime = 0

-- ============================================================================
-- 横屏 PC 多面板模式（changeForJourney）
-- 左面板：功能页组（城镇 + 铁匠/酒馆/竞技场/市场）
-- 中面板：BottomNav 主视图（角色/日志/战斗）+ 全屏战斗页 + 全局弹窗层
-- 右面板：角色固定
-- 一期限制：弹窗为模态（绘制于中面板空间）；同一页面只在一个面板
-- ============================================================================
H_SKIP_START = true   -- 调试：跳过开始画面直接进主界面
H_skipDone = false
H_AUTO_DISMISS_TITLE = false  -- DarkTitleScreen 验收已通过：关闭无输入环境自动淡出钩子
-- 截图验收钩子默认值（由外部 _validate_entry.lua 运行时覆写；此处定义避免 LSP 未定义全局）
H_AUTO_TAB = false
H_AUTO_OPEN_PANEL = false
H_ox, H_oy, H_s = 0, 0, 1
H_lastPanel = 'center'
H_lastTopBarPower = nil  -- [三队并行] TopBar 战力逐帧比对缓存
H_SEAM_BACK = false      -- [三队并行] 三行模式=true：返回键由中缝层绘制，页面内不画

local function HorizonUpdateTransform()
    H_ox, H_oy, H_s = Viewport.layout(ctx.logicalW, ctx.logicalH)
    BattleLayout.setMode("strip")
    H_TRI_L0 = BattleTriPage.isOpen()  -- [暗黑替换] 面板透明底开关（L0 已铺营地/英灵墙）
    local triRenderScale = BattleTriPage.isOpen() and BattleLayout.CARD_SCALE or 1.0
    ProjectileSystem.setRenderScale(triRenderScale)
    BattleEffects.setRenderScale(triRenderScale)  -- [三行并行]
    H_SEAM_BACK = BattleTriPage.isOpen()  -- [三队并行] 中缝返回键层开关
    -- [三队并行] TopBar 战力跟随当前编辑队伍（页签切换无回调，逐帧比对刷新）
    local curPower = CharacterPanel.getTotalPower()
    if curPower ~= H_lastTopBarPower then
        H_lastTopBarPower = curPower
        TopBar.setTotalPower(curPower)
    end
end

-- [底栏移除] 横屏日志(2)/副本(5)页：竖版设计全窗等比铺（模态层）
-- 全屏弹窗/战斗覆盖打开时不画（它们自带层级与让位逻辑）
local function HorizonDrawPageModal(vg)
    local tabIndex = BottomNav.getSelectedIndex()
    if tabIndex ~= 2 and tabIndex ~= 5 then return end
    if DungeonBattleScene.isOpen() or TowerBattleScene.isActive() then return end
    local fit = math.min(ctx.logicalW / ctx.DESIGN_W, ctx.logicalH / ctx.DESIGN_H)
    local ox = (ctx.logicalW - ctx.DESIGN_W * fit) * 0.5
    local oy = (ctx.logicalH - ctx.DESIGN_H * fit) * 0.5
    nvgSave(ctx.vg)
    nvgScissor(ctx.vg, 0, 0, ctx.logicalW, ctx.logicalH)
    nvgBeginPath(ctx.vg)
    nvgRect(ctx.vg, 0, 0, ctx.logicalW, ctx.logicalH)
    nvgFillColor(ctx.vg, nvgRGBA(8, 8, 10, 235))
    nvgFill(ctx.vg)
    nvgScissor(ctx.vg, ox, oy, ctx.DESIGN_W * fit, ctx.DESIGN_H * fit)
    nvgTranslate(ctx.vg, ox, oy)
    nvgScale(ctx.vg, fit, fit)
    if tabIndex == 2 then DiaryPage.draw(ctx.vg) else DungeonPage.draw(ctx.vg) end
    nvgRestore(ctx.vg)
end

--- [LetterIntro] 开场链全窗口覆盖：信件铺满窗口；过场/情景仍用 1080×2400 letterbox
local function HorizonDrawIntroOverlay()
    if not (LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive()) then
        return
    end
    nvgSave(ctx.vg)
    nvgResetTransform(ctx.vg)
    nvgScissor(ctx.vg, 0, 0, ctx.logicalW, ctx.logicalH)
    if LetterIntro.isOpen() then
        -- 全窗口逻辑坐标，16:9 cover，不再 letterbox 成竖条
        ---@diagnostic disable-next-line: missing-parameter
        LetterIntro.draw(ctx.vg, ctx.logicalW, ctx.logicalH)
    else
        local ss = math.min(ctx.logicalW / 1080, ctx.logicalH / 2400)
        nvgTranslate(ctx.vg, (ctx.logicalW - 1080 * ss) * 0.5, (ctx.logicalH - 2400 * ss) * 0.5)
        nvgScale(ctx.vg, ss, ss)
        if IntroCutscene.isActive() then
            IntroCutscene.draw(ctx.vg)
        elseif ScenarioDialogue.isActive() then
            ScenarioDialogue.draw()
        end
    end
    nvgRestore(ctx.vg)
end

--- [弹窗聚焦] 中面板有模态弹窗时，压暗左右面板（基屏幕空间，绘制于侧栏之后、中面板之前）
local function HorizonDimSidePanels()
    local modalOpen =
        HeroRosterPanel.isVisible() or PlayerInfoPanel.isOpen() or
        LootBox.isPageOpen() or RewardPopup.isOpen() or
        OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen() or
        SpinePowerUpEffect.isPlaying() or IntroCutscene.isActive()
    if not modalOpen then return end

    local w = Viewport.PW * H_s
    local h = Viewport.PH * H_s
    nvgBeginPath(ctx.vg)
    nvgRect(ctx.vg, H_ox, H_oy, w, h)
    nvgRect(ctx.vg, H_ox + Viewport.PANELS.right.bx * H_s, H_oy, w, h)
    nvgFillColor(ctx.vg, nvgRGBA(0, 0, 0, 140))
    nvgFill(ctx.vg)
end

--- [三队并行] 中缝返回键列表：左页‹（左框柱）/ 详情›（右框柱），两级二级页可同时存在
--- 各占一个框柱位，互不竞争（此前 if/else 单按钮，左右同开时只能活一个）
local function seamBackList()
    local list = {}
    local psL = ctx.logicalH / 1080
    local cs = psL * 0.45                    -- 面板内容缩放(设计→窗口),与 Viewport.DS 一致
    local barW = ctx.logicalH * 0.0888           -- 素材等比(158/1425)×0.8,条中心骑在页面分界线上
    local DIST = 1080                         -- 页面设计宽:滑入全程
    -- 右框柱 ›：角色详情——条整体让出页面:中心在分界线左侧(中缝侧),条右缘贴详情页左缘
    if CharacterDetail.isOpen() then
        local ot, ct, od, cd = CharacterDetail.getSeamAnim()
        local oxWin = DrawUtil.seamSlideX(1, ot, ct, od, cd, DIST) * cs
        list[#list + 1] = {
            cx = (ctx.logicalW - 486 * psL) - barW * 0.5 + oxWin,
            sw = barW, sh = ctx.logicalH, bw = 0, bh = 0, dir = "right",
            close = function() CharacterDetail.close() end,
        }
    end
    -- 左框柱 ‹：左栏二级页（背包/教堂/铁匠/酒馆/市场）——条贴页面右缘(前缘),同步推进
    local leftClose, leftAnim
    if     BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then
        leftClose = function() BackpackPanel.close() end
        leftAnim = { BackpackPanel.getSeamAnim() }
    elseif ChurchPage.isOpen()     then leftClose = function() ChurchPage.close() end
        leftAnim = { ChurchPage.getSeamAnim() }
    elseif BlacksmithPage.isOpen()  then leftClose = function() BlacksmithPage.close() end
        leftAnim = { BlacksmithPage.getSeamAnim() }
    elseif TavernPage.isOpen()      then leftClose = function() TavernPage.close() end
        leftAnim = { TavernPage.getSeamAnim() }
    elseif MarketPage.isOpen()      then leftClose = function() MarketPage.close() end
        leftAnim = { MarketPage.getSeamAnim() }
    end
    if leftClose then
        local oxWin = DrawUtil.seamSlideX(-1, leftAnim[1], leftAnim[2], leftAnim[3], leftAnim[4], DIST) * cs
        list[#list + 1] = {
            cx = 486 * psL + barW * 0.5 + oxWin,
            sw = barW, sh = ctx.logicalH, bw = 0, bh = 0, dir = "left",
            close = leftClose,
        }
    end
    return list
end

function Horizon.render()
    if not ctx.vg then return end
    HorizonUpdateTransform()
    nvgBeginFrame(ctx.vg, ctx.logicalW, ctx.logicalH, ctx.dpr)

    -- 分帧启动中：只画标题，避免未 init 的城镇/战斗模块被绘制
    if not ctx.bootReady then
        nvgBeginPath(ctx.vg)
        nvgRect(ctx.vg, 0, 0, ctx.logicalW, ctx.logicalH)
        nvgFillColor(ctx.vg, nvgRGBA(14, 14, 22, 255))
        nvgFill(ctx.vg)
        if H_SKIP_START and not H_skipDone and StartScreen.isOpen() then
            H_skipDone = true
            StartScreen.skipForReconnect()
            DarkTitleScreen.open()
        end
        if DarkTitleScreen.isOpen() then
            DarkTitleScreen.draw(ctx.vg, ctx.logicalW, ctx.logicalH)
        elseif StartScreen.isOpen() then
            local ss = math.min(ctx.logicalW / 1080, ctx.logicalH / 2400)
            nvgSave(ctx.vg)
            nvgTranslate(ctx.vg, (ctx.logicalW - 1080 * ss) * 0.5, (ctx.logicalH - 2400 * ss) * 0.5)
            nvgScale(ctx.vg, ss, ss)
            StartScreen.draw(ctx.vg)
            nvgRestore(ctx.vg)
        end
        nvgEndFrame(ctx.vg)
        return
    end

    -- 横屏背景：世界大背景图（cover 铺满；战斗页/标题页自带背景会覆盖此处）
    -- [fix] 只尝试一次：缺图时每帧重试会刷屏报错；缺图回退城镇大图，再失败走下方纯色兜底
    --       （不要用 cache:Exists 预判——Web 预览运行时对 pak 资源返回 false，会误伤正常加载）
    if imgWorldBg_ < 0 and not worldBgTried_ then
        worldBgTried_ = true
        imgWorldBg_ = nvgCreateImage(ctx.vg, WORLD_BG_PATH, 0)
        if imgWorldBg_ < 0 then
            print("[Standalone] WARN: world bg missing(" .. WORLD_BG_PATH .. "), fallback -> " .. WORLD_BG_FALLBACK)
            imgWorldBg_ = nvgCreateImage(ctx.vg, WORLD_BG_FALLBACK, 0)
            if imgWorldBg_ < 0 then
                print("[Standalone] WARN: world bg fallback failed, use solid color")
            end
        end
    end
    if imgWorldBg_ >= 0 then
        local iw, ih = nvgImageSize(ctx.vg, imgWorldBg_)
        if iw and iw > 0 then
            local s = math.max(ctx.logicalW / iw, ctx.logicalH / ih)
            local dw, dh = iw * s, ih * s
            local paint = nvgImagePattern(ctx.vg, (ctx.logicalW - dw) * 0.5, (ctx.logicalH - dh) * 0.5, dw, dh, 0, imgWorldBg_, 1.0)
            nvgBeginPath(ctx.vg)
            nvgRect(ctx.vg, 0, 0, ctx.logicalW, ctx.logicalH)
            nvgFillPaint(ctx.vg, paint)
            nvgFill(ctx.vg)
        end
    else
        nvgBeginPath(ctx.vg)
        nvgRect(ctx.vg, 0, 0, ctx.logicalW, ctx.logicalH)
        nvgFillColor(ctx.vg, nvgRGBA(14, 14, 22, 255))
        nvgFill(ctx.vg)
    end

    -- 调试跳过：进主流程
    if H_SKIP_START and not H_skipDone and StartScreen.isOpen() then
        H_skipDone = true
        StartScreen.skipForReconnect()
        DarkTitleScreen.open()  -- [DarkTitleScreen] 竖屏标题被跳过，改以横屏暗黑标题呈现
        if H_AUTO_DISMISS_TITLE and DarkTitleScreen.isReady() then
            DarkTitleScreen.handleTap()  -- 临时验证入口: 无输入环境自动淡出标题
        end
    end

    -- 开始画面：全窗口居中（2400 高画布，适配横屏高度）
    if StartScreen.isOpen() then
        local ss = math.min(ctx.logicalW / 1080, ctx.logicalH / 2400)
        nvgSave(ctx.vg)
        nvgTranslate(ctx.vg, (ctx.logicalW - 1080 * ss) * 0.5, (ctx.logicalH - 2400 * ss) * 0.5)
        nvgScale(ctx.vg, ss, ss)
        StartScreen.draw(ctx.vg)
        nvgRestore(ctx.vg)
        -- [一次性加载] 预载遮罩（开始画面上层）
        if ctx.preload.active then
            ctx.drawPreloadOverlay(ctx.vg, ctx.logicalW, ctx.logicalH)
        end
        nvgEndFrame(ctx.vg)
        return
    end

    -- [三行并行守卫] 三行战斗模式打开时，左右面板由下方 BattleTriPage 分支按
    -- 三行布局重新绘制（viewport 变换不同）；此处跳过，避免右侧「我的冒险家」
    -- 面板与左侧城镇建筑名牌各被绘制两次。
    if not BattleTriPage.isOpen() then
        -- 左面板：功能页组（城镇 + 二级页）
        Viewport.begin(ctx.vg, Viewport.PANELS.left, H_ox, H_oy, H_s)
        TownScene.draw(ctx.vg)
        BlacksmithPage.draw(ctx.vg)
        ChurchPage.draw(ctx.vg)
        TavernPage.draw(ctx.vg)
        MarketPage.draw(ctx.vg)
        BackpackPanel.draw(ctx.vg)
        Viewport.finish(ctx.vg)

        -- 右面板：角色固定（先于中面板绘制，便于弹窗时统一压暗侧栏）
        Viewport.begin(ctx.vg, Viewport.PANELS.right, H_ox, H_oy, H_s)
        CharacterPanel.draw(ctx.vg)
        Viewport.finish(ctx.vg)

        -- [弹窗聚焦] 中面板有模态弹窗时，压暗左右面板（在侧栏之上、中面板之下）
        HorizonDimSidePanels()
    end

    -- 中面板：BottomNav 主视图 + 全屏战斗页
    Viewport.begin(ctx.vg, Viewport.PANELS.center, H_ox, H_oy, H_s)
    local dungeonBattleOpen = DungeonBattleScene.isOpen()
    local towerBattleOpen = TowerBattleScene.isActive()
    if towerBattleOpen then
        -- 通天塔三行攻坚铺满窗口，见 Viewport.finish 之后
    elseif dungeonBattleOpen then
        DungeonBattleScene.draw(ctx.vg)
    else
        local tabIndex = BottomNav.getSelectedIndex()
        if tabIndex == 1 then
            CharacterPanel.draw(ctx.vg)
        elseif tabIndex == 2 then
            -- [底栏移除] 日志页横屏全窗绘制，见 Viewport.finish 之后
        elseif tabIndex == 3 then
            if not BattleTriPage.isOpen() then
                BattleScene.draw(ctx.vg)
            end
            -- [三栏并行] 三栏页打开时中面板留空，全窗绘制见 Viewport.finish 之后
        elseif tabIndex == 5 then
            -- [底栏移除] 副本页横屏全窗绘制，见 Viewport.finish 之后
        else
            TownScene.draw(ctx.vg)
        end
        -- [底栏移除] 三行布局 TopBar 只画左栏；非三行旧布局仍画中栏顶部
        local detailOpen = CharacterPanel.isDetailOpen()
        if not detailOpen and not BattleTriPage.isOpen() then
            TopBar.draw(ctx.vg)
        end
    end
    Viewport.finish(ctx.vg)

    if towerBattleOpen then
        TowerBattleScene.draw(ctx.vg, ctx.logicalW, ctx.logicalH)
        nvgEndFrame(ctx.vg)
        return
    end

    -- [三行并行] 战斗模式布局: 经营(左) | 三行战斗(中段) | 角色(右) 铺满窗口
    if BattleTriPage.isOpen() then
        local ps = ctx.logicalH / 1080                -- 面板缩放（高适配）
        local oxL = 0
        local oxR = ctx.logicalW - 1458 * ps          -- 右面板: ox + 972*ps = 右缘 - 486*ps
        BattleTriPage.drawL1Underlay(ctx.vg, ctx.logicalW, ctx.logicalH)  -- [暗黑替换] L1 行内容背景垫底（框内 clip）
        BattleTriPage.drawL0(ctx.vg, ctx.logicalW, ctx.logicalH)          -- [暗黑替换] L0 框体图（透明框内透出 L1）
        Viewport.begin(ctx.vg, Viewport.PANELS.left, oxL, 0, ps)
        TownScene.draw(ctx.vg)
        BlacksmithPage.draw(ctx.vg)
        ChurchPage.draw(ctx.vg)
        TavernPage.draw(ctx.vg)
        MarketPage.draw(ctx.vg)
        BackpackPanel.draw(ctx.vg)
        -- [三行并行] 头像/金币/宝石 显示到左侧面板（城镇主视图时顶层绘制，优先级高于场景）
        -- oy=-30：头像框/名字组稍上移（点击热区见 MouseButtonUpHorizon left 段 hitTestAvatar -30）
        if not (BlacksmithPage.isOpen() or ChurchPage.isOpen() or TavernPage.isOpen()
            or MarketPage.isOpen()) then
            TopBar.draw(ctx.vg, -30)
        end
        Viewport.finish(ctx.vg)
        Viewport.begin(ctx.vg, Viewport.PANELS.right, oxR, 0, ps)
        CharacterPanel.draw(ctx.vg)
        Viewport.finish(ctx.vg)
        -- 三行战斗内容 + UI 层（窗口坐标; 战斗内容 clip 在各框内矩形）
        BattleTriPage.draw(ctx.vg, ctx.logicalW, ctx.logicalH)
        -- [行1 HUD] 宿主最终层级绘制：速度/扫荡/统计/选关按钮——
        -- 确保位于一切战斗行背景与框柱之上（用户实测按钮被行1背景穿帮）
        BattleTriPage.drawHud(ctx.vg, ctx.logicalW, ctx.logicalH)
        -- [三队并行] 中缝返回条（窗口坐标，页面视口之外）：全高门柱边条，左页‹ / 详情›，两级并存各自绘制
        for _, seamBtn in ipairs(seamBackList()) do
            DrawUtil.drawBackSeamBar(ctx.vg, seamBtn.cx, ctx.logicalH * 0.5,
                seamBtn.sw, seamBtn.sh, seamBtn.dir, seamBtn.bw, seamBtn.bh)
        end
        -- [修复] 玩家信息面板（点头像打开）——横屏此前从未绘制，open 成功但不可见
        if PlayerInfoPanel.isOpen() then
            local fit = math.min(ctx.logicalW / 1080, ctx.logicalH / 2400)
            nvgSave(ctx.vg)
            nvgScissor(ctx.vg, 0, 0, ctx.logicalW, ctx.logicalH)
            nvgTranslate(ctx.vg, (ctx.logicalW - 1080 * fit) * 0.5, (ctx.logicalH - 2400 * fit) * 0.5)
            nvgScale(ctx.vg, fit, fit)
            PlayerInfoPanel.draw(ctx.vg)
            nvgRestore(ctx.vg)
        end
        -- [底栏移除] 日志/副本页全窗竖版模态（盖在三行战斗之上、标题/开场之下）
        HorizonDrawPageModal(ctx.vg)
        -- [DarkTitleScreen] 横屏标题（基屏幕空间，覆盖一切直至点击淡出）
        -- 资源未就绪时标题自带进度条，不允许点进空背景界面
        if DarkTitleScreen.isOpen() then
            DarkTitleScreen.draw(ctx.vg, ctx.logicalW, ctx.logicalH)
        elseif ctx.preload.active then
            ctx.drawPreloadOverlay(ctx.vg, ctx.logicalW, ctx.logicalH)
        end
        -- [LetterIntro] 开场覆盖必须在标题之后，否则信件被大门挡住且点击被吞
        HorizonDrawIntroOverlay()
        nvgEndFrame(ctx.vg)
        return
    end

    -- 全局弹窗层（模态，绘制于中面板空间，坐标与原竖屏逻辑一致）
    Viewport.begin(ctx.vg, Viewport.PANELS.center, H_ox, H_oy, H_s)
    HeroRosterPanel.draw(ctx.vg)
    PlayerInfoPanel.draw(ctx.vg)
    LootBox.drawPage(ctx.vg)
    RewardPopup.draw(ctx.vg)
    OfflineRewardPanel.draw(ctx.vg)
    SpinePowerUpEffect.draw(ctx.vg)
    LevelUpPopup.draw(ctx.vg)
    Viewport.finish(ctx.vg)

    -- [暗黑化 P0] 图标画廊验收页（基屏幕空间全窗口适配，便于验收；通过后置 SHOWCASE=false）
    if DarkIcon.SHOWCASE then
        nvgSave(ctx.vg)
        nvgScissor(ctx.vg, 0, 0, ctx.logicalW, ctx.logicalH)  -- 重置面板 intersect 裁剪
        local ss = math.min(ctx.logicalW / 1080, ctx.logicalH / 2400)
        nvgTranslate(ctx.vg, (ctx.logicalW - 1080 * ss) * 0.5, (ctx.logicalH - 2400 * ss) * 0.5)
        nvgScale(ctx.vg, ss, ss)
        DarkIcon.drawShowcase(ctx.vg)
        nvgRestore(ctx.vg)
    end

    -- [修复] 玩家信息面板（非三行横屏路径同样漏画）
    if PlayerInfoPanel.isOpen() then
        local fit = math.min(ctx.logicalW / 1080, ctx.logicalH / 2400)
        nvgSave(ctx.vg)
        nvgScissor(ctx.vg, 0, 0, ctx.logicalW, ctx.logicalH)
        nvgTranslate(ctx.vg, (ctx.logicalW - 1080 * fit) * 0.5, (ctx.logicalH - 2400 * fit) * 0.5)
        nvgScale(ctx.vg, fit, fit)
        PlayerInfoPanel.draw(ctx.vg)
        nvgRestore(ctx.vg)
    end
    -- [底栏移除] 日志/副本页全窗竖版模态
    HorizonDrawPageModal(ctx.vg)
    -- [DarkTitleScreen] 横屏标题（基屏幕空间，覆盖一切直至点击淡出）
    if DarkTitleScreen.isOpen() then
        DarkTitleScreen.draw(ctx.vg, ctx.logicalW, ctx.logicalH)
    elseif ctx.preload.active then
        ctx.drawPreloadOverlay(ctx.vg, ctx.logicalW, ctx.logicalH)
    end
    -- [LetterIntro] 开场覆盖必须在标题之后（非三行路径同样需要）
    HorizonDrawIntroOverlay()

    nvgEndFrame(ctx.vg)
end

-- [底栏移除] 横屏日志(2)/副本(5)页全窗竖版模态是否激活（全屏弹窗打开时让位）
local function HorizonPageModalActive()
    local tabIndex = BottomNav.getSelectedIndex()
    if tabIndex ~= 2 and tabIndex ~= 5 then return false end
    if DungeonBattleScene.isOpen() or TowerBattleScene.isActive() then return false end
    if PlayerInfoPanel.isOpen() or LevelUpPopup.isOpen()
        or OfflineRewardPanel.isOpen() or RewardPopup.isOpen() or LootBox.isPageOpen() then
        return false
    end
    return true
end

--- 玩家信息面板横屏 letterbox：窗口坐标 → 1080×2400 设计坐标
local function playerInfoDesignCoords(sx, sy)
    local fit = math.min(ctx.logicalW / 1080, ctx.logicalH / 2400)
    return (sx - (ctx.logicalW - 1080 * fit) * 0.5) / fit,
           (sy - (ctx.logicalH - 2400 * fit) * 0.5) / fit
end

-- 事件坐标 -> 面板命中；全局模态返回 ('modal', dx, dy)
local function HorizonResolveMouse()
    local mousePos = input:GetMousePosition()
    local sx = mousePos.x / ctx.dpr
    local sy = mousePos.y / ctx.dpr
    -- 玩家信息是全窗 letterbox，不能走左/中/右栏换算，否则点面板中部会被当成点外面
    if PlayerInfoPanel.isOpen() then
        local pdx, pdy = playerInfoDesignCoords(sx, sy)
        return 'playerinfo', pdx, pdy
    end
    -- [底栏移除] 横屏日志(2)/副本(5)页全窗竖版模态：中段命中映射到设计坐标；
    -- 左右栏让出（TopBar 页签/角色面板仍可点），全屏弹窗打开时让位
    if HorizonPageModalActive() then
        local ps = ctx.logicalH / 1080
        local leftW = 486 * ps
        if sx >= leftW and sx <= ctx.logicalW - leftW then
            local fit = math.min(ctx.logicalW / ctx.DESIGN_W, ctx.logicalH / ctx.DESIGN_H)
            return 'modal', (sx - (ctx.logicalW - ctx.DESIGN_W * fit) * 0.5) / fit,
                            (sy - (ctx.logicalH - ctx.DESIGN_H * fit) * 0.5) / fit
        end
    end
    -- [三行并行] 战斗模式命中: 面板按战斗布局定位，中段为三行战斗区
    if BattleTriPage.isOpen() then
        -- [全窗模态] 选关/扫荡/统计弹窗打开时，全窗口点击直通三行页弹窗层（含左右面板区）
        if SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen() then
            return 'tri', sx, sy
        end
        local ps = ctx.logicalH / 1080
        local leftW = 486 * ps
        if sx < leftW then
            return 'left', sx / (ps * 0.45), sy / (ps * 0.45)
        elseif sx > ctx.logicalW - leftW then
            return 'right', (sx - (ctx.logicalW - 486 * ps)) / (ps * 0.45), sy / (ps * 0.45)
        end
        return 'tri', sx, sy
    end
    if TowerBattleScene.isActive() then
        return 'modal', sx, sy
    end
    local pid, dx, dy = Viewport.hit(sx, sy, H_ox, H_oy, H_s)
    if StartScreen.isOpen() and not H_SKIP_START then return 'none', dx, dy end
    if DungeonBattleScene.isOpen()
        or LevelUpPopup.isOpen() or PlayerInfoPanel.isOpen()
        or OfflineRewardPanel.isOpen() or RewardPopup.isOpen()
        or LootBox.isPageOpen() or LootBox.handleDragBegin == nil then
        return 'modal', dx or 0, dy or 0
    end
    if not pid then return 'none', 0, 0 end
    H_lastPanel = pid
    return pid, dx, dy
end

function Horizon.mouseDown(eventType, eventData)
    if not ctx.bootReady then return end
    -- [DarkTitleScreen] 标题期吞掉按下（继续由 ButtonUp 触发）
    if DarkTitleScreen.isOpen() then return end
    -- [LetterIntro] 开场期也要记 pressValid，否则抬起被当成无效点击
    if LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive() then
        pressValid = true
        pressStartDX, pressStartDY = 0, 0
        return
    end
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local pid, dx, dy = HorizonResolveMouse()
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
        BattleTriPage.handleDragBegin(dx, dy)
        return
    end
    pressStartDX, pressStartDY = dx or 0, dy or 0
    pressValid = (pid ~= 'none')
    if pid == 'modal' and HorizonPageModalActive() then
        -- [底栏移除] 日志页全窗模态：拖拽起点（列表滚动）
        if BottomNav.getSelectedIndex() == 2 then
            DiaryPage.handleDragBegin(dx, dy)
        end
        return
    end
    if pid == 'none' then return end
    if pid == 'left' then
        if BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then BackpackPanel.handleDragBegin(dx, dy) return end
        if BlacksmithPage.isOpen() then BlacksmithPage.handleDragBegin(dx, dy) return end
        if ChurchPage.isOpen() then ChurchPage.handleDragBegin(dx, dy) return end
        if TavernPage.isOpen() then TavernPage.handleDragBegin(dx, dy) return end
        if MarketPage.isOpen() then MarketPage.handleDragBegin(dx, dy) return end
    elseif pid == 'center' then
        if BottomNav.getSelectedIndex() == 1 then CharacterPanel.handleDragBegin(dx, dy) end
    elseif pid == 'right' then
        CharacterPanel.handleDragBegin(dx, dy)
    end
end

function Horizon.mouseMove(eventType, eventData)
    if DarkTitleScreen.isOpen() then return end
    if LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive() then return end
    local pid, dx, dy = HorizonResolveMouse()
    if pid == 'none' then return end
    if pid == 'playerinfo' then
        PlayerInfoPanel.handleDragMove(dx, dy)
        return
    end
    if pid == 'modal' and HorizonPageModalActive() then
        -- [底栏移除] 日志页全窗模态：拖拽滚动
        if BottomNav.getSelectedIndex() == 2 then
            DiaryPage.handleDragMove(dx, dy)
        end
        return
    end
    if pid == 'modal' then
        if DungeonBattleScene.isOpen() then DungeonBattleScene.handleDragMove(dx, dy) return end
        if LevelUpPopup.isOpen() then return end
        if PlayerInfoPanel.isOpen() then PlayerInfoPanel.handleDragMove(dx, dy) return end
        if OfflineRewardPanel.isOpen() then OfflineRewardPanel.handleDragMove(dx, dy) return end
        if RewardPopup.handleDragMove(dx, dy) then return end
        if LootBox.handleDragMove(dx, dy) then return end
        return
    end
    if not pressValid then return end
    if pid == 'tri' then
        BattleTriPage.handleDragMove(dx, dy)
        return
    end
    if pid == 'left' then
        if BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then BackpackPanel.handleDragMove(dx, dy) return end
        if BlacksmithPage.isOpen() then BlacksmithPage.handleDragMove(dx, dy) return end
        if ChurchPage.isOpen() then ChurchPage.handleDragMove(dx, dy) return end
        if TavernPage.isOpen() then TavernPage.handleDragMove(dx, dy) return end
        if MarketPage.isOpen() then MarketPage.handleDragMove(dx, dy) return end
    elseif pid == 'center' then
        if BottomNav.getSelectedIndex() == 1 then CharacterPanel.handleDragMove(dx, dy) end
    elseif pid == 'right' then
        CharacterPanel.handleDragMove(dx, dy)
    end
end

function Horizon.mouseUp(eventType, eventData)
    if not ctx.bootReady then return end
    -- [DarkTitleScreen] 标题期任意释放 = 点击继续
    if DarkTitleScreen.isOpen() then DarkTitleScreen.handleTap() return end
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local pid, dx, dy = HorizonResolveMouse()
    local isTap = false
    if pressValid then
        local dist = math.abs(dx - pressStartDX) + math.abs(dy - pressStartDY)
        isTap = dist < TAP_THRESHOLD
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
    -- [LetterIntro] 开场链输入：信件任意释放即翻段（不依赖 isTap，避免 pressValid 丢失）
    if LetterIntro.isOpen() then
        LetterIntro.handleTap()
        return
    end
    if IntroCutscene.isActive() then
        return
    end
    if ScenarioDialogue.isActive() then
        if isTap then ScenarioDialogue.advance() end
        return
    end
    if pid == 'none' then return end
    -- [三队并行] 中缝返回键优先命中（条贴页面运动前缘,可能落在 tri 缝隙也可能落在面板区内;左右两级各自独立命中）
    -- ⚠️ 必须在 backpack 分支之前：返回条骑在左栏右缘，属背包矩形内，晚判会被背包吞掉
    for _, seamBtn in ipairs(seamBackList()) do
        if math.abs(dx - seamBtn.cx) <= seamBtn.sw * 0.5
            and math.abs(dy - ctx.logicalH * 0.5) <= seamBtn.sh * 0.5 then
            if isTap then seamBtn.close() end
            return
        end
    end
    if pid == 'tri' then
        BattleTriPage.handleDragEnd(dx, dy)
        if isTap then BattleTriPage.handleInput(dx, dy) end
        return
    end
    if pid == 'modal' then
        -- [底栏移除] 日志/副本页全窗模态点击（设计坐标）
        if HorizonPageModalActive() then
            local tab = BottomNav.getSelectedIndex()
            if tab == 2 then
                DiaryPage.handleDragEnd(dx, dy)
                if isTap then DiaryPage.handleInput(dx, dy) end
            elseif tab == 5 then
                if isTap then DungeonPage.handleInput(dx, dy) end
            end
            return
        end
        if TowerBattleScene.isActive() then
            if isTap then TowerBattleScene.handleClick(dx, dy, ctx.logicalW, ctx.logicalH) end
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
        if LootBox.isPageOpen() then
            LootBox.handleDragEnd(dx, dy)
            if isTap then LootBox.handleInput(dx, dy) end
            return
        end
        return
    end
    -- 左面板：功能页组点击链
    if pid == 'left' then
        -- [三行并行] 头像热区（TopBar 绘制在左面板时 oy=-30，热区同步）：仅城镇主视图（无二级页）时
        if isTap and not (BackpackPanel.isOpen() or BlacksmithPage.isOpen() or ChurchPage.isOpen()
            or TavernPage.isOpen() or MarketPage.isOpen()) then
            if TopBar.hitTestAvatar(dx, dy, -30) then
                PlayerInfoPanel.open()
                return
            end
            -- [底栏移除] 页面入口在 TopBar（812ddc7）：左栏链补接其输入
            if TopBar.handleInput(dx, dy, -30) then
                return
            end
        end
        -- [仓库入口] 背包左栏页（与黑市/教堂同链）
        if BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then
            BackpackPanel.handleDragEnd(dx, dy)
            if not isTap then return end
            BackpackPanel.handleInput(dx, dy)
            return
        end
        if BlacksmithPage.isOpen() then
            BlacksmithPage.handleDragEnd(dx, dy)
            if not isTap then return end
            BlacksmithPage.handleInput(dx, dy)
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

function Horizon.touchBegin(eventType, eventData)
    Horizon.mouseDown(eventType, eventData)
end

function Horizon.touchEnd(eventType, eventData)
    Horizon.mouseUp(eventType, eventData)
end

function Horizon.touchMove(eventType, eventData)
    Horizon.mouseMove(eventType, eventData)
end

function Horizon.mouseWheel(eventType, eventData)
    -- [DarkTitleScreen] 标题期吞掉滚轮
    if DarkTitleScreen.isOpen() then return end
    if LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive() then return end
    local wheel = eventData["Wheel"]:GetInt()

    -- [三行并行] 装备袋战斗区覆盖层优先（全屏级）
    if BattleTriPage.handleScroll(wheel) then return end

    -- 全屏战斗场景
    if DungeonBattleScene.isOpen() then DungeonBattleScene.handleScroll(wheel) return end
    -- 全屏弹窗
    if LevelUpPopup.isOpen() then return end
    if OfflineRewardPanel.isOpen() then OfflineRewardPanel.handleScroll(wheel) return end
    if RewardPopup.isOpen() then RewardPopup.handleScroll(wheel) return end
    if LootBox.isPageOpen() then LootBox.handleScroll(wheel) return end

    -- [按鼠标位置路由] 滚轮作用于鼠标所在的面板（左右面板可同开二级页，
    -- 不再依赖"最近点击面板"记录；滚到哪边就滚哪边的列表）
    local pid = select(1, HorizonResolveMouse())
    if pid == 'playerinfo' then
        PlayerInfoPanel.handleScroll(wheel)
        return
    end

    -- [底栏移除] 日志页全窗模态：列表滚动
    if pid == 'modal' and HorizonPageModalActive() then
        if BottomNav.getSelectedIndex() == 2 then DiaryPage.handleScroll(wheel) end
        return
    end

    if pid == 'modal' then
        PlayerInfoPanel.handleScroll(wheel)
        return
    end

    if pid == 'left' then
        if BackpackPanel.isOpen() and BackpackPanel.isLeftMode() then BackpackPanel.handleScroll(wheel) return end
        if BlacksmithPage.isOpen() then BlacksmithPage.handleScroll(wheel) return end
        if ChurchPage.isOpen() then ChurchPage.handleScroll(wheel) return end
        if TavernPage.isOpen() then TavernPage.handleScroll(wheel) return end
        if MarketPage.isOpen() then MarketPage.handleScroll(wheel) return end
        return
    end

    if pid == 'right' then
        CharacterPanel.handleScroll(wheel)
        return
    end

    if pid == 'tri' then return end  -- 三行战斗区无滚动内容（选关/扫荡为翻页按钮）

    -- center：主视图 Tab 页
    local tab = BottomNav.getSelectedIndex()
    if tab == 1 then
        CharacterPanel.handleScroll(wheel)
    elseif tab == 2 then
        DiaryPage.handleScroll(wheel)
    end
end


return Horizon
