-- ============================================================================
-- ArenaOpponentDialog - 竞技场选择对手弹窗
-- 点击"开始对战"后弹出，显示4个可挑战对手 + 刷新按钮
-- 数据来源：ArenaPage 传入的排名列表（服务器真实数据）
-- ============================================================================

local GameConfig = require("config.GameConfig")
local GameState  = require("core.GameState")
local drawTextStroke = require("core.DrawUtil").drawTextStroke
local CharacterPanel = require("ui.CharacterPanel")
local ArenaConfig = require("config.ArenaConfig")
local TopBar      = require("ui.TopBar")
local Protocol    = require("shared.Protocol")
-- Client 延迟加载，避免循环依赖（Client → ArenaPage → ArenaOpponentDialog → Client）
local HeroConfig  = require("config.HeroConfig")
local HeroAssetUtil   = require("config.HeroAssetUtil")
local AvatarFrameUtil = require("config.AvatarFrameUtil")
local EquipmentSystem = require("systems.EquipmentSystem")
local TalentEffect    = require("systems.TalentEffect")
local AD              = require("systems.AttributeDef")
local BF              = require("systems.ButtonFeedback")
local RelicBridge     = require("systems.RelicBridge")
local AvatarFrameBridge = require("systems.AvatarFrameBridge")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

local Dialog = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 弹窗主体
local D = {
    -- 遮罩
    OVL_A = 128,  -- 50% 不透明度
    -- 弹窗背景框（九宫格）
    BG_CX = 540, BG_CY = 1085, BG_W = 950, BG_H = 1399,
    BG_IT = 180, BG_IR = 40, BG_IB = 50, BG_IL = 40,
    -- 标题
    TT_CX = 540, TT_CY = 454, TT_FONT = 60, TT_SW = 6,
    TT_SR = 0x59, TT_SG = 0x32, TT_SB = 0x19,
    -- 挑战券资源栏
    TK_BG_CX = 710, TK_BG_CY = 564, TK_BG_W = 170, TK_BG_H = 47, TK_BG_R = 18, TK_BG_A = 26,
    TK_IC_CX = 646, TK_IC_CY = 564, TK_IC_W = 70, TK_IC_H = 70,
    TK_TX = 730, TK_TY = 565, TK_FONT = 33, TK_SW = 4,
    -- 战斗力资源栏
    PW_BG_CX = 904, PW_BG_CY = 564, PW_BG_W = 170, PW_BG_H = 47, PW_BG_R = 18, PW_BG_A = 26,
    PW_IW = 44, PW_IH = 44, PW_FONT = 30, PW_SW = 4,
    PW_R = 0xf7, PW_G = 0xfe, PW_B = 0x77,
    -- 内容底框
    CB_CX = 540, CB_CY = 1100, CB_R = 16, CB_W = 900, CB_H = 980, CB_A = 13,
    -- 刷新按钮
    RF_CX = 540, RF_CY = 1663, RF_W = 410, RF_H = 100,
    RF_FONT = 40, RF_R = 0x1d, RF_G = 0x50, RF_B = 0x37,
}

-- 对手条目布局
---@type table
local OPP = {
    CY1 = 739, STEP = 238, COUNT = 4,
    BG_CX = 540, BG_W = 870, BG_H = 220,
    -- 头像
    AV_CX = 193, AV_DY = -25, AV_W = 128, AV_H = 128,
    -- 名称
    NM_X = 281, NM_DY = -46, NM_FONT = 38, NM_SW = 4,
    -- 战斗力
    PW_X = 281, PW_DY = 5, PW_IW = 44, PW_IH = 44, PW_FONT = 30, PW_SW = 4,
    PW_R = 0xf7, PW_G = 0xfe, PW_B = 0x77,
    -- 小组分图标+文本
    GS_IC_CX = 426, GS_DY = 5, GS_IC_W = 50, GS_IC_H = 50,
    GS_TX = 453, GS_FONT = 30, GS_SW = 4,
    -- 挑战按钮
    CB_CX = 815, CB_DY = -25, CB_W = 270, CB_H = 122,
    CT_CX = 815, CT_DY = -49, CT_FONT = 38, CT_SW = 4,
    CI_CX = 795, CI_DY = -2, CI_W = 44, CI_H = 44,
    CC_X = 837, CC_DY = -1, CC_FONT = 32,
    CC_R = 0x6a, CC_G = 0x56, CC_B = 0x2c,
    -- 胜利/失败行
    WL_DY = 77,
    W_LBL_X = 173, W_LBL_R = 0x16, W_LBL_G = 0x45, W_LBL_B = 0x44,
    W_IC_CX = 249, W_IC_W = 50, W_IC_H = 50,
    W_VAL_X = 277, W_VAL_R = 0x90, W_VAL_G = 0xff, W_VAL_B = 0x8a,
    L_LBL_X = 787,
    L_IC_CX = 862, L_IC_W = 50, L_IC_H = 50,
    L_VAL_X = 890, L_VAL_R = 0xff, L_VAL_G = 0x77, L_VAL_B = 0x77,
    WL_FONT = 30, WL_SW = 4,
}

-- ======================== 图片句柄 ========================

local img = {
    bg = -1, ticketIcon = -1, powerIcon = -1,
    oppBg = -1, challengeBtn = -1, refreshBtn = -1,
    costIcon = -1, groupScoreIcon = -1,
    heroIcons = {},  -- 角色头像图标
    frameIcons = {},  -- [frameId] 头像框
}

-- ======================== 弹窗动画常量 ========================

local POPUP_OPEN_DUR   = 0.25
local POPUP_CLOSE_DUR  = 0.20
local POPUP_SCALE_FROM = 0.8
local POPUP_SCALE_TO   = 1.0

-- 刷新动画常量
local REFRESH_OUT_DUR  = 0.18   -- 旧对手滑出时长
local REFRESH_IN_DUR   = 0.22   -- 新对手滑入时长

-- ======================== 缓动函数 ========================

local function easeOutCubic(t) local f = t - 1; return f * f * f + 1 end
local function easeInCubic(t) return t * t * t end

-- ======================== 状态 ========================

local state = {
    open = false,
    opponents = {},      -- 当前展示的对手列表（最多4个）
    allRankings = {},    -- ArenaPage 传入的完整排名列表
    myRankData = nil,    -- 我的排名数据 { rank, name, power, tier, score }
    waitingOpponent = false,  -- 是否正在等待服务器返回对手防守阵容
    pendingTargetUid = nil,   -- 正在请求的对手 uid
    pendingTargetName = nil,  -- 正在请求的对手名称
    -- 弹窗动画
    popupAnimTime  = 0,
    popupClosing   = false,
    popupCloseTime = 0,
    -- 刷新动画
    refreshPhase   = "none",   -- "none" | "out" | "in"
    refreshTime    = 0,
    refreshPending = {},       -- 新对手列表（滑出完成后替换）
}

-- ======================== 工具函数 ========================

local function drawImageCentered(vg, imgH, cx, cy, w, h, alpha)
    if imgH < 0 or alpha <= 0.01 then return end
    local x, y = cx - w * 0.5, cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, imgH, alpha)
    nvgBeginPath(vg); nvgRect(vg, x, y, w, h); nvgFillPaint(vg, paint); nvgFill(vg)
end

local function drawNineSlice(vg, imgH, dx, dy, dw, dh, iTop, iRight, iBottom, iLeft)
    if imgH < 0 then return end
    local srcW, srcH = nvgImageSize(vg, imgH)
    if srcW <= 0 or srcH <= 0 then return end
    local sL, sR, sT, sB = iLeft, iRight, iTop, iBottom
    local sMW, sMH = srcW - sL - sR, srcH - sT - sB
    local dL = math.min(iLeft, dw * 0.5)
    local dR = math.min(iRight, dw * 0.5)
    local dT = math.min(iTop, dh * 0.5)
    local dB = math.min(iBottom, dh * 0.5)
    if sMW <= 0 or sMH <= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, imgH, 1.0)
        nvgBeginPath(vg); nvgRect(vg, dx, dy, dw, dh); nvgFillPaint(vg, paint); nvgFill(vg)
        return
    end
    local ix0 = math.floor(dx + 0.5)
    local iy0 = math.floor(dy + 0.5)
    local ix1 = math.floor(dx + dL + 0.5)
    local iy1 = math.floor(dy + dT + 0.5)
    local ix2 = math.floor(dx + dw - dR + 0.5)
    local iy2 = math.floor(dy + dh - dB + 0.5)
    local ix3 = math.floor(dx + dw + 0.5)
    local iy3 = math.floor(dy + dh + 0.5)
    local OV = 1
    local patches = {
        { ix1-OV, iy1-OV, ix2-ix1+OV*2, iy2-iy1+OV*2, sL, sT, sMW, sMH },
        { ix1-OV, iy0,    ix2-ix1+OV*2, iy1-iy0+OV,   sL, 0,  sMW, sT  },
        { ix1-OV, iy2-OV, ix2-ix1+OV*2, iy3-iy2+OV,   sL, sT+sMH, sMW, sB  },
        { ix0,    iy1-OV, ix1-ix0+OV,   iy2-iy1+OV*2, 0,  sT, sL,  sMH },
        { ix2-OV, iy1-OV, ix3-ix2+OV,   iy2-iy1+OV*2, sL+sMW, sT, sR, sMH },
        { ix0,    iy0,    ix1-ix0+OV, iy1-iy0+OV, 0,      0,      sL, sT },
        { ix2-OV, iy0,    ix3-ix2+OV, iy1-iy0+OV, sL+sMW, 0,      sR, sT },
        { ix0,    iy2-OV, ix1-ix0+OV, iy3-iy2+OV, 0,      sT+sMH, sL, sB },
        { ix2-OV, iy2-OV, ix3-ix2+OV, iy3-iy2+OV, sL+sMW, sT+sMH, sR, sB },
    }
    nvgShapeAntiAlias(vg, 0)
    for _, p in ipairs(patches) do
        local px, py, pw, ph = p[1], p[2], p[3], p[4]
        local sx, sy, sw, sh = p[5], p[6], p[7], p[8]
        if pw > 0 and ph > 0 and sw > 0 and sh > 0 then
            local scX, scY = pw / sw, ph / sh
            local paint = nvgImagePattern(vg, px - sx * scX, py - sy * scY,
                srcW * scX, srcH * scY, 0, imgH, 1.0)
            nvgBeginPath(vg); nvgRect(vg, px, py, pw, ph); nvgFillPaint(vg, paint); nvgFill(vg)
        end
    end
    nvgShapeAntiAlias(vg, 1)
end

local function formatPower(val)
    if val < 10000 then return tostring(val) end
    local k = val / 1000
    if k == math.floor(k) then return string.format("%dK", k) end
    return string.format("%.1fK", k)
end

local function hitTest(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

-- ======================== 对手选取逻辑 ========================

--- 从排名列表中选取最多4个对手（排除自己）
---@param rankings table 完整排名列表
---@param myRankData table 我的排名数据
---@return table opponents 对手列表（含 winPts/losePts）
local function pickOpponents(rankings, myRankData)
    local myUid = myRankData and myRankData.uid or nil
    local myRank = myRankData and myRankData.rank or 999

    -- 过滤掉自己
    local candidates = {}
    for _, r in ipairs(rankings) do
        if r.uid ~= myUid then
            candidates[#candidates + 1] = r
        end
    end

    -- 打乱顺序后取前4个
    for i = #candidates, 2, -1 do
        local j = math.random(1, i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    local list = {}
    for i = 1, math.min(OPP.COUNT, #candidates) do
        local r = candidates[i]
        local oppRank = r.rank or 999
        local rankDiff = myRank - oppRank  -- 正数=以下克上
        local scoring = ArenaConfig.getAttackScoring(rankDiff)
        list[i] = {
            uid          = r.uid,
            name         = r.name or ("玩家" .. i),
            power        = r.power or 0,
            score        = r.score or 0,
            rank         = oppRank,
            winPts       = scoring.winScore,
            losePts      = math.abs(scoring.loseScore),
            avatarHeroId = r.avatarHeroId or 1,
        }
    end
    return list
end

-- ======================== 从防守快照构建敌方单位 ========================

--- 根据服务器返回的防守阵容快照，构建可用于战斗的敌方单位列表
---@param defense table 防守快照 { heroes, equipment, talents, power, timestamp }
---@return table enemies 单位列表
local function buildEnemyUnits(defense)
    local enemies = {}
    if not defense or not defense.heroes then return enemies end

    -- 暂存并清除本地玩家天赋，防止 createHero 内部叠加本地天赋到敌方单位
    local savedLitNodes = HeroConfig._getSavedLitNodes and HeroConfig._getSavedLitNodes()
    HeroConfig.setDefaultLitNodes(nil)

    for seq, heroData in ipairs(defense.heroes) do
        -- 1. 创建基础英雄单位（不会应用任何天赋星图，因为已清除）
        local unit = HeroConfig.createHero(heroData.heroId, heroData.level, heroData.advBranch, heroData.awakening)
        if unit then
            -- 2. 应用装备加成（使用 seq*100+slotIdx 生成唯一 modifierId，避免同英雄多槽位覆盖）
            local equipMap = nil
            if defense.equipment then
                equipMap = defense.equipment[heroData.heroId]
                -- cjson 序列化将 numeric key 转为了 string key，兜底查找
                if not equipMap then
                    equipMap = defense.equipment[tostring(heroData.heroId)]
                end
            end
            local slotEnhanceData = defense.slotEnhance
            -- cjson 序列化将 numeric key 转为了 string key，归一化 partySlot 索引
            if slotEnhanceData and slotEnhanceData.levels then
                local fixedLevels = {}
                for k, v in pairs(slotEnhanceData.levels) do
                    local numK = tonumber(k)
                    if numK then fixedLevels[numK] = v else fixedLevels[k] = v end
                end
                slotEnhanceData.levels = fixedLevels
            end
            -- cjson 序列化将 numeric key 转为了 string key，归一化 partySlot 索引
            if slotEnhanceData and slotEnhanceData.levels then
                local fixedLevels = {}
                for k, v in pairs(slotEnhanceData.levels) do
                    local numK = tonumber(k)
                    if numK then fixedLevels[numK] = v else fixedLevels[k] = v end
                end
                slotEnhanceData.levels = fixedLevels
            end
            if equipMap then
                local slotIdx = 0
                for slot, equipData in pairs(equipMap) do
                    slotIdx = slotIdx + 1
                    local uniqueSeq = seq * 100 + slotIdx
                    -- seq 即为 partySlot（heroSnap 按 deployed 顺序构建）
                    local slotBoost = 0
                    if slotEnhanceData then
                        slotBoost = EquipmentSystem.calcSlotBoost(slotEnhanceData, seq, slot, equipData.grip)
                    end
                    EquipmentSystem.applyToUnit(unit.attrs, equipData, uniqueSeq, slotBoost)
                end
            end

            -- 3. 应用敌方天赋加成
            if defense.talents and defense.talents.litNodes then
                -- cjson 反序列化后数组元素可能变为字符串，修正为 number
                for i, nodeId in ipairs(defense.talents.litNodes) do
                    defense.talents.litNodes[i] = tonumber(nodeId) or nodeId
                end
                -- cjson 反序列化后数组元素可能变为字符串，修正为 number
                for i, nodeId in ipairs(defense.talents.litNodes) do
                    defense.talents.litNodes[i] = tonumber(nodeId) or nodeId
                end
                TalentEffect.applyToUnit(unit.attrs, defense.talents.litNodes, unit.classId)
                -- 填充 litNodeSet 供 TalentManager RUNTIME_ONLY 节点检查
                for _, nodeId in ipairs(defense.talents.litNodes) do
                    unit.litNodeSet[nodeId] = true
                end
            end

            -- 3.5. 应用敌方遗物加成（从快照 grid 还原属性）
            if defense.relicGrid and #defense.relicGrid > 0 then
                local relicConds = RelicBridge.applyFromGrid(unit.attrs, unit.classId, defense.relicGrid)
                if relicConds and #relicConds > 0 then
                    unit.relicConditions = relicConds
                end
            end

            -- 3.6. 应用对手防守快照中的头像框永久收藏属性
            AvatarFrameBridge.applyToUnit(unit.attrs, defense.unlockedAvatarFrames)

            -- 4. 装备、天赋和收藏可能增加 maxHp，重新满血
            unit.attrs:fillHp()
            unit.maxHp = unit.attrs.final[AD.MAX_HP]
            unit.hp    = unit.attrs.final[AD.HP]
            unit.atkInterval = unit.attrs:getActualInterval()

            -- 5. 初始化战斗属性
            unit.atkProgress = 0

            enemies[#enemies + 1] = unit
        end
    end

    -- 恢复本地玩家天赋
    HeroConfig.setDefaultLitNodes(savedLitNodes)

    print("[ArenaOpponentDialog] 构建敌方单位 " .. #enemies .. " 个")
    return enemies
end

-- ======================== 对手条目绘制 ========================

local function drawOpponentEntry(vg, cy, data, oppIdx)
    -- 背景
    drawImageCentered(vg, img.oppBg, OPP.BG_CX, cy, OPP.BG_W, OPP.BG_H, 1.0)

    -- 头像（灰色底 → 头像图 → 头像框）
    local avCY = cy + OPP.AV_DY
    local avR = math.floor(OPP.AV_W * 0.15)
    -- 始终先画灰色底作为底层背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, OPP.AV_CX - OPP.AV_W * 0.5, avCY - OPP.AV_H * 0.5,
        OPP.AV_W, OPP.AV_H, avR)
    nvgFillColor(vg, nvgRGBA(80, 80, 80, 180))
    nvgFill(vg)
    local avatarHeroId = (data and data.avatarHeroId) or 1
    local avatarImg = img.heroIcons[avatarHeroId] or img.heroIcons[1]
    if avatarImg and avatarImg >= 0 then
        nvgSave(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, OPP.AV_CX - OPP.AV_W * 0.5, avCY - OPP.AV_H * 0.5,
            OPP.AV_W, OPP.AV_H, avR)
        local paint = nvgImagePattern(vg, OPP.AV_CX - OPP.AV_W * 0.5, avCY - OPP.AV_H * 0.5,
            OPP.AV_W, OPP.AV_H, 0, avatarImg, 1.0)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    end
    -- 头像框覆盖层
    local avatarFrameId = (data and data.avatarFrameId) or 1
    local frameImg = AvatarFrameUtil.getIconHandle(img.frameIcons, avatarFrameId)
    drawImageCentered(vg, frameImg, OPP.AV_CX, avCY, 160, 160, 1.0)

    -- 名称
    local nmCY = cy + OPP.NM_DY
    drawTextStroke(vg, OPP.NM_X, nmCY, data.name,
        OPP.NM_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, OPP.NM_SW,
        { strokeColor = { 0x23, 0x23, 0x23 } })

    -- 战斗力图标+数值
    local pwCY = cy + OPP.PW_DY
    drawImageCentered(vg, img.powerIcon, OPP.PW_X + OPP.PW_IW * 0.5, pwCY,
        OPP.PW_IW, OPP.PW_IH, 1.0)
    local pwText = formatPower(data.power)
    local pwTextX = OPP.PW_X + OPP.PW_IW + 4
    drawTextStroke(vg, pwTextX, pwCY, pwText,
        OPP.PW_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        OPP.PW_R, OPP.PW_G, OPP.PW_B, OPP.PW_SW,
        { strokeColor = { 0x23, 0x23, 0x23 } })

    -- 测量战斗力文本宽度，自适应小组分位置
    nvgFontFace(vg, "sans"); nvgFontSize(vg, OPP.PW_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local pwTextW = nvgTextBounds(vg, 0, 0, pwText, nil, {})
    local pwEndX = pwTextX + pwTextW
    local gsGap = 8
    local gsIconCX = math.max(OPP.GS_IC_CX, pwEndX + gsGap + OPP.GS_IC_W * 0.5)

    -- 小组分图标（自适应位置）
    local gsCY = cy + OPP.GS_DY
    drawImageCentered(vg, img.groupScoreIcon, gsIconCX, gsCY, OPP.GS_IC_W, OPP.GS_IC_H, 1.0)

    -- 小组分文本（跟随图标）
    local gsTX = gsIconCX + OPP.GS_IC_W * 0.5 + 3
    drawTextStroke(vg, gsTX, gsCY, tostring(data.score),
        OPP.GS_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, OPP.GS_SW,
        { strokeColor = { 0x23, 0x23, 0x23 } })

    -- 挑战按钮背景
    local cbCY = cy + OPP.CB_DY
    local _bfC = BF.begin(vg, "aod_challenge_" .. tostring(oppIdx), OPP.CB_CX, cbCY, OPP.CB_W, OPP.CB_H)
    drawImageCentered(vg, img.challengeBtn, OPP.CB_CX, cbCY, OPP.CB_W, OPP.CB_H, 1.0)

    -- 挑战按钮文本
    local ctCY = cy + OPP.CT_DY
    drawTextStroke(vg, OPP.CT_CX, ctCY, "挑战",
        OPP.CT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, OPP.CT_SW,
        { strokeColor = { 0, 0, 0 } })

    -- 挑战按钮-挑战券图标
    local ciCY = cy + OPP.CI_DY
    drawImageCentered(vg, img.costIcon, OPP.CI_CX, ciCY, OPP.CI_W, OPP.CI_H, 1.0)

    -- 消耗文本 "×1"
    local ccCY = cy + OPP.CC_DY
    nvgFontFace(vg, "sans"); nvgFontSize(vg, OPP.CC_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(OPP.CC_R, OPP.CC_G, OPP.CC_B, 255))
    nvgText(vg, OPP.CC_X, ccCY, "×1", nil)
    BF.finish(vg, _bfC)
    -- 引导组13第二步已移除，不再强制高亮第一个对手（玩家自由挑选）

    -- ========== 胜利/失败行（左对齐固定位置） ==========
    local wlCY = cy + OPP.WL_DY
    local iconGap = 2

    local wValStr = "+" .. tostring(data.winPts)
    local lValStr = "-" .. tostring(data.losePts)

    -- 胜利组：左对齐 X=138
    local wX = 138
    nvgFontFace(vg, "sans"); nvgFontSize(vg, OPP.WL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(OPP.W_LBL_R, OPP.W_LBL_G, OPP.W_LBL_B, 255))
    nvgText(vg, wX, wlCY, "胜利：", nil)
    local wLabelW = nvgTextBounds(vg, 0, 0, "胜利：", nil, {})
    drawImageCentered(vg, img.groupScoreIcon,
        wX + wLabelW + iconGap + OPP.W_IC_W * 0.5, wlCY,
        OPP.W_IC_W, OPP.W_IC_H, 1.0)
    drawTextStroke(vg, wX + wLabelW + iconGap + OPP.W_IC_W + iconGap, wlCY,
        wValStr, OPP.WL_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        OPP.W_VAL_R, OPP.W_VAL_G, OPP.W_VAL_B, OPP.WL_SW,
        { strokeColor = { 0, 0, 0 } })

    -- 失败组：左对齐 X=752（标签颜色与胜利相同）
    local lX = 752
    nvgFontFace(vg, "sans"); nvgFontSize(vg, OPP.WL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(OPP.W_LBL_R, OPP.W_LBL_G, OPP.W_LBL_B, 255))
    nvgText(vg, lX, wlCY, "失败：", nil)
    local lLabelW = nvgTextBounds(vg, 0, 0, "失败：", nil, {})
    drawImageCentered(vg, img.groupScoreIcon,
        lX + lLabelW + iconGap + OPP.L_IC_W * 0.5, wlCY,
        OPP.L_IC_W, OPP.L_IC_H, 1.0)
    drawTextStroke(vg, lX + lLabelW + iconGap + OPP.L_IC_W + iconGap, wlCY,
        lValStr, OPP.WL_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        OPP.L_VAL_R, OPP.L_VAL_G, OPP.L_VAL_B, OPP.WL_SW,
        { strokeColor = { 0, 0, 0 } })
end

-- ======================== Public API ========================

function Dialog.init(vg)
    img.bg          = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    img.ticketIcon  = nvgCreateImage(vg, "image/UI_icon_JJCQ_X.png", 0)
    img.powerIcon   = nvgCreateImage(vg, "image/ICON_ZDL.png", 0)
    img.oppBg       = nvgCreateImage(vg, "image/UI_JJC_3.png", 0)
    img.challengeBtn = nvgCreateImage(vg, "image/UI_AN_FANG.png", 0)
    img.refreshBtn  = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    img.costIcon    = nvgCreateImage(vg, "image/UI_icon_JJCQ_X.png", 0)
    img.groupScoreIcon = nvgCreateImage(vg, "image/UI_icon_JJCFS_X.png", 0)
    HeroAssetUtil.preloadIcons(vg, img.heroIcons)
    AvatarFrameUtil.preloadFrames(vg, img.frameIcons)

    print("[ArenaOpponentDialog] init OK")
end

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

--- 打开选择对手弹窗
---@param rankings table 完整排名列表（来自 ArenaPage）
---@param myRankData table 我的排名数据
function Dialog.open(rankings, myRankData, tickets)
    state.open = true
    state.allRankings = rankings or {}
    state.myRankData = myRankData
    state.tickets = tickets or 0
    state.waitingOpponent = false
    state.pendingTargetUid = nil
    state.pendingTargetName = nil
    state.popupAnimTime = time.elapsedTime
    state.popupClosing = false
    state.refreshPhase = "none"
    state.opponents = pickOpponents(state.allRankings, state.myRankData)
    print("[ArenaOpponentDialog] 打开选择对手弹窗, 候选 " .. #state.opponents .. " 人, 剩余竞技券=" .. state.tickets)
end

function Dialog.close()
    if state.popupClosing then return end
    state.popupClosing = true
    state.popupCloseTime = time.elapsedTime
    state.waitingOpponent = false
    state.pendingTargetUid = nil
    state.pendingTargetName = nil
    print("[ArenaOpponentDialog] 关闭选择对手弹窗（动画中）")
end

--- 直接关闭（跳过动画，用于战斗进入等场景）
function Dialog.closeImmediate()
    state.open = false
    state.popupClosing = false
    state.waitingOpponent = false
    state.pendingTargetUid = nil
    state.pendingTargetName = nil
end

function Dialog.isOpen()
    return state.open
end

--- 处理服务器返回的 ARENA_GET_OPPONENT 结果
function Dialog.onActionResult(data)
    -- 失败响应（无 defense 字段）：重置等待状态，避免卡在"获取对手阵容中..."
    if data.success == false and state.waitingOpponent then
        state.waitingOpponent = false
        print("[ArenaOpponentDialog] 操作失败: " .. tostring(data.reason))
        return
    end

    -- ARENA_GET_OPPONENT 响应：包含 defense 字段
    if data.defense ~= nil and state.waitingOpponent then
        state.waitingOpponent = false

        if not data.success then
            print("[ArenaOpponentDialog] 获取对手阵容失败: " .. tostring(data.error))
            return
        end

        -- 从防守快照构建敌方单位
        local enemies = buildEnemyUnits(data.defense)

        -- 获取己方队伍
        local allies = CharacterPanel.getDeployedTeam()

        -- 竞技券由 PlayerStore 代理，无需写入 GameState

        -- 打开竞技场对战界面
        local okBattle, ArenaBattleScene = pcall(require, "ui.ArenaBattleScene")
        if not okBattle or not ArenaBattleScene or not ArenaBattleScene.open then
            print("[ArenaOpponentDialog] ArenaBattleScene 加载失败: " .. tostring(ArenaBattleScene))
            return
        end
        ArenaBattleScene.open({
            myName    = GameState.getName() or "我方玩家",
            enemyName = state.pendingTargetName or "对手",
            allies    = allies,
            enemies   = enemies,
            targetUid = state.pendingTargetUid,
            duration  = GameConfig.Battle.TIME_LIMIT_SEC,
            onSurrender = function()
                print("[ArenaOpponentDialog] 投降")
                ArenaBattleScene.close()
            end,
            onTimeout = function()
                print("[ArenaOpponentDialog] 超时 → 判负")
                ArenaBattleScene.close()
            end,
        })

        -- 关闭对手选择弹窗（跳过动画，直接进入战斗）
        Dialog.closeImmediate()

        print("[ArenaOpponentDialog] 对手阵容已获取, 进入战斗. targetUid=" .. tostring(state.pendingTargetUid))
    end
end

function Dialog.update(dt)
    if not state.open then return end

    -- 关闭动画完成检测
    if state.popupClosing then
        local _, _, done = getPopupAnim()
        if done then
            state.popupClosing = false
            state.open = false
        end
    end

    -- 刷新动画推进
    if state.refreshPhase == "out" then
        local elapsed = time.elapsedTime - state.refreshTime
        if elapsed >= REFRESH_OUT_DUR then
            -- 滑出完成，替换数据并开始滑入
            state.opponents = state.refreshPending
            state.refreshPending = {}
            state.refreshPhase = "in"
            state.refreshTime = time.elapsedTime
        end
    elseif state.refreshPhase == "in" then
        local elapsed = time.elapsedTime - state.refreshTime
        if elapsed >= REFRESH_IN_DUR then
            state.refreshPhase = "none"
        end
    end
end

function Dialog.draw(vg)
    if not state.open then return end

    -- 弹窗动画参数
    local pScale, pAlpha, _ = getPopupAnim()

    -- 1. 全屏黑色遮罩（alpha 跟随动画）
    nvgBeginPath(vg); nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(D.OVL_A * pAlpha))); nvgFill(vg)

    -- 弹窗内容整体应用 scale + fade
    nvgSave(vg)
    nvgTranslate(vg, DESIGN_W * 0.5, DESIGN_H * 0.5)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -DESIGN_W * 0.5, -DESIGN_H * 0.5)
    nvgGlobalAlpha(vg, pAlpha)

    -- 2. 弹窗背景框（九宫格）
    DarkIcon.drawNine(vg, "panel", D.BG_CX - D.BG_W * 0.5, D.BG_CY - D.BG_H * 0.5, D.BG_W, D.BG_H, { titleH = D.BG_IT })

    -- 3. 标题 "选择对手"
    drawTextStroke(vg, D.TT_CX, D.TT_CY, "选择对手",
        D.TT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, D.TT_SW,
        { strokeColor = { D.TT_SR, D.TT_SG, D.TT_SB } })

    -- 4. 挑战券资源栏背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, D.TK_BG_CX - D.TK_BG_W * 0.5, D.TK_BG_CY - D.TK_BG_H * 0.5,
        D.TK_BG_W, D.TK_BG_H, D.TK_BG_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, D.TK_BG_A)); nvgFill(vg)

    -- 5. 挑战券图标
    drawImageCentered(vg, img.ticketIcon, D.TK_IC_CX, D.TK_IC_CY, D.TK_IC_W, D.TK_IC_H, 1.0)

    -- 6. 挑战券数量
    drawTextStroke(vg, D.TK_TX, D.TK_TY, tostring(state.tickets or 0),
        D.TK_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, D.TK_SW,
        { strokeColor = { 0x23, 0x23, 0x23 } })

    -- 7. 战斗力资源栏背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, D.PW_BG_CX - D.PW_BG_W * 0.5, D.PW_BG_CY - D.PW_BG_H * 0.5,
        D.PW_BG_W, D.PW_BG_H, D.PW_BG_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, D.PW_BG_A)); nvgFill(vg)

    -- 8. 战斗力图标+数值（居中于背景）
    local pwVal = CharacterPanel.getTotalPower and CharacterPanel.getTotalPower() or 0
    local pwStr = formatPower(pwVal)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, D.PW_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local bounds = {}
    local textW = nvgTextBounds(vg, 0, 0, pwStr, nil, bounds)
    local totalW = D.PW_IW + 4 + textW
    local startX = D.PW_BG_CX - totalW * 0.5
    drawImageCentered(vg, img.powerIcon, startX + D.PW_IW * 0.5, D.PW_BG_CY,
        D.PW_IW, D.PW_IH, 1.0)
    drawTextStroke(vg, startX + D.PW_IW + 4, D.PW_BG_CY, pwStr,
        D.PW_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        D.PW_R, D.PW_G, D.PW_B, D.PW_SW,
        { strokeColor = { 0x23, 0x23, 0x23 } })

    -- 9. 内容底框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, D.CB_CX - D.CB_W * 0.5, D.CB_CY - D.CB_H * 0.5,
        D.CB_W, D.CB_H, D.CB_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, D.CB_A)); nvgFill(vg)

    -- 10. 4个对手条目（带刷新动画偏移）
    local refreshOffsetX = 0
    if state.refreshPhase == "out" then
        local t = math.min(1.0, (time.elapsedTime - state.refreshTime) / REFRESH_OUT_DUR)
        refreshOffsetX = easeInCubic(t) * DESIGN_W  -- 向右滑出
    elseif state.refreshPhase == "in" then
        local t = math.min(1.0, (time.elapsedTime - state.refreshTime) / REFRESH_IN_DUR)
        refreshOffsetX = (1.0 - easeOutCubic(t)) * (-DESIGN_W)  -- 从左滑入
    end

    if refreshOffsetX ~= 0 then
        nvgSave(vg)
        nvgTranslate(vg, refreshOffsetX, 0)
    end
    for i, opp in ipairs(state.opponents) do
        local cy = OPP.CY1 + (i - 1) * OPP.STEP
        drawOpponentEntry(vg, cy, opp, i)
    end
    if refreshOffsetX ~= 0 then
        nvgRestore(vg)
    end

    -- 11. 刷新按钮
    local _bfR = BF.begin(vg, "aod_refresh", D.RF_CX, D.RF_CY, D.RF_W, D.RF_H)
    drawImageCentered(vg, img.refreshBtn, D.RF_CX, D.RF_CY, D.RF_W, D.RF_H, 1.0)

    -- 12. 刷新文本
    nvgFontFace(vg, "sans"); nvgFontSize(vg, D.RF_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(D.RF_R, D.RF_G, D.RF_B, 255))
    nvgText(vg, D.RF_CX, D.RF_CY, "刷新", nil)
    BF.finish(vg, _bfR)

    -- 13. 等待状态提示（半透明遮罩）
    if state.waitingOpponent then
        nvgBeginPath(vg); nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 100)); nvgFill(vg)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, DESIGN_W * 0.5, DESIGN_H * 0.5, "获取对手阵容中...", nil)
    end

    nvgRestore(vg)  -- 恢复弹窗 scale+fade 变换
end

-- ======================== 输入处理 ========================

function Dialog.handleInput(dx, dy)
    if not state.open then return false end

    -- 关闭动画中阻断所有输入
    if state.popupClosing then return true end

    -- 等待服务器响应时不处理输入
    if state.waitingOpponent then return true end

    -- 刷新动画中阻断输入
    if state.refreshPhase ~= "none" then return true end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.popupAnimTime < 0.05 then return true end

    -- 点击弹窗外部区域关闭
    if not hitTest(dx, dy, D.BG_CX, D.BG_CY, D.BG_W, D.BG_H) then
        Dialog.close()
        return true
    end

    -- 刷新按钮 → 启动刷新动画
    if hitTest(dx, dy, D.RF_CX, D.RF_CY, D.RF_W, D.RF_H) then
        BF.trigger("aod_refresh")
        state.refreshPending = pickOpponents(state.allRankings, state.myRankData)
        state.refreshPhase = "out"
        state.refreshTime = time.elapsedTime
        print("[ArenaOpponentDialog] 刷新对手列表（动画）")
        return true
    end

    -- 挑战按钮（逐个检测）
    for i, opp in ipairs(state.opponents) do
        local cy = OPP.CY1 + (i - 1) * OPP.STEP
        local cbCY = cy + OPP.CB_DY
        if hitTest(dx, dy, OPP.CB_CX, cbCY, OPP.CB_W, OPP.CB_H) then
            BF.trigger("aod_challenge_" .. i)
            -- 检查竞技券
            if (state.tickets or 0) <= 0 then
                print("[ArenaOpponentDialog] 竞技券不足! (tickets=" .. tostring(state.tickets) .. ")")
                return true
            end

            -- 向服务器请求对手防守阵容
            state.waitingOpponent = true
            state.pendingTargetUid = opp.uid
            state.pendingTargetName = opp.name

            require("network.Client").sendAction(Protocol.ACTION_TYPES.ARENA_GET_OPPONENT, {
                targetUid = opp.uid,
            })
            print("[ArenaOpponentDialog] 请求对手阵容: " .. opp.name .. " uid=" .. tostring(opp.uid))
            return true
        end
    end

    return true  -- 消费事件防穿透
end

return Dialog
