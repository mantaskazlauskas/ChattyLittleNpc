---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- ACCESSIBILITY MODULE
-- Keyboard navigation, high-contrast/colorblind support, focus indicators,
-- and screen reader announcements for the Replay UI.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- High-contrast / colorblind helpers
-- ---------------------------------------------------------------------------

-- Check whether WoW's colorblind mode is active
function ReplayFrame:IsHighContrastMode()
    if GetCVarBool and GetCVarBool("colorblindMode") then return true end
    -- Also respect addon-level override
    local db = CLN and CLN.db and CLN.db.profile
    return db and db.highContrastMode
end

-- Type badge text prefixes for colorblind users (shown before label when icons are off or unavailable)
local TYPE_BADGES = {
    quest      = "[Q] ",
    Gossip     = "[G] ",
    GameObject = "[I] ",
}

-- Get a text badge prefix for an entry type (empty string if not in high-contrast mode)
function ReplayFrame:GetAccessibilityBadge(entryType)
    if not self:IsHighContrastMode() then return "" end
    return TYPE_BADGES[entryType] or ""
end

-- High-contrast color overrides: brighter, more saturated for colorblind users
local HC_COLORS = {
    playing   = { 0.1, 1.0, 0.1 },     -- brighter green
    quest     = { 1.0, 0.90, 0.10 },    -- brighter gold
    gossip    = { 0.5, 0.85, 1.0 },     -- brighter blue
    gameobj   = { 1.0, 0.85, 0.55 },    -- brighter tan
    history   = { 0.65, 0.65, 0.65 },   -- brighter gray
    default   = { 1.0, 0.90, 0.15 },    -- brighter default gold
}

function ReplayFrame:GetRowColor(element, showBadges)
    local hc = self:IsHighContrastMode()
    if element.isPlaying then
        return unpack(hc and HC_COLORS.playing or { 0.2, 1.0, 0.2 })
    elseif element.isHistory then
        return unpack(hc and HC_COLORS.history or { 0.5, 0.5, 0.5 })
    elseif showBadges and element.entryType == "quest" then
        return unpack(hc and HC_COLORS.quest or { 1.0, 0.82, 0.0 })
    elseif showBadges and element.entryType == "Gossip" then
        return unpack(hc and HC_COLORS.gossip or { 0.6, 0.8, 1.0 })
    elseif showBadges and element.entryType == "GameObject" then
        return unpack(hc and HC_COLORS.gameobj or { 0.85, 0.75, 0.55 })
    else
        return unpack(hc and HC_COLORS.default or { 0.95, 0.86, 0.20 })
    end
end

-- ---------------------------------------------------------------------------
-- Announcements (accessibility narration)
-- ---------------------------------------------------------------------------

-- Announce an accessibility message via UIErrorsFrame (brief on-screen text).
-- This is the most reliable way to surface info to players using screen readers
-- or who aren't looking at the addon frame.
function ReplayFrame:Announce(msg)
    if not msg or msg == "" then return end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1.0, 0.82, 0.0, 1.0, 3.0)
    end
end

-- Announce the currently focused row (for keyboard navigation)
function ReplayFrame:AnnounceRow(index)
    if not self.QueueRows or not self.QueueRows[index] then return end
    local row = self.QueueRows[index]
    local element = row._element
    if not element then return end
    local prefix = ""
    if element.isPlaying then
        prefix = "Now playing: "
    elseif element.isDivider then
        prefix = ""
    elseif element.isHistory then
        prefix = "History: "
    end
    local label = element.label or (row.text and row.text:GetText()) or "Unknown"
    self:Announce(prefix .. label)
end

-- ---------------------------------------------------------------------------
-- Focus ring (removed — was stealing Tab/keyboard focus during gameplay)
-- ---------------------------------------------------------------------------

function ReplayFrame:CreateFocusRing() end
function ReplayFrame:MoveFocusRing() end

-- ---------------------------------------------------------------------------
-- Keyboard navigation (removed — was stealing Tab/keyboard focus during gameplay)
-- ---------------------------------------------------------------------------

function ReplayFrame:GetFocusedRowIndex() return nil end
function ReplayFrame:SetFocusedRowIndex() end
function ReplayFrame:ClearFocus() end
function ReplayFrame:FocusNext() end
function ReplayFrame:FocusPrev() end
function ReplayFrame:ActivateFocusedRow() end
function ReplayFrame:SetupKeyboardNavigation() end

-- ---------------------------------------------------------------------------
-- Options integration helpers
-- ---------------------------------------------------------------------------

-- Generate accessibility option text for Options.lua
function ReplayFrame.GetAccessibilityDefaults()
    return {
        highContrastMode = false,
    }
end
