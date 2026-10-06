-- 程序化卡片特效；保留旧模块/API 名称，不持有原生 Spine 资源。
-- 坐标/尺寸属于调用者当前 NanoVG 空间（本模块不再乘 DPR/fit）。
-- 所有时间线直接采样 time.elapsedTime - startedAt；update(dt) 仅派发完成回调。
local SpineCardEffect = {}
local BattleLayout = require("core.BattleLayout")
local DURATION = { level = 1.3333, job = 1.3333, revive = 0.9 }
local MAX_ACTIVE = 32

---@class DarkCardSize
---@field width? number
---@field height? number
---@field size? number 宽度；高度按真实卡框比例计算。
---@class DarkCardPlayback
---@field kind DarkCardEffectKind
---@field scope string
---@field cx number
---@field cy number
---@field width number
---@field height number
---@field startedAt number
---@field duration number
---@field onComplete function|nil
---@field finished boolean
---@type DarkCardPlayback[]
local activeInstances = {}
local cancelEpoch = 0
local scopeEpochs = {} ---@type table<string, number>
local disabled = false

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function clock()
    local now = time and time.elapsedTime
    if finite(now) and now >= 0 then return now end
    return nil
end

local function dispatch(entry)
    local cb = entry.onComplete
    entry.onComplete = nil
    print("[SpineCardEffect] 完成 " .. entry.kind .. " scope=" .. entry.scope)
    if cb then
        local ok, err = pcall(cb)
        if not ok then print("[SpineCardEffect] 完成回调失败: " .. tostring(err)) end
    end
end

-- 整批到期记录先脱离列表，再执行回调；回调重入 play 不会被旧清理删除。
-- 某回调调用 stopAll/destroy 时，本批尚未派发且匹配取消范围的回调也取消。
local function expire(now)
    if not now or #activeInstances == 0 then return end
    local remaining, done = {}, {} ---@type DarkCardPlayback[], DarkCardPlayback[]
    for _, entry in ipairs(activeInstances) do
        if now - entry.startedAt >= entry.duration then
            entry.finished = true
            done[#done + 1] = entry
        else
            remaining[#remaining + 1] = entry
        end
    end
    local scopeVersions = {} ---@type table<string, number>
    for _, entry in ipairs(done) do scopeVersions[entry.scope] = scopeEpochs[entry.scope] or 0 end
    activeInstances = remaining
    local epoch = cancelEpoch
    for _, entry in ipairs(done) do
        if cancelEpoch == epoch and (scopeEpochs[entry.scope] or 0) == scopeVersions[entry.scope] then
            dispatch(entry)
        else
            entry.onComplete = nil
        end
    end
end

---@param width number|DarkCardSize|nil
---@param height number|nil
---@return number|nil, number|nil
local function dimensions(width, height)
    if type(width) == "table" then
        height = width.height
        width = width.width or width.size
    end
    local w = width or BattleLayout.CARD_W
    if not finite(w) or w <= 0 then return nil end
    local h = height or (w * BattleLayout.CARD_H / BattleLayout.CARD_W)
    if not finite(h) or h <= 0 then return nil end
    return w, h
end

---@param kind DarkCardEffectKind
---@param cx number
---@param cy number
---@param onComplete function|nil
---@param scope string|number|DarkCardSize|nil
---@param width number|DarkCardSize|nil
---@param height number|nil
---@param defaultScope string
local function play(kind, cx, cy, onComplete, scope, width, height, defaultScope)
    -- 可省略 scope，直接追加宽度或 {width,height}/size 选项。
    if scope ~= nil and type(scope) ~= "string" then
        height = type(width) == "number" and width or height
        width, scope = scope, defaultScope
    end
    scope = scope or defaultScope
    local now = clock()
    local w, h = dimensions(width, height)
    if not now or not finite(cx) or not finite(cy) or not w or not h
        or (onComplete ~= nil and type(onComplete) ~= "function") then
        print("[SpineCardEffect] 拒绝无效播放参数")
        return
    end
    expire(now)
    -- 同位置的连续升级重启并复用一条记录，不叠加无界特效队列。
    -- 被替换的旧回调取消而非完成，等同显式 stopAll 的语义。
    if kind == "level" then
        for _, entry in ipairs(activeInstances) do
            if entry.kind == kind and entry.scope == scope and entry.cx == cx and entry.cy == cy then
                entry.startedAt, entry.width, entry.height, entry.onComplete = now, w, h, onComplete
                print("[SpineCardEffect] 替换连续升级 scope=" .. scope)
                return
            end
        end
    end
    -- 全局硬上限：丢弃最老记录并取消其回调；必须明确记录丢弃日志。
    if #activeInstances >= MAX_ACTIVE then
        local dropped = table.remove(activeInstances, 1)
        dropped.finished, dropped.onComplete = true, nil
        print("[SpineCardEffect] 达到上限 " .. MAX_ACTIVE .. "，取消最老记录 " .. dropped.kind
            .. " scope=" .. dropped.scope)
    end
    activeInstances[#activeInstances + 1] = {
        kind = kind, scope = scope, cx = cx, cy = cy, width = w, height = h,
        startedAt = now, duration = DURATION[kind], onComplete = onComplete, finished = false,
    }
    print("[SpineCardEffect] 播放 " .. kind .. " scope=" .. scope .. " 中心=" .. cx .. "," .. cy)
end

--- 追加可选 scope 与尺寸；旧调用默认使用真实 BattleLayout 卡框尺寸。
---@param cx number
---@param cy number
---@param onComplete? function
---@param scope? string|number|DarkCardSize
---@param width? number|DarkCardSize
---@param height? number
function SpineCardEffect.playLevelUp(cx, cy, onComplete, scope, width, height)
    play("level", cx, cy, onComplete, scope, width, height, "battle")
end

---@param cx number
---@param cy number
---@param onComplete? function
---@param scope? string|number|DarkCardSize
---@param width? number|DarkCardSize
---@param height? number
function SpineCardEffect.playJobChange(cx, cy, onComplete, scope, width, height)
    play("job", cx, cy, onComplete, scope, width, height, "church")
end

---@param cx number
---@param cy number
---@param onComplete? function
---@param scope? string|number|DarkCardSize
---@param width? number|DarkCardSize
---@param height? number
function SpineCardEffect.playRevive(cx, cy, onComplete, scope, width, height)
    play("revive", cx, cy, onComplete, scope, width, height, "battle")
end

--- 宿主须在提前 return 前调用；非法 dt 安全忽略，绝不作为时钟累加。
---@param dt? number
function SpineCardEffect.update(dt)
    expire(clock())
end

---@param scope? string
---@return boolean
function SpineCardEffect.isPlaying(scope)
    expire(clock())
    for _, entry in ipairs(activeInstances) do
        if not scope or entry.scope == scope then return true end
    end
    return false
end

---@param vg any
---@param scope string
---@param alpha? number
function SpineCardEffect.draw(vg, scope, alpha)
    local now = clock()
    expire(now)
    if disabled or not vg or not now then return end
    local opacity = alpha == nil and 1.0 or (finite(alpha) and math.max(0.0, math.min(1.0, alpha or 0.0)) or 0.0)
    if opacity <= 0 then return end
    local batch = {} ---@type DarkCardPlayback[]
    for _, entry in ipairs(activeInstances) do
        if entry.scope == scope then batch[#batch + 1] = entry end
    end
    for _, entry in ipairs(batch) do
        if not entry.finished then
            local saved = false
            local ok, err = pcall(function()
                local primitives = require("ui.fx.DarkEffectPrimitives")
                nvgSave(vg)
                saved = true
                primitives.drawCard(vg, entry.kind, entry.cx, entry.cy, entry.width, entry.height,
                    math.max(0, now - entry.startedAt), entry.duration, opacity)
            end)
            if saved then
                local restored, restoreErr = pcall(nvgRestore, vg)
                if not restored then ok, err = false, restoreErr end
            end
            if not ok then
                -- 视觉单次降级，禁止逐帧重试；计时与业务完成回调继续。
                disabled = true
                print("[SpineCardEffect] 视觉已停用，计时继续: " .. tostring(err))
                return
            end
        end
    end
end

---@param vg? any
function SpineCardEffect.preload(vg) end -- 幂等空操作：不分配原生对象或缓存资源。

---@param scope? string 省略则取消全部；取消不执行完成回调。
function SpineCardEffect.stopAll(scope)
    if scope then
        scopeEpochs[scope] = (scopeEpochs[scope] or 0) + 1
    else
        cancelEpoch = cancelEpoch + 1
        scopeEpochs = {}
    end
    for i = #activeInstances, 1, -1 do
        local entry = activeInstances[i]
        if not scope or entry.scope == scope then
            entry.finished, entry.onComplete = true, nil
            table.remove(activeInstances, i)
        end
    end
end

function SpineCardEffect.destroy()
    SpineCardEffect.stopAll()
    disabled = false -- 显式销毁是视觉失败后唯一允许重试的生命周期边界。
end

return SpineCardEffect
