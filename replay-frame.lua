---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local ReplayFrame = {}
ReplayFrame.buttons = {}
ReplayFrame.questQueue = {}
ReplayFrame.currentPlayingQuest = nil -- Track the currently playing quest

ChattyLittleNpc.ReplayFrame = ReplayFrame

function ReplayFrame:AddQuestToQueue(questId, questTitle, questPhase, npcGender)
    if type(ReplayFrame.questQueue) ~= "table" then
        ReplayFrame.questQueue = {}
    end

    for _, quest in ipairs(ReplayFrame.questQueue) do
        if quest.id == questId and quest.phase == questPhase then
            return
        end
    end

    table.insert(ReplayFrame.questQueue, 1, { title = questTitle, id = questId, phase = questPhase, npcGender = npcGender })

    if #self.questQueue > 5 then
        table.remove(ReplayFrame.questQueue)
    end

    ReplayFrame:ShowDisplayFrame()
end

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
        ReplayFrame.displayFrame:SetSize(380, 210)  -- Initial size
        ReplayFrame:LoadFramePosition()
    
        ReplayFrame.displayFrame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
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

        ReplayFrame.displayFrame:SetScript("OnEnter", ReplayFrame:FadeInFrame(ReplayFrame.displayFrame))
        ReplayFrame.displayFrame:SetScript("OnLeave", ReplayFrame:FadeOutFrame(ReplayFrame.displayFrame))

        local closeButton = CreateFrame("Button", nil, ReplayFrame.displayFrame, "UIPanelCloseButton")
        closeButton:SetSize(20, 20)  -- Standard close button size
        closeButton:SetPoint("TOPRIGHT", ReplayFrame.displayFrame, "TOPRIGHT", -5, -5)
        closeButton:SetScript("OnClick", function()
            ReplayFrame.questQueue = {}
            ChattyLittleNpc:StopCurrentSound()
            ReplayFrame.displayFrame:Hide()
        end)

        for i = 1, 5 do
            local buttonFrame = CreateFrame("Frame", nil, ReplayFrame.displayFrame, "BackdropTemplate")
            buttonFrame:SetSize(370, 35)
            buttonFrame:SetPoint("TOP", ReplayFrame.displayFrame, "TOP", 0, -((i-1) * 40) - 40)
            buttonFrame:EnableMouse(true)
            buttonFrame:SetScript("OnEnter", ReplayFrame:FadeInFrame())
            buttonFrame:SetScript("OnLeave", ReplayFrame:FadeOutFrame())

            local stopButton = CreateFrame("Frame", nil, buttonFrame)
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
                ReplayFrame:FadeIdFrame(ReplayFrame.displayFrame)
            end)
            stopButton:SetScript("OnLeave", function()
                GameTooltip_Hide()
                ReplayFrame:FadeOutFrame(ReplayFrame.displayFrame)
            end)
            stopButton:SetScript("OnMouseDown", function()
                local quest = self.questQueue[i]
                if self.currentPlayingQuest == quest.id .. quest.phase then
                    ChattyLittleNpc:StopCurrentSound()
                end
                table.remove(ReplayFrame.questQueue, i)
                ReplayFrame:UpdateDisplayFrame()
                if #self.questQueue == 0 then
                    ReplayFrame.displayFrame:Hide()  -- Hide the frame if no quests are left
                end
            end)

            local replayButton = CreateFrame("Frame", nil, buttonFrame)
            replayButton:SetSize(12, 12)
            replayButton:SetPoint("LEFT", stopButton, "RIGHT", 5, 0)
            replayButton.texture = replayButton:CreateTexture(nil, "ARTWORK")
            replayButton.texture:SetAllPoints()
            replayButton.texture:SetTexture("Interface\\AddOns\\ChattyLittleNpc\\Textures\\Play.tga")
            replayButton:EnableMouse(true)
            replayButton:SetScript("OnEnter", function()
                GameTooltip:SetOwner(replayButton, "ANCHOR_RIGHT")
                GameTooltip:SetText("Play quest voiceover.")
                GameTooltip:Show()
                ReplayFrame:FadeInFrame(ReplayFrame.displayFrame)
            end)
            replayButton:SetScript("OnLeave", function()
                GameTooltip_Hide()
                ReplayFrame:FadeOutFrame(ReplayFrame.displayFrame)
            end)
            replayButton:SetScript("OnMouseDown", function()
                local quest = ReplayFrame.questQueue[i]
                if quest then
                    ReplayFrame.currentPlayingQuest = quest.title .. quest.phase
                    ChattyLittleNpc:PlayQuestSound(quest.id, quest.phase, quest.npcGender)
                    ReplayFrame:UpdateDisplayFrame()
                end
            end)

            local descButton = CreateFrame("Frame", nil, buttonFrame)
            descButton:SetSize(30, 30)
            descButton:SetPoint("LEFT", replayButton, "RIGHT", 0, 0)
            descButton.texture = descButton:CreateTexture(nil, "ARTWORK")
            descButton.texture:SetAllPoints()
            descButton.texture:SetTexture("Interface\\Common\\help-i")
            descButton:EnableMouse(true)
            descButton:SetScript("OnEnter", function()
                GameTooltip:SetOwner(descButton, "ANCHOR_RIGHT")
                GameTooltip:SetText("Play quest description voiceover (will add it to the list).")
                GameTooltip:Show()
                ReplayFrame:FadeInFrame(ReplayFrame.displayFrame)
            end)
            descButton:SetScript("OnLeave", function()
                GameTooltip_Hide()
                ReplayFrame:FadeOutFrame(ReplayFrame.displayFrame)
            end)
            descButton:SetScript("OnMouseDown", function()
                local quest = ReplayFrame.questQueue[i]
                if quest then
                    ReplayFrame.currentPlayingQuest = quest.title .. quest.phase
                    ChattyLittleNpc:PlayQuestSound(quest.id, "Desc", quest.npcGender)
                    ReplayFrame:UpdateDisplayFrame()
                end
            end)

            local displayText = buttonFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            displayText:SetPoint("LEFT", descButton, "RIGHT", 10, 0)
            displayText:SetJustifyH("LEFT")
            displayText:SetWordWrap(false)

            ReplayFrame.buttons[i] = {frame = buttonFrame, text = displayText}
        end
    else
        ReplayFrame:LoadFramePosition()
    end
end

function ReplayFrame:UpdateDisplayFrame()
    if self.questQueue and #self.questQueue == 0 then
        if ReplayFrame.displayFrame then
            ReplayFrame.displayFrame:Hide()
        end
        return
    end
    local numQuests = #self.questQueue
    local frameHeight = math.min(250, 40 + numQuests * 40)
    ReplayFrame.displayFrame:SetHeight(frameHeight)

    for i, button in ipairs(ReplayFrame.buttons) do
        local quest = ReplayFrame.questQueue[i]
        if quest then
            local truncatedTitle = quest.title
            if string.len(quest.title) > 40 then
                truncatedTitle = string.sub(quest.title, 1, 37) .. "..."
            end
            
            if ReplayFrame.currentPlayingQuest == quest.id .. quest.phase then
                button.text:SetText("-> " .. truncatedTitle)
            else
                button.text:SetText(truncatedTitle:gsub("-> ", ""))
            end

            button.frame:Show()

            -- Set up tooltip for full quest title
            button.text:SetScript("OnEnter", function()
                GameTooltip:SetOwner(button.frame, "ANCHOR_RIGHT")
                GameTooltip:SetText(quest.title)
                GameTooltip:Show()
                ReplayFrame:FadeInFrame(ReplayFrame.displayFrame)
            end)
            button.text:SetScript("OnLeave", function()
                GameTooltip_Hide()
                ReplayFrame:FadeOutFrame(ReplayFrame.displayFrame)
            end)
        else
            button.frame:Hide()
        end
    end
    ReplayFrame.displayFrame:Show()
end

function ReplayFrame:FadeInFrame(displayFrame)
    UIFrameFadeIn(displayFrame, 0.5, ReplayFrame.displayFrame:GetAlpha(), 1)
end

function ReplayFrame:FadeOutFrame(displayFrame)
    UIFrameFadeOut(displayFrame, 0.5, ReplayFrame.displayFrame:GetAlpha(), 0.3)
end

function ReplayFrame:ShowDisplayFrame()
    if self.questQueue and #self.questQueue == 0 then
        ReplayFrame.displayFrame:Hide()
        return
    end
    ReplayFrame:CreateDisplayFrame()
    ReplayFrame:UpdateDisplayFrame()
end
