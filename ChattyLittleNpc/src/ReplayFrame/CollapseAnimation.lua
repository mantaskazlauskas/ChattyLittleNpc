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
    if self.EnsureCompactBadge then self:EnsureCompactBadge() end
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
