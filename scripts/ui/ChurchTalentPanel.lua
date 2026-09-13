-- ChurchTalentPanel.lua
-- 教堂天赋面板子模块：天赋星图、天赋详情面板、缩放滑块、拖拽处理
-- 从 ChurchPage.lua 拆分而来

---@diagnostic disable: undefined-global

local GameConfig    = require("config.GameConfig")
local DrawUtil      = require("core.DrawUtil")
local TalentStarMap = require("ui.TalentStarMap")
local TalentEffect  = require("systems.TalentEffect")
local BF            = require("systems.ButtonFeedback")
local DarkIcon      = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

-- 天赋系颜色 → 暗黑语义 accent（配合 DarkIcon.drawNine "plain" 样式）
local TF_ACCENT = { ["红"] = "red", ["绿"] = "green", ["黄"] = "gold", ["蓝"] = "blue", ["紫"] = "purple" }

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

local M = {}

-- ======================== 天赋面板布局常量 ========================

local TF = {
    bgCX = 540, bgCY = 1200, bgW = 1080, bgH = 2400,          -- 背景
    glowCX = 540, glowCY = 230, glowW = 723, glowH = 729,     -- 天赋点光晕
    ptCX = 540, ptCY = 202, ptFont = 89, ptStroke = 9,         -- 天赋点数值
    lblCX = 540, lblCY = 286, lblFont = 54,                    -- "天赋点"文字
    infoBtnCX = 980, infoBtnCY = 210, infoBtnW = 80, infoBtnH = 80, -- 效果总览感叹号
    infoIconW = 54, infoIconH = 54,
    rstCX = 200, rstCY = 2122, rstW = 340, rstH = 100,        -- 重置按钮
    rstNsL = 55, rstNsR = 55, rstNsT = 10, rstNsB = 10,
    rstFont = 40,
    slBgCX = 994, slBgCY = 1983, slBgW = 90, slBgH = 368,    -- 缩放滑块背景
    slBgR = 18,                                                 -- 背景圆角
    slTrkW = 10, slTrkH = 312, slTrkR = 5,                    -- 滑块轨道
    slThW = 70, slThH = 30,                                    -- 滑块
}

-- ======================== 天赋详情面板布局常量 ========================

local TFD = {
    -- 面板背景 (九宫格)
    bgCX = 540, bgCY = 1027, bgW = 830, bgH = 930,
    bgNsT = 180, bgNsR = 40, bgNsB = 50, bgNsL = 40,
    -- 天赋名
    nameCX = 540, nameCY = 622, nameFont = 40, nameStroke = 4,
    -- 天赋图标
    iconCX = 540, iconCY = 802, iconW = 166, iconH = 166,
    -- 信息文本背景框
    infoBgCX = 540, infoBgCY = 1143, infoBgW = 730, infoBgH = 312, infoBgR = 14,
    -- 信息文本内边距 & 样式
    infopad = 35, infoFont = 35,
    infoR = 0x72, infoG = 0x58, infoB = 0x50,
    -- 激活按钮
    btnCX = 540, btnCY = 1380, btnW = 410, btnH = 100,
    btnNsT = 10, btnNsR = 55, btnNsB = 10, btnNsL = 55,
    btnFont = 40,
    btnR = 0x1e, btnG = 0x51, btnB = 0x37,
}

-- ======================== 天赋效果总览弹窗 ========================

local TOV = {
    bgCX = 540, bgCY = 1080, bgW = 920, bgH = 1500,
    bgNsT = 180, bgNsR = 40, bgNsB = 50, bgNsL = 40,
    titleCY = 420, titleFont = 48, titleStroke = 5,
    listTop = 500, listH = 1180, listPadX = 80, listW = 760,
    lineH = 46, headerH = 56,
    textFont = 32, headerFont = 36,
    textR = 0x72, textG = 0x58, textB = 0x50,
    headerR = 0x81, headerG = 0x57, headerB = 0x3c,
}

-- ======================== Spine 天赋背景 ========================

local spineTfBg = {
    json    = "image/spine/UI_SPINE_TFBJ.json",
    dataX   = -540,   dataY = -1200,
    dataW   = 1080,   dataH = 2400,
    inst    = nil,
    loaded  = false,
    lastT   = 0,
}

-- ======================== 星图拖拽区域 ========================

local MAP_TOP = 320
local MAP_H   = 1780

-- ======================== 共享状态（由 setContext 注入） ========================

---@type table
local state
local img
local easeOutCubic
local easeInCubic
local POPUP_ANIM_DUR
local POPUP_SCALE_FROM
local getClient
local getProtocol
local getDispatcher

--- 注入共享上下文（由 ChurchPage 调用）
function M.setContext(ctx)
    state          = ctx.state
    img            = ctx.img
    easeOutCubic   = ctx.easeOutCubic
    easeInCubic    = ctx.easeInCubic
    POPUP_ANIM_DUR = ctx.POPUP_ANIM_DUR
    POPUP_SCALE_FROM = ctx.POPUP_SCALE_FROM
    getClient      = ctx.getClient
    getProtocol    = ctx.getProtocol
    getDispatcher  = ctx.getDispatcher
end

-- ======================== 内部函数 ========================

--- 初始化 Spine 天赋背景（懒加载）
local function ensureSpineTfBgLoaded(vg)
    if spineTfBg.loaded and spineTfBg.inst then return true end
    if not vg then return false end

    local inst = nvgSpineCreate(vg)
    if not inst then
        print("[ChurchTalentPanel] nvgSpineCreate(tfBg) failed")
        return false
    end

    if not inst:Load(spineTfBg.json) then
        print("[ChurchTalentPanel] Failed to load Spine: " .. spineTfBg.json)
        return false
    end

    -- atlas 中 pma:true
    inst:SetPremultipliedAlpha(true)
    -- 动画 "1" 循环播放
    inst:SetAnimation(0, "1", true)
    inst:SetSpeed(1.0)

    spineTfBg.inst   = inst
    spineTfBg.loaded = true
    spineTfBg.lastT  = time.elapsedTime
    print("[ChurchTalentPanel] Spine tfBg loaded OK")
    return true
end

--- 判断节点是否为末尾天赋（已点亮子图的叶子：只有 1 个已点亮邻居，即其父节点）
--- 叶子节点可以安全移除而不断开其他已点亮节点的连通性
---@param nodeId number
---@return boolean
local function isTerminalNode(nodeId)
    if nodeId == 0 then return false end  -- 起始点不允许单独重置
    if not TalentStarMap.isNodeLit(nodeId) then return false end
    local node = TalentStarMap.getNode(nodeId)
    if not node or not node.adj then return false end
    local litAdjCount = 0
    for _, adjId in ipairs(node.adj) do
        if TalentStarMap.isNodeLit(adjId) then
            litAdjCount = litAdjCount + 1
        end
    end
    -- 只有 1 个已点亮邻居 → 叶子节点，可安全重置
    return litAdjCount == 1
end

--- 打开天赋详情面板
local function openDetail(nodeId)
    state.tfDetailOpen = true
    state.tfDetailNodeId = nodeId
    state.tfDetailClosing = false
    state.tfDetailAnimT = time.elapsedTime
    print("[ChurchTalentPanel] 打开天赋详情: nodeId=" .. tostring(nodeId))
end

--- 关闭天赋详情面板（带动画）
local function closeDetail()
    if not state.tfDetailOpen then return end
    if state.tfDetailClosing then return end  -- 已在关闭中
    state.tfDetailClosing = true
    state.tfDetailAnimT = time.elapsedTime
    print("[ChurchTalentPanel] 关闭天赋详情（动画）")
end

--- 重建效果总览展示行
local function rebuildOverviewLines()
    local talentsData = getDispatcher().get("talents")
    local litNodes = (talentsData and talentsData.litNodes) or { 0 }
    local overview = TalentEffect.buildOverview(litNodes)
    local lines = {}

    local function pushHeader(text)
        lines[#lines + 1] = { kind = "header", text = text }
    end
    local function pushText(text, muted)
        lines[#lines + 1] = { kind = "text", text = text, muted = muted or false }
    end
    local function pushStat(label, value)
        lines[#lines + 1] = { kind = "stat", label = label, value = value }
    end

    local hasAny = (#overview.stats > 0) or (#overview.classBonuses > 0) or (#overview.specials > 0)
    if not hasAny then
        pushText("暂无已点亮天赋效果", true)
        state.tfOverviewLines = lines
        return
    end

    if #overview.stats > 0 then
        pushHeader("属性加成")
        for _, row in ipairs(overview.stats) do
            pushStat(row.label, row.text)
        end
    end

    if #overview.classBonuses > 0 then
        pushHeader("职业专属")
        for _, row in ipairs(overview.classBonuses) do
            pushStat("[" .. row.className .. "]", row.text)
        end
    end

    if #overview.specials > 0 then
        pushHeader("特殊效果")
        for _, row in ipairs(overview.specials) do
            pushText("· " .. row.name .. "：" .. row.text)
        end
    end

    state.tfOverviewLines = lines
end

local function openOverview()
    rebuildOverviewLines()
    state.tfOverviewOpen = true
    state.tfOverviewClosing = false
    state.tfOverviewAnimT = time.elapsedTime
    state.tfOverviewScrollY = 0
    state.tfOverviewDragging = false
    print("[ChurchTalentPanel] 打开天赋效果总览")
end

local function closeOverview()
    if not state.tfOverviewOpen then return end
    if state.tfOverviewClosing then return end
    state.tfOverviewClosing = true
    state.tfOverviewAnimT = time.elapsedTime
    print("[ChurchTalentPanel] 关闭天赋效果总览（动画）")
end

local function getOverviewContentHeight()
    -- 优先使用渲染时测量的实际高度（包含长文本换行）
    if state.tfOverviewMeasuredH and state.tfOverviewMeasuredH > 0 then
        return state.tfOverviewMeasuredH
    end
    -- fallback: 粗略估算（首帧还没测量时）
    local lines = state.tfOverviewLines or {}
    local h = 0
    for _, line in ipairs(lines) do
        if line.kind == "header" then
            h = h + TOV.headerH + 8
        elseif line.kind == "stat" then
            h = h + TOV.lineH + 6
        else
            -- 特殊效果文本估算每行约3行换行
            h = h + TOV.lineH * 3 + 10
        end
    end
    return h
end

local function clampOverviewScroll()
    local maxScroll = math.max(0, getOverviewContentHeight() - TOV.listH)
    state.tfOverviewScrollY = math.max(0, math.min(state.tfOverviewScrollY, maxScroll))
end

-- ======================== 模块 API ========================

--- 天赋详情面板是否可见
function M.isDetailOpen()
    return state.tfDetailOpen
end

--- 天赋效果总览是否可见
function M.isOverviewOpen()
    return state.tfOverviewOpen
end

--- 绘制天赋背景（铺满全屏，在上半部分之前绘制）
function M.drawBg(vg)
    if not ensureSpineTfBgLoaded(vg) then
        -- fallback: 旧静态背景
        drawImageCentered(vg, img.tfBg, TF.bgCX, TF.bgCY, TF.bgW, TF.bgH, 1.0)
        drawImageCentered(vg, img.tfBorderGlow, TF.bgCX, TF.bgCY, TF.bgW, TF.bgH, 1.0)
        return
    end

    -- 计算 dt
    local now = time.elapsedTime
    local dt  = now - spineTfBg.lastT
    if dt > 0.2 then dt = 0.016 end   -- 防止暂停后大跳
    spineTfBg.lastT = now

    local inst = spineTfBg.inst

    -- 更新动画
    inst:Update(dt)

    -- 缩放：Spine 尺寸 1080×2400 = 设计分辨率，1:1 映射
    -- Spine Y 朝上，屏幕 Y 朝下，翻转 Y
    inst:SetScale(1.0, -1.0)

    -- 定位：骨架数据中心 = (dataX + dataW/2, dataY + dataH/2) = (0, 0)
    -- 屏幕中心 = (540, 1200)
    local dataCenterX = spineTfBg.dataX + spineTfBg.dataW * 0.5  -- 0
    local dataCenterY = spineTfBg.dataY + spineTfBg.dataH * 0.5  -- 0
    local posX = TF.bgCX - dataCenterX * 1.0     -- 540
    local posY = TF.bgCY + dataCenterY * 1.0     -- 1200 (Y翻转所以 +)
    inst:SetPosition(posX, posY)

    -- 渲染
    nvgSpineRender(vg, inst)
end

--- 绘制天赋 Tab 内容（受 scissor 裁剪的部分）
function M.drawContent(vg)
    -- ★ 天赋星图 (先绘制，作为底层)
    -- 同步缩放滑块值到星图
    TalentStarMap.setZoom(state.tfZoomSliderValue)
    -- 星图区域: 全屏 1080×2400
    local mapTop = 0
    local mapH   = DESIGN_H
    TalentStarMap.draw(vg, 0, mapTop, DESIGN_W, mapH)

    -- 新手引导热点：整个天赋星图区域
    local _TM = require("systems.TutorialManager")
    if _TM.isActive() then
        _TM.registerHotspot("talent_node_area", DESIGN_W * 0.5, mapTop + mapH * 0.5, DESIGN_W, mapH)
    end

    -- 3. 天赋点背景光晕 UI_JTTF_HG.png（绘制在星图上方）
    drawImageCentered(vg, img.tfPointGlow, TF.glowCX, TF.glowCY, TF.glowW, TF.glowH, 1.0)

    -- 4. 天赋点数值 "剩余天赋点/天赋点上限"
    --    左部分(剩余) #ffef67 + 黑色描边; 右部分(/上限) 白色 + 黑色描边
    local talentsData = getDispatcher().get("talents")
    local playerData  = getDispatcher().get("player")
    local litCount   = (talentsData and talentsData.litNodes) and #talentsData.litNodes or 1
    local usedPoints = litCount - 1            -- node 0 不消耗天赋点
    local maxPoints  = (playerData and playerData.level) or 1
    local remaining  = math.max(0, maxPoints - usedPoints)
    local leftText = tostring(remaining)
    local rightText = "/" .. tostring(maxPoints)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TF.ptFont)

    -- 测量整体宽度以实现居中
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local leftW = nvgTextBounds(vg, 0, 0, leftText)
    local rightW = nvgTextBounds(vg, 0, 0, rightText)
    local totalW = leftW + rightW
    local startX = TF.ptCX - totalW * 0.5

    -- 左部分：描边(黑) + 填充(#ffef67)
    drawTextStroke(vg, startX, TF.ptCY, leftText,
        TF.ptFont, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        0xff, 0xef, 0x67, TF.ptStroke)

    -- 右部分：描边(黑) + 填充(白)
    local afterLeftX = startX + leftW
    drawTextStroke(vg, afterLeftX, TF.ptCY, rightText,
        TF.ptFont, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, TF.ptStroke)

    -- 5. "天赋点"文字 (#ffef67, 无描边)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TF.lblFont)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xff, 0xef, 0x67, 255))
    nvgText(vg, TF.lblCX, TF.lblCY, "天赋点", nil)

    -- 5.5 效果总览感叹号（右上角）
    local _bfInfo = BF.begin(vg, "ctp_overview_info", TF.infoBtnCX, TF.infoBtnCY, TF.infoBtnW, TF.infoBtnH)
    if img.tfInfoIcon and img.tfInfoIcon >= 0 then
        drawImageCentered(vg, img.tfInfoIcon, TF.infoBtnCX, TF.infoBtnCY, TF.infoIconW, TF.infoIconH, 1.0)
    else
        drawTextStroke(vg, TF.infoBtnCX, TF.infoBtnCY, "!",
            44, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 4, { strokeColor = { 0, 0, 0 } })
    end
    BF.finish(vg, _bfInfo)

    -- 6. 重置按钮 [暗黑化 P1-B3] 矢量按钮（绿色）
    local _bf1 = BF.begin(vg, "ctp_reset", TF.rstCX, TF.rstCY, TF.rstW, TF.rstH)
    DarkIcon.drawNine(vg, "btn",
        TF.rstCX - TF.rstW * 0.5,
        TF.rstCY - TF.rstH * 0.5,
        TF.rstW, TF.rstH,
        { accent = "green" })

    -- 7. "重置"文字 (居中于按钮, #1d5037)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TF.rstFont)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x1d, 0x50, 0x37, 255))
    nvgText(vg, TF.rstCX, TF.rstCY, "重置", nil)
    BF.finish(vg, _bf1)

    -- 8. 缩放滑块背景 (黑色30%透明, 圆角18)
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        TF.slBgCX - TF.slBgW * 0.5,
        TF.slBgCY - TF.slBgH * 0.5,
        TF.slBgW, TF.slBgH, TF.slBgR)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 77))  -- 30% opacity ≈ 77/255
    nvgFill(vg)

    -- 9. 缩放滑块轨道 (白色30%透明, 圆角5)
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        TF.slBgCX - TF.slTrkW * 0.5,
        TF.slBgCY - TF.slTrkH * 0.5,
        TF.slTrkW, TF.slTrkH, TF.slTrkR)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 77))  -- 30% opacity
    nvgFill(vg)

    -- 10. 缩放滑块滑块 UI_JTTF_HK.png (可拖拽, 初始在顶部)
    local trackTop = TF.slBgCY - TF.slTrkH * 0.5
    local trackBot = TF.slBgCY + TF.slTrkH * 0.5
    local thumbCY = trackTop + state.tfZoomSliderValue * (trackBot - trackTop)
    drawImageCentered(vg, img.tfSliderThumb,
        TF.slBgCX, thumbCY,
        TF.slThW, TF.slThH, 1.0)
end

--- 绘制天赋详情面板
function M.drawDetailPanel(vg)
    if not state.tfDetailOpen or not state.tfDetailNodeId then return end

    local node = TalentStarMap.getNode(state.tfDetailNodeId)
    if not node then
        state.tfDetailOpen = false
        state.tfDetailNodeId = nil
        return
    end

    -- 动画进度
    local elapsed = time.elapsedTime - state.tfDetailAnimT
    local rawT = math.min(1.0, elapsed / POPUP_ANIM_DUR)
    local progress  -- 0→1 展开，1→0 收起
    if state.tfDetailClosing then
        progress = 1.0 - easeInCubic(rawT)
        if rawT >= 1.0 then
            -- 关闭动画结束
            state.tfDetailOpen = false
            state.tfDetailNodeId = nil
            state.tfDetailClosing = false
            return
        end
    else
        progress = easeOutCubic(rawT)
    end

    local alpha = math.floor(progress * 255 + 0.5)
    local scale = POPUP_SCALE_FROM + (1.0 - POPUP_SCALE_FROM) * progress

    -- 1. 全屏半透明黑色遮罩 (50% × progress)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * progress + 0.5)))
    nvgFill(vg)

    -- 应用缩放变换（以面板中心为原点）
    nvgSave(vg)
    nvgTranslate(vg, TFD.bgCX, TFD.bgCY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -TFD.bgCX, -TFD.bgCY)
    nvgGlobalAlpha(vg, progress)

    -- 2. 面板背景 [暗黑化 P1-B5] 矢量纯底板（按天赋颜色语义描边）
    local color = node.color or "无"
    if color == "无" then color = "紫" end  -- 起始点使用紫色背景
    DarkIcon.drawNine(vg, "plain",
        TFD.bgCX - TFD.bgW * 0.5,
        TFD.bgCY - TFD.bgH * 0.5,
        TFD.bgW, TFD.bgH,
        { accent = TF_ACCENT[color] or "purple" })

    -- 3. 天赋名（白色 + 描边 #282828）
    drawTextStroke(vg, TFD.nameCX, TFD.nameCY, node.name or "未知",
        TFD.nameFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TFD.nameStroke,
        { strokeColor = { 0x28, 0x28, 0x28 } })

    -- 4. 天赋图标 [暗黑化 P2-10] 矢量符号（铭牌+系色）
    TalentStarMap.drawTalentIcon(vg, state.tfDetailNodeId, TFD.iconCX, TFD.iconCY, TFD.iconW, 1.0)

    -- 5. 信息文本背景框（纯黑 5% 不透明度，圆角14）
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        TFD.infoBgCX - TFD.infoBgW * 0.5,
        TFD.infoBgCY - TFD.infoBgH * 0.5,
        TFD.infoBgW, TFD.infoBgH, TFD.infoBgR)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 13))  -- 5% ≈ 13/255
    nvgFill(vg)

    -- 6. 信息文本（左居上，内边距35）
    local infoText = node.effect or "暂无描述"
    local textBoxX = TFD.infoBgCX - TFD.infoBgW * 0.5 + TFD.infopad
    local textBoxY = TFD.infoBgCY - TFD.infoBgH * 0.5 + TFD.infopad
    local textBoxW = TFD.infoBgW - TFD.infopad * 2

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TFD.infoFont)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(TFD.infoR, TFD.infoG, TFD.infoB, 255))
    -- 使用 textBox 自动换行
    nvgTextBox(vg, textBoxX, textBoxY, textBoxW, infoText, nil)

    -- 7. 按钮：末尾已点亮节点显示红色"重置"，未点亮节点显示绿色"激活"
    local isLit = TalentStarMap.isNodeLit(state.tfDetailNodeId)
    local isTerminal = isLit and isTerminalNode(state.tfDetailNodeId)
    local btnKey = isTerminal and "ctp_reset_single" or "ctp_activate"
    local btnAccent = isTerminal and "red" or "green"  -- [暗黑化 P1-B3] 重置=红 激活=绿
    local btnText = isTerminal and "重置" or (isLit and "已激活" or "激活")
    -- 红色按钮文字: 白色; 绿色按钮文字: 深绿; 已激活灰显: 深绿
    local btnTextR = isTerminal and 0xFF or TFD.btnR
    local btnTextG = isTerminal and 0xFF or TFD.btnG
    local btnTextB = isTerminal and 0xFF or TFD.btnB

    local _bf2 = BF.begin(vg, btnKey, TFD.btnCX, TFD.btnCY, TFD.btnW, TFD.btnH)
    DarkIcon.drawNine(vg, "btn",
        TFD.btnCX - TFD.btnW * 0.5,
        TFD.btnCY - TFD.btnH * 0.5,
        TFD.btnW, TFD.btnH,
        { accent = btnAccent })

    -- 8. 按钮文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TFD.btnFont)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(btnTextR, btnTextG, btnTextB, 255))
    nvgText(vg, TFD.btnCX, TFD.btnCY, btnText, nil)
    BF.finish(vg, _bf2)

    nvgRestore(vg)  -- 恢复缩放变换
end

--- 绘制天赋效果总览弹窗
function M.drawOverviewPanel(vg)
    if not state.tfOverviewOpen then return end

    local elapsed = time.elapsedTime - state.tfOverviewAnimT
    local rawT = math.min(1.0, elapsed / POPUP_ANIM_DUR)
    local progress
    if state.tfOverviewClosing then
        progress = 1.0 - easeInCubic(rawT)
        if rawT >= 1.0 then
            state.tfOverviewOpen = false
            state.tfOverviewClosing = false
            state.tfOverviewLines = nil
            return
        end
    else
        progress = easeOutCubic(rawT)
    end

    local alpha = math.floor(progress * 255 + 0.5)
    local scale = POPUP_SCALE_FROM + (1.0 - POPUP_SCALE_FROM) * progress

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * progress + 0.5)))
    nvgFill(vg)

    nvgSave(vg)
    nvgTranslate(vg, TOV.bgCX, TOV.bgCY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -TOV.bgCX, -TOV.bgCY)
    nvgGlobalAlpha(vg, alpha / 255)

    -- 1. 弹窗底 [暗黑化 P1-B5] 矢量面板
    DarkIcon.drawNine(vg, "panel",
        TOV.bgCX - TOV.bgW * 0.5, TOV.bgCY - TOV.bgH * 0.5,
        TOV.bgW, TOV.bgH,
        { titleH = TOV.bgNsT })

    drawTextStroke(vg, TOV.bgCX, TOV.titleCY, "天赋效果总览",
        TOV.titleFont, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TOV.titleStroke,
        { strokeColor = { 0x59, 0x32, 0x19 } })

    clampOverviewScroll()

    local listLeft = TOV.bgCX - TOV.listW * 0.5
    local listTop = TOV.listTop
    local contentW = TOV.listW - TOV.listPadX * 2
    local contentLeft = listLeft + TOV.listPadX
    local contentRight = contentLeft + contentW
    nvgSave(vg)
    nvgIntersectScissor(vg, listLeft, listTop, TOV.listW, TOV.listH)
    nvgTranslate(vg, 0, -state.tfOverviewScrollY)

    local y = listTop
    for _, line in ipairs(state.tfOverviewLines or {}) do
        if line.kind == "header" then
            -- 分类标题
            y = y + 8  -- 标题前额外间距
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, TOV.headerFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(TOV.headerR, TOV.headerG, TOV.headerB, 255))
            nvgText(vg, contentLeft, y + TOV.headerH * 0.5, line.text, nil)
            y = y + TOV.headerH
        elseif line.kind == "stat" then
            -- 属性行：半透明背景 + 名称左对齐 + 数值右对齐
            local rowH = TOV.lineH
            nvgBeginPath(vg)
            nvgRoundedRect(vg, contentLeft, y, contentW, rowH, 8)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 20))
            nvgFill(vg)

            local midY = y + rowH * 0.5
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, TOV.textFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(TOV.textR, TOV.textG, TOV.textB, 255))
            nvgText(vg, contentLeft + 16, midY, line.label, nil)

            drawTextStroke(vg, contentRight - 16, midY, line.value,
                TOV.textFont, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)
            y = y + rowH + 6
        else
            -- 普通文本行（特殊效果等长文本，自动换行）
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, TOV.textFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if line.muted then
                nvgFillColor(vg, nvgRGBA(TOV.textR, TOV.textG, TOV.textB, 160))
            else
                nvgFillColor(vg, nvgRGBA(TOV.textR, TOV.textG, TOV.textB, 255))
            end
            -- 测量实际文本高度（nvgTextBoxBounds 返回4个值: x1,y1,x2,y2）
            local _, _, _, by2 = nvgTextBoxBounds(vg, contentLeft, y, contentW, line.text, nil)
            local textH = by2 - y
            nvgTextBox(vg, contentLeft, y, contentW, line.text, nil)
            y = y + math.max(TOV.lineH, textH) + 10
        end
    end

    -- 缓存实际内容高度（供滚动 clamp 使用）
    state.tfOverviewMeasuredH = y - listTop

    nvgRestore(vg)
    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

--- 天赋效果总览输入（模态拦截）
---@return boolean consumed
function M.handleOverviewInput(dx, dy)
    if not state.tfOverviewOpen then return false end
    if state.tfOverviewClosing then return true end

    if time.elapsedTime - state.tfOverviewAnimT < 0.05 then return true end

    if not hitTest(dx, dy, TOV.bgCX, TOV.bgCY, TOV.bgW, TOV.bgH) then
        closeOverview()
        return true
    end

    return true
end

--- 天赋详情面板输入处理（模态拦截）
---@return boolean consumed
function M.handleDetailInput(dx, dy)
    if not state.tfDetailOpen then return false end
    if state.tfDetailClosing then return true end  -- 关闭动画中：消费触摸，不响应

    -- 按钮点击（激活 / 重置）
    if hitTest(dx, dy, TFD.btnCX, TFD.btnCY, TFD.btnW, TFD.btnH) then
        local nid = state.tfDetailNodeId
        local isLit = nid ~= nil and TalentStarMap.isNodeLit(nid)
        local isTerminal = isLit and isTerminalNode(nid)

        if isTerminal then
            -- 末尾节点：发送单节点重置请求
            BF.trigger("ctp_reset_single")
            print("[ChurchTalentPanel] 天赋单节点重置: nodeId=" .. tostring(nid))
            getClient().sendAction(getProtocol().ACTION_TYPES.RESET_SINGLE_TALENT, {
                nodeId = nid,
            })
        elseif nid ~= nil and not isLit then
            -- 未点亮节点：发送激活请求
            BF.trigger("ctp_activate")
            print("[ChurchTalentPanel] 天赋激活按钮点击: nodeId=" .. tostring(nid))
            getClient().sendAction(getProtocol().ACTION_TYPES.ACTIVATE_TALENT, {
                nodeId = nid,
            })
        end
        closeDetail()
        return true
    end

    -- 同帧保护：防止 openDetail() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.tfDetailAnimT < 0.05 then return true end

    -- 点击面板外部 → 关闭
    if not hitTest(dx, dy, TFD.bgCX, TFD.bgCY, TFD.bgW, TFD.bgH) then
        closeDetail()
        return true
    end

    -- 面板内其他区域点击：消费掉，不透传
    return true
end

--- 天赋 Tab 交互处理（重置按钮、滑块、星图节点点击）
---@return boolean consumed
function M.handleTabInput(dx, dy)
    if state.tab ~= "tianfu" then return false end

    -- 效果总览按钮
    if hitTest(dx, dy, TF.infoBtnCX, TF.infoBtnCY, TF.infoBtnW, TF.infoBtnH) then
        BF.trigger("ctp_overview_info")
        openOverview()
        return true
    end

    -- 重置按钮
    if hitTest(dx, dy, TF.rstCX, TF.rstCY, TF.rstW, TF.rstH) then
        BF.trigger("ctp_reset")
        print("[ChurchTalentPanel] 天赋重置按钮点击")
        -- 重置天赋：发送请求，服务端会清空并推送更新
        getClient().sendAction(getProtocol().ACTION_TYPES.RESET_TALENTS, {})
        return true
    end

    -- 缩放滑块区域
    local trackTop = TF.slBgCY - TF.slTrkH * 0.5
    local trackBot = TF.slBgCY + TF.slTrkH * 0.5
    if hitTest(dx, dy, TF.slBgCX, TF.slBgCY, TF.slBgW, TF.slBgH) then
        -- 点击滑块区域 → 直接定位滑块
        local clamped = math.max(trackTop, math.min(trackBot, dy))
        state.tfZoomSliderValue = (clamped - trackTop) / (trackBot - trackTop)
        state.tfSliderDragging = true
        print("[ChurchTalentPanel] 缩放滑块: " .. string.format("%.2f", state.tfZoomSliderValue))
        return true
    end

    -- 底部 Tab 栏区域保护：转职按钮(cx=439,cy=2308,w=410,h=143) 和 天赋按钮(cx=839)
    -- 落在 Tab 栏内的点击不交给星图，让事件透传给 ChurchPage 的 Tab 切换逻辑
    if hitTest(dx, dy, 639, 2308, 810, 143) then
        return false
    end

    -- 星图节点点击 → 打开天赋详情面板
    local hitNodeId = TalentStarMap.hitTest(dx, dy)
    if hitNodeId then
        openDetail(hitNodeId)
        return true
    end

    return false
end

-- ======================== 拖拽处理 ========================

--- 拖拽开始
---@return boolean consumed
function M.handleDragBegin(dx, dy)
    if state.tab ~= "tianfu" then return false end
    if state.tfOverviewOpen then
        if hitTest(dx, dy, TOV.bgCX, TOV.bgCY, TOV.bgW, TOV.bgH) then
            state.tfOverviewDragging = true
            state.tfOverviewLastDragY = dy
            return true
        end
        return true
    end
    -- 详情面板打开时不允许拖拽星图
    if state.tfDetailOpen then return true end

    -- 缩放滑块
    local trackTop = TF.slBgCY - TF.slTrkH * 0.5
    local trackBot = TF.slBgCY + TF.slTrkH * 0.5
    if hitTest(dx, dy, TF.slBgCX, TF.slBgCY, TF.slBgW, TF.slBgH) then
        local clamped = math.max(trackTop, math.min(trackBot, dy))
        state.tfZoomSliderValue = (clamped - trackTop) / (trackBot - trackTop)
        state.tfSliderDragging = true
        return true
    end

    -- 星图区域
    if dx >= 0 and dx <= DESIGN_W and dy >= MAP_TOP and dy <= MAP_TOP + MAP_H then
        TalentStarMap.stopInertia()
        state.tfMapDragging = true
        state.tfLastDragX = dx
        state.tfLastDragY = dy
        state.tfLastDragTime = time.elapsedTime
        state.tfDragVelocityX = 0
        state.tfDragVelocityY = 0
        return true
    end

    return false
end

--- 拖拽移动
---@return boolean consumed
function M.handleDragMove(dx, dy)
    if state.tab ~= "tianfu" then return false end

    if state.tfOverviewDragging then
        local dyDelta = dy - state.tfOverviewLastDragY
        state.tfOverviewScrollY = state.tfOverviewScrollY - dyDelta
        state.tfOverviewLastDragY = dy
        clampOverviewScroll()
        return true
    end

    -- 滑块拖拽中
    if state.tfSliderDragging then
        local trackTop = TF.slBgCY - TF.slTrkH * 0.5
        local trackBot = TF.slBgCY + TF.slTrkH * 0.5
        local clamped = math.max(trackTop, math.min(trackBot, dy))
        state.tfZoomSliderValue = (clamped - trackTop) / (trackBot - trackTop)
        return true
    end

    -- 星图拖拽中
    if state.tfMapDragging then
        local ddx = dx - state.tfLastDragX
        local ddy = dy - state.tfLastDragY
        TalentStarMap.pan(ddx, ddy)
        -- 速度追踪（指数平滑）
        local now = time.elapsedTime
        local dtDrag = now - state.tfLastDragTime
        if dtDrag > 0.001 then
            local instVX = ddx / dtDrag  -- 屏幕 px/s
            local instVY = ddy / dtDrag
            local blend = 0.4
            state.tfDragVelocityX = state.tfDragVelocityX * (1 - blend) + instVX * blend
            state.tfDragVelocityY = state.tfDragVelocityY * (1 - blend) + instVY * blend
        end
        state.tfLastDragX = dx
        state.tfLastDragY = dy
        state.tfLastDragTime = now
        return true
    end

    return false
end

--- 拖拽结束
function M.handleDragEnd(dx, dy)
    if state.tfOverviewDragging then
        state.tfOverviewDragging = false
        return
    end

    -- 星图拖拽结束 → 启动惯性
    if state.tfMapDragging then
        -- 检查最后一次拖拽是否太久前（手指静止后松开不应有惯性）
        local timeSinceLast = time.elapsedTime - state.tfLastDragTime
        if timeSinceLast < 0.1 then
            -- 屏幕速度转世界速度（取反，与 pan 逻辑一致）
            local worldVX = -state.tfDragVelocityX / TalentStarMap.getZoom()
            local worldVY = -state.tfDragVelocityY / TalentStarMap.getZoom()
            TalentStarMap.startInertia(worldVX, worldVY)
        end
    end
    state.tfSliderDragging = false
    state.tfMapDragging = false
end

--- 滚轮滚动（效果总览列表）
---@param wheel number
function M.handleScroll(wheel)
    if not state.tfOverviewOpen or state.tfOverviewClosing then return end
    state.tfOverviewScrollY = state.tfOverviewScrollY - wheel * 80
    clampOverviewScroll()
end

--- 预加载 Spine 资源
function M.preloadSpine(vg)
    ensureSpineTfBgLoaded(vg)
end

return M
