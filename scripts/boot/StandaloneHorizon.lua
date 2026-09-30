-- ============================================================================
-- StandaloneHorizon - 横屏多面板绘制与输入（原 Standalone.lua 后半段）
-- 共享运行时见 boot.StandaloneRT
-- ============================================================================

local Viewport = require("core.Viewport")
local drawEquipDetailOverlay
local equipOverlayDesign
local RT = require("boot.StandaloneRT")

local TopBar            = require("ui.hud.TopBar")
local BottomNav         = require("ui.hud.BottomNav")
local BattleScene       = require("ui.battle.scene.BattleScene")
local CharacterPanel    = require("ui.character.panel.CharacterPanel")
local DebugPanel        = require("ui.dev.DebugPanel")
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
local PlayerInfoPanel   = require("ui.hud.popup.PlayerInfoPanel")
local StartScreen       = require("ui.story.gate.StartScreen")
local DarkTitleScreen   = require("ui.story.gate.DarkTitleScreenGate")
local BattleTriPage     = require("ui.battle.tri.BattleTriPage")
local SweepDialog       = require("ui.battle.stage.SweepDialog")
local DamageStatsPanel  = require("ui.battle.popup.DamageStatsPanel")
local StageSelectDialog = require("ui.battle.stage.StageSelectDialog")
local BattleLayout      = require("core.BattleLayout")
local ProjectileSystem  = require("ui.battle.combat.ProjectileSystem")
local BattleEffects     = require("ui.battle.combat.BattleEffects")
local SpinePowerUpEffect = require("ui.fx.SpinePowerUpEffect")
local IntroCutscene      = require("ui.story.gate.IntroCutscene")
local LetterIntro        = require("ui.story.gate.LetterIntro")
local CharacterDetail    = require("ui.character.detail.CharacterDetail")
local EquipmentBag       = require("ui.character.equip.EquipmentBag")
local EquipCrossDrag     = require("ui.character.EquipCrossDrag")
local ScenarioDialogue   = require("ui.story.ScenarioDialogue")
local TutorialManager    = require("systems.TutorialManager")  -- [横屏接线 0928] 新手引导
local DrawUtil           = require("core.DrawUtil")
local DarkIcon           = require("core.DarkIcon")
local UiToast            = require("core.UiToast")
local KeyboardShortcuts  = require("ui.dev.KeyboardShortcuts")

local function vg() return RT.vg end
local function logicalW() return RT.logicalW or 0 end
local function logicalH() return RT.logicalH or 0 end
local function windowW() return RT.windowW or logicalW() end
local function windowH() return RT.windowH or logicalH() end

local function applyFrame()
    nvgTranslate(vg(), RT.frameOx or 0, RT.frameOy or 0)
    local frameScale = RT.frameScale or 1
    if frameScale <= 0 then frameScale = 1 end
    nvgScale(vg(), frameScale, frameScale)
end

--- CE 面板画在帧变换后的逻辑坐标里，避免被面板 viewport 带走。
--- 归属战斗行的奖励弹窗（row=1）在离开三行战斗页时会失去唯一绘制路径
--- （drawRegion 只在 BattleTriPage.draw 内调用）。这里在收尾统一兜底绘制，
--- 避免「弹窗 open 了但看不见」。三行页打开时由 drawRegion 负责，不重复画。
local function drawOrphanRowReward()
    if not RewardPopup.isOpen() or not RewardPopup.currentRowTag() then return end
    if BattleTriPage.isOpen() then return end
    local fit = math.min(logicalW() / 1080, logicalH() / 2400)
    nvgSave(vg())
    nvgResetScissor(vg())
    nvgScissor(vg(), 0, 0, logicalW(), logicalH())
    nvgTranslate(vg(), (logicalW() - 1080 * fit) * 0.5, (logicalH() - 2400 * fit) * 0.5)
    nvgScale(vg(), fit, fit)
    RewardPopup.drawRegion(vg(), 0, 0, 1080, 2400, RewardPopup.currentRowTag())
    nvgRestore(vg())
end

--- [三面板] 在指定面板视口内绘制归属该面板的奖励弹窗（须在 Viewport.begin/finish 之间调用）
local function drawRewardInPanel(pid)
    if not pid then return end
    if not (RewardPopup.isOpen() and not RewardPopup.currentRowTag()) then return end
    if RewardPopup.currentPanel() ~= pid then return end
    -- 三行模式的中栏不走 Viewport：直接全窗 letterbox 居中绘制
    if pid == 'center' and BattleTriPage.isOpen() then
        local fit = math.min(logicalW() / 1080, logicalH() / 2400)
        nvgSave(vg())
        nvgScissor(vg(), 0, 0, logicalW(), logicalH())
        nvgTranslate(vg(), (logicalW() - 1080 * fit) * 0.5, (logicalH() - 2400 * fit) * 0.5)
        nvgScale(vg(), fit, fit)
        RewardPopup.draw(vg())
        nvgRestore(vg())
        return
    end
    RewardPopup.drawRegion(vg(), 0, 0, 1080, 2400, nil)
end

local function finishFrame()
    nvgSave(vg())
    nvgResetTransform(vg())
    applyFrame()
    nvgResetScissor(vg())
    nvgScissor(vg(), 0, 0, logicalW(), logicalH())
    drawOrphanRowReward()
    CEPanel.draw(vg(), logicalW(), logicalH())
    nvgRestore(vg())
    nvgEndFrame(vg())
end

local function toDesign(sx, sy)
    local frameScale = RT.frameScale or 1
    if frameScale <= 0 then frameScale = 1 end
    return (sx - (RT.frameOx or 0)) / frameScale, (sy - (RT.frameOy or 0)) / frameScale
end

local function talentPageUsesWideLayout()
    return TalentPage.isOpen() and TalentPage.getHorizonWidthScale() > 1.001
end

local function syncTalentPageLayout()
    if talentPageUsesWideLayout() then
        TalentPage.applyHorizonLayout()
    else
        TalentPage.resetHorizonLayout()
    end
end

--- 古树加宽后的窗口右缘（含滑入偏移）。ox 为左栏窗口原点。
local function talentPageRightEdge(ox, ps)
    syncTalentPageLayout()
    local scale = TalentPage.getHorizonWidthScale()
    local cs = ps * Viewport.DS
    local dist = 1080 * scale
    local ot, ct, od, cd = TalentPage.getSeamAnim()
    local oxDesign = DrawUtil.seamSlideX(-1, ot, ct, od, cd, dist)
    return ox + (dist + oxDesign) * cs, cs, dist, oxDesign
end

local function drawWideTalentPage(ox, oy, ps)
    if not talentPageUsesWideLayout() then return end
    syncTalentPageLayout()
    local scale = TalentPage.getHorizonWidthScale()
    local cs = ps * Viewport.DS
    nvgSave(vg())
    nvgResetScissor(vg())
    nvgScissor(vg(), ox, oy, 1080 * scale * cs, 2400 * cs)
    nvgTranslate(vg(), ox, oy)
    nvgScale(vg(), cs, cs)
    TalentPage.draw(vg())
    nvgRestore(vg())
end
local function dpr() return RT.dpr or 1 end
local function DESIGN_W() return RT.DESIGN_W or 1080 end
local function DESIGN_H() return RT.DESIGN_H or 2400 end
local function bootReady_() return RT.bootReady_ end

local TAP_THRESHOLD = 15
local MIN_TAP_INTERVAL = 0.12
local lastTapTime = 0
local pressStartDX = 0
local pressStartDY = 0
local pressValid = false
-- 遗匣按压由左栏捕获；移出左栏后不再把同次拖拽转交右栏/战斗。
local lootPress = false

-- ============================================================================
-- 横屏 PC 多面板模式（changeForJourney）
-- 左面板：功能页组（城镇 + 铁匠/酒馆/竞技场/市场）
-- 中面板：BottomNav 主视图（角色/日志/战斗）+ 全屏战斗页 + 全局弹窗层
-- 右面板：角色固定
-- 一期限制：弹窗为模态（绘制于中面板空间）；同一页面只在一个面板
-- ============================================================================
H_SKIP_START = false  -- 240db7b 打开调试跳过后会和暗黑标题互相卡住，表现为黑屏
H_skipDone = false
H_AUTO_DISMISS_TITLE = false  -- DarkTitleScreen 验收已通过：关闭无输入环境自动淡出钩子
-- 截图验收钩子默认值（由外部 _validate_entry.lua 运行时覆写；此处定义避免 LSP 未定义全局）
H_AUTO_TAB = false
H_AUTO_OPEN_PANEL = false
H_ox, H_oy, H_s = 0, 0, 1
H_lastPanel = 'center'
H_focusPanel = 'center'  -- 当前焦点面板（left/center/right），奖励弹窗 show 时记录触发面板
H_lastTopBarPower = nil  -- [三队并行] TopBar 战力逐帧比对缓存
H_SEAM_BACK = false      -- [三队并行] 三行模式=true：返回键由中缝层绘制，页面内不画

local function HorizonUpdateTransform()
    H_ox, H_oy, H_s = Viewport.layout(logicalW(), logicalH())
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

-- [底栏移除] 横屏副本(5)页：竖版设计全窗等比铺（模态层）
-- 全屏弹窗/战斗覆盖打开时不画（它们自带层级与让位逻辑）
local function HorizonDrawPageModal(_unused_vg)
    if BottomNav.getSelectedIndex() ~= 5 then return end
    if DungeonBattleScene.isOpen() or TowerBattleScene.isActive() then return end
    local fit = math.min(logicalW() / DESIGN_W(), logicalH() / DESIGN_H())
    local ox = (logicalW() - DESIGN_W() * fit) * 0.5
    local oy = (logicalH() - DESIGN_H() * fit) * 0.5
    nvgSave(vg())
    nvgScissor(vg(), 0, 0, logicalW(), logicalH())
    nvgBeginPath(vg())
    nvgRect(vg(), 0, 0, logicalW(), logicalH())
    nvgFillColor(vg(), nvgRGBA(8, 8, 10, 235))
    nvgFill(vg())
    nvgScissor(vg(), ox, oy, DESIGN_W() * fit, DESIGN_H() * fit)
    nvgTranslate(vg(), ox, oy)
    nvgScale(vg(), fit, fit)
    DungeonPage.draw(vg())
    nvgRestore(vg())
end

--- [LetterIntro] 开场链全窗口覆盖：信件与情景都用逻辑分辨率横屏绘制；旧过场用 cover 裁切避免竖条
local function HorizonDrawIntroOverlay()
    if not (LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive()) then
        return
    end
    nvgSave(vg())
    nvgResetTransform(vg())
    applyFrame()
    nvgScissor(vg(), 0, 0, logicalW(), logicalH())
    if LetterIntro.isOpen() then
        ---@diagnostic disable-next-line: missing-parameter
        LetterIntro.draw(vg(), logicalW(), logicalH())
    elseif ScenarioDialogue.isActive() then
        ScenarioDialogue.draw(logicalW(), logicalH())
    elseif IntroCutscene.isActive() then
        local lw, lh = logicalW(), logicalH()
        local ss = math.max(lw / 1080, lh / 2400)
        nvgTranslate(vg(), (lw - 1080 * ss) * 0.5, (lh - 2400 * ss) * 0.5)
        nvgScale(vg(), ss, ss)
        IntroCutscene.draw(vg())
    end
    nvgRestore(vg())
end

--- [横屏接线 0928] 新手引导蒙层：按当前高亮热点所属面板的 Viewport 变换绘制，
--- 热点 design 坐标即与该面板内容精确对齐（'modal' 上下文走全窗 letterbox，同副本页模态）
local function HorizonDrawTutorialOverlay()
    if not TutorialManager.isActive() then return end
    if ScenarioDialogue.isActive() or LetterIntro.isOpen() or IntroCutscene.isActive() then return end
    if DarkTitleScreen.isOpen() then return end
    -- 全屏战斗期间不绘制（与旧 ClientRender 的 towerBattleOpen 守卫一致）
    if DungeonBattleScene.isOpen() or TowerBattleScene.isActive() then return end
    local panel = TutorialManager.getHotspotPanel()
    nvgSave(vg())
    nvgResetTransform(vg())
    applyFrame()
    local function drawLetterboxed()
        local fit = math.min(logicalW() / DESIGN_W(), logicalH() / DESIGN_H())
        nvgScissor(vg(), 0, 0, logicalW(), logicalH())
        nvgTranslate(vg(), (logicalW() - DESIGN_W() * fit) * 0.5, (logicalH() - DESIGN_H() * fit) * 0.5)
        nvgScale(vg(), fit, fit)
        TutorialManager.draw()
    end
    if panel == 'modal' then
        drawLetterboxed()
    elseif Viewport.beginFromNote(vg(), panel) then
        -- 蒙层矩形精确等于面板区域不会溢出；解除面板裁剪让高亮/气泡可越出栏外
        -- （装备详情 compactCorner 浮层画在栏外，其按钮高亮须同样不被裁切）
        nvgResetScissor(vg())
        TutorialManager.draw()
        Viewport.finish(vg())
    else
        -- 面板无 note（如 tri 三行模式下的 center）：回退全窗 letterbox，
        -- 保证 invisible 步骤的跳过按钮始终可见可点（防卡死）
        drawLetterboxed()
    end
    nvgRestore(vg())
end

--- [弹窗聚焦] 中面板有模态弹窗时，压暗左右面板（基屏幕空间，绘制于侧栏之后、中面板之前）
local function HorizonDimSidePanels()
    local modalOpen =
        HeroRosterPanel.isVisible() or PlayerInfoPanel.isOpen() or
        RewardPopup.isOpen() or
        OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen() or
        SpinePowerUpEffect.isPlaying() or IntroCutscene.isActive()
    if not modalOpen then return end

    local w = Viewport.PW * H_s
    local h = Viewport.PH * H_s
    nvgBeginPath(vg())
    nvgRect(vg(), H_ox, H_oy, w, h)
    nvgRect(vg(), H_ox + Viewport.PANELS.right.bx * H_s, H_oy, w, h)
    nvgFillColor(vg(), nvgRGBA(0, 0, 0, 140))
    nvgFill(vg())
end

--- [三队并行] 中缝返回键列表：左页‹（左框柱）/ 详情›（右框柱），两级二级页可同时存在
--- 各占一个框柱位，互不竞争（此前 if/else 单按钮，左右同开时只能活一个）
--- [锻炉双页 0929] 锻炉页移中栏：其返回条挂在锻炉右缘（中栏右分界线），三行/非三行都绘制
local function seamBackList()
    local list = {}
    local tri = BattleTriPage.isOpen()
    local psL = logicalH() / 1080
    local cs = psL * 0.45                    -- 面板内容缩放(设计→窗口),与 Viewport.DS 一致
    local barW = logicalH() * DrawUtil.SEAMBAR_ASPECT  -- 素材实际等比,与绘制共用;条中心骑在页面分界线上
    local DIST = 1080                         -- 页面设计宽:滑入全程

    if tri then
        -- 右框柱 ›：角色详情——条整体让出页面:中心在分界线左侧(中缝侧),条右缘贴详情页左缘
        if CharacterDetail.isOpen() then
            local ot, ct, od, cd = CharacterDetail.getSeamAnim()
            local oxWin = DrawUtil.seamSlideX(1, ot, ct, od, cd, DIST) * cs
            list[#list + 1] = {
                cx = (logicalW() - 486 * psL) - barW * 0.5 + oxWin,
                sw = barW, sh = logicalH(), bw = 0, bh = 0, dir = "right",
                close = function() CharacterDetail.close() end,
            }
        end
    end

    -- [双页方向 0930] 锻炉返回条 ‹：双页(仓库+锻炉)都属左栏组，返回方向反转——
    -- 条仍挂锻炉前缘(中/右栏分界线)，但箭头朝左、随页面向左滑出；点击关闭锻炉（联动关仓库）。
    -- 三行与非三行都绘制（锻炉页内不再画返回键）
    if BlacksmithPage.isOpen() then
        local ot, ct, od, cd = BlacksmithPage.getSeamAnim()
        local oxWin = DrawUtil.seamSlideX(-1, ot, ct, od, cd, DIST) * cs
        -- 中/右栏分界线窗口坐标：三行 = 972*ps；非三行 = H_ox + 972*H_s
        local seamX = tri and (972 * psL) or (H_ox + 972 * H_s)
        list[#list + 1] = {
            cx = seamX + barW * 0.5 + oxWin,
            sw = barW, sh = logicalH(), bw = 0, bh = 0, dir = "left",
            close = function() BlacksmithPage.close() end,
        }
    end

    -- 左框柱 ‹：左栏二级页（仓库/教堂/酒馆/市场）——条贴页面右缘(前缘),同步推进
    -- [锻炉双页 0929] 锻炉打开时仓库左栏条不画（双页整体由锻炉右侧竖栏一键关闭）
    if tri then
        local leftClose, leftAnim, leftScale
        if LootBoxPage.isOpen() then
            leftClose = function() LootBoxPage.close() end
            leftAnim = { LootBoxPage.getSeamAnim() }
        elseif TaskPage.isOpen() then
            leftClose = function() TaskPage.close() end
            leftAnim = { TaskPage.getSeamAnim() }
        elseif BackpackPanel.isOpen() and BackpackPanel.isLeftMode()
            and not BlacksmithPage.isOpen() then
            leftClose = function() BackpackPanel.close() end
            leftAnim = { BackpackPanel.getSeamAnim() }
        elseif TalentPage.isOpen()     then leftClose = function() TalentPage.close() end
            leftAnim = { TalentPage.getSeamAnim() }
            leftScale = TalentPage.getHorizonWidthScale()
        elseif ChurchPage.isOpen()     then leftClose = function() ChurchPage.close() end
            leftAnim = { ChurchPage.getSeamAnim() }
        elseif TavernPage.isOpen()      then leftClose = function() TavernPage.close() end
            leftAnim = { TavernPage.getSeamAnim() }
        elseif MarketPage.isOpen()      then leftClose = function() MarketPage.close() end
            leftAnim = { MarketPage.getSeamAnim() }
        end
        if leftClose then
            local scale = leftScale or 1
            if scale < 1 then scale = 1 end
            local dist = 1080 * scale
            local oxWin = DrawUtil.seamSlideX(-1, leftAnim[1], leftAnim[2], leftAnim[3], leftAnim[4], dist) * cs
            -- 左面板右缘窗口坐标：三行 = 486*ps*scale；非三行 = H_ox + 486*H_s*scale
            local leftEdge = tri and (486 * psL * scale) or (H_ox + 486 * H_s * scale)
            list[#list + 1] = {
                cx = leftEdge + barW * 0.5 + oxWin,
                sw = barW, sh = logicalH(), bw = 0, bh = 0, dir = "left",
                close = leftClose,
            }
        end
    end
    return list
end

--- 中缝返回条命中。必须用逻辑坐标（toDesign 之后），不能用窗口像素直接比。
---@param sx number
---@param sy number
---@return table|nil
local function seamHitAt(sx, sy)
    for _, seamBtn in ipairs(seamBackList()) do
        local arrowY = seamBtn.sh * DrawUtil.SEAMBAR_ARROW_Y
        local arrowH = seamBtn.sh * 0.16
        if math.abs(sx - seamBtn.cx) <= seamBtn.sw * 0.5
            and math.abs(sy - arrowY) <= arrowH * 0.5 then
            return seamBtn
        end
    end
    return nil
end

drawEquipDetailOverlay = function()
    -- 配装详情画在栏外，不被左右栏裁切
    local ok, EquipmentDetail = pcall(require, "ui.character.equip.EquipmentDetail")
    if not ok or not EquipmentDetail.isCompactCorner or not EquipmentDetail.isCompactCorner() then return end
    local owner = EquipmentDetail.getOwner and EquipmentDetail.getOwner() or "character"
    -- [锻炉双页 0929] smith owner（锻炉工作台详情）挂中栏；其余非 character 挂左栏
    local panelId = (owner == "character") and "right"
        or (owner == "smith") and "center" or "left"
    local note = Viewport.getNote(panelId)
    if not note then return end
    local panel = Viewport.PANELS[panelId]
    nvgSave(vg())
    nvgResetScissor(vg())
    nvgTranslate(vg(), note.ox + panel.bx * note.s, note.oy + panel.by * note.s)
    nvgScale(vg(), note.s * Viewport.DS, note.s * Viewport.DS)
    EquipmentDetail.draw(vg())
    nvgRestore(vg())
end

equipOverlayDesign = function(sx, sy)
    local ok, EquipmentDetail = pcall(require, "ui.character.equip.EquipmentDetail")
    if not ok or not EquipmentDetail.isCompactCorner or not EquipmentDetail.isCompactCorner() then return nil end
    local owner = EquipmentDetail.getOwner and EquipmentDetail.getOwner() or "character"
    -- [锻炉双页 0929] smith owner（锻炉工作台详情）挂中栏；其余非 character 挂左栏
    local panelId = (owner == "character") and "right"
        or (owner == "smith") and "center" or "left"
    local note = Viewport.getNote(panelId)
    if not note then return nil end
    local panel = Viewport.PANELS[panelId]
    local cs = note.s * Viewport.DS
    if cs == 0 then return nil end
    local dx = (sx - (note.ox + panel.bx * note.s)) / cs
    local dy = (sy - (note.oy + panel.by * note.s)) / cs
    if EquipmentDetail.containsPoint(dx, dy) then
        return dx, dy, EquipmentDetail
    end
    return nil
end

function HandleNanoVGRenderHorizon()
    if not vg() then return end
    HorizonUpdateTransform()
    nvgBeginFrame(vg(), windowW(), windowH(), dpr())
    nvgBeginPath(vg())
    nvgRect(vg(), 0, 0, windowW(), windowH())
    nvgFillColor(vg(), nvgRGBA(8, 8, 12, 255))
    nvgFill(vg())
    applyFrame()

    -- 分帧启动中：只画标题，避免未 init 的城镇/战斗模块被绘制
    if not bootReady_() then
        nvgBeginPath(vg())
        nvgRect(vg(), 0, 0, logicalW(), logicalH())
        nvgFillColor(vg(), nvgRGBA(14, 14, 22, 255))
        nvgFill(vg())
        if DarkTitleScreen.isOpen() then
            DarkTitleScreen.draw(vg(), logicalW(), logicalH())
        elseif StartScreen.isOpen() then
            local ss = math.min(logicalW() / 1080, logicalH() / 2400)
            nvgSave(vg())
            nvgTranslate(vg(), (logicalW() - 1080 * ss) * 0.5, (logicalH() - 2400 * ss) * 0.5)
            nvgScale(vg(), ss, ss)
            StartScreen.draw(vg())
            nvgRestore(vg())
        end
        finishFrame()
        return
    end

    -- 标题未淡出：只画标题。bootReady_() 提前解锁后默认 tab 仍是战斗，
    -- 但 BattleTriPage 要等标题关闭才 open；若此时画中栏会闪一帧竖屏 BattleScene。
    if DarkTitleScreen.isOpen() and not DarkTitleScreen.isFading() then
        nvgBeginPath(vg())
        nvgRect(vg(), 0, 0, logicalW(), logicalH())
        nvgFillColor(vg(), nvgRGBA(14, 14, 22, 255))
        nvgFill(vg())
        if DarkTitleScreen.isOpen() then
            DarkTitleScreen.draw(vg(), logicalW(), logicalH())
        end
        finishFrame()
        return
    end

    -- 横屏底色。石框、关卡图和各页底板负责可见画面，不再铺 UI_WORLD_BG。
    nvgBeginPath(vg())
    nvgRect(vg(), 0, 0, logicalW(), logicalH())
    nvgFillColor(vg(), nvgRGBA(14, 14, 22, 255))
    nvgFill(vg())

    -- 调试跳过：进主流程
    if H_SKIP_START and not H_skipDone and StartScreen.isOpen() then
        H_skipDone = true
        StartScreen.skipForReconnect()
        -- 调试跳过开始画面时直接进主界面。提前打开暗黑标题会在资源未就绪时吞点击，表现为黑屏卡死。
    end

    -- 开始画面：全窗口居中（2400 高画布，适配横屏高度）
    if StartScreen.isOpen() then
        local ss = math.min(logicalW() / 1080, logicalH() / 2400)
        nvgSave(vg())
        nvgTranslate(vg(), (logicalW() - 1080 * ss) * 0.5, (logicalH() - 2400 * ss) * 0.5)
        nvgScale(vg(), ss, ss)
        StartScreen.draw(vg())
        nvgRestore(vg())
        -- [一次性加载] 预载遮罩（开始画面上层）
        if RT.preload_.active then
            RT.DrawPreloadOverlay(vg(), logicalW(), logicalH())
        end
        finishFrame()
        return
    end

    -- [三行并行守卫] 三行战斗模式打开时，左右面板由下方 BattleTriPage 分支按
    -- 三行布局重新绘制（viewport 变换不同）；此处跳过，避免右侧「我的远征队员」
    -- 面板与左侧城镇建筑名牌各被绘制两次。
    if not bootReady_() then
        finishFrame()
        return
    end

    if not BattleTriPage.isOpen() then
        -- 左面板：功能页组（城镇 + 二级页）
        -- [锻炉双页 0929] BlacksmithPage 已移至中面板绘制（左栏让给仓库）
        Viewport.begin(vg(), Viewport.PANELS.left, H_ox, H_oy, H_s)
        TownScene.draw(vg())
        ChurchPage.draw(vg())
        if not talentPageUsesWideLayout() then TalentPage.draw(vg()) end
        TavernPage.draw(vg())
        MarketPage.draw(vg())
        BackpackPanel.draw(vg())
        LootBox.drawPage(vg())
        TaskPage.draw(vg())
        drawRewardInPanel('left')
        Viewport.finish(vg())

        -- 右面板：角色固定（先于中面板绘制，便于弹窗时统一压暗侧栏）
        Viewport.begin(vg(), Viewport.PANELS.right, H_ox, H_oy, H_s)
        CharacterPanel.draw(vg())
        drawRewardInPanel('right')
        Viewport.finish(vg())

        -- [弹窗聚焦] 中面板有模态弹窗时，压暗左右面板（在侧栏之上、中面板之下）
        HorizonDimSidePanels()
    end

    -- 中面板：BottomNav 主视图 + 全屏战斗页
    Viewport.begin(vg(), Viewport.PANELS.center, H_ox, H_oy, H_s)
    local dungeonBattleOpen = DungeonBattleScene.isOpen()
    local towerBattleOpen = TowerBattleScene.isActive()
    if towerBattleOpen then
        -- 通天塔三行攻坚铺满窗口，见 Viewport.finish 之后
    elseif dungeonBattleOpen then
        DungeonBattleScene.draw(vg())
    else
        local tabIndex = BottomNav.getSelectedIndex()
        if tabIndex == 1 then
            CharacterPanel.draw(vg())
        elseif tabIndex == 3 then
            if not BattleTriPage.isOpen() then
                BattleScene.draw(vg())
            end
            -- [三栏并行] 三栏页打开时中面板留空，全窗绘制见 Viewport.finish 之后
        elseif tabIndex == 5 then
            -- [底栏移除] 副本页横屏全窗绘制，见 Viewport.finish 之后
        else
            TownScene.draw(vg())
        end
        -- [锻炉双页 0929] 锻炉页绘制在中面板（盖在主视图之上；左栏同时开着仓库）
        BlacksmithPage.draw(vg())
        -- [底栏移除] 三行布局 TopBar 只画左栏；非三行旧布局仍画中栏顶部
        local detailOpen = CharacterPanel.isDetailOpen()
        if not detailOpen and not BattleTriPage.isOpen() and not BlacksmithPage.isOpen() then
            TopBar.draw(vg())
        end
    end
    Viewport.finish(vg())

    -- [锻炉双页 0929] 非三行模式的中缝返回条（锻炉右缘 ›；三行模式见 BattleTriPage 分支）
    if not BattleTriPage.isOpen() then
        for _, seamBtn in ipairs(seamBackList()) do
            DrawUtil.drawBackSeamBar(vg(), seamBtn.cx, logicalH() * 0.5,
                seamBtn.sw, seamBtn.sh, seamBtn.dir, seamBtn.bw, seamBtn.bh)
        end
    end

    if talentPageUsesWideLayout() and not BattleTriPage.isOpen() then
        drawWideTalentPage(H_ox, H_oy, H_s)
    end

    if towerBattleOpen then
        TowerBattleScene.draw(vg(), logicalW(), logicalH())
        if OfflineRewardPanel.isOpen() or LevelUpPopup.isOpen()
            or (RewardPopup.isOpen() and not RewardPopup.currentRowTag()) then
            local fit = math.min(logicalW() / 1080, logicalH() / 2400)
            nvgSave(vg())
            nvgScissor(vg(), 0, 0, logicalW(), logicalH())
            nvgTranslate(vg(), (logicalW() - 1080 * fit) * 0.5, (logicalH() - 2400 * fit) * 0.5)
            nvgScale(vg(), fit, fit)
            if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
                RewardPopup.draw(vg())
            end
            if OfflineRewardPanel.isOpen() then
                OfflineRewardPanel.draw(vg())
            end
            if LevelUpPopup.isOpen() then
                LevelUpPopup.draw(vg())
            end
            nvgRestore(vg())
        end
        drawEquipDetailOverlay()
        EquipCrossDrag.draw(vg())
    KeyboardShortcuts.draw(vg(), logicalW(), logicalH())
        finishFrame()
        return
    end

    -- [三行并行] 战斗模式布局: 经营(左) | 三行战斗(中段) | 角色(右) 铺满窗口
    if BattleTriPage.isOpen() then
        local ps = logicalH() / 1080                -- 面板缩放（高适配）
        local oxL = 0
        -- 右栏与左栏同宽。横向再放大 5% 会把方形角色框拉成扁的。
        local rightW = 486 * ps
        local oxR = logicalW() - (972 * ps + rightW)
        BattleTriPage.drawL1Underlay(vg(), logicalW(), logicalH())  -- [暗黑替换] L1 行内容背景垫底（框内 clip）
        BattleTriPage.drawL0(vg(), logicalW(), logicalH())          -- [暗黑替换] L0 框体图（透明框内透出 L1）
        Viewport.begin(vg(), Viewport.PANELS.left, oxL, 0, ps)
        TownScene.draw(vg())
        ChurchPage.draw(vg())
        if not talentPageUsesWideLayout() then TalentPage.draw(vg()) end
        TavernPage.draw(vg())
        MarketPage.draw(vg())
        BackpackPanel.draw(vg())
        LootBox.drawPage(vg())
        TaskPage.draw(vg())
        -- [三行并行] 头像/金币/宝石 显示到左侧面板（城镇主视图时顶层绘制，优先级高于场景）
        -- oy=-30：头像框/名字组稍上移（点击热区见 MouseButtonUpHorizon left 段 hitTestAvatar -30）
        if not (BlacksmithPage.isOpen() or ChurchPage.isOpen() or TalentPage.isOpen() or TavernPage.isOpen()
            or MarketPage.isOpen() or LootBoxPage.isOpen() or TaskPage.isOpen()) then
            TopBar.draw(vg(), -30)
        end
        -- 三行战斗的玩家信息在后面全窗居中重画，这里不画，避免左栏裁切出半个面板。
        Viewport.finish(vg())
        Viewport.begin(vg(), Viewport.PANELS.right, oxR, 0, ps, rightW / 1080)
        CharacterPanel.draw(vg())
        Viewport.finish(vg())
        -- 三行战斗内容 + UI 层（窗口坐标; 战斗内容 clip 在各框内矩形）
        BattleTriPage.draw(vg(), logicalW(), logicalH())
        -- [行1 HUD] 宿主最终层级绘制：速度/扫荡/统计/选关按钮——
        -- 确保位于一切战斗行背景与框柱之上（用户实测按钮被行1背景穿帮）
        BattleTriPage.drawHud(vg(), logicalW(), logicalH())
        -- [锻炉双页 0929] 锻炉页绘制在 tri 中栏区域（盖在战斗行之上，紧邻左栏仓库；
        -- 关闭竖栏挂在锻炉右缘，见 seamBackList）
        if BlacksmithPage.isOpen() then
            Viewport.begin(vg(), Viewport.PANELS.center, oxL, 0, ps)
            BlacksmithPage.draw(vg())
            Viewport.finish(vg())
        end
        drawWideTalentPage(0, 0, logicalH() / 1080)
        -- [三队并行] 中缝返回条（窗口坐标，页面视口之外）：全高门柱边条，左页‹ / 详情›，两级并存各自绘制
        for _, seamBtn in ipairs(seamBackList()) do
            DrawUtil.drawBackSeamBar(vg(), seamBtn.cx, logicalH() * 0.5,
                seamBtn.sw, seamBtn.sh, seamBtn.dir, seamBtn.bw, seamBtn.bh)
        end
        -- 玩家信息已画在左栏视口内。三行路径会提前 return，必须在这里再画一层全窗居中，
        -- 否则面板被左栏裁切，点外面也无法按面板外关闭。
        if SpinePowerUpEffect.isPlaying() then
            Viewport.begin(vg(), Viewport.PANELS.left, oxL, 0, ps)
            SpinePowerUpEffect.draw(vg(), -30)
            Viewport.finish(vg())
        end
        if PlayerInfoPanel.isOpen() then
            local fit = math.min(logicalW() / 1080, logicalH() / 2400)
            nvgSave(vg())
            nvgScissor(vg(), 0, 0, logicalW(), logicalH())
            nvgTranslate(vg(), (logicalW() - 1080 * fit) * 0.5, (logicalH() - 2400 * fit) * 0.5)
            nvgScale(vg(), fit, fit)
            PlayerInfoPanel.draw(vg())
            nvgRestore(vg())
        end
        -- 全局奖励 / 离线收益仍在窗口居中覆盖，遗匣仅在上方左栏链绘制。
        -- 三行战斗会提前 return，必须在这里画，否则离线收益只 open 不显示。
        if (RewardPopup.isOpen() and not RewardPopup.currentRowTag()) or OfflineRewardPanel.isOpen() then
            local fit = math.min(logicalW() / 1080, logicalH() / 2400)
            nvgSave(vg())
            nvgScissor(vg(), 0, 0, logicalW(), logicalH())
            nvgTranslate(vg(), (logicalW() - 1080 * fit) * 0.5, (logicalH() - 2400 * fit) * 0.5)
            nvgScale(vg(), fit, fit)
            if RewardPopup.isOpen() and not RewardPopup.currentRowTag()
                and not RewardPopup.currentPanel() then
                RewardPopup.draw(vg())
            end
            if OfflineRewardPanel.isOpen() then
                OfflineRewardPanel.draw(vg())
            end
            if LevelUpPopup.isOpen() then
                LevelUpPopup.draw(vg())
            end
            nvgRestore(vg())
        end
        -- [底栏移除] 副本页全窗竖版模态（盖在三行战斗之上、标题/开场之下）
        HorizonDrawPageModal(vg())
        -- [三面板] 三行模式：归属面板的奖励弹窗随触发面板绘制（左/中/右）；
        -- 非三行模式左/右已在各自视口内绘制、中栏由全局弹窗层绘制，此处不重复
        if BattleTriPage.isOpen() then
            drawRewardInPanel(RewardPopup.currentPanel())
        end
        -- [DarkTitleScreen] 横屏标题（基屏幕空间，覆盖一切直至点击淡出）
        -- 资源未就绪时标题自带进度条，不允许点进空背景界面
        if DarkTitleScreen.isOpen() then
            DarkTitleScreen.draw(vg(), logicalW(), logicalH())
        elseif RT.preload_.active then
            RT.DrawPreloadOverlay(vg(), logicalW(), logicalH())
        end
        -- [LetterIntro] 开场覆盖必须在标题之后，否则信件被大门挡住且点击被吞
        HorizonDrawIntroOverlay()
        drawEquipDetailOverlay()
        -- [横屏接线 0928] 新手引导蒙层（装备详情浮层之上，装备引导步骤高亮可见）
        HorizonDrawTutorialOverlay()
        EquipCrossDrag.draw(vg())
    KeyboardShortcuts.draw(vg(), logicalW(), logicalH())
        finishFrame()
        return
    end

    -- 全局弹窗层（模态，绘制于中面板空间，坐标与原竖屏逻辑一致）
    Viewport.begin(vg(), Viewport.PANELS.center, H_ox, H_oy, H_s)
    HeroRosterPanel.draw(vg())
    PlayerInfoPanel.draw(vg())
    RewardPopup.draw(vg())
    OfflineRewardPanel.draw(vg())
    SpinePowerUpEffect.draw(vg())
    LevelUpPopup.draw(vg())
    Viewport.finish(vg())

    -- [暗黑化 P0] 图标画廊验收页（基屏幕空间全窗口适配，便于验收；通过后置 SHOWCASE=false）
    if DarkIcon.SHOWCASE then
        nvgSave(vg())
        nvgScissor(vg(), 0, 0, logicalW(), logicalH())  -- 重置面板 intersect 裁剪
        local ss = math.min(logicalW() / 1080, logicalH() / 2400)
        nvgTranslate(vg(), (logicalW() - 1080 * ss) * 0.5, (logicalH() - 2400 * ss) * 0.5)
        nvgScale(vg(), ss, ss)
        DarkIcon.drawShowcase(vg())
        nvgRestore(vg())
    end

    -- 玩家信息已由中栏弹窗层绘制，不再用竖屏坐标居中重画。
    -- [底栏移除] 副本页全窗竖版模态
    HorizonDrawPageModal(vg())
    -- [DarkTitleScreen] 横屏标题（基屏幕空间，覆盖一切直至点击淡出）
    if DarkTitleScreen.isOpen() then
        DarkTitleScreen.draw(vg(), logicalW(), logicalH())
    elseif RT.preload_.active then
        RT.DrawPreloadOverlay(vg(), logicalW(), logicalH())
    end
    -- [LetterIntro] 开场覆盖必须在标题之后（非三行路径同样需要）
    HorizonDrawIntroOverlay()
    UiToast.draw(vg(), logicalW(), logicalH())
    drawEquipDetailOverlay()
    -- [横屏接线 0928] 新手引导蒙层（装备详情浮层之上）
    HorizonDrawTutorialOverlay()
    EquipCrossDrag.draw(vg())
    KeyboardShortcuts.draw(vg(), logicalW(), logicalH())

    finishFrame()
end

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
    local mousePos = input:GetMousePosition()
    local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
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

local equipOverlayPress = false

function HandleMouseButtonDownHorizon(eventType, eventData)
    if vg() then
        local mousePos = input:GetMousePosition()
        local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
        if CEPanel.handleDown(sx, sy, logicalH()) then
            return
        end
    end
    if not bootReady_() then return end
    -- [DarkTitleScreen] 标题期吞掉按下（继续由 ButtonUp 触发）
    if DarkTitleScreen.isOpen() then return end
    -- [LetterIntro] 开场期也要记 pressValid，否则抬起被当成无效点击
    if LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive() then
        pressValid = true
        pressStartDX, pressStartDY = 0, 0
        return
    end
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_LEFT then
        local mousePos = input:GetMousePosition()
        local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
        local dx, dy, ED = equipOverlayDesign(sx, sy)
        if dx then
            equipOverlayPress = true
            pressValid = true
            ED.handleDragBegin(dx, dy)
            print("[Horizon] 详情浮层按下")
            return
        end
        -- 详情开着时，点任意空白先关掉，不把这次点击传给后面的页面
        local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
        if EquipmentDetail.isCompactCorner() then
            EquipmentDetail.close()
            equipOverlayPress = false
            pressValid = false
            print("[Horizon] 点击空白关闭装备详情")
            return
        end
        equipOverlayPress = false
    end
    if button == MOUSEB_RIGHT then
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
            return
        end
        return
    end
    if button ~= MOUSEB_LEFT then return end
    lootPress = false
    LootBox.handleDragEnd(0, 0)
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
            local mousePos = input:GetMousePosition()
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
        CharacterPanel.handleDragBegin(dx, dy)
    end
end

function HandleMouseMoveHorizon(eventType, eventData)
    if DarkTitleScreen.isOpen() then return end
    if LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive() then return end
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
        local mousePos = input:GetMousePosition()
        local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
        if EquipCrossDrag.move(sx, sy) then
            return
        end
        local source = EquipCrossDrag.getSource()
        if source == "overlay" then
            if pid ~= "tri" then return end
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
        local mousePos = input:GetMousePosition()
        local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
        local odx, ody, ED = equipOverlayDesign(sx, sy)
        if odx and ED then ED.handleDragMove(odx, ody) end
        return
    end
    if not pressValid then
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
    if DarkTitleScreen.isOpen() or LetterIntro.isOpen() or IntroCutscene.isActive()
        or ScenarioDialogue.isActive() or pressValid or equipOverlayPress
        or EquipCrossDrag.isArmed() then return end
    local pid, dx, dy = HorizonResolveMouse()
    if pid == 'right'
        or (pid == 'center' and BottomNav.getSelectedIndex() == 1 and not BlacksmithPage.isOpen()) then
        if CharacterPanel.handleHover then CharacterPanel.handleHover(dx, dy) end
    elseif CharacterPanel.handleHover then
        CharacterPanel.handleHover(-1, -1)
    end
    if pid == 'left' then
        if BackpackPanel.isOpen and BackpackPanel.isOpen() and BackpackPanel.handleHover then
            BackpackPanel.handleHover(dx, dy)
        end
        if EquipmentBag.isOpen and EquipmentBag.isOpen() and EquipmentBag.handleHover then
            EquipmentBag.handleHover(dx, dy)
        end
    else
        if BackpackPanel.handleHover then BackpackPanel.handleHover(-1, -1) end
        if EquipmentBag.handleHover then EquipmentBag.handleHover(-1, -1) end
    end
end

function HandleMouseButtonUpHorizon(eventType, eventData)
    if equipOverlayPress then
        equipOverlayPress = false
        local mousePos = input:GetMousePosition()
        local sx, sy = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
        local dx, dy, ED = equipOverlayDesign(sx, sy)
        if dx and ED then
            ED.handleDragEnd()
            ED.handleInput(dx, dy)
            print("[Horizon] 详情浮层点击")
        end
        pressValid = false
        return
    end
    if vg() then
        local mousePos = input:GetMousePosition()
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
            local mousePos = input:GetMousePosition()
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
        local mousePos = input:GetMousePosition()
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
    local mousePos = input:GetMousePosition()
    local seamX, seamY = toDesign(mousePos.x / dpr(), mousePos.y / dpr())
    local seamBtn = seamHitAt(seamX, seamY)
    if seamBtn then
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
    -- [横屏接线 0928] 新手引导激活时接管 tap：高亮区域推进并穿透，非目标区域/面板吞掉
    if TutorialManager.isActive() and isTap then
        local tdx, tdy = dx, dy
        if pid == 'tri' or pid == 'none' then
            -- 引导层在 tri 模式下走全窗 letterbox 绘制：把窗口坐标转为 letterbox design 坐标，
            -- 保证跳过按钮在战斗三栏期间也可点（防卡死）
            local mp = input:GetMousePosition()
            local sx2, sy2 = toDesign(mp.x / dpr(), mp.y / dpr())
            tdx, tdy = playerInfoDesignCoords(sx2, sy2)
        end
        if TutorialManager.handleClick(tdx, tdy, pid) then
            pressValid = false
            return
        end
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

function HandleTouchBeginHorizon(eventType, eventData)
    HandleMouseButtonDownHorizon(eventType, eventData)
end

function HandleTouchEndHorizon(eventType, eventData)
    HandleMouseButtonUpHorizon(eventType, eventData)
end

function HandleTouchMoveHorizon(eventType, eventData)
    HandleMouseMoveHorizon(eventType, eventData)
end

function HandleMouseWheelHorizon(eventType, eventData)
    -- [DarkTitleScreen] 标题期吞掉滚轮
    if DarkTitleScreen.isOpen() then return end
    if LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive() then return end
    local wheel = eventData["Wheel"]:GetInt()
    if wheel == 0 then return end
    local mousePos = input:GetMousePosition()
    local sx = mousePos.x / dpr()
    local sy = mousePos.y / dpr()
    local csx, csy = toDesign(sx, sy)
    if CEPanel.handleWheel(csx, csy, wheel, logicalH()) then return end
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

