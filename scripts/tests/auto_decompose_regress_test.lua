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
        local actions, rewards, dirty, progress = {}, {}, {}, {}
        local testPDM = { equipment = {}, currency = { essence = 0 } }
        patch(PlayerStore, "Get", function(name) return testPDM[name] end)
        patch(PDM, "GetModule", function(_, name) return testPDM[name] end)
        patch(PDM, "MarkDirty", function(_, name) dirty[name] = (dirty[name] or 0) + 1 end)
        patch(TaskService, "UpdateProgress", function(_, name, count)
            progress[name] = (progress[name] or 0) + count
        end)
        patch(GameAction, "sendAction", function(action, params)
            actions[#actions + 1] = { action = action, params = copy(params) }
            return true
        end)
        patch(Detail, "isOpen", function() return false end)
        patch(RewardPopup, "show", function(title, items)
            rewards[#rewards + 1] = { title = title, items = copy(items) }
        end)
        -- 不播放音效/启动按钮动画，保留真实 drawPanel、DrawUtil 与品质图绘制。
        patch(BF, "trigger", function() end)
        patch(BF, "begin", function() return false end)
        patch(BF, "finish", function() end)
        patch(SetIcon, "isEnabled", function() return false end)
        patch(QualityMark, "get", function(quality) return 72000 + math.floor(quality) end)
        patchGlobal("time", { elapsedTime = 100 })
        local checkImage = 73000
        local paints = {}
        local function noop() end
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgRoundedRectVarying",
            "nvgFill", "nvgStroke", "nvgStrokeColor", "nvgStrokeWidth", "nvgMoveTo", "nvgLineTo",
            "nvgClosePath", "nvgCircle", "nvgEllipse", "nvgBezierTo", "nvgQuadTo", "nvgArc",
            "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgTranslate", "nvgScale", "nvgRotate",
            "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgFillColor", "nvgText", "nvgLineCap" }) do
            patchGlobal(name, noop)
        end
        patchGlobal("nvgRGBA", function(r, g, b, a) return { r = r, g = g, b = b, a = a } end)
        patchGlobal("nvgLinearGradient", function() return {} end)
        patchGlobal("nvgRadialGradient", function() return {} end)
        patchGlobal("nvgTextBounds", function(_, _, _, text) return #text * 14 end)
        patchGlobal("nvgImagePattern", function(_, x, y, w, h, _, image, alpha)
            return { image = image, cx = x + w * 0.5, cy = y + h * 0.5, alpha = alpha }
        end)
        patchGlobal("nvgFillPaint", function(_, paint)
            if paint.image then paints[#paints + 1] = paint end
        end)
        -- 同一真实模块实例通过 onOpen/resetFixture 重置，不依赖加载缓存隔离。
        local M = require("ui.blacksmith.BlacksmithDecompose")
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
                    for _, seq in pairs(slots) do result[tostring(seq)] = true end
                end
                return result
            end
            -- 顶部六坐标与格子坐标分别捕获，不把格子对勾误算为顶部品质对勾。
            local function selected(expected, text)
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
                for _, seq in ipairs(expected) do wanted[tostring(seq)] = true end
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
            resetFixture()
            selected({}, "打开清空")
            local rewardBefore = #rewards
            quality(1); selected({ 9101, 9102 }, "q1选择全部未锁未装")
            quality(2); selected({ 9101, 9102, 9201, 9202 }, "q2保留q1")
            local union = { 9101, 9102, 9201, 9202 }
            request(union, "首次并集发送")
            local pendingCount = #actions
            click(773, layout.by, "pending重复分解")
            eq(#actions, pendingCount, label .. "pending阻止重复请求")
            M.onActionResult({ action = Protocol.ACTION_TYPES.TOGGLE_EQUIP_LOCK,
                decomposed = true, essenceReward = 99 })
            selected(union, "无关成功回执保留")
            eq(#rewards, rewardBefore, label .. "无关回执不弹分解奖励")
            click(773, layout.by, "无关回执后重复分解")
            eq(#actions, pendingCount, label .. "无关回执不提前释放pending")
            failure(); selected(union, "失败回执保留勾选")
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
                    eq(#rewards, rewardBefore + 1, label .. "成功奖励仅弹一次")
                    cell(9301); selected({ 9301 }, "成功后可手选其他品质")
                    M.onActionResult(result)
                    selected({ 9301 }, "非pending重复成功不误清新选择")
                    eq(#rewards, rewardBefore + 1, label .. "重复回执不重复弹奖")
                end
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
        end
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
