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
local StageConfig  = require("config.StageConfig")

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

-- ======================== [三行并行] 选关页面 ========================

local stageSel = { open = false, page = 0 }
local STAGE_SEL_COLS, STAGE_SEL_ROWS = 4, 4

function BattleTriPage.toggleStageSelect()
    stageSel.open = not stageSel.open
    stageSel.page = 0
end

--- 选关面板布局（含每页关卡格子）
local function stageSelectLayout(logicalW, logicalH)
    local BS = require("ui.BattleScene")
    local maxStage = BS.getMaxStageId() or 1
    local r1 = table.pack(interiorRect(1, logicalW, logicalH))
    local r3 = table.pack(interiorRect(COL_COUNT, logicalW, logicalH))
    local px, py = r1[1], r1[2]
    local pw, ph = r1[3], (r3[2] + r3[4]) - r1[2]
    local perPage = STAGE_SEL_COLS * STAGE_SEL_ROWS
    local cellW = (pw - 60 - (STAGE_SEL_COLS - 1) * 12) / STAGE_SEL_COLS
    local cellH = 54
    local gridTop = py + 64

    -- 收集实际存在的关卡 ID（4 位章节制, 从 101 起; ≤ 已解锁最大关）
    local SC = require("config.StageConfig")
    local existIds = {}
    local cur = 101
    local guard = 0
    while cur and cur <= maxStage and guard < 999 do
        guard = guard + 1
        if SC.getStage(cur) then existIds[#existIds + 1] = cur end
        local nxt = SC.getNextStageId and SC.getNextStageId(cur)
        if not nxt or nxt <= cur then break end
        cur = nxt
    end

    local maxPage = math.max(0, math.ceil(#existIds / perPage) - 1)
    local startIdx = stageSel.page * perPage
    local cells = {}
    for i = 1, perPage do
        local id = existIds[startIdx + i - 1]
        if id then
            local col, r = (i - 1) % STAGE_SEL_COLS, math.floor((i - 1) / STAGE_SEL_COLS)
            cells[#cells + 1] = {
                id = id,
                x = px + 30 + col * (cellW + 12),
                y = gridTop + r * (cellH + 10),
                w = cellW, h = cellH,
            }
        end
    end
    return { px = px, py = py, pw = pw, ph = ph, cells = cells,
             maxPage = maxPage, maxStage = maxStage, perPage = perPage,
             existCount = #existIds }
end

local function drawStageSelect(vg, logicalW, logicalH)
    if not stageSel.open then return end

    local BS = require("ui.BattleScene")
    local SC = require("config.StageConfig")
    local L = stageSelectLayout(logicalW, logicalH)

    -- 面板
    nvgBeginPath(vg)
    nvgRoundedRect(vg, L.px, L.py, L.pw, L.ph, 14)
    nvgFillColor(vg, nvgRGBA(12, 12, 20, 244))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, L.px, L.py, L.pw, L.ph, 14)
    nvgStrokeColor(vg, nvgRGBA(201, 151, 59, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
    nvgText(vg, L.px + L.pw * 0.5, L.py + 38, "选择关卡", nil)

    -- 关闭 ✕
    nvgBeginPath(vg)
    nvgRoundedRect(vg, L.px + L.pw - 36, L.py + 8, 28, 28, 6)
    nvgFillColor(vg, nvgRGBA(60, 40, 40, 235))
    nvgFill(vg)
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(230, 200, 200, 255))
    nvgText(vg, L.px + L.pw - 22, L.py + 22, "X", nil)

    -- 关卡格子
    local curStage = BS.getStageId()
    for _, c in ipairs(L.cells) do
        local unlocked = c.id <= L.maxStage
        local isCur = (c.id == curStage)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, c.x, c.y, c.w, c.h, 8)
        if isCur then
            nvgFillColor(vg, nvgRGBA(201, 151, 59, 235))
        elseif unlocked then
            nvgFillColor(vg, nvgRGBA(40, 44, 58, 235))
        else
            nvgFillColor(vg, nvgRGBA(22, 22, 30, 235))
        end
        nvgFill(vg)
        if isCur then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, c.x, c.y, c.w, c.h, 8)
            nvgStrokeColor(vg, nvgRGBA(240, 199, 94, 255))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if unlocked then
            nvgFillColor(vg, nvgRGBA(215, 222, 240, 255))
        else
            nvgFillColor(vg, nvgRGBA(110, 112, 125, 255))
        end
        local entry = SC.getStage(c.id)
        nvgText(vg, c.x + c.w * 0.5, c.y + c.h * 0.5,
            entry and entry.name or ("第" .. c.id .. "关"), nil)
    end

    -- 翻页
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
    nvgText(vg, L.px + 24, L.py + L.ph - 28, "上一页", nil)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(vg, L.px + L.pw - 24, L.py + L.ph - 28, "下一页", nil)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, L.px + L.pw * 0.5, L.py + L.ph - 28,
        string.format("第 %d / %d 页", stageSel.page + 1, L.maxPage + 1), nil)
end
BattleTriPage.drawStageSelect = drawStageSelect

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

    -- [行1 HUD] 战斗功能按钮（速度/扫荡/统计 + 后退/前进）
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
    local navY = iy1 + 24
    for ni = 1, 2 do
        local nx = ix1 + 260 + (ni - 1) * 62
        nvgBeginPath(vg)
        nvgRoundedRect(vg, nx - 27, navY - 17, 54, 34, 8)
        nvgFillColor(vg, stageSel.open and nvgRGBA(201, 151, 59, 235) or nvgRGBA(30, 34, 50, 225))
        nvgFill(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(225, 230, 245, 255))
        nvgText(vg, nx, navY, "关", nil)
    end

    -- [对话框覆盖] 扫荡/统计面板（等比覆盖行1 内矩形）
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() then
        local fit = math.min(iw1 / 1080, ih1 / 960)
        nvgSave(vg)
        nvgTranslate(vg, ix1 + iw1 * 0.5, iy1 + ih1 * 0.5)
        nvgScale(vg, fit, fit)
        nvgTranslate(vg, -540, -1195)
        if SweepDialog.isOpen() then SweepDialog.draw(vg) end
        if DamageStatsPanel.isOpen() then DamageStatsPanel.draw(vg) end
        nvgRestore(vg)
    end

    -- [三行并行] 选关页面（覆盖中段, UI 层最上）
    BattleTriPage.drawStageSelect(vg, logicalW, logicalH)

    -- [三行并行] 获得弹窗归属行1
    RewardPopup.drawRegion(vg, ix1, iy1, iw1, ih1, 1)
end

--- 输入（窗口坐标）；返回 true 表示消费
---@param wx number
---@param wy number
---@return boolean
function BattleTriPage.handleInput(wx, wy)
    if not isOpen_ then return false end
    -- [三行并行] 选关页输入
    if stageSel.open then
        local L = stageSelectLayout(region.w, region.h)
        -- 关闭 X
        if wx >= L.px + L.pw - 36 and wx <= L.px + L.pw - 8
           and wy >= L.py + 8 and wy <= L.py + 36 then
            stageSel.open = false
            return true
        end
        -- 面板外点击关闭
        if wx < L.px or wx > L.px + L.pw or wy < L.py or wy > L.py + L.ph then
            stageSel.open = false
            return true
        end
        -- 翻页
        if wy >= L.py + L.ph - 46 and wy <= L.py + L.ph - 10 then
            if wx >= L.px + 20 and wx <= L.px + 130 then
                if stageSel.page > 0 then stageSel.page = stageSel.page - 1 end
                return true
            elseif wx >= L.px + L.pw - 130 and wx <= L.px + L.pw - 20 then
                if stageSel.page < L.maxPage then stageSel.page = stageSel.page + 1 end
                return true
            end
        end
        -- 关卡格子
        for _, c in ipairs(L.cells) do
            if wx >= c.x and wx <= c.x + c.w and wy >= c.y and wy <= c.y + c.h then
                if c.id <= L.maxStage then
                    local bs = require("ui.BattleScene")
                    local ok = bs.gotoStage(c.id)
                    if ok then stageSel.open = false end
                end
                return true
            end
        end
        return true
    end

    -- [常驻] 点击行1 内任意处可关闭归属本行的获得弹窗
    if RewardPopup.currentRowTag() then
        RewardPopup.close()
        return true
    end

    local logicalH = region.h
    local logicalW = region.w
    local rowH1 = logicalH / COL_COUNT
    local ix1, iy1, iw1, ih1 = interiorRect(1, logicalW, logicalH)
    local bs = require("ui.BattleScene")

    -- 对话框打开: 逆映射到设计空间
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() then
        local fit = math.min(iw1 / 1080, ih1 / 960)
        local dx = (wx - ix1 - iw1 * 0.5) / fit + 540
        local dy = (wy - iy1 - ih1 * 0.5) / fit + 1195
        if SweepDialog.isOpen() then SweepDialog.handleInput(dx, dy) end
        if DamageStatsPanel.isOpen() then DamageStatsPanel.handleInput(dx, dy) end
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
    local nx1 = ix1 + 260
    local nx2 = nx1 + 62
    if wy >= iy1 + 7 and wy <= iy1 + 41 then
        if (wx >= nx1 - 27 and wx <= nx1 + 27) or (wx >= nx2 - 27 and wx <= nx2 + 27) then
            BattleTriPage.toggleStageSelect()
            return true
        end
    end

    return true  -- 战斗区吞掉其余点击（自动战斗）
end

return BattleTriPage