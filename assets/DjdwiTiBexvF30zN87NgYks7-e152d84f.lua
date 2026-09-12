-- ============================================================================
-- RedeemService - 兑换码业务逻辑
-- 职责: 校验兑换码 + 发放奖励（纯业务，禁止网络 IO）
-- 层级: server/redeem  |  通过 PDM 读写数据
-- ============================================================================

local PDM            = require("server.character.PlayerDataManager")
local RedeemConfig   = require("shared.redeem.RedeemConfig")
local CurrencyService = require("server.currency.CurrencyService")
local MarketService   = require("server.market.MarketService")

local RedeemService = {}

-- ======================== 加载一次性码批次（服务端专属） ========================

--- 批次模块列表（仅服务端可访问，客户端无法获取码值）
local BATCH_MODULES = {
    "server.redeem.RedeemBatch001",
    "server.redeem.RedeemBatch002",
}

--- 将批次码注入 RedeemConfig.CODE_MAP（启动时执行一次）
local function loadBatchCodes()
    local totalLoaded = 0
    for _, batchPath in ipairs(BATCH_MODULES) do
        local ok, batch = pcall(require, batchPath)
        if ok and batch and batch.CODES then
            for _, code in ipairs(batch.CODES) do
                local entry = {
                    code     = code,
                    type     = "onetime",
                    duration = "permanent",
                    rewards  = batch.REWARDS,
                }
                RedeemConfig.CODES[#RedeemConfig.CODES + 1] = entry
                RedeemConfig.CODE_MAP[string.upper(code)] = entry
                totalLoaded = totalLoaded + 1
            end
            print("[RedeemService] loaded batch " .. batchPath .. " (" .. #batch.CODES .. " codes)")
        elseif not ok then
            print("[RedeemService][ERROR] failed to load batch: " .. batchPath .. " err=" .. tostring(batch))
        end
    end
    print("[RedeemService] total batch codes loaded: " .. totalLoaded)
end

-- ======================== 一次性码全局已用记录 ========================

--- 全局已用一次性码（内存缓存）: { [CODE] = uid }
local globalUsedOnetime_ = {}

--- serverCloud 存储 key
local GLOBAL_REDEEM_UID = "REDEEM_GLOBAL"
local GLOBAL_REDEEM_KEY = "global_used_onetime_codes"

--- 初始化标记
local initialized_ = false

--- 从 serverCloud 加载全局一次性码使用记录（服务器启动时调用一次）
function RedeemService.Init(callback)
    if initialized_ then
        if callback then callback(true) end
        return
    end

    -- 先加载批次码到 CODE_MAP（服务端专属数据）
    loadBatchCodes()

    print("[RedeemService] Init: loading global onetime codes...")
    ---@diagnostic disable-next-line: param-type-mismatch
    serverCloud:Get(GLOBAL_REDEEM_UID, GLOBAL_REDEEM_KEY, {
        ok = function(scores)
            local data = scores and scores[GLOBAL_REDEEM_KEY]
            if type(data) == "table" then
                globalUsedOnetime_ = data
            else
                globalUsedOnetime_ = {}
            end
            initialized_ = true
            print("[RedeemService] Init done, " .. RedeemService.GetUsedOnetimeCount() .. " onetime codes used globally")
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[RedeemService][ERROR] Init failed code=" .. tostring(code)
                .. " reason=" .. tostring(reason))
            -- 即使加载失败也标记初始化完成，使用空表（安全：最差结果是同一码被多人兑换）
            initialized_ = true
            if callback then callback(false) end
        end,
    })
end

--- 持久化全局一次性码记录到 serverCloud
local function persistGlobalUsed()
    local commit = serverCloud:BatchCommit("redeem_global_save")
    ---@diagnostic disable-next-line: param-type-mismatch
    commit:ScoreSet(GLOBAL_REDEEM_UID, GLOBAL_REDEEM_KEY, globalUsedOnetime_)
    commit:Commit({
        ok = function()
            -- 静默成功
        end,
        error = function(code, reason)
            print("[RedeemService][ERROR] persist global used failed code=" .. tostring(code)
                .. " reason=" .. tostring(reason))
        end,
    })
end

--- 获取全服已用一次性码数量
function RedeemService.GetUsedOnetimeCount()
    local count = 0
    for _ in pairs(globalUsedOnetime_) do count = count + 1 end
    return count
end

-- ======================== 兑换逻辑 ========================

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

    -- 一次性码：检查全服是否已被其他人使用
    if codeDef.type == "onetime" then
        local usedByUid = globalUsedOnetime_[code]
        if usedByUid then
            return false, "该兑换码已被使用"
        end
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
    local grantedCard = false
    for _, reward in ipairs(codeDef.rewards or {}) do
        if reward.type == "privilege_card" then
            grantedCard = true
        end
        if not CurrencyService.GrantReward(uid, reward) then
            failedRewards[#failedRewards + 1] = reward.type
            print("[RedeemService] WARN grant failed uid=" .. tostring(uid)
                .. " code=" .. code .. " type=" .. tostring(reward.type))
        end
    end

    -- 特权卡激活后立即发放当日 100 特权点 + 填满特权里程进度
    local displayRewards = {}
    for _, reward in ipairs(codeDef.rewards or {}) do
        displayRewards[#displayRewards + 1] = reward
    end
    local cardActivate = nil
    if grantedCard then
        cardActivate = MarketService.OnPrivilegeCardActivated(uid)
        if cardActivate and cardActivate.grantedPoints then
            displayRewards[#displayRewards + 1] = {
                type = "privilege_point",
                amount = cardActivate.grantedPoints,
            }
        end
    end

    -- 标记已使用（即使部分奖励失败也标记，防止重复兑换）
    redeemData.usedCodes[code] = true
    PDM.MarkDirty(uid, "redeem")

    -- 一次性码：标记全局已用并持久化
    if codeDef.type == "onetime" then
        globalUsedOnetime_[code] = uid
        persistGlobalUsed()
    end

    print("[RedeemService] Redeem uid=" .. tostring(uid) .. " code=" .. code
        .. " type=" .. tostring(codeDef.type)
        .. (#failedRewards > 0 and (" failedRewards=" .. table.concat(failedRewards, ",")) or ""))

    return true, nil, {
        code = code,
        rewards = displayRewards,
        privilegeCardActivated = grantedCard or nil,
        privilegePayload = cardActivate and cardActivate.privPayload or nil,
    }
end

return RedeemService
