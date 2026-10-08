-- 塔三栏布局/正式宿主输入专项；基于既有Start+cache资源加载+隔离env范式。
-- 执行完整生产Layout/Sidebar/Scene/Tri/Input；UI树为显式CPU替身，不冒称真实Yoga/GPU。
-- 不加载main、不读玩家存档、不发Action、不调用随机数；规则专项另外独立保留。
function Start()
    assert(fileSystem:GetCurrentDir():gsub("/+$", "") == "/home/Maker/game4-validation/stage-regression",
        "isolated stage regression cwd required")
    local TAG = "[tower_layout_integration_test] "
    local checks, cases, failures = 0, 0, 0
    local sources = {}
    local function check(value, message)
        checks = checks + 1
        assert(value, message)
    end
    local function eq(actual, expected, message)
        check(actual == expected, message .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
    local function near(actual, expected, message)
        check(math.abs(actual - expected) < 0.000001, message .. " actual=" .. tostring(actual) .. " expected=" .. expected)
    end
    local function noop() end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = copy(item) end
        return result
    end
    local function read(path)
        if sources[path] then return sources[path] end
        local file = assert(cache:GetFile(path), "missing production resource " .. path)
        local ok, text = pcall(function()
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            return table.concat(lines, "\n")
        end)
        file:Dispose()
        assert(ok, text)
        sources[path] = text
        return text
    end
    local function compile(path, env)
        local chunk, err = load(read(path), "@resource:" .. path, "t", env)
        assert(chunk, err)
        return chunk()
    end
    local function runCase(name, fn)
        cases = cases + 1
        local ok, err = xpcall(fn, debug.traceback)
        if ok then print(TAG .. "PASS " .. name)
        else failures = failures + 1; print(TAG .. "FAIL " .. name .. " " .. tostring(err)) end
    end
    local function private()
        local mods, env, stat = {}, {}, { actions = 0, depth = 0, clips = {}, frames = {}, views = {}, destroyed = 0 }
        setmetatable(env, { __index = _G })
        env._G = env
        -- 生产闭包不得继承宿主File/FS/cloud；源码只经外层cache:GetFile只读出口。
        local function denied() error("native IO/network forbidden in tower fixture") end
        env.File, env.GetFileSystem, env.GetEngine, env.GetCache = denied, denied, denied, denied
        env.loadfile, env.dofile, env.SendEvent, env.SubscribeToEvent = denied, denied, denied, denied
        for _, key in ipairs({ "fileSystem", "cache", "engine", "network", "clientCloud", "serverCloud", "io", "os", "package" }) do
            env[key] = setmetatable({}, { __index = denied, __newindex = denied })
        end
        env.time = { elapsedTime = 100 }
        env.math = copy(math)
        env.math.random = function() error("random forbidden") end
        env.math.randomseed = env.math.random
        env.print = noop
        env.require = function(name) return assert(mods[name], "unprepared dependency " .. name) end
        env.nvgSave = function() stat.depth = stat.depth + 1 end
        env.nvgRestore = function() stat.depth = stat.depth - 1; check(stat.depth >= 0, "NVG no parent pop") end
        env.nvgScissor = function(_, x, y, w, h) stat.clips[#stat.clips + 1] = { x = x, y = y, w = w, h = h } end
        env.nvgIntersectScissor = env.nvgScissor
        for _, name in ipairs({ "nvgTranslate", "nvgScale", "nvgBeginPath", "nvgRect", "nvgRoundedRect",
            "nvgFillColor", "nvgFill", "nvgStrokeColor", "nvgStroke", "nvgStrokeWidth", "nvgFontFace",
            "nvgFontSize", "nvgTextAlign", "nvgText", "nvgMoveTo", "nvgLineTo" }) do env[name] = noop end
        env.nvgRGBA = function(...) return { ... } end
        -- detached UI的公开layout/content API；CPU替身不据此证明真实Yoga滚动范围。
        env.YGNodeCalculateLayout = noop
        mods["runtime.GameAction"] = { sendAction = function() stat.actions = stat.actions + 1; error("business action forbidden") end }
        mods["config.MonsterConfig"] = { MONSTERS = {} }
        mods["config.TowerConfig"] = compile("config/TowerConfig.lua", env)
        mods["ui.tower.TowerLayout"] = compile("ui/tower/TowerLayout.lua", env)
        return env, mods, stat
    end
    local function state(fn)
        for i = 1, 100 do
            local name, value = debug.getupvalue(fn, i)
            if name == "state" then return value end
            if not name then break end
        end
        error("missing production state")
    end
    -- CPU UI替身仅验证树归属/Destroy与路由，不以其自算布局证明真实Yoga测字。
    local function fakeUI(stat)
        local Widget = {}
        Widget.__index = Widget
        function Widget:Init(props)
            self.props, self.children, self.layout = props or {}, {}, { x = 0, y = 0, w = 438, h = 600 }
            self.text = self.props.text
            for _, child in ipairs(self.props.children or {}) do self:AddChild(child) end
        end
        function Widget:AddChild(child) self.children[#self.children + 1] = child; child.parent = self end
        function Widget:GetChildren() return self.children end
        function Widget:SetText(text) self.text = text end
        function Widget:SetHeight(height) self.props.height = height end
        function Widget:SetFontColor(color) self.color = color end
        function Widget:SetDisabled(value) self.disabled = value end
        function Widget:SetVisible(value) self.props.visible = value end
        function Widget:SetStyle(props) for key, value in pairs(props) do self.props[key] = value end end
        function Widget:GetAbsoluteLayout() return self.layout end
        function Widget:GetLayout() return self.layout end
        function Widget:GetScroll() return 0, self.scroll or 0 end
        function Widget:UpdateContentSize() end
        function Widget:SetScroll(_, y) self.scroll = math.max(0, y) end
        function Widget:ScrollBy(_, y) self:SetScroll(0, (self.scroll or 0) + y) end
        function Widget:Destroy()
            check(not self.destroyed, "widget destroyed once")
            for i = #self.children, 1, -1 do self.children[i]:Destroy() end
            if self.parent then
                for i, item in ipairs(self.parent.children) do
                    if item == self then table.remove(self.parent.children, i); break end
                end
            end
            self.destroyed = true; stat.destroyed = stat.destroyed + 1
        end
        function Widget:Extend()
            local class = setmetatable({}, { __index = self })
            class.__index = class
            setmetatable(class, { __index = self, __call = function(c, props)
                local result = setmetatable({}, c); result:Init(props); return result
            end })
            return class
        end
        local factory = function(props) local value = setmetatable({}, Widget); value:Init(props); return value end
        return { Widget = Widget, Label = factory, Panel = factory, Button = factory, ScrollView = factory }
    end
    runCase("tower result twelve heroes landscape and legacy close compatibility", function()
        local env, mods, stat = private()
        mods["urhox-libs/UI"] = fakeUI(stat)
        -- 确定性测宽替身只检查生产字号拟合与格子几何，不冒称真实字体/像素验收。
        local function measure(caption, size) return utf8.len(caption) * size * .62 end
        mods["urhox-libs/UI"].MeasureTextWidth = measure
        mods["urhox-libs/UI"].Theme = { FontSize = function(s) return s end }
        mods["core.NumberUtil"] = { format = tostring }
        mods["core.DrawUtil"], mods["ui.widget.ImageCache"] = {}, {}
        mods["core.DarkIcon"] = { drawQualityBg = function(_, quality)
            stat.rewardQualities[#stat.rewardQualities + 1] = quality
        end }
        mods["ui.widget.HeroFrame"] = { draw = function() stat.heroDraws = (stat.heroDraws or 0) + 1 end }
        mods["config.ResourceDefs"] = { DEFS = {
            diamond = { name = "黑晶", quality = 5, iconPath = "image/货币道具/UI_icon_SJ_X.png" },
        } }
        mods["config.HeroConfig"] = { HEROES = {} }
        mods["core.I18n"] = { get = function() return stat.language or "zh_CN" end, lookup = function(s) return s end }
        stat.imagePaths, stat.imagePaints, stat.rewardQualities = {}, {}, {}
        mods["ui.widget.DesignWidgetSurface"] = { init = noop, draw = function(root)
            stat.resultRoot = root; stat.resultDraws = (stat.resultDraws or 0) + 1
            -- 调用真实ResultIcon:Render，显式CPU布局；证明图标调用路径，不证明Yoga/GPU。
            for _, cell in ipairs(root.children[7].children) do
                if cell.children[1] and cell.children[1].reward then
                    local icon = cell.children[1]
                    icon.layout = { x = icon.props.left, y = icon.props.top,
                        w = icon.props.width, h = icon.props.height }
                    icon:Render({})
                end
            end
        end }
        env.nvgCreateImage = function(_, path)
            if path:find("角色图标", 1, true) then return -1 end
            stat.imagePaths[#stat.imagePaths + 1] = path
            return #stat.imagePaths
        end
        env.nvgImagePattern = function(_, _, _, _, _, _, image)
            stat.imagePaints[#stat.imagePaints + 1] = stat.imagePaths[image]
            return {}
        end
        env.nvgFillPaint = noop
        local result = compile("ui/battle/popup/BattleResultPanel.lua", env)
        local heroes, closed = {}, 0
        for i = 1, 12 do heroes[i] = { heroId = i, name = "英雄" .. i, quality = 1, totalDamage = i * 100 } end
        local rewards = {
            { type = "diamond", amount = 123 },
            { type = "artifact", name = "星辉护符", quality = 2,
                iconPath = "image/神器/UI_artifact_2.png", amount = 1 },
            { type = "player_exp", name = "远征经验", amount = 45678 },
            { type = "hero_exp", name = "队员经验", amount = 23456 },
        }
        local function rewardGeometry(root, items)
            local panel = root.children[7]
            eq(#panel.children, #items, "every reward retained including EXP")
            check(panel.props.left + panel.props.width <= root.props.width
                and panel.props.top + panel.props.height <= root.props.height, "reward panel inside canvas")
            for i, cell in ipairs(panel.children) do
                local item = items[i]
                check(cell.props.left >= 0 and cell.props.top >= 0
                    and cell.props.left + cell.props.width <= panel.props.width
                    and cell.props.top + cell.props.height <= panel.props.height, "reward cell inside panel " .. i)
                eq(cell.children[1].reward, item, "original complete reward instance rendered " .. i)
                eq(cell.children[2].text, item.name or "黑晶", "actual reward name " .. i)
                eq(cell.children[3].text, "×" .. tostring(item.amount), "actual reward amount " .. i)
                for _, child in ipairs(cell.children) do
                    check(child.props.left >= 0 and child.props.top >= 0
                        and child.props.left + child.props.width <= cell.props.width
                        and child.props.top + child.props.height <= cell.props.height, "reward child geometrically fits " .. i)
                    if child.text then
                        check(measure(child.text, child.props.fontSize) <= child.props.width - 4 + .000001,
                            "production fitted label width " .. i)
                        check(child.props.fontSize * child.props.lineHeight <= child.props.height,
                            "production fitted label line height " .. i)
                    end
                end
            end
        end
        result.init({})
        result.show({ layout = "tower", floor = 112, wave = 1, isWin = true, elapsedSecs = 125,
            heroStats = heroes, rewards = rewards,
            onClose = function() closed = closed + 1 end })
        for _, size in ipairs({ {1920,1080}, {1280,800} }) do
            result.draw({}, size[1], size[2])
            local root = stat.resultRoot
            eq(root.props.width, 1440, "actual horizontal content width")
            eq(root.props.height, 760, "actual horizontal content height")
            eq(root.children[1].text, "通天塔 · 通关", "clear title")
            eq(root.children[2].text, "第112层", "actual result floor only despite wave1 input")
            eq(root.children[3].text, "总耗时 2分05秒", "elapsed visible")
            eq(#root.children[6].children, 12, "all twelve heroes retained")
            for _, cell in ipairs(root.children[6].children) do
                check(cell.props.left + cell.props.width <= 900 and cell.props.top + cell.props.height <= 432, "hero inside statistics panel")
                eq(cell.children[2].props.fontWeight, "normal", "host registered font only")
            end
            eq(root.children[7].children[1].children[3].text, "×123", "reward amount visible")
            rewardGeometry(root, rewards)
            eq(stat.imagePaints[#stat.imagePaints - 1], "image/货币道具/UI_icon_SJ_X.png", "actual diamond Render image path")
            eq(stat.imagePaints[#stat.imagePaints], rewards[2].iconPath, "artifact iconPath used by actual Render")
            eq(stat.rewardQualities[#stat.rewardQualities - 2], 2, "artifact quality override rendered")
            eq(stat.depth, 0, "landscape draw restores NVG state")
        end
        local oldRoot = stat.resultRoot
        result.handleInput(0, 0); result.close()
        check(oldRoot.destroyed and not result.isOpen(), "close destroys owned tree")
        eq(closed, 1, "close callback exactly once")
        -- 真奖励可能含多件神器及两类经验；覆盖>4时生产两列路径，不丢掉后排。
        local expandedRewards = copy(rewards)
        for i = 1, 4 do
            expandedRewards[#expandedRewards + 1] = { type = "artifact", quality = (i % 3) + 1,
                name = "长名称神器" .. i .. "·保留完整实例名称与数量",
                iconPath = "image/神器/oracle_" .. i .. ".png", amount = 1 }
        end
        result.show({ layout = "tower", floor = 112, wave = 1, isWin = true,
            heroStats = heroes, rewards = expandedRewards })
        local expectedFloors = { zh_CN = "第112层", zh_TW = "第112層", en = "Floor 112", ja = "112階", ko = "112층" }
        for _, language in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            stat.language = language
            for _, size in ipairs({ {1920,1080}, {1280,800} }) do
                result.draw({}, size[1], size[2])
                local root = stat.resultRoot
                eq(root.children[2].text, expectedFloors[language], "localized floor no wave fraction " .. language)
                rewardGeometry(root, expandedRewards)
                check(root.children[7].children[2].props.left > root.children[7].children[1].props.left,
                    "actual multiple rewards two-column layout")
                eq(stat.imagePaints[#stat.imagePaints], expandedRewards[#expandedRewards].iconPath,
                    "last reward icon is actually rendered")
                eq(stat.depth, 0, "multi-reward result restores NVG state")
            end
        end
        result.close(); stat.language = "zh_CN"
        result.show({ layout = "tower", isWin = false, heroStats = heroes })
        result.draw({}, 1280, 800)
        eq(stat.resultRoot.children[1].text, "通天塔 · 失败", "defeat title")
        eq(stat.resultRoot.children[7].children[1].text, "暂无奖励", "empty rewards clear")
        result.close()
        local drawCount = stat.resultDraws
        result.show({ heroStats = heroes })
        result.draw({})
        eq(stat.resultDraws, drawCount, "ordinary result uses unchanged legacy draw")
        eq(stat.heroDraws, 6, "ordinary six-hero legacy unchanged")
        result.close()
        result.show({ layout = "tower", onClose = function() closed = closed + 1 end })
        result.resetToDefault(); result.close()
        check(not result.isOpen() and closed == 1, "reset discards old callback without completion")
    end)
    local function sidebarFixture()
        local env, mods, stat = private()
        stat.roots = {}
        mods["urhox-libs/UI"] = fakeUI(stat)
        mods["core.I18n"] = { get = function() return stat.language or "zh-Hans" end }
        mods["core.I18nTower"] = compile("core/I18nTower.lua", env)
        mods["ui.tower.TowerPresentation"] = compile("ui/tower/TowerPresentation.lua", env)
        mods["ui.tower.TowerOathEffect"] = { drawIcon = noop }
        mods["ui.widget.DesignWidgetSurface"] = { init = noop, draw = function(root)
            stat.roots[#stat.roots + 1] = root
            if stat.failDraw then error("subtree failure") end
            root.layout = { x = 0, y = 0, w = root.props.width, h = root.props.height }
            for i, child in ipairs(root.children) do
                child.layout = { x = 24, y = i == #root.children and root.props.height - 88 or 180,
                    w = 438, h = i == #root.children and 64 or 600 }
                if root.props.borderLeftWidth then
                    local ys = {20, 62, 116, 116, 840, 920, 992}
                    local hs = {32, 44, 700, 700, 64, 64, 64}
                    child.layout = {x = 19.2, y = ys[i], w = 447.6, h = hs[i]}
                end
            end
        end }
        local sidebar = compile("ui/tower/TowerBuffSidebar.lua", env)
        return sidebar, mods["ui.tower.TowerLayout"], stat
    end
    runCase("checkpoint selector real draw rewards and read-only entry mapping", function()
        local env,mods,stat=private()
        local baseRequire=env.require
        env.require=function(name)
            if mods[name] then return mods[name] end
            assert(name:match("^config%.") or name=="shared.StageUtils" or name=="systems.AttributeDef",
                "unprepared selector dependency "..name)
            local module=compile(name:gsub("%.","/")..".lua",env)
            mods[name]=module
            return module
        end
        local progress={maxStageId=701}
        local dungeon={babel_tower={floor=1,cleared={}}}
        mods["runtime.ClientDispatcher"]={get=function(name)
            return name=="battle" and progress or (name=="dungeon" and dungeon or nil)
        end}
        mods["core.GameState"]={getPower=function()return 100 end}
        mods["core.I18n"]={get=function()return stat.language or "zh_CN" end,lookup=function(s)return s end,
            format=function(s,...)return string.format(s,...)end}
        mods["core.I18nTower"]=compile("core/I18nTower.lua",env)
        mods["ui.tower.TowerPresentation"]=compile("ui/tower/TowerPresentation.lua",env)
        mods["core.NumberUtil"]={format=tostring}
        local drawn, textCalls, shapes = {}, {}, {}
        mods["core.DrawUtil"]={drawTextStroke=function(_,x,y,s,size)
                drawn[#drawn+1]=s
                textCalls[#textCalls+1]={x=x,y=y,text=s,size=size}
            end,
            drawImageCentered=noop,drawNineSlice=noop,drawImageCover=noop}
        env.nvgRoundedRect=function(_,x,y,w,h)
            shapes[#shapes+1]={x=x,y=y,w=w,h=h}
        end
        mods["core.DarkIcon"]={drawQualityBg=noop,draw=noop}
        mods["systems.ButtonFeedback"]={trigger=noop}
        mods["ui.battle.stage.BattleEnemySpawn"]={getFirstClearBonusMonsterIds=function()return {} end}
        mods["ui.battle.stage.ExpeditionOverview"]={}
        mods["ui.battle.scene.BattleScene"]={getMaxStageId=function()return progress.maxStageId end,
            getStageId=function()return 101 end,getClearedStages=function()return {} end}
        mods["ui.battle.tri.BattleTriPage"]={getTeamStageId=function()return 101 end,
            isTerminalRaidActive=function()return false end}
        mods["ui.hud.BottomNav"]={isAllLocked=function()return false end,isTabLocked=function()return false end}
        mods["ui.dungeon.DungeonBattleScene"]={isOpen=function()return false end}
        mods["ui.tower.TowerBattleScene"]={isActive=function()return false end}
        env.nvgCreateImage=function()return -1 end;env.nvgImageSize=function()return 0,0 end
        env.nvgDeleteImage=noop;env.nvgResetTransform=noop
        env.nvgTextBounds=function(_,_,_,s)return utf8.len(s)*12 end
        local resources=compile("ui/battle/stage/StageSelectResources.lua",env)
        mods["ui.battle.stage.StageSelectResources"]=resources
        local reward=compile("ui/battle/stage/StageSelectRewardPreview.lua",env)
        mods["ui.battle.stage.StageSelectRewardPreview"]=reward
        local selector=compile("ui/battle/stage/StageSelectDialog.lua",env)
        local towerGroup=resources.getGroups()[4]
        eq(#towerGroup.ids,23,"selector only lists 23 checkpoints")
        for i,id in ipairs(towerGroup.ids) do
            eq(id,400001+(i-1)*5,"checkpoint IDs stay real floors")
            eq(resources.getStageEntry(id).name,"通天塔 第"..(id-400000).."层","entry name no chapter label")
        end
        eq(resources.getDisplayStageId(400112),400111,"last floor reveals its checkpoint")
        eq(resources.getCurrentTowerStageId(dungeon),400001,"fresh tower checkpoint1")
        check(not resources.isStageUnlocked(400006,progress,dungeon),"uncleared group cannot select6")
        check(not resources.isStageUnlocked(400002,progress,dungeon),"noncheckpoint2 is never selectable")
        dungeon.babel_tower.floor=6
        eq(resources.getCurrentTowerStageId(dungeon),400006,"old floor-only save unlocks6")
        check(resources.isStageUnlocked(400006,progress,dungeon),"old cleared5 can enter6")
        eq(resources.getRewardPreview(400001,nil,dungeon).firstAmount,0,"cleared first group no diamond preview")
        dungeon.babel_tower={floor=1,cleared={["5"]=true}}
        eq(resources.getRewardPreview(400001,nil,dungeon).firstAmount,1200,"sparse5 only deducts floor5")
        dungeon.babel_tower={floor=1,cleared={}}
        local last=resources.getRewardPreview(400111,nil,dungeon)
        eq(last.runEndFloor,112,"last group ends112")
        eq(last.firstAmount,11550,"last two floors first-clear amount")
        eq(last.repeatAmount,0,"repeat and sweep diamond0")
        eq(last.artifactDropRate,.05,"artifact chance per floor5 percent")
        eq(table.concat(last.artifactQualityWeights,","),"80,18,2","conditional quality weights")
        local vg={}
        selector.init(vg);selector.openDungeon(1,"babel_tower");env.time.elapsedTime=101
        drawn={};selector.draw(vg)
        local seen={};for _,s in ipairs(drawn)do seen[s]=true end
        check(seen["第1层"] and seen["第6层"],"real selector draws floor labels")
        check(seen["第1-5层 · 每层1波"],"real selector draws group1..5")
        check(seen["首通奖励 ×1650"],"remaining group first-clear summary visible")
        check(not seen["本组剩余首通黑钻 ×1650 · 重打/扫荡0"],"selector hides repeat/sweep explanation")
        check(not seen["每层胜利神器5% · 品质1/2/3 80/18/2%"],"selector hides detailed drop probabilities")
        for _,s in ipairs(drawn)do
            check(not s:find("每层10波",1,true),"no ten-wave preview")
            check(not s:find("组远征经验",1,true),"selector hides experience formulas")
        end
        local requested=0
        selector.setOnDungeonSelect(function(_,_,floor)requested=floor;return false end)
        selector.handleInput(600,980);eq(requested,0,"locked real row6 rejects entry")
        dungeon.babel_tower.floor=6
        selector.handleInput(600,980);eq(requested,6,"unlocked row6 calls checkpoint6")
        -- 需求给定808/CH876/塔摘要44的独立锚点；不从生产常量反推oracle。
        for _, language in ipairs({"zh_CN","zh_TW","en","ja","ko"}) do
            stat.language=language
            drawn,textCalls,shapes={},{},{}
            selector.draw(vg)
            local summary=string.format(mods["core.I18nTower"].lookup("首通奖励 ×%s",language),"0")
            local expected={
                zh_CN="首通奖励 ×0",zh_TW="首通獎勵 ×0",en="First-clear reward ×0",
                ja="初回報酬 ×0",ko="첫 클리어 보상 ×0",
            }
            eq(summary,expected[language],"new complete reward translation "..language)
            local hasSummary,hasMain,hasDungeon,hasBand,hasChapter=false,false,false,false,false
            for _, call in ipairs(textCalls) do
                if call.text==summary and call.x==367 and call.y==916 then hasSummary=true end
                if call.text=="主线" and call.x==150 and call.y==808 then hasMain=true end
                if call.text=="副本" and call.x==250 and call.y==808 then hasDungeon=true end
                check(not call.text:find("%",1,true) and not call.text:find("EXP",1,true)
                    and not call.text:find("经验",1,true) and not call.text:find("重打",1,true),
                    "tower selector omits probability/EXP/repeat formula "..language)
            end
            for _, shape in ipairs(shapes) do
                if shape.x==323 and shape.y==894 and shape.w==564 and shape.h==44 then hasBand=true end
                if shape.x==105 and shape.y==876 and shape.w==190 and shape.h==84 then hasChapter=true end
            end
            check(hasSummary,"real tower summary text centered in 44 band "..language)
            check(hasMain and hasDungeon,"real tab text stays at808 "..language)
            check(hasBand and hasChapter,"44 tower band and CH_Y0=876 preserved "..language)
        end
        stat.language="zh_CN"
        eq(stat.actions,0,"preview does not dispatch rewards")
        selector.close();env.require=baseRequire
        eq(stat.depth,0,"selector drawing restores all state")
    end)
    runCase("layout symmetry cap inverses and real mainline interiors", function()
        local env, mods = private()
        local layout = mods["ui.tower.TowerLayout"]
        local text = read("ui/battle/tri/BattleTriPage.lua")
        local a = assert(text:find("local INTERIORS =", 1, true))
        local b = assert(text:find("--- 战斗卡点击", a, true))
        local helper = assert(load("local PLATE_AR=1672/941\n" .. text:sub(a, b - 1) .. "\nreturn interiorRect", "@real-interiors", "t", env))()
        for _, size in ipairs({ {1920,1080}, {1280,800}, {960,540}, {800,1000}, {640,360}, {3840,1080} }) do
            local w, h = size[1], size[2]
            local l = layout.compute(w, h)
            near(l.left.w, l.right.w, "side widths symmetric")
            near(l.left.w + l.center.w + l.right.w, w, "columns complete")
            near(l.right.x + l.right.w, w, "right aligned")
            check(l.sideScale > 0 and l.center.w > 0 and l.left.w <= w * .28, "small-window cap")
            eq(layout.panelAt(l, l.center.x, 10), "center", "left boundary not dual hit")
            eq(layout.panelAt(l, w, 10), nil, "outside right edge")
            for _, side in ipairs({"left", "right"}) do
                local x = l[side].x + 123 * l.sideScale
                local y = 234 * l.sideScale
                local dx, dy = layout.toSide(l, side, x, y)
                near(dx, 123, "side inverse x"); near(dy, 234, "side inverse y")
            end
            local tx, ty = layout.toTask(l, 540 * l.sideScale * .45, 1200 * l.sideScale * .45)
            near(tx, 540, "TaskPage inverse x"); near(ty, 1200, "TaskPage inverse y")
            for row = 1, 3 do
                local ix, iy, iw, ih = helper(row, 1920, 1080)
                local x, y, rw, rh = layout.mapInterior(l, ix, iy, iw, ih)
                check(x >= l.center.x and x + rw <= l.center.x + l.center.w, "real interior middle only " .. row)
                check(y >= 0 and y + rh <= h and rw > 0 and rh > 0, "real interior vertical " .. row)
            end
            local dialog = layout.confirm(l)
            check(dialog.cancel.x > dialog.retreat.x and dialog.frame.x >= 0, "right cancel retained")
            check(dialog.frame.x + dialog.frame.w <= w and dialog.frame.y + dialog.frame.h <= h, "confirmation fits")
        end
    end)
    runCase("Sidebar aggregate immutable descriptions tree teardown and scrolling", function()
        local sidebar, layout, stat = sidebarFixture()
        local ids = {1, 1, "2", 9999, 3}
        local before = table.concat(ids, ",")
        local rows = sidebar.aggregate(ids)
        eq(#rows, 3, "unknown omitted")
        eq(rows[1].count, 2, "same id counted")
        eq(rows[2].id, 2, "numeric string id compatibility")
        eq(table.concat(ids, ","), before, "input untouched")
        local snapshot = {floor=112,wave=10,phase="battle",buffIds=ids,inputModal=false}
        sidebar.draw({}, 1920, 1080, snapshot)
        local left, right = stat.roots[1], stat.roots[2]
        eq(#left.children[4].children[1].children, 112, "112 read-only nodes")
        eq(left.children[2].text, "第112层", "实际层号不再章-关")
        eq(left.children[3].text, "每层1波 · 每5层一组", "单波五层组规则可见")
        local routeNodes = left.children[4].children[1].children
        local starts = 0
        for floor, node in ipairs(routeNodes) do
            eq(node.children[1].text, tostring(floor), "路线仍保留真实112层号")
            if (floor - 1) % 5 == 0 then
                starts = starts + 1
                eq(node.children[2].text, "起点", "每五层标记起点")
            else eq(#node.children, 1, "普通层不假装可启动") end
        end
        eq(starts, 23, "最后起点111不裁剪112终点")
        eq(#routeNodes[112].children, 1, "112仅终点不是启动点")
        local content = right.children[3].children[1]
        eq(#content.children, 3, "one row per id")
        local first = content.children[1]
        eq(first.children[2].text, rows[1].desc, "duplicate description not multiplied")
        local destroyed = stat.destroyed
        sidebar.draw({}, 1920, 1080, snapshot)
        eq(stat.destroyed, destroyed, "same snapshot no rebuild")
        stat.language = "en"
        sidebar.draw({}, 1920, 1080, snapshot)
        check(first.destroyed and stat.destroyed > destroyed, "locale rebuild destroys old rows")
        local l = layout.compute(1920, 1080)
        local x, y = l.right.x + 100, 300
        sidebar.handleScroll(-1, x, y, 1920, 1080)
        eq(right.children[3].scroll, 110, "right wheel")
        sidebar.dragBegin(x, y, 1920, 1080)
        sidebar.dragMove(x, y-50, 1920, 1080)
        eq(right.children[3].scroll, 160, "right drag")
        sidebar.dragMove(x, y-100, 1280, 800)
        eq(right.children[3].scroll, 160, "resize cancels drag")
        eq(sidebar.handleClick(l.right.x+100, 1020, 1920,1080), "retreat", "right action hit")
        stat.failDraw = true
        local ok = pcall(sidebar.draw, {},1920,1080,snapshot)
        check(not ok, "subtree error preserved"); eq(stat.depth,0,"sidebar restores own state")
        stat.failDraw = false
        sidebar.destroy()
        check(left.destroyed and right.destroyed, "both roots destroyed")
        local after = stat.destroyed
        sidebar.destroy(); eq(stat.destroyed,after,"destroy idempotent")
        sidebar.drawConfirmation({},1280,800)
        local confirm = stat.roots[#stat.roots]
        eq(confirm.children[4].text,"Cancel","standalone confirmation uses current English locale")
        sidebar.destroy(); eq(stat.actions,0,"read-only UI no actions")
    end)
    runCase("真实右栏收起保持scroll、数量、动作与尺寸",function()
        local sidebar,layout,stat=sidebarFixture()
        local snapshot={floor=17,wave=3,phase="battle",buffIds={1,1,7,17},pendingChoices=3,inputModal=false}
        sidebar.draw({},1920,1080,snapshot)
        local left,right=stat.roots[1],stat.roots[2];local scroll=right.children[3]
        local card=scroll.children[1].children[1];local key=sidebar.getPresentationKey()
        near(left.props.padding,24,"左栏padding原值")
        near(right.children[1].props.fontSize,25.6,"右栏标题80%")
        near(card.children[1].children[1].props.width,51.2,"图标80%")
        near(card.children[1].children[2].children[1].props.fontSize,20.8,"名字80%")
        near(card.children[2].props.fontSize,18.4,"描述80%")
        eq(card.children[1].children[2].children[2].text,"普通  ×2","次数原样聚合")
        local l=layout.compute(1920,1080);local x=l.right.x+100
        sidebar.handleScroll(-1,x,300,1920,1080);sidebar.dragBegin(x,300,1920,1080)
        eq(sidebar.handleClick(x,80,1920,1080),"toggle_buffs","一键按钮动作")
        check(sidebar.toggleCollapsed(),"默认展开可以收起")
        sidebar.draw({},1920,1080,snapshot);sidebar.dragMove(x,250,1920,1080)
        eq(scroll.scroll,110,"切换停止旧drag且不清零scroll")
        eq(scroll.props.visible,false,"隐藏内容")
        eq(right.children[1].text,"已获强化  4","常驻总数量不丢失")
        eq(sidebar.handleClick(x,940,1920,1080),"resume_pick","常驻待选恢复")
        eq(sidebar.handleClick(x,1020,1920,1080),"retreat","常驻撤退入口")
        sidebar.handleScroll(-1,x,300,1920,1080);eq(scroll.scroll,110,"隐藏滚轮不影响内容")
        check(not sidebar.toggleCollapsed(),"展开")
        eq(scroll.scroll,110,"展开保留scroll")
        check(sidebar.getPresentationKey()~=key,"ABA也不重用旧版本")
        sidebar.toggleCollapsed();sidebar.reset()
        check(not sidebar.isCollapsed() and scroll.props.visible,"reset默认展开")
        eq(scroll.scroll,0,"reset清理旧scroll")
        sidebar.destroy()
    end)
    local function inputFixture()
        local env, mods, stat = private()
        local c = { w=1920,h=1080,dpr=1,key="session1:run1:floor1:wave1:battle:visiblefalse:pendingfalse",
            active=true, mouse={x=1700,y=1020}, rt={frameScale=1,frameOx=0,frameOy=0}, clicks={}, moves=0,
            begins=0, ends=0, wheel=0, taskClicks=0, taskWheel=0, taskBegins=0, taskMoves=0,
            overlays={}, ordinary=0, task=false }
        local function generic()
            return setmetatable({isOpen=function() return false end, isActive=function() return false end},
                {__index=function() return function() return false end end})
        end
        for name in read("boot/StandaloneHorizonInput.lua"):gmatch('require%("([^"]+)"%)') do
            if not mods[name] then mods[name] = generic() end
        end
        mods["ui.character.hero.AwakeningArtwork"] = { hasPress = function() return false end, observe = noop,
            isOpen = function() return false end, releaseTouch = function() return false end,
            hasTouch = function() return false end,
            bindInput = function()
                return function() return false end -- 本专项没有全图模态；完整指针闭包仍走正式Input。
            end }
        mods["ui.tower.TowerBattleScene"] = {
            isActive=function() return c.active end,
            getPresentationKey=function() return c.key .. ":" .. (c.sidebarKey and c.sidebarKey() or "") end,
            getLayout=mods["ui.tower.TowerLayout"].compute,
            handleClick=function(x,y,w,h) c.clicks[#c.clicks+1]={x,y,w,h} end,
            handleDragBegin=function() c.begins=c.begins+1 end,
            handleDragMove=function() c.moves=c.moves+1 end,
            handleDragEnd=function() c.ends=c.ends+1 end,
            handleScroll=function() c.wheel=c.wheel+1;return true end,
        }
        mods["ui.story.task.TaskPage"] = {isOpen=function() return c.task end,
            handleDragBegin=function() c.taskBegins=c.taskBegins+1 end,
            handleDragMove=function() c.taskMoves=c.taskMoves+1 end,handleDragEnd=noop,
            handleInput=function(x,y)c.taskClicks=c.taskClicks+1;c.taskX,c.taskY=x,y end,
            handleScroll=function()c.taskWheel=c.taskWheel+1 end}
        for _, path in ipairs({"ui.hud.popup.RewardPopup","ui.hud.popup.PlayerInfoPanel","ui.hud.popup.OfflineRewardPanel",
            "ui.hud.popup.LevelUpPopup","ui.hud.popup.UpdateNoticePopup","ui.story.gate.DarkTitleScreenGate",
            "ui.story.gate.LetterIntro","ui.story.gate.IntroCutscene","ui.story.ScenarioDialogue","ui.dev.CEPanel",
            "ui.battle.popup.TerminalConfirmDialog"}) do
            local mod = mods[path]
            mod.isOpen=function()return c.overlays[path]==true end
            mod.isActive=mod.isOpen
        end
        mods["ui.hud.BottomNav"].getSelectedIndex=function()return 3 end
        mods["ui.character.panel.CharacterPanel"].handleDragEnd=noop
        mods["ui.battle.tri.BattleTriPage"].handleScroll=function()c.ordinary=c.ordinary+1;return false end
        env.input={GetMousePosition=function()return c.mouse end}
        local ctx={vg=function()return {} end,logicalW=function()return c.w end,logicalH=function()return c.h end,
            windowW=function()return c.w end,windowH=function()return c.h end,dpr=function()return c.dpr end,
            toDesign=function(x,y)return (x-(c.rt.frameOx or 0))/(c.rt.frameScale or 1),(y-(c.rt.frameOy or 0))/(c.rt.frameScale or 1) end,
            RT=c.rt,bootReady_=function()return true end,equipOverlayDesign=function()return nil end,
            seamHitAt=function()return false end,seamInputBlocked=function()return true end,
            seamGesture=generic(),artifactGesture=generic(),Viewport={PANELS={},DS=.45,hit=function()return nil end},
            OfflineRewardOverlay=generic(),talentPageUsesWideLayout=function()return false end,
            syncTalentPageLayout=noop,talentPageRightEdge=function()return 0 end}
        local callbackNames={HandleMouseButtonDownHorizon=true,HandleMouseMoveHorizon=true,
            HandleEquipmentHoverTickHorizon=true,HandleMouseButtonUpHorizon=true,
            HandleTouchBeginHorizon=true,HandleTouchEndHorizon=true,HandleTouchMoveHorizon=true,
            HandleMouseWheelHorizon=true}
        setmetatable(env,{__index=function(_,key)
            local value=_G[key]
            assert(value~=nil,"unknown global read "..tostring(key))
            return value
        end,__newindex=function(t,key,value)
            assert(callbackNames[key],"unknown global assignment "..tostring(key))
            rawset(t,key,value)
        end})
        mods["boot.DecomposeMarqueeGesture"] = compile("boot/DecomposeMarqueeGesture.lua",env)
        mods["boot.StandaloneHorizonWheel"] = compile("boot/StandaloneHorizonWheel.lua",env)
        local inputMod=compile("boot/StandaloneHorizonInput.lua",env)
        inputMod.bind(ctx)
        check(type(ctx.observeTowerPress)=="function","observer exported only in context")
        check(rawget(env,"ObserveTowerPressHorizon")==nil,"no new global observer")
        c.env=env
        function c.down(button)env.HandleMouseButtonDownHorizon("MouseButtonDown",{Button={GetInt=function()return button or MOUSEB_LEFT end}})end
        function c.up(button)env.HandleMouseButtonUpHorizon("MouseButtonUp",{Button={GetInt=function()return button or MOUSEB_LEFT end}})end
        function c.move(x,y)c.mouse={x=x,y=y};env.HandleMouseMoveHorizon("MouseMove",{})end
        function c.observe()ctx.observeTowerPress()end
        function c.scroll()env.HandleMouseWheelHorizon("MouseWheel",{Wheel={GetInt=function()return -1 end}})end
        function c.touch(id,x,y,handler)
            local event={TouchID={GetInt=function()return id end},X={GetInt=function()return x end},Y={GetInt=function()return y end}}
            env[handler]("touch",event)
        end
        return c
    end
    runCase("full host fresh mouse touch and no-down gate",function()
        local c=inputFixture()
        c.up();eq(#c.clicks,0,"no Down no tower click")
        c.down();c.up();eq(#c.clicks,1,"fresh mouse click")
        c.env.time.elapsedTime=101
        c.touch(1,1700,1020,"HandleTouchBeginHorizon")
        c.touch(2,1700,1020,"HandleTouchBeginHorizon")
        c.touch(2,1700,1020,"HandleTouchEndHorizon")
        eq(#c.clicks,1,"second touch no ownership")
        c.touch(1,1700,1020,"HandleTouchEndHorizon")
        eq(#c.clicks,2,"primary touch click")
        c.env.time.elapsedTime=102
        c.down();c.up(MOUSEB_RIGHT);eq(#c.clicks,2,"secondary button preserves primary press")
        c.up();eq(#c.clicks,3,"primary release still valid")
    end)
    runCase("full host movement crossing and observed ABA identity matrix",function()
        local c=inputFixture()
        c.down();c.move(1700,990);c.move(1700,1020);c.up();eq(#c.clicks,0,"drag return not tap")
        c.down();c.move(960,1020);c.move(1700,1020);c.up();eq(#c.clicks,0,"panel crossing cancels permanently")
        local mutations={
            function()c.key=c.key..":floor2"end,function()c.key=c.key..":run2"end,
            function()c.key=c.key..":buff_pick"end,function()c.key=c.key..":visibletrue"end,
            function()c.key=c.key..":pendingtrue"end,function()c.key=c.key..":session2"end,
            function()c.w,c.h=1280,800 end,function()c.dpr=2 end,
            function()c.rt.frameScale=.8 end,function()c.rt.frameOx=10 end,function()c.rt.frameOy=10 end,
            function()c.active=false end,function()c.task=true end,
            function()c.overlays["ui.hud.popup.RewardPopup"]=true end,
            function()c.overlays["ui.hud.popup.UpdateNoticePopup"]=true end,
            function()c.overlays["ui.hud.popup.LevelUpPopup"]=true end,
            function()c.overlays["ui.dev.CEPanel"]=true end,
        }
        for index,mutate in ipairs(mutations)do
            c.key="session1:run1:floor1:wave1:battle:visiblefalse:pendingfalse"
            c.w,c.h,c.dpr,c.rt.frameScale,c.rt.frameOx,c.rt.frameOy,c.active,c.task=1920,1080,1,1,0,0,true,false
            c.overlays={}
            c.down();mutate();c.env.HandleEquipmentHoverTickHorizon()
            c.key="session1:run1:floor1:wave1:battle:visiblefalse:pendingfalse"
            c.w,c.h,c.dpr,c.rt.frameScale,c.rt.frameOx,c.rt.frameOy,c.active,c.task=1920,1080,1,1,0,0,true,false
            c.overlays={};c.up();eq(#c.clicks,0,"observed ABA cancels "..index)
        end
    end)
    runCase("正式宿主按压遇到真实Sidebar切换/ABA/reset失效",function()
        local c=inputFixture();local sidebar=sidebarFixture()
        c.sidebarKey=sidebar.getPresentationKey
        c.down();sidebar.toggleCollapsed();c.up()
        eq(#c.clicks,0,"切换后旧鼠标抬起不触发战斗或按钮")
        c.down();sidebar.toggleCollapsed();sidebar.toggleCollapsed();c.up()
        eq(#c.clicks,0,"无需中间observe也能识别真实toggleABA")
        c.env.time.elapsedTime=101
        c.touch(1,1700,1020,"HandleTouchBeginHorizon")
        sidebar.toggleCollapsed();c.observe();sidebar.toggleCollapsed()
        c.touch(1,1700,1020,"HandleTouchEndHorizon")
        eq(#c.clicks,0,"旧触摸抬起在展开后仍失效")
        c.env.time.elapsedTime=102;c.down();sidebar.reset();c.up()
        eq(#c.clicks,0,"reset使旧会话按压失效")
        c.down();c.up();eq(#c.clicks,1,"切换后新按压可以正常处理")
        sidebar.destroy()
    end)
    runCase("TaskPage exact narrow inverse wheel drag and no ordinary penetration",function()
        local c=inputFixture();c.w,c.h,c.task=1280,800,true
        local l=compile("ui/tower/TowerLayout.lua",c.env).compute(c.w,c.h)
        c.mouse={x=540*l.sideScale*.45,y=1200*l.sideScale*.45}
        c.down();c.up();eq(c.taskClicks,1,"Task click")
        near(c.taskX,540,"Task exact x");near(c.taskY,1200,"Task exact y")
        c.scroll();eq(c.taskWheel,1,"Task left wheel")
        c.mouse={x=1000,y=300};c.scroll();eq(c.taskWheel,1,"Task right consumed")
        eq(c.wheel,0,"no tower wheel under Task")
        c.task=false;c.scroll();eq(c.wheel,1,"right tower wheel")
        eq(c.ordinary,0,"no mainline equipment wheel")
        c.mouse={x=1000,y=300};c.down();c.move(1000,250);c.up()
        check(c.moves>0,"sidebar drag wired")
        eq(#c.clicks,0,"scroll no click")
        local h=read("boot/StandaloneHorizon.lua")
        check(h:find("HorizonUpdateTransform()\n    if horizonInputContext.observeTowerPress then horizonInputContext.observeTowerPress() end",1,true)~=nil,"render observes current transform")
        check(h:find("towerLayout.sideScale",1,true)~=nil,"Task draw shares tower scale")
    end)
    runCase("actual Panel hide show pending lock leaves choices and receipt identity",function()
        local env,mods,stat=private()
        mods["core.DrawUtil"]={}
        mods["systems.ButtonFeedback"]={}
        mods["shared.Protocol"]={ACTION_TYPES={}}
        mods["ui.widget.KeywordText"]={new=function()return {clear=noop}end}
        mods["ui.tower.TowerChoiceView"]={cardRect=noop,fit=noop,destroyWidgets=noop}
        mods["ui.tower.TowerOathEffect"]={release=noop,destroy=noop}
        local panel=compile("ui/tower/TowerBuffPick.lua",env)
        local choices={mods["config.TowerConfig"].BUFFS_BY_ID[1],mods["config.TowerConfig"].BUFFS_BY_ID[2]}
        local receipt={runId="r1",selectionId="s1",floor=1,wave=1}
        panel.open(1,choices,nil,receipt)
        local s=state(panel.isOpen)
        local request=s.request
        local key=panel.getPresentationKey()
        check(panel.hide(),"hide allowed before request")
        check(panel.isOpen() and not panel.isVisible(),"hidden still outstanding")
        check(key~=panel.getPresentationKey(),"hide updates version")
        check(s.choices==choices and s.request==request,"hide retains choices request")
        check(panel.show() and panel.isVisible(),"show restores same cards")
        check(s.choices==choices and s.request==request,"show no reroll or new selection")
        s.pending=true;s.pendingRequest={buffId=1,requestId="q1"}
        local pending=s.pendingRequest
        key=panel.getPresentationKey()
        check(not panel.hide(),"pending cannot hide")
        eq(panel.getPresentationKey(),key,"rejected hide keeps version")
        check(s.pendingRequest==pending and s.pending,"pending identity retained")
        eq(stat.actions,0,"hide show no gameplay dispatch")
        panel.destroy()
    end)
    local function sceneFixture()
        local env,mods,stat=private()
        mods["urhox-libs/UI"]=fakeUI(stat)
        mods["ui.widget.DesignWidgetSurface"]={init=noop,draw=noop}
        local panel={open=false,visible=false,version=0,pending=false,showCalls=0,clicks=0}
        function panel.close()panel.open,panel.visible=false,false;panel.version=panel.version+1 end
        function panel.isOpen()return panel.open end
        function panel.isVisible()return panel.visible end
        function panel.getPresentationKey()return panel.version..":"..tostring(panel.pending)end
        function panel.show()panel.visible=true;panel.version=panel.version+1;panel.showCalls=panel.showCalls+1 end
        panel.setSendAction=noop;panel.draw=noop;panel.handleClick=function()panel.clicks=panel.clicks+1 end
        local tri={confirm=false,clicks=0,retreats=0}
        tri.isConfirmationOpen=function()return tri.confirm end
        tri.getPresentationKey=function()return "tri:"..tostring(tri.confirm)end
        tri.forceClose=noop;tri.isOpen=function()return true end
        tri.draw=function()stat.frames[#stat.frames+1]="middle"end
        tri.requestRetreat=function()tri.retreats=tri.retreats+1;tri.confirm=true end
        tri.handleClick=function()tri.clicks=tri.clicks+1 end
        local side={action=nil,scrolls=0,drag=0,version=0,collapsed=false}
        side.getPresentationKey=function()return side.version..":"..tostring(side.collapsed)end
        side.toggleCollapsed=function()side.collapsed=not side.collapsed;side.version=side.version+1 end
        side.reset=function()side.collapsed=false;side.version=side.version+1 end
        side.draw=function()stat.frames[#stat.frames+1]="sides"end
        side.handleClick=function()return side.action end
        side.handleScroll=function()side.scrolls=side.scrolls+1 end
        side.dragBegin=function()side.drag=side.drag+1 end
        side.dragMove=noop;side.dragEnd=noop
        mods["ui.tower.TowerBuffPick"],mods["ui.tower.TowerTriBattle"],mods["ui.tower.TowerBuffSidebar"]=panel,tri,side
        mods["systems.TowerBuffRuntime"]={cleanup=noop,applyStatBuffs=noop,initMechanics=noop}
        mods["ui.dungeon.DungeonBattle"]={}
        mods["shared.Protocol"]={ACTION_TYPES={}}
        mods["ui.battle.popup.BattleResultPanel"]={isOpen=function()return false end, resetToDefault=noop}
        mods["ui.battle.scene.BattleDraw"]={drawTextStroke=noop}
        mods["systems.BattleStats"]={}
        mods["config.HeroConfig"]={HEROES={}}
        mods["systems.AttributeDef"]={}
        local scene=compile("ui/tower/TowerBattleScene.lua",env)
        scene._openWaveBattle=function()return true end
        return scene,state(scene.isActive),panel,tri,side,stat
    end
    runCase("actual Scene copied snapshot open-session ABA modal routing",function()
        local scene,s,panel,tri,side,stat=sceneFixture()
        local opts={data={runId="same",floor=5,wave=1,buffs={1,2}},teamAllies={{},{},{}}}
        scene.open(opts);local key=scene.getPresentationKey()
        scene.open(opts);check(key~=scene.getPresentationKey(),"same run new open session")
        local snapshot=scene.getDisplayState();snapshot.buffIds[1]=999;eq(s.buffIds[1],1,"snapshot immutable")
        scene.draw({},1920,1080);eq(stat.frames[1],"sides","side draw first");eq(stat.frames[2],"middle","middle draw next")
        scene.handleClick(100,300,1920,1080);eq(tri.clicks,0,"left read-only")
        scene.handleClick(960,300,1920,1080);eq(tri.clicks,1,"middle click")
        side.action="toggle_buffs";local beforeToggle=scene.getPresentationKey()
        scene.handleClick(1700,100,1920,1080)
        check(side.collapsed and scene.getPresentationKey()~=beforeToggle,"收起动作改变真实Scene按压版本")
        eq(tri.clicks,1,"收起不穿透中栏战斗")
        scene.handleClick(1700,100,1920,1080)
        check(not side.collapsed and scene.getPresentationKey()~=beforeToggle,"展开ABA仍使旧按压失效")
        side.action="retreat";scene.handleClick(1700,1020,1920,1080);eq(tri.retreats,1,"existing retreat API")
        scene.handleScroll(-1,100,300,1920,1080);eq(side.scrolls,0,"confirmation blocks list")
        tri.confirm=false;s.phase="battle";panel.open,panel.visible=true,true
        scene.handleClick(100,300,1920,1080);eq(panel.clicks,1,"visible pick modal")
        panel.visible=false;side.action="resume_pick"
        scene.handleClick(1700,1020,1920,1080);eq(panel.showCalls,1,"hidden pick resume")
        eq(#s.buffIds,2,"resume no buff append");eq(s.wave,1,"resume keeps the one-wave floor")
        panel.visible=false;scene.handleScroll(-1,100,300,1920,1080);eq(side.scrolls,1,"hidden pick allows list")
        scene.handleDragBegin(100,300,1920,1080);eq(side.drag,1,"hidden pick drag")
        panel.visible=true;scene.handleScroll(-1,100,300,1920,1080);eq(side.scrolls,1,"visible modal no scroll")
        eq(stat.actions,0,"Scene UI no action")
    end)
    runCase("actual Tri right cancel same defeat rule and middle frame crop",function()
        local env,mods,stat=private()
        local function generic()return setmetatable({}, {__index=function()return noop end})end
        for name in read("ui/tower/TowerTriBattle.lua"):gmatch('require%("([^"]+)"%)')do
            if not mods[name]then mods[name]=generic()end
        end
        local page=mods["ui.battle.tri.BattleTriPage"]
        local text=read("ui/battle/tri/BattleTriPage.lua")
        local a=assert(text:find("local INTERIORS =",1,true));local b=assert(text:find("--- 战斗卡点击",a,true))
        page.getInteriorRectFor=assert(load("local PLATE_AR=1672/941\n"..text:sub(a,b-1).."\nreturn interiorRect","@real-interiors","t",env))()
        page.drawL0=function(_,w,h)stat.frames[#stat.frames+1]={w,h,"L0"}end
        page.drawL1Underlay=function(_,w,h,path)stat.frames[#stat.frames+1]={w,h,path}end
        mods["core.BattleLayout"]={STRIP_W=1672,STRIP_H=700,setMode=noop}
        mods["ui.battle.combat.BattleCombat"].DEATH_ANIM_DURATION=.4
        mods["ui.battle.scene.BattleView"].draw=function()stat.views[#stat.views+1]=true end
        mods["ui.tower.TowerBuffSidebar"]={drawConfirmation=noop}
        -- PlayerStore已不是真实Tri依赖；不加载或伪造无用业务存档模块。
        mods["core.I18n"]={get=function()return "zh_CN" end}
        mods["core.I18nTower"]=compile("core/I18nTower.lua",env)
        mods["ui.tower.TowerPresentation"]=compile("ui/tower/TowerPresentation.lua",env)
        mods["core.DrawUtil"].drawTextStroke=function(_,_,_,text,_,_,r,g,b)
            stat.hudText,stat.hudColor=text,{r,g,b}
        end
        mods["ui.battle.popup.BattleResultPanel"].isOpen=function()return false end
        local dungeon=mods["ui.dungeon.DungeonBattle"]
        dungeon.getElapsed=function()return 5 end;dungeon.getTimeRemaining=function()return 120 end;dungeon.getRagePhase=function()return 0 end
        dungeon.onDefeat=function()stat.defeats=(stat.defeats or 0)+1 end
        local tri=compile("ui/tower/TowerTriBattle.lua",env)
        local s=state(tri.isOpen);s.open=true;s.phase="active";s.floor=112;s.wave=1
        for row=1,3 do s.lanes[row]={allies={},enemies={},queue={},wiped=false,cleared=false}end
        for _,size in ipairs({{1920,1080},{1280,800}})do
            stat.clips,stat.views={},{}
            tri.draw({},size[1],size[2]);eq(#stat.views,3,"three real Tri draw calls")
            eq(stat.hudText,"第112层  剩余120s","顶部只显示实际楼层与剩余秒数")
            for phase=1,2 do
                dungeon.getRagePhase=function()return phase end
                tri.draw({},size[1],size[2])
                eq(stat.hudText,"第112层  剩余120s","狂暴阶段也保留实际层号无波次")
                eq(stat.hudColor[1],255,"狂暴红色保持")
                eq(stat.hudColor[2],phase==1 and 102 or 34,"狂暴与超级狂暴颜色保留")
            end
            dungeon.getRagePhase=function()return 0 end
            local l=mods["ui.tower.TowerLayout"].compute(size[1],size[2])
            near(stat.clips[1].x,l.center.x,"frame middle clip")
            near(stat.clips[1].w,l.center.w,"frame clip width")
            for i=2,4 do check(stat.clips[i].x>=l.center.x and stat.clips[i].x+stat.clips[i].w<=l.center.x+l.center.w,"content clip inside")end
            eq(stat.depth,0,"Tri balanced drawing")
            tri.requestRetreat();local key=tri.getPresentationKey()
            local d=mods["ui.tower.TowerLayout"].confirm(l)
            tri.handleClick(d.cancel.x+d.cancel.w*.5,d.cancel.y+d.cancel.h*.5,size[1],size[2])
            check(not tri.isConfirmationOpen(),"right cancel closes confirm")
            eq(s.phase,"active","cancel keeps battle active")
            eq(stat.defeats,nil,"cancel no defeat")
            tri.requestRetreat();check(key~=tri.getPresentationKey(),"request-cancel-request ABA version")
            tri.handleClick(d.cancel.x+d.cancel.w*.5,d.cancel.y+d.cancel.h*.5,size[1],size[2])
        end
        tri.requestRetreat();local d=mods["ui.tower.TowerLayout"].confirm(mods["ui.tower.TowerLayout"].compute(1280,800))
        tri.handleClick(d.retreat.x+90,d.retreat.y+28,1280,800)
        eq(s.phase,"lose","left retreat original defeat phase")
        eq(stat.defeats,1,"left retreat existing defeat exactly once")
    end)
    print(TAG.."SUMMARY cases="..cases.." checks="..checks.." failures="..failures)
    print(TAG..(failures==0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
