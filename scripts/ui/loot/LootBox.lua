-- ============================================================================
-- LootBox - 遗匣数据与回调门面。地点由 TownScene 绘制，页面只在左栏绘制。
-- ============================================================================
local LootBoxPage = require("ui.loot.LootBoxPage")
local LootBoxSystem = require("systems.LootBoxSystem")
local DrawUtil = require("core.DrawUtil")
local LootBox = {}

local seedCount = 0
local seedSummary = {}
local lootboxData_ = { seeds = {} }
---@type string|nil
local rateGoldText = nil
---@type string|nil
local rateExpText = nil

local function formatNumber(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,")
    return tostring(out):reverse():gsub("^,", "")
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

function LootBox.updateSeedData(lootboxData)
    lootboxData_ = (lootboxData and lootboxData.seeds) and lootboxData or { seeds = {} }
    syncSummary()
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
function LootBox.update(dt) LootBoxPage.update(dt) end
function LootBox.handleInput(dx, dy) return LootBoxPage.handleInput(dx, dy) end
function LootBox.handleDragBegin(dx, dy) return LootBoxPage.handleDragBegin(dx, dy) end
function LootBox.handleDragMove(dx, dy) return LootBoxPage.handleDragMove(dx, dy) end
function LootBox.handleDragEnd(dx, dy) return LootBoxPage.handleDragEnd(dx, dy) end
function LootBox.handleScroll(wheel) return LootBoxPage.handleScroll(wheel) end

return LootBox
