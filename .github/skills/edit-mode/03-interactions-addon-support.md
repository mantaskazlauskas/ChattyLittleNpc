# Edit Mode Interactions & Addon Support

> EditModeManagerFrame methods, EditModeSystemMixin lifecycle, grid/snap/magnet system,
> settings display types, complete LibEditModeOverride API, EditModeExpanded registration,
> layout macros, and dialog handling.

---

## EditModeManagerFrame — The Central Hub

`EditModeManagerFrame` is the main frame managing Edit Mode. It controls layout switching,
entering/exiting, saving, and the settings dialog. Key methods:

### State Control Methods

```lua
-- Enter/exit Edit Mode (these are the ones you hook with hooksecurefunc)
EditModeManagerFrame:EnterEditMode()
-- Activates Edit Mode: shows grid, highlights systems, enables drag/resize.

EditModeManagerFrame:ExitEditMode()
-- Deactivates Edit Mode: hides overlays, saves pending changes if any.

-- Check if we're currently in Edit Mode
EditModeManagerFrame:IsEditModeActive()
-- Returns boolean. NOT always available — some versions use .editModeActive field.
```

### Layout Management Methods

```lua
EditModeManagerFrame:SelectLayout(index)
-- Switch to a layout by its index. Updates all systems to match the layout's positions/settings.
-- Equivalent to calling C_EditMode.SetActiveLayout(index) but also updates the UI.

EditModeManagerFrame:GetLayouts()
-- Returns the layouts table (same as C_EditMode.GetLayouts().layouts but includes presets).

EditModeManagerFrame:SaveLayoutChanges()
-- Saves all pending modifications to the active layout. Calls C_EditMode.SaveLayouts().

EditModeManagerFrame:RevertAllChanges()
-- Discards all unsaved modifications, restoring the layout to its last saved state.

EditModeManagerFrame:HasActiveChanges()
-- Returns true if there are unsaved modifications in the current Edit Mode session.

EditModeManagerFrame:ReconcileWithModern(layout)
-- Ensures a layout has entries for all modern systems (adds missing ones).
-- Returns true if any changes were made.
```

### Selection System

```lua
EditModeManagerFrame:SelectSystem(systemFrame)
-- Selects a system frame — highlights it and shows the EditModeSystemSettingsDialog.
-- The selected frame receives focus and settings controls.

EditModeManagerFrame:ClearSelectedSystem()
-- Deselects the currently selected system. Hides the settings dialog.
-- Use this when your addon frame is clicked during Edit Mode to avoid conflicts.

EditModeManagerFrame:GetSelectedSystem()
-- Returns the currently selected system frame, or nil.
```

### Import/Export

```lua
EditModeManagerFrame:ImportLayout(layoutString)
-- Import a layout from a serialized string. Shows confirmation dialog.

EditModeManagerFrame:ExportLayout()
-- Exports the active layout as a string for sharing.
-- Uses C_EditMode.ConvertLayoutInfoToString() internally.
```

---

## EditModeSystemMixin — How Systems Participate

Every UI element manageable in Edit Mode uses `EditModeSystemMixin`. This mixin provides
the lifecycle methods that Blizzard calls as users interact with Edit Mode.

### Lifecycle Methods

```lua
EditModeSystemMixin:SetupEditModeForSystem()
-- Called once during initialization. Configures the frame for Edit Mode participation:
-- - Registers the system type and index
-- - Sets up anchor management
-- - Initializes settings
-- - Prepares the frame for drag/resize interaction

EditModeSystemMixin:OnEditModeEnter()
-- Called when Edit Mode is activated. The system should:
-- - Show its highlight/selection border
-- - Enable mouse interaction (drag, click-to-select)
-- - Show grid alignment guides if applicable
-- - Display any edit-mode-specific UI (labels, handles)

EditModeSystemMixin:OnEditModeExit()
-- Called when Edit Mode is deactivated. The system should:
-- - Hide highlights and overlays
-- - Disable edit-mode mouse handlers
-- - Save any pending position/size changes
-- - Restore normal interaction behavior

EditModeSystemMixin:SetIsSelected(isSelected)
-- Called when the system is selected/deselected within Edit Mode.
-- isSelected = true: show settings panel, thicker highlight border
-- isSelected = false: hide settings panel, thin or no highlight
-- Internally triggers EditModeSystemSettingsDialog show/hide.
```

### Position & Settings Methods

```lua
EditModeSystemMixin:UpdateSystem(systemInfo)
-- Apply systemInfo (anchor + settings) to the frame. Called on layout load/switch.

EditModeSystemMixin:GetSystemInfo()
-- Returns the current EditModeSystemInfo for this system.

EditModeSystemMixin:IsInDefaultPosition()
-- Returns true if the frame hasn't been moved from its default position.

EditModeSystemMixin:ResetToDefaultPosition()
-- Moves the frame back to its built-in default position.

EditModeSystemMixin:GetSettingValue(setting)
-- Returns the current value of a specific setting ID.

EditModeSystemMixin:SetSettingValue(setting, value)
-- Updates a setting value. Triggers visual refresh.
```

### Drag & Resize Methods

```lua
EditModeSystemMixin:OnDragStart()
-- Called when the user starts dragging the system in Edit Mode.
-- The system begins following the mouse cursor.

EditModeSystemMixin:OnDragStop()
-- Called when dragging ends. The system:
-- - Calculates new anchor relative to UIParent
-- - Checks for grid snap
-- - Saves the new position to the active layout

EditModeSystemMixin:StartResizing(direction)
-- Begin resize operation from a given edge/corner.

EditModeSystemMixin:StopResizing()
-- End resize and persist new dimensions.
```

---

## Grid, Snap & Magnet System

### Account Settings (Enum.EditModeAccountSetting)

These are global settings managed via `C_EditMode.GetAccountSettings()` / `SetAccountSetting()`:

```lua
Enum.EditModeAccountSetting = {
    ShowGrid       = 0,  -- Show alignment grid (0=off, 1=on)
    GridSpacing    = 1,  -- Grid cell size in pixels (range: typically 10-200)
    EnableSnap     = 2,  -- Enable snap-to-grid behavior (0=off, 1=on)
}
```

> **Note:** Exact enum values may vary between patches. Use `C_EditMode.GetAccountSettings()`
> to query all current settings and inspect their IDs.

### Reading/Writing Account Settings

```lua
-- Read all account settings
local settings = C_EditMode.GetAccountSettings()
for _, s in ipairs(settings) do
    print("Setting:", s.setting, "Value:", s.value)
end

-- Enable grid snap
C_EditMode.SetAccountSetting(Enum.EditModeAccountSetting.EnableSnap, 1)

-- Set grid spacing to 50 pixels
C_EditMode.SetAccountSetting(Enum.EditModeAccountSetting.GridSpacing, 50)
```

### Via LibEditModeOverride

```lua
local lib = LibStub("LibEditModeOverride-1.0")

-- Read a global setting
local snapEnabled = lib:GetGlobalSetting(Enum.EditModeAccountSetting.EnableSnap)

-- Write a global setting
lib:SetGlobalSetting(Enum.EditModeAccountSetting.GridSpacing, 75)
```

### Magnet (Magnetism) Behavior

When snap is enabled, frames "magnetize" to nearby UI elements during drag:
- **Grid snap:** Frame edges align to grid lines at the configured spacing
- **Element snap:** Frame edges magnetize to edges of nearby frames
- **Center snap:** Frame centers align with other frame centers or screen center

The magnet pull radius is part of the account settings but may not have a public enum constant
in all versions. Check `C_EditMode.GetAccountSettings()` for the full list of active settings.

---

## EditModeSettingDisplayInfoManager

Blizzard uses this internal manager to define how each setting is displayed and validated
in the EditModeSystemSettingsDialog. It maps system + setting ID to display type and constraints.

### Setting Display Types (Enum.EditModeSettingDisplayType)

```lua
Enum.EditModeSettingDisplayType = {
    Dropdown = 0,   -- Dropdown menu with named options
    Checkbox = 1,   -- On/off toggle (value: 0 or 1)
    Slider   = 2,   -- Numeric slider with min/max/step
}
```

### Setting Validation Pattern (from LibEditModeOverride source)

```lua
-- Get constraints for a specific frame+setting
local restrictions = EditModeSettingDisplayInfoManager
    .systemSettingDisplayInfo[frame.system]

for _, setup in ipairs(restrictions) do
    if setup.setting == settingID then
        if setup.type == Enum.EditModeSettingDisplayType.Dropdown then
            -- setup.options = { { value=0, text="..." }, { value=1, text="..." }, ... }
        elseif setup.type == Enum.EditModeSettingDisplayType.Checkbox then
            -- min=0, max=1
        elseif setup.type == Enum.EditModeSettingDisplayType.Slider then
            -- setup.minValue, setup.maxValue, setup.stepSize
        end
    end
end
```

---

## LibEditModeOverride — Complete API Reference

> Source: [github.com/plusmouse/LibEditModeOverride](https://github.com/plusmouse/LibEditModeOverride)

### Initialization & Readiness

```lua
local lib = LibStub("LibEditModeOverride-1.0")

lib:IsReady() : boolean
-- Returns true after EDIT_MODE_LAYOUTS_UPDATED fires (EditModeManagerFrame.accountSettings exists).
-- MUST be true before calling any other method.

lib:AreLayoutsLoaded() : boolean
-- Returns true after LoadLayouts() has been called.

lib:LoadLayouts()
-- Loads layout data from C_EditMode.GetLayouts() and reconciles with presets.
-- MUST be called before frame manipulation methods.
-- Asserts lib:IsReady() — will error if called too early.
```

### Frame Manipulation

```lua
lib:HasEditModeSettings(frame) : boolean
-- Returns true if the frame is managed by Edit Mode (has system + systemIndex).

lib:ReanchorFrame(frame, point, relativeTo, [relativePoint, offsetX, offsetY])
-- Reposition a Blizzard Edit Mode frame.
-- Asserts the active layout is editable (not a preset).
-- Updates the layout data's anchorInfo for this system.
-- Example: lib:ReanchorFrame(MainMenuBar, "TOP", UIParent, "TOP", 0, 0)

lib:SetFrameSetting(frame, setting, value)
-- Set a specific Edit Mode setting for a frame.
-- Validates value against EditModeSettingDisplayInfoManager constraints.
-- value must be a non-negative integer.
-- Errors if value is outside min/max range.

lib:GetFrameSetting(frame, setting) : number|nil
-- Read a specific setting value for a frame.
-- Returns nil if the setting doesn't exist for this system.
```

### Global Settings

```lua
lib:SetGlobalSetting(setting, value)
-- Set an account-wide Edit Mode setting.
-- Wraps C_EditMode.SetAccountSetting().

lib:GetGlobalSetting(setting) : number|nil
-- Read an account-wide setting value.
-- Iterates C_EditMode.GetAccountSettings() to find the matching setting.
```

### Layout Management

```lua
lib:GetActiveLayout() : string
-- Returns the name of the currently active layout.

lib:SetActiveLayout(layoutName)
-- Switch to a named layout. Marks the layout change as pending.
-- The switch is committed on the next SaveOnly() or ApplyChanges().

lib:CanEditActiveLayout() : boolean
-- Returns true if the active layout is NOT a preset (can be modified).

lib:DoesLayoutExist(layoutName) : boolean
-- Check if a layout with the given name exists.

lib:AddLayout(layoutType, layoutName)
-- Create a new layout (copies Modern preset as base).
-- layoutType: Enum.EditModeLayoutType.Account or .Character
-- Automatically activates the new layout.

lib:DeleteLayout(layoutName)
-- Remove a named layout. Errors on preset layouts.
-- Calls C_EditMode.OnLayoutDeleted() internally.

lib:GetEditableLayoutNames() : string[]
-- Returns array of names for all non-preset layouts.

lib:GetPresetLayoutNames() : string[]
-- Returns array of names for all preset layouts.
```

### Saving & Applying

```lua
lib:SaveOnly()
-- Saves layout data via C_EditMode.SaveLayouts().
-- Also commits pending active layout switch via C_EditMode.SetActiveLayout().
-- Does NOT trigger UI refresh.

lib:ApplyChanges()
-- Saves AND refreshes the UI by briefly showing/hiding EditModeManagerFrame.
-- Asserts not in combat (InCombatLockdown()).
-- This is the method that makes changes visually take effect without /reload.
-- Internally does:
--   1. lib:SaveOnly()
--   2. ShowUIPanel(EditModeManagerFrame) → HideUIPanel(EditModeManagerFrame)
-- The show/hide cycle forces Blizzard's code to reposition all managed frames.
```

### Typical Usage Flow

```lua
-- 1. Wait for readiness
local frame = CreateFrame("Frame")
frame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
frame:SetScript("OnEvent", function()
    if not lib:IsReady() then return end

    -- 2. Load layouts
    lib:LoadLayouts()

    -- 3. Check/create layout
    if not lib:DoesLayoutExist("MyLayout") then
        lib:AddLayout(Enum.EditModeLayoutType.Account, "MyLayout")
    end

    -- 4. Modify frames
    lib:SetActiveLayout("MyLayout")
    lib:ReanchorFrame(MinimapCluster, "TOPRIGHT", UIParent, "TOPRIGHT", -10, -10)
    lib:SetFrameSetting(MainMenuBar, 3, 8)  -- Icon size = 8

    -- 5. Save and apply
    lib:ApplyChanges()
end)
```

---

## EditModeExpanded-1.0 — Custom Frame Registration

> Source: [github.com/teelolws/EditModeExpanded](https://github.com/teelolws/EditModeExpanded)

### Basic Registration

```lua
local EME = LibStub("EditModeExpanded-1.0")

-- Minimal: just make the frame movable in Edit Mode
EME:RegisterFrame(myFrame, "My Addon Frame")

-- With options
EME:RegisterFrame(myFrame, "My Addon Frame", {
    resize = true,         -- Show resize handles in Edit Mode
    hide = true,           -- Add hide/show checkbox in Edit Mode
    scaleWithUI = true,    -- Scale proportionally with UI scale changes
})
```

### What Registration Provides

1. **Drag-to-move** during Edit Mode (position saved per layout)
2. **Resize handles** (optional) with size persisted per layout
3. **Hide checkbox** (optional) — visibility persisted per layout
4. **Blue highlight overlay** matching Blizzard's system frames
5. **Automatic save/restore** on layout switch and login
6. **Profile-aware** — different positions per Edit Mode layout

### Unregistration

```lua
EME:UnregisterFrame(myFrame)
-- Removes the frame from Edit Mode management.
-- Frame reverts to normal behavior.
```

### When NOT To Use EditModeExpanded

- If your addon already has its own Edit Mode integration (like ChattyLittleNpc does)
- If you need very custom behavior beyond move/resize/hide
- If you want to avoid the library dependency

---

## EditModeSystemSettingsDialog

The settings dialog that appears when a system is selected in Edit Mode. It shows
sliders, checkboxes, and dropdowns for the selected system's settings.

### Interacting Safely

```lua
-- Hide the dialog (useful when your addon frame is clicked)
if EditModeSystemSettingsDialog and EditModeSystemSettingsDialog.IsShown
   and EditModeSystemSettingsDialog:IsShown() then
    EditModeSystemSettingsDialog:Hide()
end

-- Check if it's showing
local isShowing = EditModeSystemSettingsDialog
    and EditModeSystemSettingsDialog.IsShown
    and EditModeSystemSettingsDialog:IsShown()
```

### ⚠️ Taint Warning

Direct manipulation of `EditModeSystemSettingsDialog` internals (adding widgets,
modifying pools, changing content) causes **taint** that can break Blizzard UI in combat.
Use libraries (LibEQOL, EditModeExpanded) that handle this safely.

---

## EditModeUnsavedChangesDialog

Blizzard shows this dialog when the user tries to exit Edit Mode with unsaved changes.

```lua
-- Check for unsaved changes before programmatic exit
if EditModeManagerFrame:HasActiveChanges() then
    -- The dialog will appear automatically when ExitEditMode is called
    -- Or you can programmatically save/revert first:
    EditModeManagerFrame:SaveLayoutChanges()  -- Save
    -- OR
    EditModeManagerFrame:RevertAllChanges()   -- Discard
end
```

### For Addon Integration

Your addon should handle the case where Edit Mode exits via the unsaved changes dialog:

```lua
-- Hook both exit paths
hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
    MyAddon:OnEditModeExit()
end)

-- Also hook RevertAllChanges in case layout data changes
hooksecurefunc(EditModeManagerFrame, "RevertAllChanges", function()
    -- Layout was reverted — re-apply our per-layout settings
    local name = MyAddon:GetActiveLayoutName()
    MyAddon:ApplyLayout(name)
end)
```

---

## Layout Macros

### Toggle Between Two Layouts

```lua
-- Macro to cycle layouts by name:
/run x={"RaidUI","PvPUI"} if not p or p==#x then p=0 end p=p+1;
/run for i,l in ipairs(EditModeManagerFrame:GetLayouts()) do
    if l.layoutName==x[p] then EditModeManagerFrame:SelectLayout(i) end end
```

### Switch to Specific Layout by Name

```lua
/run for i,l in ipairs(EditModeManagerFrame:GetLayouts()) do
    if l.layoutName=="MyLayout" then EditModeManagerFrame:SelectLayout(i) break end end
```

### Switch to Layout by Index

```lua
/run EditModeManagerFrame:SelectLayout(3)
-- Or via the API:
/run C_EditMode.SetActiveLayout(3)
```

### Enter/Exit Edit Mode via Macro

```lua
-- Toggle Edit Mode
/run if EditModeManagerFrame:IsShown() then
    HideUIPanel(EditModeManagerFrame)
else ShowUIPanel(EditModeManagerFrame) end
```

---

## Frame Properties for Edit Mode

Blizzard Edit Mode checks these properties on frames:

```lua
frame.system        -- Enum.EditModeSystem value (e.g., 0 for ActionBar)
frame.systemIndex   -- Sub-index for multi-instance systems (e.g., 1-8 for action bars)
frame.isSelected    -- Boolean: whether this system is currently selected
```

### EditModePresetLayoutManager

```lua
EditModePresetLayoutManager:GetCopyOfPresetLayouts()
-- Returns a copy of the preset layouts (Modern, Classic).
-- Used internally by LibEditModeOverride to prepend presets to the layouts list
-- so that indexing aligns with C_EditMode.GetLayouts().activeLayout.
```

### Enum.EditModePresetLayoutsMeta

```lua
Enum.EditModePresetLayoutsMeta.NumValues
-- Number of built-in preset layouts (typically 2: Modern + Classic).
-- Used to calculate layout index offsets.
```

---

## Addon Support Matrix

| Addon/Library | Custom Frames | Blizzard Frames | Settings Dialog | Per-Layout Save | Resize | Keyboard Nudge |
|---------------|:---:|:---:|:---:|:---:|:---:|:---:|
| **Direct API (C_EditMode)** | ❌ | ✅ (read) | ❌ | ✅ | ❌ | ❌ |
| **EditModeExpanded-1.0** | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **LibEditModeOverride** | ❌ | ✅ (modify) | ❌ | ✅ | ❌ | ❌ |
| **LibEditMode** | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **LibEQOL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **FerrozEditModeLib** | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **Edit Mode Tweaks** (addon) | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| **ChattyLittleNpc** (built-in) | ✅ | ❌ | ✅ (own panel) | ✅ | ✅ | ❌ |

### Key Differences

- **EditModeExpanded** = "Make my frame work with Edit Mode" (registration API)
- **LibEditModeOverride** = "Move/configure Blizzard's frames programmatically" (manipulation API)
- **LibEQOL** = "Full Edit Mode toolkit" (overlay, nudge, settings widgets, selection)
- **ChattyLittleNpc** = "Custom implementation" (own overlay, own settings panel, per-layout persistence)
