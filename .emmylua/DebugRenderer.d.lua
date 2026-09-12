---@meta

--- Auto-generated from Graphics/DebugRenderer

---@class DebugRenderer : Component
---@field lineAntiAlias boolean
---@field view Matrix3x4
---@field projection Matrix4
---@field frustum Frustum
DebugRenderer = {}

---@param enable boolean
---@return nil
function DebugRenderer:SetLineAntiAlias(enable) end

---@param camera Camera
---@return nil
function DebugRenderer:SetView(camera) end

---@param start Vector3
---@param end_ Vector3
---@param color Color
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddLine(start, end_, color, depthTest) end

---@param start Vector3
---@param end_ Vector3
---@param color integer
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddLine(start, end_, color, depthTest) end

---@param v1 Vector3
---@param v2 Vector3
---@param v3 Vector3
---@param color Color
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddTriangle(v1, v2, v3, color, depthTest) end

---@param v1 Vector3
---@param v2 Vector3
---@param v3 Vector3
---@param color integer
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddTriangle(v1, v2, v3, color, depthTest) end

---@param v1 Vector3
---@param v2 Vector3
---@param v3 Vector3
---@param v4 Vector3
---@param color Color
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddPolygon(v1, v2, v3, v4, color, depthTest) end

---@param v1 Vector3
---@param v2 Vector3
---@param v3 Vector3
---@param v4 Vector3
---@param color integer
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddPolygon(v1, v2, v3, v4, color, depthTest) end

---@param node Node
---@param scale? number
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddNode(node, scale, depthTest) end

---@param box BoundingBox
---@param color Color
---@param depthTest? boolean
---@param solid? boolean
---@return nil
function DebugRenderer:AddBoundingBox(box, color, depthTest, solid) end

---@param box BoundingBox
---@param transform Matrix3x4
---@param color Color
---@param depthTest? boolean
---@param solid? boolean
---@return nil
function DebugRenderer:AddBoundingBox(box, transform, color, depthTest, solid) end

---@param frustum Frustum
---@param color Color
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddFrustum(frustum, color, depthTest) end

---@param poly Polyhedron
---@param color Color
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddPolyhedron(poly, color, depthTest) end

---@param sphere Sphere
---@param color Color
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddSphere(sphere, color, depthTest) end

---@param sphere Sphere
---@param rotation Quaternion
---@param angle number
---@param drawLines boolean
---@param color Color
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddSphereSector(sphere, rotation, angle, drawLines, color, depthTest) end

---@param skeleton Skeleton
---@param color Color
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddSkeleton(skeleton, color, depthTest) end

-- Method AddTriangleMesh is not supported (uses void* pointer)

-- Method AddTriangleMesh is not supported (uses void* pointer)

---@param center Vector3
---@param normal Vector3
---@param radius number
---@param color Color
---@param steps? integer
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddCircle(center, normal, radius, color, steps, depthTest) end

---@param center Vector3
---@param size number
---@param color Color
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddCross(center, size, color, depthTest) end

---@param center Vector3
---@param width number
---@param height number
---@param color Color
---@param depthTest? boolean
---@return nil
function DebugRenderer:AddQuad(center, width, height, color, depthTest) end

---@return nil
function DebugRenderer:Render() end

---@return boolean
function DebugRenderer:GetLineAntiAlias() end

---@return Matrix3x4
function DebugRenderer:GetView() end

---@return Matrix4
function DebugRenderer:GetProjection() end

---@return Frustum
function DebugRenderer:GetFrustum() end

---@param box BoundingBox
---@return boolean
function DebugRenderer:IsInside(box) end

