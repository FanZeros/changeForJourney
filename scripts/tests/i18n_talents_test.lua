-- 天赋五语回归：真实209节点/解析器/词典/面板，不注入 package.loaded 替身。
-- 官方 Runtime 独立入口 tests/i18n_talents_test.lua；不加载 main，不读写玩家存档。
local passed, failed = 0, 0
local function check(ok, name)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("[FAIL] " .. name)
    end
end

-- 稳定递归快照覆盖 id、坐标、效果、邻接、图标、颜色；避免只检查显示名。
---@param value any
---@return string
local function fingerprint(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = fingerprint(key) .. "=" .. fingerprint(value[key])
    end
    return "{" .. table.concat(parts, "|") .. "}"
end

---@param source string
---@return string
local function numbers(source)
    local result = {}
    for value in source:gmatch("%d+%.?%d*") do result[#result + 1] = value end
    table.sort(result)
    return table.concat(result, "|")
end

-- 复杂机制可调整语序，但数字多重集必须精确一致，不能广泛忽略或补充次数1。
local function mechanismNumbersPreserved(source, translated)
    return numbers(source) == numbers(translated)
end

local function run()
    local I18n = require("core.I18n")
    local Talents = require("core.I18nTalents")
    local Text = require("core.I18nTalentText")
    local Base = require("core.I18nDict")
    local Extra = require("core.I18nDictExtra")
    local Equipment = require("core.I18nEquipment")
    -- 精确模拟注册优先级：base → extra → talents → equipment；覆盖同名装备/天赋。
    local function registered(source, lang)
        local pack = Equipment[lang]
        return (pack and pack[source]) or Talents[lang][source]
            or Extra[lang][source] or Base[lang][source]
    end
    local Map = require("ui.church.talent.TalentStarMap")
    local Defs = require("shared.talent.TalentNodeDefs")
    local Effect = require("systems.TalentEffect")
    local Panel = require("ui.church.talent.ChurchTalentPanel")
    local snapshots = {}
    local allIds = {}
    local uniqueNames, uniqueEffects = {}, {}
    for id = 0, 208 do
        local node = Map.getNode(id)
        check(node ~= nil and node.id == id, "节点真实存在且ID保持 " .. id)
        snapshots[id] = fingerprint(node)
        allIds[#allIds + 1] = id
        uniqueNames[node.name] = true
        uniqueEffects[node.effect] = true
    end
    local defsBefore = fingerprint(Defs.NODES)
    check(Defs.getNodeCount() == 209 and Map.getNode(209) == nil, "209节点范围")
    local nameCount, effectCount, addedNames = 0, 0, 0
    for name in pairs(uniqueNames) do
        nameCount = nameCount + 1
        if Talents.en[name] then addedNames = addedNames + 1 end
    end
    for _ in pairs(uniqueEffects) do effectCount = effectCount + 1 end
    check(nameCount == 161 and effectCount == 179 and addedNames == 130, "161名179效果补130缺名")

    local aggregateBefore = fingerprint(Effect.buildOverview(allIds))
    local entriesBefore = fingerprint(Effect.collectEntries(allIds, "seal"))
    local combinations = 0
    for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
        check(I18n.set(lang), "可切换语言 " .. lang)
        local missing = 0
        for id = 0, 208 do
            local node = Map.getNode(id)
            local name = I18n.lookup(node.name)
            local effect = I18n.lookup(node.effect)
            local display = Panel.getDetailDisplay(node)
            if lang == "zh_CN" then
                check(name == node.name and effect == node.effect, "中文原名原效果 " .. id)
            else
                local expectedName = registered(node.name, lang)
                local expectedEffect = registered(node.effect, lang) or Text.lookup(node.effect, lang)
                if type(expectedName) ~= "string" or expectedName == ""
                    or type(expectedEffect) ~= "string" or expectedEffect == "" then
                    missing = missing + 1
                end
                check(name == expectedName and effect == expectedEffect, lang .. "真实词典接线 " .. id)
                check(mechanismNumbersPreserved(node.effect, effect), lang .. "效果全部数值保持 " .. id)
                -- 英韩效果不得残留汉字；日文和繁中允许合法汉字原样同形。
                if lang == "en" or lang == "ko" then
                    local hasHan = false
                    for _, code in utf8.codes(effect) do
                        if code >= 0x4E00 and code <= 0x9FFF then hasHan = true; break end
                    end
                    check(not hasHan, lang .. "效果无中文残留 " .. id)
                end
            end
            check(display.name == name and display.effect == effect, lang .. "详情显示边界 " .. id)
            check(fingerprint(node) == snapshots[id], lang .. "节点源数据不变 " .. id)
            combinations = combinations + 1
        end
        check(missing == 0, lang .. "209节点完整覆盖")

        -- 真实业务总览拆段：聚合数值不变，职业标签与裸属性值分别本地化。
        local sourceOverview = Effect.buildOverview(allIds)
        local displayOverview = Panel.buildOverviewDisplay(allIds)
        local cursor = 1
        if #sourceOverview.stats > 0 then
            check(displayOverview[cursor].text == I18n.lookup("属性加成"), lang .. "属性分组标题")
            cursor = cursor + 1
            for _, row in ipairs(sourceOverview.stats) do
                local actual = displayOverview[cursor]
                check(actual.kind == "stat" and actual.label == Text.label(row.label, lang)
                    and actual.value == row.text, lang .. "聚合属性标签与数值 " .. row.label)
                cursor = cursor + 1
            end
        end
        if #sourceOverview.classBonuses > 0 then
            check(displayOverview[cursor].text == I18n.lookup("职业专属"), lang .. "职业分组标题")
            cursor = cursor + 1
            for _, row in ipairs(sourceOverview.classBonuses) do
                local actual = displayOverview[cursor]
                check(actual.label == "[" .. I18n.lookup(row.className) .. "]"
                    and actual.value == Text.stat(row.text, lang), lang .. "职业名与加成分开翻译 " .. row.className)
                cursor = cursor + 1
            end
        end
        if #sourceOverview.specials > 0 then
            check(displayOverview[cursor].text == I18n.lookup("特殊效果"), lang .. "特殊分组标题")
            cursor = cursor + 1
            for _, row in ipairs(sourceOverview.specials) do
                local expected = I18n.format("· %s：%s", I18n.lookup(row.name), I18n.lookup(row.text))
                check(displayOverview[cursor].text == expected, lang .. "独立机制片段本地化 " .. row.name)
                if lang == "en" or lang == "ko" then
                    check(I18n.lookup(row.text) ~= row.text, lang .. "所有机制片段有译文 " .. row.name)
                end
                cursor = cursor + 1
            end
        end
        check(cursor - 1 == #displayOverview, lang .. "总览不增删业务条目")
        local empty = Panel.buildOverviewDisplay({ 0 })
        check(#empty == 1 and empty[1].muted and empty[1].text == I18n.lookup("暂无已点亮天赋效果"), lang .. "空总览")
        check(fingerprint(Effect.buildOverview(allIds)) == aggregateBefore
            and fingerprint(Effect.collectEntries(allIds, "seal")) == entriesBefore,
            lang .. "属性解析与业务总览不受语言影响")
    end
    check(combinations == 1045, "五语209节点共1045组合")

    -- 严格模板：只有1..4完整原子，单位匹配，不吞尾巴、不把复杂机制部分翻译。
    local valid = {
        "全体敏捷+01", "全体攻击速度+04.00%", "全体护甲加成+9.3%，生命加成-3.3%",
        "全体魔法攻击力+6 全体秘识+2", "全体秘识+1 魂火+1",
        "全体力量+1，敏捷+2，体质+3，秘识+4",
    }
    local invalid = {
        "", "敏捷+1", "全体", "全体敏捷+1奖励", "全体未知+1", "全体敏捷+1，未知+2",
        "全体敏捷+1，", "全体敏捷+1 ", " 全体敏捷+1", "全体敏捷+1  力量+2",
        "全体敏捷+1,力量+2", "全体敏捷+1， 力量+2", "全体敏捷+1\n",
        "全体敏捷+1\t力量+2", "全体敏捷+1；生命低于30%时回血", "全体全体敏捷+1",
        "全体力量+1，敏捷+2，体质+3，秘识+4，命数+5", "全体敏捷+1e2", "全体敏捷+1.",
        "全体敏捷+.5", "全体敏捷++1", "全体敏捷+%d", "全体敏捷+{0}", "全体敏捷+1%",
        "全体暴击率+5", "全体攻击速度+1", "全体魔法暴击率+4%后额外攻击", "全体智慧+2",
        "image/全体敏捷+1.png", "全体敏捷+1/Textures/test.png",
    }
    for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
        I18n.set(lang)
        for _, source in ipairs(valid) do
            local translated = Text.lookup(source, lang)
            check(type(translated) == "string" and numbers(translated or "") == numbers(source), lang .. "合法严格模板 " .. source)
        end
        for _, source in ipairs(invalid) do
            check(Text.lookup(source, lang) == nil, lang .. "严格拒绝 " .. source)
            if lang ~= "zh_CN" then
                local expected = registered(source, lang) or source
                check(I18n.lookup(source) == expected, lang .. "只允许已登记原文例外 " .. source)
            end
        end
        local padded = Text.lookup("全体敏捷+01", lang) or ""
        local precise = Text.lookup("全体攻击速度+04.00%", lang) or ""
        check(padded:find("+01", 1, true) ~= nil, lang .. "保留前导零")
        check(precise:find("+04.00%", 1, true) ~= nil, lang .. "保留精度")
        for _, id in ipairs({ 0, 105, 106, 108, 109, 111, 112, 113, 115, 117, 120, 124, 125, 126, 127, 128, 201, 202, 203, 204, 205, 206, 207, 208 }) do
            check(Text.lookup(Map.getNode(id).effect, lang) == nil, lang .. "复杂机制只走精确条目 " .. id)
        end
    end
    check(Text.lookup("全体敏捷+1", "unknown") == nil and Text.stat("敏捷+1", "unknown") == nil
        and Text.label("敏捷", "unknown") == nil, "未知语言不翻译")
    local nonString = 2
    ---@cast nonString any
    check(Text.lookup(nil, "en") == nil and Text.lookup(nonString, "en") == nil
        and Text.stat(nil, "en") == nil and Text.label(nil, "en") == nil, "非字符串安全返回")
    check(Text.stat("暴击伤害+10%后回血", "en") == nil, "stat拒额外文字")
    check(Text.lookup("全体" .. string.rep("敏捷+1，", 100), "en") == nil, "超长输入安全拒绝")
    check(Text.lookup("All allies: AGI+1", "en") == nil, "不二次翻译目标文本")

    -- 表形状与占位符四语同步，所有新增条目的数值与源文字逐项一致。
    local dictCount = 0
    for source in pairs(Talents.en) do
        dictCount = dictCount + 1
        for _, lang in ipairs({ "zh_TW", "en", "ja", "ko" }) do
            local translated = Talents[lang][source]
            check(type(translated) == "string" and translated ~= "", lang .. "新词典四语同键 " .. source)
            check(mechanismNumbersPreserved(source, translated), lang .. "新词典数值完整 " .. source)
        end
    end
    for _, lang in ipairs({ "zh_TW", "en", "ja", "ko" }) do
        local count = 0
        for source in pairs(Talents[lang]) do count = count + 1; check(Talents.en[source] ~= nil, lang .. "没有额外漂移键") end
        check(count == dictCount, lang .. "四语条目数相同")
        local placeholders = 0
        for _ in Talents[lang]["· %s：%s"]:gmatch("%%s") do placeholders = placeholders + 1 end
        check(placeholders == 2, lang .. "模板2个占位符保留")
    end
    -- 官方NanoVG真实字体度量，不用等宽stub；不绘制像素也可检查固定详情框。
    local vg = nvgCreate(1)
    local fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    check(fontId >= 0, "真实sans字体加载")
    local minFont = 35
    for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
        I18n.set(lang)
        for id = 0, 208 do
            local display = Panel.getDetailDisplay(Map.getNode(id))
            local fitted = Panel.fitDetailFont(vg, display.effect, 660, 242)
            minFont = math.min(minFont, fitted)
            nvgFontSize(vg, fitted)
            local bounds = nvgTextBoxBounds(vg, 0, 0, 660, display.effect, nil)
            local measured = bounds and bounds[4] - bounds[2] or 0
            check(fitted >= 22 and fitted <= 35 and measured > 0 and measured <= 242,
                lang .. "真实详情描述不溢出 " .. id)
        end
    end
    print(string.format("[i18n_talents_test] minimum_detail_font=%d", minFont))
    -- 一次性触发语义单独核验；不靠数字多重集接受模糊的英文 once 替换。
    local fatalSource = Map.getNode(125).effect
    check(Talents.en[fatalSource]:find("1 trigger per expeditioner per battle", 1, true) ~= nil,
        "125英文每位每场最多1次")
    check(Talents.ja[fatalSource]:find("各隊員につき戦闘ごとに最大1回", 1, true) ~= nil,
        "125日文每位每场最多1次")
    check(Talents.ko[fatalSource]:find("원정대원마다 전투당 최대 1회", 1, true) ~= nil,
        "125韩文每位每场最多1次")
    local ember = "触发：生命低于30%时，每场战斗回复12%最大生命"
    check(Talents.en[ember]:find("once per battle", 1, true) ~= nil
        and Talents.ja[ember]:find("戦闘ごとに一度", 1, true) ~= nil
        and Talents.ko[ember]:find("전투마다 한 번", 1, true) ~= nil, "201各语单次语义明确")
    nvgDelete(vg)

    I18n.set("en")
    check(I18n.format("· %s：%s", "50% {0}", "20% %s") == "· 50% {0}: 20% %s", "占位符和百分号参数不二次替换")
    check(fingerprint(Defs.NODES) == defsBefore, "TalentNodeDefs全量源数据不变")
    for id = 0, 208 do check(fingerprint(Map.getNode(id)) == snapshots[id], "结束源节点不变 " .. id) end
    I18n.set("zh_CN")
    print(string.format("[i18n_talents_test] nodes=209 names=%d effects=%d new_entries=%d combinations=%d passed=%d failed=%d",
        nameCount, effectCount, dictCount, combinations, passed, failed))
    assert(failed == 0, "天赋回归失败数=" .. failed)
    print("I18N TALENTS: ALL PASS")
end

function Start()
    local ok, err = pcall(run)
    if not ok then log:Write(LOG_ERROR, "[i18n_talents_test] " .. tostring(err)) end
    engine:Exit()
end
