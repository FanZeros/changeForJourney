---@meta

--- Auto-generated from Graphics/ProceduralGeometry

---@class ProceduralGeometry : RefCounted
ProceduralGeometry = {}

---@param enable boolean
---@return nil
function ProceduralGeometry:SetConvertHandedness(enable) end

---@param enable boolean
---@return nil
function ProceduralGeometry:SetDynamic(enable) end

---@param enable boolean
---@return nil
function ProceduralGeometry:SetShadowed(enable) end

---@param enable boolean
---@return nil
function ProceduralGeometry:SetGenerateTangents(enable) end

---@return Model
function ProceduralGeometry:ToModel() end

---@param geometry CustomGeometry
---@return boolean
function ProceduralGeometry:FillCustomGeometry(geometry) end

---@return integer
function ProceduralGeometry:GetVertexCount() end

---@return integer
function ProceduralGeometry:GetIndexCount() end

---@return integer
function ProceduralGeometry:GetGroupCount() end

---@return BoundingBox
function ProceduralGeometry:GetBoundingBox() end


-- Global functions
---@param width? number
---@param height? number
---@param widthSegments? integer
---@param heightSegments? integer
---@return ProceduralGeometry
function PlaneGeometry(width, height, widthSegments, heightSegments) end

---@param width? number
---@param height? number
---@param depth? number
---@param widthSegments? integer
---@param heightSegments? integer
---@param depthSegments? integer
---@return ProceduralGeometry
function BoxGeometry(width, height, depth, widthSegments, heightSegments, depthSegments) end

---@param radius? number
---@param widthSegments? integer
---@param heightSegments? integer
---@param phiStart? number
---@param phiLength? number
---@param thetaStart? number
---@param thetaLength? number
---@return ProceduralGeometry
function SphereGeometry(radius, widthSegments, heightSegments, phiStart, phiLength, thetaStart, thetaLength) end

---@param radiusTop? number
---@param radiusBottom? number
---@param height? number
---@param radialSegments? integer
---@param heightSegments? integer
---@param openEnded? boolean
---@param thetaStart? number
---@param thetaLength? number
---@return ProceduralGeometry
function CylinderGeometry(radiusTop, radiusBottom, height, radialSegments, heightSegments, openEnded, thetaStart, thetaLength) end

---@param radius? number
---@param height? number
---@param radialSegments? integer
---@param heightSegments? integer
---@param openEnded? boolean
---@param thetaStart? number
---@param thetaLength? number
---@return ProceduralGeometry
function ConeGeometry(radius, height, radialSegments, heightSegments, openEnded, thetaStart, thetaLength) end

---@param radius? number
---@param segments? integer
---@param thetaStart? number
---@param thetaLength? number
---@return ProceduralGeometry
function CircleGeometry(radius, segments, thetaStart, thetaLength) end

---@param innerRadius? number
---@param outerRadius? number
---@param thetaSegments? integer
---@param phiSegments? integer
---@param thetaStart? number
---@param thetaLength? number
---@return ProceduralGeometry
function RingGeometry(innerRadius, outerRadius, thetaSegments, phiSegments, thetaStart, thetaLength) end

---@param radius? number
---@param tube? number
---@param radialSegments? integer
---@param tubularSegments? integer
---@param arc? number
---@return ProceduralGeometry
function TorusGeometry(radius, tube, radialSegments, tubularSegments, arc) end

---@param radius? number
---@param detail? integer
---@return ProceduralGeometry
function TetrahedronGeometry(radius, detail) end

---@param radius? number
---@param detail? integer
---@return ProceduralGeometry
function OctahedronGeometry(radius, detail) end

---@param radius? number
---@param detail? integer
---@return ProceduralGeometry
function IcosahedronGeometry(radius, detail) end

---@param radius? number
---@param detail? integer
---@return ProceduralGeometry
function DodecahedronGeometry(radius, detail) end

---@param vertices number[]
---@param indices integer[]
---@param radius? number
---@param detail? integer
---@return ProceduralGeometry
function PolyhedronGeometry(vertices, indices, radius, detail) end

---@param func integer|string Built-in surface: enum index (0=Klein 1=Plane 2=Mobius 3=Mobius3D) or a case-insensitive name
---@param slices? integer
---@param stacks? integer
---@return ProceduralGeometry
function ParametricGeometry(func, slices, stacks) end

---@param geometry ProceduralGeometry
---@return ProceduralGeometry
function WireframeGeometry(geometry) end

---@param geometry ProceduralGeometry
---@param thresholdAngle? number
---@return ProceduralGeometry
function EdgesGeometry(geometry, thresholdAngle) end

---@param width? number
---@param height? number
---@param depth? number
---@param widthSegments? integer
---@param heightSegments? integer
---@param depthSegments? integer
---@return ProceduralGeometry
function BoxLineGeometry(width, height, depth, widthSegments, heightSegments, depthSegments) end

---@param radius? number
---@param tube? number
---@param tubularSegments? integer
---@param radialSegments? integer
---@param p? integer
---@param q? integer
---@return ProceduralGeometry
function TorusKnotGeometry(radius, tube, tubularSegments, radialSegments, p, q) end

---@param points Vector2[]
---@param segments? integer
---@param phiStart? number
---@param phiLength? number
---@return ProceduralGeometry
function LatheGeometry(points, segments, phiStart, phiLength) end

---@param points Vector3[]
---@param tubularSegments? integer
---@param radius? number
---@param radialSegments? integer
---@param closed? boolean
---@return ProceduralGeometry
function TubeGeometry(points, tubularSegments, radius, radialSegments, closed) end

---@param radius? number
---@param height? number
---@param capSegments? integer
---@param radialSegments? integer
---@param heightSegments? integer
---@return ProceduralGeometry
function CapsuleGeometry(radius, height, capSegments, radialSegments, heightSegments) end

---@param width? number
---@param height? number
---@param depth? number
---@param segments? integer
---@param radius? number
---@return ProceduralGeometry
function RoundedBoxGeometry(width, height, depth, segments, radius) end

---@param points Vector3[]
---@return ProceduralGeometry
function ConvexGeometry(points) end

---@param sections Vector3[][] Array of cross-sections, each a Lua array of Vector3 (uniform length)
---@param closedSections? boolean
---@return ProceduralGeometry
function LoftGeometry(sections, closedSections) end

---@param contour Vector2[]
---@return ProceduralGeometry
function ShapeGeometry(contour) end

---@param contour Vector2[]
---@param depth? number
---@return ProceduralGeometry
function ExtrudeGeometry(contour, depth) end

---@param mesh ProceduralGeometry
---@param position Vector3
---@param orientation Quaternion
---@param size Vector3
---@return ProceduralGeometry
function DecalGeometry(mesh, position, orientation, size) end

---@param size? number
---@param segments? integer
---@param bottom? boolean
---@param lid? boolean
---@param body? boolean
---@param fitLid? boolean
---@param blinn? boolean
---@return ProceduralGeometry
function TeapotGeometry(size, segments, bottom, lid, body, fitLid, blinn) end
