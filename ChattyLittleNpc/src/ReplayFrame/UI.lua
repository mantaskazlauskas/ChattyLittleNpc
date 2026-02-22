---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local IconAtlas = CLN.IconAtlas

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
    -- Background should be click-through outside Edit Mode; interactive children handle their own mouse
    frame:EnableMouse(false)
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

    -- Tooltip on hover: addon name + click to edit hint
    frame:HookScript("OnEnter", function(f)
        if not GameTooltip or not GameTooltip.SetOwner then return end
        GameTooltip:SetOwner(f, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Chatty Little NPC", 1,1,1)
        GameTooltip:AddLine("Click to Edit", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        if GameTooltip and GameTooltip:IsShown() then GameTooltip:Hide() end
    end)

    -- Build UI parts
    self:CreateContentFrame()
    self:InitializeModelContainer()
    self:CreateResizeGrip()
    self:SetupFrameResize()

    -- Initialize state machine (idempotent)
    if self.InitStateMachine then self:InitStateMachine() end

    -- Position after components exist
    if self.LoadFramePosition then self:LoadFramePosition() end
    
    -- Apply frame scale if set
    if CLN.db and CLN.db.profile and CLN.db.profile.frameScale then
        frame:SetScale(CLN.db.profile.frameScale)
    end

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
    -- Portrait / brand icon placeholder via atlas
    if IconAtlas then
        tex:SetTexture(IconAtlas:Get(IconAtlas.keys.portrait))
    else
        tex:SetTexture("Interface/Icons/Ability_Warrior_BattleShout")
    end
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
    self.npcModelFrameHeight = (CLN.db and CLN.db.profile and CLN.db.profile.npcModelFrameHeight) or 140

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

    -- Queue count badge (hidden when <=1 queued)
    local badge = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetPoint("LEFT", header, "RIGHT", 8, -1)
    badge:SetTextColor(0.9, 0.9, 0.9)
    badge:Hide()
    self.QueueBadge = badge
    badge:SetText("[0]")
    badge:SetScript("OnEnter", function(f)
        if not GameTooltip or not GameTooltip.SetOwner then return end
        GameTooltip:SetOwner(f, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        local q = CLN.questsQueue and #CLN.questsQueue or 0
        GameTooltip:AddLine("Queued Quests", 1,1,1)
        GameTooltip:AddLine("Total queued quest phases: " .. q, 0.85,0.85,0.85)
        if q == 0 then
            GameTooltip:AddLine("No pending quest audio.", 0.7,0.7,0.7)
        end
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip:IsShown() then GameTooltip:Hide() end
    end)
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
            local capturedText = full
            C_Timer.After(0, function()
                if row and row:IsShown() and row._fullText == capturedText then self:FitRowText(row) end
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

-- Update queue badge reflecting total queued quests (excluding currently playing)
function ReplayFrame:UpdateQueueBadge()
    if not self.QueueBadge then return end
    local q = CLN.questsQueue and #CLN.questsQueue or 0
    if q > 1 then
        self.QueueBadge:SetText("[" .. tostring(q) .. "]")
        self.QueueBadge:Show()
    elseif q == 1 then
        -- Show only if the single item is not the one currently playing (rare race condition)
        local cp = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
        local queued = CLN.questsQueue[1]
        if queued and cp and (queued.questId ~= cp.questId or queued.phase ~= cp.phase) then
            self.QueueBadge:SetText("[1]")
            self.QueueBadge:Show()
        else
            self.QueueBadge:Hide()
        end
    else
        self.QueueBadge:Hide()
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
            collapseBtn.tex:SetTexture(IconAtlas and IconAtlas:Get(IconAtlas.keys.expand) or "Interface/Buttons/UI-Panel-ExpandButton-Up") -- down chevron (expanded)
        else
            collapseBtn.tex:SetTexture(IconAtlas and IconAtlas:Get(IconAtlas.keys.collapse) or "Interface/Buttons/UI-Panel-CollapseButton-Up") -- right chevron (collapsed)
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
    clearTex:SetTexture(IconAtlas and IconAtlas:Get(IconAtlas.keys.clear) or "Interface/Buttons/UI-GroupLoot-Pass-Up")
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
    optionsTex:SetTexture(IconAtlas and IconAtlas:Get(IconAtlas.keys.options) or "Interface/Buttons/UI-OptionsButton")
    optionsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Open Chatty Little NPC options")
        GameTooltip:Show()
    end)
    optionsBtn:SetScript("OnLeave", function() GameTooltip_Hide() end)
    optionsBtn:SetScript("OnClick", function()
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
        GameTooltip:SetText(ReplayFrame._editMode and "Exit Edit Mode" or "Enter Edit Mode (move/resize)")
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

-- =============================================
-- Compact Badge (Collapsed Mode) Implementation
-- =============================================
function ReplayFrame:EnsureCompactBadge()
    if self.CompactBadge then return end
    if not self.DisplayFrame then return end
    local badge = CreateFrame("Frame", nil, self.DisplayFrame, "BackdropTemplate")
    badge:SetPoint("TOPLEFT", self.DisplayFrame, "TOPLEFT", 6, -6)
    badge:SetPoint("TOPRIGHT", self.DisplayFrame, "TOPRIGHT", -30, -6) -- leave space for collapse button
    badge:SetHeight(44)
    badge:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 10, insets={left=3,right=3,top=3,bottom=3} })
    badge:SetBackdropColor(0,0,0,0.55)
    badge:SetBackdropBorderColor(0.9,0.7,0.2,0.85)
    badge:Hide()

    -- Row 1: status icon + title
    local icon = badge:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", badge, "LEFT", 6, 0)
    icon:SetSize(18,18)
    icon:SetTexture(IconAtlas and IconAtlas:Get(IconAtlas.keys.speaker) or "Interface/COMMON/VOICECHAT-SPEAKER")
    badge.Icon = icon
    local titleFS = badge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFS:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    titleFS:SetPoint("RIGHT", badge, "RIGHT", -6, 0)
    titleFS:SetJustifyH("LEFT")
    if titleFS.SetWordWrap then titleFS:SetWordWrap(false) end
    titleFS:SetTextColor(1.0, 0.95, 0.7)
    badge.Title = titleFS

    -- Row 2: controls container
    local controls = CreateFrame("Frame", nil, badge)
    controls:SetPoint("TOPLEFT", badge, "BOTTOMLEFT", 0, -2)
    controls:SetPoint("TOPRIGHT", badge, "BOTTOMRIGHT", 0, -2)
    controls:SetHeight(20)
    badge.Controls = controls

    local function makeBtn(texPath, tooltip, onClick)
        local b = CreateFrame("Button", nil, controls)
        b:SetSize(18,18)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture(texPath)
        b.tex = t
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines(); GameTooltip:AddLine(tooltip,1,1,1); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip_Hide() end)
        b:SetScript("OnClick", onClick)
        return b
    end

    -- Play/Stop button
    local playBtn = makeBtn("Interface/Buttons/UI-SpellbookIcon-NextPage-Up", "Stop current playback", function()
        if CLN and CLN.VoiceoverPlayer then CLN.VoiceoverPlayer:ForceStopCurrentSound(false) end
        if self.UpdateCompactBadge then self:UpdateCompactBadge(true) end
    end)
    playBtn:SetPoint("LEFT", controls, "LEFT", 4, 0)
    badge.PlayBtn = playBtn

    -- Clear queue button
    local clearBtn = makeBtn("Interface/Buttons/UI-GroupLoot-Pass-Up", "Clear queued quests", function()
        CLN.questsQueue = {}
        if self.MarkQueueDirty then self:MarkQueueDirty() end
        if self.UpdateCompactBadge then self:UpdateCompactBadge(true) end
    end)
    clearBtn:SetPoint("LEFT", playBtn, "RIGHT", 6, 0)
    badge.ClearBtn = clearBtn

    -- Expand button (mirrors collapse button state toggle)
    local expandBtn = makeBtn("Interface/Buttons/UI-Panel-ExpandButton-Up", "Expand full panel", function()
        if self.CollapseButton then self.CollapseButton:Click() end
    end)
    expandBtn:SetPoint("LEFT", clearBtn, "RIGHT", 6, 0)
    badge.ExpandBtn = expandBtn

    -- Queue count display
    local qfs = controls:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qfs:SetPoint("LEFT", expandBtn, "RIGHT", 10, 0)
    qfs:SetPoint("RIGHT", controls, "RIGHT", -6, 0)
    qfs:SetJustifyH("RIGHT")
    badge.QueueCount = qfs

    self.CompactBadge = badge
end

function ReplayFrame:UpdateCompactBadge(force)
    if not (self.CollapseButton and self.CollapseButton._collapsed) then return end
    if not self.CompactBadge then return end
    local badge = self.CompactBadge
    -- Ensure text reflects currently playing or first queued
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
    local playing = cur and cur.isPlaying and cur:isPlaying() or false
    local title = cur and cur.title or nil
    if (not title or title == "") and CLN.questsQueue and #CLN.questsQueue > 0 then
        local q = CLN.questsQueue[1]
        title = q and q.title or "Queued Quest"
    end
    if not title then title = "Idle" end
    -- Truncate to ~32 chars
    if #title > 32 then title = string.sub(title,1,29).."..." end
    badge.Title:SetText(title)
    -- Icon state (speaker vs mute)
    if playing then
        badge.Icon:SetVertexColor(1,1,1,1)
    else
        badge.Icon:SetVertexColor(0.5,0.5,0.5,0.8)
    end
    local qcount = (CLN.questsQueue and #CLN.questsQueue or 0)
    if qcount > 0 then
        badge.QueueCount:SetText("Queue: "..qcount)
    else
        badge.QueueCount:SetText("")
    end
end

-- =============================================================
-- Animated collapse / expand (fade + subtle scale) for badge UI
-- =============================================================
function ReplayFrame:ApplyImmediateCollapseState(collapsed)
    -- Fallback non-animated logic (mirrors prior behavior but refactored)
    if not self.DisplayFrame then return end
    self:EnsureCompactBadge()
    local frame = self.DisplayFrame
    if collapsed then
        if frame and frame.GetHeight then self._preCollapseHeight = frame:GetHeight() end
        if self.HeaderText then self.HeaderText:Hide() end
        if self.HeaderDivider then self.HeaderDivider:Hide() end
        if self.QueueScrollBox then self.QueueScrollBox:Hide() end
        if self.ModelContainer then self.ModelContainer:Hide() end
        if self.NpcModelFrame then self.NpcModelFrame:Hide() end
        if self.ContentFrame then self.ContentFrame:Hide() end
        if self.CompactBadge then self.CompactBadge:Show() end
        if self.UpdateCompactBadge then self:UpdateCompactBadge(true) end
        if frame and frame.SetHeight then frame:SetHeight(56) end
    else
        if self.HeaderText then self.HeaderText:Show() end
        if self.HeaderDivider then self.HeaderDivider:Show() end
        if self.ContentFrame then self.ContentFrame:Show() end
        if self.QueueScrollBox then self.QueueScrollBox:Show() end
        if self.ModelContainer and self._hasValidModel then self.ModelContainer:Show() end
        if self.CompactBadge then self.CompactBadge:Hide() end
        if frame and frame.SetHeight and self._preCollapseHeight then frame:SetHeight(self._preCollapseHeight) end
    end
    if self.UpdateDisplayFrame then self:UpdateDisplayFrame() end
    if self.Relayout then self:Relayout() end
end

function ReplayFrame:AnimateCollapseTransition(collapsed)
    if self._animatingCollapse then return end
    self:EnsureCompactBadge()
    if not self.DisplayFrame then return end
    -- Cancel any prior OnUpdate
    if self._collapseAnimFrame and self._collapseAnimFrame.SetScript then
        self._collapseAnimFrame:SetScript("OnUpdate", nil)
    end
    local frame = self.DisplayFrame
    local dur = 0.18
    local elapsed = 0
    local startH = frame:GetHeight() or 0
    if collapsed and frame.GetHeight then self._preCollapseHeight = startH end
    local endH = collapsed and 56 or (self._preCollapseHeight or startH)
    local contentFrames = { self.HeaderText, self.HeaderDivider, self.QueueScrollBox, (self.ModelContainer or self.NpcModelFrame) }
    local badge = self.CompactBadge
    if collapsed then
        -- Prepare badge
        if badge then
            badge:Show(); badge:SetAlpha(0); badge:SetScale(0.90)
            if self.UpdateCompactBadge then self:UpdateCompactBadge(true) end
        end
    else
        -- Prepare content to fade back in
        for _, f in ipairs(contentFrames) do if f and f.Show then f:Show(); if f.SetAlpha then f:SetAlpha(0) end end end
        if badge then badge:SetAlpha(1); badge:SetScale(1.0) end
    end
    self._animatingCollapse = true
    local animFrame = self._collapseAnimFrame or CreateFrame("Frame")
    self._collapseAnimFrame = animFrame
    animFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        local t = math.min(1, elapsed / dur)
        -- Ease (smoothstep)
        local ease = t * t * (3 - 2 * t)
        local inv = 1 - ease
        -- Height interpolation
        local h = startH + (endH - startH) * ease
        if frame and frame.SetHeight then frame:SetHeight(h) end
        if collapsed then
            -- Fade out content, fade/scale in badge
            for _, f in ipairs(contentFrames) do if f and f.SetAlpha then f:SetAlpha(inv) end end
            if badge then badge:SetAlpha(ease); badge:SetScale(0.90 + 0.10 * ease) end
        else
            -- Expanding
            for _, f in ipairs(contentFrames) do if f and f.SetAlpha then f:SetAlpha(ease) end end
            if badge then badge:SetAlpha(inv); badge:SetScale(0.90 + 0.10 * inv) end
        end
        if t >= 1 then
            animFrame:SetScript("OnUpdate", nil)
            -- Finalize visibility
            if collapsed then
                for _, f in ipairs(contentFrames) do if f and f.Hide then f:Hide() end end
                if badge then badge:SetAlpha(1); badge:SetScale(1.0) end
            else
                if badge then badge:Hide() end
                for _, f in ipairs(contentFrames) do if f and f.Show then f:Show(); if f.SetAlpha then f:SetAlpha(1) end end end
            end
            self._animatingCollapse = false
            if self.UpdateDisplayFrame then self:UpdateDisplayFrame() end
            if self.Relayout then self:Relayout() end
        end
    end)
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
    self.LockButton._tex:SetTexture(IconAtlas and IconAtlas:Get(IconAtlas.keys.lock) or "Interface/Buttons/LockButton-Locked")
    else
    self.LockButton._tex:SetTexture(IconAtlas and IconAtlas:Get(IconAtlas.keys.unlock) or "Interface/Buttons/LockButton-Unlocked")
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
            local h = frame._animStartH + (frame._animEndH - frame._animStartH) * t
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
                        -- Play each queued quest entry directly using VoiceoverPlayer
                        for _, q in ipairs(toPlay) do
                            if q and q.questId and q.phase and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.PlayQuestSound then
                                if CLN.Logger then
                                    CLN.Logger:debug("ReplayFrame queue manual play: " .. tostring(q.questId) .. " (" .. tostring(q.phase) .. ")", false, (CLN.Utils and CLN.Utils.LogCategories.loader) or 'misc')
                                end
                                CLN.VoiceoverPlayer:PlayQuestSound(q.questId, q.phase, q.npcId)
                            else
                                if CLN.Logger then
                                    CLN.Logger:warn("Skipped queued quest entry (missing data or player)", false, (CLN.Utils and CLN.Utils.LogCategories.loader) or 'misc')
                                end
                            end
                        end
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
