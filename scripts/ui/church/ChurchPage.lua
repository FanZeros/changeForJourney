-- ChurchPage.lua
-- 教堂界面：神器装配 / 神器宝箱；转职与天赋保留各自有效入口。

local GameConfig        = require("config.GameConfig")
local DrawUtil          = require("core.DrawUtil")
local TownPageChrome    = require("ui.town.TownPageChrome")
local HC                = require("config.HeroConfig")
local CharacterPanel    = require("ui.character.panel.CharacterPanel")
local GameState         = require("core.GameState")
local TalentStarMap     = require("ui.church.talent.TalentStarMap")
local TalentPanel       = require("ui.church.talent.ChurchTalentPanel")
local ClassChange       = require("ui.church.ChurchClassChange")
local ArtifactPanel     = require("ui.church.ChurchArtifactPanel")
local ArtifactDrawPanel = require("ui.church.ChurchArtifactDrawPanel")
local AVC               = require("config.AdvancementConfig")
local ChurchDraw        = require("ui.church.ChurchDraw")
local ChurchInput       = require("ui.church.ChurchInput")
local ChurchInit        = require("ui.church.ChurchInit")
local ChurchBadge       = require("ui.church.ChurchBadge")
local ChurchResults     = require("ui.church.ChurchResults")
local ChurchLifecycle   = require("ui.church.ChurchLifecycle")

-- 懒加载业务模块，避免循环依赖。
---@type table|nil
local Client_
---@type table|nil
local Protocol_
---@type table|nil
local ClientDispatcher_
local function getClient()
    if not Client_ then Client_ = require("runtime.GameAction") end
    return Client_
end
local function getProtocol()
    if not Protocol_ then Protocol_ = require("shared.Protocol") end
    return Protocol_
end
local function getDispatcher()
    if not ClientDispatcher_ then ClientDispatcher_ = require("runtime.ClientDispatcher") end
    return ClientDispatcher_
end

local ChurchPage = {}
local DESIGN_W = GameConfig.Design.WIDTH
local DESIGN_H = GameConfig.Design.HEIGHT

local CHURCH = {
    NAME_TEXT_CX = 148, NAME_TEXT_CY = 130, NAME_FONT_SIZE = 50,
}
local TAB = {
    BG_CX = 540, BG_CY = 2288, BG_W = 600, BG_H = 112,
    SLIDER_W = 300, SLIDER_H = 112,
    FONT_SIZE = 32,
    ACTIVE_R = 0xD8, ACTIVE_G = 0xC9, ACTIVE_B = 0xA3,
    INACTIVE_R = 255, INACTIVE_G = 255, INACTIVE_B = 255,
    ANIM_DUR = 0.35,
}
local TAB_ITEMS = {
    { name = "神器", cx = 390, cy = 2288, textX = 390, textY = 2284 },
    { name = "宝箱", cx = 690, cy = 2288, textX = 690, textY = 2284 },
}
local TAB_KEYS = { "shenqi", "baoxiang" }
local TAB_MAP = { shenqi = 1, baoxiang = 2 }
local ANIM = {
    OPEN_DUR = 0.45, CLOSE_DUR = 0.38,
    UPPER_SLIDE_IN = 1200, UPPER_SLIDE_OUT = 2500,
    LOWER_SLIDE_DIST = 1600,
}

---@type fun()|nil
local onCloseCallback_ = nil
---@type fun()|nil
local onOpenCallback_ = nil
local state = {
    open = false, closing = false, openTime = 0, closeTime = 0,
    tab = "shenqi", tabFrom = "shenqi", tabSwitchTime = 0,
    floatText = nil, floatTextX = 0, floatTextY = 0, floatTextTime = 0,
}
local img = { nameBg = -1, tabBg = -1, iconUp = -1 }
local easeOutCubic = TownPageChrome.easeOutCubic
local easeInCubic = TownPageChrome.easeInCubic
local easeInOutCubic = TownPageChrome.easeInOutCubic

---@type table|nil
local _badge
local function bindChurchBadge()
    _badge = ChurchBadge.bind({
        HC = HC, ClassChange = ClassChange, CharacterPanel = CharacterPanel,
        GameState = GameState, AVC = AVC, ArtifactPanel = ArtifactPanel,
        getDispatcher = getDispatcher,
    })
end

--- 检查指定英雄是否有可用转职（右侧角色入口角标）。
---@param heroId number
---@return boolean
function ChurchPage.hasAdvanceForHero(heroId)
    if not _badge then bindChurchBadge() end
    return _badge.hasAdvanceForHero(heroId)
end

---@return boolean
function ChurchPage.hasAnyAdvance()
    if not _badge then bindChurchBadge() end
    return _badge.hasAnyAdvance()
end

---@return boolean
function ChurchPage.hasAnyUnusedTalent()
    if not _badge then bindChurchBadge() end
    return _badge.hasAnyUnusedTalent()
end

---@return boolean
function ChurchPage.hasAnyChurchBadge()
    if not _badge then bindChurchBadge() end
    return _badge.hasAnyChurchBadge()
end

---@return boolean show, string|nil style
function ChurchPage.getChurchBadgeInfo()
    if not _badge then bindChurchBadge() end
    return _badge.getChurchBadgeInfo()
end

--- 同步存档天赋到星图与 HeroConfig，保留古树未加载时的兜底。
local function syncTalentLitNodes()
    local talentsData = getDispatcher().get("talents")
    if not talentsData or not talentsData.litNodes then return end
    TalentStarMap.resetLit()
    for _, nodeId in ipairs(talentsData.litNodes) do
        TalentStarMap.setNodeLit(nodeId, true)
    end
    HC.setDefaultLitNodes(talentsData.litNodes)
end

function ChurchPage.syncTalentFromStore()
    local ok, TP = pcall(require, "ui.church.talent.TalentPage")
    if ok and TP and TP.syncTalentFromStore then
        TP.syncTalentFromStore()
        return
    end
    syncTalentLitNodes()
end

---@type table|nil
local _churchInit
local function bindChurchInit()
    _churchInit = ChurchInit.bind({
        img = img, state = state,
        ArtifactPanel = ArtifactPanel, ArtifactDrawPanel = ArtifactDrawPanel,
        isAutoExchangeInputReady = function()
            return state.open and not state.closing
                and time.elapsedTime - state.openTime >= ANIM.OPEN_DUR
                and (state.tabFrom == state.tab or time.elapsedTime - state.tabSwitchTime >= TAB.ANIM_DUR)
        end,
        getDispatcher = getDispatcher, getClient = getClient, getProtocol = getProtocol,
        syncTalentLitNodes = syncTalentLitNodes,
    })
end

function ChurchPage.init(vg)
    if not _churchInit then bindChurchInit() end
    return _churchInit.init(vg)
end

---@type table|nil
local _life
local function bindChurchLifecycle()
    _life = ChurchLifecycle.bind({
        state = state, ANIM = ANIM,
        easeOutCubic = easeOutCubic, easeInCubic = easeInCubic,
        ArtifactPanel = ArtifactPanel, ArtifactDrawPanel = ArtifactDrawPanel,
        ensureInit = function()
            if not _churchInit then bindChurchInit() end
            if not _churchInit.isInited() and _churchInit.getVg() then
                ChurchPage.init(_churchInit.getVg())
            end
            return _churchInit.isInited()
        end,
        getOnCloseCallback = function() return onCloseCallback_ end,
        setOnCloseCallback = function(fn) onCloseCallback_ = fn end,
        getOnOpenCallback = function() return onOpenCallback_ end,
        setOnOpenCallback = function(fn) onOpenCallback_ = fn end,
    })
end

function ChurchPage.open()
    if not _life then bindChurchLifecycle() end
    return _life.open()
end

function ChurchPage.close()
    ArtifactDrawPanel.closeAnimation()
    ArtifactPanel.cancelPointer()
    require("ui.character.hero.ArtifactDetailPanel").closeImmediate()
    if not _life then bindChurchLifecycle() end
    require("systems.StoryPlayer").onPlace("church", "leave")
    return _life.close()
end

function ChurchPage.setOnCloseCallback(fn)
    if not _life then bindChurchLifecycle() end
    return _life.setOnCloseCallback(fn)
end

function ChurchPage.setOnOpenCallback(fn)
    if not _life then bindChurchLifecycle() end
    return _life.setOnOpenCallback(fn)
end

---@return boolean
function ChurchPage.isOpen()
    if not _life then bindChurchLifecycle() end
    return _life.isOpen()
end

function ChurchPage.forceClose()
    ArtifactDrawPanel.closeAnimation()
    ArtifactPanel.cancelPointer()
    require("ui.character.hero.ArtifactDetailPanel").closeImmediate()
    if not _life then bindChurchLifecycle() end
    return _life.forceClose()
end

function ChurchPage.getAnimProgress()
    if not _life then bindChurchLifecycle() end
    return _life.getAnimProgress()
end

---@type table|nil
local _input
local function bindInput()
    _input = ChurchInput.bind({
        ArtifactPanel = ArtifactPanel, ArtifactDrawPanel = ArtifactDrawPanel,
        TAB_ITEMS = TAB_ITEMS, TAB_KEYS = TAB_KEYS, TAB = TAB,
        forceClose = ChurchPage.forceClose, closePage = ChurchPage.close,
        state = state,
    })
end

function ChurchPage.handleInput(dx, dy)
    if not _input then bindInput() end
    return _input.handleInput(dx, dy)
end

function ChurchPage.handleDragBegin(dx, dy)
    if not _input then bindInput() end
    return _input.handleDragBegin(dx, dy)
end

function ChurchPage.handleDragMove(dx, dy)
    if not _input then bindInput() end
    return _input.handleDragMove(dx, dy)
end

function ChurchPage.handleDragEnd(dx, dy)
    if not _input then bindInput() end
    return _input.handleDragEnd(dx, dy)
end

function ChurchPage.isArtifactInputActive()
    return state.open and not state.closing and not ArtifactDrawPanel.isAnimationPlaying() and state.tab == "shenqi"
        and (state.tabFrom == state.tab or time.elapsedTime - state.tabSwitchTime >= TAB.ANIM_DUR)
        and ChurchPage.getAnimProgress() >= 1
        and DrawUtil.seamSlideX(-1, state.openTime, state.closeTime,
            ANIM.OPEN_DUR, ANIM.CLOSE_DUR, 1080) == 0
end

function ChurchPage.handleHover(dx, dy)
    if ChurchPage.isArtifactInputActive() then ArtifactPanel.handleHover(dx, dy)
    else ArtifactPanel.handleHover(-1, -1) end
end

function ChurchPage.handleScroll(wheel, msx, msy)
    if not _input then bindInput() end
    return _input.handleScroll(wheel, msx, msy)
end

---@type table|nil
local _pageDraw
local function bindPageDraw()
    _pageDraw = ChurchDraw.bind({
        ANIM = ANIM, CHURCH = CHURCH, DESIGN_H = DESIGN_H, DESIGN_W = DESIGN_W,
        TAB = TAB, TAB_ITEMS = TAB_ITEMS, TAB_KEYS = TAB_KEYS, TAB_MAP = TAB_MAP,
        TownPageChrome = TownPageChrome,
        drawImageCentered = DrawUtil.drawImageCentered, drawTextStroke = DrawUtil.drawTextStroke,
        easeInCubic = easeInCubic, easeInOutCubic = easeInOutCubic, easeOutCubic = easeOutCubic,
        img = img, state = state,
        getOnCloseCallback = function() return onCloseCallback_ end,
        setOnCloseCallback = function(v) onCloseCallback_ = v end,
        getOnOpenCallback = function() return onOpenCallback_ end,
        setOnOpenCallback = function(v) onOpenCallback_ = v end,
    })
end

local function drawPageImpl(vg)
    if not _pageDraw then bindPageDraw() end
    return _pageDraw.drawPageImpl(vg)
end

---@type table|nil
local _results
local function bindChurchResults()
    _results = ChurchResults.bind({
        state = state, getProtocol = getProtocol,
        ArtifactPanel = ArtifactPanel, ArtifactDrawPanel = ArtifactDrawPanel,
        CharacterPanel = CharacterPanel,
    })
end

--- 闭页仍处理转职回执与未完成神器请求的收尾。
function ChurchPage.onActionResult(data)
    if not _results then bindChurchResults() end
    return _results.onActionResult(data)
end

function ChurchPage.preloadSpine(vg)
    local ok, TP = pcall(require, "ui.church.talent.TalentPage")
    if ok and TP and TP.preloadSpine then TP.preloadSpine(vg)
    else TalentPanel.preloadSpine(vg) end
end

function ChurchPage.getSeamAnim()
    return state.openTime, state.closeTime, ANIM.OPEN_DUR, ANIM.CLOSE_DUR
end

function ChurchPage.update(dt)
    ArtifactDrawPanel.updateAnimation(dt)
end

function ChurchPage.draw(vg)
    local ot, ct, od, cd = ChurchPage.getSeamAnim()
    local ox = DrawUtil.seamSlideX(-1, ot, ct, od, cd, 1080)
    if ox ~= 0 then
        nvgSave(vg)
        nvgTranslate(vg, ox, 0)
    end
    drawPageImpl(vg)
    if ox ~= 0 then nvgRestore(vg) end
end

return ChurchPage
