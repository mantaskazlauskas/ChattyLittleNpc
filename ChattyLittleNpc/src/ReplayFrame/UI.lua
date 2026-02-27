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
        -- Duration scales with sentence length, clamped 1.5–5s
        local dur = math.max(1.5, math.min(5.0, #sentences[idx] * 0.07 * 1.2))
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
                if frame and frame.SetHeight then frame:SetHeight(this.GetSafeExpandHeight and this:GetSafeExpandHeight() or 165) end
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

        -- Recompute hasModel AFTER LayoutModelArea which may show/hide the container.
        -- Using IsShown() ensures ContentFrame anchors match actual visibility.
        hasModel = this.ModelContainer and this.ModelContainer:IsShown() and not compact

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
