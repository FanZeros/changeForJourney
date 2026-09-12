-- ============================================================================
-- UnitAttributes - 单位属性容器
-- 四层计算: base(基础) + derived(六围派生) + flatMod(平值修改) → final(最终)
-- 百分比修改器单独累加后乘算到 final
-- ============================================================================

local AD = require("systems.AttributeDef")

local UnitAttributes = {}
UnitAttributes.__index = UnitAttributes

-- ======================== 构造 ========================

--- 创建属性容器
---@param cfg table 初始属性 { str=10, maxHp=500, physAtk=20, atkInterval=2.0, armorType=1, ... }
---@return table UnitAttributes 实例
function UnitAttributes.create(cfg)
    cfg = cfg or {}

    local self = setmetatable({}, UnitAttributes)

    -- 护甲类型（不是数值属性，单独存放）
    self.armorType = cfg.armorType or AD.ARMOR_LEATHER

    -- 默认攻击类型
    self.atkType = cfg.atkType or AD.ATK_SLASH

    -- 四层数据表
    self.base    = {}   -- 基础值（等级/职业/面板数据）
    self.derived = {}   -- 六围派生贡献
    self.flatMod = {}   -- 平值修改器（装备/Buff 等）总和
    self.pctMod  = {}   -- 百分比修改器（装备/Buff 等）总和，单位百分点
    self.final   = {}   -- 最终计算值

    -- 具名修改器存储 { [id] = { {key, flat, pct}, ... } }
    self.modifiers = {}

    -- 初始化所有属性为默认值
    for key, meta in pairs(AD.META) do
        self.base[key]    = AD.getDefault(key)
        self.derived[key] = 0
        self.flatMod[key] = 0
        self.pctMod[key]  = 0
        self.final[key]   = self.base[key]
    end

    -- 用 cfg 覆盖 base 值
    for key, val in pairs(cfg) do
        if AD.META[key] then
            self.base[key] = val
        end
    end

    -- 首次全量计算
    self:recalc()

    return self
end

-- ======================== 读取 ========================

--- 获取最终属性值
---@param key string 属性 key
---@return number
function UnitAttributes:get(key)
    local value = tonumber(self.final[key]) or 0
    if self.artifactBlockCap and (key == AD.PHYS_BLOCK_RATE or key == AD.MAG_BLOCK_RATE) then
        local uncapped = self._uncapped and self._uncapped[key] or value
        if uncapped > 100 then
            value = math.min(uncapped, self.artifactBlockCap)
        end
    end
    if self.artifactChaosDefenseDisabled then
        if key == AD.ARMOR
            or key == AD.RESISTANCE
            or key == AD.PHYS_BLOCK_RATE
            or key == AD.MAG_BLOCK_RATE
            or key == AD.PHYS_BLOCK_RATIO
            or key == AD.MAG_BLOCK_RATIO then
            value = 0
        end
    end
    return tonumber(value) or 0
end

--- 获取截断上限前的实际属性值（用于属性详情展示）
---@param key string 属性 key
---@return number
function UnitAttributes:getUncapped(key)
    if self._uncapped and self._uncapped[key] ~= nil then
        return self._uncapped[key]
    end
    return self:get(key)
end

--- 获取基础值（不含派生和修改器）
---@param key string
---@return number
function UnitAttributes:getBase(key)
    return self.base[key] or 0
end

--- 设置基础值并重算
---@param key string
---@param val number
function UnitAttributes:setBase(key, val)
    self.base[key] = val
    self:recalc()
end

--- 批量设置基础值后重算
---@param tbl table { [key] = val, ... }
function UnitAttributes:setBases(tbl)
    for k, v in pairs(tbl) do
        if AD.META[k] then
            self.base[k] = v
        end
    end
    self:recalc()
end

-- ======================== 修改器 ========================

--- 添加具名修改器（装备/Buff/被动技能等）
--- 可包含多条属性修改，同 id 会覆盖
---@param id string     修改器唯一 ID（如 "equip_sword_1"、"buff_rage"）
---@param entries table {{ key=AD.PHYS_ATK, flat=50 }, { key=AD.CRIT_RATE, pct=5 }, ...}
function UnitAttributes:addModifier(id, entries)
    local safeEntries = {}
    for _, e in ipairs(entries or {}) do
        if e and e.key then
            safeEntries[#safeEntries + 1] = e
        else
            print("[UnitAttributes] invalid modifier entry skipped id=" .. tostring(id)
                .. " key=" .. tostring(e and e.key)
                .. " flat=" .. tostring(e and e.flat)
                .. " pct=" .. tostring(e and e.pct))
        end
    end
    if #safeEntries == 0 then return end
    self.modifiers[id] = safeEntries
    self:_rebuildMods()
    self:recalc()
end

--- 移除具名修改器
---@param id string
function UnitAttributes:removeModifier(id)
    if self.modifiers[id] then
        self.modifiers[id] = nil
        self:_rebuildMods()
        self:recalc()
    end
end

--- 清除全部修改器
function UnitAttributes:clearModifiers()
    self.modifiers = {}
    self:_rebuildMods()
    self:recalc()
end

--- 深拷贝当前 UnitAttributes 实例，生成一份独立副本
--- 用于战斗快照隔离：克隆后修改不会影响原始实例
---@return table UnitAttributes 独立副本
function UnitAttributes:clone()
    local copy = setmetatable({}, UnitAttributes)

    -- 标量字段
    copy.armorType = self.armorType
    copy.atkType   = self.atkType
    copy.atkCoeff  = self.atkCoeff
    copy.dmgSpread = self.dmgSpread
    copy._healFrac = self._healFrac
    copy.energyShield = self.energyShield
    copy.tempEnergyShield = self.tempEnergyShield
    copy.esRegenCooldown = self.esRegenCooldown
    copy.artifactIgnoreArmor = self.artifactIgnoreArmor
    copy.artifactCritRateMult = self.artifactCritRateMult
    copy.artifactCritDmgMult = self.artifactCritDmgMult
    copy.artifactExtraDamageMult = self.artifactExtraDamageMult
    copy.artifactBlockCap = self.artifactBlockCap
    copy.artifactChaosDamageMult = self.artifactChaosDamageMult
    copy.artifactChaosDefenseDisabled = self.artifactChaosDefenseDisabled
    copy.artifactPowerBonus = self.artifactPowerBonus
    copy.artifactNoHeal = self.artifactNoHeal

    -- 浅拷贝数值层表（key 为字符串常量，value 为数字）
    copy.base    = {}; for k, v in pairs(self.base)    do copy.base[k]    = v end
    copy.derived = {}; for k, v in pairs(self.derived) do copy.derived[k] = v end
    copy.flatMod = {}; for k, v in pairs(self.flatMod) do copy.flatMod[k] = v end
    copy.pctMod  = {}; for k, v in pairs(self.pctMod)  do copy.pctMod[k]  = v end
    copy.final   = {}; for k, v in pairs(self.final)   do copy.final[k]   = v end
    copy._uncapped = {}
    if self._uncapped then
        for k, v in pairs(self._uncapped) do copy._uncapped[k] = v end
    end

    -- 二级深拷贝 modifiers: { [id] = { {key,flat,pct}, ... } }
    copy.modifiers = {}
    for id, entries in pairs(self.modifiers) do
        local ce = {}
        for i, e in ipairs(entries) do
            ce[i] = { key = e.key, flat = e.flat, pct = e.pct }
        end
        copy.modifiers[id] = ce
    end

    return copy
end

--- 内部：从所有具名修改器重建 flatMod / pctMod 总和
function UnitAttributes:_rebuildMods()
    -- 清零
    for key in pairs(AD.META) do
        self.flatMod[key] = 0
        self.pctMod[key]  = 0
    end
    -- 累加
    for _, entries in pairs(self.modifiers) do
        for _, e in ipairs(entries) do
            if e.flat then
                self.flatMod[e.key] = (self.flatMod[e.key] or 0) + e.flat
            end
            if e.pct then
                self.pctMod[e.key] = (self.pctMod[e.key] or 0) + e.pct
            end
        end
    end
end

-- ======================== 核心计算 ========================

--- 全量重算：六围派生 → final
function UnitAttributes:recalc()
    -- 0) 保存当前战斗 HP / 护盾上限（recalc 不应覆盖运行时 HP；仅新增护盾上限时填满护盾）
    local savedHp = self.final[AD.HP]
    local savedESMax = self.final[AD.ENERGY_SHIELD] or 0

    -- 1) 清空派生
    for key in pairs(AD.META) do
        self.derived[key] = 0
    end

    -- 2) 计算六围派生贡献
    local finalBaseStatBonus = {}
    local function calcPreDerivedValue(key)
        local meta = AD.META[key]
        if not meta then return 0 end
        local raw = (self.base[key] or 0) + (self.flatMod[key] or 0)
        local pctBonus = (self.pctMod[key] or 0) / 100
        local val = raw * (1 + pctBonus)
        if meta.dataType == AD.TYPE_INT then
            val = math.floor(val + 0.5)
        end
        local cap = meta.cap
        if cap and val > cap then
            val = cap
        end
        return val
    end
    for _, baseStat in ipairs(AD.BASE_STATS) do
        local bonusKey = AD.FINAL_BASE_STAT_BONUS and AD.FINAL_BASE_STAT_BONUS[baseStat]
        finalBaseStatBonus[baseStat] = bonusKey and calcPreDerivedValue(bonusKey) or 0
    end

    for _, baseStat in ipairs(AD.BASE_STATS) do
        local baseVal = (self.base[baseStat] or 0) + (self.flatMod[baseStat] or 0)
        -- 六围本身也受百分比修改，魔化最终六围作为最终乘区再生效
        local pctBonus = (self.pctMod[baseStat] or 0) / 100
        local finalBonus = (finalBaseStatBonus[baseStat] or 0) / 100
        local effectiveStat = baseVal * (1 + pctBonus) * (1 + finalBonus)

        local derivList = AD.DERIVATIVES[baseStat]
        if derivList then
            for _, d in ipairs(derivList) do
                self.derived[d.attr] = (self.derived[d.attr] or 0) + effectiveStat * d.perPoint
            end
        end
    end

    -- 3) 计算 final = (base + derived + flatMod) * (1 + pctMod/100)
    --    六围本身: final = base + flatMod（已在上面用过，此处也写入 final）
    self._uncapped = {}
    local function setFinalValue(key, val)
        local meta = AD.META[key]
        if not meta then return end
        if meta.dataType == AD.TYPE_INT then
            val = math.floor(val + 0.5)
        end
        self._uncapped[key] = val
        local cap = meta.cap
        if cap and val > cap then
            val = cap
        end
        self.final[key] = val
    end
    local function applyFinalBonus(targetKey, bonusKey)
        if not targetKey or not bonusKey then return end
        local bonus = self.final[bonusKey] or 0
        if bonus == 0 then return end
        setFinalValue(targetKey, (self.final[targetKey] or 0) * (1 + bonus / 100))
    end
    for key, meta in pairs(AD.META) do
        local raw = (self.base[key] or 0) + (self.derived[key] or 0) + (self.flatMod[key] or 0)
        local pctBonus = (self.pctMod[key] or 0) / 100
        setFinalValue(key, raw * (1 + pctBonus))
    end

    -- 4) 攻击加成：物理/魔法攻击加成（%）作用于对应攻击力
    local physAtkBonus = self.final[AD.PHYS_ATK_BONUS] or 0
    if physAtkBonus ~= 0 then
        self.final[AD.PHYS_ATK] = self.final[AD.PHYS_ATK] * (1 + physAtkBonus / 100)
        self._uncapped[AD.PHYS_ATK] = self.final[AD.PHYS_ATK]
    end
    local magAtkBonus = self.final[AD.MAG_ATK_BONUS] or 0
    if magAtkBonus ~= 0 then
        self.final[AD.MAG_ATK] = self.final[AD.MAG_ATK] * (1 + magAtkBonus / 100)
        self._uncapped[AD.MAG_ATK] = self.final[AD.MAG_ATK]
    end

    -- 4.5) 生命加成：百分比作用于生命值上限
    local hpBonus = self.final[AD.HP_BONUS] or 0
    if hpBonus ~= 0 then
        self.final[AD.MAX_HP] = math.floor(self.final[AD.MAX_HP] * (1 + hpBonus / 100) + 0.5)
        self._uncapped[AD.MAX_HP] = self.final[AD.MAX_HP]
    end

    -- 4.6) 闪避加成：百分比作用于闪避值
    local dodgeBonus = self.final[AD.DODGE_BONUS] or 0
    if dodgeBonus ~= 0 then
        self.final[AD.DODGE] = self.final[AD.DODGE] * (1 + dodgeBonus / 100)
        self._uncapped[AD.DODGE] = self.final[AD.DODGE]
    end

    -- 4.7) 护甲加成：百分比作用于护甲
    local armorBonus = self.final[AD.ARMOR_BONUS] or 0
    if armorBonus ~= 0 then
        self.final[AD.ARMOR] = self.final[AD.ARMOR] * (1 + armorBonus / 100)
        self._uncapped[AD.ARMOR] = self.final[AD.ARMOR]
    end

    -- 4.8) 能量护盾加成：百分比作用于能量护盾
    local esBonus = self.final[AD.ES_BONUS] or 0
    if esBonus ~= 0 then
        self.final[AD.ENERGY_SHIELD] = (self.final[AD.ENERGY_SHIELD] or 0) * (1 + esBonus / 100)
        self._uncapped[AD.ENERGY_SHIELD] = self.final[AD.ENERGY_SHIELD]
    end

    -- 4.9) 魔化最终属性：最后一层乘区，作用于已完成常规加成后的目标属性
    if AD.FINAL_ATTR_BONUS then
        for targetKey, bonusKey in pairs(AD.FINAL_ATTR_BONUS) do
            applyFinalBonus(targetKey, bonusKey)
        end
    end
    for baseStat, bonus in pairs(finalBaseStatBonus) do
        if bonus ~= 0 then
            setFinalValue(baseStat, (self.final[baseStat] or 0) * (1 + bonus / 100))
        end
    end

    -- 5) 特殊派生：护甲 → 伤害抗性（护甲不低于 0）
    local armor = math.max(0, self.final[AD.ARMOR] or 0)
    self.final[AD.RESISTANCE] = (0.01 * armor) / (0.01 * armor + 1) * 100
    self._uncapped[AD.RESISTANCE] = self.final[AD.RESISTANCE]

    -- 6) 恢复战斗 HP（不让公式覆盖运行时血量）
    --    savedHp 为 nil 仅在首次 create → recalc 时，此时 final[HP] 保持公式值（由 fillHp 初始化）
    if savedHp and savedHp > 0 then
        -- 保留当前战斗 HP，但不超过新的 maxHP
        self.final[AD.HP] = math.min(savedHp, self.final[AD.MAX_HP])
    elseif savedHp and savedHp <= 0 then
        -- 已死亡的单位保持死亡状态
        self.final[AD.HP] = 0
    end
    -- savedHp == nil → 首次构造，保留公式算出的值（后续由 fillHp 设为满血）

    -- 7) 初始化能量护盾
    self:initEnergyShield(savedESMax)
end

-- ======================== 运行时操作 ========================

--- 满血初始化（通常创建单位后调用）
function UnitAttributes:fillHp()
    self.final[AD.HP] = self.final[AD.MAX_HP]
    self._healFrac = 0
end

--- 扣血（不低于 0）
---@param amount number 伤害量
---@return number 实际扣除量
function UnitAttributes:takeDamage(amount)
    amount = math.max(0, math.floor(amount))
    if amount <= 0 then return 0 end
    -- 受到任何伤害都重置能量护盾恢复冷却（未受伤2秒后才开始恢复）
    local maxES = self.final[AD.ENERGY_SHIELD] or 0
    if maxES > 0 then
        self.esRegenCooldown = self.final[AD.ES_REGEN_INTERVAL] or 1.2
    end
    -- 能量护盾伤害减免：任一护盾存在时生效
    local es = self.energyShield or 0
    local tempEs = self.tempEnergyShield or 0
    local totalShield = es + tempEs
    if totalShield > 0 then
        local esReduce = self.final[AD.ES_DMG_REDUCE] or 0
        if esReduce > 0 then
            amount = math.floor(amount * (1 - math.min(esReduce / 100, 0.80)))
        end
        -- 临时护盾在外层，优先吸收
        tempEs = self.tempEnergyShield or 0
        if tempEs > 0 then
            local tempAbsorbed = math.min(tempEs, amount)
            self.tempEnergyShield = tempEs - tempAbsorbed
            amount = amount - tempAbsorbed
        end
        -- 常规能量护盾
        es = self.energyShield or 0
        if es > 0 and amount > 0 then
            local absorbed = math.min(es, amount)
            self.energyShield = es - absorbed
            amount = amount - absorbed
        end
    end
    local hp = self.final[AD.HP]
    local actual = math.min(hp, amount)
    self.final[AD.HP] = hp - actual
    return actual
end

--- 能量护盾恢复 tick（每帧调用）
--- 冷却结束后以 maxES/秒 的速度逐渐恢复
---@param dt number 帧间隔（秒）
function UnitAttributes:tickEnergyShield(dt)
    local maxES = self.final[AD.ENERGY_SHIELD] or 0
    if maxES <= 0 then return end
    local es = self.energyShield or 0
    if es >= maxES then return end  -- 已满
    -- 恢复冷却倒计时
    local cd = self.esRegenCooldown or 0
    if cd > 0 then
        self.esRegenCooldown = cd - dt
        return
    end
    -- 逐渐恢复（基础速率 = maxES/秒，受 esRegenSpeed% 加成）
    local regenSpeedBonus = self.final[AD.ES_REGEN_SPEED] or 0
    local regenRate = maxES * (1 + regenSpeedBonus / 100)
    self.energyShield = math.min(maxES, es + regenRate * dt)
end

--- 初始化能量护盾（创建单位 / 重新计算属性后调用）
---@param previousMaxES number|nil 重算前护盾上限；从无上限变为有上限时填满当前护盾
function UnitAttributes:initEnergyShield(previousMaxES)
    local maxES = self.final[AD.ENERGY_SHIELD] or 0
    if maxES > 0 then
        previousMaxES = previousMaxES or 0
        if self.energyShield == nil or previousMaxES <= 0 then
            self.energyShield = maxES
        else
            self.energyShield = math.min(maxES, self.energyShield)
        end
        if self.tempEnergyShield == nil then
            self.tempEnergyShield = 0
        end
        if self.esRegenCooldown == nil then
            self.esRegenCooldown = 0
        end
    else
        self.energyShield = 0
        self.tempEnergyShield = 0
    end
end

--- 回血（不超过 maxHp）
--- 小数部分内部累计，仅整数部分实际加到 HP 上，避免显示小数
---@param amount number 治疗量（可含小数）
---@return number 实际恢复量（整数）
function UnitAttributes:heal(amount)
    if self.artifactNoHeal then return 0 end
    if amount <= 0 then return 0 end
    -- 死亡状态保护：HP<=0 时禁止通过 heal 恢复（防止非复活路径意外"复活"）
    local curHp = self.final[AD.HP]
    if curHp <= 0 then return 0 end
    -- 累计小数余量
    self._healFrac = (self._healFrac or 0) + amount
    local intPart = math.floor(self._healFrac)
    self._healFrac = self._healFrac - intPart
    if intPart <= 0 then return 0 end
    local hp = self.final[AD.HP]
    local maxHp = self.final[AD.MAX_HP]
    local actual = math.min(maxHp - hp, intPart)
    self.final[AD.HP] = hp + actual
    return actual
end

--- 是否存活
---@return boolean
function UnitAttributes:isAlive()
    return self.final[AD.HP] > 0
end

--- 计算实际攻击间隔（秒）
---@return number
function UnitAttributes:getActualInterval()
    local base = self.final[AD.ATK_INTERVAL]
    local speed = self.final[AD.ATK_SPEED]
    return base / (1 + speed / 100)
end

-- ======================== 序列化 ========================

--- 导出为简单表（供 UI 显示）
---@return table
function UnitAttributes:toDisplayTable()
    local t = {}
    for key, meta in pairs(AD.META) do
        t[key] = {
            name  = meta.name,
            value = self.final[key],
            type  = meta.dataType,
        }
    end
    return t
end

--- 导出为战斗场景需要的简化格式
---@param name string 单位名称
---@param level number 等级
---@return table
function UnitAttributes:toBattleUnit(name, level)
    return {
        name        = name,
        level       = level,
        hp          = self.final[AD.HP],
        maxHp       = self.final[AD.MAX_HP],
        atkProgress = 0.0,
        attrs       = self,   -- 引用完整属性，战斗系统可直接访问
    }
end

return UnitAttributes
