-- ============================================================================
-- LootBox - 遗匣数据与回调门面。地点由 TownScene 绘制，页面只在左栏绘制。
-- ============================================================================
local LootBoxPage = require("ui.loot.LootBoxPage")
local LootBoxSystem = require("systems.LootBoxSystem")
local DrawUtil = require("core.DrawUtil")
local RewardPopup = require("ui.hud.popup.RewardPopup")
local UiToast = require("core.UiToast")
local LootBox = {}

-- 权威通知保留累计值；展示层只累计基线之后的增量，不改存档或资源到账。
local NOTICE_BATCH_COUNT = 100
local MAX_SAFE_COUNT = 9007199254740991
local noticeInitialized = false
local noticeBaseline = { seq = 0, count = 0, essence = 0 }
local pendingNotice = { count = 0, essence = 0 }
local showingNotice = false

---@class AutoDecomposeNoticeSnapshot
---@field seq number
---@field count number
---@field essence number

---@param value any
---@return number?
local function noticeInteger(value)
    local n = tonumber(value)
    if not n or n ~= n or n < 0 or n > MAX_SAFE_COUNT or n ~= math.floor(n) then return nil end
    return math.floor(n)
end

---@param notice any
---@return AutoDecomposeNoticeSnapshot?
local function snapshotNotice(notice)
    if type(notice) ~= "table" then return nil end
    local seq = noticeInteger(notice.seq)
    local count = noticeInteger(notice.count)
    local essence = noticeInteger(notice.essence)
    if not seq or not count or not essence then return nil end
    return { seq = seq, count = count, essence = essence }
end

---@param snapshot AutoDecomposeNoticeSnapshot?
local function resetNotice(snapshot)
    noticeInitialized = snapshot ~= nil
    noticeBaseline = snapshot or { seq = 0, count = 0, essence = 0 }
    pendingNotice.count, pendingNotice.essence = 0, 0
end

local function showPendingNotice()
    if showingNotice or pendingNotice.count < NOTICE_BATCH_COUNT or pendingNotice.essence <= 0
        or RewardPopup.isOpen() then return end
    local count, essence = pendingNotice.count, pendingNotice.essence
    -- 先消费展示缓冲，防止 show 回调重入时重复提示；这里不发放任何资源。
    pendingNotice.count, pendingNotice.essence = 0, 0
    showingNotice = true
    -- 后台到账通知仅作穿透短提示，不借当前焦点打开领奖模态或清掉页面悬停。
    UiToast.show("自动分解 " .. count .. " 件 · 获得精粹 " .. essence, 3.0)
    showingNotice = false
    print("[LootBox] 自动分解合并提示: 新增件数=" .. count .. " 精粹=+" .. essence)
end

---@param notice any
---@param reset boolean?
local function collectNotice(notice, reset)
    if notice == nil then
        resetNotice({ seq = 0, count = 0, essence = 0 })
        return
    end
    local current = snapshotNotice(notice)
    if not current then
        resetNotice(nil)
        return
    end
    if reset or not noticeInitialized then
        resetNotice(current)
        print("[LootBox] 自动分解展示基线: seq=" .. current.seq .. " count=" .. current.count)
        return
    end
    if current.seq == noticeBaseline.seq and current.count == noticeBaseline.count
        and current.essence == noticeBaseline.essence then return end
    if current.seq <= noticeBaseline.seq or current.count < noticeBaseline.count
        or current.essence < noticeBaseline.essence then
        -- 清档/回档/计数重建：重新建基线，不把另一生命周期的数据混进旧缓冲。
        resetNotice(current)
        print("[LootBox] 自动分解计数重建，重置展示基线")
        return
    end
    local count = current.count - noticeBaseline.count
    local essence = current.essence - noticeBaseline.essence
    noticeBaseline = current
    if count <= 0 or essence <= 0 then return end
    pendingNotice.count = pendingNotice.count + count
    pendingNotice.essence = pendingNotice.essence + essence
end

local seedCount = 0
local seedSummary = {}
local lootboxData_ = { seeds = {} }
---@type string|nil
local rateGoldText = nil
---@type string|nil
local rateExpText = nil

--- 挂机速率数值统一走公共 NumberUtil（k/M/B/T），不再单独用千分位。
local function formatNumber(n)
    return require("core.NumberUtil").format(n)
end

function LootBox.setRates(goldPerMin, expPerMin)
    rateGoldText = (goldPerMin and goldPerMin > 0) and ("金币+" .. formatNumber(goldPerMin) .. "/分钟") or nil
    rateExpText = (expPerMin and expPerMin > 0) and ("经验+" .. formatNumber(expPerMin) .. "/分钟") or nil
end

--- 由城镇地点调用，无全局悬浮图标/热区。
function LootBox.drawRates(vg, cx, cy)
    if rateGoldText then
        DrawUtil.drawTextStroke(vg, cx, cy, rateGoldText, 28,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 225, 202, 132, 3)
    end
    if rateExpText then
        DrawUtil.drawTextStroke(vg, cx, cy + 44, rateExpText, 28,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 154, 210, 202, 3)
    end
end

function LootBox.init(vg)
    LootBoxPage.init(vg)
end

local function syncSummary()
    LootBoxSystem.revealLegacy(lootboxData_)
    -- 摘要含确定装备与原存储索引，筛选不改变领取目标。
    seedSummary = LootBoxSystem.getSummary(lootboxData_)
    seedCount = 0
    for _, entry in ipairs(seedSummary) do
        seedCount = seedCount + (entry.equip and 1 or (entry.count or 1))
    end
    if LootBoxPage.isOpen() then LootBoxPage.refresh(seedSummary) end
end

--- 恢复/初始化只建立累计基线；实时更新仅收集新增分解数量与精粹。
---@param lootboxData table?
---@param options? { resetNotice: boolean? }
function LootBox.updateSeedData(lootboxData, options)
    lootboxData_ = (lootboxData and lootboxData.seeds) and lootboxData or { seeds = {} }
    collectNotice(lootboxData_.autoDecomposeNotice, options and options.resetNotice)
    syncSummary()
    -- 由 update 在结算回调结束后统一提示，避免同帧的首通/离线奖励覆盖本批通知。
end

-- 兼容战斗掉落提示调用；件数与页面始终以 updateSeedData 的权威数据为准。
function LootBox.addSeedHint(_quality, _level) end
function LootBox.getCount() return seedCount end
function LootBox.setOnClaimAll(callback) LootBoxPage.setOnClaimAll(callback) end
function LootBox.setOnClaimOne(callback) LootBoxPage.setOnClaimOne(callback) end
function LootBox.setOnDecomposeAll(callback) LootBoxPage.setOnDecomposeAll(callback) end
function LootBox.setOnDecomposeOne(callback) LootBoxPage.setOnDecomposeOne(callback) end
function LootBox.setOnAutoDecompose(callback) LootBoxPage.setOnAutoDecompose(callback) end

--- 启动接线：TownScene.setOnLootBoxClick(LootBox.openPage)。空遗匣也正常打开。
function LootBox.openPage()
    syncSummary()
    LootBoxPage.open(seedSummary)
end
function LootBox.refreshPage() syncSummary() end
function LootBox.isPageOpen() return LootBoxPage.isOpen() end
function LootBox.drawPage(vg) LootBoxPage.draw(vg) end
function LootBox.update(dt)
    LootBoxPage.update(dt)
    showPendingNotice()
end
function LootBox.handleInput(dx, dy) return LootBoxPage.handleInput(dx, dy) end
function LootBox.handleRightClick(dx, dy) return LootBoxPage.handleRightClick(dx, dy) end
function LootBox.handleDragBegin(dx, dy) return LootBoxPage.handleDragBegin(dx, dy) end
function LootBox.handleDragMove(dx, dy) return LootBoxPage.handleDragMove(dx, dy) end
function LootBox.handleDragEnd(dx, dy) return LootBoxPage.handleDragEnd(dx, dy) end
function LootBox.handleScroll(wheel) return LootBoxPage.handleScroll(wheel) end

return LootBox
