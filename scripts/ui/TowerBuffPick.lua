-- ============================================================================
-- TowerBuffPick - 通天塔三选一强化面板
-- 全屏遮罩 + 标题 + 3个强化卡片供玩家点击选择
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local BF       = require("systems.ButtonFeedback")
local Protocol = require("shared.Protocol")

local Panel = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

-- ======================== 布局常量 ========================

-- 1. 全屏遮罩
local MASK_A = 128  -- 纯黑50%

-- 2. 标题 "通天塔"（左对齐 X=82）
local TITLE = { X = 82, Y = 410, FONT = 50, SW = 6 }

-- 3. 层数 "第X层"（斜体，与通天塔左对齐 X=82）
local FLOOR_TEXT = { X = 82, Y = 500, FONT = 80, SW = 6, SKEW = -12 }

-- 4. 提示 "选择一项强化"
local HINT = { X = 869, Y = 515, FONT = 50, SW = 6 }

-- 5. 强化卡片布局（以第一张卡片为基准）
local CARD = {
    CX = 540, FIRST_CY = 744,  -- 第一张卡片中心
    W = 998, H = 321,
    GAP = 47,                    -- 卡片间距
    -- 名称（相对卡片左上角偏移）
    NAME_X = 103, NAME_Y_OFF = 47,  -- 相对card top
    NAME_FONT = 50, NAME_SW = 5,
    NAME_STROKE_R = 0x3f, NAME_STROKE_G = 0x3f, NAME_STROKE_B = 0x3f,
    -- 品质文本
    QUALITY_X = 949, QUALITY_Y_OFF = 46,
    QUALITY_FONT = 50, QUALITY_SW = 5,
    -- 介绍文本段落区域（中心Y=782相对屏幕，转为相对card top的偏移）
    DESC_CX = 540, DESC_Y_OFF = 140,  -- 区域顶边相对card top
    DESC_W = 864, DESC_H = 117,
    DESC_FONT = 38,
    DESC_R = 0x5f, DESC_G = 0x37, DESC_B = 0x37,
}
CARD.STEP = CARD.H + CARD.GAP  -- 368

-- 品质显示映射（强化品质1/2/3 → 稀有/史诗/传说）
local QUALITY_DISPLAY = {
    [1] = { name = "稀有", r = 0x72, g = 0xf2, b = 0xf5 },  -- 蓝色
    [2] = { name = "史诗", r = 0xef, g = 0x79, b = 0xff },  -- 紫色
    [3] = { name = "传说", r = 0xff, g = 0xed, b = 0x00 },  -- 金色
}

-- ======================== 图片句柄 ========================

local imgCardBg = {}  -- UI_TTTSXY_1/2/3.png

-- ======================== 状态 ========================

local state = {
    open = false,
    floor = 1,
    choices = {},     -- { {id, quality, name, desc}, ... } 最多3个
    onPick = nil,     -- function(buffId) 回调
}

-- NanoVG 上下文
local vg_ = nil

-- ======================== sendAction 注入 ========================

---@type fun(action: string, params: table)|nil
local sendAction_ = nil

function Panel.setSendAction(fn)
    sendAction_ = fn
end

-- ======================== Public API ========================

function Panel.init(vg)
    vg_ = vg
    for i = 1, 3 do
        imgCardBg[i] = nvgCreateImage(vg, "image/UI_TTTSXY_" .. i .. ".png", 0)
    end
end

--- 打开面板，展示三选一
---@param floor number 当前层数
---@param choices table[] 强化选项列表 { {id, quality, name, desc}, ... }
---@param onPick function|nil 选择后的回调 function(buffId)
function Panel.open(floor, choices, onPick)
    state.open = true
    state.floor = floor or 1
    state.choices = choices or {}
    state.onPick = onPick
    print("[TowerBuffPick] open floor=" .. state.floor .. " choices=" .. #state.choices)
end

function Panel.close()
    state.open = false
    state.choices = {}
    state.onPick = nil
end

function Panel.isOpen()
    return state.open
end

-- ======================== 渲染 ========================

function Panel.draw(vg)
    if not state.open then return end

    -- 1. 全屏遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, MASK_A))
    nvgFill(vg)

    -- 2. 标题 "通天塔"（左对齐 X=82）
    DrawUtil.drawTextStroke(vg, TITLE.X, TITLE.Y, "通天塔",
        TITLE.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, TITLE.SW,
        { strokeColor = { 0, 0, 0 } })

    -- 3. 层数 "第X层"（斜体，左对齐与通天塔对齐）
    nvgSave(vg)
    nvgTranslate(vg, FLOOR_TEXT.X, FLOOR_TEXT.Y)
    nvgSkewX(vg, FLOOR_TEXT.SKEW * math.pi / 180)
    DrawUtil.drawTextStroke(vg, 0, 0, "第" .. state.floor .. "层",
        FLOOR_TEXT.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, FLOOR_TEXT.SW,
        { strokeColor = { 0, 0, 0 } })
    nvgRestore(vg)

    -- 4. 提示 "选择一项强化"
    DrawUtil.drawTextStroke(vg, HINT.X, HINT.Y, "选择一项强化",
        HINT.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, HINT.SW,
        { strokeColor = { 0, 0, 0 } })

    -- 5. 强化卡片
    for i, choice in ipairs(state.choices) do
        local cardCY = CARD.FIRST_CY + (i - 1) * CARD.STEP
        local cardTop = cardCY - CARD.H * 0.5
        local cardLeft = CARD.CX - CARD.W * 0.5

        -- 按钮反馈
        local _bf = BF.begin(vg, "tower_buff_" .. i, CARD.CX, cardCY, CARD.W, CARD.H)

        -- 5.1) 卡片背景（按品质选图）
        local bgIdx = math.min(math.max(choice.quality or 1, 1), 3)
        local bgImg = imgCardBg[bgIdx]
        if bgImg and bgImg > 0 then
            DrawUtil.drawImageCentered(vg, bgImg, CARD.CX, cardCY, CARD.W, CARD.H, 1.0)
        end

        -- 5.2) 强化名称（左对齐）
        local nameY = cardTop + CARD.NAME_Y_OFF
        DrawUtil.drawTextStroke(vg, CARD.NAME_X, nameY, choice.name or "",
            CARD.NAME_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            255, 255, 255, CARD.NAME_SW,
            { strokeColor = { CARD.NAME_STROKE_R, CARD.NAME_STROKE_G, CARD.NAME_STROKE_B } })

        -- 5.3) 品质文本（右侧）
        local qDisplay = QUALITY_DISPLAY[choice.quality] or QUALITY_DISPLAY[1]
        local qualityY = cardTop + CARD.QUALITY_Y_OFF
        DrawUtil.drawTextStroke(vg, CARD.QUALITY_X, qualityY, qDisplay.name,
            CARD.QUALITY_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
            qDisplay.r, qDisplay.g, qDisplay.b, CARD.QUALITY_SW,
            { strokeColor = { CARD.NAME_STROKE_R, CARD.NAME_STROKE_G, CARD.NAME_STROKE_B } })

        -- 5.4) 介绍文本段落区域
        local descY = cardTop + CARD.DESC_Y_OFF
        local descLeft = CARD.DESC_CX - CARD.DESC_W * 0.5
        nvgSave(vg)
        nvgScissor(vg, descLeft, descY, CARD.DESC_W, CARD.DESC_H)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, CARD.DESC_FONT)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(CARD.DESC_R, CARD.DESC_G, CARD.DESC_B, 255))
        nvgTextBox(vg, descLeft, descY, CARD.DESC_W, choice.desc or "", nil)
        nvgResetScissor(vg)
        nvgRestore(vg)

        BF.finish(vg, _bf)
    end
end

-- ======================== 输入处理 ========================

function Panel.handleClick(dx, dy)
    if not state.open then return false end

    -- 检测点击了哪张卡片
    for i, choice in ipairs(state.choices) do
        local cardCY = CARD.FIRST_CY + (i - 1) * CARD.STEP
        if DrawUtil.hitTest(dx, dy, CARD.CX, cardCY, CARD.W, CARD.H) then
            BF.trigger("tower_buff_" .. i)
            print("[TowerBuffPick] picked #" .. i .. " buffId=" .. (choice.id or "nil") .. " name=" .. (choice.name or ""))

            -- 先保存回调引用，然后立即关闭面板（防止回调出错时面板卡死）
            local pickFn = state.onPick
            Panel.close()

            -- 发送选择请求
            if sendAction_ then
                sendAction_(Protocol.ACTION_TYPES.TOWER_PICK_BUFF, { buffId = choice.id })
            end

            -- 回调（即使出错也不影响面板关闭）
            if pickFn then
                local ok, err = pcall(pickFn, choice.id)
                if not ok then
                    print("[TowerBuffPick] ERROR in onPick callback: " .. tostring(err))
                end
            end

            return true
        end
    end

    -- 点击空白区域不关闭（强制选择）
    return true
end

return Panel
