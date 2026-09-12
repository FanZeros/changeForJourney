-- 渲染 20 张卡面参考(从 KTX 读,引擎可靠解码)5列x4行,便于裁切
local IDS = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,20,21,22,23}
local nvg = nil
local imgs = {}

function Start()
    nvg = nvgCreate(1)
    if nvg == nil then
        print("[cardref] ERROR: nvgCreate failed")
        return
    end
    for i, id in ipairs(IDS) do
        local p = string.format("image/_tmp_old/KP_YX_%d.png", id)
        imgs[i] = nvgCreateImage(nvg, p, 0)
        print(string.format("[cardref] %d -> %s (v2)", id, tostring(imgs[i])))
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
                local col = (i - 1) % 5
                local row = math.floor((i - 1) / 5)
                local ox = 10 + col * 210
                local oy = 10 + row * 452
                local dw, dh = 198, 438
                local paint = nvgImagePattern(nvg, ox, oy, dw, dh, 0, img, 1.0)
                nvgBeginPath(nvg)
                nvgRect(nvg, ox, oy, dw, dh)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)
            end
        end
    end

    nvgEndFrame(nvg)
end
