---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Creates a full-width container for the NPC model and a fixed-size PlayerModel inside it.
-- Keeps the model from resizing with the frame; only the container spans the width.
function ReplayFrame:CreateModelUI()
    -- Prevent duplicate creation
    if self.ModelContainer or self.NpcModelFrame then return end
    -- Defaults if not already set
    self.npcModelFrameWidth = self.npcModelFrameWidth or 220
    -- Avoid compounding height increases across multiple calls
    self.npcModelFrameHeight = self.npcModelFrameHeight or math.floor(140 * 1.15)

    -- Container spans the width; used as a row above the queue
    local modelContainer = CreateFrame("Frame", "ChattyLittleNpcModelContainer", self.DisplayFrame)
    modelContainer:SetPoint("TOPLEFT", self.DisplayFrame, "TOPLEFT", 5, -8)
    modelContainer:SetPoint("TOPRIGHT", self.DisplayFrame, "TOPRIGHT", -5, -8)
    modelContainer:SetHeight(self.npcModelFrameHeight)
    modelContainer:Hide()
    self.ModelContainer = modelContainer

    -- Fixed-size model anchored left within the container
    local modelFrame = CreateFrame("PlayerModel", "ChattyLittleNpcModelFrame", modelContainer)
    modelFrame:SetSize(self.npcModelFrameWidth, self.npcModelFrameHeight)
    modelFrame:SetPoint("TOPLEFT", modelContainer, "TOPLEFT", 0, 0)
    modelFrame:Hide()
    self.NpcModelFrame = modelFrame
end

-- Position the full-width model container and fixed-size model; show/hide based on state
function ReplayFrame:LayoutModelArea(frame)
    local compact = CLN.db and CLN.db.profile and CLN.db.profile.compactMode
    local hasModel = self._hasValidModel and not compact

    if self.ModelContainer then
        self.ModelContainer:ClearAllPoints()
    -- Anchor ABOVE the frame: container bottom sits at frame top
    self.ModelContainer:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 5, 6)
    self.ModelContainer:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -5, 6)
        self.ModelContainer:SetHeight(self.npcModelFrameHeight or 140)
    if self.ModelContainer.SetFrameStrata then self.ModelContainer:SetFrameStrata("HIGH") end
        if hasModel then self.ModelContainer:Show() else self.ModelContainer:Hide() end
    end

    if self.NpcModelFrame then
        self.NpcModelFrame:ClearAllPoints()
        self.NpcModelFrame:SetSize(self.npcModelFrameWidth or 220, self.npcModelFrameHeight or 140)
    self.NpcModelFrame:SetPoint("TOPLEFT", (self.ModelContainer or frame), "TOPLEFT", 0, 0)
        if hasModel then self.NpcModelFrame:Show() else self.NpcModelFrame:Hide() end
    end
end

-- Build/update the model with npcId and handle container visibility
function ReplayFrame:UpdateNpcModelDisplay(npcId)
    if (not self.NpcModelFrame) then return end
    -- Defensive: ensure we only have one PlayerModel child
    if self.ModelContainer and self.ModelContainer.GetChildren then
        local count = 0
        local children = { self.ModelContainer:GetChildren() }
        for _, child in ipairs(children) do
            if child and child.GetObjectType and child:GetObjectType() == "PlayerModel" then
                count = count + 1
            end
        end
        if count > 1 then
            -- hide any extras just in case
            for _, child in ipairs(children) do
                if child ~= self.NpcModelFrame and child and child.GetObjectType and child:GetObjectType() == "PlayerModel" then
                    child:Hide()
                end
            end
        end
    end
    if self:IsCompactModeEnabled() then
        if self.ModelContainer then self.ModelContainer:Hide() end
        self.NpcModelFrame:Hide()
        self:ContractForNpcModel()
        return
    end

    local currentlyPlaying = CLN.VoiceoverPlayer.currentlyPlaying
    if (not (self:IsVoiceoverCurrenltyPlaying() and currentlyPlaying.npcId == npcId)) then
        if self.ModelContainer then self.ModelContainer:Hide() end
        self.NpcModelFrame:Hide()
        self:ContractForNpcModel()
        return
    end

    local displayID = NpcDisplayIdDB[npcId]
    if (displayID) then
        self.NpcModelFrame:ClearModel()
        self.NpcModelFrame:SetDisplayInfo(displayID)
        -- Slightly zoomed out for more headroom so tall models aren't clipped
    self.NpcModelFrame:SetPortraitZoom(0.65)
    self._currentZoom = 0.65
        -- Nudge model lower in viewport; negative Z lowers the model
        if self.NpcModelFrame.SetPosition then
            -- cache and reuse the chosen offset
            self.modelZOffset = self.modelZOffset or -0.08
            pcall(self.NpcModelFrame.SetPosition, self.NpcModelFrame, 0, 0, self.modelZOffset)
            self._currentZOffset = self.modelZOffset
        end
        self.NpcModelFrame:SetRotation(0.3)
        -- If audio is playing for this NPC, set talk immediately; otherwise idle
        local cur = CLN and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
        local isPlaying = cur and cur.isPlaying and cur:isPlaying() and cur.npcId == npcId
        if self.NpcModelFrame.SetAnimation then
            if isPlaying then
                local talkId = 60
                if self.ChooseTalkAnimIdForText and cur and cur.title then
                    talkId = self:ChooseTalkAnimIdForText(cur.title)
                end
                pcall(self.NpcModelFrame.SetAnimation, self.NpcModelFrame, talkId)
                if self.NpcModelFrame.SetSheathed then pcall(self.NpcModelFrame.SetSheathed, self.NpcModelFrame, true) end
                self._animState = "talk"
                self._lastTalkId = talkId
                if self.StartEmoteLoop then self:StartEmoteLoop() end
            else
                pcall(self.NpcModelFrame.SetAnimation, self.NpcModelFrame, 0) -- 0 = Stand/Idle
            end
        end
        self._hasValidModel = true
        if self.ModelContainer then self.ModelContainer:Show() end
        self.NpcModelFrame:Show()
        if self.SetupModelAnimations then self:SetupModelAnimations() end
    else
        self.NpcModelFrame:ClearModel()
        self.NpcModelFrame:Hide()
        if self.ModelContainer then self.ModelContainer:Hide() end
        self._hasValidModel = false
    end
    if self.Relayout then self:Relayout() end
end

function ReplayFrame:CheckAndShowModel()
    local currentlyPlaying = CLN.VoiceoverPlayer.currentlyPlaying
    if (not self:IsCompactModeEnabled() and self:IsVoiceoverCurrenltyPlaying() and currentlyPlaying.npcId) then
    self:UpdateNpcModelDisplay(currentlyPlaying.npcId)
    if self.UpdateConversationAnimation then self:UpdateConversationAnimation() end
    else
        if (self.NpcModelFrame) then self.NpcModelFrame:Hide() end
        if (self.ModelContainer) then self.ModelContainer:Hide() end
    end
end

function ReplayFrame:ExpandForNpcModel() end
function ReplayFrame:ContractForNpcModel() end

-- =========================
-- Simple animation helpers
-- =========================

-- Ensure a gentle idle animation and subtle rotation sway are active when the model is shown
function ReplayFrame:SetupModelAnimations()
    local m = self.NpcModelFrame
    if not m then return end

    -- Try to ensure the model is not paused and is in idle animation
    if m.SetPaused then pcall(m.SetPaused, m, false) end
    -- Do NOT force idle here; OnShow hook will choose talk/idle based on current playback

    if not m._animOnUpdate then
        m._animOnUpdate = function(frame, elapsed)
            -- No rotation sway; drive conversation cadence and keep idle alive only when idling
            frame._t = (frame._t or 0) + (elapsed or 0)

            local r = ReplayFrame -- captured upvalue
            local cur = CLN and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            local isPlaying = cur and cur.isPlaying and cur:isPlaying()
            local sameHandle = isPlaying and (r._lastSoundHandle == cur.soundHandle)

            -- Smooth camera updates via generic animation system only

            -- New generalized animation system (zoom/pan)
            if r.AnimUpdate then
                r:AnimUpdate(elapsed or 0)
            end

            -- Conversation emote loop is now external and timer-driven; nothing needed here
            -- Emote loop timing: use absolute time to avoid drift from chained timers
            if r._emoteLoopActive and r._emoteSegEndTime then
                local tNow = GetTime and GetTime() or (frame._t or 0)
                if tNow >= r._emoteSegEndTime then
                    if r._EmoteLoop_PickAndStartSegment then
                        r:_EmoteLoop_PickAndStartSegment(tNow)
                    end
                end
            end

            -- Some models stop animating after loads; poke idle periodically only when idling
            if frame.SetAnimation and (r._animState == "idle" or not sameHandle) then
                frame._poke = (frame._poke or 0) + (elapsed or 0)
                if frame._poke > 4.0 then
                    pcall(frame.SetAnimation, frame, 0)
                    frame._poke = 0
                end
            end
        end
    end

    -- Hook model frame lifecycle for the update
    if not m._hookedAnim then
        m:HookScript("OnShow", function(f)
            -- Initialize timers and attach updater
            f._t = 0; f._poke = 0
            if f.SetScript then f:SetScript("OnUpdate", m._animOnUpdate) end

            -- Do not force idle; choose animation based on current playback immediately
            local r = ReplayFrame
            local cur = CLN and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            local isPlaying = cur and cur.isPlaying and cur:isPlaying()
            if isPlaying then
                local talkId = 60
                if r and r.ChooseTalkAnimIdForText and cur.title then
                    talkId = r:ChooseTalkAnimIdForText(cur.title)
                end
                if r and r.SetModelAnim then r:SetModelAnim(talkId) else if f.SetAnimation then pcall(f.SetAnimation, f, talkId) end; if f.SetSheathed then pcall(f.SetSheathed, f, true) end end
                if r then
                    r._animState = "talk"
                    r._lastTalkId = talkId
                    -- Start the loop quickly if not already
                    if r.StartEmoteLoop then r:StartEmoteLoop() end
                end
            else
                if r and r.SetModelAnim then r:SetModelAnim(0) else if f.SetAnimation then pcall(f.SetAnimation, f, 0) end end
            end

            -- Let the Director refine (wave vs talk) as needed
            if r and r.UpdateConversationAnimation then r:UpdateConversationAnimation() end
        end)
        m:HookScript("OnHide", function(f)
            if f.SetScript then f:SetScript("OnUpdate", nil) end
            if ReplayFrame and ReplayFrame.ResetAnimationState then
                ReplayFrame:ResetAnimationState()
            end
        end)
        m._hookedAnim = true
    end

    -- If already shown, start updates immediately
    if m:IsShown() and m.SetScript then
        m:SetScript("OnUpdate", m._animOnUpdate)
    end
end

-- =========================
-- Conversation-driven animations
-- =========================

-- Choose talk animation id based on punctuation statistics in the text, with weighted randomness.
-- Mapping (WoW animation IDs from wowdev.wiki):
-- 60 = EmoteTalk (normal)
-- 64 = EmoteTalkExclamation (yell)
-- 65 = EmoteTalkQuestion (question)
-- Note: 66 is EmoteBow (not a talk anim). There is no EmoteTalkSubdued id.
function ReplayFrame:ChooseTalkAnimIdForText(text)
    local s = self.ToSingleLine and self:ToSingleLine(text or "") or (text or "")
    s = tostring(s)

    -- Compute sentence punctuation stats
    local stats = self.TA_SentencePunctuationStats and self:TA_SentencePunctuationStats(s) or { total = 0, questions = 0, exclamations = 0 }
    local total = stats.total or 0
    local q = stats.questions or 0
    local e = stats.exclamations or 0

    -- If there are sentences, set probabilities based on proportions of ? and ! across sentences.
    local pQ, pE
    if total > 0 then
        pQ = math.min(1, math.max(0, q / total))
        pE = math.min(1, math.max(0, e / total))
        local sum = pQ + pE
        if sum > 1 then
            -- Normalize in case of overlapping "!?" punctuation counting toward both
            pQ = pQ / sum
            pE = pE / sum
        end
    else
        pQ, pE = 0, 0
    end

    -- Base preference when no strong punctuation bias: prefer a subdued take 3:1 over normal.
    -- Since there is no dedicated "subdued" id, we fall back to EmoteTalk (60) in both cases; variety can be added via variants per model.
    local remaining = math.max(0, 1 - (pQ + pE))
    local pSubdued = remaining * 0.75
    local pNormal = remaining * 0.25

    -- Random draw
    local r = math.random()
    if r < pE then
        return 64 -- Exclamation
    elseif r < (pE + pQ) then
        return 65 -- Question
    else
        -- Both subdued and normal map to 60; reserved for future per-model variants if safe
        return 60
    end
end

function ReplayFrame:SetIdleLoop()
    local m = self.NpcModelFrame
    if not m or not m.SetAnimation then return end
    pcall(m.SetAnimation, m, 0) -- Stand/idle
    if m.SetSheathed then pcall(m.SetSheathed, m, true) end
    self._animState = "idle"
end

-- Play a one-shot wave at the start of a new sound handle
function ReplayFrame:MaybePlayStartWave()
    local m = self.NpcModelFrame
    if not (m and m.SetAnimation) then return end
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local handle = cur and cur.soundHandle or nil
    if not handle then return end
    -- Only trigger on a fresh start (new handle) and avoid late triggers
    if self._lastSoundHandle == handle then return end
    -- Skip wave for quest audio (often mid-sentence or UI-triggered)
    if cur and cur.questId then
        self._lastSoundHandle = handle
        -- start the talk animation path directly for quests
        self._animState = "talk"
        self._talkPhase = "talk"
        self:UpdateTalkAnimation()
        return
    end
    -- Guard against delayed callbacks by checking how long since playback started
    local tNow = GetTime and GetTime() or 0
    local startedAt = (cur and cur.startTime) or (tNow)
    local sinceStart = tNow - startedAt
    -- If it's been a while (>2.0s), treat as already in-progress: don't wave
    if sinceStart > 2.0 then
        self._lastSoundHandle = handle
        self._animState = "talk"
        self._talkPhase = "talk"
        self:UpdateTalkAnimation()
        return
    end
    self._lastSoundHandle = handle
    -- reset cadence timers for new handle
    self._cadenceActive = false
    self._playTime = 0
    self._phaseTime = 0
    self._talkPhase = nil

    local title = cur and cur.title or nil
    local shouldWave = self:HasGreetingInFirstWords(title, 10)
    if shouldWave then
        -- Use the new Wave emote module to orchestrate zoom-out, wave, and zoom-back
        self:PlayEmote("wave", { duration = 1.5, waveZoom = 0.3, waveOutDur = 0.2, zoomBackDur = 0.5 })
        -- Start emote loop after the initial wave; give it a small head start
        if C_Timer and C_Timer.After then
            C_Timer.After(1.6, function()
                self:StartEmoteLoop()
            end)
        end
    else
        -- No greeting upfront: skip wave; start talking and zoom immediately
        -- Do not perform any zoom when there is no greeting
        self:PlayEmote("talk")
        -- Start the emote loop immediately
        self:StartEmoteLoop()
    end
end

function ReplayFrame:UpdateTalkAnimation()
    local m = self.NpcModelFrame
    if not (m and m.SetAnimation) then return end
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local playing = cur and cur.isPlaying and cur:isPlaying()
    local inGrace = false
    if cur and cur.startTime and GetTime then
        local dt = GetTime() - (cur.startTime or 0)
        inGrace = dt >= 0 and dt < 0.6
    end
    if not (cur and (cur.title or cur.questId) and (playing or inGrace)) then
        self:SetIdleLoop()
        return
    end
    local talkId = self:ChooseTalkAnimIdForText(cur.title)
    if self._animState ~= "talk" or self._lastTalkId ~= talkId then
        if self.SetModelAnim then self:SetModelAnim(talkId) else if m.SetSheathed then pcall(m.SetSheathed, m, true) end; pcall(m.SetAnimation, m, talkId) end
        self._animState = "talk"
        self._lastTalkId = talkId
    end
end

-- Public: update model animation based on current playback state
function ReplayFrame:UpdateConversationAnimation()
    if not (self.NpcModelFrame and self.NpcModelFrame:IsShown()) then return end
    -- Drive via the centralized FSM
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local recentlyStarted = false
    if cur and cur.startTime and GetTime then
        local dt = GetTime() - (cur.startTime or 0)
        recentlyStarted = dt >= 0 and dt < 0.6
    end
    if cur and ( (cur.isPlaying and cur:isPlaying()) or recentlyStarted ) then
        if self.FSM_OnPlaybackStart then self:FSM_OnPlaybackStart(cur) end
    else
        local lastMsg = self.Director and self.Director._lastMsg or (cur and cur.title) or nil
        if self.FSM_OnPlaybackStop then self:FSM_OnPlaybackStop(lastMsg) end
    end
    if self.FSM_Tick then self:FSM_Tick() end
end

-- Public: when conversation stops, revert to idle
function ReplayFrame:OnConversationStop()
    -- Route through FSM for consistent farewell handling
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local lastMsg = cur and cur.title or (self.Director and self.Director._lastMsg) or nil
    if self.FSM_OnPlaybackStop then self:FSM_OnPlaybackStop(lastMsg) end
end

-- Utility: fully reset animation-related state so a new conversation can wave again
function ReplayFrame:ResetAnimationState()
    self._lastTalkId = nil
    self._animState = nil
    self._cadenceActive = false -- legacy
    self._playTime = 0
    self._phaseTime = 0
    self._talkPhase = nil
    self._pendingTalkAfterZoom = false
    self._lastSoundHandle = nil
    -- Stop generalized animations
    if self.AnimStop then
        self:AnimStop("zoom")
        self:AnimStop("pan")
    end
    -- Stop emote loop
    if self.StopEmoteLoop then self:StopEmoteLoop() end
    -- Reset position to baseline if available
    if self.NpcModelFrame and self.NpcModelFrame.SetPosition and (self.modelZOffset ~= nil) then
        pcall(self.NpcModelFrame.SetPosition, self.NpcModelFrame, 0, 0, self.modelZOffset)
        self._currentZOffset = self.modelZOffset
    end
end

-- Centralized model animation setter; prevents redundant sets and ensures sheathed
function ReplayFrame:SetModelAnim(animId)
    local m = self.NpcModelFrame
    if not (m and m.SetAnimation) then return end
    if animId == nil then return end
    -- Skip if already in this anim state to reduce flicker
    if self._lastTalkId == animId and self._animState == "talk" and animId ~= 0 then
        return
    end
    if animId == 0 then
        pcall(m.SetAnimation, m, 0)
        if m.SetSheathed then pcall(m.SetSheathed, m, true) end
        self._animState = "idle"
        return
    end
    -- Talk-like animations (60/64/65) normalize animState to talk
    pcall(m.SetAnimation, m, animId)
    if m.SetSheathed then pcall(m.SetSheathed, m, true) end
    if animId == 60 or animId == 64 or animId == 65 then
        self._animState = "talk"
        self._lastTalkId = animId
    end
end
