# Canonical Pose Framing — Design Document

## Problem Statement

`FrameFullBodyFront_Immediate()` and all downstream framing code samples
`GetActiveBoundingBox()` live on every call. During talk/wave/bow animations
the AABB shifts — arms extend, body tilts, head nods — causing the camera to
drift because the target Z, visible height, and shoulder-width all change
frame-to-frame. The 87.5%/25%/60% heuristics only work for idle humanoids.

**Goal:** Sample the bounding box once in a stable "canonical" idle pose,
cache it per displayID, derive body regions from that fixed reference, and
only use live bbox for one-time calibration and rare re-validation. Camera
computations become deterministic regardless of animation state.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Existing modules (unchanged API)                 │
│  ModelFrame.lua  ──▶  ModelHost.lua  ──▶  HostCamera.lua               │
│       │                    │                                            │
│       ▼                    ▼                                            │
│  StateMachine.lua    ModelSceneHost.lua  (Attach, SetDisplayInfo, …)    │
│                            │                                            │
│                 ┌──────────┴───────────────────────────┐                │
│                 │       NEW / MODIFIED LAYER            │                │
│                 │                                       │                │
│                 │  ┌──────────────────────────────────┐ │                │
│                 │  │  CanonicalBbox.lua  (NEW)        │ │                │
│                 │  │  ● SampleCanonical(actor, cb)    │ │                │
│                 │  │  ● GetCached(displayID) → bbox   │ │                │
│                 │  │  ● Invalidate(displayID)         │ │                │
│                 │  │  ● _cache[displayID] = {…}       │ │                │
│                 │  └──────────┬───────────────────────┘ │                │
│                 │             │                          │                │
│                 │  ┌──────────▼───────────────────────┐ │                │
│                 │  │  BodyRegions.lua  (NEW)          │ │                │
│                 │  │  ● Classify(canonBbox) → class   │ │                │
│                 │  │  ● GetRegion(class, name) → {…}  │ │                │
│                 │  │  ● "bust", "head", "full", …     │ │                │
│                 │  └──────────┬───────────────────────┘ │                │
│                 │             │                          │                │
│                 │  ┌──────────▼───────────────────────┐ │                │
│                 │  │  ProjectionVerifier.lua  (NEW)   │ │                │
│                 │  │  ● Verify(scene,region,cam) →ok  │ │                │
│                 │  │  ● RefineDistance(scene,…) → d   │ │                │
│                 │  │  ● Uses Project3DPointTo2D       │ │                │
│                 │  └──────────────────────────────────┘ │                │
│                 │                                       │                │
│                 │  Framing.lua  (MODIFIED)              │                │
│                 │  ● FrameRegion(host, regionName)      │                │
│                 │  ● (replaces direct heuristic math)   │                │
│                 │                                       │                │
│                 └───────────────────────────────────────┘                │
│                                                                         │
│  ModelSceneHost.lua  (MODIFIED entry points)                            │
│  ● FrameFullBodyFront_Immediate → delegates to FrameRegion("bust")     │
│  ● _RequestAutoFrame → samples canonical bbox first                    │
│  ● SetDisplayInfo/SetUnit → invalidates + triggers canonical sample    │
│  ● GetBounds() → unchanged (still returns live bbox for diagnostics)   │
│                                                                         │
│  FramerScene.lua  (MODIFIED)                                            │
│  ● FitDefault/ShowUpper read canonical bbox instead of live             │
│                                                                         │
│  ModelFrame.lua  (MODIFIED)                                             │
│  ● BuildModelMetadataOnce → stores canonical bbox in meta              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Canonical Bbox Strategy

### 1.1 When to Sample

The canonical bbox is sampled **exactly once per displayID**, during the idle
animation (animID 0), after the model reports `IsLoaded() == true` and the
AABB has stabilized (2 consecutive identical readings 50 ms apart).

**Sampling sequence:**

```
SetDisplayInfo(displayID)
  └─▶ _BumpModelVersion()
  └─▶ Loader.loadByDisplayID(actor, displayID, …)
         └─▶ onLoaded callback
               └─▶ actor:SetAnimation(0)          -- force idle
               └─▶ C_Timer.After(0.05, …)         -- let one frame render
               └─▶ CanonicalBbox.SampleCanonical(actor, displayID, function(bbox)
                       -- bbox is now the stable idle AABB
                       -- store in cache and meta
                       -- THEN trigger FrameRegion("bust")
                   end)
```

### 1.2 Race Handling

The existing `_RequestAutoFrame` polls with `scheduleNext(0.05)` and checks
`IsLoaded()` + bbox signature stability. `CanonicalBbox.SampleCanonical`
follows the same pattern but is a **dedicated path** that:

1. Forces anim 0 (idle)
2. Waits for `IsLoaded() == true`
3. Takes up to 3 bbox readings 50 ms apart; requires 2 identical readings
4. Restores the previously-desired animation (via `AnimationController`)
5. Calls back with the canonical bbox

If the model version changes (`_BumpModelVersion`) during sampling, the
callback is silently discarded (stale guard, same pattern as existing code).

### 1.3 Cache Invalidation

```lua
_canonicalCache[displayID] = {
    bbox     = { min={…}, max={…}, center={…}, size={…} },
    sampledAt = GetTime(),
    modelVer  = host._modelVersion,
}
```

**Invalidated when:**
- `SetDisplayInfo(newID)` with `newID ~= currentID`
- `SetUnit(unit)` (always, since unit appearance can change)
- Explicit `CanonicalBbox.Invalidate(displayID)` for debug/editor

**NOT invalidated when:**
- Animation changes (the whole point)
- Camera moves, zoom, pan
- Frame resize (only distance is refit)

### 1.4 Animated Bbox Divergence (>30%)

After canonical sampling, the system does a single "divergence check" once
the model enters its first non-idle animation:

```lua
local liveH = liveBbox.size.z
local canonH = canonBbox.size.z
local drift = math.abs(liveH - canonH) / math.max(canonH, 0.01)
if drift > 0.30 then
    -- Model's animated pose is dramatically different (e.g., dragon rearing)
    -- Blend: expand canonical by 50% of the delta to add headroom
    canonBbox.size.z = canonH + (liveH - canonH) * 0.5
    -- Recompute center Z
    canonBbox.center.z = canonBbox.min.z + canonBbox.size.z * 0.5
    -- Mark as "expanded" to avoid re-applying
    canonBbox._expanded = true
end
```

This runs once per session per displayID, not per frame.

---

## 2. Body Region Mapping

### 2.1 Morphology Classifier

Without bone access, we classify by **aspect ratio** (width/height) and
**absolute height** of the canonical bbox:

```lua
function BodyRegions.Classify(canonBbox)
    local w = canonBbox.size.x   -- lateral width
    local h = canonBbox.size.z   -- vertical height
    local d = canonBbox.size.y   -- depth
    local ar = w / math.max(h, 0.01)

    if h < 0.5 then
        return "tiny_critter"       -- rabbits, squirrels, rats
    elseif ar > 1.8 then
        return "wide_beast"         -- kodo, elekk, boar
    elseif ar > 1.2 and h > 2.0 then
        return "dragon"             -- dragons, proto-drakes
    elseif ar > 0.8 then
        return "stocky_humanoid"    -- dwarves, goblins, pandaren
    else
        return "tall_humanoid"      -- humans, elves, draenei, undead
    end
end
```

### 2.2 Region Definitions (Z percentage ranges, 0=feet 1=top)

```
┌─────────────────────────────────────────────────────────────────┐
│ Class            │ bust target │ bust range │ shoulder W factor │
├──────────────────┼─────────────┼────────────┼───────────────────┤
│ tall_humanoid    │ z=87.5%     │ 75%–100%   │ 0.55              │
│ stocky_humanoid  │ z=85%       │ 70%–100%   │ 0.65              │
│ wide_beast       │ z=75%       │ 50%–100%   │ 0.80              │
│ dragon           │ z=80%       │ 55%–100%   │ 0.70              │
│ tiny_critter     │ z=50%       │ 0%–100%    │ 1.00 (full body)  │
└─────────────────────────────────────────────────────────────────┘
```

Each named region is a table:

```lua
-- Example: tall_humanoid regions
REGIONS["tall_humanoid"] = {
    bust = {
        targetPct  = 0.875,   -- camera looks at this Z%
        rangeLo    = 0.75,    -- bottom of visible slice
        rangeHi    = 1.00,    -- top of visible slice
        shoulderW  = 0.55,    -- fraction of bbox width to fit horizontally
    },
    head = {
        targetPct  = 0.925,
        rangeLo    = 0.85,
        rangeHi    = 1.00,
        shoulderW  = 0.40,
    },
    upper_body = {
        targetPct  = 0.70,
        rangeLo    = 0.45,
        rangeHi    = 1.00,
        shoulderW  = 0.65,
    },
    full_body = {
        targetPct  = 0.50,
        rangeLo    = 0.00,
        rangeHi    = 1.00,
        shoulderW  = 1.00,
    },
}
```

### 2.3 Converting Regions to World Coordinates

```lua
function BodyRegions.ToWorldCoords(canonBbox, region)
    local minZ  = canonBbox.min.z
    local height = canonBbox.size.z
    local cx    = canonBbox.center.x
    local cy    = canonBbox.center.y

    local targetZ   = minZ + height * region.targetPct
    local visibleLo = minZ + height * region.rangeLo
    local visibleHi = minZ + height * region.rangeHi
    local visibleH  = visibleHi - visibleLo
    local fitWidth  = canonBbox.size.x * region.shoulderW

    return {
        targetX   = cx,
        targetY   = cy,
        targetZ   = targetZ,
        visibleH  = visibleH,
        fitWidth  = fitWidth,
        visibleLo = visibleLo,
        visibleHi = visibleHi,
    }
end
```

---

## 3. Projection Verification Loop

After the initial camera placement (distance from FOV math), verify the
actual 2D projection covers the target region correctly.

### 3.1 Target Coverage Definition

"Well-framed" = the projected 2D bounding rect of the target region fills
**70–85%** of the viewport in the dominant axis (usually vertical).

### 3.2 Algorithm

```lua
function ProjectionVerifier.Verify(scene, worldRegion, frameW, frameH)
    -- Sample 4 corners of the target region sub-AABB
    local points = {
        { worldRegion.targetX - worldRegion.fitWidth*0.5, worldRegion.targetY, worldRegion.visibleLo },
        { worldRegion.targetX + worldRegion.fitWidth*0.5, worldRegion.targetY, worldRegion.visibleLo },
        { worldRegion.targetX - worldRegion.fitWidth*0.5, worldRegion.targetY, worldRegion.visibleHi },
        { worldRegion.targetX + worldRegion.fitWidth*0.5, worldRegion.targetY, worldRegion.visibleHi },
    }

    local minPX, minPY = math.huge, math.huge
    local maxPX, maxPY = -math.huge, -math.huge
    local allOk = true

    for _, p in ipairs(points) do
        local ok, px, py = Diagnostics.projectPoint(scene, p[1], p[2], p[3])
        if not ok then allOk = false; break end
        if px < minPX then minPX = px end
        if px > maxPX then maxPX = px end
        if py < minPY then minPY = py end
        if py > maxPY then maxPY = py end
    end

    if not allOk then return false, 0, 0 end

    local projW = maxPX - minPX
    local projH = maxPY - minPY
    local coverageH = projH / math.max(frameH, 1)
    local coverageW = projW / math.max(frameW, 1)

    return true, coverageH, coverageW
end
```

### 3.3 Binary Search Refinement (max 3 iterations)

```lua
function ProjectionVerifier.RefineDistance(scene, host, worldRegion, initialDist, frameW, frameH)
    local TARGET_COVERAGE = 0.775  -- midpoint of 70–85%
    local TOLERANCE = 0.05         -- ±5% is acceptable
    local MAX_ITER = 3

    local dLo = initialDist * 0.3  -- never closer than 30% of initial
    local dHi = initialDist * 3.0  -- never further than 3× initial
    local dMid = initialDist

    for i = 1, MAX_ITER do
        -- Apply camera at dMid
        _tempApplyCamera(host, dMid, worldRegion)

        local ok, covH, covW = ProjectionVerifier.Verify(scene, worldRegion, frameW, frameH)
        if not ok then
            -- Projection failed; use initial distance as-is
            return initialDist
        end

        local coverage = math.max(covH, covW)  -- dominant axis

        if math.abs(coverage - TARGET_COVERAGE) < TOLERANCE then
            return dMid  -- good enough
        end

        if coverage > TARGET_COVERAGE then
            -- Too close → increase distance
            dLo = dMid
        else
            -- Too far → decrease distance
            dHi = dMid
        end
        dMid = (dLo + dHi) * 0.5
    end

    return dMid
end
```

---

## 4. Animation-Resistant Camera

### 4.1 Core Principle

All camera target coordinates (targetX, targetY, targetZ) and distance
computations use the **canonical bbox**, never the live bbox.

The live bbox is used ONLY for:
1. Initial canonical sampling (idle pose after load)
2. One-time divergence check on first animation
3. `_DumpState` diagnostic output

### 4.2 Smooth Transitions Between Regions

When switching from one region to another (e.g., "bust" → "full_body" for a
wave animation), use the existing `AnimPanTo` / `AnimZoomTo` system:

```lua
function host:TransitionToRegion(regionName, duration)
    local canonBbox = CanonicalBbox.GetCached(self._currentDisplayID)
    if not canonBbox then return self:FrameFullBodyFront_Immediate(0.12) end

    local class = BodyRegions.Classify(canonBbox)
    local region = BodyRegions.GetRegion(class, regionName)
    local world = BodyRegions.ToWorldCoords(canonBbox, region)

    local fov = self:GetFovV()
    local aspect = self:GetAspect()
    local dist = Framing.SolveDistance(fov, aspect, world.visibleH, world.fitWidth, 0.12)

    local dur = tonumber(duration) or 0.3
    -- Smooth pan to new target Z
    ReplayFrame:AnimPanTo(world.targetZ, dur)
    -- Smooth zoom to new distance
    ReplayFrame:AnimZoomTo(dist, dur)
end
```

### 4.3 Exponential Smoothing (τ ≈ 0.15s)

For any per-frame camera micro-adjustments (e.g., from the projection
verifier nudging distance after a resize), apply exponential smoothing:

```lua
-- In AnimUpdate (ModelAnimation.lua), after computing raw target:
local alpha = 1.0 - math.exp(-elapsed / 0.15)  -- τ = 0.15s at 60fps → α ≈ 0.10
currentValue = currentValue + (targetValue - currentValue) * alpha
```

This is NOT applied to the canonical bbox lookup (that's instant and stable),
only to runtime corrections from projection verification.

---

## 5. Key Data Structures

### 5.1 Canonical Bbox Cache Entry

```lua
-- CanonicalBbox._cache[displayID]
{
    bbox = {
        min    = { x = number, y = number, z = number },
        max    = { x = number, y = number, z = number },
        center = { x = number, y = number, z = number },
        size   = { x = number, y = number, z = number },  -- lateral, depth, height
    },
    class       = "tall_humanoid",   -- from BodyRegions.Classify
    sampledAt   = number,            -- GetTime() when sampled
    modelVer    = number,            -- host._modelVersion at sample time
    _expanded   = false,             -- true if divergence expansion applied
}
```

### 5.2 Body Region Record

```lua
{
    targetPct  = number,  -- 0..1, vertical center of camera focus
    rangeLo    = number,  -- 0..1, bottom of visible slice
    rangeHi    = number,  -- 0..1, top of visible slice
    shoulderW  = number,  -- 0..1, fraction of bbox width to fit
}
```

### 5.3 World Region (output of ToWorldCoords)

```lua
{
    targetX   = number,
    targetY   = number,
    targetZ   = number,
    visibleH  = number,
    fitWidth  = number,
    visibleLo = number,
    visibleHi = number,
}
```

---

## 6. Performance Budget

```
┌──────────────────────────────┬───────────────────────────────────────┐
│ Operation                    │ When it runs                          │
├──────────────────────────────┼───────────────────────────────────────┤
│ CanonicalBbox.SampleCanonical│ Once per displayID load (async,       │
│                              │ 2-4 timer ticks at 50ms)              │
├──────────────────────────────┼───────────────────────────────────────┤
│ BodyRegions.Classify         │ Once per displayID (cached alongside  │
│                              │ canonical bbox)                       │
├──────────────────────────────┼───────────────────────────────────────┤
│ BodyRegions.ToWorldCoords    │ On region change, frame, or resize    │
│                              │ (4 multiplies + 2 additions, trivial) │
├──────────────────────────────┼───────────────────────────────────────┤
│ Framing.SolveDistance        │ On region change or resize            │
│                              │ (2 tan() calls, < 1μs)               │
├──────────────────────────────┼───────────────────────────────────────┤
│ ProjectionVerifier.Verify    │ After each distance solve (4 calls to │
│                              │ Project3DPointTo2D; engine calls)     │
├──────────────────────────────┼───────────────────────────────────────┤
│ ProjectionVerifier.Refine    │ Max 3 iterations × Verify, only on    │
│                              │ first frame or resize, NOT per-frame  │
├──────────────────────────────┼───────────────────────────────────────┤
│ Exponential smoothing        │ Per-frame in AnimUpdate, but only     │
│                              │ when a correction is pending (2       │
│                              │ lerps, < 0.5μs)                      │
├──────────────────────────────┼───────────────────────────────────────┤
│ Live bbox divergence check   │ Once per displayID per session,       │
│                              │ on first non-idle animation           │
├──────────────────────────────┼───────────────────────────────────────┤
│ GetActiveBoundingBox (live)  │ NO LONGER called during framing;      │
│                              │ only during canonical sampling and    │
│                              │ diagnostic dumps                      │
└──────────────────────────────┴───────────────────────────────────────┘

Total per-frame cost: ~0.5μs (exponential lerp only, when active)
Total per-load cost:  ~150-250ms (canonical sampling async, non-blocking)
Total per-resize:     ~4 Project3DPointTo2D calls × 3 iterations max
```

---

## 7. Edge Case Handling Matrix

```
┌──────────────────────────────────┬────────────────────────────────────────┐
│ Edge Case                        │ Handling                               │
├──────────────────────────────────┼────────────────────────────────────────┤
│ Model not yet loaded             │ SampleCanonical waits via existing     │
│                                  │ IsLoaded() poll (same as Loader).      │
│                                  │ Falls back to PointCameraAtHead if     │
│                                  │ timeout (3s).                          │
├──────────────────────────────────┼────────────────────────────────────────┤
│ GetActiveBoundingBox returns nil │ Retry up to 20 ticks (1s). If still   │
│                                  │ nil, skip canonical cache and fall     │
│                                  │ back to live-bbox path (current code). │
├──────────────────────────────────┼────────────────────────────────────────┤
│ displayID changes mid-animation  │ _BumpModelVersion() invalidates the   │
│                                  │ in-flight SampleCanonical via version  │
│                                  │ guard. New load starts fresh.          │
├──────────────────────────────────┼────────────────────────────────────────┤
│ Same displayID re-loaded         │ Cache hit: skip sampling, go straight  │
│                                  │ to FrameRegion. Existing code already  │
│                                  │ detects duplicates (log only).         │
├──────────────────────────────────┼────────────────────────────────────────┤
│ Non-humanoid (dragon/beast)      │ Classify() returns "wide_beast" or    │
│                                  │ "dragon"; bust region has wider range  │
│                                  │ (50-100%) and larger shoulderW (0.70-  │
│                                  │ 0.80) to avoid cutting off wings.     │
├──────────────────────────────────┼────────────────────────────────────────┤
│ Tiny critter (rabbit, rat)       │ Classify → "tiny_critter"; region is  │
│                                  │ full body (0-100%). Camera pulls back  │
│                                  │ to show entire creature.              │
├──────────────────────────────────┼────────────────────────────────────────┤
│ Animated bbox >30% larger        │ One-time expansion blends canonical   │
│                                  │ toward animated by 50% of delta. Adds │
│                                  │ headroom without fully tracking the   │
│                                  │ animation. Only happens once.         │
├──────────────────────────────────┼────────────────────────────────────────┤
│ Animated bbox >30% smaller       │ Ignore: camera shows empty space      │
│                                  │ rather than cutting off model parts.  │
│                                  │ Shrinkage (e.g., crouch) is safe.     │
├──────────────────────────────────┼────────────────────────────────────────┤
│ Frame resize while animating     │ FitDistanceForCurrentTarget recomputes│
│                                  │ distance from canonical bbox (not     │
│                                  │ live). Projection verifier runs once. │
├──────────────────────────────────┼────────────────────────────────────────┤
│ PlayerModel backend (no scene)   │ CanonicalBbox + BodyRegions still     │
│                                  │ compute percentages. PlayerModel      │
│                                  │ renderer maps them to SetPortraitZoom │
│                                  │ + SetPosition(0,0,z) via existing     │
│                                  │ HostCamera shims. No projection       │
│                                  │ verification (no Project3DPointTo2D). │
├──────────────────────────────────┼────────────────────────────────────────┤
│ Project3DPointTo2D returns NaN   │ Diagnostics.projectPoint already      │
│                                  │ rejects NaN. RefineDistance returns    │
│                                  │ initialDist as safe fallback.         │
├──────────────────────────────────┼────────────────────────────────────────┤
│ Multiple rapid displayID changes │ Each SetDisplayInfo calls             │
│                                  │ _BumpModelVersion, canceling all      │
│                                  │ pending timers. Only the last one     │
│                                  │ wins. Existing pattern unchanged.     │
├──────────────────────────────────┼────────────────────────────────────────┤
│ advancedCameraFitting = false    │ When disabled, FramerScene delegates  │
│                                  │ are not attached (existing check in   │
│                                  │ HostCamera.Attach). The system falls  │
│                                  │ back to current code path entirely.   │
│                                  │ Zero risk of regression.              │
└──────────────────────────────────┴────────────────────────────────────────┘
```

---

## 8. Integration Plan: What to Modify vs Create

### 8.1 New Files

| File | Purpose |
|------|---------|
| `Renderers/ModelScene/CanonicalBbox.lua` | Sampling, caching, invalidation of idle-pose AABB |
| `Renderers/ModelScene/BodyRegions.lua` | Morphology classifier + region table lookups |
| `Renderers/ModelScene/ProjectionVerifier.lua` | Project3DPointTo2D verification + binary search refinement |

All three are pure-ish modules under the `NS = ReplayFrame.ModelScene` namespace,
following the existing pattern (see Utils.lua, Diagnostics.lua, etc.).

### 8.2 Modified Files

| File | Changes |
|------|---------|
| **ModelSceneHost.lua** | `FrameFullBodyFront_Immediate`: read canonical bbox instead of live `GetBounds()`. `_RequestAutoFrame`: after model loads, call `CanonicalBbox.SampleCanonical` before framing. `SetDisplayInfo`/`SetUnit`: call `CanonicalBbox.Invalidate`. Add `TransitionToRegion(name, dur)` public method. |
| **Framing.lua** | Add `FrameRegion(host, canonBbox, regionName, paddingFrac)` — the unified entry point that replaces the inline math in `FrameFullBodyFront_Immediate`. Existing `solveAxis`/`FOVPair_FromF` stay. |
| **FramerScene.lua** | `FitDefault`/`ShowUpper`: call `CanonicalBbox.GetCached` then `BodyRegions.ToWorldCoords` instead of live bbox math. |
| **ModelFrame.lua** | `BuildModelMetadataOnce`: store canonical bbox in meta alongside live bbox. Minor: call `CanonicalBbox.SampleCanonical` if not already cached. |
| **ChattyLittleNpc.toc** | Add three new files after `Framing.lua` in load order. |

### 8.3 Unchanged Files

- `Loader.lua` — model loading unchanged; canonical sampling hooks into the existing `onLoaded` callback
- `Stabilizer.lua` — animation blending unchanged
- `CameraController.lua` — orientation math unchanged
- `AnimationController.lua` — animation intent tracking unchanged
- `Diagnostics.lua` — projectPoint/coverageStats already exist, reused as-is
- `ModelHost.lua` — backend factory unchanged
- `HostCamera.lua` — shim layer unchanged
- `ModelAnimation.lua` — AnimPanTo/AnimZoomTo unchanged (smoothing added alongside)
- `PlayerModelRenderer.lua` — no ProjectionVerifier support, graceful degradation via existing HostCamera shims

---

## 9. Migration Path

### Phase 1: Add Infrastructure (non-breaking)

1. Create `CanonicalBbox.lua`, `BodyRegions.lua`, `ProjectionVerifier.lua`
2. Add to `.toc` after `Framing.lua`
3. Wire `CanonicalBbox.SampleCanonical` into `SetDisplayInfo`'s post-load callback
4. No behavioral change yet; canonical bbox is sampled but not consumed

### Phase 2: Switch Framing to Canonical (behind feature gate)

5. In `FrameFullBodyFront_Immediate`, check `CanonicalBbox.GetCached(displayID)`:
   - If cached → use canonical bbox + `BodyRegions.ToWorldCoords`
   - If not cached → fall through to current live-bbox path (backward compat)
6. Gate behind existing `advancedCameraFitting` profile flag for safe rollout
7. Update `FramerScene.FitDefault`/`ShowUpper` similarly

### Phase 3: Add Projection Verification

8. After distance solve, call `ProjectionVerifier.RefineDistance` (max 3 iterations)
9. Only for ModelScene backend (PlayerModel has no projection API)

### Phase 4: Region Transitions

10. Add `TransitionToRegion` to `ModelSceneHost`
11. Wire into `StateMachine` state transitions:
    - `idle` → bust (default)
    - `wave` → upper_body (show arm motion)
    - `bow`  → upper_body
    - `talk` → bust (stable)

### Phase 5: Remove Dead Code

12. Once validated, remove the inline 87.5%/25%/60% heuristics from
    `FrameFullBodyFront_Immediate` and `FramerScene.FitDefault`/`ShowUpper`
13. The live-bbox fallback path stays forever (for uncached models)

---

## 10. Algorithm Pseudocode: Complete Flow

```
─── On SetDisplayInfo(displayID) ───────────────────────────────────────
1. _BumpModelVersion()
2. CanonicalBbox.Invalidate(displayID) if displayID changed
3. Loader.loadByDisplayID(actor, displayID, {respectAnimationIntent=true})
4. OnLoaded:
   a. actor:SetAnimation(0)     -- force idle for sampling
   b. CanonicalBbox.SampleCanonical(actor, displayID, callback):
      i.   Wait 50ms
      ii.  Read bbox = actor:GetActiveBoundingBox()
      iii. Compare with previous reading
      iv.  If stable (2 identical) → cache bbox, call callback(bbox)
      v.   If not stable after 20 ticks → use last reading as best-effort
      vi.  Restore desired animation from AnimationController
   c. callback(canonBbox):
      i.   class = BodyRegions.Classify(canonBbox)
      ii.  Cache class alongside bbox
      iii. Store in meta via SetModelMeta
      iv.  FrameRegion("bust", 0.12)

─── FrameRegion(regionName, paddingFrac) ──────────────────────────────
1. canonBbox = CanonicalBbox.GetCached(displayID)
   If nil → fallback to FrameFullBodyFront_Immediate (current code)
2. class = canonBbox.class or BodyRegions.Classify(canonBbox.bbox)
3. region = BodyRegions.GetRegion(class, regionName)
4. world = BodyRegions.ToWorldCoords(canonBbox.bbox, region)
5. fov = host:GetFovV(), aspect = host:GetAspect()
6. dist = Framing.SolveDistance(fov, aspect, world.visibleH, world.fitWidth, paddingFrac)
7. Apply camera: _ApplyCameraLookAt(world.targetX, world.targetY + dist, world.targetZ,
                                     world.targetX, world.targetY, world.targetZ)
8. _UpdateClipPlanesForFit(dist, canonBbox.bbox, paddingFrac)
9. actor:SetYaw(host._frontYaw)
10. _UpdateSnapshot({tx, ty, tz, px, py, pz, dist})
11. If ProjectionVerifier available:
    a. refinedDist = ProjectionVerifier.RefineDistance(scene, host, world, dist, frameW, frameH)
    b. If |refinedDist - dist| > 0.05:
       Apply smoothed correction via exponential smoothing (τ=0.15s)

─── On Animation Change (talk/wave/bow) ───────────────────────────────
1. Camera target: UNCHANGED (uses canonical bbox)
2. If this is first non-idle animation for this displayID:
   a. Read live bbox
   b. Compare with canonical → divergence check
   c. If >30% larger → expand canonical once
   d. Re-run FrameRegion if expanded
3. If wave/bow → TransitionToRegion("upper_body", 0.3)
4. If talk → ensure bust region (no transition if already there)

─── On Frame Resize ───────────────────────────────────────────────────
1. Read canonical bbox (NOT live)
2. Recompute distance for current region at new aspect ratio
3. Apply via FitDistanceForCurrentTarget (already exists)
4. Optional: ProjectionVerifier.Verify once to validate
```

---

## 11. File Stubs

### CanonicalBbox.lua

```lua
local CLN = _G.ChattyLittleNpc
local NS = CLN.ReplayFrame.ModelScene
NS.CanonicalBbox = NS.CanonicalBbox or {}
local CB = NS.CanonicalBbox

CB._cache = {}

function CB.SampleCanonical(actor, displayID, modelVersion, callback)
    -- Force idle, poll bbox stability, invoke callback(bbox)
end

function CB.GetCached(displayID)
    return CB._cache[tonumber(displayID)]
end

function CB.Invalidate(displayID)
    CB._cache[tonumber(displayID)] = nil
end
```

### BodyRegions.lua

```lua
local CLN = _G.ChattyLittleNpc
local NS = CLN.ReplayFrame.ModelScene
NS.BodyRegions = NS.BodyRegions or {}
local BR = NS.BodyRegions

BR.REGIONS = { --[[ tall_humanoid, stocky_humanoid, wide_beast, dragon, tiny_critter ]] }

function BR.Classify(canonBbox) end
function BR.GetRegion(class, regionName) end
function BR.ToWorldCoords(canonBbox, region) end
```

### ProjectionVerifier.lua

```lua
local CLN = _G.ChattyLittleNpc
local NS = CLN.ReplayFrame.ModelScene
NS.ProjectionVerifier = NS.ProjectionVerifier or {}
local PV = NS.ProjectionVerifier

function PV.Verify(scene, worldRegion, frameW, frameH) end
function PV.RefineDistance(scene, host, worldRegion, initialDist, frameW, frameH) end
```

---

## 12. .toc Load Order

```diff
 src/ReplayFrame/Renderers/ModelScene/CameraController.lua
 src/ReplayFrame/Renderers/ModelScene/Framing.lua
+src/ReplayFrame/Renderers/ModelScene/CanonicalBbox.lua
+src/ReplayFrame/Renderers/ModelScene/BodyRegions.lua
+src/ReplayFrame/Renderers/ModelScene/ProjectionVerifier.lua
 src/ReplayFrame/Renderers/ModelSceneHost.lua
```

New files load after Framing.lua (they reference NS.Framing and
NS.Diagnostics) but before ModelSceneHost.lua (which consumes them).
