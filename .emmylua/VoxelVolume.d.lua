---@meta

--- Auto-generated from VoxelPhysics/VoxelVolume

---@alias VoxelCollisionShapeType
---| integer # VoxelCollisionShapeType enum values

---@type VoxelCollisionShapeType
--- Derive collision directly from voxel occupancy.
VOXEL_COLLISION_SHAPE_AUTO = 0
---@type VoxelCollisionShapeType
--- Use an authored analytic box.
VOXEL_COLLISION_SHAPE_BOX = 1
---@type VoxelCollisionShapeType
--- Use an authored analytic sphere.
VOXEL_COLLISION_SHAPE_SPHERE = 2
---@type VoxelCollisionShapeType
--- Use an authored analytic capsule.
VOXEL_COLLISION_SHAPE_CAPSULE = 3
---@type VoxelCollisionShapeType
--- Use an authored analytic cylinder.
VOXEL_COLLISION_SHAPE_CYLINDER = 4

---@class VoxelVolume : Component
---@field clientBodyMode integer
---@field contentReady boolean
---@field remoteReplica boolean
---@field voxelSize number
---@field destructible boolean
---@field evictable boolean
---@field density number
---@field mass number
---@field solidVolume number
---@field buoyancy number
---@field comOffset Vector3
---@field linearVelocity Vector3
---@field angularVelocity Vector3
---@field linearDamping number
---@field angularDamping number
---@field gravityFactor number
---@field useGravity boolean
---@field friction number
---@field restitution number
---@field collisionLayer integer
---@field collisionMask integer
---@field collisionGroup integer
---@field volumeId integer
---@field collisionShapeType VoxelCollisionShapeType
---@field collisionShapeSize Vector3
---@field collisionShapeOffset Vector3
---@field collisionShapeRotation Quaternion
---@field assembly VoxelAssembly
---@field assemblyRootVolume VoxelVolume
---@field assemblyRoot boolean
---@field ccdEnabled boolean
---@field grid VoxelGrid
---@field voxelModel VoxelModel Writable: assignment swaps the model and re-bakes in place.
---@field voxelModelName string
---@field material Material
---@field vertexCount integer
---@field geometryDirty boolean
---@field static boolean
---@field tumbling boolean
---@field reSettling boolean
VoxelVolume = {}

--- True once complete authoritative content has been installed; later diffs keep it ready.
---@return boolean
function VoxelVolume:IsContentReady() end

---@return boolean
function VoxelVolume:IsRemoteReplica() end

--- CollisionProxy is the default. Simulated is reserved and rejected in Phase 1.
---@param mode integer
---@return nil
function VoxelVolume:SetClientBodyMode(mode) end

---@return integer
function VoxelVolume:GetClientBodyMode() end

--- Allocate the grid. Voxels start empty; fill them and then call MarkGeometryDirty.
--- Allocation happens here, inside the engine module, because grid storage grows through
--- engine code and freeing it from another binary would hit the wrong heap — see
--- docs/gotchas/development-gotchas.md.
---@param dimX integer
---@param dimY integer
---@param dimZ integer
---@return nil
function VoxelVolume:SetDimensions(dimX, dimY, dimZ) end

--- Set the voxel edge length in world units.
---@param size number
---@return nil
function VoxelVolume:SetVoxelSize(size) end

--- Return the voxel edge length in world units.
---@return number
function VoxelVolume:GetVoxelSize() end

--- Mutable access so damage and fragment extraction can write voxels.
--- VoxelGrid tracks content and occupancy revisions itself; callers still
--- mark geometry dirty to schedule render work after a direct edit.
---@return VoxelGrid
function VoxelVolume:GetGrid() end

--- Request a surface rebuild. Coalesced: several hits in one frame cost one remesh.
--- Also clears any coalesced DDA damage box — a full-dirty request overrides it.
---@return nil
function VoxelVolume:MarkGeometryDirty() end

--- Mark only the chunks overlapping an inclusive voxel region (plus one voxel of margin —
--- removing a voxel exposes faces of its NEIGHBOURS, which may live in the next chunk).
--- This is what keeps a blast from re-meshing an entire building.
---@param x0 integer
---@param y0 integer
---@param z0 integer
---@param x1 integer
---@param y1 integer
---@param z1 integer
---@return nil
function VoxelVolume:MarkRegionDirty(x0, y0, z0, x1, y1, z1) end

--- Return true if render geometry is waiting to be rebuilt.
---@return boolean
function VoxelVolume:IsGeometryDirty() end

--- Rebuild the render surface now. Normally driven by the world once per frame; exposed so
--- tests and tools can force it.
---@return nil
function VoxelVolume:RebuildGeometry() end

--- Set material.
---@param material Material
---@return nil
function VoxelVolume:SetMaterial(material) end

--- Return material.
---@return Material
function VoxelVolume:GetMaterial() end

--- Which palette bank this volume's grid bytes index (see the bank section in
--- VoxelPhysicsWorld.h). Serialized; default 0, so every pre-bank scene loads
--- unchanged. Set by the bake (bank chosen for the model) and inherited by fragments
--- and spall — a piece must keep meaning the same colours it meant on its parent.
--- Changing it on a live volume re-skins on the next rebuild (the default material is
--- per bank). Custom surface shaders sampling world:GetPaletteTexture() offset their rows by
--- bank * 4.
--- Effective palette domain, latched when the volume is adopted or baked.
---@return integer
function VoxelVolume:GetPaletteDomain() end

---@return integer
function VoxelVolume:GetPaletteBank() end

--- Set palette bank.
---@param bank integer
---@return nil
function VoxelVolume:SetPaletteBank(bank) end

--- Vertices in the current surface mesh. Zero means nothing has been built yet.
--- During a LOD transition this counts BOTH tables — the retired level still on
--- screen and the new one building — because both hold GPU buffers and the point of
--- this number is honest memory accounting.
---@return integer
function VoxelVolume:GetVertexCount() end

--- The level the current chunk table meshes at: level L covers cells of 2^L voxels
--- in groups of 32*2^L per axis (one whole 256^3 volume is a single group at level
--- 3). Uniform per volume — mixing levels inside one volume would open seams at
--- internal level boundaries that any-solid dilation only prevents ACROSS volumes,
--- and the target scale (a building per volume, far smaller than a ring's width)
--- never straddles rings anyway. Read-only from script because the world's ring pass owns it;
--- debug overlays and tests may inspect it.
---@return integer
function VoxelVolume:GetMeshLodLevel() end

--- Predicates alongside GetState because the Lua bindings cannot express a scoped enum —
--- every .pkg in this engine uses plain enums — and three named questions read better from
--- script than an integer compared against invented constants.
---@return boolean
function VoxelVolume:IsStatic() end

--- Return true if the volume is in the tumbling state.
---@return boolean
function VoxelVolume:IsTumbling() end

--- Return true if the volume is settling on its exact proxy before freezing.
---@return boolean
function VoxelVolume:IsReSettling() end

--- Set whether damage may modify this volume. Terrain usually clears this because world-point
--- damage cannot otherwise distinguish scenery from a target; without it a vehicle carrying
--- an impact probe digs a trench along its route.
---@param destructible boolean
---@return nil
function VoxelVolume:SetDestructible(destructible) end

--- Whether damage may remove voxels from this volume. True by default.
---@return boolean
function VoxelVolume:IsDestructible() end

--- Set whether the debris budget may delete this volume. Spall rubble starts evictable;
--- severed pieces inherit their parent's policy, so a fallen roof is not deleted to make room
--- for pebbles.
---@param evictable boolean
---@return nil
function VoxelVolume:SetEvictable(evictable) end

--- Whether the debris budget may delete this volume to make room. False by default.
---@return boolean
function VoxelVolume:IsEvictable() end

--- Set whether scene-load adoption builds a solver body. False creates a purely decorative
--- volume such as vehicle visual wheels: it renders but does not collide, avoiding a body that
--- would sit on suspension anchors and pin the car. Explicit FinalizeVolume still builds one.
---@param collidable boolean
---@return nil
function VoxelVolume:SetCollidable(collidable) end

--- Whether scene-load adoption gives this volume a solver body. True for everything except
--- purely decorative volumes — the canonical case is a vehicle's visual wheels, which ride
--- the chassis body and are posed from suspension telemetry: a body of their own would sit
--- exactly on the suspension anchors and the wheel rays would hit it at zero distance,
--- pinning the car (converted Teardown scenes, measured). Script-created volumes get this
--- for free by never calling FinalizeVolume; this attribute is the serialized equivalent.
--- An explicit FinalizeVolume/FinalizeVolumeAsDynamic call still builds a body — the flag
--- gates ADOPTION, not the API.
---@return boolean
function VoxelVolume:IsCollidable() end

--- Set density in kilograms per cubic metre for dynamic mass calculation. Fragments inherit
--- it from their parent.
---@param density number
---@return nil
function VoxelVolume:SetDensity(density) end

--- Density in kg/m^3, used for this volume's own mass when dynamic and inherited by anything
--- broken off it. Fragments of a wooden hut should not weigh like concrete.
---@return number
function VoxelVolume:GetDensity() end

--- Derived from density and current solid voxel volume. There is
--- intentionally no SetMass.
---@return number
function VoxelVolume:GetMass() end

--- Return occupied voxel volume in cubic metres.
---@return number
function VoxelVolume:GetSolidVolume() end

--- Buoyancy factor override for the world's water plane. 0 (default) = automatic from
--- density (1000/density: wood floats, stone sinks — Jolt convention, 1 = neutral).
--- Boats override upward to represent the sealed hull's trapped air, and scale it back
--- down as the hull is breached, which is what makes a shot-up yacht sink believably.
---@param buoyancy number
---@return nil
function VoxelVolume:SetBuoyancy(buoyancy) end

--- Return buoyancy.
---@return number
function VoxelVolume:GetBuoyancy() end

--- Centre-of-mass offset in volume-local metres. Boats push it below the keel (negative y)
--- for passive self-righting: near-square hull sections have a stable ~45-degree heeled
--- equilibrium (the square-log-floats-diagonally problem), and script-side control loops
--- failed twice at fixing it (undamped P diverges at the roll natural frequency; PD with
--- finite-difference rate injects energy through its one-frame lag). Set before
--- FinalizeVolumeAsDynamic; every later damage-rebuild proxy inherits it automatically.
---@param offset Vector3
---@return nil
function VoxelVolume:SetComOffset(offset) end

--- Return the centre-of-mass offset in volume-local space.
---@return Vector3
function VoxelVolume:GetComOffset() end

--- World-space velocity of the simulation body. Zero for static or body-less volumes;
--- setters are ignored for those. This is the flight-model API: lift and drag need
--- airspeed, and control loops that difference node poses instead are frame-rate coupled.
---@return Vector3
function VoxelVolume:GetLinearVelocity() end

--- Set linear velocity in world space, in metres per second.
---@param velocity Vector3
---@return nil
function VoxelVolume:SetLinearVelocity(velocity) end

--- Return angular velocity in world space, in radians per second.
---@return Vector3
function VoxelVolume:GetAngularVelocity() end

--- Set angular velocity in world space, in radians per second.
---@param velocity Vector3
---@return nil
function VoxelVolume:SetAngularVelocity(velocity) end

--- Motion damping, Jolt semantics (roughly the fraction of velocity shed per second;
--- default 0.05). Aircraft raise angular damping for attitude stability instead of
--- hand-writing counter-torques every frame. Live changes apply immediately.
---@param damping number
---@return nil
function VoxelVolume:SetLinearDamping(damping) end

--- Return linear damping.
---@return number
function VoxelVolume:GetLinearDamping() end

--- Set angular damping.
---@param damping number
---@return nil
function VoxelVolume:SetAngularDamping(damping) end

--- Return angular damping.
---@return number
function VoxelVolume:GetAngularDamping() end

--- Gravity multiplier for this body: 1 = normal (default), 0 = weightless. Hover
--- assistance for helicopters; pieces broken off always fall at 1.
---@param factor number
---@return nil
function VoxelVolume:SetGravityFactor(factor) end

--- Return gravity factor.
---@return number
function VoxelVolume:GetGravityFactor() end

--- Set use gravity.
---@param enable boolean
---@return nil
function VoxelVolume:SetUseGravity(enable) end

--- Return true if world gravity affects the volume.
---@return boolean
function VoxelVolume:GetUseGravity() end

--- Continuous collision detection (Jolt LinearCast), off by default. A fast mover
--- crosses more than a voxel wall's thickness per step (200 m/s at 60 Hz is 3.3 m),
--- so discrete collision tunnels straight through — fast movers must opt in.
---@param enable boolean
---@return nil
function VoxelVolume:SetCcdEnabled(enable) end

--- Return true if continuous collision detection is enabled.
---@return boolean
function VoxelVolume:IsCcdEnabled() end

--- Damp only one volume-local angular axis. For an assembly member the axis
--- is transformed by that member and the torque is applied to the shared
--- body.
---@param localAxis Vector3
---@param damping number
---@param maxTorque? number
---@return nil
function VoxelVolume:SetDirectionalAngularDamping(localAxis, damping, maxTorque) end

--- Clear directional angular damping.
---@param localAxis Vector3
---@return nil
function VoxelVolume:ClearDirectionalAngularDamping(localAxis) end

--- RigidBody-style force API, always world-space and automatically waking the
--- shared body.
---@param force Vector3
---@return nil
function VoxelVolume:ApplyForce(force) end

--- Apply force in newtons at the specified world-space position.
---@param force Vector3
---@param worldPosition Vector3
---@return nil
function VoxelVolume:ApplyForce(force, worldPosition) end

--- Apply impulse in newton-seconds.
---@param impulse Vector3
---@return nil
function VoxelVolume:ApplyImpulse(impulse) end

--- Apply impulse in newton-seconds.
---@param impulse Vector3
---@param worldPosition Vector3
---@return nil
function VoxelVolume:ApplyImpulse(impulse, worldPosition) end

--- Apply torque in newton-metres.
---@param torque Vector3
---@return nil
function VoxelVolume:ApplyTorque(torque) end

--- Apply angular impulse in newton-metre-seconds.
---@param torqueImpulse Vector3
---@return nil
function VoxelVolume:ApplyTorqueImpulse(torqueImpulse) end

--- Clear accumulated force and torque without clearing velocity.
---@return nil
function VoxelVolume:ResetForces() end

--- Return world-space velocity at the specified world-space point.
---@param worldPosition Vector3
---@return Vector3
function VoxelVolume:GetVelocityAtPoint(worldPosition) end

--- Wake the solver body.
---@return nil
function VoxelVolume:Activate() end

--- Return whether the underlying shared rigid body is active (not sleeping).
---@return boolean
function VoxelVolume:IsActive() end

--- Per-volume contact material. Negative serialized values mean inherit the
--- world default.
---@param friction number
---@return nil
function VoxelVolume:SetFriction(friction) end

--- Return friction.
---@return number
function VoxelVolume:GetFriction() end

--- Reset friction to world default.
---@return nil
function VoxelVolume:ResetFrictionToWorldDefault() end

--- Return true if friction overrides the world default.
---@return boolean
function VoxelVolume:HasFrictionOverride() end

--- Set restitution.
---@param restitution number
---@return nil
function VoxelVolume:SetRestitution(restitution) end

--- Return restitution.
---@return number
function VoxelVolume:GetRestitution() end

--- Reset restitution to world default.
---@return nil
function VoxelVolume:ResetRestitutionToWorldDefault() end

--- Return true if restitution overrides the world default.
---@return boolean
function VoxelVolume:HasRestitutionOverride() end

--- Member-level collision filtering. Layer is this volume's category; mask contains the
--- categories it accepts. Assembly contacts and scene queries resolve the exact member before
--- applying these values, even though all members share one broad-phase body.
---@param layer integer
---@return nil
function VoxelVolume:SetCollisionLayer(layer) end

--- Return collision layer.
---@return integer
function VoxelVolume:GetCollisionLayer() end

--- Set collision mask.
---@param mask integer
---@return nil
function VoxelVolume:SetCollisionMask(mask) end

--- Return collision mask.
---@return integer
function VoxelVolume:GetCollisionMask() end

--- Set collision layer and mask.
---@param layer integer
---@param mask integer
---@return nil
function VoxelVolume:SetCollisionLayerAndMask(layer, mask) end

--- Set collision group.
---@param group integer
---@return nil
function VoxelVolume:SetCollisionGroup(group) end

--- Return collision group.
---@return integer
function VoxelVolume:GetCollisionGroup() end

--- Return volume id.
---@return integer
function VoxelVolume:GetVolumeId() end

--- Analytic proxies affect physics only and never duplicate or replace the voxel grid used by
--- rendering and destruction. Any later occupancy mutation resets the policy to Auto; material
--- or palette edits preserve it because they do not change the occupied shape.
---@return nil
function VoxelVolume:SetCollisionShapeAuto() end

--- Use a box proxy with full local size. localOffset is relative to the occupied-bounds center.
---@param size Vector3
---@param localOffset? Vector3
---@param localRotation? Quaternion
---@return nil
function VoxelVolume:SetCollisionBox(size, localOffset, localRotation) end

--- Use a sphere proxy. diameter is the full diameter and localOffset is relative to the occupied-bounds center.
---@param diameter number
---@param localOffset? Vector3
---@return nil
function VoxelVolume:SetCollisionSphere(diameter, localOffset) end

--- Use a capsule whose height is the total end-to-end height including both caps.
---@param diameter number
---@param height number
---@param localOffset? Vector3
---@param localRotation? Quaternion
---@return nil
function VoxelVolume:SetCollisionCapsule(diameter, height, localOffset, localRotation) end

--- Use a cylinder proxy. Zero diameter and height derive both dimensions from occupied bounds.
---@param diameter? number
---@param height? number
---@param localOffset? Vector3
---@param localRotation? Quaternion
---@return nil
function VoxelVolume:SetCollisionCylinder(diameter, height, localOffset, localRotation) end

--- Derive cylinder dimensions from occupied bounds and orient its main axis to localAxis.
---@param localAxis Vector3
---@return nil
function VoxelVolume:SetCollisionCylinderAuto(localAxis) end

--- Return collision shape type.
---@return VoxelCollisionShapeType
function VoxelVolume:GetCollisionShapeType() end

--- Return collision shape size.
---@return Vector3
function VoxelVolume:GetCollisionShapeSize() end

--- Return collision shape offset.
---@return Vector3
function VoxelVolume:GetCollisionShapeOffset() end

--- Return collision shape rotation.
---@return Quaternion
function VoxelVolume:GetCollisionShapeRotation() end

--- Assembly membership is introduced by VoxelAssembly; standalone volumes
--- return null.
---@return VoxelAssembly
function VoxelVolume:GetAssembly() end

--- Return assembly root volume.
---@return VoxelVolume
function VoxelVolume:GetAssemblyRootVolume() end

--- Return true if this volume owns its assembly's shared body.
---@return boolean
function VoxelVolume:IsAssemblyRoot() end

--- Bind a different source .vox and re-bake the grid from it in place (body, constraints
--- and collision group survive). Null detaches; a model without a cache name is rejected,
--- because it could not re-bake on load. This is the script-facing model swap — a setter
--- that only recorded the reference would silently diverge it from the grid, and the
--- divergence would surface as a content swap on the next load. While bound, scene loading
--- re-bakes from the resource and skips voxel blob serialization; the first damage write
--- detaches automatically. Script that mutates the grid directly must call
--- DetachFromVoxelModel or those edits are lost on save.
---@param model VoxelModel
---@return nil
function VoxelVolume:SetVoxelModel(model) end

--- Resolve the source model through the resource cache (loading it if needed). Null when
--- detached or when the volume was never baked from a named resource. The volume stores
--- only the name — holding a pointer would pin the resource in memory for no runtime gain,
--- since collision and rendering read the grid, never the model.
---@return VoxelModel
function VoxelVolume:GetVoxelModel() end

--- Return voxel model name.
---@return string
function VoxelVolume:GetVoxelModelName() end

--- Return true if a source voxel model is assigned.
---@return boolean
function VoxelVolume:HasVoxelModel() end

--- Sever the link to the source .vox so the current grid serializes as blobs, and stop
--- following its reloads. The world calls this on the first damage write; script that
--- mutates the grid directly must call it itself, or those edits are lost on the next save.
---@return nil
function VoxelVolume:DetachFromVoxelModel() end


-- Global variables
---@type integer
VOXEL_CLIENT_PRESENTATION_ONLY = nil
---@type integer
VOXEL_CLIENT_SIMULATED = nil
---@type integer
VOXEL_CLIENT_COLLISION_PROXY = nil
