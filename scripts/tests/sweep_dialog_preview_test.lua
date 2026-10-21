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
    local captured = { previews = {}, args = {}, calls = {}, actualSweep = 0, pending = false }
    h.modules["runtime.LocalActionBridge"] = {
        getSweepState = function() return captured.work end,
        isSweepPending = function() return captured.pending end,
    }
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
    dialog.onSweep = function(count, team, stage, requestId)
        captured.calls[#captured.calls + 1] = { count = count, team = team, stage = stage, requestId = requestId }
        return false -- 旧预览矩阵只记录参数，不接受/启动实际扫荡。
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
        local playerProgress = assert(result.playerProgress) ---@type table
        eq(args.n, 10, "Preview真实十参签名")
        eq(args[10], h.data.player, "最后一参是player数据引用")
        eq(result.playerProgress ~= nil, true, "不虚构/遗漏playerProgress")
        local expected = { level = before.player.level, exp = before.player.exp + result.playerExp }
        -- 独立玩家oracle：本级逐级减经验，不借SweepProgress或Service返回的新等级。
        while h.ET.player[expected.level] and expected.exp >= h.ET.player[expected.level] do
            expected.exp = expected.exp - h.ET.player[expected.level]
            expected.level = expected.level + 1
        end
        eq(playerProgress.level, expected.level, "玩家预估新等级")
        eq(playerProgress.exp, expected.exp, "玩家预估本级剩余")
        eq(playerProgress.maxExp, h.ET.player[expected.level], "玩家新本级阈值")
        eq(playerProgress.beforeLevel, 1, "玩家原等级")
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
    run("真实阶段计数、处理中所有调节与关闭输入防重复", function()
        local h, dialog, out, click, draw = setup()
        local before = F.copy(h.data)
        local acceptedId = ""
        dialog.onSweep = function(count, team, stage, requestId)
            acceptedId = requestId
            out.calls[#out.calls + 1] = { count = count, team = team, stage = stage, requestId = requestId }
            out.pending = true
            out.work = { sweepRequestId = requestId, pending = true, phase = "generate", completed = 7, total = 30 }
            return true
        end
        dialog.open(2, 1905)
        click(857, 1435)
        click(540, 1700)
        eq(type(acceptedId), "string", "提交业务字符串身份")
        local previewCount = #out.previews
        draw()
        eq(#out.previews, previewCount, "处理中不重复昂贵预估")
        eq(at(out.tree, 270, 1080).props.disabled, true, "确认禁用")
        eq(at(out.tree, 270, 1080).props.text, "处理中", "等待按钮明确")
        eq(at(out.tree, 45, 1196).props.text, "生成奖励 · 7 / 30", "真实阶段计数不是墙钟百分比")
        near(at(out.tree, 270, 1184).props.value, 7 / 30, "真实进度条")
        eq(at(out.tree, 270, 1184).props.showLabel, false, "不显示假全程百分比")
        for _, position in ipairs({ { 540, 1700 }, { 282, 1510 }, { 798, 1510 }, { 857, 1435 },
            { 740, 1510 }, { 212.5, 731 }, { 935, 627.5 }, { 0, 0 } }) do
            eq(click(position[1], position[2]), true, "等待期间吞输入")
        end
        dialog.handleDragBegin(point(540, 1510))
        dialog.handleDragMove(point(100, 1510)); dialog.handleDragEnd()
        draw()
        eq(#out.calls, 1, "重复按与拖动不再发送")
        eq(dialog.isOpen(), true, "等待不被关闭")
        eq(at(out.tree, 175, 842).props.text, "扫荡次数：30", "请求数量冻结")
        for i = 1, 4 do eq(at(out.tree, 45 + (i - 1) * 217, 135).props.disabled, true, "分类禁用") end
        out.work.phase, out.work.completed, out.work.total = "presentation", 300, 300
        draw()
        eq(at(out.tree, 45, 1196).props.text, "整理奖励", "阶段100%仍只标整理不是业务完成")
        eq(at(out.tree, 270, 1184).props.visible, false, "整理阶段隐藏多轮重置进度")
        eq(dialog.isOpen(), true, "阶段100%不提前关框")
        readonly(h, out, before)
        out.pending = false
        eq(dialog.onActionResult({ sweepRequestId = acceptedId, success = false, reason = "模拟保存失败" }), true, "匹配失败消费")
        draw()
        eq(at(out.tree, 270, 1080).props.disabled, false, "失败恢复确认")
        eq(at(out.tree, 45, 1196).props.text, "模拟保存失败", "保留权威失败原因")
        click(282, 1510); draw()
        eq(at(out.tree, 175, 842).props.text, "扫荡次数：29", "失败恢复调节")
    end)
    run("同步回执身份、旧回执与关闭重开不关新页面", function()
        local _, dialog, out, click, draw = setup()
        local ids = {}
        dialog.onSweep = function(_, _, _, requestId)
            ids[#ids + 1] = requestId
            eq(dialog.onActionResult({ sweepRequestId = requestId, success = false, reason = "同步拒绝" }), true, "先登记再同步回执")
            return false
        end
        dialog.open(1, 1905); click(540, 1700); draw()
        eq(at(out.tree, 45, 1196).props.text, "同步拒绝", "外层不覆盖同步原因")
        dialog.onSweep = function(_, _, _, requestId) ids[#ids + 1] = requestId; return true end
        click(540, 1700)
        local first = ids[#ids]
        dialog.close(); dialog.open(2, 905)
        eq(dialog.onActionResult({ sweepRequestId = first, success = true }), false, "关闭重开不认旧成功")
        eq(dialog.isOpen(), true, "新页保留")
        click(540, 1700)
        local second = ids[#ids]
        eq(second ~= first, true, "新请求不复用身份")
        eq(dialog.onActionResult({ sweepRequestId = first, success = false }), false, "迟到失败不清新等待")
        eq(dialog.onActionResult({ success = true }), false, "无id旧回执不关闭新页")
        draw(); eq(at(out.tree, 270, 1080).props.disabled, true, "新请求仍等待")
        eq(dialog.onActionResult({ sweepRequestId = second, success = true }), true, "匹配成功才关闭")
        eq(dialog.isOpen(), false, "真正成功收尾")
    end)
    run("外部任务、未知进度与legacy关闭态自持等待树", function()
        local h, dialog, out, click, draw = setup()
        out.pending, out.work = true, { phase = "queued" }
        dialog.open(1, 1905); draw()
        eq(at(out.tree, 45, 1196).props.text, "处理中", "未知total不捏造数值")
        eq(at(out.tree, 270, 1184).props.value, 0, "未知total无伪进度")
        click(540, 1700); eq(#out.calls, 0, "全局任务防重复")
        eq(dialog.onActionResult({ sweepRequestId = "legacy-id", success = true }), false, "旁路回执不认领")
        dialog.close()
        local previews = #out.previews
        dialog.drawPending({})
        eq(dialog.isOpen(), false, "等待出口不打开业务页面")
        eq(out.width, 820, "legacy等待树宽")
        eq(out.height, 220, "legacy等待树高")
        eq(at(out.tree, 35, 32).props.text, "处理中", "关闭态真实等待")
        eq(#out.previews, previews, "关闭态不做预估")
        out.work = { phase = "presentation", completed = 12, total = 24 }
        dialog.drawPending({})
        eq(at(out.tree, 35, 32).props.text, "整理奖励", "legacy整理不显示阶段回退")
        eq(at(out.tree, 35, 112).props.visible, false, "legacy整理隐藏进度")
        eq(h.rngCalls, 0, "等待树零随机")
    end)
    run("CMH完整候选可yield、全装备保留且最终一次展示后匹配关框", function()
        local h, dialog, out, click = setup()
        local shown, tokens, toasts = {}, {}, {}
        local popup = {
            prepareRewards = function(rewards, checkpoint)
                checkpoint("presentation", 0, #rewards)
                local token = { rewards = rewards }
                tokens[#tokens + 1] = token
                return token
            end,
            show = function(title, rewards, opts)
                eq(dialog.isOpen(), true, "show前仍开框")
                shown[#shown + 1] = { title = title, rewards = rewards, opts = opts }
            end,
        }
        h.modules["ui.hud.popup.RewardPopup"] = popup
        h.modules["core.UiToast"] = { show = function(text) toasts[#toasts + 1] = text end }
        for _, name in ipairs({ "ui.loot.LootBox", "ui.loot.LootBoxPage", "ui.blacksmith.BlacksmithPage",
            "ui.backpack.BackpackPanel", "ui.church.ChurchPage", "ui.church.talent.TalentPage", "ui.tavern.TavernPage",
            "ui.market.MarketPage", "ui.dungeon.DungeonPage", "ui.dungeon.DungeonBattleScene", "ui.dev.GMConsolePanel",
            "ui.hud.TopBar", "ui.battle.scene.BattleScene", "ui.character.equip.EquipmentDetail",
            "ui.hud.popup.RedeemCodePanel", "systems.TutorialManager" }) do
            h.modules[name] = {}
        end
        local cmh = h.require("runtime.ClientMessageHandler")
        cmh.setup({ sendAction = function() error("禁止发送旁支动作") end, ui = {} })
        local id = ""
        dialog.onSweep = function(_, _, _, requestId) id = requestId; return true end
        dialog.open(1, 1905); click(540, 1700)
        local protocol = h.require("shared.Protocol")
        local data = { action = protocol.ACTION_TYPES.SWEEP, success = true, sweepRequestId = id,
            gold = 13, diamond = 5, autoDecomposeEssence = 7, playerExp = 11, heroExp = 17,
            heroExpTotal = 100, teamIdx = 2, equips = {}, scrollDrops = { weaponScroll = 4 } }
        for i = 1, 1024 do
            data.equips[i] = { type = "equip", templateId = "W1", quality = i % 6 + 1, level = i,
                equip = { seq = i, marker = { intact = true } }, destination = i < 500 and "inventory" or "lootbox" }
        end
        data.equips[1024].type = nil -- 兼容旧回执只能补副本，不改原表。
        local before = F.copy(data)
        local co = coroutine.create(function()
            return cmh.prepareSweepPresentation(data, function(phase, done, total)
                eq(phase, "presentation", "私有展示检查点阶段")
                eq(done >= 0 and done <= total, true, "真实检查点边界")
                coroutine.yield()
            end)
        end)
        local presentation
        repeat
            local ok, value = coroutine.resume(co)
            eq(ok, true, "预处理协程正常")
            eq(#shown, 0, "处理中不展示半奖励")
            eq(dialog.isOpen(), true, "处理中不关框")
            if coroutine.status(co) == "dead" then presentation = value end
        until coroutine.status(co) == "dead"
        eq(presentation.version, 1, "候选版本")
        eq(#presentation.rewards, 1028, "1024装备与四类资源完整无截断")
        eq(presentation.preparedRewards, tokens[1], "完整排序token")
        eq(presentation.rewards[4], data.equips[1], "新完整行只读复用")
        eq(presentation.rewards[1027] ~= data.equips[1024], true, "旧行补type副本")
        eq(presentation.rewards[1027].equip, data.equips[1024].equip, "旧行完整实例保留")
        eq(F.equal(data, before), true, "全量预处理不改源数据")
        eq(presentation.subtitle:find("队2每名队员经验 +17", 1, true) ~= nil, true, "回执每人经验摘要")
        data.sweepPresentation = presentation
        cmh.handleActionResult(data)
        eq(#shown, 1, "最终只展示一次")
        eq(shown[1].rewards, presentation.rewards, "不重新包装全量数组")
        eq(shown[1].opts.preparedRewards, presentation.preparedRewards, "透传opaque token")
        eq(dialog.isOpen(), false, "完整show返回后匹配关框")
        dialog.open(1, 905)
        cmh.handleActionResult({ action = protocol.ACTION_TYPES.SWEEP, success = false,
            sweepRequestId = id, reason = "迟到失败" })
        eq(dialog.isOpen(), true, "CMH迟到失败不关新页")
        eq(#toasts, 1, "失败专属提示")
        local resourceResults = 0
        local identity = h.require("ui.dungeon.DungeonRewards").newSweepIdentity()
        h.modules["ui.dungeon.DungeonPage"].onActionResult = function(result)
            resourceResults = resourceResults + 1
            identity.consume(result)
        end
        click(540, 1700)
        local throwId = id
        popup.show = function() error("模拟show异常") end
        cmh.handleActionResult({ action = protocol.ACTION_TYPES.DUNGEON_SWEEP, dungeonId = "gold_mine",
            success = true, sweepRequestId = throwId, gold = 1 })
        eq(dialog.isOpen(), false, "已到账show异常仍释放所属等待")
        eq(resourceResults, 1, "show异常仍通知资源匹配释放")
        eq(toasts[#toasts], "扫荡奖励已到账，展示失败", "异常明确已到账不诱导业务重试")
        local params = { dungeonId = "gold_mine", teamIdx = 2, floor = 3 }
        identity.send(params, function() return true end)
        h.modules["core.UiToast"].show = function()
            eq(identity.isPending(), false, "toast前资源所属身份已释放")
            error("模拟toast异常")
        end
        local feedbackOk = pcall(cmh.handleActionResult, { action = protocol.ACTION_TYPES.DUNGEON_SWEEP,
            dungeonId = params.dungeonId, teamIdx = params.teamIdx, success = true,
            sweepRequestId = params.sweepRequestId, gold = 1 })
        eq(feedbackOk, false, "故障toast真实抛出不伪称成功")
        eq(identity.isPending(), false, "show与toast双异常仍释放资源身份")
        local fresh = { dungeonId = "gold_mine", teamIdx = 2, floor = 3 }
        identity.send(fresh, function() return true end)
        h.modules["core.UiToast"].show = function(text) toasts[#toasts + 1] = text end
        cmh.handleActionResult({ action = protocol.ACTION_TYPES.DUNGEON_SWEEP,
            dungeonId = params.dungeonId, teamIdx = params.teamIdx, success = true,
            sweepRequestId = params.sweepRequestId, gold = 1 })
        eq(identity.isPending(), true, "迟到show异常不清新资源请求")
        identity.clear()
        dialog.open(1, 905); click(540, 1700)
        local prepareId = id
        local prepare = cmh.prepareSweepPresentation
        cmh.prepareSweepPresentation = function() error("模拟prepare异常") end
        cmh.handleActionResult({ action = protocol.ACTION_TYPES.SWEEP, success = true, sweepRequestId = prepareId })
        eq(dialog.isOpen(), false, "已到账prepare异常释放等待")
        dialog.open(1, 905)
        cmh.handleActionResult({ action = protocol.ACTION_TYPES.SWEEP, success = true, sweepRequestId = prepareId })
        eq(dialog.isOpen(), true, "迟到prepare异常不关新页")
        cmh.prepareSweepPresentation = prepare
        eq(#shown, 1, "展示异常不重试show或重复奖励")
        eq(h.rngCalls, 0, "展示不消费随机")
        eq(h.persists, 0, "展示不再次保存")
    end)
    run("资源旧入口身份失败恢复、独立busy与关闭重开迟到隔离", function()
        local h = setup()
        local rewards = h.require("ui.dungeon.DungeonRewards")
        local identity = rewards.newSweepIdentity()
        local sent = {}
        local function send(params) sent[#sent + 1] = F.copy(params); return true end
        local function request() return { dungeonId = "gold_mine", teamIdx = 2, floor = 3, count = 1 } end
        for _, reason in ipairs({ "缺少数据", "暂无可扫荡层", "生成失败", "busy" }) do
            local params = request()
            eq(identity.send(params, send), true, "资源请求受理")
            eq(identity.isPending(), true, "资源进入pending")
            local unrelated = request()
            eq(identity.send(unrelated, send), false, "独立busy不覆盖在途身份")
            eq(unrelated.sweepRequestId, nil, "busy不伪造新身份")
            eq(identity.consume({ dungeonId = "gold_mine", sweepRequestId = params.sweepRequestId,
                success = false, reason = reason }), true, "匹配失败立即清pending " .. reason)
            eq(identity.isPending(), false, "失败恢复不用等超时")
        end
        local old, fresh = request(), request()
        identity.send(old, send); identity.clear(); identity.send(fresh, send)
        eq(fresh.sweepRequestId ~= old.sweepRequestId, true, "资源重开新身份")
        for _, wrong in ipairs({ { dungeonId = "gold_mine", sweepRequestId = old.sweepRequestId },
            { dungeonId = "equipment_vault", sweepRequestId = fresh.sweepRequestId },
            { dungeonId = "gold_mine", sweepRequestId = fresh.sweepRequestId, teamIdx = 1 },
            { dungeonId = "gold_mine", sweepRequestId = fresh.sweepRequestId, sweepFloor = 2 },
            { dungeonId = "gold_mine" } }) do
            eq(identity.consume(wrong), false, "旧id/旁路/错误归属不消费")
            eq(identity.isPending(), true, "新pending保持")
        end
        eq(identity.consume({ dungeonId = "gold_mine", sweepRequestId = fresh.sweepRequestId,
            teamIdx = 2, sweepFloor = 3, success = true }), true, "匹配成功消费")
        eq(identity.isPending(), false, "成功释放")
        eq(identity.send(request(), function() return false end), false, "发送拒绝恢复")
        eq(identity.isPending(), false, "拒绝无挂起")
        eq(identity.send(request(), function() error("模拟发送异常") end), false, "发送异常恢复")
        eq(identity.isPending(), false, "异常无挂起")
        -- 本轮只搬独立展示helper；原时长/缺副本预览语义保持。
        eq(rewards.formatIdleDuration(3661), "1:01", "展示helper小时语义")
        eq(rewards.formatIdleDuration(59), "0分", "展示helper分钟语义")
        eq(select(1, rewards.idleClaimPreview("gold_mine", {})), 0, "缺副本预览0")
    end)
    run("真实DungeonPage资源回执清pending不关重开新页", function()
        local h = setup()
        local nav, calls = 5, {}
        h.modules["ui.hud.BottomNav"] = { getSelectedIndex = function() return nav end,
            setSelectedIndex = function(index) nav = index end }
        h.modules["core.DrawUtil"].hitTest = function(x, y, cx, cy, w, height)
            return math.abs(x - cx) <= w / 2 and math.abs(y - cy) <= height / 2
        end
        h.env.nvgCreateImage = function() return 1 end
        h.modules["runtime.GameAction"] = { sendAction = function(_, params) calls[#calls + 1] = F.copy(params); return true end }
        -- 仅测试副本注入旧详情状态；生产没有新增调试API，原handleInput/onActionResult完整执行。
        local f = assert(cache:GetFile("ui/dungeon/DungeonPage.lua"))
        local lines = {}; while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end; f:Dispose()
        local source = table.concat(lines, "\n")
        local seam = [[
function DungeonPage.testLegacyOpen()
    detailOpen, detailDungeon, detailTeamIdx = true, { id = "gold_mine" }, 2
    currentFloor, dailyUsed, dailyMax = 4, 0, 2
end
function DungeonPage.testResourcePending() return resourceSweep.isPending(), pendingSweep end
return DungeonPage]]
        source = source:gsub("return DungeonPage%s*$", function() return seam end)
        local page = assert(load(source, "@sweep-test/DungeonPage", "t", h.env))()
        page.init({}); page.testLegacyOpen(); page.handleInput(330, 1633)
        eq(#calls, 1, "真实旧按钮发送一次")
        local first = calls[1]
        eq(type(first.sweepRequestId), "string", "真实旧入口带id")
        page.onActionResult({ action = h.require("shared.Protocol").ACTION_TYPES.DUNGEON_SWEEP,
            dungeonId = "gold_mine", sweepRequestId = first.sweepRequestId, success = false })
        eq(select(1, page.testResourcePending()), false, "真实失败立即释放identity")
        eq(select(2, page.testResourcePending()), false, "真实失败立即释放pendingSweep")
        page.handleInput(330, 1633)
        eq(#calls, 2, "失败可再次提交")
        local old = calls[2]
        page.close(); page.testLegacyOpen(); page.handleInput(330, 1633)
        local fresh = calls[3]
        page.onActionResult({ action = h.require("shared.Protocol").ACTION_TYPES.DUNGEON_SWEEP,
            dungeonId = "gold_mine", sweepRequestId = old.sweepRequestId, success = true })
        eq(nav, 5, "迟到成功不关新页面")
        eq(select(2, page.testResourcePending()), true, "迟到不清新pending")
        page.onActionResult({ action = h.require("shared.Protocol").ACTION_TYPES.DUNGEON_SWEEP,
            dungeonId = "gold_mine", sweepRequestId = fresh.sweepRequestId, success = true })
        eq(nav, 3, "匹配成功离开原资源页")
        eq(select(2, page.testResourcePending()), false, "匹配清pending")
    end)
    run("真实Noto五语等待/失败字墨与百万杀计数不越框", function()
        local h = setup()
        local dictionary = h.require("core.I18nDictExtra")
        local vg = assert(nvgCreate(1))
        local ok, err = pcall(function()
            eq(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, true, "真实宿主Noto字体")
            nvgBeginFrame(vg, 1920, 1080, 1)
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            for _, lang in ipairs({ "zh", "zh_TW", "en", "ja", "ko" }) do
                local function tr(text) return lang == "zh" and text or assert(dictionary[lang][text], lang .. text) end
                local texts = { tr("处理中"), tr("整理奖励"), tr("正在结算"), tr("扫荡失败，请重试"),
                    tr("扫荡请求未受理，请重试"), tr("扫荡处理中，请稍候"),
                    string.format(tr("%s · %d / %d"), tr("生成奖励"), 100000, 100000),
                    string.format(tr("%s · %d / %d"), tr("生成奖励"), 9999999, 10000000) }
                for _, sizeWidth in ipairs({ { 22, 860 }, { 30, 750 } }) do
                    nvgFontSize(vg, sizeWidth[1])
                    for _, text in ipairs(texts) do
                        local bounds = {}
                        local advance = nvgTextBounds(vg, 0, 0, text, bounds)
                        eq(advance > 0, true, "真实文字非空 " .. lang)
                        eq(bounds[3] - bounds[1] <= sizeWidth[2], true, "真实字墨内宽 " .. lang .. " " .. text)
                        eq(advance <= sizeWidth[2], true, "真实advance内宽 " .. lang)
                    end
                end
            end
            nvgEndFrame(vg)
        end)
        nvgDelete(vg)
        if not ok then error(err) end
    end)
    print(string.format("[sweep_dialog_preview_test] SUMMARY cases=%d failures=%d assertions=%d",
        cases, #failures, assertions))
    for _, failure in ipairs(failures) do log:Write(LOG_ERROR, "[sweep_dialog_preview_test] " .. failure) end
    engine:Exit()
end
