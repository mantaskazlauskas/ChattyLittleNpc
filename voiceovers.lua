---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local Voiceovers = {}

Voiceovers.currentlyPlaying = {
    cantBeInterrupted = nil,
    gender = nil,
    phase = nil,
    questId = nil,
    soundHandle = nil,
    title = nil,
    finishedPlaying = nil
}

ChattyLittleNpc.Voiceovers = Voiceovers

function Voiceovers:StartSoundMonitor()
    C_Timer.NewTicker(1, function()
        if self.currentlyPlaying and self.currentlyPlaying.soundHandle and self.currentlyPlaying.cantBeInterrupted and C_Sound.IsPlaying(self.currentlyPlaying.soundHandle) then
            return -- Quest audio is still playing, do nothing
        end

        self.currentlyPlaying.finishedPlaying = true

        if ChattyLittleNpc.questsQueue and #ChattyLittleNpc.questsQueue > 0 then
            local nextAudioFileInfo = table.remove(ChattyLittleNpc.questsQueue, 1)
            if self.currentlyPlaying
                and nextAudioFileInfo.questId == self.currentlyPlaying.questId
                and nextAudioFileInfo.phase == self.currentlyPlaying.phase
                and #ChattyLittleNpc.questsQueue > 0
            then
                nextAudioFileInfo = table.remove(ChattyLittleNpc.questsQueue, 1) -- if next sound file is a duplicate of the last/current one then take the one after.    
            end
            self:PlayQuestSound(nextAudioFileInfo.questId, nextAudioFileInfo.phase, nextAudioFileInfo.gender)
        end

        ChattyLittleNpc.ReplayFrame:UpdateDisplayFrame()
    end)
end

-- Clear the queue from quests and stop current audio.
function Voiceovers:ForceStopCurrentSound(clearQueue)
    if clearQueue then
        ChattyLittleNpc.questsQueue = {}
    end

    if self.currentlyPlaying and self.currentlyPlaying.soundHandle then
        StopSound(self.currentlyPlaying.soundHandle)
        self.currentlyPlaying.finishedPlaying = true
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

-- Play quest audio or queue it if one is already playing.
function Voiceovers:PlayQuestSound(questId, phase, npcGender)
    if not questId or not phase then
        print("Missing required arguments")
        print("QuestId: ", questId)
        print("QuestPhase: ", phase)
        return -- fail fast if no quest ID
    end

    local basePath = "Interface\\AddOns\\ChattyLittleNpc_"
    local fileName = questId .. "_" .. phase .. ".mp3"
    local success, newSoundHandle

    if self.currentlyPlaying
        and ChattyLittleNpc.db.profile.enableQuestPlaybackQueueing
        and not self.currentlyPlaying.finishedPlaying
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

        table.insert(ChattyLittleNpc.questsQueue, audioFileInfo)
        ChattyLittleNpc.ReplayFrame:ShowDisplayFrame()
        return
    end

    self:StopCurrentSound()

    local suffix = ""
    if phase == "Desc" then suffix = " (description"
    elseif phase == "Prog" then suffix = " (progression"
    elseif phase == "Comp" then suffix = " (completion"
    end

    success = false
    for _, folder in ipairs(ChattyLittleNpc.loadedVoiceoverPacks) do
        local corePathToVoiceovers = basePath .. folder .. "\\" .. "voiceovers" .. "\\"
        local soundPath = self:GetVoiceoversPath(corePathToVoiceovers, fileName, npcGender)
        local retryCount = 0
        repeat
            -- skips on the first time by passing the first sound path to PlaySoundFile and if that fails tries all other gender folders.
            if success == nil then
                if retryCount == 1 then
                    soundPath = self:GetMaleVoiceoversPath(corePathToVoiceovers, fileName)
                elseif retryCount == 2 then
                    soundPath = self:GetFemaleVoiceoversPath(corePathToVoiceovers, fileName)
                elseif retryCount == 3 then
                    soundPath = self:GetOldVoiceoversPath(corePathToVoiceovers, fileName)
                end
                retryCount = retryCount + 1
            end
            success, newSoundHandle = PlaySoundFile(soundPath, "Master")
        until success or retryCount > 3  -- Retry until success or tried all voiceover directories

        if success then
            if not self.currentlyPlaying then
                self.currentlyPlaying = {}
            end
            self.currentlyPlaying.soundHandle = newSoundHandle
            self.currentlyPlaying.phase = phase
            self.currentlyPlaying.gender = npcGender
            self.currentlyPlaying.questId = questId
            self.currentlyPlaying.title = ChattyLittleNpc:GetTitleForQuestID(questId)
            self.currentlyPlaying.cantBeInterrupted = true
            self.currentlyPlaying.finishedPlaying = false

            if self.currentlyPlaying.title then
                ChattyLittleNpc.ReplayFrame:ShowDisplayFrame()
            end
            break
        end
    end

    if not success and ChattyLittleNpc.db.profile.printMissingFiles then
        print("Missing voiceover file: " .. fileName)
    end

    ChattyLittleNpc.ReplayFrame:ShowDisplayFrame()
end

-- Play non quest related text like gossip or text from items.
function Voiceovers:PlayNonQuestSound(npcId, soundType, text, npcGender)
    if not npcId or not soundType or not text then
        print("Arguments missing to play non quest sound.")
        print("NpcId: ", npcId)
        print("SoundType: ", soundType)
        print("Text: ", text)
        print("NpcGender(optional): ", npcGender)
        return
    end

    local depersonalisedText =  ChattyLittleNpc:CleanText(text)
    local hash = ChattyLittleNpc.MD5:GenerateHash(npcId .. depersonalisedText)

    if not npcId or not soundType or not hash then
        return -- fail fast in case of missing argument values
    end

    if self.currentlyPlaying and self.currentlyPlaying.soundHandle then
        if self.currentlyPlaying.cantBeInterrupted and not self.currentlyPlaying.finishedPlaying and ChattyLittleNpc.db.profile.enableQuestPlaybackQueueing then
            return -- skip if a quest audio is playing
        end
        StopSound(self.currentlyPlaying.soundHandle)
    end

    local basePath = "Interface\\AddOns\\ChattyLittleNpc_"
    local fileName = npcId .. "_".. soundType .."_" .. hash .. ".mp3"
    local success, newSoundHandle

    if self.currentlyPlaying and self.currentlyPlaying.cantBeInterrupted and C_Sound.IsPlaying(self.currentlyPlaying.soundHandle) then
        return
    end

    success = false
    for _, folder in ipairs(ChattyLittleNpc.loadedVoiceoverPacks) do
        local corePathToVoiceovers = basePath .. folder .. "\\" .. "voiceovers" .. "\\"
        local soundPath = self:GetVoiceoversPath(corePathToVoiceovers, fileName, npcGender)
        local retryCount = 0
        repeat
            -- skips on the first time by passing the first sound path to PlaySoundFile and if that fails tries all other gender folders.
            if success == nil then
                if retryCount == 1 then
                    soundPath = self:GetMaleVoiceoversPath(corePathToVoiceovers, fileName)
                elseif retryCount == 2 then
                    soundPath = self:GetFemaleVoiceoversPath(corePathToVoiceovers, fileName)
                elseif retryCount == 3 then
                    soundPath = self:GetOldVoiceoversPath(corePathToVoiceovers, fileName)
                end
                retryCount = retryCount + 1
            end
            success, newSoundHandle = PlaySoundFile(soundPath, "Master")
        until success or retryCount > 3  -- Retry until success or tried all voiceover directories

        if success then
            if not self.currentlyPlaying then
                self.currentlyPlaying = {}
            end
            self.currentlyPlaying.soundHandle = newSoundHandle
            self.currentlyPlaying.gender = npcGender
            self.currentlyPlaying.cantBeInterrupted = false
            break
        end
    end

    if not success and ChattyLittleNpc.db.profile.printMissingFiles then
        print("Missing voiceover file: " .. fileName)
    end
end

function Voiceovers:GetVoiceoversPath(corePathToVoiceovers, fileName, npcGender)
    if npcGender and (strlower(npcGender) == "male" or strlower(npcGender) == "female") then
        return corePathToVoiceovers .. strlower(npcGender) .. "\\".. fileName
    else
        return self:GetOldVoiceoversPath(corePathToVoiceovers, fileName)
    end
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