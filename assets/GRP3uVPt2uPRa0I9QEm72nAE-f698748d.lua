-- ============================================================================
-- MailPanel - 邮件弹窗面板
-- 全屏遮罩 + 九宫格弹窗 + 可滚动邮件列表 + 品质框 + 已读遮罩 + 底部按钮
-- ============================================================================

local GameConfig  = require("config.GameConfig")
local HeroConfig  = require("config.HeroConfig")
local DrawUtil    = require("core.DrawUtil")
local ImageCache  = require("ui.ImageCache")
local RewardPopup = require("ui.RewardPopup")
local Protocol    = require("shared.Protocol")
local BF          = require("systems.ButtonFeedback")
local ResourceDefs = require("config.ResourceDefs")

local Panel = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 1. 遮罩
local MASK_A = 128  -- 50%

-- 2. 弹窗背景（九宫格 UI_TY_EJQRK）
local BG = {
    CX = 540, CY = 1175, W = 950, H = 1447,
    IT = 180, IL = 40, IR = 40, IB = 50,
}

-- 3. 标题 "邮件"
local TTL = {
    X = 540, Y = 520, FONT = 60, SW = 6,
    SR = 0x59, SG = 0x32, SB = 0x19,
}

-- 4. 内容背景框
local CONTENT = {
    CX = 540, CY = 1153, W = 850, H = 1050, R = 16,
    BG_A = 13,  -- 5% of 255
}

-- 5. 邮件条目布局（基于第一条绝对坐标 → 相对偏移量）
-- 第一条品质框中心 Y=752，分割线 Y=757 → 取 FIRST_CY=757 作为条目基准
local FIRST_CY = 757

local ENTRY = {
    CX = 540, W = 810, H = 220, GAP = 13,
    -- 2) 品质框 UI_icon_ZBBJ_(1-5): X249 Y752 160×160 → 偏移 -5
    QFRAME_CX = 249, QFRAME_CY_OFF = -5, QFRAME_W = 160, QFRAME_H = 160,
    -- 3) 奖励图标: 同位置同尺寸
    ICON_CX = 249, ICON_CY_OFF = -5, ICON_W = 160, ICON_H = 160,
    -- 4) 标题: X左对齐354 Y719 → 偏移 -38
    TITLE_X = 354, TITLE_Y_OFF = -38, TITLE_FONT = 48,
    TITLE_R = 0x5f, TITLE_G = 0x37, TITLE_B = 0x37,
    -- 5) 分割线: X621 Y757 530×4 圆角2 颜色8d5f41 不透明度40%
    DIV_CX = 621, DIV_Y_OFF = 0, DIV_W = 530, DIV_H = 4, DIV_ROUND = 2,
    DIV_R = 0x8d, DIV_G = 0x5f, DIV_B = 0x41, DIV_A = 102,
    -- 6) 日期: X左对齐354 Y792 → 偏移 +35
    DATE_X = 354, DATE_Y_OFF = 35, DATE_FONT = 38,
    DATE_R = 0xc6, DATE_G = 0xa9, DATE_B = 0x97,
    -- 7) 剩余天数: X右对齐882 Y792 → 偏移 +35
    REMAIN_X = 882, REMAIN_Y_OFF = 35, REMAIN_FONT = 38,
    REMAIN_R = 0xc6, REMAIN_G = 0xa9, REMAIN_B = 0x97,
    -- 已读遮罩
    READ_R = 16, READ_A = 128,  -- 圆角16，50% 黑色
}
ENTRY.STEP = ENTRY.H + ENTRY.GAP  -- 233

-- 裁剪区域
local CONTENT_TOP = CONTENT.CY - CONTENT.H * 0.5  -- 628
local CLIP = {
    TOP = CONTENT_TOP + 10,  -- 638
    BOT = 1660,
}
CLIP.H = CLIP.BOT - CLIP.TOP

-- 8-9. 删除已读按钮
local BTN_DEL = { CX = 317, CY = 1761, W = 410, H = 100 }
-- 10-11. 一键领取按钮
local BTN_CLAIM = { CX = 759, CY = 1761, W = 410, H = 100 }
local BTN_FONT = 40
local BTN_TEXT_A = 191  -- 75% of 255

-- ======================== 详情模式布局常量 ========================

---@type table
local DETAIL = {
    -- 5) 邮件标题
    TITLE_X = 540, TITLE_Y = 678, TITLE_FONT = 48,
    TITLE_R = 0x5f, TITLE_G = 0x37, TITLE_B = 0x37,
    -- 6) 正文段落区域
    BODY_CX = 540, BODY_CY = 1055, BODY_W = 746, BODY_H = 626,
    BODY_FONT = 36,
    BODY_R = 0x8d, BODY_G = 0x5f, BODY_B = 0x41,
    -- 7) 奖励图标组合（第一个图标的绝对坐标）
    REWARD_FIRST_CX = 247, REWARD_CY = 1482,
    REWARD_FRAME_W = 160, REWARD_FRAME_H = 160,
    REWARD_ICON_CX_OFF = 2,   -- 图标相对品质框偏移 (249-247)
    REWARD_ICON_CY_OFF = 2,   -- (1484-1482)
    REWARD_ICON_W = 160, REWARD_ICON_H = 160,
    REWARD_GAP = 18,  -- 8) 奖励间距
    REWARD_MAX = 4,   -- 8) 最多显示4个
    -- 数量角标
    BADGE_FONT = 40, BADGE_SW = 5,
    -- 9-10) 领取按钮
    BTN_CX = 540, BTN_CY = 1761, BTN_W = 410, BTN_H = 100,
}

-- ======================== 弹窗动画 ========================

local POPUP_OPEN_DUR   = 0.25
local POPUP_CLOSE_DUR  = 0.20
local POPUP_SCALE_FROM = 0.8
local POPUP_SCALE_TO   = 1.0

local function easeOutCubic(t) local f = t - 1; return f * f * f + 1 end
local function easeInCubic(t) return t * t * t end

--- 估算正文换行高度（无 vg 时 fallback）
local function estimateBodyTextHeight(text, fontSize, wrapWidth)
    local cjkCount, asciiCount, lineBreaks = 0, 0, 0
    local i, len = 1, #(text or "")
    while i <= len do
        local b = string.byte(text, i)
        if b == 0x0A then
            lineBreaks = lineBreaks + 1
            i = i + 1
        elseif b >= 0xF0 then i = i + 4; cjkCount = cjkCount + 1
        elseif b >= 0xE0 then i = i + 3; cjkCount = cjkCount + 1
        elseif b >= 0xC0 then i = i + 2; cjkCount = cjkCount + 1
        else i = i + 1; asciiCount = asciiCount + 1 end
    end
    local lineH = math.ceil(fontSize * 1.44)
    local totalWidth = cjkCount * fontSize + asciiCount * (fontSize * 0.5)
    local wrapLines = math.max(1, math.ceil(totalWidth / wrapWidth))
    return (wrapLines + lineBreaks) * lineH
end

local function measureBodyTextHeight(vg, bodyLeft, bodyTop, bodyText)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, DETAIL.BODY_FONT)
    local bounds = nvgTextBoxBounds(vg, bodyLeft, bodyTop, DETAIL.BODY_W, bodyText)
    if bounds and bounds[4] and bounds[2] then
        local h = bounds[4] - bounds[2]
        if h > 0 then return h end
    end
    return estimateBodyTextHeight(bodyText, DETAIL.BODY_FONT, DETAIL.BODY_W)
end

local clampDetailScroll  -- forward declaration; body defined after `state`

-- ======================== 图片句柄 ========================

local imgBg       = -1  -- UI_TY_EJQRK.png（九宫格弹窗背景）
local imgEntryBg  = -1  -- UI_GG_1.png（条目背景）
local imgBtnDel   = -1  -- UI_AN_LV.png（绿色按钮）
local imgBtnClaim = -1  -- UI_AN_HUANG.png（黄色按钮）

-- NanoVG 上下文（init 时存储，用于延迟加载资源图标）
local vg_ = nil

-- ======================== 资源定义（统一引用中央注册表） ========================
local RESOURCE_DEFS = ResourceDefs.DEFS

-- 资源图标缓存（延迟加载）
local resIconCache = {}

--- 获取英雄品质（邮件碎片奖励展示用）
---@param heroId number|string|nil
---@return number quality
local function getShardQuality(heroId)
    if not heroId then return 3 end
    local heroDef = HeroConfig.get(tonumber(heroId))
    return heroDef and heroDef.quality or 3
end

--- 获取资源图标（缓存）
local function getResIcon(resType)
    local cached = resIconCache[resType]
    if cached then return cached end
    if not vg_ then return -1 end
    local def = RESOURCE_DEFS[resType]
    if not def then return -1 end
    local handle = nvgCreateImage(vg_, def.iconPath, 0)
    resIconCache[resType] = handle
    return handle
end

--- 获取邮件奖励中品质最高的资源类型和品质值
local function getHighestQualityReward(mail)
    local bestQ = 0
    local bestType = nil
    for _, r in ipairs(mail.rewards or {}) do
        local q = 0
        if r.type == "shard" and r.heroId then
            q = getShardQuality(r.heroId)
        else
            local def = RESOURCE_DEFS[r.type]
            q = def and def.quality or 0
        end
        if q > bestQ then
            bestQ = q
            bestType = r.type == "shard" and ("shard_" .. tostring(r.heroId)) or r.type
        end
    end
    return bestType or "gold", math.max(bestQ, 1)
end

-- ======================== 邮件数据（由服务端/单机模式推送） ========================

local MAILS = {}

-- ======================== 状态 ========================

local state = {
    open = false,
    scrollY = 0,
    dragging = false,
    lastDragY = 0,
    -- 弹窗动画
    popupAnimTime  = 0,
    popupClosing   = false,
    popupCloseTime = 0,
    -- 详情模式
    detailIndex = nil,  -- nil=列表模式, number=详情模式（邮件索引）
    detailScrollY = 0,  -- 详情正文滚动偏移
    detailTextH = 0,    -- 详情正文总高度（用于滚动 clamp）
    detailDragging = false,
    detailLastDragY = 0,
}

-- clampDetailScroll body (forward-declared before state)
function clampDetailScroll()
    local maxScroll = math.max(0, (state.detailTextH or 0) - DETAIL.BODY_H)
    state.detailScrollY = math.max(0, math.min(state.detailScrollY, maxScroll))
end

-- ======================== sendAction 注入 ========================

---@type fun(action: string, params: table)|nil
local sendAction_ = nil

--- 注入 sendAction 回调（Client/Standalone 调用）
---@param fn fun(action: string, params: table)
function Panel.setSendAction(fn)
    sendAction_ = fn
end

--- 设置邮件数据（服务端推送或单机模式初始化）
---@param mails table[]
function Panel.setMailData(mails)
    MAILS = mails or {}
    state.scrollY = 0
    state.detailIndex = nil
    print("[MailPanel] setMailData: " .. #MAILS .. " 封邮件")
end

--- 处理服务端操作结果
---@param data table 服务端返回的 actionResult
function Panel.onActionResult(data)
    if not data then return end

    if data.mailPush and data.mails then
        -- 初始化推送
        Panel.setMailData(data.mails)
        return
    end

    if not data.mailAction then return end

    if not data.success then
        print("[MailPanel] action failed: " .. tostring(data.reason))
        return
    end

    local action = data.action

    if action == Protocol.ACTION_TYPES.CLAIM_MAIL then
        -- 单封领取成功 → 标记对应邮件为已读并弹奖励
        local mailId = data.mailId
        for _, mail in ipairs(MAILS) do
            if mail.id == mailId then
                mail.read = true
                RewardPopup.show(mail.title, data.rewards or mail.rewards or {})
                break
            end
        end
        -- 保持在详情视图，显示"已领取"状态（点击按钮可返回列表）

    elseif action == Protocol.ACTION_TYPES.CLAIM_ALL_MAIL then
        -- 一键领取成功 → 标记所有为已读并弹奖励
        for _, mail in ipairs(MAILS) do
            mail.read = true
        end
        if data.rewards and #data.rewards > 0 then
            RewardPopup.show("一键领取", data.rewards)
        end

    elseif action == Protocol.ACTION_TYPES.DELETE_READ then
        -- 删除已读成功 → 从列表中移除所有已读邮件
        -- 已领取的邮件（静态/动态/广播）在服务端均已标记，下次登录不再返回
        for i = #MAILS, 1, -1 do
            if MAILS[i].read then
                table.remove(MAILS, i)
            end
        end
        state.detailIndex = nil
        print("[MailPanel] 删除已读 → 剩余 " .. #MAILS .. " 封")
    end
end

-- （旧硬编码 MAILS 已移除，由 setMailData 注入）

-- ======================== 弹窗动画辅助 ========================

local function getPopupAnim()
    if state.popupClosing then
        local t = math.min(1.0, (time.elapsedTime - state.popupCloseTime) / POPUP_CLOSE_DUR)
        local e = easeInCubic(t)
        local scale = POPUP_SCALE_TO + (POPUP_SCALE_FROM - POPUP_SCALE_TO) * e
        return scale, 1.0 - e, (t >= 1.0)
    else
        local t = math.min(1.0, (time.elapsedTime - state.popupAnimTime) / POPUP_OPEN_DUR)
        local e = easeOutCubic(t)
        local scale = POPUP_SCALE_FROM + (POPUP_SCALE_TO - POPUP_SCALE_FROM) * e
        return scale, e, false
    end
end

-- ======================== Public API ========================

--- 是否有未读/可领取的邮件
---@return boolean
function Panel.hasClaimable()
    for _, mail in ipairs(MAILS) do
        if not mail.read then return true end
    end
    return false
end

function Panel.init(vg)
    vg_ = vg
    imgBg       = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    imgEntryBg  = nvgCreateImage(vg, "image/UI_GG_1.png", 0)
    imgBtnDel   = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    imgBtnClaim = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    ImageCache.init(vg)
    print("[MailPanel] init OK")
end

function Panel.open()
    state.open = true
    require("systems.GameSFX").playUIMove(1)
    state.scrollY = 0
    state.dragging = false
    state.popupAnimTime = time.elapsedTime
    state.popupClosing = false
    state.detailIndex = nil
    print("[MailPanel] open")
end

function Panel.close()
    if state.popupClosing then return end
    state.popupClosing = true
    state.popupCloseTime = time.elapsedTime
    state.dragging = false
    print("[MailPanel] close (anim)")
end

function Panel.isOpen()
    return state.open
end

function Panel.update(dt)
    if not state.open then return end
    if state.popupClosing then
        local _, _, done = getPopupAnim()
        if done then
            state.popupClosing = false
            state.open = false
        end
    end
end

-- ======================== 主绘制 ========================

function Panel.draw(vg)
    if not state.open then return end

    local pScale, pAlpha, _ = getPopupAnim()

    -- 1. 全屏遮罩
    nvgBeginPath(vg); nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(MASK_A * pAlpha)))
    nvgFill(vg)

    -- 弹窗 scale+fade 变换
    nvgSave(vg)
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -BG.CX, -BG.CY)
    nvgGlobalAlpha(vg, pAlpha)

    -- 2. 九宫格弹窗背景
    DrawUtil.drawNineSlice(vg, imgBg,
        BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5,
        BG.W, BG.H, BG.IT, BG.IR, BG.IB, BG.IL)

    -- 3. 标题 "邮件"（描边文字）
    DrawUtil.drawTextStroke(vg, TTL.X, TTL.Y, "邮件",
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TTL.SW,
        { strokeColor = { TTL.SR, TTL.SG, TTL.SB } })

    -- 4. 内容背景框（圆角矩形，黑色 5%）
    DrawUtil.drawRoundedRectCentered(vg, CONTENT.CX, CONTENT.CY,
        CONTENT.W, CONTENT.H, CONTENT.R,
        0, 0, 0, CONTENT.BG_A)

    if state.detailIndex then
        -- ==================== 详情模式 ====================
        local mail = MAILS[state.detailIndex]
        if mail then
            -- 5) 邮件标题
            nvgFontFace(vg, "sans"); nvgFontSize(vg, DETAIL.TITLE_FONT)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(DETAIL.TITLE_R, DETAIL.TITLE_G, DETAIL.TITLE_B, 255))
            nvgText(vg, DETAIL.TITLE_X, DETAIL.TITLE_Y, mail.title or "", nil)

            -- 6) 正文段落区域（多行自动换行，支持滚动）
            local bodyLeft = DETAIL.BODY_CX - DETAIL.BODY_W * 0.5
            local bodyTop  = DETAIL.BODY_CY - DETAIL.BODY_H * 0.5
            nvgSave(vg)
            nvgScissor(vg, bodyLeft, bodyTop, DETAIL.BODY_W, DETAIL.BODY_H)
            nvgFontFace(vg, "sans"); nvgFontSize(vg, DETAIL.BODY_FONT)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(DETAIL.BODY_R, DETAIL.BODY_G, DETAIL.BODY_B, 255))
            local bodyText = mail.body or ""
            state.detailTextH = measureBodyTextHeight(vg, bodyLeft, bodyTop, bodyText)
            clampDetailScroll()
            nvgTranslate(vg, 0, -state.detailScrollY)
            nvgTextBox(vg, bodyLeft, bodyTop, DETAIL.BODY_W, bodyText, nil)
            nvgResetScissor(vg)
            nvgRestore(vg)

            -- 7-8) 奖励图标组合（最多4个，向右排列间距18px）
            local rewards = mail.rewards or {}
            local showCount = math.min(#rewards, DETAIL.REWARD_MAX)
            for ri = 1, showCount do
                local r = rewards[ri]
                local rcx = DETAIL.REWARD_FIRST_CX + (ri - 1) * (DETAIL.REWARD_FRAME_W + DETAIL.REWARD_GAP)
                local rcy = DETAIL.REWARD_CY

                local function drawRewardFrame(q, drawIconFn)
                    local qBgImg = ImageCache.getQualityBg(q)
                    if qBgImg and qBgImg >= 0 then
                        DrawUtil.drawImageCentered(vg, qBgImg, rcx, rcy,
                            DETAIL.REWARD_FRAME_W, DETAIL.REWARD_FRAME_H, 1.0)
                    end
                    drawIconFn()
                    local amtStr = tostring(r.amount or 1)
                    local badgeX = rcx + DETAIL.REWARD_FRAME_W * 0.5 - 8
                    local badgeY = rcy + DETAIL.REWARD_FRAME_H * 0.5 - 8
                    DrawUtil.drawTextStroke(vg, badgeX, badgeY, amtStr,
                        DETAIL.BADGE_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM,
                        255, 255, 255, DETAIL.BADGE_SW)
                    if mail.read then
                        nvgBeginPath(vg)
                        nvgRect(vg,
                            rcx - DETAIL.REWARD_FRAME_W * 0.5,
                            rcy - DETAIL.REWARD_FRAME_H * 0.5,
                            DETAIL.REWARD_FRAME_W, DETAIL.REWARD_FRAME_H)
                        nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
                        nvgFill(vg)
                    end
                end

                if r.type == "shard" and r.heroId then
                    local heroId = tonumber(r.heroId)
                    local q = getShardQuality(heroId)
                    drawRewardFrame(q, function()
                        DrawUtil.drawShardIcon(vg, heroId, rcx, rcy,
                            math.min(DETAIL.REWARD_ICON_W, DETAIL.REWARD_ICON_H), 1.0)
                    end)
                else
                    local def = RESOURCE_DEFS[r.type]
                    if def then
                        drawRewardFrame(def.quality, function()
                            local resImg = getResIcon(r.type)
                            if resImg and resImg >= 0 then
                                DrawUtil.drawImageCentered(vg, resImg,
                                    rcx + DETAIL.REWARD_ICON_CX_OFF,
                                    rcy + DETAIL.REWARD_ICON_CY_OFF,
                                    DETAIL.REWARD_ICON_W, DETAIL.REWARD_ICON_H, 1.0)
                            end
                        end)
                    end
                end
            end

            -- 9-10) 领取按钮
            local _bf1 = BF.begin(vg, "mp_detail_claim", DETAIL.BTN_CX, DETAIL.BTN_CY, DETAIL.BTN_W, DETAIL.BTN_H)
            DrawUtil.drawImageCentered(vg, imgBtnClaim, DETAIL.BTN_CX, DETAIL.BTN_CY,
                DETAIL.BTN_W, DETAIL.BTN_H, 1.0)
            nvgFontFace(vg, "sans"); nvgFontSize(vg, BTN_FONT)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, BTN_TEXT_A))
            nvgText(vg, DETAIL.BTN_CX, DETAIL.BTN_CY, mail.read and "已领取" or "领取", nil)
            BF.finish(vg, _bf1)
        end
    else
        -- ==================== 列表模式 ====================
        local count = #MAILS
        if count == 0 then
            nvgFontFace(vg, "sans"); nvgFontSize(vg, 38)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 180))
            nvgText(vg, 540, 1100, "暂无邮件", nil)
        else
            local totalH = count * ENTRY.STEP - ENTRY.GAP
            local maxScroll = math.max(0, totalH - CLIP.H)
            state.scrollY = math.max(0, math.min(state.scrollY, maxScroll))

            nvgSave(vg)
            nvgScissor(vg, CONTENT.CX - CONTENT.W * 0.5, CLIP.TOP, CONTENT.W, CLIP.H)
            nvgTranslate(vg, 0, -state.scrollY)

            for i, mail in ipairs(MAILS) do
                local cy = FIRST_CY + (i - 1) * ENTRY.STEP
                local screenCY = cy - state.scrollY

                -- 可见性检测
                if screenCY >= CLIP.TOP - ENTRY.H and screenCY <= CLIP.BOT + ENTRY.H then
                    -- 5-1) 条目背景 UI_GG_1.png
                    DrawUtil.drawImageCentered(vg, imgEntryBg, ENTRY.CX, cy,
                        ENTRY.W, ENTRY.H, 1.0)

                    -- 5-2) 品质框（取奖励中最高品质）
                    local bestType, bestQ = getHighestQualityReward(mail)
                    local qBgImg = ImageCache.getQualityBg(bestQ)
                    if qBgImg and qBgImg >= 0 then
                        DrawUtil.drawImageCentered(vg, qBgImg,
                            ENTRY.QFRAME_CX, cy + ENTRY.QFRAME_CY_OFF,
                            ENTRY.QFRAME_W, ENTRY.QFRAME_H, 1.0)
                    end

                    -- 5-3) 奖励图标（最高品质资源的图标）
                    local heroIdFromBest = bestType and bestType:match("^shard_(%d+)$")
                    if heroIdFromBest then
                        DrawUtil.drawShardIcon(vg, tonumber(heroIdFromBest),
                            ENTRY.ICON_CX, cy + ENTRY.ICON_CY_OFF,
                            math.min(ENTRY.ICON_W, ENTRY.ICON_H), 1.0)
                    else
                        local resImg = getResIcon(bestType)
                        if resImg and resImg >= 0 then
                            DrawUtil.drawImageCentered(vg, resImg,
                                ENTRY.ICON_CX, cy + ENTRY.ICON_CY_OFF,
                                ENTRY.ICON_W, ENTRY.ICON_H, 1.0)
                        end
                    end

                    -- 5-4) 邮件标题
                    nvgFontFace(vg, "sans"); nvgFontSize(vg, ENTRY.TITLE_FONT)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(ENTRY.TITLE_R, ENTRY.TITLE_G, ENTRY.TITLE_B, 255))
                    nvgText(vg, ENTRY.TITLE_X, cy + ENTRY.TITLE_Y_OFF, mail.title or "", nil)

                    -- 5-5) 分割线
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg,
                        ENTRY.DIV_CX - ENTRY.DIV_W * 0.5,
                        cy + ENTRY.DIV_Y_OFF - ENTRY.DIV_H * 0.5,
                        ENTRY.DIV_W, ENTRY.DIV_H, ENTRY.DIV_ROUND)
                    nvgFillColor(vg, nvgRGBA(ENTRY.DIV_R, ENTRY.DIV_G, ENTRY.DIV_B, ENTRY.DIV_A))
                    nvgFill(vg)

                    -- 5-6) 邮件日期
                    nvgFontFace(vg, "sans"); nvgFontSize(vg, ENTRY.DATE_FONT)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(ENTRY.DATE_R, ENTRY.DATE_G, ENTRY.DATE_B, 255))
                    nvgText(vg, ENTRY.DATE_X, cy + ENTRY.DATE_Y_OFF, mail.date or "", nil)

                    -- 5-7) 剩余天数
                    if mail.remainDays then
                        nvgFontSize(vg, ENTRY.REMAIN_FONT)
                        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(ENTRY.REMAIN_R, ENTRY.REMAIN_G, ENTRY.REMAIN_B, 255))
                        nvgText(vg, ENTRY.REMAIN_X, cy + ENTRY.REMAIN_Y_OFF,
                            "剩余" .. mail.remainDays .. "天", nil)
                    end

                    -- 已读遮罩（黑色 50%，圆角 16）
                    if mail.read then
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg,
                            ENTRY.CX - ENTRY.W * 0.5,
                            cy - ENTRY.H * 0.5,
                            ENTRY.W, ENTRY.H, ENTRY.READ_R)
                        nvgFillColor(vg, nvgRGBA(0, 0, 0, ENTRY.READ_A))
                        nvgFill(vg)
                    end
                end
            end

            nvgResetScissor(vg)
            nvgRestore(vg)  -- 恢复滚动裁剪
        end

        -- 列表模式底部按钮
        -- 删除已读按钮
        local _bf2 = BF.begin(vg, "mp_delete", BTN_DEL.CX, BTN_DEL.CY, BTN_DEL.W, BTN_DEL.H)
        DrawUtil.drawImageCentered(vg, imgBtnDel, BTN_DEL.CX, BTN_DEL.CY,
            BTN_DEL.W, BTN_DEL.H, 1.0)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, BTN_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, BTN_TEXT_A))
        nvgText(vg, BTN_DEL.CX, BTN_DEL.CY, "删除已读", nil)
        BF.finish(vg, _bf2)

        -- 一键领取按钮
        local _bf3 = BF.begin(vg, "mp_claim_all", BTN_CLAIM.CX, BTN_CLAIM.CY, BTN_CLAIM.W, BTN_CLAIM.H)
        DrawUtil.drawImageCentered(vg, imgBtnClaim, BTN_CLAIM.CX, BTN_CLAIM.CY,
            BTN_CLAIM.W, BTN_CLAIM.H, 1.0)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, BTN_TEXT_A))
        nvgText(vg, BTN_CLAIM.CX, BTN_CLAIM.CY, "一键领取", nil)
        BF.finish(vg, _bf3)
    end

    nvgRestore(vg)  -- 恢复弹窗 scale+fade 变换
end

-- ======================== 输入处理 ========================

function Panel.handleInput(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.popupAnimTime < 0.05 then return true end

    -- 点击弹窗外部 → 关闭（两种模式通用）
    local bgL = BG.CX - BG.W * 0.5
    local bgT = BG.CY - BG.H * 0.5
    if dx < bgL or dx > bgL + BG.W or dy < bgT or dy > bgT + BG.H then
        Panel.close()
        return true
    end

    if state.detailIndex then
        -- ==================== 详情模式 ====================
        local mail = MAILS[state.detailIndex]

        -- 领取按钮
        if mail and DrawUtil.hitTest(dx, dy, DETAIL.BTN_CX, DETAIL.BTN_CY, DETAIL.BTN_W, DETAIL.BTN_H) then
            BF.trigger("mp_detail_claim")
            if not mail.read and sendAction_ then
                sendAction_(Protocol.ACTION_TYPES.CLAIM_MAIL, { mailId = mail.id })
                print("[MailPanel] 请求领取邮件: " .. (mail.id or ""))
            elseif mail.read then
                state.detailIndex = nil  -- 已读邮件直接返回列表
            end
            return true
        end

        -- 正文区域点击不关闭（该区域用于拖拽滚动）
        local bodyLeft = DETAIL.BODY_CX - DETAIL.BODY_W * 0.5
        local bodyTop  = DETAIL.BODY_CY - DETAIL.BODY_H * 0.5
        if dx >= bodyLeft and dx <= bodyLeft + DETAIL.BODY_W
           and dy >= bodyTop and dy <= bodyTop + DETAIL.BODY_H then
            return true
        end

        -- 点击其他区域 → 返回列表
        state.detailIndex = nil
        return true
    else
        -- ==================== 列表模式 ====================

        -- 删除已读按钮
        if DrawUtil.hitTest(dx, dy, BTN_DEL.CX, BTN_DEL.CY, BTN_DEL.W, BTN_DEL.H) then
            BF.trigger("mp_delete")
            if sendAction_ then
                sendAction_(Protocol.ACTION_TYPES.DELETE_READ, {})
                print("[MailPanel] 请求删除已读")
            end
            return true
        end

        -- 一键领取按钮
        if DrawUtil.hitTest(dx, dy, BTN_CLAIM.CX, BTN_CLAIM.CY, BTN_CLAIM.W, BTN_CLAIM.H) then
            BF.trigger("mp_claim_all")
            if sendAction_ then
                sendAction_(Protocol.ACTION_TYPES.CLAIM_ALL_MAIL, {})
                print("[MailPanel] 请求一键领取")
            end
            return true
        end

        -- 点击邮件条目 → 进入详情模式
        if dy >= CLIP.TOP and dy <= CLIP.BOT
           and dx >= ENTRY.CX - ENTRY.W * 0.5 and dx <= ENTRY.CX + ENTRY.W * 0.5 then
            local localY = dy + state.scrollY
            for i, mail in ipairs(MAILS) do
                local cy = FIRST_CY + (i - 1) * ENTRY.STEP
                if localY >= cy - ENTRY.H * 0.5 and localY <= cy + ENTRY.H * 0.5 then
                    state.detailIndex = i
                    state.detailScrollY = 0
                    state.detailTextH = 0
                    print("[MailPanel] 进入详情: " .. (mail.title or "") .. " (index=" .. i .. ")")
                    return true
                end
            end
        end

        return true  -- 消费事件防穿透
    end
end

function Panel.handleDragBegin(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end
    if state.detailIndex then
        -- 详情模式：正文区域可滚动
        local bodyLeft = DETAIL.BODY_CX - DETAIL.BODY_W * 0.5
        local bodyTop  = DETAIL.BODY_CY - DETAIL.BODY_H * 0.5
        if dx >= bodyLeft and dx <= bodyLeft + DETAIL.BODY_W
           and dy >= bodyTop and dy <= bodyTop + DETAIL.BODY_H then
            state.detailDragging = true
            state.detailLastDragY = dy
        end
        return true
    end
    if dy >= CLIP.TOP and dy <= CLIP.BOT
       and dx >= ENTRY.CX - ENTRY.W * 0.5 and dx <= ENTRY.CX + ENTRY.W * 0.5 then
        state.dragging = true
        state.lastDragY = dy
    end
    return true
end

function Panel.handleDragMove(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end
    if state.detailIndex then
        if state.detailDragging then
            state.detailScrollY = state.detailScrollY + (state.detailLastDragY - dy)
            state.detailLastDragY = dy
            clampDetailScroll()
        end
        return true
    end
    if state.dragging then
        state.scrollY = state.scrollY + (state.lastDragY - dy)
        state.lastDragY = dy
    end
    return true
end

function Panel.handleDragEnd(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end
    state.dragging = false
    state.detailDragging = false
    return true
end

function Panel.handleScroll(wheel)
    if not state.open then return false end
    if state.popupClosing then return true end
    if state.detailIndex then
        state.detailScrollY = state.detailScrollY - wheel * 60
        clampDetailScroll()
        return true
    end
    state.scrollY = state.scrollY - wheel * 60
    return true
end

return Panel
