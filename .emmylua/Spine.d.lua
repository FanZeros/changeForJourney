---@meta

--- Auto-generated from UI/Spine

---@class SpineBone : RefCounted
SpineBone = {}

---@return boolean
function SpineBone:IsValid() end

---@return string
function SpineBone:GetName() end

---@return number
function SpineBone:GetX() end

---@return number
function SpineBone:GetY() end

---@param x number
---@return nil
function SpineBone:SetX(x) end

---@param y number
---@return nil
function SpineBone:SetY(y) end

---@return number
function SpineBone:GetRotation() end

---@param degrees number
---@return nil
function SpineBone:SetRotation(degrees) end

---@return number
function SpineBone:GetScaleX() end

---@return number
function SpineBone:GetScaleY() end

---@param sx number
---@return nil
function SpineBone:SetScaleX(sx) end

---@param sy number
---@return nil
function SpineBone:SetScaleY(sy) end

---@return number
function SpineBone:GetWorldX() end

---@return number
function SpineBone:GetWorldY() end

---@return number
function SpineBone:GetWorldRotation() end

---@return number
function SpineBone:GetWorldScaleX() end

---@return number
function SpineBone:GetWorldScaleY() end

---@param valid boolean
---@return nil
function SpineBone:SetAppliedValid(valid) end

---@return boolean
function SpineBone:IsActive() end

---@return SpineBone
function SpineBone:GetParent() end

--- local lx, ly = bone:WorldToLocal(worldX, worldY)
---@param worldX number
---@param worldY number
---@return nil
function SpineBone:WorldToLocal(worldX, worldY) end

--- local wx, wy = bone:LocalToWorld(localX, localY)
---@param localX number
---@param localY number
---@return nil
function SpineBone:LocalToWorld(localX, localY) end


---@class SpineSlot : RefCounted
SpineSlot = {}

---@return boolean
function SpineSlot:IsValid() end

---@return string
function SpineSlot:GetName() end

---@return SpineBone
function SpineSlot:GetBone() end

---@return boolean
function SpineSlot:HasDarkColor() end

--- local r, g, b, a = slot:GetColor()
---@return nil
function SpineSlot:GetColor() end

--- slot:SetColor(r, g, b, a) — values 0.0-1.0
---@param r number
---@param g number
---@param b number
---@param a number
---@return nil
function SpineSlot:SetColor(r, g, b, a) end

--- local r, g, b = slot:GetDarkColor()
---@return nil
function SpineSlot:GetDarkColor() end

--- slot:SetDarkColor(r, g, b) — values 0.0-1.0
---@param r number
---@param g number
---@param b number
---@return nil
function SpineSlot:SetDarkColor(r, g, b) end

---@return nil
function SpineSlot:SetToSetupPose() end


---@class SpineInstance : Object
SpineInstance = {}

---@param skeletonPath string
---@return boolean
function SpineInstance:Load(skeletonPath) end

---@return nil
function SpineInstance:Unload() end

---@param dt number
---@return nil
function SpineInstance:Update(dt) end

---@return nil
function SpineInstance:UpdateWorldTransform() end

---@param trackIndex integer
---@param name string
---@param loop boolean
---@return boolean
function SpineInstance:SetAnimation(trackIndex, name, loop) end

---@param trackIndex integer
---@param name string
---@param loop boolean
---@param delay number
---@return boolean
function SpineInstance:AddAnimation(trackIndex, name, loop, delay) end

---@param trackIndex integer
---@param mixDuration number
---@return nil
function SpineInstance:SetEmptyAnimation(trackIndex, mixDuration) end

---@param trackIndex integer
---@param mixDuration number
---@param delay number
---@return nil
function SpineInstance:AddEmptyAnimation(trackIndex, mixDuration, delay) end

---@param trackIndex integer
---@return nil
function SpineInstance:ClearTrack(trackIndex) end

---@return nil
function SpineInstance:ClearTracks() end

---@param duration number
---@return nil
function SpineInstance:SetDefaultMix(duration) end

---@param speed number
---@return nil
function SpineInstance:SetSpeed(speed) end

---@return number
function SpineInstance:GetSpeed() end

---@param timeScale number
---@return nil
function SpineInstance:SetTimeScale(timeScale) end

---@return number
function SpineInstance:GetTimeScale() end

---@param flip boolean
---@return nil
function SpineInstance:SetFlipX(flip) end

---@param flip boolean
---@return nil
function SpineInstance:SetFlipY(flip) end

---@param skinName string
---@return nil
function SpineInstance:SetSkin(skinName) end

---@return nil
function SpineInstance:SetToSetupPose() end

---@return nil
function SpineInstance:SetBonesToSetupPose() end

---@return nil
function SpineInstance:SetSlotsToSetupPose() end

---@param x number
---@param y number
---@return nil
function SpineInstance:SetPosition(x, y) end

---@param scaleX number
---@param scaleY number
---@return nil
function SpineInstance:SetScale(scaleX, scaleY) end

---@param name string
---@return SpineBone
function SpineInstance:FindBone(name) end

---@param name string
---@return SpineSlot
function SpineInstance:FindSlot(name) end

--- instance:SetColor(r, g, b, a) — values 0.0-1.0
---@param r number
---@param g number
---@param b number
---@param a number
---@return nil
function SpineInstance:SetColor(r, g, b, a) end

--- local r, g, b, a = instance:GetColor()
---@return nil
function SpineInstance:GetColor() end

---@return number
function SpineInstance:GetDataWidth() end

---@return number
function SpineInstance:GetDataHeight() end

---@return number
function SpineInstance:GetDataX() end

---@return number
function SpineInstance:GetDataY() end

---@return boolean
function SpineInstance:IsLoaded() end

---@param trackIndex integer
---@return boolean
function SpineInstance:IsAnimationComplete(trackIndex) end

---@param trackIndex integer
---@return number
function SpineInstance:GetTrackTime(trackIndex) end

---@param trackIndex integer
---@return number
function SpineInstance:GetAnimationDuration(trackIndex) end

---@param trackIndex integer
---@return number
function SpineInstance:GetTrackAlpha(trackIndex) end

---@param trackIndex integer
---@param alpha number
---@return nil
function SpineInstance:SetTrackAlpha(trackIndex, alpha) end

---@param pma boolean
---@return nil
function SpineInstance:SetPremultipliedAlpha(pma) end

---@return boolean
function SpineInstance:IsPremultipliedAlpha() end

---@return string[]
function SpineInstance:GetAnimationNames() end

---@return string[]
function SpineInstance:GetSkinNames() end

---@return string[]
function SpineInstance:GetBoneNames() end

---@return string[]
function SpineInstance:GetSlotNames() end

---@param slotName string
---@param attachmentName string
---@return nil
function SpineInstance:SetAttachment(slotName, attachmentName) end

---@param fromAnim string
---@param toAnim string
---@param duration number
---@return nil
function SpineInstance:SetMix(fromAnim, toAnim, duration) end

--- instance:SetCompleteListener(function(trackIndex, animName) end)
---@param fn lua_Function
---@return nil
function SpineInstance:SetCompleteListener(fn) end

--- instance:SetStartListener(function(trackIndex, animName) end)
---@param fn lua_Function
---@return nil
function SpineInstance:SetStartListener(fn) end

--- instance:SetEndListener(function(trackIndex, animName) end)
---@param fn lua_Function
---@return nil
function SpineInstance:SetEndListener(fn) end

--- instance:SetDisposeListener(function(trackIndex, animName) end)
---@param fn lua_Function
---@return nil
function SpineInstance:SetDisposeListener(fn) end

--- instance:SetEventListener(function(trackIndex, eventName, intVal, floatVal, strVal) end)
---@param fn lua_Function
---@return nil
function SpineInstance:SetEventListener(fn) end


-- Global functions
--- Create a new SpineInstance.
---@param ctx NVGContextWrapper NanoVG context (used only for context acquisition, not stored)
---@return SpineInstance # SpineInstance object
function nvgSpineCreate(ctx) end

--- Render a SpineInstance into the NanoVG command queue.
--- Must be called between nvgBeginFrame/nvgEndFrame.
---@param ctx NVGContextWrapper NanoVG context
---@param instance SpineInstance SpineInstance to render
---@return nil
function nvgSpineRender(ctx, instance) end

--- Get NanoVG render stats from last frame.
---@param ctx NVGContextWrapper
---@return integer # drawCalls, vertexCount
function nvgGetRenderStats(ctx) end
