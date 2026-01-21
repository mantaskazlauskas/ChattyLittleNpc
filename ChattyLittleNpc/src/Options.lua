---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class Options
local Options = {}

-- Attach Options to CLN immediately
CLN.Options = Options

-- Helper function to create a checkbox
local function CreateCheckBox(parent, label, desc, getFunc, setFunc, disabledFunc)
    local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    check.Text:SetText(label)
    check.tooltipText = desc
    
    check:SetScript("OnClick", function(self)
        local value = self:GetChecked()
        setFunc(value)
    end)
    
    check:SetScript("OnShow", function(self)
        self:SetChecked(getFunc())
        if disabledFunc then
            if disabledFunc() then
                self:Disable()
                self.Text:SetTextColor(0.5, 0.5, 0.5)
            else
                self:Enable()
                self.Text:SetTextColor(1, 1, 1)
            end
        end
    end)
    
    if check.SetScript then
        check:SetScript("OnEnter", function(self)
            if self.tooltipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
                GameTooltip:Show()
            end
        end)
        check:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    
    return check
end

-- Helper function to create a dropdown
local function CreateDropDown(parent, label, desc, items, getFunc, setFunc, disabledFunc)
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    
    local labelText = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 16, 3)
    labelText:SetText(label)
    dropdown.label = labelText
    
    dropdown.tooltipText = desc
    
    UIDropDownMenu_SetWidth(dropdown, 200)
    
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for value, text in pairs(items) do
            info.text = text
            info.value = value
            info.func = function()
                setFunc(value)
                UIDropDownMenu_SetText(dropdown, text)
            end
            info.checked = (getFunc() == value)
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    dropdown:SetScript("OnShow", function(self)
        local currentValue = getFunc()
        UIDropDownMenu_SetText(self, items[currentValue] or "")
        if disabledFunc then
            if disabledFunc() then
                UIDropDownMenu_DisableDropDown(self)
                labelText:SetTextColor(0.5, 0.5, 0.5)
            else
                UIDropDownMenu_EnableDropDown(self)
                labelText:SetTextColor(1, 1, 1)
            end
        end
    end)
    
    if dropdown.SetScript then
        dropdown:SetScript("OnEnter", function(self)
            if self.tooltipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
                GameTooltip:Show()
            end
        end)
        dropdown:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    
    return dropdown
end

-- Helper function to create a slider
local function CreateSlider(parent, label, desc, min, max, step, getFunc, setFunc, disabledFunc)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    
    local labelText = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("BOTTOM", slider, "TOP", 0, 0)
    labelText:SetText(label)
    slider.label = labelText
    
    local valueText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)
    slider.valueText = valueText
    
    slider.tooltipText = desc
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        setFunc(value)
        valueText:SetText(string.format("%.2f", value))
    end)
    
    slider:SetScript("OnShow", function(self)
        local value = getFunc()
        self:SetValue(value)
        valueText:SetText(string.format("%.2f", value))
        if disabledFunc then
            if disabledFunc() then
                self:Disable()
                labelText:SetTextColor(0.5, 0.5, 0.5)
                valueText:SetTextColor(0.5, 0.5, 0.5)
            else
                self:Enable()
                labelText:SetTextColor(1, 1, 1)
                valueText:SetTextColor(1, 1, 1)
            end
        end
    end)
    
    if slider.SetScript then
        slider:SetScript("OnEnter", function(self)
            if self.tooltipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
                GameTooltip:Show()
            end
        end)
        slider:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    
    return slider
end

-- Helper function to create a button
local function CreateButton(parent, label, desc, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(label)
    button:SetWidth(200)
    button:SetHeight(22)
    button.tooltipText = desc
    
    button:SetScript("OnClick", onClick)
    
    if button.SetScript then
        button:SetScript("OnEnter", function(self)
            if self.tooltipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    
    return button
end

-- Helper function to create a section header
local function CreateHeader(parent, text)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetText(text)
    return header
end

local options = {}
local optionsFrame = nil

-- Build the native UI panel
function Options:BuildOptionsPanel()
    if optionsFrame then return optionsFrame end
    
    -- Create main frame
    local frame = CreateFrame("Frame", "ChattyLittleNpcOptions", UIParent)
    frame.name = "Chatty Little Npc"
    
    -- Create scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(580, 2000)
    scrollFrame:SetScrollChild(content)
    
    local yOffset = -10
    
    -- ===== REPLAY FRAME SECTION =====
    local replayHeader = CreateHeader(content, "Replay Frame")
    replayHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local showReplayFrame = CreateCheckBox(
        content,
        "Show Voice Queue Frame",
        "Display the voice queue with character portrait during quest dialogues.",
        function() return CLN.db.profile.showReplayFrame end,
        function(value)
            CLN.db.profile.showReplayFrame = value
            if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
                CLN.ReplayFrame:UpdateDisplayFrameState()
            end
        end
    )
    showReplayFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local autoFitPortraits = CreateCheckBox(
        content,
        "Auto-Fit Character Portraits",
        "Automatically frame character portraits optimally. Disable if portraits appear jittery.",
        function() return CLN.db.profile.advancedCameraFitting end,
        function(value)
            CLN.db.profile.advancedCameraFitting = value
            if CLN.ReplayFrame and CLN.ReplayFrame.RebuildModelHost then
                CLN.ReplayFrame:RebuildModelHost()
            end
            if CLN.ReplayFrame and CLN.ReplayFrame.ApplyDefaultFit then
                local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                if cur and (CLN.ReplayFrame.NpcModelFrame and CLN.ReplayFrame.NpcModelFrame.IsShown and CLN.ReplayFrame.NpcModelFrame:IsShown()) then
                    CLN.ReplayFrame:ApplyDefaultFit(cur.displayID)
                end
            end
        end
    )
    autoFitPortraits:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local instantCamera = CreateCheckBox(
        content,
        "Instant Camera Movement",
        "Skip smooth camera transitions for immediate positioning. Character animations continue normally.",
        function() return CLN.db.profile.disableCameraAnimations end,
        function(value)
            CLN.db.profile.disableCameraAnimations = value
            if CLN.ReplayFrame then
                if CLN.ReplayFrame.AnimStop then
                    CLN.ReplayFrame:AnimStop('zoom')
                    CLN.ReplayFrame:AnimStop('pan')
                end
                if CLN.ReplayFrame._UpdateModelOnUpdateHook then
                    CLN.ReplayFrame:_UpdateModelOnUpdateHook()
                end
            end
        end
    )
    instantCamera:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    -- Graphics Quality dropdown (only if ModelScene is available)
    if CLN and CLN.ReplayFrame and CLN.ReplayFrame.IsModelSceneAvailable and CLN.ReplayFrame:IsModelSceneAvailable() then
        local graphicsDropdown = CreateDropDown(
            content,
            "Portrait Graphics Quality",
            "Choose character portrait rendering quality. Auto selects the best available option for your game version.",
            {
                auto = 'Auto (Recommended)',
                scene = 'Modern (Best Quality)',
                player = 'Classic (Compatibility)'
            },
            function() return CLN.db.profile.renderBackend or 'auto' end,
            function(value)
                CLN.db.profile.renderBackend = value
                if CLN.ReplayFrame and CLN.ReplayFrame.RebuildModelHost then
                    CLN.ReplayFrame:RebuildModelHost()
                end
                if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
                    CLN.ReplayFrame:UpdateDisplayFrameState()
                end
            end
        )
        graphicsDropdown:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
        yOffset = yOffset - 70
    end
    
    local queueScale = CreateSlider(
        content,
        "Queue Text Size",
        "Adjust the text size for voice queue entries.",
        0.75, 1.5, 0.05,
        function() return CLN.db.profile.queueTextScale or 1.0 end,
        function(value)
            CLN.db.profile.queueTextScale = value
            if CLN.ReplayFrame and CLN.ReplayFrame.ApplyQueueTextScale then
                CLN.ReplayFrame:ApplyQueueTextScale()
            end
        end
    )
    queueScale:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    queueScale:SetWidth(200)
    yOffset = yOffset - 50
    
    local compactMode = CreateCheckBox(
        content,
        "Voice Queue Only",
        "Hide character portrait to show only the voice queue.",
        function() return CLN.db.profile.compactMode end,
        function(value)
            CLN.db.profile.compactMode = value
            if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
                CLN.ReplayFrame:UpdateDisplayFrameState()
            end
        end
    )
    compactMode:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local editMode = CreateCheckBox(
        content,
        "Edit Mode",
        "Toggle edit mode for the replay frame. When enabled, you can move and resize the frame.",
        function() return CLN.ReplayFrame and CLN.ReplayFrame._editMode or false end,
        function(value)
            if not CLN.ReplayFrame then return end
            if value then
                CLN.ReplayFrame:ShowForEdit()
            else
                CLN.ReplayFrame:SetEditMode(false)
                CLN.ReplayFrame._forceShow = false
                if CLN.ReplayFrame.UpdateDisplayFrameState then
                    CLN.ReplayFrame:UpdateDisplayFrameState()
                end
            end
        end
    )
    editMode:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local resetPosBtn = CreateButton(
        content,
        "Reset Replay Frame Position",
        "Reset the replay frame position to its default values.",
        function() CLN.ReplayFrame:ResetFramePosition() end
    )
    resetPosBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 40
    
    -- ===== PLAYBACK OPTIONS SECTION =====
    local playbackHeader = CreateHeader(content, "Playback Options")
    playbackHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local autoPlay = CreateCheckBox(
        content,
        "Play on dialog window open",
        "Toggle to play voiceovers when opening the gossip or quest window.",
        function() return CLN.db.profile.autoPlayVoiceovers end,
        function(value) CLN.db.profile.autoPlayVoiceovers = value end
    )
    autoPlay:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local questMode = CreateDropDown(
        content,
        "Quest Playback Mode",
        "How quest voiceovers behave: Queue (play sequentially), Stop On Close (interrupt when window closes), or Manual (only on button press).",
        {
            queue = 'Queue (sequential, uninterrupted)',
            stopOnClose = 'Stop On Close (interrupt when dialog closes)',
            manual = 'Manual (never auto queue, only play button)'
        },
        function() return CLN.db.profile.questPlaybackMode or 'queue' end,
        function(value)
            CLN.db.profile.questPlaybackMode = value
            if CLN._SyncLegacyQuestPlaybackFlags then CLN:_SyncLegacyQuestPlaybackFlags() end
        end
    )
    questMode:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 70
    
    local delaySlider = CreateSlider(
        content,
        "Play Voiceover After A Delay",
        "Set the delay (in seconds) before playing voiceovers after talking with questgiver.",
        0, 3, 0.1,
        function() return CLN.db.profile.playVoiceoverAfterDelay end,
        function(value) CLN.db.profile.playVoiceoverAfterDelay = value end
    )
    delaySlider:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    delaySlider:SetWidth(200)
    yOffset = yOffset - 50
    
    local audioChannel = CreateDropDown(
        content,
        "Audio Channels",
        "Select the audio channel for voiceover playback.",
        {
            MASTER = 'MASTER',
            DIALOG = 'DIALOG',
            AMBIENCE = 'AMBIENCE',
            MUSIC = 'MUSIC',
            SFX = 'SFX'
        },
        function() return CLN.db.profile.audioChannel end,
        function(value) CLN.db.profile.audioChannel = value end
    )
    audioChannel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 70
    
    local showSpeakBtn = CreateCheckBox(
        content,
        "Enable Speak/Play button for dialogs",
        "Toggle to enable or disable Speak/Play button on next to the dialog frame.",
        function() return CLN.db.profile.showSpeakButton end,
        function(value) CLN.db.profile.showSpeakButton = value end
    )
    showSpeakBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 40
    
    -- ===== QUEST AND GOSSIP FRAME BUTTON OPTIONS =====
    local buttonHeader = CreateHeader(content, "Quest And Gossip Frame Button Options")
    buttonHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local buttonX = CreateSlider(
        content,
        "Button X Position",
        "Set the X coordinate for the button position relative to the frame.",
        -200, 200, 1,
        function() return CLN.db.profile.buttonPosX or 0 end,
        function(value)
            CLN.db.profile.buttonPosX = value
            CLN.PlayButton:UpdateButtonPositions()
        end
    )
    buttonX:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    buttonX:SetWidth(200)
    yOffset = yOffset - 50
    
    local buttonY = CreateSlider(
        content,
        "Button Y Position",
        "Set the Y coordinate for the button position relative to the frame.",
        -200, 200, 1,
        function() return CLN.db.profile.buttonPosY or 0 end,
        function(value)
            CLN.db.profile.buttonPosY = value
            CLN.PlayButton:UpdateButtonPositions()
        end
    )
    buttonY:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    buttonY:SetWidth(200)
    yOffset = yOffset - 50
    
    local resetBtnPos = CreateButton(
        content,
        "Reset Button Positions",
        "Reset the X and Y positions to their default values.",
        function()
            CLN.db.profile.buttonPosX = -15
            CLN.db.profile.buttonPosY = -30
            CLN.PlayButton:UpdateButtonPositions()
            -- Refresh panel to show new values
            buttonX:SetValue(CLN.db.profile.buttonPosX)
            buttonY:SetValue(CLN.db.profile.buttonPosY)
        end
    )
    resetBtnPos:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 40
    
    -- ===== DEBUGGING SECTION =====
    local debugHeader = CreateHeader(content, "Debugging")
    debugHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local debugMode = CreateCheckBox(
        content,
        "Detailed Logging",
        "Enable detailed diagnostic messages for troubleshooting. View all messages in the Logs window (/clnlogs).",
        function() return CLN.db.profile.debugMode end,
        function(value) CLN.db.profile.debugMode = value end
    )
    debugMode:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local logToChat = CreateCheckBox(
        content,
        "Show Messages in Chat",
        "Display addon messages in your chat window. Disable to keep chat clean; all messages are always available in the Logs window (/clnlogs).",
        function() return CLN.db.profile.logToChat end,
        function(value) CLN.db.profile.logToChat = value end,
        function() return not CLN.db.profile.debugMode end
    )
    logToChat:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local printMissing = CreateCheckBox(
        content,
        "Report Missing Voice Files",
        "Show warnings when voiceover files are not found for quests. Useful for identifying incomplete voice packs.",
        function() return CLN.db.profile.printMissingFiles end,
        function(value) CLN.db.profile.printMissingFiles = value end,
        function() return not CLN.db.profile.debugMode end
    )
    printMissing:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local debugNoAnim = CreateCheckBox(
        content,
        "Pause Character Animations",
        "Freeze character and emote animations for camera testing. Camera logging continues.",
        function() return CLN.db.profile.debugNoAnim end,
        function(value)
            CLN.db.profile.debugNoAnim = value
            if CLN.ReplayFrame and CLN.ReplayFrame.SetNoAnimDebug then
                CLN.ReplayFrame:SetNoAnimDebug(value)
                if CLN.ReplayFrame._UpdateModelOnUpdateHook then
                    CLN.ReplayFrame:_UpdateModelOnUpdateHook()
                end
            end
        end,
        function() return not CLN.db.profile.debugMode end
    )
    debugNoAnim:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local debugAnims = CreateCheckBox(
        content,
        "Animation System Logs",
        "Enable detailed logging for camera and animation systems. Use the category filter below to focus on specific areas.",
        function() return CLN.db.profile.debugAnimations end,
        function(value) CLN.db.profile.debugAnimations = value end,
        function() return not CLN.db.profile.debugMode end
    )
    debugAnims:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local function getCategoryItems()
        local C = CLN and CLN.Utils and CLN.Utils.LogCategories
        local values = {
            all = 'All Systems',
            none = 'None (Disable)'
        }
        if C then
            values[C.camera] = 'Camera System'
            values[C.framing] = 'Portrait Framing'
            values[C.projection] = 'Projection Math'
            values[C.host] = 'Render Host'
            values[C.loader] = 'Model Loading'
            values[C.animation] = 'Animations'
            values[C.emotes] = 'Emotes'
        end
        return values
    end
    
    local categoryDropdown = CreateDropDown(
        content,
        "Log Category Filter",
        "Choose which system to log. \"All\" shows everything, \"None\" disables animation system logs.",
        getCategoryItems(),
        function()
            local cats = CLN.db.profile.debugAnimCategories
            if cats == 'all' or not cats then return 'all' end
            if type(cats) == 'table' then
                local count = 0
                local lastCat = nil
                for k, v in pairs(cats) do
                    if v then
                        count = count + 1
                        lastCat = k
                    end
                end
                if count == 0 then return 'none' end
                if count == 1 then return lastCat end
                return 'all'
            end
            return 'all'
        end,
        function(value)
            if value == 'all' then
                CLN.db.profile.debugAnimCategories = 'all'
            elseif value == 'none' then
                CLN.db.profile.debugAnimCategories = {}
            else
                local cats = {}
                cats[value] = true
                CLN.db.profile.debugAnimCategories = cats
            end
        end,
        function() return not (CLN.db.profile.debugMode and CLN.db.profile.debugAnimations) end
    )
    categoryDropdown:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 70
    
    local allowKeyProp = CreateCheckBox(
        content,
        "Allow Key Propagation (Advanced)",
        "Enable usage of SetPropagateKeyboardInput on internal debug/overlay frames. This can reduce stuck-focus issues but may trigger Blizzard taint errors. Leave OFF unless you understand the risk.",
        function() return CLN.db.profile.allowKeyPropagation end,
        function(value) CLN.db.profile.allowKeyPropagation = value and true or false end,
        function() return not CLN.db.profile.debugMode end
    )
    allowKeyProp:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 40
    
    -- ===== DATA COLLECTION SECTION =====
    local dataHeader = CreateHeader(content, "Data Collection")
    dataHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local logNpcTexts = CreateCheckBox(
        content,
        "Track NPC Data",
        "Save all NPC texts to saved variables for voiceover generation. Contact us on Discord if you want to help contribute data.",
        function() return CLN.db.profile.logNpcTexts end,
        function(value)
            CLN.db.profile.logNpcTexts = value
            if not value then
                CLN.db.profile.printNpcTexts = false
            end
        end
    )
    logNpcTexts:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local printNpcTexts = CreateCheckBox(
        content,
        "Log Collected Data",
        "Print the NPC data being collected (if tracking is enabled).",
        function() return CLN.db.profile.printNpcTexts end,
        function(value) CLN.db.profile.printNpcTexts = value end,
        function() return not CLN.db.profile.logNpcTexts end
    )
    printNpcTexts:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local overwriteGossip = CreateCheckBox(
        content,
        "Overwrite Existing Data",
        "Overwrite existing NPC text data when interacting again.",
        function() return CLN.db.profile.overwriteExistingGossipValues end,
        function(value) CLN.db.profile.overwriteExistingGossipValues = value end,
        function() return not CLN.db.profile.logNpcTexts end
    )
    overwriteGossip:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 40
    
    -- ===== DEVELOPER TOOLS SECTION =====
    local devHeader = CreateHeader(content, "Developer Tools")
    devHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local showEditor = CreateCheckBox(
        content,
        "Show Gossip Editor",
        "Toggle the Gossip Editor window for editing/fixing collected NPC gossip lines.",
        function() return CLN.Editor.Frame:IsShown() end,
        function(value)
            if value then
                CLN.Editor.Frame:Show()
            else
                CLN.Editor.Frame:Hide()
            end
        end
    )
    showEditor:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30
    
    local printVOPack = CreateButton(
        content,
        "Print VO Pack Info",
        "Print loaded voiceover pack metadata and statistics.",
        function() CLN:PrintLoadedVoiceoverPacks() end
    )
    printVOPack:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 40
    
    optionsFrame = frame
    return frame
end

function Options:SetupOptions()
    if not optionsFrame then
        local panel = self:BuildOptionsPanel()
        
        -- Register with Blizzard Interface Options
        if Settings and Settings.RegisterCanvasLayoutCategory then
            -- Retail API (10.0+)
            local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
            Settings.RegisterAddOnCategory(category)
            optionsFrame.category = category
        elseif InterfaceOptions_AddCategory then
            -- Classic/Legacy API
            InterfaceOptions_AddCategory(panel)
        end
    end
end

-- Helper for other modules to open the Settings category
function Options:OpenSettings()
    if Settings and Settings.OpenToCategory then
        -- Retail API (10.0+)
        if optionsFrame and optionsFrame.category then
            Settings.OpenToCategory(optionsFrame.category)
        end
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Classic/Legacy API
        if optionsFrame then
            InterfaceOptionsFrame_OpenToCategory(optionsFrame)
        end
    end
end

-- Note: SetupOptions is called from Main.lua CLN:OnEnable()
