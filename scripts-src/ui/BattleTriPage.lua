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
function BattleTriPage.init(vg)
    if inited then return end
    inited = true
    BattleView.init(vg)
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
            })
        else
            local drv = drivers[row]
            if drv then
                drv.mount()
                BattleView.draw(vg, { allies = drv.allies, enemies = drv.enemies })
            else
                nvgBeginPath(vg)
                nvgRect(vg, 0, 0, rw, rowH)
                nvgFillColor(vg, nvgRGBA(16, 16, 24, 255))
                nvgFill(vg)
            end
        end
        nvgRestore(vg)

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
            nvgFillColor(vg, nvgRGBA(8, 8, 14, 205))
            nvgFill(vg)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local needLv = ExpTable.getTeamUnlockLevel(row)
            nvgFontSize(vg, 22)
            nvgFillColor(vg, nvgRGBA(165, 170, 190, 255))
            nvgText(vg, rx + rw * 0.5, ry0 + rowH * 0.5,
                string.format("冒险等级达到 %s 解锁", tostring(needLv or "?")))
        end
    end

    -- 返回按钮（区域左上）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, rx + 14, ry + 14, 100, 44, 9)
    nvgFillColor(vg, nvgRGBA(30, 34, 50, 235))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, rx + 14, ry + 14, 100, 44, 9)
    nvgStrokeColor(vg, nvgRGBA(120, 130, 160, 255))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(225, 230, 245, 255))
    nvgText(vg, rx + 64, ry + 37, "返 回")
end

--- 输入（区域本地坐标 lx=窗口X-region.x, ly=窗口Y-region.y）；返回 true 表示消费
---@param lx number
---@param ly number
---@return boolean
function BattleTriPage.handleInput(lx, ly)
    if not isOpen_ then return false end
    if lx >= 14 and lx <= 114 and ly >= 14 and ly <= 58 then
        BattleTriPage.close()
        return true
    end
    return true  -- 战斗区吞掉其余点击（自动战斗）
end

return BattleTriPage
