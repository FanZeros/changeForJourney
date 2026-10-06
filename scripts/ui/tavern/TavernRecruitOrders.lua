-- TavernRecruitOrders.lua
-- 酒馆双竖招募令：入口数据、绘制和命中共用一份设计坐标。
-- 复用宿主 1080×2400 设计空间和既有 NanoVG frame，不创建上下文/UI 根。

local DrawUtil = require("core.DrawUtil")
local UrGachaConfig = require("config.UrGachaConfig")
local ClientDispatcher = require("runtime.ClientDispatcher")

local M = {}
M.POOL_ID_STANDARD = "standard"
M.POOL_ID_STELLAR = "stellar"
M.W, M.H = 450, 650

local STANDARD_PATH = "image/界面底板/酒馆抽卡/UI_TAVERN_RECRUIT_ORDER_STANDARD.png"
local TITLE_SIZE, TITLE_MAX_W = 40, 270
local TIME_Y, STATUS_Y = 383, 810

---@class TavernRecruitOrder
---@field id string
---@field name string
---@field timeText string
---@field cx number
---@field cy number
---@field textX number
---@field textY number
---@field imagePath string
---@field enabled boolean
---@field unlocked boolean

---@type table<string, number>
local images = {}
local inited = false

---@return TavernRecruitOrder[]
function M.createPools()
    return {
        {
            id = M.POOL_ID_STANDARD, name = "常规招募", timeText = "永久",
            cx = 275, cy = 545, textX = 275, textY = 345,
            imagePath = STANDARD_PATH, enabled = true, unlocked = true,
        },
        {
            id = M.POOL_ID_STELLAR, name = UrGachaConfig.POOL_NAME,
            timeText = UrGachaConfig.getTimeDisplayText(),
            cx = UrGachaConfig.UI.poolTabCx, cy = UrGachaConfig.UI.poolTabCy,
            textX = UrGachaConfig.UI.poolTextX, textY = UrGachaConfig.UI.poolTextY,
            imagePath = UrGachaConfig.UI.poolTabPath,
            enabled = UrGachaConfig.isPoolEnabled(), unlocked = false,
        },
    }
end

---@param pools TavernRecruitOrder[]
function M.refreshPoolMeta(pools)
    local stellar = pools[2]
    if not stellar then return end
    stellar.name = UrGachaConfig.POOL_NAME
    stellar.timeText = UrGachaConfig.getTimeDisplayText()
    stellar.cx, stellar.cy = UrGachaConfig.UI.poolTabCx, UrGachaConfig.UI.poolTabCy
    stellar.textX, stellar.textY = UrGachaConfig.UI.poolTextX, UrGachaConfig.UI.poolTextY
    local currency = ClientDispatcher.get("currency")
    local heroes = ClientDispatcher.get("heroes")
    stellar.enabled = UrGachaConfig.isPoolEnabled()
    stellar.unlocked = UrGachaConfig.checkPoolUnlocked(currency, heroes and heroes.roster,
        ClientDispatcher.get("battle"))
end

---@param pool TavernRecruitOrder
---@return boolean
function M.isVisible(pool)
    return pool.enabled == true
end

---@param vg any
---@param pools TavernRecruitOrder[]
function M.init(vg, pools)
    if inited then return end
    inited = true
    M.refreshPoolMeta(pools)
    for _, pool in ipairs(pools) do
        local handle = nvgCreateImage(vg, pool.imagePath, 0)
        images[pool.id] = (handle and handle >= 0) and handle or -1
        if images[pool.id] < 0 then
            print("[TavernRecruitOrders] WARNING: 招募令加载失败 " .. tostring(pool.imagePath))
        end
        print("[TavernRecruitOrders] init pool=" .. pool.id
            .. " center=" .. pool.cx .. "," .. pool.cy .. " size=" .. M.W .. "x" .. M.H
            .. " enabled=" .. tostring(pool.enabled) .. " unlocked=" .. tostring(pool.unlocked))
    end
end

--- 标题/状态均按当前语言实际量宽缩字号；字体使用宿主初始化的 sans。
---@param vg any
---@param cx number
---@param cy number
---@param text string
---@param size number
---@param maxW number
---@param r number
---@param g number
---@param b number
---@param alpha number|nil
local function drawLabel(vg, cx, cy, text, size, maxW, r, g, b, alpha)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, size)
    local textW = nvgTextBounds(vg, 0, 0, text)
    local font = (textW > maxW) and (size * maxW / textW) or size
    DrawUtil.drawTextStroke(vg, cx, cy, text, font,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, r, g, b, 3,
        { strokeColor = { 24, 20, 21 }, alpha = alpha or 1.0 })
end

---@param vg any
---@param cx number
---@param cy number
local function drawLock(vg, cx, cy)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, 0.65, 0.65)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -13, -25, 26, 32, 13)
    nvgStrokeColor(vg, nvgRGBA(169, 171, 179, 255))
    nvgStrokeWidth(vg, 5)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -21, -8, 42, 34, 5)
    nvgFillColor(vg, nvgRGBA(31, 31, 38, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(169, 171, 179, 255))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 4, 4)
    nvgFillColor(vg, nvgRGBA(169, 171, 179, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, -2, 6, 4, 10)
    nvgFill(vg)
    nvgRestore(vg)
end

---@param vg any
---@param pool TavernRecruitOrder
---@param selected boolean
local function drawOrder(vg, pool, selected)
    local x, y = pool.cx - M.W * 0.5, pool.cy - M.H * 0.5
    local handle = images[pool.id] or -1
    local locked = pool.unlocked == false
    local paperX, paperY = x + 68, y + 86
    local paperW, paperH = M.W - 136, M.H - 132
    if handle >= 0 then
        -- 正式素材 900×1300 → 450×650，整图等比，不复用横牌/旧选中图。
        DrawUtil.drawImageCentered(vg, handle, pool.cx, pool.cy, M.W, M.H, 1.0)
        if locked then
            -- 使用同图 alpha 作暗罩，透明外缘保持透明，不画矩形黑底盖住酒馆。
            local shade = nvgRGBA(0, 0, 0, 164) --[[@as NVGcolor]]
            local paint = nvgImagePatternTinted(vg, x, y, M.W, M.H, 0, handle, shade) --[[@as NVGpaint]]
            nvgBeginPath(vg)
            nvgRect(vg, x, y, M.W, M.H)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    else
        -- 缺图仅初始化时记录；仍提供同位置的可见入口，不在每帧重载/刷日志。
        nvgBeginPath(vg)
        nvgRoundedRect(vg, paperX, paperY, paperW, paperH, 12)
        nvgFillColor(vg, locked and nvgRGBA(19, 19, 25, 255) or nvgRGBA(51, 36, 31, 255))
        nvgFill(vg)
    end

    if selected and not locked then
        -- 一层克制金边；锁定优先，不把未开放池误标成当前池。
        nvgBeginPath(vg)
        nvgRoundedRect(vg, paperX, paperY, paperW, paperH, 12)
        nvgStrokeColor(vg, nvgRGBA(214, 176, 101, 230))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end

    drawLabel(vg, pool.textX, pool.textY, pool.name, TITLE_SIZE, TITLE_MAX_W,
        248, 235, 205, locked and 0.8 or 1.0)
    drawLabel(vg, pool.cx, TIME_Y, pool.timeText, 18, TITLE_MAX_W,
        221, 207, 183, locked and 0.65 or 1.0)

    if locked then
        drawLock(vg, pool.cx + 136, 331)
        drawLabel(vg, pool.cx, 760, "未解锁", 30, TITLE_MAX_W, 187, 188, 198)
        drawLabel(vg, pool.cx, 805, "进入地狱难度后开放", 23, TITLE_MAX_W, 170, 172, 184)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, pool.cx - 84, STATUS_Y - 25, 168, 50, 8)
        nvgFillColor(vg, nvgRGBA(22, 19, 22, 215))
        nvgFill(vg)
        if selected then
            drawLabel(vg, pool.cx, STATUS_Y, "当前", 28, 140, 246, 213, 139)
        else
            drawLabel(vg, pool.cx, STATUS_Y, "选择", 28, 140, 206, 198, 184)
        end
    end
end

---@param vg any
---@param pools TavernRecruitOrder[]
---@param selectedPool number
function M.draw(vg, pools, selectedPool)
    nvgSave(vg)
    for i, pool in ipairs(pools) do
        if M.isVisible(pool) then drawOrder(vg, pool, i == selectedPool) end
    end
    nvgRestore(vg)
end

--- 与绘制共享 enabled 和整牌热区；仅返回入口，不发送招募/消费请求。
---@param dx number 宿主已转换的设计坐标
---@param dy number
---@param pools TavernRecruitOrder[]
---@return integer|nil index
---@return TavernRecruitOrder|nil pool
function M.hitTest(dx, dy, pools)
    for i, pool in ipairs(pools) do
        if M.isVisible(pool) and DrawUtil.hitTest(dx, dy, pool.cx, pool.cy, M.W, M.H) then
            return i, pool
        end
    end
    return nil, nil
end

return M
