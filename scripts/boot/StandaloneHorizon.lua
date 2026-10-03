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
local OfflineRewardOverlay = require("boot.OfflineRewardOverlay").bind(OfflineRewardPanel, RT)
local UpdateNoticePopup = require("ui.hud.popup.UpdateNoticePopup")
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

--- [UpdateNoticePopup] 更新提醒全窗模态（1080×2400 设计稿 letterbox 居中，同 PlayerInfoPanel）。
--- 放在 finishFrame 收尾统一绘制：所有 early-return 渲染路径都能盖到，且位于业务面板之上。
local function drawUpdateNotice()
    if not UpdateNoticePopup.isOpen() then return end
    local fit = math.min(logicalW() / 1080, logicalH() / 2400)
    nvgSave(vg())
    nvgResetScissor(vg())
    nvgScissor(vg(), 0, 0, logicalW(), logicalH())
    nvgTranslate(vg(), (logicalW() - 1080 * fit) * 0.5, (logicalH() - 2400 * fit) * 0.5)
    nvgScale(vg(), fit, fit)
    UpdateNoticePopup.draw(vg())
    nvgRestore(vg())
end

local function finishFrame()
    nvgSave(vg())
    nvgResetTransform(vg())
    applyFrame()
    nvgResetScissor(vg())
    nvgScissor(vg(), 0, 0, logicalW(), logicalH())
    drawOrphanRowReward()
    -- 升级弹窗由宿主逻辑空间布局：不再借中栏 Viewport 或 1080×2400 letterbox。
    -- 所有业务/PlayerInfo/三行/通天塔绘制都已完成，Offline/Update/CE 保持原上层优先级。
    if LevelUpPopup.isOpen() then
        LevelUpPopup.draw(vg(), logicalW(), logicalH())
    end
    if not DarkTitleScreen.isOpen() and not LetterIntro.isOpen()
        and not IntroCutscene.isActive() and not ScenarioDialogue.isActive() then
        OfflineRewardOverlay.draw()
    end
    drawUpdateNotice()
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
    H_SEAM_BACK = BattleTriPage.isOpen() and not TowerBattleScene.isActive()
        -- 塔路径提前返回，不画三行中缝条；塔内功绩页使用 TownPageChrome 自带返回。
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
    -- [UI 0930] 返回条朝所属页面方向收 2px：左栏条向左、右栏条向右，
    -- 让条与页面边缘轻微重叠，消除中缝留缝（hit 与 draw 共用此列表，自动同步）
    for _, b in ipairs(list) do
        b.cx = b.cx + ((b.dir == "left") and -2 or 2)
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
        -- [0930 穿帮修复] 锻炉打开时仓库下铺锻炉背景垫底（城镇组之上、仓库之下）
        BlacksmithPage.drawUnderlay(vg())
        BackpackPanel.draw(vg())
        LootBox.drawPage(vg())
        if not TowerBattleScene.isActive() then TaskPage.draw(vg()) end
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
        -- 查看等级奖励只叠功绩左栏，不退出塔；关闭后继续原塔场景。
        if TaskPage.isOpen() then
            Viewport.begin(vg(), Viewport.PANELS.left, 0, 0, logicalH() / 1080)
            TaskPage.draw(vg())
            Viewport.finish(vg())
        end
        if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
            local fit = math.min(logicalW() / 1080, logicalH() / 2400)
            nvgSave(vg())
            nvgScissor(vg(), 0, 0, logicalW(), logicalH())
            nvgTranslate(vg(), (logicalW() - 1080 * fit) * 0.5, (logicalH() - 2400 * fit) * 0.5)
            nvgScale(vg(), fit, fit)
            RewardPopup.draw(vg())
            nvgRestore(vg())
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
        -- [0930 穿帮修复] 锻炉打开时仓库下铺锻炉背景垫底（城镇组之上、仓库之下）
        BlacksmithPage.drawUnderlay(vg())
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
        -- 离线收益与升级窗由 finishFrame 全窗绘制；奖励仍保留原归属路由。
        if RewardPopup.isOpen() and not RewardPopup.currentRowTag() then
            local fit = math.min(logicalW() / 1080, logicalH() / 2400)
            nvgSave(vg())
            nvgScissor(vg(), 0, 0, logicalW(), logicalH())
            nvgTranslate(vg(), (logicalW() - 1080 * fit) * 0.5, (logicalH() - 2400 * fit) * 0.5)
            nvgScale(vg(), fit, fit)
            if not RewardPopup.currentPanel() then
                RewardPopup.draw(vg())
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
    SpinePowerUpEffect.draw(vg())
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

require('boot.StandaloneHorizonInput').bind({
    vg = vg,
    logicalW = logicalW,
    logicalH = logicalH,
    windowW = windowW,
    windowH = windowH,
    dpr = dpr,
    DESIGN_W = DESIGN_W,
    DESIGN_H = DESIGN_H,
    bootReady_ = bootReady_,
    toDesign = toDesign,
    talentPageUsesWideLayout = talentPageUsesWideLayout,
    syncTalentPageLayout = syncTalentPageLayout,
    talentPageRightEdge = talentPageRightEdge,
    equipOverlayDesign = equipOverlayDesign,
    seamHitAt = seamHitAt,
    RT = RT,
    Viewport = Viewport,
    OfflineRewardOverlay = OfflineRewardOverlay,
})
