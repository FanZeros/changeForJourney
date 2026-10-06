-- 专项只读测试：2D脚手架 Start/Stop 生命周期，真实配置/Dialog/DrawUtil，其他业务为内存mock。
-- 必须 cwd=/home/Maker/resource-dungeon-visual-validation-20261006，ROOT只从-tapcode_dir解析。
-- /home/Maker/resource-dungeon-visual-validation-20261006/.cli/UrhoXRuntime tests/resource_dungeon_visual_test.lua -tapcode_dir=<1005根>
--   -tool_mode -nosound -graphicsheadless -validate -validate-frames=60 -validate-timeout=45
--   -validate-output=<隔离cwd>/validate.json
-- 可选 -review=main|resources|gold|equipment|diamond|tower：真实Dialog/DrawUtil/PNG/NanoVG截图。
-- main只是选关“主线”分类，绝不是main.lua/完整Boot.run/完整main/战斗或存档验收。
-- review用-graphicssurfaceless -screenshot=<隔离cwd>/xxx.png -screenshot-frame=120 -x 1080 -y 2400。
-- 资源副本扁平4分类按金币/装备/黑钻/通天塔顺序，全部在同一Dialog中选层。
-- 不装载真实GameState/save/业务runtime action；固定FILE_READ白名单之外均拒绝。

local ROOT, REVIEW = "", ""
for _, arg in ipairs(GetArguments()) do
    local root = arg:match("^%-tapcode_dir=(.+)$")
    if root then ROOT = root:gsub("/+$", "") end
    local view = arg:match("^%-review=(.+)$")
    if view then REVIEW = view end
end
local CWD = "/home/Maker/resource-dungeon-visual-validation-20261006"
local TAG = "[resource_dungeon_visual_test] "
local PATHS = {
    gold_mine = "image/战斗背景/金币副本.png", equipment_vault = "image/战斗背景/装备副本.png",
    black_diamond = "image/战斗背景/黑钻副本.png", babel_tower = "image/战斗背景/通天塔.png",
}
local SOURCE_FILES = {
    ["config.StageConfig"] = "config/StageConfig.lua",
    ["config.StageConfig_Normal"] = "config/StageConfig_Normal.lua",
    ["config.StageConfig_Hard"] = "config/StageConfig_Hard.lua",
    ["config.StageConfig_Nightmare"] = "config/StageConfig_Nightmare.lua",
    ["config.StageConfig_Hell"] = "config/StageConfig_Hell.lua",
    ["config.StageConfig_Purgatory"] = "config/StageConfig_Purgatory.lua",
    ["config.StageConfig_Torment"] = "config/StageConfig_Torment.lua",
    ["config.StageConfig_Torment2"] = "config/StageConfig_Torment2.lua",
    ["config.StageConfig_Torment3"] = "config/StageConfig_Torment3.lua",
    ["config.StageConfig_Torment4"] = "config/StageConfig_Torment4.lua",
    ["config.StageConfig_Torment5"] = "config/StageConfig_Torment5.lua",
    ["config.StageConfig_Annihilation"] = "config/StageConfig_Annihilation.lua",
    ["config.StageConfig_Annihilation2"] = "config/StageConfig_Annihilation2.lua",
    ["config.StageConfig_Annihilation3"] = "config/StageConfig_Annihilation3.lua",
    ["config.StageConfig_Annihilation4"] = "config/StageConfig_Annihilation4.lua",
    ["config.StageConfig_Annihilation5"] = "config/StageConfig_Annihilation5.lua",
    ["config.DungeonConfig"] = "config/DungeonConfig.lua",
    ["config.DungeonIdleConfig"] = "config/DungeonIdleConfig.lua",
    ["config.MonsterConfig"] = "config/MonsterConfig.lua",
    ["config.TowerConfig"] = "config/TowerConfig.lua",
    ["ui.battle.stage.BattleEnemySpawn"] = "ui/battle/stage/BattleEnemySpawn.lua",
    ["ui.battle.stage.StageSelectDialog"] = "ui/battle/stage/StageSelectDialog.lua",
    ["ui.battle.stage.StageSelectResources"] = "ui/battle/stage/StageSelectResources.lua",
    ["ui.battle.tri.BattleTriPage"] = "ui/battle/tri/BattleTriPage.lua", -- 只提取背景常量+纯resolver
    ["core.DrawUtil"] = "core/DrawUtil.lua", ["core.DarkIcon"] = "core/DarkIcon.lua",
}
local nativeFile, nativeCreateImage, nativeFS = File, nvgCreateImage, fileSystem
local sources, reads, contexts, initialLoaded = {}, {}, {}, {} ---@type any
local checks, groups, failures, floorCoverage, towerCoverage = 0, 0, 0, 0, 0
for name in pairs(SOURCE_FILES) do initialLoaded[name] = package.loaded[name] end
local function check(ok, label) checks = checks + 1; assert(ok, label) end
local function eq(a,b,label) check(a == b,label .. " actual=" .. tostring(a) .. " expected=" .. tostring(b)) end
local function near(a,b,label) check(type(a)=="number" and math.abs(a-b)<0.000001,label) end
local function noop() end
local function copy(t)
    if type(t) ~= "table" then return t end
    local r = {}; for k,v in pairs(t) do r[k] = copy(v) end; return r
end
local function same(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function compareExcept(a,b,except,label)
    local x,y = copy(a),copy(b)
    for k in pairs(except) do x[k],y[k] = nil,nil end
    check(same(x,y),label)
end
local function source(name)
    local rel = assert(SOURCE_FILES[name],"source denied " .. tostring(name))
    if sources[name] then return sources[name] end
    local path = ROOT .. "/scripts/" .. rel
    assert(ROOT:sub(1,1)=="/" and not ROOT:find("..",1,true) and not ROOT:find("//",1,true))
    -- 原生File唯一出口：已固定rel白名单、FILE_READ、每次Dispose，不接受玩家文件或写模式。
    local f = assert(nativeFile(path,FILE_READ),"File unavailable " .. path)
    assert(f:IsOpen(),"source open failed " .. path)
    local ok,text = pcall(function()
        local lines = {}; while not f:IsEof() do lines[#lines+1] = f:ReadLine() end
        return table.concat(lines,"\n")
    end)
    f:Dispose(); assert(ok,text); sources[name] = text; reads[#reads+1] = path; return text
end
local function compile(text,label,env)
    local chunk,why = load(text,"@" .. label,"t",env); assert(chunk,why); return chunk()
end

-- 冻结oracle，git show ca609d7162a5e75c6ba3b0045e8750b5ab70aa79:scripts/config/DungeonConfig.lua。
-- 只读原commit取得，绝不从合并后逻辑反推；含远端累计最大敌人数/首通bonus全清/扁平1-N。
-- 原完整SHA256=6c878c85e4badb35e226c9c496597a0afd10e5d6e9ef7c407365da7b0ebad9d6。
-- 原旧数据段(三资源分隔符前)冻结UTF8字节数27716/FNV1a32=1709042829，下面原资源段逐字冻结。
-- 验证前段指纹后才复用真实前段，避免另建baseline文件；前段变化必须失败而不是更新oracle。
local LEGACY_TAIL = [==[
-- ======================== 三类资源副本 ========================

local StageConfig = require("config.StageConfig")

DungeonConfig.RESOURCE_IDS = { "gold_mine", "equipment_vault", "black_diamond" }
DungeonConfig.EXTRA_ENEMIES = 2
DungeonConfig.DEFINITIONS = {
    gold_mine = {
        name = "金币副本", unlockStage = 305, maxFloor = 115,
        cardImage = "image/界面底板/副本秘境/UI_FBRK_1.png",
        rewardType = "gold", rewardIcon = "image/货币道具/UI_icon_JB_X.png", quality = 2,
    },
    equipment_vault = {
        name = "装备副本", unlockStage = 1305, maxFloor = 109,
        cardImage = "image/界面底板/副本秘境/UI_FBRK_2.png",
        rewardType = "equip", rewardIcon = "image/货币道具/UI_icon_FBBX.png", quality = 4,
    },
    black_diamond = {
        name = "黑钻副本", unlockStage = 605, maxFloor = 115,
        cardImage = "image/界面底板/副本秘境/UI_FBRK_3.png",
        rewardType = "diamond", rewardIcon = "image/货币道具/UI_icon_SJ_X.png", quality = 5,
    },
}
for _, id in ipairs(DungeonConfig.RESOURCE_IDS) do
    local def = DungeonConfig.DEFINITIONS[id]
    DungeonConfig.UNLOCK_CONDITIONS[id] = def.unlockStage
    DungeonConfig.MAX_FLOOR[id] = def.maxFloor
    DungeonConfig.DAILY_SWEEP_LIMIT[id] = 2
end

function DungeonConfig.isResourceDungeon(id)
    return DungeonConfig.DEFINITIONS[id] ~= nil
end

-- 各层沿主线普通关卡顺序前进，跳过终焉神殿，不把副本写进主线关卡链。
local sourceStages = {} ---@type table<string, number[]>
local sourceEnemyCounts = {} ---@type table<string, number[]>
local function getSourceStage(id, floor)
    local def = DungeonConfig.DEFINITIONS[id]
    if not def then return nil end
    if not sourceStages[id] then
        local ids, counts = {}, {}
        local highestCount = 0
        ---@type number|nil
        local stageId = def.unlockStage
        while #ids < def.maxFloor and stageId do
            if not StageConfig.isTerminalTemple(stageId) then
                local source = StageConfig.getStage(stageId)
                highestCount = math.max(highestCount, source.firstCount or source.idleCount or 4)
                ids[#ids + 1] = stageId
                counts[#ids] = highestCount
            end
            local nextId = StageConfig.getNextStageId(stageId)
            if not nextId and StageConfig.isTerminalTemple(stageId) then
                nextId = StageConfig.getReincarnationTarget(StageConfig.getDifficulty(stageId))
            end
            stageId = nextId
        end
        sourceStages[id] = ids
        sourceEnemyCounts[id] = counts
    end
    return StageConfig.getStage(sourceStages[id][floor])
end

--- 资源副本与预览共用的完整主线型出怪配置；复制后修改，不污染 StageConfig。
---@return table|nil
function DungeonConfig.getCombatEntry(id, floor)
    floor = math.tointeger(tonumber(floor) or 0)
    local def = DungeonConfig.DEFINITIONS[id]
    if not def or not floor or floor < 1 or floor > def.maxFloor then return nil end
    local source = getSourceStage(id, floor)
    if not source then return nil end
    ---@type table<string, any>
    local entry = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            local copy = {}
            for k, v in pairs(value) do copy[k] = v end
            entry[key] = copy
        else
            entry[key] = value
        end
    end
    entry.name = def.name
    -- 资源连续关不应在借用主线下一章首关时从28/32名敌人骤降至12名。
    entry.firstCount = sourceEnemyCounts[id][floor] + DungeonConfig.EXTRA_ENEMIES
    entry.idleCount = entry.firstCount
    entry.firstClearBonusMonster, entry.firstClearBonusMonsters = nil, nil
    entry.maxFieldEnemies = 4
    entry.mode = "resource_dungeon"
    entry.dropRate, entry.scrollDropRate = 0, 0
    entry.fcGold, entry.fcExp, entry.fcDiamond, entry.fcEssence = 0, 0, 0, 0
    entry.fcArcaneDust, entry.fcEquip, entry.fcScroll = 0, 0, 0
    return entry
end

--- 获取层配置，旧遗迹仍能按原规则结清旧数据，不挪用为新装备副本。
---@return table|nil
function DungeonConfig.getFloor(id, floor)
    floor = math.tointeger(tonumber(floor) or 0)
    if not floor or floor < 1 or floor > (DungeonConfig.MAX_FLOOR[id] or 0) then return nil end
    if id == "ancient_ruin" then return DungeonConfig.getAncientRuinFloor(floor) end
    local combat = DungeonConfig.getCombatEntry(id, floor)
    if not combat then return nil end
    local result = { floor = floor, monsterLevel = combat.monsterLevel, monsters = combat.monsters }
    if id == "gold_mine" then
        local old = DungeonConfig.getGoldMineFloor(floor)
        if not old then return nil end
        result.firstGold, result.sweepGold = old.firstGold, old.sweepGold
    elseif id == "equipment_vault" then
        local cap = StageConfig.getMaxDropQuality(combat)
        result.firstEquip, result.sweepEquip = 6, 3
        result.equipLevel = combat.monsterLevel
        result.equipMinQuality, result.equipMaxQuality = math.min(3, cap), cap
    elseif id == "black_diamond" then
        result.firstDiamond = 150 + (floor - 1) * 50
        result.sweepDiamond = math.floor(result.firstDiamond / 2)
    end
    return result
end

--- 含终层的最高已通层；旧档没有账本时沿用 floor-1。
function DungeonConfig.getHighestClearedFloor(sub, id)
    local maxFloor = DungeonConfig.MAX_FLOOR[id] or 0
    local highest = math.min(maxFloor, math.max(0, math.floor(tonumber(sub and sub.floor) or 1) - 1))
    for key, cleared in pairs(sub and sub.cleared or {}) do
        local floor = math.tointeger(tonumber(key) or 0)
        if cleared == true and floor and floor > highest and floor <= maxFloor then highest = floor end
    end
    return highest
end

-- 资源关卡使用独立ID；只记录队伍位置，不进入主线进度链。
local RESOURCE_STAGE_BASE = { gold_mine = 100000, equipment_vault = 200000, black_diamond = 300000 }
local resourceStages = {}

function DungeonConfig.getStageId(id, floor)
    local base = RESOURCE_STAGE_BASE[id]
    local level = math.tointeger(tonumber(floor) or 0)
    if not base or not level or level < 1 or level > (DungeonConfig.MAX_FLOOR[id] or 0) then return nil end
    return base + level
end

function DungeonConfig.decodeStageId(stageId)
    local value = math.tointeger(tonumber(stageId) or 0)
    if not value then return nil end
    for id, base in pairs(RESOURCE_STAGE_BASE) do
        local floor = value - base
        if floor >= 1 and floor <= DungeonConfig.MAX_FLOOR[id] then return id, floor end
    end
    return nil
end

function DungeonConfig.getStage(stageId)
    local id, floor = DungeonConfig.decodeStageId(stageId)
    if not id then return nil end
    if resourceStages[stageId] then return resourceStages[stageId] end
    local entry = DungeonConfig.getCombatEntry(id, floor)
    if not entry then return nil end
    entry.sourceStageId = entry.id
    entry.id = stageId
    entry.resourceDungeonId, entry.resourceFloor = id, floor
    entry.displayChapter = 1
    entry.stage = floor
    entry.name = DungeonConfig.DEFINITIONS[id].name .. " " .. entry.displayChapter .. "-" .. entry.stage
    entry.firstClearBonusMonster, entry.firstClearBonusMonsters = nil, nil
    entry.mapBg = "image/关卡地图/" .. (id == "gold_mine" and "MAP_FB1.png" or (id == "equipment_vault" and "MAP_FB2.png" or "MAP_FB3.png"))
    resourceStages[stageId] = entry
    return entry
end

function DungeonConfig.isStageUnlocked(stageId, battleData, dungeonData)
    local id, floor = DungeonConfig.decodeStageId(stageId)
    if not id then return false end
    local def = DungeonConfig.DEFINITIONS[id]
    local maxId = tonumber(battleData and battleData.maxStageId) or 0
    local previous = StageConfig.getTerminalPrevStageId(maxId)
    local maxRank = previous and previous + 0.5 or maxId
    if maxRank < def.unlockStage then return false end
    local sub = type(dungeonData) == "table" and dungeonData[id] or nil
    return floor <= math.min(def.maxFloor, DungeonConfig.getHighestClearedFloor(sub, id) + 1)
end

-- 在线每次击杀与离线固定杀怪效率复用原每分钟收益，不把一次扫荡变为无限波大奖。
function DungeonConfig.getStageRewards(stageId, kills)
    local id, floor = DungeonConfig.decodeStageId(stageId)
    local rewards = { gold = 0, diamond = 0, adventureExp = 0, adventurerExp = 0, equipSeeds = {}, scrollDrops = {} }
    if not id or (tonumber(kills) or 0) <= 0 then return rewards end
    local idle = require("config.DungeonIdleConfig")
    local rate = idle.getIdlePerMin(id, floor)
    local perMinute = id == "equipment_vault" and rate or rate * idle.REWARD_MULT
    local raw = math.max(0, kills) * perMinute / 20 -- 每3秒1只，即每分钟20只。
    local amount = math.floor(raw)
    if math.random() < raw - amount then amount = amount + 1 end
    if id == "gold_mine" then rewards.gold = amount
    elseif id == "black_diamond" then rewards.diamond = amount
    elseif amount > 0 then
        local data = DungeonConfig.getFloor(id, floor)
        for _ = 1, amount do
            rewards.equipSeeds[#rewards.equipSeeds + 1] = {
                stageId = stageId, count = 1, level = data.equipLevel,
                quality = math.random(data.equipMinQuality, data.equipMaxQuality),
            }
        end
    end
    return rewards
end


return DungeonConfig
]==]
local function legacySource()
    local text = source("config.DungeonConfig")
    local marker = "-- ======================== 三类资源副本 ========================"
    local first = assert(text:find(marker,1,true),"legacy boundary missing")
    local prefix = text:sub(1,first-1)
    local hash = 2166136261
    for i=1,#prefix do hash = ((hash ~ prefix:byte(i))*16777619) & 0xffffffff end
    eq(#prefix,27716,"legacy前段冻结字节数"); eq(hash,1709042829,"legacy前段冻结FNV1a")
    return prefix .. LEGACY_TAIL
end
local NVG = {
    "nvgArc", "nvgBeginPath", "nvgBezierTo", "nvgCircle", "nvgClosePath", "nvgCreateImage", "nvgDeleteImage",
    "nvgEllipse", "nvgFill", "nvgFillColor", "nvgFillPaint", "nvgFontFace", "nvgFontSize", "nvgTextBounds",
    "nvgGlobalCompositeBlendFuncSeparate", "nvgGlobalCompositeOperation", "nvgImagePattern", "nvgImagePatternTinted",
    "nvgImageSize", "nvgIntersectScissor", "nvgLineCap", "nvgLineJoin", "nvgLineTo", "nvgLinearGradient",
    "nvgMoveTo", "nvgQuadTo", "nvgRGBA", "nvgRadialGradient", "nvgRect", "nvgRestore", "nvgRotate",
    "nvgRoundedRect", "nvgRoundedRectVarying", "nvgSave", "nvgScale", "nvgShapeAntiAlias", "nvgSkewX",
    "nvgStroke", "nvgStrokeColor", "nvgStrokeWidth", "nvgText", "nvgTextAlign", "nvgTranslate", "nvgResetTransform",
}
local function newContext(legacy,review,vg)
    local c = { env={}, modules={}, loading={}, denied={}, calls={}, events={}, loads={}, handles={}, deleted={},
        clock={elapsedTime=100}, teams={101,201,301}, maxStage=34505, accepts=true, selections={}, towerSelections={},
        vg=vg or {}, nextHandle=1, review=review==true, randomValue=0.5, randomCalls=0, imageResult={}, badSize={},
        memory={currency={gold=1234,diamond=567,ticket=8},battle={maxStageId=34505,activeTeam=2,
            teamStageIds={101,201,301},clearedStages={['101']=true}},dungeon={
            gold_mine={floor=1,cleared={},sweepsToday=1},equipment_vault={floor=1,cleared={},sweepsToday=1},
            black_diamond={floor=1,cleared={},sweepsToday=1},babel_tower={floor=1,sweepsToday=1}}},
    } ---@type any
    contexts[#contexts+1]=c
    local e=c.env
    local function deny(label) c.denied[#c.denied+1]=label; error("isolated test denies " .. label) end
    c.deny=deny
    local function blocked(label)
        return setmetatable({}, {__index=function(_,k) return function() return deny(label .. "." .. tostring(k)) end end})
    end
    for _,k in ipairs({"assert","error","ipairs","pairs","next","pcall","xpcall","select","tonumber",
        "tostring","type","setmetatable","getmetatable","rawget","rawset","rawequal"}) do e[k]=_G[k] end
    e.math,e.string,e.table,e.utf8=copy(math),copy(string),copy(table),copy(utf8)
    e.math.random=function(a,b)
        c.randomCalls=c.randomCalls+1
        if a==nil then return c.randomValue end
        if b==nil then b,a=a,1 end
        return math.min(b,a+math.floor(c.randomValue*(b-a+1)))
    end
    e.math.randomseed=function() return deny("global RNG seed") end
    e._G,e.time=e,c.clock; e.print=noop
    for k,v in pairs(_G) do if k:match("^NVG_") then e[k]=v end end
    e.File=function() return deny("File any path/mode") end
    for _,k in ipairs({"io","os","package","debug","cache","fileSystem","engine","network","clientCloud","serverCloud"}) do e[k]=blocked(k) end
    for _,k in ipairs({"load","loadfile","dofile","GetFileSystem","GetEngine","SubscribeToEvent","SendEvent"}) do e[k]=function() return deny(k) end end
    local function mock(name,fields)
        c.modules[name]=setmetatable(fields,{__index=function(_,k) return function() return deny(name .. "." .. tostring(k)) end end})
    end
    mock("config.GameConfig",{Design={WIDTH=1080,HEIGHT=2400},Battle={TIME_LIMIT_SEC=300}})
    mock("core.GameState",{getPower=function() return 100 end})
    mock("core.BattleLayout",{})
    mock("core.I18n",{get=function() return "zh_CN" end,lookup=function(s) return s end,
        difficulty=function(s) return s end,format=function(s,...) return string.format(s,...) end})
    mock("systems.ButtonFeedback",{trigger=function(k) c.events[#c.events+1]=k end,begin=function() return false end,finish=noop})
    mock("config.StageRecommendPower",{get=function() return nil end})
    mock("systems.AttributeDef",{DODGE="dodge",MAG_ARMOR="energyShield",HIT_VALUE="hitValue",CRIT_RATE="critRate",
        PHYS_ARMOR="armor",PHYS_PEN="physPen",MAG_PEN="magPen",ATK_HEAL="atkHeal",COMBO_RATE="comboRate",
        ATK_SPEED="atkSpeed",ABNORMAL_RES="abnormalRes"})
    mock("systems.UnitAttributes",{})
    mock("runtime.ClientDispatcher",{get=function(key)
        if key=="battle" or key=="dungeon" then return c.memory[key] end
        return deny("dispatcher unknown get " .. tostring(key))
    end})
    mock("ui.battle.scene.BattleScene",{getMaxStageId=function() return c.maxStage end,
        getStageId=function() return c.teams[1] end,getClearedStages=function() return c.memory.battle.clearedStages end})
    mock("ui.battle.tri.BattleTriPage",{getTeamStageId=function(team) return c.teams[team] end,
        gotoTeamStage=function(team,id)
            c.selections[#c.selections+1]={team=team,id=id}
            if c.accepts then c.teams[team]=id; return true end
            return false
        end})
    -- 不提供任何global fallback；SC->DC是函数内lazy require，DC->SC顶层按真实顺序完成。
    e.require=function(name)
        if c.modules[name] then return c.modules[name] end
        if not SOURCE_FILES[name] or name=="ui.battle.tri.BattleTriPage" then return deny("unknown require " .. tostring(name)) end
        if c.loading[name] then return deny("unexpected eager circular require " .. name) end
        c.loading[name]=true
        local text=(legacy and name=="config.DungeonConfig") and legacySource() or source(name)
        local result=compile(text,ROOT .. "/scripts/" .. SOURCE_FILES[name],e)
        c.modules[name]=assert(result,"module no return " .. name); c.loading[name]=nil
        if name=="config.MonsterConfig" then
            -- 仅unit工厂mock，不运行属性/战斗业务；名字、模板品质、卡牌映射仍真实。
            result.createMonster=function(id,level)
                local tpl=assert(result.MONSTERS[id],"unknown monster " .. id)
                return {monsterId=id,level=level,quality=tpl.quality,name=tpl.name,goldReward=99,expReward=88}
            end
        end
        return result
    end
    setmetatable(e,{__index=function(_,k) return deny("unknown global " .. tostring(k)) end})
    c.require=e.require
    local shape,paint,clip,stack={},{},{},{} ---@type any
    local fontSize,align=24,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE
    clip=nil
    for _,k in ipairs(NVG) do e[k]=noop end
    e.nvgRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end
    e.nvgSave=function() stack[#stack+1]={clip=copy(clip),fontSize=fontSize,align=align} end
    e.nvgRestore=function()
        local saved=assert(table.remove(stack),"unbalanced nvgRestore")
        clip,fontSize,align=saved.clip,saved.fontSize,saved.align
    end
    e.nvgIntersectScissor=function(_,x,y,w,h)
        if clip then local r,b=math.min(x+w,clip.x+clip.w),math.min(y+h,clip.y+clip.h)
            x,y=math.max(x,clip.x),math.max(y,clip.y); w,h=math.max(0,r-x),math.max(0,b-y) end
        clip={x=x,y=y,w=w,h=h}
    end
    e.nvgFontSize=function(_,v) fontSize=v end; e.nvgTextAlign=function(_,v) align=v end
    e.nvgTextBounds=function(_,_,_,text) return (utf8.len(text) or #text)*fontSize*0.75 end
    e.nvgText=function(_,x,y,text) c.calls[#c.calls+1]={kind="rawText",text=text,x=x,y=y,size=fontSize,align=align,clip=copy(clip)}; return x end
    e.nvgBeginPath=function() shape,paint={},nil end
    e.nvgRect=function(_,x,y,w,h) shape={x=x,y=y,w=w,h=h} end
    e.nvgRoundedRect=function(_,x,y,w,h,r) shape={x=x,y=y,w=w,h=h,radius=r} end
    e.nvgFillPaint=function(_,p) paint=p end; e.nvgFillColor=function() paint=nil end
    e.nvgFill=function() c.calls[#c.calls+1]={kind="fill",shape=copy(shape),paint=copy(paint),clip=copy(clip)} end
    e.nvgStroke=function() c.calls[#c.calls+1]={kind="stroke",shape=copy(shape),clip=copy(clip)} end
    e.nvgLinearGradient,e.nvgRadialGradient=function() return {} end,function() return {} end
    local allowedImages={
        ["image/通用图标/UI_ICON_XG.png"]=true,["image/界面底板/通用面板/UI_TY_EJQRK.png"]=true,
        ["image/按钮/UI_AN_HUANG.png"]=true,["image/通用图标/UI_ICON_SUO.png"]=true,["image/通用图标/ICON_ZDL.png"]=true,
    }
    for _,p in pairs(PATHS) do allowedImages[p]=true end
    local sc=c.require("config.StageConfig")
    for ch=1,23 do allowedImages[sc.getBattleBackground(ch*100+1)]=true end
    local mc=c.require("config.MonsterConfig")
    for id in pairs(mc.MONSTERS) do allowedImages[string.format("image/怪物卡牌/KP_GW_%d.png",mc.getCardArtId(id))]=true end
    c.allowedImages=allowedImages
    e.nvgCreateImage=function(ctx,path,flags)
        if not allowedImages[path] then return deny("image path " .. tostring(path)) end
        c.loads[path]=(c.loads[path] or 0)+1
        local h
        if c.review then h=nativeCreateImage(ctx,path,flags); assert(h and h>=0,"real review image missing " .. path)
        else h=c.imageResult[path]; if h==nil then h=c.nextHandle; c.nextHandle=h+1 end end
        if h>=0 then c.handles[h]=path end; return h
    end
    e.nvgDeleteImage=function(ctx,h) c.deleted[h]=true; if c.review then nvgDeleteImage(ctx,h) end end
    e.nvgImageSize=function(_,h) if c.badSize[c.handles[h]] then return 0,0 end; return 1896,720 end
    e.nvgImagePattern=function(_,x,y,w,h,angle,handle,alpha)
        assert(handle>=0,"invalid image painted")
        return {path=c.handles[handle],handle=handle,x=x,y=y,w=w,h=h,alpha=alpha,angle=angle}
    end
    e.nvgImagePatternTinted=function(ctx,x,y,w,h,a,handle,tint) return e.nvgImagePattern(ctx,x,y,w,h,a,handle,tint.a/255) end
    if c.review then
        local create,delete=e.nvgCreateImage,e.nvgDeleteImage
        for _,k in ipairs(NVG) do e[k]=assert(_G[k],"real NVG unavailable " .. k) end
        e.nvgCreateImage,e.nvgDeleteImage=create,delete
    end
    c.clipBalanced=function() check(#stack==0 and clip==nil,"真实Dialog/DrawUtil save/scissor无泄漏") end
    c.prepareDialog=function()
        local du=c.require("core.DrawUtil")
        if not c.review then
            local realText,realCover=du.drawTextStroke,du.drawImageCover
            du.drawTextStroke=function(ctx,x,y,text,size,textAlign,r,g,b,sw,opts)
                c.calls[#c.calls+1]={kind="text",x=x,y=y,text=text,size=size,align=textAlign,clip=copy(clip)}
                return realText(ctx,x,y,text,size,textAlign,r,g,b,sw,opts)
            end
            du.drawImageCover=function(ctx,img,x,y,w,h,alpha)
                c.calls[#c.calls+1]={kind="card",path=c.handles[img],x=x,y=y,w=w,h=h,clip=copy(clip)}
                return realCover(ctx,img,x,y,w,h,alpha)
            end
        end
        c.dialog=c.require("ui.battle.stage.StageSelectDialog"); c.dialog.init(c.vg)
        c.dialog.setOnDungeonSelect(function(id,team,floor)
            c.towerSelections[#c.towerSelections+1]={id=id,team=team,floor=floor}; return c.accepts
        end)
        return c.dialog
    end
    c.draw=function() c.calls={}; c.clock.elapsedTime=c.clock.elapsedTime+1; c.dialog.draw(c.vg); if not c.review then c.clipBalanced() end end
    return c
end
local function idle(c,before) check(same(c.memory,before),"查看/选择没有货币、解锁、收益、扫荡次数或activeTeam消费") end
local function banners(c)
    local r={}; for _,v in ipairs(c.calls) do
        if v.kind=="fill" and v.paint and v.paint.path and v.shape.x==105 and v.shape.w==190 and v.shape.h==84 then r[#r+1]=v end
    end; return r
end
local function textAt(c,text,x,y)
    for _,v in ipairs(c.calls) do if (v.kind=="text" or v.kind=="rawText") and v.text==text and v.x==x and v.y==y then return v end end
end
local function rowLabel(c,floor)
    for _,v in ipairs(c.calls) do
        if v.kind=="text" and v.x==331 and v.text=="1-" .. floor then return v end
    end
end
local function visibleRow(c,floor)
    local label=assert(rowLabel(c,floor),"real Dialog row missing 1-" .. floor)
    local top=label.y-34
    local y=(math.max(786,top)+math.min(1676,top+168))*0.5
    check(y>=786 and y<1676,"实际可视行点击位于真实裁剪内")
    return 340,y,top
end
local function currentRow(c,floor)
    local label=assert(rowLabel(c,floor),"current row label missing")
    check(label.y-34>=786 and label.y-34+168<=1676,"reveal完整当前关落入右栏")
    check(textAt(c,"当前",331,label.y+100),"真实当前状态与当前层标签同一行")
end
local function openMain(c,team)
    c.dialog.close(); c.dialog.open(team or 1); c.draw()
end
local function configCases()
    local c,old=newContext(),newContext(true)
    local sc,dc=c.require("config.StageConfig"),c.require("config.DungeonConfig")
    local od=old.require("config.DungeonConfig")
    local before=copy(sc.STAGES)
    for _,id in ipairs(dc.RESOURCE_IDS) do
        compareExcept(dc.DEFINITIONS[id],od.DEFINITIONS[id],{cardImage=true},"def仅背景改变 " .. id)
        eq(dc.DEFINITIONS[id].cardImage,PATHS[id],"def专属图 " .. id)
        eq(dc.MAX_FLOOR[id],od.MAX_FLOOR[id],"资源floor上界不变")
        local highestSourceCount,previousCount=0,0
        for floor=1,dc.MAX_FLOOR[id] do
            floorCoverage=floorCoverage+1
            local sid=dc.getStageId(id,floor); eq(sid,od.getStageId(id,floor),"独立id不变")
            local a,b=dc.getCombatEntry(id,floor),od.getCombatEntry(id,floor)
            local exception=floor==1 and {monsters=true,bossId=true} or {}
            compareExcept(a,b,exception,"combat全部非允许字段不变 " .. id .. "/" .. floor)
            local src=sc.getStage(b.id)
            highestSourceCount=math.max(highestSourceCount,src.firstCount or src.idleCount or 4)
            eq(a.firstCount,highestSourceCount+2,"ca609d7累计最大敌人数保持")
            eq(a.idleCount,a.firstCount,"idle数量与累计首场一致")
            check(a.firstCount>=previousCount,"资源连续层数量不回落")
            previousCount=a.firstCount
            check(a.firstClearBonusMonster==nil and a.firstClearBonusMonsters==nil,"全层combat无首通附加怪")
            local stage,original=dc.getStage(sid),od.getStage(sid)
            eq(stage.displayChapter,1,"扁平副本永远第1章"); eq(stage.stage,floor,"扁平副本1-N实际层号")
            eq(stage.name,dc.DEFINITIONS[id].name .. " 1-" .. floor,"扁平副本完整名字")
            local stageExcept=copy(exception); stageExcept.mapBg=true
            compareExcept(stage,original,stageExcept,"stage全部非允许字段不变 " .. sid)
            eq(stage.mapBg,PATHS[id],"339层背景正确")
            eq(stage.sourceStageId,b.id,"sourceStage不能被1-2覆盖")
            local floorExcept=floor==1 and {monsters=true} or {}
            compareExcept(dc.getFloor(id,floor),od.getFloor(id,floor),floorExcept,"floor等级数量品质收益保持 " .. sid)
            if floor==1 then
                local pool=od.getCombatEntry(id,2).monsters
                check(same(a.monsters,pool) and same(stage.monsters,pool),"仅借1-2普通怪池 " .. id)
                eq(a.bossId,0,"combat首层no boss"); eq(stage.bossId,0,"stage首层no boss")
                check(a.firstClearBonusMonster==nil and a.firstClearBonusMonsters==nil,"combat清首通附加怪")
                check(stage.firstClearBonusMonster==nil and stage.firstClearBonusMonsters==nil,"stage无附加怪")
                for _,mid in ipairs(pool) do check(mid<200 and c.require("config.MonsterConfig").MONSTERS[mid]~=nil,"首层仅主线普通怪") end
                for _,firstClear in ipairs({false,true}) do
                    local list=c.require("ui.battle.stage.BattleEnemySpawn").generateEnemyList(stage,firstClear)
                    eq(#list,b.firstCount,"实际spawn数量不借第二层")
                    for i,u in ipairs(list) do
                        eq(u.monsterId,pool[(i-1)%#pool+1],"spawn循环普通池")
                        eq(u.level,b.monsterLevel,"spawn保留旧等级"); check(not u.isBoss and not u._isBonusMonster,"spawn没有Boss/bonus")
                        eq(u.goldReward,0,"资源怪本体金币仍0"); eq(u.expReward,0,"资源怪本体经验仍0")
                    end
                end
                a.monsters[1]=-999; a.qw[1]=-888
                check(same(dc.getCombatEntry(id,1).monsters,pool),"普通池每次复制，返回对象不污染source")
            end
            local owner,decoded=dc.decodeStageId(tostring(sid)); eq(owner,id,"decode资源种类"); eq(decoded,floor,"decode层")
        end
        for _,f in ipairs({0,-1,dc.MAX_FLOOR[id]+1,1.5,"bad"}) do eq(dc.getStageId(id,f),nil,"越界floor拒绝") end
    end
    eq(floorCoverage,339,"全部339层覆盖一次")
    check(same(sc.STAGES,before),"所有真实主线source无污染")
    local cursor,seen=101,{}
    for _=1,2000 do
        if not cursor or seen[cursor] then break end; seen[cursor]=true; check(not sc.isResourceStage(cursor),"资源不写主线链")
        cursor=sc.getNextStageId(cursor) or (sc.isTerminalTemple(cursor) and sc.getReincarnationTarget(sc.getDifficulty(cursor)) or nil)
    end
    -- 独立env真正DC-first，不能给SC/DC塞临时空表遮盖不成立的循环。
    local reverse=newContext()
    reverse.modules["config.DungeonConfig"],reverse.modules["config.StageConfig"]=nil,nil
    local rd=reverse.require("config.DungeonConfig"); local rs=reverse.require("config.StageConfig")
    for _,id in ipairs(rd.RESOURCE_IDS) do eq(rs.getStage(rd.getStageId(id,1)).sourceStageId,dc.getStage(dc.getStageId(id,1)).sourceStageId,"DC-first lazy循环依赖") end
end
local function economyCases()
    local c,old=newContext(),newContext(true)
    local dc,od=c.require("config.DungeonConfig"),old.require("config.DungeonConfig")
    local di,oi=c.require("config.DungeonIdleConfig"),old.require("config.DungeonIdleConfig")
    check(same(dc.UNLOCK_CONDITIONS,od.UNLOCK_CONDITIONS) and same(dc.DAILY_SWEEP_LIMIT,od.DAILY_SWEEP_LIMIT),"解锁门槛与次数冻结")
    for _,id in ipairs(dc.RESOURCE_IDS) do
        for f=1,dc.MAX_FLOOR[id] do
            local sid=dc.getStageId(id,f)
            for _,rank in ipairs({dc.UNLOCK_CONDITIONS[id]-1,dc.UNLOCK_CONDITIONS[id],34505,999}) do
                for _,sub in ipairs({{}, {floor=f}, {floor=1,cleared={[tostring(f)]=true}}, {floor=999,cleared={}}}) do
                    local ledger={[id]=sub}; local saved=copy(ledger)
                    eq(dc.isStageUnlocked(sid,{maxStageId=rank},ledger),od.isStageUnlocked(sid,{maxStageId=rank},ledger),"解锁oracle " .. sid)
                    check(same(ledger,saved),"解锁查询不写账本")
                end
            end
            near(di.getIdlePerMin(id,f),oi.getIdlePerMin(id,f),"每分钟收益保持")
            for _,random in ipairs({0,0.999999}) do
                c.randomValue,old.randomValue=random,random
                for _,kills in ipairs({0,1,20,4800}) do
                    c.randomCalls,old.randomCalls=0,0
                    check(same(dc.getStageRewards(sid,kills),od.getStageRewards(sid,kills)),"确定性随机击杀收益不变 " .. sid)
                    eq(c.randomCalls,old.randomCalls,"随机次数不变")
                end
            end
        end
        for _,f in ipairs({1,dc.MAX_FLOOR[id]}) do
            for _,sec in ipairs({0,59,60,86400,86460,604800,604860}) do
                local a,b=di.calcReward(id,f,sec,86400); local x,y=oi.calcReward(id,f,sec,86400)
                eq(a,x,"离线收益边界保持"); eq(b,y,"离线消费分钟保持")
            end
        end
    end
end
local function resolverCases()
    local c=newContext(); local sc=c.require("config.StageConfig")
    local text=source("ui.battle.tri.BattleTriPage")
    local first=assert(text:find("local CHAPTER_BG = {",1,true)); local last=assert(text:find("local function getBackgroundImage",first,true))
    -- 精确完整常量+resolve段，不load整个Tri，不带其生命周期/战斗/存档依赖。
    local block=text:sub(first,last-1)
    local tri={}; c.env.BattleTriPage,c.env.StageConfig=tri,sc
    compile(block,"actual-BattleTriPage-background-only",c.env)
    local dc=c.require("config.DungeonConfig")
    for _,id in ipairs(dc.RESOURCE_IDS) do for f=1,dc.MAX_FLOOR[id] do
        local sid=dc.getStageId(id,f); eq(tri.resolveBackgroundPath(sid),PATHS[id],"真实Tri339层resource优先")
        eq(tri.resolveBackgroundPath(tostring(sid)),PATHS[id],"Tri字符串id路径")
    end end
    eq(tri.resolveBackgroundPath(999),"image/战斗背景/终焉神殿.png","terminal保留")
    eq(tri.resolveBackgroundPath(101),sc.getBattleBackground(101),"主线保留")
    eq(tri.resolveBackgroundPath(2401),tri.resolveBackgroundPath(101),"主线23章循环保留")
    eq(tri.resolveBackgroundPath(nil),tri.resolveBackgroundPath(101),"nil fallback")
    eq(tri.resolveBackgroundPath("invalid"),tri.resolveBackgroundPath(101),"非法fallback")
end
local function layoutCases()
    local c=newContext(); local d=c.prepareDialog(); local saved=copy(c.memory); openMain(c)
    check(textAt(c,"选择关卡",540,732),"实际标题未上移")
    check(textAt(c,"主线",150,782) and textAt(c,"副本",250,782),"tab文本真实新中心")
    local tabShapes=0
    for _,v in ipairs(c.calls) do if v.kind=="fill" and v.shape.y==759 and v.shape.w==90 and v.shape.h==46 then
        check(v.shape.x==105 or v.shape.x==205,"tab新90x46矩形"); tabShapes=tabShapes+1 end end
    eq(tabShapes,2,"两新tab形状")
    local bs=banners(c); eq(#bs,7,"主线可见7章")
    for i,v in ipairs(bs) do eq(v.shape.y,876+(i-1)*94,"CH_Y0及step整体下移10"); eq(v.shape.radius,12,"章节圆角") end
    check(textAt(c,"1-1",331,824),"右栏ROW_Y0=790不移")
    local cards={}; for _,v in ipairs(c.calls) do if v.kind=="card" and v.y==852 then cards[#cards+1]=v end end
    check(#cards>0 and cards[1].x==503 and cards[1].w==92 and cards[1].h==104,"实际右栏卡片旧布局")
    for _,p in ipairs({{445,686},{635,686},{350,782},{500,782}}) do
        local n=#c.events; d.handleInput(p[1],p[2]); c.draw(); eq(#c.events,n,"旧tabs/右栏新同行空白不响应")
        eq(banners(c)[1].paint.path,bs[1].paint.path,"旧tab不能切分类"); check(d.isOpen(),"旧tab点不关闭")
    end
    for _,x in ipairs({205,250,295}) do for _,y in ipairs({759,782,805}) do
        d.handleInput(150,782); d.handleInput(x,y); c.draw(); eq(c.events[#c.events],"stage_sel_section","副本tab端点热区")
        eq(banners(c)[1].paint.path,PATHS.gold_mine,"新副本tab实际切分类")
    end end
    for _,x in ipairs({105,150,195}) do for _,y in ipairs({759,782,805}) do
        d.handleInput(250,782); d.handleInput(x,y); c.draw(); eq(banners(c)[1].paint.path,bs[1].paint.path,"主线tab端点热区")
    end end
    for _,p in ipairs({{204.999,782},{295.001,782},{250,758.999},{250,805.001},{200,782}}) do
        d.handleInput(150,782); local n=#c.events; d.handleInput(p[1],p[2]); eq(#c.events,n,"tab边外0.001/gap不响应")
    end
    eq(#c.selections,0,"查看tabs不跳主线/副本关"); eq(#c.towerSelections,0,"不碰tower"); idle(c,saved)
end
local function scrollCases()
    local c=newContext(); local d=c.prepareDialog(); local saved=copy(c.memory); openMain(c)
    local first=banners(c)[1].paint.path
    d.handleScroll(-1,200,910); c.draw(); eq(banners(c)[1].paint.path,c.require("config.StageConfig").getBattleBackground(201),"chapter滚轮一章")
    check(textAt(c,"▲",133,842),"up箭头与统一bounds")
    d.handleInput(133,842); c.draw(); eq(banners(c)[1].paint.path,first,"up箭头点击")
    check(textAt(c,"▼",133,1558),"down箭头y1524+34")
    d.handleInput(133,1558); c.draw(); eq(banners(c)[1].paint.path,c.require("config.StageConfig").getBattleBackground(201),"down箭头点击")
    d.handleScroll(999,200,910); c.draw(); eq(banners(c)[1].paint.path,first,"wheel上界")
    d.handleDragBegin(200,876); d.handleDragMove(200,782); d.handleDragEnd(); d.handleInput(200,782); c.draw()
    eq(banners(c)[1].paint.path,c.require("config.StageConfig").getBattleBackground(201),"chapter顶部边界drag94px")
    eq(c.events[#c.events],"stage_sel_chdown","drag松手误tap被消费，没切tab")
    d.handleScroll(999,200,910); d.handleDragBegin(200,1524); d.handleDragMove(200,1336); d.handleDragEnd(); d.handleInput(200,1336); c.draw()
    eq(banners(c)[1].paint.path,c.require("config.StageConfig").getBattleBackground(301),"chapter下边界drag188px")
    d.handleScroll(999,200,910); d.handleDragBegin(200,875.999); d.handleDragMove(200,710); d.handleDragEnd(); c.draw()
    eq(banners(c)[1].paint.path,first,"CH上边外不捕获drag")
    d.handleDragBegin(200,1524.001); d.handleDragMove(200,1310); d.handleDragEnd(); c.draw()
    eq(banners(c)[1].paint.path,first,"CH下边外不捕获drag")
    local n=#c.events; d.handleInput(200,965); eq(#c.events,n,"章卡gap不点章")
    d.handleInput(200,970); c.draw(); check(textAt(c,"2-1",331,824),"第二章新顶边970点击实际右栏")
    d.handleScroll(-999,200,900); c.draw(); eq(#banners(c),7,"滚到底仍完整7章无越底")
    d.handleScroll(999,200,900); c.draw(); eq(banners(c)[1].paint.path,first,"滚回首章")
    eq(#c.selections,0,"chapter拖滚箭头不跳关"); idle(c,saved)
end
local function resourceGroupCases()
    local c=newContext(); local r=c.require("ui.battle.stage.StageSelectResources")
    local dc,tc,sc=c.require("config.DungeonConfig"),c.require("config.TowerConfig"),c.require("config.StageConfig")
    local saved=copy(c.memory); local gs=r.getGroups()
    local ids={"gold_mine","equipment_vault","black_diamond","babel_tower"}
    local sizes={115,109,115,112}
    eq(#gs,4,"副本恰为四扁平分类，不是68章节加独立tower")
    check(gs==r.getGroups(),"四分类缓存复用")
    local seen={}
    for i,id in ipairs(ids) do
        local g=gs[i]
        eq(g.key,"R:" .. id,"四组key及顺序冻结")
        eq(g.background,PATHS[id],"四组专属背景含tower")
        eq(g.subLabel,"","副本无伪章节副标题"); eq(#g.ids,sizes[i],"分类含全部层")
        if id=="babel_tower" then check(g.isTower==true and g.resourceDungeonId==nil,"塔不是三资源组")
        else eq(g.resourceDungeonId,id,"资源组种类准确"); eq(g.name,dc.DEFINITIONS[id].name,"组名冻结") end
        for f,sid in ipairs(g.ids) do
            check(not seen[sid],"四分类独立ID不重叠"); seen[sid]=true
            eq(sid,(i==4 and 400000 or i*100000)+f,"四组完整顺序ID")
            eq(r.getGroupKey(sid),g.key,"完整层key不按5层切章")
            local e=r.getStageEntry(sid)
            eq(e.displayChapter,1,"分类entry第1章"); eq(e.stage,f,"分类entry完整1-N")
            if i==4 then
                check(r.isTowerStage(sid) and r.isTowerStage(tostring(sid)),"塔数字/字符串身份")
                eq(e.monsterLevel,tc.getFloor(f).monsterLevel,"塔预览等级来自真实TowerConfig")
                check(e.tower==true and #e.monsters==0 and e.bossId==0,"随机塔预览不编固定怪牌")
                eq(e.name,"通天塔 1-" .. f,"塔完整层名")
                eq(dc.decodeStageId(sid),nil,"塔伪ID不能解码为资源关")
                check(not sc.isResourceStage(sid),"塔不是资源stage")
                check(sc.getStage(sid)==nil,"塔伪ID不进入真实主线链")
            else check(e==dc.getStage(sid),"资源entry真实配置对象") end
        end
    end
    for _,sid in ipairs({400000,400113,400001.5,"invalid"}) do check(not r.isTowerStage(sid),"塔ID越界拒绝") end
    for _,f in ipairs({-1,0,1,53,112,999}) do
        eq(r.getCurrentTowerStageId({babel_tower={floor=f}}),400000+math.max(1,math.min(112,f)),"塔UI当前层上下界")
    end
    eq(r.getTowerUnlockStage(),605,"塔门槛冻结DC605，不误用TC305")
    for _,rank in ipairs({604,605,999,34505}) do
        for _,floor in ipairs({1,53,112}) do
            for _,candidate in ipairs({1,floor,math.min(112,floor+1),112}) do
                local ledger={babel_tower={floor=floor}}
                eq(r.isStageUnlocked(400000+candidate,{maxStageId=rank},ledger),rank>=605 and candidate<=floor,"塔独立账本锁规则")
            end
        end
    end
    idle(c,saved)
end
local function imageCases()
    local c=newContext(); local d=c.prepareDialog(); local saved=copy(c.memory)
    local resources=c.require("ui.battle.stage.StageSelectResources")
    local gs=resources.getGroups(); eq(#gs,4,"资源与塔恰4分类")
    for _,id in ipairs({"gold_mine","equipment_vault","black_diamond","babel_tower"}) do
        d.close(); d.openDungeon(1,id); c.draw(); local bs=banners(c)
        eq(#bs,4,"任意分类全部四图同屏，无独立塔卡")
        for i,g in ipairs(gs) do
            local v=bs[i]
            eq(v.paint.path,g.background,"真实四preview顺序")
            eq(v.shape.y,876+(i-1)*94,"四分类CH_Y0/step含塔1158")
            near(v.paint.w/v.paint.h,1896/720,"真实preview cover保持比例")
            check(v.paint.w>=190 and v.paint.h>=84,"cover铺满卡片")
        end
        check(not textAt(c,"▲",133,842) and not textAt(c,"▼",133,1558),"四分类无左列滚动箭头")
        local loads=copy(c.loads); c.draw(); check(same(c.loads,loads),"重复draw命中缓存")
    end
    for _,p in pairs(PATHS) do eq(c.loads[p],1,"4路径全缓存恰一次") end
    for _,path in pairs(PATHS) do
        for _,response in ipairs({0,-1}) do
            local z=newContext(); z.imageResult[path]=response; local zd=z.prepareDialog()
            zd.openDungeon(1,"gold_mine"); z.draw()
            local found=false; for _,v in ipairs(banners(z)) do if v.paint.path==path then found=true; eq(v.paint.handle,response,"实际0句柄") end end
            eq(found,response==0,"0合法绘制/-1底色fallback " .. path)
            local n=z.loads[path]; zd.draw(z.vg); eq(z.loads[path],n,"0缓存或-1失败限频")
            if response==-1 then z.imageResult[path]=0; z.clock.elapsedTime=z.clock.elapsedTime+3; zd.draw(z.vg)
                eq(z.loads[path],n+1,"-1恢复2秒重试一次") end
            zd.init(z.vg); if response==0 then check(z.deleted[0],"重新init释放句柄0") end
        end
        local z=newContext(); z.badSize[path]=true; local zd=z.prepareDialog()
        zd.openDungeon(1,"gold_mine"); z.draw()
        local found=false; for _,v in ipairs(banners(z)) do if v.paint.path==path then found=true end end
        check(not found,"零尺寸图片使用底色fallback不除零")
    end
    idle(c,saved)
end
local function selectionCases()
    local c=newContext(); local d=c.prepareDialog(); local dc=c.require("config.DungeonConfig"); local saved=copy(c.memory)
    for _,team in ipairs({1,2,3}) do
        for _,id in ipairs(dc.RESOURCE_IDS) do
            c.teams={101,201,301}; local before=copy(c.teams)
            d.close(); d.openDungeon(team,id); c.draw(); d.handleInput(340,820)
            local s=c.selections[#c.selections]; eq(s.team,team,"选关准确保留队1/2/3"); eq(s.id,dc.getStageId(id,1),"实际1-1资源id")
            check(not d.isOpen(),"成功选择关闭Dialog")
            for t=1,3 do if t~=team then eq(c.teams[t],before[t],"其他两队位置不变") end end
            idle(c,saved)
            d.open(team); c.draw(); local n=#c.selections; d.handleInput(340,820)
            eq(#c.selections,n,"当前关不重复路由"); check(d.isOpen(),"当前关保留Dialog")
            d.handleInput(340,998); eq(#c.selections,n,"锁定1-2资源守卫不调用业务"); check(d.isOpen(),"锁关不关闭")
            idle(c,saved)
        end
        c.teams={101,201,301}; d.close(); d.openDungeon(team,"gold_mine"); c.draw(); d.handleInput(200,1190); c.draw()
        check(rowLabel(c,1)~=nil,"第四分类点击打开真实塔层列表")
        d.handleInput(340,820)
        local t=c.towerSelections[#c.towerSelections]; eq(t.id,"babel_tower","tower分类行回调"); eq(t.team,team,"tower队号保持")
        eq(t.floor,1,"真实塔行第三参floor"); check(not d.isOpen(),"塔业务mock接受后关闭")
        idle(c,saved)
    end
    c.accepts=false; c.teams={101,201,301}; d.close(); d.openDungeon(2,"equipment_vault"); c.draw()
    local n=#c.selections; d.handleInput(340,820); eq(#c.selections,n+1,"拒绝一次回调"); check(d.isOpen(),"业务拒绝不关闭")
    local beforeTeams=copy(c.teams); d.handleDragBegin(200,900); d.handleDragMove(200,800); d.handleDragMove(200,900); d.handleDragEnd(); d.handleInput(340,820)
    eq(#c.selections,n+1,"往返drag误tap消费"); check(same(c.teams,beforeTeams),"拒绝/drag不改队")
    for _,id in ipairs(dc.RESOURCE_IDS) do
        c.maxStage=dc.UNLOCK_CONDITIONS[id]-1; c.memory.battle.maxStageId=c.maxStage
        local lockedBefore=copy(c.memory); d.close(); d.openDungeon(3,id); c.draw(); local count=#c.selections
        d.handleInput(340,820); eq(#c.selections,count,"主线门槛不足资源锁guard " .. id); idle(c,lockedBefore)
    end
    c.maxStage=604; c.memory.battle.maxStageId=604; local towerBefore=copy(c.memory)
    d.close(); d.openDungeon(1,"babel_tower"); c.draw(); local count=#c.towerSelections; d.handleInput(340,820)
    eq(#c.towerSelections,count,"tower605锁guard不调用"); idle(c,towerBefore)
    c.maxStage=101; c.memory.battle.maxStageId=101; c.teams={101,201,301}; d.close(); d.open(1)
    n=#c.selections; d.handleInput(340,998); eq(#c.selections,n,"主线锁guard保持")
    check(d.isOpen(),"主线锁守卫不关闭")
end
local function towerDialogCases()
    local c=newContext(); local d=c.prepareDialog(); local tc=c.require("config.TowerConfig")
    local teams=copy(c.teams); c.accepts=false
    -- 112层都通过真实Dialog.openDungeon/reveal/draw/handleInput，不用mock Dialog或纯坐标副本。
    for f=1,112 do
        local team=(f-1)%3+1
        c.memory.dungeon.babel_tower.floor=f
        local saved=copy(c.memory)
        d.close(); d.openDungeon(team,"babel_tower"); c.draw(); currentRow(c,f)
        local _,_,top=visibleRow(c,f)
        check(textAt(c,"怪物 Lv." .. tc.getFloor(f).monsterLevel,673,top+36),"真实塔行显示实际等级")
        local rule=textAt(c,"每层10波，敌人随机生成",673,top+82)
        check(rule and rule.clip and rule.clip.x==455 and rule.clip.w==436,"真实随机塔规则及敌人栏裁剪")
        check(textAt(c,"三队攻坚，共同推进",673,top+128),"真实塔三队规则")
        local cards=0; for _,v in ipairs(c.calls) do if v.kind=="card" then cards=cards+1 end end
        eq(cards,0,"塔行不绘制固定敌人卡牌")
        local n=#c.towerSelections; local x,y=visibleRow(c,f); d.handleInput(x,y)
        eq(#c.towerSelections,n+1,"真实塔第1到112层分别选择一次")
        local s=c.towerSelections[#c.towerSelections]
        eq(s.id,"babel_tower","塔回调种类"); eq(s.team,team,"塔保留调用队号"); eq(s.floor,f,"塔第三参精确层号")
        check(d.isOpen(),"塔业务mock拒绝保留弹窗")
        if f<112 then
            d.handleScroll(-1,340,900); c.draw(); x,y=visibleRow(c,f+1)
            local label=rowLabel(c,f+1)
            check(textAt(c,"未解锁",331,label.y+100),"下一塔层真实未解锁状态")
            d.handleInput(x,y); eq(#c.towerSelections,n+1,"下一塔层锁定不调用业务mock")
        end
        idle(c,saved); check(same(c.teams,teams),"塔伪ID不写任一主线队伍位置")
        towerCoverage=towerCoverage+1
    end
    eq(towerCoverage,112,"112塔层真实Dialog覆盖一次")
    eq(c.randomCalls,0,"塔预览不生成随机怪/rollBuff")
    c.maxStage=604; c.memory.battle.maxStageId=604; c.memory.dungeon.babel_tower.floor=112
    local saved=copy(c.memory); d.close(); d.openDungeon(3,"babel_tower"); c.draw()
    local n=#c.towerSelections; local x,y=visibleRow(c,112); d.handleInput(x,y)
    eq(#c.towerSelections,n,"605门槛不足即使塔112也不调用"); idle(c,saved)
end
local function continuousRowCases()
    local c=newContext(); local d=c.prepareDialog(); local dc=c.require("config.DungeonConfig")
    c.accepts=false
    for i,id in ipairs(dc.RESOURCE_IDS) do
        local max=dc.MAX_FLOOR[id]
        c.memory.dungeon[id]={floor=max,cleared={[tostring(max)]=true},sweepsToday=1}
        c.teams={101,201,301}; c.teams[i]=dc.getStageId(id,60)
        local saved=copy(c.memory); d.close(); d.open(i); c.draw(); currentRow(c,60)
        local n=#c.selections; local x,y=visibleRow(c,60); d.handleInput(x,y)
        eq(#c.selections,n,"资源60当前关不重复路由")
        d.handleScroll(-999,340,900); c.draw()
        local label=assert(rowLabel(c,max)); check(label.y-34+168<=1676,"资源尾层完整露出")
        check(rowLabel(c,max+1)==nil,"资源没有越界尾层")
        x,y=visibleRow(c,max); d.handleInput(x,y)
        eq(#c.selections,n+1,"真实资源尾层可选")
        eq(c.selections[#c.selections].id,dc.getStageId(id,max),"尾层正确资源ID")
        eq(c.selections[#c.selections].team,i,"尾层保留队号")
        d.handleScroll(999,340,900); c.draw(); check(textAt(c,"1-1",331,824),"资源纵滚回第1层")
        d.handleScroll(-1,340,900); c.draw(); check(textAt(c,"1-2",331,824),"资源wheel连续一层非切分类")
        idle(c,saved)
    end
    local z=newContext(); local zd=z.prepareDialog(); z.memory.dungeon.babel_tower.floor=112
    z.accepts=false; local saved=copy(z.memory)
    zd.openDungeon(2,"babel_tower"); z.draw(); currentRow(z,112)
    zd.handleScroll(999,340,900); z.draw(); check(textAt(z,"1-1",331,824),"塔右栏上界")
    zd.handleScroll(-1,340,900); z.draw(); check(textAt(z,"1-2",331,824),"塔右栏wheel连续一层")
    local labels=0
    for _,v in ipairs(z.calls) do if v.kind=="text" and v.x==331 and v.text:match("^1%-%d+$") then
        labels=labels+1; check(v.clip and v.clip.x==315 and v.clip.y==786 and v.clip.w==580 and v.clip.h==890,"每个塔标签使用真实右栏裁剪") end end
    check(labels>=5 and labels<=6,"塔只绘制五行窗口及至多一条部分行")
    local n=#z.towerSelections
    for _,p in ipairs({{340,785.999},{340,1676},{314.999,900},{895.001,900},{340,963},{200,1620}}) do
        zd.handleInput(p[1],p[2]); eq(#z.towerSelections,n,"裁剪外/行gap/已删独立tower card无业务回调")
        check(zd.isOpen(),"面板内空白不关闭")
    end
    zd.handleScroll(999,340,900); zd.handleDragBegin(340,900); zd.handleDragMove(340,722); zd.handleDragEnd(); z.draw()
    check(textAt(z,"1-2",331,824),"塔标签区纵drag178同wheel")
    zd.handleInput(340,820); eq(#z.towerSelections,n,"塔纵drag松手tap被消费")
    zd.handleDragBegin(700,900); zd.handleDragMove(700,722); zd.handleDragEnd(); zd.handleInput(340,820); z.draw()
    check(textAt(z,"1-3",331,824),"塔敌人空白区也能纵滚")
    eq(#z.towerSelections,n,"塔空白区纵drag不误选")
    zd.handleDragBegin(340,900); zd.handleDragMove(340,722); zd.handleDragMove(340,900); zd.handleDragEnd(); zd.handleInput(340,820); z.draw()
    check(textAt(z,"1-3",331,824),"塔往返drag复位"); eq(#z.towerSelections,n,"往返drag仍消费tap")
    zd.handleDragBegin(340,785.999); zd.handleDragMove(340,600); zd.handleDragEnd(); z.draw()
    check(textAt(z,"1-3",331,824),"右栏上边外不捕获drag")
    zd.handleDragBegin(340,1676); zd.handleDragMove(340,1500); zd.handleDragEnd(); z.draw()
    check(textAt(z,"1-3",331,824),"右栏下边界不捕获drag")
    local before=copy(z.calls)
    zd.handleDragBegin(700,900); zd.handleDragMove(500,900); zd.handleDragEnd(); zd.handleInput(340,820); z.draw()
    check(textAt(z,"1-3",331,824),"塔无固定卡牌横拖不串纵轴"); eq(#z.towerSelections,n,"塔横拖消费tap")
    check(#before>0,"横拖前真实draw存在")
    zd.handleInput(200,1002); zd.handleScroll(-2,340,900); z.draw(); check(textAt(z,"1-3",331,824),"装备独立纵scroll")
    zd.handleInput(200,1190); z.draw(); check(textAt(z,"1-3",331,824),"切回塔保留自身纵scroll")
    zd.handleInput(150,782); z.draw(); zd.handleInput(250,782); z.draw()
    check(textAt(z,"1-3",331,824),"主线副本tabs切回塔仍保留纵scroll")
    zd.handleInput(200,1002); z.draw(); check(textAt(z,"1-3",331,824),"装备scroll不被塔/tabs覆盖")
    zd.handleInput(200,1190); zd.handleScroll(-999,340,900); z.draw(); currentRow(z,112)
    local x,y=visibleRow(z,112); zd.handleInput(x,y)
    eq(z.towerSelections[#z.towerSelections].floor,112,"塔纵滚末层命中112")
    check(zd.isOpen(),"末层mock拒绝不关闭")
    zd.handleScroll(999,340,900); z.draw(); check(textAt(z,"1-1",331,824),"塔wheel上下界均安全")
    idle(z,saved)
end
local function safetyCases()
    for _,c in ipairs(contexts) do eq(#c.denied,0,"生产执行无未知require/save/action/IO尝试") end
    local c=newContext()
    for _,probe in ipairs({function() c.require("main") end,function() c.require("boot.StandaloneBoot") end,
        function() c.require("boot.StandaloneSave") end,function() c.env.File("standalone_save.json",FILE_READ) end,
        function() c.env.File("standalone_save.json",FILE_WRITE) end,function() c.require("core.GameState").save() end,
        function() c.require("runtime.ClientDispatcher").action("dungeon.enter",{}) end,
        function() c.env.cache:GetFile("main.lua") end,function() c.env.clientCloud:Set("x",1) end,
        function() c.env.fileSystem:SetCurrentDir(ROOT) end,function() c.env.loadfile("main.lua") end}) do
        local n=#c.denied; check(not pcall(probe),"危险探针确实拒绝"); eq(#c.denied,n+1,"拒绝可审计")
    end
    for name in pairs(SOURCE_FILES) do eq(package.loaded[name],initialLoaded[name],"全局package cache不污染 " .. name) end
    eq(File,nativeFile,"全局File不覆写"); eq(nvgCreateImage,nativeCreateImage,"全局绘图API不覆写")
    eq(#reads,26,"固定26份源码白名单，Tri只取纯背景段")
    print(TAG .. "LIMIT: source/File=read-only allowlist; real GameState/save/File-write/cloud/runtime-action/main/Boot.run denied.")
    print(TAG .. "LIMIT: spawn unit factory, I18n, BF, progress/gotoTeamStage mocked; no full main, live combat, persistence or mobile-input claim.")
end
---@type any
local reviewContext,reviewVG=nil,nil
function HandleResourceDungeonVisualReview()
    local pw,ph,dpr=graphics:GetWidth(),graphics:GetHeight(),graphics:GetDPR()
    local w,h=pw/dpr,ph/dpr
    -- 模式A，真实Dialog的1080x2400设计空间；DPR只在BeginFrame应用，contain不压扁。
    local scale=math.min(w/1080,h/2400)
    nvgBeginFrame(reviewVG,w,h,dpr); nvgSave(reviewVG)
    nvgScale(reviewVG,scale,scale); nvgTranslate(reviewVG,(w/scale-1080)*0.5,(h/scale-2400)*0.5)
    reviewContext.dialog.draw(reviewVG); nvgRestore(reviewVG); nvgEndFrame(reviewVG)
end
function Start()
    assert(ROOT~="","required -tapcode_dir=<absolute1005root>")
    assert(nativeFS:GetCurrentDir():gsub("/+$","")==CWD,"must use isolated cwd " .. CWD)
    if REVIEW~="" then
        assert(({main=true,resources=true,gold=true,equipment=true,diamond=true,tower=true})[REVIEW],"invalid review option")
        reviewVG=assert(nvgCreate(1)); check(nvgCreateFont(reviewVG,"sans","Fonts/MiSans-Regular.ttf")>=0,"真实字体")
        reviewContext=newContext(false,true,reviewVG); local d=reviewContext.prepareDialog()
        if REVIEW=="main" then d.open(1)
        elseif REVIEW=="resources" then d.open(1); d.handleInput(250,782)
        else d.openDungeon(1,({gold="gold_mine",equipment="equipment_vault",diamond="black_diamond",tower="babel_tower"})[REVIEW]) end
        reviewContext.clock.elapsedTime=101
        SubscribeToEvent(reviewVG,"NanoVGRender","HandleResourceDungeonVisualReview")
        print(TAG .. "REVIEW=" .. REVIEW .. ": actual Dialog/DrawUtil/DarkIcon/PNG; only visual screenshot, NOT complete main.")
        return
    end
    for _,test in ipairs({{"all339-floors-frozen-oracle-and-source-safety",configCases},
        {"unlock-and-deterministic-economy-preserved",economyCases},{"actual-Tri-background-pure-resolver",resolverCases},
        {"actual-new-tabs-and-old-tabs-dead",layoutCases},{"shared-chapter-bounds-wheel-arrows-drag",scrollCases},
        {"four-flat-groups-339-resource-112-tower-entries",resourceGroupCases},
        {"four-preview-path-cache-zero-missing",imageCases},{"teams123-lock-guards-no-consumption",selectionCases},
        {"actual-Dialog-all112-tower-floor-routing-reveal-locks",towerDialogCases},
        {"actual-continuous-rows-scroll-clip-gesture-section-memory",continuousRowCases},
        {"allowlist-read-only-no-main-save-action",safetyCases}}) do
        groups=groups+1; local ok,why=pcall(test[2])
        if ok then print(TAG .. "PASS " .. test[1])
        else failures=failures+1; log:Write(LOG_ERROR,TAG .. "FAIL " .. test[1] .. " " .. tostring(why)) end
    end
    print(TAG .. "RESULT " .. (failures==0 and "ALL PASS" or "FAIL") .. " groups=" .. groups .. " checks=" .. checks .. " floors=" .. floorCoverage .. " towerFloors=" .. towerCoverage .. " failures=" .. failures)
    -- 保持validate生命周期，由官方runtime帧预算退出并写隔离报告，不自行engine:Exit。
end
function Stop()
    if reviewVG then nvgDelete(reviewVG); reviewVG=nil end
end
