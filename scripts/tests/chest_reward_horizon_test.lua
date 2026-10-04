-- 宝箱展示回归：真实 Horizon/Viewport/RewardPopup/ChurchResults/ChurchArtifactDrawPanel。
-- 仅旁页、底层 NanoVG 与 ArtifactAssetUtil.drawIcon 为 spy；成功回包使用内存数据，绝不抽取/花币/读写存档。
-- Runtime: tests/chest_reward_horizon_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local assertions, cases, failures = 0, 0, 0
local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end

function Start()
    ---@type fun(name: string): any
    local originalRequire = require
    local RT = originalRequire("boot.StandaloneRT")
    local VP = originalRequire("core.Viewport")
    local Asset = originalRequire("config.ArtifactAssetUtil")
    local Cascade = originalRequire("ui.widget.RewardCascade")
    local SFX = originalRequire("systems.GameSFX")
    local savedRT, savedGlobals, savedNotes = {}, {}, VP._notes
    local savedIcon, savedNew, savedPlay = Asset.drawIcon, Cascade.new, SFX.play
    for k, v in pairs(RT) do savedRT[k] = v end
    for k, v in pairs(_G) do savedGlobals[k] = v end
    local ok, err = pcall(function()
        local function noop() return false end
        ---@return any
        local function mock(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local mode, lowerInputs, actions, reads, badges = "tri", 0, 0, 0, 0
        local clock, cursor = { elapsedTime = 100 }, { x = 0, y = 0 }
        rawset(_G, "time", clock)
        rawset(_G, "input", { GetMousePosition = function() return cursor end })
        -- 完整仿射矩阵，包含真实 RewardCascade.applyPop 的旋转；scissor 设置时冻结在窗口逻辑空间。
        ---@type any
        local ctx = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0, alpha = 1, clip = nil, stack = {} }
        ---@type any[]
        local icons, titles, texts, frames = {}, {}, {}, {}
        local function copy(r)
            if not r then return nil end
            return { x = r.x, y = r.y, w = r.w, h = r.h }
        end
        local function matrix()
            return { a = ctx.a, b = ctx.b, c = ctx.c, d = ctx.d, e = ctx.e, f = ctx.f }
        end
        local function point(x, y) return ctx.a * x + ctx.c * y + ctx.e, ctx.b * x + ctx.d * y + ctx.f end
        local function rect(x, y, w, h)
            local xs, ys = {}, {}
            for _, p in ipairs({ { x, y }, { x + w, y }, { x, y + h }, { x + w, y + h } }) do
                local px, py = point(p[1], p[2])
                xs[#xs + 1], ys[#ys + 1] = px, py
            end
            local left, top = math.min(table.unpack(xs)), math.min(table.unpack(ys))
            return { x = left, y = top, w = math.max(table.unpack(xs)) - left, h = math.max(table.unpack(ys)) - top }
        end
        local function intersect(a, b)
            if not a then return b end
            local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
            return { x = x, y = y, w = math.max(0, math.min(a.x + a.w, b.x + b.w) - x),
                h = math.max(0, math.min(a.y + a.h, b.y + b.h) - y) }
        end
        rawset(_G, "nvgSave", function()
            ctx.stack[#ctx.stack + 1] = { m = matrix(), alpha = ctx.alpha, clip = copy(ctx.clip) }
        end)
        rawset(_G, "nvgRestore", function()
            local s = assert(table.remove(ctx.stack), "NanoVG restore 必须配对 save")
            ctx.a, ctx.b, ctx.c, ctx.d, ctx.e, ctx.f = s.m.a, s.m.b, s.m.c, s.m.d, s.m.e, s.m.f
            ctx.alpha, ctx.clip = s.alpha, s.clip
        end)
        rawset(_G, "nvgTranslate", function(_, x, y)
            ctx.e, ctx.f = ctx.e + x * ctx.a + y * ctx.c, ctx.f + x * ctx.b + y * ctx.d
        end)
        rawset(_G, "nvgScale", function(_, x, y)
            ctx.a, ctx.b, ctx.c, ctx.d = ctx.a * x, ctx.b * x, ctx.c * y, ctx.d * y
        end)
        rawset(_G, "nvgRotate", function(_, angle)
            local co, si = math.cos(angle), math.sin(angle)
            ctx.a, ctx.b, ctx.c, ctx.d = ctx.a * co + ctx.c * si, ctx.b * co + ctx.d * si,
                ctx.c * co - ctx.a * si, ctx.d * co - ctx.b * si
        end)
        rawset(_G, "nvgResetTransform", function() ctx.a, ctx.b, ctx.c, ctx.d, ctx.e, ctx.f = 1, 0, 0, 1, 0, 0 end)
        rawset(_G, "nvgScissor", function(_, x, y, w, h) ctx.clip = rect(x, y, w, h) end)
        rawset(_G, "nvgIntersectScissor", function(_, x, y, w, h) ctx.clip = intersect(ctx.clip, rect(x, y, w, h)) end)
        rawset(_G, "nvgResetScissor", function() ctx.clip = nil end)
        rawset(_G, "nvgGlobalAlpha", function(_, a) ctx.alpha = a end)
        rawset(_G, "nvgBeginFrame", function(_, w, h, dpr)
            ctx.a, ctx.b, ctx.c, ctx.d, ctx.e, ctx.f, ctx.alpha = 1, 0, 0, 1, 0, 0, 1
            ctx.clip, ctx.stack = nil, {}
            frames[#frames + 1] = { w = w, h = h, dpr = dpr }
        end)
        rawset(_G, "nvgEndFrame", function() check(#ctx.stack == 0, "帧尾恢复全部NanoVG状态") end)
        rawset(_G, "nvgText", function(_, x, y, text)
            texts[#texts + 1] = text
            if x == 540 and y == 776 then
                titles[#titles + 1] = { text = text, m = matrix(), clip = copy(ctx.clip), alpha = ctx.alpha }
            end
        end)
        rawset(_G, "nvgTextBounds", function(_, _, _, text) return #text * 12 end)
        rawset(_G, "nvgCreateImage", function() return 900 end)
        -- 颜色和 NVG 枚举仍用引擎原值，渐变只是不提交GPU。
        rawset(_G, "nvgImagePattern", noop)
        rawset(_G, "nvgRadialGradient", noop)
        rawset(_G, "nvgLinearGradient", noop)
        for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgCircle", "nvgFillColor",
            "nvgFillPaint", "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgMoveTo",
            "nvgLineTo", "nvgClosePath", "nvgFontFace", "nvgFontSize", "nvgTextAlign" }) do rawset(_G, name, noop) end

        ---@type any
        local timeline = {}
        Cascade.new = function(count, opts)
            timeline = savedNew(count, opts) -- 观察真实时间轴；不替换 t/applyPop/show/drawContent。
            return timeline
        end
        SFX.play = noop
        Asset.drawIcon = function(_, item, x, y, size)
            local px, py = point(x, y)
            icons[#icons + 1] = { item = item, x = px, y = py, size = size, m = matrix(),
                rect = rect(x - size / 2, y - size / 2, size, size), clip = copy(ctx.clip), alpha = ctx.alpha }
        end
        local function page()
            return mock({ handleInput = function() lowerInputs = lowerInputs + 1; return false end,
                handleClick = function() lowerInputs = lowerInputs + 1; return false end })
        end
        local artifactMemory = {}
        local mods = {
            ["boot.StandaloneRT"] = RT, ["core.Viewport"] = VP,
            ["config.ArtifactAssetUtil"] = Asset, ["ui.widget.RewardCascade"] = Cascade, ["systems.GameSFX"] = SFX,
            ["core.PlayerStore"] = mock({ Get = function(key)
                reads = reads + 1
                check(key == "artifacts", "结果回包只访问内存神器数据")
                return artifactMemory
            end }),
            ["core.GameState"] = mock({ getGoldenKey = function() error("禁止读取/消费货币") end,
                getGems = function() error("禁止读取/消费货币") end }),
            ["runtime.GameAction"] = mock({ sendAction = function() actions = actions + 1; error("禁止发送抽取action") end }),
            ["ui.hud.BottomNav"] = mock({ getSelectedIndex = function() return 3 end,
                refreshTownBadge = function() badges = badges + 1 end }),
            ["ui.character.panel.CharacterPanel"] = mock({ getTotalPower = function() return 0 end }),
            ["ui.battle.tri.BattleTriPage"] = mock({ isOpen = function() return mode == "tri" end }),
            ["ui.tower.TowerBattleScene"] = mock({ isActive = function() return mode == "tower" end }),
            ["core.DrawUtil"] = originalRequire("core.DrawUtil"),
            ["core.DarkIcon"] = originalRequire("core.DarkIcon"),
        }
        for _, name in ipairs({ "config.GameConfig", "config.EquipmentConfig", "config.HeroConfig", "core.NumberUtil",
            "ui.widget.ImageCache", "config.ResourceDefs", "ui.widget.HeroFrame", "ui.widget.BattleRewardQueue", "config.StageConfig", "core.I18n",
            "shared.artifact.ArtifactDefs", "shared.Protocol" }) do mods[name] = originalRequire(name) end
        -- cache:GetFile 是只读项目资源，不走玩家存档 File；load 创建独立实例，不操作 package.loaded。
        local function source(name)
            local path = name:gsub("%.", "/") .. ".lua"
            local f = assert(cache:GetFile(path), "缺少真实Lua资源 " .. path)
            check(f:IsOpen(), "打开项目源码 " .. path)
            local lines = {}
            while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
            f:Dispose()
            return table.concat(lines, "\n")
        end
        local function compile(name, text)
            local chunk, why = load(text or source(name), "@" .. name, "t", _G)
            assert(chunk, why)
            return chunk()
        end
        rawset(_G, "require", function(name)
            if not mods[name] then mods[name] = page() end
            return mods[name]
        end)
        local Reward = compile("ui.hud.popup.RewardPopup")
        mods["ui.hud.popup.RewardPopup"] = Reward
        local DrawPanel = compile("ui.church.ChurchArtifactDrawPanel")
        local Results = compile("ui.church.ChurchResults")
        local Defs, Protocol = mods["shared.artifact.ArtifactDefs"], mods["shared.Protocol"]
        mods["boot.StandaloneHorizonInput"] = compile("boot.StandaloneHorizonInput")
        mods["boot.OfflineRewardOverlay"] = compile("boot.OfflineRewardOverlay")
        local horizonSource = source("boot.StandaloneHorizon")
        Reward.init({})
        local churchState = { open = true }
        local church = Results.bind({ state = churchState, getProtocol = function() return Protocol end,
            ArtifactDrawPanel = DrawPanel, ArtifactPanel = page(), CharacterPanel = page(),
            SpineCardEffect = page(), clearPowerCache = noop })
        local function fixture(which, dpr, transformed, text)
            mode, lowerInputs, actions, reads, badges = which, 0, 0, 0, 0
            clock.elapsedTime = clock.elapsedTime + 10
            for k in pairs(RT) do RT[k] = nil end
            RT.logicalW, RT.logicalH, RT.windowW, RT.windowH = 1920, 1080, 1920, 1080
            RT.vg, RT.dpr, RT.bootReady_, RT.preload_ = {}, dpr or 1, true, { active = false }
            RT.frameOx, RT.frameOy, RT.frameScale = transformed and 37 or 0, transformed and 23 or 0, transformed and 0.8 or 1
            VP._notes = {}
            artifactMemory = { pityRare = 9, pityEpic = 19, dailyFreeDrawDayId = 1 }
            compile("boot.StandaloneHorizon", text or horizonSource)
            check(H_focusPanel == "center", "Horizon默认focus仍center")
        end
        local function artifacts(count)
            local result = {}
            for i = 1, count do
                result[i] = { id = "chest-" .. i, artifactId = (i - 1) % 5 + 1, quality = (i - 1) % 4 + 1,
                    value = 12 + i, valueRatio = 5000 + i, threatClearValue = i, threatClearRatio = 3000 + i }
            end
            return result
        end
        local function success(count)
            local result = artifacts(count)
            church.onActionResult({ action = Protocol.ACTION_TYPES.ARTIFACT_DRAW, success = true,
                artifacts = result, pityRare = 2, pityEpic = 3, dailyFreeDrawDayId = 20000 })
            check(Reward.isOpen() and Reward.currentPanel() == "left" and Reward.currentRowTag() == nil,
                "成功回包在默认focus=center时显式来源left，而非row")
            check(churchState.floatText == "获得" .. count .. "件神器", "结果件数提示准确")
            check(badges == 1 and reads == 1 and actions == 0, "结果只刷新角标/内存，不花币发action")
            check(artifactMemory.pityRare == 2 and artifactMemory.pityEpic == 3
                and artifactMemory.dailyFreeDrawDayId == 20000, "保底/每日标记同步到内存")
            check(timeline.count == count and near(timeline.revealStart, clock.elapsedTime + Cascade.LEAD), "来源接入真实cascade")
            return result
        end
        local function render(dt)
            clock.elapsedTime = clock.elapsedTime + (dt or 0)
            Reward.update(dt or 0)
            icons, titles, texts, frames = {}, {}, {}, {}
            HandleNanoVGRenderHorizon()
            check(#frames == 1 and frames[1].dpr == RT.dpr and frames[1].w == 1920 and frames[1].h == 1080,
                "唯一帧使用窗口逻辑分辨率及真实DPR")
            check(actions == 0 and lowerInputs == 0, "无存档事务/货币action/旁页点击")
        end
        local function hasText(text)
            for _, t in ipairs(texts) do if t == text then return true end end
            return false
        end
        local function host(panel)
            local cs, ox, oy
            if (mode == "tri" or mode == "tower") and (panel == "center" or panel == nil) then
                cs, ox, oy = 0.45, 717, 0
                return cs * RT.frameScale, RT.frameOx + ox * RT.frameScale, RT.frameOy + oy * RT.frameScale,
                    { x = RT.frameOx, y = RT.frameOy, w = 1920 * RT.frameScale, h = 1080 * RT.frameScale }
            end
            local p = VP.PANELS[panel or "center"]
            local n = assert(VP.getNote(panel or "center"), "真实VP note")
            cs, ox, oy = n.s * VP.DS, n.ox + p.bx * n.s, n.oy + p.by * n.s
            return cs * RT.frameScale, RT.frameOx + ox * RT.frameScale, RT.frameOy + oy * RT.frameScale,
                { x = RT.frameOx + ox * RT.frameScale, y = RT.frameOy + oy * RT.frameScale,
                    w = 1080 * cs * RT.frameScale, h = 2400 * cs * RT.frameScale }
        end
        local function equalRect(a, b)
            return a and b and near(a.x, b.x) and near(a.y, b.y) and near(a.w, b.w) and near(a.h, b.h)
        end
        local function matrixCorrect(panel, count)
            if #titles ~= 1 then return false end
            local cs, ox, oy = host(panel)
            local layout = count <= 5 and 0.7 or 1
            local m = titles[1].m
            return near(m.a, cs * layout) and near(m.d, cs * layout) and near(m.b, 0) and near(m.c, 0)
                and near(m.e, ox + cs * 540 * (1 - layout)) and near(m.f, oy + cs * 974 * (1 - layout))
        end
        local function visibleIcons(panel, count, expected)
            check(#titles == 1 and titles[1].text == "神器宝箱", "结果title主体只画一次")
            check(matrixCorrect(panel, count), "实际title矩阵 = frame × 宿主panel/letterbox × 奖励layout")
            local cs, ox, oy, clip = host(panel)
            check(equalRect(titles[1].clip, clip), "title宿主clip与所在栏/全窗同源")
            check(#icons == expected, "图标恰好绘制预期出场件数 actual=" .. #icons .. " expected=" .. expected)
            local ids = {}
            local layout = count <= 5 and 0.7 or 1
            local grid = { x = ox + cs * (540 * (1 - layout) + 71 * layout),
                y = oy + cs * (974 * (1 - layout) + 838 * layout), w = 938 * cs * layout, h = 340 * cs * layout }
            local gridClip = intersect(clip, grid)
            for _, draw in ipairs(icons) do
                check(not ids[draw.item.id], "每件图标每帧只有一次 " .. draw.item.id)
                ids[draw.item.id] = true
                check(draw.item.type == "artifact" and Defs.get(draw.item.artifactId)
                    and Asset.getIconPath(draw.item.artifactId) ~= nil and draw.item.name == Defs.getName(draw.item),
                    "真实结果神器ID/名字/可加载图标路径有效")
                check(equalRect(draw.clip, gridClip), "网格clip在图标pop旋转/缩放前冻结且受宿主clip约束")
                local area = intersect(draw.rect, draw.clip)
                check(draw.alpha > 0 and area.w > 0 and area.h > 0 and draw.clip.w > 0 and draw.clip.h > 0,
                    "实际图标有非零alpha、有效clip和可见交集")
                check(draw.x >= draw.clip.x and draw.x <= draw.clip.x + draw.clip.w
                    and draw.y >= draw.clip.y and draw.y <= draw.clip.y + draw.clip.h,
                    "图标中心可见，不在面板外绘制")
            end
            check(cs > 0 and hasText("神器宝箱"), "非零宿主scale及真实结果文字")
        end
        local button = { Button = { GetInt = function() return MOUSEB_LEFT end } }
        local function clickIcon()
            local draw = assert(icons[1], "需要已绘制图标投射点击")
            cursor.x, cursor.y = draw.x * RT.dpr, draw.y * RT.dpr
            HandleMouseButtonDownHorizon("MouseButtonDown", button)
            clock.elapsedTime = clock.elapsedTime + 0.01
            HandleMouseButtonUpHorizon("MouseButtonUp", button)
            check(lowerInputs == 0 and actions == 0, "真实down/up未穿透旁页/消费货币")
        end
        local function run(label, fn)
            cases = cases + 1
            local passed, why = pcall(fn)
            if passed then print("[PASS] chest_reward_horizon_test " .. label)
            else failures = failures + 1; print("[FAIL] chest_reward_horizon_test " .. label .. ": " .. tostring(why)) end
        end

        for _, count in ipairs({ 1, 10 }) do
            for _, which in ipairs({ "tri", "ordinary", "tower" }) do
                run(which .. " 成功回包 " .. count .. "件 0.4s/尾部稳定", function()
                    fixture(which)
                    success(count)
                    check(timeline:t(1) == nil, "来源show首件有真实lead")
                    render(0.4)
                    visibleIcons("left", count, count == 1 and 1 or 3)
                    check(timeline:t(1) > 1, "0.4秒首件已落地")
                    if count == 10 then
                        check(timeline:t(3) > 0 and timeline:t(3) < 1 and timeline:t(4) == nil,
                            "十连0.4秒第三件pop、第四件未出现")
                        check(not near(icons[3].m.b, 0), "真实第三件pop包含摇摆旋转")
                        check(hasText("点击跳过"), "级联未结束提示可跳过")
                    end
                    render(1.2)
                    visibleIcons("left", count, count)
                    check(timeline:finished() and hasText("点击空白处关闭"), "尾部落地后显示关闭提示")
                end)
            end
        end
        for _, count in ipairs({ 1, 10 }) do
            run("来源默认无onItemClick " .. count .. "件：首击skip后二击close", function()
                fixture("tri", 2, true)
                success(count)
                render(0.18)
                check(timeline:t(1) > 0 and timeline:t(1) < 1, "首击之前第一件仍在真实pop")
                check(#icons > 0 and icons[1].alpha > 0, "来源早期动画真有可见图标")
                clickIcon()
                render(0.4)
                check(Reward.isOpen() and timeline:finished(), "来源首击只skip仍open，无原有详情承诺")
                visibleIcons("left", count, count)
                clickIcon()
                render(0.26)
                check(#icons == 0 and #titles == 0 and Reward.isOpen(), "第二击关闭动画完成但仍有吞噬保护期")
                render(0.16)
                check(not Reward.isOpen(), "第二击close及保护期最终结束")
            end)
        end
        -- onItemClick 是独立共享API测试；源宝箱没有该回调，绝不伪称原有详情功能。
        for _, which in ipairs({ "tri", "ordinary", "tower" }) do
            for _, entry in ipairs({ { panel = "left" }, { panel = "right" }, { panel = "center" }, { panel = nil } }) do
                for _, dpr in ipairs({ 1, 2, 3 }) do
                    run(which .. " shared " .. tostring(entry.panel) .. " DPR=" .. dpr .. " frame偏移及真实callback", function()
                        fixture(which, dpr, true)
                        local sourceItem = { type = "artifact", id = "shared", artifactId = 2, quality = 3,
                            name = Defs.getName({ artifactId = 2, quality = 3 }) }
                        local received, receivedIndex, clicks = nil, nil, 0
                        -- nil用清空focus表达真正的无归属；不把opts.panel=nil误当成显式覆盖focus。
                        H_focusPanel = nil
                        Reward.show("神器宝箱", { sourceItem }, { panel = entry.panel, cascade = true,
                            onItemClick = function(item, index) received, receivedIndex, clicks = item, index, clicks + 1 end })
                        check(Reward.currentPanel() == entry.panel, "共享API保留显式归属/真正nil")
                        render(0.4)
                        visibleIcons(entry.panel, 1, 1)
                        local first = icons[1]
                        check(near(first.m.b, 0) and near(first.m.c, 0), "稳定帧无残留pop旋转")
                        clickIcon()
                        check(clicks == 1 and received == sourceItem and receivedIndex == 1 and Reward.isOpen(),
                            "matrix×DPR真实down/up投射到同一item/index callback，不关闭")
                    end)
                end
            end
        end
        run("row只对照真实drawRegion/handleInputRegion", function()
            fixture("tri", 3, true)
            -- 前一 shared global 仍展示：新规则 row 排队不抢占，先完成实际关闭及保护期。
            if Reward.isOpen() then
                Reward.close()
                clock.elapsedTime = clock.elapsedTime + 0.26
                Reward.update(0.26)
                clock.elapsedTime = clock.elapsedTime + 0.16
                Reward.update(0.16)
            end
            check(not Reward.isOpen(), "row对照前完成global关闭与0.15秒guard")
            H_focusPanel = nil
            local item = { type = "artifact", id = "row", artifactId = 1, quality = 1,
                name = Defs.getName({ artifactId = 1, quality = 1 }) }
            local clicks = 0
            Reward.show("神器宝箱", { item }, { row = 2, cascade = true,
                onItemClick = function(got, index) check(got == item and index == 1, "row回调同item/index"); clicks = clicks + 1 end })
            clock.elapsedTime = clock.elapsedTime + 0.4
            Reward.update(0.4)
            icons, titles = {}, {}
            nvgBeginFrame({}, 1920, 1080, RT.dpr)
            nvgTranslate({}, RT.frameOx, RT.frameOy)
            nvgScale({}, RT.frameScale, RT.frameScale)
            nvgScissor({}, 500, 300, 860, 280)
            Reward.drawRegion({}, 500, 300, 860, 280, 1)
            check(#icons == 0, "不匹配row不画")
            Reward.drawRegion({}, 500, 300, 860, 280, 2)
            check(#icons == 1 and #titles == 1, "匹配row恰好一件/title")
            local draw = icons[1]
            local fit = math.min(860 / (1080 * 1.04), 280 / 920)
            check(near(draw.m.a, RT.frameScale * fit * 0.7) and draw.clip.w > 0 and draw.clip.h > 0,
                "row保留专用region+layout缩放而非宿主panel helper")
            local wx, wy = (draw.x - RT.frameOx) / RT.frameScale, (draw.y - RT.frameOy) / RT.frameScale
            check(Reward.handleInputRegion(wx, wy, 500, 300, 860, 280) and clicks == 1,
                "drawRegion的实际matrix逆投射由handleInputRegion消费")
            nvgEndFrame({})
        end)
    end)
    if not ok then failures = failures + 1; print("[FAIL] chest_reward_horizon_test Start: " .. tostring(err)) end
    rawset(_G, "require", originalRequire)
    Asset.drawIcon, Cascade.new, SFX.play = savedIcon, savedNew, savedPlay
    VP._notes = savedNotes
    for k in pairs(RT) do RT[k] = nil end
    for k, v in pairs(savedRT) do RT[k] = v end
    local added = {}
    for k in pairs(_G) do if savedGlobals[k] == nil then added[#added + 1] = k end end
    for _, k in ipairs(added) do rawset(_G, k, nil) end
    for k, v in pairs(savedGlobals) do rawset(_G, k, v) end
    if failures == 0 then
        print("[chest_reward_horizon_test] ALL PASS: " .. cases .. " cases, " .. assertions .. " assertions")
    else
        print("[FAIL] chest_reward_horizon_test: " .. failures .. " failures / " .. cases .. " cases, " .. assertions .. " assertions")
    end
    engine:Exit()
end
