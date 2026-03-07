---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode
local Window = EditMode.Window

-- ============================================================================
-- Conversation Window Adapter
-- ============================================================================
-- Manages the Conversation window (DisplayFrame + ContentFrame) as an
-- Edit Mode citizen. Implements the CLNWindowController interface.
-- ============================================================================

local ConversationWindow = {
    id       = "conversation",
    label    = "Conversation",
    -- State (transient, not persisted)
    selected = false,
    hovered  = false,
    locked   = false,
    overlay  = nil,
    frame    = nil,
}

EditMode.ConversationWindow = ConversationWindow

-- ============================================================================
-- CLNWindowController Interface
-- ============================================================================

--- Ensure the managed frame exists and cache it.
---@return Frame
function ConversationWindow:EnsureFrame()
    if not self.frame then
        self.frame = ReplayFrame.DisplayFrame
            or (ReplayFrame.GetDisplayFrame and ReplayFrame:GetDisplayFrame())
    end
    return self.frame
end

--- Read the current live state for persistence.
---@return table state
function ConversationWindow:ReadState()
    local f = self:EnsureFrame()
    local state = {}

    state.scale     = CLN.db.profile.frameScale or 1.0
    state.textScale = CLN.db.profile.queueTextScale or 1.0

    if f then
        state.size = Window.SerializeSize(f)
        state.pos  = Window.SerializePosition(f)
    end

    return state
end

--- Apply a (possibly partial) state table to the live frame.
--- Only applies fields that are present in the state table.
--- Profile values (scale/textScale) are always written even if frame doesn't exist yet.
---@param state table
function ConversationWindow:ApplyState(state)
    if not state then return end

    -- Profile-level updates (work even before frame creation)
    if state.scale then
        CLN.db.profile.frameScale = state.scale
        if ReplayFrame.ApplyFrameScale then
            ReplayFrame:ApplyFrameScale()
        end
    end

    if state.textScale then
        CLN.db.profile.queueTextScale = state.textScale
        if ReplayFrame.ApplyQueueTextScale then
            ReplayFrame:ApplyQueueTextScale()
        end
    end

    -- Frame-level updates (require DisplayFrame to exist)
    local f = self:EnsureFrame()
    if not f then return end

    if state.size and state.size.width and state.size.height then
        -- Guard against collapsed heights
        local h = state.size.height
        if h < 80 then h = 165 end
        f:SetSize(state.size.width, h)
        CLN.db.profile.frameSize = { width = state.size.width, height = h }
        if ReplayFrame.Relayout then
            ReplayFrame:Relayout()
        end
    end

    if state.pos then
        Window.ApplyPosition(f, state.pos)
        -- Sync to legacy profile key for Position.lua compatibility
        CLN.db.profile.framePos = {
            point         = state.pos.point,
            relativePoint = state.pos.relativePoint,
            xOfs          = state.pos.x or state.pos.xOfs or 0,
            yOfs          = state.pos.y or state.pos.yOfs or 0,
        }
    end
end

--- Return default state (used by Reset Defaults).
---@return table
function ConversationWindow:GetDefaultState()
    return {
        scale     = 1.0,
        textScale = 1.0,
        size      = { width = 475, height = 165 },
        pos       = {
            point = "CENTER", relativePoint = "CENTER",
            x = 500, y = 0, x_pct = 0, y_pct = 0,
        },
    }
end

--- Return resize constraints.
---@return table {minW, minH, maxW, maxH}
function ConversationWindow:GetResizeBounds()
    return { minW = 260, minH = 120, maxW = 1000, maxH = 600 }
end

--- Whether this window supports resize via grip.
function ConversationWindow:CanResize()
    return true
end

--- Whether this window should be visible/editable in Edit Mode.
--- Always true — even if the conversation frame is hidden at runtime.
function ConversationWindow:IsVisibleInEditMode()
    return true
end

return ConversationWindow
