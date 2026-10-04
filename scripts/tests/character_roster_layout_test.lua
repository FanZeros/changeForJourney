-- 右侧角色栏：实际绘图与共享HeroFrame的碎片/职业避让、单人战力和点击中心。
function Start()
    local nativeRequire = require
    local originals = {}
    local records, images, frames, targets = {}, {}, {}, {}
    local fontSize = 24
    local function noop() end
    local function replace(name, fn) originals[name] = _G[name]; _G[name] = fn end
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgBeginPath", "nvgRect", "nvgFillColor", "nvgFill",
        "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgIntersectScissor", "nvgScissor",
        "nvgResetScissor", "nvgTranslate", "nvgGlobalAlpha", "nvgFontFace", "nvgTextAlign" }) do replace(name, noop) end
    replace("nvgFontSize", function(_, size) fontSize = size end)
    replace("nvgTextBounds", function(_, _, _, text) return utf8.len(text) * fontSize * 0.55 end)
    replace("nvgText", noop)
    replace("nvgRoundedRect", function(_, x, y, w, h)
        records[#records + 1] = { kind = "rect", x = x, y = y, w = w, h = h }
    end)
    replace("nvgCreateImage", function(_, path) images[#images + 1] = path; return #images end)
    local drawUtil = {
        drawImageCentered = function(_, image, cx, cy, w, h)
            records[#records + 1] = { kind = "image", path = images[image], cx = cx, cy = cy, w = w, h = h }
        end,
        drawTextStroke = function(_, x, y, text, size)
            records[#records + 1] = { kind = "text", x = x, y = y, text = text, size = size }
        end,
        hitTest = function(x, y, cx, cy, w, h) return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5 end,
    }
    local mocks = {
        ["core.DrawUtil"] = drawUtil,
        ["config.HeroAssetUtil"] = { ensureIcon = function() return 1 end },
        ["core.HorizonBg"] = { draw = noop },
        ["systems.TutorialManager"] = { isActive = function() return true end, getNewHeroId = function() return 3 end,
            registerHotspot = function(key, cx, cy) targets[key] = { cx = cx, cy = cy } end },
    }
    require = function(name) return mocks[name] or nativeRequire(name) end
    local checkCount = 0
    local function check(value, label) checkCount = checkCount + 1; assert(value, label) end
    local ok, err = pcall(function()
        local Frame = nativeRequire("ui.widget.HeroFrame")
        for _, size in ipairs({ 64, 148, 176, 256 }) do
            records = {}
            Frame.draw({}, { cx = 200, cy = 200, size = size, heroId = 1, state = "unowned", showClass = true,
                showShards = true, shards = 5, shardMax = 10 })
            local class, bar
            for _, r in ipairs(records) do
                if r.kind == "image" and r.path and r.path:find("ICON_ZY_", 1, true) then class = r end
                if r.kind == "rect" and math.abs(r.w - size * 0.56) < 0.001 then bar = r end
            end
            check(class and bar and bar.x + bar.w < class.cx - class.w * 0.5,
                "碎片条与职业图标横向不重叠: " .. size)
            check(bar.x >= 200 - size * 0.5 and bar.y + bar.h <= 200 + size * 0.5,
                "碎片条留在头像左侧占位内: " .. size)
        end
        records = {}
        Frame.draw({}, { cx = 200, cy = 200, size = 148, heroId = 1, state = "unowned", showClass = true,
            showShards = true, shards = 1000000000000, shardMax = 10 })
        local shardIcon, shardText, classIcon
        for _, r in ipairs(records) do
            if r.kind == "image" and r.path and r.path:find("ICON_SP", 1, true) then shardIcon = r end
            if r.kind == "image" and r.path and r.path:find("ICON_ZY_", 1, true) then classIcon = r end
            if r.kind == "text" and r.text:find("/10", 1, true) then shardText = r end
        end
        local numberWidth = utf8.len(shardText.text) * shardText.size * 0.55
        check(shardText.x - numberWidth * 0.5 - 2 > shardIcon.cx + shardIcon.w * 0.5,
            "大额碎片数字不会盖住左侧碎片图标")
        check(shardText.x + numberWidth * 0.5 + 2 < classIcon.cx - classIcon.w * 0.5,
            "大额碎片数字不会盖住右侧职业图标")
        mocks["ui.widget.HeroFrame"] = { draw = function(_, opts) frames[#frames + 1] = opts end }
        local Draw = nativeRequire("ui.character.panel.CharacterPanelDraw2")
        local teams = { { slots = { { state = "occupied", heroId = 1 }, { state = "empty" },
            { state = "empty" }, { state = "empty" } } },
            { slots = {} }, { slots = {} } }
        local roster = { { heroId = 1, owned = true, level = 1 }, { heroId = 2, owned = true, level = 20 },
            { heroId = 3, owned = false, shards = 5 } }
        Draw.initImages({})
        Draw.setContext({ getTeamSlots = function() return teams[1].slots end,
            getHeroRoster = function() return roster end, getSlotPowerCache = function() return { 777 } end,
            getRosterPowerCache = function() return { 12345, 9999, 0 } end,
            getDragState = function() return { active = false } end, getSelectSlotState = function() return {} end,
            getHeroDeployTeams = function() return {} end, getUpgradeBadgeCache = function() return {} end,
            getActiveTeamIdx = function() return 1 end, getUnlockedTeamCount = function() return 1 end,
            getTeamOccupiedCounts = function() return {} end, getTeams = function() return teams end,
            getTeamPowerCaches = function() return { { 777 }, {}, {} } end })
        records, frames = {}, {}
        Draw.draw({}, 0, false)
        local texts = {}
        for _, r in ipairs(records) do if r.kind == "text" then texts[r.text] = r end end
        check(texts["12.3k"] and texts["9999"] and texts["777"], "已有名册与队伍头像都显示缓存战力")
        local unowned
        for _, f in ipairs(frames) do if f.heroId == 3 then unowned = f end end
        check(unowned and unowned.showShards and unowned.showClass, "未拥有保留碎片与职业，不伪造零战力")
        local left, right
        for _, f in ipairs(frames) do
            if f.nameLabel then left = math.min(left or f.cx, f.cx); right = math.max(right or f.cx, f.cx) end
        end
        check((left + right) * 0.5 == 540 and Draw.CONTENT_SHIFT_X == 0, "名册左右居中，释放旧左侧空白")
        check(texts["12.3k"].y > Draw.ROW1_CY + Draw.ROSTER_ICON * 0.5 + 30,
            "名册战力独立在名字下方，不盖头像角标")
        local occupied
        for _, f in ipairs(frames) do if f.posLabel == "前锋" then occupied = f end end
        local team, slot = Draw.hitTestAvatarSlot(occupied.cx + Draw.CONTENT_SHIFT_X,
            occupied.cy + Draw.CONTENT_SHIFT_Y, false)
        check(team == 1 and slot == 1, "三队新布局头像中心与点击命中一致")
        check(targets.character_slot_1 and targets.character_slot_1.cy == Draw.ROW1_CY + Draw.CONTENT_SHIFT_Y,
            "教程名册热点同步新首行坐标")
        check(math.abs(Draw.SCROLL_BOTTOM + Draw.CONTENT_SHIFT_Y - 2400) < 0.001,
            "滚动底边扣除内容下移，末行战力可见")
        check(Draw.ROW_SPACING > Draw.ROSTER_BOTTOM_DY + Draw.ROSTER_ICON * 0.5,
            "相邻行战力与下行头像留有间隔")
        -- 当前25位角色应在零滚动时完整展示，包含末行名字、战力和底框。
        roster = {}
        for heroId = 1, 25 do
            roster[#roster + 1] = { heroId = heroId, owned = true, level = 35 }
        end
        records, frames = {}, {}
        Draw.draw({}, 0, false)
        local rosterFrames, teamFrames, teamBottom, rosterFrameBottom = {}, {}, 0, 0
        for _, f in ipairs(frames) do
            if f.nameLabel then rosterFrames[#rosterFrames + 1] = f
            else teamFrames[#teamFrames + 1] = f end
        end
        check(#rosterFrames == 25, "零滚动绘制全部25位角色，未跳过末行")
        for _, f in ipairs(rosterFrames) do
            check(f.cy - f.size * 0.5 >= Draw.SCROLL_TOP
                and f.cy + Draw.ROSTER_BOTTOM_DY <= Draw.SCROLL_BOTTOM,
                "头像、名字、战力完整位于首屏裁剪内: " .. f.heroId)
        end
        for _, r in ipairs(records) do
            if r.kind == "rect" and r.w > 790 and r.w < 800 then teamBottom = math.max(teamBottom, r.y + r.h) end
            if r.kind == "rect" and r.w > 850 and r.w < 880 then rosterFrameBottom = r.y + r.h end
        end
        local firstTop = Draw.ROW1_CY - Draw.ROSTER_ICON * 0.5
        check(firstTop - teamBottom >= 48 and firstTop - teamBottom <= 80,
            "队三与名册仍留间隙但不再浪费大块空白")
        check(rosterFrameBottom > 0 and rosterFrameBottom <= Draw.SCROLL_BOTTOM,
            "五行名册底框同样完整，不只保证头像可见")
        local fullBottom = Draw.ROW1_CY + 4 * Draw.ROW_SPACING + Draw.ROSTER_BOTTOM_DY
        check(math.max(0, fullBottom - Draw.SCROLL_BOTTOM) == 0, "25人完整内容无需滚动")
        check(Draw.ROSTER_ICON == 148 and rosterFrames[1].size == 148 and teamFrames[1].size == 176,
            "名册与编队头像尺寸没有缩小")
        check(targets.character_slot_1.cy == Draw.ROW1_CY + Draw.CONTENT_SHIFT_Y,
            "上移后教程热点仍与首行同位")
        -- 读取正式名册命中函数，隔离状态但不手抄一份输入公式。
        local file = assert(cache:GetFile("ui/character/panel/CharacterPanel.lua"))
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local source = table.concat(lines, "\n")
        local hitSource = assert(source:match("(local function hitTestRosterCard.-)\n%-%- ======================== Public API"))
        local env = setmetatable({ Draw = Draw, DESIGN_W = 1080, DESIGN_H = 2400,
            ROW1_CY = Draw.ROW1_CY, ROW_SPACING = Draw.ROW_SPACING, MAX_PER_ROW = Draw.MAX_PER_ROW,
            SCROLL_TOP = Draw.SCROLL_TOP, SCROLL_BOTTOM = Draw.SCROLL_BOTTOM, heroRoster = roster, scrollY = 0 },
            { __index = _G })
        local hit = assert(load(hitSource .. "\nreturn hitTestRosterCard", "@正式名册命中", "t", env))()
        for _, index in ipairs({ 1, 5, 21, 25 }) do
            local f = rosterFrames[index]
            check(hit(f.cx + Draw.CONTENT_SHIFT_X, f.cy + Draw.CONTENT_SHIFT_Y) == index,
                "首末行头像命中跟随正式绘制: " .. index)
            check(hit(f.cx, f.cy + Draw.ROSTER_BOTTOM_DY + Draw.CONTENT_SHIFT_Y - 1) == index,
                "首末行战力区域仍点击同一角色: " .. index)
        end
        check(hit(540, Draw.SCROLL_TOP + Draw.CONTENT_SHIFT_Y - 1) == nil,
            "裁剪上方空隙不会误选名册")
        print("[character_roster_layout_test] ALL PASS: " .. checkCount .. " assertions")
    end)
    require = nativeRequire
    for name, fn in pairs(originals) do _G[name] = fn end
    if not ok then print("[character_roster_layout_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
