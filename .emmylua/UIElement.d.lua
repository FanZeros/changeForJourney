---@meta

--- Auto-generated from UI/UIElement

---@alias HorizontalAlignment
---| integer # HorizontalAlignment enum values

---@type HorizontalAlignment
HA_LEFT = 0
---@type HorizontalAlignment
HA_CENTER = 1
---@type HorizontalAlignment
HA_RIGHT = 2
---@type HorizontalAlignment
HA_CUSTOM = 3

---@alias VerticalAlignment
---| integer # VerticalAlignment enum values

---@type VerticalAlignment
VA_TOP = 0
---@type VerticalAlignment
VA_CENTER = 1
---@type VerticalAlignment
VA_BOTTOM = 2
---@type VerticalAlignment
VA_CUSTOM = 3

---@alias Corner
---| integer # Corner enum values

---@type Corner
C_TOPLEFT = 0
---@type Corner
C_TOPRIGHT = 1
---@type Corner
C_BOTTOMLEFT = 2
---@type Corner
C_BOTTOMRIGHT = 3
---@type Corner
MAX_UIELEMENT_CORNERS = 4

---@alias Orientation
---| integer # Orientation enum values

---@type Orientation
O_HORIZONTAL = 0
---@type Orientation
O_VERTICAL = 1

---@alias FocusMode
---| integer # FocusMode enum values

---@type FocusMode
FM_NOTFOCUSABLE = 0
---@type FocusMode
FM_RESETFOCUS = 1
---@type FocusMode
FM_FOCUSABLE = 2
---@type FocusMode
FM_FOCUSABLE_DEFOCUSABLE = 3

---@alias LayoutMode
---| integer # LayoutMode enum values

---@type LayoutMode
LM_FREE = 0
---@type LayoutMode
LM_HORIZONTAL = 1
---@type LayoutMode
LM_VERTICAL = 2

---@alias TraversalMode
---| integer # TraversalMode enum values

---@type TraversalMode
TM_BREADTH_FIRST = 0
---@type TraversalMode
TM_DEPTH_FIRST = 1

---@class UIElement : Animatable
---@overload fun(): UIElement
---@field screenPosition IntVector2
---@field name string
---@field position IntVector2
---@field size IntVector2
---@field width integer
---@field height integer
---@field minSize IntVector2
---@field minWidth integer
---@field minHeight integer
---@field maxSize IntVector2
---@field maxWidth integer
---@field maxHeight integer
---@field fixedSize boolean
---@field fixedWidth boolean
---@field fixedHeight boolean
---@field childOffset IntVector2
---@field horizontalAlignment HorizontalAlignment
---@field verticalAlignment VerticalAlignment
---@field enableAnchor boolean
---@field minOffset IntVector2
---@field maxOffset IntVector2
---@field minAnchor Vector2
---@field maxAnchor Vector2
---@field pivot Vector2
---@field scale Vector2
---@field rotate number
---@field clipBorder IntRect
---@field color Color
---@field priority integer
---@field opacity number
---@field derivedOpacity number
---@field bringToFront boolean
---@field bringToBack boolean
---@field clipChildren boolean
---@field sortChildren boolean
---@field useDerivedOpacity boolean
---@field focus boolean
---@field enabled boolean
---@field enabledSelf boolean
---@field editable boolean
---@field selected boolean
---@field visible boolean
---@field visibleEffective boolean
---@field hovering boolean
---@field internal boolean
---@field colorGradient boolean
---@field focusMode FocusMode
---@field dragDropMode integer
---@field style string
---@field defaultStyle XMLFile
---@field layoutMode LayoutMode
---@field layoutSpacing integer
---@field layoutBorder IntRect
---@field layoutFlexScale Vector2
---@field numChildren integer
---@field parent UIElement
---@field root UIElement
---@field derivedColor Color
---@field combinedScreenRect IntRect
---@field indent integer
---@field indentSpacing integer
---@field indentWidth integer
---@field traversalMode TraversalMode
---@field elementEventSender boolean
---@field CreateChild __union_func__type_str__name_str_opt__index_int_opt__ret_UIElementT
UIElement = {}

---@return UIElement
function UIElement.new() end

---@return IntVector2
function UIElement:GetScreenPosition() end

---@param source Deserializer
---@return boolean
function UIElement:LoadXML(source) end

---@param fileName string
---@return boolean
function UIElement:LoadXML(fileName) end

---@param dest Serializer
---@param indentation? string
---@return boolean
function UIElement:SaveXML(dest, indentation) end

---@param fileName string
---@param indentation? string
---@return boolean
function UIElement:SaveXML(fileName, indentation) end

---@param dest XMLElement
---@return boolean
function UIElement:FilterAttributes(dest) end

---@param name string
---@return nil
function UIElement:SetName(name) end

---@param position IntVector2
---@return nil
function UIElement:SetPosition(position) end

---@param x integer
---@param y integer
---@return nil
function UIElement:SetPosition(x, y) end

---@param size IntVector2
---@return nil
function UIElement:SetSize(size) end

---@param width integer
---@param height integer
---@return nil
function UIElement:SetSize(width, height) end

---@param width integer
---@return nil
function UIElement:SetWidth(width) end

---@param height integer
---@return nil
function UIElement:SetHeight(height) end

---@param minSize IntVector2
---@return nil
function UIElement:SetMinSize(minSize) end

---@param width integer
---@param height integer
---@return nil
function UIElement:SetMinSize(width, height) end

---@param width integer
---@return nil
function UIElement:SetMinWidth(width) end

---@param height integer
---@return nil
function UIElement:SetMinHeight(height) end

---@param maxSize IntVector2
---@return nil
function UIElement:SetMaxSize(maxSize) end

---@param width integer
---@param height integer
---@return nil
function UIElement:SetMaxSize(width, height) end

---@param width integer
---@return nil
function UIElement:SetMaxWidth(width) end

---@param height integer
---@return nil
function UIElement:SetMaxHeight(height) end

---@param size IntVector2
---@return nil
function UIElement:SetFixedSize(size) end

---@param width integer
---@param height integer
---@return nil
function UIElement:SetFixedSize(width, height) end

---@param width integer
---@return nil
function UIElement:SetFixedWidth(width) end

---@param height integer
---@return nil
function UIElement:SetFixedHeight(height) end

---@param hAlign HorizontalAlignment
---@param vAlign VerticalAlignment
---@return nil
function UIElement:SetAlignment(hAlign, vAlign) end

---@param align HorizontalAlignment
---@return nil
function UIElement:SetHorizontalAlignment(align) end

---@param align VerticalAlignment
---@return nil
function UIElement:SetVerticalAlignment(align) end

---@param enable boolean
---@return nil
function UIElement:SetEnableAnchor(enable) end

---@param anchor Vector2
---@return nil
function UIElement:SetMinAnchor(anchor) end

---@param x number
---@param y number
---@return nil
function UIElement:SetMinAnchor(x, y) end

---@param anchor Vector2
---@return nil
function UIElement:SetMaxAnchor(anchor) end

---@param x number
---@param y number
---@return nil
function UIElement:SetMaxAnchor(x, y) end

---@param offset IntVector2
---@return nil
function UIElement:SetMinOffset(offset) end

---@param offset IntVector2
---@return nil
function UIElement:SetMaxOffset(offset) end

---@param pivot Vector2
---@return nil
function UIElement:SetPivot(pivot) end

---@param x number
---@param y number
---@return nil
function UIElement:SetPivot(x, y) end

---@param scale Vector2
---@return nil
function UIElement:SetScale(scale) end

---@param x number
---@param y number
---@return nil
function UIElement:SetScale(x, y) end

---@return Vector2
function UIElement:GetScale() end

---@param angle number
---@return nil
function UIElement:SetRotate(angle) end

---@return number
function UIElement:GetRotate() end

---@param rect IntRect
---@return nil
function UIElement:SetClipBorder(rect) end

---@param color Color
---@return nil
function UIElement:SetColor(color) end

---@param corner Corner
---@param color Color
---@return nil
function UIElement:SetColor(corner, color) end

---@param priority integer
---@return nil
function UIElement:SetPriority(priority) end

---@param opacity number
---@return nil
function UIElement:SetOpacity(opacity) end

---@param enable boolean
---@return nil
function UIElement:SetBringToFront(enable) end

---@param enable boolean
---@return nil
function UIElement:SetBringToBack(enable) end

---@param enable boolean
---@return nil
function UIElement:SetClipChildren(enable) end

---@param enable boolean
---@return nil
function UIElement:SetSortChildren(enable) end

---@param enable boolean
---@return nil
function UIElement:SetUseDerivedOpacity(enable) end

---@param enable boolean
---@return nil
function UIElement:SetEnabled(enable) end

---@param enable boolean
---@return nil
function UIElement:SetDeepEnabled(enable) end

---@return nil
function UIElement:ResetDeepEnabled() end

---@param enable boolean
---@return nil
function UIElement:SetEnabledRecursive(enable) end

---@param enable boolean
---@return nil
function UIElement:SetEditable(enable) end

---@param enable boolean
---@return nil
function UIElement:SetFocus(enable) end

---@param enable boolean
---@return nil
function UIElement:SetSelected(enable) end

---@param enable boolean
---@return nil
function UIElement:SetVisible(enable) end

---@param mode FocusMode
---@return nil
function UIElement:SetFocusMode(mode) end

---@param mode DragAndDropMode
---@return nil
function UIElement:SetDragDropMode(mode) end

---@param styleName string
---@param file? XMLFile
---@return boolean
function UIElement:SetStyle(styleName, file) end

---@param element XMLElement
---@return boolean
function UIElement:SetStyle(element) end

---@param file? XMLFile
---@return boolean
function UIElement:SetStyleAuto(file) end

---@param style XMLFile
---@return nil
function UIElement:SetDefaultStyle(style) end

---@param mode LayoutMode
---@param spacing? integer
---@param border? IntRect
---@return nil
function UIElement:SetLayout(mode, spacing, border) end

---@param mode LayoutMode
---@return nil
function UIElement:SetLayoutMode(mode) end

---@param spacing integer
---@return nil
function UIElement:SetLayoutSpacing(spacing) end

---@param border IntRect
---@return nil
function UIElement:SetLayoutBorder(border) end

---@param scale Vector2
---@return nil
function UIElement:SetLayoutFlexScale(scale) end

---@param indent integer
---@return nil
function UIElement:SetIndent(indent) end

---@param indentSpacing integer
---@return nil
function UIElement:SetIndentSpacing(indentSpacing) end

---@return nil
function UIElement:UpdateLayout() end

---@return nil
function UIElement:DisableLayoutUpdate() end

---@return nil
function UIElement:EnableLayoutUpdate() end

---@return nil
function UIElement:BringToFront() end

---@param element UIElement
---@return nil
function UIElement:AddChild(element) end

---@param index integer
---@param element UIElement
---@return nil
function UIElement:InsertChild(index, element) end

---@param element UIElement
---@param index? integer
---@return nil
function UIElement:RemoveChild(element, index) end

---@param index integer
---@return nil
function UIElement:RemoveChildAtIndex(index) end

---@return nil
function UIElement:RemoveAllChildren() end

---@return nil
function UIElement:Remove() end

---@param element UIElement
---@return integer
function UIElement:FindChild(element) end

---@param parent UIElement
---@param index? integer
---@return nil
function UIElement:SetParent(parent, index) end

---@param key StringHash|string
---@param value Variant
---@return nil
function UIElement:SetVar(key, value) end

---@param key string
---@param value Variant
---@return nil
function UIElement:SetVar(key, value) end

---@param enable boolean
---@return nil
function UIElement:SetInternal(enable) end

---@param traversalMode TraversalMode
---@return nil
function UIElement:SetTraversalMode(traversalMode) end

---@param flag boolean
---@return nil
function UIElement:SetElementEventSender(flag) end

---@param tag string
---@return nil
function UIElement:AddTag(tag) end

---@param tags string
---@param separator string
---@return nil
function UIElement:AddTags(tags, separator) end

---@param tag string
---@return boolean
function UIElement:RemoveTag(tag) end

---@return nil
function UIElement:RemoveAllTags() end

---@return string
function UIElement:GetName() end

---@return IntVector2
function UIElement:GetPosition() end

---@return IntVector2
function UIElement:GetSize() end

---@return integer
function UIElement:GetWidth() end

---@return integer
function UIElement:GetHeight() end

---@return IntVector2
function UIElement:GetMinSize() end

---@return integer
function UIElement:GetMinWidth() end

---@return integer
function UIElement:GetMinHeight() end

---@return IntVector2
function UIElement:GetMaxSize() end

---@return integer
function UIElement:GetMaxWidth() end

---@return integer
function UIElement:GetMaxHeight() end

---@return boolean
function UIElement:IsFixedSize() end

---@return boolean
function UIElement:IsFixedWidth() end

---@return boolean
function UIElement:IsFixedHeight() end

---@return IntVector2
function UIElement:GetChildOffset() end

---@return HorizontalAlignment
function UIElement:GetHorizontalAlignment() end

---@return VerticalAlignment
function UIElement:GetVerticalAlignment() end

---@return boolean
function UIElement:GetEnableAnchor() end

---@return Vector2
function UIElement:GetMinAnchor() end

---@return Vector2
function UIElement:GetMaxAnchor() end

---@return IntVector2
function UIElement:GetMinOffset() end

---@return IntVector2
function UIElement:GetMaxOffset() end

---@return Vector2
function UIElement:GetPivot() end

---@return IntRect
function UIElement:GetClipBorder() end

---@param corner Corner
---@return Color
function UIElement:GetColor(corner) end

---@return Color
function UIElement:GetColor() end

---@return integer
function UIElement:GetPriority() end

---@return number
function UIElement:GetOpacity() end

---@return number
function UIElement:GetDerivedOpacity() end

---@return boolean
function UIElement:GetBringToFront() end

---@return boolean
function UIElement:GetBringToBack() end

---@return boolean
function UIElement:GetClipChildren() end

---@return boolean
function UIElement:GetSortChildren() end

---@return boolean
function UIElement:GetUseDerivedOpacity() end

---@return boolean
function UIElement:HasFocus() end

---@return boolean
function UIElement:IsEnabled() end

---@return boolean
function UIElement:IsEnabledSelf() end

---@return boolean
function UIElement:IsEditable() end

---@return boolean
function UIElement:IsSelected() end

---@return boolean
function UIElement:IsVisible() end

---@return boolean
function UIElement:IsVisibleEffective() end

---@return boolean
function UIElement:IsHovering() end

---@return boolean
function UIElement:IsInternal() end

---@return boolean
function UIElement:HasColorGradient() end

---@return FocusMode
function UIElement:GetFocusMode() end

---@return DragAndDropMode
function UIElement:GetDragDropMode() end

---@return string
function UIElement:GetAppliedStyle() end

---@param recursiveUp? boolean
---@return XMLFile
function UIElement:GetDefaultStyle(recursiveUp) end

---@return LayoutMode
function UIElement:GetLayoutMode() end

---@return integer
function UIElement:GetLayoutSpacing() end

---@return IntRect
function UIElement:GetLayoutBorder() end

---@return Vector2
function UIElement:GetLayoutFlexScale() end

---@param recursive? boolean
---@return integer
function UIElement:GetNumChildren(recursive) end

---@return integer
function UIElement:GetDragButtonCombo() end

---@return integer
function UIElement:GetDragButtonCount() end

---@param name string
---@param recursive? boolean
---@return UIElement
function UIElement:GetChild(name, recursive) end

---@param index integer
---@return UIElement
function UIElement:GetChild(index) end

---@param element UIElement
---@return boolean
function UIElement:IsChildOf(element) end

---@return UIElement
function UIElement:GetParent() end

---@return UIElement
function UIElement:GetRoot() end

---@return Color
function UIElement:GetDerivedColor() end

---@param key StringHash|string
---@return Variant
function UIElement:GetVar(key) end

---@param key string
---@return Variant
function UIElement:GetVar(key) end

---@return VariantMap
function UIElement:GetVars() end

---@param tag string
---@return boolean
function UIElement:HasTag(tag) end

---@return StringVector
function UIElement:GetTags() end

---@param tag string
---@param recursive? boolean
---@return UIElement[]
function UIElement:GetChildrenWithTag(tag, recursive) end

---@param screenPosition IntVector2
---@return IntVector2
function UIElement:ScreenToElement(screenPosition) end

---@param position IntVector2
---@return IntVector2
function UIElement:ElementToScreen(position) end

---@param position IntVector2
---@param isScreen boolean
---@return boolean
function UIElement:IsInside(position, isScreen) end

---@param position IntVector2
---@param isScreen boolean
---@return boolean
function UIElement:IsInsideCombined(position, isScreen) end

---@return IntRect
function UIElement:GetCombinedScreenRect() end

---@return nil
function UIElement:SortChildren() end

---@return integer
function UIElement:GetIndent() end

---@return integer
function UIElement:GetIndentSpacing() end

---@return integer
function UIElement:GetIndentWidth() end

---@param offset IntVector2
---@return nil
function UIElement:SetChildOffset(offset) end

---@param enable boolean
---@return nil
function UIElement:SetHovering(enable) end

---@return TraversalMode
function UIElement:GetTraversalMode() end

---@return boolean
function UIElement:IsElementEventSender() end

---@return UIElement
function UIElement:GetElementEventSender() end


-- Global variables
---@type integer
DD_DISABLED = nil
---@type integer
DD_SOURCE = nil
---@type integer
DD_TARGET = nil
---@type integer
DD_SOURCE_AND_TARGET = nil
