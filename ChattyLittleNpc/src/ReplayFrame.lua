---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = {}
CLN.ReplayFrame = ReplayFrame

function ReplayFrame:SaveFramePosition()
    local point, relativeTo, relativePoint, xOfs, yOfs = self.DisplayFrame:GetPoint()
    CLN.db.profile.framePos = {
        point = point,
        relativeTo = relativeTo and relativeTo:GetName() or nil,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs
    }
end

function ReplayFrame:LoadFramePosition()
    local pos = CLN.db.profile.framePos
    if (pos) then
        self.DisplayFrame:ClearAllPoints()
        self.DisplayFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        self.DisplayFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -500, -200)
    end
end

function ReplayFrame:ResetFramePosition()
    CLN.db.profile.framePos = {
        point = "CENTER",
        relativeTo = nil,
        relativePoint = "CENTER",
        xOfs = 500,
        yOfs = 0
    }
    if (ReplayFrame.DisplayFrame) then
        ReplayFrame:LoadFramePosition()
    end
end

function ReplayFrame:GetDisplayFrame()
    if (ReplayFrame.DisplayFrame) then
        ReplayFrame:LoadFramePosition()
        return
    end

    ReplayFrame.normalWidth = 310
    ReplayFrame.npcModelFrameWidth = 140
    ReplayFrame.gap = 10
    ReplayFrame.expandedWidth = ReplayFrame.normalWidth + ReplayFrame.npcModelFrameWidth + self.gap

    -- Check if DialogueUI addon is loaded
    local parentFrame = UIParent

    if (ReplayFrame:IsDialogueUIFrameShow()) then
        parentFrame = _G["DUIQuestFrame"]
    end

    -- Parent frame
    ReplayFrame.DisplayFrame = CreateFrame("Frame", "ChattyLittleNpcDisplayFrame", parentFrame, "BackdropTemplate")
    -- Initial parent frame size: width = head + text, height = default
    local initialHeight = 165
    local initialWidth = initialHeight + ReplayFrame.normalWidth
    ReplayFrame.DisplayFrame:SetSize(initialWidth, initialHeight)
    ReplayFrame:LoadFramePosition()
    ReplayFrame.DisplayFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    ReplayFrame.DisplayFrame:SetBackdropColor(0, 0, 0, 0.2)
    ReplayFrame.DisplayFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
    ReplayFrame.DisplayFrame:SetMovable(true)
    ReplayFrame.DisplayFrame:EnableMouse(true)
    ReplayFrame.DisplayFrame:SetResizable(true)
    ReplayFrame.DisplayFrame:RegisterForDrag("LeftButton")
    ReplayFrame.DisplayFrame:SetScript("OnDragStart", ReplayFrame.DisplayFrame.StartMoving)
    ReplayFrame.DisplayFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        ReplayFrame:SaveFramePosition()
    end)

    -- Child frame: NPC model (talking head)
    local modelFrame = CreateFrame("PlayerModel", "ChattyLittleNpcModelFrame", ReplayFrame.DisplayFrame)
    modelFrame:SetSize(initialHeight - 10, initialHeight - 10)
    modelFrame:SetPoint("TOPLEFT", ReplayFrame.DisplayFrame, "TOPLEFT", 5, -5)
    modelFrame:Hide()
    ReplayFrame.NpcModelFrame = modelFrame

    -- Child frame: Content (quest queue and voiceover text)
    local contentFrame = CreateFrame("Frame", "ChattyLittleNpcContentFrame", ReplayFrame.DisplayFrame)
    contentFrame:SetSize(initialWidth - initialHeight - 5, initialHeight - 5)
    contentFrame:SetPoint("TOPLEFT", modelFrame, "TOPRIGHT", 2.5, 0)
    ReplayFrame.ContentFrame = contentFrame

    -- Resize Grip
    local resizeGrip = CreateFrame("Frame", nil, ReplayFrame.DisplayFrame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", ReplayFrame.DisplayFrame, "BOTTOMRIGHT", -2, 2)
    resizeGrip:EnableMouse(true)
    resizeGrip:SetScript("OnMouseDown", function()
        ReplayFrame.DisplayFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        ReplayFrame.DisplayFrame:StopMovingOrSizing()
        ReplayFrame:SaveFramePosition()
    end)
    local gripTex = resizeGrip:CreateTexture(nil, "ARTWORK")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip.texture = gripTex

    -- Dynamic scaling on resize
    ReplayFrame.DisplayFrame:SetScript("OnSizeChanged", function(frame, newWidth, newHeight)
        -- Enforce min/max size
        local minHeight, maxHeight = 100, 200
        local minWidth, maxWidth = minHeight + 200, maxHeight + 400
        local width, height = newWidth, newHeight
        if height < minHeight then height = minHeight end
        if height > maxHeight then height = maxHeight end
        if width < minWidth then width = minWidth end
        if width > maxWidth then width = maxWidth end
        if width ~= newWidth or height ~= newHeight then
            frame:SetSize(width, height)
        end
        -- Make model frame square and slightly smaller than parent
        if ReplayFrame.NpcModelFrame then
            ReplayFrame.NpcModelFrame:SetSize(height - 10, height - 10)
            ReplayFrame.NpcModelFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
        end
        -- Content frame takes the rest of the horizontal space, slightly smaller
        if ReplayFrame.ContentFrame then
            ReplayFrame.ContentFrame:SetSize(width - height - 5, height - 5)
            ReplayFrame.ContentFrame:SetPoint("TOPLEFT", ReplayFrame.NpcModelFrame, "TOPRIGHT", 2.5, 0)
        end
        -- Scale text size based on height (minimum 8, max 18)
        local fontSize = math.max(8, math.min(18, math.floor((height - 5) / 7)))
        for i, btn in ipairs(frame.buttons or {}) do
            if btn.text and btn.text.SetFont then
                btn.text:SetFont("Fonts\\FRIZQT__.TTF", fontSize)
            end
            btn.frame:SetWidth((width - height - 5) - 20)
        end
    end)
    ReplayFrame.DisplayFrame:SetScript("OnMouseUp", function(frame, button)
        if (button == "RightButton") then
            CLN.questsQueue = {}
            ReplayFrame.DisplayFrame:Hide()
            CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
        end
    end)
    ReplayFrame.DisplayFrame:SetScript("OnHide", function()
        if (ReplayFrame:IsVoiceoverCurrenltyPlaying()) then
            ReplayFrame:UpdateDisplayFrameState()
            return
        end
    end)


    ReplayFrame.DisplayFrame.buttons = {}
    for i = 1, 3 do
        -- BUTTON FRAME
        local buttonFrame = CreateFrame("Frame", "ButtonFrame"..i, contentFrame, "BackdropTemplate")
        buttonFrame:SetSize(contentFrame:GetWidth() - 20, math.floor(contentFrame:GetHeight() / 4))
        local spacing = math.floor(contentFrame:GetHeight() / 4)
        buttonFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -((i - 1) * spacing) - 7)
        buttonFrame:EnableMouse(true)

        -- STOP BUTTON
        local stopButton = CreateFrame("Button", "StopButton"..i, buttonFrame)
            stopButton:SetSize(16, 16)
            stopButton:SetPoint("RIGHT", buttonFrame, "RIGHT", 0, 0)
            stopButton.texture = stopButton:CreateTexture(nil, "ARTWORK")
            stopButton.texture:SetAllPoints()
            stopButton.texture:SetTexture("Interface\\Buttons\\UI-StopButton")
            stopButton:EnableMouse(true)
            stopButton:SetScript("OnEnter", function()
                GameTooltip:SetOwner(stopButton, "ANCHOR_LEFT")
                GameTooltip:SetText("Stop and remove quest voiceover from list.")
                GameTooltip:Show()
            end)
            stopButton:SetScript("OnLeave", function() GameTooltip_Hide() end)
            stopButton:SetScript("OnMouseDown", function()
                local questIndex = i

                if (questIndex == 1 and CLN.VoiceoverPlayer.currentlyPlaying) then
                    CLN.VoiceoverPlayer:ForceStopCurrentSound(false)
                else
                    table.remove(CLN.questsQueue, questIndex - 1)
                end

                ReplayFrame:UpdateDisplayFrame()
            end)

        -- DISPLAY TEXT
        local displayText = buttonFrame:CreateFontString("VoiceoverText"..i, "OVERLAY", "GameFontNormal")
            displayText:SetPoint("RIGHT", stopButton, "LEFT", -5, 0)
            displayText:SetPoint("TOPLEFT", buttonFrame, "TOPLEFT", 5, -5)
            displayText:SetJustifyH("LEFT")
            displayText:SetFont("Fonts\\FRIZQT__.TTF", 10)
            displayText:SetWordWrap(false)
            displayText:EnableMouse(true)

        ReplayFrame.DisplayFrame.buttons[i] = {frame = buttonFrame, text = displayText}
    end

    local npcModelFrame = CreateFrame("PlayerModel", "NPCModelFrame", ReplayFrame.DisplayFrame)
        npcModelFrame:SetSize(ReplayFrame.npcModelFrameWidth - 10, ReplayFrame.DisplayFrame:GetHeight() - 15)
        npcModelFrame:SetPoint("LEFT", ReplayFrame.DisplayFrame, "LEFT", 5, 0)
        npcModelFrame:Hide()

    ReplayFrame.NpcModelFrame = npcModelFrame
    ReplayFrame:UpdateDisplayFrameState()
end

function ReplayFrame:UpdateDisplayFrame()
    if (not ReplayFrame:IsShowReplayFrameToggleIsEnabled() or not CLN.VoiceoverPlayer.currentlyPlaying) then
        if (ReplayFrame.DisplayFrame) then
            ReplayFrame.DisplayFrame:Hide()
        end
        return
    end

    -- Hide Frame if there are no actively playing voiceover and no quests in queue
    if (not ReplayFrame:IsVoiceoverCurrenltyPlaying() and ReplayFrame:IsQuestQueueEmpty()) then
        if (ReplayFrame.DisplayFrame) then
            ReplayFrame.DisplayFrame:Hide()
        end
        return
    end

    if (ReplayFrame:IsDisplayFrameHideNeeded()) then
        ReplayFrame.DisplayFrame:Hide()
        return
    end

    local firstButton = ReplayFrame.DisplayFrame.buttons[1]
    if (not CLN.VoiceoverPlayer.currentlyPlaying.title) then
        CLN.VoiceoverPlayer.currentlyPlaying.title = CLN:GetTitleForQuestID(CLN.VoiceoverPlayer.currentlyPlaying.questId)

        if (CLN.db.profile.debugMode) then
            CLN:Print(
            "Getting missing title for quest id:",
            CLN.VoiceoverPlayer.currentlyPlaying.questId,
            ", title found is:",
            CLN.VoiceoverPlayer.currentlyPlaying.title)
        end
    end

    if (CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying.title) then
        local truncatedTitle = CLN.VoiceoverPlayer.currentlyPlaying.title

        if (string.len(CLN.VoiceoverPlayer.currentlyPlaying.title) > 30) then
            truncatedTitle = string.sub(CLN.VoiceoverPlayer.currentlyPlaying.title, 1, 25) .. "..."
        end

        firstButton.text:SetText("-> " .. truncatedTitle)
        firstButton.frame:Show()
        firstButton.text:SetScript("OnEnter", function()
            GameTooltip:SetOwner(firstButton.frame, "ANCHOR_RIGHT")
            GameTooltip:SetText(CLN.VoiceoverPlayer.currentlyPlaying.title)
            GameTooltip:Show()
        end)
        firstButton.text:SetScript("OnLeave", function()
            GameTooltip_Hide()
        end)
    else
        firstButton.frame:Hide()
    end

    for i = 1, 2 do
        local button = ReplayFrame.DisplayFrame.buttons[i + 1]
        local quest = CLN.questsQueue[i]
        if (button and quest and quest.title) then
            local truncatedTitle = quest.title

            if (string.len(quest.title) > 30) then
                truncatedTitle = string.sub(quest.title, 1, 25) .. "..."
            end

            button.text:SetText(truncatedTitle)
            button.frame:Show()
            button.text:SetScript("OnEnter", function()
                GameTooltip:SetOwner(button.frame, "ANCHOR_RIGHT")
                GameTooltip:SetText(quest.title)
                GameTooltip:Show()
            end)
            button.text:SetScript("OnLeave", function()
                GameTooltip_Hide()
            end)
        else
            if (button) then
                button.frame:Hide()
            end
        end
    end

    ReplayFrame:UpdateParent()
    ReplayFrame.DisplayFrame:Show()
    ReplayFrame:CheckAndShowModel()
end

function ReplayFrame:UpdateParent()
    if (ReplayFrame:IsDialogueUIFrameShow()) then
        ReplayFrame.DisplayFrame:SetParent(_G["DUIQuestFrame"])
    else
        ReplayFrame.DisplayFrame:SetParent(UIParent)
    end
end

function ReplayFrame:UpdateDisplayFrameState()
    ReplayFrame:GetDisplayFrame()
    ReplayFrame:UpdateDisplayFrame()
end

function ReplayFrame:UpdateNpcModelDisplay(npcId)
    if (not ReplayFrame.NpcModelFrame) then return end

    local currentlyPlaying = CLN.VoiceoverPlayer.currentlyPlaying
    if (not (ReplayFrame:IsVoiceoverCurrenltyPlaying() and currentlyPlaying.npcId == npcId)) then
        ReplayFrame.NpcModelFrame:Hide()
        ReplayFrame:ContractForNpcModel()
        return
    end

    local displayID = NpcDisplayIdDB[npcId]
    if (displayID) then
        ReplayFrame.NpcModelFrame:ClearModel()
        ReplayFrame.NpcModelFrame:SetDisplayInfo(displayID)
        ReplayFrame.NpcModelFrame:SetPortraitZoom(0.75)
        ReplayFrame.NpcModelFrame:SetRotation(0.3)
        ReplayFrame.NpcModelFrame:Show()
        ReplayFrame:ExpandForNpcModel()
    else
        ReplayFrame.NpcModelFrame:ClearModel()
        ReplayFrame.NpcModelFrame:Hide()
        ReplayFrame:ContractForNpcModel()
    end
end

function ReplayFrame:CheckAndShowModel()
    local currentlyPlaying = CLN.VoiceoverPlayer.currentlyPlaying
    if (ReplayFrame:IsVoiceoverCurrenltyPlaying() and currentlyPlaying.npcId) then
        ReplayFrame:UpdateNpcModelDisplay(currentlyPlaying.npcId)
    else
        if (ReplayFrame.NpcModelFrame) then
            ReplayFrame.NpcModelFrame:Hide()
        end
    end
end

function ReplayFrame:ExpandForNpcModel()
    local frame = self.DisplayFrame
    local newWidth = self.expandedWidth
    frame:SetWidth(newWidth)
end

function ReplayFrame:ContractForNpcModel()
    local frame = self.DisplayFrame
    local newWidth = self.normalWidth
    frame:SetWidth(newWidth)
end

function ReplayFrame:IsVoiceoverCurrenltyPlaying()
    return CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying:isPlaying()
end

function ReplayFrame:IsShowReplayFrameToggleIsEnabled()
    return CLN.db.profile.showReplayFrame
end

function ReplayFrame:IsDisplayFrameCurrentlyShown()
    return ReplayFrame.DisplayFrame and ReplayFrame.DisplayFrame:IsShown()
end

function ReplayFrame:IsQuestQueueEmpty()
    return CLN.questsQueue and #CLN.questsQueue == 0
end

function ReplayFrame:IsDisplayFrameHideNeeded()
    return ((not ReplayFrame:IsShowReplayFrameToggleIsEnabled())
        or (not CLN.VoiceoverPlayer.currentlyPlaying)
        or ((not ReplayFrame:IsVoiceoverCurrenltyPlaying()) and ReplayFrame:IsQuestQueueEmpty() and ReplayFrame:IsDisplayFrameCurrentlyShown()))
end

function ReplayFrame:IsDialogueUIFrameShow()
    return CLN.isDUIAddonLoaded and _G["DUIQuestFrame"] and _G["DUIQuestFrame"]:IsShown()
end