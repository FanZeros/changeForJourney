---@meta

--- Auto-generated from Urho2D/CollisionShape2D

---@class CollisionShape2D : Component
---@field trigger boolean
---@field categoryBits integer
---@field maskBits integer
---@field groupIndex integer
---@field density number
---@field friction number
---@field restitution number
---@field mass number
---@field inertia number
---@field massCenter Vector2
CollisionShape2D = {}

---@param trigger boolean
---@return nil
function CollisionShape2D:SetTrigger(trigger) end

---@param categoryBits integer
---@return nil
function CollisionShape2D:SetCategoryBits(categoryBits) end

---@param maskBits integer
---@return nil
function CollisionShape2D:SetMaskBits(maskBits) end

---@param groupIndex integer
---@return nil
function CollisionShape2D:SetGroupIndex(groupIndex) end

---@param density number
---@return nil
function CollisionShape2D:SetDensity(density) end

---@param friction number
---@return nil
function CollisionShape2D:SetFriction(friction) end

---@param restitution number
---@return nil
function CollisionShape2D:SetRestitution(restitution) end

---@return boolean
function CollisionShape2D:IsTrigger() end

---@return integer
function CollisionShape2D:GetCategoryBits() end

---@return integer
function CollisionShape2D:GetMaskBits() end

---@return integer
function CollisionShape2D:GetGroupIndex() end

---@return number
function CollisionShape2D:GetDensity() end

---@return number
function CollisionShape2D:GetFriction() end

---@return number
function CollisionShape2D:GetRestitution() end

---@return number
function CollisionShape2D:GetMass() end

---@return number
function CollisionShape2D:GetInertia() end

---@return Vector2
function CollisionShape2D:GetMassCenter() end

