-- VoiceoverPlayer/Pause.lua - Pausing, resuming, native-VO pause and text continuation.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local VoiceoverPlayer = CLN.VoiceoverPlayer
local send = VoiceoverPlayer._send

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

    if CLN.db.profile.debugMode then
        CLN.Logger:debug("Pausing addon VO for native NPC speech (~" .. string.format("%.1f", estimatedDuration) .. "s)",
            false, CLN.Utils.LogCategories.loader)
    end

    -- Stop our sound but keep the state so the watcher doesn't fire VOICEOVER_STOP
    StopSound(cp.soundHandle, 0)
    self:SetPlaybackState(cp, self.State.PAUSED_NATIVE)
    cp.soundHandle = nil -- Clear handle so watcher ignores us

    -- Suspend watcher and history-prune timers while paused
    CLN.EventHandler:SuspendTimers()

    -- Freeze model animations
    send("ANIMATION_FREEZE")

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
    CLN.EventHandler:ResumeTimers()

    CLN.Logger:debug("Resuming addon VO after native NPC speech", false, CLN.Utils.LogCategories.loader)

    -- Re-trigger playback for the current entry.
    if cp._libraryEntry then
        self:PlayLibraryFile(cp._libraryEntry, { resume = true })
    elseif cp.entryType == "quest" and cp.questId and cp.phase then
        self.currentlyPlaying = self:GetCurrentlyPlayingObject()
        self:PlayQuestSound(cp.questId, cp.phase, cp.npcId, cp.displayID, cp.gender, cp.creatureType)
    elseif cp.npcId and cp.title and cp.entryType then
        -- Non-quest (gossip/item): resume from the beginning. Its cooldown was
        -- stamped when it first started, so bypass it for this continuation.
        self.currentlyPlaying = self:GetCurrentlyPlayingObject()
        self:PlayNonQuestSound(cp.npcId, cp.entryType, cp.title, cp.gender, cp.displayID, cp.creatureType, { skipCooldown = true })
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
        CLN.EventHandler:ResumeTimers()
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
        send("SUBTITLES_CANCELLED")
        CLN.EventHandler:SuspendTimers()
        CLN.Logger:debug("Text continuation paused by user", false, CLN.Utils.LogCategories.loader)
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
                if CLN.db.profile.debugMode then
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
    CLN.EventHandler:SuspendTimers()

    if cp and (cp.soundHandle or wasNativePaused) then
        self:SetPlaybackState(cp, self.State.PAUSED_USER)
        if cp.soundHandle then
            StopSound(cp.soundHandle, 0)
            cp.soundHandle = nil -- hide from watcher so VOICEOVER_STOP doesn't fire
        end
    end

    -- Freeze model animations
    send("ANIMATION_FREEZE")

    CLN.Logger:debug("Playback paused by user", false, CLN.Utils.LogCategories.loader)
    self:NotifyQueueDirty()
    self:NotifyDisplayDirty()

    -- Schedule whitelist popupif there are recent NPC speeches to ask about
    CLN.EventHandler:ScheduleWhitelistPopup()
end

--- Resume playback: clear paused flag and either continue as text or replay audio.
function VoiceoverPlayer:ResumePlayback()
    if not self:IsPaused() then return end

    -- Resume watcher and history-prune timers
    CLN.EventHandler:ResumeTimers()

    local cp = self.currentlyPlaying
    -- If paused during text continuation, just complete it
    if cp and self:GetPlaybackState(cp) == self.State.PAUSED_USER and cp._textContinuation then
        self:SetPlaybackState(cp, self.State.TEXT_CONTINUING)
        self:CompleteTextContinuation()
        CLN.Logger:debug("Text continuation completed after pause", false, CLN.Utils.LogCategories.loader)
        self:NotifyDisplayDirty()
        return
    end
    -- Try to re-play the paused entry (restarts from beginning)
    if cp and self:GetPlaybackState(cp) == self.State.PAUSED_USER then

        -- Text continuation: if paused near the end, show remaining text
        -- instead of replaying audio from the start.
        -- Only use text continuation when we have a pack-provided duration;
        -- text estimates are too unreliable for progress calculation.
        local threshold = CLN.db.profile.textContinuationThreshold or 0.75
        local enabled = CLN.db.profile.textContinuationEnabled ~= false
        if enabled and cp._hasPackDuration and cp._elapsedAtPause and cp._estimatedDuration and cp.title
            and not cp._libraryNoText then
            local estimated = cp._estimatedDuration
            if estimated > 0 then
                local progress = cp._elapsedAtPause / estimated
                if progress >= threshold and progress < 1.0 then
                    self:StartTextContinuation(cp, progress)
                    CLN.Logger:debug("Text continuation at " .. string.format("%.0f%%", progress * 100), false, CLN.Utils.LogCategories.loader)
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
            self:AdvanceQueue()
        end
    else
        self:AdvanceQueue()
    end

    CLN.Logger:debug("Playback resumed by user", false, CLN.Utils.LogCategories.loader)
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
    local sentences = CLN.ReplayFrame:SplitTooltipIntoSentences(textForSentences)

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
    CLN.ReplayFrame:ShowRemainingSubtitles(sentences, startIndex, function()
        self:CompleteTextContinuation()
    end)
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
    self:AdvanceQueue()

    CLN.Logger:debug("Text continuation completed", false, CLN.Utils.LogCategories.loader)
end

--- Replay a paused entry directly, bypassing queue management.
---@return boolean success
function VoiceoverPlayer:ReplayPausedEntry(cp)
    if not cp then return false end
    if cp._libraryEntry then
        return self:PlayLibraryFile(cp._libraryEntry, { resume = true })
    end
    local success, newSoundHandle
    local addonsFolderPath = "Interface\\AddOns\\"

    if cp.entryType == "quest" and cp.questId and cp.phase then
        local fileName = cp.questId .. "_" .. cp.phase .. ".ogg"
        local fileLocation = "\\voiceovers\\" .. fileName
        local foundPath = nil
        for packName, packData in CLN:IterateVoiceoverPacks() do
            local found = (packData._voiceoverIndex and packData._voiceoverIndex[fileName])
                or CLN.Utils:ContainsString(packData.Voiceovers, fileName)
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
            -- Remember the real file so the duration lookup below finds it
            cp._voiceoverFileName = cp._voiceoverFileName or pathToFile:match("([^\\/]+)$")
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
        if CLN.db.profile.debugMode then
            CLN.Logger:debug("Replaying: " .. tostring(replayFileName)
                .. " | duration: " .. (replayDur and string.format("%.1fs", replayDur) or "unknown")
                .. (replayIsPack and " (pack)" or " (estimate)"),
                false, CLN.Utils.LogCategories.loader)
        end
        self:SetPlaybackState(self.currentlyPlaying, self.State.PLAYING)
        -- Don't touch the queue — the paused item was never in it
        self:NotifyQueueDirty()
        self:NotifyDisplayDirty()
        send("ANIMATION_RESET")
        return true
    end
    return false
end
