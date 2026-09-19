-- ============================================================================
-- RedeemService - 兑换码业务逻辑（单机本地版）
-- 职责: 校验固定兑换码 + 发放奖励（纯业务，无网络 IO、无云端依赖）
-- 层级: server/redeem  |  通过 PDM 读写数据
-- 说明: 单机版使用 10 个固定兑换码（阶梯钻石额度），每玩家每码限用一次，
--       防重复由玩家存档 usedCodes 保证，无需全服一次性码记录。
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local RedeemConfig    = require("shared.redeem.RedeemConfig")
local CurrencyService = require("server.currency.CurrencyService")

local RedeemService = {}

--- 初始化标记（保留兼容 Server.lua 启动调用）
local initialized_ = false

--- 初始化（单机本地版：固定码在 RedeemConfig 中静态定义，无需加载/云端记录）
---@param callback function|nil
function RedeemService.Init(callback)
    initialized_ = true
    if callback then callback(true) end
end

--- 兑换码兑换
---@param uid number
---@param code string 原始输入的兑换码
---@return boolean ok
---@return string|nil errReason
---@return table|nil result { code, rewards }
function RedeemService.Redeem(uid, code)
    if not code or type(code) ~= "string" then
        return false, "参数错误"
    end

    code = string.upper(code)
    if #code == 0 or #code > 50 then
        return false, "兑换码格式无效"
    end

    -- 查找兑换码配置
    local codeDef = RedeemConfig.CODE_MAP[code]
    if not codeDef then
        return false, "兑换码无效"
    end

    -- 获取玩家兑换码使用记录
    local redeemData = PDM.GetModule(uid, "redeem")
    if not redeemData then
        return false, "数据异常"
    end

    -- 检查该玩家是否已使用过此码
    if redeemData.usedCodes[code] then
        return false, "该兑换码已使用"
    end

    -- 发放奖励（检查返回值，记录失败的奖励）
    local failedRewards = {}
    for _, reward in ipairs(codeDef.rewards or {}) do
        if not CurrencyService.GrantReward(uid, reward) then
            failedRewards[#failedRewards + 1] = reward.type
            print("[RedeemService] WARN grant failed uid=" .. tostring(uid)
                .. " code=" .. code .. " type=" .. tostring(reward.type))
        end
    end

    -- 标记已使用（即使部分奖励失败也标记，防止重复兑换）
    redeemData.usedCodes[code] = true
    PDM.MarkDirty(uid, "redeem")

    print("[RedeemService] Redeem uid=" .. tostring(uid) .. " code=" .. code
        .. (#failedRewards > 0 and (" failedRewards=" .. table.concat(failedRewards, ",")) or ""))

    return true, nil, {
        code    = code,
        rewards = codeDef.rewards or {},
    }
end

return RedeemService
