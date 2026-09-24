-- ============================================================================
-- TalentPage - 终焉古树：独立天赋星图页（从教堂分离）
-- 设计坐标 1080×2400；星图视口 1080×1080 居中；世界约 1.5 竖屏、默认 zoom=1
-- ============================================================================

local GameConfig     = require("config.GameConfig")
local DrawUtil       = require("core.DrawUtil")
local TownPageChrome = require("ui.town.TownPageChrome")
local TalentStarMap  = require("ui.church.TalentStarMap")
local TalentPanel    = require("ui.church.ChurchTalentPanel")
local HC             = require("config.HeroConfig")
local I18n           = require("core.I18n")

local DESIGN_W = GameConfig.Design.WIDTH
local DESIGN_H = GameConfig.Design.HEIGHT

local TalentPage = {}

-- 横屏古树页相对左栏的宽度倍率。
-- 1.8 = 在原先 1.5 基础上再加宽约 20%，多出的部分从左侧盖住战斗区。
TalentPage.HORIZON_WIDTH_SCALE = 1.8

local ANIM = {
    OPEN_DUR  = 0.45,
    CLOSE_DUR = 0.38,
}

local easeOutCubic = TownPageChrome.easeOutCubic
local easeInCubic  = TownPageChrome.easeInCubic

local Client_
local Protocol_
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

---@class TalentPageState
local state = {
    open       = false,
    closing    = false,
    openTime   = 0,
    closeTime  = 0,
    tab        = "tianfu", -- ChurchTalentPanel 仍按此字段分流
    tabFrom    = "tianfu",
    tabSwitchTime = 0,

    tfZoomSliderValue   = TalentStarMap.getDefaultSliderValue(),
    tfSliderDragging    = false,
    tfMapDragging       = false,
    tfLastDragX         = 0,
    tfLastDragY         = 0,
    tfLastDragTime      = 0,
    tfDragVelocityX     = 0,
    tfDragVelocityY     = 0,

    tfDetailOpen        = false,
    tfDetailNodeId      = nil,
    tfDetailAnimT       = 0,
    tfDetailClosing     = false,

    tfOverviewOpen      = false,
    tfOverviewClosing   = false,
    tfOverviewAnimT     = 0,
    tfOverviewScrollY   = 0,
    tfOverviewDragging  = false,
    tfOverviewLastDragY = 0,
    tfOverviewLines     = nil,

    _lastDrawTime       = 0,
}

local img = {
    nameBg        = -1,
    tfBg          = -1,
    tfPointGlow   = -1,
    tfSliderThumb = -1,
    tfDetailBg    = {},
    tfInfoIcon    = -1,
}

local inited = false
local vgCache = nil
local onCloseCallback_ = nil
local onOpenCallback_ = nil

local function syncTalentLitNodes()
    local d = getDispatcher()
    local talentsData = d.get("talents")
    if not talentsData or not talentsData.litNodes then return end
    TalentStarMap.resetLit()
    for _, nodeId in ipairs(talentsData.litNodes) do
        TalentStarMap.setNodeLit(nodeId, true)
    end
    HC.setDefaultLitNodes(talentsData.litNodes)
end

local function refreshTownBadge()
    local okBN, BN = pcall(require, "ui.hud.BottomNav")
    if okBN and BN and BN.refreshTownBadge then
        BN.refreshTownBadge()
    end
end

function TalentPage.init(vg)
    if inited then return end
    inited = true
    vgCache = vg

    img.nameBg        = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0)
    img.tfBg          = nvgCreateImage(vg, "image/界面底板/终焉古树/UI_GS_TFBJ_dark.png", 0)
    img.tfPointGlow   = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_JTTF_HG.png", 0)
    img.tfSliderThumb = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_JTTF_HK.png", 0)
    local colorFileMap = { ["红"] = "HONG", ["绿"] = "LV", ["黄"] = "HUANG", ["蓝"] = "LAN", ["紫"] = "ZI" }
    for colorName, fileSuffix in pairs(colorFileMap) do
        img.tfDetailBg[colorName] = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_TFWBK_" .. fileSuffix .. ".png", 0)
    end
    img.tfInfoIcon = nvgCreateImage(vg, "image/货币道具/UI_icon_TS.png", 0)

    TalentStarMap.init(vg)
    TalentPanel.setContext({
        state            = state,
        img              = img,
        easeOutCubic     = easeOutCubic,
        easeInCubic      = easeInCubic,
        POPUP_ANIM_DUR   = 0.22,
        POPUP_SCALE_FROM = 0.85,
        getClient        = getClient,
        getProtocol      = getProtocol,
        getDispatcher    = getDispatcher,
    })

    getDispatcher().subscribe("talents", function()
        syncTalentLitNodes()
        refreshTownBadge()
    end)
    getDispatcher().subscribe("player", function()
        refreshTownBadge()
    end)

    print("[TalentPage] init OK")
end

local function ensureInit()
    if not inited and vgCache then
        TalentPage.init(vgCache)
    end
    return inited
end

function TalentPage.open()
    if not ensureInit() then
        print("[TalentPage] open before init, skip")
        return
    end
    -- 古树页独占 ChurchTalentPanel 上下文（教堂不再注入）
    TalentPanel.setContext({
        state            = state,
        img              = img,
        easeOutCubic     = easeOutCubic,
        easeInCubic      = easeInCubic,
        POPUP_ANIM_DUR   = 0.22,
        POPUP_SCALE_FROM = 0.85,
        getClient        = getClient,
        getProtocol      = getProtocol,
        getDispatcher    = getDispatcher,
    })
    do
        local okCP, CP = pcall(require, "ui.church.ChurchPage")
        if okCP and CP and CP.isOpen and CP.isOpen() and CP.forceClose then
            CP.forceClose()
        end
    end
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    require("systems.GameSFX").playUIMove(1)
    state.tab = "tianfu"
    state.tfZoomSliderValue = TalentStarMap.getDefaultSliderValue()
    state.tfSliderDragging = false
    state.tfMapDragging = false
    state.tfLastDragTime = 0
    state.tfDragVelocityX = 0
    state.tfDragVelocityY = 0
    state.tfDetailOpen = false
    state.tfDetailNodeId = nil
    state.tfDetailClosing = false
    state.tfOverviewOpen = false
    state.tfOverviewClosing = false
    TalentStarMap.resetCamera()
    syncTalentLitNodes()
    print("[TalentPage] 打开古树天赋 widthScale=" .. tostring(TalentPage.getHorizonWidthScale()))
end

function TalentPage.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    print("[TalentPage] 关闭古树天赋")
end

function TalentPage.isOpen()
    return state.open
end

function TalentPage.forceClose()
    if not state.open then return end
    state.open = false
    state.closing = false
end

function TalentPage.setOnCloseCallback(fn)
    onCloseCallback_ = fn
end

function TalentPage.setOnOpenCallback(fn)
    onOpenCallback_ = fn
end

function TalentPage.getHorizonWidthScale()
    local scale = TalentPage.HORIZON_WIDTH_SCALE or 1.0
    if scale < 1.0 then scale = 1.0 end
    return scale
end

function TalentPage.applyHorizonLayout()
    TalentPanel.setWidthScale(TalentPage.getHorizonWidthScale())
end

function TalentPage.resetHorizonLayout()
    TalentPanel.setWidthScale(1.0)
end

function TalentPage.getSeamAnim()
    return state.openTime, state.closeTime, ANIM.OPEN_DUR, ANIM.CLOSE_DUR
end

function TalentPage.getSlideDistance()
    return TalentPanel.getPageWidth()
end

function TalentPage.syncTalentFromStore()
    syncTalentLitNodes()
end

function TalentPage.hasAnyUnusedTalent()
    local talentsData = getDispatcher().get("talents")
    local playerData  = getDispatcher().get("player")
    local litCount   = (talentsData and talentsData.litNodes) and #talentsData.litNodes or 1
    local usedPoints = litCount - 1
    local maxPoints  = (playerData and playerData.level) or 1
    return (maxPoints - usedPoints) > 0
end

function TalentPage.preloadSpine(vg)
    TalentPanel.preloadSpine(vg)
end

function TalentPage.handleInput(dx, dy)
    if not state.open then return false end
    if state.closing then
        local closingElapsed = time.elapsedTime - state.closeTime
        if closingElapsed > 1.0 then
            TalentPage.forceClose()
            return false
        end
        return true
    end
    if state.tfDetailOpen then
        return TalentPanel.handleDetailInput(dx, dy)
    end
    if TownPageChrome.hitBack(dx, dy, { cx = 958 + (TalentPanel.getPageWidth() - DESIGN_W) }) then
        TalentPage.close()
        return true
    end
    local consumed = TalentPanel.handleTabInput(dx, dy)
    if consumed then return true end
    return true
end

function TalentPage.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    return TalentPanel.handleDragBegin(dx, dy)
end

function TalentPage.handleDragMove(dx, dy)
    if not state.open or state.closing then return false end
    return TalentPanel.handleDragMove(dx, dy)
end

function TalentPage.handleDragEnd(dx, dy)
    if not state.open or state.closing then return end
    TalentPanel.handleDragEnd(dx, dy)
end

---@param wheel number
---@param msx number|nil
---@param msy number|nil
function TalentPage.handleScroll(wheel, msx, msy)
    if not state.open or state.closing then return end
    if TalentPanel.handleScroll then
        TalentPanel.handleScroll(wheel, msx, msy)
    end
end

local function drawPageImpl(vg)
    if not state.open then return end

    do
        local now = time.elapsedTime
        local lastT = state._lastDrawTime or now
        local frameDt = now - lastT
        state._lastDrawTime = now
        if frameDt > 0 and frameDt < 0.2 then
            TalentStarMap.update(frameDt)
        end
    end

    local rawT, progress
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        rawT = math.min(1.0, elapsed / ANIM.CLOSE_DUR)
        progress = 1 - easeInCubic(rawT)
        if rawT >= 1.0 then
            state.open = false
            state.closing = false
            local cb = onCloseCallback_
            onCloseCallback_ = nil
            if cb then cb() end
            return
        end
    else
        local elapsed = time.elapsedTime - state.openTime
        rawT = math.min(1.0, elapsed / ANIM.OPEN_DUR)
        progress = easeOutCubic(rawT)
        if rawT >= 1.0 and onOpenCallback_ then
            local cb = onOpenCallback_
            onOpenCallback_ = nil
            cb()
        end
    end

    local overlayAlpha = math.floor(180 * progress)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, TalentPanel.getPageWidth(), DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)

    nvgSave(vg)
    nvgGlobalAlpha(vg, progress)

    TalentPanel.drawBg(vg)
    TalentPanel.drawContent(vg)

    local extra = TalentPanel.getPageWidth() - DESIGN_W
    TownPageChrome.drawNamePlate(vg, img.nameBg, I18n.t("ancient_tree"))
    TownPageChrome.drawBack(vg, { cx = 958 + extra })

    TalentPanel.drawDetailPanel(vg)

    nvgRestore(vg)
end

function TalentPage.draw(vg)
    if not state.open and not state.closing then return end
    local ot, ct, od, cd = TalentPage.getSeamAnim()
    local ox = DrawUtil.seamSlideX(-1, ot, ct, od, cd, TalentPage.getSlideDistance())
    if ox ~= 0 then
        nvgSave(vg)
        nvgTranslate(vg, ox, 0)
    end
    drawPageImpl(vg)
    if ox ~= 0 then
        nvgRestore(vg)
    end
end

return TalentPage
