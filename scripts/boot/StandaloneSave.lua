-- ============================================================================
-- StandaloneSave - 单机模式本地存档
-- 读写 save.json。这是单机唯一落盘路径。
-- 职责:
--   1. 快照 ClientDispatcher 全部模块数据 + GameState 单机本地 state
--   2. 只读结构分帧检测 → 最大30秒合并落盘本地 File（检测镜像绝不写盘）
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
local SAVE_INTERVAL     = 30.0  -- 首次变更请求后的最大合并等待；持续变更不能延后期限
local RETRY_INTERVAL    = 2.0   -- 保存失败后重试，重新采集当前业务状态
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
---@type number|nil  首次变更的合并期限（nil = 无待写变更）；请求不会重置已有期限
local flushTimer = nil
local saveEpoch = 0       -- Wipe/Restore 使旧扫描及重入中的写档失效
local requestRevision = 0 -- Flush 期间新增的请求不能被成功提交清掉
local writing = false
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

--- 普通变更只请求合并保存，不代表事务已提交；已有期限（含失败重试）绝不延后。
--- 返回 nil，调用者不能把请求受理当作 Flush 成功。
function StandaloneSave.RequestSave()
    requestRevision = requestRevision + 1
    if flushTimer == nil then flushTimer = SAVE_INTERVAL end
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
    local epoch = saveEpoch
    if not detectorScan then
        local source = detectorSource()
        if epoch ~= saveEpoch then return end
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
        if epoch ~= saveEpoch then return end
        -- 成功/失败 Flush 之后再次按真实变化设脏，而不是把本轮旧 changed 粘住重写。
        if scan.changed then
            -- 首基线吸收新初始化项，但已见过的值再变化不等整树 ready 才请求保存。
            if detectorReady or scan.changedKnown then StandaloneSave.RequestSave() end
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
    local sourceState = {}
    for key, value in next, savedState do sourceState[key] = value end
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
    }, all, sourceState
end

---@class SaveCommitModule
---@field source table
---@field values table
---@field expected table
---@class SaveCommitReceipt
---@field modules table<string, SaveCommitModule>
---@field gameState table
---@field expectedState table

--- 只冻结模块第一层与小型GameState；绝不复制/遍历库存、名册或首通账本。
--- 记录在编码前产生，提交后不能把文件回调的新变化误当成已保存。
---@param value table
---@return table
local function copyCommitFields(value)
    local copy = {}
    for key, item in next, value do copy[key] = item end
    return copy
end

--- 编码存档 JSON；成功返回字符串，失败返回 nil
local function encodeSave(candidatePlayer)
    -- 采集/构建也可能失败（页面尚未就绪或坏数据），必须在 pcall 内求值。
    local ok, json, receipt = pcall(function()
        local current, sourceModules, sourceState = buildSaveData(candidatePlayer)
        ---@type SaveCommitReceipt
        local committed = { modules = {}, gameState = copyCommitFields(current.gameState), expectedState = sourceState }
        for name, module in next, current.modules do
            local source = sourceModules[name]
            if type(module) == "table" and type(source) == "table" then
                committed.modules[name] = { source = source, values = copyCommitFields(module),
                    expected = copyCommitFields(source) }
            end
        end
        return cjson.encode(current), committed
    end)
    if not ok or type(json) ~= "string" then
        print("[StandaloneSave] encode 失败: " .. tostring(json))
        return nil
    end
    return json, receipt
end

--- 仅对齐当前仍等于编码前冻结值的标量；嵌套表仍由分帧检测收敛。
---@param mirror table|nil
---@param current table
---@param committed table
---@param expected table 编码前live值；候选玩家字段可能有意不同，不能当成回调新修改
local function reconcileCommitFields(mirror, current, committed, expected)
    local changed = false
    for key, value in next, expected do
        if rawget(current, key) ~= value then changed = true break end
    end
    if not changed then
        for key in next, current do
            if rawget(expected, key) == nil then changed = true break end
        end
    end
    -- 包含ABA（回调把值改回旧镜像），也包含嵌套表被整表替换。
    if changed then StandaloneSave.RequestSave() end
    if not mirror then return end
    for key, value in next, committed do
        if type(value) ~= "table" and rawget(current, key) == value then mirror[key] = value end
    end
    local key, value = next(mirror)
    while key ~= nil do
        local nextKey, nextValue = next(mirror, key)
        if type(value) ~= "table" and rawget(committed, key) == nil and rawget(current, key) == nil then
            -- phase1 的 cursor 指向即将删除的镜像键时，先推进，避免 next(invalid key)。
            if detectorScan then
                for _, frame in ipairs(detectorScan.stack) do
                    if frame.snapshot == mirror and frame.phase == 1 and frame.key == key then
                        frame.key = nextKey
                    end
                end
            end
            mirror[key] = nil
        end
        key, value = nextKey, nextValue
    end
end

--- 临时文件完整写入且原子替换成功才承认提交；失败不触碰玩家旧档。
local function deleteTempFile()
    local ok, err = pcall(function()
        if fileSystem and fileSystem.Delete then fileSystem:Delete(TEMP_SAVE_FILE) end
    end)
    if not ok then print("[StandaloneSave] 临时文件清理失败: " .. tostring(err)) end
end

local function writeFile(candidatePlayer)
    -- 同一临时文件只允许一个写者；重入不能假报成功，也不能截断外层候选。
    if writing then StandaloneSave.RequestSave(); return false end
    writing = true
    local epoch, revision = saveEpoch, requestRevision
    local previousSavedAt = lastSavedAt
    local session = nil ---@type table|nil
    local previousOnline = nil ---@type number|nil
    local json = nil ---@type string|nil
    local commitReceipt = nil ---@type SaveCommitReceipt|nil
    local file = nil ---@type File|nil

    -- Close/Dispose 都隔离异常，失败也释放已打开对象；Dispose 后不再访问句柄。
    local function closeFile()
        local current = file
        file = nil
        if not current then return true end
        local closed, closeResult = pcall(function() return current:Close() end)
        local disposed, disposeErr = pcall(function()
            if current.Dispose then current:Dispose() end
        end)
        if not closed or closeResult == false then return false, "关闭失败: " .. tostring(closeResult) end
        if not disposed then return false, "释放失败: " .. tostring(disposeErr) end
        return true
    end
    local function checkEpoch()
        if epoch ~= saveEpoch then error("旧存档任务已失效") end
    end
    -- 检测镜像从不参与提交。每次（包括失败重试）仍从当前业务状态 fresh 构建。
    local ok, err = pcall(function()
        session = ClientDispatcher.get("session")
        previousOnline = session and session.lastOnlineTime
        if offlineChecked and not OfflineService.HasPendingRewards(1) then
            checkEpoch()
            OfflineService.MarkOnline(1)
            checkEpoch()
            lastSavedAt = os.time()
        end
        checkEpoch()
        json, commitReceipt = encodeSave(candidatePlayer)
        if not json then error("编码失败") end
        checkEpoch()
        if not fileSystem or not fileSystem.Rename then error("无安全替换接口") end
        file = File(TEMP_SAVE_FILE, FILE_WRITE)
        checkEpoch()
        if not file or file:IsOpen() ~= true then error("无法打开临时文件") end
        checkEpoch()
        if file:WriteString(json) ~= true then error("写入未完成") end
        checkEpoch()
        local closed, closeErr = closeFile()
        if not closed then error(closeErr) end
        checkEpoch()
        -- Rename返回true就是提交点；此后Wipe/Restore是新的生命周期，不能反报旧事务失败。
        if fileSystem:Rename(TEMP_SAVE_FILE, SAVE_FILE) ~= true then error("替换未完成") end
    end)
    if not ok then
        closeFile()
        -- Wipe/Restore 已建立新生命周期，旧提交不能回写旧在线时刻或重新安排旧重试。
        if epoch == saveEpoch then
            lastSavedAt = previousSavedAt
            if session then session.lastOnlineTime = previousOnline end
            flushTimer = RETRY_INTERVAL
        end
        deleteTempFile()
        writing = false
        print("[StandaloneSave] 写档失败: " .. tostring(err))
        return false
    end
    local reconciled, reconcileErr = pcall(function()
        if epoch ~= saveEpoch then return end
        if not commitReceipt then return end
        -- 先取全部当前源，可能的重入恢复结束后再取得镜像引用；旧任务不碰新生命周期。
        local currentModules = ClientDispatcher.snapshotAll()
        if epoch ~= saveEpoch then return end
        local currentState = GameState.exportSave()
        if epoch ~= saveEpoch then return end
        local mirror = detectorSnapshot
        local modules = mirror and mirror.modules
        for name, committed in next, commitReceipt.modules do
            local savedModule = type(modules) == "table" and rawget(modules, name) or nil
            local currentModule = rawget(currentModules, name)
            if currentModule == committed.source then
                reconcileCommitFields(type(savedModule) == "table" and savedModule or nil,
                    currentModule, committed.values, committed.expected)
            else
                -- 模块换表/删除属于提交后的新修改，旧引用和旧镜像都不能代表新提交。
                StandaloneSave.RequestSave()
            end
        end
        for name in next, currentModules do
            if not commitReceipt.modules[name] then StandaloneSave.RequestSave() end
        end
        reconcileCommitFields(mirror and type(mirror.gameState) == "table" and mirror.gameState or nil,
            currentState, commitReceipt.gameState, commitReceipt.expectedState)
        -- 小型GameState副本换成提交后当前值，不能用旧候选吞掉文件回调中的新变化。
        -- 不深拷贝/对齐全库存，也不重置扫描尾部进度。
        local scan = detectorScan
        if scan then
            local root = scan.stack[1]
            local previousState = root and root.source.gameState
            if root then root.source.gameState = currentState end
            for _, frame in ipairs(scan.stack) do
                if frame.source == previousState then frame.source = currentState end
            end
        end
    end)
    -- 磁盘已经提交，镜像维护故障不能把成功伪装成可重领奖的失败。
    -- 保留只读检测兜底；也不能因此让单写者锁永远不释放。
    if not reconciled then print("[StandaloneSave] 提交后检测维护失败: " .. tostring(reconcileErr)) end
    if epoch == saveEpoch and revision == requestRevision then flushTimer = nil end
    writing = false
    print("[StandaloneSave] 存档落盘 bytes=" .. #json)
    return true
end

--- 恢复纯数据（GameState + Dispatcher 各模块）
--- ⚠️ 必须在 Standalone.Start() 的 UI/数据初始化之前调用
--- （各系统初始化均为 "if not ClientDispatcher.get(x)" 守卫，先注入即跳过默认值）
---@return boolean 是否恢复了存档
function StandaloneSave.RestoreData()
    saveEpoch = saveEpoch + 1
    requestRevision = 0
    deleteTempFile()
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
    -- 按旧接口读档，句柄检查/读取/关闭全部隔离；坏档不允许未关闭对象遗留。
    local file = nil ---@type File|nil
    local readOk, json = pcall(function()
        file = File(SAVE_FILE, FILE_READ)
        if not file or file:IsOpen() ~= true then error("无法打开存档") end
        return file:ReadString()
    end)
    local closeOk, closeErr = pcall(function() if file then file:Close() end end)
    local disposeOk, disposeErr = pcall(function() if file and file.Dispose then file:Dispose() end end)
    file = nil
    if not readOk or not closeOk or not disposeOk or type(json) ~= "string" then
        print("[StandaloneSave] 读档失败: " .. tostring(not readOk and json or closeErr or disposeErr))
        return false
    end

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
    if writing then return end
    dt = dt or 0
    if type(dt) ~= "number" or dt ~= dt or dt < 0 or dt == math.huge then dt = 0 end
    -- 固定最大合并期限；新变化只置脏，不延后首次请求。Flush当帧不再检测第二遍。
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

--- 清档使旧请求/扫描/重入写入失效；不触发旧收益或重新保存旧会话。
function StandaloneSave.Wipe()
    saveEpoch = saveEpoch + 1
    requestRevision = 0
    restoredSavedAt = 0
    lastSavedAt = 0
    restoredSave = false
    offlineChecked = false
    resetDetector()
    flushTimer = nil
    deleteTempFile()
    local deleted, deleteErr = pcall(function()
        if fileSystem and fileSystem.Delete then fileSystem:Delete(SAVE_FILE) end
    end)
    if not deleted then print("[StandaloneSave] 清档删除失败: " .. tostring(deleteErr)) end
    print("[StandaloneSave] wiped " .. SAVE_FILE)
end

---@param candidatePlayer table|nil 副本事务的待提交玩家进度；普通自动存档不传
function StandaloneSave.Flush(candidatePlayer)
    return writeFile(candidatePlayer)
end

return StandaloneSave
