-- ============================================================================
-- DiaryPage - 日志页面（标签2：冒险日志）
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local DrawUtil            = require("core.DrawUtil")
local PlayerStore         = require("client.data.PlayerStore")
local AnnouncementPanel   = require("ui.AnnouncementPanel")
local MailPanel           = require("ui.MailPanel")
local SignInPanel         = require("ui.SignInPanel")
local BackpackPanel       = require("ui.BackpackPanel")
local TaskPanel           = require("ui.TaskPanel")
local EquipmentSystem     = require("systems.EquipmentSystem")
local BF                  = require("systems.ButtonFeedback")

local DiaryPage = {}

-- ======================== 图片句柄 ========================

local imgBg      = -1   -- UI_RZ_BJ.png    背景
local imgSignIn  = -1   -- UI_RZAN_QD.png   签到卡片
local imgNotice  = -1   -- UI_RZAN_GG.png   公告卡片
local imgBag     = -1   -- UI_RZAN_BB.png   背包卡片
local imgQuest   = -1   -- UI_RZAN_CJ.png   任务卡片
local imgMail    = -1   -- UI_RZAN_YJ.png   邮件卡片

local imgRedDot  = -1   -- ICON_HD.png      红点提示

-- 红点尺寸（与 TopBar 一致 74×74）
local RED_DOT_SIZE = 74

-- ======================== 布局常量 ========================

-- 背景
local BG_CX, BG_CY = 540, 1200
local BG_W, BG_H   = 1080, 2400

-- 标题
local TITLE_CN_X, TITLE_CN_Y     = 340, 367
local TITLE_CN_SIZE              = 80
local TITLE_EN_X, TITLE_EN_Y     = 783, 375
local TITLE_EN_SIZE              = 50

-- 签到卡片
local SIGNIN_CX, SIGNIN_CY = 382, 819
local SIGNIN_W, SIGNIN_H   = 545, 502
local SIGNIN_TXT_X, SIGNIN_TXT_Y = 230, 623

-- 公告卡片
local NOTICE_CX, NOTICE_CY = 834, 819
local NOTICE_W, NOTICE_H   = 398, 502
local NOTICE_TXT_X, NOTICE_TXT_Y = 760, 623

-- 背包卡片
local BAG_CX, BAG_CY = 354, 1204
local BAG_W, BAG_H   = 526, 247
local BAG_TXT_X, BAG_TXT_Y = 191, 1137
-- 背包容量背景
local BAG_CAP_CX, BAG_CAP_CY = 224, 1272
local BAG_CAP_W, BAG_CAP_H   = 203, 60
local BAG_CAP_ROUND           = 28
local BAG_MAX = EquipmentSystem.MAX_INVENTORY  -- 背包最大容量（引用中心常量）

-- 任务卡片
local QUEST_CX, QUEST_CY = 335, 1461
local QUEST_W, QUEST_H   = 526, 247
local QUEST_TXT_X, QUEST_TXT_Y = 176, 1398

-- 邮件卡片
local MAIL_CX, MAIL_CY = 795, 1332
local MAIL_W, MAIL_H   = 397, 502
local MAIL_TXT_X, MAIL_TXT_Y = 721, 1143



-- 底部日期编号
local DATE_NUM_X, DATE_NUM_Y = 98, 1832
local DATE_NUM_SIZE          = 50

-- 装饰线1 (底部)
local DECO1_CX, DECO1_CY = 509, 1878
local DECO1_W, DECO1_H   = 953, 8
local DECO1_ROUND         = 4
-- 装饰线2 (标题下方)
local DECO2_CX, DECO2_CY = 579, 423
local DECO2_W, DECO2_H   = 801, 8
local DECO2_ROUND         = 4

-- 通用文字参数
local CARD_TEXT_SIZE   = 60
local CARD_STROKE_W    = 6

-- ======================== 工具函数 ========================

--- 居中绘制图片
local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 then return end
    alpha = alpha or 1.0
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 获取背包当前物品数量
local function getInventoryCount()
    local equip = PlayerStore.Get("equipment")
    if not equip or not equip.inventory then return 0 end
    local count = 0
    for _ in pairs(equip.inventory) do count = count + 1 end
    return count
end

-- ======================== Public API ========================

function DiaryPage.init(vg)
    imgBg     = nvgCreateImage(vg, "image/UI_RZ_BJ.png", 0)
    imgSignIn = nvgCreateImage(vg, "image/UI_RZAN_QD.png", 0)
    imgNotice = nvgCreateImage(vg, "image/UI_RZAN_GG.png", 0)
    imgBag    = nvgCreateImage(vg, "image/UI_RZAN_BB.png", 0)
    imgQuest  = nvgCreateImage(vg, "image/UI_RZAN_CJ.png", 0)
    imgMail   = nvgCreateImage(vg, "image/UI_RZAN_YJ.png", 0)
    imgRedDot = nvgCreateImage(vg, "image/ICON_HD.png", 0)
    AnnouncementPanel.init(vg)
    MailPanel.init(vg)
    SignInPanel.init(vg)
    BackpackPanel.init(vg)
    TaskPanel.init(vg)
    print("[DiaryPage] init OK")
end

function DiaryPage.draw(vg)
    -- 1. 背景
    drawImageCentered(vg, imgBg, BG_CX, BG_CY, BG_W, BG_H, 1.0)

    -- 2. 标题 "冒险日志" (斜体, 黑色, 50% 透明度, 无描边)
    nvgSave(vg)
    nvgTranslate(vg, TITLE_CN_X, TITLE_CN_Y)
    nvgSkewX(vg, -math.tan(math.rad(12)))
    nvgTranslate(vg, -TITLE_CN_X, -TITLE_CN_Y)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TITLE_CN_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
    nvgText(vg, TITLE_CN_X, TITLE_CN_Y, "冒险日志", nil)
    nvgRestore(vg)

    -- 3. 标题 "Adventure Diary" (斜体, 黑色, 50% 透明度, 无描边)
    nvgSave(vg)
    nvgTranslate(vg, TITLE_EN_X, TITLE_EN_Y)
    nvgSkewX(vg, -math.tan(math.rad(12)))
    nvgTranslate(vg, -TITLE_EN_X, -TITLE_EN_Y)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TITLE_EN_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
    nvgText(vg, TITLE_EN_X, TITLE_EN_Y, "Adventure Diary", nil)
    nvgRestore(vg)

    -- 4. 签到卡片
    local _bf1 = BF.begin(vg, "dp_signin", SIGNIN_CX, SIGNIN_CY, SIGNIN_W, SIGNIN_H)
    drawImageCentered(vg, imgSignIn, SIGNIN_CX, SIGNIN_CY, SIGNIN_W, SIGNIN_H, 1.0)

    -- 5. "签到" 文字
    DrawUtil.drawTextStroke(vg, SIGNIN_TXT_X, SIGNIN_TXT_Y, "签到",
        CARD_TEXT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, CARD_STROKE_W)
    BF.finish(vg, _bf1)

    -- 6. 公告卡片
    local _bf2 = BF.begin(vg, "dp_notice", NOTICE_CX, NOTICE_CY, NOTICE_W, NOTICE_H)
    drawImageCentered(vg, imgNotice, NOTICE_CX, NOTICE_CY, NOTICE_W, NOTICE_H, 1.0)

    -- 7. "公告" 文字
    DrawUtil.drawTextStroke(vg, NOTICE_TXT_X, NOTICE_TXT_Y, "公告",
        CARD_TEXT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, CARD_STROKE_W)
    BF.finish(vg, _bf2)

    -- 8. 背包卡片
    local _bf3 = BF.begin(vg, "dp_bag", BAG_CX, BAG_CY, BAG_W, BAG_H)
    drawImageCentered(vg, imgBag, BAG_CX, BAG_CY, BAG_W, BAG_H, 1.0)

    -- 9. "背包" 文字
    DrawUtil.drawTextStroke(vg, BAG_TXT_X, BAG_TXT_Y, "背包",
        CARD_TEXT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, CARD_STROKE_W)

    -- 10. 背包容量背景 (圆角矩形, 黑色 50% 透明)
    DrawUtil.drawRoundedRectCentered(vg, BAG_CAP_CX, BAG_CAP_CY,
        BAG_CAP_W, BAG_CAP_H, BAG_CAP_ROUND,
        0, 0, 0, 128)

    -- 11. 背包容量文字 (居中, "N" 彩色 + "/100" 纯白)
    do
        local curCount = getInventoryCount()
        local isFull = (curCount >= BAG_MAX)
        local numStr = tostring(curCount)
        local sepStr = "/" .. tostring(BAG_MAX)
        local cr, cg, cb
        if isFull then
            cr, cg, cb = 0xFF, 0x77, 0x77  -- #ff7777 满了
        else
            cr, cg, cb = 0x90, 0xFF, 0x8A  -- #90ff8a 未满
        end
        -- 计算两部分总宽度以居中
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 40)
        local numW = nvgTextBounds(vg, 0, 0, numStr)
        local sepW = nvgTextBounds(vg, 0, 0, sepStr)
        local totalW = numW + sepW
        local startX = BAG_CAP_CX - totalW * 0.5
        -- 数量部分（彩色描边）
        DrawUtil.drawTextStroke(vg, startX + numW * 0.5, BAG_CAP_CY, numStr,
            40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            cr, cg, cb, CARD_STROKE_W)
        -- "/100" 部分（纯白描边）
        DrawUtil.drawTextStroke(vg, startX + numW + sepW * 0.5, BAG_CAP_CY, sepStr,
            40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, CARD_STROKE_W)
    end
    BF.finish(vg, _bf3)

    -- 12. 任务卡片
    local _bf4 = BF.begin(vg, "dp_quest", QUEST_CX, QUEST_CY, QUEST_W, QUEST_H)
    drawImageCentered(vg, imgQuest, QUEST_CX, QUEST_CY, QUEST_W, QUEST_H, 1.0)

    -- 13. "任务" 文字
    DrawUtil.drawTextStroke(vg, QUEST_TXT_X, QUEST_TXT_Y, "任务",
        CARD_TEXT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, CARD_STROKE_W)
    BF.finish(vg, _bf4)

    -- 14. 邮件卡片
    local _bf5 = BF.begin(vg, "dp_mail", MAIL_CX, MAIL_CY, MAIL_W, MAIL_H)
    drawImageCentered(vg, imgMail, MAIL_CX, MAIL_CY, MAIL_W, MAIL_H, 1.0)

    -- 15. "邮件" 文字
    DrawUtil.drawTextStroke(vg, MAIL_TXT_X, MAIL_TXT_Y, "邮件",
        CARD_TEXT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, CARD_STROKE_W)
    BF.finish(vg, _bf5)



    -- 17. 底部日期编号 (斜体, #333333, 无描边, 显示玩家游戏天数)
    do
        local sessionData = PlayerStore.Get("session")
        local playDays = (sessionData and sessionData.playDays) or 1
        local dayStr = string.format("%02d", playDays)  -- 1→"01", 2→"02", 100→"100"
        nvgSave(vg)
        nvgTranslate(vg, DATE_NUM_X, DATE_NUM_Y)
        nvgSkewX(vg, -math.tan(math.rad(12)))
        nvgTranslate(vg, -DATE_NUM_X, -DATE_NUM_Y)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, DATE_NUM_SIZE)
        -- 三位数及以上时以当前位置为基准左对齐，否则居中
        if playDays >= 100 then
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            -- 居中位置换算为左对齐：原中心点减去两位数时的半宽作为左起点
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, DATE_NUM_SIZE)
            local twoDigitW = nvgTextBounds(vg, 0, 0, "00")
            local leftX = DATE_NUM_X - twoDigitW * 0.5
            nvgFillColor(vg, nvgRGBA(0x33, 0x33, 0x33, 255))
            nvgText(vg, leftX, DATE_NUM_Y, dayStr, nil)
        else
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0x33, 0x33, 0x33, 255))
            nvgText(vg, DATE_NUM_X, DATE_NUM_Y, dayStr, nil)
        end
        nvgRestore(vg)
    end

    -- 17. 装饰线1 (黑色 10% 透明度, 圆角4)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, DECO1_CX - DECO1_W * 0.5, DECO1_CY - DECO1_H * 0.5,
        DECO1_W, DECO1_H, DECO1_ROUND)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)

    -- 18. 装饰线2 (标题下方, 黑色 10% 透明度, 圆角4)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, DECO2_CX - DECO2_W * 0.5, DECO2_CY - DECO2_H * 0.5,
        DECO2_W, DECO2_H, DECO2_ROUND)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 26))
    nvgFill(vg)

    -- 18b. 红点提示层（绘制在所有卡片之上，避免被遮挡）
    -- 红点偏移：从卡片右上角往里(左)移 RED_DOT_INSET，往下移 RED_DOT_DOWN
    local RED_DOT_INSET = 30   -- 往里偏移
    local RED_DOT_DOWN  = 30   -- 往下偏移
    if imgRedDot >= 0 then
        if SignInPanel.hasClaimable() then
            drawImageCentered(vg, imgRedDot,
                SIGNIN_CX + SIGNIN_W * 0.5 - RED_DOT_INSET,
                SIGNIN_CY - SIGNIN_H * 0.5 + RED_DOT_DOWN,
                RED_DOT_SIZE, RED_DOT_SIZE, 1.0)
        end
        if AnnouncementPanel.hasUnread() then
            drawImageCentered(vg, imgRedDot,
                NOTICE_CX + NOTICE_W * 0.5 - RED_DOT_INSET,
                NOTICE_CY - NOTICE_H * 0.5 + RED_DOT_DOWN,
                RED_DOT_SIZE, RED_DOT_SIZE, 1.0)
        end
        if TaskPanel.hasClaimable() then
            drawImageCentered(vg, imgRedDot,
                QUEST_CX + QUEST_W * 0.5 - RED_DOT_INSET,
                QUEST_CY - QUEST_H * 0.5 + RED_DOT_DOWN,
                RED_DOT_SIZE, RED_DOT_SIZE, 1.0)
        end
        if MailPanel.hasClaimable() then
            drawImageCentered(vg, imgRedDot,
                MAIL_CX + MAIL_W * 0.5 - RED_DOT_INSET,
                MAIL_CY - MAIL_H * 0.5 + RED_DOT_DOWN,
                RED_DOT_SIZE, RED_DOT_SIZE, 1.0)
        end
    end

    -- 19. 公告弹窗（覆盖在日志页面之上）
    AnnouncementPanel.draw(vg)

    -- 20. 邮件弹窗（覆盖在日志页面之上）
    MailPanel.draw(vg)

    -- 21. 签到面板（全屏覆盖）
    SignInPanel.draw(vg)

    -- 22. 背包面板（全屏覆盖）
    BackpackPanel.draw(vg)

    -- 23. 任务面板（全屏覆盖）
    TaskPanel.draw(vg)
end

--- 是否有全屏覆盖子面板打开（用于阻断头像等全局点击区域）
---@return boolean
function DiaryPage.hasOverlayOpen()
    return SignInPanel.isOpen()
        or BackpackPanel.isOpen()
        or TaskPanel.isOpen()
        or MailPanel.isOpen()
        or AnnouncementPanel.isOpen()
end

--- 任意子面板有可领取/未读内容
function DiaryPage.hasAnyClaimable()
    return SignInPanel.hasClaimable()
        or TaskPanel.hasClaimable()
        or MailPanel.hasClaimable()
        or AnnouncementPanel.hasUnread()
end

function DiaryPage.update(dt)
    AnnouncementPanel.update(dt)
    MailPanel.update(dt)
    SignInPanel.update(dt)
    BackpackPanel.update(dt)
    TaskPanel.update(dt)
end

--- 处理点击输入（设计空间坐标）
---@return boolean 是否消费了事件
function DiaryPage.handleInput(dx, dy)
    -- 任务面板打开时优先拦截
    if TaskPanel.isOpen() then
        return TaskPanel.handleInput(dx, dy)
    end
    -- 背包面板打开时优先拦截
    if BackpackPanel.isOpen() then
        return BackpackPanel.handleInput(dx, dy)
    end
    -- 签到面板打开时优先拦截
    if SignInPanel.isOpen() then
        return SignInPanel.handleInput(dx, dy)
    end
    -- 邮件弹窗打开时优先拦截
    if MailPanel.isOpen() then
        return MailPanel.handleInput(dx, dy)
    end
    -- 公告弹窗打开时优先拦截
    if AnnouncementPanel.isOpen() then
        return AnnouncementPanel.handleInput(dx, dy)
    end

    -- 签到卡片点击区域 → 打开签到面板
    if DrawUtil.hitTest(dx, dy, SIGNIN_CX, SIGNIN_CY, SIGNIN_W, SIGNIN_H) then
        BF.trigger("dp_signin")
        print("[DiaryPage] 签到 clicked → open SignInPanel")
        SignInPanel.open()
        return true
    end
    -- 公告卡片点击区域 → 打开公告弹窗
    if DrawUtil.hitTest(dx, dy, NOTICE_CX, NOTICE_CY, NOTICE_W, NOTICE_H) then
        BF.trigger("dp_notice")
        print("[DiaryPage] 公告 clicked → open AnnouncementPanel")
        AnnouncementPanel.open()
        return true
    end
    -- 背包卡片点击区域 → 打开背包面板
    if DrawUtil.hitTest(dx, dy, BAG_CX, BAG_CY, BAG_W, BAG_H) then
        BF.trigger("dp_bag")
        print("[DiaryPage] 背包 clicked → open BackpackPanel")
        BackpackPanel.open()
        return true
    end
    -- 任务卡片点击区域 → 打开任务面板
    if DrawUtil.hitTest(dx, dy, QUEST_CX, QUEST_CY, QUEST_W, QUEST_H) then
        BF.trigger("dp_quest")
        print("[DiaryPage] 任务 clicked → open TaskPanel")
        TaskPanel.open()
        return true
    end
    -- 邮件卡片点击区域 → 打开邮件弹窗
    if DrawUtil.hitTest(dx, dy, MAIL_CX, MAIL_CY, MAIL_W, MAIL_H) then
        BF.trigger("dp_mail")
        print("[DiaryPage] 邮件 clicked → open MailPanel")
        MailPanel.open()
        return true
    end

    return false
end

-- ======================== 拖拽/滚轮转发 ========================

function DiaryPage.handleDragBegin(dx, dy)
    if TaskPanel.isOpen() then
        return TaskPanel.handleDragBegin(dx, dy)
    end
    if BackpackPanel.isOpen() then
        return BackpackPanel.handleDragBegin(dx, dy)
    end
    if SignInPanel.isOpen() then
        return SignInPanel.handleDragBegin(dx, dy)
    end
    if MailPanel.isOpen() then
        return MailPanel.handleDragBegin(dx, dy)
    end
    if AnnouncementPanel.isOpen() then
        return AnnouncementPanel.handleDragBegin(dx, dy)
    end
    return false
end

function DiaryPage.handleDragMove(dx, dy)
    if TaskPanel.isOpen() then
        return TaskPanel.handleDragMove(dx, dy)
    end
    if BackpackPanel.isOpen() then
        return BackpackPanel.handleDragMove(dx, dy)
    end
    if SignInPanel.isOpen() then
        return SignInPanel.handleDragMove(dx, dy)
    end
    if MailPanel.isOpen() then
        return MailPanel.handleDragMove(dx, dy)
    end
    if AnnouncementPanel.isOpen() then
        return AnnouncementPanel.handleDragMove(dx, dy)
    end
    return false
end

function DiaryPage.handleDragEnd(dx, dy)
    if TaskPanel.isOpen() then
        return TaskPanel.handleDragEnd(dx, dy)
    end
    if BackpackPanel.isOpen() then
        return BackpackPanel.handleDragEnd(dx, dy)
    end
    if SignInPanel.isOpen() then
        return SignInPanel.handleDragEnd(dx, dy)
    end
    if MailPanel.isOpen() then
        return MailPanel.handleDragEnd(dx, dy)
    end
    if AnnouncementPanel.isOpen() then
        return AnnouncementPanel.handleDragEnd(dx, dy)
    end
    return false
end

function DiaryPage.handleScroll(wheel)
    if TaskPanel.isOpen() then
        return TaskPanel.handleScroll(wheel)
    end
    if BackpackPanel.isOpen() then
        return BackpackPanel.handleScroll(wheel)
    end
    if SignInPanel.isOpen() then
        return SignInPanel.handleScroll(wheel)
    end
    if MailPanel.isOpen() then
        return MailPanel.handleScroll(wheel)
    end
    if AnnouncementPanel.isOpen() then
        return AnnouncementPanel.handleScroll(wheel)
    end
    return false
end

return DiaryPage
