local frame = CreateFrame("Frame")

local lastSoundHandle = nil  -- Variable to store the last played sound handle
ChattyLittleNpcTextsFromMissingFilesDB = ChattyLittleNpcTextsFromMissingFilesDB or {}  -- Initialize the saved variable as an empty table if it doesn't exist

-- Register events for quest progression and NPC interaction
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

-- Function to play sound based on quest title, phase, and optional text
local function PlayQuestSound(questId, questTitle, phase)
    StopCurrentSound()  -- Ensure no sound is playing before starting a new one

    -- List of backup folders if the sound is not found in the current zone folder
    local backupFolders = { "Landfall", "Pandaren Campaign", "Scenario", "Timewalking" }

    local basePath = "Interface\\AddOns\\ChattyLittleNpc\\Sounds\\"

    -- First try the current zone
    local currentZone = GetZoneText()
    local fileName = questId .. "_" .. phase .. "_" .. questTitle .. ".mp3"
    local soundPath = basePath .. currentZone .. "\\" .. fileName
    local success, newSoundHandle = PlaySoundFile(soundPath, "Dialog")
    if not success then
        -- If the sound file in the current zone folder fails, try the backup folders for quest categories and types
        for _, folder in ipairs(backupFolders) do
            soundPath = basePath .. folder .. "\\" .. questId .. "_" .. phase .. "_" .. questTitle .. ".mp3"
            success, newSoundHandle = PlaySoundFile(soundPath, "Dialog")
            if success then
                lastSoundHandle = newSoundHandle
                break
            end
        end
    end

    -- If no file was successfully played
    if not success then
        print("Missing voiceover file: " .. fileName)
    else
        lastSoundHandle = newSoundHandle  -- Update the handle if playing was successful
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
    elseif event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
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
    -- elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
    --     StopCurrentSound()  -- Stop any currently playing sounds when the quest window is closed
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
