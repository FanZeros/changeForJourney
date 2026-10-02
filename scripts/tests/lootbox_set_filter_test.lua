
-- 套装筛选回归：遗匣页弹窗交互 + 批量领取/回收按套装过滤 + 无套装分类。
-- 模板归属（EquipmentSetConfig 名字规则）：W5「叠甲战神之剑」→ carapace；W1「练习用剑」→ 无套装。
local function eq(actual, expected, message)
    assert(actual == expected, message .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

local function runTests()
    local oldTime = time
    time = { elapsedTime = 10 }
    local oldSfx = package.loaded["systems.GameSFX"]
    local oldFeedback = package.loaded["systems.ButtonFeedback"]
    local oldIcons = package.loaded["core.DarkIcon"]
    local oldDetail = package.loaded["ui.character.equip.EquipmentDetail"]
    package.loaded["ui.character.equip.EquipmentDetail"] = {
        init = function() end,
        readOnlySize = function() return 720, 440 end,
        drawReadOnly = function() end,
    }
    package.loaded["core.DarkIcon"] = {} -- 只测输入与数据，不调用渲染器。
    package.loaded["systems.GameSFX"] = { playUIMove = function() end }
    package.loaded["systems.ButtonFeedback"] = { trigger = function() end }

    -- 模板归属自检（名字规则变动时本测试第一时间报警）
    local ESC = require("config.EquipmentSetConfig")
    local ECfg = require("config.EquipmentConfig")
    eq(ESC.getSetIdForTemplate(ECfg.ITEMS["W5"]), "carapace", "W5 归属叠甲虫壳")
    eq(ESC.getSetIdForTemplate(ECfg.ITEMS["W1"]), nil, "W1 无套装归属")
    eq(#ESC.orderedSetIds(), 12, "套装固定顺序共 12 套")

    local Page = require("ui.loot.LootBoxPage")
    local Dialog = require("ui.widget.SetFilterDialog")
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
          equip = { templateId = "W5", name = "叠甲战神之剑", quality = 5, level = 70 } },
        { quality = 5, level = 70, count = 1, sourceIndex = 2,
          equip = { templateId = "W5", name = "叠甲战神之剑", quality = 5, level = 70 } },
        { quality = 1, level = 10, count = 1, sourceIndex = 3,
          equip = { templateId = "W1", name = "练习用剑", quality = 1, level = 10 } },
        { quality = 6, level = 80, count = 2 }, -- 待整理（无 equip）
    }
    Page.open(entries)
    time.elapsedTime = 11

    -- 1) 打开套装筛选弹窗（入口按钮 cx=190 cy=286）
    Page.handleInput(190, 286)
    eq(Dialog.isOpen(), true, "点击套装按钮打开弹窗")
    eq(Dialog.countSelected(nil), 0, "初始未勾选")

    -- 2) 弹窗模态：打开时列表点击被消费，不触发领取
    local before = #claimed
    Page.handleInput(873, 542)
    eq(#claimed, before, "弹窗打开时点击列表不领取")
    eq(Dialog.isOpen(), true, "点弹窗行区域外也不误关（行1区域）")

    -- 3) 勾选叠甲虫壳（行1，cy=610）→ onChange 实时重建列表
    Page.handleInput(540, 610)
    eq(Dialog.countSelected(nil), 1, "勾选一套")
    -- 弹窗关闭后列表只剩 carapace 两条
    Page.handleInput(750, 1836) -- 完成
    eq(Dialog.isOpen(), false, "完成关闭弹窗")
    Page.handleInput(873, 542)
    eq(claimed[#claimed], 1, "筛选后首行是原索引1（carapace）")
    Page.handleInput(873, 784)
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
    Page.handleInput(873, 542)
    eq(claimed[#claimed], 3, "无套装筛选命中 W1（原索引3）")

    -- 6) 系统层：claimAll/decomposeAll 按套装过滤
    local System = require("systems.LootBoxSystem")
    local box = { seeds = {
        { quality = 5, level = 70, count = 1,
          equip = { templateId = "W5", quality = 5, level = 70 } },
        { quality = 1, level = 10, count = 1,
          equip = { templateId = "W1", quality = 1, level = 10 } },
        { quality = 6, level = 80, count = 2 }, -- 待整理
    } }
    local bag = { inventory = {}, equipped = {}, nextSeq = 1 }
    local got = System.claimAll(box, bag, nil, { carapace = true })
    eq(#got, 1, "claimAll 套装过滤只领 carapace")
    eq(got[1].templateId, "W5", "领取的是 W5")
    eq(#box.seeds, 2, "剩余 W1 + 待整理")

    local box2 = { seeds = {
        { quality = 5, level = 70, count = 1,
          equip = { templateId = "W5", quality = 5, level = 70 } },
        { quality = 1, level = 10, count = 1,
          equip = { templateId = "W1", quality = 1, level = 10 } },
    } }
    local _, pieces = System.decomposeAll(box2, nil, { none = true })
    eq(pieces, 1, "decomposeAll 无套装过滤只回收 W1")
    eq(box2.seeds[1].equip.templateId, "W5", "carapace 保留")

    -- 品质+套装组合：q5 AND carapace → 命中；q1 AND carapace → 空
    local box3 = { seeds = {
        { quality = 5, level = 70, count = 1,
          equip = { templateId = "W5", quality = 5, level = 70 } },
        { quality = 1, level = 10, count = 1,
          equip = { templateId = "W1", quality = 1, level = 10 } },
    } }
    local _, p2 = System.decomposeAll(box3, { [1] = true }, { carapace = true })
    eq(p2, 0, "品质与套装 AND 组合无交集时不回收")
    local _, p3 = System.decomposeAll(box3, { [5] = true }, { carapace = true })
    eq(p3, 1, "品质与套装 AND 组合命中回收")

    -- 7) 旧调用兼容：不传 setFilter 等同不限制
    local box4 = { seeds = {
        { quality = 5, level = 70, count = 1,
          equip = { templateId = "W5", quality = 5, level = 70 } },
        { quality = 1, level = 10, count = 1,
          equip = { templateId = "W1", quality = 1, level = 10 } },
    } }
    local _, p4 = System.decomposeAll(box4, 0)
    eq(p4, 2, "旧签名（无套装参数）全部回收")

    -- 8) 重新打开页面重置套装筛选
    Page.open(entries)
    time.elapsedTime = 12
    Page.handleInput(320, 2210)
    eq(allClaims, 2, "重开后一键领取可用")
    eq(next(claimSetFilter), nil, "重开后套装筛选已重置")

    Page.forceClose()
    package.loaded["systems.GameSFX"] = oldSfx
    package.loaded["systems.ButtonFeedback"] = oldFeedback
    package.loaded["core.DarkIcon"] = oldIcons
    package.loaded["ui.character.equip.EquipmentDetail"] = oldDetail
    time = oldTime
    print("[lootbox_set_filter_test] ALL PASS：套装筛选全部通过")
end

function Start()
    local ok, err = pcall(runTests)
    if not ok then
        print("[lootbox_set_filter_test] [FAIL] " .. tostring(err))
    end
    engine:Exit()
end
