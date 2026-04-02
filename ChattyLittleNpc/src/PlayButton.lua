---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local IconAtlas = CLN.IconAtlas

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
        local questFileName = questID .. "_Desc.ogg"
        local fileNameFound = false
        for packName, packData in pairs(CLN.VoiceoverPacks) do
            if packData._voiceoverIndex and packData._voiceoverIndex[questFileName] then
                fileNameFound = true
                break
            end
        end

        if (CLN.isElvuiAddonLoaded) then
            PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, function()
                CLN.VoiceoverPlayer:PlayQuestSound(questID, CLN.Utils.QuestPhases.DESC)
            end)
        else
            PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, function()
                CLN.VoiceoverPlayer:PlayQuestSound(questID, CLN.Utils.QuestPhases.DESC)
            end)
        end
        if not fileNameFound then
            _G[buttonName]:Hide()
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
                    CLN.VoiceoverPlayer:PlayQuestSound(questID, CLN.Utils.QuestPhases.DESC)
            end
        end)
    else
        PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, function()
            local questID = PlayButton:GetSelectedQuest()
            if (questID) then
                    CLN.VoiceoverPlayer:PlayQuestSound(questID, CLN.Utils.QuestPhases.DESC)
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
        PlayButton:CreateQuestDetailPlayStopButton()
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
    local allButtons = {}
    for _, name in ipairs(PlayButton.DialogWindowButtons) do allButtons[#allButtons + 1] = name end
    for _, name in ipairs(PlayButton.QuestLogButtons) do allButtons[#allButtons + 1] = name end
    for _, name in ipairs(allButtons) do
        local btn = _G[name]
        if btn then
            if (questID) then btn:Show() else btn:Hide() end
        end
    end
    PlayButton:UpdateQuestDetailPlayStopState()
end

function PlayButton:HidePlayButton()
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end
    for _, name in ipairs(PlayButton.DialogWindowButtons) do
        if _G[name] then _G[name]:Hide() end
    end
    for _, name in ipairs(PlayButton.QuestLogButtons) do
        if _G[name] then _G[name]:Hide() end
    end
    PlayButton:HideQuestDetailPlayStopButton()
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

    local buttonsToUpdate = {
        {name = PlayButton.GossipButton, parent = GossipFrame},
        {name = PlayButton.QuestButton, parent = QuestFrame},
    }
    for _, entry in pairs(buttonsToUpdate) do
        local button = _G[entry.name]
        if (button and entry.parent) then
            button:ClearAllPoints()
            button:SetPoint("TOPRIGHT", entry.parent, "TOPRIGHT", x, y)
        end
    end
end

function PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction)
    local button = CreateFrame("Frame", buttonName, parentFrame)
    button:SetSize(64, 64)
    button:SetFrameStrata("TOOLTIP")

    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    -- Use central atlas (fallback to existing speech bubble if placeholder missing)
    local playTex = (IconAtlas and IconAtlas:Get(IconAtlas.keys.play)) or "Interface\\AddOns\\ChattyLittleNpc\\Icons\\speech-bubble-border.png"
    texture:SetTexture(playTex)

    -- Create a glow texture
    local glowTexture = button:CreateTexture(nil, "OVERLAY")
    glowTexture:SetAllPoints()
    local glowTex = (IconAtlas and IconAtlas:Get(IconAtlas.keys.glow)) or "Interface\\AddOns\\ChattyLittleNpc\\Icons\\speech-bubble-border-glow.png"
    glowTexture:SetTexture(glowTex)
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

-- ============================================================================
-- Quest Detail Back-Button Play/Stop Toggle
-- ============================================================================

function PlayButton:CreateQuestDetailPlayStopButton()
    if self._questDetailPlayStopBtn then
        self:UpdateQuestDetailPlayStopState()
        return self._questDetailPlayStopBtn
    end

    local DetailsFrame = QuestMapFrame and QuestMapFrame.DetailsFrame
    if not DetailsFrame then return end

    local backButton = DetailsFrame.BackButton
        or (DetailsFrame.BackFrame and DetailsFrame.BackFrame.BackButton)
    if not backButton then return end

    if CLN.db.profile.showSpeakButton == false then return end

    local size = 24
    local btn = CreateFrame("Button", nil, DetailsFrame)
    btn:SetSize(size, size)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("CENTER")
    bg:SetSize(size + 4, size + 4)
    bg:SetTexture("Interface/Tooltips/UI-Tooltip-Background")
    bg:SetVertexColor(1, 1, 1, 0.12)
    btn.bg = bg

    -- Play icon (speaker — matches addon voiceover branding)
    local playIcon = btn:CreateTexture(nil, "ARTWORK")
    playIcon:SetPoint("CENTER")
    playIcon:SetSize(size - 4, size - 4)
    playIcon:SetTexture("Interface/COMMON/VOICECHAT-SPEAKER")
    btn.playIcon = playIcon

    -- Stop icon (clean X mark — matches unified toolbar style)
    local stopIcon = btn:CreateTexture(nil, "ARTWORK")
    stopIcon:SetPoint("CENTER")
    stopIcon:SetSize(size - 4, size - 4)
    stopIcon:SetTexture("Interface/RAIDFRAME/ReadyCheck-NotReady")
    stopIcon:Hide()
    btn.stopIcon = stopIcon

    btn:SetPoint("LEFT", backButton, "RIGHT", 4, 0)

    btn:SetScript("OnClick", function()
        PlayButton:OnQuestDetailPlayStopClick()
    end)

    btn:SetScript("OnEnter", function(f)
        f.bg:SetVertexColor(1, 1, 1, 0.25)
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(f, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            if btn._isPlaying then
                GameTooltip:AddLine("Stop Voiceover", 1, 1, 1)
            else
                GameTooltip:AddLine("Play Voiceover", 1, 1, 1)
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(f)
        f.bg:SetVertexColor(1, 1, 1, 0.12)
        if GameTooltip_Hide then GameTooltip_Hide() end
    end)

    -- Periodic state refresh while visible
    local refreshElapsed = 0
    btn:SetScript("OnUpdate", function(_, dt)
        refreshElapsed = refreshElapsed + dt
        if refreshElapsed < 0.5 then return end
        refreshElapsed = 0
        PlayButton:UpdateQuestDetailPlayStopState()
    end)

    self._questDetailPlayStopBtn = btn
    self:UpdateQuestDetailPlayStopState()
    return btn
end

function PlayButton:OnQuestDetailPlayStopClick()
    local questID = self:GetSelectedQuest()
    if not questID then return end

    local cp = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    if cp and cp.questId == questID and CLN.VoiceoverPlayer:IsPlaybackActive(cp) then
        CLN.VoiceoverPlayer:ForceStopCurrentSound(false, true)
    else
        CLN.VoiceoverPlayer:PlayQuestSound(questID, CLN.Utils.QuestPhases.DESC)
    end

    C_Timer.After(0.1, function()
        PlayButton:UpdateQuestDetailPlayStopState()
    end)
end

function PlayButton:UpdateQuestDetailPlayStopState()
    local btn = self._questDetailPlayStopBtn
    if not btn then return end

    if CLN.db.profile.showSpeakButton == false then
        btn:Hide()
        return
    end

    local questID = self:GetSelectedQuest()
    if not questID then
        btn:Hide()
        return
    end

    local hasVoiceover = false
    if CLN.VoiceoverPacks then
        for _, packData in pairs(CLN.VoiceoverPacks) do
            local questFileName = questID .. "_Desc.ogg"
            if packData._voiceoverIndex and packData._voiceoverIndex[questFileName] then
                hasVoiceover = true
                break
            end
        end
    end

    if not hasVoiceover then
        btn:Hide()
        return
    end

    btn:Show()

    local cp = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local isPlaying = cp and cp.questId == questID and CLN.VoiceoverPlayer:IsPlaybackActive(cp)

    btn._isPlaying = isPlaying
    if isPlaying then
        btn.playIcon:Hide()
        btn.stopIcon:Show()
    else
        btn.playIcon:Show()
        btn.stopIcon:Hide()
    end
end

function PlayButton:HideQuestDetailPlayStopButton()
    if self._questDetailPlayStopBtn then
        self._questDetailPlayStopBtn:Hide()
    end
end