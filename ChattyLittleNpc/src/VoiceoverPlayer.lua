---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class VoiceoverPlayer
local VoiceoverPlayer = {}
CLN.VoiceoverPlayer = VoiceoverPlayer

-- The player announces changes on the shared message bus (names in
-- Core/Messages.lua); UI modules subscribe instead of being called directly.
local function send(messageKey, ...)
    local name = CLN.Messages[messageKey]
    if name and CLN.SendMessage then
        CLN:SendMessage(name, ...)
    end
end

VoiceoverPlayer._send = send  -- used by VoiceoverPlayer/Queue.lua and Pause.lua

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
    if not CLN.db.profile.gossipCooldownEnabled then return false end
    local cooldownSeconds = CLN.db.profile.gossipCooldownSeconds or 0
    local now = GetTime and GetTime() or 0

    for _, hash in ipairs(hashes) do
        local lastPlayed = self._gossipCooldowns[hash]
        if lastPlayed then
            if cooldownSeconds == 0 then
                -- 0 = infinite / entire session
                return true
            end
            if (now - lastPlayed) < cooldownSeconds then
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
    if not CLN.db.profile.gossipCooldownEnabled then return end
    local now = GetTime and GetTime() or 0
    for _, hash in ipairs(hashes) do
        self._gossipCooldowns[hash] = now
    end
end

--- True when the cooldown is on and this exact gossip line is still playing,
--- so re-opening the dialog doesn't restart it mid-line.
---@param npcId number|nil
---@param text string|nil
---@return boolean
function VoiceoverPlayer:_IsGossipLinePlaying(npcId, text)
    if not CLN.db.profile.gossipCooldownEnabled then return false end
    local cp = self.currentlyPlaying
    return cp ~= nil and cp.entryType == "Gossip" and cp.npcId == npcId and cp.title == text
        and self:IsEffectivelyPlaying() and true or false
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
                if self.startTime and GetTime then
                    local elapsed = GetTime() - self.startTime
                    -- If we have a pack/estimated duration, use it with a 30% buffer.
                    -- If duration is unknown, fall back to a 5-minute hard cap so
                    -- that the watcher can still emit VOICEOVER_STOP in Classic
                    -- instead of treating the sound as playing forever.
                    local dur = self._estimatedDuration or (60 * 5)
                    if elapsed > dur * 1.3 then
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
    for _, packData in CLN:IterateVoiceoverPacks() do
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
    if fallbackText then
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
    CLN.Logger:debug("Force stopping current sound", false, CLN.Utils.LogCategories.loader)

    -- In queue mode, ignore external stop requests (e.g., DialogueUI closing)
    -- unless the caller explicitly forces it (cinematics, movies, user stop button).
    if not force and CLN.db.profile.questPlaybackMode == 'queue' then
        CLN.Logger:debug("Ignoring ForceStop in queue mode", false, CLN.Utils.LogCategories.loader)
        return
    end

    -- Cancel any pending native VO resume (must be after queue-mode guard
    -- so an "ignored" ForceStop doesn't kill the resume timer)
    self:CancelNativeVOResume()
    self:_ResumeTimersIfUserPaused()

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
        self:NotifyQueueDirty("cleared")
    end

    if (cp and cp.soundHandle) then
        StopSound(cp.soundHandle)
    end

    -- Cancel any active text continuation
    if cp and cp._textContinuation then
        send("SUBTITLES_CANCELLED")
    end

    -- Deterministic animation cleanup: the polling watcher won't fire
    -- VOICEOVER_STOP because we clear currentlyPlaying below, so announce the
    -- end explicitly while cp is still available for the last line's text.
    send("CONVERSATION_ENDED", cp and cp.title)

    -- Clear the currentlyPlaying object
    VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

    self:NotifyDisplayDirty()
end

-- ============================================================================
-- Centralized UI Notification Helpers (Phase 1)
-- ============================================================================
--- Announce that the queue contents have changed.
---@param reason string|nil "cleared" when the whole queue was dropped
function VoiceoverPlayer:NotifyQueueDirty(reason)
    send("QUEUE_CHANGED", reason)
end

--- Announce that the display state (playing/paused/idle) may have changed.
function VoiceoverPlayer:NotifyDisplayDirty()
    local cp = self.currentlyPlaying
    send("PLAYBACK_STATE_CHANGED", self:GetPlaybackState(cp), cp)
end

--- Resolve and cache how long a queued entry will play, the same way playback
--- will find its file. Cached on the queue record so the queue view doesn't
--- re-resolve files on every redraw.
---@param q table queue record
---@return number|nil duration, boolean isPackDuration
function VoiceoverPlayer:GetQueuedEntryDuration(q)
    if not q then return nil, false end
    if q._durationResolved then
        return q._duration, q._hasPackDuration or false
    end
    local fileName
    if q.questId and q.phase then
        fileName = q.questId .. "_" .. q.phase .. ".ogg"
    elseif q.npcId and q.title and q.entryType then
        -- Any hash variant, gender suffix: same lookup playback uses
        local hashes = CLN.Utils:GetHashes(q.npcId, q.title)
        local path = hashes and CLN.Utils:GetPathToNonQuestFile(q.npcId, q.entryType, hashes, q.gender) or nil
        fileName = path and path:match("([^\\/]+)$") or nil
    else
        return nil, false
    end
    local duration, isPack = self:GetBestDuration(fileName, q.title)
    q._durationResolved = true
    q._duration = duration
    q._hasPackDuration = isPack or false
    return duration, isPack or false
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

--- Call before discarding a user-paused line. Pausing suspended the watcher,
--- and once the line is gone nothing else would restart it. Must run while the
--- line still reads as paused, before its state changes.
function VoiceoverPlayer:_ResumeTimersIfUserPaused()
    if self:IsPaused() then
        CLN.EventHandler:ResumeTimers()
    end
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

    -- Both read the paused state, so they must run before it becomes DROPPED
    self:CancelNativeVOResume()
    self:_ResumeTimersIfUserPaused()

    -- Push skipped item to history
    if cp.title or cp.questId then
        self:SetPlaybackState(cp, self.State.DROPPED)
        self:PushToHistory(cp)
    end

    -- Stop the sound
    if cp.soundHandle then
        StopSound(cp.soundHandle)
    end

    -- Cancel any active text continuation
    if cp._textContinuation then
        send("SUBTITLES_CANCELLED")
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
        _libraryEntry = cp._libraryEntry,
        state = self.State.SUSPENDED,
    }
    self:SetPlaybackState(cp, self.State.SUSPENDED)

    -- Stop the sound
    if cp.soundHandle then
        StopSound(cp.soundHandle, 0)
    end
    -- Nil the handle so the watcher doesn't fire VOICEOVER_STOP
    cp.soundHandle = nil

    CLN.Logger:debug("Suspended playback: " .. tostring(cp.title or cp.questId),
        false, CLN.Utils.LogCategories.loader)
end

--- Resume the suspended playback after the queue has drained.
function VoiceoverPlayer:ResumeSuspendedPlayback()
    local saved = self._suspendedPlayback
    if not saved then return end
    self._suspendedPlayback = nil

    CLN.Logger:debug("Resuming suspended playback: " .. tostring(saved.title or saved.questId),
        false, CLN.Utils.LogCategories.loader)

    self.currentlyPlaying = self:GetCurrentlyPlayingObject()

    if saved._libraryEntry then
        self:PlayLibraryFile(saved._libraryEntry, { resume = true })
    elseif saved.entryType == "quest" and saved.questId and saved.phase then
        self:PlayQuestSound(saved.questId, saved.phase, saved.npcId, saved.displayID, saved.gender, saved.creatureType)
    elseif saved.npcId and saved.title and saved.entryType then
        -- Resuming a suspended line: its cooldown was stamped when it first started.
        self:PlayNonQuestSound(saved.npcId, saved.entryType, saved.title, saved.gender, saved.displayID, saved.creatureType, { skipCooldown = true })
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
    CLN.Logger:debug("Stopping current sound", false, CLN.Utils.LogCategories.loader)
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
        send("SUBTITLES_CANCELLED")
    end
    
    -- Clear the currentlyPlaying object
    VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

    self:NotifyDisplayDirty()
end

--- Fill details the live unit didn't provide from the persistent metadata cache
--- (auto-populated during gameplay). Values already known are kept.
---@return number|nil displayID, string|nil gender, string|nil creatureType
local function fillFromMetadataCache(npcId, displayID, gender, creatureType)
    local cached = npcId and CLN.NpcMetadataCache:Lookup(npcId)
    if cached then
        if not displayID then displayID = cached.displayID end
        if not gender or gender == "" then gender = cached.gender end
        if not creatureType or creatureType == "" then creatureType = cached.creatureType end
    end
    return displayID, gender, creatureType
end

--- Add a quest line to the queue and announce the change.
---@return table entry The queued record
local function enqueueQuest(self, questId, phase, npcId, displayID, gender, creatureType)
    local entry = {
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
    table.insert(CLN.questsQueue, entry)
    self:NotifyQueueDirty()
    return entry
end

--- Add a non-quest line (gossip, item) to the queue and announce the change.
local function enqueueNonQuest(self, npcId, soundType, text, gender, displayID, creatureType)
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
end

---@param questId number The quest ID to play audio for
---@param phase string The quest phase ("Desc"|"Prog"|"Comp")
---@param npcId number|nil Optional NPC ID for context
---@param displayID number|nil Optional creature display ID for model portrait (captured at queue time)
---@param gender string|nil Optional NPC gender ("Male", "Female", "Neutral") captured at queue time
---@return nil
function VoiceoverPlayer:PlayQuestSound(questId, phase, npcId, displayID, gender, creatureType)
    if (not questId or not phase) then
        CLN.Logger:error("Missing required arguments for PlayQuestSound", true, CLN.Utils.LogCategories.loader)
        CLN.Logger:error("QuestId: " .. tostring(questId), false, CLN.Utils.LogCategories.loader)
        CLN.Logger:error("QuestPhase: " .. tostring(phase), false, CLN.Utils.LogCategories.loader)
        return -- fail fast if no quest ID
    end

    displayID, gender, creatureType = fillFromMetadataCache(npcId, displayID, gender, creatureType)
    local originalPhase = phase
    phase = CLN.Utils:NormalizeQuestPhase(phase)
    local valid = CLN.Utils:IsCanonicalQuestPhase(phase)
    if not valid then
        CLN.Logger:warn("Rejected unknown quest phase '" .. tostring(originalPhase) .. "'", false, CLN.Utils.LogCategories.loader)
        return
    end

    if (VoiceoverPlayer.currentlyPlaying
        and VoiceoverPlayer.currentlyPlaying.questId == questId
        and VoiceoverPlayer.currentlyPlaying.phase == phase) then
        if (VoiceoverPlayer.currentlyPlaying:isPlaying()) then
            if CLN.db.profile.debugMode then CLN.Logger:debug("Quest audio already playing: " .. tostring(questId), false, CLN.Utils.LogCategories.loader) end
            return
        end
    end

    -- Guard against rapid re-triggers after a force-stop (e.g., dialog re-opens
    -- within the same frame or a pending timer fires after ForceStopCurrentSound)
    if self._lastForceStopTime and GetTime then
        local sinceForceStopped = GetTime() - self._lastForceStopTime
        if sinceForceStopped >= 0 and sinceForceStopped < 0.5 then
            if CLN.db.profile.debugMode then
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
                enqueueQuest(self, questId, phase, npcId, displayID, gender, creatureType)
                if CLN.db.profile.debugMode then
                    CLN.Logger:debug("Queued quest during native VO pause: ".. tostring(questId) .. " phase=" .. tostring(phase), false, CLN.Utils.LogCategories.loader)
                end
            end
        elseif CLN.db.profile.debugMode then
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
            enqueueQuest(self, questId, phase, npcId, displayID, gender, creatureType)
            if CLN.db.profile.debugMode then
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
            if CLN.db.profile.debugMode then
                CLN.Logger:debug("Skipped enqueue (duplicate) quest=" .. tostring(questId) .. " phase=" .. tostring(phase), false, CLN.Utils.LogCategories.loader)
            end
            return
        end

        if VoiceoverPlayer.currentlyPlaying.cantBeInterrupted then
            -- Quest sound is playing: queue new item behind it
            local queued = enqueueQuest(self, questId, phase, npcId, displayID, gender, creatureType)

            if CLN.db.profile.debugMode then
                CLN.Logger:info("Queued quest: " .. tostring(queued.questId) .. " Title: " .. tostring(queued.title), false, CLN.Utils.LogCategories.loader)
            end

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
    for packName, packData in CLN:IterateVoiceoverPacks() do
        local fileNameFound = packData._voiceoverIndex and packData._voiceoverIndex[fileName]
        if (fileNameFound) then
            foundPath = addonsFolderPath .. packName .. fileLocation
            break
        end
    end

    -- Only stop the current sound if we have a replacement to play
    if foundPath then
        self:_ResumeTimersIfUserPaused()
        VoiceoverPlayer:StopCurrentSound()
        if CLN.db.profile.debugMode then
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
            if CLN.db.profile.debugMode then
                CLN.Logger:debug("Playing: " .. tostring(fileName)
                    .. " | duration: " .. (questDur and string.format("%.1fs", questDur) or "unknown")
                    .. (questIsPack and " (pack)" or " (estimate)"),
                    false, CLN.Utils.LogCategories.loader)
            end
            self:SetPlaybackState(VoiceoverPlayer.currentlyPlaying, self.State.PLAYING)

            -- Always start fresh for new playback to avoid stale state
            send("ANIMATION_RESET")

            self:RemoveQueuedQuestEntry(questId, phase)
            self:NotifyQueueDirty()
            self:NotifyDisplayDirty()
        end
    end

    if (not success) then
        if CLN.db.profile.printMissingFiles then
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

--- Play one exact pack file chosen in the voiceover library. Bypasses language,
--- queue and cooldown rules: the user asked for this specific file.
---@param entry table  from VoiceoverLibrary:GetEntry (path, fileName, kind, id, name, phase, entryType, gender, duration)
---@param opts table|nil  { resume = true } when continuing the same line after a pause/suspend
---@return boolean success
function VoiceoverPlayer:PlayLibraryFile(entry, opts)
    if not (entry and entry.path) then return false end
    local success, newSoundHandle = PlaySoundFile(entry.path, CLN.db.profile.audioChannel)
    if not success then
        CLN.Logger:warn("Could not play voiceover file: " .. tostring(entry.path), true, CLN.Utils.LogCategories.loader)
        return false
    end

    -- Leave user-paused / native-paused states cleanly so the watcher runs again.
    self:CancelNativeVOResume()
    self:_ResumeTimersIfUserPaused()
    if opts and opts.resume then
        -- Continuing the same line: replace the paused record without a history entry.
        VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()
    else
        -- Pushes the outgoing record to history, stops it and clears any text continuation.
        self:StopCurrentSound()
    end

    local cp = VoiceoverPlayer:GetCurrentlyPlayingObject()
    cp.soundHandle = newSoundHandle
    cp._libraryEntry = entry
    cp._libraryPath = entry.path
    -- Packs only store a hash of non-quest text, so there is no line to subtitle.
    cp._libraryNoText = entry.phase == nil
    cp._voiceoverFileName = entry.fileName
    cp.cantBeInterrupted = false
    if entry.phase then
        cp.entryType = "quest"
        cp.questId = entry.id
        cp.phase = entry.phase
        cp.title = entry.name
    else
        cp.entryType = entry.entryType or "Gossip"
        cp.npcId = entry.id
        cp.title = entry.name
        cp.gender = entry.gender
        if entry.id and entry.kind ~= 6 and entry.kind ~= 7 then
            local cached = CLN.NpcMetadataCache:Lookup(entry.id)
            if cached then
                cp.displayID = cached.displayID
                cp.creatureType = cached.creatureType
                if not cp.gender or cp.gender == "Neutral" then cp.gender = cached.gender end
            end
        end
    end
    if GetTime then cp.startTime = GetTime() end
    cp._estimatedDuration = entry.duration
    cp._hasPackDuration = entry.duration ~= nil
    VoiceoverPlayer.currentlyPlaying = cp
    self:SetPlaybackState(cp, self.State.PLAYING)

    send("ANIMATION_RESET")
    send("ANIMATION_START")
    self:NotifyQueueDirty()
    self:NotifyDisplayDirty()
    return true
end

function VoiceoverPlayer:PlayNonQuestSound(npcId, soundType, text, gender, displayID, creatureType, opts)
    if (not npcId or not soundType or not text) then
        CLN.Logger:error("Arguments missing to play non quest sound.", true, CLN.Utils.LogCategories.loader)
        CLN.Logger:error("NpcId: " .. tostring(npcId), false, CLN.Utils.LogCategories.loader)
        CLN.Logger:error("SoundType: " .. tostring(soundType), false, CLN.Utils.LogCategories.loader)
        CLN.Logger:error("Text: " .. tostring(text), false, CLN.Utils.LogCategories.loader)
        return
    end

    displayID, gender, creatureType = fillFromMetadataCache(npcId, displayID, gender, creatureType)
    if self:IsNativeVOPauseActive() then
        local gossipQueue = CLN.db.profile.gossipQueueMode or "none"
        if gossipQueue ~= "none" then
            enqueueNonQuest(self, npcId, soundType, text, gender, displayID, creatureType)
            if CLN.db.profile.debugMode then
                CLN.Logger:debug("Queued gossip during native VO pause: ".. tostring(text):sub(1, 60), false, CLN.Utils.LogCategories.loader)
            end
        else
            if CLN.db.profile.debugMode then
                CLN.Logger:debug("Skipping non-quest sound during native VO pause: " .. tostring(text), false, CLN.Utils.LogCategories.loader)
            end
        end
        return
    end

    -- While user-paused, queue gossip if gossip queueing is enabled, otherwise skip
    if self:IsPaused() then
        local gossipQueue = CLN.db.profile.gossipQueueMode or "none"
        if gossipQueue ~= "none" then
            enqueueNonQuest(self, npcId, soundType, text, gender, displayID, creatureType)
            if CLN.db.profile.debugMode then
                CLN.Logger:debug("Queued gossip while paused: ".. tostring(text):sub(1, 60), false, CLN.Utils.LogCategories.loader)
            end
        else
            if CLN.db.profile.debugMode then
                CLN.Logger:debug("Skipping non-quest sound while paused: " .. tostring(text), false, CLN.Utils.LogCategories.loader)
            end
        end
        return
    end

    local success = false
    local newSoundHandle
    local hashes = CLN.Utils:GetHashes(npcId, text)

    -- Gossip cooldown: skip if this line was recently played or is playing now.
    -- Cooldown is recorded when the line starts (so re-opening the dialog to
    -- interrupt it still counts) and again on completion (OnVoiceoverStop), so
    -- long lines are timed from their end.
    -- Multi-paragraph gossip (lore, long dialogue) is exempt from cooldown
    -- since the user likely wants to replay substantive text.
    -- History-replay clicks pass opts.skipCooldown to bypass unconditionally.
    if soundType == "Gossip"
        and not (opts and opts.skipCooldown)
        and not self:_IsMultiParagraph(text)
        and (self:IsGossipOnCooldown(hashes) or self:_IsGossipLinePlaying(npcId, text)) then
        if CLN.db.profile.debugMode then
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
                enqueueNonQuest(self, npcId, soundType, text, gender, displayID, creatureType)
                if CLN.db.profile.debugMode then
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
            -- Store duration: prefer pack-provided, fall back to text estimate.
            -- Use the file actually played: it may be another hash variant or a
            -- gender-suffixed file, which a first-hash file name would miss.
            local nqFileName = type(pathToFile) == "string" and pathToFile:match("([^\\/]+)$") or nil
            VoiceoverPlayer.currentlyPlaying._voiceoverFileName = nqFileName
            local nqDur, nqIsPack = self:GetBestDuration(nqFileName, text)
            VoiceoverPlayer.currentlyPlaying._estimatedDuration = nqDur
            VoiceoverPlayer.currentlyPlaying._hasPackDuration = nqIsPack
            if CLN.db.profile.debugMode then
                CLN.Logger:debug("Playing: " .. tostring(nqFileName)
                    .. " | duration: " .. (nqDur and string.format("%.1fs", nqDur) or "unknown")
                    .. (nqIsPack and " (pack)" or " (estimate)"),
                    false, CLN.Utils.LogCategories.loader)
            end
            self:SetPlaybackState(VoiceoverPlayer.currentlyPlaying, self.State.PLAYING)
            if soundType == "Gossip" then
                self:RecordGossipCooldown(hashes)
            end

            -- Always start fresh for new playback to avoid stale state
            send("ANIMATION_RESET")

            -- Trigger animation pipeline immediately for non-quest lines
            send("ANIMATION_START")

            self:NotifyDisplayDirty()
        end
    end

    if (not success) then
        if CLN.db.profile.printMissingFiles then
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
