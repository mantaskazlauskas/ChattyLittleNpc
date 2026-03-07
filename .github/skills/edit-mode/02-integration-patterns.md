# Edit Mode Integration Patterns

> Hooks, custom frame integration, overlays, per-layout persistence, and combat considerations.
> Includes ChattyLittleNpc-specific patterns.

---

## Detecting Edit Mode State Changes

There are **no events** for entering/exiting Edit Mode. Use `hooksecurefunc`:

```lua
-- REQUIRED: Hook EditModeManagerFrame methods
hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
    -- Player entered Edit Mode
    MyAddon:OnEditModeEnter()
end)

hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
    -- Player exited Edit Mode
    MyAddon:OnEditModeExit()
end)

-- OPTIONAL: Listen for layout changes (fires on save, switch, import, login)
local frame = CreateFrame("Frame")
frame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
frame:SetScript("OnEvent", function(self, event, layoutInfo, reconcileLayouts)
    if reconcileLayouts then
        -- Server reconcile (login/reload) — apply stored per-layout settings
        MyAddon:ApplyLayoutSettings(layoutInfo)
    else
        -- User saved/switched layout — persist current settings
        MyAddon:SaveCurrentSettings()
    end
end)
```

### Clearing Blizzard's Selection

When your addon frame is selected in Edit Mode, you may need to clear Blizzard's own
selection to avoid visual conflicts:

```lua
local function clearBlizzardSelection()
    if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
        EditModeManagerFrame:ClearSelectedSystem()
    end
    if EditModeSystemSettingsDialog and EditModeSystemSettingsDialog.IsShown
       and EditModeSystemSettingsDialog:IsShown() then
        EditModeSystemSettingsDialog:Hide()
    end
end
```

---

## Identifying the Active Layout

`GetLayouts().activeLayout` includes hidden preset layouts, creating an offset issue:

```lua
local HIDDEN_BASE_LAYOUTS = 2  -- Modern (0) and Classic (1) are hidden

function MyAddon:GetActiveLayoutName()
    local ok, layouts = pcall(C_EditMode.GetLayouts)
    if not ok or not layouts or not layouts.layouts then return nil end

    local list = layouts.layouts
    local idx = tonumber(layouts.activeLayout)
    if not idx then return nil end

    -- Try direct index first
    if list[idx] and list[idx].layoutName then
        return list[idx].layoutName
    end

    -- Adjust for hidden Modern/Classic presets
    local adj = idx - HIDDEN_BASE_LAYOUTS
    if adj >= 1 and list[adj] and list[adj].layoutName then
        return list[adj].layoutName
    end

    -- Fallback: scan for active flag
    for _, l in ipairs(list) do
        if l.isActive or l.active or l.isLayoutActive then
            return l.layoutName
        end
    end

    -- Last resort: first layout
    return list[1] and list[1].layoutName or nil
end
```

> **Why the offset?** Blizzard's `activeLayout` uses a global index (0-based internally)
> that counts Modern and Classic presets. But `GetLayouts()` only returns user-created
> layouts, so index 3 (the first user layout) maps to `layouts[1]`.

---

## Per-Layout Settings Persistence

Store addon settings keyed by layout name in saved variables:

```lua
-- Data structure in SavedVariables
-- db.profile.editModeLayouts = {
--     ["MyRaidLayout"] = {
--         frameScale = 1.2,
--         frameSize = { width = 475, height = 310 },
--         framePos = { point = "CENTER", relativePoint = "CENTER", x = 500, y = 0 },
--         -- ... any per-layout addon settings
--     },
--     ["MyPvPLayout"] = { ... },
-- }

function MyAddon:PersistCurrentToLayout()
    local name = self:GetActiveLayoutName()
    if not name then return end

    local store = db.profile.editModeLayouts or {}
    db.profile.editModeLayouts = store

    local bucket = store[name] or {}
    bucket.frameScale = db.profile.frameScale
    bucket.frameSize = {
        width = db.profile.frameSize.width,
        height = db.profile.frameSize.height,
    }

    -- Save frame position
    if self.DisplayFrame then
        local p, _, r, x, y = self.DisplayFrame:GetPoint(1)
        bucket.framePos = { point = p, relativePoint = r, x = x, y = y }
    end

    store[name] = bucket
end

function MyAddon:ApplyLayout(name)
    if not name then return end
    local data = db.profile.editModeLayouts and db.profile.editModeLayouts[name]
    if not data then return end

    -- Apply stored settings
    if data.frameScale then
        db.profile.frameScale = data.frameScale
        self:ApplyFrameScale()
    end
    if data.frameSize then
        db.profile.frameSize = data.frameSize
        self.DisplayFrame:SetSize(data.frameSize.width, data.frameSize.height)
    end
    if data.framePos and self.DisplayFrame then
        self.DisplayFrame:ClearAllPoints()
        self.DisplayFrame:SetPoint(
            data.framePos.point, UIParent,
            data.framePos.relativePoint,
            data.framePos.x or 0, data.framePos.y or 0
        )
    end
end
```

### Opt-Out System

Let users exclude specific settings from per-layout persistence:

```lua
-- db.profile.editModeExclude = {
--     frameScale = false,        -- include by default
--     frameSize = false,
--     framePos = true,           -- user opted out — position stays global
-- }

function MyAddon:PersistCurrentToLayout()
    local exclude = db.profile.editModeExclude or {}
    local bucket = store[name] or {}

    if not exclude.frameScale then bucket.frameScale = db.profile.frameScale end
    if not exclude.frameSize then bucket.frameSize = { ... } end
    if not exclude.framePos then bucket.framePos = { ... } end

    store[name] = bucket
end
```

---

## Edit Mode Overlay & Drag/Resize

Show a visual overlay when Edit Mode is active:

```lua
function MyAddon:OnEditModeEnter()
    self._editMode = true
    local frame = self.DisplayFrame
    if not frame then return end

    -- Force frame visible for positioning
    frame:Show()
    frame:EnableMouse(true)

    -- Create or show highlight overlay
    if not self._editOverlay then
        self._editOverlay = CreateFrame("Frame", nil, frame)
        self._editOverlay:SetAllPoints(frame)
        self._editOverlay:SetFrameLevel(frame:GetFrameLevel() + 10)

        -- Blue highlight border (mimics Blizzard's style)
        local border = self._editOverlay:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints()
        border:SetColorTexture(0.2, 0.4, 0.8, 0.3)  -- Semi-transparent blue
        self._editOverlay._border = border

        -- "Chatty Little NPC" label
        local label = self._editOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        label:SetPoint("CENTER")
        label:SetText("Chatty Little NPC")
        label:SetTextColor(1, 1, 1, 0.9)
    end
    self._editOverlay:Show()

    -- Enable dragging
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        MyAddon:PersistCurrentToLayout()
    end)
end

function MyAddon:OnEditModeExit()
    self._editMode = false
    if self._editOverlay then self._editOverlay:Hide() end

    local frame = self.DisplayFrame
    if not frame then return end

    -- Save final position to current layout
    self:PersistCurrentToLayout()

    -- Disable drag
    frame:RegisterForDrag()
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)
end
```

### Resize Handle in Edit Mode

```lua
-- Add a resize grip visible only in Edit Mode
local grip = CreateFrame("Button", nil, frame)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT")
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:Hide()  -- Only shown in Edit Mode

grip:SetScript("OnMouseDown", function()
    frame:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    MyAddon:PersistCurrentToLayout()
    MyAddon:SaveSizeForActiveLayout()
end)
```

---

## Layout Import/Export with Addon Data

Bundle addon-specific settings into layout strings:

```lua
local BUNDLE_MARK = "#CLN1#"

function MyAddon:ExportLayoutWithSettings()
    local layoutName = self:GetActiveLayoutName()
    if not layoutName then return nil end

    local store = db.profile.editModeLayouts or {}
    local bucket = store[layoutName]
    if not bucket then return nil end

    -- Serialize addon settings as JSON-like string
    local parts = {}
    if bucket.frameScale then table.insert(parts, "s=" .. bucket.frameScale) end
    if bucket.frameSize then
        table.insert(parts, "w=" .. bucket.frameSize.width)
        table.insert(parts, "h=" .. bucket.frameSize.height)
    end
    if bucket.framePos then
        table.insert(parts, "p=" .. bucket.framePos.point)
        table.insert(parts, "rp=" .. bucket.framePos.relativePoint)
        table.insert(parts, "x=" .. (bucket.framePos.x or 0))
        table.insert(parts, "y=" .. (bucket.framePos.y or 0))
    end

    return BUNDLE_MARK .. table.concat(parts, ";") .. BUNDLE_MARK
end

function MyAddon:ImportLayoutSettings(bundleString)
    if not bundleString or not bundleString:find(BUNDLE_MARK, 1, true) then return nil end
    local inner = bundleString:match(BUNDLE_MARK .. "(.-)" .. BUNDLE_MARK)
    if not inner then return nil end

    local result = {}
    for kv in inner:gmatch("[^;]+") do
        local k, v = kv:match("^(.-)=(.+)$")
        if k and v then result[k] = tonumber(v) or v end
    end
    return result
end
```

---

## Community Libraries

### EditModeExpanded-1.0

Best for **registering custom addon frames** with Edit Mode:

```lua
local EME = LibStub("EditModeExpanded-1.0")

-- Register your frame — it becomes movable/resizable in Edit Mode
EME:RegisterFrame(myFrame, "My Addon Frame", {
    resize = true,      -- Allow resize in Edit Mode
    hide = true,        -- Allow hiding via Edit Mode
})
-- Frame position/size now persisted per Edit Mode profile automatically
```

- **GitHub:** https://github.com/teelolws/EditModeExpanded
- **CurseForge:** https://www.curseforge.com/wow/addons/edit-mode-expanded

### LibEditModeOverride

Best for **manipulating Blizzard's own Edit Mode frames**:

```lua
local LibEMO = LibStub("LibEditModeOverride-1.0")

-- Wait for Edit Mode data to be ready
-- (call after EDIT_MODE_LAYOUTS_UPDATED fires)
if LibEMO:IsReady() then
    LibEMO:LoadLayouts()
    LibEMO:ReanchorFrame(MainMenuBar, "TOP", UIParent)
    LibEMO:SetFrameSetting(MainMenuBar, settingID, value)
    LibEMO:ApplyChanges()
end
```

- **GitHub:** https://github.com/plusmouse/LibEditModeOverride
- **CurseForge:** https://www.curseforge.com/wow/addons/libeditmodeoverride

### LibEditMode

Minimal library focused on taint-safe custom frame integration:

- **GitHub:** https://github.com/p3lim-wow/LibEditMode
- **Wago:** https://addons.wago.io/addons/libeditmode

### LibEQOL

Modern QoL library with EditMode helper for overlay, highlight, selection, and keyboard nudging:

- **GitHub:** https://github.com/R41z0r/LibEQOL

### FerrozEditModeLib

Simple registration API with enter/exit callbacks:

```lua
FerrozEditModeLib:Register(myFrame, settingsTable, onEnterFunc, onExitFunc)
```

- **CurseForge:** https://www.curseforge.com/wow/addons/ferrozeditmodelib

---

## Taint & Combat Considerations

### Combat Lockdown

```lua
-- NEVER reposition frames during combat
if InCombatLockdown() then
    -- Queue the change for after combat
    self._pendingLayoutApply = layoutName
    return
end

-- Apply pending changes after combat
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function()
    if self._pendingLayoutApply then
        self:ApplyLayout(self._pendingLayoutApply)
        self._pendingLayoutApply = nil
    end
end)
```

### Taint from Blizzard Hooks

```lua
-- SAFE: hooksecurefunc does NOT taint the original function
hooksecurefunc(EditModeManagerFrame, "EnterEditMode", myCallback)

-- UNSAFE: Direct replacement taints the secure function
EditModeManagerFrame.EnterEditMode = myOverride  -- DON'T DO THIS

-- SAFE: Use pcall for protected API calls
local ok, layouts = pcall(C_EditMode.GetLayouts)
```

### Timing: When Is the API Ready?

```lua
-- C_EditMode.GetLayouts() returns empty/nil before EDIT_MODE_LAYOUTS_UPDATED fires.
-- Always wait for the event before querying layouts.

local function OnEvent(self, event, layoutInfo, reconcileLayouts)
    if event == "EDIT_MODE_LAYOUTS_UPDATED" then
        -- NOW it's safe to call C_EditMode.GetLayouts()
        MyAddon._editModeReady = true
        MyAddon:ApplyLayout(MyAddon:GetActiveLayoutName())
    end
end
```

---

## Midnight (12.0) Specific Changes

### New Edit Mode Systems

Four new `Enum.EditModeSystem` values added in 12.0:

| System | ID | Description |
|--------|----|-------------|
| CooldownViewer | 20 | Built-in cooldown tracking (was 11.1.5) |
| PersonalResourceDisplay | 21 | Class resource display (Holy Power, Combo Points, etc.) |
| EncounterEvents | 22 | Boss encounter event tracking |
| DamageMeter | 23 | Built-in damage/healing meter |

### Combat Addon "Black Box"

Midnight restricts real-time combat data access. This does **NOT** affect:
- UI positioning addons (like ChattyLittleNpc)
- Edit Mode integration
- Non-combat QoL addons
- Layout management
- Frame customization

### Enhanced Native UI

More UI elements are now configurable natively through Edit Mode, reducing the need
for addons like MoveAnything. Players who previously needed addon-based frame
positioning can now use Edit Mode directly for most built-in frames.

---

## ChattyLittleNpc Integration Reference

The addon's Edit Mode integration lives in:

| File | Purpose |
|------|---------|
| `src/ReplayFrame/EditModeIntegration.lua` | Core integration: per-layout persistence, overlay, drag/resize, bundle export/import |
| `src/ReplayFrame/EditPanel.lua` | Settings panel with sliders for scale, size, model height, offsets, text scale |
| `src/ReplayFrame/Position.lua` | Frame position save/load, compact mode, reparenting |

### Key Integration Points

```lua
-- EditModeIntegration.lua manages:
ReplayFrame.EditModeIntegration:GetActiveLayoutName()   -- Identify current layout
ReplayFrame.EditModeIntegration:PersistCurrentToLayout() -- Save settings to layout bucket
ReplayFrame.EditModeIntegration:ApplyLayout(name)        -- Restore settings from layout bucket

-- Per-layout settings stored:
-- db.profile.editModeLayouts[layoutName] = {
--     frameScale, queueTextScale, frameSize, npcModelFrameHeight,
--     modelOffsetX, modelOffsetY, framePos
-- }

-- Opt-out config:
-- db.profile.editModeExclude = {
--     frameScale, queueTextScale, frameSize, npcModelFrameHeight,
--     modelOffset, framePos
-- }
```

### Hooks Registered

```lua
-- In Main.lua OnEnable or Init.lua:
hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
    ReplayFrame.EditModeIntegration:OnEnterEditMode()
end)

hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
    ReplayFrame.EditModeIntegration:OnExitEditMode()
end)

-- Event listener:
events:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function(_, layoutInfo, reconcile)
    ReplayFrame.EditModeIntegration:OnLayoutsUpdated(layoutInfo, reconcile)
end)
```

---

## Anti-Patterns

| ❌ Don't | ✅ Do |
|---------|-------|
| Call `C_EditMode.SaveLayouts()` from tainted code | Use `pcall` and only call from clean execution paths |
| Reposition frames during `InCombatLockdown()` | Queue changes for `PLAYER_REGEN_ENABLED` |
| Replace `EditModeManagerFrame` methods | Use `hooksecurefunc` (read-only hooks) |
| Assume `GetLayouts()` is ready at `ADDON_LOADED` | Wait for `EDIT_MODE_LAYOUTS_UPDATED` event |
| Use `activeLayout` directly as index into `layouts[]` | Subtract `HIDDEN_BASE_LAYOUTS` (2) or scan for active flag |
| Store per-layout data by index number | Store by layout **name** (indices change on create/delete) |
| Interact with `EditModeSystemSettingsDialog` directly | Use helper libraries or `ClearSelectedSystem()` only |
| Forget to save on Exit | Always `PersistCurrentToLayout()` in the `ExitEditMode` hook |
