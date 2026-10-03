-- ============================================================================
-- I18n - 运行时五语（简/繁/英/日/韩）
-- 覆盖标题、设置、顶栏、城镇页、装备 HUD。语言写入 settings_volume.json。
-- 不要开引擎 .project/i18n.json enabled=true（会扫进梗名）。
-- ============================================================================

local I18n = {}
local StageText = require("core.I18nStages")
local TalentText = require("core.I18nTalentText")
local EquipmentText = require("core.I18nEquipmentText")
local StoryText = require("core.I18nStory")

I18n.LANGS = {
    { id = "zh_CN", label = "简体" },
    { id = "zh_TW", label = "繁體" },
    { id = "en",    label = "EN" },
    { id = "ja",    label = "日本語" },
    { id = "ko",    label = "한국어" },
}

I18n.DISPLAY = {
    zh_CN = "简体中文",
    zh_TW = "繁體中文",
    en    = "English",
    ja    = "日本語",
    ko    = "한국어",
}

local current_ = "zh_CN"
local dict_ = nil ---@type table|nil
local hooked_ = false
local rawNvgText_ = nil
local rawNvgTextBox_ = nil
local rawNvgTextBounds_ = nil
local rawNvgTextBoxBounds_ = nil
local lookupCache_ = {} ---@type table<string, table<string, string>>
local LOOKUP_CACHE_LIMIT = 512
local lookupCacheSizes_ = {} ---@type table<string, number>

local function mergeLang(dst, src)
    if type(src) ~= "table" then return end
    for lang, pack in pairs(src) do
        if type(pack) == "table" then
            dst[lang] = dst[lang] or {}
            for k, v in pairs(pack) do
                dst[lang][k] = v
            end
        end
    end
end

local function dict()
    if dict_ then return dict_ end
    dict_ = { zh_TW = {}, en = {}, ja = {}, ko = {} }
    local ok, d = pcall(require, "core.I18nDict")
    if ok and type(d) == "table" then
        mergeLang(dict_, d)
    else
        print("[I18n] 基础词典加载失败: " .. tostring(d))
    end
    local ok2, extra = pcall(require, "core.I18nDictExtra")
    if ok2 and type(extra) == "table" then
        mergeLang(dict_, extra)
    else
        print("[I18n] 扩展词典加载失败: " .. tostring(extra))
    end
    local ok3, talents = pcall(require, "core.I18nTalents")
    if ok3 and type(talents) == "table" then
        mergeLang(dict_, talents)
    else
        print("[I18n] 天赋词典加载失败: " .. tostring(talents))
    end
    local ok4, equipment = pcall(require, "core.I18nEquipment")
    if ok4 and type(equipment) == "table" then
        mergeLang(dict_, equipment)
    else
        print("[I18n] 装备词典加载失败: " .. tostring(equipment))
    end
    local ok5, keywords = pcall(require, "core.I18nKeywords")
    if ok5 and type(keywords) == "table" then
        mergeLang(dict_, keywords)
    else
        print("[I18n] 关键词词典加载失败: " .. tostring(keywords))
    end
    return dict_
end

--- 按完整原文或已登记的关卡模板翻译；不修改业务数据，不猜测任意子串。
---@param text any
---@return any
function I18n.lookup(text)
    if current_ == "zh_CN" then return text end
    if type(text) ~= "string" or text == "" then return text end
    local cache = lookupCache_[current_]
    if cache and cache[text] ~= nil then return cache[text] end
    local pack = dict()[current_]
    local hit = pack and pack[text]
    -- 韩文序数前缀「第」的空串是既有排版规则，其余空译文回退原文。
    if type(hit) ~= "string" or (hit == "" and not (current_ == "ko" and text == "第")) then
        hit = StoryText.lookup(text, current_) or StageText.lookup(text, current_)
            or TalentText.lookup(text, current_) or EquipmentText.lookup(text, current_) or text
    end
    if not cache or (lookupCacheSizes_[current_] or 0) >= LOOKUP_CACHE_LIMIT then
        cache = {}
        lookupCache_[current_] = cache
        lookupCacheSizes_[current_] = 0
    end
    cache[text] = hit
    lookupCacheSizes_[current_] = (lookupCacheSizes_[current_] or 0) + 1
    return hit
end

--- printf 模板先翻译再格式化；字符串参数由显示调用方明确本地化。
---@param source string
---@param ... any
---@return string
function I18n.format(source, ...)
    return string.format(I18n.lookup(source), ...)
end

--- 关卡难度专用入口，避免「普通」与装备品质 Common 共用译法。
---@param source string
---@return string
function I18n.difficulty(source)
    return StageText.difficulty(source, current_) or source
end

local T = {
    zh_CN = {
        tap_continue      = "轻 触 屏 幕 继 续",
        loading_res       = "资源加载中",
        expedition_lv     = "远征等级 LV.{0}",
        settings          = "设置",
        bgm               = "背景音乐",
        sfx               = "音效",
        damage_numbers    = "伤害显示",
        show_effects      = "特效显示",
        redeem_code       = "兑换码",
        language          = "语言",
        on                = "开",
        off               = "关",
        tab_battle        = "战斗",
        tab_dungeon       = "副本",
        lang_changed      = "语言已切换",
        bag               = "尘封仓库",
        blacksmith        = "狱火锻炉",
        tavern            = "腐鸦酒馆",
        church            = "缄默礼拜堂",
        market            = "月蚀黑市",
        ancient_tree      = "终焉古树",
        unequip_all       = "一键卸下",
        equip_all         = "一键装备",
        hero_detail       = "角色详情",
        quality           = "品质",
        class_label       = "职业",
        tab_attr          = "属性",
        tab_equip         = "配装",
        tab_class         = "转职",
        tab_awaken        = "觉醒",
        wear              = "穿戴",
        unequip           = "卸下",
        replace           = "更换",
        filter_all        = "所有",
        filter_weapon     = "主手",
        filter_offhand    = "副手",
        filter_armor      = "护甲",
        filter_helmet     = "头盔",
        filter_shoes      = "鞋子",
        filter_accessory  = "饰品",
        slot_weapon       = "主武器",
        slot_offhand      = "副武器",
        slot_armor        = "护甲",
        slot_helmet       = "头盔",
        slot_shoes        = "鞋子",
        slot_accessory    = "饰品",
        slot_all          = "全部装备",
        cannot_wear       = "无法穿戴",
        level_not_enough_equip = "角色等级不足，需达到 Lv.{0} 才能装备",
        equipped          = "已装备",
        unequipped        = "已卸下",
        equipped_ok       = "已装备",
    },
    zh_TW = {
        tap_continue      = "輕 觸 螢 幕 繼 續",
        loading_res       = "資源載入中",
        expedition_lv     = "遠征等級 LV.{0}",
        settings          = "設定",
        bgm               = "背景音樂",
        sfx               = "音效",
        damage_numbers    = "傷害顯示",
        show_effects      = "特效顯示",
        redeem_code       = "兌換碼",
        language          = "語言",
        on                = "開",
        off               = "關",
        tab_battle        = "戰鬥",
        tab_dungeon       = "副本",
        lang_changed      = "語言已切換",
        bag               = "塵封倉庫",
        blacksmith        = "獄火鍛爐",
        tavern            = "腐鴉酒館",
        church            = "緘默禮拜堂",
        market            = "月蝕黑市",
        ancient_tree      = "終焉古樹",
        unequip_all       = "一鍵卸下",
        equip_all         = "一鍵裝備",
        hero_detail       = "角色詳情",
        quality           = "品質",
        class_label       = "職業",
        tab_attr          = "屬性",
        tab_equip         = "配裝",
        tab_class         = "轉職",
        tab_awaken        = "覺醒",
        wear              = "穿戴",
        unequip           = "卸下",
        replace           = "更換",
        filter_all        = "所有",
        filter_weapon     = "主手",
        filter_offhand    = "副手",
        filter_armor      = "護甲",
        filter_helmet     = "頭盔",
        filter_shoes      = "鞋子",
        filter_accessory  = "飾品",
        slot_weapon       = "主武器",
        slot_offhand      = "副武器",
        slot_armor        = "護甲",
        slot_helmet       = "頭盔",
        slot_shoes        = "鞋子",
        slot_accessory    = "飾品",
        slot_all          = "全部裝備",
        cannot_wear       = "無法穿戴",
        level_not_enough_equip = "角色等級不足，需達到 Lv.{0} 才能裝備",
        equipped          = "已裝備",
        unequipped        = "已卸下",
        equipped_ok       = "已裝備",
    },
    en = {
        tap_continue      = "TAP TO CONTINUE",
        loading_res       = "Loading assets",
        expedition_lv     = "Expedition Lv.{0}",
        settings          = "Settings",
        bgm               = "Music",
        sfx               = "Sound FX",
        damage_numbers    = "Damage Numbers",
        show_effects      = "VFX",
        redeem_code       = "Redeem Code",
        language          = "Language",
        on                = "ON",
        off               = "OFF",
        tab_battle        = "Battle",
        tab_dungeon       = "Dungeon",
        lang_changed      = "Language changed",
        bag               = "Sealed Vault",
        blacksmith        = "Hellforge",
        tavern            = "Rotcrow Inn",
        church            = "Silent Chapel",
        market            = "Eclipse Market",
        ancient_tree      = "Doom Tree",
        unequip_all       = "Unequip All",
        equip_all         = "Equip Best",
        hero_detail       = "Hero Details",
        quality           = "Rarity",
        class_label       = "Class",
        tab_attr          = "Stats",
        tab_equip         = "Gear",
        tab_class         = "Class",
        tab_awaken        = "Awaken",
        wear              = "Equip",
        unequip           = "Unequip",
        replace           = "Swap",
        filter_all        = "All",
        filter_weapon     = "Main",
        filter_offhand    = "Off",
        filter_armor      = "Armor",
        filter_helmet     = "Helm",
        filter_shoes      = "Boots",
        filter_accessory  = "Acc.",
        slot_weapon       = "Main Hand",
        slot_offhand      = "Off Hand",
        slot_armor        = "Armor",
        slot_helmet       = "Helmet",
        slot_shoes        = "Boots",
        slot_accessory    = "Accessory",
        slot_all          = "All Gear",
        cannot_wear       = "Can't equip",
        level_not_enough_equip = "Level too low. Reach Lv.{0} to equip",
        equipped          = "Equipped",
        unequipped        = "Unequipped",
        equipped_ok       = "Equipped",
    },
    ja = {
        tap_continue      = "タップして続ける",
        loading_res       = "読み込み中",
        expedition_lv     = "遠征レベル LV.{0}",
        settings          = "設定",
        bgm               = "BGM",
        sfx               = "効果音",
        damage_numbers    = "ダメージ表示",
        show_effects      = "エフェクト",
        redeem_code       = "シリアルコード",
        language          = "言語",
        on                = "オン",
        off               = "オフ",
        tab_battle        = "戦闘",
        tab_dungeon       = "ダンジョン",
        lang_changed      = "言語を切り替えました",
        bag               = "塵封倉庫",
        blacksmith        = "獄火鍛炉",
        tavern            = "腐鴉酒場",
        church            = "沈黙礼拝堂",
        market            = "月蝕黒市",
        ancient_tree      = "終焉古樹",
        unequip_all       = "一括解除",
        equip_all         = "一括装備",
        hero_detail       = "キャラ詳細",
        quality           = "レア度",
        class_label       = "クラス",
        tab_attr          = "ステータス",
        tab_equip         = "装備",
        tab_class         = "転職",
        tab_awaken        = "覚醒",
        wear              = "装備",
        unequip           = "外す",
        replace           = "付け替え",
        filter_all        = "全て",
        filter_weapon     = "メイン",
        filter_offhand    = "サブ",
        filter_armor      = "鎧",
        filter_helmet     = "兜",
        filter_shoes      = "靴",
        filter_accessory  = "装飾",
        slot_weapon       = "メイン武器",
        slot_offhand      = "サブ武器",
        slot_armor        = "鎧",
        slot_helmet       = "兜",
        slot_shoes        = "靴",
        slot_accessory    = "装飾品",
        slot_all          = "全装備",
        cannot_wear       = "装備できない",
        level_not_enough_equip = "レベル不足です。Lv.{0} で装備可能",
        equipped          = "装備済み",
        unequipped        = "外しました",
        equipped_ok       = "装備しました",
    },
    ko = {
        tap_continue      = "화면을 터치하세요",
        loading_res       = "리소스 로딩 중",
        expedition_lv     = "원정 레벨 LV.{0}",
        settings          = "설정",
        bgm               = "배경음악",
        sfx               = "효과음",
        damage_numbers    = "데미지 숫자",
        show_effects      = "이펙트",
        redeem_code       = "코드 입력",
        language          = "언어",
        on                = "켜기",
        off               = "끄기",
        tab_battle        = "전투",
        tab_dungeon       = "던전",
        lang_changed      = "언어가 변경되었습니다",
        bag               = "봉인 창고",
        blacksmith        = "옥화 단조",
        tavern            = "부패 까마귀",
        church            = "침묵 예배당",
        market            = "월식 암시장",
        ancient_tree      = "종언 고목",
        unequip_all       = "일괄 해제",
        equip_all         = "일괄 장착",
        hero_detail       = "영웅 정보",
        quality           = "등급",
        class_label       = "직업",
        tab_attr          = "능력",
        tab_equip         = "장비",
        tab_class         = "전직",
        tab_awaken        = "각성",
        wear              = "장착",
        unequip           = "해제",
        replace           = "교체",
        filter_all        = "전체",
        filter_weapon     = "주무",
        filter_offhand    = "부무",
        filter_armor      = "갑옷",
        filter_helmet     = "투구",
        filter_shoes      = "신발",
        filter_accessory  = "장신",
        slot_weapon       = "주무기",
        slot_offhand      = "부무기",
        slot_armor        = "갑옷",
        slot_helmet       = "투구",
        slot_shoes        = "신발",
        slot_accessory    = "장신구",
        slot_all          = "전체 장비",
        cannot_wear       = "장착 불가",
        level_not_enough_equip = "레벨 부족, Lv.{0} 도달 시 장착 가능",
        equipped          = "장착됨",
        unequipped        = "해제됨",
        equipped_ok       = "장착됨",
    },
}

local function validLang(id)
    return T[id] ~= nil
end

function I18n.get()
    return current_
end

function I18n.displayName(id)
    id = id or current_
    return I18n.DISPLAY[id] or id
end

--- 一次遍历原模板；参数里的百分号和占位符不参与二次替换。
---@param template string
---@param ... any
---@return string
function I18n.interpolate(template, ...)
    local args = table.pack(...)
    return (template:gsub("%{(%d+)%}", function(index)
        local position = tonumber(index) + 1
        if position > args.n then return "{" .. index .. "}" end
        return tostring(args[position])
    end))
end

---@param key string
---@param ... string|number
---@return string
function I18n.t(key, ...)
    local pack = T[current_] or T.zh_CN
    local s = pack[key]
    if type(s) ~= "string" or s == "" then s = T.zh_CN[key] or key end
    return I18n.interpolate(s, ...)
end

---@param lang string
---@return boolean
function I18n.set(lang)
    if not validLang(lang) then return false end
    if current_ == lang then return true end
    current_ = lang
    print("[I18n] language=" .. lang)
    return true
end

function I18n.cycle()
    local idx = 1
    for i, item in ipairs(I18n.LANGS) do
        if item.id == current_ then
            idx = i
            break
        end
    end
    local nextItem = I18n.LANGS[idx % #I18n.LANGS + 1]
    I18n.set(nextItem.id)
    return nextItem.id
end

--- 已完成本地化和分段的显示串原样绘制，避免富文本片段被 hook 再次翻译。
---@param vg any
---@param x number
---@param y number
---@param text string
---@param endp any
---@return any
function I18n.displayText(vg, x, y, text, endp)
    local draw = rawNvgText_ or nvgText
    return draw(vg, x, y, text, endp)
end

--- 与 displayText 配对的原样测量；完整透传边界参数和返回值。
---@param vg any
---@param x number
---@param y number
---@param text string
---@param ... any
---@return any
function I18n.displayBounds(vg, x, y, text, ...)
    local measure = rawNvgTextBounds_ or nvgTextBounds
    return measure(vg, x, y, text, ...)
end

--- 已本地化或截取的剧情串原样换行绘制，不再查片段词典。
---@param vg any
---@param x number
---@param y number
---@param width number
---@param text string
---@param endp any
function I18n.displayTextBox(vg, x, y, width, text, endp)
    local draw = rawNvgTextBox_ or nvgTextBox
    return draw(vg, x, y, width, text, endp)
end

--- 与 displayTextBox 配对的原样边界测量。
---@param vg any
---@param x number
---@param y number
---@param width number
---@param text string
---@param ... any
---@return any
function I18n.displayTextBoxBounds(vg, x, y, width, text, ...)
    local measure = rawNvgTextBoxBounds_ or nvgTextBoxBounds
    return measure(vg, x, y, width, text, ...)
end

--- 拦截文字绘制和边界测量，保证两者收到同一译文。
function I18n.installDrawHook()
    if hooked_ then return end
    if type(nvgText) ~= "function" then return end
    rawNvgText_ = nvgText
    rawNvgTextBox_ = nvgTextBox
    rawNvgTextBounds_ = nvgTextBounds
    rawNvgTextBoxBounds_ = nvgTextBoxBounds
    nvgText = function(vg, x, y, text, endp)
        return rawNvgText_(vg, x, y, I18n.lookup(text), endp)
    end
    if type(rawNvgTextBox_) == "function" then
        nvgTextBox = function(vg, x, y, breakRowWidth, text, endp)
            return rawNvgTextBox_(vg, x, y, breakRowWidth, I18n.lookup(text), endp)
        end
    end
    if type(rawNvgTextBounds_) == "function" then
        nvgTextBounds = function(vg, x, y, text, ...)
            return rawNvgTextBounds_(vg, x, y, I18n.lookup(text), ...)
        end
    end
    if type(rawNvgTextBoxBounds_) == "function" then
        nvgTextBoxBounds = function(vg, x, y, breakRowWidth, text, ...)
            return rawNvgTextBoxBounds_(vg, x, y, breakRowWidth, I18n.lookup(text), ...)
        end
    end
    hooked_ = true
    print("[I18n] 文字绘制与测量翻译已安装")
end

return I18n
