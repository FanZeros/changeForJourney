-- 右键框选按下捕获原仓库与坐标变换；取消后仍吞掉同一次松开，不能跨栏落点。
local MarqueeGesture = {}

function MarqueeGesture.bind(ctx)
    local panel, RT = ctx.panel, ctx.RT
    local press = nil ---@type table?
    local api = {}
    local function scale()
        return ctx.tri() and ctx.height() / 1080 * ctx.DS or H_s * ctx.DS
    end
    local function valid()
        local p = press
        if not p then return false end
        if ctx.blocked() or not panel.canMarquee() or not panel.isMarqueeActive()
            or p.w ~= ctx.width() or p.h ~= ctx.height() or p.dpr ~= ctx.dpr()
            or p.scale ~= (RT.frameScale or 1) or p.ox ~= (RT.frameOx or 0)
            or p.oy ~= (RT.frameOy or 0) or p.tri ~= ctx.tri()
            or p.cs ~= scale() or p.hs ~= H_s or p.hx ~= H_ox or p.hy ~= H_oy then
            p.cancelled = true
            panel.cancelMarquee()
        end
        return not p.cancelled
    end
    function api.hasPress() return press ~= nil end
    function api.cancel()
        if press then press.cancelled = true; panel.cancelMarquee() end
    end
    function api.observe() valid() end
    function api.begin(dx, dy, sx, sy)
        if press or ctx.source() ~= "mouse" or ctx.blocked() then return false end
        if not panel.handleMarqueeBegin(dx, dy) then return false end
        local cs = scale()
        press = { x = sx - dx * cs, y = sy - dy * cs, cs = cs,
            w = ctx.width(), h = ctx.height(), dpr = ctx.dpr(), tri = ctx.tri(),
            scale = RT.frameScale or 1, ox = RT.frameOx or 0, oy = RT.frameOy or 0,
            hs = H_s, hx = H_ox, hy = H_oy, cancelled = false }
        return true
    end
    function api.move(sx, sy)
        if not press then return false end
        if ctx.source() ~= "mouse" then api.cancel(); return true end
        if valid() then panel.handleMarqueeMove((sx - press.x) / press.cs, (sy - press.y) / press.cs) end
        return true
    end
    function api.up(sx, sy)
        if not press then return false end
        if ctx.source() == "mouse" and valid() then
            panel.handleMarqueeEnd((sx - press.x) / press.cs, (sy - press.y) / press.cs)
        else
            panel.cancelMarquee()
        end
        press = nil
        return true
    end
    return api
end

return MarqueeGesture
