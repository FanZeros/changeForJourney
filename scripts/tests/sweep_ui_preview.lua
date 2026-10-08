-- 基于 scaffold-2d 的 Start/Update/Stop 和官方 NanoVGRender 宿主帧。
-- 只安装 SweepRegressionFixture 隔离假数据，绘制真实UI/Surface/SweepDialog；绝不启动Boot。
-- 禁止真实File/玩家档/持久化/actualSweep，PNG由Runtime -screenshot写到外部验证目录。
-- -sweep-preview=main|equipment|growth|max|exhausted|capped；1920x1080用真实Viewport中栏transform。
local F = require("tests.SweepRegressionFixture")
local UI = require("urhox-libs/UI")
local ImageCache = require("urhox-libs/UI/Core/ImageCache")
local mode = "main"
for _, argument in ipairs(GetArguments()) do
    mode = argument:match("^%-sweep%-preview=(.+)$") or mode
end
local vg = nil ---@type NVGContextWrapper?
local h = {} ---@type table
local dialog = {} ---@type table
local surface = {} ---@type table
local viewport = {} ---@type table
local snapshot = {} ---@type table
local tree = nil ---@type Panel?
local result = {} ---@type table
local checks, frames, rendered, errors = 0, 0, 0, {}
local actualSweep, fileCalls, validated = 0, 0, false

local function check(value, name)
    checks = checks + 1
    if not value then errors[#errors + 1] = name end
end
local function at(root, x, y)
    for _, child in ipairs(root:GetChildren()) do
        if child.props.left == x and child.props.top == y then return child end
    end
    error("real UI missing " .. x .. "," .. y)
end
local function click(x, y)
    return dialog.handleInput(540 + (x - 540) * .8, 1195 + (y - 1195) * .8)
end
local function validateTree()
    local root = assert(tree)
    local size = root:GetLayout()
    check(size.w == 950 and size.h == 1250, "real Yoga root950x1250")
    local format = h.require("ui.battle.stage.StageSelectRewardPreview").formatEstimate
    local metrics = { result.gold, result.diamond, result.playerExp, result.heroExp, result.equipCount, result.scrollCount }
    for i, value in ipairs(metrics) do
        local card = at(root, 45 + ((i - 1) % 3) * 289, 310 + math.floor((i - 1) / 3) * 100)
        local layout = card:GetLayout()
        check(layout.w == 277 and layout.h == 90, "real metric277x90 " .. i)
        local children = card:GetChildren()
        check(children[#children]:GetText() == format(value), "real metric Service value " .. i)
        if i == 1 or i == 2 then
            local defs = h.require("config.ResourceDefs").DEFS
            check(children[1].props.backgroundImage == (i == 1 and defs.gold.iconPath or defs.diamond.iconPath),
                "real independent reward icon " .. i)
        end
    end
    local quantity = at(root, 175, 842)
    local bottom = quantity:GetAbsoluteLayout().y
    for i = 1, 4 do
        local card = at(root, 45 + (i - 1) * 217, 671)
        local layout = card:GetLayout()
        check(layout.w == 202 and layout.h == 158, "real member202x158 " .. i)
        local absolute = card:GetAbsoluteLayout()
        check(absolute.y + absolute.h <= bottom, "real member clears quantity " .. i)
        local children = card:GetChildren()
        check(card:IsVisible(), "all four members visible " .. i)
        local growth = result.heroProgress[i]
        check(children[2]:GetText() == h.require("config.HeroConfig").get(growth.heroId).name, "real member name " .. i)
        check(children[3]:GetText() == string.format("Lv.%d → Lv.%d", growth.beforeLevel, growth.level), "real member level " .. i)
        local expected = growth.maxExp > 0 and growth.exp / growth.maxExp or (growth.capped and 1 or 0)
        check(math.abs(children[4]:GetValue() - expected) < 1e-10, "real member normalized progress " .. i)
        -- 字符宽度测量只用于真实可见内容，不以mock/复制绘制替代实际树。
        for j = 2, 5 do
            if j ~= 4 then
                local text, props = children[j]:GetText(), children[j].props
                nvgFontFace(vg, "sans"); nvgFontSize(vg, UI.Theme.FontSize(props.fontSize))
                local measured = nvgTextBounds(vg, 0, 0, text)
                print(string.format("[sweep_ui_preview] TEXT member=%d field=%d width=%.2f available=%d text=%s",
                    i, j, measured, props.width, text))
                check(measured <= props.width, "member text fully fits " .. i .. "/" .. j)
            end
        end
    end
    local player = at(root, 45, 520):GetChildren()
    local growth = result.playerProgress
    check(player[2]:GetText() == string.format("Lv.%d → Lv.%d", growth.beforeLevel, growth.level), "real player new level")
    local fraction = growth.maxExp > 0 and growth.exp / growth.maxExp or (growth.capped and 1 or 0)
    check(math.abs(player[3]:GetValue() - fraction) < 1e-10, "real player normalized progress")
    check(at(root, 270, 1080):IsDisabled() == (mode == "exhausted"), "real confirm state")
    print(string.format("[sweep_ui_preview] TREE mode=%s size=%dx%d members=4 count=%d player=%d->%d exp=%s/%s",
        mode, size.w, size.h, result.count, growth.beforeLevel, growth.level, tostring(growth.exp), tostring(growth.maxExp)))
end

function Start()
    local ok, err = pcall(function()
        h = F.new(); F.install(h)
        h.forbidRNG = true
        h.env.File = function() fileCalls = fileCalls + 1; error("preview forbids player File") end
        h.env.fileSystem = setmetatable({}, { __index = function()
            return function() fileCalls = fileCalls + 1; error("preview forbids player filesystem") end
        end })
        h.Transaction.SetPersistCallback(function() error("preview forbids persistence") end)
        h.Sweep.Sweep = function() actualSweep = actualSweep + 1; error("preview forbids actualSweep") end
        h.data.heroes.teams = { { slots = { 1, 2, 3, 4 } }, { slots = { 0, 0, 0, 0 } }, { slots = { 0, 0, 0, 0 } } }
        h.data.player = { level = 100, exp = 999999900 }
        for _, hero in pairs(h.data.heroes.roster) do hero.level, hero.exp = 100, 199999990 end
        if mode == "growth" then
            h.data.player = { level = 1, exp = 99 }
            for _, hero in pairs(h.data.heroes.roster) do hero.level, hero.exp = 1, 0 end
        elseif mode == "capped" then
            h.data.player = { level = 200, exp = 0 }
            for _, hero in pairs(h.data.heroes.roster) do hero.level, hero.exp = 200, 0 end
        end
        h.data.currency.sweepTicket = mode == "exhausted" and 0 or 45052
        h.modules["urhox-libs/UI"] = UI
        h.modules["urhox-libs/UI/Core/ImageCache"] = ImageCache
        h.modules["core.GameState"].getSweepTicket = function() return h.data.currency.sweepTicket end
        h.modules["systems.ButtonFeedback"] = { trigger = function() end }
        h.modules["core.DrawUtil"] = { drawImageCentered = function() end, drawTextStroke = function() end }
        h.modules["core.DarkIcon"] = {}
        h.modules["core.I18n"] = { lookup = function(text) return text end, get = function() return "zh" end,
            format = function(text, ...) return string.format(text, ...) end }
        surface = h.require("ui.widget.DesignWidgetSurface")
        surface.init()
        vg = assert(nvgCreate(1), "real NanoVG context")
        assert(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "real host font")
        local realDraw = surface.draw
        surface.draw = function(root, context, width, height)
            tree = root
            return realDraw(root, context, width, height)
        end
        local preview = h.Sweep.Preview
        h.Sweep.Preview = function(...)
            result = assert(preview(...))
            return result
        end
        viewport = h.require("core.Viewport")
        dialog = h.require("ui.battle.stage.SweepDialog")
        dialog.init(vg)
        dialog.onSweep = function() error("preview has no submit actions") end
        local stage = mode == "equipment" and h.DC.getStageId("equipment_vault", 1) or 1905
        dialog.open(1, stage)
        if mode == "max" then click(857, 1435)
        elseif mode == "growth" or mode == "equipment" then click(798, 1510) end
        snapshot = F.copy(h.data)
        h.env.time.elapsedTime = 101 -- 冻结完成的开窗动画和受控成长数据。
        SubscribeToEvent("Update", "SweepPreviewUpdate")
        SubscribeToEvent(vg, "NanoVGRender", "SweepPreviewRender")
        print("[sweep_ui_preview] START isolated fixture + real UI " .. mode)
    end)
    if not ok then
        errors[#errors + 1] = tostring(err)
        log:Write(LOG_ERROR, "[sweep_ui_preview] Start " .. tostring(err))
        engine:Exit()
    end
end

---@param eventType string
---@param eventData UpdateEventData
function SweepPreviewUpdate(eventType, eventData)
    frames = frames + 1
    UI.Update(eventData:GetFloat("TimeStep"))
end
function SweepPreviewRender()
    if not vg then return end
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    -- nvg-resolution-mode A：1920x1080 contain；DPR只交给BeginFrame。
    local scale = math.min(width / 1920, height / 1080)
    nvgBeginFrame(vg, width, height, dpr)
    nvgSave(vg)
    nvgTranslate(vg, (width - 1920 * scale) / 2, (height - 1080 * scale) / 2)
    nvgScale(vg, scale, scale)
    nvgBeginPath(vg); nvgRect(vg, 0, 0, 1920, 1080)
    nvgFillColor(vg, nvgRGBA(12, 13, 17, 255)); nvgFill(vg)
    local ox, oy, fit = viewport.layout(1920, 1080)
    viewport.begin(vg, viewport.PANELS.center, ox, oy, fit)
    local ok, err = pcall(function()
        dialog.draw(vg)
        rendered = rendered + 1
        if not validated and tree then validateTree(); validated = true end
    end)
    if not ok then
        errors[#errors + 1] = tostring(err)
        log:Write(LOG_ERROR, "[sweep_ui_preview] Render " .. tostring(err))
        validated = true
    end
    viewport.finish(vg)
    nvgRestore(vg)
    nvgEndFrame(vg)
end
function Stop()
    check(validated and rendered > 0, "real UI tree rendered")
    check(F.equal(h.data, snapshot), "all isolated data remain unchanged")
    check(h.rngCalls == 0, "no RNG")
    check(actualSweep == 0, "no actualSweep")
    check(fileCalls == 0, "no player File or filesystem")
    check(h.persists == 0 and h.notifications == 0 and h.events == 0, "no persistence/notifications")
    if dialog.close then dialog.close() end
    if tree then tree:Destroy(); tree = nil end
    if surface.shutdown then surface.shutdown() end
    if vg then nvgDelete(vg); vg = nil end
    print(string.format("[sweep_ui_preview] SUMMARY mode=%s frames=%d rendered=%d failures=%d assertions=%d file=%d actualSweep=%d rng=%d",
        mode, frames, rendered, #errors, checks, fileCalls, actualSweep, h.rngCalls or -1))
    for _, err in ipairs(errors) do log:Write(LOG_ERROR, "[sweep_ui_preview] " .. err) end
end
