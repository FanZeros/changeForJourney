---@meta

--- Auto-generated from Urho2D/ConstraintRope2D

---@class ConstraintRope2D : Constraint2D
---@field ownerBodyAnchor Vector2
---@field otherBodyAnchor Vector2
---@field maxLength number
ConstraintRope2D = {}

---@param anchor Vector2
---@return nil
function ConstraintRope2D:SetOwnerBodyAnchor(anchor) end

---@param anchor Vector2
---@return nil
function ConstraintRope2D:SetOtherBodyAnchor(anchor) end

---@param maxLength number
---@return nil
function ConstraintRope2D:SetMaxLength(maxLength) end

---@return Vector2
function ConstraintRope2D:GetOwnerBodyAnchor() end

---@return Vector2
function ConstraintRope2D:GetOtherBodyAnchor() end

---@return number
function ConstraintRope2D:GetMaxLength() end

