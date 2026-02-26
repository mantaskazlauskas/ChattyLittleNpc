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
-- Focus ring (visual keyboard focus indicator)
-- ---------------------------------------------------------------------------

function ReplayFrame:CreateFocusRing(parent)
    if self._focusRing then return self._focusRing end
    local ring = CreateFrame("Frame", nil, parent)
    ring:SetFrameStrata("HIGH")
    ring:Hide()

    -- Gold border lines (top, bottom, left, right)
    local thickness = 1.5
    local alpha = 0.85
    local color = { 1.0, 0.82, 0.0, alpha }

    local top = ring:CreateTexture(nil, "OVERLAY")
    top:SetColorTexture(unpack(color))
    top:SetHeight(thickness)
    top:SetPoint("TOPLEFT", ring, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", ring, "TOPRIGHT", 0, 0)

    local bottom = ring:CreateTexture(nil, "OVERLAY")
    bottom:SetColorTexture(unpack(color))
    bottom:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT", ring, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT", 0, 0)

    local left = ring:CreateTexture(nil, "OVERLAY")
    left:SetColorTexture(unpack(color))
    left:SetWidth(thickness)
    left:SetPoint("TOPLEFT", ring, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", ring, "BOTTOMLEFT", 0, 0)

    local right = ring:CreateTexture(nil, "OVERLAY")
    right:SetColorTexture(unpack(color))
    right:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", ring, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT", 0, 0)

    self._focusRing = ring
    return ring
end

function ReplayFrame:MoveFocusRing(row)
    if not self._focusRing then return end
    if not row or not row:IsShown() then
        self._focusRing:Hide()
        return
    end
    self._focusRing:ClearAllPoints()
    self._focusRing:SetAllPoints(row)
    self._focusRing:Show()
end

-- ---------------------------------------------------------------------------
-- Keyboard navigation
-- ---------------------------------------------------------------------------

function ReplayFrame:GetFocusedRowIndex()
    return self._focusedRowIndex
end

function ReplayFrame:SetFocusedRowIndex(index)
    local rows = self.QueueRows
    if not rows or #rows == 0 then
        self._focusedRowIndex = nil
        if self._focusRing then self._focusRing:Hide() end
        return
    end
    -- Find visible row count
    local visCount = 0
    for _, r in ipairs(rows) do
        if r:IsShown() then visCount = visCount + 1 end
    end
    if visCount == 0 then
        self._focusedRowIndex = nil
        if self._focusRing then self._focusRing:Hide() end
        return
    end
    -- Clamp
    index = math.max(1, math.min(index or 1, visCount))
    self._focusedRowIndex = index
    self:MoveFocusRing(rows[index])
    self:AnnounceRow(index)
end

function ReplayFrame:ClearFocus()
    self._focusedRowIndex = nil
    if self._focusRing then self._focusRing:Hide() end
end

function ReplayFrame:FocusNext()
    local cur = self._focusedRowIndex or 0
    self:SetFocusedRowIndex(cur + 1)
end

function ReplayFrame:FocusPrev()
    local cur = self._focusedRowIndex or 2
    self:SetFocusedRowIndex(cur - 1)
end

-- Activate (click) the currently focused row
function ReplayFrame:ActivateFocusedRow()
    local idx = self._focusedRowIndex
    if not idx then return end
    local rows = self.QueueRows
    if not rows or not rows[idx] then return end
    local row = rows[idx]
    if row._element and row:IsShown() then
        -- Simulate a left-click by calling the row's OnMouseUp handler
        local script = row:GetScript("OnMouseUp")
        if script then
            script(row, "LeftButton")
        end
    end
end

-- Install keyboard handler on the queue list frame
function ReplayFrame:SetupKeyboardNavigation()
    local list = self.QueueListFrame
    if not list or self._keyboardNavInstalled then return end

    -- Create focus ring parented to the list
    self:CreateFocusRing(list)

    -- The list frame needs to be focusable
    list:EnableKeyboard(true)
    list:SetPropagateKeyboardInput(true)

    local this = self
    list:SetScript("OnKeyDown", function(f, key)
        -- Only consume keys when we have focus (a row is focused)
        local hasFocus = this._focusedRowIndex ~= nil

        if key == "DOWN" then
            if hasFocus then
                f:SetPropagateKeyboardInput(false)
                this:FocusNext()
            else
                f:SetPropagateKeyboardInput(true)
            end
        elseif key == "UP" then
            if hasFocus then
                f:SetPropagateKeyboardInput(false)
                this:FocusPrev()
            else
                f:SetPropagateKeyboardInput(true)
            end
        elseif key == "ENTER" or key == "SPACE" then
            if hasFocus then
                f:SetPropagateKeyboardInput(false)
                this:ActivateFocusedRow()
            else
                f:SetPropagateKeyboardInput(true)
            end
        elseif key == "ESCAPE" then
            if hasFocus then
                f:SetPropagateKeyboardInput(false)
                this:ClearFocus()
            else
                f:SetPropagateKeyboardInput(true)
            end
        elseif key == "TAB" then
            -- Tab into the list: focus first row
            if not hasFocus then
                f:SetPropagateKeyboardInput(false)
                this:SetFocusedRowIndex(1)
            else
                f:SetPropagateKeyboardInput(true)
                this:ClearFocus()
            end
        elseif key == "HOME" then
            if hasFocus then
                f:SetPropagateKeyboardInput(false)
                this:SetFocusedRowIndex(1)
            else
                f:SetPropagateKeyboardInput(true)
            end
        elseif key == "END" then
            if hasFocus then
                f:SetPropagateKeyboardInput(false)
                this:SetFocusedRowIndex(999)
            else
                f:SetPropagateKeyboardInput(true)
            end
        else
            f:SetPropagateKeyboardInput(true)
        end
    end)

    self._keyboardNavInstalled = true
end

-- ---------------------------------------------------------------------------
-- Options integration helpers
-- ---------------------------------------------------------------------------

-- Generate accessibility option text for Options.lua
function ReplayFrame.GetAccessibilityDefaults()
    return {
        highContrastMode = false,
    }
end
