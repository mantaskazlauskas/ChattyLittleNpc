---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- EDIT MODE FUNCTIONALITY
-- ============================================================================

-- Bind our lightweight edit mode to Blizzard's Edit Mode (Retail)
function ReplayFrame:BindBlizzardEditMode()
    if self._editModeBound then return end
    if type(EditModeManagerFrame) == "table" and hooksecurefunc then
        hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
            if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
            -- Ensure our frame exists and force-show while in Edit Mode
            self._forceShow = true
            if not self.DisplayFrame then self:GetDisplayFrame() end
            self.userHidden = false
            if self.MinButton then self.MinButton:Hide() end
            self:UpdateParent()
            if self.DisplayFrame then self.DisplayFrame:Show() end
            self:SetEditMode(true)
            self:Relayout()
        end)
        hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
            if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
            self:SetEditMode(false)
            self:SaveFramePosition()
            -- If we forced the frame open for editing and nothing is playing, hide it afterward
            if self._forceShow and not self._manualEdit then
                self._forceShow = false
                if not self:IsVoiceoverCurrenltyPlaying() and self:IsQuestQueueEmpty() then
                    if self.DisplayFrame then self.DisplayFrame:Hide() end
                end
            end
        end)
        -- If user enters Edit Mode before we initialize, sync state
        if EditModeManagerFrame.IsInEditMode and EditModeManagerFrame:IsInEditMode() then
            if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
            self._forceShow = true
            if not self.DisplayFrame then self:GetDisplayFrame() end
            self.userHidden = false
            if self.MinButton then self.MinButton:Hide() end
            self:UpdateParent()
            if self.DisplayFrame then self.DisplayFrame:Show() end
            self:SetEditMode(true)
            self:Relayout()
        end
        self._editModeBound = true
    end
end

-- Toggle a lightweight Edit Mode to move/resize the replay frame
function ReplayFrame:SetEditMode(enabled)
    self._editMode = not not enabled
    if not self.DisplayFrame then return end

    -- Show a subtle border/overlay when edit mode is active
    if self._editMode then
        if not self._editOverlay then
            local ol = self.DisplayFrame:CreateTexture(nil, "OVERLAY")
            ol:SetAllPoints()
            ol:SetColorTexture(1, 1, 1, 0.08)
            self._editOverlay = ol
        end
        self._editOverlay:Show()
        -- Enable resizing and dragging
        self.DisplayFrame:SetResizable(true)
        self.DisplayFrame:RegisterForDrag("LeftButton")
        if self.ResizeGrip then self.ResizeGrip:Show() end
        if self.PrepareEditControlHighlights then self:PrepareEditControlHighlights() end
    else
        if self._editOverlay then self._editOverlay:Hide() end
        -- Keep drag enabled but rely on user preference; grip hidden by default
        if self.ResizeGrip then self.ResizeGrip:Hide() end
        if self._hoverOverlay then self._hoverOverlay:Hide() end
        if self.HighlightEditControls then self:HighlightEditControls(false) end
    end
end

-- Force-show the replay frame for editing even when nothing is playing
function ReplayFrame:ShowForEdit()
    self._forceShow = true
    self:GetDisplayFrame()
    self.userHidden = false
    if self.MinButton then self.MinButton:Hide() end
    self:UpdateParent()
    if self.DisplayFrame then self.DisplayFrame:Show() end
    self:SetEditMode(true)
    self:Relayout()
    -- Do not programmatically enter Blizzard Edit Mode to avoid protected calls/taint, especially in combat.
    -- Users can open Blizzard Edit Mode themselves; our frame will sync via BindBlizzardEditMode hooks.
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        if CLN and CLN.Print then
            CLN:Print("Frame shown for editing. Open Blizzard Edit Mode after combat to adjust with anchors.")
        end
    end
end

-- Re-apply size-based layout without user resize
function ReplayFrame:Relayout()
    if not self.DisplayFrame then return end
    local f = self.DisplayFrame
    local w, h = f:GetSize()
    local cb = f:GetScript("OnSizeChanged")
    if cb then cb(f, w, h) end
end

-- Prepare glow overlays for edit-related controls (once)
function ReplayFrame:PrepareEditControlHighlights()
    local function ensureGlow(holder, attachTo)
        if holder or not attachTo then return holder end
        local g = attachTo:CreateTexture(nil, "OVERLAY")
        g:SetTexture("Interface/Buttons/UI-ActionButton-Border")
        g:SetBlendMode("ADD")
        g:SetAllPoints(attachTo)
        g:SetAlpha(0.0)
        return g
    end
    self._glowEdit = ensureGlow(self._glowEdit, self.EditModeButton)
    self._glowOptions = ensureGlow(self._glowOptions, self.OptionsButton)
    self._glowClear = ensureGlow(self._glowClear, self.ClearButton)
    self._glowCollapse = ensureGlow(self._glowCollapse, self.CollapseButton)
    if self.ResizeGrip and not self._glowGrip then
        local g = self.ResizeGrip:CreateTexture(nil, "OVERLAY")
        g:SetTexture("Interface/Buttons/UI-ActionButton-Border")
        g:SetBlendMode("ADD")
        g:SetPoint("CENTER")
        g:SetSize(24, 24)
        g:SetAlpha(0.0)
        self._glowGrip = g
    end
end

-- Highlight edit controls with glow effect
function ReplayFrame:HighlightEditControls(show)
    local a = show and 0.9 or 0.0
    if self._glowEdit then self._glowEdit:SetAlpha(a) end
    if self._glowOptions then self._glowOptions:SetAlpha(a) end
    if self._glowClear then self._glowClear:SetAlpha(a) end
    if self._glowCollapse then self._glowCollapse:SetAlpha(a) end
    if self._glowGrip then self._glowGrip:SetAlpha(a) end
end

-- Manual edit flow keeps window visible until user explicitly ends editing
function ReplayFrame:BeginManualEdit()
    self._manualEdit = true
    self._forceShow = true
    self.userHidden = false
    self:GetDisplayFrame()
    if self.MinButton then self.MinButton:Hide() end
    self:UpdateParent()
    if self.DisplayFrame then self.DisplayFrame:Show() end
    self:SetEditMode(true)
    self:Relayout()
end

-- End manual edit mode
function ReplayFrame:EndManualEdit()
    self._manualEdit = false
    self:SetEditMode(false)
    self:SaveFramePosition()
    -- Only clear forced show if Blizzard Edit Mode isn't still active
    if not (EditModeManagerFrame and EditModeManagerFrame.IsInEditMode and EditModeManagerFrame:IsInEditMode()) then
        self._forceShow = false
        if not self:IsVoiceoverCurrenltyPlaying() and self:IsQuestQueueEmpty() then
            if self.DisplayFrame then self.DisplayFrame:Hide() end
        end
    end
end

-- Build context menu entries for right-click menu (DISABLED)
--[[
local function CLN_BuildContextMenuEntries(self)
    local entries = {}
    if self:IsVoiceoverCurrenltyPlaying() then
        table.insert(entries, { text = "Stop current", func = function()
            CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
            self.userHidden = false
            self:UpdateDisplayFrameState()
        end })
    end
    if CLN.questsQueue and #CLN.questsQueue > 0 then
        table.insert(entries, { text = "Clear queue", func = function()
            CLN.questsQueue = {}
            self:UpdateDisplayFrameState()
        end })
    end
    table.insert(entries, { text = (CLN.db.profile.compactMode and "Disable" or "Enable") .. " compact mode", func = function()
        CLN.db.profile.compactMode = not CLN.db.profile.compactMode
        if self.ApplyCompactMode then self:ApplyCompactMode() end
    end })
    table.insert(entries, { text = "Options", func = function()
        local Ace = LibStub and LibStub("AceAddon-3.0", true)
        local Opts = Ace and Ace:GetAddon("Options", true) or nil
        if Opts and Opts.OpenSettings then
            Opts:OpenSettings(); return
        end
        local dlg = LibStub and LibStub("AceConfigDialog-3.0", true)
        if dlg and dlg.Open then dlg:Open("ChattyLittleNpc") end
    end })
    return entries
end

-- Open context menu on right-click (DISABLED)
function ReplayFrame:OpenContextMenu(owner)
    -- Right-click context menu functionality has been removed for cleaner interface
    -- Users can access options via the options button and clear queue via the clear button
end
--]]
