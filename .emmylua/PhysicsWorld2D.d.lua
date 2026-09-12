---@meta

--- Auto-generated from Urho2D/PhysicsWorld2D

---@class PhysicsRaycastResult2D
---@overload fun(): PhysicsRaycastResult2D
---@field position Vector2
---@field normal Vector2
---@field distance number
---@field body RigidBody2D
PhysicsRaycastResult2D = {}

---@return PhysicsRaycastResult2D
function PhysicsRaycastResult2D.new() end


---@class PhysicsWorld2D : Component
---@field updateEnabled boolean
---@field drawShape boolean
---@field drawJoint boolean
---@field drawAabb boolean
---@field drawPair boolean
---@field drawCenterOfMass boolean
---@field allowSleeping boolean
---@field warmStarting boolean
---@field continuousPhysics boolean
---@field subStepping boolean
---@field autoClearForces boolean
---@field gravity Vector2
---@field velocityIterations integer
---@field positionIterations integer
PhysicsWorld2D = {}

---@return nil
function PhysicsWorld2D:DrawDebugGeometry() end

---@param enable boolean
---@return nil
function PhysicsWorld2D:SetUpdateEnabled(enable) end

---@param drawShape boolean
---@return nil
function PhysicsWorld2D:SetDrawShape(drawShape) end

---@param drawJoint boolean
---@return nil
function PhysicsWorld2D:SetDrawJoint(drawJoint) end

---@param drawAabb boolean
---@return nil
function PhysicsWorld2D:SetDrawAabb(drawAabb) end

---@param drawPair boolean
---@return nil
function PhysicsWorld2D:SetDrawPair(drawPair) end

---@param drawCenterOfMass boolean
---@return nil
function PhysicsWorld2D:SetDrawCenterOfMass(drawCenterOfMass) end

---@param enable boolean
---@return nil
function PhysicsWorld2D:SetAllowSleeping(enable) end

---@param enable boolean
---@return nil
function PhysicsWorld2D:SetWarmStarting(enable) end

---@param enable boolean
---@return nil
function PhysicsWorld2D:SetContinuousPhysics(enable) end

---@param enable boolean
---@return nil
function PhysicsWorld2D:SetSubStepping(enable) end

---@param gravity Vector2
---@return nil
function PhysicsWorld2D:SetGravity(gravity) end

---@param enable boolean
---@return nil
function PhysicsWorld2D:SetAutoClearForces(enable) end

---@param velocityIterations integer
---@return nil
function PhysicsWorld2D:SetVelocityIterations(velocityIterations) end

---@param positionIterations integer
---@return nil
function PhysicsWorld2D:SetPositionIterations(positionIterations) end

---@param startPoint Vector2
---@param endPoint Vector2
---@param collisionMask? integer
---@return PhysicsRaycastResult2D[]
function PhysicsWorld2D:Raycast(startPoint, endPoint, collisionMask) end

---@param startPoint Vector2
---@param endPoint Vector2
---@param collisionMask? integer
---@return PhysicsRaycastResult2D
function PhysicsWorld2D:RaycastSingle(startPoint, endPoint, collisionMask) end

---@param point Vector2
---@param collisionMask? integer
---@return RigidBody2D
function PhysicsWorld2D:GetRigidBody(point, collisionMask) end

---@param screenX integer
---@param screenY integer
---@param collisionMask? integer
---@return RigidBody2D
function PhysicsWorld2D:GetRigidBody(screenX, screenY, collisionMask) end

---@param aabb Rect
---@param collisionMask? integer
---@return RigidBody2D[]
function PhysicsWorld2D:GetRigidBodies(aabb, collisionMask) end

---@return boolean
function PhysicsWorld2D:IsUpdateEnabled() end

---@return boolean
function PhysicsWorld2D:GetDrawShape() end

---@return boolean
function PhysicsWorld2D:GetDrawJoint() end

---@return boolean
function PhysicsWorld2D:GetDrawAabb() end

---@return boolean
function PhysicsWorld2D:GetDrawPair() end

---@return boolean
function PhysicsWorld2D:GetDrawCenterOfMass() end

---@return boolean
function PhysicsWorld2D:GetAllowSleeping() end

---@return boolean
function PhysicsWorld2D:GetWarmStarting() end

---@return boolean
function PhysicsWorld2D:GetContinuousPhysics() end

---@return boolean
function PhysicsWorld2D:GetSubStepping() end

---@return boolean
function PhysicsWorld2D:GetAutoClearForces() end

---@return Vector2
function PhysicsWorld2D:GetGravity() end

---@return integer
function PhysicsWorld2D:GetVelocityIterations() end

---@return integer
function PhysicsWorld2D:GetPositionIterations() end

