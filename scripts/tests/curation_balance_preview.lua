-- scaffold-2d生命周期：真实优选规划/预览服务/弹窗，玩家数据与File/FS在隔离fixture内。
-- 500件武器满仓，各其他部位100件候选；验证低评分部位也能获得仓位。
local F = require("tests.InventoryCurationFixture")
---@type NVGContextWrapper?
local vg = nil
local dialog, context = {}, {}
local language, frames = "zh_CN", 0
local initial = {}
local aliases = {}
---@type Panel?
local tree = nil
function Start()
    for _, arg in ipairs(GetArguments()) do
        local value = arg:match("^%-curation%-lang=(.+)$")
        if value then language = value end
    end
    context = F.new()
    context.allowBootFixture = true
    local config = context.require("config.EquipmentConfig")
    local keys = {}
    for key in pairs(config.ITEMS) do keys[#keys + 1] = key end
    table.sort(keys)
    local modules = F.modules(context, 500)
    local selected, candidates = {}, {}
    for _, key in ipairs(keys) do
        local template = config.ITEMS[key]
        if not selected[template.slot] then selected[template.slot] = key end
    end
    for _, slot in ipairs(config.SLOTS) do
        if slot ~= "weapon" then
            assert(selected[slot], "真实部位模板必须存在 " .. slot)
            for _ = 1, 100 do candidates[#candidates + 1] = F.item(context, selected[slot], 1, 1) end
        end
    end
    modules.lootbox = F.box(candidates)
    context:attach(modules)
    modules = context.modules
    initial, aliases = F.copy(modules), F.aliases(modules)
    local service = context.require("rules.equipment.InventoryCurationService")
    local lang = context.require("core.I18n")
    assert(lang.set(language) or lang.get() == language)
    vg = assert(nvgCreate(1))
    assert(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0)
    local surface = context.require("ui.widget.DesignWidgetSurface")
    surface.init()
    context.mocks["ui.widget.DesignWidgetSurface"] = {
        init = surface.init,
        draw = function(root, ctx, width, height)
            tree = root
            surface.draw(root, ctx, width, height)
        end,
    }
    dialog = context.require("ui.loot.InventoryCurationDialog")
    context.mocks["runtime.GameAction"] = { sendAction = function(action, params)
        if action == "CancelInventoryCuration" then service.CancelInventoryCuration(1, params.token); return true end
        assert(action == "PreviewInventoryCuration", "预览夹具禁止确认/穿戴/领取")
        local ok, reason, receipt = service.PreviewInventoryCuration(1)
        assert(ok, reason)
        local covered = {}
        for _, group in ipairs(receipt.groups) do
            covered[group.slot] = (covered[group.slot] or 0) + group.inventory
        end
        for _, slot in ipairs(config.SLOTS) do
            assert(covered[slot] and covered[slot] > 0, "满仓零配额部位必须能进入 " .. slot)
            print("[curation-balance-preview] " .. slot .. "=" .. covered[slot])
        end
        receipt.action, receipt.success, receipt.requestId = action, true, params.requestId
        dialog.onActionResult(receipt)
        return true
    end }
    dialog.bindHost({ sourceValid = function() return true end, blocked = function() return false end })
    assert(dialog.open("backpack"))
    F.same(modules, initial, "预览原数据不变")
    F.assertAliases(aliases)
    assert(context.randomCalls == 0 and context.fileCalls == 0 and context.fsCalls == 0)
    SubscribeToEvent(vg, "NanoVGRender", "HandleCurationBalancePreview")
end
function HandleCurationBalancePreview()
    local ctx = vg
    if not ctx then return end
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(ctx, width, height, dpr)
    nvgBeginPath(ctx); nvgRect(ctx, 0, 0, width, height)
    nvgFillColor(ctx, nvgRGBA(22, 19, 15, 255)); nvgFill(ctx)
    dialog.draw(ctx, width, height)
    nvgEndFrame(ctx)
    frames = frames + 1
    if frames == 120 then
        assert(tree, "真实弹窗树已绘制")
        F.same(context.modules, initial, "反复预览绘制不变更数据")
        F.assertAliases(aliases)
        print("[curation-balance-preview] ALL PASS language=" .. language .. " zeroRNG=true zeroIO=true")
    end
end
function Stop()
    if dialog.reset then dialog.reset() end
    if context.require then context.require("ui.widget.DesignWidgetSurface").shutdown() end
    if vg then nvgDelete(vg); vg = nil end
end
