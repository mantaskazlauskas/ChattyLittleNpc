---
name: model-scene-api
description: "Complete reference for WoW ModelScene Widget API — the modern 3D model rendering system for addon UI. Covers ModelScene frame, ModelSceneActorBase, ModelSceneActor, C_ModelInfo helpers, camera/lighting/fog systems, Patch 12.0 SecretArguments/taint restrictions, and practical patterns. Current for Midnight (Patch 12.0.1, build 65893)."
---

# ModelScene Widget API — Midnight (Patch 12.0.1)

> The definitive reference for World of Warcraft's ModelScene 3D rendering widget system.
> Current as of Patch 12.0.1 (build 65893, Interface 120001) — the Midnight expansion launch patch.

---

## Overview

The **ModelScene** widget is WoW's modern system for rendering 3D models in addon UI. It consists of:

| Component | Type | Purpose |
|-----------|------|---------|
| **ModelScene** | Frame widget | 3D viewport with camera, lighting, and fog controls |
| **ModelSceneActorBase** | ScriptObject | Base class for 3D model actors — positioning, animation, model loading |
| **ModelSceneActor** | ScriptObject | Extended actor with DressUpModel features — transmog, equipment, mounts |
| **C_ModelInfo** | Global API | Database-backed scene/camera/actor presets from Blizzard's content DB |

### Widget Inheritance

```
Frame
  └── ModelScene (scene container — camera, lighting, fog, actors)

Object > FrameScriptObject (NOT ScriptObject)
  └── ModelSceneActorBase (3D actor — position, animation, model loading)
        └── ModelSceneActor (+ DressUpModel — transmog, equipment, mounts)
```

**Important**: `ModelSceneActor` inherits from `DressUpModel` and parts of `Model`, `Frame`, `ScriptRegion`. It does **not** inherit `ScriptObject` — scripts can only be set from XML, not Lua.

### Creation

```lua
-- Create a ModelScene frame
local scene = CreateFrame("ModelScene", nil, UIParent)
-- Or with the Blizzard template (recommended):
local scene = CreateFrame("ModelScene", nil, UIParent, "ModelSceneFrameTemplate")

-- Create an actor in the scene
local actor = scene:CreateActor()
-- Or with template:
local actor = scene:CreateActor("MyActorName", "ModelSceneActorTemplate")
```

**XML creation** (in your addon's .xml file):

```xml
<ModelScene parentKey="ModelScene" inherits="ModelSceneFrameTemplate">
    <Size x="300" y="400"/>
    <Anchors>
        <Anchor point="CENTER"/>
    </Anchors>
</ModelScene>
```

**Template details**:
- `ModelSceneFrameTemplate` — sets up basic scene defaults (lighting, camera). Recommended over bare `CreateFrame("ModelScene")`.
- `ModelSceneActorTemplate` — standard actor template. Falls back to bare `CreateActor()` if unavailable.
- Use `pcall(CreateFrame, "ModelScene", ...)` to safely detect unavailability on older clients.

### Game Client Availability

| Client | ModelScene | C_ModelInfo | Notes |
|--------|-----------|-------------|-------|
| **Mainline (Retail)** | ✅ Full | ✅ Full | 12.0.1 (Midnight) — Interface 120001 |
| **MoP Classic** | ✅ Available | ✅ Available | 5.5.3 — Interface 50503 |
| **BCC Anniversary** | ✅ Available | ✅ Available | 2.5.5 — Interface 20505 |
| **Classic Era** | ✅ Available | ✅ Available | 1.15.8 — Interface 11508 |

**Note**: While the widgets exist across all clients, specific method availability and behavior may differ. Always use `pcall` when calling ModelScene methods in addons that target multiple clients.

---

## Patch 12.0 Critical Change: SecretArguments

### What Changed

Patch 12.0.0 (Midnight pre-patch) added **SecretArguments** restrictions to nearly all ModelScene/Actor **setter** methods. This is part of the broader "Secret Values" security system.

### How It Works

| Caller Context | Argument Type | Result |
|----------------|---------------|--------|
| Untainted (Blizzard code) | Regular value | ✅ Works |
| Untainted (Blizzard code) | Secret value | ✅ Works |
| **Tainted (addon code)** | **Regular value** | **✅ Works** |
| **Tainted (addon code)** | **Secret value** | **❌ Lua error** |

**Key insight**: Addon code is ALWAYS tainted. But this only matters if you pass a **secret value** (returned by combat APIs like `UnitHealth()`, `UnitName()`, `UnitGUID()`) into a restricted setter. Using your own literal or computed values is **completely unaffected**.

### Rules for Addon Developers

```lua
-- ✅ SAFE: Literal/computed values from addon code
scene:SetCameraPosition(0, 5, 2)          -- always works
actor:SetModelByCreatureDisplayID(12345)   -- always works
actor:SetPosition(0, 0, 0)                -- always works

-- ❌ DANGEROUS: Secret combat API values in setters
local hp = UnitHealth("player")            -- returns SECRET value in 12.0
actor:SetScale(hp / 100)                   -- ERROR: arithmetic on secret
-- Even if you could compute it, passing secret to setter = error

-- ✅ SAFE: Getters with no arguments are always unrestricted
local x, y, z = actor:GetPosition()        -- works from any context
local fov = scene:GetCameraFieldOfView()   -- works from any context

-- ⚠️ CAUTION: Some "getter-like" functions take arguments and HAVE SecretArgs
-- (e.g., GetActorAtIndex, Project3DPointTo2D) — don't pass secret values as args
```

### Utility Functions

```lua
issecretvalue(val)    -- returns true if val is a secret value
canaccessvalue(val)   -- returns true if val can be used normally
widget:SetToDefaults() -- clears secret aspects from a widget
```

---

## ModelScene Methods

The ModelScene frame is the 3D viewport container. It manages the camera, lighting, fog, and actors.

### Actor Management

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `CreateActor` | Yes | `([name: cstring, template: cstring]) → actor` | Creates a ModelSceneActor in this scene |
| `GetActorAtIndex` | Yes | `(index: luaIndex) → actor` | Returns actor at 1-based index |
| `GetNumActors` | — | `() → numActors` | Number of actors in the scene |
| `TakeActor` | — | `()` | Detaches an actor from the scene's internal pool (use mixin's `ReleaseActor` instead) |

> **`CreateActor` note**: Blizzard docs declare both params as non-nilable `cstring`, but warcraft.wiki.gg documents them as optional: `([name, template])`. Calling `scene:CreateActor()` with no arguments is common. Template `"ModelSceneActorTemplate"` is typically passed when available.

### Camera — Position & Orientation

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `GetCameraPosition` | — | `() → x, y, z` | Camera world position |
| `SetCameraPosition` | Yes | `(x, y, z)` | Set camera world position |
| `GetCameraForward` | — | `() → fwdX, fwdY, fwdZ` | Camera forward vector |
| `GetCameraRight` | — | `() → rightX, rightY, rightZ` | Camera right vector |
| `GetCameraUp` | — | `() → upX, upY, upZ` | Camera up vector |
| `SetCameraOrientationByYawPitchRoll` | Yes | `(yaw, pitch, roll)` | Set camera orientation (radians) |
| `SetCameraOrientationByAxisVectors` | Yes | `(forwardX,forwardY,forwardZ, rightX,rightY,rightZ, upX,upY,upZ)` | Set camera by axis vectors |

### Camera — Projection

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `GetCameraFieldOfView` | — | `() → fov` | Vertical FOV in **radians** |
| `SetCameraFieldOfView` | Yes | `(fov)` | Set vertical FOV in **radians** |
| `GetCameraNearClip` | — | `() → nearClip` | Near clip plane distance |
| `SetCameraNearClip` | Yes | `(nearClip)` | Set near clip distance |
| `GetCameraFarClip` | — | `() → farClip` | Far clip plane distance |
| `SetCameraFarClip` | Yes | `(farClip)` | Set far clip distance |
| `Project3DPointTo2D` | Yes | `(x, y, z) → x2D, y2D, depth` | Project 3D point to clip space. **MayReturnNothing**. |

> **`Project3DPointTo2D` details**: Converts a 3D world-space point into the ModelScene frame's local coordinate space. Returns X/Y as fractions of the frame dimensions (0–1 range, where 0,0 is top-left). Multiply by `scene:GetWidth()`/`scene:GetHeight()` for pixel offsets. `depth` is the z-buffer value. Returns nil if the point is behind the camera or cannot be projected. Use cases: positioning UI frames on 3D model hotspots, drawing 3D quads/triangles via `TextureBase:SetVertexOffset(i, x, y)`.

### Lighting

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `GetLightType` | — | `() → lightType` | Returns `ModelLightType` enum or nil |
| `SetLightType` | Yes | `(lightType)` | Set light type (see `Enum.ModelLightType`) |
| `IsLightVisible` | — | `() → isVisible` | Whether the scene light is enabled |
| `SetLightVisible` | Yes | `([visible=false])` | Show/hide the scene light |
| `GetLightAmbientColor` | — | `() → r, g, b` | Ambient light RGB (0–1) |
| `SetLightAmbientColor` | Yes | `(r, g, b)` | Set ambient light color |
| `GetLightDiffuseColor` | — | `() → r, g, b` | Diffuse light RGB (0–1) |
| `SetLightDiffuseColor` | Yes | `(r, g, b)` | Set diffuse light color |
| `GetLightDirection` | — | `() → dirX, dirY, dirZ` | Light direction vector |
| `SetLightDirection` | Yes | `(dirX, dirY, dirZ)` | Set light direction |
| `GetLightPosition` | — | `() → posX, posY, posZ` | Light world position |
| `SetLightPosition` | Yes | `(posX, posY, posZ)` | Set light position |

### Fog

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `ClearFog` | — | `()` | Remove all fog from the scene |
| `GetFogColor` | — | `() → r, g, b` | Fog color RGB (0–1) |
| `SetFogColor` | Yes | `(r, g, b)` | Set fog color |
| `GetFogNear` | — | `() → near` | Fog start distance |
| `SetFogNear` | Yes | `(near)` | Set fog start distance |
| `GetFogFar` | — | `() → far` | Fog end distance (fully fogged) |
| `SetFogFar` | Yes | `(far)` | Set fog end distance |

### View & Display

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `GetDrawLayer` | — | `() → layer, sublevel` | Returns the DrawLayer |
| `SetDrawLayer` | Yes | `(layer)` | Set the DrawLayer |
| `SetDesaturation` | Yes | `(strength)` | Desaturate the scene (0–1). **No getter** — scene-level only, read back not possible. |
| `GetViewInsets` | — | `() → insets` | Returns `uiRect` view insets |
| `SetViewInsets` | Yes | `(insets)` | Set view insets (`uiRect`) |
| `GetViewTranslation` | — | `() → translationX, translationY` | 2D view translation |
| `SetViewTranslation` | Yes | `(translationX, translationY)` | Set 2D view translation |
| `GetAllowOverlappedModels` | — | `() → allow` | Whether models can overlap |
| `SetAllowOverlappedModels` | Yes | `(allow)` | Allow/disallow overlapping |
| `SetPaused` | Yes | `(paused [, affectsGlobalPause=true])` | Pause scene animation |

### Frame-Inherited Methods (commonly used on ModelScene)

These are inherited from the `Frame` base class and frequently used in ModelScene setup:

| Method | Description |
|--------|-------------|
| `Show()` / `Hide()` / `SetShown(show)` | Control scene visibility |
| `SetAlpha(alpha)` / `GetAlpha()` | Scene opacity (0–1) |
| `SetFrameStrata(strata)` | Set layering strata ("BACKGROUND", "LOW", "MEDIUM", "HIGH", etc.) |
| `SetFrameLevel(level)` | Set level within strata |
| `EnableMouse(enable)` | Enable/disable mouse interaction on the scene |
| `SetAllPoints(relativeTo)` | Anchor scene to fill a parent frame |
| `SetPoint(...)` / `SetSize(w, h)` | Standard positioning and sizing |
| `HookScript("OnSizeChanged", fn)` | **Important**: Re-apply camera when scene is resized |

### Mixin Methods (from ModelSceneMixin in FrameXML)

These come from Blizzard's `ModelSceneMixin` (not the raw C++ API) and are available when using `ModelSceneFrameTemplate`:

| Method | Description |
|--------|-------------|
| `GetPlayerActor()` | Returns the designated "player" actor (if scene was set up with one) |

> **`OnSizeChanged` pattern**: Resizing a ModelScene changes its aspect ratio. Always re-apply your camera when the frame size changes:
> ```lua
> scene:HookScript("OnSizeChanged", function(self)
>     MyAddon:ReapplyCamera(self)
> end)
> ```

---

## ModelSceneActorBase Methods

The base actor class — 3D model positioning, animation, and model loading.

### Model Loading

| Method | SecretArgs | Signature | Returns | Description |
|--------|-----------|-----------|---------|-------------|
| `SetModelByCreatureDisplayID` | Yes | `(creatureDisplayID [, useActivePlayerCustomizations=false])` | `success` | Load model by creature display ID |
| `SetModelByFileID` | Yes | `(asset [, useMips=false])` | `success` | Load model by file ID |
| `SetModelByPath` | Yes | `(asset [, useMips=false])` | `success` | Load model by file path |
| `SetModelByUnit` | Yes | `(unit [, sheatheWeapons=false [, autoDress=true [, hideWeapons=false [, usePlayerNativeForm=true [, holdBowString=false [, customRaceID]]]]]])` | `success` | Load model from a unit token |
| `SetPlayerModelFromGlues` | Yes | `([characterIndex [, sheatheWeapons=false [, autoDress=true [, hideWeapons=false [, usePlayerNativeForm=true [, customRaceID]]]]]])` | `success` | Load player model from character select |
| `ClearModel` | — | `()` | — | Remove the current model |
| `IsLoaded` | — | `() → isLoaded` | `bool` | Whether the model has finished loading |

### Model Info (Read-Only)

| Method | SecretArgs | Signature | Returns | Description |
|--------|-----------|-----------|---------|-------------|
| `GetModelFileID` | — | `()` | `fileID` | Current model's file ID |
| `GetModelPath` | — | `()` | `string` | Current model's file path |
| `GetModelUnitGUID` | — | `()` | `WOWGUID` | GUID of the unit (may be ConditionalSecret) |

### Position & Orientation

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `GetPosition` | — | `() → x, y, z` | Actor position in scene space |
| `SetPosition` | Yes | `(x, y, z)` | Set actor position |
| `GetYaw` | — | `() → yaw` | Rotation around vertical axis (radians) |
| `SetYaw` | Yes | `(yaw)` | Set yaw rotation |
| `GetPitch` | — | `() → pitch` | Forward/backward tilt (radians) |
| `SetPitch` | Yes | `(pitch)` | Set pitch |
| `GetRoll` | — | `() → roll` | Side-to-side roll (radians) |
| `SetRoll` | Yes | `(roll)` | Set roll |
| `GetScale` | — | `() → scale` | Actor scale multiplier |
| `SetScale` | Yes | `(scale)` | Set actor scale |
| `GetAlpha` | — | `() → alpha` | Actor opacity (0–1) |
| `SetAlpha` | Yes | `(alpha)` | Set actor opacity |

### Bounds

| Method | Signature | Returns | Description |
|--------|-----------|---------|-------------|
| `GetActiveBoundingBox` | `()` | `boxBottom: Vector3DMixin?, boxTop: Vector3DMixin?` | Current animation bounding box |
| `GetMaxBoundingBox` | `()` | `boxBottom: Vector3DMixin?, boxTop: Vector3DMixin?` | Maximum bounding box across all animations |

**Bounds priority**: Use `GetActiveBoundingBox` first (reflects current animation pose), fall back to `GetMaxBoundingBox` (full model extents). Both return `Vector3DMixin` objects with `.x`, `.y`, `.z` fields. **Both MayReturnNothing** — returns nil if model is unloaded, has no geometry, or is still loading. Always nil-guard.

### Animation

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `GetAnimation` | — | `() → animation` | Current `AnimationDataEnum` value |
| `SetAnimation` | Yes | `(animation [, variation, animSpeed=1, animOffsetSeconds=0])` | Set animation by ID |
| `GetAnimationVariation` | — | `() → variation` | Current animation variation |
| `GetAnimationBlendOperation` | — | `() → blendOp` | `ModelBlendOperation` enum value |
| `SetAnimationBlendOperation` | Yes | `(blendOp)` | Set animation blend mode |
| `PlayAnimationKit` | Yes | `(animationKit [, isLooping=false])` | Play an AnimationKit by ID |
| `StopAnimationKit` | — | `()` | Stop the currently playing animation kit |

**Common Animation IDs** (AnimationDataEnum — not a formal Lua enum; use numeric values):

| ID | Name | Description |
|----|------|-------------|
| 0 | Stand | Default idle pose |
| 4 | Walk | Walking animation |
| 5 | Run | Running animation |
| 26 | SpellCastOmni | Generic spell cast |
| 60 | Death | Death animation |
| 143 | Fly | Flying idle |
| 157 | MountSpecial | Mount special animation |
| 804 | EmoteTalk | NPC talking animation |

> **Tip**: Use `SetAnimation(0)` to reset to idle. Use `animSpeed` < 1 for slow-motion effects.

### Visual Effects

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `GetDesaturation` | — | `() → strength` | Desaturation amount (0–1) |
| `SetDesaturation` | Yes | `(strength)` | Set desaturation (0 = full color, 1 = grayscale) |
| `GetParticleOverrideScale` | — | `() → scale?` | Particle effect scale override |
| `SetParticleOverrideScale` | Yes | `([scale])` | Override particle scale; nil to reset |
| `GetSpellVisualKit` | — | `() → spellVisualKitID` | Currently applied spell visual kit |
| `SetSpellVisualKit` | Yes | `([spellVisualKitID=0, oneShot=false])` | Apply a spell visual kit |
| `SetGradientMask` | Yes | `(gradientIndex0, gradientIndex1, gradientIndex2, gradientIndex3)` | Apply gradient mask (**Added 11.2.7**) |
| `TryOn` | Yes | `(itemLinkOrItemModifiedAppearanceID [, handSlotName, spellEnchantmentID=0])` | Try on an item; returns `ItemTryOnReason?` |

### Origin & Collision

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `IsUsingCenterForOrigin` | — | `() → x, y, z` | Per-axis center-origin flags (3 booleans) |
| `SetUseCenterForOrigin` | Yes | `([x=false, y=false, z=false])` | Center the model's origin per axis |
| `IsPreferringModelCollisionBounds` | — | `() → preferring` | Whether collision bounds are preferred |
| `SetPreferModelCollisionBounds` | Yes | `(prefer)` | Use collision bounds for sizing/centering |

> **`SetUseCenterForOrigin`**: The API accepts 3 per-axis booleans (all default `false`). Passing a single `true` sets only the X axis. For full centering, use `SetUseCenterForOrigin(true, true, true)`.

### Visibility

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `IsShown` | — | `() → isShown` | Whether the actor is shown |
| `IsVisible` | — | `() → isVisible` | Whether the actor and parents are visible |
| `Show` | — | `()` | Show the actor |
| `Hide` | — | `()` | Hide the actor |
| `SetShown` | Yes | `([show=false])` | Show/hide the actor |

---

## ModelSceneActor Methods

Extends `ModelSceneActorBase` with DressUpModel features for equipment, transmog, and mount support.

### Equipment & Transmog

| Method | SecretArgs | Signature | Returns | Description |
|--------|-----------|-----------|---------|-------------|
| `Dress` | — | `()` | — | Apply current equipment to the model |
| `Undress` | Yes | `([includeWeapons=true])` | — | Remove all equipment from model |
| `UndressSlot` | Yes | `(inventorySlots)` | — | Remove equipment from specific slot |
| `DressPlayerSlot` | Yes | `(invSlot)` | — | Apply player's slot item to model |
| `GetAutoDress` | — | `() → autoDress` | — | Whether auto-dress is enabled |
| `SetAutoDress` | Yes | `(autoDress)` | — | Enable/disable auto-dressing on model load |
| `GetSheathed` | — | `() → sheathed` | — | Whether weapons are sheathed |
| `SetSheathed` | Yes | `(sheathed [, hidden=false])` | — | Sheathe weapons (optionally hide them) |
| `ResetNextHandSlot` | — | `()` | — | Reset hand slot for next TryOn call |

### Transmog Info

| Method | SecretArgs | Signature | Returns |
|--------|-----------|-----------|---------|
| `GetItemTransmogInfo` | Yes | `(inventorySlots) → itemTransmogInfo?` | `ItemTransmogInfoMixin` or nil |
| `GetItemTransmogInfoList` | — | `() → infoList` | Table of `ItemTransmogInfo` |
| `SetItemTransmogInfo` | Yes | `(transmogInfo [, inventorySlots, ignoreChildItems=false]) → result` | `ItemTryOnReason` |
| `GetUseTransmogChoices` | — | `() → use` | Whether transmog choices are active |
| `SetUseTransmogChoices` | Yes | `(use)` | Enable/disable transmog choices |
| `GetUseTransmogSkin` | — | `() → use` | Whether transmog skin is active |
| `SetUseTransmogSkin` | Yes | `(use)` | Enable/disable transmog skin |
| `GetObeyHideInTransmogFlag` | — | `() → obey` | Whether hide-in-transmog flag is obeyed |
| `SetObeyHideInTransmogFlag` | Yes | `(obey)` | Set hide-in-transmog flag behavior |
| `IsSlotAllowed` | Yes | `(inventorySlots) → allowed` | Whether a slot can be modified |
| `IsSlotVisible` | Yes | `(inventorySlots) → visible` | Whether a slot is visually shown |

### Mount System

| Method | SecretArgs | Signature | Returns | Description |
|--------|-----------|-----------|---------|-------------|
| `AttachToMount` | Yes | `(rider, animation [, spellKitVisualID])` | `success` | Attach rider actor to mount actor |
| `DetachFromMount` | Yes | `(rider)` | `success` | Detach rider from mount |
| `CalculateMountScale` | Yes | `(rider)` | `scale` | Compute proper scale for mount+rider |

### Model Loading (Actor-Specific)

| Method | SecretArgs | Signature | Returns | Description |
|--------|-----------|-----------|---------|-------------|
| `SetModelByHyperlink` | Yes | `(link)` | `success` | Load model from an item/creature hyperlink |
| `SetFrontEndLobbyModelFromDefaultCharacterDisplay` | Yes | `(characterIndex)` | `success` | Load character select lobby model |
| `ReleaseFrontEndCharacterDisplays` | — | `()` | `success` | Release character select display resources |

### Pause Control

| Method | SecretArgs | Signature | Description |
|--------|-----------|-----------|-------------|
| `GetPaused` | — | `() → paused, globalPaused` | Actor pause state + global pause state |
| `SetPaused` | Yes | `(paused [, affectsGlobalPause=true])` | Pause/resume actor animation |

> **Scene vs Actor pause**: `ModelScene:SetPaused` pauses all animation globally in the scene. `ModelSceneActor:SetPaused` pauses a single actor. When `affectsGlobalPause=true` (default), an actor's pause state contributes to the scene's global pause. Use `affectsGlobalPause=false` to pause an individual actor independently.

### Geo Readiness

| Method | Signature | Returns | Description |
|--------|-----------|---------|-------------|
| `IsGeoReady` | `()` | `bool` | Whether the model geometry is fully loaded and ready |

---

## C_ModelInfo — Scene Preset Helpers

The `C_ModelInfo` namespace provides database-backed presets for configuring ModelScene widgets with Blizzard's authored camera positions, actor placements, and display info. Added in **Patch 7.2.0** (Legion). All 4 query functions are `MayReturnNothing` (return nil for invalid IDs) and have `SecretArguments = AllowedWhenUntainted` in 12.0.

> **Important**: Scene IDs (`modelSceneID`) are DB keys — **not** the same as `Enum.ModelSceneType` values. You get scene IDs from companion APIs, not from the enum. Common sources:
>
> | Source API | Returns sceneID for |
> |-----------|---------------------|
> | `C_MountJournal.GetMountInfoExtraByID(mountID)` | Mount display (returns `..., modelSceneID`) |
> | `C_PetJournal.GetPetInfoBySpeciesID(speciesID)` | Pet display |
> | DressUpFrame XML (`modelSceneID` attribute) | Transmog/dressing room |
> | `C_Item.GetItemModelSceneInfoByID(itemID)` | Item 3D previews |
>
> The `Enum.ModelSceneType` is the *type* returned by `GetModelSceneInfoByID`, not the ID you pass to it.

### ModelSceneMixin (FrameXML Helper)

When using `ModelSceneFrameTemplate`, these mixin methods are available for preset-based setup:

```lua
-- Recommended approach: use the mixin's SetFromModelSceneID
-- This auto-creates actors, cameras, and registers with C_ModelInfo
scene:SetFromModelSceneID(modelSceneID, forceEvenIfSame, noAutoCreateActors)

-- Transition with animation effects (for scene changes)
scene:TransitionToModelSceneID(modelSceneID, cameraTransitionType, cameraModificationType, forceEvenIfSame)

-- Get actors/cameras by their scriptTag from the preset
local actor = scene:GetActorByTag("yourTag")
local camera = scene:GetCameraByTag("yourTag")

-- Player actor helper (finds actor by race/gender tag or "player" tag)
local playerActor = scene:GetPlayerActor()

-- Mount helper (sets up player on mount with proper scaling)
scene:AttachPlayerToMount(mountActor, animID, isSelfMount, disablePlayerMountPreview, spellVisualKitID, usePlayerNativeForm)

-- Scene lifecycle
scene:ClearScene()
scene:Reset()  -- re-applies current modelSceneID
```

### GetModelSceneInfoByID

```lua
modelSceneType, modelCameraIDs, modelActorsIDs, flags
    = C_ModelInfo.GetModelSceneInfoByID(modelSceneID)
```

| Return | Type | Description |
|--------|------|-------------|
| `modelSceneType` | `Enum.ModelSceneType` | Scene type enum (see below) |
| `modelCameraIDs` | `number[]` | Array of camera preset IDs for this scene |
| `modelActorsIDs` | `number[]` | Array of actor preset IDs for this scene |
| `flags` | `number` | Bitfield of `Enum.ModelSceneSetting` |

### GetModelSceneCameraInfoByID

```lua
local cam = C_ModelInfo.GetModelSceneCameraInfoByID(modelSceneCameraID)
```

Returns `UIModelSceneCameraInfo`:

| Field | Type | Description |
|-------|------|-------------|
| `modelSceneCameraID` | `number` | Camera preset ID |
| `scriptTag` | `string` | Script identifier tag |
| `cameraType` | `string` | Camera type name |
| `target` | `Vector3DMixin` | Look-at target position (.x, .y, .z) |
| `yaw` | `number` | Horizontal rotation (radians) |
| `pitch` | `number` | Vertical tilt (radians) |
| `roll` | `number` | Roll rotation (radians) |
| `zoomDistance` | `number` | Default orbit distance |
| `minZoomDistance` | `number` | Minimum allowed zoom |
| `maxZoomDistance` | `number` | Maximum allowed zoom |
| `zoomedTargetOffset` | `Vector3DMixin` | Target offset when zoomed (.x, .y, .z) |
| `zoomedYawOffset` | `number` | Yaw offset when zoomed |
| `zoomedPitchOffset` | `number` | Pitch offset when zoomed |
| `zoomedRollOffset` | `number` | Roll offset when zoomed |
| `flags` | `Enum.ModelSceneSetting` | Setting flags |

### GetModelSceneActorInfoByID

```lua
local actorInfo = C_ModelInfo.GetModelSceneActorInfoByID(modelActorID)
```

Returns `UIModelSceneActorInfo`:

| Field | Type | Description |
|-------|------|-------------|
| `modelActorID` | `number` | Actor preset ID |
| `scriptTag` | `string` | Script identifier tag |
| `position` | `Vector3DMixin` | World position (.x, .y, .z) |
| `yaw` | `number` | Facing rotation (radians) |
| `pitch` | `number` | Tilt (radians) |
| `roll` | `number` | Roll (radians) |
| `normalizeScaleAggressiveness` | `number?` | How aggressively to normalize scale (nil = don't) |
| `useCenterForOriginX` | `boolean` | Center origin on X axis |
| `useCenterForOriginY` | `boolean` | Center origin on Y axis |
| `useCenterForOriginZ` | `boolean` | Center origin on Z axis |
| `modelActorDisplayID` | `number?` | Optional display info override ID |

### GetModelSceneActorDisplayInfoByID

```lua
local display = C_ModelInfo.GetModelSceneActorDisplayInfoByID(modelActorDisplayID)
```

Returns `UIModelSceneActorDisplayInfo`:

| Field | Type | Description |
|-------|------|-------------|
| `animation` | `number` | Animation ID to play |
| `animationVariation` | `number` | Animation variation index |
| `animSpeed` | `number` | Animation playback speed multiplier |
| `animationKitID` | `number?` | Optional AnimationKit to play |
| `spellVisualKitID` | `number?` | Optional spell visual kit to apply |
| `alpha` | `number` | Actor opacity (0–1) |
| `scale` | `number` | Actor scale multiplier |

### Enum.ModelSceneType (20 values)

```lua
Enum.ModelSceneType = {
    MountJournal                = 0,   -- Mount Journal preview
    PetJournalCard              = 1,   -- Pet battle journal card
    ShopCard                    = 2,   -- In-game shop preview
    EncounterJournal            = 3,   -- Encounter Journal boss model
    PetJournalLoadout           = 4,   -- Pet battle loadout
    ArtifactTier2               = 5,   -- Legion artifact tier 2
    ArtifactTier2ForgingScene   = 6,   -- Artifact forging effect
    ArtifactTier2SlamEffect     = 7,   -- Artifact slam effect
    CommentatorVictoryFanfare   = 8,   -- PvP commentator victory
    ArtifactRelicTalentEffect   = 9,   -- Relic talent visual
    PvPWarModeOrb               = 10,  -- War Mode orb effect
    PvPWarModeFire              = 11,  -- War Mode fire effect
    PartyPose                   = 12,  -- Party pose (e.g., Island Expedition)
    AzeriteItemLevelUpToast     = 13,  -- Azerite level-up toast
    AzeritePowers               = 14,  -- Azerite power selection
    AzeriteRewardGlow           = 15,  -- Azerite reward glow effect
    HeartOfAzeroth              = 16,  -- Heart of Azeroth display
    WorldMapThreat              = 17,  -- World map N'Zoth threat
    Soulbinds                   = 18,  -- Shadowlands soulbind display
    JailersTowerAnimaGlow       = 19,  -- Torghast anima glow
}
```

### Enum.ModelSceneSetting

```lua
Enum.ModelSceneSetting = {
    AlignLightToOrbitDelta = 1,  -- Align scene lighting to camera orbit changes
}
```

### Enum.ModelLightType

```lua
-- Used with ModelScene:SetLightType/GetLightType
-- Available as global constants (not a Lua enum table):
LE_MODEL_LIGHT_TYPE_DIRECTIONAL = 1  -- Directional (sun-like) lighting
-- Point light (positional) = 0, but no global constant exists for it.
-- Use: scene:SetLightType(0) for point, scene:SetLightType(1) for directional.
```

### Enum.ModelBlendOperation

```lua
-- Used with SetAnimationBlendOperation/GetAnimationBlendOperation
-- Controls how a secondary animation blends with the primary animation
Enum.ModelBlendOperation = {
    None = 0,    -- No blending (replace)
    Anim = 1,    -- Standard animation blend
}
```

### Internal Methods (no-op in public clients)

```lua
-- These exist in the API docs but do nothing in public (non-dev) clients:
C_ModelInfo.AddActiveModelScene(modelSceneFrame, modelSceneID)
C_ModelInfo.AddActiveModelSceneActor(modelSceneFrameActor, modelSceneActorID)
C_ModelInfo.ClearActiveModelScene(modelSceneFrame)
C_ModelInfo.ClearActiveModelSceneActor(modelSceneFrameActor)
-- All have SecretArguments = AllowedWhenUntainted
```

### Event

```lua
UI_MODEL_SCENE_INFO_UPDATED
-- Fires when C_ModelInfo DB entries are hotfixed by the server
-- Use this to refresh any cached scene/camera/actor info
```

### Applying C_ModelInfo Presets (Full Pattern)

```lua
-- RECOMMENDED: Use the mixin method (handles cameras, actors, lifecycle):
-- scene:SetFromModelSceneID(sceneID)  -- see ModelSceneMixin section above

-- MANUAL approach (if not using ModelSceneFrameTemplate mixin):
local function ApplyModelScenePreset(scene, sceneID, actorIndex)
    actorIndex = actorIndex or 1
    local sceneType, cameraIDs, actorIDs, flags =
        C_ModelInfo.GetModelSceneInfoByID(sceneID)
    if not sceneType then return false end

    -- Apply first camera (orbit around target at zoomDistance)
    if cameraIDs and cameraIDs[1] then
        local cam = C_ModelInfo.GetModelSceneCameraInfoByID(cameraIDs[1])
        if cam then
            -- cam.target is the look-at point; cam.zoomDistance is the orbit radius
            -- Compute camera position on a sphere around the target
            local dist = cam.zoomDistance
            local cy, sy = math.cos(cam.yaw), math.sin(cam.yaw)
            local cp, sp = math.cos(cam.pitch), math.sin(cam.pitch)
            local camX = cam.target.x + dist * cp * cy
            local camY = cam.target.y + dist * cp * sy
            local camZ = cam.target.z + dist * sp
            scene:SetCameraPosition(camX, camY, camZ)

            -- Compute look-at axis vectors
            local tx, ty, tz = cam.target.x, cam.target.y, cam.target.z
            local len = math.sqrt((tx-camX)^2 + (ty-camY)^2 + (tz-camZ)^2)
            if len > 1e-6 then
                local fx, fy, fz = (tx-camX)/len, (ty-camY)/len, (tz-camZ)/len
                -- Right = cross(worldUp, forward)
                local rx, ry, rz = -fz*0 + fy*1, fz*0 - fx*0, fx*0 - fy*0
                -- Simplified: worldUp=(0,0,1), right = cross((0,0,1), forward)
                rx, ry, rz = 0*fz - 1*fy, 1*fx - 0*fz, 0*fy - 0*fx
                local rlen = math.sqrt(rx*rx + ry*ry + rz*rz)
                if rlen > 1e-6 then
                    rx, ry, rz = rx/rlen, ry/rlen, rz/rlen
                end
                -- Up = cross(forward, right)
                local ux, uy, uz = fy*rz - fz*ry, fz*rx - fx*rz, fx*ry - fy*rx
                -- Docs say (forward, right, up); see axis vector note if wrong
                scene:SetCameraOrientationByAxisVectors(
                    fx, fy, fz,  rx, ry, rz,  ux, uy, uz
                )
            end
        end
    end

    -- Apply actor placement from preset
    if actorIDs and actorIDs[actorIndex] then
        local actorInfo = C_ModelInfo.GetModelSceneActorInfoByID(actorIDs[actorIndex])
        if actorInfo then
            local actor = scene:GetActorAtIndex(1) or scene:CreateActor()
            actor:SetPosition(actorInfo.position.x, actorInfo.position.y, actorInfo.position.z)
            actor:SetYaw(actorInfo.yaw)
            actor:SetUseCenterForOrigin(
                actorInfo.useCenterForOriginX,
                actorInfo.useCenterForOriginY,
                actorInfo.useCenterForOriginZ
            )
            -- Apply display overrides if referenced
            if actorInfo.modelActorDisplayID then
                local display = C_ModelInfo.GetModelSceneActorDisplayInfoByID(
                    actorInfo.modelActorDisplayID)
                if display then
                    actor:SetAnimation(display.animation, display.animationVariation, display.animSpeed)
                    actor:SetAlpha(display.alpha)
                    actor:SetScale(display.scale)
                    if display.spellVisualKitID then
                        actor:SetSpellVisualKit(display.spellVisualKitID)
                    end
                end
            end
            return true
        end
    end
    return false
end
```

---

## Coordinate System

```
       +Z (up)
        |
        |
        |_____ +Y (right)
       /
      /
    +X (forward / into screen)
```

- **+Z** is up (vertical)
- Camera "forward" is derived from yaw/pitch
- Actor **yaw** rotates around +Z (facing left/right)
  - **yaw = 0** faces +X (into the screen / away from default camera)
  - **yaw = π** faces -X (toward viewer when camera is on +Y axis)
  - To face a camera at `SetCameraOrientationByYawPitchRoll(π, 0, 0)`, set `actor:SetYaw(0)` (both face toward each other)
- Actor **pitch** tilts forward/backward
- Actor **roll** tilts side-to-side
- All angles are in **radians**
- FOV is **vertical** field of view in radians
- **Aspect ratio** is not a native API — compute it: `scene:GetWidth() / scene:GetHeight()`
- **Horizontal FOV** from vertical: `hfov = 2 * math.atan(math.tan(vfov / 2) * aspect)`

---

## Common Patterns

### Display a Creature by Display ID

```lua
local scene = CreateFrame("ModelScene", nil, UIParent)
scene:SetPoint("CENTER")
scene:SetSize(300, 400)

-- Setup camera
scene:SetCameraPosition(0, 5, 1)
scene:SetCameraFieldOfView(0.6)
scene:SetCameraNearClip(0.1)
scene:SetCameraFarClip(100)
scene:SetCameraOrientationByYawPitchRoll(0, 0, 0)

-- Setup lighting
scene:SetLightVisible(true)
scene:SetLightAmbientColor(0.6, 0.6, 0.6)
scene:SetLightDiffuseColor(1, 1, 1)
scene:SetLightDirection(-1, -1, -1)

-- Create actor and load model
local actor = scene:CreateActor()
actor:SetUseCenterForOrigin(true, true, true)
actor:SetPosition(0, 0, 0)

local success = actor:SetModelByCreatureDisplayID(12345)
```

### Display a Player/Unit Model

```lua
local actor = scene:CreateActor()
local success = actor:SetModelByUnit("player",
    false,  -- sheatheWeapons
    true,   -- autoDress
    false,  -- hideWeapons
    true,   -- usePlayerNativeForm
    false   -- holdBowString
)
```

### Orbit Camera Setup

```lua
-- Orbit camera: camera orbits around a target point at a given distance.
-- Uses axis vectors for reliable orientation (avoids YPR ambiguity).
local function SetOrbitCamera(scene, distance, yaw, pitch, target)
    target = target or {x=0, y=0, z=0}

    -- Compute camera position on a sphere around the target
    local cp = math.cos(pitch)
    local sp = math.sin(pitch)
    local cy = math.cos(yaw)
    local sy = math.sin(yaw)
    local camX = target.x + distance * cp * cy
    local camY = target.y + distance * cp * sy
    local camZ = target.z + distance * sp

    scene:SetCameraPosition(camX, camY, camZ)

    -- Compute look-at vectors (camera faces the target)
    local dx, dy, dz = target.x - camX, target.y - camY, target.z - camZ
    local len = math.sqrt(dx*dx + dy*dy + dz*dz)
    if len < 1e-6 then return end
    local fx, fy, fz = dx/len, dy/len, dz/len  -- forward

    -- Right = cross(worldUp, forward); worldUp = (0,0,1)
    local rx, ry, rz = -fy, fx, 0
    local rlen = math.sqrt(rx*rx + ry*ry + rz*rz)
    if rlen > 1e-6 then rx, ry, rz = rx/rlen, ry/rlen, rz/rlen end

    -- Up = cross(forward, right)
    local ux, uy, uz = fy*rz - fz*ry, fz*rx - fx*rz, fx*ry - fy*rx

    -- Docs say (forward, right, up); see axis vector note if orientation is wrong
    scene:SetCameraOrientationByAxisVectors(
        fx, fy, fz,  rx, ry, rz,  ux, uy, uz
    )
end

-- Example: camera 5 units away, slight elevation, looking at model center
SetOrbitCamera(scene, 5, 0, 0.1, {x=0, y=0, z=1})
```

### Waiting for Model Load (Robust Pattern)

```lua
-- Models load asynchronously. IsLoaded() must be polled.
-- IMPORTANT: Always wrap IsLoaded in pcall — it can error on some models.
local function WaitForModelLoad(actor, callback, timeoutMs, intervalMs)
    timeoutMs = timeoutMs or 3000
    intervalMs = intervalMs or 50
    local maxTicks = math.ceil(timeoutMs / intervalMs)
    local ticks = 0
    local ticker
    ticker = C_Timer.NewTicker(intervalMs / 1000, function()
        ticks = ticks + 1
        local ok, loaded = pcall(actor.IsLoaded, actor)
        if (ok and loaded) or ticks >= maxTicks then
            ticker:Cancel()
            callback(actor, ok and loaded)
        end
    end, maxTicks)
    return ticker  -- caller can cancel early via ticker:Cancel()
end

-- Usage:
actor:SetModelByCreatureDisplayID(12345)
WaitForModelLoad(actor, function(actor, didLoad)
    if didLoad then
        local boxBottom, boxTop = actor:GetActiveBoundingBox()
        if boxBottom and boxTop then
            local height = boxTop.z - boxBottom.z
            -- Adjust camera based on model height...
        end
    end
end)
```

**Tip**: Wrapping `IsLoaded()` in `pcall` is defensive coding — useful when teardown may invalidate the actor mid-poll.

### Defensive Capability Detection

```lua
-- Check method availability before calling (useful for multi-client addons)
local function hasMethod(obj, name)
    return obj and obj[name] ~= nil
end

if hasMethod(actor, "SetUseTransmogChoices") then
    actor:SetUseTransmogChoices(false)
end
```

### Framing with Bounds

```lua
local function FitModelToView(scene, actor, padding)
    padding = padding or 0.1
    local bottom, top = actor:GetActiveBoundingBox()
    if not bottom then
        bottom, top = actor:GetMaxBoundingBox()
    end
    if not (bottom and top) then return end

    local height = top.z - bottom.z
    local fov = scene:GetCameraFieldOfView()
    local distance = (height / 2) / math.tan(fov / 2)
    distance = distance * (1 + padding)

    local centerZ = (bottom.z + top.z) / 2
    -- Place camera along +Y, looking toward origin (-Y direction)
    scene:SetCameraPosition(0, distance, centerZ)

    -- Compute axis vectors: camera looks along -Y toward model
    local fx, fy, fz =  0, -1,  0  -- forward (camera look direction)
    local rx, ry, rz =  1,  0,  0  -- right
    local ux, uy, uz =  0,  0,  1  -- up
    -- Docs say (forward, right, up); see axis vector note if orientation is wrong
    scene:SetCameraOrientationByAxisVectors(
        fx, fy, fz,  rx, ry, rz,  ux, uy, uz
    )
end
```

### Mount + Rider Composition

```lua
local mountActor = scene:CreateActor()
mountActor:SetModelByCreatureDisplayID(mountDisplayID)

local riderActor = scene:CreateActor()
riderActor:SetModelByUnit("player")

-- Calculate proper scale and attach
-- animationID: 0 = idle/stand, 143 = flying idle. Use 0 for ground mounts.
local scale = mountActor:CalculateMountScale(riderActor)
mountActor:SetScale(scale)
mountActor:AttachToMount(riderActor, 0)  -- 0 = mounted idle
```

> **Multi-actor load sequencing**: Both models load asynchronously. Wait for both before composing:
> ```lua
> local mountLoaded, riderLoaded = false, false
> local function TryCompose()
>     if not (mountLoaded and riderLoaded) then return end
>     local scale = mountActor:CalculateMountScale(riderActor)
>     mountActor:SetScale(scale)
>     mountActor:AttachToMount(riderActor, 0)
> end
> WaitForModelLoad(mountActor, function(_, ok) mountLoaded = ok; TryCompose() end)
> WaitForModelLoad(riderActor, function(_, ok) riderLoaded = ok; TryCompose() end)
> ```
>
> **Or use the mixin** (recommended): `scene:AttachPlayerToMount(mountActor, animID)` handles all this automatically when using `ModelSceneFrameTemplate`.

### Adding Fog

```lua
scene:SetFogColor(0.2, 0.2, 0.3)  -- dark blue fog
scene:SetFogNear(5)                 -- fog starts at distance 5
scene:SetFogFar(50)                 -- fully fogged at distance 50
-- To remove:
scene:ClearFog()
```

---

## Best Practices

### DO

- **Use `pcall` around ModelScene creation** — not available on Classic clients
- **Use `pcall` around `SetModelByCreatureDisplayID`** — some display IDs are invalid
- **Wait for `IsLoaded()` before reading bounds** — models load asynchronously
- **Use `SetUseCenterForOrigin(true, true, true)`** — ensures consistent rotation
- **Scale near clip proportionally to camera distance** — prevents z-fighting
- **Prefer `GetActiveBoundingBox` over `GetMaxBoundingBox`** — reflects current pose
- **Keep ModelScene setters with literal/computed values** — avoids SecretArguments errors
- **Clean up actors when done** — frames cannot be garbage collected. Use the mixin's `scene:ReleaseActor(actor)` to return an actor to the pool, or `scene:ClearScene()` to release all actors and cameras. Calling `actor:Hide(); actor:ClearModel()` reduces rendering cost but doesn't free the object.

### DON'T

- **Don't pass combat API return values to ModelScene setters** — may be secret in 12.0
- **Don't assume bounds are immediately available after SetModel** — wait for load
- **Don't create excessive actors** — each consumes rendering resources
- **Don't call setters from hooked Blizzard functions with secret args** — will error
- **Don't use `SetModelByUnit` out of combat for NPCs** — unit may not be available

---

## Taint-Safe Patterns for 12.0

```lua
-- ✅ Pattern 1: Hardcoded values (always safe)
actor:SetModelByCreatureDisplayID(displayIDFromAddonDB)

-- ✅ Pattern 2: Computed from addon data (always safe)
local scale = myAddon.db.profile.modelScale or 1.0
actor:SetScale(scale)

-- ✅ Pattern 3: Check before using potentially secret values
local function safeSetScale(actor, value)
    if issecretvalue and issecretvalue(value) then return end
    actor:SetScale(value)
end

-- ✅ Pattern 4: Getters are always safe
local pos = {actor:GetPosition()}
local bounds = {actor:GetActiveBoundingBox()}
local loaded = actor:IsLoaded()
```

### When You Receive a Potentially Secret Value

Secret values **cannot** be converted, inspected, or "laundered" — that's by design. If a value is secret, you cannot pass it to ModelScene setters from addon code. Strategies:

```lua
-- ✅ Strategy A: Maintain your own ID mapping (most common for addon devs)
-- Don't rely on C_ APIs that might return secrets. Cache IDs yourself.
local myDisplayIDs = { ["Hogger"] = 46254, ["Deathwing"] = 35229 }

-- ✅ Strategy B: Use the preset system (sceneIDs from C_MountJournal etc.)
-- SetFromModelSceneID uses Blizzard's untainted mixin code internally
scene:SetFromModelSceneID(sceneIDFromAPI)

-- ✅ Strategy C: Guard and bail out gracefully
local function SafeSetDisplayID(actor, displayID)
    if issecretvalue and issecretvalue(displayID) then
        -- Can't use it. Show a placeholder or skip.
        return false
    end
    return pcall(actor.SetModelByCreatureDisplayID, actor, displayID, false)
end

-- ❌ These DO NOT work for recovering secret values:
-- tonumber(secretVal)     -- errors
-- tostring(secretVal)     -- errors
-- secretVal + 0           -- errors
-- table key = secretVal   -- irrevocably poisons the table
```

---

## Version History

| Patch | Changes |
|-------|---------|
| **7.0.3** | ModelScene widget introduced (Legion) |
| **8.0.1** | ModelSceneActor, mount system, transmog support added |
| **10.x** | Stable API through Dragonflight |
| **11.2.7** | `SetGradientMask` added to ModelSceneActorBase |
| **12.0.0** | SecretArguments added to all setter methods (Midnight pre-patch) |
| **12.0.1** | Midnight launch patch — TOC 120001, no ModelScene-specific changes |

---

## Reference Links

### Primary Sources (actively maintained, authoritative)

| Source | URL | What it covers |
|--------|-----|----------------|
| **Warcraft Wiki (wiki.gg)** | https://warcraft.wiki.gg/wiki/Widget_API | Modern, actively updated API reference (functions/events/widgets) |
| **Warcraft Wiki — ModelScene** | https://warcraft.wiki.gg/wiki/UIOBJECT_ModelScene | ModelScene frame method reference |
| **Warcraft Wiki — ActorBase** | https://warcraft.wiki.gg/wiki/UIOBJECT_ModelSceneActorBase | ActorBase method reference |
| **Warcraft Wiki — Actor** | https://warcraft.wiki.gg/wiki/UIOBJECT_ModelSceneActor | ModelSceneActor (DressUpModel) reference |
| **Gethe/wow-ui-source (GitHub)** | https://github.com/Gethe/wow-ui-source | FrameXML source mirror — most authoritative for real behavior |
| **Blizzard API Docs (in-game)** | `/api` command in-game | Official Blizzard_APIDocumentation addon |
| **Blizzard API Docs (source)** | `Interface/AddOns/Blizzard_APIDocumentationGenerated/` | Lua source files with typed signatures |

### Secondary Sources

| Source | URL | What it covers |
|--------|-----|----------------|
| **Wowpedia (Fandom)** | https://wowpedia.fandom.com/wiki/World_of_Warcraft_API | Large historical API reference (may lag newer patches) |
| **WoWWiki archive (Fandom)** | https://wowwiki-archive.fandom.com/wiki/World_of_Warcraft_API | Older reference pages and event lists |
| **AddOn Studio wiki** | https://addonstudio.org/wiki/WoW:World_of_Warcraft_API | API reference + FrameXML/UI topics |
| **Townlong-Yak** | https://www.townlong-yak.com/framexml/ | FrameXML browser (availability intermittent) |
| **mrbuds /api web** | https://mrbuds.github.io/wow-api-web/ | Searchable Blizzard_APIDocumentation mirror |

### Community Resources

| Source | URL | What it covers |
|--------|-----|----------------|
| **wowuidev Discord** | https://discord.gg/txUg39Vhc6 | Active addon development community |
| **Ketho/BlizzardInterfaceResources** | https://github.com/Ketho/BlizzardInterfaceResources | Templates, enums, globals dumps |

### Key Blizzard API Doc Files (in wow-ui-source)

```
Interface/AddOns/Blizzard_APIDocumentationGenerated/
├── FrameAPIModelSceneFrameDocumentation.lua          -- ModelScene methods
├── FrameAPIModelSceneFrameActorDocumentation.lua     -- ModelSceneActor methods
├── FrameAPIModelSceneFrameActorBaseDocumentation.lua -- ModelSceneActorBase methods
└── UIModelInfoDocumentation.lua                      -- C_ModelInfo functions
```

### API Change Tracking

| Patch | URL |
|-------|-----|
| **12.0.1 (Midnight launch)** | https://warcraft.wiki.gg/wiki/Patch_12.0.1/API_changes |
| **12.0.0 (Midnight pre-patch)** | https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes |
| **All API change summaries** | https://warcraft.wiki.gg/wiki/API_change_summaries |
