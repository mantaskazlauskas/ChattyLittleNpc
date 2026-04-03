# Widget API (Patch 12.0.1)

> Widgets are graphical elements created in Lua with CreateFrame() or via XML.
> Full reference: https://warcraft.wiki.gg/wiki/Widget_API

## Widget Hierarchy

```
FrameScriptObject
  └── Object
        └── ScriptObject
              └── ScriptRegion (+ ScriptRegionResizing, AnimatableObject)
                    ├── Region (textures, fontstrings)
                    │     ├── TextureBase → Texture, MaskTexture, Line
                    │     └── FontString
                    └── Frame
                          ├── Button → CheckButton, ItemButton
                          ├── EditBox
                          ├── ScrollFrame
                          ├── Slider
                          ├── StatusBar
                          ├── Cooldown
                          ├── ColorSelect
                          ├── GameTooltip
                          ├── MessageFrame
                          ├── ScrollingMessageFrame
                          ├── SimpleHTML
                          ├── Model → PlayerModel, CinematicModel, DressUpModel
                          ├── ModelScene
                          ├── MovieFrame
                          └── ...
```

## Creating Widgets

```lua
-- CreateFrame(frameType [, name, parent, template, id])
local frame = CreateFrame("Frame", "MyFrameName", UIParent)
local button = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
local editbox = CreateFrame("EditBox", nil, UIParent, "InputBoxTemplate")
```

**Important**: Frames cannot be garbage collected. Use CreateFramePool() for reuse.

## FrameScriptObject Methods

```lua
obj:GetName() : name
obj:GetObjectType() : objectType
obj:IsObjectType(objectType) : isType
obj:IsForbidden() : isForbidden
obj:SetForbidden()  -- #protected
```

## Object Methods

```lua
obj:GetParent() : parent
obj:GetParentKey() : parentKey
obj:SetParentKey(parentKey [, clearOtherKeys])
obj:GetDebugName([preferParentKey]) : debugName
```

## ScriptObject Methods

```lua
obj:GetScript(scriptTypeName [, bindingType]) : script
obj:HasScript(scriptName) : hasScript
obj:SetScript(scriptTypeName, script)
obj:HookScript(scriptTypeName, script [, bindingType])  -- Post-hook
```

## ScriptRegion Methods (Base for all visible widgets)

### Visibility
```lua
region:Show()  -- #secureframe
region:Hide()  -- #secureframe
region:SetShown([show])  -- #secureframe
region:IsShown() : isShown
region:IsVisible() : isVisible  -- True only if region AND parents are shown
```

### Mouse Input
```lua
region:EnableMouse([enable])  -- #secureframe
region:EnableMouseMotion([enable])  -- #secureframe
region:EnableMouseWheel([enable])  -- #secureframe
region:IsMouseEnabled() : enabled
region:IsMouseOver([offsetTop, offsetBottom, offsetLeft, offsetRight]) : isOver
region:SetPassThroughButtons([button1, ...])  -- #nocombat
```

### Size & Position
```lua
region:GetWidth([ignoreRect]) : width
region:GetHeight([ignoreRect]) : height
region:GetSize([ignoreRect]) : width, height
region:GetRect() : left, bottom, width, height  -- #restrictedframe
region:GetCenter() : x, y  -- #restrictedframe
region:GetLeft() / GetRight() / GetTop() / GetBottom()
region:GetScaledRect() : left, bottom, width, height
```

### Anchoring (ScriptRegionResizing)
```lua
region:SetPoint(point [, relativeTo [, relativePoint]] [, offsetX, offsetY])
region:SetAllPoints(relativeTo [, doResize])
region:ClearAllPoints()
region:ClearPoint(point)
region:SetSize(width, height)  -- #secureframe
region:SetWidth(width)  -- #secureframe
region:SetHeight(height)  -- #secureframe
region:GetNumPoints() : numPoints
region:GetPoint([anchorIndex]) : point, relativeTo, relativePoint, offsetX, offsetY
region:AdjustPointsOffset(x, y)  -- #secureframe
```

### Anchor Points
```
TOPLEFT      TOP       TOPRIGHT
LEFT         CENTER    RIGHT
BOTTOMLEFT   BOTTOM    BOTTOMRIGHT
```

### Other
```lua
region:SetParent([parent])  -- #secureframe
region:IsProtected() : isProtected, isProtectedExplicitly
region:IsDragging() : isDragging
region:IsRectValid() : isValid
region:GetSourceLocation() : location  -- Where created (file:line)
```

## Region Methods (Textures, FontStrings)

```lua
region:GetAlpha() : alpha
region:SetAlpha(alpha)
region:GetScale() : scale
region:SetScale(scale)  -- #secureframe
region:GetEffectiveScale() : effectiveScale
region:GetDrawLayer() : layer, sublayer
region:SetDrawLayer(layer [, sublevel])
region:GetVertexColor() : r, g, b, a
region:SetVertexColor(r, g, b [, a])
region:SetIgnoreParentAlpha(ignore)
region:SetIgnoreParentScale(ignore)  -- #secureframe
region:IsObjectLoaded() : isLoaded
```

## Frame Methods

### Core
```lua
frame:SetFrameStrata(strata)  -- "BACKGROUND","LOW","MEDIUM","HIGH","DIALOG","FULLSCREEN","FULLSCREEN_DIALOG","TOOLTIP"
frame:GetFrameStrata() : strata
frame:SetFrameLevel(level)
frame:GetFrameLevel() : level
frame:SetID(id)
frame:GetID() : id
frame:SetToplevel(isTopLevel)
```

### Events
```lua
frame:RegisterEvent(eventName) : registered
frame:RegisterUnitEvent(eventName, unit1 [, unit2]) : registered
frame:UnregisterEvent(eventName) : registered
frame:UnregisterAllEvents()
frame:IsEventRegistered(eventName) : isRegistered, unit1, unit2
```

### Input
```lua
frame:EnableKeyboard([enable])
frame:SetPropagateKeyboardInput(propagate)
frame:RegisterForDrag(button1 [, ...])
frame:SetMovable(movable)
frame:SetResizable(resizable)
frame:StartMoving()
frame:StopMovingOrSizing()
frame:SetClampedToScreen(clamped)
frame:SetClipsChildren(clip)
```

### Attributes (Secure Frames)
```lua
frame:SetAttribute(name, value)  -- Must be out of combat for protected frames
frame:GetAttribute(name) : value
```

### Regions
```lua
frame:CreateTexture([name, layer, inherits, sublevel]) : texture
frame:CreateFontString([name, layer, inherits]) : fontString
frame:CreateLine([name, layer, inherits, sublevel]) : line
frame:CreateMaskTexture([name, layer, inherits, sublevel]) : maskTexture
frame:GetChildren() : child1, child2, ...
frame:GetNumChildren() : numChildren
frame:GetRegions() : region1, region2, ...
frame:GetNumRegions() : numRegions
```

### Backdrop (Deprecated — use NineSlice templates instead)
```lua
frame:SetBackdrop(backdropInfo)  -- nil to remove
frame:GetBackdrop() : backdropInfo
frame:SetBackdropColor(r, g, b [, a])
frame:SetBackdropBorderColor(r, g, b [, a])
```

## Texture Methods

```lua
texture:SetTexture(fileID_or_path [, wrapModeH, wrapModeV, filterMode])
texture:SetAtlas(atlas [, useAtlasSize, filterMode, resetTexCoords])
texture:SetTexCoord(left, right, top, bottom)  -- or (ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
texture:GetTexture() : fileID
texture:SetColorTexture(r, g, b [, a])  -- Solid color
texture:SetGradient(orientation, minColor, maxColor)
texture:SetBlendMode(blendMode)  -- "DISABLE", "BLEND", "ALPHAKEY", "ADD", "MOD"
texture:SetDesaturated(desaturated)
texture:SetRotation(radians [, normalizedRotationPoint])
texture:SetAllPoints([relativeTo])
texture:SetSnapToPixelGrid(snap)
texture:SetTexelSnappingBias(bias)
```

## FontString Methods

```lua
fontString:SetText(text)
fontString:GetText() : text
fontString:SetFormattedText(formatString, ...)
fontString:SetTextColor(r, g, b [, a])
fontString:SetFont(fontFile, height [, flags])  -- flags: "OUTLINE", "THICKOUTLINE", "MONOCHROME"
fontString:GetFont() : fontFile, height, flags
fontString:SetJustifyH(justifyH)  -- "LEFT", "CENTER", "RIGHT"
fontString:SetJustifyV(justifyV)  -- "TOP", "MIDDLE", "BOTTOM"
fontString:SetWordWrap(wrap)
fontString:SetMaxLines(maxLines)
fontString:GetStringWidth() : width
fontString:GetStringHeight() : height
fontString:GetWrappedWidth() : width
fontString:SetShadowOffset(x, y)
fontString:SetShadowColor(r, g, b [, a])
fontString:SetFontObject(fontObject)
fontString:ClearText()  -- New in 12.0.1
```

## Button Methods

```lua
button:SetText(text)
button:GetText() : text
button:SetEnabled(enabled)
button:IsEnabled() : enabled
button:Click([button, isDown])
button:RegisterForClicks(button1 [, ...])  -- "AnyDown", "AnyUp", "LeftButtonDown", etc.
button:SetNormalTexture(texture)
button:SetPushedTexture(texture)
button:SetHighlightTexture(texture [, blendMode])
button:SetDisabledTexture(texture)
button:GetNormalTexture() : texture
button:GetButtonState() : state  -- "NORMAL", "PUSHED", "DISABLED"
button:SetButtonState(state [, locked])
```

## EditBox Methods

```lua
editbox:SetText(text)
editbox:GetText() : text
editbox:GetNumber() : number
editbox:SetNumber(number)
editbox:SetMaxLetters(maxLetters)
editbox:SetFocus()
editbox:ClearFocus()
editbox:HasFocus() : hasFocus
editbox:SetAutoFocus(autoFocus)
editbox:SetMultiLine(multiLine)
editbox:SetPassword(isPassword)
editbox:HighlightText([start, end])
editbox:Insert(text)
editbox:SetCursorPosition(position)
editbox:GetCursorPosition() : position
```

## ScrollFrame Methods

```lua
scrollFrame:SetScrollChild(childFrame)
scrollFrame:GetScrollChild() : childFrame
scrollFrame:GetVerticalScroll() : offset
scrollFrame:SetVerticalScroll(offset)
scrollFrame:GetHorizontalScroll() : offset
scrollFrame:SetHorizontalScroll(offset)
scrollFrame:GetVerticalScrollRange() : range
scrollFrame:GetHorizontalScrollRange() : range
```

## StatusBar Methods

```lua
statusbar:SetMinMaxValues(min, max)
statusbar:GetMinMaxValues() : min, max
statusbar:SetValue(value)
statusbar:GetValue() : value
statusbar:SetStatusBarTexture(texture)
statusbar:SetStatusBarColor(r, g, b [, a])
statusbar:SetOrientation(orientation)  -- "HORIZONTAL" or "VERTICAL"
statusbar:SetFillStyle(fillStyle)  -- "STANDARD", "REVERSE", "CENTER", "STANDARD_NO_RANGE_FILL"
statusbar:SetReverseFill(reverse)
```

## Animation Methods

```lua
-- Create animation group
local ag = frame:CreateAnimationGroup([name, template])
ag:Play()
ag:Stop()
ag:Pause()
ag:SetLooping(loopType)  -- "NONE", "REPEAT", "BOUNCE"
ag:IsPlaying() : isPlaying

-- Create animation within group
local anim = ag:CreateAnimation(animType [, name, template])
-- animType: "Alpha", "Scale", "Translation", "Rotation", "Path", "LineScale", "LineTranslation", "TextureCoordTranslation"
anim:SetDuration(seconds)
anim:SetStartDelay(seconds)
anim:SetEndDelay(seconds)
anim:SetOrder(order)  -- Execution order within group
anim:SetSmoothing(smoothType)  -- "NONE", "IN", "OUT", "IN_OUT", "OUT_IN"
```

## GameTooltip Key Methods

```lua
GameTooltip:SetOwner(owner, anchor [, offsetX, offsetY])
-- anchor: "ANCHOR_TOPLEFT", "ANCHOR_TOPRIGHT", "ANCHOR_BOTTOMLEFT", "ANCHOR_BOTTOMRIGHT",
--         "ANCHOR_LEFT", "ANCHOR_RIGHT", "ANCHOR_CURSOR", "ANCHOR_PRESERVE", "ANCHOR_NONE"
GameTooltip:AddLine(text [, r, g, b, wrap])
GameTooltip:AddDoubleLine(leftText, rightText [, lr, lg, lb, rr, rg, rb])
GameTooltip:SetUnit(unitToken)
GameTooltip:SetSpellByID(spellID)
GameTooltip:SetItemByID(itemID)
GameTooltip:SetHyperlink(hyperlink)
GameTooltip:Show()
GameTooltip:Hide()
GameTooltip:ClearLines()
GameTooltip:ClearPadding()  -- New in 12.0.1
GameTooltip:NumLines() : numLines
GameTooltip:GetUnit() : unitName, unitID
GameTooltip:GetItem() : itemName, itemLink
GameTooltip:GetSpell() : spellName, spellID
```

## Draw Layers (bottom to top)

```
BACKGROUND  → behind everything
BORDER      → borders, outlines
ARTWORK     → main art (default)
OVERLAY     → overlays
HIGHLIGHT   → mouse highlight (top)
```

## Frame Strata (back to front)

```
WORLD → BACKGROUND → LOW → MEDIUM → HIGH → DIALOG → FULLSCREEN → FULLSCREEN_DIALOG → TOOLTIP
```

## PlayerModel Methods (Legacy)

```lua
local model = CreateFrame("PlayerModel", name, parent)
model:SetUnit(unitID)                  -- Display a unit ("player", "target", "npc")
model:SetDisplayInfo(displayID)        -- Display by CreatureDisplayID
model:SetCreature(creatureID)          -- Display by CreatureID
model:SetFacing(radians)               -- Rotate model
model:SetPosition(x, y, z)            -- Position within frame
model:SetCamera(cameraIndex)           -- Select predefined camera
model:SetCameraDistance(distance)
model:SetCameraPosition(x, y, z)
model:SetCameraTarget(x, y, z)
model:MakeCurrentCameraCustom()
model:SetModelScale(scale)
model:SetModelAlpha(alpha)
model:SetSequence(animID)              -- 0=stand, 4=walk, 60=emote_talk
model:SetSequenceTime(animID, timeMS)
model:SetPaused(paused)
model:SetLight(enabled, lightTable)    -- lightTable = {omni, dirX,dirY,dirZ, ambR,ambG,ambB, dirR,dirG,dirB}
model:SetDesaturation(strength)
model:SetParticlesEnabled(enabled)
model:GetModelFileID() : fileID
model:ClearModel()
```

## ModelScene Methods (Shadowlands+)

```lua
local scene = CreateFrame("ModelScene", name, parent, "ModelSceneFrameTemplate")
local actor = scene:CreateActor([name, template])
actor:SetModelByCreatureDisplayID(displayID)
actor:SetModelByUnit(unitID)
actor:SetAnimation(animID [, variation, speed])
actor:SetPosition(x, y, z)
actor:SetFacing(radians)
actor:SetScale(scale)
actor:SetAlpha(alpha)
actor:ClearModel()
scene:SetCameraOrientationByYawPitchRoll(yaw, pitch, roll)
scene:SetCameraPosition(x, y, z)
scene:SetCameraFieldOfView(fov)
scene:SetLightDirection(x, y, z)
scene:SetLightAmbientColor(r, g, b)
scene:SetLightDiffuseColor(r, g, b)
scene:SetLightVisible([visible])
scene:SetPaused(paused)
scene:GetNumActors() : numActors
C_ModelInfo.GetModelSceneActorDisplayInfoByID(displayID) : info
-- Returns: { animation, animationVariation, animSpeed, animationKitID, spellVisualKitID, alpha, scale }
```

### Common Animation IDs

| ID | Animation | ID | Animation |
|----|-----------|-----|-----------|
| 0 | Stand | 60 | EmoteTalk |
| 4 | Walk | 64 | EmoteWave |
| 5 | Run | 65 | EmoteBow |
| 26 | AttackUnarmed | 67 | EmoteDance |
| 69 | EmoteLaugh | 113 | EmotePoint |
