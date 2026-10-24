-- advancement_fusion_ui_test.lua
-- 独立 Runtime：真实职业/转职配置与真实 ChurchClassChange 绘制和点击回归。
-- 只替换绘图后端、角色存档边界及动作发送；不替换配置，不读写玩家 File。
-- ./.cli/UrhoXRuntime tests/advancement_fusion_ui_test.lua -tapcode_dir=. -tool_mode -graphicsheadless

local failures, passes = {}, 0
local function check(ok, label)
    if ok then passes = passes + 1; print("[PASS] " .. label)
    else failures[#failures + 1] = label; print("[FAIL] " .. label) end
end

function Start()
    local globals, stubs = {}, {}
    local originalRequire = require
    local function swap(name, value)
        globals[#globals + 1] = { name = name, value = rawget(_G, name) }
        rawset(_G, name, value)
    end
    local function module(name, value)
        rawset(stubs, name, value)
    end
    local function restore()
        for i = #globals, 1, -1 do rawset(_G, globals[i].name, globals[i].value) end
    end
    local ok, err = xpcall(function()
        -- UrhoX 的自定义 require 不一定读取标准 package.loaded，边界必须在 require 入口拦截。
        swap("require", function(name)
            local stub = rawget(stubs, name)
            if stub then return stub end
            return originalRequire(name)
        end)
        swap("File", function() error("UI test must not access player File") end)
        local clock = { elapsedTime = 100 }
        swap("time", clock)
        local CC = require("config.ClassConfig")
        local AVC = require("config.AdvancementConfig")
        local HC = require("config.HeroConfig")
        local Protocol = require("shared.Protocol")
        check(type(AVC.isParentBranch) == "function", "真实配置提供双父前置 API")
        assert(AVC.isParentBranch, "等待融合配置完成，不能用 stub 配置代替")

        local state = { x = 0, y = 0, scale = 1, font = 36, clip = nil,
            color = {}, path = nil, paint = nil, stack = {}, images = {}, rects = {}, texts = {} }
        local loads, handles, actions, buttons = {}, {}, {}, {}
        local own = { level = 100, advBranch = nil }
        local gold = 10000000
        local function noop() end
        local function transform(x, y) return state.x + x * state.scale, state.y + y * state.scale end
        local function recordRect(x, y, w, h)
            local sx, sy = transform(x, y)
            return { x = sx, y = sy, w = w * state.scale, h = h * state.scale }
        end
        local function intersect(a, b)
            if not a then return b end
            local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
            return { x = x, y = y, w = math.max(0, math.min(a.x + a.w, b.x + b.w) - x),
                h = math.max(0, math.min(a.y + a.h, b.y + b.h) - y) }
        end
        for _, name in ipairs({ "nvgFontFace", "nvgTextAlign", "nvgStrokeColor", "nvgStrokeWidth",
            "nvgStroke", "nvgGlobalAlpha", "nvgSkewX", "nvgCircle" }) do swap(name, noop) end
        swap("nvgRGBA", function(r, g, b, a) return { r = r, g = g, b = b, a = a } end)
        swap("nvgSave", function()
            state.stack[#state.stack + 1] = { x = state.x, y = state.y, scale = state.scale, clip = state.clip }
        end)
        swap("nvgRestore", function()
            local s = assert(table.remove(state.stack), "unbalanced render restore")
            state.x, state.y, state.scale, state.clip = s.x, s.y, s.scale, s.clip
        end)
        swap("nvgTranslate", function(_, x, y)
            state.x, state.y = state.x + x * state.scale, state.y + y * state.scale
        end)
        swap("nvgScale", function(_, x) state.scale = state.scale * x end)
        swap("nvgScissor", function(_, x, y, w, h) state.clip = recordRect(x, y, w, h) end)
        swap("nvgIntersectScissor", function(_, x, y, w, h)
            state.clip = intersect(state.clip, recordRect(x, y, w, h))
        end)
        swap("nvgResetScissor", function() error("tree must preserve host scissor") end)
        swap("nvgBeginPath", function() state.path, state.paint = nil, nil end)
        swap("nvgRect", function(_, x, y, w, h) state.path = recordRect(x, y, w, h) end)
        swap("nvgRoundedRect", function(_, x, y, w, h) state.path = recordRect(x, y, w, h) end)
        swap("nvgFillColor", function(_, c) state.color = c end)
        swap("nvgFillPaint", function(_, p) state.paint = p end)
        swap("nvgRadialGradient", function() return { glow = true } end)
        swap("nvgImagePattern", function(_, _, _, _, _, _, handle, alpha)
            return { handle = handle, alpha = alpha }
        end)
        swap("nvgFill", function()
            if not state.path then return end
            local r = state.path
            if state.paint and state.paint.handle then
                state.images[#state.images + 1] = { rect = r, path = handles[state.paint.handle], alpha = state.paint.alpha, clip = state.clip }
            elseif not state.paint then
                state.rects[#state.rects + 1] = { rect = r, color = state.color }
            end
        end)
        swap("nvgFontSize", function(_, size) state.font = size end)
        swap("nvgTextBounds", function(_, _, _, text)
            local w = 0
            for _, c in utf8.codes(text) do w = w + state.font * (c > 127 and 1 or 0.55) end
            return w
        end)
        swap("nvgText", function(_, x, y, text)
            local sx, sy = transform(x, y)
            state.texts[#state.texts + 1] = { x = sx, y = sy, text = text, font = state.font, color = state.color }
        end)
        swap("nvgCreateImage", function(_, path)
            loads[path] = (loads[path] or 0) + 1
            local h = #handles + 1
            handles[h] = path
            return h
        end)

        module("ui.character.panel.CharacterPanel", {
            getOwnedHero = function() return own end, getEffectiveLevel = function() return own.level end,
        })
        module("core.GameState", { getGold = function() return gold end })
        module("systems.EquipmentPower", { getContext = function() return nil end })
        module("systems.ButtonFeedback", { begin = noop, finish = noop, trigger = noop })
        module("core.DarkIcon", { drawNine = function(_, _, x, y, w, h, opts)
            buttons[#buttons + 1] = { rect = recordRect(x, y, w, h), opts = opts, clip = state.clip }
        end })
        module("ui.widget.KeywordText", { new = function()
            return { clear = noop, measureHeight = function() return 40 end,
                setTransform = noop, setPopupTransform = noop, draw = noop, drawPopup = noop,
                isOpen = function() return false end, closePopup = noop,
                handleInput = function() return false end }
        end })
        module("runtime.GameAction", { sendAction = function(kind, payload)
            actions[#actions + 1] = { kind = kind, payload = payload }
        end })
        -- 独立进程直接加载真实被测模块；配置从不拦截。
        local UI = require("ui.church.ChurchClassChange")
        local Tree = require("ui.church.ClassChangeTree")
        UI.init(state)
        local function clearDraw()
            state.x, state.y, state.scale, state.clip = 0, 0, 1, nil
            state.stack, state.images, state.rects, state.texts, buttons = {}, {}, {}, {}, {}
        end
        local function close()
            UI.setHero(nil) -- 无动作关闭，避免关闭动画干扰下一案例
        end
        local function draw(hero, first, second, level)
            close(); UI.setHero(hero)
            own.level, own.advBranch = level or 100, first and { first = first, second = second } or nil
            clearDraw(); UI.drawContent(state)
        end
        local function contains(r, x, y) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
        local function lineColor(x, y)
            local color
            for _, record in ipairs(state.rects) do
                if contains(record.rect, x, y - 300) then color = record.color end
            end
            return color or {}
        end
        local function isGold(c) return c.r == 255 and c.g == 196 and c.b == 46 and c.a == 255 end
        local function isWhite(c, alpha) return c.r == 255 and c.g == 255 and c.b == 255 and c.a == alpha end
        local function textAt(text)
            for _, row in ipairs(state.texts) do if row.text == text then return true end end
            return false
        end
        local function popup(hero, id, ownedFlag)
            close(); UI.setHero(hero)
            UI.openConfirmPopup(2, id, AVC.get(id).name, UI.CLASS_NUM[HC.get(hero).classId], ownedFlag)
        end
        local function submit(x, y)
            return UI.handleConfirmInput(x or 540, y or 1643)
        end
        local heroes = {}
        for id, cfg in pairs(HC.HEROES) do heroes[cfg.classId] = heroes[cfg.classId] or id end
        local classes = { CC.KNIGHT, CC.WARRIOR, CC.MAGE, CC.RANGER, CC.ASSASSIN, CC.PRIEST }
        for k, cid in ipairs(classes) do
            local hero, parents = assert(heroes[cid]), AVC.FIRST_BRANCHES[cid]
            local left, right = AVC.SECOND_BRANCHES[parents[1]], AVC.SECOND_BRANCHES[parents[2]]
            local fusion = 224 + k
            check(#left == 3 and #right == 3 and left[3] == fusion and right[3] == fusion,
                cid .. " 每父三去向且中心同一真实融合 ID")
            local nodes = Tree.getNodes(cid)
            check(#nodes == 5 and nodes[1].id == left[1] and nodes[2].id == left[2]
                and nodes[3].id == fusion and nodes[4].id == right[1] and nodes[5].id == right[2], cid .. " 五节点保留旧次序")
            draw(hero, parents[1])
            local counts = {}
            for _, record in ipairs(state.images) do
                local id = tonumber((record.path or ""):match("UI_icon_ZY_(%d+)%.png"))
                if id and id >= 200 then
                    counts[id] = (counts[id] or 0) + 1
                    local node
                    for _, n in ipairs(nodes) do if n.id == id then node = n end end
                    check(node and record.rect.x == node.pos.iconCX - 83 and record.rect.y == 1941 - 83 - 300
                        and record.rect.w == 166 and record.rect.h == 166, cid .. " 图边/位置 " .. id)
                end
            end
            local unique = 0
            for _, count in pairs(counts) do unique = unique + 1; check(count == 1, cid .. " 唯一图标不重画") end
            check(unique == 5 and counts[fusion] == 1, cid .. " 实际 draw 五节点共享仅一次")
            -- 融合两线并排：左父亮左线 528、右线压暗；两条专属竖线同样按父着色。
            check(isWhite(lineColor(140, 1820), 255) and isWhite(lineColor(340, 1820), 255)
                and isWhite(lineColor(528, 1800), 255) and isWhite(lineColor(552, 1800), 77)
                and isWhite(lineColor(740, 1800), 77), cid .. " 左父三路亮/右父暗")
            draw(hero, parents[2])
            check(isWhite(lineColor(740, 1820), 255) and isWhite(lineColor(940, 1820), 255)
                and isWhite(lineColor(552, 1800), 255) and isWhite(lineColor(528, 1800), 77)
                and isWhite(lineColor(340, 1800), 77), cid .. " 右父三路亮/左父暗")
            for side = 1, 2 do
                for _, id in ipairs(AVC.SECOND_BRANCHES[parents[side]]) do
                    own.advBranch = { first = parents[side] }
                    popup(hero, id)
                    local hitNode = nodes[1]
                    for _, n in ipairs(nodes) do if n.id == id then hitNode = n end end
                    close(); UI.setHero(hero)
                    check(UI.handleBranchInput(hitNode.pos.iconCX, hitNode.pos.iconCY - 300), cid .. " 合法分支实际命中 " .. id)
                    clock.elapsedTime = clock.elapsedTime + 1
                    local before = #actions
                    submit()
                    check(#actions == before + 1 and actions[#actions].payload.branchId == id
                        and actions[#actions].payload.advLevel == 2, cid .. " 合法一转父动作 " .. id)
                end
            end
            for side = 1, 2 do
                local selectedParent = side == 1 and parents[1] or parents[2]
                draw(hero, selectedParent, fusion)
                -- 该父自己的融合线是必经段 → 金；另一父通向融合的线不误亮。
                local ownStem = side == 1 and 528 or 552
                local otherStem = side == 1 and 552 or 528
                local otherBarX = side == 1 and 640 or 440
                check(isGold(lineColor(ownStem, 1800)) and isGold(lineColor(ownStem, 1848))
                    and not isGold(lineColor(otherStem, 1800))
                    and not isGold(lineColor(otherBarX, 1758))
                    and not isGold(lineColor(340, 1820)) and not isGold(lineColor(740, 1820)), cid .. " 融合仅真实父路径金色 side=" .. side)
            end
            -- 每个原专属的金路只抵达自身，不误亮融合/相邻专属。
            for i, node in ipairs(nodes) do
                if i ~= 3 then
                    local side = i <= 2 and 1 or 2
                    local selectedParent = side == 1 and parents[1] or parents[2]
                    draw(hero, selectedParent, node.id)
                    check(isGold(lineColor(node.pos.iconCX, 1848)) and not isGold(lineColor(540, 1848)), cid .. " 专属二转金路 " .. node.id)
                end
            end
            draw(hero, nil, nil, 1)
            check(isWhite(lineColor(528, 1800), 89) and isWhite(lineColor(340, 1800), 89)
                and textAt("达到Lv" .. AVC.COST[1].level .. "解锁"), cid .. " 双阶段锁罩灰线")
            draw(hero, parents[1], nil, AVC.COST[2].level - 1)
            check(isWhite(lineColor(528, 1848), 89) and textAt("达到Lv" .. AVC.COST[2].level .. "解锁"), cid .. " 二转锁罩布局")
        end

        local cid, hero = CC.KNIGHT, heroes[CC.KNIGHT]
        local parents = AVC.FIRST_BRANCHES[cid]
        local fusion = AVC.SECOND_BRANCHES[parents[1]][3]
        local blockedCases = {
            { name = "没有一转数据", ab = nil, id = fusion },
            { name = "一转空表", ab = {}, id = fusion },
            { name = "另一父专属", ab = { first = parents[1] }, id = AVC.SECOND_BRANCHES[parents[2]][1] },
            { name = "二转重复（陈旧弹窗未标 owned）", ab = { first = parents[1], second = fusion }, id = fusion },
            { name = "已二转再选另一分支", ab = { first = parents[1], second = fusion }, id = AVC.SECOND_BRANCHES[parents[1]][1] },
            { name = "跨基础职业", ab = { first = parents[1] }, id = 226 },
        }
        for _, c in ipairs(blockedCases) do
            own.level, own.advBranch = 100, c.ab
            popup(hero, c.id); clock.elapsedTime = clock.elapsedTime + 1
            clearDraw(); UI.drawConfirmPopup(state)
            check(textAt(c.ab and c.ab.first and "不可转职" or "需先完成一转"), c.name .. " 绘制锁态")
            local before = #actions; submit()
            check(#actions == before, c.name .. " 禁止动作")
        end
        own.advBranch = { first = parents[1] }
        own.level = AVC.COST[2].level - 1
        popup(hero, fusion); clock.elapsedTime = clock.elapsedTime + 1
        clearDraw(); UI.drawConfirmPopup(state)
        check(textAt("需要Lv" .. AVC.COST[2].level), "确认等级锁")
        local before = #actions; submit(); check(#actions == before, "确认等级不足不发送")
        own.level, gold = 100, 0
        popup(hero, fusion); clock.elapsedTime = clock.elapsedTime + 1
        before = #actions; submit(); check(#actions == before, "金币不足不发送")
        gold = 10000000
        own.advBranch = { first = parents[1], second = fusion }
        popup(hero, fusion, true); clock.elapsedTime = clock.elapsedTime + 1
        clearDraw(); UI.drawConfirmPopup(state)
        check(textAt("已拥有"), "旧/融合 owned 详情按钮保留")
        before = #actions; submit(); check(#actions == before, "owned 只关闭无重复请求")

        own.advBranch = { first = parents[1] }
        popup(hero, fusion)
        clearDraw(); UI.drawConfirmPopup(state) -- 首帧0.85按钮真实中心=1570.1，而不是1643
        before = #actions
        check(submit(540, 1157 + (1643 - 1157) * 0.85) and #actions == before + 1, "首帧缩放按钮逆变换")
        popup(hero, fusion)
        clearDraw(); UI.drawConfirmPopup(state)
        before = #actions
        submit(740, 1643) -- 在未缩放按钮内，却在实际0.85按钮外，不能发动作
        check(#actions == before, "缩放按钮外不按未缩放范围误提交")
        draw(hero, parents[1])
        check(not UI.handleBranchInput(-10, 1641) and not UI.handleBranchInput(1090, 1641)
            and not UI.handleResetButton(-10, 1940), "外栏输入不吞")
        check(not UI.handleBranchInput(540, 1941), "未逆树平移的旧Y不误命中节点")
        check(UI.handleBranchInput(340, 1616 - 300), "一转左节点对齐千面后命中")
        close(); UI.setHero(hero)
        check(UI.handleBranchInput(740, 1616 - 300), "一转右节点对齐致命面后命中")
        close(); UI.setHero(hero)
        check(UI.handleBranchInput(540, 1295 - 300), "基础职业详情保留")
        close(); UI.setHero(hero)
        before = #actions
        check(UI.handleResetButton(540, 2240 - 300) and #actions == before + 1
            and actions[#actions].kind == Protocol.ACTION_TYPES.RESET_CLASS, "重置按钮同树平移不挤二转")

        for id = 225, 227 do
            local cfg = AVC.get(id)
            own.level, own.advBranch = 100, { first = cfg.parentBranches[1] }
            popup(heroes[cfg.baseClass], id)
            clock.elapsedTime = clock.elapsedTime + 1
            clearDraw(); UI.drawConfirmPopup(state)
            check(textAt("+8%") and not textAt("+0"), "真实融合 pct 属性显示 +8% " .. id)
        end
        -- 二转直角线的终点必须落在166图标真实顶边，不向非节点伸尾。
        draw(hero, parents[1], fusion)
        local terminals = { 140, 340, 528, 552, 740, 940 }
        local terminalCount = 0
        for _, record in ipairs(state.rects) do
            local r = record.rect
            if r.y >= 1699 - 300 and r.y < 1858 - 300 and r.w == 12 then
                check(r.y + r.h <= 1858 - 300, "二转竖线不穿图标/无非节点尾段")
                if r.y + r.h == 1858 - 300 then
                    terminalCount = terminalCount + 1
                    local realNode = false
                    for _, x in ipairs(terminals) do if r.x + r.w * 0.5 == x then realNode = true end end
                    check(realNode, "二转终点中心对齐真实节点")
                end
            end
        end
        check(terminalCount == 6, "六条终段（融合两条）精确止于图边")
        -- 横竖线交点不得由两段矩形重叠覆盖（半透明叠加会变亮）。
        local thin = {}
        for _, record in ipairs(state.rects) do
            local r = record.rect
            if r.y >= 1699 - 300 and r.y + r.h <= 1858 - 300 and (r.w == 12 or r.h == 12) then
                thin[#thin + 1] = r
            end
        end
        local overlap = 0
        for i = 1, #thin do
            for j = i + 1, #thin do
                local a, b = thin[i], thin[j]
                local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
                local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
                if ox > 0 and oy > 0 then overlap = overlap + 1 end
            end
        end
        check(#thin >= 12 and overlap == 0, "二转线段互不重叠（交点不叠加变亮）")
        -- 融合节点无相由左右父各引一条竖线并排接入，不再共用单条中干。
        local fusionStems = {}
        for _, record in ipairs(state.rects) do
            local r = record.rect
            if r.w == 12 and r.y == 1758 - 6 - 300 and r.y + r.h == 1858 - 300
                and r.x + r.w * 0.5 ~= 540 then
                local cx = r.x + r.w * 0.5
                if cx > 500 and cx < 580 then fusionStems[#fusionStems + 1] = cx end
            end
        end
        table.sort(fusionStems)
        check(#fusionStems == 2 and fusionStems[2] - fusionStems[1] == 12 + 12,
            "融合两条并排竖线，中缝12px，不再共用单条中干")
        check(#fusionStems == 2 and (fusionStems[1] + fusionStems[2]) * 0.5 == 540,
            "融合两线以节点中心540对称")
        -- 一转与二转中心对齐：两条黄色路径应各为一条直竖线（无横向小折）。
        local stemCx = {}
        for _, record in ipairs(state.rects) do
            local r = record.rect
            if r.w == 12 and r.y + r.h == 1858 - 300 and (r.x + r.w * 0.5 == 340 or r.x + r.w * 0.5 == 740) then
                stemCx[#stemCx + 1] = r.x + r.w * 0.5
            end
        end
        table.sort(stemCx)
        check(#stemCx == 2 and stemCx[1] == 340 and stemCx[2] == 740,
            "一转中心与二转中心对齐（340/740 竖直贯通）")
        check(isGold(lineColor(540, 1430)) and not isGold(lineColor(740, 1467)), "原基础到一转当前路径金线保留")
        draw(hero, nil)
        check(isWhite(lineColor(540, 1430), 255), "未一转基础分叉白亮保留")

        -- 验证宿主的横向平移/裁剪没有被模块清除，且所有 save 成对恢复。
        clearDraw(); state.x, state.y = 1200, 50
        local hostClip = { x = 1200, y = 0, w = 1080, h = 2400 }
        state.clip = hostClip
        UI.drawContent(state)
        check(state.x == 1200 and state.y == 50 and state.clip == hostClip and #state.stack == 0, "保留宿主平移和scissor")
        check(buttons[#buttons].clip == hostClip and buttons[#buttons].rect.y == 2240 - 300 - 50 + 50,
            "重置按钮恢复宿主裁剪而非无限制跨栏")
        for id = 225, 230 do
            check(loads["image/职业图标/UI_icon_ZY_" .. id .. ".png"] == 1, "融合图标缓存仅创建一次 " .. id)
        end
        close()
    end, debug.traceback)
    restore()
    if not ok then failures[#failures + 1] = tostring(err); print("[FAIL] " .. tostring(err)) end
    if #failures == 0 then print("[advancement_fusion_ui_test] ALL PASS (" .. passes .. " 断言)")
    else print("[advancement_fusion_ui_test] FAILURES=" .. #failures) end
    engine:Exit()
end
