-- 宝箱奖励的继续开启页脚；只扩展主动结果，不改普通/战斗奖励布局。
local RepeatButton = require("ui.widget.RepeatDrawButton")

local M = { EXTRA_HEIGHT = 100, HINT_Y = 1334 }
local BUTTON_Y, BUTTON_W, BUTTON_H = 1244, 440, 76
local CENTERS = { [1] = 304, [10] = 776 }

function M.hit(x, y)
    for _, count in ipairs({ 1, 10 }) do
        if RepeatButton.hit(x, y, CENTERS[count], BUTTON_Y, BUTTON_W, BUTTON_H) then return count end
    end
    return 0
end

-- getCost 每次读取当前余额，不使用上一次消费数量充当下一次报价。
function M.draw(vg, options, getIcon)
    for _, count in ipairs({ 1, 10 }) do
        local cost = options.getCost(count)
        local parts = {}
        for _, part in ipairs(cost.parts or {}) do
            parts[#parts + 1] = { icon = getIcon(part.type), type = part.type, amount = part.amount }
        end
        RepeatButton.draw(vg, CENTERS[count], BUTTON_Y, BUTTON_W, BUTTON_H,
            count == 1 and "继续单开" or "继续十连", parts, cost.enough, cost.freeText)
    end
end

return M
