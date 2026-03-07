---
name: edit-mode
description: "Complete WoW Edit Mode API reference and integration guide for Midnight (Patch 12.0.1). Covers C_EditMode namespace (all 11 functions), EDIT_MODE_LAYOUTS_UPDATED event, EditModeManagerFrame methods (SelectLayout, SaveLayoutChanges, RevertAllChanges, HasActiveChanges, SelectSystem, ClearSelectedSystem), EditModeSystemMixin lifecycle (OnEditModeEnter, OnEditModeExit, SetIsSelected, SetupEditModeForSystem), data structures (EditModeLayouts, EditModeSystemInfo, EditModeAnchorInfo), all 24 Enum.EditModeSystem values, layout types, grid/snap/magnet system, EditModeAccountSetting, EditModeSettingDisplayInfoManager, EditModeSystemSettingsDialog, EditModeUnsavedChangesDialog, community libraries (EditModeExpanded, LibEditModeOverride, LibEQOL, LibEditMode, FerrozEditModeLib), custom frame registration, per-layout persistence patterns, overlay/highlight systems, taint/combat considerations, layout import/export, layout macros, and ChattyLittleNpc-specific integration. Activates for: Edit Mode, EditMode, C_EditMode, layout, EditModeManagerFrame, per-layout settings, frame positioning, edit mode integration, edit mode overlay, EditModeSystemMixin, grid snap, magnet, settings dialog, layout macro."
---

# WoW Edit Mode API — Midnight (Patch 12.0.1)

> Comprehensive reference for WoW Edit Mode addon integration. Current for Midnight (Patch 12.0.1, Interface 120001).

## Quick Reference

| Resource | Description |
|----------|-------------|
| [01-api-reference.md](./01-api-reference.md) | C_EditMode functions, event, data structures, enums |
| [02-integration-patterns.md](./02-integration-patterns.md) | Hooks, custom frames, overlays, per-layout persistence, taint |
| [03-interactions-addon-support.md](./03-interactions-addon-support.md) | EditModeManagerFrame methods, EditModeSystemMixin lifecycle, grid/snap/magnet, LibEditModeOverride full API, EditModeExpanded registration, settings dialog, macros, addon support matrix |
| [04-blizzard-source-reference.md](./04-blizzard-source-reference.md) | **200+ function signatures** extracted from Blizzard's official FrameXML source — EditModeSystemMixin, EditModeManagerFrameMixin, EditModeMagnetismManager, all system-specific mixins, settings metadata for every UI system |
| [05-addon-examples.md](./05-addon-examples.md) | Real addon integration analysis — EditModeExpanded (full API + hooks), LibEditMode (callback architecture), Bartender4 (EventRegistry + taint-safe patterns), ElvUI (bypass pattern), common techniques, lessons for ChattyLittleNpc |
| [06-brainstorm-results.md](./06-brainstorm-results.md) | **Plus Ultra brainstorm** — 34 ideas from 3 model families, 19 scored by 3 critics, 8 recommended features with implementation paths, wild cards, blind spots, and phased roadmap |

---

## Overview

Edit Mode (introduced in Dragonflight 10.0) lets players reposition, resize, and configure built-in UI elements. Addons integrate by:

1. **Hooking** `EditModeManagerFrame:EnterEditMode()` / `ExitEditMode()` to detect mode changes
2. **Listening** to `EDIT_MODE_LAYOUTS_UPDATED` for layout switches/saves
3. **Querying** `C_EditMode.GetLayouts()` to identify the active layout
4. **Persisting** per-layout settings in addon saved variables
5. **Displaying** overlay/highlight UI during Edit Mode for frame manipulation

### Key Constraints

- **No official events** for enter/exit — must use `hooksecurefunc` on `EditModeManagerFrame`
- **Taint risk** — most `C_EditMode` write functions have `SecretArguments = "AllowedWhenUntainted"`
- **Combat lockdown** — frame repositioning blocked in combat (`InCombatLockdown()`)
- **Hidden base layouts** — `GetLayouts()` excludes 2 built-in presets (Modern, Classic); `activeLayout` index includes them
- **Non-combat addons** (like ChattyLittleNpc) are safe from Midnight's combat addon restrictions
