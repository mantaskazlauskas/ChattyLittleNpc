---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local ReplayFrame = ChattyLittleNpc.ReplayFrame

local PlayButton = {}
ChattyLittleNpc.PlayButton = PlayButton
PlayButton.GossipButton = "ChattyLittleGossipButton"
PlayButton.QuestButton = "ChattyLittleQuestButton"
PlayButton.ItemTextButton = "ChattyLittleItemTextButton"

PlayButton.buttons = {}

function PlayButton:ClearButtons()
    if (_G[PlayButton.GossipButton]) then
        _G[PlayButton.GossipButton]:Hide()
        _G[PlayButton.GossipButton] = nil
    end

    if (_G[PlayButton.QuestButton]) then
        _G[PlayButton.QuestButton]:Hide()
        _G[PlayButton.QuestButton] = nil
    end

    if (_G[PlayButton.ItemTextButton]) then
        _G[PlayButton.ItemTextButton]:Hide()
        _G[PlayButton.ItemTextButton] = nil
    end
end

function PlayButton:AttachPlayButton(point, relativeTo, relativePoint, offsetX, offsetY, buttonName)
    PlayButton:ClearButtons()

    local button
    if (ChattyLittleNpc.isElvuiAddonLoaded) then
        button = CreateFrame("Button", buttonName, relativeTo, "UIPanelButtonTemplate")
            button:SetSize(32, 32) -- Adjusted to fit ElvUI's style better
            button:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)

        local ElvUI = PlayButton:GetElvUI()
        local ElvUISkins = ElvUI:GetModule('Skins')
        ElvUISkins:HandleButton(button)
        button:SetText("Play Voiceover")

        button:SetScript("OnEnter", function()
            button:SetBackdropBorderColor(1, 1, 0) -- Highlight border on hover
        end)

        button:SetScript("OnLeave", function()
            button:SetBackdropBorderColor(ElvUI.media.bordercolor) -- Reset border on leave
        end)
    else
        button = CreateFrame("Frame", buttonName, relativeTo)
            button:SetSize(64, 64)
            button:SetFrameStrata("TOOLTIP")

        local texture = button:CreateTexture(nil, "BACKGROUND")
            texture:SetAllPoints()
            texture:SetTexture("Interface\\AddOns\\ChattyLittleNpc\\Icons\\speech-bubble-border.png")

        -- Create a glow texture
        local glowTexture = button:CreateTexture(nil, "OVERLAY")
            glowTexture:SetAllPoints()
            glowTexture:SetTexture("Interface\\AddOns\\ChattyLittleNpc\\Icons\\speech-bubble-border-glow.png")
            glowTexture:Hide()

        button:SetScript("OnEnter", function()
            glowTexture:Show()
        end)

        button:SetScript("OnLeave", function()
            glowTexture:Hide()
        end)
    end

    button:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
    button:SetScript("OnMouseUp", function()
        local questID = PlayButton:GetSelectedQuest()

        if (questID) then
            ChattyLittleNpc.Voiceovers:PlayQuestSound(questID, "Desc")
        end
    end)
    button:Hide()

    PlayButton.buttons[buttonName] = button
end

function PlayButton:UpdatePlayButton()
    local questID = PlayButton:GetSelectedQuest()
    for buttonName, button in pairs(PlayButton.buttons) do

        if (questID) then
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
    if (ChattyLittleNpc.useNamespaces and C_QuestLog and C_QuestLog.GetSelectedQuest) then
        return C_QuestLog.GetSelectedQuest()
    else
        local selectedIndex = GetQuestLogSelection()

        if (selectedIndex and selectedIndex > 0) then
            local quesTitle, _, _, _, _, _, _, questID = GetQuestLogTitle(selectedIndex)
            ChattyLittleNpc.Voiceovers.currentQuestId = questID
            ChattyLittleNpc.Voiceovers.currentPhase = "desc"
            ChattyLittleNpc.currentQuestTitle = quesTitle

            if (ChattyLittleNpc.currentQuestTitle) then
                ChattyLittleNpc.ReplayFrame:UpdateDisplayFrameState()
            end
            return questID
        end
    end
    return nil
end

function PlayButton:CreatePlayVoiceoverButton(parentFrame, buttonName, onMouseUpFunction)
    PlayButton:ClearButtons()

    if (ChattyLittleNpc.isElvuiAddonLoaded) then
        local button = CreateFrame("Button", buttonName, parentFrame, "UIPanelButtonTemplate")
            button:SetSize(32, 32) -- Adjusted to fit ElvUI's style better

        local ElvUI = PlayButton:GetElvUI()
        local ElvUISkins = ElvUI:GetModule('Skins')
        ElvUISkins:HandleButton(button)
        button:SetText("Play Voiceover")

        button:SetScript("OnEnter", function()
            button:SetBackdropBorderColor(1, 1, 0) -- Highlight border on hover
        end)

        button:SetScript("OnLeave", function()
            button:SetBackdropBorderColor(ElvUI.media.bordercolor) -- Reset border on leave
        end)

        local posX = ChattyLittleNpc.db.profile.buttonPosX
        local posY = ChattyLittleNpc.db.profile.buttonPosY
        button:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", posX, posY)

        button:SetScript("OnMouseUp", onMouseUpFunction)

        return button
    else
        local button = CreateFrame("Frame", buttonName, parentFrame)
        button:SetSize(64, 64)
        button:SetFrameStrata("TOOLTIP")

        local texture = button:CreateTexture(nil, "BACKGROUND")
            texture:SetAllPoints()
            texture:SetTexture("Interface\\AddOns\\ChattyLittleNpc\\Icons\\speech-bubble-border.png")

        -- Create a glow texture
        local glowTexture = button:CreateTexture(nil, "OVERLAY")
            glowTexture:SetAllPoints()
            glowTexture:SetTexture("Interface\\AddOns\\ChattyLittleNpc\\Icons\\speech-bubble-border-glow.png")
            glowTexture:Hide()

        button:SetScript("OnEnter", function()
            glowTexture:Show()
        end)

        button:SetScript("OnLeave", function()
            glowTexture:Hide()
        end)

        local posX = ChattyLittleNpc.db.profile.buttonPosX
        local posY = ChattyLittleNpc.db.profile.buttonPosY
        button:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", posX, posY)

        button:SetScript("OnMouseUp", onMouseUpFunction)

        return button
    end
end

function PlayButton:UpdateButtonPositions()
    local x = ChattyLittleNpc.db.profile.buttonPosX or 0
    local y = ChattyLittleNpc.db.profile.buttonPosY or 0

    local buttonsToUpdate = {"GossipFramePlayButton", "QuestFramePlayButton"}
    for _, buttonName in pairs(buttonsToUpdate) do
        local button = _G[buttonName] -- Fetch the button by name
        if (button) then
            button:ClearAllPoints()
            if (buttonName == "GossipFramePlayButton") then
                button:SetPoint("TOPRIGHT", GossipFrame, "TOPRIGHT", x, y)
            elseif (buttonName == "QuestFramePlayButton") then
                button:SetPoint("TOPRIGHT", QuestFrame, "TOPRIGHT", x, y)
            end
        end
    end
end

function PlayButton:GetElvUI()
    local ElvUI = LibStub("AceAddon-3.0"):GetAddon("ElvUI")
    return ElvUI
end