---@class ChattyLittleNpc: AceAddon-3.0, AceConsole-3.0, AceEvent-3.0
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = ChattyLittleNpc.ReplayFrame

---@class PlayButton
local PlayButton = {}
ChattyLittleNpc.PlayButton = PlayButton

PlayButton.GossipButton = "ChattyLittleGossipButton"
PlayButton.QuestButton = "ChattyLittleQuestButton"
PlayButton.ItemTextButton = "ChattyLittleItemTextButton"

PlayButton.DetailFrameButton = "ChattyLittleDetailFrameButton"
PlayButton.QuestLogFrameButton = "ChattyLittleQuestLogFrameButton"
PlayButton.QuestLogDetailFrameButton = "ChattyLittleQuestLogDetailFrameButton"


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

function PlayButton:ClearQuestLogAndDetailButtons()
    if (_G[PlayButton.DetailFrameButton]) then
        _G[PlayButton.DetailFrameButton]:Hide()
        _G[PlayButton.DetailFrameButton] = nil
    end

    if (_G[PlayButton.QuestLogFrameButton]) then
        _G[PlayButton.QuestLogFrameButton]:Hide()
        _G[PlayButton.QuestLogFrameButton] = nil
    end

    if (_G[PlayButton.QuestLogDetailFrameButton]) then
        _G[PlayButton.QuestLogDetailFrameButton]:Hide()
        _G[PlayButton.QuestLogDetailFrameButton] = nil
    end
end

function PlayButton:AttachPlayButton(parentFrame, offsetX, offsetY, buttonName)
    PlayButton:ClearButtons()

    local questID = PlayButton:GetSelectedQuest()
    if (questID) then
        for packName, packData in pairs(ChattyLittleNpc.VoiceoverPacks) do
            local questFileName =  questID .. "_Desc"
            local fileNameFound = ChattyLittleNpc.Utils:ContainsString(packData.Voiceovers, questFileName)
            if fileNameFound then
                if (ChattyLittleNpc.isElvuiAddonLoaded) then
                    return PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, function()
                        ChattyLittleNpc.VoiceoverPlayer:PlayQuestSound(questID, "Desc")
                    end)
                else
                    return PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, function()
                        ChattyLittleNpc.VoiceoverPlayer:PlayQuestSound(questID, "Desc")
                    end)
                end
            end
        end
    end
end

function PlayButton:CreatePlayVoiceoverButton(parentFrame, buttonName, onMouseUpFunction)
    PlayButton:ClearButtons()

    local offsetX = ChattyLittleNpc.db.profile.buttonPosX
    local offsetY = ChattyLittleNpc.db.profile.buttonPosY

    if (ChattyLittleNpc.isElvuiAddonLoaded) then
        return PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction)
    else
        return PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction)
    end
end

function PlayButton:AttachQuestLogAndDetailsButtons()
    PlayButton:ClearQuestLogAndDetailButtons()

    local DetailsFrame = QuestMapFrame and QuestMapFrame.DetailsFrame
    if (DetailsFrame) then
        ChattyLittleNpc:Print("DetailsFrame is available")
        PlayButton:AttachPlayButton(DetailsFrame, -10, -10, PlayButton.DetailFrameButton)
    end

    if (_G["QuestLogFrame"]) then
        ChattyLittleNpc:Print("QuestLogFrame is available")
        PlayButton:AttachPlayButton(_G["QuestLogFrame"], 40, 40, PlayButton.QuestLogFrameButton)
    end

    if (_G["QuestLogDetailFrame"]) then
        ChattyLittleNpc:Print("QuestLogDetailFrame is available")
        PlayButton:AttachPlayButton(_G["QuestLogDetailFrame"], 40, 40, PlayButton.QuestLogDetailFrameButton)
    end
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
            local _, _, _, _, _, _, _, questID = GetQuestLogTitle(selectedIndex)
            return questID
        end
    end
    return nil
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

function PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction)
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

    button:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", offsetX, offsetY)

    button:SetScript("OnMouseUp", onMouseUpFunction)

    -- Make the button draggable
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")

    button:SetScript("OnDragStart", function(self)
        self:StartMoving()
        self:SetScript("OnUpdate", function()
            local right, top = self:GetRight(), self:GetTop()
            local parentRight, parentTop = parentFrame:GetRight(), parentFrame:GetTop()
            local newX = parentRight - right
            local newY = parentTop - top
    
            -- Constrain the movement within -100 to 100 units in both x and y axes
            if newX < -100 then newX = -100 end
            if newY < -100 then newY = -100 end
            if newX > 100 then newX = 100 end
            if newY > 100 then newY = 100 end
    
            self:ClearAllPoints()
            self:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -newX, -newY)
        end)
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)

        -- Save the new position
        local right, top = self:GetRight(), self:GetTop()
        local parentRight, parentTop = parentFrame:GetRight(), parentFrame:GetTop()
        local newX = parentRight - right
        local newY = parentTop - top

        -- Constrain the movement within -100 to 100 units in both x and y axes
        if newX < -100 then newX = -100 end
        if newY < -100 then newY = -100 end
        if newX > 100 then newX = 100 end
        if newY > 100 then newY = 100 end

        ChattyLittleNpc.db.profile.buttonPosX = -newX
        ChattyLittleNpc.db.profile.buttonPosY = -newY
    end)

    return button
end

-- ElvUI Support
function PlayButton:GetElvUI()
    local ElvUI = LibStub("AceAddon-3.0"):GetAddon("ElvUI")
    return ElvUI
end

function PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction)
    local button = CreateFrame("Button", buttonName, parentFrame, "UIPanelButtonTemplate")
    button:SetSize(90, 25) -- Adjusted to fit ElvUI's style better

    local ElvUI = PlayButton:GetElvUI()
    local ElvUISkins = ElvUI:GetModule('Skins')
    ElvUISkins:HandleButton(button)
    button:SetText("Play Voiceover")

    button:SetScript("OnEnter", function()
        button:SetBackdropBorderColor(1, 1, 0) -- Highlight border on hover
    end)

    button:SetScript("OnLeave", function()
        button:SetBackdropBorderColor(unpack(ElvUI.media.bordercolor)) -- Reset border on leave
    end)

    button:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", offsetX, offsetY)

    button:SetScript("OnMouseUp", onMouseUpFunction)

    -- Make the button draggable
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")

    button:SetScript("OnDragStart", function(self)
        self:StartMoving()
        self:SetScript("OnUpdate", function()
            local right, top = self:GetRight(), self:GetTop()
            local parentRight, parentTop = parentFrame:GetRight(), parentFrame:GetTop()
            local newX = parentRight - right
            local newY = parentTop - top

            -- Constrain the movement within -100 to 100 units in both x and y axes
            if newX < -100 then newX = -100 end
            if newY < -100 then newY = -100 end
            if newX > 100 then newX = 100 end
            if newY > 100 then newY = 100 end
    
            self:ClearAllPoints()
            self:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -newX, -newY)
        end)
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)

        -- Save the new position
        local right, top = self:GetRight(), self:GetTop()
        local parentRight, parentTop = parentFrame:GetRight(), parentFrame:GetTop()
        local newX = parentRight - right
        local newY = parentTop - top

        -- Constrain the movement within -100 to 100 units in both x and y axes
        if newX < -100 then newX = -100 end
        if newY < -100 then newY = -100 end
        if newX > 100 then newX = 100 end
        if newY > 100 then newY = 100 end

        ChattyLittleNpc.db.profile.buttonPosX = -newX
        ChattyLittleNpc.db.profile.buttonPosY = -newY
    end)

    return button
end