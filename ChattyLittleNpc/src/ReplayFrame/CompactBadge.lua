local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
local IconAtlas = CLN.IconAtlas

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
    -- Reuse the tracker-style golden icon treatment for visual consistency
    local restFn  = ReplayFrame._ApplyTrackerIconRest
    local hoverFn = ReplayFrame._ApplyTrackerIconHover

    local function makeBtn(parent, size, texPath, tooltip, onClick)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(size, size)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetPoint("CENTER")
        t:SetSize(size - 4, size - 4)
        t:SetTexture(texPath)
        if restFn then restFn(t) end
        b.tex = t
        b:SetScript("OnEnter", function(self)
            if hoverFn then hoverFn(self.tex) end
            if GameTooltip and GameTooltip.SetOwner then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines(); GameTooltip:AddLine(tooltip, 1, 1, 1); GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(self)
            if restFn then restFn(self.tex) end
            if GameTooltip_Hide then GameTooltip_Hide() end
        end)
        b:SetScript("OnClick", onClick)
        return b
    end

    -- Stop button (clean X mark matching header clear icon)
    local stopBtn = makeBtn(badge, 22, "Interface/RAIDFRAME/ReadyCheck-NotReady", "Stop playback", function()
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
        if hoverFn then hoverFn(btn.tex) end
        if GameTooltip and GameTooltip.SetOwner then
            local paused = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer:IsPaused()
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(paused and "Resume playback" or "Pause playback", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    pauseBtn:SetScript("OnLeave", function(btn)
        if restFn then restFn(btn.tex) end
        if GameTooltip_Hide then GameTooltip_Hide() end
    end)
    badge.PauseBtn = pauseBtn

    -- Micro-scrub buttons: ◀ ▶ for sentence navigation during text continuation
    local scrubBack = makeBtn(badge, 18, "Interface/Buttons/UI-SpellbookIcon-PrevPage-Up", "Previous sentence", function()
        if CLN.ReplayFrame and CLN.ReplayFrame.ScrubSentence then
            CLN.ReplayFrame:ScrubSentence(-1)
        end
    end)
    scrubBack:SetPoint("RIGHT", pauseBtn, "LEFT", -2, 0)
    scrubBack:Hide()
    badge.ScrubBackBtn = scrubBack

    local scrubFwd = makeBtn(badge, 18, "Interface/Buttons/UI-SpellbookIcon-NextPage-Up", "Next sentence", function()
        if CLN.ReplayFrame and CLN.ReplayFrame.ScrubSentence then
            CLN.ReplayFrame:ScrubSentence(1)
        end
    end)
    scrubFwd:SetPoint("RIGHT", scrubBack, "LEFT", -2, 0)
    scrubFwd:Hide()
    badge.ScrubFwdBtn = scrubFwd

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

    -- Time text ("0:23 / 1:45") shown when pack-provided duration is available
    local timeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("BOTTOMRIGHT", badge, "BOTTOMRIGHT", -6, 4)
    timeText:SetJustifyH("RIGHT")
    timeText:SetTextColor(0.75, 0.75, 0.75, 0.8)
    timeText:Hide()
    badge.TimeText = timeText

    -- Helper: format seconds as "M:SS"
    local function FormatTime(seconds)
        if not seconds or seconds < 0 then return "0:00" end
        local m = math.floor(seconds / 60)
        local s = math.floor(seconds % 60)
        return string.format("%d:%02d", m, s)
    end

    -- Progress updater: animate ProgressLine width per-frame while playing
    badge._progressOnUpdate = function(_, _)
        local cp = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
        if not (cp and GetTime) then return end

        -- Throttle to ~20 Hz — progress bar doesn't need 60fps
        local now = GetTime()
        local thr = ReplayFrame.Config and ReplayFrame.Config.Throttle
        local interval = thr and thr.progressBarInterval or 0.05
        if (badge._progressLastUpdate or 0) + interval > now then return end
        badge._progressLastUpdate = now

        -- Text continuation mode: progress based on reading time
        if cp._textContinuation and cp._textContinuationStartTime and cp._textContinuationDuration then
            -- Freeze progress bar while paused
            local paused = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer:IsPaused()
            if paused then return end
            local elapsed = GetTime() - cp._textContinuationStartTime
            local duration = cp._textContinuationDuration
            if duration <= 0 then return end
            local maxW = math.max(1, (badge:GetWidth() or 200) - 6)
            local progress = math.min(1, math.max(0, elapsed / duration))
            progressLine:SetWidth(math.max(1, maxW * progress))
            if badge.TimeText then badge.TimeText:Hide() end
            return
        end

        -- Normal audio mode: use stored duration (pack-provided or text estimate)
        if not (cp.startTime and cp.title) then return end
        local elapsed = GetTime() - cp.startTime
        local estimated = cp._estimatedDuration or 0
        if estimated <= 0 then return end
        local maxW = math.max(1, (badge:GetWidth() or 200) - 6)
        local progress = math.min(1, math.max(0, elapsed / estimated))
        progressLine:SetWidth(math.max(1, maxW * progress))

        -- Show elapsed / total time when pack duration is available
        if badge.TimeText then
            if cp._hasPackDuration then
                local displayElapsed = math.min(elapsed, estimated)
                badge.TimeText:SetText(FormatTime(displayElapsed) .. " / " .. FormatTime(estimated))
                badge.TimeText:Show()
            else
                badge.TimeText:Hide()
            end
        end
    end

    -- Speaker glow pulse animation
    local F = self.Config and self.Config.Fade
    local glowDur = F and F.badgeGlowPulseDur or 0.8
    local glowAlpha = F and F.badgeGlowMaxAlpha or 0.35
    local glowAG = iconGlow:CreateAnimationGroup()
    glowAG:SetLooping("REPEAT")
    local fadeIn = glowAG:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(glowAlpha)
    fadeIn:SetDuration(glowDur)
    fadeIn:SetOrder(1)
    local fadeOut = glowAG:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(glowAlpha)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(glowDur)
    fadeOut:SetOrder(2)
    badge.GlowAnim = glowAG

    badge:SetScript("OnSizeChanged", function()
        if self.UpdateCompactBadge then self:UpdateCompactBadge(true) end
    end)

    self.CompactBadge = badge
end

function ReplayFrame:UpdatePauseButton()
    local player = CLN.VoiceoverPlayer
    local paused = player and player:IsPaused()

    -- Compact badge pause button (collapsed state)
    local badge = self.CompactBadge
    if badge and badge.PauseBtn then
        local tex = badge.PauseBtn.tex
        if tex then
            if paused then
                -- Check if we're past the text continuation threshold (Smart Resume)
                local cp = player and player.currentlyPlaying
                local showReadIcon = false
                if cp and cp._elapsedAtPause and cp.title then
                    local estimated = cp._estimatedDuration
                        or (CLN.Utils and CLN.Utils.EstimateVODuration and CLN.Utils.EstimateVODuration(cp.title))
                        or 0
                    local threshold = (CLN.db and CLN.db.profile and CLN.db.profile.textContinuationThreshold) or 0.75
                    local enabled = not CLN.db or not CLN.db.profile or CLN.db.profile.textContinuationEnabled ~= false
                    if enabled and estimated > 0 and (cp._elapsedAtPause / estimated) >= threshold then
                        showReadIcon = true
                    end
                end
                if showReadIcon then
                    tex:SetTexture("Interface/Icons/INV_Misc_Book_09")
                else
                    tex:SetTexture("Interface/Buttons/UI-SpellbookIcon-NextPage-Up")
                end
            else
                tex:SetTexture("Interface/TimeManager/PauseButton")
            end
            -- Re-apply golden treatment after texture swap
            if self._ApplyTrackerIconRest then self._ApplyTrackerIconRest(tex) end
        end
    end

    -- Refresh queue rows to update the playing row's bullet icon
    if self.RefreshQueueDataProvider then self:RefreshQueueDataProvider() end
end

function ReplayFrame:UpdateCompactBadge(force)
    if not (self.CollapseButton and self.CollapseButton._collapsed) then return end
    if not self.CompactBadge then return end
    local badge = self.CompactBadge
    local player = CLN.VoiceoverPlayer
    local cur = player and player.currentlyPlaying or nil
    local curState = player and player.GetPlaybackState and player:GetPlaybackState(cur) or nil
    local playing = curState == (player and player.State and player.State.PLAYING or "playing")
    local textContinuation = curState == (player and player.State and player.State.TEXT_CONTINUING or "text_continuing")
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
    if playing or textContinuation then
        if textContinuation then
            -- Text continuation: use a distinct icon color (softer white)
            badge.Icon:SetVertexColor(0.9, 0.9, 1.0, 1)
        else
            badge.Icon:SetVertexColor(1.0, 0.82, 0.0, 1)
        end
        badge.Title:SetTextColor(1.0, 1.0, 1.0, 0.95)
        if badge.IconGlow then
            if textContinuation then
                -- Steady glow during text continuation (no pulsing)
                badge.IconGlow:Show()
                badge.IconGlow:SetAlpha(0.4)
                if badge.GlowAnim and badge.GlowAnim:IsPlaying() then badge.GlowAnim:Stop() end
            else
                badge.IconGlow:Show()
                if badge.GlowAnim and not badge.GlowAnim:IsPlaying() then badge.GlowAnim:Play() end
            end
        end
        -- Show animated progress line
        if badge.ProgressLine then
            badge.ProgressLine:Show()
            badge._progressLastUpdate = nil
            if badge._progressOnUpdate then
                badge:SetScript("OnUpdate", badge._progressOnUpdate)
            end
        end
        -- Show micro-scrub buttons during text continuation
        if textContinuation then
            if badge.ScrubBackBtn then badge.ScrubBackBtn:Show() end
            if badge.ScrubFwdBtn then badge.ScrubFwdBtn:Show() end
        else
            if badge.ScrubBackBtn then badge.ScrubBackBtn:Hide() end
            if badge.ScrubFwdBtn then badge.ScrubFwdBtn:Hide() end
        end
    else
        badge.Icon:SetVertexColor(0.5, 0.5, 0.5, 0.6)
        badge.Title:SetTextColor(0.7, 0.7, 0.7, 0.8)
        if badge.GlowAnim and badge.GlowAnim:IsPlaying() then badge.GlowAnim:Stop() end
        if badge.IconGlow then badge.IconGlow:Hide() end
        if badge.ProgressLine then badge.ProgressLine:Hide() end
        if badge.TimeText then badge.TimeText:Hide() end
        if badge.ScrubBackBtn then badge.ScrubBackBtn:Hide() end
        if badge.ScrubFwdBtn then badge.ScrubFwdBtn:Hide() end
        badge:SetScript("OnUpdate", nil)
    end
end
