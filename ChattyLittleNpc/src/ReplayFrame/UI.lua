---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- UI CREATION AND LAYOUT
-- ============================================================================

-- Create the minimized button that appears when frame is hidden
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

-- Create the main display frame and all its child elements
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

    -- Create background
    self:CreateFrameBackground()
    
    -- Setup frame movement and interaction
    self:SetupFrameInteraction()
    
    -- Initialize model container
    self:InitializeModelContainer()
    
    -- Create content frame and all UI elements
    self:CreateContentFrame()
    
    -- Create resize grip
    self:CreateResizeGrip()
    
    -- Setup frame resize handling
    self:SetupFrameResize()
    
    -- Initialize minimized button and bind edit mode
    ReplayFrame:EnsureMinimizedButton()
    ReplayFrame:UpdateDisplayFrameState()
    
    -- Bind to Blizzard Edit Mode so our frame is editable when Edit Mode is active
    if self.BindBlizzardEditMode then
        self:BindBlizzardEditMode()
    end
end

-- Create the frame background (transparent for objectives style)
function ReplayFrame:CreateFrameBackground()
    local bg = self.DisplayFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    -- Keep a transparent background to match Objectives tracker look
    bg:SetColorTexture(0, 0, 0, 0)
    bg:SetAlpha(0)
    self.DisplayFrame.Bg = bg
end

-- Setup frame movement, dragging, and mouse interaction
function ReplayFrame:SetupFrameInteraction()
    local this = self
    
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
    
    -- Allow closing with ESC
    if UISpecialFrames then
        self.DisplayFrame:RegisterForDrag("LeftButton")
    end
    
    -- Right-click context menu removed for cleaner interface
    
    -- Handle frame hide events
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
    
    -- Hover overlay for edit mode
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
                label:SetPoint("CENTER")
                label:SetText("Drag to move, resize from corner")
                label:SetTextColor(1, 1, 1, 0.8)
                ov.label = label
                this._hoverOverlay = ov
            end
            this._hoverOverlay:Show()
            if this.HighlightEditControls then this:HighlightEditControls(true) end
        end
    end)
    
    self.DisplayFrame:SetScript("OnLeave", function()
        if this._hoverOverlay then this._hoverOverlay:Hide() end
        if this.HighlightEditControls then this:HighlightEditControls(false) end
    end)
end

-- Initialize the model container (delegate to ModelFrame if available)
function ReplayFrame:InitializeModelContainer()
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
end

-- Create the content frame and all UI elements within it
function ReplayFrame:CreateContentFrame()
    local this = self
    
    -- Child frame: Content (quest queue and voiceover text)
    local contentFrame = CreateFrame("Frame", "ChattyLittleNpcContentFrame", self.DisplayFrame)
    contentFrame:SetPoint("TOPLEFT", self.DisplayFrame, "TOPLEFT", 5, -5)
    contentFrame:SetPoint("TOPRIGHT", self.DisplayFrame, "TOPRIGHT", -5, -5)
    contentFrame:SetPoint("BOTTOMLEFT", self.DisplayFrame, "BOTTOMLEFT", 5, 5)
    self.ContentFrame = contentFrame

    -- Create header and controls
    self:CreateHeaderElements(contentFrame)
    
    -- Create header buttons
    self:CreateHeaderButtons(contentFrame)
    
    -- Create the scroll box for the conversation queue
    self:CreateScrollBox(contentFrame)
    
    -- Setup CVar watcher for text scaling
    self:SetupCVarWatcher()
end

-- Create header title and divider
function ReplayFrame:CreateHeaderElements(contentFrame)
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
end

-- Create all header buttons (collapse, clear, options, edit)
function ReplayFrame:CreateHeaderButtons(contentFrame)
    local this = self
    
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

    -- Clear button
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

    -- Options button
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

    -- Edit Mode toggle button
    local editBtn = CreateFrame("Button", nil, contentFrame)
    editBtn:SetSize(18, 18)
    editBtn:SetPoint("RIGHT", optionsBtn, "LEFT", -6, 0)
    local editTex = editBtn:CreateTexture(nil, "ARTWORK")
    editTex:SetAllPoints()
    editTex:SetTexture("Interface/CURSOR/UI-Cursor-Move")
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
end

-- Create the resize grip in the bottom-right corner
function ReplayFrame:CreateResizeGrip()
    local this = self
    
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
    
    resizeGrip.texture = gripTex
    self.ResizeGrip = resizeGrip
end

-- Create the scroll box for the conversation queue
function ReplayFrame:CreateScrollBox(contentFrame)
    local this = self
    
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
            bulletTex:SetColorTexture(1.0, 0.82, 0.0, 0.9) -- gold
            row.bulletTex = bulletTex

            -- Row text
            local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", bulletTex, "RIGHT", 8, 0)
            text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            text:SetJustifyH("LEFT")
            text:SetTextColor(0.95, 0.86, 0.20) -- similar to Objectives tracker
            row.text = text

            -- Row click handler
            row:SetScript("OnClick", function(self, button)
                local e = self._element
                if not e then return end
                if button == "LeftButton" then
                    if e.isPlaying then
                        -- Stop current playback
                        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
                        this.userHidden = false
                        this:UpdateDisplayFrameState()
                    elseif e.queueIndex then
                        -- Play from queue position
                        local qi = e.queueIndex
                        local toPlay = {}
                        for i = qi, #CLN.questsQueue do
                            table.insert(toPlay, CLN.questsQueue[i])
                        end
                        CLN.questsQueue = {}
                        for _, quest in ipairs(toPlay) do
                            CLN:PlayQuestTTS(quest)
                        end
                    end
                end
            end)

            row:SetScript("OnEnter", function(self)
                if self._hl then self._hl:Show() end
                if not self._isActive and self.text then
                    self.text:SetTextColor(1.0, 1.0, 1.0)
                end
                local element = self._element
                if element and element.tooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    GameTooltip:SetText(element.tooltip, 0.9, 0.9, 0.9, true)
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
        
        -- Update row content
        row._element = element
        if element then
            row._isActive = element.isPlaying
            if row.text then
                -- Set text and handle wrapping
                local label = element.label or "Unknown"
                row._fullText = label
                row.text:SetText(label)
                
                -- Apply text scaling
                if this.ApplyQueueTextScale then this:ApplyQueueTextScale() end
                
                -- Fit text to available width
                local available = (row:GetWidth() or 0) - 28
                if available > 20 then
                    local function fits(s)
                        row.text:SetText(s)
                        return (row.text:GetStringWidth() or 0) <= available
                    end
                    if not fits(label) then
                        local lo, hi = 1, #label
                        local best = 0
                        while lo <= hi do
                            local mid = math.floor((lo + hi) / 2)
                            local candidate = string.sub(label, 1, mid) .. "..."
                            if fits(candidate) then 
                                best = mid
                                lo = mid + 1 
                            else 
                                hi = mid - 1 
                            end
                        end
                        if best > 0 then
                            row.text:SetText(string.sub(label, 1, best) .. "...")
                        else
                            row.text:SetText("...")
                        end
                    end
                end
                
                -- Set text color based on state
                if element.isPlaying then
                    row.text:SetTextColor(0.2, 1.0, 0.2) -- bright green for playing
                else
                    row.text:SetTextColor(0.95, 0.86, 0.20) -- gold for queued
                end
            end
            
            -- Show/hide bullet
            if row.bulletTex then
                row.bulletTex:SetShown(true)
            end
        else
            -- Clear row
            if row.text then row.text:SetText("") end
            if row.bulletTex then row.bulletTex:Hide() end
            row._isActive = false
        end
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
end

-- Setup CVar watcher for accessibility text scaling
function ReplayFrame:SetupCVarWatcher()
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
end

-- Setup frame resize handling
function ReplayFrame:SetupFrameResize()
    local this = self
    
    -- Dynamic scaling on resize (layout only; bounds handled by SetResizeBounds)
    self.DisplayFrame:SetScript("OnSizeChanged", function(frame, newWidth, newHeight)
        local width, height = newWidth, newHeight
        local compact = CLN.db and CLN.db.profile and CLN.db.profile.compactMode
        local hasModel = this._hasValidModel and not compact

        if this.ModelContainer then
            this.ModelContainer:ClearAllPoints()
            this.ModelContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -8)
            this.ModelContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -8)
            this.ModelContainer:SetHeight(this.npcModelFrameHeight or 140)
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
end
