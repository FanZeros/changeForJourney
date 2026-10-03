local Glyph = require("ui.widget.TalentGlyph")
local StarMap = require("ui.church.talent.TalentStarMap")

---@type TalentGlyphSample[]
local allSamples = {}
local seen = {}
for id = 0, 208 do
    local sample = Glyph.getSample(StarMap.getNode(id))
    if not seen[sample.id] then
        allSamples[#allSamples + 1] = sample
        seen[sample.id] = true
    end
end
local samples = {}
for _, id in ipairs({ 1, 2, 33, 104, 114, 5 }) do
    samples[#samples + 1] = Glyph.getSample(StarMap.getNode(id))
end

---@type NVGContextWrapper?
local vg
local DESIGN_W, DESIGN_H = 1536, 1080
local reviewPage = 0

function Start()
    for _, arg in ipairs(GetArguments()) do
        local value = arg:match("^%-talent_review_page=(%d+)$")
        if value then reviewPage = tonumber(value) or 0 end
    end
    vg = nvgCreate(1)
    assert(vg, "图标审核 NanoVG 初始化失败")
    local font = nvgCreateFont(vg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    assert(font >= 0, "图标审核字体加载失败")
    assert(#allSamples == 85, "全量图标未覆盖85个编号")
    local ids = {}
    for _, sample in ipairs(allSamples) do
        assert(not ids[sample.id], "重复审核图标编号")
        ids[sample.id] = true
    end
    SubscribeToEvent(vg, "NanoVGRender", "DrawTalentGlyphReview")
    print("[TalentGlyphReview] 85个独立编号覆盖完成；未加载任何PNG图标；审核页=" .. tostring(reviewPage))
end

local function text(x, y, value, size, r, g, b)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, size)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
    nvgText(vg, x, y, value, nil)
end

function DrawTalentGlyphReview()
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local logicalH = graphics:GetHeight() / dpr
    local scale = math.min(logicalW / DESIGN_W, logicalH / DESIGN_H)
    nvgBeginFrame(vg, logicalW, logicalH, dpr)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logicalW, logicalH)
    nvgFillColor(vg, nvgRGBA(14, 12, 10, 255))
    nvgFill(vg)
    nvgSave(vg)
    nvgTranslate(vg, (logicalW - DESIGN_W * scale) * 0.5, (logicalH - DESIGN_H * scale) * 0.5)
    nvgScale(vg, scale, scale)

    if reviewPage > 0 then
        text(768, 48, "暗铁骨白 · 全量图标审核 " .. tostring(reviewPage) .. "/5", 32, 220, 208, 180)
        text(768, 91, "85个编号全覆盖 / 大样与48px、未点亮态 / 无贴图、无底纹星形", 18, 142, 132, 114)
        local first = (reviewPage - 1) * 18 + 1
        local last = math.min(first + 17, #allSamples)
        for index = first, last do
            local sample = allSamples[index]
            local i = index - first
            local cx = 128 + (i % 6) * 256
            local top = 134 + math.floor(i / 6) * 288
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - 116, top, 232, 274, 14)
            nvgFillColor(vg, nvgRGBA(24, 21, 18, 255))
            nvgFill(vg)
            Glyph.draw(vg, sample, cx, top + 91, 148, 1)
            text(cx, top + 180, tostring(sample.id) .. " · " .. sample.name, 19, 220, 208, 181)
            Glyph.draw(vg, sample, cx - 40, top + 226, 48, 1)
            Glyph.draw(vg, sample, cx + 40, top + 226, 48, 0.45)
            text(cx - 40, top + 262, "48px", 12, 137, 129, 115)
            text(cx + 40, top + 262, "未点亮", 12, 137, 129, 115)
        end
    else
    text(768, 48, "天赋图标 · 暗铁骨白审核", 32, 220, 208, 180)
    text(768, 91, "暗铁底盘 / 骨白浮雕 / 低饱和系色 / 纯代码绘制", 18, 142, 132, 114)

    for i, sample in ipairs(samples) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local cx = 256 + col * 512
        local top = 134 + row * 452
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 229, top, 458, 420, 18)
        nvgFillColor(vg, nvgRGBA(24, 21, 18, 255))
        nvgFill(vg)
        Glyph.draw(vg, sample, cx, top + 155, 242, 1)
        text(cx, top + 298, sample.name, 26, 220, 208, 181)
        Glyph.draw(vg, sample, cx - 104, top + 357, 64, 1)
        Glyph.draw(vg, sample, cx, top + 357, 48, 1)
        Glyph.draw(vg, sample, cx + 104, top + 357, 48, 0.45)
        text(cx - 104, top + 403, "64px", 15, 137, 149, 166)
        text(cx, top + 403, "48px", 15, 137, 149, 166)
        text(cx + 104, top + 403, "未点亮", 15, 137, 149, 166)
    end
    end
    text(768, 1040, "仅审核样稿：正式星图、节点连线和玩法均未替换", 19, 163, 172, 184)
    nvgRestore(vg)
    nvgEndFrame(vg)
end

function Stop()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end
