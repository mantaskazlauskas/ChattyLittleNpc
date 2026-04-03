# Edit Mode Two-Window Refactor — Unified Architecture Plan

> **Co-Architects:** Claude Opus 4.6 + GPT 5.4  
> **Process:** 3-iteration adversarial synthesis (independent proposals → cross-reviews → final synthesis)  
> **Status:** Final — ready for implementation  
> **Scope:** Refactor Edit Mode integration for 2 independently positionable windows with snap

---

## 1. Executive Summary

The current Edit Mode integration is a monolithic ~1600 LOC file that treats the addon as a single
unit. This plan refactors it into a **two-window architecture** where the **Conversation Window**
(DisplayFrame + ContentFrame) and **Model Window** (ModelContainer + NpcModelFrame) are
independently positionable, resizable, and persistable per Edit Mode layout. A custom pairwise
magnetism system provides snap-to-grid and snap-to-each-other functionality with visual guides.
The monolith is decomposed into 9 focused files in an `EditMode/` subdirectory.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        EditMode/Init.lua                        │
│            Bootstrap: creates controllers, registers,           │
│            wires hooks, migration                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐     ┌──────────────┐     ┌─────────────────┐ │
│  │  Conversation │     │    Model     │     │    Registry     │ │
│  │   Window.lua  │     │  Window.lua  │     │     .lua        │ │
│  │  (adapter)    │     │  (adapter)   │     │  (selection +   │ │
│  │              │     │              │     │   lifecycle)    │ │
│  └──────┬───────┘     └──────┬───────┘     └───────┬─────────┘ │
│         │                    │                     │           │
│  ┌──────┴────────────────────┴─────────────────────┘           │
│  │                                                             │
│  ▼                                                             │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │   Window     │  │   Overlay    │  │    SnapManager.lua     │ │
│  │   .lua       │  │  Factory.lua │  │  (grid + pairwise +   │ │
│  │  (shared     │  │  (6 states,  │  │   hysteresis + dock)  │ │
│  │  utilities)  │  │   grips,     │  │                       │ │
│  │              │  │   labels)    │  │  ┌─────────────────┐  │ │
│  └──────────────┘  └──────────────┘  │  │  Guides.lua     │  │ │
│                                      │  │  (UIParent-level │  │ │
│  ┌──────────────┐  ┌──────────────┐  │  │   snap lines)   │  │ │
│  │ Persistence  │  │ ImportExport │  │  └─────────────────┘  │ │
│  │    .lua      │  │    .lua      │  └────────────────────────┘ │
│  │ (v2 schema,  │  │ (CLN2 +     │                             │
│  │  migration,  │  │  CLN1 compat)│                             │
│  │  resolution) │  │              │                             │
│  └──────────────┘  └──────────────┘                             │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  EditPanel.lua (MODIFIED — stacked sections + selector pills)   │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Edit Mode Enter → Registry:OnEnter() → ForEach window: ShowOverlay()
User clicks overlay → Registry:Select(id) → SetSelected(true) + panel sync
User drags window → SnapManager:Evaluate() → guide lines → StopDrag → Commit → Persist
Layout switch → EDIT_MODE_LAYOUTS_UPDATED → Persistence:ApplyLayout() → ForEach: ApplyState()
Edit Mode Exit → Registry:OnExit() → ForEach: HideOverlay() → Persist final state
```

---

## 3. Window Abstraction

### 3.1 Shared Utilities (Window.lua)

A flat module of shared functions — not a class. Matches WoW addon convention.

```lua
-- src/ReplayFrame/EditMode/Window.lua

local Window = {}

--- Compute frame rect in UIParent-space pixels (scale-normalized)
function Window.GetRect(frame)
    local scale = frame:GetEffectiveScale() or 1
    local uiScale = UIParent:GetEffectiveScale() or 1
    local ratio = scale / uiScale
    return {
        left   = (frame:GetLeft()   or 0) * ratio,
        right  = (frame:GetRight()  or 0) * ratio,
        top    = (frame:GetTop()    or 0) * ratio,
        bottom = (frame:GetBottom() or 0) * ratio,
    }
end

function Window.GetCenter(rect)
    return (rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2
end

--- Serialize position for persistence (UIParent-space)
function Window.SerializePosition(frame)
    local p, _, r, x, y = frame:GetPoint(1)
    local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
    return {
        point = p, relativePoint = r,
        x = x, y = y,
        x_pct = uiW > 0 and (x / uiW) or 0,
        y_pct = uiH > 0 and (y / uiH) or 0,
    }
end

--- Apply position, using percentage coords if resolution changed significantly
function Window.ApplyPosition(frame, pos, opts)
    if not pos then return end
    local x, y = pos.x or 0, pos.y or 0
    if opts and opts.usePercentage and pos.x_pct and pos.y_pct then
        local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
        x = pos.x_pct * uiW
        y = pos.y_pct * uiH
    end
    frame:ClearAllPoints()
    frame:SetPoint(pos.point or "CENTER", UIParent,
                   pos.relativePoint or "CENTER", x, y)
end

--- Clamp frame to screen bounds
function Window.ClampToScreen(frame)
    local left = frame:GetLeft()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local bottom = frame:GetBottom()
    if not (left and right and top and bottom) then return end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local dx, dy = 0, 0
    if left < 0 then dx = -left
    elseif right > sw then dx = sw - right end
    if bottom < 0 then dy = -bottom
    elseif top > sh then dy = sh - top end
    if dx ~= 0 or dy ~= 0 then
        local p, _, r, x, y2 = frame:GetPoint(1)
        frame:ClearAllPoints()
        frame:SetPoint(p, UIParent, r, (x or 0) + dx, (y2 or 0) + dy)
    end
end

return Window
```

### 3.2 Window Controller Contract

Each window adapter (ConversationWindow, ModelWindow) exposes this interface:

```lua
---@alias CLNWindowId "conversation"|"model"

---@class CLNWindowController
---@field id CLNWindowId
---@field label string                           -- "Conversation" | "Model"
---@field frame Frame?                           -- root frame (may be nil before creation)
---@field selected boolean
---@field hovered boolean
---@field locked boolean
---@field overlay Frame?                         -- created lazily
--
---@field EnsureFrame fun(self): Frame
---@field ReadState fun(self): table             -- current live state for persistence
---@field ApplyState fun(self, state: table)     -- restore from persisted state
---@field GetDefaultState fun(self): table
---@field GetResizeBounds fun(self): table       -- {minW, minH, maxW, maxH}
---@field CanResize fun(self): boolean
---@field IsVisibleInEditMode fun(self): boolean -- true even in Compact Mode
--
-- Drag/resize/nudge delegated to shared Window utilities
-- Selection/overlay delegated to OverlayFactory + Registry
```

### 3.3 Conversation Window Adapter

```lua
-- src/ReplayFrame/EditMode/ConversationWindow.lua

local ConversationWindow = {
    id    = "conversation",
    label = "Conversation",
}

function ConversationWindow:EnsureFrame()
    self.frame = self.frame or ReplayFrame:GetDisplayFrame()
    return self.frame
end

function ConversationWindow:ReadState()
    local f = self:EnsureFrame()
    return {
        pos       = Window.SerializePosition(f),
        size      = { width = f:GetWidth(), height = f:GetHeight() },
        scale     = CLN.db.profile.frameScale,
        textScale = CLN.db.profile.queueTextScale,
    }
end

function ConversationWindow:ApplyState(state)
    local f = self:EnsureFrame()
    if state.scale then
        CLN.db.profile.frameScale = state.scale
        ReplayFrame:ApplyFrameScale()
    end
    if state.textScale then
        CLN.db.profile.queueTextScale = state.textScale
        ReplayFrame:ApplyQueueTextScale()
    end
    if state.size then
        f:SetSize(state.size.width, state.size.height)
    end
    if state.pos then
        Window.ApplyPosition(f, state.pos)
    end
end

function ConversationWindow:GetDefaultState()
    return {
        pos       = { point = "CENTER", relativePoint = "CENTER", x = 500, y = 0 },
        size      = { width = 475, height = 165 },
        scale     = 1.0,
        textScale = 1.0,
    }
end

function ConversationWindow:GetResizeBounds()
    return { minW = 260, minH = 120, maxW = 1000, maxH = 600 }
end

function ConversationWindow:CanResize() return true end
function ConversationWindow:IsVisibleInEditMode() return true end
```

### 3.4 Model Window Adapter

```lua
-- src/ReplayFrame/EditMode/ModelWindow.lua

local ModelWindow = {
    id    = "model",
    label = "Model",
}

function ModelWindow:EnsureFrame()
    self.frame = self.frame or ReplayFrame.ModelContainer
    return self.frame
end

function ModelWindow:ReadState()
    local f = self:EnsureFrame()
    return {
        docked = self:IsDocked(),
        pos    = Window.SerializePosition(f),
        size   = { width = f:GetWidth(), height = f:GetHeight() },
    }
end

function ModelWindow:ApplyState(state)
    local f = self:EnsureFrame()
    if state.size then
        f:SetSize(state.size.width, state.size.height)
    end
    if state.docked then
        self:Dock()
    elseif state.pos then
        Window.ApplyPosition(f, state.pos)
    end
end

function ModelWindow:IsDocked()
    -- Docked = model anchored to conversation, not free-floating
    return self._docked ~= false  -- default to docked
end

function ModelWindow:Dock()
    local conv = Registry:Get("conversation")
    if not conv or not conv.frame then return end
    self._docked = true
    local f = self:EnsureFrame()
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", conv.frame, "TOPLEFT", 0, 2)
    f:SetPoint("BOTTOMRIGHT", conv.frame, "TOPRIGHT", 0, 2)
end

function ModelWindow:Undock()
    -- Convert docked anchor to absolute UIParent position (preserve screen location)
    local f = self:EnsureFrame()
    local left, bottom = f:GetLeft(), f:GetBottom()
    self._docked = false
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left or 0, bottom or 0)
end

function ModelWindow:GetDefaultState()
    return { docked = true, size = { width = 475, height = 140 } }
end

function ModelWindow:GetResizeBounds()
    return { minW = 100, minH = 80, maxW = 600, maxH = 500 }
end

function ModelWindow:CanResize() return true end
function ModelWindow:IsVisibleInEditMode() return true end  -- even in Compact Mode
```

---

## 4. Registry & Selection

```lua
-- src/ReplayFrame/EditMode/Registry.lua

local Registry = {
    _windows   = {},       -- { [CLNWindowId] = CLNWindowController }
    _selected  = nil,      -- CLNWindowId or nil
    _active    = false,    -- Edit Mode active?
    _order     = { "conversation", "model" },  -- Tab cycling order
}

function Registry:Register(controller)
    self._windows[controller.id] = controller
end

function Registry:Get(id) return self._windows[id] end

function Registry:ForEach(fn)
    for _, id in ipairs(self._order) do
        local w = self._windows[id]
        if w then fn(id, w) end
    end
end

function Registry:Select(id, source)
    -- Deselect previous
    if self._selected and self._selected ~= id then
        local prev = self._windows[self._selected]
        if prev then prev.selected = false end
        OverlayFactory:SetState(prev, "default")
    end
    -- Select new (or nil to clear)
    self._selected = id
    if id then
        local w = self._windows[id]
        if w then
            w.selected = true
            OverlayFactory:SetState(w, "selected")
        end
    end
    -- Clear Blizzard selection to avoid visual conflicts
    self:ClearBlizzardSelection()
    -- Sync panel if source ~= "panel" (avoid infinite loop)
    if source ~= "panel" then
        ReplayFrame:FocusEditPanelSection(id)
    end
end

function Registry:GetSelected() return self._selected end

function Registry:CycleSelection(reverse)
    local order = self._order
    local cur = self._selected
    local idx = 0
    for i, id in ipairs(order) do
        if id == cur then idx = i break end
    end
    if reverse then
        idx = idx - 1
        if idx < 1 then idx = #order end
    else
        idx = idx + 1
        if idx > #order then idx = 1 end
    end
    self:Select(order[idx], "keyboard")
end

function Registry:ClearBlizzardSelection()
    if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
        EditModeManagerFrame:ClearSelectedSystem()
    end
end

function Registry:OnEnter()
    self._active = true
    self:ForEach(function(id, w)
        w:EnsureFrame()
        OverlayFactory:EnsureOverlay(w)
        OverlayFactory:Show(w)
    end)
end

function Registry:OnExit()
    self._active = false
    self._selected = nil
    self:ForEach(function(id, w)
        w.selected = false
        OverlayFactory:Hide(w)
    end)
    Persistence:PersistAll()
end
```

### Selection Rules

1. At most **one** CLN window selected at a time
2. Clicking a CLN overlay → selects it, deselects other CLN window + clears Blizzard selection
3. Blizzard selecting a system → hook fires `Registry:Select(nil)` to clear CLN selection
4. **Tab** → cycles CLN windows only (does not interact with Blizzard systems)
5. **Esc** → clears CLN selection + propagates keypress (Blizzard handles exit on next Esc)
6. Keyboard focus lives on the selected overlay; active EditBox in panel wins over overlay

---

## 5. Snap & Magnetism System

### 5.1 SnapManager

```lua
-- src/ReplayFrame/EditMode/SnapManager.lua

local SnapManager = {
    -- Thresholds (UIParent-space pixels after scale normalization)
    EDGE_THRESHOLD   = 10,
    CENTER_THRESHOLD = 14,
    DOCK_THRESHOLD   = 12,
    HYSTERESIS       = 3,   -- hold snap until beaten by this many px

    -- Grid (read from Blizzard)
    gridEnabled = true,
    gridSpacing = 50,

    -- Anti-jitter state
    _lastSnapH  = nil,      -- cached horizontal snap target
    _lastSnapV  = nil,      -- cached vertical snap target
}
```

### 5.2 Grid Snap

```lua
function SnapManager:ReadGridSettings()
    if not C_EditMode or not C_EditMode.GetAccountSettings then return end
    local ok, settings = pcall(C_EditMode.GetAccountSettings)
    if not ok or not settings then return end
    for _, s in ipairs(settings) do
        if s.setting == Enum.EditModeAccountSetting.EnableSnap then
            self.gridEnabled = (s.value == 1)
        elseif s.setting == Enum.EditModeAccountSetting.GridSpacing then
            self.gridSpacing = s.value
        end
    end
end

function SnapManager:GetGridThreshold()
    return math.min(12, math.max(6, math.floor(self.gridSpacing * 0.35)))
end

function SnapManager:FindGridSnap(rect)
    if not self.gridEnabled then return nil, nil end
    local spacing = self.gridSpacing
    local threshold = self:GetGridThreshold()

    local snapLeft = math.floor((rect.left / spacing) + 0.5) * spacing
    local snapTop  = math.floor((rect.top / spacing) + 0.5) * spacing

    local dx = snapLeft - rect.left
    local dy = snapTop - rect.top

    return (math.abs(dx) <= threshold) and dx or nil,
           (math.abs(dy) <= threshold) and dy or nil
end
```

### 5.3 Pairwise Window Snap

6 candidates per axis (Blizzard model: left/right/center × left/right/center):

```lua
function SnapManager:FindPairwiseSnap(draggedRect, targetRect)
    local t = self.EDGE_THRESHOLD
    local ct = self.CENTER_THRESHOLD
    local dcx, dcy = Window.GetCenter(draggedRect)
    local tcx, tcy = Window.GetCenter(targetRect)

    -- Horizontal candidates (6)
    local hCandidates = {
        { dist = math.abs(draggedRect.left  - targetRect.left),  dx = targetRect.left  - draggedRect.left,  thr = t },
        { dist = math.abs(draggedRect.left  - targetRect.right), dx = targetRect.right - draggedRect.left,  thr = t },
        { dist = math.abs(draggedRect.right - targetRect.left),  dx = targetRect.left  - draggedRect.right, thr = t },
        { dist = math.abs(draggedRect.right - targetRect.right), dx = targetRect.right - draggedRect.right, thr = t },
        { dist = math.abs(dcx - tcx),                           dx = tcx - dcx,                            thr = ct },
    }

    -- Vertical candidates (6)
    local vCandidates = {
        { dist = math.abs(draggedRect.top    - targetRect.top),    dy = targetRect.top    - draggedRect.top,    thr = t },
        { dist = math.abs(draggedRect.top    - targetRect.bottom), dy = targetRect.bottom - draggedRect.top,    thr = t },
        { dist = math.abs(draggedRect.bottom - targetRect.top),    dy = targetRect.top    - draggedRect.bottom, thr = t },
        { dist = math.abs(draggedRect.bottom - targetRect.bottom), dy = targetRect.bottom - draggedRect.bottom, thr = t },
        { dist = math.abs(dcy - tcy),                              dy = tcy - dcy,                              thr = ct },
    }

    local bestH = self:FindBest(hCandidates, "dx")
    local bestV = self:FindBest(vCandidates, "dy")
    return bestH, bestV
end

function SnapManager:FindBest(candidates, key)
    local best = nil
    for _, c in ipairs(candidates) do
        if c.dist <= c.thr and (not best or c.dist < best.dist) then
            best = c
        end
    end
    return best
end
```

### 5.4 Hysteresis (Anti-Jitter)

```lua
function SnapManager:ApplyHysteresis(axis, newSnap)
    local lastKey = (axis == "h") and "_lastSnapH" or "_lastSnapV"
    local last = self[lastKey]
    if last and newSnap then
        -- Keep existing snap unless new one beats it by HYSTERESIS px
        if newSnap.dist >= last.dist - self.HYSTERESIS then
            return last
        end
    end
    self[lastKey] = newSnap
    return newSnap
end

function SnapManager:ClearHysteresis()
    self._lastSnapH = nil
    self._lastSnapV = nil
end
```

### 5.5 Dock Eligibility (3-Gate Protection)

```lua
function SnapManager:CheckDockEligibility(modelRect, convRect)
    -- Gate 1: bottom-of-model near top-of-conversation
    local vertDist = math.abs(modelRect.bottom - convRect.top)
    if vertDist > self.DOCK_THRESHOLD then
        return false, "too far vertically"
    end

    -- Gate 2: horizontal overlap >= 70% of smaller width
    local mWidth = modelRect.right - modelRect.left
    local cWidth = convRect.right - convRect.left
    local overlapLeft  = math.max(modelRect.left, convRect.left)
    local overlapRight = math.min(modelRect.right, convRect.right)
    local overlap = math.max(0, overlapRight - overlapLeft)
    local smallerWidth = math.min(mWidth, cWidth)
    if smallerWidth > 0 and (overlap / smallerWidth) < 0.70 then
        return false, "insufficient horizontal overlap"
    end

    -- Gate 3: width delta <= 16px
    if math.abs(mWidth - cWidth) > 16 then
        return false, "width mismatch too large"
    end

    return true
end
```

### 5.6 Docking State Machine

```
          ┌─────────────────────────┐
          │         DOCKED          │
          │  (anchored to conv)     │
          └────────┬────────────────┘
                   │ User starts dragging model
                   ▼
          ┌─────────────────────────┐
          │      UNDOCKING          │
          │  Convert anchor to      │
          │  absolute UIParent pos  │
          │  (preserve screen loc)  │
          └────────┬────────────────┘
                   │ StartMoving()
                   ▼
          ┌─────────────────────────┐
          │     FREE / DRAGGING     │◄──────────────┐
          │  Independent position   │               │
          └────────┬────────────────┘               │
                   │ User releases                   │
                   ▼                                 │
          ┌─────────────────────────┐               │
          │   DOCK CHECK            │               │
          │  3-gate eligibility     │───(fail)──────┘
          │  assessment             │     persist free pos
          └────────┬────────────────┘
                   │ (pass)
                   ▼
          ┌─────────────────────────┐
          │     REDOCK PREVIEW      │
          │  Gold strip on conv top │
          │  → commit dock          │
          └────────┬────────────────┘
                   │
                   ▼
          ┌─────────────────────────┐
          │         DOCKED          │
          └─────────────────────────┘
```

### 5.7 Visual Guides (Guides.lua)

```lua
-- src/ReplayFrame/EditMode/Guides.lua
-- Guide lines rendered on a UIParent-level frame at DIALOG strata
-- EnableMouse(false) so they don't intercept clicks

local GuidesFrame = CreateFrame("Frame", nil, UIParent)
GuidesFrame:SetFrameStrata("DIALOG")
GuidesFrame:SetFrameLevel(500)
GuidesFrame:SetAllPoints(UIParent)
GuidesFrame:EnableMouse(false)

-- Guide line appearance:
--   Snap preview: { 0.3, 0.7, 1.0, 0.6 } cyan, 1px width
--   Dock preview: { 0.82, 0.69, 0.35, 0.7 } gold strip on conv top edge
--   Screen center: { 0.5, 0.5, 0.5, 0.4 } gray crosshair
-- Lines extend full screen width/height (not just between windows)
-- Fade-in: 0.15s alpha transition when snap candidate enters range
-- Immediate hide when candidate leaves range or drag stops
```

---

## 6. Overlay System

### 6.1 OverlayFactory (OverlayFactory.lua)

Creates and manages per-window overlays. Separated from window controllers.

```lua
-- src/ReplayFrame/EditMode/OverlayFactory.lua

local OverlayFactory = {}

function OverlayFactory:EnsureOverlay(controller)
    if controller.overlay then return controller.overlay end
    -- Create overlay as child of the managed frame
    local ov = CreateFrame("Frame", nil, controller.frame, "BackdropTemplate")
    ov:SetAllPoints(controller.frame)
    ov:SetFrameLevel(controller.frame:GetFrameLevel() + 10)
    -- ... fill, border, label, hint, badge, grip (see below)
    controller.overlay = ov
    self:WireScripts(controller, ov)
    return ov
end
```

### 6.2 Six Visual States

| State | Fill RGBA | Border RGBA | Label | Hint | Grip |
|-------|-----------|-------------|-------|------|------|
| `default` | `0.30, 0.30, 0.30, 0.05` | `0.50, 0.45, 0.35, 0.40` | hidden | hidden | visible if resizable |
| `hovered` | `0.30, 0.60, 0.90, 0.20` | `0.40, 0.70, 1.00, 0.80` | hidden | "Click to Edit" | highlighted |
| `selected` | `0.69, 0.57, 0.31, 0.35` | `0.82, 0.69, 0.35, 0.90` | window label | hidden | highlighted |
| `dragging` | `0.69, 0.57, 0.31, 0.25` | `0.90, 0.75, 0.40, 1.00` | window label | hidden | hidden |
| `resizing` | `0.69, 0.57, 0.31, 0.30` | `0.82, 0.69, 0.35, 0.90` | size text | hidden | highlighted + active |
| `locked` | `0.40, 0.40, 0.40, 0.10` | `0.50, 0.50, 0.50, 0.50` | 🔒 + label | "Locked" | hidden |

### 6.3 State Transitions

```
default ──(mouse enter)──► hovered
hovered ──(mouse leave)──► default
hovered ──(click)──► selected
selected ──(other window clicked)──► default
selected ──(drag start)──► dragging
dragging ──(drag stop)──► selected
selected ──(resize start)──► resizing
resizing ──(resize stop)──► selected
any ──(lock toggled on)──► locked
locked ──(lock toggled off)──► default
```

### 6.4 Overlay Components

Each overlay contains:
- **Fill texture** — `SetColorTexture()` with state-dependent RGBA
- **Border** — `SetBackdrop()` with `UI-Tooltip-Border` edge file
- **Center label** — `GameFontNormalLarge`, shows window name when selected
- **Hint text** — `GameFontNormal`, shows "Click to Edit" on hover
- **Top-left badge** — small pill showing "CLN: Conversation" or "CLN: Model"
- **Resize grip** — bottom-right, standard chat resize textures, visible when resizable + not locked
- **Lock icon** — top-right corner when locked

### 6.5 Keyboard Focus

Selected overlay receives keyboard input:
- **Arrow keys** — nudge (Shift=1px, plain=5px, Ctrl=20px)
- **Tab** — cycle to next CLN window
- **Shift+Tab** — cycle to previous
- **Esc** — deselect (propagate to Blizzard)
- `SetPropagateKeyboardInput(true)` for unhandled keys
- Active `EditBox` in settings panel takes priority over overlay keyboard

---

## 7. Per-Layout Persistence

### 7.1 Schema v2

```lua
db.profile.editMode = {
    schemaVersion = 2,

    layouts = {
        ["Layout Name"] = {
            conversation = {
                pos       = { point="CENTER", relativePoint="CENTER",
                              x=500, y=0, x_pct=0.26, y_pct=0.50 },
                size      = { width=475, height=165 },
                scale     = 1.0,
                textScale = 1.0,
            },
            model = {
                docked = true,
                pos    = { point="BOTTOMLEFT", relativePoint="BOTTOMLEFT",
                           x=500, y=180, x_pct=0.26, y_pct=0.17 },
                size   = { width=475, height=140 },
            },
        },
    },

    exclude = {
        conversation = {
            pos       = false,
            size      = false,
            scale     = false,
            textScale = false,
        },
        model = {
            docked = false,
            pos    = false,
            size   = false,
        },
    },
}
```

### 7.2 Nil Semantics

- `nil` in a layout bucket field = **"inherit from global profile default"**
- `false` in exclude table = **"include in per-layout persistence"** (default)
- `true` in exclude table = **"exclude — use global value across all layouts"**
- `model.pos = nil` when `model.docked = true` = **valid** (position derived from dock anchor)

### 7.3 Migration (v1 → v2)

```lua
function Persistence:Migrate()
    local profile = CLN.db.profile
    if profile.editMode and profile.editMode.schemaVersion then return end

    -- Backup shadow (removed next addon version)
    profile._editModeLegacyBackup = CopyTable(profile.editModeLayouts or {})

    local migrated = { schemaVersion = 2, layouts = {}, exclude = {} }

    -- Migrate per-layout data
    local old = profile.editModeLayouts or {}
    for name, v1 in pairs(old) do
        if type(v1) == "table" then
            migrated.layouts[name] = {
                conversation = {
                    scale     = v1.frameScale,
                    textScale = v1.queueTextScale,
                    size      = v1.frameSize,
                    pos       = v1.framePos,
                },
                model = {
                    docked = true,  -- v1 was always docked
                    size   = {
                        width  = v1.frameSize and v1.frameSize.width or 475,
                        height = v1.npcModelFrameHeight or 140,
                    },
                    pos    = nil,   -- docked → position derived from anchor
                },
            }
        end
    end

    -- Migrate exclude config
    local oldExclude = profile.editModeExclude or {}
    migrated.exclude = {
        conversation = {
            pos       = oldExclude.framePos or false,
            size      = oldExclude.frameSize or false,
            scale     = oldExclude.frameScale or false,
            textScale = oldExclude.queueTextScale or false,
        },
        model = {
            docked = false,
            pos    = oldExclude.framePos or false,
            size   = oldExclude.npcModelFrameHeight or false,
        },
    }

    profile.editMode = migrated
end
```

### 7.4 Persist / Apply Flow

```lua
function Persistence:PersistAll()
    local name = self:GetActiveLayoutName()
    if not name then return end
    local store = CLN.db.profile.editMode.layouts
    local bucket = store[name] or {}
    local exclude = CLN.db.profile.editMode.exclude

    Registry:ForEach(function(id, controller)
        local wExclude = exclude[id] or {}
        local state = controller:ReadState()
        local wBucket = bucket[id] or {}
        for key, value in pairs(state) do
            if not wExclude[key] then
                wBucket[key] = value
            end
        end
        bucket[id] = wBucket
    end)

    store[name] = bucket
end

function Persistence:ApplyLayout(name)
    if not name then return end
    if InCombatLockdown() then
        self._pendingApply = name
        return
    end
    local data = CLN.db.profile.editMode.layouts[name]
    if not data then return end
    Registry:ForEach(function(id, controller)
        if data[id] then
            controller:ApplyState(data[id])
        end
    end)
end
```

### 7.5 Orphan Layout Handling

- Keep orphan buckets indefinitely (layout may return)
- Future: add "Clean Unused Layout Data" button in Layout Manager

---

## 8. EditPanel Refactor

### 8.1 Stacked Sections with Selector Pills

```
+-------------------------------------------+
|  Chatty Little NPC               [X]      |
|  Layout: My Raid Layout                   |
+---------+---------+---------+-------------+
| ● Conv  |  Model  | Layout  |             |
+---------+---------+---------+-------------+
|                                           |
|  ▼ Conversation Window                    |
|  ─────────────────────────                |
|  Scale       [<] ====+====== [>]  [1.00]  |
|  Width       [<] ====+====== [>]  [ 475]  |
|  Height      [<] ====+====== [>]  [ 165]  |
|  Text Scale  [<] ====+====== [>]  [1.00]  |
|                                           |
|  [ ] Exclude pos from per-layout save     |
|  [ ] Exclude size from per-layout save    |
|  [ ] Exclude scale from per-layout save   |
|                                           |
+-------------------------------------------+
|  [     Save Changes     ]                 |
|  [    Revert Changes    ]                 |
|  [ Layouts ]  [ Import/Export ]           |
|  [     Reset Defaults     ]              |
+-------------------------------------------+
```

### 8.2 Section Visibility Rules

- **Selector pills** at top: Conversation / Model / Layout
- Clicking a pill → shows that section, hides others
- Clicking a pill also selects the corresponding window overlay (bidirectional sync)
- **Layout section** is always accessible via its pill
- **Power users**: collapsible section headers allow showing multiple sections simultaneously
- Save / Revert / bottom buttons always visible regardless of section

### 8.3 FormBuilder Extension

Reuse the existing `FormBuilder` pattern for slider rows. Each section gets its own
`FormBuilder` instance populating a section container frame.

### 8.4 Dirty Tracking

- Each section tracks its own `_orig` snapshot independently
- Panel title shows `*` if **any** section has unsaved changes
- **Save** persists all sections to the active layout
- **Revert** restores all sections from their `_orig` snapshots

### 8.5 Settings → Controller Bridge

```lua
-- Panel emits changes to controllers via a patch API:
function EditPanel:OnSliderChanged(windowId, key, value)
    local controller = Registry:Get(windowId)
    if controller then
        -- Live preview: apply immediately to frame
        controller:ApplyState({ [key] = value })
        -- Mark dirty
        self:MarkDirty(windowId, key)
    end
end

-- On Save:
function EditPanel:CommitAll()
    Persistence:PersistAll()
    self:ClearAllDirty()
end

-- On Revert:
function EditPanel:RevertAll()
    Registry:ForEach(function(id, controller)
        controller:ApplyState(self._orig[id])
    end)
    self:ClearAllDirty()
end
```

---

## 9. Import/Export

### 9.1 CLN2 Bundle Format

```
<BlizzardLayoutString>#CLN2#<Base64(payload)>
```

**Payload** (semicolon-delimited key=value, namespaced):

```
v=2;
c.pos.pt=CENTER;c.pos.rp=CENTER;c.pos.x=500;c.pos.y=0;c.pos.xp=0.26;c.pos.yp=0.50;
c.size.w=475;c.size.h=165;c.scale=1;c.ts=1;
m.docked=1;m.size.w=475;m.size.h=140;
m.pos.pt=BOTTOMLEFT;m.pos.rp=BOTTOMLEFT;m.pos.x=500;m.pos.y=180;m.pos.xp=0.26;m.pos.yp=0.17;
```

Key prefix rules:
- `c.*` — Conversation window
- `m.*` — Model window
- `v` — Format version

### 9.2 Backward Compatibility

```lua
function ImportExport:Import(bundle, opts)
    if bundle:find("#CLN2#", 1, true) then
        return self:ImportV2(bundle, opts)
    elseif bundle:find("#CLN1#", 1, true) then
        return self:ImportV1(bundle, opts)  -- map old keys to conversation
    end
    return nil, "No CLN bundle marker found"
end
```

**CLN1 import** maps old keys to conversation-only data:
- `fs` → `conversation.scale`, `ts` → `conversation.textScale`
- `w/h` → `conversation.size`, `pt/rp/px/py` → `conversation.pos`
- Model gets default docked state

### 9.3 Independent Block Parsing

Invalid model block does NOT abort conversation import. Invalid conversation block does NOT
abort Blizzard layout import. Each block parsed independently with error reporting.

### 9.4 Export Options

- **Default**: Export CLN2 (both windows)
- **"Blizzard Only"**: Export Blizzard layout string without CLN suffix (for sharing with non-Chatty users)

---

## 10. File Structure & Load Order

### 10.1 New File Layout

```
src/ReplayFrame/
├── EditMode/
│   ├── Window.lua              NEW  ~100 LOC  Shared utilities (GetRect, SerializePosition, etc.)
│   ├── ConversationWindow.lua  NEW  ~120 LOC  Conversation adapter (ReadState, ApplyState, etc.)
│   ├── ModelWindow.lua         NEW  ~150 LOC  Model adapter (dock/undock, ReadState, ApplyState)
│   ├── Registry.lua            NEW  ~120 LOC  Singleton (selection, lifecycle, cycling)
│   ├── OverlayFactory.lua      NEW  ~250 LOC  Overlay creation, 6 states, grips, scripts
│   ├── SnapManager.lua         NEW  ~250 LOC  Grid snap, pairwise snap, hysteresis, dock check
│   ├── Guides.lua              NEW  ~120 LOC  UIParent-level snap guide line rendering
│   ├── Persistence.lua         NEW  ~250 LOC  Schema v2, migration, persist/apply, layout name
│   ├── ImportExport.lua        NEW  ~200 LOC  CLN2 encode/decode, CLN1 compat, Blizzard-only
│   └── Init.lua                NEW  ~100 LOC  Bootstrap: create controllers, register, wire hooks
├── EditPanel.lua               MOD  ~900 LOC  Stacked sections, selector pills, FormBuilder
├── Position.lua                MOD  ~minor    Delegate to Persistence
├── UI.lua                      —    unchanged
├── ModelFrame.lua              MOD  ~minor    Remove edit-mode-specific logic
└── ...
```

### 10.2 TOC Load Order

```
src/ReplayFrame/EditMode/Window.lua
src/ReplayFrame/EditMode/Registry.lua
src/ReplayFrame/EditMode/OverlayFactory.lua
src/ReplayFrame/EditMode/SnapManager.lua
src/ReplayFrame/EditMode/Guides.lua
src/ReplayFrame/EditMode/Persistence.lua
src/ReplayFrame/EditMode/ImportExport.lua
src/ReplayFrame/EditMode/ConversationWindow.lua
src/ReplayFrame/EditMode/ModelWindow.lua
src/ReplayFrame/EditMode/Init.lua
src/ReplayFrame/EditPanel.lua
```

### 10.3 LOC Budget

| File | LOC | Source |
|------|:---:|--------|
| Window.lua | ~100 | New shared utilities |
| ConversationWindow.lua | ~120 | New adapter |
| ModelWindow.lua | ~150 | New adapter (dock logic) |
| Registry.lua | ~120 | New singleton |
| OverlayFactory.lua | ~250 | Extracted + 6-state expansion |
| SnapManager.lua | ~250 | New (grid + pairwise + hysteresis + dock) |
| Guides.lua | ~120 | New (UIParent guide lines) |
| Persistence.lua | ~250 | Extracted + v2 schema + migration |
| ImportExport.lua | ~200 | Extracted + CLN2 + CLN1 compat |
| Init.lua | ~100 | New bootstrap |
| EditPanel.lua (modified) | ~900 | Stacked sections + pills |
| **Total** | **~2560** | vs current ~2430 (monolith + panel) |

Net change: ~130 lines added. Code is now modular with single-responsibility files.

---

## 11. Interaction Design

### 11.1 Full User Flow

**Edit Mode Enter:**
1. Both windows appear with `default` overlay state (very subtle — 0.05 alpha)
2. If queue is empty, sample data injected into conversation window
3. If no model loaded, player model preview shown in model window
4. "Chatty NPC" button visible in EditModeManagerFrame

**Window Selection:**
5. Mouse enters model overlay → `hovered` state (blue, "Click to Edit")
6. Click model overlay → `selected` state (gold, label shown)
7. Conversation overlay returns to `default`
8. EditPanel opens/switches to Model section
9. Bidirectional: clicking Model pill in panel also selects model overlay

**Independent Drag:**
10. Drag conversation → conversation moves, docked model follows
11. Drag model while docked → **undock transition** (preserves screen position), model moves freely
12. Model approaches conversation top edge → cyan snap guide line appears
13. Release within dock threshold → 3-gate check → dock (gold strip confirms)
14. Release outside threshold → free position persisted

**Resize:**
15. Drag bottom-right grip → frame resizes within bounds
16. On release → snap check → persist

**Edit Mode Exit:**
17. Both overlays hidden
18. Sample data cleared
19. Final state persisted to active layout
20. If queue empty and no audio playing, frames auto-hide

### 11.2 Keyboard Shortcuts

| Key | Context | Action |
|-----|---------|--------|
| Arrow keys | Window selected | Nudge 5px |
| Shift+Arrow | Window selected | Nudge 1px (fine) |
| Ctrl+Arrow | Window selected | Nudge 20px (coarse) |
| Tab | Any CLN state | Cycle selection: Conv → Model → Conv |
| Shift+Tab | Any CLN state | Reverse cycle |
| Esc | Window selected | Clear CLN selection (propagate to Blizzard) |
| Esc | Panel focused | Close panel |

### 11.3 Onboarding (One-Time)

On first Edit Mode entry after upgrade:
- Toast notification: *"Chatty NPC now has 2 independent windows! Click each to customize. Tab cycles between them."*
- Both windows pulse with subtle glow (3 cycles, 1s each)
- Guarded by `db.profile._seenTwoWindowOnboarding`
- Suppressed on Classic (no Edit Mode)

### 11.4 Reload / Login Recovery

- `/reload` during Edit Mode: `EDIT_MODE_LAYOUTS_UPDATED(reconcile=true)` fires
- Clear transient state (selection, drag, guides)
- Re-apply active layout settings
- Do NOT reopen Edit Mode overlays (user must re-enter Edit Mode)

---

## 12. Risk Analysis

### Taint

| Risk | Severity | Mitigation |
|------|----------|------------|
| Hooking EditModeManagerFrame methods | Low | `hooksecurefunc` only (read-only). Production-proven in current code. |
| Reading C_EditMode.GetAccountSettings | Low | Read-only, wrapped in `pcall`. No writes to Blizzard settings. |
| CLN snap interfering with Blizzard snap | None | Fully independent `SnapManager`. Never registers with Blizzard magnetism. |
| Button injection in EditModeManagerFrame | Medium | Anchor to semantic elements with retry + fallback. Idempotent reattach on manager show. |

### Performance

| Risk | Severity | Mitigation |
|------|----------|------------|
| OnUpdate during drag for snap | Low | Only 2 windows = O(1) comparison. Throttle guide refresh to cursor delta ≥ 1px. |
| Overlay creation | Low | Lazy creation, one-time per session. Simple frames with textures. |
| Persist on every drag stop | Low | Debounce: coalesce rapid drag-stops into single write after 0.5s idle. |

### User Confusion

| Risk | Severity | Mitigation |
|------|----------|------------|
| Users don't realize two windows exist | Medium | Onboarding toast + both overlays visible on Edit Mode enter. |
| Accidental undock | Medium | 3-gate dock protection. Snap guides show dock preview. "Reset Defaults" re-docks. |
| Overlapping overlays when docked | Low | Default state is 0.05 alpha — nearly invisible. Only selected window is prominent. |

### SavedVariables

| Risk | Severity | Mitigation |
|------|----------|------------|
| Migration fails mid-flight | Medium | `schemaVersion` gate (idempotent). One-version backup shadow in `_editModeLegacyBackup`. |
| v1 code reads v2 data | Low | v2 uses nested tables. v1 code looking for `frameScale` at top level falls to defaults. Safe degradation. |
| Orphan layout entries | Low | Kept by default. Future cleanup button. Negligible memory (~1KB per orphan). |

### Classic WoW

| Risk | Severity | Mitigation |
|------|----------|------------|
| No Edit Mode API | Low | `hasAPI` guard. Window controllers work for manual drag/resize. No overlay/snap on Classic. |
| Nil from retail-only globals | Low | All `EditModeManagerFrame`/`C_EditMode` access behind `hasAPI` or `pcall`. |

---

## 13. Implementation Phases

### Dependency Graph

```
Phase 1 ──► Phase 2 ──► Phase 3
  │                       │
  │           Phase 4 ◄───┘
  │             │
  └──► Phase 5  │
         │      │
         ▼      ▼
       Phase 6 (final)
```

### Phase 1: Persistence + Window Adapters

**Goal:** Data layer works; both windows serialize/apply independent state.

| Task | File | Description |
|------|------|-------------|
| 1.1 | `Window.lua` | Shared utilities: GetRect, SerializePosition, ApplyPosition, ClampToScreen |
| 1.2 | `Persistence.lua` | Schema v2, migration from v1, backup shadow, GetActiveLayoutName, PersistAll, ApplyLayout |
| 1.3 | `ConversationWindow.lua` | Adapter: ReadState, ApplyState, GetDefaultState, resize bounds |
| 1.4 | `ModelWindow.lua` | Adapter: ReadState, ApplyState, dock/undock, resize bounds |
| 1.5 | Classic guard | Ensure all modules degrade when `hasAPI = false` |

**Verification gate:** Manually call `ConversationWindow:ReadState()` and `ModelWindow:ReadState()`, serialize to SV, `/reload`, verify `ApplyState()` restores correctly. Verify v1→v2 migration preserves all existing layout data. Verify backup shadow exists.

### Phase 2: Registry + Overlay Factory

**Goal:** Both overlays render independently with correct visual states.

| Task | File | Description |
|------|------|-------------|
| 2.1 | `Registry.lua` | Singleton: Register, Select, CycleSelection, ForEach, OnEnter, OnExit |
| 2.2 | `OverlayFactory.lua` | Create overlays, 6 visual states, grips, labels, badges, script wiring |
| 2.3 | `Init.lua` | Bootstrap: create controllers, register, wire `hooksecurefunc` hooks + events |
| 2.4 | Remove old code | Delete overlay logic from `EditModeIntegration.lua`, redirect to new system |

**Verification gate:** Enter Edit Mode → both overlays appear. Click each → gold selection. Hover → blue. Tab cycles. Esc deselects. Blizzard system click clears CLN selection. Exit Edit Mode → overlays hide.

### Phase 3: Snap Manager + Visual Guides

**Goal:** Drag interactions feel stable and deterministic.

| Task | File | Description |
|------|------|-------------|
| 3.1 | `SnapManager.lua` | Grid snap, pairwise snap (6 candidates), hysteresis, dock eligibility check |
| 3.2 | `Guides.lua` | UIParent-level guide line rendering, fade-in/out, dock preview strip |
| 3.3 | Wire into drag | Integrate snap into `OnDragStop`. Show guides during `OnUpdate` while dragging. |
| 3.4 | Dock state machine | Undock-on-drag + dock-on-release with 3-gate protection |

**Verification gate:** Drag model near conversation → snap guide appears → release → docks. Drag model far → no snap → free position. Grid snap works when Blizzard grid enabled. Hysteresis prevents jitter. Dragging docked model undocks smoothly (no position jump).

### Phase 4: EditPanel Refactor

**Goal:** User can configure both windows from one coherent panel.

| Task | File | Description |
|------|------|-------------|
| 4.1 | `EditPanel.lua` | Stacked sections with selector pills (Conversation / Model / Layout) |
| 4.2 | Section content | FormBuilder sliders per-window; exclude checkboxes per-field |
| 4.3 | Bidirectional sync | Panel pill click ↔ overlay selection |
| 4.4 | Dirty tracking | Per-section `_orig` snapshots; save/revert operates on all sections |
| 4.5 | Model section | Dock/undock toggle, redock button, size controls |

**Verification gate:** Click model overlay → panel shows Model section. Change slider → live preview on frame. Save → persisted. Revert → restored. Dirty indicator shows `*` when changed.

### Phase 5: Import/Export CLN2

**Goal:** Full round-trip for both windows.

| Task | File | Description |
|------|------|-------------|
| 5.1 | `ImportExport.lua` | CLN2 format encode/decode with `c.*`/`m.*` namespaced keys |
| 5.2 | CLN1 backward compat | Map v1 keys to conversation-only data |
| 5.3 | Independent block parsing | Model failure doesn't abort conversation; conversation failure doesn't abort Blizzard |
| 5.4 | Blizzard-only export | Secondary action for sharing with non-Chatty users |
| 5.5 | `/clnexp` `/clnimp` | Update slash commands for CLN2 |

**Verification gate:** Export → reimport → identical state. Import CLN1 bundle → conversation restored, model defaults. Import with corrupted model block → conversation still imports. Blizzard-only export contains no `#CLN` marker.

### Phase 6: Integration Polish + Onboarding

**Goal:** Fully integrated retail UX, Classic validated.

| Task | File | Description |
|------|------|-------------|
| 6.1 | Onboarding toast | One-time 4-point message + glow animation |
| 6.2 | "Chatty NPC" button | Updated behavior: opens panel, selects conversation if none selected |
| 6.3 | Blizzard hooks | RevertAllChanges hook, unsaved changes dialog, layout switch |
| 6.4 | Reload recovery | Clear transient state on `EDIT_MODE_LAYOUTS_UPDATED(reconcile=true)` |
| 6.5 | Preview staging | Auto-inject sample data + player model on Edit Mode enter if queue empty |
| 6.6 | Classic validation | Verify no nil-path regressions on Classic branches |
| 6.7 | Cleanup | Remove `EditModeIntegration.lua` (replaced by Init.lua + modules) |

**Verification gate:** Full end-to-end test matrix:
- Enter/exit Edit Mode ✓
- Both windows drag/resize/snap independently ✓
- Layout switch applies correct per-layout state ✓
- Import/export round-trip ✓
- Reload during Edit Mode recovers cleanly ✓
- Classic client loads without errors ✓
- Onboarding shows exactly once ✓
- Combat lockdown defers frame moves ✓

---

## 14. Open Questions for User

1. **Model resize in v1** — Should the model window be resizable via grip in Edit Mode, or only via panel sliders? (Plan assumes grip-resizable; can be disabled.)

2. **Dock presets** — Currently only "model above conversation" docking. Should we add "model left" / "model right" in v1, or defer to v2? (Plan defers.)

3. **Undo/redo** — The brainstorm scored this at 19.7. Should we add a circular undo buffer (8 states, Ctrl+Z) as part of this refactor, or defer? (Plan defers — can be added to Phase 4.)

4. **Preview staging** — Should Edit Mode auto-inject a preview NPC model + sample queue text when entering Edit Mode with empty queue? (Plan includes this in Phase 6.)

5. **Curated presets** — Should we ship pre-built layout presets (Cinematic, Compact, Streamer)? (Deferred — depends on this refactor being complete first.)

---

## Appendix A: Coordinate Space Rules

All snap math operates in **UIParent-space pixels** (normalized by effective scale):

```lua
local function ToUIParentSpace(frame)
    local scale = frame:GetEffectiveScale() or 1
    local uiScale = UIParent:GetEffectiveScale() or 1
    local ratio = scale / uiScale
    return {
        left   = (frame:GetLeft()   or 0) * ratio,
        right  = (frame:GetRight()  or 0) * ratio,
        top    = (frame:GetTop()    or 0) * ratio,
        bottom = (frame:GetBottom() or 0) * ratio,
    }
end
```

**Persistence** stores positions as UIParent-relative anchor + offset in UIParent units,
plus `x_pct`/`y_pct` for cross-resolution sharing.

**Never** mix frame-local coordinates with UIParent-space in the same formula.

## Appendix B: Glossary

| Term | Definition |
|------|-----------|
| **Window Controller** | Flat table implementing the CLNWindowController interface for one frame |
| **Registry** | Singleton managing all window controllers, selection, and lifecycle |
| **OverlayFactory** | Creates and manages visual overlays for each window controller |
| **SnapManager** | Computes snap offsets (grid + pairwise + dock) with hysteresis |
| **Guides** | UIParent-level frame rendering snap preview lines |
| **Persistence** | Handles v2 schema, migration, per-layout save/load |
| **Conversation Window** | DisplayFrame + ContentFrame — the text/queue area |
| **Model Window** | ModelContainer + NpcModelFrame — the 3D NPC model |
| **Dock** | Model anchored to conversation top edge, moves as a unit |
| **Undock** | Model free-floating with absolute UIParent position |
| **Bundle** | Serialized string: Blizzard layout + CLN addon data |
| **CLN1** | Legacy bundle format (single-window) |
| **CLN2** | New bundle format (two-window, namespaced keys) |
| **Exclude** | Per-field opt-out from per-layout persistence |
| **Hysteresis** | Snap hold: current snap maintained until beaten by ≥3px |
