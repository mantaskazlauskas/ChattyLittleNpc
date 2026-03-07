# Edit Mode API Reference

> All C_EditMode functions, the EDIT_MODE_LAYOUTS_UPDATED event, data structures, and enums.
> Current for Midnight (Patch 12.0.1). Source: Blizzard API Documentation (`EditModeManagerDocumentation.lua`).

---

## C_EditMode Functions (11 total)

### Layout Management

```lua
C_EditMode.GetLayouts() : EditModeLayouts
-- Returns all custom layouts (NOT default presets Modern/Classic).
-- The returned .activeLayout index counts from 1 INCLUDING hidden presets,
-- so you often need to subtract 2 (HIDDEN_BASE_LAYOUTS) to index into .layouts[].
-- Safe to call anytime. Read-only, no taint.

C_EditMode.SaveLayouts(saveInfo: EditModeLayouts)
-- Persist modified layouts to the server.
-- SecretArguments = "AllowedWhenUntainted" — tainted calls will silently fail.
-- Fires EDIT_MODE_LAYOUTS_UPDATED after success.

C_EditMode.SetActiveLayout(activeLayout: luaIndex)
-- Switch the player's active layout by index.
-- SecretArguments = "AllowedWhenUntainted".
-- Fires EDIT_MODE_LAYOUTS_UPDATED after switch.

C_EditMode.OnLayoutAdded(addedLayoutIndex: luaIndex, activateNewLayout: bool, isLayoutImported: bool)
-- Called by Blizzard code when a layout is created.
-- SecretArguments = "AllowedWhenUntainted". Internal use — do not call from addons.

C_EditMode.OnLayoutDeleted(deletedLayoutIndex: luaIndex)
-- Called by Blizzard code when a layout is deleted.
-- SecretArguments = "AllowedWhenUntainted". Internal use — do not call from addons.
```

### Layout Serialization (Import/Export)

```lua
C_EditMode.ConvertLayoutInfoToString(layoutInfo: EditModeLayoutInfo) : string
-- Serialize a single layout to a shareable string.
-- SecretArguments = "AllowedWhenUntainted".
-- Used for layout export features.

C_EditMode.ConvertStringToLayoutInfo(layoutInfoAsString: string) : EditModeLayoutInfo?
-- Deserialize an import string back to layout data.
-- SecretArguments = "AllowedWhenUntainted".
-- MayReturnNothing — returns nil if the string is invalid.
```

### Account Settings

```lua
C_EditMode.GetAccountSettings() : EditModeSettingInfo[]
-- Returns account-wide Edit Mode settings (e.g., action bar visibility).
-- Read-only, safe to call anytime.

C_EditMode.SetAccountSetting(setting: EditModeAccountSetting, value: number)
-- Modify an account-wide setting.
-- SecretArguments = "AllowedWhenUntainted".
```

### Validation & Lifecycle

```lua
C_EditMode.IsValidLayoutName(name: cstring) : bool
-- Check if a layout name is allowed (no profanity, length limits).
-- SecretArguments = "AllowedWhenUntainted".

C_EditMode.OnEditModeExit()
-- Signal that Edit Mode has been exited.
-- Internal use by Blizzard — do not call from addons.
```

---

## EDIT_MODE_LAYOUTS_UPDATED Event

The **only** Edit Mode event. Fires when layouts change (save, switch, import, server reconcile).

```lua
-- Registration
local frame = CreateFrame("Frame")
frame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
frame:SetScript("OnEvent", function(self, event, layoutInfo, reconcileLayouts)
    -- layoutInfo: EditModeLayouts — full layout data
    -- reconcileLayouts: boolean — true when reconciling from server (login/reload)
end)
```

**When it fires:**
- Player saves a layout in Edit Mode
- Player switches active layout
- Layout imported from string
- UI reload / login (with `reconcileLayouts = true`)
- Layout created or deleted

**When it does NOT fire:**
- Entering Edit Mode (use `hooksecurefunc` instead)
- Exiting Edit Mode (use `hooksecurefunc` instead)

**Patch history:**
- Added in 10.0.0
- 10.0.5: Renamed param `fromServer` → `reconcileLayouts`

---

## Data Structures

### EditModeLayouts

Top-level container returned by `GetLayouts()`.

```lua
---@class EditModeLayouts
---@field layouts EditModeLayoutInfo[]  -- Array of user-created layouts
---@field activeLayout number           -- 1-based index (includes hidden presets!)
```

### EditModeLayoutInfo

A single layout profile.

```lua
---@class EditModeLayoutInfo
---@field layoutName string
---@field layoutType EditModeLayoutType  -- Enum (see below)
---@field systems EditModeSystemInfo[]   -- All systems in this layout
```

### EditModeSystemInfo

Configuration for one UI system (action bar, minimap, etc.) within a layout.

```lua
---@class EditModeSystemInfo
---@field system EditModeSystem         -- Enum identifying the system type
---@field systemIndex number?           -- Sub-index for multi-instance systems (action bars 1-8)
---@field anchorInfo EditModeAnchorInfo  -- Primary anchor point
---@field anchorInfo2 EditModeAnchorInfo? -- Secondary anchor (dual-anchored systems)
---@field settings EditModeSettingInfo[] -- System-specific settings
---@field isInDefaultPosition boolean   -- Whether frame is at its default position
```

### EditModeAnchorInfo

Anchor data for positioning a system frame.

```lua
---@class EditModeAnchorInfo
---@field point FramePoint       -- "CENTER", "TOPLEFT", "BOTTOM", etc.
---@field relativeTo string      -- Parent frame name (usually "UIParent")
---@field relativePoint FramePoint
---@field offsetX number
---@field offsetY number
```

### EditModeSettingInfo

A single setting key-value pair.

```lua
---@class EditModeSettingInfo
---@field setting number  -- Setting ID (system-specific, e.g., 0=Orientation for ActionBar)
---@field value number    -- Setting value
```

---

## Enums

### Enum.EditModeLayoutType

```lua
-- Layout profile type
Preset    = 0   -- Built-in presets (Modern, Classic) — NOT returned by GetLayouts()
Account   = 1   -- Account-wide custom layout
Character = 2   -- Character-specific custom layout
Override  = 3   -- Layout override (used in some export/import contexts)
```

### Enum.EditModeSystem (24 values in 12.0)

```lua
-- UI system types manageable in Edit Mode
ActionBar              = 0   -- Action bars (systemIndex 1-8, 11=Stance, 12=Pet, 13=Possess)
CastBar                = 1   -- Player cast bar
Minimap                = 2   -- Minimap frame
UnitFrame              = 3   -- Unit frames (systemIndex: 1=Player, 2=Target, 3=Focus, ...)
EncounterBar           = 4   -- Boss encounter bar
ExtraAbilities         = 5   -- Extra action button / zone abilities
AuraFrame              = 6   -- Buff/debuff frames
TalkingHeadFrame       = 7   -- Talking head cinematic overlay
ChatFrame              = 8   -- Chat window
VehicleLeaveButton     = 9   -- Vehicle exit button
LootFrame              = 10  -- Loot window
HudTooltip             = 11  -- HUD tooltip
ObjectiveTracker       = 12  -- Quest/objective tracker
MicroMenu              = 13  -- Micro menu bar (added 10.0.5)
Bags                   = 14  -- Bag slots (added 10.0.5)
StatusTrackingBar      = 15  -- XP/reputation/honor bars (added 10.0.5)
DurabilityFrame        = 16  -- Durability indicator (added 10.1.5)
TimerBars              = 17  -- Timer/mirror bars (added 10.1.5)
VehicleSeatIndicator   = 18  -- Vehicle seat indicator (added 10.1.5)
ArchaeologyBar         = 19  -- Archaeology progress bar (added 10.1.5)
CooldownViewer         = 20  -- Cooldown tracking (added 11.1.5) ← NEW in The War Within
PersonalResourceDisplay = 21 -- Personal resource display (added 12.0) ← NEW in Midnight
EncounterEvents        = 22  -- Encounter event tracking (added 12.0) ← NEW in Midnight
DamageMeter            = 23  -- Built-in damage meter (added 12.0) ← NEW in Midnight
```

### ActionBar systemIndex Values

```lua
-- For system = 0 (ActionBar), systemIndex identifies which bar:
1-8   = Action Bars 1 through 8
11    = Stance Bar
12    = Pet Bar
13    = Possess Bar
```

### Common Setting IDs (ActionBar example)

```lua
-- For ActionBar systems, setting IDs:
0 = Orientation      -- 0=horizontal, 1=vertical
1 = NumRows          -- 1-4
2 = NumIcons         -- 6-12
3 = IconSize         -- 0-15 (value × 10% + 50%)
4 = IconPadding      -- 2-10
5 = BarVisible       -- 0=Always, 1=InCombat, 2=OutOfCombat, 3=Hidden
6 = HideBarArt       -- 0=false, 1=true
8 = HideBarScrolling -- 0=false, 1=true
9 = AlwaysShowButtons -- 0=false, 1=true
```

### Common Setting IDs (CastBar example)

```lua
0 = BarSize           -- 0-5 (value × 10% + 100%)
1 = LockToPlayerFrame -- 0=false, 1=true
2 = ShowCastTime      -- 0=false, 1=true
```

### Common Setting IDs (Minimap example)

```lua
0 = HeaderUnderneath  -- 0=false, 1=true
1 = RotateMinimap     -- 0=false, 1=true
2 = Size              -- 0-15 (value × 10% + 50%)
```

### Common Setting IDs (UnitFrame example)

```lua
-- Player frame (systemIndex=1):
1  = CastBarUnderneath -- 0=false, 1=true
16 = FrameSize         -- 0-20 (value × 5% + 100%)

-- Target frame (systemIndex=2):
2  = BuffsOnTop        -- 0=false, 1=true
16 = FrameSize         -- 0-20 (value × 5% + 100%)
```

---

## Taint & Protection Rules

### SecretArguments = "AllowedWhenUntainted"

Most `C_EditMode` write functions use this protection level:

```lua
-- These functions are PROTECTED (will silently fail if tainted):
C_EditMode.SaveLayouts()
C_EditMode.SetActiveLayout()
C_EditMode.SetAccountSetting()
C_EditMode.OnLayoutAdded()
C_EditMode.OnLayoutDeleted()
C_EditMode.ConvertLayoutInfoToString()
C_EditMode.ConvertStringToLayoutInfo()
C_EditMode.IsValidLayoutName()

-- These functions are SAFE (no taint restrictions):
C_EditMode.GetLayouts()             -- Read-only
C_EditMode.GetAccountSettings()     -- Read-only
C_EditMode.OnEditModeExit()         -- No arguments
```

### Best Practice

```lua
-- Always wrap protected calls in pcall to handle taint gracefully
local ok, result = pcall(C_EditMode.GetLayouts)
if ok and result then
    -- Use result safely
end

-- Never call protected functions from tainted execution paths
-- (e.g., from within hooked Blizzard functions that modify secure state)
```

---

## Layout Data Example

Complete example of what `C_EditMode.GetLayouts()` returns:

```lua
local layoutData = C_EditMode.GetLayouts()
-- layoutData = {
--     activeLayout = 3,  -- WARNING: includes hidden presets (Modern=0, Classic=1)
--     layouts = {
--         [1] = {
--             layoutName = "MyRaidLayout",
--             layoutType = 1,  -- Account
--             systems = {
--                 [1] = {
--                     system = 0,         -- ActionBar
--                     systemIndex = 1,    -- Action Bar 1
--                     isInDefaultPosition = false,
--                     anchorInfo = {
--                         point = "BOTTOM",
--                         relativeTo = "UIParent",
--                         relativePoint = "BOTTOM",
--                         offsetX = 45,
--                         offsetY = 0,
--                     },
--                     settings = {
--                         { setting = 0, value = 0 },  -- Horizontal
--                         { setting = 1, value = 2 },  -- 2 rows
--                         { setting = 2, value = 12 }, -- 12 icons
--                     },
--                 },
--                 [2] = {
--                     system = 2,  -- Minimap
--                     isInDefaultPosition = true,
--                     anchorInfo = { ... },
--                     settings = { ... },
--                 },
--                 -- ... more systems
--             },
--         },
--         -- ... more layouts
--     },
-- }
```
