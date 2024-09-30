---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local ReplayFrame = {}
ReplayFrame.buttons = {}

ChattyLittleNpc.ReplayFrame = ReplayFrame

function ReplayFrame:SaveFramePosition()
    local point, relativeTo, relativePoint, xOfs, yOfs = ReplayFrame.displayFrame:GetPoint()
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
        ReplayFrame.displayFrame:ClearAllPoints()
        ReplayFrame.displayFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        ReplayFrame.displayFrame:SetPoint("CENTER", UIParent, "CENTER", 500, 0)
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
        ReplayFrame.displayFrame = CreateFrame("Frame", "ChattyLittleNpcDisplayFrame", UIParent, "BackdropTemplate")
        ReplayFrame.displayFrame:SetSize(310, 210)  -- Initial size
        ReplayFrame:LoadFramePosition()

        ReplayFrame.displayFrame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        UIFrameFadeIn(ReplayFrame.displayFrame, 0.5, ReplayFrame.displayFrame:GetAlpha(), 0.5)
        ReplayFrame.displayFrame:SetBackdropColor(0, 0, 0, 0.3)
        ReplayFrame.displayFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
        ReplayFrame.displayFrame:SetMovable(true)
        ReplayFrame.displayFrame:EnableMouse(true)
        ReplayFrame.displayFrame:RegisterForDrag("LeftButton")
        ReplayFrame.displayFrame:SetScript("OnDragStart", ReplayFrame.displayFrame.StartMoving)
        ReplayFrame.displayFrame:SetScript("OnDragStop", function(frame)
            frame:StopMovingOrSizing()
            ReplayFrame:SaveFramePosition()
        end)

        local function fadeInFrame()
            UIFrameFadeIn(ReplayFrame.displayFrame, 0.5, ReplayFrame.displayFrame:GetAlpha(), 1)
        end

        local function fadeOutFrame()
            UIFrameFadeOut(ReplayFrame.displayFrame, 0.5, ReplayFrame.displayFrame:GetAlpha(), 0.5)
        end

        ReplayFrame.displayFrame:SetScript("OnEnter", fadeInFrame)
        ReplayFrame.displayFrame:SetScript("OnLeave", fadeOutFrame)

        -- CLOSE BUTTON
        local closeButton = CreateFrame("Button", nil, ReplayFrame.displayFrame, "UIPanelCloseButton")
        closeButton:SetSize(20, 20)  -- Standard close button size
        closeButton:SetPoint("TOPRIGHT", ReplayFrame.displayFrame, "TOPRIGHT", -5, -5)
        closeButton:SetScript("OnClick", function()
            ChattyLittleNpc.questsQueue = {}
            ChattyLittleNpc.Voiceovers:ForceStopCurrentSound(true)
            ReplayFrame.displayFrame:Hide()
        end)

        -- Dynamically create up to 11 buttons (1 for currently playing quest and 10 for queued quests)
        for i = 1, 11 do
            -- BUTTON FRAME
            local buttonFrame = CreateFrame("Frame", nil, ReplayFrame.displayFrame, "BackdropTemplate")
            buttonFrame:SetSize(280, 35)
            buttonFrame:SetPoint("TOP", ReplayFrame.displayFrame, "TOP", 0, -((i - 1) * 40) - 40)
            buttonFrame:EnableMouse(true)
            buttonFrame:SetScript("OnEnter", fadeInFrame)
            buttonFrame:SetScript("OnLeave", fadeOutFrame)

            -- STOP BUTTON
            local stopButton = CreateFrame("Button", nil, buttonFrame)
            stopButton:SetSize(12, 12)
            stopButton:SetPoint("LEFT", 5, 0)
            stopButton.texture = stopButton:CreateTexture(nil, "ARTWORK")
            stopButton.texture:SetAllPoints()
            stopButton.texture:SetTexture("Interface\\Buttons\\UI-StopButton")
            stopButton:EnableMouse(true)
            stopButton:SetScript("OnEnter", function()
                GameTooltip:SetOwner(stopButton, "ANCHOR_RIGHT")
                GameTooltip:SetText("Stop and remove quest voiceover from list.")
                GameTooltip:Show()
                fadeInFrame()
            end)
            stopButton:SetScript("OnLeave", function()
                GameTooltip_Hide()
                fadeOutFrame()
            end)

            stopButton:SetScript("OnMouseDown", function()
                local questIndex = i

                -- Check if it's the currently playing quest
                if questIndex == 1 and ChattyLittleNpc.Voiceovers.currentlyPlaying then
                    ChattyLittleNpc.Voiceovers:ForceStopCurrentSound(false) -- Use false to not clear the queue
                else
                    table.remove(ChattyLittleNpc.questsQueue, questIndex - 1)
                end

                ReplayFrame:UpdateDisplayFrame()

                if #ChattyLittleNpc.questsQueue == 0 and not ChattyLittleNpc.Voiceovers.currentlyPlaying then
                    ReplayFrame.displayFrame:Hide()
                end
            end)

            local displayText = buttonFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            displayText:SetPoint("LEFT", stopButton, "RIGHT", 10, 0)
            displayText:SetJustifyH("LEFT")
            displayText:SetWordWrap(false)
            displayText:EnableMouse(true)
            displayText:SetScript("OnEnter", fadeInFrame)
            displayText:SetScript("OnLeave", fadeOutFrame)

            ReplayFrame.buttons[i] = {frame = buttonFrame, text = displayText}
        end
    else
        ReplayFrame:LoadFramePosition()
    end
end

function ReplayFrame:UpdateDisplayFrame()
    if (not ChattyLittleNpc.Voiceovers.currentlyPlaying or not ChattyLittleNpc.Voiceovers.currentlyPlaying.isPlaying) and (#ChattyLittleNpc.questsQueue == 0) then
        if self.displayFrame then
            self.displayFrame:Hide()
        end
        return
    end

    -- Calculate frame height based on the number of quests
    local numQuests = math.min(#ChattyLittleNpc.questsQueue, 10)
    local frameHeight = 40 + (numQuests + 1) * 40 -- +1 for the currently playing quest
    ReplayFrame.displayFrame:SetHeight(frameHeight)

    -- Update display button for the currently playing quest
    local currentlyPlayingQuest = ChattyLittleNpc.Voiceovers.currentlyPlaying
    local firstButton = ReplayFrame.buttons[1]
    if currentlyPlayingQuest and currentlyPlayingQuest.title then
        local truncatedTitle = currentlyPlayingQuest.title

        -- Truncate quest title if it's too long (show full title on hover over)
        if string.len(currentlyPlayingQuest.title) > 30 then
            truncatedTitle = string.sub(currentlyPlayingQuest.title, 1, 25) .. "..."
        end

        firstButton.text:SetText("-> " .. truncatedTitle) -- Highlight the currently playing quest
        firstButton.frame:Show()

        -- Tooltip for full quest title
        firstButton.text:SetScript("OnEnter", function()
            GameTooltip:SetOwner(firstButton.frame, "ANCHOR_RIGHT")
            GameTooltip:SetText(currentlyPlayingQuest.title)
            GameTooltip:Show()
        end)
        firstButton.text:SetScript("OnLeave", function()
            GameTooltip_Hide()
        end)
    else
        firstButton.frame:Hide()
    end

    -- Update display buttons for the queued quests
    for i = 1, 10 do
        local button = ReplayFrame.buttons[i + 1] -- Start from the second button
        local quest = ChattyLittleNpc.questsQueue[i]
        if button and quest and quest.title then
            local truncatedTitle = quest.title

            -- Truncate quest title if it's too long (show full title on hover over)
            if string.len(quest.title) > 30 then
                truncatedTitle = string.sub(quest.title, 1, 25) .. "..."
            end

            button.text:SetText(truncatedTitle)
            button.frame:Show()

            -- Tooltip for full quest title
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
end

function ReplayFrame:ShowDisplayFrame()
    -- Hide frame if no items in queue or queue displayFrame is turned off.
    if (not ChattyLittleNpc.db.profile.showReplayFrame or
        ((ChattyLittleNpc.questsQueue and #ChattyLittleNpc.questsQueue == 0) and not ChattyLittleNpc.Voiceovers.currentlyPlaying))
        and ReplayFrame.displayFrame then
            ReplayFrame.displayFrame:Hide()
            return
    end

    ReplayFrame:CreateDisplayFrame()
    ReplayFrame:UpdateDisplayFrame()
end

-- Create the main frame
local npcModelFrame = CreateFrame("PlayerModel", "NPCModelFrame", UIParent)
npcModelFrame:SetSize(100, 100)
npcModelFrame:SetPoint("CENTER", UIParent, "CENTER", 100, 0) -- Move the model a bit to the right


-- Function to update the model display based on NPC ID
function ChattyLittleNpc:UpdateNpcModelDisplay(npcId)
    local displayID = NpcDisplayIdDB[npcId]
    if displayID then
        npcModelFrame:ClearModel()
        npcModelFrame:SetDisplayInfo(displayID)
        npcModelFrame:SetPosition(0, 0, -0.2)
        npcModelFrame:SetRotation(math.rad(30))
        npcModelFrame:SetCamDistanceScale(0.5)
        npcModelFrame:SetPortraitZoom(0.6)
        npcModelFrame:Show()
    else
        npcModelFrame:ClearModel()
        npcModelFrame:Hide()
    end
end

-- Function to check and show the model if a voiceover is currently playing
function ChattyLittleNpc:CheckAndShowModel()
    local currentlyPlaying = self.Voiceovers.currentlyPlaying
    if currentlyPlaying and currentlyPlaying.npcId and currentlyPlaying.isPlaying then
        self:UpdateNpcModelDisplay(currentlyPlaying.npcId)
    else
        npcModelFrame:Hide() -- Hide the model if no voiceover is playing
    end
end