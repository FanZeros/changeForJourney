-- ============================================================================
-- AdvancementConfig - 转职配置数据表
-- 数据来源: docs/配置文件/职业配置.txt
-- 包含: 12个一转 + 24个二转（六门契）。数字ID保留，talentId 已换；207/220 双持 id 保留
-- ============================================================================

local AD = require("systems.AttributeDef")
local CC = require("config.ClassConfig")

local AVC = {}

-- ======================== 转职等级常量 ========================

AVC.ADV_FIRST  = 1   -- 一转
AVC.ADV_SECOND = 2   -- 二转

-- ======================== 转职消耗 ========================

AVC.COST = {
    [1] = { level = 10, gold = 10000    },   -- 一转要求
    [2] = { level = 25, gold = 100000   },   -- 二转要求
}

-- ======================== 一转配置表 ========================
-- id           : 一转 branch ID (101~112)
-- name         : 一转职业名称
-- baseClass    : 前置基础职业 (CC.KNIGHT 等)
-- advLevel     : 转职等级 (1)
-- statBonus    : 属性加成 { { key=AD.xxx, flat=n }, ... }
-- talentName   : 天赋名称
-- talentDesc   : 天赋效果描述
-- talentId     : 天赋内部 ID (用于 TalentManager 路由)
-- combatPower  : 天赋提供的战斗力

AVC.BRANCHES = {
    -- ==================== 骑士一转 ====================
    [101] = {
        name = "门闩", baseClass = CC.KNIGHT, advLevel = 1,
        statBonus = {
            { key = AD.VIT, flat = 5 },
            { key = AD.SPI, flat = 5 },
        },
        talentName = "门闩",
        talentDesc = "门缝容量+50%。释放伤害的50%改为打敌人。",
        talentId = "gate_101_latch",
        combatPower = 15,
    },
    [102] = {
        name = "闸门", baseClass = CC.KNIGHT, advLevel = 1,
        statBonus = {
            { key = AD.VIT, flat = 5 },
            { key = AD.STR, flat = 5 },
        },
        talentName = "闸门",
        talentDesc = "门缝满时强制嘲讽2秒，并清空30%门缝（打自己的那部分免了）。",
        talentId = "gate_102_sluice",
        combatPower = 15,
    },
    -- ==================== 战士一转 ====================
    [103] = {
        name = "骨市", baseClass = CC.WARRIOR, advLevel = 1,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.VIT, flat = 5 },
        },
        talentName = "骨市",
        talentDesc = "骸骨上限12→18。消耗时回复4%已损失生命。",
        talentId = "gate_103_bone_market",
        combatPower = 15,
    },
    [104] = {
        name = "剥壳", baseClass = CC.WARRIOR, advLevel = 1,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.AGI, flat = 5 },
        },
        talentName = "剥壳",
        talentDesc = "对精英/Boss击杀也给3骨。消耗攻击改为打护甲克制优势目标。",
        talentId = "gate_104_peel",
        combatPower = 15,
    },
    -- ==================== 法师一转 ====================
    [105] = {
        name = "错位", baseClass = CC.MAGE, advLevel = 1,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.SPI, flat = 5 },
        },
        talentName = "错位",
        talentDesc = "裂隙冷却8→6秒。裂痕满3层时打一次60%魔攻。",
        talentId = "gate_105_offset",
        combatPower = 15,
    },
    [106] = {
        name = "深缝", baseClass = CC.MAGE, advLevel = 1,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.LUK, flat = 5 },
        },
        talentName = "深缝",
        talentDesc = "裂隙期间自身攻击附加随机次类型（火/冰/雷/暗轮换）。",
        talentId = "gate_106_deep",
        combatPower = 15,
    },
    -- ==================== 射手一转 ====================
    [107] = {
        name = "残响", baseClass = CC.RANGER, advLevel = 1,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.STR, flat = 5 },
        },
        talentName = "残响",
        talentDesc = "回响可暴击（主人暴击率40%）。回响延迟1.2→0.8秒。",
        talentId = "gate_107_aftertone",
        combatPower = 15,
    },
    [108] = {
        name = "叠声", baseClass = CC.RANGER, advLevel = 1,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.LUK, flat = 5 },
        },
        talentName = "叠声",
        talentDesc = "同一目标身上第2个回响改为70%伤害，最多2个。",
        talentId = "gate_108_stacktone",
        combatPower = 15,
    },
    -- ==================== 刺客一转 ====================
    [109] = {
        name = "借面", baseClass = CC.ASSASSIN, advLevel = 1,
        statBonus = {
            { key = AD.LUK, flat = 5 },
            { key = AD.AGI, flat = 5 },
        },
        talentName = "借面",
        talentDesc = "复制目标时额外偷一条：目标会治疗则下次攻击8%吸血，否则8%攻速4秒。",
        talentId = "gate_109_borrow",
        combatPower = 15,
    },
    [110] = {
        name = "剥面", baseClass = CC.ASSASSIN, advLevel = 1,
        statBonus = {
            { key = AD.LUK, flat = 5 },
            { key = AD.STR, flat = 5 },
        },
        talentName = "剥面",
        talentDesc = "目标死亡时对邻近敌人也挂2秒「面」（破甲）。",
        talentId = "gate_110_stripface",
        combatPower = 15,
    },
    -- ==================== 牧师一转 ====================
    [111] = {
        name = "延祷", baseClass = CC.PRIEST, advLevel = 1,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.LUK, flat = 5 },
        },
        talentName = "延祷",
        talentDesc = "延缓可同时存在于2名队友。",
        talentId = "gate_111_defer2",
        combatPower = 15,
    },
    [112] = {
        name = "领忏", baseClass = CC.PRIEST, advLevel = 1,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.VIT, flat = 5 },
        },
        talentName = "领忏",
        talentDesc = "债结束时，按债期受到伤害的10%治疗全队（有上限）。",
        talentId = "gate_112_confess",
        combatPower = 15,
    },

    -- ==================== 二转职业 ====================

    -- ===== 圣骑士 → 二转 =====
    [201] = {
        name = "封条", baseClass = CC.KNIGHT, advLevel = 2,
        parentBranch = 101,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.VIT, flat = 5 },
            { key = AD.HEAL_BONUS, flat = 20 },
        },
        talentName = "封条",
        talentDesc = "门缝释放改为100%打敌人，自己不挨。",
        talentId = "gate_201_seal_strip",
        combatPower = 20,
    },
    [202] = {
        name = "殉门", baseClass = CC.KNIGHT, advLevel = 2,
        parentBranch = 101,
        statBonus = {
            { key = AD.VIT, flat = 5 },
            { key = AD.STR, flat = 5 },
            { key = AD.MAG_ARMOR, flat = 7 },
        },
        talentName = "殉门",
        talentDesc = "门缝爆炸时全队获得3秒8%减伤。",
        talentId = "gate_202_martyr",
        combatPower = 20,
    },
    -- ===== 龙骑士 → 二转 =====
    [203] = {
        name = "死闸", baseClass = CC.KNIGHT, advLevel = 2,
        parentBranch = 102,
        statBonus = {
            { key = AD.VIT, flat = 5 },
            { key = AD.STR, flat = 5 },
            { key = AD.PHYS_ARMOR, flat = 7 },
        },
        talentName = "死闸",
        talentDesc = "嘲讽时门缝不打自己。",
        talentId = "gate_203_deadgate",
        combatPower = 20,
    },
    [204] = {
        name = "反冲闸", baseClass = CC.KNIGHT, advLevel = 2,
        parentBranch = 102,
        statBonus = {
            { key = AD.VIT, flat = 5 },
            { key = AD.AGI, flat = 5 },
            { key = AD.PHYS_CRIT_RATE, flat = 6.25 },
        },
        talentName = "反冲闸",
        talentDesc = "嘲讽结束立刻填40%攻击进度。",
        talentId = "gate_204_recoil",
        combatPower = 20,
    },
    -- ===== 狂战士 → 二转 =====
    [205] = {
        name = "骨潮", baseClass = CC.WARRIOR, advLevel = 2,
        parentBranch = 103,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.AGI, flat = 5 },
            { key = AD.PHYS_CRIT_RATE, flat = 6.25 },
        },
        talentName = "骨潮",
        talentDesc = "消耗不花骨，改为每秒掉1骨，期间永久40%额外段。",
        talentId = "gate_205_tide",
        combatPower = 20,
    },
    [206] = {
        name = "骨债", baseClass = CC.WARRIOR, advLevel = 2,
        parentBranch = 103,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.VIT, flat = 5 },
            { key = AD.CRIT_DMG, flat = 25 },
        },
        talentName = "骨债",
        talentDesc = "消耗时自损3%当前生命，额外段80%。",
        talentId = "gate_206_bone_debt",
        combatPower = 20,
    },
    -- ===== 决斗者 → 二转 =====
    [207] = {
        name = "双械", baseClass = CC.WARRIOR, advLevel = 2,
        parentBranch = 104,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.AGI, flat = 5 },
            { key = AD.PHYS_PEN, flat = 10 },
        },
        talentName = "双械",
        talentDesc = "无法再装备常规副手，但可在副手装备与主手不同类型的武器。骸骨获取-30%。",
        talentId = "adv_207_weapon_master",
        combatPower = 20,
    },
    [208] = {
        name = "连剥", baseClass = CC.WARRIOR, advLevel = 2,
        parentBranch = 104,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.PHYS_CRIT_DMG, flat = 33 },
        },
        talentName = "连剥",
        talentDesc = "对同一目标连续攻击时骸骨获取+1，换目标清。",
        talentId = "gate_208_peelchain",
        combatPower = 20,
    },
    -- ===== 咒术师 → 二转 =====
    [209] = {
        name = "群缝", baseClass = CC.MAGE, advLevel = 2,
        parentBranch = 105,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.VIT, flat = 5 },
            { key = AD.MAG_PEN, flat = 10 },
        },
        talentName = "群缝",
        talentDesc = "裂痕同时上全体敌人，效果70%。",
        talentId = "gate_209_mass",
        combatPower = 20,
    },
    [210] = {
        name = "蚀缝", baseClass = CC.MAGE, advLevel = 2,
        parentBranch = 105,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.SPI, flat = 5 },
            { key = AD.MAG_CRIT_RATE, flat = 6.25 },
        },
        talentName = "蚀缝",
        talentDesc = "裂痕目标每次受伤额外50%魔攻暗影，1秒CD。",
        talentId = "gate_210_corrode",
        combatPower = 20,
    },
    -- ===== 魔导师 → 二转 =====
    [211] = {
        name = "择缝", baseClass = CC.MAGE, advLevel = 2,
        parentBranch = 106,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.SPI, flat = 5 },
            { key = AD.MAG_CRIT_RATE, flat = 6.25 },
        },
        talentName = "择缝",
        talentDesc = "轮换改为锁定克制最优的次类型。",
        talentId = "gate_211_choose",
        combatPower = 20,
    },
    [212] = {
        name = "爆缝", baseClass = CC.MAGE, advLevel = 2,
        parentBranch = 106,
        statBonus = {
            { key = AD.INT, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.MAG_PEN, flat = 10 },
        },
        talentName = "爆缝",
        talentDesc = "次类型切换时对邻敌100%魔攻。",
        talentId = "gate_212_burst",
        combatPower = 20,
    },
    -- ===== 巡林客 → 二转 =====
    [213] = {
        name = "风回", baseClass = CC.RANGER, advLevel = 2,
        parentBranch = 107,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.STR, flat = 5 },
            { key = AD.ATK_SPEED, flat = 15 },
        },
        talentName = "风回",
        talentDesc = "回响命中给自己12%攻速5秒，最多3层。",
        talentId = "gate_213_wind",
        combatPower = 20,
    },
    [214] = {
        name = "瞳回", baseClass = CC.RANGER, advLevel = 2,
        parentBranch = 107,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.CRIT_DMG, flat = 33 },
        },
        talentName = "瞳回",
        talentDesc = "回响必定暴击，叠暴伤层。",
        talentId = "gate_214_eye",
        combatPower = 20,
    },
    -- ===== 弓箭手 → 二转 =====
    [215] = {
        name = "瞄回", baseClass = CC.RANGER, advLevel = 2,
        parentBranch = 108,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.PHYS_PEN, flat = 10 },
        },
        talentName = "瞄回",
        talentDesc = "回响吃穿透；叠声第2击额外加穿透。",
        talentId = "gate_215_aim",
        combatPower = 20,
    },
    [216] = {
        name = "重回", baseClass = CC.RANGER, advLevel = 2,
        parentBranch = 108,
        statBonus = {
            { key = AD.STR, flat = 5 },
            { key = AD.AGI, flat = 5 },
            { key = AD.CRIT_DMG, flat = 25 },
        },
        talentName = "重回",
        talentDesc = "攻速锁100%；多余攻速按1:2变为回响系数。",
        talentId = "gate_216_heavy",
        combatPower = 20,
    },
    -- ===== 暗杀者 → 二转 =====
    [217] = {
        name = "静面", baseClass = CC.ASSASSIN, advLevel = 2,
        parentBranch = 109,
        statBonus = {
            { key = AD.LUK, flat = 5 },
            { key = AD.STR, flat = 5 },
            { key = AD.CRIT_DMG, flat = 33 },
        },
        talentName = "静面",
        talentDesc = "5秒未挨打则「面」破甲20%→40%。",
        talentId = "gate_217_still",
        combatPower = 20,
    },
    [218] = {
        name = "千面", baseClass = CC.ASSASSIN, advLevel = 2,
        parentBranch = 109,
        statBonus = {
            { key = AD.AGI, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.PHYS_PEN, flat = 10 },
        },
        talentName = "千面",
        talentDesc = "5秒未挨打则攻速+40%（不加暴击）。",
        talentId = "gate_218_thousand",
        combatPower = 20,
    },
    -- ===== 影袭者 → 二转 =====
    [219] = {
        name = "致命面", baseClass = CC.ASSASSIN, advLevel = 2,
        parentBranch = 110,
        statBonus = {
            { key = AD.LUK, flat = 5 },
            { key = AD.AGI, flat = 5 },
            { key = AD.CRIT_RATE, flat = 6.25 },
        },
        talentName = "致命面",
        talentDesc = "暴击时攻击进度+100%，每轮1次。职业不加暴击。",
        talentId = "gate_219_lethal",
        combatPower = 20,
    },
    [220] = {
        name = "双面", baseClass = CC.ASSASSIN, advLevel = 2,
        parentBranch = 110,
        statBonus = {
            { key = AD.LUK, flat = 5 },
            { key = AD.STR, flat = 5 },
            { key = AD.PHYS_PEN, flat = 10 },
        },
        talentName = "双面",
        talentDesc = "无法再装备常规副手，但可在副手装备与主手相同类型的武器。",
        talentId = "adv_220_dual_blade",
        combatPower = 20,
    },
    -- ===== 大祭祀 → 二转 =====
    [221] = {
        name = "战祷", baseClass = CC.PRIEST, advLevel = 2,
        parentBranch = 111,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.INT, flat = 5 },
            { key = AD.HEAL_BONUS, flat = 20 },
        },
        talentName = "战祷",
        talentDesc = "延缓触发后，该队友下次攻击+25%伤。",
        talentId = "gate_221_war",
        combatPower = 20,
    },
    [222] = {
        name = "血祷", baseClass = CC.PRIEST, advLevel = 2,
        parentBranch = 111,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.LUK, flat = 5 },
            { key = AD.HEAL_CRIT_RATE, flat = 6.25 },
        },
        talentName = "血祷",
        talentDesc = "延缓改为40%概率，但触发时按伤害回血。",
        talentId = "gate_222_blood",
        combatPower = 20,
    },
    -- ===== 大主教 → 二转 =====
    [223] = {
        name = "大赦", baseClass = CC.PRIEST, advLevel = 2,
        parentBranch = 112,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.VIT, flat = 5 },
            { key = AD.HEAL_BONUS, flat = 20 },
        },
        talentName = "大赦",
        talentDesc = "债结束治疗×3；低于20%生命必治疗暴击。",
        talentId = "gate_223_pardon",
        combatPower = 20,
    },
    [224] = {
        name = "罚忏", baseClass = CC.PRIEST, advLevel = 2,
        parentBranch = 112,
        statBonus = {
            { key = AD.SPI, flat = 5 },
            { key = AD.INT, flat = 5 },
            { key = AD.MAG_PEN, flat = 10 },
        },
        talentName = "罚忏",
        talentDesc = "治疗时40%对随机敌打治疗量300%暗影。",
        talentId = "gate_224_punish",
        combatPower = 20,
    },
}

-- ======================== 一转分支映射 ========================
-- baseClass → { branchId1, branchId2 }

AVC.FIRST_BRANCHES = {
    [CC.KNIGHT]   = { 101, 102 },
    [CC.WARRIOR]  = { 103, 104 },
    [CC.MAGE]     = { 105, 106 },
    [CC.RANGER]   = { 107, 108 },
    [CC.ASSASSIN] = { 109, 110 },
    [CC.PRIEST]   = { 111, 112 },
}

-- ======================== 二转分支映射 ========================
-- firstBranchId → { branchId1, branchId2 }

AVC.SECOND_BRANCHES = {
    [101] = { 201, 202 },
    [102] = { 203, 204 },
    [103] = { 205, 206 },
    [104] = { 207, 208 },
    [105] = { 209, 210 },
    [106] = { 211, 212 },
    [107] = { 213, 214 },
    [108] = { 215, 216 },
    [109] = { 217, 218 },
    [110] = { 219, 220 },
    [111] = { 221, 222 },
    [112] = { 223, 224 },
}

-- ======================== 辅助方法 ========================

--- 获取转职分支配置
---@param branchId number 101~224
---@return table|nil
function AVC.get(branchId)
    return AVC.BRANCHES[branchId]
end

--- 获取英雄当前最高的转职分支 ID
--- 优先返回二转，否则一转，否则 nil
---@param advBranch table|nil 英雄存档中的 advBranch = { first=number?, second=number? }
---@return number|nil 最高转职分支ID
function AVC.getHighestBranch(advBranch)
    if not advBranch then return nil end
    return advBranch.second or advBranch.first
end

--- 获取英雄所有已完成的转职分支 ID 列表（用于属性叠加）
--- 返回 { firstBranchId?, secondBranchId? }
---@param advBranch table|nil
---@return number[] 已完成的转职分支 ID 列表
function AVC.getAllBranches(advBranch)
    if not advBranch then return {} end
    local list = {}
    if advBranch.first then
        list[#list + 1] = advBranch.first
    end
    if advBranch.second then
        list[#list + 1] = advBranch.second
    end
    return list
end

--- 应用转职属性加成到 UnitAttributes
---@param advBranch table|nil 英雄存档中的 advBranch
---@param attrs table UnitAttributes 实例
function AVC.applyStatBonuses(advBranch, attrs)
    local branches = AVC.getAllBranches(advBranch)
    for _, branchId in ipairs(branches) do
        local cfg = AVC.BRANCHES[branchId]
        if cfg and cfg.statBonus then
            attrs:addModifier("adv_stat_" .. branchId, cfg.statBonus)
        end
    end
end

--- 校验是否可以执行转职
---@param heroLevel number 英雄等级
---@param gold number 当前金币
---@param advLevel number 转职等级 (1=一转, 2=二转)
---@param classId string 英雄职业 ID
---@param branchId number 目标转职分支 ID
---@param advBranch table|nil 已有转职数据
---@return boolean ok, string? reason
function AVC.canAdvance(heroLevel, gold, advLevel, classId, branchId, advBranch)
    local req = AVC.COST[advLevel]
    if not req then
        return false, "无效的转职等级"
    end

    local branch = AVC.BRANCHES[branchId]
    if not branch then
        return false, "无效的转职分支"
    end

    -- 校验转职等级匹配
    if branch.advLevel ~= advLevel then
        return false, "转职等级不匹配"
    end

    -- 校验等级要求
    if heroLevel < req.level then
        return false, "英雄等级不足（需要 Lv" .. req.level .. "）"
    end

    -- 校验金币
    if gold < req.gold then
        return false, "金币不足（需要 " .. req.gold .. "）"
    end

    if advLevel == 1 then
        -- 一转：不能已有一转
        if advBranch and advBranch.first then
            return false, "已完成一转"
        end
        -- 校验职业匹配
        if branch.baseClass ~= classId then
            return false, "职业不匹配"
        end
    elseif advLevel == 2 then
        -- 二转：必须已有一转
        if not advBranch or not advBranch.first then
            return false, "未完成一转"
        end
        -- 不能已有二转
        if advBranch.second then
            return false, "已完成二转"
        end
        -- 校验前置一转匹配
        if branch.parentBranch ~= advBranch.first then
            return false, "前置一转不匹配"
        end
    end

    return true
end

--- 检查英雄是否拥有指定 talentId 的转职天赋
---@param advBranch table|nil 英雄存档中的 advBranch = { first=number?, second=number? }
---@param talentId string 天赋 ID（如 "adv_207_weapon_master"）
---@return boolean
function AVC.hasTalent(advBranch, talentId)
    if not advBranch then return false end
    local branches = AVC.getAllBranches(advBranch)
    for _, bId in ipairs(branches) do
        local cfg = AVC.BRANCHES[bId]
        if cfg and cfg.talentId == talentId then
            return true
        end
    end
    return false
end

--- 获取 207/220 天赋的副手武器模式
--- 返回 "different"(207武器精通)、"same"(220双刃精通)、nil(无此天赋)
---@param advBranch table|nil
---@return string|nil mode "different"|"same"|nil
function AVC.getDualWieldMode(advBranch)
    if AVC.hasTalent(advBranch, "adv_207_weapon_master") then
        return "different"
    end
    if AVC.hasTalent(advBranch, "adv_220_dual_blade") then
        return "same"
    end
    return nil
end

return AVC
