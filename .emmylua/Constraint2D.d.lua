---@meta

--- Auto-generated from Urho2D/Constraint2D

---@class Constraint2D : Component
---@field ownerBody RigidBody2D
---@field otherBody RigidBody2D
---@field collideConnected boolean
Constraint2D = {}

---@param body RigidBody2D
---@return nil
function Constraint2D:SetOtherBody(body) end

---@param collideConnected boolean
---@return nil
function Constraint2D:SetCollideConnected(collideConnected) end

---@return RigidBody2D
function Constraint2D:GetOwnerBody() end

---@return RigidBody2D
function Constraint2D:GetOtherBody() end

---@return boolean
function Constraint2D:GetCollideConnected() end

