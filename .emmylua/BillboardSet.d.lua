---@meta

--- Auto-generated from Graphics/BillboardSet

---@class Billboard
---@field position Vector3
---@field size Vector2
---@field uv Rect
---@field color Color
---@field rotation number
---@field anchor Vector2
---@field enabled boolean
Billboard = {}


---@class BillboardSet : Drawable
---@field material Material
---@field numBillboards integer
---@field relative boolean
---@field scaled boolean
---@field sorted boolean
---@field fixedScreenSize boolean
---@field faceCameraMode FaceCameraMode
---@field minAngle number
---@field animationLodBias number
BillboardSet = {}

---@param material Material
---@return nil
function BillboardSet:SetMaterial(material) end

---@param num integer
---@return nil
function BillboardSet:SetNumBillboards(num) end

---@param enable boolean
---@return nil
function BillboardSet:SetRelative(enable) end

---@param enable boolean
---@return nil
function BillboardSet:SetScaled(enable) end

---@param enable boolean
---@return nil
function BillboardSet:SetSorted(enable) end

---@param enable boolean
---@return nil
function BillboardSet:SetFixedScreenSize(enable) end

---@param mode FaceCameraMode
---@return nil
function BillboardSet:SetFaceCameraMode(mode) end

---@param angle number
---@return nil
function BillboardSet:SetMinAngle(angle) end

---@param bias number
---@return nil
function BillboardSet:SetAnimationLodBias(bias) end

---@return nil
function BillboardSet:Commit() end

---@return Material
function BillboardSet:GetMaterial() end

---@return integer
function BillboardSet:GetNumBillboards() end

---@param index integer
---@return Billboard
function BillboardSet:GetBillboard(index) end

---@return boolean
function BillboardSet:IsRelative() end

---@return boolean
function BillboardSet:IsScaled() end

---@return boolean
function BillboardSet:IsSorted() end

---@return boolean
function BillboardSet:IsFixedScreenSize() end

---@return FaceCameraMode
function BillboardSet:GetFaceCameraMode() end

---@return number
function BillboardSet:GetMinAngle() end

---@return number
function BillboardSet:GetAnimationLodBias() end

