---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- UI CREATION AND LAYOUT
-- ============================================================================

-- Lazily create and return the main display frame
function ReplayFrame:GetDisplayFrame()
    if self.DisplayFrame then return self.DisplayFrame end

    local frame = CreateFrame("Frame", "ChattyLittleNpcDisplayFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    -- Resize only allowed in Edit Mode (will be enabled there)
    frame:SetResizable(false)

    -- Defaults; will be overridden by saved size/position if present
    self.normalWidth = self.normalWidth or 310
    self.expandedWidth = self.expandedWidth or (CLN and CLN.db and CLN.db.profile and CLN.db.profile.frameSize and CLN.db.profile.frameSize.width) or (self.normalWidth)
    local defaultW = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.frameSize and CLN.db.profile.frameSize.width) or (self.expandedWidth or 475)
    local defaultH = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.frameSize and CLN.db.profile.frameSize.height) or 165
    frame:SetSize(defaultW, defaultH)
    if frame.SetResizeBounds then frame:SetResizeBounds(260, 120) end

    self.DisplayFrame = frame

    -- Build UI parts
    self:CreateContentFrame()
    self:InitializeModelContainer()
    self:CreateResizeGrip()
    self:SetupFrameResize()

    -- Initialize state machine (idempotent)
    if self.InitStateMachine then self:InitStateMachine() end

    -- Position after components exist
    if self.LoadFramePosition then self:LoadFramePosition() end

    return frame
end

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
    -- click to restore/show frame
    btn:SetScript("OnClick", function()
        ReplayFrame.userHidden = false
        if ReplayFrame.UpdateDisplayFrameState then
            ReplayFrame:UpdateDisplayFrameState()
        end
    end)
    self.MinButton = btn
    if self.LoadMinButtonPosition then self:LoadMinButtonPosition() end
end

-- Initialize the model container (delegate to ModelFrame if available)
function ReplayFrame:InitializeModelContainer()
    self.npcModelFrameWidth = 220
    self.npcModelFrameHeight = 140

    -- Initialize the model container and model frame via extracted module (idempotent)
    if self.CreateModelUI and not (self.ModelContainer or self.NpcModelFrame) then
        self:CreateModelUI()
        if self.LayoutModelArea and self.DisplayFrame then
            self:LayoutModelArea(self.DisplayFrame)
        end
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
        if self.LayoutModelArea and self.DisplayFrame then
            self:LayoutModelArea(self.DisplayFrame)
        end
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
    -- After buttons exist, constrain the header to end just before the buttons
    if self.AnchorHeaderToButtons then self:AnchorHeaderToButtons() end
    
    -- Create the non-scrolling list for the conversation queue
    self:CreateScrollBox(contentFrame)
    
    -- Setup CVar watcher for text scaling
    self:SetupCVarWatcher()
end

-- Create header title and divider
function ReplayFrame:CreateHeaderElements(contentFrame)
    -- Header title (styled like Objectives tracker)
    local header = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    header:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -6)
    header:SetText("Conversations")
    header:SetTextColor(1.0, 0.82, 0.0) -- gold
    if header.SetWordWrap then header:SetWordWrap(false) end
    if header.SetMaxLines then header:SetMaxLines(1) end
    self.HeaderText = header

    -- Divider below header
    local divider = contentFrame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1.0, 0.82, 0.0, 0.35) -- slightly stronger like Objectives
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -4)
    divider:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -10, -4)
    divider:SetHeight(1)
    self.HeaderDivider = divider
end
-- Return the real available width (in pixels) that a row's text can use
function ReplayFrame:GetRowTextAvailableWidth(row)
    if not (row and row.text) then return 0 end
    -- Preferred: compute from on-screen coordinates to include right anchor
    local left = row.text.GetLeft and row.text:GetLeft() or nil
    local right = row.GetRight and row:GetRight() or nil
    if left and right then
        local pad = 8 -- mirror the RIGHT -8 used in SetPoint
        local w = (right - pad) - left
        if w and w > 0 then return w end
    end
    -- Fallback to row width minus approximate bullet/left padding
    local fallback = (row.GetWidth and row:GetWidth() or 0) - 28
    return math.max(0, fallback)
end

-- Fit a single row's text to its available width, appending ellipses if needed
function ReplayFrame:FitRowText(row)
    if not (row and row.text) then return end
    local full = row._fullText or row.text:GetText() or ""
    local available = self:GetRowTextAvailableWidth(row)
    -- If layout not ready yet (no coordinates), try again next frame
    if (not available) or available <= 0 then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if row and row:IsShown() then self:FitRowText(row) end
            end)
        end
        return
    end
    local function fits(s)
        row.text:SetText(s)
        return (row.text:GetStringWidth() or 0) <= available
    end
    -- First try full text (this can undo a prior over-truncation)
    if fits(full) then
        row.text:SetText(full)
        return
    end
    -- Binary search for the longest prefix that fits with "..."
    local lo, hi, best = 1, #full, 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local candidate = string.sub(full, 1, mid) .. "..."
        if fits(candidate) then best = mid; lo = mid + 1 else hi = mid - 1 end
    end
    if best > 0 then
        row.text:SetText(string.sub(full, 1, best) .. "...")
    else
        row.text:SetText("...")
    end
end


-- Ensure the header fills all space up to the left of the right-side buttons
function ReplayFrame:AnchorHeaderToButtons()
    if not (self.HeaderText and self.ContentFrame) then return end
    -- Prefer the left-most always-visible button as the right anchor (editBtn exists even when lock is hidden)
    local rightAnchor = self.EditModeButton or self.OptionsButton or self.ClearButton or self.CollapseButton
    self.HeaderText:ClearAllPoints()
    self.HeaderText:SetPoint("TOPLEFT", self.ContentFrame, "TOPLEFT", 10, -6)
    if rightAnchor then
        self.HeaderText:SetPoint("RIGHT", rightAnchor, "LEFT", -6, 0)
    else
        -- Fallback to full width if buttons missing
        self.HeaderText:SetPoint("RIGHT", self.ContentFrame, "RIGHT", -10, 0)
    end
end

-- Truncate a fontstring's text to fit a given pixel width using "..."
function ReplayFrame:TruncateToWidth(fs, text, maxWidth)
    if not (fs and text and maxWidth and maxWidth > 0) then return end
    fs:SetText(text)
    local w = fs:GetStringWidth() or 0
    if w <= maxWidth then return end
    local lo, hi = 1, #text
    local best = 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local candidate = string.sub(text, 1, mid) .. "..."
        fs:SetText(candidate)
        local cw = fs:GetStringWidth() or 0
        if cw <= maxWidth then best = mid; lo = mid + 1 else hi = mid - 1 end
    end
    if best > 0 then
        fs:SetText(string.sub(text, 1, best) .. "...")
    else
        fs:SetText("...")
    end
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
        local targetCollapsed = not self._collapsed
        self._collapsed = targetCollapsed
        SetChevron(not targetCollapsed)
        if ReplayFrame.AnimateCollapse then
            ReplayFrame:AnimateCollapse(targetCollapsed, 0.2)
        else
            -- Instant fallback
            local frame = this.DisplayFrame
            if targetCollapsed then
                if frame and frame.GetHeight then this._preCollapseHeight = frame:GetHeight() end
                if this.QueueScrollBox then this.QueueScrollBox:Hide() end
                if this.HeaderDivider then this.HeaderDivider:Hide() end
                if frame and frame.SetHeight then
                    local base = 44
                    if this.HeaderText and this.HeaderText.GetStringHeight then
                        local h = math.ceil(this.HeaderText:GetStringHeight() or 18)
                        base = math.max(36, h + 24)
                    end
                    frame:SetHeight(base)
                end
            else
                if this.HeaderDivider then this.HeaderDivider:Show() end
                if this.QueueScrollBox then this.QueueScrollBox:Show() end
                if frame and frame.SetHeight and this._preCollapseHeight then frame:SetHeight(this._preCollapseHeight) end
            end
            if this.UpdateDisplayFrame then this:UpdateDisplayFrame() end
            if this.Relayout then this:Relayout() end
        end
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
        if ReplayFrame.MarkQueueDirty then ReplayFrame:MarkQueueDirty() end
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
        -- Use the new Options module
        if CLN.Options and CLN.Options.OpenSettings then
            CLN.Options:OpenSettings()
        end
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

    -- Lock toggle button (visible in Edit Mode; appears on hover)
    local lockBtn = CreateFrame("Button", nil, contentFrame)
    lockBtn:SetSize(18, 18)
    lockBtn:SetPoint("RIGHT", editBtn, "LEFT", -6, 0)
    local lockTex = lockBtn:CreateTexture(nil, "ARTWORK")
    lockTex:SetAllPoints()
    lockBtn._tex = lockTex
    lockBtn:Hide()
    lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if ReplayFrame:IsFrameLocked() then
            GameTooltip:SetText("Unlock window (allow moving)")
        else
            GameTooltip:SetText("Lock window (prevent moving)")
        end
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip_Hide() end)
    lockBtn:SetScript("OnClick", function()
        ReplayFrame:SetFrameLocked(not ReplayFrame:IsFrameLocked())
        ReplayFrame:UpdateLockUI()
    end)
    self.LockButton = lockBtn
    if self.UpdateLockUI then self:UpdateLockUI() end

    -- Re-anchor the header now that all buttons exist
    if self.AnchorHeaderToButtons then self:AnchorHeaderToButtons() end
end

-- Tooltip helpers: width and smart sentence splitting
function ReplayFrame:GetTooltipMaxWidth()
    -- Base width; scale slightly with accessibility/text scale
    local base = 420
    base = math.floor(base * 1.25) -- 25% wider
    local a11y = self.GetAccessibilityTextScale and (self:GetAccessibilityTextScale() or 1) or 1
    local scaled = math.floor(base * math.max(0.9, math.min(1.3, a11y)))
    return scaled
end

function ReplayFrame:SplitTooltipIntoSentences(text)
    local lines = {}
    if not text then return lines end
    if type(text) ~= "string" then text = tostring(text) end
    -- Normalize whitespace
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #text == 0 then return lines end
    -- Split on sentence-ending punctuation while keeping it
    for chunk, punc in text:gmatch("([^%.%!%?]+)([%.%!%?]*)%s*") do
        local s = (chunk or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local seg = s .. (punc or "")
        if #seg > 0 then table.insert(lines, seg) end
    end
    -- Fallback if nothing matched
    if #lines == 0 then table.insert(lines, text) end
    return lines
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
        if this._editMode and this.DisplayFrame and this.DisplayFrame.IsResizable and this.DisplayFrame:IsResizable() then
            this._isResizing = true
            -- Ensure we are not moving when starting to size
            if this.DisplayFrame.StopMovingOrSizing then this.DisplayFrame:StopMovingOrSizing() end
            this.DisplayFrame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        if this.DisplayFrame and this.DisplayFrame.StopMovingOrSizing then
            this.DisplayFrame:StopMovingOrSizing()
        end
        if this.SaveFramePosition then this:SaveFramePosition() end
        this._isResizing = false
    end)
    
    resizeGrip.texture = gripTex
    self.ResizeGrip = resizeGrip
    -- Resize only allowed in Edit Mode; keep grip hidden by default
    resizeGrip:Hide()
end

-- Lock state helpers and visuals
function ReplayFrame:IsFrameLocked()
    return (CLN and CLN.db and CLN.db.profile and CLN.db.profile.frameLocked) and true or false
end

function ReplayFrame:SetFrameLocked(locked)
    if not (CLN and CLN.db and CLN.db.profile) then return end
    CLN.db.profile.frameLocked = not not locked
end

function ReplayFrame:UpdateLockUI()
    if not self.LockButton then return end
    local locked = self:IsFrameLocked()
    if locked then
        self.LockButton._tex:SetTexture("Interface/Buttons/LockButton-Locked")
    else
        self.LockButton._tex:SetTexture("Interface/Buttons/LockButton-Unlocked")
    end
end

-- Smoothly animate collapse/expand of the display frame
function ReplayFrame:AnimateCollapse(collapse, duration)
    local frame = self.DisplayFrame
    if not frame then return end
    duration = duration or 0.2

    -- Compute header-only target height
    local function HeaderOnlyHeight()
        local base = 44
        if self.HeaderText and self.HeaderText.GetStringHeight then
            local h = math.ceil(self.HeaderText:GetStringHeight() or 18)
            base = math.max(36, h + 24)
        end
        return base
    end

    -- Record pre-collapse height if needed
    if collapse then
        if frame.GetHeight then self._preCollapseHeight = frame:GetHeight() end
    end

    local startH = frame:GetHeight() or 0
    local endH = collapse and HeaderOnlyHeight() or (self._preCollapseHeight or startH)
    if endH <= 0 then endH = startH end

    -- Simple tween via OnUpdate
    frame._animatingCollapse = true
    frame._animStart = GetTime and GetTime() or 0
    frame._animDur = duration
    frame._animStartH = startH
    frame._animEndH = endH
    frame._animCollapse = collapse

    if not frame._collapseOnUpdate then
        frame._collapseOnUpdate = function()
            local tNow = GetTime and GetTime() or 0
            local t = 0
            if frame._animDur > 0 then
                t = math.min(1, (tNow - (frame._animStart or 0)) / frame._animDur)
            else
                t = 1
            end
            local h = (frame._animStartH or startH) + ((frame._animEndH or endH) - (frame._animStartH or startH)) * t
            if frame.SetHeight then frame:SetHeight(h) end
            if self.QueueScrollBox and self.QueueScrollBox.SetAlpha then
                local alpha = frame._animCollapse and (1 - t) or t
                self.QueueScrollBox:SetAlpha(alpha)
            end
            if self.HeaderDivider and self.HeaderDivider.SetAlpha then
                local alpha = frame._animCollapse and (1 - t) or t
                self.HeaderDivider:SetAlpha(alpha)
            end
            if t >= 1 then
                frame:SetScript("OnUpdate", nil)
                frame._animatingCollapse = false
                -- finalize
                if frame._animCollapse then
                    if self.QueueScrollBox then self.QueueScrollBox:Hide() end
                    if self.HeaderDivider then self.HeaderDivider:Hide() end
                else
                    if self.HeaderDivider then self.HeaderDivider:Show() end
                    if self.QueueScrollBox then self.QueueScrollBox:Show() end
                end
                if self.QueueScrollBox and self.QueueScrollBox.SetAlpha then self.QueueScrollBox:SetAlpha(1) end
                if self.HeaderDivider and self.HeaderDivider.SetAlpha then self.HeaderDivider:SetAlpha(1) end
                if self.UpdateDisplayFrame then self:UpdateDisplayFrame() end
            end
        end
    end
    frame:SetScript("OnUpdate", frame._collapseOnUpdate)
end

-- Create the scroll box for the conversation queue
function ReplayFrame:CreateScrollBox(contentFrame)
    -- Manual, non-scrolling fixed-row list replacing ScrollBox
    local this = self
    local list = CreateFrame("Frame", "ChattyLittleNpcQueueList", contentFrame)
    if self.HeaderDivider then
        list:SetPoint("TOPLEFT", self.HeaderDivider, "BOTTOMLEFT", 0, -6)
        list:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -8, -2)
    else
        list:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -36)
        list:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -8, -2)
    end
    list:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", 8, 8)
    self.QueueListFrame = list
    self.QueueRowHeight = 24
    self.QueueRows = {}

    function this:EnsureQueueRows(n)
        local created = 0
        while #self.QueueRows < n do
            local index = #self.QueueRows + 1
            local row = CreateFrame("Button", nil, self.QueueListFrame)
            row:SetHeight(self.QueueRowHeight)
            row:SetPoint("TOPLEFT", self.QueueListFrame, "TOPLEFT", 0, - (index - 1) * self.QueueRowHeight)
            row:SetPoint("TOPRIGHT", self.QueueListFrame, "TOPRIGHT", 0, - (index - 1) * self.QueueRowHeight)
            row:EnableMouse(true)

            local hl = row:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
            hl:SetAlpha(0.15)
            hl:Hide()
            row._hl = hl

            local bulletTex = row:CreateTexture(nil, "ARTWORK")
            bulletTex:SetPoint("LEFT", 8, 0)
            bulletTex:SetSize(4, 4)
            bulletTex:SetColorTexture(1.0, 0.82, 0.0, 0.9)
            row.bulletTex = bulletTex

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", bulletTex, "RIGHT", 8, 0)
            text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            text:SetJustifyH("LEFT")
            if text.SetWordWrap then text:SetWordWrap(false) end
            text:SetTextColor(0.95, 0.86, 0.20)
            row.text = text

            row:SetScript("OnMouseUp", function(selfBtn, button)
                local e = selfBtn._element
                if not e then return end
                if button == "LeftButton" then
                    if e.isPlaying then
                        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
                        this.userHidden = false
                        this:UpdateDisplayFrameState()
                    elseif e.queueIndex then
                        local qi = e.queueIndex
                        local toPlay = {}
                        for i = qi, #CLN.questsQueue do
                            table.insert(toPlay, CLN.questsQueue[i])
                        end
                        CLN.questsQueue = {}
                        if this.MarkQueueDirty then this:MarkQueueDirty() end
                        for _, q in ipairs(toPlay) do CLN:PlayQuestTTS(q) end
                    end
                end
            end)

            row:SetScript("OnEnter", function(selfBtn)
                if selfBtn._hl then selfBtn._hl:Show() end
                if not selfBtn._isActive and selfBtn.text then
                    selfBtn.text:SetTextColor(1.0, 1.0, 1.0)
                end
                local e = selfBtn._element
                if e and e.tooltip then
                    GameTooltip:SetOwner(selfBtn, "ANCHOR_LEFT")
                    -- Prefer smart sentence split with multiple AddLine calls to improve wrapping
                    local maxW = ReplayFrame.GetTooltipMaxWidth and ReplayFrame:GetTooltipMaxWidth() or 420
                    if GameTooltip.SetMaximumWidth then GameTooltip:SetMaximumWidth(maxW) end
                    local lines = ReplayFrame.SplitTooltipIntoSentences and ReplayFrame:SplitTooltipIntoSentences(e.tooltip) or { e.tooltip }
                    GameTooltip:ClearLines()
                    for i, line in ipairs(lines) do
                        if i == 1 then
                            GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
                        else
                            GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
                        end
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(selfBtn)
                if selfBtn._hl then selfBtn._hl:Hide() end
                if not selfBtn._isActive and selfBtn.text then
                    selfBtn.text:SetTextColor(0.95, 0.86, 0.20)
                end
                GameTooltip_Hide()
            end)

            table.insert(self.QueueRows, row)
            created = created + 1
        end
        return created
    end

    function this:SetQueueData(entries)
        entries = entries or {}
        local h = self.QueueListFrame:GetHeight() or 0
        local maxRows = math.max(1, math.floor(h / self.QueueRowHeight))
        local toShow = math.min(#entries, maxRows)
        self:EnsureQueueRows(toShow)
        for _, r in ipairs(self.QueueRows) do r:Hide(); r._element = nil end
        for i = 1, toShow do
            local row = self.QueueRows[i]
            local element = entries[i]
            row._element = element
            row._isActive = element.isPlaying
            row:Show()
            local label = element.label or "Unknown"
            row._fullText = label
            -- Apply coloring
            if element.isPlaying then
                row.text:SetTextColor(0.2, 1.0, 0.2)
            else
                row.text:SetTextColor(0.95, 0.86, 0.20)
            end
            -- Only update text/fit if content or available width changed
            local avail = self:GetRowTextAvailableWidth(row)
            if row._lastLabel ~= label or row._lastAvail ~= avail then
                row.text:SetText(label)
                if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end
                self:FitRowText(row)
                row._lastLabel = label
                row._lastAvail = avail
            end
            if row.bulletTex then row.bulletTex:Show() end
        end
    end

    -- Backwards compat naming so other code can Hide/Show this container
    self.QueueScrollBox = self.QueueListFrame
    self.QueueScrollBar = nil
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

        -- If collapsed, keep header-only layout and skip further content layout
        if this.CollapseButton and this.CollapseButton._collapsed then
            if this.ModelContainer then this.ModelContainer:Hide() end
            if this.NpcModelFrame then this.NpcModelFrame:Hide() end
            if this.ContentFrame then
                this.ContentFrame:ClearAllPoints()
                this.ContentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
                this.ContentFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
                this.ContentFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 5)
            end
            if this.HeaderDivider then this.HeaderDivider:Hide() end
            if this.QueueScrollBox then this.QueueScrollBox:Hide() end
            if this.QueueScrollBar then this.QueueScrollBar:Hide() end
            -- Only scale header font and exit
            if this.HeaderText then
                local headerFontSize = math.max(10, math.min(20, math.floor((height) / 8)))
                local scale = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.queueTextScale) or 1.0
                this.HeaderText:SetFont("Fonts\\FRIZQT__.TTF", headerFontSize * scale, "")
            end
            if this.SaveSizeForActiveLayout then this:SaveSizeForActiveLayout() end
            return
        end

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
            -- Measure actual header width (anchored between left edge and buttons)
            if this.TruncateToWidth and this.HeaderText.GetWidth then
                local maxW = math.max(40, self.HeaderText:GetWidth() or 0)
                this:TruncateToWidth(this.HeaderText, this.HeaderText:GetText() or "", maxW)
            end
        end
        
        if this.ApplyQueueTextScale then this:ApplyQueueTextScale() end

    -- Recompute visible rows for manual list using centralized provider
    if this.RefreshQueueDataProvider then this:RefreshQueueDataProvider() end
        
        if this.SaveSizeForActiveLayout then this:SaveSizeForActiveLayout() end
    end)
end
