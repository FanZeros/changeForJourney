-- 遗匣页面与存档回归：替换外部输入/磁盘，不触碰玩家数据。
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

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local closePage = function() end
local function runTests()
    replace(_G, "time", { elapsedTime = 10 })
    replace(_G, "H_SEAM_BACK", false)
    -- 托管 require 不读取 package.loaded 预注入；替换真实模块持有的方法。
    -- calcEquipPower 始终调用真实实现，只有绘图/音效/反馈改为有命中计数的替身。
    local Detail = require("ui.character.equip.EquipmentDetail")
    local originalPower = Detail.calcEquipPower
    local powerCalls, sizeCalls, detailCalls, sfxCalls, feedbackCalls = {}, 0, {}, 0, 0
    replace(Detail, "calcEquipPower", function(equip, heroId)
        powerCalls[#powerCalls + 1] = { equip = equip, heroId = heroId }
        return originalPower(equip, heroId)
    end)
    replace(Detail, "readOnlySize", function()
        sizeCalls = sizeCalls + 1
        return 720, 440
    end)
    replace(Detail, "drawReadOnly", function(_, equip)
        detailCalls[#detailCalls + 1] = equip
    end)
    local Sfx = require("systems.GameSFX")
    replace(Sfx, "playUIMove", function() sfxCalls = sfxCalls + 1 end)
    local Feedback = require("systems.ButtonFeedback")
    replace(Feedback, "trigger", function() feedbackCalls = feedbackCalls + 1 end)
    replace(Feedback, "begin", function() return false end)
    replace(Feedback, "finish", function() end)

    -- Headless draw 是调用链测试，不创建 GPU/NanoVG context，也不产出伪截图。
    local drawCalls = {}
    local DrawUtil = require("core.DrawUtil")
    replace(DrawUtil, "drawTextStroke", function(_, x, y, caption)
        drawCalls[#drawCalls + 1] = { x = x, y = y, text = caption }
    end)
    replace(DrawUtil, "drawImageCentered", function() end)
    local Chrome = require("ui.town.TownPageChrome")
    replace(Chrome, "drawNamePlate", function() end)
    replace(Chrome, "drawBack", function() end)
    local Icons = require("core.DarkIcon")
    for _, method in ipairs({ "drawNine", "drawQualityBg", "drawIconDark" }) do
        replace(Icons, method, function() end)
    end
    replace(require("ui.widget.ImageCache"), "getEquipIcon", function() return -1 end)
    replace(require("ui.widget.QualityMark"), "draw", function() return false end)
    replace(require("ui.widget.EquipmentSetIcon"), "drawBadge", function() end)
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgTranslate",
        "nvgGlobalAlpha", "nvgBeginPath", "nvgRect", "nvgFillColor", "nvgFill",
        "nvgFontFace", "nvgFontSize", "nvgRoundedRect", "nvgStrokeColor",
        "nvgStrokeWidth", "nvgStroke", "nvgTextAlign", "nvgText" }) do
        replace(_G, name, function() end)
    end
    replace(_G, "nvgRGBA", function() return {} end)
    replace(_G, "nvgTextBounds", function(_, _, _, caption) return #caption * 16, {0, 0, #caption * 16, 16} end)
    replace(require("core.I18n"), "displayBounds", function(_, _, _, caption) return #caption * 16 end)

    local Filters = require("ui.backpack.BackpackFilters")
    local originalBind = Filters.bind
    local filterBar = {} ---@type table
    replace(Filters, "bind", function(deps)
        filterBar = originalBind(deps)
        return filterBar
    end)
    local Page = require("ui.loot.LootBoxPage")
    closePage = function()
        Page.forceClose()
        Page.setOnClaimOne(nil)
        Page.setOnDecomposeOne(nil)
        Page.setOnClaimAll(nil)
        Page.setOnDecomposeAll(nil)
    end
    local claimed, decomposed, allClaims, allDecomposes = {}, {}, 0, 0
    Page.setOnClaimOne(function(index) claimed[#claimed + 1] = index end)
    Page.setOnDecomposeOne(function(index) decomposed[#decomposed + 1] = index end)
    ---@type table<number, boolean>
    local claimQuality = {}
    ---@type table<number, boolean>
    local recycleQuality = {}
    Page.setOnClaimAll(function(quality) allClaims = allClaims + 1 claimQuality = quality end)
    Page.setOnDecomposeAll(function(quality) allDecomposes = allDecomposes + 1 recycleQuality = quality end)
    local entries = {}
    for index = 1, 20 do
        entries[index] = {
            quality = 1, level = index, count = 1, source = "idle", sourceIndex = index,
            equip = { templateId = "W1", name = "确定装备", quality = 1, level = index, baseStats = {} },
        }
    end
    for index = 1, 20 do
        eq(originalPower(entries[index].equip, nil), 0, "旧无属性交互 fixture 保持同战力 " .. index)
    end
    Page.open(entries)
    eq(#powerCalls, 20, "open 对每件确定装备计算一次")
    eq(sfxCalls, 1, "音效替身由真实 Page.open 命中")
    Page.handleInput(873, 772)
    eq(#claimed, 0, "开场动画期间不触发领取")
    time.elapsedTime = 11
    Page.handleInput(873, 772)
    eq(claimed[1], 1, "首行领取索引")
    Page.handleScroll(-1000)
    Page.handleInput(873, 2008)
    eq(claimed[2], 20, "滚轮到底仍对应原存储索引")
    Page.handleScroll(1000)
    Page.handleDragBegin(500, 1000)
    Page.handleDragMove(500, 800)
    Page.handleDragEnd(500, 800)
    Page.handleInput(873, 874)
    eq(#claimed, 2, "拖拽结束不会误领")
    Page.handleScroll(1000)
    Page.handleInput(873, 1014)
    eq(claimed[3], 2, "拖拽后按可见位置命中第二行")
    Page.handleRightClick(873, 1014)
    eq(decomposed[1], 2, "右键回收对应原索引")
    Page.handleScroll(1000)
    Page.handleDragBegin(873, 832)
    Page.handleScroll(-2)
    Page.handleDragEnd(873, 832)
    Page.handleInput(873, 832)
    eq(#decomposed, 1, "按住后滚轮不能误分解新出现的条目")
    Page.handleDragBegin(873, 832)
    Page.refresh(entries)
    Page.handleScroll(1)
    Page.handleDragEnd(873, 832)
    Page.handleInput(873, 832)
    eq(#decomposed, 1, "数据刷新加滚轮仍保留防误点击保护")
    Page.handleInput(780, 2210)
    eq(allDecomposes, 0, "全部分解必须二次确认")
    Page.handleInput(873, 874)
    eq(#decomposed, 1, "确认框阻止点击底层条目")
    Page.handleInput(330, 1340)
    eq(allDecomposes, 0, "取消确认不分解")
    Page.handleInput(780, 2210)
    Page.handleInput(750, 1340)
    eq(allDecomposes, 1, "确认后仅分解一次")
    Page.handleInput(330, 2210)
    eq(allClaims, 1, "全部领取接线")
    Page.refresh({})
    eq(Page.isOpen(), true, "领空后保留地点空态")
    Page.handleInput(330, 2210)
    Page.handleInput(780, 2210)
    eq(allClaims, 1, "空态不能重复领取")
    eq(allDecomposes, 1, "空态不能分解")
    eq(type(claimQuality), "table", "默认领取范围为勾选集合")
    eq(next(claimQuality), nil, "默认空集合表示全部")
    eq(type(recycleQuality), "table", "默认回收范围为勾选集合")
    eq(next(recycleQuality), nil, "默认空集合表示全部")
    entries[2].quality, entries[2].equip.quality = 6, 6
    entries[9].quality, entries[9].equip.quality = 6, 6
    Page.refresh(entries)
    Page.handleInput(975, 286) -- 勾选稀有度 6 档（多选开关，右上角第6个槽位中心）
    Page.handleRightClick(873, 772)
    eq(decomposed[#decomposed], 2, "筛选后的首行回收仍指向原索引2")
    Page.handleInput(873, 1014)
    eq(claimed[#claimed], 9, "筛选后的第二行领取仍指向原索引9")
    Page.handleInput(330, 2210)
    eq(type(claimQuality), "table", "一键领取透传勾选集合")
    eq(claimQuality[6], true, "勾选集合包含稀有度6")
    Page.handleInput(780, 2210)
    Page.handleInput(750, 1340)
    eq(type(recycleQuality), "table", "一键回收透传勾选集合")
    eq(recycleQuality[6], true, "回收集合包含稀有度6")
    Page.refresh(entries)
    Page.handleInput(873, 772)
    eq(claimed[#claimed], 2, "刷新保持当前勾选筛选")
    Page.handleInput(565, 286) -- 追加勾选 1 档，形成多档混合
    Page.handleInput(330, 2210)
    eq(claimQuality[1], true, "多档集合包含稀有度1")
    eq(claimQuality[6], true, "多档集合保留稀有度6")
    Page.handleInput(975, 286) -- 取消 6 档
    Page.handleInput(565, 286) -- 取消 1 档
    Page.handleInput(729, 286) -- 勾选无装备的 3 档：列表空、批量按钮禁用
    local beforeEmptyFilter = allClaims
    Page.handleInput(330, 2210)
    eq(allClaims, beforeEmptyFilter, "空筛选不领取")
    Page.handleInput(729, 286) -- 取消勾选回到全部
    Page.handleInput(330, 2210)
    eq(allClaims, beforeEmptyFilter + 1, "取消全部勾选后恢复一键领取全部")
    eq(next(claimQuality), nil, "空集合表示不按稀有度限制")
    Page.close()
    time.elapsedTime = 12
    Page.update(1)
    eq(Page.isOpen(), false, "关闭动画可由更新完成")
    Page.open({})
    time.elapsedTime = 13
    H_SEAM_BACK = false
    Page.handleInput(958, 2308)
    time.elapsedTime = 14
    Page.update(1)
    eq(Page.isOpen(), false, "非三行页内返回")

    local pending = { quality = 6, level = 80, count = 3 }
    local determined = {
        quality = 6, level = 20, count = 1, sourceIndex = 17,
        equip = { templateId = "W1", quality = 6, level = 20 },
    }
    Page.open({ pending, determined })
    time.elapsedTime = 15
    local beforePending = #claimed
    Page.handleInput(873, 1014) -- 待整理排序在确定装备之后（第二行）。
    eq(#claimed, beforePending, "待整理条目不可领取")
    Page.handleInput(975, 286) -- 勾选稀有度 6 档
    Page.handleInput(873, 772)
    eq(claimed[#claimed], 17, "筛选保留摘要携带的原存储索引")
    Page.handleInput(180, 772)
    eq(Page.isDetailOpen(), true, "点击装备卡片显示只读详情")
    Page.handleInput(400, 700)
    eq(Page.isDetailOpen(), false, "点击详情关闭预览")
    Page.showToast("消息甲")
    Page.showToast("消息乙")
    Page.handleInput(873, 772)
    eq(claimed[#claimed], 17, "消息队列不拦截领取按钮")
    Page.handleScroll(-1)
    Page.handleHover(180, 772)
    time.elapsedTime = 15.6
    Page.handleHover(180, 772)
    Page.handleInput(780, 2210)
    local beforeRefresh = allDecomposes
    Page.refresh({ pending, determined })
    Page.handleInput(750, 1340)
    eq(allDecomposes, beforeRefresh, "刷新后旧确认不能执行回收")
    Page.forceClose()

    -- 数值战力排序：真实物攻价值 0.5，直接用 baseStats 构造，品质/等级不代表战力。
    local NumberUtil = require("core.NumberUtil")
    local function equipment(name, power, quality, sourceIndex)
        return {
            quality = quality, level = 1, count = 1, sourceIndex = sourceIndex,
            equip = { templateId = "W1", name = name, quality = quality, level = 1,
                baseStats = { { "physAtk", power * 2 } } },
        }
    end
    local low = equipment("低战力高品质", 9999, 6, 71)
    local tieA = equipment("同战力先来源", 10040, 1, 90)
    local million = equipment("百万低品质", 1000000, 1, 4)
    local tieB = equipment("同战力后来源", 10040, 6, 3)
    local high = equipment("同短单位较高", 10041, 6, nil)
    local pendingA = { quality = 6, level = 99, count = 3 }
    local pendingB = { quality = 1, level = 99, count = 2 }
    local source = { pendingA, low, tieA, million, pendingB, tieB, high }
    for _, fixture in ipairs({ low, tieA, million, tieB, high }) do
        eq(originalPower(fixture.equip, nil), fixture.equip.baseStats[1][2] * 0.5,
            "真实 calcEquipPower fixture 自检 " .. fixture.equip.name)
    end
    eq(NumberUtil.format(9999), "9999", "未缩写的低战力")
    eq(NumberUtil.format(1000000), "1M", "更高战力使用不同短单位")
    eq(NumberUtil.format(10040), NumberUtil.format(10041), "不同数值会显示同样短单位")
    check(NumberUtil.format(9999) > NumberUtil.format(1000000), "字符串排序会把低战力错误排前")

    local function rebuilt(fn, expectedEquips)
        local before = #powerCalls
        fn()
        eq(#powerCalls - before, #expectedEquips, "每次 rebuild 只计算筛选后确定装备一次")
        for index, equip in ipairs(expectedEquips) do
            local display = powerCalls[before + index].equip
            check(display ~= equip and display.baseStats ~= equip.baseStats, "计算仅水合深拷贝 " .. index)
            eq(display.name, equip.name, "计算对应来源装备名称 " .. index)
            check(same(display.baseStats, equip.baseStats), "计算保留来源实际基础属性 " .. index)
            eq(powerCalls[before + index].heroId, nil, "战力计算无英雄过滤 " .. index)
        end
    end
    local function claimRow(row, expectedIndex, message)
        local before = #claimed
        Page.handleInput(873, 772 + (row - 1) * 242)
        eq(#claimed, before + 1, message .. " 仅领取一次")
        eq(claimed[#claimed], expectedIndex, message)
    end
    local function drawChecked()
        local beforePower, beforeDraw = #powerCalls, #drawCalls
        Page.draw(nil)
        eq(#powerCalls, beforePower, "draw 不重复计算缓存战力")
        check(#drawCalls > beforeDraw, "draw 实际命中绘图替身而非提前返回")
        return beforeDraw
    end
    local function textAt(after, x, y, caption)
        for index = after + 1, #drawCalls do
            local call = drawCalls[index]
            if call.x == x and call.y == y and call.text == caption then return true end
        end
        return false
    end
    local snapshot = copy(source)
    rebuilt(function() Page.open(source) end, { low.equip, tieA.equip, million.equip, tieB.equip, high.equip })
    time.elapsedTime = 17
    claimRow(1, 4, "百万战力先于9999且无视品质")
    claimRow(2, 7, "相同显示短单位按原数值排且缺省索引指向来源位置7")
    claimRow(3, 90, "同战力来源先者保留显式索引90")
    claimRow(4, 3, "同战力不按显式索引大小排序")
    claimRow(5, 71, "低战力确定装备仍在待整理之前")
    local beforeTailClaim, beforeTailDecompose = #claimed, #decomposed
    Page.handleScroll(-1000) -- 列表缩短后先滚到底，待整理在裁剪内命中而非误点批量按钮。
    for _, y in ipairs({ 1766, 2008 }) do
        Page.handleInput(873, y)
        Page.handleRightClick(873, y)
    end
    Page.handleScroll(1000)
    eq(#claimed, beforeTailClaim, "尾部两个待整理均不能领取")
    eq(#decomposed, beforeTailDecompose, "尾部两个待整理均不能右键回收")
    Page.handleRightClick(873, 1014)
    eq(decomposed[#decomposed], 7, "排序后右键回收仍对应缺省来源索引")
    Page.handleInput(180, 1256)
    eq(Page.isDetailOpen(), true, "排序后点击第三行打开详情")
    local drawn = drawChecked()
    check(detailCalls[#detailCalls] ~= tieA.equip, "点击详情不持有来源装备")
    eq(detailCalls[#detailCalls].name, tieA.equip.name, "点击详情使用排序后第三行水合副本")
    check(textAt(drawn, 294, 716, million.equip.name), "首行实际绘制百万装备")
    check(textAt(drawn, 332, 831, "1M"), "首行实际绘制缓存战力短单位")
    check(textAt(drawn, 294, 958, high.equip.name), "第二行实际绘制较高数值装备")
    check(textAt(drawn, 332, 1073, NumberUtil.format(10041)), "第二行缓存战力显示与真实计算一致")
    check(textAt(drawn, 540, 360, "全部品质 · 待领取 5 件 · 待整理 5 件"), "排序不改变装备与待整理数量")
    Page.handleInput(400, 1256)
    eq(Page.isDetailOpen(), false, "排序后点击详情区域关闭")
    Page.handleHover(180, 1014)
    eq(Page.isDetailOpen(), false, "hover 不提前显示详情")
    time.elapsedTime = 17.6
    Page.handleHover(180, 1014)
    eq(Page.isDetailOpen(), true, "排序后 hover 延迟显示第二行详情")
    drawChecked()
    eq(detailCalls[#detailCalls].name, high.equip.name, "hover 详情命中排序后的装备副本而非来源第二项")
    check(sizeCalls > 0, "真实 Page 命中详情尺寸替身")
    check(feedbackCalls > 0, "真实 Page 命中反馈替身")
    check(same(source, snapshot), "open/动作/详情/draw 不写入来源数组及嵌套装备")
    for index, entry in ipairs(source) do
        eq(entry.power, nil, "缓存战力不污染来源 " .. index)
        eq(entry.displayOrder, nil, "排序序号不污染来源 " .. index)
        eq(entry.index, nil, "命中行号不污染来源 " .. index)
    end

    -- 来源主动改变属性后 refresh 必须重新计算重排；页面不得回写缓存到装备。
    low.equip.baseStats[1][2] = 4000000
    snapshot = copy(source)
    rebuilt(function() Page.refresh(source) end, { low.equip, tieA.equip, million.equip, tieB.equip, high.equip })
    eq(Page.isDetailOpen(), false, "refresh 清理指向旧行的详情")
    claimRow(1, 71, "refresh 后新两百万装备移到首行")
    claimRow(2, 4, "refresh 后原百万装备移到第二行")
    drawn = drawChecked()
    check(textAt(drawn, 332, 831, "2M"), "refresh 同时更新显示缓存战力")
    check(same(source, snapshot), "refresh 重排不改来源及装备")

    rebuilt(function() Page.handleInput(975, 286) end, { low.equip, tieB.equip, high.equip })
    claimRow(1, 71, "品质筛选首行保持数值降序")
    claimRow(2, 7, "品质筛选重排不采用筛选数组索引")
    claimRow(3, 3, "品质筛选第三行保留显式来源索引")
    Page.handleRightClick(873, 1256)
    eq(decomposed[#decomposed], 3, "筛选重排右键仍回收正确装备")
    Page.handleHover(180, 1014)
    time.elapsedTime = 18.2
    Page.handleHover(180, 1014)
    drawChecked()
    eq(detailCalls[#detailCalls].name, high.equip.name, "筛选重排 hover 仍对应正确装备副本")
    rebuilt(function() Page.refresh(source) end, { low.equip, tieB.equip, high.equip })
    claimRow(2, 7, "筛选期间 refresh 保持筛选和正确排序索引")
    rebuilt(function() Page.handleInput(975, 286) end, { low.equip, tieA.equip, million.equip, tieB.equip, high.equip })
    claimRow(4, 90, "取消筛选恢复全部并保持同战力来源顺序")
    claimRow(5, 3, "取消筛选同战力后者位置稳定")
    check(same(source, snapshot), "筛选/refresh/draw 均不写入来源及嵌套装备")

    -- 同战力顺序以最新来源数组为准，不以 sourceIndex 为准；重复 refresh 不抖动。
    local reordered = { pendingA, tieB, million, high, tieA, low, pendingB }
    local reorderedSnapshot = copy(reordered)
    for repeatIndex = 1, 2 do
        rebuilt(function() Page.refresh(reordered) end, { tieB.equip, million.equip, high.equip, tieA.equip, low.equip })
        claimRow(3, 4, "来源重排缺省sourceIndex更新为4（刷新" .. repeatIndex .. "）")
        claimRow(4, 3, "来源重排同战力新先者稳定（刷新" .. repeatIndex .. "）")
        claimRow(5, 90, "来源重排同战力新后者稳定（刷新" .. repeatIndex .. "）")
        drawChecked()
    end
    check(same(reordered, reorderedSnapshot), "新来源数组及装备不被排序/缓存/entryAt写入")
    for index, entry in ipairs(source) do
        eq(entry, reordered[({ 1, 6, 5, 3, 7, 2, 4 })[index]], "两份来源数组保留原条目引用 " .. index)
    end
    Page.forceClose()

    -- 真实 bind 工具条菜单选项点击，绝不绕过 onChange 或借用仓库英雄状态。
    local fs = filterBar.getState()
    local function choose(key, value)
        local options = filterBar.getOptions(key)
        local wanted = 0
        for index, option in ipairs(options) do if option.value == value then wanted = index break end end
        check(wanted > 0, "真实菜单包含选项 " .. key .. "/" .. value)
        local cx, cy = key == "type" and 765 or 295, key == "sort" and 524 or 434
        Page.handleInput(cx, cy)
        check(filterBar.isOpen(), "点击打开独立菜单 " .. key)
        Page.handleScroll(10000)
        local scroll = math.max(0, wanted - 8)
        Page.handleScroll(-scroll)
        Page.handleInput(cx, cy + 35 + 8 + 6 + (wanted - scroll - 0.5) * 62)
        check(not filterBar.isOpen(), "选择后关闭独立菜单 " .. key)
    end
    local Config = require("config.EquipmentConfig")
    local Query = require("systems.EquipmentQuery")
    local ES = require("systems.EquipmentSystem")
    local function entry(templateId, quality, index)
        return { count = 1, sourceIndex = index,
            equip = { templateId = templateId, quality = quality, level = 1, baseStats = {} } }
    end
    local otherType = ""
    for id, tpl in pairs(Config.ITEMS) do
        if tpl.slot == "weapon" and tpl.type ~= Config.ITEMS.W5.type then otherType = id break end
    end
    check(otherType ~= "", "模板含其他武器类型用于AND排除")
    local filterSource = { entry("W5", 5, 90), entry("W1", 5, 3), entry("W5", 1, 7),
        entry("O1", 5, 17), entry(otherType, 5, 23), { count = 4 } }
    local filterSnapshot = copy(filterSource)
    Page.open(filterSource)
    time.elapsedTime = 30
    eq(#fs.summary, 6, "全不限展示待整理")
    choose("sort", "ascend")
    eq(#fs.summary, 6, "仅排序不隐藏待整理")
    choose("slot", "weapon")
    eq(fs.pendingCount, 0, "部位筛选隐藏待整理")
    eq(#fs.summary, 4, "主手不会借双持包含副手")
    choose("type", Config.ITEMS.W5.type)
    eq(#fs.summary, 3, "装备类型与部位AND")
    Page.handleInput(893, 286) -- 品质5
    eq(#fs.summary, 2, "品质与部位类型AND")
    Page.handleInput(190, 286)
    local Dialog = require("ui.widget.SetFilterDialog")
    Page.handleInput(540, 610) -- 叠甲虫壳
    Page.handleInput(750, 1836)
    eq(#fs.summary, 1, "套装与品质部位类型四维AND")
    eq(fs.summary[1].sourceIndex, 90, "多维筛选不丢原索引")
    local snapshots = {}
    Page.setOnClaimAll(function(quality, sets, detail)
        snapshots[#snapshots + 1] = detail
        eq(quality[5], true, "批量旧第一参仍为品质集合")
        eq(sets.carapace, true, "批量旧第二参仍为套装集合")
        eq(detail.slotFilter, "weapon", "第三参部位快照")
        eq(detail.typeFilter, Config.ITEMS.W5.type, "第三参类型快照")
        quality[5], sets.carapace, detail.slotFilter = nil, nil, "offhand"
    end)
    Page.handleInput(320, 2210)
    Page.handleInput(320, 2210)
    check(snapshots[1] ~= snapshots[2], "每次批量第三参新快照")
    eq(fs.slotFilter, "weapon", "接收方修改快照不污染页面")
    eq(fs.qualitySet[5], true, "接收方修改品质快照不污染页面")
    eq(fs.setFilter.carapace, true, "接收方修改套装快照不污染页面")
    Page.setOnDecomposeAll(function(quality, sets, detail)
        eq(quality[5], true, "确认回收旧第一参")
        eq(sets.carapace, true, "确认回收旧第二参")
        eq(detail.slotFilter, "weapon", "确认回收部位快照")
        eq(detail.typeFilter, Config.ITEMS.W5.type, "确认回收类型快照")
    end)
    Page.handleInput(760, 2210)
    Page.handleInput(750, 1340)
    check(same(filterSource, filterSnapshot), "四维筛选及动作均不改来源")
    -- 单独类型、品质、套装都是实际过滤；重置一次统一清所有维度及排序。
    Page.handleInput(940, 524)
    eq(#fs.summary, 6, "重置恢复待整理及全部装备")
    choose("type", Config.ITEMS.W5.type)
    eq(fs.pendingCount, 0, "仅类型隐藏待整理")
    Page.handleInput(940, 524)
    Page.handleInput(565, 286)
    eq(fs.pendingCount, 0, "仅品质隐藏待整理")
    Page.handleInput(940, 524)
    Page.handleInput(190, 286)
    Page.handleInput(540, 1666)
    Page.handleInput(750, 1836)
    eq(fs.pendingCount, 0, "仅无套装也不把待整理当无套装")
    Page.handleInput(940, 524)

    -- 菜单遮挡优先；按下后refresh必须在close清moved前保存旧Up保护。
    Page.handleInput(295, 524)
    local beforeMenuClaim, beforeMenuRecycle = #claimed, #decomposed
    Page.handleHover(180, 772)
    time.elapsedTime = 31
    Page.handleHover(180, 772)
    eq(Page.isDetailOpen(), false, "菜单打开时不显示底层hover详情")
    Page.handleRightClick(873, 772)
    eq(#decomposed, beforeMenuRecycle, "菜单打开右键不回收底层")
    Page.handleDragBegin(295, 600)
    Page.handleDragMove(295, 470)
    Page.refresh(filterSource)
    Page.handleDragEnd(873, 772)
    Page.handleInput(873, 772)
    eq(#claimed, beforeMenuClaim, "菜单旧按下refresh后Up不能领新行")
    eq(filterBar.isOpen(), false, "refresh关闭旧菜单但保过滤")
    Page.handleInput(873, 772)
    eq(#claimed, beforeMenuClaim + 1, "旧Up仅抑制一次随后正常领取")
    Page.handleInput(180, 772)
    check(Page.isDetailOpen(), "排序切换前存在详情")
    choose("sort", "level")
    eq(Page.isDetailOpen(), false, "排序切换清旧详情")
    Page.handleScroll(-2)
    choose("slot", "weapon")
    eq(fs.scrollY, 0, "筛选切换重置滚动")
    Page.handleInput(760, 2210)
    local oldConfirm = fs.confirm
    Page.refresh(filterSource)
    check(oldConfirm and not fs.confirm, "refresh保过滤但取消旧确认")
    Page.handleInput(750, 1340) -- 旧确认释放仅消费
    eq(fs.slotFilter, "weapon", "refresh保部位过滤")
    Page.handleInput(295, 524)
    Page.close()
    eq(filterBar.isOpen(), false, "close立即清菜单")
    Page.forceClose()
    Page.open(filterSource)
    time.elapsedTime = 32
    eq(filterBar.isOpen(), false, "open不残留菜单")
    eq(fs.slotFilter, nil, "open重置独立部位状态")
    eq(fs.sortKey, nil, "open重置独立排序状态")

    -- 有效属性合计独立验证：主词条升阶、副词条轮转、普通词条倍率+固定加成、魔化排除。
    local complex = { templateId = "W1", quality = 1, level = 1, ascendLevel = 5, affixMult = 3,
        baseStats = { { "str", 10 }, { "str", 7 }, { "agi", 2 } },
        affixes = { { affixId = 1, value = 4, ascBonus = 2 }, { affixId = 1001, quality = 0, value = 3, ascBonus = 99 } },
        corruptRevert = { baseMult = "1", affixCount = "2", patches = { { ["1"] = "s", ["2"] = "1", ["3"] = "4", layer = "1" } } } }
    local complexSnapshot = copy(complex)
    local hydrated = Query.hydrateCopy(complex)
    local total, present = Query.attributeValue(hydrated, "str")
    eq(total, ES.effectiveBaseStatValue(hydrated, 1) + ES.effectiveBaseStatValue(hydrated, 2) + 14,
        "有效属性合计固定主副与普通词条")
    check(present, "已存在属性标识")
    eq(Query.attributeValue(hydrated, "finalPhysAtkBonus"), 3, "魔化词条不吃倍率和ascBonus")
    eq(hydrated.affixes[1].key, "str", "冷词条由affixId恢复")
    check(same(complex, complexSnapshot), "水合不改源腐化恢复快照或词条")
    local cold = { templateId = "W1", quality = 1, level = 1, affixes = { { affixId = 1, value = 2 } } }
    local coldSnapshot = copy(cold)
    local warm = Query.hydrateCopy(cold)
    check(warm.baseStats and #warm.baseStats > 0 and warm.slot == "weapon", "冷装备模板水合基础值和部位")
    check(same(cold, coldSnapshot), "冷装备水合无源字段回写")

    local function attributeEntry(index, baseStats, affixes, ascend)
        return { sourceIndex = index, equip = { templateId = "W1", name = "属性" .. index, quality = 1,
            level = 1, baseStats = baseStats, affixes = affixes, ascendLevel = ascend or 0 } }
    end
    local attrSource = { attributeEntry(80, {}, {}), attributeEntry(90, {{ "str", 0 }}, {}),
        attributeEntry(3, {{ "str", -2 }}, {}), attributeEntry(70, {{ "str", 5 }}, {}),
        attributeEntry(2, {{ "str", 5 }}, {}), { sourceIndex = 100, equip = complex }, { count = 2 } }
    local attrSnapshot = copy(attrSource)
    Page.open(attrSource)
    time.elapsedTime = 33
    choose("sort", "str")
    local function order(expected, message)
        for index, sourceIndex in ipairs(expected) do eq(fs.summary[index].sourceIndex, sourceIndex, message .. index) end
    end
    order({ 100, 70, 2, 90, 3, 80 }, "属性降序有效值/稳定来源/无值后置 ")
    Page.handleInput(605, 524)
    order({ 3, 90, 70, 2, 100, 80 }, "属性升序0负数仍有值/无值后置 ")
    eq(fs.pendingCount, 2, "属性排序仍保待整理")
    Page.refresh(attrSource)
    order({ 3, 90, 70, 2, 100, 80 }, "refresh保属性升序 ")
    choose("sort", "ascend")
    eq(fs.summary[3].sourceIndex, 80, "升阶同值同战力按来源稳定")
    Page.handleInput(605, 524)
    eq(fs.summary[1].sourceIndex, 100, "升阶降序按装备自身等级")
    for _, key in ipairs({ "power", "quality", "level" }) do
        choose("sort", key)
        check(fs.sortKey == key and fs.summary[1].equip ~= nil, "显式排序可用 " .. key)
    end
    check(same(attrSource, attrSnapshot), "所有属性排序refresh不改源腐化嵌套快照")
    -- 菜单提供的每一个属性键都验证有值/零值/负值/无值，避免只支持META的一小部分。
    for _, option in ipairs(filterBar.getOptions("sort")) do
        local key = option.value
        if key ~= "default" and key ~= "power" and key ~= "quality" and key ~= "level" and key ~= "ascend" then
            local every = { attributeEntry(8, {}, {}), attributeEntry(9, {{key, 0}}, {}),
                attributeEntry(3, {{key, -2}}, {}), attributeEntry(7, {{key, 5}}, {}) }
            Page.open(every)
            time.elapsedTime = time.elapsedTime + 1
            choose("sort", key)
            order({ 7, 9, 3, 8 }, "全部属性键降序无值后置 " .. key)
            Page.handleInput(605, 524)
            order({ 3, 9, 7, 8 }, "全部属性键升序无值后置 " .. key)
        end
    end
    Page.forceClose()

    local System = require("systems.LootBoxSystem")
    local box = { seeds = { pending, determined } }
    local _, pendingPieces = System.decomposeOne(box, 1)
    eq(pendingPieces, 0, "待整理条目不可单件回收")
    local _, selectedPieces = System.decomposeAll(box, 6)
    eq(selectedPieces, 1, "批量回收件数仅包含确定装备")
    eq(#box.seeds, 1, "批量回收保留待整理条目")
    eq(box.seeds[1], pending, "待整理原始数据完整保留")
    eq(pending.count, 3, "待整理数量不会因回收减少")
    local _, repeatedPieces = System.decomposeAll(box, 0)
    eq(repeatedPieces, 0, "全部回收也不能消耗待整理数量")
    print("[lootbox_page_test] 页面交互与排序全部通过")

    -- 持续变化也必须周期保存，模拟磁盘可证明不会覆盖玩家实际存档。
    -- 运行时 require 自带模块缓存，改 package.loaded 不会替换已加载的模块。
    -- 直接替换被 StandaloneSave 持有的模块方法，再在测试结束恢复。
    local Dispatcher = require("runtime.ClientDispatcher")
    local GameState = require("core.GameState")
    local data = { lootbox = { seeds = {} } }
    local written = {}
    local snapshotCalls, exportCalls, fileCalls = 0, 0, 0
    replace(Dispatcher, "snapshotAll", function()
        snapshotCalls = snapshotCalls + 1
        return data
    end)
    replace(GameState, "exportSave", function()
        exportCalls = exportCalls + 1
        return {}
    end)
    local disk, renames = {}, 0
    -- File 与 fileSystem 必须同时完全内存替换，临时文件原子替换也不接触玩家盘。
    replace(_G, "fileSystem", {
        Rename = function(_, from, to)
            check(from == "standalone_save.pending.json" and to == "standalone_save.json", "只重命名内存测试存档")
            check(disk[from] ~= nil, "内存临时文件已完整写入")
            disk[to], disk[from] = disk[from], nil
            renames = renames + 1
            return true
        end,
        Delete = function(_, path) disk[path] = nil return true end,
        FileExists = function(_, path) return disk[path] ~= nil end,
    })
    replace(_G, "File", function(path, mode)
        check(path == "standalone_save.pending.json", "File 只写内存临时存档")
        eq(mode, FILE_WRITE, "存档写入模式")
        fileCalls = fileCalls + 1
        return {
            IsOpen = function() return true end,
            WriteString = function(_, json)
                disk[path] = json
                written[#written + 1] = json
                return true
            end,
            Close = function() end,
            Dispose = function() end,
        }
    end)
    local Save = require("boot.StandaloneSave")
    for index = 1, 100 do
        data.lootbox.seeds = { { quality = 1, level = 1, count = index } }
        Save.Update(1)
    end
    check(#written >= 3, "持续掉落在30秒合并期限内周期保存")
    check(Save.Flush(), "最新数据立即保存成功")
    local decoded = cjson.decode(disk["standalone_save.json"])
    eq(decoded.modules.lootbox.seeds[1].count, 100, "立即保存包含最新遗匣数据")
    check(snapshotCalls >= 100, "存档实际命中 snapshotAll 替身")
    eq(exportCalls, snapshotCalls, "存档实际命中 exportSave 替身")
    eq(fileCalls, #written, "全部落盘均命中 File 替身而非玩家文件")
    eq(renames, #written, "全部提交均使用内存 fileSystem 替身")
    print("[lootbox_page_test] 持续掉落存档全部通过")
end

function Start()
    local ok, err = pcall(runTests)
    local cleanupErrors = {}
    local closed, closeErr = pcall(closePage)
    if not closed then cleanupErrors[#cleanupErrors + 1] = tostring(closeErr) end
    -- 独立 pcall 逐项恢复：即使一个恢复失败，也不能阻止其他全局/真实方法恢复。
    for index = #restorers, 1, -1 do
        local restored, restoreErr = pcall(restorers[index])
        if not restored then cleanupErrors[#cleanupErrors + 1] = tostring(restoreErr) end
    end
    if not ok then
        log:Write(LOG_ERROR, "[lootbox_page_test] [FAIL] " .. tostring(err))
    end
    if #cleanupErrors > 0 then
        log:Write(LOG_ERROR, "[lootbox_page_test] [FAIL] cleanup: " .. table.concat(cleanupErrors, "; "))
    elseif ok then
        print("[lootbox_page_test] ALL PASS assertions=" .. assertions)
    end
    engine:Exit()
end
