---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode
local Window = EditMode.Window
local DEFAULT_W = CLN.DEFAULT_FRAME_WIDTH

-- ============================================================================
-- Model Window Adapter
-- ============================================================================
-- Manages the Model window (ModelContainer + NpcModelFrame) as an
-- Edit Mode citizen. Implements the CLNWindowController interface.
-- Handles dock/undock state transitions.
-- ============================================================================

local ModelWindow = {
    id       = "model",
    label    = "Model",
    -- State (transient, not persisted)
    selected = false,
    hovered  = false,
    locked   = false,
    overlay  = nil,
    frame    = nil,
    _docked  = true,    -- default: docked above conversation
}

EditMode.ModelWindow = ModelWindow

-- ============================================================================
-- CLNWindowController Interface
-- ============================================================================

--- Ensure the managed frame exists and cache it.
--- Attempts lazy initialization if ModelContainer hasn't been created yet.
---@return Frame|nil
function ModelWindow:EnsureFrame()
    if not self.frame then
        self.frame = ReplayFrame.ModelContainer
        -- Try lazy init if container doesn't exist yet
        if not self.frame and ReplayFrame.InitializeModelContainer then
            ReplayFrame:InitializeModelContainer()
            self.frame = ReplayFrame.ModelContainer
        end
    end
    return self.frame
end

--- Read the current live state for persistence.
---@return table state
function ModelWindow:ReadState()
    local f = self:EnsureFrame()
    local state = {
        docked = self:IsDocked(),
    }

    if f then
        state.size = Window.SerializeSize(f)
        if not state.docked then
            state.pos = Window.SerializePosition(f)
        end
    end

    return state
end

--- Apply a (possibly partial) state table to the live frame.
---@param state table
function ModelWindow:ApplyState(state)
    if not state then return end
    local f = self:EnsureFrame()
    if not f then return end

    if state.size and state.size.width and state.size.height then
        f:SetSize(state.size.width, state.size.height)
        CLN.db.profile.npcModelFrameHeight = state.size.height
        ReplayFrame.npcModelFrameHeight = state.size.height
        -- Also update NpcModelFrame if it exists
        if ReplayFrame.NpcModelFrame then
            ReplayFrame.NpcModelFrame:SetHeight(state.size.height)
        end
    end

    -- The portrait is always docked to the conversation window; saved layouts
    -- from when it could float (docked = false + pos) dock it too.
    self:Dock()
end

--- Return default state (docked above conversation).
---@return table
function ModelWindow:GetDefaultState()
    return {
        docked = true,
        size   = { width = DEFAULT_W, height = 140 },
    }
end

--- Return resize constraints.
---@return table {minW, minH, maxW, maxH}
function ModelWindow:GetResizeBounds()
    return { minW = 100, minH = 80, maxW = 600, maxH = 500 }
end

function ModelWindow:CanResize()
    return true
end

--- Always visible in Edit Mode, even if hidden in Compact Mode.
function ModelWindow:IsVisibleInEditMode()
    return true
end

-- ============================================================================
-- Dock / Undock
-- ============================================================================

--- Whether the model is currently docked to the conversation window.
---@return boolean
function ModelWindow:IsDocked()
    return self._docked ~= false
end

--- Dock the model above the conversation window.
--- Uses SetPoint anchoring so it moves with conversation automatically.
function ModelWindow:Dock()
    local f = self:EnsureFrame()
    if not f then return end

    local Registry = EditMode.Registry
    local conv = Registry and Registry:Get("conversation")
    local convFrame = conv and conv:EnsureFrame()

    if convFrame then
        self._docked = true
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", convFrame, "TOPLEFT", 0, 2)
        f:SetPoint("BOTTOMRIGHT", convFrame, "TOPRIGHT", 0, 2)
        -- Clear legacy undocked position
        CLN.db.profile.modelFramePos = nil
    else
        -- No conversation frame yet — clear legacy key first, then try LayoutModelArea
        self._docked = true
        CLN.db.profile.modelFramePos = nil
        if ReplayFrame.LayoutModelArea and ReplayFrame.DisplayFrame then
            ReplayFrame:LayoutModelArea(ReplayFrame.DisplayFrame)
        end
    end
end

--- The portrait can no longer float on its own (a saved floating position
--- could leave it off-screen), so undocking just keeps it docked.
function ModelWindow:Undock()
    self:Dock()
end

--- Initialize dock state on addon load. The portrait is always docked; drop
--- any floating position saved by older versions.
function ModelWindow:InitDockState()
    self._docked = true
    CLN.db.profile.modelFramePos = nil
end

return ModelWindow
