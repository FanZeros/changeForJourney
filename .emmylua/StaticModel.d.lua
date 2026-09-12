---@meta

--- Auto-generated from Graphics/StaticModel

---@class StaticModel : Drawable
---@field model Model
---@field material Material
---@field boundingBox BoundingBox
---@field numGeometries integer
---@field occlusionLodLevel integer
---@field useInstanceColor boolean Enable the Surface Shader INSTANCE_COLOR input for StaticModel and AnimatedModel.
---@field instanceColor Color Surface Shader INSTANCE_COLOR input for StaticModel and AnimatedModel.
---@field useInstanceCustomData boolean Surface Shader INSTANCE_CUSTOM data for direct instances of StaticModel.
---@field instanceCustomData Vector4 Surface Shader INSTANCE_CUSTOM data for direct instances of StaticModel.
StaticModel = {}

---@param model Model
---@return nil
function StaticModel:SetModel(model) end

---@param material Material
---@return nil
function StaticModel:SetMaterial(material) end

---@param index integer
---@param material Material
---@return boolean
function StaticModel:SetMaterial(index, material) end

---@param level integer
---@return nil
function StaticModel:SetOcclusionLodLevel(level) end

---@param fileName? string
---@return nil
function StaticModel:ApplyMaterialList(fileName) end

---@return Model
function StaticModel:GetModel() end

---@return integer
function StaticModel:GetNumGeometries() end

---@return Material
function StaticModel:GetMaterial() end

---@param index integer
---@return Material
function StaticModel:GetMaterial(index) end

---@return integer
function StaticModel:GetOcclusionLodLevel() end

---@param point Vector3
---@return boolean
function StaticModel:IsInside(point) end

---@param point Vector3
---@return boolean
function StaticModel:IsInsideLocal(point) end

--- Surface Shader INSTANCE_COLOR input for StaticModel and AnimatedModel.
---@param color Color
---@return nil
function StaticModel:SetInstanceColor(color) end

--- Surface Shader INSTANCE_COLOR input for StaticModel and AnimatedModel.
---@return Color
function StaticModel:GetInstanceColor() end

--- Surface Shader INSTANCE_CUSTOM data for direct instances of StaticModel.
---@param data Vector4
---@return nil
function StaticModel:SetInstanceCustomData(data) end

--- Surface Shader INSTANCE_CUSTOM data for direct instances of StaticModel.
---@return Vector4
function StaticModel:GetInstanceCustomData() end

