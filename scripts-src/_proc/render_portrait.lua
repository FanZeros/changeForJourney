-- 离线渲染:单张角色立绘高清导出(配合截图参数使用)
-- PORT_ID 通过 sed 替换,画布 1024x2048,品红背景便于 trim
local PORT_ID = 21

local nvg = nil
local img = -1
local imgW, imgH = 0, 0

function Start()
    nvg = nvgCreate(1)
    if nvg == nil then
        print("[portrait] ERROR: nvgCreate failed")
        return
    end
    local path = string.format("image/角色立绘/UI_DLH_%d.png", PORT_ID)
    img = nvgCreateImage(nvg, path, 0)
    if img and img >= 0 then
        imgW, imgH = nvgImageSize(nvg, img)
        print(string.format("[portrait] %d %s size=%dx%d", PORT_ID, path, imgW, imgH))
    else
        print("[portrait] ERROR: load failed " .. path)
    end
    SubscribeToEvent(nvg, "NanoVGRender", "HandleRender")
end

---@param eventType string
---@param eventData any
function HandleRender(eventType, eventData)
    local graphics = GetGraphics()
    if not graphics then return end
    local width = graphics:GetWidth()
    local height = graphics:GetHeight()

    nvgBeginFrame(nvg, width, height, 1.0)

    -- 品红纯色背景(便于 convert trim)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, width, height)
    nvgFillColor(nvg, nvgRGBA(255, 0, 255, 255))
    nvgFill(nvg)

    if img and img >= 0 and imgW > 0 then
        -- fit 到画布内(保持比例)
        local scale = math.min(width / imgW, height / imgH)
        local dw, dh = imgW * scale, imgH * scale
        local ox = (width - dw) * 0.5
        local oy = (height - dh) * 0.5
        local paint = nvgImagePattern(nvg, ox, oy, dw, dh, 0, img, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, ox, oy, dw, dh)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)
    end

    nvgEndFrame(nvg)
end
