-- ============================================================================
-- BattleDiag - 战斗数据完整性守卫
-- 功能：
--   1. 防御性 guard：attrs 为 nil 时安全跳过，阻断级联崩溃
--   2. 关键事件日志：定位数据丢失的时机和路径
--   3. attrs 写入哨兵：拦截 attrs 被意外置 nil 的操作
-- 本模块是正式代码，不是临时诊断（已证实防御逻辑可阻断级联故障）
-- ============================================================================

local BattleDiag = {}

-- 控制日志输出（guard 逻辑始终生效，仅日志可关闭；生产默认关，避免热路径 print 拖慢战斗）
BattleDiag.logEnabled = false

-- 日志限流：同一 key 每 N 秒只打印一次，避免刷屏
local _lastLog = {}   -- { [key] = lastTime }
local _logCounts = {} -- { [key] = count }
local THROTTLE_SEC = 10.0  -- 正式模式：10秒限流

local function getTime()
    return os.clock()
end

--- 带限流的日志输出
---@param key string 去重 key
---@param msg string 日志内容
local function throttledLog(key, msg)
    if not BattleDiag.logEnabled then return end
    local now = getTime()
    _logCounts[key] = (_logCounts[key] or 0) + 1
    local last = _lastLog[key]
    if last and (now - last) < THROTTLE_SEC then return end
    _lastLog[key] = now
    local count = _logCounts[key]
    local prefix = "[BattleGuard]"
    if count > 1 then
        prefix = prefix .. "(x" .. count .. ")"
    end
    print(prefix .. " " .. msg)
end

--- 重要事件日志（每次都打印，但同一 key 10秒内合并）
---@param key string
---@param msg string
local function logOnce(key, msg)
    if not BattleDiag.logEnabled then return end
    local now = getTime()
    local last = _lastLog[key]
    if last and (now - last) < THROTTLE_SEC then return end
    _lastLog[key] = now
    print("[BattleGuard] " .. msg)
end

-- ============================================================================
-- 防御点 #1: findUnitIndex 返回 nil
-- 场景：攻击者不在列表中 → 投射物位置回退到 slot 1
-- ============================================================================

---@param attacker table
---@param allyList table
---@param isAlly boolean
---@param context string
function BattleDiag.onFindUnitFailed(attacker, allyList, isAlly, context, extra)
    local id = attacker.heroId or attacker.monsterId or attacker.instanceId or "?"
    local name = attacker.name or "unknown"
    local listLen = #allyList
    local hp = attacker.hp or -1
    local hasAttrs = attacker.attrs ~= nil

    -- 检查是否同 id 仍在列表中（引用丢失 vs 真的不在列表）
    local foundById = false
    local foundByInstance = false
    for _, u in ipairs(allyList) do
        if attacker.heroId and u.heroId == attacker.heroId then foundById = true end
        if attacker.instanceId and u.instanceId == attacker.instanceId then foundByInstance = true end
    end

    local key = "find_nil_" .. tostring(id) .. "_" .. context
    logOnce(key, string.format(
        "FIND_UNIT_NIL [%s] side=%s name=%s id=%s hp=%d hasAttrs=%s listLen=%d byId=%s byInst=%s",
        context, isAlly and "ally" or "enemy",
        name, tostring(id), hp, tostring(hasAttrs), listLen,
        tostring(foundById), tostring(foundByInstance)
    ))

    -- ===== 增强诊断：table identity + 列表内容 dump + 调用深度 =====
    local extra = extra or {}
    -- 1) 攻击者完整身份
    print(string.format(
        "[BattleGuard] DIAG_DETAIL attacker_ref=%s instId=%s heroId=%s monsterId=%s name=%s hp=%s",
        tostring(attacker), tostring(attacker.instanceId), tostring(attacker.heroId),
        tostring(attacker.monsterId), tostring(attacker.name), tostring(attacker.hp)
    ))
    -- 2) table identity：传入的 allyList vs ctx 返回的当前 list
    local ctxTableId = extra.ctxTableId or "N/A"
    local callDepth = extra.callDepth or 0
    print(string.format(
        "[BattleGuard] DIAG_TABLE allyList_ref=%s ctx_current_ref=%s same=%s callDepth=%d",
        tostring(allyList), ctxTableId,
        tostring(tostring(allyList) == ctxTableId), callDepth
    ))
    -- 3) 列表内容 dump（最多打印前 12 个 unit 的 id）
    local parts = {}
    for i, u in ipairs(allyList) do
        if i > 12 then parts[#parts + 1] = "...+" .. (#allyList - 12); break end
        parts[#parts + 1] = string.format("[%d]%s/%s/%s(hp%s)",
            i, tostring(u.instanceId), tostring(u.heroId),
            tostring(u.monsterId), tostring(u.hp))
    end
    print("[BattleGuard] DIAG_LIST " .. table.concat(parts, " "))
end

-- ============================================================================
-- 防御点 #2: attrs 为 nil（调用方应 early return）
-- ============================================================================

---@param unit table
---@param context string
function BattleDiag.onAttrsNil(unit, context)
    local id = unit.heroId or unit.monsterId or unit.instanceId or "?"
    local name = unit.name or "unknown"
    local hp = unit.hp or -1
    local maxHp = unit.maxHp or -1

    local key = "attrs_nil_" .. tostring(id) .. "_" .. context
    logOnce(key, string.format(
        "ATTRS_NIL [%s] name=%s id=%s hp=%d maxHp=%d revive=%s _sentinel=%s",
        context, name, tostring(id), hp, maxHp,
        tostring(unit.reviveTimer ~= nil),
        tostring(unit._attrsSetNilTrace or "none")
    ))
end

-- ============================================================================
-- 防御点 #3: 治疗为 0（heal 返回 0 但 healAmt > 0）
-- ============================================================================

---@param attacker table
---@param target table
---@param healAmount number
---@param actualHeal number
---@param context string
function BattleDiag.onHealZero(attacker, target, healAmount, actualHeal, context)
    local atkId = attacker.heroId or attacker.name or "?"
    local tgtId = target.heroId or target.name or "?"
    local tgtHp = target.hp or -1
    local tgtMaxHp = target.maxHp or -1
    local hasAttrs = target.attrs ~= nil

    local key = "heal0_" .. tostring(tgtId)
    local msg = string.format(
        "HEAL_ZERO [%s] healer=%s target=%s healAmt=%d actual=%d hp=%d/%d hasAttrs=%s",
        context, tostring(atkId), tostring(tgtId),
        healAmount, actualHeal, tgtHp, tgtMaxHp, tostring(hasAttrs)
    )

    if hasAttrs then
        local AD = require("systems.AttributeDef")
        local attrHp = target.attrs:get(AD.HP)
        local attrMaxHp = target.attrs:get(AD.MAX_HP)
        local frac = target.attrs._healFrac or 0
        msg = msg .. string.format(" attrHp=%.0f/%.0f frac=%.3f", attrHp, attrMaxHp, frac)
    end

    logOnce(key, msg)
end

-- ============================================================================
-- 防御点 #4: 定期完整性扫描（降频至 15 秒）
-- ============================================================================

local _integrityTimer = 0
local INTEGRITY_INTERVAL = 60.0

---@param dt number
---@param allies table
---@param enemies table
function BattleDiag.update(dt, allies, enemies)
    _integrityTimer = _integrityTimer + dt
    if _integrityTimer < INTEGRITY_INTERVAL then return end
    _integrityTimer = 0

    if not BattleDiag.logEnabled then return end

    local AD = require("systems.AttributeDef")

    -- 扫描己方
    for i, u in ipairs(allies) do
        if u.hp > 0 then
            if not u.attrs then
                BattleDiag.onAttrsNil(u, "scan_ally_" .. i)
            elseif u.attrs.final then
                local attrHp = u.attrs.final[AD.HP] or 0
                if math.abs(attrHp - u.hp) > 1 then
                    throttledLog("desync_a" .. i, string.format(
                        "HP_DESYNC ally[%d] %s unit.hp=%d attrs.hp=%d",
                        i, u.name or "?", u.hp, attrHp))
                end
                -- [HealDiag3] 定期检查存活治疗者是否治疗量归零
                if AD.getAtkCategory(u.attrs.atkType) == "healing" then
                    local healAmt = u.attrs:get(AD.HEAL_AMOUNT)
                    if healAmt <= 0 then
                        local snapHeal = u._baseSnapshot and u._baseSnapshot:get(AD.HEAL_AMOUNT) or -1
                        throttledLog("healer_zero_a" .. i, string.format(
                            "[HealDiag3] HEALER_LIVE_ZERO ally[%d] %s(id%s) healAmt=%.1f snapHeal=%.1f hp=%d/%d",
                            i, u.name or "?", tostring(u.heroId or "?"),
                            healAmt, snapHeal, u.hp, u.maxHp or 0))
                    end
                elseif u._diagInitHealer then
                    -- [HealDiag3] 初始治疗者的 atkType 被破坏（不再识别为 healing）
                    throttledLog("healer_type_lost_a" .. i, string.format(
                        "[HealDiag3] HEALER_TYPE_LOST ally[%d] %s(id%s) atkType=%s expected=healing hp=%d/%d",
                        i, u.name or "?", tostring(u.heroId or "?"),
                        tostring(u.attrs.atkType), u.hp, u.maxHp or 0))
                end
            end
        end
    end

    -- 扫描敌方
    for i, u in ipairs(enemies) do
        if u.hp > 0 then
            if not u.attrs then
                BattleDiag.onAttrsNil(u, "scan_enemy_" .. i)
            elseif u.attrs.final then
                local attrHp = u.attrs.final[AD.HP] or 0
                if math.abs(attrHp - u.hp) > 1 then
                    throttledLog("desync_e" .. i, string.format(
                        "HP_DESYNC enemy[%d] %s unit.hp=%d attrs.hp=%d",
                        i, u.name or "?", u.hp, attrHp))
                end
            end
        end
    end
end

-- ============================================================================
-- 哨兵系统：追踪 attrs 被置 nil 的操作
-- 原理：给 unit table 设置 __newindex 元表，当 attrs 被赋值为 nil 时
--       记录调用栈到 unit._attrsSetNilTrace
-- ============================================================================

--- 为单位安装 attrs 写入哨兵
--- 调用时机：单位创建后、加入 allies/enemies 列表时
---@param unit table 战斗单位
function BattleDiag.installSentinel(unit)
    if not unit or unit._sentinelInstalled then return end

    -- 把现有字段存入内部 store
    local store = {}
    for k, v in pairs(unit) do
        store[k] = v
        unit[k] = nil  -- 清空原始字段，由元表代理
    end

    local mt = {
        __index = store,
        __newindex = function(t, k, v)
            if k == "attrs" and v == nil and store.attrs ~= nil then
                -- attrs 从有值变为 nil！记录调用栈
                local trace = debug.traceback("attrs set to nil", 2)
                store._attrsSetNilTrace = trace
                if BattleDiag.logEnabled then
                    local id = store.heroId or store.monsterId or store.instanceId or "?"
                    print("[BattleGuard] SENTINEL: attrs=nil on " ..
                        (store.name or "?") .. " id=" .. tostring(id))
                    print(trace)
                end
            end
            store[k] = v
        end,
        -- pairs/ipairs 支持
        __pairs = function()
            return next, store, nil
        end,
    }
    setmetatable(unit, mt)
    unit._sentinelInstalled = true
end

--- 重置诊断状态（新战斗开始时调用）
function BattleDiag.reset()
    _integrityTimer = 0
    _lastLog = {}
    _logCounts = {}
end

--- 即时完整性扫描（战斗开始后立即调用，不受限流）
--- 检查所有单位的 attrs 是否为 nil，输出完整状态快照
---@param allies table
---@param enemies table
---@param context string 调用来源标记
function BattleDiag.scanNow(allies, enemies, context)
    if not BattleDiag.logEnabled then return end
    local issues = 0
    local ctx = context or "scanNow"

    for i, u in ipairs(allies) do
        if not u.attrs then
            issues = issues + 1
            print(string.format(
                "[BattleDiag] SCAN_ISSUE [%s] ally[%d] name=%s id=%s hp=%d maxHp=%d attrs=NIL sentinel=%s",
                ctx, i, u.name or "?",
                tostring(u.heroId or u.instanceId or "?"),
                u.hp or -1, u.maxHp or -1,
                tostring(u._sentinelInstalled or false)))
        end
    end

    for i, u in ipairs(enemies) do
        if not u.attrs then
            issues = issues + 1
            print(string.format(
                "[BattleDiag] SCAN_ISSUE [%s] enemy[%d] name=%s id=%s hp=%d maxHp=%d attrs=NIL sentinel=%s",
                ctx, i, u.name or "?",
                tostring(u.monsterId or u.instanceId or "?"),
                u.hp or -1, u.maxHp or -1,
                tostring(u._sentinelInstalled or false)))
        end
    end

    if issues == 0 then
        print(string.format("[BattleDiag] SCAN_OK [%s] allies=%d enemies=%d all_have_attrs",
            ctx, #allies, #enemies))
    else
        print(string.format("[BattleDiag] SCAN_FAIL [%s] issues=%d allies=%d enemies=%d",
            ctx, issues, #allies, #enemies))
    end
end

return BattleDiag
