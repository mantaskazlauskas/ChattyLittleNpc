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

    -- Ensure we react to the display frame visibility to stop model rendering off-screen
    if frame and not self._hookedDisplayFrame then
        if frame.HookScript then
            frame:HookScript("OnHide", function()
                -- Hide and clear model to avoid rendering costs while window is hidden
                if self.NpcModelFrame then
                    if self.NpcModelFrame.ClearModel then pcall(self.NpcModelFrame.ClearModel, self.NpcModelFrame) end
                    self.NpcModelFrame:Hide()
                end
                if self.ModelContainer then self.ModelContainer:Hide() end
                if self.ResetAnimationState then self:ResetAnimationState() end
            end)
            frame:HookScript("OnShow", function()
                -- Re-evaluate model only when window becomes visible
                if self.CheckAndShowModel then self:CheckAndShowModel() end
            end)
        end
        self._hookedDisplayFrame = true
    end

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
    -- Skip any model work if the window itself is hidden
    if self.DisplayFrame and self.DisplayFrame.IsShown and (not self.DisplayFrame:IsShown()) then
        if self.ModelContainer then self.ModelContainer:Hide() end
        self.NpcModelFrame:Hide()
        return
    end
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
        if isPlaying then
            local talkId = 60
            if self.ChooseTalkAnimIdForText and cur and cur.title then
                talkId = self:ChooseTalkAnimIdForText(cur.title)
            end
            -- Set initial talk animation; let FSM start the loop/camera
            self:SetModelAnim(talkId)
        else
            self:SetModelAnim(0) -- Idle
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
    -- Do nothing if the window is hidden
    if self.DisplayFrame and self.DisplayFrame.IsShown and (not self.DisplayFrame:IsShown()) then
        if (self.NpcModelFrame) then self.NpcModelFrame:Hide() end
        if (self.ModelContainer) then self.ModelContainer:Hide() end
        return
    end
    if (not self:IsCompactModeEnabled() and self:IsVoiceoverCurrenltyPlaying() and currentlyPlaying.npcId) then
    self:UpdateNpcModelDisplay(currentlyPlaying.npcId)
    -- Don't call UpdateConversationAnimation here - let the OnShow hook handle it
    -- to avoid duplicate calls when the model becomes visible
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug() then 
            CLN.Utils:LogAnimDebug("CheckAndShowModel - showing model, letting OnShow hook handle animation")
        end
    else
        if (self.NpcModelFrame) then self.NpcModelFrame:Hide() end
        if (self.ModelContainer) then self.ModelContainer:Hide() end
        if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug() then
            CLN.Utils:LogAnimDebug("CheckAndShowModel - hiding model")
        end
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

            -- Conversation emote loop is now external and timer-driven; no per-frame checks

            -- Some models stop animating after loads; poke idle periodically only when idling
            if frame.SetAnimation and ((r._lastAppliedAnimId == 0) or not sameHandle) then
                frame._poke = (frame._poke or 0) + (elapsed or 0)
                if frame._poke > 4.0 then
                    pcall(frame.SetAnimation, frame, 0)
                    frame._poke = 0
                end
            end

            -- One-shot animation finish watcher: only while visible and flagged
            if r._watchAnimActive and frame.IsShown and frame:IsShown() then
                -- Use timeout as a safety; WoW API lacks a universal IsAnimationFinished
                local nowT = (type(GetTime) == "function") and GetTime() or 0
                local started = tonumber(r._watchStartedAt or 0) or 0
                local timeout = tonumber(r._watchTimeout or 0) or 0
                local timedOut = (timeout > 0) and ((nowT - started) >= timeout)
                local animDone = false
                -- If GetModelAnimation exists, try to detect switch back to idle/talk
                if frame.GetAnimation then
                    local ok, current = pcall(frame.GetAnimation, frame)
                    if ok and type(current) == "number" then
                        if current ~= r._watchAnimId then
                            animDone = true
                        end

                        -- Safety: if we expect a talk animation but the model isn't playing it, reapply occasionally
                        if frame.SetAnimation and r and r._lastAppliedAnimId and (r._lastAppliedAnimId == 60 or r._lastAppliedAnimId == 64 or r._lastAppliedAnimId == 65) then
                            frame._talkPoke = (frame._talkPoke or 0) + (elapsed or 0)
                            if frame._talkPoke > 1.2 then
                                frame._talkPoke = 0
                                if frame.GetAnimation then
                                    local ok, curAnim = pcall(frame.GetAnimation, frame)
                                    if ok and type(curAnim) == "number" and curAnim ~= r._lastAppliedAnimId then
                                        pcall(frame.SetAnimation, frame, r._lastAppliedAnimId)
                                        if frame.SetSheathed then pcall(frame.SetSheathed, frame, true) end
                                    end
                                end
                            end
                        end
                    end
                end
                if timedOut or animDone then
                    -- Clear watcher first
                    r._watchAnimActive = false
                    r._watchAnimId = nil
                    r._watchStartedAt = nil
                    r._watchTimeout = nil
                    -- If playback is ongoing, resume talk and ensure loop is running
                    local stillPlaying = cur and cur.isPlaying and cur:isPlaying()
                    if stillPlaying then
                        if r.UpdateTalkAnimation then r:UpdateTalkAnimation() end
                        if r.StartEmoteLoop then r:StartEmoteLoop() end
                    end
                    if r._UpdateModelOnUpdateHook then r:_UpdateModelOnUpdateHook() end
                end
            end
        end
    end

    -- Hook model frame lifecycle for the update
    if not m._hookedAnim then
        m:HookScript("OnShow", function(f)
            -- Record first visible time for timing-sensitive decisions (e.g., greeting wave)
            if type(GetTime) == "function" then
                ReplayFrame._modelBecameVisibleAt = GetTime()
            else
                ReplayFrame._modelBecameVisibleAt = (ReplayFrame._modelBecameVisibleAt or 0)
            end
            -- Initialize timers; OnUpdate will be attached only if needed via gate
            f._t = 0; f._poke = 0
            if ReplayFrame and ReplayFrame._UpdateModelOnUpdateHook then ReplayFrame:_UpdateModelOnUpdateHook() end

            -- Do not force idle; choose animation based on current playback immediately
            local r = ReplayFrame
            local cur = CLN and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            local isPlaying = cur and cur.isPlaying and cur:isPlaying()
            if isPlaying then
                local talkId = 60
                if r and r.ChooseTalkAnimIdForText and cur.title then
                    talkId = r:ChooseTalkAnimIdForText(cur.title)
                end
                -- Set base anim, defer loop and camera to FSM
                r:SetModelAnim(talkId)
            else
                r:SetModelAnim(0)
            end

            -- Let the Director refine (wave vs talk) as needed
            if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug() then
                CLN.Utils:LogAnimDebug("ModelFrame OnShow hook - calling UpdateConversationAnimation")
            end
            if r and r.UpdateConversationAnimation then r:UpdateConversationAnimation() end
        end)
        m:HookScript("OnHide", function(f)
            if f.SetScript then f:SetScript("OnUpdate", nil) end
            if ReplayFrame and ReplayFrame.ResetAnimationState then
                ReplayFrame:ResetAnimationState()
            end
            ReplayFrame._modelBecameVisibleAt = nil
        end)
        m._hookedAnim = true
    end

    -- If already shown, start updates immediately
    if m:IsShown() and self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
end

-- =========================
-- OnUpdate gating helpers
-- =========================

-- Determine if the model needs a per-frame OnUpdate (active anims or emote loop)
function ReplayFrame:_ModelNeedsOnUpdate()
    local m = self.NpcModelFrame
    if not (m and m.IsShown and m:IsShown()) then return false end
    if self._anims and #self._anims > 0 then return true end
    -- Need updates while watching for a one-shot animation to finish
    if self._watchAnimActive then return true end
    -- Keep updates while our emote loop is active to guard talk animations from dropping
    if self._emoteLoopActive then return true end
    -- If we expect talk (cached id) keep lightweight updates for safety reapply
    if self._lastAppliedAnimId == 60 or self._lastAppliedAnimId == 64 or self._lastAppliedAnimId == 65 then return true end
    return false
end

-- Attach/detach the model's OnUpdate based on current needs
function ReplayFrame:_UpdateModelOnUpdateHook()
    local m = self.NpcModelFrame
    if not m then return end
    -- Ensure update function exists
    if not m._animOnUpdate then
        if self.SetupModelAnimations then self:SetupModelAnimations() end
    end
    local need = self:_ModelNeedsOnUpdate()
    local isAttached = m.GetScript and (m:GetScript("OnUpdate") ~= nil)
    
    -- Log only when state changes to avoid spam
    do
        local count = (self._anims and #self._anims or 0)
        local last = self._lastUpdateHookState or {}
        if last.need ~= need or last.attached ~= isAttached or last.count ~= count then
            CLN.Utils:LogAnimDebug("_UpdateModelOnUpdateHook: need=" .. tostring(need) .. ", isAttached=" .. tostring(isAttached) .. ", anims=" .. tostring(count))
            self._lastUpdateHookState = { need = need, attached = isAttached, count = count }
        end
    end
    
    if need and not isAttached and m._animOnUpdate and m.SetScript then
        CLN.Utils:LogAnimDebug("Attaching OnUpdate handler to model")
        m:SetScript("OnUpdate", m._animOnUpdate)
    elseif (not need) and isAttached and m.SetScript then
        CLN.Utils:LogAnimDebug("Detaching OnUpdate handler from model")
        m:SetScript("OnUpdate", nil)
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
    return ReplayFrame.Pure.ChooseTalkAnimIdForText(text)
end

function ReplayFrame:SetIdleLoop()
    local m = self.NpcModelFrame
    if not m then return end
    self:SetModelAnim(0)
end

-- Play a one-shot wave at the start of a new sound handle
function ReplayFrame:MaybePlayStartWave()
    local m = self.NpcModelFrame
    if not m then return end
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local handle = cur and cur.soundHandle or nil
    if not handle then return end
    -- Only trigger on a fresh start (new handle) and avoid late triggers
    if self._lastSoundHandle == handle then return end
    -- Skip wave for quest audio (often mid-sentence or UI-triggered)
    if cur and cur.questId then
        self._lastSoundHandle = handle
    -- start the talk animation path directly for quests
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
    if self._lastAppliedAnimId ~= talkId then
        self:SetModelAnim(talkId)
    end
end

-- Public: update model animation based on current playback state
function ReplayFrame:UpdateConversationAnimation()
    -- Only act when model is visible to avoid hidden-frame churn
    if not (self.NpcModelFrame and self.NpcModelFrame:IsShown()) then 
        -- if CLN.Utils and CLN.Utils.LogAnimDebug then CLN.Utils:LogAnimDebug("UpdateConversationAnimation - ModelFrame not shown") end
        return 
    end

    -- Debounce per handle/title to avoid re-triggering every frame
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local handle = cur and cur.soundHandle or nil
    local title = cur and cur.title or nil
    local nowT = GetTime and GetTime() or 0
    if handle and self._lastAnimDecision and self._lastAnimDecision.handle == handle 
        and self._lastAnimDecision.title == title then
        -- If we just decided very recently (< 0.2s), skip
        if (nowT - (self._lastAnimDecision.t or 0)) < 0.2 then
            return
        end
    end

    -- Drive via the centralized FSM
    local recentlyStarted = false
    if cur and cur.startTime and GetTime then
        local dt = nowT - (cur.startTime or 0)
        recentlyStarted = dt >= 0 and dt < 0.6
        if CLN.Utils:ShouldLogAnimDebug() then 
            CLN.Utils:LogAnimDebug("UpdateConversationAnimation - title: " .. tostring(title or "nil") .. ", dt: " .. tostring(dt) .. ", recent: " .. tostring(recentlyStarted))
        end
    end
    
    if cur and ( (cur.isPlaying and cur:isPlaying()) or recentlyStarted ) then
        if self.FSM_OnPlaybackStart then self:FSM_OnPlaybackStart(cur) end
    else
        local lastMsg = self.Director and self.Director._lastMsg or title
        if self.FSM_OnPlaybackStop then self:FSM_OnPlaybackStop(lastMsg) end
    end
    if self.FSM_Tick then self:FSM_Tick() end

    -- Record last decision context/time
    self._lastAnimDecision = { handle = handle, title = title, t = nowT }
end

-- Public: when conversation stops, revert to idle
function ReplayFrame:OnConversationStop()
    -- Don't run stop/farewell animations if the model isn't visible
    if not (self.NpcModelFrame and self.NpcModelFrame:IsShown()) then
        self:ResetAnimationState()
        return
    end
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
    -- Cancel any scripted emote sequence that might be running
    self._emoteSeqActive = false
    self._emoteActive = false
    self._emoteName = nil
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
    -- Query current animation if available to avoid false "already applied" when it didn't take
    local curAnim
    if m.GetAnimation then
        local ok, a = pcall(m.GetAnimation, m)
        if ok and type(a) == "number" then curAnim = a end
    end
    -- Skip only if both our cached value and the model's actual state match
    if self._lastAppliedAnimId == animId and curAnim == animId then return end
    pcall(m.SetAnimation, m, animId)
    if m.SetSheathed then pcall(m.SetSheathed, m, true) end
    if m.SetPaused then pcall(m.SetPaused, m, false) end
    self._lastAppliedAnimId = animId

    -- Start/stop one-shot finish watcher for specific non-looping emotes when visible
    local visible = m and m.IsShown and m:IsShown()
    local isOneShot = (animId == 67) or (animId == 185) or (animId == 186)
    if visible and isOneShot then
        self._watchAnimActive = true
        self._watchAnimId = animId
        self._watchStartedAt = (type(GetTime) == "function") and GetTime() or 0
        local cfg = (ReplayFrame.Config and ReplayFrame.Config.Timings) or {}
        self._watchTimeout = tonumber(cfg.oneShotWatchTimeout) or 2.0
        if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
    else
        -- Clear watcher when switching away or hidden
        self._watchAnimActive = false
        self._watchAnimId = nil
        self._watchStartedAt = nil
        self._watchTimeout = nil
        if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
    end
end

-- Intent wrappers to keep FSM boundary clear (no-op if FSM not present)
function ReplayFrame:OnPlaybackStart(cur)
    if self.FSM_OnPlaybackStart then self:FSM_OnPlaybackStart(cur) end
end

function ReplayFrame:OnPlaybackStop(msg)
    if self.FSM_OnPlaybackStop then self:FSM_OnPlaybackStop(msg) end
end
