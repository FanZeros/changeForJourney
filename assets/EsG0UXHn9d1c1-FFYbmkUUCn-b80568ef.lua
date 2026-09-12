-- ============================================================================
-- EquipmentDetail - 装备详情面板
-- 从 EquipmentBag 的格子点击打开
-- 展示双面板对比（当前已穿戴 vs 新装备），支持穿戴/更换
-- 像素精确布局，所有坐标基于设计分辨率 1080×2400
-- ============================================================================

local EquipmentConfig  = require("config.EquipmentConfig")
local EquipmentSystem  = require("systems.EquipmentSystem")
local AffixConfig      = require("config.AffixConfig")
local AD               = require("systems.AttributeDef")
local GameConfig       = require("config.GameConfig")
local PlayerStore      = require("client.data.PlayerStore")
local HC               = require("config.HeroConfig")
local ImageCache       = require("ui.ImageCache")
local BF               = require("systems.ButtonFeedback")
local ExpTable         = require("config.ExpTable")
local GameState        = require("core.GameState")

local BlacksmithConfig = require("config.BlacksmithConfig")
local BlacksmithPage   = nil  -- 延迟加载，避免循环依赖
local EquipmentBag     = nil  -- 延迟加载
local BottomNav        = nil  -- 延迟加载
local CharacterDetail  = nil  -- 延迟加载

local EquipmentDetail = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 状态 ========================

local detState = {
    open      = false,
    closing   = false,
    equipSeq  = nil,    -- 点击的背包装备 seq (string)
    slot      = nil,    -- 槽位 "weapon"|"offhand"|"armor"|"accessory"
    heroId    = nil,    -- 当前角色 ID
    openTime  = 0,
    closeTime = 0,
    -- 关闭动画快照（close() 时冻结，防止 server 推送导致面板内容跳变）
    snapshot  = nil,    -- { newEquip, isEquipped, curEquip, hasCurrent, btnText, powerDiff }
}

-- ======================== 动画常量 ========================

local ANIM_OPEN_DUR  = 0.25
local ANIM_CLOSE_DUR = 0.20
local SLIDE_DIST     = 800   -- 从下方滑入的距离

-- 前向声明（close() 中需要在定义之前引用）
local isClickedEquipEquipped
local getComparisonEquip

local function easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 九宫格 insets (UI_ZBTS) ========================

local NS_TOP    = 400
local NS_RIGHT  = 93
local NS_BOTTOM = 93
local NS_LEFT   = 93

-- ======================== 品质边框/文本颜色 ========================

local QUALITY_COLOR = {
    [1] = { 0xb5, 0xb5, 0xb5 },  -- 普通
    [2] = { 0xa2, 0xff, 0x94 },  -- 优质
    [3] = { 0x72, 0xf2, 0xf5 },  -- 稀有
    [4] = { 0xef, 0x79, 0xff },  -- 史诗
    [5] = { 0xff, 0xed, 0x00 },  -- 传说
    [6] = { 0xff, 0x00, 0x00 },  -- 至臻
}

-- 词缀品质名 → 图片key映射
local AFFIX_BADGE_KEY = { "D", "C", "B", "A", "S" }

-- ======================== 图片资源 ========================

local imgBg          = {}   -- [1..5] 品质背景九宫格
local imgPowerIcon   = -1
local imgArrowUp     = -1
local imgArrowDown   = -1
local imgBtnGreen    = -1
local imgBtnYellow   = -1   -- UI_AN_HUANG.png（前往洗练按钮）
local imgBtnRed      = -1   -- UI_AN_HONG.png（立即分解按钮）
local imgLock        = -1   -- UI_ICON_SUO.png（装备锁定图标）
local imgAffixBadge  = {}   -- { D=handle, C=handle, ... }
-- 装备图标缓存已迁移至 ImageCache 共享模块（LRU 淘汰，防止 VRAM 累积）

-- ======================== Lazy-load Client ========================

---@type table|nil
local _cachedClient = nil

local function getClient()
    if not _cachedClient then
        _cachedClient = require("network.Client")
    end
    return _cachedClient
end

---@type table|nil
local _cachedProtocol = nil

local function getProtocol()
    if not _cachedProtocol then
        _cachedProtocol = require("shared.Protocol")
    end
    return _cachedProtocol
end

-- ======================== 工具函数 ========================

--- 居中绘制图片
local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 or alpha <= 0.01 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 点击测试（中心坐标+尺寸）
local function hitTest(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

--- 描边文字（16方向采样）
local drawTextStroke = require("core.DrawUtil").drawTextStroke

-- ======================== 九宫格绘制 ========================

--- 绘制九宫格拉伸图片
---@param vg any NanoVG 上下文
---@param img number 图片句柄
---@param dx number 目标区域左上角 X
---@param dy number 目标区域左上角 Y
---@param dw number 目标区域宽
---@param dh number 目标区域高
---@param iTop number 上边距 inset
---@param iRight number 右边距 inset
---@param iBottom number 下边距 inset
---@param iLeft number 左边距 inset
local function drawNineSlice(vg, img, dx, dy, dw, dh, iTop, iRight, iBottom, iLeft)
    if img < 0 then return end

    local srcW, srcH = nvgImageSize(vg, img)
    if srcW <= 0 or srcH <= 0 then return end

    local sL = iLeft
    local sR = iRight
    local sT = iTop
    local sB = iBottom
    local sMW = srcW - sL - sR
    local sMH = srcH - sT - sB

    local dL = math.min(iLeft, dw * 0.5)
    local dR = math.min(iRight, dw * 0.5)
    local dT = math.min(iTop, dh * 0.5)
    local dB = math.min(iBottom, dh * 0.5)

    if sMW <= 0 or sMH <= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, img, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, dx, dy, dw, dh)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        return
    end

    -- 整数分界点
    local ix0 = math.floor(dx + 0.5)
    local iy0 = math.floor(dy + 0.5)
    local ix1 = math.floor(dx + dL + 0.5)
    local iy1 = math.floor(dy + dT + 0.5)
    local ix2 = math.floor(dx + dw - dR + 0.5)
    local iy2 = math.floor(dy + dh - dB + 0.5)
    local ix3 = math.floor(dx + dw + 0.5)
    local iy3 = math.floor(dy + dh + 0.5)

    -- 9个patch: {destX, destY, destW, destH, srcX, srcY, srcW, srcH}
    -- 绘制顺序：中心→边→角，后画的覆盖先画的，用1px重叠消除缝隙
    local OV = 1  -- 重叠像素
    local patches = {
        -- 中心（四向各扩1px）
        { ix1 - OV, iy1 - OV, ix2 - ix1 + OV * 2, iy2 - iy1 + OV * 2, sL, sT, sMW, sMH },
        -- 四条边（朝中心方向扩1px）
        { ix1 - OV, iy0,      ix2 - ix1 + OV * 2, iy1 - iy0 + OV,     sL,       0,        sMW, sT  }, -- 上
        { ix1 - OV, iy2 - OV, ix2 - ix1 + OV * 2, iy3 - iy2 + OV,     sL,       sT + sMH, sMW, sB  }, -- 下
        { ix0,      iy1 - OV, ix1 - ix0 + OV,     iy2 - iy1 + OV * 2, 0,        sT,       sL,  sMH }, -- 左
        { ix2 - OV, iy1 - OV, ix3 - ix2 + OV,     iy2 - iy1 + OV * 2, sL + sMW, sT,       sR,  sMH }, -- 右
        -- 四个角（朝中心方向扩1px，最后绘制覆盖边的重叠区）
        { ix0,      iy0,      ix1 - ix0 + OV, iy1 - iy0 + OV, 0,        0,        sL, sT  }, -- 左上
        { ix2 - OV, iy0,      ix3 - ix2 + OV, iy1 - iy0 + OV, sL + sMW, 0,        sR, sT  }, -- 右上
        { ix0,      iy2 - OV, ix1 - ix0 + OV, iy3 - iy2 + OV, 0,        sT + sMH, sL, sB  }, -- 左下
        { ix2 - OV, iy2 - OV, ix3 - ix2 + OV, iy3 - iy2 + OV, sL + sMW, sT + sMH, sR, sB  }, -- 右下
    }

    nvgShapeAntiAlias(vg, 0)
    for _, p in ipairs(patches) do
        local px, py, pw, ph = p[1], p[2], p[3], p[4]
        local sx, sy, sw, sh = p[5], p[6], p[7], p[8]
        if pw > 0 and ph > 0 and sw > 0 and sh > 0 then
            local scaleX = pw / sw
            local scaleY = ph / sh
            local paint = nvgImagePattern(vg,
                px - sx * scaleX,
                py - sy * scaleY,
                srcW * scaleX,
                srcH * scaleY,
                0, img, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, px, py, pw, ph)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    end
    nvgShapeAntiAlias(vg, 1)
end

-- ======================== 战斗力计算 ========================

-- [临时背包战斗力优化] 按角色伤害类型过滤不生效的"攻击向"派生属性
-- 防御属性(physArmor/magArmor等)对所有角色都有减伤效果，不排除
-- 六围属性：不直接排除，而是按派生表(AD.DERIVATIVES)计算部分有效战斗力
--   例：物理角色的 INT(2.0→魔攻[排除] + 0.5%→魔伤加成[排除] + 3.0→能量护盾[保留])
--       → 只计入能量护盾的贡献 = 3.0 * 0.1 = 0.30 价值/点（而非完整的 5 价值/点）
local EXCLUDED_KEYS_BY_DMG_TYPE = {
    ["物理"] = {
        magAtk=true, magCritRate=true, magCritDmg=true, magPen=true,
        magDmgBonus=true, magAtkBonus=true,
        healAmount=true, healBonus=true, healCritRate=true, healCritDmg=true,
    },
    ["魔法"] = {
        physAtk=true, physCritRate=true, physCritDmg=true, physPen=true,
        physDmgBonus=true, physAtkBonus=true,
        healAmount=true, healBonus=true, healCritRate=true, healCritDmg=true,
    },
    ["治疗"] = {
        physAtk=true, physCritRate=true, physCritDmg=true, physPen=true,
        physDmgBonus=true, physAtkBonus=true,
        magAtk=true, magCritRate=true, magCritDmg=true, magPen=true,
        magDmgBonus=true, magAtkBonus=true,
    },
}

-- 六围 key 快速查找集合
local BASE_STAT_SET = {}
for _, k in ipairs(AD.BASE_STATS) do BASE_STAT_SET[k] = true end

--- 计算单个属性贡献的战斗力值
---@param key string 属性 key
---@param value number 属性数值
---@param excluded table|nil 排除集合
---@return number 战斗力贡献
local function calcStatPower(key, value, excluded)
    -- 六围属性且存在排除规则 → 按派生表部分计算
    if excluded and BASE_STAT_SET[key] then
        local derivatives = AD.DERIVATIVES and AD.DERIVATIVES[key]
        if derivatives then
            local effectiveVM = 0
            for _, d in ipairs(derivatives) do
                if not excluded[d.attr] then
                    local dMeta = AD.META[d.attr]
                    if dMeta and dMeta.valueModel and dMeta.valueModel > 0 then
                        -- perPoint 是每点六围增加的派生属性量
                        -- dMeta.valueModel 是派生属性的价值权重
                        if dMeta.dataType == AD.TYPE_PCT then
                            effectiveVM = effectiveVM + d.perPoint * dMeta.valueModel / 100
                        else
                            effectiveVM = effectiveVM + d.perPoint * dMeta.valueModel
                        end
                    end
                end
            end
            return value * effectiveVM
        end
        -- 无派生表则回退到原始 valueModel
    end

    -- 非六围属性 / 无排除规则 → 检查排除后用原始 valueModel
    if excluded and excluded[key] then return 0 end
    local meta = AD.META[key]
    if not meta or not meta.valueModel or meta.valueModel <= 0 then return 0 end
    if meta.dataType == AD.TYPE_PCT then
        return value * meta.valueModel / 100
    else
        return value * meta.valueModel
    end
end

--- 计算装备战斗力
--- heroId 非 nil 时按角色伤害类型过滤；六围属性按派生表部分计算有效贡献
---@param equip table 装备实例
---@param heroId number|nil 角色ID（临时背包传入，总背包传nil）
---@return number
local function calcEquipPower(equip, heroId)
    if not equip then return 0 end

    -- 根据角色伤害类型获取需要排除的属性集合
    local excluded = nil
    if heroId then
        local hero = HC.HEROES and HC.HEROES[heroId]
        if hero and hero.dmgMainType then
            excluded = EXCLUDED_KEYS_BY_DMG_TYPE[hero.dmgMainType]
        end
    end

    local power = 0
    local enhBoost = BlacksmithConfig.getEnhanceBoost(equip.enhanceLevel or 0)

    -- 槽位强化加成（仅作用于第一条基础属性，与服务端 computeModifierEntries 保持一致）
    local slotBoost = 0
    if detState.heroId and detState.slot then
        local heroesData = PlayerStore.Get("heroes")
        local deployed = heroesData and heroesData.deployed
        local partySlot = EquipmentSystem.findPartySlot(deployed, detState.heroId)
        if partySlot then
            local slotEnhanceData = PlayerStore.Get("slotEnhance")
            slotBoost = EquipmentSystem.calcSlotBoost(slotEnhanceData, partySlot, detState.slot, equip.grip)
        end
    end

    for i, s in ipairs(equip.baseStats or {}) do
        local val = s[2] * (1 + enhBoost)
        if i == 1 then val = val * (1 + slotBoost) end
        power = power + calcStatPower(s[1], val, excluded)
    end

    for _, affix in ipairs(equip.affixes or {}) do
        power = power + calcStatPower(affix.key, affix.value, excluded)
    end

    return math.floor(power)
end

-- ======================== 属性格式化 ========================

--- 格式化属性值为显示文本
---@param key string 属性 key
---@param value number
---@return string
local function formatStatValue(key, value)
    local meta = AD.META[key]
    if not meta then return string.format("%.1f", value) end

    if meta.dataType == AD.TYPE_PCT then
        return string.format("%.1f%%", value)
    elseif meta.dataType == AD.TYPE_INT then
        return tostring(math.floor(value))
    else
        return string.format("%.1f", value)
    end
end

--- 获取属性中文名
---@param key string
---@return string
local function getStatName(key)
    local meta = AD.META[key]
    return meta and meta.name or key
end

-- ======================== 新装备面板参考坐标（绝对值） ========================
-- 所有 X,Y 为中心坐标（用于 hitTest、drawImageCentered）
-- 文本坐标用 NVG_ALIGN_LEFT/RIGHT + NVG_ALIGN_MIDDLE

-- 面板背景
local REF_BG_CX  = 805
local REF_BG_CY  = 1072
local REF_BG_W   = 530
local REF_BG_H   = 1015

-- 装备名称（左对齐）
local REF_NAME_X = 578    -- 左对齐基准
local REF_NAME_Y = 625
local REF_NAME_FONT = 40

-- 装备类型
local REF_TYPE_X = 578
local REF_TYPE_Y = 706
local REF_TYPE_FONT = 30

-- 品质文本
local REF_QUALITY_X = 578
local REF_QUALITY_Y = 861
local REF_QUALITY_FONT = 30

-- 装备图标
local REF_ICON_CX = 903
local REF_ICON_CY = 809
local REF_ICON_SIZE = 290

-- 战斗力图标
local REF_POWER_ICON_CX = 596
local REF_POWER_ICON_CY = 917

-- 战斗力数值
local REF_POWER_VAL_X = 622
local REF_POWER_VAL_Y = 917
local REF_POWER_VAL_FONT = 42

-- 提升/下降箭头
local REF_ARROW_SIZE = 48
local REF_ARROW_GAP  = 12  -- 战斗力文本右边12像素

-- 等级背景框
local REF_LV_BG_CX  = 961
local REF_LV_BG_CY  = 917
local REF_LV_BG_W   = 142
local REF_LV_BG_H   = 42
local REF_LV_BG_RAD  = 21
local REF_LV_FONT   = 30

-- 基础属性栏
local REF_STAT_BG_CX  = 805
local REF_STAT_BG_Y0  = 1007   -- 第一行中心Y
local REF_STAT_BG_W   = 460
local REF_STAT_BG_H   = 60
local REF_STAT_BG_RAD = 14
local REF_STAT_GAP    = 12     -- 多条属性间距
local REF_STAT_TEXT_X  = 595   -- 左对齐
local REF_STAT_VAL_X   = 1016  -- 右对齐
local REF_STAT_FONT   = 34

-- 随机属性标题
local REF_AFFIX_TITLE_X = 578
local REF_AFFIX_TITLE_Y = 1206
local REF_AFFIX_TITLE_FONT = 30

-- 随机属性行（与基础属性相同的背景+样式）
local REF_AFFIX_TEXT_X  = 636   -- 左对齐（缩进，留出徽章空间）
local REF_AFFIX_GAP_TOP = 15    -- 与"随机属性"标题下方间距
local REF_AFFIX_GAP     = 15    -- 多条随机属性间距（含背景）
local REF_AFFIX_ROW_H   = 60    -- 行高与基础属性一致

-- 品质标识徽章
local REF_BADGE_CX   = 611
local REF_BADGE_Y0   = 1264   -- 第一条徽章中心Y
local REF_BADGE_W    = 36
local REF_BADGE_H    = 44

-- 穿戴按钮
local REF_BTN_CX  = 807
local REF_BTN_CY  = 1461
local REF_BTN_W   = 410
local REF_BTN_H   = 100
local REF_BTN_FONT = 40

-- 前往洗练按钮（装备详情背景底边下方 18px）
local REF_ENH_BTN_GAP  = 18   -- 与背景底边间距
local REF_ENH_BTN_W    = 410
local REF_ENH_BTN_H    = 100
local REF_ENH_BTN_FONT = 40

-- 立即分解按钮（前往洗练按钮下方，背包模式专用）
local REF_DEC_BTN_GAP = 72    -- 与前往洗练按钮的间距（下移至背景框外）

-- 当前装备面板（顶部与新装备面板对齐）
local CUR_BG_CX = 274
local CUR_BG_W  = 530
local CUR_BG_H  = 850
-- 新面板顶部 = REF_BG_CY - REF_BG_H*0.5 = 564.5
-- 当前面板CY = 564.5 + CUR_BG_H*0.5 = 989.5 → 取整
local CUR_BG_CY = math.floor(REF_BG_CY - REF_BG_H * 0.5 + CUR_BG_H * 0.5)

-- 单面板居中
local SINGLE_BG_CX = 540

-- ======================== 面板绘制（绝对坐标 + X偏移） ========================

--- 获取装备图标（委托 ImageCache 共享缓存）
---@param templateId string 模板 ID（如 "W1"）
---@return number nvgImage handle (-1 if failed)
local function getEquipIcon(templateId)
    return ImageCache.getEquipIcon(templateId)
end

--- 获取当前装备详情上下文的槽位强化等级
---@param equipSlot string|nil 装备槽位 ("weapon"|"offhand"|"armor"|"accessory")
---@return number|nil slotLevel 槽位强化等级 (nil = 上下文不可用，不显示角标)
local function getSlotEnhLevel(equipSlot)
    if not detState.heroId or not equipSlot then return nil end
    local heroesData = PlayerStore.Get("heroes")
    local deployed = heroesData and heroesData.deployed
    local partySlot = EquipmentSystem.findPartySlot(deployed, detState.heroId)
    if not partySlot then return nil end
    local slotEnhanceData = PlayerStore.Get("slotEnhance")
    if not slotEnhanceData or not slotEnhanceData.levels then return 0 end
    local partyLevels = slotEnhanceData.levels[tostring(partySlot)] or slotEnhanceData.levels[partySlot]
    if not partyLevels then return 0 end
    return partyLevels[equipSlot] or 0
end

--- 绘制单个装备面板（新装备或当前装备）
---@param vg any NanoVG 上下文
---@param equip table 装备实例
---@param offsetX number X轴偏移（相对于新装备面板参考坐标）
---@param bgCX number 背景中心X
---@param bgCY number 背景中心Y
---@param bgW number 背景宽
---@param bgH number 背景高
---@param powerDiff number|nil 战斗力差值（nil=不显示）
---@param showButton boolean 是否显示穿戴按钮
---@param btnText string 按钮文本
---@param showEnhanceOnly boolean|nil 仅显示前往洗练按钮（隐藏穿戴按钮）
---@param showLock boolean|nil 是否在名称右侧显示锁定图标（仅背包装备）
---@param showDecompose boolean|nil 是否在前往洗练按钮下方显示「立即分解」按钮（仅背包未穿戴装备）
local function drawEquipPanel(vg, equip, offsetX, bgCX, bgCY, bgW, bgH, powerDiff, showButton, btnText, showEnhanceOnly, showLock, showDecompose)
    if not equip then return end

    local q = equip.quality or 1
    local qColor = QUALITY_COLOR[q] or QUALITY_COLOR[1]
    local bgImg = imgBg[q] or imgBg[1]

    -- 1) 九宫格背景（坐标取整避免缝隙）
    local bgX = math.floor(bgCX - bgW * 0.5 + 0.5)
    local bgY = math.floor(bgCY - bgH * 0.5 + 0.5)
    drawNineSlice(vg, bgImg,
        bgX, bgY, bgW, bgH,
        NS_TOP, NS_RIGHT, NS_BOTTOM, NS_LEFT)

    -- 2) 装备名称 - 左对齐 X578 Y625 字号40 纯白 描边4
    local nameStr = equip.name or "???"
    if equip.enhanceLevel and equip.enhanceLevel > 0 then
        nameStr = nameStr .. " +" .. equip.enhanceLevel
    end
    drawTextStroke(vg, REF_NAME_X + offsetX, REF_NAME_Y, nameStr,
        REF_NAME_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, 4)

    -- 2.1) 锁定图标 - 名称右侧（仅背包装备显示，可点击）
    if showLock and imgLock >= 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, REF_NAME_FONT)
        local nameW = nvgTextBounds(vg, 0, 0, nameStr)
        local LOCK_SIZE = 48
        local LOCK_GAP  = 14
        local lockCX = REF_NAME_X + offsetX + nameW + LOCK_GAP + LOCK_SIZE * 0.5
        local locked = (equip.locked == true)
        drawImageCentered(vg, imgLock, lockCX, REF_NAME_Y, LOCK_SIZE, LOCK_SIZE,
            locked and 1.0 or 0.4)
        -- 记录点击热区（最终位置，触摸区域略放大方便点按）
        detState.lockHotspot = {
            cx = lockCX, cy = REF_NAME_Y,
            w  = LOCK_SIZE + 24, h = LOCK_SIZE + 24,
        }
    end

    -- 3) 装备类型 - 左对齐 X578 Y706 字号30 纯白
    local typeName = equip.type or EquipmentConfig.SLOT_NAME[equip.slot] or ""
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, REF_TYPE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, REF_TYPE_X + offsetX, REF_TYPE_Y, typeName, nil)

    -- 4) 品质文本 - 左对齐 X578 Y861 字号30 品质色 描边4
    local qualityDef = EquipmentConfig.QUALITY[q]
    local qualityName = qualityDef and qualityDef.name or "普通"
    drawTextStroke(vg, REF_QUALITY_X + offsetX, REF_QUALITY_Y, qualityName,
        REF_QUALITY_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        qColor[1], qColor[2], qColor[3], 4)

    -- 5) 战斗力图标 - X596 Y917
    local powerIconSize = 36
    drawImageCentered(vg, imgPowerIcon,
        REF_POWER_ICON_CX + offsetX, REF_POWER_ICON_CY,
        powerIconSize, powerIconSize, 1.0)

    -- 6) 战斗力数值 - 左对齐 X622 Y917 字号42 颜色f7fe77 描边4
    local equipPower = calcEquipPower(equip, detState.heroId)
    local powerStr = tostring(equipPower)
    drawTextStroke(vg, REF_POWER_VAL_X + offsetX, REF_POWER_VAL_Y, powerStr,
        REF_POWER_VAL_FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        0xf7, 0xfe, 0x77, 4)

    -- 7) 提升/下降箭头 - 48*48 战斗力文本右边12px Y居中
    if powerDiff and powerDiff ~= 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, REF_POWER_VAL_FONT)
        local pwTextW = nvgTextBounds(vg, 0, 0, powerStr)
        local arrowCX = REF_POWER_VAL_X + offsetX + pwTextW + REF_ARROW_GAP + REF_ARROW_SIZE * 0.5

        if powerDiff > 0 then
            drawImageCentered(vg, imgArrowUp, arrowCX, REF_POWER_VAL_Y,
                REF_ARROW_SIZE, REF_ARROW_SIZE, 1.0)
        else
            drawImageCentered(vg, imgArrowDown, arrowCX, REF_POWER_VAL_Y,
                REF_ARROW_SIZE, REF_ARROW_SIZE, 1.0)
        end
    end

    -- 8) 装备图标 - X903 Y809 290*290
    local iconCX = REF_ICON_CX + offsetX
    local iconCY = REF_ICON_CY
    local equipIconImg = getEquipIcon(equip.templateId)
    if equipIconImg >= 0 then
        drawImageCentered(vg, equipIconImg, iconCX, iconCY, REF_ICON_SIZE, REF_ICON_SIZE, 1.0)
    else
        -- 无图标时回退为占位框+文字
        nvgBeginPath(vg)
        nvgRoundedRect(vg, iconCX - REF_ICON_SIZE * 0.5, iconCY - REF_ICON_SIZE * 0.5,
            REF_ICON_SIZE, REF_ICON_SIZE, 20)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 25))
        nvgFill(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 48)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(qColor[1], qColor[2], qColor[3], 180))
        local shortName = string.sub(equip.name or "?", 1, 6)
        nvgText(vg, iconCX, iconCY, shortName, nil)
    end

    -- 8.5) 槽位强化角标（右上角，描边，+X）
    local slotLv = getSlotEnhLevel(detState.slot)
    if slotLv then
        local enhText = "+" .. slotLv
        local enhX = iconCX + REF_ICON_SIZE * 0.5 - 12
        local enhY = iconCY - REF_ICON_SIZE * 0.5 + 12
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 48)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        -- 黑色描边 16方向
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        local sStep = math.pi * 2 / 16
        for si = 0, 15 do
            local sa = si * sStep
            nvgText(vg, enhX + math.cos(sa) * 4, enhY + math.sin(sa) * 4, enhText, nil)
        end
        -- 绿色填充
        nvgFillColor(vg, nvgRGBA(0x00, 0xff, 0x60, 255))
        nvgText(vg, enhX, enhY, enhText, nil)
    end

    -- 9) 等级背景框 - X961 Y917 142*42 纯黑40% 圆角21
    local lvBgCX = REF_LV_BG_CX + offsetX
    nvgBeginPath(vg)
    nvgRoundedRect(vg, lvBgCX - REF_LV_BG_W * 0.5, REF_LV_BG_CY - REF_LV_BG_H * 0.5,
        REF_LV_BG_W, REF_LV_BG_H, REF_LV_BG_RAD)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 102))  -- 40% 不透明度
    nvgFill(vg)

    -- 10) 等级文字 - 等级背景框中央 "LV 45" 字号30 纯白
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, REF_LV_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, lvBgCX, REF_LV_BG_CY, "LV " .. (equip.level or 1), nil)

    -- 11-14) 基础属性栏（含强化加成 + 槽位强化加成）
    if equip.baseStats and #equip.baseStats > 0 then
        local enhBoost = BlacksmithConfig.getEnhanceBoost(equip.enhanceLevel or 0)
        -- 槽位强化加成（仅第一条基础属性，与服务端保持一致）
        local slotBoost = 0
        if detState.heroId and detState.slot then
            local heroesData = PlayerStore.Get("heroes")
            local deployed = heroesData and heroesData.deployed
            local partySlot = EquipmentSystem.findPartySlot(deployed, detState.heroId)
            if partySlot then
                local slotEnhanceData = PlayerStore.Get("slotEnhance")
                slotBoost = EquipmentSystem.calcSlotBoost(slotEnhanceData, partySlot, detState.slot, equip.grip)
            end
        end
        for i, s in ipairs(equip.baseStats) do
            local statCY = REF_STAT_BG_Y0 + (i - 1) * (REF_STAT_BG_H + REF_STAT_GAP)

            -- 11) 属性背景 - X805 460*60 纯黑10% 圆角14
            nvgBeginPath(vg)
            nvgRoundedRect(vg,
                REF_STAT_BG_CX + offsetX - REF_STAT_BG_W * 0.5,
                statCY - REF_STAT_BG_H * 0.5,
                REF_STAT_BG_W, REF_STAT_BG_H, REF_STAT_BG_RAD)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 25))  -- 10% 不透明度
            nvgFill(vg)

            -- 12) 属性名 - 左对齐 X595 字号34 颜色725850
            local sName = getStatName(s[1])
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, REF_STAT_FONT)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
            nvgText(vg, REF_STAT_TEXT_X + offsetX, statCY, sName, nil)

            -- 13) 属性值 - 右对齐 X1016 字号34 纯白 描边4（含强化加成 + 槽位强化加成）
            local rawVal = s[2] * (1 + enhBoost)
            if i == 1 then rawVal = rawVal * (1 + slotBoost) end
            local sVal = formatStatValue(s[1], rawVal)
            drawTextStroke(vg, REF_STAT_VAL_X + offsetX, statCY, sVal,
                REF_STAT_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)
        end
    end

    -- 15-18) 随机属性（词缀）
    if equip.affixes and #equip.affixes > 0 then
        -- 15) "随机属性" 标题 - 左对齐 X578 Y1206 字号30 颜色918f88
        -- 标题Y根据基础属性数量动态偏移
        local baseStatCount = equip.baseStats and #equip.baseStats or 0
        local affixTitleY = REF_AFFIX_TITLE_Y
        -- 如果基础属性数量不同，调整Y位置（以2条为基准）
        if baseStatCount ~= 0 then
            local baseStatEndY = REF_STAT_BG_Y0 + (baseStatCount - 1) * (REF_STAT_BG_H + REF_STAT_GAP) + REF_STAT_BG_H * 0.5
            -- 标题在最后一条基础属性下方留一定间距
            local minGap = 30
            if affixTitleY < baseStatEndY + minGap then
                affixTitleY = baseStatEndY + minGap
            end
        end

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, REF_AFFIX_TITLE_FONT)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x91, 0x8f, 0x88, 255))
        nvgText(vg, REF_AFFIX_TITLE_X + offsetX, affixTitleY, "随机属性", nil)

        -- 词缀行起始Y：标题底部 + 15px + 行高一半
        local firstAffixY = affixTitleY + REF_AFFIX_TITLE_FONT * 0.5 + REF_AFFIX_GAP_TOP + REF_AFFIX_ROW_H * 0.5

        for i, affix in ipairs(equip.affixes) do
            local affixY = firstAffixY + (i - 1) * (REF_AFFIX_ROW_H + REF_AFFIX_GAP)
            local isCorrupt = AffixConfig.isCorruptAffix(affix)
            local aq = affix.quality or 1
            local badgeKey = AFFIX_BADGE_KEY[aq] or "D"
            local badgeImg = imgAffixBadge[badgeKey] or -1

            -- 背景框（与基础属性相同：460*60 黑10% 圆角14）
            nvgBeginPath(vg)
            nvgRoundedRect(vg,
                REF_STAT_BG_CX + offsetX - REF_STAT_BG_W * 0.5,
                affixY - REF_AFFIX_ROW_H * 0.5,
                REF_STAT_BG_W, REF_AFFIX_ROW_H, REF_STAT_BG_RAD)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 25))  -- 10%不透明度
            nvgFill(vg)

            -- 17) 品质标识徽章 / 魔化紫色圆标
            if isCorrupt then
                local r = math.min(REF_BADGE_W, REF_BADGE_H) * 0.28
                nvgBeginPath(vg)
                nvgCircle(vg, REF_BADGE_CX + offsetX, affixY, r)
                nvgFillColor(vg, nvgRGBA(0x9B, 0x4D, 0xFF, 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgCircle(vg, REF_BADGE_CX + offsetX, affixY, r)
                nvgStrokeWidth(vg, 2)
                nvgStrokeColor(vg, nvgRGBA(0xE0, 0xB0, 0xFF, 220))
                nvgStroke(vg)
            elseif badgeImg >= 0 then
                drawImageCentered(vg, badgeImg,
                    REF_BADGE_CX + offsetX, affixY,
                    REF_BADGE_W, REF_BADGE_H, 1.0)
            end

            -- 16) 词缀名称 - 左对齐 X636 字号34 颜色725850（与基础属性相同）
            local affName = affix.name or "?"
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, REF_STAT_FONT)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0x72, 0x58, 0x50, 255))
            nvgText(vg, REF_AFFIX_TEXT_X + offsetX, affixY, affName, nil)

            -- 词缀数值 - 右对齐 X1016 字号34 白色 描边4（与基础属性相同）
            local affVal = "+" .. formatStatValue(affix.key, affix.value)
            drawTextStroke(vg, REF_STAT_VAL_X + offsetX, affixY, affVal,
                REF_STAT_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)
        end
    end

    -- 19-20) 穿戴按钮
    if showButton then
        -- 按钮Y也可能需要根据内容动态调整
        local btnCY = REF_BTN_CY
        -- 检查词缀是否超出按钮位置
        if equip.affixes and #equip.affixes > 0 then
            local baseStatCount = equip.baseStats and #equip.baseStats or 0
            local affixTitleY = REF_AFFIX_TITLE_Y
            if baseStatCount ~= 0 then
                local baseStatEndY = REF_STAT_BG_Y0 + (baseStatCount - 1) * (REF_STAT_BG_H + REF_STAT_GAP) + REF_STAT_BG_H * 0.5
                local minGap = 30
                if affixTitleY < baseStatEndY + minGap then
                    affixTitleY = baseStatEndY + minGap
                end
            end
            local lastAffixY = affixTitleY + REF_AFFIX_TITLE_FONT * 0.5 + REF_AFFIX_GAP_TOP + REF_AFFIX_ROW_H * 0.5
                + (#equip.affixes - 1) * (REF_AFFIX_ROW_H + REF_AFFIX_GAP)
            local minBtnGap = 40
            if btnCY < lastAffixY + REF_AFFIX_ROW_H * 0.5 + minBtnGap then
                btnCY = lastAffixY + REF_AFFIX_ROW_H * 0.5 + minBtnGap
            end
        end

        if not showEnhanceOnly then
            -- 19) 按钮背景 UI_AN_LV.png - X807 Y1461 410*100
            local _bf1 = BF.begin(vg, "ed_equip", REF_BTN_CX + offsetX, btnCY, REF_BTN_W, REF_BTN_H)
            drawImageCentered(vg, imgBtnGreen,
                REF_BTN_CX + offsetX, btnCY,
                REF_BTN_W, REF_BTN_H, 1.0)

            -- 20) 按钮文字 - 正中央 字号40 颜色25553d
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, REF_BTN_FONT)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0x25, 0x55, 0x3d, 255))
            nvgText(vg, REF_BTN_CX + offsetX, btnCY, btnText, nil)
            BF.finish(vg, _bf1)
            local _TM = require("systems.TutorialManager")
            if _TM.isActive() then _TM.registerHotspot("equip_btn_equip", REF_BTN_CX + offsetX, btnCY, REF_BTN_W, REF_BTN_H) end
        end

        -- 21-22) 前往洗练按钮（仅铁匠铺已解锁时显示）
        if ExpTable.isBuildingUnlocked("smith", GameState.getLevel()) then
            local enhBtnCY
            if showEnhanceOnly then
                -- 背包模式：前往洗练按钮顶替穿戴按钮的位置
                enhBtnCY = btnCY
            else
                enhBtnCY = bgCY + bgH * 0.5 + REF_ENH_BTN_GAP + REF_ENH_BTN_H * 0.5
            end
            local _bf2 = BF.begin(vg, "ed_enhance", REF_BTN_CX + offsetX, enhBtnCY, REF_BTN_W, REF_BTN_H)
            drawImageCentered(vg, imgBtnYellow,
                REF_BTN_CX + offsetX, enhBtnCY,
                REF_ENH_BTN_W, REF_ENH_BTN_H, 1.0)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, REF_ENH_BTN_FONT)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))
            nvgText(vg, REF_BTN_CX + offsetX, enhBtnCY, "前往洗练", nil)
            BF.finish(vg, _bf2)

            -- 23-24) 立即分解按钮（背包未穿戴装备，前往洗练下方）
            if showDecompose then
                local decBtnCY = enhBtnCY + REF_ENH_BTN_H * 0.5 + REF_DEC_BTN_GAP + REF_ENH_BTN_H * 0.5
                local _bf3 = BF.begin(vg, "ed_decompose", REF_BTN_CX + offsetX, decBtnCY, REF_ENH_BTN_W, REF_ENH_BTN_H)
                drawImageCentered(vg, imgBtnRed,
                    REF_BTN_CX + offsetX, decBtnCY,
                    REF_ENH_BTN_W, REF_ENH_BTN_H, 1.0)
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, REF_ENH_BTN_FONT)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))   -- 纯黑 75% 不透明度
                nvgText(vg, REF_BTN_CX + offsetX, decBtnCY, "立即分解", nil)
                BF.finish(vg, _bf3)
            end
        end
    end
end

-- ======================== Public API ========================

--- 初始化（加载图片资源）
---@param vg any NanoVG 上下文
function EquipmentDetail.init(vg)
    for i = 1, 6 do
        imgBg[i] = nvgCreateImage(vg, "image/UI_ZBTS_" .. i .. ".png", 0)
    end
    imgPowerIcon = nvgCreateImage(vg, "image/ICON_ZDL.png", 0)
    imgArrowUp   = nvgCreateImage(vg, "image/ICON_UP.png", 0)
    imgArrowDown = nvgCreateImage(vg, "image/ICON_down.png", 0)
    imgBtnGreen  = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    imgBtnYellow = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    imgBtnRed    = nvgCreateImage(vg, "image/UI_AN_HONG.png", 0)
    imgLock      = nvgCreateImage(vg, "image/UI_ICON_SUO.png", 0)
    ImageCache.init(vg)

    for _, key in ipairs(AFFIX_BADGE_KEY) do
        imgAffixBadge[key] = nvgCreateImage(vg, "image/ICON_CZBZ_" .. key .. ".png", 0)
    end

    print("[EquipmentDetail] init OK")
end

--- 打开装备详情
---@param seq string|number 装备序列号
---@param slot string 槽位
---@param heroId number 角色ID
function EquipmentDetail.open(seq, slot, heroId)
    detState.open      = true
    detState.closing   = false
    detState.equipSeq  = tostring(seq)
    detState.slot      = slot
    detState.heroId    = heroId
    detState.openTime  = time.elapsedTime
    print("[EquipmentDetail] open seq=" .. tostring(seq) .. " slot=" .. tostring(slot) .. " heroId=" .. tostring(heroId))
end

--- 关闭（冻结当前面板内容用于关闭动画）
function EquipmentDetail.close()
    if detState.closing then return end
    -- 快照当前渲染数据，动画期间不再读实时数据
    local equipData = PlayerStore.Get("equipment")
    local newEquip = equipData and equipData.inventory and equipData.inventory[detState.equipSeq]
    local isEquipped = isClickedEquipEquipped()
    local curEquip = getComparisonEquip()
    local hasCurrent = (not isEquipped) and (curEquip ~= nil)
    local btnText = isEquipped and "卸下" or (hasCurrent and "更换" or "穿戴")
    local newPower = newEquip and calcEquipPower(newEquip, detState.heroId) or 0
    local curPower = curEquip and calcEquipPower(curEquip, detState.heroId) or 0
    detState.snapshot = {
        newEquip   = newEquip,
        isEquipped = isEquipped,
        curEquip   = curEquip,
        hasCurrent = hasCurrent,
        btnText    = btnText,
        powerDiff  = newPower - curPower,
    }
    detState.closing   = true
    detState.closeTime = time.elapsedTime
    print("[EquipmentDetail] close")
end

--- 是否打开
---@return boolean
function EquipmentDetail.isOpen()
    return detState.open
end

--- 判断当前点击的装备是否已穿戴
---@return boolean isEquipped, string|nil equippedSlot 已装备的实际槽位
isClickedEquipEquipped = function()
    local equipData = PlayerStore.Get("equipment")
    if not equipData or not equipData.equipped then return false, nil end
    local heroEquipped = equipData.equipped[detState.heroId]
    if not heroEquipped then return false, nil end

    local seqStr = detState.equipSeq
    local slot = detState.slot

    -- 直接检查该槽位
    if heroEquipped[slot] and tostring(heroEquipped[slot]) == seqStr then
        return true, slot
    end

    -- 副手槽位：检查主手是否为该双手武器
    if slot == "offhand" and heroEquipped["weapon"] then
        local wSeqStr = tostring(heroEquipped["weapon"])
        if wSeqStr == seqStr then
            return true, "weapon"
        end
    end

    return false, nil
end

--- 获取用于对比的"当前装备"（处理副手对比双手武器场景）
---@return table|nil curEquip, number|nil curSeq
getComparisonEquip = function()
    local equipData = PlayerStore.Get("equipment")
    if not equipData or not equipData.equipped then return nil, nil end
    local heroEquipped = equipData.equipped[detState.heroId]
    if not heroEquipped then return nil, nil end

    local slot = detState.slot

    -- 直接获取该槽位的装备
    local curSeq = heroEquipped[slot]
    if curSeq and tostring(curSeq) ~= detState.equipSeq then
        local curEquip = equipData.inventory and equipData.inventory[tostring(curSeq)]
        if curEquip then return curEquip, curSeq end
    end

    -- 副手槽位：如果副手没有装备，检查主手是否为双手武器（副手被占用）
    if slot == "offhand" and not curSeq then
        local weaponSeq = heroEquipped["weapon"]
        if weaponSeq then
            local weaponEquip = equipData.inventory and equipData.inventory[tostring(weaponSeq)]
            if weaponEquip and weaponEquip.grip == "twohand" then
                return weaponEquip, weaponSeq
            end
        end
    end

    return nil, nil
end

--- 处理点击
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function EquipmentDetail.handleInput(dx, dy)
    if not detState.open then return false end
    if detState.closing then return true end

    local equipData = PlayerStore.Get("equipment")
    if not equipData then return true end

    local newEquip = equipData.inventory and equipData.inventory[detState.equipSeq]
    if not newEquip then
        EquipmentDetail.close()
        return true
    end

    -- 判断是否为已穿戴装备
    local isEquipped, equippedSlot = isClickedEquipEquipped()

    -- 判断是否有对比装备
    local curEquip = getComparisonEquip()
    local hasCurrent = (not isEquipped) and (curEquip ~= nil)

    -- 按钮位置（与绘制一致）
    local btnCX, btnCY
    local offsetX = 0
    if hasCurrent then
        btnCX = REF_BTN_CX  -- 双面板模式，按钮在右面板
        btnCY = REF_BTN_CY
        offsetX = 0
    else
        offsetX = SINGLE_BG_CX - REF_BG_CX
        btnCX = REF_BTN_CX + offsetX  -- 单面板居中
        btnCY = REF_BTN_CY
    end

    -- 动态调整按钮Y（与绘制逻辑一致）
    if newEquip.affixes and #newEquip.affixes > 0 then
        local baseStatCount = newEquip.baseStats and #newEquip.baseStats or 0
        local affixTitleY = REF_AFFIX_TITLE_Y
        if baseStatCount ~= 0 then
            local baseStatEndY = REF_STAT_BG_Y0 + (baseStatCount - 1) * (REF_STAT_BG_H + REF_STAT_GAP) + REF_STAT_BG_H * 0.5
            local minGap = 30
            if affixTitleY < baseStatEndY + minGap then
                affixTitleY = baseStatEndY + minGap
            end
        end
        local lastAffixY = affixTitleY + REF_AFFIX_TITLE_FONT * 0.5 + REF_AFFIX_GAP_TOP + REF_AFFIX_ROW_H * 0.5
            + (#newEquip.affixes - 1) * (REF_AFFIX_ROW_H + REF_AFFIX_GAP)
        local minBtnGap = 40
        if btnCY < lastAffixY + REF_AFFIX_ROW_H * 0.5 + minBtnGap then
            btnCY = lastAffixY + REF_AFFIX_ROW_H * 0.5 + minBtnGap
        end
    end

    -- 前往洗练按钮Y
    local enhOnly = (detState.slot == nil)  -- 背包模式
    local enhBtnCY
    if enhOnly then
        enhBtnCY = btnCY  -- 背包模式：顶替穿戴按钮位置
    else
        enhBtnCY = REF_BG_CY + REF_BG_H * 0.5 + REF_ENH_BTN_GAP + REF_ENH_BTN_H * 0.5
    end

    -- 点击前往洗练按钮（仅铁匠铺已解锁时响应）
    if ExpTable.isBuildingUnlocked("smith", GameState.getLevel())
       and hitTest(dx, dy, btnCX, enhBtnCY, REF_ENH_BTN_W, REF_ENH_BTN_H) then
        BF.trigger("ed_enhance")
        -- 延迟加载依赖模块
        if not BlacksmithPage then BlacksmithPage = require("ui.BlacksmithPage") end
        if not EquipmentBag then EquipmentBag = require("ui.EquipmentBag") end
        if not BottomNav then BottomNav = require("ui.BottomNav") end
        if not CharacterDetail then CharacterDetail = require("ui.CharacterDetail") end

        -- 1) 立即关闭装备详情（不走动画，直接重置状态）
        detState.open    = false
        detState.closing = false
        detState.snapshot = nil

        -- 2) 关闭背包（EquipmentBag 或 BackpackPanel）
        if EquipmentBag.isOpen() then
            EquipmentBag.close()
        end
        local BackpackPanel = require("ui.BackpackPanel")
        if BackpackPanel.isOpen() then
            BackpackPanel.close()
        end

        -- 3) 强制关闭角色详情（跳过动画，否则 isDetailOpen()=true 会阻止 BottomNav 绘制）
        if CharacterDetail.isOpen() then
            CharacterDetail.forceClose()
        end

        -- 4) 切换底部标签栏到"城镇"（index=4），铁匠铺在城镇页内绘制
        BottomNav.setSelectedIndex(4)

        -- 5) 打开铁匠铺洗练面板并预选装备
        BlacksmithPage.open(newEquip, "xilian")
        print("[EquipmentDetail] 前往洗练 → 切换城镇 + 打开铁匠铺洗练面板，装备: " .. (newEquip.name or "?"))
        return true
    end

    -- 点击立即分解按钮（未穿戴未锁定装备，前往洗练下方；背包模式与角色槽位模式通用）
    if (not newEquip.locked) and (not isEquipped)
       and ExpTable.isBuildingUnlocked("smith", GameState.getLevel()) then
        local decBtnCY = enhBtnCY + REF_ENH_BTN_H + REF_DEC_BTN_GAP
        if hitTest(dx, dy, btnCX, decBtnCY, REF_ENH_BTN_W, REF_ENH_BTN_H) then
            BF.trigger("ed_decompose")
            local Client = getClient()
            local Protocol = getProtocol()
            if Client and Client.sendAction and Protocol then
                Client.sendAction(Protocol.ACTION_TYPES.DECOMPOSE_EQUIP, {
                    seqs = { tonumber(detState.equipSeq) },
                })
                detState.pendingDecompose = true   -- 标记由本面板发起，供 onActionResult 弹出奖励
                print("[EquipmentDetail] 立即分解 seq=" .. tostring(detState.equipSeq))
            end
            EquipmentDetail.close()
            return true
        end
    end

    -- 点击穿戴/卸下按钮（背包模式不显示此按钮，跳过）
    if not enhOnly and hitTest(dx, dy, btnCX, btnCY, REF_BTN_W, REF_BTN_H) then
        BF.trigger("ed_equip")
        local Client = getClient()
        local Protocol = getProtocol()
        if Client and Client.sendAction and Protocol then
            if isEquipped then
                -- 卸下装备
                Client.sendAction(Protocol.ACTION_TYPES.UNEQUIP_ITEM, {
                    heroId = detState.heroId,
                    slot   = equippedSlot or detState.slot,
                })
                print("[EquipmentDetail] 发送卸下请求 slot=" .. tostring(equippedSlot or detState.slot))
            else
                -- 穿戴/更换装备
                Client.sendAction(Protocol.ACTION_TYPES.EQUIP_ITEM, {
                    seq    = tonumber(detState.equipSeq),
                    heroId = detState.heroId,
                    slot   = detState.slot,
                })
                print("[EquipmentDetail] 发送穿戴请求 seq=" .. detState.equipSeq)
                require("systems.GameSFX").play("install")
            end
        end
        -- 乐观更新本地 equipment 缓存，立即刷新角标（不等服务端推送）
        local okPS, PS = pcall(require, "client.data.PlayerStore")
        if okPS then
            local eq = PS.Get("equipment")
            if eq then
                eq.equipped = eq.equipped or {}
                local hid = tostring(detState.heroId)
                if isEquipped then
                    -- 卸下：清除对应槽位
                    local sl = equippedSlot or detState.slot
                    if eq.equipped[hid] then
                        eq.equipped[hid][sl] = nil
                    end
                else
                    -- 穿戴：写入 seq
                    eq.equipped[hid] = eq.equipped[hid] or {}
                    eq.equipped[hid][detState.slot] = tonumber(detState.equipSeq)
                end
            end
        end
        local okCP, CP = pcall(require, "ui.CharacterPanel")
        if okCP and CP.refreshBadge then CP.refreshBadge() end
        EquipmentDetail.close()
        return true
    end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - detState.openTime < 0.05 then return true end

    -- 点击锁定图标 → 切换锁定状态
    if detState.lockHotspot
       and hitTest(dx, dy, detState.lockHotspot.cx, detState.lockHotspot.cy,
                   detState.lockHotspot.w, detState.lockHotspot.h) then
        BF.trigger("ed_equip")
        local Client = getClient()
        local Protocol = getProtocol()
        if Client and Client.sendAction and Protocol then
            Client.sendAction(Protocol.ACTION_TYPES.TOGGLE_EQUIP_LOCK, {
                seq = tonumber(detState.equipSeq),
            })
        end
        -- 乐观更新本地缓存，立即刷新锁图标
        newEquip.locked = (not newEquip.locked) or nil
        print("[EquipmentDetail] 切换装备锁定 seq=" .. tostring(detState.equipSeq)
            .. " locked=" .. tostring(newEquip.locked == true))
        return true
    end

    -- 点击面板外部 → 关闭
    local inPanel = false
    if hasCurrent then
        if hitTest(dx, dy, CUR_BG_CX, CUR_BG_CY, CUR_BG_W, CUR_BG_H)
           or hitTest(dx, dy, REF_BG_CX, REF_BG_CY, REF_BG_W, REF_BG_H) then
            inPanel = true
        end
    else
        if hitTest(dx, dy, SINGLE_BG_CX, REF_BG_CY, REF_BG_W, REF_BG_H) then
            inPanel = true
        end
    end

    -- 穿戴按钮区域也算面板内
    if hitTest(dx, dy, btnCX, btnCY, REF_BTN_W + 40, REF_BTN_H + 40) then
        inPanel = true
    end
    -- 前往洗练按钮区域也算面板内
    if hitTest(dx, dy, btnCX, enhBtnCY, REF_ENH_BTN_W + 40, REF_ENH_BTN_H + 40) then
        inPanel = true
    end

    if not inPanel then
        EquipmentDetail.close()
        return true
    end

    return true
end

--- 绘制
---@param vg any NanoVG 上下文
function EquipmentDetail.draw(vg)
    if not detState.open then return end

    -- 动画计算
    local progress, slideOY

    if detState.closing then
        local elapsed = time.elapsedTime - detState.closeTime
        local rawT = math.min(1.0, elapsed / ANIM_CLOSE_DUR)
        progress = 1 - easeInCubic(rawT)
        if rawT >= 1.0 then
            detState.open     = false
            detState.closing  = false
            detState.snapshot = nil
            return
        end
    else
        local elapsed = time.elapsedTime - detState.openTime
        local rawT = math.min(1.0, elapsed / ANIM_OPEN_DUR)
        progress = easeOutCubic(rawT)
    end

    slideOY = SLIDE_DIST * (1 - progress)
    local overlayAlpha = math.floor(120 * progress)

    -- 获取渲染数据：关闭动画期间使用快照，避免 server 推送导致面板内容跳变
    local newEquip, isEquipped, curEquip, hasCurrent, powerDiff, btnText

    if detState.closing and detState.snapshot then
        local s = detState.snapshot
        newEquip   = s.newEquip
        isEquipped = s.isEquipped
        curEquip   = s.curEquip
        hasCurrent = s.hasCurrent
        powerDiff  = s.powerDiff
        btnText    = s.btnText
    else
        local equipData = PlayerStore.Get("equipment")
        if not equipData or not equipData.inventory then return end
        newEquip = equipData.inventory[detState.equipSeq]
        if not newEquip then return end
        isEquipped = isClickedEquipEquipped()
        curEquip = getComparisonEquip()
        hasCurrent = (not isEquipped) and (curEquip ~= nil)
        btnText = isEquipped and "卸下" or (hasCurrent and "更换" or "穿戴")
        local newPower = calcEquipPower(newEquip, detState.heroId)
        local curPower = curEquip and calcEquipPower(curEquip, detState.heroId) or 0
        powerDiff = newPower - curPower
    end

    if not newEquip then return end

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)

    -- 应用滑入偏移
    nvgSave(vg)
    nvgTranslate(vg, 0, slideOY)

    local enhOnly = (detState.slot == nil)  -- 背包模式：无穿戴按钮，仅前往洗练

    if hasCurrent then
        -- ===== 双面板布局（有对比装备） =====
        local curOffsetX = CUR_BG_CX - REF_BG_CX

        drawEquipPanel(vg, curEquip, curOffsetX,
            CUR_BG_CX, CUR_BG_CY, CUR_BG_W, CUR_BG_H,
            nil, false, "", false)

        -- 点击的是背包未穿戴装备，未锁定时显示「立即分解」
        local showDecompose = (not newEquip.locked)
        drawEquipPanel(vg, newEquip, 0,
            REF_BG_CX, REF_BG_CY, REF_BG_W, REF_BG_H,
            powerDiff, true, btnText, enhOnly, true, showDecompose)
    elseif isEquipped then
        -- ===== 单面板布局（已穿戴） =====
        local singleOffsetX = SINGLE_BG_CX - REF_BG_CX

        drawEquipPanel(vg, newEquip, singleOffsetX,
            SINGLE_BG_CX, REF_BG_CY, REF_BG_W, REF_BG_H,
            nil, true, btnText, enhOnly, true)
    else
        -- ===== 单面板布局（未穿戴） =====
        local singleOffsetX = SINGLE_BG_CX - REF_BG_CX

        -- 未穿戴且未锁定时，显示「立即分解」按钮
        local showDecompose = (not newEquip.locked)
        drawEquipPanel(vg, newEquip, singleOffsetX,
            SINGLE_BG_CX, REF_BG_CY, REF_BG_W, REF_BG_H,
            nil, true, btnText, enhOnly, true, showDecompose)
    end

    nvgRestore(vg)
end

--- 处理 action 结果：当「立即分解」由本面板发起时，弹出分解奖励
--- （铁匠铺未打开时 BlacksmithPage.onActionResult 会提前 return，需要本模块兜底展示奖励）
---@param data table
function EquipmentDetail.onActionResult(data)
    if not detState.pendingDecompose then return end
    local Protocol = getProtocol()
    -- 仅处理分解结果（成功/失败都清除标记，避免后续误弹）
    if Protocol and data.action ~= Protocol.ACTION_TYPES.DECOMPOSE_EQUIP then return end
    detState.pendingDecompose = false
    if data.decomposed then
        local rewards = {}
        if (data.essenceReward or 0) > 0 then
            rewards[#rewards + 1] = { type = "essence", amount = data.essenceReward }
        end
        if (data.goldReward or 0) > 0 then
            rewards[#rewards + 1] = { type = "gold", amount = data.goldReward }
        end
        if #rewards > 0 then
            require("ui.RewardPopup").show("分解奖励", rewards)
        end
    end
end

--- 暴露战斗力计算供 EquipmentBag 角标判断使用
EquipmentDetail.calcEquipPower = calcEquipPower

return EquipmentDetail
