-- ============================================================================
-- RelicPage - 遗物祭坛宿主页面（左栏二级页门面）
-- 承载 RelicBagPanel（背包网格）+ RelicDetailPanel（详情弹窗）+ RelicReforgePanel（洗练），
-- 负责三者的初始化接线、页面生命周期、draw 层叠与输入分发。
--
-- 历史：接线原在已删除的 RelicPanel（全屏封兽祭阵页，依赖已缺失的祭阵座位大图）。
-- 本页把「镶嵌本座」改为直接放入遗物类型对应的本座位（RelicAltar.TYPE_TO_SLOT），
-- 无需祭阵放置模式；座位已占用时走替换（findReplaceTarget）。
--
-- 坐标系：1080×2400 设计分辨率；作为横屏左栏二级页，外层水平滑入（dirSign=-1）。
-- ============================================================================

local DrawUtil          = require("core.DrawUtil")
local RelicBagPanel     = require("ui.relic.RelicBagPanel")
local RelicDetailPanel  = require("ui.relic.RelicDetailPanel")
local RelicReforgePanel = require("ui.relic.RelicReforgePanel")
local RelicSystem       = require("systems.RelicSystem")
local RelicAltar        = require("systems.RelicAltar")
local PlayerStore       = require("core.PlayerStore")
local UiToast           = require("core.UiToast")

local RelicPage = {}

-- ======================== 动画常量（左栏二级页水平滑入范式）========================

local ANIM_OPEN_DUR  = 0.35
local ANIM_CLOSE_DUR = 0.28

local state = {
    open      = false,
    closing   = false,
    openTime  = 0,
    closeTime = 0,
    inited    = false,
}

local function getMaxStageId()
    local battleData = PlayerStore.Get("battle")
    return battleData and tonumber(battleData.maxStageId) or 0
end

--- 把背包遗物镶嵌到其类型对应的本座位；座位被占则替换其中较低品质者。
---@param relic table 背包遗物
local function embedToNativeSlot(relic)
    if not relic then return end
    local slotId = RelicAltar.TYPE_TO_SLOT[tonumber(relic.type) or 0]
    if not slotId then
        UiToast.show("该遗物无对应祭位")
        return
    end
    if not RelicAltar.isSlotUnlocked(slotId, getMaxStageId()) then
        UiToast.show(RelicAltar.unlockHint(slotId))
        return
    end
    -- 优先替换：背包件比祭阵同词缀件更优时替换，否则直接放入空座
    local replaceTarget = RelicSystem.findReplaceTarget(relic)
    if replaceTarget then
        RelicSystem.requestReplace(relic.id, replaceTarget.id, function(success, reason)
            if not success then UiToast.show(reason or "替换失败") end
        end)
    else
        RelicSystem.requestPlace(relic.id, slotId, function(success, reason)
            if not success then UiToast.show(reason or "镶嵌失败") end
        end)
    end
end

-- ======================== 初始化 ========================

--- 初始化三面板并接线（迁移自旧 RelicPanel.init）
--- 幂等：子面板 init 无 guard（每次 nvgCreateImage），故在此层拦截重复初始化
---@param vg any NanoVG 上下文
function RelicPage.init(vg)
    if state.inited then return end
    RelicBagPanel.init(vg)
    RelicDetailPanel.init(vg)
    RelicReforgePanel.init(vg)

    -- 背包选中 → 打开详情
    RelicBagPanel.setOnSelectCallback(function(relic)
        if relic then
            RelicDetailPanel.show(relic, "bag")
        end
    end)

    -- 详情关闭 → 清除背包选中态
    RelicDetailPanel.setOnClose(function()
        RelicBagPanel.clearSelection()
    end)

    -- 详情「洗练」→ 关详情、开洗练面板
    RelicDetailPanel.setOnReforge(function(relic)
        RelicDetailPanel.hide()
        RelicReforgePanel.show(relic)
    end)

    -- 详情「装备/替换/取下」
    RelicDetailPanel.setOnEquip(function(relic, location, replaceTarget)
        if location == "replace" and replaceTarget then
            RelicDetailPanel.hide()
            RelicBagPanel.close()
            RelicSystem.requestReplace(relic.id, replaceTarget.id, function(success, reason)
                if not success then UiToast.show(reason or "替换失败") end
            end)
        elseif location == "bag" then
            -- 镶嵌本座（直接放入类型对应本座位，无需祭阵放置模式）
            RelicDetailPanel.hide()
            RelicBagPanel.close()
            embedToNativeSlot(relic)
        elseif location == "grid" then
            RelicDetailPanel.hide()
            RelicSystem.requestRemoveFromGrid(relic.id, function(success, reason)
                if not success then UiToast.show(reason or "取下失败") end
            end)
        end
    end)

    state.inited = true
    print("[RelicPage] init OK")
end

-- ======================== 生命周期 ========================

function RelicPage.open()
    if not state.inited then return end
    state.open      = true
    state.closing   = false
    state.openTime  = time.elapsedTime
    RelicBagPanel.open()
    print("[RelicPage] open")
end

function RelicPage.close()
    if state.closing then return end
    state.closing   = true
    state.closeTime = time.elapsedTime
    -- 子面板一并收起
    if RelicReforgePanel.isVisible() then RelicReforgePanel.hide() end
    if RelicDetailPanel.isVisible() then RelicDetailPanel.hide() end
    RelicBagPanel.close()
    print("[RelicPage] close")
end

function RelicPage.isOpen()
    return state.open
end

--- seamBack（中缝返回）需要的动画四元组
---@return number openTime
---@return number closeTime
---@return number openDur
---@return number closeDur
function RelicPage.getSeamAnim()
    return state.openTime, state.closeTime, ANIM_OPEN_DUR, ANIM_CLOSE_DUR
end

--- 关闭动画是否已播完（播完后真正把 open 置 false）
local function updateLifecycle()
    if not state.open then return end
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        if elapsed >= ANIM_CLOSE_DUR then
            state.closing = false
            state.open    = false
        end
    end
end

-- ======================== 绘制 ========================

--- 外层水平滑入；内部按层叠顺序画 背包 → 详情 → 洗练
---@param vg any
function RelicPage.draw(vg)
    if not state.open then return end
    updateLifecycle()
    if not state.open then return end

    local ox = DrawUtil.seamSlideX(-1, state.openTime, state.closeTime,
                                   ANIM_OPEN_DUR, ANIM_CLOSE_DUR, 1080)
    if ox ~= 0 then
        nvgSave(vg)
        nvgTranslate(vg, ox, 0)
    end

    -- 层叠：背包在底，详情弹窗居中，洗练面板最上
    RelicBagPanel.draw(vg)
    if RelicDetailPanel.isVisible() then
        RelicDetailPanel.draw(vg)
    end
    if RelicReforgePanel.isVisible() then
        RelicReforgePanel.draw(vg)
    end

    if ox ~= 0 then
        nvgRestore(vg)
    end
end

-- ======================== 输入分发 ========================
-- 优先级：洗练 > 详情 > 背包（上层弹窗先消费）

--- 点击（dx,dy 为 1080×2400 设计坐标）
---@return boolean 是否消费
function RelicPage.handleInput(dx, dy)
    if not state.open or state.closing then return false end
    if RelicReforgePanel.isPoolOpen() then
        return RelicReforgePanel.handlePoolTap(dx, dy)
    end
    if RelicReforgePanel.isVisible() then
        return RelicReforgePanel.handleTap(dx, dy)
    end
    if RelicDetailPanel.isVisible() then
        return RelicDetailPanel.handleTap(dx, dy)
    end
    return RelicBagPanel.handleTap(dx, dy)
end

function RelicPage.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    if RelicReforgePanel.isPoolOpen() then
        return RelicReforgePanel.handlePoolDragBegin(dx, dy)
    end
    return RelicBagPanel.handleDragBegin(dx, dy)
end

function RelicPage.handleDragMove(dx, dy)
    if not state.open or state.closing then return false end
    if RelicReforgePanel.isPoolOpen() then
        return RelicReforgePanel.handlePoolDragMove(dx, dy)
    end
    return RelicBagPanel.handleDragMove(dx, dy)
end

function RelicPage.handleDragEnd(dx, dy)
    if not state.open or state.closing then return false end
    if RelicReforgePanel.isPoolOpen() then
        return RelicReforgePanel.handlePoolDragEnd(dx, dy)
    end
    return RelicBagPanel.handleDragEnd(dx, dy)
end

function RelicPage.handleScroll(wheel, msx, msy)
    if not state.open or state.closing then return false end
    if RelicReforgePanel.isPoolOpen() then
        return RelicReforgePanel.handlePoolScroll(wheel)
    end
    return RelicBagPanel.handleScroll(wheel)
end

return RelicPage
