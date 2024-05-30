local frame = CreateFrame("Frame")

local lastSoundHandle = nil  -- Variable to store the last played sound handle
ChattyLittleNpcTextsFromMissingFilesDB = ChattyLittleNpcTextsFromMissingFilesDB or {}  -- Initialize the saved variable as an empty table if it doesn't exist

-- Register events for quest progression and NPC interaction
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("GOSSIP_CLOSED")
frame:RegisterEvent("QUEST_FINISHED")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("QUEST_GREETING")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("ADDON_LOADED")  -- Register the ADDON_LOADED event to initialize the database

-- Function to stop currently playing sound
local function StopCurrentSound()
    if lastSoundHandle and type(lastSoundHandle) == "number" then
        StopSound(lastSoundHandle)
        lastSoundHandle = nil  -- Reset the sound handle after stopping
    end
end

-- Function to log missing sounds
local function LogMissingSound(questId, questTitle, phase)
    ChattyLittleNpcTextsFromMissingFilesDB[questId] = ChattyLittleNpcTextsFromMissingFilesDB[questId] or {}
    ChattyLittleNpcTextsFromMissingFilesDB[questId][phase] = "Missing file for quest: " .. questTitle .. ", phase: " .. phase
    print(ChattyLittleNpcTextsFromMissingFilesDB[questId][phase])
end

-- Function to play sound based on quest title, phase, and optional text
local function PlayQuestSound(questId, questTitle, phase)
    StopCurrentSound()  -- Ensure no sound is playing before starting a new one
    local soundPath = "Interface\\AddOns\\ChattyLittleNpc\\Sounds\\" .. phase .. "_" .. questTitle .. ".wav"
    local success, newSoundHandle = PlaySoundFile(soundPath, "Master")
    if success then
        lastSoundHandle = newSoundHandle  -- Only update handle if playing was successful
    else
        LogMissingSound(questId, questTitle, phase)
    end
end

-- Event handler function
local function OnEvent(self, event, ...)
    -- print(event)
    local questId, questTitle
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "ChattyLittleNpc" then
            ChattyLittleNpcTextsFromMissingFilesDB = ChattyLittleNpcTextsFromMissingFilesDB or {}
        end
    elseif event == "QUEST_DETAIL" or event == "QUEST_ACCEPTED" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        if event == "QUEST_DETAIL" then
            questTitle = GetTitleText()
            questId = GetQuestID()
            PlayQuestSound(questId, questTitle, "Desc")
        elseif event == "QUEST_PROGRESS" then
            questTitle = GetTitleText()
            questId = GetQuestID()
            PlayQuestSound(questId, questTitle, "Prog")
        elseif event == "QUEST_COMPLETE" then
            questTitle = GetTitleText()
            questId = GetQuestID()
            PlayQuestSound(questId, questTitle, "Comp")
        end
    elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
        StopCurrentSound()  -- Stop any currently playing sounds when the quest window is closed
    end
end

frame:SetScript("OnEvent", OnEvent)

-- Command to manually trigger the sound (optional)
SLASH_QUESTSOUND1 = "/questsound"
SlashCmdList["QUESTSOUND"] = function(msg, phase)
    local questId = tonumber(msg)
    local questInfo = C_QuestLog.GetInfo(questId)
    local questTitle = questInfo and questInfo.title or "Unknown"
    PlayQuestSound(questId, questTitle, phase or "Desc", "Manual trigger")
    print("Played sound for quest: " .. questTitle .. " phase: " .. (phase or "Desc"))
end
