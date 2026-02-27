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
    if defaultH < 80 then defaultH = 165 end
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

    -- Edit mode glow overlay (hidden until edit mode activates)
    local glow = frame:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
    glow:SetTexture("Interface/Buttons/UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1.0, 0.82, 0.0, 0)
    glow:Hide()
    self.EditGlow = glow

    return frame
end

function ReplayFrame:StartEditGlowPulse()
    if not self.EditGlow then return end
    local enabled = CLN and CLN.db and CLN.db.profile and CLN.db.profile.editModeGlowHints
    if not enabled then return end
    -- Check if already shown enough times
    local profile = CLN and CLN.db and CLN.db.profile
    if profile and profile._glowHintShown then return end

    self.EditGlow:Show()
    self._glowPulseCount = 0
    local maxCycles = 3

    if not self._glowAnimGroup then
        local ag = self.EditGlow:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(0.4)
        fadeIn:SetDuration(1.0)
        fadeIn:SetOrder(1)
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(0.4)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(1.0)
        fadeOut:SetOrder(2)
        ag:SetLooping("REPEAT")
        ag:SetScript("OnLoop", function()
            self._glowPulseCount = (self._glowPulseCount or 0) + 1
            if self._glowPulseCount >= maxCycles then
                ag:Stop()
                self.EditGlow:Hide()
                -- Mark as shown in profile
                if CLN and CLN.db and CLN.db.profile then
                    CLN.db.profile._glowHintShown = true
                end
            end
        end)
        self._glowAnimGroup = ag
    end

    self._glowPulseCount = 0
    self._glowAnimGroup:Play()
end

function ReplayFrame:StopEditGlowPulse()
    if self._glowAnimGroup then self._glowAnimGroup:Stop() end
    if self.EditGlow then self.EditGlow:Hide() end
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
        modelContainer:SetClipsChildren(true)
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
    if header.SetJustifyH then header:SetJustifyH("LEFT") end
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

    -- Progress bar: 2px gold texture below divider (indeterminate shimmer)
    local progressBar = contentFrame:CreateTexture(nil, "ARTWORK")
    progressBar:SetColorTexture(1.0, 0.82, 0.0, 0.7)
    progressBar:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -1)
    progressBar:SetHeight(2)
    progressBar:SetWidth(0)
    progressBar:Hide()
    self.ProgressBar = progressBar

    -- Shimmer overlay for indeterminate progress
    local shimmer = contentFrame:CreateTexture(nil, "OVERLAY")
    shimmer:SetColorTexture(1.0, 1.0, 0.8, 0.4)
    shimmer:SetPoint("TOPLEFT", progressBar, "TOPLEFT", 0, 0)
    shimmer:SetHeight(2)
    shimmer:SetWidth(30)
    shimmer:Hide()
    self.ProgressShimmer = shimmer

    -- Subtitle display: shows current dialogue text below model area
    local subtitleBg = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
    subtitleBg:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    subtitleBg:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -4, -4)
    subtitleBg:SetHeight(36)
    subtitleBg:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    subtitleBg:SetBackdropColor(0, 0, 0, 0.5)
    subtitleBg:SetFrameLevel((contentFrame.GetFrameLevel and contentFrame:GetFrameLevel() or 0) + 5)
    subtitleBg:Hide()
    self.SubtitleFrame = subtitleBg

    local subtitleText = subtitleBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitleText:SetPoint("TOPLEFT", subtitleBg, "TOPLEFT", 8, -6)
    subtitleText:SetPoint("BOTTOMRIGHT", subtitleBg, "BOTTOMRIGHT", -8, 4)
    subtitleText:SetJustifyH("CENTER")
    subtitleText:SetJustifyV("MIDDLE")
    if subtitleText.SetWordWrap then subtitleText:SetWordWrap(true) end
    subtitleText:SetTextColor(1.0, 1.0, 1.0, 0.95)
    self.SubtitleText = subtitleText

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

function ReplayFrame:ShowSubtitle(text)
    local enabled = CLN and CLN.db and CLN.db.profile and CLN.db.profile.showSubtitles
    if not enabled or not self.SubtitleFrame or not self.SubtitleText then return end
    -- Cancel any existing subtitle timer
    self:HideSubtitle()
    if not text or text == "" then return end

    local fontScale = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.subtitleFontScale) or 1.0
    self.SubtitleText:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, math.floor(12 * fontScale)), "")

    -- Split into sentences and reveal one at a time
    local sentences = self.SplitTooltipIntoSentences and self:SplitTooltipIntoSentences(text) or { text }
    self._subtitleSentences = sentences
    self._subtitleIndex = 0
    -- Generation token: prevents stale C_Timer callbacks from a prior
    -- ShowSubtitle call from corrupting the new subtitle sequence.
    self._subtitleToken = (self._subtitleToken or 0) + 1
    local token = self._subtitleToken
    self.SubtitleFrame:Show()
    self.SubtitleFrame:SetAlpha(0)
    -- Push header below subtitle to avoid overlap
    if self.HeaderText then
        self.HeaderText:ClearAllPoints()
        self.HeaderText:SetPoint("TOPLEFT", self.SubtitleFrame, "BOTTOMLEFT", 6, -4)
    end
    if self.AnchorHeaderToButtons then self:AnchorHeaderToButtons() end

    local function showNext()
        if token ~= self._subtitleToken then return end
        if not self.SubtitleFrame or not self.SubtitleFrame:IsShown() then return end
        self._subtitleIndex = (self._subtitleIndex or 0) + 1
        local idx = self._subtitleIndex
        if idx > #sentences then
            -- All sentences shown; hide visuals after a pause but keep
            -- _subtitleSentences non-nil so UpdateAnimationsIfNeeded
            -- won't re-trigger the same text while the voiceover plays.
            self._subtitleTimer = C_Timer and C_Timer.After(2.0, function()
                if token ~= self._subtitleToken then return end
                self._subtitleTimer = nil
                if self.SubtitleFrame then self.SubtitleFrame:Hide() end
                -- Restore header to original position
                if self.HeaderText and self.ContentFrame then
                    self.HeaderText:ClearAllPoints()
                    self.HeaderText:SetPoint("TOPLEFT", self.ContentFrame, "TOPLEFT", 10, -6)
                end
                if self.AnchorHeaderToButtons then self:AnchorHeaderToButtons() end
            end)
            return
        end
        self.SubtitleText:SetText(sentences[idx])
        self.SubtitleFrame:SetAlpha(1)
        -- Duration scales with sentence length: ~0.07s per character, clamped 1.5–5s
        local dur = math.max(1.5, math.min(5.0, #sentences[idx] * 0.07))
        self._subtitleTimer = C_Timer and C_Timer.After(dur, showNext)
    end

    -- Start first sentence after a brief fade-in delay
    self._subtitleTimer = C_Timer and C_Timer.After(0.3, showNext)
end

function ReplayFrame:HideSubtitle()
    -- Invalidate any in-flight timer callbacks via generation token
    self._subtitleToken = (self._subtitleToken or 0) + 1
    self._subtitleTimer = nil
    self._subtitleSentences = nil
    self._subtitleIndex = nil
    if self.SubtitleFrame then self.SubtitleFrame:Hide() end
    -- Restore header to original position
    if self.HeaderText and self.ContentFrame then
        self.HeaderText:ClearAllPoints()
        self.HeaderText:SetPoint("TOPLEFT", self.ContentFrame, "TOPLEFT", 10, -6)
    end
    if self.AnchorHeaderToButtons then self:AnchorHeaderToButtons() end
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
    -- Only set the RIGHT anchor; preserve existing TOPLEFT (may be relative to SubtitleFrame)
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
                if frame and frame.GetHeight then
                    local curH = frame:GetHeight()
                    if curH >= 80 then this._preCollapseHeight = curH end
                end
                if this.HideSubtitle then this:HideSubtitle() end
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
                if frame and frame.SetHeight then frame:SetHeight(this:GetSafeExpandHeight()) end
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
    badge:SetPoint("TOPLEFT", self.DisplayFrame, "TOPLEFT", 4, -4)
    badge:SetPoint("TOPRIGHT", self.DisplayFrame, "TOPRIGHT", -4, -4)
    badge:SetHeight(44)
    badge:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    badge:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
    badge:SetBackdropBorderColor(0.25, 0.22, 0.20, 0.6)
    badge:Hide()

    -- Left: speaker icon with glow ring for active playback
    local iconFrame = CreateFrame("Frame", nil, badge)
    iconFrame:SetSize(28, 28)
    iconFrame:SetPoint("LEFT", badge, "LEFT", 8, 0)
    local iconGlow = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconGlow:SetPoint("CENTER")
    iconGlow:SetSize(32, 32)
    iconGlow:SetTexture("Interface/Buttons/UI-ActionButton-Border")
    iconGlow:SetBlendMode("ADD")
    iconGlow:SetVertexColor(1.0, 0.82, 0.0, 0)
    iconGlow:Hide()
    badge.IconGlow = iconGlow
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(20, 20)
    icon:SetTexture(IconAtlas and IconAtlas:Get(IconAtlas.keys.speaker) or "Interface/COMMON/VOICECHAT-SPEAKER")
    badge.Icon = icon

    -- Title text (prominent, white on dark)
    local titleFS = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
    titleFS:SetPoint("RIGHT", badge, "RIGHT", -90, 0)
    titleFS:SetJustifyH("LEFT")
    if titleFS.SetWordWrap then titleFS:SetWordWrap(false) end
    titleFS:SetTextColor(1.0, 1.0, 1.0, 0.95)
    badge.Title = titleFS

    -- Right-side controls (inline, inside the badge)
    local function makeBtn(parent, size, texPath, tooltip, onClick)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(size, size)
        -- Subtle background circle
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("CENTER")
        bg:SetSize(size + 4, size + 4)
        bg:SetTexture("Interface/Tooltips/UI-Tooltip-Background")
        bg:SetVertexColor(1, 1, 1, 0.12)
        b.bg = bg
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetPoint("CENTER")
        t:SetSize(size - 4, size - 4)
        t:SetTexture(texPath)
        b.tex = t
        b:SetScript("OnEnter", function(self)
            self.bg:SetVertexColor(1, 1, 1, 0.25)
            if GameTooltip and GameTooltip.SetOwner then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines(); GameTooltip:AddLine(tooltip, 1, 1, 1); GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(self)
            self.bg:SetVertexColor(1, 1, 1, 0.12)
            if GameTooltip_Hide then GameTooltip_Hide() end
        end)
        b:SetScript("OnClick", onClick)
        return b
    end

    -- Stop button
    local stopBtn = makeBtn(badge, 22, "Interface/Buttons/UI-GroupLoot-Pass-Up", "Stop playback", function()
        if CLN and CLN.VoiceoverPlayer then CLN.VoiceoverPlayer:ForceStopCurrentSound(false, true) end
        if self.UpdateCompactBadge then self:UpdateCompactBadge(true) end
    end)
    stopBtn:SetPoint("RIGHT", badge, "RIGHT", -38, 0)
    badge.PlayBtn = stopBtn

    -- Pause/Resume button
    local pauseBtn = makeBtn(badge, 22, "Interface/TimeManager/PauseButton", "Pause playback", function()
        if CLN and CLN.VoiceoverPlayer then CLN.VoiceoverPlayer:TogglePause() end
    end)
    pauseBtn:SetPoint("RIGHT", stopBtn, "LEFT", -4, 0)
    -- Override tooltip to be dynamic (pause/resume)
    pauseBtn:SetScript("OnEnter", function(btn)
        btn.bg:SetVertexColor(1, 1, 1, 0.25)
        if GameTooltip and GameTooltip.SetOwner then
            local paused = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer:IsPaused()
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(paused and "Resume playback" or "Pause playback", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    badge.PauseBtn = pauseBtn

    -- Expand button
    local expandBtn = makeBtn(badge, 22, "Interface/Buttons/UI-Panel-ExpandButton-Up", "Expand", function()
        if self.CollapseButton then self.CollapseButton:Click() end
    end)
    expandBtn:SetPoint("RIGHT", badge, "RIGHT", -10, 0)
    badge.ExpandBtn = expandBtn

    -- Queue count badge (small pill, between title and buttons)
    local queuePill = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    queuePill:SetPoint("RIGHT", pauseBtn, "LEFT", -8, 0)
    queuePill:SetJustifyH("RIGHT")
    queuePill:SetTextColor(0.75, 0.75, 0.75, 0.9)
    badge.QueueCount = queuePill

    -- Bottom progress line (thin gold bar)
    local progressLine = badge:CreateTexture(nil, "OVERLAY")
    progressLine:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT", 3, 2)
    progressLine:SetHeight(2)
    progressLine:SetWidth(0)
    progressLine:SetColorTexture(1.0, 0.82, 0.0, 0.8)
    progressLine:Hide()
    badge.ProgressLine = progressLine

    -- Speaker glow pulse animation
    local glowAG = iconGlow:CreateAnimationGroup()
    glowAG:SetLooping("REPEAT")
    local fadeIn = glowAG:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(0.35)
    fadeIn:SetDuration(0.8)
    fadeIn:SetOrder(1)
    local fadeOut = glowAG:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(0.35)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.8)
    fadeOut:SetOrder(2)
    badge.GlowAnim = glowAG

    badge:SetScript("OnSizeChanged", function()
        if self.UpdateCompactBadge then self:UpdateCompactBadge(true) end
    end)

    self.CompactBadge = badge
end

function ReplayFrame:UpdatePauseButton()
    local badge = self.CompactBadge
    if badge and badge.PauseBtn then
        local paused = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer:IsPaused()
        local tex = badge.PauseBtn.tex
        if tex then
            if paused then
                tex:SetTexture("Interface/Buttons/UI-SpellbookIcon-NextPage-Up")
            else
                tex:SetTexture("Interface/TimeManager/PauseButton")
            end
        end
    end
end

function ReplayFrame:UpdateCompactBadge(force)
    if not (self.CollapseButton and self.CollapseButton._collapsed) then return end
    if not self.CompactBadge then return end
    local badge = self.CompactBadge
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
    local playing = cur and cur.isPlaying and cur:isPlaying() or false
    local title = cur and cur.title or nil
    if (not title or title == "") and CLN.questsQueue and #CLN.questsQueue > 0 then
        local q = CLN.questsQueue[1]
        title = q and q.title or "Queued Quest"
    end
    if not title then title = "Chatty Little NPC" end

    -- Title with queue count prefix when items are queued
    local qcount = (CLN.questsQueue and #CLN.questsQueue or 0)
    local displayTitle = title
    if qcount > 0 then
        badge.QueueCount:SetText("|cff8080a0" .. qcount .. " queued|r")
    else
        badge.QueueCount:SetText("")
    end

    -- Truncate title to fit
    if self.TruncateToWidth and badge.Title.GetWidth then
        local maxW = math.max(40, (badge:GetWidth() or 200) - 140)
        self:TruncateToWidth(badge.Title, displayTitle, maxW)
    else
        badge.Title:SetText(displayTitle)
    end

    -- Speaker icon and glow state
    if playing then
        badge.Icon:SetVertexColor(1.0, 0.82, 0.0, 1)
        badge.Title:SetTextColor(1.0, 1.0, 1.0, 0.95)
        if badge.IconGlow then
            badge.IconGlow:Show()
            if badge.GlowAnim and not badge.GlowAnim:IsPlaying() then badge.GlowAnim:Play() end
        end
        -- Show progress line
        if badge.ProgressLine then
            local maxW = math.max(1, (badge:GetWidth() or 200) - 6)
            badge.ProgressLine:SetWidth(maxW)
            badge.ProgressLine:Show()
        end
    else
        badge.Icon:SetVertexColor(0.5, 0.5, 0.5, 0.6)
        badge.Title:SetTextColor(0.7, 0.7, 0.7, 0.8)
        if badge.GlowAnim and badge.GlowAnim:IsPlaying() then badge.GlowAnim:Stop() end
        if badge.IconGlow then badge.IconGlow:Hide() end
        if badge.ProgressLine then badge.ProgressLine:Hide() end
    end
end

function ReplayFrame:UpdateProgressBar()
    if not self.ProgressBar then return end
    local enabled = CLN and CLN.db and CLN.db.profile and CLN.db.profile.showProgressBar
    if not enabled then
        self.ProgressBar:Hide()
        if self.ProgressShimmer then self.ProgressShimmer:Hide() end
        return
    end
    local playing = self:IsVoiceoverCurrenltyPlaying()
    if playing then
        -- Show progress bar at full width of divider
        local maxW = 0
        if self.HeaderDivider and self.HeaderDivider.GetWidth then
            maxW = self.HeaderDivider:GetWidth() or 200
        end
        self.ProgressBar:SetWidth(maxW)
        self.ProgressBar:Show()
        -- Animate shimmer
        if self.ProgressShimmer then
            self.ProgressShimmer:Show()
            -- Simple shimmer: move shimmer across the bar using time
            local t = GetTime and GetTime() or 0
            local cycle = (t % 2) / 2 -- 0..1 over 2 seconds
            local shimmerX = cycle * math.max(1, maxW - 30)
            self.ProgressShimmer:ClearAllPoints()
            self.ProgressShimmer:SetPoint("TOPLEFT", self.ProgressBar, "TOPLEFT", shimmerX, 0)
        end
    else
        self.ProgressBar:Hide()
        if self.ProgressShimmer then self.ProgressShimmer:Hide() end
    end
end

-- =============================================================
-- Animated collapse / expand (fade + subtle scale) for badge UI
-- =============================================================

-- Safe fallback height when _preCollapseHeight is nil (clamped to minimum expanded size)
function ReplayFrame:GetSafeExpandHeight()
    local h = self._preCollapseHeight
        or (CLN and CLN.db and CLN.db.profile and CLN.db.profile.frameSize and CLN.db.profile.frameSize.height)
        or 165
    -- Clamp: if the stored value is itself corrupted (collapsed), use the hard default
    if h < 80 then h = 165 end
    return h
end

function ReplayFrame:ApplyImmediateCollapseState(collapsed)
    -- Fallback non-animated logic (mirrors prior behavior but refactored)
    if not self.DisplayFrame then return end
    self:EnsureCompactBadge()
    local frame = self.DisplayFrame
    if collapsed then
        -- Only record pre-collapse height if the frame isn't already at a collapsed size
        if frame and frame.GetHeight then
            local curH = frame:GetHeight()
            if curH >= 80 then self._preCollapseHeight = curH end
        end
        if self.HideSubtitle then self:HideSubtitle() end
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
        if self.CompactBadge then
            self.CompactBadge:Hide()
            -- Stop glow animation when hiding badge
            if self.CompactBadge.GlowAnim and self.CompactBadge.GlowAnim:IsPlaying() then
                self.CompactBadge.GlowAnim:Stop()
            end
            if self.CompactBadge.IconGlow then self.CompactBadge.IconGlow:Hide() end
        end
        if frame and frame.SetHeight then frame:SetHeight(self:GetSafeExpandHeight()) end
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
    if collapsed and frame.GetHeight and startH >= 80 then self._preCollapseHeight = startH end
    local endH = collapsed and 56 or self:GetSafeExpandHeight()
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
                if self.HideSubtitle then self:HideSubtitle() end
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

    -- Record pre-collapse height if needed (skip if already at collapsed size)
    if collapse then
        local curH = frame.GetHeight and frame:GetHeight() or 0
        if curH >= 80 then self._preCollapseHeight = curH end
    end

    local startH = frame:GetHeight() or 0
    local endH = collapse and HeaderOnlyHeight() or self:GetSafeExpandHeight()
    if endH <= 0 then endH = 165 end

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
                    if self.HideSubtitle then self:HideSubtitle() end
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
        list:SetPoint("TOPRIGHT", self.HeaderDivider, "BOTTOMRIGHT", 2, -6)
    else
        list:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -36)
        list:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -8, -36)
    end
    list:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", 8, 8)
    self.QueueListFrame = list
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        this._scrollOffset = (this._scrollOffset or 0) - delta
        if this.RefreshQueueDataProvider then this:RefreshQueueDataProvider() end
    end)
    -- Thin scroll position indicator (right edge, only visible when content overflows)
    -- Use a Frame (not Texture) so it can receive mouse events for drag-to-scroll
    local scrollThumb = CreateFrame("Frame", nil, list)
    scrollThumb:SetWidth(6)
    scrollThumb:SetFrameStrata("HIGH")
    scrollThumb:EnableMouse(true)
    scrollThumb:SetMovable(true)
    scrollThumb:Hide()
    local scrollTex = scrollThumb:CreateTexture(nil, "ARTWORK")
    scrollTex:SetAllPoints()
    scrollTex:SetColorTexture(1.0, 0.82, 0.0, 0.4) -- gold, semi-transparent

    -- Widen hit area: hover brightens
    scrollThumb:SetScript("OnEnter", function(f)
        scrollTex:SetColorTexture(1.0, 0.82, 0.0, 0.7)
        f:SetWidth(6)
    end)
    scrollThumb:SetScript("OnLeave", function(f)
        if not f._dragging then
            scrollTex:SetColorTexture(1.0, 0.82, 0.0, 0.4)
            f:SetWidth(6)
        end
    end)

    -- Drag-to-scroll logic
    scrollThumb:SetScript("OnMouseDown", function(f, button)
        if button ~= "LeftButton" then return end
        f._dragging = true
        f._dragStartY = select(2, GetCursorPosition()) / (f:GetEffectiveScale() or 1)
        f._dragStartOffset = this._scrollOffset or 0
        scrollTex:SetColorTexture(1.0, 0.82, 0.0, 0.9)
    end)
    scrollThumb:SetScript("OnMouseUp", function(f, button)
        if button ~= "LeftButton" then return end
        f._dragging = false
        if f:IsMouseOver() then
            scrollTex:SetColorTexture(1.0, 0.82, 0.0, 0.7)
        else
            scrollTex:SetColorTexture(1.0, 0.82, 0.0, 0.4)
            f:SetWidth(6)
        end
    end)
    scrollThumb:SetScript("OnUpdate", function(f)
        if not f._dragging then return end
        local curY = select(2, GetCursorPosition()) / (f:GetEffectiveScale() or 1)
        local deltaY = f._dragStartY - curY -- negative = dragged down
        local listHeight = this.QueueListFrame and this.QueueListFrame:GetHeight() or 100
        local thumbHeight = f:GetHeight()
        local trackHeight = listHeight - thumbHeight
        if trackHeight <= 0 then return end
        local maxOffset = this._scrollMaxOffset or 0
        if maxOffset <= 0 then return end
        -- Map pixel delta to offset delta
        local offsetDelta = (deltaY / trackHeight) * maxOffset
        local newOffset = math.floor(f._dragStartOffset + offsetDelta + 0.5)
        newOffset = math.max(0, math.min(maxOffset, newOffset))
        if newOffset ~= (this._scrollOffset or 0) then
            this._scrollOffset = newOffset
            if this.RefreshQueueDataProvider then this:RefreshQueueDataProvider() end
        end
    end)

    self._scrollIndicator = scrollThumb
    self.QueueRowHeight = 24
    self.QueueRows = {}

    -- Keyboard navigation removed: was stealing Tab/focus during gameplay

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

            local typeIcon = row:CreateTexture(nil, "ARTWORK")
            typeIcon:SetPoint("LEFT", bulletTex, "RIGHT", 4, 0)
            typeIcon:SetSize(0.001, 14)
            typeIcon:Hide()
            row.typeIcon = typeIcon

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", typeIcon, "RIGHT", 4, 0)
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
                        -- Push to history before stopping so it's available for replay
                        local cp = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                        if cp and (cp.title or cp.questId) and ReplayFrame.PushHistory then
                            local title = cp.title
                            if not title and cp.questId then
                                title = CLN:GetTitleForQuestID(cp.questId)
                            end
                            ReplayFrame:PushHistory({
                                title = title,
                                npcId = cp.npcId,
                                questId = cp.questId,
                                phase = cp.phase,
                                entryType = cp.entryType or (cp.questId and "quest" or "unknown"),
                                gender = cp.gender,
                                completedAt = GetTime and GetTime() or 0,
                            })
                        end
                        CLN.VoiceoverPlayer:ForceStopCurrentSound(false, true)
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
                    elseif e.isHistory then
                        -- Replay from history: remove from history so it shows as current playback
                        if InCombatLockdown and InCombatLockdown() then return end
                        -- Remove by identity match (safe against stale indices)
                        if ReplayFrame._replayHistory then
                            for i = #ReplayFrame._replayHistory, 1, -1 do
                                local h = ReplayFrame._replayHistory[i]
                                if h.npcId == e.npcId and h.title == e.title
                                   and (h.questId or "") == (e.questId or "")
                                   and (h.phase or "") == (e.phase or "") then
                                    table.remove(ReplayFrame._replayHistory, i)
                                    break
                                end
                            end
                        end
                        if e.questId and e.phase and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.PlayQuestSound then
                            CLN.VoiceoverPlayer:PlayQuestSound(e.questId, e.phase, e.npcId)
                        elseif e.npcId and e.title and e.entryType and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.PlayNonQuestSound then
                            CLN.VoiceoverPlayer:PlayNonQuestSound(e.npcId, e.entryType, e.title, e.gender)
                        end
                        if ReplayFrame.MarkQueueDirty then ReplayFrame:MarkQueueDirty() end
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
                    GameTooltip:ClearLines()
                    -- Type badge prefix
                    local typeBadge = ""
                    local showBadges = CLN and CLN.db and CLN.db.profile and CLN.db.profile.showQuestTypeBadges
                    if showBadges then
                        if e.entryType == "quest" then
                            typeBadge = "|cFFFFD100[Quest]|r "
                        elseif e.entryType == "Gossip" then
                            typeBadge = "|cFF99CCFF[Gossip]|r "
                        elseif e.entryType == "GameObject" then
                            typeBadge = "|cFFD9C08C[Item]|r "
                        end
                    end
                    local lines = ReplayFrame.SplitTooltipIntoSentences and ReplayFrame:SplitTooltipIntoSentences(e.tooltip) or { e.tooltip }
                    for i, line in ipairs(lines) do
                        if i == 1 then
                            GameTooltip:AddLine(typeBadge .. line, 0.9, 0.9, 0.9, true)
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
                    local e = selfBtn._element
                    local showBadges = CLN and CLN.db and CLN.db.profile and CLN.db.profile.showQuestTypeBadges
                    if e and e.isHistory then
                        selfBtn.text:SetTextColor(0.5, 0.5, 0.5)
                    elseif showBadges and e and e.entryType == "Gossip" then
                        selfBtn.text:SetTextColor(0.6, 0.8, 1.0)
                    elseif showBadges and e and e.entryType == "GameObject" then
                        selfBtn.text:SetTextColor(0.85, 0.75, 0.55)
                    else
                        selfBtn.text:SetTextColor(0.95, 0.86, 0.20)
                    end
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
        for _, r in ipairs(self.QueueRows) do r:Hide(); r._element = nil; if r.bulletTex then r.bulletTex:Hide() end; if r.typeIcon then r.typeIcon:SetSize(0.001, 14); r.typeIcon:Hide() end end
        local showBadges = CLN and CLN.db and CLN.db.profile and CLN.db.profile.showQuestTypeBadges
        for i = 1, toShow do
            local row = self.QueueRows[i]
            local element = entries[i]
            row._element = element
            row._isActive = element.isPlaying
            row:Show()

            -- Divider row
            if element.isDivider then
                row.text:SetText(element.label or "— History —")
                row.text:SetTextColor(0.6, 0.5, 0.2)
                row._lastLabel = nil -- invalidate cache so recycled rows re-render
                row._lastAvail = nil
                if row.bulletTex then row.bulletTex:Hide() end
                if row.typeIcon then row.typeIcon:SetSize(0.001, 14); row.typeIcon:Hide() end
                row:EnableMouse(false)
            -- History row (greyed out with replay capability)
            elseif element.isHistory then
                local label = element.label or "Unknown"
                if self.GetAccessibilityBadge then
                    local badge = self:GetAccessibilityBadge(element.entryType)
                    if badge ~= "" then label = badge .. label end
                end
                row._fullText = label
                -- Use accessibility-aware coloring
                if self.GetRowColor then
                    row.text:SetTextColor(self:GetRowColor(element, showBadges))
                else
                    row.text:SetTextColor(0.5, 0.5, 0.5)
                end
                if row.bulletTex then
                    row.bulletTex:SetColorTexture(0.5, 0.5, 0.5, 0.5) -- dim bullet
                    row.bulletTex:Show()
                end
                -- Type icon for history
                if row.typeIcon then
                    if showBadges then
                        local iconAtlas = CLN and CLN.IconAtlas
                        if iconAtlas and element.entryType then
                            if element.entryType == "quest" then
                                row.typeIcon:SetTexture(iconAtlas:Get(iconAtlas.keys.questBang))
                                row.typeIcon:SetDesaturated(true)
                                row.typeIcon:SetSize(14, 14); row.typeIcon:Show()
                            elseif element.entryType == "Gossip" then
                                row.typeIcon:SetTexture(iconAtlas:Get(iconAtlas.keys.gossipBubble))
                                row.typeIcon:SetDesaturated(true)
                                row.typeIcon:SetSize(14, 14); row.typeIcon:Show()
                            elseif element.entryType == "GameObject" then
                                row.typeIcon:SetTexture(iconAtlas:Get(iconAtlas.keys.itemScroll))
                                row.typeIcon:SetDesaturated(true)
                                row.typeIcon:SetSize(14, 14); row.typeIcon:Show()
                            else
                                row.typeIcon:SetSize(0.001, 14); row.typeIcon:Hide()
                            end
                        else
                            row.typeIcon:SetSize(0.001, 14); row.typeIcon:Hide()
                        end
                    else
                        row.typeIcon:SetSize(0.001, 14); row.typeIcon:Hide()
                    end
                end
                row:EnableMouse(true)
                -- Update text
                local avail = self:GetRowTextAvailableWidth(row)
                if row._lastLabel ~= label or row._lastAvail ~= avail then
                    row.text:SetText(label)
                    self:FitRowText(row)
                    row._lastLabel = label
                    row._lastAvail = avail
                end
            -- Active/queued row (existing logic)
            else
                local label = element.label or "Unknown"
                -- Prepend accessibility badge in high-contrast mode
                if self.GetAccessibilityBadge then
                    local badge = self:GetAccessibilityBadge(element.entryType)
                    if badge ~= "" then label = badge .. label end
                end
                row._fullText = label
                row:EnableMouse(true)
                -- Apply coloring by type (accessibility-aware)
                if self.GetRowColor then
                    row.text:SetTextColor(self:GetRowColor(element, showBadges))
                elseif element.isPlaying then
                    row.text:SetTextColor(0.2, 1.0, 0.2)
                elseif showBadges and element.entryType == "quest" then
                    row.text:SetTextColor(1.0, 0.82, 0.0)
                elseif showBadges and element.entryType == "Gossip" then
                    row.text:SetTextColor(0.6, 0.8, 1.0)
                elseif showBadges and element.entryType == "GameObject" then
                    row.text:SetTextColor(0.85, 0.75, 0.55)
                else
                    row.text:SetTextColor(0.95, 0.86, 0.20)
                end
                -- Set type icon
                if row.typeIcon then
                    if showBadges then
                        local iconAtlas = CLN and CLN.IconAtlas
                        if iconAtlas and element.entryType then
                            if element.entryType == "quest" then
                                row.typeIcon:SetTexture(iconAtlas:Get(iconAtlas.keys.questBang))
                                row.typeIcon:SetDesaturated(false)
                                row.typeIcon:SetSize(14, 14); row.typeIcon:Show()
                            elseif element.entryType == "Gossip" then
                                row.typeIcon:SetTexture(iconAtlas:Get(iconAtlas.keys.gossipBubble))
                                row.typeIcon:SetDesaturated(false)
                                row.typeIcon:SetSize(14, 14); row.typeIcon:Show()
                            elseif element.entryType == "GameObject" then
                                row.typeIcon:SetTexture(iconAtlas:Get(iconAtlas.keys.itemScroll))
                                row.typeIcon:SetDesaturated(false)
                                row.typeIcon:SetSize(14, 14); row.typeIcon:Show()
                            else
                                row.typeIcon:SetSize(0.001, 14); row.typeIcon:Hide()
                            end
                        else
                            row.typeIcon:SetSize(0.001, 14); row.typeIcon:Hide()
                        end
                    else
                        row.typeIcon:SetSize(0.001, 14); row.typeIcon:Hide()
                    end
                end
                if row.bulletTex then
                    row.bulletTex:SetColorTexture(1.0, 0.82, 0.0, 0.9) -- restore gold bullet
                    row.bulletTex:Show()
                end
                local avail = self:GetRowTextAvailableWidth(row)
                if row._lastLabel ~= label or row._lastAvail ~= avail then
                    row.text:SetText(label)
                    if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end
                    self:FitRowText(row)
                    row._lastLabel = label
                    row._lastAvail = avail
                end
            end
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

        -- Layout the model area via extracted module
        if this.LayoutModelArea then this:LayoutModelArea(frame) end

        -- Ensure minimum content space when model is visible
        -- Header (~24px) + divider (5px) + at least 1 row (24px) + padding = ~60px
        local MIN_CONTENT_HEIGHT = 60
        if hasModel and this.ModelContainer then
            local modelH = this.ModelContainer:GetHeight() or 0
            local availContent = height - modelH - 8 - 6 - 5 -- top margin + gap + bottom margin
            if availContent < MIN_CONTENT_HEIGHT then
                -- Shrink model to fit, keeping minimum content area
                local newModelH = math.max(40, height - MIN_CONTENT_HEIGHT - 8 - 6 - 5)
                this.ModelContainer:SetHeight(newModelH)
                if this.NpcModelFrame then
                    this.NpcModelFrame:SetHeight(newModelH)
                    -- Refit camera for the smaller viewport
                    if this.NpcModelFrame.FitDistanceForCurrentTarget then
                        pcall(this.NpcModelFrame.FitDistanceForCurrentTarget, this.NpcModelFrame, 0.12)
                    end
                end
            end
        end

        if this.ContentFrame then
            this.ContentFrame:ClearAllPoints()
            if hasModel and this.ModelContainer then
                -- content directly below full-width model container
                this.ContentFrame:SetPoint("TOPLEFT", this.ModelContainer, "BOTTOMLEFT", 0, -6)
                this.ContentFrame:SetPoint("TOPRIGHT", this.ModelContainer, "BOTTOMRIGHT", 0, -6)
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
