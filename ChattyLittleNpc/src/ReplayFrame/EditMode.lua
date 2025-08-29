---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- EDIT MODE FUNCTIONALITY
-- ============================================================================

-- Central guards/wrappers for Blizzard Edit Mode availability
function ReplayFrame:_DetectEditModeApis()
    if self._editModeDetected then return end
    local fr = type(EditModeManagerFrame) == "table" and EditModeManagerFrame or nil
    local hasEnter = fr and type(fr.EnterEditMode) == "function" or false
    local hasExit = fr and type(fr.ExitEditMode) == "function" or false
    local hasIsIn = fr and type(fr.IsInEditMode) == "function" or false
    self._editModeApi = { frame = fr, hasEnter = hasEnter, hasExit = hasExit, hasIsIn = hasIsIn }
    self._editModeDetected = true
end

function ReplayFrame:HasBlizzardEditMode()
    self:_DetectEditModeApis()
    local a = self._editModeApi
    return a and a.frame and a.hasEnter and a.hasExit or false
end

function ReplayFrame:IsBlizzardInEditMode()
    self:_DetectEditModeApis()
    local a = self._editModeApi
    if a and a.frame and a.hasIsIn then
        return a.frame:IsInEditMode()
    end
    return false
end

function ReplayFrame:SafeHook(obj, methodName, handler)
    if not (hooksecurefunc and type(obj) == "table" and type(obj[methodName]) == "function" and type(handler) == "function") then
        return false
    end
    hooksecurefunc(obj, methodName, handler)
    return true
end

-- Bind our lightweight edit mode to Blizzard's Edit Mode (Retail)
function ReplayFrame:BindBlizzardEditMode()
    if self._editModeBound then return end
    if type(EditModeManagerFrame) == "table" and hooksecurefunc then
        if not self:HasBlizzardEditMode() then
            if self.Debug then self:Debug("Blizzard Edit Mode not available; skipping binding.") end
            return
        end

        self:SafeHook(EditModeManagerFrame, "EnterEditMode", function()
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
        self:SafeHook(EditModeManagerFrame, "ExitEditMode", function()
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
        if self:IsBlizzardInEditMode() then
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
    if type(EditModeManagerFrame) ~= "table" or not hooksecurefunc then
        if self.Debug then self:Debug("EditModeManagerFrame or hooksecurefunc missing; skipping binding.") end
    end
end

-- Toggle a lightweight Edit Mode to move/resize the replay frame
function ReplayFrame:SetEditMode(enabled)
    self._editMode = not not enabled
    if not self.DisplayFrame then return end

    -- Show a subtle border/overlay when edit mode is active
    if self._editMode then
        -- Visuals: light Blizzard-blue field with hover intensification and border
        self:EnsureEditModeVisuals()
        if self._editOverlay then self._editOverlay:Show() end
        if self._hoverOverlay then self._hoverOverlay:Hide() end
        if self._editBorder then for _, t in ipairs(self._editBorder) do t:Show() end end

    -- Enable resizing always in Edit Mode; dragging only if unlocked
    local locked = self.IsFrameLocked and self:IsFrameLocked()
    self.DisplayFrame:SetResizable(true)
    if not locked then self.DisplayFrame:RegisterForDrag("LeftButton") end
        if self.ResizeGrip then self.ResizeGrip:Show() end
        if self.PrepareEditControlHighlights then self:PrepareEditControlHighlights() end

    -- Make window draggable from anywhere in edit mode (if not locked)
        local f = self.DisplayFrame
        -- Drag handlers
        if not locked then
            f:SetScript("OnDragStart", function(frame)
                if self._isResizing then return end
                self._isDragging = true
                frame:StartMoving()
            end)
            f:SetScript("OnDragStop", function(frame)
                frame:StopMovingOrSizing()
                self._isDragging = false
                if self.SaveFramePosition then self:SaveFramePosition() end
            end)
        f:SetScript("OnMouseDown", function(frame, button)
                if button == "LeftButton" then
            if self._isResizing then return end
                    self._isDragging = true
                    frame:StartMoving()
                end
            end)
            f:SetScript("OnMouseUp", function(frame)
                if self._isDragging then
                    frame:StopMovingOrSizing()
                    self._isDragging = false
                    if self.SaveFramePosition then self:SaveFramePosition() end
                end
            end)
        end

        -- Hover feedback on the entire frame; show lock button and guidance tooltip in edit mode
        f:SetScript("OnEnter", function()
            if self._hoverOverlay then self._hoverOverlay:Show() end
            if self.HighlightEditControls then self:HighlightEditControls(true) end
            if self.LockButton then self.LockButton:Show() end
            -- Frame-level guidance tooltip
            if GameTooltip and GameTooltip.SetOwner then
                GameTooltip:SetOwner(f, "ANCHOR_TOPLEFT")
                GameTooltip:ClearLines()
                local title = "Chatty Little Npc — Conversations"
                GameTooltip:AddLine(title, 1, 1, 1, true)
                local locked = self.IsFrameLocked and self:IsFrameLocked()
                if locked then
                    GameTooltip:AddLine("Locked: click the lock to allow moving.", 0.85, 0.85, 0.85, true)
                else
                    GameTooltip:AddLine("Drag anywhere to move the window.", 0.85, 0.85, 0.85, true)
                end
                GameTooltip:AddLine("Resize from the bottom-right grip (Edit Mode only).", 0.80, 0.80, 0.80, true)
                GameTooltip:AddLine("Exit Edit Mode to finish.", 0.80, 0.80, 0.80, true)
                GameTooltip:Show()
            end
        end)
        f:SetScript("OnLeave", function()
            if self._hoverOverlay then self._hoverOverlay:Hide() end
            if self.HighlightEditControls then self:HighlightEditControls(false) end
            if self.LockButton then self.LockButton:Hide() end
            if GameTooltip_Hide then GameTooltip_Hide() end
        end)

        -- Loosen child capture so parent can drag: disable queue rows mouse only if unlocked
        if not locked and self.QueueRows then
            for _, row in ipairs(self.QueueRows) do
                if row and row.EnableMouse and row:IsShown() then
                    -- preserve state
                    if row.IsMouseEnabled and row:IsMouseEnabled() then row._prevMouseEnabled = true end
                    row:EnableMouse(false)
                end
            end
        end

        -- Resize grip: use contrasted highlight art in edit mode
    if self.ResizeGrip and self.ResizeGrip.texture then
            -- Save existing handlers to restore later
            if not self._gripPrevEnter then self._gripPrevEnter = self.ResizeGrip:GetScript("OnEnter") end
            if not self._gripPrevLeave then self._gripPrevLeave = self.ResizeGrip:GetScript("OnLeave") end
            self.ResizeGrip.texture:SetTexture("Interface/CHATFRAME/UI-ChatIM-SizeGrabber-Highlight")
            -- Force-highlight regardless of hover in edit mode
            self.ResizeGrip:SetScript("OnEnter", nil)
            self.ResizeGrip:SetScript("OnLeave", nil)
        end
        if self._glowGrip then self._glowGrip:SetAlpha(0.9) end
    else
        if self._editOverlay then self._editOverlay:Hide() end
        -- Keep drag enabled but rely on user preference; grip hidden by default
    if self.ResizeGrip then self.ResizeGrip:Hide() end
        if self._hoverOverlay then self._hoverOverlay:Hide() end
        if self._editBorder then for _, t in ipairs(self._editBorder) do t:Hide() end end
        if self.HighlightEditControls then self:HighlightEditControls(false) end

        -- Restore child mouse capture
        if self.QueueRows then
            for _, row in ipairs(self.QueueRows) do
                if row and row.EnableMouse and row._prevMouseEnabled then
                    row:EnableMouse(true)
                    row._prevMouseEnabled = nil
                end
            end
        end

        -- Reset resize grip art and handlers
        if self.ResizeGrip and self.ResizeGrip.texture then
            self.ResizeGrip.texture:SetTexture("Interface/CHATFRAME/UI-ChatIM-SizeGrabber-Up")
            if self._gripPrevEnter ~= nil then self.ResizeGrip:SetScript("OnEnter", self._gripPrevEnter) end
            if self._gripPrevLeave ~= nil then self.ResizeGrip:SetScript("OnLeave", self._gripPrevLeave) end
            self._gripPrevEnter = nil
            self._gripPrevLeave = nil
        end

        -- Clear frame scripts set for edit mode
        local f = self.DisplayFrame
        if f then
            f:SetScript("OnDragStart", nil)
            f:SetScript("OnDragStop", nil)
            f:SetScript("OnMouseDown", nil)
            f:SetScript("OnMouseUp", nil)
            f:SetScript("OnEnter", nil)
            f:SetScript("OnLeave", nil)
        end

        -- Ensure resizing is disabled outside edit mode
        if self.DisplayFrame and self.DisplayFrame.SetResizable then
            self.DisplayFrame:SetResizable(false)
        end
        -- Hide lock button outside edit mode
        if self.LockButton then self.LockButton:Hide() end
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

-- Build edit mode visuals: blue overlay, hover overlay, and border
function ReplayFrame:EnsureEditModeVisuals()
    if not self.DisplayFrame then return end
    local f = self.DisplayFrame

    -- Base light blue fill (behind content) — normal: #7299AA over raw #4F5154
    if not self._editOverlay then
        local ol = f:CreateTexture(nil, "BACKGROUND")
        ol:SetAllPoints()
        -- #7299AA ~= (0.447, 0.600, 0.667)
        ol:SetColorTexture(0.447, 0.600, 0.667, 0.20)
        self._editOverlay = ol
    else
        self._editOverlay:SetColorTexture(0.447, 0.600, 0.667, 0.20)
        self._editOverlay:ClearAllPoints()
        self._editOverlay:SetAllPoints()
        self._editOverlay:SetDrawLayer("BACKGROUND")
    end

    -- Stronger hover layer (behind content, on top of base) — hover: #A9DBED
    if not self._hoverOverlay then
        local hov = f:CreateTexture(nil, "BACKGROUND")
        hov:SetAllPoints()
        -- #A9DBED ~= (0.663, 0.859, 0.929)
        hov:SetColorTexture(0.663, 0.859, 0.929, 0.30)
        hov:Hide()
        self._hoverOverlay = hov
    else
        self._hoverOverlay:SetColorTexture(0.663, 0.859, 0.929, 0.30)
        self._hoverOverlay:ClearAllPoints()
        self._hoverOverlay:SetAllPoints()
        self._hoverOverlay:SetDrawLayer("BACKGROUND")
    end

    -- Simple 1px border in hover blue for contrast
    if not self._editBorder then
        self._editBorder = {}
        local edges = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
        for _, edge in ipairs(edges) do
            local t = f:CreateTexture(nil, "BORDER")
            t:SetColorTexture(0.663, 0.859, 0.929, 0.85)
            if edge == "TOP" then
                t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
                t:SetHeight(1)
            elseif edge == "BOTTOM" then
                t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
                t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
                t:SetHeight(1)
            elseif edge == "LEFT" then
                t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
                t:SetWidth(1)
            elseif edge == "RIGHT" then
                t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
                t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
                t:SetWidth(1)
            end
            table.insert(self._editBorder, t)
        end
    else
        for _, t in ipairs(self._editBorder) do
            t:SetColorTexture(0.663, 0.859, 0.929, 0.85)
            t:Show()
        end
    end
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
    if not self:IsBlizzardInEditMode() then
        self._forceShow = false
        if not self:IsVoiceoverCurrenltyPlaying() and self:IsQuestQueueEmpty() then
            if self.DisplayFrame then self.DisplayFrame:Hide() end
        end
    end
end

