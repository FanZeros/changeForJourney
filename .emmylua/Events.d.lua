---@meta

--- Urho3D Event System Type Definitions
--- Auto-generated from *Events.h files
---
--- This file provides type-safe event data for SubscribeToEvent
---
--- Usage:
---   SubscribeToEvent("MouseMove", function(eventType, eventData)
---       local x = eventData["X"]:GetInt()  -- Type-safe: X is a valid field
---   end)

--- NOTE: VariantMap and VariantWith* types are defined in _UrhoTypes.d.lua

-- =============================================================================
-- Type Aliases for Event Names
-- =============================================================================

--- Union type of all known event names (259 events)
--- Can be used to constrain event name parameters for auto-completion
---@alias KnownEventName
---| "AnimationAllStoppingEvent"
---| "AnimationControllerPostUpdate"
---| "AnimationControllerPreUpdate"
---| "AnimationFinished"
---| "AnimationFinishedEventEx"
---| "AnimationSuppressedEvent"
---| "AnimationTrigger"
---| "AnimationUpdate"
---| "AppDidEnterBackground"
---| "AppDidEnterForebackground"
---| "AppLowMemory"
---| "AppTerminating"
---| "AppWillEnterBackground"
---| "AppWillEnterForeground"
---| "AsyncExecFinished"
---| "AsyncLoadFinished"
---| "AsyncLoadProgress"
---| "AttributeAnimationAdded"
---| "AttributeAnimationRemoved"
---| "AttributeAnimationUpdate"
---| "BeforeBeginFrame"
---| "BeforeRestartGame"
---| "BeginAllViewRender"
---| "BeginFrame"
---| "BeginRendering"
---| "BeginReplayFrame"
---| "BeginViewRender"
---| "BeginViewUpdate"
---| "BoneHierarchyCreated"
---| "ChangeLanguage"
---| "Click"
---| "ClickEnd"
---| "ClientConnected"
---| "ClientDisconnected"
---| "ClientIdentity"
---| "ClientIdentityAccepted"
---| "ClientSceneLoaded"
---| "ComponentAdded"
---| "ComponentCloned"
---| "ComponentEnabledChanged"
---| "ComponentRemoved"
---| "ConnectFailed"
---| "ConsoleCommand"
---| "CrowdAgentFailure"
---| "CrowdAgentFormation"
---| "CrowdAgentNodeFailure"
---| "CrowdAgentNodeFormation"
---| "CrowdAgentNodeReposition"
---| "CrowdAgentNodeStateChanged"
---| "CrowdAgentReposition"
---| "CrowdAgentStateChanged"
---| "CustomValue"
---| "DbCursor"
---| "Defocused"
---| "DeviceLost"
---| "DeviceReset"
---| "DiskQuotaExceeded"
---| "DoubleClick"
---| "DragBegin"
---| "DragCancel"
---| "DragDropFinish"
---| "DragDropTest"
---| "DragEnd"
---| "DragMove"
---| "DrawableBatchesChanged"
---| "DropFile"
---| "DumpTest"
---| "ElementAdded"
---| "ElementRemoved"
---| "EndAllViewsRender"
---| "EndFrame"
---| "EndRendering"
---| "EndViewRender"
---| "EndViewUpdate"
---| "ExitRequested"
---| "FileChanged"
---| "FileSelected"
---| "FinishResources"
---| "FocusChanged"
---| "Focused"
---| "GPUHandleChanged"
---| "GameSessionStarted"
---| "GestureInput"
---| "GestureRecorded"
---| "HoverBegin"
---| "HoverEnd"
---| "IKEffectorTargetChanged"
---| "InputBegin"
---| "InputEnd"
---| "InputFocus"
---| "InterceptNetworkUpdate"
---| "ItemClicked"
---| "ItemDeselected"
---| "ItemDoubleClicked"
---| "ItemSelected"
---| "JoystickAxisMove"
---| "JoystickButtonDown"
---| "JoystickButtonUp"
---| "JoystickConnected"
---| "JoystickDisconnected"
---| "JoystickHatMove"
---| "KeyDown"
---| "KeyUp"
---| "LayoutUpdated"
---| "LoadFailed"
---| "LogMessage"
---| "MenuSelected"
---| "MergeLight"
---| "MessageACK"
---| "ModalChanged"
---| "MouseButtonDown"
---| "MouseButtonUp"
---| "MouseModeChanged"
---| "MouseMove"
---| "MouseVisibleChanged"
---| "MouseWheel"
---| "MultiGesture"
---| "NameChanged"
---| "NanoVGRender"
---| "NavigationAllTilesRemoved"
---| "NavigationAreaRebuilt"
---| "NavigationMeshRebuilt"
---| "NavigationObstacleAdded"
---| "NavigationObstacleRemoved"
---| "NavigationTileAdded"
---| "NavigationTileRemoved"
---| "NetworkBanned"
---| "NetworkHostDiscovered"
---| "NetworkInvalidPassword"
---| "NetworkMessage"
---| "NetworkNatMasterConnectionFailed"
---| "NetworkNatMasterConnectionSucceeded"
---| "NetworkNatPunchtroughFailed"
---| "NetworkNatPunchtroughSucceeded"
---| "NetworkReconnected"
---| "NetworkReconnecting"
---| "NetworkSceneLoadFailed"
---| "NetworkUpdate"
---| "NetworkUpdateSent"
---| "NodeAdded"
---| "NodeBeginContact2D"
---| "NodeCloned"
---| "NodeCollision"
---| "NodeCollisionEnd"
---| "NodeCollisionStart"
---| "NodeEnabledChanged"
---| "NodeEndContact2D"
---| "NodeNameChanged"
---| "NodeRemoved"
---| "NodeTagAdded"
---| "NodeTagRemoved"
---| "NodeUpdateContact2D"
---| "OrientationChanged"
---| "ParticleEffectFinished"
---| "ParticlesDuration"
---| "ParticlesEnd"
---| "PhysicsBeginContact2D"
---| "PhysicsCollision"
---| "PhysicsCollisionEnd"
---| "PhysicsCollisionStart"
---| "PhysicsEndContact2D"
---| "PhysicsMotionStates"
---| "PhysicsPostStep"
---| "PhysicsPreStep"
---| "PhysicsUpdateContact2D"
---| "PlayerSessionDisconnected"
---| "PlayerSessionJoined"
---| "PlayerSessionLeft"
---| "PlayerSessionReconnected"
---| "Positioned"
---| "PostPreRenderUI"
---| "PostRenderUI"
---| "PostRenderUpdate"
---| "PostUpdate"
---| "PreEndFrame"
---| "PreRenderUI"
---| "PreRenderUpdate"
---| "Pressed"
---| "ProgressBarChanged"
---| "Released"
---| "ReloadFailed"
---| "ReloadFinished"
---| "ReloadStarted"
---| "RemoteEventData"
---| "RenderPathEvent"
---| "RenderQualityApply"
---| "RenderSurfaceUpdate"
---| "RenderUpdate"
---| "Resized"
---| "ResourceBackgroundLoaded"
---| "ResourceNotFound"
---| "RuntimeDebuggerSelectionChanged"
---| "SDLRawInput"
---| "SceneDrawableUpdateFinished"
---| "SceneLoadFinished"
---| "ScenePostUpdate"
---| "SceneSubsystemUpdate"
---| "SceneUpdate"
---| "ScreenMode"
---| "ScrollBarChanged"
---| "SelectionChanged"
---| "ServerConnected"
---| "ServerDisconnected"
---| "ShaderCompile"
---| "ShaderUncompress"
---| "SliderChanged"
---| "SliderPaged"
---| "SoundFinished"
---| "TargetPositionChanged"
---| "TargetRotationChanged"
---| "TemporaryChanged"
---| "TerrainCreated"
---| "TextChanged"
---| "TextEditing"
---| "TextEntry"
---| "TextFinished"
---| "TextInput"
---| "TextureFroamtWarn"
---| "Toggled"
---| "Touch"
---| "TouchBegin"
---| "TouchEnd"
---| "TouchMove"
---| "TransportConnectFailed"
---| "TransportConnected"
---| "TransportData"
---| "TransportDisconnected"
---| "UIDropFile"
---| "UIMouseClick"
---| "UIMouseClickEnd"
---| "UIMouseClickReplay"
---| "UIMouseClickReplayPlay"
---| "UIMouseClicked"
---| "UIMouseDoubleClick"
---| "UIMouseEnter"
---| "UIMouseLeave"
---| "UIMouseRealClick"
---| "UnhandledKey"
---| "UnknownResourceType"
---| "Update"
---| "UpdateSmoothing"
---| "UserStat"
---| "ViewBakeShadowMap"
---| "ViewBuffersReady"
---| "ViewChanged"
---| "ViewGlobalShaderParameters"
---| "VisibleChanged"
---| "VoxelAssemblyMemberDetached"
---| "VoxelAssemblyRootChanged"
---| "VoxelContact"
---| "VoxelContentReady"
---| "VoxelDamaged"
---| "VoxelFragmentFrozen"
---| "VoxelInitialSyncFinished"
---| "VoxelSevered"
---| "VoxelSyncFailed"
---| "WindowClosed"
---| "WindowPos"
---| "WorldPartitionReady"

-- =============================================================================
-- Event Data Type Definitions
-- =============================================================================
-- Each event has a specific EventData class that inherits from VariantMap
-- Fields are typed with precise VariantWithXXX types based on C++ type annotations
-- This provides compile-time type checking - e.g., VariantWithInt only has GetInt()

--- AnimationAllStoppingEvent event data
---@class AnimationAllStoppingEventEventData
---@field Node VariantWithPtr
---@field GetPtr fun(self: AnimationAllStoppingEventEventData, field: "Node"): AnimationState

--- AnimationControllerPostUpdate event data
---@class AnimationControllerPostUpdateEventData
---@field Node VariantWithPtr
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: AnimationControllerPostUpdateEventData, field: "TimeStep"): number
---@field GetPtr fun(self: AnimationControllerPostUpdateEventData, field: "Node"): Node

--- AnimationControllerPreUpdate event data
---@class AnimationControllerPreUpdateEventData
---@field Node VariantWithPtr
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: AnimationControllerPreUpdateEventData, field: "TimeStep"): number
---@field GetPtr fun(self: AnimationControllerPreUpdateEventData, field: "Node"): Node

--- AnimationFinished event data
---@class AnimationFinishedEventData
---@field Node VariantWithPtr
---@field Animation VariantWithPtr
---@field Name VariantWithString
---@field Looped VariantWithBool
---@field GetBool fun(self: AnimationFinishedEventData, field: "Looped"): boolean
---@field GetPtr fun(self: AnimationFinishedEventData, field: "Node"): Node
---@field GetPtr fun(self: AnimationFinishedEventData, field: "Animation"): Animation
---@field GetString fun(self: AnimationFinishedEventData, field: "Name"): string

--- AnimationFinishedEventEx event data
---@class AnimationFinishedEventExEventData
---@field Node VariantWithPtr
---@field State VariantWithPtr
---@field HandleHash VariantWithStringHash
---@field NameHash VariantWithStringHash
---@field Completed VariantWithBool
---@field Animation VariantWithPtr
---@field Name VariantWithString
---@field Looped VariantWithBool
---@field GetBool fun(self: AnimationFinishedEventExEventData, field: "Completed"): boolean
---@field GetBool fun(self: AnimationFinishedEventExEventData, field: "Looped"): boolean
---@field GetPtr fun(self: AnimationFinishedEventExEventData, field: "Node"): Node
---@field GetPtr fun(self: AnimationFinishedEventExEventData, field: "State"): AnimationState
---@field GetPtr fun(self: AnimationFinishedEventExEventData, field: "Animation"): Animation
---@field GetString fun(self: AnimationFinishedEventExEventData, field: "Name"): string
---@field GetStringHash fun(self: AnimationFinishedEventExEventData, field: "HandleHash"): StringHash
---@field GetStringHash fun(self: AnimationFinishedEventExEventData, field: "NameHash"): StringHash

--- AnimationSuppressedEvent event data
---@class AnimationSuppressedEventEventData
---@field Node VariantWithPtr
---@field HandleHash VariantWithStringHash
---@field NameHash VariantWithStringHash
---@field Occluded VariantWithBool
---@field GetBool fun(self: AnimationSuppressedEventEventData, field: "Occluded"): boolean
---@field GetPtr fun(self: AnimationSuppressedEventEventData, field: "Node"): Node
---@field GetStringHash fun(self: AnimationSuppressedEventEventData, field: "HandleHash"): StringHash
---@field GetStringHash fun(self: AnimationSuppressedEventEventData, field: "NameHash"): StringHash

--- AnimationTrigger event data
---@class AnimationTriggerEventData
---@field Node VariantWithPtr
---@field Animation VariantWithPtr
---@field Name VariantWithString
---@field Time VariantWithFloat
---@field Data Variant # user-defined animation trigger payload
---@field GetFloat fun(self: AnimationTriggerEventData, field: "Time"): number
---@field GetPtr fun(self: AnimationTriggerEventData, field: "Node"): Node
---@field GetPtr fun(self: AnimationTriggerEventData, field: "Animation"): Animation
---@field GetString fun(self: AnimationTriggerEventData, field: "Name"): string

--- AnimationUpdate event data
---@class AnimationUpdateEventData
---@field Scene VariantWithPtr
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: AnimationUpdateEventData, field: "TimeStep"): number
---@field GetPtr fun(self: AnimationUpdateEventData, field: "Scene"): Scene

--- AppDidEnterBackground event data
---@class AppDidEnterBackgroundEventData

--- AppDidEnterForebackground event data
---@class AppDidEnterForebackgroundEventData

--- AppLowMemory event data
---@class AppLowMemoryEventData

--- AppTerminating event data
---@class AppTerminatingEventData

--- AppWillEnterBackground event data
---@class AppWillEnterBackgroundEventData

--- AppWillEnterForeground event data
---@class AppWillEnterForegroundEventData

--- AsyncExecFinished event data
---@class AsyncExecFinishedEventData
---@field RequestID VariantWithInt
---@field ExitCode VariantWithInt
---@field GetInt fun(self: AsyncExecFinishedEventData, field: "RequestID"): integer
---@field GetInt fun(self: AsyncExecFinishedEventData, field: "ExitCode"): integer

--- AsyncLoadFinished event data
---@class AsyncLoadFinishedEventData
---@field Scene VariantWithPtr
---@field GetPtr fun(self: AsyncLoadFinishedEventData, field: "Scene"): Scene

--- AsyncLoadProgress event data
---@class AsyncLoadProgressEventData
---@field Scene VariantWithPtr
---@field Progress VariantWithFloat
---@field LoadedNodes VariantWithInt
---@field TotalNodes VariantWithInt
---@field LoadedResources VariantWithInt
---@field TotalResources VariantWithInt
---@field GetFloat fun(self: AsyncLoadProgressEventData, field: "Progress"): number
---@field GetInt fun(self: AsyncLoadProgressEventData, field: "LoadedNodes"): integer
---@field GetInt fun(self: AsyncLoadProgressEventData, field: "TotalNodes"): integer
---@field GetInt fun(self: AsyncLoadProgressEventData, field: "LoadedResources"): integer
---@field GetInt fun(self: AsyncLoadProgressEventData, field: "TotalResources"): integer
---@field GetPtr fun(self: AsyncLoadProgressEventData, field: "Scene"): Scene

--- AttributeAnimationAdded event data
---@class AttributeAnimationAddedEventData
---@field ObjectAnimation VariantWithPtr
---@field AttributeAnimationName VariantWithString
---@field GetPtr fun(self: AttributeAnimationAddedEventData, field: "ObjectAnimation"): ObjectAnimation
---@field GetString fun(self: AttributeAnimationAddedEventData, field: "AttributeAnimationName"): string

--- AttributeAnimationRemoved event data
---@class AttributeAnimationRemovedEventData
---@field ObjectAnimation VariantWithPtr
---@field AttributeAnimationName VariantWithString
---@field GetPtr fun(self: AttributeAnimationRemovedEventData, field: "ObjectAnimation"): ObjectAnimation
---@field GetString fun(self: AttributeAnimationRemovedEventData, field: "AttributeAnimationName"): string

--- AttributeAnimationUpdate event data
---@class AttributeAnimationUpdateEventData
---@field Scene VariantWithPtr
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: AttributeAnimationUpdateEventData, field: "TimeStep"): number
---@field GetPtr fun(self: AttributeAnimationUpdateEventData, field: "Scene"): Scene

--- BeforeBeginFrame event data
---@class BeforeBeginFrameEventData
---@field FrameNumber VariantWithInt
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: BeforeBeginFrameEventData, field: "TimeStep"): number
---@field GetInt fun(self: BeforeBeginFrameEventData, field: "FrameNumber"): integer

--- BeforeRestartGame event data
---@class BeforeRestartGameEventData

--- BeginAllViewRender event data
---@class BeginAllViewRenderEventData

--- BeginFrame event data
---@class BeginFrameEventData
---@field FrameNumber VariantWithInt
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: BeginFrameEventData, field: "TimeStep"): number
---@field GetInt fun(self: BeginFrameEventData, field: "FrameNumber"): integer

--- BeginRendering event data
---@class BeginRenderingEventData

--- BeginReplayFrame event data
---@class BeginReplayFrameEventData
---@field FrameNumber VariantWithInt
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: BeginReplayFrameEventData, field: "TimeStep"): number
---@field GetInt fun(self: BeginReplayFrameEventData, field: "FrameNumber"): integer

--- BeginViewRender event data
---@class BeginViewRenderEventData
---@field View VariantWithPtr
---@field Texture VariantWithPtr
---@field Surface VariantWithPtr
---@field Scene VariantWithPtr
---@field Camera VariantWithPtr
---@field GetPtr fun(self: BeginViewRenderEventData, field: "View"): View
---@field GetPtr fun(self: BeginViewRenderEventData, field: "Texture"): Texture
---@field GetPtr fun(self: BeginViewRenderEventData, field: "Surface"): RenderSurface
---@field GetPtr fun(self: BeginViewRenderEventData, field: "Scene"): Scene
---@field GetPtr fun(self: BeginViewRenderEventData, field: "Camera"): Camera

--- BeginViewUpdate event data
---@class BeginViewUpdateEventData
---@field View VariantWithPtr
---@field Texture VariantWithPtr
---@field Surface VariantWithPtr
---@field Scene VariantWithPtr
---@field Camera VariantWithPtr
---@field GetPtr fun(self: BeginViewUpdateEventData, field: "View"): View
---@field GetPtr fun(self: BeginViewUpdateEventData, field: "Texture"): Texture
---@field GetPtr fun(self: BeginViewUpdateEventData, field: "Surface"): RenderSurface
---@field GetPtr fun(self: BeginViewUpdateEventData, field: "Scene"): Scene
---@field GetPtr fun(self: BeginViewUpdateEventData, field: "Camera"): Camera

--- BoneHierarchyCreated event data
---@class BoneHierarchyCreatedEventData
---@field Node VariantWithPtr
---@field GetPtr fun(self: BoneHierarchyCreatedEventData, field: "Node"): Node

--- ChangeLanguage event data
---@class ChangeLanguageEventData

--- Click event data
---@class ClickEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: ClickEventData, field: "X"): integer
---@field GetInt fun(self: ClickEventData, field: "Y"): integer
---@field GetInt fun(self: ClickEventData, field: "Button"): integer
---@field GetInt fun(self: ClickEventData, field: "Buttons"): integer
---@field GetInt fun(self: ClickEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: ClickEventData, field: "Element"): UIElement

--- ClickEnd event data
---@class ClickEndEventData
---@field Element VariantWithPtr
---@field BeginElement VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: ClickEndEventData, field: "X"): integer
---@field GetInt fun(self: ClickEndEventData, field: "Y"): integer
---@field GetInt fun(self: ClickEndEventData, field: "Button"): integer
---@field GetInt fun(self: ClickEndEventData, field: "Buttons"): integer
---@field GetInt fun(self: ClickEndEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: ClickEndEventData, field: "Element"): UIElement
---@field GetPtr fun(self: ClickEndEventData, field: "BeginElement"): UIElement

--- ClientConnected event data
---@class ClientConnectedEventData
---@field Connection VariantWithPtr
---@field GetPtr fun(self: ClientConnectedEventData, field: "Connection"): Connection

--- ClientDisconnected event data
---@class ClientDisconnectedEventData
---@field Connection VariantWithPtr
---@field GetPtr fun(self: ClientDisconnectedEventData, field: "Connection"): Connection

--- ClientIdentity event data
---@class ClientIdentityEventData
---@field Connection VariantWithPtr
---@field Allow VariantWithBool
---@field GetBool fun(self: ClientIdentityEventData, field: "Allow"): boolean
---@field GetPtr fun(self: ClientIdentityEventData, field: "Connection"): Connection

--- ClientIdentityAccepted event data
---@class ClientIdentityAcceptedEventData
---@field Connection VariantWithPtr
---@field GetPtr fun(self: ClientIdentityAcceptedEventData, field: "Connection"): Connection

--- ClientSceneLoaded event data
---@class ClientSceneLoadedEventData
---@field Connection VariantWithPtr
---@field GetPtr fun(self: ClientSceneLoadedEventData, field: "Connection"): Connection

--- ComponentAdded event data
---@class ComponentAddedEventData
---@field Scene VariantWithPtr
---@field Node VariantWithPtr
---@field Component VariantWithPtr
---@field GetPtr fun(self: ComponentAddedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: ComponentAddedEventData, field: "Node"): Node
---@field GetPtr fun(self: ComponentAddedEventData, field: "Component"): Component

--- ComponentCloned event data
---@class ComponentClonedEventData
---@field Scene VariantWithPtr
---@field Component VariantWithPtr
---@field CloneComponent VariantWithPtr
---@field GetPtr fun(self: ComponentClonedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: ComponentClonedEventData, field: "Component"): Component
---@field GetPtr fun(self: ComponentClonedEventData, field: "CloneComponent"): Component

--- ComponentEnabledChanged event data
---@class ComponentEnabledChangedEventData
---@field Scene VariantWithPtr
---@field Node VariantWithPtr
---@field Component VariantWithPtr
---@field GetPtr fun(self: ComponentEnabledChangedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: ComponentEnabledChangedEventData, field: "Node"): Node
---@field GetPtr fun(self: ComponentEnabledChangedEventData, field: "Component"): Component

--- ComponentRemoved event data
---@class ComponentRemovedEventData
---@field Scene VariantWithPtr
---@field Node VariantWithPtr
---@field Component VariantWithPtr
---@field GetPtr fun(self: ComponentRemovedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: ComponentRemovedEventData, field: "Node"): Node
---@field GetPtr fun(self: ComponentRemovedEventData, field: "Component"): Component

--- ConnectFailed event data
---@class ConnectFailedEventData

--- ConsoleCommand event data
---@class ConsoleCommandEventData
---@field Command VariantWithString
---@field Id VariantWithString
---@field GetString fun(self: ConsoleCommandEventData, field: "Command"): string
---@field GetString fun(self: ConsoleCommandEventData, field: "Id"): string

--- CrowdAgentFailure event data
---@class CrowdAgentFailureEventData
---@field Node VariantWithPtr
---@field CrowdAgent VariantWithPtr
---@field Position VariantWithVector3
---@field Velocity VariantWithVector3
---@field CrowdAgentState VariantWithInt
---@field CrowdTargetState VariantWithInt
---@field GetInt fun(self: CrowdAgentFailureEventData, field: "CrowdAgentState"): integer
---@field GetInt fun(self: CrowdAgentFailureEventData, field: "CrowdTargetState"): integer
---@field GetPtr fun(self: CrowdAgentFailureEventData, field: "Node"): Node
---@field GetPtr fun(self: CrowdAgentFailureEventData, field: "CrowdAgent"): CrowdAgent
---@field GetVector3 fun(self: CrowdAgentFailureEventData, field: "Position"): Vector3
---@field GetVector3 fun(self: CrowdAgentFailureEventData, field: "Velocity"): Vector3

--- CrowdAgentFormation event data
---@class CrowdAgentFormationEventData
---@field Node VariantWithPtr
---@field CrowdAgent VariantWithPtr
---@field Index VariantWithInt
---@field Size VariantWithInt
---@field Position VariantWithVector3 # in/out
---@field GetInt fun(self: CrowdAgentFormationEventData, field: "Index"): integer
---@field GetInt fun(self: CrowdAgentFormationEventData, field: "Size"): integer
---@field GetPtr fun(self: CrowdAgentFormationEventData, field: "Node"): Node
---@field GetPtr fun(self: CrowdAgentFormationEventData, field: "CrowdAgent"): CrowdAgent
---@field GetVector3 fun(self: CrowdAgentFormationEventData, field: "Position"): Vector3

--- CrowdAgentNodeFailure event data
---@class CrowdAgentNodeFailureEventData
---@field Node VariantWithPtr
---@field CrowdAgent VariantWithPtr
---@field Position VariantWithVector3
---@field Velocity VariantWithVector3
---@field CrowdAgentState VariantWithInt
---@field CrowdTargetState VariantWithInt
---@field GetInt fun(self: CrowdAgentNodeFailureEventData, field: "CrowdAgentState"): integer
---@field GetInt fun(self: CrowdAgentNodeFailureEventData, field: "CrowdTargetState"): integer
---@field GetPtr fun(self: CrowdAgentNodeFailureEventData, field: "Node"): Node
---@field GetPtr fun(self: CrowdAgentNodeFailureEventData, field: "CrowdAgent"): CrowdAgent
---@field GetVector3 fun(self: CrowdAgentNodeFailureEventData, field: "Position"): Vector3
---@field GetVector3 fun(self: CrowdAgentNodeFailureEventData, field: "Velocity"): Vector3

--- CrowdAgentNodeFormation event data
---@class CrowdAgentNodeFormationEventData
---@field Node VariantWithPtr
---@field CrowdAgent VariantWithPtr
---@field Index VariantWithInt
---@field Size VariantWithInt
---@field Position VariantWithVector3 # in/out
---@field GetInt fun(self: CrowdAgentNodeFormationEventData, field: "Index"): integer
---@field GetInt fun(self: CrowdAgentNodeFormationEventData, field: "Size"): integer
---@field GetPtr fun(self: CrowdAgentNodeFormationEventData, field: "Node"): Node
---@field GetPtr fun(self: CrowdAgentNodeFormationEventData, field: "CrowdAgent"): CrowdAgent
---@field GetVector3 fun(self: CrowdAgentNodeFormationEventData, field: "Position"): Vector3

--- CrowdAgentNodeReposition event data
---@class CrowdAgentNodeRepositionEventData
---@field Node VariantWithPtr
---@field CrowdAgent VariantWithPtr
---@field Position VariantWithVector3
---@field Velocity VariantWithVector3
---@field Arrived VariantWithBool
---@field TimeStep VariantWithFloat
---@field GetBool fun(self: CrowdAgentNodeRepositionEventData, field: "Arrived"): boolean
---@field GetFloat fun(self: CrowdAgentNodeRepositionEventData, field: "TimeStep"): number
---@field GetPtr fun(self: CrowdAgentNodeRepositionEventData, field: "Node"): Node
---@field GetPtr fun(self: CrowdAgentNodeRepositionEventData, field: "CrowdAgent"): CrowdAgent
---@field GetVector3 fun(self: CrowdAgentNodeRepositionEventData, field: "Position"): Vector3
---@field GetVector3 fun(self: CrowdAgentNodeRepositionEventData, field: "Velocity"): Vector3

--- CrowdAgentNodeStateChanged event data
---@class CrowdAgentNodeStateChangedEventData
---@field Node VariantWithPtr
---@field CrowdAgent VariantWithPtr
---@field Position VariantWithVector3
---@field Velocity VariantWithVector3
---@field CrowdAgentState VariantWithInt
---@field CrowdTargetState VariantWithInt
---@field GetInt fun(self: CrowdAgentNodeStateChangedEventData, field: "CrowdAgentState"): integer
---@field GetInt fun(self: CrowdAgentNodeStateChangedEventData, field: "CrowdTargetState"): integer
---@field GetPtr fun(self: CrowdAgentNodeStateChangedEventData, field: "Node"): Node
---@field GetPtr fun(self: CrowdAgentNodeStateChangedEventData, field: "CrowdAgent"): CrowdAgent
---@field GetVector3 fun(self: CrowdAgentNodeStateChangedEventData, field: "Position"): Vector3
---@field GetVector3 fun(self: CrowdAgentNodeStateChangedEventData, field: "Velocity"): Vector3

--- CrowdAgentReposition event data
---@class CrowdAgentRepositionEventData
---@field Node VariantWithPtr
---@field CrowdAgent VariantWithPtr
---@field Position VariantWithVector3
---@field Velocity VariantWithVector3
---@field Arrived VariantWithBool
---@field TimeStep VariantWithFloat
---@field GetBool fun(self: CrowdAgentRepositionEventData, field: "Arrived"): boolean
---@field GetFloat fun(self: CrowdAgentRepositionEventData, field: "TimeStep"): number
---@field GetPtr fun(self: CrowdAgentRepositionEventData, field: "Node"): Node
---@field GetPtr fun(self: CrowdAgentRepositionEventData, field: "CrowdAgent"): CrowdAgent
---@field GetVector3 fun(self: CrowdAgentRepositionEventData, field: "Position"): Vector3
---@field GetVector3 fun(self: CrowdAgentRepositionEventData, field: "Velocity"): Vector3

--- CrowdAgentStateChanged event data
---@class CrowdAgentStateChangedEventData
---@field Node VariantWithPtr
---@field CrowdAgent VariantWithPtr
---@field Position VariantWithVector3
---@field Velocity VariantWithVector3
---@field CrowdAgentState VariantWithInt
---@field CrowdTargetState VariantWithInt
---@field GetInt fun(self: CrowdAgentStateChangedEventData, field: "CrowdAgentState"): integer
---@field GetInt fun(self: CrowdAgentStateChangedEventData, field: "CrowdTargetState"): integer
---@field GetPtr fun(self: CrowdAgentStateChangedEventData, field: "Node"): Node
---@field GetPtr fun(self: CrowdAgentStateChangedEventData, field: "CrowdAgent"): CrowdAgent
---@field GetVector3 fun(self: CrowdAgentStateChangedEventData, field: "Position"): Vector3
---@field GetVector3 fun(self: CrowdAgentStateChangedEventData, field: "Velocity"): Vector3

--- CustomValue event data
---@class CustomValueEventData

--- DbCursor event data
---@class DbCursorEventData
---@field DbConnection VariantWithPtr
---@field SQL VariantWithString
---@field NumCols VariantWithInt
---@field ColValues VariantWithVariantVector
---@field ColHeaders VariantWithStringVector
---@field Filter VariantWithBool # in
---@field Abort VariantWithBool # in
---@field GetBool fun(self: DbCursorEventData, field: "Filter"): boolean
---@field GetBool fun(self: DbCursorEventData, field: "Abort"): boolean
---@field GetInt fun(self: DbCursorEventData, field: "NumCols"): integer
---@field GetPtr fun(self: DbCursorEventData, field: "DbConnection"): DbConnection
---@field GetString fun(self: DbCursorEventData, field: "SQL"): string
---@field GetStringVector fun(self: DbCursorEventData, field: "ColHeaders"): string[]
---@field GetVariantVector fun(self: DbCursorEventData, field: "ColValues"): Variant[]

--- Defocused event data
---@class DefocusedEventData
---@field Element VariantWithPtr
---@field GetPtr fun(self: DefocusedEventData, field: "Element"): UIElement

--- DeviceLost event data
---@class DeviceLostEventData

--- DeviceReset event data
---@class DeviceResetEventData

--- DiskQuotaExceeded event data
---@class DiskQuotaExceededEventData
---@field Path VariantWithString
---@field GetString fun(self: DiskQuotaExceededEventData, field: "Path"): string

--- DoubleClick event data
---@class DoubleClickEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field XBegin VariantWithInt
---@field YBegin VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: DoubleClickEventData, field: "X"): integer
---@field GetInt fun(self: DoubleClickEventData, field: "Y"): integer
---@field GetInt fun(self: DoubleClickEventData, field: "XBegin"): integer
---@field GetInt fun(self: DoubleClickEventData, field: "YBegin"): integer
---@field GetInt fun(self: DoubleClickEventData, field: "Button"): integer
---@field GetInt fun(self: DoubleClickEventData, field: "Buttons"): integer
---@field GetInt fun(self: DoubleClickEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: DoubleClickEventData, field: "Element"): UIElement

--- DragBegin event data
---@class DragBeginEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field ElementX VariantWithInt
---@field ElementY VariantWithInt
---@field Buttons VariantWithInt
---@field NumButtons VariantWithInt
---@field GetInt fun(self: DragBeginEventData, field: "X"): integer
---@field GetInt fun(self: DragBeginEventData, field: "Y"): integer
---@field GetInt fun(self: DragBeginEventData, field: "ElementX"): integer
---@field GetInt fun(self: DragBeginEventData, field: "ElementY"): integer
---@field GetInt fun(self: DragBeginEventData, field: "Buttons"): integer
---@field GetInt fun(self: DragBeginEventData, field: "NumButtons"): integer
---@field GetPtr fun(self: DragBeginEventData, field: "Element"): UIElement

--- DragCancel event data
---@class DragCancelEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field ElementX VariantWithInt
---@field ElementY VariantWithInt
---@field Buttons VariantWithInt
---@field NumButtons VariantWithInt
---@field GetInt fun(self: DragCancelEventData, field: "X"): integer
---@field GetInt fun(self: DragCancelEventData, field: "Y"): integer
---@field GetInt fun(self: DragCancelEventData, field: "ElementX"): integer
---@field GetInt fun(self: DragCancelEventData, field: "ElementY"): integer
---@field GetInt fun(self: DragCancelEventData, field: "Buttons"): integer
---@field GetInt fun(self: DragCancelEventData, field: "NumButtons"): integer
---@field GetPtr fun(self: DragCancelEventData, field: "Element"): UIElement

--- DragDropFinish event data
---@class DragDropFinishEventData
---@field Source VariantWithPtr
---@field Target VariantWithPtr
---@field Accept VariantWithBool
---@field GetBool fun(self: DragDropFinishEventData, field: "Accept"): boolean
---@field GetPtr fun(self: DragDropFinishEventData, field: "Source"): UIElement
---@field GetPtr fun(self: DragDropFinishEventData, field: "Target"): UIElement

--- DragDropTest event data
---@class DragDropTestEventData
---@field Source VariantWithPtr
---@field Target VariantWithPtr
---@field Accept VariantWithBool
---@field GetBool fun(self: DragDropTestEventData, field: "Accept"): boolean
---@field GetPtr fun(self: DragDropTestEventData, field: "Source"): UIElement
---@field GetPtr fun(self: DragDropTestEventData, field: "Target"): UIElement

--- DragEnd event data
---@class DragEndEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field ElementX VariantWithInt
---@field ElementY VariantWithInt
---@field Buttons VariantWithInt
---@field NumButtons VariantWithInt
---@field GetInt fun(self: DragEndEventData, field: "X"): integer
---@field GetInt fun(self: DragEndEventData, field: "Y"): integer
---@field GetInt fun(self: DragEndEventData, field: "ElementX"): integer
---@field GetInt fun(self: DragEndEventData, field: "ElementY"): integer
---@field GetInt fun(self: DragEndEventData, field: "Buttons"): integer
---@field GetInt fun(self: DragEndEventData, field: "NumButtons"): integer
---@field GetPtr fun(self: DragEndEventData, field: "Element"): UIElement

--- DragMove event data
---@class DragMoveEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field DX VariantWithInt
---@field DY VariantWithInt
---@field ElementX VariantWithInt
---@field ElementY VariantWithInt
---@field Buttons VariantWithInt
---@field NumButtons VariantWithInt
---@field GetInt fun(self: DragMoveEventData, field: "X"): integer
---@field GetInt fun(self: DragMoveEventData, field: "Y"): integer
---@field GetInt fun(self: DragMoveEventData, field: "DX"): integer
---@field GetInt fun(self: DragMoveEventData, field: "DY"): integer
---@field GetInt fun(self: DragMoveEventData, field: "ElementX"): integer
---@field GetInt fun(self: DragMoveEventData, field: "ElementY"): integer
---@field GetInt fun(self: DragMoveEventData, field: "Buttons"): integer
---@field GetInt fun(self: DragMoveEventData, field: "NumButtons"): integer
---@field GetPtr fun(self: DragMoveEventData, field: "Element"): UIElement

--- DrawableBatchesChanged event data
---@class DrawableBatchesChangedEventData
---@field Drawable VariantWithPtr
---@field GetPtr fun(self: DrawableBatchesChangedEventData, field: "Drawable"): Drawable

--- DropFile event data
---@class DropFileEventData
---@field FileName VariantWithString
---@field GetString fun(self: DropFileEventData, field: "FileName"): string

--- DumpTest event data
---@class DumpTestEventData

--- ElementAdded event data
---@class ElementAddedEventData
---@field Root VariantWithPtr
---@field Parent VariantWithPtr
---@field Element VariantWithPtr
---@field GetPtr fun(self: ElementAddedEventData, field: "Root"): UIElement
---@field GetPtr fun(self: ElementAddedEventData, field: "Parent"): UIElement
---@field GetPtr fun(self: ElementAddedEventData, field: "Element"): UIElement

--- ElementRemoved event data
---@class ElementRemovedEventData
---@field Root VariantWithPtr
---@field Parent VariantWithPtr
---@field Element VariantWithPtr
---@field GetPtr fun(self: ElementRemovedEventData, field: "Root"): UIElement
---@field GetPtr fun(self: ElementRemovedEventData, field: "Parent"): UIElement
---@field GetPtr fun(self: ElementRemovedEventData, field: "Element"): UIElement

--- EndAllViewsRender event data
---@class EndAllViewsRenderEventData

--- EndFrame event data
---@class EndFrameEventData

--- EndRendering event data
---@class EndRenderingEventData

--- EndViewRender event data
---@class EndViewRenderEventData
---@field View VariantWithPtr
---@field Texture VariantWithPtr
---@field Surface VariantWithPtr
---@field Scene VariantWithPtr
---@field Camera VariantWithPtr
---@field GetPtr fun(self: EndViewRenderEventData, field: "View"): View
---@field GetPtr fun(self: EndViewRenderEventData, field: "Texture"): Texture
---@field GetPtr fun(self: EndViewRenderEventData, field: "Surface"): RenderSurface
---@field GetPtr fun(self: EndViewRenderEventData, field: "Scene"): Scene
---@field GetPtr fun(self: EndViewRenderEventData, field: "Camera"): Camera

--- EndViewUpdate event data
---@class EndViewUpdateEventData
---@field View VariantWithPtr
---@field Texture VariantWithPtr
---@field Surface VariantWithPtr
---@field Scene VariantWithPtr
---@field Camera VariantWithPtr
---@field GetPtr fun(self: EndViewUpdateEventData, field: "View"): View
---@field GetPtr fun(self: EndViewUpdateEventData, field: "Texture"): Texture
---@field GetPtr fun(self: EndViewUpdateEventData, field: "Surface"): RenderSurface
---@field GetPtr fun(self: EndViewUpdateEventData, field: "Scene"): Scene
---@field GetPtr fun(self: EndViewUpdateEventData, field: "Camera"): Camera

--- ExitRequested event data
---@class ExitRequestedEventData

--- FileChanged event data
---@class FileChangedEventData
---@field FileName VariantWithString
---@field ResourceName VariantWithString
---@field GetString fun(self: FileChangedEventData, field: "FileName"): string
---@field GetString fun(self: FileChangedEventData, field: "ResourceName"): string

--- FileSelected event data
---@class FileSelectedEventData
---@field FileName VariantWithString
---@field Filter VariantWithString
---@field OK VariantWithBool
---@field GetBool fun(self: FileSelectedEventData, field: "OK"): boolean
---@field GetString fun(self: FileSelectedEventData, field: "FileName"): string
---@field GetString fun(self: FileSelectedEventData, field: "Filter"): string

--- FinishResources event data
---@class FinishResourcesEventData

--- FocusChanged event data
---@class FocusChangedEventData
---@field Element VariantWithPtr
---@field ClickedElement VariantWithPtr
---@field GetPtr fun(self: FocusChangedEventData, field: "Element"): UIElement
---@field GetPtr fun(self: FocusChangedEventData, field: "ClickedElement"): UIElement

--- Focused event data
---@class FocusedEventData
---@field Element VariantWithPtr
---@field ByKey VariantWithBool
---@field GetBool fun(self: FocusedEventData, field: "ByKey"): boolean
---@field GetPtr fun(self: FocusedEventData, field: "Element"): UIElement

--- GPUHandleChanged event data
---@class GPUHandleChangedEventData

--- GameSessionStarted event data
---@class GameSessionStartedEventData
---@field IsReconnect VariantWithBool
---@field SessionId VariantWithString
---@field GetBool fun(self: GameSessionStartedEventData, field: "IsReconnect"): boolean
---@field GetString fun(self: GameSessionStartedEventData, field: "SessionId"): string

--- GestureInput event data
---@class GestureInputEventData
---@field GestureID VariantWithInt
---@field CenterX VariantWithInt
---@field CenterY VariantWithInt
---@field NumFingers VariantWithInt
---@field Error VariantWithFloat
---@field GetFloat fun(self: GestureInputEventData, field: "Error"): number
---@field GetInt fun(self: GestureInputEventData, field: "GestureID"): integer
---@field GetInt fun(self: GestureInputEventData, field: "CenterX"): integer
---@field GetInt fun(self: GestureInputEventData, field: "CenterY"): integer
---@field GetInt fun(self: GestureInputEventData, field: "NumFingers"): integer

--- GestureRecorded event data
---@class GestureRecordedEventData
---@field GestureID VariantWithInt
---@field GetInt fun(self: GestureRecordedEventData, field: "GestureID"): integer

--- HoverBegin event data
---@class HoverBeginEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field ElementX VariantWithInt
---@field ElementY VariantWithInt
---@field GetInt fun(self: HoverBeginEventData, field: "X"): integer
---@field GetInt fun(self: HoverBeginEventData, field: "Y"): integer
---@field GetInt fun(self: HoverBeginEventData, field: "ElementX"): integer
---@field GetInt fun(self: HoverBeginEventData, field: "ElementY"): integer
---@field GetPtr fun(self: HoverBeginEventData, field: "Element"): UIElement

--- HoverEnd event data
---@class HoverEndEventData
---@field Element VariantWithPtr
---@field GetPtr fun(self: HoverEndEventData, field: "Element"): UIElement

--- IKEffectorTargetChanged event data
---@class IKEffectorTargetChangedEventData
---@field EffectorNode VariantWithPtr # The effector node that has changed targets
---@field TargetNode VariantWithPtr # The new target node. NOTE: Can be NULL (means no target)
---@field GetPtr fun(self: IKEffectorTargetChangedEventData, field: "EffectorNode"): Node
---@field GetPtr fun(self: IKEffectorTargetChangedEventData, field: "TargetNode"): Node

--- InputBegin event data
---@class InputBeginEventData

--- InputEnd event data
---@class InputEndEventData

--- InputFocus event data
---@class InputFocusEventData
---@field Focus VariantWithBool
---@field Minimized VariantWithBool
---@field GetBool fun(self: InputFocusEventData, field: "Focus"): boolean
---@field GetBool fun(self: InputFocusEventData, field: "Minimized"): boolean

--- InterceptNetworkUpdate event data
---@class InterceptNetworkUpdateEventData
---@field Serializable VariantWithPtr
---@field TimeStamp VariantWithInt # 0-255
---@field Index VariantWithInt
---@field Name VariantWithString
---@field Value Variant
---@field GetInt fun(self: InterceptNetworkUpdateEventData, field: "TimeStamp"): integer
---@field GetInt fun(self: InterceptNetworkUpdateEventData, field: "Index"): integer
---@field GetPtr fun(self: InterceptNetworkUpdateEventData, field: "Serializable"): Serializable
---@field GetString fun(self: InterceptNetworkUpdateEventData, field: "Name"): string

--- ItemClicked event data
---@class ItemClickedEventData
---@field Element VariantWithPtr
---@field Item VariantWithPtr
---@field Selection VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: ItemClickedEventData, field: "Selection"): integer
---@field GetInt fun(self: ItemClickedEventData, field: "Button"): integer
---@field GetInt fun(self: ItemClickedEventData, field: "Buttons"): integer
---@field GetInt fun(self: ItemClickedEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: ItemClickedEventData, field: "Element"): UIElement
---@field GetPtr fun(self: ItemClickedEventData, field: "Item"): UIElement

--- ItemDeselected event data
---@class ItemDeselectedEventData
---@field Element VariantWithPtr
---@field Selection VariantWithInt
---@field GetInt fun(self: ItemDeselectedEventData, field: "Selection"): integer
---@field GetPtr fun(self: ItemDeselectedEventData, field: "Element"): UIElement

--- ItemDoubleClicked event data
---@class ItemDoubleClickedEventData
---@field Element VariantWithPtr
---@field Item VariantWithPtr
---@field Selection VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: ItemDoubleClickedEventData, field: "Selection"): integer
---@field GetInt fun(self: ItemDoubleClickedEventData, field: "Button"): integer
---@field GetInt fun(self: ItemDoubleClickedEventData, field: "Buttons"): integer
---@field GetInt fun(self: ItemDoubleClickedEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: ItemDoubleClickedEventData, field: "Element"): UIElement
---@field GetPtr fun(self: ItemDoubleClickedEventData, field: "Item"): UIElement

--- ItemSelected event data
---@class ItemSelectedEventData
---@field Element VariantWithPtr
---@field Selection VariantWithInt
---@field GetInt fun(self: ItemSelectedEventData, field: "Selection"): integer
---@field GetPtr fun(self: ItemSelectedEventData, field: "Element"): UIElement

--- JoystickAxisMove event data
---@class JoystickAxisMoveEventData
---@field JoystickID VariantWithInt
---@field Button VariantWithInt
---@field Position VariantWithFloat
---@field GetFloat fun(self: JoystickAxisMoveEventData, field: "Position"): number
---@field GetInt fun(self: JoystickAxisMoveEventData, field: "JoystickID"): integer
---@field GetInt fun(self: JoystickAxisMoveEventData, field: "Button"): integer

--- JoystickButtonDown event data
---@class JoystickButtonDownEventData
---@field JoystickID VariantWithInt
---@field Button VariantWithInt
---@field GetInt fun(self: JoystickButtonDownEventData, field: "JoystickID"): integer
---@field GetInt fun(self: JoystickButtonDownEventData, field: "Button"): integer

--- JoystickButtonUp event data
---@class JoystickButtonUpEventData
---@field JoystickID VariantWithInt
---@field Button VariantWithInt
---@field GetInt fun(self: JoystickButtonUpEventData, field: "JoystickID"): integer
---@field GetInt fun(self: JoystickButtonUpEventData, field: "Button"): integer

--- JoystickConnected event data
---@class JoystickConnectedEventData
---@field JoystickID VariantWithInt
---@field GetInt fun(self: JoystickConnectedEventData, field: "JoystickID"): integer

--- JoystickDisconnected event data
---@class JoystickDisconnectedEventData
---@field JoystickID VariantWithInt
---@field GetInt fun(self: JoystickDisconnectedEventData, field: "JoystickID"): integer

--- JoystickHatMove event data
---@class JoystickHatMoveEventData
---@field JoystickID VariantWithInt
---@field Button VariantWithInt
---@field Position VariantWithInt
---@field GetInt fun(self: JoystickHatMoveEventData, field: "JoystickID"): integer
---@field GetInt fun(self: JoystickHatMoveEventData, field: "Button"): integer
---@field GetInt fun(self: JoystickHatMoveEventData, field: "Position"): integer

--- KeyDown event data
---@class KeyDownEventData
---@field Key VariantWithInt
---@field Scancode VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field Repeat VariantWithBool
---@field GetBool fun(self: KeyDownEventData, field: "Repeat"): boolean
---@field GetInt fun(self: KeyDownEventData, field: "Key"): integer
---@field GetInt fun(self: KeyDownEventData, field: "Scancode"): integer
---@field GetInt fun(self: KeyDownEventData, field: "Buttons"): integer
---@field GetInt fun(self: KeyDownEventData, field: "Qualifiers"): integer

--- KeyUp event data
---@class KeyUpEventData
---@field Key VariantWithInt
---@field Scancode VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: KeyUpEventData, field: "Key"): integer
---@field GetInt fun(self: KeyUpEventData, field: "Scancode"): integer
---@field GetInt fun(self: KeyUpEventData, field: "Buttons"): integer
---@field GetInt fun(self: KeyUpEventData, field: "Qualifiers"): integer

--- LayoutUpdated event data
---@class LayoutUpdatedEventData
---@field Element VariantWithPtr
---@field GetPtr fun(self: LayoutUpdatedEventData, field: "Element"): UIElement

--- LoadFailed event data
---@class LoadFailedEventData
---@field ResourceName VariantWithString
---@field GetString fun(self: LoadFailedEventData, field: "ResourceName"): string

--- LogMessage event data
---@class LogMessageEventData
---@field Message VariantWithString
---@field Level VariantWithInt
---@field CustomLog VariantWithString # optional: "lua"/"game"/empty for engine
---@field GetInt fun(self: LogMessageEventData, field: "Level"): integer
---@field GetString fun(self: LogMessageEventData, field: "Message"): string
---@field GetString fun(self: LogMessageEventData, field: "CustomLog"): string

--- MenuSelected event data
---@class MenuSelectedEventData
---@field Element VariantWithPtr
---@field GetPtr fun(self: MenuSelectedEventData, field: "Element"): UIElement

--- MergeLight event data
---@class MergeLightEventData

--- MessageACK event data
---@class MessageACKEventData
---@field OK VariantWithBool
---@field GetBool fun(self: MessageACKEventData, field: "OK"): boolean

--- ModalChanged event data
---@class ModalChangedEventData
---@field Element VariantWithPtr
---@field Modal VariantWithBool
---@field GetBool fun(self: ModalChangedEventData, field: "Modal"): boolean
---@field GetPtr fun(self: ModalChangedEventData, field: "Element"): UIElement

--- MouseButtonDown event data
---@class MouseButtonDownEventData
---@field X VariantWithInt # only when mouse visible
---@field Y VariantWithInt # only when mouse visible
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: MouseButtonDownEventData, field: "X"): integer
---@field GetInt fun(self: MouseButtonDownEventData, field: "Y"): integer
---@field GetInt fun(self: MouseButtonDownEventData, field: "Button"): integer
---@field GetInt fun(self: MouseButtonDownEventData, field: "Buttons"): integer
---@field GetInt fun(self: MouseButtonDownEventData, field: "Qualifiers"): integer

--- MouseButtonUp event data
---@class MouseButtonUpEventData
---@field X VariantWithInt # only when mouse visible
---@field Y VariantWithInt # only when mouse visible
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: MouseButtonUpEventData, field: "X"): integer
---@field GetInt fun(self: MouseButtonUpEventData, field: "Y"): integer
---@field GetInt fun(self: MouseButtonUpEventData, field: "Button"): integer
---@field GetInt fun(self: MouseButtonUpEventData, field: "Buttons"): integer
---@field GetInt fun(self: MouseButtonUpEventData, field: "Qualifiers"): integer

--- MouseModeChanged event data
---@class MouseModeChangedEventData
---@field Mode VariantWithInt # MouseMode: MM_ABSOLUTE/MM_RELATIVE/MM_WRAP/MM_FREE
---@field MouseLocked VariantWithBool
---@field GetBool fun(self: MouseModeChangedEventData, field: "MouseLocked"): boolean
---@field GetInt fun(self: MouseModeChangedEventData, field: "Mode"): integer

--- MouseMove event data
---@class MouseMoveEventData
---@field X VariantWithInt # only when mouse visible
---@field Y VariantWithInt # only when mouse visible
---@field DX VariantWithInt
---@field DY VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: MouseMoveEventData, field: "X"): integer
---@field GetInt fun(self: MouseMoveEventData, field: "Y"): integer
---@field GetInt fun(self: MouseMoveEventData, field: "DX"): integer
---@field GetInt fun(self: MouseMoveEventData, field: "DY"): integer
---@field GetInt fun(self: MouseMoveEventData, field: "Buttons"): integer
---@field GetInt fun(self: MouseMoveEventData, field: "Qualifiers"): integer

--- MouseVisibleChanged event data
---@class MouseVisibleChangedEventData
---@field Visible VariantWithBool
---@field GetBool fun(self: MouseVisibleChangedEventData, field: "Visible"): boolean

--- MouseWheel event data
---@class MouseWheelEventData
---@field Wheel VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: MouseWheelEventData, field: "Wheel"): integer
---@field GetInt fun(self: MouseWheelEventData, field: "Buttons"): integer
---@field GetInt fun(self: MouseWheelEventData, field: "Qualifiers"): integer

--- MultiGesture event data
---@class MultiGestureEventData
---@field CenterX VariantWithInt
---@field CenterY VariantWithInt
---@field NumFingers VariantWithInt
---@field DTheta VariantWithFloat # degrees
---@field DDist VariantWithFloat
---@field GetFloat fun(self: MultiGestureEventData, field: "DTheta"): number
---@field GetFloat fun(self: MultiGestureEventData, field: "DDist"): number
---@field GetInt fun(self: MultiGestureEventData, field: "CenterX"): integer
---@field GetInt fun(self: MultiGestureEventData, field: "CenterY"): integer
---@field GetInt fun(self: MultiGestureEventData, field: "NumFingers"): integer

--- NameChanged event data
---@class NameChangedEventData
---@field Element VariantWithPtr
---@field GetPtr fun(self: NameChangedEventData, field: "Element"): UIElement

--- NanoVGRender event data
---@class NanoVGRenderEventData

--- NavigationAllTilesRemoved event data
---@class NavigationAllTilesRemovedEventData
---@field Node VariantWithPtr
---@field Mesh VariantWithPtr
---@field GetPtr fun(self: NavigationAllTilesRemovedEventData, field: "Node"): Node
---@field GetPtr fun(self: NavigationAllTilesRemovedEventData, field: "Mesh"): NavigationMesh

--- NavigationAreaRebuilt event data
---@class NavigationAreaRebuiltEventData
---@field Node VariantWithPtr
---@field Mesh VariantWithPtr
---@field BoundsMin VariantWithVector3
---@field BoundsMax VariantWithVector3
---@field GetPtr fun(self: NavigationAreaRebuiltEventData, field: "Node"): Node
---@field GetPtr fun(self: NavigationAreaRebuiltEventData, field: "Mesh"): NavigationMesh
---@field GetVector3 fun(self: NavigationAreaRebuiltEventData, field: "BoundsMin"): Vector3
---@field GetVector3 fun(self: NavigationAreaRebuiltEventData, field: "BoundsMax"): Vector3

--- NavigationMeshRebuilt event data
---@class NavigationMeshRebuiltEventData
---@field Node VariantWithPtr
---@field Mesh VariantWithPtr
---@field GetPtr fun(self: NavigationMeshRebuiltEventData, field: "Node"): Node
---@field GetPtr fun(self: NavigationMeshRebuiltEventData, field: "Mesh"): NavigationMesh

--- NavigationObstacleAdded event data
---@class NavigationObstacleAddedEventData
---@field Node VariantWithPtr
---@field Obstacle VariantWithPtr
---@field Position VariantWithVector3
---@field Radius VariantWithFloat
---@field Height VariantWithFloat
---@field GetFloat fun(self: NavigationObstacleAddedEventData, field: "Radius"): number
---@field GetFloat fun(self: NavigationObstacleAddedEventData, field: "Height"): number
---@field GetPtr fun(self: NavigationObstacleAddedEventData, field: "Node"): Node
---@field GetPtr fun(self: NavigationObstacleAddedEventData, field: "Obstacle"): Obstacle
---@field GetVector3 fun(self: NavigationObstacleAddedEventData, field: "Position"): Vector3

--- NavigationObstacleRemoved event data
---@class NavigationObstacleRemovedEventData
---@field Node VariantWithPtr
---@field Obstacle VariantWithPtr
---@field Position VariantWithVector3
---@field Radius VariantWithFloat
---@field Height VariantWithFloat
---@field GetFloat fun(self: NavigationObstacleRemovedEventData, field: "Radius"): number
---@field GetFloat fun(self: NavigationObstacleRemovedEventData, field: "Height"): number
---@field GetPtr fun(self: NavigationObstacleRemovedEventData, field: "Node"): Node
---@field GetPtr fun(self: NavigationObstacleRemovedEventData, field: "Obstacle"): Obstacle
---@field GetVector3 fun(self: NavigationObstacleRemovedEventData, field: "Position"): Vector3

--- NavigationTileAdded event data
---@class NavigationTileAddedEventData
---@field Node VariantWithPtr
---@field Mesh VariantWithPtr
---@field Tile VariantWithIntVector2
---@field GetIntVector2 fun(self: NavigationTileAddedEventData, field: "Tile"): IntVector2
---@field GetPtr fun(self: NavigationTileAddedEventData, field: "Node"): Node
---@field GetPtr fun(self: NavigationTileAddedEventData, field: "Mesh"): NavigationMesh

--- NavigationTileRemoved event data
---@class NavigationTileRemovedEventData
---@field Node VariantWithPtr
---@field Mesh VariantWithPtr
---@field Tile VariantWithIntVector2
---@field GetIntVector2 fun(self: NavigationTileRemovedEventData, field: "Tile"): IntVector2
---@field GetPtr fun(self: NavigationTileRemovedEventData, field: "Node"): Node
---@field GetPtr fun(self: NavigationTileRemovedEventData, field: "Mesh"): NavigationMesh

--- NetworkBanned event data
---@class NetworkBannedEventData

--- NetworkHostDiscovered event data
---@class NetworkHostDiscoveredEventData
---@field Address VariantWithString
---@field Port VariantWithInt
---@field Beacon VariantWithVariantMap
---@field GetInt fun(self: NetworkHostDiscoveredEventData, field: "Port"): integer
---@field GetString fun(self: NetworkHostDiscoveredEventData, field: "Address"): string
---@field GetVariantMap fun(self: NetworkHostDiscoveredEventData, field: "Beacon"): VariantMap|nil

--- NetworkInvalidPassword event data
---@class NetworkInvalidPasswordEventData

--- NetworkMessage event data
---@class NetworkMessageEventData
---@field Connection VariantWithPtr
---@field MessageID VariantWithInt
---@field Data VariantWithBuffer
---@field GetBuffer fun(self: NetworkMessageEventData, field: "Data"): VectorBuffer
---@field GetInt fun(self: NetworkMessageEventData, field: "MessageID"): integer
---@field GetPtr fun(self: NetworkMessageEventData, field: "Connection"): Connection

--- NetworkNatMasterConnectionFailed event data
---@class NetworkNatMasterConnectionFailedEventData
---@field Address VariantWithString
---@field Port VariantWithInt
---@field GetInt fun(self: NetworkNatMasterConnectionFailedEventData, field: "Port"): integer
---@field GetString fun(self: NetworkNatMasterConnectionFailedEventData, field: "Address"): string

--- NetworkNatMasterConnectionSucceeded event data
---@class NetworkNatMasterConnectionSucceededEventData
---@field Address VariantWithString
---@field Port VariantWithInt
---@field GetInt fun(self: NetworkNatMasterConnectionSucceededEventData, field: "Port"): integer
---@field GetString fun(self: NetworkNatMasterConnectionSucceededEventData, field: "Address"): string

--- NetworkNatPunchtroughFailed event data
---@class NetworkNatPunchtroughFailedEventData
---@field Address VariantWithString
---@field Port VariantWithInt
---@field GetInt fun(self: NetworkNatPunchtroughFailedEventData, field: "Port"): integer
---@field GetString fun(self: NetworkNatPunchtroughFailedEventData, field: "Address"): string

--- NetworkNatPunchtroughSucceeded event data
---@class NetworkNatPunchtroughSucceededEventData
---@field Address VariantWithString
---@field Port VariantWithInt
---@field GetInt fun(self: NetworkNatPunchtroughSucceededEventData, field: "Port"): integer
---@field GetString fun(self: NetworkNatPunchtroughSucceededEventData, field: "Address"): string

--- NetworkReconnected event data
---@class NetworkReconnectedEventData

--- NetworkReconnecting event data
---@class NetworkReconnectingEventData

--- NetworkSceneLoadFailed event data
---@class NetworkSceneLoadFailedEventData
---@field Connection VariantWithPtr
---@field GetPtr fun(self: NetworkSceneLoadFailedEventData, field: "Connection"): Connection

--- NetworkUpdate event data
---@class NetworkUpdateEventData

--- NetworkUpdateSent event data
---@class NetworkUpdateSentEventData

--- NodeAdded event data
---@class NodeAddedEventData
---@field Scene VariantWithPtr
---@field Parent VariantWithPtr
---@field Node VariantWithPtr
---@field GetPtr fun(self: NodeAddedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: NodeAddedEventData, field: "Parent"): Node
---@field GetPtr fun(self: NodeAddedEventData, field: "Node"): Node

--- NodeBeginContact2D event data
---@class NodeBeginContact2DEventData
---@field Body VariantWithPtr
---@field OtherNode VariantWithPtr
---@field OtherBody VariantWithPtr
---@field Contacts VariantWithBuffer # containing position (Vector2), normal (Vector2), negative overlap distance (float). Normal is the same for all points.
---@field Shape VariantWithPtr
---@field OtherShape VariantWithPtr
---@field GetBuffer fun(self: NodeBeginContact2DEventData, field: "Contacts"): VectorBuffer
---@field GetPtr fun(self: NodeBeginContact2DEventData, field: "Body"): RigidBody2D
---@field GetPtr fun(self: NodeBeginContact2DEventData, field: "OtherNode"): Node
---@field GetPtr fun(self: NodeBeginContact2DEventData, field: "OtherBody"): RigidBody2D
---@field GetPtr fun(self: NodeBeginContact2DEventData, field: "Shape"): CollisionShape2D
---@field GetPtr fun(self: NodeBeginContact2DEventData, field: "OtherShape"): CollisionShape2D

--- NodeCloned event data
---@class NodeClonedEventData
---@field Scene VariantWithPtr
---@field Node VariantWithPtr
---@field CloneNode VariantWithPtr
---@field GetPtr fun(self: NodeClonedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: NodeClonedEventData, field: "Node"): Node
---@field GetPtr fun(self: NodeClonedEventData, field: "CloneNode"): Node

--- NodeCollision event data
---@class NodeCollisionEventData
---@field Node VariantWithPtr
---@field Body VariantWithPtr
---@field OtherNode VariantWithPtr
---@field OtherBody VariantWithPtr
---@field Trigger VariantWithBool
---@field Contacts VariantWithBuffer # containing position (Vector3), normal (Vector3), distance (float), impulse (float) for each contact
---@field GetBool fun(self: NodeCollisionEventData, field: "Trigger"): boolean
---@field GetBuffer fun(self: NodeCollisionEventData, field: "Contacts"): VectorBuffer
---@field GetPtr fun(self: NodeCollisionEventData, field: "Node"): Node
---@field GetPtr fun(self: NodeCollisionEventData, field: "Body"): RigidBody
---@field GetPtr fun(self: NodeCollisionEventData, field: "OtherNode"): Node
---@field GetPtr fun(self: NodeCollisionEventData, field: "OtherBody"): RigidBody

--- NodeCollisionEnd event data
---@class NodeCollisionEndEventData
---@field Node VariantWithPtr
---@field Body VariantWithPtr
---@field OtherNode VariantWithPtr
---@field OtherBody VariantWithPtr
---@field Trigger VariantWithBool
---@field GetBool fun(self: NodeCollisionEndEventData, field: "Trigger"): boolean
---@field GetPtr fun(self: NodeCollisionEndEventData, field: "Node"): Node
---@field GetPtr fun(self: NodeCollisionEndEventData, field: "Body"): RigidBody
---@field GetPtr fun(self: NodeCollisionEndEventData, field: "OtherNode"): Node
---@field GetPtr fun(self: NodeCollisionEndEventData, field: "OtherBody"): RigidBody

--- NodeCollisionStart event data
---@class NodeCollisionStartEventData
---@field Node VariantWithPtr
---@field Body VariantWithPtr
---@field OtherNode VariantWithPtr
---@field OtherBody VariantWithPtr
---@field Trigger VariantWithBool
---@field Contacts VariantWithBuffer # containing position (Vector3), normal (Vector3), distance (float), impulse (float) for each contact
---@field GetBool fun(self: NodeCollisionStartEventData, field: "Trigger"): boolean
---@field GetBuffer fun(self: NodeCollisionStartEventData, field: "Contacts"): VectorBuffer
---@field GetPtr fun(self: NodeCollisionStartEventData, field: "Node"): Node
---@field GetPtr fun(self: NodeCollisionStartEventData, field: "Body"): RigidBody
---@field GetPtr fun(self: NodeCollisionStartEventData, field: "OtherNode"): Node
---@field GetPtr fun(self: NodeCollisionStartEventData, field: "OtherBody"): RigidBody

--- NodeEnabledChanged event data
---@class NodeEnabledChangedEventData
---@field Scene VariantWithPtr
---@field Node VariantWithPtr
---@field GetPtr fun(self: NodeEnabledChangedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: NodeEnabledChangedEventData, field: "Node"): Node

--- NodeEndContact2D event data
---@class NodeEndContact2DEventData
---@field Body VariantWithPtr
---@field OtherNode VariantWithPtr
---@field OtherBody VariantWithPtr
---@field Contacts VariantWithBuffer # containing position (Vector2), normal (Vector2), negative overlap distance (float). Normal is the same for all points.
---@field Shape VariantWithPtr
---@field OtherShape VariantWithPtr
---@field GetBuffer fun(self: NodeEndContact2DEventData, field: "Contacts"): VectorBuffer
---@field GetPtr fun(self: NodeEndContact2DEventData, field: "Body"): RigidBody2D
---@field GetPtr fun(self: NodeEndContact2DEventData, field: "OtherNode"): Node
---@field GetPtr fun(self: NodeEndContact2DEventData, field: "OtherBody"): RigidBody2D
---@field GetPtr fun(self: NodeEndContact2DEventData, field: "Shape"): CollisionShape2D
---@field GetPtr fun(self: NodeEndContact2DEventData, field: "OtherShape"): CollisionShape2D

--- NodeNameChanged event data
---@class NodeNameChangedEventData
---@field Scene VariantWithPtr
---@field Node VariantWithPtr
---@field GetPtr fun(self: NodeNameChangedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: NodeNameChangedEventData, field: "Node"): Node

--- NodeRemoved event data
---@class NodeRemovedEventData
---@field Scene VariantWithPtr
---@field Parent VariantWithPtr
---@field Node VariantWithPtr
---@field GetPtr fun(self: NodeRemovedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: NodeRemovedEventData, field: "Parent"): Node
---@field GetPtr fun(self: NodeRemovedEventData, field: "Node"): Node

--- NodeTagAdded event data
---@class NodeTagAddedEventData
---@field Scene VariantWithPtr
---@field Node VariantWithPtr
---@field Tag VariantWithString # tag
---@field GetPtr fun(self: NodeTagAddedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: NodeTagAddedEventData, field: "Node"): Node
---@field GetString fun(self: NodeTagAddedEventData, field: "Tag"): string

--- NodeTagRemoved event data
---@class NodeTagRemovedEventData
---@field Scene VariantWithPtr
---@field Node VariantWithPtr
---@field Tag VariantWithString # tag
---@field GetPtr fun(self: NodeTagRemovedEventData, field: "Scene"): Scene
---@field GetPtr fun(self: NodeTagRemovedEventData, field: "Node"): Node
---@field GetString fun(self: NodeTagRemovedEventData, field: "Tag"): string

--- NodeUpdateContact2D event data
---@class NodeUpdateContact2DEventData
---@field Body VariantWithPtr
---@field OtherNode VariantWithPtr
---@field OtherBody VariantWithPtr
---@field Contacts VariantWithBuffer # containing position (Vector2), normal (Vector2), negative overlap distance (float). Normal is the same for all points.
---@field Shape VariantWithPtr
---@field OtherShape VariantWithPtr
---@field Enabled VariantWithBool # in/out
---@field GetBool fun(self: NodeUpdateContact2DEventData, field: "Enabled"): boolean
---@field GetBuffer fun(self: NodeUpdateContact2DEventData, field: "Contacts"): VectorBuffer
---@field GetPtr fun(self: NodeUpdateContact2DEventData, field: "Body"): RigidBody2D
---@field GetPtr fun(self: NodeUpdateContact2DEventData, field: "OtherNode"): Node
---@field GetPtr fun(self: NodeUpdateContact2DEventData, field: "OtherBody"): RigidBody2D
---@field GetPtr fun(self: NodeUpdateContact2DEventData, field: "Shape"): CollisionShape2D
---@field GetPtr fun(self: NodeUpdateContact2DEventData, field: "OtherShape"): CollisionShape2D

--- OrientationChanged event data
---@class OrientationChangedEventData
---@field Orientation VariantWithInt # SDL_DisplayOrientation
---@field GetInt fun(self: OrientationChangedEventData, field: "Orientation"): integer

--- ParticleEffectFinished event data
---@class ParticleEffectFinishedEventData
---@field Node VariantWithPtr
---@field Effect VariantWithPtr
---@field GetPtr fun(self: ParticleEffectFinishedEventData, field: "Node"): Node
---@field GetPtr fun(self: ParticleEffectFinishedEventData, field: "Effect"): ParticleEffect

--- ParticlesDuration event data
---@class ParticlesDurationEventData
---@field Node VariantWithPtr
---@field Effect VariantWithPtr
---@field GetPtr fun(self: ParticlesDurationEventData, field: "Node"): Node
---@field GetPtr fun(self: ParticlesDurationEventData, field: "Effect"): ParticleEffect2D

--- ParticlesEnd event data
---@class ParticlesEndEventData
---@field Node VariantWithPtr
---@field Effect VariantWithPtr
---@field GetPtr fun(self: ParticlesEndEventData, field: "Node"): Node
---@field GetPtr fun(self: ParticlesEndEventData, field: "Effect"): ParticleEffect2D

--- PhysicsBeginContact2D event data
---@class PhysicsBeginContact2DEventData
---@field World VariantWithPtr
---@field BodyA VariantWithPtr
---@field BodyB VariantWithPtr
---@field NodeA VariantWithPtr
---@field NodeB VariantWithPtr
---@field Contacts VariantWithBuffer # containing position (Vector2), normal (Vector2), negative overlap distance (float). Normal is the same for all points.
---@field ShapeA VariantWithPtr
---@field ShapeB VariantWithPtr
---@field GetBuffer fun(self: PhysicsBeginContact2DEventData, field: "Contacts"): VectorBuffer
---@field GetPtr fun(self: PhysicsBeginContact2DEventData, field: "World"): PhysicsWorld2D
---@field GetPtr fun(self: PhysicsBeginContact2DEventData, field: "BodyA"): RigidBody2D
---@field GetPtr fun(self: PhysicsBeginContact2DEventData, field: "BodyB"): RigidBody2D
---@field GetPtr fun(self: PhysicsBeginContact2DEventData, field: "NodeA"): Node
---@field GetPtr fun(self: PhysicsBeginContact2DEventData, field: "NodeB"): Node
---@field GetPtr fun(self: PhysicsBeginContact2DEventData, field: "ShapeA"): CollisionShape2D
---@field GetPtr fun(self: PhysicsBeginContact2DEventData, field: "ShapeB"): CollisionShape2D

--- PhysicsCollision event data
---@class PhysicsCollisionEventData
---@field World VariantWithPtr
---@field NodeA VariantWithPtr
---@field NodeB VariantWithPtr
---@field BodyA VariantWithPtr
---@field BodyB VariantWithPtr
---@field Trigger VariantWithBool
---@field Contacts VariantWithBuffer # containing position (Vector3), normal (Vector3), distance (float), impulse (float) for each contact
---@field GetBool fun(self: PhysicsCollisionEventData, field: "Trigger"): boolean
---@field GetBuffer fun(self: PhysicsCollisionEventData, field: "Contacts"): VectorBuffer
---@field GetPtr fun(self: PhysicsCollisionEventData, field: "World"): PhysicsWorld
---@field GetPtr fun(self: PhysicsCollisionEventData, field: "NodeA"): Node
---@field GetPtr fun(self: PhysicsCollisionEventData, field: "NodeB"): Node
---@field GetPtr fun(self: PhysicsCollisionEventData, field: "BodyA"): RigidBody
---@field GetPtr fun(self: PhysicsCollisionEventData, field: "BodyB"): RigidBody

--- PhysicsCollisionEnd event data
---@class PhysicsCollisionEndEventData
---@field World VariantWithPtr
---@field NodeA VariantWithPtr
---@field NodeB VariantWithPtr
---@field BodyA VariantWithPtr
---@field BodyB VariantWithPtr
---@field Trigger VariantWithBool
---@field GetBool fun(self: PhysicsCollisionEndEventData, field: "Trigger"): boolean
---@field GetPtr fun(self: PhysicsCollisionEndEventData, field: "World"): PhysicsWorld
---@field GetPtr fun(self: PhysicsCollisionEndEventData, field: "NodeA"): Node
---@field GetPtr fun(self: PhysicsCollisionEndEventData, field: "NodeB"): Node
---@field GetPtr fun(self: PhysicsCollisionEndEventData, field: "BodyA"): RigidBody
---@field GetPtr fun(self: PhysicsCollisionEndEventData, field: "BodyB"): RigidBody

--- PhysicsCollisionStart event data
---@class PhysicsCollisionStartEventData
---@field World VariantWithPtr
---@field NodeA VariantWithPtr
---@field NodeB VariantWithPtr
---@field BodyA VariantWithPtr
---@field BodyB VariantWithPtr
---@field Trigger VariantWithBool
---@field Contacts VariantWithBuffer # containing position (Vector3), normal (Vector3), distance (float), impulse (float) for each contact
---@field GetBool fun(self: PhysicsCollisionStartEventData, field: "Trigger"): boolean
---@field GetBuffer fun(self: PhysicsCollisionStartEventData, field: "Contacts"): VectorBuffer
---@field GetPtr fun(self: PhysicsCollisionStartEventData, field: "World"): PhysicsWorld
---@field GetPtr fun(self: PhysicsCollisionStartEventData, field: "NodeA"): Node
---@field GetPtr fun(self: PhysicsCollisionStartEventData, field: "NodeB"): Node
---@field GetPtr fun(self: PhysicsCollisionStartEventData, field: "BodyA"): RigidBody
---@field GetPtr fun(self: PhysicsCollisionStartEventData, field: "BodyB"): RigidBody

--- PhysicsEndContact2D event data
---@class PhysicsEndContact2DEventData
---@field World VariantWithPtr
---@field BodyA VariantWithPtr
---@field BodyB VariantWithPtr
---@field NodeA VariantWithPtr
---@field NodeB VariantWithPtr
---@field Contacts VariantWithBuffer # containing position (Vector2), normal (Vector2), negative overlap distance (float). Normal is the same for all points.
---@field ShapeA VariantWithPtr
---@field ShapeB VariantWithPtr
---@field GetBuffer fun(self: PhysicsEndContact2DEventData, field: "Contacts"): VectorBuffer
---@field GetPtr fun(self: PhysicsEndContact2DEventData, field: "World"): PhysicsWorld2D
---@field GetPtr fun(self: PhysicsEndContact2DEventData, field: "BodyA"): RigidBody2D
---@field GetPtr fun(self: PhysicsEndContact2DEventData, field: "BodyB"): RigidBody2D
---@field GetPtr fun(self: PhysicsEndContact2DEventData, field: "NodeA"): Node
---@field GetPtr fun(self: PhysicsEndContact2DEventData, field: "NodeB"): Node
---@field GetPtr fun(self: PhysicsEndContact2DEventData, field: "ShapeA"): CollisionShape2D
---@field GetPtr fun(self: PhysicsEndContact2DEventData, field: "ShapeB"): CollisionShape2D

--- PhysicsMotionStates event data
---@class PhysicsMotionStatesEventData
---@field World VariantWithPtr
---@field TimeStep VariantWithFloat
---@field FrameNumber VariantWithInt
---@field GetFloat fun(self: PhysicsMotionStatesEventData, field: "TimeStep"): number
---@field GetInt fun(self: PhysicsMotionStatesEventData, field: "FrameNumber"): integer
---@field GetPtr fun(self: PhysicsMotionStatesEventData, field: "World"): PhysicsWorld

--- PhysicsPostStep event data
---@class PhysicsPostStepEventData
---@field World VariantWithPtr
---@field TimeStep VariantWithFloat
---@field FrameNumber VariantWithInt
---@field GetFloat fun(self: PhysicsPostStepEventData, field: "TimeStep"): number
---@field GetInt fun(self: PhysicsPostStepEventData, field: "FrameNumber"): integer
---@field GetPtr fun(self: PhysicsPostStepEventData, field: "World"): PhysicsWorld

--- PhysicsPreStep event data
---@class PhysicsPreStepEventData
---@field World VariantWithPtr
---@field TimeStep VariantWithFloat
---@field FrameNumber VariantWithInt
---@field GetFloat fun(self: PhysicsPreStepEventData, field: "TimeStep"): number
---@field GetInt fun(self: PhysicsPreStepEventData, field: "FrameNumber"): integer
---@field GetPtr fun(self: PhysicsPreStepEventData, field: "World"): PhysicsWorld

--- PhysicsUpdateContact2D event data
---@class PhysicsUpdateContact2DEventData
---@field World VariantWithPtr
---@field BodyA VariantWithPtr
---@field BodyB VariantWithPtr
---@field NodeA VariantWithPtr
---@field NodeB VariantWithPtr
---@field Contacts VariantWithBuffer # containing position (Vector2), normal (Vector2), negative overlap distance (float). Normal is the same for all points.
---@field ShapeA VariantWithPtr
---@field ShapeB VariantWithPtr
---@field Enabled VariantWithBool # in/out
---@field GetBool fun(self: PhysicsUpdateContact2DEventData, field: "Enabled"): boolean
---@field GetBuffer fun(self: PhysicsUpdateContact2DEventData, field: "Contacts"): VectorBuffer
---@field GetPtr fun(self: PhysicsUpdateContact2DEventData, field: "World"): PhysicsWorld2D
---@field GetPtr fun(self: PhysicsUpdateContact2DEventData, field: "BodyA"): RigidBody2D
---@field GetPtr fun(self: PhysicsUpdateContact2DEventData, field: "BodyB"): RigidBody2D
---@field GetPtr fun(self: PhysicsUpdateContact2DEventData, field: "NodeA"): Node
---@field GetPtr fun(self: PhysicsUpdateContact2DEventData, field: "NodeB"): Node
---@field GetPtr fun(self: PhysicsUpdateContact2DEventData, field: "ShapeA"): CollisionShape2D
---@field GetPtr fun(self: PhysicsUpdateContact2DEventData, field: "ShapeB"): CollisionShape2D

--- PlayerSessionDisconnected event data
---@class PlayerSessionDisconnectedEventData
---@field Connection VariantWithPtr
---@field UserId VariantWithInt64
---@field ReconnectTimeout VariantWithFloat # seconds
---@field GetFloat fun(self: PlayerSessionDisconnectedEventData, field: "ReconnectTimeout"): number
---@field GetInt64 fun(self: PlayerSessionDisconnectedEventData, field: "UserId"): integer
---@field GetPtr fun(self: PlayerSessionDisconnectedEventData, field: "Connection"): Connection

--- PlayerSessionJoined event data
---@class PlayerSessionJoinedEventData
---@field Connection VariantWithPtr # non-null
---@field UserId VariantWithInt64
---@field GetInt64 fun(self: PlayerSessionJoinedEventData, field: "UserId"): integer
---@field GetPtr fun(self: PlayerSessionJoinedEventData, field: "Connection"): Connection

--- PlayerSessionLeft event data
---@class PlayerSessionLeftEventData
---@field UserId VariantWithInt64
---@field Reason VariantWithString
---@field GetInt64 fun(self: PlayerSessionLeftEventData, field: "UserId"): integer
---@field GetString fun(self: PlayerSessionLeftEventData, field: "Reason"): string

--- PlayerSessionReconnected event data
---@class PlayerSessionReconnectedEventData
---@field Connection VariantWithPtr # non-null
---@field UserId VariantWithInt64
---@field GetInt64 fun(self: PlayerSessionReconnectedEventData, field: "UserId"): integer
---@field GetPtr fun(self: PlayerSessionReconnectedEventData, field: "Connection"): Connection

--- Positioned event data
---@class PositionedEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field GetInt fun(self: PositionedEventData, field: "X"): integer
---@field GetInt fun(self: PositionedEventData, field: "Y"): integer
---@field GetPtr fun(self: PositionedEventData, field: "Element"): UIElement

--- PostPreRenderUI event data
---@class PostPreRenderUIEventData

--- PostRenderUI event data
---@class PostRenderUIEventData

--- PostRenderUpdate event data
---@class PostRenderUpdateEventData
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: PostRenderUpdateEventData, field: "TimeStep"): number

--- PostUpdate event data
---@class PostUpdateEventData
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: PostUpdateEventData, field: "TimeStep"): number

--- PreEndFrame event data
---@class PreEndFrameEventData

--- PreRenderUI event data
---@class PreRenderUIEventData

--- PreRenderUpdate event data
---@class PreRenderUpdateEventData

--- Pressed event data
---@class PressedEventData
---@field Element VariantWithPtr
---@field GetPtr fun(self: PressedEventData, field: "Element"): UIElement

--- ProgressBarChanged event data
---@class ProgressBarChangedEventData
---@field Element VariantWithPtr
---@field Value VariantWithFloat
---@field GetFloat fun(self: ProgressBarChangedEventData, field: "Value"): number
---@field GetPtr fun(self: ProgressBarChangedEventData, field: "Element"): UIElement

--- Released event data
---@class ReleasedEventData
---@field Element VariantWithPtr
---@field GetPtr fun(self: ReleasedEventData, field: "Element"): UIElement

--- ReloadFailed event data
---@class ReloadFailedEventData

--- ReloadFinished event data
---@class ReloadFinishedEventData

--- ReloadStarted event data
---@class ReloadStartedEventData

--- RemoteEventData event data
---@class RemoteEventDataEventData
---@field Connection VariantWithPtr
---@field GetPtr fun(self: RemoteEventDataEventData, field: "Connection"): Connection

--- RenderPathEvent event data
---@class RenderPathEventEventData
---@field Name VariantWithString
---@field Scene VariantWithPtr
---@field RenderTarget VariantWithPtr
---@field GetPtr fun(self: RenderPathEventEventData, field: "Scene"): Scene
---@field GetPtr fun(self: RenderPathEventEventData, field: "RenderTarget"): Texture2D
---@field GetString fun(self: RenderPathEventEventData, field: "Name"): string

--- RenderQualityApply event data
---@class RenderQualityApplyEventData

--- RenderSurfaceUpdate event data
---@class RenderSurfaceUpdateEventData

--- RenderUpdate event data
---@class RenderUpdateEventData
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: RenderUpdateEventData, field: "TimeStep"): number

--- Resized event data
---@class ResizedEventData
---@field Element VariantWithPtr
---@field Width VariantWithInt
---@field Height VariantWithInt
---@field DX VariantWithInt
---@field DY VariantWithInt
---@field GetInt fun(self: ResizedEventData, field: "Width"): integer
---@field GetInt fun(self: ResizedEventData, field: "Height"): integer
---@field GetInt fun(self: ResizedEventData, field: "DX"): integer
---@field GetInt fun(self: ResizedEventData, field: "DY"): integer
---@field GetPtr fun(self: ResizedEventData, field: "Element"): UIElement

--- ResourceBackgroundLoaded event data
---@class ResourceBackgroundLoadedEventData
---@field ResourceName VariantWithString
---@field Success VariantWithBool
---@field Resource VariantWithPtr
---@field GetBool fun(self: ResourceBackgroundLoadedEventData, field: "Success"): boolean
---@field GetPtr fun(self: ResourceBackgroundLoadedEventData, field: "Resource"): Resource
---@field GetString fun(self: ResourceBackgroundLoadedEventData, field: "ResourceName"): string

--- ResourceNotFound event data
---@class ResourceNotFoundEventData
---@field ResourceName VariantWithString
---@field GetString fun(self: ResourceNotFoundEventData, field: "ResourceName"): string

--- RuntimeDebuggerSelectionChanged event data
---@class RuntimeDebuggerSelectionChangedEventData
---@field Node VariantWithPtr # Selected, can be null
---@field Component VariantWithPtr # Selected, can be null
---@field GetPtr fun(self: RuntimeDebuggerSelectionChangedEventData, field: "Node"): Node
---@field GetPtr fun(self: RuntimeDebuggerSelectionChangedEventData, field: "Component"): Component

--- SDLRawInput event data
---@class SDLRawInputEventData
---@field SDLEvent VariantWithPtr
---@field Consumed VariantWithBool
---@field GetBool fun(self: SDLRawInputEventData, field: "Consumed"): boolean
---@field GetPtr fun(self: SDLRawInputEventData, field: "SDLEvent"): SDL_Event

--- SceneDrawableUpdateFinished event data
---@class SceneDrawableUpdateFinishedEventData
---@field Scene VariantWithPtr
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: SceneDrawableUpdateFinishedEventData, field: "TimeStep"): number
---@field GetPtr fun(self: SceneDrawableUpdateFinishedEventData, field: "Scene"): Scene

--- SceneLoadFinished event data
---@class SceneLoadFinishedEventData
---@field Scene VariantWithPtr
---@field GetPtr fun(self: SceneLoadFinishedEventData, field: "Scene"): Scene

--- ScenePostUpdate event data
---@class ScenePostUpdateEventData
---@field Scene VariantWithPtr
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: ScenePostUpdateEventData, field: "TimeStep"): number
---@field GetPtr fun(self: ScenePostUpdateEventData, field: "Scene"): Scene

--- SceneSubsystemUpdate event data
---@class SceneSubsystemUpdateEventData
---@field Scene VariantWithPtr
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: SceneSubsystemUpdateEventData, field: "TimeStep"): number
---@field GetPtr fun(self: SceneSubsystemUpdateEventData, field: "Scene"): Scene

--- SceneUpdate event data
---@class SceneUpdateEventData
---@field Scene VariantWithPtr
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: SceneUpdateEventData, field: "TimeStep"): number
---@field GetPtr fun(self: SceneUpdateEventData, field: "Scene"): Scene

--- ScreenMode event data
---@class ScreenModeEventData
---@field Width VariantWithInt
---@field Height VariantWithInt
---@field Fullscreen VariantWithBool
---@field Borderless VariantWithBool
---@field Resizable VariantWithBool
---@field HighDPI VariantWithBool
---@field Monitor VariantWithInt
---@field RefreshRate VariantWithInt
---@field GetBool fun(self: ScreenModeEventData, field: "Fullscreen"): boolean
---@field GetBool fun(self: ScreenModeEventData, field: "Borderless"): boolean
---@field GetBool fun(self: ScreenModeEventData, field: "Resizable"): boolean
---@field GetBool fun(self: ScreenModeEventData, field: "HighDPI"): boolean
---@field GetInt fun(self: ScreenModeEventData, field: "Width"): integer
---@field GetInt fun(self: ScreenModeEventData, field: "Height"): integer
---@field GetInt fun(self: ScreenModeEventData, field: "Monitor"): integer
---@field GetInt fun(self: ScreenModeEventData, field: "RefreshRate"): integer

--- ScrollBarChanged event data
---@class ScrollBarChangedEventData
---@field Element VariantWithPtr
---@field Value VariantWithFloat
---@field GetFloat fun(self: ScrollBarChangedEventData, field: "Value"): number
---@field GetPtr fun(self: ScrollBarChangedEventData, field: "Element"): UIElement

--- SelectionChanged event data
---@class SelectionChangedEventData
---@field Element VariantWithPtr
---@field GetPtr fun(self: SelectionChangedEventData, field: "Element"): UIElement

--- ServerConnected event data
---@class ServerConnectedEventData

--- ServerDisconnected event data
---@class ServerDisconnectedEventData

--- ShaderCompile event data
---@class ShaderCompileEventData
---@field Name VariantWithString
---@field ShortName VariantWithString
---@field Status VariantWithInt
---@field GetInt fun(self: ShaderCompileEventData, field: "Status"): integer
---@field GetString fun(self: ShaderCompileEventData, field: "Name"): string
---@field GetString fun(self: ShaderCompileEventData, field: "ShortName"): string

--- ShaderUncompress event data
---@class ShaderUncompressEventData
---@field Name VariantWithString
---@field GetString fun(self: ShaderUncompressEventData, field: "Name"): string

--- SliderChanged event data
---@class SliderChangedEventData
---@field Element VariantWithPtr
---@field Value VariantWithFloat
---@field GetFloat fun(self: SliderChangedEventData, field: "Value"): number
---@field GetPtr fun(self: SliderChangedEventData, field: "Element"): UIElement

--- SliderPaged event data
---@class SliderPagedEventData
---@field Element VariantWithPtr
---@field Offset VariantWithInt
---@field Pressed VariantWithBool
---@field GetBool fun(self: SliderPagedEventData, field: "Pressed"): boolean
---@field GetInt fun(self: SliderPagedEventData, field: "Offset"): integer
---@field GetPtr fun(self: SliderPagedEventData, field: "Element"): UIElement

--- SoundFinished event data
---@class SoundFinishedEventData
---@field Node VariantWithPtr
---@field SoundSource VariantWithPtr
---@field Sound VariantWithPtr
---@field GetPtr fun(self: SoundFinishedEventData, field: "Node"): Node
---@field GetPtr fun(self: SoundFinishedEventData, field: "SoundSource"): SoundSource
---@field GetPtr fun(self: SoundFinishedEventData, field: "Sound"): Sound

--- TargetPositionChanged event data
---@class TargetPositionChangedEventData

--- TargetRotationChanged event data
---@class TargetRotationChangedEventData

--- TemporaryChanged event data
---@class TemporaryChangedEventData
---@field Serializable VariantWithPtr
---@field GetPtr fun(self: TemporaryChangedEventData, field: "Serializable"): Serializable

--- TerrainCreated event data
---@class TerrainCreatedEventData
---@field Node VariantWithPtr
---@field GetPtr fun(self: TerrainCreatedEventData, field: "Node"): Node

--- TextChanged event data
---@class TextChangedEventData
---@field Element VariantWithPtr
---@field Text VariantWithString
---@field GetPtr fun(self: TextChangedEventData, field: "Element"): UIElement
---@field GetString fun(self: TextChangedEventData, field: "Text"): string

--- TextEditing event data
---@class TextEditingEventData
---@field Composition VariantWithString
---@field Cursor VariantWithInt
---@field SelectionLength VariantWithInt
---@field GetInt fun(self: TextEditingEventData, field: "Cursor"): integer
---@field GetInt fun(self: TextEditingEventData, field: "SelectionLength"): integer
---@field GetString fun(self: TextEditingEventData, field: "Composition"): string

--- TextEntry event data
---@class TextEntryEventData
---@field Element VariantWithPtr
---@field Text VariantWithString # in/out
---@field GetPtr fun(self: TextEntryEventData, field: "Element"): UIElement
---@field GetString fun(self: TextEntryEventData, field: "Text"): string

--- TextFinished event data
---@class TextFinishedEventData
---@field Element VariantWithPtr
---@field Text VariantWithString
---@field Value VariantWithFloat
---@field GetFloat fun(self: TextFinishedEventData, field: "Value"): number
---@field GetPtr fun(self: TextFinishedEventData, field: "Element"): UIElement
---@field GetString fun(self: TextFinishedEventData, field: "Text"): string

--- TextInput event data
---@class TextInputEventData
---@field Text VariantWithString
---@field GetString fun(self: TextInputEventData, field: "Text"): string

--- TextureFroamtWarn event data
---@class TextureFroamtWarnEventData

--- Toggled event data
---@class ToggledEventData
---@field Element VariantWithPtr
---@field State VariantWithBool
---@field GetBool fun(self: ToggledEventData, field: "State"): boolean
---@field GetPtr fun(self: ToggledEventData, field: "Element"): UIElement

--- Touch event data
---@class TouchEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field GetInt fun(self: TouchEventData, field: "X"): integer
---@field GetInt fun(self: TouchEventData, field: "Y"): integer
---@field GetPtr fun(self: TouchEventData, field: "Element"): UIElement

--- TouchBegin event data
---@class TouchBeginEventData
---@field TouchID VariantWithInt
---@field X VariantWithInt
---@field Y VariantWithInt
---@field Pressure VariantWithFloat
---@field GetFloat fun(self: TouchBeginEventData, field: "Pressure"): number
---@field GetInt fun(self: TouchBeginEventData, field: "TouchID"): integer
---@field GetInt fun(self: TouchBeginEventData, field: "X"): integer
---@field GetInt fun(self: TouchBeginEventData, field: "Y"): integer

--- TouchEnd event data
---@class TouchEndEventData
---@field TouchID VariantWithInt
---@field X VariantWithInt
---@field Y VariantWithInt
---@field GetInt fun(self: TouchEndEventData, field: "TouchID"): integer
---@field GetInt fun(self: TouchEndEventData, field: "X"): integer
---@field GetInt fun(self: TouchEndEventData, field: "Y"): integer

--- TouchMove event data
---@class TouchMoveEventData
---@field TouchID VariantWithInt
---@field X VariantWithInt
---@field Y VariantWithInt
---@field DX VariantWithInt
---@field DY VariantWithInt
---@field Pressure VariantWithFloat
---@field GetFloat fun(self: TouchMoveEventData, field: "Pressure"): number
---@field GetInt fun(self: TouchMoveEventData, field: "TouchID"): integer
---@field GetInt fun(self: TouchMoveEventData, field: "X"): integer
---@field GetInt fun(self: TouchMoveEventData, field: "Y"): integer
---@field GetInt fun(self: TouchMoveEventData, field: "DX"): integer
---@field GetInt fun(self: TouchMoveEventData, field: "DY"): integer

--- TransportConnectFailed event data
---@class TransportConnectFailedEventData
---@field Address VariantWithString # remote address
---@field Port VariantWithInt # remote port
---@field Protocol VariantWithString # protocol name
---@field Error VariantWithString # error message
---@field GetInt fun(self: TransportConnectFailedEventData, field: "Port"): integer
---@field GetString fun(self: TransportConnectFailedEventData, field: "Address"): string
---@field GetString fun(self: TransportConnectFailedEventData, field: "Protocol"): string
---@field GetString fun(self: TransportConnectFailedEventData, field: "Error"): string

--- TransportConnected event data
---@class TransportConnectedEventData
---@field Address VariantWithString # remote address
---@field Port VariantWithInt # remote port
---@field Protocol VariantWithString # protocol name (udp/ws/kcp)
---@field GetInt fun(self: TransportConnectedEventData, field: "Port"): integer
---@field GetString fun(self: TransportConnectedEventData, field: "Address"): string
---@field GetString fun(self: TransportConnectedEventData, field: "Protocol"): string

--- TransportData event data
---@class TransportDataEventData
---@field Address VariantWithString # remote address
---@field Port VariantWithInt # remote port
---@field Protocol VariantWithString # protocol name
---@field Data VariantWithBuffer # raw data
---@field GetBuffer fun(self: TransportDataEventData, field: "Data"): VectorBuffer
---@field GetInt fun(self: TransportDataEventData, field: "Port"): integer
---@field GetString fun(self: TransportDataEventData, field: "Address"): string
---@field GetString fun(self: TransportDataEventData, field: "Protocol"): string

--- TransportDisconnected event data
---@class TransportDisconnectedEventData
---@field Address VariantWithString # remote address
---@field Port VariantWithInt # remote port
---@field Protocol VariantWithString # protocol name
---@field Reason VariantWithString # disconnect reason
---@field GetInt fun(self: TransportDisconnectedEventData, field: "Port"): integer
---@field GetString fun(self: TransportDisconnectedEventData, field: "Address"): string
---@field GetString fun(self: TransportDisconnectedEventData, field: "Protocol"): string
---@field GetString fun(self: TransportDisconnectedEventData, field: "Reason"): string

--- UIDropFile event data
---@class UIDropFileEventData
---@field FileName VariantWithString
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field ElementX VariantWithInt # only if element is non-null
---@field ElementY VariantWithInt # only if element is non-null
---@field GetInt fun(self: UIDropFileEventData, field: "X"): integer
---@field GetInt fun(self: UIDropFileEventData, field: "Y"): integer
---@field GetInt fun(self: UIDropFileEventData, field: "ElementX"): integer
---@field GetInt fun(self: UIDropFileEventData, field: "ElementY"): integer
---@field GetPtr fun(self: UIDropFileEventData, field: "Element"): UIElement
---@field GetString fun(self: UIDropFileEventData, field: "FileName"): string

--- UIMouseClick event data
---@class UIMouseClickEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: UIMouseClickEventData, field: "X"): integer
---@field GetInt fun(self: UIMouseClickEventData, field: "Y"): integer
---@field GetInt fun(self: UIMouseClickEventData, field: "Button"): integer
---@field GetInt fun(self: UIMouseClickEventData, field: "Buttons"): integer
---@field GetInt fun(self: UIMouseClickEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: UIMouseClickEventData, field: "Element"): UIElement

--- UIMouseClickEnd event data
---@class UIMouseClickEndEventData
---@field Element VariantWithPtr
---@field BeginElement VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: UIMouseClickEndEventData, field: "X"): integer
---@field GetInt fun(self: UIMouseClickEndEventData, field: "Y"): integer
---@field GetInt fun(self: UIMouseClickEndEventData, field: "Button"): integer
---@field GetInt fun(self: UIMouseClickEndEventData, field: "Buttons"): integer
---@field GetInt fun(self: UIMouseClickEndEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: UIMouseClickEndEventData, field: "Element"): UIElement
---@field GetPtr fun(self: UIMouseClickEndEventData, field: "BeginElement"): UIElement

--- UIMouseClickReplay event data
---@class UIMouseClickReplayEventData
---@field Control VariantWithString # Control id
---@field X VariantWithInt
---@field Y VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: UIMouseClickReplayEventData, field: "X"): integer
---@field GetInt fun(self: UIMouseClickReplayEventData, field: "Y"): integer
---@field GetInt fun(self: UIMouseClickReplayEventData, field: "Button"): integer
---@field GetInt fun(self: UIMouseClickReplayEventData, field: "Buttons"): integer
---@field GetInt fun(self: UIMouseClickReplayEventData, field: "Qualifiers"): integer
---@field GetString fun(self: UIMouseClickReplayEventData, field: "Control"): string

--- UIMouseClickReplayPlay event data
---@class UIMouseClickReplayPlayEventData
---@field Control VariantWithString # Control id
---@field X VariantWithInt
---@field Y VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: UIMouseClickReplayPlayEventData, field: "X"): integer
---@field GetInt fun(self: UIMouseClickReplayPlayEventData, field: "Y"): integer
---@field GetInt fun(self: UIMouseClickReplayPlayEventData, field: "Button"): integer
---@field GetInt fun(self: UIMouseClickReplayPlayEventData, field: "Buttons"): integer
---@field GetInt fun(self: UIMouseClickReplayPlayEventData, field: "Qualifiers"): integer
---@field GetString fun(self: UIMouseClickReplayPlayEventData, field: "Control"): string

--- UIMouseClicked event data
---@class UIMouseClickedEventData
---@field Element VariantWithPtr
---@field BeginElement VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: UIMouseClickedEventData, field: "X"): integer
---@field GetInt fun(self: UIMouseClickedEventData, field: "Y"): integer
---@field GetInt fun(self: UIMouseClickedEventData, field: "Button"): integer
---@field GetInt fun(self: UIMouseClickedEventData, field: "Buttons"): integer
---@field GetInt fun(self: UIMouseClickedEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: UIMouseClickedEventData, field: "Element"): UIElement
---@field GetPtr fun(self: UIMouseClickedEventData, field: "BeginElement"): UIElement

--- UIMouseDoubleClick event data
---@class UIMouseDoubleClickEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field XBegin VariantWithInt
---@field YBegin VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: UIMouseDoubleClickEventData, field: "X"): integer
---@field GetInt fun(self: UIMouseDoubleClickEventData, field: "Y"): integer
---@field GetInt fun(self: UIMouseDoubleClickEventData, field: "XBegin"): integer
---@field GetInt fun(self: UIMouseDoubleClickEventData, field: "YBegin"): integer
---@field GetInt fun(self: UIMouseDoubleClickEventData, field: "Button"): integer
---@field GetInt fun(self: UIMouseDoubleClickEventData, field: "Buttons"): integer
---@field GetInt fun(self: UIMouseDoubleClickEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: UIMouseDoubleClickEventData, field: "Element"): UIElement

--- UIMouseEnter event data
---@class UIMouseEnterEventData
---@field Element VariantWithPtr
---@field GetPtr fun(self: UIMouseEnterEventData, field: "Element"): UIElement

--- UIMouseLeave event data
---@class UIMouseLeaveEventData
---@field Element VariantWithPtr
---@field GetPtr fun(self: UIMouseLeaveEventData, field: "Element"): UIElement

--- UIMouseRealClick event data
---@class UIMouseRealClickEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field Button VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: UIMouseRealClickEventData, field: "X"): integer
---@field GetInt fun(self: UIMouseRealClickEventData, field: "Y"): integer
---@field GetInt fun(self: UIMouseRealClickEventData, field: "Button"): integer
---@field GetInt fun(self: UIMouseRealClickEventData, field: "Buttons"): integer
---@field GetInt fun(self: UIMouseRealClickEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: UIMouseRealClickEventData, field: "Element"): UIElement

--- UnhandledKey event data
---@class UnhandledKeyEventData
---@field Element VariantWithPtr
---@field Key VariantWithInt
---@field Buttons VariantWithInt
---@field Qualifiers VariantWithInt
---@field GetInt fun(self: UnhandledKeyEventData, field: "Key"): integer
---@field GetInt fun(self: UnhandledKeyEventData, field: "Buttons"): integer
---@field GetInt fun(self: UnhandledKeyEventData, field: "Qualifiers"): integer
---@field GetPtr fun(self: UnhandledKeyEventData, field: "Element"): UIElement

--- UnknownResourceType event data
---@class UnknownResourceTypeEventData
---@field ResourceType VariantWithStringHash
---@field GetStringHash fun(self: UnknownResourceTypeEventData, field: "ResourceType"): StringHash

--- Update event data
---@class UpdateEventData
---@field TimeStep VariantWithFloat
---@field GetFloat fun(self: UpdateEventData, field: "TimeStep"): number

--- UpdateSmoothing event data
---@class UpdateSmoothingEventData
---@field Constant VariantWithFloat
---@field SquaredSnapThreshold VariantWithFloat
---@field GetFloat fun(self: UpdateSmoothingEventData, field: "Constant"): number
---@field GetFloat fun(self: UpdateSmoothingEventData, field: "SquaredSnapThreshold"): number

--- UserStat event data
---@class UserStatEventData
---@field Type VariantWithString # stat type (e.g. "DownloadError")
---@field Arg VariantWithString # stat argument (free-form)
---@field GetString fun(self: UserStatEventData, field: "Type"): string
---@field GetString fun(self: UserStatEventData, field: "Arg"): string

--- ViewBakeShadowMap event data
---@class ViewBakeShadowMapEventData

--- ViewBuffersReady event data
---@class ViewBuffersReadyEventData
---@field View VariantWithPtr
---@field Texture VariantWithPtr
---@field Surface VariantWithPtr
---@field Scene VariantWithPtr
---@field Camera VariantWithPtr
---@field GetPtr fun(self: ViewBuffersReadyEventData, field: "View"): View
---@field GetPtr fun(self: ViewBuffersReadyEventData, field: "Texture"): Texture
---@field GetPtr fun(self: ViewBuffersReadyEventData, field: "Surface"): RenderSurface
---@field GetPtr fun(self: ViewBuffersReadyEventData, field: "Scene"): Scene
---@field GetPtr fun(self: ViewBuffersReadyEventData, field: "Camera"): Camera

--- ViewChanged event data
---@class ViewChangedEventData
---@field Element VariantWithPtr
---@field X VariantWithInt
---@field Y VariantWithInt
---@field GetInt fun(self: ViewChangedEventData, field: "X"): integer
---@field GetInt fun(self: ViewChangedEventData, field: "Y"): integer
---@field GetPtr fun(self: ViewChangedEventData, field: "Element"): UIElement

--- ViewGlobalShaderParameters event data
---@class ViewGlobalShaderParametersEventData
---@field View VariantWithPtr
---@field Texture VariantWithPtr
---@field Surface VariantWithPtr
---@field Scene VariantWithPtr
---@field Camera VariantWithPtr
---@field GetPtr fun(self: ViewGlobalShaderParametersEventData, field: "View"): View
---@field GetPtr fun(self: ViewGlobalShaderParametersEventData, field: "Texture"): Texture
---@field GetPtr fun(self: ViewGlobalShaderParametersEventData, field: "Surface"): RenderSurface
---@field GetPtr fun(self: ViewGlobalShaderParametersEventData, field: "Scene"): Scene
---@field GetPtr fun(self: ViewGlobalShaderParametersEventData, field: "Camera"): Camera

--- VisibleChanged event data
---@class VisibleChangedEventData
---@field Element VariantWithPtr
---@field Visible VariantWithBool
---@field GetBool fun(self: VisibleChangedEventData, field: "Visible"): boolean
---@field GetPtr fun(self: VisibleChangedEventData, field: "Element"): UIElement

--- VoxelAssemblyMemberDetached event data
---@class VoxelAssemblyMemberDetachedEventData
---@field Assembly VariantWithPtr
---@field Volume VariantWithPtr # detached
---@field Force VariantWithVector3 # last member reaction force
---@field Torque VariantWithVector3 # last member reaction torque
---@field BreakFactor VariantWithFloat
---@field Reason Variant # Manual or StressBreak
---@field GetFloat fun(self: VoxelAssemblyMemberDetachedEventData, field: "BreakFactor"): number
---@field GetPtr fun(self: VoxelAssemblyMemberDetachedEventData, field: "Assembly"): VoxelAssembly
---@field GetPtr fun(self: VoxelAssemblyMemberDetachedEventData, field: "Volume"): VoxelVolume
---@field GetVector3 fun(self: VoxelAssemblyMemberDetachedEventData, field: "Force"): Vector3
---@field GetVector3 fun(self: VoxelAssemblyMemberDetachedEventData, field: "Torque"): Vector3

--- VoxelAssemblyRootChanged event data
---@class VoxelAssemblyRootChangedEventData
---@field Assembly VariantWithPtr
---@field OldRoot VariantWithPtr
---@field NewRoot VariantWithPtr
---@field GetPtr fun(self: VoxelAssemblyRootChangedEventData, field: "Assembly"): VoxelAssembly
---@field GetPtr fun(self: VoxelAssemblyRootChangedEventData, field: "OldRoot"): VoxelVolume
---@field GetPtr fun(self: VoxelAssemblyRootChangedEventData, field: "NewRoot"): VoxelVolume

--- VoxelContact event data
---@class VoxelContactEventData
---@field VolumeA VariantWithPtr # or null (test body)
---@field VolumeB VariantWithPtr # or null
---@field Position VariantWithVector3 # world-space contact point
---@field Velocity VariantWithFloat # closing speed along the contact normal
---@field GetFloat fun(self: VoxelContactEventData, field: "Velocity"): number
---@field GetPtr fun(self: VoxelContactEventData, field: "VolumeA"): VoxelVolume
---@field GetPtr fun(self: VoxelContactEventData, field: "VolumeB"): VoxelVolume
---@field GetVector3 fun(self: VoxelContactEventData, field: "Position"): Vector3

--- VoxelContentReady event data
---@class VoxelContentReadyEventData
---@field Volume VariantWithPtr
---@field CollisionReady VariantWithBool
---@field GetBool fun(self: VoxelContentReadyEventData, field: "CollisionReady"): boolean
---@field GetPtr fun(self: VoxelContentReadyEventData, field: "Volume"): VoxelVolume

--- VoxelDamaged event data
---@class VoxelDamagedEventData
---@field Volume VariantWithPtr
---@field Position VariantWithVector3 # world-space damage centre
---@field Radius VariantWithFloat # nominal damage radius
---@field Removed VariantWithInt # voxels destroyed
---@field Material VariantWithInt # dominant removed palette index
---@field GetFloat fun(self: VoxelDamagedEventData, field: "Radius"): number
---@field GetInt fun(self: VoxelDamagedEventData, field: "Removed"): integer
---@field GetInt fun(self: VoxelDamagedEventData, field: "Material"): integer
---@field GetPtr fun(self: VoxelDamagedEventData, field: "Volume"): VoxelVolume
---@field GetVector3 fun(self: VoxelDamagedEventData, field: "Position"): Vector3

--- VoxelFragmentFrozen event data
---@class VoxelFragmentFrozenEventData
---@field Volume VariantWithPtr
---@field Position VariantWithVector3 # world position of its node
---@field GetPtr fun(self: VoxelFragmentFrozenEventData, field: "Volume"): VoxelVolume
---@field GetVector3 fun(self: VoxelFragmentFrozenEventData, field: "Position"): Vector3

--- VoxelInitialSyncFinished event data
---@class VoxelInitialSyncFinishedEventData
---@field World VariantWithPtr
---@field GetPtr fun(self: VoxelInitialSyncFinishedEventData, field: "World"): VoxelPhysicsWorld

--- VoxelSevered event data
---@class VoxelSeveredEventData
---@field Volume VariantWithPtr # the parent
---@field Fragment VariantWithPtr # the severed piece
---@field Voxels VariantWithInt # voxels in the piece
---@field Anchored VariantWithBool # true = stayed standing as static
---@field GetBool fun(self: VoxelSeveredEventData, field: "Anchored"): boolean
---@field GetInt fun(self: VoxelSeveredEventData, field: "Voxels"): integer
---@field GetPtr fun(self: VoxelSeveredEventData, field: "Volume"): VoxelVolume
---@field GetPtr fun(self: VoxelSeveredEventData, field: "Fragment"): VoxelVolume

--- VoxelSyncFailed event data
---@class VoxelSyncFailedEventData
---@field Reason VariantWithString
---@field GetString fun(self: VoxelSyncFailedEventData, field: "Reason"): string

--- WindowClosed event data
---@class WindowClosedEventData

--- WindowPos event data
---@class WindowPosEventData
---@field X VariantWithInt
---@field Y VariantWithInt
---@field GetInt fun(self: WindowPosEventData, field: "X"): integer
---@field GetInt fun(self: WindowPosEventData, field: "Y"): integer

--- WorldPartitionReady event data
---@class WorldPartitionReadyEventData
---@field Component VariantWithPtr
---@field GetPtr fun(self: WorldPartitionReadyEventData, field: "Component"): WorldPartitionComponent
