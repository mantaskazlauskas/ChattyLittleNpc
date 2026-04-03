local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame

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
    if self.EnsureCompactBadge then self:EnsureCompactBadge() end
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
        if frame and frame.SetHeight then frame:SetHeight(self.Config and self.Config.Collapse and self.Config.Collapse.collapsedHeight or 56) end
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

function ReplayFrame:AnimateCollapse(collapsed, duration)
    if self._animatingCollapse then return end
    if self.EnsureCompactBadge then self:EnsureCompactBadge() end
    if not self.DisplayFrame then return end
    -- Cancel any prior OnUpdate
    if self._collapseAnimFrame and self._collapseAnimFrame.SetScript then
        self._collapseAnimFrame:SetScript("OnUpdate", nil)
    end
    local frame = self.DisplayFrame
    local dur = duration or (self.Config and self.Config.Collapse and self.Config.Collapse.duration or 0.18)
    local elapsed = 0
    local startH = frame:GetHeight() or 0
    if collapsed and frame.GetHeight and startH >= 80 then self._preCollapseHeight = startH end
    local endH = collapsed and (self.Config and self.Config.Collapse and self.Config.Collapse.collapsedHeight or 56) or self:GetSafeExpandHeight()
    local contentFrames = { self.HeaderText, self.HeaderDivider, self.QueueScrollBox, (self.ModelContainer or self.NpcModelFrame) }
    local badge = self.CompactBadge
    local bss = self.Config and self.Config.Collapse and self.Config.Collapse.badgeScaleStart or 0.90
    if collapsed then
        -- Prepare badge
        if badge then
            badge:Show(); badge:SetAlpha(0); badge:SetScale(bss)
            if self.UpdateCompactBadge then self:UpdateCompactBadge(true) end
        end
    else
        -- Prepare content to fade back in
        if self.ContentFrame then self.ContentFrame:Show() end
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
            if badge then badge:SetAlpha(ease); badge:SetScale(bss + (1 - bss) * ease) end
        else
            -- Expanding
            for _, f in ipairs(contentFrames) do if f and f.SetAlpha then f:SetAlpha(ease) end end
            if badge then badge:SetAlpha(inv); badge:SetScale(bss + (1 - bss) * inv) end
        end
        if t >= 1 then
            animFrame:SetScript("OnUpdate", nil)
            -- Finalize visibility
            if collapsed then
                for _, f in ipairs(contentFrames) do if f and f.Hide then f:Hide() end end
                if self.ContentFrame then self.ContentFrame:Hide() end
                if badge then badge:SetAlpha(1); badge:SetScale(1.0) end
                if self.HideSubtitle then self:HideSubtitle() end
            else
                if self.ContentFrame then self.ContentFrame:Show() end
                if badge then badge:Hide() end
                for _, f in ipairs(contentFrames) do if f and f.Show then f:Show(); if f.SetAlpha then f:SetAlpha(1) end end end
            end
            self._animatingCollapse = false
            if self.UpdateDisplayFrame then self:UpdateDisplayFrame() end
            if self.Relayout then self:Relayout() end
        end
    end)
end
