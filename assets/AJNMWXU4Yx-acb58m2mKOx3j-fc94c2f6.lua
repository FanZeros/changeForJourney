-- ============================================================================
-- RelicGrid.lua — 遗物网格放置逻辑
--
-- 职责:
--   1. 维护 8x8 网格的占用状态
--   2. 判断指定位置是否可放置某类型遗物
--   3. 执行放置/移除操作（标记/释放格子）
--   4. 搜索所有合法放置位置（供 UI 高亮提示）
--
-- 坐标约定:
--   row: 1~GRID_ROWS (从上到下)
--   col: 1~GRID_COLS (从左到右)
--   cells 偏移: {rowOffset, colOffset}，锚点为放置位置 (row, col)
--
-- 数据来源:
--   通过 RelicSystem.getGrid() 获取已镶嵌遗物列表
--   每个遗物的 row/col/rotation 记录锚点位置和旋转状态
-- ============================================================================

local RelicDefs = require("data.RelicDefs")

---@class RelicGrid
local RelicGrid = {}

-- ======================== 常量 ========================

RelicGrid.GRID_ROWS = 10
RelicGrid.GRID_COLS = 8

-- 格子状态
local CELL_EMPTY    = 0   -- 空闲
local CELL_OCCUPIED = 1   -- 被遗物占据

-- ======================== 旋转辅助 ========================

--- 将 cells 顺时针旋转 90 度: {r,c} → {c,-r}
local function rotateCells90(cells)
    local result = {}
    for i, cell in ipairs(cells) do
        result[i] = { cell[2], -cell[1] }
    end
    return result
end

--- 获取旋转后的 cell 偏移列表
---@param relicType number
---@param rotation number 0~7 (0-3正常旋转, 4-7翻转+旋转)
---@return number[][] offsets 每项 {rowOffset, colOffset}
function RelicGrid.getRotatedCellOffsets(relicType, rotation)
    local typeDef = RelicDefs.TYPES[relicType]
    if not typeDef then return {} end

    rotation = rotation or 0
    local flipped = rotation >= 4

    local cells = {}
    for i, c in ipairs(typeDef.cells) do
        cells[i] = { c[1], c[2] }
    end

    -- 先翻转（水平镜像：列取反）
    if flipped then
        for i, cell in ipairs(cells) do
            cells[i] = { cell[1], -cell[2] }
        end
    end

    -- 再旋转
    for _ = 1, rotation % 4 do
        cells = rotateCells90(cells)
    end
    return cells
end

-- ======================== 网格状态管理 ========================

--- 根据已镶嵌遗物列表构建网格状态矩阵
--- 每次需要判断时重新构建，保证与 PlayerStore 数据一致
---@param gridRelics table[] 已镶嵌的遗物列表（每个有 type, gridPos）
---@return number[][] matrix [row][col] = CELL_EMPTY | relicId_hash
---@return table<string, table> occupancy relicId → { cells={{row,col},...} }
function RelicGrid.buildMatrix(gridRelics)
    -- 初始化空矩阵
    local matrix = {}
    for r = 1, RelicGrid.GRID_ROWS do
        matrix[r] = {}
        for c = 1, RelicGrid.GRID_COLS do
            matrix[r][c] = CELL_EMPTY
        end
    end

    -- 遗物占用映射
    local occupancy = {}

    if not gridRelics then return matrix, occupancy end

    for _, relic in ipairs(gridRelics) do
        local anchorRow = relic.row
        local anchorCol = relic.col
        if anchorRow and anchorCol and relic.type then
            local offsets = RelicGrid.getRotatedCellOffsets(relic.type, relic.rotation or 0)

            if #offsets > 0 then
                local cells = {}
                for _, offset in ipairs(offsets) do
                    local r = anchorRow + offset[1]
                    local c = anchorCol + offset[2]
                    if r >= 1 and r <= RelicGrid.GRID_ROWS and c >= 1 and c <= RelicGrid.GRID_COLS then
                        matrix[r][c] = CELL_OCCUPIED
                        cells[#cells + 1] = { r, c }
                    end
                end
                occupancy[relic.id] = { cells = cells, anchor = { anchorRow, anchorCol } }
            end
        end
    end

    return matrix, occupancy
end

-- ======================== 放置校验 ========================

--- 判断指定类型遗物是否可放置到 (row, col) 位置
---@param relicType number 遗物类型 (1-5)
---@param row number 锚点行 (1~GRID_ROWS)
---@param col number 锚点列 (1~GRID_COLS)
---@param matrix number[][]|nil 网格矩阵（nil则自动构建）
---@param gridRelics table[]|nil 已镶嵌遗物列表（matrix为nil时需要）
---@param rotation number|nil 旋转次数 (0~3)，默认 0
---@return boolean canPlace
---@return string|nil reason 失败原因
function RelicGrid.canPlace(relicType, row, col, matrix, gridRelics, rotation)
    -- 类型校验
    local typeDef = RelicDefs.TYPES[relicType]
    if not typeDef then
        return false, "无效的遗物类型"
    end

    -- 自动构建矩阵
    if not matrix then
        if not gridRelics then
            local RelicSystem = require("systems.RelicSystem")
            gridRelics = RelicSystem.getGrid()
        end
        matrix = RelicGrid.buildMatrix(gridRelics)
    end

    -- 获取旋转后的 cell 偏移
    local offsets = RelicGrid.getRotatedCellOffsets(relicType, rotation or 0)

    -- 检查每个格子是否在边界内且空闲
    for _, offset in ipairs(offsets) do
        local r = row + offset[1]
        local c = col + offset[2]

        -- 边界检查
        if r < 1 or r > RelicGrid.GRID_ROWS then
            return false, "超出网格边界(行)"
        end
        if c < 1 or c > RelicGrid.GRID_COLS then
            return false, "超出网格边界(列)"
        end

        -- 占用检查
        if matrix[r][c] ~= CELL_EMPTY then
            return false, "位置已被占用"
        end
    end

    return true, nil
end

--- 判断指定遗物是否可放置到 (row, col)（含锁定检查）
---@param relic table 遗物实例
---@param row number
---@param col number
---@param matrix number[][]|nil
---@param gridRelics table[]|nil
---@return boolean canPlace, string|nil reason
function RelicGrid.canPlaceRelic(relic, row, col, matrix, gridRelics)
    if not relic then return false, "遗物不存在" end
    if not relic.type then return false, "遗物类型无效" end
    return RelicGrid.canPlace(relic.type, row, col, matrix, gridRelics)
end

-- ======================== 合法位置搜索 ========================

--- 搜索指定类型遗物的所有合法放置位置
--- 用于 UI 高亮提示可放置的区域
---@param relicType number 遗物类型 (1-5)
---@param gridRelics table[]|nil 已镶嵌遗物列表
---@return {row:number, col:number}[] validPositions 所有合法锚点列表
function RelicGrid.findValidPositions(relicType, gridRelics)
    local typeDef = RelicDefs.TYPES[relicType]
    if not typeDef then return {} end

    -- 构建当前矩阵
    if not gridRelics then
        local RelicSystem = require("systems.RelicSystem")
        gridRelics = RelicSystem.getGrid()
    end
    local matrix = RelicGrid.buildMatrix(gridRelics)

    local validPositions = {}

    -- 遍历所有可能的锚点位置
    for r = 1, RelicGrid.GRID_ROWS do
        for c = 1, RelicGrid.GRID_COLS do
            local canDo = RelicGrid.canPlace(relicType, r, c, matrix)
            if canDo then
                validPositions[#validPositions + 1] = { row = r, col = c }
            end
        end
    end

    return validPositions
end

--- 检查指定类型遗物是否还有可放置的空间
---@param relicType number
---@param gridRelics table[]|nil
---@return boolean hasSpace
function RelicGrid.hasSpaceFor(relicType, gridRelics)
    local positions = RelicGrid.findValidPositions(relicType, gridRelics)
    return #positions > 0
end

-- ======================== 占用信息查询 ========================

--- 获取指定遗物占据的所有格子坐标
---@param relic table 遗物实例（需有 type, row, col, rotation）
---@return {row:number, col:number}[]|nil cells 占据的格子列表
function RelicGrid.getOccupiedCells(relic)
    if not relic or not relic.type or not relic.row or not relic.col then
        return nil
    end

    local offsets = RelicGrid.getRotatedCellOffsets(relic.type, relic.rotation or 0)
    if #offsets == 0 then return nil end

    local anchorRow = relic.row
    local anchorCol = relic.col

    local cells = {}
    for _, offset in ipairs(offsets) do
        local r = anchorRow + offset[1]
        local c = anchorCol + offset[2]
        if r >= 1 and r <= RelicGrid.GRID_ROWS and c >= 1 and c <= RelicGrid.GRID_COLS then
            cells[#cells + 1] = { row = r, col = c }
        end
    end

    return cells
end

--- 获取所有已占用的格子坐标（用于网格绘制）
---@param gridRelics table[]|nil
---@return table<string, table> cellMap key="row_col" → { relicId, relicType, quality }
function RelicGrid.getOccupiedMap(gridRelics)
    if not gridRelics then
        local RelicSystem = require("systems.RelicSystem")
        gridRelics = RelicSystem.getGrid()
    end

    local cellMap = {}
    for _, relic in ipairs(gridRelics) do
        local anchorRow = relic.row
        local anchorCol = relic.col
        if anchorRow and anchorCol and relic.type then
            local offsets = RelicGrid.getRotatedCellOffsets(relic.type, relic.rotation or 0)
            for _, offset in ipairs(offsets) do
                local r = anchorRow + offset[1]
                local c = anchorCol + offset[2]
                if r >= 1 and r <= RelicGrid.GRID_ROWS and c >= 1 and c <= RelicGrid.GRID_COLS then
                    local key = r .. "_" .. c
                    cellMap[key] = {
                        relicId = relic.id,
                        relicType = relic.type,
                        quality = relic.quality,
                        isAnchor = (r == anchorRow and c == anchorCol),
                    }
                end
            end
        end
    end

    return cellMap
end

-- ======================== 网格统计 ========================

--- 计算网格使用率
---@param gridRelics table[]|nil
---@return number occupiedCount 已占用格子数
---@return number totalCells 总格子数 (64)
---@return number percentage 使用百分比 (0~100)
function RelicGrid.getUsageStats(gridRelics)
    if not gridRelics then
        local RelicSystem = require("systems.RelicSystem")
        gridRelics = RelicSystem.getGrid()
    end

    local totalCells = RelicGrid.GRID_ROWS * RelicGrid.GRID_COLS
    local matrix = RelicGrid.buildMatrix(gridRelics)

    local occupiedCount = 0
    for r = 1, RelicGrid.GRID_ROWS do
        for c = 1, RelicGrid.GRID_COLS do
            if matrix[r][c] ~= CELL_EMPTY then
                occupiedCount = occupiedCount + 1
            end
        end
    end

    local percentage = math.floor(occupiedCount / totalCells * 100)
    return occupiedCount, totalCells, percentage
end

--- 获取指定格子上的遗物
---@param row number
---@param col number
---@param gridRelics table[]|nil
---@return table|nil relic 占据该格子的遗物实例
function RelicGrid.getRelicAt(row, col, gridRelics)
    if row < 1 or row > RelicGrid.GRID_ROWS then return nil end
    if col < 1 or col > RelicGrid.GRID_COLS then return nil end

    if not gridRelics then
        local RelicSystem = require("systems.RelicSystem")
        gridRelics = RelicSystem.getGrid()
    end

    for _, relic in ipairs(gridRelics) do
        local anchorRow = relic.row
        local anchorCol = relic.col
        if anchorRow and anchorCol and relic.type then
            local offsets = RelicGrid.getRotatedCellOffsets(relic.type, relic.rotation or 0)
            for _, offset in ipairs(offsets) do
                local r = anchorRow + offset[1]
                local c = anchorCol + offset[2]
                if r == row and c == col then
                    return relic
                end
            end
        end
    end

    return nil
end

-- ======================== 形状预览（UI 辅助） ========================

--- 获取放置预览格子列表（不做碰撞检测，用于 UI 预显示形状）
---@param relicType number
---@param row number 锚点行
---@param col number 锚点列
---@param rotation number|nil 旋转次数 (0~3)
---@return {row:number, col:number, inBounds:boolean}[] previewCells
function RelicGrid.getPlacementPreview(relicType, row, col, rotation)
    local offsets = RelicGrid.getRotatedCellOffsets(relicType, rotation or 0)
    if #offsets == 0 then return {} end

    local preview = {}
    for _, offset in ipairs(offsets) do
        local r = row + offset[1]
        local c = col + offset[2]
        local inBounds = (r >= 1 and r <= RelicGrid.GRID_ROWS and c >= 1 and c <= RelicGrid.GRID_COLS)
        preview[#preview + 1] = { row = r, col = c, inBounds = inBounds }
    end

    return preview
end

--- 判断放置预览是否全部合法（边界内 + 无冲突）
---@param relicType number
---@param row number
---@param col number
---@param matrix number[][]|nil 已构建的矩阵
---@param rotation number|nil 旋转次数 (0~3)
---@return boolean allValid
---@return {row:number, col:number, valid:boolean}[] detailedCells 每格的状态
function RelicGrid.getDetailedPreview(relicType, row, col, matrix, rotation)
    local offsets = RelicGrid.getRotatedCellOffsets(relicType, rotation or 0)
    if #offsets == 0 then return false, {} end

    if not matrix then
        local RelicSystem = require("systems.RelicSystem")
        local gridRelics = RelicSystem.getGrid()
        matrix = RelicGrid.buildMatrix(gridRelics)
    end

    local allValid = true
    local detailedCells = {}

    for _, offset in ipairs(offsets) do
        local r = row + offset[1]
        local c = col + offset[2]
        local valid = true

        if r < 1 or r > RelicGrid.GRID_ROWS or c < 1 or c > RelicGrid.GRID_COLS then
            valid = false
        elseif matrix[r][c] ~= CELL_EMPTY then
            valid = false
        end

        if not valid then allValid = false end
        detailedCells[#detailedCells + 1] = { row = r, col = c, valid = valid }
    end

    return allValid, detailedCells
end

-- ======================== 自动放置建议 ========================

--- 为遗物寻找最佳放置位置（简单策略：优先靠左上角紧凑放置）
---@param relicType number
---@param gridRelics table[]|nil
---@return {row:number, col:number}|nil bestPosition 最佳位置，nil表示无空间
function RelicGrid.suggestPosition(relicType, gridRelics)
    local positions = RelicGrid.findValidPositions(relicType, gridRelics)
    if #positions == 0 then return nil end

    -- 简单策略：选择最靠左上角的位置（行优先）
    table.sort(positions, function(a, b)
        if a.row ~= b.row then return a.row < b.row end
        return a.col < b.col
    end)

    return positions[1]
end

return RelicGrid
