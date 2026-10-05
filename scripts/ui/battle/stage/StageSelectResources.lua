-- 选关中的资源副本列表；不混入主线关卡链，通天塔使用独立入口。
local DC = require("config.DungeonConfig")
local DrawUtil = require("core.DrawUtil")
local I18n = require("core.I18n")
local ClientDispatcher = require("runtime.ClientDispatcher")

local M = {}
local X, Y, W, H, GAP = 105, 836, 790, 172, 18
local TOWER_Y = Y + 3 * (H + GAP) + 28
local images = {} ---@type table<string, integer>

local function image(vg, path)
    local cached = images[path]
    if cached and cached >= 0 then return cached end
    local loaded = nvgCreateImage(vg, path, 0) or -1
    if loaded >= 0 then images[path] = loaded end
    return loaded
end

local function text(vg, x, y, caption, size, width, color)
    local value = I18n.lookup(caption)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, size)
    while size > 18 and nvgTextBounds(vg, 0, 0, value) > width do
        size = size - 1
        nvgFontSize(vg, size)
    end
    DrawUtil.drawTextStroke(vg, x, y, value, size,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, color[1], color[2], color[3], 2)
end

local function unlocked(id, maxStage)
    return maxStage >= (DC.UNLOCK_CONDITIONS[id] or 0)
end

local function row(vg, id, name, path, reward, top, maxStage)
    local available = unlocked(id, maxStage)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, X, top, W, H, 14)
    nvgFillColor(vg, nvgRGBA(19, 17, 24, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(201, 151, 59, available and 170 or 70))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    local art = image(vg, path)
    if art >= 0 then
        nvgSave(vg)
        nvgIntersectScissor(vg, X + 4, top + 4, 238, H - 8)
        DrawUtil.drawImageCover(vg, art, X + 123, top + H * 0.5, 238, H - 8,
            available and 0.85 or 0.4)
        nvgRestore(vg)
    end
    local tx, tw = X + 264, W - 284
    local color = available and { 255, 222, 142 } or { 139, 149, 165 }
    text(vg, tx, top + 34, name, 34, tw, color)
    text(vg, tx, top + 76, reward, 26, tw, { 236, 226, 198 })
    local dungeon = ClientDispatcher.get("dungeon") or {}
    local sub = dungeon[id] or {}
    local floor = math.max(1, tonumber(sub.floor) or 1)
    local caption
    if available then
        caption = I18n.format("第 %d 层", floor)
    else
        local stageId = DC.UNLOCK_CONDITIONS[id] or 0
        caption = I18n.format("通关 %d-%d 解锁", math.floor(stageId / 100), stageId % 100)
    end
    text(vg, tx, top + 119, caption, 25, tw, color)
    if id == "babel_tower" then
        text(vg, tx, top + 150, "独立通天塔 · 三队攻坚", 21, tw, { 182, 176, 157 })
    end
end

function M.draw(vg, teamIdx, maxStage)
    for index, id in ipairs(DC.RESOURCE_IDS) do
        local def = DC.DEFINITIONS[id]
        local reward = id == "gold_mine" and "奖励：金币"
            or (id == "equipment_vault" and "奖励：装备" or "奖励：黑晶")
        row(vg, id, def.name, def.cardImage, reward, Y + (index - 1) * (H + GAP), maxStage)
    end
    row(vg, "babel_tower", "通天塔", "image/界面底板/副本秘境/UI_FBRK_3.png",
        "奖励：黑晶", TOWER_Y, maxStage)
    text(vg, X + 4, TOWER_Y + H + 37,
        I18n.format("资源副本使用队伍 %d；通天塔独立使用三队。", teamIdx),
        24, W - 8, { 201, 151, 59 })
end

function M.hit(x, y)
    if x < X or x > X + W then return nil end
    for index, id in ipairs(DC.RESOURCE_IDS) do
        local top = Y + (index - 1) * (H + GAP)
        if y >= top and y <= top + H then return id end
    end
    if y >= TOWER_Y and y <= TOWER_Y + H then return "babel_tower" end
    return nil
end

function M.release(vg)
    for _, handle in pairs(images) do nvgDeleteImage(vg, handle) end
    images = {}
end

return M
