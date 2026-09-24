-- 遗匣页面与存档回归：替换外部输入/磁盘，不触碰玩家数据。
local function eq(actual, expected, message)
    assert(actual == expected, message .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

function Start()
    local oldTime = time
    time = { elapsedTime = 10 }
    local oldSfx = package.loaded["systems.GameSFX"]
    local oldFeedback = package.loaded["systems.ButtonFeedback"]
    local oldIcons = package.loaded["core.DarkIcon"]
    package.loaded["core.DarkIcon"] = {} -- 本测试只测输入，不调用渲染器。
    package.loaded["systems.GameSFX"] = { playUIMove = function() end }
    package.loaded["systems.ButtonFeedback"] = { trigger = function() end }
    local Page = require("ui.LootBoxPage")
    local claimed, decomposed, allClaims, allDecomposes = {}, {}, 0, 0
    Page.setOnClaimOne(function(index) claimed[#claimed + 1] = index end)
    Page.setOnDecomposeOne(function(index) decomposed[#decomposed + 1] = index end)
    local claimQuality, recycleQuality = -1, -1
    Page.setOnClaimAll(function(quality) allClaims = allClaims + 1 claimQuality = quality end)
    Page.setOnDecomposeAll(function(quality) allDecomposes = allDecomposes + 1 recycleQuality = quality end)
    local entries = {}
    for index = 1, 20 do
        entries[index] = {
            quality = 1, level = index, count = 1, source = "idle", sourceIndex = index,
            equip = { templateId = "W1", name = "确定装备", quality = 1, level = index },
        }
    end
    Page.open(entries)
    Page.handleInput(873, 602)
    eq(#claimed, 0, "开场动画期间不触发领取")
    time.elapsedTime = 11
    Page.handleInput(873, 602)
    eq(claimed[1], 1, "首行领取索引")
    Page.handleScroll(-1000)
    Page.handleInput(873, 1828)
    eq(claimed[2], 20, "滚轮到底仍对应原存储索引")
    Page.handleScroll(1000)
    Page.handleDragBegin(500, 1000)
    Page.handleDragMove(500, 800)
    Page.handleDragEnd(500, 800)
    Page.handleInput(873, 644)
    eq(#claimed, 2, "拖拽结束不会误领")
    Page.handleInput(873, 644)
    eq(claimed[3], 2, "拖拽后按可见位置命中第二行")
    Page.handleInput(300, 2070)
    Page.handleInput(873, 644)
    eq(decomposed[1], 2, "分解模式原索引")
    Page.handleScroll(1000)
    Page.handleDragBegin(873, 602)
    Page.handleScroll(-2)
    Page.handleDragEnd(873, 602)
    Page.handleInput(873, 602)
    eq(#decomposed, 1, "按住后滚轮不能误分解新出现的条目")
    Page.handleDragBegin(873, 602)
    Page.refresh(entries)
    Page.handleScroll(1)
    Page.handleDragEnd(873, 602)
    Page.handleInput(873, 602)
    eq(#decomposed, 1, "数据刷新加滚轮仍保留防误点击保护")
    Page.handleInput(540, 2220)
    eq(allDecomposes, 0, "全部分解必须二次确认")
    Page.handleInput(873, 644)
    eq(#decomposed, 1, "确认框阻止点击底层条目")
    Page.handleInput(330, 1340)
    eq(allDecomposes, 0, "取消确认不分解")
    Page.handleInput(540, 2220)
    Page.handleInput(750, 1340)
    eq(allDecomposes, 1, "确认后仅分解一次")
    Page.handleInput(780, 2070)
    eq(allClaims, 1, "全部领取接线")
    Page.refresh({})
    eq(Page.isOpen(), true, "领空后保留地点空态")
    Page.handleInput(780, 2070)
    Page.handleInput(540, 2220)
    eq(allClaims, 1, "空态不能重复领取")
    eq(allDecomposes, 1, "空态不能分解")
    eq(claimQuality, 0, "默认领取范围为全部")
    eq(recycleQuality, 0, "默认回收范围为全部")
    entries[2].quality, entries[2].equip.quality = 6, 6
    entries[9].quality, entries[9].equip.quality = 6, 6
    Page.refresh(entries)
    Page.handleInput(966, 354)
    Page.handleInput(873, 602)
    eq(decomposed[#decomposed], 2, "筛选后的首行回收仍指向原索引2")
    Page.handleInput(300, 2070)
    Page.handleInput(873, 844)
    eq(claimed[#claimed], 9, "筛选后的第二行领取仍指向原索引9")
    Page.handleInput(780, 2070)
    eq(claimQuality, 6, "一键领取透传稀有度")
    Page.handleInput(540, 2220)
    Page.handleInput(750, 1340)
    eq(recycleQuality, 6, "一键回收只处理筛选品质")
    Page.refresh(entries)
    Page.handleInput(873, 602)
    eq(claimed[#claimed], 2, "刷新保持当前品质筛选")
    Page.handleInput(398, 354)
    local beforeEmptyFilter = allClaims
    Page.handleInput(780, 2070)
    eq(allClaims, beforeEmptyFilter, "空筛选不领取隐藏品质")
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
    Page.handleInput(873, 602)
    eq(#claimed, beforePending, "待整理条目不可领取")
    Page.handleInput(966, 354)
    Page.handleInput(873, 602)
    eq(claimed[#claimed], 17, "筛选保留摘要携带的原存储索引")
    Page.handleInput(540, 2220)
    local beforeRefresh = allDecomposes
    Page.refresh({ pending, determined })
    Page.handleInput(750, 1340)
    eq(allDecomposes, beforeRefresh, "刷新后旧确认不能执行回收")
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
    package.loaded["systems.GameSFX"] = oldSfx
    package.loaded["systems.ButtonFeedback"] = oldFeedback
    package.loaded["core.DarkIcon"] = oldIcons
    time = oldTime
    print("[lootbox_page_test] 页面交互全部通过")

    -- 持续变化也必须周期保存，模拟磁盘可证明不会覆盖玩家实际存档。
    local original = {}
    for _, name in ipairs({ "network.ClientDispatcher", "core.GameState", "ui.BattleScene", "network.StandaloneSave" }) do
        original[name] = package.loaded[name]
    end
    local data = { lootbox = { seeds = {} } }
    local written = {}
    package.loaded["network.ClientDispatcher"] = { snapshotAll = function() return data end }
    package.loaded["core.GameState"] = { exportSave = function() return {} end }
    package.loaded["ui.BattleScene"] = {}
    package.loaded["network.StandaloneSave"] = nil
    local originalFile = File
    File = function()
        return {
            IsOpen = function() return true end,
            WriteString = function(_, json) written[#written + 1] = json end,
            Close = function() end,
        }
    end
    local Save = require("network.StandaloneSave")
    for index = 1, 10 do
        data.lootbox.seeds = { { quality = 1, level = 1, count = index } }
        Save.Update(1)
    end
    assert(#written >= 3, "持续掉落不能永远推迟存档")
    Save.Flush()
    local decoded = cjson.decode(written[#written])
    eq(decoded.modules.lootbox.seeds[1].count, 10, "立即保存包含最新遗匣数据")
    File = originalFile
    for name, value in pairs(original) do package.loaded[name] = value end
    print("[lootbox_page_test] 持续掉落存档全部通过")
end
