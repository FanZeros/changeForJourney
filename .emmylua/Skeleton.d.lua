---@meta

--- Auto-generated from Graphics/Skeleton

---@class Bone
---@overload fun(): Bone
---@field name string
---@field nameHash StringHash|string
---@field parentIndex integer
---@field initialPosition Vector3
---@field initialRotation Quaternion
---@field initialScale Vector3
---@field offsetMatrix Matrix3x4
---@field animated boolean
---@field collisionMask number -- unsigned char
---@field radius number
---@field boundingBox BoundingBox
---@field node Node
Bone = {}

---@return Bone
function Bone.new() end

---@return Matrix3x4
function Bone:GetFinalWorldTransform() end


---@class Skeleton
---@field numBones integer
---@field rootBone Bone
Skeleton = {}

---@return integer
function Skeleton:GetNumBones() end

---@return Bone
function Skeleton:GetRootBone() end

---@param name string
---@return Bone
function Skeleton:GetBone(name) end

---@param index integer
---@return Bone
function Skeleton:GetBone(index) end

---@param boneName string
---@return integer
function Skeleton:GetBoneIndex(boneName) end

---@param bone Bone
---@return integer
function Skeleton:GetBoneIndex(bone) end

---@param bone Bone
---@return Bone
function Skeleton:GetBoneParent(bone) end

