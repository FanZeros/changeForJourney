-- ============================================================================
-- BlacksmithResults - 装备数据刷新与操作结果转发（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local state = deps.state
    local BlacksmithDecompose = deps.BlacksmithDecompose
    local BlacksmithEnhance = deps.BlacksmithEnhance
    local BlacksmithRefine = deps.BlacksmithRefine
    local ClientDispatcher = deps.ClientDispatcher
    local PlayerStore = deps.PlayerStore
    local deriveSelectedEquip = deps.deriveSelectedEquip
    local _enhanceCache = deps.enhanceCache

    local function onEquipmentDataUpdate(equipmentData)
        if not state.open then return end

        -- 刷新分解页面背包数据
        BlacksmithDecompose.refreshBackpackItems()

        -- 洗练 tab 下：按 seq 从最新 inventory 中刷新独立选中的装备，不走 deriveSelectedEquip
        if state.tab == "xilian" and state.selectedEquip then
            local seq = state.selectedEquip.seq
            if seq then
                local eqData = equipmentData or ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
                if eqData and eqData.inventory then
                    local refreshed = eqData.inventory[tostring(seq)]
                    if refreshed then
                        state.selectedEquip = refreshed
                        if BlacksmithRefine.hasPreview() then
                            -- 有洗练预览时仅重算消耗，避免覆盖预览/动画状态
                            BlacksmithRefine.refreshCostOnly()
                        else
                            BlacksmithRefine.updateRefineData(refreshed)
                        end
                        print("[BlacksmithPage] 洗练tab: 按seq=" .. tostring(seq) .. "刷新装备数据+消耗")
                    else
                        -- 装备可能已被分解/删除
                        state.selectedEquip = nil
                        BlacksmithRefine.updateRefineData(nil)
                        print("[BlacksmithPage] 洗练tab: seq=" .. tostring(seq) .. "装备已不存在，重置")
                    end
                end
            end
            return
        end

        -- 强化/分解 tab：重新推导当前选中装备（服务端推送后英雄装备可能变化）
        deriveSelectedEquip()
        print("[BlacksmithPage] 装备数据已刷新（deriveSelectedEquip）")
    end

    --- 当服务端返回 action result 时处理强化/洗练特有数据
    ---@param data table action result 数据
    local function onActionResult(data)
        if not state.open then return end

        -- 任何操作结果都可能影响金币/卷轴/强化等级 → 标脏角标缓存
        _enhanceCache.dirty = true

        -- 失败响应（无特定字段）→ 按当前 Tab 转发到对应子模块以释放门控
        if not data.enhanceOutcome and not data.refinePreview and not data.decomposed and not data.refineReplaced then
            if state.tab == "qianghua" then
                BlacksmithEnhance.onActionResult(data)
            elseif state.tab == "xilian" then
                BlacksmithRefine.onActionResult(data)
            elseif state.tab == "fenjie" then
                BlacksmithDecompose.onActionResult(data)
            end
            return
        end

        -- 强化结果 → 委托给 Enhance 子模块
        if data.enhanceOutcome then
            BlacksmithEnhance.onActionResult(data)
        end

        -- 洗练结果预览 → 委托给 Refine 子模块
        if data.refinePreview then
            BlacksmithRefine.onActionResult(data)
        end

        -- 分解结果处理 → 委托给 Decompose 子模块
        if data.decomposed then
            BlacksmithDecompose.onActionResult(data)
        end

        -- 替换成功 → 委托给 Refine 子模块
        if data.refineReplaced then
            BlacksmithRefine.onActionResult(data)
        end
    end


    return {
        onEquipmentDataUpdate = onEquipmentDataUpdate,
        onActionResult = onActionResult,
    }
end

return M
