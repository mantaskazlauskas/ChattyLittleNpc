---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local IconAtlas = CLN.IconAtlas

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local DEFAULT_W, DEFAULT_H = CLN.DEFAULT_FRAME_WIDTH, CLN.DEFAULT_FRAME_HEIGHT

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
    self.expandedWidth = self.expandedWidth or (CLN.db.profile.frameSize and CLN.db.profile.frameSize.width) or (self.normalWidth)
    local defaultW = (CLN.db.profile.frameSize and CLN.db.profile.frameSize.width) or (self.expandedWidth or DEFAULT_W)
    local defaultH = (CLN.db.profile.frameSize and CLN.db.profile.frameSize.height) or DEFAULT_H
    if defaultH < 80 then defaultH = DEFAULT_H end
    frame:SetSize(defaultW, defaultH)
    if frame.SetResizeBounds then frame:SetResizeBounds(260, 120) end

    self.DisplayFrame = frame

    -- Dragging the window (manual edit or Edit Mode overlay) ends docking; the
    -- client re-anchors it to the screen, which SaveFramePosition then stores.
    hooksecurefunc(frame, "StartMoving", function()
        CLN.db.profile.frameAnchor = "free"
    end)

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
    if CLN.db.profile.frameScale then
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

    self:_CreateDisplayFrameAnimations()
    self:_IdleFadeInit()

    -- Visual style (backgrounds, portrait framing, header colors)
    if self.ApplyFrameStyle then self:ApplyFrameStyle() end

    -- Start hidden; UpdateVisibility() is the sole gatekeeper for showing.
    frame:Hide()
    frame:SetAlpha(0)

    -- Idle-fade hover detection ticker (throttled to every 0.2s)
    local idleTickElapsed = 0
    frame:HookScript("OnUpdate", function(_, dt)
        idleTickElapsed = idleTickElapsed + dt
        if idleTickElapsed < 0.2 then return end
        idleTickElapsed = 0
        self:_IdleFadeTick()
    end)

    return frame
end

function ReplayFrame:StartEditGlowPulse()
    if not self.EditGlow then return end
    local enabled = CLN.db.profile.editModeGlowHints
    if not enabled then return end
    -- Check if already shown enough times
    local profile = CLN.db.profile
    if profile._glowHintShown then return end

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
                CLN.db.profile._glowHintShown = true
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
    self.npcModelFrameHeight = CLN.db.profile.npcModelFrameHeight or 140

    -- Initialize the model container and model frame via extracted module (idempotent)
    if self.CreateModelUI and not (self.ModelContainer or self.NpcModelFrame) then
        self:CreateModelUI()
        if self.LayoutModelArea and self.DisplayFrame then
            self:LayoutModelArea(self.DisplayFrame)
        end
    elseif not (self.ModelContainer or self.NpcModelFrame) then
        -- Fallback: standalone model container above DisplayFrame
        local modelContainer = CreateFrame("Frame", "ChattyLittleNpcModelContainer", UIParent)
        modelContainer:SetPoint("BOTTOMLEFT", self.DisplayFrame, "TOPLEFT", 0, 2)
        modelContainer:SetPoint("BOTTOMRIGHT", self.DisplayFrame, "TOPRIGHT", 0, 2)
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

    -- Subtitle display: current dialogue text under the header line. While it
    -- shows, the queue list moves below it (_SetSubtitleSpace); its height
    -- follows the text (_SetSubtitleText).
    local subtitleBg = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
    subtitleBg:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    subtitleBg:SetPoint("TOPRIGHT", divider, "BOTTOMRIGHT", 2, -4)
    subtitleBg:SetHeight(36)
    subtitleBg:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    subtitleBg:SetBackdropColor(0, 0, 0, 0.5)
    subtitleBg:SetFrameLevel((contentFrame.GetFrameLevel and contentFrame:GetFrameLevel() or 0) + 5)
    subtitleBg:Hide()
    self.SubtitleFrame = subtitleBg

    local subtitleText = subtitleBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Width only: the box grows to the text's height
    subtitleText:SetPoint("TOPLEFT", subtitleBg, "TOPLEFT", 8, -6)
    subtitleText:SetPoint("TOPRIGHT", subtitleBg, "TOPRIGHT", -8, -6)
    subtitleText:SetJustifyH("CENTER")
    subtitleText:SetJustifyV("MIDDLE")
    if subtitleText.SetWordWrap then subtitleText:SetWordWrap(true) end
    subtitleText:SetTextColor(1.0, 1.0, 1.0, 0.95)
    self.SubtitleText = subtitleText
    self:_CreateSubtitleAnimations()

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
function ReplayFrame:AnchorHeaderToButtons()
    if not (self.HeaderText and self.ContentFrame) then return end
    -- Prefer the left-most always-visible button as the right anchor (editBtn exists even when lock is hidden)
    local rightAnchor = self.IdleCountdownText or self.EditModeButton or self.OptionsButton or self.ClearButton or self.CollapseButton
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

-- ============================================================================
-- Unified Tracker-Style Icon Helper
-- ============================================================================
-- Provides a consistent golden, desaturated look matching the Objectives
-- Tracker sidebar.  On hover icons brighten to full color; at rest they use a
-- muted gold tint so they sit quietly beside the tracker headers.

local ICON_NORMAL_ALPHA = 0.7
local ICON_HOVER_ALPHA  = 1.0
local ICON_GOLD_R, ICON_GOLD_G, ICON_GOLD_B = 1.0, 0.82, 0.0

--- Apply the "at rest" golden treatment to a texture.
local function ApplyTrackerIconRest(tex)
    tex:SetDesaturated(true)
    tex:SetVertexColor(ICON_GOLD_R, ICON_GOLD_G, ICON_GOLD_B, ICON_NORMAL_ALPHA)
end

--- Apply the "hovered" bright treatment to a texture.
local function ApplyTrackerIconHover(tex)
    tex:SetDesaturated(false)
    tex:SetVertexColor(1, 1, 1, ICON_HOVER_ALPHA)
end

--- Create a tracker-style icon button with unified golden appearance.
---@param parent Frame
---@param size number
---@param texturePath string
---@param tooltip string|fun():string
---@param onClick? function
---@return Button
local function CreateTrackerStyleIcon(parent, size, texturePath, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("CENTER")
    tex:SetSize(size - 2, size - 2)
    tex:SetTexture(texturePath)
    ApplyTrackerIconRest(tex)
    btn.tex = tex

    btn:SetScript("OnEnter", function(self)
        ApplyTrackerIconHover(self.tex)
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            local tip = type(tooltip) == "function" and tooltip() or tooltip
            GameTooltip:SetText(tip)
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function(self)
        ApplyTrackerIconRest(self.tex)
        if GameTooltip_Hide then GameTooltip_Hide() end
    end)

    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    return btn
end

-- Expose helpers so CompactBadge can reuse the same treatment
ReplayFrame._ApplyTrackerIconRest  = ApplyTrackerIconRest
ReplayFrame._ApplyTrackerIconHover = ApplyTrackerIconHover
ReplayFrame._CreateTrackerStyleIcon = CreateTrackerStyleIcon

-- Create all header buttons (collapse, clear, options, edit)
function ReplayFrame:CreateHeaderButtons(contentFrame)
    local this = self

    -- Chevron expand/collapse toggle (tracker minimize style)
    local expandTex  = IconAtlas and IconAtlas:Get(IconAtlas.keys.expand)  or "Interface/Buttons/UI-Panel-ExpandButton-Up"
    local collapseTex = IconAtlas and IconAtlas:Get(IconAtlas.keys.collapse) or "Interface/Buttons/UI-Panel-CollapseButton-Up"

    local collapseBtn
    collapseBtn = CreateTrackerStyleIcon(contentFrame, 18, expandTex,
        function() return collapseBtn._collapsed and "Expand" or "Collapse" end)
    collapseBtn:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -6, -6)
    collapseBtn._collapsed = false

    local function SetChevron(expanded)
        collapseBtn.tex:SetTexture(expanded and expandTex or collapseTex)
        ApplyTrackerIconRest(collapseBtn.tex)
    end

    collapseBtn:SetScript("OnClick", function(self)
        local targetCollapsed = not self._collapsed
        self._collapsed = targetCollapsed
        SetChevron(not targetCollapsed)
        if ReplayFrame.AnimateCollapse then
            local CC = ReplayFrame.Config and ReplayFrame.Config.Collapse
            ReplayFrame:AnimateCollapse(targetCollapsed, CC and CC.duration or 0.2)
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
                if frame and frame.SetHeight then frame:SetHeight(this.GetSafeExpandHeight and this:GetSafeExpandHeight() or DEFAULT_H) end
            end
            if this.UpdateDisplayFrame then this:UpdateDisplayFrame() end
            if this.Relayout then this:Relayout() end
        end
    end)
    self.CollapseButton = collapseBtn

    -- Clear button
    local clearBtn = CreateTrackerStyleIcon(contentFrame, 18,
        IconAtlas and IconAtlas:Get(IconAtlas.keys.clear) or "Interface/RAIDFRAME/ReadyCheck-NotReady",
        "Stop playback and clear all queued voiceovers",
        function()
            CLN.VoiceoverPlayer:ForceStopCurrentSound(true, true)
            ReplayFrame.userHidden = false
            ReplayFrame:UpdateDisplayFrameState()
        end)
    clearBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -6, 0)
    self.ClearButton = clearBtn

    -- Options button
    local optionsBtn = CreateTrackerStyleIcon(contentFrame, 18,
        IconAtlas and IconAtlas:Get(IconAtlas.keys.options) or "Interface/Buttons/UI-OptionsButton",
        "Open Chatty Little NPC options",
        function()
            CLN.Options:OpenSettings()
        end)
    optionsBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    self.OptionsButton = optionsBtn

    -- Edit Mode toggle button
    local editBtn = CreateTrackerStyleIcon(contentFrame, 18,
        "Interface/CURSOR/UI-Cursor-Move",
        function() return ReplayFrame._editMode and "Exit Edit Mode" or "Enter Edit Mode (move/resize)" end,
        function()
            if not ReplayFrame._editMode then
                if ReplayFrame.BeginManualEdit then ReplayFrame:BeginManualEdit() else ReplayFrame:SetEditMode(true) end
            else
                if ReplayFrame.EndManualEdit then ReplayFrame:EndManualEdit() else ReplayFrame:SetEditMode(false) end
            end
        end)
    editBtn:SetPoint("RIGHT", optionsBtn, "LEFT", -6, 0)
    self.EditModeButton = editBtn

    -- Lock toggle button (visible in Edit Mode; appears on hover)
    local lockBtn = CreateTrackerStyleIcon(contentFrame, 18,
        IconAtlas and IconAtlas:Get(IconAtlas.keys.lock) or "Interface/Buttons/LockButton-Locked",
        function()
            if ReplayFrame:IsFrameLocked() then
                return "Unlock window (allow moving)"
            else
                return "Lock window (prevent moving)"
            end
        end,
        function()
            ReplayFrame:SetFrameLocked(not ReplayFrame:IsFrameLocked())
            ReplayFrame:UpdateLockUI()
        end)
    lockBtn:SetPoint("RIGHT", editBtn, "LEFT", -6, 0)
    lockBtn:Hide()
    lockBtn._tex = lockBtn.tex
    self.LockButton = lockBtn
    if self.UpdateLockUI then self:UpdateLockUI() end

    -- Seconds until the idle fade, left of the buttons. Collapsed to 1px while
    -- hidden so the header keeps its width (see _UpdateIdleCountdown).
    local countdown = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countdown:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)
    countdown:SetJustifyH("RIGHT")
    countdown:SetWidth(1)
    self.IdleCountdownText = countdown

    -- Re-anchor the header now that all buttons exist
    if self.AnchorHeaderToButtons then self:AnchorHeaderToButtons() end
end

-- =============================================
-- Compact Badge (Collapsed Mode) Implementation
-- =============================================
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
    return CLN.db.profile.frameLocked and true or false
end

function ReplayFrame:SetFrameLocked(locked)
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
    -- Re-apply tracker-style tint after texture swap
    if self._ApplyTrackerIconRest then self._ApplyTrackerIconRest(self.LockButton._tex) end
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
        local compact = CLN.db.profile.compactMode
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
                local scale = CLN.db.profile.queueTextScale or 1.0
                this.HeaderText:SetFont("Fonts\\FRIZQT__.TTF", headerFontSize * scale, "")
            end
            if this.SaveSizeForActiveLayout then this:SaveSizeForActiveLayout() end
            return
        end

        -- Layout the model area via extracted module (separate frame above DisplayFrame)
        if this.LayoutModelArea then this:LayoutModelArea(frame) end

        -- ContentFrame always fills DisplayFrame (model is a separate frame above)
        if this.ContentFrame then
            this.ContentFrame:ClearAllPoints()
            this.ContentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
            this.ContentFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
            this.ContentFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 5)
        end

        CLN.db.profile.expandedWidth = width

        -- Scale header font size based on height
        if this.HeaderText then
            local headerFontSize = math.max(10, math.min(20, math.floor((height) / 8)))
            local scale = CLN.db.profile.queueTextScale or 1.0
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
