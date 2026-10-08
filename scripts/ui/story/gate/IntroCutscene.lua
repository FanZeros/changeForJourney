-- ============================================================================
-- IntroCutscene.lua — 终焉通关后的远征过场（5 段时间轴）
-- 沿用宿主的全屏绘制与完成回调，不重播新手开场，不改首通/奖励/关卡进度。
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local GameConfig = require("config.GameConfig")
local Story = require("core.I18nStory")
local Display = require("ui.story.StoryDisplay")

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

local function drawBlack(alpha)
    if alpha <= 0.01 then return end
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, DW, DH)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, math.floor(alpha * 255)))
    nvgFill(vg_)
end

local function drawBackground(image, alpha, zoom)
    if image < 0 or alpha <= 0.01 then return end
    local width, height = nvgImageSize(vg_, image)
    if width <= 0 or height <= 0 then return end
    local scale = math.max(DW / width, DH / height) * zoom
    DrawUtil.drawImageCentered(vg_, image, DW * 0.5, DH * 0.5,
        width * scale, height * scale, alpha)
end

local function drawCaption()
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
    local font, rows = Display.fitLayout(vg_, text, DW * 0.88, 176, 58, 24, 1.25)
    -- 长英文不能靠三行小字挤入高度；横屏中部固定最多两行，完整译文按宽度缩字。
    while #rows > 2 and font > 24 do
        font = font - 1
        rows = Display.layoutText(vg_, text, DW * 0.88, font)
    end
    nvgFontSize(vg_, font)
    nvgFillColor(vg_, nvgRGBA(255, 255, 255, math.floor(alpha * 255)))
    Display.drawRows(vg_, DW * 0.5, DH * 0.5 - #rows * font * 1.25 * 0.5,
        rows, Story.length(visible), font * 1.25)
end

local function ensureImages()
    if not vg_ then return end
    if imgTemple < 0 then
        imgTemple = nvgCreateImage(vg_, "image/关卡地图/MAP_999.png", 0)
    end
    if imgRoad < 0 then
        imgRoad = nvgCreateImage(vg_, "image/暗黑/L1_row1_forest.png", 0)
    end
end

local function finish()
    active = false
    finished = true
    local callback = onFinishCb
    onFinishCb = nil
    print("[IntroCutscene] 终焉远征过场结束")
    if callback then callback() end
end

---@param vg any NanoVG context
---@param _sceneRef Scene|nil 兼容宿主初始化接口；新过场不播放旧濒死音效
function IntroCutscene.init(vg, _sceneRef)
    if vg_ ~= vg then
        imgTemple, imgRoad = -1, -1
    end
    vg_ = vg
end

---@param onFinish function|nil 保留终焉 token 及三队统一进场的宿主闭包
function IntroCutscene.start(onFinish)
    ensureImages()
    active = true
    finished = false
    phase, phaseT = 1, 0
    onFinishCb = onFinish
    print("[IntroCutscene] 开始终焉远征过场")
end

function IntroCutscene.isActive() return active end
function IntroCutscene.isFinished() return finished end

function IntroCutscene.update(dt)
    if not active then return end
    phaseT = phaseT + math.max(0, dt)
    if phaseT >= PHASE_DURATIONS[phase] then
        phase = phase + 1
        phaseT = 0
        if phase > #PHASE_DURATIONS then finish() end
    end
end

-- 宿主已应用设计空间变换；此处不另开 NanoVG frame，不改变输入坐标。
function IntroCutscene.draw(_vg)
    if not active then return end
    nvgSave(vg_)
    nvgScissor(vg_, 0, 0, DW, DH)
    drawBlack(1)
    local progress = easeInOut(phaseT / PHASE_DURATIONS[phase])
    if phase == 2 then
        drawBackground(imgTemple, progress, 1 + progress * 0.04)
        drawBlack(0.35)
    elseif phase == 3 then
        -- 道路覆盖不透明神殿，避免两层同时淡出造成中途亮度下陷。
        drawBackground(imgTemple, 1, 1.04)
        drawBackground(imgRoad, progress, 1.04 - progress * 0.04)
        drawBlack(0.35)
    elseif phase == 4 then
        drawBackground(imgRoad, 1, 1 + progress * 0.02)
        drawBlack(0.35)
    elseif phase == 5 then
        drawBackground(imgRoad, 1 - progress, 1.02)
        drawBlack(0.35)
    end
    drawCaption()
    nvgResetScissor(vg_)
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
    onFinishCb = nil
    print("[IntroCutscene] 终焉远征过场已重置")
end

return IntroCutscene
