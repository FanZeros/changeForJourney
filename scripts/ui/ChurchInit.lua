-- ============================================================================
-- ChurchInit - 教堂资源加载 / 订阅 / 子模块注入（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local img = deps.img
    local state = deps.state
    local ANIM = deps.ANIM
    local easeOutCubic = deps.easeOutCubic
    local easeInCubic = deps.easeInCubic
    local TalentStarMap = deps.TalentStarMap
    local TalentPanel = deps.TalentPanel
    local ClassChange = deps.ClassChange
    local ArtifactPanel = deps.ArtifactPanel
    local getDispatcher = deps.getDispatcher
    local getClient = deps.getClient
    local getProtocol = deps.getProtocol
    local getClassIcon2 = deps.getClassIcon2
    local syncTalentLitNodes = deps.syncTalentLitNodes
    local clearPowerCache = deps.clearPowerCache

    local inited = false
    local vgCache = nil

    local function refreshTownBadge()
        local okBN, BN = pcall(require, "ui.BottomNav")
        if okBN and BN and BN.refreshTownBadge then
            BN.refreshTownBadge()
        end
    end

    local function init(vg)
        if inited then return end
        inited = true
        vgCache = vg
        img.bg       = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_JTZZBJ.png", 0)
        img.nameBg   = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0)
        img.btnBack  = nvgCreateImage(vg, "image/按钮/UI_AN_FH.png", 0)
        img.tabBg    = nvgCreateImage(vg, "image/按钮/UI_AN_1.png", 0)
        -- [暗黑化 P1-B5] 原 image/按钮/UI_AN_2.png 贴图加载已移除（矢量绘制替代）
        img.plus     = nvgCreateImage(vg, "image/通用图标/UI_ICON_JIA.png", 0)

        -- 转职相关图片
        for i = 1, 6 do
            img.classBg[i] = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_ZZBJ_" .. i .. ".png", 0)
        end
        img.titleBg    = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_ZBT1.png", 0)
        img.branchLine  = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_ZZXT_1Z.png", 0)
        img.branchLine2 = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_ZZXT_2Z.png", 0)
        -- 职业图标（基础/一转/二转）按需加载，避免启动同步解码 42 张

        -- 角色列表背景（与角色面板相同）
        img.listBg = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSJM_0.png", 0)
        -- 职业小图标（角色卡牌左上角）
        for i = 1, 6 do
            img.classIcons[i] = nvgCreateImage(vg, "image/通用图标/ICON_ZY_" .. i .. ".png", 0)
        end

        -- 卡片详情图片（与角色面板相同）
        img.expBarBg   = nvgCreateImage(vg, "image/进度条/UI_JSMB_JYT1.png", 0)
        img.expBarFill = nvgCreateImage(vg, "image/进度条/UI_JSMB_JYT2.png", 0)
        img.deployed   = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSJM_CZZ.png", 0)

        -- 转职确认弹窗图片
        for i = 1, 6 do
            img.confirmBg[i] = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_ZYTS_" .. i .. ".png", 0)
        end
        -- [暗黑化 P1-B5] 原 image/按钮/UI_AN_LV.png 贴图加载已移除（矢量绘制替代）
        -- [暗黑化 P1-B5] 原 image/按钮/UI_AN_FANG.png 贴图加载已移除（矢量绘制替代）
        -- [暗黑化 P1-B5] 原 image/界面底板/通用面板/UI_TY_EJQRK.png 贴图加载已移除（矢量绘制替代）
        img.goldCoin    = nvgCreateImage(vg, "image/货币道具/UI_icon_JB.png", 0)
        img.iconUp     = nvgCreateImage(vg, "image/通用图标/ICON_UP.png", 0)
        img.resDiamond = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ_X.png", 0)

        -- 天赋面板图片
        img.tfBg          = nvgCreateImage(vg, "image/界面底板/终焉古树/UI_GS_TFBJ_dark.png", 0)
        img.tfPointGlow   = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_JTTF_HG.png", 0)
        img.tfSliderThumb = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_JTTF_HK.png", 0)

        -- 天赋详情面板背景（5种颜色）
        local colorFileMap = { ["红"]="HONG", ["绿"]="LV", ["黄"]="HUANG", ["蓝"]="LAN", ["紫"]="ZI" }
        for colorName, fileSuffix in pairs(colorFileMap) do
            img.tfDetailBg[colorName] = nvgCreateImage(vg, "image/界面底板/教堂转职/UI_TFWBK_" .. fileSuffix .. ".png", 0)
        end

        -- [暗黑化 P1-B5] 原 image/按钮/UI_AN_HONG.png 贴图加载已移除（矢量绘制替代）
        img.tfInfoIcon = nvgCreateImage(vg, "image/货币道具/UI_icon_TS.png", 0)

        -- 天赋星图由 TalentPage.init 负责，教堂不再抢初始化

        -- 订阅天赋数据变更，自动同步星图渲染状态 + 刷新角标
        getDispatcher().subscribe("talents", function()
            local okTP, TP = pcall(require, "ui.TalentPage")
            if okTP and TP and TP.syncTalentFromStore then
                TP.syncTalentFromStore()
            else
                syncTalentLitNodes()
            end
            clearPowerCache()
            refreshTownBadge()
        end)

        -- 订阅玩家数据变更（升级 → 天赋点上限增加 → 刷新角标）
        getDispatcher().subscribe("player", function()
            clearPowerCache()
            refreshTownBadge()
        end)

        -- 订阅英雄数据变更（等级/共鸣变化 → 刷新战力缓存）
        getDispatcher().subscribe("heroes", function()
            clearPowerCache()
        end)

        -- 订阅装备变更（穿戴/卸下影响战力预览）
        getDispatcher().subscribe("equipment", function()
            clearPowerCache()
        end)

        -- 构造共享上下文，注入到子模块
        local ctx = {
            state            = state,
            img              = img,
            easeOutCubic     = easeOutCubic,
            easeInCubic      = easeInCubic,
            POPUP_ANIM_DUR   = ANIM.POPUP_DUR,
            POPUP_SCALE_FROM = ANIM.POPUP_SCALE_FROM,
            getClient        = getClient,
            getProtocol      = getProtocol,
            getDispatcher    = getDispatcher,
        }
        -- 天赋面板上下文由 TalentPage 独占注入，教堂不再 setContext
        ctx.getClassIcon2 = getClassIcon2
        ClassChange.setContext(ctx)
        ArtifactPanel.setContext(ctx)
        ArtifactPanel.init(vg)

        print("[ChurchPage] init OK")
    end

    return {
        init = init,
        isInited = function() return inited end,
        getVg = function() return vgCache end,
        setVg = function(vg) vgCache = vg end,
    }
end

return M
