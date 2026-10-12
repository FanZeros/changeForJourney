-- 扫荡界面隔离验收：真实Dialog/Service/成长/输入；组件树替身不冒充像素验收。
-- 原生截图另由 sweep_ui_preview 执行；本入口禁止真实Sweep、持久化、玩家文件和RNG。
local F = require("tests.SweepRegressionFixture")
local cases, assertions, failures = 0, 0, {}
local function eq(a, b, name)
    assertions = assertions + 1
    assert(a == b, name .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function near(a, b, name)
    assertions = assertions + 1
    assert(math.abs(a - b) < 1e-10, name .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function run(name, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. " => " .. tostring(err) end
    print("[sweep_dialog_preview_test] " .. (ok and "PASS " or "FAIL ") .. name)
end
local function point(x, y)
    return 540 + (x - 540) * 0.8, 1195 + (y - 1195) * 0.8
end
local function visit(w, fn)
    fn(w)
    for _, child in ipairs(w.children) do visit(child, fn) end
end
local function find(root, predicate)
    local found = {}
    visit(root, function(w) if predicate(w) then found[#found + 1] = w end end)
    return found
end
local function at(root, x, y)
    for _, w in ipairs(root.children) do
        if w.props.left == x and w.props.top == y then return w end
    end
    error("真实树缺少控件 " .. x .. "," .. y)
end

local function setup()
    local h = F.new()
    F.install(h)
    local captured = { previews = {}, args = {}, calls = {}, actualSweep = 0 }
    local function widget(kind)
        return function(props)
            local w = { kind = kind, props = props, children = props.children or {} }
            function w:AddChild(child) self.children[#self.children + 1] = child end
            function w:SetText(text) self.props.text = text end
            function w:SetDisabled(value) self.props.disabled = value end
            function w:SetVisible(value) self.props.visible = value end
            function w:SetValue(value) self.props.value = value end
            function w:SetStyle(style) for k, v in pairs(style) do self.props[k] = v end end
            function w:Destroy() self.destroyed = true end
            return w
        end
    end
    h.modules["urhox-libs/UI"] = { Panel = widget("Panel"), Label = widget("Label"),
        Button = widget("Button"), ProgressBar = widget("ProgressBar") }
    h.modules["ui.widget.DesignWidgetSurface"] = { init = function() end,
        draw = function(root, _, width, height)
            captured.tree, captured.width, captured.height = root, width, height
        end }
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
        captured.args[#captured.args + 1] = table.pack(...)
        local result, err = realPreview(...)
        captured.previews[#captured.previews + 1] = result or { reason = err }
        return result, err
    end
    h.Sweep.Sweep = function()
        captured.actualSweep = captured.actualSweep + 1
        error("预览专项禁止实际Sweep")
    end
    h.Transaction.SetPersistCallback(function() error("预览专项禁止持久化") end)
    local dialog = h.require("ui.battle.stage.SweepDialog")
    dialog.onSweep = function(count, team, stage)
        captured.calls[#captured.calls + 1] = { count = count, team = team, stage = stage }
    end
    h.forbidRNG = true
    local function click(x, y) return dialog.handleInput(point(x, y)) end
    local function draw()
        h.env.time.elapsedTime = h.env.time.elapsedTime + 1
        dialog.draw({})
    end
    return h, dialog, captured, click, draw
end
local function readonly(h, out, before)
    eq(F.equal(h.data, before), true, "预估/输入不修改隔离数据")
    eq(h.rngCalls, 0, "不消费RNG")
    eq(out.actualSweep, 0, "没有实际Sweep")
    eq(h.persists, 0, "没有保存")
    eq(h.notifications, 0, "没有脏通知")
    eq(h.events, 0, "没有货币事件")
end
local function checkProgress(view, progress, format)
    eq(view.children[2].props.text, string.format("Lv.%d → Lv.%d", progress.beforeLevel, progress.level), "新等级文案")
    local bar, text = view.children[3], view.children[4]
    eq(bar.kind, "ProgressBar", "真实新进度条类型")
    eq(bar.props.max, 1, "进度条max归一化")
    local fraction = progress.maxExp > 0 and progress.exp / progress.maxExp or (progress.capped and 1 or 0)
    near(bar.props.value, fraction, "进度仅按新本级经验归一化")
    eq(text.props.text, progress.capped and "满级" or
        (format(progress.exp) .. " / " .. format(progress.maxExp)), "新本级剩余经验")
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
    run("四分类731热区、固定入口队无切换且不跟随自动推进", function()
        local h, dialog, out, click, draw = setup()
        dialog.open(2, 1905)
        for i, kind in ipairs({ "main", "gold_mine", "equipment_vault", "black_diamond" }) do
            click(65 + 45 + (i - 1) * 217 + 102.5, 731)
            local result = out.previews[#out.previews]
            local target = kind == "main" and 6705 or h.DC.getStageId(kind, 1)
            eq(result.stageId, target, "分类目标 " .. kind)
            eq(result.teamIdx, 2, "分类不改固定队")
            draw()
            local category = at(out.tree, 45 + (i - 1) * 217, 135)
            eq(category.props.height, 52, "真实分类控件高度")
            eq(570 + category.props.top + category.props.height / 2, 731, "树与分类热区中心一致")
            click(438 + 194, 968) -- 旧队2按钮坐标现在是非交互收益卡。
            h.data.battle.teamStageIds[2] = 2501
            click(540, 1700)
            eq(out.calls[#out.calls].team, 2, "旧队按钮不切队")
            eq(out.calls[#out.calls].stage, target, "确认不随当前队目标变化")
        end
        eq(#find(out.tree, function(w)
            return w.kind == "Button" and (w.props.text == "队1" or w.props.text == "队2" or w.props.text == "队3")
        end), 0, "新UI没有切队按钮")
        eq(h.rngCalls, 0, "所有分类预估纯读")
    end)
    run("装备小数期望、六指标独立金币黑晶图标与真实树尺寸", function()
        local h, dialog, out, click, draw = setup()
        local before = F.copy(h.data)
        dialog.open(1, h.DC.getStageId("equipment_vault", 1))
        click(798, 1510)
        draw()
        local result = out.previews[#out.previews]
        eq(result.count, 2, "次数更新")
        eq(result.cost, 2, "一券一场")
        eq(result.ticketDrop, 0, "Service扫荡不产券")
        eq(result.equipCount > 0 and result.equipCount < 1, true, "保留不足一件期望")
        eq(out.tree ~= nil, true, "新UI树已渲染")
        eq(out.width, 950, "Surface真实传入宽")
        eq(out.height, 1250, "Surface真实传入高")
        eq(out.tree.props.width, 950, "树根宽")
        eq(out.tree.props.height, 1250, "树根高")
        local cards = find(out.tree, function(w) return w.props.width == 277 and w.props.height == 90 end)
        eq(#cards, 6, "六指标卡277x90")
        local captions = { "金币", "黑晶", "远征经验", "每名队员经验", "随机装备 / 件", "卷轴合计 / 张" }
        local values = { result.gold, result.diamond, result.playerExp, result.heroExp, result.equipCount, result.scrollCount }
        local format = h.require("ui.battle.stage.StageSelectRewardPreview").formatEstimate
        for i, card in ipairs(cards) do
            eq(card.props.left, 45 + ((i - 1) % 3) * 289, "指标列坐标")
            eq(card.props.top, 310 + math.floor((i - 1) / 3) * 100, "指标行坐标")
            eq(card.children[#card.children - 1].props.text, captions[i], "指标定义不是ticketDrop")
            eq(card.children[#card.children].props.text, format(values[i]), "指标逐项对应Service值")
        end
        local defs = h.require("config.ResourceDefs").DEFS
        eq(cards[1].children[1].props.backgroundImage, defs.gold.iconPath, "金币独立icon")
        eq(cards[2].children[1].props.backgroundImage, defs.diamond.iconPath, "黑晶独立icon")
        eq(cards[1].children[1] ~= cards[2].children[1], true, "独立图标控件")
        eq(cards[6].children[1].props.backgroundImage, defs.random_scroll.iconPath, "第六项卷轴不是券掉落")
        for _, card in ipairs(cards) do
            eq(#find(card, function(w) return w.props.backgroundImage == defs.sweep_ticket.iconPath end), 0, "收益无券图标")
        end
        eq(at(out.tree, 175, 842).props.text, "扫荡次数：2", "次数文案")
        eq(at(out.tree, 222, 994).props.text, "消耗 2 张扫荡券（拥有 30 张）", "成本文案")
        readonly(h, out, before)
    end)
    run("真实Service末参player、新成员成长与本级归一化", function()
        local h, dialog, out, click, draw = setup()
        for _, hero in pairs(h.data.heroes.roster) do hero.level, hero.exp = 1, 0 end
        h.data.heroes.teams = { { slots = { 1, 2, 3, 4 } }, { slots = { 0, 0, 0, 0 } }, { slots = { 0, 0, 0, 0 } } }
        h.data.player = { level = 1, exp = 99 }
        for i = 1, 4 do h.data.heroes.roster[i].exp = i * 3 end
        local before = F.copy(h.data)
        dialog.open(1, 905)
        click(798, 1510)
        draw()
        local result, args = out.previews[#out.previews], out.args[#out.args]
        eq(args.n, 10, "Preview真实十参签名")
        eq(args[10], h.data.player, "最后一参是player数据引用")
        eq(result.playerProgress ~= nil, true, "不虚构/遗漏playerProgress")
        local expected = { level = before.player.level, exp = before.player.exp + result.playerExp }
        -- 独立玩家oracle：本级逐级减经验，不借SweepProgress或Service返回的新等级。
        while h.ET.player[expected.level] and expected.exp >= h.ET.player[expected.level] do
            expected.exp = expected.exp - h.ET.player[expected.level]
            expected.level = expected.level + 1
        end
        eq(result.playerProgress.level, expected.level, "玩家预估新等级")
        eq(result.playerProgress.exp, expected.exp, "玩家预估本级剩余")
        eq(result.playerProgress.maxExp, h.ET.player[expected.level], "玩家新本级阈值")
        eq(result.playerProgress.beforeLevel, 1, "玩家原等级")
        eq(expected.level > 1, true, "覆盖跨级不是原值")
        local format = h.require("ui.battle.stage.StageSelectRewardPreview").formatEstimate
        checkProgress(at(out.tree, 45, 520), result.playerProgress, format)
        local members = find(out.tree, function(w) return w.props.width == 202 and w.props.height == 158 end)
        eq(#members, 4, "四成员单行卡")
        eq(#result.heroProgress, 4, "Service四个成员成长")
        for i, card in ipairs(members) do
            local growth = result.heroProgress[i]
            local old = before.heroes.roster[i]
            local oracle = h.ET.simulateHeroExp(old.level, old.exp, result.heroExp)
            eq(growth.heroId, i, "成员保持真实槽序")
            eq(growth.level, oracle.level, "成员新等级")
            eq(growth.exp, oracle.exp, "成员新本级经验")
            eq(growth.maxExp, oracle.maxExp, "成员新本级阈值")
            eq(card.props.left, 45 + (i - 1) * 217, "成员横向排列")
            eq(card.props.top, 671, "成员单行Y")
            eq(card.props.top + card.props.height <= 842, true, "成员不覆盖数量")
            eq(card.props.visible, true, "有成员SetVisible")
            eq(card.children[1].props.backgroundImage, h.require("config.HeroAssetUtil").getIconPath(i), "真实成员icon")
            eq(card.children[2].props.text, h.require("config.HeroConfig").get(i).name, "真实成员名")
            -- 成员卡[1]=icon,[2]=name,[3]=level,[4]=bar,[5]=exp。
            checkProgress({ children = { card.children[2], card.children[3], card.children[4], card.children[5] } }, growth, format)
        end
        readonly(h, out, before)
        h.data.heroes.teams[1].slots = { 1, 0, 0, 0 }
        draw()
        eq(members[1].props.visible, true, "保留第一成员")
        for i = 2, 4 do eq(members[i].props.visible, false, "空成员隐藏不留旧值") end
    end)
    run("满级和缺player不伪造进度", function()
        local h, dialog, out, _, draw = setup()
        h.data.heroes.roster[1].level = 200
        dialog.open(1, 1905); draw()
        local result = out.previews[#out.previews]
        checkProgress(at(out.tree, 45, 520), result.playerProgress,
            h.require("ui.battle.stage.StageSelectRewardPreview").formatEstimate)
        local member = at(out.tree, 45, 671)
        eq(member.children[4].props.value, 1, "满级成员进度1")
        eq(member.children[5].props.text, "满级", "满级成员文案")
        h.data.player = nil; draw()
        local player = at(out.tree, 45, 520)
        eq(out.previews[#out.previews].playerProgress, nil, "可选player缺失")
        eq(player.children[2].props.text, "—", "缺玩家等级占位")
        eq(player.children[3].props.value, 0, "缺玩家进度0")
        eq(player.children[4].props.text, "—", "缺玩家经验占位")
    end)
    run("无已通分类、空队、锁队和不足券不能发请求", function()
        local h, dialog, out, click, draw = setup()
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
        draw(); eq(at(out.tree, 270, 1080).props.disabled, true, "安全拒绝按钮禁用")
        eq(h.rngCalls, 0, "拒绝不消费随机")
        eq(out.actualSweep, 0, "拒绝不调用实际Sweep")
    end)
    run("滑条/拖动/最大45052场，余额下调与耗尽重新夹紧", function()
        local h, dialog, out, click, draw = setup()
        h.data.currency.sweepTicket = 45052
        dialog.open(1, 1905)
        click(740, 1510)
        eq(out.calls[1], nil, "调滑条不提交")
        draw(); eq(out.previews[#out.previews].count, 45052, "滑条可到45052不是10")
        eq(at(out.tree, 715, 841).props.disabled, true, "到券数最大按钮禁用")
        click(540, 1700); eq(out.calls[1].count, 45052, "大批量提交仅记录不扫荡")
        click(282, 1510); draw()
        eq(out.previews[#out.previews].count, 45051, "减一场")
        eq(at(out.tree, 715, 841).props.disabled, false, "未到上限允许最大")
        click(857, 1435); draw()
        eq(out.previews[#out.previews].count, 45052, "最大按钮全券数")
        click(798, 1510); draw()
        eq(out.previews[#out.previews].count, 45052, "加号不越余额")
        dialog.handleDragBegin(point(540, 1510))
        dialog.handleDragMove(point(900, 1510)); draw()
        eq(out.previews[#out.previews].count, 45052, "拖动越右边夹最大")
        dialog.handleDragMove(point(100, 1510)); draw()
        eq(out.previews[#out.previews].count, 1, "拖动越左边夹1")
        eq(dialog.handleDragEnd(), true, "拖动结束")
        eq(dialog.handleDragMove(point(740, 1510)), false, "结束后不再拖动")
        click(857, 1435)
        h.data.currency.sweepTicket = 3
        click(540, 1700); eq(out.calls[2].count, 3, "余额二次校验")
        h.data.currency.sweepTicket = 2.9
        click(857, 1435); draw(); click(540, 1700)
        eq(out.calls[3].count, 2, "maxCount依据券数向下取整")
        eq(at(out.tree, 222, 994).props.text, "消耗 2 张扫荡券（拥有 2 张）", "浮点余额绘制统一取整")
        for _, invalid in ipairs({ -1, math.huge, 0 / 0 }) do
            h.data.currency.sweepTicket = invalid
            draw(); click(540, 1700)
            eq(at(out.tree, 715, 841).props.disabled, true, "非法券余额最大禁用")
            eq(at(out.tree, 270, 1080).props.disabled, true, "非法券余额确认禁用")
            eq(at(out.tree, 222, 994).props.text, "消耗 1 张扫荡券（拥有 0 张）", "非法券余额显示0")
            eq(#out.calls, 3, "非法券余额不发请求")
        end
        h.data.currency.sweepTicket = 0
        local before = F.copy(h.data)
        draw()
        eq(out.previews[#out.previews].count, 1, "耗尽次数夹1非0负值")
        eq(at(out.tree, 715, 841).props.disabled, true, "耗尽最大禁用")
        eq(at(out.tree, 270, 1080).props.disabled, true, "耗尽确认禁用")
        eq(at(out.tree, 222, 994).props.text, "消耗 1 张扫荡券（拥有 0 张）", "耗尽余额显示")
        click(857, 1435); click(798, 1510); click(740, 1510); click(540, 1700)
        eq(#out.calls, 3, "耗尽不能发请求")
        readonly(h, out, before)
    end)
    print(string.format("[sweep_dialog_preview_test] SUMMARY cases=%d failures=%d assertions=%d",
        cases, #failures, assertions))
    for _, failure in ipairs(failures) do log:Write(LOG_ERROR, "[sweep_dialog_preview_test] " .. failure) end
    engine:Exit()
end
