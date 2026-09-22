-- ============================================================================
-- I18n - 运行时五语（简/繁/英/日/韩）
-- 覆盖标题、设置、顶栏等玩家可见 UI。存档键 language 写入 settings_volume.json。
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
local loaded_ = false

local T = {
    zh_CN = {
        tap_continue      = "轻 触 屏 幕 继 续",
        loading_res       = "资源加载中",
        expedition_lv     = "远征等级 LV.{0}",
        settings          = "设置",
        bgm               = "背景音乐",
        sfx               = "音效",
        damage_numbers    = "伤害数字显示",
        show_effects      = "特效显示",
        redeem_code       = "兑换码",
        language          = "语言",
        on                = "开",
        off               = "关",
        tab_log           = "日志",
        tab_battle        = "战斗",
        tab_dungeon       = "副本",
        lang_changed      = "语言已切换",
    },
    zh_TW = {
        tap_continue      = "輕 觸 螢 幕 繼 續",
        loading_res       = "資源載入中",
        expedition_lv     = "遠征等級 LV.{0}",
        settings          = "設定",
        bgm               = "背景音樂",
        sfx               = "音效",
        damage_numbers    = "傷害數字顯示",
        show_effects      = "特效顯示",
        redeem_code       = "兌換碼",
        language          = "語言",
        on                = "開",
        off               = "關",
        tab_log           = "日誌",
        tab_battle        = "戰鬥",
        tab_dungeon       = "副本",
        lang_changed      = "語言已切換",
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

return I18n
