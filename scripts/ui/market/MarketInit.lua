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
        img.gold     = nvgCreateImage(vg, "image/货币道具/UI_icon_JB_X.png", 0)
        img.gem      = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ_X.png", 0)

        img.btnBack  = nvgCreateImage(vg, "image/按钮/UI_AN_FH.png", 0)
        img.tabBg    = nvgCreateImage(vg, "image/按钮/UI_AN_1.png", 0)
        img.slider   = nvgCreateImage(vg, "image/按钮/UI_AN_2.png", 0)

        -- 商品品质底已改矢量，不再加载 UI_SDICONBJ。
        img.buyBtn = nvgCreateImage(vg, "image/界面底板/商店/UI_SD_AN.png", 0)
        for idx, item in ipairs(SHOP_ITEMS) do
            img.itemIcons[idx] = nvgCreateImage(vg, item.icon, 0)
            img.costIcons[idx] = nvgCreateImage(vg, item.costIcon, 0)
        end

        -- 弹窗
        -- 弹窗背景由 DarkIcon.drawNine 矢量绘制
        img.buyBtnYellow = nvgCreateImage(vg, "image/按钮/UI_AN_HUANG.png", 0)
        img.btnMinus = nvgCreateImage(vg, "image/按钮/UI_AN_JIAN.png", 0)
        img.btnPlus = nvgCreateImage(vg, "image/按钮/UI_AN_JIA.png", 0)
        -- [图标统一 0928] diamondIcon 与 gem 同贴图，复用句柄避免重复加载（无 delete，复用安全）
        img.diamondIcon = img.gem
        for i = 1, 6 do
        end

        -- 典藏（神器宝箱）图片已随页签迁移至 ChurchArtifactDrawPanel

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
