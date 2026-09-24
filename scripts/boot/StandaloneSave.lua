-- ============================================================================
-- StandaloneSave - 单机模式本地存档（无联网）
-- 职责:
--   1. 快照 ClientDispatcher 全部模块数据 + GameState 单机本地 state
--   2. 变更检测（每秒全量 JSON 对比）→ 防抖落盘本地 File
--   3. 启动时恢复（纯数据先注入，battle 进度待场景就绪后回灌）
-- 运行端: 仅 Standalone（multiplayer.enabled=false）
-- 注意: 多人模式的持久化走 serverCloud + SaveManager（Server.lua），与本模块无关
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
local BattleScene      = require("ui.BattleScene")

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

--- 收集当前全部可持久化数据 → 存档表
local function buildSaveData()
    local all = ClientDispatcher.snapshotAll()
    local modules = {}
    for name, data in pairs(all) do
        modules[name] = data
    end
    return {
        version   = SAVE_VERSION,
        savedAt   = os.time(),
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

--- 写盘（不传 json 则实时编码）
local function writeFile(json)
    if not json then
        json = encodeSave()
        if not json then return false end
    end
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

    lastSnapshot = nil  -- 恢复后重建基线，防止把恢复内容误判为变更
    print("[StandaloneSave] 存档已恢复: " .. #names .. " 个模块 savedAt=" .. tostring(saveData.savedAt))
    return true
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
        flushTimer = FLUSH_DEBOUNCE
    end
end

--- 立即落盘（退出时调用）
function StandaloneSave.Flush()
    writeFile()
end

return StandaloneSave
