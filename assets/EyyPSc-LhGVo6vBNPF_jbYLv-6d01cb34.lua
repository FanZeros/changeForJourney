-- ============================================================================
-- StageSelectDialog - 主线选关弹窗
-- 入口：战斗界面 HUD「选关」按钮（与扫荡/统计同套图标按钮）
-- 面板：复用 SweepDialog 九宫格 + 弹性缩放 + 点击空白关闭
-- ============================================================================

local GameConfig        = require("config.GameConfig")
local SC                = require("config.StageConfig")
local DrawUtil          = require("core.DrawUtil")
local BF                = require("systems.ButtonFeedback")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice

local StageSelectDialog = {}

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- 入口按钮（设计坐标，与扫荡/统计同一套尺寸）
-- 扫荡 (971, 2115) / 统计 (815, 2115) / 选关放统计左侧
local BTN_CX = 659
local BTN_CY = 2115
local BTN_W  = 130
local BTN_H  = 144

local D = {
    OVL_A   = 128,

    BG_CX   = 540,  BG_CY  = 1195,
    BG_W    = 950,  BG_H   = 1117,
    BG_IT   = 180,  BG_IR  = 40,  BG_IB = 50,  BG_IL = 40,

    TT_Y    = 705,  TT_FONT = 60,  TT_SW = 6,
    TT_SR   = 0x46, TT_SG  = 0x2f, TT_SB = 0x20,

    SUB_Y   = 800,  SUB_FONT = 34,
    SUB_R   = 0xb6, SUB_G  = 0xb0, SUB_B = 0x9d,

    -- 当前关卡信息条
    CUR_BG_CX = 540, CUR_BG_CY = 888,
    CUR_BG_W  = 800, CUR_BG_H  = 72, CUR_BG_R = 16, CUR_BG_A = 18,
    CUR_LBL_X = 169, CUR_VAL_X = 904,
    CUR_FONT  = 36,
    CUR_LBL_R = 0x8d, CUR_LBL_G = 0x5f, CUR_LBL_B = 0x41,

    -- 关卡网格
    COLS      = 4,
    ROWS      = 4,
    CELL_W    = 186,
    CELL_H    = 92,
    CELL_GAPX = 14,
    CELL_GAPY = 12,
    GRID_CX   = 540,
    GRID_Y0   = 948,   -- 第一行顶边

    -- 翻页
    PAGE_Y    = 1608,
    PAGE_FONT = 32,
    ARROW_W   = 160,
    ARROW_H   = 64,
}

local PER_PAGE = D.COLS * D.ROWS

local ANIM_OPEN_DUR = 0.18

local imgBtn = -1
local imgBg  = -1
local imgAct = -1

local state = {
    open     = false,
    openTime = 0,
    page     = 0,
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

--- 沿官方关卡链收集至 maxStage（含终焉神殿，不用数值比较截断）
local function collectExistIds(maxStage)
    local ids = {}
    ---@type table<number, boolean>
    local seen = {}
    local cur = SC.NORMAL_FIRST_STAGE or 101
    local guard = 0
    while cur and guard < 2000 do
        guard = guard + 1
        if seen[cur] then break end
        seen[cur] = true
        if SC.getStage(cur) then
            ids[#ids + 1] = cur
        end
        if cur == maxStage then break end
        local nxt = SC.getNextStageId(cur)
        if not nxt and SC.isTerminalTemple(cur) then
            nxt = SC.getReincarnationTarget(SC.getDifficulty(cur))
        end
        if not nxt then break end
        cur = nxt
    end
    return ids
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

local function gridOrigin()
    local totalW = D.COLS * D.CELL_W + (D.COLS - 1) * D.CELL_GAPX
    local x0 = D.GRID_CX - totalW * 0.5
    return x0, D.GRID_Y0
end

local function cellRect(indexOnPage)
    local col = (indexOnPage - 1) % D.COLS
    local row = math.floor((indexOnPage - 1) / D.COLS)
    local x0, y0 = gridOrigin()
    local x = x0 + col * (D.CELL_W + D.CELL_GAPX)
    local y = y0 + row * (D.CELL_H + D.CELL_GAPY)
    return x, y, D.CELL_W, D.CELL_H
end

-- ======================== Public API ========================

---@param vg any
function StageSelectDialog.init(vg)
    imgBtn = nvgCreateImage(vg, "image/UI_ICON_XG.png", 0)
    imgBg  = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    imgAct = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    print("[StageSelectDialog] init OK")
end

function StageSelectDialog.open()
    if state.open then return end
    state.open     = true
    state.openTime = time.elapsedTime
    -- 打开时定位到当前关卡所在页
    local BS = require("ui.BattleScene")
    local maxStage = BS.getMaxStageId()
    if not maxStage or maxStage < 1 then
        maxStage = SC.NORMAL_FIRST_STAGE or 101
    end
    local curStage = BS.getStageId() or maxStage
    local ids = collectExistIds(maxStage)
    local idx = 1
    for i = 1, #ids do
        if ids[i] == curStage then idx = i; break end
    end
    state.page = math.max(0, math.floor((idx - 1) / PER_PAGE))
end

function StageSelectDialog.close()
    state.open = false
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

-- ======================== 绘制入口按钮 ========================

---@param vg any
function StageSelectDialog.drawButton(vg)
    local _ds = BF.begin(vg, "stage_sel_btn", BTN_CX, BTN_CY, BTN_W, BTN_H)
    if imgBtn >= 0 then
        drawImageCentered(vg, imgBtn, BTN_CX, BTN_CY, BTN_W, BTN_H, 1.0)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, BTN_CX - BTN_W * 0.5, BTN_CY - BTN_H * 0.5, BTN_W, BTN_H, 18)
        nvgFillColor(vg, nvgRGBA(201, 151, 59, 230))
        nvgFill(vg)
    end
    drawTextStroke(vg, BTN_CX, 2174, "选关", 32,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
    BF.finish(vg, _ds)
end

-- ======================== 绘制弹窗 ========================

---@param vg any
function StageSelectDialog.draw(vg)
    if not state.open then return end
    local scale = getAnimScale()
    if scale <= 0.01 then return end

    local BS = require("ui.BattleScene")
    local maxStage = BS.getMaxStageId()
    if not maxStage or maxStage < 1 then
        maxStage = SC.NORMAL_FIRST_STAGE or 101
    end
    local curStage = BS.getStageId() or maxStage
    local ids = collectExistIds(maxStage)
    local maxPage = math.max(0, math.ceil(#ids / PER_PAGE) - 1)
    if state.page > maxPage then state.page = maxPage end
    if state.page < 0 then state.page = 0 end

    local ovlAlpha = math.floor(D.OVL_A * math.min(scale * 2, 1.0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, ovlAlpha))
    nvgFill(vg)

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

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, D.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(D.SUB_R, D.SUB_G, D.SUB_B, 255))
    nvgText(vg, D.BG_CX, D.SUB_Y, "点击已解锁关卡即可切换", nil)

    -- 当前关卡条
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        D.CUR_BG_CX - D.CUR_BG_W * 0.5, D.CUR_BG_CY - D.CUR_BG_H * 0.5,
        D.CUR_BG_W, D.CUR_BG_H, D.CUR_BG_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, D.CUR_BG_A))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, D.CUR_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(D.CUR_LBL_R, D.CUR_LBL_G, D.CUR_LBL_B, 255))
    nvgText(vg, D.CUR_LBL_X, D.CUR_BG_CY, "当前关卡", nil)

    local curName = SC.formatProgressDisplay(curStage)
    drawTextStroke(vg, D.CUR_VAL_X, D.CUR_BG_CY, curName,
        D.CUR_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        0x63, 0xff, 0x84, 5, { strokeColor = { 0, 0, 0 } })

    -- 关卡格子
    local startIdx = state.page * PER_PAGE
    for i = 1, PER_PAGE do
        local id = ids[startIdx + i]
        if id then
            local x, y, w, h = cellRect(i)
            local cx, cy = x + w * 0.5, y + h * 0.5
            local isCur = (id == curStage)
            local isBoss = SC.hasBoss(id) or SC.isTerminalTemple(id)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, x, y, w, h, 14)
            if isCur then
                nvgFillColor(vg, nvgRGBA(201, 151, 59, 48))
            else
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 22))
            end
            nvgFill(vg)
            if isCur then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, x, y, w, h, 14)
                nvgStrokeColor(vg, nvgRGBA(201, 151, 59, 230))
                nvgStrokeWidth(vg, 3)
                nvgStroke(vg)
            end

            local label = shortStageLabel(id)
            local fr, fg, fb = 0x46, 0x2f, 0x20
            if isCur then
                fr, fg, fb = 0x8d, 0x5f, 0x41
            elseif isBoss then
                fr, fg, fb = 0x8a, 0x3a, 0x28
            end
            drawTextStroke(vg, cx, cy - 12, label, 30,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4, { strokeColor = { fr, fg, fb } })

            local sub
            if isCur then
                sub = "当前"
            elseif SC.isTerminalTemple(id) then
                sub = "神殿"
            elseif isBoss then
                sub = "首领"
            else
                sub = SC.getDifficultyDisplayName(SC.getDifficulty(id))
            end
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if isCur then
                nvgFillColor(vg, nvgRGBA(0x8d, 0x5f, 0x41, 255))
            else
                nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 255))
            end
            nvgText(vg, cx, cy + 22, sub, nil)
        end
    end

    -- 翻页
    local pageStr = string.format("%d / %d", state.page + 1, maxPage + 1)
    drawTextStroke(vg, D.BG_CX, D.PAGE_Y, pageStr, D.PAGE_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4, { strokeColor = { 0x46, 0x2f, 0x20 } })

    if imgAct >= 0 then
        if state.page > 0 then
            drawImageCentered(vg, imgAct, D.BG_CX - 280, D.PAGE_Y, D.ARROW_W, D.ARROW_H, 1.0)
            nvgFontFace(vg, "sans"); nvgFontSize(vg, 28)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 178))
            nvgText(vg, D.BG_CX - 280, D.PAGE_Y, "上一页", nil)
        end
        if state.page < maxPage then
            drawImageCentered(vg, imgAct, D.BG_CX + 280, D.PAGE_Y, D.ARROW_W, D.ARROW_H, 1.0)
            nvgFontFace(vg, "sans"); nvgFontSize(vg, 28)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 178))
            nvgText(vg, D.BG_CX + 280, D.PAGE_Y, "下一页", nil)
        end
    else
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x46, 0x2f, 0x20, 220))
        if state.page > 0 then nvgText(vg, D.BG_CX - 280, D.PAGE_Y, "上一页", nil) end
        if state.page < maxPage then nvgText(vg, D.BG_CX + 280, D.PAGE_Y, "下一页", nil) end
    end

    nvgRestore(vg)
end

-- ======================== 输入 ========================

---@param x number
---@param y number
---@return boolean
function StageSelectDialog.handleInput(x, y)
    if not state.open then return false end

    local BS = require("ui.BattleScene")
    local maxStage = BS.getMaxStageId()
    if not maxStage or maxStage < 1 then
        maxStage = SC.NORMAL_FIRST_STAGE or 101
    end
    local ids = collectExistIds(maxStage)
    local maxPage = math.max(0, math.ceil(#ids / PER_PAGE) - 1)

    -- 翻页
    if state.page > 0 and hitTestRect(x, y, D.BG_CX - 280, D.PAGE_Y, D.ARROW_W, D.ARROW_H) then
        BF.trigger("stage_sel_prev")
        state.page = state.page - 1
        return true
    end
    if state.page < maxPage and hitTestRect(x, y, D.BG_CX + 280, D.PAGE_Y, D.ARROW_W, D.ARROW_H) then
        BF.trigger("stage_sel_next")
        state.page = state.page + 1
        return true
    end

    -- 关卡格子
    local startIdx = state.page * PER_PAGE
    for i = 1, PER_PAGE do
        local id = ids[startIdx + i]
        if id then
            local cx0, cy0, w, h = cellRect(i)
            if x >= cx0 and x <= cx0 + w and y >= cy0 and y <= cy0 + h then
                BF.trigger("stage_sel_cell")
                local ok = BS.gotoStage(id)
                if ok then StageSelectDialog.close() end
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
