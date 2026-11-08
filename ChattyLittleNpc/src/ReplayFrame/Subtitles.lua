-- Subtitles.lua - Sentence-by-sentence subtitles shown in the voiceover window.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

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
            if CLN.db.profile.readingPaceCoefficient then
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
        local dur = CLN.Utils.EstimateReadDuration(sentence)
        -- Adaptive pace coefficient from SavedVariables
        local coeff = CLN.db.profile.readingPaceCoefficient or 1.0
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
    local dur = CLN.Utils.EstimateReadDuration(sentences[newIdx])
    local coeff = CLN.db.profile.readingPaceCoefficient or 1.0
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
