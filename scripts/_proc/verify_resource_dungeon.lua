-- 基于选关验收入口的同一NanoVG生命周期，展示正式副本战斗，不读取或修改存档。
-- -review-dungeon=gold_mine|equipment_vault|black_diamond -review-team=1|2|3
local Scene = require("ui.dungeon.DungeonBattleScene")
local BattleDraw = require("ui.battle.scene.BattleDraw")
local BattleCombat = require("ui.battle.combat.BattleCombat")
local DungeonConfig = require("config.DungeonConfig")
local HeroConfig = require("config.HeroConfig")

---@type NVGContextWrapper|nil
local vg = nil
local dungeonId, teamIdx = "equipment_vault", 2
local opened = false
local renderLogged = false

function Start()
    for _, argument in ipairs(GetArguments()) do
        dungeonId = argument:match("^%-review%-dungeon=(.+)$") or dungeonId
        teamIdx = tonumber(argument:match("^%-review%-team=([123])$")) or teamIdx
    end
    assert(DungeonConfig.isResourceDungeon(dungeonId), "验收入口仅支持资源副本")
    vg = assert(nvgCreate(1), "副本验收图形上下文创建失败")
    assert(nvgCreateFont(vg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf") >= 0,
        "副本验收字体加载失败")
    local function image(path)
        local handle = nvgCreateImage(vg, path, 0)
        assert(handle >= 0, "副本验收图片加载失败: " .. path)
        return handle
    end
    local allyTags = {}
    for index = 1, 6 do
        allyTags[index] = image("image/通用图标/ICON_ZY_" .. index .. ".png")
    end
    BattleDraw.setContext({
        combat = BattleCombat, imgHeroCards = {}, imgMonsterCards = {}, imgAllyTags = allyTags,
        imgHpBg = image("image/界面底板/战斗/UI_ZD_HP1.png"),
        imgHpFill = image("image/界面底板/战斗/UI_ZD_HPT2.png"),
        imgEsFill = image("image/界面底板/战斗/UI_ZD_HPT3.png"),
    })
    Scene.init(vg)
    local entry = assert(DungeonConfig.getCombatEntry(dungeonId, 1))
    local allies = {}
    for heroId = 1, 4 do
        allies[#allies + 1] = assert(HeroConfig.createHero(heroId, 60, nil, {}, {}))
    end
    Scene.open({
        allies = allies,
        data = {
            dungeonId = dungeonId, floor = 1, teamIdx = teamIdx,
            challengeId = "visual-only", resourceCombat = true,
            stageEntry = entry, monsterLevel = entry.monsterLevel,
        },
        onClose = function() end,
    })
    -- 仅推进入场动画；不运行真实挑战、不发WIN、不改变任何玩家数据。
    for _ = 1, 12 do Scene.update(0.05) end
    opened = true
    SubscribeToEvent("NanoVGRender", "HandleResourceDungeonReviewRender")
    print(string.format("[verify_resource_dungeon] %s 队伍%d | 首波%d 同屏4",
        dungeonId, teamIdx, entry.firstCount))
end

function HandleResourceDungeonReviewRender()
    if not vg or not opened then return end
    if not renderLogged then
        print("[verify_resource_dungeon] 首帧正式NanoVG渲染")
        renderLogged = true
    end
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    local fit = math.min(width / 1080, height / 2400)
    nvgBeginFrame(vg, width, height, dpr)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(16, 16, 22, 255))
    nvgFill(vg)
    nvgSave(vg)
    nvgTranslate(vg, (width - 1080 * fit) * 0.5, (height - 2400 * fit) * 0.5)
    nvgScale(vg, fit, fit)
    Scene.draw(vg)
    nvgRestore(vg)
    nvgEndFrame(vg)
end

function Stop()
    if opened then Scene.close(); opened = false end
    if vg then nvgDelete(vg); vg = nil end
end
