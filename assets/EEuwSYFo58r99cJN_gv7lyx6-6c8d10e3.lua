-- ============================================================================
-- RelicService - 遗物管理业务逻辑
-- 职责: GM给遗物
-- 层级: server/relic  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM         = require("server.character.PlayerDataManager")
local RelicAffix  = require("systems.RelicAffix")
local RelicDefs   = require("data.RelicDefs")
local RelicSchema = require("shared.relic.RelicSchema")

local RelicService = {}

--- 遗物背包容量上限（200 件 × ~81B/件 ≈ 16KB，远低于 50KB 网络分片阈值）
RelicService.MAX_BAG = 200

--- 确保遗物模块结构合法（稀疏 bag/grid 会导致 ipairs 漏项，UI 表现为「遗物被吞」）
---@param relicData table|nil
local function ensureRelicData(relicData)
    if relicData then
        RelicSchema.normalizeModule(relicData)
    end
    return relicData
end

--- GM 生成遗物（指定类型/品质）
---@param uid number
---@param relicType number 1~5
---@param quality number 1~6
---@return boolean ok, string? err, table? result
function RelicService.GmGiveRelic(uid, relicType, quality)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end

    -- 背包容量检查
    if #relicData.bag >= RelicService.MAX_BAG then
        return false, "遗物背包已满（上限 " .. RelicService.MAX_BAG .. " 件）"
    end

    relicType = tonumber(relicType) or 1
    quality   = tonumber(quality)   or 1

    -- 校验类型范围
    if relicType < 1 or relicType > 5 then
        return false, "无效的遗物类型: " .. tostring(relicType)
    end
    if quality < 1 or quality > 6 then
        return false, "无效的品质: " .. tostring(quality)
    end

    -- 验证类型定义存在
    local typeDef = RelicDefs.TYPES[relicType]
    if not typeDef then
        return false, "遗物类型定义不存在: " .. tostring(relicType)
    end

    -- 随机词缀
    local level = 1
    local affixId = RelicAffix.rollAffix(relicType, quality, level)
    if not affixId then
        return false, "词缀池为空 type=" .. relicType .. " q=" .. quality
    end

    -- 生成遗物对象
    local id = relicData.nextId
    relicData.nextId = id + 1

    local relic = {
        id      = tostring(id),
        type    = relicType,
        quality = quality,
        affixId = affixId,
        -- level 省略时默认为 1，locked 省略时默认为 false（减少持久化体积）
    }

    -- 加入背包
    relicData.bag[#relicData.bag + 1] = relic

    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] GM_GIVE_RELIC uid=" .. tostring(uid)
        .. " id=" .. relic.id
        .. " type=" .. typeDef.name
        .. " q=" .. quality
        .. " affix=" .. affixId)

    return true, nil, { relic = relic }
end

--- 遗物洗练（消耗奥术粉尘，重随词缀）
---@param uid number
---@param relicId string 遗物ID
---@return boolean ok, string? err, table? result
function RelicService.Reforge(uid, relicId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end

    relicId = tostring(relicId or "")
    if relicId == "" then return false, "缺少 relicId" end

    -- 在背包和装备栏中查找遗物
    local relic = nil
    for _, r in ipairs(relicData.bag) do
        if tostring(r.id) == relicId then relic = r; break end
    end
    if not relic then
        -- 尝试装备栏
        for _, r in pairs(relicData.grid or {}) do
            if tostring(r.id) == relicId then relic = r; break end
        end
    end
    if not relic then return false, "遗物不存在: " .. relicId end

    -- 品质检查（3品及以上才可洗练）
    if (relic.quality or 0) < 3 then
        return false, "品质不足，需要3品及以上"
    end

    -- 计算消耗
    local qualityDef = RelicDefs.QUALITIES[relic.quality]
    if not qualityDef then return false, "品质定义不存在: " .. tostring(relic.quality) end
    local cost = qualityDef.reforgeCost or 0

    -- 检查并扣除奥术粉尘
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, "货币数据未加载" end

    local owned = currency.arcaneDust or 0
    if owned < cost then
        return false, "奥术粉尘不足: 拥有" .. owned .. " 需要" .. cost
    end
    currency.arcaneDust = owned - cost
    PDM.MarkDirty(uid, "currency")

    -- 随机新词缀（排除当前词缀）
    local newAffixId = RelicAffix.rollAffix(relic.type, relic.quality, relic.level or 1, relic.affixId)
    if not newAffixId then
        -- 回滚奥术粉尘
        currency.arcaneDust = owned
        PDM.MarkDirty(uid, "currency")
        return false, "词缀池耗尽，无法洗练"
    end

    -- 记录旧词缀（日志用）
    local oldAffixId = relic.affixId

    -- 洗练只生成候选，不立即替换；点击"替换"时再提交
    relic.pendingReforgeAffixId = newAffixId

    -- 递增洗练计数
    relicData.reforgeCount = (relicData.reforgeCount or 0) + 1

    PDM.MarkDirty(uid, "mod_relics")
    PDM.FlushImmediate(uid)

    print("[RelicService] REFORGE uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " oldAffix=" .. tostring(oldAffixId)
        .. " pendingAffix=" .. tostring(newAffixId)
        .. " cost=" .. cost
        .. " remaining=" .. tostring(currency.arcaneDust))

    return true, nil, { newAffixId = newAffixId }
end

--- 确认替换洗练候选词缀
---@param uid number
---@param relicId string 遗物ID
---@param newAffixId number 候选词缀ID
---@return boolean ok, string? err, table? result
function RelicService.ConfirmReforge(uid, relicId, newAffixId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end

    relicId = tostring(relicId or "")
    newAffixId = tonumber(newAffixId)
    if relicId == "" or not newAffixId then return false, "参数错误" end

    local relic = nil
    for _, r in ipairs(relicData.bag or {}) do
        if tostring(r.id) == relicId then relic = r; break end
    end
    if not relic then
        for _, r in pairs(relicData.grid or {}) do
            if tostring(r.id) == relicId then relic = r; break end
        end
    end
    if not relic then return false, "遗物不存在: " .. relicId end
    if tonumber(relic.pendingReforgeAffixId) ~= newAffixId then
        return false, "洗练结果已失效，请重新洗练"
    end

    local oldAffixId = relic.affixId
    relic.affixId = newAffixId
    relic.pendingReforgeAffixId = nil
    PDM.MarkDirty(uid, "mod_relics")
    PDM.FlushImmediate(uid)

    print("[RelicService] REFORGE_CONFIRM uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " oldAffix=" .. tostring(oldAffixId)
        .. " newAffix=" .. tostring(newAffixId))

    return true, nil, { relicId = relicId, newAffixId = newAffixId }
end

--- 遗物合成（3个同类型同品质 → 1个高一级品质）
---@param uid number
---@param relicIds string[] 3个遗物ID
---@return boolean ok, string? err, table? result
function RelicService.Merge(uid, relicIds)
    local relicData = PDM.GetModule(uid, "mod_relics")
    if not relicData then return false, "数据未加载" end

    if not relicIds or #relicIds ~= 3 then
        return false, "需要提供3个遗物ID"
    end

    -- 查找并验证3个遗物（必须都在背包中）
    local relics = {}
    local bagIndices = {}
    for _, rid in ipairs(relicIds) do
        rid = tostring(rid)
        local found = false
        for i, r in ipairs(relicData.bag) do
            if tostring(r.id) == rid then
                relics[#relics + 1] = r
                bagIndices[#bagIndices + 1] = i
                found = true
                break
            end
        end
        if not found then
            return false, "遗物不在背包中: " .. rid
        end
    end

    -- 检查ID不重复
    if relicIds[1] == relicIds[2] or relicIds[1] == relicIds[3] or relicIds[2] == relicIds[3] then
        return false, "不能使用重复的遗物"
    end

    -- 验证同类型
    local baseType = relics[1].type
    for i = 2, 3 do
        if relics[i].type ~= baseType then
            return false, "合成需要相同类型的遗物"
        end
    end

    -- 验证同品质
    local baseQuality = relics[1].quality
    for i = 2, 3 do
        if relics[i].quality ~= baseQuality then
            return false, "合成需要相同品质的遗物"
        end
    end

    -- 品质上限检查
    if baseQuality >= 6 then
        return false, "至臻品质无法继续合成"
    end

    -- 检查锁定
    for i = 1, 3 do
        if relics[i].locked == true then
            return false, "遗物已锁定: " .. tostring(relics[i].id)
        end
    end

    -- 背包容量检查（消耗3个 产出1个，净减少2个，不会溢出）

    -- 验证类型定义存在
    local typeDef = RelicDefs.TYPES[baseType]
    if not typeDef then
        return false, "遗物类型定义不存在: " .. tostring(baseType)
    end

    -- 生成新遗物
    local newQuality = baseQuality + 1
    local level = 1
    local affixId = RelicAffix.rollAffix(baseType, newQuality, level)
    if not affixId then
        return false, "词缀池为空 type=" .. baseType .. " q=" .. newQuality
    end

    local id = relicData.nextId
    relicData.nextId = id + 1

    local newRelic = {
        id      = tostring(id),
        type    = baseType,
        quality = newQuality,
        affixId = affixId,
        -- level 省略时默认为 1，locked 省略时默认为 false（减少持久化体积）
    }

    -- 从背包中移除3个素材遗物（从后往前删，避免索引偏移）
    table.sort(bagIndices, function(a, b) return a > b end)
    for _, idx in ipairs(bagIndices) do
        table.remove(relicData.bag, idx)
    end

    -- 加入新遗物
    relicData.bag[#relicData.bag + 1] = newRelic

    -- 递增合成计数
    relicData.mergeCount = (relicData.mergeCount or 0) + 1

    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] MERGE uid=" .. tostring(uid)
        .. " consumed=" .. relicIds[1] .. "," .. relicIds[2] .. "," .. relicIds[3]
        .. " type=" .. typeDef.name
        .. " " .. baseQuality .. "→" .. newQuality
        .. " newId=" .. newRelic.id
        .. " affix=" .. affixId)

    return true, nil, { relic = newRelic }
end

--- 网格尺寸常量
local GRID_ROWS = 10
local GRID_COLS = 8

--- 对 cells 应用旋转（顺时针 90° 每次: {r,c} → {c,-r}）
--- rotation 0~3 = 正常旋转; 4~7 = 水平翻转 + 旋转(0~3)
---@param cells number[][]
---@param rotation number 0~7
---@return number[][]
local function applyCellsRotation(cells, rotation)
    rotation = rotation or 0
    local flipped = rotation >= 4
    local rot = rotation % 4

    local result = {}
    for _, offset in ipairs(cells) do
        local r, c = offset[1], offset[2]
        -- 先翻转（水平镜像：列取反）
        if flipped then
            c = -c
        end
        -- 再旋转
        for _ = 1, rot do
            r, c = c, -r
        end
        result[#result + 1] = { r, c }
    end
    return result
end

--- 将遗物从背包镶嵌到石板网格
---@param uid number
---@param relicId string 遗物ID
---@param row number 锚点行 (1~GRID_ROWS)
---@param col number 锚点列 (1~GRID_COLS)
---@param rotation number|nil 旋转+翻转 0~7（0-3正常旋转, 4-7翻转+旋转, 默认0）
---@return boolean ok, string? err, table? result
function RelicService.PlaceOnGrid(uid, relicId, row, col, rotation)
    local relicData = PDM.GetModule(uid, "mod_relics")
    if not relicData then return false, "数据未加载" end

    relicId = tostring(relicId or "")
    if relicId == "" then return false, "缺少 relicId" end

    row = tonumber(row)
    col = tonumber(col)
    rotation = tonumber(rotation) or 0
    if not row or not col then return false, "缺少坐标" end
    if row < 1 or row > GRID_ROWS or col < 1 or col > GRID_COLS then
        return false, "坐标超出网格范围"
    end

    -- 在背包中查找遗物
    local relic = nil
    local bagIndex = nil
    for i, r in ipairs(relicData.bag) do
        if tostring(r.id) == relicId then
            relic = r
            bagIndex = i
            break
        end
    end
    if not relic then
        print("[RelicService] PLACE FAILED uid=" .. tostring(uid)
            .. " relicId=" .. relicId .. " reason=遗物不在背包中"
            .. " bagSize=" .. #relicData.bag
            .. " gridSize=" .. #(relicData.grid or {}))
        return false, "遗物不在背包中"
    end

    -- 获取遗物类型定义
    local typeDef = RelicDefs.TYPES[relic.type]
    if not typeDef then return false, "遗物类型定义不存在" end

    -- 应用旋转得到实际占用格子
    local rotatedCells = applyCellsRotation(typeDef.cells, rotation)

    -- 构建网格矩阵，检查放置合法性
    local gridRelics = relicData.grid or {}

    -- 初始化空矩阵
    local matrix = {}
    for r = 1, GRID_ROWS do
        matrix[r] = {}
        for c = 1, GRID_COLS do
            matrix[r][c] = 0
        end
    end
    -- 填充已占用格子（已安装的遗物使用存储的 rotation 重建占位）
    for _, gr in ipairs(gridRelics) do
        if gr.row and gr.col and gr.type then
            local td = RelicDefs.TYPES[gr.type]
            if td then
                local grCells = applyCellsRotation(td.cells, gr.rotation or 0)
                for _, offset in ipairs(grCells) do
                    local rr = gr.row + offset[1]
                    local cc = gr.col + offset[2]
                    if rr >= 1 and rr <= GRID_ROWS and cc >= 1 and cc <= GRID_COLS then
                        matrix[rr][cc] = 1
                    end
                end
            end
        end
    end

    -- 检查每个格子是否在边界内且空闲
    for _, offset in ipairs(rotatedCells) do
        local rr = row + offset[1]
        local cc = col + offset[2]
        if rr < 1 or rr > GRID_ROWS or cc < 1 or cc > GRID_COLS then
            print("[RelicService] PLACE FAILED uid=" .. tostring(uid)
                .. " relicId=" .. relicId .. " reason=超出网格边界"
                .. " cell=(" .. rr .. "," .. cc .. ")")
            return false, "遗物形状超出网格边界"
        end
        if matrix[rr][cc] ~= 0 then
            print("[RelicService] PLACE FAILED uid=" .. tostring(uid)
                .. " relicId=" .. relicId .. " reason=位置被占用"
                .. " pos=(" .. row .. "," .. col .. ") rot=" .. rotation
                .. " conflictCell=(" .. rr .. "," .. cc .. ")")
            return false, "位置已被占用"
        end
    end

    -- 从背包移除
    table.remove(relicData.bag, bagIndex)

    -- 设置网格位置（扁平存储，客户端可直接读取 relic.row/col/rotation）
    relic.row = row
    relic.col = col
    relic.rotation = rotation
    relic.gridPos = nil  -- 清除旧格式（如有）

    -- 加入网格列表
    if not relicData.grid then relicData.grid = {} end
    relicData.grid[#relicData.grid + 1] = relic

    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] PLACE uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " type=" .. tostring(relic.type)
        .. " pos=(" .. row .. "," .. col .. ")"
        .. " rot=" .. rotation)

    return true, nil, { relicId = relicId, row = row, col = col, rotation = rotation }
end

--- 调整模式批量移动（原子化 REMOVE+PLACE）
--- 将一组已在网格上的遗物移动到新位置，单次操作避免频率限制问题
---@param uid number
---@param moves table[] { {relicId, row, col, rotation}, ... }
---@return boolean ok, string? err, table? result
function RelicService.BatchAdjust(uid, moves)
    local relicData = PDM.GetModule(uid, "mod_relics")
    if not relicData then return false, "数据未加载" end

    if not moves or #moves == 0 then return false, "无移动数据" end
    if #moves > 20 then return false, "单次移动过多" end

    local gridRelics = relicData.grid or {}

    -- Step 1: 找到所有要移动的遗物（必须都在 grid 上）
    local moveSet = {} -- relicId(string) → move params
    for _, m in ipairs(moves) do
        local rid = tostring(m.relicId or "")
        if rid == "" then return false, "缺少 relicId" end
        moveSet[rid] = {
            row = tonumber(m.row),
            col = tonumber(m.col),
            rotation = tonumber(m.rotation) or 0,
        }
        if not moveSet[rid].row or not moveSet[rid].col then
            return false, "遗物 " .. rid .. " 缺少坐标"
        end
    end

    -- Step 2: 构建网格矩阵（排除正在被移动的遗物）
    local matrix = {}
    for r = 1, GRID_ROWS do
        matrix[r] = {}
        for c = 1, GRID_COLS do
            matrix[r][c] = 0
        end
    end
    for _, gr in ipairs(gridRelics) do
        if gr.row and gr.col and gr.type then
            local rid = tostring(gr.id)
            if not moveSet[rid] then
                -- 不参与移动的遗物正常占位
                local td = RelicDefs.TYPES[gr.type]
                if td then
                    local grCells = applyCellsRotation(td.cells, gr.rotation or 0)
                    for _, offset in ipairs(grCells) do
                        local rr = gr.row + offset[1]
                        local cc = gr.col + offset[2]
                        if rr >= 1 and rr <= GRID_ROWS and cc >= 1 and cc <= GRID_COLS then
                            matrix[rr][cc] = 1
                        end
                    end
                end
            end
        end
    end

    -- Step 3: 验证所有新位置（互相之间也要检查冲突）
    local placedCells = {} -- 存储本次批量放置已占用的格子
    for _, m in ipairs(moves) do
        local rid = tostring(m.relicId)
        local params = moveSet[rid]
        -- 在 grid 中找到遗物获取 type
        local relic = nil
        for _, gr in ipairs(gridRelics) do
            if tostring(gr.id) == rid then
                relic = gr
                break
            end
        end
        if not relic then return false, "遗物 " .. rid .. " 不在网格上" end

        local typeDef = RelicDefs.TYPES[relic.type]
        if not typeDef then return false, "遗物类型定义不存在" end

        local rotatedCells = applyCellsRotation(typeDef.cells, params.rotation)
        for _, offset in ipairs(rotatedCells) do
            local rr = params.row + offset[1]
            local cc = params.col + offset[2]
            if rr < 1 or rr > GRID_ROWS or cc < 1 or cc > GRID_COLS then
                return false, "遗物 " .. rid .. " 超出网格边界"
            end
            if matrix[rr][cc] ~= 0 then
                return false, "遗物 " .. rid .. " 位置被占用"
            end
            -- 检查本批次内的冲突
            local key = rr .. "," .. cc
            if placedCells[key] then
                return false, "遗物 " .. rid .. " 与本次其他遗物冲突"
            end
            placedCells[key] = true
        end
    end

    -- Step 4: 所有验证通过，原地更新位置（不需要移到背包再移回来）
    local movedCount = 0
    for _, gr in ipairs(gridRelics) do
        local rid = tostring(gr.id)
        local params = moveSet[rid]
        if params then
            gr.row = params.row
            gr.col = params.col
            gr.rotation = params.rotation
            gr.gridPos = nil
            movedCount = movedCount + 1
        end
    end

    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] BATCH_ADJUST uid=" .. tostring(uid)
        .. " moved=" .. movedCount .. "/" .. #moves)

    return true, nil, { moved = movedCount }
end

--- 从石板网格取下遗物，放回背包
---@param uid number
---@param relicId string 遗物ID
---@return boolean ok, string? err, table? result
function RelicService.RemoveFromGrid(uid, relicId)
    local relicData = PDM.GetModule(uid, "mod_relics")
    if not relicData then return false, "数据未加载" end

    relicId = tostring(relicId or "")
    if relicId == "" then return false, "缺少 relicId" end

    -- 在网格中查找遗物
    local gridRelics = relicData.grid or {}
    local relic = nil
    local gridIndex = nil
    for i, r in ipairs(gridRelics) do
        if tostring(r.id) == relicId then
            relic = r
            gridIndex = i
            break
        end
    end
    if not relic then return false, "遗物不在网格上" end

    -- 背包容量检查
    if #relicData.bag >= RelicService.MAX_BAG then
        return false, "背包已满，无法取下"
    end

    -- 从网格移除
    table.remove(relicData.grid, gridIndex)

    -- 清除网格位置（新格式 + 兼容旧格式）
    relic.row = nil
    relic.col = nil
    relic.rotation = nil
    relic.gridPos = nil

    -- 放回背包
    relicData.bag[#relicData.bag + 1] = relic

    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] REMOVE uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " type=" .. tostring(relic.type))

    return true, nil, { relicId = relicId }
end

--- 原子化替换：将背包中的新遗物替换到旧遗物的网格位置（单次 MarkDirty，避免 REMOVE+PLACE 两次推送的竞态）
---@param uid number
---@param oldRelicId string 旧遗物ID（网格上）
---@param newRelicId string 新遗物ID（背包中）
---@param row number 旧遗物行号
---@param col number 旧遗物列号
---@param rotation number|nil 旧遗物旋转
---@return boolean ok, string? err, table? result
function RelicService.ReplaceOnGrid(uid, oldRelicId, newRelicId, row, col, rotation)
    local relicData = PDM.GetModule(uid, "mod_relics")
    if not relicData then return false, "数据未加载" end

    oldRelicId = tostring(oldRelicId or "")
    newRelicId = tostring(newRelicId or "")
    if oldRelicId == "" or newRelicId == "" then return false, "缺失遗物ID" end

    row = tonumber(row)
    col = tonumber(col)
    rotation = tonumber(rotation) or 0
    if not row or not col then return false, "缺失坐标" end
    if row < 1 or row > GRID_ROWS or col < 1 or col > GRID_COLS then
        return false, "坐标超出网格范围"
    end

    -- Step 1: 在网格中找到旧遗物
    local gridRelics = relicData.grid or {}
    local oldRelic = nil
    local oldIndex = nil
    for i, r in ipairs(gridRelics) do
        if tostring(r.id) == oldRelicId then
            oldRelic = r
            oldIndex = i
            break
        end
    end
    if not oldRelic then return false, "旧遗物不在网格上" end

    -- Step 2: 在背包中找到新遗物
    local newRelic = nil
    local newIndex = nil
    for i, r in ipairs(relicData.bag) do
        if tostring(r.id) == newRelicId then
            newRelic = r
            newIndex = i
            break
        end
    end
    if not newRelic then return false, "新遗物不在背包中" end

    -- Step 3: 检查新遗物的形状是否能放在旧位置
    local typeDef = RelicDefs.TYPES[newRelic.type]
    if not typeDef then return false, "新遗物类型定义不存在" end

    local rotatedCells = applyCellsRotation(typeDef.cells, rotation)

    -- 构建排除旧遗物的网格矩阵
    local matrix = {}
    for r = 1, GRID_ROWS do
        matrix[r] = {}
        for c = 1, GRID_COLS do
            matrix[r][c] = 0
        end
    end
    for _, gr in ipairs(gridRelics) do
        if gr ~= oldRelic then
            if gr.row and gr.col and gr.type then
                local td = RelicDefs.TYPES[gr.type]
                if td then
                    local grCells = applyCellsRotation(td.cells, gr.rotation or 0)
                    for _, offset in ipairs(grCells) do
                        local rr = gr.row + offset[1]
                        local cc = gr.col + offset[2]
                        if rr >= 1 and rr <= GRID_ROWS and cc >= 1 and cc <= GRID_COLS then
                            matrix[rr][cc] = 1
                        end
                    end
                end
            end
        end
    end

    for _, offset in ipairs(rotatedCells) do
        local rr = row + offset[1]
        local cc = col + offset[2]
        if rr < 1 or rr > GRID_ROWS or cc < 1 or cc > GRID_COLS then
            return false, "新遗物超出网格边界"
        end
        if matrix[rr][cc] ~= 0 then
            return false, "位置已被占用"
        end
    end

    -- Step 4: 原子化替换（单次 MarkDirty）
    table.remove(relicData.grid, oldIndex)
    oldRelic.row = nil; oldRelic.col = nil; oldRelic.rotation = nil; oldRelic.gridPos = nil
    relicData.bag[#relicData.bag + 1] = oldRelic

    table.remove(relicData.bag, newIndex)
    newRelic.row = row; newRelic.col = col; newRelic.rotation = rotation; newRelic.gridPos = nil
    relicData.grid[#relicData.grid + 1] = newRelic

    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] REPLACE uid=" .. tostring(uid) .. " old=" .. oldRelicId .. " new=" .. newRelicId .. " pos=(" .. row .. "," .. col .. ") rot=" .. rotation)

    return true, nil, {}
end

--- 切换遗物锁定状态（锁定后无法参与合成）
---@param uid number
---@param relicId string
---@return boolean ok, string|nil err, table|nil result { relicId, locked }
function RelicService.ToggleLock(uid, relicId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end

    relicId = tostring(relicId or "")
    if relicId == "" then return false, "缺少 relicId" end

    local relic = nil
    for _, r in ipairs(relicData.bag or {}) do
        if tostring(r.id) == relicId then relic = r; break end
    end
    if not relic then
        for _, r in ipairs(relicData.grid or {}) do
            if tostring(r.id) == relicId then relic = r; break end
        end
    end
    if not relic then return false, "遗物不存在: " .. relicId end

    if relic.locked then
        relic.locked = nil
    else
        relic.locked = true
    end
    PDM.MarkDirty(uid, "mod_relics")
    PDM.FlushImmediate(uid)

    print("[RelicService] ToggleLock uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " locked=" .. tostring(relic.locked == true))
    return true, nil, { relicId = relicId, locked = relic.locked == true }
end

return RelicService
