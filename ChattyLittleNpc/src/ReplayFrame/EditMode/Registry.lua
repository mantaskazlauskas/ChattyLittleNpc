---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode

-- ============================================================================
-- Window Registry
-- ============================================================================
-- Singleton that manages all Edit Mode window controllers.
-- Handles selection, lifecycle, and cross-window coordination.
-- ============================================================================

local Registry = {
    _windows  = {},                           -- { [CLNWindowId] = controller }
    _selected = nil,                          -- CLNWindowId or nil
    _active   = false,                        -- Edit Mode currently active?
    _order    = { "conversation", "model" },  -- Tab cycling order
}

EditMode.Registry = Registry

-- ============================================================================
-- Registration
-- ============================================================================

--- Register a window controller.
---@param controller table CLNWindowController
function Registry:Register(controller)
    self._windows[controller.id] = controller
end

--- Unregister a window controller.
---@param id string
function Registry:Unregister(id)
    self._windows[id] = nil
    if self._selected == id then
        self._selected = nil
    end
end

--- Get a registered controller by id.
---@param id string
---@return table|nil controller
function Registry:Get(id)
    return self._windows[id]
end

--- Iterate all registered controllers in defined order.
---@param fn fun(id: string, controller: table)
function Registry:ForEach(fn)
    for _, id in ipairs(self._order) do
        local w = self._windows[id]
        if w then fn(id, w) end
    end
end

--- Get all controllers except the given id.
---@param excludeId string
---@return table[] controllers
function Registry:GetOthers(excludeId)
    local others = {}
    for _, id in ipairs(self._order) do
        local w = self._windows[id]
        if w and id ~= excludeId then
            others[#others + 1] = w
        end
    end
    return others
end

-- ============================================================================
-- Selection
-- ============================================================================

--- Select a window (or nil to clear selection).
--- Only one CLN window can be selected at a time.
--- Clears Blizzard Edit Mode selection when a CLN window is selected.
---@param id string|nil
---@param source? string "overlay"|"panel"|"keyboard" (prevents sync loops)
function Registry:Select(id, source)
    -- Deselect previous
    if self._selected and self._selected ~= id then
        local prev = self._windows[self._selected]
        if prev then
            prev.selected = false
            -- OverlayFactory will handle visual state updates when available
        end
    end

    self._selected = id

    if id then
        local w = self._windows[id]
        if w then
            w.selected = true
        end
        -- Clear Blizzard selection to avoid visual conflicts
        self:ClearBlizzardSelection()
    end
end

--- Get the currently selected window id.
---@return string|nil
function Registry:GetSelected()
    return self._selected
end

--- Cycle selection to the next/previous CLN window.
---@param reverse? boolean
function Registry:CycleSelection(reverse)
    local order = self._order
    local cur = self._selected
    local idx = 0
    for i, id in ipairs(order) do
        if id == cur then idx = i; break end
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

--- Clear Blizzard's Edit Mode system selection.
function Registry:ClearBlizzardSelection()
    if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
        EditModeManagerFrame:ClearSelectedSystem()
    end
    if EditModeSystemSettingsDialog
       and EditModeSystemSettingsDialog.IsShown
       and EditModeSystemSettingsDialog:IsShown() then
        EditModeSystemSettingsDialog:Hide()
    end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

--- Called when Edit Mode is entered.
function Registry:OnEnter()
    self._active = true
    self:ForEach(function(id, controller)
        controller:EnsureFrame()
        -- OverlayFactory will show overlays when wired in Phase 2
    end)
end

--- Called when Edit Mode is exited.
function Registry:OnExit()
    self._active = false
    self._selected = nil
    self:ForEach(function(id, controller)
        controller.selected = false
        -- OverlayFactory will hide overlays when wired in Phase 2
    end)
    -- Persist final state
    local Persistence = EditMode.Persistence
    if Persistence then
        Persistence:PersistAll()
        Persistence:SyncToLegacyProfile()
    end
end

--- Whether Edit Mode is currently active.
---@return boolean
function Registry:IsActive()
    return self._active
end

return Registry
