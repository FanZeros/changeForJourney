-- 剧情环境只负责资源归属，不改变情景编号、台词、奖励或关卡状态。
local StageConfig = require("config.StageConfig")
local M = {}

M.STUDY = "image/剧情/背景/STORY_BG_01.png"
M.HALL = "image/剧情/背景/STORY_BG_02.png"
M.DEFAULT = "image/剧情/背景/STORY_BG_03.png"

local function path(index)
    return string.format("image/剧情/背景/STORY_BG_%02d.png", index)
end

local SCENES = {}
local function assign(first, last, index)
    for id = first, last do SCENES[id] = path(index) end
end
assign(1, 4, 2)
assign(5, 19, 3)
assign(20, 22, 4)
assign(23, 26, 5)
assign(27, 27, 6)
assign(28, 30, 5)
assign(31, 31, 7)
assign(32, 34, 5)
assign(35, 37, 9)
assign(38, 40, 3) -- 失败时由事件捕获的关卡环境覆盖，不能固定为第二章。
assign(41, 46, 9)
assign(47, 47, 8)
assign(48, 50, 5)
assign(51, 53, 10)
assign(55, 57, 13)
assign(58, 60, 12)
assign(61, 62, 14)
assign(63, 63, 3)
assign(64, 64, 10)
assign(65, 65, 15)
assign(67, 67, 16)
assign(68, 69, 14)
assign(70, 71, 3)
assign(72, 72, 10)
assign(73, 73, 11)
assign(74, 81, 17)
assign(82, 82, 10)

---@param id number
---@return string|nil
function M.forScenario(id)
    return SCENES[id]
end

-- 未制作剧情专图的章节沿用同地域正式战斗图；只作临时失败背景，不改战区素材。
local CHAPTERS = {
    [1] = path(3), [2] = path(10), [3] = path(11), [4] = path(15),
    [5] = "image/战斗背景/哀嚎沙丘.png", [6] = path(16),
    [7] = "image/战斗背景/焦土平原.png", [8] = "image/战斗背景/断魂裂谷.png",
    [9] = "image/战斗背景/蛊语山洞.png", [10] = "image/战斗背景/悬魂瀑布.png",
    [11] = "image/战斗背景/霜噬雪岭.png", [12] = "image/战斗背景/沉眠冰原.png",
    [13] = path(13), [14] = "image/战斗背景/枯枫遗迹.png",
    [15] = "image/战斗背景/烬暮湖畔.png", [16] = "image/战斗背景/废弃营地.png",
    [17] = "image/战斗背景/古代遗迹.png", [18] = "image/战斗背景/沉没神殿.png",
    [19] = "image/战斗背景/哭泣峭壁.png", [20] = "image/战斗背景/恶灵岔路.png",
    [21] = "image/战斗背景/遗忘墓穴.png", [22] = "image/战斗背景/亡灵墓穴.png",
    [23] = "image/战斗背景/烛龙之巢.png",
}

---@param stageId number|string|nil
---@return string
function M.forStage(stageId)
    local id = tonumber(stageId) or 0
    if StageConfig.isTerminalTemple(id) then return path(14) end
    local entry = StageConfig.getStage(id)
    local chapter = entry and entry.chapter or 1
    return CHAPTERS[((chapter - 1) % 23) + 1] or M.DEFAULT
end

return M
