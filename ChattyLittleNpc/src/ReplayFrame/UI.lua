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
    self.expandedWidth = self.expandedWidth or (CLN and CLN.db and CLN.db.profile and CLN.db.profile.frameSize and CLN.db.profile.frameSize.width) or (self.normalWidth)
    local defaultW = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.frameSize and CLN.db.profile.frameSize.width) or (self.expandedWidth or DEFAULT_W)
    local defaultH = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.frameSize and CLN.db.profile.frameSize.height) or DEFAULT_H
    if defaultH < 80 then defaultH = DEFAULT_H end
    frame:SetSize(defaultW, defaultH)
    if frame.SetResizeBounds then frame:SetResizeBounds(260, 120) end

    self.DisplayFrame = frame

    -- Dragging the window (manual edit or Edit Mode overlay) ends docking; the
    -- client re-anchors it to the screen, which SaveFramePosition then stores.
    hooksecurefunc(frame, "StartMoving", function()
        if CLN.db and CLN.db.profile then CLN.db.profile.frameAnchor = "free" end
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

--- Stop an Alpha animation group and keep the frame at the alpha it had
--- reached. Stop() alone snaps the frame back to its own alpha, which the
--- animation never changed (e.g. full opacity in the middle of an idle fade).
local function stopAtCurrentAlpha(ag, frame)
    if not (ag and ag:IsPlaying()) then return end
    local anim = ag._anim
    local alpha
    if anim then
        local from, to = anim:GetFromAlpha(), anim:GetToAlpha()
        alpha = from + (to - from) * (anim:GetSmoothProgress() or 0)
    end
    ag:Stop()
    if alpha then frame:SetAlpha(alpha) end
end

--- Create fade-in/fade-out AnimationGroups on DisplayFrame.
--- Called once from GetDisplayFrame after the frame is built.
function ReplayFrame:_CreateDisplayFrameAnimations()
    local frame = self.DisplayFrame
    if not frame then return end

    -- Fade In: 0 → 1 with ease-out
    local fadeIn = frame:CreateAnimationGroup()
    local fi = fadeIn:CreateAnimation("Alpha")
    fi:SetFromAlpha(0)
    fi:SetToAlpha(1)
    local F = self.Config and self.Config.Fade
    fi:SetDuration(F and F.frameFadeIn or 0.2)
    fi:SetSmoothing("OUT")
    fadeIn._anim = fi
    fadeIn:SetScript("OnFinished", function()
        frame:SetAlpha(1)
    end)
    self._frameFadeInAG = fadeIn

    -- Fade Out: 1 → 0 with ease-in
    local fadeOut = frame:CreateAnimationGroup()
    local fo = fadeOut:CreateAnimation("Alpha")
    fo:SetFromAlpha(1)
    fo:SetToAlpha(0)
    fo:SetDuration(F and F.frameFadeOut or 0.25)
    fo:SetSmoothing("IN")
    fadeOut._anim = fo
    fadeOut:SetScript("OnFinished", function()
        self._frameFadingOut = false
        frame:SetAlpha(0)
        frame:Hide()
    end)
    self._frameFadeOutAG = fadeOut
end

--- Smoothly show the main DisplayFrame with a fade-in.
--- Idempotent: safe to call every frame from UpdateVisibility.
function ReplayFrame:_DisplayFrameFadeIn()
    local frame = self.DisplayFrame
    if not frame then return end
    -- Cancel idle-fade if active — playback/visibility is restoring. The idle
    -- restore animates the shown frame itself; a second fade on top would fight it.
    if self._idleFadeState and self._idleFadeState ~= "active" then
        if frame:IsShown() then
            self:_IdleFadeRestore()
            return
        end
        -- Hidden: nothing to restore, just reset the idle state
        self:_IdleFadeCancel()
    end
    -- Cancel any fade-out in progress, keeping the alpha it reached
    if self._frameFadingOut then
        stopAtCurrentAlpha(self._frameFadeOutAG, frame)
        self._frameFadingOut = false
    end
    -- Already playing fade-in? Let it continue
    if self._frameFadeInAG and self._frameFadeInAG:IsPlaying() then
        frame:Show()
        return
    end
    -- Already fully visible? No-op
    if frame:IsShown() and frame:GetAlpha() >= 1 then return end
    -- Reset idle timer so the countdown starts from when the frame re-appears
    -- (covers post-combat restore and any other hide→show cycle).
    self._idleLastActivity = GetTime()
    -- Fade in from where the frame is (0 when hidden, partway when a fade-out was cut short)
    local startAlpha = frame:IsShown() and frame:GetAlpha() or 0
    frame:SetAlpha(startAlpha)
    frame:Show()
    if self._frameFadeInAG then
        local F = self.Config and self.Config.Fade
        self._frameFadeInAG._anim:SetFromAlpha(startAlpha)
        self._frameFadeInAG._anim:SetDuration((F and F.frameFadeIn or 0.2) * (1 - startAlpha))
        self._frameFadeInAG:Play()
    else
        frame:SetAlpha(1)
    end
    -- Sync ModelContainer alpha
    local F2 = self.Config and self.Config.Fade
    self:_CancelModelFade()
    if self.ModelContainer and self.ModelContainer:IsShown() then
        self:_SetModelVisualAlpha(0)
        self:_FadeModelTo(1, F2 and F2.frameFadeIn or 0.2)
    end
end

--- Show the frame at full opacity right away, cancelling every fade.
--- Used by Edit Mode, which needs the frame visible even if it was hidden
--- by a fade-out (alpha 0) or dimmed by the idle fade.
function ReplayFrame:_ShowImmediately()
    local frame = self.DisplayFrame
    if not frame then return end
    if self._frameFadeInAG then self._frameFadeInAG:Stop() end
    if self._frameFadeOutAG then self._frameFadeOutAG:Stop() end
    self._frameFadingOut = false
    self:_IdleFadeCancel()
    self._idleLastActivity = GetTime()
    frame:SetAlpha(1)
    frame:Show()
    self:_SetModelVisualAlpha(1)
end

--- Smoothly hide the main DisplayFrame with a fade-out.
--- Idempotent: safe to call every frame from UpdateVisibility.
--- On completion, calls frame:Hide() to fully remove the frame.
function ReplayFrame:_DisplayFrameFadeOut()
    local frame = self.DisplayFrame
    if not frame or not frame:IsShown() then return end
    -- Already fading out? Let it continue
    if self._frameFadingOut then return end
    -- Cancel any fade-in, keeping the alpha it reached
    stopAtCurrentAlpha(self._frameFadeInAG, frame)
    -- Cancel idle-fade if in progress (we're doing a full hide)
    self:_IdleFadeCancel()
    -- Start fade-out from current alpha (avoid flash when idle-faded)
    self._frameFadingOut = true
    local curAlpha = frame:GetAlpha()
    if curAlpha < 0.01 then
        -- Already invisible — skip animation, just hide immediately
        self._frameFadingOut = false
        frame:SetAlpha(0)
        frame:Hide()
        self:_SetModelVisualAlpha(0)
        if self.ModelContainer then self.ModelContainer:Hide() end
        return
    end
    if self._frameFadeOutAG then
        self._frameFadeOutAG._anim:SetFromAlpha(curAlpha)
        self._frameFadeOutAG._anim:SetDuration((self.Config and self.Config.Fade and self.Config.Fade.frameFadeOut or 0.25) * curAlpha)
        self._frameFadeOutAG:Play()
    else
        self._frameFadingOut = false
        frame:SetAlpha(0)
        frame:Hide()
    end
    -- Sync ModelContainer alpha
    local F2 = self.Config and self.Config.Fade
    self:_FadeModelTo(0, F2 and F2.frameFadeOut or 0.25, function()
        if self.ModelContainer then self.ModelContainer:Hide() end
    end)
end

-- ============================================================================
-- IDLE-FADE SYSTEM
-- The frame is always visible when enabled.  When nothing is playing and the
-- mouse is not hovering, it fades to a low alpha.  Hovering or starting
-- playback restores full opacity.
-- ============================================================================

--- Initialize idle-fade state.  Called once from GetDisplayFrame.
function ReplayFrame:_IdleFadeInit()
    self._idleFadeState = "active" -- "active" | "idle" | "fading_out" | "fading_in"
    self._idleLastActivity = GetTime()
    self._idleHovered = false
end

--- Instantly restore the frame in the idle-faded state (no fade-in animation).
--- Used after combat ends when the frame was already idle before combat started.
function ReplayFrame:_RestoreAsIdle()
    local frame = self.DisplayFrame
    if not frame then return end
    local F = self.Config and self.Config.Fade
    local p = CLN and CLN.db and CLN.db.profile
    local idleAlpha = (p and p.idleFadeOpacity) or (F and F.idleAlpha) or 0.1
    -- Cancel any lingering animations
    if self._frameFadeInAG and self._frameFadeInAG:IsPlaying() then self._frameFadeInAG:Stop() end
    if self._frameFadeOutAG and self._frameFadeOutAG:IsPlaying() then self._frameFadeOutAG:Stop() end
    if self._idleFadingInAG and self._idleFadingInAG:IsPlaying() then self._idleFadingInAG:Stop() end
    if self._idleFadingOutAG and self._idleFadingOutAG:IsPlaying() then self._idleFadingOutAG:Stop() end
    self:_CancelModelFade()
    self._frameFadingOut = false
    -- Show at idle alpha directly
    frame:SetAlpha(idleAlpha)
    frame:Show()
    self:_SetModelVisualAlpha(idleAlpha)
    self._idleFadeState = "idle"
end

--- Record activity (hover, playback start) — resets the idle timer.
function ReplayFrame:_IdleFadeTouch()
    self._idleLastActivity = GetTime()
    if self._idleFadeState == "idle" or self._idleFadeState == "fading_out" then
        self:_IdleFadeRestore()
    end
    self._idleFadeState = "active"
end

--- Cancel idle fade entirely (used before a full hide).
function ReplayFrame:_IdleFadeCancel()
    if self.DisplayFrame then
        stopAtCurrentAlpha(self._idleFadingOutAG, self.DisplayFrame)
        stopAtCurrentAlpha(self._idleFadingInAG, self.DisplayFrame)
    end
    self:_CancelModelFade()
    self._idleFadeState = "active"
end

-- ============================================================================
-- MODEL-CONTAINER ALPHA SYNC
-- ModelContainer is parented to UIParent (for independent positioning), so it
-- does not inherit DisplayFrame's alpha.  These helpers mirror fade operations
-- onto ModelContainer using a simple OnUpdate lerp.
-- ============================================================================

--- Apply alpha to all model-rendering layers.
--- ModelScene rendering can bypass parent alpha in some states, so we drive
--- container, host, backend frame, and actor in sync.
function ReplayFrame:_SetModelVisualAlpha(alpha)
    local a = tonumber(alpha) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end

    if self.ModelContainer and self.ModelContainer.SetAlpha then
        self.ModelContainer:SetAlpha(a)
    end

    local host = self.NpcModelFrame
    if host and host.SetAlpha then
        host:SetAlpha(a)
    end

    local backend = host and host._backend
    local backendFrame = backend and backend.frame
    if backendFrame and backendFrame.SetAlpha then
        pcall(backendFrame.SetAlpha, backendFrame, a)
    end

    local actor = backend and backend.actor
    if actor and actor.SetAlpha then
        pcall(actor.SetAlpha, actor, a)
    end
end

--- Smoothly fade ModelContainer to a target alpha.
--- Cancels any previous model fade in progress.
function ReplayFrame:_FadeModelTo(targetAlpha, duration, onFinished)
    local mc = self.ModelContainer
    if not mc then
        if onFinished then onFinished() end
        return
    end
    if not mc:IsShown() then
        self:_SetModelVisualAlpha(targetAlpha)
        if onFinished then onFinished() end
        return
    end

    local startAlpha = mc:GetAlpha()
    if math.abs(startAlpha - targetAlpha) < 0.01 then
        self:_SetModelVisualAlpha(targetAlpha)
        if onFinished then onFinished() end
        return
    end

    if not duration or duration <= 0 then
        self:_SetModelVisualAlpha(targetAlpha)
        if onFinished then onFinished() end
        return
    end

    local elapsed = 0
    if not self._modelFadeFrame then
        self._modelFadeFrame = CreateFrame("Frame")
    end
    self._modelFadeFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        local t = math.min(1, elapsed / duration)
        self:_SetModelVisualAlpha(startAlpha + (targetAlpha - startAlpha) * t)
        if t >= 1 then
            self._modelFadeFrame:SetScript("OnUpdate", nil)
            if onFinished then onFinished() end
        end
    end)
end

--- Cancel any in-progress model fade and leave alpha as-is.
function ReplayFrame:_CancelModelFade()
    if self._modelFadeFrame then
        self._modelFadeFrame:SetScript("OnUpdate", nil)
    end
end

--- Smoothly fade frame to idle alpha.
function ReplayFrame:_IdleFadeToIdle()
    local frame = self.DisplayFrame
    if not frame or not frame:IsShown() then return end
    if self._idleFadeState == "idle" or self._idleFadeState == "fading_out" then return end

    local F = self.Config and self.Config.Fade
    local p = CLN and CLN.db and CLN.db.profile
    local targetAlpha = (p and p.idleFadeOpacity) or (F and F.idleAlpha) or 0.1
    local dur = F and F.idleFadeOut or 0.8

    -- Cancel any in-progress idle-fade-in, keeping the alpha it reached
    stopAtCurrentAlpha(self._idleFadingInAG, frame)

    -- Create animation group on first use
    if not self._idleFadingOutAG then
        local ag = frame:CreateAnimationGroup()
        local anim = ag:CreateAnimation("Alpha")
        anim:SetSmoothing("IN")
        ag._anim = anim
        ag:SetScript("OnFinished", function()
            -- Read the target from the animation: the Idle Opacity setting
            -- may have changed since this handler was created.
            if frame:IsShown() then
                frame:SetAlpha(anim:GetToAlpha())
            end
            self._idleFadeState = "idle"
        end)
        self._idleFadingOutAG = ag
    end

    -- Configure from current alpha to target
    local curAlpha = frame:GetAlpha()
    self._idleFadingOutAG._anim:SetFromAlpha(curAlpha)
    self._idleFadingOutAG._anim:SetToAlpha(targetAlpha)
    -- abs: the frame can sit below a newly raised Idle Opacity
    local fadeDur = dur * math.abs(curAlpha - targetAlpha) / (1 - targetAlpha + 0.01)
    self._idleFadingOutAG._anim:SetDuration(fadeDur)

    self._idleFadeState = "fading_out"
    self._idleFadingOutAG:Play()
    -- Sync ModelContainer to same idle alpha
    self:_FadeModelTo(targetAlpha, fadeDur)
end

--- Smoothly restore frame from idle alpha to full opacity.
function ReplayFrame:_IdleFadeRestore()
    local frame = self.DisplayFrame
    if not frame or not frame:IsShown() then return end

    local F = self.Config and self.Config.Fade
    local dur = F and F.idleFadeIn or 0.25

    -- Cancel any in-progress idle-fade-out, keeping the alpha it reached
    stopAtCurrentAlpha(self._idleFadingOutAG, frame)

    -- Create animation group on first use
    if not self._idleFadingInAG then
        local ag = frame:CreateAnimationGroup()
        local anim = ag:CreateAnimation("Alpha")
        anim:SetSmoothing("OUT")
        ag._anim = anim
        ag:SetScript("OnFinished", function()
            if frame:IsShown() then
                frame:SetAlpha(1)
            end
            self._idleFadeState = "active"
        end)
        self._idleFadingInAG = ag
    end

    local curAlpha = frame:GetAlpha()
    local p2 = CLN and CLN.db and CLN.db.profile
    local targetAlpha = (p2 and p2.idleFadeOpacity) or (F and F.idleAlpha) or 0.1
    self._idleFadingInAG._anim:SetFromAlpha(curAlpha)
    self._idleFadingInAG._anim:SetToAlpha(1)
    local restoreDur = math.max(0, dur * (1 - curAlpha) / (1 - targetAlpha + 0.01))
    self._idleFadingInAG._anim:SetDuration(restoreDur)

    self._idleFadeState = "fading_in"
    self._idleFadingInAG:Play()
    -- Sync ModelContainer to full opacity
    self:_FadeModelTo(1, restoreDur)
end

--- OnUpdate tick for idle-fade hover detection and timer.
--- Attached to DisplayFrame; fades frame to idle alpha when nothing is playing.
function ReplayFrame:_IdleFadeTick()
    local frame = self.DisplayFrame
    if not frame or not frame:IsShown() then return end
    -- A full fade-out owns the frame's alpha until it hides it
    if self._frameFadingOut then
        self:_UpdateIdleCountdown(nil)
        return
    end

    -- Detect hover via IsMouseOver (works even with EnableMouse(false))
    local hovered = (frame.IsMouseOver and frame:IsMouseOver())
        or (self.ModelContainer and self.ModelContainer:IsShown() and self.ModelContainer:IsMouseOver())
    if hovered and not self._idleHovered then
        -- Mouse entered
        self:_IdleFadeTouch()
    elseif self._idleHovered and not hovered then
        -- Mouse left: count the full delay from now, not from when it entered
        self._idleLastActivity = GetTime()
    end
    self._idleHovered = hovered

    -- Don't fade while something is playing, or during edit mode
    local isPlaying = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
        and CLN.VoiceoverPlayer.IsEffectivelyPlaying
        and CLN.VoiceoverPlayer:IsEffectivelyPlaying()
    if isPlaying or self._editMode or self._blizzardEditMode then
        -- Always keep the idle timer fresh while playing so that the idle
        -- countdown starts from the moment playback ends, not from whenever
        -- UpdateVisibility last fired (which could be the start of a long VO).
        self._idleLastActivity = GetTime()
        if self._idleFadeState ~= "active" then
            self:_IdleFadeTouch()
        end
        self:_UpdateIdleCountdown(nil)
        return
    end

    -- If hovered, stay active
    if hovered then
        self:_UpdateIdleCountdown(nil)
        return
    end

    -- Check idle timer
    local remaining
    if self._idleFadeState == "active" then
        local F = self.Config and self.Config.Fade
        local p = CLN and CLN.db and CLN.db.profile
        local delay = (p and p.idleFadeDelay) or (F and F.idleDelay) or 10
        local elapsed = GetTime() - (self._idleLastActivity or 0)
        if elapsed >= delay then
            self:_IdleFadeToIdle()
        else
            remaining = delay - elapsed
        end
    end
    self:_UpdateIdleCountdown(remaining)
end

--- Show the seconds left until the idle fade in the header, or hide the
--- counter (remaining = nil). Hidden when the setting is off or the fade
--- would change nothing (Idle Opacity at 100%).
function ReplayFrame:_UpdateIdleCountdown(remaining)
    local fs = self.IdleCountdownText
    if not fs then return end
    local p = CLN and CLN.db and CLN.db.profile
    local enabled = p and p.showIdleFadeCountdown ~= false and (p.idleFadeOpacity or 0.1) < 1
    local text = (enabled and remaining) and (math.ceil(remaining) .. "s") or ""
    if fs._text == text then return end
    fs._text = text
    fs:SetText(text)
    fs:SetWidth(text == "" and 1 or 28)
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

-- Make room for the subtitle: while shown, the queue list starts below it
-- instead of below the header line. The header and its buttons never move.
function ReplayFrame:_SetSubtitleSpace(shown)
    local list, divider = self.QueueListFrame, self.HeaderDivider
    if not (list and divider and self.ContentFrame) then return end
    local top = (shown and self.SubtitleFrame) or divider
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -6)
    list:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", (top == divider) and 2 or 0, -6)
    list:SetPoint("BOTTOMLEFT", self.ContentFrame, "BOTTOMLEFT", 8, 8)
    -- Row count depends on the list's height
    if self.DisplayFrame and self.DisplayFrame:IsShown() and self.RefreshQueueDataProvider then
        self:RefreshQueueDataProvider()
    end
end

-- Set the subtitle text and grow the box to fit it.
function ReplayFrame:_SetSubtitleText(text)
    if not (self.SubtitleText and self.SubtitleFrame) then return end
    self.SubtitleText:SetText(text or "")
    local h = self.SubtitleText:GetStringHeight() or 0
    self.SubtitleFrame:SetHeight(math.max(24, math.ceil(h) + 12))
end

function ReplayFrame:HideSubtitle()
    -- Invalidate any in-flight timer callbacks via generation token
    self._subtitleToken = (self._subtitleToken or 0) + 1
    -- Stop any in-progress subtitle fade animations.
    -- Note: Stop() does not fire OnFinished, so any _SubtitleFadeOut callback
    -- (including text-continuation onComplete) is intentionally dropped — the
    -- cancel action that triggered HideSubtitle supersedes the old completion.
    if self._subtitleFadeInAG and self._subtitleFadeInAG:IsPlaying() then
        self._subtitleFadeInAG:Stop()
    end
    if self._subtitleFadeOutAG and self._subtitleFadeOutAG:IsPlaying() then
        self._subtitleFadeOutAG:Stop()
    end
    self._subtitleTimer = nil
    self._subtitleSentences = nil
    self._subtitleIndex = nil
    self._textContinuationActive = false
    self._tcSentences = nil
    self._tcStartIndex = nil
    self._tcOnComplete = nil
    if self.SubtitleFrame then self.SubtitleFrame:Hide() end
    -- Restore header to original position
    if self.HeaderText and self.ContentFrame then
        self:_SetSubtitleSpace(false)
    end
    if self.AnchorHeaderToButtons then self:AnchorHeaderToButtons() end
end

--- Create fade-in/fade-out AnimationGroups on SubtitleFrame.
--- Called once during CreateContent after SubtitleFrame is built.
function ReplayFrame:_CreateSubtitleAnimations()
    local frame = self.SubtitleFrame
    if not frame then return end

    -- Fade In: 0 → 1 with ease-out
    local fadeIn = frame:CreateAnimationGroup()
    local fi = fadeIn:CreateAnimation("Alpha")
    fi:SetFromAlpha(0)
    fi:SetToAlpha(1)
    local F = self.Config and self.Config.Fade
    fi:SetDuration(F and F.subtitleFadeIn or 0.15)
    fi:SetSmoothing("OUT")
    fadeIn:SetScript("OnFinished", function()
        frame:SetAlpha(1)
    end)
    self._subtitleFadeInAG = fadeIn

    -- Fade Out: 1 → 0 with ease-in
    local fadeOut = frame:CreateAnimationGroup()
    local fo = fadeOut:CreateAnimation("Alpha")
    fo:SetFromAlpha(1)
    fo:SetToAlpha(0)
    fo:SetDuration(F and F.subtitleFadeOut or 0.2)
    fo:SetSmoothing("IN")
    self._subtitleFadeOutAG = fadeOut
end

--- Smoothly fade subtitle frame from current alpha to 1.
--- If already fully visible, this is a no-op.
function ReplayFrame:_SubtitleFadeIn()
    local frame = self.SubtitleFrame
    if not frame then return end
    -- Stop any in-progress fade-out and lock alpha to 1 (Stop doesn't fire OnFinished)
    if self._subtitleFadeOutAG and self._subtitleFadeOutAG:IsPlaying() then
        self._subtitleFadeOutAG:Stop()
        frame:SetAlpha(1)
        return
    end
    -- Stop an in-progress fade-in before restarting
    if self._subtitleFadeInAG and self._subtitleFadeInAG:IsPlaying() then
        self._subtitleFadeInAG:Stop()
        frame:SetAlpha(1)
        return
    end
    -- Only animate if not already fully visible
    if frame:GetAlpha() < 0.9 and self._subtitleFadeInAG then
        self._subtitleFadeInAG:Play()
    else
        frame:SetAlpha(1)
    end
end

--- Smoothly fade subtitle frame from 1 to 0, then hide and invoke callback.
--- Token-safe: the OnFinished handler bails if _subtitleToken has changed.
---@param token number   Current _subtitleToken for stale-check.
---@param callback function|nil  Called after fade completes and frame is hidden.
function ReplayFrame:_SubtitleFadeOut(token, callback)
    local frame = self.SubtitleFrame
    if not frame or not frame:IsShown() then
        if callback then callback() end
        return
    end
    -- Stop any in-progress fade-in
    if self._subtitleFadeInAG and self._subtitleFadeInAG:IsPlaying() then
        self._subtitleFadeInAG:Stop()
    end
    if self._subtitleFadeOutAG then
        self._subtitleFadeOutAG:SetScript("OnFinished", function()
            if token ~= self._subtitleToken then return end
            frame:SetAlpha(0)
            frame:Hide()
            if callback then callback() end
        end)
        frame:SetAlpha(1)
        self._subtitleFadeOutAG:Play()
    else
        frame:SetAlpha(0)
        frame:Hide()
        if callback then callback() end
    end
end

--- Show remaining sentences as timed subtitles for text continuation mode.
--- Displays a dimmed recap of the last-heard sentence, then reveals
--- unheard sentences one at a time at reading speed (~200 WPM).
---@param sentences string[]    Full sentence array from SplitTooltipIntoSentences.
---@param startIndex number     1-based index of the first UNHEARD sentence.
---@param onComplete function   Called when all sentences have been displayed.
function ReplayFrame:ShowRemainingSubtitles(sentences, startIndex, onComplete)
    if not self.SubtitleFrame or not self.SubtitleText then
        if onComplete then onComplete() end
        return
    end
    -- Cancel any existing subtitle sequence
    self:HideSubtitle()
    if not sentences or #sentences == 0 then
        if onComplete then onComplete() end
        return
    end

    startIndex = math.max(1, math.min(startIndex, #sentences))

    local styleScale = self.GetFrameStyle and self:GetFrameStyle().subtitleScale or 1
    self.SubtitleText:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, math.floor(12 * styleScale)), "")

    self._subtitleSentences = sentences
    self._subtitleIndex = 0
    self._subtitleToken = (self._subtitleToken or 0) + 1
    local token = self._subtitleToken

    self.SubtitleFrame:Show()
    self.SubtitleFrame:SetAlpha(0)
    -- Move the queue list below the subtitle (header and buttons stay put)
    if self.HeaderText then
        self:_SetSubtitleSpace(true)
    end
    if self.AnchorHeaderToButtons then self:AnchorHeaderToButtons() end

    -- "Show All" escape: click subtitle to instantly reveal remaining text
    -- Store current state on self so the click handler always reads fresh values
    self._tcSentences = sentences
    self._tcStartIndex = startIndex
    self._tcOnComplete = onComplete
    if not self._subtitleClickHooked then
        self.SubtitleFrame:EnableMouse(true)
        self.SubtitleFrame:SetScript("OnMouseDown", function()
            if not self._textContinuationActive then return end
            local curToken = self._subtitleToken
            local curSentences = self._tcSentences
            local curOnComplete = self._tcOnComplete
            if not curSentences then return end
            -- Show all remaining sentences at once
            local remaining = {}
            local idx = self._subtitleIndex or 1
            for i = idx, #curSentences do
                remaining[#remaining + 1] = curSentences[i]
            end
            if #remaining > 0 then
                self:_SetSubtitleText(table.concat(remaining, " "))
                self:_SubtitleFadeIn()
            end
            -- Cancel auto-advance timer and complete after a brief pause
            self._subtitleTimer = nil
            -- Adaptive pace: user clicked "Show All" → they read faster, nudge coefficient down
            if CLN.db and CLN.db.profile and CLN.db.profile.readingPaceCoefficient then
                local coeff = CLN.db.profile.readingPaceCoefficient
                CLN.db.profile.readingPaceCoefficient = math.max(0.5, coeff - 0.05)
            end
            -- Reset model to idle
            local m = self.NpcModelFrame
            if m and m.IsShown and m:IsShown() then
                self:SetModelAnim(self._naturalAnimId or 0)
            end
            self._subtitleTimer = C_Timer and C_Timer.After(2.0, function()
                if curToken ~= self._subtitleToken then return end
                self._textContinuationActive = false
                self:HideSubtitle()
                if curOnComplete then curOnComplete() end
            end)
        end)
        self._subtitleClickHooked = true
    end

    self._textContinuationActive = true

    -- Build focus-mode context text: previous (grey) + current (yellow) + next (dim white)
    local function buildFocusText(idx)
        local parts = {}
        -- Show previous sentence dimmed for context
        if idx > 1 and sentences[idx - 1] then
            parts[#parts + 1] = "|cFF666666" .. sentences[idx - 1] .. "|r"
        end
        -- Current sentence highlighted
        if sentences[idx] then
            parts[#parts + 1] = "|cFFFFFF00" .. sentences[idx] .. "|r"
        end
        -- Show next sentence dimmed for preview
        if idx < #sentences and sentences[idx + 1] then
            parts[#parts + 1] = "|cFF999999" .. sentences[idx + 1] .. "|r"
        end
        return table.concat(parts, " ")
    end

    -- Trigger NPC model talk animation for current sentence (lip-read mode)
    local function triggerLipRead(sentence)
        local m = self.NpcModelFrame
        if not (m and m.IsShown and m:IsShown()) then return end
        if self._npcIsDead then return end
        local animId = self.ChooseTalkAnimIdForText
            and self:ChooseTalkAnimIdForText(sentence) or 60
        if self.SetModelAnim then
            self:SetModelAnim(animId)
        end
    end

    -- Calculate reading duration with combat multiplier and adaptive pace
    local S = self.Config and self.Config.Subtitle
    local function getReadDuration(sentence)
        local dur = CLN.Utils and CLN.Utils.EstimateReadDuration
            and CLN.Utils.EstimateReadDuration(sentence)
            or math.max(S and S.sentenceDurMin or 1.5, #sentence / 20)
        -- Adaptive pace coefficient from SavedVariables
        local coeff = (CLN.db and CLN.db.profile and CLN.db.profile.readingPaceCoefficient) or 1.0
        dur = dur * coeff
        -- Combat multiplier: show text faster during combat (less distraction)
        if UnitAffectingCombat and UnitAffectingCombat("player") then
            dur = dur * (S and S.combatSpeedMult or 0.7)
        end
        return math.max(S and S.readingDurMin or 1.0, dur)
    end

    -- Inner function to advance through sentences
    local function showNext()
        if token ~= self._subtitleToken then return end
        if not self.SubtitleFrame or not self.SubtitleFrame:IsShown() then return end
        self._subtitleIndex = (self._subtitleIndex or 0) + 1
        local idx = self._subtitleIndex

        if idx > #sentences then
            -- Reset model to idle
            local m = self.NpcModelFrame
            if m and m.IsShown and m:IsShown() then
                self:SetModelAnim(self._naturalAnimId or 0)
            end
            -- All sentences shown; complete after a brief pause
            self._subtitleTimer = C_Timer and C_Timer.After(
                S and S.lastSentencePause or 2.0, function()
                if token ~= self._subtitleToken then return end
                self._textContinuationActive = false
                self._subtitleTimer = nil
                self:_SubtitleFadeOut(token, function()
                    if self.HeaderText and self.ContentFrame then
                        self:_SetSubtitleSpace(false)
                    end
                    if self.AnchorHeaderToButtons then self:AnchorHeaderToButtons() end
                    if onComplete then onComplete() end
                end)
            end)
            return
        end

        -- Skip already-heard sentences (before startIndex)
        if idx < startIndex then
            showNext()
            return
        end

        -- Focus mode: show context window (previous + current + next)
        self:_SetSubtitleText(buildFocusText(idx))
        self:_SubtitleFadeIn()
        -- Lip-read: trigger talk animation on model
        triggerLipRead(sentences[idx])
        -- Reading-speed timing with combat + adaptive multipliers
        local dur = getReadDuration(sentences[idx])
        self._subtitleTimer = C_Timer and C_Timer.After(dur, showNext)
    end

    -- Phase 1: Show recap of last-heard sentence (dimmed) if available
    local recapIndex = startIndex - 1
    if recapIndex >= 1 and sentences[recapIndex] then
        self:_SetSubtitleText("|cFF666666" .. sentences[recapIndex] .. "|r")
        self:_SubtitleFadeIn()
        self._subtitleIndex = startIndex - 1
        self._subtitleTimer = C_Timer and C_Timer.After(
            S and S.recapDuration or 1.5, function()
            if token ~= self._subtitleToken then return end
            self._subtitleIndex = startIndex - 1
            showNext()
        end)
    else
        -- No recap available; start directly
        self._subtitleIndex = startIndex - 1
        self._subtitleTimer = C_Timer and C_Timer.After(
            S and S.firstSentenceDelay or 0.3, showNext)
    end
end

--- Jump to a sentence by delta during text continuation (micro-scrub).
--- delta: -1 to go back one sentence, +1 to go forward.
---@param delta number  -1 or +1
function ReplayFrame:ScrubSentence(delta)
    if not self._textContinuationActive then return end
    local sentences = self._tcSentences
    local startIdx = self._tcStartIndex or 1
    if not sentences or #sentences == 0 then return end

    -- Cancel current auto-advance timer by invalidating its token
    self._subtitleToken = (self._subtitleToken or 0) + 1
    self._subtitleTimer = nil

    local curIdx = self._subtitleIndex or startIdx
    local newIdx = curIdx + delta
    -- Clamp to valid range (startIndex to #sentences)
    newIdx = math.max(startIdx, math.min(newIdx, #sentences))
    self._subtitleIndex = newIdx

    -- Build focus text for the new position
    local parts = {}
    if newIdx > 1 and sentences[newIdx - 1] then
        parts[#parts + 1] = "|cFF666666" .. sentences[newIdx - 1] .. "|r"
    end
    if sentences[newIdx] then
        parts[#parts + 1] = "|cFFFFFF00" .. sentences[newIdx] .. "|r"
    end
    if newIdx < #sentences and sentences[newIdx + 1] then
        parts[#parts + 1] = "|cFF999999" .. sentences[newIdx + 1] .. "|r"
    end
    if self.SubtitleText then
        self:_SetSubtitleText(table.concat(parts, " "))
        self:_SubtitleFadeIn()
    end

    -- Trigger lip-read animation
    local m = self.NpcModelFrame
    if m and m.IsShown and m:IsShown() and sentences[newIdx] then
        if not self._npcIsDead then
            local animId = self.ChooseTalkAnimIdForText
                and self:ChooseTalkAnimIdForText(sentences[newIdx]) or 60
            self:SetModelAnim(animId)
        end
    end

    -- Restart auto-advance timer from this sentence
    local token = self._subtitleToken
    local S = self.Config and self.Config.Subtitle
    local dur = CLN.Utils and CLN.Utils.EstimateReadDuration
        and CLN.Utils.EstimateReadDuration(sentences[newIdx])
        or math.max(S and S.sentenceDurMin or 1.5, #sentences[newIdx] / 20)
    local coeff = (CLN.db and CLN.db.profile and CLN.db.profile.readingPaceCoefficient) or 1.0
    dur = dur * coeff
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        dur = dur * (S and S.combatSpeedMult or 0.7)
    end
    dur = math.max(S and S.readingDurMin or 1.0, dur)

    self._subtitleTimer = C_Timer and C_Timer.After(dur, function()
        if token ~= self._subtitleToken then return end
        -- Continue auto-advancing from newIdx
        -- Increment and show next, or complete if at end
        self._subtitleIndex = newIdx
        local nextIdx = newIdx + 1
        if nextIdx > #sentences then
            -- Complete
            self._textContinuationActive = false
            self._subtitleTimer = nil
            if m and m.IsShown and m:IsShown() then self:SetModelAnim(self._naturalAnimId or 0) end
            C_Timer.After(S and S.lastSentencePause or 2.0, function()
                if token ~= self._subtitleToken then return end
                self:_SubtitleFadeOut(token, function()
                    if self.HeaderText and self.ContentFrame then
                        self:_SetSubtitleSpace(false)
                    end
                    if self.AnchorHeaderToButtons then self:AnchorHeaderToButtons() end
                    local cb = self._tcOnComplete
                    if cb then cb() end
                end)
            end)
        else
            -- Auto-advance to next
            self._subtitleIndex = newIdx
            -- Re-trigger the next sentence via a recursive-like pattern
            self:ScrubSentence(1)
        end
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
            if CLN.Options and CLN.Options.OpenSettings then
                CLN.Options:OpenSettings()
            end
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
