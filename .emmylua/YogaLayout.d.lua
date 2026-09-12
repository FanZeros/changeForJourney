---@meta

--- Auto-generated from UI/YogaLayout

-- Global functions
--- Get the default Yoga configuration.
---@return YGConfigRef
function YGConfigGetDefault() end

--- Set the point scale factor for layout rounding.
--- This controls the density of the grid used for layout rounding.
--- Set to scale factor (e.g. 2.0 for 2x displays) to ensure pixel-perfect alignment.
---@param config YGConfigRef
---@param pixelsInPoint number
---@return nil
function YGConfigSetPointScaleFactor(config, pixelsInPoint) end

--- Get the current point scale factor.
---@param config YGConfigRef
---@return number
function YGConfigGetPointScaleFactor(config) end

--- Create a new Yoga layout node.
---@return YGNodeRef
function YGNodeNew() end

--- Free a Yoga node and all its children recursively.
---@param node YGNodeRef
---@return nil
function YGNodeFreeRecursive(node) end

--- Free a single Yoga node (does not free children).
---@param node YGNodeRef
---@return nil
function YGNodeFree(node) end

--- Reset node to default state.
---@param node YGNodeRef
---@return nil
function YGNodeReset(node) end

--- Insert a child node at the given index.
---@param node YGNodeRef
---@param child YGNodeRef
---@param index integer
---@return nil
function YGNodeInsertChild(node, child, index) end

--- Remove a child node.
---@param node YGNodeRef
---@param child YGNodeRef
---@return nil
function YGNodeRemoveChild(node, child) end

--- Remove all children from a node.
---@param node YGNodeRef
---@return nil
function YGNodeRemoveAllChildren(node) end

--- Get child node at index.
---@param node YGNodeRef
---@param index integer
---@return YGNodeRef
function YGNodeGetChild(node, index) end

--- Get the number of children.
---@param node YGNodeRef
---@return integer
function YGNodeGetChildCount(node) end

--- Get the parent of a node.
---@param node YGNodeRef
---@return YGNodeRef
function YGNodeGetParent(node) end

--- Calculate layout for the tree rooted at node.
---@param node YGNodeRef
---@param availableWidth number
---@param availableHeight number
---@param direction? integer
---@return nil
function YGNodeCalculateLayout(node, availableWidth, availableHeight, direction) end

--- Mark the node as dirty (needs recalculation).
---@param node YGNodeRef
---@return nil
function YGNodeMarkDirty(node) end

--- Check if node is dirty.
---@param node YGNodeRef
---@return boolean
function YGNodeIsDirty(node) end

--- Get computed left position.
---@param node YGNodeRef
---@return number
function YGNodeLayoutGetLeft(node) end

--- Get computed top position.
---@param node YGNodeRef
---@return number
function YGNodeLayoutGetTop(node) end

--- Get computed right position.
---@param node YGNodeRef
---@return number
function YGNodeLayoutGetRight(node) end

--- Get computed bottom position.
---@param node YGNodeRef
---@return number
function YGNodeLayoutGetBottom(node) end

--- Get computed width.
---@param node YGNodeRef
---@return number
function YGNodeLayoutGetWidth(node) end

--- Get computed height.
---@param node YGNodeRef
---@return number
function YGNodeLayoutGetHeight(node) end

--- Get computed margin for an edge.
---@param node YGNodeRef
---@param edge integer
---@return number
function YGNodeLayoutGetMargin(node, edge) end

--- Get computed padding for an edge.
---@param node YGNodeRef
---@param edge integer
---@return number
function YGNodeLayoutGetPadding(node, edge) end

--- Get computed border for an edge.
---@param node YGNodeRef
---@param edge integer
---@return number
function YGNodeLayoutGetBorder(node, edge) end

--- Set the direction.
---@param node YGNodeRef
---@param direction integer
---@return nil
function YGNodeStyleSetDirection(node, direction) end

--- Set the flex direction.
---@param node YGNodeRef
---@param flexDirection integer
---@return nil
function YGNodeStyleSetFlexDirection(node, flexDirection) end

--- Set justify content.
---@param node YGNodeRef
---@param justifyContent integer
---@return nil
function YGNodeStyleSetJustifyContent(node, justifyContent) end

--- Set align content.
---@param node YGNodeRef
---@param alignContent integer
---@return nil
function YGNodeStyleSetAlignContent(node, alignContent) end

--- Set align items.
---@param node YGNodeRef
---@param alignItems integer
---@return nil
function YGNodeStyleSetAlignItems(node, alignItems) end

--- Set align self.
---@param node YGNodeRef
---@param alignSelf integer
---@return nil
function YGNodeStyleSetAlignSelf(node, alignSelf) end

--- Set position type.
---@param node YGNodeRef
---@param positionType integer
---@return nil
function YGNodeStyleSetPositionType(node, positionType) end

--- Set flex wrap.
---@param node YGNodeRef
---@param flexWrap integer
---@return nil
function YGNodeStyleSetFlexWrap(node, flexWrap) end

--- Set overflow.
---@param node YGNodeRef
---@param overflow integer
---@return nil
function YGNodeStyleSetOverflow(node, overflow) end

--- Set display.
---@param node YGNodeRef
---@param display integer
---@return nil
function YGNodeStyleSetDisplay(node, display) end

--- Set flex value.
---@param node YGNodeRef
---@param flex number
---@return nil
function YGNodeStyleSetFlex(node, flex) end

--- Set flex grow.
---@param node YGNodeRef
---@param flexGrow number
---@return nil
function YGNodeStyleSetFlexGrow(node, flexGrow) end

--- Set flex shrink.
---@param node YGNodeRef
---@param flexShrink number
---@return nil
function YGNodeStyleSetFlexShrink(node, flexShrink) end

--- Set flex basis (point value).
---@param node YGNodeRef
---@param flexBasis number
---@return nil
function YGNodeStyleSetFlexBasis(node, flexBasis) end

--- Set flex basis (percent value).
---@param node YGNodeRef
---@param flexBasis number
---@return nil
function YGNodeStyleSetFlexBasisPercent(node, flexBasis) end

--- Set flex basis to auto.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetFlexBasisAuto(node) end

--- Set flex basis to max-content.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetFlexBasisMaxContent(node) end

--- Set flex basis to fit-content.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetFlexBasisFitContent(node) end

--- Set flex basis to stretch.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetFlexBasisStretch(node) end

--- Set position (point value).
---@param node YGNodeRef
---@param edge integer
---@param position number
---@return nil
function YGNodeStyleSetPosition(node, edge, position) end

--- Set position (percent value).
---@param node YGNodeRef
---@param edge integer
---@param position number
---@return nil
function YGNodeStyleSetPositionPercent(node, edge, position) end

--- Set margin (point value).
---@param node YGNodeRef
---@param edge integer
---@param margin number
---@return nil
function YGNodeStyleSetMargin(node, edge, margin) end

--- Set margin (percent value).
---@param node YGNodeRef
---@param edge integer
---@param margin number
---@return nil
function YGNodeStyleSetMarginPercent(node, edge, margin) end

--- Set margin to auto.
---@param node YGNodeRef
---@param edge integer
---@return nil
function YGNodeStyleSetMarginAuto(node, edge) end

--- Set padding (point value).
---@param node YGNodeRef
---@param edge integer
---@param padding number
---@return nil
function YGNodeStyleSetPadding(node, edge, padding) end

--- Set padding (percent value).
---@param node YGNodeRef
---@param edge integer
---@param padding number
---@return nil
function YGNodeStyleSetPaddingPercent(node, edge, padding) end

--- Set border width.
---@param node YGNodeRef
---@param edge integer
---@param border number
---@return nil
function YGNodeStyleSetBorder(node, edge, border) end

--- Set width (point value).
---@param node YGNodeRef
---@param width number
---@return nil
function YGNodeStyleSetWidth(node, width) end

--- Set width (percent value).
---@param node YGNodeRef
---@param width number
---@return nil
function YGNodeStyleSetWidthPercent(node, width) end

--- Set width to auto.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetWidthAuto(node) end

--- Set height (point value).
---@param node YGNodeRef
---@param height number
---@return nil
function YGNodeStyleSetHeight(node, height) end

--- Set height (percent value).
---@param node YGNodeRef
---@param height number
---@return nil
function YGNodeStyleSetHeightPercent(node, height) end

--- Set height to auto.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetHeightAuto(node) end

--- Set min width.
---@param node YGNodeRef
---@param minWidth number
---@return nil
function YGNodeStyleSetMinWidth(node, minWidth) end

--- Set min width (percent).
---@param node YGNodeRef
---@param minWidth number
---@return nil
function YGNodeStyleSetMinWidthPercent(node, minWidth) end

--- Set min width to max-content.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMinWidthMaxContent(node) end

--- Set min width to fit-content.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMinWidthFitContent(node) end

--- Set min width to stretch.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMinWidthStretch(node) end

--- Set min height.
---@param node YGNodeRef
---@param minHeight number
---@return nil
function YGNodeStyleSetMinHeight(node, minHeight) end

--- Set min height (percent).
---@param node YGNodeRef
---@param minHeight number
---@return nil
function YGNodeStyleSetMinHeightPercent(node, minHeight) end

--- Set min height to max-content.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMinHeightMaxContent(node) end

--- Set min height to fit-content.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMinHeightFitContent(node) end

--- Set min height to stretch.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMinHeightStretch(node) end

--- Set max width.
---@param node YGNodeRef
---@param maxWidth number
---@return nil
function YGNodeStyleSetMaxWidth(node, maxWidth) end

--- Set max width (percent).
---@param node YGNodeRef
---@param maxWidth number
---@return nil
function YGNodeStyleSetMaxWidthPercent(node, maxWidth) end

--- Set max width to max-content.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMaxWidthMaxContent(node) end

--- Set max width to fit-content.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMaxWidthFitContent(node) end

--- Set max width to stretch.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMaxWidthStretch(node) end

--- Set max height.
---@param node YGNodeRef
---@param maxHeight number
---@return nil
function YGNodeStyleSetMaxHeight(node, maxHeight) end

--- Set max height (percent).
---@param node YGNodeRef
---@param maxHeight number
---@return nil
function YGNodeStyleSetMaxHeightPercent(node, maxHeight) end

--- Set max height to max-content.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMaxHeightMaxContent(node) end

--- Set max height to fit-content.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMaxHeightFitContent(node) end

--- Set max height to stretch.
---@param node YGNodeRef
---@return nil
function YGNodeStyleSetMaxHeightStretch(node) end

--- Set aspect ratio.
---@param node YGNodeRef
---@param aspectRatio number
---@return nil
function YGNodeStyleSetAspectRatio(node, aspectRatio) end

--- Set gap (point value).
---@param node YGNodeRef
---@param gutter integer
---@param gapLength number
---@return nil
function YGNodeStyleSetGap(node, gutter, gapLength) end

--- Set gap (percent value).
---@param node YGNodeRef
---@param gutter integer
---@param gapLength number
---@return nil
function YGNodeStyleSetGapPercent(node, gutter, gapLength) end

--- Get flex direction.
---@param node YGNodeRef
---@return integer
function YGNodeStyleGetFlexDirection(node) end

--- Get justify content.
---@param node YGNodeRef
---@return integer
function YGNodeStyleGetJustifyContent(node) end

--- Get align items.
---@param node YGNodeRef
---@return integer
function YGNodeStyleGetAlignItems(node) end

--- Get align self.
---@param node YGNodeRef
---@return integer
function YGNodeStyleGetAlignSelf(node) end

--- Get position type.
---@param node YGNodeRef
---@return integer
function YGNodeStyleGetPositionType(node) end

--- Get flex wrap.
---@param node YGNodeRef
---@return integer
function YGNodeStyleGetFlexWrap(node) end

--- Get flex grow.
---@param node YGNodeRef
---@return number
function YGNodeStyleGetFlexGrow(node) end

--- Get flex shrink.
---@param node YGNodeRef
---@return number
function YGNodeStyleGetFlexShrink(node) end

--- Get flex basis (returns table {value, unit}).
---@param node YGNodeRef
---@return {value: number, unit: integer}
function YGNodeStyleGetFlexBasis(node) end

--- Get width (returns table {value, unit}).
---@param node YGNodeRef
---@return {value: number, unit: integer}
function YGNodeStyleGetWidth(node) end

--- Get height (returns table {value, unit}).
---@param node YGNodeRef
---@return {value: number, unit: integer}
function YGNodeStyleGetHeight(node) end

--- Get min width (returns table {value, unit}).
---@param node YGNodeRef
---@return {value: number, unit: integer}
function YGNodeStyleGetMinWidth(node) end

--- Get min height (returns table {value, unit}).
---@param node YGNodeRef
---@return {value: number, unit: integer}
function YGNodeStyleGetMinHeight(node) end

--- Get max width (returns table {value, unit}).
---@param node YGNodeRef
---@return {value: number, unit: integer}
function YGNodeStyleGetMaxWidth(node) end

--- Get max height (returns table {value, unit}).
---@param node YGNodeRef
---@return {value: number, unit: integer}
function YGNodeStyleGetMaxHeight(node) end

--- Get position (returns table {value, unit}).
---@param node YGNodeRef
---@param edge integer
---@return {value: number, unit: integer}
function YGNodeStyleGetPosition(node, edge) end

--- Get margin (returns table {value, unit}).
---@param node YGNodeRef
---@param edge integer
---@return {value: number, unit: integer}
function YGNodeStyleGetMargin(node, edge) end

--- Get padding (returns table {value, unit}).
---@param node YGNodeRef
---@param edge integer
---@return {value: number, unit: integer}
function YGNodeStyleGetPadding(node, edge) end

--- Get gap (returns table {value, unit}).
---@param node YGNodeRef
---@param gutter integer
---@return {value: number, unit: integer}
function YGNodeStyleGetGap(node, gutter) end

--- Get the number of live YGNode instances (for debugging).
---@return integer
function YGNodeGetLiveCount() end

--- Get the YGUndefined value (NaN).
--- Used to specify unconstrained dimensions in YGNodeCalculateLayout.
---@return number
function YGGetUndefined() end

--- Set a fixed baseline value for a node.
--- Enables alignItems="baseline" alignment by telling Yoga the text baseline offset.
---@param node YGNodeRef The Yoga node
---@param baseline number The baseline offset from the top of the node (paddingTop + ascender)
---@return nil
function YGNodeSetBaselineValue(node, baseline) end

--- Clear the baseline value for a node (disables baseline alignment).
---@param node YGNodeRef The Yoga node
---@return nil
function YGNodeClearBaselineValue(node) end
