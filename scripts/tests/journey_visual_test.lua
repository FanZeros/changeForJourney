-- 前进状态、三行背景锚点与队伍角标回归；绘制调用用记录器，不依赖 GPU。
local engineRequire = require
local mocks = {}
local loaded = {}
rawset(_G, "require", function(name)
    if mocks[name] then return mocks[name] end
    if loaded[name] then return loaded[name] end
    local module = engineRequire(name)
    loaded[name] = module
    return module
end)

local assertions = 0
local function check(value, label)
    assert(value, label)
    assertions = assertions + 1
    print("[journey_visual] PASS " .. label)
end
local function near(a, b) return math.abs(a - b) < 0.00001 end
local noop = function() end
local combat = setmetatable({
    newState = function() return {} end,
    setCardAnim = noop,
    addFloatingText = function() error("前进不能创建中央浮字") end,
}, { __index = function() return noop end })
mocks["ui.battle.combat.BattleCombat"] = combat
for _, name in ipairs({
    "ui.battle.combat.BattleEffects", "ui.battle.combat.ProjectileSystem",
    "systems.StatusEffectManager", "systems.ThreatManager", "systems.TalentManager",
    "systems.RelicConditionHandler", "systems.ArtifactRuntime", "systems.BattleStats",
}) do
    mocks[name] = setmetatable({ newState = function() return {} end,
        newFxState = function() return {} end, newSemState = function() return {} end,
        newBattleRefs = function() return {} end }, { __index = function() return noop end })
end
mocks["ui.battle.scene.BattleAllyReset"] = { compactFallen = noop }
mocks["systems.BattleTimeout"] = { calcMult = function() return 1 end }
mocks["ui.character.panel.CharacterPanel"] = {
    getTeamSignature = function() return "team" end,
    getDeployedTeam = function() return {} end,
}

local mainStage, mainMax = 101, 101
local cleared = {}
local battle = { maxStageId = 101, clearedStages = {} }
local scene = {
    pumpBattleCards = noop,
    getStageId = function() return mainStage end,
    getMaxStageId = function() return mainMax end,
    getClearedStages = function() return cleared end,
    adoptStageProgress = function(id) mainStage = id end,
    onFirstClear = noop,
    isSpeedButtonVisible = function() return false end,
}
mocks["ui.battle.scene.BattleScene"] = scene
mocks["runtime.ClientDispatcher"] = { get = function() return battle end }
mocks["ui.battle.scene.BattleView"] = { init = noop, draw = noop }
mocks["ui.battle.tri.TerminalRaid"] = {}
mocks["ui.hud.popup.RewardPopup"] = { drawRegion = noop, currentRowTag = function() return nil end }
for _, name in ipairs({ "ui.battle.stage.SweepDialog", "ui.battle.popup.DamageStatsPanel",
    "ui.battle.stage.StageSelectDialog", "ui.battle.popup.TerminalConfirmDialog",
    "ui.story.gate.LetterIntro", "ui.story.gate.IntroCutscene", "ui.story.ScenarioDialogue" }) do
    mocks[name] = { init = noop, update = noop, isOpen = function() return false end,
        isActive = function() return false end }
end
mocks["ui.widget.SoundToggle"] = { initImages = noop }
mocks["ui.character.equip.EquipmentBag"] = { shouldBattleOverlay = function() return false end,
    setOverlayRegion = noop }

local paints, texts, paths = {}, {}, {}
local currentColor = {}
local handle = 0
local imagePaths = {}
local deletedImages = {}
local failImagePath = ""
for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgScissor", "nvgResetScissor",
    "nvgIntersectScissor", "nvgTranslate", "nvgScale", "nvgBeginPath", "nvgRect",
    "nvgRoundedRect", "nvgFill", "nvgStroke", "nvgStrokeWidth", "nvgFontFace",
    "nvgFontSize", "nvgTextAlign", "nvgFillPaint", "nvgGlobalAlpha", "nvgDeleteImage" }) do
    _G[name] = noop
end
nvgCreateImage = function(_, path)
    paths[#paths + 1] = path
    if path == failImagePath then return -1 end
    handle = handle + 1
    imagePaths[handle] = path
    return handle
end
nvgDeleteImage = function(_, image) deletedImages[image] = true end
rawset(_G, "nvgImagePattern", function(_, x, y, w, h, _, image, alpha)
    assert(not deletedImages[image], "不能使用被删除的共享背景句柄")
    local paint = { x = x, y = y, w = w, h = h, image = image, alpha = alpha }
    paints[#paints + 1] = paint
    return nil
end)
rawset(_G, "nvgRGBA", function(r, g, b, a) return { r, g, b, a } end)
nvgFillColor = function(_, color) currentColor = color end
nvgStrokeColor = noop
nvgTextBounds = function(_, _, _, text) return #text * 10 end
nvgText = function(_, x, y, text)
    texts[#texts + 1] = { text = text, x = x, y = y, color = currentColor }
end

local function testMarch()
    local Driver = require("ui.battle.tri.BattleTriDriver")
    local drv = Driver.new(2)
    drv.allies = { { hp = 100 } }
    drv.active = true
    drv:beginMarch()
    check(drv.marchNotice and drv.marchTimer == 2, "前进持续两秒且无中央浮字")
    local zoom, alpha = drv:getMarchBackground()
    check(near(zoom, 1) and near(alpha, 1), "前进起点背景原状")
    drv.marchTimer = 1
    zoom, alpha = drv:getMarchBackground()
    check(near(zoom, 1.06) and near(alpha, 0.75), "前进中点放大6%并淡化25%")
    drv:tick(0.25)
    check(drv.marchNotice and near(drv.marchTimer, 0.75), "前进跨帧提示不消失")
    drv.marchTimer = 0
    zoom, alpha = drv:getMarchBackground()
    check(near(zoom, 1) and near(alpha, 1), "前进终点背景恢复")
    local originalStart = drv.start
    drv.start = function(self, id)
        self.stageId, self.marchTimer, self.marchNotice, self.introTimer = id, 0, false, 0.3
    end
    drv:advanceStage()
    check(drv.stageId == 102 and drv.marchNotice, "切关后提示延续到敌人入场")
    drv:tick(0.1)
    check(drv.marchNotice, "入场未结束仍显示提示")
    drv:tick(0.21)
    check(not drv.marchNotice, "下一战斗开始清除提示")
    drv.start = originalStart
    drv.marchTimer, drv.marchNotice = 1, true
    drv:start(103)
    check(drv.marchTimer == 0 and not drv.marchNotice, "手动切关清理前进状态")
    drv.marchTimer, drv.marchNotice, drv.active = 1, true, true
    drv.allies = {}
    drv:tick(0.1)
    check(drv.marchTimer == 0 and not drv.marchNotice, "前进中清空编队不残留提示")
    drv:start(104)
    drv:advanceStage()
    check(not drv.marchNotice, "下一关为空编队时不重新挂前进提示")
end

local function testPage()
    local Driver = require("ui.battle.tri.BattleTriDriver")
    local newDriver = Driver.new
    local drivers = {}
    Driver.new = function(idx)
        local drv = { teamIdx = idx, allies = {}, enemies = {}, starts = 0,
            stageId = 101, marchTimer = 0, marchNotice = false }
        function drv:start(id) self.stageId = id self.starts = self.starts + 1 end
        function drv:update() end
        function drv:activate() end
        function drv:getMarchBackground() return self.zoom or 1, self.alpha or 1 end
        drivers[idx] = drv
        return drv
    end
    local Page = require("ui.battle.tri.BattleTriPage")
    Page.open()
    paints, paths = {}, {}
    Page.drawL1Underlay({}, 1920, 1080)
    check(imagePaths[paints[2].image]:find("悬魂瀑布", 1, true), "锁定队2使用图10")
    check(imagePaths[paints[3].image]:find("恶灵岔路", 1, true), "锁定队3使用图20")
    local original = paints[1]
    drivers[1].zoom, drivers[1].alpha = 1.06, 0.75
    paints = {}
    Page.drawL1Underlay({}, 1920, 1080)
    local changed = paints[1]
    local ix, iy, iw, ih = Page.getInteriorRectFor(1, 1920, 1080)
    local px, py = ix + iw, iy + ih * 0.5
    check(near(changed.x, px + (original.x - px) * 1.06)
        and near(changed.y, py + (original.y - py) * 1.06), "背景以可见行右侧中心缩放")
    check(near(changed.w, original.w * 1.06) and near(changed.alpha, 0.75), "绘制使用实际缩放与透明度")
    drivers[1].marchTimer, drivers[1].marchNotice = 2, true
    drivers[1].onStageCleared(1, 101)
    Page.update(0.1)
    check(drivers[1].stageId == 101 and drivers[1].starts == 1, "主线进度同步不截断两秒前进")
    texts = {}
    Page.draw({}, 1920, 1080)
    local found = false
    for _, text in ipairs(texts) do
        if text.text:find("正在前进中", 1, true) then found = text.y == iy + 55 end
    end
    check(found, "前进提示固定于战斗行上方")
    battle.clearedStages = { ["905"] = true, ["1905"] = true }
    drivers[1].marchTimer = 0
    Page.update(0.1)
    check(drivers[2] and drivers[3], "通关进度立即创建新解锁队伍")
    paints = {}
    Page.drawL1Underlay({}, 1920, 1080)
    check(imagePaths[paints[2].image]:find("forest", 1, true), "解锁后切回实际关卡背景")

    local SC = require("config.StageConfig")
    local chapterBg = Page.resolveBackgroundPath(101)
    for diff = 0, 14 do
        check(Page.resolveBackgroundPath((diff * 23 + 1) * 100 + 1) == chapterBg,
            "难度" .. diff .. "的章节背景循环不变")
    end
    for diff = 0, 13 do
        check(Page.resolveBackgroundPath(diff * 1000 + 999) == "image/战斗背景/终焉神殿.png",
            "终焉" .. diff .. "解析为专用背景")
    end
    check(Page.resolveBackgroundPath(2305) == "image/战斗背景/烛龙之巢.png",
        "第23章仍保留烛龙之巢")
    check(Page.resolveBackgroundPath(nil) == chapterBg
        and Page.resolveBackgroundPath("无效") == chapterBg, "无效关卡背景安全回退")

    local starts = { drivers[1].starts, drivers[2].starts, drivers[3].starts }
    local stageIds = { drivers[1].stageId, drivers[2].stageId, drivers[3].stageId }
    local dispatcher = mocks["runtime.ClientDispatcher"]
    local originalGet, originalStage = dispatcher.get, Page.getTeamStageId
    local originalMarch = drivers[1].getMarchBackground
    dispatcher.get = function() error("固定塔背景不能读取主线解锁状态") end
    Page.getTeamStageId = function() error("固定塔背景不能读取主线关卡") end
    drivers[1].getMarchBackground = function() error("固定塔背景不能读取主线行进") end
    paints, paths = {}, {}
    Page.drawL1Underlay({}, 1920, 1080, "image/战斗背景/通天塔.png")
    check(#paints == 3 and #paths == 1, "塔三行共用一次加载的专用图")
    for row, paint in ipairs(paints) do
        check(imagePaths[paint.image] == "image/战斗背景/通天塔.png"
            and paint.alpha == 1, "塔行" .. row .. "专用图不受主线动画影响")
        check(drivers[row].starts == starts[row] and drivers[row].stageId == stageIds[row],
            "塔行" .. row .. "绘制不改变主线进度")
    end
    failImagePath = "image/战斗背景/失败测试.png"
    paints, paths = {}, {}
    Page.drawL1Underlay({}, 1920, 1080, failImagePath)
    check(#paints == 0, "塔图失败不偷用主线背景")
    failImagePath = ""
    paints, paths = {}, {}
    Page.drawL1Underlay({}, 1920, 1080, "image/战斗背景/失败测试.png")
    check(#paints == 3 and #paths == 1, "图片失败后仍可恢复加载")
    dispatcher.get, Page.getTeamStageId = originalGet, originalStage
    drivers[1].getMarchBackground = originalMarch

    Page.getTeamStageId = function() return SC.TERMINAL_NORMAL end
    paints, paths = {}, {}
    Page.drawL1Underlay({}, 1920, 1080)
    check(#paths == 1, "三行终焉共用一张专用图")
    for row, paint in ipairs(paints) do
        check(imagePaths[paint.image] == "image/战斗背景/终焉神殿.png",
            "终焉行" .. row .. "实际绘制专用图")
    end
    Page.getTeamStageId = originalStage
    paints, paths = {}, {}
    Page.drawL1Underlay({}, 1920, 1080)
    check(#paths == 0 and imagePaths[paints[1].image] == chapterBg,
        "从终焉和塔返回主线复用有效旧图")
    check(next(deletedImages) == nil, "背景切换不删除其他场景共用句柄")
    Driver.new = newDriver
end

local function testBadges()
    local Frame = require("ui.widget.HeroFrame")
    local colors = { { 90, 170, 255 }, { 110, 220, 140 }, { 192, 132, 252 } }
    local tags = {}
    for i, color in ipairs(colors) do tags[i] = { text = tostring(i), color = color } end
    texts = {}
    Frame.draw({}, { cx = 100, cy = 100, size = 148, heroId = 1, frameOnly = true,
        showTeamTag = true, teamTags = tags })
    check(#texts == 3, "跨队角色分别绘制三个左上队号")
    for i, text in ipairs(texts) do
        local color = colors[i]
        check(text.color[1] == color[1] and text.color[2] == color[2]
            and text.color[3] == color[3], "队" .. i .. "角标使用对应蓝绿紫")
        check(text.y < 100, "队" .. i .. "角标位于头像左上")
    end
    check(Frame.GOLD_HI[1] == 255 and Frame.GOLD_HI[2] == 214, "选中拖拽高亮金色保持不变")
end

function Start()
    local ok, err = pcall(function()
        testMarch()
        testPage()
        testBadges()
    end)
    if ok then
        print("[journey_visual] ALL PASS assertions=" .. assertions)
    else
        print("[journey_visual] FAIL " .. tostring(err))
        log:Write(LOG_ERROR, tostring(err))
    end
    engine:Exit()
end
