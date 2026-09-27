-- ============================================================================
-- StandaloneSave - 单机模式本地存档
-- 读写 save.json。这是单机唯一落盘路径。
-- 职责:
--   1. 快照 ClientDispatcher 全部模块数据 + GameState 单机本地 state
--   2. 变更检测（每秒全量 JSON 对比）→ 防抖落盘本地 File
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
local OfflineService   = require("rules.offline.OfflineService")

local StandaloneSave = {}

local SAVE_FILE         = "standalone_save.json"
local SAVE_VERSION      = 1
local SNAPSHOT_INTERVAL = 1.0   -- 快照对比周期（秒）
local FLUSH_DEBOUNCE    = 2.0   -- 变更后写盘防抖（秒）

---@type string|nil  上次快照 JSON（nil = 尚未建立基线）
local lastSnapshot = nil
---@type number  快照计时
local snapshotAcc = 0.0
---@type number|nil  防抖写盘剩余时间（nil = 无待写变更）
local flushTimer = nil
local restoredSavedAt = 0  -- 当前进程启动前最后一次落盘；用于兼容旧存档的在线边界
local restoredSave = false
local offlineChecked = false
local lastSavedAt = 0

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

--- 收集当前全部可持久化数据 → 存档表
local function buildSaveData()
    local all = ClientDispatcher.snapshotAll()
    local modules = {}
    for name, data in pairs(all) do
        if name == "heroes" and type(data) == "table" then
            local copy = {}
            for k, v in pairs(data) do copy[k] = v end
            copy.roster = rosterForSave(data.roster)
            modules[name] = copy
        else
            modules[name] = data
        end
    end
    return {
        version   = SAVE_VERSION,
        savedAt   = lastSavedAt,
        gameState = GameState.exportSave(),
        modules   = modules,
    }
end

--- 编码存档 JSON；成功返回字符串，失败返回 nil
local function encodeSave()
    local ok, json = pcall(cjson.encode, buildSaveData())
    if not ok or type(json) ~= "string" then
        print("[StandaloneSave] encode 失败: " .. tostring(json))
        return nil
    end
    return json
end

--- 离线收益尚未核算或尚待领取时，不改写旧存档的时间边界。
local function writeFile()
    if not offlineChecked or OfflineService.HasPendingRewards(1) then return false end
    OfflineService.MarkOnline(1)
    lastSavedAt = os.time()
    local json = encodeSave()
    if not json then return false end
    local file = File(SAVE_FILE, FILE_WRITE)
    if not file or not file:IsOpen() then
        print("[StandaloneSave] 写档失败(无法打开): " .. SAVE_FILE)
        return false
    end
    file:WriteString(json)
    file:Close()
    lastSnapshot = json
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
    lastSnapshot = nil
    flushTimer = nil
    snapshotAcc = 0
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

    -- 2. 恢复各模块（经 handleStateUpdate 统一走 onLoad 修正 + 订阅通知）
    local names = {}
    for name, data in pairs(saveData.modules) do
        ClientDispatcher.handleStateUpdate(cjson.encode({ modules = { [name] = data } }))
        names[#names + 1] = name
    end

    restoredSavedAt = tonumber(saveData.savedAt) or 0
    lastSavedAt = restoredSavedAt
    restoredSave = true
    lastSnapshot = nil  -- 恢复后重建基线，防止把恢复内容误判为变更
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

--- 离线收益已核算；只有不存在待领取奖励时才允许写档和推进在线边界。
function StandaloneSave.OfflineChecked()
    offlineChecked = true
    lastSnapshot = nil
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
    BattleScene.setBattleData(battle)
    print("[StandaloneSave] 战斗进度已回灌 maxStageId=" .. tostring(battle.maxStageId))
end

--- 主循环更新（由 Standalone.HandleUpdate 调用）
---@param dt number
function StandaloneSave.Update(dt)
    if not offlineChecked or OfflineService.HasPendingRewards(1) then return end
    -- 防抖写盘
    if flushTimer then
        flushTimer = flushTimer - dt
        if flushTimer <= 0 then
            flushTimer = nil
            writeFile()
        end
    end

    -- 周期快照对比
    snapshotAcc = snapshotAcc + (dt or 0)
    if snapshotAcc < SNAPSHOT_INTERVAL then return end
    snapshotAcc = 0

    local json = encodeSave()
    if not json then return end
    if lastSnapshot == nil then
        lastSnapshot = json  -- 首次基线（含恢复后的状态）
        return
    end
    if json ~= lastSnapshot then
        lastSnapshot = json
        -- 掉落会持续改变快照；已有待写计时不能每秒重置，否则永远无法落盘。
        if not flushTimer then flushTimer = FLUSH_DEBOUNCE end
    end
end

--- 立即落盘（退出时调用）
function StandaloneSave.Wipe()
    restoredSavedAt = 0
    lastSavedAt = 0
    restoredSave = false
    offlineChecked = false
    lastSnapshot = nil
    snapshotAcc = 0
    flushTimer = nil
    if fileSystem and fileSystem.Delete then
        fileSystem:Delete(SAVE_FILE)
    end
    print("[StandaloneSave] wiped " .. SAVE_FILE)
end

function StandaloneSave.Flush()
    writeFile()
end

return StandaloneSave
