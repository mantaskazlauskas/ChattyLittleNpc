---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

---@class PlayButton
local PlayButton = {}
CLN.PlayButton = PlayButton

PlayButton.GossipButton = "ChattyLittleGossipButton"
PlayButton.QuestButton = "ChattyLittleQuestButton"
PlayButton.ItemTextButton = "ChattyLittleItemTextButton"

PlayButton.DetailFrameButton = "ChattyLittleDetailFrameButton"
PlayButton.QuestLogFrameButton = "ChattyLittleQuestLogFrameButton"
PlayButton.QuestLogDetailFrameButton = "ChattyLittleQuestLogDetailFrameButton"

PlayButton.DialogWindowButtons = { PlayButton.GossipButton, PlayButton.QuestButton, PlayButton.ItemTextButton }
PlayButton.QuestLogButtons = { PlayButton.DetailFrameButton, PlayButton.QuestLogFrameButton, PlayButton.QuestLogDetailFrameButton }

PlayButton.buttons = {}

function PlayButton:ClearButtons()

    for buttonName, button in pairs(PlayButton.DialogWindowButtons) do
        if (_G[button]) then
            _G[button]:Hide()
            _G[button] = nil
        end
    end
end

function PlayButton:ClearQuestLogAndDetailButtons()
    for buttonName, button in pairs(PlayButton.QuestLogButtons) do
        if (_G[button]) then
            _G[button]:Hide()
            _G[button] = nil
        end
    end
end

function PlayButton:AttachPlayButton(parentFrame, offsetX, offsetY, buttonName)
    PlayButton:ClearButtons()
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end

    local questID = PlayButton:GetSelectedQuest()
    if (questID) then
        for packName, packData in pairs(CLN.VoiceoverPacks) do
            local questFileName =  questID .. "_Desc.ogg"
            local fileNameFound = CLN.Utils:ContainsString(packData.Voiceovers, questFileName)
            if (CLN.isElvuiAddonLoaded) then
                PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, function()
                    CLN.VoiceoverPlayer:PlayQuestSound(questID, "Desc")
                end)
                if not fileNameFound then
                    _G[buttonName]:Hide()
                end
                return
            else
                PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, function()
                    CLN.VoiceoverPlayer:PlayQuestSound(questID, "Desc")
                end)
                if not fileNameFound then
                    _G[buttonName]:Hide()
                end
                return
            end
        end
    end
end

function PlayButton:AttachPlayButtonForQuestLog(parentFrame, offsetX, offsetY, buttonName)
    PlayButton:ClearButtons()
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end

    if (CLN.isElvuiAddonLoaded) then
        PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, function()
            local questID = PlayButton:GetSelectedQuest()
            if (questID) then
                CLN.VoiceoverPlayer:PlayQuestSound(questID, "Desc")
            end
        end)
    else
        PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, function()
            local questID = PlayButton:GetSelectedQuest()
            if (questID) then
                CLN.VoiceoverPlayer:PlayQuestSound(questID, "Desc")
            end
        end)
    end
end

function PlayButton:CreatePlayVoiceoverButton(parentFrame, buttonName, onMouseUpFunction)
    PlayButton:ClearButtons()
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end

    local offsetX = CLN.db.profile.buttonPosX
    local offsetY = CLN.db.profile.buttonPosY

    if (CLN.isElvuiAddonLoaded) then
        return PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction)
    else
        return PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction)
    end
end

function PlayButton:AttachQuestLogAndDetailsButtons()
    PlayButton:ClearQuestLogAndDetailButtons()
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end

    local DetailsFrame = QuestMapFrame and QuestMapFrame.DetailsFrame
    if (DetailsFrame) then
        PlayButton:AttachPlayButtonForQuestLog(DetailsFrame, -10, -10, PlayButton.DetailFrameButton)
    end

    if (_G["QuestLogFrame"]) then
        PlayButton:AttachPlayButtonForQuestLog(_G["QuestLogFrame"], 40, 40, PlayButton.QuestLogFrameButton)
    end

    if (_G["QuestLogDetailFrame"]) then
        PlayButton:AttachPlayButtonForQuestLog(_G["QuestLogDetailFrame"], 40, 40, PlayButton.QuestLogDetailFrameButton)
    end
end

function PlayButton:UpdatePlayButton()
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end
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
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end
    for buttonName, button in pairs(PlayButton.buttons) do
        button:Hide()
    end
end

function PlayButton:GetSelectedQuest()
    if (CLN.useNamespaces and C_QuestLog and C_QuestLog.GetSelectedQuest) then
        return C_QuestLog.GetSelectedQuest()
    else
        ---@diagnostic disable-next-line: undefined-global
        local selectedIndex = GetQuestLogSelection()

        if (selectedIndex and selectedIndex > 0) then
            ---@diagnostic disable-next-line: undefined-global
            local _, _, _, _, _, _, _, questID = GetQuestLogTitle(selectedIndex)
            return questID
        end
    end
    return nil
end

function PlayButton:UpdateButtonPositions()
    local x = CLN.db.profile.buttonPosX or 0
    local y = CLN.db.profile.buttonPosY or 0

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

        CLN.db.profile.buttonPosX = -newX
        CLN.db.profile.buttonPosY = -newY
    end)

    return button
end

-- ElvUI Support
function PlayButton:GetElvUI()
    -- ElvUI is stored globally as an array, the addon object is at index 1
    ---@type table|nil
    ---@diagnostic disable-next-line: undefined-field
    local ElvUI = _G.ElvUI
    -- ElvUI stores the main addon object in the first index
    if ElvUI and type(ElvUI) == "table" and ElvUI[1] then
        return ElvUI[1]
    end
    return nil
end

function PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction)
    local button = CreateFrame("Button", buttonName, parentFrame, "UIPanelButtonTemplate")
    button:SetSize(90, 25) -- Adjusted to fit ElvUI's style better

    local ElvUI = PlayButton:GetElvUI()
    if ElvUI then
        local ElvUISkins = ElvUI:GetModule('Skins')
        if ElvUISkins and ElvUISkins.HandleButton then
            ---@diagnostic disable-next-line: undefined-field
            ElvUISkins:HandleButton(button)
        end
    end
    button:SetText("Play Voiceover")

    button:SetScript("OnEnter", function()
        button:SetBackdropBorderColor(1, 1, 0) -- Highlight border on hover
    end)

    button:SetScript("OnLeave", function()
        if ElvUI and ElvUI.media and ElvUI.media.bordercolor then
            ---@diagnostic disable-next-line: undefined-field
            button:SetBackdropBorderColor(unpack(ElvUI.media.bordercolor)) -- Reset border on leave
        end
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

        CLN.db.profile.buttonPosX = -newX
        CLN.db.profile.buttonPosY = -newY
    end)

    return button
end