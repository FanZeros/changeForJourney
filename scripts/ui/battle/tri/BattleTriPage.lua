-- ============================================================================
-- BattleTriPage - 三行并行战斗（Phase 3 修正版）
-- 布局: 战斗区 = 中段区域（Standalone 传入 486,0,948,1080，左右经营/角色面板
--       保持原样），纵向堆叠三行战斗（行高 = rh/3 ≈ 360）:
--   行1/2/3 = 同一套 BattleTriDriver（各自独立状态）
--   行1 的关卡进度仍跟随 BattleScene（首通/存档/掉落不另起一套）
--   未解锁行: 暗罩 + 通关解锁条件 + 该队编队预览；返回按钮退出战斗区
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
local ClientDispatcher = require("runtime.ClientDispatcher")
local RewardPopup  = require("ui.hud.popup.RewardPopup")
local SweepDialog       = require("ui.battle.stage.SweepDialog")
local DamageStatsPanel  = require("ui.battle.popup.DamageStatsPanel")
local StageSelectDialog = require("ui.battle.stage.StageSelectDialog")
local TerminalConfirmDialog = require("ui.battle.popup.TerminalConfirmDialog")
local TerminalRaid = require("ui.battle.tri.TerminalRaid")
local SoundToggle       = require("ui.widget.SoundToggle")  -- [音效开关] 行1 HUD 快捷按钮
local EquipmentBag      = require("ui.character.equip.EquipmentBag")
local StageConfig       = require("config.StageConfig")
local BattleStats       = require("systems.BattleStats")
local I18n              = require("core.I18n")
local RCH               = require("systems.RelicConditionHandler")
local BattleMountScope  = require("ui.battle.scene.BattleMountScope")

-- 只在显示边界翻译；驱动进度、源关卡名和地图缓存仍使用原始配置。
local function stageDisplayName(stageId)
    local entry = stageId and StageConfig.getStage(tonumber(stageId))
    return I18n.lookup((entry and entry.name) or tostring(stageId or "?"))
end

local BattleTriPage = {}

local COL_COUNT = ExpTable.TEAM_COUNT or 3

-- ---- 状态 ----
local isOpen_ = false
local inited = false
local battleReady = true -- 宿主分帧启动时关闭，首次进度与阵容回灌完成后开放
local drivers = {}        -- [1]/[2]/[3] = BattleTriDriver
local restoredStageIds = nil ---@type number[]|nil 只在读档时回灌，未建驱动不覆盖保存进度
local terminalRaid = nil
local l1Images = {}       -- 同一路径共用句柄，切场景不删除其他行仍在使用的贴图
local l1Failures = {}     -- 加载失败只提示一次，后续帧仍允许重试
local l1RowImages = {}    -- 跨章图尚未就绪时保留本行最近成功加载的背景
local triOnKill = nil     -- function(data)（由宿主注入，与 BattleScene.onEnemyKill 同构）
local triOnDrop = nil     -- function(data)（击杀掉落，与 BattleScene.onEnemyDrop 同构）
local triOnStageClear = nil -- function(teamIdx, clearedStageId)
local region = { x = 486, y = 0, w = 948, h = 1080 }  -- 战斗区（窗口坐标）

local function dialogToDesign(wx, wy)
    local fit = math.min(region.w / 1080, region.h / 2400) * 2
    return (wx - region.w * 0.5) / fit + 540,
           (wy - region.h * 0.5) / fit + 1195
end

--- 击杀奖励回调注入（宿主与 BattleScene.setOnEnemyKill 同源）
function BattleTriPage.setOnKill(cb) triOnKill = cb end
function BattleTriPage.setOnDrop(cb) triOnDrop = cb end
function BattleTriPage.setOnStageClear(cb) triOnStageClear = cb end

function BattleTriPage.isOpen() return isOpen_ end
function BattleTriPage.setBattleReady(ready) battleReady = ready == true end

--- 存档阵容晚于战斗页到达时，清掉已记住的编队，下一帧按真实槽位重建。
---@param onlyTeams table<number, boolean>|nil 仅失效指定队伍；nil=全部（旧行为）
function BattleTriPage.invalidateTeams(onlyTeams)
    for idx, drv in pairs(drivers) do
        if not onlyTeams or onlyTeams[idx] then
            drv.teamSignature = nil
        end
    end
end


local function recordTeamStage(teamIdx, stageId)
    local battle = ClientDispatcher.get("battle")
    if type(battle) ~= "table" then return end
    local stages = BattleTriPage.getTeamStageIds() or { battle.currentStageId or 101, 101, 101 }
    stages[teamIdx] = stageId
    battle.teamCurrentStageIds = stages
    if teamIdx == 1 then
        battle.currentStageId = stageId
        local cleared = battle.clearedStages or {}
        battle.battleMode = (cleared[stageId] or cleared[tostring(stageId)]) and "idle" or "firstClear"
    end
end

-- [终焉协同] 前向声明：ensureDrivers 的终焉接管分支引用（定义在下方）
local startTerminalRaid

--- 创建新解锁队伍的战斗驱动；已存在的驱动保留关卡进度。
--- 小队1跟主线 BattleScene 的当前关，避免共用驱动后从第一关重开。
local function ensureDrivers()
    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
    local BattleScene = require("ui.battle.scene.BattleScene")
    for t = 1, COL_COUNT do
        if unlocked >= t and not drivers[t] then
            local Driver = require("ui.battle.tri.BattleTriDriver")
            local drv = Driver.new(t)
            drv.onKill = function(data)
                if triOnKill then triOnKill(data) end
            end
            drv.onDrop = function(data)
                if triOnDrop then triOnDrop(data) end
            end
            drv.onStageCleared = function(teamIdx, clearedStageId)
                -- 首通先落盘、行军后才开新关；预约与背景、真实推进共用解析。
                drv.pendingStageId = drv:resolveAdvanceStage()
                local firstClear = BattleScene.completeTriStageClear(clearedStageId, teamIdx)
                if not firstClear and triOnStageClear then
                    triOnStageClear(teamIdx, clearedStageId)
                end
            end
            drv.onStageChanged = recordTeamStage
            local battle = ClientDispatcher.get("battle")
            local savedStages = restoredStageIds or (type(battle) == "table" and battle.teamCurrentStageIds) or {}
            local startStage = (t == 1) and BattleScene.getStageId()
                or tonumber(savedStages[t] or savedStages[tostring(t)]) or StageConfig.NORMAL_FIRST_STAGE
            drv._syncedMainStage = startStage
            drivers[t] = drv
            drv:start(startStage)
        end
    end
    local teamOne = drivers[1]
    local mainStage = BattleScene.getStageId()
    -- [终焉协同] 主线经单队路径进入终焉（BattleScene 确认框）后打开三行页：
    -- 三行页接管为协同战，队一绝不单独 start(终焉)（会按普通规则清关闭环）。
    if mainStage and StageConfig.isTerminalTemple(mainStage) and not terminalRaid then
        print("[BattleTriPage] 主线停在终焉 " .. tostring(mainStage) .. "，接管为三队协同战")
        startTerminalRaid(mainStage)
        return unlocked
    end
    if teamOne and mainStage and teamOne.stageId ~= mainStage
        and teamOne.stageId == teamOne._syncedMainStage
        and (teamOne.marchTimer or 0) <= 0 then
        teamOne._syncedMainStage = mainStage
        teamOne:start(mainStage)
    elseif teamOne then
        teamOne._syncedMainStage = teamOne.stageId
    end
    return unlocked
end

local function clearTerminalRaid()
    if not terminalRaid then return end
    -- 共享池打空可能发生在最后一条更新的战线；未命中的 Boss 尚未来得及 tick。
    -- 必须在解绑共享池/重开驱动前按各线状态分发，奖励仍只走 settleRaidKillRewards。
    if terminalRaid.hp <= 0 then
        for row = 1, COL_COUNT do
            local drv = drivers[row]
            if drv and drv.terminalRaid == terminalRaid then
                drv:activate()
                drv:reportDefeatedEnemies()
            end
        end
    end
    terminalRaid:release()
    for row = 1, COL_COUNT do
        if drivers[row] then drivers[row].terminalRaid = nil end
    end
    terminalRaid = nil
end

startTerminalRaid = function(stageId)
    clearTerminalRaid()
    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
    for row = 1, math.min(COL_COUNT, unlocked) do
        drivers[row]:start(stageId)
        drivers[row]._syncedMainStage = stageId
    end
    terminalRaid = TerminalRaid.new(stageId, drivers)
    for row = 1, math.min(COL_COUNT, unlocked) do
        drivers[row].terminalRaid = terminalRaid
    end
    if terminalRaid.maxHp <= 0 then
        terminalRaid:finish(false)
    end
end

--- 胜利时按战线结算 Boss 击杀奖励（经验/金币）。
--- 共享池被打空 = 三路 Boss 同时死亡，与主线「敌人死亡即上报击杀」等价；
--- 每路取该队当时存活英雄作为经验分配名单（全灭队只计金币/玩家经验）。
local function settleRaidKillRewards(raid)
    for row = 1, COL_COUNT do
        local enemy = raid.lines[row]
        local drv = drivers[row]
        if enemy and drv and triOnKill then
            local heroIds = {}
            for _, u in ipairs(drv.allies) do
                if u.hp > 0 and u.heroId then heroIds[#heroIds + 1] = u.heroId end
            end
            triOnKill({
                teamIdx = row,
                stageId = raid.stageId,
                expReward = enemy.expReward or 0,
                goldReward = enemy.goldReward or 0,
                heroIds = heroIds,
                allyCount = #heroIds,
            })
        end
    end
end

local function finishTerminalRaid(won)
    local raid = terminalRaid
    if not raid then return end
    local stageId = raid.stageId
    clearTerminalRaid()
    local BattleScene = require("ui.battle.scene.BattleScene")
    local destination = won and StageConfig.getReincarnationTarget(StageConfig.getDifficulty(stageId))
        or StageConfig.getTerminalPrevStageId(stageId)
    -- 终焉结算内部会立即落盘，先为所有参战队预约一致的退出关卡。
    for _, drv in pairs(drivers) do drv.pendingStageId = destination or stageId end
    if won then
        settleRaidKillRewards(raid)
        BattleScene.completeTriTerminal(stageId)
    else
        local previous = StageConfig.getTerminalPrevStageId(stageId)
        BattleScene.adoptStageProgress(previous)
        BattleTriPage.gotoTeamStage(1, previous)
        -- 进终焉时导航被锁定（NavLogic gotoStage），失败退回必须解锁
        require("ui.hud.BottomNav").setAllLocked(false)
        require("systems.GameBGM").setScene("battle")
    end
    for row = 2, COL_COUNT do
        if drivers[row] then
            drivers[row]:start(won and (StageConfig.getReincarnationTarget(StageConfig.getDifficulty(stageId)) or stageId)
                or (StageConfig.getTerminalPrevStageId(stageId) or stageId))
        end
    end
    print(string.format("[BattleTriPage] 终焉%s，三队协同结束 stage=%d", won and "胜利" or "失败", stageId))
end

--- 打开三行战斗（懒建驱动器；已解锁队伍自动开战）
local function openRows()
    require("ui.battle.scene.BattleScene").pumpBattleCards()
    local unlocked = ensureDrivers()
    print("[BattleTriPage] open, unlockedTeams=" .. unlocked)
end

function BattleTriPage.open()
    if not battleReady or isOpen_ then return end
    isOpen_ = true
    return BattleMountScope.run(openRows)
end

--- 返回（关闭战斗区，恢复中面板原战斗视图）
function BattleTriPage.close() isOpen_ = false end

--- 幂等初始化（贴图）
local imgL0 = nil

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
        rch    = RCH.newState(),
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
    RCH.mount(emptyStates.rch)
end

-- 章 1 用现有林景；2–23 用按章重出的满幅背景。难度章按 23 循环。
local CHAPTER_BG = {
    [1]  = "image/暗黑/L1_row1_forest.png",
    [2]  = "image/战斗背景/幽烬林地.png",
    [3]  = "image/战斗背景/哑雾沼泽.png",
    [4]  = "image/战斗背景/巨木之冢.png",
    [5]  = "image/战斗背景/哀嚎沙丘.png",
    [6]  = "image/战斗背景/蚀骨荒漠.png",
    [7]  = "image/战斗背景/焦土平原.png",
    [8]  = "image/战斗背景/断魂裂谷.png",
    [9]  = "image/战斗背景/蛊语山洞.png",
    [10] = "image/战斗背景/悬魂瀑布.png",
    [11] = "image/战斗背景/霜噬雪岭.png",
    [12] = "image/战斗背景/沉眠冰原.png",
    [13] = "image/战斗背景/血晶溶洞.png",
    [14] = "image/战斗背景/枯枫遗迹.png",
    [15] = "image/战斗背景/烬暮湖畔.png",
    [16] = "image/战斗背景/废弃营地.png",
    [17] = "image/战斗背景/古代遗迹.png",
    [18] = "image/战斗背景/沉没神殿.png",
    [19] = "image/战斗背景/哭泣峭壁.png",
    [20] = "image/战斗背景/恶灵岔路.png",
    [21] = "image/战斗背景/遗忘墓穴.png",
    [22] = "image/战斗背景/亡灵墓穴.png",
    [23] = "image/战斗背景/烛龙之巢.png",
}

local TERMINAL_BG = "image/战斗背景/终焉神殿.png"

--- 只解析展示资源，不改变关卡或战斗状态。
---@param stageId number|string|nil
---@return string
function BattleTriPage.resolveBackgroundPath(stageId)
    local id = tonumber(stageId) or 0
    if StageConfig.isTerminalTemple(id) then return TERMINAL_BG end
    local entry = StageConfig.getStage(id)
    local chapter = (entry and entry.chapter) or 1
    return CHAPTER_BG[((chapter - 1) % 23) + 1] or CHAPTER_BG[1]
end

local function getBackgroundImage(vg, path)
    local cached = l1Images[path]
    if cached then return cached end
    local img = nvgCreateImage(vg, path, 0) or -1
    if img >= 0 then
        l1Images[path] = img
        l1Failures[path] = nil
        print(string.format("[BattleTriPage] 背景加载 -> %s (%d)", path, img))
    elseif not l1Failures[path] then
        l1Failures[path] = true
        print("[BattleTriPage] 背景加载失败 -> " .. path)
    end
    return img
end

local function ensureRowBg(vg, row, unlocked)
    -- 锁定队展示待解锁章节；解锁后按各队实际战斗进度切回背景。
    ---@type string
    local path
    if row > unlocked then
        path = CHAPTER_BG[row == 2 and 10 or 20]
    else
        path = BattleTriPage.resolveBackgroundPath(BattleTriPage.getTeamStageId(row))
    end
    local image = getBackgroundImage(vg, path)
    if image >= 0 then
        l1RowImages[row] = image
        return image
    end
    return l1RowImages[row] or image
end

function BattleTriPage.init(vg)
    if inited then return end
    inited = true
    BattleView.init(vg)
    imgL0 = nvgCreateImage(vg, "image/暗黑/L0_stone_frame.png", 0)
    StageSelectDialog.init(vg)
    SoundToggle.initImages(vg)
end

--- [三行并行] L0 整套大背景铺满窗口（左右面板 + 中段框体同源）

--- 每帧更新：三行使用同一套 BattleTriDriver，只切换各自的状态实例。
local function updateRows(dt)
    if not isOpen_ then return end
    -- 初始剧情（信件/过场/情景对话）点完之前不推进战斗，避免开场期间自动开战。
    if require("ui.story.gate.LetterIntro").isOpen()
        or require("ui.story.gate.IntroCutscene").isActive()
        or require("ui.story.ScenarioDialogue").isActive() then
        return
    end
    BattleLayout.setMode("strip")
    require("ui.battle.scene.BattleScene").pumpBattleCards()
    local unlocked = ensureDrivers()
    for t = 1, math.min(COL_COUNT, unlocked) do
        local drv = drivers[t]
        if drv then drv:update(dt) end
    end
    if terminalRaid and not terminalRaid.finished then
        terminalRaid.elapsed = terminalRaid.elapsed + dt
        if terminalRaid.hp <= 0 then
            terminalRaid:finish(true)
        elseif terminalRaid.elapsed >= require("config.GameConfig").Battle.TIME_LIMIT_SEC then
            terminalRaid:finish(false)
        end
    end
    if terminalRaid and terminalRaid.finished then
        finishTerminalRaid(terminalRaid.won)
    end
    TerminalConfirmDialog.update()
end

function BattleTriPage.update(dt)
    if not battleReady or not isOpen_ then return end
    return BattleMountScope.run(updateRows, dt)
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
        nvgFillPaint(vg, paint --[[@as NVGpaint]])
        nvgFill(vg)
    end
end

--- L1 行内容背景垫底层（clip 到框内矩形; 锁定行加暗罩）——绘制于 L0 之前
---@param fixedBgPath string|nil 塔等独立场景使用固定背景，不读取主线行状态
function BattleTriPage.drawL1Underlay(vg, logicalW, logicalH, fixedBgPath)
    BattleTriPage.init(vg)
    local unlocked = COL_COUNT
    if not fixedBgPath then
        unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
    end
    for row = 1, COL_COUNT do
        local ix, iy, iw, ih = interiorRect(row, logicalW, logicalH)
        nvgSave(vg)
        nvgScissor(vg, ix, iy, iw, ih)
        -- L1 cover-fit
        local s = math.max(iw / 1896, ih / 720)
        local dw, dh = 1896 * s, 720 * s
        local bg = fixedBgPath and getBackgroundImage(vg, fixedBgPath)
            or ensureRowBg(vg, row, unlocked)
        local zoom, alpha, nextBgStageId = 1, 1, nil
        local drv = not fixedBgPath and row <= unlocked and drivers[row] or nil
        if drv then zoom, alpha, nextBgStageId = drv:getMarchBackground() end
        -- 先铺不透明的新背景，再画放大淡出的旧背景；同章复用同一有效句柄。
        if nextBgStageId then
            local nextBg = getBackgroundImage(vg, BattleTriPage.resolveBackgroundPath(nextBgStageId))
            if nextBg and nextBg >= 0 then
                local paint = nvgImagePattern(vg, ix + (iw - dw) * 0.5, iy + (ih - dh) * 0.5,
                    dw, dh, 0, nextBg, 1)
                nvgBeginPath(vg)
                nvgRect(vg, ix, iy, iw, ih)
                nvgFillPaint(vg, paint --[[@as NVGpaint]])
                nvgFill(vg)
            else
                -- 下层未就绪时旧图保持原尺寸和不透明，切关回退也不会缩闪。
                zoom, alpha = 1, 1
            end
        end
        -- 以可见战场的右侧中心为锚点，不按 cover 图片被裁掉的边缘定位。
        local pivotX, pivotY = ix + iw, iy + ih * 0.5
        local bgX = pivotX + (ix + (iw - dw) * 0.5 - pivotX) * zoom
        local bgY = pivotY + (iy + (ih - dh) * 0.5 - pivotY) * zoom
        if bg and bg >= 0 then
            local paint = nvgImagePattern(vg, bgX, bgY, dw * zoom, dh * zoom, 0, bg, alpha)
            nvgBeginPath(vg)
            nvgRect(vg, ix, iy, iw, ih)
            nvgFillPaint(vg, paint --[[@as NVGpaint]])
            nvgFill(vg)
        end
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
local function drawRows(vg, logicalW, logicalH)
    if not isOpen_ then return end
    BattleTriPage.init(vg)
    BattleLayout.setMode("strip")
    region = { x = 0, y = 0, w = logicalW, h = logicalH }

    local BattleScene = require("ui.battle.scene.BattleScene")
    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))

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
                -- 无编队时完全不显示敌人（血条/名字等），只留空行提示
                local enemiesShown = (#drv.allies > 0) and drv.enemies or {}
                BattleView.draw(vg, { allies = drv.allies, enemies = enemiesShown }, nil, true)
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
        if terminalRaid and row <= unlocked then
            -- [终焉协同] 先翻译关卡，再组装小队/失守文案，不写回 raid 或驱动。
            local raidStageText = stageDisplayName(terminalRaid.stageId)
            if terminalRaid.defeated[row] then
                raidStageText = I18n.format("%s（已失守）", raidStageText)
            end
            stageText = I18n.format("【小队%d】%s", row, raidStageText)
        elseif row <= unlocked and drivers[row] then
            stageText = I18n.format("【小队%d】%s", row, stageDisplayName(drivers[row].stageId))
        elseif row <= unlocked then
            stageText = I18n.format("【小队%d】%s", row, I18n.lookup("准备中"))
        else
            stageText = I18n.format("【小队%d】%s", row, I18n.lookup("待解锁"))
        end
        -- [暗黑化] 不再画行标签底条，文字直接浮在战斗场景上
        nvgFillColor(vg, nvgRGBA(215, 222, 240, 255))
        if terminalRaid and terminalRaid.defeated[row] then
            nvgFillColor(vg, nvgRGBA(165, 170, 190, 255))
        end
        -- 普通战斗给右上 HUD 留空；按最终译文测宽，不改行高/按钮热区。
        local labelW = iw - 56
        if not terminalRaid and row <= unlocked then
            local hudCount = BattleScene.isSpeedButtonVisible() and 5 or 4
            labelW = math.max(1, iw - 116 - (hudCount - 1) * 58)
        end
        local labelTextW = nvgTextBounds(vg, 0, 0, stageText, nil)
        local labelFont = labelTextW > labelW and math.max(16, 22 * labelW / labelTextW) or 22
        nvgSave(vg)
        nvgIntersectScissor(vg, ix + 26, iy + 5, labelW + 4, 48)
        nvgFontSize(vg, labelFont)
        if labelTextW * labelFont / 22 > labelW then
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgTextBox(vg, ix + 28, iy + 9, labelW, stageText, nil)
        else
            nvgText(vg, ix + 28, iy + 25, stageText, nil)
        end
        nvgRestore(vg)
        -- 前进提示复用底部进度说明位置，字号和留白随战斗行高度缩放。
        local marching = not terminalRaid and row <= unlocked and drivers[row] and drivers[row].marchNotice
        if marching then
            local noticeScale = math.min(1, ih / 360)
            nvgSave(vg)
            nvgIntersectScissor(vg, ix, iy, iw, ih)
            nvgFontSize(vg, 22 * noticeScale)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 230, 160, 255))
            nvgText(vg, ix + iw * 0.5, iy + ih - 26 * noticeScale, "正在前进中", nil)
            nvgRestore(vg)
        end

        -- [终焉协同] 每行底部进度条替换为共享生命池（绯红），行1 附加数值与倒计时
        if terminalRaid and row <= unlocked and terminalRaid.maxHp > 0 then
            local ratio = math.max(0, math.min(1, terminalRaid.hp / terminalRaid.maxHp))
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
                nvgFillColor(vg, nvgRGBA(196, 62, 62, 235))
                nvgFill(vg)
            end
            if row == 1 then
                -- 行1 显示共享池数值 + 剩余时限（行2/3 只显示同步血条，避免文字堆叠）
                local NumberUtil = require("core.NumberUtil")
                nvgFontSize(vg, 16)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 205, 195, 255))
                nvgText(vg, ix + iw * 0.5, barY - 12,
                    I18n.format("共享生命 %s / %s",
                        NumberUtil.format(terminalRaid.hp), NumberUtil.format(terminalRaid.maxHp)), nil)
                local timeLimit = require("config.GameConfig").Battle.TIME_LIMIT_SEC
                local left = math.max(0, math.ceil(timeLimit - terminalRaid.elapsed))
                nvgFontSize(vg, 22)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, left <= 30 and nvgRGBA(255, 120, 110, 255)
                    or nvgRGBA(236, 226, 198, 255))
                nvgText(vg, ix + 28, iy + 55,
                    I18n.format("限时 %d:%02d", left // 60, left % 60), nil)
            end
        end

        local killed, total
        if not terminalRaid and row <= unlocked and drivers[row] and #drivers[row].allies > 0 then
            killed, total = drivers[row].kills, drivers[row].stageTotal
        end
        if killed and total and total > 0 then
            local ratio = math.max(0, math.min(1, killed / total))
            local pctShown = math.floor(ratio * 100 + 0.5)
            local pctText = string.format("%d%%", pctShown)
            local barW = math.min(iw * 0.62, 280)
            local progressScale = marching and math.min(1, ih / 360) or 1
            local barH = 10 * progressScale
            local barX = ix + (iw - barW) * 0.5
            local barY = iy + ih - 8 * progressScale
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
            if not marching then
                nvgFontSize(vg, 16)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(236, 226, 198, 255))
                nvgText(vg, ix + iw * 0.5, barY - 12, I18n.format("关卡进度 %s", pctText), nil)
            end
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
            nvgFontSize(vg, 44)
            nvgFillColor(vg, nvgRGBA(165, 170, 190, 255))
            nvgText(vg, ix + iw * 0.5, iy + ih * 0.5,
                I18n.lookup(ExpTable.getTeamUnlockText(row)), nil)
        end
    end

    -- [对话框覆盖] 选关/扫荡/统计/终焉确认：按当前横屏可用区域放大到 2 倍。
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen()
        or TerminalConfirmDialog.isOpen() then
        local fit = math.min(logicalW / 1080, logicalH / 2400) * 2
        nvgSave(vg)
        nvgScissor(vg, 0, 0, logicalW, logicalH)
        nvgTranslate(vg, logicalW * 0.5, logicalH * 0.5)
        nvgScale(vg, fit, fit)
        nvgTranslate(vg, -540, -1195)
        if SweepDialog.isOpen() then SweepDialog.draw(vg) end
        if DamageStatsPanel.isOpen() then DamageStatsPanel.draw(vg) end
        if StageSelectDialog.isOpen() then StageSelectDialog.draw(vg) end
        if TerminalConfirmDialog.isOpen() then
            TerminalConfirmDialog.draw(vg, BattleScene.getStageId(), function() return StageConfig end)
        end
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

function BattleTriPage.draw(vg, logicalW, logicalH)
    if not isOpen_ then return end
    return BattleMountScope.run(drawRows, vg, logicalW, logicalH)
end

--- 三队快照：无驱动且未收到读档值时返回 nil，禁止启动默认值覆盖保存。
---@return number[]|nil
function BattleTriPage.getTeamStageIds()
    if not next(drivers) and not restoredStageIds then return nil end
    local battle = ClientDispatcher.get("battle")
    local saved = type(battle) == "table" and battle.teamCurrentStageIds or {}
    saved = saved or {}
    local result = {}
    for team = 1, COL_COUNT do
        local drv = drivers[team]
        local closedMainStage = team == 1 and not isOpen_
            and require("ui.battle.scene.BattleScene").getStageId() or nil
        result[team] = closedMainStage or (drv and (drv.pendingStageId or drv.stageId))
            or (restoredStageIds and restoredStageIds[team])
            or tonumber(saved[team] or saved[tostring(team)])
            or (team == 1 and type(battle) == "table" and tonumber(battle.currentStageId))
            or StageConfig.NORMAL_FIRST_STAGE
    end
    return result
end

--- 仅真实读档/清档恢复调用；周期同步只采集，不把旧值灌回正在战斗的队伍。
---@param stageIds number[]
function BattleTriPage.setTeamStageIds(stageIds)
    restoredStageIds = {}
    for team = 1, COL_COUNT do
        restoredStageIds[team] = tonumber(stageIds[team] or stageIds[tostring(team)]) or StageConfig.NORMAL_FIRST_STAGE
    end
    BattleMountScope.run(function()
        clearTerminalRaid()
        for team, drv in pairs(drivers) do
            local stageId = restoredStageIds[team]
            if drv.stageId ~= stageId or drv.pendingStageId then
                drv._syncedMainStage = stageId
                drv:start(stageId)
            end
        end
    end)
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
local function gotoTeamStage(teamIdx, stageId)
    stageId = tonumber(stageId)
    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
    if not teamIdx or teamIdx % 1 ~= 0 or teamIdx < 1 or teamIdx > unlocked
        or not stageId or stageId % 1 ~= 0 or not StageConfig.getStage(stageId) then return false end
    local BattleScene = require("ui.battle.scene.BattleScene")
    if StageConfig.isTerminalTemple(stageId) then
        if terminalRaid then return false end
        local previous = StageConfig.getTerminalPrevStageId(stageId)
        local cleared = BattleScene.getClearedStages()
        local maxStage = BattleScene.getMaxStageId()
        if not previous or maxStage < previous
            or not (cleared[previous] or cleared[tostring(previous)]) then
            return false
        end
        if not BattleScene.gotoStage(stageId, { deferEnter = true }) then return false end
        startTerminalRaid(stageId)
        require("systems.GameBGM").setScene("samsara", { fromStart = true })
        return true
    end
    if terminalRaid then return false end
    if stageId > BattleScene.getMaxStageId() then return false end
    local drv = drivers[teamIdx]
    if not drv then return false end
    if teamIdx == 1 then
        if not BattleScene.gotoStage(stageId, { deferEnter = true }) then return false end
    end
    drv:start(stageId)
    recordTeamStage(teamIdx, stageId)
    return true
end

function BattleTriPage.gotoTeamStage(teamIdx, stageId)
    return BattleMountScope.run(gotoTeamStage, teamIdx, stageId)
end

--- 每行 HUD 从右上角往左排：速度(可选) / 扫荡 / 统计 / 选关 / 音效。
--- 由宿主在 BattleTriPage.draw 之后调用——保证按钮位于一切战斗背景/框柱之上（避免穿帮）。
--- 任一模态对话框打开时不绘制（弹窗压暗与本体在 draw 内已覆盖按钮位）。
--- 已解锁的其他队伍与第一行保持同一套按钮。
function BattleTriPage.drawHud(vg, logicalW, logicalH)
    if not isOpen_ then return end
    if SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen()
        or TerminalConfirmDialog.isOpen() or terminalRaid then
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
    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
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

    if TerminalConfirmDialog.isOpen() then
        local dx, dy = dialogToDesign(wx, wy)
        TerminalConfirmDialog.handleInput(dx, dy, function(nextId)
            BattleTriPage.gotoTeamStage(1, nextId)
        end)
        return true
    end
    if terminalRaid then return true end

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
    -- （逐个获得未结束时点击只跳过动画）。弹窗打开时任意点击都消费：
    -- 行内点击由 handleInputRegion 处理，行外点击也关闭弹窗，避免一直挂着。
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
        SweepDialog.handleButtonInput(971 + (wx - hudSweepX) / hudScale, 2115 + (wy - hudY) / hudScale, 1)
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
    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
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
            SweepDialog.handleButtonInput(971 + (wx - rowSweepX) / hudScale, 2115 + (wy - rowY) / hudScale, row)
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

    -- 点击己方战斗卡，右侧打开该角色属性页。敌方卡和空白不处理。
    local contentScale = 1.0
    for row = 1, COL_COUNT do
        local _, _, iw, ih = interiorRect(row, logicalW, logicalH)
        contentScale = math.min(contentScale,
            math.min(iw / BattleLayout.STRIP_W, ih / BattleLayout.STRIP_H))
    end
    local cardW = BattleLayout.CARD_W * BattleLayout.CARD_SCALE * contentScale
    local cardH = BattleLayout.CARD_H * BattleLayout.CARD_SCALE * contentScale
    for row = 1, math.min(COL_COUNT, unlocked) do
        local ix, iy, iw, ih = interiorRect(row, logicalW, logicalH)
        local dw = BattleLayout.STRIP_W * contentScale
        local dh = BattleLayout.STRIP_H * contentScale
        local originX = ix + (iw - dw) * 0.5
        local originY = iy + (ih - dh) * 0.5 + ih * 0.06
        local allies = drivers[row] and drivers[row].allies
        if allies then
            for i = 1, #allies do
                local unit = allies[i]
                -- [阵亡紧凑] 只响应存活且未退场的角色；已退到队尾的阵亡者不可点
                if unit and unit.heroId and unit.hp > 0 and not unit._fallen then
                    local cx, cy = BattleLayout.cardPos("ally", i, #allies)
                    local sx = originX + cx * contentScale
                    local sy = originY + cy * contentScale
                    if math.abs(wx - sx) <= cardW * 0.5 and math.abs(wy - sy) <= cardH * 0.5 then
                        require("ui.character.detail.CharacterDetail").open(unit.heroId)
                        require("systems.GameSFX").play("ui_pick")
                        print(string.format("[BattleTriPage] 点击战场角色 队%d 槽%d hero=%s",
                            row, i, tostring(unit.heroId)))
                        return true
                    end
                end
            end
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
