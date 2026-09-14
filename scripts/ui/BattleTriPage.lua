-- ============================================================================
-- BattleTriPage - 三行并行战斗（Phase 3 修正版）
-- 布局: 战斗区 = 中段区域（Standalone 传入 486,0,948,1080，左右经营/角色面板
--       保持原样），纵向堆叠三行战斗（行高 = rh/3 ≈ 360）:
--   行1 = 队1 = BattleScene 全引擎（完整关卡进度/首通/掉落，零改动复用）
--   行2/3 = BattleTriDriver 轻量驱动（自动战斗/击杀奖励回调/通关推进）
--   未解锁行: 暗罩 + 解锁等级 + 该队编队预览；返回按钮退出战斗区
-- 每行内 8 卡单线: 我方 4 张在左半段、敌方 4 张在右半段（BattleLayout strip 模式）
-- ============================================================================
local BattleLayout = require("core.BattleLayout")
local BattleView   = require("ui.BattleView")
local BattleCombat = require("ui.BattleCombat")
local ProjectileSystem = require("ui.ProjectileSystem")
local TM               = require("systems.ThreatManager")
local TAL              = require("systems.TalentManager")
local BattleEffects    = require("ui.BattleEffects")
local SEM              = require("systems.StatusEffectManager")
local ExpTable     = require("config.ExpTable")
local GameState    = require("core.GameState")
local RewardPopup  = require("ui.RewardPopup")
local SweepDialog       = require("ui.SweepDialog")
local DamageStatsPanel  = require("ui.DamageStatsPanel")
local StageSelectDialog = require("ui.StageSelectDialog")
local EquipmentBag      = require("ui.EquipmentBag")
local StageConfig       = require("config.StageConfig")

local function stageDisplayName(stageId)
    local entry = stageId and StageConfig.getStage(tonumber(stageId))
    return (entry and entry.name) or tostring(stageId or "?")
end

local BattleTriPage = {}

local COL_COUNT = ExpTable.TEAM_COUNT or 3

-- ---- 状态 ----
local isOpen_ = false
local inited = false
local drivers = {}        -- [2]/[3] = BattleTriDriver
local triOnKill = nil     -- function(data)（由宿主注入，与 BattleScene.onEnemyKill 同构）
local region = { x = 486, y = 0, w = 948, h = 1080 }  -- 战斗区（窗口坐标）

--- 击杀奖励回调注入（宿主与 BattleScene.setOnEnemyKill 同源）
function BattleTriPage.setOnKill(cb) triOnKill = cb end

function BattleTriPage.isOpen() return isOpen_ end

--- 打开三行战斗（懒建驱动器；已解锁队伍自动开战）
function BattleTriPage.open()
    if isOpen_ then return end
    isOpen_ = true
    local unlocked = ExpTable.getUnlockedTeamCount(GameState.getLevel())
    for t = 2, COL_COUNT do
        if unlocked >= t and not drivers[t] then
            local Driver = require("ui.BattleTriDriver")
            local drv = Driver.new(t)
            drv.onKill = function(data)
                if triOnKill then triOnKill(data) end
            end
            drv:start(1)
            drivers[t] = drv
        end
    end
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
    imgL0      = nvgCreateImage(vg, "image/暗黑/L0_ui_bg_v2.png", 0)
    imgL1[1]   = nvgCreateImage(vg, "image/暗黑/L1_row1_forest.png", 0)
    imgL1[2]   = nvgCreateImage(vg, "image/暗黑/L1_row2_bonefield.png", 0)
    imgL1[3]   = nvgCreateImage(vg, "image/暗黑/L1_row3_abyss.png", 0)
    StageSelectDialog.init(vg)
end

--- [三行并行] L0 整套大背景铺满窗口（左右面板 + 中段框体同源）

--- 每帧更新: 行1 走 BattleScene 全引擎（default 状态），行2/3 走各自驱动
function BattleTriPage.update(dt)
    if not isOpen_ then return end
    BattleLayout.setMode("strip")
    -- 回到 default 状态供 BattleScene 使用
    BattleCombat.mount(nil)
    ProjectileSystem.mount(nil)
    TM.mount(nil)
    TAL.mount(nil)
    BattleEffects.mount(nil)
    SEM.mount(nil)
    local BattleScene = require("ui.BattleScene")
    BattleScene.update(dt)
    for t = 2, COL_COUNT do
        local drv = drivers[t]
        if drv then drv:update(dt) end
    end
end
-- [暗黑替换 v2] L0 框体图（用户素材, 1672x941, 三个透明内矩形）+ 分层渲染
local PLATE_AR = 1672 / 941
-- 透明内矩形（归一化, 由图像 alpha 分析测得）
local INTERIORS = {
    { x0 = 0.2590, y0 = 0.0064, x1 = 0.6920, y1 = 0.3092 },
    { x0 = 0.2590, y0 = 0.3475, x1 = 0.6920, y1 = 0.6089 },
    { x0 = 0.2590, y0 = 0.6493, x1 = 0.6920, y1 = 0.9926 },
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
    local BattleScene = require("ui.BattleScene")
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
    BattleLayout.setMode("strip")
    region = { x = 0, y = 0, w = logicalW, h = logicalH }

    local BattleScene = require("ui.BattleScene")
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
            if row == 1 then
                BattleCombat.mount(nil)
                ProjectileSystem.mount(nil)
                TM.mount(nil)
                TAL.mount(nil)
                BattleEffects.mount(nil)
                SEM.mount(nil)
                BattleView.draw(vg, {
                    allies  = BattleScene.getAllies() or {},
                    enemies = BattleScene.getEnemies() or {},
                }, nil, true)
            else
                local drv = drivers[row]
                if drv then
                    drv.mount()
                    BattleView.draw(vg, { allies = drv.allies, enemies = drv.enemies }, nil, true)
                end
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
        if row == 1 then
            stageText = string.format("【小队1】%s", stageDisplayName(BattleScene.getStageId()))
        elseif drivers[row] then
            stageText = string.format("【小队%d】%s · 击杀%d", row,
                stageDisplayName(drivers[row].stageId), drivers[row].kills)
        else
            stageText = string.format("【小队%d】待解锁", row)
        end
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ix + 14, iy + 8, 360, 34, 8)
        nvgFillColor(vg, nvgRGBA(16, 18, 28, 200))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(215, 222, 240, 255))
        nvgText(vg, ix + 28, iy + 25, stageText, nil)

        -- 未解锁提示（行内居中）
        if row > unlocked then
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local needLv = ExpTable.getTeamUnlockLevel(row)
            nvgFontSize(vg, 44)
            nvgFillColor(vg, nvgRGBA(165, 170, 190, 255))
            nvgText(vg, ix + iw * 0.5, iy + ih * 0.5,
                string.format("冒险等级达到 %s 解锁", tostring(needLv or "?")), nil)
        end
    end

    -- [行1 HUD] 战斗功能按钮：选关 / 扫荡 / 统计 / 速度（同一套图标按钮）
    local ix1, iy1, iw1, ih1 = interiorRect(1, logicalW, logicalH)
    local hudScale = 0.55
    do
        local tx, ty = ix1 + iw1 - 42, iy1 + 26
        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -987, -311)
        BattleScene.drawSpeedButton(vg)
        nvgRestore(vg)
    end
    do
        local tx, ty = ix1 + iw1 - 194, iy1 + 26
        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -971, -2115)
        SweepDialog.drawButton(vg)
        nvgRestore(vg)
    end
    do
        local tx, ty = ix1 + iw1 - 118, iy1 + 26
        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -815, -2115)
        DamageStatsPanel.drawButton(vg)
        nvgRestore(vg)
    end
    do
        local tx, ty = ix1 + iw1 - 270, iy1 + 26
        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -659, -2115)
        StageSelectDialog.drawButton(vg)
        nvgRestore(vg)
    end

    -- [对话框覆盖] 选关/扫荡/统计面板（等比覆盖行1 内矩形）
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen() then
        local fit = math.min(iw1 / 1080, ih1 / 960)
        nvgSave(vg)
        nvgTranslate(vg, ix1 + iw1 * 0.5, iy1 + ih1 * 0.5)
        nvgScale(vg, fit, fit)
        nvgTranslate(vg, -540, -1195)
        if SweepDialog.isOpen() then SweepDialog.draw(vg) end
        if DamageStatsPanel.isOpen() then DamageStatsPanel.draw(vg) end
        if StageSelectDialog.isOpen() then StageSelectDialog.draw(vg) end
        nvgRestore(vg)
    end

    -- [三行并行] 获得弹窗归属行1
    RewardPopup.drawRegion(vg, ix1, iy1, iw1, ih1, 1)

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

--- 输入（窗口坐标）；返回 true 表示消费
---@param wx number
---@param wy number
---@return boolean
function BattleTriPage.handleInput(wx, wy)
    if not isOpen_ then return false end

    -- 装备背包覆盖战斗区：窗口坐标映射到背包设计空间
    if EquipmentBag.shouldBattleOverlay() and EquipmentBag.hasOverlayRegion() then
        local dx, dy = EquipmentBag.overlayToDesign(wx, wy)
        return EquipmentBag.handleInput(dx, dy)
    end

    -- [常驻] 点击行1 内任意处可关闭归属本行的获得弹窗
    if RewardPopup.currentRowTag() then
        RewardPopup.close()
        return true
    end

    local logicalH = region.h
    local logicalW = region.w
    local ix1, iy1, iw1, ih1 = interiorRect(1, logicalW, logicalH)
    local bs = require("ui.BattleScene")

    -- 对话框打开: 逆映射到设计空间
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen() then
        local fit = math.min(iw1 / 1080, ih1 / 960)
        local dx = (wx - ix1 - iw1 * 0.5) / fit + 540
        local dy = (wy - iy1 - ih1 * 0.5) / fit + 1195
        if SweepDialog.isOpen() then SweepDialog.handleInput(dx, dy) end
        if DamageStatsPanel.isOpen() then DamageStatsPanel.handleInput(dx, dy) end
        if StageSelectDialog.isOpen() then StageSelectDialog.handleInput(dx, dy) end
        return true
    end

    local hudScale = 0.55
    local tx, ty = ix1 + iw1 - 42, iy1 + 26
    if math.abs(wx - tx) <= 65 * hudScale and math.abs(wy - ty) <= 71.5 * hudScale then
        bs.handleSpeedButtonInput(987 + (wx - tx) / hudScale, 311 + (wy - ty) / hudScale)
        return true
    end
    tx, ty = ix1 + iw1 - 194, iy1 + 26
    if math.abs(wx - tx) <= 65 * hudScale and math.abs(wy - ty) <= 72 * hudScale then
        SweepDialog.handleButtonInput(971 + (wx - tx) / hudScale, 2115 + (wy - ty) / hudScale)
        return true
    end
    tx, ty = ix1 + iw1 - 118, iy1 + 26
    if math.abs(wx - tx) <= 65 * hudScale and math.abs(wy - ty) <= 72 * hudScale then
        DamageStatsPanel.handleButtonInput(815 + (wx - tx) / hudScale, 2115 + (wy - ty) / hudScale)
        return true
    end
    tx, ty = ix1 + iw1 - 270, iy1 + 26
    if math.abs(wx - tx) <= 65 * hudScale and math.abs(wy - ty) <= 72 * hudScale then
        StageSelectDialog.handleButtonInput(659 + (wx - tx) / hudScale, 2115 + (wy - ty) / hudScale)
        return true
    end

    return true  -- 战斗区吞掉其余点击（自动战斗）
end

---@param wx number
---@param wy number
---@return boolean
function BattleTriPage.handleDragBegin(wx, wy)
    if not isOpen_ then return false end
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
    if EquipmentBag.shouldBattleOverlay() and EquipmentBag.hasOverlayRegion() then
        local dx, dy = EquipmentBag.overlayToDesign(wx, wy)
        EquipmentBag.handleDragEnd(dx, dy)
        return true
    end
    return false
end

---@param wheel number
---@return boolean
function BattleTriPage.handleScroll(wheel)
    if not isOpen_ then return false end
    if EquipmentBag.shouldBattleOverlay() and EquipmentBag.hasOverlayRegion() then
        EquipmentBag.handleScroll(wheel)
        return true
    end
    return false
end

return BattleTriPage
