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
    PlayButton._currentPlayCallback = nil

    for _, button in pairs(PlayButton.DialogWindowButtons) do
        if (_G[button]) then
            PlayButton:ReleaseButton(_G[button])
            _G[button] = nil
        end
    end
end

function PlayButton:ClearQuestLogAndDetailButtons()
    for _, button in pairs(PlayButton.QuestLogButtons) do
        if (_G[button]) then
            PlayButton:ReleaseButton(_G[button])
            _G[button] = nil
        end
    end
    if PlayButton._questDetailPlayStopBtn then
        PlayButton:ReleaseButton(PlayButton._questDetailPlayStopBtn)
        PlayButton._questDetailPlayStopBtn = nil
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
            PlayButton:SetButtonShown(_G[buttonName], false)
        end
    end
end

function PlayButton:AttachPlayButtonForQuestLog(parentFrame, offsetX, offsetY, buttonName)
    -- Deliberately does not clear the dialog window buttons: the caller has
    -- already cleared the quest log ones, and an open gossip/quest window must
    -- keep its own button (and _currentPlayCallback for the keybind).
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end

    local function playSelectedQuest()
        local questID = PlayButton:GetSelectedQuest()
        if (questID) then
                CLN.VoiceoverPlayer:PlayQuestSound(questID, CLN.Utils.QuestPhases.DESC)
        end
    end

    local button
    if (CLN.isElvuiAddonLoaded) then
        button = PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, playSelectedQuest, UIParent)
    else
        button = PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, playSelectedQuest, UIParent)
    end
    PlayButton:FollowAnchor(button, parentFrame)
end

function PlayButton:CreatePlayVoiceoverButton(parentFrame, buttonName, onMouseUpFunction)
    PlayButton:ClearButtons()
    -- Store callback for keybind use regardless of whether the button is visible
    PlayButton._currentPlayCallback = onMouseUpFunction
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end

    local offsetX = CLN.db.profile.buttonPosX
    local offsetY = CLN.db.profile.buttonPosY

    local button
    if (CLN.isElvuiAddonLoaded) then
        button = PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction, UIParent)
    else
        button = PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction, UIParent)
    end
    PlayButton:FollowAnchor(button, parentFrame)
    return button
end

-- Our buttons are parented to UIParent and only anchored to Blizzard frames.
-- In gamepad mode SmartNavigation post-hooks CreateFrame and, when the new
-- frame's parent chain reaches an open panel (GossipFrame, QuestFrame,
-- WorldMapFrame, ...), rebuilds that panel's navigation state inside our call.
-- That state is then tainted, and the gamepad action bar's next
-- SetPreferredGamepadInteractTarget() gets ADDON_ACTION_BLOCKED. The walk stops
-- at UIParent, so UIParent-hosted frames never touch it.
local anchoredButtons = {} -- anchorFrame -> { [button] = true }

--- Match the scale and draw order of the anchor frame.
local function MatchAnchorLook(button, anchorFrame)
    local uiScale = UIParent:GetEffectiveScale()
    if uiScale and uiScale > 0 then
        button:SetScale(anchorFrame:GetEffectiveScale() / uiScale)
    end
    if button:GetFrameStrata() ~= "TOOLTIP" then
        button:SetFrameStrata(anchorFrame:GetFrameStrata())
        button:SetFrameLevel(anchorFrame:GetFrameLevel() + 20)
    end
end

-- Show/hide the anchor's buttons the way WoW would if they were its children:
-- hiding the anchor hides them, showing it brings back the ones that were
-- shown before (_clnWantShown), and a button hidden by our own code stays hidden.
local function SyncWithAnchor(anchorFrame, shown)
    local buttons = anchoredButtons[anchorFrame]
    if not buttons then return end
    for btn in pairs(buttons) do
        if btn._clnAnchor == anchorFrame then
            if not shown then
                btn:Hide()
            elseif btn._clnWantShown then
                MatchAnchorLook(btn, anchorFrame)
                btn:Show()
            end
        end
    end
end

--- Make a UIParent-hosted button look and behave like a child of anchorFrame:
--- same effective scale, drawn above it, and shown only while it is visible.
function PlayButton:FollowAnchor(button, anchorFrame)
    if not button or not anchorFrame then return end
    button._clnAnchor = anchorFrame
    -- Freshly created frames are shown, just like a child button would be
    button._clnWantShown = button:IsShown() and true or false

    MatchAnchorLook(button, anchorFrame)

    if not anchorFrame:IsVisible() then
        button:Hide()
    end

    if not anchoredButtons[anchorFrame] then
        anchoredButtons[anchorFrame] = setmetatable({}, { __mode = "k" })
        anchorFrame:HookScript("OnShow", function(self) SyncWithAnchor(self, true) end)
        anchorFrame:HookScript("OnHide", function(self) SyncWithAnchor(self, false) end)
    end
    anchoredButtons[anchorFrame][button] = true
end

--- Show or hide a button, remembering the intent while its anchor is hidden.
--- Use this instead of calling Show()/Hide() on an anchored button.
function PlayButton:SetButtonShown(button, shown)
    if not button then return end
    button._clnWantShown = shown and true or false
    local anchor = button._clnAnchor
    if shown and (not anchor or anchor:IsVisible()) then
        button:Show()
    else
        button:Hide()
    end
end

--- Detach a button from its anchor and hide it, so a replacement button can
--- take over without the old one reappearing when the anchor is shown again.
function PlayButton:ReleaseButton(button)
    if not button then return end
    local anchor = button._clnAnchor
    if anchor and anchoredButtons[anchor] then
        anchoredButtons[anchor][button] = nil
    end
    button._clnAnchor = nil
    button._clnWantShown = false
    button:Hide()
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

-- Only the quest log buttons follow the quest log selection. The dialog window
-- buttons (gossip, quest detail, item text) belong to frames that open and
-- close on their own events, so they must not be touched here: these two
-- functions are driven by quest log hooks (QuestMapFrame_UpdateAll fires on
-- every QUEST_LOG_UPDATE) and would otherwise hide a perfectly good gossip
-- button whenever no quest happens to be selected in the log.
function PlayButton:UpdatePlayButton()
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end
    local questID = PlayButton:GetSelectedQuest()
    for _, name in ipairs(PlayButton.QuestLogButtons) do
        local btn = _G[name]
        if btn then
            PlayButton:SetButtonShown(btn, questID ~= nil)
        end
    end
    PlayButton:UpdateQuestDetailPlayStopState()
end

function PlayButton:HidePlayButton()
    if (CLN.db.profile.showSpeakButton == false) then
        -- dont create button if the setting is disabled in options
        return
    end
    for _, name in ipairs(PlayButton.QuestLogButtons) do
        if _G[name] then PlayButton:SetButtonShown(_G[name], false) end
    end
    PlayButton:HideQuestDetailPlayStopButton()
end

function PlayButton:GetSelectedQuest()
    -- Feature detect rather than gate on the client version: some builds report
    -- a Classic interface number while shipping the modern quest log API and no
    -- legacy GetQuestLogSelection/GetQuestLogTitle globals.
    -- The legacy API comes first: where it exists it tracks the classic
    -- QuestLogFrame selection, which is the window our buttons sit on. Retail
    -- dropped these globals in 9.0, so it falls through to C_QuestLog.
    ---@diagnostic disable-next-line: undefined-global
    if (type(GetQuestLogSelection) == "function" and type(GetQuestLogTitle) == "function") then
        ---@diagnostic disable-next-line: undefined-global
        local selectedIndex = GetQuestLogSelection()

        if (selectedIndex and selectedIndex > 0) then
            ---@diagnostic disable-next-line: undefined-global
            local _, _, _, _, _, _, _, questID = GetQuestLogTitle(selectedIndex)
            return questID
        end
        return nil
    end

    if (C_QuestLog and C_QuestLog.GetSelectedQuest) then
        local questID = C_QuestLog.GetSelectedQuest()
        if (questID and questID ~= 0) then
            return questID
        end
    end

    -- Last resort: the modern quest map keeps the detail quest on the frame.
    ---@diagnostic disable-next-line: undefined-global
    if (type(QuestMapFrame_GetDetailQuestID) == "function") then
        ---@diagnostic disable-next-line: undefined-global
        return QuestMapFrame_GetDetailQuestID()
    end
    if (QuestMapFrame and QuestMapFrame.DetailsFrame) then
        return QuestMapFrame.DetailsFrame.questID
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

function PlayButton:GenerateSpeakChatBubbleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction, hostFrame)
    local button = CreateFrame("Frame", buttonName, hostFrame or parentFrame)
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

function PlayButton:GenerateElvUiStyleButton(parentFrame, buttonName, offsetX, offsetY, onMouseUpFunction, hostFrame)
    local button = CreateFrame("Button", buttonName, hostFrame or parentFrame, "UIPanelButtonTemplate")
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
    local btn = CreateFrame("Button", nil, UIParent)
    btn:SetSize(size, size)
    PlayButton:FollowAnchor(btn, DetailsFrame)

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
        self:SetButtonShown(btn, false)
        return
    end

    local questID = self:GetSelectedQuest()
    if not questID then
        self:SetButtonShown(btn, false)
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
        self:SetButtonShown(btn, false)
        return
    end

    self:SetButtonShown(btn, true)

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
        self:SetButtonShown(self._questDetailPlayStopBtn, false)
    end
end