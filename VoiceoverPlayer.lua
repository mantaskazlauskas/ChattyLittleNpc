---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class VoiceoverPlayer
local VoiceoverPlayer = {}
ChattyLittleNpc.VoiceoverPlayer = VoiceoverPlayer

VoiceoverPlayer.currentlyPlaying = {
    cantBeInterrupted = nil,
    npcId = nil,
    gender = nil,
    phase = nil,
    questId = nil,
    soundHandle = nil,
    title = nil,
    isPlaying = nil,
    stopped = nil
}

-- Clear the queue from quests and stop current audio.
function VoiceoverPlayer:ForceStopCurrentSound(clearQueue)
    if (clearQueue) then
        ChattyLittleNpc.questsQueue = {}
    end

    if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle) then
        if (ChattyLittleNpc.db.profile.debugMode) then
            ChattyLittleNpc:Print("Force stopping current sound handle", VoiceoverPlayer.currentlyPlaying.soundHandle)
        end
        StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle)
        VoiceoverPlayer.currentlyPlaying.isPlaying = false
    end

    ChattyLittleNpc.ReplayFrame:UpdateDisplayFrameState()
end

-- Stop current audio.
function VoiceoverPlayer:StopCurrentSound()
    if (VoiceoverPlayer.currentlyPlaying
        and VoiceoverPlayer.currentlyPlaying.soundHandle
        and C_Sound.IsPlaying(VoiceoverPlayer.currentlyPlaying.soundHandle)) then
        StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle)
    end

    ChattyLittleNpc.ReplayFrame:UpdateDisplayFrameState()
end

function VoiceoverPlayer:PlayQuestSound(questId, phase, npcId, npcGender)
    if (not questId or not phase) then
        ChattyLittleNpc:Print("Missing required arguments")
        ChattyLittleNpc:Print("QuestId: ", questId)
        ChattyLittleNpc:Print("QuestPhase: ", phase)
        return -- fail fast if no quest ID
    end

    if (VoiceoverPlayer.currentlyPlaying
        and VoiceoverPlayer.currentlyPlaying.questId == questId
        and VoiceoverPlayer.currentlyPlaying.phase == phase) then
        if (VoiceoverPlayer.currentlyPlaying.isPlaying) then
            if (ChattyLittleNpc.db.profile.debugMode) then
                ChattyLittleNpc:Print("Quest audio is already playing: ", questId)
            end
            return
        end
    end

    local addonsFolderPath = "Interface\\AddOns\\"
    local fileName = questId .. "_" .. phase .. ".ogg"
    local fileLocation = "\\voiceovers\\" .. fileName
    local success, newSoundHandle

    if (VoiceoverPlayer.currentlyPlaying
        and ChattyLittleNpc.db.profile.enableQuestPlaybackQueueing
        and VoiceoverPlayer.currentlyPlaying.isPlaying
        and VoiceoverPlayer.currentlyPlaying.soundHandle
        and VoiceoverPlayer.currentlyPlaying.cantBeInterrupted
        and C_Sound.IsPlaying(VoiceoverPlayer.currentlyPlaying.soundHandle)) then

        for _, queuedAudio in ipairs(ChattyLittleNpc.questsQueue) do
            if (queuedAudio.questId == questId and queuedAudio.phase == phase) then
                if (ChattyLittleNpc.db.profile.debugMode) then
                    ChattyLittleNpc:Print("Found a quest match in queue: ", queuedAudio.questId, "Quest Title: ", queuedAudio.title)
                end
                return
            end
        end

        -- queue the sound and exit if last on is still playing and is a quest
        local audioFileInfo = {}
            audioFileInfo.questId = questId
            audioFileInfo.phase = phase
            audioFileInfo.gender = npcGender
            audioFileInfo.title = ChattyLittleNpc:GetTitleForQuestID(questId)
            audioFileInfo.cantBeInterrupted = true
            audioFileInfo.npcId = npcId

        if (ChattyLittleNpc.db.profile.debugMode) then
            ChattyLittleNpc:Print("Queued quest: ", audioFileInfo.questId, "Quest Title: ", audioFileInfo.title)
        end

        table.insert(ChattyLittleNpc.questsQueue, audioFileInfo)
        ChattyLittleNpc.ReplayFrame:UpdateDisplayFrameState()
        return
    end

    VoiceoverPlayer:StopCurrentSound()

    for packName, packData in pairs(ChattyLittleNpc.VoiceoverPacks) do
        local fileNameFound = ChattyLittleNpc.Utils:ContainsString(packData.Voiceovers, fileName)
        if (fileNameFound) then
            local voiceoverPath = addonsFolderPath .. packName .. fileLocation
            if(ChattyLittleNpc.db.profile.debugMode) then
                ChattyLittleNpc:Print("FileNameFound: ", fileNameFound, " in : ", voiceoverPath)
            end

            success, newSoundHandle = PlaySoundFile(voiceoverPath, ChattyLittleNpc.db.profile.audioChannel)
            if (success) then
                VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer.currentlyPlaying or {}

                VoiceoverPlayer.currentlyPlaying.soundHandle = newSoundHandle
                VoiceoverPlayer.currentlyPlaying.phase = phase
                VoiceoverPlayer.currentlyPlaying.gender = npcGender
                VoiceoverPlayer.currentlyPlaying.questId = questId
                VoiceoverPlayer.currentlyPlaying.npcId = npcId
                VoiceoverPlayer.currentlyPlaying.title = ChattyLittleNpc:GetTitleForQuestID(questId)
                VoiceoverPlayer.currentlyPlaying.cantBeInterrupted = true
                VoiceoverPlayer.currentlyPlaying.isPlaying = true

                if (VoiceoverPlayer.currentlyPlaying.title) then
                    table.remove(ChattyLittleNpc.questsQueue, 1)
                    ChattyLittleNpc.ReplayFrame:UpdateDisplayFrameState()
                end
            end
            break
        end
    end

    if (not success) then
        if (ChattyLittleNpc.db.profile.printMissingFiles) then
            ChattyLittleNpc:Print("Missing voiceover file: ", fileName)
        end
        for _, queuedAudio in ipairs(ChattyLittleNpc.questsQueue) do
            if (queuedAudio.questId == questId and queuedAudio.phase == phase) then
                table.remove(ChattyLittleNpc.questsQueue, 1)
                break
            end
        end
    end

    ChattyLittleNpc.ReplayFrame:UpdateDisplayFrameState()
end

function VoiceoverPlayer:PlayNonQuestSound(npcId, soundType, text, npcGender)
    if (not npcId or not soundType or not text) then
        ChattyLittleNpc:Print("Arguments missing to play non quest sound.")
        ChattyLittleNpc:Print("NpcId: ", npcId)
        ChattyLittleNpc:Print("SoundType: ", soundType)
        ChattyLittleNpc:Print("Text: ", text)
        ChattyLittleNpc:Print("NpcGender(optional): ", npcGender)
        return
    end

    local depersonalisedText =  ChattyLittleNpc.Utils:CleanText(text)
    local hash = ChattyLittleNpc.MD5:GenerateHash(npcId .. depersonalisedText)
    -- transition to new text cleaning method
    local depersonalisedText2 =  ChattyLittleNpc.Utils:CleanTextV2(text)
    local hash2 = ChattyLittleNpc.MD5:GenerateHash(npcId .. depersonalisedText2)

    local hashes = {hash, hash2}

    if (not npcId or not soundType or not hash) then
        return -- fail fast in case of missing argument values
    end

    if (VoiceoverPlayer.currentlyPlaying and VoiceoverPlayer.currentlyPlaying.soundHandle) then
        if (VoiceoverPlayer.currentlyPlaying.cantBeInterrupted
            and VoiceoverPlayer.currentlyPlaying.isPlaying
            and ChattyLittleNpc.db.profile.enableQuestPlaybackQueueing) then
            return -- skip if a quest audio is playing
        end
        StopSound(VoiceoverPlayer.currentlyPlaying.soundHandle, 0.5)
    end

    local addonsFolderPath = "Interface\\AddOns\\"
    local success, newSoundHandle

    if (VoiceoverPlayer.currentlyPlaying
        and VoiceoverPlayer.currentlyPlaying.cantBeInterrupted
        and C_Sound.IsPlaying(VoiceoverPlayer.currentlyPlaying.soundHandle)) then
        return
    end

    success = false
    for _, hash in ipairs(hashes) do
        local fileName = npcId .. "_".. soundType .."_" .. hash .. ".ogg"
        local fileLocation = "\\voiceovers\\" .. fileName

        for packName, packData in pairs(ChattyLittleNpc.VoiceoverPacks) do
            local fileNameFound = ChattyLittleNpc.Utils:ContainsString(packData.Voiceovers, fileName)
            if (fileNameFound) then
                local voiceoverPath = addonsFolderPath .. packName .. fileLocation
                if(ChattyLittleNpc.db.profile.debugMode) then
                    ChattyLittleNpc:Print("FileNameFound: ", fileNameFound, " in : ", voiceoverPath)
                end

                success, newSoundHandle = PlaySoundFile(voiceoverPath, ChattyLittleNpc.db.profile.audioChannel)
                if (success) then
                    VoiceoverPlayer.currentlyPlaying = VoiceoverPlayer.currentlyPlaying or {}
                    VoiceoverPlayer.currentlyPlaying.soundHandle = newSoundHandle
                    VoiceoverPlayer.currentlyPlaying.npcId = npcId
                    VoiceoverPlayer.currentlyPlaying.gender = npcGender
                    VoiceoverPlayer.currentlyPlaying.cantBeInterrupted = false
                    VoiceoverPlayer.currentlyPlaying.isPlaying = true
                    VoiceoverPlayer.currentlyPlaying.title = depersonalisedText
                end
                break
            end
        end
        if (success) then
            break
        end
    end

    if (not success) then
        if (ChattyLittleNpc.db.profile.printMissingFiles) then
            ChattyLittleNpc:Print("Missing voiceover file: " .. npcId .. "_".. soundType .."_" .. hash .. ".ogg")
            ChattyLittleNpc:Print("Missing voiceover file: " .. npcId .. "_".. soundType .."_" .. hash2 .. ".ogg")
        end
        if (ChattyLittleNpc.VoiceoverPlayer.currentlyPlaying) then
            ChattyLittleNpc.VoiceoverPlayer.currentlyPlaying.isPlaying = false
        end
    end

    ChattyLittleNpc.ReplayFrame:UpdateDisplayFrameState()
end