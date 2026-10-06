-- 远征收益概览：复用选关模态的设计空间，仅消费只读离线期望快照。
local Dispatcher = require("runtime.ClientDispatcher")
local OfflineService = require("rules.offline.OfflineService")
local ET = require("config.ExpTable")
local SC = require("config.StageConfig")
local ResourceDefs = require("config.ResourceDefs")
local HeroFrame = require("ui.widget.HeroFrame")
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local NumberUtil = require("core.NumberUtil")
local I18n = require("core.I18n")

local M = {}
local D = { x = 65, y = 636.5, w = 950, h = 1117,
    cardX = 105, cardY = 812, cardW = 870, cardH = 245, cardStep = 259,
    closeX = 953, closeY = 714, closeSize = 48 }
local icons = {} ---@type table<string, number>
local lastRefresh = -1
local snapshot = { teams = {}, gold = 0, diamond = 0, equipment = 0 }
local selectedTeam = 1
local dragX, dragY = 0, 0
local dragged = false

local function inside(x, y, left, top, width, height)
    return x >= left and x <= left + width and y >= top and y <= top + height
end

local function amount(value)
    value = math.max(0, value or 0)
    if value >= 10000 then return NumberUtil.format(value) end
    if value > 0 and value < 0.01 then return "<0.01" end
    return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
end

local function text(vg, x, y, caption, size, width, color, align)
    caption = I18n.lookup(caption)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, size)
    local measured = nvgTextBounds(vg, 0, 0, caption) or 0
    local font = measured > width and math.max(16, size * width / measured) or size
    DrawUtil.drawTextStroke(vg, x, y, caption, font,
        align or (NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE), color[1], color[2], color[3], 2)
end

local GOLD = DarkIcon.Palette.GOLD_HI
local BONE = DarkIcon.Palette.BONE
local DIM = DarkIcon.Palette.BONE_DIM

-- 只复制位置字段，当前战线优先于已预约的下一关；不启动/挂载战斗驱动。
local function refresh()
    local heroes = Dispatcher.get("heroes") or {}
    local source = Dispatcher.get("battle") or {}
    local battle = {}
    for key, value in pairs(source) do battle[key] = value end
    local saved = type(source.teamStageIds) == "table" and source.teamStageIds or {}
    battle.teamStageIds = {}
    for key, value in pairs(saved) do battle.teamStageIds[key] = value end
    local Tri = require("ui.battle.tri.BattleTriPage")
    for team = 1, ET.TEAM_COUNT do
        local current = Tri.getTeamStageId(team)
        if current then battle.teamStageIds[tostring(team)] = current end
    end
    local preview = OfflineService.PreviewTeamIncome(heroes, battle, Dispatcher.get("dungeon"), 3600)
    local rewards = {}
    for _, entry in ipairs(preview and preview.teamRewards or {}) do rewards[entry.teamIdx] = entry end
    local teams = {}
    local unlocked = ET.getUnlockedTeamCount(battle)
    local configured = type(heroes.teams) == "table" and next(heroes.teams) ~= nil
    for team = 1, ET.TEAM_COUNT do
        local data = configured and (heroes.teams[team] or heroes.teams[tostring(team)]) or nil
        local slots = data and data.slots or (not configured and team == 1 and heroes.deployed) or {}
        slots = type(slots) == "table" and slots or {}
        local avatars, occupied = {}, 0
        for slot = 1, ET.TEAM_MAX_SLOTS do
            local id = tonumber(slots[slot]) or 0
            local hero = heroes.roster and (heroes.roster[id] or heroes.roster[tostring(id)])
            if id > 0 and hero then
                avatars[slot] = { heroId = id, level = hero.level or 1 }
                occupied = occupied + 1
            end
        end
        local stageId = tonumber(battle.teamStageIds[tostring(team)] or battle.teamStageIds[team]
            or (team == 1 and battle.currentStageId))
        local reward = rewards[team]
        local equipment, scrolls = 0, 0
        for _, seed in ipairs(reward and reward.equipSeeds or {}) do equipment = equipment + seed.count end
        for key, count in pairs(reward and reward.scrollDrops or {}) do
            if key ~= "sweepTicket" then scrolls = scrolls + count end
        end
        local status = "按当前关卡估算"
        if team > unlocked then status = ET.getTeamUnlockText(team)
        elseif occupied == 0 then status = "未上阵队员，暂无收益"
        elseif not reward then status = "暂无有效挂机关卡"
        elseif stageId and SC.isTerminalTemple(stageId) then status = "终焉不挂机；采用末关基准" end
        teams[team] = { index = team, unlocked = team <= unlocked, avatars = avatars,
            stageId = stageId, status = status, reward = reward, equipment = equipment, scrolls = scrolls }
    end
    local equipment = 0
    for _, row in ipairs(teams) do equipment = equipment + row.equipment end
    snapshot = { teams = teams, gold = preview and preview.gold or 0,
        diamond = preview and preview.diamond or 0, equipment = equipment }
    lastRefresh = time.elapsedTime
end

function M.open(team)
    selectedTeam = tonumber(team) or 1
    dragged = false
    refresh()
    print(string.format("[ExpeditionOverview] open: 金币/h=%s 黑晶/h=%s 装备期望/h=%s",
        amount(snapshot.gold), amount(snapshot.diamond), amount(snapshot.equipment)))
end

function M.init(vg)
    HeroFrame.initImages(vg)
    for _, key in ipairs({ "gold", "diamond", "random_scroll", "sweep_ticket" }) do
        local definition = ResourceDefs.DEFS[key]
        if not icons[key] then icons[key] = nvgCreateImage(vg, definition.iconPath, 0) or -1 end
    end
end

local function metric(vg, x, y, label, value, icon, expected)
    if icons[icon] and icons[icon] >= 0 then
        DrawUtil.drawImageCentered(vg, icons[icon], x + 18, y + 10, 34, 34, 1)
    else
        DarkIcon.draw(vg, icon == "equip" and "relicbox" or "merit", x + 18, y + 10, 30, 1)
    end
    text(vg, x + 42, y, label, 20, 105, DIM)
    text(vg, x + 42, y + 29, (expected and "≈" or "") .. amount(value), 28, 105, GOLD)
end

function M.draw(vg, scale)
    if time.elapsedTime - lastRefresh >= 1 then refresh() end
    M.init(vg)
    nvgSave(vg)
    nvgTranslate(vg, 540, 1195)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -540, -1195)
    DarkIcon.drawNine(vg, "panel", D.x, D.y, D.w, D.h, { titleH = 157, radius = 24 })
    text(vg, 540, 707, "远征收益概览", 44, 650, GOLD, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    text(vg, 540, 765, "1小时预估 · 离线基准 · 选择队伍后选关", 25, 760, BONE,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DarkIcon.drawNine(vg, "btn", D.closeX - 24, D.closeY - 24, 48, 48)
    text(vg, D.closeX, D.closeY, "×", 35, 40, BONE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for team, row in ipairs(snapshot.teams) do
        local y = D.cardY + (team - 1) * D.cardStep
        DarkIcon.drawNine(vg, "plain", D.cardX, y, D.cardW, D.cardH,
            { accent = row.unlocked and team == selectedTeam and "gold" or nil, radius = 14 })
        text(vg, 128, y + 30, "队伍 " .. team, 30, 340, row.unlocked and GOLD or DIM)
        local stageName = row.stageId and SC.getStageDisplayName(row.stageId) or "尚未选择关卡"
        text(vg, 128, y + 69, stageName, 23, 365, BONE)
        for slot = 1, ET.TEAM_MAX_SLOTS do
            local hero = row.avatars[slot]
            HeroFrame.draw(vg, { cx = 160 + (slot - 1) * 84, cy = y + 121, size = 65,
                heroId = hero and hero.heroId, level = hero and hero.level,
                state = hero and "owned" or (row.unlocked and "empty" or "locked"),
                showLevel = hero ~= nil, showClass = hero ~= nil, alpha = row.unlocked and 1 or 0.5 })
        end
        text(vg, 128, y + 178, row.status, 21, 365, DIM)
        local reward = row.reward or {}
        local diamond = SC.isResourceStage(row.stageId or 0)
            and require("config.DungeonConfig").decodeStageId(row.stageId) == "black_diamond"
        metric(vg, 504, y + 67, diamond and "黑晶" or "金币",
            diamond and reward.diamond or reward.gold, diamond and "diamond" or "gold", false)
        metric(vg, 657, y + 67, "远征经验", reward.adventureExp, "exp", false)
        local perHero = reward.heroCount and math.floor((reward.adventurerExp or 0) / reward.heroCount + 0.5) or 0
        metric(vg, 810, y + 67, "每名队员经验", perHero, "hero_exp", false)
        metric(vg, 504, y + 137, "装备/件", row.equipment, "equip", true)
        metric(vg, 657, y + 137, "卷轴合计/张", row.scrolls, "random_scroll", true)
        metric(vg, 810, y + 137, "扫荡券/张", reward.scrollDrops and reward.scrollDrops.sweepTicket,
            "sweep_ticket", true)
        local buttonX, buttonY = 782, y + 198
        DarkIcon.drawNine(vg, "btn", buttonX, buttonY, 170, 38,
            { accent = row.unlocked and "gold" or nil, alpha = row.unlocked and 1 or 0.45 })
        text(vg, buttonX + 85, buttonY + 19, row.unlocked and "选择队伍 →" or "尚未解锁", 22, 158,
            row.unlocked and GOLD or DIM, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    text(vg, 540, 1622, "三队合计：金币 " .. amount(snapshot.gold) .. "  黑晶 "
        .. amount(snapshot.diamond) .. "  装备 ≈" .. amount(snapshot.equipment) .. " 件",
        26, 860, GOLD, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    text(vg, 540, 1670, "≈为随机掉落期望，不保证每小时获得；六种卷轴均匀随机。", 21, 865, DIM,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    text(vg, 540, 1705, "在线受击杀效率影响；不含首通大奖、分解精粹及24小时后的衰减。", 21, 865, DIM,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgRestore(vg)
end

function M.handleDragBegin(x, y)
    dragX, dragY, dragged = x, y, false
end

function M.handleDragMove(x, y)
    if math.max(math.abs(x - dragX), math.abs(y - dragY)) >= 15 then dragged = true end
end

-- 返回：close / team / none，宿主负责导航与战斗独占状态的二次校验。
function M.handleInput(x, y)
    if dragged then dragged = false return "none" end
    if inside(x, y, D.closeX - 24, D.closeY - 24, 48, 48)
        or not inside(x, y, D.x, D.y, D.w, D.h) then return "close" end
    for team, row in ipairs(snapshot.teams) do
        if row.unlocked and inside(x, y, D.cardX, D.cardY + (team - 1) * D.cardStep, D.cardW, D.cardH) then
            selectedTeam = team
            print("[ExpeditionOverview] 选择队伍=" .. team)
            return "team", team
        end
    end
    return "none"
end

return M
