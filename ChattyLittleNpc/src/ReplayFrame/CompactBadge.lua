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

    -- Progress updater: animate ProgressLine width per-frame while playing
    badge._progressOnUpdate = function(_, _)
        local cp = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
        if not (cp and cp.startTime and cp.title and GetTime) then return end
        local elapsed = GetTime() - cp.startTime
        local estimated = CLN.Utils and CLN.Utils.EstimateVODuration and CLN.Utils.EstimateVODuration(cp.title) or 0
        if estimated <= 0 then return end
        local maxW = math.max(1, (badge:GetWidth() or 200) - 6)
        local progress = math.min(1, math.max(0, elapsed / estimated))
        progressLine:SetWidth(math.max(1, maxW * progress))
    end

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
    local paused = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer:IsPaused()

    -- Compact badge pause button (collapsed state)
    local badge = self.CompactBadge
    if badge and badge.PauseBtn then
        local tex = badge.PauseBtn.tex
        if tex then
            if paused then
                tex:SetTexture("Interface/Buttons/UI-SpellbookIcon-NextPage-Up")
            else
                tex:SetTexture("Interface/TimeManager/PauseButton")
            end
        end
    end

    -- Refresh queue rows to update the playing row's bullet icon
    if self.RefreshQueueDataProvider then self:RefreshQueueDataProvider() end
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
        -- Show animated progress line
        if badge.ProgressLine then
            badge.ProgressLine:Show()
            if badge._progressOnUpdate then
                badge:SetScript("OnUpdate", badge._progressOnUpdate)
            end
        end
    else
        badge.Icon:SetVertexColor(0.5, 0.5, 0.5, 0.6)
        badge.Title:SetTextColor(0.7, 0.7, 0.7, 0.8)
        if badge.GlowAnim and badge.GlowAnim:IsPlaying() then badge.GlowAnim:Stop() end
        if badge.IconGlow then badge.IconGlow:Hide() end
        if badge.ProgressLine then badge.ProgressLine:Hide() end
        badge:SetScript("OnUpdate", nil)
    end
end

