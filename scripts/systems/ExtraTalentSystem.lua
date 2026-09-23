-- ============================================================================
-- ExtraTalentSystem - 角色超模追加技（觉醒解锁）
-- 觉醒1=粗暴永久层  觉醒2=机制（旧4）  觉醒3=形态进化（旧7）
-- 未点对应节点则不生效（不再默认自带）
-- ============================================================================

local AD = require("systems.AttributeDef")
local SEM = require("systems.StatusEffectManager")
local BattleLayout = require("core.BattleLayout")
local Protocol = require("shared.Protocol")

local ETS = {}

local ATK_ORDER = {
    AD.ATK_SLASH, AD.ATK_CRUSH, AD.ATK_PIERCE,
    AD.ATK_FIRE, AD.ATK_ICE, AD.ATK_LIGHTNING,
    AD.ATK_SHADOW, AD.ATK_HOLY,
}

local NAMES = {
    [1] = "衔骨图鉴", [2] = "火葬场", [3] = "预约通知", [4] = "武德银行",
    [5] = "焊甲", [6] = "安可回路", [7] = "必杀库存", [8] = "仇册",
    [9] = "温泉本金", [10] = "门板", [11] = "斩影", [12] = "冰雕收藏",
    [13] = "分裂弹", [14] = "抄作业簿", [15] = "预存复活", [16] = "剑冢",
    [17] = "水压图鉴", [18] = "草图鉴", [19] = "功德本金",
    [20] = "星门殖民", [21] = "氮气赛道", [22] = "课时", [23] = "护盾本金",
    [24] = "缓存条", [25] = "丢包补偿",
}

---@class ExtraTalentData
---@field stacks number
---@field biteTypes table<string, boolean>
---@field splitKills number
---@field tickets table<string, boolean>
---@field iceStatues number
---@field issuedCards number
---@field burnKills number
---@field preciseStored number
---@field blockBank number
---@field conquerCarry number
---@field shockKills number
---@field beamCharges number
---@field markTypes table<string, boolean>
---@field overflowCount number
---@field shareCount number
---@field slashShadows number
---@field nitroKills number
---@field gatlingKills number
---@field swordStacks number
---@field gateStacks number
---@field shieldStacks number

local battle = {
    iceStatues = {}, ---@type table[]
    orbitAngle = 0,
    persistAcc = 0,
    dirty = {}, ---@type table<number, ExtraTalentData>
    pendingPrecise = {}, ---@type table<number, number>
    pendingConquer = {}, ---@type table<number, number>
    pendingBeams = {}, ---@type table<number, number>
    pendingShadows = {}, ---@type table<number, number>
    pendingGatling = {}, ---@type table<number, number>
    pendingNitroDash = {}, ---@type table<number, number>
}

local NUM_KEYS = {
    "stacks", "splitKills", "iceStatues", "issuedCards", "burnKills",
    "preciseStored", "blockBank", "conquerCarry", "shockKills", "beamCharges",
    "overflowCount", "shareCount", "slashShadows", "nitroKills", "gatlingKills",
    "swordStacks", "gateStacks", "shieldStacks",
}

local function toHeroId(v)
    return tonumber(v) or 0
end

local function copyBoolMap(src)
    local t = {}
    if type(src) == "table" then
        for k, v in pairs(src) do
            if v then t[tostring(k)] = true end
        end
    end
    return t
end

local function mapCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

--- 规范化存档字段
---@param data table|nil
---@return ExtraTalentData
function ETS.normalize(data)
    ---@type ExtraTalentData
    local d = {}
    local src = type(data) == "table" and data or {}
    for _, k in ipairs(NUM_KEYS) do
        local n = math.max(0, math.floor(tonumber(src[k]) or 0))
        if k == "iceStatues" then n = math.min(3, n) end
        d[k] = n
    end
    d.biteTypes = copyBoolMap(src.biteTypes)
    d.tickets = copyBoolMap(src.tickets)
    d.markTypes = copyBoolMap(src.markTypes)
    return d
end

---@param heroId number
---@return ExtraTalentData
function ETS.getOwned(heroId)
    heroId = toHeroId(heroId)
    local ok, CP = pcall(require, "ui.CharacterPanel")
    if ok and CP and CP.getOwnedHero then
        local owned = CP.getOwnedHero(heroId)
        if owned then
            owned.extraTalent = ETS.normalize(owned.extraTalent)
            return owned.extraTalent
        end
    end
    return ETS.normalize(nil)
end

local function ownedAwakening(heroId)
    local ok, CP = pcall(require, "ui.CharacterPanel")
    if ok and CP and CP.getOwnedHero then
        local owned = CP.getOwnedHero(heroId)
        return owned and owned.awakening or nil
    end
    return nil
end

local function awkHas(awk, node)
    if type(awk) ~= "table" then return false end
    local AC = require("config.AwakeningConfig")
    local migrated = AC.migrateAwakening(awk)
    local mapped = AC.mapLegacyNode(node)
    if mapped <= 0 then mapped = node end
    return migrated[mapped] == true or awk[node] == true or awk[tostring(node)] == true
end

--- 单位/存档是否已点指定觉醒节点
---@param unit table|nil
---@param node number
---@param awakening table|nil
---@return boolean
function ETS.hasNode(unit, node, awakening)
    if unit and unit._etsDisabled then return false end
    if awakening and awkHas(awakening, node) then return true end
    if unit then
        if awkHas(unit.awakeningNodes, node) then return true end
        local hid = toHeroId(unit.heroId)
        if hid > 0 then
            return awkHas(ownedAwakening(hid), node)
        end
    end
    return false
end

local function biteCount(extra)
    return mapCount(extra.biteTypes)
end

---@param heroId number
---@return string
function ETS.getName(heroId)
    return NAMES[toHeroId(heroId)] or ""
end

local function lockedTag(awk, node, text)
    if awkHas(awk, node) then return text end
    return "【未解锁】" .. text
end

---@param heroId number
---@param extra ExtraTalentData|nil
---@return string
function ETS.getStatusLine(heroId, extra)
    heroId = toHeroId(heroId)
    extra = ETS.normalize(extra)
    local awk = ownedAwakening(heroId)
    local name = NAMES[heroId]
    if not name then return "" end
    local n4 = awkHas(awk, 4)
    local n7 = awkHas(awk, 7)
    local lines = {
        [1] = function()
            return string.format("%s · %s · %s",
                lockedTag(awk, 1, string.format("生命上限 +%d", extra.stacks)),
                lockedTag(awk, 4, string.format("图鉴 %d/8", biteCount(extra))),
                n7 and "全系撕咬" or "【未解锁】全系撕咬")
        end,
        [2] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("魔攻 +%.1f", extra.burnKills * 0.2)),
                lockedTag(awk, 4, string.format("火种 %d/4", math.min(4, math.floor(extra.burnKills / 5)))))
        end,
        [3] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("物攻 +%.1f", extra.stacks * 0.2)),
                lockedTag(awk, 4, string.format("预存精准 %d/5", extra.preciseStored)))
        end,
        [4] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("生命上限 +%.1f", extra.stacks * 0.5)),
                lockedTag(awk, 4, string.format("武德库存 %d", extra.blockBank)))
        end,
        [5] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("护甲 +%.1f", extra.stacks * 0.2)),
                lockedTag(awk, 4, string.format("开场甲片 %d", extra.conquerCarry)))
        end,
        [6] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("魔攻 +%.1f", extra.shockKills * 0.2)),
                n4 and "电跳邻" or "【未解锁】安可回路")
        end,
        [7] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("连击率 +%.1f%%", extra.stacks * 0.1)),
                lockedTag(awk, 4, string.format("预存光线 %d/3", extra.beamCharges)))
        end,
        [8] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("全伤害 +%.2f%%", extra.stacks * 0.15)),
                lockedTag(awk, 4, string.format("仇种 %d/8", mapCount(extra.markTypes))))
        end,
        [9] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("精神 +%.2f", extra.overflowCount * 0.05)),
                n4 and "泉眼" or "【未解锁】泉眼")
        end,
        [10] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("生命上限 +%d", extra.shareCount * 3)),
                lockedTag(awk, 4, string.format("驻留门 %d/3", math.min(3, math.floor(extra.shareCount / 8)))))
        end,
        [11] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("物攻 +%.1f", extra.stacks * 0.3)),
                lockedTag(awk, 4, string.format("斩影 %d/4", extra.slashShadows)))
        end,
        [12] = function()
            return string.format("%s · %s · %s",
                lockedTag(awk, 1, string.format("魔攻 +%.1f", extra.stacks * 0.2)),
                lockedTag(awk, 4, string.format("冰雕 %d/3", extra.iceStatues)),
                n7 and "冰面" or "【未解锁】冰面")
        end,
        [13] = function()
            local extraBounces = n4 and math.min(5, math.floor(extra.splitKills / 8)) or 0
            return string.format("%s · %s%s",
                lockedTag(awk, 1, string.format("物攻 +%.1f", extra.stacks * 0.25)),
                lockedTag(awk, 4, string.format("分裂击杀 %d · 额外弹射 +%d", extra.splitKills, extraBounces)),
                n7 and " · 环绕进化" or "")
        end,
        [14] = function()
            return lockedTag(awk, 1, string.format("双攻 +%.1f%%", extra.stacks * 0.1))
        end,
        [15] = function()
            local rate = math.min(80, extra.stacks * 0.5)
            return string.format("%s · %s · %s",
                lockedTag(awk, 1, string.format("生命上限 +%d · 复活率 +%.1f%%", extra.stacks * 2, rate)),
                lockedTag(awk, 4, string.format("预存票 %d", mapCount(extra.tickets))),
                n7 and "圣核" or "【未解锁】圣核")
        end,
        [16] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("飞剑系数 +%.1f%%", extra.swordStacks * 0.2)),
                n7 and "环绕剑" or "【未解锁】环绕剑")
        end,
        [20] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("星门伤害 +%.1f%%", extra.gateStacks * 0.3)),
                n4 and "人走门在" or "【未解锁】殖民")
        end,
        [21] = function()
            return string.format("%s · %s",
                lockedTag(awk, 1, string.format("氮气率 +%.2f%%", extra.nitroKills * 0.05)),
                n4 and "赛道" or "【未解锁】赛道")
        end,
        [22] = function()
            local cut = math.min(12, extra.gatlingKills * 0.05)
            return lockedTag(awk, 1, string.format("课时 -%.2f（连打间隔）", cut))
        end,
        [23] = function()
            return lockedTag(awk, 1, string.format("护盾上限 +%d", extra.shieldStacks))
        end,
    }
    local fn = lines[heroId]
    if fn then
        return tostring(fn())
    end
    return ""
end

---@param heroId number
---@param extra ExtraTalentData|nil
---@return string
function ETS.getDesc(heroId, extra)
    heroId = toHeroId(heroId)
    extra = ETS.normalize(extra)
    local name = NAMES[heroId]
    if not name then return "" end
    local awk = ownedAwakening(heroId)
    local unlocked = awkHas(awk, 1) or awkHas(awk, 4) or awkHas(awk, 7)
    if not unlocked then
        return name .. "（觉醒后解锁）"
    end
    return name .. "  Lv." .. tostring(extra.stacks) .. "\n" .. ETS.getStatusLine(heroId, extra)
end

local function bruteEntries(heroId, data)
    local entries = {}
    if heroId == 1 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.MAX_HP, flat = data.stacks }
    end
    if heroId == 2 and data.burnKills > 0 then
        entries[#entries + 1] = { key = AD.MAG_ATK, flat = data.burnKills * 0.2 }
    end
    if heroId == 3 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.PHYS_ATK, flat = data.stacks * 0.2 }
    end
    if heroId == 4 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.MAX_HP, flat = data.stacks * 0.5 }
    end
    if heroId == 5 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.ARMOR, flat = data.stacks * 0.2 }
    end
    if heroId == 6 and data.shockKills > 0 then
        entries[#entries + 1] = { key = AD.MAG_ATK, flat = data.shockKills * 0.2 }
    end
    if heroId == 7 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.COMBO_RATE, flat = data.stacks * 0.1 }
    end
    if heroId == 8 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.DMG_BONUS, flat = data.stacks * 0.15 }
    end
    if heroId == 9 and data.overflowCount > 0 then
        entries[#entries + 1] = { key = AD.SPI, flat = data.overflowCount * 0.05 }
    end
    if heroId == 10 and data.shareCount > 0 then
        entries[#entries + 1] = { key = AD.MAX_HP, flat = data.shareCount * 3 }
    end
    if heroId == 11 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.PHYS_ATK, flat = data.stacks * 0.3 }
    end
    if heroId == 12 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.MAG_ATK, flat = data.stacks * 0.2 }
    end
    if heroId == 13 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.PHYS_ATK, flat = data.stacks * 0.25 }
    end
    if heroId == 14 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.PHYS_ATK_BONUS, flat = data.stacks * 0.1 }
        entries[#entries + 1] = { key = AD.MAG_ATK_BONUS, flat = data.stacks * 0.1 }
    end
    if heroId == 15 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.MAX_HP, flat = data.stacks * 2 }
    end
    if heroId == 23 and data.shieldStacks > 0 then
        entries[#entries + 1] = { key = AD.ENERGY_SHIELD, flat = data.shieldStacks }
    end
    if heroId == 18 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.CRIT_RATE, flat = data.stacks * 0.1 }
    end
    if heroId == 19 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.SPI, flat = data.stacks * 0.05 }
    end
    if heroId == 24 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.MAX_HP, flat = data.stacks }
    end
    if heroId == 25 and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.PHYS_ATK, flat = data.stacks * 0.3 }
    end
    return entries
end

---@param heroId number
---@param attrs table
---@param extra ExtraTalentData|nil|boolean
---@param awakening table|nil
function ETS.applyToAttrs(heroId, attrs, extra, awakening)
    if extra == false then return end
    if not attrs or not attrs.addModifier then return end
    heroId = toHeroId(heroId)
    if not awkHas(awakening, 1) then
        if not awakening then
            awakening = ownedAwakening(heroId)
        end
    end
    if not awkHas(awakening, 1) then
        attrs:removeModifier("extra_talent_" .. tostring(heroId))
        return
    end
    ---@type ExtraTalentData
    local data
    if extra == nil then
        data = ETS.getOwned(heroId)
    else
        ---@type table|nil
        local raw = nil
        if type(extra) == "table" then raw = extra end
        data = ETS.normalize(raw)
    end
    local entries = bruteEntries(heroId, data)
    attrs:removeModifier("extra_talent_" .. tostring(heroId))
    if #entries > 0 then
        attrs:addModifier("extra_talent_" .. tostring(heroId), entries)
    end
end

---@param extra ExtraTalentData
---@param unit table|nil
---@return number
function ETS.getSnowFreezeBonus(extra, unit)
    if not ETS.hasNode(unit, 1) then return 0 end
    extra = ETS.normalize(extra)
    return extra.stacks * 0.0005
end

---@param extra ExtraTalentData
---@param unit table|nil
---@return number
function ETS.getReviveRateBonus(extra, unit)
    if not ETS.hasNode(unit, 1) then return 0 end
    extra = ETS.normalize(extra)
    return extra.stacks * 0.005
end

---@param extra ExtraTalentData
---@param unit table|nil
---@return integer
function ETS.getExtraBounces(extra, unit)
    if not ETS.hasNode(unit, 4) then return 0 end
    extra = ETS.normalize(extra)
    return math.min(5, math.floor(extra.splitKills / 8))
end

---@param extra ExtraTalentData
---@param unit table|nil
---@return boolean
function ETS.hasOrbit(extra, unit)
    if not ETS.hasNode(unit, 7) then return false end
    extra = ETS.normalize(extra)
    return extra.splitKills >= 40
end

---@param unit table|nil
---@return number
function ETS.getSwordCoeffBonus(unit)
    if not ETS.hasNode(unit, 1) then return 0 end
    local extra = ETS.getOwned(toHeroId(unit and unit.heroId))
    return extra.swordStacks * 0.002
end

---@param unit table|nil
---@return number
function ETS.getStarGateDmgBonus(unit)
    if not ETS.hasNode(unit, 1) then return 0 end
    local extra = ETS.getOwned(toHeroId(unit and unit.heroId))
    return extra.gateStacks * 0.003
end

---@param unit table|nil
---@return number
function ETS.getNitroProcBonus(unit)
    if not ETS.hasNode(unit, 1) then return 0 end
    local extra = ETS.getOwned(toHeroId(unit and unit.heroId))
    return extra.nitroKills * 0.0005
end

---@param unit table|nil
---@return number
function ETS.getGatlingCut(unit)
    if not ETS.hasNode(unit, 1) then return 0 end
    local extra = ETS.getOwned(toHeroId(unit and unit.heroId))
    return math.min(12, extra.gatlingKills * 0.05)
end

---@param unit table|nil
---@return boolean
function ETS.starGatePersist(unit)
    return ETS.hasNode(unit, 4)
end

---@param unit table|nil
---@return integer
function ETS.extraStarGates(unit)
    if not ETS.hasNode(unit, 4) then return 0 end
    local extra = ETS.getOwned(20)
    return math.min(2, math.floor(extra.gateStacks / 40))
end

local function persistNow(heroId, extra)
    heroId = toHeroId(heroId)
    extra = ETS.normalize(extra)
    local ok, CP = pcall(require, "ui.CharacterPanel")
    if ok and CP and CP.patchExtraTalent then
        CP.patchExtraTalent(heroId, extra)
    end
    local sentOk, GameAction = pcall(require, "network.GameAction")
    if sentOk and GameAction and GameAction.sendAction then
        pcall(function()
            GameAction.sendAction(Protocol.ACTION_TYPES.SYNC_EXTRA_TALENT, {
                heroId = heroId,
                extraTalent = extra,
            })
        end)
    end
    local dispOk, ClientDispatcher = pcall(require, "network.ClientDispatcher")
    if dispOk and ClientDispatcher and ClientDispatcher.get then
        local heroes = ClientDispatcher.get("heroes")
        if heroes and heroes.roster then
            local hd = heroes.roster[heroId] or heroes.roster[tostring(heroId)]
            if hd then
                hd.extraTalent = extra
            end
        end
    end
end

local function markDirty(heroId, extra)
    heroId = toHeroId(heroId)
    battle.dirty[heroId] = extra
end

local function commit(unit, extra)
    local heroId = toHeroId(unit and unit.heroId)
    local ok, CP = pcall(require, "ui.CharacterPanel")
    if ok and CP and CP.patchExtraTalent then
        CP.patchExtraTalent(heroId, extra)
    end
    if ETS.hasNode(unit, 1) and unit and unit.attrs then
        ETS.applyToAttrs(heroId, unit.attrs, extra, unit.awakeningNodes)
        local newMax = unit.attrs.final[AD.MAX_HP]
        if newMax and newMax > (unit.maxHp or 0) then
            local gained = newMax - (unit.maxHp or newMax)
            unit.maxHp = newMax
            if unit.attrs.final[AD.HP] then
                unit.attrs.final[AD.HP] = math.min(unit.maxHp, (unit.attrs.final[AD.HP] or 0) + gained)
                unit.hp = unit.attrs.final[AD.HP]
            end
        end
    end
    markDirty(heroId, extra)
end

local function spawnIceStatue(deadEnemy, enemies, source)
    if #battle.iceStatues >= 3 then
        table.remove(battle.iceStatues, 1)
    end
    local idx = 1
    for i, e in ipairs(enemies or {}) do
        if e == deadEnemy then
            idx = i
            break
        end
    end
    local cx, cy = BattleLayout.cardPos("enemy", idx, math.max(1, #(enemies or {})))
    battle.iceStatues[#battle.iceStatues + 1] = {
        hp = 1, cx = cx, cy = cy, source = source,
    }
end

---@param allies table[]
---@param enemies table[]
function ETS.onBattleStart(allies, enemies)
    battle.orbitAngle = 0
    battle.iceStatues = {}
    for _, u in ipairs(allies or {}) do
        if not u._etsDisabled then
        local hid = toHeroId(u.heroId)
        if hid == 12 and (u.hp or 0) > 0 and ETS.hasNode(u, 4) then
            local extra = ETS.getOwned(12)
            local n = extra.iceStatues
            for i = 1, n do
                local cx, cy = BattleLayout.cardPos("enemy", i, math.max(n, 1))
                battle.iceStatues[#battle.iceStatues + 1] = {
                    hp = 1, cx = cx, cy = cy, source = u,
                }
            end
            print(string.format("[ExtraTalent] 雪皇 开场冰雕 x%d", n))
        elseif hid == 5 and ETS.hasNode(u, 4) then
            local extra = ETS.getOwned(5)
            if extra.conquerCarry > 0 then
                u._etsConquerStart = extra.conquerCarry
            end
        elseif hid == 3 and ETS.hasNode(u, 4) then
            local extra = ETS.getOwned(3)
            if extra.preciseStored > 0 then
                u._etsPreciseStart = extra.preciseStored
            end
        elseif hid == 7 and ETS.hasNode(u, 4) then
            local extra = ETS.getOwned(7)
            if extra.beamCharges > 0 then
                u._etsBeamStart = extra.beamCharges
            end
        elseif hid == 11 and ETS.hasNode(u, 4) then
            local extra = ETS.getOwned(11)
            if extra.slashShadows > 0 then
                u._etsShadowStart = extra.slashShadows
            end
        elseif hid == 22 and ETS.hasNode(u, 4) then
            local extra = ETS.getOwned(22)
            if extra.gatlingKills > 0 then
                u._etsGatlingStart = math.min(10, math.floor(extra.gatlingKills / 8))
            end
        end
        end
    end
end

---@param deadEnemy table
---@param allies table[]
---@param enemies table[]
function ETS.onEnemyDeath(deadEnemy, allies, enemies)
    local killer = deadEnemy and deadEnemy._killedBy
    if not killer or not killer.heroId then return end
    if killer._etsDisabled then return end
    local heroId = toHeroId(killer.heroId)
    if NAMES[heroId] == nil then return end
    local extra = ETS.getOwned(heroId)
    local n1 = ETS.hasNode(killer, 1)
    local n4 = ETS.hasNode(killer, 4)
    local n7 = ETS.hasNode(killer, 7)
    if not n1 and not n4 and not n7 then return end

    local function bump()
        extra.stacks = extra.stacks + 1
    end

    if heroId == 1 then
        if n1 then bump() end
        if n4 then
            local atkType = tonumber(deadEnemy.atkType)
            if atkType and atkType >= 1 and atkType <= 8 then
                extra.biteTypes[tostring(atkType)] = true
            end
        end
    end
    if heroId == 2 then
        if SEM.has(deadEnemy, SEM.BURNING) then
            if n1 then extra.burnKills = extra.burnKills + 1; bump() end
        end
    end
    if heroId == 3 then
        if n1 then bump() end
        if n4 and killer._preciseKill then
            extra.preciseStored = math.min(5, extra.preciseStored + 1)
        end
    end
    if heroId == 4 then
        if n1 then bump() end
    end
    if heroId == 5 then
        if n1 then bump() end
        if n4 and killer._conquerFullKill then
            extra.conquerCarry = math.min(15, extra.conquerCarry + 1)
        end
    end
    if heroId == 6 then
        if SEM.has(deadEnemy, SEM.SHOCKED) then
            if n1 then extra.shockKills = extra.shockKills + 1; bump() end
        end
    end
    if heroId == 7 then
        if n1 then bump() end
        if n4 then extra.beamCharges = math.min(3, extra.beamCharges + 1) end
    end
    if heroId == 8 then
        if SEM.has(deadEnemy, SEM.MARKED) then
            if n1 then bump() end
            if n4 then
                local t = tostring(deadEnemy.atkType or deadEnemy.name or "?")
                extra.markTypes[t] = true
            end
        end
    end
    if heroId == 11 then
        if n1 then bump() end
        if n4 and killer._nightSlashKill then
            extra.slashShadows = math.min(4, extra.slashShadows + 1)
        end
    end
    if heroId == 12 then
        if n1 then bump() end
        if n4 and SEM.has(deadEnemy, SEM.FROZEN) then
            extra.iceStatues = math.min(3, extra.iceStatues + 1)
            spawnIceStatue(deadEnemy, enemies, killer)
        end
    end
    if heroId == 13 then
        if n1 then bump() end
        if n4 and deadEnemy._killedByRicochet then
            extra.splitKills = extra.splitKills + 1
        end
    end
    if heroId == 14 then
        if n1 then bump() end
    end
    if heroId == 16 then
        if n1 then extra.swordStacks = extra.swordStacks + 1; bump() end
    end
    if heroId == 20 then
        if n1 then extra.gateStacks = extra.gateStacks + 1; bump() end
    end
    if heroId == 21 then
        if killer._nitroKill then
            if n1 then extra.nitroKills = extra.nitroKills + 1; bump() end
        end
    end
    if heroId == 22 then
        if n1 then extra.gatlingKills = extra.gatlingKills + 1; bump() end
    end
    if heroId == 18 or heroId == 19 or heroId == 24 then
        if n1 then bump() end
    end
    if heroId == 25 then
        if n1 then bump() end
    end

    commit(killer, extra)
    print(string.format("[ExtraTalent] hero=%d stacks=%d n1=%s n4=%s n7=%s",
        heroId, extra.stacks, tostring(n1), tostring(n4), tostring(n7)))
end

---@param unit table
---@param blockedAmt number
function ETS.onBlock(unit, blockedAmt)
    if unit and unit._etsDisabled then return end
    if toHeroId(unit and unit.heroId) ~= 4 then return end
    if not ETS.hasNode(unit, 1) and not ETS.hasNode(unit, 4) then return end
    local extra = ETS.getOwned(4)
    if ETS.hasNode(unit, 1) then
        extra.stacks = extra.stacks + 1
    end
    if ETS.hasNode(unit, 4) then
        extra.blockBank = extra.blockBank + math.max(0, math.floor(blockedAmt or 0))
    end
    commit(unit, extra)
end

---@param healer table
---@param overflow number
function ETS.onOverflowHeal(healer, overflow)
    if healer and healer._etsDisabled then return end
    local hid = toHeroId(healer and healer.heroId)
    if overflow <= 0 then return end
    if hid == 9 then
        if not ETS.hasNode(healer, 1) then return end
        local extra = ETS.getOwned(9)
        extra.overflowCount = extra.overflowCount + 1
        extra.stacks = extra.stacks + 1
        commit(healer, extra)
    elseif hid == 23 then
        if not ETS.hasNode(healer, 1) then return end
        local extra = ETS.getOwned(23)
        extra.shieldStacks = extra.shieldStacks + 1
        extra.stacks = extra.stacks + 1
        commit(healer, extra)
    end
end

---@param unit table
function ETS.onShareFatal(unit)
    if unit and unit._etsDisabled then return end
    if toHeroId(unit and unit.heroId) ~= 10 then return end
    if not ETS.hasNode(unit, 1) then return end
    local extra = ETS.getOwned(10)
    extra.shareCount = extra.shareCount + 1
    extra.stacks = extra.stacks + 1
    commit(unit, extra)
end

---@param dyingUnit table
---@param allies table[]
---@param syncHpFn function
---@return boolean
function ETS.tryTicketRevive(dyingUnit, allies, syncHpFn)
    if not dyingUnit or not dyingUnit.heroId then return false end
    if dyingUnit._etsDisabled then return false end
    local lover
    for _, a in ipairs(allies or {}) do
        if toHeroId(a.heroId) == 15 and (a.hp or 0) > 0 then
            lover = a
            break
        end
    end
    if not lover or not ETS.hasNode(lover, 4) then return false end
    local extra = ETS.getOwned(15)
    local key = tostring(dyingUnit.heroId)
    if not extra.tickets[key] then return false end
    extra.tickets[key] = nil
    if dyingUnit.attrs and dyingUnit.attrs.fillHp then
        dyingUnit.attrs:fillHp()
        if syncHpFn then syncHpFn(dyingUnit) end
    else
        dyingUnit.hp = dyingUnit.maxHp
    end
    commit(lover, extra)
    print("[ExtraTalent] 预存票复活 " .. tostring(dyingUnit.name))
    return true
end

---@param lover table
---@param revivedUnit table
function ETS.onSuccessfulRevive(lover, revivedUnit)
    if lover and lover._etsDisabled then return end
    if toHeroId(lover and lover.heroId) ~= 15 then return end
    if not ETS.hasNode(lover, 1) and not ETS.hasNode(lover, 4) then return end
    local extra = ETS.getOwned(15)
    if ETS.hasNode(lover, 1) then
        extra.stacks = extra.stacks + 1
        extra.issuedCards = extra.issuedCards + 1
    end
    if ETS.hasNode(lover, 4) and revivedUnit and revivedUnit.heroId then
        extra.tickets[tostring(revivedUnit.heroId)] = true
    end
    commit(lover, extra)
    print(string.format("[ExtraTalent] 预存复活发卡 层=%d 对象=%s", extra.stacks, tostring(revivedUnit and revivedUnit.name)))
end

---@param dyingUnit table
---@param allies table[]
---@param enemies table[]
---@param dealDmgFn function|nil
function ETS.onLoverDeathNuke(dyingUnit, allies, enemies, dealDmgFn)
    if dyingUnit and dyingUnit._etsDisabled then return end
    if toHeroId(dyingUnit and dyingUnit.heroId) ~= 15 then return end
    if not ETS.hasNode(dyingUnit, 7) then return end
    local extra = ETS.getOwned(15)
    local cards = extra.issuedCards
    if cards <= 0 or not dealDmgFn then return end
    local mag = (dyingUnit.attrs and dyingUnit.attrs:get(AD.MAG_ATK)) or 0
    local dmg = math.floor(mag * 0.6 * cards + 0.5)
    if dmg <= 0 then return end
    for _, e in ipairs(enemies or {}) do
        if (e.hp or 0) > 0 then
            dealDmgFn(e, dmg, false, "圣核 ", { 255, 230, 140 }, {
                instantDamage = true,
                statCategory = "magical",
            })
        end
    end
    print(string.format("[ExtraTalent] 复活吧爱人 核爆 cards=%d dmg=%d", cards, dmg))
end

---@param attacker table
---@param target table
---@param result table
---@param isAlly boolean
---@param targetList table[]
---@param dealDmgFn function|nil
function ETS.onAfterAttack(attacker, target, result, isAlly, targetList, dealDmgFn)
    if attacker and attacker._etsDisabled then return end
    if not attacker or not result or result.isMiss then return end
    if attacker._etsBiting then return end
    local heroId = toHeroId(attacker.heroId)
    if not dealDmgFn or (target.hp or 0) <= 0 then return end

    if heroId == 1 and ETS.hasNode(attacker, 4) then
        local extra = ETS.getOwned(1)
        local n = biteCount(extra)
        if n <= 0 then return end
        local base = result.totalDamage or 0
        if base <= 0 then return end
        attacker._etsBiting = true
        local ownType = tonumber(attacker.atkType)
        local full = ETS.hasNode(attacker, 7) and n >= 8
        for _, t in ipairs(ATK_ORDER) do
            if extra.biteTypes[tostring(t)] and t ~= ownType then
                local dmg = math.floor(base * (full and 0.10 or 0.12) + 0.5)
                if dmg > 0 then
                    local cat = AD.ATK_CATEGORY[t] or "physical"
                    dealDmgFn(target, dmg, not isAlly, (AD.ATK_TYPE_NAME[t] or "撕咬") .. " ", { 255, 210, 120 }, {
                        instantDamage = true,
                        statCategory = cat,
                    })
                end
            end
        end
        attacker._etsBiting = nil
    elseif heroId == 13 then
        local extra = ETS.getOwned(13)
        if not ETS.hasOrbit(extra, attacker) then return end
        if attacker._etsOrbit then return end
        local base = result.totalDamage or 0
        if base <= 0 or not targetList then return end
        local hits = 0
        attacker._etsOrbit = true
        for _, u in ipairs(targetList) do
            if hits >= 2 then break end
            if u ~= target and (u.hp or 0) > 0 then
                local dmg = math.floor(base * 0.40 + 0.5)
                if dmg > 0 then
                    dealDmgFn(u, dmg, not isAlly, "环绕 ", { 180, 220, 255 }, {
                        isRicochet = true,
                        instantDamage = true,
                        statCategory = result.category or "physical",
                    })
                    hits = hits + 1
                end
            end
        end
        attacker._etsOrbit = nil
    elseif heroId == 6 and ETS.hasNode(attacker, 4) and targetList then
        local shocked = 0
        for _, u in ipairs(targetList) do
            if SEM.has(u, SEM.SHOCKED) then shocked = shocked + 1 end
        end
        if shocked >= 2 then
            for _, u in ipairs(targetList) do
                if u ~= target and SEM.has(u, SEM.SHOCKED) and (u.hp or 0) > 0 then
                    SEM.apply(u, SEM.SHOCKED, 1.2, attacker, { mult = 0.20 })
                end
            end
        end
    end
end

--- 冰雕挡一次伤害
---@param target table
---@param damage number
---@param enemies table[]
---@return number remainingDamage
function ETS.absorbWithIceStatue(target, damage, enemies)
    if damage <= 0 or #battle.iceStatues <= 0 then return damage end
    if not target or not target.heroId then return damage end
    local statue = battle.iceStatues[1]
    local source = statue and statue.source
    if source and not ETS.hasNode(source, 4) then return damage end
    table.remove(battle.iceStatues, 1)
    local extra = ETS.getOwned(12)
    extra.iceStatues = math.max(0, extra.iceStatues - 1)
    local ok, CP = pcall(require, "ui.CharacterPanel")
    if ok and CP and CP.patchExtraTalent then
        CP.patchExtraTalent(12, extra)
    end
    markDirty(12, extra)
    for _, e in ipairs(enemies or {}) do
        if (e.hp or 0) > 0 then
            SEM.apply(e, SEM.FROZEN, ETS.hasNode(source, 7) and 1.2 or 0.8, source or target, {})
        end
    end
    print("[ExtraTalent] 冰雕碎裂挡伤 " .. tostring(math.floor(damage)))
    return 0
end

---@param dt number
function ETS.update(dt)
    battle.orbitAngle = (battle.orbitAngle or 0) + dt * 2.2
    battle.persistAcc = (battle.persistAcc or 0) + dt
    if battle.persistAcc >= 1.5 then
        battle.persistAcc = 0
        for hid, extra in pairs(battle.dirty) do
            persistNow(hid, extra)
        end
        battle.dirty = {}
    end
end

function ETS.flush()
    for hid, extra in pairs(battle.dirty) do
        persistNow(hid, extra)
    end
    battle.dirty = {}
end

---@return number
function ETS.getOrbitAngle()
    return battle.orbitAngle or 0
end

---@return table[]
function ETS.getIceStatues()
    return battle.iceStatues
end

---@param vg any
function ETS.drawIceStatues(vg)
    for _, st in ipairs(battle.iceStatues) do
        nvgBeginPath(vg)
        nvgCircle(vg, st.cx, st.cy + 40, 28)
        nvgFillColor(vg, nvgRGBA(160, 220, 255, 90))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, st.cx, st.cy - 10)
        nvgLineTo(vg, st.cx + 22, st.cy + 55)
        nvgLineTo(vg, st.cx - 22, st.cy + 55)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(190, 235, 255, 150))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(230, 250, 255, 220))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
end

---@param vg any
---@param unit table
---@param cx number
---@param cy number
function ETS.drawOrbit(vg, unit, cx, cy)
    if toHeroId(unit and unit.heroId) ~= 13 then return end
    if (unit.hp or 0) <= 0 then return end
    if not ETS.hasOrbit(ETS.getOwned(13), unit) then return end
    local ang = ETS.getOrbitAngle()
    for i = 1, 3 do
        local a = ang + (i - 1) * (math.pi * 2 / 3)
        local ox = cx + math.cos(a) * 70
        local oy = cy + math.sin(a) * 38
        nvgBeginPath(vg)
        nvgCircle(vg, ox, oy, 7)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, 230))
        nvgFill(vg)
    end
end

return ETS
