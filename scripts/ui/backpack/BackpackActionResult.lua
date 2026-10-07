-- ============================================================================
-- BackpackActionResult - 背包服务端操作结果回调
-- 复用原装备关联与道具详情状态；分解就绪标记在回执时读取。
-- ============================================================================

local ActionResult = {}

---@param deps table
function ActionResult.bind(deps)
    local equipLink, Protocol = deps.equipLink, deps.Protocol
    local BlacksmithDecompose, itemDetState = deps.BlacksmithDecompose, deps.itemDetState
    local getDecomposeReady = deps.getDecomposeReady

    --- 服务端操作结果回调
    ---@param data table
    return function(data)
        equipLink.onActionResult(data)
        if data.action == Protocol.ACTION_TYPES.DECOMPOSE_EQUIP then
            -- [分解入仓 0929] 分解请求由 BlacksmithDecompose（仓库分解 tab）发出，
            -- 回执转发给它（内部 pendingDecompose 门控保证只处理自己发起的请求，
            -- 与 ClientMessageHandler 同时广播给 BlacksmithPage 的路径互不重复弹奖）
            if getDecomposeReady() then
                BlacksmithDecompose.onActionResult(data)
            end
            return
        end

        if data.action == Protocol.ACTION_TYPES.CONVERT_UR_SHARD then
            itemDetState.urConvertPending = false
            if not data.success then
                local LootBoxPage = require("ui.loot.LootBoxPage")
                if LootBoxPage.showToast then
                    LootBoxPage.showToast(data.reason or "转化失败")
                end
            end
            return
        end

        if data.action == Protocol.ACTION_TYPES.RESTORE_UR_SHARD_CONVERT then
            itemDetState.urConvertPending = false
            local LootBoxPage = require("ui.loot.LootBoxPage")
            if data.success then
                if LootBoxPage.showToast then LootBoxPage.showToast("转化次数已恢复") end
            elseif LootBoxPage.showToast then
                LootBoxPage.showToast(data.reason or "恢复失败")
            end
        end
    end
end

return ActionResult
