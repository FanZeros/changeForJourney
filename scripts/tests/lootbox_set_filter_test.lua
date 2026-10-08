
-- 套装筛选回归：遗匣页弹窗交互 + 批量领取/回收按套装过滤 + 无套装分类。
-- 模板归属（EquipmentSetConfig 名字规则）：W5「叠甲战神之剑」→ carapace；W1「练习用剑」→ 无套装。
local assertions = 0
local function check(condition, message)
    assertions = assertions + 1
    assert(condition, message)
end
local function eq(actual, expected, message)
    check(actual == expected, message .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

local restorers = {}
local function replace(target, key, value)
    local original = target[key]
    restorers[#restorers + 1] = function()
        target[key] = original
        eq(target[key], original, "恢复替换 " .. key)
    end
    target[key] = value
end
local closePage = function() end

-- 弹窗说明独立回归：真实套装表/KeywordText，绘制桩只隔离引擎上下文。
local function runDialogExplanationTests()
    local Dialog = require("ui.widget.SetFilterDialog")
    local ESC = require("config.EquipmentSetConfig")
    local selected, changed, done = {}, 0, 0
    local function open()
        Dialog.open(selected, {
            onChange = function() changed = changed + 1 end,
            onDone = function() done = done + 1 end,
        })
    end
    open()
    eq(Dialog.getExplanation(), nil, "打开不带旧说明")
    for index, key in ipairs(ESC.orderedSetIds()) do
        check(Dialog.handleHover(164, 610 + (index - 1) * 88), "弹窗 hover 模态消费 " .. key)
        local tip = Dialog.getExplanation()
        check(tip and tip.key == key and not tip.pinned, "徽记 hover 命中 " .. key)
        eq(#tip.effects, 3, "说明包含全部三个档位 " .. key)
        for tierIndex, pieces in ipairs({ 2, 4, 6 }) do
            eq(tip.effects[tierIndex].pieces, pieces, "档位顺序 " .. key)
            eq(tip.effects[tierIndex].desc, ESC.get(key)["desc" .. pieces], "完整未截断描述 " .. key)
        end
    end
    Dialog.handleHover(-1, -1)
    eq(Dialog.getExplanation(), nil, "移出左栏清 hover")
    eq(changed, 0, "hover 不触发筛选变化")
    eq(next(selected), nil, "hover 不写筛选表")

    Dialog.handleInput(164, 610)
    check(Dialog.getExplanation().pinned, "图标点击钉住说明")
    Dialog.handleHover(-1, -1)
    eq(Dialog.getExplanation().key, "carapace", "离开图标保留钉住说明")
    Dialog.handleHover(164, 698)
    eq(Dialog.getExplanation().key, "faceless", "其他图标 hover 临时预览")
    Dialog.handleHover(-1, -1)
    eq(Dialog.getExplanation().key, "carapace", "离开临时预览恢复钉住说明")
    Dialog.handleInput(164, 610)
    eq(Dialog.getExplanation(), nil, "再点同图标取消钉住")
    Dialog.handleInput(164, 698)
    Dialog.handleInput(164, 610)
    eq(Dialog.getExplanation().key, "carapace", "点击不同图标切换钉住")
    eq(next(selected), nil, "所有图标点击都不意外勾选")
    eq(changed, 0, "所有图标点击都不触发 onChange")

    Dialog.handleInput(220, 610)
    eq(selected.carapace, true, "名称行仍切换筛选")
    eq(changed, 1, "名称行只回调一次")
    eq(Dialog.getExplanation(), nil, "名称行筛选清旧说明")
    Dialog.handleInput(938, 610)
    eq(selected.carapace, nil, "勾选框仍切换筛选")
    eq(changed, 2, "勾选框只回调一次")
    Dialog.handleHover(164, 1666)
    local none = Dialog.getExplanation()
    eq(none.key, "none", "无套装图标也有说明")
    eq(#none.effects, 0, "无套装不伪造三个档位")
    check(none.note and none.note:find("不提供2/4/6件", 1, true), "无套装解释不产生套装效果")
    Dialog.handleInput(164, 1666)
    eq(next(selected), nil, "无套装图标点击不勾选")
    Dialog.handleInput(540, 1666)
    eq(selected.none, true, "无套装名称行仍勾选")
    Dialog.handleInput(164, 610)
    Dialog.handleInput(330, 1836)
    eq(next(selected), nil, "清空按钮仍清筛选")
    eq(Dialog.getExplanation(), nil, "清空按钮清旧说明")
    Dialog.handleInput(164, 610)
    Dialog.close()
    eq(Dialog.getExplanation(), nil, "close 清 hover/钉住")
    eq(Dialog.handleHover(164, 610), false, "关闭后 hover 不消费")
    eq(Dialog.handleInput(164, 610), false, "关闭后点击不消费")
    open()
    Dialog.handleInput(164, 610)
    open()
    eq(Dialog.getExplanation(), nil, "连续 open 清旧钉住")
    Dialog.handleHover(164, 610)
    open()
    eq(Dialog.getExplanation(), nil, "连续 open 清旧 hover")
    Dialog.handleInput(164, 610)
    Dialog.handleInput(750, 1836)
    eq(done, 1, "完成按钮只回调一次")
    eq(Dialog.getExplanation(), nil, "完成按钮清旧说明")
    open()
    Dialog.handleInput(164, 610)
    Dialog.handleInput(10, 10)
    eq(done, 2, "面板外点击按原契约完成关闭")
    eq(Dialog.getExplanation(), nil, "面板外关闭清说明")

    -- 同步捕获整卡几何与 KeywordText 实际绘制片段，不能只验证数据 getter。
    local calls, rects, stack = {}, {}, {}
    local state = { x = 0, y = 0, scale = 1, font = 30 }
    local function noop() end
    for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgCircle", "nvgFillColor", "nvgFill",
        "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFontFace", "nvgTextAlign",
        "nvgTextLetterSpacing", "nvgIntersectScissor" }) do replace(_G, name, noop) end
    replace(_G, "nvgRGBA", function() return nil end)
    replace(_G, "nvgCreateImage", function() return -1 end)
    replace(_G, "nvgFontSize", function(_, font) state.font = font end)
    replace(_G, "nvgSave", function()
        stack[#stack + 1] = { x = state.x, y = state.y, scale = state.scale, font = state.font }
    end)
    replace(_G, "nvgRestore", function() state = table.remove(stack) end)
    replace(_G, "nvgTranslate", function(_, x, y)
        state.x, state.y = state.x + x * state.scale, state.y + y * state.scale
    end)
    replace(_G, "nvgScale", function(_, x, y)
        eq(x, y, "说明整卡等比缩放")
        state.scale = state.scale * x
    end)
    replace(_G, "nvgCurrentTransform", function(_, matrix)
        matrix[1], matrix[2], matrix[3], matrix[4] = state.scale, 0, 0, state.scale
        matrix[5], matrix[6] = state.x, state.y
    end)
    replace(_G, "nvgRoundedRect", function(_, x, y, w, h)
        if state.x ~= 0 or state.y ~= 0 then
            rects[#rects + 1] = { x = state.x + x * state.scale, y = state.y + y * state.scale,
                w = w * state.scale, h = h * state.scale }
        end
    end)
    local function width(text, font)
        local result = 0
        for _, code in utf8.codes(text) do result = result + (code > 127 and font or font * 0.55) end
        return result
    end
    local function bounds(_, _, _, text, out)
        local w = width(text, state.font)
        if out then out[1], out[2], out[3], out[4] = 0, 0, w, state.font end
        return w
    end
    replace(_G, "nvgTextBounds", bounds)
    local I18n = require("core.I18n")
    local lang = I18n.get()
    restorers[#restorers + 1] = function() I18n.set(lang) end
    I18n.set("zh_CN")
    replace(I18n, "displayBounds", bounds)
    replace(I18n, "displayText", function(_, x, y, text)
        calls[#calls + 1] = { text = text, x = state.x + x * state.scale,
            y = state.y + y * state.scale, w = width(text, state.font) * state.scale,
            h = state.font * state.scale }
    end)
    replace(require("core.DrawUtil"), "drawImageCentered", noop)
    replace(require("core.DarkIcon"), "drawNine", noop)
    replace(require("ui.widget.EquipmentSetIcon"), "draw", function() return false end)
    replace(require("systems.ButtonFeedback"), "begin", noop)
    replace(require("systems.ButtonFeedback"), "finish", noop)
    replace(_G, "nvgText", noop)
    local vg = {}
    local function draw()
        calls, rects = {}, {}
        Dialog.draw(vg)
        eq(#stack, 0, "绘制恢复 NanoVG 状态栈")
        eq(#rects, 1, "说明只绘制一张最上层浮卡")
        local rect = rects[1]
        check(rect.x >= 24 and rect.y >= 24 and rect.x + rect.w <= 1056.01
            and rect.y + rect.h <= 2376.01, "说明卡不溢出左栏屏幕边界")
        local full = {}
        for _, call in ipairs(calls) do
            full[#full + 1] = call.text
            check(call.x >= rect.x and call.y >= rect.y
                and call.x + call.w <= rect.x + rect.w + 0.01
                and call.y + call.h <= rect.y + rect.h + 0.01, "每个描述片段都在卡内且未裁断")
        end
        return table.concat(full), rect
    end
    open()
    for index, key in ipairs(ESC.orderedSetIds()) do
        Dialog.handleHover(164, 610 + (index - 1) * 88)
        local full = draw()
        for _, pieces in ipairs({ 2, 4, 6 }) do
            check(full:find(ESC.get(key)["desc" .. pieces], 1, true), "实际绘制完整描述 " .. key .. pieces)
        end
    end
    Dialog.handleHover(164, 1666)
    local full = draw()
    check(full:find(Dialog.getExplanation().note, 1, true), "实际绘制无套装完整说明")

    -- 超长多行正文触发整卡缩放，最后一句必须仍被绘制，不能以 maxH 截断。
    local long = string.rep("能量护盾加成+8%，完整效果逐行保留。\n", 80) .. "这是六件效果末尾。"
    replace(ESC.get("carapace"), "desc6", long)
    Dialog.handleInput(164, 610)
    local longText, rect = draw()
    check(rect.h <= 2352.01, "超长说明整卡缩放到安全高度")
    check(longText:find(long:gsub("\n", ""), 1, true), "超长说明完整绘制到最后一句")
    local beforeChange = changed
    Dialog.handleHover(rect.x + 12, rect.y + 12)
    Dialog.handleInput(rect.x + 12, rect.y + 12)
    eq(changed, beforeChange, "说明卡点击不穿透勾选")
    check(Dialog.getExplanation().pinned, "说明卡 hover/点击保留钉住")
    Dialog.close()
    open()
    eq(Dialog.getExplanation(), nil, "重开不保留浮卡几何")
    Dialog.handleInput(220, 610)
    eq(changed, beforeChange + 1, "重开后旧浮卡位置不阻塞筛选")
    Dialog.close()
end

local function runTests()
    replace(_G, "time", { elapsedTime = 10 })
    -- 托管 require 忽略 package.loaded 预注入；替换真实方法并验证页面实际命中。
    local Detail = require("ui.character.equip.EquipmentDetail")
    local originalPower = Detail.calcEquipPower
    local powerCalls, sfxCalls, feedbackCalls = 0, 0, 0
    replace(Detail, "calcEquipPower", function(equip, heroId)
        powerCalls = powerCalls + 1
        return originalPower(equip, heroId)
    end)
    replace(require("systems.GameSFX"), "playUIMove", function() sfxCalls = sfxCalls + 1 end)
    replace(require("systems.ButtonFeedback"), "trigger", function() feedbackCalls = feedbackCalls + 1 end)

    -- 模板归属自检（名字规则变动时本测试第一时间报警）
    local ESC = require("config.EquipmentSetConfig")
    local ECfg = require("config.EquipmentConfig")
    eq(ESC.getSetIdForTemplate(ECfg.ITEMS["W5"]), "carapace", "W5 归属叠甲虫壳")
    eq(ESC.getSetIdForTemplate(ECfg.ITEMS["W1"]), nil, "W1 无套装归属")
    eq(#ESC.orderedSetIds(), 12, "套装固定顺序共 12 套")

    local Page = require("ui.loot.LootBoxPage")
    local Dialog = require("ui.widget.SetFilterDialog")
    local originalOpen = Dialog.open
    closePage = function()
        Page.forceClose()
        Page.setOnClaimOne(nil)
        Page.setOnClaimAll(nil)
        Page.setOnDecomposeOne(nil)
        Page.setOnDecomposeAll(nil)
    end
    ---@type (fun(): table<string, integer>)|nil
    local countGetter = nil
    replace(Dialog, "open", function(sel, opts)
        countGetter = opts and opts.getCounts or nil
        originalOpen(sel, opts)
    end)
    local claimed = {}
    ---@type table<number, boolean>
    local claimQuality = {}
    ---@type table<string, boolean>
    local claimSetFilter = {}
    local allClaims = 0
    Page.setOnClaimOne(function(index) claimed[#claimed + 1] = index end)
    Page.setOnClaimAll(function(quality, setFilter)
        allClaims = allClaims + 1
        claimQuality = quality
        claimSetFilter = setFilter
    end)
    Page.setOnDecomposeOne(function() end)
    Page.setOnDecomposeAll(function() end)

    local entries = {
        { quality = 5, level = 70, count = 1, sourceIndex = 1,
          equip = { templateId = "W5", name = "叠甲战神之剑", quality = 5, level = 70, baseStats = {} } },
        { quality = 5, level = 70, count = 1, sourceIndex = 2,
          equip = { templateId = "W5", name = "叠甲战神之剑", quality = 5, level = 70, baseStats = {} } },
        { quality = 1, level = 10, count = 1, sourceIndex = 3,
          equip = { templateId = "W1", name = "练习用剑", quality = 1, level = 10, baseStats = {} } },
        { quality = 6, level = 80, count = 2 }, -- 待整理（无 equip）
    }
    for index = 1, 3 do
        eq(originalPower(entries[index].equip, nil), 0, "套装 fixture 无基础属性保持同战力 " .. index)
    end
    Page.open(entries)
    eq(powerCalls, 3, "Page.open 实际命中战力包装且忽略待整理")
    eq(sfxCalls, 1, "Page.open 实际命中音效替身")
    time.elapsedTime = 11

    -- 1) 打开套装筛选弹窗（入口按钮 cx=190 cy=286）
    Page.handleInput(190, 286)
    eq(Dialog.isOpen(), true, "点击套装按钮打开弹窗")
    eq(Dialog.countSelected(nil), 0, "初始未勾选")
    check(countGetter, "遗匣必须接入套装数量 getter")
    local counts = countGetter()
    eq(counts.carapace, 2, "套装数量按两个已确定装备实例计数")
    eq(counts.none, 1, "待整理数量不计入无套装")
    eq(counts.faceless, 0, "无匹配套装也显式返回零")

    -- 2) 弹窗模态：打开时列表点击被消费，不触发领取
    local before = #claimed
    Page.handleInput(20, 772) -- 列表左侧、弹窗外侧，不会误选套装第3行
    eq(#claimed, before, "弹窗打开时点击列表不领取")
    eq(Dialog.isOpen(), false, "弹窗外点击按完成语义关闭且不穿透")
    Page.handleInput(190, 286)

    -- 3) 勾选叠甲虫壳（行1，cy=610）→ onChange 实时重建列表
    Page.handleInput(540, 610)
    eq(Dialog.countSelected(nil), 1, "勾选一套")
    eq(countGetter().none, 1, "勾选套装后其他行数量不被套装筛选清零")
    -- 弹窗关闭后列表只剩 carapace 两条
    Page.handleInput(750, 1836) -- 完成
    eq(Dialog.isOpen(), false, "完成关闭弹窗")
    Page.handleInput(873, 772)
    eq(claimed[#claimed], 1, "筛选后首行是原索引1（carapace）")
    Page.handleInput(873, 1014)
    eq(claimed[#claimed], 2, "筛选后第二行是原索引2（carapace）")

    -- 4) 批量领取透传套装集合
    Page.handleInput(320, 2210)
    eq(allClaims, 1, "领取勾选接线")
    eq(type(claimSetFilter), "table", "批量领取带套装集合")
    eq(claimSetFilter["carapace"], true, "套装集合包含 carapace")
    eq(next(claimQuality), nil, "品质集合为空=不限品质")

    -- 5) 追加勾选「无套装」（行13，cy=566+12*88+44=1666）
    Page.handleInput(190, 286)
    Page.handleInput(540, 1666)
    eq(Dialog.countSelected(nil), 2, "追加勾选无套装")
    Page.handleInput(330, 1836) -- 清空
    eq(Dialog.countSelected(nil), 0, "清空全部勾选")
    Page.handleInput(540, 1666) -- 只勾无套装
    Page.handleInput(750, 1836)
    Page.handleInput(873, 772)
    eq(claimed[#claimed], 3, "无套装筛选命中 W1（原索引3）")

    -- 6) 系统层：claimAll/decomposeAll 按套装过滤
    local System = require("systems.LootBoxSystem")
    local box = { seeds = {
        { quality = 5, level = 70, count = 1,
          equip = { templateId = "W5", quality = 5, level = 70, baseStats = {} } },
        { quality = 1, level = 10, count = 1,
          equip = { templateId = "W1", quality = 1, level = 10, baseStats = {} } },
        { quality = 6, level = 80, count = 2 }, -- 待整理
    } }
    local bag = { inventory = {}, equipped = {}, nextSeq = 1 }
    local got = System.claimAll(box, bag, nil, { carapace = true })
    eq(#got, 1, "claimAll 套装过滤只领 carapace")
    eq(got[1].templateId, "W5", "领取的是 W5")
    eq(#box.seeds, 2, "剩余 W1 + 待整理")

    local box2 = { seeds = {
        { quality = 5, level = 70, count = 1,
          equip = { templateId = "W5", quality = 5, level = 70, baseStats = {} } },
        { quality = 1, level = 10, count = 1,
          equip = { templateId = "W1", quality = 1, level = 10, baseStats = {} } },
    } }
    local _, pieces = System.decomposeAll(box2, nil, { none = true })
    eq(pieces, 1, "decomposeAll 无套装过滤只回收 W1")
    eq(box2.seeds[1].equip.templateId, "W5", "carapace 保留")

    -- 品质+套装组合：q5 AND carapace → 命中；q1 AND carapace → 空
    local box3 = { seeds = {
        { quality = 5, level = 70, count = 1,
          equip = { templateId = "W5", quality = 5, level = 70, baseStats = {} } },
        { quality = 1, level = 10, count = 1,
          equip = { templateId = "W1", quality = 1, level = 10, baseStats = {} } },
    } }
    local _, p2 = System.decomposeAll(box3, { [1] = true }, { carapace = true })
    eq(p2, 0, "品质与套装 AND 组合无交集时不回收")
    local _, p3 = System.decomposeAll(box3, { [5] = true }, { carapace = true })
    eq(p3, 1, "品质与套装 AND 组合命中回收")

    -- 7) 旧调用兼容：不传 setFilter 等同不限制
    local box4 = { seeds = {
        { quality = 5, level = 70, count = 1,
          equip = { templateId = "W5", quality = 5, level = 70, baseStats = {} } },
        { quality = 1, level = 10, count = 1,
          equip = { templateId = "W1", quality = 1, level = 10, baseStats = {} } },
    } }
    local _, p4 = System.decomposeAll(box4, 0)
    eq(p4, 2, "旧签名（无套装参数）全部回收")

    -- 8) 重新打开页面重置套装筛选
    Page.open(entries)
    time.elapsedTime = 12
    Page.handleInput(320, 2210)
    eq(allClaims, 2, "重开后一键领取可用")
    eq(next(claimSetFilter), nil, "重开后套装筛选已重置")

    -- 9) 数量跟随品质与最新来源刷新，不重开弹窗，也不生成待整理装备。
    Page.handleInput(565 + 4 * 82, 286) -- 仅品质5
    Page.handleInput(190, 286)
    check(countGetter, "重开套装弹窗必须重新绑定数量")
    counts = countGetter()
    eq(counts.carapace, 2, "品质5保留两件叠甲虫壳")
    eq(counts.none, 0, "品质5排除品质1无套装")
    Page.refresh({ entries[1], entries[3], entries[4] })
    counts = countGetter()
    eq(counts.carapace, 1, "弹窗打开期间来源刷新立即减少套装数量")
    eq(counts.none, 0, "来源刷新保留当前品质筛选")
    eq(entries[4].equip, nil, "计数不会生成或迁移待整理条目")
    Page.handleInput(750, 1836)
    Page.handleInput(565 + 4 * 82, 286) -- 清掉品质5恢复全部
    Page.handleInput(190, 286)
    eq(countGetter().none, 1, "取消品质后无套装数量恢复")
    Page.handleInput(750, 1836)
    -- 数量忽略当前套装选择，但严格按部位+类型+品质AND，不借英雄双持。
    local offhandId = ""
    for id, tpl in pairs(ECfg.ITEMS) do
        if tpl.slot == "offhand" and ESC.getSetIdForTemplate(tpl) == "carapace" then offhandId = id break end
    end
    check(offhandId ~= "", "找到叠甲副手计数夹具")
    local more = { entries[1], entries[2], entries[3], entries[4],
        { equip = { templateId = offhandId, quality = 5, level = 1 } } }
    Page.refresh(more)
    Page.handleInput(295, 434)
    Page.handleInput(295, 576) -- 部位主手（all之后第一项）
    Page.handleInput(765, 434)
    -- 类型选项来自模板并排序，查真实通用bar选项来点击，不写页面状态。
    local typeOptions = require("ui.backpack.BackpackFilters").bind({
        filters = {}, GRID = { FIRST_ROW_TOP = 660, CLIP_BOTTOM = 2120 },
        getSlot = function() return "weapon" end,
        setSlot = function() end, onChange = function() end,
    }).getOptions("type")
    local typeRow = 0
    for index, option in ipairs(typeOptions) do if option.value == ECfg.ITEMS.W5.type then typeRow = index end end
    check(typeRow >= 1 and typeRow <= 8, "叠甲剑类型选项可见")
    Page.handleInput(765, 483 + (typeRow - 0.5) * 62)
    Page.handleInput(893, 286) -- 品质5
    Page.handleInput(190, 286)
    counts = countGetter()
    eq(counts.carapace, 2, "主手类型品质过滤计数排除叠甲副手")
    eq(counts.none, 0, "品质5排除普通无套装")
    Page.handleInput(540, 1666) -- 当前选无套装，列表空，但套装计数仍忽略当前setFilter
    eq(countGetter().carapace, 2, "当前无套装过滤不清零其他套装数量")
    Page.handleInput(750, 1836)
    Page.handleInput(940, 524)

    check(feedbackCalls > 0, "页面及套装弹窗实际命中反馈替身")
    Page.forceClose()
    runDialogExplanationTests()
end

function Start()
    local ok, err = pcall(runTests)
    local cleanupErrors = {}
    local closed, closeErr = pcall(closePage)
    if not closed then cleanupErrors[#cleanupErrors + 1] = tostring(closeErr) end
    for index = #restorers, 1, -1 do
        local restored, restoreErr = pcall(restorers[index])
        if not restored then cleanupErrors[#cleanupErrors + 1] = tostring(restoreErr) end
    end
    if not ok then
        log:Write(LOG_ERROR, "[lootbox_set_filter_test] [FAIL] " .. tostring(err))
    end
    if #cleanupErrors > 0 then
        log:Write(LOG_ERROR, "[lootbox_set_filter_test] [FAIL] cleanup: " .. table.concat(cleanupErrors, "; "))
    elseif ok then
        print("[lootbox_set_filter_test] ALL PASS assertions=" .. assertions)
    end
    engine:Exit()
end
