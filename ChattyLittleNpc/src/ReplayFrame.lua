-- (moved) ShouldShowNpcModel is defined after ReplayFrame is created
---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = {}
CLN.ReplayFrame = ReplayFrame

-- Defer binding to after addon init to ensure globals exist
local function CLN_InitEditModeBinding()
    if ReplayFrame and ReplayFrame.BindBlizzardEditMode then
        ReplayFrame:BindBlizzardEditMode()
    end
end
if CreateFrame then
    local binder = CreateFrame("Frame")
    binder:RegisterEvent("PLAYER_LOGIN")
    binder:SetScript("OnEvent", function()
        CLN_InitEditModeBinding()
    end)
end

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

-- Decide if there's enough horizontal room to show the NPC talking head
function ReplayFrame:ShouldShowNpcModel()
    if self:IsCompactModeEnabled() then return false end
    if not self.DisplayFrame then return false end
    local w = self.DisplayFrame:GetWidth() or 0
    -- model + gap + some content minimum (heuristic)
    local minContent = 160
    local need = (self.npcModelFrameWidth or 140) + (self.gap or 10) + minContent
    return w >= need
end

-- Track if the user explicitly hid the window while audio is playing
ReplayFrame.userHidden = false

function ReplayFrame:SaveFramePosition()
    local point, relativeTo, relativePoint, xOfs, yOfs = self.DisplayFrame:GetPoint()
    CLN.db.profile.framePos = {
        point = point,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs
    }
    -- Persist current size as well
    if self.DisplayFrame and self.DisplayFrame.GetSize then
        local w, h = self.DisplayFrame:GetSize()
        CLN.db.profile.frameSize = { width = math.floor(w + 0.5), height = math.floor(h + 0.5) }
    end
end

function ReplayFrame:LoadFramePosition()
    local pos = CLN.db.profile.framePos
    -- Apply saved size first (if any)
    local size = CLN.db.profile.frameSize
    if size and size.width and size.height and self.DisplayFrame and self.DisplayFrame.SetSize then
        self.DisplayFrame:SetSize(size.width, size.height)
    end
    if (pos) then
        self.DisplayFrame:ClearAllPoints()
        self.DisplayFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        self.DisplayFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -500, -200)
    end
end

function ReplayFrame:ResetFramePosition()
    CLN.db.profile.framePos = {
        point = "CENTER",
        relativePoint = "CENTER",
        xOfs = 500,
        yOfs = 0
    }
    -- Reset saved size and per-mode widths to defaults
    CLN.db.profile.frameSize = { width = 310 + 165, height = 165 }
    CLN.db.profile.compactWidth = nil
    CLN.db.profile.expandedWidth = nil
    if (ReplayFrame.DisplayFrame) then
        ReplayFrame:LoadFramePosition()
    end
end

    -- Reparent while preserving the on-screen position regardless of scale/parent
    function ReplayFrame:ReparentPreservingScreenPosition(newParent)
        if not self.DisplayFrame then return end
        local f = self.DisplayFrame
        local cx, cy = f:GetCenter()
        if not cx or not cy then
            f:SetParent(newParent)
            return
        end
        local s = f:GetEffectiveScale() or 1
        local absX, absY = cx * s, cy * s
        f:SetParent(newParent)
        local s2 = f:GetEffectiveScale() or 1
        local relX, relY = absX / s2, absY / s2
        f:ClearAllPoints()
    -- Initialize the model container and model frame via extracted module (idempotent)
    if self.CreateModelUI and not (self.ModelContainer or self.NpcModelFrame) then
            self:CreateModelUI()
    elseif not (self.ModelContainer or self.NpcModelFrame) then
            -- Fallback defaults if module hasn't loaded yet
            local modelContainer = CreateFrame("Frame", "ChattyLittleNpcModelContainer", self.DisplayFrame)
            modelContainer:SetPoint("TOPLEFT", self.DisplayFrame, "TOPLEFT", 5, -8)
            modelContainer:SetPoint("TOPRIGHT", self.DisplayFrame, "TOPRIGHT", -5, -8)
            modelContainer:SetHeight(self.npcModelFrameHeight)
            modelContainer:Hide()
            self.ModelContainer = modelContainer

            local modelFrame = CreateFrame("PlayerModel", "ChattyLittleNpcModelFrame", modelContainer)
            modelFrame:SetSize(self.npcModelFrameWidth, self.npcModelFrameHeight)
            modelFrame:SetPoint("TOPLEFT", modelContainer, "TOPLEFT", 0, 0)
            modelFrame:Hide() -- shown dynamically when a valid model is available
            self.NpcModelFrame = modelFrame
        end

        -- Re-anchor to keep the same screen position after reparenting
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", relX, relY)
    end

-- Minimized button persistence
function ReplayFrame:SaveMinButtonPosition()
    if not self.MinButton then return end
    local point, relativeTo, relativePoint, xOfs, yOfs = self.MinButton:GetPoint()
    CLN.db.profile.minBtnPos = {
        point = point,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs,
    }
end

function ReplayFrame:LoadMinButtonPosition()
    if not self.MinButton then return end
    local pos = CLN.db.profile.minBtnPos
    self.MinButton:ClearAllPoints()
    if pos then
        self.MinButton:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        self.MinButton:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -420, -200)
    end
end

-- Per-Edit-Mode-layout position persistence (Retail)

function ReplayFrame:EnsureMinimizedButton()
    if self.MinButton then return end
    local btn = CreateFrame("Button", "ChattyLittleNpcMinButton", UIParent)
    btn:SetSize(36, 36)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetClampedToScreen(true)
    btn:SetScript("OnDragStart", btn.StartMoving)
    btn:SetScript("OnDragStop", function(b)
        b:StopMovingOrSizing()
        ReplayFrame:SaveMinButtonPosition()
    end)
    -- circular masked icon
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface/Icons/Ability_Warrior_BattleShout")
    local mask = btn:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    btn.tex = tex
    -- border ring
    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints()
    ring:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    btn.ring = ring
    btn:SetScript("OnClick", function()
        ReplayFrame.userHidden = false
        if ReplayFrame.DisplayFrame then
            ReplayFrame.DisplayFrame:Show()
        end
        btn:Hide()
        ReplayFrame:UpdateDisplayFrame()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Conversation Queue (click to open)")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    self.MinButton = btn
    self:LoadMinButtonPosition()
    btn:Hide()
end

function ReplayFrame:GetDisplayFrame()
    if (self.DisplayFrame) then
        self:LoadFramePosition()
        return
    end

    self.normalWidth = 310
    self.npcModelFrameWidth = 140
    self.gap = 10
    self.expandedWidth = self.normalWidth + self.npcModelFrameWidth + self.gap

    -- Check if DialogueUI addon is loaded
    local parentFrame = UIParent

    if (self:IsDialogueUIFrameShow()) then
        parentFrame = _G["DUIQuestFrame"]
    end

    -- Parent frame (texture-based background; no NineSlice/Backdrop)
    self.DisplayFrame = CreateFrame("Frame", "ChattyLittleNpcDisplayFrame", parentFrame)
    local this = self -- capture for closures below
    -- Use native resize bounds instead of manual clamping
    if ReplayFrame.DisplayFrame.SetResizeBounds then
        -- minWidth, minHeight; let max be unconstrained
        ReplayFrame.DisplayFrame:SetResizeBounds(260, 120)
    end
    -- Initial parent frame size: prefer saved size; else infer from mode
    local initialHeight = 165
    local initialWidth
    local savedSize = CLN.db and CLN.db.profile and CLN.db.profile.frameSize or nil
    if savedSize and savedSize.width and savedSize.height then
        initialWidth, initialHeight = savedSize.width, savedSize.height
    else
        if CLN.db and CLN.db.profile and CLN.db.profile.compactMode then
            initialWidth = ReplayFrame.normalWidth
        else
            initialWidth = initialHeight + ReplayFrame.normalWidth
        end
    end
    self.DisplayFrame:SetSize(initialWidth, initialHeight)
    self:LoadFramePosition()
    -- Edit Mode support removed
    -- Objectives-style background: mostly transparent, no parchment/backdrop
    do
        local bg = self.DisplayFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        -- Keep a transparent background to match Objectives tracker look
        bg:SetColorTexture(0, 0, 0, 0)
        bg:SetAlpha(0)
        self.DisplayFrame.Bg = bg

        -- Previously: thin border lines. For Objectives style, skip visible border.
        local function makeBorder()
            local border = {}
            local r, g, b, a = 0.6, 0.6, 0.6, 0.9
            border.top = self.DisplayFrame:CreateTexture(nil, "BORDER")
            border.top:SetColorTexture(r, g, b, a)
            border.top:SetPoint("TOPLEFT")
            border.top:SetPoint("TOPRIGHT")
            border.top:SetHeight(1)

            border.bottom = self.DisplayFrame:CreateTexture(nil, "BORDER")
            border.bottom:SetColorTexture(r, g, b, a)
            border.bottom:SetPoint("BOTTOMLEFT")
            border.bottom:SetPoint("BOTTOMRIGHT")
            border.bottom:SetHeight(1)

            border.left = self.DisplayFrame:CreateTexture(nil, "BORDER")
            border.left:SetColorTexture(r, g, b, a)
            border.left:SetPoint("TOPLEFT")
            border.left:SetPoint("BOTTOMLEFT")
            border.left:SetWidth(1)

            border.right = self.DisplayFrame:CreateTexture(nil, "BORDER")
            border.right:SetColorTexture(r, g, b, a)
            border.right:SetPoint("TOPRIGHT")
            border.right:SetPoint("BOTTOMRIGHT")
            border.right:SetWidth(1)
            return border
        end
    -- Do not create a border to keep things clean/transparent
    end
    -- DisplayFrame scripts (drag/resize/mouse)
    self.DisplayFrame:SetMovable(true)
    self.DisplayFrame:EnableMouse(true)
    self.DisplayFrame:SetResizable(true)
    self.DisplayFrame:SetClampedToScreen(true)
    self.DisplayFrame:RegisterForDrag("LeftButton")
    self.DisplayFrame:SetScript("OnDragStart", function(frame)
        this._isDragging = true
        frame:StartMoving()
    end)
    self.DisplayFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        this._isDragging = false
        this:SaveFramePosition()
    end)
    -- Allow closing with ESC (Edit Mode support removed; keep default drag)
    if UISpecialFrames then
        self.DisplayFrame:RegisterForDrag("LeftButton")
    end

    -- Full-width container row for the model, with a fixed-size model anchored left inside
    self.npcModelFrameWidth = 220
    self.npcModelFrameHeight = 140

    -- Initialize the model container and model frame via extracted module (idempotent)
    if self.CreateModelUI and not (self.ModelContainer or self.NpcModelFrame) then
            self:CreateModelUI()
    elseif not (self.ModelContainer or self.NpcModelFrame) then
            -- Fallback defaults if module hasn't loaded yet
            local modelContainer = CreateFrame("Frame", "ChattyLittleNpcModelContainer", self.DisplayFrame)
            modelContainer:SetPoint("TOPLEFT", self.DisplayFrame, "TOPLEFT", 5, -8)
            modelContainer:SetPoint("TOPRIGHT", self.DisplayFrame, "TOPRIGHT", -5, -8)
            modelContainer:SetHeight(self.npcModelFrameHeight)
            modelContainer:Hide()
            self.ModelContainer = modelContainer

            local modelFrame = CreateFrame("PlayerModel", "ChattyLittleNpcModelFrame", modelContainer)
            modelFrame:SetSize(self.npcModelFrameWidth, self.npcModelFrameHeight)
            modelFrame:SetPoint("TOPLEFT", modelContainer, "TOPLEFT", 0, 0)
            modelFrame:Hide() -- shown dynamically when a valid model is available
            self.NpcModelFrame = modelFrame
        end

    -- Child frame: Content (quest queue and voiceover text)
    local contentFrame = CreateFrame("Frame", "ChattyLittleNpcContentFrame", self.DisplayFrame)
    contentFrame:SetPoint("TOPLEFT", self.DisplayFrame, "TOPLEFT", 5, -5)
    contentFrame:SetPoint("TOPRIGHT", self.DisplayFrame, "TOPRIGHT", -5, -5)
    contentFrame:SetPoint("BOTTOMLEFT", self.DisplayFrame, "BOTTOMLEFT", 5, 5)
    self.ContentFrame = contentFrame

    -- Header title (styled like Objectives tracker)
    local header = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    header:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -6)
    header:SetText("Conversation Queue")
    header:SetTextColor(1.0, 0.82, 0.0) -- gold
    if header.SetTextToFit then header:SetTextToFit() end
    self.HeaderText = header

    -- Divider below header
    local divider = contentFrame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1.0, 0.82, 0.0, 0.35) -- slightly stronger like Objectives
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -4)
    divider:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -10, -4)
    divider:SetHeight(1)
    self.HeaderDivider = divider

    -- Chevron expand/collapse toggle like Objectives tracker
    local collapseBtn = CreateFrame("Button", nil, contentFrame)
    collapseBtn:SetSize(18, 18)
    collapseBtn:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -6, -6)
    collapseBtn.tex = collapseBtn:CreateTexture(nil, "ARTWORK")
    collapseBtn.tex:SetAllPoints()
    local function SetChevron(expanded)
        if expanded then
            collapseBtn.tex:SetTexture("Interface/Buttons/UI-Panel-ExpandButton-Up") -- down chevron (expanded)
        else
            collapseBtn.tex:SetTexture("Interface/Buttons/UI-Panel-CollapseButton-Up") -- right chevron (collapsed)
        end
    end
    collapseBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self._collapsed and "Expand" or "Collapse")
        GameTooltip:Show()
    end)
    collapseBtn:SetScript("OnLeave", function() GameTooltip_Hide() end)
    collapseBtn._collapsed = false
    SetChevron(true)
    collapseBtn:SetScript("OnClick", function(self)
        self._collapsed = not self._collapsed
        if self._collapsed then
            -- Collapse content area (hide scroll list but keep header visible)
            if this.QueueScrollBox then this.QueueScrollBox:Hide() end
            if this.QueueScrollBar then this.QueueScrollBar:Hide() end
            if this.HeaderDivider then this.HeaderDivider:Hide() end
            if this.ContentFrame then this.ContentFrame:SetHeight(32) end
            SetChevron(false)
        else
            if this.QueueScrollBox then this.QueueScrollBox:Show() end
            if this.QueueScrollBar then this.QueueScrollBar:Show() end
            if this.HeaderDivider then this.HeaderDivider:Show() end
            SetChevron(true)
        end
    -- Refresh header text to reflect collapsed/expanded state
    if this.UpdateDisplayFrame then this:UpdateDisplayFrame() end
    end)
    self.CollapseButton = collapseBtn

    -- Options and Clear buttons in header
    local clearBtn = CreateFrame("Button", nil, contentFrame)
    clearBtn:SetSize(18, 18)
    clearBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -6, 0)
    local clearTex = clearBtn:CreateTexture(nil, "ARTWORK")
    clearTex:SetAllPoints()
    clearTex:SetTexture("Interface/Buttons/UI-GroupLoot-Pass-Up")
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Clear all queued voiceovers")
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip_Hide() end)
    clearBtn:SetScript("OnClick", function()
        CLN.questsQueue = {}
        ReplayFrame:UpdateDisplayFrame()
    end)
    self.ClearButton = clearBtn

    local optionsBtn = CreateFrame("Button", nil, contentFrame)
    optionsBtn:SetSize(18, 18)
    optionsBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    local optionsTex = optionsBtn:CreateTexture(nil, "ARTWORK")
    optionsTex:SetAllPoints()
    optionsTex:SetTexture("Interface/Buttons/UI-OptionsButton")
    optionsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Open Chatty Little Npc options")
        GameTooltip:Show()
    end)
    optionsBtn:SetScript("OnLeave", function() GameTooltip_Hide() end)
    optionsBtn:SetScript("OnClick", function()
        local Ace = LibStub and LibStub("AceAddon-3.0", true)
        local Opts = Ace and Ace:GetAddon("Options", true) or nil
        if Opts and Opts.OpenSettings then
            Opts:OpenSettings()
            return
        end
        local dlg = LibStub and LibStub("AceConfigDialog-3.0", true)
        if dlg and dlg.Open then dlg:Open("ChattyLittleNpc") end
    end)
    self.OptionsButton = optionsBtn

    -- Edit Mode toggle button: enables moving/resizing with a visual hint
    local editBtn = CreateFrame("Button", nil, contentFrame)
    editBtn:SetSize(18, 18)
    editBtn:SetPoint("RIGHT", optionsBtn, "LEFT", -6, 0)
    local editTex = editBtn:CreateTexture(nil, "ARTWORK")
    editTex:SetAllPoints()
    editTex:SetTexture("Interface/Buttons/UI-OptionsButton")
    editBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Toggle Edit Mode (move/resize)")
        GameTooltip:Show()
    end)
    editBtn:SetScript("OnLeave", function() GameTooltip_Hide() end)
    editBtn:SetScript("OnClick", function()
        if not ReplayFrame._editMode then
            if ReplayFrame.BeginManualEdit then ReplayFrame:BeginManualEdit() else ReplayFrame:SetEditMode(true) end
        else
            if ReplayFrame.EndManualEdit then ReplayFrame:EndManualEdit() else ReplayFrame:SetEditMode(false) end
        end
    end)
    self.EditModeButton = editBtn

    -- Resize Grip
    local resizeGrip = CreateFrame("Frame", nil, self.DisplayFrame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", ReplayFrame.DisplayFrame, "BOTTOMRIGHT", -2, 2)
    resizeGrip:EnableMouse(true)
    local gripTex = resizeGrip:CreateTexture(nil, "ARTWORK")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface/CHATFRAME/UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetScript("OnEnter", function(self)
        self:GetRegions():SetTexture("Interface/CHATFRAME/UI-ChatIM-SizeGrabber-Highlight")
    end)
    resizeGrip:SetScript("OnLeave", function(self)
        self:GetRegions():SetTexture("Interface/CHATFRAME/UI-ChatIM-SizeGrabber-Up")
    end)
    resizeGrip:SetScript("OnMouseDown", function()
    this.DisplayFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
    this.DisplayFrame:StopMovingOrSizing()
    this:SaveFramePosition()
    end)
    local gripTex = resizeGrip:CreateTexture(nil, "ARTWORK")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip.texture = gripTex
    self.ResizeGrip = resizeGrip

    -- Dynamic scaling on resize (layout only; bounds handled by SetResizeBounds)
    self.DisplayFrame:SetScript("OnSizeChanged", function(frame, newWidth, newHeight)
        local width, height = newWidth, newHeight
        local compact = CLN.db and CLN.db.profile and CLN.db.profile.compactMode
        local hasModel = this._hasValidModel and not compact

        if this.ModelContainer then
            this.ModelContainer:ClearAllPoints()
            this.ModelContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -8)
            this.ModelContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -8)
            this.ModelContainer:SetHeight(self.npcModelFrameHeight or 140)
            if hasModel then this.ModelContainer:Show() else this.ModelContainer:Hide() end
        end
        -- Layout the model area via extracted module
        if this.LayoutModelArea then this:LayoutModelArea(frame) end

        if this.ContentFrame then
            this.ContentFrame:ClearAllPoints()
            if hasModel and this.ModelContainer then
                -- content directly below full-width model container
                this.ContentFrame:SetPoint("TOPLEFT", this.ModelContainer, "BOTTOMLEFT", 0, -6)
                this.ContentFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
            else
                this.ContentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
                this.ContentFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
            end
            this.ContentFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 5)
        end

        CLN.db.profile.expandedWidth = width
    -- Scale header font size based on height
        if this.HeaderText then
            local headerFontSize = math.max(10, math.min(20, math.floor((height) / 8)))
        local scale = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.queueTextScale) or 1.0
    this.HeaderText:SetFont("Fonts\\FRIZQT__.TTF", headerFontSize * scale, "")
        end
    -- ScrollBox anchors handle their own layout; nothing else to do here.
    if this.ApplyQueueTextScale then this:ApplyQueueTextScale() end
    -- Re-flow visible row texts to fit new width
    if this.QueueScrollBox and ScrollUtil and ScrollUtil.IterateToActive then
        for _, row in ScrollUtil.IterateToActive(this.QueueScrollBox) do
            if row.text and row.text.GetText then
                local original = row._fullText or row.text:GetText()
                row._fullText = original
                row.text:SetText(original)
                local available = (row:GetWidth() or 0) - 28
                if available > 20 then
                    local function fits(s)
                        row.text:SetText(s)
                        return (row.text:GetStringWidth() or 0) <= available
                    end
                    if not fits(original) then
                        local lo, hi = 1, #original
                        local best = 0
                        while lo <= hi do
                            local mid = math.floor((lo + hi) / 2)
                            local candidate = string.sub(original, 1, mid) .. "..."
                            if fits(candidate) then best = mid; lo = mid + 1 else hi = mid - 1 end
                        end
                        if best > 0 then
                            row.text:SetText(string.sub(original, 1, best) .. "...")
                        else
                            row.text:SetText("...")
                        end
                    end
                end
            end
        end
    end
    if this.SaveSizeForActiveLayout then this:SaveSizeForActiveLayout() end
    end)
    -- Hover overlay and control highlighting in edit mode
    self.DisplayFrame:SetScript("OnEnter", function()
        if this._editMode then
            if not this._hoverOverlay then
                local ov = CreateFrame("Frame", nil, this.DisplayFrame)
                ov:SetAllPoints()
                ov:EnableMouse(false)
                ov:SetFrameStrata("TOOLTIP")
                local bg = ov:CreateTexture(nil, "OVERLAY")
                bg:SetAllPoints()
                bg:SetColorTexture(0, 0.1, 0.2, 0.10)
                ov.bg = bg
                local label = ov:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
                label:SetPoint("TOP", 0, -8)
                label:SetText("ChattyLittleNpc — Replay Window")
                label:SetTextColor(1.0, 0.82, 0.0)
                ov.label = label
                this._hoverOverlay = ov
            end
            this._hoverOverlay:Show()
            if this.HighlightEditControls then this:HighlightEditControls(true) end
        end
    end)
    self.DisplayFrame:SetScript("OnLeave", function()
        if this._editMode then
            if this._hoverOverlay then this._hoverOverlay:Hide() end
            if this.HighlightEditControls then this:HighlightEditControls(false) end
        end
    end)
    -- Right-click context menu (Retail MenuUtil with Classic fallback)
    self.DisplayFrame:SetScript("OnMouseDown", function(frame, button)
        if button == "RightButton" then
            this:OpenContextMenu(frame)
        end
    end)
    self.DisplayFrame:SetScript("OnHide", function()
        if this._editMode or this._isDragging then return end
        if this.StopSpeakingAnimation then this:StopSpeakingAnimation() end
        if this:IsVoiceoverCurrenltyPlaying() then
            if not this.userHidden then
                C_Timer.After(0, function()
                    if this.DisplayFrame and not this.DisplayFrame:IsShown() then
                        this:UpdateDisplayFrameState()
                    end
                end)
            else
                this:EnsureMinimizedButton()
                this.MinButton:Show()
            end
        else
            if this.MinButton then this.MinButton:Hide() end
            this.userHidden = false
        end
    end)
    -- ScrollBox list for the conversation queue
    local scrollBox = CreateFrame("Frame", "ChattyLittleNpcQueueScrollBox", contentFrame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -36)
    scrollBox:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -8, 8)

    local view = CreateScrollBoxListLinearView()
    -- Provide a fixed extent so the view doesn't require template metrics
    if view.SetElementExtent then view:SetElementExtent(24) end
    local function setupRow(row, element)
            if not row._initialized then
                row:SetHeight(24)
                row:EnableMouse(true)

                -- Manual highlight texture
                local hl = row:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints()
                hl:SetTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
                hl:SetAlpha(0.15)
                hl:Hide()
                row._hl = hl

                -- Bullet texture like Objectives tracker (small gold dot)
                local bulletTex = row:CreateTexture(nil, "ARTWORK")
                bulletTex:SetPoint("LEFT", 8, 0)
                bulletTex:SetSize(4, 4)
                bulletTex:SetTexture("Interface\\Buttons\\WHITE8x8")
                bulletTex:SetVertexColor(0.85, 0.78, 0.18, 1)
                row.bulletTex = bulletTex

                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.text:SetPoint("LEFT", row.bulletTex, "RIGHT", 6, 0)
                row.text:SetPoint("RIGHT", -24, 0)
                row.text:SetWordWrap(false)
                if row.text.SetTextToFit then row.text:SetTextToFit() end
                -- initialize font with current scale
                local baseHeight = 12
                local userScale = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.queueTextScale) or 1.0
                local a11y = (this and this.GetAccessibilityTextScale and this:GetAccessibilityTextScale()) or 1
                local finalScale = math.max(0.5, math.min(2.0, userScale * a11y))
                local _, _, flags = row.text:GetFont()
                row.text:SetFont("Fonts\\FRIZQT__.TTF", baseHeight * finalScale, flags)

                row.stop = CreateFrame("Button", nil, row)
                row.stop:SetSize(16, 16)
                row.stop:SetPoint("RIGHT", -2, 0)
                row.stop:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
                row.stop:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    GameTooltip:SetText("Stop and remove from list")
                    GameTooltip:Show()
                end)
                row.stop:SetScript("OnLeave", GameTooltip_Hide)

                row._initialized = true
            end

            -- Dynamic truncation based on available width
            row._fullText = element.label
            row.text:SetText(element.label)
            do
                local available = (row:GetWidth() or 0) - 28 -- bullet+padding+stop
                if available > 20 then
                    local text = element.label or ""
                    local font, size, flags = row.text:GetFont()
                    local function fits(s)
                        row.text:SetText(s)
                        local w = row.text:GetStringWidth() or 0
                        return w <= available
                    end
                    if not fits(text) then
                        local lo, hi = 1, #text
                        local best = 0
                        while lo <= hi do
                            local mid = math.floor((lo + hi) / 2)
                            local candidate = string.sub(text, 1, mid) .. "..."
                            if fits(candidate) then
                                best = mid
                                lo = mid + 1
                            else
                                hi = mid - 1
                            end
                        end
                        if best > 0 then
                            row.text:SetText(string.sub(text, 1, best) .. "...")
                        else
                            row.text:SetText("...")
                        end
                    end
                end
            end
            row._isActive = element.isPlaying and true or false
            if row._isActive then
                row.text:SetTextColor(1.0, 0.82, 0.0) -- active: brighter gold
                if row.bulletTex then row.bulletTex:SetVertexColor(1.0, 0.82, 0.0, 1) end
            else
                -- default Objectives-like gold text
                row.text:SetTextColor(0.95, 0.86, 0.20)
                if row.bulletTex then row.bulletTex:SetVertexColor(0.85, 0.78, 0.18, 1) end
            end
            -- apply scaling on refresh, too
            do
                local baseHeight = 12
                local userScale = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.queueTextScale) or 1.0
                local a11y = (this and this.GetAccessibilityTextScale and this:GetAccessibilityTextScale()) or 1
                local finalScale = math.max(0.5, math.min(2.0, userScale * a11y))
                local _, _, flags = row.text:GetFont()
                row.text:SetFont("Fonts\\FRIZQT__.TTF", baseHeight * finalScale, flags)
            end

            row.stop:SetScript("OnClick", function()
                if element.isPlaying then
                    CLN.VoiceoverPlayer:ForceStopCurrentSound(false)
                elseif element.queueIndex then
                    table.remove(CLN.questsQueue, element.queueIndex)
                end
                ReplayFrame:UpdateDisplayFrameState()
            end)

            row:SetScript("OnEnter", function(self)
                if self._hl then self._hl:Show() end
                if not self._isActive and self.text then
                    self.text:SetTextColor(1.0, 0.82, 0.0)
                end
                if element.tooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(element.isPlaying and "Now Playing" or "Queued", 1.0, 0.82, 0.0, true)
                    GameTooltip:AddLine(element.tooltip, 0.9, 0.9, 0.9, true)
                    if GameTooltip.SetMaximumWidth then GameTooltip:SetMaximumWidth(360) end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                if self._hl then self._hl:Hide() end
                if not self._isActive and self.text then
                    self.text:SetTextColor(0.95, 0.86, 0.20)
                end
                GameTooltip_Hide()
            end)
    end
    view:SetElementFactory(function(factory)
        factory("Frame", setupRow)
    end)

    -- Initialize without a visible scrollbar when supported (Retail)
    if ScrollUtil and ScrollUtil.InitScrollBoxList then
        ScrollUtil.InitScrollBoxList(scrollBox, view)
    else
        -- Fallback for older clients: create a hidden scrollbar to satisfy API
        local scrollBar = CreateFrame("EventFrame", "ChattyLittleNpcQueueScrollBar", contentFrame, "WowTrimScrollBar")
        scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, 0)
        scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 0)
        scrollBar:Hide()
        if ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar then
            ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
        end
        self.QueueScrollBar = scrollBar
    end
    self.QueueScrollBox = scrollBox
    self.QueueView = view
    if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end

    -- Watch CVars/UI scale changes to auto-apply accessibility scaling
    if not self.CVarWatcher then
        local watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", function(_, event, name, value)
            if not self.ApplyQueueTextScale then return end
            if event == "CVAR_UPDATE" then
                if type(name) == "string" then
                    local n = string.lower(name)
                    if n == "uitextscale" or n == "textscale" or n == "uitextsize" then
                        self:ApplyQueueTextScale()
                    end
                end
            else
                -- UI scale or display size changed
                self:ApplyQueueTextScale()
            end
        end)
        watcher:RegisterEvent("CVAR_UPDATE")
        if watcher.RegisterEvent then watcher:RegisterEvent("UI_SCALE_CHANGED") end
        if watcher.RegisterEvent then watcher:RegisterEvent("DISPLAY_SIZE_CHANGED") end
        self.CVarWatcher = watcher
    end

    -- Duplicate NPC model frame removed; using ChattyLittleNpcModelFrame defined earlier
    ReplayFrame:EnsureMinimizedButton()
    ReplayFrame:UpdateDisplayFrameState()
    -- Bind to Blizzard Edit Mode so our frame is editable when Edit Mode is active
    if self.BindBlizzardEditMode then
        self:BindBlizzardEditMode()
    end
    -- Edit Mode overlay/watcher removed
end

function ReplayFrame:IsCompactModeEnabled()
    return CLN and CLN.db and CLN.db.profile and CLN.db.profile.compactMode
end

function ReplayFrame:ApplyCompactMode()
    if not ReplayFrame.DisplayFrame or not ReplayFrame.ContentFrame then return end
    local frame = self.DisplayFrame
    local height = frame:GetHeight()
    if ReplayFrame:IsCompactModeEnabled() then
        -- Shrink to normal width and hide model
    -- If we have a remembered compact width, use it; else default normalWidth
    local w = (CLN.db and CLN.db.profile and CLN.db.profile.compactWidth) or self.normalWidth
    frame:SetWidth(w)
        if self.NpcModelFrame then
            self.NpcModelFrame:Hide()
        end
        self.ContentFrame:ClearAllPoints()
        self.ContentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
        self.ContentFrame:SetSize(frame:GetWidth() - 10, height - 5)
    else
        -- Allow model to expand the width as needed later
    local w = (CLN.db and CLN.db.profile and CLN.db.profile.expandedWidth) or self.expandedWidth
    frame:SetWidth(w)
        if self.NpcModelFrame then
            -- visibility controlled by current NPC state
        end
        self.ContentFrame:ClearAllPoints()
        self.ContentFrame:SetPoint("TOPLEFT", self.NpcModelFrame, "TOPRIGHT", 2.5, 0)
        self.ContentFrame:SetSize(frame:GetWidth() - height - 5, height - 5)
        self:CheckAndShowModel()
    end
    -- Persist updated size after mode change
    self:SaveFramePosition()
end

-- Build or refresh the queue data provider used by the ScrollBox
function ReplayFrame:RefreshQueueDataProvider()
    if not self.QueueScrollBox then return end
    local provider = CreateDataProvider()

    -- Build a list of entries (now playing first, then queued)
    local entries = {}
    local nowPlayingIndex = nil
    if CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying.title then
        local title = CLN.VoiceoverPlayer.currentlyPlaying.title
        table.insert(entries, { isPlaying = true, label = title, tooltip = title })
        nowPlayingIndex = 1
    end

    if CLN.questsQueue then
        for i, quest in ipairs(CLN.questsQueue) do
            if quest.title then
                table.insert(entries, { queueIndex = i, label = quest.title, tooltip = quest.title })
            end
        end
    end

    -- Compute how many rows fit, and keep the latest that fit (always include now playing)
    local rowsFit = 6
    if self.ContentFrame and self.ContentFrame.GetHeight then
        local h = self.ContentFrame:GetHeight() or 0
        rowsFit = math.max(1, math.floor((h - 36 - 8) / 24))
    end
    local selected = {}
    if #entries <= rowsFit then
        selected = entries
    else
        if nowPlayingIndex then
            -- Always include now playing, plus most recent others from the end
            table.insert(selected, entries[nowPlayingIndex])
            local needed = rowsFit - 1
            for idx = #entries, 1, -1 do
                if needed <= 0 then break end
                if idx ~= nowPlayingIndex then
                    table.insert(selected, entries[idx])
                    needed = needed - 1
                end
            end
            -- Keep selected in a sensible order: now playing first, rest newest last
            -- Reverse tail so newest appears at bottom
            if #selected > 1 then
                local head = selected[1]
                local tail = {}
                for i = 2, #selected do table.insert(tail, selected[i]) end
                local rev = {}
                for i = #tail, 1, -1 do table.insert(rev, tail[i]) end
                selected = { head }
                for _, v in ipairs(rev) do table.insert(selected, v) end
            end
        else
            -- No now playing: just take the last rowsFit items in order
            for i = math.max(1, #entries - rowsFit + 1), #entries do
                table.insert(selected, entries[i])
            end
        end
    end

    for _, item in ipairs(selected) do
        provider:Insert(item)
    end

    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil
    self.QueueScrollBox:SetDataProvider(provider, retain)
end

function ReplayFrame:UpdateDisplayFrame()
    if (not self._forceShow) and (not self:IsShowReplayFrameToggleIsEnabled() or not CLN.VoiceoverPlayer.currentlyPlaying) then
        if (self.DisplayFrame) then
            self.DisplayFrame:Hide()
        end
        return
    end

    -- Hide Frame if there are no actively playing voiceover and no quests in queue
    if (not self._forceShow) and (not self:IsVoiceoverCurrenltyPlaying() and self:IsQuestQueueEmpty()) then
        if (self.DisplayFrame) then
            self.DisplayFrame:Hide()
        end
        if self.MinButton then self.MinButton:Hide() end
        self.userHidden = false
        return
    end

    if (not self._forceShow) and (self:IsDisplayFrameHideNeeded()) then
        self.DisplayFrame:Hide()
        return
    end

    if (not CLN.VoiceoverPlayer.currentlyPlaying.title) then
        CLN.VoiceoverPlayer.currentlyPlaying.title = CLN:GetTitleForQuestID(CLN.VoiceoverPlayer.currentlyPlaying.questId)

        if (CLN.db.profile.debugMode) then
            CLN:Print(
            "Getting missing title for quest id:",
            CLN.VoiceoverPlayer.currentlyPlaying.questId,
            ", title found is:",
            CLN.VoiceoverPlayer.currentlyPlaying.title)
        end
    end

    if (self.HeaderText) then
        local qcount = (CLN.questsQueue and #CLN.questsQueue or 0)
        local playingTitle = CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying.title or nil
        local playingCount = playingTitle and 1 or 0
        local total = playingCount + qcount
        local collapsed = self.CollapseButton and self.CollapseButton._collapsed
        if total > 0 then
            if collapsed and playingTitle then
                self.HeaderText:SetText(string.format("%s (%d)", playingTitle, total))
            else
                self.HeaderText:SetText(string.format("Conversation Queue (%d)", total))
            end
        else
            self.HeaderText:SetText("Conversation Queue")
        end
    end

    -- Refresh the ScrollBox list from current state
    self:RefreshQueueDataProvider()
    if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end

    -- Respect user-hidden during playback: keep minimized indicator instead of reopening
    if (not self._forceShow) and self.userHidden and self:IsVoiceoverCurrenltyPlaying() then
        self:EnsureMinimizedButton()
        self.MinButton:Show()
        return
    end

    self:UpdateParent()
    self.DisplayFrame:Show()
    if self.MinButton then self.MinButton:Hide() end
    self:CheckAndShowModel()
    self.userHidden = false
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

function ReplayFrame:UpdateParent()
    if not self.DisplayFrame then return end
    if self._editMode or self._isDragging then return end
    local parent = UIParent
    if (self:IsDialogueUIFrameShow()) then
        parent = _G["DUIQuestFrame"]
    end
    self:ReparentPreservingScreenPosition(parent)
end

function ReplayFrame:UpdateDisplayFrameState()
    if self._editMode or self._isDragging then return end
    self:GetDisplayFrame()
    self:UpdateDisplayFrame()
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

-- Re-apply size-based layout without user resize
function ReplayFrame:Relayout()
    if not self.DisplayFrame then return end
    local f = self.DisplayFrame
    local w, h = f:GetSize()
    local cb = f:GetScript("OnSizeChanged")
    if cb then cb(f, w, h) end
end

function ReplayFrame:IsVoiceoverCurrenltyPlaying()
    return CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying:isPlaying()
end

function ReplayFrame:IsShowReplayFrameToggleIsEnabled()
    return CLN.db.profile.showReplayFrame
end

function ReplayFrame:IsDisplayFrameCurrentlyShown()
    return self.DisplayFrame and self.DisplayFrame:IsShown()
end

function ReplayFrame:IsQuestQueueEmpty()
    return CLN.questsQueue and #CLN.questsQueue == 0
end

function ReplayFrame:IsDisplayFrameHideNeeded()
    return ((not self:IsShowReplayFrameToggleIsEnabled())
        or (not CLN.VoiceoverPlayer.currentlyPlaying)
        or ((not self:IsVoiceoverCurrenltyPlaying()) and self:IsQuestQueueEmpty() and self:IsDisplayFrameCurrentlyShown()))
end

function ReplayFrame:IsDialogueUIFrameShow()
    return CLN.isDUIAddonLoaded and _G["DUIQuestFrame"] and _G["DUIQuestFrame"]:IsShown()
end

function ReplayFrame:GetAccessibilityTextScale()
    if C_CVar and C_CVar.GetCVar then
        local keys = { "uiTextScale", "textScale", "uiTextSize" }
        for _, key in ipairs(keys) do
            local ok, val = pcall(C_CVar.GetCVar, key)
            if ok and val then
                local num = tonumber(val)
                if num and num > 0 then
                    return num
                end
            end
        end
    end
    return 1
end

function ReplayFrame:ApplyQueueTextScale()
    local userScale = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.queueTextScale) or 1.0
    local a11y = self:GetAccessibilityTextScale() or 1
    local finalScale = math.max(0.5, math.min(2.0, userScale * a11y))

    -- Header
    if self.HeaderText and self.DisplayFrame then
        local h = self.DisplayFrame:GetHeight() or 165
        local base = math.max(10, math.min(20, math.floor(h / 8)))
    self.HeaderText:SetFont("Fonts\\FRIZQT__.TTF", base * finalScale, "")
    end

    -- Active rows only
    if self.QueueScrollBox then
        local baseHeight = 12
        if ScrollUtil and ScrollUtil.IterateToActive then
            for _, row in ScrollUtil.IterateToActive(self.QueueScrollBox) do
                if row.text then
                    local _, _, flags = row.text:GetFont()
                    row.text:SetFont("Fonts\\FRIZQT__.TTF", baseHeight * finalScale, flags)
                end
                if row.bulletTex and row.bulletTex.SetSize then
                    local sz = math.max(3, math.floor((baseHeight * finalScale) * 0.33))
                    row.bulletTex:SetSize(sz, sz)
                end
            end
        end
    end
end

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

function ReplayFrame:OpenContextMenu(owner)
    -- Retail context menu (Edit Mode options removed)
    if MenuUtil and MenuUtil.CreateContextMenu then
        return MenuUtil.CreateContextMenu(owner, function(_, root)
            for _, e in ipairs(CLN_BuildContextMenuEntries(self)) do
                root:CreateButton(e.text, e.func)
            end
        end)
    end
    -- Classic fallback: simple dropdown using UIDropDownMenu if available
    if UIDropDownMenu_Initialize then
        if not self._dropdown then
            local dd = CreateFrame("Frame", "CLNReplayFrameDropdown", UIParent, "UIDropDownMenuTemplate")
            self._dropdown = dd
        end
        local menu = {}
        for _, e in ipairs(CLN_BuildContextMenuEntries(self)) do
            table.insert(menu, { text = e.text, notCheckable = true, func = e.func })
        end
    -- Edit Mode options removed
        EasyMenu(menu, self._dropdown, owner, 0, 0, "MENU", 2)
        return
    end
    -- Fallback: no-op
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