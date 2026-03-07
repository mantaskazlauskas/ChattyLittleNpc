---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode
local Window = EditMode.Window

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

    if state.docked ~= nil then
        if state.docked then
            self:Dock()
        else
            -- Always transition to undocked first, then apply position if present
            self:Undock()
            if state.pos then
                Window.ApplyPosition(f, state.pos)
                -- Sync legacy modelFramePos
                CLN.db.profile.modelFramePos = {
                    point         = state.pos.point,
                    relativePoint = state.pos.relativePoint,
                    xOfs          = state.pos.x or state.pos.xOfs or 0,
                    yOfs          = state.pos.y or state.pos.yOfs or 0,
                    width         = state.size and state.size.width or nil,
                }
            end
        end
    elseif state.pos and not self:IsDocked() then
        Window.ApplyPosition(f, state.pos)
    end
end

--- Return default state (docked above conversation).
---@return table
function ModelWindow:GetDefaultState()
    return {
        docked = true,
        size   = { width = 475, height = 140 },
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

--- Undock the model: convert from relative anchor to absolute UIParent position.
--- Preserves current screen position so the frame doesn't visually jump.
function ModelWindow:Undock()
    local f = self:EnsureFrame()
    if not f then return end

    -- Capture current screen position before detaching
    local cx, cy = f:GetCenter()
    if not (cx and cy) then return end

    local s = f:GetEffectiveScale() or 1
    local uiS = UIParent:GetEffectiveScale() or 1
    local relX = (cx * s) / uiS
    local relY = (cy * s) / uiS

    self._docked = false
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", relX, relY)

    -- Sync legacy modelFramePos
    local w = f:GetWidth()
    CLN.db.profile.modelFramePos = {
        point         = "CENTER",
        relativePoint = "BOTTOMLEFT",
        xOfs          = relX,
        yOfs          = relY,
        width         = w and math.floor(w + 0.5) or nil,
    }
end

--- Initialize dock state from saved profile data.
--- Call on addon load to sync _docked flag with legacy modelFramePos.
function ModelWindow:InitDockState()
    local pos = CLN.db.profile.modelFramePos
    if type(pos) == "table" and pos.point and pos.relativePoint then
        self._docked = false
    else
        self._docked = true
        -- Clean up any malformed truthy value
        if pos ~= nil and type(pos) ~= "table" then
            CLN.db.profile.modelFramePos = nil
        end
    end
end

return ModelWindow
