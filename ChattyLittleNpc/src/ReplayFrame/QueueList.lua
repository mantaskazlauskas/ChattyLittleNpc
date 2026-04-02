local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame

function ReplayFrame:GetRowTextAvailableWidth(row)
    if not (row and row.text) then return 0 end
    local left = row.text.GetLeft and row.text:GetLeft() or nil
    local right = row.GetRight and row:GetRight() or nil
    if left and right then
        local pad = 8 -- mirror the RIGHT -8 used in SetPoint
        local w = (right - pad) - left
        if w and w > 0 then return w end
    end
    local fallback = (row.GetWidth and row:GetWidth() or 0) - 28
    return math.max(0, fallback)
end

function ReplayFrame:FitRowText(row)
    if not (row and row.text) then return end
    local full = row._fullText or row.text:GetText() or ""
    local available = self:GetRowTextAvailableWidth(row)
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
    if fits(full) then
        row.text:SetText(full)
        return
    end
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

function ReplayFrame:UpdateQueueBadge()
    if not self.QueueBadge then return end
    local q = CLN.questsQueue and #CLN.questsQueue or 0
    if q > 1 then
        self.QueueBadge:SetText("[" .. tostring(q) .. "]")
        self.QueueBadge:Show()
    elseif q == 1 then
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

function ReplayFrame:GetTooltipMaxWidth()
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
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #text == 0 then return lines end
    for chunk, punc in text:gmatch("([^%.%!%?]+)([%.%!%?]*)%s*") do
        local s = (chunk or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local seg = s .. (punc or "")
        if #seg > 0 then table.insert(lines, seg) end
    end
    if #lines == 0 then table.insert(lines, text) end
    return lines
end

function ReplayFrame:CreateScrollBox(contentFrame)
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
    local scrollThumb = CreateFrame("Frame", nil, list)
    scrollThumb:SetWidth(6)
    scrollThumb:SetFrameStrata("HIGH")
    scrollThumb:EnableMouse(true)
    scrollThumb:SetMovable(true)
    scrollThumb:Hide()
    local scrollTex = scrollThumb:CreateTexture(nil, "ARTWORK")
    scrollTex:SetAllPoints()
    scrollTex:SetColorTexture(1.0, 0.82, 0.0, 0.4) -- gold, semi-transparent

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

            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnMouseUp", function(selfBtn, button)
                local e = selfBtn._element
                if not e then return end
                if e.isPlaying then
                    if button == "RightButton" then
                        CLN.VoiceoverPlayer:SkipCurrentSound()
                        this.userHidden = false
                        this:UpdateDisplayFrameState()
                    else
                        if CLN.VoiceoverPlayer then CLN.VoiceoverPlayer:TogglePause() end
                    end
                elseif button == "LeftButton" and e.queueIndex then
                    -- Delegate to player: drops items before target, then plays it
                    if CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.PlayQueuedItemAtIndex then
                        CLN.VoiceoverPlayer:PlayQueuedItemAtIndex(e.queueIndex)
                    end
                elseif button == "LeftButton" and e.isHistory then
                    if InCombatLockdown and InCombatLockdown() then return end
                    -- For non-quest sounds, check if a quest is blocking playback
                    -- before removing from history (PlayNonQuestSound would skip it)
                    if not (e.questId and e.phase) and e.npcId and e.title and e.entryType then
                        local cp = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                        if cp and cp.cantBeInterrupted
                            and CLN.VoiceoverPlayer:IsEffectivelyPlaying()
                            and CLN.db.profile.questPlaybackMode == 'queue' then
                            return -- can't play gossip while quest is playing; leave in history
                        end
                    end
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
                        CLN.VoiceoverPlayer:PlayQuestSound(e.questId, e.phase, e.npcId, e.displayID, e.gender, e.creatureType)
                    elseif e.npcId and e.title and e.entryType and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.PlayNonQuestSound then
                        CLN.VoiceoverPlayer:PlayNonQuestSound(e.npcId, e.entryType, e.title, e.gender, e.displayID, e.creatureType, { skipCooldown = true })
                    end
                    if ReplayFrame.MarkQueueDirty then ReplayFrame:MarkQueueDirty() end
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
                    local maxW = ReplayFrame.GetTooltipMaxWidth and ReplayFrame:GetTooltipMaxWidth() or 420
                    if GameTooltip.SetMaximumWidth then GameTooltip:SetMaximumWidth(maxW) end
                    GameTooltip:ClearLines()
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
                    if e.isPlaying then
                        GameTooltip:AddLine(" ")
                        local paused = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer:IsPaused()
                        GameTooltip:AddLine(paused and "|cFF00FF00Click|r to resume" or "|cFF00FF00Click|r to pause", 0.7, 0.7, 0.7)
                        GameTooltip:AddLine("|cFFFF8800Right-click|r to skip", 0.7, 0.7, 0.7)
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
        for _, r in ipairs(self.QueueRows) do r:Hide(); r._element = nil; if r.bulletTex then r.bulletTex:Hide() end; if r.typeIcon then r.typeIcon:SetSize(0.001, 14); r.typeIcon:Hide() end; r:SetScript("OnUpdate", nil) end
        local showBadges = CLN and CLN.db and CLN.db.profile and CLN.db.profile.showQuestTypeBadges
        for i = 1, toShow do
            local row = self.QueueRows[i]
            local element = entries[i]
            row._element = element
            row._isActive = element.isPlaying
            row:Show()

            if element.isDivider then
                row.text:SetText(element.label or "— History —")
                row.text:SetTextColor(0.6, 0.5, 0.2)
                row._lastLabel = nil -- invalidate cache so recycled rows re-render
                row._lastAvail = nil
                if row.bulletTex then row.bulletTex:Hide() end
                if row.typeIcon then row.typeIcon:SetSize(0.001, 14); row.typeIcon:Hide() end
                row:EnableMouse(false)
            elseif element.isHistory then
                local label = element.label or "Unknown"
                if self.GetAccessibilityBadge then
                    local badge = self:GetAccessibilityBadge(element.entryType)
                    if badge ~= "" then label = badge .. label end
                end
                row._fullText = label
                if self.GetRowColor then
                    row.text:SetTextColor(self:GetRowColor(element, showBadges))
                else
                    row.text:SetTextColor(0.5, 0.5, 0.5)
                end
                if row.bulletTex then
                    row.bulletTex:SetColorTexture(0.5, 0.5, 0.5, 0.5) -- dim bullet
                    row.bulletTex:Show()
                end
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
                local avail = self:GetRowTextAvailableWidth(row)
                if row._lastLabel ~= label or row._lastAvail ~= avail then
                    row.text:SetText(label)
                    self:FitRowText(row)
                    row._lastLabel = label
                    row._lastAvail = avail
                end
            else
                local label = element.label or "Unknown"
                if self.GetAccessibilityBadge then
                    local badge = self:GetAccessibilityBadge(element.entryType)
                    if badge ~= "" then label = badge .. label end
                end
                row._fullText = label
                row:EnableMouse(true)
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
                    if element.isPlaying then
                        local paused = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer:IsPaused()
                        row.bulletTex:SetColorTexture(0, 0, 0, 0) -- hide color bullet
                        row.bulletTex:SetSize(14, 14)
                        if paused then
                            row.bulletTex:SetTexture("Interface/Buttons/UI-SpellbookIcon-NextPage-Up")
                        else
                            row.bulletTex:SetTexture("Interface/TimeManager/PauseButton")
                        end
                        row.bulletTex:Show()
                    else
                        row.bulletTex:SetTexture(nil) -- clear any icon texture
                        row.bulletTex:SetSize(4, 4)
                        row.bulletTex:SetColorTexture(1.0, 0.82, 0.0, 0.9) -- restore gold bullet
                        row.bulletTex:Show()
                    end
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

    self.QueueScrollBox = self.QueueListFrame
    self.QueueScrollBar = nil
end
