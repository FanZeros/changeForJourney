-- ============================================================================
-- ArtifactAssetUtil - 神器美术资产路径与绘制
-- ============================================================================

local DrawUtil     = require("core.DrawUtil")
local DarkIcon     = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质底框矢量绘制
local ImageCache   = require("ui.ImageCache")
local ArtifactDefs = require("shared.artifact.ArtifactDefs")

local ArtifactAssetUtil = {}

---@param artifactTypeId number
---@return string|nil
function ArtifactAssetUtil.getIconPath(artifactTypeId)
    local id = tonumber(artifactTypeId) or 0
    if id <= 0 then return nil end
    return "image/神器图标/UI_icon_SQ_A" .. id .. ".png"
end

--- 从神器实例解析类型 ID（1~16）
---@param artifact table|nil
---@return number
function ArtifactAssetUtil.resolveTypeId(artifact)
    if not artifact then return 0 end
    local candidates = {
        artifact.artifactId,
        artifact.defId,
        artifact.type,
        artifact.templateId,
    }
    for _, id in ipairs(candidates) do
        local n = tonumber(id)
        if n and ArtifactDefs.get(n) then
            return n
        end
    end
    return tonumber(artifact.artifactId) or tonumber(artifact.type) or 0
end

---@return number[]
function ArtifactAssetUtil.getAssetIds()
    local ids = {}
    for id in pairs(ArtifactDefs.ARTIFACTS or {}) do
        ids[#ids + 1] = tonumber(id) or id
    end
    table.sort(ids)
    return ids
end

--- 预加载全部神器图标到 ImageCache
function ArtifactAssetUtil.preloadIcons()
    for _, id in ipairs(ArtifactAssetUtil.getAssetIds()) do
        ImageCache.getArtifactIcon(id)
    end
end

local function drawCornerName(vg, cx, cy, size, nameText)
    nameText = tostring(nameText or "")
    if nameText == "" then return end
    local nameX = cx + size * 0.5 - 8
    local nameY = cy + size * 0.5 - 8
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 26)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
    local sStep = math.pi * 2 / 12
    for si = 0, 11 do
        local sa = si * sStep
        nvgText(vg, nameX + math.cos(sa) * 3, nameY + math.sin(sa) * 3, nameText, nil)
    end
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, nameX, nameY, nameText, nil)
end

--- 绘制神器图标（品质框 + 类型图标）
---@param vg any
---@param artifact table|nil
---@param cx number
---@param cy number
---@param size number
---@param opts table|nil { selected, nameStyle = "below"|"corner", iconPadding, hideQualityBg }
function ArtifactAssetUtil.drawIcon(vg, artifact, cx, cy, size, opts)
    if not artifact then return end
    opts = opts or {}

    local q = math.max(1, math.min(tonumber(artifact.quality) or 1, 6))
    local typeId = ArtifactAssetUtil.resolveTypeId(artifact)

    if not opts.hideQualityBg then
        DarkIcon.drawQualityBg(vg, q, cx, cy, size, size, 1.0)  -- [暗黑化 P2-A] 矢量品质底框
    end

    local iconPadding = opts.iconPadding or math.max(12, math.floor(size * 0.12))
    local inner = size - iconPadding * 2
    local iconImg = ImageCache.getArtifactIcon(typeId)
    if iconImg >= 0 then
        DarkIcon.drawIconDark(vg, iconImg, cx, cy, inner, inner, 1.0)  -- [暗黑化 P2-B]
    else
        local qc = ArtifactDefs.getQualityColor(q)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, inner * 0.45)
        nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 180))
        nvgFill(vg)
    end

    if opts.nameStyle == "below" then
        local name = ArtifactDefs.getName(artifact)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.floor(size * 0.14))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, cx, cy + size * 0.29, name, nil)
    elseif opts.nameStyle == "corner" then
        drawCornerName(vg, cx, cy, size, opts.name or ArtifactDefs.getName(artifact))
    end

    if opts.selected then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - size * 0.5, cy - size * 0.5, size, size, 12)
        nvgStrokeColor(vg, nvgRGBA(0xff, 0xc1, 0x40, 255))
        nvgStrokeWidth(vg, 5)
        nvgStroke(vg)
    end
end

return ArtifactAssetUtil
