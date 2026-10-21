-- ============================================================================
-- BattleCombatFx - 即时飘字 / 原始数值短窗叠加 / 对象池 / 受击闪烁
-- 状态只写调用方BCS；显示合并不合并伤害结算、统计或命中回调。
-- ============================================================================

local SettingsPanel = require("ui.hud.popup.SettingsPanel")
local NumberUtil = require("core.NumberUtil")
local DamageTypeIcon = require("ui.battle.scene.DamageTypeIcon")

local M = {}
local FLOAT_DURATION = 0.7
local MERGE_WINDOW = 0.2
local MAX_FLOATING_TEXTS = 15
local HIT_FLASH_DURATION = 0.3
-- 出生候选围绕受击点交错，而不是固定上/中/下三排；单位为战场设计坐标。
local SPREAD_POINTS = {
    { 0, -6 }, { -20, -54 }, { 24, 46 }, { 28, -28 },
    { -24, 72 }, { 12, -76 }, { -28, 20 }, { 24, -64 },
    { -8, 58 }, { 16, -18 }, { 8, 82 }, { -16, -42 },
    { 32, 8 }, { -32, -86 }, { -4, 34 },
}
M.FLOAT_DURATION = FLOAT_DURATION
M.MERGE_WINDOW = MERGE_WINDOW
M.MAX_FLOATING_TEXTS = MAX_FLOATING_TEXTS
M.FLOAT_MOVE_DIST = 240
M.HIT_FLASH_DURATION = HIT_FLASH_DURATION

local function ensureState(BCS)
    BCS.floatingTexts = BCS.floatingTexts or {}
    BCS.ftPool = BCS.ftPool or {}
    BCS.combatNumberIndex = BCS.combatNumberIndex or {}
end

local function acquireFt(BCS)
    local n = #BCS.ftPool
    if n > 0 then
        local ft = BCS.ftPool[n]
        BCS.ftPool[n] = nil
        return ft
    end
    return {}
end

local function releaseFt(BCS, ft)
    -- 索引只保当前批次；旧批次到期不能误删同目标刚创建的新批次。
    local target = ft.target
    local targetIndex = target and BCS.combatNumberIndex[target]
    if targetIndex then
        local channelIndex = targetIndex[ft.channel]
        if channelIndex and channelIndex[ft.atkType] == ft then
            channelIndex[ft.atkType] = nil
            if next(channelIndex) == nil then targetIndex[ft.channel] = nil end
            if next(targetIndex) == nil then BCS.combatNumberIndex[target] = nil end
        end
    end
    -- target/amount/flags/位置都清理，池不能持有退场单位或上个批次语义。
    for key in pairs(ft) do ft[key] = nil end
    if #BCS.ftPool < MAX_FLOATING_TEXTS then BCS.ftPool[#BCS.ftPool + 1] = ft end
end

-- 只在出生时挑一次空位；最多15×15次距离比较，不搬动已显示的数字。
-- 用扁椭圆近似读数区：横向140、纵向48，优先纵向留白，邻卡也参与避让。
local function chooseSpread(BCS, cx, cy, sequence)
    local bestX, bestY, bestScore = 0.0, 0.0, -1.0
    for step = 1, #SPREAD_POINTS do
        local candidate = SPREAD_POINTS[(sequence + step - 2) % #SPREAD_POINTS + 1]
        ---@cast candidate number[]
        local x, y = cx + candidate[1], cy + candidate[2]
        local score = math.huge
        for _, ft in ipairs(BCS.floatingTexts) do
            local progress = math.min(1, ft.timer / ft.duration)
            local drift = (1 - (1 - progress) ^ 3) * 22
            local dx = (x - ft.x - (ft.spreadX or 0)) / 140
            local dy = (y - ft.y - (ft.spreadY or 0) + drift) / 48
            score = math.min(score, dx * dx + dy * dy)
        end
        if score > bestScore then
            bestX, bestY, bestScore = candidate[1], candidate[2], score
        end
        if score >= 1 then break end
    end
    return bestX, bestY
end

local function spawn(BCS, text, cx, cy, color, isCrit, fontSize, kind)
    ensureState(BCS)
    while #BCS.floatingTexts >= MAX_FLOATING_TEXTS do
        local oldest = table.remove(BCS.floatingTexts, 1)
        releaseFt(BCS, oldest)
    end
    -- 确定性轻微分散：纯视觉不消费/重置 gameplay math.random。
    BCS.ftSequence = (BCS.ftSequence or 0) + 1
    local angle = -math.pi * 0.5 + ((BCS.ftSequence % 5) - 2) * 0.14
    local entry = acquireFt(BCS)
    entry.text = text
    entry.x, entry.y = cx, cy
    entry.visualSequence = BCS.ftSequence
    entry.spreadX, entry.spreadY = chooseSpread(BCS, cx, cy, BCS.ftSequence)
    entry.dirX, entry.dirY = math.cos(angle), math.sin(angle)
    entry.timer, entry.duration = 0, FLOAT_DURATION
    entry.color = color or { 255, 255, 255 }
    entry.isCrit = isCrit or false
    entry.baseFontSize = fontSize or 80
    entry.fontSize = entry.baseFontSize * (entry.isCrit and 2 or 1)
    entry.kind = kind
    BCS.floatingTexts[#BCS.floatingTexts + 1] = entry
    return entry
end

-- 保留非数字提示API与参数；deferred兼容但忽略，不再存在待显示队列。
function M.addFloatingText(BCS, text, cx, cy, color, isCrit, fontSize, deferred, kind)
    return spawn(BCS, text, cx, cy, color, isCrit, fontSize, kind)
end

---@param BCS table
---@param target table
---@param amount number 原始数值，不解析格式化字符串
---@param meta? DamageNumberMeta
function M.addCombatNumber(BCS, target, amount, cx, cy, meta)
    if type(target) ~= "table" or type(amount) ~= "number" or amount <= 0
        or amount ~= amount or amount == math.huge then return nil end
    ensureState(BCS)
    meta = meta or {}
    local visual = DamageTypeIcon.resolve({
        channel = meta.channel or "damage", atkType = meta.atkType, floatKind = meta.floatKind,
        isCrit = meta.isCrit, isBlocked = meta.isBlocked, isDot = meta.isDot,
    })
    local channel, atkType = visual.channel, visual.atkType
    local targetIndex = BCS.combatNumberIndex[target]
    local channelIndex = targetIndex and targetIndex[channel]
    local current = channelIndex and channelIndex[atkType]
    if current and current.timer < current.duration
        and current.timer - current.lastMergeTimer <= MERGE_WINDOW then
        current.amount = current.amount + amount
        current.text = (channel == "heal" and "+" or "") .. NumberUtil.format(current.amount)
        current.lastMergeTimer = current.timer
        current.pulseTimer = 0.12
        current.isCrit = current.isCrit or visual.isCrit
        current.isBlocked = current.isBlocked or visual.isBlocked
        current.isDot = current.isDot or visual.isDot
        current.fontSize = current.baseFontSize * (current.isCrit and 2 or 1)
        current.color = meta.color or DamageTypeIcon.color(current)
        -- 不重置timer/duration，机关枪持续叠加也至多占据0.7秒。
        return current
    end
    local entry = spawn(BCS, (channel == "heal" and "+" or "") .. NumberUtil.format(amount),
        cx, cy, meta.color or DamageTypeIcon.color(visual), visual.isCrit, meta.fontSize, meta.floatKind)
    entry.target, entry.amount = target, amount
    entry.channel, entry.atkType = channel, atkType
    entry.isBlocked, entry.isDot = visual.isBlocked, visual.isDot
    entry.lastMergeTimer, entry.pulseTimer = 0, 0
    -- spawn可能淘汰刚才同目标的最旧文字，因此重新取索引。
    targetIndex = BCS.combatNumberIndex[target] or {}
    BCS.combatNumberIndex[target] = targetIndex
    channelIndex = targetIndex[channel] or {}
    targetIndex[channel] = channelIndex
    channelIndex[atkType] = entry
    return entry
end

function M.updateFloatingTexts(BCS, dt)
    ensureState(BCS)
    local i = 1
    while i <= #BCS.floatingTexts do
        local ft = BCS.floatingTexts[i]
        ft.timer = ft.timer + dt
        if ft.pulseTimer then ft.pulseTimer = math.max(0, ft.pulseTimer - dt) end
        if ft.timer >= ft.duration then
            releaseFt(BCS, ft)
            table.remove(BCS.floatingTexts, i)
        else
            i = i + 1
        end
    end
end

function M.resetFloatingTexts(BCS)
    ensureState(BCS)
    for _, ft in ipairs(BCS.floatingTexts) do releaseFt(BCS, ft) end
    BCS.floatingTexts, BCS.combatNumberIndex = {}, {}
    BCS.ftSequence = 0
    -- 旧BCS/宿主兼容字段只清理，永不出队或重放。
    BCS.pendingFt, BCS.ftSpawnCd = nil, nil
end

function M.setHitFlash(BCS, target)
    if not SettingsPanel.isEffectsEnabled() then return end
    BCS.hitFlashes[target] = { timer = 0 }
end

function M.updateHitFlashes(BCS, dt)
    local toRemove = {}
    for unit, flash in pairs(BCS.hitFlashes) do
        flash.timer = flash.timer + dt
        if flash.timer >= HIT_FLASH_DURATION then toRemove[#toRemove + 1] = unit end
    end
    for _, unit in ipairs(toRemove) do BCS.hitFlashes[unit] = nil end
end

function M.getHitFlashAlpha(BCS, unit)
    if not SettingsPanel.isEffectsEnabled() then return 0 end
    local flash = BCS.hitFlashes[unit]
    if not flash then return 0 end
    -- 局部低亮回声替代长平台闪白；仍在原0.3秒寿命内，不做hitstop。
    local t = math.max(0, math.min(1, flash.timer / HIT_FLASH_DURATION))
    local q = 1 - t
    return math.floor(72 * q * q * q)
end

function M.clearHitFlash(BCS, unit) BCS.hitFlashes[unit] = nil end
return M
