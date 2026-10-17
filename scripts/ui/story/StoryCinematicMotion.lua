-- 纯视觉模块：无事件、回调、图片加载、随机数或存档读写。
-- NanoVG frame/DPR 归宿主持有；经过时间只由 update 推进。
local DrawUtil = require("core.DrawUtil")
local Motion = {}
local DISSOLVE = 0.32

---@class StoryMotionLayer
---@field identity string
---@field image number
---@field elapsed number
---@field theme string
---@class StoryMotionState
---@field current StoryMotionLayer?
---@field previous StoryMotionLayer?
---@field transition number

---@return StoryMotionState
function Motion.new()
    return { transition = DISSOLVE }
end

---@param state StoryMotionState
function Motion.reset(state)
    state.current, state.previous = nil, nil
    state.transition = DISSOLVE
end

-- 明确场景而非说话人/语言/标题决定色调：书斋、门厅、酒馆与铁匠铺用暖铜；
-- 林道和未知环境保持克制的灰蓝，不添加无来由的火星。
---@param path string?
---@return string
function Motion.theme(path)
    if path == "image/剧情/背景/STORY_BG_01.png"
        or path == "image/剧情/背景/STORY_BG_02.png"
        or path == "image/剧情/背景/STORY_BG_07.png"
        or path == "image/剧情/背景/STORY_BG_09.png"
        or path == "image/剧情/开场三人CG.png" then return "warm" end
    return "cool"
end

---@param state StoryMotionState
---@param identity string?
---@param image number
---@param theme string?
function Motion.present(state, identity, image, theme)
    local key = identity or ""
    local current = state.current
    if current and current.identity == key and current.image == image then return end
    -- 快速连换不累积合成层，最多只保留旧/新两幅图。
    state.previous = current and current.image >= 0 and image >= 0
        and current.identity ~= key and current or nil
    state.current = { identity = key, image = image, elapsed = 0,
        theme = theme or Motion.theme(identity) }
    state.transition = state.previous and 0 or DISSOLVE
end

---@param state StoryMotionState
---@param dt number
function Motion.update(state, dt)
    local elapsed = math.max(0, dt)
    if state.current then state.current.elapsed = state.current.elapsed + elapsed end
    if state.previous then
        state.previous.elapsed = state.previous.elapsed + elapsed
        state.transition = math.min(DISSOLVE, state.transition + elapsed)
        if state.transition >= DISSOLVE then state.previous = nil end
    end
end

-- cover 目标区域最大 3% 超扫，平移始终落在超扫余量中。
-- 仅环境图做缓推镜；字幕、立绘和输入锚点不参与变换。
---@param elapsed number
---@param w number
---@param h number
---@return number cx
---@return number cy
---@return number width
---@return number height
function Motion.cover(elapsed, w, h)
    local t = math.max(0, elapsed)
    local zoom = 1.006 + 0.024 * (1 - math.exp(-t / 24))
    return w * (0.5 + 0.0018 * math.sin(t * 0.065)),
        h * (0.5 - 0.0012 * math.sin(t * 0.045)), w * zoom, h * zoom
end

---@param vg NVGContextWrapper?
---@param image number
---@param elapsed number
---@param w number
---@param h number
---@param alpha number
function Motion.drawImage(vg, image, elapsed, w, h, alpha)
    if not vg or image < 0 or alpha <= 0.01 or w <= 0 or h <= 0 then return end
    local cx, cy, width, height = Motion.cover(elapsed, w, h)
    nvgSave(vg)
    nvgIntersectScissor(vg, 0, 0, w, h)
    DrawUtil.drawImageCover(vg, image, cx, cy, width, height, alpha)
    nvgRestore(vg)
end

---@param state StoryMotionState
---@param vg NVGContextWrapper?
---@param w number
---@param h number
---@param alpha number
function Motion.draw(state, vg, w, h, alpha)
    local current, previous = state.current, state.previous
    if not current then return end
    if previous then
        Motion.drawImage(vg, previous.image, previous.elapsed, w, h, alpha)
    end
    local progress = math.min(1, state.transition / DISSOLVE)
    local blend = progress * progress * (3 - 2 * progress)
    Motion.drawImage(vg, current.image, current.elapsed, w, h, alpha * blend)
end

local function gradient(vg, w, h, paint)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

-- 克制的环境光在原对话框/信笺之下，不重复叠加人物。
---@param vg NVGContextWrapper?
---@param elapsed number
---@param w number
---@param h number
---@param alpha number
---@param theme string
---@param desk boolean?
function Motion.atmosphere(vg, elapsed, w, h, alpha, theme, desk)
    if not vg or alpha <= 0.01 or w <= 0 or h <= 0 then return end
    local warm = theme == "warm"
    local r, g, b = warm and 198 or 108, warm and 141 or 137, warm and 83 or 163
    local breath = 0.82 + 0.18 * math.sin(elapsed * 0.48)
    nvgSave(vg)
    nvgIntersectScissor(vg, 0, 0, w, h)
    gradient(vg, w, h, nvgRadialGradient(vg, w * 0.76, h * 0.28,
        0, w * 0.58, nvgRGBA(r, g, b, math.floor((desk and 23 or 14) * breath * alpha)),
        nvgRGBA(r, g, b, 0)))
    gradient(vg, w, h, nvgLinearGradient(vg, 0, h * 0.38, 0, h,
        nvgRGBA(3, 5, 9, 0), nvgRGBA(3, 5, 9, math.floor(112 * alpha))))
    gradient(vg, w, h, nvgRadialGradient(vg, w * 0.5, h * 0.40,
        h * 0.25, w * 0.66, nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, math.floor(48 * alpha))))
    if desk then
        -- 六颗固定相位微尘，只出现在书案右侧露出的区域。
        -- 解析轨迹在 reset 后可复现，不调用玩法随机数。
        for i = 1, 6 do
            local cycle = (elapsed * (0.009 + i * 0.0007) + i * 0.137) % 1
            local x = w * (0.78 + 0.17 * ((i * 0.271) % 1)
                + 0.005 * math.sin(elapsed * 0.16 + i))
            local y = h * (0.16 + 0.46 * cycle)
            local a = math.sin(cycle * math.pi) ^ 2 * 30 * alpha
            nvgBeginPath(vg)
            nvgCircle(vg, x, y, math.max(0.6, h * (0.0007 + i * 0.00006)))
            nvgFillColor(vg, nvgRGBA(203, 184, 146, math.floor(a)))
            nvgFill(vg)
        end
    end
    nvgRestore(vg)
end

return Motion
