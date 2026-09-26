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

    -- 中栏：关卡竖排（5-1 在上，5-5 在下），每行直接展示敌人卡面
    MID_X     = 315,
    MID_W     = 580,
    ROW_Y0    = 756,     -- 第一行顶边
    ROW_H     = 168,     -- 一行高度
    ROW_GAP   = 10,
    CARD_W    = 104,     -- 敌人卡面宽
    CARD_H    = 132,     -- 敌人卡面高
    CARD_GAP  = 8,
    CARD_X    = 455,     -- 卡面区左缘（标签右侧）

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
        if SC.getStage(cur) then
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

--- 敌人卡面句柄缓存（懒加载，键=怪物 id）
---@type table<number, integer>
local monsterCards = {}

--- 取怪物卡面，失败不缓存，避免永久空白
---@param vg any
---@param monsterId number
---@return integer
local function ensureMonsterCard(vg, monsterId)
    local img = monsterCards[monsterId]
    if img and img >= 0 then return img end
    img = nvgCreateImage(vg, string.format("image/怪物卡牌/KP_GW_%d.png", monsterId), 0)
    if img and img >= 0 then
        monsterCards[monsterId] = img
        return img
    end
    monsterCards[monsterId] = nil
    return -1
end

--- 一关实际出场的敌人 id：常规怪 + 首领 + 首通附加怪
---@param entry table|nil
---@return number[]
local function stageMonsterIds(entry)
    local ids = {}
    if not entry then return ids end
    for _, monsterId in ipairs(entry.monsters or {}) do
        ids[#ids + 1] = monsterId
    end
    if entry.bossId and entry.bossId > 0 then
        ids[#ids + 1] = entry.bossId
    end
    local bonusIds = BattleEnemySpawn.getFirstClearBonusMonsterIds(entry)
    for _, monsterId in ipairs(bonusIds or {}) do
        ids[#ids + 1] = monsterId
    end
    return ids
end

local function currentStageId()
    if state.targetTeam then
        local BattleTriPage = require("ui.battle.tri.BattleTriPage")
        return BattleTriPage.getTeamStageId(state.targetTeam)
            or require("ui.battle.scene.BattleScene").getStageId()
    end
    return require("ui.battle.scene.BattleScene").getStageId()
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

---@param teamIdx number|nil 多队战斗行号；大于 1 时确认后切该队自己的关卡
function StageSelectDialog.open(teamIdx)
    if state.open then return end
    state.open     = true
    state.openTime = time.elapsedTime
    state.chDragY = nil
    state.chDragMoved = false
    state.targetTeam = teamIdx
    local BS = require("ui.battle.scene.BattleScene")
    local curStage = BS.getStageId()
    if state.targetTeam then
        local BattleTriPage = require("ui.battle.tri.BattleTriPage")
        curStage = BattleTriPage.getTeamStageId(state.targetTeam) or curStage
    end
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

    local groups, maxOrder = ensureCache()
    local curStage = currentStageId()
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

    -- ===================== 中栏：关卡竖排 + 敌人卡面 =====================
    nvgSave(vg)
    nvgIntersectScissor(vg, D.MID_X, D.ROW_Y0 - 4, D.MID_W, 5 * (D.ROW_H + D.ROW_GAP))
    for i, id in ipairs(sel.ids) do
        local y = D.ROW_Y0 + (i - 1) * (D.ROW_H + D.ROW_GAP)
        local x = D.MID_X
        local isCur = (id == curStage)
        local isBoss = SC.hasBoss(id) or SC.isTerminalTemple(id)
        local ord = state.cacheOrder and state.cacheOrder[id] or nil
        local locked = (ord == nil) or (maxOrder == nil) or (ord > maxOrder)
        local entry = SC.getStage(id)

        -- 行底
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, D.MID_W, D.ROW_H, 12)
        if isCur then
            nvgFillColor(vg, nvgRGBA(201, 151, 59, 40))
        else
            nvgFillColor(vg, nvgRGBA(0, 0, 0, locked and 70 or 40))
        end
        nvgFill(vg)
        if isCur then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x, y, D.MID_W, D.ROW_H, 12)
            nvgStrokeColor(vg, nvgRGBA(201, 151, 59, 235))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end

        -- 关卡号（行左上）
        local fr, fg, fb = 255, 255, 255
        if isBoss then fr, fg, fb = 0xE0, 0x5A, 0x5A end
        local txtA = locked and 140 or 255
        drawTextStroke(vg, x + 16, y + 34, shortStageLabel(id), 30,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            txtA, txtA, txtA, 3, { strokeColor = { fr, fg, fb } })

        -- 状态（行左下）
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
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if isCur then
            nvgFillColor(vg, nvgRGBA(0xC9, 0x97, 0x3B, 255))
        elseif locked then
            nvgFillColor(vg, nvgRGBA(0x8a, 0x84, 0x74, 220))
        else
            nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 255))
        end
        nvgText(vg, x + 16, y + D.ROW_H - 34, sub, nil)

        -- 敌人卡面（行右侧横排）
        local mids = stageMonsterIds(entry)
        local cardCY = y + D.ROW_H * 0.5
        for ci, monsterId in ipairs(mids) do
            local cardCX = D.CARD_X + (ci - 1) * (D.CARD_W + D.CARD_GAP) + D.CARD_W * 0.5
            local card = ensureMonsterCard(vg, monsterId)
            if card >= 0 then
                drawImageCover(vg, card, cardCX, cardCY, D.CARD_W, D.CARD_H, locked and 0.4 or 1.0)
            else
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cardCX - D.CARD_W * 0.5, cardCY - D.CARD_H * 0.5,
                    D.CARD_W, D.CARD_H, 8)
                nvgFillColor(vg, nvgRGBA(30, 26, 22, 200))
                nvgFill(vg)
            end
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cardCX - D.CARD_W * 0.5, cardCY - D.CARD_H * 0.5,
                D.CARD_W, D.CARD_H, 8)
            nvgStrokeColor(vg, nvgRGBA(201, 151, 59, locked and 90 or 200))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
    end
    nvgRestore(vg)

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
            return true
        end
    end

    -- 关卡行：点击直接前往，不再弹确认
    local sel = selectedGroup(groups)
    if sel then
        for i, id in ipairs(sel.ids) do
            local y0 = D.ROW_Y0 + (i - 1) * (D.ROW_H + D.ROW_GAP)
            if x >= D.MID_X and x <= D.MID_X + D.MID_W and y >= y0 and y <= y0 + D.ROW_H then
                BF.trigger("stage_sel_cell")
                local ord = state.cacheOrder and state.cacheOrder[id] or nil
                if (ord == nil) or (maxOrder == nil) or (ord > maxOrder) then
                    return true
                end
                if id == currentStageId() then return true end
                local ok
                if state.targetTeam then
                    local BattleTriPage = require("ui.battle.tri.BattleTriPage")
                    ok = BattleTriPage.gotoTeamStage(state.targetTeam, id)
                else
                    ok = BS.gotoStage(id)
                end
                if ok then StageSelectDialog.close() end
                print("[StageSelectDialog] 前往关卡: " .. tostring(id))
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
