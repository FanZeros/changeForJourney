-- 天赋纯属性显示模板。无 I18n / AttributeDef / 引擎依赖，不修改业务数据。
-- lookup 只接受「全体」开头、1..4 个完整白名单属性原子；复杂机制交给完整词典。
-- stat 仅供天赋总览的职业加成值（单个无前缀属性原子），不注册到全局 lookup。
local M = {}

-- 源属性、繁中、英文、日文、韩文、单位。比例属性必须带 %，平值必须不带 %。
---@type string[][]
local ROWS = {
    { "力量", "力量", "STR", "力", "힘", "" },
    { "敏捷", "敏捷", "AGI", "敏捷", "민첩", "" },
    { "体质", "體質", "VIT", "体力", "체질", "" },
    { "秘识", "秘識", "INT", "知力", "지력", "" },
    { "命数", "命數", "LUK", "運", "운", "" },
    { "魂火", "魂火", "Spirit", "魂火", "혼화", "" },
    { "生命值", "生命值", "HP", "HP", "체력", "" },
    { "生命加成", "生命加成", "HP Bonus", "HP補正", "생명력 보너스", "%" },
    { "护甲", "護甲", "Armor", "防御", "방어력", "" },
    { "护甲加成", "護甲加成", "Armor Bonus", "防御補正", "방어력 보너스", "%" },
    { "护盾", "護盾", "Shield", "シールド", "보호막", "" },
    { "护盾加成", "護盾加成", "Shield Bonus", "シールド補正", "보호막 보너스", "%" },
    { "护盾减伤", "護盾減傷", "Shield DMG Reduction", "シールド被ダメージ軽減", "보호막 피해 감소", "%" },
    { "闪避值", "閃避值", "Dodge", "回避値", "회피 수치", "" },
    { "闪避加成", "閃避加成", "Dodge Bonus", "回避補正", "회피 보너스", "%" },
    { "怨引值", "怨引值", "Threat", "ヘイト値", "어그로 수치", "%" },
    { "每秒回血", "每秒回血", "HP Regen/s", "毎秒HP回復", "초당 생명력 회복", "" },
    { "攻击速度", "攻擊速度", "Attack Speed", "攻撃速度", "공격 속도", "%" },
    { "暴击率", "暴擊率", "Crit Rate", "会心率", "치명타율", "%" },
    { "暴击伤害", "暴擊傷害", "Crit DMG", "会心ダメージ", "치명 피해", "%" },
    { "伤害加成", "傷害加成", "DMG Bonus", "ダメージ補正", "피해 보너스", "%" },
    { "物理攻击力", "物理攻擊力", "ATK", "物理攻撃力", "물리 공격력", "" },
    { "魔法攻击力", "魔法攻擊力", "MATK", "魔法攻撃力", "마법 공격력", "" },
    { "物理攻击加成", "物理攻擊加成", "ATK Bonus", "物理攻撃補正", "물리 공격 보너스", "%" },
    { "魔法攻击加成", "魔法攻擊加成", "MATK Bonus", "魔法攻撃補正", "마법 공격 보너스", "%" },
    { "物理伤害加成", "物理傷害加成", "Physical DMG Bonus", "物理ダメージ補正", "물리 피해 보너스", "%" },
    { "魔法伤害加成", "魔法傷害加成", "Magic DMG Bonus", "魔法ダメージ補正", "마법 피해 보너스", "%" },
    { "物理暴击率", "物理暴擊率", "Physical Crit Rate", "物理会心率", "물리 치명타율", "%" },
    { "魔法暴击率", "魔法暴擊率", "Magic Crit Rate", "魔法会心率", "마법 치명타율", "%" },
    { "物理暴击伤害", "物理暴擊傷害", "Physical Crit DMG", "物理会心ダメージ", "물리 치명 피해", "%" },
    { "魔法暴击伤害", "魔法暴擊傷害", "Magic Crit DMG", "魔法会心ダメージ", "마법 치명 피해", "%" },
    { "物理穿透", "物理穿透", "Physical Penetration", "物理貫通", "물리 관통", "" },
    { "魔法穿透", "魔法穿透", "Magic Penetration", "魔法貫通", "마법 관통", "" },
    { "物理格挡概率", "物理格擋機率", "Physical Block Chance", "物理ガード率", "물리 막기 확률", "%" },
    { "魔法格挡概率", "魔法格擋機率", "Magic Block Chance", "魔法ガード率", "마법 막기 확률", "%" },
    { "命中值", "命中值", "Accuracy", "命中値", "명중 수치", "" },
    { "连击概率", "連擊機率", "Combo Chance", "連撃率", "연격 확률", "%" },
    { "连击增伤", "連擊增傷", "Combo DMG Bonus", "連撃ダメージ補正", "연격 피해 보너스", "%" },
    { "治疗量", "治療量", "Healing", "回復量", "치유량", "" },
    { "治疗加成", "治療加成", "Healing Bonus", "回復量補正", "치유 보너스", "%" },
    { "治疗暴击率", "治療暴擊率", "Healing Crit Rate", "回復会心率", "치유 치명타율", "%" },
    { "暴击治疗", "暴擊治療", "Critical Healing", "会心回復量", "치명타 치유", "%" },
}

---@type table<string, string[]>
local attributes = {}
for _, row in ipairs(ROWS) do attributes[row[1]] = row end
-- 兼容已有天赋原文和关键词标识，不改业务 key。
attributes["护盾伤害减免"] = attributes["护盾减伤"]
attributes["治疗暴击加成"] = attributes["暴击治疗"]

---@type table<string, integer>
local COLUMNS = { zh_CN = 1, zh_TW = 2, en = 3, ja = 4, ko = 5 }
---@type table<string, string>
local PREFIXES = { zh_CN = "全体", zh_TW = "全體", en = "All allies: ", ja = "全員：", ko = "아군 전체: " }
---@type table<string, string>
local GAPS = { zh_CN = "，", zh_TW = "，", en = ", ", ja = "、", ko = ", " }

---@param atom string
---@param column integer
---@return string|nil
local function translateAtom(atom, column)
    -- 数值只按严格十进制字面量匹配，不 tonumber，不归一化前导零、正负号、小数精度。
    local name, value, unit = atom:match("^(.-)([+-]%d+%.%d+)(%%?)$")
    if not name then name, value, unit = atom:match("^(.-)([+-]%d+)(%%?)$") end
    local row = name and attributes[name]
    if not row or unit ~= row[6] then return nil end
    return row[column] .. value .. unit
end

--- 总览属性标签；不注册全局，避免「护甲」与装备部位共用语义。
---@param source string
---@param lang string
---@return string|nil
function M.label(source, lang)
    if type(source) ~= "string" or type(lang) ~= "string" then return nil end
    local column = COLUMNS[lang]
    local row = attributes[source]
    if not column or not row then return nil end
    return row[column]
end

--- 总览职业加成的单一原子，例「怨引值+15%」。
---@param source string
---@param lang string
---@return string|nil
function M.stat(source, lang)
    if type(source) ~= "string" or type(lang) ~= "string" then return nil end
    local column = COLUMNS[lang]
    if not column then return nil end
    return translateAtom(source, column)
end

--- 全局仅登记受限的完整「全体」属性结构。未知输入完整返回 nil，绝不部分翻译。
---@param text string
---@param lang string
---@return string|nil
function M.lookup(text, lang)
    if type(text) ~= "string" or type(lang) ~= "string" then return nil end
    local column = COLUMNS[lang]
    if not column or #text > 512 or text:sub(1, #"全体") ~= "全体" then return nil end
    local body = text:sub(#"全体" + 1)
    local atoms = {}
    local pos = 1
    while pos <= #body do
        -- 用 plain find 分割 UTF-8 标点，不用 [，] 等多字节字符类。
        local commaStart, commaEnd = body:find("，", pos, true)
        local spaceStart, spaceEnd = body:find(" ", pos, true)
        local first, last = commaStart, commaEnd
        if spaceStart and (not first or spaceStart < first) then first, last = spaceStart, spaceEnd end
        local atom = first and body:sub(pos, first - 1) or body:sub(pos)
        -- 源码中「全体魔法攻击力+6 全体秘识+2」的重复前缀只在后续原子合法。
        if #atoms > 0 and atom:sub(1, #"全体") == "全体" then atom = atom:sub(#"全体" + 1) end
        local translated = translateAtom(atom, column)
        if not translated or #atoms >= 4 then return nil end
        atoms[#atoms + 1] = translated
        if not first then break end
        if last >= #body then return nil end
        pos = last + 1
    end
    if #atoms == 0 then return nil end
    if lang == "zh_CN" then return text end
    return PREFIXES[lang] .. table.concat(atoms, GAPS[lang])
end

return M
