-- TavernPopups.lua
-- 酒馆弹窗子模块：招募说明、历史招募、确认购买、飘字提示
-- 通过 setContext 接收主模块依赖

local GachaConfig    = require("config.GachaConfig")
local UrGachaConfig  = require("config.UrGachaConfig")
local GameState      = require("core.GameState")
local HC             = require("config.HeroConfig")
local DrawUtil       = require("core.DrawUtil")
local drawTextStroke = DrawUtil.drawTextStroke
local drawNineSlice  = DrawUtil.drawNineSlice
local hitTest        = DrawUtil.hitTest
local drawImageCentered      = DrawUtil.drawImageCentered
local drawRoundedRectCentered = DrawUtil.drawRoundedRectCentered
local BF = require("systems.ButtonFeedback")

local M = {}

-- ======================== ctx 依赖（由 setContext 注入） ========================

local doRecruitDirect   -- function(count): 执行招募
local syncDisplayData   -- function(): 同步界面显示数据
local getSelectedPoolId -- function(): 当前卡池 id
local canPullForCurrentPool -- function(count): 检查资源
local DESIGN_W = 1080
local DESIGN_H = 2400

--- 设置上下文依赖
function M.setContext(ctx)
    doRecruitDirect = ctx.doRecruitDirect
    syncDisplayData = ctx.syncDisplayData
    getSelectedPoolId = ctx.getSelectedPoolId
    canPullForCurrentPool = ctx.canPullForCurrentPool
    DESIGN_W = ctx.DESIGN_W or 1080
    DESIGN_H = ctx.DESIGN_H or 2400
end

-- ======================== 弹窗动画常量 ========================

local POPUP_OPEN_DURATION  = 0.25
local POPUP_CLOSE_DURATION = 0.20
local POPUP_SCALE_FROM     = 0.8
local POPUP_SCALE_TO       = 1.0


-- ======================== 招募说明弹窗常量 ========================

local INFO = {
    MASK_A    = 128,
    CX = 540,  CY = 1162,
    W  = 950,  H  = 1051,
    INSET_TOP = 180, INSET_LEFT = 40, INSET_RIGHT = 40, INSET_BOTTOM = 50,
    TITLE_CX = 540, TITLE_CY = 705, TITLE_SIZE = 60, TITLE_STROKE_W = 6,
    SUB_CX = 540, SUB_CY = 828, SUB_SIZE = 40,
    RULE_BG_CX = 540, RULE_BG_CY = 1068, RULE_BG_W = 850, RULE_BG_H = 380, RULE_BG_R = 14,
    RULE_BG_A = 13,
    RULE_PAD = 30,
    RULE_FONT_SIZE = 40,
    RULE_TEXT_R = 0x72, RULE_TEXT_G = 0x58, RULE_TEXT_B = 0x50,
    RULE_HL_R = 0xE6, RULE_HL_G = 0x87, RULE_HL_B = 0x00,
    POOL_TITLE_SIZE = 40,
    POOL_BG_CX = 540, POOL_BG_CY = 1456, POOL_BG_W = 850, POOL_BG_H = 332, POOL_BG_R = 14,
    POOL_BG_A = 13,
    POOL_PAD = 30,
    POOL_FONT_SIZE = 40,
    POOL_TEXT_R = 0x72, POOL_TEXT_G = 0x58, POOL_TEXT_B = 0x50,
    POOL_N_R = 0xA2,   POOL_N_G = 0xFF,   POOL_N_B = 0x94,
    POOL_R_R = 0x72,   POOL_R_G = 0xF2,   POOL_R_B = 0xF5,
    POOL_SR_R = 0xEF,  POOL_SR_G = 0x79,  POOL_SR_B = 0xFF,
    POOL_SSR_R = 0xFF, POOL_SSR_G = 0xED, POOL_SSR_B = 0x00,
    POOL_STROKE_R = 0x30, POOL_STROKE_G = 0x30, POOL_STROKE_B = 0x30, POOL_STROKE_W = 5,
}

-- ======================== 历史招募弹窗常量 ========================

local HIST = {
    MASK_A    = 128,
    CX = 540,  CY = 1162,
    W  = 950,  H  = 1051,
    INSET_TOP = 180, INSET_LEFT = 40, INSET_RIGHT = 40, INSET_BOTTOM = 50,
    TITLE_CX = 540, TITLE_CY = 705, TITLE_SIZE = 60, TITLE_STROKE_W = 6,
    LABEL_BG_CX = 540, LABEL_BG_CY = 849, LABEL_BG_W = 850, LABEL_BG_H = 74, LABEL_BG_R = 14,
    LABEL_BG_A = 13,
    LABEL_GET_X = 174, LABEL_GET_Y = 848, LABEL_SIZE = 40,
    LABEL_TIME_X = 571, LABEL_TIME_Y = 849,
    LABEL_R = 0x72, LABEL_G = 0x58, LABEL_B = 0x50,
    LIST_BG_CX = 540, LIST_BG_CY = 1257, LIST_BG_W = 850, LIST_BG_H = 690, LIST_BG_R = 14,
    LIST_BG_A = 13,
    LIST_PAD_TOP = 24,
    LIST_PAD_LEFT = 21,
    LINE_H = 60,
    ITEM_X = 136,
    TIME_X = 533,
    ITEM_SIZE = 40,
    TIME_SIZE = 40,
    STROKE_R = 0x30, STROKE_G = 0x30, STROKE_B = 0x30, STROKE_W = 5,
    VISIBLE_ROWS = 10,
}

-- ======================== 二级确认框常量 ========================

local CF = {
    MASK_A    = 128,
    CX = 540,  CY = 1110,
    W  = 950,  H  = 647,
    TITLE_CX = 540, TITLE_CY = 856, TITLE_SIZE = 50, TITLE_STROKE_W = 6,
    SUB_CX = 540, SUB_CY = 967, SUB_SIZE = 40,
    SUB_R = 0xB6, SUB_G = 0xB0, SUB_B = 0x9D,
    CONTENT_CX = 540, CONTENT_CY = 1121, CONTENT_W = 800, CONTENT_H = 218, CONTENT_A = 13,
    ARROW_CX = 540, ARROW_CY = 1123, ARROW_W = 48, ARROW_H = 48,
    DIAMOND_CX = 415, DIAMOND_CY = 1122, DIAMOND_W = 160, DIAMOND_H = 160,
    TICKET_CX = 664, TICKET_CY = 1122, TICKET_W = 160, TICKET_H = 160,
    BADGE_SIZE = 40, BADGE_STROKE_W = 5, BADGE_OX = 60, BADGE_OY = 55,
    BUY_CX = 540, BUY_CY = 1301, BUY_W = 410, BUY_H = 100,
    BUY_TEXT_SIZE = 40, BUY_TEXT_R = 0x64, BUY_TEXT_G = 0x51, BUY_TEXT_B = 0x29,
    BTN_INSET_TOP = 10, BTN_INSET_BOTTOM = 10, BTN_INSET_LEFT = 40, BTN_INSET_RIGHT = 40,
}

-- ======================== 弹窗状态 ========================

local popupState = {
    -- 历史招募弹窗
    historyVisible  = false,
    historyScrollY  = 0,
    historyTouchY   = nil,
    -- 招募说明弹窗
    infoVisible     = false,
    infoScrollY     = 0,
    infoTouchY      = nil,
    -- 二级确认框
    confirmVisible  = false,
    confirmCount    = 1,
    confirmNeedTickets  = 0,
    confirmDiamondCost  = 0,
    confirmIsStellar    = false,
    -- 弹窗动画
    popupAnimTime   = 0,
    popupClosing    = false,
    popupCloseTime  = 0,
    popupCloseTarget = nil,
    -- 飘字提示
    floatText       = nil,
    floatTextX      = 0,
    floatTextY      = 0,
    floatTextTime   = 0,
}

-- ======================== 图片资源（弹窗专用） ========================

local img = {
    confirmBg     = -1,
    confirmArrow  = -1,
    confirmBtnBuy = -1,
    diamondBig    = -1,
    ticketBig     = -1,
    ticketBigStellar = -1,
    diamondBg     = -1,
    ticketQBg     = -1,
}

-- ======================== 缓动函数 ========================

local function easeOutCubic(t)
    t = t - 1
    return t * t * t + 1
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 弹窗动画系统 ========================

--- 打开指定弹窗
local function openPopup(name)
    if name == "history" then
        popupState.historyVisible = true
        popupState.historyScrollY = 0
        popupState.historyTouchY = nil
    elseif name == "info" then
        popupState.infoVisible = true
        popupState.infoScrollY = 0
        popupState.infoTouchY = nil
    elseif name == "confirm" then
        popupState.confirmVisible = true
    end
    popupState.popupAnimTime = time.elapsedTime
    popupState.popupClosing = false
    popupState.popupCloseTarget = nil
end

--- 开始关闭弹窗动画
local function closePopup(name)
    popupState.popupClosing = true
    popupState.popupCloseTime = time.elapsedTime
    popupState.popupCloseTarget = name
end

--- 计算弹窗动画参数 → scale, alpha, done
local function getPopupAnim()
    if popupState.popupClosing then
        local t = math.min(1.0, (time.elapsedTime - popupState.popupCloseTime) / POPUP_CLOSE_DURATION)
        local e = easeInCubic(t)
        local scale = POPUP_SCALE_TO + (POPUP_SCALE_FROM - POPUP_SCALE_TO) * e
        local alpha = 1.0 - e
        return scale, alpha, (t >= 1.0)
    else
        local t = math.min(1.0, (time.elapsedTime - popupState.popupAnimTime) / POPUP_OPEN_DURATION)
        local e = easeOutCubic(t)
        local scale = POPUP_SCALE_FROM + (POPUP_SCALE_TO - POPUP_SCALE_FROM) * e
        local alpha = e
        return scale, alpha, false
    end
end

-- ======================== 历史招募数据 ========================

local RES_NAME_MAP = {
    gold           = "金币",
    essence        = "精粹",
    enhance_star   = "强化星石",
    sweep_ticket   = "扫荡券",
    degrade_protect = "退级保护石",
    break_protect  = "损毁保护石",
}

local QUALITY_TAG = { [0] = "N", [1] = "R", [2] = "SR", [3] = "SSR" }
local STELLAR_QUALITY_TAG = { [1] = "R", [2] = "SR", [3] = "SSR", [4] = "UR" }

local historyData = {
    standard = {},
    stellar  = {},
}

local function isStellarPoolId(poolId)
    return poolId == UrGachaConfig.POOL_ID or poolId == "stellar"
end

local function getActivePoolId()
    if getSelectedPoolId then
        return getSelectedPoolId()
    end
    return "standard"
end

local function getHistoryBucket(poolId)
    return isStellarPoolId(poolId) and "stellar" or "standard"
end

local function getActiveHistoryList()
    return historyData[getHistoryBucket(getActivePoolId())]
end

local QUOTA_FAIL_TEXT = "剩余购买次数不足"

--- 将服务端招募失败原因转为玩家可读文案
---@param reason string|nil
---@return string
function M.formatGachaFailReason(reason)
    if not reason then return "招募失败" end
    local text = tostring(reason)
    if text:find("钻石购买星辉") or text:find("购买上限") or text == QUOTA_FAIL_TEXT then
        return QUOTA_FAIL_TEXT
    end
    return text
end

-- ======================== 抽卡记录本地持久化 ========================

local HISTORY_SAVE_FILE = "gacha_history.json"

--- 保存抽卡记录到本地文件
local function saveHistoryData()
    local payload = {
        version  = 2,
        standard = historyData.standard,
        stellar  = historyData.stellar,
    }
    local ok, str = pcall(cjson.encode, payload)
    if not ok then return end
    local file = File(HISTORY_SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(str)
        file:Close()
    end
end

--- 从本地文件加载抽卡记录
local function loadHistoryData()
    if not fileSystem:FileExists(HISTORY_SAVE_FILE) then return end
    local file = File(HISTORY_SAVE_FILE, FILE_READ)
    if not file:IsOpen() then return end
    local raw = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" then return end
    if data.standard or data.stellar then
        historyData.standard = data.standard or {}
        historyData.stellar  = data.stellar or {}
        return
    end
    -- 旧版扁平数组 → 归入常规招募
    if data[1] then
        historyData.standard = data
        historyData.stellar  = {}
    end
end

-- 模块加载时自动读取历史记录
loadHistoryData()

local function formatNowTime()
    local t = os.date("*t")
    return string.format("%d/%d/%d/%02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.min, t.sec)
end

--- 将一批抽卡结果追加到历史记录
---@param results table[] 抽卡结果数组
---@param poolId string|nil "standard"|"stellar"
function M.recordHistory(results, poolId)
    poolId = poolId or "standard"
    local bucket = getHistoryBucket(poolId)
    local list = historyData[bucket]
    local isStellar = bucket == "stellar"
    local timeStr = formatNowTime()
    for _, r in ipairs(results) do
        local name
        if r.type == "hero" then
            local hero = HC.HEROES[r.heroId]
            name = hero and hero.name or ("英雄" .. tostring(r.heroId))
        elseif r.type == "shard" then
            local hero = HC.HEROES[r.heroId]
            local heroName = hero and hero.name or ("英雄" .. tostring(r.heroId))
            name = heroName .. "碎片×" .. tostring(r.amount or 1)
        elseif r.type == "dupe_to_shard" then
            local hero = HC.HEROES[r.heroId]
            local heroName = hero and hero.name or ("英雄" .. tostring(r.heroId))
            name = heroName .. "→碎片×" .. tostring(r.shardGain or 10)
        elseif r.type == "decompose" then
            local hero = HC.HEROES[r.heroId]
            local heroName = hero and hero.name or ("英雄" .. tostring(r.heroId))
            name = heroName .. "→酒馆币×" .. tostring(r.tavernCoin or 0)
        else
            name = RES_NAME_MAP[r.resType] or r.resType or "未知"
        end
        local tagMap = isStellar and STELLAR_QUALITY_TAG or QUALITY_TAG
        local tag = tagMap[r.quality] or (isStellar and "R" or "N")
        table.insert(list, 1, {
            name    = "[" .. tag .. "]" .. name,
            quality = r.quality or (isStellar and 1 or 0),
            time    = timeStr,
        })
    end
    local MAX_HISTORY = 200
    while #list > MAX_HISTORY do
        table.remove(list)
    end
    saveHistoryData()
end

-- ======================== 招募说明弹窗 - 数据构建 ========================

local QUALITY_COLOR = {
    [0] = { INFO.POOL_N_R,   INFO.POOL_N_G,   INFO.POOL_N_B   },
    [1] = { INFO.POOL_R_R,   INFO.POOL_R_G,   INFO.POOL_R_B   },
    [2] = { INFO.POOL_SR_R,  INFO.POOL_SR_G,  INFO.POOL_SR_B  },
    [3] = { INFO.POOL_SSR_R, INFO.POOL_SSR_G, INFO.POOL_SSR_B },
}

local STELLAR_QUALITY_COLOR = {
    [1] = { INFO.POOL_N_R,   INFO.POOL_N_G,   INFO.POOL_N_B   },
    [2] = { INFO.POOL_SR_R,  INFO.POOL_SR_G,  INFO.POOL_SR_B  },
    [3] = { INFO.POOL_SSR_R, INFO.POOL_SSR_G, INFO.POOL_SSR_B },
    [4] = { INFO.POOL_SSR_R, INFO.POOL_SSR_G, INFO.POOL_SSR_B },
}

local _infoPoolLines = {}

local function buildInfoPoolLines(poolId)
    if _infoPoolLines[poolId] then return _infoPoolLines[poolId] end

    local lines = {}
    if isStellarPoolId(poolId) then
        local qualityOrder = {
            UrGachaConfig.QUALITY_UR,
            UrGachaConfig.QUALITY_SSR,
            UrGachaConfig.QUALITY_SR,
            UrGachaConfig.QUALITY_R,
        }
        for _, q in ipairs(qualityOrder) do
            local poolGroup = UrGachaConfig.getPoolGroup(q)
            if poolGroup then
                local names = {}
                for _, item in ipairs(poolGroup.items) do
                    if item.type == "hero" then
                        local hero = HC.HEROES[item.heroId]
                        names[#names + 1] = hero and hero.name or ("英雄" .. item.heroId)
                    end
                end
                local tag = STELLAR_QUALITY_TAG[q] or "R"
                local clr = STELLAR_QUALITY_COLOR[q] or STELLAR_QUALITY_COLOR[1]
                for i = 1, #names, 3 do
                    local segments = {}
                    for j = i, math.min(i + 2, #names) do
                        if j > i then
                            segments[#segments + 1] = { text = " ", r = clr[1], g = clr[2], b = clr[3] }
                        end
                        segments[#segments + 1] = { text = "[" .. tag .. "]" .. names[j], r = clr[1], g = clr[2], b = clr[3] }
                    end
                    lines[#lines + 1] = { segments = segments }
                end
            end
        end
    else
        local groups = {}
        local qualityOrder = { 3, 2, 1, 0 }
        for _, q in ipairs(qualityOrder) do
            local poolGroup = GachaConfig.getPoolGroup(q)
            if poolGroup then
                local names = {}
                for _, item in ipairs(poolGroup.items) do
                    if item.type == "hero" then
                        local hero = HC.HEROES[item.heroId]
                        names[#names + 1] = hero and hero.name or ("英雄" .. item.heroId)
                    elseif item.type == "shard" then
                        local hero = HC.HEROES[item.heroId]
                        local heroName = hero and hero.name or ("英雄" .. item.heroId)
                        names[#names + 1] = heroName .. "碎片"
                    else
                        local resName = RES_NAME_MAP[item.resType] or item.resType
                        names[#names + 1] = resName
                    end
                end
                groups[#groups + 1] = { quality = q, names = names }
            end
        end
        for _, grp in ipairs(groups) do
            local tag = QUALITY_TAG[grp.quality]
            local clr = QUALITY_COLOR[grp.quality]
            for i = 1, #grp.names, 3 do
                local segments = {}
                for j = i, math.min(i + 2, #grp.names) do
                    if j > i then
                        segments[#segments + 1] = { text = " ", r = clr[1], g = clr[2], b = clr[3] }
                    end
                    segments[#segments + 1] = { text = "[" .. tag .. "]" .. grp.names[j], r = clr[1], g = clr[2], b = clr[3] }
                end
                lines[#lines + 1] = { segments = segments }
            end
        end
    end

    _infoPoolLines[poolId] = lines
    return lines
end

-- ======================== 多段彩色文本绘制 ========================

local STROKE_OFFSETS_16 = {}
for i = 0, 15 do
    local angle = i * math.pi * 2 / 16
    STROKE_OFFSETS_16[#STROKE_OFFSETS_16 + 1] = { math.cos(angle), math.sin(angle) }
end

-- 文本宽度缓存：避免在 scale 动画期间因字体 hinting 导致 nvgTextBounds 返回值波动
-- key = "text\0fontSize"，value = advance width（在无变换状态下测量）
local _textWidthCache = {}

--- 获取文本宽度（使用缓存避免 scale 动画抖动）
local function getCachedTextWidth(vg, text, fontSize)
    local key = text .. "\0" .. fontSize
    local w = _textWidthCache[key]
    if not w then
        -- 在当前变换下测量一次并缓存
        -- 首次测量发生在 scale=0.8 附近，但一旦缓存后每帧位置稳定不再跳动
        w = nvgTextBounds(vg, 0, 0, text)
        _textWidthCache[key] = w
    end
    return w
end

local function drawColorSegments(vg, x, y, segments, fontSize, strokeR, strokeG, strokeB, strokeW)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- 预计算各段的 x 偏移（使用缓存宽度，确保动画过程中位置稳定）
    local offsets = {}
    local curOff = 0
    for i, seg in ipairs(segments) do
        offsets[i] = curOff
        curOff = curOff + getCachedTextWidth(vg, seg.text, fontSize)
    end

    if strokeR then
        local dist = strokeW or 5
        nvgFillColor(vg, nvgRGBA(strokeR, strokeG, strokeB, 255))
        for _, off in ipairs(STROKE_OFFSETS_16) do
            local ox, oy = off[1] * dist, off[2] * dist
            for i, seg in ipairs(segments) do
                nvgText(vg, x + offsets[i] + ox, y + oy, seg.text, nil)
            end
        end
    end
    for i, seg in ipairs(segments) do
        nvgFillColor(vg, nvgRGBA(seg.r, seg.g, seg.b, 255))
        nvgText(vg, x + offsets[i], y, seg.text, nil)
    end
end

-- ======================== 招募说明弹窗 - 绘制辅助 ========================

local function drawInfoRuleText(vg, poolId)
    local x = INFO.RULE_BG_CX - INFO.RULE_BG_W * 0.5 + INFO.RULE_PAD
    local y = INFO.RULE_BG_CY - INFO.RULE_BG_H * 0.5 + INFO.RULE_PAD
    local lineH = 46
    local tr, tg, tb = INFO.RULE_TEXT_R, INFO.RULE_TEXT_G, INFO.RULE_TEXT_B
    local hr, hg, hb = INFO.RULE_HL_R, INFO.RULE_HL_G, INFO.RULE_HL_B

    local ruleLines
    if isStellarPoolId(poolId) then
        local pity = UrGachaConfig.Pity
        ruleLines = {
            { { text = "每", r = tr, g = tg, b = tb },
              { text = tostring(pity.SR_THRESHOLD), r = hr, g = hg, b = hb },
              { text = "次招募必定获得", r = tr, g = tg, b = tb },
              { text = "SR", r = hr, g = hg, b = hb },
              { text = "级冒险家", r = tr, g = tg, b = tb } },
            { { text = "每", r = tr, g = tg, b = tb },
              { text = tostring(pity.SSR_THRESHOLD), r = hr, g = hg, b = hb },
              { text = "次招募必定获得", r = tr, g = tg, b = tb },
              { text = "SSR", r = hr, g = hg, b = hb },
              { text = "级冒险家", r = tr, g = tg, b = tb } },
            { { text = "每", r = tr, g = tg, b = tb },
              { text = tostring(pity.UR_THRESHOLD), r = hr, g = hg, b = hb },
              { text = "次招募必定获得", r = tr, g = tg, b = tb },
              { text = "UR", r = hr, g = hg, b = hb },
              { text = "级冒险家", r = tr, g = tg, b = tb } },
            {},
            { { text = "各品质基础概率：", r = tr, g = tg, b = tb } },
            { { text = "R  : ", r = tr, g = tg, b = tb },
              { text = string.format("%.0f%%", UrGachaConfig.Probability[UrGachaConfig.QUALITY_R] or 0),
                r = hr, g = hg, b = hb } },
            { { text = "SR : ", r = tr, g = tg, b = tb },
              { text = string.format("%.0f%%", UrGachaConfig.Probability[UrGachaConfig.QUALITY_SR] or 0),
                r = hr, g = hg, b = hb } },
            { { text = "SSR: ", r = tr, g = tg, b = tb },
              { text = string.format("%.0f%%", UrGachaConfig.Probability[UrGachaConfig.QUALITY_SSR] or 0),
                r = hr, g = hg, b = hb } },
            { { text = "UR : ", r = tr, g = tg, b = tb },
              { text = string.format("%.0f%%", UrGachaConfig.Probability[UrGachaConfig.QUALITY_UR] or 0),
                r = hr, g = hg, b = hb } },
        }
    else
        ruleLines = {
            { { text = "每", r = tr, g = tg, b = tb },
              { text = "80", r = hr, g = hg, b = hb },
              { text = "次招募必定获得", r = tr, g = tg, b = tb },
              { text = "SSR", r = hr, g = hg, b = hb },
              { text = "级冒险家", r = tr, g = tg, b = tb } },
            { { text = "第", r = tr, g = tg, b = tb },
              { text = "61", r = hr, g = hg, b = hb },
              { text = "抽起SSR概率逐抽提升", r = tr, g = tg, b = tb } },
            {},
            { { text = "各品质基础概率：", r = tr, g = tg, b = tb } },
            { { text = "N  : ", r = tr, g = tg, b = tb },
              { text = "71%", r = hr, g = hg, b = hb } },
            { { text = "R  : ", r = tr, g = tg, b = tb },
              { text = "18%", r = hr, g = hg, b = hb } },
            { { text = "SR : ", r = tr, g = tg, b = tb },
              { text = "10%", r = hr, g = hg, b = hb } },
            { { text = "SSR: ", r = tr, g = tg, b = tb },
              { text = "1%", r = hr, g = hg, b = hb } },
        }
    end

    for i, segs in ipairs(ruleLines) do
        if #segs > 0 then
            drawColorSegments(vg, x, y + (i - 1) * lineH, segs, INFO.RULE_FONT_SIZE)
        end
    end
end

local function drawInfoPoolContent(vg, poolId)
    local bgX = INFO.POOL_BG_CX - INFO.POOL_BG_W * 0.5
    local bgY = INFO.POOL_BG_CY - INFO.POOL_BG_H * 0.5
    local contentX = bgX + INFO.POOL_PAD
    local contentY = bgY + INFO.POOL_PAD
    local contentW = INFO.POOL_BG_W - INFO.POOL_PAD * 2
    local contentH = INFO.POOL_BG_H - INFO.POOL_PAD * 2
    local lineH = 46
    local titleH = 50

    local lines = buildInfoPoolLines(poolId)
    local totalH = titleH + #lines * lineH

    local maxScroll = math.max(0, totalH - contentH)
    popupState.infoScrollY = math.max(0, math.min(maxScroll, popupState.infoScrollY))

    nvgSave(vg)
    nvgScissor(vg, contentX, contentY, contentW, contentH)

    local titleY = contentY - popupState.infoScrollY
    if titleY + titleH > contentY and titleY < contentY + contentH then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, INFO.POOL_TITLE_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(INFO.RULE_TEXT_R, INFO.RULE_TEXT_G, INFO.RULE_TEXT_B, 255))
        nvgText(vg, contentX, titleY, "可获得的奖励：", nil)
    end

    local itemsStartY = contentY + titleH - popupState.infoScrollY
    for i, line in ipairs(lines) do
        local ly = itemsStartY + (i - 1) * lineH
        if ly + lineH > contentY and ly < contentY + contentH then
            drawColorSegments(vg, contentX, ly, line.segments, INFO.POOL_FONT_SIZE,
                INFO.POOL_STROKE_R, INFO.POOL_STROKE_G, INFO.POOL_STROKE_B, INFO.POOL_STROKE_W)
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)
end

-- ======================== 公开接口 ========================

--- 初始化弹窗资源
function M.init(vg)
    img.confirmBg     = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    img.confirmArrow  = nvgCreateImage(vg, "image/UI_TJP_JIANTOU.png", 0)
    img.confirmBtnBuy = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    img.diamondBig    = nvgCreateImage(vg, "image/UI_icon_SJ.png", 0)
    img.ticketBig     = nvgCreateImage(vg, "image/UI_icon_ZMQ_1.png", 0)
    local stellarTicketPath = UrGachaConfig.UI.ticketIconPath or "image/UI_icon_ZMQ2_X.png"
    img.ticketBigStellar = nvgCreateImage(vg, stellarTicketPath, 0)
    if img.ticketBigStellar < 0 then
        img.ticketBigStellar = nvgCreateImage(vg, "image/UI_icon_ZMQ_2.png", 0)
    end
    img.diamondBg     = nvgCreateImage(vg, "image/UI_icon_ZBBJ_5.png", 0)
    img.ticketQBg     = nvgCreateImage(vg, "image/UI_icon_ZBBJ_5.png", 0)
    print("[TavernPopups] init OK")
end

--- 打开历史招募弹窗
function M.openHistory()
    openPopup("history")
    print("[TavernPopups] 打开历史招募弹窗")
end

--- 打开招募说明弹窗
function M.openInfo()
    openPopup("info")
    print("[TavernPopups] 打开招募说明弹窗")
end

--- 检查招募券是否足够，不足时弹出确认框
---@param count number 1 或 10
---@return boolean canProceed 是否可以直接执行招募
function M.checkAndShowConfirm(count)
    local poolId = getSelectedPoolId and getSelectedPoolId() or "standard"
    local isStellar = poolId == UrGachaConfig.POOL_ID or poolId == "stellar"
    local costCfg = isStellar and UrGachaConfig.Cost or GachaConfig.Cost
    local ticketCost = (count == 10) and costCfg.TEN_TICKET or costCfg.SINGLE_TICKET
    local tickets = isStellar and GameState.getStellarRecruitTicket() or GameState.getRecruitTicket()

    if tickets >= ticketCost then
        return true
    end

    local shortfall = ticketCost - tickets

    local diamondPerTicket = costCfg.SINGLE_DIAMOND
    local diamondCost = shortfall * diamondPerTicket

    openPopup("confirm")
    popupState.confirmCount       = count
    popupState.confirmNeedTickets = shortfall
    popupState.confirmDiamondCost = diamondCost
    popupState.confirmIsStellar   = isStellar
    print("[TavernPopups] 招募券不足，弹出确认框: 需" .. shortfall .. "张券, 花费" .. diamondCost .. "钻石")
    return false
end

--- 是否有弹窗正在阻塞输入
---@return boolean
function M.isBlocking()
    return popupState.popupClosing
        or popupState.historyVisible
        or popupState.infoVisible
        or popupState.confirmVisible
end

--- 显示飘字提示
function M.showFloatText(text, x, y)
    popupState.floatText = text
    popupState.floatTextX = x or CF.BUY_CX
    popupState.floatTextY = y or CF.BUY_CY
    popupState.floatTextTime = time.elapsedTime
end

--- 清除卡池说明缓存（卡池配置变更后调用以重建显示）
function M.clearPoolCache()
    _infoPoolLines = {}
end

--- 重置所有弹窗状态（酒馆关闭时调用）
function M.resetAll()
    popupState.historyVisible = false
    popupState.historyScrollY = 0
    popupState.historyTouchY = nil
    popupState.infoVisible = false
    popupState.infoScrollY = 0
    popupState.infoTouchY = nil
    popupState.confirmVisible = false
    popupState.popupClosing = false
    popupState.popupCloseTarget = nil
    popupState.floatText = nil
end

-- ======================== 绘制 ========================

--- 绘制所有弹窗（在主页面 draw 最后调用）
function M.drawAll(vg)
    -- ============ 确认框 ============
    if popupState.confirmVisible then
        local pScale, pAlpha = getPopupAnim()

        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(CF.MASK_A * pAlpha)))
        nvgFill(vg)

        nvgSave(vg)
        nvgTranslate(vg, DESIGN_W * 0.5, DESIGN_H * 0.5)
        nvgScale(vg, pScale, pScale)
        nvgTranslate(vg, -DESIGN_W * 0.5, -DESIGN_H * 0.5)
        nvgGlobalAlpha(vg, pAlpha)

        drawImageCentered(vg, img.confirmBg, CF.CX, CF.CY, CF.W, CF.H, 1.0)

        drawTextStroke(vg,
            CF.TITLE_CX, CF.TITLE_CY,
            "招募券不足",
            CF.TITLE_SIZE,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255,
            CF.TITLE_STROKE_W,
            { strokeColor = { 0x59, 0x32, 0x19 } }
        )

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, CF.SUB_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(CF.SUB_R, CF.SUB_G, CF.SUB_B, 255))
        nvgText(vg, CF.SUB_CX, CF.SUB_CY, "是否使用钻石快速购买", nil)

        drawRoundedRectCentered(vg,
            CF.CONTENT_CX, CF.CONTENT_CY,
            CF.CONTENT_W, CF.CONTENT_H,
            12,
            0, 0, 0, CF.CONTENT_A)

        drawImageCentered(vg, img.confirmArrow, CF.ARROW_CX, CF.ARROW_CY, CF.ARROW_W, CF.ARROW_H, 1.0)
        drawImageCentered(vg, img.diamondBg, CF.DIAMOND_CX, CF.DIAMOND_CY, CF.DIAMOND_W, CF.DIAMOND_H, 1.0)
        drawImageCentered(vg, img.diamondBig, CF.DIAMOND_CX, CF.DIAMOND_CY, CF.DIAMOND_W, CF.DIAMOND_H, 1.0)
        drawImageCentered(vg, img.ticketQBg, CF.TICKET_CX, CF.TICKET_CY, CF.TICKET_W, CF.TICKET_H, 1.0)
        local confirmTicketIcon = img.ticketBig
        if popupState.confirmIsStellar and img.ticketBigStellar >= 0 then
            confirmTicketIcon = img.ticketBigStellar
        end
        drawImageCentered(vg, confirmTicketIcon, CF.TICKET_CX, CF.TICKET_CY, CF.TICKET_W, CF.TICKET_H, 1.0)

        local diamondEnough = GameState.getGems() >= popupState.confirmDiamondCost
        local dBadgeR, dBadgeG, dBadgeB = 255, 255, 255
        if not diamondEnough then
            dBadgeR, dBadgeG, dBadgeB = 255, 50, 50
        end
        drawTextStroke(vg,
            CF.DIAMOND_CX + CF.BADGE_OX,
            CF.DIAMOND_CY + CF.BADGE_OY,
            tostring(popupState.confirmDiamondCost),
            CF.BADGE_SIZE,
            NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
            dBadgeR, dBadgeG, dBadgeB,
            CF.BADGE_STROKE_W,
            { strokeColor = { 0, 0, 0 } }
        )

        drawTextStroke(vg,
            CF.TICKET_CX + CF.BADGE_OX,
            CF.TICKET_CY + CF.BADGE_OY,
            tostring(popupState.confirmNeedTickets),
            CF.BADGE_SIZE,
            NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
            255, 255, 255,
            CF.BADGE_STROKE_W,
            { strokeColor = { 0, 0, 0 } }
        )

        local _bfBuy = BF.begin(vg, "tp_confirm", CF.BUY_CX, CF.BUY_CY, CF.BUY_W, CF.BUY_H)
        drawNineSlice(vg, img.confirmBtnBuy,
            CF.BUY_CX - CF.BUY_W * 0.5, CF.BUY_CY - CF.BUY_H * 0.5,
            CF.BUY_W, CF.BUY_H,
            CF.BTN_INSET_TOP, CF.BTN_INSET_RIGHT, CF.BTN_INSET_BOTTOM, CF.BTN_INSET_LEFT)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, CF.BUY_TEXT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(CF.BUY_TEXT_R, CF.BUY_TEXT_G, CF.BUY_TEXT_B, 255))
        nvgText(vg, CF.BUY_CX, CF.BUY_CY, "购买", nil)
        BF.finish(vg, _bfBuy)

        nvgRestore(vg)
    end

    -- ============ 招募说明弹窗 ============
    if popupState.infoVisible then
        local pScale, pAlpha = getPopupAnim()

        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(INFO.MASK_A * pAlpha)))
        nvgFill(vg)

        nvgSave(vg)
        nvgTranslate(vg, DESIGN_W * 0.5, DESIGN_H * 0.5)
        nvgScale(vg, pScale, pScale)
        nvgTranslate(vg, -DESIGN_W * 0.5, -DESIGN_H * 0.5)
        nvgGlobalAlpha(vg, pAlpha)

        drawNineSlice(vg, img.confirmBg,
            INFO.CX - INFO.W * 0.5, INFO.CY - INFO.H * 0.5,
            INFO.W, INFO.H,
            INFO.INSET_TOP, INFO.INSET_RIGHT, INFO.INSET_BOTTOM, INFO.INSET_LEFT)

        drawTextStroke(vg,
            INFO.TITLE_CX, INFO.TITLE_CY,
            "招募说明",
            INFO.TITLE_SIZE,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255,
            INFO.TITLE_STROKE_W,
            { strokeColor = { 0x59, 0x32, 0x19 } }
        )

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, INFO.SUB_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(INFO.RULE_TEXT_R, INFO.RULE_TEXT_G, INFO.RULE_TEXT_B, 255))
        local infoPoolId = getActivePoolId()
        local subTitle = isStellarPoolId(infoPoolId) and "星辉招募卡池" or "常规招募卡池"
        nvgText(vg, INFO.SUB_CX, INFO.SUB_CY, subTitle, nil)

        drawRoundedRectCentered(vg,
            INFO.RULE_BG_CX, INFO.RULE_BG_CY,
            INFO.RULE_BG_W, INFO.RULE_BG_H,
            INFO.RULE_BG_R,
            0, 0, 0, INFO.RULE_BG_A)

        drawInfoRuleText(vg, infoPoolId)

        drawRoundedRectCentered(vg,
            INFO.POOL_BG_CX, INFO.POOL_BG_CY,
            INFO.POOL_BG_W, INFO.POOL_BG_H,
            INFO.POOL_BG_R,
            0, 0, 0, INFO.POOL_BG_A)

        drawInfoPoolContent(vg, infoPoolId)

        nvgRestore(vg)
    end

    -- ============ 历史招募弹窗 ============
    if popupState.historyVisible then
        local pScale, pAlpha = getPopupAnim()

        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(HIST.MASK_A * pAlpha)))
        nvgFill(vg)

        nvgSave(vg)
        nvgTranslate(vg, DESIGN_W * 0.5, DESIGN_H * 0.5)
        nvgScale(vg, pScale, pScale)
        nvgTranslate(vg, -DESIGN_W * 0.5, -DESIGN_H * 0.5)
        nvgGlobalAlpha(vg, pAlpha)

        drawNineSlice(vg, img.confirmBg,
            HIST.CX - HIST.W * 0.5, HIST.CY - HIST.H * 0.5,
            HIST.W, HIST.H,
            HIST.INSET_TOP, HIST.INSET_RIGHT, HIST.INSET_BOTTOM, HIST.INSET_LEFT)

        drawTextStroke(vg,
            HIST.TITLE_CX, HIST.TITLE_CY,
            isStellarPoolId(getActivePoolId()) and "星辉招募历史" or "常规招募历史",
            HIST.TITLE_SIZE,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255,
            HIST.TITLE_STROKE_W,
            { strokeColor = { 0x59, 0x32, 0x19 } }
        )

        drawRoundedRectCentered(vg,
            HIST.LABEL_BG_CX, HIST.LABEL_BG_CY,
            HIST.LABEL_BG_W, HIST.LABEL_BG_H,
            HIST.LABEL_BG_R,
            0, 0, 0, HIST.LABEL_BG_A)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, HIST.LABEL_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(HIST.LABEL_R, HIST.LABEL_G, HIST.LABEL_B, 255))
        nvgText(vg, HIST.LABEL_GET_X, HIST.LABEL_GET_Y, "获得", nil)
        nvgText(vg, HIST.LABEL_TIME_X, HIST.LABEL_TIME_Y, "时间", nil)

        drawRoundedRectCentered(vg,
            HIST.LIST_BG_CX, HIST.LIST_BG_CY,
            HIST.LIST_BG_W, HIST.LIST_BG_H,
            HIST.LIST_BG_R,
            0, 0, 0, HIST.LIST_BG_A)

        -- 列表内容（可滚动）
        local listX = HIST.LIST_BG_CX - HIST.LIST_BG_W * 0.5
        local listY = HIST.LIST_BG_CY - HIST.LIST_BG_H * 0.5
        local listW = HIST.LIST_BG_W
        local listH = HIST.LIST_BG_H

        local activeHistory = getActiveHistoryList()
        local totalH = HIST.LIST_PAD_TOP + #activeHistory * HIST.LINE_H
        local maxScroll = math.max(0, totalH - listH)
        popupState.historyScrollY = math.max(0, math.min(maxScroll, popupState.historyScrollY))

        nvgSave(vg)
        nvgScissor(vg, listX, listY, listW, listH)

        local isStellarHist = isStellarPoolId(getActivePoolId())
        local colorMap = isStellarHist and STELLAR_QUALITY_COLOR or QUALITY_COLOR

        for i, rec in ipairs(activeHistory) do
            local ly = listY + HIST.LIST_PAD_TOP + (i - 1) * HIST.LINE_H - popupState.historyScrollY
            if ly + HIST.LINE_H > listY and ly < listY + listH then
                local clr = colorMap[rec.quality] or colorMap[0] or colorMap[1]
                local segs = { { text = rec.name, r = clr[1], g = clr[2], b = clr[3] } }
                drawColorSegments(vg, HIST.ITEM_X, ly, segs, HIST.ITEM_SIZE,
                    HIST.STROKE_R, HIST.STROKE_G, HIST.STROKE_B, HIST.STROKE_W)

                local timeSegs = { { text = rec.time, r = 255, g = 255, b = 255 } }
                drawColorSegments(vg, HIST.TIME_X, ly, timeSegs, HIST.TIME_SIZE,
                    HIST.STROKE_R, HIST.STROKE_G, HIST.STROKE_B, HIST.STROKE_W)
            end
        end

        nvgResetScissor(vg)
        nvgRestore(vg)

        nvgRestore(vg)
    end

    -- ============ 飘字提示 ============
    if popupState.floatText then
        local FLOAT_DURATION = 1.5
        local FLOAT_DIST     = 100
        local elapsed = time.elapsedTime - popupState.floatTextTime
        if elapsed >= FLOAT_DURATION then
            popupState.floatText = nil
        else
            local t = elapsed / FLOAT_DURATION
            local alpha = 1.0 - t
            local offsetY = -FLOAT_DIST * t
            drawTextStroke(vg, popupState.floatTextX, popupState.floatTextY + offsetY,
                popupState.floatText,
                40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 80, 80, 6,
                { alpha = alpha })
        end
    end
end

-- ======================== 输入处理 ========================

--- 处理弹窗输入（在主页面 handleInput 中优先调用）
---@return boolean consumed 是否消费了输入
function M.handleInput(dx, dy)
    -- 关闭动画播放中，吞掉所有输入
    if popupState.popupClosing then return true end

    -- 同帧保护：防止 openPopup() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - popupState.popupAnimTime < 0.05 then return true end

    -- 历史招募弹窗
    if popupState.historyVisible then
        if not hitTest(dx, dy, HIST.CX, HIST.CY, HIST.W, HIST.H) then
            closePopup("history")
            print("[TavernPopups] 关闭历史招募弹窗")
        end
        return true
    end

    -- 招募说明弹窗
    if popupState.infoVisible then
        if not hitTest(dx, dy, INFO.CX, INFO.CY, INFO.W, INFO.H) then
            closePopup("info")
            print("[TavernPopups] 关闭招募说明弹窗")
        end
        return true
    end

    -- 确认框
    if popupState.confirmVisible then
        -- 购买按钮
        if hitTest(dx, dy, CF.BUY_CX, CF.BUY_CY, CF.BUY_W, CF.BUY_H) then
            BF.trigger("tp_confirm")
            if GameState.getGems() < popupState.confirmDiamondCost then
                M.showFloatText("资源不足", CF.BUY_CX, CF.BUY_CY)
                print("[TavernPopups] 钻石不足，无法购买: 需要" .. popupState.confirmDiamondCost .. " 拥有" .. GameState.getGems())
                return true
            end
            print("[TavernPopups] 确认购买招募券，数量=" .. popupState.confirmNeedTickets .. " 花费钻石=" .. popupState.confirmDiamondCost)
            popupState.confirmVisible = false
            if doRecruitDirect then
                doRecruitDirect(popupState.confirmCount, "diamond")
            end
            return true
        end
        -- 点击外部关闭
        if not hitTest(dx, dy, CF.CX, CF.CY, CF.W, CF.H) then
            closePopup("confirm")
            print("[TavernPopups] 关闭确认框")
        end
        return true
    end

    return false
end

-- ======================== 拖拽/滚动 ========================

function M.handleDragBegin(dx, dy)
    if popupState.historyVisible then
        popupState.historyTouchY = dy
    elseif popupState.infoVisible then
        popupState.infoTouchY = dy
    end
end

function M.handleDragMove(dx, dy)
    if popupState.historyVisible and popupState.historyTouchY then
        local delta = popupState.historyTouchY - dy
        popupState.historyScrollY = popupState.historyScrollY + delta
        popupState.historyTouchY = dy
    elseif popupState.infoVisible and popupState.infoTouchY then
        local delta = popupState.infoTouchY - dy
        popupState.infoScrollY = popupState.infoScrollY + delta
        popupState.infoTouchY = dy
    end
end

function M.handleDragEnd(dx, dy)
    popupState.historyTouchY = nil
    popupState.infoTouchY = nil
end

function M.handleScroll(wheel)
    if popupState.historyVisible then
        popupState.historyScrollY = popupState.historyScrollY - wheel * 40
    elseif popupState.infoVisible then
        popupState.infoScrollY = popupState.infoScrollY - wheel * 40
    end
end

-- ======================== 更新 ========================

--- 每帧更新（弹窗关闭动画检测）
function M.update(dt)
    if popupState.popupClosing then
        local _, _, done = getPopupAnim()
        if done then
            local target = popupState.popupCloseTarget
            popupState.popupClosing = false
            popupState.popupCloseTarget = nil
            if target == "history" then
                popupState.historyVisible = false
                popupState.historyScrollY = 0
                popupState.historyTouchY = nil
            elseif target == "info" then
                popupState.infoVisible = false
                popupState.infoScrollY = 0
                popupState.infoTouchY = nil
            elseif target == "confirm" then
                popupState.confirmVisible = false
            end
        end
    end
end

return M
