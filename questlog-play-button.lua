local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local PlayButton = {}
ChattyLittleNpc.PlayButton = PlayButton

local playButton

function PlayButton:GetSelectedQuest()
    if IsRetailVersion() and C_QuestLog and C_QuestLog.GetSelectedQuest then
        return C_QuestLog.GetSelectedQuest()
    else
        local selectedIndex = GetQuestLogSelection()
        if selectedIndex and selectedIndex > 0 then
            local _, _, _, _, _, _, _, questID = GetQuestLogTitle(selectedIndex)
            print(questID)
            return questID
        end
    end
    return nil
end

function PlayButton:AttachPlayButton(detailsFrame)
    if not detailsFrame then return end
    playButton = CreateFrame("Button", "ChattyNPCPlayButton", detailsFrame, "UIPanelButtonTemplate")
    playButton:SetSize(70, 25)
    playButton:SetPoint("TOPRIGHT", detailsFrame, "TOPRIGHT", 0, 30)
    playButton:SetText("Play Audio")
    playButton:SetScript("OnClick", function()
        local questID = PlayButton.GetSelectedQuest()
        if questID then
            ChattyLittleNpc:PlayQuestSound(questID, "Desc")
        end
    end)
    playButton:Hide()
end

function PlayButton:UpdatePlayButton()
    local questID = PlayButton.GetSelectedQuest()
    if questID and playButton then
        playButton:Show()
    else
        if playButton then
            playButton:Hide()
        end
    end
end

function PlayButton:HidePlayButton()
    if playButton then
        playButton:Hide()
    end
end

function IsRetailVersion()
    -- This function checks if the game version is Retail by trying to access an API exclusive to Retail
    return C_QuestLog ~= nil
end
