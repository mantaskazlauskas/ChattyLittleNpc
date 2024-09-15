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


function PlayButton:CreateGossipButton()
    local button = CreateFrame("Button", "GossipFramePlayButton", GossipFrame, "UIPanelButtonTemplate")

    button:SetSize(120, 25)
    button:SetText("Play Voiceover")
    button:SetFrameStrata("DIALOG")

    local posX = ChattyLittleNpc.db.profile.buttonPosX
    local posY = ChattyLittleNpc.db.profile.buttonPosY
    button:SetPoint("TOPRIGHT", GossipFrame, "TOPRIGHT", posX, posY)
    button:SetScript("OnClick", function()
        local _, npcGender, _, _, _, unitId = ChattyLittleNpc:GetUnitInfo("npc")
        local gossipText = C_GossipInfo.GetText()

        ChattyLittleNpc.Voiceovers:PlayNonQuestSound(unitId, "Gossip", gossipText, npcGender)
    end)

    return button
end

function PlayButton:CreatePlayQuestVoiceoverButton()
    local button = CreateFrame("Button", "QuestFramePlayButton", QuestFrame, "UIPanelButtonTemplate")

    button:SetSize(120, 25)
    button:SetText("Play Voiceover")
    button:SetFrameStrata("DIALOG")
    local posX = ChattyLittleNpc.db.profile.buttonPosX
    local posY = ChattyLittleNpc.db.profile.buttonPosY
    button:SetPoint("TOPRIGHT", QuestFrame, "TOPRIGHT", posX, posY)
    button:SetScript("OnClick", function()
        local _, npcGender, _, _, _, _ = ChattyLittleNpc:GetUnitInfo("npc")
        local questID = GetQuestID()
        local questPhase
        if QuestFrameDetailPanel and QuestFrameDetailPanel:IsShown() then
            questPhase = "Desc"
        elseif QuestFrameProgressPanel and QuestFrameProgressPanel:IsShown() then
            questPhase = "Prog"
        elseif QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() then
            questPhase = "Comp"
        end

        ChattyLittleNpc.Voiceovers:PlayQuestSound(questID, questPhase, npcGender)
    end)

    return button
end

function PlayButton:UpdateButtonPositions()
    local x = ChattyLittleNpc.db.profile.buttonPosX or 0
    local y = ChattyLittleNpc.db.profile.buttonPosY or 0

    local buttonsToUpdate = {"GossipFramePlayButton", "QuestFramePlayButton"}
    for _, buttonName in pairs(buttonsToUpdate) do
        local button = _G[buttonName] -- Fetch the button by name
        if button then
            button:ClearAllPoints()
            if buttonName == "GossipFramePlayButton" then
                button:SetPoint("TOPRIGHT", GossipFrame, "TOPRIGHT", x, y)
            elseif buttonName == "QuestFramePlayButton" then
                button:SetPoint("TOPRIGHT", QuestFrame, "TOPRIGHT", x, y)
            end
        end
    end
end