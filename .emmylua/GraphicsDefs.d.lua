---@meta

--- Auto-generated from Graphics/GraphicsDefs

---@alias PrimitiveType
---| integer # PrimitiveType enum values

---@type PrimitiveType
TRIANGLE_LIST = 0
---@type PrimitiveType
LINE_LIST = 1
---@type PrimitiveType
POINT_LIST = 2
---@type PrimitiveType
TRIANGLE_STRIP = 3
---@type PrimitiveType
LINE_STRIP = 4
---@type PrimitiveType
TRIANGLE_FAN = 5

---@alias GeometryType
---| integer # GeometryType enum values

---@type GeometryType
GEOM_STATIC = 0
---@type GeometryType
GEOM_SKINNED = 1
---@type GeometryType
GEOM_INSTANCED = 2
---@type GeometryType
GEOM_BILLBOARD = 3
---@type GeometryType
GEOM_STATIC_NOINSTANCING = 4
---@type GeometryType
MAX_GEOMETRYTYPES = 4

---@alias BlendMode
---| integer # BlendMode enum values

---@type BlendMode
BLEND_REPLACE = 0
---@type BlendMode
BLEND_ADD = 1
---@type BlendMode
BLEND_MULTIPLY = 2
---@type BlendMode
BLEND_ALPHA = 3
---@type BlendMode
BLEND_ADDALPHA = 4
---@type BlendMode
BLEND_PREMULALPHA = 5
---@type BlendMode
BLEND_INVDESTALPHA = 6
---@type BlendMode
BLEND_SUBTRACT = 7
---@type BlendMode
BLEND_SUBTRACTALPHA = 8
---@type BlendMode
MAX_BLENDMODES = 9

---@alias CompareMode
---| integer # CompareMode enum values

---@type CompareMode
CMP_ALWAYS = 0
---@type CompareMode
CMP_EQUAL = 1
---@type CompareMode
CMP_NOTEQUAL = 2
---@type CompareMode
CMP_LESS = 3
---@type CompareMode
CMP_LESSEQUAL = 4
---@type CompareMode
CMP_GREATER = 5
---@type CompareMode
CMP_GREATEREQUAL = 6
---@type CompareMode
MAX_COMPAREMODES = 7

---@alias CullMode
---| integer # CullMode enum values

---@type CullMode
CULL_NONE = 0
---@type CullMode
CULL_CCW = 1
---@type CullMode
CULL_CW = 2
---@type CullMode
MAX_CULLMODES = 3

---@alias FillMode
---| integer # FillMode enum values

---@type FillMode
FILL_SOLID = 0
---@type FillMode
FILL_WIREFRAME = 1
---@type FillMode
FILL_POINT = 2

---@alias StencilOp
---| integer # StencilOp enum values

---@type StencilOp
OP_KEEP = 0
---@type StencilOp
OP_ZERO = 1
---@type StencilOp
OP_REF = 2
---@type StencilOp
OP_INCR = 3
---@type StencilOp
OP_DECR = 4

---@alias LockState
---| integer # LockState enum values

---@type LockState
LOCK_NONE = 0
---@type LockState
LOCK_HARDWARE = 1
---@type LockState
LOCK_SHADOW = 2
---@type LockState
LOCK_SCRATCH = 3

---@alias LegacyVertexElement
---| integer # LegacyVertexElement enum values

---@type LegacyVertexElement
ELEMENT_POSITION = 0
---@type LegacyVertexElement
ELEMENT_NORMAL = 1
---@type LegacyVertexElement
ELEMENT_COLOR = 2
---@type LegacyVertexElement
ELEMENT_TEXCOORD1 = 3
---@type LegacyVertexElement
ELEMENT_TEXCOORD2 = 4
---@type LegacyVertexElement
ELEMENT_CUBETEXCOORD1 = 5
---@type LegacyVertexElement
ELEMENT_CUBETEXCOORD2 = 6
---@type LegacyVertexElement
ELEMENT_TANGENT = 7
---@type LegacyVertexElement
ELEMENT_BLENDWEIGHTS = 8
---@type LegacyVertexElement
ELEMENT_BLENDINDICES = 9
---@type LegacyVertexElement
ELEMENT_INSTANCEMATRIX1 = 10
---@type LegacyVertexElement
ELEMENT_INSTANCEMATRIX2 = 11
---@type LegacyVertexElement
ELEMENT_INSTANCEMATRIX3 = 12
---@type LegacyVertexElement
ELEMENT_OBJECTINDEX = 13
---@type LegacyVertexElement
MAX_LEGACY_VERTEX_ELEMENTS = 14

---@alias VertexElementType
---| integer # VertexElementType enum values

---@type VertexElementType
TYPE_INT = 0
---@type VertexElementType
TYPE_FLOAT = 1
---@type VertexElementType
TYPE_VECTOR2 = 2
---@type VertexElementType
TYPE_VECTOR3 = 3
---@type VertexElementType
TYPE_VECTOR4 = 4
---@type VertexElementType
TYPE_UBYTE4 = 5
---@type VertexElementType
TYPE_UBYTE4_NORM = 6
---@type VertexElementType
MAX_VERTEX_ELEMENT_TYPES = 7

---@alias VertexElementSemantic
---| integer # VertexElementSemantic enum values

---@type VertexElementSemantic
SEM_POSITION = 0
---@type VertexElementSemantic
SEM_NORMAL = 1
---@type VertexElementSemantic
SEM_BINORMAL = 2
---@type VertexElementSemantic
SEM_TANGENT = 3
---@type VertexElementSemantic
SEM_TEXCOORD = 4
---@type VertexElementSemantic
SEM_COLOR = 5
---@type VertexElementSemantic
SEM_BLENDWEIGHTS = 6
---@type VertexElementSemantic
SEM_BLENDINDICES = 7
---@type VertexElementSemantic
SEM_OBJECTINDEX = 8
---@type VertexElementSemantic
MAX_VERTEX_ELEMENT_SEMANTICS = 9

---@alias TextureFilterMode
---| integer # TextureFilterMode enum values

---@type TextureFilterMode
FILTER_NEAREST = 0
---@type TextureFilterMode
FILTER_BILINEAR = 1
---@type TextureFilterMode
FILTER_TRILINEAR = 2
---@type TextureFilterMode
FILTER_ANISOTROPIC = 3
---@type TextureFilterMode
FILTER_NEAREST_ANISOTROPIC = 4
---@type TextureFilterMode
FILTER_DEFAULT = 5
---@type TextureFilterMode
MAX_FILTERMODES = 6

---@alias TextureAddressMode
---| integer # TextureAddressMode enum values

---@type TextureAddressMode
ADDRESS_WRAP = 0
---@type TextureAddressMode
ADDRESS_MIRROR = 1
---@type TextureAddressMode
ADDRESS_CLAMP = 2
---@type TextureAddressMode
ADDRESS_BORDER = 3
---@type TextureAddressMode
MAX_ADDRESSMODES = 4

---@alias TextureCoordinate
---| integer # TextureCoordinate enum values

---@type TextureCoordinate
COORD_U = 0
---@type TextureCoordinate
COORD_V = 1
---@type TextureCoordinate
COORD_W = 2
---@type TextureCoordinate
MAX_COORDS = 3

---@alias TextureUsage
---| integer # TextureUsage enum values

---@type TextureUsage
TEXTURE_STATIC = 0
---@type TextureUsage
TEXTURE_DYNAMIC = 1
---@type TextureUsage
TEXTURE_RENDERTARGET = 2
---@type TextureUsage
TEXTURE_DEPTHSTENCIL = 3

---@alias CubeMapFace
---| integer # CubeMapFace enum values

---@type CubeMapFace
FACE_POSITIVE_X = 0
---@type CubeMapFace
FACE_NEGATIVE_X = 1
---@type CubeMapFace
FACE_POSITIVE_Y = 2
---@type CubeMapFace
FACE_NEGATIVE_Y = 3
---@type CubeMapFace
FACE_POSITIVE_Z = 4
---@type CubeMapFace
FACE_NEGATIVE_Z = 5
---@type CubeMapFace
MAX_CUBEMAP_FACES = 6

---@alias RenderSurfaceUpdateMode
---| integer # RenderSurfaceUpdateMode enum values

---@type RenderSurfaceUpdateMode
SURFACE_MANUALUPDATE = 0
---@type RenderSurfaceUpdateMode
SURFACE_UPDATEVISIBLE = 1
---@type RenderSurfaceUpdateMode
SURFACE_UPDATEALWAYS = 2

---@alias ShaderType
---| integer # ShaderType enum values

---@type ShaderType
VS = 0
---@type ShaderType
PS = 1

---@alias TextureUnit
---| integer # TextureUnit enum values

---@type TextureUnit
TU_DIFFUSE = 0
---@type TextureUnit
TU_ALBEDOBUFFER = 0
---@type TextureUnit
TU_NORMAL = 1
---@type TextureUnit
TU_NORMALBUFFER = 1
---@type TextureUnit
TU_SPECULAR = 2
---@type TextureUnit
TU_EMISSIVE = 3
---@type TextureUnit
TU_ENVIRONMENT = 4

---@alias FaceCameraMode
---| integer # FaceCameraMode enum values

---@type FaceCameraMode
FC_NONE = 0
---@type FaceCameraMode
FC_ROTATE_XYZ = 1
---@type FaceCameraMode
FC_ROTATE_Y = 2
---@type FaceCameraMode
FC_LOOKAT_XYZ = 3
---@type FaceCameraMode
FC_LOOKAT_Y = 4
---@type FaceCameraMode
FC_LOOKAT_MIXED = 5
---@type FaceCameraMode
FC_DIRECTION = 6

---@alias ShadowQuality
---| integer # ShadowQuality enum values

---@type ShadowQuality
SHADOWQUALITY_SIMPLE_16BIT = 0
---@type ShadowQuality
SHADOWQUALITY_SIMPLE_24BIT = 1
---@type ShadowQuality
SHADOWQUALITY_PCF_16BIT = 2
---@type ShadowQuality
SHADOWQUALITY_PCF_24BIT = 3
---@type ShadowQuality
SHADOWQUALITY_VSM = 4
---@type ShadowQuality
SHADOWQUALITY_BLUR_VSM = 5

---@alias VolumetricFogQuality
---| integer # VolumetricFogQuality enum values

---@type VolumetricFogQuality
VOLUMETRIC_FOG_QUALITY_LOW = 0
---@type VolumetricFogQuality
VOLUMETRIC_FOG_QUALITY_HIGH = 1
---@type VolumetricFogQuality
VOLUMETRIC_FOG_QUALITY_ULTRA = 2

---@alias MaterialQuality
---| integer # MaterialQuality enum values

---@type MaterialQuality
QUALITY_LOW = 0
---@type MaterialQuality
QUALITY_MEDIUM = 1
---@type MaterialQuality
QUALITY_HIGH = 2
---@type MaterialQuality
QUALITY_MAX = 3

---@alias ClearTarget
---| integer # ClearTarget enum values

---@type ClearTarget
CLEAR_COLOR = 0
---@type ClearTarget
CLEAR_DEPTH = 1
---@type ClearTarget
CLEAR_STENCIL = 2

---@alias VertexMask
---| integer # VertexMask enum values

---@type VertexMask
MASK_NONE = 0
---@type VertexMask
MASK_POSITION = 1
---@type VertexMask
MASK_NORMAL = 2
---@type VertexMask
MASK_COLOR = 3
---@type VertexMask
MASK_TEXCOORD1 = 4
---@type VertexMask
MASK_TEXCOORD2 = 5
---@type VertexMask
MASK_CUBETEXCOORD1 = 6
---@type VertexMask
MASK_CUBETEXCOORD2 = 7
---@type VertexMask
MASK_TANGENT = 8
---@type VertexMask
MASK_BLENDWEIGHTS = 9
---@type VertexMask
MASK_BLENDINDICES = 10
---@type VertexMask
MASK_INSTANCEMATRIX1 = 11
---@type VertexMask
MASK_INSTANCEMATRIX2 = 12
---@type VertexMask
MASK_INSTANCEMATRIX3 = 13
---@type VertexMask
MASK_OBJECTINDEX = 14

---@class VertexElement
---@overload fun(type: VertexElementType, semantic: VertexElementSemantic, index?: number, perInstance?: boolean): VertexElement
---@overload fun(): VertexElement
---@field type VertexElementType
---@field semantic VertexElementSemantic
---@field index number -- unsigned char
---@field perInstance boolean
---@field offset integer
VertexElement = {}

---@overload fun(self: VertexElement, type: VertexElementType, semantic: VertexElementSemantic, index?: number, perInstance?: boolean): VertexElement
---@overload fun(type: VertexElementType, semantic: VertexElementSemantic, index?: number, perInstance?: boolean): VertexElement
---@return VertexElement
function VertexElement.new() end


-- Global variables
---@type integer
MAX_MATERIAL_TEXTURE_UNITS = nil
