---@meta

--- Auto-generated from Urho2D/ConstraintPulley2D

---@class ConstraintPulley2D : Constraint2D
---@field ownerBodyGroundAnchor Vector2
---@field otherBodyGroundAnchor Vector2
---@field ownerBodyAnchor Vector2
---@field otherBodyAnchor Vector2
---@field ratio number
ConstraintPulley2D = {}

---@param groundAnchor Vector2
---@return nil
function ConstraintPulley2D:SetOwnerBodyGroundAnchor(groundAnchor) end

---@param groundAnchor Vector2
---@return nil
function ConstraintPulley2D:SetOtherBodyGroundAnchor(groundAnchor) end

---@param anchor Vector2
---@return nil
function ConstraintPulley2D:SetOwnerBodyAnchor(anchor) end

---@param anchor Vector2
---@return nil
function ConstraintPulley2D:SetOtherBodyAnchor(anchor) end

---@param ratio number
---@return nil
function ConstraintPulley2D:SetRatio(ratio) end

---@return Vector2
function ConstraintPulley2D:GetOwnerBodyGroundAnchor() end

---@return Vector2
function ConstraintPulley2D:GetOtherBodyGroundAnchor() end

---@return Vector2
function ConstraintPulley2D:GetOwnerBodyAnchor() end

---@return Vector2
function ConstraintPulley2D:GetOtherBodyAnchor() end

---@return number
function ConstraintPulley2D:GetRatio() end

