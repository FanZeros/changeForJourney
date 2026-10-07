-- 扫荡界面隔离验收：真实预估/输入，组件树替身只检查内容与坐标，不宣称像素验收。
local F = require("tests.SweepRegressionFixture")
local cases, assertions, failures = 0, 0, {}
local function eq(a, b, name)
    assertions = assertions + 1
    assert(a == b, name .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function run(name, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. " => " .. tostring(err) end
    print("[sweep_dialog_preview_test] " .. (ok and "PASS " or "FAIL ") .. name)
end

local function setup()
    local h = F.new()
    F.install(h)
    local captured = { previews = {}, calls = {} }
    local function widget(props)
        local w = { props = props, children = props.children or {} }
        function w:AddChild(child) self.children[#self.children + 1] = child end
        function w:SetText(text) self.props.text = text end
        function w:SetDisabled(value) self.props.disabled = value end
        function w:SetStyle(style) for k, v in pairs(style) do self.props[k] = v end end
        function w:Destroy() self.destroyed = true end
        return w
    end
    h.modules["urhox-libs/UI"] = { Panel = widget, Label = widget, Button = widget }
    h.modules["ui.widget.DesignWidgetSurface"] = { init = function() end,
        draw = function(root) captured.tree = root end }
    h.modules["core.GameState"].getSweepTicket = function() return h.data.currency.sweepTicket end
    h.modules["ui.character.panel.CharacterPanel"] = { getActiveTeamIdx = function() return 1 end }
    h.modules["systems.ButtonFeedback"] = { trigger = function() end }
    h.modules["core.DrawUtil"] = { drawImageCentered = function() end, drawTextStroke = function() end }
    h.modules["core.DarkIcon"] = {}
    h.modules["core.I18n"] = { lookup = function(s) return s end, get = function() return "zh" end,
        format = function(s, ...) return string.format(s, ...) end }
    for _, key in ipairs({ "nvgSave", "nvgRestore", "nvgTranslate", "nvgScale", "nvgBeginPath",
        "nvgRoundedRect", "nvgFillColor", "nvgFill", "nvgCircle" }) do h.env[key] = function() end end
    h.env.nvgRGBA = function(...) return { ... } end
    local realPreview = h.Sweep.Preview
    h.Sweep.Preview = function(...)
        local result, err = realPreview(...)
        captured.previews[#captured.previews + 1] = result or { reason = err }
        return result, err
    end
    local dialog = h.require("ui.battle.stage.SweepDialog")
    dialog.onSweep = function(count, team, stage)
        captured.calls[#captured.calls + 1] = { count = count, team = team, stage = stage }
    end
    h.forbidRNG = true
    local function click(x, y)
        return dialog.handleInput(540 + (x - 540) * 0.8, 1195 + (y - 1195) * 0.8)
    end
    local function draw()
        h.env.time.elapsedTime = h.env.time.elapsedTime + 1
        dialog.draw({})
    end
    return h, dialog, captured, click, draw
end

function Start()
    run("开窗锁定真实主线关卡，不随自动推进换目标", function()
        local h, dialog, out, click = setup()
        h.data.battle.currentStageId = 2501
        dialog.open(2, 905)
        eq(out.previews[#out.previews].stageId, 905, "用传入真实关卡")
        h.data.battle.teamStageIds[2] = 6705
        click(540, 1700)
        eq(out.calls[1].stage, 905, "确认冻结目标")
        eq(out.calls[1].team, 2, "确认本队")
        eq(h.rngCalls, 0, "预估不消费随机")
    end)
    run("资源入口保留当前已通层，而非悄悄跳到最高层", function()
        local h, dialog, out, click = setup()
        h.data.dungeon.gold_mine = { floor = 4, cleared = { [1] = true, [3] = true } }
        local first = h.DC.getStageId("gold_mine", 1)
        dialog.open(1, first)
        eq(out.previews[#out.previews].stageId, first, "当前资源层")
        click(540, 1700)
        eq(out.calls[1].stage, first, "提交原层")
    end)
    run("未通资源当前层安全回退同副本已通层", function()
        local h, dialog, out = setup()
        dialog.open(1, h.DC.getStageId("gold_mine", 2))
        eq(out.previews[#out.previews].stageId, h.DC.getStageId("gold_mine", 1), "回退已通")
    end)
    run("四分类资源预估和队伍切换同一目标", function()
        local h, dialog, out, click = setup()
        dialog.open(1, 1905)
        for i, kind in ipairs({ "main", "gold_mine", "equipment_vault", "black_diamond" }) do
            click(65 + 45 + (i - 1) * 217 + 102.5, 846)
            local result = out.previews[#out.previews]
            local target = kind == "main" and 6705 or h.DC.getStageId(kind, 1)
            eq(result.stageId, target, "分类目标 " .. kind)
            click(438 + 194, 968)
            eq(out.previews[#out.previews].teamIdx, 2, "切换队2")
            eq(out.previews[#out.previews].stageId, target, "队伍不改目标")
        end
        eq(h.rngCalls, 0, "所有分类预估纯读")
    end)
    run("装备小数期望、六指标和总次数同步显示", function()
        local h, dialog, out, click, draw = setup()
        dialog.open(1, h.DC.getStageId("equipment_vault", 1))
        click(798, 1510)
        draw()
        local result = out.previews[#out.previews]
        eq(result.count, 2, "次数更新")
        eq(result.cost, 2, "一券一场")
        eq(result.ticketDrop, 0, "扫荡不产券")
        eq(result.equipCount > 0 and result.equipCount < 1, true, "保留不足一件期望")
        local tree = out.tree
        eq(tree ~= nil, true, "新UI树已渲染")
        local text, cards = {}, 0
        local function visit(w)
            if w.props.text then text[w.props.text] = true end
            if w.props.width == 277 and w.props.height == 125 then cards = cards + 1 end
            for _, child in ipairs(w.children) do visit(child) end
        end
        visit(tree)
        eq(cards, 6, "六指标卡片")
        eq(text["扫荡次数：2"], true, "次数文案")
        eq(text["消耗 2 张扫荡券（拥有 30 张）"], true, "成本文案")
        eq(text[h.require("ui.battle.stage.StageSelectRewardPreview").formatEstimate(result.equipCount)], true, "小数预估不取整")
    end)
    run("无已通分类、空队、锁队和不足券不能发请求", function()
        local h, dialog, out, click = setup()
        h.data.dungeon.black_diamond = { floor = 1, cleared = {} }
        dialog.open(1, h.DC.getStageId("black_diamond", 1))
        click(540, 1700); eq(#out.calls, 0, "未通分类拒绝")
        dialog.close(); dialog.open(1, 1905)
        h.data.heroes.teams[1].slots = { 0, 0, 0, 0 }
        click(540, 1700); eq(#out.calls, 0, "空队拒绝")
        h.data.heroes.teams[1].slots = { 1, 0, 0, 0 }
        h.data.currency.sweepTicket = 0
        click(540, 1700); eq(#out.calls, 0, "券不足拒绝")
        h.data.currency.sweepTicket = 30
        h.data.battle = { maxStageId = 305, currentStageId = 305, clearedStages = { [305] = true } }
        dialog.close(); dialog.open(3, 305)
        click(540, 1700); eq(#out.calls, 0, "锁队拒绝")
        eq(h.rngCalls, 0, "拒绝不消费随机")
    end)
    run("滑条最高10场，券余额下调重新限制次数", function()
        local h, dialog, out, click = setup()
        dialog.open(1, 1905)
        click(740, 1510)
        eq(out.calls[1], nil, "调滑条不提交")
        click(540, 1700)
        eq(out.calls[1].count, 10, "批量上限")
        h.data.currency.sweepTicket = 3
        click(540, 1700)
        eq(out.calls[2].count, 3, "余额二次校验")
    end)
    print(string.format("[sweep_dialog_preview_test] SUMMARY cases=%d failures=%d assertions=%d",
        cases, #failures, assertions))
    for _, failure in ipairs(failures) do log:Write(LOG_ERROR, "[sweep_dialog_preview_test] " .. failure) end
    engine:Exit()
end
