-- ============================================================================
-- StageSelectDialog - 主线选关弹窗（v2 章节两栏版）
-- 布局（参考暗黑地牢选关图）:
--   左栏: 大关卡（章节）竖排列表，各章色调横幅 + 章名，>9 章上下滚动
--   中栏: 章节地图预览（MAP_{rel}.png cover）+ 该章小关卡网格（5 列）
--         当前关金框 / Boss 关红字 / 终焉神殿独立章组
--   点击空白关闭
-- 入口：战斗界面 HUD「选关」按钮（与扫荡/统计同套图标按钮）
-- ============================================================================

local GameConfig        = require("config.GameConfig")
local SC                = require("config.StageConfig")
local MC                = require("config.MonsterConfig")
local BattleEnemySpawn  = require("ui.battle.stage.BattleEnemySpawn")
local DrawUtil          = require("core.DrawUtil")
local BF                = require("systems.ButtonFeedback")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local drawImageCover    = DrawUtil.drawImageCover

local StageSelectDialog = {}

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
    BG_IT   = 180,  BG_IR  = 40,  BG_IB = 50,  BG_IL = 40,

    TT_Y    = 690,  TT_FONT = 50,  TT_SW = 6,
    TT_SR   = 0x00, TT_SG  = 0x00, TT_SB = 0x00,

    -- 左栏: 章节列表
    CH_X      = 105,     -- 左栏左缘
    CH_W      = 190,
    CH_BTN_H  = 84,
    CH_GAP    = 10,
    CH_Y0     = 756,     -- 第一个章节按钮顶边
    CH_VISIBLE = 8,      -- 可视章节数（超出滚动）

    CONFIRM_TOP = 1170,
    CONFIRM_W = 580,
    CONFIRM_H = 390,
    CONFIRM_BTN_OFFSET = 52,

    -- 中栏
    MID_X     = 315,
    MID_W     = 580,
    PREV_Y    = 756,     -- 预览图顶边
    PREV_H    = 232,
    GRID_Y0   = 1020,    -- 网格顶边
    CELL_W    = 106,
    CELL_H    = 92,
    CELL_GAP  = 8,
    GRID_COLS = 5,

}

local ANIM_OPEN_DUR = 0.18

-- 章节横幅色调（8 色循环，参考图每章一色的效果）
local CH_HUES = {
    { 0x3e, 0x5a, 0x40 }, { 0x6b, 0x46, 0x2f }, { 0x33, 0x4a, 0x63 }, { 0x2f, 0x5a, 0x5c },
    { 0x4a, 0x3f, 0x63 }, { 0x5a, 0x30, 0x33 }, { 0x3d, 0x53, 0x3a }, { 0x59, 0x4d, 0x2e },
}

local imgBtn = -1
local imgBg  = -1
local imgAct = -1

local state = {
    open      = false,
    openTime  = 0,
    selKey    = nil,   -- 选中章节 key（chapter number 或 "T"=终焉神殿组）
    pendingId = nil,   -- 二次确认的关卡 ID
    chScroll  = 0,     -- 左栏滚动起点（0-based）
    chDragY   = nil,   -- 左栏按下位置
    chDragScroll = 0, -- 按下时滚动起点
    chDragMoved = false,

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

--- 沿官方关卡链收集全链（不随进度截断；不跟随转生跨难度回环）
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
        if SC.getStage(cur) then
            ids[#ids + 1] = cur
            order[cur] = #ids
        end
        local nxt = SC.getNextStageId(cur)
        if not nxt then break end
        cur = nxt
    end
    return ids, order
end

--- 章节组：{{ key=chapter|"T", name=, ids={} } 按进度顺序}
local function collectChapterGroups()
    local ids, order = collectAllIds()
    local groups = {}
    ---@type table<any, number>
    local indexOf = {}
    for _, id in ipairs(ids) do
        local key
        if SC.isTerminalTemple(id) then
            key = "T"
        else
            key = math.floor(id / 100)
        end
        local gi = indexOf[key]
        if not gi then
            gi = #groups + 1
            indexOf[key] = gi
            local name
            if key == "T" then
                name = "终焉"
            else
                name = SC.getChapterName(key)
            end
            groups[gi] = { key = key, name = name, ids = {} }
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
    if not state.cacheGroups or state.cacheMaxStage ~= maxStage then
        local groups, order = collectChapterGroups()
        state.cacheGroups = groups
        state.cacheOrder = order
        state.cacheMaxStage = maxStage
        -- 解锁基准: maxStage 的链序; 链上找不到(如转生后 id)则视为全解锁
        state.cacheMaxOrder = (maxStage and order[maxStage]) or ids_of(groups)
    end
    return state.cacheGroups, state.cacheMaxOrder
end

local function chapterHue(key)
    local n = (type(key) == "number") and key or 23
    return CH_HUES[((n - 1) % #CH_HUES) + 1]
end

local function shortStageLabel(id)
    if SC.isTerminalTemple(id) then
        local entry = SC.getStage(id)
        return entry and entry.name or "终焉神殿"
    end
    local entry = SC.getStage(id)
    if not entry then return tostring(id) end
    local rel = SC.getRelativeChapter(entry.chapter)
    return string.format("%d-%d", rel, entry.stage)
end

--- 预览图句柄缓存（懒加载，键=相对章节号或 mapBg 文件名）
---@type table<any, integer>
local mapImgs = {}

local function ensureMapImg(vg, group)
    local firstId = group.ids[1]
    local entry = firstId and SC.getStage(firstId)
    if entry and entry.mapBg then
        local img = mapImgs[entry.mapBg]
        if img == nil then
            img = nvgCreateImage(vg, "image/关卡地图/" .. entry.mapBg, 0)
            mapImgs[entry.mapBg] = img
        end
        return img
    end
    local chapter = (group.key ~= "T") and group.key or 23
    local n = ((chapter - 1) % 23) + 1
    local img = mapImgs[n]
    if img == nil then
        img = nvgCreateImage(vg, "image/关卡地图/MAP_" .. n .. ".png", 0)
        mapImgs[n] = img
    end
    return img
end

local function selectedGroup(groups)
    for _, g in ipairs(groups) do
        if tostring(g.key) == tostring(state.selKey) then return g end
    end
    return groups[1]
end

local function chapterListBounds(groups)
    local needScroll = #groups > D.CH_VISIBLE
    local top = D.CH_Y0 + (needScroll and 30 or 0)
    local bottom = top + D.CH_VISIBLE * (D.CH_BTN_H + D.CH_GAP) - D.CH_GAP
    return top, bottom
end

-- ======================== Public API ========================

---@param vg any
function StageSelectDialog.init(vg)
    imgBtn = nvgCreateImage(vg, "image/通用图标/UI_ICON_XG.png", 0)
    imgBg  = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TY_EJQRK.png", 0)
    imgAct = nvgCreateImage(vg, "image/按钮/UI_AN_HUANG.png", 0)
    print("[StageSelectDialog] init OK")
end

function StageSelectDialog.open()
    if state.open then return end
    state.open     = true
    state.openTime = time.elapsedTime
    state.pendingId = nil
    state.chDragY = nil
    state.chDragMoved = false
    local BS = require("ui.battle.scene.BattleScene")
    local curStage = BS.getStageId()
    -- 定位到当前关所在章节
    local curKey
    if curStage and SC.isTerminalTemple(curStage) then
        curKey = "T"
    elseif curStage then
        curKey = math.floor(curStage / 100)
    end
    ensureCache()
    state.selKey = curKey
    -- 滚动让当前章可见
    local groups = state.cacheGroups or {}
    local gi = 1
    for i, g in ipairs(groups) do
        if tostring(g.key) == tostring(curKey) then gi = i; break end
    end
    local maxScroll = math.max(0, #groups - D.CH_VISIBLE)
    state.chScroll = math.max(0, math.min(gi - 1, maxScroll))
end

function StageSelectDialog.close()
    state.open = false
    state.pendingId = nil
    state.chDragY = nil
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
    if state.pendingId then return true end
    local groups = ensureCache()
    local top, bottom = chapterListBounds(groups)
    if x >= D.CH_X and x <= D.CH_X + D.CH_W and y >= top and y <= bottom then
        local maxScroll = math.max(0, #groups - D.CH_VISIBLE)
        state.chScroll = math.max(0, math.min(maxScroll, state.chScroll - wheel))
    end
    return true
end

function StageSelectDialog.handleDragBegin(x, y)
    if not state.open then return false end
    state.chDragMoved = false
    if state.pendingId then return true end
    local groups = ensureCache()
    local top, bottom = chapterListBounds(groups)
    if x >= D.CH_X and x <= D.CH_X + D.CH_W and y >= top and y <= bottom then
        state.chDragY = y
        state.chDragScroll = state.chScroll
        state.chDragMoved = false
    end
    return true
end

function StageSelectDialog.handleDragMove(_, y)
    if not state.open then return false end
    if state.chDragY then
        local delta = state.chDragY - y
        if math.abs(delta) >= 15 then state.chDragMoved = true end
        local groups = ensureCache()
        local maxScroll = math.max(0, #groups - D.CH_VISIBLE)
        local step = D.CH_BTN_H + D.CH_GAP
        state.chScroll = math.max(0, math.min(maxScroll,
            state.chDragScroll + math.floor(delta / step + 0.5)))
    end
    return true
end

function StageSelectDialog.handleDragEnd()
    if not state.open then return false end
    state.chDragY = nil
    return true
end

-- ======================== 绘制入口按钮 ========================

---@param vg any
function StageSelectDialog.drawButton(vg)
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
    if not state.open then return end
    local scale = getAnimScale()
    if scale <= 0.01 then return end

    local BS = require("ui.battle.scene.BattleScene")
    local groups, maxOrder = ensureCache()
    local curStage = BS.getStageId()
    local sel = selectedGroup(groups)
    if not sel then return end

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

    drawTextStroke(vg, D.BG_CX, D.TT_Y, "选择关卡",
        D.TT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, D.TT_SW,
        { strokeColor = { D.TT_SR, D.TT_SG, D.TT_SB } })

    -- ===================== 左栏：章节列表 =====================
    local maxScroll = math.max(0, #groups - D.CH_VISIBLE)
    if state.chScroll > maxScroll then state.chScroll = maxScroll end
    if state.chScroll < 0 then state.chScroll = 0 end

    local needScroll = maxScroll > 0
    local arrowCX = D.CH_X + D.CH_W * 0.5
    local listTop = D.CH_Y0
    if needScroll then
        -- 上箭头
        if state.chScroll > 0 then
            drawImageCentered(vg, imgAct, arrowCX, D.CH_Y0 - 26, 64, 40, 1.0)
            drawTextStroke(vg, arrowCX, D.CH_Y0 - 26, "▲", 24,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
        end
        listTop = D.CH_Y0 + 30
        -- 下箭头位置在列表底部之后
    end

    for vi = 1, D.CH_VISIBLE do
        local gi = state.chScroll + vi
        local g = groups[gi]
        if not g then break end
        local x = D.CH_X
        local y = listTop + (vi - 1) * (D.CH_BTN_H + D.CH_GAP)
        local isSel = (tostring(g.key) == tostring(sel.key))
        local hue = chapterHue(g.key)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, D.CH_W, D.CH_BTN_H, 12)
        if isSel then
            nvgFillColor(vg, nvgRGBA(hue[1] + 24, hue[2] + 24, hue[3] + 18, 235))
        else
            nvgFillColor(vg, nvgRGBA(hue[1], hue[2], hue[3], 170))
        end
        nvgFill(vg)
        if isSel then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x, y, D.CH_W, D.CH_BTN_H, 12)
            nvgStrokeColor(vg, nvgRGBA(201, 151, 59, 235))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end

        local cx = x + D.CH_W * 0.5
        drawTextStroke(vg, cx, y + D.CH_BTN_H * 0.36, g.name, 28,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 235, 230, 210, 3)
        local rel
        if g.key == "T" then
            rel = "终焉"
        else
            rel = tostring(SC.getRelativeChapter(g.key)) .. " 章"
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xc9, 0x97, 0x3B, 220))
        nvgText(vg, cx, y + D.CH_BTN_H * 0.74, rel, nil)
    end

    if needScroll then
        local listBottom = listTop + D.CH_VISIBLE * (D.CH_BTN_H + D.CH_GAP) - D.CH_GAP
        if state.chScroll < maxScroll then
            drawImageCentered(vg, imgAct, arrowCX, listBottom + 26, 64, 40, 1.0)
            drawTextStroke(vg, arrowCX, listBottom + 26, "▼", 24,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
        end
    end

    -- ===================== 中栏：预览图 + 关卡网格 =====================
    -- 章节预览图（cover 填充，圆角裁切由 ImagePattern 矩形保证）
    local pvX = D.MID_X
    local pvY = D.PREV_Y
    local mapImg = ensureMapImg(vg, sel)
    if mapImg and mapImg >= 0 then
        drawImageCover(vg, mapImg, pvX + D.MID_W * 0.5, pvY + D.PREV_H * 0.5,
            D.MID_W, D.PREV_H, 1.0)
    else
        nvgBeginPath(vg)
        nvgRect(vg, pvX, pvY, D.MID_W, D.PREV_H)
        nvgFillColor(vg, nvgRGBA(18, 18, 24, 255))
        nvgFill(vg)
    end
    -- 预览图压暗遮罩 + 章名
    nvgBeginPath(vg)
    nvgRect(vg, pvX, pvY, D.MID_W, D.PREV_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 70))
    nvgFill(vg)
    drawTextStroke(vg, pvX + D.MID_W * 0.5, pvY + D.PREV_H * 0.5 - 12, sel.name, 44,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 240, 232, 208, 5)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xd8, 0xc9, 0xa3, 255))
    nvgText(vg, pvX + D.MID_W * 0.5, pvY + D.PREV_H * 0.5 + 28,
        string.format("%d 个关卡 · 点击下方小关切换", #sel.ids), nil)

    -- 关卡网格（5 列）
    local cols = D.GRID_COLS
    local cellW, cellH, gap = D.CELL_W, D.CELL_H, D.CELL_GAP
    for i, id in ipairs(sel.ids) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = pvX + col * (cellW + gap)
        local y = D.GRID_Y0 + row * (cellH + gap)
        local cx, cy = x + cellW * 0.5, y + cellH * 0.5
        local isCur = (id == curStage)
        local isBoss = SC.hasBoss(id) or SC.isTerminalTemple(id)
        -- 未解锁: 链序超过玩家解锁进度
        local ord = state.cacheOrder and state.cacheOrder[id] or nil
        local locked = (ord == nil) or (maxOrder == nil) or (ord > maxOrder)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, cellW, cellH, 12)
        if isCur then
            nvgFillColor(vg, nvgRGBA(201, 151, 59, 48))
        else
            nvgFillColor(vg, nvgRGBA(0, 0, 0, locked and 60 or 26))
        end
        nvgFill(vg)
        if isCur then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x, y, cellW, cellH, 12)
            nvgStrokeColor(vg, nvgRGBA(201, 151, 59, 235))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end

        local label = shortStageLabel(id)
        local fr, fg, fb = 0, 0, 0
        if isCur then
            fr, fg, fb = 0, 0, 0
        elseif isBoss then
            fr, fg, fb = 0xA6, 0x1E, 0x1E
        end
        local txtA = locked and 150 or 255
        drawTextStroke(vg, cx, cy - 12, label, 28,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            txtA, txtA, txtA, 4, { strokeColor = { fr, fg, fb } })

        local sub
        if isCur then
            sub = "当前"
        elseif locked then
            sub = "未解锁"
        elseif SC.isTerminalTemple(id) then
            sub = "神殿"
        elseif isBoss then
            sub = "首领"
        else
            sub = SC.getDifficultyDisplayName(SC.getDifficulty(id))
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isCur then
            nvgFillColor(vg, nvgRGBA(0xC9, 0x97, 0x3B, 255))
        elseif locked then
            nvgFillColor(vg, nvgRGBA(0x8a, 0x84, 0x74, 220))
        else
            nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 255))
        end
        nvgText(vg, cx, cy + 20, sub, nil)
    end

    -- 待确认的关卡详情，明确展示敌人后才能切换。
    if state.pendingId then
        local entry = SC.getStage(state.pendingId)
        local cx, top, w, h = D.BG_CX, D.CONFIRM_TOP, D.CONFIRM_W, D.CONFIRM_H
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - w * 0.5, top, w, h, 18)
        nvgFillColor(vg, nvgRGBA(19, 17, 16, 248))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(201, 151, 59, 240))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
        drawTextStroke(vg, cx, top + 48, "确认前往 " .. shortStageLabel(state.pendingId) .. "？", 32,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
        local enemies = {}
        if entry then
            for _, monsterId in ipairs(entry.monsters or {}) do
                enemies[#enemies + 1] = MC.getName(monsterId)
            end
            if entry.bossId and entry.bossId > 0 then
                enemies[#enemies + 1] = "首领 " .. MC.getName(entry.bossId)
            end
            local bonusIds = BattleEnemySpawn.getFirstClearBonusMonsterIds(entry)
            for _, monsterId in ipairs(bonusIds or {}) do
                enemies[#enemies + 1] = "首通 " .. MC.getName(monsterId)
            end
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 25)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
        nvgText(vg, cx, top + 103, "敌人 Lv." .. tostring(entry and entry.monsterLevel or "?") .. "：", nil)
        for i, name in ipairs(enemies) do
            nvgText(vg, cx, top + 106 + i * 28, name, nil)
        end
        local buttonY = top + h - D.CONFIRM_BTN_OFFSET
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 245, buttonY - 38, 200, 76, 12)
        nvgFillColor(vg, nvgRGBA(67, 58, 46, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx + 33, buttonY - 38, 225, 76, 12)
        nvgFillColor(vg, nvgRGBA(153, 106, 36, 255))
        nvgFill(vg)
        drawTextStroke(vg, cx - 145, buttonY, "取消", 32,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
        drawTextStroke(vg, cx + 145, buttonY, "确认前往", 32,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
    end

    nvgRestore(vg)
end

-- ======================== 输入 ========================

---@param x number
---@param y number
---@return boolean
function StageSelectDialog.handleInput(x, y)
    if not state.open then return false end

    local BS = require("ui.battle.scene.BattleScene")
    local groups, maxOrder = ensureCache()
    if state.pendingId then
        local id = state.pendingId
        local buttonY = D.CONFIRM_TOP + D.CONFIRM_H - D.CONFIRM_BTN_OFFSET
        if hitTestRect(x, y, D.BG_CX - 145, buttonY, 200, 76) then
            state.pendingId = nil
        elseif hitTestRect(x, y, D.BG_CX + 145, buttonY, 225, 76) then
            local ord = state.cacheOrder and state.cacheOrder[id]
            if ord and maxOrder and ord <= maxOrder and SC.getStage(id) then
                local ok = BS.gotoStage(id)
                if ok then StageSelectDialog.close() end
            else
                state.pendingId = nil
            end
        end
        return true
    end
    if state.chDragMoved then
        state.chDragMoved = false
        return true
    end
    local maxScroll = math.max(0, #groups - D.CH_VISIBLE)
    local needScroll = maxScroll > 0

    local listTop, listBottom = chapterListBounds(groups)
    local arrowCX = D.CH_X + D.CH_W * 0.5

    -- 左栏滚动箭头
    if needScroll and state.chScroll > 0
        and hitTestRect(x, y, arrowCX, D.CH_Y0 - 26, 72, 44) then
        BF.trigger("stage_sel_chup")
        state.chScroll = state.chScroll - 1
        return true
    end
    if needScroll and state.chScroll < maxScroll
        and hitTestRect(x, y, arrowCX, listBottom + 26, 72, 44) then
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
            state.selKey = g.key
            state.pendingId = nil
            return true
        end
    end

    -- 关卡网格
    local sel = selectedGroup(groups)
    if sel then
        local cols = D.GRID_COLS
        for i, id in ipairs(sel.ids) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local x0 = D.MID_X + col * (D.CELL_W + D.CELL_GAP)
            local y0 = D.GRID_Y0 + row * (D.CELL_H + D.CELL_GAP)
            if x >= x0 and x <= x0 + D.CELL_W and y >= y0 and y <= y0 + D.CELL_H then
                BF.trigger("stage_sel_cell")
                -- 未解锁: 吞掉点击不跳转
                local ord = state.cacheOrder and state.cacheOrder[id] or nil
                if (ord == nil) or (maxOrder == nil) or (ord > maxOrder) then
                    return true
                end
                if id == BS.getStageId() then return true end
                state.pendingId = id
                print("[StageSelectDialog] 待确认关卡: " .. tostring(id))
                return true
            end
        end
    end

    if not hitTestRect(x, y, D.BG_CX, D.BG_CY, D.BG_W, D.BG_H) then
        StageSelectDialog.close()
    end
    return true
end

---@param x number
---@param y number
---@return boolean
function StageSelectDialog.handleButtonInput(x, y)
    if state.open then return false end
    if hitTestRect(x, y, BTN_CX, BTN_CY, BTN_W, BTN_H) then
        BF.trigger("stage_sel_btn")
        StageSelectDialog.open()
        return true
    end
    return false
end

return StageSelectDialog
