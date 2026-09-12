---@meta

--- Auto-generated from Physics/PhysicsWorld

---@class PhysicsRaycastResult
---@overload fun(): PhysicsRaycastResult
---@field position Vector3
---@field normal Vector3
---@field distance number
---@field hitFraction number
---@field body RigidBody
PhysicsRaycastResult = {}

---@return PhysicsRaycastResult
function PhysicsRaycastResult.new() end


---@class PhysicsWorld : Component
---@overload fun(): PhysicsWorld
---@field gravity Vector3
---@field maxSubSteps integer
---@field numIterations integer
---@field updateEnabled boolean
---@field interpolation boolean
---@field internalEdge boolean
---@field splitImpulse boolean
---@field fps integer
---@field maxNetworkAngularVelocity number
PhysicsWorld = {}

---@return PhysicsWorld
function PhysicsWorld.new() end

---@param timeStep number
---@return nil
function PhysicsWorld:Update(timeStep) end

---@return nil
function PhysicsWorld:UpdateCollisions() end

---@param fps integer
---@return nil
function PhysicsWorld:SetFps(fps) end

---@param gravity Vector3
---@return nil
function PhysicsWorld:SetGravity(gravity) end

---@param num integer
---@return nil
function PhysicsWorld:SetMaxSubSteps(num) end

---@param num integer
---@return nil
function PhysicsWorld:SetNumIterations(num) end

---@param enable boolean
---@return nil
function PhysicsWorld:SetUpdateEnabled(enable) end

---@param enable boolean
---@return nil
function PhysicsWorld:SetInterpolation(enable) end

---@param enable boolean
---@return nil
function PhysicsWorld:SetInternalEdge(enable) end

---@param enable boolean
---@return nil
function PhysicsWorld:SetSplitImpulse(enable) end

---@param velocity number
---@return nil
function PhysicsWorld:SetMaxNetworkAngularVelocity(velocity) end

---@param ray Ray
---@param maxDistance number
---@param collisionMask? integer
---@return PhysicsRaycastResult[]
function PhysicsWorld:Raycast(ray, maxDistance, collisionMask) end

---@param ray Ray
---@param maxDistance number
---@param collisionMask? integer
---@return PhysicsRaycastResult
function PhysicsWorld:RaycastSingle(ray, maxDistance, collisionMask) end

---@param ray Ray
---@param maxDistance number
---@param segmentDistance number
---@param collisionMask? integer
---@param overlapDistance? number
---@return PhysicsRaycastResult
function PhysicsWorld:RaycastSingleSegmented(ray, maxDistance, segmentDistance, collisionMask, overlapDistance) end

---@param ray Ray
---@param radius number
---@param maxDistance number
---@param collisionMask? integer
---@return PhysicsRaycastResult
function PhysicsWorld:SphereCast(ray, radius, maxDistance, collisionMask) end

---@param shape CollisionShape
---@param startPos Vector3
---@param startRot Quaternion
---@param endPos Vector3
---@param endRot Quaternion
---@param collisionMask? integer
---@return PhysicsRaycastResult
function PhysicsWorld:ConvexCast(shape, startPos, startRot, endPos, endRot, collisionMask) end

---@param sphere Sphere
---@param collisionMask? integer
---@return RigidBody[]
function PhysicsWorld:GetRigidBodies(sphere, collisionMask) end

---@param box BoundingBox
---@param collisionMask? integer
---@return RigidBody[]
function PhysicsWorld:GetRigidBodies(box, collisionMask) end

---@param body RigidBody
---@return RigidBody[]
function PhysicsWorld:GetRigidBodies(body) end

---@param body RigidBody
---@return RigidBody[]
function PhysicsWorld:GetCollidingBodies(body) end

---@param depthTest boolean
---@return nil
function PhysicsWorld:DrawDebugGeometry(depthTest) end

---@param model Model
---@return nil
function PhysicsWorld:RemoveCachedGeometry(model) end

---@return Vector3
function PhysicsWorld:GetGravity() end

---@return integer
function PhysicsWorld:GetMaxSubSteps() end

---@return integer
function PhysicsWorld:GetNumIterations() end

---@return boolean
function PhysicsWorld:IsUpdateEnabled() end

---@return boolean
function PhysicsWorld:GetInterpolation() end

---@return boolean
function PhysicsWorld:GetInternalEdge() end

---@return boolean
function PhysicsWorld:GetSplitImpulse() end

---@return integer
function PhysicsWorld:GetFps() end

---@return number
function PhysicsWorld:GetMaxNetworkAngularVelocity() end

