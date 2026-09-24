-- ============================================================================
-- CEPanel - 横屏测试作弊面板
-- 左上角 CE 按钮，或按 F1 开关。只给单机测试用。
-- ============================================================================

local CEService = require("rules.gm.CEService")
local CERuntime = require("ui.CERuntime")

local CEPanel = {}

local open_ = false
local scroll_ = 0
local pressedId = nil
local captured_ = false
local resetArm_ = 0

local TOGGLE = { x = 16, y = 16, w = 88, h = 36 }
local PANEL = { x = 16, y = 60, w = 420, h = 560 }
local PAD = 12
local COLS = 2
local BTN_W = 190
local BTN_H = 36
local GAP = 8
local HEADER = 34

local buttons_ = {}

local function actions()
    return {
        { id = "pack", label = "一键测试包" },
        { id = "res", label = "全资源+100万" },
        { id = "heroes", label = "解锁全部英雄" },
        { id = "lv10", label = "全员等级+10" },
        { id = "awk", label = "全员觉醒+1" },
        { id = "plv", label = "远征等级到30" },
        { id = "stage10", label = "主线跳关+10" },
        { id = "preterm", label = "跳到终焉前" },
        { id = "stage305", label = "主线至少3-5" },
        { id = "kill", label = "秒杀当前战斗" },
        { id = "heal", label = "己方满血" },
        { id = "god", label = CERuntime.isGodMode() and "无敌：开" or "无敌：关" },
        { id = "speed", label = CERuntime.isSpeedOn() and "三倍速：开" or "三倍速：关" },
        { id = "guide", label = "跳过引导" },
        { id = "dungeon", label = "副本/塔层+5" },
        { id = "loot", label = "遗匣塞各品质" },
        { id = "talent", label = "点亮全部天赋" },
        { id = "relic", label = "遗物各1件" },
        { id = "reset", label = resetArm_ > 0 and "再点确认清档" or "重置存档" },
    }
end

local function hit(sx, sy, x, y, w, h)
    return sx >= x and sx <= x + w and sy >= y and sy <= y + h
end

local function contentHeight()
    local rows = math.ceil(#actions() / COLS)
    return HEADER + PAD + rows * (BTN_H + GAP)
end

local function panelH(screenH)
    local maxH = math.max(180, screenH - PANEL.y - 16)
    return math.min(PANEL.h, maxH)
end

local function layoutButtons(screenH)
    buttons_ = {}
    local list = actions()
    local h = panelH(screenH)
    local viewTop = PANEL.y + HEADER
    local viewH = h - HEADER - 8
    local originY = viewTop - scroll_
    for i, action in ipairs(list) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local x = PANEL.x + PAD + col * (BTN_W + GAP)
        local y = originY + row * (BTN_H + GAP)
        buttons_[#buttons_ + 1] = {
            id = action.id,
            label = action.label,
            x = x,
            y = y,
            w = BTN_W,
            h = BTN_H,
            visible = y + BTN_H >= viewTop and y <= viewTop + viewH,
        }
    end
end

local function clampScroll(screenH)
    local h = panelH(screenH)
    local viewH = h - HEADER - 8
    local maxScroll = math.max(0, contentHeight() - HEADER - viewH)
    if scroll_ < 0 then scroll_ = 0 end
    if scroll_ > maxScroll then scroll_ = maxScroll end
end

local function drawBtn(vg, x, y, w, h, text, hot)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 6)
    if hot then
        nvgFillColor(vg, nvgRGBA(176, 132, 48, 235))
    else
        nvgFillColor(vg, nvgRGBA(42, 36, 28, 230))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 6)
    nvgStrokeColor(vg, nvgRGBA(196, 164, 92, 220))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(245, 232, 200, 255))
    nvgText(vg, x + w * 0.5, y + h * 0.5, text, nil)
end

function CEPanel.isOpen()
    return open_
end

function CEPanel.toggle()
    open_ = not open_
    print("[CE] panel open=" .. tostring(open_))
end

function CEPanel.pollHotkey()
    if input:GetKeyPress(KEY_F1) then
        CEPanel.toggle()
    end
end

function CEPanel.draw(vg, screenW, screenH)
    if not vg or not open_ then return end
    if resetArm_ > 0 and os.clock() - resetArm_ > 3 then
        resetArm_ = 0
    end

    clampScroll(screenH)
    local h = panelH(screenH)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, PANEL.x, PANEL.y, PANEL.w, h, 10)
    nvgFillColor(vg, nvgRGBA(16, 14, 12, 235))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, PANEL.x, PANEL.y, PANEL.w, h, 10)
    nvgStrokeColor(vg, nvgRGBA(196, 164, 92, 230))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(232, 196, 96, 255))
    nvgText(vg, PANEL.x + PAD, PANEL.y + HEADER * 0.5, "测试 CE   F1 开关", nil)

    nvgSave(vg)
    nvgIntersectScissor(vg, PANEL.x + 4, PANEL.y + HEADER, PANEL.w - 8, h - HEADER - 6)
    layoutButtons(screenH)
    for _, btn in ipairs(buttons_) do
        if btn.visible then
            local hot = btn.id == "god" and CERuntime.isGodMode()
                or btn.id == "speed" and CERuntime.isSpeedOn()
                or btn.id == "pack"
            drawBtn(vg, btn.x, btn.y, btn.w, btn.h, btn.label, hot)
        end
    end
    nvgRestore(vg)
end

local function buttonAt(sx, sy)
    for _, btn in ipairs(buttons_) do
        if btn.visible and hit(sx, sy, btn.x, btn.y, btn.w, btn.h) then
            return btn.id
        end
    end
    return nil
end

local function inPanel(sx, sy, screenH)
    return hit(sx, sy, PANEL.x, PANEL.y, PANEL.w, panelH(screenH or 1080))
end

function CEPanel.handleDown(sx, sy, screenH)
    if not open_ then
        pressedId = nil
        captured_ = false
        return false
    end
    layoutButtons(screenH or 1080)
    local id = buttonAt(sx, sy)
    if id then
        pressedId = id
        captured_ = true
        return true
    end
    if inPanel(sx, sy, screenH) then
        pressedId = nil
        captured_ = true
        return true
    end
    pressedId = nil
    captured_ = false
    return false
end

function CEPanel.handleUp(sx, sy, screenH)
    if not captured_ then return false end
    captured_ = false
    local id = pressedId
    pressedId = nil
    if id == "toggle" then
        if hit(sx, sy, TOGGLE.x, TOGGLE.y, TOGGLE.w, TOGGLE.h) then
            CEPanel.toggle()
        end
        return true
    end
    if not open_ or not id then return true end
    layoutButtons(screenH or 1080)
    if buttonAt(sx, sy) ~= id then return true end
    CEPanel.run(id)
    return true
end

function CEPanel.handleWheel(sx, sy, wheel, screenH)
    if not open_ or not inPanel(sx, sy, screenH) then return false end
    scroll_ = scroll_ - wheel * 28
    clampScroll(screenH or 1080)
    print("[CE] scroll=" .. tostring(scroll_))
    return true
end

function CEPanel.run(id)
    print("[CE] run " .. tostring(id))
    if id == "pack" then
        CEService.testPack()
    elseif id == "res" then
        CEService.giveAllResources()
    elseif id == "heroes" then
        CEService.unlockAllHeroes()
    elseif id == "lv10" then
        CEService.levelAllHeroes(10)
    elseif id == "awk" then
        CEService.awakenAllHeroes()
    elseif id == "plv" then
        CEService.setPlayerLevel(30)
    elseif id == "stage10" then
        CEService.jumpStages(10)
    elseif id == "preterm" then
        CEService.jumpPreTerminal()
    elseif id == "stage305" then
        CEService.jumpToAtLeast(305)
    elseif id == "kill" then
        CEService.instantClear()
    elseif id == "heal" then
        CEService.healAllies()
    elseif id == "god" then
        local on = CERuntime.toggleGodMode()
        require("core.UiToast").show(on and "无敌已开" or "无敌已关", 1.6)
    elseif id == "speed" then
        local on = CERuntime.toggleSpeed()
        require("core.UiToast").show(on and "三倍速已开" or "三倍速已关", 1.6)
    elseif id == "guide" then
        CEService.skipGuide()
    elseif id == "dungeon" then
        CEService.boostDungeons(5)
    elseif id == "loot" then
        CEService.fillLootbox()
    elseif id == "talent" then
        CEService.lightAllTalents()
    elseif id == "relic" then
        CEService.giveRelicSet()
    elseif id == "reset" then
        local now = os.clock()
        if resetArm_ == 0 or now - resetArm_ > 3 then
            resetArm_ = now
            require("core.UiToast").show("3 秒内再点一次确认清档", 2.0)
            print("[CE] reset armed")
            return
        end
        resetArm_ = 0
        CEService.resetSave()
    end
end

return CEPanel
