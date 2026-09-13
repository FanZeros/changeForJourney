-- ============================================================================
-- StartScreen  - 开始游戏界面
-- 全屏背景视频 + LOGO + "开始游戏按钮，点击任意位置进入游戏
-- ============================================================================

local GameConfig         = require("config.GameConfig")
local ServerListConfig   = require("shared.ServerListConfig")
local ServerSelectPanel  = require("ui.ServerSelectPanel")

local StartScreen = {}

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ── 资源句柄 ──
local vg_          = nil
local imgLogo_     = -1
local imgGlow_     = -1
local imgDeco_     = -1
local imgFwq_      = { -1, -1, -1 }   -- ICON_FWQ_1=通畅 2=繁忙 3=满
local imgMask_     = -1                -- 底部渐变遮罩
local imgBgFallback_ = -1             -- 视频首帧静态图（视频未就绪时显示）
local videoPlayer_ = nil
local videoHandle_ = nil

-- ── BGM ──
local bgmNode_     = nil   ---@type Node
local bgmSource_   = nil   ---@type SoundSource
local BGM_PATH       = "audio/bgm_title.ogg"
local BGM_VOLUME     = 0.6
local BGM_SPEED      = 1.0   -- 播放速度倍率（1.0 = 原速）

-- ── 状态 ──
local isOpen_     = true
local fadeOut_    = false
local fadeAlpha_  = 1.0
local glowTimer_  = 0   -- 发光呼吸动画计时
local bgmStarted_ = false  -- BGM 是否已开始播放（延迟到首帧）
local bgmDelayTimer_ = nil -- draw 首帧后开始计时，达到 0.6 秒才播放

-- ── 回调 ──
local onStartCallback_        = nil
local onServerSelectCallback_  = nil  -- 选服回调 function(serverId)
local onClosedTransferCallback_ = nil  -- 结束态转出回调 function(serverId)

-- ── 区服状态 ──
local serverInfo_ = {
    name      = "选择服务器",  -- 区服名称（未选服时显示默认文本）
    signal    = 1,             -- 网络信号 1=通畅 2=繁忙 3=中（对应 ICON_FWQ_1/2/3）
    isNew     = false,         -- 是否为最新区服（显示"新"标签）
}
local selectedServerId_ = nil  -- 当前选中的区服ID
local serverListData_   = nil  -- 缓存的区服列表数据（来自服务端）
local pendingServerId_  = nil  -- 淡出期间暂存的待发送区服ID

-- ── 工具函数 ──
local function drawImg(vg, img, cx, cy, w, h, alpha)
    local paint = nvgImagePattern(vg, cx - w * 0.5, cy - h * 0.5, w, h, 0, img, alpha or 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, cx - w * 0.5, cy - h * 0.5, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

local function startSelectedServer()
    if selectedServerId_ then
        pendingServerId_ = selectedServerId_
        fadeOut_ = true
        print("[StartScreen] start selected server: " .. tostring(selectedServerId_))
        return true
    end
    if serverListData_ then
        print("[StartScreen] no selected server, opening server panel")
        ServerSelectPanel.open()
        return true
    end
    print("[StartScreen] click ignored: server list not yet received")
    return true
end

local function canAutoSelectServer(s)
    if not s then return false end
    if not ServerListConfig.isChallengerServer(s.id) then return true end
    if s.stageConfigReady == false then return false end
    if s.closed or s.status == "closed" or s.status == "not_open" then return false end
    return true
end

-- ============================================================================
-- Public API
-- ============================================================================

--- 初始化（在 NanoVG 上下文创建后调用）
---@param nvgCtx userdata
---@param scene Scene|nil  传入场景用于播放 BGM（可选）
function StartScreen.init(nvgCtx, scene)
    vg_ = nvgCtx

    -- 加载图片
    imgLogo_ = nvgCreateImage(vg_, "image/LOGO终焉之门_透明版.png", 0)
    imgGlow_ = nvgCreateImage(vg_, "image/UI_KSYXFG.png", 0)
    imgDeco_ = nvgCreateImage(vg_, "image/UI_KSYXJT.png", 0)

    -- 底部渐变遮罩（与加载界面相同）
    imgMask_ = nvgCreateImage(vg_, "image/UI_ZRJM_HD.png", 0)

    -- 视频首帧静态图（视频解码就绪前的fallback，避免黑屏闪烁）
    imgBgFallback_ = nvgCreateImage(vg_, "image/UI_DLJMBJ_Frame1.jpg", 0)

    -- 区服网络状态图标
    for i = 1, 3 do
        imgFwq_[i] = nvgCreateImage(vg_, "image/ICON_FWQ_" .. i .. ".png", 0)
    end

    -- 选服面板初始化（数据由 setServerListData 注入）
    ServerSelectPanel.init(vg_)

    -- 背景视频（循环、静音）
    videoPlayer_ = VideoPlayer:new()
    if videoPlayer_ then
        local ok = videoPlayer_:Load("video/UI_DLJMBJ_Compat.mp4", 1080, 2400)
        if ok then
            videoPlayer_:SetLoop(true)
            videoPlayer_:SetVolume(0)
            videoPlayer_:Play()
        end
    end

    -- BGM（预加载资源，延迟到首次 update 时播放，避免初始化期间音乐空转）
    if scene then
        local snd = cache:GetResource("Sound", BGM_PATH)
        if snd then
            snd.looped = true
            bgmNode_ = scene:CreateChild("StartScreenBGM", LOCAL)
            bgmSource_ = bgmNode_:CreateComponent("SoundSource")
            bgmSource_.soundType = "Music"
            bgmSource_.gain = 0  -- 初始静音，update 时再淡入
            bgmStarted_ = false
        end
    end
end

--- 设置点击"开始游戏后的回调
function StartScreen.setOnStart(fn)
    onStartCallback_ = fn
end

--- 设置选服回调（用户在面板中选中区服后触发）
---@param fn fun(serverId: number)
function StartScreen.setOnServerSelect(fn)
    onServerSelectCallback_ = fn
end

function StartScreen.setOnClosedTransfer(fn)
    onClosedTransferCallback_ = fn
end

--- 接收服务端推送的区服列表数据
--- data 结构: { servers = {{id, name, ...}}, createdServers = {id,...}, lastServerId = number|nil }
---@param data table
function StartScreen.setServerListData(data)
    serverListData_ = data

    -- 将服务端数据转为 ServerSelectPanel 需要的格式
    local panelServers = {}
    if data.servers then
        for _, s in ipairs(data.servers) do
            panelServers[#panelServers + 1] = {
                id        = s.id,
                name      = s.name,
                level     = s.level or 0,
                stage     = s.stage or "",
                isNew     = s.isNew or false,
                kind      = s.kind,
                status    = s.status,
                closeTime = s.closeTime,
                closed    = s.closed == true,
                stageConfigReady = s.stageConfigReady ~= false,
            }
        end
    end

    local playedIds = data.createdServers or {}
    local lastId    = data.lastServerId

    ServerSelectPanel.setData(panelServers, playedIds, lastId)

    ServerSelectPanel.setOnSelect(function(serverId)
        -- 更新本地区服显示
        for _, s in ipairs(panelServers) do
            if s.id == serverId then
                serverInfo_.name  = s.name
                serverInfo_.isNew = s.isNew
                if ServerListConfig.isChallengerServer and ServerListConfig.isChallengerServer(s.id) then
                    serverInfo_.isNew = false
                end
                break
            end
        end
        selectedServerId_ = serverId
        ServerSelectPanel.close()

        -- 启动淡出，淡出完成后自动触发选服回调进入游戏
        pendingServerId_ = serverId
        fadeOut_ = true
    end)

    ServerSelectPanel.setOnClosedTransfer(function(serverId)
        if onClosedTransferCallback_ then
            onClosedTransferCallback_(serverId)
        end
    end)

    -- 自动选中上次的服务器并显示其名称
    -- 注意: lastServerId 默认值为 0（ModuleRegistry），Lua 中 0 是 truthy，
    -- 必须显式判断 > 0 才能区分"从未选服"和"选过"
    local foundLast = false
    if lastId and lastId > 0 and #panelServers > 0 then
        for _, s in ipairs(panelServers) do
            if s.id == lastId and canAutoSelectServer(s) then
                serverInfo_.name  = s.name
                serverInfo_.isNew = s.isNew
                selectedServerId_ = lastId
                foundLast = true
                break
            end
        end
    end
    if not foundLast and #panelServers > 0 then
        -- 从未选服 或上次的服务器已不在列表中 → 默认选最新的可进入服务器
        for i = #panelServers, 1, -1 do
            local newest = panelServers[i]
            if canAutoSelectServer(newest) then
                serverInfo_.name  = newest.name
                serverInfo_.isNew = newest.isNew
                selectedServerId_ = newest.id
                break
            end
        end
    end

    print("[StartScreen] server list data set, servers=" .. #panelServers
        .. " selectedId=" .. tostring(selectedServerId_))
end

--- 每帧更新
function StartScreen.update(dt)
    if not isOpen_ then return end

    -- BGM 延迟播放计时（draw 首帧触发后开始倒计时）
    if not bgmStarted_ and bgmDelayTimer_ and bgmSource_ then
        bgmDelayTimer_ = bgmDelayTimer_ + dt
        if bgmDelayTimer_ >= 0.6 then
            local snd = cache:GetResource("Sound", BGM_PATH)
            if snd then
                bgmSource_:Play(snd)
                bgmSource_.frequency = snd:GetFrequency() * BGM_SPEED
                bgmSource_.gain = BGM_VOLUME
                bgmStarted_ = true
            end
        end
    end

    -- 视频帧更新
    if videoPlayer_ then
        videoPlayer_:Update()
    end

    -- 发光呼吸计时
    glowTimer_ = glowTimer_ + dt

    -- 淡出过渡
    if fadeOut_ then
        fadeAlpha_ = fadeAlpha_ - dt * 2.0  -- 0.5 秒淡出
        if fadeAlpha_ <= 0 then
            fadeAlpha_ = 0
            isOpen_ = false
            fadeOut_ = false
            -- 将视频播放器和 BGM 一起传递给回调（LoadingScreen 复用）
            local vp = videoPlayer_
            local vh = videoHandle_
            local bn = bgmNode_
            local bs = bgmSource_
            videoPlayer_ = nil
            videoHandle_ = nil
            bgmNode_ = nil
            bgmSource_ = nil
            -- 触发回调，传递视频和 BGM 资源
            if onStartCallback_ then
                onStartCallback_(vp, vh, bs, bn)
            end
            -- 淡出完成后，触发暂存的选服回调（发送 SELECT_SERVER）
            if pendingServerId_ and onServerSelectCallback_ then
                local sid = pendingServerId_
                pendingServerId_ = nil
                onServerSelectCallback_(sid)
            end
        end
    end
end

--- 绘制（在设计空间 1080×2400 内调用）
function StartScreen.draw(vg)
    if not isOpen_ then return end

    nvgSave(vg)

    -- 1. 背景视频（全屏）/ 始终全不透明，不参与淡出
    if not videoHandle_ and videoPlayer_ and videoPlayer_:IsReady() then
        local texture = videoPlayer_:GetTexture()
        if texture and nvgCreateVideo then
            videoHandle_ = nvgCreateVideo(vg, texture)
        end
    end
    if videoHandle_ and videoHandle_ > 0 then
        drawImg(vg, videoHandle_, DESIGN_W * 0.5, DESIGN_H * 0.5, DESIGN_W, DESIGN_H, 1.0)
    elseif imgBgFallback_ >= 0 then
        drawImg(vg, imgBgFallback_, DESIGN_W * 0.5, DESIGN_H * 0.5, DESIGN_W, DESIGN_H, 1.0)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(10, 10, 20, 255))
        nvgFill(vg)
    end

    -- 1.5 底部渐变遮罩（与加载界面相同，底部对齐，裁剪到设计宽度）
    if imgMask_ >= 0 then
        local mw, mh = 1098, 1229
        nvgSave(vg)
        nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        drawImg(vg, imgMask_, DESIGN_W * 0.5, DESIGN_H - mh * 0.5, mw, mh, 1.0)
        nvgRestore(vg)
    end

    -- 淡出仅作用于 UI 叠加元素（LOGO、发光、文字），视频背景保持全屏
    if fadeOut_ then
        nvgGlobalAlpha(vg, math.max(fadeAlpha_, 0))
    end

    -- 2. LOGO  (cx=537 cy=424 874×545) / 上下浮动动画
    if imgLogo_ >= 0 then
        local logoFloat = math.sin(glowTimer_ * 1.2) * 12  -- 幅度12px，周期约5.2秒
        -- LOGO 透明画布 1920×1080：等比缩放至宽度 1080（高 607），保持构图
        drawImg(vg, imgLogo_, 540, 403 + logoFloat, 1080, 607, 1.0)
    end

    -- 3. 开始游戏背景光 (cx=540 cy=2002 1057×317)  呼吸闪烁
    if imgGlow_ >= 0 then
        local glowAlpha = 0.7 + 0.3 * math.sin(glowTimer_ * 2.0)
        drawImg(vg, imgGlow_, 540, 2002, 1057, 317, glowAlpha)
    end

    -- 4. 装饰点(cx=340 cy=2002 152×44) / 向左漂浮
    if imgDeco_ >= 0 then
        local driftL = math.sin(glowTimer_ * 1.8) * 8
        drawImg(vg, imgDeco_, 340 - driftL, 2002, 152, 44, 1.0)
    end

    -- 5. 装饰点(cx=739 cy=2002 152×44 旋转180°) / 向右漂浮
    if imgDeco_ >= 0 then
        local driftR = math.sin(glowTimer_ * 1.8) * 8
        nvgSave(vg)
        nvgTranslate(vg, 739 + driftR, 2002)
        nvgRotate(vg, math.pi)
        local paint = nvgImagePattern(vg, -76, -22, 152, 44, 0, imgDeco_, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, -76, -22, 152, 44)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 6. 文字"开始游戏 (cx=540 cy=2001 字号50 纯白)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 50)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, 540, 2001, "开始游戏", nil)

    -- 7. 区服状态(背景 cx=540 cy=1854 600×70)
    do
        -- 7a. 半透明圆角背景
        local bgCx, bgCy = 540, 1854
        local bgW, bgH = 600, 70
        local bgR = 12  -- 圆角半径
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bgCx - bgW * 0.5, bgCy - bgH * 0.5, bgW, bgH, bgR)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)

        -- 7b. 网络状态图标(cx=282 cy=1854 84×84)
        local sigIdx = math.max(1, math.min(3, serverInfo_.signal))
        local fwqImg = imgFwq_[sigIdx]
        if fwqImg and fwqImg >= 0 then
            drawImg(vg, fwqImg, 282, 1854, 84, 84, 1.0)
        end

        -- 7c. 区服名称 (cx=540 cy=1854 字号38 纯白)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, 540, 1854, serverInfo_.name, nil)

        -- 7d. "选"标签 (cx=796 cy=1853 字号38 颜色#44ff63 纯黑描边5)
        if serverInfo_.isNew then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 38)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            -- 纯黑描边
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            for ox = -2, 2 do
                for oy = -2, 2 do
                    if ox ~= 0 or oy ~= 0 then
                        nvgText(vg, 796 + ox, 1853 + oy, "新", nil)
                    end
                end
            end
            -- 绿色填充 #44ff63
            nvgFillColor(vg, nvgRGBA(0x44, 0xff, 0x63, 255))
            nvgText(vg, 796, 1853, "新", nil)
        end
    end

    -- 8. 防沉迷提示文字(cx=540 cy=2186 字号30 纯白 黑色描边5)
    do
        local line1 = "抵制不良游戏，拒绝盗版游戏。注意自我保护，谨防受骗上当"
        local line2 = "适度游戏益脑，沉迷游戏伤身。合理安排时间，享受健康生活"
        local lineH = 38  -- 行间距
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 描边（纯黑，宽度5）
        nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgStrokeWidth(vg, 5)
        nvgFontBlur(vg, 0)
        nvgTextLetterSpacing(vg, 0)
        -- 用 strokeText 模拟描边：先画黑色文字作为底层描边
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        for ox = -2, 2 do
            for oy = -2, 2 do
                if ox ~= 0 or oy ~= 0 then
                    nvgText(vg, 540 + ox, 2186 - lineH * 0.5 + oy, line1, nil)
                    nvgText(vg, 540 + ox, 2186 + lineH * 0.5 + oy, line2, nil)
                end
            end
        end
        -- 纯白填充
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, 540, 2186 - lineH * 0.5, line1, nil)
        nvgText(vg, 540, 2186 + lineH * 0.5, line2, nil)
    end

    -- 9. 版本号（防沉迷文字下方居中）
    do
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 26)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 153))
        local VersionConfig = require("shared.VersionConfig")
        nvgText(vg, 540, 2377, "V" .. VersionConfig.CURRENT, nil)
    end

    -- 10. 选服面板（覆盖在所有 UI 元素之上）
    ServerSelectPanel.draw(vg)

    nvgRestore(vg)

    -- 首帧绘制后开始计时，延迟 1.5 秒再播放 BGM
    if not bgmStarted_ and bgmSource_ then
        if not bgmDelayTimer_ then
            bgmDelayTimer_ = 0
        end
    end
end

--- 处理点击（设计坐标），返回 true 表示已消费
function StartScreen.handleClick(dx, dy)
    if not isOpen_ or fadeOut_ then return false end

    -- 选服面板打开时，事件交给面板处理
    if ServerSelectPanel.isOpen() then
        ServerSelectPanel.handleClick(dx, dy)
        return true
    end

    -- 点击"开始游戏"视觉按钮区域 → 进入游戏
    local startCx, startCy = 540, 2001
    local startW, startH = 620, 170
    local hitStart = dx >= startCx - startW * 0.5 and dx <= startCx + startW * 0.5
        and dy >= startCy - startH * 0.5 and dy <= startCy + startH * 0.5
    if hitStart then
        return startSelectedServer()
    end

    -- 点击区服状态区域(cx=540 cy=1854 600×70) → 打开选服面板
    local bgCx, bgCy = 540, 1854
    local bgW, bgH   = 600, 70
    local hitServer = dx >= bgCx - bgW * 0.5 and dx <= bgCx + bgW * 0.5
        and dy >= bgCy - bgH * 0.5 and dy <= bgCy + bgH * 0.5
    if hitServer then
        print("[StartScreen] open server panel")
        ServerSelectPanel.open()
        return true
    end

    -- 点击其他位置 → 进入游戏 / 打开选服面板
    return startSelectedServer()
end

--- 处理滚轮（设计坐标），返回 true 表示已消费
function StartScreen.handleScroll(dx, dy, delta)
    if not isOpen_ or fadeOut_ then return false end
    if ServerSelectPanel.isOpen() then
        ServerSelectPanel.handleScroll(dx, dy, delta)
        return true
    end
    return false
end

--- 拖拽开始转发
function StartScreen.handleDragBegin(dx, dy)
    if not isOpen_ or fadeOut_ then return false end
    if ServerSelectPanel.isOpen() then
        ServerSelectPanel.handleDragBegin(dx, dy)
        return true
    end
    return false
end

--- 拖拽移动转发
function StartScreen.handleDragMove(dx, dy)
    if not isOpen_ or fadeOut_ then return false end
    if ServerSelectPanel.isOpen() then
        ServerSelectPanel.handleDragMove(dx, dy)
        return true
    end
    return false
end

--- 拖拽结束转发
function StartScreen.handleDragEnd(dx, dy)
    if not isOpen_ or fadeOut_ then return false end
    if ServerSelectPanel.isOpen() then
        ServerSelectPanel.handleDragEnd(dx, dy)
        return true
    end
    return false
end

--- 是否仍在显示
function StartScreen.isOpen()
    return isOpen_
end

--- 更新区服显示信息
---@param info table { name?: string, signal?: number, isNew?: boolean }
function StartScreen.setServerInfo(info)
    if info.name   ~= nil then serverInfo_.name   = info.name   end
    if info.signal ~= nil then serverInfo_.signal = info.signal end
    if info.isNew  ~= nil then serverInfo_.isNew  = info.isNew  end
end

--- 获取当前区服显示信息
function StartScreen.getServerInfo()
    return serverInfo_
end

--- 重连时强制跳过开始界面（不走淡出动画，直接关闭并触发回调）
--- 将视频播放器和 BGM 资源传递给 LoadingScreen 复用
function StartScreen.skipForReconnect()
    if not isOpen_ then return end

    isOpen_   = false
    fadeOut_  = false
    fadeAlpha_ = 0

    -- 将视频和 BGM 资源传递给回调（LoadingScreen 复用），与正常淡出完成时的行为一致
    local vp = videoPlayer_
    local vh = videoHandle_
    local bn = bgmNode_
    local bs = bgmSource_
    videoPlayer_ = nil
    videoHandle_ = nil
    bgmNode_     = nil
    bgmSource_   = nil

    if onStartCallback_ then
        onStartCallback_(vp, vh, bs, bn)
    end

    -- 重连不需要触发选服回调（pendingServerId_ 保持 nil）
    print("[StartScreen] skipped for reconnect")
end

--- 重新打开开始界面（清除存档后调用）
--- 重置内部状态并重新创建视频和 BGM 资源
---@param scene Scene 场景节点（用于创建 BGM）
function StartScreen.reopen(scene)
    -- 重置状态
    isOpen_    = true
    fadeOut_   = false
    fadeAlpha_ = 1.0
    glowTimer_ = 0
    selectedServerId_ = nil
    pendingServerId_  = nil
    serverListData_   = nil
    serverInfo_.name  = "选择服务器"
    serverInfo_.isNew = false

    -- 清理旧资源（如果有残留）
    if videoPlayer_ then
        videoPlayer_ = nil
    end
    videoHandle_ = nil

    if bgmNode_ then
        bgmNode_:Remove()
        bgmNode_ = nil
        bgmSource_ = nil
    end

    -- 重新创建视频播放器
    videoPlayer_ = VideoPlayer:new()
    if videoPlayer_ then
        local ok = videoPlayer_:Load("video/UI_DLJMBJ_Compat.mp4", 1080, 2400)
        if ok then
            videoPlayer_:SetLoop(true)
            videoPlayer_:SetVolume(0)
            videoPlayer_:Play()
        end
    end

    -- 重新创建 BGM（延迟到首次 update 时播放）
    if scene then
        local snd = cache:GetResource("Sound", BGM_PATH)
        if snd then
            snd.looped = true
            bgmNode_ = scene:CreateChild("StartScreenBGM", LOCAL)
            bgmSource_ = bgmNode_:CreateComponent("SoundSource")
            bgmSource_.soundType = "Music"
            bgmSource_.gain = 0
            bgmStarted_ = false
            bgmDelayTimer_ = nil
        end
    end

    print("[StartScreen] reopened")
end

return StartScreen
