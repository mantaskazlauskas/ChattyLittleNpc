# Edit Mode Integration — Real Addon Examples & Library Analysis

> **Research date**: Based on live GitHub source analysis of the most popular WoW addons
> that integrate with Edit Mode. All code references link to actual repositories.

---

## Table of Contents

1. [EditModeExpanded-1.0 (Library)](#1-editmodeexpanded-10)
2. [LibEditMode by p3lim (Library)](#2-libeditmode-by-p3lim)
3. [Bartender4 (Action Bar Addon)](#3-bartender4)
4. [ElvUI / Tukui (UI Replacement)](#4-elvui--tukui)
5. [muleyoUI (Custom UI)](#5-muleyoui)
6. [Common Patterns & Techniques](#6-common-patterns--techniques)
7. [Key Blizzard APIs Used](#7-key-blizzard-apis-used)
8. [Lessons for Chatty NPC](#8-lessons-for-chatty-npc)

---

## 1. EditModeExpanded-1.0

> **Source**: [teelolws/EditModeExpanded](https://github.com/teelolws/EditModeExpanded)
> **Size**: ~98KB, MINOR version 114
> **Distribution**: LibStub embedded library
> **Used by**: 116+ addons found on GitHub

### Architecture Overview

EditModeExpanded (EME) is the most comprehensive library for adding custom frames to
Blizzard's Edit Mode system. It works by extending Blizzard's internal system ID space,
mixing in the `EditModeSystemMixin` onto custom frames, and hooking the manager frame.

**Key internal state:**

- `frames` — array of all registered custom frames
- `baseFramesDB` — per-frame base SavedVariables DB (contains profiles)
- `framesDB` — currently active profile's DB for each frame
- `framesDialogs` — settings dialog definitions per systemID
- `framesDialogsKeys` — tracks which settings are registered per systemID
- `existingFrames` — Blizzard frames where EME adds extra options
- System IDs start after `Enum.EditModeSystem` max value (index 20+)

### Complete Public API

#### Frame Registration

```lua
-- Register a custom frame for Edit Mode control
-- frame: the Frame to register
-- name: localized display name shown when selected
-- db: SavedVariables table for position persistence
-- anchorTo: parent frame (default: UIParent)
-- anchorPoint: anchor point string (default: "BOTTOMLEFT")
-- clamped: enable screen clamping (default: true)
lib:RegisterFrame(frame, name, db, anchorTo, anchorPoint, clamped)
```

**What RegisterFrame does internally:**
1. Assigns a unique `frame.system` ID (incrementing from `STARTING_INDEX`)
2. Calls `Mixin(frame, EditModeSystemMixin)` to add Blizzard Edit Mode methods
3. Creates a `Selection` frame using `EditModeSystemSelectionTemplate`
4. Creates a checkbox in the Expanded Manager panel for show/hide toggle
5. Creates a Reset button per frame
6. Sets up drag handlers that save position to the profile DB
7. Handles per-layout profile initialization
8. Adds a "Clamp to Screen" checkbox by default
9. Stores default position for reset functionality

#### Settings Registration

```lua
-- Add a resize slider (uses frame:SetScale internally)
lib:RegisterResizable(frame, minSize, maxSize, step)
-- minSize default: 10, maxSize default: 200, step default: 5

-- Add a "Hide" checkbox (hide frame outside Edit Mode)
lib:RegisterHideable(frame, onEventHandler)

-- Add a custom checkbox with callbacks
-- Returns: reset function
lib:RegisterCustomCheckbox(frame, name, onChecked, onUnchecked, internalName)

-- Add a custom button (no saved settings)
-- Returns: getCurrentDB function
lib:RegisterCustomButton(frame, name, onClick, internalName)

-- Add a dropdown menu (requires LibUIDropDownMenu)
-- Returns: dropdown, getCurrentDB function
lib:RegisterDropdown(frame, libUIDropDownMenu, internalName)

-- Add a custom slider
lib:RegisterSlider(frame, name, internalName, onChanged, min, max, step)

-- Add coordinate input fields (X, Y text boxes)
lib:RegisterCoordinates(frame)

-- Pin/unpin frame to minimap
lib:RegisterMinimapPinnable(frame)
```

#### Utility Functions

```lua
-- Set default size for frames that don't have one yet
lib:SetDefaultSize(frame, x, y)

-- Prevent small frames from being resized up to 40px during Edit Mode
lib:SetDontResize(frame)

-- Reposition frame from DB (call after delayed anchoring)
lib:RepositionFrame(frame)

-- Change anchor without changing visual position
lib:ReanchorFrame(frame, anchorTo, anchorPoint)

-- Check if frame is registered
lib:IsRegistered(frame)

-- Check if frame's checkbox is enabled
lib:IsFrameEnabled(frame)

-- Check if user marked frame as hidden
lib:IsFrameMarkedHidden(frame)

-- Force update of frame resize from DB
lib:UpdateFrameResize(frame)
```

### How It Hooks Blizzard's Edit Mode

EME hooks four critical methods on `EditModeManagerFrame`:

```lua
-- 1. EnterEditMode — show all registered frames, highlight them
hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function(self)
    for _, frame in ipairs(frames) do
        frame:SetHasActiveChanges(false)
        frame:HighlightSystem()
        wasVisible[frame.system] = frame:IsShown()
        frame:SetShown(framesDB[frame.system].enabled)
        -- Bump small frames to minimum 40x40 for draggability
    end
end)

-- 2. ExitEditMode — restore visibility, clear highlights
hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function(self)
    for _, frame in ipairs(frames) do
        frame:ClearHighlight()
        frame:StopMovingOrSizing()
        frame:SetShown(wasVisible[frame.system])  -- restore pre-edit visibility
    end
end)

-- 3. SelectSystem — deselect custom frames when Blizzard frame selected
hooksecurefunc(EditModeManagerFrame, "SelectSystem", function(self, systemFrame)
    for _, frame in ipairs(frames) do
        if systemFrame ~= frame then
            frame:HighlightSystem()
        end
    end
end)

-- 4. MakeNewLayout — copy profile data to new layout
hooksecurefunc(EditModeManagerFrame, "MakeNewLayout", function(self, _, layoutType, layoutName)
    -- copies position data from old profile to new profile
end)
```

Additionally hooks `OnShow`/`OnHide` on `EditModeManagerFrame` to show/hide the
expanded panel.

### Per-Layout Profile System

EME implements its own profile system that mirrors Blizzard's layout system:

```lua
-- Profile key construction:
local layoutInfo = EditModeManagerFrame:GetActiveLayoutInfo()
local profileName = layoutInfo.layoutType .. "-" .. layoutInfo.layoutName

-- Character-specific layouts include character name:
if layoutInfo.layoutType == Enum.EditModeLayoutType.Character then
    local unitName, unitRealm = UnitFullName("player")
    profileName = layoutInfo.layoutType .. "-" .. unitName .. "-" .. unitRealm
                  .. "-" .. layoutInfo.layoutName
end

-- Stored in SavedVariables as:
-- db.profiles[profileName] = { x=, y=, enabled=, settings={}, defaultX=, defaultY= }
```

### Position Save/Restore

```lua
-- On drag stop, saves raw GetRect() coordinates:
frame.Selection:SetScript("OnDragStop", function(self)
    local profiledb = framesDB[frame.system]
    profiledb.x, profiledb.y = self:GetRect()
    -- Convert to offset-based positioning:
    local x, y = getOffsetXY(frame, profiledb.x, profiledb.y)
    frame:ClearAllPoints()
    frame:SetPoint(frame.EMEanchorPoint, frame.EMEanchorTo, frame.EMEanchorPoint, x, y)
end)
```

### Novel Techniques

1. **Taint-safe Mixin**: Custom `Mixin()` that does NOT overwrite existing functions and
   explicitly skips `AddSnappedFrame` to prevent taint spread
2. **Hook versioning**: Uses `hookScriptWrapper`/`hooksecurefuncWrapper` with MINOR version
   checks to prevent duplicate hook execution across library versions
3. **Combat lockdown guard**: All enter/exit/position operations check `InCombatLockdown()`
4. **Secure handler for mouse-over hide**: Uses `SecureHandlerEnterLeaveTemplate` to
   hide/show frames on mouseover without taint
5. **Out-of-combat queue**: Defers operations via `runOutOfCombat` when in combat

---

## 2. LibEditMode by p3lim

> **Source**: [p3lim-wow/LibEditMode](https://github.com/p3lim-wow/LibEditMode)
> **Size**: ~31KB, MINOR version 15
> **Distribution**: LibStub or namespace-embedded
> **Used by**: TwintopInsanityBar, DarkUI, Glider, RasUI, PhoUI, muleyoUI, and others

### Architecture Overview

LibEditMode takes a different, lighter-weight approach than EME. Instead of mixing in
`EditModeSystemMixin`, it creates standalone selection overlays and its own dialog system.
It focuses on clean callback-based positioning and provides explicit layout lifecycle events.

### Complete Public API

#### Frame Management

```lua
-- Register a frame for Edit Mode control
-- callback: function(point, x, y) triggered on reposition
-- default: { point = "CENTER", x = 0, y = 0 }
-- name: display name (defaults to frame:GetName())
lib:AddFrame(frame, callback, default, name)

-- Add settings controls to a frame's dialog
lib:AddFrameSettings(frame, settings)

-- Enable/disable individual settings
lib:EnableFrameSetting(frame, settingName)
lib:DisableFrameSetting(frame, settingName)

-- Add action buttons to frame dialog
lib:AddFrameSettingsButton(frame, data)   -- deprecated
lib:AddFrameSettingsButtons(frame, buttons)

-- Refresh the dialog for a frame
lib:RefreshFrameSettings(frame)
```

#### Blizzard System Extensions

```lua
-- Add extra settings to Blizzard's built-in Edit Mode systems
lib:AddSystemSettings(systemID, settings, subSystemID)
lib:EnableSystemSetting(systemID, settingName, subSystemID)
lib:DisableSystemSetting(systemID, settingName, subSystemID)
lib:AddSystemSettingsButtons(systemID, buttons, subSystemID)
```

#### Lifecycle Callbacks

```lua
-- Register for Edit Mode lifecycle events
lib:RegisterCallback(event, callback)

-- Available events:
-- "enter"  — Edit Mode opened
-- "exit"   — Edit Mode closed
-- "layout" — layout changed (also fires at login)
--            callback(layoutName, layoutIndex)
-- "create" — new layout created
--            callback(layoutName, layoutIndex, sourceLayoutName)
-- "rename" — layout renamed
--            callback(oldName, newName, layoutIndex)
-- "delete" — layout deleted
--            callback(layoutName)
```

#### Query Functions

```lua
lib:GetActiveLayout()         -- returns layout index
lib:GetActiveLayoutName()     -- returns layout name string
lib:IsInEditMode()            -- returns boolean
lib:GetFrameDefaultPosition(frame)  -- returns default position table
```

### How It Hooks Blizzard's Edit Mode

LibEditMode uses a cleaner event-based approach:

```lua
-- Enter/Exit via OnShow/OnHide hooks on EditModeManagerFrame
EditModeManagerFrame:HookScript('OnShow', onEditModeEnter)
EditModeManagerFrame:HookScript('OnHide', onEditModeExit)

-- Layout changes via EventRegistry
EventRegistry:RegisterFrameEventAndCallback('EDIT_MODE_LAYOUTS_UPDATED', onEditModeChanged)
EventRegistry:RegisterFrameEventAndCallback('PLAYER_SPECIALIZATION_CHANGED', onSpecChanged)
EventRegistry:RegisterCallback('EditMode.SavedLayouts', onEditModeLayoutChanged)

-- System selection deselects custom frames
hooksecurefunc(EditModeManagerFrame, 'SelectSystem', function(_, systemFrame)
    resetDialogs()
    resetSelection()
    -- Check if this system has registered extensions
end)

-- Track layout copy source
hooksecurefunc(EditModeManagerFrame, 'ShowNewLayoutDialog', function(_, sourceLayout)
    lib._layoutCopySource = sourceLayout
end)
```

### Key Design Differences from EME

| Feature | EditModeExpanded | LibEditMode |
|---------|-----------------|-------------|
| Frame registration | Mixin-based (EditModeSystemMixin) | Selection overlay only |
| Position storage | Library manages DB directly | Callback-based (addon manages DB) |
| Profile system | Built-in profile management | Layout event callbacks |
| Settings UI | Extends Blizzard's dialog | Custom dialog + extension panel |
| System extensions | Via EMESystemID on existing frames | Direct system/subSystem settings |
| Taint handling | Custom Mixin that skips taint-spreading keys | Avoids Mixin entirely |
| Layout lifecycle | Hooks MakeNewLayout | Full create/rename/delete callbacks |
| Hook versioning | MINOR-based wrapper dedup | MINOR-based hookVersion check |

### Novel Techniques

1. **Position normalization**: Adapted from LibWindow-1.1 — dynamically calculates the
   best anchor point (TOPLEFT, CENTER, BOTTOMRIGHT, etc.) based on frame position
   relative to parent, ensuring positions survive resolution changes
2. **Global dialog coordination**: Uses `EventRegistry:TriggerEvent('EditModeExternal.hideDialog')`
   as a cross-addon protocol for hiding custom dialogs when Blizzard selects a system
3. **Spec change tracking**: Listens to `PLAYER_SPECIALIZATION_CHANGED` to update layout
   (Blizzard auto-switches layouts per spec)
4. **Layout copy source tracking**: Hooks `ShowNewLayoutDialog` to know which layout was
   the source of a copy operation

---

## 3. Bartender4

> **Source**: [Nevcairiel/Bartender4](https://github.com/Nevcairiel/Bartender4)
> **Type**: Action bar replacement addon

### Edit Mode Integration Pattern

Bartender4 takes a **minimal integration** approach — it doesn't register frames with
Edit Mode but instead listens for Edit Mode enter/exit to unlock/lock its own bar system:

```lua
-- In Bartender4:OnInitialize()
if EditModeManagerFrame then
    -- Listen for Edit Mode enter/exit via EventRegistry callbacks
    EventRegistry:RegisterCallback("EditMode.Enter", function() self:Unlock(true) end)
    EventRegistry:RegisterCallback("EditMode.Exit", function() self:Lock() end)

    -- Sync snapping setting with Blizzard's Edit Mode checkbox
    if EditModeManagerFrame.EnableSnapCheckButton then
        self:SecureHook(EditModeManagerFrame.EnableSnapCheckButton,
            "OnCheckButtonClick", "UpdateSnapFromEditMode")
        self:SecureHook(EditModeManagerFrame.EnableSnapCheckButton,
            "SetControlChecked", "UpdateSnapFromEditMode")
    end
end
```

### Blizzard Frame Hiding (Taint-Safe)

Bartender4's approach to hiding Blizzard action bars is relevant for any addon that
replaces UI elements:

```lua
local function hideActionBarFrame(frame, clearEvents)
    if frame then
        if clearEvents then
            frame:UnregisterAllEvents()
        end

        -- Remove EditMode hooks to avoid taint
        if frame.system then
            Bartender4.Util:PurgeKey(frame, "isShownExternal")
        end

        -- EditMode overrides Hide(), use HideBase() to avoid taint
        if frame.HideBase then
            frame:HideBase()
        else
            frame:Hide()
        end
        frame:SetParent(Bartender4.UIHider)  -- reparent to hidden frame
    end
end
```

### Key API Functions Used

- `EventRegistry:RegisterCallback("EditMode.Enter", ...)` — official callback
- `EventRegistry:RegisterCallback("EditMode.Exit", ...)` — official callback
- `EditModeManagerFrame.EnableSnapCheckButton` — reads snap setting
- `frame.HideBase` — Blizzard's base Hide before EditMode override

### Novel Techniques

1. **PurgeKey for taint**: Custom utility to nil out secure variables without spreading taint
   by writing dummy values until `issecurevariable` returns true
2. **UIHider pattern**: Creates a hidden parent frame and reparents Blizzard frames to it
3. **`fromEditMode` parameter**: `Unlock(true)` tells the unlock system it came from Edit Mode,
   so it skips showing its own unlock dialog (Blizzard's UI is already showing)

---

## 4. ElvUI / Tukui

> **Source**: [tukui-org/ElvUI](https://github.com/tukui-org/ElvUI)
> **Type**: Complete UI replacement framework

### Edit Mode Integration

ElvUI takes the most aggressive approach — it has its own complete mover/anchor system
and largely **bypasses** Blizzard's Edit Mode. Key observations:

**ActionBars module** — only references EditMode to avoid taint:
```lua
-- Avoids taint from EditModeManager's UpdateBottomActionBarPositions
button:SetScript('OnShow', nil)
button:SetScript('OnHide', nil)
```

**Tukui's Commands.lua** — directly toggles Edit Mode:
```lua
-- Tukui hooks into edit mode for its own mover system
```

**Tukui's MoveUI.lua** — implements its own frame mover that is similar to but
independent of Edit Mode.

### Key Pattern: Own Mover System

ElvUI and Tukui both implement their own mover systems using `E:CreateMover()` rather
than integrating with Blizzard's Edit Mode. This is because:

1. They replace almost all Blizzard frames, so Edit Mode's built-in systems don't apply
2. They need more control over positioning (custom grid, snap-to-pixel)
3. They have their own profile system that predates Edit Mode

The key takeaway is that **large UI replacements bypass Edit Mode entirely** and
implement their own positioning systems.

---

## 5. muleyoUI

> **Source**: [muleyo/muleyoUI](https://github.com/muleyo/muleyoUI)
> **Type**: Custom UI compilation using LibEditMode

### Edit Mode Integration

muleyoUI demonstrates a full LibEditMode consumer implementation for classic/non-retail
clients that don't have Blizzard's Edit Mode:

```lua
local EditMode = mUI:NewModule("mUI.EditMode", "AceHook-3.0")

function EditMode:OnInitialize()
    EditMode.db = mUI.db.profile.edit

    -- Stores frame positions with full anchor data
    EditMode.db.frames = {}

    -- Defines defaults per named frame
    EditMode.defaults = {
        ["mUIStatsFrame"] = {
            point = "BOTTOMLEFT",
            relativeTo = "UIParent",
            relativePoint = "BOTTOMLEFT",
            x = 5, y = 5
        },
        -- ... more frame defaults
    }

    -- Grid overlay for alignment
    EditMode.db.grid = {
        enabled = false,
        size = 32,
        alpha = 0.3,
        color = {1, 1, 1}
    }

    -- Snapping configuration
    EditMode.db.snapping = {
        enabled = true,
        snapToFrames = true,
        snapToCenter = true,
        snapToGrid = false,
        snapDistance = 10
    }
end
```

### Key Pattern: Full Position Persistence

The position table stores complete anchor data for reliable restoration:
```lua
-- Each frame stores:
{
    point = "TOPLEFT",
    relativeTo = "UIParent",
    relativePoint = "TOPLEFT",
    x = 100,
    y = -200
}
```

---

## 6. Common Patterns & Techniques

### Pattern 1: Enter/Exit Hook

Every addon uses one of two approaches to detect Edit Mode:

```lua
-- Approach A: EventRegistry callbacks (cleanest, used by Bartender4)
EventRegistry:RegisterCallback("EditMode.Enter", onEnter)
EventRegistry:RegisterCallback("EditMode.Exit", onExit)

-- Approach B: HookScript on the manager frame (used by EME, LibEditMode)
EditModeManagerFrame:HookScript("OnShow", onEnter)
EditModeManagerFrame:HookScript("OnHide", onExit)

-- Approach C: hooksecurefunc (used by EME for more control)
hooksecurefunc(EditModeManagerFrame, "EnterEditMode", onEnter)
hooksecurefunc(EditModeManagerFrame, "ExitEditMode", onExit)
```

### Pattern 2: Selection Overlay

Both libraries create selection overlays using Blizzard's template:

```lua
local selection = CreateFrame("Frame", nil, frame, "EditModeSystemSelectionTemplate")
selection:SetAllPoints(frame)
selection:Hide()
```

### Pattern 3: Combat Lockdown Guard

Every operation that moves or shows/hides frames checks combat state:

```lua
if InCombatLockdown() then return end
```

### Pattern 4: Profile Key Construction

Mapping Blizzard layouts to addon profiles:

```lua
local layoutInfo = EditModeManagerFrame:GetActiveLayoutInfo()
-- layoutInfo.layoutType: Enum.EditModeLayoutType (Account or Character)
-- layoutInfo.layoutName: string
```

### Pattern 5: UIHider for Blizzard Frame Removal

```lua
local UIHider = CreateFrame("Frame")
UIHider:Hide()
blizzardFrame:SetParent(UIHider)  -- effectively hides without taint
```

### Pattern 6: Taint Avoidance

```lua
-- Don't overwrite existing methods when mixing in
if not object[k] then object[k] = v end

-- Skip known taint-spreading methods
if k ~= "AddSnappedFrame" then ...

-- Use HideBase() instead of Hide() on EditMode frames
if frame.HideBase then frame:HideBase() end

-- PurgeKey pattern for secure variable cleanup
repeat
    if t[c] == nil then t[c] = nil end
    c = c + 1
until issecurevariable(t, k)
```

### Pattern 7: Library Version Deduplication

Both libraries handle multiple embedded versions:

```lua
-- EME: wrapper tables that only execute for current MINOR
f.hookScriptWrappers[frame][event][MINOR] = hookfunc
-- Only the latest version's hook runs

-- LibEditMode: hookVersion check
lib.hookVersion = MINOR
EditModeManagerFrame:HookScript('OnShow', function()
    if lib.hookVersion == MINOR then onEditModeEnter() end
end)
```

---

## 7. Key Blizzard APIs Used

### C_EditMode Namespace

```lua
C_EditMode.GetLayouts()
-- Returns: { activeLayout = number, layouts = { { layoutName, layoutType, ... } } }

EditModeManagerFrame:GetActiveLayoutInfo()
-- Returns: { layoutType = Enum.EditModeLayoutType, layoutName = string }
```

### Enums

```lua
Enum.EditModeLayoutType.Account    -- shared across characters
Enum.EditModeLayoutType.Character  -- per-character

Enum.EditModeSystem                -- built-in system IDs (ActionBar, UnitFrame, etc.)

Enum.EditModeSettingDisplayType.Checkbox
Enum.EditModeSettingDisplayType.Slider
Enum.EditModeSettingDisplayType.Dropdown
```

### Events

```lua
-- Frame events
"EDIT_MODE_LAYOUTS_UPDATED"      -- layout data changed

-- EventRegistry callbacks (not frame events)
"EditMode.Enter"                 -- entering edit mode
"EditMode.Exit"                  -- exiting edit mode
"EditMode.SavedLayouts"          -- layouts saved (create/rename/delete)
```

### Templates

```lua
"EditModeSystemSelectionTemplate"  -- selection overlay with drag support
"EditModeSystemSettingsDialogButtonTemplate"  -- button in settings dialog
```

### Key Manager Frame Methods

```lua
EditModeManagerFrame:EnterEditMode()
EditModeManagerFrame:ExitEditMode()
EditModeManagerFrame:SelectSystem(systemFrame)
EditModeManagerFrame:ClearSelectedSystem()
EditModeManagerFrame:GetActiveLayoutInfo()
EditModeManagerFrame:MakeNewLayout(_, layoutType, layoutName)
EditModeManagerFrame:OnSystemPositionChange(systemFrame)
EditModeManagerFrame.editModeActive  -- boolean state
```

---

## 8. Lessons for Chatty NPC

### Recommended Approach

For a single-frame addon like Chatty NPC, the best approach is a **lightweight
LibEditMode-style integration** or direct hooks, not the full EME library:

1. **Hook Enter/Exit**: Use `EventRegistry:RegisterCallback("EditMode.Enter/Exit")`
2. **Create selection overlay**: Use `EditModeSystemSelectionTemplate`
3. **Save per-layout positions**: Key on `GetActiveLayoutInfo()` layout type + name
4. **Combat guard everything**: Check `InCombatLockdown()` before any frame operation
5. **Callback for position changes**: Fire a callback on drag-stop with normalized position
6. **Normalize positions**: Use the LibWindow-style point calculation for resolution safety

### What NOT to Do

- Don't use `EditModeSystemMixin` directly — it spreads taint
- Don't skip the `AddSnappedFrame` exclusion if mixing in
- Don't call `frame:SetUserPlaced(true)` — it conflicts with Edit Mode's position management
- Don't register for Edit Mode without combat lockdown checks
- Don't try to extend Blizzard's system enum — use your own ID space

### Minimal Integration Skeleton

```lua
-- Detect Edit Mode support
if EditModeManagerFrame then
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        if InCombatLockdown() then return end
        -- Show selection overlay, enable dragging
    end)

    EventRegistry:RegisterCallback("EditMode.Exit", function()
        if InCombatLockdown() then return end
        -- Hide selection overlay, save position, disable dragging
    end)

    -- Track layout changes for per-layout positions
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    frame:SetScript("OnEvent", function()
        local layoutInfo = EditModeManagerFrame:GetActiveLayoutInfo()
        -- Load position for this layout from SavedVariables
    end)
end
```

### WeakAuras & Edit Mode

WeakAuras (org: WeakAuras on GitHub) does **not** have direct Edit Mode integration.
No search results were found for EditMode in the WeakAuras codebase. WeakAuras uses
its own anchor/mover system (`/wa` configuration UI) and is independent of Blizzard's
Edit Mode. This is the same pattern as ElvUI — complex addons with their own positioning
systems tend to bypass Edit Mode entirely.

---

## Appendix: Addons Using EditModeExpanded

From GitHub search (116+ results), notable consumers include addon compilations and
UI packs that register various game frames. The typical consumer pattern is:

```lua
local EME = LibStub("EditModeExpanded-1.0")
EME:RegisterFrame(MyFrame, "My Frame Name", MyAddonDB.framePosition)
EME:RegisterResizable(MyFrame)
EME:RegisterHideable(MyFrame)
```

### Addons Using LibEditMode

Found in: TwintopInsanityBar, DarkUI, Glider, RasUI, PhoUI, ItruliaQoL, QUI, muleyoUI.
LibEditMode is also available as a namespace-embedded library (no LibStub required).
