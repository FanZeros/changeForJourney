---@meta

--- Auto-generated from Graphics/LocalFogVolume

---@class LocalFogVolume : Component
---@field albedo Color
---@field emissive Color
---@field radialExtinction number
---@field heightExtinction number
---@field heightFalloff number
---@field radialFalloff number
---@field phaseG number
---@field maxDrawDistance number
LocalFogVolume = {}

---@param albedo Color
---@return nil
function LocalFogVolume:SetAlbedo(albedo) end

---@return Color
function LocalFogVolume:GetAlbedo() end

---@param emissive Color
---@return nil
function LocalFogVolume:SetEmissive(emissive) end

---@return Color
function LocalFogVolume:GetEmissive() end

---@param extinction number
---@return nil
function LocalFogVolume:SetRadialExtinction(extinction) end

---@return number
function LocalFogVolume:GetRadialExtinction() end

---@param extinction number
---@return nil
function LocalFogVolume:SetHeightExtinction(extinction) end

---@return number
function LocalFogVolume:GetHeightExtinction() end

---@param falloff number
---@return nil
function LocalFogVolume:SetHeightFalloff(falloff) end

---@return number
function LocalFogVolume:GetHeightFalloff() end

---@param falloff number
---@return nil
function LocalFogVolume:SetRadialFalloff(falloff) end

---@return number
function LocalFogVolume:GetRadialFalloff() end

---@param phaseG number
---@return nil
function LocalFogVolume:SetPhaseG(phaseG) end

---@return number
function LocalFogVolume:GetPhaseG() end

---@param distance number
---@return nil
function LocalFogVolume:SetMaxDrawDistance(distance) end

---@return number
function LocalFogVolume:GetMaxDrawDistance() end

