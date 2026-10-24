-- ============================================================================
-- IntroCutscene.lua — 终焉通关后的远征过场（5 段时间轴）
-- 沿用宿主的全屏绘制与完成回调，不重播新手开场，不改首通/奖励/关卡进度。
-- ============================================================================

local GameConfig = require("config.GameConfig")
local Story = require("core.I18nStory")
local Display = require("ui.story.StoryDisplay")
local Motion = require("ui.story.StoryCinematicMotion")
local presentationElapsed_ = 0

local IntroCutscene = {}
local DW = GameConfig.Design.WIDTH
local DH = GameConfig.Design.HEIGHT
local PHASE_DURATIONS = { 1.5, 4.0, 7.5, 4.0, 3.5 }
local TYPEWRITER_CPS = 10

local active = false
local finished = false
local phase = 0
local phaseT = 0
---@type any
local vg_ = nil
local imgTemple = -1
local imgRoad = -1
---@type function|nil
local onFinishCb = nil

local function easeInOut(t)
    t = math.max(0, math.min(1, t))
    return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2)^2 / 2
end

local function drawBlack(alpha, w, h)
    if alpha <= 0.01 then return end
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, w, h)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, math.floor(alpha * 255)))
    nvgFill(vg_)
end

local function drawBackground(image, alpha, elapsed, w, h)
    Motion.drawImage(vg_, image, elapsed, w, h, alpha)
end

local function drawCaption(w, h, scale)
    local source = Story.INTRO[phase]
    local elapsed = phaseT - 0.2
    if not source or elapsed <= 0 then return end
    local text = Display.text(source)
    local available = PHASE_DURATIONS[phase] - 0.2
    local visible, count, _, duration = Story.typed(text, elapsed, TYPEWRITER_CPS, available)
    if count == 0 or elapsed >= duration then return end
    local fade = math.min(0.5, duration * 0.3)
    local alpha = math.min(1, elapsed / 0.15)
    if elapsed > duration - fade then
        alpha = alpha * (1 - easeInOut((elapsed - duration + fade) / fade))
    end
    nvgFontFace(vg_, "sans")
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local minFont = 24 * scale
    local font, rows = Display.fitLayout(vg_, text, w * 0.88, 176 * scale, 58 * scale, minFont, 1.25)
    -- 字幕单独按窗口缩放，不跟随旧竖屏 cover 放大，完整译文最多两行。
    while #rows > 2 and font > minFont do
        font = math.max(minFont, font - scale)
        rows = Display.layoutText(vg_, text, w * 0.88, font)
    end
    nvgFontSize(vg_, font)
    nvgFillColor(vg_, nvgRGBA(255, 255, 255, math.floor(alpha * 255)))
    Display.drawRows(vg_, w * 0.5, h * 0.5 - #rows * font * 1.25 * 0.5,
        rows, Story.length(visible), font * 1.25)
end

local function ensureImages()
    if not vg_ then return end
    if imgTemple < 0 then
        imgTemple = nvgCreateImage(vg_, "image/剧情/背景/STORY_TERMINAL_TEMPLE.png", 0) or -1
    end
    if imgRoad < 0 then
        imgRoad = nvgCreateImage(vg_, "image/剧情/背景/STORY_TERMINAL_ROAD.png", 0) or -1
    end
end

local function finish()
    active = false
    finished = true
    local callback = onFinishCb
    onFinishCb = nil
    presentationElapsed_ = 0 -- 回调可能同步开启下一过场，先清旧视觉
    print("[IntroCutscene] 终焉远征过场结束")
    if callback then callback() end
end

---@param vg any NanoVG context
---@param _sceneRef Scene|nil 兼容宿主初始化接口；新过场不播放旧濒死音效
function IntroCutscene.init(vg, _sceneRef)
    if vg_ ~= vg then
        imgTemple, imgRoad = -1, -1
        presentationElapsed_ = 0
    end
    vg_ = vg
end

---@param onFinish function|nil 保留终焉 token 及三队统一进场的宿主闭包
function IntroCutscene.start(onFinish)
    ensureImages()
    active = true
    finished = false
    phase, phaseT = 1, 0
    presentationElapsed_ = 0
    onFinishCb = onFinish
    print("[IntroCutscene] 开始终焉远征过场")
end

function IntroCutscene.isActive() return active end
function IntroCutscene.isFinished() return finished end

function IntroCutscene.update(dt)
    if not active then return end
    presentationElapsed_ = presentationElapsed_ + math.max(0, dt)
    phaseT = phaseT + math.max(0, dt)
    if phaseT >= PHASE_DURATIONS[phase] then
        phase = phase + 1
        phaseT = 0
        if phase > #PHASE_DURATIONS then finish() end
    end
end

-- 宿主传入逻辑窗口尺寸；只对背景做等比 cover，不二次放大竖屏画布。
---@param _vg any
---@param width number?
---@param height number?
function IntroCutscene.draw(_vg, width, height)
    if not active then return end
    local w, h = width or DW, height or DH
    if w <= 0 or h <= 0 then return end
    local scale = width and math.min(w / 1920, h / 1080) or 1
    nvgSave(vg_)
    nvgIntersectScissor(vg_, 0, 0, w, h)
    drawBlack(1, w, h)
    local progress = easeInOut(phaseT / PHASE_DURATIONS[phase])
    local templeElapsed = math.max(0, presentationElapsed_ - PHASE_DURATIONS[1])
    local roadElapsed = math.max(0, templeElapsed - PHASE_DURATIONS[2])
    if phase == 2 then
        drawBackground(imgTemple, progress, templeElapsed, w, h)
        drawBlack(0.35, w, h)
    elseif phase == 3 then
        -- 道路覆盖不透明神殿，避免两层同时淡出造成中途亮度下陷。
        drawBackground(imgTemple, 1, templeElapsed, w, h)
        drawBackground(imgRoad, progress, roadElapsed, w, h)
        drawBlack(0.35, w, h)
    elseif phase == 4 then
        drawBackground(imgRoad, 1, roadElapsed, w, h)
        drawBlack(0.35, w, h)
    elseif phase == 5 then
        drawBackground(imgRoad, 1 - progress, roadElapsed, w, h)
        drawBlack(0.35, w, h)
    end
    local environmentAlpha = phase == 2 and progress or (phase == 5 and 1 - progress or 1)
    if phase >= 2 and (imgTemple >= 0 or imgRoad >= 0) then
        Motion.atmosphere(vg_, presentationElapsed_, w, h, environmentAlpha, "cool")
    end
    drawCaption(w, h, scale)
    nvgRestore(vg_)
end

function IntroCutscene.skip()
    if not active then return end
    finish()
end

-- 清档/读档时丢弃回调，不执行旧 token 所属的关卡推进。
function IntroCutscene.reset()
    active, finished = false, false
    phase, phaseT = 0, 0
    presentationElapsed_ = 0
    onFinishCb = nil
    print("[IntroCutscene] 终焉远征过场已重置")
end

return IntroCutscene
