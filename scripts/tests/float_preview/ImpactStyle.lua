-- 独立飘字样片的表现模型，不接入 BattleCombat，不读取角色或存档。
local NumberUtil = require("core.NumberUtil")
local DamageTypeIcon = require("ui.battle.scene.DamageTypeIcon")
local M = {}

local PRESETS = {
    damage = { duration = 0.64, holdEnd = 0.43, size = 1.0, color = { 238, 229, 206 } },
    crit = { duration = 0.76, holdEnd = 0.51, size = 1.28, color = { 255, 210, 142 } },
    heal = { duration = 0.82, holdEnd = 0.56, size = 1.0, color = { 147, 227, 171 } },
    shield = { duration = 0.66, holdEnd = 0.44, size = 0.96, color = { 190, 210, 224 } },
}
local MAX_ENTRIES = 15
local MERGE_GAP = 0.16
local OUTLINE = { { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }
local SHARDS = { { -1, -0.6, 0.3 }, { 0.8, -0.9, -0.4 }, { 1, 0.35, 0.6 } }
M.PRESETS = PRESETS
M.MAX_ENTRIES = MAX_ENTRIES

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function ease(v)
    local t = clamp(v, 0, 1)
    return 1 - (1 - t) ^ 3
end
local function mix(a, b, t) return a + (b - a) * t end

---@param ft table
---@return table
function M.pose(ft)
    local preset = PRESETS[ft.style] or PRESETS.damage
    local age = clamp(ft.age or 0, 0, preset.duration)
    local enter = ease(age / 0.075)
    local settle = ease((age - 0.075) / 0.09)
    local out = clamp((age - preset.holdEnd) / (preset.duration - preset.holdEnd), 0, 1)
    local sx, sy = mix(0.78, 1.12, enter), mix(0.92, 1.05, enter)
    if age >= 0.075 then sx, sy = mix(1.12, 1, settle), mix(1.05, 1, settle) end
    if ft.style == "crit" then
        sx, sy = mix(0.76, 1.17, enter), mix(0.83, 1.1, enter)
        if age >= 0.075 then sx, sy = mix(1.17, 1, settle), mix(1.1, 1, settle) end
    elseif ft.style == "heal" then
        local grow = ease(age / 0.16)
        sx, sy = mix(0.86, 1, grow), mix(0.7, 1, grow)
    elseif ft.style == "shield" then
        sx, sy = mix(1.14, 0.9, enter), mix(0.72, 1.08, enter)
        if age >= 0.075 then sx, sy = mix(0.9, 1, settle), mix(1.08, 1, settle) end
    end
    local pulse = clamp((ft.pulse or 0) / 0.09, 0, 1)
    sx, sy = sx * (1 + 0.045 * pulse), sy * (1 + 0.045 * pulse)
    local side = ft.side or 1
    local x = side * 7 * (1 - settle)
    local y = -3 * settle
    local angle = ft.style == "crit" and side * -0.075 * (1 - settle) or 0
    if ft.style == "heal" then
        x, y = 0, -4 * ease(age / 0.16)
        sx, sy = sx * (1 - out * 0.12), sy * (1 - out * 0.45)
    elseif ft.style == "shield" then
        sx, sy = sx * (1 - out * 0.45), sy * (1 - out * 0.12)
    else
        x = x + side * out * out * 12
        sy = sy * (1 - out * 0.2)
    end
    return {
        sx = sx, sy = sy, x = x, y = y, angle = angle, out = out,
        alpha = out < 0.7 and 1 or clamp((1 - out) / 0.3, 0, 1),
        impact = clamp(1 - age / 0.18, 0, 1),
    }
end

function M.newState()
    return { entries = {}, pool = {}, index = {}, sequence = 0 }
end

---@param state table
---@param ft table
local function release(state, ft)
    local index = state.index[ft.target]
    if index and index[ft.key] == ft then
        index[ft.key] = nil
        if next(index) == nil then state.index[ft.target] = nil end
    end
    for key in pairs(ft) do ft[key] = nil end
    if #state.pool < MAX_ENTRIES then state.pool[#state.pool + 1] = ft end
end

---@param state table
---@param target table
---@param amount number
---@param x number
---@param y number
---@param meta? table
function M.add(state, target, amount, x, y, meta)
    if type(target) ~= "table" or type(amount) ~= "number" or amount <= 0
        or amount ~= amount or amount == math.huge then return nil end
    meta = meta or {}
    local visual = DamageTypeIcon.resolve(meta) or { channel = "damage", atkType = 1 }
    local style = visual.channel == "heal" and "heal" or visual.channel == "shield" and "shield"
        or visual.isCrit and "crit" or "damage"
    local key = table.concat({ visual.channel, tostring(visual.atkType),
        visual.isCrit and "crit" or "normal", visual.isDot and "dot" or "direct",
        visual.isBlocked and "block" or "full" }, ":")
    local index = state.index[target]
    local current = index and index[key]
    local preset = PRESETS[style]
    -- 收尾前关闭合并窗口，旧字不会在压缩擦除时继续吞进新数。
    local mergedAmount = current and current.amount + amount
    local integerOverflow = current and math.type(current.amount) == "integer" and math.type(amount) == "integer"
        and amount > math.maxinteger - current.amount
    if current and current.age <= preset.holdEnd - 0.1
        and current.age - current.lastMerge <= MERGE_GAP
        and not integerOverflow and mergedAmount > 0 and mergedAmount < math.huge then
        current.amount = mergedAmount
        current.text = (visual.channel == "heal" and "+" or "") .. NumberUtil.format(current.amount)
        current.lastMerge, current.pulse = current.age, 0.09
        current.measuredText = nil
        return current
    end
    if #state.entries >= MAX_ENTRIES then release(state, table.remove(state.entries, 1)) end
    state.sequence = state.sequence + 1
    local ft = table.remove(state.pool) or {}
    ft.target, ft.key, ft.style, ft.visual = target, key, style, visual
    ft.amount, ft.text = amount, (visual.channel == "heal" and "+" or "") .. NumberUtil.format(amount)
    ft.x, ft.y, ft.age, ft.lastMerge, ft.pulse = x, y, 0, 0, 0
    ft.side = state.sequence % 2 == 0 and 1 or -1
    ft.fontSize = meta.fontSize or 56
    local occupied = {}
    for _, active in ipairs(state.entries) do
        if active.target == target then occupied[active.slot] = true end
    end
    local slot = 1
    while occupied[slot] do slot = slot + 1 end
    -- 每目标最多三条视觉轨道，满轨时回收该目标最旧字，不让第四批重叠第三批。
    if slot > 3 then
        for i, active in ipairs(state.entries) do
            if active.target == target then
                slot = active.slot
                release(state, table.remove(state.entries, i))
                break
            end
        end
    end
    ft.slot = slot
    ft.offsetX = ft.slot == 2 and -12 or ft.slot == 3 and 12 or 0
    ft.offsetY = ft.slot == 2 and -76 or ft.slot == 3 and 76 or -4
    state.entries[#state.entries + 1] = ft
    index = state.index[target] or {}
    state.index[target], index[key] = index, ft
    return ft
end

---@param state table
---@param dt number
function M.update(state, dt)
    if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt == math.huge then return end
    for i = #state.entries, 1, -1 do
        local ft = state.entries[i]
        ft.age = ft.age + dt
        ft.pulse = math.max(0, ft.pulse - dt)
        if ft.age >= PRESETS[ft.style].duration then
            release(state, ft)
            table.remove(state.entries, i)
        end
    end
end

---@param state table
function M.reset(state)
    for _, ft in ipairs(state.entries) do release(state, ft) end
    state.entries, state.index, state.sequence = {}, {}, 0
end

local function color(vg, rgb, alpha)
    nvgFillColor(vg, nvgRGBA(rgb[1], rgb[2], rgb[3], math.floor(clamp(alpha, 0, 1) * 255)))
end
local function path(vg, points)
    nvgBeginPath(vg)
    nvgMoveTo(vg, points[1], points[2])
    for i = 3, #points, 2 do nvgLineTo(vg, points[i], points[i + 1]) end
end

---@param ft table
---@param pose table
local function decoration(vg, ft, pose, width, size)
    local half = math.max(size, width * 0.5)
    local impact = pose.impact
    if ft.style == "crit" then
        if impact > 0 then
            path(vg, { -half - 14, 9, -half * 0.45, -7, -8, 5, half * 0.4, -9, half + 14, 1 })
            nvgStrokeColor(vg, nvgRGBA(106, 31, 28, math.floor(impact * 210)))
            nvgStrokeWidth(vg, 7); nvgStroke(vg)
            nvgStrokeColor(vg, nvgRGBA(226, 99, 66, math.floor(impact * 150)))
            nvgStrokeWidth(vg, 2); nvgStroke(vg)
        end
        local burst = clamp((ft.age or 0) / 0.24, 0, 1)
        local strength = (1 - burst) * 0.7 + pose.out * (1 - pose.out)
        if strength > 0.01 then
            for _, shard in ipairs(SHARDS) do
                nvgSave(vg)
                local spread = 12 + burst * 30 + pose.out * 22
                nvgTranslate(vg, shard[1] * (half + spread), shard[2] * spread)
                nvgRotate(vg, shard[3] + burst)
                nvgBeginPath(vg); nvgMoveTo(vg, -4, -1); nvgLineTo(vg, 5, -3)
                nvgLineTo(vg, 1, 3); nvgClosePath(vg)
                color(vg, { 214, 159, 108 }, strength); nvgFill(vg)
                nvgRestore(vg)
            end
        end
    elseif ft.style == "heal" then
        local progress = ease((ft.age or 0) / 0.24)
        for i = 1, 3 do
            local angle = i * math.pi * 2 / 3 + 0.3
            local radius = size * (0.8 - progress * 0.35) * (1 - pose.out)
            nvgBeginPath(vg)
            nvgCircle(vg, math.cos(angle) * (half + radius * 0.3), math.sin(angle) * radius, 2.4)
            color(vg, { 155, 227, 169 }, (1 - progress) * 0.65 + pose.out * 0.2)
            nvgFill(vg)
        end
    elseif ft.style == "shield" then
        local a = impact * 0.65 + pose.out * 0.2
        if a > 0.01 then
            for _, side in ipairs({ -1, 1 }) do
                local x = side * (half + 12 - pose.out * 10)
                path(vg, { x - side * 8, -14, x, -9, x, 9, x - side * 8, 14 })
                nvgStrokeColor(vg, nvgRGBA(161, 196, 217, math.floor(a * 255)))
                nvgStrokeWidth(vg, 2); nvgStroke(vg)
            end
        end
    elseif impact > 0 then
        path(vg, { -half * 0.55, size * 0.37, half * 0.55, size * 0.37 })
        nvgStrokeColor(vg, nvgRGBA(140, 116, 79, math.floor(impact * 110)))
        nvgStrokeWidth(vg, 2); nvgStroke(vg)
    end
end

---@param ft table
local function measure(vg, ft, font)
    local size = ft.fontSize * PRESETS[ft.style].size
    if ft.measuredText ~= ft.text or ft.measuredFont ~= font or ft.measuredSize ~= size
        or ft.measuredContext ~= vg then
        nvgFontFace(vg, font); nvgFontSize(vg, size)
        ft.textWidth = nvgTextBounds(vg, 0, 0, ft.text) or size
        ft.measuredText, ft.measuredFont, ft.measuredSize, ft.measuredContext = ft.text, font, size, vg
    end
    local icon = ft.style == "heal" and 0 or size * 0.72
    return ft.textWidth + icon + (icon > 0 and 7 or 0), size, icon
end

---@param ft table
local function glyph(vg, ft, font, size, icon, width)
    nvgFontFace(vg, font); nvgFontSize(vg, size)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local textX = -width * 0.5 + icon + (icon > 0 and 7 or 0)
    nvgFillColor(vg, nvgRGBA(18, 15, 16, 255))
    for _, offset in ipairs(OUTLINE) do nvgText(vg, textX + offset[1], offset[2], ft.text) end
    local rgb = PRESETS[ft.style].color
    local light = nvgRGBA(255, 247, 223, 255)
    local base = nvgRGBA(rgb[1], rgb[2], rgb[3], 255)
    ---@cast light NVGcolor
    ---@cast base NVGcolor
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, -size * 0.35, 0, size * 0.4, light, base))
    nvgText(vg, textX, 0, ft.text)
    if icon > 0 then DamageTypeIcon.draw(vg, ft.visual, -width * 0.5 + icon * 0.5, 0, icon) end
end

---@param ft table
---@param bounds? table
function M.draw(vg, ft, font, bounds)
    if not PRESETS[ft.style] then return end
    local pose = M.pose(ft)
    if pose.alpha <= 0 then return end
    nvgSave(vg)
    local width, size, icon = measure(vg, ft, font)
    local x = ft.x + (ft.offsetX or 0) + pose.x
    local y = ft.y + (ft.offsetY or 0) + pose.y
    if bounds then
        local mx = math.min(bounds.w * 0.5, width * pose.sx * 0.5 + 48)
        local my = math.min(bounds.h * 0.5, math.max(size * pose.sy * 0.7, 34) + 6)
        x = clamp(x, bounds.x + mx, bounds.x + bounds.w - mx)
        y = clamp(y, bounds.y + my, bounds.y + bounds.h - my)
        nvgIntersectScissor(vg, bounds.x, bounds.y, bounds.w, bounds.h)
    end
    nvgTranslate(vg, x, y); nvgRotate(vg, pose.angle); nvgScale(vg, pose.sx, pose.sy)
    nvgGlobalAlpha(vg, pose.alpha)
    decoration(vg, ft, pose, width, size)
    if pose.out > 0 and (ft.style == "damage" or ft.style == "crit") then
        local bands = ft.style == "crit" and 3 or 1
        local height = size * 1.6
        for i = 1, bands do
            nvgSave(vg)
            local bandY = -height * 0.5 + (i - 1) * height / bands
            nvgIntersectScissor(vg, -width * 0.5 - 4, bandY, (width + 8) * (1 - pose.out), height / bands)
            nvgTranslate(vg, (i % 2 == 0 and -1 or 1) * pose.out * 7, 0)
            glyph(vg, ft, font, size, icon, width)
            nvgRestore(vg)
        end
    else
        glyph(vg, ft, font, size, icon, width)
    end
    nvgRestore(vg)
end

return M
