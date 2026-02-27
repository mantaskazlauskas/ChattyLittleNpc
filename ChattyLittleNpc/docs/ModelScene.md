# ModelScene renderer overview

This addon uses Blizzard's ModelScene widget (with a single ModelSceneActor) as a 3D renderer for the Replay Frame. The renderer focuses on being simple and reliable:

- One ModelScene, one actor.
- Orbit camera (distance, yaw, pitch) that always “looks at” a target point.
- Actor origin centered; yaw-only rotation for predictable facing.
- Bounds-first framing (uses engine bounding boxes) without custom projection math.

No third‑party libraries are required; we rely on Blizzard mixins and APIs.


## Key concepts

- Coordinate system: +Z is up. The camera “forward” is derived from yaw/pitch. Actor yaw is around +Z.
- Actor origin: we use SetUseCenterForOrigin so the actor rotates about its center.
- FOV/aspect: we read the scene’s vertical FOV and current widget aspect ratio to compute camera distances.
- Near/far clips: near scales with distance; far leaves safety headroom to avoid clipping while keeping z-precision.
- Lighting: a neutral, soft baseline is applied (ambient + low diffuse, directional from above/front). Further tuning hooks may be available.


## Public API (host methods)

These methods are attached to the host frame when the ModelScene backend is active. Unless noted, arguments are numbers (radians for angles).

- Camera and target
  - SetCamera(distance, yaw, pitch) — orbit camera parameters and apply.
  - SetTarget({ x, y, z }) — world-space target point the camera looks at.
  - GetFovV() — vertical FOV (radians).
  - GetAspect() — current width/height.

- Bounds
  - GetBounds() — { min = {x,y,z}, max = {x,y,z} } using, in order: GetActiveBoundingBox → GetMaxBoundingBox → GetModelBounds.

- Actor control
  - ClearModel()
  - SetDisplayInfo(displayID) — sets creature display by ID.
  - SetUnit(unit) — sets model from a unit (player/NPC) if available.
  - SetAnimation(animId); GetAnimation()
  - SetPaused(boolean)
  - GetActorScale(); SetActorScale(scale)
  - GetActorYaw(); SetActorYaw(yaw)
  - RotateBy(degrees) — convenience; adds to yaw.
  - FlipFacing() — rotates yaw by 180°.

- Framing helpers
  - FitDefault(padding) — frame full body using bounds + FOV; small headroom bias.
  - ShowUpper(heightFrac, padding) — frame upper portion (e.g., 0.7 for “torso and up”).
  - ZoomToHeightFactor(factor) — zoom relative to default height framing.
  - PointCameraAtHead() — nudges target toward head region.

- Presets & lifecycle
  - ApplyPreset(name) — dispatches to ReplayFrame.ScenePresets[name] if present; falls back to FitDefault.
  - OnModelLoadedOnce(callback) — runs callback when actor model reports loaded (with a short timeout fallback).

Note: Some builds may expose additional lighting helpers (SetLightVisible, SetLightDiffuse, SetLightAmbient, SetLightDirection, SetLightIntensity, SetLightPreset, SetActorDesaturated). These are optional and safe to no-op when unavailable.


## Camera model

We keep a simple orbit camera around the target:

- distance ≥ 0.1
- yaw around +Z (face left/right)
- pitch around local X (tilt up/down)
- look-at is set via axis vectors when available; otherwise by position + target.

Fitting computes the distance needed so the actor’s height or width fits inside the FOV rectangle:

- vfov = GetFovV(); hfov derived from vfov and aspect.
- distance = max(height/2 / tan(vfov/2), width/2 / tan(hfov/2)) with a padding factor.


## Best practices used

- Prefer engine bounds: Active → Max → ModelBounds.
- Center origin; rotate actor by yaw only for consistency across humanoids.
- Keep camera math minimal; avoid custom projective math except for optional diagnostics.
- Re-apply camera on OnSizeChanged; keep clips proportional to distance.
- After SetDisplayInfo/SetUnit, use OnModelLoadedOnce to trigger a FitDefault.


## Common flows

- Display a creature by display ID:
  1) SetDisplayInfo(id)
  2) OnModelLoadedOnce(function(host) host:FitDefault(0.1) end)

- Show upper body portrait:
  1) SetDisplayInfo(id)
  2) OnModelLoadedOnce(function(host) host:ShowUpper(0.7, 0.1) end)

- Rotate slowly during playback: call RotateBy(deltaDegrees) periodically; the camera stays fixed.


## Edge cases and tips

- Missing/zero bounds: some models report incomplete bounds; FitDefault falls back gracefully but framing may be conservative.
- Animation-dependent bounds: ActiveBoundingBox changes with animations; brief pops are possible when switching animations immediately after load.
- Units vs display IDs: SetModelByUnit may apply equipment; not all units are available out of combat or in every scene.
- Angles: yaw/pitch use radians; RotateBy takes degrees for convenience.
- Aspect changes: resizing the frame changes aspect; camera is re-applied automatically.


## References (Blizzard APIs)

- Widget: ModelScene, ModelSceneActorBase
- Actor bounds: GetActiveBoundingBox, GetMaxBoundingBox, GetModelBounds
- Scene helpers: SetCameraFieldOfView, Project3DPointTo2D (diagnostics), camera clips
- Data: C_ModelInfo (camera/actor/display info) — see [C_ModelInfo.md](C_ModelInfo.md) for full API reference
