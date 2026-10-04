-- 关卡显示文本的独立翻译器：只处理完整已知词或严格格式，不替换业务原文。
-- 无 SC / I18n / 引擎依赖；未知语言、资源路径、参数模板、任意附加文字返回 nil。
-- 接线时先查现有字典，再调用 lookup；难度控件可直接调用 difficulty。
-- 特别约束：lookup("普通", lang) 不接管品质词 Common；difficulty 使用 Normal。
local M = {}

-- 行格式固定为：业务简中原名、繁中、英文、日文、韩文。
---@type string[][]
local REGION_ROWS = {
    { "黑棘林道", "黑棘林道", "Blackthorn Trail", "黒棘の林道", "검은가시 숲길" },
    { "幽烬林地", "幽燼林地", "Gloomember Woods", "幽燼の森", "그늘진 잔화 숲" },
    { "哑雾沼泽", "啞霧沼澤", "Silentmist Marsh", "沈黙の霧沼", "침묵의 안개 늪" },
    { "巨木之冢", "巨木之塚", "Great Tree Barrow", "巨木の塚", "거목의 무덤" },
    { "哀嚎沙丘", "哀嚎沙丘", "Wailing Dunes", "慟哭の砂丘", "통곡의 사구" },
    { "蚀骨荒漠", "蝕骨荒漠", "Bone-Eroding Desert", "骨を蝕む荒漠", "뼈를 부식시키는 사막" },
    { "焦土平原", "焦土平原", "Scorched Plains", "焦土の平原", "초토의 평원" },
    { "断魂裂谷", "斷魂裂谷", "Soul-Sundering Rift", "魂断ちの裂谷", "혼을 가르는 협곡" },
    { "蛊语山洞", "蠱語山洞", "Hexwhisper Cave", "呪いの囁きの洞窟", "저주의 속삭임 동굴" },
    { "悬魂瀑布", "懸魂瀑布", "Falls of Suspended Souls", "宙吊りの魂の滝", "매달린 영혼의 폭포" },
    { "霜噬雪岭", "霜噬雪嶺", "Frostbitten Snow Ridge", "霜に蝕まれた雪嶺", "서리에 잠식된 설령" },
    { "沉眠冰原", "沉眠冰原", "Slumbering Icefield", "眠れる氷原", "잠든 빙원" },
    { "血晶溶洞", "血晶溶洞", "Bloodcrystal Cavern", "血晶の鍾乳洞", "혈정의 석회동굴" },
    { "枯枫遗迹", "枯楓遺跡", "Withered Maple Ruins", "枯れ楓の遺跡", "마른 단풍나무 유적" },
    { "烬暮湖畔", "燼暮湖畔", "Emberdusk Lakeshore", "残り火の黄昏湖畔", "잿불 황혼의 호숫가" },
    { "废弃营地", "廢棄營地", "Abandoned Camp", "廃棄された野営地", "버려진 야영지" },
    { "古代遗迹", "古代遺跡", "Ancient Ruins", "古代遺跡", "고대 유적" },
    { "沉没神殿", "沉沒神殿", "Sunken Temple", "沈んだ神殿", "가라앉은 신전" },
    { "哭泣峭壁", "哭泣峭壁", "Weeping Cliffs", "涙の断崖", "흐느끼는 절벽" },
    { "恶灵岔路", "惡靈岔路", "Evil-Spirit Crossroads", "悪霊の分かれ道", "악령의 갈림길" },
    { "遗忘墓穴", "遺忘墓穴", "Forgotten Crypt", "忘れられた墓穴", "잊힌 묘굴" },
    { "亡灵墓穴", "亡靈墓穴", "Undead Crypt", "亡霊の墓穴", "망령의 묘굴" },
    { "烛龙之巢", "燭龍之巢", "Zhulong's Nest", "燭龍の巣", "촉룡의 둥지" },
}

---@type string[][]
local DIFFICULTY_ROWS = {
    { "普通", "普通", "Normal", "ノーマル", "일반" },
    { "困难", "困難", "Hard", "ハード", "어려움" },
    { "噩梦", "噩夢", "Nightmare", "ナイトメア", "악몽" },
    { "地狱", "地獄", "Hell", "ヘル", "지옥" },
    { "炼狱", "煉獄", "Purgatory", "煉獄", "연옥" },
    { "折磨", "折磨", "Torment", "責苦", "고통" },
    { "湮灭", "湮滅", "Annihilation", "殲滅", "소멸" },
}

-- 终焉及终焉神殿沿用当前 I18nDict / I18n 中的既有译法。
---@type table<string, string[]>
local TERMINALS = {
    ["终焉"] = { "终焉", "終焉", "Finality", "終焉", "종언" },
    ["终焉神殿"] = { "终焉神殿", "終焉神殿", "Final Temple", "終焉神殿", "종언 신전" },
}

-- 仅导出审计用原文数组；内部映射独立，不依赖调用方对导出表的修改。
---@type string[]
M.REGIONS = {}
---@type string[]
M.DIFFICULTIES = {
    "普通", "困难", "噩梦", "地狱", "炼狱", "折磨",
    "折磨II", "折磨III", "折磨IV", "折磨V", "湮灭",
    "湮灭II", "湮灭III", "湮灭IV", "湮灭V",
}
---@type table<string, string[]>
local regions = {}
---@type table<string, string[]>
local difficulties = {}
for _, row in ipairs(REGION_ROWS) do
    regions[row[1]] = row
    M.REGIONS[#M.REGIONS + 1] = row[1]
end
for _, row in ipairs(DIFFICULTY_ROWS) do
    difficulties[row[1]] = row
end

---@type table<string, integer>
local COLUMNS = { zh_CN = 1, zh_TW = 2, en = 3, ja = 4, ko = 5 }
---@type table<string, boolean>
local ROMAN_SUFFIXES = { II = true, III = true, IV = true, V = true }
---@type table<string, string>
local SEPARATORS = { zh_CN = "·", zh_TW = "·", en = " · ", ja = "・", ko = " · " }
---@type table<string, string>
local NUMBER_GAPS = { zh_CN = "", zh_TW = "", en = " ", ja = " ", ko = " " }

-- 难度专用入口，严格限定七个基础难度及折磨 / 湮灭 II..V。
---@param text string
---@param lang string
---@return string|nil
function M.difficulty(text, lang)
    if type(text) ~= "string" or type(lang) ~= "string" then return nil end
    local column = COLUMNS[lang]
    if not column then return nil end
    local row = difficulties[text]
    if row then return row[column] end
    local base, suffix = text:match("^(.-)([IV]+)$")
    if (base ~= "折磨" and base ~= "湮灭") or not ROMAN_SUFFIXES[suffix] then
        return nil
    end
    local baseRow = difficulties[base]
    if lang == "zh_CN" then return text end
    local gap = (lang == "zh_TW") and "" or " "
    return baseRow[column] .. gap .. suffix
end

-- 数字始终以源字符串保留，包括前导零；不做 tonumber 或关卡编号重算。
---@param text string
---@param lang string
---@return string|nil
function M.lookup(text, lang)
    if type(text) ~= "string" or type(lang) ~= "string" then return nil end
    local column = COLUMNS[lang]
    if not column or text == "" then return nil end
    local row = regions[text] or TERMINALS[text]
    if row then return row[column] end

    -- 「普通」歧义交还既有词典，其他完整难度词可以安全匹配。
    if text == "普通" then return nil end
    local diff = M.difficulty(text, lang)
    if diff then return diff end

    -- 特殊关只允许「终焉神殿·完整难度」，不接管其他带终焉的名字。
    local terminalDiff = text:match("^终焉神殿·(.+)$")
    if terminalDiff then
        local translatedDiff = M.difficulty(terminalDiff, lang)
        if not translatedDiff then return nil end
        if lang == "zh_CN" then return text end
        return TERMINALS["终焉神殿"][column] .. SEPARATORS[lang] .. translatedDiff
    end

    -- 章节只接收「第N章」或「N 章」，不接受参数模板或额外空白。
    local chapter = text:match("^第(%d+)章$") or text:match("^(%d+) 章$")
    if chapter then
        if lang == "zh_CN" or lang == "zh_TW" then return text end
        if lang == "en" then return "Chapter " .. chapter end
        if lang == "ja" then return "第" .. chapter .. "章" end
        return chapter .. "장"
    end

    -- 普通关「地名N-M」；高难度关「完整难度·地名N-M」。
    -- 先拆整个结构，再核对词表，绝不进行全局子串替换。
    local prefix, body = text:match("^(.-)·(.-)$")
    local stageBody = body or text
    local region, numbers = stageBody:match("^(.-)(%d+%-%d+)$")
    if region and numbers then
        local regionRow = regions[region]
        if regionRow then
            if prefix then
                local translatedDiff = M.difficulty(prefix, lang)
                if not translatedDiff then return nil end
                if lang == "zh_CN" then return text end
                return translatedDiff .. SEPARATORS[lang] .. regionRow[column]
                    .. NUMBER_GAPS[lang] .. numbers
            end
            if lang == "zh_CN" then return text end
            return regionRow[column] .. NUMBER_GAPS[lang] .. numbers
        end
    end
    if prefix then return nil end

    -- 难度进度「完整难度N-M」独立处理，普通在此明确为 Normal。
    local progressDiff, progress = text:match("^(.-) ?(%d+%-%d+)$")
    if progressDiff and progress then
        local translatedDiff = M.difficulty(progressDiff, lang)
        if translatedDiff then
            if lang == "zh_CN" then return text end
            return translatedDiff .. NUMBER_GAPS[lang] .. progress
        end
    end
    return nil
end

return M
