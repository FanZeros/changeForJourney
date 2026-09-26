-- ============================================================================
-- BattleTriPage - 三行并行战斗（Phase 3 修正版）
-- 布局: 战斗区 = 中段区域（Standalone 传入 486,0,948,1080，左右经营/角色面板
--       保持原样），纵向堆叠三行战斗（行高 = rh/3 ≈ 360）:
--   行1/2/3 = 同一套 BattleTriDriver（各自独立状态）
--   行1 的关卡进度仍跟随 BattleScene（首通/存档/掉落不另起一套）
--   未解锁行: 暗罩 + 解锁等级 + 该队编队预览；返回按钮退出战斗区
-- 每行内 8 卡单线: 我方 4 张在左半段、敌方 4 张在右半段（BattleLayout strip 模式）
-- ============================================================================
local BattleLayout = require("core.BattleLayout")
local BattleView   = require("ui.battle.scene.BattleView")
local BattleCombat = require("ui.battle.combat.BattleCombat")
local ProjectileSystem = require("ui.battle.combat.ProjectileSystem")
local TM               = require("systems.ThreatManager")
local TAL              = require("systems.TalentManager")
local BattleEffects    = require("ui.battle.combat.BattleEffects")
local SEM              = require("systems.StatusEffectManager")
local ExpTable     = require("config.ExpTable")
local GameState    = require("core.GameState")
local RewardPopup  = require("ui.hud.popup.RewardPopup")
local SweepDialog       = require("ui.battle.stage.SweepDialog")
local DamageStatsPanel  = require("ui.battle.popup.DamageStatsPanel")
local StageSelectDialog = require("ui.battle.stage.StageSelectDialog")
local SoundToggle       = require("ui.widget.SoundToggle")  -- [音效开关] 行1 HUD 快捷按钮
local EquipmentBag      = require("ui.character.equip.EquipmentBag")
local StageConfig       = require("config.StageConfig")
local BattleStats       = require("systems.BattleStats")

local function stageDisplayName(stageId)
    local entry = stageId and StageConfig.getStage(tonumber(stageId))
    return (entry and entry.name) or tostring(stageId or "?")
end

local BattleTriPage = {}

local COL_COUNT = ExpTable.TEAM_COUNT or 3

-- ---- 状态 ----
local isOpen_ = false
local inited = false
local drivers = {}        -- [1]/[2]/[3] = BattleTriDriver
local triOnKill = nil     -- function(data)（由宿主注入，与 BattleScene.onEnemyKill 同构）
local triOnDrop = nil     -- function(data)（击杀掉落，与 BattleScene.onEnemyDrop 同构）
local region = { x = 486, y = 0, w = 948, h = 1080 }  -- 战斗区（窗口坐标）

local function dialogToDesign(wx, wy)
    local fit = math.min(region.w / 1080, region.h / 2400) * 2
    return (wx - region.w * 0.5) / fit + 540,
           (wy - region.h * 0.5) / fit + 1195
end

--- 击杀奖励回调注入（宿主与 BattleScene.setOnEnemyKill 同源）
function BattleTriPage.setOnKill(cb) triOnKill = cb end
function BattleTriPage.setOnDrop(cb) triOnDrop = cb end

function BattleTriPage.isOpen() return isOpen_ end

--- 存档阵容晚于战斗页到达时，清掉已记住的编队，下一帧按真实槽位重建。
function BattleTriPage.invalidateTeams()
    for _, drv in pairs(drivers) do
        drv.teamSignature = nil
    end
end


--- 创建新解锁队伍的战斗驱动；已存在的驱动保留关卡进度。
--- 小队1跟主线 BattleScene 的当前关，避免共用驱动后从第一关重开。
local function ensureDrivers()
    local unlocked = ExpTable.getUnlockedTeamCount(GameState.getLevel())
    local BattleScene = require("ui.battle.scene.BattleScene")
    for t = 1, COL_COUNT do
        if unlocked >= t and not drivers[t] then
            local Driver = require("ui.battle.tri.BattleTriDriver")
            local drv = Driver.new(t)
            drv.onKill = function(data)
                if triOnKill then triOnKill(data) end
                if triOnDrop then triOnDrop(data) end
            end
            local startStage = (t == 1) and BattleScene.getStageId()
                or StageConfig.NORMAL_FIRST_STAGE
            drv._syncedMainStage = startStage
            drv:start(startStage)
            drivers[t] = drv
        end
    end
    local teamOne = drivers[1]
    local mainStage = BattleScene.getStageId()
    if teamOne and mainStage and teamOne.stageId ~= mainStage
        and teamOne.stageId == teamOne._syncedMainStage then
        teamOne._syncedMainStage = mainStage
        teamOne:start(mainStage)
    elseif teamOne then
        teamOne._syncedMainStage = teamOne.stageId
    end
    return unlocked
end

--- 打开三行战斗（懒建驱动器；已解锁队伍自动开战）
function BattleTriPage.open()
    if isOpen_ then return end
    isOpen_ = true
    require("ui.battle.scene.BattleScene").pumpBattleCards()
    local unlocked = ensureDrivers()
    print("[BattleTriPage] open, unlockedTeams=" .. unlocked)
end

--- 返回（关闭战斗区，恢复中面板原战斗视图）
function BattleTriPage.close() isOpen_ = false end

--- 幂等初始化（贴图）
local imgL0, imgL1 = nil, {}   -- [三行并行] L0 整套大背景 + L1 行内容背景

-- [修复] 锁定行专用空状态: 锁定行绘制前挂载, 避免把行1 的飘字/特效/投射物
-- 重复画到行2/3（此前未挂载, BCS 上残留的是最近一次更新的状态）
local emptyStates = nil
local function ensureEmptyStates()
    if emptyStates then return end
    emptyStates = {
        combat = BattleCombat.newState("triLocked"),
        ps     = ProjectileSystem.newState(),
        tm     = TM.newState(),
        tal    = TAL.newBattleRefs(),
        be     = BattleEffects.newFxState(),
        sem    = SEM.newSemState(),
    }
end

--- 挂载锁定行的全空状态集
function BattleTriPage.mountEmpty()
    ensureEmptyStates()
    BattleStats.mount(0)
    BattleCombat.mount(emptyStates.combat)
    ProjectileSystem.mount(emptyStates.ps)
    TM.mount(emptyStates.tm)
    TAL.mount(emptyStates.tal)
    BattleEffects.mount(emptyStates.be)
    SEM.mount(emptyStates.sem)
end

function BattleTriPage.init(vg)
    if inited then return end
    inited = true
    BattleView.init(vg)
    -- [暗黑替换] L0 整套大背景 + L1 行内容背景（森林/荒原/深渊）
    imgL0      = nvgCreateImage(vg, "image/暗黑/L0_stone_frame.png", 0)  -- 石框三行底，左右石墙
    imgL1[1]   = nvgCreateImage(vg, "image/暗黑/L1_row1_forest.png", 0)
    imgL1[2]   = nvgCreateImage(vg, "image/暗黑/L1_row2_bonefield.png", 0)
    imgL1[3]   = nvgCreateImage(vg, "image/暗黑/L1_row3_abyss.png", 0)
    StageSelectDialog.init(vg)
    SoundToggle.initImages(vg)
end

--- [三行并行] L0 整套大背景铺满窗口（左右面板 + 中段框体同源）

--- 每帧更新：三行使用同一套 BattleTriDriver，只切换各自的状态实例。
function BattleTriPage.update(dt)
    if not isOpen_ then return end
    require("ui.battle.combat.BattleStutterPlans").poll()
    BattleLayout.setMode("strip")
    require("ui.battle.scene.BattleScene").pumpBattleCards()
    ensureDrivers()
    for t = 1, COL_COUNT do
        local drv = drivers[t]
        if drv then drv:update(dt) end
    end
    -- 三行结束后恢复默认状态，避免后续单场界面读到最后一队的数据。
    BattleStats.mount(0)
    BattleCombat.mount(nil)
    ProjectileSystem.mount(nil)
    TM.mount(nil)
    TAL.mount(nil)
    BattleEffects.mount(nil)
    SEM.mount(nil)
end
-- [暗黑替换 v2] L0 框体图（用户素材, 1672x941, 三个透明内矩形）+ 分层渲染
local PLATE_AR = 1672 / 941
-- 透明内矩形（归一化, 由图像 alpha 分析测得）
-- [等距化] 左右缝柱=行缝=37: x0=(486*941/1080+37)/1672, x1=1-同款
local INTERIORS = {
    { x0 = 0.2835, y0 = 0.0117, x1 = 0.7201, y1 = 0.3103 },
    { x0 = 0.2835, y0 = 0.3475, x1 = 0.7207, y1 = 0.6482 },
    { x0 = 0.2877, y0 = 0.6812, x1 = 0.7099, y1 = 0.9883 },
}

--- 框体内矩形 → 窗口坐标（L0 图按高度适配居中）
---@param row number 1..3
---@return number x number y number w number h
local function interiorRect(row, logicalW, logicalH)
    local ir = INTERIORS[row]
    local ph = logicalH
    local pw = ph * PLATE_AR
    local ox = (logicalW - pw) * 0.5
    return ox + ir.x0 * pw, ir.y0 * ph, (ir.x1 - ir.x0) * pw, (ir.y1 - ir.y0) * ph
end

--- [三队并行] 行内矩形（窗口坐标）导出：供 Standalone 中缝返回键定位
---@param row number 行号 1~3
---@return number x number y number w number h
function BattleTriPage.getInteriorRect(row)
    return interiorRect(row, region.w, region.h)
end

--- 按指定窗口尺寸取行内矩形（通天塔攻坚等独立宿主）
---@param row number
---@param logicalW number
---@param logicalH number
---@return number x number y number w number h
function BattleTriPage.getInteriorRectFor(row, logicalW, logicalH)
    return interiorRect(row, logicalW, logicalH)
end

--- L0 整套大背景铺满窗口（透明框内将由 L1 垫底透出）
function BattleTriPage.drawL0(vg, logicalW, logicalH)
    BattleTriPage.init(vg)
    local ph = logicalH
    local pw = ph * PLATE_AR
    local ox = (logicalW - pw) * 0.5
    if imgL0 and imgL0 >= 0 then
        local paint = nvgImagePattern(vg, ox, 0, pw, ph, 0, imgL0, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, ox, 0, pw, ph)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
end

--- L1 行内容背景垫底层（clip 到框内矩形; 锁定行加暗罩）——绘制于 L0 之前
function BattleTriPage.drawL1Underlay(vg, logicalW, logicalH)
    BattleTriPage.init(vg)
    local BattleScene = require("ui.battle.scene.BattleScene")
    local unlocked = ExpTable.getUnlockedTeamCount(GameState.getLevel())
    for row = 1, COL_COUNT do
        local ix, iy, iw, ih = interiorRect(row, logicalW, logicalH)
        nvgSave(vg)
        nvgScissor(vg, ix, iy, iw, ih)
        -- L1 cover-fit
        local s = math.max(iw / 1896, ih / 720)
        local dw, dh = 1896 * s, 720 * s
        local paint = nvgImagePattern(vg, ix + (iw - dw) * 0.5, iy + (ih - dh) * 0.5,
            dw, dh, 0, imgL1[row], 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, ix, iy, iw, ih)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        if row > unlocked then
            nvgBeginPath(vg)
            nvgRect(vg, ix, iy, iw, ih)
            nvgFillColor(vg, nvgRGBA(8, 8, 14, 150))
            nvgFill(vg)
        end
        nvgRestore(vg)
    end
end

--- 三行战斗区主绘制（L0 已由宿主铺底; 本函数画战斗内容层 + UI 层）
function BattleTriPage.draw(vg, logicalW, logicalH)
    if not isOpen_ then return end
    BattleTriPage.init(vg)
    local plans = require("ui.battle.combat.BattleStutterPlans")
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 214, 120, 255))
    nvgText(vg, 16, 8, "卡顿方案 " .. (plans.names[plans.mode] or "?") .. "  按1/2/3切换", nil)
    BattleLayout.setMode("strip")
    region = { x = 0, y = 0, w = logicalW, h = logicalH }

    local BattleScene = require("ui.battle.scene.BattleScene")
    local unlocked = ExpTable.getUnlockedTeamCount(GameState.getLevel())

    -- 统一战斗缩放: 取三个内矩形中最小可容缩放, 保证三行卡牌等大
    local contentScale = 1.0
    for row = 1, COL_COUNT do
        local ix, iy, iw, ih = interiorRect(row, logicalW, logicalH)
        contentScale = math.min(contentScale,
            math.min(iw / BattleLayout.STRIP_W, ih / BattleLayout.STRIP_H))
    end

    -- ===== 战斗内容层（clip 到各框内矩形）=====
    for row = 1, COL_COUNT do
        local ix, iy, iw, ih = interiorRect(row, logicalW, logicalH)
        if row <= unlocked then
            local dw = BattleLayout.STRIP_W * contentScale
            local dh = BattleLayout.STRIP_H * contentScale
            nvgSave(vg)
            nvgScissor(vg, ix, iy, iw, ih)
            nvgTranslate(vg, ix + (iw - dw) * 0.5, iy + (ih - dh) * 0.5 + ih * 0.06)
            nvgScale(vg, contentScale, contentScale)
            local drv = drivers[row]
            if drv then
                drv:activate()
                BattleView.draw(vg, { allies = drv.allies, enemies = drv.enemies }, nil, true)
            end
            nvgRestore(vg)
        end
    end

    -- ===== UI 层（窗口坐标）=====
    -- 行标签
    for row = 1, COL_COUNT do
        local ix, iy, iw, ih = interiorRect(row, logicalW, logicalH)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local stageText
        if drivers[row] then
            stageText = string.format("【小队%d】%s", row, stageDisplayName(drivers[row].stageId))
        elseif row <= unlocked then
            stageText = string.format("【小队%d】准备中", row)
        else
            stageText = string.format("【小队%d】待解锁", row)
        end
        -- [暗黑化] 不再画行标签底条，文字直接浮在战斗场景上
        nvgFillColor(vg, nvgRGBA(215, 222, 240, 255))
        nvgText(vg, ix + 28, iy + 25, stageText, nil)

        local killed, total
        if row <= unlocked and drivers[row] and #drivers[row].allies > 0 then
            killed, total = drivers[row].kills, drivers[row].stageTotal
        end
        if killed and total and total > 0 then
            local ratio = math.max(0, math.min(1, killed / total))
            local pctShown = math.floor(ratio * 100 + 0.5)
            local pctText = string.format("%d%%", pctShown)
            local barW = math.min(iw * 0.62, 280)
            local barH = 10
            local barX = ix + (iw - barW) * 0.5
            local barY = iy + ih - 8
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW, barH, 5)
            nvgFillColor(vg, nvgRGBA(8, 8, 14, 170))
            nvgFill(vg)
            if ratio > 0 then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, barX, barY, math.max(barH, barW * ratio), barH, 5)
                nvgFillColor(vg, nvgRGBA(196, 148, 72, 230))
                nvgFill(vg)
            end
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(236, 226, 198, 255))
            nvgText(vg, ix + iw * 0.5, barY - 12, "关卡进度 " .. pctText, nil)
        end

        if row <= unlocked and drivers[row] and #drivers[row].allies == 0 then
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 28)
            nvgFillColor(vg, nvgRGBA(236, 226, 198, 255))
            nvgText(vg, ix + iw * 0.5, iy + ih * 0.5, "未编队，请在右侧部署队员", nil)
        end

        -- 未解锁提示（行内居中）
        if row > unlocked then
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local needLv = ExpTable.getTeamUnlockLevel(row)
            nvgFontSize(vg, 44)
            nvgFillColor(vg, nvgRGBA(165, 170, 190, 255))
            nvgText(vg, ix + iw * 0.5, iy + ih * 0.5,
                string.format("远征等级达到 %s 解锁", tostring(needLv or "?")), nil)
        end
    end

    -- [对话框覆盖] 选关/扫荡/统计：按当前横屏可用区域放大到 2 倍。
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen() then
        local fit = math.min(logicalW / 1080, logicalH / 2400) * 2
        nvgSave(vg)
        nvgScissor(vg, 0, 0, logicalW, logicalH)
        nvgTranslate(vg, logicalW * 0.5, logicalH * 0.5)
        nvgScale(vg, fit, fit)
        nvgTranslate(vg, -540, -1195)
        if SweepDialog.isOpen() then SweepDialog.draw(vg) end
        if DamageStatsPanel.isOpen() then DamageStatsPanel.draw(vg) end
        if StageSelectDialog.isOpen() then StageSelectDialog.draw(vg) end
        nvgRestore(vg)
    end

    -- [三行并行] 获得弹窗归属行1
    local rx1, ry1, rw1, rh1 = interiorRect(1, logicalW, logicalH)
    RewardPopup.drawRegion(vg, rx1, ry1, rw1, rh1, 1)

    -- 装备背包覆盖战斗区（无灰底；铺进行 1~3 内框）
    if EquipmentBag.shouldBattleOverlay() then
        local ox, oy, ow = interiorRect(1, logicalW, logicalH)
        local _, y3, _, h3 = interiorRect(COL_COUNT, logicalW, logicalH)
        EquipmentBag.setOverlayRegion(ox, oy, ow, (y3 + h3) - oy)
        EquipmentBag.drawOverlay(vg)
    else
        EquipmentBag.setOverlayRegion(nil)
    end
end

--- 某队当前关卡（供选关弹窗定位章节）
---@param teamIdx number
---@return number|nil
function BattleTriPage.getTeamStageId(teamIdx)
    local drv = drivers[teamIdx]
    return drv and drv.stageId or nil
end

--- 切换某队关卡。小队1同步写回 BattleScene，保持主线进度一致。
---@param teamIdx number
---@param stageId number
---@return boolean
function BattleTriPage.gotoTeamStage(teamIdx, stageId)
    local drv = drivers[teamIdx]
    if not drv then return false end
    if teamIdx == 1 then
        local BattleScene = require("ui.battle.scene.BattleScene")
        if not BattleScene.gotoStage(stageId) then return false end
    end
    drv:start(stageId)
    return true
end

--- 每行 HUD 从右上角往左排：速度(可选) / 扫荡 / 统计 / 选关 / 音效。
--- 由宿主在 BattleTriPage.draw 之后调用——保证按钮位于一切战斗背景/框柱之上（避免穿帮）。
--- 任一模态对话框打开时不绘制（弹窗压暗与本体在 draw 内已覆盖按钮位）。
--- 已解锁的其他队伍与第一行保持同一套按钮。
function BattleTriPage.drawHud(vg, logicalW, logicalH)
    if not isOpen_ then return end
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen() then
        return
    end
    local BattleScene = require("ui.battle.scene.BattleScene")
    local ix1, iy1, iw1, ih1 = interiorRect(1, logicalW, logicalH)
    local hudScale = 0.44  -- 原 0.55 的约 80%
    local hudPad = 4
    local hudHalf = 29
    local hudY = iy1 + hudHalf + 2
    local hudGap = 58
    local hudShift = 17  -- 约 0.3 个按钮宽，避免贴出右框
    local showSpeed = BattleScene.isSpeedButtonVisible()
    local cursorX = ix1 + iw1 - hudPad - hudHalf - hudShift
    local hudSpeedX, hudSweepX, hudStatsX, hudStageX, hudSoundX
    if showSpeed then
        hudSpeedX = cursorX
        cursorX = cursorX - hudGap
    end
    hudSweepX = cursorX
    cursorX = cursorX - hudGap
    hudStatsX = cursorX
    cursorX = cursorX - hudGap
    hudStageX = cursorX
    cursorX = cursorX - hudGap
    hudSoundX = cursorX
    if showSpeed then
        nvgSave(vg)
        nvgTranslate(vg, hudSpeedX, hudY)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -987, -311)
        BattleScene.drawSpeedButton(vg)
        nvgRestore(vg)
    end
    do
        nvgSave(vg)
        nvgTranslate(vg, hudSweepX, hudY)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -971, -2115)
        SweepDialog.drawButton(vg)
        nvgRestore(vg)
    end
    do
        nvgSave(vg)
        nvgTranslate(vg, hudStatsX, hudY)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -815, -2115)
        DamageStatsPanel.drawButton(vg)
        nvgRestore(vg)
    end
    do
        nvgSave(vg)
        nvgTranslate(vg, hudStageX, hudY)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -659, -2115)
        StageSelectDialog.drawButton(vg)
        nvgRestore(vg)
    end
    do
        nvgSave(vg)
        nvgTranslate(vg, hudSoundX, hudY)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -503, -2115)
        SoundToggle.drawButton(vg, 1)
        nvgRestore(vg)
    end

    -- 其余已解锁队伍与第一行使用同一组按钮。
    local unlocked = ExpTable.getUnlockedTeamCount(GameState.getLevel())
    for row = 2, math.min(COL_COUNT, unlocked) do
        local ix, iy, iw = interiorRect(row, logicalW, logicalH)
        local rowY = iy + hudHalf + 2
        local rowCursor = ix + iw - hudPad - hudHalf - hudShift
        local rowSpeedX, rowSweepX, rowStatsX, rowStageX, rowSoundX
        if showSpeed then
            rowSpeedX = rowCursor
            rowCursor = rowCursor - hudGap
        end
        rowSweepX = rowCursor
        rowCursor = rowCursor - hudGap
        rowStatsX = rowCursor
        rowCursor = rowCursor - hudGap
        rowStageX = rowCursor
        rowCursor = rowCursor - hudGap
        rowSoundX = rowCursor
        if showSpeed then
            nvgSave(vg)
            nvgTranslate(vg, rowSpeedX, rowY)
            nvgScale(vg, hudScale, hudScale)
            nvgTranslate(vg, -987, -311)
            BattleScene.drawSpeedButton(vg)
            nvgRestore(vg)
        end
        nvgSave(vg)
        nvgTranslate(vg, rowSweepX, rowY)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -971, -2115)
        SweepDialog.drawButton(vg)
        nvgRestore(vg)
        nvgSave(vg)
        nvgTranslate(vg, rowStatsX, rowY)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -815, -2115)
        DamageStatsPanel.drawButton(vg)
        nvgRestore(vg)
        nvgSave(vg)
        nvgTranslate(vg, rowStageX, rowY)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -659, -2115)
        StageSelectDialog.drawButton(vg)
        nvgRestore(vg)
        nvgSave(vg)
        nvgTranslate(vg, rowSoundX, rowY)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -503, -2115)
        SoundToggle.drawButton(vg, row)
        nvgRestore(vg)
    end
end

--- 输入（窗口坐标）；返回 true 表示消费
---@param wx number
---@param wy number
---@return boolean
function BattleTriPage.handleInput(wx, wy)
    if not isOpen_ then return false end

    -- 全窗扫荡弹窗优先于装备背包覆盖层处理
    if SweepDialog.isOpen() then
        local logicalW, logicalH = region.w, region.h
        local fit = math.min(logicalW / 1080, logicalH / 2400) * 2
        local dx = (wx - logicalW * 0.5) / fit + 540
        local dy = (wy - logicalH * 0.5) / fit + 1195
        SweepDialog.handleInput(dx, dy)
        return true
    end

    -- 装备背包覆盖战斗区：窗口坐标映射到背包设计空间
    if EquipmentBag.shouldBattleOverlay() and EquipmentBag.hasOverlayRegion() then
        -- 装备详情弹窗按竖版设计空间铺在覆盖矩形内，需单独换算
        local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
        if EquipmentDetail.isOpen() then
            local dx, dy = EquipmentBag.overlayToDetail(wx, wy)
            return EquipmentDetail.handleInput(dx, dy)
        end
        local dx, dy = EquipmentBag.overlayToDesign(wx, wy)
        return EquipmentBag.handleInput(dx, dy)
    end

    local logicalH = region.h
    local logicalW = region.w
    local ix1, iy1, iw1, ih1 = interiorRect(1, logicalW, logicalH)

    -- [常驻] 行1 的获得弹窗：交给 RewardPopup 统一处理，保留同帧保护
    -- （逐个获得未结束时点击只跳过动画）。此前直接 close() 会让通关后
    -- 随手一点就把刚弹出的奖励关掉，看起来像「结算页不显示」。
    if RewardPopup.currentRowTag() then
        RewardPopup.handleInputRegion(wx, wy, ix1, iy1, iw1, ih1)
        return true
    end
    local bs = require("ui.battle.scene.BattleScene")

    -- 对话框打开: 逆映射到设计空间（与 2 倍渲染缩放一致）
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen() then
        local dx, dy = dialogToDesign(wx, wy)
        if SweepDialog.isOpen() then SweepDialog.handleInput(dx, dy) end
        if DamageStatsPanel.isOpen() then DamageStatsPanel.handleInput(dx, dy) end
        if StageSelectDialog.isOpen() then StageSelectDialog.handleInput(dx, dy) end
        return true
    end

    local hudScale = 0.44  -- 与 drawHud 一致，约原尺寸 80%
    local hudPad = 4
    local hudHalf = 29
    local hudY = iy1 + hudHalf + 2
    local hudGap = 58
    local hudShift = 17  -- 与 drawHud 一致
    local showSpeed = bs.isSpeedButtonVisible()
    local cursorX = ix1 + iw1 - hudPad - hudHalf - hudShift
    local hudSpeedX, hudSweepX, hudStatsX, hudStageX, hudSoundX
    if showSpeed then
        hudSpeedX = cursorX
        cursorX = cursorX - hudGap
    end
    hudSweepX = cursorX
    cursorX = cursorX - hudGap
    hudStatsX = cursorX
    cursorX = cursorX - hudGap
    hudStageX = cursorX
    cursorX = cursorX - hudGap
    hudSoundX = cursorX
    local hitW, hitH = 65 * hudScale, 72 * hudScale
    if showSpeed and math.abs(wx - hudSpeedX) <= hitW and math.abs(wy - hudY) <= hitH then
        bs.handleSpeedButtonInput(987 + (wx - hudSpeedX) / hudScale, 311 + (wy - hudY) / hudScale)
        return true
    end
    if math.abs(wx - hudSweepX) <= hitW and math.abs(wy - hudY) <= hitH then
        SweepDialog.handleButtonInput(971 + (wx - hudSweepX) / hudScale, 2115 + (wy - hudY) / hudScale)
        return true
    end
    if math.abs(wx - hudStatsX) <= hitW and math.abs(wy - hudY) <= hitH then
        DamageStatsPanel.handleButtonInput(815 + (wx - hudStatsX) / hudScale, 2115 + (wy - hudY) / hudScale, 1)
        return true
    end
    if math.abs(wx - hudStageX) <= hitW and math.abs(wy - hudY) <= hitH then
        StageSelectDialog.handleButtonInput(659 + (wx - hudStageX) / hudScale, 2115 + (wy - hudY) / hudScale)
        return true
    end
    if math.abs(wx - hudSoundX) <= hitW and math.abs(wy - hudY) <= hitH then
        SoundToggle.handleButtonInput(1)
        return true
    end

    -- 其余已解锁队伍与第一行使用同一组按钮。
    local unlocked = ExpTable.getUnlockedTeamCount(GameState.getLevel())
    for row = 2, math.min(COL_COUNT, unlocked) do
        local ix, iy, iw = interiorRect(row, logicalW, logicalH)
        local rowY = iy + hudHalf + 2
        local rowCursor = ix + iw - hudPad - hudHalf - hudShift
        local rowSpeedX, rowSweepX, rowStatsX, rowStageX, rowSoundX
        if showSpeed then
            rowSpeedX = rowCursor
            rowCursor = rowCursor - hudGap
        end
        rowSweepX = rowCursor
        rowCursor = rowCursor - hudGap
        rowStatsX = rowCursor
        rowCursor = rowCursor - hudGap
        rowStageX = rowCursor
        rowCursor = rowCursor - hudGap
        rowSoundX = rowCursor
        if showSpeed and math.abs(wx - rowSpeedX) <= hitW and math.abs(wy - rowY) <= hitH then
            bs.handleSpeedButtonInput(987 + (wx - rowSpeedX) / hudScale, 311 + (wy - rowY) / hudScale)
            return true
        end
        if math.abs(wx - rowSweepX) <= hitW and math.abs(wy - rowY) <= hitH then
            SweepDialog.handleButtonInput(971 + (wx - rowSweepX) / hudScale, 2115 + (wy - rowY) / hudScale)
            return true
        end
        if math.abs(wx - rowStatsX) <= hitW and math.abs(wy - rowY) <= hitH then
            DamageStatsPanel.handleButtonInput(815 + (wx - rowStatsX) / hudScale, 2115 + (wy - rowY) / hudScale, row)
            return true
        end
        if math.abs(wx - rowStageX) <= hitW and math.abs(wy - rowY) <= hitH then
            StageSelectDialog.handleButtonInput(659 + (wx - rowStageX) / hudScale, 2115 + (wy - rowY) / hudScale, row)
            return true
        end
        if math.abs(wx - rowSoundX) <= hitW and math.abs(wy - rowY) <= hitH then
            SoundToggle.handleButtonInput(row)
            return true
        end
    end

    return true  -- 战斗区吞掉其余点击（自动战斗）
end

---@param wx number
---@param wy number
---@return boolean
function BattleTriPage.handleDragBegin(wx, wy)
    if not isOpen_ then return false end
    if SweepDialog.isOpen() then
        local dx, dy = dialogToDesign(wx, wy)
        return SweepDialog.handleDragBegin(dx, dy)
    end
    if StageSelectDialog.isOpen() then
        local dx, dy = dialogToDesign(wx, wy)
        return StageSelectDialog.handleDragBegin(dx, dy)
    end
    if EquipmentBag.shouldBattleOverlay() and EquipmentBag.hasOverlayRegion() then
        local dx, dy = EquipmentBag.overlayToDesign(wx, wy)
        EquipmentBag.handleDragBegin(dx, dy)
        return true
    end
    return false
end

---@param wx number
---@param wy number
---@return boolean
function BattleTriPage.handleDragMove(wx, wy)
    if not isOpen_ then return false end
    if SweepDialog.isOpen() then
        local dx, dy = dialogToDesign(wx, wy)
        return SweepDialog.handleDragMove(dx, dy)
    end
    if StageSelectDialog.isOpen() then
        local dx, dy = dialogToDesign(wx, wy)
        return StageSelectDialog.handleDragMove(dx, dy)
    end
    if EquipmentBag.shouldBattleOverlay() and EquipmentBag.hasOverlayRegion() then
        local dx, dy = EquipmentBag.overlayToDesign(wx, wy)
        EquipmentBag.handleDragMove(dx, dy)
        return true
    end
    return false
end

---@param wx number
---@param wy number
---@return boolean
function BattleTriPage.handleDragEnd(wx, wy)
    if not isOpen_ then return false end
    if SweepDialog.isOpen() then return SweepDialog.handleDragEnd() end
    if StageSelectDialog.isOpen() then return StageSelectDialog.handleDragEnd() end
    if EquipmentBag.shouldBattleOverlay() and EquipmentBag.hasOverlayRegion() then
        local dx, dy = EquipmentBag.overlayToDesign(wx, wy)
        EquipmentBag.handleDragEnd(dx, dy)
        return true
    end
    return false
end

---@param wheel number
---@param wx number|nil 窗口坐标
---@param wy number|nil
---@return boolean
function BattleTriPage.handleScroll(wheel, wx, wy)
    if not isOpen_ then return false end
    if StageSelectDialog.isOpen() then
        if wx and wy then
            local dx, dy = dialogToDesign(wx, wy)
            return StageSelectDialog.handleScroll(wheel, dx, dy)
        end
        return true
    end
    if not (EquipmentBag.shouldBattleOverlay() and EquipmentBag.hasOverlayRegion()) then
        return false
    end
    if not EquipmentBag.hitOverlayWindow(wx, wy) then return false end
    local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
    if EquipmentDetail.isOpen() then
        local dx, dy = EquipmentBag.overlayToDetail(wx, wy)
        if EquipmentDetail.handleScroll(wheel, dx, dy) then return true end
    end
    EquipmentBag.scrollByWheel(wheel)
    return true
end

---@param wx number
---@param wy number
---@return boolean
function BattleTriPage.handleRightClick(wx, wy)
    if not isOpen_ then return false end
    if EquipmentBag.shouldBattleOverlay() and EquipmentBag.hasOverlayRegion() then
        local dx, dy = EquipmentBag.overlayToDesign(wx, wy)
        return EquipmentBag.handleRightClick(dx, dy)
    end
    return false
end

return BattleTriPage
