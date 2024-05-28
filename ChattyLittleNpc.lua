local frame = CreateFrame("Frame")

local lastSoundHandle = nil  -- Variable to store the last played sound handle

-- Register events for quest progression and NPC interaction
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("GOSSIP_CLOSED")
frame:RegisterEvent("QUEST_FINISHED")

-- Function to stop currently playing sound
local function StopCurrentSound()
    if lastSoundHandle and type(lastSoundHandle) == "number" then
        StopSound(lastSoundHandle)
        lastSoundHandle = nil  -- Reset the sound handle after stopping
    end
end

-- Function to play sound based on quest title
local function PlayQuestSound(questTitle)
    StopCurrentSound()  -- Ensure no sound is playing before starting a new one
    local soundPath = "Interface\\AddOns\\ChattyLittleNpc\\Sounds\\" .. questTitle .. ".wav"
    local success, newSoundHandle = PlaySoundFile(soundPath, "Master")
    if success then
        lastSoundHandle = newSoundHandle  -- Only update handle if playing was successful
    else
        print("Failed to play sound for: " .. questTitle)
    end
end

-- Event handler function
local function OnEvent(self, event, ...)
    if event == "QUEST_DETAIL" or event == "QUEST_ACCEPTED" then
        local questTitle
        if event == "QUEST_DETAIL" then
            questTitle = GetTitleText()
        elseif event == "QUEST_ACCEPTED" then
            local questIndex = ...
            local questID = C_QuestLog.GetQuestIDForLogIndex(questIndex)
            local questInfo = C_QuestLog.GetInfo(questID)
            questTitle = questInfo and questInfo.title
        end
        if questTitle and questTitle ~= "" then
            PlayQuestSound(questTitle)
        end
    elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
        StopCurrentSound()  -- Stop any currently playing sounds when the quest window is closed
    end
end

-- Set the event handler
frame:SetScript("OnEvent", OnEvent)

-- Command to manually trigger the sound (optional)
SLASH_QUESTSOUND1 = "/questsound"
SlashCmdList["QUESTSOUND"] = function(msg)
    PlayQuestSound(msg)
    print("Played sound for quest: " .. msg)
end
