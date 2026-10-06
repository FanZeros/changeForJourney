-- 第二批真实资源/原UUID/转职门槛/绘图边界回归，不读写玩家存档。
-- 基于已有 advancement_icon_asset_test 的 Start/pcall/Dispose/Exit 模板。
local AVC = require("config.AdvancementConfig")
local CC = require("config.ClassConfig")
local ROOT = "/workspace/assets/image/职业图标/"
local RESOURCE = "image/职业图标/"
local rows = {
    { 2, "spoil", 0, 0, "gate_spoil_bone", "Du1fAVvAyqzeCEVyPXZHYNLg" },
    { 3, "rift", 0, 0, "gate_rift_open", "EMzOmapeBUIeg6mgs9INQaxQ" },
    { 103, "spoil", 1, 0, "gate_103_bone_market", "HtQLqZOMOIHFCMvHaTZv-PLL" },
    { 104, "spoil", 1, 0, "gate_104_peel", "GPlDeQprDSL-pT7gX2skmZ75" },
    { 105, "rift", 1, 0, "gate_105_offset", "GtOZiSuasa4CLCq4AH6XDV2U" },
    { 106, "rift", 1, 0, "gate_106_deep", "Awm1EX3VwdVGFA0ahg7H008L" },
    { 205, "spoil", 2, 103, "gate_205_tide", "DEojuQCwhwHEg7PgA8Pqflwx" },
    { 206, "spoil", 2, 103, "gate_206_bone_debt", "BaWWYWcOh4hlUwhBWbLURZEX" },
    { 207, "spoil", 2, 104, "adv_207_weapon_master", "BefBeTlK9xOE6IhYY7pQqEZK" },
    { 208, "spoil", 2, 104, "gate_208_peelchain", "DhSHyecfmbQrs1s5kVjWvuiK" },
    { 209, "rift", 2, 105, "gate_209_mass", "CGmZ8X_YCHgj1tt3w0dhrq2V" },
    { 210, "rift", 2, 105, "gate_210_corrode", "Ce74EVPj3NM9Y6JCuV8WdVAP" },
    { 211, "rift", 2, 106, "gate_211_choose", "FA52ce3XBVTnHvVSPGiPEYaC" },
    { 212, "rift", 2, 106, "gate_212_burst", "CIb54XV8HC24zcz3DRurYAAC" },
}
local passes, failures = 0, 0
local drawOnly = false
for _, argument in ipairs(GetArguments()) do
    if argument == "-draw-only" then drawOnly = true end
end
---@type Image[]
local images = {}
---@type table<number, Image>
local byId = {}
local function check(ok, label)
    if ok then passes = passes + 1 else failures = failures + 1 end
    print((ok and "[PASS] " or "[FAIL] ") .. label)
end
local function readMeta(id)
    local file = File(ROOT .. "UI_icon_ZY_" .. id .. ".png.meta", FILE_READ)
    local ok, result = pcall(function()
        assert(file:IsOpen(), "meta不存在：" .. id)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        return cjson.decode(table.concat(lines, "\n"))
    end)
    file:Dispose()
    assert(ok, result)
    return result
end
---@param id integer
---@return Image
local function loadImage(id)
    local file = assert(cache:GetFile(RESOURCE .. "UI_icon_ZY_" .. id .. ".png"), "资源根无法解析：" .. id)
    file:Dispose()
    local image = Image()
    images[#images + 1] = image
    assert(image:Load(ROOT .. "UI_icon_ZY_" .. id .. ".png"), "加载PNG失败：" .. id)
    assert(image.width == 280 and image.height == 280 and image.components == 4, "尺寸/RGBA错误：" .. id)
    return image
end

local function testDrawers()
    local spoil = require("_proc.advancement.BatchSpoil")
    local rift = require("_proc.advancement.BatchRift")
    local firstSpoil = require("_proc.advancement.ReviewSpoil")
    local firstRift = require("_proc.advancement.ReviewRift")
    local drawers = { [2] = spoil, [205] = spoil, [206] = spoil, [207] = spoil, [208] = spoil,
        [3] = rift, [209] = rift, [210] = rift, [211] = rift, [212] = rift,
        [103] = firstSpoil, [104] = firstSpoil, [105] = firstRift, [106] = firstRift }
    local signatures = {}
    for _, row in ipairs(rows) do
        local maximum, shapes = 0, 0
        local geometry = {}
        local function point(x, y, extra)
            maximum = math.max(maximum, math.sqrt((x - 139.5) ^ 2 + (y - 139.5) ^ 2) + (extra or 0))
            geometry[#geometry + 1] = string.format("%.9f,%.9f,%.9f", x, y, extra or 0)
        end
        local function polygon(points)
            shapes = shapes + 1
            for _, p in ipairs(points) do point(p[1], p[2], 0) end
        end
        local function line(x0, y0, x1, y1, width)
            shapes = shapes + 1
            point(x0, y0, width * 0.5)
            point(x1, y1, width * 0.5)
        end
        local function stroke(points, width)
            shapes = shapes + 1
            for _, p in ipairs(points) do point(p[1], p[2], width * 0.5) end
        end
        local function ellipse(cx, cy, rx, ry)
            shapes = shapes + 1
            for i = 0, 96 do
                local a = i * math.pi / 48
                point(cx + math.cos(a) * rx, cy + math.sin(a) * ry)
            end
        end
        local function arc(cx, cy, rx, ry, first, last, width)
            shapes = shapes + 1
            for i = 0, 48 do
                local a = (first + (last - first) * i / 48) * math.pi / 180
                point(cx + math.cos(a) * rx, cy + math.sin(a) * ry, width * 0.5)
            end
        end
        local function curve(points, x1, y1, x2, y2, x3, y3)
            local p = points[#points]
            for i = 1, 28 do
                local t, u = i / 28, 1 - i / 28
                points[#points + 1] = { u ^ 3 * p[1] + 3 * u ^ 2 * t * x1 + 3 * u * t ^ 2 * x2 + t ^ 3 * x3,
                    u ^ 3 * p[2] + 3 * u ^ 2 * t * y1 + 3 * u * t ^ 2 * y2 + t ^ 3 * y3 }
            end
        end
        local function emblem(points) stroke(points, 7); polygon(points) end
        local d = { polygon = polygon, line = line, stroke = stroke, ellipse = ellipse,
            arc = arc, curve = curve, emblem = emblem, star = function(cx, cy, radius) ellipse(cx, cy, radius, radius) end,
            DARK = { 14, 12, 10 }, GOLD = { 161, 121, 64 }, BONE = { 220, 206, 170 }, SHADE = { 77, 55, 30 } }
        local draw = drawers[row[1]]
        check(pcall(draw, d, row[1]), row[1] .. "实际绘图模块可执行")
        check(shapes >= 12, row[1] .. "实际器物图元完整 count=" .. shapes)
        check(maximum <= 112, row[1] .. "主体含描边半径不超过112 max=" .. maximum)
        check(not pcall(draw, d, 224), row[1] .. "模块拒绝越权编号224")
        local signature = table.concat(geometry, ";")
        signatures[row[1]] = signature
        -- 改色负对照：坐标及线宽签名不包含颜色，纯换色不能被判成新轮廓。
        geometry = {}
        d.DARK, d.GOLD, d.BONE, d.SHADE = { 0, 0, 0 }, { 20, 30, 40 }, { 50, 60, 70 }, { 80, 90, 100 }
        local recolored = pcall(draw, d, row[1])
        check(recolored and table.concat(geometry, ";") == signature, row[1] .. "改色负对照不改变图元几何签名")
    end
    for _, group in ipairs({ { 2, 103, 104, 205, 206, 207, 208 }, { 3, 105, 106, 209, 210, 211, 212 } }) do
        for i = 1, #group - 1 do
            for j = i + 1, #group do
                check(signatures[group[i]] ~= signatures[group[j]], group[i] .. "/" .. group[j] .. "无颜色图元几何差异（不依赖骨白阈值）")
            end
        end
    end
end

function Start()
    local ok, err = pcall(function()
        if drawOnly then testDrawers(); return end
        check(#rows == 14, "第二批白名单十新图＋四精修")
        check(CC.WARRIOR == "spoil" and CC.MAGE == "rift", "基础职业id保持")
        check(AVC.COST[1].level == 10 and AVC.COST[1].gold == 10000, "一转原门槛保持")
        check(AVC.COST[2].level == 25 and AVC.COST[2].gold == 100000, "二转原门槛保持")
        local reference = loadImage(111)
        local uuids = {}
        for _, row in ipairs(rows) do
            local id, classId, level, parent, talentId = row[1], row[2], row[3], row[4], row[5]
            local cfg = level == 0 and CC.get(classId) or AVC.get(id)
            check(cfg ~= nil and cfg.talentId == talentId, id .. "职业天赋id保持")
            if level == 0 then
                check(AVC.get(id) == nil and cfg.name == (id == 2 and "拾骸者" or "裂隙使"), id .. "基础图归属不误作分支")
            else
                check(cfg.baseClass == classId and cfg.advLevel == level and cfg.combatPower == (level == 1 and 15 or 20), id .. "归属阶段战力保持")
                ---@type table|nil
                local before = nil
                if level == 2 then before = { first = parent } end
                local cost = AVC.COST[level]
                check(AVC.canAdvance(cost.level, cost.gold, level, classId, id, before), id .. "原等级金币精确门槛开放")
                check(not AVC.canAdvance(cost.level - 1, cost.gold, level, classId, id, before), id .. "少一级拒绝")
                check(not AVC.canAdvance(cost.level, cost.gold - 1, level, classId, id, before), id .. "少一金币拒绝")
                -- 二转沿现有契约按一转父分支校验；跨职业夹具也必须带该职业的真实一转。
                local wrongBefore = level == 2 and { first = 101 } or nil
                check(not AVC.canAdvance(30, 1000000, level, "seal", id, wrongBefore), id .. "拒绝错职业及其真实前置分支")
                if level == 2 then
                    check(AVC.canAdvance(30, 1000000, level, "seal", id, before), id .. "既有二转父分支校验契约保持（不重新检查职业字段）")
                    check(cfg.parentBranch == parent, id .. "父分支保持")
                    local siblings = AVC.SECOND_BRANCHES[parent]
                    check(siblings and (siblings[1] == id or siblings[2] == id), id .. "二转映射保持")
                    local otherParent = parent % 2 == 1 and parent + 1 or parent - 1
                    check(not AVC.canAdvance(30, 1000000, 2, classId, id, { first = otherParent }), id .. "拒绝同职业另一父分支")
                    check(not AVC.canAdvance(30, 1000000, 2, classId, id, nil), id .. "缺一转拒绝")
                end
            end
            local meta = readMeta(id)
            check(meta.uuid == row[6], id .. "原meta UUID保持")
            check(not uuids[meta.uuid], id .. "UUID不重复")
            uuids[meta.uuid] = true
            local image = loadImage(id)
            byId[id] = image
            check(true, id .. "真实资源根PNG可加载280RGBA")
            local transparent, opaque, partial, dirty, outside, changed = 0, 0, 0, 0, 0, 0
            for y = 0, 279 do
                for x = 0, 279 do
                    local c = image:GetPixel(x, y)
                    if c.a == 0 then
                        transparent = transparent + 1
                        if c.r ~= 0 or c.g ~= 0 or c.b ~= 0 then dirty = dirty + 1 end
                    elseif c.a == 1 then opaque = opaque + 1
                    else partial = partial + 1 end
                    local differs = image:GetPixelInt(x, y) ~= reference:GetPixelInt(x, y)
                    if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 > 114 ^ 2 then
                        if differs then outside = outside + 1 end
                    elseif differs then changed = changed + 1 end
                end
            end
            check(transparent > 20000 and opaque > 50000, id .. "实体底板透明外缘保持")
            check(partial > 100 and dirty == 0, id .. "抗锯齿且零透明残色")
            check(outside == 0, id .. "与111共用底板逐像素一致 mismatch=" .. outside)
            check(changed > 500, id .. "主体独立不是复制111 changed=" .. changed)
        end
        for _, pair in ipairs({ { 2, 3 }, { 103, 104 }, { 105, 106 }, { 205, 206 }, { 207, 208 }, { 209, 210 }, { 211, 212 } }) do
            local a, b = byId[pair[1]], byId[pair[2]]
            local changed, shape = 0, 0
            for y = 26, 253 do
                for x = 26, 253 do
                    if a:GetPixelInt(x, y) ~= b:GetPixelInt(x, y) then changed = changed + 1 end
                    local ca, cb = a:GetPixel(x, y), b:GetPixel(x, y)
                    local brightA = (ca.r + ca.g + ca.b) / 3 > 0.55
                    local brightB = (cb.r + cb.g + cb.b) / 3 > 0.55
                    if brightA ~= brightB then shape = shape + 1 end
                end
            end
            check(changed > 500 and shape > 200, pair[1] .. "/" .. pair[2] .. "不同器物轮廓非仅换色 pixels=" .. changed .. " shape=" .. shape)
        end
        testDrawers()
    end)
    for _, image in ipairs(images) do image:Dispose() end
    images = {}
    if not ok then failures = failures + 1; log:Write(LOG_ERROR, "[adv-batch2-test] " .. tostring(err)) end
    print("[advancement_batch2_asset_test] " .. (failures == 0 and "ALL PASS" or "FAILED") .. " passes=" .. passes .. " failures=" .. failures)
    engine:Exit()
end
