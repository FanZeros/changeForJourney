local Glyph = require("ui.widget.TalentGlyph")
local StarMap = require("ui.church.talent.TalentStarMap")

function Start()
    local ok, err = pcall(function()
        ---@type table<number, TalentGlyphSample>
        local ids = {}
        local renamedNode = StarMap.getNode(124)
        local originalSample = Glyph.getSample(renamedNode)
        local renamedSample = Glyph.getSample({ icon = renamedNode.icon, name = "Localized talent", color = renamedNode.color, st = renamedNode.st })
        assert(originalSample.glyph == renamedSample.glyph, "翻译后的名称不能改变图标")
        local recoloredSample = Glyph.getSample({ icon = renamedNode.icon, name = renamedNode.name, color = "蓝", st = "large" })
        assert(recoloredSample.glyph == originalSample.glyph and recoloredSample.color == "blue" and recoloredSample.shape == "hex", "复用符号必须独立适配颜色和尺寸")
        local allSamples = {}
        for nodeId = 0, 208 do
            local sample = Glyph.getSample(StarMap.getNode(nodeId))
            if not ids[sample.id] then
                allSamples[#allSamples + 1] = sample
                ids[sample.id] = sample
            end
        end
        assert(#allSamples == 85, "审核目录应覆盖85个图标编号")

        local seenColors, seenShapes = {}, {}
        local calls = 0
        local images = 0
        local depth = 0
        local minDepth = 0
        local names = {
            "nvgBeginPath", "nvgMoveTo", "nvgLineTo", "nvgQuadTo", "nvgBezierTo",
            "nvgClosePath", "nvgCircle", "nvgEllipse", "nvgRoundedRect", "nvgPathWinding",
            "nvgFill", "nvgStroke", "nvgFillColor", "nvgStrokeColor", "nvgFillPaint",
            "nvgStrokePaint", "nvgStrokeWidth", "nvgLineCap", "nvgLineJoin", "nvgGlobalAlpha",
            "nvgTranslate", "nvgScale", "nvgRotate", "nvgSave", "nvgRestore",
            "nvgRGBA", "nvgLinearGradient", "nvgCreateImage", "nvgImagePattern",
        }
        local originals = {}
        for _, name in ipairs(names) do originals[name] = _G[name] end
        for _, name in ipairs(names) do
            _G[name] = function(...)
                calls = calls + 1
                return 0
            end
        end
        _G.nvgSave = function(...) depth = depth + 1 end
        _G.nvgRestore = function(...)
            depth = depth - 1
            minDepth = math.min(minDepth, depth)
        end
        _G.nvgCreateImage = function(...) images = images + 1; return 0 end
        _G.nvgImagePattern = function(...) images = images + 1; return 0 end
        local colors = { ["绿"] = "green", ["红"] = "red", ["蓝"] = "blue", ["紫"] = "purple", ["黄"] = "yellow", ["无"] = "neutral" }
        local shapes = { small = "circle", medium = "diamond", large = "hex" }
        local covered = 0
        local drawOk, drawErr = pcall(function()
            local hexPaths = {}
            local currentPath = {}
            _G.nvgBeginPath = function(...)
                currentPath = {}
                hexPaths[#hexPaths + 1] = currentPath
            end
            _G.nvgMoveTo = function(_, x, y)
                currentPath[#currentPath + 1] = { x, y }
            end
            _G.nvgLineTo = function(_, x, y)
                currentPath[#currentPath + 1] = { x, y }
            end
            Glyph.draw(nil, { name = "六边形验证", glyph = "fist", color = "red", shape = "hex" }, 100, 100, 148, 1)
            for i = 1, 4 do
                local points = hexPaths[i]
                assert(#points == 6, "六边形底盘必须有六个顶点")
                for j = 1, 6 do
                    local a, b = points[j], points[j % 6 + 1]
                    local dx, dy = a[1] - b[1], a[2] - b[2]
                    assert(math.abs(math.sqrt(dx * dx + dy * dy) - 46) < 0.00001, "六边形底盘边长不一致")
                end
            end
            for _, name in ipairs({ "nvgBeginPath", "nvgMoveTo", "nvgLineTo" }) do
                _G[name] = function(...) calls = calls + 1; return 0 end
            end
            local parentAlphaCalls = 0
            _G.nvgGlobalAlpha = function(...) parentAlphaCalls = parentAlphaCalls + 1 end
            local alphas = {}
            _G.nvgRGBA = function(_, _, _, alpha)
                alphas[#alphas + 1] = alpha
                return 0
            end
            local sample124 = Glyph.getSample(StarMap.getNode(124))
            Glyph.draw(nil, sample124, 100, 100, 148, 0.5)
            assert(parentAlphaCalls == 0, "图标不得覆盖外层页面透明度")
            assert(#alphas > 0, "透明度测试未执行颜色绘制")
            for _, a in ipairs(alphas) do assert(a <= 128, "图标透明度未传入颜色或渐变") end
            local zeroCalls = calls
            Glyph.draw(nil, sample124, 100, 100, 148, 0)
            assert(calls == zeroCalls, "全透明图标不应残留绘制")
            _G.nvgRGBA = function(...) calls = calls + 1; return 0 end
            local actualDraw = Glyph.draw
            local detailCalls = 0
            Glyph.draw = function(vg, sample, cx, cy, size, alpha)
                detailCalls = detailCalls + 1
                assert(sample.glyph == sample124.glyph, "详情入口选错图标")
                return actualDraw(vg, sample, cx, cy, size, alpha)
            end
            local detailOk, detailErr = pcall(StarMap.drawTalentIcon, nil, 124, 100, 100, 148, 1)
            Glyph.draw = actualDraw
            assert(detailOk, detailErr)
            assert(detailCalls == 1, "真实星图详情入口未接入新绘制器")
            assert(parentAlphaCalls == 0, "真实详情绘制覆盖外层透明度")
            print("[talent_glyph_coverage_test] PASS 编号选图、详情真实接线、透明度透传与零透明不绘制")
            for nodeId = 0, 208 do
                local node = assert(StarMap.getNode(nodeId), "缺少星图节点")
                local id = tonumber(node.icon:match("UI_icon_TF_(%d+)%.png"))
                local reference = assert(ids[id], "节点没有对应矢量符号")
                ---@cast reference TalentGlyphSample
                ---@type TalentGlyphSample
                local sample = { name = node.name, glyph = reference.glyph, color = colors[node.color], shape = shapes[node.st] }
                seenColors[sample.color] = true
                seenShapes[sample.shape] = true
                for _, size in ipairs({ 48, 64, 148 }) do
                    Glyph.draw(nil, sample, 100, 100, size, 1)
                    Glyph.draw(nil, sample, 100, 100, size, 0.45)
                end
                assert(depth == 0, "节点绘制泄漏变换状态")
                covered = covered + 1
            end
        end)
        for _, name in ipairs(names) do _G[name] = originals[name] end
        assert(drawOk, drawErr)
        assert(minDepth == 0 and depth == 0, "NanoVG保存恢复不平衡")
        assert(images == 0, "代码图标不能依赖图标贴图")
        assert(covered == 209 and calls > 0, "没有覆盖所有节点实际绘制调用")
        local nc, ns = 0, 0
        for _ in pairs(seenColors) do nc = nc + 1 end
        for _ in pairs(seenShapes) do ns = ns + 1 end
        assert(nc == 6 and ns == 3, "节点配色或底盘形状覆盖不全")
        print("[talent_glyph_coverage_test] ALL PASS: 85图标/209节点/6配色/3形状/1254次绘制，零图片调用，状态平衡")
    end)
    if not ok then
        log:Write(LOG_ERROR, "[talent_glyph_coverage_test] " .. tostring(err))
    end
    engine:Exit()
end
