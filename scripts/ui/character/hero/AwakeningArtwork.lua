-- 满觉醒影画全窗浏览：复用宿主帧与新 UI 文本，不裁切源图、不发送业务动作。
local Artwork = {}
local generation = 0
local touches = {} ---@type table<number, boolean>
---@type table?
local state = nil
---@type table?
local press = nil
---@type Panel?
local chrome = nil
---@type Label?
local title = nil
---@type Label?
local hint = nil

function Artwork.close()
    if state then print("[AwakeningArtwork] 关闭全图 hero=" .. state.heroId) end
    state = nil
    generation = generation + 1
end

function Artwork.destroy()
    Artwork.close()
    press = nil
    touches = {}
    if chrome then chrome:Destroy() end
    chrome, title, hint = nil, nil, nil
end

function Artwork.isOpen()
    if state and state.validate and not state.validate() then Artwork.close() end
    return state ~= nil
end

function Artwork.open(heroId, image, imageWidth, imageHeight, validate)
    if not image or image < 0 or imageWidth <= 0 or imageHeight <= 0 or not validate() then return false end
    Artwork.close()
    if press then press.cancelled = true end
    state = { heroId = heroId, image = image, imageWidth = imageWidth, imageHeight = imageHeight,
        validate = validate, openedAt = time.elapsedTime }
    print("[AwakeningArtwork] 查看完整影画 hero=" .. heroId)
    return true
end

-- 关闭/换角色/覆盖/窗口变化均永久取消旧按压，取消后的松手也不能穿透到下层。
local function frameKey(runtime)
    return table.concat({ runtime.logicalW or 0, runtime.logicalH or 0, runtime.dpr or 1,
        runtime.frameScale or 1, runtime.frameOx or 0, runtime.frameOy or 0 }, ":")
end

function Artwork.observe(runtime, blocked)
    if press and (not Artwork.isOpen() or press.generation ~= generation
        or press.frame ~= frameKey(runtime) or blocked) then press.cancelled = true end
end

function Artwork.hasPress() return press ~= nil end

-- 副指也属于开始时的全图模态；主图关闭或被覆盖后不能把副指松手转成新点击。
function Artwork.captureTouch(id) touches[id] = true end
function Artwork.hasTouch(id) return touches[id] == true end
function Artwork.releaseTouch(id)
    local captured = touches[id] == true
    touches[id] = nil
    return captured
end

function Artwork.handleDown(x, y, button, source, runtime)
    if not Artwork.isOpen() and not press then return false end
    if press then return true end
    if button == MOUSEB_LEFT and Artwork.isOpen() then
        press = { x = x, y = y, source = source, frame = frameKey(runtime), generation = generation }
    end
    return true
end

function Artwork.handleMove(x, y, source, runtime)
    if not Artwork.isOpen() and not press then return false end
    Artwork.observe(runtime, false)
    if press and press.source == source and math.abs(x - press.x) + math.abs(y - press.y) >= 15 then
        press.cancelled = true
    end
    return true
end

function Artwork.handleUp(x, y, button, source, runtime)
    if not Artwork.isOpen() and not press then return false end
    if button ~= MOUSEB_LEFT or (press and press.source ~= source) then return true end
    Artwork.observe(runtime, false)
    local tap = press and not press.cancelled and Artwork.isOpen()
        and math.abs(x - press.x) + math.abs(y - press.y) < 15
    press = nil
    if tap then Artwork.close() end
    return true
end

function Artwork.cancelPress()
    if press then press.cancelled = true end
end

-- 指针路由与宿主坐标闭包绑定，保持横屏入口只负责原有输入优先级。
function Artwork.bindInput(ctx)
    return function(method, button)
        local blocked = ctx.blocked()
        Artwork.observe(ctx.runtime, blocked)
        if not Artwork.hasPress() and (blocked or not Artwork.isOpen()) then return false end
        ctx.cancelUnderlyingPress()
        local sx, sy = ctx.position()
        local source = ctx.source()
        if blocked then
            Artwork.cancelPress()
            if method == "up" then Artwork.handleUp(sx, sy, button, source, ctx.runtime) end
        elseif method == "down" then
            Artwork.handleDown(sx, sy, button, source, ctx.runtime)
        elseif method == "move" then
            Artwork.handleMove(sx, sy, source, ctx.runtime)
        else
            Artwork.handleUp(sx, sy, button, source, ctx.runtime)
        end
        return true
    end
end

local function ensureChrome()
    local Surface = require("ui.widget.DesignWidgetSurface")
    Surface.init()
    if chrome then return end
    local UI = require("urhox-libs/UI")
    title = UI.Label { text = "", fontFamily = "sans", fontWeight = "normal", fontSize = 24,
        textAlign = "center", height = 42, width = "100%", fontColor = { 244, 237, 224, 255 } }
    hint = UI.Label { text = "", fontFamily = "sans", fontWeight = "normal", fontSize = 15,
        textAlign = "center", height = 30, width = "100%", fontColor = { 196, 160, 90, 255 } }
    chrome = UI.Panel { width = 800, height = 78, gap = 4, pointerEvents = "none", children = { title, hint } }
end

-- 全图 contain：留出上下文字与安全边距，整个源图完整显示，不能用 cover。
function Artwork.getImageBounds(width, height)
    if not Artwork.isOpen() then return nil end
    local availableW, availableH = math.max(1, width - 64), math.max(1, height - 220)
    local fit = math.min(availableW / state.imageWidth, availableH / state.imageHeight)
    local w, h = state.imageWidth * fit, state.imageHeight * fit
    return { x = (width - w) * 0.5, y = (height - h) * 0.5, w = w, h = h }
end

function Artwork.draw(vg, width, height)
    if not Artwork.isOpen() or width <= 0 or height <= 0 then return end
    local bounds = Artwork.getImageBounds(width, height)
    if not bounds then return end
    nvgSave(vg)
    nvgResetScissor(vg)
    nvgScissor(vg, 0, 0, width, height)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(5, 7, 12, 246))
    nvgFill(vg)
    local elapsed = math.max(0, time.elapsedTime - state.openedAt)
    local t = math.min(1, elapsed / 0.22)
    nvgGlobalAlpha(vg, 0.35 + 0.65 * (1 - (1 - t) ^ 3))
    require("core.DrawUtil").drawImageCentered(vg, state.image,
        bounds.x + bounds.w * 0.5, bounds.y + bounds.h * 0.5, bounds.w, bounds.h, 1)
    nvgGlobalAlpha(vg, 1)
    ensureChrome()
    local cfg = require("config.HeroConfig").get(state.heroId)
    local I18n = require("core.I18n")
    title:SetText(I18n.lookup(cfg and cfg.name or "") .. " · " .. I18n.lookup("觉醒"))
    hint:SetText(I18n.lookup("点击关闭") .. " / Esc")
    local scale = math.min(1, math.max(0.1, (width - 32) / 800))
    nvgTranslate(vg, (width - 800 * scale) * 0.5, 16)
    nvgScale(vg, scale, scale)
    require("ui.widget.DesignWidgetSurface").draw(chrome, vg, 800, 78)
    nvgRestore(vg)
end

return Artwork
