---@meta

--- Auto-generated from Scene/SplinePath

---@class SplinePath : Component
---@field interpolationMode InterpolationMode
---@field speed number
---@field length number
---@field controlledNode Node
SplinePath = {}

---@param point Node
---@param index? integer
---@return nil
function SplinePath:AddControlPoint(point, index) end

---@param point Node
---@return nil
function SplinePath:RemoveControlPoint(point) end

---@return nil
function SplinePath:ClearControlPoints() end

---@param mode InterpolationMode
---@return nil
function SplinePath:SetInterpolationMode(mode) end

---@param factor number
---@return nil
function SplinePath:SetPosition(factor) end

---@param controlled Node
---@return nil
function SplinePath:SetControlledNode(controlled) end

---@return InterpolationMode
function SplinePath:GetInterpolationMode() end

---@return number
function SplinePath:GetSpeed() end

---@return number
function SplinePath:GetLength() end

---@return Vector3
function SplinePath:GetPosition() end

---@return Node
function SplinePath:GetControlledNode() end

---@param factor number
---@return Vector3
function SplinePath:GetPoint(factor) end

---@param timeStep number
---@return nil
function SplinePath:Move(timeStep) end

---@return nil
function SplinePath:Reset() end

---@return boolean
function SplinePath:IsFinished() end

