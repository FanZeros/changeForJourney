-- ============================================================================
-- backpack_grid_scroll_test - 仓库网格滚动绘制回归
-- 复现/防回归：BackpackGrids.drawEquipGrid 下滑后格子被错位裁剪框裁空
-- （"只显示第一页，下面全空" bug）。
--
-- 原理：stub 全部 nvg* 与绘制依赖，模拟 NanoVG 的 scissor/transform 语义
-- （scissor 矩形按设置时的 transform 变换到屏幕空间存储），跟踪每个装备格
-- 绘制时的有效裁剪区，断言可见格子真的可见（有效裁剪与格子屏幕矩形交集非空）。
--
-- 运行: ./.cli/UrhoXRuntime scripts/tests/backpack_grid_scroll_test.lua
--          -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- ============================================================================

local failures = {}
local passes = 0
local function check(cond, label)
    if cond then
        passes = passes + 1
        print("[PASS] " .. label)
    else
        failures[#failures + 1] = label
        print("[FAIL] " .. label)
    end
end

-- ======================== nvg stub：模拟 scissor + transform ========================

local CELL = 160
local COLS = 5

-- 状态
local vgState = {
    scissor = nil,        -- 当前有效屏幕裁剪 {x,y,w,h}（nil=无裁剪）
    ty = 0,               -- 当前累计 Y 平移（内容坐标 → 屏幕坐标偏移）
    stack = {},
    calls = {},           -- 记录 drawQualityBg 时的 {cy(内容), scissor(屏幕)}
    intersectCount = 0,   -- nvgIntersectScissor 调用次数
}

local function xformY(y) return y + vgState.ty end

local function intersectRect(a, b)
    if not a then return b end
    if not b then return a end
    local x1 = math.max(a.x, b.x)
    local y1 = math.max(a.y, b.y)
    local x2 = math.min(a.x + a.w, b.x + b.w)
    local y2 = math.min(a.y + a.h, b.y + b.h)
    if x2 <= x1 or y2 <= y1 then return { x = 0, y = 0, w = 0, h = 0 } end
    return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

local function resetVg()
    vgState.scissor = nil
    vgState.ty = 0
    vgState.stack = {}
    vgState.calls = {}
    vgState.intersectCount = 0
end

nvgSave = function(_)
    vgState.stack[#vgState.stack + 1] = { scissor = vgState.scissor, ty = vgState.ty }
end
nvgRestore = function(_)
    local s = table.remove(vgState.stack)
    if s then vgState.scissor, vgState.ty = s.scissor, s.ty end
end
nvgScissor = function(_, x, y, w, h)
    -- NanoVG 语义：按当前 transform 变换到屏幕空间
    vgState.scissor = { x = x, y = xformY(y), w = w, h = h }
end
nvgIntersectScissor = function(_, x, y, w, h)
    vgState.intersectCount = vgState.intersectCount + 1
    local rect = { x = x, y = xformY(y), w = w, h = h }
    vgState.scissor = intersectRect(vgState.scissor, rect)
end
nvgTranslate = function(_, _, dy) vgState.ty = vgState.ty + dy end
nvgBeginPath = function(_) end
nvgRoundedRect = function(_, _, _, _, _, _) end
nvgRect = function(_, _, _, _, _) end
nvgFillColor = function(_, _) end
nvgStrokeColor = function(_, _) end
nvgStrokeWidth = function(_, _) end
nvgFill = function(_) end
nvgStroke = function(_) end
nvgFontFace = function(_, _) end
nvgFontSize = function(_, _) end
nvgTextAlign = function(_, _) end
nvgText = function(_, _, _, _) end
nvgRGBA = function(r, g, b, a) return (a or 255) * 16777216 + b * 65536 + g * 256 + r end
NVG_ALIGN_RIGHT = 4; NVG_ALIGN_BOTTOM = 8
NVG_ALIGN_CENTER = 2; NVG_ALIGN_MIDDLE = 16
NVG_ALIGN_LEFT = 1; NVG_ALIGN_TOP = 32

-- ======================== 依赖 stub ========================

-- DarkIcon.drawQualityBg 是"格子真的画出来了"的信号：记录当时的内容坐标与有效屏幕裁剪
local DarkIconStub = {
    drawQualityBg = function(_, _, cx, cy, w, h)
        vgState.calls[#vgState.calls + 1] = {
            cx = cx, cy = cy, w = w, h = h,
            scissor = vgState.scissor and {
                x = vgState.scissor.x, y = vgState.scissor.y,
                w = vgState.scissor.w, h = vgState.scissor.h,
            } or nil,
            ty = vgState.ty,
        }
    end,
    drawIconDark = function() end,
    drawNine = function() end,
}
local DrawUtilStub = { drawImageCentered = function() end, drawShardIcon = function() end }

package.preload["core.DarkIcon"] = function() return DarkIconStub end
package.preload["core.DrawUtil"] = function() return DrawUtilStub end
package.preload["ui.widget.ImageCache"] = function()
    return { getEquipIcon = function() return 1 end, init = function() end }
end
package.preload["ui.widget.HeroFrame"] = function() return { draw = function() end } end
package.preload["ui.widget.QualityMark"] = function()
    return { init = function() end, draw = function() return true end }
end
package.preload["systems.TutorialManager"] = function()
    return { isActive = function() return false end, registerHotspot = function() end }
end

local PlayerStore = require("core.PlayerStore")
local EquipmentConfig = require("config.EquipmentConfig")
local EquipmentSystem = require("systems.EquipmentSystem")

-- 构造 60 件装备的库存（跨 12 行，超过一屏）
local fakeEquipData = { inventory = {}, equipped = {} }
local seq = 0
local ids = EquipmentConfig.BY_SLOT.accessory
for i = 1, 60 do
    seq = seq + 1
    local tid = ids[((i - 1) % #ids) + 1]
    fakeEquipData.inventory[tostring(seq)] =
        EquipmentSystem.generate(tid, 85, ((i - 1) % 6) + 1)
end
PlayerStore.Get = function(key)
    if key == "equipment" then return fakeEquipData end
    return nil
end

-- ======================== 绑定被测模块 ========================

-- 本测试 fakeVG 只模拟裁剪；角标由独立测试覆盖，避免真实helper用fakeVG加载纹理。
local originalRequire = require
local legacySetIcon = {
    drawBadge = function() return false end,
    hasBadge = function() return false end,
    levelLayout = function(_, cx, cy, size)
        return { x = cx + size * 0.5 - 8, y = cy + size * 0.5 - 6,
            fontSize = 40, align = NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM }
    end,
}
require = function(name)
    if name == "ui.widget.EquipmentSetIcon" then return legacySetIcon end
    return originalRequire(name)
end
local BackpackGrids = require("ui.backpack.BackpackGrids")

local GRID = {
    CELL_SIZE = CELL, CELL_RADIUS = 16, GAP = 30, COLS = COLS,
    MARGIN_LEFT = 80, FIRST_ROW_TOP = 670, CLIP_BOTTOM = 2020,
}
local CELL_COL_CX = {}
for c = 1, COLS do
    CELL_COL_CX[c] = GRID.MARGIN_LEFT + (c - 1) * (CELL + GRID.GAP) + CELL * 0.5
end
local DESIGN_W = 1080

local state = { scrollY = 0, scrollMax = 0 }
local function calcScrollMax(totalItems)
    local rows = math.ceil(totalItems / COLS)
    local contentH = rows * CELL + math.max(0, rows - 1) * GRID.GAP
    local clipH = GRID.CLIP_BOTTOM - GRID.FIRST_ROW_TOP
    return math.max(0, contentH - clipH)
end
local function clampScroll()
    state.scrollY = math.max(0, math.min(state.scrollMax, state.scrollY))
end

local grids = BackpackGrids.bind({
    GRID = GRID,
    CELL_COL_CX = CELL_COL_CX,
    CLIP_TOP = GRID.FIRST_ROW_TOP,
    CLIP_H = GRID.CLIP_BOTTOM - GRID.FIRST_ROW_TOP,
    DESIGN_W = DESIGN_W,
    DarkIcon = DarkIconStub,
    DrawUtil = DrawUtilStub,
    state = state,
    decomposeState = { active = false, selectedItems = {} },
    ITEM_DEFS = {},
    getItemIcon = function() return 1 end,
    getImgCheckmark = function() return 1 end,
    getImgLock = function() return 1 end,
    qualityChecked = function() return true end,
    getImgHeroIcons = function() return {} end,
    calcScrollMax = calcScrollMax,
    clampScroll = clampScroll,
})

-- ======================== 可见性判定 ========================

--- 一次绘制中，统计：
---   visible      = 画了品质底且有效裁剪与格子屏幕矩形交集非空（玩家真的看得见）
---   clippedEmpty = 格子屏幕矩形与外层可见窗口**相交**，但有效裁剪交集为空
---                  （= 玩家预期看到却全空的格子，即 bug 信号）
--- 完全出屏的格子（与窗口无交集）画了也会被外层 scissor 裁掉，属合法，不计入。
local function runAt(scrollY)
    resetVg()
    state.scrollY = scrollY
    grids.drawEquipGrid(vgState)
    local window = { x = 0, y = GRID.FIRST_ROW_TOP, w = DESIGN_W,
        h = GRID.CLIP_BOTTOM - GRID.FIRST_ROW_TOP }
    local visible, clippedEmpty = 0, 0
    for _, c in ipairs(vgState.calls) do
        -- 格子屏幕矩形（内容坐标 + 绘制时的累计平移）
        local top = c.cy - c.h * 0.5 + c.ty
        local cellRect = { x = c.cx - c.w * 0.5, y = top, w = c.w, h = c.h }
        local inWindow = intersectRect(window, cellRect)
        local inter = intersectRect(c.scissor, cellRect)
        if inter and inter.w > 1 and inter.h > 1 then
            visible = visible + 1
        elseif inWindow and inWindow.w > 1 and inWindow.h > 1 then
            clippedEmpty = clippedEmpty + 1
        end
    end
    return visible, clippedEmpty, #vgState.calls
end

-- 一屏可见行数：(2020-670+30)/(160+30) ≈ 7.3 → 7 行完整 + 边缘半行
local list = grids.getEquipList()
check(#list == 60, "构造 60 件装备列表（实际 " .. #list .. "）")

function Start()
    print("[backpack_grid_scroll_test] start")
    local ok, err = pcall(function()
        -- 第一页（scrollY=0）：应全部可见
        local v0, e0 = runAt(0)
        check(e0 == 0, "scrollY=0 无被裁空的格子（裁空=" .. e0 .. "）")
        check(v0 >= 35, "scrollY=0 可见格 ≥35（实际 " .. v0 .. "）")

        -- 下滑半屏：可见窗口应对应内容中部，所有画出的装备格必须真实可见
        local v1, e1 = runAt(600)
        check(e1 == 0, "scrollY=600 无被裁空的格子（裁空=" .. e1 .. "）")
        check(v1 >= 30, "scrollY=600 可见装备格 ≥30（实际 " .. v1 .. "）")

        -- 下滑到底：最后几行必须可见（这正是"下面都是空显示"的位置）
        local scrollMax = calcScrollMax(60)
        local v2, e2 = runAt(scrollMax)
        check(e2 == 0, "scrollY=max(" .. scrollMax .. ") 无被裁空的格子（裁空=" .. e2 .. "）")
        check(v2 >= 25, "滚动到底可见装备格 ≥25（实际 " .. v2 .. "）")

        -- 滚动到底时，列表尾部的装备（第 56-60 件）必须至少有一件被真实画出
        resetVg()
        state.scrollY = scrollMax
        grids.drawEquipGrid(vgState)
        local sawTail = false
        for _, c in ipairs(vgState.calls) do
            local row = math.floor((c.cy - GRID.FIRST_ROW_TOP - CELL * 0.5) / (CELL + GRID.GAP) + 0.5)
            if row >= 11 then sawTail = true end
        end
        check(sawTail, "滚动到底能画到第 12 行（尾部装备）")

        -- 紧凑布局切换后（applyLayout 改写 GRID 字段），裁剪应跟随新布局
        GRID.FIRST_ROW_TOP, GRID.CLIP_BOTTOM = 470, 1980
        local v3, e3 = runAt(400)
        check(e3 == 0, "紧凑布局 scrollY=400 无被裁空的格子（裁空=" .. e3 .. "）")
        check(v3 >= 30, "紧凑布局 scrollY=400 可见装备格 ≥30（实际 " .. v3 .. "）")
        GRID.FIRST_ROW_TOP, GRID.CLIP_BOTTOM = 670, 2020
    end)
    if not ok then
        print("[FAIL] 测试抛异常: " .. tostring(err))
        failures[#failures + 1] = "exception"
    end
    if #failures == 0 then
        print("[backpack_grid_scroll_test] ALL PASS (" .. passes .. " 断言)")
    else
        print("[backpack_grid_scroll_test] FAILURES=" .. #failures)
        for _, m in ipairs(failures) do print("  - " .. m) end
    end
    engine:Exit()
end
