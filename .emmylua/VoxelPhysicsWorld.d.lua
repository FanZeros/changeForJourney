---@meta

--- Auto-generated from VoxelPhysics/VoxelPhysicsWorld

---@alias VoxelShadowVolumeQuery
---| integer # VoxelShadowVolumeQuery enum values

---@type VoxelShadowVolumeQuery
--- Trace the complete voxel occupancy hierarchy for every shadow ray.
VOXEL_SHADOW_QUERY_ACCURATE = 0
---@type VoxelShadowVolumeQuery
--- Trace the sparse hierarchy used by the default lighting path.
VOXEL_SHADOW_QUERY_SPARSE = 1
---@type VoxelShadowVolumeQuery
--- Use the cheapest banded ambient shadow approximation.
VOXEL_SHADOW_QUERY_SUPER_SPARSE = 2

---@class VoxelRaycastResult
---@overload fun(): VoxelRaycastResult
---@field hit boolean
---@field position Vector3
---@field normal Vector3
---@field distance number
---@field volume VoxelVolume
---@field assembly VoxelAssembly
---@field voxel IntVector3
---@field material integer
---@field volumeId integer
VoxelRaycastResult = {}

---@return VoxelRaycastResult
function VoxelRaycastResult.new() end


---@class VoxelPhysicsWorld : Component
---@field ddaRenderingEnabled boolean
---@field bodyCount integer
---@field gravity Vector3
---@field volumeCount integer
---@field minFragmentVoxels integer
---@field maxFrozenFragments integer
---@field frozenFragmentCount integer
---@field spallChunkVoxels integer
---@field spallSpeed number
---@field maxSpallChunks integer
---@field damageNoise number
---@field stressBreakFactor number
---@field contactEventThreshold number
---@field minDamageableVoxels integer
---@field debrisMaxAge number
---@field defaultFriction number
---@field lastSpawnedFragmentCount integer
---@field waterEnabled boolean
---@field waterLevel number
---@field updateEnabled boolean
---@field collisionSteps integer
VoxelPhysicsWorld = {}

--- Step the simulation. collisionSteps is the solver's substep count. Called
--- automatically on the scene subsystem update; call directly only when self-pacing
--- with SetUpdateEnabled(false).
---@param timeStep number
---@param collisionSteps? integer
---@return nil
function VoxelPhysicsWorld:Update(timeStep, collisionSteps) end

--- Number of bodies currently in the world. Present so callers can observe the
--- world without reaching for the solver.
---@return integer
function VoxelPhysicsWorld:GetBodyCount() end

--- Gravity shared by dynamic voxel bodies, vehicles, debris and characters. Individual
--- bodies and characters multiply this vector by their gravity factor.
---@param gravity Vector3
---@return nil
function VoxelPhysicsWorld:SetGravity(gravity) end

--- Return gravity acceleration in world space, in metres per second squared.
---@return Vector3
function VoxelPhysicsWorld:GetGravity() end

--- Create volume.
---@param dimX integer
---@param dimY integer
---@param dimZ integer
---@param voxelSize number
---@param position Vector3
---@param rotation? Quaternion
---@param mode? integer
---@return VoxelVolume
function VoxelPhysicsWorld:CreateVolume(dimX, dimY, dimZ, voxelSize, position, rotation, mode) end

--- Create a Scene-owned assembly and immediately adopt rootVolume as its first member.
---@param rootVolume VoxelVolume
---@return VoxelAssembly
function VoxelPhysicsWorld:CreateAssembly(rootVolume) end

--- Whether the component steps itself on the scene subsystem update (default true).
--- Turn off to pace the simulation manually through Update — fixed-timestep loops,
--- lockstep netcode, tests.
---@param enable boolean
---@return nil
function VoxelPhysicsWorld:SetUpdateEnabled(enable) end

--- Disable derived voxel rendering while retaining CPU data, physics and queries.
---@param enable boolean
---@return nil
function VoxelPhysicsWorld:SetDerivedRenderingEnabled(enable) end

---@return boolean
function VoxelPhysicsWorld:IsDerivedRenderingEnabled() end

--- Return true if fixed-step simulation updates are enabled.
---@return boolean
function VoxelPhysicsWorld:IsUpdateEnabled() end

--- Freeze solver stepping while continuing rendering, residency and background jobs.
---@param paused boolean
---@return nil
function VoxelPhysicsWorld:SetSimulationPaused(paused) end

--- Return true if solver stepping is paused for editor or tool use.
---@return boolean
function VoxelPhysicsWorld:IsSimulationPaused() end

--- Solver substep count used by the automatic step.
---@param steps integer
---@return nil
function VoxelPhysicsWorld:SetCollisionSteps(steps) end

--- Return collision steps.
---@return integer
function VoxelPhysicsWorld:GetCollisionSteps() end

--- Create an empty volume as a child of this world's Node, and fill it through the
--- component's grid.
---@param model VoxelModel
---@param voxelSize number
---@param position Vector3
---@param rotation? Quaternion
---@param mode? integer
---@return VoxelVolume
function VoxelPhysicsWorld:CreateVolumeFromModel(model, voxelSize, position, rotation, mode) end

--- Create a kinematic character backed by Jolt CharacterVirtual. height is the full standing
--- height (capsule top to bottom); position and GetCharacterPosition refer to the FEET.
---@param height number
---@param radius number
---@param position Vector3
---@return integer
function VoxelPhysicsWorld:CreateCharacter(height, radius, position) end

--- Remove the character referenced by the handle.
---@param handle integer
---@return nil
function VoxelPhysicsWorld:RemoveCharacter(handle) end

--- Drive one frame of movement. desiredVelocity is walk intent in the XZ plane (its Y is
--- ignored on land); gravity integrates internally, and jumpSpeed > 0 while grounded
--- launches a jump. Call once per rendered frame with that frame's timeStep — the character
--- sweeps against whatever the world looks like right now, including this frame's damage.
---@param handle integer
---@param desiredVelocity Vector3
---@param jumpSpeed number
---@param timeStep number
---@return nil
function VoxelPhysicsWorld:MoveCharacter(handle, desiredVelocity, jumpSpeed, timeStep) end

--- World position of the feet.
---@param handle integer
---@return Vector3
function VoxelPhysicsWorld:GetCharacterPosition(handle) end

--- Set character position.
---@param handle integer
---@param position Vector3
---@return nil
function VoxelPhysicsWorld:SetCharacterPosition(handle, position) end

--- Return character linear velocity.
---@param handle integer
---@return Vector3
function VoxelPhysicsWorld:GetCharacterLinearVelocity(handle) end

--- Set character linear velocity.
---@param handle integer
---@param velocity Vector3
---@return nil
function VoxelPhysicsWorld:SetCharacterLinearVelocity(handle, velocity) end

--- Return true if the character has walkable support.
---@param handle integer
---@return boolean
function VoxelPhysicsWorld:IsCharacterOnGround(handle) end

--- Return character ground state.
---@param handle integer
---@return VoxelCharacterGroundState
function VoxelPhysicsWorld:GetCharacterGroundState(handle) end

--- Return character ground normal.
---@param handle integer
---@return Vector3
function VoxelPhysicsWorld:GetCharacterGroundNormal(handle) end

--- Return character ground velocity.
---@param handle integer
---@return Vector3
function VoxelPhysicsWorld:GetCharacterGroundVelocity(handle) end

--- True while MoveCharacter is in swim mode (water enabled and past chest depth). While
--- swimming, desiredVelocity.y is the dive/ascend intent. Use this for animation, camera bob
--- and UI hints.
---@param handle integer
---@return boolean
function VoxelPhysicsWorld:IsCharacterSwimming(handle) end

--- Set character gravity factor.
---@param handle integer
---@param factor number
---@return nil
function VoxelPhysicsWorld:SetCharacterGravityFactor(handle, factor) end

--- Return character gravity factor.
---@param handle integer
---@return number
function VoxelPhysicsWorld:GetCharacterGravityFactor(handle) end

--- Set character mass.
---@param handle integer
---@param mass number
---@return nil
function VoxelPhysicsWorld:SetCharacterMass(handle, mass) end

--- Return character mass.
---@param handle integer
---@return number
function VoxelPhysicsWorld:GetCharacterMass(handle) end

--- Set character max strength.
---@param handle integer
---@param strength number
---@return nil
function VoxelPhysicsWorld:SetCharacterMaxStrength(handle, strength) end

--- Return character max strength.
---@param handle integer
---@return number
function VoxelPhysicsWorld:GetCharacterMaxStrength(handle) end

--- Set character max slope angle.
---@param handle integer
---@param degrees number
---@return nil
function VoxelPhysicsWorld:SetCharacterMaxSlopeAngle(handle, degrees) end

--- Return character max slope angle.
---@param handle integer
---@return number
function VoxelPhysicsWorld:GetCharacterMaxSlopeAngle(handle) end

--- Set character step height.
---@param handle integer
---@param height number
---@return nil
function VoxelPhysicsWorld:SetCharacterStepHeight(handle, height) end

--- Return character step height.
---@param handle integer
---@return number
function VoxelPhysicsWorld:GetCharacterStepHeight(handle) end

--- Set character stick to floor distance.
---@param handle integer
---@param distance number
---@return nil
function VoxelPhysicsWorld:SetCharacterStickToFloorDistance(handle, distance) end

--- Return character stick to floor distance.
---@param handle integer
---@return number
function VoxelPhysicsWorld:GetCharacterStickToFloorDistance(handle) end

--- Set character penetration recovery speed.
---@param handle integer
---@param speed number
---@return nil
function VoxelPhysicsWorld:SetCharacterPenetrationRecoverySpeed(handle, speed) end

--- Return character penetration recovery speed.
---@param handle integer
---@return number
function VoxelPhysicsWorld:GetCharacterPenetrationRecoverySpeed(handle) end

--- Set character enhanced internal edge removal.
---@param handle integer
---@param enable boolean
---@return nil
function VoxelPhysicsWorld:SetCharacterEnhancedInternalEdgeRemoval(handle, enable) end

--- Return true if enhanced internal edge removal is enabled for the character.
---@param handle integer
---@return boolean
function VoxelPhysicsWorld:GetCharacterEnhancedInternalEdgeRemoval(handle) end

--- Set character max num hits.
---@param handle integer
---@param maxHits integer
---@return nil
function VoxelPhysicsWorld:SetCharacterMaxNumHits(handle, maxHits) end

--- Return character max num hits.
---@param handle integer
---@return integer
function VoxelPhysicsWorld:GetCharacterMaxNumHits(handle) end

--- Return true if the character's last update exceeded its contact limit.
---@param handle integer
---@return boolean
function VoxelPhysicsWorld:GetCharacterMaxHitsExceeded(handle) end

--- Change capsule dimensions without moving its feet. Returns false when growing would
--- overlap the world (standing up below a low ceiling).
---@param handle integer
---@param height number
---@param radius number
---@return boolean
function VoxelPhysicsWorld:SetCharacterShape(handle, height, radius) end

--- Begin a generic constraint-solver grab using a kinematic anchor and compliant leash. The
--- same grab drags loose debris, swings hinged doors and slides drawers. Frozen debris is a
--- legitimate target and is woken; authored static structure refuses and returns INVALID_GRAB.
--- UpdateGrab returns false once released, the volume dies or the load falls breakDistance
--- behind.
---@param volume VoxelVolume
---@param worldPoint Vector3
---@return integer
function VoxelPhysicsWorld:BeginGrab(volume, worldPoint) end

--- Steer the anchor toward target (the hand), speed-clamped to maxSpeed. Returns false
--- once the grab has ended — released, the volume died or moved to another assembly body,
--- or the load fell more than breakDistance behind the hand (stuck behind a wall, door at
--- its limit while the player keeps walking, too heavy to follow). Callers drop the handle
--- on false.
---@param handle integer
---@param target Vector3
---@param timeStep number
---@param maxSpeed? number
---@param breakDistance? number
---@return boolean
function VoxelPhysicsWorld:UpdateGrab(handle, target, timeStep, maxSpeed, breakDistance) end

--- End the grab and retire its runtime handle.
---@param handle integer
---@return nil
function VoxelPhysicsWorld:EndGrab(handle) end

--- Return the volume referenced by a live grab handle, or null.
---@param handle integer
---@return VoxelVolume
function VoxelPhysicsWorld:GetGrabbedVolume(handle) end

--- Publish a volume's collision to the simulation as immovable world geometry. Call once its
--- voxels are filled in.
---@param volume VoxelVolume
---@return nil
function VoxelPhysicsWorld:FinalizeVolume(volume) end

--- Same, but as a movable body: a vehicle chassis, a wheel, a pushable crate.
---@param volume VoxelVolume
---@return nil
function VoxelPhysicsWorld:FinalizeVolumeAsDynamic(volume) end

--- Rebuild a dynamic volume's collision from its current voxels after editing its grid
--- directly. Damage operations do this automatically.
---@param volume VoxelVolume
---@return nil
function VoxelPhysicsWorld:RebuildDynamicProxy(volume) end

--- Components smaller than this are deleted rather than released as fragments.
---@param voxels integer
---@return nil
function VoxelPhysicsWorld:SetMinFragmentVoxels(voxels) end

--- Return min fragment voxels.
---@return integer
function VoxelPhysicsWorld:GetMinFragmentVoxels() end

--- Cap on simultaneously existing frozen fragments. Exceeding it evicts the oldest.
---@param count integer
---@return nil
function VoxelPhysicsWorld:SetMaxFrozenFragments(count) end

--- Return max frozen fragments.
---@return integer
function VoxelPhysicsWorld:GetMaxFrozenFragments() end

--- Return frozen fragment count.
---@return integer
function VoxelPhysicsWorld:GetFrozenFragmentCount() end

--- Side length, in voxels, of the lattice that removed material is grouped into before being
--- thrown clear as debris. Severing alone yields almost no rubble because a hole through the
--- middle of a building disconnects nothing. Zero — the default — disables spall entirely and
--- restores pure subtraction.
---@param voxelsPerSide integer
---@return nil
function VoxelPhysicsWorld:SetSpallChunkVoxels(voxelsPerSide) end

--- Return spall chunk voxels.
---@return integer
function VoxelPhysicsWorld:GetSpallChunkVoxels() end

--- Speed, in m/s, that debris is thrown away from the point of impact.
---@param speed number
---@return nil
function VoxelPhysicsWorld:SetSpallSpeed(speed) end

--- Return spall speed.
---@return number
function VoxelPhysicsWorld:GetSpallSpeed() end

--- Upper bound on debris chunks thrown by one damage event. Default 12. Raise together with a
--- smaller chunk size or finer rubble is silently truncated.
---@param count integer
---@return nil
function VoxelPhysicsWorld:SetMaxSpallChunks(count) end

--- Return max spall chunks.
---@return integer
function VoxelPhysicsWorld:GetMaxSpallChunks() end

--- Raggedness of the damage boundary, 0 (off, default) to 1. Fine voxels approximate the
--- damage shape so precisely that holes look machined; noise restores a smashed edge.
---@param amount number
---@return nil
function VoxelPhysicsWorld:SetDamageNoise(amount) end

--- Stress-break heuristic: after damage, a nearly-severed structure snaps at its weakest
--- horizontal layer instead of hanging off a sliver forever.
---@param factor number
---@return nil
function VoxelPhysicsWorld:SetStressBreakFactor(factor) end

--- Return stress break factor.
---@return number
function VoxelPhysicsWorld:GetStressBreakFactor() end

--- Contact events (E_VOXELCONTACT): bodies hitting each other harder than this closing
--- speed (m/s) raise an event — the hook for impact sounds and hit-by-debris damage.
--- 0 (the default) disables collection entirely.
---@param minClosingSpeed number
---@return nil
function VoxelPhysicsWorld:SetContactEventThreshold(minClosingSpeed) end

--- Return contact event threshold.
---@return number
function VoxelPhysicsWorld:GetContactEventThreshold() end

--- Return damage noise.
---@return number
function VoxelPhysicsWorld:GetDamageNoise() end

--- Rubble at or below this many voxels ignores further damage (Teardown-style inert pebbles).
--- Zero (default) disables.
---@param voxels integer
---@return nil
function VoxelPhysicsWorld:SetMinDamageableVoxels(voxels) end

--- Return min damageable voxels.
---@return integer
function VoxelPhysicsWorld:GetMinDamageableVoxels() end

--- Seconds a frozen piece of rubble may exist before being quietly removed. Zero (default)
--- disables. Only evictable rubble ages; structure never expires. Together with the cap this
--- gives the debris field a lifetime as well as a size.
---@param seconds number
---@return nil
function VoxelPhysicsWorld:SetDebrisMaxAge(seconds) end

--- Return debris max age.
---@return number
function VoxelPhysicsWorld:GetDebrisMaxAge() end

--- Destroy a volume: its Node, its component and its solver body.
---@param volume VoxelVolume
---@return nil
function VoxelPhysicsWorld:RemoveVolume(volume) end

--- Push everything dynamic within radius away from a point, waking frozen rubble first
--- so a blast scatters the debris field instead of only nudging what already moves.
--- impulse is in N*s at the centre, falling off linearly to zero at the radius.
---@param worldCenter Vector3
---@param radius number
---@param impulse number
---@return nil
function VoxelPhysicsWorld:ApplyRadialImpulse(worldCenter, radius, impulse) end

--- Remove every voxel whose centre falls inside a world-space sphere, then re-check
--- connectivity.
---@param volume VoxelVolume
---@param worldCenter Vector3
---@param radius number
---@param power? number
---@param scorchMaterial? integer
---@param onlyMaterial? integer
---@return integer
function VoxelPhysicsWorld:ApplyDamage(volume, worldCenter, radius, power, scorchMaterial, onlyMaterial) end

--- Damage whatever is at a world position, without the caller having to know which volume that
--- is. A non-zero scorchMaterial repaints the surviving shell just outside the carve with that
--- palette slot for burn or saw marks.
---@param worldCenter Vector3
---@param radius number
---@param power? number
---@param scorchMaterial? integer
---@param onlyMaterial? integer
---@return integer
function VoxelPhysicsWorld:ApplyDamageAtWorldPoint(worldCenter, radius, power, scorchMaterial, onlyMaterial) end

--- Segment-swept damage: everything within `radius` of the segment [worldA, worldB] is
--- carved. The saw/slash/laser primitive — a thin long capsule cuts a wall in half.
--- Broadcast like ApplyDamageAtWorldPoint: every volume the capsule's bounds reach.
---@param worldA Vector3
---@param worldB Vector3
---@param radius number
---@param power? number
---@param scorchMaterial? integer
---@param onlyMaterial? integer
---@return integer
function VoxelPhysicsWorld:ApplyDamageCapsule(worldA, worldB, radius, power, scorchMaterial, onlyMaterial) end

--- Oriented-box damage. A thin box is the plane-cut primitive.
---@param worldCenter Vector3
---@param halfExtent Vector3
---@param rotation Quaternion
---@param power? number
---@param scorchMaterial? integer
---@param onlyMaterial? integer
---@return integer
function VoxelPhysicsWorld:ApplyDamageBox(worldCenter, halfExtent, rotation, power, scorchMaterial, onlyMaterial) end

--- Directional cone damage: apex at `apex`, opening `halfAngleDeg` around `direction`,
--- reaching `range`. The breaching-charge/shotgun-blast primitive — carves forward, not
--- isotropically.
---@param apex Vector3
---@param direction Vector3
---@param halfAngleDeg number
---@param range number
---@param power? number
---@param scorchMaterial? integer
---@param onlyMaterial? integer
---@return integer
function VoxelPhysicsWorld:ApplyDamageCone(apex, direction, halfAngleDeg, range, power, scorchMaterial, onlyMaterial) end

--- Palette index of the solid voxel at a world position, or -1 if the point is empty or
--- outside every volume. The non-destructive read tools want before deciding what to do:
--- footstep sounds, hit sparks vs splinters, "this is rock, bring explosives" prompts.
---@param worldPos Vector3
---@return integer
function VoxelPhysicsWorld:GetMaterialAtWorldPoint(worldPos) end

--- The build counterpart of ApplyDamageAtWorldPoint: fill EMPTY voxels within the sphere
--- with `material`, in every existing volume the sphere reaches. Existing solids are left
--- untouched (their material included). Dynamic volumes get their proxy and mass rebuilt.
--- Returns the number of voxels added. Does NOT create new volumes where none exist.
---@param worldCenter Vector3
---@param radius number
---@param material integer
---@return integer
function VoxelPhysicsWorld:ApplyFillAtWorldPoint(worldCenter, radius, material) end

--- Volumes this world is simulating, in creation order. Entries can be null if a volume's
--- Node was destroyed from outside.
---@return integer
function VoxelPhysicsWorld:GetVolumeCount() end

--- Return volume.
---@param index integer
---@return VoxelVolume
function VoxelPhysicsWorld:GetVolume(index) end

--- Indexed view of the same list. Scripts cannot hand over a caller-owned array, so they
--- walk it instead.
---@return integer
function VoxelPhysicsWorld:GetLastSpawnedFragmentCount() end

--- Return last spawned fragment.
---@param index integer
---@return VoxelVolume
function VoxelPhysicsWorld:GetLastSpawnedFragment(index) end

--- Rebuild the broad phase. Worth one call after the initial batch of static bodies.
---@return nil
function VoxelPhysicsWorld:OptimizeBroadPhase() end

--- Enable distance-based mesh streaming. The render mesh is a discardable cache of the grid:
--- when enabled (default), distant volumes drop their GPU mesh and rebuild in the background
--- when the camera returns; when disabled, everything stays meshed permanently. Damage
--- remeshing stays asynchronous either way. This is a runtime flag and is not serialized.
---@param enable boolean
---@return nil
function VoxelPhysicsWorld:SetMeshStreamingEnabled(enable) end

--- Return true if distance-based mesh streaming is enabled.
---@return boolean
function VoxelPhysicsWorld:IsMeshStreamingEnabled() end

--- Distance (meters, from the streaming reference position to the volume's world
--- bounds) beyond which a volume's mesh is dropped. Rebuild kicks in at a hysteresis
--- margin inside this, so a camera hovering on the boundary does not thrash.
---@param distance number
---@return nil
function VoxelPhysicsWorld:SetMeshStreamingDistance(distance) end

--- Return mesh streaming distance.
---@return number
function VoxelPhysicsWorld:GetMeshStreamingDistance() end

--- Where "the camera" is for streaming decisions. Auto-follows viewport 0's camera
--- every frame when one exists; setting this pins it explicitly — for split-screen
--- policy, server-side authority, or headless tests, where no Renderer camera exists.
---@param position Vector3
---@return nil
function VoxelPhysicsWorld:SetMeshStreamingReferencePosition(position) end

--- Back to auto-following viewport 0.
---@return nil
function VoxelPhysicsWorld:ClearMeshStreamingReferencePosition() end

--- Add or update a scene-scoped secondary DDA residency source. It forms a
--- union with the primary pin/camera source. Zero and ~0ull are reserved;
--- Lua callers should use positive IDs no greater than 2^53 so identity is exact.
---@param sourceId integer
---@param position Vector3
---@return boolean
function VoxelPhysicsWorld:SetDdaResidencySourcePosition(sourceId, position) end

--- Remove one secondary source without changing the primary source. Lua callers
--- should use positive IDs no greater than 2^53 so identity is exact.
---@param sourceId integer
---@return boolean
function VoxelPhysicsWorld:RemoveDdaResidencySource(sourceId) end

--- Remove every secondary source. The primary pin/camera is unchanged.
---@return nil
function VoxelPhysicsWorld:ClearDdaResidencySources() end

--- Background mesh jobs submitted but not yet landed. "Volume not dirty" alone does
--- not mean its surface is current — dirty clears at submission; this is the other
--- half of convergence. Tests and load-progress UI poll it.
---@return integer
function VoxelPhysicsWorld:GetPendingMeshJobCount() end

--- Stable key=value Dense DDA atlas/upload/job telemetry. The query never creates
--- atlas or table resources and is intended for deterministic baseline fixtures.
---@return string
function VoxelPhysicsWorld:GetDdaStatsString() end

--- Read current voxel content synchronization diagnostics without changing state.
---@return string
function VoxelPhysicsWorld:GetNetworkStatsString() end

--- Distance (meters) of the first LOD ring boundary: volumes closer than this mesh
--- at full resolution, then each ring doubles (LOD1 to 2x, LOD2 to 4x, capped at
--- VOXEL_MAX_MESH_LOD). 0 disables LOD entirely (everything meshes at level 0 — the
--- PR2 behaviour and the triage lever when a LOD artefact is suspected). Ring
--- changes rebuild through the async pipeline build-before-teardown, so crossing a
--- boundary never blanks a building. Runtime flag like the streaming switch, never
--- serialized. Default 100.
---@param distance number
---@return nil
function VoxelPhysicsWorld:SetMeshLodDistance(distance) end

--- Return mesh lod distance.
---@return number
function VoxelPhysicsWorld:GetMeshLodDistance() end

--- Screen-size cull: a volume whose world bounds project smaller than this many
--- pixels (vertically, against viewport 0's camera) is streamed out entirely — at
--- that size it is sub-pixel noise, and distant scenes are mostly such volumes.
--- Needs a real camera for the pixel conversion; with none (headless, pinned
--- reference without a Renderer) the cull is inert. 0 disables. Default 4.
---@param pixels number
---@return nil
function VoxelPhysicsWorld:SetMeshScreenCullSize(pixels) end

--- Return mesh screen cull size.
---@return number
function VoxelPhysicsWorld:GetMeshScreenCullSize() end

--- Define a palette entry: the flat colour its voxels render with, and the hardness a damage
--- call must match or exceed to remove them. Entry 0 defaults to white with hardness 0.
--- debrisStyle: 0 = removed material spalls into lumps as usual; 1 = shatters to dust
--- (glass) — the hole appears but no debris spawns from it.
--- index is GLOBAL (bank * 256 + slot); writing past the current bank count allocates
--- banks up to it (within MAX_PALETTE_BANKS). Indices 0-255 remain the original scene-wide
--- bank 0, so pre-bank scripts keep working; a volume's bank is chosen at bake.
---@param index integer
---@param color Color
---@param hardness number
---@param debrisStyle? integer
---@param domain? integer
---@return nil
function VoxelPhysicsWorld:SetPaletteEntry(index, color, hardness, debrisStyle, domain) end

--- Banks allocated so far (>= 1; bank 0 always exists).
---@param domain? integer
---@return integer
function VoxelPhysicsWorld:GetPaletteBankCount(domain) end

--- Return palette debris style.
---@param index integer
---@param domain? integer
---@return integer
function VoxelPhysicsWorld:GetPaletteDebrisStyle(index, domain) end

--- Return a color from the selected domain.
---@param index integer
---@param domain? integer
---@return Color
function VoxelPhysicsWorld:GetPaletteColor(index, domain) end

--- Return palette hardness.
---@param index integer
---@param domain? integer
---@return number
function VoxelPhysicsWorld:GetPaletteHardness(index, domain) end

--- PBR surface parameters of an entry: how its voxels respond to light, on top of the flat
--- colour above. Defaults (roughness 0.85, metallic 0, specular 0.5, no emission) match
--- what the voxel technique hard-coded before the palette carried materials, so untouched
--- entries render exactly as they always did. emissive is a colour whose ALPHA is the
--- intensity, 0..16: final emission = rgb * a. The ceiling exists because the texture
--- mirror is plain RGBA8 — intensity quantises to 1/16 steps, plenty for bloom while
--- keeping the palette a dumb small texture. Imported .vox MATL chunks land here; this
--- override wins over the import, same contract as SetPaletteEntry vs the MATL hardness
--- table.
---@param index integer
---@param roughness number
---@param metallic number
---@param specular number
---@param emissive? Color
---@param domain? integer
---@return nil
function VoxelPhysicsWorld:SetPaletteEntryPBR(index, roughness, metallic, specular, emissive, domain) end

--- Return palette roughness.
---@param index integer
---@param domain? integer
---@return number
function VoxelPhysicsWorld:GetPaletteRoughness(index, domain) end

--- Return palette metallic.
---@param index integer
---@param domain? integer
---@return number
function VoxelPhysicsWorld:GetPaletteMetallic(index, domain) end

--- Return palette specular.
---@param index integer
---@param domain? integer
---@return number
function VoxelPhysicsWorld:GetPaletteSpecular(index, domain) end

--- Return palette emissive.
---@param index integer
---@param domain? integer
---@return Color
function VoxelPhysicsWorld:GetPaletteEmissive(index, domain) end

--- Colour freshly exposed cross-sections of this entry render with (the interior-bit path;
--- see VoxelGrid's interior mask). Unset entries derive albedo * 0.6 — material seen in
--- section reads darker than its painted skin, the Teardown default. Setting it makes the
--- cut a material of its own: pale timber inside dark bark, mortar grey inside brick.
---@param index integer
---@param color Color
---@param domain? integer
---@return nil
function VoxelPhysicsWorld:SetPaletteCutColor(index, color, domain) end

--- Return palette cut color.
---@param index integer
---@param domain? integer
---@return Color
function VoxelPhysicsWorld:GetPaletteCutColor(index, domain) end

--- The palette as a 256-wide RGBA8 texture the voxel shaders sample by palette index.
--- Each bank owns 4 consecutive rows: row 0 albedo, row 1 roughness/metallic/specular,
--- row 2 emissive (a = intensity/16), row 3 cut-face colour; bank B's rows start at
--- B * 4, and the texture is a fixed 256 x (MAX_PALETTE_BANKS * 4) so growing the bank
--- count never reallocates it. Uploads are per-bank sub-rects driven by a bank dirty
--- set, at most once per frame — a SetPaletteEntry* burst re-uploads 4 KB per touched
--- bank, not the whole atlas. Null in headless contexts (no Graphics).
--- Plain RGBA8 (no sRGB view): albedo / emissive.rgb / cut rows are sRGB bytes and need
--- a manual linear decode after sample; the PBR row is linear scalar data and must not
--- be decoded.
--- This is the UGC hook: a custom SurfaceShader material binds it via
--- material:SetSurfaceTexture("<sampler name>", world:GetPaletteTexture()) and
--- reimplements the look on top of the same data (raw slot indices are owned by the
--- SurfaceShader codegen — never hardcode them). Non-zero-bank volumes must offset
--- their sampling rows by GetPaletteBank() * 4 — see the VoxelPaletteBank material
--- parameter on the default materials.
---@param domain? integer
---@return Texture2D
function VoxelPhysicsWorld:GetPaletteTexture(domain) end

--- This world's default voxel material for a bank: Materials/VoxelPalette.xml cloned
--- with the palette texture bound and the bank's row offset set as the
--- "VoxelPaletteBank" shader parameter. One clone per (world, bank), shared by every
--- volume in that bank so batching stays intact. A clone because both the texture and
--- the bank offset are per-world state that must not leak into the shared cache
--- resource. Volumes get their bank's material by default at CreateVolume, at bake and
--- on load; an explicit SetMaterial (fragments inheriting a parent's skin) overrides it.
--- Allocates the bank if missing (a handed-out material must only ever sample uploaded
--- atlas rows); null past MAX_PALETTE_BANKS or without the template resource.
---@param bank? integer
---@param domain? integer
---@return Material
function VoxelPhysicsWorld:GetPaletteMaterial(bank, domain) end

--- World-palette volumes use DDA when this is on and the render path has deferredvox.
--- Desktop default on; mobile default off. Lua: world:SetDdaRenderingEnabled(true).
---@param enable boolean
---@return nil
function VoxelPhysicsWorld:SetDdaRenderingEnabled(enable) end

--- Return true if DDA rendering is enabled for eligible volumes.
---@return boolean
function VoxelPhysicsWorld:IsDdaRenderingEnabled() end

--- Fixed world-space shadow volume for Teardown-style voxel shadow rendering.
--- Disabled by default; enabled by calling InitializeShadowVolume(). texelSize should usually
--- be 2 * voxelSize so one texel represents 2x2x2 subvoxels.
---@param boundsMin Vector3
---@param boundsMax Vector3
---@param texelSize number
---@return boolean
function VoxelPhysicsWorld:InitializeShadowVolume(boundsMin, boundsMax, texelSize) end

--- One-shot bounds from current volumes, padded by sunExtend on every axis.
--- Does not track future spawn; re-call after the level is fully placed.
---@param texelSize number
---@param sunExtend? number
---@return boolean
function VoxelPhysicsWorld:InitializeShadowVolumeFromCurrentVolumes(texelSize, sunExtend) end

--- Destroy the optional voxel shadow volume.
---@return nil
function VoxelPhysicsWorld:ShutdownShadowVolume() end

--- Return true if the optional voxel shadow volume is initialized.
---@return boolean
function VoxelPhysicsWorld:IsShadowVolumeEnabled() end

--- Switch Teardown query: Accurate / Sparse (default) / SuperSparse. Takes effect next frame.
---@param query VoxelShadowVolumeQuery
---@return nil
function VoxelPhysicsWorld:SetShadowVolumeQuery(query) end

--- Return shadow volume query.
---@return VoxelShadowVolumeQuery
function VoxelPhysicsWorld:GetShadowVolumeQuery() end

--- 0 = no random tangent jitter. 1 = full Teardown jitterPosition (default).
--- Systematic light/normal bias is always on. Takes effect next frame.
---@param scale number
---@return nil
function VoxelPhysicsWorld:SetShadowVolumeJitter(scale) end

--- Return shadow volume jitter.
---@return number
function VoxelPhysicsWorld:GetShadowVolumeJitter() end

---@param ray Ray
---@param maxDistance number
---@param collisionMask? integer
---@return VoxelRaycastResult[]
function VoxelPhysicsWorld:Raycast(ray, maxDistance, collisionMask) end

---@param ray Ray
---@param maxDistance number
---@param collisionMask? integer
---@return VoxelRaycastResult
function VoxelPhysicsWorld:RaycastSingle(ray, maxDistance, collisionMask) end

---@param ray Ray
---@param maxDistance number
---@param layerMask? integer
---@param ignoreVolume? VoxelVolume
---@return VoxelRaycastResult[]
function VoxelPhysicsWorld:RaycastGrid(ray, maxDistance, layerMask, ignoreVolume) end

---@param ray Ray
---@param maxDistance number
---@param layerMask? integer
---@param ignoreVolume? VoxelVolume
---@return VoxelRaycastResult
function VoxelPhysicsWorld:RaycastGridSingle(ray, maxDistance, layerMask, ignoreVolume) end

---@param sphere Sphere
---@param direction Vector3
---@param maxDistance number
---@param collisionMask? integer
---@return VoxelRaycastResult
function VoxelPhysicsWorld:SphereCast(sphere, direction, maxDistance, collisionMask) end

--- Coulomb friction given to every body created from now on. Existing bodies are unchanged, so
--- set this before building the level.
---@param friction number
---@return nil
function VoxelPhysicsWorld:SetDefaultFriction(friction) end

--- Return default friction.
---@return number
function VoxelPhysicsWorld:GetDefaultFriction() end

--- Enable the global water plane. Dynamic volumes below it receive buoyancy derived from
--- density (1000 / density) or the volume's explicit buoyancy override. See
--- VoxelVolume.buoyancy.
---@param enable boolean
---@return nil
function VoxelPhysicsWorld:SetWaterEnabled(enable) end

--- Return true if the global water plane is enabled.
---@return boolean
function VoxelPhysicsWorld:IsWaterEnabled() end

--- Set the world-space height of the water plane.
---@param level number
---@return nil
function VoxelPhysicsWorld:SetWaterLevel(level) end

--- Return the world-space height of the water plane.
---@return number
function VoxelPhysicsWorld:GetWaterLevel() end

--- Drag factors for submerged bodies (Jolt linear/angular drag, defaults 0.4 / 0.6).
---@param linearDrag number
---@param angularDrag number
---@return nil
function VoxelPhysicsWorld:SetWaterDrag(linearDrag, angularDrag) end


-- Global variables
---@type integer
VOXEL_PALETTE_REPLICATED = nil
---@type integer
VOXEL_PALETTE_LOCAL = nil
