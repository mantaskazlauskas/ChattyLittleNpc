---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class VoiceoverPlayer
local VoiceoverPlayer = {}
CLN.VoiceoverPlayer = VoiceoverPlayer

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
function VoiceoverPlayer:ForceStopCurrentSound(clearQueue)
    CLN.Utils:LogDebug("Force stopping current sound")
    if (clearQueue) then
        CLN.questsQueue = {}
        if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
    end

    if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle) then
        StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle)
    end
    
    -- Clear the currentlyPlaying object
    VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

    CLN.ReplayFrame:UpdateDisplayFrameState()
end

-- Stop current audio.
function VoiceoverPlayer:StopCurrentSound()
    CLN.Utils:LogDebug("Stopping current sound")
    if (VoiceoverPlayer.currentlyPlaying
        and VoiceoverPlayer.currentlyPlaying:isPlaying()) then
        StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle)
    end
    
    -- Clear the currentlyPlaying object
    VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

    CLN.ReplayFrame:UpdateDisplayFrameState()
end

function VoiceoverPlayer:PlayQuestSound(questId, phase, npcId)
    if (not questId or not phase) then
        CLN:Print("Missing required arguments")
        CLN:Print("QuestId: ", questId)
        CLN:Print("QuestPhase: ", phase)
        return -- fail fast if no quest ID
    end

    if (VoiceoverPlayer.currentlyPlaying
        and VoiceoverPlayer.currentlyPlaying.questId == questId
        and VoiceoverPlayer.currentlyPlaying.phase == phase) then
        if (VoiceoverPlayer.currentlyPlaying:isPlaying()) then
            CLN.Utils:LogDebug("Quest audio is already playing: " .. questId)
            return
        end
    end

    local addonsFolderPath = "Interface\\AddOns\\"
    local fileName = questId .. "_" .. phase .. ".ogg"
    local fileLocation = "\\voiceovers\\" .. fileName
    local success, newSoundHandle

    if (VoiceoverPlayer.currentlyPlaying
        and CLN.db.profile.enableQuestPlaybackQueueing
        and VoiceoverPlayer.currentlyPlaying:isPlaying()
        and VoiceoverPlayer.currentlyPlaying.soundHandle
        and VoiceoverPlayer.currentlyPlaying.cantBeInterrupted) then

        for _, queuedAudio in ipairs(CLN.questsQueue) do
            if (queuedAudio.questId == questId and queuedAudio.phase == phase) then
                if (CLN.db.profile.debugMode) then
                    CLN:Print("Found a quest match in queue: ", queuedAudio.questId, "Quest Title: ", queuedAudio.title)
                end
                return
            end
        end

        -- queue the sound and exit if last on is still playing and is a quest
        local audioFileInfo = {}
            audioFileInfo.questId = questId
            audioFileInfo.phase = phase
            audioFileInfo.title = CLN:GetTitleForQuestID(questId)
            audioFileInfo.cantBeInterrupted = true
            audioFileInfo.npcId = npcId

        if (CLN.db.profile.debugMode) then
            CLN:Print("Queued quest: ", audioFileInfo.questId, "Quest Title: ", audioFileInfo.title)
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
            if (CLN.db.profile.debugMode) then
                CLN:Print("FileNameFound: ", fileNameFound, " in : ", voiceoverPath)
            end

            success, newSoundHandle = PlaySoundFile(voiceoverPath, CLN.db.profile.audioChannel)
            if (success) then
                VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer:GetCurrentlyPlayingObject()

                VoiceoverPlayer.currentlyPlaying.soundHandle = newSoundHandle
                VoiceoverPlayer.currentlyPlaying.phase = phase
                VoiceoverPlayer.currentlyPlaying.questId = questId
                VoiceoverPlayer.currentlyPlaying.npcId = npcId
                VoiceoverPlayer.currentlyPlaying.title = CLN:GetTitleForQuestID(questId)
                VoiceoverPlayer.currentlyPlaying.cantBeInterrupted = true
                -- Mark playback start time for animation gating
                if GetTime then
                    VoiceoverPlayer.currentlyPlaying.startTime = GetTime()
                end

                -- Always start fresh for new playback to avoid stale state
                if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
                    CLN.ReplayFrame:ResetAnimationState()
                end

                if (VoiceoverPlayer.currentlyPlaying.title) then
                    table.remove(CLN.questsQueue, 1)
                    if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                    CLN.ReplayFrame:UpdateDisplayFrameState()
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
        if (CLN.db.profile.printMissingFiles) then
            CLN:Print("Missing voiceover file: ", fileName)
        end
        for _, queuedAudio in ipairs(CLN.questsQueue) do
            if (queuedAudio.questId == questId and queuedAudio.phase == phase) then
                table.remove(CLN.questsQueue, 1)
                if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                break
            end
        end
    end

    CLN.ReplayFrame:UpdateDisplayFrameState()
    -- Only trigger animation update if playback didn't start successfully
    -- (successful playback already triggered it above)
    if not success and CLN.ReplayFrame and CLN.ReplayFrame.UpdateConversationAnimation then
        CLN.ReplayFrame:UpdateConversationAnimation()
    end
end

function VoiceoverPlayer:PlayNonQuestSound(npcId, soundType, text, gender)
    if (not npcId or not soundType or not text) then
        CLN:Print("Arguments missing to play non quest sound.")
        CLN:Print("NpcId: ", npcId)
        CLN:Print("SoundType: ", soundType)
        CLN:Print("Text: ", text)
        return
    end

    if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle) then
        if (VoiceoverPlayer.currentlyPlaying.cantBeInterrupted
            and VoiceoverPlayer.currentlyPlaying:isPlaying()
            and CLN.db.profile.enableQuestPlaybackQueueing) then
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
            VoiceoverPlayer.currentlyPlaying.cantBeInterrupted = false
            VoiceoverPlayer.currentlyPlaying.title = text
            -- Mark playback start time for animation gating
            if GetTime then
                VoiceoverPlayer.currentlyPlaying.startTime = GetTime()
            end

            -- Always start fresh for new playback to avoid stale state
            if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
                CLN.ReplayFrame:ResetAnimationState()
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
        if (CLN.db.profile.printMissingFiles) then
            if hashes then
                for index, hash in ipairs(hashes) do
                    CLN:Print("Missing voiceover file: " .. npcId .. "_".. soundType .. "_" .. hash .. ".ogg")
                end
            end
        end
    end

    CLN.ReplayFrame:UpdateDisplayFrameState()
    -- Only trigger animation update if playback didn't start successfully
    -- (successful playback already triggered it above)
    if not success and CLN.ReplayFrame and CLN.ReplayFrame.NpcModelFrame and CLN.ReplayFrame.NpcModelFrame:IsShown()
        and CLN.ReplayFrame.UpdateConversationAnimation then
        CLN.ReplayFrame:UpdateConversationAnimation()
    end
end