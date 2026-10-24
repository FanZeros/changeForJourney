-- ============================================================================
-- ChurchInit - 教堂资源加载 / 订阅 / 神器子模块注入
-- ============================================================================

local M = {}

function M.bind(deps)
    local img = deps.img
    local state = deps.state
    local ArtifactPanel = deps.ArtifactPanel
    local ArtifactDrawPanel = deps.ArtifactDrawPanel
    local getDispatcher = deps.getDispatcher
    local getClient = deps.getClient
    local getProtocol = deps.getProtocol
    local syncTalentLitNodes = deps.syncTalentLitNodes

    local inited = false
    ---@type any
    local vgCache = nil

    local function refreshTownBadge()
        local okBN, BN = pcall(require, "ui.hud.BottomNav")
        if okBN and BN and BN.refreshTownBadge then BN.refreshTownBadge() end
    end

    local function init(vg)
        if inited then return end
        inited = true
        vgCache = vg
        img.nameBg = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0)
        img.tabBg = nvgCreateImage(vg, "image/按钮/UI_AN_1.png", 0)
        img.iconUp = nvgCreateImage(vg, "image/通用图标/ICON_UP.png", 0)

        -- 古树持有星图上下文；教堂只保留数据同步与入口角标刷新。
        getDispatcher().subscribe("talents", function()
            local okTP, TP = pcall(require, "ui.church.talent.TalentPage")
            if okTP and TP and TP.syncTalentFromStore then TP.syncTalentFromStore()
            else syncTalentLitNodes() end
            refreshTownBadge()
        end)
        getDispatcher().subscribe("player", refreshTownBadge)

        local ctx = {
            state = state,
            getClient = getClient,
            getProtocol = getProtocol,
            isAutoExchangeInputReady = deps.isAutoExchangeInputReady,
        }
        ArtifactPanel.setContext(ctx)
        ArtifactPanel.init(vg)
        ArtifactDrawPanel.setContext(ctx)
        ArtifactDrawPanel.init(vg)
        print("[ChurchPage] init OK: 神器/宝箱，已移除旧选人资源")
    end

    return {
        init = init,
        isInited = function() return inited end,
        getVg = function() return vgCache end,
        setVg = function(vg) vgCache = vg end,
    }
end

return M
