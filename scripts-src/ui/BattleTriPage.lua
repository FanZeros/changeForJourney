-- ============================================================================
-- BattleTriPage - 三栏并行战斗页（Phase 3 / 总 16:9 = 1920x1080）
-- 布局: 三栏各 640x1080，每栏一场战斗（左4 vs 右4 列阵设计稿 1080x1830 带
--       等比缩放约 0.59 恰好填满栏高）
--   栏1 = 队1 = BattleScene 全引擎（完整关卡进度/首通/掉落，零改动复用）
--   栏2/3 = BattleTriDriver 轻量驱动（自动战斗/击杀奖励回调/通关推进）
--   未解锁栏: 暗罩 + 解锁等级 + 该队编队预览
-- 集成: Standalone HORIZON_MODE 下 tab3 由本页替换；BackToPanels() 返回三联经营。
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

-- ---- 布局参数（设计参数可调）----
local TOTAL_W, TOTAL_H = 1920, 1080      -- 总画布 16:9
local COL_W = 640                        -- 单栏宽（调它即调三栏占比）
local COL_COUNT = ExpTable.TEAM_COUNT or 3
local FIELD_BAND_H = 1830                -- 战场带高（BattleView 同步）
local VIEW_SCALE = TOTAL_H / FIELD_BAND_H        -- 0.5902
local VIEW_W = 1080 * VIEW_SCALE                 -- ≈637.6

-- ---- 状态 ----
local isOpen_ = false
local inited = false
local drivers = {}        -- [2]/[3] = BattleTriDriver
local triOnKill = nil     -- function(data)（由宿主注入，与 BattleScene.onEnemyKill 同构）

--- 击杀奖励回调注入（宿主与 BattleScene.setOnEnemyKill 同源）
function BattleTriPage.setOnKill(cb) triOnKill = cb end

function BattleTriPage.isOpen() return isOpen_ end

--- 打开三栏页（懒建驱动器；队2/3 已解锁则自动开战）
function BattleTriPage.open()
    isOpen_ = true
    local CharacterPanel = require("ui.CharacterPanel")
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

--- 返回三联经营面板
function BattleTriPage.close() isOpen_ = false end

--- 幂等初始化（贴图）
function BattleTriPage.init(vg)
    if inited then return end
    inited = true
    BattleView.init(vg)
end

--- 每帧更新: 栏1 走 BattleScene 全引擎（default 状态），栏2/3 走各自驱动
function BattleTriPage.update(dt)
    if not isOpen_ then return end
    -- 回到 default 状态供 BattleScene 使用
    BattleCombat.mount(nil)
    ProjectileSystem.mount(nil)
    TM.mount(nil)
    TAL.mount(nil)
    BattleEffects.mount(nil)
    SEM.mount(nil)
    local BattleScene = require("ui.BattleScene")
    BattleScene.update(dt)
    -- 栏2/3
    for t = 2, COL_COUNT do
        local drv = drivers[t]
        if drv then drv:update(dt) end
    end
end

--- 绘制整页（窗口逻辑坐标 1920x1080）
---@param vg any
---@param logicalW number 窗口逻辑宽（letterbox 适配）
---@param logicalH number 窗口逻辑高
function BattleTriPage.draw(vg, logicalW, logicalH)
    if not isOpen_ then return end
    BattleTriPage.init(vg)

    -- 适配: 窗口 → 1920x1080 letterbox
    local s = math.min(logicalW / TOTAL_W, logicalH / TOTAL_H)
    local ox = (logicalW - TOTAL_W * s) * 0.5
    local oy = (logicalH - TOTAL_H * s) * 0.5

    nvgSave(vg)
    nvgTranslate(vg, ox, oy)
    nvgScale(vg, s, s)

    -- 底色
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, TOTAL_W, TOTAL_H)
    nvgFillColor(vg, nvgRGBA(10, 10, 16, 255))
    nvgFill(vg)

    local BattleScene = require("ui.BattleScene")
    local CharacterPanel = require("ui.CharacterPanel")
    local unlocked = ExpTable.getUnlockedTeamCount(GameState.getLevel())

    for col = 1, COL_COUNT do
        local x0 = (col - 1) * COL_W
        nvgSave(vg)
        -- 栏内视口: 1080 宽战场带缩放 VIEW_SCALE，垂直方向平移到战场带顶
        nvgScissor(vg, x0, 0, COL_W, TOTAL_H)
        local padX = (COL_W - VIEW_W) * 0.5
        nvgTranslate(vg, x0 + padX, 0)
        nvgScale(vg, VIEW_SCALE, VIEW_SCALE)
        nvgTranslate(vg, 0, -BattleLayout.FIELD_TOP)

        if col == 1 then
            -- 栏1: BattleScene 的战场（default 状态）
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
            local drv = drivers[col]
            if drv then
                drv.mount()
                BattleView.draw(vg, { allies = drv.allies, enemies = drv.enemies })
            end
        end
        nvgRestore(vg)

        -- 栏头: 队伍标签 + 关卡进度
        local headY = 34
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 26)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local stageText
        if col == 1 then
            stageText = string.format("队1 · 第%s关", tostring(BattleScene.getStageId() or "?"))
        elseif drivers[col] then
            stageText = string.format("队%d · 第%s关 · 击杀%d", col, tostring(drivers[col].stageId), drivers[col].kills)
        else
            stageText = string.format("队%d", col)
        end
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x0 + COL_W * 0.5 - 130, headY - 20, 260, 40, 10)
        nvgFillColor(vg, nvgRGBA(16, 18, 28, 200))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(220, 228, 245, 255))
        nvgText(vg, x0 + COL_W * 0.5, headY, stageText)

        -- 未解锁遮罩
        if col > unlocked then
            nvgBeginPath(vg)
            nvgRect(vg, x0, 0, COL_W, TOTAL_H)
            nvgFillColor(vg, nvgRGBA(8, 8, 14, 215))
            nvgFill(vg)
            local needLv = ExpTable.getTeamUnlockLevel(col)
            nvgFontSize(vg, 30)
            nvgFillColor(vg, nvgRGBA(200, 205, 220, 255))
            nvgText(vg, x0 + COL_W * 0.5, TOTAL_H * 0.42, string.format("队%d 未解锁", col))
            nvgFontSize(vg, 24)
            nvgFillColor(vg, nvgRGBA(150, 155, 175, 255))
            nvgText(vg, x0 + COL_W * 0.5, TOTAL_H * 0.42 + 46,
                string.format("冒险等级达到 %s 解锁", tostring(needLv or "?")))
            -- 该队编队预览（已配置人数）
            local counts = CharacterPanel.getTeamOccupiedCounts()
            nvgText(vg, x0 + COL_W * 0.5, TOTAL_H * 0.42 + 92,
                    string.format("已编队 %d/%d 人", counts[col] or 0, 4))
        end
    end

    -- 返回按钮（左上）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 14, 14, 108, 48, 10)
    nvgFillColor(vg, nvgRGBA(30, 34, 50, 235))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 14, 14, 108, 48, 10)
    nvgStrokeColor(vg, nvgRGBA(120, 130, 160, 255))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(225, 230, 245, 255))
    nvgText(vg, 68, 39, "返 回")

    nvgRestore(vg)
end

--- 输入（窗口逻辑坐标）；返回 true 表示消费
---@param wx number
---@param wy number
---@return boolean
function BattleTriPage.handleInput(wx, wy)
    if not isOpen_ then return false end
    -- 返回按钮命中（窗口即 1920x1080 设计，无需逆变换——由调用方保证比例）
    if wx >= 14 and wx <= 122 and wy >= 14 and wy <= 62 then
        BattleTriPage.close()
        return true
    end
    return true  -- 三栏页吞掉其余点击（战斗自动进行）
end

return BattleTriPage
