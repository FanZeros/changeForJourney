-- ============================================================================
-- StandaloneSave - 单机模式本地存档
-- 读写 save.json。这是单机唯一落盘路径。
-- 职责:
--   1. 快照 ClientDispatcher 全部模块数据 + GameState 单机本地 state
--   2. 只读结构分帧检测 → 防抖落盘本地 File（检测镜像绝不写盘）
--   3. 启动时恢复（纯数据先注入，battle 进度待场景就绪后回灌）
-- 运行端: 仅 Standalone（multiplayer.enabled=false）
-- 本模块是单机唯一落盘路径。规则层 localMode 不再写云。
-- ============================================================================
-- 数据双源说明（单机模式）:
--   - GameState.state       货币/等级/经验的真实源（setter 写本地表）
--   - ClientDispatcher      heroes/equipment/lootbox/session/battle 等模块
--   - BattleScene 本地进度  maxStageId_/clearedStages，经 SyncBattleState
--                           每秒镜像进 dispatcher 的 battle 模块；恢复时用
--                           setBattleData 回灌（含 string→number key 修正）
-- ============================================================================

local ClientDispatcher = require("runtime.ClientDispatcher")
local GameState        = require("core.GameState")
local BattleScene      = require("ui.battle.scene.BattleScene")
local BattleSchema     = require("shared.battle.BattleSchema")
local OfflineService   = require("rules.offline.OfflineService")

local StandaloneSave = {}

---@class TeamStagePersistencePage
---@field getTeamStageIds fun(): number[]|nil
---@field setTeamStageIds fun(stageIds: table)
---@type TeamStagePersistencePage|nil
local battlePage = nil

---@param page TeamStagePersistencePage
function StandaloneSave.SetBattlePage(page)
    battlePage = page
end

--- 即时快照只采集，不把旧存档回灌到仍在战斗的驱动。
---@param battle table
---@return table
function StandaloneSave.CaptureBattleProgress(battle)
    local copy = {}
    for key, value in pairs(battle) do copy[key] = value end
    local live = battlePage and battlePage.getTeamStageIds()
    if type(live) == "table" then
        local sceneMax = tonumber(BattleScene.getMaxStageId()) or 0
        local savedMax = tonumber(battle.maxStageId) or 0
        local SC = require("config.StageConfig")
        local function rank(id)
            local previous = SC.getTerminalPrevStageId(id)
            return previous and previous + 0.5 or id
        end
        copy.maxStageId = rank(sceneMax) > rank(savedMax) and sceneMax or savedMax
        local cleared = {}
        for _, ledger in ipairs({ battle.clearedStages or {}, BattleScene.getClearedStages() or {} }) do
            if type(ledger) == "table" then
                for key, value in pairs(ledger) do
                    local id = math.tointeger(tonumber(key) or 0)
                    if value == true and id and id > 0 then cleared[tostring(id)] = true end
                end
            end
        end
        copy.clearedStages = cleared
        local saved = type(battle.teamStageIds) == "table" and battle.teamStageIds or {}
        local ids = {}
        for team = 1, 3 do
            ids[tostring(team)] = live[team] or live[tostring(team)]
                or saved[tostring(team)] or saved[team]
        end
        copy.teamStageIds = ids
        copy.currentStageId = ids["1"] or battle.currentStageId
    end
    BattleSchema.normalizeTeamStageIds(copy, false)
    return copy
end

local SAVE_FILE         = "standalone_save.json"
local TEMP_SAVE_FILE    = "standalone_save.pending.json"
local SAVE_VERSION      = 1
local SNAPSHOT_INTERVAL = 1.0   -- 空闲时开始下一轮只读检测（秒），不是大树扫描完成期限
local FLUSH_DEBOUNCE    = 2.0   -- 变更后写盘防抖（秒）
local DETECT_MAX_STEPS  = 4096  -- 每 Update 的键/栈操作硬上限
local DETECT_CPU_BUDGET = 0.001 -- 每 32 步检查 CPU 软时限；不包含实际 Flush

---@class SaveDetectorFrame
---@field source table
---@field snapshot table
---@field phase integer
---@field key any
---@class SaveDetectorScan
---@field stack SaveDetectorFrame[]
---@field frames SaveDetectorFrame[]
---@field changed boolean
---@field changedKnown boolean
---@type table|nil 私有检测镜像，允许跨帧；绝不能交给 encodeSave/writeFile
local detectorSnapshot = nil
---@type SaveDetectorScan|nil
local detectorScan = nil
local detectorReady = false
local snapshotAcc = 0.0
---@type number|nil  防抖写盘剩余时间（nil = 无待写变更）
local flushTimer = nil
local restoredSavedAt = 0  -- 当前进程启动前最后一次落盘；用于兼容旧存档的在线边界
local restoredSave = false
local offlineChecked = false
local lastSavedAt = 0

local function resetDetector()
    detectorSnapshot = nil
    detectorScan = nil
    -- 已恢复/已进入业务后，首扫未知项不能当初始化吞掉：旧盘可能正缺这次真实修改。
    -- 保守请求新鲜 Flush（大树首扫期间可能多次），未开场纯新档才允许只建基线。
    detectorReady = restoredSave or offlineChecked
    snapshotAcc = 0
end

--- 只读变化源，不构建保存表、不转换全名册/账本，也不调用 JSON。
--- liveBattle 是额外脏检测输入：原地进度/预约无需先等 dispatcher 通知。
--- 真正落盘仍只用 buildSaveData/CaptureBattleProgress 的新鲜完整转换。
local function detectorSource()
    local live = battlePage and battlePage.getTeamStageIds()
    local liveBattle = nil
    if type(live) == "table" then
        liveBattle = {
            teamStageIds = live,
            maxStageId = BattleScene.getMaxStageId(),
            clearedStages = BattleScene.getClearedStages(),
        }
    end
    return { modules = ClientDispatcher.snapshotAll(), gameState = GameState.exportSave(),
        liveBattle = liveBattle }
end

---@param scan SaveDetectorScan
---@param source table
---@param snapshot table
local function pushDetectorFrame(scan, source, snapshot)
    -- cjson 本来也拒绝循环/过深数据。检测不能在坏数据上无限循环耗尽每帧预算。
    local depth = #scan.stack + 1
    for _, frame in ipairs(scan.stack) do
        if frame.source == source then error("存档检测循环引用") end
    end
    -- cjson 的深度限制由实际 Flush 验证；检测对坏表不应无限递归占帧。
    if depth > 64 then error("存档检测嵌套过深") end
    -- 栈帧按深度复用，不为每件装备/词条反复分配临时表造成周期 GC 压力。
    local frame = scan.frames[depth]
    if not frame then
        frame = { source = source, snapshot = snapshot, phase = 1 }
        scan.frames[depth] = frame
    end
    frame.source, frame.snapshot, frame.phase, frame.key = source, snapshot, 1, next(snapshot)
    scan.stack[depth] = frame
end

---@param scan SaveDetectorScan
---@param frame SaveDetectorFrame
---@param key any
---@param value any
local function detectEntry(scan, frame, key, value)
    local previous = rawget(frame.snapshot, key)
    local known = previous ~= nil
    if type(value) == "table" then
        if type(previous) ~= "table" then
            previous = {}
            frame.snapshot[key] = previous
            scan.changed = true
            scan.changedKnown = scan.changedKnown or known
        end
        pushDetectorFrame(scan, value, previous)
    elseif previous ~= value then
        frame.snapshot[key] = value
        scan.changed = true
        scan.changedKnown = scan.changedKnown or known
    end
end

--- 一步至多处理一个键或退栈。先走私有镜像查删除，再走 live 查新增。
--- live 的上次 key 在帧间可能被删除；重启该层遍历，避免 next(invalid key)。
--- 新增/整表替换/已经访问后的更改会在后续扫描收敛；镜像只是脏标记，不是提交。
---@param scan SaveDetectorScan
local function detectorStep(scan)
    local frame = scan.stack[#scan.stack]
    if frame.phase == 1 then
        local key = frame.key
        if key == nil then
            frame.phase = 2
            return
        end
        -- 私有镜像无人并发修改；在删除当前键前取好下一个 cursor，批量删除仍线性。
        frame.key = next(frame.snapshot, key)
        local value = rawget(frame.source, key)
        if value == nil then
            frame.snapshot[key] = nil
            scan.changed, scan.changedKnown = true, true
        else
            detectEntry(scan, frame, key, value)
        end
        return
    end
    if frame.key ~= nil and rawget(frame.source, frame.key) == nil then frame.key = nil end
    local key, value = next(frame.source, frame.key)
    if key == nil then
        scan.stack[#scan.stack] = nil
        return
    end
    frame.key = key
    -- 已有子表在 phase 1 已扫描，不再次遍历整个库存；普通值再读可见新变化。
    local previous = rawget(frame.snapshot, key)
    if previous == nil or type(value) ~= "table" then
        detectEntry(scan, frame, key, value)
    elseif type(previous) ~= "table" then
        detectEntry(scan, frame, key, value)
    end
end

---@param started number
local function advanceDetector(started)
    if not detectorScan then
        local source = detectorSource()
        detectorSnapshot = detectorSnapshot or {}
        detectorScan = { stack = {}, frames = {}, changed = false, changedKnown = false }
        pushDetectorFrame(detectorScan, source, detectorSnapshot)
    end
    local scan = detectorScan
    for step = 1, DETECT_MAX_STEPS do
        if step == 1 or step % 32 == 0 then
            if os.clock() - started >= DETECT_CPU_BUDGET then return end
        end
        detectorStep(scan)
        -- 成功/失败 Flush 之后再次按真实变化设脏，而不是把本轮旧 changed 粘住重写。
        if scan.changed then
            -- 首基线吸收新初始化项，但已见过的值再变化不等整树 ready 才请求保存。
            if (detectorReady or scan.changedKnown) and not flushTimer then flushTimer = FLUSH_DEBOUNCE end
            scan.changed, scan.changedKnown = false, false
        end
        if #scan.stack == 0 then
            detectorScan = nil
            detectorReady = true
            snapshotAcc = 0
            return
        end
    end
end

--- 数字键会被 cjson 存成数组，读回来就丢掉英雄编号。落盘前改成字符串键。
---@param roster table|nil
---@return table|nil
local function rosterForSave(roster)
    if type(roster) ~= "table" then return roster end
    local out = {}
    for heroId, hero in pairs(roster) do
        out["h" .. tostring(heroId)] = hero
    end
    return out
end

--- 收集当前全部可持久化数据 → 存档表；候选玩家仅用于副本事务，不发布通知。
local function buildSaveData(candidatePlayer)
    local all = ClientDispatcher.snapshotAll()
    local modules = {}
    for name, data in pairs(all) do
        if name == "heroes" and type(data) == "table" then
            local copy = {}
            for k, v in pairs(data) do copy[k] = v end
            copy.roster = rosterForSave(data.roster)
            modules[name] = copy
        elseif name == "battle" and type(data) == "table" then
            modules[name] = StandaloneSave.CaptureBattleProgress(data)
        else
            modules[name] = data
        end
    end
    local savedState = GameState.exportSave()
    if type(candidatePlayer) == "table" then
        -- 两份玩家进度同源；不提前改 live GameState，失败仍可原位回滚。
        modules.player = candidatePlayer
        for _, field in ipairs({ "name", "level", "exp", "maxExp" }) do
            if candidatePlayer[field] ~= nil then savedState[field] = candidatePlayer[field] end
        end
    end
    return {
        version   = SAVE_VERSION,
        savedAt   = lastSavedAt,
        gameState = savedState,
        modules   = modules,
    }
end

--- 编码存档 JSON；成功返回字符串，失败返回 nil
local function encodeSave(candidatePlayer)
    -- 采集/构建也可能失败（页面尚未就绪或坏数据），必须在 pcall 内求值。
    local ok, json, data = pcall(function()
        local current = buildSaveData(candidatePlayer)
        return cjson.encode(current), current
    end)
    if not ok or type(json) ~= "string" then
        print("[StandaloneSave] encode 失败: " .. tostring(json))
        return nil
    end
    return json, data
end

--- 临时文件完整写入且原子替换成功才承认提交；失败不触碰玩家旧档。
local function writeFile(candidatePlayer)
    -- 检测栈/镜像从不参与落盘；保留在途扫描进度，防止持续掉落写档让大库存尾部饥饿。
    -- 即时提交仍只从当前业务状态重新同步构建。
    local previousSavedAt = lastSavedAt
    local session = ClientDispatcher.get("session")
    local previousOnline = session and session.lastOnlineTime
    if offlineChecked and not OfflineService.HasPendingRewards(1) then
        OfflineService.MarkOnline(1)
        lastSavedAt = os.time()
    end
    local committedOnline = session and session.lastOnlineTime
    local function failed(reason)
        lastSavedAt = previousSavedAt
        if session then session.lastOnlineTime = previousOnline end
        flushTimer = FLUSH_DEBOUNCE
        if fileSystem and fileSystem.Delete then fileSystem:Delete(TEMP_SAVE_FILE) end
        print("[StandaloneSave] 写档失败(" .. reason .. "): " .. SAVE_FILE)
        return false
    end
    local json, committedData = encodeSave(candidatePlayer)
    if not json then return failed("编码") end
    if not fileSystem or not fileSystem.Rename then return failed("无安全替换接口") end
    local opened, file = pcall(File, TEMP_SAVE_FILE, FILE_WRITE)
    if not opened or not file or not file:IsOpen() then
        return failed("无法打开临时文件")
    end
    local wrote, complete = pcall(file.WriteString, file, json)
    file:Close()
    if not wrote or complete ~= true then return failed("写入未完成") end
    local renamed, replaced = pcall(fileSystem.Rename, fileSystem, TEMP_SAVE_FILE, SAVE_FILE)
    if not renamed or replaced ~= true then return failed("替换未完成") end
    -- 只修正在线提交自己改变的标量，避免 MarkOnline 每次引出多余自动写盘。
    -- 其余镜像继续合作式核对，绝不借成功 Flush 对未知/回调后变化宣布已检测。
    if detectorSnapshot then
        local modules = detectorSnapshot.modules
        local savedSession = type(modules) == "table" and modules.session
        local currentSession = ClientDispatcher.get("session")
        if type(savedSession) == "table" and type(currentSession) == "table"
            and currentSession == session and currentSession.lastOnlineTime == committedOnline then
            savedSession.lastOnlineTime = committedOnline
        end
    end
    -- GameState.exportSave 是小型浅副本；用本次真正编码的同源副本替换扫描旧输入，
    -- 不沿用扫描开始时旧经验/货币再触发一遍，且不深拷贝/对齐全库存。
    if detectorScan and committedData then
        local root = detectorScan.stack[1]
        local previousState = root and root.source.gameState
        if root then root.source.gameState = committedData.gameState end
        for _, frame in ipairs(detectorScan.stack) do
            if frame.source == previousState then frame.source = committedData.gameState end
        end
    end
    flushTimer = nil
    print("[StandaloneSave] 存档落盘 bytes=" .. #json)
    return true
end

--- 恢复纯数据（GameState + Dispatcher 各模块）
--- ⚠️ 必须在 Standalone.Start() 的 UI/数据初始化之前调用
--- （各系统初始化均为 "if not ClientDispatcher.get(x)" 守卫，先注入即跳过默认值）
---@return boolean 是否恢复了存档
function StandaloneSave.RestoreData()
    offlineChecked = false
    restoredSave = false
    restoredSavedAt = 0
    lastSavedAt = 0
    resetDetector()
    flushTimer = nil
    if not fileSystem or not fileSystem:FileExists(SAVE_FILE) then
        print("[StandaloneSave] 无本地存档，开始新档")
        return false
    end
    local file = File(SAVE_FILE, FILE_READ)
    if not file or not file:IsOpen() then
        print("[StandaloneSave] 读档失败(无法打开): " .. SAVE_FILE)
        return false
    end
    local json = file:ReadString()
    file:Close()

    local ok, saveData = pcall(cjson.decode, json)
    if not ok or type(saveData) ~= "table" or type(saveData.modules) ~= "table" then
        print("[StandaloneSave] 存档损坏或版本不符，按新档处理")
        return false
    end

    -- 1. 恢复 GameState（单机货币/等级真实源）
    GameState.importSave(saveData.gameState)

    -- 旧档 player 镜像可能停在Lv1；GameState 保存的单机等级/经验优先，保留头像等字段。
    local savedState = saveData.gameState
    local player = saveData.modules.player or {}
    if type(savedState) == "table" then
        for _, field in ipairs({ "name", "level", "exp", "maxExp", "power" }) do
            if savedState[field] ~= nil then player[field] = savedState[field] end
        end
    end
    saveData.modules.player = player

    -- 先规范战斗位置，避免模块遍历顺序影响三队解锁；只有真正读档回退终焉。
    local savedBattle = saveData.modules.battle
    if type(savedBattle) == "table" then
        BattleSchema.Fields.battle.onLoad(savedBattle)
        BattleSchema.normalizeTeamStageIds(savedBattle, true)
    end

    -- 2. 恢复各模块（经 handleStateUpdate 统一走 onLoad 修正 + 订阅通知）
    local names = {}
    for name, data in pairs(saveData.modules) do
        ClientDispatcher.handleStateUpdate(cjson.encode({ modules = { [name] = data } }))
        names[#names + 1] = name
    end

    GameState.syncPlayerData(ClientDispatcher.get("player"), { silent = true })
    restoredSavedAt = tonumber(saveData.savedAt) or 0
    lastSavedAt = restoredSavedAt
    restoredSave = true
    resetDetector()  -- 恢复后分帧重建检测基线，不编码全库存
    print("[StandaloneSave] 存档已恢复: " .. #names .. " 个模块 savedAt=" .. tostring(saveData.savedAt))
    return true
end

--- 旧存档的 lastOnlineTime 长期未推进时，以已落盘的在线快照时刻作离线起点。
--- 必须在本轮 CalcOnEnter 之前调用，不能使用本轮新写入的 savedAt。
function StandaloneSave.ReconcileOfflineBoundary()
    local session = ClientDispatcher.get("session")
    if not restoredSave or type(session) ~= "table" or (session.lastOnlineTime or 0) <= 0 then
        restoredSavedAt = 0
        return
    end
    local boundary = math.min(restoredSavedAt, os.time())
    if boundary > session.lastOnlineTime then
        print("[StandaloneSave] 恢复在线边界 lastOnline=" .. tostring(session.lastOnlineTime)
            .. " savedAt=" .. tostring(boundary))
        session.lastOnlineTime = boundary
        local battle = ClientDispatcher.get("battle")
        if type(battle) == "table" then
            battle.idleAccumSec = 0
        end
    end
    restoredSavedAt = 0
end

--- 离线收益已核算；没有待领取奖励时，写档才推进 savedAt/在线边界。
--- 兼容既有事务：此标记与 pending 本身不是 Flush 的拒写门禁。
function StandaloneSave.OfflineChecked()
    offlineChecked = true
    resetDetector()
    print("[StandaloneSave] 离线时间边界已核算")
end

--- 回灌战斗进度（切关/首通标记/挂机模式判定）
--- ⚠️ 必须在 BattleScene.init 之后、Standalone 5.3 初始阵容同步之前调用：
--- setBattleData 首次加载会 loadStage 切到存档关卡，随后 5.3 的 setAllies +
--- reloadStage 会用恢复出的阵容重载同一关卡，时序即正确。
function StandaloneSave.ApplyBattleProgress()
    local battle = ClientDispatcher.get("battle")
    if type(battle) ~= "table" then return end
    if battle.maxStageId == nil and battle.currentStageId == nil and battle.clearedStages == nil then
        return
    end
    BattleSchema.normalizeTeamStageIds(battle, true)
    BattleScene.setBattleData(battle)
    if battlePage then battlePage.setTeamStageIds(battle.teamStageIds) end
    print("[StandaloneSave] 战斗进度已回灌 maxStageId=" .. tostring(battle.maxStageId))
end

--- 主循环更新（由 Standalone.HandleUpdate 调用）
---@param dt number
function StandaloneSave.Update(dt)
    dt = dt or 0
    -- 防抖写盘。实际 Flush 已做完整新鲜编码，本帧不再检测/编码第二遍。
    if flushTimer then
        flushTimer = flushTimer - dt
        if flushTimer <= 0 then
            flushTimer = nil
            writeFile()
            return
        end
    end

    snapshotAcc = snapshotAcc + dt
    if not detectorScan and snapshotAcc < SNAPSHOT_INTERVAL then return end
    local started = os.clock()
    local ok, err = pcall(advanceDetector, started)
    if not ok then
        -- 坏数据/采集异常不打断战斗，镜像不作完整基线，下一周期重新核对。
        detectorScan = nil
        snapshotAcc = 0
        print("[StandaloneSave] 检测失败: " .. tostring(err))
    end
end

--- 立即落盘（退出时调用）
function StandaloneSave.Wipe()
    restoredSavedAt = 0
    lastSavedAt = 0
    restoredSave = false
    offlineChecked = false
    resetDetector()
    flushTimer = nil
    if fileSystem and fileSystem.Delete then
        fileSystem:Delete(SAVE_FILE)
    end
    print("[StandaloneSave] wiped " .. SAVE_FILE)
end

---@param candidatePlayer table|nil 副本事务的待提交玩家进度；普通自动存档不传
function StandaloneSave.Flush(candidatePlayer)
    return writeFile(candidatePlayer)
end

return StandaloneSave
