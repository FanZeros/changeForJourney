---@meta

--- Auto-generated from Animation/BlendSpace

---@class AnimationBlendWeight
---@overload fun(path: string, w: number, s?: number): AnimationBlendWeight
---@overload fun(): AnimationBlendWeight
---@field animationPath string
---@field weight number
---@field speed number
AnimationBlendWeight = {}

---@overload fun(self: AnimationBlendWeight, path: string, w: number, s?: number): AnimationBlendWeight
---@overload fun(path: string, w: number, s?: number): AnimationBlendWeight
---@return AnimationBlendWeight
function AnimationBlendWeight.new() end


---@class BlendSpaceBase : Object
---@field blendSpaceName string
BlendSpaceBase = {}

---@return string
function BlendSpaceBase:GetBlendSpaceName() end

---@return string
function BlendSpaceBase:GetBlendSpaceType() end


---@class BlendSpaceResource : Resource
BlendSpaceResource = {}

---@return BlendSpaceBase
function BlendSpaceResource:GetBlendSpace() end


---@class BlendSpace1D : BlendSpaceBase
---@field parameterName string
BlendSpace1D = {}

---@return string
function BlendSpace1D:GetParameterName() end

---@param value number
---@param animation string
---@param speed? number
---@return nil
function BlendSpace1D:AddPoint(value, animation, speed) end

---@return nil
function BlendSpace1D:ClearPoints() end


---@class BlendSpace2D : BlendSpaceBase
---@field parameterNameX string
---@field parameterNameY string
BlendSpace2D = {}

---@return string
function BlendSpace2D:GetParameterNameX() end

---@return string
function BlendSpace2D:GetParameterNameY() end

---@param x number
---@param y number
---@param animation string
---@param speed? number
---@return nil
function BlendSpace2D:AddPoint(x, y, animation, speed) end

---@return nil
function BlendSpace2D:ClearPoints() end

---@return nil
function BlendSpace2D:BuildTriangulation() end

