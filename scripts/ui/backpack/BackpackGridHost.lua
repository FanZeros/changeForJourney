-- 仓库网格宿主适配：惰性绑定、滚动边界、预算队列生命周期。
-- 不订阅全局 Update；由 BackpackPanel.update 唯一驱动。
local Grids = require("ui.backpack.BackpackGrids")
local M = {}
function M.bind(deps)
    local grids = nil
    local api = {}
    function api.calcScrollMax(totalItems)
        local grid = deps.GRID
        local rows = math.ceil(totalItems / grid.COLS)
        return math.max(0, rows * grid.CELL_SIZE + math.max(0, rows - 1) * grid.GAP
            - (grid.CLIP_BOTTOM - grid.FIRST_ROW_TOP))
    end
    function api.clampScroll()
        local state = deps.state
        state.scrollY = math.max(0, math.min(state.scrollMax, state.scrollY))
    end
    local function ensure()
        if not grids then
            deps.calcScrollMax, deps.clampScroll = api.calcScrollMax, api.clampScroll
            grids = Grids.bind(deps)
        end
        return grids
    end
    function api.getEquipList() return ensure().getPresentedEquipList() end
    function api.getSetCounts() return ensure().getSetCounts() end
    function api.buildItemList() return ensure().buildItemList() end
    function api.drawEquipGrid(vg) ensure().drawEquipGrid(vg) end
    function api.drawItemGrid(vg) ensure().drawItemGrid(vg) end
    function api.cancel() if grids then grids.cancel() end end
    function api.update()
        if deps.state.open and not deps.state.closing and deps.state.tab == "equip" then
            ensure().update()
        else
            api.cancel()
        end
    end
    return api
end
return M
