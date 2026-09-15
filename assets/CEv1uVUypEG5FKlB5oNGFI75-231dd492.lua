-- ============================================================================
-- RelicSystem.lua — 遗物系统核心逻辑（客户端侧）
--
-- 职责:
--   1. 遗物获取/移除（本地数据操作 + 服务端请求）
--   2. 洗练/合成操作（发送 sendAction → 等待 PlayerStore 更新）
--   3. 属性汇总（读取已镶嵌遗物，计算总加成）
--   4. 数据查询便利方法（给 UI 层用）
--
-- 数据来源:
--   PlayerStore.Get("mod_relics") → { bag = {...}, grid = {...}, mergeCount, reforgeCount }
--
-- 与服务端的交互:
--   Client.sendAction(ACTION_TYPE, params) → 服务端处理 → pushModule → PlayerStore 更新
-- ============================================================================

local RelicDefs  = require("data.RelicDefs")
local RelicAffix = require("systems.RelicAffix")

---@class RelicSystem
local RelicSystem = {}

-- ======================== Action Types ========================
-- 注册到 Protocol.ACTION_TYPES 中（需在 Protocol.lua 中补充）

RelicSystem.ACTIONS = {
    RELIC_REFORGE = "relic_reforge",     -- 洗练
    RELIC_REFORGE_CONFIRM = "relic_reforge_confirm", -- 确认洗练替换
    RELIC_MERGE   = "relic_merge",       -- 合成
    RELIC_PLACE   = "relic_place",       -- 镶嵌到网格
    RELIC_REMOVE  = "relic_remove",      -- 从网格取下
    RELIC_LOCK    = "relic_lock",        -- 锁定/解锁
    RELIC_BATCH_ADJUST = "relic_batch_adjust", -- 调整模式批量移动
    RELIC_REPLACE   = "relic_replace",
}

-- ======================== 数据访问 ========================

--- 获取遗物模块完整数据
---@return table|nil { bag={...}, grid={...}, mergeCount, reforgeCount }
function RelicSystem.getData()
    local PlayerStore = require("client.data.PlayerStore")
    return PlayerStore.Get("mod_relics")
end

--- 获取背包中的所有遗物
---@return table[] 遗物实例列表
function RelicSystem.getBag()
    local data = RelicSystem.getData()
    if not data then return {} end
    return data.bag or {}
end

--- 获取已镶嵌到网格的所有遗物
---@return table[] 遗物实例列表
function RelicSystem.getGrid()
    local data = RelicSystem.getData()
    if not data then return {} end
    return data.grid or {}
end

--- 获取所有遗物（背包+网格）
---@return table[]
function RelicSystem.getAll()
    local bag = RelicSystem.getBag()
    local grid = RelicSystem.getGrid()
    local all = {}
    for _, r in ipairs(bag) do all[#all + 1] = r end
    for _, r in ipairs(grid) do all[#all + 1] = r end
    return all
end

--- 通过ID查找遗物实例
---@param relicId string|number
---@return table|nil relic, string|nil location ("bag"|"grid")
function RelicSystem.findById(relicId)
    if relicId == nil then return nil, nil end
    relicId = tostring(relicId)
    local data = RelicSystem.getData()
    if not data then return nil, nil end

    local function scan(list, location)
        if not list then return nil end
        for _, r in ipairs(list) do
            if r and tostring(r.id) == relicId then return r, location end
        end
        -- ipairs 可能漏掉非连续数组项（cjson 对象化 bag）
        for _, r in pairs(list) do
            if type(r) == "table" and tostring(r.id) == relicId then return r, location end
        end
        return nil
    end

    local relic, loc = scan(data.bag, "bag")
    if relic then return relic, loc end
    relic, loc = scan(data.grid, "grid")
    if relic then return relic, loc end
    return nil, nil
end

-- ======================== 筛选/排序 ========================

--- 按类型筛选背包遗物
---@param relicType number|nil nil表示全部
---@return table[]
function RelicSystem.filterBagByType(relicType)
    local bag = RelicSystem.getBag()
    if not relicType then return bag end

    local result = {}
    for _, r in ipairs(bag) do
        if r.type == relicType then
            result[#result + 1] = r
        end
    end
    return result
end

--- 按品质降序排列遗物列表
---@param relics table[]
---@return table[] 排序后的新列表（不修改原表）
function RelicSystem.sortByQuality(relics)
    local sorted = {}
    for _, r in ipairs(relics) do sorted[#sorted + 1] = r end
    table.sort(sorted, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.type ~= b.type then return a.type < b.type end
        return (a.id or "") < (b.id or "")
    end)
    return sorted
end

-- ======================== 属性计算 ========================

--- 计算已镶嵌遗物提供的总属性加成
---@return {flat:table<string,number>, percent:table<string,number>, conditional:table[]}
function RelicSystem.calcStats()
    local grid = RelicSystem.getGrid()
    return RelicAffix.summarizeStats(grid)
end

--- 构建已安装遗物的效果总览行（供 UI 弹窗展示）
---@param gridRelics table[]|nil 网格遗物列表（可含 localOverrides 后的位置信息）
---@return table[] lines { kind="header"|"text", text=string, muted?=boolean }
function RelicSystem.buildEquippedOverview(gridRelics)
    gridRelics = gridRelics or RelicSystem.getGrid()

    local equipped = {}
    for _, r in ipairs(gridRelics) do
        local full = (r and r.id and RelicSystem.findById(r.id)) or r
        if full and full.affixId then
            equipped[#equipped + 1] = full
        end
    end

    if #equipped == 0 then
        return { { kind = "text", text = "暂无已安装遗物", muted = true } }
    end

    local lines = {}
    local summary = RelicAffix.summarizeStats(equipped)

    local statRows = {}
    for key, val in pairs(summary.flat or {}) do
        if val ~= 0 then
            local text = (val > 0 and "+" or "") .. tostring(val)
            statRows[#statRows + 1] = { key = key, text = text, sort = key }
        end
    end
    for key, val in pairs(summary.percent or {}) do
        if val ~= 0 then
            statRows[#statRows + 1] = {
                key = key,
                text = string.format("%+.1f%%", val),
                sort = key,
            }
        end
    end
    table.sort(statRows, function(a, b) return a.sort < b.sort end)

    if #statRows > 0 then
        lines[#lines + 1] = { kind = "header", text = "属性加成" }
        for _, row in ipairs(statRows) do
            lines[#lines + 1] = { kind = "stat", label = row.key, value = row.text }
        end
    end

    if summary.conditional and #summary.conditional > 0 then
        lines[#lines + 1] = { kind = "header", text = "条件效果" }
        for _, c in ipairs(summary.conditional) do
            if c.raw and c.raw ~= "" then
                lines[#lines + 1] = { kind = "text", text = "· " .. c.raw }
            end
        end
    end

    lines[#lines + 1] = { kind = "header", text = "已安装遗物" }
    table.sort(equipped, function(a, b)
        local qa = a.quality or 0
        local qb = b.quality or 0
        if qa ~= qb then return qa > qb end
        return tostring(a.id) < tostring(b.id)
    end)
    for _, r in ipairs(equipped) do
        local typeDef = RelicSystem.getTypeDef(r.type)
        local qDef = RelicSystem.getQualityDef(r.quality)
        local name = typeDef and typeDef.name or "遗物"
        local qName = qDef and qDef.name or ""
        local affixText = RelicSystem.getRelicAffixText(r)
        lines[#lines + 1] = {
            kind = "text",
            text = string.format("· %s（%s）：%s", name, qName, affixText),
        }
    end

    return lines
end

-- ======================== 校验方法 ========================

--- 遗物是否已锁定（仅 true 视为锁定，与 Schema 归一化一致）
---@param relic table|nil
---@return boolean
function RelicSystem.isLocked(relic)
    return relic ~= nil and relic.locked == true
end

--- 检查遗物是否可洗练
---@param relic table 遗物实例
---@return boolean canReforge, string|nil reason
function RelicSystem.canReforge(relic)
    if not relic then return false, "遗物不存在" end

    local qualityDef = RelicDefs.QUALITIES[relic.quality]
    if not qualityDef then return false, "品质数据异常" end
    if not qualityDef.canReforge then
        return false, "品质" .. qualityDef.name .. "不可洗练(需稀有及以上)"
    end

    return true, nil
end

--- 检查是否可合成（需要3个相同类型+相同品质）
---@param relicIds string[] 3个遗物ID
---@return boolean canMerge, string|nil reason
function RelicSystem.canMerge(relicIds)
    if not relicIds or #relicIds ~= 3 then
        return false, "需要选择3个遗物"
    end

    local relics = {}
    for _, id in ipairs(relicIds) do
        local r, loc = RelicSystem.findById(id)
        if not r then return false, "遗物不存在: " .. tostring(id) end
        if loc ~= "bag" then return false, "只能合成背包中的遗物" end
        if RelicSystem.isLocked(r) then return false, "遗物已锁定: " .. tostring(id) end
        relics[#relics + 1] = r
    end

    -- 同类型
    local baseType = relics[1].type
    for i = 2, 3 do
        if relics[i].type ~= baseType then
            return false, "合成需要相同类型的遗物"
        end
    end

    -- 同品质
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

    return true, nil
end

--- 获取洗练费用
---@param relic table 遗物实例
---@return number cost（0表示不可洗练）
function RelicSystem.getReforgeCost(relic)
    if not relic then return 0 end
    return RelicDefs.getReforgeCost(relic.quality)
end

-- ======================== 合成预览 ========================

--- 预览合成结果（不执行，用于 UI 展示）
---@param relicIds string[] 3个遗物ID
---@return table|nil 预览信息 { type, quality, possibleAffixes }
function RelicSystem.previewMerge(relicIds)
    local canDo, reason = RelicSystem.canMerge(relicIds)
    if not canDo then return nil end

    ---@diagnostic disable-next-line: param-type-mismatch
    local relic = RelicSystem.findById(relicIds[1])
    if not relic then return nil end

    local newQuality = relic.quality + 1
    local pool = RelicAffix.getCandidatePool(relic.type, newQuality, relic.level or 1)

    return {
        type = relic.type,
        quality = newQuality,
        possibleAffixCount = #pool,
    }
end

-- ======================== 操作请求（发送到服务端） ========================

--- 请求洗练遗物
---@param relicId string 遗物ID
---@param onResult function|nil 回调 function(success, newAffixId)
function RelicSystem.requestReforge(relicId, onResult)
    local relic = RelicSystem.findById(relicId)
    if not relic then
        if onResult then onResult(false, "遗物不存在") end
        return
    end

    local canDo, reason = RelicSystem.canReforge(relic)
    if not canDo then
        if onResult then onResult(false, reason) end
        return
    end

    -- 发送服务端请求
    local Client = require("network.Client")
    Client.sendAction(RelicSystem.ACTIONS.RELIC_REFORGE, {
        relicId = relicId,
    })

    -- 结果通过 PlayerStore 订阅 "mod_relics" 变更来获取
    -- UI 层应监听 PlayerStore 变更并刷新
    if onResult then onResult(true, nil) end
end

--- 请求确认替换洗练候选词缀
---@param relicId string 遗物ID
---@param newAffixId number 候选词缀ID
---@param onResult function|nil 回调 function(success, reason)
function RelicSystem.requestReforgeConfirm(relicId, newAffixId, onResult)
    local relic = RelicSystem.findById(relicId)
    if not relic then
        if onResult then onResult(false, "遗物不存在") end
        return
    end
    if not newAffixId then
        if onResult then onResult(false, "没有可替换的洗练结果") end
        return
    end

    local Client = require("network.Client")
    Client.sendAction(RelicSystem.ACTIONS.RELIC_REFORGE_CONFIRM, {
        relicId = relicId,
        newAffixId = newAffixId,
    })
    -- 结果由 ClientMessageHandler 收到 RES_ACTION_RESULT 后处理
end

--- 请求合成遗物
---@param relicIds string[] 3个遗物ID
---@param onResult function|nil 回调 function(success, reason)
function RelicSystem.requestMerge(relicIds, onResult)
    local canDo, reason = RelicSystem.canMerge(relicIds)
    if not canDo then
        if onResult then onResult(false, reason) end
        return
    end

    local Client = require("network.Client")
    Client.sendAction(RelicSystem.ACTIONS.RELIC_MERGE, {
        relicIds = relicIds,
    })

    if onResult then onResult(true, nil) end
end

--- 请求镶嵌遗物到网格
---@param relicId string
---@param row number
---@param col number
---@param rotation number|nil 旋转方向 0-3（0=默认，1=90°顺时针…）
---@param onResult function|nil
function RelicSystem.requestPlace(relicId, row, col, rotation, onResult)
    local relic, loc = RelicSystem.findById(relicId)
    if not relic then
        if onResult then onResult(false, "遗物不存在") end
        return
    end
    if loc ~= "bag" then
        if onResult then onResult(false, "遗物不在背包中") end
        return
    end

    local Client = require("network.Client")
    Client.sendAction(RelicSystem.ACTIONS.RELIC_PLACE, {
        relicId = relicId,
        row = row,
        col = col,
        rotation = rotation or 0,
    })

    if onResult then onResult(true, nil) end
end

--- 请求从网格取下遗物
---@param relicId string
---@param onResult function|nil
function RelicSystem.requestRemoveFromGrid(relicId, onResult)
    local relic, loc = RelicSystem.findById(relicId)
    if not relic then
        if onResult then onResult(false, "遗物不存在") end
        return
    end
    if loc ~= "grid" then
        if onResult then onResult(false, "遗物不在网格上") end
        return
    end

    local Client = require("network.Client")
    Client.sendAction(RelicSystem.ACTIONS.RELIC_REMOVE, {
        relicId = relicId,
    })

    if onResult then onResult(true, nil) end
end

--- 请求移动网格中的遗物到新位置（调整模式用）
--- 实现: 发送 REMOVE + PLACE 两步操作
---@param relicId string
---@param newRow number
---@param newCol number
---@param newRotation number
---@param onResult function|nil
function RelicSystem.requestMoveOnGrid(relicId, newRow, newCol, newRotation, onResult)
    local relic, loc = RelicSystem.findById(relicId)
    if not relic then
        if onResult then onResult(false, "遗物不存在") end
        return
    end
    if loc ~= "grid" then
        if onResult then onResult(false, "遗物不在网格上") end
        return
    end

    local Client = require("network.Client")
    -- 先移除
    Client.sendAction(RelicSystem.ACTIONS.RELIC_REMOVE, {
        relicId = relicId,
    })
    -- 再放置到新位置
    Client.sendAction(RelicSystem.ACTIONS.RELIC_PLACE, {
        relicId = relicId,
        row = newRow,
        col = newCol,
        rotation = newRotation or 0,
    })

    if onResult then onResult(true, nil) end
end

--- 请求切换遗物锁定状态（与装备锁定一致：服务端 toggle）
---@param relicId string
function RelicSystem.requestToggleLock(relicId)
    local Client = require("network.Client")
    Client.sendAction(RelicSystem.ACTIONS.RELIC_LOCK, {
        relicId = relicId,
    })
end

-- ======================== 辅助方法 ========================

--- 获取遗物的词缀文本
---@param relic table 遗物实例
---@return string
function RelicSystem.getRelicAffixText(relic)
    if not relic or not relic.affixId then return "" end
    return RelicAffix.getAffixText(relic.affixId, relic.quality)
end

--- 获取遗物类型定义
---@param relicType number
---@return RelicTypeDef|nil
function RelicSystem.getTypeDef(relicType)
    return RelicDefs.TYPES[relicType]
end

--- 获取遗物品质定义
---@param quality number
---@return RelicQualityDef|nil
function RelicSystem.getQualityDef(quality)
    return RelicDefs.QUALITIES[quality]
end

--- 获取可合成的遗物组合（UI 自动检测）
--- 返回所有可组合的三元组（按品质降序）
---@return {type:number, quality:number, ids:string[]}[]
function RelicSystem.findMergeCandidates()
    local bag = RelicSystem.getBag()
    -- 按 type+quality 分组
    local groups = {} -- key="type_quality" → {relic, ...}
    for _, r in ipairs(bag) do
        if not RelicSystem.isLocked(r) and r.quality < 6 then
            local key = r.type .. "_" .. r.quality
            if not groups[key] then groups[key] = {} end
            groups[key][#groups[key] + 1] = r
        end
    end

    -- 找出数量 >= 3 的组合
    local candidates = {}
    for key, list in pairs(groups) do
        if #list >= 3 then
            local parts = {}
            for part in key:gmatch("[^_]+") do parts[#parts + 1] = tonumber(part) end
            candidates[#candidates + 1] = {
                type = parts[1],
                quality = parts[2],
                ids = { list[1].id, list[2].id, list[3].id },
                count = #list,
            }
        end
    end

    -- 按品质降序排列
    table.sort(candidates, function(a, b)
        return a.quality > b.quality
    end)

    return candidates
end

--- 获取遗物总数
---@return number bagCount, number gridCount
function RelicSystem.getCount()
    local data = RelicSystem.getData()
    if not data then return 0, 0 end
    local bagCount = data.bag and #data.bag or 0
    local gridCount = data.grid and #data.grid or 0
    return bagCount, gridCount
end

-- ======================== 快速替换 & 遮蔽判定 ========================

--- 检查背包遗物是否可以快速替换已装备的同词缀低品质遗物
--- 规则: 背包遗物 affixId == 网格遗物 affixId 且 bagRelic.quality > gridRelic.quality
---@param bagRelic table 背包中的遗物
---@return table|nil 可被替换的网格遗物，nil 表示无可替换目标
function RelicSystem.findReplaceTarget(bagRelic)
    if not bagRelic or not bagRelic.affixId then return nil end
    local grid = RelicSystem.getGrid()
    for _, gridRelic in ipairs(grid) do
        if gridRelic.type == bagRelic.type and gridRelic.affixId == bagRelic.affixId and bagRelic.quality > gridRelic.quality then
            return gridRelic
        end
    end
    return nil
end

--- 检查背包遗物是否被已装备的同词缀遗物遮蔽（无法装备）
--- 规则: 网格中已有相同 affixId 且品质 >= 本遗物的品质
---@param bagRelic table 背包中的遗物
---@return boolean 是否被遮蔽
function RelicSystem.isBlockedByEquipped(bagRelic)
    if not bagRelic or not bagRelic.affixId then return false end
    local grid = RelicSystem.getGrid()
    for _, gridRelic in ipairs(grid) do
        if gridRelic.type == bagRelic.type and gridRelic.affixId == bagRelic.affixId and gridRelic.quality >= bagRelic.quality then
            return true
        end
    end
    return false
end

--- 请求快速替换（原子化：在服务端一步完成取下+放置）
---@param newRelicId string 背包中的新遗物ID
---@param oldRelicId string 网格中要被替换的旧遗物ID
---@param onResult function|nil
function RelicSystem.requestReplace(newRelicId, oldRelicId, onResult)
    local newRelic, newLoc = RelicSystem.findById(newRelicId)
    if not newRelic or newLoc ~= "bag" then
        if onResult then onResult(false, "新遗物不在背包中") end
        return
    end
    local oldRelic, oldLoc = RelicSystem.findById(oldRelicId)
    if not oldRelic or oldLoc ~= "grid" then
        if onResult then onResult(false, "旧遗物不在网格上") end
        return
    end

    local row = oldRelic.row
    local col = oldRelic.col
    local rotation = oldRelic.rotation or 0
    if not row or not col then
        if onResult then onResult(false, "旧遗物网格位置异常") end
        return
    end

    local Client = require("network.Client")
    -- 使用原子化替换接口（服务端单次操作，避免中间状态）
    Client.sendAction(RelicSystem.ACTIONS.RELIC_REPLACE, {
        oldRelicId = oldRelicId,
        newRelicId = newRelicId,
        row = row,
        col = col,
        rotation = rotation,
    })

    if onResult then onResult(true, nil) end
end

-- ======================== 角标/红点系统 ========================

-- 已查看遗物ID集合（本地内存，每次登录重置）
-- 用于判断是否有"新获得"的遗物未被查看
local _seenRelicIds = {}

--- 标记所有当前遗物为已看（用户打开遗物标签页时调用）
function RelicSystem.markAllSeen()
    _seenRelicIds = {}
    local all = RelicSystem.getAll()
    for _, r in ipairs(all) do
        if r.id then
            _seenRelicIds[r.id] = true
        end
    end
end

--- 初始化已看集合（登录/数据首次到达时调用，静默标记当前全部为已看）
function RelicSystem.initSeenSet()
    RelicSystem.markAllSeen()
end

--- 是否有未查看的新遗物
---@return boolean
function RelicSystem.hasNewRelic()
    -- 如果 seenRelicIds 为空说明还没初始化（数据未到达），不显示红点
    local hasAny = false
    for _ in pairs(_seenRelicIds) do hasAny = true; break end
    if not hasAny then return false end

    local all = RelicSystem.getAll()
    for _, r in ipairs(all) do
        if r.id and not _seenRelicIds[r.id] then
            return true
        end
    end
    return false
end

--- 是否有任意背包遗物可以替换网格中同词缀低品质遗物
---@return boolean
function RelicSystem.canUpgradeAnyRelic()
    local bag = RelicSystem.getBag()
    for _, bagRelic in ipairs(bag) do
        if RelicSystem.findReplaceTarget(bagRelic) then
            return true
        end
    end
    return false
end

--- 获取遗物角标综合信息（供 TownScene/BottomNav 使用）
--- 可强化角标(绿色箭头)优先覆盖红点
---@return boolean show 是否显示角标
---@return string|nil style nil=绿色箭头(可强化), "redDot"=红点(新遗物)
function RelicSystem.getRelicBadgeInfo()
    if RelicSystem.canUpgradeAnyRelic() then
        return true, nil  -- 绿色箭头优先
    end
    if RelicSystem.hasNewRelic() then
        return true, "redDot"
    end
    return false, nil
end

return RelicSystem
