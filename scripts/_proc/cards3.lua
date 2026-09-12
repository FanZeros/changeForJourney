-- 渲染 3 张旧卡(从备份 KTX 读)用于色调采样
local CARDS = { 9, 11, 21 }
local nvg = nil
local imgs = {}

function Start()
    nvg = nvgCreate(1)
    if nvg == nil then
        print("[cards3] ERROR: nvgCreate failed")
        return
    end
    for i, id in ipairs(CARDS) do
        local p = "image/_backup_oldcards/KP_YX_" .. id .. ".png"
        imgs[i] = nvgCreateImage(nvg, p, 0)
        print("[cards3] " .. id .. " -> " .. tostring(imgs[i]))
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

    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, width, height)
    nvgFillColor(nvg, nvgRGBA(255, 0, 255, 255))
    nvgFill(nvg)

    for i, img in ipairs(imgs) do
        if img and img >= 0 then
            local iw, ih = nvgImageSize(nvg, img)
            if iw and iw > 0 then
                local ox = 10 + (i - 1) * 230
                local oy = 10
                local paint = nvgImagePattern(nvg, ox, oy, iw, ih, 0, img, 1.0)
                nvgBeginPath(nvg)
                nvgRect(nvg, ox, oy, iw, ih)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)
            end
        end
    end

    nvgEndFrame(nvg)
end
