---@meta

--- Auto-generated from Graphics/CustomGeometry

---@class CustomGeometryVertex
---@field position Vector3
---@field normal Vector3
---@field color integer
---@field texCoord Vector2
---@field tangent Vector4
CustomGeometryVertex = {}


---@class CustomGeometry : Drawable
---@field material Material
---@field numGeometries integer
---@field dynamic boolean
---@field useInstanceColor boolean Enable the Surface Shader INSTANCE_COLOR input for CustomGeometry.
---@field instanceColor Color Surface Shader INSTANCE_COLOR input for CustomGeometry.
---@field useInstanceCustomData boolean
---@field instanceCustomData Vector4
CustomGeometry = {}

---@return nil
function CustomGeometry:Clear() end

---@param num integer
---@return nil
function CustomGeometry:SetNumGeometries(num) end

---@param enable boolean
---@return nil
function CustomGeometry:SetDynamic(enable) end

---@param index integer
---@param type PrimitiveType
---@return nil
function CustomGeometry:BeginGeometry(index, type) end

--- 绕序约定：三角形正面 = (v1-v0)×(v2-v0) 指向的一侧，正面须朝外，反了会被默认背面剔除。例：(0,0,0)→(0,0,1)→(1,0,0) 正面朝 +Y
---@param position Vector3
---@return nil
function CustomGeometry:DefineVertex(position) end

---@param normal Vector3
---@return nil
function CustomGeometry:DefineNormal(normal) end

---@param tangent Vector4
---@return nil
function CustomGeometry:DefineTangent(tangent) end

---@param color Color
---@return nil
function CustomGeometry:DefineColor(color) end

---@param texCoord Vector2
---@return nil
function CustomGeometry:DefineTexCoord(texCoord) end

---@param index integer
---@param type PrimitiveType
---@param numVertices integer
---@param hasNormals boolean
---@param hasColors boolean
---@param hasTexCoords boolean
---@param hasTangents boolean
---@return nil
function CustomGeometry:DefineGeometry(index, type, numVertices, hasNormals, hasColors, hasTexCoords, hasTangents) end

--- 从已定义的法线 + UV 一键生成切线（等价 Godot generate_tangents / Unity RecalculateTangents）。需法线贴图材质时必须显式调用：Commit() 不会自动生成。
--- 调用时机在 Define* 之后、Commit() 之前；前置条件是每个顶点都有 DefineNormal + DefineTexCoord。解出的 geometry 上已有切线会被重算覆盖；解不出的 geometry 保留原有切线。缺法线/UV 或没有 TRIANGLE_LIST 几何时返回 false 并打警告，不改动数据。
---@return boolean
function CustomGeometry:GenerateTangents() end

---@return nil
function CustomGeometry:Commit() end

---@param material Material
---@return nil
function CustomGeometry:SetMaterial(material) end

---@param index integer
---@param material Material
---@return boolean
function CustomGeometry:SetMaterial(index, material) end

---@return integer
function CustomGeometry:GetNumGeometries() end

---@param index integer
---@return integer
function CustomGeometry:GetNumVertices(index) end

---@param model Model
---@return boolean
function CustomGeometry:FillModel(model) end

---@return boolean
function CustomGeometry:IsDynamic() end

---@param index? integer
---@return Material
function CustomGeometry:GetMaterial(index) end

--- 注意：经本函数写入的字段引擎无法记账（分不清"写过"和"未初始化"）。切线要生效，请走 DefineTangent / GenerateTangents，
--- 或用 DefineGeometry(..., hasTangents=true) 声明"我自己填"——后者下 Commit() 不会碰这块 geometry 的顶点。
---@param geometryIndex integer
---@param vertexNum integer
---@return CustomGeometryVertex
function CustomGeometry:GetVertex(geometryIndex, vertexNum) end

--- Surface Shader INSTANCE_COLOR input for CustomGeometry.
---@param color Color
---@return nil
function CustomGeometry:SetInstanceColor(color) end

--- Surface Shader INSTANCE_COLOR input for CustomGeometry.
---@return Color
function CustomGeometry:GetInstanceColor() end

--- Surface Shader INSTANCE_CUSTOM data for CustomGeometry.
---@param data Vector4
---@return nil
function CustomGeometry:SetInstanceCustomData(data) end

--- Surface Shader INSTANCE_CUSTOM data for CustomGeometry.
---@return Vector4
function CustomGeometry:GetInstanceCustomData() end

