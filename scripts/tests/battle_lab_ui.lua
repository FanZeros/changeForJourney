-- 独立的战斗平衡工作台：运行 tests/battle_lab_ui.lua，不进入玩家游戏或存档。
-- 选择关卡、模式、英雄、等级、局数；结果来自 tests.BattleLab 的真实逐帧战斗。
local Lab = require("tests.BattleLab")
local SC = require("config.StageConfig")
local HC = require("config.HeroConfig")

local canvas = nil
local buttons = {}
local heroes = HC.getAllIds()
local choice = { stageId = SC.NORMAL_FIRST_STAGE, mode = "firstClear",
    level = 1, runs = 10, seed = 926, team = { 1, 3, 2, 0 } }
local report = nil
local notice = "选择配置后点击开始；不影响真实存档或游戏战斗。"
local runOptions = { 1, 5, 10, 20, 50 }

local function pickHero(team, slot, delta)
    local id = team[slot]
    local pos = 1 -- 空位；后续依次为 heroes[1..n]
    for i, heroId in ipairs(heroes) do
        if heroId == id then pos = i + 1 break end
    end
    local count = #heroes + 1
    for offset = 1, count do
        local nextPos = (pos - 1 + delta * offset) % count + 1
        local candidate = nextPos == 1 and 0 or heroes[nextPos - 1]
        local occupied = false
        for i, selected in ipairs(team) do
            if i ~= slot and candidate ~= 0 and selected == candidate then
                occupied = true
                break
            end
        end
        if not occupied then return candidate end
    end
    return id
end

local function addButton(id, text, x, y, w, h, hot)
    buttons[#buttons + 1] = { id = id, x = x, y = y, w = w, h = h }
    nvgBeginPath(canvas)
    nvgRoundedRect(canvas, x, y, w, h, 7)
    nvgFillColor(canvas, hot and nvgRGBA(126, 72, 102, 240) or nvgRGBA(43, 36, 51, 240))
    nvgFill(canvas)
    nvgStrokeColor(canvas, nvgRGBA(175, 134, 109, 210))
    nvgStrokeWidth(canvas, 1)
    nvgStroke(canvas)
    nvgFontFace(canvas, "sans")
    nvgFontSize(canvas, 16)
    nvgTextAlign(canvas, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(canvas, nvgRGBA(245, 232, 215, 255))
    nvgText(canvas, x + w * .5, y + h * .5, text, nil)
end

local function label(x, y, text, size, color)
    nvgFontFace(canvas, "sans")
    nvgFontSize(canvas, size or 18)
    nvgTextAlign(canvas, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(canvas, color or nvgRGBA(224, 214, 204, 255))
    nvgText(canvas, x, y, text, nil)
end

local function show()
    local graphics = GetGraphics()
    local dpr = graphics:GetDPR()
    if dpr <= 0 then dpr = 1 end
    local w, h = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(canvas, w, h, dpr)
    nvgBeginPath(canvas)
    nvgRect(canvas, 0, 0, w, h)
    nvgFillColor(canvas, nvgRGBA(17, 15, 24, 255))
    nvgFill(canvas)
    local left = math.max(20, (w - 1050) * .5)
    local panelW = math.min(1050, w - 40)
    buttons = {}
    label(left, 38, "终焉之门  /  战斗平衡工作台", 27, nvgRGBA(223, 177, 107, 255))
    label(left, 70, "独立进程 · 模板英雄无装备/神器/遗物 · 首通含词缀与狂暴 · 固定种子复现", 15)
    local entry = SC.getStage(choice.stageId)
    label(left, 112, string.format("关卡 #%d  %s  怪物 Lv.%d", choice.stageId,
        entry and entry.name or "?", entry and entry.monsterLevel or 1), 20)
    addButton("stage_prev", "上一关", left, 132, 120, 38)
    addButton("stage_next", "下一关", left + 132, 132, 120, 38)
    addButton("mode", choice.mode == "firstClear" and "首通模式" or "挂机模式", left + 268, 132, 130, 38)
    label(left + 418, 150, "随机种子 " .. choice.seed, 16)
    addButton("seed", "换种子", left + 594, 132, 100, 38)
    label(left, 202, string.format("英雄统一等级 Lv.%d", choice.level), 19)
    addButton("level_down", "-10", left + 265, 183, 76, 36)
    addButton("level_up", "+10", left + 349, 183, 76, 36)
    addButton("runs", "重复 " .. choice.runs .. " 局", left + 445, 183, 142, 36)
    for i = 1, 4 do
        local id = choice.team[i]
        local config = id and id ~= 0 and HC.get(id) or nil
        local x = left + ((i - 1) % 2) * (panelW * .5)
        local y = 242 + math.floor((i - 1) / 2) * 55
        label(x, y + 16, string.format("位置%d: %s", i,
            config and ("#" .. id .. " " .. config.name) or "空位"), 17)
        addButton("hero_prev_" .. i, "<", x + panelW * .5 - 110, y, 42, 34)
        addButton("hero_next_" .. i, ">", x + panelW * .5 - 58, y, 42, 34)
    end
    addButton("run", "开始真实战斗测试", left, 375, 240, 46, true)
    label(left + 255, 400, notice, 15)
    label(left, 430, "模拟期间界面会暂停重绘；结束后将显示结果并保存 battle_lab_report.json", 15)
    local resultY = 465
    if report then
        label(left, resultY, string.format("%s #%d · 胜 %d/%d (%.1f%%) 败 %d 超时 %d",
            report.stageName, report.stageId, report.wins, report.completedRuns,
            report.winRate, report.losses, report.timeouts), 21, nvgRGBA(224, 177, 107, 255))
        label(left, resultY + 32, string.format("均耗时 %.1fs  |  剩余血量 %.1f%%  |  总伤害 %.0f  |  总治疗 %.0f",
            report.avgSeconds, report.avgHpRemainingPct, report.avgDamage, report.avgHealing), 17)
        for i, stat in ipairs(report.heroStats) do
            local y = resultY + 80 + (i - 1) * 40
            label(left, y, string.format("#%d %-12s   场均输出 %.0f   治疗 %.0f   承伤 %.0f   暴击 %.1f%%",
                stat.heroId, stat.name, stat.avgDamage, stat.avgHealing, stat.avgTaken, stat.critRate), 17)
        end
        label(left, resultY + 263, "逐局种子/胜负/用时/英雄伤害在运行日志的 [BattleLab][REPORT] JSON 中。", 15)
    else
        label(left, resultY, "结果将在此显示；日志可复制完整 JSON 保存或与改数值前对比。", 17)
    end
    nvgEndFrame(canvas)
end

local function execute(id)
    if id == "stage_prev" then
        choice.stageId = SC.getPrevStageId(choice.stageId) or choice.stageId
    elseif id == "stage_next" then
        choice.stageId = SC.getNextStageId(choice.stageId) or choice.stageId
    elseif id == "mode" then
        choice.mode = choice.mode == "firstClear" and "idle" or "firstClear"
    elseif id == "seed" then
        choice.seed = choice.seed + 100
    elseif id == "level_up" then
        choice.level = math.min(345, choice.level + 10)
    elseif id == "level_down" then
        choice.level = math.max(1, choice.level - 10)
    elseif id == "runs" then
        for i, value in ipairs(runOptions) do
            if value == choice.runs then
                choice.runs = runOptions[i % #runOptions + 1]
                break
            end
        end
    elseif id == "run" then
        local ids = {}
        for _, heroId in ipairs(choice.team) do
            if heroId ~= 0 then ids[#ids + 1] = { id = heroId, level = choice.level } end
        end
        local result, err = Lab.run({ stageId = choice.stageId, mode = choice.mode,
            seed = choice.seed, runs = choice.runs, heroes = ids }, nil)
        report = result
        notice = result and ("完成 " .. result.completedRuns .. " 局；每局随机种子已记入日志")
            or ("测试失败：" .. tostring(err))
        if result then
            local file = File("battle_lab_report.json", FILE_WRITE)
            if file:IsOpen() then
                file:WriteLine(cjson.encode(result))
                file:Close()
                print("[BattleLab] 已保存 battle_lab_report.json")
            end
            print("[BattleLab][REPORT] " .. cjson.encode(result))
        else
            print("[BattleLab] ERROR " .. tostring(err))
        end
    else
        local direction, slot = id:match("^hero_(prev)_(%d+)$")
        if not direction then direction, slot = id:match("^hero_(next)_(%d+)$") end
        if direction then
            local slotIndex = tonumber(slot)
            choice.team[slotIndex] = pickHero(choice.team, slotIndex, direction == "prev" and -1 or 1)
        end
    end
    if id ~= "run" then report = nil end
end

function Start()
    canvas = nvgCreate(1)
    assert(canvas, "NanoVG 初始化失败")
    assert(nvgCreateFont(canvas, "sans", "Fonts/MiSans-Regular.ttf") >= 0, "字体加载失败")
    SubscribeToEvent(canvas, "NanoVGRender", "BattleLabRender")
    SubscribeToEvent("MouseButtonUp", "BattleLabClick")
    print("[BattleLab] 工作台就绪，无存档及奖励写入")
end

function BattleLabRender()
    show()
end

function BattleLabClick(_, eventData)
    if eventData:GetInt("Button") ~= MOUSEB_LEFT then return end
    local pos = input:GetMousePosition()
    local dpr = GetGraphics():GetDPR()
    if dpr <= 0 then dpr = 1 end
    local x, y = pos.x / dpr, pos.y / dpr
    for _, btn in ipairs(buttons) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            execute(btn.id)
            return
        end
    end
end

function Stop()
    if canvas then nvgDelete(canvas) canvas = nil end
end
