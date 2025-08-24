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

            -- Smooth vertical position animation (Z)
            if r._posAnimActive and frame.SetPosition then
                r._posElapsed = (r._posElapsed or 0) + (elapsed or 0)
                local d = math.max(0.01, r._posDuration or 0.25)
                local t = math.min(1, r._posElapsed / d)
                -- easeOutCubic
                local e = 1 - (1 - t) * (1 - t) * (1 - t)
                local fromZ = (r._posFromZ ~= nil) and r._posFromZ or (r._currentZOffset or r.modelZOffset or 0)
                local toZ = (r._posToZ ~= nil) and r._posToZ or (r.modelZOffset or 0)
                local z = fromZ + (toZ - fromZ) * e
                pcall(frame.SetPosition, frame, 0, 0, z)
                r._currentZOffset = z
                if t >= 1 then
                    r._posAnimActive = false
                end
            end

            -- Smooth zoom animation when conversation starts
            if r._zoomAnimActive and frame.SetPortraitZoom then
                r._zoomElapsed = (r._zoomElapsed or 0) + (elapsed or 0)
                local d = math.max(0.01, r._zoomDuration or 0.6)
                local t = math.min(1, r._zoomElapsed / d)
                -- easeOutCubic
                local e = 1 - (1 - t) * (1 - t) * (1 - t)
                local z = (r._zoomFrom or 0.3) + ((r._zoomTo or 0.65) - (r._zoomFrom or 0.3)) * e
                z = math.max(0, math.min(1, z))
                pcall(frame.SetPortraitZoom, frame, z)
                r._currentZoom = z
                if t >= 1 then
                    r._zoomAnimActive = false
                    -- If we were waiting to start talking until zoom finishes, do it now
                    if r._pendingTalkAfterZoom then
                        r._pendingTalkAfterZoom = false
                        local curNow = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                        if curNow and curNow.isPlaying and curNow:isPlaying() then
                            r._animState = "talk"
                            r._talkPhase = "talk"
                            if r.UpdateTalkAnimation then r:UpdateTalkAnimation() end
                        else
                            -- If playback just started, don't flicker to idle due to timing
                            local cur2 = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                            local inGrace = false
                            if cur2 and cur2.startTime and GetTime then
                                local dt = GetTime() - (cur2.startTime or 0)
                                inGrace = dt >= 0 and dt < 0.6
                            end
                            if not inGrace and r.SetIdleLoop then r:SetIdleLoop() end
                        end
                    end
                end
            end

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
                if f.SetAnimation then pcall(f.SetAnimation, f, talkId) end
                if f.SetSheathed then pcall(f.SetSheathed, f, true) end
                if r then
                    r._animState = "talk"
                    r._lastTalkId = talkId
                    -- Start the loop quickly if not already
                    if r.StartEmoteLoop then r:StartEmoteLoop() end
                end
            else
                if f.SetAnimation then pcall(f.SetAnimation, f, 0) end
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
        if m.SetSheathed then pcall(m.SetSheathed, m, true) end
        pcall(m.SetAnimation, m, talkId)
        self._animState = "talk"
        self._lastTalkId = talkId
    end
end

-- Public: update model animation based on current playback state
function ReplayFrame:UpdateConversationAnimation()
    if not (self.NpcModelFrame and self.NpcModelFrame:IsShown()) then return end
    if self.Director and self.Director.OnPlaybackUpdate then
        self.Director:OnPlaybackUpdate()
    end
    
    -- Fallback: if Director didn't handle it, ensure we start talk animation
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    if cur and cur.isPlaying and cur:isPlaying() and not self._emoteActive and not self._emoteLoopActive then
        -- No emote system is active but audio is playing - start talk animation immediately
        -- Use enhanced greeting detection that includes ChooseTalkAnimIdForText analysis
        local shouldWave = false
        if cur.title and self.HasGreetingInFirstWords then
            shouldWave = self:HasGreetingInFirstWords(cur.title, 10)
        end
        
        -- Immediately set animation on model frame to avoid idle delay
        local m = self.NpcModelFrame
        if m and m.SetAnimation then
            local talkId = 60
            if self.ChooseTalkAnimIdForText and cur and cur.title then
                talkId = self:ChooseTalkAnimIdForText(cur.title)
            end
            if self._animState ~= "talk" or self._lastTalkId ~= talkId then
                pcall(m.SetAnimation, m, talkId)
            end
            if m.SetSheathed then pcall(m.SetSheathed, m, true) end
            self._animState = "talk"
            self._lastTalkId = talkId
        end
        
        if shouldWave and self.PlayEmote then
            -- Play wave for detected greetings (even late-detected ones)
            self:PlayEmote("wave", { duration = 1.5, waveZoom = 0.3, waveOutDur = 0.2, zoomBackDur = 0.5 })
        else
            -- No greeting: start with talk animation
            if self.PlayEmote then 
                self:PlayEmote("talk")
            end
            if self.StartEmoteLoop then 
                self:StartEmoteLoop()
            end
        end
    end
end

-- Public: when conversation stops, revert to idle
function ReplayFrame:OnConversationStop()
    -- Let the Director handle any farewell emote before we fully reset/hide
    if self.Director and self.Director.Stop then self.Director:Stop() end
    -- Keep model idling so bye/hello can play; a later timer may hide it
    self:SetIdleLoop()
    -- Stop emote loop and generic camera animations; do NOT cancel a potential farewell sequence
    if self.StopEmoteLoop then self:StopEmoteLoop() end
    if self.AnimStop then self:AnimStop("zoom"); self:AnimStop("pan") end
    -- Do not clear emote sequence flags here; allow brief farewell to complete
    -- Do not hard hide the model here; Director may play brief emote
end

-- Start a zoom from the current zoom (or provided from) to target over duration seconds
function ReplayFrame:StartZoom(from, to, duration)
    if not (self.NpcModelFrame and self.NpcModelFrame.SetPortraitZoom) then return end
    self._zoomFrom = from or self._zoomFrom or 0.3
    self._zoomTo = to or 0.65
    self._zoomDuration = duration or 0.6
    self._zoomElapsed = 0
    self._zoomAnimActive = true
    pcall(self.NpcModelFrame.SetPortraitZoom, self.NpcModelFrame, self._zoomFrom)
end

function ReplayFrame:StartZoomTo(target, duration)
    local from = self._currentZoom or 0.3
    if self.NpcModelFrame and self.NpcModelFrame.GetPortraitZoom then
        local ok, current = pcall(self.NpcModelFrame.GetPortraitZoom, self.NpcModelFrame)
        if ok and type(current) == "number" then from = current end
    end
    self:StartZoom(from, target, duration)
end

-- Animate the vertical position to a target Z over duration seconds
function ReplayFrame:StartVerticalOffset(fromZ, toZ, duration)
    if not (self.NpcModelFrame and self.NpcModelFrame.SetPosition) then return end
    self._posFromZ = (fromZ ~= nil) and fromZ or (self._currentZOffset or self.modelZOffset or 0)
    self._posToZ = (toZ ~= nil) and toZ or (self.modelZOffset or 0)
    self._posDuration = duration or 0.25
    self._posElapsed = 0
    self._posAnimActive = true
    pcall(self.NpcModelFrame.SetPosition, self.NpcModelFrame, 0, 0, self._posFromZ)
    self._currentZOffset = self._posFromZ
end

function ReplayFrame:StartVerticalOffsetTo(targetZ, duration)
    local fromZ = self._currentZOffset or self.modelZOffset or 0
    self:StartVerticalOffset(fromZ, targetZ, duration)
end

-- Utility: fully reset animation-related state so a new conversation can wave again
function ReplayFrame:ResetAnimationState()
    self._lastTalkId = nil
    self._animState = nil
    self._cadenceActive = false -- legacy
    self._playTime = 0
    self._phaseTime = 0
    self._talkPhase = nil
    self._zoomAnimActive = false
    self._posAnimActive = false
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
