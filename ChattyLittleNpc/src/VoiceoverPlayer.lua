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
    for i, q in ipairs(CLN.questsQueue) do
        if q.questId == questId and q.phase == phase then
            return true, i
        end
    end
    return false
end

--- Remove duplicate quest-phase entries keeping the first occurrence.

function VoiceoverPlayer:GetCurrentlyPlayingObject()
    if VoiceoverPlayer.currentlyPlaying then
        return VoiceoverPlayer.currentlyPlaying
    end

    return {
        cantBeInterrupted = nil,
        npcId = nil,
        gender = nil,
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

-- Clear the queue from quests and stop current audio.
---@param clearQueue boolean|nil If true, clears queued quests
function VoiceoverPlayer:ForceStopCurrentSound(clearQueue)
    if CLN and CLN.Logger then CLN.Logger:debug("Force stopping current sound", false, CLN.Utils.LogCategories.loader) end
    if (clearQueue) then
        CLN.questsQueue = {}
        if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
    end

    if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle) then
        StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle)
    end
    
    -- Clear the currentlyPlaying object
    VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

    if CLN and CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
            CLN.ReplayFrame:UpdateDisplayFrameState()
        end
    end
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

    if CLN and CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
        CLN.ReplayFrame:UpdateDisplayFrameState()
    end
end

---@param questId number The quest ID to play audio for
---@param phase string The quest phase ("Desc"|"Prog"|"Comp")
---@param npcId number|nil Optional NPC ID for context
---@return nil
function VoiceoverPlayer:PlayQuestSound(questId, phase, npcId)
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
        and VoiceoverPlayer.currentlyPlaying:isPlaying()
        and VoiceoverPlayer.currentlyPlaying.soundHandle
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
            npcId = npcId,
        }

        if (CLN.db.profile.debugMode) and CLN.Logger then
            CLN.Logger:info("Queued quest: " .. tostring(audioFileInfo.questId) .. " Title: " .. tostring(audioFileInfo.title), false, CLN.Utils.LogCategories.loader)
        end

    table.insert(CLN.questsQueue, audioFileInfo)
        if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
        CLN.ReplayFrame:UpdateDisplayFrameState()
        return
    end

    VoiceoverPlayer:StopCurrentSound()

    for packName, packData in pairs(CLN.VoiceoverPacks) do
        local fileNameFound = CLN.Utils:ContainsString(packData.Voiceovers, fileName)
        if (fileNameFound) then
            local voiceoverPath = addonsFolderPath .. packName .. fileLocation
            if (CLN.db.profile.debugMode) and CLN.Logger then
                CLN.Logger:debug("FileNameFound in: " .. tostring(voiceoverPath), false, CLN.Utils.LogCategories.loader)
            end

            success, newSoundHandle = PlaySoundFile(voiceoverPath, CLN.db.profile.audioChannel)
            if (success) then
                VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

                VoiceoverPlayer.currentlyPlaying.soundHandle = newSoundHandle
                VoiceoverPlayer.currentlyPlaying.phase = phase
                VoiceoverPlayer.currentlyPlaying.questId = questId
                VoiceoverPlayer.currentlyPlaying.npcId = npcId
                VoiceoverPlayer.currentlyPlaying.title = CLN:GetTitleForQuestID(questId)
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
                    -- Only trigger animation update if model is already visible; otherwise OnShow will handle it
                    if CLN.ReplayFrame and CLN.ReplayFrame.NpcModelFrame and CLN.ReplayFrame.NpcModelFrame:IsShown() 
                        and CLN.ReplayFrame.UpdateConversationAnimation then
                        CLN.ReplayFrame:UpdateConversationAnimation()
                    end
                end
            end
            break
        end
    end

    if (not success) then
        if (CLN.db.profile.printMissingFiles) and CLN.Logger then
            CLN.Logger:warn("Missing voiceover file: " .. tostring(fileName), true, CLN.Utils.LogCategories.loader)
        end
        for _, queuedAudio in ipairs(CLN.questsQueue) do
            if (queuedAudio.questId == questId and queuedAudio.phase == phase) then
                table.remove(CLN.questsQueue, 1)
                if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                break
            end
        end
    end

    if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
        CLN.ReplayFrame:UpdateDisplayFrameState()
    end
    -- Only trigger animation update if playback didn't start successfully
    -- (successful playback already triggered it above)
    if not success and CLN.ReplayFrame and CLN.ReplayFrame.UpdateConversationAnimation then
        CLN.ReplayFrame:UpdateConversationAnimation()
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

    if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle) then
        if (VoiceoverPlayer.currentlyPlaying.cantBeInterrupted
            and VoiceoverPlayer.currentlyPlaying:isPlaying()
            and CLN.db.profile.questPlaybackMode == 'queue') then
            return -- skip if a quest audio is playing
        end
        StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle, 0.5)
    end

    local success = false
    local newSoundHandle
    local hashes = CLN.Utils:GetHashes(npcId, text)
    local pathToFile = CLN.Utils:GetPathToNonQuestFile(npcId, soundType, hashes, gender)
    if (pathToFile and not CLN.Utils:IsNilOrEmpty(pathToFile)) then
        success, newSoundHandle = PlaySoundFile(pathToFile, CLN.db.profile.audioChannel)
        if (success) then
            VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()
            VoiceoverPlayer.currentlyPlaying.soundHandle = newSoundHandle
            VoiceoverPlayer.currentlyPlaying.npcId = npcId
            -- Non-quest lines are never queue-locked
            VoiceoverPlayer.currentlyPlaying.cantBeInterrupted = false
            VoiceoverPlayer.currentlyPlaying.title = text
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
    -- Only trigger animation update if playback didn't start successfully
    -- (successful playback already triggered it above)
    if not success and CLN.ReplayFrame and CLN.ReplayFrame.NpcModelFrame and CLN.ReplayFrame.NpcModelFrame:IsShown()
        and CLN.ReplayFrame.UpdateConversationAnimation then
        CLN.ReplayFrame:UpdateConversationAnimation()
    end
end