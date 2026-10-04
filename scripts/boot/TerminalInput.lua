-- 终焉确认独占点击；不让全窗确认中的按压启动下层装备/神器拖拽。
local Terminal = require("ui.battle.popup.TerminalConfirmDialog")
local Tri = require("ui.battle.tri.BattleTriPage")
local Battle = require("ui.battle.scene.BattleScene")
local M = {}

function M.bind(ctx)
    local press = nil ---@type table|nil
    local api = {}
    local function frame()
        local rt = ctx.RT
        return { ctx.logicalW(), ctx.logicalH(), ctx.dpr(), rt.frameScale or 1,
            rt.frameOx or 0, rt.frameOy or 0, Tri.isOpen() }
    end
    local function unchanged()
        if not press then return false end
        local current = frame()
        for i, value in ipairs(press.frame) do
            if current[i] ~= value then return false end
        end
        return true
    end
    function api.down(x, y, button)
        if not Terminal.isOpen() then press = nil return false end
        ctx.cancelUnderlyingPress()
        if button == MOUSEB_LEFT then
            press = { x = x, y = y, moved = false, frame = frame() }
        end
        return true
    end
    function api.move(x, y)
        if not Terminal.isOpen() and not press then return false end
        if press and (not Terminal.isOpen() or not unchanged()
            or math.abs(x - press.x) + math.abs(y - press.y) >= 15) then press.moved = true end
        return true
    end
    function api.up(x, y, button)
        if not Terminal.isOpen() and not press then return false end
        if button ~= MOUSEB_LEFT then return true end
        local tap = press and not press.moved and Terminal.isOpen() and unchanged()
            and math.abs(x - press.x) + math.abs(y - press.y) < 15
        press = nil
        ctx.cancelUnderlyingPress()
        if tap then
            if Tri.isOpen() then Tri.handleInput(x, y)
            else
                local dx, dy = ctx.playerInfoDesignCoords(x, y)
                Battle.handleInput(dx, dy)
            end
        end
        return true
    end
    return api
end

return M
