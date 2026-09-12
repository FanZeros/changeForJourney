---@meta

--- Auto-generated from Scene/Node

---@alias CreateMode
---| integer # CreateMode enum values

---@type CreateMode
REPLICATED = 0
---@type CreateMode
LOCAL = 1

---@alias TransformSpace
---| integer # TransformSpace enum values

---@type TransformSpace
TS_LOCAL = 0
---@type TransformSpace
TS_PARENT = 1
---@type TransformSpace
TS_WORLD = 2

---@class Node : Animatable
---@overload fun(): Node
---@field ID integer
---@field replicated boolean
---@field name string
---@field nameHash StringHash|string
---@field parent Node
---@field scene Scene
---@field enabled boolean
---@field enabledSelf boolean
---@field owner Connection
---@field position Vector3
---@field position2D Vector2
---@field rotation Quaternion
---@field rotation2D number
---@field direction Vector3
---@field up Vector3
---@field right Vector3
---@field scale Vector3
---@field scale2D Vector2
---@field transform Matrix3x4
---@field worldPosition Vector3
---@field worldPosition2D Vector2
---@field worldRotation Quaternion
---@field worldRotation2D number
---@field worldDirection Vector3
---@field worldUp Vector3
---@field worldRight Vector3
---@field worldScale Vector3
---@field signedWorldScale Vector3
---@field worldScale2D Vector2
---@field worldTransform Matrix3x4
---@field dirty boolean
---@field numChildren integer
---@field numComponents integer
---@field numNetworkComponents integer
---@field CreateComponent __union_func__type_str__mode_CreateMode_opt__id_int_opt__ret_ComponentT
---@field GetOrCreateComponent __union_func__type_str__mode_CreateMode_opt__id_int_opt__ret_ComponentT
---@field GetComponent __union_func__type_str__recursive_bool_opt__ret_ComponentT
---@field GetParentComponent __union_func__type_str__recursive_bool_opt__ret_ComponentT
---@field GetComponents __union_func__type_str__recursive_bool_opt__ret_ComponentT_arr
Node = {}

---@return Node
function Node.new() end

---@param dest File
---@param indentation? string
---@return boolean
function Node:SaveXML(dest, indentation) end

---@param dest File
---@param indentation? string
---@return boolean
function Node:SaveJSON(dest, indentation) end

---@param name string
---@return nil
function Node:SetName(name) end

---@param tag string
---@return nil
function Node:AddTag(tag) end

---@param tags string
---@param separator string
---@return nil
function Node:AddTags(tags, separator) end

---@param tag string
---@return boolean
function Node:RemoveTag(tag) end

---@return nil
function Node:RemoveAllTags() end

---@param position Vector3
---@return nil
function Node:SetPosition(position) end

---@param position Vector2
---@return nil
function Node:SetPosition2D(position) end

---@param x number
---@param y number
---@return nil
function Node:SetPosition2D(x, y) end

---@param rotation Quaternion
---@return nil
function Node:SetRotation(rotation) end

---@param rotation number
---@return nil
function Node:SetRotation2D(rotation) end

---@param direction Vector3
---@return nil
function Node:SetDirection(direction) end

---@param scale number
---@return nil
function Node:SetScale(scale) end

---@param scale Vector3
---@return nil
function Node:SetScale(scale) end

---@param scale Vector2
---@return nil
function Node:SetScale2D(scale) end

---@param x number
---@param y number
---@return nil
function Node:SetScale2D(x, y) end

---@param position Vector3
---@param rotation Quaternion
---@return nil
function Node:SetTransform(position, rotation) end

---@param position Vector3
---@param rotation Quaternion
---@param scale Vector3
---@return nil
function Node:SetTransform(position, rotation, scale) end

---@param position Vector3
---@param rotation Quaternion
---@param scale number
---@return nil
function Node:SetTransform(position, rotation, scale) end

---@param transform Matrix3x4
---@return nil
function Node:SetTransform(transform) end

---@param position Vector2
---@param rotation number
---@return nil
function Node:SetTransform2D(position, rotation) end

---@param position Vector2
---@param rotation number
---@param scale Vector2
---@return nil
function Node:SetTransform2D(position, rotation, scale) end

---@param position Vector2
---@param rotation number
---@param scale number
---@return nil
function Node:SetTransform2D(position, rotation, scale) end

---@param position Vector3
---@return nil
function Node:SetWorldPosition(position) end

---@param position Vector2
---@return nil
function Node:SetWorldPosition2D(position) end

---@param x number
---@param y number
---@return nil
function Node:SetWorldPosition2D(x, y) end

---@param rotation Quaternion
---@return nil
function Node:SetWorldRotation(rotation) end

---@param rotation number
---@return nil
function Node:SetWorldRotation2D(rotation) end

---@param direction Vector3
---@return nil
function Node:SetWorldDirection(direction) end

---@param scale number
---@return nil
function Node:SetWorldScale(scale) end

---@param scale Vector3
---@return nil
function Node:SetWorldScale(scale) end

---@param scale Vector2
---@return nil
function Node:SetWorldScale2D(scale) end

---@param x number
---@param y number
---@return nil
function Node:SetWorldScale2D(x, y) end

---@param position Vector3
---@param rotation Quaternion
---@return nil
function Node:SetWorldTransform(position, rotation) end

---@param position Vector3
---@param rotation Quaternion
---@param scale Vector3
---@return nil
function Node:SetWorldTransform(position, rotation, scale) end

---@param position Vector3
---@param rotation Quaternion
---@param scale number
---@return nil
function Node:SetWorldTransform(position, rotation, scale) end

---@param position Vector2
---@param rotation number
---@return nil
function Node:SetWorldTransform2D(position, rotation) end

---@param position Vector2
---@param rotation number
---@param scale Vector2
---@return nil
function Node:SetWorldTransform2D(position, rotation, scale) end

---@param position Vector2
---@param rotation number
---@param scale number
---@return nil
function Node:SetWorldTransform2D(position, rotation, scale) end

---@param delta Vector3
---@param space? TransformSpace
---@return nil
function Node:Translate(delta, space) end

---@param delta Vector2
---@param space? TransformSpace
---@return nil
function Node:Translate2D(delta, space) end

---@param delta Quaternion
---@param space? TransformSpace
---@return nil
function Node:Rotate(delta, space) end

---@param delta number
---@param space? TransformSpace
---@return nil
function Node:Rotate2D(delta, space) end

---@param point Vector3
---@param delta Quaternion
---@param space? TransformSpace
---@return nil
function Node:RotateAround(point, delta, space) end

---@param point Vector2
---@param delta number
---@param space? TransformSpace
---@return nil
function Node:RotateAround2D(point, delta, space) end

---@param angle number
---@param space? TransformSpace
---@return nil
function Node:Pitch(angle, space) end

---@param angle number
---@param space? TransformSpace
---@return nil
function Node:Yaw(angle, space) end

---@param angle number
---@param space? TransformSpace
---@return nil
function Node:Roll(angle, space) end

---@param target Vector3
---@param upAxis? Vector3
---@param space? TransformSpace
---@return boolean
function Node:LookAt(target, upAxis, space) end

---@param scale number
---@return nil
function Node:Scale(scale) end

---@param scale Vector3
---@return nil
function Node:Scale(scale) end

---@param scale Vector2
---@return nil
function Node:Scale2D(scale) end

---@param enable boolean
---@return nil
function Node:SetEnabled(enable) end

---@param enable boolean
---@return nil
function Node:SetDeepEnabled(enable) end

---@return nil
function Node:ResetDeepEnabled() end

---@param enable boolean
---@return nil
function Node:SetEnabledRecursive(enable) end

---@param owner Connection
---@return nil
function Node:SetOwner(owner) end

---@return nil
function Node:MarkDirty() end

---@param name? string
---@param mode? CreateMode
---@param id? integer
---@param temporary? boolean
---@return Node
function Node:CreateChild(name, mode, id, temporary) end

---@param id integer
---@param mode CreateMode
---@param temporary? boolean
---@return Node
function Node:CreateChild(id, mode, temporary) end

---@param name? string
---@param mode? CreateMode
---@param id? integer
---@return Node
function Node:CreateTemporaryChild(name, mode, id) end

---@param node Node
---@param index? integer
---@return nil
function Node:AddChild(node, index) end

---@param node Node
---@return nil
function Node:RemoveChild(node) end

---@return nil
function Node:RemoveAllChildren() end

---@param removeReplicated boolean
---@param removeLocal boolean
---@param recursive boolean
---@return nil
function Node:RemoveChildren(removeReplicated, removeLocal, recursive) end

---@param component Component
---@return nil
function Node:RemoveComponent(component) end

---@param type StringHash|string
---@return nil
function Node:RemoveComponent(type) end

---@param type string
---@return nil
function Node:RemoveComponent(type) end

---@param removeReplicated boolean
---@param removeLocal boolean
---@return nil
function Node:RemoveComponents(removeReplicated, removeLocal) end

---@param type string
---@return nil
function Node:RemoveComponents(type) end

---@return nil
function Node:RemoveAllComponents() end

---@param component Component
---@param index integer
---@return nil
function Node:ReorderComponent(component, index) end

---@param mode? CreateMode
---@return Node
function Node:Clone(mode) end

---@return nil
function Node:Remove() end

---@return nil
function Node:Dispose() end

---@param parent Node
---@return nil
function Node:SetParent(parent) end

---@param key StringHash|string
---@param value Variant
---@return nil
function Node:SetVar(key, value) end

---@param key string
---@param value Variant
---@return nil
function Node:SetVar(key, value) end

---@param component Component
---@return nil
function Node:AddListener(component) end

---@param component Component
---@return nil
function Node:RemoveListener(component) end

---@param component Component
---@param id? integer
---@return Component
function Node:CloneComponent(component, id) end

---@param component Component
---@param mode CreateMode
---@param id? integer
---@return Component
function Node:CloneComponent(component, mode, id) end

---@param scriptObjectType string
---@return LuaScriptObject?
function Node:CreateScriptObject(scriptObjectType) end

---@param fileName string
---@param scriptObjectType string
---@return LuaScriptObject?
function Node:CreateScriptObject(fileName, scriptObjectType) end

---@return LuaScriptObject?
function Node:GetScriptObject() end

---@param scriptObjectType string
---@return LuaScriptObject?
function Node:GetScriptObject(scriptObjectType) end

---@return integer
function Node:GetID() end

---@return boolean
function Node:IsReplicated() end

---@return string
function Node:GetName() end

---@return StringHash|string
function Node:GetNameHash() end

---@return Node
function Node:GetParent() end

---@return Scene
function Node:GetScene() end

---@param node Node
---@return boolean
function Node:IsChildOf(node) end

---@return boolean
function Node:IsEnabled() end

---@return boolean
function Node:IsEnabledSelf() end

---@return Connection
function Node:GetOwner() end

---@return Vector3
function Node:GetPosition() end

---@return Vector2
function Node:GetPosition2D() end

---@return Quaternion
function Node:GetRotation() end

---@return number
function Node:GetRotation2D() end

---@return Vector3
function Node:GetDirection() end

---@return Vector3
function Node:GetUp() end

---@return Vector3
function Node:GetRight() end

---@return Vector3
function Node:GetScale() end

---@return Vector2
function Node:GetScale2D() end

---@return Matrix3x4
function Node:GetTransform() end

---@return Vector3
function Node:GetWorldPosition() end

---@return Vector2
function Node:GetWorldPosition2D() end

---@return Quaternion
function Node:GetWorldRotation() end

---@return number
function Node:GetWorldRotation2D() end

---@return Vector3
function Node:GetWorldDirection() end

---@return Vector3
function Node:GetWorldUp() end

---@return Vector3
function Node:GetWorldRight() end

---@return Vector3
function Node:GetWorldScale() end

---@return Vector3
function Node:GetSignedWorldScale() end

---@return Vector2
function Node:GetWorldScale2D() end

---@return Matrix3x4
function Node:GetWorldTransform() end

---@param position Vector3
---@return Vector3
function Node:LocalToWorld(position) end

---@param vector Vector4
---@return Vector3
function Node:LocalToWorld(vector) end

---@param vector Vector2
---@return Vector2
function Node:LocalToWorld2D(vector) end

---@param position Vector3
---@return Vector3
function Node:WorldToLocal(position) end

---@param vector Vector4
---@return Vector3
function Node:WorldToLocal(vector) end

---@param vector Vector2
---@return Vector2
function Node:WorldToLocal2D(vector) end

---@return boolean
function Node:IsDirty() end

---@param recursive? boolean
---@return integer
function Node:GetNumChildren(recursive) end

---@param name string
---@param recursive? boolean
---@return Node
function Node:GetChild(name, recursive) end

---@param nameHash StringHash|string
---@param recursive? boolean
---@return Node
function Node:GetChild(nameHash, recursive) end

---@param index integer
---@return Node
function Node:GetChild(index) end

---@return integer
function Node:GetNumComponents() end

---@return integer
function Node:GetNumNetworkComponents() end

---@param type StringHash|string
---@return boolean
function Node:HasComponent(type) end

---@param type string
---@return boolean
function Node:HasComponent(type) end

---@param key StringHash|string
---@return Variant
function Node:GetVar(key) end

---@param key string
---@return Variant
function Node:GetVar(key) end

---@return VariantMap
function Node:GetVars() end

---@param recursive? boolean
---@return Node[]
function Node:GetChildren(recursive) end

---@param type string
---@param recursive? boolean
---@return Node[]
function Node:GetChildrenWithComponent(type, recursive) end

---@param source XMLElement
---@return boolean
function Node:LoadXML(source) end

---@param source XMLElement
---@param resolver SceneResolver
---@param loadChildren? boolean
---@param rewriteIDs? boolean
---@param mode? CreateMode
---@return boolean
function Node:LoadXML(source, resolver, loadChildren, rewriteIDs, mode) end

---@param source JSONValue
---@return boolean
function Node:LoadJSON(source) end

---@param source JSONValue
---@param resolver SceneResolver
---@param loadChildren? boolean
---@param rewriteIDs? boolean
---@param mode? CreateMode
---@return boolean
function Node:LoadJSON(source, resolver, loadChildren, rewriteIDs, mode) end

---@param source Deserializer
---@param resolver SceneResolver
---@param loadChildren? boolean
---@param rewriteIDs? boolean
---@param mode? CreateMode
---@return boolean
function Node:Load(source, resolver, loadChildren, rewriteIDs, mode) end

---@param component Component
---@param id integer
---@param mode CreateMode
---@return nil
function Node:AddComponent(component, id, mode) end

---@param tag string
---@return boolean
function Node:HasTag(tag) end

---@return StringVector
function Node:GetTags() end

---@param tag string
---@param recursive? boolean
---@return Node[]
function Node:GetChildrenWithTag(tag, recursive) end

---@param tag string
---@param recursive? boolean
---@return Node[]
function Node:GetChildrenWithName(tag, recursive) end

---@param id integer
---@return nil
function Node:SetID(id) end

