---@meta

--- Auto-generated from Physics/CollisionShape

---@alias ShapeType
---| integer # ShapeType enum values

---@type ShapeType
SHAPE_BOX = 0
---@type ShapeType
SHAPE_SPHERE = 1
---@type ShapeType
SHAPE_STATICPLANE = 2
---@type ShapeType
SHAPE_CYLINDER = 3
---@type ShapeType
SHAPE_CAPSULE = 4
---@type ShapeType
SHAPE_CONE = 5
---@type ShapeType
SHAPE_TRIANGLEMESH = 6
---@type ShapeType
SHAPE_CONVEXHULL = 7
---@type ShapeType
SHAPE_TERRAIN = 8

---@class CollisionShape : Component
---@overload fun(): CollisionShape
---@field physicsWorld PhysicsWorld
---@field shapeType ShapeType
---@field size Vector3
---@field position Vector3
---@field rotation Quaternion
---@field margin number
---@field model Model
---@field lodLevel integer
---@field worldBoundingBox BoundingBox
---@field modelAttr ResourceRef
CollisionShape = {}

---@return CollisionShape
function CollisionShape.new() end

---@param size Vector3
---@param position? Vector3
---@param rotation? Quaternion
---@return nil
function CollisionShape:SetBox(size, position, rotation) end

---@param diameter number
---@param position? Vector3
---@param rotation? Quaternion
---@return nil
function CollisionShape:SetSphere(diameter, position, rotation) end

---@param position? Vector3
---@param rotation? Quaternion
---@return nil
function CollisionShape:SetStaticPlane(position, rotation) end

---@param diameter number
---@param height number
---@param position? Vector3
---@param rotation? Quaternion
---@return nil
function CollisionShape:SetCylinder(diameter, height, position, rotation) end

---@param diameter number
---@param height number
---@param position? Vector3
---@param rotation? Quaternion
---@return nil
function CollisionShape:SetCapsule(diameter, height, position, rotation) end

---@param diameter number
---@param height number
---@param position? Vector3
---@param rotation? Quaternion
---@return nil
function CollisionShape:SetCone(diameter, height, position, rotation) end

---@param model Model
---@param lodLevel? integer
---@param scale? Vector3
---@param position? Vector3
---@param rotation? Quaternion
---@return nil
function CollisionShape:SetTriangleMesh(model, lodLevel, scale, position, rotation) end

---@param custom CustomGeometry
---@param scale? Vector3
---@param position? Vector3
---@param rotation? Quaternion
---@return nil
function CollisionShape:SetCustomTriangleMesh(custom, scale, position, rotation) end

---@param model Model
---@param lodLevel? integer
---@param scale? Vector3
---@param position? Vector3
---@param rotation? Quaternion
---@return nil
function CollisionShape:SetConvexHull(model, lodLevel, scale, position, rotation) end

---@param custom CustomGeometry
---@param scale? Vector3
---@param position? Vector3
---@param rotation? Quaternion
---@return nil
function CollisionShape:SetCustomConvexHull(custom, scale, position, rotation) end

---@param lodLevel? integer
---@return nil
function CollisionShape:SetTerrain(lodLevel) end

---@param type ShapeType
---@return nil
function CollisionShape:SetShapeType(type) end

---@param size Vector3
---@return nil
function CollisionShape:SetSize(size) end

---@param position Vector3
---@return nil
function CollisionShape:SetPosition(position) end

---@param rotation Quaternion
---@return nil
function CollisionShape:SetRotation(rotation) end

---@param position Vector3
---@param rotation Quaternion
---@return nil
function CollisionShape:SetTransform(position, rotation) end

---@param margin number
---@return nil
function CollisionShape:SetMargin(margin) end

---@param model Model
---@return nil
function CollisionShape:SetModel(model) end

---@param lodLevel integer
---@return nil
function CollisionShape:SetLodLevel(lodLevel) end

---@return PhysicsWorld
function CollisionShape:GetPhysicsWorld() end

---@return ShapeType
function CollisionShape:GetShapeType() end

---@return Vector3
function CollisionShape:GetSize() end

---@return Vector3
function CollisionShape:GetPosition() end

---@return Quaternion
function CollisionShape:GetRotation() end

---@return number
function CollisionShape:GetMargin() end

---@return Model
function CollisionShape:GetModel() end

---@return integer
function CollisionShape:GetLodLevel() end

---@return BoundingBox
function CollisionShape:GetWorldBoundingBox() end

