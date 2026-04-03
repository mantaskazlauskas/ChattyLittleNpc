# C_ModelInfo API Reference

The `C_ModelInfo` namespace provides helper functions for working with Blizzard's
pre-authored ModelScene data stored in the game database. It lets addons query
scene definitions (camera positions, actor placement, display overrides) by
numeric ID and apply them to `ModelScene` widgets without hard-coding values.

**Namespace:** `C_ModelInfo`  
**Environment:** All (mainline, classic era, MoP classic, BCC anniversary)  
**Added:** Patch 7.2.0 / 1.13.2  
**Source:** `Blizzard_APIDocumentationGenerated/UIModelInfoDocumentation.lua`

> All functions carry the `SecretArguments = "AllowedWhenUntainted"` predicate
> and are safe to call from addon code. Functions that query by ID carry the
> `MayReturnNothing` predicate — they return **nil** when the requested ID does
> not exist in the client's database.

---

## Functions

### C_ModelInfo.GetModelSceneInfoByID

Retrieves the top-level definition of a model scene: its type, which cameras
and actors belong to it, and scene-level flags.

```lua
modelSceneType, modelCameraIDs, modelActorsIDs, flags = C_ModelInfo.GetModelSceneInfoByID(modelSceneID)
```

| Direction | Name | Type | Nilable | Description |
|-----------|------|------|---------|-------------|
| **arg** | `modelSceneID` | `number` | no | Database ID of the scene to query. |
| **ret** | `modelSceneType` | `Enum.ModelSceneType` | no | Scene category (see enum table below). |
| **ret** | `modelCameraIDs` | `number[]` | no | Array of camera IDs belonging to this scene. |
| **ret** | `modelActorsIDs` | `number[]` | no | Array of actor IDs belonging to this scene. |
| **ret** | `flags` | `number` | no | Bitmask of scene-level flags. |

Returns **nil** if `modelSceneID` is invalid.

#### Example

```lua
local sceneType, cameraIDs, actorIDs, flags = C_ModelInfo.GetModelSceneInfoByID(290)
if sceneType then
    print("Scene type:", sceneType)               -- e.g. Enum.ModelSceneType.MountJournal
    print("Cameras:", #cameraIDs, "Actors:", #actorIDs)
end
```

---

### C_ModelInfo.GetModelSceneCameraInfoByID

Returns the full camera definition for a single camera ID, including orbit
parameters, zoom limits, and zoomed-state offsets.

```lua
modelSceneCameraInfo = C_ModelInfo.GetModelSceneCameraInfoByID(modelSceneCameraID)
```

| Direction | Name | Type | Nilable | Description |
|-----------|------|------|---------|-------------|
| **arg** | `modelSceneCameraID` | `number` | no | Camera ID (from `modelCameraIDs`). |
| **ret** | `modelSceneCameraInfo` | `UIModelSceneCameraInfo` | no | Camera data table (see structure below). |

Returns **nil** if `modelSceneCameraID` is invalid.

#### UIModelSceneCameraInfo structure

| Field | Type | Nilable | Description |
|-------|------|---------|-------------|
| `modelSceneCameraID` | `number` | no | Echo of the queried ID. |
| `scriptTag` | `string` | no | Script identifier tag (e.g. `"primary"`). |
| `cameraType` | `string` | no | Camera behaviour type string. |
| `target` | `vector3` (Vector3DMixin) | no | World-space look-at point `{x, y, z}`. |
| `yaw` | `number` | no | Orbit yaw in radians. |
| `pitch` | `number` | no | Orbit pitch in radians. |
| `roll` | `number` | no | Camera roll in radians. |
| `zoomDistance` | `number` | no | Default orbit distance from target. |
| `minZoomDistance` | `number` | no | Closest allowed zoom distance. |
| `maxZoomDistance` | `number` | no | Farthest allowed zoom distance. |
| `zoomedTargetOffset` | `vector3` (Vector3DMixin) | no | Target offset applied when zoomed. |
| `zoomedYawOffset` | `number` | no | Yaw delta applied when zoomed. |
| `zoomedPitchOffset` | `number` | no | Pitch delta applied when zoomed. |
| `zoomedRollOffset` | `number` | no | Roll delta applied when zoomed. |
| `flags` | `Enum.ModelSceneSetting` | no | Camera-level flags bitmask. |

#### Example

```lua
local cam = C_ModelInfo.GetModelSceneCameraInfoByID(cameraIDs[1])
if cam then
    print(cam.scriptTag, cam.zoomDistance) -- "primary"  8.5
    -- Apply to a ModelScene camera:
    local sceneCam = modelScene:GetActiveCamera()
    sceneCam:SetTarget(cam.target:GetXYZ())
    sceneCam:SetYaw(cam.yaw)
    sceneCam:SetPitch(cam.pitch)
    sceneCam:SetMinZoomDistance(cam.minZoomDistance)
    sceneCam:SetMaxZoomDistance(cam.maxZoomDistance)
    sceneCam:SetZoomDistance(cam.zoomDistance)
end
```

---

### C_ModelInfo.GetModelSceneActorInfoByID

Returns the placement and transform data for a single actor slot within a
scene — position, orientation, scale normalisation, and an optional display
override.

```lua
actorInfo = C_ModelInfo.GetModelSceneActorInfoByID(modelActorID)
```

| Direction | Name | Type | Nilable | Description |
|-----------|------|------|---------|-------------|
| **arg** | `modelActorID` | `number` | no | Actor ID (from `modelActorsIDs`). |
| **ret** | `actorInfo` | `UIModelSceneActorInfo` | no | Actor data table (see structure below). |

Returns **nil** if `modelActorID` is invalid.

#### UIModelSceneActorInfo structure

| Field | Type | Nilable | Description |
|-------|------|---------|-------------|
| `modelActorID` | `number` | no | Echo of the queried ID. |
| `scriptTag` | `string` | no | Script identifier tag. |
| `position` | `vector3` (Vector3DMixin) | no | World-space actor position `{x, y, z}`. |
| `yaw` | `number` | no | Facing yaw in radians (around +Z). |
| `pitch` | `number` | no | Pitch rotation in radians. |
| `roll` | `number` | no | Roll rotation in radians. |
| `normalizeScaleAggressiveness` | `number` | yes | If set, how aggressively to normalize model scale. |
| `useCenterForOriginX` | `boolean` | no | Use center of model bounds as X origin. |
| `useCenterForOriginY` | `boolean` | no | Use center of model bounds as Y origin. |
| `useCenterForOriginZ` | `boolean` | no | Use center of model bounds as Z origin. |
| `modelActorDisplayID` | `number` | yes | Optional display info override ID (query with `GetModelSceneActorDisplayInfoByID`). |

#### Example

```lua
local actorInfo = C_ModelInfo.GetModelSceneActorInfoByID(actorIDs[1])
if actorInfo then
    local actor = modelScene:GetActorByTag(actorInfo.scriptTag)
    if actor then
        actor:SetPosition(actorInfo.position:GetXYZ())
        actor:SetYaw(actorInfo.yaw)
        actor:SetUseCenterForOrigin(
            actorInfo.useCenterForOriginX,
            actorInfo.useCenterForOriginY,
            actorInfo.useCenterForOriginZ
        )
    end
end
```

---

### C_ModelInfo.GetModelSceneActorDisplayInfoByID

Returns animation and visual overrides for an actor slot, referenced by the
`modelActorDisplayID` field of `UIModelSceneActorInfo`.

```lua
actorDisplayInfo = C_ModelInfo.GetModelSceneActorDisplayInfoByID(modelActorDisplayID)
```

| Direction | Name | Type | Nilable | Description |
|-----------|------|------|---------|-------------|
| **arg** | `modelActorDisplayID` | `number` | no | Display info ID (from `actorInfo.modelActorDisplayID`). |
| **ret** | `actorDisplayInfo` | `UIModelSceneActorDisplayInfo` | no | Display data table (see structure below). |

Returns **nil** if `modelActorDisplayID` is invalid.

#### UIModelSceneActorDisplayInfo structure

| Field | Type | Nilable | Description |
|-------|------|---------|-------------|
| `animation` | `number` | no | Animation ID to play on the actor. |
| `animationVariation` | `number` | no | Variation index for the animation. |
| `animSpeed` | `number` | no | Playback speed multiplier (1.0 = normal). |
| `animationKitID` | `number` | yes | Optional AnimationKit override. |
| `spellVisualKitID` | `number` | yes | Optional SpellVisualKit to attach. |
| `alpha` | `number` | no | Actor alpha (0.0–1.0). |
| `scale` | `number` | no | Actor scale multiplier. |

#### Example

```lua
local actorInfo = C_ModelInfo.GetModelSceneActorInfoByID(actorIDs[1])
if actorInfo and actorInfo.modelActorDisplayID then
    local display = C_ModelInfo.GetModelSceneActorDisplayInfoByID(actorInfo.modelActorDisplayID)
    if display then
        actor:SetAnimation(display.animation, display.animationVariation)
        actor:SetAlpha(display.alpha)
        actor:SetModelScale(display.scale)
    end
end
```

---

### C_ModelInfo.AddActiveModelScene

Registers a ModelScene frame as actively displaying a scene. **Does nothing in
public (non-internal) clients** — included for completeness.

```lua
C_ModelInfo.AddActiveModelScene(modelSceneFrame, modelSceneID)
```

| Direction | Name | Type | Nilable | Description |
|-----------|------|------|---------|-------------|
| **arg** | `modelSceneFrame` | `ModelSceneFrame` | no | The widget instance. |
| **arg** | `modelSceneID` | `number` | no | Scene database ID. |

---

### C_ModelInfo.AddActiveModelSceneActor

Registers an actor within an active model scene. **Does nothing in public
clients.**

```lua
C_ModelInfo.AddActiveModelSceneActor(modelSceneFrameActor, modelSceneActorID)
```

| Direction | Name | Type | Nilable | Description |
|-----------|------|------|---------|-------------|
| **arg** | `modelSceneFrameActor` | `ModelSceneFrameActor` | no | The actor instance. |
| **arg** | `modelSceneActorID` | `number` | no | Actor database ID. |

---

### C_ModelInfo.ClearActiveModelScene

Unregisters a ModelScene from the active set. **Does nothing in public
clients.**

```lua
C_ModelInfo.ClearActiveModelScene(modelSceneFrame)
```

| Direction | Name | Type | Nilable | Description |
|-----------|------|------|---------|-------------|
| **arg** | `modelSceneFrame` | `ModelSceneFrame` | no | The widget instance. |

---

### C_ModelInfo.ClearActiveModelSceneActor

Unregisters an actor from the active set. **Does nothing in public clients.**

```lua
C_ModelInfo.ClearActiveModelSceneActor(modelSceneFrameActor)
```

| Direction | Name | Type | Nilable | Description |
|-----------|------|------|---------|-------------|
| **arg** | `modelSceneFrameActor` | `ModelSceneFrameActor` | no | The actor instance. |

---

## Events

### UI_MODEL_SCENE_INFO_UPDATED

Fires when model scene database entries are refreshed (e.g. after a hotfix
push). This is a unique event — only one instance fires per batch of updates.

```lua
-- Register:
local f = CreateFrame("Frame")
f:RegisterEvent("UI_MODEL_SCENE_INFO_UPDATED")
f:SetScript("OnEvent", function(self, event)
    -- Re-query any cached C_ModelInfo data here
end)
```

---

## Enumerations

### Enum.ModelSceneType

Categorises the purpose of a scene definition. Returned by
`GetModelSceneInfoByID`.

| Value | Name | Description |
|------:|------|-------------|
| 0 | `MountJournal` | Mount Journal preview scene. |
| 1 | `PetJournalCard` | Pet Journal card preview. |
| 2 | `ShopCard` | In-game shop card scene. |
| 3 | `EncounterJournal` | Encounter/Dungeon Journal boss preview. |
| 4 | `PetJournalLoadout` | Pet Journal loadout slot preview. |
| 5 | `ArtifactTier2` | Legion Artifact Tier 2 display. |
| 6 | `ArtifactTier2ForgingScene` | Artifact Tier 2 forging animation. |
| 7 | `ArtifactTier2SlamEffect` | Artifact Tier 2 slam visual effect. |
| 8 | `CommentatorVictoryFanfare` | PvP Commentator victory scene. |
| 9 | `ArtifactRelicTalentEffect` | Artifact relic talent visual. |
| 10 | `PvPWarModeOrb` | War Mode toggle orb scene. |
| 11 | `PvPWarModeFire` | War Mode fire effect scene. |
| 12 | `PartyPose` | Party Pose (end-of-dungeon) scene. |
| 13 | `AzeriteItemLevelUpToast` | Azerite item level-up toast scene. |
| 14 | `AzeritePowers` | Heart of Azeroth powers UI scene. |
| 15 | `AzeriteRewardGlow` | Azerite reward glow effect scene. |
| 16 | `HeartOfAzeroth` | Heart of Azeroth necklace scene. |
| 17 | `WorldMapThreat` | World map N'Zoth threat eye scene. |
| 18 | `Soulbinds` | Shadowlands Soulbinds scene. |
| 19 | `JailersTowerAnimaGlow` | Torghast anima glow scene. |

### Enum.ModelSceneSetting

Bitmask flags for camera settings. Used in the `flags` field of
`UIModelSceneCameraInfo`.

| Value | Name | Description |
|------:|------|-------------|
| 1 | `AlignLightToOrbitDelta` | Scene lighting rotates to follow camera orbit changes. |

---

## Typical usage flow

The standard Blizzard pattern (used in `ModelSceneMixin:SetFromModelSceneID`)
is:

```lua
-- 1. Query the scene definition
local sceneType, cameraIDs, actorIDs, flags = C_ModelInfo.GetModelSceneInfoByID(sceneID)
if not sceneType then return end

-- 2. Set up cameras
for _, camID in ipairs(cameraIDs) do
    local camInfo = C_ModelInfo.GetModelSceneCameraInfoByID(camID)
    if camInfo then
        -- Apply camInfo fields to the scene's camera
    end
end

-- 3. Set up actors
for _, actorID in ipairs(actorIDs) do
    local actorInfo = C_ModelInfo.GetModelSceneActorInfoByID(actorID)
    if actorInfo then
        -- Position the actor using actorInfo fields
        if actorInfo.modelActorDisplayID then
            local display = C_ModelInfo.GetModelSceneActorDisplayInfoByID(actorInfo.modelActorDisplayID)
            -- Apply animation, alpha, scale from display info
        end
    end
end
```

---

## Relationship to ModelScene widget

`C_ModelInfo` is a **data-only** API. It reads pre-authored records from the
game database but does not create or manipulate widgets. The actual rendering is
done through:

- `ModelScene` — the frame widget that hosts the 3D viewport.
- `ModelSceneActor` — individual 3D actors within the scene.
- `ModelSceneMixin` / `ModelSceneActorMixin` — Blizzard FrameXML mixins that
  consume `C_ModelInfo` data via `SetFromModelSceneID()`.

For the addon's own ModelScene renderer API (which wraps these lower-level
widgets), see [ModelScene.md](ModelScene.md).
