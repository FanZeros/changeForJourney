-- 三行独立驱动，中段战斗区486,0,948,1080；左右保留经营/角色面板。
-- 每行己方/敌方各四槽；队一沿用主线进度，未解锁行显示条件与编队预览。
local BattleLayout = require("core.BattleLayout")
local BattleView   = require("ui.battle.scene.BattleView")
local BattleCombat = require("ui.battle.combat.BattleCombat")
local BattleCombatAnim = require("ui.battle.combat.BattleCombatAnim")
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
local BattleSpeed       = require("ui.battle.stage.BattleSpeed")

-- 只在显示边界翻译；驱动进度、源关卡名和地图缓存仍使用原始配置。
local function stageDisplayName(stageId)
    return I18n.lookup(StageConfig.getStageDisplayName(stageId))
end

local BattleTriPage = {}

local COL_COUNT = ExpTable.TEAM_COUNT or 3

-- ---- 状态 ----
local isOpen_ = false
local inited = false
---@type any
local imageVg = nil
local battleReady = true  -- 分帧启动/读档期间由宿主关闭
local drivers = {}        -- [1]/[2]/[3] = BattleTriDriver
local entryPreparation = require("ui.battle.tri.BattleEntryPreparation").new()
---@type table<number|string, number>|nil
local restoredStageIds = nil
local terminalRaid = nil
local applyingTerminalDestination = false
local l1Images = {}       -- 同一路径共用句柄，切场景不删除其他行仍在使用的贴图
local l1Failures = {}     -- 加载失败只提示一次，后续帧仍允许重试
local l1RowImages = {}    -- 跨章图尚未就绪时保留本行最近成功加载的背景
local triOnKill = nil     -- function(data)（由宿主注入，与 BattleScene.onEnemyKill 同构）
local triOnDrop = nil     -- function(data)（击杀掉落，与 BattleScene.onEnemyDrop 同构）
local triOnStageClear = nil -- function(teamIdx, clearedStageId)
local triOnAllDead = nil  -- 普通全灭通知；不干预终焉与掉落
local region = { x = 486, y = 0, w = 948, h = 1080 }  -- 战斗区（窗口坐标）

--- 弹窗绘制、输入和教程热点共用横屏变换，不能借普通中栏的旧帧坐标。
---@param width number|nil
---@param height number|nil
---@return number, number, number
function BattleTriPage.getDialogTransform(width, height)
    local w, h = width or region.w, height or region.h
    local fit = math.min(w / 1080, h / 2400) * 2
    return w * 0.5 - 540 * fit, h * 0.5 - 1195 * fit, fit
end

local function dialogToDesign(wx, wy)
    local ox, oy, fit = BattleTriPage.getDialogTransform()
    return (wx - ox) / fit, (wy - oy) / fit
end

--- 击杀奖励回调注入（宿主与 BattleScene.setOnEnemyKill 同源）
function BattleTriPage.setOnKill(cb) triOnKill = cb end
function BattleTriPage.setOnDrop(cb) triOnDrop = cb end
function BattleTriPage.setOnStageClear(cb) triOnStageClear = cb end
function BattleTriPage.setOnAllDead(cb) triOnAllDead = cb end

function BattleTriPage.isOpen() return isOpen_ end

--- 与 HUD 同源：终焉失败退场仍被接管，直到共享协同战正式清理才允许选关。
---@return boolean
function BattleTriPage.isTerminalRaidActive() return terminalRaid ~= nil end

function BattleTriPage.setBattleReady(ready)
    battleReady = ready == true
    if not battleReady then entryPreparation.invalidate() end
end
function BattleTriPage.isBattleReady() return battleReady end

--- 入场门禁只在离线结算前查询，真实回执/编队变化不能沿用旧预热凭据。
function BattleTriPage.isEntryPrepared()
    local CharacterPanel = require("ui.character.panel.CharacterPanel")
    local unlocked = math.min(COL_COUNT, ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle")))
    return entryPreparation.isPrepared(battleReady and isOpen_, drivers, unlocked,
        CharacterPanel.getTeamSignature)
end

--- 全局倍率以账户最高难度解锁，不随某队选旧关/模态按钮隐藏而降速。
function BattleTriPage.getMaxUnlockedBattleSpeed()
    local Scene = require("ui.battle.scene.BattleScene")
    local battle = ClientDispatcher.get("battle")
    local savedMax = type(battle) == "table" and (tonumber(battle.maxStageId) or 0) or 0
    -- 终焉编号并非难度顺序，先解析两份凭据再合并倍率。
    return math.max(BattleSpeed.getMaxUnlocked(StageConfig.getDifficulty(Scene.getMaxStageId() or 0)),
        BattleSpeed.getMaxUnlocked(StageConfig.getDifficulty(savedMax)))
end

function BattleTriPage.isSpeedButtonVisible()
    if not battleReady or not isOpen_ or terminalRaid
        or BattleTriPage.getMaxUnlockedBattleSpeed() <= 1
        or SweepDialog.isOpen() or DamageStatsPanel.isOpen() or StageSelectDialog.isOpen()
        or TerminalConfirmDialog.isOpen() or RewardPopup.currentRowTag()
        or EquipmentBag.shouldBattleOverlay()
        or require("ui.story.gate.LetterIntro").isOpen()
        or require("ui.story.gate.IntroCutscene").isActive()
        or require("ui.story.ScenarioDialogue").isActive() then return false end
    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
    for row = 1, math.min(COL_COUNT, unlocked) do
        local drv = drivers[row]
        if drv and drv.active and #drv.allies > 0
            and (drv.introTimer or 0) <= 0 and (drv.marchTimer or 0) <= 0 then return true end
    end
    return false
end

--- 原始真实 dt 入口；Page.update 每帧只解析一次，再把同一值传给三队与共享计时。
function BattleTriPage.getBattleLogicDt(dt)
    local Scene = require("ui.battle.scene.BattleScene")
    local logicDt, speed = BattleSpeed.getLogicDt(dt, Scene.battleSpeed,
        BattleTriPage.getMaxUnlockedBattleSpeed(), true)
    Scene.battleSpeed = speed
    return logicDt
end

--- 存档阵容晚于战斗页到达时，清掉已记住的编队，下一帧按真实槽位重建。
---@param onlyTeams table<number, boolean>|nil 仅失效指定队伍；nil=全部（旧行为）
function BattleTriPage.invalidateTeams(onlyTeams)
    entryPreparation.invalidate()
    for idx, drv in pairs(drivers) do
        if not onlyTeams or onlyTeams[idx] then
            drv.teamSignature = nil
        end
    end
end

--- 成长刷新与编队交易分离：转职失效真实队，普通属性只构建下波 pending。
--- 不懒建驱动、不重开关卡、不重置统计或复活；关闭页时默认 Scene 仅属于队一。
---@param teamIndices number[] 已由面板冻结差异筛选的真实变化队
---@param classTeams table<number, boolean>|nil 分支变化队；省略时仅轻刷新
function BattleTriPage.refreshHeroProgressTeams(teamIndices, classTeams)
    local changed, rebuild = {}, {}
    for _, value in ipairs(teamIndices or {}) do
        local teamIdx = tonumber(value)
        if teamIdx and teamIdx >= 1 and teamIdx <= COL_COUNT and teamIdx % 1 == 0 then
            changed[teamIdx] = true
            if classTeams and classTeams[teamIdx] then rebuild[teamIdx] = true end
        end
    end
    if not next(changed) then return false end
    entryPreparation.invalidate()
    return BattleMountScope.run(function()
        if next(rebuild) then BattleTriPage.invalidateTeams(rebuild) end
        for teamIdx = 1, COL_COUNT do
            local drv = drivers[teamIdx]
            if changed[teamIdx] and not rebuild[teamIdx] and drv then
                -- 只借本队挂载，不重新 bindContext；保留战斗上下文/连击/投射物原引用。
                drv.mount()
                local lifecycle = require("ui.battle.scene.BattleAllyLifecycle").bind({
                    getAllies = function() return drv.allies end,
                    getEnemies = function() return drv.enemies end,
                    getEnemyQueue = function() return drv.enemyQueue end,
                    get = function(key) return drv[key] end,
                    set = function(key, value) drv[key] = value end,
                    -- 三行驱动没有默认 Scene 挂机收益缓存，不能回算默认场景。
                    recalcIdleIncome = function() end,
                    ALLY_CARD_CY = BattleLayout.FIELD_CY,
                    effectScope = "tri" .. teamIdx,
                    effectCardCY = BattleLayout.STRIP_CY,
                    effectCardScale = BattleLayout.CARD_SCALE,
                })
                lifecycle.refreshAllyStats()
                print(string.format("[BattleTriPage] 队%d 成长属性已写入下波快照", teamIdx))
            end
        end
        if changed[1] and not isOpen_ then
            require("ui.battle.scene.BattleScene").refreshAllyStats()
        end
        return true
    end)
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
                drv.pendingStageId = drv:resolveAdvanceStage()
                local firstClear = BattleScene.completeTriStageClear(clearedStageId, teamIdx)
                if not firstClear and triOnStageClear then
                    triOnStageClear(teamIdx, clearedStageId)
                end
            end
            drv.onStageChanged = function(teamIdx, stageId)
                -- 轮回三队事务最后统一写目标；队1进场不能先保存队2/3的旧末关。
                if applyingTerminalDestination then return end
                -- 关卡到达才记录当前关；重开同关/改编队不重复通知。
                local battle = ClientDispatcher.get("battle")
                if type(battle) == "table" then
                    if type(battle.teamStageIds) ~= "table" then battle.teamStageIds = {} end
                    local savedId = StageConfig.isTerminalTemple(stageId)
                        and StageConfig.getTerminalPrevStageId(stageId) or stageId
                    local key = tostring(teamIdx)
                    local changed = battle.teamStageIds[key] ~= savedId
                        or (teamIdx == 1 and battle.currentStageId ~= savedId)
                    battle.teamStageIds[key] = savedId
                    if teamIdx == 1 then
                        if not StageConfig.isTerminalTemple(stageId) then
                            BattleScene.adoptStageProgress(stageId)
                        end
                        -- 终焉仍留在运行态，落盘的一队当前关使用同一个末关回退点。
                        battle.currentStageId = savedId
                        local cleared = battle.clearedStages or {}
                        battle.battleMode = (StageConfig.isResourceStage(savedId)
                            or cleared[savedId] or cleared[tostring(savedId)]) and "idle" or "firstClear"
                    end
                    if changed then
                        print(string.format("[BattleTriPage] 队%d 关卡入档 stage=%s", teamIdx, tostring(savedId)))
                        ClientDispatcher.notifySubscribers("battle")
                        require("boot.StandaloneSave").Flush()
                    end
                end
            end
            drv.onAllDead = function(teamIdx, stageId)
                if triOnAllDead then triOnAllDead(teamIdx, stageId) end
            end
            local battle = ClientDispatcher.get("battle")
            local savedTeams = restoredStageIds or (type(battle) == "table" and battle.teamStageIds) or {}
            savedTeams = type(savedTeams) == "table" and savedTeams or {}
            local startStage = (t == 1) and BattleScene.getStageId()
                or tonumber(savedTeams[tostring(t)] or savedTeams[t]) or StageConfig.NORMAL_FIRST_STAGE
            if t ~= 1 and StageConfig.isTerminalTemple(startStage) then
                startStage = StageConfig.getTerminalPrevStageId(startStage) or StageConfig.NORMAL_FIRST_STAGE
            end
            if StageConfig.isResourceStage(startStage) then
                local DC = require("config.DungeonConfig")
                if not DC.isStageUnlocked(startStage, battle, ClientDispatcher.get("dungeon")) then
                    startStage = StageConfig.NORMAL_FIRST_STAGE
                    if t == 1 then BattleScene.adoptStageProgress(startStage) end
                end
            end
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

--- 胜利时三个编号各结算一次 Boss 击杀奖励（经验/金币），不按战线副本重复发奖。
--- 沿用原编号归属队伍的存活英雄名单，全灭队只计金币/玩家经验。
local function settleRaidKillRewards(raid)
    for row = 1, COL_COUNT do
        -- 三只真实 Boss 各结算一次，保持原有敌人1/2/3分配队1/2/3的奖励口径。
        -- 九张卡只是三只 Boss 的战线表现，不能按九个实例重复发经验/金币。
        local enemy = raid.lines[row] and raid.lines[row][row]
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
    if not raid or raid.settlementStarted then return end
    local stageId = raid.stageId
    raid.settlementStarted = true
    local BattleScene = require("ui.battle.scene.BattleScene")
    if won then
        require("ui.battle.tri.TerminalReincarnation").settleVictory(raid, drivers, settleRaidKillRewards, BattleScene)
        return
    end
    clearTerminalRaid()
    require("ui.battle.tri.TerminalReincarnation").retreat(raid, drivers,
        StageConfig.getTerminalPrevStageId(stageId), BattleScene, BattleTriPage.gotoTeamStage)
end

--- 只由完成/skip动画出口调用，三队实际进场后由Scene统一持久化。
function BattleTriPage.completeTerminalReincarnation(stageId)
    if not terminalRaid or not terminalRaid.won or not terminalRaid.settlementStarted then return false end
    clearTerminalRaid()
    entryPreparation.invalidate()
    require("ui.battle.tri.TerminalReincarnation").enterTeams(drivers, stageId,
        function(value) applyingTerminalDestination = value end)
    return true
end

--- 打开三行战斗（懒建驱动器；已解锁队伍自动开战）
function BattleTriPage.open()
    if not battleReady or isOpen_ then return end
    isOpen_ = true
    local unlocked = ensureDrivers()
    print("[BattleTriPage] open, unlockedTeams=" .. unlocked)
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
    if entry and entry.mode == "resource_dungeon" and entry.mapBg then return entry.mapBg end
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

local function ensureRowBg(vg, row, unlocked, stageId)
    -- 锁定队展示待解锁章节；解锁后按各队实际战斗进度切回背景。
    ---@type string
    local path
    if row > unlocked then
        path = CHAPTER_BG[row == 2 and 10 or 20]
    else
        path = BattleTriPage.resolveBackgroundPath(stageId or BattleTriPage.getTeamStageId(row))
    end
    local image = getBackgroundImage(vg, path)
    if image >= 0 then
        l1RowImages[row] = image
        return image
    end
    return l1RowImages[row] or image
end

function BattleTriPage.init(vg)
    if imageVg ~= vg then
        imageVg = vg
        inited = false
        l1Images, l1Failures, l1RowImages = {}, {}, {}
    end
    if inited then return end
    inited = true
    BattleView.init(vg)
    imgL0 = nvgCreateImage(vg, "image/暗黑/L0_stone_frame.png", 0)
    StageSelectDialog.init(vg)
    SoundToggle.initImages(vg)
end

--- 仅预热首屏素材，不创建/推进战斗驱动，不改变各队进度。
function BattleTriPage.preload(vg)
    BattleTriPage.init(vg)
    local battle = ClientDispatcher.get("battle")
    local unlocked = ExpTable.getUnlockedTeamCount(battle)
    local savedTeams = restoredStageIds or (type(battle) == "table" and battle.teamStageIds) or {}
    savedTeams = type(savedTeams) == "table" and savedTeams or {}
    local BattleScene = require("ui.battle.scene.BattleScene")
    for row = 1, COL_COUNT do
        -- 与首次建驱动的关卡选择一致，但不为加载图片启动战斗或发进度通知。
        local stageId = BattleTriPage.getTeamStageId(row)
            or (row == 1 and BattleScene.getStageId())
            or tonumber(savedTeams[tostring(row)] or savedTeams[row]) or StageConfig.NORMAL_FIRST_STAGE
        if row ~= 1 and StageConfig.isTerminalTemple(stageId) then
            stageId = StageConfig.getTerminalPrevStageId(stageId) or StageConfig.NORMAL_FIRST_STAGE
        end
        if StageConfig.isResourceStage(stageId)
            and not require("config.DungeonConfig").isStageUnlocked(stageId, battle, ClientDispatcher.get("dungeon")) then
            stageId = StageConfig.NORMAL_FIRST_STAGE
        end
        ensureRowBg(vg, row, unlocked, stageId)
    end
end

--- 入场前创建真实驱动并预热完整首波（含候补），不调用update或推进攻击/领奖。
--- 由宿主合作式队列调用；绘制期不消费全图鉴后台加载队列。
function BattleTriPage.prepareEntry(vg)
    if not battleReady then return false end
    entryPreparation.invalidate()
    BattleTriPage.open()
    BattleTriPage.preload(vg)
    local CharacterPanel = require("ui.character.panel.CharacterPanel")
    local unlocked = math.min(COL_COUNT, ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle")))
    return entryPreparation.prepare(vg, drivers, unlocked, CharacterPanel.getTeamSignature, not terminalRaid)
end

--- [三行并行] L0 整套大背景铺满窗口（左右面板 + 中段框体同源）

--- 每帧更新：三行使用同一套 BattleTriDriver，只切换各自的状态实例。
function BattleTriPage.update(dt)
    if not battleReady or not isOpen_ then return end
    -- 初始剧情（信件/过场/情景对话）点完之前不推进战斗，避免开场期间自动开战。
    if require("ui.story.gate.LetterIntro").isOpen()
        or require("ui.story.gate.IntroCutscene").isActive()
        or require("ui.story.ScenarioDialogue").isActive() then
        return
    end
    BattleLayout.setMode("strip")
    -- 三行卡面走在场/待补位缓存，不能在攻击期间继续解码全图鉴大图。
    local unlocked = ensureDrivers()
    local logicDt = BattleTriPage.getBattleLogicDt(dt)
    -- 帧开始仍在任一有效战线入场时，全协同只推进视觉，不推进攻击或共享限时。
    local raidAtFrameStart = terminalRaid
    local waitingReincarnation = raidAtFrameStart and raidAtFrameStart.settlementStarted and raidAtFrameStart.won
    local raidClockActive = false
    if raidAtFrameStart and not raidAtFrameStart.finished then
        local introPending = false
        for row = 1, math.min(COL_COUNT, unlocked) do
            local drv = drivers[row]
            if drv and drv.terminalRaid == raidAtFrameStart and not raidAtFrameStart.defeated[row]
                and #drv.allies > 0 then
                raidClockActive = true
                if (drv.introTimer or 0) > 0 then introPending = true end
            end
        end
        raidAtFrameStart._introPending = introPending
        raidClockActive = raidClockActive and not introPending
    end
    for t = 1, math.min(COL_COUNT, unlocked) do
        local drv = drivers[t]
        if drv then drv:update(dt, logicDt) end
    end
    if waitingReincarnation then
        require("ui.battle.scene.BattleScene").updateTriReincarnation(dt)
        return
    end
    if terminalRaid and not terminalRaid.finished then
        if terminalRaid == raidAtFrameStart and raidClockActive then
            terminalRaid.elapsed = terminalRaid.elapsed + logicDt
        end
        if terminalRaid.hp <= 0 then
            terminalRaid:finish(true)
        elseif terminalRaid.elapsed >= require("config.GameConfig").Battle.TIME_LIMIT_SEC then
            terminalRaid:finish(false)
        end
    end
    if terminalRaid and terminalRaid.finished then
        if terminalRaid.won then
            finishTerminalRaid(true)
        else
            -- 全灭/超时先停止战斗，至少留一秒让角色退场，不同帧立即重开。
            -- 首次观察到失败不累计当前战斗帧；即使大 dt 也不能同帧直接退关。
            if terminalRaid.finishObserved then
                terminalRaid.finishElapsed = terminalRaid.finishElapsed + dt
            else
                terminalRaid.finishObserved = true
            end
            local pendingExit = false
            for _, drv in pairs(drivers) do
                if drv.terminalRaid == terminalRaid then
                    for _, ally in ipairs(drv.allies) do
                        if ally._fallenPending then pendingExit = true break end
                    end
                end
            end
            if not pendingExit and terminalRaid.finishElapsed >= TerminalRaid.FAILURE_HOLD_SEC then
                finishTerminalRaid(false)
            end
        end
    end
    TerminalConfirmDialog.update()
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

--- 战斗卡点击与教程热点共用实际条带位置；数组为阵亡紧凑后的绘制顺序，不代表原编队槽号。
local function visitAllyCards(logicalW, logicalH, unlocked, visit)
    local scale = 1.0
    for row = 1, COL_COUNT do
        local _, _, iw, ih = interiorRect(row, logicalW, logicalH)
        scale = math.min(scale, math.min(iw / BattleLayout.STRIP_W, ih / BattleLayout.STRIP_H))
    end
    local w = BattleLayout.CARD_W * BattleLayout.CARD_SCALE * scale
    local h = BattleLayout.CARD_H * BattleLayout.CARD_SCALE * scale
    for row = 1, math.min(COL_COUNT, unlocked) do
        local ix, iy, iw, ih = interiorRect(row, logicalW, logicalH)
        local ox = ix + (iw - BattleLayout.STRIP_W * scale) * 0.5
        local oy = iy + (ih - BattleLayout.STRIP_H * scale) * 0.5 + ih * 0.06
        local allies = drivers[row] and drivers[row].allies
        for i, unit in ipairs(allies or {}) do
            if unit.heroId and unit.hp > 0 and not unit._fallen then
                local cx, cy = BattleLayout.cardPos("ally", i, #allies)
                if visit(unit, row, i, ox + cx * scale, oy + cy * scale, w, h) then return end
            end
        end
    end
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
        ---@cast paint NVGpaint
        nvgBeginPath(vg)
        nvgRect(vg, ox, 0, pw, ph)
        nvgFillPaint(vg, paint)
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
                ---@cast paint NVGpaint
                nvgBeginPath(vg)
                nvgRect(vg, ix, iy, iw, ih)
                nvgFillPaint(vg, paint)
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
            ---@cast paint NVGpaint
            nvgBeginPath(vg)
            nvgRect(vg, ix, iy, iw, ih)
            nvgFillPaint(vg, paint)
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
function BattleTriPage.draw(vg, logicalW, logicalH)
    if not isOpen_ then return end
    BattleTriPage.init(vg)
    BattleLayout.setMode("strip")
    region = { x = 0, y = 0, w = logicalW, h = logicalH }

    local BattleScene = require("ui.battle.scene.BattleScene")
    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
    local tutorial = require("systems.TutorialManager")
    if tutorial.getCurrentHighlight() == "battle_hero_detail" and not terminalRaid then
        local session = ClientDispatcher.get("session")
        local initialHeroId = session and tonumber(session.initialHeroId)
        visitAllyCards(logicalW, logicalH, math.min(1, unlocked), function(unit, row, _, cx, cy, w, h)
            -- 首轮赠送武器对应初始角色，不能因其退场改选无法穿戴该武器的队友。
            if initialHeroId and initialHeroId > 0 and tonumber(unit.heroId) ~= initialHeroId then return false end
            local ix, iy, iw, ih = interiorRect(row, logicalW, logicalH)
            local state = drivers[row].combatState
            local anim = BattleCombatAnim.getState(state, unit)
            if anim == "entering" or anim == "reviving" or anim == "dying" or anim == "gone"
                or anim == "march" or anim == "advance" then return false end
            -- 视觉卡可能冲刺/蓄力；高亮只取可见卡与原点击框的交集，不改普通点击规则。
            local scale = w / (BattleLayout.CARD_W * BattleLayout.CARD_SCALE)
            local offset = BattleCombatAnim.getOffsetY(state, unit)
                + BattleCombatAnim.getChargeOffsetY(state, unit, true)
            local vx = cx - offset * scale
            local vy = cy + BattleCombatAnim.getArcOffsetY(state, unit, true) * scale / BattleLayout.CARD_SCALE
            local cardScale = BattleCombatAnim.getCardScale(state, unit, true)
            local left = math.max(cx - w * 0.5, vx - w * cardScale * 0.5, ix, 0)
            local right = math.min(cx + w * 0.5, vx + w * cardScale * 0.5, ix + iw, logicalW)
            local top = math.max(cy - h * 0.5, vy - h * cardScale * 0.5, iy, 0)
            local bottom = math.min(cy + h * 0.5, vy + h * cardScale * 0.5, iy + ih, logicalH)
            if right - left < 12 or bottom - top < 12 then return false end
            tutorial.registerCharacterDetailHotspot("battle_hero_detail", unit.heroId,
                (left + right) * 0.5, (top + bottom) * 0.5, right - left, bottom - top, "screen")
            return true
        end)
    end

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
                -- 普通空编队隐藏敌人；终焉仍展示三只 Boss，包括空队/失守战线。
                local enemiesShown = (terminalRaid or #drv.allies > 0) and drv.enemies or {}
                BattleView.draw(vg, { allies = drv.allies, enemies = enemiesShown }, nil, true)
                -- 与本行卡面共用当前transform/scissor，仅绘本行scope，不在窗口坐标重画。
                if require("ui.hud.popup.SettingsPanel").isEffectsEnabled() then
                    require("ui.fx.SpineCardEffect").draw(vg, "tri" .. row)
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

        -- [终焉协同] 生命由各 Boss 卡牌血条展示，行1 只保留协同倒计时。
        if terminalRaid and row == 1 and row <= unlocked then
            local timeLimit = require("config.GameConfig").Battle.TIME_LIMIT_SEC
            local left = math.max(0, math.ceil(timeLimit - terminalRaid.elapsed))
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, left <= 30 and nvgRGBA(255, 120, 110, 255)
                or nvgRGBA(236, 226, 198, 255))
            nvgText(vg, ix + 28, iy + 55,
                I18n.format("限时 %d:%02d", left // 60, left % 60), nil)
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
        local ox, oy, fit = BattleTriPage.getDialogTransform(logicalW, logicalH)
        nvgSave(vg)
        nvgScissor(vg, 0, 0, logicalW, logicalH)
        nvgTranslate(vg, ox, oy)
        nvgScale(vg, fit, fit)
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
    teamIdx = tonumber(teamIdx)
    stageId = tonumber(stageId)
    if not teamIdx or teamIdx % 1 ~= 0 or not stageId or stageId % 1 ~= 0
        or not StageConfig.getStage(stageId) then return false end
    local unlocked = ExpTable.getUnlockedTeamCount(ClientDispatcher.get("battle"))
    if teamIdx < 1 or teamIdx > unlocked then return false end
    local BattleScene = require("ui.battle.scene.BattleScene")
    -- 终焉 ID 比本难度末关小，解锁比较须与单队 Nav 使用同一进度顺序。
    local maxStage = tonumber(BattleScene.getMaxStageId()) or 0
    local maxPrevious = StageConfig.getTerminalPrevStageId(maxStage)
    local maxRank = maxPrevious and maxPrevious + 0.5 or maxStage
    if StageConfig.isTerminalTemple(stageId) then
        if terminalRaid then return false end
        local previous = StageConfig.getTerminalPrevStageId(stageId)
        local cleared = BattleScene.getClearedStages()
        if not previous or maxRank < previous
            or not (cleared[previous] == true or cleared[tostring(previous)] == true) then
            return false
        end
        if not BattleScene.gotoStage(stageId, { deferEnter = true }) then return false end
        startTerminalRaid(stageId)
        require("systems.GameBGM").setScene("samsara", { fromStart = true })
        return true
    end
    if terminalRaid then return false end
    if StageConfig.isResourceStage(stageId) then
        if not require("config.DungeonConfig").isStageUnlocked(stageId,
            ClientDispatcher.get("battle"), ClientDispatcher.get("dungeon")) then return false end
    elseif stageId > maxRank then
        return false
    end
    local drv = drivers[teamIdx]
    if not drv then return false end
    if teamIdx == 1 then
        if not BattleScene.gotoStage(stageId, { deferEnter = true }) then return false end
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
        do
            nvgSave(vg)
            nvgTranslate(vg, rowSweepX, rowY)
            nvgScale(vg, hudScale, hudScale)
            nvgTranslate(vg, -971, -2115)
            SweepDialog.drawButton(vg)
            nvgRestore(vg)
        end
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

    -- 终焉只锁战斗操作；上方覆盖层和行1 奖励仍沿用各自的输入保护。
    if terminalRaid then return true end

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
        -- 驱动 stageId 是已到达关卡；pendingStageId 仅是行军预约，不能冒充当前。
        SweepDialog.handleButtonInput(971 + (wx - hudSweepX) / hudScale, 2115 + (wy - hudY) / hudScale,
            1, BattleTriPage.getTeamStageId(1))
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
            SweepDialog.handleButtonInput(971 + (wx - rowSweepX) / hudScale, 2115 + (wy - rowY) / hudScale,
                row, BattleTriPage.getTeamStageId(row))
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

    -- 点击己方战斗卡，右侧打开该角色详情。敌方卡和空白不处理。
    visitAllyCards(logicalW, logicalH, unlocked, function(unit, row, i, cx, cy, w, h)
        if math.abs(wx - cx) > w * 0.5 or math.abs(wy - cy) > h * 0.5 then return false end
        require("ui.character.detail.CharacterDetail").open(unit.heroId)
        require("systems.TutorialManager").notifyCharacterDetailOpened("battle", unit.heroId)
        require("systems.GameSFX").play("ui_pick")
        print(string.format("[BattleTriPage] 点击战场角色 队%d 槽%d hero=%s", row, i, tostring(unit.heroId)))
        return true
    end)

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
    if RewardPopup.currentRowTag() then
        local rx, ry, rw, rh = interiorRect(1, region.w, region.h)
        return RewardPopup.handleDragRegion("begin", wx, wy, rx, ry, rw, rh)
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
    if RewardPopup.currentRowTag() then
        local rx, ry, rw, rh = interiorRect(1, region.w, region.h)
        return RewardPopup.handleDragRegion("move", wx, wy, rx, ry, rw, rh)
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
    if RewardPopup.currentRowTag() then
        local rx, ry, rw, rh = interiorRect(1, region.w, region.h)
        return RewardPopup.handleDragRegion("end", wx, wy, rx, ry, rw, rh)
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
    if RewardPopup.currentRowTag() then
        local rx, ry, rw, rh = interiorRect(1, region.w, region.h)
        return RewardPopup.handleScrollRegion(wheel, wx, wy, rx, ry, rw, rh)
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

--- 三队实时快照。预约只用于存档连续性，不改变正在行军的战线实际关卡。
---@return number[]|nil
function BattleTriPage.getTeamStageIds()
    if not next(drivers) and not restoredStageIds then return nil end
    local battle = ClientDispatcher.get("battle")
    local saved = type(battle) == "table" and battle.teamStageIds or {}
    saved = type(saved) == "table" and saved or {}
    local result = {}
    for team = 1, COL_COUNT do
        local drv = drivers[team]
        local closedMainStage = team == 1 and not isOpen_
            and require("ui.battle.scene.BattleScene").getStageId() or nil
        local stageId = closedMainStage or (drv and (drv.pendingStageId or drv.stageId))
            or (restoredStageIds and restoredStageIds[team])
            or tonumber(saved[tostring(team)] or saved[team])
            or (team == 1 and type(battle) == "table" and tonumber(battle.currentStageId))
            or StageConfig.NORMAL_FIRST_STAGE
        -- 协同是临时运行态，读档回到末关，不允许单队恢复终焉。
        result[team] = StageConfig.isTerminalTemple(stageId)
            and (StageConfig.getTerminalPrevStageId(stageId) or StageConfig.NORMAL_FIRST_STAGE) or stageId
    end
    return result
end

--- 放弃旧协同，不分发死亡事件，不通过正常收尾/奖励结算路径。
local function discardTerminalRaid()
    if not terminalRaid then return end
    terminalRaid:release()
    for _, drv in pairs(drivers) do drv.terminalRaid = nil end
    terminalRaid = nil
end

local discardDriver = require("ui.battle.tri.TerminalReincarnation").discardDriver

--- 只在真实恢复时回灌，周期同步必须仅采集；接受数组或规范字符串键表。
---@param stageIds table<number|string, number>
function BattleTriPage.setTeamStageIds(stageIds)
    if type(stageIds) ~= "table" then return false end
    local restored = {}
    for team = 1, COL_COUNT do
        local id = tonumber(stageIds[tostring(team)] or stageIds[team]) or StageConfig.NORMAL_FIRST_STAGE
        if id % 1 ~= 0 or not StageConfig.getStage(id) then id = StageConfig.NORMAL_FIRST_STAGE end
        restored[team] = StageConfig.isTerminalTemple(id)
            and (StageConfig.getTerminalPrevStageId(id) or StageConfig.NORMAL_FIRST_STAGE) or id
    end
    -- 旧单位、掉落与共享绑定均属于旧读档上下文；新阵容齐备后才由ensureDrivers重建。
    require("ui.battle.scene.BattleScene").cancelTriReincarnation()
    entryPreparation.invalidate()
    discardTerminalRaid()
    for _, drv in pairs(drivers) do discardDriver(drv) end
    drivers = {}
    restoredStageIds = restored
    return true
end

--- 清档公开出口：不得让旧raid在清理时结算奖，也不能保留驱动或恢复进度。
function BattleTriPage.resetToDefault()
    battleReady, isOpen_ = false, false
    require("ui.battle.scene.BattleScene").cancelTriReincarnation()
    entryPreparation.invalidate()
    discardTerminalRaid()
    for _, drv in pairs(drivers) do discardDriver(drv) end
    drivers, restoredStageIds, l1RowImages = {}, nil, {}
    emptyStates = nil
    print("[BattleTriPage] resetToDefault: discarded drivers/restore/raid/rewards")
end

-- 更新/绘制/选关/恢复临时借用各战线，正常及异常出口均恢复调用方挂载。
BattleMountScope.wrap(BattleTriPage, {
    "open", "prepareEntry", "update", "draw", "gotoTeamStage", "setTeamStageIds", "resetToDefault", "handleInput",
    "completeTerminalReincarnation",
}, false)

return BattleTriPage
