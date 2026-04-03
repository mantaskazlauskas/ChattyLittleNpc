---
name: edit-mode
description: "WoW Edit Mode API reference and addon integration guide for Midnight (12.0.1). C_EditMode functions, EditModeManagerFrame, EditModeSystemMixin, data structures, Enum.EditModeSystem (24 values), grid/snap/magnet, community libraries (EditModeExpanded, LibEditModeOverride, LibEQOL, LibEditMode), per-layout persistence, overlay/highlight systems, taint/combat rules, layout import/export, 200+ Blizzard FrameXML function signatures, real addon integration analysis (Bartender4, ElvUI), and ChattyLittleNpc-specific patterns. Activates for: Edit Mode, EditMode, C_EditMode, layout, EditModeManagerFrame, per-layout, frame positioning, edit mode integration, overlay, EditModeSystemMixin, grid snap, magnet, settings dialog, layout macro, EditModeExpanded, LibEditModeOverride."
---

# WoW Edit Mode API — Midnight (Patch 12.0.1)

> Comprehensive reference for WoW Edit Mode addon integration.
> Current for Midnight (Patch 12.0.1, Interface 120001).
> Includes Blizzard FrameXML source analysis and real addon case studies.

## Quick Reference

| File | Content |
|------|---------|
| [01-api-reference.md](./01-api-reference.md) | C_EditMode functions (11), event, data structures, all 24 Enum.EditModeSystem values, setting IDs, taint rules |
| [02-integration-patterns.md](./02-integration-patterns.md) | Hooks, active layout detection, per-layout persistence, overlay/drag/resize, import/export, community libraries, combat lockdown, ChattyLittleNpc reference, anti-patterns table |
| [03-interactions-addon-support.md](./03-interactions-addon-support.md) | EditModeManagerFrame methods, EditModeSystemMixin lifecycle, grid/snap/magnet, complete LibEditModeOverride API, EditModeExpanded registration, settings dialog, unsaved changes dialog, layout macros, addon support matrix |
| [04-blizzard-source-reference.md](./04-blizzard-source-reference.md) | **200+ function signatures** from Blizzard FrameXML — EditModeSystemMixin (60+ methods), 15 system-specific mixins, EditModeMagnetismManager snap algorithm, complete per-system settings metadata |
| [05-addon-examples.md](./05-addon-examples.md) | Real addon analysis — EditModeExpanded (full public API, hook architecture, per-layout profiles), LibEditMode (callback API, lifecycle events), Bartender4 (EventRegistry, PurgeKey, UIHider), ElvUI (bypass pattern), 7 reusable patterns |
| [06-brainstorm-results.md](./06-brainstorm-results.md) | Plus Ultra brainstorm — 34 ideas from 3 model families, 19 scored by 3 critics, 8 recommended features with implementation paths, phased roadmap |

---

## Overview

Edit Mode (introduced in Dragonflight 10.0) lets players reposition, resize, and configure built-in UI elements. Addons integrate through three approaches:

### Detecting Edit Mode State Changes

```lua
-- Approach A: EventRegistry callbacks (cleanest, used by Bartender4)
EventRegistry:RegisterCallback("EditMode.Enter", onEnter)
EventRegistry:RegisterCallback("EditMode.Exit", onExit)

-- Approach B: HookScript on manager frame (used by LibEditMode)
EditModeManagerFrame:HookScript("OnShow", onEnter)
EditModeManagerFrame:HookScript("OnHide", onExit)

-- Approach C: hooksecurefunc (used by EditModeExpanded, ChattyLittleNpc)
hooksecurefunc(EditModeManagerFrame, "EnterEditMode", onEnter)
hooksecurefunc(EditModeManagerFrame, "ExitEditMode", onExit)
```

### Integration Steps

1. **Detect** Edit Mode enter/exit (see above)
2. **Listen** to `EDIT_MODE_LAYOUTS_UPDATED` for layout switches/saves
3. **Query** `C_EditMode.GetLayouts()` to identify the active layout
4. **Persist** per-layout settings in addon saved variables (keyed by layout name)
5. **Display** overlay/highlight UI during Edit Mode for frame manipulation

### Key Constraints

- **Enter/exit detection** — no dedicated event; use EventRegistry callbacks, HookScript, or hooksecurefunc (see above)
- **Taint risk** — most `C_EditMode` write functions require untainted execution (`SecretArguments = "AllowedWhenUntainted"`)
- **Combat lockdown** — frame repositioning blocked during combat (`InCombatLockdown()`)
- **Hidden base layouts** — `GetLayouts()` excludes 2 built-in presets (Modern, Classic); `activeLayout` index includes them, so subtract 2 or scan by name
- **Classic versions** — Classic Era, Wrath, and TBC have **no Edit Mode API**; addons targeting these need a fallback positioning interface
- **Non-combat addons** (like ChattyLittleNpc) are safe from Midnight's combat addon restrictions

### ChattyLittleNpc Status

The addon has **~70% Edit Mode integration** via `src/ReplayFrame/EditModeIntegration.lua` (1540 lines):
- ✅ Per-layout persistence (frameScale, queueTextScale, frameSize, npcModelFrameHeight, framePos)
- ✅ Overlay with drag/resize and grid snapping
- ✅ Keyboard arrow nudging (1px/5px/20px)
- ✅ Import/export bundles (Blizzard layout string + Base64 addon data)
- ✅ Layout manager UI with apply/delete/reset
- ✅ Sample data injection for Edit Mode preview
- ✅ Combat-aware persistence deferral
- See [06-brainstorm-results.md](./06-brainstorm-results.md) for recommended next steps
