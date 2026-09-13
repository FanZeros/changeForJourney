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
local SweepDialog      = require("ui.SweepDialog")
local DamageStatsPanel = require("ui.DamageStatsPanel")

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
    imgL0      = nvgCreateImage(vg, "image/暗黑/L0_ui_bg.png", 0)
    imgL1[1]   = nvgCreateImage(vg, "image/暗黑/L1_row1_forest.png", 0)
    imgL1[2]   = nvgCreateImage(vg, "image/暗黑/L1_row2_bonefield.png", 0)
    imgL1[3]   = nvgCreateImage(vg, "image/暗黑/L1_row3_abyss.png", 0)
end

--- [三行并行] L0 整套大背景铺满窗口（左右面板 + 中段框体同源）
function BattleTriPage.drawL0(vg, logicalW, logicalH)
    BattleTriPage.init(vg)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logicalW, logicalH)
    nvgFillColor(vg, nvgRGBA(13, 11, 9, 255))   -- #0D0B09 兜底
    nvgFill(vg)
    if imgL0 and imgL0 >= 0 then
        local s = logicalH / 1080
        local w = 1920 * s
        local ox = (logicalW - w) * 0.5
        local paint = nvgImagePattern(vg, ox, 0, w, logicalH, 0, imgL0, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, ox, 0, w, logicalH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
end

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

--- 绘制战斗区（区域窗口坐标，由宿主传入；内部三行均分高度）
---@param vg any
---@param rx number 区域左上 X（窗口坐标）
---@param ry number 区域左上 Y
---@param rw number 区域宽（948）
---@param rh number 区域高（1080）
function BattleTriPage.draw(vg, rx, ry, rw, rh)
    if not isOpen_ then return end
    BattleTriPage.init(vg)
    BattleLayout.setMode("strip")
    region = { x = rx, y = ry, w = rw, h = rh }

    -- 底色
    nvgBeginPath(vg)
    nvgRect(vg, rx, ry, rw, rh)
    nvgFillColor(vg, nvgRGBA(10, 10, 16, 255))
    nvgFill(vg)

    -- [微调] 血月辉光：天幕带下缘溢光到行1顶部
    do
        local gx, gy = rx + rw * 0.54, ry - 6
        local glow = nvgRadialGradient(vg, gx, gy, 8, 190,
            nvgRGBA(224, 72, 72, 70), nvgRGBA(166, 30, 30, 0))
        nvgBeginPath(vg)
        nvgRect(vg, rx, ry, rw, 130)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, gx, ry + 2, 15)
        nvgFillColor(vg, nvgRGBA(224, 72, 72, 110))
        nvgFill(vg)
    end

    local BattleScene = require("ui.BattleScene")
    local CharacterPanel = require("ui.CharacterPanel")
    local unlocked = ExpTable.getUnlockedTeamCount(GameState.getLevel())
    local rowH = rh / COL_COUNT

    for row = 1, COL_COUNT do
        local ry0 = ry + (row - 1) * rowH
        -- 等比适配: 条带 948x360 → 区域内每行（宽高取小者，居中）
        local rowScale = math.min(rw / BattleLayout.STRIP_W, rowH / BattleLayout.STRIP_H)
        local drawW = BattleLayout.STRIP_W * rowScale
        local drawH = BattleLayout.STRIP_H * rowScale
        nvgSave(vg)
        nvgScissor(vg, rx, ry0, rw, rowH)
        nvgTranslate(vg, rx + (rw - drawW) * 0.5, ry0 + (rowH - drawH) * 0.5)
        nvgScale(vg, rowScale, rowScale)

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
            }, imgL1[1])
        else
            local drv = drivers[row]
            if drv then
                drv.mount()
                BattleView.draw(vg, { allies = drv.allies, enemies = drv.enemies }, imgL1[row])
            else
                -- [微调] 锁定行也铺 L1 背景（挂载空状态, 防止行1 瞬态串染）
                BattleTriPage.mountEmpty()
                BattleView.draw(vg, { allies = {}, enemies = {} }, imgL1[row])
            end
        end
        nvgRestore(vg)

        -- [三行并行] 获得展示归属本行: 行1 的首通奖励弹窗卡在行内显示
        if row == 1 then
            RewardPopup.drawRegion(vg, rx, ry0, rw, rowH, 1)
        end

        -- 行头标签（条带坐标转窗口坐标绘制）
        local headY = ry0 + 24
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local stageText
        if row == 1 then
            stageText = string.format("队1 · 第%s关", tostring(BattleScene.getStageId() or "?"))
        elseif drivers[row] then
            stageText = string.format("队%d · 第%s关 · 击杀%d", row,
                tostring(drivers[row].stageId), drivers[row].kills)
        else
            stageText = string.format("队%d", row)
        end
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rx + 128, headY - 17, 220, 34, 8)
        nvgFillColor(vg, nvgRGBA(16, 18, 28, 200))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(215, 222, 240, 255))
        nvgText(vg, rx + 142, headY, stageText)

        -- 未解锁行遮罩（只提示解锁等级）
        if row > unlocked then
            nvgBeginPath(vg)
            nvgRect(vg, rx, ry0, rw, rowH)
            nvgFillColor(vg, nvgRGBA(8, 8, 14, 160))
            nvgFill(vg)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local needLv = ExpTable.getTeamUnlockLevel(row)
            nvgFontSize(vg, 22)
            nvgFillColor(vg, nvgRGBA(165, 170, 190, 255))
            nvgText(vg, rx + rw * 0.5, ry0 + rowH * 0.5,
                string.format("冒险等级达到 %s 解锁", tostring(needLv or "?")))
        end
    end


    -- [暗黑替换] 骨质分隔条: 行与行交界（骨白窄条 + 中央纹章）
    for i = 1, COL_COUNT - 1 do
        local sy = ry + i * rowH
        nvgBeginPath(vg)
        nvgRect(vg, rx + rw * 0.12, sy - 4, rw * 0.76, 8)
        nvgFillColor(vg, nvgRGBA(216, 201, 163, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, rx + rw * 0.5, sy, 11)
        nvgFillColor(vg, nvgRGBA(201, 151, 59, 230))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, rx + rw * 0.5, sy, 11)
        nvgStrokeColor(vg, nvgRGBA(13, 11, 9, 255))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)
    end

    -- [行1 HUD] 战斗功能按钮（区域坐标; 速度/扫荡/统计复用原绘制重定位+缩放）
    local ry1 = ry
    local rowH1 = rh / COL_COUNT
    local hudScale = 0.55   -- HUD 按钮缩放（原按钮 130x144 对行高过大）
    -- 速度（右上; 原设计中心 987,311）
    do
        local tx, ty = rx + rw - 42, ry1 + 26
        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -987, -311)
        BattleScene.drawSpeedButton(vg)
        nvgRestore(vg)
    end
    -- 扫荡（右下; 原中心 971,2115）
    do
        local tx, ty = rx + rw - 40, ry1 + rowH1 - 34
        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -971, -2115)
        SweepDialog.drawButton(vg)
        nvgRestore(vg)
    end
    -- 统计（扫荡左侧; 原中心 815,2115）
    do
        local tx, ty = rx + rw - 116, ry1 + rowH1 - 34
        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        nvgScale(vg, hudScale, hudScale)
        nvgTranslate(vg, -815, -2115)
        DamageStatsPanel.drawButton(vg)
        nvgRestore(vg)
    end
    -- 后退/前进（行头右侧小按钮）
    local navY = ry1 + 24
    for ni = 1, 2 do
        local nx = rx + rw * 0.5 + 130 + (ni - 1) * 62
        nvgBeginPath(vg)
        nvgRoundedRect(vg, nx - 27, navY - 17, 54, 34, 8)
        nvgFillColor(vg, nvgRGBA(30, 34, 50, 225))
        nvgFill(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(225, 230, 245, 255))
        nvgText(vg, nx, navY, ni == 1 and "◀" or "▶", nil)
    end

    -- [对话框覆盖] 扫荡/统计面板打开时等比覆盖战斗区
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() then
        local fit = math.min(rw / 1080, rh / 960)
        nvgSave(vg)
        nvgTranslate(vg, rx + rw * 0.5, ry + rh * 0.5)
        nvgScale(vg, fit, fit)
        nvgTranslate(vg, -540, -1195)
        if SweepDialog.isOpen() then SweepDialog.draw(vg) end
        if DamageStatsPanel.isOpen() then DamageStatsPanel.draw(vg) end
        nvgRestore(vg)
    end
end

--- 输入（区域本地坐标 lx=窗口X-region.x, ly=窗口Y-region.y）；返回 true 表示消费
---@param lx number
---@param ly number
---@return boolean
function BattleTriPage.handleInput(lx, ly)
    if not isOpen_ then return false end
    -- [常驻] 点击行内任意处可关闭归属本行的获得弹窗
    if RewardPopup.currentRowTag() then
        RewardPopup.close()
        return true
    end

    local rowH1 = region.h / COL_COUNT
    local bs = require("ui.BattleScene")

    -- 对话框打开: 坐标逆映射到设计空间, 交给对话框处理
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() then
        local fit = math.min(region.w / 1080, region.h / 960)
        local dx = (lx - region.w * 0.5) / fit + 540
        local dy = (ly - region.h * 0.5) / fit + 1195
        if SweepDialog.isOpen() then SweepDialog.handleInput(dx, dy) end
        if DamageStatsPanel.isOpen() then DamageStatsPanel.handleInput(dx, dy) end
        return true
    end

    -- 速度（右上; 命中范围随缩放, 差值除回缩放后交给原判定）
    local hudScale = 0.55
    local tx, ty = region.w - 42, 26
    if math.abs(lx - tx) <= 65 * hudScale and math.abs(ly - ty) <= 71.5 * hudScale then
        bs.handleSpeedButtonInput(987 + (lx - tx) / hudScale, 311 + (ly - ty) / hudScale)
        return true
    end
    -- 扫荡（右下）
    tx, ty = region.w - 40, rowH1 - 34
    if math.abs(lx - tx) <= 65 * hudScale and math.abs(ly - ty) <= 72 * hudScale then
        SweepDialog.handleButtonInput(971 + (lx - tx) / hudScale, 2115 + (ly - ty) / hudScale)
        return true
    end
    -- 统计
    tx, ty = region.w - 116, rowH1 - 34
    if math.abs(lx - tx) <= 65 * hudScale and math.abs(ly - ty) <= 72 * hudScale then
        DamageStatsPanel.handleButtonInput(815 + (lx - tx) / hudScale, 2115 + (ly - ty) / hudScale)
        return true
    end
    -- 后退 / 前进（行头右侧）
    local nx1 = region.w * 0.5 + 130
    local nx2 = nx1 + 62
    if ly >= 7 and ly <= 41 then
        if lx >= nx1 - 27 and lx <= nx1 + 27 then
            bs.prevStage()
            return true
        elseif lx >= nx2 - 27 and lx <= nx2 + 27 then
            bs.nextStage()
            return true
        end
    end

    return true  -- 战斗区吞掉其余点击（自动战斗）
end

return BattleTriPage
