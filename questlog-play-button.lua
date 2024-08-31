---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local ReplayFrame = ChattyLittleNpc.ReplayFrame

local PlayButton = {}
ChattyLittleNpc.PlayButton = PlayButton

PlayButton.buttons = {}

function PlayButton:AttachPlayButton(point, relativeTo, relativePoint, offsetX, offsetY, buttonName)
    local button = CreateFrame("Button", buttonName, relativeTo, "UIPanelButtonTemplate")
    button:SetSize(120, 25)
    button:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
    button:SetText("Play Voiceover")
    button:SetFrameStrata("TOOLTIP")
    button:SetScript("OnClick", function()
        local questID = C_QuestLog.GetSelectedQuest()
        if questID then
            ChattyLittleNpc.Voiceovers:PlayQuestSound(questID, "Desc")
        end
    end)
    button:Hide()

    PlayButton.buttons[buttonName] = button
end

function PlayButton:UpdatePlayButton()
    local questID = C_QuestLog.GetSelectedQuest()
    for buttonName, button in pairs(PlayButton.buttons) do
        if questID then
            button:Show()
        else
            button:Hide()
        end
    end
end

function PlayButton:HidePlayButton()
    for buttonName, button in pairs(PlayButton.buttons) do
        button:Hide()
    end
end


