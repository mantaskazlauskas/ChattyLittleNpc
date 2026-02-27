---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class VoiceoverPlayer
local VoiceoverPlayer = {}
CLN.VoiceoverPlayer = VoiceoverPlayer

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
        local key = (q.questId or "") .. "|" .. (q.phase or "") .. "|" .. (q.title or "")
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

    if (clearQueue) then
        CLN.questsQueue = {}
        if CLN.ReplayFrame then CLN.ReplayFrame._scrollOffset = 0 end
        if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
    end

    if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle) then
        StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle)
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

    if CLN and CLN.Logger then
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
    -- For quest entries, replay from queue; for gossip, the moment has passed.
    if cp.entryType == "quest" and cp.questId and cp.phase then
        -- Re-play the same quest sound
        self.currentlyPlaying = self:GetCurrentlyPlayingObject()
        self:PlayQuestSound(cp.questId, cp.phase, cp.npcId, cp.displayID)
    else
        -- Non-quest (gossip): can't meaningfully resume, just let it go
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

--- Resume playback: clear paused flag and advance queue.
function VoiceoverPlayer:ResumePlayback()
    if not self._paused then return end
    self._paused = false

    local cp = self.currentlyPlaying
    -- Try to re-play the paused entry (restarts from beginning)
    if cp and cp._pausedByUser then
        cp._pausedByUser = nil
        if cp.entryType == "quest" and cp.questId and cp.phase then
            self.currentlyPlaying = self:GetCurrentlyPlayingObject()
            self:PlayQuestSound(cp.questId, cp.phase, cp.npcId, cp.displayID)
        elseif cp.npcId and cp.title and cp.entryType then
            self.currentlyPlaying = self:GetCurrentlyPlayingObject()
            self:PlayNonQuestSound(cp.npcId, cp.entryType, cp.title, cp.gender)
        else
            -- Can't replay; advance queue
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

--- If nothing to replay, try to advance the queue.
function VoiceoverPlayer:ProcessQueueAfterResume()
    if #CLN.questsQueue > 0 then
        local next = CLN.questsQueue[1]
        self:PlayQuestSound(next.questId, next.phase, next.npcId, next.displayID)
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

-- Stop current audio.
---Stop the current sound if playing and reset state
---@return nil
function VoiceoverPlayer:StopCurrentSound()
    if CLN and CLN.Logger then CLN.Logger:debug("Stopping current sound", false, CLN.Utils.LogCategories.loader) end
    if (VoiceoverPlayer.currentlyPlaying
        and VoiceoverPlayer.currentlyPlaying:isPlaying()) then
        StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle)
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
            if CLN and CLN.Logger then CLN.Logger:debug("Quest audio already playing: " .. tostring(questId), false, CLN.Utils.LogCategories.loader) end
            return
        end
    end

    local addonsFolderPath = "Interface\\AddOns\\"
    local fileName = questId .. "_" .. phase .. ".ogg"
    local fileLocation = "\\voiceovers\\" .. fileName
    local success, newSoundHandle

    if (VoiceoverPlayer.currentlyPlaying
        and (CLN.db.profile.questPlaybackMode == 'queue')
        and VoiceoverPlayer:IsEffectivelyPlaying()
        and VoiceoverPlayer.currentlyPlaying.cantBeInterrupted) then

        local alreadyQueued = self:IsQuestPhaseQueued(questId, phase)
        if alreadyQueued then
            if (CLN.db.profile.debugMode) and CLN.Logger then
                CLN.Logger:debug("Skipped enqueue (duplicate) quest=" .. tostring(questId) .. " phase=" .. tostring(phase), false, CLN.Utils.LogCategories.loader)
            end
            return
        end

        -- queue the sound and exit if last one is still playing and is a quest
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
    end

    -- Find the voiceover file first, before stopping current audio
    local foundPath = nil
    for packName, packData in pairs(CLN.VoiceoverPacks) do
        local fileNameFound = CLN.Utils:ContainsString(packData.Voiceovers, fileName)
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

    local success = false
    local newSoundHandle
    local hashes = CLN.Utils:GetHashes(npcId, text)
    local pathToFile = CLN.Utils:GetPathToNonQuestFile(npcId, soundType, hashes, gender)
    if (pathToFile and not CLN.Utils:IsNilOrEmpty(pathToFile)) then
        -- Only stop current sound once we know we have a replacement
        if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle) then
            if (VoiceoverPlayer.currentlyPlaying.cantBeInterrupted
                and VoiceoverPlayer:IsEffectivelyPlaying()
                and CLN.db.profile.questPlaybackMode == 'queue') then
                return -- skip if a quest audio is playing
            end
            StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle, 0.5)
        end

        success, newSoundHandle = PlaySoundFile(pathToFile, CLN.db.profile.audioChannel)
        if (success) then
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
