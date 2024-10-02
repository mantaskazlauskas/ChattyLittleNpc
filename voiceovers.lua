---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local Voiceovers = {}
ChattyLittleNpc.Voiceovers = Voiceovers

Voiceovers.currentlyPlaying = {
    cantBeInterrupted = nil,
    npcId = nil,
    gender = nil,
    phase = nil,
    questId = nil,
    soundHandle = nil,
    title = nil,
    isPlaying = nil
}

-- Clear the queue from quests and stop current audio.
function Voiceovers:ForceStopCurrentSound(clearQueue)
    if clearQueue then
        ChattyLittleNpc.questsQueue = {}
    end

    if self.currentlyPlaying and self.currentlyPlaying.soundHandle then
        StopSound(self.currentlyPlaying.soundHandle)
        self.currentlyPlaying.isPlaying = false
    end

    ChattyLittleNpc.ReplayFrame:ShowDisplayFrame()
end

-- Stop current audio.
function Voiceovers:StopCurrentSound()
    if self.currentlyPlaying
        and self.currentlyPlaying.soundHandle
        and C_Sound.IsPlaying(self.currentlyPlaying.soundHandle) then
        StopSound(self.currentlyPlaying.soundHandle)
    end

    ChattyLittleNpc.ReplayFrame:ShowDisplayFrame()
end

function Voiceovers:PlayQuestSound(questId, phase, npcId, npcGender)
    if not questId or not phase then
        ChattyLittleNpc:Print("Missing required arguments")
        ChattyLittleNpc:Print("QuestId: ", questId)
        ChattyLittleNpc:Print("QuestPhase: ", phase)
        return -- fail fast if no quest ID
    end

    if self.currentlyPlaying and self.currentlyPlaying.questId == questId and self.currentlyPlaying.phase == phase then
        if self.currentlyPlaying.isPlaying then
            return -- skip if the same quest audio is already playing
        end
    end

    local basePath = "Interface\\AddOns\\ChattyLittleNpc_"
    local fileNameBase = questId .. "_" .. phase
    local success, newSoundHandle

    if self.currentlyPlaying
        and ChattyLittleNpc.db.profile.enableQuestPlaybackQueueing
        and self.currentlyPlaying.isPlaying
        and self.currentlyPlaying.soundHandle and self.currentlyPlaying.cantBeInterrupted and C_Sound.IsPlaying(self.currentlyPlaying.soundHandle) then

        for _, queuedAudio in ipairs(ChattyLittleNpc.questsQueue) do
            if queuedAudio.questId == questId and queuedAudio.phase == phase then
                return -- Stop checking further since we found a match in the queued quests
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
            ChattyLittleNpc:Print("Queued quest: ", audioFileInfo.title)
        end

        table.insert(ChattyLittleNpc.questsQueue, audioFileInfo)
        ChattyLittleNpc.ReplayFrame:ShowDisplayFrame()
        return
    end

    self:StopCurrentSound()

    success = false
    for _, folder in ipairs(ChattyLittleNpc.loadedVoiceoverPacks) do
        local corePathToVoiceovers = basePath .. folder .. "\\" .. "voiceovers" .. "\\"
        local retryCount = 0
        repeat
            local soundPath = self:GetVoiceoversPath(corePathToVoiceovers, fileNameBase, npcGender, retryCount)
            success, newSoundHandle = PlaySoundFile(soundPath, "Master")
            retryCount = retryCount + 1
        until success or retryCount > 6  -- Retry until success or tried all voiceover directories and extensions

        if success then
            if not self.currentlyPlaying then
                self.currentlyPlaying = {}
            end
            self.currentlyPlaying.soundHandle = newSoundHandle
            self.currentlyPlaying.phase = phase
            self.currentlyPlaying.gender = npcGender
            self.currentlyPlaying.questId = questId
            self.currentlyPlaying.npcId = npcId
            self.currentlyPlaying.title = ChattyLittleNpc:GetTitleForQuestID(questId)
            self.currentlyPlaying.cantBeInterrupted = true
            self.currentlyPlaying.isPlaying = true

            if self.currentlyPlaying.title then
                table.remove(ChattyLittleNpc.questsQueue, 1) 
                ChattyLittleNpc.ReplayFrame:ShowDisplayFrame()
            end
            break
        end
    end

    if not success then
        if ChattyLittleNpc.db.profile.printMissingFiles then
            ChattyLittleNpc:Print("Missing voiceover file (.ogg or .mp3): ", fileNameBase)
        end
        for _, queuedAudio in ipairs(ChattyLittleNpc.questsQueue) do
            if queuedAudio.questId == questId and queuedAudio.phase == phase then
                table.remove(ChattyLittleNpc.questsQueue, 1)
                break
            end
        end

    end

    ChattyLittleNpc.ReplayFrame:ShowDisplayFrame()
end

function Voiceovers:PlayNonQuestSound(npcId, soundType, text, npcGender)
    if not npcId or not soundType or not text then
        ChattyLittleNpc:Print("Arguments missing to play non quest sound.")
        ChattyLittleNpc:Print("NpcId: ", npcId)
        ChattyLittleNpc:Print("SoundType: ", soundType)
        ChattyLittleNpc:Print("Text: ", text)
        ChattyLittleNpc:Print("NpcGender(optional): ", npcGender)
        return
    end

    local depersonalisedText =  ChattyLittleNpc.Utils:CleanText(text)
    local hash = ChattyLittleNpc.MD5:GenerateHash(npcId .. depersonalisedText)

    if not npcId or not soundType or not hash then
        return -- fail fast in case of missing argument values
    end

    if self.currentlyPlaying and self.currentlyPlaying.soundHandle then
        if self.currentlyPlaying.cantBeInterrupted and self.currentlyPlaying.isPlaying and ChattyLittleNpc.db.profile.enableQuestPlaybackQueueing then
            return -- skip if a quest audio is playing
        end
        StopSound(self.currentlyPlaying.soundHandle, 0.5)
    end

    local basePath = "Interface\\AddOns\\ChattyLittleNpc_"
    local fileNameBase = npcId .. "_".. soundType .."_" .. hash
    local success, newSoundHandle

    if self.currentlyPlaying and self.currentlyPlaying.cantBeInterrupted and C_Sound.IsPlaying(self.currentlyPlaying.soundHandle) then
        return
    end

    success = false
    for _, folder in ipairs(ChattyLittleNpc.loadedVoiceoverPacks) do
        local corePathToVoiceovers = basePath .. folder .. "\\" .. "voiceovers" .. "\\"
        local retryCount = 0
        repeat
            local soundPath = self:GetVoiceoversPath(corePathToVoiceovers, fileNameBase, npcGender, retryCount)
            success, newSoundHandle = PlaySoundFile(soundPath, "Master")
            retryCount = retryCount + 1
        until success or retryCount > 6  -- Retry until success or tried all voiceover directories and extensions

        if success then
            if not self.currentlyPlaying then
                self.currentlyPlaying = {}
            end
            self.currentlyPlaying.soundHandle = newSoundHandle
            self.currentlyPlaying.npcId = npcId
            self.currentlyPlaying.gender = npcGender
            self.currentlyPlaying.cantBeInterrupted = false
            self.currentlyPlaying.isPlaying = true
            self.currentlyPlaying.title = depersonalisedText
            break
        end
    end

    if not success then
        if ChattyLittleNpc.db.profile.printMissingFiles then
            ChattyLittleNpc:Print("Missing voiceover file: " .. fileNameBase .. ".ogg or .mp3")
        end
        ChattyLittleNpc.Voiceovers.currentlyPlaying.isPlaying = false
    end

    ChattyLittleNpc.ReplayFrame:ShowDisplayFrame()
end

function Voiceovers:GetVoiceoversPath(corePathToVoiceovers, fileNameBase, npcGender, retryCount)
    local extensions = {".ogg", ".mp3"}
    local genderFolders = {"", "male\\", "female\\", "old\\"}

    local genderFolder = genderFolders[math.floor(retryCount / 2) + 1]
    local extension = extensions[(retryCount % 2) + 1]

    return corePathToVoiceovers .. genderFolder .. fileNameBase .. extension
end

function Voiceovers:GetFemaleVoiceoversPath(corePathToVoiceovers, fileName)
    return corePathToVoiceovers .. "female" .. "\\".. fileName
end

function Voiceovers:GetMaleVoiceoversPath(corePathToVoiceovers, fileName)
    return corePathToVoiceovers .. "male" .. "\\".. fileName
end

function Voiceovers:GetOldVoiceoversPath(corePathToVoiceovers, fileName)
    return corePathToVoiceovers .. fileName -- try the old directory if user didnt update voiceovers
end