---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local ReplayFrame = {}
ReplayFrame.buttons = {}

ChattyLittleNpc.ReplayFrame = ReplayFrame

function ReplayFrame:SaveFramePosition()
    local point, relativeTo, relativePoint, xOfs, yOfs = self.displayFrame:GetPoint()
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
    if pos then
        self.displayFrame:ClearAllPoints()
        self.displayFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        self.displayFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -500, -200)
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
    if ReplayFrame.displayFrame then
        ReplayFrame:LoadFramePosition()
    end
end

function ReplayFrame:CreateDisplayFrame()
    if not ReplayFrame.displayFrame then
        ReplayFrame.normalWidth = 310
        ReplayFrame.npcModelFrameWidth = 140
        ReplayFrame.gap = 10
        ReplayFrame.expandedWidth = ReplayFrame.normalWidth + ReplayFrame.npcModelFrameWidth + self.gap

        ReplayFrame.displayFrame = CreateFrame("Frame", "ChattyLittleNpcDisplayFrame", UIParent, "BackdropTemplate")
        ReplayFrame.displayFrame:SetSize(ReplayFrame.normalWidth, 165)
        ReplayFrame:LoadFramePosition()

        ReplayFrame.displayFrame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })

        -- Add right-click handler to close the frame
        ReplayFrame.displayFrame:SetScript("OnMouseUp", function(frame, button)
            if button == "RightButton" then
                ChattyLittleNpc.questsQueue = {}
                ChattyLittleNpc.Voiceovers:ForceStopCurrentSound(true)
                ReplayFrame.displayFrame:Hide()
            end
        end)

        ReplayFrame.displayFrame:SetBackdropColor(0, 0, 0, 0.2)
        ReplayFrame.displayFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
        ReplayFrame.displayFrame:SetMovable(true)
        ReplayFrame.displayFrame:EnableMouse(true)
        ReplayFrame.displayFrame:RegisterForDrag("LeftButton")
        ReplayFrame.displayFrame:SetScript("OnDragStart", ReplayFrame.displayFrame.StartMoving)
        ReplayFrame.displayFrame:SetScript("OnDragStop", function(frame)
            frame:StopMovingOrSizing()
            ReplayFrame:SaveFramePosition()
        end)

        ReplayFrame.contentFrame = CreateFrame("Frame", nil, ReplayFrame.displayFrame)
        ReplayFrame.contentFrame:SetSize(ReplayFrame.normalWidth, ReplayFrame.displayFrame:GetHeight())
        ReplayFrame.contentFrame:SetPoint("TOPRIGHT", ReplayFrame.displayFrame, "TOPRIGHT", 0, 0)

        -- CLOSE BUTTON (now parented to contentFrame)
        local closeButton = CreateFrame("Button", nil, ReplayFrame.contentFrame, "UIPanelCloseButton")
            closeButton:SetSize(20, 20)
            closeButton:SetPoint("TOPRIGHT", ReplayFrame.contentFrame, "TOPRIGHT", -5, -5)
            closeButton:SetScript("OnClick", function()
                ChattyLittleNpc.questsQueue = {}
                ChattyLittleNpc.Voiceovers:ForceStopCurrentSound(true)
                ReplayFrame.displayFrame:Hide()
            end)

        for i = 1, 3 do
            -- BUTTON FRAME
            local buttonFrame = CreateFrame("Frame", nil, ReplayFrame.contentFrame, "BackdropTemplate")
            buttonFrame:SetSize(ReplayFrame.normalWidth - 20, 35)
            buttonFrame:SetPoint("TOPLEFT", ReplayFrame.contentFrame, "TOPLEFT", 10, -((i - 1) * 40) - 40)
            buttonFrame:EnableMouse(true)

            -- STOP BUTTON
            local stopButton = CreateFrame("Button", nil, buttonFrame)
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

                    if questIndex == 1 and ChattyLittleNpc.Voiceovers.currentlyPlaying then
                        ChattyLittleNpc.Voiceovers:ForceStopCurrentSound(false)
                    else
                        table.remove(ChattyLittleNpc.questsQueue, questIndex - 1)
                    end

                    ReplayFrame:UpdateDisplayFrame()

                    if #ChattyLittleNpc.questsQueue == 0 and not ChattyLittleNpc.Voiceovers.currentlyPlaying then
                        ReplayFrame.displayFrame:Hide()
                    end
                end)

            -- DISPLAY TEXT
            local displayText = buttonFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                displayText:SetPoint("LEFT", buttonFrame, "LEFT", 5, 0)
                displayText:SetPoint("RIGHT", stopButton, "LEFT", -5, 0)
                displayText:SetJustifyH("LEFT")
                displayText:SetFont("Fonts\\FRIZQT__.TTF", 15)
                displayText:SetWordWrap(false)
                displayText:SetWordWrap(false)
                displayText:EnableMouse(true)

            ReplayFrame.buttons[i] = {frame = buttonFrame, text = displayText}
        end

        local npcModelFrame = CreateFrame("PlayerModel", "NPCModelFrame", ReplayFrame.displayFrame)
            npcModelFrame:SetSize(ReplayFrame.npcModelFrameWidth, ReplayFrame.displayFrame:GetHeight() - 15)
            npcModelFrame:SetPoint("LEFT", ReplayFrame.displayFrame, "LEFT", 5, 0)
            npcModelFrame:Hide()

            ReplayFrame.npcModelFrame = npcModelFrame
    else
        ReplayFrame:LoadFramePosition()
    end
end

function ReplayFrame:UpdateDisplayFrame()
    if (not ChattyLittleNpc.Voiceovers.currentlyPlaying or not ChattyLittleNpc.Voiceovers.currentlyPlaying.isPlaying) and (#ChattyLittleNpc.questsQueue == 0) then
        if ReplayFrame.displayFrame then
            ReplayFrame.displayFrame:Hide()
        end
        return
    end

    local firstButton = ReplayFrame.buttons[1]
    if not ChattyLittleNpc.Voiceovers.currentlyPlaying.title then
        ChattyLittleNpc.Voiceovers.currentlyPlaying.title = ChattyLittleNpc:GetTitleForQuestID(ChattyLittleNpc.Voiceovers.currentlyPlaying.questId)

        if ChattyLittleNpc.db.profile.debugMode then
            ChattyLittleNpc:Print("Getting missing title for quest id:", ChattyLittleNpc.Voiceovers.currentlyPlaying.questId, ", title found is:", ChattyLittleNpc.Voiceovers.currentlyPlaying.title)
        end
    end

    if ChattyLittleNpc.Voiceovers.currentlyPlaying and ChattyLittleNpc.Voiceovers.currentlyPlaying.title then
        local truncatedTitle = ChattyLittleNpc.Voiceovers.currentlyPlaying.title

        if string.len(ChattyLittleNpc.Voiceovers.currentlyPlaying.title) > 30 then
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
        local button = ReplayFrame.buttons[i + 1]
        local quest = ChattyLittleNpc.questsQueue[i]
        if button and quest and quest.title then
            local truncatedTitle = quest.title

            if string.len(quest.title) > 30 then
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
            if button then
                button.frame:Hide()
            end
        end
    end

    ReplayFrame.displayFrame:Show()
    ReplayFrame:CheckAndShowModel()
end

function ReplayFrame:ShowDisplayFrame()
    if (not ChattyLittleNpc.db.profile.showReplayFrame or
        ((ChattyLittleNpc.questsQueue and #ChattyLittleNpc.questsQueue == 0) and not ChattyLittleNpc.Voiceovers.currentlyPlaying))
        and ReplayFrame.displayFrame then
            ReplayFrame.displayFrame:Hide()
            return
    end

    ReplayFrame:CreateDisplayFrame()
    ReplayFrame:UpdateDisplayFrame()
end

function ReplayFrame:UpdateNpcModelDisplay(npcId)
    if not ReplayFrame.npcModelFrame then return end

    local currentlyPlaying = ChattyLittleNpc.Voiceovers.currentlyPlaying
    if not (currentlyPlaying and currentlyPlaying.isPlaying and currentlyPlaying.npcId == npcId) then
        ReplayFrame.npcModelFrame:Hide()
        ReplayFrame:ContractForNpcModel()
        return
    end

    local displayID = NpcDisplayIdDB[npcId]
    if displayID then
        ReplayFrame.npcModelFrame:ClearModel()
        ReplayFrame.npcModelFrame:SetDisplayInfo(displayID)
        ReplayFrame.npcModelFrame:SetPortraitZoom(0.75)
        ReplayFrame.npcModelFrame:SetRotation(0)
        ReplayFrame.npcModelFrame:Show()
        ReplayFrame:ExpandForNpcModel()
    else
        ReplayFrame.npcModelFrame:ClearModel()
        ReplayFrame.npcModelFrame:Hide()
        ReplayFrame:ContractForNpcModel()
    end
end

function ReplayFrame:CheckAndShowModel()
    local currentlyPlaying = ChattyLittleNpc.Voiceovers.currentlyPlaying
    if currentlyPlaying and currentlyPlaying.npcId and currentlyPlaying.isPlaying then
        ReplayFrame:UpdateNpcModelDisplay(currentlyPlaying.npcId)
    else
        if ReplayFrame.npcModelFrame then
            ReplayFrame.npcModelFrame:Hide()
        end
    end
end

function ReplayFrame:ExpandForNpcModel()
    local frame = self.displayFrame
    local newWidth = self.expandedWidth
    frame:SetWidth(newWidth)
end

function ReplayFrame:ContractForNpcModel()
    local frame = self.displayFrame
    local newWidth = self.normalWidth
    frame:SetWidth(newWidth)
end
