---@meta

--- Auto-generated from Urho2D/ConstraintDistance2D

---@class ConstraintDistance2D : Constraint2D
---@field ownerBodyAnchor Vector2
---@field otherBodyAnchor Vector2
---@field frequencyHz number
---@field dampingRatio number
---@field length number
ConstraintDistance2D = {}

---@param anchor Vector2
---@return nil
function ConstraintDistance2D:SetOwnerBodyAnchor(anchor) end

---@param anchor Vector2
---@return nil
function ConstraintDistance2D:SetOtherBodyAnchor(anchor) end

---@param frequencyHz number
---@return nil
function ConstraintDistance2D:SetFrequencyHz(frequencyHz) end

---@param dampingRatio number
---@return nil
function ConstraintDistance2D:SetDampingRatio(dampingRatio) end

---@param length number
---@return nil
function ConstraintDistance2D:SetLength(length) end

---@return Vector2
function ConstraintDistance2D:GetOwnerBodyAnchor() end

---@return Vector2
function ConstraintDistance2D:GetOtherBodyAnchor() end

---@return number
function ConstraintDistance2D:GetFrequencyHz() end

---@return number
function ConstraintDistance2D:GetDampingRatio() end

---@return number
function ConstraintDistance2D:GetLength() end

