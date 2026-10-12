-- 十名史诗Ⅱ完整正文：独立真实NanoVG/Noto字体专项，不加载main，不读写玩家档。
-- 由legendary_awakening_text_font_test.lua复制适配，沿scaffold-2d的Start/Stop + NanoVGRender。
-- 真实Viewport右栏设计缩放；双1920/1280、五语十条Ⅱ100样本与原短文30样本。
-- -awakening-font-baseline仅测原36号并报告溢出；默认验证真实Panel.draw，不替换测量/文字/热区。
-- File/FileSystem/fileSystem/GetFileSystem四入口封闭；owned fixture与点击声音为显式业务边界。
-- 不声明GPU截图、真实设备触控、性能或整游戏战斗验收；此入口不实现战斗联动。
local TAG = "[epic_awakening_two_text_font] "
local totals = { assertions = 0, failed = 0, samples = 0, glyphs = 0, hotspots = 0, overflow = 0, renders = 0 }
---@type NVGContextWrapper?
local vg = nil
local finished, cleaned, baseline = false, false, false
local patches = {} ---@type table[]
local ioCalls = 0
local fixture = { shards = 150, awakening = { _awk3Migrated = true }, extraTalent = {} }
local current = {} ---@type table
local modules = {} ---@type table
local BODY_X, BODY_Y, BODY_W, BODY_BOTTOM = 85, 1893.5, 910, 2110 - 12
local LANGS = { "zh_CN", "zh_TW", "en", "ja", "ko" }
local HEROES = { 10, 11, 12, 13, 14, 15, 21, 22, 23, 24 }
local SIZES = { { 1920, 1080 }, { 1280, 720 } }
-- 冻结c64364a4：旧Ⅱ必须逐字节作为前缀保留，包括H15旧60%文案；不反向修改业务。
local OLD_TWO = {
    [10] = "生命较低时护甲+12；开战生命加成提升至35%。",
    [11] = "通宵斩击杀可记录斩影（最多4道）；物理暴击率+10%、暴击伤害+35%。",
    [12] = "冰冻目标被击杀时生成冰雕（最多3座）；冰雕可替队友抵挡一次伤害，碎裂时冰冻敌人。首次冰冻延长2秒；自身首次低于半血时冰冻全场3秒。",
    [13] = "弹射击杀积累分裂层，每8层额外弹射一次（最多+5）；物理攻击加成+25%、攻击速度+25%。",
    [14] = "开战获得10次受击免疫；敌人死亡后额外获得1至2次免疫。每次敌人死亡暴击伤害+10%，最多+100%。",
    [15] = "为复活的队友留下一次濒死保护；复活概率提升至60%，复活时获得相当于最大生命20%的护盾，持续5秒。",
    [21] = "氮气触发后，下次攻击进度+15%；每80点命中额外获得5点护甲。",
    [22] = "连续攻击期间击杀可积累预存次数；触发间隔缩短至每15次攻击，连续攻击时攻击速度+50%并积累过载。",
    [23] = "有盾队友的下次攻击可附带本次治疗量20%的额外伤害；临时护盾上限提高20%，治疗暴击率+10%。",
    [24] = "加载条容量由最大生命的10%提升至14%；释放的伤害按粉碎属性结算。",
}
local FROZEN_THREE = {
    [1] = "生命低于35%时，衔骨效果翻倍；已记录的攻击属性可随普攻追加撕咬伤害。",
    [2] = "燃烧最多叠加3层；魔法暴击率+10%、魔法暴击伤害+50%。",
    [3] = "已读不回可攻击3名敌人；暴击伤害额外+50%。",
    [4] = "格挡成功有25%概率使攻击者眩晕1秒；化劲反击计入的格挡伤害提高50%。",
    [5] = "甲片满层时，甲片提供的属性效果额外提高50%。",
    [6] = "感电目标被暴击的概率额外提高10%。",
    [7] = "光线就绪时连击率+100%、连击伤害+30%；未就绪时无法触发连击。",
    [8] = "攻击生命低于15%的标记目标时可触发斩杀。",
    [9] = "温泉每秒恢复量提升至本次治疗量的25%。",
    [10] = "全队单次受到的伤害不超过各自最大生命的30%（冷却8秒）。",
    [11] = "有敌人阵亡后，调整攻击计数，使下一次攻击触发通宵斩。",
    [12] = "每冰冻一名敌人，魔法攻击加成+3%，最多20层。",
    [13] = "累计40次弹射击杀后，攻击可额外命中至多两名其他敌人；弹射可重复命中同一敌人。",
    [14] = "暴击时可斩杀生命低于15%的目标；暴击率溢出时有概率触发超暴击。",
    [15] = "自己阵亡时按本场救援次数造成神圣范围伤害；首次阵亡必定复活，并为全队恢复20%生命。",
    [16] = "飞剑命中后的飞回概率提升至50%。【万剑天倾】：剑冢提供的飞剑伤害比例加成翻倍；每第3轮飞剑额外发射一轮等伤剑雨，剑雨不触发飞回或伤害记录。",
    [17] = "场上至少3名敌人潮湿时，溅射会攻击所有潮湿目标；潮湿目标被暴击的概率额外提高10%。",
    [18] = "首次攻击获得的额外护甲克制系数提升至0.10；解锁暴击溢出转暴伤：超过100%的暴击率，每溢出1个百分点使暴击伤害提高1%（乘算）。",
    [19] = "清心减伤提升至25%，持续时间延长至4.5秒。",
    [20] = "星象共鸣效果提升50%。【群星坍缩】：觉醒1的星门伤害成长加成翻倍，每层星痕增伤由12%提升至24%；满5层星痕发射时，额外对最多4名敌人各造成首扇成功星门本轮发射伤害的150%。",
    [21] = "氮气额外伤害享受魔法伤害加成。",
    [22] = "连续攻击期间每击杀一名敌人，下一轮触发所需攻击次数减少；每发连射有20%概率攻击所有敌人。",
    [23] = "护盾清零时获得2秒无敌；每次触发后，下次触发概率减半。",
    [24] = "加载条闲置4秒未继续蓄能时，会释放已积累的伤害。",
    [25] = "延迟结算时若目标生命低于30%，该次延迟伤害再提高25%。【可靠传输】：补偿增幅提升为每层1%、最多400%；目标阵亡时延迟包转向其他存活敌人，结算后0.6秒重传一次等量伤害，重传不再次生成延迟包。",
}

local function check(ok, message)
    totals.assertions = totals.assertions + 1
    if not ok then totals.failed = totals.failed + 1; print(TAG .. "FAIL " .. message) end
end
local function patch(target, key, value)
    patches[#patches + 1] = { target = target, key = key, previous = target[key] }
    rawset(target, key, value)
end
local function denyIO(...)
    ioCalls = ioCalls + 1
    error("epic awakening font test forbids File/FS access: " .. tostring(select(1, ...)))
end
local function sealIO()
    patch(_G, "File", denyIO)
    patch(_G, "FileSystem", denyIO)
    patch(_G, "fileSystem", setmetatable({}, { __index = function() return denyIO end }))
    patch(_G, "GetFileSystem", denyIO)
end
local function cleanup()
    if cleaned then return end
    cleaned = true
    if modules.Panel then modules.Panel.kwText:clear(); modules.Panel.setOwnedDataGetter(nil) end
    if modules.I18n then modules.I18n.set(modules.language) end
    for i = #patches, 1, -1 do
        local item = patches[i]
        rawset(item.target, item.key, item.previous)
    end
    patches = {}
end

local function prepare()
    -- 封闭早于任何用户模块require；引擎资源缓存仍可加载正式字体/源码/图片。
    sealIO()
    modules.I18n = require("core.I18n")
    modules.language = modules.I18n.get()
    modules.Config = require("config.AwakeningConfig")
    modules.Extra = require("core.I18nDictExtra")
    modules.Keyword = require("ui.widget.KeywordText")
    modules.Viewport = require("core.Viewport")
    modules.Panel = require("ui.character.hero.AwakeningPanel")
    for heroId = 1, 25 do
        check(modules.Config.getNodeEffect(heroId, 3) == FROZEN_THREE[heroId],
            "c643冻结Ⅲ正文逐字节不变 H" .. heroId)
    end
    for _, heroId in ipairs(HEROES) do
        local old = OLD_TWO[heroId]
        local source = assert(modules.Config.getNodeEffect(heroId, 2))
        check(source:sub(1, #old) == old and #source > #old, "旧Ⅱ全文保留并追加 H" .. heroId)
    end
    check(modules.Config.NODE_COUNT == 3 and modules.Config.getShardCost(1) == 10
        and modules.Config.getShardCost(2) == 30 and modules.Config.getShardCost(3) == 50
        and modules.Config.getTotalShardCost() == 90, "觉醒阶段及费用不变")
    modules.Panel.setOwnedDataGetter(function() return fixture end)
    modules.Panel.initImages(vg)
    local sounds = require("systems.GameSFX")
    patch(sounds, "play", function() end) -- 关键词点击声音，不替换文字/热区/输入实现。
    local displayText = modules.I18n.displayText
    patch(modules.I18n, "displayText", function(ctx, x, y, text, endp)
        if current.capturing then
            local bounds = {}
            local advance = modules.I18n.displayBounds(ctx, x, y, text, bounds)
            current.glyphs[#current.glyphs + 1] = { text = text, bounds = bounds, advance = advance }
            totals.glyphs = totals.glyphs + 1
        end
        return displayText(ctx, x, y, text, endp)
    end)
    local draw = modules.Panel.kwText.draw
    patch(modules.Panel.kwText, "draw", function(self, ctx, text, x, y, width, size, lh, cx)
        current = { text = text, x = x, y = y, width = width, font = size, cx = cx,
            glyphs = {}, capturing = true }
        local h = draw(self, ctx, text, x, y, width, size, lh, cx)
        current.capturing, current.height = false, h
        return h
    end)
end

local function translated(source, lang)
    local expected = lang == "zh_CN" and source or modules.Extra[lang][source]
    check(type(expected) == "string" and expected ~= "", lang .. "新增正文有明确整句词典")
    check(modules.I18n.lookup(source) == expected, lang .. "真实I18n采用当前整句译文")
    return expected
end

local function baselineSample(heroId, stage, lang)
    local source = assert(modules.Config.getNodeEffect(heroId, stage))
    local expected = translated(source, lang)
    local keyword = modules.Keyword.new()
    local height, lines = keyword:measureHeight(vg, source, BODY_W, 36)
    current = { capturing = true, glyphs = {} }
    local drawn = keyword:draw(vg, source, BODY_X, BODY_Y, BODY_W, 36, nil, 540)
    current.capturing = false
    check(height == drawn and height > 0, "baseline真实测量/绘制高度一致")
    local fragments, bottom = {}, BODY_Y
    for _, glyph in ipairs(current.glyphs) do
        fragments[#fragments + 1] = glyph.text
        check(#glyph.bounds == 4, "baseline真实字墨bounds存在")
        bottom = math.max(bottom, glyph.bounds[4] or BODY_Y)
    end
    check(table.concat(fragments) == expected, "baseline保留整句所有字符")
    local overflow = BODY_Y + height > BODY_BOTTOM or bottom > BODY_BOTTOM
    if overflow then totals.overflow = totals.overflow + 1 end
    totals.samples = totals.samples + 1
    print(TAG .. "BASELINE lang=" .. lang .. " hero=" .. heroId .. " stage=" .. stage
        .. " font=36 lines=" .. lines .. " h=" .. height .. " inkBottom=" .. bottom
        .. " available=" .. (BODY_BOTTOM - BODY_Y) .. " overflow=" .. tostring(overflow))
end

local function finalSample(heroId, stage, lang, label, short)
    local Panel = modules.Panel
    local source = assert(modules.Config.getNodeEffect(heroId, stage))
    local expected = short and modules.I18n.lookup(source) or translated(source, lang)
    Panel.reset(heroId)
    check(Panel.handleInput(204 + (stage - 1) * 336, 1056, heroId), label .. "真实切片选择")
    Panel.draw(vg, heroId)
    check(current.text == source and current.x == BODY_X and current.y == BODY_Y
        and current.width == BODY_W and current.cx == 540,
        label .. "源正文/1893.5锚点/910宽/居中不变")
    check(Panel.BTN_CX == 720 and Panel.BTN_CY == 2160 and Panel.BTN_W == 520 and Panel.BTN_H == 100,
        label .. "按钮位置尺寸完全不变")
    local reference = modules.Keyword.new()
    local height, lines = reference:measureHeight(vg, source, BODY_W, current.font)
    local original = reference:measureHeight(vg, source, BODY_W, 36)
    check(current.font >= 18 and current.font <= 36 and current.height == height
        and BODY_Y + height <= BODY_BOTTOM, label .. "最终真实字号/高度留12px按钮间距")
    check((original <= BODY_BOTTOM - BODY_Y and current.font == 36)
        or (original > BODY_BOTTOM - BODY_Y and current.font < 36), label .. "只对确实溢出正文缩号")
    if current.font < 36 then
        check(reference:measureHeight(vg, source, BODY_W, current.font + 1) > BODY_BOTTOM - BODY_Y,
            label .. "整数最大可用字号，不多缩")
    end
    if short then check(current.font == 36, label .. "原短正文保持36号") end
    local fragments, bottom = {}, BODY_Y
    for _, glyph in ipairs(current.glyphs) do
        fragments[#fragments + 1] = glyph.text
        check(#glyph.bounds == 4 and glyph.bounds[1] >= BODY_X - 0.01
            and glyph.bounds[3] <= BODY_X + BODY_W + 0.01 and glyph.bounds[2] >= BODY_Y - 0.01
            and glyph.bounds[4] <= BODY_BOTTOM + 0.01, label .. "真实字墨逐段留在正文安全区")
        bottom = math.max(bottom, glyph.bounds[4] or BODY_Y)
    end
    check(#current.glyphs > 0 and table.concat(fragments) == expected,
        label .. "实际绘制全文逐字符相等，不截断省略")
    local layout = reference:_layout(vg, source, BODY_W, current.font)
    local keywords = 0
    for _, line in ipairs(layout.lines) do
        for _, piece in ipairs(line.pieces) do if piece.keyword then keywords = keywords + 1 end end
    end
    check(#Panel.kwText.hotspots == keywords, label .. "所有原关键词片段保留热点")
    for _, hit in ipairs(Panel.kwText.hotspots) do
        totals.hotspots = totals.hotspots + 1
        check(hit.x1 >= BODY_X and hit.x2 <= BODY_X + BODY_W and hit.y1 >= BODY_Y
            and hit.y2 + 4 < 2110 and hit.y2 <= BODY_BOTTOM,
            label .. "关键词热点及4px点击宽容不进入按钮")
        local popup = Panel.handleInput((hit.x1 + hit.x2) * 0.5, (hit.y1 + hit.y2) * 0.5, heroId)
        check(popup and Panel.kwText.popup and Panel.kwText.popup.key == hit.key,
            label .. "真实Panel输入仍打开该关键词")
        Panel.kwText:closePopup()
    end
    totals.samples = totals.samples + 1
    print(TAG .. "FIT " .. label .. " font=" .. current.font .. " originalH=" .. original
        .. " lines=" .. lines .. " h=" .. height .. " inkBottom=" .. bottom .. " keywords=" .. keywords)
end

function Start()
    for _, arg in ipairs(GetArguments()) do if arg == "-awakening-font-baseline" then baseline = true end end
    local ok, err = xpcall(function()
        vg = assert(nvgCreate(1), "real NanoVG context required")
        check(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "exact native multilingual sans font")
        check(nvgFindFont(vg, "sans-bold") < 0, "不借UI私有sans-bold或其他字体替代")
        prepare()
        SubscribeToEvent(vg, "NanoVGRender", "HandleEpicAwakeningFontRender")
    end, debug.traceback)
    if not ok then check(false, "Start " .. tostring(err)); cleanup(); finished = true; engine:Exit() end
end

function HandleEpicAwakeningFontRender()
    if finished or not vg then return end
    local index = totals.renders + 1
    local size = SIZES[index]
    if not size then return end
    totals.renders = index
    -- 模式A：指定1920/1280逻辑画布及DPR=1，以真实Viewport.layout×DS投影到右栏。
    nvgBeginFrame(vg, size[1], size[2], 1)
    nvgSave(vg)
    local ox, oy, scale = modules.Viewport.layout(size[1], size[2])
    nvgTranslate(vg, ox + modules.Viewport.PANELS.right.bx * scale, oy)
    nvgScale(vg, scale * modules.Viewport.DS, scale * modules.Viewport.DS)
    local ok, err = xpcall(function()
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 36)
        local bounds = {}
        check(nvgTextBounds(vg, 0, 0, "W国i", bounds) > 0 and #bounds == 4,
            "实际frame中原生字体返回字墨边界")
        check(nvgTextBounds(vg, 0, 0, "WWW") > nvgTextBounds(vg, 0, 0, "iii") * 2,
            "真实比例字体非等宽mock")
        for _, lang in ipairs(LANGS) do
            check(modules.I18n.set(lang), "真实语言切换 " .. lang)
            for _, heroId in ipairs(HEROES) do
                local label = size[1] .. "x" .. size[2] .. " " .. lang .. " H" .. heroId .. "/2"
                if baseline then baselineSample(heroId, 2, lang)
                else finalSample(heroId, 2, lang, label, false) end
            end
            if not baseline then
                for _, heroId in ipairs({ 1, 6, 12 }) do
                    finalSample(heroId, 1, lang, size[1] .. " " .. lang .. " shortH" .. heroId, true)
                end
            end
        end
    end, debug.traceback)
    nvgRestore(vg)
    nvgEndFrame(vg)
    if not ok then check(false, "harness " .. tostring(err)) end
    if baseline or index == #SIZES or not ok then
        check(ioCalls == 0, "独立Runtime全部File/FS请求0，无玩家档IO")
        check(totals.samples == (baseline and 50 or 130), "五语十新增Ⅱ正文及原短文完整测绘覆盖")
        finished = true
        cleanup()
        print(TAG .. "FINAL " .. (totals.failed == 0 and "ALL PASS" or "FAILED")
            .. " baseline=" .. tostring(baseline) .. " assertions=" .. totals.assertions .. " failed=" .. totals.failed
            .. " samples=" .. totals.samples .. " glyphs=" .. totals.glyphs .. " hotspots=" .. totals.hotspots
            .. " overflow=" .. totals.overflow .. " renders=" .. totals.renders .. " FileFS=" .. ioCalls)
        engine:Exit()
    end
end

function Stop()
    cleanup()
    if vg then nvgDelete(vg); vg = nil end
    print(TAG .. "STOP finished=" .. tostring(finished) .. " failed=" .. totals.failed)
end
