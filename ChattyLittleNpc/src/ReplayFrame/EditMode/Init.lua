---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode

-- ============================================================================
-- EditMode Bootstrap (Init.lua)
-- ============================================================================
-- Registers window adapters, runs migration, initializes dock state,
-- and wires Edit Mode enter/exit hooks + combat deferral.
-- Must load AFTER all other EditMode/ files and BEFORE EditModeIntegration.lua.
-- ============================================================================

local hasAPI = (C_EditMode and type(C_EditMode.GetLayouts) == "function")

local Registry    = EditMode.Registry
local Persistence = EditMode.Persistence
local ConvWindow  = EditMode.ConversationWindow
local ModelWin    = EditMode.ModelWindow

-- ============================================================================
-- Registration
-- ============================================================================

Registry:Register(ConvWindow)
Registry:Register(ModelWin)

-- ============================================================================
-- Migration & Dock State Init
-- ============================================================================
-- These run immediately at load time. CLN.db.profile may not exist yet,
-- so we defer to PLAYER_LOGIN / ADDON_LOADED via the existing Init.lua flow.
-- The EditModeIntegration:Init() function (which fires on PLAYER_LOGIN)
-- will call EditMode.Bootstrap() below.

--- Bootstrap function called from the addon's initialization flow.
--- Safe to call multiple times (idempotent).
function EditMode.Bootstrap()
    if EditMode._bootstrapped then return end

    -- Run v1 → v2 migration (idempotent — checks schemaVersion)
    Persistence:MigrateIfNeeded()

    -- Initialize model dock state from legacy profile data
    ModelWin:InitDockState()

    EditMode._bootstrapped = true
end

-- ============================================================================
-- Event Wiring
-- ============================================================================
-- Create a hidden event frame for EDIT_MODE_LAYOUTS_UPDATED and
-- PLAYER_REGEN_ENABLED. These hooks complement (not replace) the existing
-- EditModeIntegration:Init() hooks — they handle the v2 persistence layer.

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        Persistence:ApplyPendingLayout()
    end
end)

-- ============================================================================
-- Edit Mode Enter/Exit Hooks
-- ============================================================================
-- These hook into Blizzard's EditModeManagerFrame to coordinate the v2 layer.
-- They run AFTER the existing Integration hooks (since Init.lua loads later
-- in the TOC). This is safe because hooksecurefunc appends handlers.

if hasAPI and EditModeManagerFrame then
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        Registry:OnEnter()
    end)

    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        Registry:OnExit()
    end)

    -- When Blizzard selects one of its own systems, clear CLN selection
    if EditModeManagerFrame.SelectSystem then
        hooksecurefunc(EditModeManagerFrame, "SelectSystem", function()
            if Registry:GetSelected() then
                Registry:Select(nil, "blizzard")
            end
        end)
    end
end

return EditMode
