-- ============================================================================
-- MarketInit - 市场资源加载（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local img = deps.img
    local state = deps.state
    local SHOP_ITEMS = deps.SHOP_ITEMS

    local inited = false
    local vgCache = nil

    local function init(vg)
        if inited then return end
        inited = true
        vgCache = vg
        img.bg       = nvgCreateImage(vg, "image/界面底板/商店/UI_SCBJ.png", 0)
        img.nameBg   = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_MC.png", 0)
        img.lowerBg  = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_1.png", 0)
        img.titleDeco = nvgCreateImage(vg, "image/界面底板/竞技场排行/UI_JJC_BTBJ.png", 0)
        img.gold     = nvgCreateImage(vg, "image/货币道具/UI_icon_JB_X.png", 0)
        img.gem      = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ_X.png", 0)

        img.btnBack  = nvgCreateImage(vg, "image/按钮/UI_AN_FH.png", 0)
        img.tabBg    = nvgCreateImage(vg, "image/按钮/UI_AN_1.png", 0)
        img.slider   = nvgCreateImage(vg, "image/按钮/UI_AN_2.png", 0)

        -- 商品卡片
        for i = 1, 6 do
            img.cardBg[i] = nvgCreateImage(vg, "image/界面底板/商店/UI_SDICONBJ_" .. i .. ".png", 0)
        end
        img.buyBtn = nvgCreateImage(vg, "image/界面底板/商店/UI_SD_AN.png", 0)
        for idx, item in ipairs(SHOP_ITEMS) do
            img.itemIcons[idx] = nvgCreateImage(vg, item.icon, 0)
            img.costIcons[idx] = nvgCreateImage(vg, item.costIcon, 0)
        end

        -- 弹窗
        img.dialogBg = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TY_EJQRK.png", 0)
        img.buyBtnYellow = nvgCreateImage(vg, "image/按钮/UI_AN_HUANG.png", 0)
        img.btnMinus = nvgCreateImage(vg, "image/按钮/UI_AN_JIAN.png", 0)
        img.btnPlus = nvgCreateImage(vg, "image/按钮/UI_AN_JIA.png", 0)
        -- [暗黑化 P1-B5] 原 image/界面底板/商店/UI_SD_AN.png 贴图加载已移除（矢量绘制替代）
        img.diamondIcon = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ_X.png", 0)
        for i = 1, 6 do
        -- [暗黑化 P2-A] 原 ZBBJ 贴图加载已移除（矢量品质框替代）
        end

        img.collectionChestBg = nvgCreateImage(vg, "image/界面底板/商店/UI_SCDC_KC1.png", 0)
        img.collectionDrawBtn = nvgCreateImage(vg, "image/界面底板/商店/UI_SCDC_AN.png", 0)
        img.goldenKey = nvgCreateImage(vg, "image/货币道具/UI_icon_HJYS.png", 0)
        img.diamondBig = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ.png", 0)
        img.confirmArrow = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TJP_JIANTOU.png", 0)

        state.purchased = {}
        state.scrollY = 0
        state.dialogOpen = false
        state.dialogItemIdx = nil

        print("[MarketPage] init OK, items=" .. #SHOP_ITEMS)
    end

    return {
        init = init,
        isInited = function() return inited end,
        getVg = function() return vgCache end,
        setVg = function(vg) vgCache = vg end,
    }
end

return M
