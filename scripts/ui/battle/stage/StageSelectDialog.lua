-- ============================================================================
-- StageSelectDialog - 主线选关弹窗（v2 章节两栏版）
-- 布局（参考暗黑地牢选关图）:
--   左栏: 章节战斗背景圆角卡片 + 章名/章号，超出可视区上下滚动
--   中栏: 该章关卡竖排行 + 敌人卡面
--         当前关金框 / Boss 关红字 / 终焉神殿独立章组
--   点击空白关闭
-- 入口：战斗界面 HUD「选关」按钮（与扫荡/统计同套图标按钮）
-- ============================================================================

local GameConfig        = require("config.GameConfig")
local SC                = require("config.StageConfig")
local MC                = require("config.MonsterConfig")
local BattleEnemySpawn  = require("ui.battle.stage.BattleEnemySpawn")
local DrawUtil          = require("core.DrawUtil")
local DarkIcon          = require("core.DarkIcon")
local GameState         = require("core.GameState")
local I18n              = require("core.I18n")
local BF                = require("systems.ButtonFeedback")
local ResourceList      = require("ui.battle.stage.StageSelectResources")
local ExpeditionOverview = require("ui.battle.stage.ExpeditionOverview")
local ET                = require("config.ExpTable")
local RewardPreview     = require("ui.battle.stage.StageSelectRewardPreview")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local drawImageCover    = DrawUtil.drawImageCover

-- 章名先翻译再测量；长专名最多两行，避免挤入相邻列或无限缩小字号。
local titleLayoutCache = {}
local titleLayoutKeys = {}
local TITLE_CACHE_LIMIT = 256
local function titleLines(vg, source, width, fontSize)
    local caption = I18n.lookup(source)
    local key = I18n.get() .. "\0" .. caption .. "\0" .. width .. "\0" .. fontSize
    local cached = titleLayoutCache[key]
    if cached then return cached end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    local lines, line = {}, ""
    local tokens = {}
    if I18n.get() == "en" then
        for token in caption:gmatch("%S+%s*") do tokens[#tokens + 1] = token end
    else
        for _, code in utf8.codes(caption) do tokens[#tokens + 1] = utf8.char(code) end
    end
    for _, token in ipairs(tokens) do
        local candidate = line .. token
        if line ~= "" and nvgTextBounds(vg, 0, 0, candidate) > width then
            lines[#lines + 1] = line:gsub("%s+$", "")
            line = token
        else
            line = candidate
        end
    end
    if line ~= "" then lines[#lines + 1] = line:gsub("%s+$", "") end
    if #lines == 0 then lines[1] = caption end
    titleLayoutCache[key] = lines
    titleLayoutKeys[#titleLayoutKeys + 1] = key
    if #titleLayoutKeys > TITLE_CACHE_LIMIT then
        local oldest = table.remove(titleLayoutKeys, 1)
        if oldest then titleLayoutCache[oldest] = nil end
    end
    return lines
end

local function drawFittedTitle(vg, x, y, source, width, fontSize, maxLines, align, r, g, b, stroke, opts)
    local size = fontSize
    local lines = titleLines(vg, source, width, size)
    local function tooLarge()
        if #lines > maxLines then return true end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, size)
        for _, line in ipairs(lines) do
            if nvgTextBounds(vg, 0, 0, line) > width then return true end
        end
        return false
    end
    while tooLarge() and size > 18 do
        size = size - 1
        lines = titleLines(vg, source, width, size)
    end
    local lineHeight = size + 2
    local topY = y - (#lines - 1) * lineHeight * 0.5
    for index, line in ipairs(lines) do
        drawTextStroke(vg, x, topY + (index - 1) * lineHeight, line, size,
            align, r, g, b, stroke, opts)
    end
end

local StageSelectDialog = {}
local onDungeonSelect = nil ---@type fun(dungeonId: string, teamIdx: number, floor: number): boolean|nil
local TAB_Y, TAB_W, TAB_H = 782, 90, 46
local MAIN_TAB_X, DUNGEON_TAB_X = 150, 250

function StageSelectDialog.setOnDungeonSelect(callback)
    onDungeonSelect = callback
end

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- 入口按钮（设计坐标，与扫荡/统计同一套尺寸）
local BTN_CX = 659
local BTN_CY = 2115
local BTN_W  = 130
local BTN_H  = 144
local ICON_W = 130
local ICON_H = 144

local D = {
    OVL_A   = 128,

    BG_CX   = 540,  BG_CY  = 1195,
    BG_W    = 950,  BG_H   = 1117,
    -- 九宫格边距必须完整包住源图(827x569)四角铜铆钉(铆钉延伸至 ~x68 / ~y500)，
    -- 否则铆钉被切进中块随面板拉伸变形
    BG_IT   = 180,  BG_IR  = 72,  BG_IB = 72,  BG_IL = 72,

    TT_Y    = 732,  -- 标题下移半行（章节行高 84 的一半；原 690）
    TT_FONT = 50,  TT_SW = 6,
    TT_SR   = 0x00, TT_SG  = 0x00, TT_SB = 0x00,

    -- 左栏: 章节列表
    CH_X      = 105,     -- 左栏左缘
    CH_W      = 190,
    CH_BTN_H  = 84,
    CH_GAP    = 10,
    CH_Y0     = 876,     -- 第一个章节按钮顶边（主线/副本导航整体下移，留出更舒展的顶部间距）
    CH_VISIBLE = 7,      -- 可视章节数（下移后仍留在弹窗内，超出滚动）

    -- 中栏：关卡竖排（5-1 在上，5-5 在下），每行直接展示敌人卡面
    MID_X     = 315,
    MID_W     = 580,
    ROW_Y0    = 790,     -- 第一行顶边（整体下移 20% 行高 ≈34；原 756）
    ROW_H     = 168,     -- 一行高度
    ROW_GAP   = 10,
    CARD_W    = 92,      -- 敌人卡面宽
    CARD_H    = 104,     -- 敌人卡面高
    CARD_GAP  = 8,
    CARD_X    = 455,     -- 卡面区左缘（标签右侧）

}

-- 绘制、裁剪、滚动、命中共用布局；主线/神殿参数原值不动。
---@class StageSelectRowLayout
---@field rowHeight number
---@field step number
---@field cardWidth number
---@field cardHeight number
---@field cardGap number
---@field cardCenterY number
---@field cardViewportHeight number
---@field numberOffset number
---@field scrollBarY number
---@field scrollHintY number
---@field labelY number
---@field statusY number
---@field powerY number
---@field compact boolean
local MAIN_ROW_LAYOUT = {
    rowHeight = D.ROW_H, step = D.ROW_H + D.ROW_GAP,
    cardWidth = D.CARD_W, cardHeight = D.CARD_H, cardGap = D.CARD_GAP,
    cardCenterY = 62, cardViewportHeight = D.ROW_H - 12, numberOffset = 12,
    scrollBarY = D.ROW_H - 6, scrollHintY = D.ROW_H - 22,
    labelY = 34, statusY = D.ROW_H - 34, powerY = 84, compact = false,
} ---@type StageSelectRowLayout
local RESOURCE_ROW_LAYOUT = {
    rowHeight = 140, step = 150, cardWidth = 76, cardHeight = 72, cardGap = 8,
    cardCenterY = 44, cardViewportHeight = 88, numberOffset = 7,
    scrollBarY = 99, scrollHintY = 94, labelY = 28, statusY = 78, powerY = 53, compact = true,
} ---@type StageSelectRowLayout
local ROW_VIEWPORT_HEIGHT = 5 * (D.ROW_H + D.ROW_GAP) -- 固定890，紧凑副本增加可见行而非缩视窗。
local REWARD_BAND_Y, REWARD_BAND_HEIGHT = 104, 34

---@param group StageSelectGroup|nil
---@return StageSelectRowLayout
local function rowLayout(group)
    return group and group.resourceDungeonId and RESOURCE_ROW_LAYOUT or MAIN_ROW_LAYOUT
end

local ANIM_OPEN_DUR = 0.18

-- 章节横幅色调（8 色循环，参考图每章一色的效果）
local CH_HUES = {
    { 0x3e, 0x5a, 0x40 }, { 0x6b, 0x46, 0x2f }, { 0x33, 0x4a, 0x63 }, { 0x2f, 0x5a, 0x5c },
    { 0x4a, 0x3f, 0x63 }, { 0x5a, 0x30, 0x33 }, { 0x3d, 0x53, 0x3a }, { 0x59, 0x4d, 0x2e },
}

local imgBtn, imgBg, imgAct, imgLock = -1, -1, -1, -1
local imageVg = nil ---@type any
local imageBatch = {} -- 每次init独立身份；合作式加载让出后，旧批次不能写回新context。
local imagesReady = false
local state = {
    view      = "selector",
    fromOverview = false,
    targetTeam = 1,
    section   = "main",
    sectionPositions = {}, ---@type table<string, table> 各分类保留选中章与滚动位置
    open      = false,
    openTime  = 0,
    selKey    = nil,   -- 选中章节 key（chapter number 或 "T<神殿id>"=单难度终焉组）
    chScroll  = 0,     -- 左栏滚动起点（0-based）
    chDragY   = nil,   -- 左栏按下位置
    chDragScroll = 0, -- 按下时滚动起点
    chDragMoved = false,
    rowScroll = {},        ---@type table<string, number> 各组关卡列表的纵向像素偏移
    rowDragKey = nil,      ---@type string|nil 整个右视窗（含标签/空白）捕获纵拖
    rowDragLastY = 0,
    cardScroll = {},       ---@type table<number, number> 各关敌人列表独立偏移
    cardDragId = nil,      ---@type number|nil 当前捕获的关卡
    cardDragX = 0,
    cardDragY = 0,
    cardDragLastX = 0,
    cardDragScroll = 0,
    cardDragHorizontal = false,
    cardDragMoved = false, -- 锁存整次手势，拖回起点也不能误切关

    -- [选关 v3] 全链数据缓存（ensureCache 维护, 随 maxStage 变化重建）
    cacheGroups   = nil,  ---@type table[] 章节组列表
    cacheOrder    = nil,  ---@type table<number, number> id→链序
    cacheMaxStage = nil,  ---@type number 构建时的 maxStageId
    cacheMaxOrder = nil,  ---@type number 解锁基准链序
}

local function hitTestRect(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

local function getAnimScale()
    if not state.open then return 0 end
    local t = math.min((time.elapsedTime - state.openTime) / ANIM_OPEN_DUR, 1.0)
    return t * (1.0 + 0.08 * math.sin(t * math.pi))
end

--- 沿官方关卡链收集全链（不随进度截断，终焉神殿后进入下一难度）
--- 返回 ids 与链序表 order[id]=序号
local function collectAllIds()
    local ids = {}
    ---@type table<number, number>
    local order = {}
    local cur = SC.NORMAL_FIRST_STAGE or 101
    local guard = 0
    while cur and guard < 2000 do
        guard = guard + 1
        if order[cur] then break end
        if ResourceList.getStageEntry(cur) then
            ids[#ids + 1] = cur
            order[cur] = #ids
        end
        local nxt = SC.getNextStageId(cur)
        if not nxt and SC.isTerminalTemple(cur) then
            nxt = SC.getReincarnationTarget(SC.getDifficulty(cur))
        end
        if not nxt then break end
        cur = nxt
    end
    return ids, order
end

--- 章节组：{{ key=chapter|"T<神殿id>", name=, subLabel=, ids={} } 按进度顺序}
--- [单难度终焉] 终焉神殿不再合并成一个 "T" 组，每座神殿独立成组，
--- 沿关卡链自然追加在对应难度第 23 章之后（如困难 23 章 → 困难终焉 → 噩梦 1 章）
local function collectChapterGroups()
    local ids, order = collectAllIds()
    local groups = {}
    ---@type table<any, number>
    local indexOf = {}
    for _, id in ipairs(ids) do
        local key, name, subLabel
        if SC.isTerminalTemple(id) then
            key = "T" .. tostring(id)
            name = "终焉"
            subLabel = SC.getDifficultyDisplayName(SC.getDifficulty(id))
        else
            local chapter = math.floor(id / 100)
            key = chapter
            name = SC.getChapterName(chapter)
            -- 绝对章号（困难从 24 章起显示 24 章，而非相对 1 章）
            subLabel = tostring(chapter) .. " 章"
        end
        local gi = indexOf[key]
        if not gi then
            gi = #groups + 1
            indexOf[key] = gi
            groups[gi] = { key = key, name = name, subLabel = subLabel, ids = {} }
        end
        local g = groups[gi]
        g.ids[#g.ids + 1] = id
    end
    return groups, order
end

--- 全链总关数
local function ids_of(groups)
    local n = 0
    for _, g in ipairs(groups) do n = n + #g.ids end
    return n
end

--- 弹窗数据缓存：全链列表随 maxStage 变化重建
local function ensureCache()
    local BS = require("ui.battle.scene.BattleScene")
    local maxStage = BS.getMaxStageId()
    if not maxStage or maxStage < 1 then
        maxStage = SC.NORMAL_FIRST_STAGE or 101
    end
    local nextId = SC.getNextStageId(maxStage)
    local cleared = BS.getClearedStages()
    local terminalUnlocked = nextId and SC.isTerminalTemple(nextId)
        and (cleared[maxStage] or cleared[tostring(maxStage)])
    if not state.cacheGroups or state.cacheMaxStage ~= maxStage
        or state.cacheTerminalUnlocked ~= terminalUnlocked then
        local groups, order = collectChapterGroups()
        state.cacheGroups = groups
        state.cacheOrder = order
        state.cacheMaxStage = maxStage
        state.cacheTerminalUnlocked = terminalUnlocked
        state.cacheMaxOrder = (maxStage and order[maxStage]) or ids_of(groups)
        if terminalUnlocked then
            state.cacheMaxOrder = order[nextId] or state.cacheMaxOrder
        end
    end
    return state.cacheGroups, state.cacheMaxOrder
end

local function currentGroups()
    if state.section == "dungeon" then return ResourceList.getGroups(), nil end
    return ensureCache()
end

-- 资源/通天塔进度是副本独立账本，不能用主线链序 cacheMaxOrder 代替。
local function stageLocked(id, maxOrder, battleData, dungeonData)
    if ResourceList.isTowerStage(id) or SC.isResourceStage(id) then
        return not ResourceList.isStageUnlocked(id, battleData, dungeonData)
    end
    local ord = state.cacheOrder and state.cacheOrder[id]
    return ord == nil or maxOrder == nil or ord > maxOrder
end

local function chapterHue(key, hueIndex)
    -- 终焉组 key 形如 "T999"，提取神殿 id 参与取色，让各难度终焉色调互异
    local n = hueIndex or key
    if type(n) == "string" then
        n = tonumber(n:match("^T(%d+)$")) or 23
    end
    return CH_HUES[((n - 1) % #CH_HUES) + 1]
end

--- 选关显示的章号：绝对章号（困难第 24 章显示 24-1，与普通 1-23 连续）；
--- 普通难度相对章与绝对章相同，显示不变
---@param id number
---@return number
local function displayChapter(id)
    local entry = ResourceList.getStageEntry(id)
    return entry and entry.displayChapter or math.floor(id / 100)
end

local function shortStageLabel(id)
    if SC.isTerminalTemple(id) then
        local entry = ResourceList.getStageEntry(id)
        return entry and entry.name or "终焉神殿"
    end
    local entry = ResourceList.getStageEntry(id)
    if not entry then return tostring(id) end
    local rel = displayChapter(id)
    return string.format("%d-%d", rel, entry.stage)
end

--- 敌人卡面句柄缓存（懒加载，键=怪物 id）
---@type table<number, integer>
local monsterCards = {}

--- 取怪物卡面，失败不缓存，避免永久空白
---@param vg any
---@param monsterId number
---@return integer
local function ensureMonsterCard(vg, monsterId)
    local batch, cards = imageBatch, monsterCards
    local img = cards[monsterId]
    if img and img >= 0 then return img end
    local artId = require("config.MonsterConfig").getCardArtId(monsterId)
    local loaded = nvgCreateImage(vg, string.format("image/怪物卡牌/KP_GW_%d.png", artId), 0)
    ---@cast loaded integer|nil
    if imageBatch ~= batch or imageVg ~= vg or not imagesReady then return -1 end
    if loaded and loaded >= 0 then
        cards[monsterId] = loaded
        return loaded
    end
    cards[monsterId] = nil
    return -1
end

--- 一关实际出场的敌人 id：常规怪 + 首领 + 首通附加怪
---@class StageSelectEnemyCard
---@field id number
---@field count number
---@param entry table|nil
---@return StageSelectEnemyCard[]
local function stageMonsterCards(entry)
    local cards = {} ---@type StageSelectEnemyCard[]
    local counts = {} ---@type table<number, number>
    local seen = {} ---@type table<number, boolean>
    if not entry then return cards end
    if entry.tower then return cards end
    local total = entry.firstCount or entry.idleCount or 0
    local types = entry.monsters or {}
    local normalCount = total
    if entry.bossId and entry.bossId > 0 then
        normalCount = math.max(0, total - 1)
    end
    for i = 1, normalCount do
        local monsterId = types[((i - 1) % math.max(1, #types)) + 1]
        if monsterId then counts[monsterId] = (counts[monsterId] or 0) + 1 end
    end
    if entry.bossId and entry.bossId > 0 then
        counts[entry.bossId] = (counts[entry.bossId] or 0) + 1
    end
    local bonusIds = BattleEnemySpawn.getFirstClearBonusMonsterIds(entry)
    for _, monsterId in ipairs(bonusIds or {}) do
        counts[monsterId] = (counts[monsterId] or 0) + 1
    end
    local function push(monsterId)
        if monsterId and counts[monsterId] and not seen[monsterId] then
            seen[monsterId] = true
            cards[#cards + 1] = { id = monsterId, count = counts[monsterId] }
        end
    end
    for _, monsterId in ipairs(types) do push(monsterId) end
    push(entry.bossId)
    for _, monsterId in ipairs(bonusIds or {}) do push(monsterId) end
    return cards
end

local function currentStageId()
    local BattleTriPage = require("ui.battle.tri.BattleTriPage")
    return BattleTriPage.getTeamStageId(state.targetTeam or 1)
        or require("ui.battle.scene.BattleScene").getStageId()
end

local function selectedGroup(groups)
    for _, g in ipairs(groups) do
        if tostring(g.key) == tostring(state.selKey) then return g end
    end
    return groups[1]
end

local function chapterListBounds(groups)
    local top = D.CH_Y0
    local bottom = top + D.CH_VISIBLE * (D.CH_BTN_H + D.CH_GAP) - D.CH_GAP
    return top, bottom
end

-- 关卡视窗与纵向偏移是绘制/命中的唯一来源；主线五行及神殿说明保留原尺寸。
local function rowViewport()
    return D.MID_X, D.ROW_Y0 - 4, D.MID_W, ROW_VIEWPORT_HEIGHT
end

local function inRowViewport(x, y)
    local vx, vy, vw, vh = rowViewport()
    return x >= vx and x <= vx + vw and y >= vy and y < vy + vh
end

---@param group StageSelectGroup
local function rowScrollLimit(group)
    local _, _, _, height = rowViewport()
    return math.max(0, #group.ids * rowLayout(group).step - D.ROW_GAP + 4 - height)
end

local function setRowScroll(group, offset)
    local value = math.max(0, math.min(rowScrollLimit(group), offset))
    state.rowScroll[tostring(group.key)] = value
    return value
end

local function getRowScroll(group)
    return setRowScroll(group, state.rowScroll[tostring(group.key)] or 0)
end

---@param group StageSelectGroup
local function rowY(group, index, offset)
    return D.ROW_Y0 + (index - 1) * rowLayout(group).step - offset
end

---@param group StageSelectGroup
local function visibleRows(group)
    local offset = getRowScroll(group)
    local layout = rowLayout(group)
    local _, top, _, height = rowViewport()
    local first = math.max(1, math.floor((top - D.ROW_Y0 + offset - layout.rowHeight) / layout.step) + 2)
    local last = math.min(#group.ids, math.ceil((top + height - D.ROW_Y0 + offset) / layout.step))
    return first, last, offset
end

---@param group StageSelectGroup
---@param stageId number|nil
local function revealStage(group, stageId)
    local offset = getRowScroll(group)
    local displayId = ResourceList.getDisplayStageId(stageId)
    if not displayId then return end
    local layout = rowLayout(group)
    local _, top, _, height = rowViewport()
    for index, id in ipairs(group.ids) do
        if id == displayId then
            local y = rowY(group, index, offset)
            if y < top then offset = offset + y - top
            elseif y + layout.rowHeight > top + height then
                offset = offset + y + layout.rowHeight - top - height
            end
            setRowScroll(group, offset)
            return
        end
    end
end

local function groupTarget(group)
    return group.isTower and ResourceList.getCurrentTowerStageId()
        or ResourceList.getDisplayStageId(currentStageId())
end

---@param group StageSelectGroup|nil
local function rowAt(group, x, y)
    if not group or not inRowViewport(x, y) then return nil end
    local offset = getRowScroll(group)
    local layout = rowLayout(group)
    local index = math.floor((y - D.ROW_Y0 + offset) / layout.step) + 1
    local id = group.ids[index]
    local top = rowY(group, index, offset)
    if id and y >= top and y <= top + layout.rowHeight then return id, top end
    return nil
end

-- 标签区 | 敌人视口 [卡面 + 名称 + xN] | 行右缘
--         CARD_X=455 <---------------> MID_X+MID_W-4=891
-- 紧凑行敌人视口只覆盖y+6..94；奖励带y+104..138不捕获横拖。
---@param group StageSelectGroup|nil
local function cardViewport(group, y)
    return D.CARD_X, y + 6, D.MID_X + D.MID_W - D.CARD_X - 4, rowLayout(group).cardViewportHeight
end

---@param group StageSelectGroup|nil
---@param cards StageSelectEnemyCard[]
local function cardScrollLimit(group, cards)
    local _, _, width = cardViewport(group, 0)
    local layout = rowLayout(group)
    -- 两端各留2像素，包含居中描边和抗锯齿，首末卡边框不会被裁掉。
    local contentW = #cards * layout.cardWidth + math.max(0, #cards - 1) * layout.cardGap + 4
    return math.max(0, contentW - width), contentW
end

local function resetCardScroll()
    state.cardScroll = {}
    state.rowDragKey = nil
    state.cardDragId = nil
    state.cardDragHorizontal = false
    state.cardDragMoved = false
end

local function stageGroupKey(stageId)
    if not stageId then return nil end
    if ResourceList.isTowerStage(stageId) or SC.isResourceStage(stageId) then
        return ResourceList.getGroupKey(stageId)
    end
    if SC.isTerminalTemple(stageId) then return "T" .. tostring(stageId) end
    return math.floor(stageId / 100)
end

local function locateGroup(groups, key, targetId)
    local gi = 1
    for i, g in ipairs(groups) do
        if tostring(g.key) == tostring(key) then gi = i; break end
    end
    local group = groups[gi]
    state.selKey = group and group.key or nil
    state.chScroll = math.min(gi - 1, math.max(0, #groups - D.CH_VISIBLE))
    if group then
        if targetId or state.rowScroll[tostring(group.key)] == nil then
            revealStage(group, targetId or groupTarget(group))
        else
            getRowScroll(group)
        end
    end
end

local function switchSection(section)
    if state.section == section then return end
    state.sectionPositions[state.section] = { key = state.selKey, scroll = state.chScroll }
    state.section = section
    state.chDragY = nil
    state.chDragMoved = false
    resetCardScroll()
    local groups = currentGroups()
    local saved = state.sectionPositions[section]
    if saved then
        locateGroup(groups, saved.key)
        state.chScroll = math.max(0, math.min(saved.scroll or 0, #groups - D.CH_VISIBLE))
    else
        -- 首次切到副本定位首章；不要沿用主线数字章号造成跨分类错位。
        local stageId = currentStageId()
        local isDungeon = stageId and (ResourceList.isTowerStage(stageId) or SC.isResourceStage(stageId))
        local key = stageId and ((section == "dungeon") == not not isDungeon)
            and stageGroupKey(stageId) or nil
        locateGroup(groups, key, key and stageId or nil)
    end
end

local function cardRowAt(groups, x, y)
    local group = selectedGroup(groups)
    local id, y0 = rowAt(group, x, y)
    if not id then return nil end
    local vx, vy, vw, vh = cardViewport(group, y0)
    if x >= vx and x <= vx + vw and y >= vy and y <= vy + vh then
        return id, stageMonsterCards(ResourceList.getStageEntry(id))
    end
    return nil
end

local function drawTerminalGuide(vg, rowY, locked)
    local x, width = D.MID_X + 16, D.MID_W - 32
    local cursorY = rowY + D.ROW_H + 34
    local sources = {
        "最多三队一起上场，不必三队全部存活。",
        "同编号敌人跨队共享生命，击败全部三名敌人即可通关。",
        "不限时；全部参战队伍失守才失败。",
        "胜利进入下一难度，失败退回本难度最后一关。",
    }
    for index, source in ipairs(sources) do
        -- 开窗缩放很小时字体会被运行时最小像素字号放大；按稳定设计空间测宽，
        -- 不把动画首帧的窄折行缓存到后续帧。
        nvgSave(vg)
        nvgResetTransform(vg)
        local lines = titleLines(vg, source, width, 24)
        nvgRestore(vg)
        for _, line in ipairs(lines) do
            drawTextStroke(vg, x, cursorY, line, 24,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                index == 1 and 201 or 236, index == 1 and 151 or 226,
                index == 1 and 59 or 198, 2, { alpha = locked and 0.65 or 1 })
            cursorY = cursorY + 30
        end
        cursorY = cursorY + 14
    end
end

-- ======================== Public API ========================

-- 按资源路径缓存，跨难度复用背景；失败限频重试，不永久缓存缺图。
---@type table<string, integer>
local chapterBackgrounds = {}
---@type table<string, number>
local chapterBackgroundRetry = {}
local function ensureChapterBackground(vg, stageId, background)
    local batch = imageBatch
    local backgrounds, retries = chapterBackgrounds, chapterBackgroundRetry
    local path = background or SC.getBattleBackground(stageId)
    local image = backgrounds[path]
    if image and image >= 0 then return image end
    local now = time.elapsedTime
    if retries[path] and now < retries[path] then return -1 end
    local loaded = nvgCreateImage(vg, path, 0) or -1
    if imageBatch ~= batch or imageVg ~= vg or not imagesReady then return -1 end
    if loaded >= 0 then
        backgrounds[path] = loaded
        retries[path] = nil
        print("[StageSelectDialog] 章节背景已加载: " .. path)
    else
        retries[path] = now + 2
        print("[StageSelectDialog] 章节背景暂不可用，稍后重试: " .. path)
    end
    return loaded
end

local function drawChapterBackground(vg, stageId, x, y, hue, isSel, locked, background)
    local batch = imageBatch
    local image = ensureChapterBackground(vg, stageId, background)
    if imageBatch ~= batch or imageVg ~= vg or not imagesReady then return false end
    local srcW, srcH = 0, 0
    if image >= 0 then srcW, srcH = nvgImageSize(vg, image) end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, D.CH_W, D.CH_BTN_H, 12)
    if srcW and srcH and srcW > 0 and srcH > 0 then
        -- 等比cover并居中裁切，圆角路径保持现有卡片热区与动画变换。
        local scale = math.max(D.CH_W / srcW, D.CH_BTN_H / srcH)
        local w, h = srcW * scale, srcH * scale
        local imagePaint = nvgImagePattern(vg, x + (D.CH_W - w) * 0.5,
            y + (D.CH_BTN_H - h) * 0.5, w, h, 0, image, 1.0) --[[@as NVGpaint]]
        nvgFillPaint(vg, imagePaint)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, D.CH_W, D.CH_BTN_H, 12)
        nvgFillColor(vg, nvgRGBA(8, 8, 14, locked and 150 or (isSel and 65 or 90)))
    elseif isSel then
        nvgFillColor(vg, nvgRGBA(hue[1] + 24, hue[2] + 24, hue[3] + 18, 235))
    else
        nvgFillColor(vg, nvgRGBA(hue[1], hue[2], hue[3], 170))
    end
    nvgFill(vg)
    return true
end

-- 塔每波随机出怪，规则与整层奖励单独绘制，不套资源卡面布局。
local function drawTowerPreview(vg, entry, y, locked)
    local vx, vy, vw, vh = cardViewport(nil, y)
    nvgSave(vg)
    nvgIntersectScissor(vg, vx, vy, vw, vh)
    local color = locked and 149 or 230
    drawFittedTitle(vg, vx + vw * 0.5, y + 28,
        I18n.format("怪物 Lv.%d", entry.monsterLevel or 0), vw - 16, 28, 1,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 235, color, 194, 2)
    drawFittedTitle(vg, vx + vw * 0.5, y + 64, "每层10波，敌人随机生成", vw - 16, 24, 1,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, color, color, color, 2)
    drawFittedTitle(vg, vx + vw * 0.5, y + 98, "三队攻坚，共同推进", vw - 16, 24, 1,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 201, 151, 59, 2)
    nvgRestore(vg)
    RewardPreview.draw(vg, ResourceList.getRewardPreview(entry.id, entry),
        D.MID_X + 8, y + 130, D.MID_W - 16, 34, locked)
end

---@param vg any
function StageSelectDialog.init(vg)
    -- 同VG保留原init契约：释放章节缓存并重新请求静态图，奖励缓存也重置。
    -- 换VG时旧context可能已经销毁，只丢弃句柄，不能用新VG删除旧图片。
    if imageVg == vg then
        for _, image in pairs(chapterBackgrounds) do nvgDeleteImage(vg, image) end
    else
        monsterCards = {}
    end
    local batch = {}
    imageBatch, imageVg, imagesReady = batch, vg, false
    chapterBackgrounds, chapterBackgroundRetry = {}, {}
    titleLayoutCache, titleLayoutKeys = {}, {}
    imgBtn, imgBg, imgAct, imgLock = -1, -1, -1, -1
    RewardPreview.init(vg)
    local button = nvgCreateImage(vg, "image/通用图标/UI_ICON_XG.png", 0)
    if imageBatch ~= batch then return end
    -- 九宫格拉伸用法（950x1117），保留原图；整图拉伸用法（950x647）走 UI_TY_EJQRK_POP 副本
    local background = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TY_EJQRK.png", 0)
    if imageBatch ~= batch then return end
    local action = nvgCreateImage(vg, "image/按钮/UI_AN_HUANG.png", 0)
    if imageBatch ~= batch then return end
    local lock = nvgCreateImage(vg, "image/通用图标/UI_ICON_SUO.png", 0)
    if imageBatch ~= batch then return end
    -- nvgCreateImage可合作式yield；四图加载调用全部返回后才原子发布本批结果。
    imgBtn, imgBg, imgAct, imgLock, imagesReady = button, background, action, lock, true
    print(string.format("[StageSelectDialog] 主线行%d/资源行%d，视窗%d；副本显示战力、奖励与经验",
        MAIN_ROW_LAYOUT.rowHeight, RESOURCE_ROW_LAYOUT.rowHeight, ROW_VIEWPORT_HEIGHT))
    print(string.format("[StageSelectDialog] init OK; layout TAB_Y=%d TAB_W=%d TAB_H=%d "
        .. "MAIN_TAB_X=%d DUNGEON_TAB_X=%d CH_Y0=%d ROW_Y0=%d",
        TAB_Y, TAB_W, TAB_H, MAIN_TAB_X, DUNGEON_TAB_X, D.CH_Y0, D.ROW_Y0))
end

local function teamSelectionAllowed(teamIdx)
    local Tri = require("ui.battle.tri.BattleTriPage")
    local Nav = require("ui.hud.BottomNav")
    return not Tri.isTerminalRaidActive() and not Nav.isAllLocked() and not Nav.isTabLocked(3)
        and not require("ui.dungeon.DungeonBattleScene").isOpen()
        and not require("ui.tower.TowerBattleScene").isActive()
        and teamIdx >= 1 and teamIdx <= ET.getUnlockedTeamCount(require("runtime.ClientDispatcher").get("battle"))
end

local function locateTeam(teamIdx)
    state.view = "selector"
    state.openTime = time.elapsedTime
    state.chDragY = nil
    state.chDragMoved = false
    state.sectionPositions = {}
    resetCardScroll()
    state.targetTeam = teamIdx
    local curStage = currentStageId()
    local isDungeon = curStage and (ResourceList.isTowerStage(curStage) or SC.isResourceStage(curStage))
    state.section = isDungeon and "dungeon" or "main"
    local groups = currentGroups()
    locateGroup(groups, stageGroupKey(curStage), curStage)
end

---@param teamIdx number|nil 多队战斗行号；行 HUD 保持直接进入该队选关。
function StageSelectDialog.open(teamIdx)
    if state.open then return end
    local team = math.tointeger(tonumber(teamIdx) or 1)
    if not team or not teamSelectionAllowed(team) then return end
    state.open = true
    state.fromOverview = false
    locateTeam(team)
end

function StageSelectDialog.openOverview()
    if state.open or not teamSelectionAllowed(1) then return end
    state.open = true
    state.view = "overview"
    state.fromOverview = true
    state.openTime = time.elapsedTime
    state.chDragY, state.chDragMoved = nil, false
    resetCardScroll()
    ExpeditionOverview.open(require("ui.character.panel.CharacterPanel").getActiveTeamIdx())
end

function StageSelectDialog.showTeam(teamIdx)
    local team = math.tointeger(tonumber(teamIdx) or 0)
    if not state.open or not team or not teamSelectionAllowed(team) then return false end
    state.fromOverview = state.fromOverview or state.view == "overview"
    locateTeam(team)
    return true
end

function StageSelectDialog.backToOverview()
    if not state.open then return end
    state.view = "overview"
    state.fromOverview = true
    state.openTime = time.elapsedTime
    state.chDragY, state.chDragMoved = nil, false
    resetCardScroll()
    ExpeditionOverview.open(state.targetTeam)
end

-- 旧副本导航也只打开同一张关卡选择表，不再进入次数/挑战详情。
function StageSelectDialog.openDungeon(teamIdx, dungeonId)
    local team = math.tointeger(tonumber(teamIdx) or state.targetTeam or 1)
    if not team or not teamSelectionAllowed(team) then return end
    if not state.open then StageSelectDialog.open(team)
    else locateTeam(team) end
    switchSection("dungeon")
    local groups = currentGroups()
    local targetId = currentStageId()
    local key = stageGroupKey(targetId)
    if dungeonId == "babel_tower" then
        targetId = ResourceList.getCurrentTowerStageId()
        key = "R:babel_tower"
    elseif dungeonId then
        local DC = require("config.DungeonConfig")
        local dungeon = require("runtime.ClientDispatcher").get("dungeon") or {}
        if DC.isResourceDungeon(dungeonId) then
            local currentDungeon = targetId and DC.decodeStageId(targetId)
            if currentDungeon ~= dungeonId then
                local floor = math.min(DC.MAX_FLOOR[dungeonId],
                    DC.getHighestClearedFloor(dungeon[dungeonId], dungeonId) + 1)
                targetId = DC.getStageId(dungeonId, floor)
            end
            key = "R:" .. dungeonId
        end
    end
    locateGroup(groups, key, targetId)
    resetCardScroll()
end

--- 幂等恢复教程首层。只调整视图，不切关；稳定后不反复重开或重置动画。
---@return boolean
function StageSelectDialog.prepareTutorial()
    local key = "R:gold_mine"
    local changed = not state.open or state.section ~= "dungeon"
        or state.targetTeam ~= 1 or tostring(state.selKey) ~= key
        or state.chScroll ~= 0 or (state.rowScroll[key] or 0) ~= 0
    if not changed then return false end
    -- 恢复首层不能把已拖动的往返手势伪装成短点击；标记留到释放消费或下次按下。
    local chMoved, cardMoved = state.chDragMoved, state.cardDragMoved
    StageSelectDialog.openDungeon(1, "gold_mine")
    state.selKey, state.chScroll = key, 0
    state.rowScroll[key] = 0
    state.chDragY = nil
    resetCardScroll()
    state.chDragMoved, state.cardDragMoved = chMoved, cardMoved
    print("[StageSelectDialog] 准备黄金矿洞1-1引导，小队1；不修改战斗进度")
    return true
end

function StageSelectDialog.close()
    state.open = false
    state.view = "selector"
    state.fromOverview = false
    state.chDragY = nil
    state.chDragMoved = false
    resetCardScroll()
end

function StageSelectDialog.isOpen()
    return state.open
end

function StageSelectDialog.toggle()
    if state.open then
        StageSelectDialog.close()
    else
        StageSelectDialog.open()
    end
end

function StageSelectDialog.handleScroll(wheel, x, y)
    if not state.open then return false end
    if state.view == "overview" then return true end
    local groups = currentGroups()
    local top, bottom = chapterListBounds(groups)
    -- 覆盖整列章节和上下箭头，不要求正好落在按钮高度内。
    if x >= D.CH_X - 20 and x <= D.CH_X + D.CH_W + 20
        and y >= top - 70 and y <= bottom + 70 then
        local maxScroll = math.max(0, #groups - D.CH_VISIBLE)
        state.chScroll = math.max(0, math.min(maxScroll, state.chScroll - wheel))
    elseif inRowViewport(x, y) then
        local group = selectedGroup(groups)
        if group then
            setRowScroll(group, getRowScroll(group) - wheel * rowLayout(group).step)
            -- 混合滚轮与拖动后，不回到按下时的旧偏移。
            if state.rowDragKey then state.cardDragMoved = true end
        end
    end
    return true
end

function StageSelectDialog.handleDragBegin(x, y)
    if not state.open then return false end
    if state.view == "overview" then ExpeditionOverview.handleDragBegin(x, y) return true end
    state.chDragY = nil
    state.chDragMoved = false
    state.rowDragKey = nil
    state.cardDragId = nil
    state.cardDragHorizontal = false
    state.cardDragMoved = false
    local groups = currentGroups()
    local top, bottom = chapterListBounds(groups)
    if x >= D.CH_X and x <= D.CH_X + D.CH_W and y >= top and y <= bottom then
        state.chDragY = y
        state.chDragScroll = state.chScroll
    elseif inRowViewport(x, y) then
        local group = selectedGroup(groups)
        if group then
            state.rowDragKey = tostring(group.key)
            state.cardDragX, state.cardDragY = x, y
            state.cardDragLastX, state.rowDragLastY = x, y
            local id, cards = cardRowAt(groups, x, y)
            if id and cards and not ResourceList.isTowerStage(id) then
                state.cardDragId = id
                local limit = cardScrollLimit(group, cards)
                state.cardDragScroll = math.max(0, math.min(limit, state.cardScroll[id] or 0))
            end
        end
    end
    return true
end

function StageSelectDialog.handleDragMove(x, y)
    if not state.open then return false end
    if state.view == "overview" then ExpeditionOverview.handleDragMove(x, y) return true end
    if state.chDragY then
        local delta = state.chDragY - y
        if math.abs(delta) >= 15 then state.chDragMoved = true end
        local groups = currentGroups()
        local maxScroll = math.max(0, #groups - D.CH_VISIBLE)
        local step = D.CH_BTN_H + D.CH_GAP
        state.chScroll = math.max(0, math.min(maxScroll,
            state.chDragScroll + math.floor(delta / step + 0.5)))
    elseif state.rowDragKey then
        local deltaX, deltaY = state.cardDragX - x, state.cardDragY - y
        if not state.cardDragMoved and math.max(math.abs(deltaX), math.abs(deltaY)) >= 15 then
            -- 首次越阈值即锁方向，之后往返/斜拖也不串轴、不误切关。
            state.cardDragHorizontal = math.abs(deltaX) >= math.abs(deltaY)
            state.cardDragMoved = true
        end
        if state.cardDragMoved then
            if state.cardDragHorizontal and state.cardDragId then
                local cards = stageMonsterCards(ResourceList.getStageEntry(state.cardDragId))
                local limit = cardScrollLimit(selectedGroup(currentGroups()), cards)
                state.cardDragScroll = math.max(0, math.min(limit,
                    state.cardDragScroll + state.cardDragLastX - x))
                state.cardScroll[state.cardDragId] = state.cardDragScroll
                state.cardDragLastX = x
            elseif not state.cardDragHorizontal then
                local group = selectedGroup(currentGroups())
                if group and tostring(group.key) == state.rowDragKey then
                    setRowScroll(group, getRowScroll(group) + state.rowDragLastY - y)
                end
                -- 消化越界位移，反向拖动立即响应，不必走回起点。
                state.rowDragLastY = y
            end
        end
    end
    return true
end

function StageSelectDialog.handleDragEnd()
    if not state.open then return false end
    state.chDragY = nil
    state.rowDragKey = nil
    state.cardDragId = nil
    state.cardDragHorizontal = false
    -- moved 留到点击消费或下一次按下；宿主可能把往返拖动误判为短点击。
    return true
end

-- ======================== 绘制入口按钮 ========================

---@param vg any
function StageSelectDialog.drawButton(vg)
    if imageVg ~= vg or not imagesReady then return end
    local _ds = BF.begin(vg, "stage_sel_btn", BTN_CX, BTN_CY, BTN_W, BTN_H)
    if imgBtn >= 0 then
        drawImageCentered(vg, imgBtn, BTN_CX, BTN_CY, ICON_W, ICON_H, 1.0)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, BTN_CX - BTN_W * 0.5, BTN_CY - BTN_H * 0.5, BTN_W, BTN_H, 18)
        nvgFillColor(vg, nvgRGBA(201, 151, 59, 230))
        nvgFill(vg)
    end
    drawTextStroke(vg, BTN_CX, BTN_CY + BTN_H * 0.42, "选关", 32,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
    BF.finish(vg, _ds)
end

-- ======================== 绘制弹窗 ========================

---@param vg any
function StageSelectDialog.draw(vg)
    if not state.open or imageVg ~= vg or not imagesReady then return end
    local batch = imageBatch
    local scale = getAnimScale()
    if scale <= 0.01 then return end
    if state.view == "overview" then ExpeditionOverview.draw(vg, scale) return end

    local groups, maxOrder = currentGroups()
    local sel = selectedGroup(groups)
    if not sel then return end
    local battleData, dungeonData = ResourceList.getProgress()

    -- 不再铺全屏灰色遮罩
    nvgSave(vg)
    nvgTranslate(vg, D.BG_CX, D.BG_CY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -D.BG_CX, -D.BG_CY)

    if imgBg >= 0 then
        drawNineSlice(vg, imgBg,
            D.BG_CX - D.BG_W * 0.5, D.BG_CY - D.BG_H * 0.5,
            D.BG_W, D.BG_H, D.BG_IT, D.BG_IR, D.BG_IB, D.BG_IL)
    end

    drawTextStroke(vg, D.BG_CX, D.TT_Y, "队伍 " .. state.targetTeam .. " · 选择关卡",
        D.TT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, D.TT_SW,
        { strokeColor = { D.TT_SR, D.TT_SG, D.TT_SB } })

    if state.fromOverview then
        DarkIcon.drawNine(vg, "btn", 95, 701, 145, 54)
        drawTextStroke(vg, 167.5, 728, "‹ 收益概览", 24,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 240, 199, 94, 2)
    end

    -- 顶部分类不挪动主线章节、敌人及既有滚动热区。
    -- 顶部分类与章节列表整体下移一点，按钮组在左栏仍水平居中；右侧关卡及敌人区不动。
    for _, tab in ipairs({ { x = MAIN_TAB_X, key = "main", text = "主线" },
        { x = DUNGEON_TAB_X, key = "dungeon", text = "副本" } }) do
        local active = state.section == tab.key
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tab.x - TAB_W * 0.5, TAB_Y - TAB_H * 0.5, TAB_W, TAB_H, 10)
        nvgFillColor(vg, nvgRGBA(active and 106 or 37, active and 78 or 33, active and 36 or 29, 240))
        nvgFill(vg)
        drawFittedTitle(vg, tab.x, TAB_Y, tab.text, TAB_W - 12, 28, 1,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 235, 194, 2)
    end
    -- 两类关卡共用下方章节、关卡行与敌人卡面，不进入独立资源详情。

    -- ===================== 左栏：章节列表 =====================
    local maxScroll = math.max(0, #groups - D.CH_VISIBLE)
    if state.chScroll > maxScroll then state.chScroll = maxScroll end
    if state.chScroll < 0 then state.chScroll = 0 end

    local needScroll = maxScroll > 0
    local arrowCX = D.CH_X + 28
    local listTop, listBottom = chapterListBounds(groups)
    if needScroll and state.chScroll > 0 then
        drawImageCentered(vg, imgAct, arrowCX, listTop - 34, 52, 32, 1.0)
        drawTextStroke(vg, arrowCX, listTop - 34, "▲", 22,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 2)
    end

    for vi = 1, D.CH_VISIBLE do
        local gi = state.chScroll + vi
        local g = groups[gi]
        if not g then break end
        local x = D.CH_X
        local y = listTop + (vi - 1) * (D.CH_BTN_H + D.CH_GAP)
        local isSel = (tostring(g.key) == tostring(sel.key))
        local hue = chapterHue(g.key, g.hueIndex)
        local firstId = g.ids and g.ids[1]
        local chapterLocked = stageLocked(firstId, maxOrder, battleData, dungeonData)

        if not drawChapterBackground(vg, firstId, x, y, hue, isSel, chapterLocked, g.background) then
            nvgRestore(vg) return
        end
        if isSel then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x, y, D.CH_W, D.CH_BTN_H, 12)
            nvgStrokeColor(vg, nvgRGBA(201, 151, 59, 235))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end

        local cx = x + D.CH_W * 0.5
        -- 章节按钮文字：解锁=亮色，锁定=灰蓝色
        local chR, chG, chB = 235, 230, 210
        if chapterLocked then chR, chG, chB = 0x8b, 0x95, 0xa5 end
        local singleTitle = g.resourceDungeonId or g.isTower
        drawFittedTitle(vg, cx, y + D.CH_BTN_H * (singleTitle and 0.5 or 0.34),
            g.name, D.CH_W - 18, 26, 2,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, chR, chG, chB, 3)
        if chapterLocked and imgLock >= 0 then
            drawImageCentered(vg, imgLock, x + D.CH_W - 22, y + 22, 30, 30, 0.9)
        end
        if not singleTitle then
            -- 主线章节/终焉保留原副标题，副本每类只显示居中名称。
            local rel = g.subLabel or tostring(SC.getRelativeChapter(g.key)) .. " 章"
            rel = type(g.key) == "string" and I18n.difficulty(rel) or I18n.lookup(rel)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 20)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0xc9, 0x97, 0x3B, 220))
            nvgText(vg, cx, y + D.CH_BTN_H * 0.74, rel, nil)
        end
    end

    if needScroll and state.chScroll < maxScroll then
        drawImageCentered(vg, imgAct, arrowCX, listBottom + 34, 52, 32, 1.0)
        drawTextStroke(vg, arrowCX, listBottom + 34, "▼", 22,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 2)
    end

    -- ===================== 中栏：关卡竖排 + 敌人卡面 =====================
    nvgSave(vg)
    local vx0, vy0, vw0, vh0 = rowViewport()
    nvgIntersectScissor(vg, vx0, vy0, vw0, vh0)
    local firstRow, lastRow, rowOffset = visibleRows(sel)
    local selectedCurrent = groupTarget(sel)
    local actualCurrent = currentStageId()
    local layout = rowLayout(sel)
    for i = firstRow, lastRow do
        local id = sel.ids[i]
        local y = rowY(sel, i, rowOffset)
        local x = D.MID_X
        local isCur = (id == selectedCurrent)
        local entry = ResourceList.getStageEntry(id)
        local isBoss = (entry and (entry.bossId or 0) > 0) or SC.isTerminalTemple(id)
        local locked = stageLocked(id, maxOrder, battleData, dungeonData)
        -- 目标就是稳定、未锁定的首层真实行；裁剪外或开窗动画期间不放行。
        if state.section == "dungeon" and sel.resourceDungeonId == "gold_mine"
            and state.targetTeam == 1 and i == 1 and not locked
            and time.elapsedTime - state.openTime >= ANIM_OPEN_DUR then
            local top = math.max(y, vy0)
            local bottom = math.min(y + layout.rowHeight, vy0 + vh0)
            if bottom > top then
                require("systems.TutorialManager").registerHotspot("dungeon_gold_mine",
                    x + D.MID_W * 0.5, (top + bottom) * 0.5,
                    D.MID_W, bottom - top, "tri_modal")
            end
        end

        -- 行底
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, D.MID_W, layout.rowHeight, 12)
        if isCur then
            nvgFillColor(vg, nvgRGBA(201, 151, 59, 40))
        else
            nvgFillColor(vg, nvgRGBA(0, 0, 0, locked and 70 or 40))
        end
        nvgFill(vg)
        if isCur then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x, y, D.MID_W, layout.rowHeight, 12)
            nvgStrokeColor(vg, nvgRGBA(201, 151, 59, 235))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end

        -- 关卡号（行左上）：解锁=亮色（Boss红），锁定=棕色
        local fr, fg, fb = 255, 255, 255
        if isBoss then fr, fg, fb = 0xE0, 0x5A, 0x5A end
        if locked then fr, fg, fb = 0x8b, 0x95, 0xa5 end
        if SC.isTerminalTemple(id) then
            drawFittedTitle(vg, x + 16, y + 50, shortStageLabel(id), D.CARD_X - x - 28, 24, 4,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, fr, fg, fb, 2)
        else
            drawTextStroke(vg, x + 16, y + layout.labelY, shortStageLabel(id), 30,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, fr, fg, fb, 2)
        end

        -- 状态（行左下）
        local sub = ""
        if isCur then
            sub = layout.compact and id ~= actualCurrent and "当前章节" or "当前"
        elseif locked then
            sub = "未解锁"
        elseif SC.isTerminalTemple(id) then
            sub = "神殿"
        elseif isBoss then
            sub = "首领"
        elseif ResourceList.isTowerStage(id) then
            sub = "通天塔"
        elseif SC.isResourceStage(id) then
            sub = "副本"
        else
            sub = I18n.difficulty(SC.getDifficultyDisplayName(SC.getDifficulty(id)))
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if isCur then
            nvgFillColor(vg, nvgRGBA(0xC9, 0x97, 0x3B, 255))
        elseif locked then
            nvgFillColor(vg, nvgRGBA(0x8b, 0x95, 0xa5, 255))  -- 未解锁=灰蓝色
        else
            nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 255))
        end
        -- 塔状态上移，避开y+130..164奖励带；主线134/资源78原值不动。
        local statusY = entry and entry.tower and 100 or layout.statusY
        nvgText(vg, x + 16, y + statusY, sub, nil)

        -- 推荐战力（行左中，v2.61 接线 / v2.63 图标化）：
        -- 口径 = battle-lab 开荒三人组无养成实测阈值（ml≤46 实测 / ml≤92 保守外推），
        -- 带装备养成的玩家实际需求更低，因此只做「达标提示」不做硬性门槛。
        -- v2.63（用户要求）：不再显示「推荐/推荐≈」文字，改为 power 火焰图标
        --   + 纯数字（与 TopBar 玩家战力同图标，玩家一看即懂是战力比较）。
        --   ≈ 模糊前缀取消——外推关仅以蓝灰数字色区分，不做文本标注。
        -- 三态：实测(数字与玩家总战力比较着色) / 外推(蓝灰) / 无数据(不绘制)。
        -- 布局：图标中心 x+25，数字左缘 x+38；副本大数缩写并适配可用宽度。
        -- 主线仍保留原完整数字，锁定行的图标与文字透明度一致。
        ---@type number|nil, boolean|nil
        local recPower, recExtr = ResourceList.getRecommendedPower(id, entry)
        if recPower then
            local rr, rg, rb
            if recExtr then
                -- 外推带（ml 47..92）：估算值，数字蓝灰，不与玩家战力比较
                rr, rg, rb = 0x8F, 0xA8, 0xC0
            else
                local playerPower = GameState.getPower() or 0
                if playerPower <= 0 then
                    rr, rg, rb = 0xb6, 0xb0, 0x9d          -- 战力未知：中性色
                elseif playerPower >= recPower then
                    rr, rg, rb = 0x7A, 0xC8, 0x6E          -- 达标：绿
                else
                    rr, rg, rb = 0xE0, 0x5A, 0x5A          -- 不足：红（与 Boss 关同色系）
                end
            end
            local iconAlpha = (locked and 140 or 255) / 255
            DarkIcon.draw(vg, "power", x + 25, y + layout.powerY, 18, iconAlpha)
            local isDungeon = ResourceList.getGroupKey(id) ~= nil
            local powerText = isDungeon and require("core.NumberUtil").format(recPower) or tostring(recPower)
            drawFittedTitle(vg, x + 38, y + layout.powerY, powerText,
                D.CARD_X - x - 46, 20, 1, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                rr, rg, rb, 2, { alpha = iconAlpha })
        end

        if entry and entry.tower then
            drawTowerPreview(vg, entry, y, locked)
        else
            -- 敌人卡面（行右侧横排；名称和数量随卡面一起滚动）
            local mids = stageMonsterCards(entry)
            local maxOffset, contentW = cardScrollLimit(sel, mids)
            local offset = math.max(0, math.min(maxOffset, state.cardScroll[id] or 0))
            state.cardScroll[id] = offset
            local vx, vy, vw, vh = cardViewport(sel, y)
            local cardCY = y + layout.cardCenterY
            local cardW, cardH = layout.cardWidth, layout.cardHeight
            nvgSave(vg)
            nvgIntersectScissor(vg, vx, vy, vw, vh)
            for ci, info in ipairs(mids) do
                local monsterId = info.id
                local cardCX = D.CARD_X + 2 + (ci - 1) * (cardW + layout.cardGap) + cardW * 0.5 - offset
                local card = ensureMonsterCard(vg, monsterId)
                if imageBatch ~= batch or imageVg ~= vg or not imagesReady then
                    -- 卡面clip、关卡视窗clip、弹窗transform依次恢复。
                    nvgRestore(vg) nvgRestore(vg) nvgRestore(vg)
                    return
                end
                if card >= 0 then
                    drawImageCover(vg, card, cardCX, cardCY, cardW, cardH, locked and 0.4 or 1.0)
                else
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, cardCX - cardW * 0.5, cardCY - cardH * 0.5,
                        cardW, cardH, 8)
                    nvgFillColor(vg, nvgRGBA(30, 26, 22, 200))
                    nvgFill(vg)
                end
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cardCX - cardW * 0.5, cardCY - cardH * 0.5,
                    cardW, cardH, 8)
                nvgStrokeColor(vg, nvgRGBA(201, 151, 59, locked and 90 or 200))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)
                local name = MC.getName(monsterId)
                nvgSave(vg)
                nvgIntersectScissor(vg, cardCX - cardW * 0.5, cardCY - cardH * 0.5,
                    cardW, cardH)
                drawTextStroke(vg, cardCX, cardCY - cardH * 0.5 + 14, name, 16,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 236, 226, 198, 2,
                    { alpha = locked and 0.55 or 1 })
                nvgRestore(vg)
                -- 紧凑行数量留在卡面底部，横滚条/奖励带另占固定区域。
                local numberY = layout.compact and (cardCY + cardH * 0.5 - 8)
                    or (cardCY + cardH * 0.5 + layout.numberOffset)
                drawTextStroke(vg, cardCX, numberY, "x" .. tostring(info.count), 18,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 214, 120, 2,
                    { alpha = locked and 0.55 or 1 })
            end
            nvgRestore(vg)
            if maxOffset > 0 then
                local thumbW = vw * vw / contentW
                local thumbX = vx + (vw - thumbW) * offset / maxOffset
                nvgBeginPath(vg)
                nvgRoundedRect(vg, vx, y + layout.scrollBarY, vw, 3, 1.5)
                nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 60))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, thumbX, y + layout.scrollBarY, thumbW, 3, 1.5)
                nvgFillColor(vg, nvgRGBA(201, 151, 59, locked and 110 or 220))
                nvgFill(vg)
                if not layout.compact then
                    drawFittedTitle(vg, vx + vw * 0.5, y + layout.scrollHintY, "左右拖动查看敌人", vw - 8, 18, 1,
                        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 201, 151, 59, 2)
                end
            end
            if layout.compact then
                RewardPreview.draw(vg, ResourceList.getRewardPreview(id, entry),
                    x + 8, y + REWARD_BAND_Y, D.MID_W - 16, REWARD_BAND_HEIGHT, locked)
            end
        end
        if imageBatch ~= batch or imageVg ~= vg or not imagesReady then
            nvgRestore(vg) nvgRestore(vg) -- 关卡视窗clip、弹窗transform
            return
        end
        if SC.isTerminalTemple(id) then drawTerminalGuide(vg, y, locked) end
    end
    nvgRestore(vg)

    local rowLimit = rowScrollLimit(sel)
    if rowLimit > 0 then
        local thumbH = math.max(30, vh0 * vh0 / (vh0 + rowLimit))
        local thumbY = vy0 + (vh0 - thumbH) * rowOffset / rowLimit
        nvgBeginPath(vg)
        nvgRoundedRect(vg, vx0 + vw0 + 8, vy0, 5, vh0, 2.5)
        nvgFillColor(vg, nvgRGBA(182, 176, 157, 60))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, vx0 + vw0 + 8, thumbY, 5, thumbH, 2.5)
        nvgFillColor(vg, nvgRGBA(201, 151, 59, 220))
        nvgFill(vg)
    end
    if layout.compact then
        -- 四分类下方的左栏空区，仅画说明，不新增热区或挤占右侧关卡视窗。
        local noteCX, noteW = D.CH_X + D.CH_W * 0.5, D.CH_W
        local align = NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE
        drawFittedTitle(vg, noteCX, 1320, "按击杀结算", noteW, 20, 1,
            align, 201, 151, 59, 2)
        drawFittedTitle(vg, noteCX, 1346, "非额外通关奖励", noteW, 20, 1,
            align, 201, 151, 59, 2)
        if sel.resourceDungeonId == "equipment_vault" then
            drawFittedTitle(vg, noteCX, 1390, "装备随机掉落", noteW, 18, 1,
                align, 182, 176, 157, 2)
            drawFittedTitle(vg, noteCX, 1416, "按设置入包/分解", noteW, 18, 1,
                align, 182, 176, 157, 2)
            drawFittedTitle(vg, noteCX, 1442, "或进入遗匣", noteW, 18, 1,
                align, 182, 176, 157, 2)
        else
            drawFittedTitle(vg, noteCX, 1390, "一关约主线一章", noteW, 18, 1,
                align, 182, 176, 157, 2)
            drawFittedTitle(vg, noteCX, 1416, "末关保留原跨度", noteW, 18, 1,
                align, 182, 176, 157, 2)
        end
    end
    nvgRestore(vg)
end

-- 只在小队1真实已进入金币关后确认教学，不把分类点击或业务拒绝当成功。
local function notifyGoldMineEntered(teamIdx, stageId)
    if teamIdx ~= 1 or require("config.DungeonConfig").decodeStageId(stageId) ~= "gold_mine" then
        return false
    end
    if require("ui.battle.tri.BattleTriPage").getTeamStageId(1) ~= stageId then return false end
    require("systems.TutorialManager").notifyEvent("enter_gold_mine")
    return true
end

-- ======================== 输入 ========================

---@param x number
---@param y number
---@return boolean
function StageSelectDialog.handleInput(x, y)
    if not state.open then return false end
    if state.view == "overview" then
        local action, team = ExpeditionOverview.handleInput(x, y)
        if action == "close" then StageSelectDialog.close()
        elseif action == "team" then StageSelectDialog.showTeam(team) end
        return true
    end

    local groups, maxOrder = currentGroups()
    if state.chDragMoved or state.cardDragMoved then
        state.chDragMoved = false
        state.cardDragMoved = false
        return true
    end
    if state.fromOverview and hitTestRect(x, y, 167.5, 728, 145, 54) then
        StageSelectDialog.backToOverview()
        return true
    end
    if hitTestRect(x, y, MAIN_TAB_X, TAB_Y, TAB_W, TAB_H)
        or hitTestRect(x, y, DUNGEON_TAB_X, TAB_Y, TAB_W, TAB_H) then
        switchSection(x < (MAIN_TAB_X + DUNGEON_TAB_X) * 0.5 and "main" or "dungeon")
        BF.trigger("stage_sel_section")
        return true
    end
    local maxScroll = math.max(0, #groups - D.CH_VISIBLE)
    local needScroll = maxScroll > 0

    local arrowCX = D.CH_X + 28
    local listTop, listBottom = chapterListBounds(groups)

    -- 左栏滚动箭头（列表外侧，不压章节名）
    if needScroll and state.chScroll > 0
        and hitTestRect(x, y, arrowCX, listTop - 34, 64, 40) then
        BF.trigger("stage_sel_chup")
        state.chScroll = state.chScroll - 1
        return true
    end
    if needScroll and state.chScroll < maxScroll
        and hitTestRect(x, y, arrowCX, listBottom + 34, 64, 40) then
        BF.trigger("stage_sel_chdown")
        state.chScroll = state.chScroll + 1
        return true
    end

    -- 章节按钮
    for vi = 1, D.CH_VISIBLE do
        local gi = state.chScroll + vi
        local g = groups[gi]
        if not g then break end
        local bx = D.CH_X
        local by = listTop + (vi - 1) * (D.CH_BTN_H + D.CH_GAP)
        if x >= bx and x <= bx + D.CH_W and y >= by and y <= by + D.CH_BTN_H then
            BF.trigger("stage_sel_ch")
            if tostring(state.selKey) ~= tostring(g.key) then resetCardScroll() end
            state.selKey = g.key
            if state.rowScroll[tostring(g.key)] == nil then revealStage(g, groupTarget(g)) end
            return true
        end
    end

    -- 关卡行：绘制/命中共用偏移，裁剪外和行间空白绝不能选到隐藏关卡。
    local sel = selectedGroup(groups)
    local id = rowAt(sel, x, y)
    if id then
        BF.trigger("stage_sel_cell")
        if not teamSelectionAllowed(state.targetTeam) then return true end
        if stageLocked(id, maxOrder) then return true end
        if ResourceList.isTowerStage(id) then
            local entry = ResourceList.getStageEntry(id)
            local teamIdx = state.targetTeam or 1
            if entry and onDungeonSelect then
                local ok = onDungeonSelect("babel_tower", teamIdx, entry.stage)
                if ok then StageSelectDialog.close() end
                print("[StageSelectDialog] 前往通天塔: 队伍=" .. teamIdx .. " 层=" .. entry.stage)
            end
            return true
        end
        local teamIdx = SC.isTerminalTemple(id) and 1 or (state.targetTeam or 1)
        if id == currentStageId() then
            if notifyGoldMineEntered(teamIdx, id) then StageSelectDialog.close() end
            return true
        end
        local BattleTriPage = require("ui.battle.tri.BattleTriPage")
        local ok = BattleTriPage.gotoTeamStage(teamIdx, id)
        -- 只关选关弹窗，三队页与其他两队战斗继续保留。
        if ok then
            notifyGoldMineEntered(teamIdx, id)
            StageSelectDialog.close()
        end
        print("[StageSelectDialog] 前往关卡: " .. tostring(id))
        return true
    end

    if not hitTestRect(x, y, D.BG_CX, D.BG_CY, D.BG_W, D.BG_H) then
        StageSelectDialog.close()
    end
    return true
end

---@param x number
---@param y number
---@return boolean
function StageSelectDialog.handleButtonInput(x, y, teamIdx)
    if state.open then return false end
    if hitTestRect(x, y, BTN_CX, BTN_CY, BTN_W, BTN_H) then
        BF.trigger("stage_sel_btn")
        StageSelectDialog.open(teamIdx)
        return true
    end
    return false
end

return StageSelectDialog
