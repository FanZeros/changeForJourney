---@meta

--- Auto-generated from Graphics/Camera


---@alias Handedness
---| integer # Handedness enum values

---@type Handedness
HANDEDNESS_LH = 0
---@type Handedness
HANDEDNESS_RH = 1

---@class Camera : Component
---@field farClip number
---@field nearClip number
---@field fov number
---@field orthoSize number
---@field aspectRatio number
---@field zoom number
---@field lodBias number
---@field viewMask integer
---@field viewOverrideFlags ViewOverride
---@field fillMode FillMode
---@field orthographic boolean
---@field autoAspectRatio boolean
---@field frustum Frustum
---@field projection Matrix4
---@field gpuProjection Matrix4
---@field view Matrix3x4
---@field halfViewSize number
---@field viewSpaceFrustum Frustum
---@field projectionOffset Vector2
---@field useReflection boolean
---@field reflectionPlane Plane
---@field useClipping boolean
---@field clipPlane Plane
---@field reverseZ boolean
---@field handedness Handedness
---@field projectionValid boolean
---@field effectiveWorldTransform Matrix3x4
Camera = {}

---@param nearClip number
---@return nil
function Camera:SetNearClip(nearClip) end

---@param farClip number
---@return nil
function Camera:SetFarClip(farClip) end

---@param fov number
---@return nil
function Camera:SetFov(fov) end

---@param orthoSize number
---@return nil
function Camera:SetOrthoSize(orthoSize) end

---@param orthoSize Vector2
---@return nil
function Camera:SetOrthoSize(orthoSize) end

---@param aspectRatio number
---@return nil
function Camera:SetAspectRatio(aspectRatio) end

---@param mode FillMode
---@return nil
function Camera:SetFillMode(mode) end

---@param zoom number
---@return nil
function Camera:SetZoom(zoom) end

---@param bias number
---@return nil
function Camera:SetLodBias(bias) end

---@param mask integer
---@return nil
function Camera:SetViewMask(mask) end

---@param flags ViewOverride
---@return nil
function Camera:SetViewOverrideFlags(flags) end

---@param enable boolean
---@return nil
function Camera:SetOrthographic(enable) end

---@param enable boolean
---@return nil
function Camera:SetAutoAspectRatio(enable) end

---@param offset Vector2
---@return nil
function Camera:SetProjectionOffset(offset) end

---@param enable boolean
---@return nil
function Camera:SetUseReflection(enable) end

---@param reflectionPlane Plane
---@return nil
function Camera:SetReflectionPlane(reflectionPlane) end

---@param enable boolean
---@return nil
function Camera:SetUseClipping(enable) end

---@param clipPlane Plane
---@return nil
function Camera:SetClipPlane(clipPlane) end

---@param projection Matrix4
---@return nil
function Camera:SetProjection(projection) end

---@param enable boolean
---@return nil
function Camera:SetReverseZ(enable) end

---@param handedness Handedness
---@return nil
function Camera:SetHandedness(handedness) end

---@return Handedness
function Camera:GetHandedness() end

---@return number
function Camera:GetFarClip() end

---@return number
function Camera:GetNearClip() end

---@return number
function Camera:GetFov() end

---@return number
function Camera:GetOrthoSize() end

---@return number
function Camera:GetAspectRatio() end

---@return number
function Camera:GetZoom() end

---@return number
function Camera:GetLodBias() end

---@return integer
function Camera:GetViewMask() end

---@return ViewOverride
function Camera:GetViewOverrideFlags() end

---@return FillMode
function Camera:GetFillMode() end

---@return boolean
function Camera:IsOrthographic() end

---@return boolean
function Camera:GetAutoAspectRatio() end

---@return Frustum
function Camera:GetFrustum() end

---@return Matrix4
function Camera:GetProjection() end

---@return Matrix4
function Camera:GetGPUProjection() end

---@return Matrix3x4
function Camera:GetView() end

---@param near Vector3
---@param far Vector3
---@return nil
function Camera:GetFrustumSize(near, far) end

---@return number
function Camera:GetHalfViewSize() end

---@param nearClip number
---@param farClip number
---@return Frustum
function Camera:GetSplitFrustum(nearClip, farClip) end

---@return Frustum
function Camera:GetViewSpaceFrustum() end

---@param nearClip number
---@param farClip number
---@return Frustum
function Camera:GetViewSpaceSplitFrustum(nearClip, farClip) end

---@param x number
---@param y number
---@return Ray
function Camera:GetScreenRay(x, y) end

---@param worldPos Vector3
---@return Vector2
function Camera:WorldToScreenPoint(worldPos) end

---@param screenPos Vector3
---@return Vector3
function Camera:ScreenToWorldPoint(screenPos) end

---@return Vector2
function Camera:GetProjectionOffset() end

---@return boolean
function Camera:GetUseReflection() end

---@return Plane
function Camera:GetReflectionPlane() end

---@return boolean
function Camera:GetUseClipping() end

---@return Plane
function Camera:GetClipPlane() end

---@return boolean
function Camera:GetReverseZ() end

---@return boolean
function Camera:UseReverseZ() end

---@return number
function Camera:GetFarthestDepthValue() end

---@param worldPos Vector3
---@return number
function Camera:GetDistance(worldPos) end

---@param worldPos Vector3
---@return number
function Camera:GetDistanceSquared(worldPos) end

---@param distance number
---@param scale number
---@param bias number
---@return number
function Camera:GetLodDistance(distance, scale, bias) end

---@return boolean
function Camera:IsProjectionValid() end

---@return Matrix3x4
function Camera:GetEffectiveWorldTransform() end


-- Global variables
---@type integer
VO_NONE = nil
---@type integer
VO_MATERIAL_QUALITY = nil
---@type integer
VO_DISABLE_SHADOWS = nil
---@type integer
VO_DISABLE_OCCLUSION = nil
