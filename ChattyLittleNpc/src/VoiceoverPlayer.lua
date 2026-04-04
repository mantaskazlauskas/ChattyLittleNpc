---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class VoiceoverPlayer
local VoiceoverPlayer = {}
CLN.VoiceoverPlayer = VoiceoverPlayer

-- ============================================================================
-- Gossip Cooldown
-- ============================================================================

-- Session-local table: hash → GetTime() timestamp of last playback
VoiceoverPlayer._gossipCooldowns = {}

VoiceoverPlayer.State = {
    IDLE = "idle",
    QUEUED = "queued",
    PLAYING = "playing",
    PAUSED_USER = "paused_user",
    PAUSED_NATIVE = "paused_native",
    TEXT_CONTINUING = "text_continuing",
    SUSPENDED = "suspended",
    COMPLETED = "completed",
    DROPPED = "dropped",
}

--- Derive a best-guess state from structural fields for records that were never
--- given an explicit state. After Phase 3 this is only a safety net — all live
--- records receive explicit state via SetPlaybackState.
local function DerivePlaybackState(self, record)
    if not record then return VoiceoverPlayer.State.IDLE end
    if record._textContinuation then
        return VoiceoverPlayer.State.TEXT_CONTINUING
    end
    if record.soundHandle then
        local isActuallyPlaying = true
        if type(record.isPlaying) == "function" then
            isActuallyPlaying = record:isPlaying()
        elseif C_Sound and type(C_Sound.IsPlaying) == "function" then
            isActuallyPlaying = C_Sound.IsPlaying(record.soundHandle)
        end
        if isActuallyPlaying then
            return VoiceoverPlayer.State.PLAYING
        end
    end
    if record == self._suspendedPlayback then
        return VoiceoverPlayer.State.SUSPENDED
    end
    if record.questId or record.title then
        return VoiceoverPlayer.State.QUEUED
    end
    return VoiceoverPlayer.State.IDLE
end

--- Get the canonical playback state of a record.
--- Explicit state (set via SetPlaybackState) is authoritative.
--- DerivePlaybackState is only consulted for records without explicit state.
function VoiceoverPlayer:GetPlaybackState(record)
    local target = record or self.currentlyPlaying
    if not target then return self.State.IDLE end
    if target.state and target.state ~= self.State.IDLE then
        return target.state
    end
    return DerivePlaybackState(self, target)
end

function VoiceoverPlayer:SetPlaybackState(record, state)
    if not record then return end
    record.state = state
end

function VoiceoverPlayer:IsPlaybackStateActive(state)
    return state == self.State.PLAYING
        or state == self.State.PAUSED_USER
        or state == self.State.PAUSED_NATIVE
        or state == self.State.TEXT_CONTINUING
end

function VoiceoverPlayer:IsPlaybackActive(record)
    return self:IsPlaybackStateActive(self:GetPlaybackState(record))
end

function VoiceoverPlayer:IsTemporarilyPaused(record)
    return self:GetPlaybackState(record) == self.State.PAUSED_NATIVE
end

--- Check whether any of the given hashes are still on cooldown.
--- Expiry is checked lazily on access — no background timer needed.
---@param hashes string[]
---@return boolean
function VoiceoverPlayer:IsGossipOnCooldown(hashes)
    if not CLN.db or not CLN.db.profile or not CLN.db.profile.gossipCooldownEnabled then return false end
    local cooldownMinutes = CLN.db.profile.gossipCooldownMinutes or 0
    local now = GetTime and GetTime() or 0

    for _, hash in ipairs(hashes) do
        local lastPlayed = self._gossipCooldowns[hash]
        if lastPlayed then
            if cooldownMinutes == 0 then
                -- 0 = infinite / entire session
                return true
            end
            if (now - lastPlayed) < (cooldownMinutes * 60) then
                return true
            end
            -- Expired — clean up lazily
            self._gossipCooldowns[hash] = nil
        end
    end
    return false
end

--- Record that a gossip line was just played.
---@param hashes string[]
function VoiceoverPlayer:RecordGossipCooldown(hashes)
    if not CLN.db or not CLN.db.profile or not CLN.db.profile.gossipCooldownEnabled then return end
    local now = GetTime and GetTime() or 0
    for _, hash in ipairs(hashes) do
        self._gossipCooldowns[hash] = now
    end
end

--- Returns true when text contains more than one paragraph.
--- Multi-paragraph gossip (lore, long dialogue) is exempt from cooldown.
---@param text string|nil
---@return boolean
function VoiceoverPlayer:_IsMultiParagraph(text)
    if not text or type(text) ~= "string" then return false end
    local normalized = text:gsub("|n", "\n")
    return normalized:find("\n\n") ~= nil
end

-- ============================================================================
-- Queue Integrity Helpers
-- ============================================================================
--- Check if currentlyPlaying matches the quest/phase and is actively held.
---@param questId number
---@param phase string
---@return boolean
function VoiceoverPlayer:IsCurrentQuestPhaseActive(questId, phase)
    if not (questId and phase) then return false end
    local cp = VoiceoverPlayer.currentlyPlaying
    if not cp or cp.questId ~= questId or cp.phase ~= phase then
        return false
    end

    return self:IsPlaybackActive(cp)
end

--- Check if a quest/phase combo is already queued.
---@param questId number
---@param phase string
---@return boolean isQueued, number index
function VoiceoverPlayer:IsQuestPhaseQueued(questId, phase)
    if not (questId and phase) then return false end
    -- Check currently playing item too (not just the queue)
    if self:IsCurrentQuestPhaseActive(questId, phase) then
        return true, 0
    end
    for i, q in ipairs(CLN.questsQueue) do
        if q.questId == questId and q.phase == phase then
            return true, i
        end
    end
    return false
end

--- Build a stable identity key for a queue/current-playback entry.
---@param entry table|nil
---@return string|nil
function VoiceoverPlayer:GetQueueEntryKey(entry)
    if not entry then return nil end
    if entry.questId and entry.phase then
        return "quest|" .. tostring(entry.questId) .. "|" .. tostring(entry.phase)
    end
    if entry.npcId and entry.entryType and entry.title then
        return "nonquest|"
            .. tostring(entry.entryType) .. "|"
            .. tostring(entry.npcId) .. "|"
            .. tostring(entry.gender or "") .. "|"
            .. tostring(entry.title)
    end
    return nil
end

--- Deduplicate the queue, removing entries that match currently playing or are duplicated.
function VoiceoverPlayer:DeduplicateQueue()
    if not CLN.questsQueue then return end
    local seen = {}
    local cp = VoiceoverPlayer.currentlyPlaying
    local removedAny = false
    local currentKey = self:GetQueueEntryKey(cp)
    if currentKey then
        seen[currentKey] = true
    end
    for i = #CLN.questsQueue, 1, -1 do
        local q = CLN.questsQueue[i]
        local key = self:GetQueueEntryKey(q)
        if key and seen[key] then
            table.remove(CLN.questsQueue, i)
            removedAny = true
        elseif key then
            seen[key] = true
        end
    end
    if removedAny and CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then
        CLN.ReplayFrame:MarkQueueDirty()
    end
end

--- Remove a queued quest entry by identity.
---@param questId number|nil
---@param phase string|nil
---@return boolean removed
function VoiceoverPlayer:RemoveQueuedQuestEntry(questId, phase)
    if not (questId and phase and CLN.questsQueue) then return false end
    for i, q in ipairs(CLN.questsQueue) do
        if q.questId == questId and q.phase == phase then
            table.remove(CLN.questsQueue, i)
            return true
        end
    end
    return false
end

function VoiceoverPlayer:GetDisplayEntries()
    local entries = {}
    local cp = self.currentlyPlaying
    local currentState = self:GetPlaybackState(cp)
    local currentKey = nil

    if cp and not cp._historyPushed and (cp.title or cp.questId) and self:IsPlaybackStateActive(currentState) then
        currentKey = self:GetQueueEntryKey(cp)
        table.insert(entries, {
            kind = "current",
            state = currentState,
            isPlaying = true,
            questId = cp.questId,
            phase = cp.phase,
            npcId = cp.npcId,
            title = cp.title,
            gender = cp.gender,
            displayID = cp.displayID,
            entryType = cp.entryType or (cp.questId and "quest" or "unknown"),
        })
    end

    if CLN.questsQueue then
        for i, q in ipairs(CLN.questsQueue) do
            local queueKey = self:GetQueueEntryKey(q)
            if not (currentKey and queueKey and currentKey == queueKey) then
                local state = self:GetPlaybackState(q)
                if state == self.State.IDLE then
                    state = self.State.QUEUED
                end
                table.insert(entries, {
                    kind = "queue",
                    state = state,
                    queueIndex = i,
                    questId = q.questId,
                    phase = q.phase,
                    npcId = q.npcId,
                    title = q.title,
                    gender = q.gender,
                    displayID = q.displayID,
                    entryType = q.entryType or ((q.questId and q.phase) and "quest" or "unknown"),
                })
            end
        end
    end

    return entries
end

function VoiceoverPlayer:GetCurrentlyPlayingObject()
    return {
        cantBeInterrupted = nil,
        npcId = nil,
        gender = nil,
        displayID = nil,
        creatureType = nil,
        entryType = nil,
        phase = nil,
        questId = nil,
        soundHandle = nil,
        state = VoiceoverPlayer.State.IDLE,
        title = nil,
        isPlaying = function (self)
            if self.soundHandle and C_Sound and type(C_Sound.IsPlaying) == "function" then
                return C_Sound.IsPlaying(self.soundHandle)
            end
            -- Fallback for clients without C_Sound (e.g. BC Anniversary):
            -- trust the explicit state, but use estimated duration to detect
            -- natural completion so the watcher can advance the queue.
            if self.soundHandle and self.state == VoiceoverPlayer.State.PLAYING then
                if self.startTime and self._estimatedDuration and GetTime then
                    local elapsed = GetTime() - self.startTime
                    if elapsed > self._estimatedDuration * 1.3 then
                        return false
                    end
                end
                return true
            end
            return false
        end,
    }
end

VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()
VoiceoverPlayer.queueProcessed = false
VoiceoverPlayer._suspendedPlayback = nil

--- Look up the pre-computed duration (in seconds) for a voiceover filename
--- from the voiceover pack's VoiceoverDurations table.
---@param fileName string  The .ogg filename (e.g. "5741_Desc.ogg")
---@return number|nil duration  Seconds, or nil if not available
function VoiceoverPlayer:LookupFileDuration(fileName)
    if not fileName then return nil end
    for _, packData in pairs(CLN.VoiceoverPacks) do
        if packData.VoiceoverDurations then
            local dur = packData.VoiceoverDurations[fileName]
            if dur then return dur end
        end
    end
    return nil
end

--- Get the best available duration for a voiceover entry.
--- Prefers pack-provided duration, falls back to text-based estimate.
---@param fileName string|nil  The .ogg filename to look up
---@param fallbackText string|nil  Text to estimate from if no pack duration
---@return number|nil duration  Seconds, or nil if nothing available
---@return boolean isPackDuration  True if the duration came from a voiceover pack
function VoiceoverPlayer:GetBestDuration(fileName, fallbackText)
    local packDur = self:LookupFileDuration(fileName)
    if packDur then return packDur, true end
    if fallbackText and CLN.Utils and CLN.Utils.EstimateVODuration then
        return CLN.Utils.EstimateVODuration(fallbackText), false
    end
    return nil, false
end

--- Look up the quest body text from NpcInfoDB for a playing/queued entry.
--- Returns the full dialogue text that the voiceover audio is based on,
--- which is far more accurate for duration estimation than the quest title.
---@param cp table  A currentlyPlaying or queue entry with npcId, questId, phase.
---@return string|nil bodyText  The full quest dialogue, or nil if unavailable.
function VoiceoverPlayer:GetQuestBodyText(cp)
    if not (cp and cp.npcId and cp.questId and cp.phase) then return nil end
    if not (_G.NpcInfoDB and CLN.locale) then return nil end
    local npcData = _G.NpcInfoDB[cp.npcId]
    if not npcData then return nil end
    local localeData = npcData[CLN.locale]
    if not localeData or not localeData.quests then return nil end
    local questData = localeData.quests[cp.questId]
    if not questData then return nil end
    local phaseFields = { Desc = "quest_detail", Prog = "quest_progress", Comp = "quest_complete" }
    local field = phaseFields[cp.phase]
    if not field then return nil end
    local text = questData[field]
    if not text or text == "" then return nil end
    return text
end

-- ============================================================================
-- Centralized History Push
-- ============================================================================
--- Push a record to replay history. Accepts a currentlyPlaying object, a queue
--- entry, a suspended-playback table, or any table with at least a title or
--- questId.  Normalizes the fields so callers don't need to worry about shape.
---@param record table Any voiceover record (currentlyPlaying, queue item, etc.)
function VoiceoverPlayer:PushToHistory(record)
    if not record then return end
    if record._historyPushed then return end
    -- Resolve title: prefer explicit, fall back to questId lookup
    local title = record.title
    if not title and record.questId then
        title = CLN.GetTitleForQuestID and CLN:GetTitleForQuestID(record.questId) or nil
    end
    -- Must have *something* identifiable
    if not title and not record.questId then return end

    if CLN.ReplayFrame and CLN.ReplayFrame.PushHistory then
        record._historyPushed = true
        local historyEntry = {
            title = title,
            npcId = record.npcId,
            questId = record.questId,
            phase = record.phase,
            entryType = record.entryType or (record.questId and "quest" or "unknown"),
            state = record.state or self:GetPlaybackState(record),
            gender = record.gender,
            displayID = record.displayID,
            completedAt = GetTime and GetTime() or 0,
        }
        -- Enrich with cached metadata so replays have full model info
        if CLN.NpcMetadataCache and CLN.NpcMetadataCache.Enrich then
            CLN.NpcMetadataCache:Enrich(historyEntry)
        end
        CLN.ReplayFrame:PushHistory(historyEntry)
    end
end

-- Grace period: consider a sound "still playing" if it started recently,
-- even when C_Sound.IsPlaying briefly returns false during frame transitions.
local PLAYBACK_GRACE_SEC = 0.6
-- Extended grace from last watcher confirmation (watcher runs every 0.5s)
local WATCHER_GRACE_SEC = 1.5
-- Hard timeout: if a sound has been "playing" for this long without watcher
-- confirmation, consider it stuck and let the queue advance.
local MAX_UNCONFIRMED_SEC = 30
function VoiceoverPlayer:IsEffectivelyPlaying()
    local cp = self.currentlyPlaying
    if self:IsNativeVOPauseActive() then return true end
    if not cp or not cp.soundHandle then return false end
    if cp.isPlaying and cp:isPlaying() then return true end
    -- Hard timeout: if started long ago and watcher never confirmed, give up
    if cp.startTime and GetTime then
        local elapsed = GetTime() - cp.startTime
        if elapsed > MAX_UNCONFIRMED_SEC and not cp._lastConfirmedPlayingAt then
            return false
        end
    end
    -- Fallback 1: treat the sound as playing within startup grace window
    if cp.startTime and GetTime then
        local elapsed = GetTime() - cp.startTime
        if elapsed >= 0 and elapsed < PLAYBACK_GRACE_SEC then return true end
    end
    -- Fallback 2: watcher recently confirmed this sound was playing;
    -- survives transient C_Sound.IsPlaying false blips during dialog transitions
    if cp._lastConfirmedPlayingAt and GetTime then
        local since = GetTime() - cp._lastConfirmedPlayingAt
        if since >= 0 and since < WATCHER_GRACE_SEC then return true end
    end
    return false
end

-- Clear the queue from quests and stop current audio.
---@param clearQueue boolean|nil If true, clears queued quests
---@param force boolean|nil If true, bypass queue-mode protection (used by cinematics/movies)
function VoiceoverPlayer:ForceStopCurrentSound(clearQueue, force)
    if CLN and CLN.Logger then CLN.Logger:debug("Force stopping current sound", false, CLN.Utils.LogCategories.loader) end

    -- In queue mode, ignore external stop requests (e.g., DialogueUI closing)
    -- unless the caller explicitly forces it (cinematics, movies, user stop button).
    if not force and CLN.db and CLN.db.profile and CLN.db.profile.questPlaybackMode == 'queue' then
        if CLN and CLN.Logger then CLN.Logger:debug("Ignoring ForceStop in queue mode", false, CLN.Utils.LogCategories.loader) end
        return
    end

    -- Cancel any pending native VO resume (must be after queue-mode guard
    -- so an "ignored" ForceStop doesn't kill the resume timer)
    self:CancelNativeVOResume()

    -- Record the force-stop time so PlayQuestSound can reject rapid re-triggers
    self._lastForceStopTime = GetTime and GetTime() or 0

    -- Push suspended playback to history before discarding
    if self._suspendedPlayback then
        self:SetPlaybackState(self._suspendedPlayback, self.State.DROPPED)
        self:PushToHistory(self._suspendedPlayback)
        self._suspendedPlayback = nil
    end

    -- Push currently playing to history before stopping
    local cp = VoiceoverPlayer.currentlyPlaying
    if cp and (cp.title or cp.questId) then
        self:SetPlaybackState(cp, self.State.DROPPED)
        self:PushToHistory(cp)
    end

    if (clearQueue) then
        -- Push all queued items to history before clearing
        for _, q in ipairs(CLN.questsQueue) do
            self:SetPlaybackState(q, self.State.DROPPED)
            self:PushToHistory(q)
        end
        CLN.questsQueue = {}
        if CLN.ReplayFrame then CLN.ReplayFrame._scrollOffset = 0 end
        self:NotifyQueueDirty()
    end

    if (cp and cp.soundHandle) then
        StopSound(cp.soundHandle)
    end

    -- Cancel any active text continuation
    if cp and cp._textContinuation then
        if CLN.ReplayFrame and CLN.ReplayFrame.HideSubtitle then
            CLN.ReplayFrame:HideSubtitle()
        end
    end

    -- Deterministic animation cleanup: the polling watcher won't fire
    -- VOICEOVER_STOP because we clear currentlyPlaying below, so call
    -- OnConversationStop explicitly while cp is still available for lastMsg.
    if CLN.ReplayFrame and CLN.ReplayFrame.OnConversationStop then
        CLN.ReplayFrame:OnConversationStop(cp and cp.title)
    end

    -- Clear the currentlyPlaying object
    VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

    self:NotifyDisplayDirty()
end

-- ============================================================================
-- Native VO Pause/Resume
-- ============================================================================
-- Same WoW limitation applies here: the addon sound is *stopped*, not paused.
-- ResumeAfterNativeVO replays the file from the beginning once the native
-- voice-over finishes (see User-Initiated Pause/Resume note above).

--- Temporarily stop addon voiceover to yield to native NPC voice-over.
--- Preserves the currentlyPlaying state so we can replay on resume.
---@param estimatedDuration number Seconds to wait before auto-resuming
function VoiceoverPlayer:PauseForNativeVO(estimatedDuration)
    local cp = self.currentlyPlaying
    if not (cp and cp.soundHandle and cp:isPlaying()) then return end

    if CLN.db.profile.debugMode and CLN.Logger then
        CLN.Logger:debug("Pausing addon VO for native NPC speech (~" .. string.format("%.1f", estimatedDuration) .. "s)",
            false, CLN.Utils.LogCategories.loader)
    end

    -- Stop our sound but keep the state so the watcher doesn't fire VOICEOVER_STOP
    StopSound(cp.soundHandle, 0)
    self:SetPlaybackState(cp, self.State.PAUSED_NATIVE)
    cp.soundHandle = nil -- Clear handle so watcher ignores us

    -- Suspend watcher and history-prune timers while paused
    if CLN.EventHandler and CLN.EventHandler.SuspendTimers then
        CLN.EventHandler:SuspendTimers()
    end

    -- Freeze model animations
    if CLN.ReplayFrame and CLN.ReplayFrame.NpcModelFrame then
        local m = CLN.ReplayFrame.NpcModelFrame
        if m and m.SetScript then m:SetScript("OnUpdate", nil) end
    end

    -- Schedule auto-resume
    if self._nativeVOResumeTimer then
        self._nativeVOResumeTimer:Cancel()
    end
    self._nativeVOResumeTimer = C_Timer.NewTimer(estimatedDuration, function()
        self:ResumeAfterNativeVO()
    end)
end

--- Resume addon voiceover after native VO pause expires.
--- Re-plays the same sound from the beginning (WoW has no seek API).
function VoiceoverPlayer:ResumeAfterNativeVO()
    self._nativeVOResumeTimer = nil
    local cp = self.currentlyPlaying
    if not (cp and self:GetPlaybackState(cp) == self.State.PAUSED_NATIVE) then return end

    -- Resume watcher and history-prune timers
    if CLN.EventHandler and CLN.EventHandler.ResumeTimers then
        CLN.EventHandler:ResumeTimers()
    end

    if CLN and CLN.Logger then
        CLN.Logger:debug("Resuming addon VO after native NPC speech", false, CLN.Utils.LogCategories.loader)
    end

    -- Re-trigger playback for the current entry.
    if cp.entryType == "quest" and cp.questId and cp.phase then
        self.currentlyPlaying = self:GetCurrentlyPlayingObject()
        self:PlayQuestSound(cp.questId, cp.phase, cp.npcId, cp.displayID, cp.gender, cp.creatureType)
    elseif cp.npcId and cp.title and cp.entryType then
        -- Non-quest (gossip/item): resume from the beginning.
        self.currentlyPlaying = self:GetCurrentlyPlayingObject()
        self:PlayNonQuestSound(cp.npcId, cp.entryType, cp.title, cp.gender, cp.displayID, cp.creatureType)
    else
        -- Can't identify the entry; clear state
        self.currentlyPlaying = self:GetCurrentlyPlayingObject()
        self:NotifyDisplayDirty()
    end
end

--- Cancel any pending native VO resume timer (e.g., if user manually stops).
function VoiceoverPlayer:CancelNativeVOResume()
    if self._nativeVOResumeTimer then
        self._nativeVOResumeTimer:Cancel()
        self._nativeVOResumeTimer = nil
    end
    local cp = self.currentlyPlaying
    if cp and self:GetPlaybackState(cp) == self.State.PAUSED_NATIVE then
        -- Resume timers that were suspended during native VO pause
        if CLN.EventHandler and CLN.EventHandler.ResumeTimers then
            CLN.EventHandler:ResumeTimers()
        end
    end
end

--- Returns true while native NPC speech has paused addon playback and resume is pending.
---@return boolean
function VoiceoverPlayer:IsNativeVOPauseActive()
    local cp = self.currentlyPlaying
    return not not (self:IsTemporarilyPaused(cp) or self._nativeVOResumeTimer)
end

--- Extend (or start) the native VO resume timer without re-pausing sound.
--- Called by EventHandler when additional native VO lines arrive while already paused.
---@param duration number Seconds until auto-resume
function VoiceoverPlayer:ExtendNativeVOPause(duration)
    if self._nativeVOResumeTimer then
        self._nativeVOResumeTimer:Cancel()
    end
    self._nativeVOResumeTimer = C_Timer.NewTimer(duration, function()
        self:ResumeAfterNativeVO()
    end)
end

-- ============================================================================
-- User-Initiated Pause/Resume
-- ============================================================================
-- WoW's sound API has no seek or pause capability — StopSound() is the only
-- way to silence a playing file, and PlaySoundFile() always starts from the
-- beginning.  Therefore "pause" actually *stops* the sound and "resume"
-- *replays it from the start*.  The progress bar resets on resume because
-- there is no way to pick up where we left off.

--- Pause playback: stop current sound and freeze queue advancement.
--- Skips pausing if less than 1.5 seconds of estimated playback remain.
function VoiceoverPlayer:PausePlayback()
    if self:IsPaused() then return end

    local cp = self.currentlyPlaying
    local wasNativePaused = cp and self:GetPlaybackState(cp) == self.State.PAUSED_NATIVE

    -- Text continuation mode: pause the subtitle sequence
    if cp and cp._textContinuation then
        self:SetPlaybackState(cp, self.State.PAUSED_USER)
        -- Cancel subtitle timers
        if CLN.ReplayFrame and CLN.ReplayFrame.HideSubtitle then
            CLN.ReplayFrame:HideSubtitle()
        end
        if CLN.EventHandler and CLN.EventHandler.SuspendTimers then
            CLN.EventHandler:SuspendTimers()
        end
        if CLN and CLN.Logger then
            CLN.Logger:debug("Text continuation paused by user", false, CLN.Utils.LogCategories.loader)
        end
        self:NotifyQueueDirty()
        self:NotifyDisplayDirty()
        return
    end

    -- If the VO is almost finished, let it play out instead of pausing.
    -- Only skip when we have a pack-provided duration (accurate); text estimates
    -- are too unreliable for this guard.
    if cp and cp.soundHandle and cp.startTime and cp._hasPackDuration and cp._estimatedDuration and GetTime then
        local elapsed = GetTime() - cp.startTime
        local estimated = cp._estimatedDuration
        if estimated > 0 then
            local remaining = estimated - elapsed
            if remaining >= 0 and remaining < 1.5 then
                if CLN.db.profile.debugMode and CLN.Logger then
                    CLN.Logger:debug("Pause skipped: ~" .. string.format("%.1f", remaining) .. "s remaining", false, CLN.Utils.LogCategories.loader)
                end
                return
            end
        end
    end

    if wasNativePaused then
        self:CancelNativeVOResume()
    end

    -- Store elapsed time so text continuation can estimate where we were
    if cp and cp.startTime and GetTime then
        cp._elapsedAtPause = GetTime() - cp.startTime
    end

    -- Suspend watcher and history-prune timers while paused
    if CLN.EventHandler and CLN.EventHandler.SuspendTimers then
        CLN.EventHandler:SuspendTimers()
    end

    if cp and (cp.soundHandle or wasNativePaused) then
        self:SetPlaybackState(cp, self.State.PAUSED_USER)
        if cp.soundHandle then
            StopSound(cp.soundHandle, 0)
            cp.soundHandle = nil -- hide from watcher so VOICEOVER_STOP doesn't fire
        end
    end

    -- Freeze model animations
    if CLN.ReplayFrame and CLN.ReplayFrame.NpcModelFrame then
        local m = CLN.ReplayFrame.NpcModelFrame
        if m and m.SetScript then m:SetScript("OnUpdate", nil) end
    end

    if CLN and CLN.Logger then
        CLN.Logger:debug("Playback paused by user", false, CLN.Utils.LogCategories.loader)
    end
    self:NotifyQueueDirty()
    self:NotifyDisplayDirty()

    -- Schedule whitelist popupif there are recent NPC speeches to ask about
    if CLN.EventHandler and CLN.EventHandler.ScheduleWhitelistPopup then
        CLN.EventHandler:ScheduleWhitelistPopup()
    end
end

--- Resume playback: clear paused flag and either continue as text or replay audio.
function VoiceoverPlayer:ResumePlayback()
    if not self:IsPaused() then return end

    -- Resume watcher and history-prune timers
    if CLN.EventHandler and CLN.EventHandler.ResumeTimers then
        CLN.EventHandler:ResumeTimers()
    end

    local cp = self.currentlyPlaying
    -- If paused during text continuation, just complete it
    if cp and self:GetPlaybackState(cp) == self.State.PAUSED_USER and cp._textContinuation then
        self:SetPlaybackState(cp, self.State.TEXT_CONTINUING)
        self:CompleteTextContinuation()
        if CLN and CLN.Logger then
            CLN.Logger:debug("Text continuation completed after pause", false, CLN.Utils.LogCategories.loader)
        end
        self:NotifyDisplayDirty()
        return
    end
    -- Try to re-play the paused entry (restarts from beginning)
    if cp and self:GetPlaybackState(cp) == self.State.PAUSED_USER then

        -- Text continuation: if paused near the end, show remaining text
        -- instead of replaying audio from the start.
        -- Only use text continuation when we have a pack-provided duration;
        -- text estimates are too unreliable for progress calculation.
        local threshold = (CLN.db and CLN.db.profile and CLN.db.profile.textContinuationThreshold) or 0.75
        local enabled = not CLN.db or not CLN.db.profile or CLN.db.profile.textContinuationEnabled ~= false
        if enabled and cp._hasPackDuration and cp._elapsedAtPause and cp._estimatedDuration and cp.title then
            local estimated = cp._estimatedDuration
            if estimated > 0 then
                local progress = cp._elapsedAtPause / estimated
                if progress >= threshold and progress < 1.0 then
                    self:StartTextContinuation(cp, progress)
                    if CLN and CLN.Logger then
                        CLN.Logger:debug("Text continuation at " .. string.format("%.0f%%", progress * 100), false, CLN.Utils.LogCategories.loader)
                    end
                    self:NotifyDisplayDirty()
                    return
                end
            end
        end

        -- Normal path: replay audio from the start
        local replayed = self:ReplayPausedEntry(cp)
        if not replayed then
            -- Couldn't replay; push the lost item to history and advance queue
            self:SetPlaybackState(cp, self.State.DROPPED)
            self:PushToHistory(cp)
            self.currentlyPlaying = self:GetCurrentlyPlayingObject()
            self:ProcessQueueAfterResume()
        end
    else
        self:ProcessQueueAfterResume()
    end

    if CLN and CLN.Logger then
        CLN.Logger:debug("Playback resumed by user", false, CLN.Utils.LogCategories.loader)
    end
    self:NotifyDisplayDirty()
end

--- Enter text continuation mode: show remaining sentences as timed subtitles
--- instead of replaying audio from the start.
---@param cp table              The currentlyPlaying object.
---@param progress number       0-1 progress when paused.
function VoiceoverPlayer:StartTextContinuation(cp, progress)
    cp._textContinuation = true
    cp._textContinuationStartTime = GetTime and GetTime() or 0
    self:SetPlaybackState(cp, self.State.TEXT_CONTINUING)

    -- Split text into sentences and find where we left off
    local bodyText = self:GetQuestBodyText(cp)
    local textForSentences = bodyText or cp.title
    local sentences
    if CLN.ReplayFrame and CLN.ReplayFrame.SplitTooltipIntoSentences then
        sentences = CLN.ReplayFrame:SplitTooltipIntoSentences(textForSentences)
    else
        sentences = { textForSentences }
    end

    local startIndex = CLN.Utils.EstimateSentenceAtPosition(sentences, progress)
    -- Ensure at least one sentence is shown
    if startIndex > #sentences then startIndex = #sentences end

    -- Calculate total reading duration for remaining sentences (for progress bar)
    local totalReadDuration = 0
    for i = startIndex, #sentences do
        totalReadDuration = totalReadDuration + (CLN.Utils.EstimateReadDuration(sentences[i]) or 1.5)
    end
    -- Add recap time if applicable
    if startIndex > 1 then totalReadDuration = totalReadDuration + 1.5 end
    cp._textContinuationDuration = totalReadDuration

    self:NotifyQueueDirty()

    -- Show remaining sentences as subtitles with completion callback
    if CLN.ReplayFrame and CLN.ReplayFrame.ShowRemainingSubtitles then
        CLN.ReplayFrame:ShowRemainingSubtitles(sentences, startIndex, function()
            self:CompleteTextContinuation()
        end)
    else
        -- Fallback: no subtitle system available, complete immediately
        self:CompleteTextContinuation()
    end
end

--- Complete text continuation: clean up state and advance the queue.
function VoiceoverPlayer:CompleteTextContinuation()
    local cp = self.currentlyPlaying
    if cp then
        cp._textContinuation = nil
        cp._textContinuationStartTime = nil
        cp._textContinuationDuration = nil
        cp._elapsedAtPause = nil
        self:SetPlaybackState(cp, self.State.COMPLETED)
        self:PushToHistory(cp)
    end

    self.currentlyPlaying = self:GetCurrentlyPlayingObject()
    self:NotifyQueueDirty()
    self:NotifyDisplayDirty()
    self:ProcessQueueAfterResume()

    if CLN and CLN.Logger then
        CLN.Logger:debug("Text continuation completed", false, CLN.Utils.LogCategories.loader)
    end
end

--- Replay a paused entry directly, bypassing queue management.
---@return boolean success
function VoiceoverPlayer:ReplayPausedEntry(cp)
    if not cp then return false end
    local success, newSoundHandle
    local addonsFolderPath = "Interface\\AddOns\\"

    if cp.entryType == "quest" and cp.questId and cp.phase then
        local fileName = cp.questId .. "_" .. cp.phase .. ".ogg"
        local fileLocation = "\\voiceovers\\" .. fileName
        local foundPath = nil
        for packName, packData in pairs(CLN.VoiceoverPacks) do
            local found = (packData._voiceoverIndex and packData._voiceoverIndex[fileName])
                or (CLN.Utils and CLN.Utils.ContainsString and CLN.Utils:ContainsString(packData.Voiceovers, fileName))
            if found then
                foundPath = addonsFolderPath .. packName .. fileLocation
                break
            end
        end
        if foundPath then
            success, newSoundHandle = PlaySoundFile(foundPath, CLN.db.profile.audioChannel)
        end
    elseif cp.npcId and cp.title and cp.entryType then
        local hashes = CLN.Utils:GetHashes(cp.npcId, cp.title)
        local pathToFile = CLN.Utils:GetPathToNonQuestFile(cp.npcId, cp.entryType, hashes, cp.gender)
        if pathToFile and not CLN.Utils:IsNilOrEmpty(pathToFile) then
            success, newSoundHandle = PlaySoundFile(pathToFile, CLN.db.profile.audioChannel)
        end
    end

    if success then
        -- Rebuild currentlyPlaying with the new sound handle, preserving all metadata
        self.currentlyPlaying = self:GetCurrentlyPlayingObject()
        self.currentlyPlaying.soundHandle = newSoundHandle
        self.currentlyPlaying.questId = cp.questId
        self.currentlyPlaying.phase = cp.phase
        self.currentlyPlaying.npcId = cp.npcId
        self.currentlyPlaying.displayID = cp.displayID
        self.currentlyPlaying.title = cp.title
        self.currentlyPlaying.entryType = cp.entryType
        self.currentlyPlaying.gender = cp.gender
        self.currentlyPlaying.creatureType = cp.creatureType
        self.currentlyPlaying.cantBeInterrupted = cp.cantBeInterrupted
        if GetTime then self.currentlyPlaying.startTime = GetTime() end
        -- Store duration: prefer pack-provided, fall back to text estimate
        local replayFileName = cp._voiceoverFileName
            or (cp.questId and cp.phase and (cp.questId .. "_" .. cp.phase .. ".ogg"))
            or nil
        local estBody = self:GetQuestBodyText(self.currentlyPlaying)
        local replayDur, replayIsPack = self:GetBestDuration(replayFileName, estBody or self.currentlyPlaying.title)
        self.currentlyPlaying._estimatedDuration = replayDur
        self.currentlyPlaying._hasPackDuration = replayIsPack
        self.currentlyPlaying._voiceoverFileName = replayFileName
        if CLN.db.profile.debugMode and CLN.Logger then
            CLN.Logger:debug("Replaying: " .. tostring(replayFileName)
                .. " | duration: " .. (replayDur and string.format("%.1fs", replayDur) or "unknown")
                .. (replayIsPack and " (pack)" or " (estimate)"),
                false, CLN.Utils.LogCategories.loader)
        end
        self:SetPlaybackState(self.currentlyPlaying, self.State.PLAYING)
        -- Don't touch the queue — the paused item was never in it
        self:NotifyQueueDirty()
        self:NotifyDisplayDirty()
        if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
            pcall(CLN.ReplayFrame.ResetAnimationState, CLN.ReplayFrame)
        end
        return true
    end
    return false
end

--- If nothing to replay, try to advance the queue, then check suspended.
--- @deprecated Use AdvanceQueue() instead. Kept as a thin wrapper for any
--- callers that haven't migrated yet.
function VoiceoverPlayer:ProcessQueueAfterResume()
    self:AdvanceQueue()
end

-- ============================================================================
-- Centralized Queue Advancement (Phase 1)
-- ============================================================================
--- Single canonical path for popping the next queued item and playing it.
--- Falls back to suspended playback, then to idle + UI refresh.
--- All callers that need "play the next thing" should call this.
function VoiceoverPlayer:AdvanceQueue()
    self:DeduplicateQueue()

    -- Iterative skip of unknown entries (avoids deep recursion on malformed queues)
    while #CLN.questsQueue > 0 do
        local nextItem = CLN.questsQueue[1]
        if nextItem.questId and nextItem.phase then
            -- Clean animation state before starting next item
            if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
                pcall(CLN.ReplayFrame.ResetAnimationState, CLN.ReplayFrame)
            end
            -- PlayQuestSound handles its own queue removal on success
            self:PlayQuestSound(nextItem.questId, nextItem.phase, nextItem.npcId, nextItem.displayID, nextItem.gender, nextItem.creatureType)
            return
        elseif nextItem.npcId and nextItem.title and nextItem.entryType then
            if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
                pcall(CLN.ReplayFrame.ResetAnimationState, CLN.ReplayFrame)
            end
            table.remove(CLN.questsQueue, 1)
            self:NotifyQueueDirty()
            self:PlayNonQuestSound(nextItem.npcId, nextItem.entryType, nextItem.title, nextItem.gender, nextItem.displayID, nextItem.creatureType)
            return
        else
            -- Unknown entry; discard and try next
            if CLN.Logger then
                CLN.Logger:debug("AdvanceQueue: discarding unknown entry", false, (CLN.Utils and CLN.Utils.LogCategories.loader) or "misc")
            end
            table.remove(CLN.questsQueue, 1)
            self:NotifyQueueDirty()
        end
    end

    -- Queue is empty
    if self:HasSuspendedPlayback() then
        self:ResumeSuspendedPlayback()
    else
        self:NotifyDisplayDirty()
    end
end

--- Drop queued items by index range, pushing each to history as DROPPED.
--- Indices are 1-based and inclusive. Removes in reverse to avoid shifting.
---@param startIdx number First queue index to drop (inclusive)
---@param endIdx number Last queue index to drop (inclusive)
function VoiceoverPlayer:DropQueuedRange(startIdx, endIdx)
    if not CLN.questsQueue then return end
    local lo = math.max(startIdx or 1, 1)
    local hi = math.min(endIdx or #CLN.questsQueue, #CLN.questsQueue)
    for i = hi, lo, -1 do
        local item = CLN.questsQueue[i]
        if item then
            self:SetPlaybackState(item, self.State.DROPPED)
            self:PushToHistory(item)
        end
        table.remove(CLN.questsQueue, i)
    end
    self:NotifyQueueDirty()
end

--- Play a specific queued item by index, dropping everything before it.
--- This is the player-owned version of what QueueList's click handler does.
---@param queueIndex number 1-based index of the item to play
function VoiceoverPlayer:PlayQueuedItemAtIndex(queueIndex)
    if not CLN.questsQueue or queueIndex < 1 or queueIndex > #CLN.questsQueue then return end

    -- Drop everything before the target
    if queueIndex > 1 then
        self:DropQueuedRange(1, queueIndex - 1)
    end

    -- The target is now at index 1
    local item = CLN.questsQueue[1]
    if not item then return end

    if item.questId and item.phase then
        self:PlayQuestSound(item.questId, item.phase, item.npcId, item.displayID, item.gender, item.creatureType)
    elseif item.npcId and item.title and item.entryType then
        table.remove(CLN.questsQueue, 1)
        self:NotifyQueueDirty()
        self:PlayNonQuestSound(item.npcId, item.entryType, item.title, item.gender, item.displayID, item.creatureType)
    else
        table.remove(CLN.questsQueue, 1)
        self:NotifyQueueDirty()
    end
end

-- ============================================================================
-- Centralized UI Notification Helpers (Phase 1)
-- ============================================================================
--- Notify the UI that the queue contents have changed.
function VoiceoverPlayer:NotifyQueueDirty()
    if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then
        CLN.ReplayFrame:MarkQueueDirty()
    end
end

--- Notify the UI that the display state (playing/paused/idle) has changed.
function VoiceoverPlayer:NotifyDisplayDirty()
    if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
        CLN.ReplayFrame:UpdateDisplayFrameState()
    end
    if CLN.ReplayFrame and CLN.ReplayFrame.UpdatePauseButton then
        CLN.ReplayFrame:UpdatePauseButton()
    end
end

--- Toggle pause/resume.
function VoiceoverPlayer:TogglePause()
    if self:IsPaused() then
        self:ResumePlayback()
    else
        self:PausePlayback()
    end
end

--- Is playback currently paused?
---@return boolean
function VoiceoverPlayer:IsPaused()
    return self:GetPlaybackState() == self.State.PAUSED_USER
end

--- Skip the currently playing sound and advance to the next item.
--- Unlike ForceStopCurrentSound, this preserves suspended playback and the
--- queue, advancing through queue → suspended → idle in order.
function VoiceoverPlayer:SkipCurrentSound()
    -- Guard against re-entrancy (rapid double-click on skip)
    if self._skipping then return end
    self._skipping = true

    local cp = self.currentlyPlaying
    if not cp then self._skipping = false; return end

    -- Push skipped item to history
    if cp.title or cp.questId then
        self:SetPlaybackState(cp, self.State.DROPPED)
        self:PushToHistory(cp)
    end

    -- Cancel native VO timer if active
    self:CancelNativeVOResume()

    -- Stop the sound
    if cp.soundHandle then
        StopSound(cp.soundHandle)
    end

    -- Cancel any active text continuation
    if cp._textContinuation then
        if CLN.ReplayFrame and CLN.ReplayFrame.HideSubtitle then
            CLN.ReplayFrame:HideSubtitle()
        end
    end

    -- Clear current without touching suspended or queue
    self.currentlyPlaying = self:GetCurrentlyPlayingObject()

    -- Advance via the single canonical path
    self._skipping = false
    self:AdvanceQueue()
end

-- ============================================================================
-- Queue Suspension (pause current when new queue items arrive)
-- ============================================================================

--- Suspend the currently playing sound to make way for a newly queued item.
--- Saves the current playback info so it can be resumed after the queue drains.
function VoiceoverPlayer:SuspendCurrentPlayback()
    local cp = self.currentlyPlaying
    if not cp then return end
    -- Don't overwrite an existing suspended item
    if self._suspendedPlayback then return end

    self._suspendedPlayback = {
        questId = cp.questId,
        phase = cp.phase,
        npcId = cp.npcId,
        displayID = cp.displayID,
        title = cp.title,
        entryType = cp.entryType,
        gender = cp.gender,
        creatureType = cp.creatureType,
        state = self.State.SUSPENDED,
    }
    self:SetPlaybackState(cp, self.State.SUSPENDED)

    -- Stop the sound
    if cp.soundHandle then
        StopSound(cp.soundHandle, 0)
    end
    -- Nil the handle so the watcher doesn't fire VOICEOVER_STOP
    cp.soundHandle = nil

    if CLN and CLN.Logger then
        CLN.Logger:debug("Suspended playback: " .. tostring(cp.title or cp.questId),
            false, CLN.Utils.LogCategories.loader)
    end
end

--- Resume the suspended playback after the queue has drained.
function VoiceoverPlayer:ResumeSuspendedPlayback()
    local saved = self._suspendedPlayback
    if not saved then return end
    self._suspendedPlayback = nil

    if CLN and CLN.Logger then
        CLN.Logger:debug("Resuming suspended playback: " .. tostring(saved.title or saved.questId),
            false, CLN.Utils.LogCategories.loader)
    end

    self.currentlyPlaying = self:GetCurrentlyPlayingObject()

    if saved.entryType == "quest" and saved.questId and saved.phase then
        self:PlayQuestSound(saved.questId, saved.phase, saved.npcId, saved.displayID, saved.gender, saved.creatureType)
    elseif saved.npcId and saved.title and saved.entryType then
        self:PlayNonQuestSound(saved.npcId, saved.entryType, saved.title, saved.gender, saved.displayID, saved.creatureType)
    end

    -- If playback didn't actually start (file missing/unavailable), the
    -- suspended item would be silently lost. Push it to history as a fallback.
    if not (self.currentlyPlaying and self.currentlyPlaying.soundHandle) then
        self:SetPlaybackState(saved, self.State.DROPPED)
        self:PushToHistory(saved)
    end
end

--- Check if there is a suspended playback waiting to resume.
---@return boolean
function VoiceoverPlayer:HasSuspendedPlayback()
    return self._suspendedPlayback ~= nil
end

-- Stop current audio.
---Stop the current sound if playing and reset state.
---The outgoing record is pushed to history so no voiceover is silently lost.
---@return nil
function VoiceoverPlayer:StopCurrentSound()
    if CLN and CLN.Logger then CLN.Logger:debug("Stopping current sound", false, CLN.Utils.LogCategories.loader) end
    local cp = VoiceoverPlayer.currentlyPlaying
    -- Push outgoing record to history before clearing
    if cp and (cp.title or cp.questId) then
        self:SetPlaybackState(cp, self.State.DROPPED)
        self:PushToHistory(cp)
    end
    if cp and cp.soundHandle then
        StopSound(cp.soundHandle)
    end

    -- Cancel any active text continuation before clearing currentlyPlaying
    if cp and cp._textContinuation then
        if CLN.ReplayFrame and CLN.ReplayFrame.HideSubtitle then
            CLN.ReplayFrame:HideSubtitle()
        end
    end
    
    -- Clear the currentlyPlaying object
    VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

    self:NotifyDisplayDirty()
end

---@param questId number The quest ID to play audio for
---@param phase string The quest phase ("Desc"|"Prog"|"Comp")
---@param npcId number|nil Optional NPC ID for context
---@param displayID number|nil Optional creature display ID for model portrait (captured at queue time)
---@param gender string|nil Optional NPC gender ("Male", "Female", "Neutral") captured at queue time
---@return nil
function VoiceoverPlayer:PlayQuestSound(questId, phase, npcId, displayID, gender, creatureType)
    if (not questId or not phase) then
        if CLN and CLN.Logger then
            CLN.Logger:error("Missing required arguments for PlayQuestSound", true, CLN.Utils.LogCategories.loader)
            CLN.Logger:error("QuestId: " .. tostring(questId), false, CLN.Utils.LogCategories.loader)
            CLN.Logger:error("QuestPhase: " .. tostring(phase), false, CLN.Utils.LogCategories.loader)
        end
        return -- fail fast if no quest ID
    end

    -- Resolve displayID from static DB or metadata cache if not captured from the live unit
    if npcId then
        if not displayID then
            displayID = _G.NpcDisplayIdDB and _G.NpcDisplayIdDB[npcId] or nil
        end
        -- Fall back to persistent metadata cache (auto-populated during gameplay)
        if CLN.NpcMetadataCache then
            local cached = CLN.NpcMetadataCache:Lookup(npcId)
            if cached then
                if not displayID then displayID = cached.displayID end
                if not gender or gender == "" then gender = cached.gender end
                if not creatureType or creatureType == "" then creatureType = cached.creatureType end
            end
        end
    end
    local originalPhase = phase
    if CLN and CLN.Utils and CLN.Utils.NormalizeQuestPhase then
        phase = CLN.Utils:NormalizeQuestPhase(phase)
        local valid = (CLN.Utils.IsCanonicalQuestPhase and CLN.Utils:IsCanonicalQuestPhase(phase)) or false
        if not valid then
            if CLN.Logger then
                CLN.Logger:warn("Rejected unknown quest phase '" .. tostring(originalPhase) .. "'", false, CLN.Utils.LogCategories.loader)
            end
            return
        end
    end

    if (VoiceoverPlayer.currentlyPlaying
        and VoiceoverPlayer.currentlyPlaying.questId == questId
        and VoiceoverPlayer.currentlyPlaying.phase == phase) then
        if (VoiceoverPlayer.currentlyPlaying:isPlaying()) then
            if CLN.db.profile.debugMode and CLN.Logger then CLN.Logger:debug("Quest audio already playing: " .. tostring(questId), false, CLN.Utils.LogCategories.loader) end
            return
        end
    end

    -- Guard against rapid re-triggers after a force-stop (e.g., dialog re-opens
    -- within the same frame or a pending timer fires after ForceStopCurrentSound)
    if self._lastForceStopTime and GetTime then
        local sinceForceStopped = GetTime() - self._lastForceStopTime
        if sinceForceStopped >= 0 and sinceForceStopped < 0.5 then
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Skipped PlayQuestSound: too soon after force-stop (" .. string.format("%.2f", sinceForceStopped) .. "s)", false, CLN.Utils.LogCategories.loader)
            end
            return
        end
    end

    -- While yielding to native NPC speech, defer quest playback so the paused
    -- line can resume first and queued lines continue afterward.
    if self:IsNativeVOPauseActive() then
        if CLN.db.profile.questPlaybackMode == 'queue' then
            local alreadyQueued = self:IsQuestPhaseQueued(questId, phase)
            if not alreadyQueued then
                local audioFileInfo = {
                    questId = questId,
                    phase = phase,
                    title = CLN:GetTitleForQuestID(questId),
                    cantBeInterrupted = true,
                    entryType = "quest",
                    state = self.State.QUEUED,
                    npcId = npcId,
                    displayID = displayID,
                    gender = gender,
                    creatureType = creatureType,
                }
                table.insert(CLN.questsQueue, audioFileInfo)
                self:NotifyQueueDirty()
                if CLN.db.profile.debugMode and CLN.Logger then
                    CLN.Logger:debug("Queued quest during native VO pause: ".. tostring(questId) .. " phase=" .. tostring(phase), false, CLN.Utils.LogCategories.loader)
                end
            end
        elseif CLN.db.profile.debugMode and CLN.Logger then
            CLN.Logger:debug("Skipping quest during native VO pause: " .. tostring(questId) .. " phase=" .. tostring(phase), false, CLN.Utils.LogCategories.loader)
        end
        return
    end

    -- While paused in queue mode, queue new items instead of playing them.
    -- This prevents playback timers from bypassing the pause and cycling
    -- queued items into history.
    if self:IsPaused() and CLN.db.profile.questPlaybackMode == 'queue' then
        local alreadyQueued = self:IsQuestPhaseQueued(questId, phase)
        if not alreadyQueued then
            local audioFileInfo = {
                questId = questId,
                phase = phase,
                title = CLN:GetTitleForQuestID(questId),
                cantBeInterrupted = true,
                entryType = "quest",
                state = self.State.QUEUED,
                npcId = npcId,
                displayID = displayID,
                gender = gender,
                creatureType = creatureType,
            }
            table.insert(CLN.questsQueue, audioFileInfo)
            self:NotifyQueueDirty()
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Queued quest while paused: ".. tostring(questId) .. " phase=" .. tostring(phase), false, CLN.Utils.LogCategories.loader)
            end
        end
        return
    end

    local addonsFolderPath = "Interface\\AddOns\\"
    local fileName = questId .. "_" .. phase .. ".ogg"
    local fileLocation = "\\voiceovers\\" .. fileName
    local success, newSoundHandle

    if (VoiceoverPlayer.currentlyPlaying
        and (CLN.db.profile.questPlaybackMode == 'queue')
        and VoiceoverPlayer:IsEffectivelyPlaying()) then

        local alreadyQueued = self:IsQuestPhaseQueued(questId, phase)
        if alreadyQueued then
            if (CLN.db.profile.debugMode) and CLN.Logger then
                CLN.Logger:debug("Skipped enqueue (duplicate) quest=" .. tostring(questId) .. " phase=" .. tostring(phase), false, CLN.Utils.LogCategories.loader)
            end
            return
        end

        if VoiceoverPlayer.currentlyPlaying.cantBeInterrupted then
            -- Quest sound is playing: queue new item behind it
            local audioFileInfo = {
                questId = questId,
                phase = phase,
                title = CLN:GetTitleForQuestID(questId),
                cantBeInterrupted = true,
                entryType = "quest",
                state = self.State.QUEUED,
                npcId = npcId,
                displayID = displayID,
                gender = gender,
                creatureType = creatureType,
            }

            if (CLN.db.profile.debugMode) and CLN.Logger then
                CLN.Logger:info("Queued quest: " .. tostring(audioFileInfo.questId) .. " Title: " .. tostring(audioFileInfo.title), false, CLN.Utils.LogCategories.loader)
            end

            table.insert(CLN.questsQueue, audioFileInfo)
            self:NotifyQueueDirty()
            self:NotifyDisplayDirty()
            return
        else
            -- Non-quest sound is playing: suspend it so it can resume after the queue drains
            self:SuspendCurrentPlayback()
            -- Clear currentlyPlaying so StopCurrentSound (called below before the new
            -- sound starts) doesn't push the suspended item to history a second time.
            VoiceoverPlayer.currentlyPlaying = self:GetCurrentlyPlayingObject()
            -- Fall through to play the new quest sound
        end
    end

    -- Find the voiceover file first, before stopping current audio
    local foundPath = nil
    for packName, packData in pairs(CLN.VoiceoverPacks) do
        local fileNameFound = packData._voiceoverIndex and packData._voiceoverIndex[fileName]
        if (fileNameFound) then
            foundPath = addonsFolderPath .. packName .. fileLocation
            break
        end
    end

    -- Only stop the current sound if we have a replacement to play
    if foundPath then
        VoiceoverPlayer:StopCurrentSound()
        if (CLN.db.profile.debugMode) and CLN.Logger then
            CLN.Logger:debug("FileNameFound in: " .. tostring(foundPath), false, CLN.Utils.LogCategories.loader)
        end

        success, newSoundHandle = PlaySoundFile(foundPath, CLN.db.profile.audioChannel)
        if (success) then
            VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

            VoiceoverPlayer.currentlyPlaying.soundHandle = newSoundHandle
            VoiceoverPlayer.currentlyPlaying.phase = phase
            VoiceoverPlayer.currentlyPlaying.questId = questId
            VoiceoverPlayer.currentlyPlaying.npcId = npcId
            VoiceoverPlayer.currentlyPlaying.displayID = displayID
            VoiceoverPlayer.currentlyPlaying.creatureType = creatureType
            VoiceoverPlayer.currentlyPlaying.title = CLN:GetTitleForQuestID(questId)
            VoiceoverPlayer.currentlyPlaying.entryType = "quest"
            VoiceoverPlayer.currentlyPlaying.gender = gender
            -- Non-interruptible only when in queue mode
            VoiceoverPlayer.currentlyPlaying.cantBeInterrupted = (CLN.db.profile.questPlaybackMode == 'queue')
            -- Mark playback start time for animation gating
            if GetTime then
                VoiceoverPlayer.currentlyPlaying.startTime = GetTime()
            end
            -- Store duration: prefer pack-provided, fall back to text estimate
            VoiceoverPlayer.currentlyPlaying._voiceoverFileName = fileName
            local estBody = self:GetQuestBodyText(VoiceoverPlayer.currentlyPlaying)
            local questDur, questIsPack = self:GetBestDuration(fileName, estBody or VoiceoverPlayer.currentlyPlaying.title)
            VoiceoverPlayer.currentlyPlaying._estimatedDuration = questDur
            VoiceoverPlayer.currentlyPlaying._hasPackDuration = questIsPack
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Playing: " .. tostring(fileName)
                    .. " | duration: " .. (questDur and string.format("%.1fs", questDur) or "unknown")
                    .. (questIsPack and " (pack)" or " (estimate)"),
                    false, CLN.Utils.LogCategories.loader)
            end
            self:SetPlaybackState(VoiceoverPlayer.currentlyPlaying, self.State.PLAYING)

            -- Always start fresh for new playback to avoid stale state
            if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
                local ok, err = pcall(CLN.ReplayFrame.ResetAnimationState, CLN.ReplayFrame)
                if (not ok) and CLN and CLN.Logger then
                    CLN.Logger:warn("ResetAnimationState failed: " .. tostring(err), false, CLN.Utils.LogCategories.animation)
                end
            end

            self:RemoveQueuedQuestEntry(questId, phase)
            self:NotifyQueueDirty()
            self:NotifyDisplayDirty()
        end
    end

    if (not success) then
        if (CLN.db.profile.printMissingFiles) and CLN.Logger then
            CLN.Logger:warn("Missing voiceover file: " .. tostring(fileName), true, CLN.Utils.LogCategories.loader)
        end
        for i, queuedAudio in ipairs(CLN.questsQueue) do
            if (queuedAudio.questId == questId and queuedAudio.phase == phase) then
                table.remove(CLN.questsQueue, i)
                self:NotifyQueueDirty()
                break
            end
        end
        -- If we suspended something for this failed playback, restore it now
        -- so it isn't stranded.
        if self:HasSuspendedPlayback() then
            self:ResumeSuspendedPlayback()
        end
    end

    if not success then
        self:NotifyDisplayDirty()
    end
end

function VoiceoverPlayer:PlayNonQuestSound(npcId, soundType, text, gender, displayID, creatureType, opts)
    if (not npcId or not soundType or not text) then
        if CLN and CLN.Logger then
            CLN.Logger:error("Arguments missing to play non quest sound.", true, CLN.Utils.LogCategories.loader)
            CLN.Logger:error("NpcId: " .. tostring(npcId), false, CLN.Utils.LogCategories.loader)
            CLN.Logger:error("SoundType: " .. tostring(soundType), false, CLN.Utils.LogCategories.loader)
            CLN.Logger:error("Text: " .. tostring(text), false, CLN.Utils.LogCategories.loader)
        end
        return
    end

    -- Resolve displayID from static DB or metadata cache if not captured from the live unit
    if npcId then
        if not displayID then
            displayID = _G.NpcDisplayIdDB and _G.NpcDisplayIdDB[npcId] or nil
        end
        if CLN.NpcMetadataCache then
            local cached = CLN.NpcMetadataCache:Lookup(npcId)
            if cached then
                if not displayID then displayID = cached.displayID end
                if not gender or gender == "" then gender = cached.gender end
                if not creatureType or creatureType == "" then creatureType = cached.creatureType end
            end
        end
    end
    if self:IsNativeVOPauseActive() then
        local gossipQueue = CLN.db.profile.gossipQueueMode or "none"
        if gossipQueue ~= "none" then
            table.insert(CLN.questsQueue, {
                npcId = npcId,
                title = text,
                entryType = soundType,
                gender = gender,
                displayID = displayID,
                creatureType = creatureType,
                cantBeInterrupted = false,
                state = self.State.QUEUED,
            })
            self:NotifyQueueDirty()
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Queued gossip during native VO pause: ".. tostring(text):sub(1, 60), false, CLN.Utils.LogCategories.loader)
            end
        else
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Skipping non-quest sound during native VO pause: " .. tostring(text), false, CLN.Utils.LogCategories.loader)
            end
        end
        return
    end

    -- While user-paused, queue gossip if gossip queueing is enabled, otherwise skip
    if self:IsPaused() then
        local gossipQueue = CLN.db.profile.gossipQueueMode or "none"
        if gossipQueue ~= "none" then
            table.insert(CLN.questsQueue, {
                npcId = npcId,
                title = text,
                entryType = soundType,
                gender = gender,
                displayID = displayID,
                creatureType = creatureType,
                cantBeInterrupted = false,
                state = self.State.QUEUED,
            })
            self:NotifyQueueDirty()
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Queued gossip while paused: ".. tostring(text):sub(1, 60), false, CLN.Utils.LogCategories.loader)
            end
        else
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Skipping non-quest sound while paused: " .. tostring(text), false, CLN.Utils.LogCategories.loader)
            end
        end
        return
    end

    local success = false
    local newSoundHandle
    local hashes = CLN.Utils:GetHashes(npcId, text)

    -- Gossip cooldown: skip if this line was recently played.
    -- Cooldown is recorded on completion (OnVoiceoverStop), not on play-start,
    -- so interrupted gossip doesn't get marked as "heard".
    -- Multi-paragraph gossip (lore, long dialogue) is exempt from cooldown
    -- since the user likely wants to replay substantive text.
    -- History-replay clicks pass opts.skipCooldown to bypass unconditionally.
    if soundType == "Gossip"
        and not (opts and opts.skipCooldown)
        and not self:_IsMultiParagraph(text)
        and self:IsGossipOnCooldown(hashes) then
        if CLN.db.profile.debugMode and CLN.Logger then
            CLN.Logger:debug("Gossip on cooldown, skipping: " .. tostring(text):sub(1, 60), false, CLN.Utils.LogCategories.loader)
        end
        return
    end

    local pathToFile = CLN.Utils:GetPathToNonQuestFile(npcId, soundType, hashes, gender)
    if (pathToFile and not CLN.Utils:IsNilOrEmpty(pathToFile)) then
        -- Check if we should queue behind active playback instead of overriding
        local gossipQueue = CLN.db.profile.gossipQueueMode or "none"
        if gossipQueue ~= "none" and VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle then
            local shouldQueue = false
            if gossipQueue == "all" and VoiceoverPlayer:IsEffectivelyPlaying() then
                shouldQueue = true
            elseif (gossipQueue == "medium" or gossipQueue == "long") and VoiceoverPlayer:IsEffectivelyPlaying() then
                local threshold = (gossipQueue == "medium") and 5 or 10
                local cp = VoiceoverPlayer.currentlyPlaying
                if cp.startTime and GetTime then
                    local elapsed = GetTime() - cp.startTime
                    if elapsed > threshold then
                        shouldQueue = true
                    end
                end
            end
            if shouldQueue then
                -- Queue as a non-interruptible entry
                table.insert(CLN.questsQueue, {
                    npcId = npcId,
                    title = text,
                    entryType = soundType,
                    gender = gender,
                    displayID = displayID,
                    creatureType = creatureType,
                    cantBeInterrupted = false,
                    state = self.State.QUEUED,
                })
                self:NotifyQueueDirty()
                if CLN.db.profile.debugMode and CLN.Logger then
                    CLN.Logger:debug("Queued gossip behind active playback: ".. tostring(text):sub(1, 60), false, CLN.Utils.LogCategories.loader)
                end
                return
            end
        end

        -- Guard: skip if a non-interruptible quest audio is playing in queue mode
        if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle
            and VoiceoverPlayer.currentlyPlaying.cantBeInterrupted
            and VoiceoverPlayer:IsEffectivelyPlaying()
            and CLN.db.profile.questPlaybackMode == 'queue') then
            return
        end

        -- Only stop current sound once we know we have a replacement
        success, newSoundHandle = PlaySoundFile(pathToFile, CLN.db.profile.audioChannel)
        if (success) then
            -- New sound confirmed — now safe to stop the old one
            if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle) then
                self:SetPlaybackState(VoiceoverPlayer.currentlyPlaying, self.State.DROPPED)
                self:PushToHistory(VoiceoverPlayer.currentlyPlaying)
                StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle, 0.5)
            end
            VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()
            VoiceoverPlayer.currentlyPlaying.soundHandle = newSoundHandle
            VoiceoverPlayer.currentlyPlaying.npcId = npcId
            VoiceoverPlayer.currentlyPlaying.displayID = displayID
            VoiceoverPlayer.currentlyPlaying.creatureType = creatureType
            -- Non-quest lines are never queue-locked
            VoiceoverPlayer.currentlyPlaying.cantBeInterrupted = false
            VoiceoverPlayer.currentlyPlaying.title = text
            VoiceoverPlayer.currentlyPlaying.entryType = soundType
            VoiceoverPlayer.currentlyPlaying.gender = gender
            -- Mark playback start time for animation gating
            if GetTime then
                VoiceoverPlayer.currentlyPlaying.startTime = GetTime()
            end
            -- Store duration: prefer pack-provided, fall back to text estimate
            local nqHashes = CLN.Utils:GetHashes(npcId, text)
            local nqFileName = nqHashes and nqHashes[1]
                and (npcId .. "_" .. soundType .. "_" .. nqHashes[1] .. ".ogg") or nil
            VoiceoverPlayer.currentlyPlaying._voiceoverFileName = nqFileName
            local nqDur, nqIsPack = self:GetBestDuration(nqFileName, text)
            VoiceoverPlayer.currentlyPlaying._estimatedDuration = nqDur
            VoiceoverPlayer.currentlyPlaying._hasPackDuration = nqIsPack
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Playing: " .. tostring(nqFileName)
                    .. " | duration: " .. (nqDur and string.format("%.1fs", nqDur) or "unknown")
                    .. (nqIsPack and " (pack)" or " (estimate)"),
                    false, CLN.Utils.LogCategories.loader)
            end
            self:SetPlaybackState(VoiceoverPlayer.currentlyPlaying, self.State.PLAYING)

            -- Always start fresh for new playback to avoid stale state
            if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
                local ok, err = pcall(CLN.ReplayFrame.ResetAnimationState, CLN.ReplayFrame)
                if (not ok) and CLN and CLN.Logger then
                    CLN.Logger:warn("ResetAnimationState failed: " .. tostring(err), false, CLN.Utils.LogCategories.animation)
                end
            end

            -- Trigger animation pipeline immediately for non-quest lines
            -- Only call if the model is visible; otherwise the ModelFrame OnShow hook will handle it
            if CLN.ReplayFrame and CLN.ReplayFrame.NpcModelFrame and CLN.ReplayFrame.NpcModelFrame:IsShown()
                and CLN.ReplayFrame.UpdateConversationAnimation then
                CLN.ReplayFrame:UpdateConversationAnimation()
            end

            self:NotifyDisplayDirty()
        end
    end

    if (not success) then
        if (CLN.db.profile.printMissingFiles) and CLN.Logger then
            if hashes then
                for index, hash in ipairs(hashes) do
                    CLN.Logger:warn("Missing voiceover file: " .. tostring(npcId) .. "_".. tostring(soundType) .. "_" .. tostring(hash) .. ".ogg", true, CLN.Utils.LogCategories.loader)
                end
            end
        end
    end

    if not success then
        self:NotifyDisplayDirty()
    end
end
