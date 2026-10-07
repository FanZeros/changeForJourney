-- 无引擎专项：真实 KeywordText/词典及装备、升阶、洗练、神器公开 UI 接口。
-- Lua 5.4: package.path 加入 scripts/?.lua 后 require("tests.equipment_keyword_test").run()
-- NanoVG、资源图标和只读货币 getter 使用 spy；不执行存档/网络动作。
local M = {}

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
        for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            I18n.set(lang)
            for _, affix in ipairs(affixes) do
                local expected = assert(Locale.getAttribute(affix.key, lang, affix.name))
                check(expected.title == I18n.lookup(affix.name), "完整名称不截为子词 " .. affix.key .. lang)
                check(expected.desc ~= "" and (lang == "zh_CN" or expected.desc ~= AD.getDesc(affix.key)),
                    "完整四语说明不回落简体 " .. affix.key .. lang)
                local kt = Keyword.new()
                local width, font = kt:drawAttribute(nil, affix.name, affix.key, 20, 40, 210, 28)
                check(width <= 210 and font >= 8 and #kt.hotspots == 1, "缩字不越列 " .. affix.key .. lang)
                local h = kt.hotspots[1]
                check(h.key == "attribute:" .. affix.key and h.text == I18n.lookup(affix.name), "稳定key " .. affix.key .. lang)
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
        local texts, color, font = {}, {}, 28
        local images, circles = {}, {}
        local function noop() end
        for _, name in ipairs({ "nvgFontFace", "nvgTextAlign", "nvgTextLetterSpacing", "nvgBeginPath",
            "nvgRoundedRect", "nvgRect", "nvgCircle", "nvgFill", "nvgStroke", "nvgStrokeWidth",
            "nvgStrokeColor", "nvgMoveTo", "nvgLineTo", "nvgClosePath", "nvgSave", "nvgRestore",
            "nvgTranslate", "nvgScale", "nvgGlobalAlpha", "nvgIntersectScissor", "nvgFillPaint" }) do
            replace(_G, name, noop)
        end
        for i, name in ipairs({ "NVG_ALIGN_LEFT", "NVG_ALIGN_TOP", "NVG_ALIGN_MIDDLE",
            "NVG_ALIGN_CENTER", "NVG_ALIGN_RIGHT" }) do replace(_G, name, 2 ^ (i - 1)) end
        replace(_G, "nvgFontSize", function(_, value) font = value end)
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
            texts[#texts + 1] = {text = text, x = x, y = y, color = color, font = font}
        end)
        replace(_G, "time", { elapsedTime = 100 })
        local Draw = require("core.DrawUtil")
        replace(Draw, "drawImageCentered", function(_, image, x, y, w, h, alpha)
            images[#images + 1] = {image = image, x = x, y = y, w = w, h = h, alpha = alpha}
        end)
        replace(Draw, "drawTextStroke", function(vg, x, y, text, size)
            nvgFontSize(vg, size); nvgText(vg, x, y, text)
        end)
        replace(Draw, "drawDoubleChevron", noop)
        local Dark = require("core.DarkIcon")
        replace(Dark, "drawNine", noop)
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
        local valueDrawn, corruptDrawn = false, false
        for _, t in ipairs(texts) do
            if t.text == "7.5" then valueDrawn = true end
            if t.text == "最终运气" and t.color[1] == 0xef and t.color[3] == 0xff then corruptDrawn = true end
        end
        check(valueDrawn and corruptDrawn, "数值与腐化紫色名称保持")

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
