-- 全窗奖励持有完整指针手势；旧按压、跨帧尺寸变化和副指松手不能触发新奖励操作。
local M = {}
function M.bind(deps)
    local popup, RT = deps.popup, deps.RT
    local press = nil ---@type table|nil
    local function snapshot()
        return table.concat({ deps.width(), deps.height(), deps.dpr(), RT.frameScale or 1,
            RT.frameOx or 0, RT.frameOy or 0, popup.getPresentationVersion() }, ":")
    end
    local function cancel()
        popup.cancelDrag()
        if press then press.cancelled = true end
    end
    local function active()
        return popup.isLarge() and not deps.blocked()
    end
    local function pointer(phase, button)
        if not active() then
            if press then
                cancel()
                if phase == "end" and button == MOUSEB_LEFT and press.source == deps.source() then press = nil end
                return not deps.blocked()
            end
            return false
        end
        deps.cancelUnderlyingPress()
        local x, y = deps.position()
        local source = deps.source()
        if phase == "begin" then
            if button ~= MOUSEB_LEFT or press and not press.cancelled and press.source ~= source then return true end
            press = { source = source, key = snapshot(), x = x, y = y, moved = false, cancelled = false }
            popup.handleLargePointer("begin", x, y, deps.width(), deps.height(), false)
        elseif phase == "move" then
            if not press or press.source ~= source then return true end
            if snapshot() ~= press.key then cancel(); return true end
            if math.abs(x - press.x) + math.abs(y - press.y) >= 15 then press.moved = true end
            if not press.cancelled then popup.handleLargePointer("move", x, y, deps.width(), deps.height(), false) end
        elseif phase == "end" then
            if button ~= MOUSEB_LEFT or not press or press.source ~= source then return true end
            local tap = not press.cancelled and not press.moved and snapshot() == press.key
                and math.abs(x - press.x) + math.abs(y - press.y) < 15
            press = nil
            popup.handleLargePointer("end", x, y, deps.width(), deps.height(), tap)
        end
        return true
    end
    local function observe()
        if press and (not active() or press.key ~= snapshot()) then cancel() end
    end
    return { pointer = pointer, observe = observe }
end
function M.bindHost(ctx, popup, cancelUnderlyingPress, pointerPosition)
    local panels = { "ui.dev.CEPanel", "ui.hud.popup.PlayerInfoPanel", "ui.hud.popup.OfflineRewardPanel",
        "ui.hud.popup.LevelUpPopup", "ui.hud.popup.UpdateNoticePopup", "ui.story.gate.DarkTitleScreenGate",
        "ui.story.gate.LetterIntro" }
    local blockers = {}
    for _, name in ipairs(panels) do blockers[#blockers + 1] = require(name) end
    local intro, story = require("ui.story.gate.IntroCutscene"), require("ui.story.ScenarioDialogue")
    return M.bind({ popup = popup, RT = ctx.RT, width = ctx.logicalW, height = ctx.logicalH,
        dpr = ctx.dpr, source = ctx.pointerSource, cancelUnderlyingPress = cancelUnderlyingPress,
        blocked = function()
            for _, panel in ipairs(blockers) do if panel.isOpen() then return true end end
            return intro.isActive() or story.isActive()
        end,
        position = function()
            local mp = pointerPosition()
            return ctx.toDesign(mp.x / ctx.dpr(), mp.y / ctx.dpr())
        end })
end
return M
