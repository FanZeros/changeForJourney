-- 离线收益全窗覆盖：所有横屏模式共用绘制与输入逆变换。
local Overlay = {}

---@param panel table
---@param runtime table
---@return table
function Overlay.bind(panel, runtime)
    local pressed = false
    local startX, startY = 0, 0
    local pressWidth, pressHeight = 0, 0
    local pressScale, pressOx, pressOy, pressDpr = 1, 0, 0, 1
    local moved = false
    local lastTapTime = 0
    local api = {}

    local function layout()
        local width, height = runtime.logicalW or 0, runtime.logicalH or 0
        local fit = math.min(width / 1080, height / 2400)
        if fit <= 0 then fit = 1 end
        return (width - 1080 * fit) * 0.5, (height - 2400 * fit) * 0.5, fit, width, height
    end

    --- 输入为已去除 DPR 与全帧缩放的逻辑坐标。
    function api.toDesign(x, y)
        local ox, oy, fit = layout()
        return (x - ox) / fit, (y - oy) / fit
    end

    function api.draw()
        if not panel.isOpen() or not runtime.vg then return end
        local ox, oy, fit, width, height = layout()
        local vg = runtime.vg
        nvgSave(vg)
        nvgResetScissor(vg)
        nvgScissor(vg, 0, 0, width, height)
        nvgTranslate(vg, ox, oy)
        nvgScale(vg, fit, fit)
        panel.draw(vg)
        nvgRestore(vg)
    end

    function api.handleDown(x, y, button)
        if not panel.isOpen() then return false end
        if button == MOUSEB_LEFT then
            startX, startY = api.toDesign(x, y)
            pressWidth, pressHeight = runtime.logicalW, runtime.logicalH
            pressScale, pressOx, pressOy, pressDpr = runtime.frameScale or 1,
                runtime.frameOx or 0, runtime.frameOy or 0, runtime.dpr or 1
            pressed, moved = true, false
            panel.handleDragBegin(startX, startY)
        end
        return true
    end

    function api.handleMove(x, y)
        if not panel.isOpen() then return false end
        if pressed then
            local dx, dy = api.toDesign(x, y)
            if math.abs(dx - startX) + math.abs(dy - startY) >= 15 then moved = true end
            panel.handleDragMove(dx, dy)
        end
        return true
    end

    function api.handleUp(x, y, button)
        if not panel.isOpen() then
            pressed = false
            return false
        end
        if button == MOUSEB_LEFT then
            local dx, dy = api.toDesign(x, y)
            local isTap = pressed and not moved
                and runtime.logicalW == pressWidth and runtime.logicalH == pressHeight
                and (runtime.frameScale or 1) == pressScale and (runtime.frameOx or 0) == pressOx
                and (runtime.frameOy or 0) == pressOy and (runtime.dpr or 1) == pressDpr
                and math.abs(dx - startX) + math.abs(dy - startY) < 15
            pressed = false
            panel.handleDragEnd(dx, dy)
            local now = time.elapsedTime
            if isTap and now - lastTapTime >= 0.12 then
                lastTapTime = now
                panel.handleInput(dx, dy)
            end
        end
        return true
    end

    function api.hasPress()
        return pressed
    end

    function api.cancel()
        pressed, moved = false, false
        panel.handleDragEnd(-1, -1)
    end

    function api.handleWheel(wheel)
        if not panel.isOpen() then return false end
        panel.handleScroll(wheel)
        return true
    end

    return api
end

return Overlay
