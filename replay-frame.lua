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

        -- Dynamically create up to 5 buttons but hide unused ones
        for i = 1, 5 do
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
                        questIndex = questIndex - 1
                        table.remove(ChattyLittleNpc.questsQueue, questIndex)
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
    local tempQueue = {}

    if (not ChattyLittleNpc.Voiceovers.currentlyPlaying or ChattyLittleNpc.Voiceovers.currentlyPlaying.finishedPlaying) then
        if self.displayFrame then
            self.displayFrame:Hide()
        end

        return
    end

    -- Add currently playing quest to the top if it exists
    if ChattyLittleNpc.Voiceovers.currentlyPlaying and ChattyLittleNpc.Voiceovers.currentlyPlaying.questId then
        table.insert(tempQueue, 1, {
            title = ChattyLittleNpc.Voiceovers.currentlyPlaying.title,
            questId = ChattyLittleNpc.Voiceovers.currentlyPlaying.questId,
            phase = ChattyLittleNpc.Voiceovers.currentlyPlaying.phase,
            npcGender = ChattyLittleNpc.Voiceovers.currentlyPlaying.gender,
            isPlaying = true -- flag to identify the currently playing quest
        })
    end

    -- Add the rest of the queued quests
    for _, quest in ipairs(ChattyLittleNpc.questsQueue) do
        table.insert(tempQueue, quest)
    end

    -- Calculate frame height based on the number of quests
    local numQuests = math.min(#tempQueue, 5)
    local frameHeight = 40 + numQuests * 40
    ReplayFrame.displayFrame:SetHeight(frameHeight)

    -- Update display buttons based on the temp queue
    for i, button in ipairs(ReplayFrame.buttons) do
        local quest = tempQueue[i]
        if quest then
            local title = quest.title or ""
            local truncatedTitle = title

            -- truncate quest title if its too long (show full title on hover over)
            if string.len(title) > 30 then
                truncatedTitle = string.sub(title, 1, 25) .. "..."
            end

            if quest.isPlaying then
                button.text:SetText("-> " .. truncatedTitle) -- Highlight the currently playing quest
            else
                button.text:SetText(truncatedTitle)
            end

            button.frame:Show()

            -- Tooltip for full quest title
            button.text:SetScript("OnEnter", function()
                GameTooltip:SetOwner(button.frame, "ANCHOR_RIGHT")
                GameTooltip:SetText(title)
                GameTooltip:Show()
            end)
            button.text:SetScript("OnLeave", function()
                GameTooltip_Hide()
            end)
        else
            button.frame:Hide()
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
