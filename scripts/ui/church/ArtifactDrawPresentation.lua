-- 神器开匣表现。基于 scaffold-2d 的声明式控件树，复用 DesignWidgetSurface
-- 与宿主 1080×2400 模式 A 帧；不新建上下文/字体/帧，不设置全局主题或 DPR。
-- 仅持有本模块加载的装饰图片；神器图标由既有共享 ImageCache 持有。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local ArtifactDefs = require("shared.artifact.ArtifactDefs")
local ArtifactAssetUtil = require("config.ArtifactAssetUtil")
local ImageCache = require("ui.widget.ImageCache")
local DarkIcon = require("core.DarkIcon")
local I18n = require("core.I18n")
local RepeatDrawButton = require("ui.widget.RepeatDrawButton")
local Timeline = require("ui.tavern.RecruitTimeline")
local M = {}

M.REPEAT_CX, M.REPEAT_CY, M.REPEAT_W, M.REPEAT_H = 540, 2170, 640, 100
local PATHS = {
    background = "image/界面底板/酒馆抽卡/UI_XKJM.png",
    back = "image/招募特效/card_back.png",
    ring = "image/招募特效/rune_ring.png",
    halo = "image/招募特效/halo.png",
    spark = "image/招募特效/spark.png",
    key = "image/货币道具/UI_icon_HJYS.png",
    gem = "image/货币道具/UI_icon_SJ_X.png",
}
---@class ArtifactDrawImage
---@field handle number
---@field width number
---@field height number
---@type table<any, table<string, ArtifactDrawImage>>
local contexts = {}
---@type any
local cachedVg = nil
---@type Widget?
local root = nil
---@type Label?
local title = nil
---@type Label?
local hint = nil
---@type Button?
local repeatButton = nil
---@class ArtifactDrawTextTree
---@field root Widget
---@field quality Label
---@field name Label
---@field desc Label
---@type ArtifactDrawTextTree[]
local cards = {}
local current = { rewards = {}, count = 1, chestType = "normal", phase = "idle",
    ready = false, waiting = false, language = "", quote = nil, repeatText = "",
    statusKey = "", showRepeat = false }
local BONE, COPPER = DarkIcon.Palette.BONE, DarkIcon.Palette.GOLD

-- 局部显示译文，不注入全局 I18n 字典、不改变配置/回执。说明先完整本地化再替换 X/Y。
-- 中文效果来自 ArtifactDefs 原文；四语仅为该只读展示补齐缺失的完整模板。
local LANG_TEXT = {
    zh_CN = { opening = "封印正在苏醒", result = "神器已显现", skip = "点击立即揭晓全部",
        close = "点击空白处关闭", waiting = "等待开箱结果…", one = "继续单抽", ten = "继续十连" },
    zh_TW = { opening = "封印正在甦醒", result = "神器已顯現", skip = "點擊立即揭曉全部",
        close = "點擊空白處關閉", waiting = "等待開箱結果…", one = "繼續單抽", ten = "繼續十連" },
    en = { opening = "The seal awakens", result = "Artifacts revealed", skip = "Tap to reveal all",
        close = "Tap empty space to close", waiting = "Waiting for chest results…", one = "Draw again", ten = "Draw ten again" },
    ja = { opening = "封印が目覚める", result = "神器が顕現", skip = "タップですべて開示",
        close = "空白をタップして閉じる", waiting = "宝箱の結果を待っています…", one = "もう1回", ten = "もう10回" },
    ko = { opening = "봉인이 깨어납니다", result = "신기 공개", skip = "눌러서 모두 공개",
        close = "빈 곳을 눌러 닫기", waiting = "보물상자 결과 대기 중…", one = "1회 더 뽑기", ten = "10회 더 뽑기" },
}
-- 顺序：繁、英、日、韩；简体始终读取该类型的正式静态说明。
local NAMES = {
    [1] = { "影羽斗篷", "Shadowfeather Cloak", "影羽の外套", "그림자 깃 망토" },
    [2] = { "星輝護符", "Starlight Amulet", "星輝の護符", "별빛 부적" },
    [3] = { "生命稜鏡", "Prism of Life", "生命のプリズム", "생명의 프리즘" },
    [4] = { "命運紡錘", "Spindle of Fate", "運命の紡錘", "운명의 물레" },
    [5] = { "巨人之鎧", "Giant's Armor", "巨人の鎧", "거인의 갑옷" },
    [6] = { "神聖十架", "Sacred Cross", "聖なる十字架", "성스러운 십자가" },
    [7] = { "左誓戰旗", "Left Oath Banner", "左誓の戦旗", "좌측 맹세 깃발" },
    [8] = { "右誓法典", "Right Oath Codex", "右誓の法典", "우측 맹세 법전" },
    [9] = { "血誓聖杯", "Blood Oath Grail", "血誓の聖杯", "혈맹 성배" },
    [10] = { "亡魂之祭", "Rite of Ghosts", "亡魂の祭儀", "망혼의 제례" },
    [11] = { "嘲諷面具", "Taunting Mask", "挑発の仮面", "도발 가면" },
    [12] = { "神徒之骰", "Disciple's Die", "信徒の骰子", "신도의 주사위" },
    [13] = { "狂怒沙漏", "Hourglass of Fury", "憤怒の砂時計", "격노의 모래시계" },
    [14] = { "審判官之錘", "Inquisitor's Hammer", "審判官の槌", "심판관의 망치" },
    [15] = { "魔王之瞳", "Demon King's Eye", "魔王の瞳", "마왕의 눈" },
    [16] = { "雙生壁壘", "Twin Bastions", "双生の防壁", "쌍둥이 보루" },
}
local EFFECTS = {
    [1] = { "進入戰鬥時額外閃避加成固定+200%；每次觸發閃避後，本次入場的額外加成減少初始值的X%（最低為0），不影響原有閃避",
        "Gain a fixed +200% extra dodge bonus on entering battle. Each dodge removes X% of the initial extra bonus for this entry, down to 0. Existing dodge is unaffected.",
        "戦闘開始時に回避ボーナスを追加で+200%。回避するたび、この入場時の追加分が初期値のX%ずつ減少（最低0）。元の回避には影響しない。",
        "전투 진입 시 추가 회피 보너스 +200%. 회피할 때마다 이번 진입의 추가 보너스가 초기값의 X%만큼 감소하며 최저 0. 기존 회피에는 영향 없음." },
    [2] = { "護盾加成額外增加X%，護盾破碎後，清除當前Y%的仇恨值",
        "Gain an extra X% shield bonus. When the shield breaks, clear Y% of current threat.",
        "シールドボーナスを追加でX%。シールド破壊時、現在のヘイトをY%除去。",
        "보호막 보너스 추가 X%. 보호막 파괴 시 현재 위협 수치의 Y% 제거." },
    [3] = { "將50%的生命值按X%比例轉化為最大護盾", "Convert 50% of HP into maximum shield at a ratio of X%.",
        "生命値の50%をX%の比率で最大シールドに変換。", "생명력의 50%를 X% 비율로 최대 보호막으로 전환." },
    [4] = { "無視敵人所有護甲，但護甲加成-X%", "Ignore all enemy armor, but armor bonus is reduced by X%.",
        "敵のすべての防御を無視するが、防御ボーナスが-X%。", "적의 모든 방어를 무시하지만 방어 보너스 -X%." },
    [5] = { "受到傷害時有50%機率立即反擊，造成X%攻擊的傷害", "When damaged, a 50% chance to counterattack immediately for X% of attack as damage.",
        "被ダメージ時、50%の確率で即反撃し、攻撃力のX%のダメージ。", "피해를 받으면 50% 확률로 즉시 반격하여 공격력의 X% 피해." },
    [6] = { "在戰鬥中首次死亡時，以50%生命值復活，並在復活後額外傷害+X%", "On the first death in battle, revive with 50% HP and gain +X% extra damage after revival.",
        "戦闘中の最初の死亡時、生命値50%で復活し、復活後の追加ダメージ+X%。", "전투 중 첫 사망 시 생명력 50%로 부활하며 부활 후 추가 피해 +X%." },
    [7] = { "使左槽位的友方遠征隊員物理攻擊加成+X%", "The allied expeditioner in the left slot gains +X% physical attack bonus.",
        "左スロットの味方遠征隊員の物理攻撃ボーナス+X%。", "왼쪽 슬롯 아군 원정대원의 물리 공격 보너스 +X%." },
    [8] = { "使右槽位的友方遠征隊員魔法攻擊加成+X%", "The allied expeditioner in the right slot gains +X% magic attack bonus.",
        "右スロットの味方遠征隊員の魔法攻撃ボーナス+X%。", "오른쪽 슬롯 아군 원정대원의 마법 공격 보너스 +X%." },
    [9] = { "巨額生命加成額外+X%，無法再以任何形式恢復生命值", "Gain an extra +X% massive HP bonus. HP can no longer be restored by any means.",
        "生命ボーナスを追加で+X%。いかなる方法でも生命値を回復できなくなる。", "생명력 보너스 추가 +X%. 어떤 방법으로도 생명력을 회복할 수 없음." },
    [10] = { "死亡時在10秒內變亡魂狀態，亡魂狀態下無法被攻擊選中，亡魂狀態額外增加X%傷害加成", "On death, become a ghost for 10 seconds: cannot be targeted by attacks and gains an extra X% damage bonus.",
        "死亡時、10秒間亡魂となる。攻撃対象に選ばれず、亡魂中のダメージボーナスを追加でX%。", "사망 시 10초간 망혼 상태. 공격 대상이 되지 않으며 망혼 상태에서 피해 보너스 추가 X%." },
    [11] = { "額外傷害+X，額外獲得X的2倍仇恨值", "Gain +X extra damage and twice X as extra threat.",
        "追加ダメージ+X。追加ヘイトはXの2倍。", "추가 피해 +X, 추가 위협 수치는 X의 2배." },
    [12] = { "暴擊傷害屬性變為原來的X%，但暴擊機率減半", "Critical damage becomes X% of its original value, but critical chance is halved.",
        "会心ダメージが元のX%になるが、会心率は半減。", "치명타 피해 속성이 기존의 X%가 되지만 치명타 확률은 절반." },
    [13] = { "攻擊間隔延長50%，但額外傷害+X%", "Attack interval is 50% longer, but extra damage is +X%.",
        "攻撃間隔が50%延長されるが、追加ダメージ+X%。", "공격 간격 50% 증가, 추가 피해 +X%." },
    [14] = { "每次攻擊命中同一目標，該目標對應傷害類型的抗性降低X個百分點（最多8層，僅對你生效）；切換目標時層數清零",
        "Each attack on the same target reduces its resistance to your damage type by X percentage points (up to 8 stacks, only for you). Changing targets clears the stacks.",
        "同じ対象への命中ごとに対応する属性の耐性をXポイント低下（最大8層、自身にのみ有効）。対象変更で層をリセット。",
        "동일 대상 명중마다 해당 피해 유형의 저항이 X%p 감소(최대 8중첩, 자신에게만 적용). 대상 변경 시 중첩 초기화." },
    [15] = { "攻擊造成的傷害使用混沌結算：合併物理與魔法穿透、傷害加成；按X%傷害倍率取代護甲類型克制。自身護甲、抗性和格擋失效",
        "Attacks use chaos damage: combine physical and magic penetration and damage bonuses; replace armor-type advantage with an X% damage multiplier. Your armor, resistances and block are disabled.",
        "攻撃は混沌計算：物理・魔法の貫通とダメージボーナスを合算し、防御相性の代わりにX%の倍率を使用。自身の防御・耐性・ガードは無効。",
        "공격은 혼돈 방식으로 계산: 물리·마법 관통과 피해 보너스를 합산하고 방어 유형 상성을 X% 피해 배율로 대체. 자신의 방어·저항·막기는 무효." },
    [16] = { "物理/魔法格擋率上限提升至X%，超過100%的部分可額外格擋", "Raise the physical/magic block chance cap to X%. The part above 100% can grant extra blocks.",
        "物理・魔法ガード率の上限をX%に上昇。100%超過分で追加ガード可能。", "물리·마법 막기 확률 상한을 X%로 증가. 100% 초과분으로 추가 막기 가능." },
}
local LANGUAGE_COLUMN = { zh_TW = 1, en = 2, ja = 3, ko = 4 }

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function clamp(value) return math.max(0, math.min(1, value)) end
local function color(c, alpha) return nvgRGBA(c[1], c[2], c[3], math.floor(clamp(alpha or 1) * 255)) end
local function translated(source, fallback)
    local text = I18n.lookup(source)
    return type(text) == "string" and text ~= source and text ~= "" and text or (fallback or source)
end
local function language() return I18n.get() end
local function words() return LANG_TEXT[language()] or LANG_TEXT.zh_CN end
local function numberText(value) return tostring(value) end
local function effectText(item)
    local def = ArtifactDefs.get(item.artifactId)
    local source = def and def.desc or ""
    local row = EFFECTS[tonumber(item.artifactId)]
    local column = LANGUAGE_COLUMN[language()]
    local text = translated(source, column and row and row[column] or source)
    -- 替换字符而非带百分号的片段，保留固定50/200%、真实X/Y和点数单位。
    text = text:gsub("X", function() return numberText(item.value) end)
    if item.threatClearValue ~= nil then
        text = text:gsub("Y", function() return numberText(item.threatClearValue) end)
    end
    return text
end

-- 按宿主字体实际量宽；在 prepare/语言变化时拟合，不在 draw 中重建树或量宽。
local function fitLabel(label, text, width, height, baseSize, multiline)
    label:SetText(text)
    local size = baseSize
    if cachedVg and type(nvgTextBounds) == "function" then
        nvgSave(cachedVg)
        local face = UI.Theme.FontFace("sans", "normal")
        nvgFontFace(cachedVg, face)
        if multiline and type(nvgTextBoxBounds) == "function" then
            nvgTextAlign(cachedVg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgTextLineHeight(cachedVg, 1.18)
            for _ = 1, 10 do
                nvgFontSize(cachedVg, UI.Theme.FontSize(size))
                local ok, bounds = pcall(I18n.displayTextBoxBounds, cachedVg, 0, 0, width - 8, text)
                if not ok or type(bounds) ~= "table" or not finite(bounds[2]) or not finite(bounds[4]) then break end
                if bounds[4] - bounds[2] <= height - 8 then break end
                size = size * 0.87
            end
        else
            nvgFontSize(cachedVg, UI.Theme.FontSize(baseSize))
            local measured = I18n.displayBounds(cachedVg, 0, 0, text)
            if finite(measured) and measured > width - 8 then size = baseSize * (width - 8) / measured end
        end
        nvgRestore(cachedVg)
    end
    label:SetStyle({ width = width, height = height, fontSize = size })
end

local function label(x, y, width, height, size, c, multiline)
    return UI.Label { text = "", fontFamily = "sans", fontWeight = "normal", fontSize = size,
        fontColor = { c[1], c[2], c[3], 255 }, position = "absolute", left = x, top = y,
        width = width, height = height, textAlign = "center", verticalAlign = "middle",
        whiteSpace = multiline and "normal" or "nowrap", wordBreak = "break-word",
        lineHeight = 1.18, flexShrink = 1, pointerEvents = "none" }
end

function M.init(vg)
    if vg == nil or (type(vg) == "number" and not finite(vg)) then return false end
    cachedVg = vg
    if not contexts[vg] then
        local images = {}
        contexts[vg] = images
        for key, path in pairs(PATHS) do
            local entry = { handle = -1, width = 1, height = 1 }
            images[key] = entry
            local ok, handle = pcall(nvgCreateImage, vg, path, 0)
            if ok and finite(handle) and handle >= 0 then
                entry.handle = handle
                if type(nvgImageSize) == "function" then
                    local sized, w, h = pcall(nvgImageSize, vg, handle)
                    if sized and finite(w) and finite(h) and w > 0 and h > 0 then entry.width, entry.height = w, h end
                end
            else
                print("[ArtifactDrawPresentation] 缺图，使用几何兜底：" .. path)
            end
        end
    end
    if root then return true end
    Surface.init()
    title = label(60, 175, 960, 90, 32, BONE, false)
    hint = label(40, 2250, 1000, 72, 23, BONE, true)
    repeatButton = UI.Button { text = "", position = "absolute", left = M.REPEAT_CX - M.REPEAT_W/2,
        top = M.REPEAT_CY - M.REPEAT_H/2, width = M.REPEAT_W, height = M.REPEAT_H,
        pointerEvents = "none", visible = false, onClick = function() end }
    -- 使用UI按钮子树承载旧按钮的共享量宽/混合货币绘制；不注册第二条输入路径。
    repeatButton.Render = function(self, context)
        local quote = current.quote or { parts = {} }
        RepeatDrawButton.draw(context, M.REPEAT_CX, M.REPEAT_CY, M.REPEAT_W, M.REPEAT_H,
            current.repeatText, quote.parts, quote.enough, quote.freeText)
    end
    root = UI.Panel { width = 1080, height = 2400, pointerEvents = "none", children = { title, hint, repeatButton } }
    for i = 1, 10 do
        local q = label(0, 0, 1, 1, 20, BONE, false)
        local name = label(0, 0, 1, 1, 24, BONE, true)
        local desc = label(0, 0, 1, 1, 24, BONE, true)
        cards[i] = { root = UI.Panel { width = 188, height = 520, pointerEvents = "none", overflow = "hidden",
            children = { q, name, desc } }, quality = q, name = name, desc = desc }
    end
    return true
end

function M.prepare(rewards, count, chestType)
    if not root or type(rewards) ~= "table" or (count ~= 1 and count ~= 10) then return false end
    current.rewards, current.count, current.chestType = rewards, count, chestType
    current.language, current.statusKey = language(), ""
    local single = count == 1
    local w, h = single and 740 or 188, single and 1260 or 520
    for i, item in ipairs(rewards) do
        local tree = cards[i]
        if tree then
            local def = ArtifactDefs.get(item.artifactId)
            local source = item.name or (def and def.name) or "未知神器"
            local names, column = NAMES[tonumber(item.artifactId)], LANGUAGE_COLUMN[current.language]
            local nameText = translated(source, source == (def and def.name) and column and names and names[column] or source)
            local qc = ArtifactDefs.getQualityColor(item.quality)
            local qText = I18n.lookup(ArtifactDefs.getQualityName(item.quality))
            tree.root:SetStyle({ width = w, height = h })
            local inner, left = w - (single and 76 or 22), single and 38 or 11
            tree.quality:SetStyle({ left = left, top = single and 30 or 14, fontColor = { qc[1], qc[2], qc[3], 255 } })
            fitLabel(tree.quality, qText, inner, single and 66 or 44, single and 31 or 21, false)
            tree.name:SetStyle({ left = left, top = single and 100 or 258 })
            fitLabel(tree.name, nameText, inner, single and 108 or 190, single and 39 or 23, true)
            tree.desc:SetStyle({ left = left, top = 640, visible = single })
            fitLabel(tree.desc, single and effectText(item) or "", inner, 450, 27, true)
            -- 实际数值只融入单抽效果说明；不显示公式占位符或内部比例。
            -- 只预热该回执的真实类型；共享图标不由本模块释放。
            pcall(ImageCache.getArtifactIcon, tonumber(item.artifactId))
        end
    end
    M.setStatus(current.phase, current.ready, current.waiting, chestType, current.showRepeat)
    return true
end

function M.setStatus(phase, ready, waiting, chestType, showRepeat)
    current.phase, current.ready, current.waiting = phase, ready == true, waiting == true
    current.chestType = chestType or current.chestType
    current.showRepeat = showRepeat == true
    local key = phase .. tostring(ready) .. tostring(waiting) .. tostring(current.chestType) .. language()
    if repeatButton then repeatButton:SetVisible(current.showRepeat) end
    if not title or not hint or current.statusKey == key then return end
    current.statusKey = key
    local text = words()
    fitLabel(title, phase == "intro" and text.opening or text.result, 960, 90, 32, false)
    fitLabel(hint, waiting and text.waiting or (ready and text.close or text.skip), 1000, 72, 23, true)
    current.repeatText = current.count == 10 and text.ten or text.one
    if repeatButton then repeatButton:SetText(current.repeatText) end
end

function M.setCost(quote, count)
    if count == 1 or count == 10 then current.count = count end
    if not quote then current.quote = nil; return end
    local parts = {}
    local images = contexts[cachedVg]
    for i, part in ipairs(quote.parts or {}) do
        local entry = images and images[part.type == "golden_key" and "key" or (part.type == "diamond" and "gem" or "")]
        parts[i] = { type = part.type, amount = part.amount, icon = part.icon or (entry and entry.handle) }
    end
    current.quote = { parts = parts, enough = quote.enough,
        freeText = quote.freeText and I18n.lookup(quote.freeText) or nil }
end

-- 在 Update 处理语言变化，draw 只读已准备好的显示文本。
function M.refreshLanguage()
    if current.language == language() then return end
    if #current.rewards > 0 then M.prepare(current.rewards, current.count, current.chestType) end
end

local function rect(vg, x, y, w, h, c, alpha, radius)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, radius or 0)
    nvgFillColor(vg, color(c, alpha))
    nvgFill(vg)
end
local function line(vg, x1, y1, x2, y2, c, alpha, width)
    nvgBeginPath(vg); nvgMoveTo(vg, x1, y1); nvgLineTo(vg, x2, y2)
    nvgStrokeColor(vg, color(c, alpha)); nvgStrokeWidth(vg, width or 2); nvgStroke(vg)
end
local function ring(vg, cx, cy, radius, c, alpha, width)
    nvgBeginPath(vg); nvgCircle(vg, cx, cy, radius)
    nvgStrokeColor(vg, color(c, alpha)); nvgStrokeWidth(vg, width or 2); nvgStroke(vg)
end
local function picture(vg, key, cx, cy, width, height, alpha, tint, angle, contain)
    local images = contexts[vg]
    local entry = images and images[key]
    if not entry or entry.handle < 0 or alpha <= 0.001 then return false end
    local w, h = width, height
    if contain then
        local fit = math.min(width / entry.width, height / entry.height)
        w, h = entry.width * fit, entry.height * fit
    end
    nvgSave(vg); nvgTranslate(vg, cx, cy)
    if angle then nvgRotate(vg, angle) end
    local paint = tint and nvgImagePatternTinted(vg, -w/2, -h/2, w, h, 0, entry.handle, color(tint, alpha))
        or nvgImagePattern(vg, -w/2, -h/2, w, h, 0, entry.handle, alpha)
    nvgBeginPath(vg); nvgRect(vg, -w/2, -h/2, w, h); nvgFillPaint(vg, paint); nvgFill(vg)
    nvgRestore(vg)
    return true
end
local function glow(vg, cx, cy, radius, c, alpha)
    nvgBeginPath(vg); nvgCircle(vg, cx, cy, radius)
    nvgFillPaint(vg, nvgRadialGradient(vg, cx, cy, radius * 0.08, radius,
        color(c, alpha), color(c, 0))); nvgFill(vg)
end

function M.drawBackground(vg, chestType)
    -- 与角色招募共用整页底板和压暗强度，独立持有句柄，不借用角色缓存。
    rect(vg, 0, 0, 1080, 2400, { 0, 0, 0 }, 1)
    picture(vg, "background", 540, 1200, 1080, 2400, 0.72)
    rect(vg, 0, 0, 1080, 2400, { 8, 10, 16 }, 70 / 255)
end

function M.drawIntro(vg, elapsed, chestType, highestQ)
    if not finite(elapsed) or not finite(highestQ) then return end
    local pose = Timeline.intro(elapsed)
    local tint = chestType == "advanced" and { 189, 137, 228 } or COPPER
    local qc = ArtifactDefs.getQualityColor(highestQ)
    local cx, cy = 540, 1140
    nvgSave(vg); nvgGlobalAlpha(vg, pose.alpha)
    glow(vg, cx, cy - 30, 580, tint, 0.12 + pose.charge * 0.14)
    picture(vg, "halo", cx, cy - 40, 860, 1060, pose.light * 0.24, tint)
    -- 封印双旋环：即使缺图也有清晰的几何封印。
    nvgSave(vg); nvgTranslate(vg, cx, cy - 40); nvgScale(vg, 1, 0.82)
    ring(vg, 0, 0, 350 + pose.opening * 45, tint, 0.35 + pose.charge * 0.4, 3)
    ring(vg, 0, 0, 300, COPPER, pose.sealAlpha * 0.6, 2)
    picture(vg, "ring", 0, 0, 690, 690, 0.3 + pose.charge * 0.34, tint, pose.ringAngle)
    for i = 1, 8 do
        local angle = i * math.pi / 4 - pose.ringAngle
        local r1, r2 = 280, 292 + pose.charge * 18
        line(vg, math.cos(angle)*r1, math.sin(angle)*r1, math.cos(angle)*r2, math.sin(angle)*r2,
            BONE, pose.sealAlpha * 0.7, 3)
    end
    nvgRestore(vg)
    -- 中央光柱逐渐从匣口打开，不做全屏白闪。
    local beam = 28 + pose.opening * 180
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - 18, cy - 90); nvgLineTo(vg, cx - beam, cy - 680)
    nvgLineTo(vg, cx + beam, cy - 680); nvgLineTo(vg, cx + 18, cy - 90); nvgClosePath(vg)
    nvgFillPaint(vg, nvgLinearGradient(vg, cx, cy - 650, cx, cy - 80,
        color(qc, 0), color(qc, pose.opening * 0.4))); nvgFill(vg)
    -- 几何宝匣：箱身、金属倒角、开盖。紫/金对应真实chestType，而非奖励升品质。
    rect(vg, cx - 238, cy + 144, 476, 40, { 26, 22, 19 }, 1, 7)
    rect(vg, cx - 214, cy - 60, 428, 208, { 29, 23, 22 }, 1, 12)
    nvgBeginPath(vg); nvgRoundedRect(vg, cx - 214, cy - 60, 428, 208, 12)
    nvgStrokeColor(vg, color(tint, 0.9)); nvgStrokeWidth(vg, 5); nvgStroke(vg)
    line(vg, cx - 190, cy + 112, cx + 190, cy + 112, COPPER, 0.7, 3)
    for _, x in ipairs({ cx - 146, cx + 146 }) do rect(vg, x - 14, cy - 48, 28, 180, tint, 0.32, 4) end
    nvgSave(vg); nvgTranslate(vg, cx, cy - 60 - pose.opening * 156)
    nvgRotate(vg, -pose.opening * 0.10); nvgScale(vg, 1, 1 - pose.opening * 0.4)
    rect(vg, -228, -112, 456, 120, { 48, 34, 29 }, 1, 18)
    nvgBeginPath(vg); nvgRoundedRect(vg, -228, -112, 456, 120, 18)
    nvgStrokeColor(vg, color(tint, 0.9)); nvgStrokeWidth(vg, 5); nvgStroke(vg)
    line(vg, -200, -84, 200, -84, BONE, 0.4, 2)
    nvgRestore(vg)
    rect(vg, cx - 34, cy - 87, 68, 110, COPPER, pose.sealAlpha, 10)
    ring(vg, cx, cy - 29, 17 + pose.charge * 3, BONE, pose.sealAlpha, 3)
    -- 六条封印裂隙/少量火星，解析轨迹不消费RNG。
    for i = 1, 6 do
        local angle = i * math.pi / 3 + pose.ringAngle
        local radius = 90 + pose.opening * 260
        local x, y = cx + math.cos(angle)*radius, cy - 40 + math.sin(angle)*radius
        line(vg, x, y, x + math.cos(angle)*38, y + math.sin(angle)*38, tint,
            pose.opening * (1 - pose.opening) * 2, 3)
        picture(vg, "spark", x, y, 14, 26, pose.light * 0.55, tint, angle)
    end
    nvgRestore(vg)
end

function M.drawBack(vg, cx, cy, width, height, alpha)
    if picture(vg, "back", cx, cy, width, height, alpha) then return end
    rect(vg, cx - width/2, cy - height/2, width, height, { 30, 25, 22 }, alpha, 12)
    nvgBeginPath(vg); nvgRoundedRect(vg, cx - width/2 + 5, cy - height/2 + 5, width - 10, height - 10, 10)
    nvgStrokeColor(vg, color(COPPER, alpha)); nvgStrokeWidth(vg, 3); nvgStroke(vg)
    ring(vg, cx, cy, width * 0.25, BONE, alpha * 0.6, 2)
end

function M.drawCardGlow(vg, cx, cy, width, height, quality, pulse, elapsed)
    if not finite(quality) or not finite(pulse) or not finite(elapsed) then return end
    local qc = ArtifactDefs.getQualityColor(quality)
    -- 中/高品质保留可辨认的余辉；揭晓冲击圈只在0.66秒翻牌末段出现。
    local ambient = quality >= 4 and 0.18 or (quality >= 3 and 0.10 or 0.025)
    local alpha = ambient + pulse * (quality >= 4 and 0.55 or 0.25)
    picture(vg, "halo", cx, cy, width * 1.65, height * 1.15, alpha, qc)
    glow(vg, cx, cy - height * 0.16, width * 0.8, qc, alpha * 0.45)
    if quality >= 3 and pulse > 0.001 then
        local p = clamp((elapsed / Timeline.CARD_DURATION - 0.55) / 0.45)
        ring(vg, cx, cy - height * 0.19, width * (0.35 + p * 0.45), qc, pulse * 0.64, quality >= 4 and 4 or 2)
    end
end

function M.drawFront(vg, item, cx, cy, width, height)
    local qc = ArtifactDefs.getQualityColor(item.quality)
    local x, y = cx - width/2, cy - height/2
    rect(vg, x, y, width, height, { 22, 18, 16 }, 1, 12)
    nvgBeginPath(vg); nvgRoundedRect(vg, x + 3, y + 3, width - 6, height - 6, 10)
    nvgStrokeColor(vg, color(qc, 0.86)); nvgStrokeWidth(vg, item.quality >= 4 and 4 or 2.5); nvgStroke(vg)
    if item.quality >= 4 then
        nvgBeginPath(vg); nvgRoundedRect(vg, x + 8, y + 8, width - 16, height - 16, 7)
        nvgStrokeColor(vg, color(COPPER, 0.75)); nvgStrokeWidth(vg, 2); nvgStroke(vg)
    end
    local single = width > 300
    local iconSize = single and 310 or 156
    local iconCY = y + (single and 395 or 161)
    ring(vg, cx, iconCY, iconSize * 0.53, qc, 0.34, 2)
    ArtifactAssetUtil.drawIcon(vg, item, cx, iconCY, iconSize, { hideQualityBg = true, iconPadding = single and 14 or 8 })
    if single then
        line(vg, x + 38, y + 590, x + width - 38, y + 590, COPPER, 0.3, 2)
    end
end

function M.drawCardText(vg, index, cx, cy, width, height, alpha)
    local tree = cards[index]
    if not tree then return end
    nvgSave(vg); nvgTranslate(vg, cx - width/2, cy - height/2); nvgGlobalAlpha(vg, clamp(alpha))
    Surface.draw(tree.root, vg, width, height)
    nvgRestore(vg)
end

function M.drawLabels(vg, alpha)
    if not root or not finite(alpha) then return end
    nvgSave(vg); nvgGlobalAlpha(vg, clamp(alpha))
    Surface.draw(root, vg, 1080, 2400)
    nvgRestore(vg)
end

function M.clear()
    current.rewards, current.quote, current.phase, current.statusKey = {}, nil, "idle", ""
    current.ready, current.waiting, current.showRepeat = false, false, false
    if repeatButton then repeatButton:SetVisible(false) end
end

function M.destroy()
    for vg, images in pairs(contexts) do
        local deleted = {}
        for _, entry in pairs(images) do
            if entry.handle >= 0 and not deleted[entry.handle] then
                deleted[entry.handle] = true
                pcall(nvgDeleteImage, vg, entry.handle)
            end
        end
    end
    contexts, cachedVg = {}, nil
    if root then root:Destroy() end
    for _, tree in ipairs(cards) do tree.root:Destroy() end
    cards = {}
    root, title, hint, repeatButton = nil, nil, nil, nil
    current.rewards, current.quote, current.language, current.phase, current.statusKey = {}, nil, "", "idle", ""
end

return M
