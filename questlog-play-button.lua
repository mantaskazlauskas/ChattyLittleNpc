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
        local questID = PlayButton:GetSelectedQuest()
        if questID then
            ChattyLittleNpc.Voiceovers:PlayQuestSound(questID, "Desc")
        end
    end)
    button:Hide()

    PlayButton.buttons[buttonName] = button
end

function PlayButton:UpdatePlayButton()
    local questID = PlayButton:GetSelectedQuest()
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

function PlayButton:GetSelectedQuest()
    if ChattyLittleNpc.useNamespaces and C_QuestLog and C_QuestLog.GetSelectedQuest then
        return C_QuestLog.GetSelectedQuest()
    else
        local selectedIndex = GetQuestLogSelection()
        if selectedIndex and selectedIndex > 0 then
            local quesTitle, _, _, _, _, _, _, questID = GetQuestLogTitle(selectedIndex)
            ChattyLittleNpc.Voiceovers.currentQuestId = questID
            ChattyLittleNpc.Voiceovers.currentPhase = "desc"
            ChattyLittleNpc.currentQuestTitle = quesTitle
            if ChattyLittleNpc.currentQuestTitle then
                ReplayFrame.ShowDisplayFrame(ChattyLittleNpc.currentQuestTitle .. " (description)")
            end
            return questID
        end
    end
    return nil
end


