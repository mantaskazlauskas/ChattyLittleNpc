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

--- Check whether any of the given hashes are still on cooldown.
--- Expiry is checked lazily on access — no background timer needed.
---@param hashes string[]
---@return boolean
function VoiceoverPlayer:IsGossipOnCooldown(hashes)
    if not CLN.db.profile.gossipCooldownEnabled then return false end
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
    if not CLN.db.profile.gossipCooldownEnabled then return end
    local now = GetTime and GetTime() or 0
    for _, hash in ipairs(hashes) do
        self._gossipCooldowns[hash] = now
    end
end

-- ============================================================================
-- Queue Integrity Helpers
-- ============================================================================
--- Check if a quest/phase combo is already queued.
---@param questId number
---@param phase string
---@return boolean isQueued, number index
function VoiceoverPlayer:IsQuestPhaseQueued(questId, phase)
    if not (questId and phase) then return false end
    -- Check currently playing item too (not just the queue)
    local cp = VoiceoverPlayer.currentlyPlaying
    if cp and cp.questId == questId and cp.phase == phase and cp.soundHandle then
        return true, 0
    end
    for i, q in ipairs(CLN.questsQueue) do
        if q.questId == questId and q.phase == phase then
            return true, i
        end
    end
    return false
end

--- Deduplicate the queue, removing entries that match currently playing or are duplicated.
function VoiceoverPlayer:DeduplicateQueue()
    if not CLN.questsQueue then return end
    local seen = {}
    local cp = VoiceoverPlayer.currentlyPlaying
    -- Mark currently playing as seen
    if cp and cp.questId and cp.phase then
        seen[cp.questId .. "|" .. cp.phase] = true
    end
    for i = #CLN.questsQueue, 1, -1 do
        local q = CLN.questsQueue[i]
        local key = (q.questId or "") .. "|" .. (q.phase or "")
        if seen[key] then
            table.remove(CLN.questsQueue, i)
        else
            seen[key] = true
        end
    end
end

function VoiceoverPlayer:GetCurrentlyPlayingObject()
    return {
        cantBeInterrupted = nil,
        npcId = nil,
        gender = nil,
        displayID = nil,
        entryType = nil,
        phase = nil,
        questId = nil,
        soundHandle = nil,
        title = nil,
        isPlaying = function (self)
            return self.soundHandle and C_Sound.IsPlaying(self.soundHandle) or false
        end,
    }
end

VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()
VoiceoverPlayer.queueProcessed = false
VoiceoverPlayer._paused = false
VoiceoverPlayer._suspendedPlayback = nil

-- ============================================================================
-- Centralized History Push
-- ============================================================================
--- Push a record to replay history. Accepts a currentlyPlaying object, a queue
--- entry, a suspended-playback table, or any table with at least a title or
--- questId.  Normalizes the fields so callers don't need to worry about shape.
---@param record table Any voiceover record (currentlyPlaying, queue item, etc.)
function VoiceoverPlayer:PushToHistory(record)
    if not record then return end
    -- Resolve title: prefer explicit, fall back to questId lookup
    local title = record.title
    if not title and record.questId then
        title = CLN.GetTitleForQuestID and CLN:GetTitleForQuestID(record.questId) or nil
    end
    -- Must have *something* identifiable
    if not title and not record.questId then return end

    if CLN.ReplayFrame and CLN.ReplayFrame.PushHistory then
        CLN.ReplayFrame:PushHistory({
            title = title,
            npcId = record.npcId,
            questId = record.questId,
            phase = record.phase,
            entryType = record.entryType or (record.questId and "quest" or "unknown"),
            gender = record.gender,
            displayID = record.displayID,
            completedAt = GetTime and GetTime() or 0,
        })
    end
end

-- Grace period: consider a sound "still playing" if it started recently,
-- even when C_Sound.IsPlaying briefly returns false during frame transitions.
local PLAYBACK_GRACE_SEC = 0.6
function VoiceoverPlayer:IsEffectivelyPlaying()
    local cp = self.currentlyPlaying
    if not cp or not cp.soundHandle then return false end
    if cp.isPlaying and cp:isPlaying() then return true end
    -- Fallback: treat the sound as playing within the grace window
    if cp.startTime and GetTime then
        local elapsed = GetTime() - cp.startTime
        if elapsed >= 0 and elapsed < PLAYBACK_GRACE_SEC then return true end
    end
    return false
end

-- Clear the queue from quests and stop current audio.
---@param clearQueue boolean|nil If true, clears queued quests
---@param force boolean|nil If true, bypass queue-mode protection (used by cinematics/movies)
function VoiceoverPlayer:ForceStopCurrentSound(clearQueue, force)
    if CLN and CLN.Logger then CLN.Logger:debug("Force stopping current sound", false, CLN.Utils.LogCategories.loader) end

    -- Cancel any pending native VO resume
    self:CancelNativeVOResume()

    -- In queue mode, ignore external stop requests (e.g., DialogueUI closing)
    -- unless the caller explicitly forces it (cinematics, movies, user stop button).
    if not force and CLN.db.profile.questPlaybackMode == 'queue' then
        if CLN and CLN.Logger then CLN.Logger:debug("Ignoring ForceStop in queue mode", false, CLN.Utils.LogCategories.loader) end
        return
    end

    -- Clear paused state on explicit stop
    self._paused = false

    -- Push suspended playback to history before discarding
    if self._suspendedPlayback then
        self:PushToHistory(self._suspendedPlayback)
        self._suspendedPlayback = nil
    end

    -- Push currently playing to history before stopping
    local cp = VoiceoverPlayer.currentlyPlaying
    if cp and (cp.title or cp.questId) then
        self:PushToHistory(cp)
    end

    if (clearQueue) then
        -- Push all queued items to history before clearing
        for _, q in ipairs(CLN.questsQueue) do
            self:PushToHistory(q)
        end
        CLN.questsQueue = {}
        if CLN.ReplayFrame then CLN.ReplayFrame._scrollOffset = 0 end
        if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
    end

    if (cp and cp.soundHandle) then
        StopSound(cp.soundHandle)
    end
    
    -- Clear the currentlyPlaying object
    VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

    if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then CLN.ReplayFrame:UpdateDisplayFrameState() end
    if CLN.ReplayFrame and CLN.ReplayFrame.UpdatePauseButton then CLN.ReplayFrame:UpdatePauseButton() end
end

-- ============================================================================
-- Native VO Pause/Resume
-- ============================================================================

--- Temporarily pause addon voiceover to yield to native NPC voice-over.
--- Stops the sound but preserves the currentlyPlaying state so we can resume.
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
    cp._pausedForNativeVO = true
    cp._pausedSoundHandle = cp.soundHandle
    cp.soundHandle = nil -- Clear handle so watcher ignores us

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
    if not (cp and cp._pausedForNativeVO) then return end

    cp._pausedForNativeVO = nil
    cp._pausedSoundHandle = nil

    if CLN and CLN.Logger then
        CLN.Logger:debug("Resuming addon VO after native NPC speech", false, CLN.Utils.LogCategories.loader)
    end

    -- Re-trigger playback for the current entry.
    if cp.entryType == "quest" and cp.questId and cp.phase then
        self.currentlyPlaying = self:GetCurrentlyPlayingObject()
        self:PlayQuestSound(cp.questId, cp.phase, cp.npcId, cp.displayID)
    elseif cp.npcId and cp.title and cp.entryType then
        -- Non-quest (gossip/item): resume from the beginning
        self.currentlyPlaying = self:GetCurrentlyPlayingObject()
        self:PlayNonQuestSound(cp.npcId, cp.entryType, cp.title, cp.gender)
    else
        -- Can't identify the entry; clear state
        self.currentlyPlaying = self:GetCurrentlyPlayingObject()
        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
            CLN.ReplayFrame:UpdateDisplayFrameState()
        end
    end
end

--- Cancel any pending native VO resume timer (e.g., if user manually stops).
function VoiceoverPlayer:CancelNativeVOResume()
    if self._nativeVOResumeTimer then
        self._nativeVOResumeTimer:Cancel()
        self._nativeVOResumeTimer = nil
    end
    local cp = self.currentlyPlaying
    if cp then
        cp._pausedForNativeVO = nil
        cp._pausedSoundHandle = nil
    end
end

-- ============================================================================
-- User-Initiated Pause/Resume
-- ============================================================================

--- Pause playback: stop current sound and freeze queue advancement.
--- WoW has no sound seek API so the interrupted sound cannot resume mid-stream.
function VoiceoverPlayer:PausePlayback()
    if self._paused then return end
    self._paused = true

    local cp = self.currentlyPlaying
    if cp and cp.soundHandle then
        StopSound(cp.soundHandle, 0)
        cp._pausedByUser = true
        cp.soundHandle = nil -- hide from watcher so VOICEOVER_STOP doesn't fire
    end

    if CLN and CLN.Logger then
        CLN.Logger:debug("Playback paused by user", false, CLN.Utils.LogCategories.loader)
    end
    if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
    if CLN.ReplayFrame and CLN.ReplayFrame.UpdatePauseButton then CLN.ReplayFrame:UpdatePauseButton() end

    -- Schedule whitelist popup if there are recent NPC speeches to ask about
    if CLN.EventHandler and CLN.EventHandler.ScheduleWhitelistPopup then
        CLN.EventHandler:ScheduleWhitelistPopup()
    end
end

--- Resume playback: clear paused flag and replay the paused entry.
function VoiceoverPlayer:ResumePlayback()
    if not self._paused then return end
    self._paused = false

    local cp = self.currentlyPlaying
    -- Try to re-play the paused entry (restarts from beginning)
    if cp and cp._pausedByUser then
        cp._pausedByUser = nil
        -- Replay directly using PlaySoundFile, bypassing PlayQuestSound/PlayNonQuestSound
        -- to avoid their queue-removal and dedup logic which would discard queued items.
        local replayed = self:ReplayPausedEntry(cp)
        if not replayed then
            -- Couldn't replay; push the lost item to history and advance queue
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
    if CLN.ReplayFrame and CLN.ReplayFrame.UpdatePauseButton then CLN.ReplayFrame:UpdatePauseButton() end
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
        self.currentlyPlaying.cantBeInterrupted = cp.cantBeInterrupted
        if GetTime then self.currentlyPlaying.startTime = GetTime() end
        -- Don't touch the queue — the paused item was never in it
        if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then CLN.ReplayFrame:UpdateDisplayFrameState() end
        if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
            pcall(CLN.ReplayFrame.ResetAnimationState, CLN.ReplayFrame)
        end
        return true
    end
    return false
end

--- If nothing to replay, try to advance the queue, then check suspended.
function VoiceoverPlayer:ProcessQueueAfterResume()
    if #CLN.questsQueue > 0 then
        local next = CLN.questsQueue[1]
        if next.questId and next.phase then
            self:PlayQuestSound(next.questId, next.phase, next.npcId, next.displayID)
        elseif next.npcId and next.title and next.entryType then
            table.remove(CLN.questsQueue, 1)
            if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
            self:PlayNonQuestSound(next.npcId, next.entryType, next.title, next.gender)
        else
            table.remove(CLN.questsQueue, 1)
        end
    elseif self:HasSuspendedPlayback() then
        self:ResumeSuspendedPlayback()
    else
        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
            CLN.ReplayFrame:UpdateDisplayFrameState()
        end
    end
end

--- Toggle pause/resume.
function VoiceoverPlayer:TogglePause()
    if self._paused then
        self:ResumePlayback()
    else
        self:PausePlayback()
    end
end

--- Is playback currently paused?
---@return boolean
function VoiceoverPlayer:IsPaused()
    return self._paused == true
end

--- Skip the currently playing sound and advance to the next item.
--- Unlike ForceStopCurrentSound, this preserves suspended playback and the
--- queue, advancing through queue → suspended → idle in order.
function VoiceoverPlayer:SkipCurrentSound()
    local cp = self.currentlyPlaying
    if not cp then return end

    -- Push skipped item to history
    if cp.title or cp.questId then
        self:PushToHistory(cp)
    end

    -- Cancel native VO timer if active
    self:CancelNativeVOResume()

    -- Stop the sound
    if cp.soundHandle then
        StopSound(cp.soundHandle)
    end

    -- Clear paused state
    self._paused = false

    -- Clear current without touching suspended or queue
    self.currentlyPlaying = self:GetCurrentlyPlayingObject()

    -- Advance: queue → suspended → idle
    if #CLN.questsQueue > 0 then
        self:DeduplicateQueue()
        if #CLN.questsQueue > 0 then
            local nextQuest = CLN.questsQueue[1]
            self:PlayQuestSound(nextQuest.questId, nextQuest.phase, nextQuest.npcId, nextQuest.displayID)
            return
        end
    end
    if self:HasSuspendedPlayback() then
        self:ResumeSuspendedPlayback()
        return
    end

    if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then CLN.ReplayFrame:UpdateDisplayFrameState() end
    if CLN.ReplayFrame and CLN.ReplayFrame.UpdatePauseButton then CLN.ReplayFrame:UpdatePauseButton() end
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
    }

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
        self:PlayQuestSound(saved.questId, saved.phase, saved.npcId, saved.displayID)
    elseif saved.npcId and saved.title and saved.entryType then
        self:PlayNonQuestSound(saved.npcId, saved.entryType, saved.title, saved.gender)
    end

    -- If playback didn't actually start (file missing/unavailable), the
    -- suspended item would be silently lost. Push it to history as a fallback.
    if not (self.currentlyPlaying and self.currentlyPlaying.soundHandle) then
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
        self:PushToHistory(cp)
    end
    if cp and cp.soundHandle and cp:isPlaying() then
        StopSound(cp.soundHandle)
    end
    
    -- Clear the currentlyPlaying object
    VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

    if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then CLN.ReplayFrame:UpdateDisplayFrameState() end
end

---@param questId number The quest ID to play audio for
---@param phase string The quest phase ("Desc"|"Prog"|"Comp")
---@param npcId number|nil Optional NPC ID for context
---@param displayID number|nil Optional creature display ID for model portrait (captured at queue time)
---@return nil
function VoiceoverPlayer:PlayQuestSound(questId, phase, npcId, displayID)
    if (not questId or not phase) then
        if CLN and CLN.Logger then
            CLN.Logger:error("Missing required arguments for PlayQuestSound", true, CLN.Utils.LogCategories.loader)
            CLN.Logger:error("QuestId: " .. tostring(questId), false, CLN.Utils.LogCategories.loader)
            CLN.Logger:error("QuestPhase: " .. tostring(phase), false, CLN.Utils.LogCategories.loader)
        end
        return -- fail fast if no quest ID
    end

    -- Normalize & validate phase early; keep both original and normalized for logging
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

    -- While paused in queue mode, queue new items instead of playing them.
    -- This prevents playback timers from bypassing the pause and cycling
    -- queued items into history.
    if self._paused and CLN.db.profile.questPlaybackMode == 'queue' then
        local alreadyQueued = self:IsQuestPhaseQueued(questId, phase)
        if not alreadyQueued then
            local audioFileInfo = {
                questId = questId,
                phase = phase,
                title = CLN:GetTitleForQuestID(questId),
                cantBeInterrupted = true,
                entryType = "quest",
                npcId = npcId,
                displayID = displayID,
            }
            table.insert(CLN.questsQueue, audioFileInfo)
            if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Queued quest while paused: " .. tostring(questId) .. " phase=" .. tostring(phase), false, CLN.Utils.LogCategories.loader)
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
                npcId = npcId,
                displayID = displayID,
            }

            if (CLN.db.profile.debugMode) and CLN.Logger then
                CLN.Logger:info("Queued quest: " .. tostring(audioFileInfo.questId) .. " Title: " .. tostring(audioFileInfo.title), false, CLN.Utils.LogCategories.loader)
            end

            table.insert(CLN.questsQueue, audioFileInfo)
            if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
            if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then CLN.ReplayFrame:UpdateDisplayFrameState() end
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
            VoiceoverPlayer.currentlyPlaying.title = CLN:GetTitleForQuestID(questId)
            VoiceoverPlayer.currentlyPlaying.entryType = "quest"
            -- Non-interruptible only when in queue mode
            VoiceoverPlayer.currentlyPlaying.cantBeInterrupted = (CLN.db.profile.questPlaybackMode == 'queue')
            -- Mark playback start time for animation gating
            if GetTime then
                VoiceoverPlayer.currentlyPlaying.startTime = GetTime()
            end

            -- Always start fresh for new playback to avoid stale state
            if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
                local ok, err = pcall(CLN.ReplayFrame.ResetAnimationState, CLN.ReplayFrame)
                if (not ok) and CLN and CLN.Logger then
                    CLN.Logger:warn("ResetAnimationState failed: " .. tostring(err), false, CLN.Utils.LogCategories.animation)
                end
            end

            if (VoiceoverPlayer.currentlyPlaying.title) then
                table.remove(CLN.questsQueue, 1)
                if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
                    CLN.ReplayFrame:UpdateDisplayFrameState()
                end
                if CLN.ReplayFrame and CLN.ReplayFrame.UpdatePauseButton then
                    CLN.ReplayFrame:UpdatePauseButton()
                end
            end
        end
    end

    if (not success) then
        if (CLN.db.profile.printMissingFiles) and CLN.Logger then
            CLN.Logger:warn("Missing voiceover file: " .. tostring(fileName), true, CLN.Utils.LogCategories.loader)
        end
        for i, queuedAudio in ipairs(CLN.questsQueue) do
            if (queuedAudio.questId == questId and queuedAudio.phase == phase) then
                table.remove(CLN.questsQueue, i)
                if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                break
            end
        end
        -- If we suspended something for this failed playback, restore it now
        -- so it isn't stranded.
        if self:HasSuspendedPlayback() then
            self:ResumeSuspendedPlayback()
        end
    end

    if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
        CLN.ReplayFrame:UpdateDisplayFrameState()
    end
end

function VoiceoverPlayer:PlayNonQuestSound(npcId, soundType, text, gender)
    if (not npcId or not soundType or not text) then
        if CLN and CLN.Logger then
            CLN.Logger:error("Arguments missing to play non quest sound.", true, CLN.Utils.LogCategories.loader)
            CLN.Logger:error("NpcId: " .. tostring(npcId), false, CLN.Utils.LogCategories.loader)
            CLN.Logger:error("SoundType: " .. tostring(soundType), false, CLN.Utils.LogCategories.loader)
            CLN.Logger:error("Text: " .. tostring(text), false, CLN.Utils.LogCategories.loader)
        end
        return
    end

    -- Don't start new non-quest playback while user-paused
    if self._paused then
        if CLN.db.profile.debugMode and CLN.Logger then
            CLN.Logger:debug("Skipping non-quest sound while paused: " .. tostring(text), false, CLN.Utils.LogCategories.loader)
        end
        return
    end

    local success = false
    local newSoundHandle
    local hashes = CLN.Utils:GetHashes(npcId, text)

    -- Gossip cooldown: skip if this line was recently played
    if soundType == "Gossip" and self:IsGossipOnCooldown(hashes) then
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
            elseif gossipQueue == "long" and VoiceoverPlayer:IsEffectivelyPlaying() then
                local cp = VoiceoverPlayer.currentlyPlaying
                if cp.startTime and GetTime then
                    local elapsed = GetTime() - cp.startTime
                    if elapsed > 10 then
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
                    cantBeInterrupted = false,
                })
                if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                if CLN.db.profile.debugMode and CLN.Logger then
                    CLN.Logger:debug("Queued gossip behind active playback: " .. tostring(text):sub(1, 60), false, CLN.Utils.LogCategories.loader)
                end
                return
            end
        end

        -- Only stop current sound once we know we have a replacement
        if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle) then
            if (VoiceoverPlayer.currentlyPlaying.cantBeInterrupted
                and VoiceoverPlayer:IsEffectivelyPlaying()
                and CLN.db.profile.questPlaybackMode == 'queue') then
                return -- skip if a quest audio is playing
            end
            -- Push outgoing record to history before replacing
            self:PushToHistory(VoiceoverPlayer.currentlyPlaying)
            StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle, 0.5)
        end

        success, newSoundHandle = PlaySoundFile(pathToFile, CLN.db.profile.audioChannel)
        if (success) then
            -- Record gossip cooldown on successful playback
            if soundType == "Gossip" then
                self:RecordGossipCooldown(hashes)
            end
            VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()
            VoiceoverPlayer.currentlyPlaying.soundHandle = newSoundHandle
            VoiceoverPlayer.currentlyPlaying.npcId = npcId
            -- Non-quest lines are never queue-locked
            VoiceoverPlayer.currentlyPlaying.cantBeInterrupted = false
            VoiceoverPlayer.currentlyPlaying.title = text
            VoiceoverPlayer.currentlyPlaying.entryType = soundType
            VoiceoverPlayer.currentlyPlaying.gender = gender
            -- Mark playback start time for animation gating
            if GetTime then
                VoiceoverPlayer.currentlyPlaying.startTime = GetTime()
            end

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

            if CLN.ReplayFrame and CLN.ReplayFrame.UpdatePauseButton then
                CLN.ReplayFrame:UpdatePauseButton()
            end
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

    if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
        CLN.ReplayFrame:UpdateDisplayFrameState()
    end
end
