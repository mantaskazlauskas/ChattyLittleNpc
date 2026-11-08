-- WindowFade.lua - Fading the voiceover window and portrait: show/hide fades and idle fade.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

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
    local p = CLN.db.profile
    local idleAlpha = p.idleFadeOpacity or (F and F.idleAlpha) or 0.1
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
    local p = CLN.db.profile
    local targetAlpha = p.idleFadeOpacity or (F and F.idleAlpha) or 0.1
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
    local p2 = CLN.db.profile
    local targetAlpha = p2.idleFadeOpacity or (F and F.idleAlpha) or 0.1
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
    local isPlaying = CLN.VoiceoverPlayer.currentlyPlaying
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
        local p = CLN.db.profile
        local delay = p.idleFadeDelay or (F and F.idleDelay) or 10
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
    local p = CLN.db.profile
    local enabled = p.showIdleFadeCountdown ~= false and (p.idleFadeOpacity or 0.1) < 1
    local text = (enabled and remaining) and (math.ceil(remaining) .. "s") or ""
    if fs._text == text then return end
    fs._text = text
    fs:SetText(text)
    fs:SetWidth(text == "" and 1 or 28)
end
