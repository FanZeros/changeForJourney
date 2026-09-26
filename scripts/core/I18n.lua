-- ============================================================================
-- I18n - 运行时五语（简/繁/英/日/韩）
-- 覆盖标题、设置、顶栏、城镇页、装备 HUD。语言写入 settings_volume.json。
-- 不要开引擎 .project/i18n.json enabled=true（会扫进梗名）。
-- ============================================================================

local I18n = {}

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
    if ok then mergeLang(dict_, d) end
    local ok2, extra = pcall(require, "core.I18nDictExtra")
    if ok2 then mergeLang(dict_, extra) end
    return dict_
end

--- 按中文原文查表；无条目则原样返回（梗名/剧情不翻）
---@param text any
---@return any
function I18n.lookup(text)
    if current_ == "zh_CN" then return text end
    if type(text) ~= "string" or text == "" then return text end
    local pack = dict()[current_]
    if not pack then return text end
    local hit = pack[text]
    if hit then return hit end
    return text
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
        tab_log           = "日志",
        tab_battle        = "战斗",
        tab_dungeon       = "副本",
        lang_changed      = "语言已切换",
        bag               = "背包",
        blacksmith        = "铁匠铺",
        tavern            = "酒馆",
        church            = "教堂",
        market            = "市场",
        ancient_tree      = "古树",
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
        tab_log           = "日誌",
        tab_battle        = "戰鬥",
        tab_dungeon       = "副本",
        lang_changed      = "語言已切換",
        bag               = "背包",
        blacksmith        = "鐵匠鋪",
        tavern            = "酒館",
        church            = "教堂",
        market            = "市場",
        ancient_tree      = "古樹",
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
        tab_log           = "Log",
        tab_battle        = "Battle",
        tab_dungeon       = "Dungeon",
        lang_changed      = "Language changed",
        bag               = "Bag",
        blacksmith        = "Smithy",
        tavern            = "Tavern",
        church            = "Chapel",
        market            = "Market",
        ancient_tree      = "World Tree",
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
        tab_log           = "日誌",
        tab_battle        = "戦闘",
        tab_dungeon       = "ダンジョン",
        lang_changed      = "言語を切り替えました",
        bag               = "バッグ",
        blacksmith        = "鍛冶屋",
        tavern            = "酒場",
        church            = "教会",
        market            = "市場",
        ancient_tree      = "古樹",
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
        tab_log           = "일지",
        tab_battle        = "전투",
        tab_dungeon       = "던전",
        lang_changed      = "언어가 변경되었습니다",
        bag               = "가방",
        blacksmith        = "대장간",
        tavern            = "주점",
        church            = "성당",
        market            = "시장",
        ancient_tree      = "고목",
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

---@param key string
---@param ... string|number
---@return string
function I18n.t(key, ...)
    local pack = T[current_] or T.zh_CN
    local s = pack[key] or (T.zh_CN[key] or key)
    local n = select("#", ...)
    if n <= 0 then return s end
    for i = 1, n do
        s = s:gsub("%{" .. (i - 1) .. "%}", tostring(select(i, ...)))
    end
    return s
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

--- 拦截 nvgText / nvgTextBox / nvgTextBounds，绘制时按原文查表
function I18n.installDrawHook()
    if hooked_ then return end
    if type(nvgText) ~= "function" then return end
    rawNvgText_ = nvgText
    rawNvgTextBox_ = nvgTextBox
    rawNvgTextBounds_ = nvgTextBounds
    nvgText = function(vg, x, y, text, endp)
        return rawNvgText_(vg, x, y, I18n.lookup(text), endp)
    end
    if type(rawNvgTextBox_) == "function" then
        nvgTextBox = function(vg, x, y, breakRowWidth, text, endp)
            return rawNvgTextBox_(vg, x, y, breakRowWidth, I18n.lookup(text), endp)
        end
    end
    if type(rawNvgTextBounds_) == "function" then
        nvgTextBounds = function(vg, x, y, text, endp)
            return rawNvgTextBounds_(vg, x, y, I18n.lookup(text), endp)
        end
    end
    hooked_ = true
    print("[I18n] nvgText draw hook installed")
end

return I18n
