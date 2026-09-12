---@meta

--- Auto-generated from UI/NanoVG

---@alias NVGsizeMethod
---| integer # NVGsizeMethod enum values

---@type NVGsizeMethod
NVG_SIZE_PIXEL = 0
---@type NVGsizeMethod
NVG_SIZE_CHAR = 1

---@alias NVGtextScaleMode
---| integer # NVGtextScaleMode enum values

---@type NVGtextScaleMode
NVG_TEXT_SCALE_FULL = 0
---@type NVGtextScaleMode
NVG_TEXT_SCALE_DPR_ONLY = 1

-- Global functions
--- Create NanoVG context (automatically manages BGFX ViewId).
---@param edgeAntiAlias integer Enable edge anti-aliasing (0=off, 1=on)
---@return NVGContextWrapper # NanoVG context
function nvgCreate(edgeAntiAlias) end

--- Delete NanoVG context.
---@param ctx NVGContextWrapper NanoVG context
---@return nil
function nvgDelete(ctx) end

--- Set NanoVG bloom enable.
---@param wrapper NVGContextWrapper Wrapped context
---@param enable boolean
---@return nil
function nvgSetBloomEnabled(wrapper, enable) end

--- Set NanoVG color space.
---@param wrapper NVGContextWrapper Wrapped context
---@param colorSpace NVGColorSpace
---@return nil
function nvgSetColorSpace(wrapper, colorSpace) end

--- Set NanoVG context render to texture.
---@param ctx NVGContextWrapper
---@param renderTarget Texture2D
---@return nil
function nvgSetRenderTarget(ctx, renderTarget) end

--- Set NanoVG render order (priority).
--- Lower values render first (at bottom), higher values render last (on top).
---@param ctx NVGContextWrapper
---@param renderOrder integer Render priority value
---@return nil
function nvgSetRenderOrder(ctx, renderOrder) end

--- Begin drawing a new frame (automatically sets ViewId from Graphics subsystem).
---@param ctx NVGContextWrapper NanoVG context
---@param windowWidth number Window width in pixels
---@param windowHeight number Window height in pixels
---@param devicePixelRatio number Device pixel ratio (usually 1.0)
---@return nil
function nvgBeginFrame(ctx, windowWidth, windowHeight, devicePixelRatio) end

--- Cancel drawing the current frame.
---@param ctx NVGContextWrapper NanoVG context
---@return nil
function nvgCancelFrame(ctx) end

--- End drawing flushing remaining render state.
---@param ctx NVGContextWrapper NanoVG context
---@return nil
function nvgEndFrame(ctx) end

--- Set the composite operation.
---@param ctx NVGContextWrapper
---@param op integer
---@return nil
function nvgGlobalCompositeOperation(ctx, op) end

--- Set the composite operation with custom pixel arithmetic.
---@param ctx NVGContextWrapper
---@param sfactor integer
---@param dfactor integer
---@return nil
function nvgGlobalCompositeBlendFunc(ctx, sfactor, dfactor) end

--- Set the composite operation with custom pixel arithmetic for RGB and alpha separately.
---@param ctx NVGContextWrapper
---@param srcRGB integer
---@param dstRGB integer
---@param srcAlpha integer
---@param dstAlpha integer
---@return nil
function nvgGlobalCompositeBlendFuncSeparate(ctx, srcRGB, dstRGB, srcAlpha, dstAlpha) end

--- Push and save the current render state into a state stack.
---@param ctx NVGContextWrapper
---@return nil
function nvgSave(ctx) end

--- Pop and restore current render state.
---@param ctx NVGContextWrapper
---@return nil
function nvgRestore(ctx) end

--- Reset current render state to default values.
---@param ctx NVGContextWrapper
---@return nil
function nvgReset(ctx) end

--- Set whether to draw antialias for stroke and fill.
---@param ctx NVGContextWrapper
---@param enabled integer
---@return nil
function nvgShapeAntiAlias(ctx, enabled) end

---@param ctx NVGContextWrapper
---@param enabled integer
---@return nil
function nvgFillThinDedup(ctx, enabled) end

--- Set current stroke style to a solid color.
---@param ctx NVGContextWrapper
---@param color NVGcolor
---@return nil
function nvgStrokeColor(ctx, color) end

--- Set current stroke style to a paint.
---@param ctx NVGContextWrapper
---@param paint NVGpaint
---@return nil
function nvgStrokePaint(ctx, paint) end

--- Set current fill style to a solid color.
---@param ctx NVGContextWrapper
---@param color NVGcolor
---@return nil
function nvgFillColor(ctx, color) end

--- Set current fill style to a paint.
---@param ctx NVGContextWrapper
---@param paint NVGpaint
---@return nil
function nvgFillPaint(ctx, paint) end

--- Set the miter limit of the stroke style.
---@param ctx NVGContextWrapper
---@param limit number
---@return nil
function nvgMiterLimit(ctx, limit) end

--- Set the stroke width of the stroke style.
---@param ctx NVGContextWrapper
---@param size number
---@return nil
function nvgStrokeWidth(ctx, size) end

--- Set how the end of the line (cap) is drawn.
---@param ctx NVGContextWrapper
---@param cap integer
---@return nil
function nvgLineCap(ctx, cap) end

--- Set how sharp path corners are drawn.
---@param ctx NVGContextWrapper
---@param join integer
---@return nil
function nvgLineJoin(ctx, join) end

--- Set the transparency applied to all rendered shapes.
---@param ctx NVGContextWrapper
---@param alpha number
---@return nil
function nvgGlobalAlpha(ctx, alpha) end

--- Reset current transform to identity matrix.
---@param ctx NVGContextWrapper
---@return nil
function nvgResetTransform(ctx) end

--- Premultiply current coordinate system by specified matrix.
---@param ctx NVGContextWrapper
---@param a number
---@param b number
---@param c number
---@param d number
---@param e number
---@param f number
---@return nil
function nvgTransform(ctx, a, b, c, d, e, f) end

--- Translate current coordinate system.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@return nil
function nvgTranslate(ctx, x, y) end

--- Rotate current coordinate system (angle in radians).
---@param ctx NVGContextWrapper
---@param angle number
---@return nil
function nvgRotate(ctx, angle) end

--- Skew the current coordinate system along X axis (angle in radians).
---@param ctx NVGContextWrapper
---@param angle number
---@return nil
function nvgSkewX(ctx, angle) end

--- Skew the current coordinate system along Y axis (angle in radians).
---@param ctx NVGContextWrapper
---@param angle number
---@return nil
function nvgSkewY(ctx, angle) end

--- Scale the current coordinate system.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@return nil
function nvgScale(ctx, x, y) end

--- Store the top part (a-f) of the current transformation matrix.
---@param ctx NVGContextWrapper
---@param xform table
---@return nil
function nvgCurrentTransform(ctx, xform) end

--- Set the transform to identity matrix.
---@param dst table
---@return nil
function nvgTransformIdentity(dst) end

--- Set the transform to translation matrix.
---@param dst table
---@param tx number
---@param ty number
---@return nil
function nvgTransformTranslate(dst, tx, ty) end

--- Set the transform to scale matrix.
---@param dst table
---@param sx number
---@param sy number
---@return nil
function nvgTransformScale(dst, sx, sy) end

--- Set the transform to rotate matrix (angle in radians).
---@param dst table
---@param a number
---@return nil
function nvgTransformRotate(dst, a) end

--- Set the transform to skew-x matrix (angle in radians).
---@param dst table
---@param a number
---@return nil
function nvgTransformSkewX(dst, a) end

--- Set the transform to skew-y matrix (angle in radians).
---@param dst table
---@param a number
---@return nil
function nvgTransformSkewY(dst, a) end

--- Convert degrees to radians.
---@param deg number
---@return number
function nvgDegToRad(deg) end

--- Convert radians to degrees.
---@param rad number
---@return number
function nvgRadToDeg(rad) end

--- Creates image by loading it from disk.
--- Supports all formats including GPU compressed textures (DDS, KTX, PVR, ETC, ASTC).
---@param ctx NVGContextWrapper NanoVG context
---@param path string File path to the image
---@param imageFlags? integer Image flags (combination of NVGimageFlags: NVG_IMAGE_GENERATE_MIPMAPS, NVG_IMAGE_REPEATX, NVG_IMAGE_REPEATY, NVG_IMAGE_FLIPY, NVG_IMAGE_PREMULTIPLIED, NVG_IMAGE_NEAREST)
---@return integer # Image handle, or -1 on failure
function nvgCreateImage(ctx, path, imageFlags) end

--- Returns the dimensions of a created image.
---@param ctx NVGContextWrapper NanoVG context
---@param image integer Image handle
---@return integer # w
---@return integer # h
function nvgImageSize(ctx, image) end

--- Deletes created image.
---@param ctx NVGContextWrapper
---@param image integer
---@return nil
function nvgDeleteImage(ctx, image) end

--- Creates image from a Texture2D for video playback or render-target sampling.
--- Render targets are normalized to NanoVG image orientation internally.
---@param ctx NVGContextWrapper NanoVG context
---@param texture Texture2D Texture2D pointer to wrap as a NanoVG image
---@return integer # Image handle, or 0 on failure/unsupported platform
function nvgCreateVideo(ctx, texture) end

--- Delete a video image created by nvgCreateVideo.
---@param ctx NVGContextWrapper NanoVG context
---@param image integer Image handle to delete
---@return nil
function nvgDeleteVideo(ctx, image) end

--- Create and return a linear gradient.
---@param ctx NVGContextWrapper
---@param sx number
---@param sy number
---@param ex number
---@param ey number
---@param icol NVGcolor
---@param ocol NVGcolor
---@return NVGpaint
function nvgLinearGradient(ctx, sx, sy, ex, ey, icol, ocol) end

--- Create and return a box gradient.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@param r number
---@param f number
---@param icol NVGcolor
---@param ocol NVGcolor
---@return NVGpaint
function nvgBoxGradient(ctx, x, y, w, h, r, f, icol, ocol) end

--- Create and return a box gradient with Gaussian (erf) falloff, matching CSS box-shadow / outer glow.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@param r number
---@param f number
---@param icol NVGcolor
---@param ocol NVGcolor
---@return NVGpaint
function nvgBoxGradientGaussian(ctx, x, y, w, h, r, f, icol, ocol) end

--- Create and return a radial gradient.
---@param ctx NVGContextWrapper
---@param cx number
---@param cy number
---@param inr number
---@param outr number
---@param icol NVGcolor
---@param ocol NVGcolor
---@return NVGpaint
function nvgRadialGradient(ctx, cx, cy, inr, outr, icol, ocol) end

--- Create and return an image pattern.
---@param ctx NVGContextWrapper
---@param ox number
---@param oy number
---@param ex number
---@param ey number
---@param angle number
---@param image integer
---@param alpha number
---@return NVGpaint
function nvgImagePattern(ctx, ox, oy, ex, ey, angle, image, alpha) end

--- Create and return a tinted image pattern. The color tints the image (multiplied in shader).
---@param ctx NVGContextWrapper
---@param ox number
---@param oy number
---@param ex number
---@param ey number
---@param angle number
---@param image integer
---@param color NVGcolor
---@return NVGpaint
function nvgImagePatternTinted(ctx, ox, oy, ex, ey, angle, image, color) end

--- Set the current scissor rectangle.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@return nil
function nvgScissor(ctx, x, y, w, h) end

--- Intersect current scissor rectangle with the specified rectangle.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@return nil
function nvgIntersectScissor(ctx, x, y, w, h) end

--- Reset and disable scissoring.
---@param ctx NVGContextWrapper
---@return nil
function nvgResetScissor(ctx) end

--- Clear the current path and sub-paths.
---@param ctx NVGContextWrapper
---@return nil
function nvgBeginPath(ctx) end

--- Start new sub-path with specified point as first point.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@return nil
function nvgMoveTo(ctx, x, y) end

--- Add line segment from the last point in the path to the specified point.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@return nil
function nvgLineTo(ctx, x, y) end

--- Add cubic bezier segment from last point in the path.
---@param ctx NVGContextWrapper
---@param c1x number
---@param c1y number
---@param c2x number
---@param c2y number
---@param x number
---@param y number
---@return nil
function nvgBezierTo(ctx, c1x, c1y, c2x, c2y, x, y) end

--- Add quadratic bezier segment from last point in the path.
---@param ctx NVGContextWrapper
---@param cx number
---@param cy number
---@param x number
---@param y number
---@return nil
function nvgQuadTo(ctx, cx, cy, x, y) end

--- Add an arc segment at the corner defined by the last path point.
---@param ctx NVGContextWrapper
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param radius number
---@return nil
function nvgArcTo(ctx, x1, y1, x2, y2, radius) end

--- Close current sub-path with a line segment.
---@param ctx NVGContextWrapper
---@return nil
function nvgClosePath(ctx) end

--- Set the current sub-path winding.
---@param ctx NVGContextWrapper
---@param dir integer
---@return nil
function nvgPathWinding(ctx, dir) end

--- Create new circle arc shaped sub-path.
---@param ctx NVGContextWrapper
---@param cx number
---@param cy number
---@param r number
---@param a0 number
---@param a1 number
---@param dir integer
---@return nil
function nvgArc(ctx, cx, cy, r, a0, a1, dir) end

--- Create new ellipse arc shaped sub-path.
---@param ctx NVGContextWrapper
---@param cx number
---@param cy number
---@param rx number
---@param ry number
---@param rotation number
---@param a0 number
---@param a1 number
---@param dir integer
---@return nil
function nvgEllipseArc(ctx, cx, cy, rx, ry, rotation, a0, a1, dir) end

--- Create new rectangle shaped sub-path.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@return nil
function nvgRect(ctx, x, y, w, h) end

--- Create new rounded rectangle shaped sub-path.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@param r number
---@return nil
function nvgRoundedRect(ctx, x, y, w, h, r) end

--- Create new rounded rectangle shaped sub-path with varying radii for each corner.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@param radTopLeft number
---@param radTopRight number
---@param radBottomRight number
---@param radBottomLeft number
---@return nil
function nvgRoundedRectVarying(ctx, x, y, w, h, radTopLeft, radTopRight, radBottomRight, radBottomLeft) end

--- Create new ellipse shaped sub-path.
---@param ctx NVGContextWrapper
---@param cx number
---@param cy number
---@param rx number
---@param ry number
---@return nil
function nvgEllipse(ctx, cx, cy, rx, ry) end

--- Create new circle shaped sub-path.
---@param ctx NVGContextWrapper
---@param cx number
---@param cy number
---@param r number
---@return nil
function nvgCircle(ctx, cx, cy, r) end

--- Fill the current path with current fill style.
---@param ctx NVGContextWrapper
---@return nil
function nvgFill(ctx) end

--- Stroke the current path with current stroke style.
---@param ctx NVGContextWrapper
---@return nil
function nvgStroke(ctx) end

--- Create font by loading it from the disk. Returns handle to the font.
---@param ctx NVGContextWrapper
---@param name string
---@param filename string
---@return integer
function nvgCreateFont(ctx, name, filename) end

--- Delete a loaded font by handle. Returns 1 when deleted, or 0 for an invalid handle.
---@param ctx NVGContextWrapper
---@param font integer
---@return integer
function nvgDeleteFont(ctx, font) end

--- Find a loaded font of specified name. Returns handle to it, or -1 if not found.
---@param ctx NVGContextWrapper
---@param name string
---@return integer
function nvgFindFont(ctx, name) end

--- Add a fallback font by handle.
---@param ctx NVGContextWrapper
---@param baseFont integer
---@param fallbackFont integer
---@return integer
function nvgAddFallbackFontId(ctx, baseFont, fallbackFont) end

--- Add a fallback font by name.
---@param ctx NVGContextWrapper
---@param baseFont string
---@param fallbackFont string
---@return integer
function nvgAddFallbackFont(ctx, baseFont, fallbackFont) end

--- Set the font size of current text style.
---@param ctx NVGContextWrapper
---@param size number
---@return nil
function nvgFontSize(ctx, size) end

--- Get the font size of current text style.
---@param ctx NVGContextWrapper
---@return number
function nvgGetFontSize(ctx) end

--- Set the blur of current text style.
---@param ctx NVGContextWrapper
---@param blur number
---@return nil
function nvgFontBlur(ctx, blur) end

--- Set the letter spacing of current text style.
---@param ctx NVGContextWrapper
---@param spacing number
---@return nil
function nvgTextLetterSpacing(ctx, spacing) end

--- Set the proportional line height of current text style.
---@param ctx NVGContextWrapper
---@param lineHeight number
---@return nil
function nvgTextLineHeight(ctx, lineHeight) end

--- Set the text align of current text style.
---@param ctx NVGContextWrapper
---@param align integer
---@return nil
function nvgTextAlign(ctx, align) end

--- Set the font face based on specified id of current text style.
---@param ctx NVGContextWrapper
---@param font integer
---@return nil
function nvgFontFaceId(ctx, font) end

--- Set the font face based on specified name of current text style.
---@param ctx NVGContextWrapper
---@param font string
---@return nil
function nvgFontFace(ctx, font) end

--- Set whether to use FreeType's auto-hinter (FT_LOAD_FORCE_AUTOHINT).
--- Default is disabled (0), which uses the font's built-in hints.
---@param ctx NVGContextWrapper
---@param enabled integer
---@return nil
function nvgForceAutoHint(ctx, enabled) end

--- Get whether FreeType's auto-hinter is enabled.
---@param ctx NVGContextWrapper
---@return integer
function nvgGetForceAutoHint(ctx) end

--- Set the font size method for FreeType.
--- NVG_SIZE_PIXEL (0): Use FT_Set_Pixel_Sizes (default).
--- NVG_SIZE_CHAR (1): Use FT_Set_Char_Size with 96 DPI.
---@param ctx NVGContextWrapper
---@param method integer
---@return nil
function nvgFontSizeMethod(ctx, method) end

--- Get the current font size method.
---@param ctx NVGContextWrapper
---@return integer
function nvgGetFontSizeMethod(ctx) end

--- Set the text scale mode. Controls how font size is computed when a widget has a transform.
--- NVG_TEXT_SCALE_FULL (0, default): fontSize includes xform scale - sharp but may jitter during animations.
--- NVG_TEXT_SCALE_DPR_ONLY (1): fontSize uses only DPR - smooth animations, slightly blurry when scaled.
--- This state is saved/restored with nvgSave/nvgRestore.
---@param ctx NVGContextWrapper
---@param mode integer
---@return nil
function nvgTextScaleMode(ctx, mode) end

--- Draw text string at specified location. Returns horizontal advance.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param string string
---@param end_? string
---@return number
function nvgText(ctx, x, y, string, end_) end

--- Draw multi-line text string at specified location wrapped at the specified width.
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param breakRowWidth number
---@param string string
---@param end_? string
---@return nil
function nvgTextBox(ctx, x, y, breakRowWidth, string, end_) end

--- Measure text string. If bounds table is passed, it is reused (no allocation).
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param string string
---@param bounds? number[] Optional reusable bounds table
---@return number advance
---@return number[]? bounds {xmin, ymin, xmax, ymax}
---@overload fun(ctx: NVGContextWrapper, x: number, y: number, string: string, endStr?: nil, bounds?: number[]): number, number[]?
function nvgTextBounds(ctx, x, y, string, bounds) end

--- Measure multi-line text string. If bounds table is passed, it is reused (no allocation).
---@param ctx NVGContextWrapper
---@param x number
---@param y number
---@param breakRowWidth number
---@param string string
---@param bounds? number[] Optional reusable bounds table
---@return number[] bounds {xmin, ymin, xmax, ymax}
---@overload fun(ctx: NVGContextWrapper, x: number, y: number, breakRowWidth: number, string: string, endStr: nil, bounds: number[]): number[]
function nvgTextBoxBounds(ctx, x, y, breakRowWidth, string, bounds) end

--- Returns the vertical metrics based on the current text style.
---@param ctx NVGContextWrapper
---@return number ascender
---@return number descender
---@return number lineHeight
function nvgTextMetrics(ctx) end
