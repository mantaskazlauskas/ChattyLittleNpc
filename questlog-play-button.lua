local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local PlayButton = {}
ChattyLittleNpc.PlayButton = PlayButton

local playButton

function PlayButton:AttachPlayButton(detailsFrame)
    if not detailsFrame then return end
    playButton = CreateFrame("Button", "ChattyNPCPlayButton", detailsFrame, "UIPanelButtonTemplate")
    playButton:SetSize(70, 25)
    playButton:SetPoint("TOPRIGHT", detailsFrame, "TOPRIGHT", 0, 30)
    playButton:SetText("PLay Audio")
    playButton:SetScript("OnClick", function()
        local questID = C_QuestLog.GetSelectedQuest()
        if questID then
            ChattyLittleNpc:PlayQuestSound(questID, "Desc")
        end
    end)
    playButton:Hide()
end

function PlayButton:UpdatePlayButton()
    local questID = C_QuestLog.GetSelectedQuest()
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
