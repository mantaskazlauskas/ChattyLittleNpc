---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = {}

ChattyLittleNpc.ReplayFrame = ReplayFrame

function ReplayFrame:SaveFramePosition()
    local point, relativeTo, relativePoint, xOfs, yOfs = self.DisplayFrame:GetPoint()
    ChattyLittleNpc.db.profile.framePos = {
        point = point,
        relativeTo = relativeTo and relativeTo:GetName() or nil,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs
    }
end

function ReplayFrame:LoadFramePosition()
    local pos = ChattyLittleNpc.db.profile.framePos
    if (pos) then
        self.DisplayFrame:ClearAllPoints()
        self.DisplayFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        self.DisplayFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -500, -200)
    end
end

function ReplayFrame:ResetFramePosition()
    ChattyLittleNpc.db.profile.framePos = {
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
        if (ChattyLittleNpc.db.profile.debugMode) then
            ChattyLittleNpc:Print("DisplayFrame already exists.. loading")
        end
        ReplayFrame:LoadFramePosition()
        return
    end

    ReplayFrame.normalWidth = 310
    ReplayFrame.npcModelFrameWidth = 140
    ReplayFrame.gap = 10
    ReplayFrame.expandedWidth = ReplayFrame.normalWidth + ReplayFrame.npcModelFrameWidth + self.gap

    -- Check if DialogueUI addon is loaded
    local parentFrame = UIParent

    if (ChattyLittleNpc.db.profile.ShowReplayFrameIfDialogueUIAddonIsLoaded) then
        if (ReplayFrame:IsDialogueUIFrameShow()) then
            parentFrame = _G["DUIQuestFrame"]
            if (ChattyLittleNpc.db.profile.debugMode) then
                ChattyLittleNpc:Print("DUIQuestFrame found")
            end
        end
    end

    ReplayFrame.DisplayFrame = CreateFrame("Frame", "ChattyLittleNpcDisplayFrame", parentFrame, "BackdropTemplate")
    ReplayFrame.DisplayFrame.buttons = {}
    ReplayFrame.DisplayFrame:SetSize(ReplayFrame.normalWidth, 165)
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
    ReplayFrame.DisplayFrame:RegisterForDrag("LeftButton")
    ReplayFrame.DisplayFrame:SetScript("OnDragStart", ReplayFrame.DisplayFrame.StartMoving)
    ReplayFrame.DisplayFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        ReplayFrame:SaveFramePosition()
    end)

    ReplayFrame.DisplayFrame:SetScript("OnMouseUp", function(frame, button)
        if (button == "RightButton") then
            ChattyLittleNpc.questsQueue = {}
            ReplayFrame.DisplayFrame:Hide()
            ChattyLittleNpc.Voiceovers:ForceStopCurrentSound(true)
            if (ChattyLittleNpc.db.profile.debugMode) then
                ChattyLittleNpc:Print("Hiding DisplayFrame using RMB click")
            end
        end
    end)

    ReplayFrame.DisplayFrame:SetScript("OnHide", function()
        if (ReplayFrame:IsVoiceoverCurrenltyPlaying()) then
            ReplayFrame:UpdateDisplayFrameState(true)
            if (ChattyLittleNpc.db.profile.debugMode) then
                ChattyLittleNpc:Print("Preventing hiding DisplayFrame while audio is still playing.")
            end

            return
        end

        if (ChattyLittleNpc.db.profile.debugMode) then
            ChattyLittleNpc:Print("DisplayFrame Hide event handler triggered.")
        end
    end)

    ReplayFrame.ContentFrame = CreateFrame("Frame", "ContentFrame", ReplayFrame.DisplayFrame)
    ReplayFrame.ContentFrame:SetSize(ReplayFrame.normalWidth, ReplayFrame.DisplayFrame:GetHeight())
    ReplayFrame.ContentFrame:SetPoint("TOPRIGHT", ReplayFrame.DisplayFrame, "TOPRIGHT", 0, 0)

    -- CLOSE BUTTON
    local closeButton = CreateFrame("Button", "CloseButton", ReplayFrame.ContentFrame, "UIPanelCloseButton")
        closeButton:SetSize(20, 20)
        closeButton:SetPoint("TOPRIGHT", ReplayFrame.ContentFrame, "TOPRIGHT", -5, -5)
        closeButton:SetScript("OnClick", function()
            ChattyLittleNpc.questsQueue = {}
            ReplayFrame.DisplayFrame:Hide()
            ChattyLittleNpc.Voiceovers:ForceStopCurrentSound(true)
            if (ChattyLittleNpc.db.profile.debugMode) then
                ChattyLittleNpc:Print("Hiding Display frame using close button.")
            end
        end)

    for i = 1, 3 do
        -- BUTTON FRAME
        local buttonFrame = CreateFrame("Frame", "ButtonFrame"..i, ReplayFrame.ContentFrame, "BackdropTemplate")
            buttonFrame:SetSize(ReplayFrame.normalWidth - 20, 35)
            buttonFrame:SetPoint("TOPLEFT", ReplayFrame.ContentFrame, "TOPLEFT", 10, -((i - 1) * 40) - 40)
            buttonFrame:EnableMouse(true)

        -- STOP BUTTON
        local stopButton = CreateFrame("Button", "StopButton"..i, buttonFrame)
            stopButton:SetSize(16, 16)
            stopButton:SetPoint("RIGHT", buttonFrame, "RIGHT", -5, 0)
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

                if (questIndex == 1 and ChattyLittleNpc.Voiceovers.currentlyPlaying) then
                    ChattyLittleNpc.Voiceovers:ForceStopCurrentSound(false)
                else
                    table.remove(ChattyLittleNpc.questsQueue, questIndex - 1)
                end

                ReplayFrame:UpdateDisplayFrame()
            end)

        -- DISPLAY TEXT
        local displayText = buttonFrame:CreateFontString("VoiceoverText"..i, "OVERLAY", "GameFontNormal")
            displayText:SetPoint("LEFT", buttonFrame, "LEFT", 5, 0)
            displayText:SetPoint("RIGHT", stopButton, "LEFT", -5, 0)
            displayText:SetJustifyH("LEFT")
            displayText:SetFont("Fonts\\FRIZQT__.TTF", 15)
            displayText:SetWordWrap(false)
            displayText:EnableMouse(true)

        ReplayFrame.DisplayFrame.buttons[i] = {frame = buttonFrame, text = displayText}
    end

    local npcModelFrame = CreateFrame("PlayerModel", "NPCModelFrame", ReplayFrame.DisplayFrame)
        npcModelFrame:SetSize(ReplayFrame.npcModelFrameWidth, ReplayFrame.DisplayFrame:GetHeight() - 15)
        npcModelFrame:SetPoint("LEFT", ReplayFrame.DisplayFrame, "LEFT", 5, 0)
        npcModelFrame:Hide()

    ReplayFrame.NpcModelFrame = npcModelFrame
    ReplayFrame:UpdateDisplayFrameState()
end

function ReplayFrame:UpdateDisplayFrame()
    if (not ReplayFrame:IsShowReplayFrameToggleIsEnabled() or not ChattyLittleNpc.Voiceovers.currentlyPlaying) then
        if (ReplayFrame.DisplayFrame) then
            if (ChattyLittleNpc.db.profile.debugMode) then
                ChattyLittleNpc:Print("Hiding DisplayFrame due to toggle or missing current voiceover")
            end
            ReplayFrame.DisplayFrame:Hide()
        end
        return
    end

    -- Hide Frame if there are no actively playing voiceover and no quests in queue
    if (not ReplayFrame:IsVoiceoverCurrenltyPlaying() and ReplayFrame:IsQuestQueueEmpty()) then
        if (ReplayFrame.DisplayFrame) then
            if (ChattyLittleNpc.db.profile.debugMode) then
                ChattyLittleNpc:Print("Disabling DisplayFrame due no active voiceovers")
            end
            ReplayFrame.DisplayFrame:Hide()
        end
        return
    end

    if (ReplayFrame:IsDisplayFrameHideNeeded()) then
        if (ChattyLittleNpc.db.profile.debugMode) then
            ChattyLittleNpc:Print("Hiding DisplayFrame because there is no more quests to play in queue")
        end
        ReplayFrame.DisplayFrame:Hide()
        return
    end

    local firstButton = ReplayFrame.DisplayFrame.buttons[1]
    if (not ChattyLittleNpc.Voiceovers.currentlyPlaying.title) then
        ChattyLittleNpc.Voiceovers.currentlyPlaying.title = ChattyLittleNpc:GetTitleForQuestID(ChattyLittleNpc.Voiceovers.currentlyPlaying.questId)

        if (ChattyLittleNpc.db.profile.debugMode) then
            ChattyLittleNpc:Print("Getting missing title for quest id:", ChattyLittleNpc.Voiceovers.currentlyPlaying.questId, ", title found is:", ChattyLittleNpc.Voiceovers.currentlyPlaying.title)
        end
    end

    if (ChattyLittleNpc.Voiceovers.currentlyPlaying and ChattyLittleNpc.Voiceovers.currentlyPlaying.title) then
        local truncatedTitle = ChattyLittleNpc.Voiceovers.currentlyPlaying.title

        if (string.len(ChattyLittleNpc.Voiceovers.currentlyPlaying.title) > 30) then
            truncatedTitle = string.sub(ChattyLittleNpc.Voiceovers.currentlyPlaying.title, 1, 25) .. "..."
        end

        firstButton.text:SetText("-> " .. truncatedTitle)
        firstButton.frame:Show()
        firstButton.text:SetScript("OnEnter", function()
            GameTooltip:SetOwner(firstButton.frame, "ANCHOR_RIGHT")
            GameTooltip:SetText(ChattyLittleNpc.Voiceovers.currentlyPlaying.title)
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
        local quest = ChattyLittleNpc.questsQueue[i]
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
    if (ChattyLittleNpc.db.profile.ShowReplayFrameIfDialogueUIAddonIsLoaded and ReplayFrame:IsDialogueUIFrameShow()) then
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

    local currentlyPlaying = ChattyLittleNpc.Voiceovers.currentlyPlaying
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
        ReplayFrame.NpcModelFrame:SetRotation(0)
        ReplayFrame.NpcModelFrame:Show()
        ReplayFrame:ExpandForNpcModel()
    else
        ReplayFrame.NpcModelFrame:ClearModel()
        ReplayFrame.NpcModelFrame:Hide()
        ReplayFrame:ContractForNpcModel()
    end
end

function ReplayFrame:CheckAndShowModel()
    local currentlyPlaying = ChattyLittleNpc.Voiceovers.currentlyPlaying
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
    return ChattyLittleNpc.Voiceovers.currentlyPlaying and ChattyLittleNpc.Voiceovers.currentlyPlaying.isPlaying
end

function ReplayFrame:IsShowReplayFrameToggleIsEnabled()
    return ChattyLittleNpc.db.profile.showReplayFrame
end

function ReplayFrame:IsDisplayFrameCurrentlyShown()
    return ReplayFrame.DisplayFrame and ReplayFrame.DisplayFrame:IsShown()
end

function ReplayFrame:IsQuestQueueEmpty()
    return ChattyLittleNpc.questsQueue and #ChattyLittleNpc.questsQueue == 0
end

function ReplayFrame:IsDisplayFrameHideNeeded()
    return ((not ReplayFrame:IsShowReplayFrameToggleIsEnabled())
        or (not ChattyLittleNpc.Voiceovers.currentlyPlaying)
        or ((not ReplayFrame:IsVoiceoverCurrenltyPlaying()) and ReplayFrame:IsQuestQueueEmpty() and ReplayFrame:IsDisplayFrameCurrentlyShown()))
end

function ReplayFrame:IsDialogueUIFrameShow()
    return ChattyLittleNpc.isDUIAddonLoaded and _G["DUIQuestFrame"] and _G["DUIQuestFrame"]:IsShown()
end