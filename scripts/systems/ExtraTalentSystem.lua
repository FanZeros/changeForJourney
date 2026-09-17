-- ============================================================================
-- ExtraTalentSystem - 角色追加技（粗暴永久层 + 机制进化）
-- 试点：#1 大狗嚼 / #12 雪皇 / #13 弹弹弹 / #15 复活吧爱人
-- ============================================================================

local AD = require("systems.AttributeDef")
local SEM = require("systems.StatusEffectManager")
local BattleLayout = require("core.BattleLayout")
local Protocol = require("shared.Protocol")

local ETS = {}

local HERO_DOG = 1
local HERO_SNOW = 12
local HERO_BOUNCE = 13
local HERO_REVIVE = 15

local ATK_ORDER = {
    AD.ATK_SLASH, AD.ATK_CRUSH, AD.ATK_PIERCE,
    AD.ATK_FIRE, AD.ATK_ICE, AD.ATK_LIGHTNING,
    AD.ATK_SHADOW, AD.ATK_HOLY,
}

local NAMES = {
    [HERO_DOG] = "衔骨图鉴",
    [HERO_SNOW] = "冰雕收藏",
    [HERO_BOUNCE] = "分裂弹",
    [HERO_REVIVE] = "预存复活",
}

---@class ExtraTalentData
---@field stacks number
---@field biteTypes table<string, boolean>
---@field splitKills number
---@field tickets table<string, boolean>
---@field iceStatues number
---@field issuedCards number

local battle = {
    iceStatues = {}, ---@type table[]
    orbitAngle = 0,
    persistAcc = 0,
    dirty = {}, ---@type table<number, ExtraTalentData>
}

local function toHeroId(v)
    return tonumber(v) or 0
end

--- 规范化存档字段
---@param data table|nil
---@return ExtraTalentData
function ETS.normalize(data)
    ---@type ExtraTalentData
    local d = {}
    if type(data) ~= "table" then
        d.stacks = 0
        d.biteTypes = {}
        d.splitKills = 0
        d.tickets = {}
        d.iceStatues = 0
        d.issuedCards = 0
        return d
    end
    d.stacks = math.max(0, math.floor(tonumber(data.stacks) or 0))
    d.splitKills = math.max(0, math.floor(tonumber(data.splitKills) or 0))
    d.iceStatues = math.max(0, math.min(3, math.floor(tonumber(data.iceStatues) or 0)))
    d.issuedCards = math.max(0, math.floor(tonumber(data.issuedCards) or 0))
    d.biteTypes = {}
    if type(data.biteTypes) == "table" then
        for k, v in pairs(data.biteTypes) do
            if v then
                d.biteTypes[tostring(k)] = true
            end
        end
    end
    d.tickets = {}
    if type(data.tickets) == "table" then
        for k, v in pairs(data.tickets) do
            if v then
                d.tickets[tostring(k)] = true
            end
        end
    end
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

---@param extra ExtraTalentData
---@return integer
local function biteCount(extra)
    local n = 0
    for _ in pairs(extra.biteTypes) do
        n = n + 1
    end
    return n
end

---@param heroId number
---@return string
function ETS.getName(heroId)
    return NAMES[toHeroId(heroId)] or ""
end

---@param heroId number
---@param extra ExtraTalentData|nil
---@return string
function ETS.getStatusLine(heroId, extra)
    heroId = toHeroId(heroId)
    extra = ETS.normalize(extra)
    if heroId == HERO_DOG then
        return string.format("生命上限 +%d · 图鉴 %d/8%s",
            extra.stacks, biteCount(extra),
            biteCount(extra) >= 8 and " · 全系撕咬" or "")
    elseif heroId == HERO_SNOW then
        local freezePct = math.min(60, 25 + extra.stacks * 0.05)
        return string.format("魔攻 +%.1f · 冰冻率 %.1f%% · 冰雕 %d/3",
            extra.stacks * 0.2, freezePct, extra.iceStatues)
    elseif heroId == HERO_BOUNCE then
        local extraBounces = math.min(5, math.floor(extra.splitKills / 8))
        local evolved = extra.splitKills >= 40
        return string.format("物攻 +%.1f · 分裂击杀 %d · 额外弹射 +%d%s",
            extra.stacks * 0.25, extra.splitKills, extraBounces,
            evolved and " · 环绕进化" or "")
    elseif heroId == HERO_REVIVE then
        local rate = math.min(80, 25 + extra.stacks * 0.5)
        local tickets = 0
        for _ in pairs(extra.tickets) do tickets = tickets + 1 end
        return string.format("生命上限 +%d · 复活率 %d%% · 预存票 %d",
            extra.stacks * 2, math.floor(rate + 0.5), tickets)
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
    return name .. "  Lv." .. tostring(extra.stacks) .. "\n" .. ETS.getStatusLine(heroId, extra)
end

---@param heroId number
---@param attrs table
---@param extra ExtraTalentData|nil|boolean
function ETS.applyToAttrs(heroId, attrs, extra)
    if extra == false then return end
    if not attrs or not attrs.addModifier then return end
    heroId = toHeroId(heroId)
    ---@type ExtraTalentData
    local data
    if extra == nil then
        data = ETS.getOwned(heroId)
    else
        ---@type table|nil
        local raw = nil
        if type(extra) == "table" then
            raw = extra
        end
        data = ETS.normalize(raw)
    end
    local entries = {}
    if heroId == HERO_DOG and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.MAX_HP, flat = data.stacks }
    elseif heroId == HERO_SNOW and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.MAG_ATK, flat = data.stacks * 0.2 }
    elseif heroId == HERO_BOUNCE and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.PHYS_ATK, flat = data.stacks * 0.25 }
    elseif heroId == HERO_REVIVE and data.stacks > 0 then
        entries[#entries + 1] = { key = AD.MAX_HP, flat = data.stacks * 2 }
    end
    if #entries > 0 then
        attrs:removeModifier("extra_talent_" .. tostring(heroId))
        attrs:addModifier("extra_talent_" .. tostring(heroId), entries)
    end
end

---@param extra ExtraTalentData
---@return number
function ETS.getSnowFreezeBonus(extra)
    extra = ETS.normalize(extra)
    return extra.stacks * 0.0005
end

---@param extra ExtraTalentData
---@return number
function ETS.getReviveRateBonus(extra)
    extra = ETS.normalize(extra)
    return extra.stacks * 0.005
end

---@param extra ExtraTalentData
---@return integer
function ETS.getExtraBounces(extra)
    extra = ETS.normalize(extra)
    return math.min(5, math.floor(extra.splitKills / 8))
end

---@param extra ExtraTalentData
---@return boolean
function ETS.hasOrbit(extra)
    extra = ETS.normalize(extra)
    return extra.splitKills >= 40
end

local function persistNow(heroId, extra)
    heroId = toHeroId(heroId)
    extra = ETS.normalize(extra)
    local ok, CP = pcall(require, "ui.CharacterPanel")
    if ok and CP and CP.patchExtraTalent then
        CP.patchExtraTalent(heroId, extra)
    end
    local sentOk, Client = pcall(require, "network.Client")
    if sentOk and Client and Client.sendAction then
        pcall(function()
            Client.sendAction(Protocol.ACTION_TYPES.SYNC_EXTRA_TALENT, {
                heroId = heroId,
                extraTalent = extra,
            })
        end)
    end
    -- 单机无连服：把 extraTalent 写回 Dispatcher 镜像，避免刷新丢失
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

local function applyLiveHpBonus(unit, amount)
    if not unit or not unit.attrs or amount <= 0 then return end
    unit.attrs:removeModifier("extra_talent_" .. tostring(unit.heroId))
    ETS.applyToAttrs(unit.heroId, unit.attrs, ETS.getOwned(unit.heroId))
    local newMax = unit.attrs.final[AD.MAX_HP] or unit.maxHp
    local gained = math.max(0, newMax - (unit.maxHp or newMax))
    unit.maxHp = newMax
    if unit.attrs.final[AD.HP] then
        unit.attrs.final[AD.HP] = (unit.attrs.final[AD.HP] or 0) + math.max(amount, gained)
        if unit.attrs.final[AD.HP] > unit.maxHp then
            unit.attrs.final[AD.HP] = unit.maxHp
        end
        unit.hp = unit.attrs.final[AD.HP]
    else
        unit.hp = math.min(unit.maxHp, (unit.hp or 0) + amount)
    end
end

---@param allies table[]
---@param enemies table[]
function ETS.onBattleStart(allies, enemies)
    battle.orbitAngle = 0
    battle.iceStatues = {}
    local snow
    for _, u in ipairs(allies or {}) do
        if toHeroId(u.heroId) == HERO_SNOW and (u.hp or 0) > 0 then
            snow = u
            break
        end
    end
    if snow then
        local extra = ETS.getOwned(HERO_SNOW)
        local n = extra.iceStatues
        for i = 1, n do
            local cx, cy = BattleLayout.cardPos("enemy", i, math.max(n, 1))
            battle.iceStatues[#battle.iceStatues + 1] = {
                hp = 1, cx = cx, cy = cy, source = snow,
            }
        end
        print(string.format("[ExtraTalent] 雪皇 开场冰雕 x%d", n))
    end
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

---@param deadEnemy table
---@param allies table[]
---@param enemies table[]
function ETS.onEnemyDeath(deadEnemy, allies, enemies)
    local killer = deadEnemy and deadEnemy._killedBy
    if not killer or not killer.heroId then return end
    local heroId = toHeroId(killer.heroId)
    if heroId ~= HERO_DOG and heroId ~= HERO_SNOW and heroId ~= HERO_BOUNCE then
        return
    end
    local extra = ETS.getOwned(heroId)
    extra.stacks = extra.stacks + 1

    if heroId == HERO_DOG then
        local atkType = tonumber(deadEnemy.atkType)
        if atkType and atkType >= 1 and atkType <= 8 then
            extra.biteTypes[tostring(atkType)] = true
        end
    elseif heroId == HERO_SNOW then
        local frozenKill = SEM.has(deadEnemy, SEM.FROZEN)
        if frozenKill then
            extra.iceStatues = math.min(3, extra.iceStatues + 1)
            spawnIceStatue(deadEnemy, enemies, killer)
        end
    elseif heroId == HERO_BOUNCE then
        if deadEnemy._killedByRicochet then
            extra.splitKills = extra.splitKills + 1
        end
    end

    local ok, CP = pcall(require, "ui.CharacterPanel")
    if ok and CP and CP.patchExtraTalent then
        CP.patchExtraTalent(heroId, extra)
    end

    if heroId == HERO_DOG then
        applyLiveHpBonus(killer, 1)
        print(string.format("[ExtraTalent] 大狗嚼 衔骨 层=%d 图鉴=%d/8",
            extra.stacks, biteCount(extra)))
    elseif killer.attrs then
        ETS.applyToAttrs(heroId, killer.attrs, extra)
        print(string.format("[ExtraTalent] hero=%d 层=%d split=%d ice=%d",
            heroId, extra.stacks, extra.splitKills, extra.iceStatues))
    end
    markDirty(heroId, extra)
end

---@param dyingUnit table
---@param allies table[]
---@param syncHpFn function
---@return boolean
function ETS.tryTicketRevive(dyingUnit, allies, syncHpFn)
    if not dyingUnit or not dyingUnit.heroId then return false end
    local lover
    for _, a in ipairs(allies or {}) do
        if toHeroId(a.heroId) == HERO_REVIVE and (a.hp or 0) > 0 then
            lover = a
            break
        end
    end
    if not lover then return false end
    local extra = ETS.getOwned(HERO_REVIVE)
    local key = tostring(dyingUnit.heroId)
    if not extra.tickets[key] then return false end
    extra.tickets[key] = nil
    extra.stacks = extra.stacks + 1
    extra.issuedCards = extra.issuedCards + 1
    if dyingUnit.attrs and dyingUnit.attrs.fillHp then
        dyingUnit.attrs:fillHp()
        if syncHpFn then syncHpFn(dyingUnit) end
    else
        dyingUnit.hp = dyingUnit.maxHp
    end
    applyLiveHpBonus(lover, 2)
    local ok, CP = pcall(require, "ui.CharacterPanel")
    if ok and CP and CP.patchExtraTalent then
        CP.patchExtraTalent(HERO_REVIVE, extra)
    end
    markDirty(HERO_REVIVE, extra)
    print("[ExtraTalent] 预存票复活 " .. tostring(dyingUnit.name))
    return true
end

---@param lover table
---@param revivedUnit table
function ETS.onSuccessfulRevive(lover, revivedUnit)
    if toHeroId(lover and lover.heroId) ~= HERO_REVIVE then return end
    local extra = ETS.getOwned(HERO_REVIVE)
    extra.stacks = extra.stacks + 1
    extra.issuedCards = extra.issuedCards + 1
    if revivedUnit and revivedUnit.heroId then
        extra.tickets[tostring(revivedUnit.heroId)] = true
    end
    applyLiveHpBonus(lover, 2)
    local ok, CP = pcall(require, "ui.CharacterPanel")
    if ok and CP and CP.patchExtraTalent then
        CP.patchExtraTalent(HERO_REVIVE, extra)
    end
    markDirty(HERO_REVIVE, extra)
    print(string.format("[ExtraTalent] 预存复活发卡 层=%d 对象=%s", extra.stacks, tostring(revivedUnit and revivedUnit.name)))
end

---@param dyingUnit table
---@param allies table[]
---@param enemies table[]
---@param dealDmgFn function|nil
function ETS.onLoverDeathNuke(dyingUnit, allies, enemies, dealDmgFn)
    if toHeroId(dyingUnit and dyingUnit.heroId) ~= HERO_REVIVE then return end
    local extra = ETS.getOwned(HERO_REVIVE)
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
    if not attacker or not result or result.isMiss then return end
    if attacker._etsBiting then return end
    local heroId = toHeroId(attacker.heroId)
    if heroId ~= HERO_DOG and heroId ~= HERO_BOUNCE then return end
    if not dealDmgFn or (target.hp or 0) <= 0 then return end

    if heroId == HERO_DOG then
        local extra = ETS.getOwned(HERO_DOG)
        local n = biteCount(extra)
        if n <= 0 then return end
        local base = result.totalDamage or 0
        if base <= 0 then return end
        attacker._etsBiting = true
        local ownType = tonumber(attacker.atkType)
        for _, t in ipairs(ATK_ORDER) do
            if extra.biteTypes[tostring(t)] and t ~= ownType then
                local dmg = math.floor(base * (n >= 8 and 0.10 or 0.12) + 0.5)
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
    elseif heroId == HERO_BOUNCE then
        local extra = ETS.getOwned(HERO_BOUNCE)
        if not ETS.hasOrbit(extra) then return end
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
    end
end

--- 冰雕挡一次伤害
---@param target table 受伤的己方
---@param damage number
---@param enemies table[]
---@return number remainingDamage
function ETS.absorbWithIceStatue(target, damage, enemies)
    if damage <= 0 or #battle.iceStatues <= 0 then return damage end
    if not target or not target.heroId then return damage end
    local statue = table.remove(battle.iceStatues, 1)
    local extra = ETS.getOwned(HERO_SNOW)
    extra.iceStatues = math.max(0, extra.iceStatues - 1)
    local ok, CP = pcall(require, "ui.CharacterPanel")
    if ok and CP and CP.patchExtraTalent then
        CP.patchExtraTalent(HERO_SNOW, extra)
    end
    markDirty(HERO_SNOW, extra)
    local source = statue.source
    for _, e in ipairs(enemies or {}) do
        if (e.hp or 0) > 0 then
            SEM.apply(e, SEM.FROZEN, extra.stacks >= 30 and 1.2 or 0.8, source or target, {})
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
    if toHeroId(unit and unit.heroId) ~= HERO_BOUNCE then return end
    if (unit.hp or 0) <= 0 then return end
    if not ETS.hasOrbit(ETS.getOwned(HERO_BOUNCE)) then return end
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
