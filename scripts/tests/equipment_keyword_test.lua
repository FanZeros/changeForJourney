-- 无引擎专项：真实 KeywordText/词典及装备、升阶、洗练、神器公开 UI 接口。
-- Lua 5.4: package.path 加入 scripts/?.lua 后 require("tests.equipment_keyword_test").run()
-- NanoVG、资源图标和只读货币 getter 使用 spy；不执行存档/网络动作。
local M = {}

-- 独立名称 oracle：不从配置/翻译实现反推期望，防止旧 name 与词典一起回流。
-- 列顺序固定为简体、繁体、英文、日文、韩文；基础 INT/LUK/Spirit 是当前规范。
local NAME_ORACLE = {
    { key = "int", canonical = "秘识", legacy = "智慧",
        titles = { "秘识", "秘識", "INT", "知力", "지력" } },
    { key = "luk", canonical = "命数", legacy = "运气",
        titles = { "命数", "命數", "LUK", "運", "운" } },
    { key = "spi", canonical = "魂火", legacy = "精神",
        titles = { "魂火", "魂火", "Spirit", "魂火", "혼화" } },
    { key = "energyShield", canonical = "护盾", legacy = "魔法护甲",
        titles = { "护盾", "護盾", "Shield", "シールド", "보호막" } },
    { key = "esBonus", canonical = "护盾加成", legacy = "能量护盾加成",
        titles = { "护盾加成", "護盾加成", "Shield bonus", "シールド補正", "보호막 보너스" } },
    { key = "threat", canonical = "怨引值", legacy = "仇恨值",
        titles = { "怨引值", "怨引值", "Threat", "敵視値", "위협 수치" } },
    { key = "finalIntBonus", canonical = "最终秘识", legacy = "最终智慧", affixId = 1007,
        titles = { "最终秘识", "最終秘識", "Final Lore", "最終秘知", "최종 비지" } },
    { key = "finalLukBonus", canonical = "最终命数", legacy = "最终运气", affixId = 1009,
        titles = { "最终命数", "最終命數", "Final Fate", "最終運命", "최종 운명" } },
    { key = "finalSpiBonus", canonical = "最终魂火", legacy = "最终精神", affixId = 1010,
        titles = { "最终魂火", "最終魂火", "Final Soulfire", "最終魂火", "최종 혼불" } },
}

function M.run()
    local count = 0
    local restores = {}
    local function replace(owner, key, value)
        local old = owner[key]
        restores[#restores + 1] = function() owner[key] = old end
        owner[key] = value
    end
    local function check(value, label)
        count = count + 1
        assert(value, label)
    end
    local ok, err = pcall(function()
        local I18n = require("core.I18n")
        local Keyword = require("ui.widget.KeywordText")
        local Locale = require("core.I18nKeywords")
        local AC = require("config.AffixConfig")
        local AD = require("systems.AttributeDef")
        local EC = require("config.EquipmentConfig")
        local ES = require("systems.EquipmentSystem")
        local oldLanguage = I18n.get()
        restores[#restores + 1] = function() I18n.set(oldLanguage) end
        local affixes = {}
        for _, list in ipairs({ AC.AFFIXES, AC.CORRUPT_AFFIXES }) do
            for _, affix in ipairs(list) do affixes[#affixes + 1] = affix end
        end
        check(#AC.AFFIXES == 45 and #AC.CORRUPT_AFFIXES == 13, "45普通+13魔化")
        for _, case in ipairs(NAME_ORACLE) do
            check(AD.META[case.key].name == case.canonical, "AD规范名独立oracle " .. case.key)
            if case.affixId then
                local affix = AC.BY_ID[case.affixId]
                check(affix.key == case.key and affix.name == case.canonical,
                    "魔化生成源独立oracle " .. case.affixId)
                check(affix.baseValue == 1.7 and affix.weight == 100 and affix.dataType == "pct",
                    "仅改魔化名称不改数值 " .. case.affixId)
            end
        end
        local Awaken = require("config.AwakeningConfig")
        check(Awaken.DATA[9][1] == "【温泉本金】：过量治疗永久魂火+0.05；处于温泉状态的队友护甲+10，治疗暴击率+5%。",
            "温泉永久魂火源文与数值")
        check(Awaken.DATA[19][1] == "【功德积累】：每次击杀永久魂火+0.05；治疗暴击额外获得1层功德。",
            "功德永久魂火源文与数值")
        check(Awaken.DATA[7][1] == "【必杀库存】：每次击杀永久连击率+0.1%；连击命中有20%概率降低目标7点护盾；光线间隔缩短至每3次攻击。",
            "必杀库存说明energyShield为护盾")
        check(AD.getDesc("threat") == "影响被敌方随机攻击的权重，怨引值越高越容易被集火",
            "静态怨引说明独立oracle")
        for languageIndex, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            I18n.set(lang)
            for _, case in ipairs(NAME_ORACLE) do
                local expectedTitle = case.titles[languageIndex]
                local definition = assert(Locale.getAttribute(case.key, lang, case.legacy))
                check(definition.key == case.key and definition.title == expectedTitle,
                    "旧名输入新标题五语oracle " .. case.key .. lang)
                check(definition.desc == Locale.getAttribute(case.key, lang).desc,
                    "旧名不改变属性说明 " .. case.key .. lang)
                local kt = Keyword.new()
                local layout = kt:_layout(nil, case.legacy, 10000, 28, { attributeKey = case.key })
                check(layout.displayText == expectedTitle, "属性模式规范显示 " .. case.key .. lang)
                kt:drawAttribute(nil, case.legacy, case.key, 20, 40, 210, 28)
                local hotspot = kt.hotspots[1]
                check(#kt.hotspots == 1 and hotspot.key == "attribute:" .. case.key
                    and hotspot.text == expectedTitle, "旧名按稳定key完整高亮 " .. case.key .. lang)
                check(kt:handleInput(hotspot.x1 + 1, hotspot.y1 + 1) and kt.popup.name == expectedTitle
                    and kt.popup.desc == definition.desc, "旧名点击弹规范标题 " .. case.key .. lang)
                local mixed = Keyword.new()
                mixed:drawAttribute(nil, "任意旧名仇恨精神", case.key, 20, 40, 210, 28)
                check(#mixed.hotspots == 1 and mixed.hotspots[1].text == expectedTitle,
                    "已知key不从任意sourceName反推 " .. case.key .. lang)
            end
            local unknown = Keyword.new()
            local unknownText = "未登记旧名精神原样"
            check(unknown:_layout(nil, unknownText, 10000, 28, {attributeKey = "unknown"}).displayText == unknownText,
                "未知属性源名回退不改写 " .. lang)
            check(Locale.getAttribute("unknown", lang, unknownText) == nil,
                "未知属性不伪造解释 " .. lang)
            for _, affix in ipairs(affixes) do
                local expected = assert(Locale.getAttribute(affix.key, lang, affix.name))
                check(expected.title == I18n.lookup(AD.META[affix.key].name), "完整规范名称不截为子词 " .. affix.key .. lang)
                check(expected.desc ~= "" and (lang == "zh_CN" or expected.desc ~= AD.getDesc(affix.key)),
                    "完整四语说明不回落简体 " .. affix.key .. lang)
                local kt = Keyword.new()
                local width, font = kt:drawAttribute(nil, affix.name, affix.key, 20, 40, 210, 28)
                check(width <= 210 and font >= 8 and #kt.hotspots == 1, "缩字不越列 " .. affix.key .. lang)
                local h = kt.hotspots[1]
                check(h.key == "attribute:" .. affix.key and h.text == I18n.lookup(AD.META[affix.key].name), "稳定key " .. affix.key .. lang)
                check(kt:handleInput(h.x1 + 1, h.y1 + 1) and kt.popup.desc == expected.desc
                    and kt.popup.name == expected.title, "名称与解释一一对应 " .. affix.key .. lang)
                check(kt:handleInput(773, 2129) and not kt:isOpen(), "第二次点击只关说明 " .. affix.key .. lang)
            end
            check(Locale.getAttribute("dropLuck", lang).desc ~= Locale.getAttribute("luk", lang).desc,
                "幸运值不等于命数/运气 " .. lang)
            for _, alias in ipairs({ {"finalIntBonus", "最终智慧"}, {"finalLukBonus", "最终运气"},
                {"finalSpiBonus", "最终精神"} }) do
                check(Locale.getAttribute(alias[1], lang, alias[2]).desc == Locale.getAttribute(alias[1], lang).desc,
                    "魔化旧名同key " .. alias[1] .. lang)
            end
        end
        I18n.set("zh_CN")
        local clipped = Keyword.new()
        clipped:drawAttribute(nil, "最终力量", "finalStrBonus", 100, 100, 210, 28,
            { clip = {100, 99, 50, 10} })
        check(#clipped.hotspots == 1 and clipped.hotspots[1].x2 == 150, "热点裁剪与视觉范围一致")
        check(not clipped:handleInput(110, 96) and not clipped:handleInput(151, 103), "容差不能穿过clip")
        clipped:beginFrame()
        clipped:drawPopup(nil)
        check(#clipped.hotspots == 0 and not clipped:isOpen(), "空表清理旧热区")
        local readonly = Keyword.new()
        readonly:drawAttribute(nil, "力量", "str", 0, 20, 210, 28, { interactive = false })
        check(#readonly.hotspots == 0, "只读预览不产生热区")

        -- 字体/颜色/文字 spy，真实布局与热区不替换。
        local texts, color, font, align = {}, {}, 28, 0
        local images, circles, panels, rects = {}, {}, {}, {}
        local function noop() end
        for _, name in ipairs({ "nvgFontFace", "nvgTextAlign", "nvgTextLetterSpacing", "nvgBeginPath",
            "nvgRoundedRect", "nvgRect", "nvgCircle", "nvgFill", "nvgStroke", "nvgStrokeWidth",
            "nvgStrokeColor", "nvgMoveTo", "nvgLineTo", "nvgClosePath", "nvgSave", "nvgRestore",
            "nvgTranslate", "nvgScale", "nvgGlobalAlpha", "nvgIntersectScissor", "nvgFillPaint", "nvgTextBox" }) do
            replace(_G, name, noop)
        end
        for i, name in ipairs({ "NVG_ALIGN_LEFT", "NVG_ALIGN_TOP", "NVG_ALIGN_MIDDLE",
            "NVG_ALIGN_CENTER", "NVG_ALIGN_RIGHT" }) do replace(_G, name, 2 ^ (i - 1)) end
        replace(_G, "nvgFontSize", function(_, value) font = value end)
        replace(_G, "nvgTextAlign", function(_, value) align = value end)
        replace(_G, "nvgRoundedRect", function(_, x, y, w, h)
            rects[#rects + 1] = {x = x, y = y, w = w, h = h}
        end)
        replace(_G, "nvgRGBA", function(r, g, b, a) return {r, g, b, a} end)
        replace(_G, "nvgFillColor", function(_, value) color = value end)
        replace(_G, "nvgCreateImage", function() return -1 end)
        replace(_G, "nvgTextBounds", function(_, _, _, text, bounds)
            local width = utf8.len(text) * font * 0.6
            if bounds then bounds[1], bounds[2], bounds[3], bounds[4] = 0, 0, width, font end
            return width
        end)
        replace(_G, "nvgCurrentTransform", function(_, matrix) matrix[1], matrix[2], matrix[3], matrix[4] = 1, 0, 0, 1 end)
        replace(_G, "nvgText", function(_, x, y, text)
            texts[#texts + 1] = {text = text, x = x, y = y, color = color, font = font, align = align}
        end)
        replace(_G, "time", { elapsedTime = 100 })
        local Draw = require("core.DrawUtil")
        replace(Draw, "drawImageCentered", function(_, image, x, y, w, h, alpha)
            images[#images + 1] = {image = image, x = x, y = y, w = w, h = h, alpha = alpha}
        end)
        replace(Draw, "drawTextStroke", function(vg, x, y, text, size, alignment, r, g, b)
            nvgFontSize(vg, size); nvgTextAlign(vg, alignment)
            nvgFillColor(vg, nvgRGBA(r, g, b, 255)); nvgText(vg, x, y, text)
        end)
        replace(Draw, "drawDoubleChevron", noop)
        local Dark = require("core.DarkIcon")
        replace(Dark, "drawNine", function(_, _, x, y, w, h)
            panels[#panels + 1] = {x = x, y = y, w = w, h = h}
        end)
        replace(Dark, "drawQualityBg", noop)
        replace(Dark, "drawIconDark", noop)
        local Feedback = require("systems.ButtonFeedback")
        replace(Feedback, "begin", function() return false end)
        replace(Feedback, "finish", noop)
        replace(Feedback, "trigger", noop)
        local Images = require("ui.widget.ImageCache")
        replace(Images, "getEquipIcon", function() return -1 end)
        local Tutorial = require("systems.TutorialManager")
        replace(Tutorial, "isBuildingUnlocked", function() return false end)
        replace(Tutorial, "isActive", function() return false end)
        local State = require("core.GameState")
        for _, name in ipairs({ "getLevel", "getGold", "getEssence", "getWeaponScroll", "getOffhandScroll",
            "getArmorScroll", "getHelmetScroll", "getShoesScroll", "getAccessoryScroll" }) do
            replace(State, name, function() return 100000 end)
        end
        local instances = {}
        local realNew = Keyword.new
        replace(Keyword, "new", function(opts)
            local kt = realNew(opts); instances[#instances + 1] = kt; return kt
        end)
        local vg = {}
        local equip = ES.generate("W1", 1, 3)
        equip.seq, equip.ascendLevel = 98001, 4
        equip.affixes = {
            {affixId = 45, key = "dropLuck", name = "幸运值", quality = 2, value = 7.5},
            {affixId = 1009, key = "finalLukBonus", name = "最终运气", quality = 1, value = 2.5, isCorrupt = true},
        }
        local state = {open = true, tab = "xilian", selectedEquip = equip, selectedSeq = equip.seq,
            selectedEquipSlot = "weapon"}
        local grade = { D = 9101, C = 9102, B = 9103, A = 9104, S = 9105 }
        replace(_G, "nvgCreateImage", function(_, path)
            local key = path:match("ICON_CZBZ_([DCBAS])%.png$")
            return key and grade[key] or -1
        end)
        replace(_G, "nvgCircle", function(_, x, y, radius)
            circles[#circles + 1] = {x = x, y = y, radius = radius}
        end)
        replace(_G, "nvgImagePattern", function(_, x, y, w, h, _, image, alpha)
            images[#images + 1] = {image = image, x = x, y = y, w = w, h = h, alpha = alpha}
            return {}
        end)
        local function gradeCount(key)
            local n = 0
            for _, image in ipairs(images) do if image.image == grade[key] then n = n + 1 end end
            return n
        end
        local actions = 0
        local function client() return {sendAction = function() actions = actions + 1 end} end
        local ctx = { state = state, imgGrade = grade, formatAffixValue = function(_, v) return tostring(v) end,
            formatCompact = tostring, imgLock = -1, imgEnhBtn = -1, imgReplaceBtn = -1, imgEssenceIcon = -1,
            imgGoldQBg = -1, imgGoldIcon = -1, imgXlBefore = -1, imgPlus = -1, imgQualityBg = {},
            getClient = client, getProtocol = function() return require("shared.Protocol") end }
        local Enhance = require("ui.blacksmith.BlacksmithEnhance")
        local Refine = require("ui.blacksmith.BlacksmithRefine")
        local Input = require("ui.blacksmith.BlacksmithInput").bind({
            BlacksmithEnhance = Enhance, BlacksmithRefine = Refine, state = state,
            TAB_ITEMS = {}, SLIDER_W = 1, SLIDER_H = 1, hitTest = Draw.hitTest,
            WORKBENCH_CX = 540, WORKBENCH_CY = 420, WORKBENCH_SIZE = 160,
            closePage = noop, forceClose = noop,
        })
        Enhance.setContext(ctx); Refine.setContext(ctx)
        Enhance.updateEnhanceData(equip); Refine.updateRefineData(equip)
        -- 原UI准备流程已有魔化数值/名称水合；只验证新增显示层不再回写水合后的实例。
        local storedAffix = equip.affixes[2]
        local storedName, storedKey, storedValue, storedId = storedAffix.name, storedAffix.key,
            storedAffix.value, storedAffix.affixId
        local function keywordInstance(key)
            for i = #instances, 1, -1 do
                local kt = instances[i]
                for _, h in ipairs(kt.hotspots) do
                    if h.key == key then return kt, h end
                end
            end
            error("missing hotspot " .. key)
        end
        local function tap(x, y)
            Input.handleDragBegin(x, y)
            Input.handleDragEnd(x, y)
            return Input.handleInput(x, y)
        end
        Refine.drawPanel(vg)
        check(gradeCount("D") == 1 and gradeCount("C") == 1 and #circles == 0, "洗练前腐化D与普通C均保留评级，无紫点")
        local kt, h = keywordInstance("attribute:dropLuck")
        check(tap(h.x1 + 1, h.y1 + 1) and kt:isOpen(), "真实洗练Begin→End→Input开解释")
        check(tap(773, 2129) and not kt:isOpen() and actions == 0, "洗练按钮首点只关说明不派动作")
        Refine.onActionResult({success = true, refinePreview = equip.affixes, seq = equip.seq})
        time.elapsedTime = 101
        images, circles = {}, {}
        Refine.drawPanel(vg)
        check(gradeCount("D") == 2 and gradeCount("C") == 2 and #circles == 0, "洗练前后均保留腐化品级，无紫点")
        kt, h = keywordInstance("attribute:finalLukBonus")
        local n = 0
        for _, s in ipairs(kt.hotspots) do if s.key == "attribute:finalLukBonus" then n = n + 1 end end
        check(n == 2, "洗练前后均有完整魔化词条热点")
        check(Input.handleInput(540, 1889), "打开真实材料modal")
        check(Input.handleInput(680, 1432) and not kt:isOpen(), "材料modal遮挡右词条时优先选项不弹说明")
        local beforeActions = actions
        -- 关闭材料选项后的下一次关键词点击恢复，不影响数值/锁区。
        Refine.drawPanel(vg)
        check(actions == beforeActions, "材料选择不派业务")
        Refine.clearKeywords()
        state.tab = "qianghua"
        images, circles = {}, {}
        Enhance.drawPanel(vg)
        check(gradeCount("D") == 1 and gradeCount("C") == 1 and #circles == 0, "强化保留腐化品级，无紫点")
        kt, h = keywordInstance("attribute:dropLuck")
        check(tap(h.x1 + 1, h.y1 + 1) and kt:isOpen(), "真实升阶Begin→End→Input开解释")
        check(tap(307, 2129) and not kt:isOpen() and actions == 0, "升阶按钮首点只关说明")
        Enhance.updateEnhanceData(equip)
        check(#kt.hotspots == 0, "换装备刷新清升阶热区")
        check(equip.affixes[2].name == storedName and equip.affixes[2].key == storedKey
            and equip.affixes[2].value == storedValue and equip.affixes[2].affixId == storedId,
            "显示不改变已水合词条name/key/value/id")
        local valueDrawn, corruptDrawn = false, false
        for _, t in ipairs(texts) do
            if t.text == "7.5" then valueDrawn = true end
            if t.text == "最终命数" and t.color[1] == 0xef and t.color[3] == 0xff then corruptDrawn = true end
            check(t.text ~= "最终运气", "真实洗练/升阶不能回流旧名称")
        end
        check(valueDrawn and corruptDrawn, "数值与腐化紫色规范名称保持")

        local Store = require("core.PlayerStore")
        replace(Store, "Get", function(module)
            if module == "equipment" then return {inventory = {[tostring(equip.seq)] = equip}, equipped = {}} end
            return nil
        end)
        local Detail = require("ui.character.equip.EquipmentDetail")
        Detail.init(vg)
        Detail.open(equip.seq, "weapon", nil, false, "bag")
        time.elapsedTime = 102
        images, circles = {}, {}
        Detail.draw(vg)
        check(gradeCount("D") == 1 and gradeCount("C") == 1 and #circles == 0,
            "大详情保留腐化品级，无紫点 D=" .. gradeCount("D") .. " C=" .. gradeCount("C") .. " circles=" .. #circles)
        kt, h = keywordInstance("attribute:dropLuck")
        local detailKt = kt
        local function detailTap(x, y)
            Detail.handleDragBegin(x, y)
            Detail.handleDragEnd()
            return Detail.handleInput(x, y)
        end
        check(detailTap(h.x1 + 1, h.y1 + 1) and kt:isOpen(), "大详情真实按下松手点击关键词")
        check(detailTap(-10, -10) and not kt:isOpen() and Detail.isOpen(), "详情下次点击只关说明不关闭面板")
        detailTap(h.x1 + 1, h.y1 + 1)
        Detail.handleDragBegin(-10, -10)
        Detail.handleDragMove(-10, -9) -- 宿主15px以内仍会在松手派tap。
        Detail.handleDragEnd()
        check(Detail.handleInput(-10, -9) and Detail.isOpen() and not kt:isOpen(), "微抖动Move后松手仍只消费原说明")
        -- 足够多行产生实际滚动；业务词条值保持，渲染和输入必须共享scrollY。
        local saved = equip.affixes
        equip.affixes = {}
        for i = 1, 20 do equip.affixes[i] = saved[(i - 1) % 2 + 1] end
        Detail.draw(vg)
        Detail.handleScroll(-4)
        Detail.draw(vg)
        local clippedSpot = kt.hotspots[1]
        check(clippedSpot ~= nil and clippedSpot.clip ~= nil, "大详情滚动后只保留可见词条热区")
        local scroll = clippedSpot.clip[2] - 980
        check(scroll > 0, "真实详情产生正滚动")
        check(detailTap(clippedSpot.x1 + 1, clippedSpot.y1 + 1 - scroll) and kt:isOpen(), "滚动输入补偿命中可见词条")
        check(math.abs(kt.popup.topY - (clippedSpot.y1 - scroll)) < 0.01, "解释锚点扣回滚动量")
        Detail.close()
        equip.affixes = saved
        Detail.open(equip.seq, "weapon", nil, true, "smith", 100, 600)
        Detail.draw(vg)
        check(#detailKt.hotspots > 0, "compact真实详情保留词条热点")
        local before = #detailKt.hotspots
        Detail.drawReadOnly(vg, equip, 0, 0)
        check(#detailKt.hotspots == before, "只读比较不清主窗口热点")
        Detail.close()

        -- 装备详情配色/评级专项：真实大小入口、只读与比较均使用同一绘制实现。
        local SC = require("config.EquipmentSetConfig")
        local Power = require("systems.EquipmentPower")
        replace(Power, "score", function() return 777777777 end)
        local sample = {
            seq = 98002, templateId = "W1", name = EC.ITEMS.W1.name, type = EC.ITEMS.W1.type,
            slot = "weapon", quality = 3, level = 9999, ascendLevel = 4, affixMult = 2,
            baseStats = { {"maxHp", 321}, {"armor", 12.5}, {"str", 3.5} },
            affixes = {
                {key = "atkSpeed", name = "攻击速度", quality = 1, value = 1.5, ascBonus = 0.5},
                {key = "dropLuck", name = "幸运值", quality = 2, value = 7.5},
                {key = "critRate", name = "暴击率", quality = 3, value = 4.5},
                {key = "physPen", name = "物理穿透", quality = 4, value = 9.5},
                {key = "finalLukBonus", name = "最终运气", quality = 5, value = 2.5, isCorrupt = true},
            },
        }
        local sampleData = {inventory = {[tostring(sample.seq)] = sample}, equipped = {}}
        replace(Store, "Get", function(module) return module == "equipment" and sampleData or nil end)
        local function resetDetailSpy() texts, images, panels, rects, circles = {}, {}, {}, {}, {} end
        local function textCall(text, alignment)
            for _, call in ipairs(texts) do
                if call.text == text and (not alignment or call.align == alignment) then return call end
            end
        end
        local function colorIs(call, expected)
            return call and call.color[1] == expected[1] and call.color[2] == expected[2]
                and call.color[3] == expected[3]
        end
        local function affixValue(affix)
            local value = ES.effectiveAffixValue(sample, affix)
            local meta = AD.META[affix.key]
            return "+" .. (meta.dataType == AD.TYPE_PCT and string.format("%.1f%%", value)
                or meta.dataType == AD.TYPE_INT and tostring(math.floor(value)) or string.format("%.1f", value))
        end
        local function checkDetailRows(label, badgeImages)
            local mainColor, fixedColor = {244, 237, 224}, {168, 191, 207}
            for index, stat in ipairs(sample.baseStats) do
                local expected = index == 1 and mainColor or fixedColor
                local value = ES.formatBaseStatValue(stat[1], ES.effectiveBaseStatValue(sample, index))
                check(colorIs(textCall(AD.META[stat[1]].name), expected), label .. "主/固定副名称分色 " .. index)
                check(colorIs(textCall(value, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE), expected),
                    label .. "主/固定副数值分色且保留升阶生效值 " .. index)
            end
            for index, affix in ipairs(sample.affixes) do
                local corrupt = AC.isCorruptAffix(affix)
                local name = textCall(affix.name)
                local value = textCall(affixValue(affix), NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                check(colorIs(name, corrupt and {239, 121, 255} or {232, 200, 106}), label .. "随机名称金/腐化紫 " .. index)
                check(colorIs(value, corrupt and {226, 164, 243} or {114, 242, 245}),
                    label .. "随机数值浅青/腐化浅紫，倍率与旧升阶投入不丢 " .. index)
                local key = ({"D", "C", "B", "A", "S"})[index]
                if badgeImages then
                    check(gradeCount(key) == 1, label .. "真实评级图片 " .. key)
                else
                    check(textCall(key, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE) ~= nil,
                        label .. "缺图文字评级 " .. key)
                end
            end
            check(textCall("随机属性") ~= nil and textCall(EC.QUALITY[3].name) ~= nil
                and textCall("Lv.9999") ~= nil and textCall("777777777") ~= nil,
                label .. "随机标题/完整品质/长等级/完整战力保留")
            check(textCall("升阶") ~= nil and #circles == 0, label .. "原升阶标记保留，不把腐化评级改紫点")
        end
        for _, compact in ipairs({false, true}) do
            Detail.open(sample.seq, "weapon", nil, compact, "bag", 100, 600)
            time.elapsedTime = time.elapsedTime + 1
            resetDetailSpy(); Detail.draw(vg)
            checkDetailRows(compact and "compact" or "大详情", true)
            check(#detailKt.hotspots == #sample.baseStats + #sample.affixes, "主窗口每条属性仅一个关键词热点")
            local h = detailKt.hotspots[#sample.baseStats + 1]
            local image = images[1]
            check(h.x1 > (compact and 533 or 205), "关键词名称向右给评级留空间")
            for _, drawn in ipairs(images) do
                if drawn.image == grade.D then image = drawn end
            end
            check(image.x + image.w < h.x1, "评级图片不覆盖关键词热区")
            if compact then
                local x = (h.x1 + 1) * 0.92 + 112 - 505 * 0.92
                local y = (h.y1 + 1) * 0.92 + 600
                check(detailTap(x, y) and detailKt:isOpen(), "compact徽章缩进后真实输入仍命中随机关键词")
                local hotspotCount = #detailKt.hotspots
                Detail.drawReadOnly(vg, sample, 0, 0)
                check(#detailKt.hotspots == hotspotCount and detailKt:isOpen(), "只读预览不清主窗口解释与热区")
                check(detailTap(-10, -10) and not detailKt:isOpen() and Detail.isOpen(), "compact关键词首点关说明不关闭详情")
            end
            Detail.close()
        end
        resetDetailSpy(); Detail.drawReadOnly(vg, sample, 0, 0)
        checkDetailRows("只读", true)
        local readonlyW, readonlyH = Detail.readOnlySize(sample)
        check(math.abs(readonlyW - panels[1].w * 0.92) < 0.001
            and math.abs(readonlyH - panels[1].h * 0.92) < 0.001, "只读声明尺寸与真实底板同源")
        check(#detailKt.hotspots == 0 and textCall(I18n.t("wear")) == nil, "只读不污染主窗口热点也不显示穿戴按钮")

        -- 不新增资源；未init与图片加载失败都须显示每条真实品级。
        replace(_G, "nvgCreateImage", function() return -1 end)
        Detail.init(vg)
        for _, compact in ipairs({false, true}) do
            Detail.open(sample.seq, "weapon", nil, compact, "bag", 100, 600)
            time.elapsedTime = time.elapsedTime + 1
            resetDetailSpy(); Detail.draw(vg)
            checkDetailRows(compact and "compact缺图" or "大详情缺图", false)
            Detail.close()
        end
        resetDetailSpy(); Detail.drawReadOnly(vg, sample, 0, 0)
        checkDetailRows("只读缺图", false)
        replace(_G, "nvgCreateImage", function(_, path)
            local key = path:match("ICON_CZBZ_([DCBAS])%.png$")
            return key and grade[key] or -1
        end)
        Detail.init(vg)

        -- 套装和按钮按新增随机标题的实际底部下移；无主属性时不能侵占 Lv 行。
        local setTemplate = ""
        for id, template in pairs(EC.ITEMS) do
            if template.slot == "weapon" and SC.getSetIdForTemplate(template) == "carapace" then
                setTemplate = id; break
            end
        end
        check(setTemplate ~= "", "布局专项真实套装模板存在")
        sample.templateId = setTemplate
        local allStats, allAffixes = sample.baseStats, sample.affixes
        for _, stats in ipairs({{}, {allStats[1]}, allStats}) do
            sample.baseStats = stats
            for _, affixes in ipairs({{}, {allAffixes[1]}, allAffixes}) do
                sample.affixes = affixes
                Detail.open(sample.seq, "weapon", nil, true, "bag", 100, 600)
                resetDetailSpy(); Detail.draw(vg)
                local panel, setBlock = panels[1], rects[1]
                local button = textCall(I18n.t("wear"))
                check(panel and setBlock and button and setBlock.y + setBlock.h < button.y - 32
                    and button.y + 32 <= panel.h - 18, "套装全文与64高按钮完整留在compact底板内")
                local screenX = 112 + 300 * 0.92
                check(Detail.containsPoint(screenX, 600 + (panel.h - 1) * 0.92)
                    and not Detail.containsPoint(screenX, 600 + (panel.h + 1) * 0.92),
                    "compact内容高度变化后底部命中边界与真实底板一致")
                local lastValue = nil ---@type table|nil
                for _, call in ipairs(texts) do
                    if call.align == NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE then lastValue = call end
                end
                if lastValue then
                    check(lastValue.y + 30 + 24 + 10 <= setBlock.y, "最后属性与套装保留完整内容底部间隔")
                end
                if #affixes > 0 then
                    local title = textCall("随机属性")
                    local firstValue = textCall(affixValue(affixes[1]), NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                    check(title and firstValue and title.y + 13 + 12 + 30 == firstValue.y,
                        "随机标题与首行使用同源布局，字号和行高不重叠")
                    check(#stats > 0 or title.y - 13 >= 180, "无baseStats随机标题在完整Lv行下方")
                else
                    check(textCall("随机属性") == nil, "无随机词条不增空标题和无效高度")
                end
                Detail.close()
                resetDetailSpy(); Detail.drawReadOnly(vg, sample, 0, 0)
                local _, declaredH = Detail.readOnlySize(sample)
                check(math.abs(declaredH - panels[1].h * 0.92) < 0.001
                    and rects[1].y + rects[1].h < panels[1].h, "所有0/1/多属性只读尺寸含完整套装")
            end
        end
        sample.baseStats, sample.affixes = allStats, allAffixes
        local compare = {}
        for key, value in pairs(sample) do compare[key] = value end
        compare.seq = 98003
        sampleData.inventory[tostring(compare.seq)] = compare
        sampleData.equipped[1] = {weapon = compare.seq}
        Detail.open(sample.seq, "weapon", 1, true, "bag", 100, 600)
        resetDetailSpy(); Detail.draw(vg)
        for _, key in ipairs({"D", "C", "B", "A", "S"}) do
            check(gradeCount(key) == 2, "主/比较窗口均保留真实词条评级 " .. key)
        end
        check(#panels == 2 and #detailKt.hotspots == 8, "比较窗口只读，不增加或清除主窗口8个关键词热点")
        local previewKt = instances[#instances]
        check(#previewKt.hotspots == 0 and not previewKt:isOpen(), "比较及遗匣共用只读关键词实例不产生热点")
        Detail.close()

        -- 页签只检查当前工作台；背包另有可强化装备不能串标，资源变化实时生效。
        local Page = require("ui.blacksmith.BlacksmithPage")
        local Dispatcher = require("runtime.ClientDispatcher")
        replace(Dispatcher, "get", function(module)
            if module == "equipment" then return {inventory = {[tostring(equip.seq)] = equip}} end
            return nil
        end)
        local Config = require("config.BlacksmithConfig")
        local ExpTable = require("config.ExpTable")
        local ownedGold, ownedScroll, playerLevel = 100000000, 100000000, 100000
        replace(State, "getGold", function() return ownedGold end)
        replace(State, "getWeaponScroll", function() return ownedScroll end)
        replace(State, "getLevel", function() return playerLevel end)
        Page.setSelectedEquip(nil)
        Page.markEnhanceDirty()
        check(Page.canEnhanceAny() and not Page.canEnhanceSelected(), "空工作台不被背包可强化装备点亮")
        Page.setSelectedEquip(equip)
        local cost = Config.getAscendCost(equip.ascendLevel + 1)
        ownedGold, ownedScroll = cost.gold, cost.scroll
        check(Page.canEnhanceSelected(), "当前装备材料刚好够升一级时点亮")
        ownedGold = cost.gold - 1
        check(not Page.canEnhanceSelected(), "金币不足立即熄灭，不借用全背包缓存")
        ownedGold, ownedScroll = cost.gold, cost.scroll - 1
        check(not Page.canEnhanceSelected(), "对应卷轴不足立即熄灭")
        ownedScroll = cost.scroll
        check(Page.canEnhanceSelected(), "补足材料不需要缓存刷新即恢复")
        local savedLevel = equip.ascendLevel
        equip.ascendLevel = Config.MAX_ENHANCE_LEVEL
        check(not Page.canEnhanceSelected(), "当前装备满阶时熄灭")
        playerLevel = 1
        equip.ascendLevel = ExpTable.getEnhanceLevelCap(playerLevel)
        check(not Page.canEnhanceSelected(), "达到玩家等级上限时熄灭")
        equip.ascendLevel, playerLevel = savedLevel, 100000
        Page.setSelectedEquip(nil)
        check(not Page.canEnhanceSelected(), "移走当前装备即熄灭")
        Page.setSelectedEquip(equip)
        check(Page.canEnhanceSelected() and actions == 0, "重新放入装备恢复，检查不发强化动作")
        Page.setSelectedEquip(nil)

        -- 真实神器详情保留橙色数值、灰色比例，关键词popup点击不能穿透安装按钮。
        local Assets = require("config.ArtifactAssetUtil")
        replace(Assets, "drawIcon", noop)
        local Artifact = require("ui.character.hero.ArtifactDetailPanel")
        local item = { id = "keyword-artifact", artifactId = 1, quality = 2, value = 7.5,
            valueRatio = 4321, effectText = "攻击速度提高7.5%，回响伤害提高。" }
        Artifact.setOnEquip(function() actions = actions + 1 end)
        Artifact.show(item, "bag", nil, nil, nil, {hover = true, anchor = {x = 200, y = 1000, w = 100, h = 100}})
        texts = {}
        Artifact.draw(vg)
        kt, h = keywordInstance("攻击速度")
        -- anchor右侧: 左缘312,中心577；顶部603,中心1050，原BG中心(540,1146)。
        local dx, dy = 37, -96
        check(Artifact.handleTap(h.x1 + 1 + dx, h.y1 + 1 + dy) and kt:isOpen(), "神器平移后术语可点击")
        check(Artifact.isPinned(), "打开说明钉住hover详情")
        check(Artifact.handleTap(408 + dx, 1496 + dy) and actions == 0 and not kt:isOpen(), "神器安装按钮只关关键词不派动作")
        local valueColor, ratioColor = false, false
        for _, t in ipairs(texts) do
            if t.text == "7.5%" and t.color[1] == 0xf6 and t.color[2] == 0x85 then valueColor = true end
            if t.text == "（43.2%）" and t.color[1] == 0x99 and t.color[2] == 0x92 then ratioColor = true end
        end
        check(valueColor and ratioColor, "神器主值橙/比例灰不丢")
        Artifact.closeImmediate()
        check(#kt.hotspots == 0 and not kt:isOpen(), "神器关闭清热区")
        Artifact.setOnEquip(nil)
        check(count > 1700, "防空通过：完整58×5语与真实UI场景")
    end)
    for i = #restores, 1, -1 do restores[i]() end
    assert(ok, tostring(err) .. " (" .. count .. " assertions)")
    print("EQUIPMENT KEYWORD: ALL PASS (" .. count .. " assertions)")
    return count
end

function Start()
    local ok, err = pcall(M.run)
    if not ok then print("EQUIPMENT KEYWORD: FAIL " .. tostring(err)); log:Write(LOG_ERROR, tostring(err)) end
    engine:Exit()
end

return M
