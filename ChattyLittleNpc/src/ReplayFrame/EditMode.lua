---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")
---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- LEGACY EDIT MODE FILE (DEPRECATED)
-- ============================================================================
-- All functionality has moved to EditModeIntegration.lua
-- This file remains as a thin adapter so any older references do not error.
-- Safe to remove after confirming no external calls depend on these wrappers.
-- ============================================================================

local function log(msg)
    if CLN and CLN.Logger then CLN.Logger:debug("[LegacyEditMode] "..msg, false, CLN.Utils.LogCategories.ui) end
end

function ReplayFrame:BindBlizzardEditMode()
    -- Delegate to new integration init.
    if self.InitEditModeIntegration then self:InitEditModeIntegration() end
    log("BindBlizzardEditMode deprecated; forwarded to InitEditModeIntegration")
end

function ReplayFrame:SetEditMode(enable)
    -- Show / hide overlay only.
    if not self.EditModeIntegration then return end
    if enable then
        self.EditModeIntegration:ShowOverlay()
    else
        self.EditModeIntegration:HideOverlay()
    end
    log("SetEditMode("..tostring(enable)..") redirected to overlay show/hide")
end

function ReplayFrame:BeginManualEdit()
    if not self.DisplayFrame then self:GetDisplayFrame() end
    if self.DisplayFrame then self.DisplayFrame:Show() end
    self.userHidden = false
    if self.EditModeIntegration then self.EditModeIntegration:ShowOverlay() end
    log("BeginManualEdit redirected")
end

function ReplayFrame:EndManualEdit()
    if self.EditModeIntegration then self.EditModeIntegration:HideOverlay() end
    log("EndManualEdit redirected")
end

-- No-op stubs retained for compatibility
function ReplayFrame:EnsureEditModeVisuals() end
function ReplayFrame:PrepareEditControlHighlights() end
function ReplayFrame:HighlightEditControls() end


