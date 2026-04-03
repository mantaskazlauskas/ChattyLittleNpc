# Blizzard Edit Mode — Source Code Reference

> **Source:** [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) — `live` branch, commit `3fefc3a` (Patch 11.1.5 / 11.1.7 era)
> **Path prefix:** `Interface/AddOns/Blizzard_EditMode/Shared/`
> **Note:** Function signatures may shift in Midnight (12.0). Verify against live client FrameXML.

---

## Table of Contents

1. [EditModeSystemTemplates.lua](#1-editmodesystemtemplateslua)
2. [EditModeManager.lua](#2-editmodemanagerlua)
3. [EditModeSettingDisplayInfo.lua](#3-editmodesettingdisplayinfolua)
4. [EditModeUtil.lua](#4-editmodeutillua)

---

## 1. EditModeSystemTemplates.lua

The core mixin applied to every draggable/configurable Edit Mode system frame. Defines selection, snapping, movement, settings, and per-system-type overrides.

### Constants & Locals

| Name | Description |
|------|-------------|
| `SELECTION_PADDING` | `2` — pixel padding added around selection frames for clamp calculations |
| `movementKeys` | Table `{UP=true, DOWN=true, LEFT=true, RIGHT=true}` — keys that trigger pixel nudge |

---

### EditModeSystemMixin (base mixin for all systems)

#### Lifecycle & Initialization

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:OnSystemLoad()` | Primary init: overrides SetScale/SetPoint/ClearAllPoints/Show/Hide, registers with manager, creates snappedFrames table, loads settingDisplayInfoMap |
| `EditModeSystemMixin:SetupVisibilityFunctionOverrides()` | Replaces SetShown/Hide with override versions that handle snap-break on hide |
| `EditModeSystemMixin:OnSystemHide()` | Clears selection on hide; calls UIParentManagedFrameMixin.OnHide for managed frames |
| `EditModeSystemMixin:IsInitialized()` | Returns `self.systemInfo ~= nil` |
| `EditModeSystemMixin:OnUpdateSystem(anySettingsDirty)` | Override hook — called after full system update |
| `EditModeSystemMixin:PrepareForSave()` | Pre-save: breaks snapped frames if needed, forces top-left/right anchor |

#### Movement & Keyboard

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:ProcessMovementKey(key)` | Nudges frame 1px (or 10px with shift); breaks from frame manager if managed and default |
| `EditModeSystemMixin:OnKeyDown(key)` | Records key in `self.downKeys`, dispatches to ProcessMovementKey |
| `EditModeSystemMixin:OnKeyUp(key)` | Clears key from `self.downKeys` |
| `EditModeSystemMixin:ClearDownKeys()` | Resets `self.downKeys = {}` |
| `EditModeSystemMixin:IsShiftKeyDown()` | Checks LSHIFT or RSHIFT in downKeys |

#### Scale & Anchor Overrides

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:SetScaleOverride(newScale)` | Adjusts all anchor offsets proportionally when scale changes; manages UIParent frame positions |
| `EditModeSystemMixin:SetPointOverride(point, relativeTo, relativePoint, offsetX, offsetY)` | Calls base SetPoint, then SetSnappedToFrame and notifies manager of anchor change |
| `EditModeSystemMixin:ClearAllPointsOverride()` | Clears points and frame snap |
| `EditModeSystemMixin:HideOverride()` | Breaks snapped frames on hide if needed, then calls base Hide |
| `EditModeSystemMixin:SetShownOverride(shown)` | Routes to Show() or Hide() |

#### Selection & Highlight System

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:UpdateClampOffsets()` | Calculates clamp rect insets from Selection frame bounds |
| `EditModeSystemMixin:AnchorSelectionFrame()` | Override point — calls UpdateClampOffsets (subclasses set Selection anchor points) |
| `EditModeSystemMixin:ClearHighlight()` | Clears selection, hides Selection frame, unregisters from magnetism |
| `EditModeSystemMixin:HighlightSystem()` | Stops dragging, makes immovable, shows highlighted Selection, registers magnetism |
| `EditModeSystemMixin:SelectSystem()` | Makes movable, shows selected Selection, attaches settings dialog, registers magnetism |
| `EditModeSystemMixin:SetSelectionShown(shown)` | Shows/hides Selection frame |
| `EditModeSystemMixin:ShowEditInstructions(shown)` | Forwards to `self.Selection:ShowEditInstructions(shown)` |
| `EditModeSystemMixin:UpdateMagnetismRegistration()` | Registers/unregisters from EditModeMagnetismManager based on visibility + highlight state |

#### Edit Mode Enter/Exit

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:OnEditModeEnter()` | Highlights system unless `self.defaultHideSelection` |
| `EditModeSystemMixin:OnEditModeExit()` | Clears highlight, stops moving, hides settings dialog |
| `EditModeSystemMixin:CanBeMoved()` | Returns `self.isSelected and not self.isLocked` |
| `EditModeSystemMixin:IsInDefaultPosition()` | Returns `self.systemInfo.isInDefaultPosition` |
| `EditModeSystemMixin:IsEditModeDragging()` | Delegates to `self.Selection:IsDragging()` |

#### Drag & Drop

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:OnDragStart()` | Breaks from frame manager, clears snap, starts moving, sets snap preview frame |
| `EditModeSystemMixin:OnDragStop()` | Clears snap preview, stops moving, applies magnetism if snap enabled, notifies position change |
| `EditModeSystemMixin:OnSystemPositionChange()` | Delegates to `EditModeManagerFrame:OnSystemPositionChange(self)` |
| `EditModeSystemMixin:OnAnyEditModeSystemAnchorChanged()` | Override hook — called when any system anchor changes |

#### Snap & Magnet System

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:GetScaledSelectionCenter()` | Returns Selection center × scale |
| `EditModeSystemMixin:GetScaledCenter()` | Returns frame center × scale |
| `EditModeSystemMixin:GetScaledSelectionSides()` | Returns left, right, bottom, top of Selection × scale |
| `EditModeSystemMixin:GetLeftOffset()` | Selection point 1 x-offset minus padding |
| `EditModeSystemMixin:GetRightOffset()` | Selection point 2 x-offset plus padding |
| `EditModeSystemMixin:GetTopOffset()` | Selection point 1 y-offset plus padding |
| `EditModeSystemMixin:GetBottomOffset()` | Selection point 2 y-offset minus padding |
| `EditModeSystemMixin:GetSelectionOffset(point, forYOffset)` | Resolves offset for a named anchor point (LEFT/RIGHT/TOP/BOTTOM/corners/CENTER) |
| `EditModeSystemMixin:GetCombinedSelectionOffset(frameInfo, forYOffset)` | Computes snap offset combining both frame's selection offsets |
| `EditModeSystemMixin:GetCombinedCenterOffset(frame)` | Returns center-to-center offset / scale |
| `EditModeSystemMixin:GetSnapOffsets(frameInfo)` | Calculates final (offsetX, offsetY) for a snap operation |
| `EditModeSystemMixin:SnapToFrame(frameInfo)` | Clears points, sets point using snap offsets relative to target frame |
| `EditModeSystemMixin:AddSnappedFrame(frame)` | Adds frame to `self.snappedFrames` |
| `EditModeSystemMixin:RemoveSnappedFrame(frame)` | Removes frame from `self.snappedFrames` |
| `EditModeSystemMixin:BreakSnappedFrames()` | Calls BreakFrameSnap on all frames snapped to this one |
| `EditModeSystemMixin:ShouldBreakSnappedFramesOnHide()` | Returns true if this is a LayoutFrame |
| `EditModeSystemMixin:SetSnappedToFrame(frame)` | Records that this frame is snapped to another |
| `EditModeSystemMixin:ClearFrameSnap()` | Removes self from snapped-to frame's snap list |
| `EditModeSystemMixin:BreakFrameSnap(deltaX, deltaY)` | Re-anchors frame to UIParent TOPLEFT/TOPRIGHT with optional pixel delta |
| `EditModeSystemMixin:IsFrameAnchoredToMe(frame)` | Recursively checks if a frame's anchor chain leads to self |
| `EditModeSystemMixin:GetFrameMagneticEligibility(systemFrame)` | Returns (horizontalEligible, verticalEligible) — whether this frame can snap to systemFrame |

#### Spatial Queries (for magnetism)

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:IsToTheLeftOfFrame(systemFrame)` | Right edge < other's left edge |
| `EditModeSystemMixin:IsToTheRightOfFrame(systemFrame)` | Left edge > other's right edge |
| `EditModeSystemMixin:IsAboveFrame(systemFrame)` | Bottom > other's top |
| `EditModeSystemMixin:IsBelowFrame(systemFrame)` | Top < other's bottom |
| `EditModeSystemMixin:IsVerticallyAlignedWithFrame(systemFrame)` | Overlapping vertical range |
| `EditModeSystemMixin:IsHorizontallyAlignedWithFrame(systemFrame)` | Overlapping horizontal range |

#### Settings System

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:ConvertSettingDisplayValueToRawValue(setting, value)` | Converts display value to raw via settingDisplayInfoMap |
| `EditModeSystemMixin:UpdateSettingMap(updateDirtySettings)` | Rebuilds `self.settingMap` from systemInfo.settings |
| `EditModeSystemMixin:UpdateDirtySettings(oldSettingsMap)` | Marks changed settings in `self.dirtySettings` |
| `EditModeSystemMixin:MarkAllSettingsDirty()` | Clears settingMap to force full update |
| `EditModeSystemMixin:IsSettingDirty(setting)` | Checks dirtySettings table |
| `EditModeSystemMixin:ClearDirtySetting(setting)` | Removes from dirtySettings |
| `EditModeSystemMixin:AnySettingsDirty()` | Returns true if any dirty setting exists |
| `EditModeSystemMixin:HasSetting(setting)` | Checks settingMap; handles composite number settings |
| `EditModeSystemMixin:HasCompositeNumberSetting(setting)` | Checks if a composite (hundreds + tens/ones) setting exists |
| `EditModeSystemMixin:GetSettingValue(setting, useRawValue)` | Returns setting value (raw or display); handles composites |
| `EditModeSystemMixin:GetSettingValueBool(setting, useRawValue)` | Returns `value == 1` |
| `EditModeSystemMixin:DoesSettingValueEqual(setting, value)` | Raw value equality check |
| `EditModeSystemMixin:DoesSettingDisplayValueEqual(setting, value)` | Display value equality check |
| `EditModeSystemMixin:GetCompositeNumberSettingValue(setting, useRawValue)` | Combines hundreds + tens/ones sub-settings |
| `EditModeSystemMixin:TrySetCompositeNumberSettingValue(setting, newValue)` | Splits value into hundreds and tens/ones sub-settings |
| `EditModeSystemMixin:UpdateSystemSettingValue(setting, newValue)` | Converts and applies new value to systemInfo |
| `EditModeSystemMixin:UpdateSystemSetting(setting, entireSystemUpdate)` | Marks dirty, updates map, anchors, dialog; mirrors setting |
| `EditModeSystemMixin:UpdateSystem(systemInfo)` | Full system update: saves, rebuilds settings, applies anchor, updates all settings |
| `EditModeSystemMixin:AreAllSystemSettingsDefault()` | Compares all settings against preset defaults |
| `EditModeSystemMixin:IsSystemSettingDefault(systemSetting)` | Single setting default check |
| `EditModeSystemMixin:UseSettingAltName(setting)` | Override hook for alternate setting names |
| `EditModeSystemMixin:UpdateDisplayInfoOptions(displayInfo)` | Override hook to modify display options dynamically |
| `EditModeSystemMixin:ShouldShowSetting(setting)` | Override hook to control setting visibility |

#### Position & Layout

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:ResetToDefaultPosition()` | Restores default anchor, breaks snaps, applies anchor |
| `EditModeSystemMixin:GetManagedFrameContainer()` | Returns UIParentBottomManagedFrameContainer, Right, or PlayerFrame container |
| `EditModeSystemMixin:BreakFromFrameManager()` | Removes from managed container, reparents to UIParent |
| `EditModeSystemMixin:ApplySystemAnchor()` | Positions frame from systemInfo.anchorInfo; handles managed frames and action bars |
| `EditModeSystemMixin:SetHasActiveChanges(hasActiveChanges)` | Sets flag, notifies manager |
| `EditModeSystemMixin:HasActiveChanges()` | Returns `self.hasActiveChanges` |
| `EditModeSystemMixin:GetSystemName()` | Returns system name string (optionally with systemIndex suffix) |

#### Dialog & Buttons

| Signature | Description |
|-----------|-------------|
| `EditModeSystemMixin:SetupSettingsDialogAnchor()` | Default: BOTTOMRIGHT of UIParent with offset |
| `EditModeSystemMixin:ShouldResetSettingsDialogAnchors(oldSelectedSystemFrame)` | Returns true if system type changed |
| `EditModeSystemMixin:GetSettingsDialogAnchor()` | Returns `self.settingsDialogAnchor` |
| `EditModeSystemMixin:AddExtraButtons(extraButtonPool)` | Creates "Reset Position" button; returns true |

---

### EditModeActionBarSystemMixin

Extends EditModeSystemMixin for action bars.

| Signature | Description |
|-----------|-------------|
| `EditModeActionBarSystemMixin:UpdateSystem(systemInfo)` | Base update + RefreshGridLayout, RefreshDividers, RefreshBarArt |
| `EditModeActionBarSystemMixin:OnEditModeEnter()` | Base enter + UpdateVisibility |
| `EditModeActionBarSystemMixin:OnEditModeExit()` | Base exit + UpdateVisibility |
| `EditModeActionBarSystemMixin:OnSystemPositionChange()` | Base + RefreshBarArt (Classic bar art depends on position) |
| `EditModeActionBarSystemMixin:ApplySystemAnchor()` | Base + RefreshBarArt |
| `EditModeActionBarSystemMixin:OnAnyEditModeSystemAnchorChanged()` | Updates spell flyout direction |
| `EditModeActionBarSystemMixin:MarkGridLayoutDirty()` | Sets `self.gridLayoutDirty = true` |
| `EditModeActionBarSystemMixin:RefreshGridLayout()` | Calls UpdateGridLayout if dirty |
| `EditModeActionBarSystemMixin:UpdateGridLayout()` | ActionBarMixin.UpdateGridLayout + manager layout update |
| `EditModeActionBarSystemMixin:MarkDividersDirty()` | Sets `self.dividersDirty = true` |
| `EditModeActionBarSystemMixin:RefreshDividers()` | Calls UpdateDividers if dirty |
| `EditModeActionBarSystemMixin:MarkBarArtDirty()` | Sets `self.barArtDirty = true` |
| `EditModeActionBarSystemMixin:RefreshBarArt(force)` | Updates end caps and background art |
| `EditModeActionBarSystemMixin:UpdateSystemSettingOrientation()` | Sets isHorizontal, updates Selection vertical state, marks grid/dividers/art dirty |
| `EditModeActionBarSystemMixin:UpdateSystemSettingNumRows()` | Sets numRows, marks grid/dividers/art dirty |
| `EditModeActionBarSystemMixin:UpdateSystemSettingNumIcons()` | Sets numButtonsShowable, updates shown buttons, marks dirty |
| `EditModeActionBarSystemMixin:UpdateSystemSettingIconSize()` | Applies icon scale to action buttons |
| `EditModeActionBarSystemMixin:UpdateSystemSettingIconPadding()` | Sets buttonPadding, marks grid/dividers dirty |
| `EditModeActionBarSystemMixin:UpdateSystemSettingHideBarArt()` | Toggles BorderArt visibility, updates button art |
| `EditModeActionBarSystemMixin:UpdateSystemSettingHideBarScrolling()` | Toggles ActionBarPageNumber visibility |
| `EditModeActionBarSystemMixin:UpdateSystemSettingVisibleSetting()` | Sets visibility mode: Always/InCombat/OutOfCombat/Hidden |
| `EditModeActionBarSystemMixin:UpdateSystemSettingAlwaysShowButtons()` | Toggles ShowGrid for empty slots |
| `EditModeActionBarSystemMixin:UpdateSystemSetting(setting, entireSystemUpdate)` | Dispatcher for all action bar settings |
| `EditModeActionBarSystemMixin:UseSettingAltName(setting)` | NumRows uses alt name when vertical |
| `EditModeActionBarSystemMixin:AddExtraButtons(extraButtonPool)` | Adds Quick Keybind Mode + Action Bar Settings buttons |

---

### EditModeUnitFrameSystemMixin

Extends EditModeSystemMixin for unit frames (Player, Target, Focus, Party, Raid, Boss, Arena, Pet).

| Signature | Description |
|-----------|-------------|
| `EditModeUnitFrameSystemMixin:AddExtraButtons(extraButtonPool)` | Adds Raid Frame Settings button for raid/raid-style party |
| `EditModeUnitFrameSystemMixin:ShouldResetSettingsDialogAnchors(...)` | Always returns true |
| `EditModeUnitFrameSystemMixin:UseCombinedGroups()` | Checks if raid display is CombineGroups mode |
| `EditModeUnitFrameSystemMixin:UseSettingAltName(setting)` | RowSize uses alt when CombineGroupsVertical |
| `EditModeUnitFrameSystemMixin:ShouldShowSetting(setting)` | Complex conditional visibility for party/raid-specific settings |
| `EditModeUnitFrameSystemMixin:AnchorSelectionFrame()` | Per-systemIndex selection frame anchoring with offsets |
| `EditModeUnitFrameSystemMixin:SetupSettingsDialogAnchor()` | Per-systemIndex dialog positioning |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingBuffsOnTop()` | Sets buffsOnTop, updates auras |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingUseLargerFrame()` | Toggles large frame for Focus/Boss |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingUseRaidStylePartyFrames()` | Refreshes party/raid frame display |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingShowPartyFrameBackground()` | Updates party background |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingUseHorizontalGroups()` | Updates raid container flow |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingCastBarOnSide()` | Sets cast bar position |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingViewRaidSize()` | Updates raid container |
| `EditModeUnitFrameSystemMixin:UpdateCompactRaidFrameContainerSetting(...)` | Applies multiple settings to CRF container |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingFrameWidth()` | Updates compact unit frame width |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingFrameHeight()` | Updates compact unit frame height |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingDisplayBorder()` | Updates raid group borders |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingAuraOrganizationType()` | Updates aura layout mode |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingIconSize()` | Updates aura icon size |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingOpacity()` | Sets frame alpha from Opacity setting |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingRaidGroupDisplayType()` | Sets group mode (flush/discrete), updates flow |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingSortPlayersBy()` | Sets sort function: Role/Group/Alphabetical |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingRowSize()` | Updates raid container flow |
| `EditModeUnitFrameSystemMixin:UpdateSelectionVerticalState()` | Sets Selection vertical state based on raid-style + horizontal settings |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingFrameSize()` | Sets scale from FrameSize percentage |
| `EditModeUnitFrameSystemMixin:UpdateSystemSettingViewArenaSize()` | Refreshes arena members |
| `EditModeUnitFrameSystemMixin:UpdateSystemSetting(setting, entireSystemUpdate)` | Dispatcher for all unit frame settings |

---

### Other System Mixins

| Mixin | Key Methods |
|-------|-------------|
| **EditModeBossUnitFrameSystemMixin** | `OnEditModeExit()`, `ShouldAnyBossFrameShow()`, `UpdateShownState()` |
| **EditModeArenaUnitFrameSystemMixin** | `SetIsInEditMode(isInEditMode)`, `AddExtraButtons(extraButtonPool)` — manages CC remover, diminish, debuff frames |
| **EditModeMinimapSystemMixin** | `UpdateSystemSettingHeaderUnderneath()`, `UpdateSystemSettingRotateMinimap()`, `UpdateSystemSettingSize()`, `UpdateSystemSetting(setting, entireSystemUpdate)` |
| **EditModeCastBarSystemMixin** | `OnDragStart()` (unlocks from player frame), `ApplySystemAnchor()` (attach/detach from player), `ResetToDefaultPosition()`, `AnchorSelectionFrame()`, `UpdateSystemSettingLockToPlayerFrame()`, `UpdateSystemSettingShowCastTime()`, `UpdateSystemSettingBarSize()` |
| **EditModeEncounterBarSystemMixin** | `ApplySystemAnchor()` — calls Layout after base anchor |
| **EditModeExtraAbilitiesSystemMixin** | `OnEditModeExit()` |
| **EditModeAuraFrameSystemMixin** | `OnEditModeExit()`, `AnchorSelectionFrame()`, `UpdateDisplayInfoOptions(displayInfo)`, `UpdateSystem(systemInfo)`, `UpdateSystemSettingOrientation(entireSystemUpdate)`, `UpdateSystemSettingIconWrap()`, `UpdateSystemSettingIconDirection()`, `UpdateSystemSettingIconLimit()`, `UpdateSystemSettingIconSize()`, `UpdateSystemSettingIconPadding()`, `UpdateSystemSettingVisibleSetting()`, `UpdateSystemSettingOpacity()`, `UpdateSystemSettingShowDispelType()` |
| **EditModeTalkingHeadFrameSystemMixin** | `OnEditModeExit()` |
| **EditModeChatFrameSystemMixin** | `UpdateSystem(systemInfo)`, `MarkSystemPositionDirty()`, `RefreshSystemPosition()`, `OnEditModeEnter()`, `OnEditModeExit()`, `EditMode_OnResized()`, `UpdateSystemSettingWidth()`, `UpdateSystemSettingHeight()` |
| **EditModeChatFrameResizeButtonMixin** | `OnMouseDown()`, `OnMouseUp()` — handles chat frame resize dragging |
| **EditModeVehicleLeaveButtonSystemMixin** | `OnEditModeExit()`, `EditModeVehicleLeaveButtonSystem_OnShow()`, `EditModeVehicleLeaveButtonSystem_OnHide()` |
| **EditModeLootFrameSystemMixin** | `OnEditModeExit()`, `OnDragStart()`, `ApplySystemAnchor()` — toggles UI panel behavior based on position |
| **EditModeObjectiveTrackerSystemMixin** | `OnEditModeEnter()` (expands if collapsed), `OnEditModeExit()`, `OnDragStop()`, `AnchorSelectionFrame()`, `ResetToDefaultPosition()`, `ShouldShowSetting(setting)`, `UpdateSystemSettingHeight()`, `UpdateSystemSettingOpacity()`, `UpdateSystemSettingTextSize()`, `OnAnyEditModeSystemAnchorChanged()` |
| **EditModeMicroMenuSystemMixin** | `OnEditModeEnter()`, `OnEditModeExit()`, `OnAnyEditModeSystemAnchorChanged()`, `OnDragStop()`, `UpdateSystem(systemInfo)`, `UpdateSystemSettingOrientation()`, `UpdateSystemSettingOrder()`, `UpdateSystemSettingSize()`, `UpdateSystemSettingEyeSize()` |
| **EditModeBagsSystemMixin** | `UpdateSystem(systemInfo)`, `UpdateDisplayInfoOptions(displayInfo)`, `UpdateSystemSettingOrientation(entireSystemUpdate)`, `UpdateSystemSettingDirection()`, `UpdateSystemSettingSize()`, `UpdateSystemSettingBagSlotPadding()` |
| **EditModeStatusTrackingBarSystemMixin** | `OnEditModeExit()`, `OnSystemPositionChange()`, `ApplySystemAnchor()` |
| **EditModeStatusTrackingBar1SystemMixin** | `OnEditModeEnter()`, `GetSystemName()` (dynamic: XP bar vs status bar) |
| **EditModeDurabilityFrameSystemMixin** | `OnEditModeExit()`, `UpdateSystemSettingSize()` |
| **EditModePlayerFrameSystemMixin** | `ApplySystemAnchor()` (re-anchors cast bar), `UpdateSystemSettingFrameSize()` (updates pet + cast bar) |
| **EditModePetFrameSystemMixin** | `OnEditModeExit()`, `UpdateSystemSettingFrameSize()` |
| **EditModeTimerBarsSystemMixin** | `OnEditModeExit()`, `UpdateSystemSettingSize()` |
| **EditModeVehicleSeatIndicatorSystemMixin** | `OnEditModeExit()`, `UpdateSystemSettingSize()` |
| **EditModeArchaeologyBarSystemMixin** | `OnEditModeExit()`, `UpdateSystemSettingSize()` |
| **EditModeCooldownViewerSystemMixin** | `OnEditModeExit()`, `ShouldShowSetting(setting)` (per-systemIndex filtering), `UpdateDisplayInfoOptions(displayInfo)`, `UpdateSystemSettingOrientation()`, `UpdateSystemSettingIconLimit()`, `UpdateSystemSettingIconDirection()`, `UpdateSystemSettingIconSize()`, `UpdateSystemSettingIconPadding()`, `UpdateSystemSettingOpacity()`, `UpdateSystemSettingVisibleSetting()`, `UpdateSystemSettingBarContent()`, `UpdateSystemSettingHideWhenInactive()`, `UpdateSystemSettingShowTimer()`, `UpdateSystemSettingShowTooltips()`, `UpdateSystemSettingBarWidthScale()`, `UseSettingAltName(setting)` |

---

## 2. EditModeManager.lua

The central controller: manages layouts, registered system frames, edit mode state, snap/grid, account settings, and layout CRUD.

### Constants & Enums

| Name | Description |
|------|-------------|
| `EditModeManagerOptionsCategory` | `{ Frames = 1, Combat = 2, Misc = 3 }` — categories for account settings checkboxes |
| `RIGHT_ACTION_BAR_DEFAULT_OFFSET_X` | (referenced) Default X offset for right action bars |
| `RIGHT_ACTION_BAR_DEFAULT_OFFSET_Y` | (referenced) Default Y offset for right action bars |
| `MAIN_ACTION_BAR_DEFAULT_OFFSET_Y` | (referenced) Default Y offset for main action bar |
| `BOTTOM_ACTION_BARS_SPACER_Y` | (referenced) Vertical spacing between stacked bottom bars |

### Local Helper Functions

| Signature | Description |
|-----------|-------------|
| `AreAnchorsEqual(anchorInfo, otherAnchorInfo)` | Compares two anchor info tables with epsilon 0.1 |
| `CopyAnchorInfo(anchorInfo, otherAnchorInfo)` | Copies anchor fields from one table to another |
| `ConvertToAnchorInfo(point, relativeTo, relativePoint, offsetX, offsetY)` | Creates anchorInfo table from raw anchor data |
| `SortLayouts(a, b)` | Sorts layouts: character-specific → account → preset |

---

### EditModeManagerFrameMixin

#### Lifecycle

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:OnLoad()` | Initializes registeredSystemFrames, modernSystemMap, layout dropdown, grid/snap/advanced checkboxes, save/revert buttons, registers events |
| `EditModeManagerFrameMixin:OnDragStart()` | Starts moving the manager frame |
| `EditModeManagerFrameMixin:OnDragStop()` | Stops moving the manager frame |
| `EditModeManagerFrameMixin:OnUpdate()` | Invokes deferred anchor-change callbacks, refreshes snap preview lines |
| `EditModeManagerFrameMixin:OnShow()` | Enters edit mode (or restores selections from lock state) |
| `EditModeManagerFrameMixin:OnHide()` | Exits edit mode (or hides selections for lock state) |
| `EditModeManagerFrameMixin:OnEvent(event, ...)` | Handles EDIT_MODE_LAYOUTS_UPDATED, PLAYER_SPECIALIZATION_CHANGED, DISPLAY_SIZE_CHANGED, UI_SCALE_CHANGED |
| `EditModeManagerFrameMixin:IsInitialized()` | Returns `self.layoutInfo ~= nil` |

#### Edit Mode State

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:EnterEditMode()` | Sets editModeActive, clears changes, shows selections, fires EditMode.Enter event |
| `EditModeManagerFrameMixin:ExitEditMode()` | Reverts changes, hides selections, calls C_EditMode.OnEditModeExit, fires EditMode.Exit event |
| `EditModeManagerFrameMixin:IsEditModeActive()` | Returns `self.editModeActive` |
| `EditModeManagerFrameMixin:ShowSystemSelections()` | Calls OnEditModeEnter on all registered systems |
| `EditModeManagerFrameMixin:HideSystemSelections()` | Calls OnEditModeExit on all registered systems |
| `EditModeManagerFrameMixin:CheckHideAndLockEditMode(lockState)` | Clears selection, locks edit mode, hides UI panel |
| `EditModeManagerFrameMixin:ShowIfActive()` | Shows UI panel if edit mode is active |
| `EditModeManagerFrameMixin:SetEditModeLockState(lockState)` | Sets lock state string |
| `EditModeManagerFrameMixin:IsEditModeInLockState(lockState)` | Checks current lock state |
| `EditModeManagerFrameMixin:ClearEditModeLockState()` | Clears lock state |
| `EditModeManagerFrameMixin:IsEditModeLocked()` | Returns true if any lock state is set |
| `EditModeManagerFrameMixin:CanEnterEditMode()` | Checks game rule, NPE restriction, account settings, blocking frames |
| `EditModeManagerFrameMixin:BlockEnteringEditMode(blockingFrame)` | Adds frame to blocking set |
| `EditModeManagerFrameMixin:UnblockEnteringEditMode(blockingFrame)` | Removes frame from blocking set |

#### System Registration & Selection

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:RegisterSystemFrame(systemFrame)` | Appends to registeredSystemFrames list |
| `EditModeManagerFrameMixin:GetRegisteredSystemFrame(system, systemIndex)` | Finds system frame by system enum + index |
| `EditModeManagerFrameMixin:SelectSystem(selectFrame)` | Selects one system, highlights all others |
| `EditModeManagerFrameMixin:ClearSelectedSystem()` | Highlights all systems, hides settings dialog |

#### Anchor & Position Management

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:UpdateSystemAnchorInfo(systemFrame)` | Reads current anchors from frame, saves to systemInfo, handles scale correction |
| `EditModeManagerFrameMixin:OnSystemPositionChange(systemFrame)` | Updates anchor info, triggers layout/position updates |
| `EditModeManagerFrameMixin:OnEditModeSystemAnchorChanged()` | Sets `editModeSystemAnchorDirty = true` |
| `EditModeManagerFrameMixin:InvokeOnAnyEditModeSystemAnchorChanged(force)` | Calls OnAnyEditModeSystemAnchorChanged on all systems if dirty |
| `EditModeManagerFrameMixin:InitSystemAnchors()` | Clears all system anchors to TOPLEFT UIParent |
| `EditModeManagerFrameMixin:SetToLayoutAnchor(systemFrame, forceOffsetX, forceOffsetY)` | Positions system from layout/preset anchor info |
| `EditModeManagerFrameMixin:GetDefaultAnchor(frame)` | Returns default anchor for override/preset layouts |

#### Action Bar Layout

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:UpdateActionBarLayout(systemFrame)` | Routes to bottom or right bar position updates |
| `EditModeManagerFrameMixin:UpdateActionBarPositions()` | Updates both bottom and right bar positions |
| `EditModeManagerFrameMixin:UpdateRightActionBarPositions()` | Positions right action bars with auto-scaling |
| `EditModeManagerFrameMixin:UpdateBottomActionBarPositions()` | Stacks bottom action bars vertically |
| `EditModeManagerFrameMixin:UpdateTopFramePositions()` | Updates top-anchored frames (GMTicketFrame) |

#### Settings & Changes

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:SetHasActiveChanges(hasActiveChanges)` | Sets flag, enables/disables Save/Revert buttons |
| `EditModeManagerFrameMixin:CheckForSystemActiveChanges()` | Scans all systems for active changes |
| `EditModeManagerFrameMixin:HasActiveChanges()` | Returns `self.hasActiveChanges` |
| `EditModeManagerFrameMixin:ClearActiveChangesFlags()` | Clears all system change flags |
| `EditModeManagerFrameMixin:OnSystemSettingChange(systemFrame, changedSetting, newValue)` | Applies setting change to system |
| `EditModeManagerFrameMixin:MirrorSetting(system, systemIndex, setting, value)` | Applies mirrored settings to linked systems |
| `EditModeManagerFrameMixin:RevertSystemChanges(systemFrame)` | Restores single system to saved state |
| `EditModeManagerFrameMixin:GetSettingValue(system, systemIndex, setting, useRawValue)` | Gets setting value by system enum |
| `EditModeManagerFrameMixin:GetSettingValueBool(system, systemIndex, setting, useRawValue)` | Gets setting value as boolean |
| `EditModeManagerFrameMixin:DoesSettingValueEqual(system, systemIndex, setting, value)` | Raw value equality check |
| `EditModeManagerFrameMixin:DoesSettingDisplayValueEqual(system, systemIndex, setting, value)` | Display value equality check |

#### Grid & Snap

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:SetGridShown(gridShown, isUserInput)` | Shows/hides grid, enables/disables spacing slider |
| `EditModeManagerFrameMixin:SetGridSpacing(gridSpacing, isUserInput)` | Sets grid spacing, updates slider |
| `EditModeManagerFrameMixin:SetEnableSnap(enableSnap, isUserInput)` | Enables/disables snap, hides preview lines when off |
| `EditModeManagerFrameMixin:IsSnapEnabled()` | Returns `self.snapEnabled` |
| `EditModeManagerFrameMixin:SetSnapPreviewFrame(snapPreviewFrame)` | Sets frame currently being dragged for snap preview |
| `EditModeManagerFrameMixin:ClearSnapPreviewFrame()` | Clears snap preview frame and hides lines |
| `EditModeManagerFrameMixin:ShouldShowSnapPreviewLines()` | Returns true if snap enabled and preview frame set |
| `EditModeManagerFrameMixin:RefreshSnapPreviewLines()` | Creates/updates magnetism preview lines |
| `EditModeManagerFrameMixin:HideSnapPreviewLines()` | Releases all preview lines |
| `EditModeManagerFrameMixin:SetEnableAdvancedOptions(enableAdvancedOptions, isUserInput)` | Toggles advanced options, re-layouts settings |
| `EditModeManagerFrameMixin:AreAdvancedOptionsEnabled()` | Returns `self.advancedOptionsEnabled` |

#### Layout Management

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:UpdateLayoutInfo(layoutInfo, reconcileLayouts)` | Master layout update: reconciles, merges presets, inits anchors, updates all systems |
| `EditModeManagerFrameMixin:GetLayouts()` | Returns `self.layoutInfo.layouts` |
| `EditModeManagerFrameMixin:GetActiveLayoutInfo()` | Returns override layout or active layout from layoutInfo |
| `EditModeManagerFrameMixin:GetActiveLayoutSystemInfo(system, systemIndex)` | Finds system info in active layout |
| `EditModeManagerFrameMixin:IsActiveLayoutPreset()` | Checks if active layout type is Preset |
| `EditModeManagerFrameMixin:SelectLayout(layoutIndex)` | Switches active layout via C_EditMode |
| `EditModeManagerFrameMixin:IsLayoutSelected(layoutIndex)` | Checks if layout is active |
| `EditModeManagerFrameMixin:UpdateSystems()` | Calls UpdateSystem on all registered frames |
| `EditModeManagerFrameMixin:UpdateSystem(systemFrame, forceFullUpdate)` | Updates single system from active layout |
| `EditModeManagerFrameMixin:SetOverrideLayout(overrideLayoutIndex)` | Sets override layout (e.g., for Plunderstorm) |
| `EditModeManagerFrameMixin:ClearOverrideLayout()` | Clears override layout |
| `EditModeManagerFrameMixin:CreateLayoutTbls()` | Sorts layouts and tracks highest index per type |
| `EditModeManagerFrameMixin:UpdateDropdownOptions()` | Rebuilds layout dropdown with copy/rename/delete/import/export |
| `EditModeManagerFrameMixin:MakeNewLayout(newLayoutInfo, layoutType, layoutName, isLayoutImported)` | Creates new layout entry |
| `EditModeManagerFrameMixin:DeleteLayout(layoutIndex)` | Removes layout (non-preset only) |
| `EditModeManagerFrameMixin:DeleteAllLayouts()` | Removes all user layouts |
| `EditModeManagerFrameMixin:RenameLayout(layoutIndex, layoutName)` | Renames layout |
| `EditModeManagerFrameMixin:CopyActiveLayoutToClipboard()` | Exports active layout to clipboard |
| `EditModeManagerFrameMixin:ImportLayout(newLayoutInfo, layoutType, layoutName)` | Imports layout |
| `EditModeManagerFrameMixin:SaveLayouts()` | Prepares systems and saves via C_EditMode.SaveLayouts |
| `EditModeManagerFrameMixin:SaveLayoutChanges()` | Saves or prompts for new layout if preset |
| `EditModeManagerFrameMixin:RevertAllChanges()` | Reverts to last saved state |
| `EditModeManagerFrameMixin:PrepareSystemsForSave()` | Calls PrepareForSave on all systems |

#### Layout Reconciliation

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:RemoveOldSystemsAndSettings(layoutInfo)` | Strips outdated systems/settings from saved data |
| `EditModeManagerFrameMixin:AddNewSystemsAndSettings(layoutInfo)` | Adds missing modern systems/settings to saved data |
| `EditModeManagerFrameMixin:ReconcileWithModern(layoutInfo)` | Removes old + adds new |
| `EditModeManagerFrameMixin:ReconcileLayoutsWithModern()` | Reconciles all saved layouts |

#### Account Settings

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:UpdateAccountSettingMap()` | Rebuilds account setting map |
| `EditModeManagerFrameMixin:GetAccountSettingValue(setting)` | Returns account setting value |
| `EditModeManagerFrameMixin:GetAccountSettingValueBool(setting)` | Returns `value == 1` |
| `EditModeManagerFrameMixin:HasAccountSettings()` | Returns `self.accountSettings ~= nil` |
| `EditModeManagerFrameMixin:InitializeAccountSettings()` | Loads all account settings from C_EditMode, applies to UI |
| `EditModeManagerFrameMixin:OnAccountSettingChanged(changedSetting, newValue)` | Updates account setting and saves via C_EditMode |
| `EditModeManagerFrameMixin:UpdateLayoutCounts(savedLayouts)` | Counts layouts per type |
| `EditModeManagerFrameMixin:AreLayoutsOfTypeMaxed(layoutType)` | Checks against EditModeMaxLayoutsPerType |
| `EditModeManagerFrameMixin:AreLayoutsFullyMaxed()` | Both types maxed |

#### Dialogs

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:SetupEditModeDialogs()` | Configures new/rename/delete/import layout dialogs |
| `EditModeManagerFrameMixin:ShowNewLayoutDialog(layoutInfo)` | Opens new layout dialog |
| `EditModeManagerFrameMixin:ShowImportLayoutDialog()` | Opens import dialog |
| `EditModeManagerFrameMixin:ShowRenameLayoutDialog(layoutIndex, layoutInfo)` | Opens rename dialog |
| `EditModeManagerFrameMixin:ShowDeleteLayoutDialog(layoutIndex, layoutInfo)` | Opens delete dialog |
| `EditModeManagerFrameMixin:ShowRevertWarningDialog(selectedLayoutIndex)` | Opens unsaved changes warning |
| `EditModeManagerFrameMixin:ValidateLayoutNameFromDialog(dialog)` | Validates name uniqueness and format |
| `EditModeManagerFrameMixin:CanCreateNewLayoutFromDialog(dialog)` | Checks max layouts + validates name |
| `EditModeManagerFrameMixin:CanImportFromDialog(dialog)` | Checks max layouts + validates import data |
| `EditModeManagerFrameMixin:TryShowUnsavedChangesGlow()` | Shows glow on Save button if changes exist |
| `EditModeManagerFrameMixin:ClearUnsavedChangesGlow()` | Hides save button glow |

#### Specific System Queries

| Signature | Description |
|-----------|-------------|
| `EditModeManagerFrameMixin:ArePartyFramesForcedShown()` | Edit mode + ShowPartyFrames account setting |
| `EditModeManagerFrameMixin:GetNumArenaFramesForcedShown()` | Returns 2 or 3 based on ViewArenaSize |
| `EditModeManagerFrameMixin:UseRaidStylePartyFrames()` | Checks UseRaidStylePartyFrames setting |
| `EditModeManagerFrameMixin:ShouldShowPartyFrameBackground()` | Checks ShowPartyFrameBackground |
| `EditModeManagerFrameMixin:UpdateRaidContainerFlow()` | Sets raid container orientation, maxPerLine, sort |
| `EditModeManagerFrameMixin:AreRaidFramesForcedShown()` | Edit mode + ShowRaidFrames account setting |
| `EditModeManagerFrameMixin:GetNumRaidGroupsForcedShown()` | Returns 2/5/8 based on ViewRaidSize |
| `EditModeManagerFrameMixin:GetNumRaidMembersForcedShown()` | Returns 10/25/40 based on ViewRaidSize |
| `EditModeManagerFrameMixin:GetRaidFrameWidth(systemIndex, default)` | Returns FrameWidth setting or default |
| `EditModeManagerFrameMixin:GetRaidFrameHeight(systemIndex, default)` | Returns FrameHeight setting or default |
| `EditModeManagerFrameMixin:GetRaidFrameAuraOrganizationType(systemIndex)` | Returns AuraOrganizationType or Legacy default |
| `EditModeManagerFrameMixin:GetRaidFrameIconScale(systemIndex, default)` | Returns IconSize as percentage |
| `EditModeManagerFrameMixin:ShouldRaidFrameUseHorizontalRaidGroups(systemIndex)` | Party: UseHorizontalGroups; Raid: SeparateGroupsHorizontal |
| `EditModeManagerFrameMixin:ShouldRaidFrameDisplayBorder(systemIndex)` | Checks DisplayBorder setting |
| `EditModeManagerFrameMixin:ShouldRaidFrameShowSeparateGroups()` | Checks for SeparateGroups display type |
| `EditModeManagerFrameMixin:NotifyChatOfLayoutChange()` | Prints layout name to chat |

---

### EditModeGridMixin

| Signature | Description |
|-----------|-------------|
| `EditModeGridMixin:OnLoad()` | Creates line pool, registers events |
| `EditModeGridMixin:OnHide()` | Unregisters grid from magnetism, releases lines |
| `EditModeGridMixin:SetGridSpacing(spacing)` | Sets spacing and updates grid |
| `EditModeGridMixin:UpdateGrid()` | Draws center lines + evenly-spaced grid lines |

### EditModeGridSpacingSliderMixin

| Signature | Description |
|-----------|-------------|
| `EditModeGridSpacingSliderMixin:OnLoad()` | Registers slider callback |
| `EditModeGridSpacingSliderMixin:SetupSlider(gridSpacing)` | Inits slider with min/max/steps |
| `EditModeGridSpacingSliderMixin:SetEnabled(enabled)` | Enables/disables slider |
| `EditModeGridSpacingSliderMixin:OnSliderValueChanged(value)` | Forwards to manager SetGridSpacing |

### EditModeAccountSettingsMixin

| Signature | Description |
|-----------|-------------|
| `EditModeAccountSettingsMixin:OnLoad()` | Prepares all settings checkboxes, sets visibility per game flavor |
| `EditModeAccountSettingsMixin:PrepareSettingsCheckButtons()` | Creates callback wiring for ~25 settings checkboxes |
| `EditModeAccountSettingsMixin:OnEvent(event, ...)` | Handles PLAYER_TARGET_CHANGED, PLAYER_FOCUS_CHANGED for forced targeting |
| `EditModeAccountSettingsMixin:OnEditModeEnter()` | Saves old action bar states, sets up frames |
| `EditModeAccountSettingsMixin:OnEditModeExit()` | Resets all forced frame states |
| `EditModeAccountSettingsMixin:LayoutSettings()` | Toggles basic/advanced option layout |
| `EditModeAccountSettingsMixin:SetExpandedState(expanded)` | (referenced) Controls settings panel expansion |
| `EditModeAccountSettingsMixin:SetTargetAndFocusShown(shown, isUserInput)` | Forces target/focus to player in edit mode |
| `EditModeAccountSettingsMixin:RefreshTargetAndFocus()` | Targets player, highlights target/focus frames |
| `EditModeAccountSettingsMixin:ResetTargetAndFocus()` | Restores original target/focus |
| `EditModeAccountSettingsMixin:Set[SystemName]Shown(shown, isUserInput)` | ~25 methods for each toggleable system (PartyFrames, RaidFrames, CastBar, EncounterBar, ExtraAbilities, BuffsAndDebuffs, TalkingHeadFrame, VehicleLeaveButton, BossFrames, ArenaFrames, LootFrame, HudTooltip, DurabilityFrame, PetFrame, CooldownViewer, EncounterEvents, DamageMeter, StanceBar, PetActionBar, PossessActionBar, etc.) |
| `EditModeAccountSettingsMixin:Set[SystemName]MouseOver(...)` | ~25 methods forwarding ShowEditInstructions to system frames |
| `EditModeAccountSettingsMixin:SetActionBarShown(bar, shown, isUserInput)` | Generic action bar toggle |
| `EditModeAccountSettingsMixin:SetupActionBar(bar)` | Saves initial state, sets up checkbox |

---

## 3. EditModeSettingDisplayInfo.lua

Defines metadata for every Edit Mode setting: display type, min/max/step values, conversion functions, and option lists.

### Top-Level Functions & Helpers

| Signature | Description |
|-----------|-------------|
| `ShowAsPercentage(value)` | Formats `value/100` as percentage string |
| `ConvertValueDefault(self, value, forDisplay)` | Default slider conversion: `(value * stepSize) + minValue` for display; inverse for raw |
| `ConvertValueDiffFromMin(self, value, forDisplay)` | Slider conversion: `value + minValue` for display; `value - minValue` for raw |

### EditModeSettingDisplayInfoManager

| Signature | Description |
|-----------|-------------|
| `EditModeSettingDisplayInfoManager:GetSystemSettingDisplayInfo(system)` | Returns ordered array of setting display info for a system |
| `EditModeSettingDisplayInfoManager:GetSystemSettingDisplayInfoMap(system)` | Returns map from setting enum → display info |
| `EditModeSettingDisplayInfoManager:GetMirroredSettings(system, systemIndex, setting)` | Returns mirrored settings for cross-system synchronization |

### DefaultSettingDisplayInfo (metatable)

| Method | Description |
|--------|-------------|
| `DefaultSettingDisplayInfo:ConvertValue(value, forDisplay)` | Default identity conversion with clamping |
| `DefaultSettingDisplayInfo:ClampValue(value)` | Clamps to valid range based on display type |
| `DefaultSettingDisplayInfo:ConvertValueForDisplay(value)` | Convenience wrapper for display conversion |

### Systems with Settings Defined

| System Enum | Settings |
|-------------|----------|
| **ActionBar** | Orientation (H/V), NumRows (1-4), NumIcons (6-12), IconSize (50-200%), IconPadding (2-10), VisibleSetting (Always/InCombat/OutOfCombat/Hidden), AlwaysShowButtons, HideBarArt, HideBarScrolling |
| **Minimap** | HeaderUnderneath, RotateMinimap, Size (50-200%) |
| **CastBar** | BarSize (100-150%), LockToPlayerFrame, ShowCastTime |
| **UnitFrame** | CastBarUnderneath, UseLargerFrame, BuffsOnTop, UseRaidStylePartyFrames, ShowPartyFrameBackground, CastBarOnSide, ViewRaidSize (10/25/40), ViewArenaSize (2/3), FrameWidth (72-144), FrameHeight (36-72), RaidGroupDisplayType, SortPlayersBy (Role/Group/Alpha), UseHorizontalGroups, DisplayBorder, RowSize (2-10), FrameSize (100-200%), AuraOrganizationType, Opacity (50-100%), IconSize (50-200%) |
| **AuraFrame** | Orientation (H/V), IconWrap (Down/Up), IconDirection (Left/Right), IconSize (50-200%), IconPadding (5-15), IconLimitBuffFrame (2-32), IconLimitDebuffFrame (1-16), Opacity (50-100%), VisibleSetting, ShowDispelType |
| **ChatFrame** | Width (250-800, composite), Height (120-800, composite) |
| **ObjectiveTracker** | Height (400-1000), Opacity (0-100%), TextSize (12-20) |
| **MicroMenu** | Orientation (H/V), Order (Default/Reverse), Size (70-200%), EyeSize (50-150%) |
| **Bags** | Orientation (H/V), Direction (Left/Right or Up/Down), Size (75-200%), BagSlotPadding (2-10) |
| **DurabilityFrame** | Size (75-200%) |
| **TimerBars** | Size (100-150%) |
| **VehicleSeatIndicator** | Size (50-100%) |
| **ArchaeologyBar** | Size (100-200%) |
| **CooldownViewer** | Orientation, IconLimit (1-20), IconDirection, IconSize (50-200%), IconPadding (0-14), BarWidthScale (50-200%), Opacity (50-100%), VisibleSetting, BarContent, HideWhenInactive, ShowTimer, ShowTooltips |
| **PersonalResourceDisplay** | HideHealthAndPower, OnlyShowInCombat |
| **EncounterEvents** | ViewType (Timeline/Bars), Orientation, IconDirection, IconSize, OverallSize, Padding, BarWidth, BackgroundTransparency, Transparency, Visibility, TooltipAnchor, FlipHorizontally, ShowSpellName, ShowTimer |
| **DamageMeter** | Style, Numbers, FrameWidth, FrameHeight, BarHeight, Padding, Transparency, BackgroundTransparency, TextSize, Visibility, ShowSpecIcon, ShowClassColor |

### Mirrored Settings

| Setting A | Setting B |
|-----------|-----------|
| `CastBar.LockToPlayerFrame` | `UnitFrame[Player].CastBarUnderneath` |

> When one changes, the other is automatically updated via MirrorSetting.

### Custom Display-Only Enums

```lua
Enum.EditModeChatFrameDisplayOnlySetting = {
    Width = (highest EditModeChatFrameSetting) + 1,
    Height = (highest EditModeChatFrameSetting) + 2,
}
```

These are composite settings — Width maps to WidthHundreds + WidthTensAndOnes sub-settings.

---

## 4. EditModeUtil.lua

Utility functions and the **EditModeMagnetismManager** — the complete snap/magnet system.

### EditModeUtil (utility functions)

| Signature | Description |
|-----------|-------------|
| `EditModeUtil:IsRightAnchoredActionBar(systemFrame)` | Returns true for MultiBarRight/MultiBarLeft |
| `EditModeUtil:IsBottomAnchoredActionBar(systemFrame)` | Returns true for MultiBarBottomRight/Left, MainActionBar, StanceBar, PetActionBar, PossessActionBar, VehicleLeaveButton |
| `EditModeUtil:GetRightActionBarWidth()` | Calculates total width of right-anchored bars |
| `EditModeUtil:GetBottomActionBarHeight()` | Calculates total height of bottom-anchored bars |
| `EditModeUtil:GetRightContainerAnchor()` | Returns anchor for right container (offset by right bar width) |
| `EditModeUtil:GetSettingMapFromSettings(settings, displayInfoMap)` | Converts settings array to `{ [setting] = { value, displayValue } }` map |
| `EditModeUtil.CreateLinePool(ownerFrame, template)` | Creates ObjectPool for lines with reset function |

### Local Helper

| Signature | Description |
|-----------|-------------|
| `GetBarsLayoutSize(barHeirarchy, getWidth)` | Walks bar hierarchy to find first visible/default bar and returns offset + size |
| `IsGridLineOrUIParent(frame)` | Returns true if frame is grid line or UIParent |

---

### EditModeMagnetismManager

The snap/magnet engine. Manages magnetic frame registration, grid registration, and snap calculations.

#### Constants

| Name | Value | Description |
|------|-------|-------------|
| `magnetismRange` | `8` | Default snap distance in pixels |
| `sqrMagnetismRange` | `64` | Squared range for edge snapping |
| `sqrCornerMagnetismRange` | `128` | Squared range for corner snapping (2× edge range) |

#### UIParent Points

| Signature | Description |
|-----------|-------------|
| `EditModeMagnetismManager:UpdateUIParentPoints()` | Caches UIParent center, dimensions, and all four edges |

#### Registration

| Signature | Description |
|-----------|-------------|
| `EditModeMagnetismManager:SetMagnetismRange(magnetismRange)` | Updates range and derived squared values |
| `EditModeMagnetismManager:RegisterFrame(frame)` | Adds frame to `magneticFrames` set |
| `EditModeMagnetismManager:UnregisterFrame(frame)` | Removes frame from `magneticFrames` set |
| `EditModeMagnetismManager:RegisterGrid()` | Creates `magneticGridLines = { horizontal = {}, vertical = {} }` |
| `EditModeMagnetismManager:UnregisterGrid()` | Sets `magneticGridLines = nil` |
| `EditModeMagnetismManager:RegisterGridLine(line, verticalLine, centerOffset)` | Stores grid line position as center + offset |

#### Eligibility

| Signature | Description |
|-----------|-------------|
| `EditModeMagnetismManager:GetEligibleMagneticFrames(systemFrame)` | Returns `{ horizontal = {...}, vertical = {...} }` — UIParent always included; other frames filtered by alignment |

#### Core Snap Logic

| Signature | Description |
|-----------|-------------|
| `EditModeMagnetismManager:GetMagneticFrameInfoTable(frame, point, relativePoint, distance, offset, isHorizontal, isCornerSnap)` | Creates snap info structure |
| `EditModeMagnetismManager:CheckReplaceMagneticFrameInfo(currentInfo, frame, point, relativePoint, distance, offset, isHorizontal)` | Replaces current snap candidate if new one is closer (within range) |
| `EditModeMagnetismManager:GetUIParentCheckPoints(systemFrame, verticalLines)` | Returns 5 check points: LEFT/RIGHT/CENTER edges of UIParent (or TOP/BOTTOM/CENTER for horizontal) |
| `EditModeMagnetismManager:GetGridLineCheckPoints(systemFrame, verticalLines)` | Returns 3 check points: LEFT/RIGHT/CENTER (or TOP/BOTTOM/CENTER) |
| `EditModeMagnetismManager:FindClosestGridLine(systemFrame, verticalLines)` | Finds closest UIParent edge or grid line; returns distance, point, relativePoint, offset |

#### Corner Snapping

| Signature | Description |
|-----------|-------------|
| `EditModeMagnetismManager:IsPotentialMagneticCornerFrame(frame)` | Checks if frame has `GetScaledSelectionSides` method |
| `EditModeMagnetismManager:ShouldReplaceClosestCorner(closestSqrDistance, cornerSqrDistance)` | Checks if corner is within range and closer |
| `EditModeMagnetismManager:GetCornerMagneticFrameInfo(frame, relativeToFrameInfo)` | Calculates nearest corner snap between two frames; excludes diagonal corners (TOPLEFT↔BOTTOMRIGHT, etc.) |

#### Snap Resolution

| Signature | Description |
|-----------|-------------|
| `EditModeMagnetismManager:GetMagneticFrameInfoOptions(systemFrame)` | Returns best horizontal, vertical, and corner snap candidates |
| `EditModeMagnetismManager:GetMagneticFrameInfos(systemFrame)` | Resolves final snap targets: corner priority → grid double-snap → closest single snap |
| `EditModeMagnetismManager:ApplyMagnetism(systemFrame)` | Gets snap targets and calls `SnapToFrame` on each |

#### Preview Lines

| Signature | Description |
|-----------|-------------|
| `EditModeMagnetismManager:GetPreviewLineAnchors(magneticFrameInfo)` | Returns anchor strings ("Top", "Bottom", "Left", "Right", "CenterVertical", "CenterHorizontal") for preview line rendering |

---

## Key Architectural Patterns

### Snap Priority Order
1. **Corner snaps** — Highest priority. Snaps frame corner to another frame's corner (excludes diagonal pairs).
2. **Grid/UIParent double-snap** — If both horizontal and vertical candidates are grid lines or UIParent, both are applied simultaneously.
3. **Closest single snap** — Otherwise, the closest of horizontal or vertical is used.

### Setting Value Pipeline
```
Raw Value (saved) → ConvertValueForDisplay() → Display Value (shown in UI)
Display Value (from slider) → ConvertSettingDisplayValueToRawValue() → Raw Value (saved)
```
Composite settings (e.g., ChatFrame Width) split a display value into Hundreds + TensAndOnes sub-settings.

### System Lifecycle
```
OnSystemLoad() → RegisterSystemFrame() → UpdateLayoutInfo() → UpdateSystem(systemInfo) →
  UpdateSettingMap() → ApplySystemAnchor() → UpdateSystemSetting(each) → OnUpdateSystem()
```

### Frame Manager Integration
Managed frames (bottom bars, right bars, player-frame children) live in `UIParentBottomManagedFrameContainer`, `UIParentRightManagedFrameContainer`, or `PlayerFrameBottomManagedFramesContainer`. When a user moves them, `BreakFromFrameManager()` reparents to UIParent.

### Selection States
- **Hidden** — No selection visible, not in edit mode
- **Highlighted** — Selection frame shown with highlight appearance; frame is NOT movable; registered as magnetic target
- **Selected** — Selection frame shown with selected appearance; frame IS movable; settings dialog attached; NOT registered as magnetic target (you can't snap to the frame you're dragging)
