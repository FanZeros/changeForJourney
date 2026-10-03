-- 本地美术/UI 迁移回归：真实 SettingsPanel、PlayerInfoPanel、TownScene 的公开 API。
-- File/FileSystem 全部为内存替身；依赖白名单 + NanoVG spy，不加载玩家业务存档或图形资源。
-- Runtime: tests/local_art_ui_migration_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- 不通过 debug/upvalue 读取私有布局或计时器；从实际 draw/input/init/update 观察结果。
function Start()
    ---@type fun(name: string): any
    local originalRequire = _G.require
    ---@type table<string, any>
    local originalGlobals, originalLoaded = {}, {}
    for key, value in pairs(_G) do originalGlobals[key] = value end
    for key, value in pairs(package.loaded) do originalLoaded[key] = value end
    local originalPackageLoaded = package.loaded
    local assertions, failures, cases, passes = 0, 0, 0, 0
    ---@type any
    local i18n = {}
    local initialLanguage = "zh_CN"
    local i18nReady = false
    local function check(condition, label)
        assertions = assertions + 1
        if not condition then
            failures = failures + 1
            print("[FAIL] local_art_ui_migration_test: " .. label)
        end
    end
    local function runCase(label, fn)
        cases = cases + 1
        local before = failures
        local ok, err = pcall(fn)
        if not ok then check(false, label .. " exception: " .. tostring(err)) end
        if failures == before then
            passes = passes + 1
            print("[PASS] " .. label)
        end
    end
    local function near(a, b)
        return type(a) == "number" and math.abs(a - b) < 0.00001
    end
    local function clear(t)
        for key in pairs(t) do t[key] = nil end
    end
    local function noop() end

    local ok, err = pcall(function()
        -- 真实五语接口，不安装 I18n 的全局绘制 hook；结束后恢复原语言。
        i18n = originalRequire("core.I18n")
        initialLanguage = i18n.get()
        i18nReady = true
        local langs = {
            { id = "zh_CN", label = "简体" }, { id = "zh_TW", label = "繁體" },
            { id = "en", label = "EN" }, { id = "ja", label = "日本語" },
            { id = "ko", label = "한국어" },
        }
        check(#i18n.LANGS == 5, "真实语言列表恰好五语")
        for index, lang in ipairs(langs) do
            check(i18n.LANGS[index] and i18n.LANGS[index].id == lang.id
                and i18n.LANGS[index].label == lang.label, "真实语言顺序/标签 " .. lang.id)
        end

        ---@type table<string, string>
        local memory = {}
        ---@type table<string, number>
        local reads, writes = {}, {}
        ---@type any[]
        local fileEvents, draws, loads, feedback = {}, {}, {}, {}
        local clock = { elapsedTime = 100 }
        ---@type any
        local vg = {}
        ---@type any
        local vgState = { sx = 1, sy = 1, tx = 0, ty = 0, fontSize = 22, align = 0, stack = {} }
        local allowedFiles = { ["settings_volume.json"] = true, ["play_time.json"] = true }
        local function filePath(path)
            assert(allowedFiles[path], "unexpected file access: " .. tostring(path))
        end
        -- 即使误调用了新的存档路径也 fail-loud，绝不透传到真实 File。
        rawset(_G, "File", function(path, mode)
            filePath(path)
            assert(mode == FILE_READ or mode == FILE_WRITE, "unexpected File mode")
            fileEvents[#fileEvents + 1] = { path = path, mode = mode }
            local opened = true
            return {
                IsOpen = function() return opened end,
                Close = function() opened = false end,
                ReadString = function()
                    assert(opened and mode == FILE_READ, "invalid mock read")
                    reads[path] = (reads[path] or 0) + 1
                    return memory[path] or ""
                end,
                WriteString = function(_, value)
                    assert(opened and mode == FILE_WRITE and type(value) == "string", "invalid mock write")
                    memory[path] = value
                    writes[path] = (writes[path] or 0) + 1
                    return true
                end,
            }
        end)
        rawset(_G, "fileSystem", { FileExists = function(_, path)
            filePath(path)
            return memory[path] ~= nil
        end })
        rawset(_G, "time", clock)
        local audioEvents = {}
        rawset(_G, "audio", { SetMasterGain = function(_, channel, gain)
            audioEvents[#audioEvents + 1] = { channel = channel, gain = gain }
        end })

        -- 累积父变换，记录的是实际最终绘制坐标，而不是抄私有常量。
        local function point(x, y) return vgState.tx + x * vgState.sx, vgState.ty + y * vgState.sy end
        local function recordRect(kind, x, y, w, h, fields)
            local px, py = point(x, y)
            ---@type any
            local entry = fields or {}
            entry.kind, entry.x, entry.y = kind, px, py
            entry.w, entry.h = w * vgState.sx, h * vgState.sy
            draws[#draws + 1] = entry
        end
        local function recordText(x, y, text, size, align)
            local px, py = point(x, y)
            draws[#draws + 1] = { kind = "text", x = px, y = py, text = text, size = size, align = align }
        end
        local function stub(name, fn) rawset(_G, name, fn or noop) end
        stub("nvgSave", function()
            vgState.stack[#vgState.stack + 1] = { sx = vgState.sx, sy = vgState.sy,
                tx = vgState.tx, ty = vgState.ty, fontSize = vgState.fontSize, align = vgState.align }
        end)
        stub("nvgRestore", function()
            local saved = table.remove(vgState.stack)
            assert(saved, "NanoVG restore without save")
            vgState.sx, vgState.sy, vgState.tx, vgState.ty = saved.sx, saved.sy, saved.tx, saved.ty
            vgState.fontSize, vgState.align = saved.fontSize, saved.align
        end)
        stub("nvgTranslate", function(_, x, y)
            vgState.tx, vgState.ty = vgState.tx + x * vgState.sx, vgState.ty + y * vgState.sy
        end)
        stub("nvgScale", function(_, x, y) vgState.sx, vgState.sy = vgState.sx * x, vgState.sy * y end)
        stub("nvgRect", function(_, x, y, w, h) recordRect("rect", x, y, w, h) end)
        stub("nvgRoundedRect", function(_, x, y, w, h, radius)
            recordRect("rounded", x, y, w, h, { radius = radius })
        end)
        stub("nvgFontSize", function(_, size) vgState.fontSize = size end)
        stub("nvgTextAlign", function(_, align) vgState.align = align end)
        stub("nvgText", function(_, x, y, text)
            recordText(x, y, text, vgState.fontSize, vgState.align)
        end)
        stub("nvgTextBounds", function(_, _, _, text)
            return utf8.len(tostring(text)) * vgState.fontSize * 0.5
        end)
        stub("nvgCreateImage", function(_, path)
            loads[#loads + 1] = path
            return #loads
        end)
        local function imagePattern(_, x, y, w, h, _, image)
            assert(type(image) == "number" and loads[image], "unknown mock image handle")
            recordRect("image", x, y, w, h, { image = image, path = loads[image] })
            return {}
        end
        stub("nvgImagePattern", imagePattern)
        stub("nvgImagePatternTinted", imagePattern)
        for _, name in ipairs({ "nvgBeginPath", "nvgFill", "nvgFillColor", "nvgFillPaint",
            "nvgStroke", "nvgStrokeColor", "nvgStrokeWidth", "nvgFontFace", "nvgCircle",
            "nvgScissor", "nvgGlobalCompositeOperation", "nvgGlobalCompositeBlendFuncSeparate" }) do stub(name) end
        -- nvgRGBA/NVG_* 与 FILE_* 沿用引擎真实定义；不覆写颜色类型，不猜枚举数字。

        local redeemState = { open = false, opens = 0, inputs = 0, updates = 0 }
        local redeem = {
            init = noop, draw = noop,
            isOpen = function() return redeemState.open end,
            open = function() redeemState.open = true; redeemState.opens = redeemState.opens + 1 end,
            close = function() redeemState.open = false end,
            handleInput = function() redeemState.inputs = redeemState.inputs + 1; return true end,
            update = function() redeemState.updates = redeemState.updates + 1 end,
        }
        local drawUtil = {
            hitTest = function(x, y, cx, cy, w, h)
                return x >= cx - w * 0.5 and x <= cx + w * 0.5
                    and y >= cy - h * 0.5 and y <= cy + h * 0.5
            end,
            easeOutBack = function(progress) return progress end,
            drawTextStroke = function(_, x, y, text, size, align) recordText(x, y, text, size, align) end,
            drawImageCentered = function(_, image, cx, cy, w, h)
                recordRect("image", cx - w * 0.5, cy - h * 0.5, w, h,
                    { image = image, path = loads[image] })
            end,
            drawNineSlice = noop,
        }
        local darkIcon = {
            drawNine = function(_, style, x, y, w, h) recordRect("nine", x, y, w, h, { style = style }) end,
            draw = function(_, key, cx, cy, size)
                recordRect("icon", cx - size * 0.5, cy - size * 0.5, size, size, { key = key })
            end,
        }
        local buttonFeedback = {
            begin = function() return false end, finish = noop,
            trigger = function(key) feedback[#feedback + 1] = key end,
        }
        local store = {
            session = { playDays = 7 }, heroes = { roster = {} }, equipment = { inventory = {} },
            battle = { maxStageId = 204 },
        }
        local gameState = {
            getGold = function() return 123 end, getGems = function() return 456 end,
            getEssence = function() return 3 end, getSweepTicket = function() return 4 end,
            getRecruitTicket = function() return 5 end, getGoldenKey = function() return 6 end,
            getLevel = function() return 30 end, getExp = function() return 0 end,
            getMaxExp = function() return 100 end,
        }
        local closedPanel = { init = noop, draw = noop, isOpen = function() return false end }
        ---@type table<string, any>
        local mods = {
            ["core.I18n"] = i18n, ["core.DrawUtil"] = drawUtil, ["core.DarkIcon"] = darkIcon,
            ["systems.ButtonFeedback"] = buttonFeedback,
            ["systems.GameBGM"] = { setMasterGain = noop },
            ["ui.hud.popup.RedeemCodePanel"] = redeem,
            ["core.GameState"] = gameState,
            ["core.PlayerStore"] = { Get = function(key) return store[key] end },
            ["core.NumberUtil"] = { format = function(value) return tostring(value) end },
            ["config.StageConfig"] = { formatProgressDisplay = function() return "2-4" end },
            ["ui.character.panel.CharacterPanel"] = { getTotalPower = function() return 1234 end },
            ["config.HeroConfig"] = {}, ["config.HeroAssetUtil"] = {},
            ["ui.character.hero.AvatarSelectPanel"] = closedPanel,
            ["ui.dev.GMConsolePanel"] = closedPanel,
            ["ui.hud.TopBar"] = {}, ["ui.character.detail.CharacterDetail"] = closedPanel,
            ["ui.widget.HeroFrame"] = { draw = noop },
            ["runtime.GameAction"] = { isGM = function() return false end },
            ["core.HorizonBg"] = { draw = noop },
            ["config.ExpTable"] = { isBuildingUnlocked = function() return true end },
            ["systems.TutorialManager"] = { isActive = function() return false end,
                isBuildingUnlocked = function() return true end },
            ["ui.loot.LootBox"] = { getCount = function() return 0 end, drawRates = noop },
            ["ui.blacksmith.BlacksmithPage"] = { canEnhanceAny = function() return false end },
            ["ui.church.talent.TalentPage"] = { hasAnyUnusedTalent = function() return false end },
            ["ui.church.ChurchPage"] = { hasAnyChurchBadge = function() return false end },
            ["ui.story.task.TaskPage"] = { hasClaimable = function() return false end },
        }
        rawset(_G, "require", function(name)
            assert(mods[name], "unmocked dependency: " .. tostring(name))
            return mods[name]
        end)
        local function fresh(name)
            -- UrhoX 的 require 另有引擎侧缓存，仅清 package.loaded 不会重建 playLoaded。
            -- 用 ResourceCache 只读真实 Lua 资源，再用标准 load 编译同一源码得到独立实例。
            -- 源码读取不经过玩家 File；没有 debug、私有变量注入或源码字符串替换。
            local path = name:gsub("%.", "/") .. ".lua"
            local sourceFile = cache:GetFile(path)
            assert(sourceFile and sourceFile:IsOpen(), "cannot read real module source: " .. path)
            local lines = {}
            while not sourceFile:IsEof() do lines[#lines + 1] = sourceFile:ReadLine() end
            sourceFile:Dispose()
            local chunk, compileErr = load(table.concat(lines, "\n"), "@" .. path, "t", _G)
            assert(chunk, compileErr)
            return chunk()
        end
        ---@type any
        local settings = fresh("ui.hud.popup.SettingsPanel")
        mods["ui.hud.popup.SettingsPanel"] = settings
        local function capture(fn)
            clear(draws)
            check(#vgState.stack == 0, "draw 前 NanoVG 栈为空")
            fn()
            check(#vgState.stack == 0 and near(vgState.sx, 1) and near(vgState.sy, 1)
                and near(vgState.tx, 0) and near(vgState.ty, 0), "draw 后恢复 NanoVG 变换/栈")
        end
        local function matches(kind, field, value)
            local result = {}
            for _, draw in ipairs(draws) do
                if draw.kind == kind and (not field or draw[field] == value) then result[#result + 1] = draw end
            end
            return result
        end
        local function one(kind, field, value)
            local result = matches(kind, field, value)
            assert(#result == 1, "expected one " .. kind .. "/" .. tostring(value) .. ", actual=" .. #result)
            return result[1]
        end
        local function readSettings() return cjson.decode(memory["settings_volume.json"]) end
        local function settledOpen(panel)
            panel.open()
            clock.elapsedTime = clock.elapsedTime + 1
        end
        local function expectStillOpen(panel, label)
            clock.elapsedTime = clock.elapsedTime + 0.3
            capture(function() panel.draw(vg) end)
            check(panel.isOpen(), label .. " 未被旧边界关闭")
        end
        local function assertLayout(oy, standalone)
            local chips = {}
            for _, draw in ipairs(draws) do
                if draw.kind == "rounded" and near(draw.w, 150) and near(draw.h, 44) then
                    chips[#chips + 1] = draw
                end
            end
            check(#chips == 5, "语言芯片实际画出五枚，不是旧3列")
            local expectedX = { 693, 853, 693, 853, 853 }
            local expectedY = { 1480, 1480, 1534, 1534, 1588 }
            for index, lang in ipairs(langs) do
                local text = one("text", "text", lang.label)
                check(near(text.x, expectedX[index]) and near(text.y, expectedY[index] + oy),
                    lang.id .. " 中心为两列三行活坐标，offset=" .. oy)
                check(text.align == NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, lang.id .. " 居中文字")
                local chip = chips[index] or {}
                check(near(chip.x, expectedX[index] - 75) and near(chip.y, expectedY[index] + oy - 22),
                    lang.id .. " 实际圆角芯片与文字/点击布局一致")
            end
            check(near((chips[5] or {}).x, (chips[2] or {}).x), "末行单枚与右列对齐")
            local code = one("text", "text", i18n.t("redeem_code"))
            local codeBg = one("nine", "style", "btn")
            check(near(code.x, 540) and near(code.y, 1768 + oy), "兑换码文字中心=" .. (1768 + oy))
            check(near(codeBg.x + codeBg.w * 0.5, 540) and near(codeBg.y + codeBg.h * 0.5, 1768 + oy)
                and near(codeBg.w, 410) and near(codeBg.h, 100), "兑换码背景与文本中心/热区一致")
            if standalone then
                local bg = one("nine", "style", "panel")
                check(near(bg.x, 65) and near(bg.w, 950) and near(bg.y, 785.5)
                    and near(bg.y + bg.h, 1918), "独立设置背景保持顶785.5，底扩展至1918")
            end
        end

        runCase("套装偏好仍可持久化和重新初始化", function()
            settings.init(vg)
            check(settings.isSetIconsEnabled(), "无旧档默认套装徽记开启")
            settings.setSetIconsEnabled(false)
            check(not settings.isSetIconsEnabled() and readSettings().showSetIcons == false,
                "false 套装偏好写入内存 settings_volume.json")
            local falseSave = memory["settings_volume.json"]
            settings.setSetIconsEnabled(true)
            check(readSettings().showSetIcons == true, "true 套装偏好仍可保存")
            memory["settings_volume.json"] = falseSave
            settings.init(vg)
            check(not settings.isSetIconsEnabled(), "init 从内存旧档恢复 false，不变默认值")
        end)
        settledOpen(settings)
        runCase("独立 draw 五语2+2+1布局和背景", function()
            check(settings.getEmbedYOffset() == 40, "嵌入默认偏移仍为40")
            capture(function() settings.draw(vg) end)
            assertLayout(0, true)
        end)
        for _, offset in ipairs({ 40, 0, 125 }) do
            runCase("drawEmbedded offset=" .. offset .. " 共用语言/兑换码布局", function()
                capture(function()
                    if offset == 40 then settings.drawEmbedded(vg) else settings.drawEmbedded(vg, offset) end
                end)
                assertLayout(offset, false)
                check(#matches("nine", "style", "panel") == 0, "嵌入不画独立面板")
            end)
        end

        -- 点击区域示意（芯片44高；相邻行中心差54，垂直缝10；列间缝10）。
        -- row1: [618..768] [778..928], y1458..1502
        -- row2: [618..768] [778..928], y1512..1556
        -- row3:            [778..928], y1566..1610
        -- 检测：每枚中心/内角 -> 指定语言；缝/末行左空格 -> 无切换、无特效翻转/落盘。
        -- 嵌入把所有 Y 同加offset；独立面板在内部留白消费true，嵌入留白返回false。
        local expectedX = { 693, 853, 693, 853, 853 }
        local expectedY = { 1480, 1480, 1534, 1534, 1588 }
        for _, mode in ipairs({ { label = "standalone", embedded = false, oy = 0 },
            { label = "embedded-default", embedded = true, oy = 40 },
            { label = "embedded-custom", embedded = true, oy = 125 } }) do
            local function click(x, y)
                if mode.embedded then
                    if mode.oy == 40 then return settings.handleEmbeddedInput(x, y) end
                    return settings.handleEmbeddedInput(x, y, mode.oy)
                end
                return settings.handleInput(x, y)
            end
            runCase(mode.label .. " 五语中心及内角实际切换/保持false偏好", function()
                for index, lang in ipairs(langs) do
                    for _, delta in ipairs({ { x = 0, y = 0 }, { x = -74, y = -21 }, { x = 74, y = 21 } }) do
                        i18n.set(lang.id == "en" and "zh_CN" or "en")
                        local before = writes["settings_volume.json"] or 0
                        check(click(expectedX[index] + delta.x, expectedY[index] + mode.oy + delta.y),
                            mode.label .. " 命中 " .. lang.id)
                        check(i18n.get() == lang.id, mode.label .. " 实际切换 " .. lang.id)
                        local saved = readSettings()
                        check(saved.language == lang.id and saved.showSetIcons == false
                            and not settings.isSetIconsEnabled(), "切语言落盘且不会丢 false 套装偏好")
                        check((writes["settings_volume.json"] or 0) == before + 1, "一次语言点击只保存一次")
                    end
                end
                settings.persistLanguage()
                check(readSettings().showSetIcons == false, "标题页 persistLanguage 同样保留 false")
                expectStillOpen(settings, mode.label)
            end)
            runCase(mode.label .. " 行/列缝和末行空位不误触特效", function()
                local before = writes["settings_volume.json"] or 0
                local language, effects, damage = i18n.get(), settings.isEffectsEnabled(), settings.isDamageNumbersEnabled()
                for _, gap in ipairs({ { x = 693, y = 1507 }, { x = 853, y = 1507 },
                    { x = 693, y = 1561 }, { x = 853, y = 1561 }, { x = 773, y = 1480 },
                    { x = 773, y = 1534 }, { x = 693, y = 1588 }, { x = 853, y = 1457 } }) do
                    check(click(gap.x, gap.y + mode.oy) == (not mode.embedded),
                        mode.label .. " 留白消费语义 x=" .. gap.x .. " y=" .. gap.y)
                    check(i18n.get() == language and settings.isEffectsEnabled() == effects
                        and settings.isDamageNumbersEnabled() == damage, "语言缝隙不切换语言/特效/伤害开关")
                end
                check((writes["settings_volume.json"] or 0) == before, "留白不写设置档")
                expectStillOpen(settings, mode.label .. " gaps")
            end)
            runCase(mode.label .. " 兑换码实际热区及子面板优先", function()
                redeem.close()
                local before = redeemState.opens
                check(click(540, 1768 + mode.oy) and redeemState.opens == before + 1,
                    "迁移后的兑换码中心可点击")
                check(feedback[#feedback] == "set_code", "兑换码使用原按钮反馈key")
                local inputBefore = redeemState.inputs
                check(click(10, 10) and redeemState.inputs == inputBefore + 1, "子面板优先，不触发父面板外部关闭")
                redeem.close()
                expectStillOpen(settings, mode.label .. " redeem")
                check(click(540, 1817 + mode.oy) and redeemState.opens == before + 2,
                    "兑换码底部内边可点，不被旧背景底边1570.5关闭")
                redeem.close()
                expectStillOpen(settings, mode.label .. " redeem lower edge")
            end)
        end
        runCase("独立设置背景边缘与外部关闭仍一致", function()
            for _, y in ipairs({ 785.5, 1918 }) do
                check(settings.handleInput(100, y), "背景边界事件被消费")
                expectStillOpen(settings, "inside edge " .. y)
            end
            for _, y in ipairs({ 785.4, 1918.1 }) do
                check(settings.handleInput(100, y), "背景外事件被消费")
                clock.elapsedTime = clock.elapsedTime + 0.3
                capture(function() settings.draw(vg) end)
                check(not settings.isOpen(), "背景外 y=" .. y .. " 关闭动画完成")
                settledOpen(settings)
            end
        end)

        local function newPip(seconds)
            memory["play_time.json"] = cjson.encode({ seconds = seconds })
            ---@type any
            local panel = fresh("ui.hud.popup.PlayerInfoPanel")
            panel.init(vg)
            -- 原规则：update 即使闭合也 loadPlayTime；0 不累加。
            panel.update(0)
            settledOpen(panel)
            return panel
        end
        local function expectTime(panel, text)
            capture(function() panel.draw(vg) end)
            local label = one("text", "text", text)
            check(near(label.x, 355) and near(label.y, 430), "远征时间文案仍在原头像旁坐标")
            check(#matches("text", "text", "游玩时间 不足1分") == 0, "不回退旧游玩时间文案")
        end
        for _, sample in ipairs({ { seconds = 59.9, text = "远征时间 不足1分" },
            { seconds = 125, text = "远征时间 2分" }, { seconds = 7385, text = "远征时间 2小时3分" },
            { seconds = 184219, text = "远征时间 2天3小时" } }) do
            runCase("PIP 四格式从内存 seconds 加载：" .. sample.text, function()
                local beforeReads = reads["play_time.json"] or 0
                local panel = newPip(sample.seconds)
                check((reads["play_time.json"] or 0) == beforeReads + 1, "真实 PIP update 读取内存秒数一次")
                expectTime(panel, sample.text)
                memory["play_time.json"] = cjson.encode({ seconds = 999999 })
                panel.update(0)
                check((reads["play_time.json"] or 0) == beforeReads + 1, "后续 update 不重复覆盖已加载秒数")
                expectTime(panel, sample.text)
                panel.close()
                check(cjson.decode(memory["play_time.json"]).seconds == math.floor(sample.seconds),
                    "close 持久化原累计秒数并向下取整，不使用被改写的测试文件")
            end)
        end
        runCase("PIP 背景与嵌入兑换码/五语输入一致", function()
            local panel = newPip(0)
            capture(function() panel.draw(vg) end)
            local bg = one("nine", "style", "panel")
            check(near(bg.x, 65) and near(bg.w, 950) and near(bg.y, 193.5)
                and near(bg.y + bg.h, 2070.5), "PIP 背景保持顶193.5，底为2070.5")
            assertLayout(40, false)
            for index, lang in ipairs(langs) do
                i18n.set(lang.id == "en" and "zh_CN" or "en")
                check(panel.handleInput(expectedX[index], expectedY[index] + 40) and i18n.get() == lang.id,
                    "PIP 真实 handleInput 转发嵌入五语 " .. lang.id)
                expectStillOpen(panel, "PIP " .. lang.id)
            end
            redeem.close()
            local opens = redeemState.opens
            check(panel.handleInput(540, 1808) and redeemState.opens == opens + 1,
                "PIP 嵌入兑换码中心1808可点")
            redeem.close()
            expectStillOpen(panel, "PIP redeem")
            check(panel.handleInput(540, 1857) and redeemState.opens == opens + 2,
                "PIP 兑换码底部仍可点")
            redeem.close()
            expectStillOpen(panel, "PIP redeem lower edge")
            panel.close()
        end)
        runCase("PIP 原dt有效区间/闭合累加/20秒周期/close持久化", function()
            local panel = newPip(100.75)
            panel.close()
            clock.elapsedTime = clock.elapsedTime + 0.3
            capture(function() panel.draw(vg) end)
            check(not panel.isOpen(), "dt测试先让PIP完全闭合")
            local baseline = writes["play_time.json"] or 0
            for _, dt in ipairs({ -1, 0, 5, 6, "1", math.huge }) do panel.update(dt) end
            panel.update(nil)
            check((writes["play_time.json"] or 0) == baseline, "非法dt不触发周期保存")
            for _, dt in ipairs({ 4, 4, 4, 4, 3.75 }) do panel.update(dt) end
            check((writes["play_time.json"] or 0) == baseline, "闭合累计19.75秒仍未达保存阈值")
            panel.update(0.25)
            check((writes["play_time.json"] or 0) == baseline + 1
                and cjson.decode(memory["play_time.json"]).seconds == 120, "恰好累计20秒保存floor(100.75+20)")
            settledOpen(panel)
            expectTime(panel, "远征时间 2分")
            panel.update(4.999)
            panel.update(5) -- 上界严格小于5，不能累加这次5秒。
            check((writes["play_time.json"] or 0) == baseline + 1, "周期保存后积累重置，小于20不重复写")
            panel.close()
            panel.close()
            check((writes["play_time.json"] or 0) == baseline + 2
                and cjson.decode(memory["play_time.json"]).seconds == 125,
                "close只保存一次；有效4.999累加、5秒排除并向下取整")
            local loaded = fresh("ui.hud.popup.PlayerInfoPanel")
            loaded.init(vg)
            loaded.update(0)
            settledOpen(loaded)
            expectTime(loaded, "远征时间 2分")
            loaded.close()
            check(cjson.decode(memory["play_time.json"]).seconds == 125, "新的PIP实例从内存持久化125秒恢复")
        end)

        runCase("Town 遗匣/功绩对齐且六个原地点布局不变", function()
            local town = fresh("ui.town.TownScene")
            town.init(vg)
            capture(function() town.draw(vg) end)
            local loot = one("text", "text", "遗匣")
            local lootIcon = one("icon", "key", "relicbox")
            check(near(loot.x, 574 + 70) and near(loot.y, 2090)
                and near(lootIcon.x + lootIcon.w * 0.5, 467 + 70)
                and near(lootIcon.y + lootIcon.h * 0.5, 2090), "遗匣图标467+shift/文本574+shift同Y")
            local task = one("text", "text", "功绩")
            local taskIcon = one("icon", "key", "merit")
            check(near(task.x, 230 + 34) and near(task.y, 2240)
                and near(taskIcon.x + taskIcon.w * 0.5, 230 - 73)
                and near(taskIcon.y + taskIcon.h * 0.5, 2240), "功绩图标TASK_CX-73/文本TASK_CX+34且无Y-6")
            check(near(lootIcon.w, 64) and near(taskIcon.w, 64), "遗匣/功绩沿用64图标")
            local labels = matches("nine", "style", "plain")
            local oldPlain = 0
            for _, label in ipairs(labels) do
                if near(label.w, 300) and near(label.h, 64) then oldPlain = oldPlain + 1 end
            end
            check(oldPlain == 0 and #labels == 8, "移除遗匣300x64额外plain，只保留八个地点名牌")
            for _, sample in ipairs({ { text = "狱火锻炉", x = 569, y = 554, icon = "ICON_CZ_TJP.png", ix = 444 },
                { text = "终焉古树", x = 585, y = 1229, icon = "ICON_CZ_TREE.png", ix = 450 },
                { text = "月蚀黑市", x = 259, y = 846, icon = "ICON_CZ_SC.png", ix = 152 },
                { text = "尘封仓库", x = 871, y = 864, icon = "ICON_CZ_CK.png", ix = 764 },
                { text = "缄默礼拜堂", x = 292, y = 1714, icon = "ICON_CZ_JT.png", ix = 148 },
                { text = "腐鸦酒馆", x = 871, y = 1524, icon = "ICON_CZ_JG.png", ix = 764 } }) do
                local text = one("text", "text", sample.text)
                local icon = one("image", "path", "image/通用图标/" .. sample.icon)
                check(near(text.x, sample.x) and near(text.y, sample.y)
                    and near(icon.x + icon.w * 0.5, sample.ix)
                    and near(icon.y + icon.h * 0.5, sample.y), "未迁移地点仍在原坐标 " .. sample.text)
            end
            local count = #loads
            capture(function() town.draw(vg) end)
            check(#loads == count, "Town 图片按需加载后缓存，不逐帧重复加载")
        end)
        check(#fileEvents > 0 and (writes["settings_volume.json"] or 0) > 0
            and (writes["play_time.json"] or 0) > 0, "测试确实执行两份持久化但全部隔离于内存")
        check(#audioEvents > 0, "真实settings.init音量应用经过音频替身，不播放实际音频")
    end)
    if not ok then check(false, "Start exception: " .. tostring(err)) end

    -- 无论断言/加载失败均还原真实语言、require、引擎全局和模块缓存。
    if i18nReady then
        local restored, restoreErr = pcall(function() i18n.set(initialLanguage) end)
        if not restored then check(false, "restore language: " .. tostring(restoreErr)) end
    end
    clear(originalPackageLoaded)
    for key, value in pairs(originalLoaded) do originalPackageLoaded[key] = value end
    local added = {}
    for key in pairs(_G) do if originalGlobals[key] == nil then added[#added + 1] = key end end
    for _, key in ipairs(added) do rawset(_G, key, nil) end
    for key, value in pairs(originalGlobals) do rawset(_G, key, value) end
    if failures == 0 then
        print("[local_art_ui_migration_test] ALL PASS: " .. passes .. "/" .. cases
            .. " cases, " .. assertions .. " assertions")
    else
        print("[FAIL] local_art_ui_migration_test: " .. passes .. "/" .. cases
            .. " cases passed, " .. failures .. " failures, " .. assertions .. " assertions")
    end
    engine:Exit()
end
