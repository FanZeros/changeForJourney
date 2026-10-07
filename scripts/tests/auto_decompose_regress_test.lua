-- ============================================================================
-- auto_decompose_regress_test.lua — 自动分解统一判定/钳制/分解防刷回归
-- 验证：
--   1) shouldAutoDecompose 语义：双0不分解；单维0=不限制；双维 AND；字符串容错
--   2) SetAutoDecompose 钳制：品质上限6（至臻）、等级上限60，handler 返回钳制值
--   3) calcAutoDecomposeEssence 与手动分解基础公式一致
--   4) recordAutoDecompose 通知 seq 递增、累计 count/essence、带时间戳
--   5) DecomposeEquip 重复 seq 拒绝（防刷精粹），正常分解奖励正确且库存删除
--   6) 真实红装获取：噩梦击杀/离线种子/炼狱首通/点金石提品，低难度不越界
-- 跑法: ./.cli/UrhoXRuntime tests/auto_decompose_regress_test.lua \
--         -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local PREFIX = "[auto_decompose_regress] "
local failures = {}
local function check(cond, msg)
    if cond then print(PREFIX .. "[PASS] " .. msg)
    else print(PREFIX .. "[FAIL] " .. msg); failures[#failures + 1] = msg end
end
local function eq(actual, expected, msg)
    check(actual == expected, msg .. " (实际=" .. tostring(actual) .. " 期望=" .. tostring(expected) .. ")")
end

local BC = require("config.BlacksmithConfig")

-- 顶部六档为手动分解多选；只替换数据/发送/绘图边界，不访问真实玩家存档。
local function testRarityMultiselect()
    local patches, globals = {}, {}
    local globalKeys = {}
    local function patch(target, key, value)
        patches[#patches + 1] = { target = target, key = key, value = target[key] }
        target[key] = value
    end
    local function patchGlobal(key, value)
        globals[key] = _G[key]
        globalKeys[#globalKeys + 1] = key
        _G[key] = value
    end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = copy(child) end
        return result
    end
    local function signature(values)
        local result = {}
        for _, value in ipairs(values) do result[#result + 1] = tostring(value) end
        table.sort(result)
        return table.concat(result, ",")
    end
    local ok, err = pcall(function()
        local PlayerStore = require("core.PlayerStore")
        local GameAction = require("runtime.GameAction")
        local Protocol = require("shared.Protocol")
        local PDM = require("rules.character.PlayerDataManager")
        local TaskService = require("rules.task.TaskService")
        local EquipmentSystem = require("systems.EquipmentSystem")
        local BS = require("rules.blacksmith.BlacksmithService")
        local Detail = require("ui.character.equip.EquipmentDetail")
        local RewardPopup = require("ui.hud.popup.RewardPopup")
        local BF = require("systems.ButtonFeedback")
        local QualityMark = require("ui.widget.QualityMark")
        local SetIcon = require("ui.widget.EquipmentSetIcon")
        local ResourceDefs = require("config.ResourceDefs")
        local EquipmentConfig = require("config.EquipmentConfig")
        local I18n = require("core.I18n")
        local EquipmentText = require("core.I18nEquipmentText")
        local actions, rewards, dirty, progress = {}, {}, {}, {}
        local testPDM = { equipment = {}, currency = { essence = 0 } }
        local equipmentRevision = 0
        patch(PlayerStore, "Get", function(name) return testPDM[name] end)
        patch(PlayerStore, "GetRevision", function(name) return name == "equipment" and equipmentRevision or 0 end)
        patch(PDM, "GetModule", function(_, name) return testPDM[name] end)
        patch(PDM, "MarkDirty", function(_, name) dirty[name] = (dirty[name] or 0) + 1 end)
        patch(TaskService, "UpdateProgress", function(_, name, count)
            progress[name] = (progress[name] or 0) + count
        end)
        patch(GameAction, "sendAction", function(action, params)
            actions[#actions + 1] = { action = action, params = copy(params) }
            return true
        end)
        local detailState = { open = false, pinned = false, point = false, owner = "backpack", opens = 0, dismisses = 0 }
        patch(Detail, "isOpen", function() return detailState.open end)
        patch(Detail, "isPinned", function() return detailState.pinned end)
        patch(Detail, "getOwner", function() return detailState.owner end)
        patch(Detail, "containsPoint", function() return detailState.point end)
        patch(Detail, "dismissHover", function(owner)
            if owner == detailState.owner and not detailState.pinned then
                detailState.open = false; detailState.dismisses = detailState.dismisses + 1
            end
        end)
        patch(Detail, "open", function(_, _, _, _, owner)
            detailState.opens = detailState.opens + 1
            detailState.open, detailState.owner = true, owner
        end)
        patch(RewardPopup, "show", function(title, items)
            rewards[#rewards + 1] = { title = title, items = copy(items) }
        end)
        -- 不播放音效/启动按钮动画，保留真实 drawPanel、DrawUtil 与品质图绘制。
        patch(BF, "trigger", function() end)
        patch(BF, "begin", function() return false end)
        patch(BF, "finish", function() end)
        patch(SetIcon, "isEnabled", function() return false end)
        patch(QualityMark, "get", function(quality) return 72000 + math.floor(quality) end)
        patch(QualityMark, "init", function() end)
        patch(Detail, "init", function() end)
        patchGlobal("time", { elapsedTime = 100 })
        local checkImage = 73000
        local paints, texts, imagePaths, imageHandles = {}, {}, {}, {}
        local imageCount = 0
        local function noop() end
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgRoundedRectVarying",
            "nvgFill", "nvgStroke", "nvgStrokeColor", "nvgStrokeWidth", "nvgMoveTo", "nvgLineTo",
            "nvgClosePath", "nvgCircle", "nvgEllipse", "nvgBezierTo", "nvgQuadTo", "nvgArc",
            "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgTranslate", "nvgScale", "nvgRotate",
            "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor", "nvgLineCap" }) do
            patchGlobal(name, noop)
        end
        patchGlobal("nvgText", function(_, x, y, text)
            texts[#texts + 1] = { x = x, y = y, text = text }
            return x
        end)
        patchGlobal("nvgCreateImage", function(_, path)
            if not imageHandles[path] then
                imageCount = imageCount + 1
                local handle = 75000 + imageCount
                imageHandles[path] = handle
                imagePaths[handle] = path
            end
            return imageHandles[path]
        end)
        imagePaths[74002] = ResourceDefs.DEFS.essence.iconPath
        patchGlobal("nvgRGBA", function(r, g, b, a) return { r = r, g = g, b = b, a = a } end)
        patchGlobal("nvgLinearGradient", function() return {} end)
        patchGlobal("nvgRadialGradient", function() return {} end)
        patchGlobal("nvgTextBounds", function(_, _, _, text) return #text * 14 end)
        patchGlobal("nvgImagePattern", function(_, x, y, w, h, _, image, alpha)
            return { image = image, cx = x + w * 0.5, cy = y + h * 0.5, w = w, h = h, alpha = alpha }
        end)
        patchGlobal("nvgFillPaint", function(_, paint)
            if paint.image then paints[#paints + 1] = paint end
        end)
        -- NanoVG 边界替身先于模块加载；不替换被局部缓存的 DrawUtil 绘制函数。
        -- 同一真实模块实例通过 onOpen/resetFixture 重置，不依赖加载缓存隔离。
        local M = require("ui.blacksmith.BlacksmithDecompose")
        M.init({})  -- 设置真实 vgHandle/懒加载图标缓存，详情与品质图初始化仅替换边界。
        M.setContext({
            imgGoldQBg = 74001, imgEssenceIcon = 74002, imgEnhBtn = 74003,
            imgReplaceBtn = 74004, imgCheckmark = checkImage, imgQualityBg = {},
            getEquipIconCached = function() return -1 end,
            QUALITY_COST = BC.QUALITY_COST, ENHANCE_TABLE = BC.ENHANCE_TABLE,
            SLOT_BG_ALPHA = 1, EQUIP_NAME_CX = 540, EQUIP_NAME_CY = 650,
            EQUIP_NAME_FONT_SIZE = 36, EQUIP_NAME_STROKE = 4,
            getClient = function() return GameAction end, getProtocol = function() return Protocol end,
        })
        local function equip(seq, quality, locked)
            local item = assert(EquipmentSystem.generate("W1", 10, quality), "测试装备生成失败")
            item.seq, item.locked = seq, locked or nil
            return item
        end
        local function resetFixture()
            testPDM.equipment = { inventory = {}, equipped = {
                [1] = { weapon = 9701 }, [2] = { weapon = "9702" },
            }, settings = { autoQuality = 4, autoLevel = 30 } }
            for _, row in ipairs({ { 9101, 1 }, { 9102, 1 }, { 9103, 1, true },
                { 9201, 2 }, { 9202, 2 }, { 9203, 2, true }, { 9301, 3 }, { 9302, 3 },
                { 9401, 4 }, { 9501, 5 }, { 9601, 6 }, { 9602, 6, true },
                { 9701, 1 }, { 9702, 2 } }) do
                testPDM.equipment.inventory[tostring(row[1])] = equip(row[1], row[2], row[3])
            end
            testPDM.currency = { essence = 0 }
            detailState.open, detailState.pinned, detailState.point = false, false, false
            -- onOpen保留旧longPressFired语义；夹具显式结束上轮触摸并重置按压。
            M.handleDragBegin(-1, -1); M.handleDragEnd(-1, -1)
            M.onOpen()
        end
        local allEligible = { 9101, 9102, 9201, 9202, 9301, 9302, 9401, 9501, 9601 }
        for _, profile in ipairs({ "warehouse", "smith" }) do
            local label = "手动多品质[" .. profile .. "] "
            local layout = profile == "warehouse"
                and { qx = 565, qy = 328, qs = 82, gx = 160, gy = 550, gs = 190, by = 2160 }
                or { qx = 558, qy = 900, qs = 103, gx = 150, gy = 1060, gs = 195, by = 2129 }
            M.applyProfile(profile)
            local function click(x, y, text)
                check(M.handleInput(x, y) == true, label .. text .. " 消费点击")
            end
            local function quality(q) click(layout.qx + (q - 1) * layout.qs, layout.qy, "顶部品质" .. q) end
            local function cell(seq)
                for index = 1, 25 do
                    local x = layout.gx + ((index - 1) % 5) * layout.gs
                    local y = layout.gy + math.floor((index - 1) / 5) * layout.gs
                    local item = M.peekCellAt(x, y)
                    if item and tostring(item.seq) == tostring(seq) then
                        click(x, y, "装备格子" .. seq)
                        return
                    end
                end
                error(label .. "找不到可见测试格子 seq=" .. tostring(seq))
            end
            local function equippedSet()
                local result = {}
                for _, slots in pairs(testPDM.equipment.equipped or {}) do
                    for _, seq in pairs(slots) do
                        local numeric = tonumber(seq)
                        result[tostring(numeric and (math.tointeger(numeric) or numeric) or seq)] = true
                    end
                end
                return result
            end
            -- 顶部六坐标与格子坐标分别捕获，不把格子对勾误算为顶部品质对勾。
            local function selected(expected, text, committed)
                paints = {}
                M.drawPanel({})
                local top, icons, actual, seen = {}, {}, {}, {}
                for _, paint in ipairs(paints) do
                    for q = 1, 6 do
                        if math.abs(paint.cx - (layout.qx + (q - 1) * layout.qs)) < 0.001
                            and math.abs(paint.cy - layout.qy) < 0.001 then
                            if paint.image == checkImage then top[q] = (top[q] or 0) + 1 end
                            if paint.image == 72000 + q then icons[q] = (icons[q] or 0) + 1 end
                        end
                    end
                    if paint.image == checkImage and paint.cy ~= layout.qy then
                        local item = M.peekCellAt(paint.cx, paint.cy)
                        check(item ~= nil, label .. text .. " 对勾落在真实装备格子")
                        if item then
                            local seq = tostring(item.seq)
                            check(not seen[seq], label .. text .. " 格子对勾不重复 seq=" .. seq)
                            seen[seq], actual[#actual + 1] = true, seq
                        end
                    end
                end
                eq(signature(actual), signature(expected), label .. text .. " 格子选择")
                local wanted, equipped = {}, equippedSet()
                for _, seq in ipairs(committed or expected) do wanted[tostring(seq)] = true end
                for q = 1, 6 do
                    local eligible, complete = 0, true
                    for seq, item in pairs(testPDM.equipment.inventory) do
                        if item.quality == q and not item.locked and not equipped[tostring(seq)] then
                            eligible = eligible + 1
                            if not wanted[tostring(seq)] then complete = false end
                        end
                    end
                    eq(icons[q] or 0, 1, label .. text .. " 顶部品质图" .. q .. "含红档且坐标准确")
                    eq(top[q] or 0, eligible > 0 and complete and 1 or 0,
                        label .. text .. " 顶部对勾" .. q .. "由全选可分解项派生")
                end
            end
            local function request(expected, text)
                local before = #actions
                click(773, layout.by, "分解按钮")
                eq(#actions, before + (#expected > 0 and 1 or 0), label .. text .. " 请求数量")
                if #expected == 0 then return nil end
                local action = actions[before + 1]
                check(action ~= nil, label .. text .. " 捕获GameAction")
                if not action then return nil end
                eq(action.action, Protocol.ACTION_TYPES.DECOMPOSE_EQUIP, label .. text .. " 分解动作")
                local seqs = action.params.seqs or {}
                eq(signature(seqs), signature(expected), label .. text .. " payload多品质并集")
                eq(#seqs, #expected, label .. text .. " payload长度准确")
                local seen, equipped = {}, equippedSet()
                for _, seq in ipairs(seqs) do
                    local key = tostring(seq)
                    check(not seen[key], label .. text .. " payload不重复 seq=" .. key)
                    seen[key] = true
                    local item = testPDM.equipment.inventory[key]
                    check(item ~= nil and not item.locked and not equipped[key],
                        label .. text .. " payload排除最新锁定/穿戴 seq=" .. key)
                end
                return action
            end
            local function failure()
                M.onActionResult({ action = Protocol.ACTION_TYPES.DECOMPOSE_EQUIP, success = false })
            end
            -- 单独绘制真实奖励区域：不把背包等级文字/品质对勾混入预览捕获。
            local originalEmpty = ""
            local function preview(seqs, text)
                local essence, scrolls = 0, {}
                for _, seq in ipairs(seqs) do
                    local item = assert(testPDM.equipment.inventory[tostring(seq)])
                    essence = essence + BC.calcAutoDecomposeEssence(item.quality, item.level)
                    local tpl = EquipmentConfig.ITEMS[item.templateId]
                    local field = BC.SLOT_SCROLL_MAP[item.slot or (tpl and tpl.slot)]
                    local refund = BC.calcAscendScrollRefund(EquipmentSystem.getAscendLevel(item))
                    if field and refund > 0 then scrolls[field] = (scrolls[field] or 0) + refund end
                end
                local entries = {}
                if essence > 0 then entries[1] = { type = "essence", amount = essence } end
                BC.appendScrollRewardItems(entries, scrolls)
                paints, texts = {}, {}
                M.drawUpperSlot({})
                local imageTokens, textTokens, uniqueText, resourceImages = {}, {}, {}, {}
                for _, paint in ipairs(paints) do
                    local path = imagePaths[paint.image]
                    check(path ~= nil, label .. text .. " 预览图像由真实资源路径解析")
                    resourceImages[#resourceImages + 1] = path or tostring(paint.image)
                    imageTokens[#imageTokens + 1] = table.concat({ path or tostring(paint.image),
                        tostring(paint.cx), tostring(paint.cy), tostring(paint.w), tostring(paint.h) }, "@")
                end
                for _, drawn in ipairs(texts) do
                    uniqueText[drawn.text] = true
                    textTokens[#textTokens + 1] = table.concat({ drawn.text,
                        tostring(drawn.x), tostring(drawn.y) }, "@")
                end
                local actualTexts = {}
                for value in pairs(uniqueText) do actualTexts[#actualTexts + 1] = value end
                local expectedTexts, expectedImages = {}, {}
                if profile == "warehouse" then
                    if #seqs == 0 then
                        expectedTexts[1] = "勾选装备预览分解所得"
                    else
                        expectedTexts[1] = "当前分解可获得"
                        local firstCX = 540 - (#entries - 1) * 106 * 0.5
                        for index, entry in ipairs(entries) do
                            local path = ResourceDefs.DEFS[entry.type].iconPath
                            expectedImages[#expectedImages + 1] = path
                            expectedTexts[#expectedTexts + 1] = tostring(entry.amount)
                            local cx = firstCX + (index - 1) * 106
                            local iconCount, amountCount = 0, 0
                            for _, paint in ipairs(paints) do
                                if imagePaths[paint.image] == path and math.abs(paint.cx - cx) < 0.001
                                    and math.abs(paint.cy - 2056) < 0.001 and paint.w == 64 and paint.h == 64 then
                                    iconCount = iconCount + 1
                                end
                            end
                            for _, drawn in ipairs(texts) do
                                if drawn.text == tostring(entry.amount) and math.abs(drawn.x - (cx + 36)) < 0.001
                                    and math.abs(drawn.y - 2094) < 0.001 then amountCount = amountCount + 1 end
                            end
                            eq(iconCount, 1, label .. text .. " 真实图标居中且不重复 " .. entry.type)
                            eq(amountCount, 1, label .. text .. " 真实数量角标 " .. entry.type)
                        end
                    end
                else
                    -- smith 原空态本来有静态精粹槽图；只禁止历史奖励数和卷轴 hint，不删该图。
                    expectedImages[1] = ResourceDefs.DEFS.essence.iconPath
                    expectedTexts[1] = #seqs > 0 and I18n.format("精粹 +%s", tostring(essence)) or "分解奖励"
                    local hint = BC.formatScrollRefund(scrolls)
                    if hint then expectedTexts[#expectedTexts + 1] = EquipmentText.lookup(hint, I18n.get()) or hint end
                end
                local uniqueExpected, wantedTexts = {}, {}
                for _, value in ipairs(expectedTexts) do uniqueExpected[value] = true end
                for value in pairs(uniqueExpected) do wantedTexts[#wantedTexts + 1] = value end
                eq(signature(resourceImages), signature(expectedImages),
                    label .. text .. " 真实预览资源完整且无旧金币/卷轴图")
                eq(signature(actualTexts), signature(wantedTexts),
                    label .. text .. " 真实预览文字完整且无历史数量/卷轴hint")
                if #seqs == 0 then
                    local capture = signature(imageTokens) .. "|" .. signature(textTokens)
                    if originalEmpty == "" then originalEmpty = capture end
                    eq(capture, originalEmpty, label .. text .. " 恢复原空态图文及坐标")
                end
            end
            local function popup(expected, index, text)
                local reward = rewards[index]
                check(reward ~= nil, label .. text .. " 捕获真实RewardPopup入口")
                if not reward then return end
                eq(reward.title, "分解奖励", label .. text .. " 弹奖标题不变")
                eq(#reward.items, #expected, label .. text .. " 弹奖完整资源数量")
                for position, item in ipairs(expected) do
                    local actual = reward.items[position] or {}
                    eq(actual.type, item.type, label .. text .. " 弹奖有序type " .. position)
                    eq(actual.amount, item.amount, label .. text .. " 弹奖完整amount " .. position)
                end
            end
            resetFixture()
            selected({}, "打开清空")
            preview({}, "打开原空态")
            local rewardBefore = #rewards
            quality(1); selected({ 9101, 9102 }, "q1选择全部未锁未装")
            quality(2); selected({ 9101, 9102, 9201, 9202 }, "q2保留q1")
            local union = { 9101, 9102, 9201, 9202 }
            preview(union, "有选中基础精粹预览")
            request(union, "首次并集发送")
            local pendingCount = #actions
            click(773, layout.by, "pending重复分解")
            eq(#actions, pendingCount, label .. "pending阻止重复请求")
            M.onActionResult({ action = Protocol.ACTION_TYPES.TOGGLE_EQUIP_LOCK,
                decomposed = true, essenceReward = 99 })
            selected(union, "无关成功回执保留")
            preview(union, "无关回执预览仍由选择派生")
            eq(#rewards, rewardBefore, label .. "无关回执不弹分解奖励")
            click(773, layout.by, "无关回执后重复分解")
            eq(#actions, pendingCount, label .. "无关回执不提前释放pending")
            failure(); selected(union, "失败回执保留勾选")
            preview(union, "失败回执保留基础预览")
            eq(#rewards, rewardBefore, label .. "失败回执不弹奖励")
            local retry = request(union, "失败释放pending可重试")
            check(retry ~= nil, label .. "服务端使用真实多品质payload")
            if retry then
                local inventoryBefore = {}
                for key, item in pairs(testPDM.equipment.inventory) do inventoryBefore[key] = item end
                local essence = 0
                for _, seq in ipairs(union) do
                    local item = inventoryBefore[tostring(seq)]
                    essence = essence + BC.calcAutoDecomposeEssence(item.quality, item.level)
                end
                local equipDirty, currencyDirty = dirty.equipment or 0, dirty.currency or 0
                local taskBefore = progress.decompose or 0
                local serviceOk, serviceErr, result = BS.DecomposeEquip(1, retry.params.seqs)
                check(serviceOk == true, label .. "真实BS.DecomposeEquip多品质成功 " .. tostring(serviceErr))
                if serviceOk and result then
                    eq(result.decomposeCount, 4, label .. "真实服务分解数量")
                    eq(testPDM.currency.essence, essence, label .. "真实服务精粹并集奖励")
                    eq(result.essenceReward, essence, label .. "真实服务返回奖励")
                    eq(dirty.equipment, equipDirty + 1, label .. "真实服务装备标脏")
                    eq(dirty.currency, currencyDirty + 1, label .. "真实服务货币标脏")
                    eq(progress.decompose, taskBefore + 4, label .. "真实服务任务数量")
                    local removed = {}
                    for _, seq in ipairs(union) do removed[tostring(seq)] = true end
                    for key, item in pairs(inventoryBefore) do
                        if not removed[key] then
                            eq(testPDM.equipment.inventory[key], item,
                                label .. "真实服务保留未选/锁定/穿戴 seq=" .. key)
                        end
                    end
                    for _, seq in ipairs(union) do
                        eq(testPDM.equipment.inventory[tostring(seq)], nil, label .. "库存删除并集 seq=" .. seq)
                    end
                    eq(testPDM.equipment.equipped[1].weapon, 9701, label .. "数字穿戴关系保留")
                    eq(testPDM.equipment.equipped[2].weapon, "9702", label .. "字符串穿戴关系保留")
                    result.action = Protocol.ACTION_TYPES.DECOMPOSE_EQUIP
                    M.onActionResult(result)
                    selected({}, "成功回执清所有品质勾选")
                    preview({}, "基础奖励成功后无历史回显")
                    eq(#rewards, rewardBefore + 1, label .. "成功奖励仅弹一次")
                    popup({ { type = "essence", amount = essence } }, rewardBefore + 1, "基础成功弹奖内容不变")
                    cell(9301); selected({ 9301 }, "成功后可手选其他品质")
                    M.onActionResult(result)
                    selected({ 9301 }, "非pending重复成功不误清新选择")
                    preview({ 9301 }, "重复回执不回显旧奖励")
                    eq(#rewards, rewardBefore + 1, label .. "重复回执不重复弹奖")
                end
            end
            -- 升阶返卷轴用真实不同部位装备与 BC 成本计算；服务真实入账，弹奖不能被清预览吞掉。
            resetFixture()
            for _, row in ipairs({ { 9101, "W1", 1, 3, 2 }, { 9102, "W1", 1, 1, 0 },
                { 9201, "A1", 2, 5, 1 }, { 9301, "O1", 3, 7, 0 } }) do
                local item = assert(EquipmentSystem.generate(row[2], 10, row[3]))
                item.seq, item.ascendLevel, item.enhanceLevel, item.refineCount = row[1], row[4], row[4], row[5]
                testPDM.equipment.inventory[tostring(row[1])] = item
            end
            testPDM.currency = { essence = 123, gold = 456789, weaponScroll = 11, offhandScroll = 13,
                armorScroll = 17, helmetScroll = 19, shoesScroll = 23, accessoryScroll = 29 }
            M.onEquipmentDataUpdate()
            local ascended = { 9101, 9102, 9201, 9301 }
            quality(1); cell(9201); cell(9301)
            selected(ascended, "不同部位升阶装备多选")
            preview(ascended, "升阶精粹及不同部位卷轴预览")
            local ascRewardsBefore = #rewards
            request(ascended, "升阶多部位首次发送")
            M.onActionResult({ action = Protocol.ACTION_TYPES.DECOMPOSE_EQUIP, success = false,
                essenceReward = 777, goldReward = 888, scrollRewards = { weaponScroll = 999 } })
            selected(ascended, "升阶失败保留所有选择")
            preview(ascended, "升阶失败不回显回执资源")
            eq(#rewards, ascRewardsBefore, label .. "升阶失败不弹奖")
            local ascendRetry = request(ascended, "升阶失败可重试")
            if ascendRetry then
                local inventoryBefore, currencyBefore = copy(testPDM.equipment.inventory), copy(testPDM.currency)
                local expectedEssence, expectedRefine, expectedScrolls, expectedScrollTotal = 0, 0, {}, 0
                for _, seq in ipairs(ascended) do
                    local item = inventoryBefore[tostring(seq)]
                    expectedEssence = expectedEssence + BC.calcAutoDecomposeEssence(item.quality, item.level)
                    expectedRefine = expectedRefine
                        + math.floor(BC.calcTotalRefineSpent(item.quality, item.level, item.refineCount, item.grip) * 0.5)
                    local field = BC.SLOT_SCROLL_MAP[item.slot]
                    local amount = BC.calcAscendScrollRefund(EquipmentSystem.getAscendLevel(item))
                    expectedScrolls[field] = (expectedScrolls[field] or 0) + amount
                    expectedScrollTotal = expectedScrollTotal + amount
                end
                expectedEssence = expectedEssence + expectedRefine
                check(expectedScrolls.weaponScroll > 0 and expectedScrolls.offhandScroll > 0
                    and expectedScrolls.armorScroll > 0, label .. "真实BC配置覆盖三部位且同部位累计")
                local equipDirty, currencyDirty = dirty.equipment or 0, dirty.currency or 0
                local taskBefore = progress.decompose or 0
                local serviceOk, serviceErr, result = BS.DecomposeEquip(1, ascendRetry.params.seqs)
                check(serviceOk == true, label .. "真实升阶多部位分解成功 " .. tostring(serviceErr))
                if serviceOk and result then
                    eq(result.decomposeCount, #ascended, label .. "升阶实际分解数量")
                    eq(result.essenceReward, expectedEssence, label .. "升阶实际精粹包含洗练返还")
                    eq(result.refineReturn, expectedRefine, label .. "升阶实际洗练返还不变")
                    eq(result.scrollReward, expectedScrollTotal, label .. "升阶实际卷轴返还总量")
                    eq(result.goldReward or 0, 0, label .. "升阶实际服务金币不退")
                    local actualScrolls, wantedScrolls = {}, {}
                    for field, amount in pairs(result.scrollRewards or {}) do
                        actualScrolls[#actualScrolls + 1] = field .. ":" .. amount
                    end
                    for field, amount in pairs(expectedScrolls) do wantedScrolls[#wantedScrolls + 1] = field .. ":" .. amount end
                    eq(signature(actualScrolls), signature(wantedScrolls), label .. "升阶实际卷轴完整部位及数量")
                    for field, amount in pairs(currencyBefore) do
                        local added = field == "essence" and expectedEssence or (expectedScrolls[field] or 0)
                        eq(testPDM.currency[field], amount + added, label .. "升阶真实资源入账/未涉及资源保留 " .. field)
                    end
                    eq(dirty.equipment, equipDirty + 1, label .. "升阶服务装备标脏一次")
                    eq(dirty.currency, currencyDirty + 1, label .. "升阶服务货币标脏一次")
                    eq(progress.decompose, taskBefore + #ascended, label .. "升阶服务任务计数不变")
                    for _, seq in ipairs(ascended) do
                        eq(testPDM.equipment.inventory[tostring(seq)], nil, label .. "升阶实际库存删除 seq=" .. seq)
                    end
                    result.action = Protocol.ACTION_TYPES.DECOMPOSE_EQUIP
                    M.onActionResult(result)
                    selected({}, "升阶成功清所有选择")
                    preview({}, "升阶成功无历史数量卷轴hint及金币")
                    for index = 1, 25 do
                        local item = M.peekCellAt(layout.gx + ((index - 1) % 5) * layout.gs,
                            layout.gy + math.floor((index - 1) / 5) * layout.gs)
                        if item then
                            for _, seq in ipairs(ascended) do
                                check(tostring(item.seq) ~= tostring(seq), label .. "升阶成功真实背包刷新排除 seq=" .. seq)
                            end
                        end
                    end
                    eq(#rewards, ascRewardsBefore + 1, label .. "升阶成功仍弹奖一次")
                    local expectedPopup = { { type = "essence", amount = expectedEssence } }
                    BC.appendScrollRewardItems(expectedPopup, expectedScrolls)
                    popup(expectedPopup, ascRewardsBefore + 1, "升阶实际完整精粹及三部位卷轴弹奖")
                    cell(9302); selected({ 9302 }, "升阶成功后新选其他装备")
                    M.onActionResult(result)
                    selected({ 9302 }, "升阶重复回执不误清新选择")
                    preview({ 9302 }, "升阶重复回执仅显示新选择精粹")
                    M.onActionResult({ action = Protocol.ACTION_TYPES.TOGGLE_EQUIP_LOCK,
                        decomposed = true, essenceReward = expectedEssence, goldReward = 99999,
                        scrollRewards = expectedScrolls })
                    selected({ 9302 }, "升阶无关回执不误清新选择")
                    preview({ 9302 }, "升阶无关回执不混旧资源")
                    eq(#rewards, ascRewardsBefore + 1, label .. "升阶重复及无关回执不重复弹奖")
                    cell(9302); selected({}, "手动取消全部选择")
                    preview({}, "取消全部不回落上次升阶奖励")
                    request({}, "取消全部不发送")
                    cell(9501); M.onTabSwitch(); selected({}, "升阶奖励后切tab清空")
                    preview({}, "升阶奖励后切tab保持原空态")
                    cell(9401); M.onOpen(); selected({}, "升阶奖励后重开清空")
                    preview({}, "升阶奖励后重开保持原空态")
                end
            end

            -- 兼容旧 goldReward 回执仍完整弹窗显示，但不成为新的预览来源，也不重复入账。
            M.onOpen(); cell(9501)
            preview({ 9501 }, "兼容金币回执前正常选择预览")
            local legacyRequest = request({ 9501 }, "兼容金币回执请求")
            if legacyRequest then
                local legacyBefore, currencyBefore = #rewards, copy(testPDM.currency)
                local scrolls = { weaponScroll = BC.calcAscendScrollRefund(3), armorScroll = BC.calcAscendScrollRefund(5) }
                M.onActionResult({ action = Protocol.ACTION_TYPES.DECOMPOSE_EQUIP, decomposed = true,
                    essenceReward = 987, goldReward = 4321, scrollRewards = scrolls })
                selected({}, "兼容金币成功回执清选择")
                preview({}, "兼容金币成功无旧金币图及数量")
                eq(#rewards, legacyBefore + 1, label .. "兼容金币成功仍弹窗")
                local expectedPopup = { { type = "essence", amount = 987 }, { type = "gold", amount = 4321 } }
                BC.appendScrollRewardItems(expectedPopup, scrolls)
                popup(expectedPopup, legacyBefore + 1, "兼容金币与精粹卷轴完整弹奖不变")
                for field, amount in pairs(currencyBefore) do
                    eq(testPDM.currency[field], amount, label .. "UI兼容回执不重复发资源 " .. field)
                end
                cell(9501); cell(9501); preview({}, "兼容奖励后取消全部保持空态")
                M.onTabSwitch(); preview({}, "兼容奖励后切tab保持空态")
                M.onOpen(); preview({}, "兼容奖励后重开保持空态")
            end

            resetFixture()
            cell(9301); cell(9101)
            selected({ 9101, 9301 }, "手选两种品质但各自部分选不亮")
            quality(1); selected({ 9101, 9102, 9301 }, "部分选补选缺失项")
            quality(2); selected({ 9101, 9102, 9201, 9202, 9301 }, "异品质手选保持")
            quality(1); selected({ 9201, 9202, 9301 }, "二次点击仅取消q1")
            quality(1); cell(9101)
            selected({ 9102, 9201, 9202, 9301 }, "手动取消一项顶部q1熄灭")
            quality(1); selected({ 9101, 9102, 9201, 9202, 9301 }, "部分取消后q1回补")
            cell(9302); selected({ 9101, 9102, 9201, 9202, 9301, 9302 }, "手动全选q3自动亮勾")
            cell(9301); quality(3)
            quality(4); quality(5); quality(6)
            selected(allEligible, "六档含至臻红全部选中")
            request(allEligible, "六档含红payload")
            failure(); selected(allEligible, "六档失败保持")
            quality(6)
            selected({ 9101, 9102, 9201, 9202, 9301, 9302, 9401, 9501 }, "二次点击红档取消")
            quality(6); cell(9602); selected(allEligible, "锁定红装格子不可选")
            M.onTabSwitch(); selected({}, "切tab清勾选")
            request({}, "切tab后空选不发送")
            quality(1); M.onOpen(); selected({}, "重新打开清勾选")

            -- 新增排序前插项不继承旧索引；删除/全量新引用后仍按seq保持选择。
            quality(1); quality(2); cell(9301)
            testPDM.equipment.inventory["9000"] = equip(9000, 1)
            testPDM.equipment.inventory["9001"] = equip(9001, 5)
            M.onEquipmentDataUpdate()
            selected({ 9101, 9102, 9201, 9202, 9301 }, "排序前插不误选且q1部分选熄灭")
            quality(1); selected({ 9000, 9101, 9102, 9201, 9202, 9301 }, "新增同品质仅补缺")
            testPDM.equipment.inventory["9101"] = nil
            M.onEquipmentDataUpdate()
            selected({ 9000, 9102, 9201, 9202, 9301 }, "删除后seq重映射稳定")
            testPDM.equipment = copy(testPDM.equipment)
            testPDM.equipment.inventory["8988"] = equip(8988, 6)
            testPDM.equipment.inventory["9000"].locked = true
            testPDM.equipment.inventory["9201"].locked = true
            testPDM.equipment.equipped[3] = { weapon = "9102", offhand = 9301 }
            -- 刻意不调用数据更新，发送前必须主动刷新最新锁定/数字及字符串穿戴。
            request({ 9202 }, "发送前全量更新安全过滤并重映射")
            selected({ 9202 }, "发送前刷新不丢剩余安全项")
            failure(); selected({ 9202 }, "安全过滤后失败保留剩余项")
            testPDM.equipment.inventory["9000"].locked = nil
            testPDM.equipment.inventory["9201"].locked = nil
            testPDM.equipment.equipped[3] = nil
            M.onOpen(); quality(1); quality(2); cell(9301)
            testPDM.equipment = copy(testPDM.equipment)
            testPDM.equipment.inventory["9102"].locked = true
            testPDM.equipment.equipped[3] = { weapon = "9202" }
            M.onEquipmentDataUpdate()
            selected({ 9000, 9201, 9301 }, "推送刷新排除新锁定/字符串穿戴仍保留其他")

            testPDM.equipment = { inventory = { ["9901"] = equip(9901, 1),
                ["9902"] = equip(9902, 6, true), ["9903"] = equip(9903, 6) },
                equipped = { [1] = { weapon = "9903" } }, settings = {} }
            M.onOpen(); cell(9901)
            quality(6); selected({ 9901 }, "红档仅锁装/穿戴视为空不亮不改选择")
            quality(2); selected({ 9901 }, "完全空品质不亮不改其他手选")
            request({ 9901 }, "空品质不会混入payload")
            failure()
            testPDM.equipment.inventory["9901"].locked = true
            request({}, "全部新锁定发送前清空且不发送")
            selected({}, "无可分解项全部顶部不亮")
            testPDM.equipment.inventory["9901"].locked = nil
            M.onEquipmentDataUpdate(); cell(9901)
            request({ 9901 }, "空请求不遗留pending")
            failure()

            -- JSON数字可能为浮点；9101.0/"9101.0"与整数序号必须视为同一装备。
            resetFixture()
            testPDM.equipment.equipped[1].weapon = 9701.0
            testPDM.equipment.equipped[2].weapon = "9702.0"
            M.onEquipmentDataUpdate()
            quality(1); quality(2)
            selected(union, "浮点与小数字符串穿戴排除且不误亮")
            request(union, "浮点穿戴不混入多品质payload")
            failure()
            testPDM.equipment.equipped[3] = { weapon = 9101.0, offhand = "9201.0" }
            request({ 9102, 9202 }, "发送前新增浮点穿戴再次安全排除")
            failure()

            -- 自动分解弹窗仍是单阈值，与顶部手动多选互不干扰。
            resetFixture(); quality(1); quality(2)
            click(310, layout.by, "自动分解按钮")
            check(M.isPopupOpen(), label .. "自动弹窗打开")
            check(M.handlePopupInput(230, 1060), label .. "自动阈值选择q1")
            check(M.handlePopupInput(354, 1060), label .. "自动阈值q2替换q1")
            local autoBefore = #actions
            check(M.handlePopupInput(540, 1330), label .. "自动弹窗保存")
            eq(#actions, autoBefore + 1, label .. "自动设置仅发送一次")
            local auto = actions[#actions]
            eq(auto.action, Protocol.ACTION_TYPES.SET_AUTO_DECOMPOSE, label .. "自动设置独立动作")
            eq(auto.params.autoQuality, 2, label .. "autoQuality保持单数字阈值")
            eq(auto.params.autoLevel, 30, label .. "autoLevel仍为原阈值")
            eq(auto.params.seqs, nil, label .. "自动设置不发送手动多选seq")
            check(not M.isPopupOpen(), label .. "保存后关闭自动弹窗")
            selected(union, "自动阈值保存不改变手动并集")
            click(310, layout.by, "再次打开自动分解")
            check(M.handlePopupInput(850, 1060), label .. "自动红档单阈值可选")
            check(M.handlePopupInput(850, 1060), label .. "自动红档再次点击关闭阈值")
            check(M.handlePopupInput(540, 1330), label .. "保存关闭自动阈值")
            eq(actions[#actions].params.autoQuality, 0, label .. "自动同阈值二次点击仍归零")
            selected(union, "自动阈值取消不清手动选择")

            -- 框选只经过真实公开 API 和真实 drawPanel/奖励预览/请求出口。
            -- 区域跨两行两列：首行9101/9102；次行锁定9203/可选9301。
            -- 既选9501在选区外必须保留；相交有面积，擦边/格隙/空格不选。
            local x1, x2 = layout.gx - 70, layout.gx + layout.gs + 70
            local y1, y2 = layout.gy - 70, layout.gy + layout.gs + 70
            local base, added = { 9501 }, { 9101, 9102, 9301, 9501 }
            local gestureActions, gestureRewards = #actions, #rewards
            for direction, corners in ipairs({ { x1, y1, x2, y2 }, { x2, y1, x1, y2 },
                { x1, y2, x2, y1 }, { x2, y2, x1, y1 } }) do
                resetFixture(); cell(9501)
                check(M.handleMarqueeBegin(corners[1], corners[2]) == true,
                    label .. "四方向" .. direction .. " Begin成功")
                check(M.isMarqueeActive(), label .. "四方向" .. direction .. "已捕获")
                selected(base, "Begin不提前勾选")
                check(M.handleMarqueeMove(corners[3], corners[4]) == true,
                    label .. "四方向" .. direction .. " Move消费")
                selected(added, "四方向" .. direction .. "预览跳锁且追加既选", base)
                preview(base, "框选预览不提前污染已选奖励")
                -- 回到起点后 Move 重算临时集合，而非留下经过格子的历史选择。
                check(M.handleMarqueeMove(corners[1], corners[2]) == true, label .. "回原点仍消费")
                selected(base, "回原点零面积只保留既选", base)
                check(M.handleMarqueeMove(corners[3], corners[4]) == true, label .. "再次展开仍消费")
                check(M.handleMarqueeEnd(corners[3], corners[4]) == true, label .. "四方向End消费")
                check(not M.isMarqueeActive(), label .. "End释放框选")
                selected(added, "四方向" .. direction .. "提交追加并集")
                preview(added, "End后奖励才计入新增装备")
            end
            eq(#actions, gestureActions, label .. "四方向右键只选不分解或设置")
            eq(#rewards, gestureRewards, label .. "四方向右键不弹分解奖励")
            request(added, "四方向提交后必须显式分解按钮发送")
            failure()

            resetFixture(); cell(9501)
            check(M.handleMarqueeBegin(x1, y1), label .. "取消测试Begin")
            M.handleMarqueeMove(x2, y2)
            selected(added, "取消前确有临时预览", base)
            M.cancelMarquee(); M.cancelMarquee()
            check(not M.isMarqueeActive(), label .. "重复取消幂等")
            selected(base, "取消保留按下前选择")
            preview(base, "取消不残留临时奖励")
            check(M.handleMarqueeMove(x2, y2) == false and M.handleMarqueeEnd(x2, y2) == false,
                label .. "取消后旧Move/Up不复活")
            selected(base, "旧Up不追加预览项")
            check(M.handleMarqueeBegin(x1, y1), label .. "刷新测试Begin")
            M.handleMarqueeMove(x2, y2)
            testPDM.equipment = copy(testPDM.equipment)
            testPDM.equipment.inventory["8999"] = equip(8999, 6)
            M.onEquipmentDataUpdate()
            check(not M.isMarqueeActive() and not M.handleMarqueeEnd(x2, y2),
                label .. "全量刷新永久取消旧框选")
            selected(base, "刷新只按seq保留之前选择且不误选前插项")
            preview(base, "刷新保留原选择奖励")
            request(base, "刷新不把临时预览混入payload")
            failure()
            for _, updateKind in ipairs({ "reference", "revision" }) do
                resetFixture(); cell(9401); cell(9501)
                check(M.handleMarqueeBegin(x1, y1), label .. updateKind .. "未通知刷新Begin")
                M.handleMarqueeMove(x2, y2)
                if updateKind == "reference" then testPDM.equipment = copy(testPDM.equipment) end
                testPDM.equipment.inventory["9101"].locked = true
                testPDM.equipment.inventory["9401"].locked = true
                testPDM.equipment.equipped[3] = { weapon = "9102.0" }
                if updateKind == "revision" then equipmentRevision = equipmentRevision + 1 end
                -- 不主动调onEquipmentDataUpdate，依赖真实模块观测引用/revision。
                check(not M.handleMarqueeMove(x2, y2) and not M.isMarqueeActive(),
                    label .. updateKind .. "真实数据变化Move立即取消")
                check(not M.handleMarqueeEnd(x2, y2), label .. updateKind .. "旧Up不能提交过时选区")
                selected({ 9501 }, updateKind .. "只按seq保留之前仍安全选择")
                preview({ 9501 }, updateKind .. "安全重映射后真实预览")
                request({ 9501 }, updateKind .. "最新锁定穿戴不混入payload")
                failure()
            end

            resetFixture()
            local beforeSingle = #actions
            for _, expected in ipairs({ { 9101 }, {} }) do
                check(M.handleMarqueeBegin(layout.gx, layout.gy), label .. "静止右键Begin")
                check(M.handleMarqueeEnd(layout.gx, layout.gy), label .. "静止右键End")
                selected(expected, "无拖拽右键单格切换")
            end
            local gapX = layout.gx + 80 + (layout.gs - 160) * 0.5
            check(M.handleMarqueeBegin(gapX, layout.gy), label .. "格隙静止右键可开始")
            check(M.handleMarqueeEnd(gapX, layout.gy), label .. "格隙静止右键消费")
            selected({}, "格隙无单格选择")
            check(M.handleMarqueeBegin(layout.gx + 2 * layout.gs, layout.gy), label .. "锁格右键Begin")
            check(M.handleMarqueeEnd(layout.gx + 2 * layout.gs, layout.gy), label .. "锁格右键End")
            selected({}, "锁格右键不选")
            eq(#actions, beforeSingle, label .. "静止右键不执行分解")
            -- 缝隙垂直矩形不碰任何格；贴着首格右边界向缝内拖不算擦边。
            for _, edgeX in ipairs({ layout.gx + 80, gapX }) do
                check(M.handleMarqueeBegin(edgeX, y1), label .. "格边矩形Begin")
                M.handleMarqueeMove(gapX + 1, y2)
                check(M.handleMarqueeEnd(gapX + 1, y2), label .. "格边矩形End")
                selected({}, "格隙与擦边均无相交面积")
            end
            local gridBottom = profile == "warehouse" and 1980 or 2025
            for _, point in ipairs({ { layout.gx - 81, layout.gy }, { 1011, layout.gy },
                { layout.gx, layout.gy - 81 }, { layout.gx, gridBottom + 1 },
                { 773, layout.by }, { layout.qx, layout.qy } }) do
                check(M.handleMarqueeBegin(point[1], point[2]) == false,
                    label .. "非网格Begin拒绝 " .. point[1] .. "," .. point[2])
                check(not M.isMarqueeActive(), label .. "非网格没有遗留capture")
            end

            resetFixture(); cell(9501)
            check(M.handleMarqueeBegin(x1, y1), label .. "本页自动弹窗前Begin")
            M.handleMarqueeMove(x2, y2); M.openAutoPopup()
            check(M.isPopupOpen() and not M.isMarqueeActive(), label .. "本页弹窗取消框选")
            check(not M.handleMarqueeBegin(x1, y1) and not M.handleMarqueeEnd(x2, y2),
                label .. "本页弹窗拒绝新旧右键")
            check(M.handlePopupInput(540, 1330), label .. "关闭真实自动弹窗")
            selected(base, "弹窗关闭后不复活临时选择")
            request(base, "pending测试原选择发送")
            check(not M.handleMarqueeBegin(x1, y1), label .. "pending分解不启动框选")
            failure()
            for _, blocked in ipairs({ "pinned", "point", "owner" }) do
                detailState.open, detailState.pinned, detailState.point = true, false, false
                detailState.owner = profile == "warehouse" and "backpack" or "smith"
                if blocked == "owner" then detailState.owner = "other"
                else detailState[blocked] = true end
                check(not M.handleMarqueeBegin(x1, y1), label .. "详情" .. blocked .. "拒绝框选")
                detailState.open, detailState.pinned, detailState.point = false, false, false
            end
            detailState.owner = profile == "warehouse" and "backpack" or "smith"
            detailState.open = true
            local dismissBefore = detailState.dismisses
            check(M.handleMarqueeBegin(x1, y1), label .. "同宿主未钉住hover允许开始")
            eq(detailState.dismisses, dismissBefore + 1, label .. "开始先关闭同宿主hover")
            local opensBefore = detailState.opens
            M.handleHover(layout.gx, layout.gy); time.elapsedTime = time.elapsedTime + 0.5
            M.handleHover(layout.gx, layout.gy); M.drawPanel({})
            eq(detailState.opens, opensBefore, label .. "框选期间hover及长按不打开详情")
            M.handleMarqueeMove(x2, y2)
            detailState.open = true
            check(not M.handleMarqueeMove(x2, y2) and not M.isMarqueeActive(),
                label .. "途中详情模态取消框选")
            detailState.open = false
            check(not M.handleMarqueeEnd(x2, y2), label .. "详情关闭后旧Up仍不复活")
            selected(base, "详情取消保留之前选择")

            -- 50件跨十行：只选可见格；仓库整八行，旧smith第五行后部分格裁剪。
            resetFixture()
            testPDM.equipment = { inventory = {}, equipped = { [1] = { weapon = "8050.0" } }, settings = {} }
            for index = 1, 50 do
                testPDM.equipment.inventory[tostring(8000 + index)] = equip(8000 + index, 1, index == 2)
            end
            M.onOpen()
            for _, scroll in ipairs({ 0, 100 }) do
                if scroll > 0 then M.handleScroll(-1, layout.gx, layout.gy) end
                local visible = {}
                for index = 1, 49 do
                    local cy = layout.gy + math.floor((index - 1) / 5) * layout.gs - scroll
                    local height = math.min(cy + 80, gridBottom) - math.max(cy - 80, layout.gy - 80)
                    if height > 8 and index ~= 2 then visible[#visible + 1] = 8000 + index end
                end
                check(#visible > 0 and #visible < 49, label .. "可见oracle不等于全库存")
                check(M.handleMarqueeBegin(80, layout.gy - 80), label .. "裁剪边缘Begin")
                local topCell = M.peekCellAt(layout.gx, layout.gy - 79)
                M.handleScroll(-1, layout.gx, layout.gy)
                eq(M.peekCellAt(layout.gx, layout.gy - 79), topCell, label .. "框选期间滚轮不改可见坐标")
                check(M.handleMarqueeEnd(3000, 4000), label .. "跨栏及按钮区End仍由原网格裁剪")
                request(visible, "可见格裁剪scroll=" .. scroll)
                failure()
                -- 单格取消所有已选，下一轮追加不携带上一轮已选的出屏项。
                M.onOpen()
            end
            -- 部分露出<=8px沿用原点击不可选；超过8px可选，不选择完全出屏格。
            if profile == "warehouse" then
                for _, row in ipairs({ { 152, {} }, { 151, { 8001 } } }) do
                    M.onOpen()
                    M.handleDragBegin(-1, 0); M.handleDragMove(-1, -row[1]); M.handleDragEnd(-1, -row[1])
                    check(M.handleMarqueeBegin(layout.gx - 70, layout.gy - 80), label .. "8px裁剪边界Begin")
                    check(M.handleMarqueeEnd(layout.gx + 70, layout.gy - 64), label .. "8px裁剪边界End")
                    request(row[2], "可见高度" .. (160 - row[1]) .. "px严格沿用原点击阈值")
                    failure()
                end
                M.onOpen()
                M.handleScroll(-12, layout.gx, layout.gy) -- 第七行顶部仍露出100px，前六行完全出屏。
                local clipped = M.peekCellAt(layout.gx, layout.gy - 79)
                check(clipped ~= nil, label .. "滚动顶部确有部分可见格")
                check(M.handleMarqueeBegin(layout.gx - 70, layout.gy - 79), label .. "部分可见格Begin")
                check(M.handleMarqueeEnd(layout.gx + 70, layout.gy - 65), label .. "部分可见格End")
                request(clipped and { clipped.seq } or {}, "裁剪顶部只命中部分可见格")
                failure(); M.onOpen()
            end

            -- 原触摸/左键语义：短按切换，拖动滚动且取消长按，长按详情不勾选。
            resetFixture()
            M.handleDragBegin(layout.gx, layout.gy)
            M.handleDragEnd(layout.gx, layout.gy)
            cell(9101); selected({ 9101 }, "原短按仍单格切换")
            M.handleDragBegin(layout.gx, layout.gy)
            M.handleDragMove(layout.gx, layout.gy - 100)
            M.handleDragEnd(layout.gx, layout.gy - 100)
            eq(M.peekCellAt(layout.gx, layout.gy - 79).seq, 9101, label .. "原拖动滚动后顶部部分格")
            local touchOpens = detailState.opens
            time.elapsedTime = time.elapsedTime + 0.5; M.drawPanel({})
            eq(detailState.opens, touchOpens, label .. "原触摸移动超限取消长按")
            resetFixture()
            M.handleDragBegin(layout.gx, layout.gy)
            time.elapsedTime = time.elapsedTime + 0.5; M.drawPanel({})
            eq(detailState.opens, touchOpens + 1, label .. "原触摸长按仍打开详情一次")
            M.handleDragEnd(layout.gx, layout.gy)
            detailState.open = false
            M.handleInput(layout.gx, layout.gy)
            selected({}, "原长按释放不额外勾选")
            resetFixture()
        end

        -- 真实仓库Panel仅薄转发：验证宿主模式/页签/动画/本页modal与关闭取消。
        -- 初始化只替换资源及声音边界，分解模块和equipLink仍是真实实例。
        local Panel = require("ui.backpack.BackpackPanel")
        local GameSFX = require("systems.GameSFX")
        local ImageCache = require("ui.widget.ImageCache")
        local SetFilter = require("ui.widget.SetFilterDialog")
        patch(GameSFX, "playUIMove", function() end)
        patch(ImageCache, "init", function() end)
        Panel.init({})
        resetFixture()
        Panel.open("left", "decompose")
        check(not Panel.canMarquee() and not Panel.handleMarqueeBegin(90, 480),
            "真实Panel打开动画期间不允许框选未绘制位置")
        time.elapsedTime = time.elapsedTime + 0.5
        check(Panel.canMarquee(), "真实Panel稳定左栏分解页允许框选")
        check(Panel.handleMarqueeBegin(90, 480) == true and M.isMarqueeActive() and Panel.isMarqueeActive(),
            "真实Panel Begin薄转发到同一Decompose实例")
        check(Panel.handleMarqueeMove(420, 810) == true, "真实Panel Move薄转发")
        check(Panel.handleMarqueeEnd(420, 810) == true and not M.isMarqueeActive(), "真实Panel End薄转发")
        local forwardedActions = #actions
        check(Panel.handleInput(773, 2160), "真实Panel显式分解按钮沿原路径")
        eq(#actions, forwardedActions + 1, "真实Panel框选只在显式按钮后发一次分解")
        eq(signature(actions[#actions].params.seqs), signature({ 9101, 9102, 9301 }),
            "真实Panel并集payload跳锁/已穿戴")
        M.onActionResult({ action = Protocol.ACTION_TYPES.DECOMPOSE_EQUIP, success = false })
        check(Panel.handleMarqueeBegin(90, 480), "真实Panel取消转发前Begin")
        Panel.cancelMarquee(); Panel.cancelMarquee()
        check(not Panel.isMarqueeActive() and not M.isMarqueeActive() and not Panel.handleMarqueeEnd(420, 810),
            "真实Panel重复取消与旧End不复活")
        check(Panel.handleMarqueeBegin(90, 480), "真实Panel自动popup前Begin")
        M.openAutoPopup()
        check(not Panel.canMarquee() and not Panel.handleMarqueeMove(420, 810),
            "真实Panel本页自动modal阻止can/Move")
        check(M.handlePopupInput(540, 1330), "真实Panel关闭自动modal")
        check(not Panel.handleMarqueeEnd(420, 810), "真实Panel自动modal关闭不复活旧End")
        local filterOpen = false
        patch(SetFilter, "isOpen", function() return filterOpen end)
        check(Panel.handleMarqueeBegin(90, 480), "真实Panel套装modal前Begin")
        filterOpen = true
        check(not Panel.canMarquee() and not Panel.handleMarqueeEnd(420, 810) and not M.isMarqueeActive(),
            "真实Panel套装筛选modal取消End")
        filterOpen = false
        check(Panel.handleMarqueeBegin(90, 480), "真实Panel切页前Begin")
        check(Panel.handleInput(274, 2308), "真实Panel原装备页签点击")
        check(not Panel.canMarquee() and not M.isMarqueeActive() and not Panel.handleMarqueeEnd(420, 810),
            "真实Panel切equip页永久取消分解框选")
        for _, mode in ipairs({ true, false }) do
            Panel.open(mode, "decompose"); time.elapsedTime = time.elapsedTime + 0.5
            check(not Panel.canMarquee() and not Panel.handleMarqueeBegin(90, 480),
                "真实Panel非left宿主不允许框选 mode=" .. tostring(mode))
        end
        Panel.open("left", "decompose"); time.elapsedTime = time.elapsedTime + 0.5
        check(Panel.handleMarqueeBegin(90, 480), "真实Panel关闭前Begin")
        Panel.close()
        check(not Panel.canMarquee() and not M.isMarqueeActive() and not Panel.handleMarqueeEnd(420, 810),
            "真实Panelclose立即取消不等动画完成")
        time.elapsedTime = time.elapsedTime + 0.5; Panel.update(0)
        check(not Panel.isOpen(), "真实Panel关闭动画完成")
    end)
    -- 无论断言或真实模块抛错，先恢复全部替身，沿用原PDM恢复方式。
    for index = #patches, 1, -1 do
        local saved = patches[index]
        saved.target[saved.key] = saved.value
    end
    for _, key in ipairs(globalKeys) do _G[key] = globals[key] end
    check(ok, "手动分解六品质并集/状态/真实服务回归: " .. tostring(err))
end

function Start()
    print(PREFIX .. "start")

    -- ========== 1) 共享判定语义 ==========
    check(BC.shouldAutoDecompose(nil, 1, 1) == false, "settings=nil 不分解")
    check(BC.shouldAutoDecompose({}, 1, 1) == false, "双0（未设置）不分解")
    check(BC.shouldAutoDecompose({ autoQuality = 0, autoLevel = 0 }, 6, 60) == false, "显式双0不分解")
    -- 单维启用：另一维 0 = 不限制
    check(BC.shouldAutoDecompose({ autoQuality = 2, autoLevel = 0 }, 2, 60) == true, "仅品质启用：q<=阈值 分解")
    check(BC.shouldAutoDecompose({ autoQuality = 2, autoLevel = 0 }, 3, 1) == false, "仅品质启用：q>阈值 不分解")
    check(BC.shouldAutoDecompose({ autoQuality = 0, autoLevel = 30 }, 6, 30) == true, "仅等级启用：lv<=阈值 分解")
    check(BC.shouldAutoDecompose({ autoQuality = 0, autoLevel = 30 }, 1, 31) == false, "仅等级启用：lv>阈值 不分解")
    -- 双维 AND
    check(BC.shouldAutoDecompose({ autoQuality = 3, autoLevel = 40 }, 3, 40) == true, "双维边界(=阈值) 分解")
    check(BC.shouldAutoDecompose({ autoQuality = 3, autoLevel = 40 }, 4, 1) == false, "品质超阈 不分解")
    check(BC.shouldAutoDecompose({ autoQuality = 3, autoLevel = 40 }, 1, 41) == false, "等级超阈 不分解")
    -- 至臻档（修复前钳 5 导致永不分解）
    check(BC.shouldAutoDecompose({ autoQuality = 6, autoLevel = 0 }, 6, 60) == true, "至臻(6)档可分解至臻掉落")
    -- 字符串容错
    check(BC.shouldAutoDecompose({ autoQuality = "3", autoLevel = "40" }, 3, 40) == true, "字符串设置 tonumber 容错")
    check(BC.shouldAutoDecompose({ autoQuality = "abc", autoLevel = nil }, 1, 1) == false, "非法设置视为未启用")

    -- ========== 2) 精粹公式与手动分解一致 ==========
    local qCost3 = BC.QUALITY_COST[3]
    local expect3 = math.floor(qCost3.decBase * (1 + 25 * qCost3.decScale))
    eq(BC.calcAutoDecomposeEssence(3, 25), expect3, "自动分解精粹=手动基础公式 q3 lv25")
    eq(BC.calcAutoDecomposeEssence(9, 1), BC.calcAutoDecomposeEssence(1, 1), "越界品质回退 q1 公式")

    -- ========== 3) 通知记录 ==========
    local lootbox = { seeds = {} }
    BC.recordAutoDecompose(lootbox, 2, 10, 12)
    BC.recordAutoDecompose(lootbox, 3, 20, 17)
    local n = lootbox.autoDecomposeNotice
    check(n ~= nil, "notice 已创建")
    eq(n.seq, 2, "notice.seq 递增")
    eq(n.count, 2, "notice.count 累计")
    eq(n.essence, 29, "notice.essence 累计")
    eq(n.quality, 3, "notice.quality 为最近一次")
    check(type(n.time) == "number" and n.time > 0, "notice.time 时间戳存在")

    -- ========== 4) 服务端钳制（真实 PDM 注入） ==========
    local PDM = require("rules.character.PlayerDataManager")
    local oldGetModule, oldMarkDirty = PDM.GetModule, PDM.MarkDirty
    local equipment = { inventory = {}, equipped = {}, settings = {} }
    local currency = { essence = 0 }
    PDM.GetModule = function(_, name)
        return ({ equipment = equipment, currency = currency })[name]
    end
    local dirty = {}
    PDM.MarkDirty = function(_, fieldKey) dirty[fieldKey] = (dirty[fieldKey] or 0) + 1 end

    local EquipmentService = require("rules.equipment.EquipmentService")
    local ok1, _, cq, cl = EquipmentService.SetAutoDecompose(1, 9, 999)
    check(ok1 == true, "SetAutoDecompose 成功")
    eq(cq, 6, "品质钳制上限 6（至臻）")
    eq(cl, 60, "等级钳制上限 60")
    eq(equipment.settings.autoQuality, 6, "存储值为钳制后品质")
    eq(equipment.settings.autoLevel, 60, "存储值为钳制后等级")
    local ok2, _, cq2, cl2 = EquipmentService.SetAutoDecompose(1, -5, -1)
    check(ok2 == true and cq2 == 0 and cl2 == 0, "负值钳制为 0（关闭）")

    -- ========== 5) DecomposeEquip 重复 seq 防刷 ==========
    local EquipmentSystem = require("systems.EquipmentSystem")
    local equipA = EquipmentSystem.generateRandom(10, 2)
    local equipB = EquipmentSystem.generateRandom(10, 2)
    check(equipA ~= nil and equipB ~= nil, "测试装备生成成功")
    equipA.seq, equipB.seq = 9001, 9002
    equipment.inventory = { ["9001"] = equipA, ["9002"] = equipB }
    equipment.equipped = {}
    currency.essence = 0

    local BS = require("rules.blacksmith.BlacksmithService")
    -- 重复 seq：必须拒绝且不发奖
    local dupOk, dupErr = BS.DecomposeEquip(1, { 9001, 9001, 9001 })
    check(dupOk == false, "重复 seq 被拒绝: " .. tostring(dupErr))
    eq(currency.essence, 0, "重复 seq 不发精粹")
    eq(equipment.inventory["9001"] ~= nil, true, "重复 seq 不删库存")

    -- 正常分解两件：奖励 = 两件基础公式和，库存清空
    local qA, lvA = equipA.quality or 1, equipA.level or 1
    local qB, lvB = equipB.quality or 1, equipB.level or 1
    local expectSum = BC.calcAutoDecomposeEssence(qA, lvA) + BC.calcAutoDecomposeEssence(qB, lvB)
    local normOk, normErr, res = BS.DecomposeEquip(1, { 9001, 9002 })
    check(normOk == true, "正常分解成功: " .. tostring(normErr))
    eq(res.decomposeCount, 2, "分解数量 2")
    eq(res.essenceReward, expectSum, "精粹奖励=两件基础和（无洗练/升阶投入）")
    eq(currency.essence, expectSum, "货币入账正确")
    eq(equipment.inventory["9001"], nil, "库存删除 9001")
    eq(equipment.inventory["9002"], nil, "库存删除 9002")

    -- ========== 6) 真实获取链路：只控制 RNG，不替换掉落/生成算法 ==========
    local EC = require("config.EquipmentConfig")
    local SC = require("config.StageConfig")
    local MC = require("config.MonsterConfig")
    local DropSystem = require("systems.DropSystem")
    local OfflineCalc = require("systems.OfflineCalc")
    local oldRandom = math.random
    math.random = function(minValue, maxValue)
        if minValue == nil then return 0 end
        return maxValue or minValue
    end
    local dropOk, dropErr = pcall(function()
        eq(EC.QUALITY[6].name, "至臻", "红装品质名称为至臻")
        eq(EC.QUALITY[6].color, "ff0000", "第6档使用红色")
        eq(EquipmentSystem.rollQuality(), 6, "生成器随机候选包含第6档")

        local slotSeen = {}
        for _, template in pairs(EC.ITEMS) do
            if not slotSeen[template.slot] then
                local equip = EquipmentSystem.generate(template.id, template.levelRange[1], 6)
                check(equip ~= nil and equip.quality == 6, template.slot .. "可生成红装")
                slotSeen[template.slot] = true
            end
        end
        for _, slot in ipairs(EC.SLOTS) do
            check(slotSeen[slot] == true, "红装生成覆盖部位 " .. slot)
        end

        for _, fixture in ipairs({ { 105, 4 }, { 2405, 5 }, { 4705, 6 }, { 7005, 6 } }) do
            local stage = assert(SC.getStage(fixture[1]), "真实关卡夹具不存在")
            local equip = DropSystem.generateKillDrop(stage)
            eq(equip and equip.quality, fixture[2], "真实击杀掉落品质边界 stage=" .. fixture[1])
        end
        eq(OfflineCalc._rollQualityByMonster(5), 6, "传说怪物离线随机池包含红装")
        eq(OfflineCalc._rollQualityByMonster(6), 6, "至臻怪物离线随机池包含红装")

        local nightmare = assert(SC.getStage(4705))
        eq(MC.MONSTERS[nightmare.bossId].quality, 5, "噩梦1-5 Boss 为传说品质")
        local kills = math.ceil((#nightmare.monsters + 1) / nightmare.dropRate)
        local seeds = OfflineCalc.buildEquipSeeds(kills, nightmare, SC)
        local redSeed = false
        for _, seed in ipairs(seeds) do
            if seed.quality == 6 and seed.count > 0 then redSeed = true end
        end
        check(redSeed, "真实噩梦关卡离线掉落种子保留红装")
        local early = DropSystem.generateKillDrop(assert(SC.getStage(4701)))
        check(early ~= nil and early.quality < 6, "噩梦1-1的怪物池没有红装权重，开放上限不等于必出")

        local firstClear = assert(SC.getStage(11201))
        local rewards = DropSystem.generateFirstClearEquips(firstClear)
        eq(#rewards, firstClear.fcEquip, "真实炼狱首通装备数量正确")
        check(#rewards > 0, "真实炼狱首通有装备奖励")
        for _, equip in ipairs(rewards) do
            eq(equip.quality, 6, "真实炼狱首通最低品质可直接产出红装")
        end

        local redDrop = assert(DropSystem.generateKillDrop(nightmare))
        check(not BC.shouldAutoDecompose({ autoQuality = 5, autoLevel = 0 }, redDrop.quality, redDrop.level),
            "实际红色掉落在仅自动分解传说及以下时保留")
        check(BC.shouldAutoDecompose({ autoQuality = 6, autoLevel = 0 }, redDrop.quality, redDrop.level),
            "实际红色掉落在自动分解至臻时会被分解")

        math.random = function() return 0.999999 end
        eq(DropSystem.generateKillDrop(nightmare), nil, "未命中掉落概率时不生成装备")
    end)
    math.random = oldRandom
    check(dropOk, "真实红装获取定向回归: " .. tostring(dropErr))

    -- ========== 7) 点金石正式服务路径：直接提品并保存，不需要手动替换 ==========
    local oldFlush = PDM.FlushImmediate
    local TaskService = require("rules.task.TaskService")
    local oldProgress = TaskService.UpdateProgress
    local flushCount = 0
    PDM.FlushImmediate = function() flushCount = flushCount + 1 end
    TaskService.UpdateProgress = function() end
    local battle = { maxStageId = 4701 }
    PDM.GetModule = function(_, name)
        return ({ equipment = equipment, currency = currency, battle = battle })[name]
    end
    local upgradeOk, upgradeErr = pcall(function()
        local legendary = assert(EquipmentSystem.generate("W1", 10, 5))
        legendary.seq = 9010
        EquipmentSystem.hydrate(legendary)
        equipment.inventory["9010"] = legendary
        currency.destroyStone = 20
        local equipmentDirtyBefore = dirty.equipment or 0
        local currencyDirtyBefore = dirty.currency or 0
        local previewOk, previewErr, preview = BS.RefineEquip(1, 9010, "destroyStone")
        check(previewOk, "噩梦进度允许点金石提品: " .. tostring(previewErr))
        eq(flushCount, 1, "点金石提品请求立即保存")
        eq(dirty.equipment, equipmentDirtyBefore + 1, "点金石提品标脏装备")
        eq(dirty.currency, currencyDirtyBefore + 1, "点金石消耗标脏货币")
        eq(preview and preview.upgradedQuality, 6, "点金石返回目标品质=至臻")
        check(preview and preview.autoReplaced == true, "点金石提品直接应用，不需要手动替换")
        eq(currency.destroyStone, 15, "传说提至臻消耗5个点金石")
        eq(legendary.quality, 6, "点金石调用后库存装备真正变为红装")
        local replaceOk = BS.RefineReplace(1, 9010)
        check(not replaceOk, "点金石直接应用后不遗留待替换预览")
        eq(legendary.quality, 6, "重复确认不会丢失至臻品质")
        local restored = EquipmentSystem.hydrate(EquipmentSystem.dehydrate(legendary))
        eq(restored.quality, 6, "点金石红装脱水/水合品质不丢")

        battle.maxStageId = 2401
        local hardEquip = assert(EquipmentSystem.generate("W1", 10, 5))
        hardEquip.seq = 9011
        EquipmentSystem.hydrate(hardEquip)
        hardEquip.affixes[1].quality = 1
        hardEquip.affixes[2].quality = 5
        equipment.inventory["9011"] = hardEquip
        local hardOk, hardErr, hardPreview = BS.RefineEquip(1, 9011, "destroyStone")
        check(hardOk, "困难进度点金石仍可提高普通词条品级: " .. tostring(hardErr))
        eq(hardPreview and hardPreview.upgradedQuality, nil, "困难进度不越界提到红装")
        check(hardPreview and hardPreview.autoReplaced == true, "困难进度词条提品直接应用")
        eq(hardEquip.affixes[1].quality, 2, "困难进度点金石提高普通词条品级")
        eq(hardEquip.quality, 5, "困难进度操作后仍为传说装备")
    end)
    PDM.FlushImmediate = oldFlush
    TaskService.UpdateProgress = oldProgress
    PDM.GetModule, PDM.MarkDirty = oldGetModule, oldMarkDirty
    check(upgradeOk, "点金石真实红装获取回归: " .. tostring(upgradeErr))

    -- ========== 8) 仓库/铁匠手动分解顶部六品质多选 ==========
    testRarityMultiselect()

    -- ========== 汇总 ==========
    if #failures > 0 then
        print(PREFIX .. "RESULT FAIL " .. #failures)
        for _, f in ipairs(failures) do print(PREFIX .. "  - " .. f) end
        error(PREFIX .. #failures .. " assertions failed")
    end
    print(PREFIX .. "RESULT ALL PASS")
    engine:Exit()
end
