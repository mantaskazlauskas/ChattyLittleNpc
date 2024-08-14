---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local Voiceovers = {}

Voiceovers.lastSoundHandle = nil
Voiceovers.currentQuestId = nil
Voiceovers.currentQuestTitle = ""
Voiceovers.currentPhase = nil

ChattyLittleNpc.Voiceovers = Voiceovers

function Voiceovers:StopCurrentSound()
    if self.lastSoundHandle and type(self.lastSoundHandle) == "number" then
        StopSound(self.lastSoundHandle)
        self.lastSoundHandle = nil
    end

    ChattyLittleNpc.ReplayFrame.currentPlayingQuest = nil
    ChattyLittleNpc.ReplayFrame:UpdateDisplayFrame()
end

function Voiceovers:PlayQuestSound(questId, phase, npcGender)
    self:StopCurrentSound()
    self.currentQuestId = questId
    self.currentPhase = phase

    local basePath = "Interface\\AddOns\\ChattyLittleNpc_"
    local fileName = questId .. "_" .. phase .. ".mp3"
    local success, newSoundHandle

    local suffix = ""
    if phase == "Desc" then
        suffix = " (description"
    elseif phase == "Prog" then
        suffix = " (progression"
    elseif phase == "Comp" then
        suffix = " (completion"
    end

    success = false
    for _, folder in ipairs(ChattyLittleNpc.loadedVoiceoverPacks) do
        local corePathToVoiceovers = basePath .. folder .. "\\" .. "voiceovers" .. "\\"
        local soundPath = self:GetVoiceoversPath(corePathToVoiceovers, fileName, npcGender)
        local retryCount = 0
        repeat
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
            self.lastSoundHandle = newSoundHandle
            self.currentQuestTitle = ChattyLittleNpc:GetTitleForQuestID(questId)
            ChattyLittleNpc.ReplayFrame:AddQuestToQueue(questId, self.currentQuestTitle .. suffix .. ")", phase, npcGender)
            ChattyLittleNpc.ReplayFrame:ShowDisplayFrame()
            break
        end
    end

    if not success and ChattyLittleNpc.db.profile.printMissingFiles then
        self.currentQuestTitle = ChattyLittleNpc:GetTitleForQuestID(questId)
        ChattyLittleNpc.ReplayFrame:AddQuestToQueue(questId, self.currentQuestTitle .. suffix .. ", voiceover missing)", phase, npcGender)
        print("Missing voiceover file: " .. fileName)
    end

    ChattyLittleNpc.ReplayFrame.currentPlayingQuest = questId .. phase -- Track the currently playing quest
    ChattyLittleNpc.ReplayFrame:UpdateDisplayFrame()
end

function Voiceovers:PlayGossipSound(npcId, hash, npcGender)
    self:StopCurrentSound()

    local basePath = "Interface\\AddOns\\ChattyLittleNpc_"
    local fileName = npcId .. "_Gossip_" .. hash .. ".mp3"
    local success, newSoundHandle

    success = false
    for _, folder in ipairs(ChattyLittleNpc.loadedVoiceoverPacks) do
        local corePathToVoiceovers = basePath .. folder .. "\\" .. "voiceovers" .. "\\"
        local soundPath = self:GetVoiceoversPath(corePathToVoiceovers, fileName, npcGender)
        local retryCount = 0
        repeat
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
            self.lastSoundHandle = newSoundHandle
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